unit Core.Workspace.Loader;

// Host-Rolle Core: Projekt eines Arbeitsbereichs laden. Projektdatei finden (#648), Delphi-Version und
// Installation wählen (#47, #1321), die .dproj mit Konfiguration und Plattform lesen (#46) und den
// Projektkontext der IDE anwenden (#396, #615).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.IdeProject,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.DprojReader,
  Core.Workspace.Setup,
  Core.Workspace.Build,
  Core.Workspace.State;

type
  /// <summary>Geladenes Projekt mit Installation und Projektkontext der IDE.</summary>
  TCoreLoadedProject = record
    ProjectFile: string;
    /// <summary>ProjectVersion der .dproj; '' ohne.</summary>
    ProjectVersion: string;
    /// <summary>Gewählte Delphi-Version; ohne Installation die erwartete, sie liefert nur die Symbole
    /// (#1321).</summary>
    Version: string;
    /// <summary>nil ohne Installation.</summary>
    Installation: ILibraryPathProvider;
    Context: TIdeProjectContext;
    HasContext: Boolean;
    Options: TDprojOptions;
    Project: TProjectInfo;
    /// <summary>Bibliothekspfade für den Compiler; aus der IDE, wenn sie welche meldet.</summary>
    CompilerLibraryPaths: TArray<string>;
    /// <summary>Variablen der Installation ($(BDS) …); nil ohne Installation.</summary>
    function Variables: TArray<TPair<string, string>>;
    /// <summary>Bibliotheks- und Browsing-Pfade der Installation; nil ohne Installation.</summary>
    function LibraryPaths: TArray<string>;
    /// <summary>Für den Compileraufruf; leer ohne Installation.</summary>
    function Install: TCoreInstallInfo;
    /// <summary>Projekt-, Hauptdatei- und Unit-Namen, die das Server-Log verbirgt (#647).</summary>
    function Names: TArray<string>;
  end;

  TCoreProjectLoader = class
  private
    FName: string;
    FRoot: string;
    FConfigRoot: string;
    FLogger: ILogger;
    FSetup: TCoreWorkspaceSetup;
    FBuild: TCoreBuildChoice;
    function ConfiguredProjectFile(const ASettings: TServerSettings): string;
    function SingleProjectFile: string;
    function ChosenVersion(const ASettings: TServerSettings; const ALoaded: TCoreLoadedProject;
      const AInstalled: TArray<string>): string;
    procedure ChooseInstallation(const ASettings: TServerSettings; var ALoaded: TCoreLoadedProject);
    /// <summary>Konfiguration und Plattform: Einstellung, dann mit AWithChoice die gewählte (#46), dann die der
    /// IDE (#396).</summary>
    procedure SetTarget(const ASettings: TServerSettings; AWithChoice: Boolean; var ALoaded: TCoreLoadedProject);
    function ReadProject(const ASettings: TServerSettings; var ALoaded: TCoreLoadedProject): Boolean;
    procedure ApplyContext(var ALoaded: TCoreLoadedProject);
  public
    /// <summary>AConfigRoot ist der Ordner der geltenden atlas.json (kann über ARoot liegen); '' gilt als ARoot.
    /// </summary>
    constructor Create(const AName, ARoot, AConfigRoot: string; const ALogger: ILogger; ASetup: TCoreWorkspaceSetup;
      ABuild: TCoreBuildChoice);
    /// <summary>Feste Projektdatei (Projektgruppe), sonst "project" aus atlas.json (relativ zum Ordner der
    /// atlas.json), sonst die einzige .dproj im Ordner; '' ohne oder bei fehlender Datei.</summary>
    function FindProjectFile(const ASettings: TServerSettings): string;
    /// <summary>Lädt AProjectFile; False, wenn die .dproj nicht lesbar ist.</summary>
    function Load(const AProjectFile: string; const ASettings: TServerSettings;
      out ALoaded: TCoreLoadedProject): Boolean;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Compiler.CommandLine,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Projects.DelphiVersions,
  Core.Workspace.Listings,
  Atlas.Text.LogMarks,
  Atlas.Text.Files;

{ TCoreLoadedProject }

function TCoreLoadedProject.Variables: TArray<TPair<string, string>>;
begin
  Result := nil;
  if Installation <> nil then
  begin
    Result := Installation.Variables;
  end;
end;

function TCoreLoadedProject.LibraryPaths: TArray<string>;
begin
  Result := nil;
  if Installation <> nil then
  begin
    Result := CompilerLibraryPaths + Installation.BrowsingPaths(Project.Platform);
  end;
end;

function TCoreLoadedProject.Install: TCoreInstallInfo;
begin
  Result := Default(TCoreInstallInfo);
  if Installation <> nil then
  begin
    Result.DelphiVersion := Version;
    Result.BdsRoot := TCompilerCommandLine.BdsRoot(Installation.Variables);
    Result.LibraryPaths := CompilerLibraryPaths;
  end;
end;

function TCoreLoadedProject.Names: TArray<string>;
var
  mUnit: TProjectUnit;
