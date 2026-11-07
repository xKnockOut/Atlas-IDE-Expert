unit Atlas.IDE.Welcome.Neighbors;

// Andere Module für die Willkommensseite (#1455, ADR 0017 Regel 6): Builds
// auf Auftrag (Build-Pipeline), Testprojekte (Tests), Startprofile und
// Projektaufgaben (Build-Werkzeuge) und die Baseline (Prüfregeln) erreicht
// die Seite nur über deren Verträge in Base (Atlas.IDE.Contracts.*) und fragt bei
// jedem Aufruf neu (Regel 2): Fehlt ein Modul oder ist es aus, meldet die
// Schnellaktion den Grund, statt etwas zu tun. Vorher klebte die
// Kompositionswurzel diese Verbindungen. Die Einrichtung (#759) bekommt hier
// die Baseline und „Neu mit Atlas“ (Dateivorlagen von Base). Notizen und
// Lesezeichen für den Reiter „Gemerkt“ (#755) kommen vom Modul Lesezeichen
// (#1456).

interface

uses
  System.SysUtils,
  Atlas.Core.SavedPlaces.Contract,
  Atlas.IDE.Welcome.QuickActions,
  Atlas.IDE.Welcome.Setup;

type
  TAtlasWelcomeNeighbors = class
  public
    /// <summary>Haken der Schnellaktionen (#764) an die Module Build-Pipeline, Tests und Build-Werkzeuge.</summary>
    class procedure Connect(AQuickActions: TAtlasIdeQuickActions); static;
    /// <summary>Baseline von AProject über das Modul Prüfregeln aktualisieren (#759); '' = gestartet, sonst der
    /// Grund.</summary>
    class function StartBaseline(const AProject: string; const ADone: TAtlasSetupBaselineDone): string; static;
    /// <summary>Bereich „Projekt für Atlas einrichten“ (#759) mit Baseline und „Neu mit Atlas“; AMessage bekommt
    /// die Zeilen der Einrichtung.</summary>
    class function CreateSetup(const AMessage: TProc<string>): TAtlasIdeSetup; static;
    /// <summary>Läuft gerade ein Testlauf des Moduls Tests?</summary>
    class function TestsBusy: Boolean; static;
    /// <summary>Notizen und Lesezeichen neben AProjects vom Modul Lesezeichen; leer ohne das Modul.</summary>
    class function SavedPlaces(const AProjects: TArray<string>): TAtlasSavedPlaces; static;
    /// <summary>Lesezeichen über das Modul Lesezeichen öffnen (#622); False, wenn es fehlt oder das gerade nicht
    /// kann: dann öffnet die Seite Datei und Zeile selbst.</summary>
    class function OpenBookmark(const AProject, AId: string): Boolean; static;
  end;

implementation

uses
  Atlas.Core.Generate.FileTemplates,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Generate.NewFile,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Welcome.QuickActions,
  Atlas.IDE.Contracts.BuildPipeline,
  Atlas.IDE.Contracts.Tests,
  Atlas.IDE.Contracts.BuildTools,
  Atlas.IDE.Contracts.Rules,
  Atlas.UI.Strings,
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

class procedure TAtlasWelcomeNeighbors.Connect(AQuickActions: TAtlasIdeQuickActions);
begin
  AQuickActions.Hooks.OnBuild := StartBuild;
  AQuickActions.Hooks.OnTests := RunTests;
  AQuickActions.Hooks.OnTestsBusy := TestsRunning;
  AQuickActions.Hooks.OnIdeBusy := IdeBusy;
  AQuickActions.Hooks.OnProfiles := Profiles;
  AQuickActions.Hooks.OnRun := RunProfile;
  AQuickActions.Hooks.OnTaskNames := TaskNames;
  AQuickActions.Hooks.OnRunTask := RunTask;
end;

class function TAtlasWelcomeNeighbors.StartBaseline(const AProject: string;
  const ADone: TAtlasSetupBaselineDone): string;
var
  mSource: IAtlasBaselineSource;
begin
  Result := TAtlasStrings.Text(TAtlasTextId.BaselineUpdateModuleOff);
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

class function TAtlasWelcomeNeighbors.CreateSetup(const AMessage: TProc<string>): TAtlasIdeSetup;
begin
  Result := TAtlasIdeSetup.Create(AMessage, StartBaselineOf, NewFile);
end;

class function TAtlasWelcomeNeighbors.TestsBusy: Boolean;
begin
  Result := TestsRunning;
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

end.
