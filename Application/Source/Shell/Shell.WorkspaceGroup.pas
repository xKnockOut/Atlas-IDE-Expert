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
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Query.Contract,
  Shell.Workspace;

type
  /// <summary>Gemerkte Projekte der Gruppe für projektweite Regeln (#1102); Valid bis Invalidate.</summary>
  TShellRuleProjectCache = record
    Items: TArray<TRuleProject>;
    Valid: Boolean;
  end;

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
    FRuleProjects: TShellRuleProjectCache;
    /// <summary>Uses-Graph über FIndex für projektweite Regeln (#64) und die MCP-Werkzeuge; einer für die Gruppe,
    /// statt je Prüfung einen eigenen aufzubauen.</summary>
    FUsesGraph: TUsesGraphService;
    /// <summary>Code-Abfragen über alle Projekte der Gruppe (#1351) für query_code, --query und die Regeln
    /// query:&lt;name&gt;; ein Dienst, damit ein Ergebnis je Index-Stand einmal gerechnet wird.</summary>
    FQueries: ICodeQueries;
    function Workspaces: TArray<TShellWorkspace>;
    function QuerySource(out ASource: TQuerySource): Boolean;
    procedure Prepare(AWorkspace: TShellWorkspace);
    function RuleProjects: TArray<TRuleProject>;
  public
    /// <summary>Name des Clients für alle Arbeitsbereiche, auch nach Load (#1883).</summary>
    procedure SetClient(const AClient: string);
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
    /// <summary>Code-Abfragen über alle Projekte der Gruppe (#1351) mit dem Index, den Namensräumen des
    /// Hauptprojekts und der Aufrufhierarchie.</summary>
    function Queries: ICodeQueries;
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
  Atlas.Common.Architecture.UsesGraph,
  System.Classes,
  System.Diagnostics,
  System.JSON,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Query.Service,
  Atlas.Common.Lsp.Query,
  Shell.Bootstrap,
  Shell.Workspace.Setup,
  Shell.Workspace.RuleProjects;

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
  FMain := TShellWorkspace.Create(ARoot, ExtractFileName(ARoot),
    TShellWorkspaceServices.Create(AStore, FTransport, ALogger,
    AIndex, AProgressToken));
  FUsesGraph := TUsesGraphService.Create(AIndex, TUsesGraphOptions.Default);
  FQueries := TCodeQueryService.Create(QuerySource);
end;

destructor TShellWorkspaceGroup.Destroy;
begin
  FQueries := nil;
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
  AWorkspace.Setup.ProcessIdentity := FProcessIdentity;
  AWorkspace.Setup.CacheRoot := FCacheRoot;
  AWorkspace.Events.OnIndexFinished :=
    procedure
    begin
      System.TMonitor.Enter(FLock);
      try
        if not FFinished.Contains(AWorkspace) then
        begin
          FFinished.Add(AWorkspace);
        end;
        FRuleProjects.Valid := False;
      finally
        System.TMonitor.Exit(FLock);
      end;
      FFinishedEvent.SetEvent;
    end;
  // uses-unit-not-found: Was ein anderes Projekt der Gruppe in einen Suchpfad übersetzt, gibt es beim Bau der
  // Gruppe (wie in der Komposition; hier für --check und MCP).
  AWorkspace.Setup.OnGroupProjects :=
    function: TArray<string>
    begin
      Result := TShellBootstrap.GroupProjects(FRoot, FLogger);
    end;
end;

procedure TShellWorkspaceGroup.Load(const AGlobalSettings: string);
var
  mInfo: TProjectInfo;
  mProjectFile: string;
  mOther: TShellWorkspace;
begin
  Prepare(FMain);
  FMain.Load(AGlobalSettings);
  // Übrige Projekte der Gruppe (index.projectGroup, Standard an): Sonst fehlen z. B. Units, die nur ein
  // Package enthält, wenn atlas.json auf ein anderes Projekt zeigt.
  if not FMain.Configuration.Settings.IndexProjectGroup then
  begin
    Exit;
  end;
  for mProjectFile in TShellBootstrap.GroupProjects(FRoot, FLogger) do
  begin
    if FMain.State.Project(mInfo) and SameText(mInfo.FileName, mProjectFile) then
    begin
      Continue;
    end;
    mOther := TShellWorkspace.Create(ExtractFileDir(mProjectFile), ChangeFileExt(ExtractFileName(mProjectFile), ''),
      TShellWorkspaceServices.Create(FStore, FTransport, FLogger, FIndex, Format('%s-%d', [FProgressToken,
      FOthers.Count + 1])));
    mOther.Setup.ProjectFile := mProjectFile;
    Prepare(mOther);
    FOthers.Add(mOther);
    mOther.Load(AGlobalSettings);
  end;
end;

procedure TShellWorkspaceGroup.Stop;
var
  mWorkspace: TShellWorkspace;
begin
  for mWorkspace in FOthers do
  begin
    mWorkspace.Stop;
  end;
  FMain.Stop;
end;

procedure TShellWorkspaceGroup.SetClient(const AClient: string);
var
  mWorkspace: TShellWorkspace;
begin
  FProcessIdentity.Client := AClient;
  for mWorkspace in Workspaces do
  begin
    mWorkspace.Cache.SetClient(AClient);
  end;
end;

function TShellWorkspaceGroup.Workspaces: TArray<TShellWorkspace>;
var
  mOther: TShellWorkspace;
begin
  Result := [FMain];
  for mOther in FOthers do
  begin
    Result := Result + [mOther];
  end;
