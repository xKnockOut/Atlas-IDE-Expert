unit Shell.Workspace;

// Host-Rolle Shell: ein Ordner des Arbeitsbereichs mit eigener
// atlas.json, eigenem Projekt und eigenem Indexaufbau. Alle Ordner
// schreiben in denselben Symbolindex, damit Navigation und Suche über
// Ordnergrenzen funktionieren.
// Projektgruppe (#648): Je Projekt der Gruppe ein Arbeitsbereich mit fest
// vorgegebener Projektdatei (Setup.ProjectFile); mehrere können denselben Ordner
// haben. Der gemeinsame Scheduler ordnet ihre Aufbauten.
// Die Teile stehen in eigenen Units: Vorgaben und Ereignisse (Setup), Stand des
// geladenen Projekts (State), Projektwahl (Build), Index-Cache (Cache), Laden
// (Loader), Indexauftrag (Requests) und Aufbau (Indexing).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Configuration,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Index.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Baseline,
  Shell.Compiler,
  Shell.Workspace.Setup,
  Shell.Workspace.State,
  Shell.Workspace.Build,
  Shell.Workspace.Cache,
  Shell.Workspace.Indexing,
  Shell.Workspace.Jobs;

type
  TShellWorkspace = class
  private
    FRoot: string;
    FName: string;
    FLogger: ILogger;
    FConfiguration: TLspConfiguration;
    FSetup: TShellWorkspaceSetup;
    FEvents: TShellWorkspaceEvents;
    FState: TShellProjectState;
    FBuild: TShellBuildChoice;
    FCache: TShellWorkspaceCache;
    FIndexing: TShellWorkspaceIndexing;
    FBaseline: TShellBaselineFile;
    procedure SettingsChanged(const ASettings: TServerSettings);
    procedure StartIndex(const ASettings: TServerSettings);
  public
    constructor Create(const ARoot, AName: string; const AServices: TShellWorkspaceServices);
    destructor Destroy; override;
    /// <summary>Liest atlas.json des Ordners und startet den Indexaufbau.</summary>
    procedure Load; overload;
    /// <summary>Wie Load, mit der globalen settings.json AGlobalSettings; der Index startet nur einmal.</summary>
    procedure Load(const AGlobalSettings: string); overload;
    /// <summary>Lädt das Projekt neu, auch wenn sich die Einstellungen nicht geändert haben.</summary>
    procedure Reload;
    /// <summary>Baut den Index ohne Cache neu auf (Befehl „Index neu aufbauen“, #49).</summary>
    procedure Rebuild;
    /// <summary>Hält den Indexaufbau an.</summary>
    procedure Stop;
    /// <summary>Hält den Aufbau an und gibt die Sperre des eigenen Caches frei, damit „Index löschen“ (#492)
    /// ihn entfernen kann; Rebuild sperrt ihn wieder.</summary>
    procedure ReleaseCache;
    function EnsureUnit(const AUnitName: string): Boolean;
    function ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
    function ApplyText(const AFileName, AText: string): Boolean;
    /// <summary>atlas-baseline.json des Ordners (#97), neu gelesen, sobald sich die Datei ändert; nil ohne oder
    /// bei ungültiger Datei. Threadsicher.</summary>
    function Baseline: IRuleBaseline;
    /// <summary>Compilerlauf für das Projekt (#40, #261): Aufruf von dcc32/dcc64, Projekt, Plattform,
    /// Installation und compiler-Einstellungen. Ob dcc da und nutzbar ist, prüft der Aufrufer
    /// (TShellCompilerEditions). False mit Grund in AError ohne Projekt, Installation oder unterstützte
    /// Plattform. Threadsicher.</summary>
    function CompileJob(out AJob: TShellCompileJob; out AError: string): Boolean;
    /// <summary>Wechselt Konfiguration und/oder Plattform ('' = unverändert) und lädt das Projekt neu (#46).
    /// False mit Grund in AError ohne Projekt oder bei unbekannten Werten. Threadsicher.</summary>
    function SelectBuild(const AConfig, APlatform: string; out AError: string): Boolean; overload;
    /// <summary>Wie oben; mit AHasDefines ersetzen ADefines die Symbole (DCC_Define) der .dproj,
    /// etwa ungespeicherte Projektoptionen der IDE (#615).</summary>
    function SelectBuild(const AConfig, APlatform: string; const ADefines: TArray<string>; AHasDefines: Boolean;
      out AError: string): Boolean; overload;
    /// <summary>Fortschritt des laufenden Indexaufbaus in Prozent; -1, wenn keiner läuft (#647).</summary>
    function IndexLoading: Integer;
    /// <summary>Letzter Indexlauf für den Status-Befehl (#28). Threadsicher.</summary>
    function IndexStatus: TWorkspaceStatus;
    /// <summary>Projekt aus der Gruppe, das mit index.projectGroup = false noch wartet: jetzt indizieren.</summary>
    procedure Activate;
    /// <summary>Dienste des Projekts für die Prüfregeln (#1112), siehe TShellRuleProjects.ServicesOf. Threadsicher.
    /// </summary>
    function RuleServices: TRuleServices;
    /// <summary>Projekt geladen und Index fertig (#1102, #1112)? Sonst der Grund in AReason. Ein Arbeitsbereich,
    /// dessen Projekt noch lädt, kann Verwendungen enthalten, die keiner kennt. Ein Arbeitsbereich ohne Projekt ist
    /// bereit, sobald der Aufbau das festgestellt hat (#1220). Threadsicher.</summary>
    function RuleReady(out AReason: string): Boolean;
    property Root: string read FRoot;
    property Name: string read FName;
    property Configuration: TLspConfiguration read FConfiguration;
    /// <summary>Vorgaben, vor Load zu setzen (Projektgruppe, Cache-Ordner, IDE-Projekte, Projektwahl …).</summary>
    property Setup: TShellWorkspaceSetup read FSetup;
    property Events: TShellWorkspaceEvents read FEvents;
    /// <summary>Stand des geladenen Projekts: Projekt, Symbole, Namespaces, Dateien, Unit-Suche. Threadsicher.
    /// </summary>
    property State: TShellProjectState read FState;
    /// <summary>Eigener Index-Cache und die daran angemeldeten Prozesse (#62).</summary>
    property Cache: TShellWorkspaceCache read FCache;
  end;

  TShellWorkspaces = class
  public
    /// <summary>Arbeitsbereich zu einer Datei (S-02): AFound, sonst bei genau einem Arbeitsbereich dieser,
    /// sonst nil. Eine Regel für alle Einstellungs- und Pfadabfragen des Servers.</summary>
    class function Choose(AFound: TShellWorkspace; const AAll: TList<TShellWorkspace>): TShellWorkspace; static;
  end;

