unit Shell.Workspace;

// Host-Rolle Shell: ein Ordner des Arbeitsbereichs mit eigener
// atlas.json, eigenem Projekt und eigenem Indexaufbau. Alle Ordner
// schreiben in denselben Symbolindex, damit Navigation und Suche über
// Ordnergrenzen funktionieren.
// Projektgruppe (#648): Je Projekt der Gruppe ein Arbeitsbereich mit fest
// vorgegebener Projektdatei (ProjectFile); mehrere können denselben Ordner
// haben. Der gemeinsame Scheduler ordnet ihre Aufbauten.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.Configuration,
  Atlas.Common.Lsp.WorkDoneProgress,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.UnitResolver,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Service,
  Atlas.Common.Index.Builder,
  Atlas.Common.Index.Scheduler,
  Atlas.Common.Rules.Baseline,
  Atlas.Common.Lsp.Status;

type
  TShellWorkspace = class
  private
    FRoot: string;
    FName: string;
    FLogger: ILogger;
    FIndex: ISymbolIndex;
    FConfiguration: TLspConfiguration;
    FIndexService: TIndexService;
    FProgress: TLspWorkDoneProgress;
    FUnitResolver: TUnitResolver;
    /// <summary>Frühere Resolver: Der alte Builder bedient EnsureUnit, bis der neue veröffentlicht ist,
    /// und ruft sie dabei noch auf. Freigabe erst mit dem Arbeitsbereich.</summary>
    FRetiredResolvers: TObjectList<TUnitResolver>;
    FSignature: string;
    // Schützt Defines und Namespaces, die Anfrage-Threads lesen.
    FLock: TObject;
    FDefines: TArray<string>;
    FHasDefines: Boolean;
    FNamespaces: TArray<string>;
    FSearchPaths: TArray<string>;
    FProjectFiles: TArray<string>;
    /// <summary>Alle Units der Suchpfade im Index (#648), unter FLock.</summary>
    FSearchFiles: TArray<string>;
    /// <summary>Projektdateien und Suchpfad-Units in Großschreibung, für ContainsFile; unter FLock.</summary>
    FOwnFiles: TDictionary<string, Boolean>;
    /// <summary>Fest vorgegebene Projektdatei (Projektgruppe, #648); '' = im Ordner suchen.</summary>
    FFixedProject: string;
    FPriority: Integer;
    FScheduler: TIndexScheduler;
    /// <summary>Aus der Projektgruppe: Mit index.projectGroup = false erst indizieren, wenn eine Datei des
    /// Projekts geöffnet wird (Activate).</summary>
    FDeferred: Boolean;
    FActivated: Boolean;
    FOrigin: string;
    // Für den Compileraufruf (#40), unter FLock.
    FProject: TProjectInfo;
    FHasProject: Boolean;
    FBdsRoot: string;
    FDelphiVersion: string;
    /// <summary>Beim nächsten Indexaufbau den Cache verwerfen (#49).</summary>
    FDiscardCache: Boolean;
    FCompilerLibraryPaths: TArray<string>;
    // Per Befehl gewählte Konfiguration und Plattform (#46), unter FLock; '' = Einstellung.
    FBuildConfig: string;
    FBuildPlatform: string;
    FOnProjectLoaded: TProc;
    FOnIndexFinished: TProc;
    FOnProjectReady: TProc;
    FOnIndexEvent: TProc<string>;
    FOnNames: TProc<TArray<string>>;
    /// <summary>Ein Aufbau läuft und hat die Projektstufe noch nicht hinter sich.</summary>
    FProjectPending: Boolean;
    FOnSettingsChanged: TProc<TServerSettings>;
    FBaseline: IRuleBaseline;
    FLastIndexMs: Int64;
    FLastIndex: TIndexBuildResult;
    /// <summary>Sperre des eigenen Index-Caches (#184); nil, wenn eine andere Instanz ihn hält.</summary>
    FCacheLock: TStream;
    FCacheLockFile: string;
    FBaselineTime: TDateTime;
    /// <summary>Sperrt ACacheFile, gibt eine alte Sperre frei; False = nur lesen. Beim Aufräumen bleiben
    /// ACacheFile und ALibraryCacheFile stehen (#616).</summary>
    function LockCache(const ACacheFile, ALibraryCacheFile: string): Boolean;
    /// <summary>Weist auf gemischte Kodierungen der Projektdateien hin (Index-Thread).</summary>
    procedure ReportEncodings;
    procedure IndexEvent(const AText: string);
    procedure StartIndex(const ASettings: TServerSettings);
    function FindProjectFile(const ASettings: TServerSettings): string;
    function GetNamespaces: TArray<string>;
    function GetIncludePaths: TArray<string>;
    function GetProjectFiles: TArray<string>;
  public
    constructor Create(const ARoot, AName: string; const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
      const ALogger: ILogger; const AIndex: ISymbolIndex; const AProgressToken: string);
    destructor Destroy; override;
    /// <summary>Liest atlas.json des Ordners und startet den Indexaufbau.</summary>
    procedure Load;
    /// <summary>Lädt das Projekt neu, auch wenn sich die Einstellungen nicht geändert haben.</summary>
    procedure Reload;
    /// <summary>Baut den Index ohne Cache neu auf (Befehl „Index neu aufbauen“, #49).</summary>
    procedure Rebuild;
    /// <summary>Hält den Indexaufbau an.</summary>
    procedure Stop;
    function EnsureUnit(const AUnitName: string): Boolean;
    function ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
    function ApplyText(const AFileName, AText: string): Boolean;
    /// <summary>Symbole des Projekts für das Abblenden; False ohne Projekt. Threadsicher.</summary>
    function Defines(out ADefines: TArray<string>): Boolean;
    /// <summary>
    /// atlas-baseline.json des Ordners (#97), neu gelesen, sobald sich die
    /// Datei ändert; nil ohne oder bei ungültiger Datei. Threadsicher.
    /// </summary>
    function Baseline: IRuleBaseline;
    /// <summary>Aufruf des Compilers für das Projekt (#40); False mit Grund in AError
    /// ohne Projekt, Installation oder unterstützte Plattform. Threadsicher.</summary>
    function CompilerRequest(out ARequest: TCompilerRequest; out AError: string): Boolean;
    /// <summary>Wechselt Konfiguration und/oder Plattform ('' = unverändert) und lädt das Projekt neu (#46).
    /// False mit Grund in AError ohne Projekt oder bei unbekannten Werten. Threadsicher.</summary>
    function SelectBuild(const AConfig, APlatform: string; out AError: string): Boolean;
    /// <summary>Geladenes Projekt; False ohne Projekt. Threadsicher.</summary>
    function Project(out AProject: TProjectInfo): Boolean;
    /// <summary>Für das Projekt gewählte Delphi-Version (z. B. "23.0", #47); '' ohne Installation. Threadsicher.</summary>
    function DelphiVersion: string;
    /// <summary>Ordner der Delphi-Installation ($(BDS)); '' ohne Installation. Threadsicher.</summary>
    function BdsRoot: string;
    /// <summary>Fortschritt des laufenden Indexaufbaus in Prozent; -1, wenn keiner läuft (#647).</summary>
    function IndexLoading: Integer;
    /// <summary>Letzter Indexlauf für den Status-Befehl (#28). Threadsicher.</summary>
    function IndexStatus: TWorkspaceStatus;
    property Root: string read FRoot;
    property Name: string read FName;
    property Configuration: TLspConfiguration read FConfiguration;
    /// <summary>Unit-Namespaces des Projekts. Threadsicher.</summary>
    property Namespaces: TArray<string> read GetNamespaces;
    /// <summary>Suchpfade für Include-Dateien (#264): Projekt-Suchpfade, dann Bibliothekspfade. Threadsicher.</summary>
    property IncludePaths: TArray<string> read GetIncludePaths;
    /// <summary>Quelltexte des Projekts (Hauptdatei, Units). Threadsicher.</summary>
    property ProjectFiles: TArray<string> read GetProjectFiles;
    /// <summary>Nach dem Laden eines Projekts (Defines und Namespaces neu).</summary>
    property OnProjectLoaded: TProc read FOnProjectLoaded write FOnProjectLoaded;
    /// <summary>Nach einem vollständigen (nicht abgebrochenen) Indexaufbau; im Index-Thread.</summary>
    property OnIndexFinished: TProc read FOnIndexFinished write FOnIndexFinished;
    /// <summary>Projektstufe des Aufbaus fertig (Projektdateien und über uses erreichbare Units); im Index-Thread.</summary>
    property OnProjectReady: TProc read FOnProjectReady write FOnProjectReady;
    /// <summary>Zeile fürs Diagnoselog (#647), nur Zahlen und feste Wörter; im Index- oder Nachrichten-Thread.</summary>
    property OnIndexEvent: TProc<string> read FOnIndexEvent write FOnIndexEvent;
    /// <summary>Projekt- und Unit-Namen nach dem Lesen der .dproj, damit das Server-Log sie verbirgt (#647).</summary>
    property OnNames: TProc<TArray<string>> read FOnNames write FOnNames;
    /// <summary>True, solange ein Aufbau die Projektstufe noch nicht hinter sich hat. Threadsicher.</summary>
    property ProjectPending: Boolean read FProjectPending;
    /// <summary>Nach dem Lesen der Einstellungen, für serverweite Werte wie das Zeitlimit (#283).</summary>
    property OnSettingsChanged: TProc<TServerSettings> read FOnSettingsChanged write FOnSettingsChanged;
    /// <summary>True, wenn AFileName zum Projekt gehört (DCCReference, Hauptdatei oder Suchpfad-Unit). Threadsicher.</summary>
    function ContainsFile(const AFileName: string): Boolean;
    /// <summary>Projekt aus der Gruppe, das mit index.projectGroup = false noch wartet: jetzt indizieren.</summary>
    procedure Activate;
    /// <summary>Vor Load setzen (#648): feste Projektdatei, Reihenfolge, gemeinsamer Scheduler und ob das
    /// Projekt nur aus der Gruppe stammt.</summary>
    property ProjectFile: string read FFixedProject write FFixedProject;
    property Priority: Integer read FPriority write FPriority;
    property Scheduler: TIndexScheduler read FScheduler write FScheduler;
    property Deferred: Boolean read FDeferred write FDeferred;
    /// <summary>Eintrag des Clients, aus dem der Arbeitsbereich stammt (TWorkspaceFolder.Key); zum Entfernen.</summary>
    property Origin: string read FOrigin write FOrigin;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Compiler.CommandLine,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Projects.DprojReader,
  Atlas.Common.Projects.DelphiVersions,
  Atlas.Common.Index.ProjectFiles,
  Atlas.Common.Index.Adapters.DiskFileSystem,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Index.CacheHousekeeping,
  Atlas.Windows.Projects.DelphiInstallation;

