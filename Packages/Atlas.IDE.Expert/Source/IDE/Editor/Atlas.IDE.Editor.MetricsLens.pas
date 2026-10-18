unit Atlas.IDE.Editor.MetricsLens;

// Code Lens mit Code-Metriken (#66): Länge, Verschachtelungstiefe,
// zyklomatische und kognitive Komplexität und Parameteranzahl je Methode.
// - Abruf: Ein Zeitgeber prüft den oberen Editor. Nach einer Tipp-Pause fragt
//   er atlas.server.metrics für die Datei (nur, wenn der Server ohnehin läuft)
//   und merkt sich die Antwort je Datei und Textstand. Ohne Änderung fragt er
//   alle RefreshMs neu (geänderte Grenzwerte in atlas.json).
// - Zeichnen: hinter dem Ende der Kopfzeile jeder implementierten Methode
//   (plsEndPaint) eine Marke mit den Werten; ein Wert über dem Grenzwert ist
//   markiert und die Marke in der Warnfarbe. Die IDE kann keine eigene Zeile
//   über der Methode einfügen, darum steht die Lens hinter dem Kopf.
// - Kein Klickziel: Die Werte sind Information; die Regeln metric-* melden
//   Überschreitungen als Problem.
// Abschaltbar über die Einstellung „Code Lens mit Code-Metriken“
// (codeLens.metrics, auch als Schnellschalter); die Server-Einstellung
// codeLens.metrics in settings.json schaltet sie ebenfalls ab. Ausblenden am
// Element (#628): je Methode („Nur hier“, Anker = Name der Methode) oder je
// Datei über .atlas.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Vcl.ExtCtrls,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.Metrics;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasMetricsLensSessionFunc = reference to function: TLspSession;

  TAtlasEditorMetricsLens = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  private const
    QuietMs = 700;
    TimeoutMs = 800;
    RetryMs = 5000;
    RefreshMs = 30000;
  private
    FSession: TAtlasMetricsLensSessionFunc;
    FTimer: TTimer;
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FFileName: string;
    FText: string;
    FChangedAt: Cardinal;
    FFetchedAt: Cardinal;
    FRetryAt: Cardinal;
    /// <summary>Textstand, zu dem FMetrics gehört; '' wenn keiner.</summary>
    FFetchedText: string;
    FFetchedFile: string;
    FMetrics: TAtlasFileMetrics;
    FFormats: TAtlasMetricFormats;
    FShowing: Boolean;
    procedure Tick(Sender: TObject);
    procedure Fetch;
    procedure Clear;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class procedure Invalidate; static;
    class function Formats: TAtlasMetricFormats; static;
  public
    constructor Create(const ASession: TAtlasMetricsLensSessionFunc);
    destructor Destroy; override;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.JSON,
  Vcl.Graphics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Pairs,
  Atlas.UI.Strings,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements;

const
  MetricsCommand = 'atlas.server.metrics';

{ TAtlasEditorMetricsLens.TEvents }

function TAtlasEditorMetricsLens.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasEditorMetricsLens.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasEditorMetricsLens }

constructor TAtlasEditorMetricsLens.Create(const ASession: TAtlasMetricsLensSessionFunc);
var
  Services: INTACodeEditorServices;
begin
  inherited Create;
  FSession := ASession;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasEditorMetricsLens.Destroy;
var
  Services: INTACodeEditorServices;
begin
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.RemoveEditorEventsNotifier(FIndex);
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

class procedure TAtlasEditorMetricsLens.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
    Services.InvalidateTopEditor;
end;

class function TAtlasEditorMetricsLens.Formats: TAtlasMetricFormats;
begin
  Result[TAtlasMetric.MethodLength] := TAtlasStrings.Text(TAtlasTextId.MetricsLensLines);
  Result[TAtlasMetric.Nesting] := TAtlasStrings.Text(TAtlasTextId.MetricsLensDepth);
  Result[TAtlasMetric.Cyclomatic] := TAtlasStrings.Text(TAtlasTextId.MetricsLensCyclomatic);
  Result[TAtlasMetric.Cognitive] := TAtlasStrings.Text(TAtlasTextId.MetricsLensCognitive);
  Result[TAtlasMetric.Parameters] := TAtlasStrings.Text(TAtlasTextId.MetricsLensParameters);