begin
  Result := TArray<string>.Create(ChangeFileExt(ExtractFileName(Project.FileName), ''),
    ChangeFileExt(ExtractFileName(Project.MainSource), ''));
  for mUnit in Project.Units do
  begin
    Result := Result + [mUnit.Name];
  end;
end;

/// <summary>ProjectVersion der .dproj; '' wenn nicht lesbar.</summary>
function ProjectVersionOfFile(const AProjectFile: string): string;
begin
  try
    Result := TDelphiVersions.ProjectVersionOf(TFileEncoding.LoadText(AProjectFile));
  except
    on E: Exception do
    begin
      if not (TTextFiles.IsFileError(E) or (E is EFileEncodingError)) then
      begin
        raise;
      end;
      Result := '';
    end;
  end;
end;

{ TCoreProjectLoader }

constructor TCoreProjectLoader.Create(const AName, ARoot, AConfigRoot: string; const ALogger: ILogger;
  ASetup: TCoreWorkspaceSetup; ABuild: TCoreBuildChoice);
begin
  inherited Create;
  FName := AName;
  FRoot := ARoot;
  FConfigRoot := AConfigRoot;
  if FConfigRoot = '' then
  begin
    FConfigRoot := ARoot;
  end;
  FLogger := ALogger;
  FSetup := ASetup;
  FBuild := ABuild;
end;

function TCoreProjectLoader.ConfiguredProjectFile(const ASettings: TServerSettings): string;
begin
  Result := '';
  if TProjectPaths.IsAbsolute(ASettings.Project) then
  begin
    Result := ASettings.Project;
  end
  else if FConfigRoot <> '' then
  begin
    // Wie alle Pfade in atlas.json relativ zu deren Ordner, auch wenn sie über der Wurzel liegt (Packages\X als
    // Wurzel, atlas.json im Stamm).
    Result := TProjectPaths.Combine(FConfigRoot, ASettings.Project);
  end;
  if not FileExists(Result) then
  begin
    FLogger.Warning('Projektdatei nicht gefunden: ' + TLogMarks.Path(Result));
    Result := '';
  end;
end;

function TCoreProjectLoader.SingleProjectFile: string;
var
  mCandidates: TArray<string>;
begin
  Result := '';
  if (FRoot = '') or not TDirectory.Exists(FRoot) then
  begin
    Exit;
  end;
  mCandidates := TDirectory.GetFiles(FRoot, '*.dproj');
  if Length(mCandidates) = 1 then
  begin
    Result := mCandidates[0];
  end
  else if Length(mCandidates) > 1 then
  begin
    FLogger.Info(Format('%d Projektdateien in %s; "project" in %s wählt eine aus',
      [Length(mCandidates), TLogMarks.Path(FRoot), cConfigurationFileName]));
  end;
end;

function TCoreProjectLoader.ChosenVersion(const ASettings: TServerSettings; const ALoaded: TCoreLoadedProject;
  const AInstalled: TArray<string>): string;
var
  mConfiguredMissing: Boolean;
begin
  // In der IDE bestimmt die IDE die Delphi-Version (#396).
  if ALoaded.HasContext and (ALoaded.Context.BdsVersion <> '') and
    (IndexText(ALoaded.Context.BdsVersion, AInstalled) >= 0) then
  begin
    Exit(ALoaded.Context.BdsVersion);
  end;
  // Konfiguration vor ProjectVersion der .dproj vor neuester Installation (#47); ohne Installation die
  // erwartete Version: Sie liefert nur die Symbole (#1321).
  Result := TDelphiVersions.Choose(ASettings.DelphiVersion, ALoaded.ProjectVersion, AInstalled, mConfiguredMissing);
  // Die Warnung steht auch an "delphiVersion" in atlas.json (#47).
  if mConfiguredMissing then
  begin
    FLogger.Warning(Format('%s: delphiVersion %s ist nicht installiert; automatisch gewählt: %s',
      [TLogMarks.Name(FName), ASettings.DelphiVersion, Result]));
  end;
end;

procedure TCoreProjectLoader.ChooseInstallation(const ASettings: TServerSettings; var ALoaded: TCoreLoadedProject);
var
  mInstalled: TArray<string>;
begin
  ALoaded.ProjectVersion := ProjectVersionOfFile(ALoaded.ProjectFile);
  ALoaded.Installation := nil;
  mInstalled := FSetup.Factories.Versions;
  try
    ALoaded.Version := ChosenVersion(ASettings, ALoaded, mInstalled);
    if not TDelphiVersions.IsInstalled(ALoaded.Version, mInstalled) then
    begin
      FLogger.Info(Format('%s: kein Delphi installiert; Symbole wie %s (BDS %s, ProjectVersion %s), ' +
        'ohne Bibliothekspfade', [TLogMarks.Name(FName), TDelphiVersions.ProductName(ALoaded.Version), ALoaded.Version,
        ALoaded.ProjectVersion]));
      Exit;
    end;
    ALoaded.Installation := FSetup.Factories.InstallationOf(ALoaded.Version);
    FLogger.Info(Format('%s: %s (BDS %s, ProjectVersion %s)',
      [TLogMarks.Name(FName), TDelphiVersions.ProductName(ALoaded.Version), ALoaded.Version,
        ALoaded.ProjectVersion]));
  except
    // Version bleibt: CompilerVersion und VERxxx hängen nicht an den Pfaden der Installation (#1321).
    on E: EProjectError do
    begin
      FLogger.Warning('Delphi-Installation nicht gefunden: ' + TLogMarks.Text(E.Message));
      ALoaded.Installation := nil;
    end;
  end;