const
  /// <summary>So lange wartet ein lesender Prozess höchstens auf den Cache des schreibenden (#62).</summary>
  CacheWaitMs = 120000;

{ TShellWorkspace }

constructor TShellWorkspace.Create(const ARoot, AName: string; const AStore: IDocumentStore;
  const ATransport: IJsonRpcTransport; const ALogger: ILogger; const AIndex: ISymbolIndex;
  const AProgressToken: string);
begin
  inherited Create;
  FRoot := ARoot;
  FName := AName;
  FLogger := ALogger;
  FIndex := AIndex;
  FLock := TObject.Create;
  FOwnFiles := TDictionary<string, Boolean>.Create;
  FRetiredResolvers := TObjectList<TUnitResolver>.Create(True);
  FLastIndexMs := -1;
  FConfiguration := TLspConfiguration.Create(AStore, ATransport,
    function(const AFileName: string; out AText: string): Boolean
    var
      FileFormat: TFileFormat;
    begin
      Result := FileExists(AFileName);
      if Result then
        AText := TFileEncoding.LoadFromFile(AFileName, FileFormat)
      else
        AText := '';
    end);
  FConfiguration.OnChanged :=
    procedure(const ASettings: TServerSettings)
    begin
      FLogger.Info(Format('Einstellungen für %s: Delphi %s, Projekt %s, %d Regeleinstellungen, %d Ausschlüsse',
        [FName, ASettings.DelphiVersion, ASettings.Project, Length(ASettings.Rules), Length(ASettings.Exclude)]));
      // Der Index ist gemeinsam; bei mehreren Ordnern gilt das zuletzt gelesene Budget.
      FIndex.SetBudget(Int64(ASettings.MemoryBudgetMb) * 1024 * 1024);
      if Assigned(FOnSettingsChanged) then
        FOnSettingsChanged(ASettings);
      StartIndex(ASettings);
    end;
  FIndexService := TIndexService.Create(FIndex, TDiskIndexFileSystem.Create);
  FProgress := TLspWorkDoneProgress.Create(ATransport, AProgressToken);
  FIndexService.OnProgress := FProgress.AsIndexProgress();
  FIndexService.OnProjectReady :=
    procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
    begin
      FProjectPending := False;
      IndexEvent(Format('index project#%d projectStage %d ms parsed %d cached %d missing %d',
        [FPriority, AElapsedMs, AResult.Parsed, AResult.FromCache, AResult.Missing]));
      if Assigned(FOnProjectReady) then
        FOnProjectReady();
    end;
  FIndexService.OnFinished :=
    procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
    begin
      // Abgebrochen (Neustart): Der neue Aufbau hat FProjectPending schon wieder gesetzt.
      if not AResult.Cancelled then
        FProjectPending := False;
      IndexEvent(Format('index project#%d done %d ms parsed %d cached %d missing %d units %d resolve %d ms parse %d ms%s',
        [FPriority, AElapsedMs, AResult.Parsed, AResult.FromCache, AResult.Missing, FIndex.UnitCount,
         AResult.ResolveMs, AResult.ParseMs, IfThen(AResult.Cancelled, ' cancelled', '')]));
      if not AResult.Cancelled then
      begin
        TMonitor.Enter(FLock);
        try
          FLastIndexMs := AElapsedMs;
          FLastIndex := AResult;
        finally
          TMonitor.Exit(FLock);
        end;
      end;
      FLogger.Info(Format('Symbolindex für %s fertig in %d ms: %d Units, %d Symbole (%d neu eingelesen, %d aus dem Cache, %d fehlen)%s',
        [FName, AElapsedMs, FIndex.UnitCount, FIndex.SymbolCount, AResult.Parsed, AResult.FromCache, AResult.Missing,
         IfThen(AResult.Cancelled, ', abgebrochen', '')]));
      if not AResult.Cancelled then
      begin
        ReportEncodings;
        if Assigned(FOnIndexFinished) then
          FOnIndexFinished();
      end;
    end;
  FIndexService.OnError :=
    procedure(const AError: Exception)
    begin
      FLogger.Error(Format('Fehler beim Aufbau des Symbolindex für %s: %s: %s', [FName, AError.ClassName, AError.Message]));
    end;
