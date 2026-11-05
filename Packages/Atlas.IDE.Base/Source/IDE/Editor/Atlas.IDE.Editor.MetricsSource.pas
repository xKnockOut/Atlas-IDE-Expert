unit Atlas.IDE.Editor.MetricsSource;

// Code-Metriken des oberen Editors (#66) für alle Leser: die Atlas-Statusleiste
// von Base (#1155) und die Code Lens mit Code-Metriken im Modul Analyse
// (Atlas.IDE.Analysis.MetricsLens, #1756). Eine Anfrage je Stand, nicht eine
// je Leser.
// - Abruf: Ein Zeitgeber prüft den oberen Editor. Nach einer Tipp-Pause fragt
//   er atlas.server.metrics für die Datei (nur, wenn der Server ohnehin läuft)
//   und merkt sich die Antwort je Datei und Textstand. Ohne Änderung fragt er
//   alle RefreshMs neu (geänderte Grenzwerte in atlas.json).
// - Bedarf: Jeder Leser meldet über Want, ob er die Werte liest (Read) oder
//   im Editor zeigt (Paint). Ohne Bedarf, ohne metrics oder bei gesperrter
//   Code Lens fragt der Zeitgeber nicht und vergisst die letzte Antwort.
//   Zeigt ein Leser die Werte, zeichnet der Abruf danach den Editor neu.
// - Version zählt jede neue Antwort und jedes Vergessen; ein Leser mit Paint
//   holt sich damit die Werte nur bei Änderung (Fetched).
// Base kennt das Modul nicht (Regel 9): Leser melden sich nur mit einer
// Kennung an und holen die Werte selbst ab.

interface

uses
  Vcl.ExtCtrls,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Editor.Metrics,
  Atlas.IDE.Editor.Lens;

type
  /// <summary>Laufende Sitzung oder nil; startet keinen Server.</summary>
  TAtlasMetricsSourceSessionFunc = reference to function: TLspSession;

