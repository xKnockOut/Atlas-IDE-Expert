unit Shell.Workspace;

// Host-Rolle Shell: ein Ordner des Arbeitsbereichs mit eigener
// delphi-lsp.json, eigenem Projekt und eigenem Indexaufbau. Alle Ordner
// schreiben in denselben Symbolindex, damit Navigation und Suche über
// Ordnergrenzen funktionieren.

interface

uses
  System.SysUtils,
  System.Classes,
  BDLsp.Common.Logging.Contract,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Lsp.Configuration,
  BDLsp.Common.Lsp.WorkDoneProgress,
  BDLsp.Common.Projects.Contract,
  BDLsp.Common.Projects.UnitResolver,
  BDLsp.Common.Compiler.Contract,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Index.Service,
  BDLsp.Common.Rules.Baseline,
  BDLsp.Common.Lsp.Status;

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
    FSignature: string;
    // Schützt Defines und Namespaces, die Anfrage-Threads lesen.
    FLock: TObject;
    FDefines: TArray<string>;
    FHasDefines: Boolean;
    FNamespaces: TArray<string>;
    FSearchPaths: TArray<string>;
    FProjectFiles: TArray<string>;
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
    FBaseline: IRuleBaseline;
    FLastIndexMs: Int64;
    FLastIndex: TIndexBuildResult;
    /// <summary>Sperre des eigenen Index-Caches (#184); nil, wenn eine andere Instanz ihn hält.</summary>
    FCacheLock: TStream;
    FCacheLockFile: string;
    /// <summary>Sperrt ACacheFile, gibt eine alte Sperre frei; False = nur lesen.</summary>
    function LockCache(const ACacheFile: string): Boolean;
    FBaselineTime: TDateTime;
    /// <summary>Weist auf gemischte Kodierungen der Projektdateien hin (Index-Thread).</summary>
    procedure ReportEncodings;
    procedure StartIndex(const ASettings: TServerSettings);
    function FindProjectFile(const ASettings: TServerSettings): string;
    function GetNamespaces: TArray<string>;
    function GetIncludePaths: TArray<string>;
    function GetProjectFiles: TArray<string>;
  public
    constructor Create(const ARoot, AName: string; const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
      const ALogger: ILogger; const AIndex: ISymbolIndex; const AProgressToken: string);
    destructor Destroy; override;
    /// <summary>Liest delphi-lsp.json des Ordners und startet den Indexaufbau.</summary>
    procedure Load;
    /// <summary>Lädt das Projekt neu, auch wenn sich die Einstellungen nicht geändert haben.</summary>
    procedure Reload;
    /// <summary>Baut den Index ohne Cache neu auf (Befehl „Index neu aufbauen“, #49).</summary>
    procedure Rebuild;
    /// <summary>Hält den Indexaufbau an.</summary>
    procedure Stop;
    function EnsureUnit(const AUnitName: string): Boolean;
    function ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
    /// <summary>Symbole des Projekts für das Abblenden; False ohne Projekt. Threadsicher.</summary>
    function Defines(out ADefines: TArray<string>): Boolean;
    /// <summary>
    /// delphi-lsp-baseline.json des Ordners (#97), neu gelesen, sobald sich die
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
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  BDLsp.Common.Documents.FileEncoding,
  BDLsp.Common.Compiler.CommandLine,
  BDLsp.Common.Projects.Paths,
  BDLsp.Common.Projects.DprojReader,
  BDLsp.Common.Projects.DelphiVersions,
  BDLsp.Common.Index.Builder,
  BDLsp.Common.Index.ProjectFiles,
  BDLsp.Common.Index.Adapters.DiskFileSystem,
  BDLsp.Common.Index.Adapters.CacheDirectory,
  BDLsp.Common.Index.CacheHousekeeping,
  BDLsp.Windows.Projects.DelphiInstallation;

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
      StartIndex(ASettings);
    end;
  FIndexService := TIndexService.Create(FIndex, TDiskIndexFileSystem.Create);
  FProgress := TLspWorkDoneProgress.Create(ATransport, AProgressToken);
  FIndexService.OnProgress := FProgress.AsIndexProgress;
  FIndexService.OnFinished :=
    procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
    begin
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
        ReportEncodings;
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
  FConfiguration.Free;
  FLock.Free;
  FIndex := nil;
  FLogger := nil;
  inherited;
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

function TShellWorkspace.EnsureUnit(const AUnitName: string): Boolean;
begin
  Result := FIndexService.EnsureUnit(AUnitName);
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

function TShellWorkspace.LockCache(const ACacheFile: string): Boolean;
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
    Removed := TIndexCacheDirectory.Cleanup(TIndexCacheDirectory.DefaultRoot,
      TIndexCacheHousekeeping.DefaultMaxBytes, ACacheFile);
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
  FileName := TPath.Combine(FRoot, BaselineFileName);
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
  OutputDir := TPath.Combine(TPath.GetTempPath, Format('BetterDelphiLSP\dcc-%.8x\%s-%s',
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
begin
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
  // Neu indexieren, wenn sich Schlüssel oder Unit-Liste ändern; der Cache hängt nur am Schlüssel.
  State := Signature + '#' + AnsiUpperCase(String.Join(';', TIndexProjectFiles.Files(Project)));
  if State = FSignature then
    Exit;
  FSignature := State;
  FIndexService.Stop;
  if Installation <> nil then
    LibraryPaths := Installation.LibraryPaths(Project.Platform) + Installation.BrowsingPaths(Project.Platform)
  else
    LibraryPaths := nil;
  Resolver := TUnitResolver.Create(Project, LibraryPaths, FileExistsFunc);
  FUnitResolver.Free;
  FUnitResolver := Resolver;
  Request.Files := TIndexProjectFiles.Files(Project);
  Request.Defines := TIndexProjectFiles.Defines(Project, Version);
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
  CacheFile := TPath.Combine(TIndexCacheDirectory.DefaultRoot,
    Format('index-%.8x.json', [Cardinal(Signature.GetHashCode)]));
  Request.CacheFile := CacheFile;
  Request.ReadOnlyCache := not LockCache(CacheFile);
  if Request.ReadOnlyCache then
    FLogger.Info(Format('Cache %s wird von einer anderen Instanz geschrieben und hier nur gelesen', [CacheFile]));
  if FDiscardCache then
  begin
    FDiscardCache := False;
    if not Request.ReadOnlyCache and TFile.Exists(CacheFile) then
      try
        TFile.Delete(CacheFile);
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
  finally
    TMonitor.Exit(FLock);
  end;
  FLogger.Info(Format('Symbolindex für %s (%s, %s): %d Projektdateien, Cache %s',
    [ProjectFile, Project.Config, Project.Platform, Length(Request.Files), CacheFile]));
  FIndexService.Start(Request);
  if Assigned(FOnProjectLoaded) then
    FOnProjectLoaded();
end;

end.