end;

destructor TShellWorkspace.Destroy;
begin
  FIndexService.Free;
  FCacheLock.Free;
  FProgress.Free;
  FUnitResolver.Free;
  FRetiredResolvers.Free;
  FConfiguration.Free;
  FOwnFiles.Free;
  FLock.Free;
  FIndex := nil;
  FLogger := nil;
  inherited;
end;

procedure TShellWorkspace.IndexEvent(const AText: string);
begin
  if Assigned(FOnIndexEvent) then
    FOnIndexEvent(AText);
end;

procedure TShellWorkspace.Load;
begin
  FConfiguration.LoadWorkspace(FRoot);
end;

procedure TShellWorkspace.Reload;
begin
  FSignature := '';
  StartIndex(FConfiguration.Settings);
end;

procedure TShellWorkspace.Rebuild;
begin
  FDiscardCache := True;
  Reload;
end;

procedure TShellWorkspace.Stop;
begin
  FIndexService.Stop;
end;

procedure TShellWorkspace.Activate;
begin
  if not FDeferred or FActivated then
    Exit;
  FActivated := True;
  // Mit index.projectGroup = true ist der Arbeitsbereich schon indiziert.
  if Configuration.Settings.IndexProjectGroup then
    Exit;
  FLogger.Info(Format('%s: Datei des Projekts geöffnet, Index wird aufgebaut', [FName]));
  Reload;
