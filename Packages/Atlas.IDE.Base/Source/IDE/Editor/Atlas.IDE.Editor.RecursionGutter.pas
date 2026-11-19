unit Atlas.IDE.Editor.RecursionGutter;

// Rekursionssymbole im Editorrand (#623) als Schicht der gemeinsamen
// Zeichenschicht TAtlasIdeGutterMarks:
// - Abruf: Ein Zeitgeber prüft den oberen Editor. Nach einer Tipp-Pause fragt
//   er atlas.server.recursion mit der Datei und der Tiefe
//   (editor.recursionMarkers.depth), nur, wenn der Server ohnehin läuft, und
//   merkt sich die Antwort je Datei, Textstand und Tiefe. Der Befehl läuft im
//   Hintergrund (TAtlasLensPoll.AskAsync); sonst wartete der Hauptthread alle
//   250 ms bis zu 800 ms auf den Server.
// - Symbol: ein Kreispfeil (↻) neben jeder Zeile mit einem Aufruf, der über
//   höchstens „Tiefe“ Methoden derselben Unit zur aufrufenden zurückführt;
//   nur, solange die Zeile noch den Text vom Abruf hat.
// - Tooltip: „Rekursion: ruft sich selbst auf“ bzw. „Rekursion über n
//   Methoden“, darunter die Kette und je Methode ein Link, der zu ihr springt.
// Abschaltbar über die Einstellung „Rekursionssymbole“ (editor.recursionMarkers,
// auch als Schnellschalter) und am Element (#628); Sicherung über
// TAtlasFeature.RecursionMarkers (#493). Die Property-Falle meldet der Server als
// Befund der Regel setter-recursion.

interface

uses
  System.SysUtils,
  System.Types,
  System.JSON,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.Recursion,
  Atlas.Core.Lsp.Session,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Editor.Lens;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasRecursionSessionFunc = reference to function: TLspSession;

  TAtlasIdeRecursionGutter = class(TAtlasGutterLayer)
  public const
    cCommand = 'atlas.server.recursion';
  private const
    cQuietMs = 700;
    // Im Hintergrund: Ein langsamer Server hält nur die Symbole auf, nicht die IDE.
    cTimeoutMs = 5000;
    cRetryMs = 5000;
    // Gleicher Stand und gleiche Tiefe: nie neu fragen.
    cRefreshMs = High(Cardinal);
  private
    FSession: TAtlasRecursionSessionFunc;
    FRun: TAtlasLensCommandProc;
    FTimer: TTimer;
    /// <summary>Abruf; FPoll.FetchedFile und FetchedText sind der Stand, zu dem FMarks gehört.</summary>
    FPoll: TAtlasLensPoll;
    FFetchedDepth: Integer;
    FMarks: TAtlasFileRecursion;
    procedure Tick(Sender: TObject);
    procedure Fetch(ADepth: Integer);
    function Answer(ADepth: Integer): TProc<TJSONValue>;
    procedure Take(AAnswer: TJSONValue; ADepth: Integer);
    procedure Clear;
    function CallsAt(const AFileName: string; ALine: Integer): TArray<TAtlasRecursionCall>;
  public
    /// <summary>ASession für den Textstand, ARun für den Befehl im Hintergrund.</summary>
    constructor Create(const ASession: TAtlasRecursionSessionFunc; const ARun: TAtlasLensCommandProc);
    destructor Destroy; override;
    function Feature: TAtlasFeature; override;
    function Element: TAtlasDrawnElement; override;
    function Wanted: Boolean; override;
    procedure Track(const AFileName, AText: string; AOpened: Boolean); override;
    function HasMarks(const AFileName: string): Boolean; override;
    function MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
      AHasText: Boolean): Boolean; override;
    procedure PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
      ABack: TAtlasColor); override;
    function TipText(const AFileName: string; ALine: Integer; out ATitle, AText: string): Boolean; override;
    function TipLinks(const AFileName: string; ALine: Integer): TArray<string>; override;
    procedure OpenLink(const AFileName: string; ALine, AIndex: Integer); override;
  end;

implementation

uses
  Atlas.Core.Editor.SourceFiles,
  System.Generics.Collections,
  System.Math,
  ToolsAPI,
  Atlas.UI.Editor.Strings,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.EditorSettings,
  Atlas.IDE.Foundation.EditorBuffer;

