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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Variants,
  System.Win.Registry,
  Winapi.Windows;

function BuildConfiguration(const AProject: IOTAProject; const APlatform: string): IOTABuildConfiguration;
var
  Configurations: IOTAProjectOptionsConfigurations;
  Platformed: IOTABuildConfiguration;
begin
  Result := nil;
  if not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, Configurations) then
    Exit;
  Result := Configurations.ActiveConfiguration;
  if (Result = nil) or (APlatform = '') then
    Exit;
  // Plattformabhängige Werte (z. B. Suchpfade nur für Win64) stehen in der Plattformkonfiguration.
  Platformed := Result.PlatformConfiguration[APlatform];
  if Platformed <> nil then
    Result := Platformed;
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
