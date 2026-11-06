unit Atlas.Common.Lsp.Metrics;

// Befehl atlas.server.metrics (#66): Code-Metriken für die Code Lens des
// IDE-Plugins, den Metrikbericht und die Projekt-Zusammenfassung der
// Willkommensseite (#592, Projektverlauf #758).
// Argumente: [uri, mode]
//   - URI einer Quelltextdatei, mode fehlt oder "file":
//       {"enabled": true, "limits": {…}, "structure": […], "file": "Source/Main.pas", "methods": […]}
//     Die Methoden und "structure" (Member je Klasse, Zeilen und Units im uses, #939, mit Index die
//     Vererbungstiefe, #980) haben das Format aus
//     Atlas.Common.Metrics.Report (Zeilen ab 1); "enabled" ist die Einstellung codeLens.metrics.
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
  Atlas.Common.Index.Contract,
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
    cCommand = 'atlas.server.metrics';
  private
    FCollector: TMetricsCollector;
    FSourceFor: TLspMetricsSourceFunc;
    FReadText: TMetricsReadText;
    FIndex: ISymbolIndex;
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
    /// <summary>Symbolindex für die Vererbungstiefe in "structure" (#980); nil ohne.</summary>
    property Index: ISymbolIndex read FIndex write FIndex;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Calculator,
  Atlas.Common.Metrics.Report,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TMetricsText = (MetricsDataIsNotValid, UnknownModeAllowedFileSummary);

const
  cTexts: array[TMetricsText] of TAtlasText = (
    (De: 'Metrikdaten sind kein gültiges JSON'; En: 'Metrics data is not valid JSON'),
    (De: 'Unbekannter Modus "%s"; erlaubt: file, summary, json, markdown';
     En: 'Unknown mode "%s"; allowed: file, summary, json, markdown'));

{$SCOPEDENUMS OFF}

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
  begin
    AMode := TLspMetricsMode.FileValues;
  end
  else if SameText(AText, 'summary') then
  begin
    AMode := TLspMetricsMode.Summary;
  end
  else if SameText(AText, 'json') then
  begin
    AMode := TLspMetricsMode.Json;
  end
  else if SameText(AText, 'markdown') then
  begin
    AMode := TLspMetricsMode.Markdown;
  end
  else
  begin
    AMode := TLspMetricsMode.FileValues;
    Result := False;
  end;
end;

class function TLspMetrics.IsProject(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (AFileName = '') or (mExtension = '') or (mExtension = '.dproj') or (mExtension = '.dpr') or
    (mExtension = '.dpk') or (mExtension = '.groupproj');
end;

function TLspMetrics.FileJson(const AFileName: string; const ASource: TLspMetricsSource): string;
var
  mText, mMethods, mStructure: string;
  mLimits: TMetricLimits;
  mFileItem: TFileMetrics;
  mTree: TSyntaxTree;
  mItems: TArray<TStructureMetrics>;
begin
  mStructure := '[]';
  mLimits := TMetricRules.Limits(ASource.Settings);
  if Assigned(FReadText) and FReadText(AFileName, mText) then
  begin
    mFileItem := TFileMetrics.Create(TMetricsCollector.RelativePath(ASource.Root, AFileName),
      FCollector.FileRoutines(AFileName, mText));
    // Aufbau (#939): Member je Klasse, Zeilen und Units im uses für die Metrik-Linse des Plugins; mit Index auch
    // die Vererbungstiefe (#980).
    mTree := TSyntaxTreeCache.Parse(mText);
    try
      mItems := TMetricsCalculator.Structure(mTree);
      if FIndex <> nil then
      begin
        mItems := mItems + TMetricRules.InheritanceDepths(mTree, FIndex, TIndexExtractor.Extract(mTree, AFileName));
      end;
    finally
      mTree.Free;
    end;
    mStructure := TMetricsReport.StructureJson(mItems, mLimits);
  end
  else
  begin
    mFileItem := TFileMetrics.Create(TMetricsCollector.RelativePath(ASource.Root, AFileName), nil);
  end;
  // {"file": …, "methods": […]} um "enabled" und "limits" ergänzt.
  mMethods := TMetricsReport.FileJson(mFileItem, mLimits);
  Result := '{"enabled": ' + LowerCase(BoolToStr(ASource.Settings.Metrics and ASource.Settings.CodeLens.Metrics, True)) + ', "limits": ' +
    TMetricsReport.LimitsJson(mLimits) + ', "structure": ' + mStructure + ', ' + Copy(mMethods, 2, MaxInt);
end;

function TLspMetrics.ProjectJson(const ASource: TLspMetricsSource; AMode: TLspMetricsMode): string;
var
  mFiles: TArray<TFileMetrics>;
  mLimits: TMetricLimits;
begin
  mLimits := TMetricRules.Limits(ASource.Settings);
  mFiles := FCollector.Collect(ASource.Files, ASource.Root, FReadText);
  case AMode of
    TLspMetricsMode.Json:
      Result := TMetricsReport.Json(mFiles, mLimits);
    TLspMetricsMode.Markdown:
      Result := TMetricsReport.JsonString(TMetricsReport.Markdown(mFiles, mLimits, ASource.Title));
  else
    Result := '{"format": ' + IntToStr(TMetricsReport.cFormat) + ', "limits": ' + TMetricsReport.LimitsJson(mLimits) +
      ', "summary": ' + TMetricsReport.SummaryJson(TMetricsReport.Summarize(mFiles, mLimits)) + '}';
  end;
end;

function TLspMetrics.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mFileName, mModeText: string;
  mMode: TLspMetricsMode;
  mSource: TLspMetricsSource;
  mText: string;
begin
  mFileName := '';
  mModeText := '';
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONString) then
  begin
    mFileName := TDocumentUris.ToPath(AArguments.Items[0].Value);
  end;
  if (AArguments <> nil) and (AArguments.Count > 1) and (AArguments.Items[1] is TJSONString) then
  begin
    mModeText := AArguments.Items[1].Value;
  end;
  if not TryParseMode(mModeText, mMode) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TMetricsText.UnknownModeAllowedFileSummary].Fmt([mModeText]));
  end;
  if (mMode = TLspMetricsMode.FileValues) and IsProject(mFileName) then
  begin
    mMode := TLspMetricsMode.Summary;
  end;
  if not (Assigned(FSourceFor) and FSourceFor(mFileName, mMode <> TLspMetricsMode.FileValues, mSource)) then
  begin
    mSource := Default(TLspMetricsSource);
    mSource.Settings := TServerSettings.Default;
  end;
  if mMode = TLspMetricsMode.FileValues then
  begin
    mText := FileJson(mFileName, mSource);
  end
  else
  begin
    mText := ProjectJson(mSource, mMode);
  end;
  Result := TJSONObject.ParseJSONValue(mText);
  if Result = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInternalError, cTexts[TMetricsText.MetricsDataIsNotValid].Text);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Metrics', cTexts);

end.
