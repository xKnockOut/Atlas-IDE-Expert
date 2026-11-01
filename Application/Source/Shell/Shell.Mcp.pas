unit Shell.Mcp;

// Host-Rolle Shell: MCP-Modus (--mcp, #48). Bietet den Symbolindex eines
// Projektordners über das Model Context Protocol an, z. B. für Claude Code:
//
//   claude mcp add delphi -- AtlasServer.exe --mcp --root C:\Projekte\App
//
// stdout gehört dem Protokoll (eine JSON-Nachricht je Zeile); Meldungen gehen
// auf stderr und in die Logdatei.
// Sicherheit (#99): mcp.disabledTools aus atlas.json, --restricted schaltet
// schreibende Werkzeuge ab, schreibende Aufrufe stehen im Log. Ungespeicherte
// Dateien der IDE meldet das Plugin in %LOCALAPPDATA%\Atlas\editor-dirty-<pid>.json.
// Formatieren (format_code, #1358) mit den Formatregeln des Projekts, zu dem die Datei gehört.
// Prüfregeln (get_diagnostics, check_code, explain_finding, apply_code_action, fix_findings)
// bekommen den Symbolindex und die Projektdienste über TShellWorkspaceGroup wie
// im Server (#1112); solange der Index lädt, sagt get_diagnostics das dazu.
// get_server_status (#1356) zeigt den Status des Atlas-Servers der IDE für den
// Ordner (aus dessen Statusdatei), sonst den dieses Prozesses.
// Prompts und Ressourcenvorlagen (#1357) kommen aus TMcpPrompts; hier nur die
// Auflösung von Units und Pfaden (#99) und die Änderungen für prepare_commit.

interface

uses
  Shell.CommandLine;

type
  TMcpShell = class
  public
    /// <summary>Namen aller Werkzeuge, in der Reihenfolge von tools/list (für den Abgleich mit docs/MCP.md).</summary>
    class function ToolNames: TArray<string>; static;
    /// <summary>Läuft, bis der Client die Eingabe schließt; liefert den Exit-Code.</summary>
    class function Run(const AOptions: TCommandLineOptions): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Product.Version,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.JsonRpc.Connection,
  Atlas.Common.JsonRpc.LineTransport,
  Atlas.Common.JsonRpc.RecentMessages,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Adapters.DiskFileSystem,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Freshness,
  Atlas.Common.Mcp.Prompts,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Prompt,
  Atlas.Common.Rules.Conventions,
  Atlas.Common.Rules.Builtin,
  Shell.Platform,
  Shell.CrashCases,
  Shell.Workspace,
  Shell.Mcp.Context,
  Shell.Mcp.Services,
  Shell.Mcp.Tools,
  Shell.Mcp.Changes,
  Shell.Mcp.Startup;

class function TMcpShell.ToolNames: TArray<string>;
var
  mContext: TMcpToolContext;
  mServer: TMcpServer;
  mListed: TJSONObject;
  mTool: TJSONValue;
begin
  Result := nil;
  // Nur registrieren, nicht aufrufen: Die Werkzeuge greifen erst beim Aufruf auf ihre Dienste zu.
  mServer := TMcpServer.Create('Atlas', '0');
  try
    mContext := Default(TMcpToolContext);
    mContext.Server := mServer;
    RegisterContextTools(mContext);
    mListed := mServer.ListTools;
    try
      for mTool in mListed.GetValue<TJSONArray>('tools') do
      begin
        Result := Result + [mTool.GetValue<string>('name')];
      end;
    finally
      mListed.Free;
    end;
  finally
    mServer.Free;
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

/// <summary>Projektkonventionen (#272) als Markdown.</summary>
function ConventionsOf(AWorkspace: TShellWorkspace): TFunc<string>;
begin
  Result :=
    function: string
    var
      mCatalog: TRuleCatalog;
    begin
      mCatalog := TFindingPrompt.GermanCatalog;
      try
        Result := TRuleConventions.Markdown(BuiltinRules, AWorkspace.Configuration.Settings, mCatalog);
      finally
        mCatalog.Free;
      end;
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
  mAllFiles := AServices.AllFiles;
  Result :=
    procedure
    var
      mChanges: TArray<TFileChange>;
    begin
      mChanges := TMcpFreshness.Changes(mServices.Index, TDiskIndexFileSystem.Create, mAllFiles());
      if Length(mChanges) > 0 then
      begin
        mLogger.Info(Format('%d geänderte Dateien nachgeladen, %d Units aktualisiert',
          [Length(mChanges), mServices.Workspace.ApplyChanges(mChanges)]));
        mServices.Group.Invalidate;
      end;
    end;
end;

