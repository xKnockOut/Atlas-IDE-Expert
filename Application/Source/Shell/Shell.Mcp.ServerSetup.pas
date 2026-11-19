unit Shell.Mcp.ServerSetup;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Einrichtung des Servers: Werkzeuge und Sicherheit (#99), abgeschaltete
// Werkzeuge (#227), Konventionen, Nachladen geänderter Dateien vor jedem Werkzeugaufruf, batch (#2638) und die
// Prompts (#1357).

interface

uses
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Prompts,
  Shell.Mcp.Services;

/// <summary>Abgeschaltete Werkzeuge: mcp.disabledTools und die Werkzeuge abgeschalteter Funktionen (#227).</summary>
function DisabledTools(const ASettings: TServerSettings): TArray<string>;
/// <summary>Werkzeuge, Sicherheit (#99), Konventionen und das Nachladen vor jedem Werkzeugaufruf.</summary>
procedure ConfigureServer(AServer: TMcpServer; const AServices: TMcpServices; ARestricted: Boolean;
  const ALogger: ILogger);
/// <summary>Prompts und Ressourcenvorlagen (#1357), abschaltbar mit mcp.prompts.</summary>
function NewPrompts(AServer: TMcpServer; const AServices: TMcpServices): TMcpPrompts;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Adapters.DiskFileSystem,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.CurrentRequest,
  Atlas.Common.Mcp.Freshness,
  Atlas.Common.Mcp.Paths,
  Atlas.Common.Mcp.BatchTool,
  Atlas.Common.Localization.Texts,
  Shell.Workspace,
  Shell.Mcp.Context,
  Shell.Mcp.RefactorSources,
  Shell.Mcp.Tools,
  Shell.Mcp.Changes,
  Shell.Mcp.Conventions;

type
{$SCOPEDENUMS ON}
  TMcpServerSetupText = (Reloaded);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpServerSetupText] of TAtlasText = (
    (De: '%d geänderte Dateien nachgeladen, %d Units aktualisiert'; En: '%d changed files reloaded, %d units updated'));

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
        mLogger.Info(cTexts[TMcpServerSetupText.Reloaded].Fmt([Length(mChanges),
          mServices.Workspace.ApplyChanges(mChanges)]));
        mServices.Group.Invalidate;
      end;
    end;
end;

/// <summary>Grenzen von batch (#2638): requestTimeoutMs und Abbruch über notifications/cancelled.</summary>
function BatchLimitsOf(AWorkspace: TShellWorkspace): TFunc<TMcpBatchLimits>;
begin
  Result :=
    function: TMcpBatchLimits
    var
      Token: IJsonRpcCancellationToken;
    begin
      Result := Default(TMcpBatchLimits);
      Result.TimeoutMs := AWorkspace.Configuration.Settings.RequestTimeoutMs;
      Token := TJsonRpcCurrentRequest.Token;
      Result.Cancelled :=
        function: Boolean
        begin
          Result := (Token <> nil) and Token.IsCancellationRequested;
        end;
    end;
end;

procedure ConfigureServer(AServer: TMcpServer; const AServices: TMcpServices; ARestricted: Boolean;
  const ALogger: ILogger);
var
  mContext: TMcpToolContext;
begin
  mContext := AServices.ToolContext(AServer);
  TMcpRefactorSources.Attach(mContext, ALogger);
  RegisterContextTools(mContext);
  TMcpBatchTool.Register(AServer, BatchLimitsOf(AServices.Workspace));
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
  TAtlasTextTables.Add('Shell.Mcp.ServerSetup', cTexts);

end.