end;

function TShellWorkspace.ContainsFile(const AFileName: string): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FOwnFiles.ContainsKey(AnsiUpperCase(AFileName));
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.EnsureUnit(const AUnitName: string): Boolean;
begin
  Result := FIndexService.EnsureUnit(AUnitName);
end;

function TShellWorkspace.ApplyText(const AFileName, AText: string): Boolean;
begin
  Result := FIndexService.ApplyText(AFileName, AText);
end;

function TShellWorkspace.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
begin
  Result := FIndexService.ApplyChanges(AChanges);
end;

function TShellWorkspace.Defines(out ADefines: TArray<string>): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    ADefines := FDefines;
    Result := FHasDefines;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.LockCache(const ACacheFile, ALibraryCacheFile: string): Boolean;
var
  Removed: Integer;
begin
  if SameText(ACacheFile, FCacheLockFile) and (FCacheLock <> nil) then
    Exit(True);
  FreeAndNil(FCacheLock);
  FCacheLockFile := ACacheFile;
  FCacheLock := TIndexCacheDirectory.TryLock(ACacheFile);
  Result := FCacheLock <> nil;
  try
    // Der gemeinsame Bibliotheks-Cache ist nicht gesperrt; ohne ihn hier zu nennen, löschte das Aufräumen
    // ihn bei jedem Start, sobald der Ordner über der Höchstgröße lag (#616: "0 aus dem Cache").
    Removed := TIndexCacheDirectory.Cleanup(TIndexCacheDirectory.DefaultRoot,
      TIndexCacheHousekeeping.DefaultMaxBytes, TArray<string>.Create(ACacheFile, ALibraryCacheFile));
    if Removed > 0 then
      FLogger.Info(Format('%d alte Index-Caches gelöscht (Höchstgröße %d MB)',
        [Removed, TIndexCacheHousekeeping.DefaultMaxBytes div (1024 * 1024)]));
  except
    on E: Exception do
      FLogger.Warning(Format('Aufräumen des Cache-Ordners fehlgeschlagen: %s', [E.Message]));
  end;
