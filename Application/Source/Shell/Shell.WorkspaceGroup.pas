unit Shell.WorkspaceGroup;

// Host-Rolle Shell: Arbeitsbereiche ohne LSP-Client für MCP-Modus und Linter
// (#1112). Ein Ordner mit seinem Projekt und, mit index.projectGroup, den
// übrigen Projekten der Projektgruppe, alle in einem Symbolindex wie im
// LSP-Server. Für die Prüfregeln liefert RuleProject den Projektkontext einer
// Datei mit Index, Nachladen über alle Projekte und den Projekten der Gruppe:
// derselbe Weg wie TServerComposition.RuleContextFor, damit IDE, MCP und
// --check dieselben Befunde haben. Der Index ist das Herzstück: Ohne ihn
// schweigen Regeln, die Typen aus anderen Units oder der RTL brauchen.

interface

uses
  System.SysUtils,
  System.SyncObjs,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Processes,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.ProjectFiles,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesService,
  Shell.Workspace;

type
  TShellWorkspaceGroup = class
  private
    FRoot: string;
    FStore: IDocumentStore;
    FTransport: IJsonRpcTransport;
    FLogger: ILogger;
    FIndex: ISymbolIndex;
    FProgressToken: string;
    FReadText: TRuleProjectReadText;
    FMain: TShellWorkspace;
    FOthers: TObjectList<TShellWorkspace>;
    FProcessIdentity: TIndexProcessInfo;
    FCacheRoot: string;
    /// <summary>Arbeitsbereiche, deren Indexaufbau seit Load fertig ist; unter FLock.</summary>
    FFinished: TList<TShellWorkspace>;
    FFinishedEvent: TEvent;
    FLock: TObject;
    /// <summary>Projekte der Gruppe für projektweite Regeln (#1102), bis Invalidate; unter FLock.</summary>
    FRuleProjects: TArray<TRuleProject>;
    FHasRuleProjects: Boolean;
    /// <summary>Uses-Graph über FIndex für projektweite Regeln (#64) und die MCP-Werkzeuge; einer für die Gruppe,
    /// statt je Prüfung einen eigenen aufzubauen.</summary>
    FUsesGraph: TUsesGraphService;
    function Workspaces: TArray<TShellWorkspace>;
    procedure Prepare(AWorkspace: TShellWorkspace);
    function RuleProjects: TArray<TRuleProject>;
  public
    /// <summary>AReadText liest Quelltexte (Hauptquelltexte der Projekte); Fortschritt und logMessage der
    /// Arbeitsbereiche gehen ins Leere, Meldungen an ALogger.</summary>
    constructor Create(const ARoot: string; const AStore: IDocumentStore; const ALogger: ILogger;
      const AIndex: ISymbolIndex; const AProgressToken: string; const AReadText: TRuleProjectReadText);
    destructor Destroy; override;
    /// <summary>Liest atlas.json, lädt das Projekt (ProjectFile oder im Ordner gesucht) und mit
    /// index.projectGroup die übrigen Projekte der Gruppe; startet den Indexaufbau.</summary>
    procedure Load(const AGlobalSettings: string);
    /// <summary>Hält alle Indexaufbauten an.</summary>
    procedure Stop;
    /// <summary>Wartet, bis der Index aller Projekte fertig ist; False nach ATimeoutMs.</summary>
    function WaitForIndex(ATimeoutMs: Cardinal): Boolean;
    /// <summary>Projekte geladen und Index fertig? Sonst der Grund in AReason.</summary>
    function Ready(out AReason: string): Boolean;
    /// <summary>Projektdateien aller Projekte der Gruppe.</summary>
    function AllFiles: TArray<string>;
    /// <summary>Lädt AUnitName über die Suchpfade des ersten Projekts nach, das sie findet.</summary>
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>Arbeitsbereich, zu dem AFileName gehört, sonst der Hauptarbeitsbereich.</summary>
    function WorkspaceOf(const AFileName: string): TShellWorkspace;
    /// <summary>Projektkontext für die Prüfregeln (#1112): Anwendungsart, Formulare der .dpr und die Dienste
    /// mit Index, Nachladen über alle Projekte und den Projekten der Gruppe.</summary>
    function RuleProject(const AFileName: string): TCheckProject;
    /// <summary>Projekte der Gruppe für projektweite Regeln (#1102, #64) mit dem Uses-Graphen der Gruppe; still,
    /// solange Projekte laden oder der Index läuft.</summary>
    function RuleProjectFiles: IRuleProjectFiles;
    /// <summary>Uses-Graph der Gruppe (#64) mit den Namensräumen des Hauptprojekts; neu aufgebaut wird er nur bei
    /// einer Änderung.</summary>
    function UsesGraph: TUsesGraphService;
    /// <summary>Projekte der Gruppe neu ermitteln (nach geänderten Projektdateien).</summary>
    procedure Invalidate;
    property Main: TShellWorkspace read FMain;
    /// <summary>Symbolindex aller Projekte der Gruppe.</summary>
    property Index: ISymbolIndex read FIndex;
    /// <summary>Vor Load setzen (#62): Anmeldung am Index-Cache.</summary>
    property ProcessIdentity: TIndexProcessInfo read FProcessIdentity write FProcessIdentity;
    /// <summary>Vor Load setzen (#1112): Ordner der Index-Caches.</summary>
    property CacheRoot: string read FCacheRoot write FCacheRoot;
  end;