end;

procedure TCoreProjectLoader.SetTarget(const ASettings: TServerSettings; AWithChoice: Boolean;
  var ALoaded: TCoreLoadedProject);
begin
  ALoaded.Options.Config := ASettings.Config;
  ALoaded.Options.Platform := ASettings.Platform;
  if AWithChoice then
  begin
    FBuild.ApplyTo(ALoaded.Options);
  end;
  if ALoaded.HasContext and (ALoaded.Context.Configuration <> '') then
  begin
    ALoaded.Options.Config := ALoaded.Context.Configuration;
  end;
  if ALoaded.HasContext and (ALoaded.Context.Platform <> '') then
  begin
    ALoaded.Options.Platform := ALoaded.Context.Platform;
  end;
end;

function TCoreProjectLoader.ReadProject(const ASettings: TServerSettings; var ALoaded: TCoreLoadedProject): Boolean;
begin
  ALoaded.Options := Default(TDprojOptions);
  SetTarget(ASettings, True, ALoaded);
  ALoaded.Options.FileExists := TCoreFileAccess.ExistsFunc();
  ALoaded.Options.Variables := ALoaded.Variables;
  try
    ALoaded.Project := TDprojReader.Load(ALoaded.ProjectFile, ALoaded.Options);
    // Gemerkte Wahl (#46), die es im Projekt nicht mehr gibt: mit den Vorgaben weiter.
    if FBuild.DropUnknown(ALoaded.Project) then
    begin
      SetTarget(ASettings, False, ALoaded);
      ALoaded.Project := TDprojReader.Load(ALoaded.ProjectFile, ALoaded.Options);
    end;
    Result := True;
  except
    on E: EProjectError do
    begin
      FLogger.Error(Format('Projekt %s nicht lesbar: %s', [TLogMarks.Path(ALoaded.ProjectFile),
        TLogMarks.Text(E.Message)]));
      Result := False;
    end;
  end;
end;

procedure TCoreProjectLoader.ApplyContext(var ALoaded: TCoreLoadedProject);
begin
  ALoaded.CompilerLibraryPaths := nil;
  if ALoaded.Installation <> nil then
  begin
    ALoaded.CompilerLibraryPaths := ALoaded.Installation.LibraryPaths(ALoaded.Project.Platform);
  end;
  if ALoaded.HasContext then
  begin
    ALoaded.Context.ApplyTo(ALoaded.Project, ALoaded.Variables);
    if Length(ALoaded.Context.LibraryPaths) > 0 then
    begin
      ALoaded.CompilerLibraryPaths := ALoaded.Context.ExpandedLibraryPaths(ALoaded.Project, ALoaded.Variables);
    end;
    FLogger.Info(Format('%s: Projektkontext aus der IDE (%s, %s, %d Symbole, %d Suchpfade)',
      [TLogMarks.Name(FName), TLogMarks.Name(ALoaded.Project.Config),
      TLogMarks.Name(ALoaded.Project.Platform), Length(ALoaded.Project.Defines),
       Length(ALoaded.Project.SearchPaths)]));
  end;
  // Symbole aus den Projektoptionen der IDE gelten vor denen der Datei (#615).
  FBuild.ApplyDefines(ALoaded.Project);
end;

function TCoreProjectLoader.FindProjectFile(const ASettings: TServerSettings): string;
begin
  // Aus der Projektgruppe (#648): Die Datei ist vorgegeben, auch wenn mehrere im Ordner liegen.
  if FSetup.ProjectFile <> '' then
  begin
    Result := FSetup.ProjectFile;
    if not FileExists(Result) then
    begin
      FLogger.Warning('Projektdatei nicht gefunden: ' + TLogMarks.Path(Result));
      Result := '';
    end;
  end
  else if ASettings.Project <> '' then
  begin
    Result := ConfiguredProjectFile(ASettings);
  end
  else
  begin
    // Ohne Angabe: die einzige .dproj im Ordner.
    Result := SingleProjectFile;
  end;
end;

function TCoreProjectLoader.Load(const AProjectFile: string; const ASettings: TServerSettings;
  out ALoaded: TCoreLoadedProject): Boolean;
begin
  ALoaded := Default(TCoreLoadedProject);
  ALoaded.ProjectFile := AProjectFile;
  // In der IDE bestimmt die IDE Konfiguration, Plattform, Optionen und Delphi-Version (#396).
  ALoaded.HasContext := FSetup.IdeContext(AProjectFile, ALoaded.Context);
  ChooseInstallation(ASettings, ALoaded);
  FBuild.Restore(AProjectFile);
  Result := ReadProject(ASettings, ALoaded);
  if Result then
  begin
    ApplyContext(ALoaded);
  end;
end;

end.
