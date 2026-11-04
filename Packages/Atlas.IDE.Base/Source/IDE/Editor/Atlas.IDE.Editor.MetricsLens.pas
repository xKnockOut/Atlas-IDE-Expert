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
//   über der Methode einfügen, darum steht die Lens hinter dem Kopf. Den Platz
//   hinter dem Zeilenende teilt sie über TAtlasLineTail mit Inlay-Hints und
//   dem Fehlertext am Zeilenende (#509).
// - Kein Klickziel: Die Werte sind Information; die Regeln metric-* melden
//   Überschreitungen als Problem.
// Die Atlas-Statusleiste (#1155) liest Zeilen und CC der Methode am Cursor
// aus demselben Abruf (Latest); braucht sie Metriken, meldet sie das über
// Want, dann fragt der Zeitgeber auch bei ausgeschalteter Lens (gezeichnet
// wird nur mit Lens). So gibt es eine Anfrage je Stand, nicht zwei.
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
  Atlas.Core.Editor.Metrics,
  Atlas.IDE.Editor.Lens;

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
    /// <summary>Abruf; FPoll.FetchedText ist der Textstand, zu dem FMetrics gehört.</summary>
    FPoll: TAtlasLensPoll;
    FMetrics: TAtlasFileMetrics;
    FFormats: TAtlasMetricFormats;
    FStructureFormats: TAtlasStructureFormats;
    FShowing: Boolean;
    class var FCurrent: TAtlasEditorMetricsLens;
    class var FDemand: Boolean;
    procedure Tick(Sender: TObject);
    procedure Fetch;
    procedure Clear;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    class procedure Invalidate; static;
    class function Formats: TAtlasMetricFormats; static;
    class function StructureFormats: TAtlasStructureFormats; static;
  public
    constructor Create(const ASession: TAtlasMetricsLensSessionFunc);
    destructor Destroy; override;
    /// <summary>Metriken auch ohne Lens holen (Atlas-Statusleiste, #1155).</summary>
    class procedure Want(AOn: Boolean); static;
    /// <summary>Letzte Antwort für AFileName; False ohne (andere Datei, noch nicht geholt, kein Server).</summary>
    class function Latest(const AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean; static;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.LineTail,
  Atlas.UI.Strings,
  Atlas.Core.Editor.Elements,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorRefresh;

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
  begin
    FIndex := Services.AddEditorEventsNotifier(FEventsRef);
  end;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  FCurrent := Self;
end;

destructor TAtlasEditorMetricsLens.Destroy;
var
  Services: INTACodeEditorServices;
begin
  if FCurrent = Self then
  begin
    FCurrent := nil;
  end;
  FTimer.Free;
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    Services.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  inherited Destroy;
end;

class procedure TAtlasEditorMetricsLens.Invalidate;
var
  Services: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, Services) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(Services);
  end;
end;

class function TAtlasEditorMetricsLens.Formats: TAtlasMetricFormats;
begin
  Result[TAtlasMetric.MethodLength] := TAtlasStrings.Text(TAtlasTextId.MetricsLensLines);
  Result[TAtlasMetric.Nesting] := TAtlasStrings.Text(TAtlasTextId.MetricsLensDepth);
  Result[TAtlasMetric.Cyclomatic] := TAtlasStrings.Text(TAtlasTextId.MetricsLensCyclomatic);
  Result[TAtlasMetric.Cognitive] := TAtlasStrings.Text(TAtlasTextId.MetricsLensCognitive);
  Result[TAtlasMetric.Parameters] := TAtlasStrings.Text(TAtlasTextId.MetricsLensParameters);
  Result[TAtlasMetric.Operands] := TAtlasStrings.Text(TAtlasTextId.MetricsLensOperands);
  Result[TAtlasMetric.Locals] := TAtlasStrings.Text(TAtlasTextId.MetricsLensLocals);
  Result[TAtlasMetric.Exits] := TAtlasStrings.Text(TAtlasTextId.MetricsLensExits);
