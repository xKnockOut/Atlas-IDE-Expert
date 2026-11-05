unit Shell.Composition.Workspaces;

// Internals-Rolle Shell: Register der Arbeitsbereiche des Servers. Hält die Liste, ihre Sperre, die Nutzer
// außerhalb der Sperre (EnsureUnit), die Projekte der Projektgruppen, die gewählten Projekte je Datei und den
// Vorrat der Projekte für projektweite Prüfregeln (#1102). Anlegen, Laden und Verdrahten der Arbeitsbereiche
// bleibt in der Komposition.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.ProjectFiles,
  Shell.Workspace,
  Shell.Composition.Contract;

type
  /// <summary>Gemerktes Projekt zu einem Ursprung (Ordner oder Projektgruppe), leer ohne Wahl.</summary>
  TShellRegistrySelectedFunc = reference to function(const AOrigin: string): string;
  /// <summary>In der IDE aktives Projekt, leer ohne.</summary>
  TShellRegistryActiveFunc = reference to function: string;

  /// <summary>Was das Register von der Komposition braucht.</summary>
  TShellWorkspaceRegistryServices = record
    Logger: ILogger;
    SelectedProject: TShellRegistrySelectedFunc;
    ActiveProject: TShellRegistryActiveFunc;
    /// <summary>Geöffnete Dokumente vor der Platte, für Hauptquelltexte und Formulare der Prüfprojekte.</summary>
    ReadText: TRuleProjectReadText;
  end;

  /// <summary>Arbeitsbereiche des Servers. Ändern nur im Thread der Nachrichtenschleife unter Lock, weil
  /// Anfrage-Threads lesen; Items, WorkspaceOf, Pick, IsLibrarySource, Hold und Touch nur unter Lock.</summary>
  TShellWorkspaceRegistry = class
  private
    FServices: TShellWorkspaceRegistryServices;
    FItems: TObjectList<TShellWorkspace>;
    FLock: TObject;
    /// <summary>Je Arbeitsbereich die Anfragen, die ihn außerhalb der Sperre nutzen; ein entfernter wird erst
    /// freigegeben, wenn er hier fehlt.</summary>
    FUsers: TDictionary<TShellWorkspace, Integer>;
    /// <summary>Zuletzt gewähltes Projekt je Datei, die zu mehreren Projekten gehört (#46), fürs Log.</summary>
    FChoices: TDictionary<string, string>;
    /// <summary>Projekte aller gemeldeten Projektgruppen, schon bevor ihre Arbeitsbereiche geladen sind.</summary>
    FGroupProjectFiles: TArray<string>;
    /// <summary>Gültig, solange FRuleProjectsStamp = FStamp; FStamp steigt mit jedem geladenen Projekt und
    /// jedem hinzugefügten oder entfernten Arbeitsbereich.</summary>
    FRuleProjects: TArray<TRuleProject>;
    FRuleProjectsStamp: Integer;
    FStamp: Integer;
    function FolderWorkspace(const AFileName: string): TShellWorkspace;
    function ChooseProject(const AFileName: string; const ACandidates: TArray<TShellWorkspace>): TShellWorkspace;
    function PreferredProject(const ACandidates: TArray<TShellWorkspace>; out AReason: string): TShellWorkspace;
    procedure LogChoice(const AFileName: string; ACount: Integer; AChosen: TShellWorkspace; const AReason: string);
    function CollectRuleProjects(out AStamp: Integer; out AMainSources: TArray<string>): TArray<TRuleProject>;
    function CachedRuleProjects(out AProjects: TArray<TRuleProject>): Boolean;
    procedure StoreRuleProjects(const AProjects: TArray<TRuleProject>; AStamp: Integer);
  public
    constructor Create(const AServices: TShellWorkspaceRegistryServices);
    destructor Destroy; override;
    /// <summary>Gibt die Arbeitsbereiche frei; Sperre und Nutzer bleiben bis Destroy, weil deren Index-Threads
    /// beim Beenden noch melden.</summary>
    procedure FreeWorkspaces;
    /// <summary>Neuer Stand: Projekte für projektweite Prüfregeln neu bestimmen. Nur unter Lock.</summary>
    procedure Touch;
    /// <summary>Nimmt einen Arbeitsbereich auf (unter der Sperre).</summary>
    procedure Add(AWorkspace: TShellWorkspace);
    /// <summary>Merkt die Projekte einer Gruppe; True, wenn schon Arbeitsbereiche bestehen.</summary>
    function AddGroupProjects(const AProjects: TArray<string>): Boolean;
    function HasProject(const AProjectFile: string): Boolean;
    /// <summary>Projekte der Gruppen und aller Arbeitsbereiche (uses-unit-not-found).</summary>
    function GroupProjectFiles: TArray<string>;
    /// <summary>Ordner aller Projekte, für requires-Packages als Quelle (#46).</summary>
    function PackageFolders: TArray<string>;
    /// <summary>Nimmt alle Arbeitsbereiche des Ursprungs heraus, ohne sie freizugeben.</summary>
    function Extract(const AOrigin: string; out ARemaining: TArray<TShellWorkspace>): TArray<TShellWorkspace>;
    /// <summary>Gibt einen herausgenommenen Arbeitsbereich frei, sobald keine Anfrage ihn mehr nutzt.</summary>
    procedure FreeWhenUnused(AWorkspace: TShellWorkspace);
    /// <summary>Arbeitsbereich, zu dem die Datei gehört, oder nil.</summary>
    function WorkspaceOf(const AFileName: string): TShellWorkspace;
    /// <summary>Arbeitsbereich zur Datei, ohne passenden der einzige.</summary>
    function Pick(const AFileName: string): TShellWorkspace;
    function IsSelected(AWorkspace: TShellWorkspace): Boolean;
    /// <summary>Datei liegt in keinem Projekt, aber in der Bibliothek (diagnostics.librarySources).</summary>
    function IsLibrarySource(const AFileName: string): Boolean;
    /// <summary>Meldet Nutzer außerhalb der Sperre an; Release meldet sie (unter der Sperre) ab.</summary>
    procedure Hold(const AWorkspaces: TArray<TShellWorkspace>);
    procedure Release(const AWorkspaces: TArray<TShellWorkspace>);
    /// <summary>Höchster Ladefortschritt aller Indexe, -1 ohne Aufbau.</summary>
    function IndexLoading: Integer;
    /// <summary>Ein Projekt wird noch indiziert.</summary>
    function ProjectIndexPending: Boolean;
    /// <summary>Projekte aller Arbeitsbereiche für projektweite Prüfregeln (#1102).</summary>
    function RuleProjects: TArray<TRuleProject>;
    function RuleProjectsComplete(out AReason: string): Boolean;
    /// <summary>Ruft AVisit mit allen Arbeitsbereichen unter der Sperre auf.</summary>
    procedure Visit(const AVisit: TShellWorkspacesProc);
    property Lock: TObject read FLock;
    property Items: TObjectList<TShellWorkspace> read FItems;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Common.Lsp.WorkspaceFolders,
  Atlas.Common.Rules.LibrarySources,
  Atlas.Text.LogMarks;

