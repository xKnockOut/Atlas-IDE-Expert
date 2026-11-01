unit Shell.Workspace.Loader;

// Internals-Rolle Shell: Projekt eines Arbeitsbereichs laden. Projektdatei finden (#648), Delphi-Version und
// Installation wählen (#47, #1321), die .dproj mit Konfiguration und Plattform lesen (#46) und den
// Projektkontext der IDE anwenden (#396, #615).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.IdeProject,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Projects.DprojReader,
  Shell.Workspace.Setup,
  Shell.Workspace.Build,
  Shell.Workspace.State;

type
  /// <summary>Geladenes Projekt mit Installation und Projektkontext der IDE.</summary>
  TShellLoadedProject = record
    ProjectFile: string;
    /// <summary>ProjectVersion der .dproj; '' ohne.</summary>
    ProjectVersion: string;
    /// <summary>Gewählte Delphi-Version; ohne Installation die erwartete, sie liefert nur die Symbole (#1321).</summary>
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
    function Install: TShellInstallInfo;
    /// <summary>Projekt-, Hauptdatei- und Unit-Namen, die das Server-Log verbirgt (#647).</summary>
    function Names: TArray<string>;
  end;

  TShellProjectLoader = class
  private
    FName: string;
    FRoot: string;
    FLogger: ILogger;
    FSetup: TShellWorkspaceSetup;
    FBuild: TShellBuildChoice;
    function ConfiguredProjectFile(const ASettings: TServerSettings): string;
    function SingleProjectFile: string;
    function ChosenVersion(const ASettings: TServerSettings; const ALoaded: TShellLoadedProject;
      const AInstalled: TArray<string>): string;
    procedure ChooseInstallation(const ASettings: TServerSettings; var ALoaded: TShellLoadedProject);
    /// <summary>Konfiguration und Plattform: Einstellung, dann mit AWithChoice die gewählte (#46), dann die der
    /// IDE (#396).</summary>
    procedure SetTarget(const ASettings: TServerSettings; AWithChoice: Boolean; var ALoaded: TShellLoadedProject);
    function ReadProject(const ASettings: TServerSettings; var ALoaded: TShellLoadedProject): Boolean;
    procedure ApplyContext(var ALoaded: TShellLoadedProject);
  public
    constructor Create(const AName, ARoot: string; const ALogger: ILogger; ASetup: TShellWorkspaceSetup;
      ABuild: TShellBuildChoice);
    /// <summary>Feste Projektdatei (Projektgruppe), sonst "project" aus atlas.json, sonst die einzige .dproj im
    /// Ordner; '' ohne oder bei fehlender Datei.</summary>
    function FindProjectFile(const ASettings: TServerSettings): string;
    /// <summary>Lädt AProjectFile; False, wenn die .dproj nicht lesbar ist.</summary>
    function Load(const AProjectFile: string; const ASettings: TServerSettings;
      out ALoaded: TShellLoadedProject): Boolean;
  end;

implementation

uses
  System.IOUtils,
  System.StrUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Compiler.CommandLine,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Projects.DelphiVersions,
  Shell.Platform,
  Shell.Workspace.Listings;

{ TShellLoadedProject }

function TShellLoadedProject.Variables: TArray<TPair<string, string>>;
begin
  Result := nil;
  if Installation <> nil then
  begin
    Result := Installation.Variables;
  end;
end;

function TShellLoadedProject.LibraryPaths: TArray<string>;
begin
  Result := nil;
  if Installation <> nil then
  begin
    Result := CompilerLibraryPaths + Installation.BrowsingPaths(Project.Platform);
  end;
end;

function TShellLoadedProject.Install: TShellInstallInfo;
begin
  Result := Default(TShellInstallInfo);
  if Installation <> nil then
  begin
    Result.DelphiVersion := Version;
    Result.BdsRoot := TCompilerCommandLine.BdsRoot(Installation.Variables);
    Result.LibraryPaths := CompilerLibraryPaths;
  end;
end;

function TShellLoadedProject.Names: TArray<string>;
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
    on Exception do
      Result := '';
  end;
end;

{ TShellProjectLoader }

constructor TShellProjectLoader.Create(const AName, ARoot: string; const ALogger: ILogger;
  ASetup: TShellWorkspaceSetup; ABuild: TShellBuildChoice);