end;

class function TAtlasEditorMetricsLens.StructureFormats: TAtlasStructureFormats;
begin
  Result[TAtlasStructureMetric.ClassSize] := TAtlasStrings.Text(TAtlasTextId.MetricsLensMembers);
  Result[TAtlasStructureMetric.UnitLength] := TAtlasStrings.Text(TAtlasTextId.MetricsLensLines);
  Result[TAtlasStructureMetric.UsesCount] := TAtlasStrings.Text(TAtlasTextId.MetricsLensUses);
  Result[TAtlasStructureMetric.InheritanceDepth] := TAtlasStrings.Text(TAtlasTextId.MetricsLensInheritance);
end;

function Wanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.Metrics and ASettings.CodeLensMetrics and
    not TAtlasGuard.Disabled(TAtlasFeature.CodeLens);
end;

/// <summary>Holen: für die Lens oder auf Wunsch der Statusleiste (Want).</summary>
function Fetching(const ASettings: TAtlasPluginSettings; ADemand: Boolean): Boolean;
begin
  Result := Wanted(ASettings) or (ADemand and ASettings.Enabled and ASettings.Metrics and
    not TAtlasGuard.Disabled(TAtlasFeature.CodeLens));
end;

class procedure TAtlasEditorMetricsLens.Want(AOn: Boolean);
begin
  FDemand := AOn;
end;

class function TAtlasEditorMetricsLens.Latest(const AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean;
begin
  AMetrics := Default(TAtlasFileMetrics);
  Result := (FCurrent <> nil) and (FCurrent.FPoll.FetchedFile <> '') and
    SameText(FCurrent.FPoll.FetchedFile, AFileName);
  if Result then
  begin
    AMetrics := FCurrent.FMetrics;
  end;
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
  FPoll.Forget;
  if FShowing then
  begin
    FShowing := False;
    Invalidate;
  end;
end;

procedure TAtlasEditorMetricsLens.Tick(Sender: TObject);
var
  mView: IOTAEditView;
begin
  try
    if not Fetching(TAtlasIdeSettings.Current, FDemand) then
    begin
      Clear;
      Exit;
    end;
    mView := TAtlasLensPoll.TopView;
    if (mView <> nil) and (mView.Buffer <> nil) and IsSource(mView.Buffer.FileName) and
      FPoll.Due(mView, QuietMs, RefreshMs) then
    begin
      Fetch;
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CodeLens, E);
  end;
end;

procedure TAtlasEditorMetricsLens.Fetch;
var
  mAnswer: TJSONValue;
  mMetrics: TAtlasFileMetrics;
begin
  if not FPoll.Ask(FSession(), MetricsCommand, FPoll.UriArguments, TimeoutMs, RetryMs, mAnswer) then
  begin
    Exit;
  end;
  try
    mMetrics := TAtlasFileMetrics.FromJson(mAnswer);
  finally
    mAnswer.Free;
  end;
  FPoll.Fetched;
  FMetrics := mMetrics;
  FFormats := Formats;
  FStructureFormats := StructureFormats;
  FShowing := mMetrics.Enabled and ((Length(mMetrics.Methods) > 0) or (Length(mMetrics.Structures) > 0));
  // Nur für die Statusleiste geholt: Der Editor zeigt nichts davon.
  if Wanted(TAtlasIdeSettings.Current) then
  begin
    Invalidate;
  end;
end;

/// <summary>Lens der Methode, deren Kopf in Zeile ALine steht; False ohne.</summary>
function MethodLens(const AMetrics: TAtlasFileMetrics; const AFormats: TAtlasMetricFormats; ALine: Integer;
  out AName, AText: string; out AOver: Boolean): Boolean;
var
  mIndex: Integer;
  mMethod: TAtlasMethodMetrics;
