unit Shell.Mcp.Startup;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Start eines Laufs: Logger und Logdatei, Projektordner, globale
// Einstellungen und Absturzfälle (#1355), Werkzeuge und Sicherheit des Servers (#99) und die Prompts (#1357).

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.JsonRpc.RecentMessages,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Prompts,
  Shell.CommandLine,
  Shell.CrashCases,
  Shell.Workspace,
  Shell.Mcp.Services;

/// <summary>Logger mit Warnungen auf stderr und der Logdatei aus --log; die Hinweise der Kommandozeile gleich darin.
/// </summary>
function NewLogger(const AOptions: TCommandLineOptions): ILogger;
/// <summary>Projektordner aus --root, sonst das aktuelle Verzeichnis; absolut, ohne Trenner am Ende.</summary>
function RootOf(const AOptions: TCommandLineOptions): string;
/// <summary>Globale Einstellungen wie im LSP-Server und im Linter, abschaltbar mit mcp.globalSettings in
/// atlas.json. Load übernimmt sie, damit der Index nur einmal mit den wirksamen Einstellungen startet.</summary>
function GlobalSettingsOf(const ARoot: string; const ALogger: ILogger): string;
/// <summary>Absturzfälle auch im MCP-Modus (#1355): Werkzeugaufrufe haben kein Dokument, also nur der Fall, kein
/// Überspringen. Eine Meldung an den Client gibt es nicht (MCP-Clients kennen atlas/crashCase nicht).</summary>
function NewCrashCases(const ALogger: ILogger; const ARecent: IJsonRpcRecentMessages; const ARoot: string):
  TShellCrashCases;
/// <summary>OnRequestFailed des Dispatchers: Fall sichern, wenn server.crashCases an ist.</summary>
function RequestFailedOf(ACrashCases: TShellCrashCases; AWorkspace: TShellWorkspace): TJsonRpcRequestFailedEvent;
/// <summary>Werkzeuge, Sicherheit (#99), Konventionen und das Nachladen vor jedem Werkzeugaufruf.</summary>
procedure ConfigureServer(AServer: TMcpServer; const AServices: TMcpServices; ARestricted: Boolean;
  const ALogger: ILogger);
/// <summary>Prompts und Ressourcenvorlagen (#1357), abschaltbar mit mcp.prompts.</summary>
function NewPrompts(AServer: TMcpServer; const AServices: TMcpServices): TMcpPrompts;

implementation

uses
  System.IOUtils,
  System.JSON,
  Atlas.Common.Product.Version,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Logging.Providers.StreamSink,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Adapters.DiskFileSystem,
  Atlas.Common.Mcp.Freshness,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Diagnostics.Anonymizer,
  Shell.Platform,
  Shell.Bootstrap,
  Shell.Diagnostics,
  Shell.Mcp.Context,
  Shell.Mcp.Tools,
  Shell.Mcp.Changes,
  Shell.Mcp.Conventions,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpStartupText = (Reloaded);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpStartupText] of TAtlasText = (
    (De: '%d geänderte Dateien nachgeladen, %d Units aktualisiert'; En: '%d changed files reloaded, %d units updated'));

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

/// <summary>Globale Einstellungen wie im LSP-Server und im Linter, abschaltbar mit mcp.globalSettings in
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
/// Überspringen. Eine Meldung an den Client gibt es nicht (MCP-Clients kennen atlas/crashCase nicht).</summary>
function NewCrashCases(const ALogger: ILogger; const ARecent: IJsonRpcRecentMessages; const ARoot: string):
  TShellCrashCases;
var
  mRoot: string;
begin
  mRoot := ARoot;
  Result := TShellCrashCases.Create('', ALogger, nil, ARecent);
  Result.AtlasVersion := TProductVersion.cVersion;
  Result.ServerPath := ParamStr(0);
  Result.Client := 'MCP-Client';
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