end;

function TShellWorkspace.SelectBuild(const AConfig, APlatform: string; out AError: string): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    if not FHasProject then
      AError := Format('Für %s ist kein Projekt geladen.', [FName])
    else
      AError := TDprojReader.CheckTarget(FProject, AConfig, APlatform);
    Result := AError = '';
    if Result then
    begin
      if AConfig <> '' then
        FBuildConfig := AConfig;
      if APlatform <> '' then
        FBuildPlatform := APlatform;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  if Result then
  begin
    FLogger.Info(Format('%s: Konfiguration %s, Plattform %s gewählt', [FName, AConfig, APlatform]));
    Reload;
  end;
end;

function TShellWorkspace.DelphiVersion: string;
begin
  TMonitor.Enter(FLock);
  try
    Result := FDelphiVersion;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.BdsRoot: string;
begin
  TMonitor.Enter(FLock);
  try
    Result := FBdsRoot;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.IndexLoading: Integer;
begin
  if FProgress.Active then
    Result := FProgress.Percent
  else
    Result := -1;
end;

function TShellWorkspace.Project(out AProject: TProjectInfo): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FHasProject;
    if Result then
      AProject := FProject
    else
      AProject := Default(TProjectInfo);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.IndexStatus: TWorkspaceStatus;
begin
  TMonitor.Enter(FLock);
  try
    Result.Name := FName;
    Result.LastIndexMs := FLastIndexMs;
    Result.Parsed := FLastIndex.Parsed;
    Result.FromCache := FLastIndex.FromCache;
    Result.Missing := FLastIndex.Missing;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.Baseline: IRuleBaseline;
var
  FileName: string;
  FileTime: TDateTime;
  FileFormat: TFileFormat;
begin
  FileName := ExistingOrLegacyFile(FRoot, BaselineFileName, LegacyBaselineFileName);
  TMonitor.Enter(FLock);
  try
    if not TFile.Exists(FileName) then
    begin
      FBaseline := nil;
      FBaselineTime := 0;
      Exit(nil);
    end;
    FileTime := TFile.GetLastWriteTime(FileName);
    if FileTime <> FBaselineTime then
    begin
      FBaselineTime := FileTime;
      try
        FBaseline := TRuleBaseline.FromJson(TFileEncoding.LoadFromFile(FileName, FileFormat));
        FLogger.Info(Format('Baseline für %s geladen: %d bekannte Treffer', [FName, FBaseline.Count]));
      except
        on E: Exception do
        begin
          FBaseline := nil;
          FLogger.Error(Format('Baseline %s nicht lesbar: %s', [FileName, E.Message]));
        end;
      end;
    end;
    Result := FBaseline;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.CompilerRequest(out ARequest: TCompilerRequest; out AError: string): Boolean;
var
  Project: TProjectInfo;
  HasProject: Boolean;
  BdsRoot, OutputDir: string;
  LibraryPaths: TArray<string>;
begin
  ARequest := Default(TCompilerRequest);
  AError := '';
  TMonitor.Enter(FLock);
  try
    Project := FProject;
    HasProject := FHasProject;
    BdsRoot := FBdsRoot;
    LibraryPaths := FCompilerLibraryPaths;
  finally
    TMonitor.Exit(FLock);
  end;
  if not HasProject then
  begin
    AError := 'Kein Projekt geladen';
    Exit(False);
  end;
  if BdsRoot = '' then
  begin
    AError := 'Delphi-Installation nicht gefunden';
    Exit(False);
  end;
  // Eigener Ausgabeordner je Projekt, Plattform und Konfiguration; der Build des Entwicklers bleibt unberührt.
  OutputDir := TPath.Combine(TPath.GetTempPath, Format('Atlas\dcc-%.8x\%s-%s',
    [Cardinal(LowerCase(Project.FileName).GetHashCode), Project.Platform, Project.Config]));
  try
    ARequest := TCompilerCommandLine.Build(Project, LibraryPaths, BdsRoot, OutputDir);
    // Die Starter Edition liefert keinen Kommandozeilen-Compiler mit.
    if not FileExists(ARequest.Executable) then
    begin
      AError := Format('Kein Kommandozeilen-Compiler gefunden (%s), z. B. in der Starter Edition', [ARequest.Executable]);
      Exit(False);
    end;
    ForceDirectories(OutputDir);
    Result := True;
  except
    on E: ECompilerError do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

