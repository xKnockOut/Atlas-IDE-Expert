unit Atlas.IDE.Projects.Context;

// Projektkontext aus der laufenden IDE (#396): Konfiguration und Plattform
// des Projekts, bedingte Symbole, Suchpfade und Unit-Namespaces aus den
// Optionen der aktiven Konfiguration für die aktive Plattform (mit geerbten
// Werten, auch ungespeicherte Änderungen), Bibliothekspfade aus den
// Bibliotheksoptionen der laufenden IDE (auch mit eigenem Profil -r) und ihre
// Version. Nur im Hauptthread aufrufen.
//
// Ob GetValue(…, True) die geerbten Werte wirklich einsetzt, ist nur in der
// IDE prüfbar. Deshalb: Steht danach noch $(DCC_Define) im Wert, setzt das
// Plugin die Elternkonfigurationen selbst ein; fehlt die
// Konfigurationsschnittstelle oder wirft sie, gelten die Projektoptionen
// (IOTAProjectOptions.Values). Welcher Weg galt, steht in Source und mit
// Diagnose=1 im Protokoll.
//
// Macros (#759): Werte für $(…) in Such- und Bibliothekspfaden wie die IDE
// sie kennt: Umgebungsvariablen aus den IDE-Optionen (Registry "Environment
// Variables" des laufenden Profils), BDS-Ordner der laufenden IDE (BDS,
// BDSLIB, BDSBIN, BDSINCLUDE), BDSCOMMONDIR, BDSUSERDIR und
// BDSCatalogRepository der Version, Projekt, Plattform und Konfiguration;
// zuletzt die Umgebung des Prozesses.
//
// Präfixe (#452): Read übernimmt die Vorgaben unter "naming" aus der
// Projektdatei .atlas (#486, nur wenn sie eingeschaltet und gültig ist).

interface

uses
  ToolsAPI,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Projects.PathCheck;

type
  TAtlasIdeProjectContext = class
  public
    /// <summary>Kontext eines Projekts; Project = '' für Projekte, die keine gespeicherte .dproj sind.</summary>
    class function Read(const AProject: IOTAProject): TAtlasProjectContext; static;
    /// <summary>Kontexte aller Projekte der geöffneten Gruppe, die eine gespeicherte .dproj haben.</summary>
    class function Group: TArray<TAtlasProjectContext>; static;
    /// <summary>Werte für $(…) in den Pfaden von AContext (siehe Kopf); nur im Hauptthread aufrufen, das Ergebnis
    /// darf in einen Hintergrundthread.</summary>
    class function Macros(const AContext: TAtlasProjectContext): TAtlasPathMacros; static;
    /// <summary>Wert der Option AName in Konfiguration AConfiguration ('' = aktive) für APlatform ('' = ohne
    /// Plattformkonfiguration), mit geerbten Werten wie Read; '' = nicht gesetzt oder nicht lesbar. Ohne
    /// Konfigurationsschnittstelle gelten die Projektoptionen, aber nur für die aktive Konfiguration (#533).
    /// </summary>
    class function ConfigurationValue(const AProject: IOTAProject; const AConfiguration, APlatform,
      AName: string): string; static;
    /// <summary>Namen der Build-Konfigurationen des Projekts (z. B. Base, Debug, Release); leer, wenn nicht lesbar.
    /// </summary>
    class function Configurations(const AProject: IOTAProject): TArray<string>; static;
    /// <summary>Hat das Projekt die Konfiguration AName (Groß-/Kleinschreibung egal)?</summary>
    class function HasConfiguration(const AProject: IOTAProject; const AName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Variants,
  System.Win.Registry,
  Winapi.Windows,
  Atlas.Core.Settings.TeamFile,
  Atlas.IDE.Foundation.TeamFile;

/// <summary>Konfiguration AConfiguration ('' = aktive), für APlatform deren Plattformkonfiguration; nil ohne.
/// </summary>
function NamedConfiguration(const AProject: IOTAProject; const AConfiguration,
  APlatform: string): IOTABuildConfiguration;
var
  Configurations: IOTAProjectOptionsConfigurations;
  Platformed: IOTABuildConfiguration;
  Index: Integer;
begin
  Result := nil;
  if not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, Configurations) then
    Exit;
  if AConfiguration = '' then
    Result := Configurations.ActiveConfiguration
  else
    for Index := 0 to Configurations.ConfigurationCount - 1 do
      if SameText(Configurations.Configurations[Index].Name, AConfiguration) then
      begin
        Result := Configurations.Configurations[Index];
        Break;
      end;
  if (Result = nil) or (APlatform = '') then
    Exit;
  // Plattformabhängige Werte (z. B. Suchpfade nur für Win64) stehen in der Plattformkonfiguration.
  Platformed := Result.PlatformConfiguration[APlatform];
  if Platformed <> nil then
    Result := Platformed;