{ TAtlasIdeRecursionGutter }

constructor TAtlasIdeRecursionGutter.Create(const ASession: TAtlasRecursionSessionFunc;
  const ARun: TAtlasLensCommandProc);
const
  cTickMs = 250;
begin
  inherited Create;
  FSession := ASession;
  FRun := ARun;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeRecursionGutter.Destroy;
begin
  FTimer.Free;
  // Eine ausstehende Antwort erreicht die Schicht nicht mehr.
  FPoll.Close;
  inherited Destroy;
end;

function TAtlasIdeRecursionGutter.Feature: TAtlasFeature;
begin
  Result := TAtlasFeature.RecursionMarkers;
end;

function TAtlasIdeRecursionGutter.Element: TAtlasDrawnElement;
begin
  Result := TAtlasDrawnElement.Recursion;
end;

function TAtlasIdeRecursionGutter.Wanted: Boolean;
begin
  Result := TAtlasIdeEditorSettings.RecursionMarkersOn;
end;

procedure TAtlasIdeRecursionGutter.Track(const AFileName, AText: string; AOpened: Boolean);
begin
  // Der eigene Zeitgeber fragt den Server; hier gibt es nichts zu verankern.
end;

/// <summary>Oberer Editor mit einer Pascal-Quelle, sonst nil.</summary>
function TopCompiledView: IOTAEditView;
begin
  Result := TAtlasEditorBuffer.TopSourceView;
  if (Result <> nil) and not TAtlasSourceFiles.IsCompiled(Result.Buffer.FileName) then
  begin
    Result := nil;
  end;
end;

function TAtlasIdeRecursionGutter.HasMarks(const AFileName: string): Boolean;
begin
  Result := SameText(AFileName, FPoll.FetchedFile) and FMarks.HasCalls;
end;

function TAtlasIdeRecursionGutter.MarkAt(const AFileName: string; ALine: Integer; const ALineText: string;
  AHasText: Boolean): Boolean;
begin
  Result := Length(CallsAt(AFileName, ALine)) > 0;
  // Zeile seit dem Abruf geändert: Das Symbol wartet auf die nächste Antwort.
  if Result and AHasText then
  begin
    Result := TAtlasRecursionMarks.LineMatches(ALineText, TAtlasRecursionMarks.LineOf(FPoll.FetchedText, ALine));
  end;
end;

procedure TAtlasIdeRecursionGutter.PaintIcon(ACanvas: TCanvas; const AIcon: TRect; const AColors: TAtlasColors;
  ABack: TAtlasColor);
const
  cArrowTone = 0.9;
  cPenDivisor = 8;
  cThirds = 3;
var
  mSize, mLeft, mTop, mHead: Integer;
  mBox: TRect;
begin
  // Kreispfeil (↻): Dreiviertelbogen im Uhrzeigersinn, Spitze oben rechts, in der Warnfarbe.
  mSize := Min(AIcon.Width, AIcon.Height);
  mLeft := AIcon.Left + (AIcon.Width - mSize) div 2;
  mTop := AIcon.Top + (AIcon.Height - mSize) div 2;
  mBox := TRect.Create(mLeft + 1, mTop + 1, mLeft + mSize - 1, mTop + mSize - 1);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := TColor(TAtlasColorMath.Mix(AColors.Warn, ABack, cArrowTone));
  ACanvas.Pen.Width := Max(1, mSize div cPenDivisor);
  // Arc läuft gegen den Uhrzeigersinn vom Start- zum Endpunkt: von oben rechts über links bis oben.
  ACanvas.Arc(mBox.Left, mBox.Top, mBox.Right, mBox.Bottom, mBox.Right, mBox.Top + mBox.Height div cThirds,
    mBox.Left + mBox.Width div 2, mBox.Top);
  mHead := Max(2, mSize div cThirds);
  ACanvas.Pen.Width := 1;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := ACanvas.Pen.Color;
  ACanvas.Polygon([Point(mBox.Right, mBox.Top + mBox.Height div cThirds + 1),
    Point(mBox.Right - mHead, mBox.Top + mBox.Height div cThirds - mHead div 2),
    Point(mBox.Right + 1, mBox.Top + mBox.Height div cThirds - mHead)]);