end;

function Wanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.Metrics and ASettings.CodeLensMetrics and
    not TAtlasGuard.Disabled(TAtlasFeature.EditorCommands);
end;

function IsSource(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := ExtractFileExt(AFileName);
  Result := SameText(Extension, '.pas') or SameText(Extension, '.dpr') or SameText(Extension, '.dpk');
end;

procedure TAtlasEditorMetricsLens.Clear;
begin
  FMetrics := Default(TAtlasFileMetrics);
  FMetrics.Methods := nil;
  FFetchedText := '';
  FFetchedFile := '';
  if FShowing then
  begin
    FShowing := False;
    Invalidate;
  end;
end;

procedure TAtlasEditorMetricsLens.Tick(Sender: TObject);
var
  Editors: IOTAEditorServices;
  View: IOTAEditView;
  Text: string;
  Moment: Cardinal;
begin
  try
    if not Wanted(TAtlasIdeSettings.Current) then
    begin
      Clear;
      Exit;
    end;
    View := nil;
    if Supports(BorlandIDEServices, IOTAEditorServices, Editors) then
      View := Editors.TopView;
    if (View = nil) or (View.Buffer = nil) or not IsSource(View.Buffer.FileName) then
      Exit;
    Text := TAtlasEditorBuffer.Text(View.Buffer);
    if not SameText(FFileName, View.Buffer.FileName) or (FText <> Text) then
    begin
      FFileName := View.Buffer.FileName;
      FText := Text;
      FChangedAt := GetTickCount;
      Exit;
    end;
    Moment := GetTickCount;
    if (Moment - FChangedAt < QuietMs) or (Moment < FRetryAt) then
      Exit;
    // Gleicher Stand schon gefragt: nur ab und zu neu (Grenzwerte in atlas.json geändert).
    if SameText(FFetchedFile, FFileName) and (FFetchedText = FText) and (Moment - FFetchedAt < RefreshMs) then
      Exit;
    Fetch;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

procedure TAtlasEditorMetricsLens.Fetch;
var
  Session: TLspSession;
  Values: TJSONArray;
  Arguments: string;
  Answer: TJSONValue;
  Metrics: TAtlasFileMetrics;
  Percent: Integer;
begin
  Session := FSession();
  if Session = nil then
    Exit;
  // Server indexiert: Er antwortet erst danach, der Hauptthread würde warten (#874). Später noch einmal.
  if Session.Indexing(Percent) then
  begin
    FRetryAt := GetTickCount + RetryMs;
    Exit;
  end;
  Values := TJSONArray.Create;
  try
    Values.Add(TLspSession.PathToUri(FFileName));
    Arguments := Values.ToJSON;
  finally
    Values.Free;
  end;
  try
    Session.Sync(FFileName, FText);
    Answer := Session.RunCommand(MetricsCommand, Arguments, TimeoutMs);
  except
    on E: ELspClientError do
    begin
      // Server beschäftigt, weg oder zu alt (Befehl unbekannt): später noch einmal, ohne den Editor zu bremsen.
      FRetryAt := GetTickCount + RetryMs;
      Exit;
    end;
  end;
  try
    Metrics := TAtlasFileMetrics.FromJson(Answer);
  finally
    Answer.Free;
  end;
  FFetchedFile := FFileName;
  FFetchedText := FText;
  FFetchedAt := GetTickCount;
  FMetrics := Metrics;
  FFormats := Formats;
  FShowing := Metrics.Enabled and (Length(Metrics.Methods) > 0);
  Invalidate;
end;

procedure TAtlasEditorMetricsLens.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  Text, Line: string;
  LineState: INTACodeEditorLineState;
  Index, TabWidth, Width, Height, Top, Column: Integer;
  Method: TAtlasMethodMetrics;
  Colors: TAtlasColors;
  Canvas: TCanvas;
  Cell, Pill: TRect;
  OldFont: TFont;
  OldBrush: TBrush;
  OldPen: TPen;
  Back, Tone: TAtlasColor;
  Sample: COLORREF;
begin
  if BeforeEvent or (Stage <> plsEndPaint) or (Context = nil) or not FShowing then
    Exit;
  try
    if not Wanted(TAtlasIdeSettings.Current) then
      Exit;
    if not SameText(Context.FileName, FFetchedFile) then
      Exit;
    Index := FMetrics.IndexAt(Context.LogicalLineNum - 1);
    LineState := Context.LineState;
    if (Index < 0) or (LineState = nil) or (Context.EditView = nil) or (Context.EditView.Buffer = nil) then
      Exit;
    Method := FMetrics.Methods[Index];
    Line := LineState.Text;
    // Nur, wenn die Zeile noch den Namen der Methode trägt (Text kann seit dem Abruf verschoben sein).
    if not TAtlasMetricsLens.LineMatches(Line, Method.Name) then
      Exit;
    if TAtlasIdeElements.Hidden(TAtlasDrawnElement.CodeLensMetrics, Context.FileName, Method.Name) then
      Exit;
    Text := TAtlasMetricsLens.Caption(Method, FMetrics.Limits, FFormats,
      TAtlasStrings.Text(TAtlasTextId.MetricsLensLimit));
    TabWidth := TAtlasEditorBuffer.TabWidth(Context.EditView.Buffer);
    Column := Length(TrimRight(TAtlasPairs.DisplayLine(Line, TabWidth))) + 1;
    Cell := Context.EditorState.GetCharacterPosPx(Column + 3, Context.EditorLineNum);
    Canvas := Context.Canvas;
    Sample := GetPixel(Canvas.Handle, Cell.Left, Rect.Top + 1);
    if Sample = CLR_INVALID then
      Back := TAtlasColor(ColorToRGB(Canvas.Brush.Color))
    else
      Back := TAtlasColor(Sample);
    Colors := TAtlasColors.ForBackground(Back);
    Tone := Colors.Muted;
    if TAtlasMetricsLens.Exceeds(Method, FMetrics.Limits) then
      Tone := Colors.Warn;
    OldFont := TFont.Create;
    OldBrush := TBrush.Create;
    OldPen := TPen.Create;
    try
      OldFont.Assign(Canvas.Font);
      OldBrush.Assign(Canvas.Brush);
      OldPen.Assign(Canvas.Pen);
      Canvas.Font.Size := Max(6, Canvas.Font.Size - 1);
      Canvas.Font.Style := [];
      Canvas.Font.Color := TColor(TAtlasColorMath.Mix(Tone, Back, 0.85));
      Canvas.Pen.Color := TColor(TAtlasColorMath.Mix(Tone, Back, 0.3));
      Canvas.Brush.Color := TColor(TAtlasColorMath.Mix(Tone, Back, 0.1));
      Height := Canvas.TextHeight('Xg');
      Width := Canvas.TextWidth(Text);
      Top := Rect.Top + Max(0, (Rect.Bottom - Rect.Top - Height - 2) div 2);
      Pill := TRect.Create(Cell.Left, Top, Cell.Left + Width + 10, Top + Height + 2);
      Canvas.Brush.Style := bsSolid;
      Canvas.RoundRect(Pill.Left, Pill.Top, Pill.Right, Pill.Bottom, 6, 6);
      Canvas.Brush.Style := bsClear;
      Canvas.TextOut(Pill.Left + 5, Pill.Top + 1, Text);
      TAtlasIdeElements.Painted(TAtlasDrawnElement.CodeLensMetrics, Context.FileName, Context.LogicalLineNum - 1,
        Method.Name, Pill, Context.EditView.TopRow, Rect.Height);
    finally
      Canvas.Font.Assign(OldFont);
      Canvas.Brush.Assign(OldBrush);
      Canvas.Pen.Assign(OldPen);
      OldPen.Free;
      OldBrush.Free;
      OldFont.Free;
    end;
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.EditorCommands, E);
  end;
end;

end.
