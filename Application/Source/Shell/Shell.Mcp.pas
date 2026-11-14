unit Shell.Mcp;

// Host-Rolle Shell: MCP-Modus (--mcp, #48). Bietet den Symbolindex eines
// Projektordners über das Model Context Protocol an, z. B. für KI-Assistenten (MCP):
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
  System.JSON,
  Atlas.Common.Product.Version,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.JsonRpc.Connection,
  Atlas.Common.JsonRpc.LineTransport,
  Atlas.Common.JsonRpc.RecentMessages,
  Atlas.Common.Lsp.ServerActivity,
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Prompts,
  Shell.Platform,
  Shell.CrashCases,
  Shell.WorkspaceGroup,
  Shell.Mcp.Context,
  Shell.Mcp.Services,
  Shell.Mcp.Tools,
  Shell.Mcp.Startup,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpHostText = (Instructions);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpHostText] of TAtlasText = (
    (De: 'Delphi-Projekt in %s. Für Fragen zu Typen, Units und Formularen zuerst diese Werkzeuge nutzen statt ' +
    'Quelldateien vollständig zu lesen.';
    En: 'Delphi project in %s. For questions about types, units and forms, use these tools first instead of ' +
    'reading source files completely.'));

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

function ConnectionErrorOf(const ALogger: ILogger): TJsonRpcErrorEvent;
var
  mLogger: ILogger;
begin
  mLogger := ALogger;
  Result :=
    procedure(const AError: Exception)
    begin
      mLogger.Error(Format('MCP: %s: %s', [AError.ClassName, TLogMarks.Text(AError.Message)]));
    end;
end;

/// <summary>Name aus clientInfo für „Prozesse am Projekt“ und Absturzfälle (#1883).</summary>
function ClientInfoOf(AGroup: TShellWorkspaceGroup; ACrashCases: TShellCrashCases): TProc<string>;
begin
  Result :=
    procedure(AClient: string)
    begin
      AGroup.SetClient(AClient);
      ACrashCases.Client := AClient;
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
      ALogger.Error('MCP-Server abgebrochen: ' + TLogMarks.Text(E.Message));
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
  mServer := TMcpServer.Create(TProductVersion.cName, TProductVersion.cVersion);
  mPrompts := nil;
  mDispatcher := TJsonRpcDispatcher.Create;
  mConnection := TJsonRpcConnection.Create(mTransport, mDispatcher);
  mRecent := TJsonRpcRecentMessages.Create;
  mDispatcher.Recent := mRecent;
  mCrashCases := NewCrashCases(mLogger, mRecent, mServices.Root);
  mDispatcher.OnRequestFailed := RequestFailedOf(mCrashCases, mServices.Workspace);
  // Statusdatei (#1901): Ordner des Servers, laufende Werkzeuge, server.statusFile aus den Einstellungen.
  TServerActivity.Shared.Describe(TServerStatusEntry.cKindMcp, '', mServices.Root);
  TServerActivity.Shared.Enabled := mServices.Workspace.Configuration.Settings.ServerStatusFile;
  mDispatcher.Observer := TServerActivityObserver.Create(TServerActivity.Shared, nil);
  try
    mServer.Instructions := cTexts[TMcpHostText.Instructions].Fmt([mServices.Root]);
    ConfigureServer(mServer, mServices, AOptions.Restricted, mLogger);
    mServer.OnClientInfo := ClientInfoOf(mServices.Group, mCrashCases);
    mPrompts := NewPrompts(mServer, mServices);
    mServer.Attach(mDispatcher);
    mConnection.OnError := ConnectionErrorOf(mLogger);
    mLogger.Info(Format('%s %s im MCP-Modus für %s', [TProductVersion.cName, TProductVersion.cVersion,
      TLogMarks.Path(mServices.Root)]));
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

initialization
  TAtlasTextTables.Add('Shell.Mcp', cTexts);

end.
