unit Atlas.IDE.Analysis.MetricsLens;

// Code Lens mit Code-Metriken (#66) im Modul Analyse (#1756; bis dahin in
// Base): Länge, Verschachtelungstiefe, zyklomatische und kognitive
// Komplexität und Parameteranzahl je Methode, dazu die Kennzahlen des Aufbaus
// (#939, #980).
// - Werte: Base holt sie je Datei und Textstand für alle Leser
//   (Atlas.IDE.Editor.MetricsSource; die Atlas-Statusleiste liest denselben
//   Abruf). Die Lens meldet dort Bedarf „zeigen“ an, solange sie läuft und
//   codeLens.metrics an ist; dann zeichnet der Abruf nach jeder Antwort den
//   Editor neu. Ändert sich der Stand (Version), liest die Lens die Werte neu.
// - Zeichnen: hinter dem Ende der Kopfzeile jeder implementierten Methode
//   (plsEndPaint) eine Marke mit den Werten; ein Wert über dem Grenzwert ist
//   markiert und die Marke in der Warnfarbe. Die IDE kann keine eigene Zeile
//   über der Methode einfügen, darum steht die Lens hinter dem Kopf. Den Platz
//   hinter dem Zeilenende teilt sie über TAtlasLineTail mit Inlay-Hints und
//   dem Fehlertext am Zeilenende (#509).
// - Kein Klickziel: Die Werte sind Information; die Regeln metric-* melden
//   Überschreitungen als Problem.
// Abschaltbar über „Code Lens mit Code-Metriken“ (codeLens.metrics, auch als
// Schnellschalter, gehört zum Modulschalter analysis.enabled); die
// Server-Einstellung codeLens.metrics in settings.json schaltet sie ebenfalls
// ab. Ausblenden am Element (#628): je Methode („Nur hier“, Anker = Name der
// Methode) oder je Datei über .atlas.

interface

uses
  System.Types,
  ToolsAPI.Editor,
  Atlas.Core.Editor.Metrics,
  Atlas.Core.Analysis.MetricsLens;

type
  TAtlasAnalysisMetricsLens = class
  private type
    TEvents = class(TNTACodeEditorNotifier)
    protected
      function AllowedEvents: TCodeEditorEvents; override;
      function AllowedLineStages: TPaintLineStages; override;
    end;
  public const
    /// <summary>Kennung beim Abruf von Base.</summary>
    cClient = 'atlas.analysis.metricsLens';
  private
    FEvents: TEvents;
    FEventsRef: INTACodeEditorEvents;
    FIndex: Integer;
    FWanted: Boolean;
    /// <summary>Stand des Abrufs, zu dem FFileName und FMetrics gehören.</summary>
    FVersion: Cardinal;
    FFileName: string;
    FMetrics: TAtlasFileMetrics;
    FFormats: TAtlasMetricFormats;
    FStructureFormats: TAtlasStructureFormats;
    procedure Refresh;
    function Showing: Boolean;
    procedure PaintLine(const Rect: TRect; const Stage: TPaintLineStage; const BeforeEvent: Boolean;
      var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
    procedure PaintPill(const ARect: TRect; const AContext: INTACodeEditorPaintContext; const ALine, AName,
      AText: string; AOver: Boolean);
    class function Formats: TAtlasMetricFormats; static;
    class function StructureFormats: TAtlasStructureFormats; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Bedarf beim Abruf nach codeLens.metrics; beim Ausschalten verschwinden die Marken sofort.</summary>
    procedure ApplySettings;
  end;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.LineTail,
  Atlas.Core.Editor.Elements,
  Atlas.UI.Analysis.Strings,
  Atlas.IDE.Editor.Lens,
  Atlas.IDE.Editor.MetricsSource,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.Elements,
  Atlas.IDE.Foundation.EditorRefresh;

{ TAtlasAnalysisMetricsLens.TEvents }

function TAtlasAnalysisMetricsLens.TEvents.AllowedEvents: TCodeEditorEvents;
begin
  Result := [cevPaintLineEvents];
end;

function TAtlasAnalysisMetricsLens.TEvents.AllowedLineStages: TPaintLineStages;
begin
  Result := [plsEndPaint];
end;

{ TAtlasAnalysisMetricsLens }

function Wanted(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.Metrics and ASettings.CodeLensMetrics and
    not TAtlasGuard.Disabled(TAtlasFeature.CodeLens);
end;

procedure InvalidateEditor;
var
  mServices: INTACodeEditorServices;
begin
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    TAtlasIdeEditorRefresh.InvalidateTop(mServices);
  end;
end;

constructor TAtlasAnalysisMetricsLens.Create;
var
  mServices: INTACodeEditorServices;
begin
  inherited Create;
  FIndex := -1;
  FEvents := TEvents.Create;
  FEventsRef := FEvents;
  FEvents.OnEditorPaintLine := PaintLine;
  if Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    FIndex := mServices.AddEditorEventsNotifier(FEventsRef);
  end;
  ApplySettings;
end;

destructor TAtlasAnalysisMetricsLens.Destroy;
var
  mServices: INTACodeEditorServices;
begin
  // Base hält danach keinen Bedarf des Moduls mehr (Regel 3).
  TAtlasEditorMetricsSource.Want(cClient, TAtlasMetricsDemand.None);
  // Erst abmelden, dann freigeben (#493).
  if (FIndex >= 0) and Supports(BorlandIDEServices, INTACodeEditorServices, mServices) then
  begin
    mServices.RemoveEditorEventsNotifier(FIndex);
  end;
  FEvents.OnEditorPaintLine := nil;
  FEventsRef := nil;
  if FWanted then
  begin
    InvalidateEditor;
  end;
  inherited Destroy;
end;

procedure TAtlasAnalysisMetricsLens.ApplySettings;
var
  mWanted: Boolean;
begin
  mWanted := Wanted(TAtlasIdeSettings.Current);
  if mWanted = FWanted then
  begin
    Exit;
  end;
  FWanted := mWanted;
  if mWanted then
  begin
    TAtlasEditorMetricsSource.Want(cClient, TAtlasMetricsDemand.Paint);
  end
  else
  begin
    TAtlasEditorMetricsSource.Want(cClient, TAtlasMetricsDemand.None);
  end;
  InvalidateEditor;
end;

class function TAtlasAnalysisMetricsLens.Formats: TAtlasMetricFormats;
begin
  Result[TAtlasMetric.MethodLength] := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensLines);
  Result[TAtlasMetric.Nesting] := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensDepth);
  Result[TAtlasMetric.Cyclomatic] := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensCyclomatic);
  Result[TAtlasMetric.Cognitive] := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensCognitive);
  Result[TAtlasMetric.Parameters] := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensParameters);
  Result[TAtlasMetric.Operands] := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensOperands);
  Result[TAtlasMetric.Locals] := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensLocals);
  Result[TAtlasMetric.Exits] := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensExits);