begin
  mIndex := AMetrics.IndexAt(ALine);
  Result := mIndex >= 0;
  AOver := False;
  if not Result then
  begin
    Exit;
  end;
  mMethod := AMetrics.Methods[mIndex];
  AName := mMethod.Name;
  AText := TAtlasMetricsLens.Caption(mMethod, AMetrics.Limits, AFormats,
    TAtlasStrings.Text(TAtlasTextId.MetricsLensLimit));
  AOver := TAtlasMetricsLens.Exceeds(mMethod, AMetrics.Limits);
end;

/// <summary>Lens des Aufbaus in Zeile ALine (#939): Member und Vererbungstiefe (#980) über der Klasse, Zeilen über
/// dem Unit-Namen, Units im uses über uses; False ohne.</summary>
function StructureLens(const AMetrics: TAtlasFileMetrics; const AFormats: TAtlasStructureFormats; ALine: Integer;
  out AName, AText: string; out AOver: Boolean): Boolean;
var
  mStructures: TArray<TAtlasStructureItem>;
  mStructure: TAtlasStructureItem;
begin
  mStructures := AMetrics.StructuresAt(ALine);
  Result := mStructures <> nil;
  AOver := False;
  if not Result then
  begin
    Exit;
  end;
  AName := mStructures[0].Name;
  if mStructures[0].Kind = TAtlasStructureMetric.UsesCount then
  begin
    AName := 'uses';
  end;
  AText := TAtlasMetricsLens.StructureCaption(mStructures, AFormats,
    TAtlasStrings.Text(TAtlasTextId.MetricsLensInheritanceAtLeast), TAtlasStrings.Text(TAtlasTextId.MetricsLensLimit));
  for mStructure in mStructures do
  begin
    AOver := AOver or (mStructure.Value > mStructure.Limit);
  end;
end;

procedure TAtlasEditorMetricsLens.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mText, mLine, mName, mTailKey: string;
  mOver: Boolean;
  mCell, mPill: TRect;
  mBack, mTone: TAtlasColor;
begin
  if not FShowing or not TAtlasLensPill.Ready(Stage, BeforeEvent, Context, FPoll.FetchedFile) then
  begin
    Exit;
  end;
  try
    mLine := Context.LineState.Text;
    // Nur, wenn die Zeile noch den Namen trägt (Text kann seit dem Abruf verschoben sein).
    if not Wanted(TAtlasIdeSettings.Current) or
      not (MethodLens(FMetrics, FFormats, Context.LogicalLineNum - 1, mName, mText, mOver) or
      StructureLens(FMetrics, FStructureFormats, Context.LogicalLineNum - 1, mName, mText, mOver)) or
      not TAtlasMetricsLens.LineMatches(mLine, mName) or
      TAtlasIdeElements.Hidden(TAtlasDrawnElement.CodeLensMetrics, Context.FileName, mName) then
    begin
      Exit;
    end;
    mCell := TAtlasLensPill.CellAfter(Context, mLine);
    mTailKey := TAtlasLineTail.KeyOf(Context.FileName, Context.LogicalLineNum, Context.EditorLineNum, Rect.Top);
    mBack := TAtlasLensPill.BackAt(Context.Canvas, mCell.Left, Rect.Top + 1);
    mTone := TAtlasColors.ForBackground(mBack).Muted;
    if mOver then
    begin
      mTone := TAtlasColors.ForBackground(mBack).Warn;
    end;
    mPill := TAtlasLensPill.Paint(Context.Canvas, Rect, TAtlasLineTail.Start(Self, mTailKey, mCell.Left), mText,
      TAtlasLensPillStyle.Create(mTone, mBack, 0.3, 0.1, []));
    TAtlasLineTail.Finish(Self, mTailKey, mPill.Right);
    TAtlasIdeElements.Painted(TAtlasDrawnElement.CodeLensMetrics, Context.FileName, Context.LogicalLineNum - 1,
      mName, mPill, Context.EditView.TopRow, Rect.Height);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CodeLens, E);
  end;
end;

end.