const
  cWaitForever = Cardinal($FFFFFFFF);

constructor TShellWorkspaceRegistry.Create(const AServices: TShellWorkspaceRegistryServices);
begin
  inherited Create;
  FServices := AServices;
  FItems := TObjectList<TShellWorkspace>.Create(True);
  FLock := TObject.Create;
  FUsers := TDictionary<TShellWorkspace, Integer>.Create;
  FChoices := TDictionary<string, string>.Create;
  FRuleProjectsStamp := -1;
end;

destructor TShellWorkspaceRegistry.Destroy;
begin
  FreeWorkspaces;
  FChoices.Free;
  FUsers.Free;
  FLock.Free;
  inherited Destroy;
end;

procedure TShellWorkspaceRegistry.FreeWorkspaces;
begin
  // Nicht FreeAndNil: Index-Threads der Arbeitsbereiche melden beim Beenden und lesen dabei die Liste.
  FItems.Free;
  FItems := nil;
end;

procedure TShellWorkspaceRegistry.Touch;
begin
  Inc(FStamp);
end;

procedure TShellWorkspaceRegistry.Add(AWorkspace: TShellWorkspace);
begin
  System.TMonitor.Enter(FLock);
  try
    FItems.Add(AWorkspace);
    Touch;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceRegistry.AddGroupProjects(const AProjects: TArray<string>): Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FItems.Count > 0;
    FGroupProjectFiles := FGroupProjectFiles + AProjects;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceRegistry.HasProject(const AProjectFile: string): Boolean;