implementation

uses
  System.Classes,
  System.Diagnostics,
  System.JSON,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Shell.Bootstrap;

type
  /// <summary>Nimmt die LSP-Benachrichtigungen der Arbeitsbereiche (Fortschritt, logMessage) auf und verwirft
  /// sie; ohne LSP-Client gibt es niemanden, der sie liest.</summary>
  TSilentTransport = class(TInterfacedObject, IJsonRpcTransport)
  public
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
  end;

function TSilentTransport.ReadMessage: TJSONObject;
begin
  raise EJsonRpcTransportClosed.Create('Kein LSP-Client');
end;

procedure TSilentTransport.WriteMessage(const AMessage: TJSONObject);
begin
end;

{ TShellWorkspaceGroup }

constructor TShellWorkspaceGroup.Create(const ARoot: string; const AStore: IDocumentStore; const ALogger: ILogger;
  const AIndex: ISymbolIndex; const AProgressToken: string; const AReadText: TRuleProjectReadText);
begin
  inherited Create;
  FRoot := ARoot;
  FStore := AStore;
  FLogger := ALogger;
  FIndex := AIndex;
  FProgressToken := AProgressToken;
  FReadText := AReadText;
  FTransport := TSilentTransport.Create;
  FLock := TObject.Create;
  FFinished := TList<TShellWorkspace>.Create;
  FFinishedEvent := TEvent.Create(nil, False, False, '');
  FOthers := TObjectList<TShellWorkspace>.Create(True);
  FCacheRoot := TIndexCacheDirectory.DefaultRoot;
  FMain := TShellWorkspace.Create(ARoot, ExtractFileName(ARoot), AStore, FTransport, ALogger, AIndex, AProgressToken);
  FUsesGraph := TUsesGraphService.Create(AIndex, TUsesGraphOptions.Default);
end;

destructor TShellWorkspaceGroup.Destroy;
begin
  FUsesGraph.Free;
  FOthers.Free;
  FMain.Free;
  FFinishedEvent.Free;
  FFinished.Free;
  FLock.Free;
  inherited;
end;

procedure TShellWorkspaceGroup.Prepare(AWorkspace: TShellWorkspace);
begin
  AWorkspace.ProcessIdentity := FProcessIdentity;
  AWorkspace.CacheRoot := FCacheRoot;
  AWorkspace.OnIndexFinished :=
    procedure
    begin
      System.TMonitor.Enter(FLock);
      try
        if not FFinished.Contains(AWorkspace) then
          FFinished.Add(AWorkspace);
        FHasRuleProjects := False;
      finally
        System.TMonitor.Exit(FLock);
      end;
      FFinishedEvent.SetEvent;
    end;
end;

procedure TShellWorkspaceGroup.Load(const AGlobalSettings: string);
var
  Info: TProjectInfo;
  ProjectFile: string;
  Other: TShellWorkspace;
begin
  Prepare(FMain);
  FMain.Load(AGlobalSettings);
  // Übrige Projekte der Gruppe (index.projectGroup, Standard an): Sonst fehlen z. B. Units, die nur ein
  // Package enthält, wenn atlas.json auf ein anderes Projekt zeigt.
  if not FMain.Configuration.Settings.IndexProjectGroup then
    Exit;
  for ProjectFile in TShellBootstrap.GroupProjects(FRoot, FLogger) do
  begin
    if FMain.Project(Info) and SameText(Info.FileName, ProjectFile) then
      Continue;
    Other := TShellWorkspace.Create(ExtractFileDir(ProjectFile), ChangeFileExt(ExtractFileName(ProjectFile), ''),
      FStore, FTransport, FLogger, FIndex, Format('%s-%d', [FProgressToken, FOthers.Count + 1]));
    Other.ProjectFile := ProjectFile;
    Prepare(Other);
    FOthers.Add(Other);
    Other.Load(AGlobalSettings);
  end;
end;

procedure TShellWorkspaceGroup.Stop;
var
  Workspace: TShellWorkspace;
begin
  for Workspace in FOthers do
    Workspace.Stop;
  FMain.Stop;
end;

function TShellWorkspaceGroup.Workspaces: TArray<TShellWorkspace>;
var
  Other: TShellWorkspace;
begin
  Result := [FMain];
  for Other in FOthers do
    Result := Result + [Other];
