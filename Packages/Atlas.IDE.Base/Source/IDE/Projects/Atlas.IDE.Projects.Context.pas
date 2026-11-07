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
// Projektdatei .atlas (#486, nur wenn sie eingeschaltet und gültig ist),
// ebenso die eigenen Formatroutinen unter "formatFunctions" (#451).

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
    /// <summary>Build-Konfiguration AName ('' = aktive) ohne Plattform, etwa zum Setzen einer Option (#840); nil
    /// ohne.</summary>
    class function BuildConfiguration(const AProject: IOTAProject; const AName: string): IOTABuildConfiguration;
      static;
    /// <summary>Version von AProject in AConfiguration und APlatform aus seinen Versionsinformationen (#533, #1455);
    /// '' ohne.</summary>
    class function Version(const AProject: IOTAProject; const AConfiguration, APlatform: string): string; static;
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
  Atlas.Core.Versions.Project,
  Atlas.IDE.Foundation.TeamFile;

/// <summary>Konfiguration AConfiguration ('' = aktive), für APlatform deren Plattformkonfiguration; nil ohne.
/// </summary>
function NamedConfiguration(const AProject: IOTAProject; const AConfiguration,
  APlatform: string): IOTABuildConfiguration;
var
  mConfigurations: IOTAProjectOptionsConfigurations;
  mPlatformed: IOTABuildConfiguration;
  mIndex: Integer;
begin
  Result := nil;
  if not Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, mConfigurations) then
  begin
    Exit;
  end;
  if AConfiguration = '' then
  begin
    Result := mConfigurations.ActiveConfiguration;
  end
  else
  begin
    for mIndex := 0 to mConfigurations.ConfigurationCount - 1 do
    begin
      if SameText(mConfigurations.Configurations[mIndex].Name, AConfiguration) then
      begin
        Result := mConfigurations.Configurations[mIndex];
        Break;
      end;
    end;
  end;
  if (Result = nil) or (APlatform = '') then
  begin
    Exit;
  end;
  // Plattformabhängige Werte (z. B. Suchpfade nur für Win64) stehen in der Plattformkonfiguration.
  mPlatformed := Result.PlatformConfiguration[APlatform];
  if mPlatformed <> nil then
  begin
    Result := mPlatformed;
  end;
end;

function BuildConfiguration(const AProject: IOTAProject; const APlatform: string): IOTABuildConfiguration;
begin
  Result := NamedConfiguration(AProject, '', APlatform);
end;

/// <summary>Wert mit geerbten Werten; AResolved wird True, wenn das Plugin $(AName) selbst einsetzen musste.</summary>
function ConfigValue(const ABuild: IOTABuildConfiguration; const AName: string; ADepth: Integer;
  var AResolved: Boolean): string;
var
  mParent: IOTABuildConfiguration;
begin
  Result := ABuild.GetValue(AName, True);
  if not TAtlasProjectContext.RefersToItself(Result, AName) then
  begin
    Exit;
  end;
  mParent := ABuild.Parent;
  if (mParent = nil) or (ADepth > 8) then
  begin
    Result := TAtlasProjectContext.Inherit(Result, AName, '');
  end
  else
  begin
    Result := TAtlasProjectContext.Inherit(Result, AName, ConfigValue(mParent, AName, ADepth + 1, AResolved));
  end;
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
  mBuild: IOTABuildConfiguration;
  mResolved: Boolean;
begin
  mResolved := False;
  try
    mBuild := BuildConfiguration(AProject, AContext.Platform);
    if mBuild <> nil then
    begin
      AContext.Defines := TAtlasProjectContext.List(ConfigValue(mBuild, 'DCC_Define', 0, mResolved));
      AContext.SearchPaths := TAtlasProjectContext.List(ConfigValue(mBuild, 'DCC_UnitSearchPath', 0, mResolved));
      AContext.Namespaces := TAtlasProjectContext.List(ConfigValue(mBuild, 'DCC_Namespace', 0, mResolved));
      AContext.Source := TAtlasProjectContext.cSourceConfiguration;
      if mResolved then
      begin
        AContext.Source := TAtlasProjectContext.cSourceResolved;
      end;
      Exit;
    end;
  except
    on Exception do
      ; // Ersatzweg unten.
  end;
  if AProject.ProjectOptions = nil then
  begin
    Exit;
  end;
  AContext.Defines := TAtlasProjectContext.List(OptionValue(AProject, 'DCC_Define'));
  AContext.SearchPaths := TAtlasProjectContext.List(OptionValue(AProject, 'DCC_UnitSearchPath'));
  AContext.Namespaces := TAtlasProjectContext.List(OptionValue(AProject, 'DCC_Namespace'));
  AContext.Source := TAtlasProjectContext.cSourceOptions;