end;

function TAtlasIdeRecursionGutter.TipText(const AFileName: string; ALine: Integer;
  out ATitle, AText: string): Boolean;
var
  mCalls: TArray<TAtlasRecursionCall>;
begin
  mCalls := CallsAt(AFileName, ALine);
  TAtlasRecursionMarks.TipText(mCalls, TAtlasEditorStrings.Text(TAtlasEditorTextId.RecursionTipDirect),
    TAtlasEditorStrings.Text(TAtlasEditorTextId.RecursionTipChain), ATitle, AText);
  Result := Length(mCalls) > 0;
end;

function TAtlasIdeRecursionGutter.TipLinks(const AFileName: string; ALine: Integer): TArray<string>;
var
  mStep: TAtlasRecursionStep;
begin
  Result := nil;
  for mStep in TAtlasRecursionMarks.Links(CallsAt(AFileName, ALine)) do
  begin
    Result := Result + [mStep.Name];
  end;
end;

procedure TAtlasIdeRecursionGutter.OpenLink(const AFileName: string; ALine, AIndex: Integer);
var
  mLinks: TArray<TAtlasRecursionStep>;
begin
  mLinks := TAtlasRecursionMarks.Links(CallsAt(AFileName, ALine));
  if (AIndex >= 0) and (AIndex <= High(mLinks)) then
  begin
    TAtlasIdeNavigation.GoToLocation(AFileName, mLinks[AIndex].Line, mLinks[AIndex].Character);
  end;
end;

procedure TAtlasIdeRecursionGutter.Tick(Sender: TObject);
var
  mView: IOTAEditView;
  mDepth: Integer;
begin
  try
    if not Wanted or TAtlasGuard.Disabled(Feature) then
    begin
      Clear;
      Exit;
    end;
    mView := TopCompiledView;
    if mView = nil then
    begin
      Exit;
    end;
    mDepth := TAtlasIdeEditorSettings.RecursionMarkersDepth;
    // Andere Tiefe: der geholte Stand gilt nicht mehr.
    if (mDepth <> FFetchedDepth) and (FPoll.FetchedFile <> '') then
    begin
      Clear;
    end;
    if FPoll.Due(mView, cQuietMs, cRefreshMs) then
    begin
      Fetch(mDepth);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(Feature, E);
  end;
end;

procedure TAtlasIdeRecursionGutter.Fetch(ADepth: Integer);
var
  mValues: TJSONArray;
  mArguments: string;
begin
  mValues := TJSONArray.Create;
  try
    mValues.Add(TLspSession.PathToUri(FPoll.FileName));
    mValues.Add(ADepth);
    mArguments := mValues.ToJSON;
  finally
    mValues.Free;
  end;
  FPoll.AskAsync(FSession(), FRun, Feature, TAtlasLensRequest.Create(cCommand, mArguments, cTimeoutMs), cRetryMs,
    Answer(ADepth));
end;

function TAtlasIdeRecursionGutter.Answer(ADepth: Integer): TProc<TJSONValue>;
begin
  Result :=
    procedure(AAnswer: TJSONValue)
    begin
      Take(AAnswer, ADepth);
    end;
end;

procedure TAtlasIdeRecursionGutter.Take(AAnswer: TJSONValue; ADepth: Integer);
begin
  // Den Wert gibt der Manager frei.
  if not FPoll.Answered(AAnswer, cRetryMs) then
  begin
    Exit;
  end;
  FFetchedDepth := ADepth;
  FMarks := TAtlasFileRecursion.FromJson(AAnswer);
  TAtlasIdeGutterMarks.Invalidate;
end;

procedure TAtlasIdeRecursionGutter.Clear;
var
  mHad: Boolean;
begin
  mHad := FMarks.HasCalls;
  FMarks := Default(TAtlasFileRecursion);
  FPoll.Forget;
  if mHad then
  begin
    TAtlasIdeGutterMarks.Invalidate;
  end;
end;

function TAtlasIdeRecursionGutter.CallsAt(const AFileName: string; ALine: Integer): TArray<TAtlasRecursionCall>;
begin
  Result := nil;
  if SameText(AFileName, FPoll.FetchedFile) then
  begin
    Result := FMarks.CallsAt(ALine);
  end;
end;

end.