function TShellWorkspace.GetProjectFiles: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FProjectFiles;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.GetIncludePaths: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FSearchPaths + FCompilerLibraryPaths;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspace.GetNamespaces: TArray<string>;
begin
  TMonitor.Enter(FLock);
  try
    Result := FNamespaces;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellWorkspace.ReportEncodings;
var
  Files: TArray<string>;
  FileName: string;
  Survey: TEncodingSurvey;
begin
  TMonitor.Enter(FLock);
  try
    Files := FProjectFiles;
  finally
    TMonitor.Exit(FLock);
  end;
  Survey := Default(TEncodingSurvey);
  for FileName in Files do
    if FileExists(FileName) then
      Survey.Add(TFile.ReadAllBytes(FileName));
  if Survey.IsMixed then
    FLogger.Warning(Format('Gemischte Kodierungen im Projekt %s: %s. Beim Schreiben behält jede Datei ihre Kodierung.',
      [FName, Survey.Describe]))
  else
    FLogger.Debug(Format('Kodierungen im Projekt %s: %s', [FName, Survey.Describe]));
end;

function TShellWorkspace.FindProjectFile(const ASettings: TServerSettings): string;
var
  Candidates: TArray<string>;
begin
  Result := '';
  // Aus der Projektgruppe (#648): Die Datei ist vorgegeben, auch wenn mehrere im Ordner liegen.
  if FFixedProject <> '' then
  begin
    if FileExists(FFixedProject) then
      Result := FFixedProject
    else
      FLogger.Warning('Projektdatei nicht gefunden: ' + FFixedProject);
    Exit;
  end;
  if ASettings.Project <> '' then
  begin
    if TProjectPaths.IsAbsolute(ASettings.Project) then
      Result := ASettings.Project
    else if FRoot <> '' then
      Result := TProjectPaths.Combine(FRoot, ASettings.Project);
    if not FileExists(Result) then
    begin
      FLogger.Warning('Projektdatei nicht gefunden: ' + Result);
      Result := '';
    end;
    Exit;
  end;
  // Ohne Angabe: die einzige .dproj im Ordner.
  if (FRoot = '') or not TDirectory.Exists(FRoot) then
    Exit;
  Candidates := TDirectory.GetFiles(FRoot, '*.dproj');
  if Length(Candidates) = 1 then
    Result := Candidates[0]
  else if Length(Candidates) > 1 then
    FLogger.Info(Format('%d Projektdateien in %s; "project" in %s wählt eine aus',
      [Length(Candidates), FRoot, ConfigurationFileName]));
end;

procedure TShellWorkspace.StartIndex(const ASettings: TServerSettings);
var
  ProjectFile, Signature, State, CacheFile: string;
  Installation: ILibraryPathProvider;
  Options: TDprojOptions;
  Project: TProjectInfo;
  LibraryPaths: TArray<string>;
  Request: TIndexRequest;
  Resolver: TUnitResolver;
  FileExistsFunc: TFunc<string, Boolean>;
  ProjectVersion, Version: string;
  ListUnits: TIndexListUnits;
  Excluded: TIndexExcluded;
  Exclude, Files, SearchFiles, LibraryFiles: TArray<string>;
  FileName: string;
  Names: TArray<string>;
  ProjectUnit: TProjectUnit;
