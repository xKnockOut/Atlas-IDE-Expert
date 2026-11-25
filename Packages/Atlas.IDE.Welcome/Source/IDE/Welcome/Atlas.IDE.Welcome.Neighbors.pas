unit Atlas.IDE.Welcome.Neighbors;

// Andere Module für die Willkommensseite (#1455, Modulregel 6): Builds
// auf Auftrag (Build-Pipeline), Testprojekte (Tests), Startprofile und
// Projektaufgaben (Build-Werkzeuge) und die Baseline (Prüfregeln) erreicht
// die Seite nur über deren Verträge in Base (Atlas.IDE.Base.Foundation.*) und fragt bei
// jedem Aufruf neu (Regel 2): Fehlt ein Modul oder ist es aus, meldet die
// Schnellaktion den Grund, statt etwas zu tun. Vorher klebte die
// Kompositionswurzel diese Verbindungen. Die Einrichtung (#759) bekommt hier
// die Baseline und „Neu mit Atlas“ (Dateivorlagen von Base). Notizen und
// Lesezeichen für den Reiter „Gemerkt“ (#755) kommen vom Modul Lesezeichen
// (#1456), aktives Issue und Zustand der Issues für den Reiter „Issues“
// (#2052) vom Tracker.

interface

uses
  System.SysUtils,
  Atlas.Plugin.SavedPlaces.Contract,
  Atlas.Core.Welcome.Setup,
  Atlas.IDE.Base.Foundation.IssueWork;

type
  /// <summary>Ende eines Builds: AError &lt;&gt; '' = nicht gebaut (Grund), sonst Erfolg.</summary>
  TAtlasQuickBuildDone = reference to procedure(ASucceeded: Boolean; const AError: string);
  /// <summary>Baut das offene AProject (Konfiguration und Plattform '' = wie in der IDE); False mit Grund.</summary>
  TAtlasQuickBuildFunc = reference to function(const AProject, AConfiguration, APlatform: string;
    const ADone: TAtlasQuickBuildDone; out AReason: string): Boolean;
  /// <summary>Startet die Tests des offenen Testprojekts ATestProject (mit Build vorab); False mit Grund.</summary>
  TAtlasQuickTestsFunc = reference to function(const ATestProject: string; out AReason: string): Boolean;
  /// <summary>Startprofile von AProject (Namen) und das aktive.</summary>
  TAtlasQuickProfilesFunc = reference to function(const AProject: string; out AActive: string): TArray<string>;
  /// <summary>Startet das offene AProject mit Profil AProfile ('' = ohne); False mit Grund.</summary>
  TAtlasQuickRunFunc = reference to function(const AProject, AProfile: string; out AReason: string): Boolean;
  /// <summary>Namen der Projektaufgaben von AProject (#900).</summary>
  TAtlasQuickTaskNamesFunc = reference to function(const AProject: string): TArray<string>;
  /// <summary>Startet die Projektaufgabe AName von AProject; False mit Grund.</summary>
  TAtlasQuickRunTaskFunc = reference to function(const AProject, AName: string; out AReason: string): Boolean;

  /// <summary>Haken der IDE-Schicht für die Schnellaktionen (Composition setzt sie).</summary>
  TAtlasQuickActionHooks = record
    OnBuild: TAtlasQuickBuildFunc;
    OnTests: TAtlasQuickTestsFunc;
    /// <summary>Läuft ein Testlauf (auch der Build davor)?</summary>
    OnTestsBusy: TFunc<Boolean>;
    /// <summary>Ist die IDE schon mit einem Build oder Testlauf beschäftigt (auch nicht von hier)?</summary>
    OnIdeBusy: TFunc<Boolean>;
    OnProfiles: TAtlasQuickProfilesFunc;
    OnRun: TAtlasQuickRunFunc;
    OnTaskNames: TAtlasQuickTaskNamesFunc;
    OnRunTask: TAtlasQuickRunTaskFunc;
  end;

  TAtlasWelcomeNeighbors = class
  public
    /// <summary>Haken der Schnellaktionen (#764) an die Module Build-Pipeline, Tests und Build-Werkzeuge.</summary>
    class function QuickActionHooks: TAtlasQuickActionHooks; static;
    /// <summary>Baseline von AProject über das Modul Prüfregeln aktualisieren (#759); '' = gestartet, sonst der
    /// Grund.</summary>
    class function StartBaseline(const AProject: string; const ADone: TAtlasSetupBaselineDone): string; static;
    /// <summary>Baseline für den Bereich „Projekt für Atlas einrichten“ (#759) über das Modul Prüfregeln.</summary>
    class function SetupBaseline: TAtlasSetupBaselineStart; static;
    /// <summary>„Neu mit Atlas“ für die Einrichtung (#759): Dateivorlagen von Base.</summary>
    class function SetupNewFile: TAtlasSetupNewFile; static;
    /// <summary>Notizen und Lesezeichen neben AProjects vom Modul Lesezeichen; leer ohne das Modul.</summary>
    class function SavedPlaces(const AProjects: TArray<string>): TAtlasSavedPlaces; static;
    /// <summary>Lesezeichen über das Modul Lesezeichen öffnen (#622); False, wenn es fehlt oder das gerade nicht
    /// kann: dann öffnet die Seite Datei und Zeile selbst.</summary>
    class function OpenBookmark(const AProject, AId: string): Boolean; static;
    /// <summary>Aktives Issue und Zustände vom Tracker (#2052); False ohne das Modul.</summary>
    class function IssueWorkSource(out ASource: IAtlasIssueWorkSource): Boolean; static;
  end;

