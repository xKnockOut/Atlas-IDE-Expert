unit Atlas.IDE.Projects.Context;

// Projektkontext aus der laufenden IDE (#396): Konfiguration und Plattform
// des Projekts, bedingte Symbole, Suchpfade und Unit-Namespaces aus den
// Optionen der aktiven Konfiguration für die aktive Plattform (mit geerbten
// Werten, auch ungespeicherte Änderungen), Bibliothekspfade aus den
// Bibliotheksoptionen der laufenden IDE (auch mit eigenem Profil -r) und ihre
// Version. Nur im Hauptthread aufrufen.

interface

uses
  ToolsAPI,
  Atlas.Core.Projects.Context;

type
  TAtlasIdeProjectContext = class
  public
    /// <summary>Kontext eines Projekts; Project = '' für Projekte, die keine gespeicherte .dproj sind.</summary>
    class function Read(const AProject: IOTAProject): TAtlasProjectContext; static;
    /// <summary>Kontexte aller Projekte der geöffneten Gruppe, die eine gespeicherte .dproj haben.</summary>
    class function Group: TArray<TAtlasProjectContext>; static;
  end;

implementation

uses
  System.SysUtils,
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
  Build: IOTABuildConfiguration;
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
  Build := BuildConfiguration(AProject, Result.Platform);
  if Build <> nil then
  begin
    Result.Defines := TAtlasProjectContext.List(Build.GetValue('DCC_Define', True));
    Result.SearchPaths := TAtlasProjectContext.List(Build.GetValue('DCC_UnitSearchPath', True));
    Result.Namespaces := TAtlasProjectContext.List(Build.GetValue('DCC_Namespace', True));
  end;
  Result.LibraryPaths := LibraryPaths(BaseKey, Result.Platform);
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