var
  mExisting: TShellWorkspace;
begin
  Result := False;
  System.TMonitor.Enter(FLock);
  try
    for mExisting in FItems do
    begin
      if SameText(mExisting.Setup.ProjectFile, AProjectFile) then
      begin
        Exit(True);
      end;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceRegistry.GroupProjectFiles: TArray<string>;
var
  mOther: TShellWorkspace;
begin
  System.TMonitor.Enter(FLock);
  try
    // Auch Projekte, deren Arbeitsbereich erst nach diesem entsteht: Die Unit-Suche wird beim Laden gebaut.
    Result := FGroupProjectFiles;
    for mOther in FItems do
    begin
      if mOther.Setup.ProjectFile <> '' then
      begin
        Result := Result + [mOther.Setup.ProjectFile];
      end;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceRegistry.PackageFolders: TArray<string>;
var
  mOther: TShellWorkspace;
begin
  Result := nil;
  System.TMonitor.Enter(FLock);
  try
    for mOther in FItems do
    begin
      if mOther.Setup.ProjectFile <> '' then
      begin
        Result := Result + [ExtractFileDir(mOther.Setup.ProjectFile)];
      end;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceRegistry.Extract(const AOrigin: string;
  out ARemaining: TArray<TShellWorkspace>): TArray<TShellWorkspace>;
var
  mIndex: Integer;
begin
  Result := nil;
  System.TMonitor.Enter(FLock);
  try
    for mIndex := FItems.Count - 1 downto 0 do
    begin
      if SameText(FItems[mIndex].Setup.Origin, AOrigin) then
      begin
        Result := Result + [FItems.Extract(FItems[mIndex])];
      end;
    end;
    ARemaining := FItems.ToArray;
    Touch;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TShellWorkspaceRegistry.FreeWhenUnused(AWorkspace: TShellWorkspace);
begin
  // Erst freigeben, wenn keine Anfrage ihn mehr außerhalb der Sperre nutzt (EnsureUnit). Neue Anfragen
  // sehen ihn nicht mehr, das Warten endet also.
  System.TMonitor.Enter(FLock);
  try
    while FUsers.ContainsKey(AWorkspace) do
    begin
      System.TMonitor.Wait(FLock, cWaitForever);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  AWorkspace.Free;
end;

/// <summary>Arbeitsbereich mit der Projektdatei AFileName oder nil.</summary>
function ProjectFileWorkspace(const AItems: TObjectList<TShellWorkspace>; const AFileName: string): TShellWorkspace;
var
  mWorkspace: TShellWorkspace;
begin
  Result := nil;
  for mWorkspace in AItems do
  begin
    if SameText(mWorkspace.State.ProjectFileName, AFileName) then
    begin
      Exit(mWorkspace);
    end;
  end;
end;

function TShellWorkspaceRegistry.FolderWorkspace(const AFileName: string): TShellWorkspace;
var
  mFolders: TArray<TWorkspaceFolder>;
  mWorkspace: TShellWorkspace;
  mIndex: Integer;
begin
  mFolders := nil;
  for mWorkspace in FItems do
  begin
    mFolders := mFolders + [TWorkspaceFolder.Create(mWorkspace.Root, mWorkspace.Name)];
  end;
  mIndex := TLspWorkspaceFolders.FolderOf(mFolders, AFileName);
  Result := nil;
  if mIndex >= 0 then
  begin
    Result := FItems[mIndex];
  end;
end;

function TShellWorkspaceRegistry.WorkspaceOf(const AFileName: string): TShellWorkspace;
var
  mWorkspace: TShellWorkspace;
  mCandidates: TArray<TShellWorkspace>;