begin
  inherited Create;
  FName := AName;
  FRoot := ARoot;
  FLogger := ALogger;
  FSetup := ASetup;
  FBuild := ABuild;
end;

function TShellProjectLoader.ConfiguredProjectFile(const ASettings: TServerSettings): string;
begin
  Result := '';
  if TProjectPaths.IsAbsolute(ASettings.Project) then
  begin
    Result := ASettings.Project;
  end
  else if FRoot <> '' then
  begin
    Result := TProjectPaths.Combine(FRoot, ASettings.Project);
  end;
  if not FileExists(Result) then
  begin
    FLogger.Warning('Projektdatei nicht gefunden: ' + Result);
    Result := '';
  end;
end;

function TShellProjectLoader.SingleProjectFile: string;
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
      [Length(mCandidates), FRoot, ConfigurationFileName]));
  end;
end;

function TShellProjectLoader.FindProjectFile(const ASettings: TServerSettings): string;
begin
  // Aus der Projektgruppe (#648): Die Datei ist vorgegeben, auch wenn mehrere im Ordner liegen.
  if FSetup.ProjectFile <> '' then
  begin
    Result := FSetup.ProjectFile;
    if not FileExists(Result) then
    begin
      FLogger.Warning('Projektdatei nicht gefunden: ' + Result);
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

function TShellProjectLoader.ChosenVersion(const ASettings: TServerSettings; const ALoaded: TShellLoadedProject;
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
      [FName, ASettings.DelphiVersion, Result]));
  end;
end;

procedure TShellProjectLoader.ChooseInstallation(const ASettings: TServerSettings; var ALoaded: TShellLoadedProject);
var
  mInstalled: TArray<string>;
begin
  ALoaded.ProjectVersion := ProjectVersionOfFile(ALoaded.ProjectFile);
  ALoaded.Installation := nil;
  mInstalled := TDelphiInstallation.Versions;
  try
    ALoaded.Version := ChosenVersion(ASettings, ALoaded, mInstalled);
    if not TDelphiVersions.IsInstalled(ALoaded.Version, mInstalled) then
    begin
      FLogger.Info(Format('%s: kein Delphi installiert; Symbole wie %s (BDS %s, ProjectVersion %s), ' +
        'ohne Bibliothekspfade', [FName, TDelphiVersions.ProductName(ALoaded.Version), ALoaded.Version,
        ALoaded.ProjectVersion]));
      Exit;
    end;
    ALoaded.Installation := TDelphiInstallation.Create(ALoaded.Version);
    FLogger.Info(Format('%s: %s (BDS %s, ProjectVersion %s)',
      [FName, TDelphiVersions.ProductName(ALoaded.Version), ALoaded.Version, ALoaded.ProjectVersion]));
  except
    // Version bleibt: CompilerVersion und VERxxx hängen nicht an den Pfaden der Installation (#1321).
    on E: EProjectError do
    begin
      FLogger.Warning('Delphi-Installation nicht gefunden: ' + E.Message);
      ALoaded.Installation := nil;
    end;
  end;
end;

procedure TShellProjectLoader.SetTarget(const ASettings: TServerSettings; AWithChoice: Boolean;
  var ALoaded: TShellLoadedProject);
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

function TShellProjectLoader.ReadProject(const ASettings: TServerSettings; var ALoaded: TShellLoadedProject): Boolean;
begin
  ALoaded.Options := Default(TDprojOptions);
  SetTarget(ASettings, True, ALoaded);
  ALoaded.Options.FileExists := TShellFileAccess.ExistsFunc();
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
      FLogger.Error(Format('Projekt %s nicht lesbar: %s', [ALoaded.ProjectFile, E.Message]));
      Result := False;
    end;
  end;
end;

procedure TShellProjectLoader.ApplyContext(var ALoaded: TShellLoadedProject);
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
      [FName, ALoaded.Project.Config, ALoaded.Project.Platform, Length(ALoaded.Project.Defines),
       Length(ALoaded.Project.SearchPaths)]));
  end;
  // Symbole aus den Projektoptionen der IDE gelten vor denen der Datei (#615).
  FBuild.ApplyDefines(ALoaded.Project);
end;

function TShellProjectLoader.Load(const AProjectFile: string; const ASettings: TServerSettings;
  out ALoaded: TShellLoadedProject): Boolean;
begin
  ALoaded := Default(TShellLoadedProject);
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