end;

function BuildConfiguration(const AProject: IOTAProject; const APlatform: string): IOTABuildConfiguration;
begin
  Result := NamedConfiguration(AProject, '', APlatform);
end;

/// <summary>Wert mit geerbten Werten; AResolved wird True, wenn das Plugin $(AName) selbst einsetzen musste.</summary>
function ConfigValue(const ABuild: IOTABuildConfiguration; const AName: string; ADepth: Integer;
  var AResolved: Boolean): string;
var
  Parent: IOTABuildConfiguration;
begin
  Result := ABuild.GetValue(AName, True);
  if not TAtlasProjectContext.RefersToItself(Result, AName) then
    Exit;
  Parent := ABuild.Parent;
  if (Parent = nil) or (ADepth > 8) then
    Result := TAtlasProjectContext.Inherit(Result, AName, '')
  else
    Result := TAtlasProjectContext.Inherit(Result, AName, ConfigValue(Parent, AName, ADepth + 1, AResolved));
  AResolved := True;
end;

function OptionValue(const AProject: IOTAProject; const AName: string): string;
begin
  try
    Result := TAtlasProjectContext.Inherit(VarToStr(AProject.ProjectOptions.Values[AName]), AName, '');
  except
    on Exception do
      Result := '';
  end;
end;

procedure ReadOptions(const AProject: IOTAProject; var AContext: TAtlasProjectContext);
var
  Build: IOTABuildConfiguration;
  Resolved: Boolean;
begin
  Resolved := False;
  try
    Build := BuildConfiguration(AProject, AContext.Platform);
    if Build <> nil then
    begin
      AContext.Defines := TAtlasProjectContext.List(ConfigValue(Build, 'DCC_Define', 0, Resolved));
      AContext.SearchPaths := TAtlasProjectContext.List(ConfigValue(Build, 'DCC_UnitSearchPath', 0, Resolved));
      AContext.Namespaces := TAtlasProjectContext.List(ConfigValue(Build, 'DCC_Namespace', 0, Resolved));
      AContext.Source := TAtlasProjectContext.SourceConfiguration;
      if Resolved then
        AContext.Source := TAtlasProjectContext.SourceResolved;
      Exit;
    end;
  except
    on Exception do
      ; // Ersatzweg unten.
  end;
  if AProject.ProjectOptions = nil then
    Exit;
  AContext.Defines := TAtlasProjectContext.List(OptionValue(AProject, 'DCC_Define'));
  AContext.SearchPaths := TAtlasProjectContext.List(OptionValue(AProject, 'DCC_UnitSearchPath'));
  AContext.Namespaces := TAtlasProjectContext.List(OptionValue(AProject, 'DCC_Namespace'));
  AContext.Source := TAtlasProjectContext.SourceOptions;
end;

function LibraryPaths(const ABaseKey, APlatform: string): TArray<string>;
var
  Registry: TRegistry;
begin
  Result := nil;
  if (ABaseKey = '') or (APlatform = '') then
    Exit;
  Registry := TRegistry.Create(KEY_READ);
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if Registry.OpenKeyReadOnly(ABaseKey + '\Library\' + APlatform) and Registry.ValueExists('Search Path') then
      Result := TAtlasProjectContext.List(Registry.ReadString('Search Path'));
  finally
    Registry.Free;
  end;
end;

function BaseRegistryKey: string;
var
  Services: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, Services) then
    Result := Services.GetBaseRegistryKey;
end;

procedure ReadNaming(var AContext: TAtlasProjectContext);
var
  Team: TAtlasTeamSettings;
  Kind: TAtlasNamingKind;
begin
  Team := TAtlasIdeTeamFile.ForProject(AContext.Project);
  if not Team.Valid then
    Exit;
  for Kind := Low(TAtlasNamingKind) to High(TAtlasNamingKind) do
    if Team.HasNaming[Kind] then
    begin
      AContext.HasNaming[TAtlasProjectNamingKind(Ord(Kind))] := True;
      AContext.Naming[TAtlasProjectNamingKind(Ord(Kind))] := Team.Naming[Kind];
    end;
end;

class function TAtlasIdeProjectContext.Read(const AProject: IOTAProject): TAtlasProjectContext;
var
  BaseKey: string;
begin
  Result := Default(TAtlasProjectContext);
  if (AProject = nil) or not SameText(ExtractFileExt(AProject.FileName), '.dproj') or
    not FileExists(AProject.FileName) then
    Exit;
  Result.Project := AProject.FileName;
  Result.Configuration := AProject.CurrentConfiguration;
  Result.Platform := AProject.CurrentPlatform;
  BaseKey := BaseRegistryKey;
  Result.BdsVersion := TAtlasProjectContext.VersionOfRegistryKey(BaseKey);
  ReadOptions(AProject, Result);
  Result.LibraryPaths := LibraryPaths(BaseKey, Result.Platform);
  ReadNaming(Result);