implementation

uses
  Atlas.Core.Generate.FileTemplates,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Generate.NewFile,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Welcome.QuickActions,
  Atlas.IDE.Base.Foundation.BuildPipeline,
  Atlas.IDE.Base.Foundation.Tests,
  Atlas.IDE.Base.Foundation.BuildTools,
  Atlas.IDE.Base.Foundation.Rules,
  Atlas.Plugin.Localization.Strings,
  Atlas.UI.Welcome.Strings;

function BuildJobs(out AJobs: IAtlasBuildJobs): Boolean;
var
  mItem: IInterface;
begin
  AJobs := nil;
  Result := False;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasBuildJobs) do
  begin
    if not Result then
    begin
      Result := Supports(mItem, IAtlasBuildJobs, AJobs);
    end;
  end;
end;

function TestsSource(out ATests: IAtlasTestsSource): Boolean;
var
  mItem: IInterface;
begin
  ATests := nil;
  Result := False;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasTestsSource) do
  begin
    if not Result then
    begin
      Result := Supports(mItem, IAtlasTestsSource, ATests);
    end;
  end;
end;

function BuildTools(out ATools: IAtlasBuildToolsSource): Boolean;
var
  mItem: IInterface;
begin
  ATools := nil;
  Result := False;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasBuildToolsSource) do
  begin
    if not Result then
    begin
      Result := Supports(mItem, IAtlasBuildToolsSource, ATools);
    end;
  end;
end;

function SavedSource(out ASource: IAtlasSavedPlacesSource): Boolean;
var
  mItem: IInterface;
begin
  ASource := nil;
  Result := False;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasSavedPlacesSource) do
  begin
    if not Result then
    begin
      Result := Supports(mItem, IAtlasSavedPlacesSource, ASource);
    end;
  end;
end;

function Baseline(out ASource: IAtlasBaselineSource): Boolean;
var
  mItem: IInterface;
begin
  ASource := nil;
  Result := False;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasBaselineSource) do
  begin
    if not Result then
    begin
      Result := Supports(mItem, IAtlasBaselineSource, ASource);
    end;
  end;
end;

/// <summary>Ergebnis an die Einrichtung (#759); eigene Routine, weil die beiden gleich gebauten
/// Methodenreferenzen in Delphi 12 verschiedene Typen sind.</summary>
function SetupBaselineDone(const ADone: TAtlasSetupBaselineDone): TAtlasBaselineUpdateDone;
begin
  Result := nil;
  if Assigned(ADone) then
  begin
    Result :=
      procedure(ASucceeded: Boolean; ATotal, AFiles: Integer; const AReason: string)
      begin
        ADone(ASucceeded, ATotal, AFiles, AReason);
      end;
  end;
end;

function JobDone(const ADone: TAtlasQuickBuildDone): TAtlasBuildJobDone;
begin
  Result :=
    procedure(const AResult: TAtlasBuildJobResult)
    begin
      ADone(AResult.Succeeded, AResult.Error);
    end;
end;

function StartBuild(const AProject, AConfiguration, APlatform: string; const ADone: TAtlasQuickBuildDone;
  out AReason: string): Boolean;
var
  mJob: TAtlasBuildJob;
  mJobs: IAtlasBuildJobs;
begin
  Result := False;
  AReason := TAtlasStrings.Text(TAtlasTextId.TestsNoBuildRunner);
  if BuildJobs(mJobs) then
  begin
    mJob := Default(TAtlasBuildJob);
    mJob.Project := AProject;
    mJob.Kind := TAtlasBuildJobKind.Build;
    mJob.Configuration := AConfiguration;
    mJob.Platform := APlatform;
    mJob.RequestedBy := TAtlasWelcomeQuickActions.cRequestedBy;
    AReason := '';
    Result := mJobs.Start(mJob, JobDone(ADone), AReason);
  end;
