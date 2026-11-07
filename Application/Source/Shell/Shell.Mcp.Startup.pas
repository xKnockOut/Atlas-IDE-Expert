unit Shell.Mcp.Startup;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Start eines Laufs: Logger und Logdatei, Projektordner, globale
// Einstellungen und Absturzfälle (#1355).

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.JsonRpc.RecentMessages,
  Shell.CommandLine,
  Shell.CrashCases,
  Shell.Workspace;

/// <summary>Logger mit Warnungen auf stderr und der Logdatei aus --log; die Hinweise der Kommandozeile gleich darin.
/// </summary>
function NewLogger(const AOptions: TCommandLineOptions): ILogger;
/// <summary>Projektordner aus --root, sonst das aktuelle Verzeichnis; absolut, ohne Trenner am Ende.</summary>
function RootOf(const AOptions: TCommandLineOptions): string;
/// <summary>Globale Einstellungen wie im LSP-Server und im Linter (D-08), abschaltbar mit mcp.globalSettings in
/// atlas.json. Load übernimmt sie, damit der Index nur einmal mit den wirksamen Einstellungen startet.</summary>
function GlobalSettingsOf(const ARoot: string; const ALogger: ILogger): string;
/// <summary>Absturzfälle auch im MCP-Modus (#1355): Werkzeugaufrufe haben kein Dokument, also nur der Fall, kein
/// Überspringen. Eine Meldung an den Client gibt es nicht (Claude Code kennt atlas/crashCase nicht).</summary>
function NewCrashCases(const ALogger: ILogger; const ARecent: IJsonRpcRecentMessages; const ARoot: string):
  TShellCrashCases;
/// <summary>OnRequestFailed des Dispatchers: Fall sichern, wenn server.crashCases an ist.</summary>
function RequestFailedOf(ACrashCases: TShellCrashCases; AWorkspace: TShellWorkspace): TJsonRpcRequestFailedEvent;

implementation

uses
  System.IOUtils,
  System.JSON,
  Atlas.Common.Product.Version,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Logging.Providers.StreamSink,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Diagnostics.Anonymizer,
  Shell.Platform,
  Shell.Bootstrap,
  Shell.Diagnostics;

/// <summary>Logger mit Warnungen auf stderr und der Logdatei aus --log; die Hinweise der Kommandozeile gleich darin.
/// </summary>
function NewLogger(const AOptions: TCommandLineOptions): ILogger;
var
  mLogger: TLogger;
  mAnonymizer: ILogAnonymizer;
  mWarning: TCommandLineWarning;
begin
  mLogger := TLogger.Create;
  Result := mLogger;
  mLogger.AddSink(TStreamLogSink.Create(TStdStreams.CreateError, True), TLogLevel.Warning);
  TShellDiagnostics.AddLogFile(mLogger, AOptions.LogFile, IntToStr(TParentWatcher.CurrentProcessId),
    AOptions.LogNames, AOptions.LogLevel, mAnonymizer);
  for mWarning in AOptions.Warnings do
  begin
    Result.Warning(mWarning.Text);
  end;
end;

/// <summary>Projektordner aus --root, sonst das aktuelle Verzeichnis; absolut, ohne Trenner am Ende.</summary>
function RootOf(const AOptions: TCommandLineOptions): string;
begin
  Result := AOptions.McpRoot;
  if Result = '' then
  begin
    Result := GetCurrentDir;
  end;
  Result := ExcludeTrailingPathDelimiter(TPath.GetFullPath(Result));
end;

/// <summary>Globale Einstellungen wie im LSP-Server und im Linter (D-08), abschaltbar mit mcp.globalSettings in
/// atlas.json. Load übernimmt sie, damit der Index nur einmal mit den wirksamen Einstellungen startet.</summary>
function GlobalSettingsOf(const ARoot: string; const ALogger: ILogger): string;
begin
  Result := '';
  if TShellBootstrap.ProjectSettings(ARoot).McpGlobalSettings then
  begin
    Result := TShellBootstrap.LoadGlobalSettings(ALogger);
  end
  else
  begin
    ALogger.Info('Globale Einstellungen ausgeschaltet (mcp.globalSettings)');
  end;
end;

/// <summary>Absturzfälle auch im MCP-Modus (#1355): Werkzeugaufrufe haben kein Dokument, also nur der Fall, kein
/// Überspringen. Eine Meldung an den Client gibt es nicht (Claude Code kennt atlas/crashCase nicht).</summary>
function NewCrashCases(const ALogger: ILogger; const ARecent: IJsonRpcRecentMessages; const ARoot: string):
  TShellCrashCases;
var
  mRoot: string;
begin
  mRoot := ARoot;
  Result := TShellCrashCases.Create('', ALogger, nil, ARecent);
  Result.AtlasVersion := TProductVersion.cVersion;
  Result.ServerPath := ParamStr(0);
  Result.Client := 'Claude Code (MCP)';
  Result.SkipEnabled := False;
  Result.SettingsFiles :=
    function(const AUri: string): TArray<string>
    begin
      Result := TArray<string>.Create(TShellBootstrap.GlobalSettingsFile,
        ExistingOrLegacyFile(mRoot, cConfigurationFileName, cLegacyConfigurationFileName));
    end;
end;

function RequestFailedOf(ACrashCases: TShellCrashCases; AWorkspace: TShellWorkspace): TJsonRpcRequestFailedEvent;
begin
  Result :=
    procedure(const AMethod: string; const AParams: TJSONValue; const AError: Exception)
    begin
      ACrashCases.Enabled := AWorkspace.Configuration.Settings.ServerCrashCases;
      ACrashCases.RequestFailed(AMethod, AParams, AError, TShellPlatform.StackTraceOf(AError));
    end;
end;

end.