implementation

uses
  System.Classes,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Shell.Bootstrap,
  Shell.Workspace.Loader,
  Shell.Workspace.RuleProjects,
  Atlas.Text.LogMarks;

/// <summary>Teile für den Indexaufbau eines Arbeitsbereichs.</summary>
function IndexingParts(const ARoot, AName: string; const AServices: TShellWorkspaceServices;
  ASetup: TShellWorkspaceSetup; AEvents: TShellWorkspaceEvents; AState: TShellProjectState): TShellIndexingParts;
begin
  Result.Name := AName;
  Result.Root := ARoot;
  Result.Logger := AServices.Logger;
  Result.Transport := AServices.Transport;
  Result.Index := AServices.Index;
  Result.ProgressToken := AServices.ProgressToken;
  Result.Setup := ASetup;
  Result.Events := AEvents;
  Result.State := AState;
  Result.Cache := nil;
end;

{ TShellWorkspace }

constructor TShellWorkspace.Create(const ARoot, AName: string; const AServices: TShellWorkspaceServices);
var
  mParts: TShellIndexingParts;
begin
  inherited Create;
  FRoot := ARoot;
  FName := AName;
  FLogger := AServices.Logger;
  FSetup := TShellWorkspaceSetup.Create;
  FEvents := TShellWorkspaceEvents.Create;
  FState := TShellProjectState.Create(FSetup);
  FBuild := TShellBuildChoice.Create(AName, AServices.Logger, FSetup);
  FCache := TShellWorkspaceCache.Create(AName, AServices.Logger, FSetup, FEvents);
  FBaseline := TShellBaselineFile.Create(ARoot, AName, AServices.Logger);
  mParts := IndexingParts(ARoot, AName, AServices, FSetup, FEvents, FState);
  mParts.Cache := FCache;
  FIndexing := TShellWorkspaceIndexing.Create(mParts);
  FConfiguration := TLspConfiguration.Create(AServices.Store, AServices.Transport,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := TShellBootstrap.ReadSourceText(AFileName, AText);
    end);
  FConfiguration.OnChanged :=
    procedure(const ASettings: TServerSettings)
    begin
      SettingsChanged(ASettings);
    end;
end;

destructor TShellWorkspace.Destroy;
begin
  if FRoot <> '' then
  begin
    TFileEncodingDefaults.RemoveFolder(FRoot);
  end;
  // Zuerst der Aufbau: Seine Rückrufe erreichen Zustand, Cache und Ereignisse.
  FIndexing.Free;
  FCache.Free;
  FConfiguration.Free;
  FBaseline.Free;
  FBuild.Free;
  FState.Free;
  FEvents.Free;
  FSetup.Free;
  FLogger := nil;
  inherited;