begin
  // Mit index.projectGroup = false nur das Projekt der geöffneten Datei (#648).
  if FDeferred and not FActivated and not ASettings.IndexProjectGroup then
  begin
    FLogger.Info(Format('%s: index.projectGroup ist aus; indiziert wird, sobald eine Datei des Projekts offen ist',
      [FName]));
    Exit;
  end;
  ProjectFile := FindProjectFile(ASettings);
  if ProjectFile = '' then
    Exit;
  // Konfiguration vor ProjectVersion der .dproj vor neuester Installation (#47).
  try
    ProjectVersion := TDelphiVersions.ProjectVersionOf(TFile.ReadAllText(ProjectFile));
  except
    on Exception do
      ProjectVersion := '';
  end;
  try
    Version := TDelphiVersions.Choose(ASettings.DelphiVersion, ProjectVersion, TDelphiInstallation.Versions);
    if Version <> '' then
    begin
      Installation := TDelphiInstallation.Create(Version);
      FLogger.Info(Format('%s: %s (BDS %s, ProjectVersion %s)',
        [FName, TDelphiVersions.ProductName(Version), Version, ProjectVersion]));
    end
    else
      Installation := nil;
  except
    on E: EProjectError do
    begin
      FLogger.Warning('Delphi-Installation nicht gefunden: ' + E.Message);
      Installation := nil;
      Version := '';
    end;
  end;
  FileExistsFunc :=
    function(AFileName: string): Boolean
    begin
      Result := FileExists(AFileName);
    end;
  Options := Default(TDprojOptions);
  Options.Config := ASettings.Config;
  Options.Platform := ASettings.Platform;
  TMonitor.Enter(FLock);
  try
    if FBuildConfig <> '' then
      Options.Config := FBuildConfig;
    if FBuildPlatform <> '' then
      Options.Platform := FBuildPlatform;
  finally
    TMonitor.Exit(FLock);
  end;
  Options.FileExists := FileExistsFunc;
  if Installation <> nil then
    Options.Variables := Installation.Variables;
  try
    Project := TDprojReader.Load(ProjectFile, Options);
  except
    on E: EProjectError do
    begin
      FLogger.Error(Format('Projekt %s nicht lesbar: %s', [ProjectFile, E.Message]));
      Exit;
    end;
  end;
  if Assigned(FOnNames) then
  begin
    Names := [ChangeFileExt(ExtractFileName(Project.FileName), ''),
      ChangeFileExt(ExtractFileName(Project.MainSource), '')];
    for ProjectUnit in Project.Units do
      Names := Names + [ProjectUnit.Name];
    FOnNames(Names);
  end;
  TMonitor.Enter(FLock);
  try
    FProject := Project;
    FHasProject := True;
    if Installation <> nil then
    begin
      FDelphiVersion := Version;
      FBdsRoot := TCompilerCommandLine.BdsRoot(Installation.Variables);
      FCompilerLibraryPaths := Installation.LibraryPaths(Project.Platform);
    end
    else
    begin
      FDelphiVersion := '';
      FBdsRoot := '';
      FCompilerLibraryPaths := nil;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  Signature := TIndexProjectFiles.Signature(Project, Version);
  if Installation <> nil then
    LibraryPaths := Installation.LibraryPaths(Project.Platform) + Installation.BrowsingPaths(Project.Platform)
  else
    LibraryPaths := nil;
  // Alle Units der Such- und Bibliothekspfade (#648), nicht nur die über uses erreichbaren.
  ListUnits :=
    function(const AFolder: string): TArray<string>
    begin
      Result := nil;
      try
        if TDirectory.Exists(AFolder) then
          Result := TDirectory.GetFiles(AFolder, '*.pas');
      except
        // Nicht lesbare Ordner (Rechte, Netzlaufwerk) tragen nichts bei.
        on Exception do
          Result := nil;
      end;
    end;
  Exclude := ASettings.IndexExclude;
  Excluded :=
    function(const AFileName: string): Boolean
    var
      Pattern: string;
    begin
      for Pattern in Exclude do
        if MatchesGlob(Pattern, AFileName) then
          Exit(True);
      Result := False;
    end;
  Files := TIndexProjectFiles.Files(Project);
  SearchFiles := nil;
  if ASettings.IndexSearchPaths then
    SearchFiles := TIndexProjectFiles.PathFiles(Project.SearchPaths, ListUnits, Excluded, Files);
  LibraryFiles := nil;
  if ASettings.IndexLibraryPaths then
    LibraryFiles := TIndexProjectFiles.PathFiles(LibraryPaths, ListUnits, Excluded, Files + SearchFiles);
  // Neu indexieren, wenn sich Schlüssel oder Unit-Listen ändern; der Cache hängt nur am Schlüssel.
  State := Signature + '#' + AnsiUpperCase(String.Join(';', Files)) + '#' +
    AnsiUpperCase(String.Join(';', SearchFiles)) + '#' + AnsiUpperCase(String.Join(';', LibraryFiles));
  if State = FSignature then
    Exit;
  FSignature := State;
  FIndexService.Stop;
  Resolver := TUnitResolver.Create(Project, LibraryPaths, FileExistsFunc);
  // Nicht freigeben: Anfragen können den alten Builder noch nutzen (EnsureUnit ohne Sperre, #647).
  if FUnitResolver <> nil then
    FRetiredResolvers.Add(FUnitResolver);
  FUnitResolver := Resolver;
  Request.Files := Files;
  Request.SearchFiles := SearchFiles;
  Request.LibraryFiles := LibraryFiles;
  Request.Priority := FPriority;
  FIndexService.Scheduler := FScheduler;
  Request.Defines := TIndexProjectFiles.Defines(Project, Version);
  // RTL, VCL und FMX einmal je Compiler und Plattform, unabhängig von Projekt und Konfiguration (#647).
  // Nur der Ordner der Installation: Eigener Code im Bibliothekspfad wird oft mit dem Projekt übersetzt.
  if Installation <> nil then
  begin
    Request.LibraryRoots := [TCompilerCommandLine.BdsRoot(Installation.Variables)];
    Request.LibraryDefines := TIndexProjectFiles.LibraryDefines(Project, Version);
  end;
  // $I-Dateien wie beim Compiler: Projekt-Suchpfade, dann Bibliothekspfade (#264).
  if Installation <> nil then
    Request.IncludePaths := Project.SearchPaths + Installation.LibraryPaths(Project.Platform)
  else
    Request.IncludePaths := Project.SearchPaths;
  Request.ResolveUnit :=
    function(const AUnitName: string): string
    begin
      Result := Resolver.Resolve(AUnitName);
    end;
  CacheFile := TIndexCacheDirectory.FileFor(TIndexCacheDirectory.DefaultRoot, Signature);
  Request.CacheFile := CacheFile;
  // RTL/VCL/FMX einmal je Compilerversion und Plattform, geteilt mit allen Projekten (#492, #647).
  Request.LibraryCacheFile := TIndexCacheDirectory.FileFor(TIndexCacheDirectory.DefaultRoot,
    TIndexProjectFiles.LibrarySignature(Project, Version));
  Request.ReadOnlyCache := not LockCache(CacheFile, Request.LibraryCacheFile);
  if Request.ReadOnlyCache then
  begin
    FLogger.Info(Format('Cache %s wird von einer anderen Instanz geschrieben und hier nur gelesen', [CacheFile]));
    // Auf deren Stand warten statt alles doppelt zu lesen (#62), begrenzt.
    Request.CacheBusy :=
      function: Boolean
      begin
        Result := TIndexCacheDirectory.IsLocked(CacheFile);
      end;
    Request.CacheWaitMs := CacheWaitMs;
  end;
  if FDiscardCache then
  begin
    FDiscardCache := False;
    if not Request.ReadOnlyCache and TFile.Exists(CacheFile) then
      try
        TFile.Delete(CacheFile);
        if TFile.Exists(Request.LibraryCacheFile) then
          TFile.Delete(Request.LibraryCacheFile);
        FLogger.Info('Index-Cache verworfen: ' + CacheFile);
      except
        on E: Exception do
          FLogger.Warning(Format('Index-Cache %s nicht löschbar: %s', [CacheFile, E.Message]));
      end;
  end;
  TMonitor.Enter(FLock);
  try
    // Dieselben Symbole bestimmen, welche {$IFDEF}-Zweige der Editor abblendet.
    FDefines := Request.Defines;
    FHasDefines := True;
    FNamespaces := Project.Namespaces;
    FSearchPaths := Project.SearchPaths;
    FProjectFiles := Request.Files;
    FSearchFiles := Request.SearchFiles;
    FOwnFiles.Clear;
    for FileName in Request.Files + Request.SearchFiles do
      FOwnFiles.AddOrSetValue(AnsiUpperCase(FileName), True);
  finally
    TMonitor.Exit(FLock);
  end;
  FLogger.Info(Format('Symbolindex für %s (%s, %s): %d Projektdateien, %d Units der Suchpfade, %d der Bibliothek, Cache %s',
    [ProjectFile, Project.Config, Project.Platform, Length(Request.Files), Length(Request.SearchFiles),
     Length(Request.LibraryFiles), CacheFile]));
  IndexEvent(Format('index project#%d start files %d search %d library %d cache %s',
    [FPriority, Length(Request.Files), Length(Request.SearchFiles), Length(Request.LibraryFiles),
     IfThen(Request.ReadOnlyCache, 'readOnly', 'write')]));
  FProjectPending := True;
  FIndexService.Start(Request);
  if Assigned(FOnProjectLoaded) then
    FOnProjectLoaded();
end;

end.
