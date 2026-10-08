unit Shell.Workspace;

// Host-Rolle Shell: ein Ordner des Arbeitsbereichs mit eigener
// delphi-lsp.json, eigenem Projekt und eigenem Indexaufbau. Alle Ordner
// schreiben in denselben Symbolindex, damit Navigation und Suche über
// Ordnergrenzen funktionieren.

interface

uses
  System.SysUtils,
  BDLsp.Common.Logging.Contract,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Lsp.Configuration,
  BDLsp.Common.Lsp.WorkDoneProgress,
  BDLsp.Common.Projects.UnitResolver,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Index.Service,
  BDLsp.Common.Rules.Baseline;

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
    FProjectFiles: TArray<string>;
    FOnProjectLoaded: TProc;
    FBaseline: IRuleBaseline;
    FBaselineTime: TDateTime;
    /// <summary>Weist auf gemischte Kodierungen der Projektdateien hin (Index-Thread).</summary>
    procedure ReportEncodings;
    procedure StartIndex(const ASettings: TServerSettings);
    function FindProjectFile(const ASettings: TServerSettings): string;
    function GetNamespaces: TArray<string>;
  public
    constructor Create(const ARoot, AName: string; const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
      const ALogger: ILogger; const AIndex: ISymbolIndex; const AProgressToken: string);
    destructor Destroy; override;
    /// <summary>Liest delphi-lsp.json des Ordners und startet den Indexaufbau.</summary>
    procedure Load;
    /// <summary>Lädt das Projekt neu, auch wenn sich die Einstellungen nicht geändert haben.</summary>
    procedure Reload;
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
    property Root: string read FRoot;
    property Name: string read FName;
    property Configuration: TLspConfiguration read FConfiguration;
    /// <summary>Unit-Namespaces des Projekts. Threadsicher.</summary>
    property Namespaces: TArray<string> read GetNamespaces;
    /// <summary>Nach dem Laden eines Projekts (Defines und Namespaces neu).</summary>
    property OnProjectLoaded: TProc read FOnProjectLoaded write FOnProjectLoaded;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  BDLsp.Common.Documents.FileEncoding,
  BDLsp.Common.Projects.Contract,
  BDLsp.Common.Projects.Paths,
  BDLsp.Common.Projects.DprojReader,
  BDLsp.Common.Index.Builder,
  BDLsp.Common.Index.ProjectFiles,
  BDLsp.Common.Index.Adapters.DiskFileSystem,
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
      StartIndex(ASettings);
    end;
  FIndexService := TIndexService.Create(FIndex, TDiskIndexFileSystem.Create);
  FProgress := TLspWorkDoneProgress.Create(ATransport, AProgressToken);
  FIndexService.OnProgress := FProgress.AsIndexProgress();
  FIndexService.OnFinished :=
    procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
    begin
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
  ProjectFile, Signature, CacheFile: string;
  Installation: ILibraryPathProvider;
  Options: TDprojOptions;
  Project: TProjectInfo;
  LibraryPaths: TArray<string>;
  Request: TIndexRequest;
  Resolver: TUnitResolver;
  FileExistsFunc: TFunc<string, Boolean>;
begin
  ProjectFile := FindProjectFile(ASettings);
  if ProjectFile = '' then
    Exit;
  try
    if ASettings.DelphiVersion <> '' then
      Installation := TDelphiInstallation.Create(ASettings.DelphiVersion)
    else
      Installation := TDelphiInstallation.Latest;
  except
    on E: EProjectError do
    begin
      FLogger.Warning('Delphi-Installation nicht gefunden: ' + E.Message);
      Installation := nil;
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
  Signature := TIndexProjectFiles.Signature(Project, ASettings.DelphiVersion);
  if Signature = FSignature then
    Exit;
  FSignature := Signature;
  FIndexService.Stop;
  if Installation <> nil then
    LibraryPaths := Installation.LibraryPaths(Project.Platform) + Installation.BrowsingPaths(Project.Platform)
  else
    LibraryPaths := nil;
  Resolver := TUnitResolver.Create(Project, LibraryPaths, FileExistsFunc);
  FUnitResolver.Free;
  FUnitResolver := Resolver;
  Request.Files := TIndexProjectFiles.Files(Project);
  Request.Defines := TIndexProjectFiles.Defines(Project, ASettings.DelphiVersion);
  Request.ResolveUnit :=
    function(const AUnitName: string): string
    begin
      Result := Resolver.Resolve(AUnitName);
    end;
  CacheFile := TPath.Combine(TPath.Combine(TPath.GetCachePath, 'BetterDelphiLSP'),
    Format('index-%.8x.json', [Cardinal(Signature.GetHashCode)]));
  Request.CacheFile := CacheFile;
  TMonitor.Enter(FLock);
  try
    // Dieselben Symbole bestimmen, welche {$IFDEF}-Zweige der Editor abblendet.
    FDefines := Request.Defines;
    FHasDefines := True;
    FNamespaces := Project.Namespaces;
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