end;

class function TAtlasIdeProjectContext.Macros(const AContext: TAtlasProjectContext): TAtlasPathMacros;
var
  Registry: TRegistry;
  Names: TStringList;
  Name, BaseKey, Studio: string;
  Services: IOTAServices;
begin
  Result := TAtlasPathMacros.Create(
    function(const AName: string): string
    begin
      Result := GetEnvironmentVariable(AName);
    end);
  BaseKey := BaseRegistryKey;
  // Umgebungsvariablen aus den IDE-Optionen (Tools › Optionen › Umgebungsvariablen) gehen allem vor.
  if BaseKey <> '' then
  begin
    Registry := TRegistry.Create(KEY_READ);
    Names := TStringList.Create;
    try
      Registry.RootKey := HKEY_CURRENT_USER;
      if Registry.OpenKeyReadOnly(BaseKey + '\Environment Variables') then
      begin
        Registry.GetValueNames(Names);
        for Name in Names do
          try
            Result.Add(Name, Registry.ReadString(Name));
          except
            on Exception do
              ; // Kein Text (etwa REG_DWORD): übergehen.
          end;
      end;
    finally
      Names.Free;
      Registry.Free;
    end;
  end;
  // Ordner der laufenden IDE.
  if Supports(BorlandIDEServices, IOTAServices, Services) then
    Result.AddBds(Services.GetRootDirectory);
  // Ordner der Version unter „Öffentliche Dokumente“ und „Dokumente“, wie sie die IDE setzt.
  if AContext.BdsVersion <> '' then
  begin
    Studio := 'Embarcadero\Studio\' + AContext.BdsVersion;
    try
      Result.AddDefault('BDSCOMMONDIR', IncludeTrailingPathDelimiter(TPath.GetSharedDocumentsPath) + Studio);
      Result.AddDefault('BDSUSERDIR', IncludeTrailingPathDelimiter(TPath.GetDocumentsPath) + Studio);
      Result.AddDefault('BDSCatalogRepository', IncludeTrailingPathDelimiter(TPath.GetDocumentsPath) + Studio +
        '\CatalogRepository');
    except
      on Exception do
        ; // Ordner nicht ermittelbar: dann gilt die Umgebung des Prozesses.
    end;
  end;
  Result.AddProject(AContext.Project, AContext.Platform, AContext.Configuration);
end;

class function TAtlasIdeProjectContext.ConfigurationValue(const AProject: IOTAProject; const AConfiguration,
  APlatform, AName: string): string;
var
  Build: IOTABuildConfiguration;
  Resolved: Boolean;
begin
  Result := '';
  if AProject = nil then
    Exit;
  Resolved := False;
  try
    Build := NamedConfiguration(AProject, AConfiguration, APlatform);
    if Build <> nil then
      Exit(ConfigValue(Build, AName, 0, Resolved));
  except
    on Exception do
      ; // Ersatzweg unten.
  end;
  if (AProject.ProjectOptions <> nil) and
    ((AConfiguration = '') or SameText(AConfiguration, AProject.CurrentConfiguration)) then
    Result := OptionValue(AProject, AName);
end;

class function TAtlasIdeProjectContext.Configurations(const AProject: IOTAProject): TArray<string>;
var
  Items: IOTAProjectOptionsConfigurations;
  Index: Integer;
begin
  Result := nil;
  try
    if (AProject <> nil) and Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, Items) then
      for Index := 0 to Items.ConfigurationCount - 1 do
        Result := Result + [Items.Configurations[Index].Name];
  except
    on Exception do
      Result := nil;
  end;
end;

class function TAtlasIdeProjectContext.HasConfiguration(const AProject: IOTAProject; const AName: string): Boolean;
var
  Name: string;
begin
  Result := False;
  for Name in Configurations(AProject) do
    if SameText(Name, AName) then
      Exit(True);
end;

class function TAtlasIdeProjectContext.Group: TArray<TAtlasProjectContext>;
var
  Modules: IOTAModuleServices;
  Projects: IOTAProjectGroup;
  Index: Integer;
  Context: TAtlasProjectContext;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Modules) then
    Exit;
  Projects := Modules.MainProjectGroup;
  if Projects = nil then
    Exit;
  for Index := 0 to Projects.ProjectCount - 1 do
  begin
    Context := Read(Projects.Projects[Index]);
    if Context.Project <> '' then
      Result := Result + [Context];
  end;
end;

end.