begin
  // Die .dproj gehört zu ihrem eigenen Projekt (#46), auch wenn mehrere im selben Ordner liegen.
  if SameText(ExtractFileExt(AFileName), '.dproj') then
  begin
    Result := ProjectFileWorkspace(FItems, AFileName);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  // Zuerst das Projekt, das die Datei enthält (#648); mehrere Projekte können im selben Ordner liegen,
  // und eine Unit kann in mehreren Projekten der Gruppe stehen (#46).
  mCandidates := nil;
  for mWorkspace in FItems do
  begin
    if mWorkspace.State.ContainsFile(AFileName) then
    begin
      mCandidates := mCandidates + [mWorkspace];
    end;
  end;
  case Length(mCandidates) of
    0:
      Result := FolderWorkspace(AFileName);
    1:
      Result := mCandidates[0];
  else
    Result := ChooseProject(AFileName, mCandidates);
  end;
end;

function TShellWorkspaceRegistry.IsSelected(AWorkspace: TShellWorkspace): Boolean;
var
  mSelected: string;
begin
  mSelected := FServices.SelectedProject(AWorkspace.Setup.Origin);
  Result := (mSelected <> '') and SameText(mSelected, AWorkspace.State.ProjectFileName);
end;

function TShellWorkspaceRegistry.PreferredProject(const ACandidates: TArray<TShellWorkspace>;
  out AReason: string): TShellWorkspace;
var
  mWorkspace: TShellWorkspace;
  mActive: string;
begin
  for mWorkspace in ACandidates do
  begin
    if IsSelected(mWorkspace) then
    begin
      AReason := 'ausgewählt';
      Exit(mWorkspace);
    end;
  end;
  mActive := FServices.ActiveProject();
  if mActive <> '' then
  begin
    for mWorkspace in ACandidates do
    begin
      if SameText(mWorkspace.State.ProjectFileName, mActive) then
      begin
        AReason := 'aktiv in der IDE';
        Exit(mWorkspace);
      end;
    end;
  end;
  AReason := 'erstes der Gruppe';
  Result := ACandidates[0];
end;

procedure TShellWorkspaceRegistry.LogChoice(const AFileName: string; ACount: Integer; AChosen: TShellWorkspace;
  const AReason: string);
var
  mKnown: string;
begin
  // Nur Wechsel ins Log, nicht jede Anfrage.
  if not FChoices.TryGetValue(AnsiUpperCase(AFileName), mKnown) or not SameText(mKnown, AChosen.Name) then
  begin
    FChoices.AddOrSetValue(AnsiUpperCase(AFileName), AChosen.Name);
    FServices.Logger.Info(Format('%s gehört zu %d Projekten; es gilt %s (%s)',
      [TLogMarks.Path(ExtractFileName(AFileName)), ACount,
      TLogMarks.Name(AChosen.Name), TLogMarks.Text(AReason)]));
  end;
end;

function TShellWorkspaceRegistry.ChooseProject(const AFileName: string;
  const ACandidates: TArray<TShellWorkspace>): TShellWorkspace;
var
  mReason: string;
begin
  Result := PreferredProject(ACandidates, mReason);
  LogChoice(AFileName, Length(ACandidates), Result, mReason);
end;

function TShellWorkspaceRegistry.Pick(const AFileName: string): TShellWorkspace;
begin
  Result := TShellWorkspaces.Choose(WorkspaceOf(AFileName), FItems);
end;

function TShellWorkspaceRegistry.IsLibrarySource(const AFileName: string): Boolean;
var
  mWorkspace: TShellWorkspace;
  mRoots, mProjectRoots: TArray<string>;
begin
  mRoots := nil;
  mProjectRoots := nil;
  for mWorkspace in FItems do
  begin
    if mWorkspace.State.ContainsFile(AFileName) then
    begin
      Exit(False);
    end;
    mProjectRoots := mProjectRoots + [mWorkspace.Root];
    if mWorkspace.State.BdsRoot <> '' then
    begin
      mRoots := mRoots + [mWorkspace.State.BdsRoot];
    end;
    mRoots := mRoots + mWorkspace.State.Install.LibraryPaths;
  end;
  Result := TLibrarySources.Create(mRoots, mProjectRoots).IsLibraryFile(AFileName);
