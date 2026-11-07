unit Shell.Composition.Ide;

// Internals-Rolle Shell: Nachrichten aus der IDE. Compilermeldungen aus dem Meldungsfenster (#528), der letzte
// Build für den MCP-Prozess (#556), die Pause der Projektprüfung während eines Compiles (#1247), der
// Projektkontext (#396), der betroffene Projekte neu lädt, neue Präfixe aus .atlas (#1111) und die Typen aus den
// Packages der IDE (atlas/ideTypes), nach denen offene Dateien neu geprüft werden. Ist der Index fertig, fragt
// sie nach den Mitgliedern der Units ohne Quelltext (atlas/ideMembersWanted); die Antwort (atlas/ideMembers)
// wird zu Ersatz-Units für Hover, Vervollständigung und Parameterhilfe.

interface

uses
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.IdeBuild,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Lsp.IdeTypes,
  Atlas.Common.Lsp.IdeUnits,
  Shell.Workspace,
  Shell.Composition.Workspaces;

type
  TShellIdeMessagesProc = reference to procedure(const AMessages: TArray<TCompilerMessage>);
  TShellIdeCompilingProc = reference to procedure(ARunning: Boolean);
  TShellIdeRefreshProc = reference to procedure;
  /// <summary>Benachrichtigung an die IDE; übernimmt AParams.</summary>
  TShellIdeNotifyProc = reference to procedure(const AMethod: string; AParams: TJSONObject);

  /// <summary>Was die IDE-Nachrichten von der Komposition brauchen.</summary>
  TShellIdeServices = record
    Logger: ILogger;
    Workspaces: TShellWorkspaceRegistry;
    /// <summary>Meldungen der IDE ersetzen die des letzten Laufs; Dateien neu prüfen.</summary>
    MessagesReceived: TShellIdeMessagesProc;
    /// <summary>Die IDE kompiliert (True) oder ist fertig (False).</summary>
    Compiling: TShellIdeCompilingProc;
    /// <summary>Namenskonvention geändert: offene Dateien neu prüfen.</summary>
    NamingChanged: TShellIdeRefreshProc;
    /// <summary>Typen der IDE geändert: offene Dateien neu prüfen.</summary>
    TypesChanged: TShellIdeRefreshProc;
    /// <summary>Ersatz-Units der IDE und gemeinsamer Index (ohne sie).</summary>
    IdeUnits: TIdeUnits;
    Index: ISymbolIndex;
    Notify: TShellIdeNotifyProc;
  end;

  /// <summary>Build und Projektkontext aus der IDE.</summary>
  TShellIde = class
  private
    FServices: TShellIdeServices;
    FBuild: TLspIdeBuild;
    FProject: TLspIdeProject;
    FTypes: TLspIdeTypes;
    // Der Index ist einmal ganz aufgebaut; erst dann gilt eine Unit ohne Eintrag als ohne Quelltext.
    FIndexFinished: Boolean;
    procedure MessagesReceived(const AMessages: TArray<TCompilerMessage>);
    /// <summary>Ordner des Projekts für die Build-Datei: Wurzel des Arbeitsbereichs, sonst der Projektordner.
    /// </summary>
    function BuildRootOf(const AProject: string): string;
    procedure BuildChanged(const ABuild: TIdeBuild);
    procedure Compiling(ARunning: Boolean);
    /// <summary>Arbeitsbereiche, deren Projekt AProject ist.</summary>
    function WorkspacesOfProject(const AProject: string): TArray<TShellWorkspace>;
    procedure ProjectChanged(const AContext: TIdeProjectContext);
    procedure NamingChanged(const AContext: TIdeProjectContext);
    procedure TypesChanged(ACount: Integer);
    /// <summary>Fragt nach den Mitgliedern der Units aus dem Typkatalog, die der Index nicht kennt.</summary>
    procedure RequestMembers;
    procedure MembersChanged(ACount: Integer);
  public
    constructor Create(const AServices: TShellIdeServices);
    destructor Destroy; override;
    /// <summary>Meldet die Nachrichten der IDE am Dispatcher an.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Der Indexaufbau ist fertig: nach den Units ohne Quelltext fragen.</summary>
    procedure IndexFinished;
    property Build: TLspIdeBuild read FBuild;
    property Project: TLspIdeProject read FProject;
    /// <summary>Typen aus den Packages der IDE (atlas/ideTypes).</summary>
    property Types: TLspIdeTypes read FTypes;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.Generics.Collections,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Text.LogMarks;

constructor TShellIde.Create(const AServices: TShellIdeServices);
begin
  inherited Create;
  FServices := AServices;
  // Compilermeldungen aus dem Meldungsfenster der IDE ersetzen die des letzten Laufs wie ein eigener Compile (#528).
  FBuild := TLspIdeBuild.Create;
  FBuild.OnMessages := MessagesReceived;
  // Letzten Build für den MCP-Prozess ablegen (#556): je Arbeitsordner eine Datei im Atlas-Cache.
  FBuild.OnChanged := BuildChanged;
  // Während die IDE kompiliert, ruht die Projektprüfung (#1247). Die Frist ist ein Sicherheitsnetz für ein
  // verlorenes Ende, keine Steuerung.
  FBuild.OnCompiling := Compiling;
  // Konfiguration, Plattform und Optionen aus der IDE (#396): betroffene Projekte neu laden.
  FProject := TLspIdeProject.Create;
  FProject.OnChanged := ProjectChanged;
  // Neue Präfixe aus .atlas (#1111): naming-prefix und shadowed-name prüfen neu, das Projekt bleibt geladen.
  FProject.OnNamingChanged := NamingChanged;
  // Typen aus den Packages der IDE: unresolved-type und unresolved-identifier schweigen für sie, offene Dateien
  // prüfen neu.
  FTypes := TLspIdeTypes.Create;
  FTypes.OnChanged := TypesChanged;
  if FServices.IdeUnits <> nil then
  begin
    FServices.IdeUnits.OnChanged := MembersChanged;
  end;
