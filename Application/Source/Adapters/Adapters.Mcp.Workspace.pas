unit Adapters.Mcp.Workspace;

// Host-Adapter zwischen Mcp und dem Host: Die MCP-Werkzeuge lesen den Arbeitsbereich über IMcpWorkspace, der Host
// hält ihn in der Arbeitsbereichsgruppe (TCoreWorkspaceGroup). Erzeugt nur in Shell.*; kennt nur den Contract und
// die Gruppe.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Query.Contract,
  Mcp.Contract.Workspace,
  Core.WorkspaceGroup;

type
  TMcpWorkspaceAdapter = class(TInterfacedObject, IMcpWorkspace)
  private
    FGroup: TCoreWorkspaceGroup;
  public
    /// <summary>AGroup gehört dem Aufrufer und lebt länger als der Adapter.</summary>
    constructor Create(AGroup: TCoreWorkspaceGroup);
    /// <summary>Neuer Adapter über AGroup als Interface (ohne Leck bei direkter Übergabe).</summary>
    class function ForGroup(AGroup: TCoreWorkspaceGroup): IMcpWorkspace; static;
    function Settings: TServerSettings;
    function SettingsOf(const AFileName: string): TServerSettings;
    function SettingsFile: string;
    function GlobalSettingsFile: string;
    function Namespaces: TArray<string>;
    function ProjectFiles: TArray<string>;
    function AllFiles: TArray<string>;
    function Ready(out AReason: string): Boolean;
    function Client: string;
    function Index: ISymbolIndex;
    function EnsureUnit(const AUnitName: string): Boolean;
    function UnitLoader: TEnsureUnitFunc;
    function CheckSource(const AFileName: string): TPascalSource;
    function Queries: ICodeQueries;
  end;

implementation

uses
  Core.Bootstrap;

{ TMcpWorkspaceAdapter }

constructor TMcpWorkspaceAdapter.Create(AGroup: TCoreWorkspaceGroup);
begin
  inherited Create;
  FGroup := AGroup;
end;

class function TMcpWorkspaceAdapter.ForGroup(AGroup: TCoreWorkspaceGroup): IMcpWorkspace;
begin
  Result := TMcpWorkspaceAdapter.Create(AGroup);
end;

function TMcpWorkspaceAdapter.Settings: TServerSettings;
begin
  Result := FGroup.Main.Configuration.Settings;
end;

function TMcpWorkspaceAdapter.SettingsOf(const AFileName: string): TServerSettings;
begin
  Result := FGroup.WorkspaceOf(AFileName).Configuration.Settings;
end;

function TMcpWorkspaceAdapter.SettingsFile: string;
begin
  Result := FGroup.Main.Configuration.Files.Read;
end;

function TMcpWorkspaceAdapter.GlobalSettingsFile: string;
begin
  Result := TCoreBootstrap.GlobalSettingsFile;
end;

function TMcpWorkspaceAdapter.Namespaces: TArray<string>;
begin
  Result := FGroup.Main.State.Namespaces;
end;

function TMcpWorkspaceAdapter.ProjectFiles: TArray<string>;
begin
  Result := FGroup.Main.State.ProjectFiles;
end;

function TMcpWorkspaceAdapter.AllFiles: TArray<string>;
begin
  Result := FGroup.AllFiles;
end;

function TMcpWorkspaceAdapter.Ready(out AReason: string): Boolean;
begin
  Result := FGroup.Ready(AReason);
end;

function TMcpWorkspaceAdapter.Client: string;
begin
  Result := FGroup.ProcessIdentity.Client;
end;

function TMcpWorkspaceAdapter.Index: ISymbolIndex;
begin
  Result := FGroup.Index;
end;

function TMcpWorkspaceAdapter.EnsureUnit(const AUnitName: string): Boolean;
begin
  Result := FGroup.EnsureUnit(AUnitName);
end;

function TMcpWorkspaceAdapter.UnitLoader: TEnsureUnitFunc;
begin
  Result := FGroup.UnitLoader();
end;

function TMcpWorkspaceAdapter.CheckSource(const AFileName: string): TPascalSource;
begin
  Result := FGroup.Main.State.CheckSource(AFileName);
end;

function TMcpWorkspaceAdapter.Queries: ICodeQueries;
begin
  Result := FGroup.Queries;
end;

end.
