unit Shell.Workspace.Jobs;

// Internals-Rolle Shell: Aufträge aus dem geladenen Projekt eines Arbeitsbereichs. Compilerlauf (#40, #261), Suche
// nach einer Unit, die der Compiler nicht fand (#550), und die atlas-baseline.json des Ordners (#97).

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.MissingUnit,
  Atlas.Common.Rules.Baseline,
  Shell.Compiler,
  Shell.Workspace.State;

type
  TShellWorkspaceJobs = class
  public
    /// <summary>Compilerlauf für AProject (#40, #261): Aufruf von dcc32/dcc64, Projekt, Plattform, Installation
    /// und ASettings. Ob dcc da und nutzbar ist, prüft der Aufrufer (TShellCompilerEditions). False mit Grund in
    /// AError ohne Installation oder unterstützte Plattform.</summary>
    class function CompileJobOf(const AProject: TProjectInfo; const AInstall: TShellInstallInfo;
      const ASettings: TCompilerSettings; out AJob: TShellCompileJob; out AError: string): Boolean; static;
    /// <summary>Suche nach einer Unit, die der Compiler nicht fand (#550): AProject, alle Konfigurationen und
    /// Plattformen der .dproj, Bibliothekspfade und Ordnerzugriff. Gruppe und Index ergänzt der Aufrufer.</summary>
    class function MissingUnitSetupOf(const AProject: TProjectInfo; const AInstall: TShellInstallInfo):
      TMissingUnitSetup; static;
  end;

  /// <summary>atlas-baseline.json eines Ordners (#97), neu gelesen, sobald sich die Datei ändert. Threadsicher.
  /// </summary>
  TShellBaselineFile = class
  private
    FRoot: string;
    FName: string;
    FLogger: ILogger;
    FLock: TObject;
    FBaseline: IRuleBaseline;
    FTime: TDateTime;
    procedure Read(const AFileName: string);
  public
    constructor Create(const ARoot, AName: string; const ALogger: ILogger);
    destructor Destroy; override;
    /// <summary>nil ohne oder bei ungültiger Datei.</summary>
    function Current: IRuleBaseline;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.CommandLine,
  Atlas.Common.Projects.DprojReader,
  Shell.Platform,
  Shell.Workspace.Listings,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TWorkspaceJobText = (NoDelphi);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TWorkspaceJobText] of TAtlasText = (
    (De: 'Delphi-Installation nicht gefunden'; En: 'Delphi installation not found'));

{ TShellWorkspaceJobs }

class function TShellWorkspaceJobs.CompileJobOf(const AProject: TProjectInfo; const AInstall: TShellInstallInfo;
  const ASettings: TCompilerSettings; out AJob: TShellCompileJob; out AError: string): Boolean;
var
  mOutputDir: string;
begin
  AJob := Default(TShellCompileJob);
  AJob.Settings := ASettings;
  AError := '';
  if AInstall.BdsRoot = '' then
  begin
    AError := cTexts[TWorkspaceJobText.NoDelphi].Text;
    Exit(False);
  end;
  // Eigener Ausgabeordner je Projekt, Plattform und Konfiguration; der Build des Entwicklers bleibt unberührt.
  mOutputDir := TPath.Combine(TPath.GetTempPath, Format('Atlas\dcc-%.8x\%s-%s',
    [Cardinal(LowerCase(AProject.FileName).GetHashCode), AProject.Platform, AProject.Config]));
  try
    AJob.Request := TCompilerCommandLine.Build(AProject, AInstall.LibraryPaths, AInstall.BdsRoot, mOutputDir);
    AJob.Project := AProject.FileName;
    AJob.Platform := AProject.Platform;
    AJob.BdsRoot := AInstall.BdsRoot;
    AJob.Version := AInstall.DelphiVersion;
    // Ob dcc32/dcc64 da ist (Starter Edition, #261), prüft TShellCompilerEditions; der Ausgabeordner
    // entsteht erst, wenn dcc wirklich läuft.
    AJob.OutputDir := mOutputDir;
    Result := True;
  except
    on E: ECompilerError do
    begin
      AError := E.Message;
      Result := False;
    end;
  end;
end;

/// <summary>Installation zu AVersion; nil ohne oder wenn sie nicht lesbar ist (dann ohne Bibliothek und ohne
/// $(BDS) in den Suchpfaden).</summary>
function InstallationOf(const AVersion: string): ILibraryPathProvider;
begin
  Result := nil;
  if AVersion = '' then
  begin
    Exit;
  end;
  try
    Result := TDelphiInstallation.Create(AVersion);
  except
    on EProjectError do
      Result := nil;
  end;