end;

class function TAtlasAnalysisMetricsLens.StructureFormats: TAtlasStructureFormats;
begin
  Result[TAtlasStructureMetric.ClassSize] := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensMembers);
  Result[TAtlasStructureMetric.UnitLength] := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensLines);
  Result[TAtlasStructureMetric.UsesCount] := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensUses);
  Result[TAtlasStructureMetric.InheritanceDepth] :=
    TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensInheritance);
end;

/// <summary>Werte neu lesen, wenn der Abruf einen neuen Stand hat.</summary>
procedure TAtlasAnalysisMetricsLens.Refresh;
begin
  if FVersion = TAtlasEditorMetricsSource.Version then
  begin
    Exit;
  end;
  FVersion := TAtlasEditorMetricsSource.Version;
  if not TAtlasEditorMetricsSource.Fetched(FFileName, FMetrics) then
  begin
    FFileName := '';
  end;
  FFormats := Formats;
  FStructureFormats := StructureFormats;
end;

function TAtlasAnalysisMetricsLens.Showing: Boolean;
begin
  Result := FWanted and (FFileName <> '') and FMetrics.Enabled and
    ((Length(FMetrics.Methods) > 0) or (Length(FMetrics.Structures) > 0));
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
    TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensLimit));
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
    TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensInheritanceAtLeast),
    TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.MetricsLensLimit));
  for mStructure in mStructures do
  begin
    AOver := AOver or (mStructure.Value > mStructure.Limit);
  end;
end;

procedure TAtlasAnalysisMetricsLens.PaintPill(const ARect: TRect; const AContext: INTACodeEditorPaintContext;
  const ALine, AName, AText: string; AOver: Boolean);
var
  mTailKey: string;
  mCell, mPill: TRect;
  mBack, mTone: TAtlasColor;
begin
  mCell := TAtlasLensPill.CellAfter(AContext, ALine);
  mTailKey := TAtlasLineTail.KeyOf(AContext.FileName, AContext.LogicalLineNum, AContext.EditorLineNum, ARect.Top);
  mBack := TAtlasLensPill.BackAt(AContext.Canvas, mCell.Left, ARect.Top + 1);
  mTone := TAtlasColors.ForBackground(mBack).Muted;
  if AOver then
  begin
    mTone := TAtlasColors.ForBackground(mBack).Warn;
  end;
  mPill := TAtlasLensPill.Paint(AContext.Canvas, ARect, TAtlasLineTail.Start(Self, mTailKey, mCell.Left), AText,
    TAtlasLensPillStyle.Create(mTone, mBack, 0.3, 0.1, []));
  TAtlasLineTail.Finish(Self, mTailKey, mPill.Right);
  TAtlasIdeElements.Painted(TAtlasIdeElements.Target(TAtlasDrawnElement.CodeLensMetrics, AContext.FileName,
    AContext.LogicalLineNum - 1, AName), mPill, AContext.EditView.TopRow, ARect.Height);
end;

procedure TAtlasAnalysisMetricsLens.PaintLine(const Rect: TRect; const Stage: TPaintLineStage;
  const BeforeEvent: Boolean; var AllowDefaultPainting: Boolean; const Context: INTACodeEditorPaintContext);
var
  mText, mLine, mName: string;
  mOver: Boolean;
begin
  try
    Refresh;
    if not Showing or not TAtlasLensPill.Ready(Stage, BeforeEvent, Context, FFileName) then
    begin
      Exit;
    end;
    mLine := Context.LineState.Text;
    // Nur, wenn die Zeile noch den Namen trägt (Text kann seit dem Abruf verschoben sein).
    if not (MethodLens(FMetrics, FFormats, Context.LogicalLineNum - 1, mName, mText, mOver) or
      StructureLens(FMetrics, FStructureFormats, Context.LogicalLineNum - 1, mName, mText, mOver)) or
      not TAtlasMetricsLens.LineMatches(mLine, mName) or
      TAtlasIdeElements.Hidden(TAtlasDrawnElement.CodeLensMetrics, Context.FileName, mName) then
    begin
      Exit;
    end;
    PaintPill(Rect, Context, mLine, mName, mText, mOver);
  except
    // Zeichnen darf die IDE nie stören.
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.CodeLens, E);
  end;
end;

end.