end;

function LibraryPaths(const ABaseKey, APlatform: string): TArray<string>;
var
  mRegistry: TRegistry;
begin
  Result := nil;
  if (ABaseKey = '') or (APlatform = '') then
  begin
    Exit;
  end;
  mRegistry := TRegistry.Create(KEY_READ);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if mRegistry.OpenKeyReadOnly(ABaseKey + '\Library\' + APlatform) and mRegistry.ValueExists('Search Path') then
    begin
      Result := TAtlasProjectContext.List(mRegistry.ReadString('Search Path'));
    end;
  finally
    mRegistry.Free;
  end;
end;

function BaseRegistryKey: string;
var
  mServices: IOTAServices;
begin
  Result := '';
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Result := mServices.GetBaseRegistryKey;
  end;
end;

/// <summary>Umgebungsvariablen der IDE-Optionen unter ABaseKey in AMacros; nichts ohne Schlüssel.</summary>
procedure AddIdeEnvironment(var AMacros: TAtlasPathMacros; const ABaseKey: string);
var
  mRegistry: TRegistry;
  mNames: TStringList;
  mName: string;
begin
  if ABaseKey = '' then
  begin
    Exit;
  end;
  mRegistry := TRegistry.Create(KEY_READ);
  mNames := TStringList.Create;
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if mRegistry.OpenKeyReadOnly(ABaseKey + '\Environment Variables') then
    begin
      mRegistry.GetValueNames(mNames);
      for mName in mNames do
      begin
        try
          AMacros.Add(mName, mRegistry.ReadString(mName));
        except
          on Exception do
            ; // Kein Text (etwa REG_DWORD): übergehen.
        end;
      end;
    end;
  finally
    mNames.Free;
    mRegistry.Free;
  end;
end;

procedure ReadNaming(var AContext: TAtlasProjectContext);
var
  mTeam: TAtlasTeamSettings;
  mKind: TAtlasNamingKind;
  mItem: TAtlasFormatFunction;
  mEntry: TAtlasProjectFormatFunction;
begin
  mTeam := TAtlasIdeTeamFile.ForProject(AContext.Project);
  if not mTeam.Valid then
  begin
    Exit;
  end;
  for mKind := Low(TAtlasNamingKind) to High(TAtlasNamingKind) do
  begin
    if mTeam.HasNaming[mKind] then
    begin
      AContext.HasNaming[TAtlasProjectNamingKind(Ord(mKind))] := True;
      AContext.Naming[TAtlasProjectNamingKind(Ord(mKind))] := mTeam.Naming[mKind];
    end;
  end;
  // Eigene Formatroutinen für die Platzhalter im Parameter-Hint (#451).
  for mItem in mTeam.FormatFunctions do
  begin
    mEntry.Name := mItem.Name;
    mEntry.FormatIndex := mItem.FormatIndex;
    AContext.FormatFunctions := AContext.FormatFunctions + [mEntry];
  end;
end;

class function TAtlasIdeProjectContext.Read(const AProject: IOTAProject): TAtlasProjectContext;
var
  mBaseKey: string;
begin
  Result := Default(TAtlasProjectContext);
  if (AProject = nil) or not SameText(ExtractFileExt(AProject.FileName), '.dproj') or
    not FileExists(AProject.FileName) then
  begin
    Exit;
  end;
  Result.Project := AProject.FileName;
  Result.Configuration := AProject.CurrentConfiguration;
  Result.Platform := AProject.CurrentPlatform;
  mBaseKey := BaseRegistryKey;
  Result.BdsVersion := TAtlasProjectContext.VersionOfRegistryKey(mBaseKey);
  ReadOptions(AProject, Result);
  Result.LibraryPaths := LibraryPaths(mBaseKey, Result.Platform);
  ReadNaming(Result);
end;

class function TAtlasIdeProjectContext.Macros(const AContext: TAtlasProjectContext): TAtlasPathMacros;
var
  mStudio: string;
  mServices: IOTAServices;
begin
  Result := TAtlasPathMacros.Create(
    function(const AName: string): string
    begin
      Result := GetEnvironmentVariable(AName);
    end);
  // Umgebungsvariablen aus den IDE-Optionen (Tools › Optionen › Umgebungsvariablen) gehen allem vor.
  AddIdeEnvironment(Result, BaseRegistryKey);
  // Ordner der laufenden IDE.
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Result.AddBds(mServices.GetRootDirectory);
  end;
  // Ordner der Version unter „Öffentliche Dokumente“ und „Dokumente“, wie sie die IDE setzt.
  if AContext.BdsVersion <> '' then
  begin
    mStudio := 'Embarcadero\Studio\' + AContext.BdsVersion;
    try
      Result.AddDefault('BDSCOMMONDIR', IncludeTrailingPathDelimiter(TPath.GetSharedDocumentsPath) + mStudio);
      Result.AddDefault('BDSUSERDIR', IncludeTrailingPathDelimiter(TPath.GetDocumentsPath) + mStudio);
      Result.AddDefault('BDSCatalogRepository', IncludeTrailingPathDelimiter(TPath.GetDocumentsPath) + mStudio +
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
  mBuild: IOTABuildConfiguration;
  mResolved: Boolean;
begin
  Result := '';
  if AProject = nil then
  begin
    Exit;
  end;
  mResolved := False;
  try
    mBuild := NamedConfiguration(AProject, AConfiguration, APlatform);
    if mBuild <> nil then
    begin
      Exit(ConfigValue(mBuild, AName, 0, mResolved));
    end;
  except
    on Exception do
      ; // Ersatzweg unten.
  end;
  if (AProject.ProjectOptions <> nil) and
    ((AConfiguration = '') or SameText(AConfiguration, AProject.CurrentConfiguration)) then
  begin
    Result := OptionValue(AProject, AName);
  end;
end;

class function TAtlasIdeProjectContext.BuildConfiguration(const AProject: IOTAProject;
  const AName: string): IOTABuildConfiguration;
begin
  Result := nil;
  if AProject <> nil then
  begin
    Result := NamedConfiguration(AProject, AName, '');
  end;
end;

class function TAtlasIdeProjectContext.Configurations(const AProject: IOTAProject): TArray<string>;
var
  mItems: IOTAProjectOptionsConfigurations;
  mIndex: Integer;
begin
  Result := nil;
  try
    if (AProject <> nil) and Supports(AProject.ProjectOptions, IOTAProjectOptionsConfigurations, mItems) then
    begin
      for mIndex := 0 to mItems.ConfigurationCount - 1 do
      begin
        Result := Result + [mItems.Configurations[mIndex].Name];
      end;
    end;
  except
    on Exception do
      Result := nil;
  end;
end;

class function TAtlasIdeProjectContext.HasConfiguration(const AProject: IOTAProject; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in Configurations(AProject) do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasIdeProjectContext.Group: TArray<TAtlasProjectContext>;
var
  mModules: IOTAModuleServices;
  mProjects: IOTAProjectGroup;
  mIndex: Integer;
  mContext: TAtlasProjectContext;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mProjects := mModules.MainProjectGroup;
  if mProjects = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mProjects.ProjectCount - 1 do
  begin
    mContext := Read(mProjects.Projects[mIndex]);
    // Aktives Projekt für Dateien, die zu mehreren Projekten gehören (#46).
    mContext.Active := mProjects.Projects[mIndex] = mProjects.ActiveProject;
    if mContext.Project <> '' then
    begin
      Result := Result + [mContext];
    end;
  end;
end;

class function TAtlasIdeProjectContext.Version(const AProject: IOTAProject; const AConfiguration,
  APlatform: string): string;

  function Value(const AName: string): string;
  begin
    Result := Trim(ConfigurationValue(AProject, AConfiguration, APlatform, AName));
  end;

begin
  Result := '';
  if (AProject = nil) or (AProject.ProjectOptions = nil) then
  begin
    Exit;
  end;
  Result := TAtlasProjectVersion.FromOptions(Value('VerInfo_IncludeVerInfo'), Value('VerInfo_Keys'), Value('VerInfo_MajorVer'),
    Value('VerInfo_MinorVer'), Value('VerInfo_Release'), Value('VerInfo_Build'));
end;

end.