end;

procedure TShellWorkspace.SettingsChanged(const ASettings: TServerSettings);
begin
  FLogger.Info(Format('Einstellungen für %s: Delphi %s, Projekt %s, %d Regeleinstellungen, %d Ausschlüsse',
    [TLogMarks.Name(FName), ASettings.DelphiVersion, TLogMarks.Path(ASettings.Project), Length(ASettings.Rules),
      Length(ASettings.Exclude)]));
  // Vorgabe-Kodierung (#121) gilt für alle Lese- und Schreibpfade unter diesem Ordner.
  if FRoot <> '' then
  begin
    TFileEncodingDefaults.SetFolder(FRoot, ASettings.DefaultEncoding);
  end;
  // Der Index ist gemeinsam; bei mehreren Ordnern gilt das zuletzt gelesene Budget.
  FIndexing.Index.SetBudget(Int64(ASettings.MemoryBudgetMb) * 1024 * 1024);
  FEvents.SettingsChanged(ASettings);
  StartIndex(ASettings);
end;

procedure TShellWorkspace.StartIndex(const ASettings: TServerSettings);
var
  mLoader: TShellProjectLoader;
  mProjectFile: string;
  mLoaded: TShellLoadedProject;
  mLoadedOk: Boolean;
begin
  // Mit index.projectGroup = false nur das Projekt der geöffneten Datei (#648).
  if FSetup.Deferred and not FSetup.Activated and not ASettings.IndexProjectGroup then
  begin
    FLogger.Info(Format('%s: index.projectGroup ist aus; indiziert wird, sobald eine Datei des Projekts offen ist',
      [TLogMarks.Name(FName)]));
    FState.WithoutProject := True;
    Exit;
  end;
  mLoader := TShellProjectLoader.Create(FName, FRoot, FLogger, FSetup, FBuild);
  try
    mProjectFile := mLoader.FindProjectFile(ASettings);
    // Ohne Projekt indiziert dieser Arbeitsbereich nichts; Prüfungen sollen dann nicht auf ihn warten. Sonst liefen
    // die indexabhängigen Regeln in einem Ordner ohne Projekt nie (#1220).
    FState.WithoutProject := mProjectFile = '';
    mLoadedOk := not FState.WithoutProject and mLoader.Load(mProjectFile, ASettings, mLoaded);
  finally
    mLoader.Free;
  end;
  if not mLoadedOk then
  begin
    Exit;
  end;
  FEvents.Names(mLoaded.Names);
  FState.SetProject(mLoaded.Project, mLoaded.Install);
  if FIndexing.Start(mLoaded, ASettings) then
  begin
    FEvents.ProjectLoaded;
  end;
end;

procedure TShellWorkspace.Load;
begin
  FConfiguration.LoadWorkspace(FRoot);
end;

procedure TShellWorkspace.Load(const AGlobalSettings: string);
begin
  FConfiguration.LoadWorkspace(FRoot, AGlobalSettings);
end;

procedure TShellWorkspace.Reload;
begin
  // StartIndex ändert Zustand ohne Sperre: Andere Threads stellen Reload über TJsonRpcConnection.Queue
  // in die Schleife (A-03).
  if (FSetup.LoopThreadId <> 0) and (TThread.Current.ThreadID <> FSetup.LoopThreadId) then
  begin
    raise EInvalidOpException.Create('Reload nur im Thread der Nachrichtenschleife');
  end;
  FIndexing.Forget;
  StartIndex(FConfiguration.Settings);
end;

procedure TShellWorkspace.Rebuild;
begin
  FIndexing.DiscardNext;
  Reload;
end;

procedure TShellWorkspace.Stop;
begin
  FIndexing.Stop;
end;

procedure TShellWorkspace.ReleaseCache;
begin
  FIndexing.Stop;
  FCache.Release;
end;

function TShellWorkspace.EnsureUnit(const AUnitName: string): Boolean;
begin
  Result := FIndexing.EnsureUnit(AUnitName);
end;

function TShellWorkspace.ApplyText(const AFileName, AText: string): Boolean;
begin
  Result := FIndexing.ApplyText(AFileName, AText);
end;

function TShellWorkspace.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
begin
  Result := FIndexing.ApplyChanges(AChanges);
end;

function TShellWorkspace.Baseline: IRuleBaseline;
begin
  Result := FBaseline.Current;
end;

function TShellWorkspace.CompileJob(out AJob: TShellCompileJob; out AError: string): Boolean;
var
  mProject: TProjectInfo;