/// <summary>Abgeschaltete Werkzeuge: mcp.disabledTools und die Werkzeuge abgeschalteter Funktionen (#227).</summary>
function DisabledTools(const ASettings: TServerSettings): TArray<string>;
var
  mOff: TList<string>;
begin
  mOff := TList<string>.Create;
  try
    mOff.AddRange(ASettings.McpDisabledTools);
    if not ASettings.ArchitectureEnabled then
    begin
      mOff.Add('get_architecture');
    end;
    if not ASettings.HotspotsEnabled then
    begin
      mOff.Add('get_hotspots');
    end;
    if not ASettings.Navigation.SymbolPath then
    begin
      mOff.Add('find_path');
    end;
    // Betroffene Tests (#1353).
    if not ASettings.Tests.Affected then
    begin
      mOff.Add('get_affected_tests');
    end;
    if not ASettings.QueryEnabled then
    begin
      mOff.Add('query_code');
    end;
    Result := mOff.ToArray;
  finally
    mOff.Free;
  end;
end;

function DisabledToolsOf(AWorkspace: TShellWorkspace): TFunc<TArray<string>>;
begin
  Result :=
    function: TArray<string>
    begin
      Result := DisabledTools(AWorkspace.Configuration.Settings);
    end;
end;

function ServerAuditOf(const ALogger: ILogger): TProc<string>;
var
  mLogger: ILogger;
begin
  mLogger := ALogger;
  Result :=
    procedure(AText: string)
    begin
      mLogger.Info(AText);
    end;
end;

/// <summary>Vor jedem Werkzeugaufruf geänderte Projektdateien nachladen (#48).</summary>
function BeforeToolCallOf(const AServices: TMcpServices; const ALogger: ILogger): TProc;
var
  mServices: TMcpServices;
  mLogger: ILogger;
  mAllFiles: TFunc<TArray<string>>;
begin
  mServices := AServices;
  mLogger := ALogger;
  mAllFiles := AServices.AllFiles();
  Result :=
    procedure
    var
      mChanges: TArray<TFileChange>;
    begin
      mChanges := TMcpFreshness.Changes(mServices.Index, TDiskIndexFileSystem.Create, mAllFiles());
      if Length(mChanges) > 0 then
      begin
        mLogger.Info(cTexts[TMcpStartupText.Reloaded].Fmt([Length(mChanges),
          mServices.Workspace.ApplyChanges(mChanges)]));
        mServices.Group.Invalidate;
      end;
    end;
end;

procedure ConfigureServer(AServer: TMcpServer; const AServices: TMcpServices; ARestricted: Boolean;
  const ALogger: ILogger);
begin
  RegisterContextTools(AServices.ToolContext(AServer));
  AServer.Restricted := ARestricted;
  AServer.OnDisabledTools := DisabledToolsOf(AServices.Workspace);
  AServer.OnAudit := ServerAuditOf(ALogger);
  TMcpConventions.Register(AServer, AServices.Workspace);
  AServer.OnBeforeToolCall := BeforeToolCallOf(AServices, ALogger);
end;

function PromptSettingsOf(AWorkspace: TShellWorkspace): TFunc<TServerSettings>;
begin
  Result :=
    function: TServerSettings
    begin
      Result := AWorkspace.Configuration.Settings;
    end;
end;

function ResolveFileOf(AGuard: TMcpPathGuard): TFunc<string, string>;
begin
  Result :=
    function(APath: string): string
    begin
      Result := AGuard.Resolve(APath);
    end;
end;

function NewPrompts(AServer: TMcpServer; const AServices: TMcpServices): TMcpPrompts;
begin
  Result := TMcpPrompts.Create(AServer, PromptSettingsOf(AServices.Workspace));
  Result.ReadText := ReadSourceText;
  Result.ResolveFile := ResolveFileOf(AServices.Guard);
  Result.ResolveUnit := UnitFileOf(AServices.Index, AServices.Group, AServices.Guard);
  Result.Changes := ChangesOf(AServices.Group, AServices.Root);
  Result.Register;
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.Startup', cTexts);

end.