end;

function TShellWorkspaceGroup.WaitForIndex(ATimeoutMs: Cardinal): Boolean;
var
  Workspace: TShellWorkspace;
  Info: TProjectInfo;
  Watch: TStopwatch;
  Missing: Boolean;
begin
  Watch := TStopwatch.StartNew;
  repeat
    // Nur Arbeitsbereiche mit Projekt bauen einen Index; ohne Projekt gibt es nichts abzuwarten.
    Missing := False;
    System.TMonitor.Enter(FLock);
    try
      for Workspace in Workspaces do
        if Workspace.Project(Info) and not FFinished.Contains(Workspace) then
          Missing := True;
    finally
      System.TMonitor.Exit(FLock);
    end;
    if not Missing then
      Exit(True);
    if Watch.ElapsedMilliseconds >= ATimeoutMs then
      Exit(False);
    FFinishedEvent.WaitFor(200);
  until False;
end;

function TShellWorkspaceGroup.Ready(out AReason: string): Boolean;
var
  Workspace: TShellWorkspace;
begin
  AReason := '';
  for Workspace in Workspaces do
    if not Workspace.RuleReady(AReason) then
      Exit(False);
  Result := True;
end;

function TShellWorkspaceGroup.AllFiles: TArray<string>;
var
  Workspace: TShellWorkspace;
begin
  Result := nil;
  for Workspace in Workspaces do
    Result := Result + Workspace.ProjectFiles;
end;

function TShellWorkspaceGroup.EnsureUnit(const AUnitName: string): Boolean;
var
  Workspace: TShellWorkspace;
begin
  for Workspace in Workspaces do
    if Workspace.EnsureUnit(AUnitName) then
      Exit(True);
  Result := False;
end;

function TShellWorkspaceGroup.WorkspaceOf(const AFileName: string): TShellWorkspace;
var
  Workspace: TShellWorkspace;
begin
  for Workspace in Workspaces do
    if Workspace.ContainsFile(AFileName) then
      Exit(Workspace);
  Result := FMain;
end;

procedure TShellWorkspaceGroup.Invalidate;
begin
  System.TMonitor.Enter(FLock);
  try
    FHasRuleProjects := False;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceGroup.RuleProjects: TArray<TRuleProject>;
var
  Workspace: TShellWorkspace;
  Project: TRuleProject;
  MainSource: string;
begin
  System.TMonitor.Enter(FLock);
  try
    if FHasRuleProjects then
      Exit(FRuleProjects);
  finally
    System.TMonitor.Exit(FLock);
  end;
  Result := nil;
  for Workspace in Workspaces do
    if Workspace.RuleProject(Project, MainSource) then
    begin
      Result := Result + [TRuleProjectFiles.ProjectOf(Project.FileName, MainSource, Project.Sources, FReadText)];
    end;
  System.TMonitor.Enter(FLock);
  try
    FRuleProjects := Result;
    FHasRuleProjects := True;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceGroup.RuleProject(const AFileName: string): TCheckProject;
var
  Workspace, Other: TShellWorkspace;
  Info: TProjectInfo;
  Projects: TArray<TProjectInfo>;
begin
  // Alle Projekte der Gruppe, die die Datei enthalten, das gewählte zuerst: Eine Unit im Testprogramm und
  // im Package hat keine eindeutige Anwendungsart (MergeRuleProjects).
  Workspace := WorkspaceOf(AFileName);
  Projects := nil;
  if Workspace.Project(Info) then
    Projects := Projects + [Info];
  for Other in Workspaces do
    if (Other <> Workspace) and Other.ContainsFile(AFileName) and Other.Project(Info) then
      Projects := Projects + [Info];
  Result := TShellWorkspace.RuleProjectOf(Projects, AFileName, FReadText);
  Result.Services := Workspace.RuleServices;
  // Nachladen über alle Projekte der Gruppe und projektweite Regeln (#1102) wie im Server.
  Result.Services.EnsureUnit :=
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end;
  Result.Services.ProjectFiles := RuleProjectFiles;
end;

function TShellWorkspaceGroup.UsesGraph: TUsesGraphService;
var
  mOptions: TUsesGraphOptions;
begin
  mOptions := FUsesGraph.Options;
  if string.Join(';', mOptions.Namespaces) <> string.Join(';', FMain.Namespaces) then
  begin
    mOptions.Namespaces := FMain.Namespaces;
    FUsesGraph.SetOptions(mOptions);
  end;
  Result := FUsesGraph;
end;

function TShellWorkspaceGroup.RuleProjectFiles: IRuleProjectFiles;
begin
  Result := TRuleProjectFiles.Create(RuleProjects, FIndex, FReadText,
    function(out AReason: string): Boolean
    begin
      Result := Ready(AReason);
    end,
    UsesGraph);
end;

end.