end;

procedure TShellWorkspaceRegistry.Hold(const AWorkspaces: TArray<TShellWorkspace>);
var
  mWorkspace: TShellWorkspace;
  mUsers: Integer;
begin
  for mWorkspace in AWorkspaces do
  begin
    if FUsers.TryGetValue(mWorkspace, mUsers) then
    begin
      FUsers[mWorkspace] := mUsers + 1;
    end
    else
    begin
      FUsers.Add(mWorkspace, 1);
    end;
  end;
end;

procedure TShellWorkspaceRegistry.Release(const AWorkspaces: TArray<TShellWorkspace>);
var
  mWorkspace: TShellWorkspace;
  mUsers: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    for mWorkspace in AWorkspaces do
    begin
      mUsers := FUsers[mWorkspace] - 1;
      if mUsers = 0 then
      begin
        FUsers.Remove(mWorkspace);
      end
      else
      begin
        FUsers[mWorkspace] := mUsers;
      end;
    end;
    System.TMonitor.PulseAll(FLock);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceRegistry.IndexLoading: Integer;
var
  mWorkspace: TShellWorkspace;
begin
  Result := -1;
  System.TMonitor.Enter(FLock);
  try
    for mWorkspace in FItems do
    begin
      Result := Max(Result, mWorkspace.IndexLoading);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceRegistry.ProjectIndexPending: Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  Result := False;
  System.TMonitor.Enter(FLock);
  try
    for mWorkspace in FItems do
    begin
      if mWorkspace.State.ProjectPending then
      begin
        Exit(True);
      end;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceRegistry.CachedRuleProjects(out AProjects: TArray<TRuleProject>): Boolean;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FRuleProjectsStamp = FStamp;
    AProjects := FRuleProjects;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceRegistry.CollectRuleProjects(out AStamp: Integer;
  out AMainSources: TArray<string>): TArray<TRuleProject>;
var
  mWorkspace: TShellWorkspace;
  mProject: TRuleProject;
  mMainSource: string;
begin
  Result := nil;
  AMainSources := nil;
  System.TMonitor.Enter(FLock);
  try
    AStamp := FStamp;
    for mWorkspace in FItems do
    begin
      if mWorkspace.State.RuleProject(mProject, mMainSource) then
      begin
        Result := Result + [mProject];
        AMainSources := AMainSources + [mMainSource];
      end;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TShellWorkspaceRegistry.StoreRuleProjects(const AProjects: TArray<TRuleProject>; AStamp: Integer);
begin
  System.TMonitor.Enter(FLock);
  try
    // Inzwischen ein anderes Projekt geladen: Das Ergebnis gilt für diese Prüfung, aber nicht als Vorrat.
    if AStamp = FStamp then
    begin
      FRuleProjects := AProjects;
      FRuleProjectsStamp := AStamp;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceRegistry.RuleProjects: TArray<TRuleProject>;
var
  mStamp, mIndex: Integer;
  mMainSources: TArray<string>;
begin
  if CachedRuleProjects(Result) then
  begin
    Exit;
  end;
  Result := CollectRuleProjects(mStamp, mMainSources);
  // Hauptquelltexte und Formulardateien außerhalb der Sperre lesen (dieselbe Regel wie find_unused_code, #64).
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex] := TRuleProjectFiles.ProjectOf(Result[mIndex].FileName, mMainSources[mIndex],
      Result[mIndex].Sources, FServices.ReadText);
  end;
  StoreRuleProjects(Result, mStamp);
end;

function TShellWorkspaceRegistry.RuleProjectsComplete(out AReason: string): Boolean;
var
  mWorkspace: TShellWorkspace;
begin
  AReason := '';
  System.TMonitor.Enter(FLock);
  try
    for mWorkspace in FItems do
    begin
      if not mWorkspace.RuleReady(AReason) then
      begin
        Exit(False);
      end;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  Result := True;
end;

procedure TShellWorkspaceRegistry.Visit(const AVisit: TShellWorkspacesProc);
begin
  System.TMonitor.Enter(FLock);
  try
    AVisit(FItems.ToArray);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