begin
  Result := FState.Project(mProject);
  if not Result then
  begin
    AJob := Default(TShellCompileJob);
    AJob.Settings := FConfiguration.Settings.Compiler;
    AError := 'Kein Projekt geladen';
    Exit;
  end;
  Result := TShellWorkspaceJobs.CompileJobOf(mProject, FState.Install, FConfiguration.Settings.Compiler, AJob,
    AError);
end;

function TShellWorkspace.SelectBuild(const AConfig, APlatform: string; out AError: string): Boolean;
begin
  Result := SelectBuild(AConfig, APlatform, nil, False, AError);
end;

function TShellWorkspace.SelectBuild(const AConfig, APlatform: string; const ADefines: TArray<string>;
  AHasDefines: Boolean; out AError: string): Boolean;
var
  mProject: TProjectInfo;
begin
  Result := FState.Project(mProject);
  if not Result then
  begin
    AError := Format('Für %s ist kein Projekt geladen.', [FName]);
    Exit;
  end;
  Result := FBuild.Select(mProject, AConfig, APlatform, ADefines, AHasDefines, AError);
  if not Result then
  begin
    Exit;
  end;
  FLogger.Info(Format('%s: Konfiguration %s, Plattform %s gewählt', [TLogMarks.Name(FName), TLogMarks.Name(AConfig),
    TLogMarks.Name(APlatform)]));
  // Über Neustarts merken (#46); die Symbole der IDE kommen nach dem Start neu.
  if (FSetup.Selection <> nil) and ((AConfig <> '') or (APlatform <> '')) then
  begin
    FSetup.Selection.SetBuild(FState.ProjectFileName, AConfig, APlatform);
  end;
  Reload;
end;

function TShellWorkspace.IndexLoading: Integer;
begin
  Result := FIndexing.Loading;
end;

function TShellWorkspace.IndexStatus: TWorkspaceStatus;
var
  mStats: TShellIndexStats;
  mFiles: TShellCacheFiles;
  mProject: TProjectInfo;
begin
  Result := Default(TWorkspaceStatus);
  mStats := FState.Stats;
  mFiles := FCache.Files;
  Result.Name := FName;
  Result.LastIndexMs := mStats.LastIndexMs;
  Result.Parsed := mStats.LastIndex.Parsed;
  Result.FromCache := mStats.LastIndex.FromCache;
  Result.Missing := mStats.LastIndex.Missing;
  Result.LastUpdate := mStats.LastUpdate;
  Result.CacheFile := mFiles.ProjectFile;
  Result.LibraryCacheFile := mFiles.LibraryFile;
  // Projektwahl (#46); aktiv und ausgewählt ergänzt die Komposition.
  Result.Project := FSetup.ProjectFile;
  if FState.Project(mProject) then
  begin
    Result.Project := mProject.FileName;
    Result.Config := mProject.Config;
    Result.Platform := mProject.Platform;
  end;
  Result.BuildChosen := FBuild.Chosen;
  Result.CacheBytes := TIndexCacheDirectory.SizeOf([Result.CacheFile]);
  Result.LibraryCacheBytes := TIndexCacheDirectory.SizeOf([Result.LibraryCacheFile]);
end;

procedure TShellWorkspace.Activate;
begin
  if not FSetup.Deferred or FSetup.Activated then
  begin
    Exit;
  end;
  FSetup.Activated := True;
  // Mit index.projectGroup = true ist der Arbeitsbereich schon indiziert.
  if FConfiguration.Settings.IndexProjectGroup then
  begin
    Exit;
  end;
  FLogger.Info(Format('%s: Datei des Projekts geöffnet, Index wird aufgebaut', [TLogMarks.Name(FName)]));
  Reload;
end;

function TShellWorkspace.RuleServices: TRuleServices;
begin
  Result := TShellRuleProjects.ServicesOf(FState, FSetup, FIndexing.Index,
    function(const AUnitName: string): Boolean
    begin
      Result := EnsureUnit(AUnitName);
    end);
end;

function TShellWorkspace.RuleReady(out AReason: string): Boolean;
var
  mInfo: TProjectInfo;
begin
  AReason := '';
  if FState.ProjectPending or not (FState.Project(mInfo) or FState.WithoutProject) then
  begin
    AReason := 'Projekte werden geladen';
    Exit(False);
  end;
  if IndexLoading >= 0 then
  begin
    AReason := 'Index wird aufgebaut';
    Exit(False);
  end;
  Result := True;
end;

{ TShellWorkspaces }

class function TShellWorkspaces.Choose(AFound: TShellWorkspace; const AAll: TList<TShellWorkspace>): TShellWorkspace;
begin
  Result := AFound;
  if (Result = nil) and (AAll <> nil) and (AAll.Count = 1) then
  begin
    Result := AAll[0];
  end;
end;

end.