end;

function RunTests(const ATestProject: string; out AReason: string): Boolean;
var
  mTests: IAtlasTestsSource;
begin
  AReason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonTestsOff);
  Result := TestsSource(mTests) and mTests.RunProject(ATestProject, AReason);
end;

function TestsRunning: Boolean;
var
  mTests: IAtlasTestsSource;
begin
  Result := TestsSource(mTests) and mTests.Busy;
end;

function IdeBusy: Boolean;
var
  mJobs: IAtlasBuildJobs;
begin
  Result := (BuildJobs(mJobs) and mJobs.Busy) or TestsRunning;
end;

function Profiles(const AProject: string; out AActive: string): TArray<string>;
var
  mTools: IAtlasBuildToolsSource;
begin
  Result := nil;
  AActive := '';
  if BuildTools(mTools) then
  begin
    Result := mTools.StartProfiles(AProject, AActive);
  end;
end;

function RunProfile(const AProject, AProfile: string; out AReason: string): Boolean;
var
  mTools: IAtlasBuildToolsSource;
begin
  Result := False;
  AReason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonTasksOff);
  if BuildTools(mTools) then
  begin
    Result := mTools.RunStartProfile(AProject, AProfile, AReason);
  end;
end;

function TaskNames(const AProject: string): TArray<string>;
var
  mTools: IAtlasBuildToolsSource;
begin
  Result := nil;
  if BuildTools(mTools) then
  begin
    Result := mTools.TaskNames(AProject);
  end;
end;

function RunTask(const AProject, AName: string; out AReason: string): Boolean;
var
  mTools: IAtlasBuildToolsSource;
begin
  Result := False;
  AReason := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeQuickReasonTasksOff);
  if BuildTools(mTools) then
  begin
    Result := mTools.RunTask(AProject, AName, AReason);
  end;
end;

{ TAtlasWelcomeNeighbors }

class function TAtlasWelcomeNeighbors.QuickActionHooks: TAtlasQuickActionHooks;
begin
  Result := Default(TAtlasQuickActionHooks);
  Result.OnBuild := StartBuild;
  Result.OnTests := RunTests;
  Result.OnTestsBusy := TestsRunning;
  Result.OnIdeBusy := IdeBusy;
  Result.OnProfiles := Profiles;
  Result.OnRun := RunProfile;
  Result.OnTaskNames := TaskNames;
  Result.OnRunTask := RunTask;
end;

class function TAtlasWelcomeNeighbors.StartBaseline(const AProject: string;
  const ADone: TAtlasSetupBaselineDone): string;
var
  mSource: IAtlasBaselineSource;
begin
  Result := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.BaselineUpdateModuleOff);
  if Baseline(mSource) then
  begin
    Result := mSource.StartUpdate(AProject, SetupBaselineDone(ADone));
  end;
end;

function StartBaselineOf(const AProject: string; const ADone: TAtlasSetupBaselineDone): string;
begin
  Result := TAtlasWelcomeNeighbors.StartBaseline(AProject, ADone);
end;

procedure NoteNewFile(AText: string);
begin
  // Nur Meldungsansicht: Die Zeilen enthalten Pfade.
  TAtlasIdeHost.Message(AText);
end;

procedure NewFile(AKind: TAtlasNewFileKind);
begin
  TAtlasIdeNewFile.Show(AKind, TAtlasIdeHost.FileSnippets, NoteNewFile);
end;

class function TAtlasWelcomeNeighbors.SetupBaseline: TAtlasSetupBaselineStart;
begin
  Result := StartBaselineOf;
end;

class function TAtlasWelcomeNeighbors.SetupNewFile: TAtlasSetupNewFile;
begin
  Result := NewFile;
end;

class function TAtlasWelcomeNeighbors.SavedPlaces(const AProjects: TArray<string>): TAtlasSavedPlaces;
var
  mSource: IAtlasSavedPlacesSource;
begin
  Result := nil;
  if SavedSource(mSource) then
  begin
    Result := mSource.Places(AProjects);
  end;
end;

class function TAtlasWelcomeNeighbors.OpenBookmark(const AProject, AId: string): Boolean;
var
  mSource: IAtlasSavedPlacesSource;
begin
  Result := SavedSource(mSource) and mSource.OpenBookmark(AProject, AId);
end;

class function TAtlasWelcomeNeighbors.IssueWorkSource(out ASource: IAtlasIssueWorkSource): Boolean;
var
  mItem: IInterface;
begin
  ASource := nil;
  Result := False;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasIssueWorkSource) do
  begin
    if not Result then
    begin
      Result := Supports(mItem, IAtlasIssueWorkSource, ASource);
    end;
  end;
end;

end.
