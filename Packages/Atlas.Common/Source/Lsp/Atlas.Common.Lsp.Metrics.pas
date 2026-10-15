unit Atlas.Common.Lsp.Metrics;

// Befehl atlas.server.metrics (#66): Code-Metriken für die Code Lens des
// IDE-Plugins, den Metrikbericht und die Projekt-Zusammenfassung der
// Willkommensseite (#592, Projektverlauf #758).
// Argumente: [uri, mode]
//   - URI einer Quelltextdatei, mode fehlt oder "file":
//       {"enabled": true, "limits": {…}, "file": "Source/Main.pas", "methods": […]}
//     Die Methoden haben das Format aus Atlas.Common.Metrics.Report (Zeilen ab 1);
//     "enabled" ist die Einstellung codeLens.metrics.
//   - URI eines Projekts (.dproj, .dpr, .dpk), eines Ordners oder null, dazu mode
//       "summary"  → {"format": 1, "limits": {…}, "summary": {…}}
//       "json"     → vollständige Metrikdaten (TMetricsReport.Json)
//       "markdown" → Gesamtbericht als Markdown (JSON-String)
// Die Grenzwerte stammen aus "rules" der Einstellungen (Option "max" der
// Regeln metric-*). Unveränderte Dateien kommen aus dem Zwischenspeicher.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Metrics.Collector;

type
  /// <summary>Wo gemessen wird: Einstellungen, Wurzel für relative Pfade, Titel und Dateien.</summary>
  TLspMetricsSource = record
    Settings: TServerSettings;
    Root: string;
    /// <summary>Überschrift des Berichts, z. B. der Projektname.</summary>
    Title: string;
    /// <summary>Dateien des Projekts; nur für Bericht und Zusammenfassung.</summary>
    Files: TArray<string>;
  end;

  /// <summary>Quelle zu AFileName (Datei, Projekt, Ordner; '' = alles). AProject: Dateien werden gebraucht.
  /// False, wenn nichts passt.</summary>
  TLspMetricsSourceFunc = reference to function(const AFileName: string; AProject: Boolean;
    out ASource: TLspMetricsSource): Boolean;

  TLspMetricsMode = (FileValues, Summary, Json, Markdown);

  TLspMetrics = class
  public const
    Command = 'atlas.server.metrics';
  private
    FCollector: TMetricsCollector;
    FSourceFor: TLspMetricsSourceFunc;
    FReadText: TMetricsReadText;
  public
    constructor Create(const ASourceFor: TLspMetricsSourceFunc; const AReadText: TMetricsReadText);
    destructor Destroy; override;
    /// <summary>Führt den Befehl aus; der Aufrufer übernimmt das Ergebnis.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
    /// <summary>Antwort für eine Datei (siehe Kopf der Unit) als JSON-Text.</summary>
    function FileJson(const AFileName: string; const ASource: TLspMetricsSource): string;
    /// <summary>Bericht, Daten oder Zusammenfassung über ASource.Files als JSON-Text.</summary>
    function ProjectJson(const ASource: TLspMetricsSource; AMode: TLspMetricsMode): string;
    /// <summary>Modus aus dem Argument; leer = FileValues. False bei unbekanntem Modus.</summary>
    class function TryParseMode(const AText: string; out AMode: TLspMetricsMode): Boolean; static;
    /// <summary>True für .dproj, .dpr, .dpk und Ordner (Endung leer): Bericht über das Projekt.</summary>
    class function IsProject(const AFileName: string): Boolean; static;
    property Collector: TMetricsCollector read FCollector;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Rules.Builtin.Metrics;

{ TLspMetrics }

constructor TLspMetrics.Create(const ASourceFor: TLspMetricsSourceFunc; const AReadText: TMetricsReadText);
begin
  inherited Create;
  FSourceFor := ASourceFor;
  FReadText := AReadText;
  FCollector := TMetricsCollector.Create;
end;

destructor TLspMetrics.Destroy;
begin
  FCollector.Free;
  inherited Destroy;
end;