{$SCOPEDENUMS ON}
  /// <summary>Bedarf eines Lesers: keiner, Werte lesen (Statusleiste) oder im Editor zeigen (Code Lens).</summary>
  TAtlasMetricsDemand = (None, Read, Paint);
{$SCOPEDENUMS OFF}

  TAtlasEditorMetricsSource = class
  private type
    TClient = record
      Name: string;
      Demand: TAtlasMetricsDemand;
    end;
  private const
    QuietMs = 700;
    TimeoutMs = 800;
    RetryMs = 5000;
    RefreshMs = 30000;
  private
    FSession: TAtlasMetricsSourceSessionFunc;
    FTimer: TTimer;
    /// <summary>Abruf; FPoll.FetchedFile ist die Datei, zu der FMetrics gehört.</summary>
    FPoll: TAtlasLensPoll;
    FMetrics: TAtlasFileMetrics;
    class var FCurrent: TAtlasEditorMetricsSource;
    class var FClients: TArray<TClient>;
    class var FVersion: Cardinal;
    procedure Tick(Sender: TObject);
    procedure Fetch;
    procedure Clear;
    class function Demand: TAtlasMetricsDemand; static;
    class function IndexOfClient(const AName: string): Integer; static;
  public
    constructor Create(const ASession: TAtlasMetricsSourceSessionFunc);
    destructor Destroy; override;
    /// <summary>Bedarf des Lesers AClient setzen; None meldet ihn ab.</summary>
    class procedure Want(const AClient: string; ADemand: TAtlasMetricsDemand); static;
    /// <summary>Letzte Antwort für AFileName; False ohne (andere Datei, noch nicht geholt, kein Server).</summary>
    class function Latest(const AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean; static;
    /// <summary>Letzte Antwort mit ihrer Datei; False ohne.</summary>
    class function Fetched(out AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean; static;
    /// <summary>Zählt jede neue Antwort und jedes Vergessen.</summary>
    class function Version: Cardinal; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  ToolsAPI,
  ToolsAPI.Editor,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorRefresh;

const
  MetricsCommand = 'atlas.server.metrics';

{ TAtlasEditorMetricsSource }

constructor TAtlasEditorMetricsSource.Create(const ASession: TAtlasMetricsSourceSessionFunc);
begin
  inherited Create;
  FSession := ASession;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := 250;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  FCurrent := Self;
end;

destructor TAtlasEditorMetricsSource.Destroy;
begin
  if FCurrent = Self then
  begin
    FCurrent := nil;
    Inc(FVersion);
  end;
  FTimer.Free;
  inherited Destroy;
end;

class function TAtlasEditorMetricsSource.IndexOfClient(const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(FClients) do
  begin
    if SameText(FClients[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
end;

class procedure TAtlasEditorMetricsSource.Want(const AClient: string; ADemand: TAtlasMetricsDemand);
var
  mIndex: Integer;
  mClient: TClient;
begin
  mIndex := IndexOfClient(AClient);
  if mIndex >= 0 then
  begin
    Delete(FClients, mIndex, 1);
  end;
  if ADemand <> TAtlasMetricsDemand.None then
  begin
    mClient.Name := AClient;
    mClient.Demand := ADemand;
    FClients := FClients + [mClient];
  end;
end;

/// <summary>Stärkster Bedarf aller Leser.</summary>
class function TAtlasEditorMetricsSource.Demand: TAtlasMetricsDemand;
var
  mClient: TClient;
begin
  Result := TAtlasMetricsDemand.None;
  for mClient in FClients do
  begin
    if mClient.Demand > Result then
    begin
      Result := mClient.Demand;
    end;
  end;
end;

class function TAtlasEditorMetricsSource.Fetched(out AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean;
begin
  AFileName := '';
  AMetrics := Default(TAtlasFileMetrics);
  Result := (FCurrent <> nil) and (FCurrent.FPoll.FetchedFile <> '');
  if Result then
  begin
    AFileName := FCurrent.FPoll.FetchedFile;
    AMetrics := FCurrent.FMetrics;
  end;
end;

class function TAtlasEditorMetricsSource.Latest(const AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean;
var
  mFileName: string;
begin
  Result := Fetched(mFileName, AMetrics) and SameText(mFileName, AFileName);
  if not Result then
  begin
    AMetrics := Default(TAtlasFileMetrics);
  end;
end;

class function TAtlasEditorMetricsSource.Version: Cardinal;
begin
  Result := FVersion;
end;

/// <summary>Holen nur mit Bedarf eines Lesers, mit metrics und ohne gesperrte Code Lens.</summary>
function Fetching(const ASettings: TAtlasPluginSettings; ADemand: TAtlasMetricsDemand): Boolean;
begin
  Result := (ADemand <> TAtlasMetricsDemand.None) and ASettings.Enabled and ASettings.Metrics and
    not TAtlasGuard.Disabled(TAtlasFeature.CodeLens);
end;

function IsSource(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := ExtractFileExt(AFileName);
  Result := SameText(mExtension, '.pas') or SameText(mExtension, '.dpr') or SameText(mExtension, '.dpk');
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

procedure TAtlasEditorMetricsSource.Clear;
begin
  if FPoll.FetchedFile = '' then
  begin
    Exit;
  end;
  FMetrics := Default(TAtlasFileMetrics);
  FMetrics.Methods := nil;
  FPoll.Forget;
  Inc(FVersion);
  // Gezeigte Werte verschwinden (metrics aus, Code Lens gesperrt).
  if Demand = TAtlasMetricsDemand.Paint then
  begin
    InvalidateEditor;
  end;
end;

procedure TAtlasEditorMetricsSource.Tick(Sender: TObject);
var
  mView: IOTAEditView;
begin
  try
    if not Fetching(TAtlasIdeSettings.Current, Demand) then
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

procedure TAtlasEditorMetricsSource.Fetch;
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
  Inc(FVersion);
  // Nur für die Statusleiste geholt: Der Editor zeigt nichts davon.
  if Demand = TAtlasMetricsDemand.Paint then
  begin
    InvalidateEditor;
  end;
end;

end.
