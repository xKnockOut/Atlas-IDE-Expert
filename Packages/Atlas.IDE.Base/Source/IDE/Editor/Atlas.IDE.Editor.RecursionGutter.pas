unit Atlas.IDE.Editor.RecursionGutter;

// Rekursionssymbole im Editorrand (#623) als Schicht der gemeinsamen
// Zeichenschicht TAtlasIdeGutterMarks:
// - Abruf: Ein Zeitgeber prüft den oberen Editor. Nach einer Tipp-Pause fragt
//   er atlas.server.recursion mit der Datei und der Tiefe
//   (editor.recursionMarkers.depth), nur, wenn der Server ohnehin läuft, und
//   merkt sich die Antwort je Datei, Textstand und Tiefe. Der Befehl läuft im
//   Hintergrund (TAtlasLensPoll.AskAsync); vorher wartete der Hauptthread alle
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
    Command = 'atlas.server.recursion';
  private const
    QuietMs = 700;
    // Im Hintergrund: Ein langsamer Server hält nur die Symbole auf, nicht die IDE.
    TimeoutMs = 5000;
    RetryMs = 5000;
    // Gleicher Stand und gleiche Tiefe: nie neu fragen.
    RefreshMs = High(Cardinal);
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
  System.Generics.Collections,
  System.Math,
  ToolsAPI,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings;

function IsSource(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := ExtractFileExt(AFileName);
  Result := SameText(Extension, '.pas') or SameText(Extension, '.dpr') or SameText(Extension, '.dpk');
end;

{ TAtlasIdeRecursionGutter }

constructor TAtlasIdeRecursionGutter.Create(const ASession: TAtlasRecursionSessionFunc;
  const ARun: TAtlasLensCommandProc);
begin
  inherited Create;
  FSession := ASession;
  FRun := ARun;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
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
  Result := TAtlasIdeSettings.RecursionMarkersOn;
end;

procedure TAtlasIdeRecursionGutter.Clear;
var
  Had: Boolean;
begin
  Had := FMarks.HasCalls;
  FMarks := Default(TAtlasFileRecursion);
  FPoll.Forget;
  if Had then
  begin
    TAtlasIdeGutterMarks.Invalidate;
  end;
end;

/// <summary>Oberer Editor mit einer Pascal-Quelle, sonst nil.</summary>
function TopSourceView: IOTAEditView;
var
  mEditors: IOTAEditorServices;
begin
  Result := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    Result := mEditors.TopView;
  end;
  if (Result <> nil) and ((Result.Buffer = nil) or not IsSource(Result.Buffer.FileName)) then
  begin
    Result := nil;
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
    mView := TopSourceView;
    if mView = nil then
    begin
      Exit;
    end;
    mDepth := TAtlasIdeSettings.RecursionMarkersDepth;
    // Andere Tiefe: der geholte Stand gilt nicht mehr.
    if (mDepth <> FFetchedDepth) and (FPoll.FetchedFile <> '') then
    begin
      Clear;
    end;
    if FPoll.Due(mView, QuietMs, RefreshMs) then
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
  FPoll.AskAsync(FSession(), FRun, Feature, Command, mArguments, RetryMs, TimeoutMs, Answer(ADepth));
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
  if not FPoll.Answered(AAnswer, RetryMs) then
  begin
    Exit;
  end;
  FFetchedDepth := ADepth;
  FMarks := TAtlasFileRecursion.FromJson(AAnswer);
  TAtlasIdeGutterMarks.Invalidate;
end;

procedure TAtlasIdeRecursionGutter.Track(const AFileName, AText: string; AOpened: Boolean);
begin
  // Der eigene Zeitgeber fragt den Server; hier gibt es nichts zu verankern.
end;

function TAtlasIdeRecursionGutter.HasMarks(const AFileName: string): Boolean;
begin
  Result := SameText(AFileName, FPoll.FetchedFile) and FMarks.HasCalls;
end;

function TAtlasIdeRecursionGutter.CallsAt(const AFileName: string; ALine: Integer): TArray<TAtlasRecursionCall>;
begin
  Result := nil;
  if SameText(AFileName, FPoll.FetchedFile) then
  begin
    Result := FMarks.CallsAt(ALine);
  end;
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
var
  Size, Left, Top, Head: Integer;
  Box: TRect;
begin
  // Kreispfeil (↻): Dreiviertelbogen im Uhrzeigersinn, Spitze oben rechts, in der Warnfarbe.
  Size := Min(AIcon.Width, AIcon.Height);
  Left := AIcon.Left + (AIcon.Width - Size) div 2;
  Top := AIcon.Top + (AIcon.Height - Size) div 2;
  Box := TRect.Create(Left + 1, Top + 1, Left + Size - 1, Top + Size - 1);
  ACanvas.Brush.Style := bsClear;
  ACanvas.Pen.Color := TColor(TAtlasColorMath.Mix(AColors.Warn, ABack, 0.9));
  ACanvas.Pen.Width := Max(1, Size div 8);
  // Arc läuft gegen den Uhrzeigersinn vom Start- zum Endpunkt: von oben rechts über links bis oben.
  ACanvas.Arc(Box.Left, Box.Top, Box.Right, Box.Bottom, Box.Right, Box.Top + Box.Height div 3,
    Box.Left + Box.Width div 2, Box.Top);
  Head := Max(2, Size div 3);
  ACanvas.Pen.Width := 1;
  ACanvas.Brush.Style := bsSolid;
  ACanvas.Brush.Color := ACanvas.Pen.Color;
  ACanvas.Polygon([Point(Box.Right, Box.Top + Box.Height div 3 + 1),
    Point(Box.Right - Head, Box.Top + Box.Height div 3 - Head div 2),
    Point(Box.Right + 1, Box.Top + Box.Height div 3 - Head)]);
end;

function TAtlasIdeRecursionGutter.TipText(const AFileName: string; ALine: Integer;
  out ATitle, AText: string): Boolean;
var
  Calls: TArray<TAtlasRecursionCall>;
begin
  Calls := CallsAt(AFileName, ALine);
  TAtlasRecursionMarks.TipText(Calls, TAtlasStrings.Text(TAtlasTextId.RecursionTipDirect),
    TAtlasStrings.Text(TAtlasTextId.RecursionTipChain), ATitle, AText);
  Result := Length(Calls) > 0;
end;

function TAtlasIdeRecursionGutter.TipLinks(const AFileName: string; ALine: Integer): TArray<string>;
var
  Step: TAtlasRecursionStep;
begin
  Result := nil;
  for Step in TAtlasRecursionMarks.Links(CallsAt(AFileName, ALine)) do
  begin
    Result := Result + [Step.Name];
  end;
end;

procedure TAtlasIdeRecursionGutter.OpenLink(const AFileName: string; ALine, AIndex: Integer);
var
  Links: TArray<TAtlasRecursionStep>;
begin
  Links := TAtlasRecursionMarks.Links(CallsAt(AFileName, ALine));
  if (AIndex >= 0) and (AIndex <= High(Links)) then
  begin
    TAtlasIdeNavigation.GoToLocation(AFileName, Links[AIndex].Line, Links[AIndex].Character);
  end;
end;

end.