end;

function TShellWorkspaceGroup.WaitForIndex(ATimeoutMs: Cardinal): Boolean;
var
  mWorkspace: TShellWorkspace;
  mInfo: TProjectInfo;
  mWatch: TStopwatch;
  mMissing: Boolean;
begin
  mWatch := TStopwatch.StartNew;
  repeat
    // Nur Arbeitsbereiche mit Projekt bauen einen Index; ohne Projekt gibt es nichts abzuwarten.
    mMissing := False;
    System.TMonitor.Enter(FLock);
    try
      for mWorkspace in Workspaces do
      begin
        if mWorkspace.State.Project(mInfo) and not FFinished.Contains(mWorkspace) then
        begin
          mMissing := True;
        end;
      end;
    finally
      System.TMonitor.Exit(FLock);
    end;
    if not mMissing then
    begin
      Exit(True);
    end;
    if mWatch.ElapsedMilliseconds >= ATimeoutMs then
    begin
      Exit(False);
    end;
    FFinishedEvent.WaitFor(200);
  until False;
end;

function TShellWorkspaceGroup.Ready(out AReason: string): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  AReason := '';
  for mWorkspace in Workspaces do
  begin
    if not mWorkspace.RuleReady(AReason) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TShellWorkspaceGroup.AllFiles: TArray<string>;
var
  mWorkspace: TShellWorkspace;
begin
  Result := nil;
  for mWorkspace in Workspaces do
  begin
    Result := Result + mWorkspace.State.ProjectFiles;
  end;
end;

function TShellWorkspaceGroup.EnsureUnit(const AUnitName: string): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  for mWorkspace in Workspaces do
  begin
    if mWorkspace.EnsureUnit(AUnitName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TShellWorkspaceGroup.WorkspaceOf(const AFileName: string): TShellWorkspace;
var
  mWorkspace: TShellWorkspace;
begin
  for mWorkspace in Workspaces do
  begin
    if mWorkspace.State.ContainsFile(AFileName) then
    begin
      Exit(mWorkspace);
    end;
  end;
  Result := FMain;
end;

procedure TShellWorkspaceGroup.Invalidate;
begin
  System.TMonitor.Enter(FLock);
  try
    FRuleProjects.Valid := False;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceGroup.RuleProjects: TArray<TRuleProject>;
var
  mWorkspace: TShellWorkspace;
  mProject: TRuleProject;
  mMainSource: string;
begin
  System.TMonitor.Enter(FLock);
  try
    if FRuleProjects.Valid then
    begin
      Exit(FRuleProjects.Items);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  Result := nil;
  for mWorkspace in Workspaces do
  begin
    if mWorkspace.State.RuleProject(mProject, mMainSource) then
    begin
      Result := Result + [TRuleProjectFiles.ProjectOf(mProject.FileName, mMainSource, mProject.Sources, FReadText)];
    end;
  end;
  System.TMonitor.Enter(FLock);
  try
    FRuleProjects.Items := Result;
    FRuleProjects.Valid := True;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceGroup.RuleProject(const AFileName: string): TCheckProject;
var
  mWorkspace, mOther: TShellWorkspace;
  mInfo: TProjectInfo;
  mProjects: TArray<TProjectInfo>;
begin
  // Alle Projekte der Gruppe, die die Datei enthalten, das gewählte zuerst: Eine Unit im Testprogramm und
  // im Package hat keine eindeutige Anwendungsart (MergeRuleProjects).
  mWorkspace := WorkspaceOf(AFileName);
  mProjects := nil;
  if mWorkspace.State.Project(mInfo) then
  begin
    mProjects := mProjects + [mInfo];
  end;
  for mOther in Workspaces do
  begin
    if (mOther <> mWorkspace) and mOther.State.ContainsFile(AFileName) and mOther.State.Project(mInfo) then
    begin
      mProjects := mProjects + [mInfo];
    end;
  end;
  Result := TShellRuleProjects.RuleProjectOf(mProjects, AFileName, FReadText);
  Result.Services := mWorkspace.RuleServices;
  // Nachladen über alle Projekte der Gruppe und projektweite Regeln (#1102) wie im Server.
  Result.Services.EnsureUnit :=
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end;
  Result.Services.ProjectFiles := RuleProjectFiles;
  // Gespeicherte Abfragen mit failIfAny als Regeln query:<name> (#1351).
  Result.Services.Queries := FQueries;
end;

function TShellWorkspaceGroup.Queries: ICodeQueries;
begin
  Result := FQueries;
end;

function TShellWorkspaceGroup.QuerySource(out ASource: TQuerySource): Boolean;
var
  mInput: TLspQueryInput;
begin
  mInput.Index := FIndex;
  mInput.EnsureUnit :=
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end;
  mInput.Root := FRoot;
  mInput.Files := AllFiles;
  mInput.Namespaces := FMain.State.Namespaces;
  mInput.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := Assigned(FReadText) and FReadText(AFileName, AText);
    end;
  ASource := TLspQuery.Source(mInput, FMain.Configuration.Settings.References);
  Result := True;
end;

function TShellWorkspaceGroup.UsesGraph: TUsesGraphService;
var
  mOptions: TUsesGraphOptions;
begin
  mOptions := FUsesGraph.Options;
  if string.Join(';', mOptions.Namespaces) <> string.Join(';', FMain.State.Namespaces) then
  begin
    mOptions.Namespaces := FMain.State.Namespaces;
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
