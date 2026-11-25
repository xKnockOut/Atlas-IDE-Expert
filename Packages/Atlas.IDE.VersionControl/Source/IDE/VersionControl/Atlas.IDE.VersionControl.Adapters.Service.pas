unit Atlas.IDE.VersionControl.Adapters.Service;

// Dienst der Versionsverwaltung für Base und andere Module (#1891): TAtlasVcsServiceAdapter erfüllt IAtlasVcsService
// (Atlas.IDE.Base.Foundation.VersionControl) über TAtlasIdeVcsCore. Die Composition setzt ihn bei TAtlasIdeVcs ein und
// stellt ihn über den Scope des Moduls bereit.

interface

uses
  System.SysUtils,
  Atlas.VersionControl.Repository.Contract,
  Atlas.VersionControl.Repository.Tools,
  Atlas.VersionControl.Repository.ToolCheck,
  Atlas.VersionControl.Repository.ServerCheck,
  Atlas.Plugin.Projects.VersionControl,
  Atlas.IDE.Base.Foundation.VersionControl;

type
  /// <summary>IAtlasVcsService über TAtlasIdeVcsCore.</summary>
  TAtlasVcsServiceAdapter = class(TInterfacedObject, IAtlasVcsService)
  public
    procedure Report(const AText: string);
    function Provider: TAtlasVcsProvider;
    function TimeoutMs: Cardinal;
    procedure Reload;
    function ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
    function MainBranchOf(const AProjectFile, AGroupFile: string): string;
    function Projects: TArray<TAtlasVcsProjectMapping>;
    function Run(const AWork, ADone: TProc): Boolean;
    function Locate(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation;
    function CheckTool(AKind: TAtlasVcsKind; const APath: string; const ADone: TProc<TAtlasVcsToolCheck>): Boolean;
    function QueryProject(const AProjectFile, AGroupFile: string; const ADone: TProc<TAtlasVcsProjectState>): Boolean;
    function CheckServer(const AFolder: string; const ADone: TProc<TAtlasVcsServerCheck>): Boolean;
    function ServerState(const AFolder: string): TAtlasVcsServerCheck;
    function OpenServerLogin(const ACheck: TAtlasVcsServerCheck; const AClosed: TProc): Boolean;
  end;

implementation

uses
  Atlas.IDE.VersionControl.Service;

{ TAtlasVcsServiceAdapter }

procedure TAtlasVcsServiceAdapter.Report(const AText: string);
begin
  TAtlasIdeVcsCore.Report(AText);
end;

function TAtlasVcsServiceAdapter.Provider: TAtlasVcsProvider;
begin
  Result := TAtlasIdeVcsCore.Provider;
end;

function TAtlasVcsServiceAdapter.TimeoutMs: Cardinal;
begin
  Result := TAtlasIdeVcsCore.TimeoutMs;
end;

procedure TAtlasVcsServiceAdapter.Reload;
begin
  TAtlasIdeVcsCore.Reload;
end;

function TAtlasVcsServiceAdapter.ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
begin
  Result := TAtlasIdeVcsCore.ForFolder(AFolder, ATimeoutMs);
end;

function TAtlasVcsServiceAdapter.MainBranchOf(const AProjectFile, AGroupFile: string): string;
begin
  Result := TAtlasIdeVcsCore.MainBranchOf(AProjectFile, AGroupFile);
end;

function TAtlasVcsServiceAdapter.Projects: TArray<TAtlasVcsProjectMapping>;
begin
  Result := TAtlasIdeVcsCore.Projects;
end;

function TAtlasVcsServiceAdapter.Run(const AWork, ADone: TProc): Boolean;
begin
  Result := TAtlasIdeVcsCore.Run(AWork, ADone);
end;

function TAtlasVcsServiceAdapter.Locate(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation;
begin
  Result := TAtlasIdeVcsCore.Locate(AKind, APath);
end;

function TAtlasVcsServiceAdapter.CheckTool(AKind: TAtlasVcsKind; const APath: string;
  const ADone: TProc<TAtlasVcsToolCheck>): Boolean;
begin
  Result := TAtlasIdeVcsCore.CheckTool(AKind, APath, ADone);
end;

function TAtlasVcsServiceAdapter.QueryProject(const AProjectFile, AGroupFile: string;
  const ADone: TProc<TAtlasVcsProjectState>): Boolean;
begin
  Result := TAtlasIdeVcsCore.QueryProject(AProjectFile, AGroupFile, ADone);
end;

function TAtlasVcsServiceAdapter.CheckServer(const AFolder: string;
  const ADone: TProc<TAtlasVcsServerCheck>): Boolean;
begin
  Result := TAtlasIdeVcsCore.CheckServer(AFolder, ADone);
end;

function TAtlasVcsServiceAdapter.ServerState(const AFolder: string): TAtlasVcsServerCheck;
begin
  Result := TAtlasIdeVcsCore.ServerState(AFolder);
end;

function TAtlasVcsServiceAdapter.OpenServerLogin(const ACheck: TAtlasVcsServerCheck; const AClosed: TProc): Boolean;
begin
  Result := TAtlasIdeVcsCore.OpenServerLogin(ACheck, AClosed);
end;

end.