end;

destructor TShellIde.Destroy;
begin
  FreeAndNil(FBuild);
  FreeAndNil(FProject);
  FreeAndNil(FTypes);
  inherited Destroy;
end;

procedure TShellIde.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FBuild.Attach(ADispatcher);
  FProject.Attach(ADispatcher);
  FTypes.Attach(ADispatcher);
  if FServices.IdeUnits <> nil then
  begin
    FServices.IdeUnits.Attach(ADispatcher);
  end;
end;

procedure TShellIde.MessagesReceived(const AMessages: TArray<TCompilerMessage>);
begin
  FServices.MessagesReceived(AMessages);
  FServices.Logger.Info(Format('Compilermeldungen aus der IDE: %d', [Length(AMessages)]));
end;

function TShellIde.BuildRootOf(const AProject: string): string;
var
  mWorkspace: TShellWorkspace;
begin
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mWorkspace := FServices.Workspaces.Pick(AProject);
    Result := ExtractFileDir(AProject);
    if mWorkspace <> nil then
    begin
      Result := mWorkspace.Root;
    end;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
end;

procedure TShellIde.BuildChanged(const ABuild: TIdeBuild);
var
  mRoot: string;
begin
  mRoot := BuildRootOf(ABuild.Project);
  if mRoot = '' then
  begin
    Exit;
  end;
  try
    ForceDirectories(TIndexCacheDirectory.DefaultRoot);
    TFile.WriteAllText(TIndexCacheDirectory.BuildFileFor(TIndexCacheDirectory.DefaultRoot, mRoot),
      TMcpBuildTools.ToFileText(ABuild), TEncoding.UTF8);
  except
    on E: Exception do
      FServices.Logger.Warning(Format('Letzter Build nicht gespeichert: %s', [TLogMarks.Text(E.Message)]));
  end;
end;

procedure TShellIde.Compiling(ARunning: Boolean);
begin
  FServices.Compiling(ARunning);
end;

function TShellIde.WorkspacesOfProject(const AProject: string): TArray<TShellWorkspace>;
var
  mWorkspace: TShellWorkspace;
  mProject: TProjectInfo;
begin
  Result := nil;
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    for mWorkspace in FServices.Workspaces.Items do
    begin
      if SameText(mWorkspace.Setup.ProjectFile, AProject) or
        (mWorkspace.State.Project(mProject) and SameText(mProject.FileName, AProject)) then
      begin
        Result := Result + [mWorkspace];
      end;
    end;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
end;

procedure TShellIde.ProjectChanged(const AContext: TIdeProjectContext);
var
  mWorkspace: TShellWorkspace;
begin
  FServices.Logger.Info(Format('Projektkontext aus der IDE: %s (%s, %s)',
    [TLogMarks.Path(ExtractFileName(AContext.Project)),
      TLogMarks.Name(AContext.Configuration), TLogMarks.Name(AContext.Platform)]));
  for mWorkspace in WorkspacesOfProject(AContext.Project) do
  begin
    mWorkspace.Reload;
  end;
end;

procedure TShellIde.NamingChanged(const AContext: TIdeProjectContext);
begin
  FServices.NamingChanged();
end;

procedure TShellIde.TypesChanged(ACount: Integer);
begin
  FServices.Logger.Info(Format('IDE-Typen: %d', [ACount]));
  if Assigned(FServices.TypesChanged) then
  begin
    FServices.TypesChanged();
  end;
  if FIndexFinished then
  begin
    RequestMembers;
  end;
end;

procedure TShellIde.IndexFinished;
begin
  FIndexFinished := True;
  RequestMembers;
end;

/// <summary>Units der Einträge ohne Doppelte, in der Reihenfolge des Katalogs.</summary>
function UnitsOf(const AEntries: TArray<TIdeTypeEntry>): TArray<string>;
var
  mSeen: TDictionary<string, Boolean>;
  mEntry: TIdeTypeEntry;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mEntry in AEntries do
    begin
      if not mSeen.ContainsKey(UpperCase(mEntry.UnitName)) then
      begin
        mSeen.Add(UpperCase(mEntry.UnitName), True);
        Result := Result + [mEntry.UnitName];
      end;
    end;
  finally
    mSeen.Free;
  end;
end;

procedure TShellIde.RequestMembers;
var
  mWanted: TArray<string>;
  mParams: TJSONObject;
  mUnits: TJSONArray;
  mUnit: string;
begin
  if (FServices.IdeUnits = nil) or not Assigned(FServices.Notify) then
  begin
    Exit;
  end;
  mWanted := FServices.IdeUnits.Wanted(UnitsOf(FTypes.Catalog.Entries), FServices.Index);
  if mWanted = nil then
  begin
    Exit;
  end;
  mUnits := TJSONArray.Create;
  for mUnit in mWanted do
  begin
    mUnits.Add(mUnit);
  end;
  mParams := TJSONObject.Create;
  mParams.AddPair('units', mUnits);
  FServices.Logger.Info(Format('IDE-Units ohne Quelltext erfragt: %d', [Length(mWanted)]));
  FServices.Notify(TIdeUnits.cWantedMethod, mParams);
end;

procedure TShellIde.MembersChanged(ACount: Integer);
begin
  FServices.Logger.Info(Format('IDE-Ersatz-Units: %d', [ACount]));
end;

end.