class function TLspMetrics.TryParseMode(const AText: string; out AMode: TLspMetricsMode): Boolean;
begin
  Result := True;
  if (AText = '') or SameText(AText, 'file') then
    AMode := TLspMetricsMode.FileValues
  else if SameText(AText, 'summary') then
    AMode := TLspMetricsMode.Summary
  else if SameText(AText, 'json') then
    AMode := TLspMetricsMode.Json
  else if SameText(AText, 'markdown') then
    AMode := TLspMetricsMode.Markdown
  else
  begin
    AMode := TLspMetricsMode.FileValues;
    Result := False;
  end;
end;

class function TLspMetrics.IsProject(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (AFileName = '') or (Extension = '') or (Extension = '.dproj') or (Extension = '.dpr') or
    (Extension = '.dpk') or (Extension = '.groupproj');
end;

function TLspMetrics.FileJson(const AFileName: string; const ASource: TLspMetricsSource): string;
var
  Text, Methods: string;
  Limits: TMetricLimits;
  FileItem: TFileMetrics;
begin
  Limits := TMetricRules.Limits(ASource.Settings);
  if Assigned(FReadText) and FReadText(AFileName, Text) then
    FileItem := TFileMetrics.Create(TMetricsCollector.RelativePath(ASource.Root, AFileName),
      FCollector.FileRoutines(AFileName, Text))
  else
    FileItem := TFileMetrics.Create(TMetricsCollector.RelativePath(ASource.Root, AFileName), nil);
  // {"file": …, "methods": […]} um "enabled" und "limits" ergänzt.
  Methods := TMetricsReport.FileJson(FileItem, Limits);
  Result := '{"enabled": ' + LowerCase(BoolToStr(ASource.Settings.CodeLens.Metrics, True)) + ', "limits": ' +
    TMetricsReport.LimitsJson(Limits) + ', ' + Copy(Methods, 2, MaxInt);
end;

function TLspMetrics.ProjectJson(const ASource: TLspMetricsSource; AMode: TLspMetricsMode): string;
var
  Files: TArray<TFileMetrics>;
  Limits: TMetricLimits;
begin
  Limits := TMetricRules.Limits(ASource.Settings);
  Files := FCollector.Collect(ASource.Files, ASource.Root, FReadText);
  case AMode of
    TLspMetricsMode.Json:
      Result := TMetricsReport.Json(Files, Limits);
    TLspMetricsMode.Markdown:
      Result := TMetricsReport.JsonString(TMetricsReport.Markdown(Files, Limits, ASource.Title));
  else
    Result := '{"format": ' + IntToStr(TMetricsReport.Format) + ', "limits": ' + TMetricsReport.LimitsJson(Limits) +
      ', "summary": ' + TMetricsReport.SummaryJson(TMetricsReport.Summarize(Files, Limits)) + '}';
  end;
end;

function TLspMetrics.Execute(const AArguments: TJSONArray): TJSONValue;
var
  FileName, ModeText: string;
  Mode: TLspMetricsMode;
  Source: TLspMetricsSource;
  Text: string;
begin
  FileName := '';
  ModeText := '';
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
    FileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONString) then
    ModeText := AArguments.Items[1].Value;
  if not TryParseMode(ModeText, Mode) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      Format('Unbekannter Modus "%s"; erlaubt: file, summary, json, markdown', [ModeText]));
  if (Mode = TLspMetricsMode.FileValues) and IsProject(FileName) then
    Mode := TLspMetricsMode.Summary;
  if not (Assigned(FSourceFor) and FSourceFor(FileName, Mode <> TLspMetricsMode.FileValues, Source)) then
  begin
    Source := Default(TLspMetricsSource);
    Source.Settings := TServerSettings.Default;
  end;
  if Mode = TLspMetricsMode.FileValues then
    Text := FileJson(FileName, Source)
  else
    Text := ProjectJson(Source, Mode);
  Result := TJSONObject.ParseJSONValue(Text);
  if Result = nil then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InternalError, 'Metrikdaten sind kein gültiges JSON');
end;

end.
