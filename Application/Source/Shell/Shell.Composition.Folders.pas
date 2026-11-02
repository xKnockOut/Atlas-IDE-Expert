unit Shell.Composition.Folders;

// Internals-Rolle Shell: Arbeitsbereiche anlegen und entfernen. Ein gemeldeter Ordner, eine .dproj oder eine
// .groupproj wird zu einem Arbeitsbereich je Projekt (#648); Ordner ohne Meldung leitet es aus geöffneten Dateien ab
// (#175). Beim Entfernen verlassen die Units der Projekte den Index, sofern kein anderes sie enthält. Units, die
// eine Anfrage braucht, lädt es aus den Suchpfaden nach.

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.Diagnostics.Anonymizer,
  Atlas.Common.Projects.Selection,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Lsp.WorkspaceFolders,
  Shell.Workspace,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings,
  Shell.Composition.Configuration;

type
  TShellFoldersIndexFunc = reference to function: ISymbolIndex;
  TShellFoldersIdeProjectFunc = reference to function: TLspIdeProject;
  TShellFoldersSelectionFunc = reference to function: TProjectSelection;
  TShellFoldersAnonymizerFunc = reference to function: ILogAnonymizer;
  TShellFoldersTextFunc = reference to function: string;
  TShellFoldersReadText = reference to function(const AFileName: string; out AText: string): Boolean;

  /// <summary>Was das Anlegen und Entfernen der Arbeitsbereiche von der Komposition braucht. Die Funktionen fragen
  /// erst beim Anlegen; was sie liefern, entsteht nach den Ordnern.</summary>
  TShellFoldersServices = record
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    Documents: IDocumentStore;
    Workspaces: TShellWorkspaceRegistry;
    Settings: TShellSettings;
    Configuration: TShellConfiguration;
    Index: TShellFoldersIndexFunc;
    IdeProject: TShellFoldersIdeProjectFunc;
    Selection: TShellFoldersSelectionFunc;
    /// <summary>Anonymisierer des Server-Logs (#647); nil ohne.</summary>
    Anonymizer: TShellFoldersAnonymizerFunc;
    /// <summary>clientInfo.name für die Anmeldung am Index-Cache (#62).</summary>
    ClientName: TShellFoldersTextFunc;
    ReadText: TShellFoldersReadText;
    /// <summary>Ein Projekt ist geladen oder entfernt.</summary>
    ProjectLoaded: TProc;
    /// <summary>Projektstufe (True) bzw. ganzer Aufbau (False) eines Index fertig; im Index-Thread.</summary>
    IndexStageDone: TProc<Boolean>;
    /// <summary>Zeile fürs Diagnoselog (#647).</summary>
    IndexEvent: TProc<string>;
    /// <summary>Einstellungen eines Ordners gelesen, für serverweite Werte (#283).</summary>
    SettingsChanged: TProc<TServerSettings>;
  end;

  /// <summary>Legt Arbeitsbereiche an und entfernt sie.</summary>
  TShellFolders = class
  private
    FServices: TShellFoldersServices;
    FScheduler: TIndexScheduler;
    FCounter: Integer;
    FPriority: Integer;
    /// <summary>Projekte zu einem Eintrag: die .dproj, die Projekte der .groupproj bzw. der einzigen im Ordner.
    /// </summary>
    function ProjectsOf(const AFolder: TWorkspaceFolder): TArray<string>;
    procedure AddProject(const ARoot, AName, AProjectFile, AOrigin: string; ADeferred: Boolean);
    function NewWorkspace(const ARoot, AName, AProjectFile, AOrigin: string; ADeferred: Boolean): TShellWorkspace;
    procedure WireEvents(AWorkspace: TShellWorkspace);
    procedure AddLogNames(const ANames: TArray<string>);
    /// <summary>Units der entfernten Projekte verlassen den Index, sofern kein verbleibendes sie enthält.</summary>
    procedure RemoveOwnedUnits(const ARemoved, ARemaining: TArray<TShellWorkspace>);
    /// <summary>Meldungen in atlas.json: gespeicherte Abfragen (#1351) und, mit fertigem Index,
    /// Eigenschaftsregeln mit unbekannter Klasse oder Property (#309).</summary>
    function ConfigurationExtraIssues(const ASettings: TServerSettings): TArray<TConfigurationIssue>;
    function ReadSourceBytes(const AFileName: string; out AData: TBytes): Boolean;
  public
    constructor Create(const AServices: TShellFoldersServices);
    destructor Destroy; override;
    /// <summary>Arbeitsbereiche zu einem gemeldeten Eintrag; Projektgruppe (#648): das erste Projekt ist aktiv,
    /// die übrigen warten bei index.projectGroup = false, bis eine ihrer Dateien geöffnet wird.</summary>
    procedure Add(const AFolder: TWorkspaceFolder);
    /// <summary>Entfernt alle Arbeitsbereiche, die der Eintrag erzeugt hat.</summary>
    procedure Remove(const AFolder: TWorkspaceFolder);
    /// <summary>Datei ohne Arbeitsbereich: Ordner mit Projekt darüber anlegen (#175).</summary>
    procedure Derive(const AFileName: string);
    /// <summary>Lädt AUnitName über die Suchpfade eines Arbeitsbereichs; Anfrage-Threads.</summary>
    function EnsureUnit(const AUnitName: string): Boolean;
    function EnsureUnitFunc: TEnsureUnitFunc;
    /// <summary>Reihenfolge der Indexaufbauten aller Projekte (#648).</summary>
    property Scheduler: TIndexScheduler read FScheduler;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Atlas.Common.Index.Processes,
  Atlas.Common.JsonRpc.CurrentRequest,
  Atlas.Common.Query.Language,
  Atlas.Common.Rules.Builtin.DfmProperties,
  Shell.Platform,
  Shell.Bootstrap,
  Shell.Workspace.Setup;