end;

/// <summary>Jede Konfiguration mit jeder Plattform, wie der Compiler sie sähe; nicht lesbare fehlen.</summary>
function TargetsOf(const AProject: TProjectInfo; const AInstallation: ILibraryPathProvider):
  TArray<TMissingUnitTarget>;
var
  mOptions: TDprojOptions;
  mConfig, mPlatform: string;
  mTarget: TMissingUnitTarget;
begin
  Result := nil;
  mOptions := Default(TDprojOptions);
  mOptions.FileExists := TShellFileAccess.ExistsFunc();
  if AInstallation <> nil then
  begin
    mOptions.Variables := AInstallation.Variables;
  end;
  for mConfig in AProject.Configs do
  begin
    for mPlatform in AProject.Platforms do
    begin
      mOptions.Config := mConfig;
      mOptions.Platform := mPlatform;
      mTarget := Default(TMissingUnitTarget);
      try
        mTarget.SearchPaths := TDprojReader.Load(AProject.FileName, mOptions).SearchPaths;
      except
        on EProjectError do
          Continue;
      end;
      mTarget.Config := mConfig;
      mTarget.Platform := mPlatform;
      Result := Result + [mTarget];
    end;
  end;
end;

/// <summary>Bibliothekspfade je Plattform; nicht installierte Plattformen haben keine.</summary>
function LibraryPathsOf(const AInstallation: ILibraryPathProvider): TFunc<string, TArray<string>>;
begin
  Result :=
    function(APlatform: string): TArray<string>
    begin
      try
        Result := AInstallation.LibraryPaths(APlatform);
      except
        on EProjectError do
          Result := nil;
      end;
    end;
end;

class function TShellWorkspaceJobs.MissingUnitSetupOf(const AProject: TProjectInfo;
  const AInstall: TShellInstallInfo): TMissingUnitSetup;
var
  mInstallation: ILibraryPathProvider;
begin
  Result := Default(TMissingUnitSetup);
  Result.ActiveLibraryPaths := AInstall.LibraryPaths;
  Result.Project := AProject;
  Result.Namespaces := AProject.Namespaces;
  mInstallation := InstallationOf(AInstall.DelphiVersion);
  Result.Targets := TargetsOf(AProject, mInstallation);
  if mInstallation <> nil then
  begin
    Result.Platforms := TMissingUnitSearch.KnownPlatforms;
    Result.LibraryPaths := LibraryPathsOf(mInstallation);
  end;
  Result.ListFiles := TSharedUnitListings.ListUnitFilesFunc();
  Result.ListFolders := TShellFileAccess.FoldersFunc();
end;

{ TShellBaselineFile }

constructor TShellBaselineFile.Create(const ARoot, AName: string; const ALogger: ILogger);
begin
  inherited Create;
  FRoot := ARoot;
  FName := AName;
  FLogger := ALogger;
  FLock := TObject.Create;
end;

destructor TShellBaselineFile.Destroy;
begin
  FLock.Free;
  FLogger := nil;
  inherited;
end;

procedure TShellBaselineFile.Read(const AFileName: string);
var
  mFormat: TFileFormat;
begin
  try
    FBaseline := TRuleBaseline.FromJson(TFileEncoding.LoadFromFile(AFileName, mFormat));
    FLogger.Info(Format('Baseline für %s geladen: %d bekannte Treffer', [TLogMarks.Name(FName), FBaseline.Count]));
  except
    on E: Exception do
    begin
      FBaseline := nil;
      FLogger.Error(Format('Baseline %s nicht lesbar: %s', [TLogMarks.Path(AFileName), TLogMarks.Text(E.Message)]));
    end;
  end;
end;

function TShellBaselineFile.Current: IRuleBaseline;
var
  mFileName: string;
  mTime: TDateTime;
begin
  mFileName := ExistingOrLegacyFile(FRoot, cBaselineFileName, cLegacyBaselineFileName);
  TMonitor.Enter(FLock);
  try
    if not TFile.Exists(mFileName) then
    begin
      FBaseline := nil;
      FTime := 0;
      Exit(nil);
    end;
    mTime := TFile.GetLastWriteTime(mFileName);
    if mTime <> FTime then
    begin
      FTime := mTime;
      Read(mFileName);
    end;
    Result := FBaseline;
  finally
    TMonitor.Exit(FLock);
  end;
end;

initialization
  TAtlasTextTables.Add('Shell.Workspace.Jobs', cTexts);

end.