/// <summary>Werkzeuge, Sicherheit (#99), Konventionen und das Nachladen vor jedem Werkzeugaufruf.</summary>
procedure ConfigureServer(AServer: TMcpServer; const AServices: TMcpServices; ARestricted: Boolean;
  const ALogger: ILogger);
begin
  AServer.Instructions := 'Delphi-Projekt in ' + AServices.Root + '. Für Fragen zu Typen, Units und Formularen ' +
    'zuerst diese Werkzeuge nutzen statt Quelldateien vollständig zu lesen.';
  RegisterContextTools(AServices.ToolContext(AServer));
  AServer.Restricted := ARestricted;
  AServer.OnDisabledTools := DisabledToolsOf(AServices.Workspace);
  AServer.OnAudit := ServerAuditOf(ALogger);
  AServer.AddResource('delphi://conventions', 'Projektkonventionen',
    'Regelprofil, Formatstil, Benennungsregeln und aktive Prüfregeln des Projekts als Markdown.', 'text/markdown',
    ConventionsOf(AServices.Workspace));
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

/// <summary>Prompts und Ressourcenvorlagen (#1357), abschaltbar mit mcp.prompts.</summary>
function NewPrompts(AServer: TMcpServer; const AServices: TMcpServices): TMcpPrompts;
begin
  Result := TMcpPrompts.Create(AServer, PromptSettingsOf(AServices.Workspace));
  Result.ReadText := ReadSourceText;
  Result.ResolveFile := ResolveFileOf(AServices.Guard);
  Result.ResolveUnit := UnitFileOf(AServices.Index, AServices.Group, AServices.Guard);
  Result.Changes := ChangesOf(AServices.Group, AServices.Root);
  Result.Register;
end;

function ConnectionErrorOf(const ALogger: ILogger): TJsonRpcErrorEvent;
var
  mLogger: ILogger;
begin
  mLogger := ALogger;
  Result :=
    procedure(const AError: Exception)
    begin
      mLogger.Error(Format('MCP: %s: %s', [AError.ClassName, AError.Message]));
    end;
end;

/// <summary>Bedient den Client, bis er die Eingabe schließt; 1, wenn die Verbindung abbricht.</summary>
function Serve(AConnection: TJsonRpcConnection; const ALogger: ILogger): Integer;
begin
  try
    AConnection.Run;
    Result := 0;
  except
    on E: Exception do
    begin
      ALogger.Error('MCP-Server abgebrochen: ' + E.Message);
      Result := 1;
    end;
  end;
end;

class function TMcpShell.Run(const AOptions: TCommandLineOptions): Integer;
var
  mLogger: ILogger;
  mTransport: IJsonRpcTransport;
  mServices: TMcpServices;
  mGlobalSettings: string;
  mServer: TMcpServer;
  mPrompts: TMcpPrompts;
  mDispatcher: TJsonRpcDispatcher;
  mConnection: TJsonRpcConnection;
  mRecent: IJsonRpcRecentMessages;
  mCrashCases: TShellCrashCases;
begin
  mLogger := NewLogger(AOptions);
  // Ab hier erreichen versehentliche Ausgaben nur noch stderr.
  mTransport := TJsonRpcLineTransport.Create(TStdStreams.CreateInput, TStdStreams.ReserveOutputForProtocol, True);
  mServices := TMcpServices.Create(RootOf(AOptions), mLogger);
  mGlobalSettings := GlobalSettingsOf(mServices.Root, mLogger);
  mServer := TMcpServer.Create(TProductVersion.Name, TProductVersion.Version);
  mPrompts := nil;
  mDispatcher := TJsonRpcDispatcher.Create;
  mConnection := TJsonRpcConnection.Create(mTransport, mDispatcher);
  mRecent := TJsonRpcRecentMessages.Create;
  mDispatcher.Recent := mRecent;
  mCrashCases := NewCrashCases(mLogger, mRecent, mServices.Root);
  mDispatcher.OnRequestFailed := RequestFailedOf(mCrashCases, mServices.Workspace);
  try
    ConfigureServer(mServer, mServices, AOptions.Restricted, mLogger);
    mPrompts := NewPrompts(mServer, mServices);
    mServer.Attach(mDispatcher);
    mConnection.OnError := ConnectionErrorOf(mLogger);
    mLogger.Info(Format('%s %s im MCP-Modus für %s', [TProductVersion.Name, TProductVersion.Version,
      mServices.Root]));
    // Mit index.projectGroup auch die übrigen Projekte der Gruppe.
    mServices.Group.Load(mGlobalSettings);
    Result := Serve(mConnection, mLogger);
    mServices.Group.Stop;
  finally
    mConnection.Free;
    mDispatcher.Free;
    mCrashCases.Free;
    mServer.Free;
    mPrompts.Free;
    mServices.Free;
  end;
end;

end.