/// <summary>Gehört AFileName zu AWorkspace? Mit fester Projektdatei nur die Projekt- und Suchpfad-Units, sonst
/// alles unter dem Ordner.</summary>
function OwnsFile(AWorkspace: TShellWorkspace; const AFileName: string): Boolean;
begin
  Result := AWorkspace.State.ContainsFile(AFileName);
  if not Result and (AWorkspace.Setup.ProjectFile = '') then
  begin
    Result := TLspWorkspaceFolders.FolderOf([TWorkspaceFolder.Create(AWorkspace.Root, '')], AFileName) = 0;
  end;
end;

/// <summary>Gehört AFileName zu einem der Arbeitsbereiche AWorkspaces?</summary>
function OwnedByAny(const AWorkspaces: TArray<TShellWorkspace>; const AFileName: string): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  Result := False;
  for mWorkspace in AWorkspaces do
  begin
    if OwnsFile(mWorkspace, AFileName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Liegt in AFolder eine .dproj oder .groupproj?</summary>
function HasProjectFile(const AFolder: string): Boolean;
begin
  try
    Result := (Length(TDirectory.GetFiles(AFolder, '*.dproj')) > 0) or
      (Length(TDirectory.GetFiles(AFolder, '*.groupproj')) > 0);
  except
    // Ungültige oder nicht lesbare Ordner zählen als ohne Projekt.
    on Exception do
      Result := False;
  end;
end;

/// <summary>Die einzige .groupproj in AFolder, wenn dort nicht genau eine .dproj liegt; sonst ''.</summary>
function GroupFileIn(const AFolder: string): string;
var
  mGroups: TArray<string>;
begin
  Result := '';
  try
    // Genau eine .dproj im Ordner: wie bisher dieses Projekt (oder "project" aus atlas.json).
    if Length(TDirectory.GetFiles(AFolder, '*.dproj')) <> 1 then
    begin
      mGroups := TDirectory.GetFiles(AFolder, '*.groupproj');
      if Length(mGroups) = 1 then
      begin
        Result := mGroups[0];
      end;
    end;
  except
    // Nicht lesbare Ordner haben keine Gruppe.
    on Exception do
      Result := '';
  end;
end;

constructor TShellFolders.Create(const AServices: TShellFoldersServices);
begin
  inherited Create;
  FServices := AServices;
  FScheduler := TIndexScheduler.Create;
end;

destructor TShellFolders.Destroy;
begin
  FreeAndNil(FScheduler);
  inherited Destroy;
end;

function TShellFolders.EnsureUnitFunc: TEnsureUnitFunc;
begin
  Result := EnsureUnit;
end;

function TShellFolders.ProjectsOf(const AFolder: TWorkspaceFolder): TArray<string>;
var
  mGroupFile: string;
begin
  Result := nil;
  if SameText(ExtractFileExt(AFolder.ProjectFile), '.dproj') then
  begin
    Result := TArray<string>.Create(AFolder.ProjectFile);
    Exit;
  end;
  if SameText(ExtractFileExt(AFolder.ProjectFile), '.groupproj') then
  begin
    mGroupFile := AFolder.ProjectFile;
  end
  else
  begin
    mGroupFile := GroupFileIn(AFolder.Path);
  end;
  if mGroupFile <> '' then
  begin
    Result := TShellBootstrap.LoadGroup(mGroupFile, FServices.Logger);
  end;
end;

procedure TShellFolders.Add(const AFolder: TWorkspaceFolder);
var
  mProjects: TArray<string>;
  mIndex: Integer;
  mHasOthers: Boolean;
begin
  mProjects := ProjectsOf(AFolder);
  if Length(mProjects) = 0 then
  begin
    AddProject(AFolder.Path, AFolder.Name, '', AFolder.Key, False);
    Exit;
  end;
  mHasOthers := FServices.Workspaces.AddGroupProjects(mProjects);
  for mIndex := 0 to High(mProjects) do
  begin
    AddProject(ExtractFileDir(mProjects[mIndex]), ChangeFileExt(ExtractFileName(mProjects[mIndex]), ''),
      mProjects[mIndex], AFolder.Key, mHasOthers or (mIndex > 0));
  end;
end;

procedure TShellFolders.AddProject(const ARoot, AName, AProjectFile, AOrigin: string; ADeferred: Boolean);
var
  mWorkspace: TShellWorkspace;
begin
  if (AProjectFile <> '') and FServices.Workspaces.HasProject(AProjectFile) then
  begin
    Exit;
  end;
  AddLogNames(TArray<string>.Create(AName, ExtractFileName(ExcludeTrailingPathDelimiter(ARoot)),
    ChangeFileExt(ExtractFileName(AProjectFile), '')));
  mWorkspace := NewWorkspace(ARoot, AName, AProjectFile, AOrigin, ADeferred);
  WireEvents(mWorkspace);
  mWorkspace.Configuration.SetGlobalSettings(FServices.Settings.GlobalSettings);
  mWorkspace.Configuration.SetEditorSettings(FServices.Settings.EditorSettings);
  FServices.Workspaces.Add(mWorkspace);
  FServices.Configuration.UpdateWatchedFiles;
  if AProjectFile <> '' then
  begin
    FServices.Logger.Info('Arbeitsbereich für Projekt: ' + AProjectFile);
  end
  else
  begin
    FServices.Logger.Info('Arbeitsbereichsordner: ' + ARoot);
  end;
  mWorkspace.Load;
end;

function TShellFolders.NewWorkspace(const ARoot, AName, AProjectFile, AOrigin: string;
  ADeferred: Boolean): TShellWorkspace;
var
  mIdentity: TIndexProcessInfo;
begin
  Inc(FCounter);
  Result := TShellWorkspace.Create(ARoot, AName, TShellWorkspaceServices.Create(FServices.Documents,
    FServices.Transport, FServices.Logger, FServices.Index(), Format('atlas-index-%d', [FCounter])));
  Result.Setup.ProjectFile := AProjectFile;
  Result.Setup.Priority := FPriority;
  Inc(FPriority);
  Result.Setup.Scheduler := FScheduler;
  Result.Setup.Deferred := ADeferred;
  Result.Setup.IdeProjects := FServices.IdeProject();
  Result.Setup.Origin := AOrigin;
  Result.Setup.Selection := FServices.Selection();
  // Anmeldung am Index-Cache für „Prozesse am Projekt“ (#62).
  mIdentity := Default(TIndexProcessInfo);
  mIdentity.Pid := TShellPlatform.CurrentProcessId;
  mIdentity.Kind := TIndexProcessInfo.KindLsp;
  mIdentity.Client := FServices.ClientName();
  Result.Setup.ProcessIdentity := mIdentity;
  // Ordner entstehen in der Nachrichtenschleife (initialized, didChangeWorkspaceFolders, didOpen):
  // Reload ist nur dort erlaubt (Code-Review A-03).
  Result.Setup.LoopThreadId := TThread.Current.ThreadID;
end;

procedure TShellFolders.WireEvents(AWorkspace: TShellWorkspace);
begin
  // uses-unit-not-found: Was ein Projekt der Gruppe in einen Suchpfad übersetzt, gibt es beim Bau der Gruppe.
  AWorkspace.Setup.OnGroupProjects :=
    function: TArray<string>
    begin
      Result := FServices.Workspaces.GroupProjectFiles;
    end;
  // requires-Packages als Quelle zuerst bei den Projekten der Gruppe suchen (#46).
  AWorkspace.Setup.OnPackageFolders :=
    function: TArray<string>
    begin
      Result := FServices.Workspaces.PackageFolders;
    end;
  AWorkspace.Events.OnProjectLoaded := FServices.ProjectLoaded;
  AWorkspace.Events.OnIndexFinished :=
    procedure
    begin
      FServices.IndexStageDone(False);
    end;
  AWorkspace.Events.OnProjectReady :=
    procedure
    begin
      FServices.IndexStageDone(True);
    end;
  // Projekt- und Unit-Namen erscheinen im Server-Log nicht im Klartext (#647).
  AWorkspace.Events.OnNames :=
    procedure(ANames: TArray<string>)
    begin
      AddLogNames(ANames);
    end;
  AWorkspace.Events.OnIndexEvent := FServices.IndexEvent;
  // Das Zeitlimit gilt serverweit; bei mehreren Ordnern das zuletzt gelesene.
  AWorkspace.Events.OnSettingsChanged := FServices.SettingsChanged;
  // Eigenschaftsregeln mit unbekannter Klasse oder Property (#309): erst mit fertigem Index, sonst
  // fehlten die Klassen nur, weil sie noch nicht gelesen sind; der fertige Aufbau prüft dann neu.
  AWorkspace.Configuration.ExtraIssues := ConfigurationExtraIssues;
end;

procedure TShellFolders.AddLogNames(const ANames: TArray<string>);
var
  mAnonymizer: ILogAnonymizer;
begin
  mAnonymizer := FServices.Anonymizer();
  if mAnonymizer <> nil then
  begin
    mAnonymizer.AddNames(ANames);
  end;
end;

function TShellFolders.ConfigurationExtraIssues(const ASettings: TServerSettings): TArray<TConfigurationIssue>;
var
  mIndex: ISymbolIndex;
begin
  // Gespeicherte Abfragen mit Fehler (#1351) an der Stelle in atlas.json, unabhängig vom Index.
  Result := TQueryParser.ConfigurationIssues(ASettings.Queries);
  mIndex := FServices.Index();
  if (Length(ASettings.DfmPropertyRules) = 0) or FServices.Workspaces.ProjectIndexPending or
    (Length(mIndex.Units) = 0) then
  begin
    Exit;
  end;
  Result := Result + TDfmPropertyCheckRule.ConfigurationIssues(ASettings.DfmPropertyRules, mIndex, ReadSourceBytes);
end;

function TShellFolders.ReadSourceBytes(const AFileName: string; out AData: TBytes): Boolean;
var
  mText: string;
begin
  Result := FServices.ReadText(AFileName, mText);
  if Result then
  begin
    AData := TEncoding.UTF8.GetBytes(mText);
  end;
end;

procedure TShellFolders.Remove(const AFolder: TWorkspaceFolder);
var
  mRemoved: TArray<TShellWorkspace>;
  mRemaining: TArray<TShellWorkspace>;
  mWorkspace: TShellWorkspace;
begin
  // Ein Eintrag (Ordner, .dproj oder .groupproj) kann mehrere Arbeitsbereiche erzeugt haben (#648).
  mRemoved := FServices.Workspaces.Extract(AFolder.Key, mRemaining);
  if Length(mRemoved) = 0 then
  begin
    Exit;
  end;
  FServices.Logger.Info(Format('Arbeitsbereich entfernt: %s (%d Projekte)', [AFolder.Path, Length(mRemoved)]));
  for mWorkspace in mRemoved do
  begin
    mWorkspace.Stop;
  end;
  RemoveOwnedUnits(mRemoved, mRemaining);
  for mWorkspace in mRemoved do
  begin
    FServices.Workspaces.FreeWhenUnused(mWorkspace);
  end;
  FServices.Configuration.UpdateWatchedFiles;
  FServices.ProjectLoaded();
end;

procedure TShellFolders.RemoveOwnedUnits(const ARemoved, ARemaining: TArray<TShellWorkspace>);
var
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
begin
  // Geteilte Bibliotheks-Units bleiben.
  mIndex := FServices.Index();
  for mUnit in mIndex.Units do
  begin
    if not mUnit.Library_ and OwnedByAny(ARemoved, mUnit.FileName) and not OwnedByAny(ARemaining, mUnit.FileName) then
    begin
      mIndex.RemoveFile(mUnit.FileName);
    end;
  end;
end;

procedure TShellFolders.Derive(const AFileName: string);
var
  mKnown: Boolean;
  mFolder: string;
begin
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mKnown := FServices.Workspaces.WorkspaceOf(AFileName) <> nil;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
  if mKnown then
  begin
    Exit;
  end;
  mFolder := TLspWorkspaceFolders.ProjectFolderFor(AFileName, HasProjectFile);
  if mFolder <> '' then
  begin
    Add(TWorkspaceFolder.Create(mFolder, ExtractFileName(mFolder)));
  end;
end;

function TShellFolders.EnsureUnit(const AUnitName: string): Boolean;
var
  mWorkspace: TShellWorkspace;
  mTargets: TArray<TShellWorkspace>;
begin
  // Anfrage-Threads: jeder Ordner versucht es mit seinen Suchpfaden. Das Parsen läuft außerhalb der Sperre
  // (#647): Sonst warteten alle Anfragen, die nur kurz einen Arbeitsbereich suchen (Defines, Einstellungen,
  // Diagnoselog), auf das Parsen einer Unit, und Hover dauerte Minuten.
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mTargets := FServices.Workspaces.Items.ToArray;
    FServices.Workspaces.Hold(mTargets);
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
  try
    Result := False;
    for mWorkspace in mTargets do
    begin
      // Abgebrochene Anfrage (Watchdog, $/cancelRequest): keine weitere Unit parsen (Code-Review A-06).
      TJsonRpcCurrentRequest.ThrowIfCancellationRequested;
      if mWorkspace.EnsureUnit(AUnitName) then
      begin
        Exit(True);
      end;
    end;
  finally
    FServices.Workspaces.Release(mTargets);
  end;
end;

end.
