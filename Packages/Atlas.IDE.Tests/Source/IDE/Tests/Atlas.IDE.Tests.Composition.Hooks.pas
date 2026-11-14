unit Atlas.IDE.Tests.Composition.Hooks;

// Haken des Testläufers, aus Atlas.IDE.Tests.Composition gelöst; die
// Composition setzt sie in StartTests:
// - OnBuild: vor den Tests bauen über IAtlasBuildJobs der Build-Pipeline
//   (Atlas.IDE.Contracts.BuildPipeline, ohne Modul nicht),
// - OnProblems: Fehlschläge ins Problemfenster von Base,
// - OnFinished: Projekt-Zusammenfassung (TAtlasIdeProjectSummaries, #69) und
//   jeder IAtlasTestsListener (Schnellaktionen der Willkommensseite),
// - Ziel und Pfad des Servers der betroffenen Tests, Probleme leeren, Meldung ohne Läufer,
//   Leckprüfung einrichten, Sichtbarkeit von „Test debuggen“;
// - OnLastFailed: fehlgeschlagene Tests des letzten Laufs aus den
//   Projektdateien (TAtlasProjectSummaries), auch ohne Willkommensseite.
// - Mutationslauf (#1460): Schattenprojekt vollständig bauen, mit
//   Konfiguration und Plattform des Testprojekts, Auftraggeber "mutation".

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tests.Run,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Affected;

/// <summary>Vor den Tests bauen: über die Builds auf Auftrag (#261) der Build-Pipeline, Auftraggeber "tests".
/// </summary>
function BuildForTests(const AProject: string; const ADone: TAtlasTestsBuildDone; out AReason: string): Boolean;
/// <summary>Mutationslauf (#1460): ATarget.Project vollständig bauen (Build, nicht make: Die mutierte Kopie ist
/// keine offene Datei) mit Konfiguration und Plattform aus ATarget; Auftraggeber "mutation".</summary>
function BuildForMutation(const ATarget: TAtlasTestTarget; const ADone: TAtlasTestsBuildDone;
  out AReason: string): Boolean;
procedure ShowProblems(const AProblems: TArray<TPair<string, TAtlasProblem>>);
/// <summary>Fehlschläge der Tests aus dem Problemfenster nehmen.</summary>
procedure ClearProblems;
/// <summary>Ziel der betroffenen Tests (#1353): Testprojekt, das ATests für die aktive Unit wählen, an AThen.</summary>
procedure ResolveTestTarget(ATests: TAtlasIdeTests; const AThen: TAtlasAffectedTargetProc);
/// <summary>Meldung „Tests ausführen ist aus“ in der Meldungsansicht.</summary>
procedure WarnTestsOff;
/// <summary>Leckprüfung des aktiven Projekts einrichten (#1880, Atlas.IDE.Tests.LeakSetup).</summary>
procedure SetUpLeakCheck(const AScope: IAtlasModuleScope);
/// <summary>Pfad des Atlas-Servers (Betroffene Tests, #1353).</summary>
function ServerPath: string;
/// <summary>„Test debuggen“ nach den Einstellungen gewünscht.</summary>
function DebugWanted: Boolean;
/// <summary>Ende eines Laufs in die Projekt-Zusammenfassung und an jeden IAtlasTestsListener.</summary>
procedure AnnounceTests(const AProject: string; const ATests: TAtlasProjectTests);
function LastFailed(AProject: string): TArray<string>;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Tests.Debug,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.CodeInsight.Manager.Paths,
  Atlas.IDE.Contracts.Tests,
  Atlas.IDE.Contracts.BuildPipeline,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Tests.LeakSetup,
  Atlas.IDE.Projects.Summaries,
  Atlas.UI.Strings;

/// <summary>Builds auf Auftrag des Moduls Build-Pipeline (Vertrag); False ohne laufendes Modul.</summary>
function BuildJobs(out AJobs: IAtlasBuildJobs): Boolean;
var
  mItem: IInterface;
begin
  AJobs := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasBuildJobs) do
  begin
    if Supports(mItem, IAtlasBuildJobs, AJobs) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Vor den Tests bauen: über die Builds auf Auftrag (#261) der Build-Pipeline, Auftraggeber "tests".
/// </summary>
function BuildForTests(const AProject: string; const ADone: TAtlasTestsBuildDone; out AReason: string): Boolean;
var
  mJobs: IAtlasBuildJobs;
  mJob: TAtlasBuildJob;
  mDone: TAtlasTestsBuildDone;
begin
  if not BuildJobs(mJobs) then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.TestsNoBuildRunner);
    Exit(False);
  end;
  mDone := ADone;
  mJob := Default(TAtlasBuildJob);
  mJob.Project := AProject;
  mJob.Kind := TAtlasBuildJobKind.Make;
  mJob.RequestedBy := TAtlasTestRun.cRequestedBy;
  Result := mJobs.Start(mJob,
    procedure(const AResult: TAtlasBuildJobResult)
    begin
      mDone(AResult.Succeeded, AResult.OutputFile, AResult.Error);
    end, AReason);
end;

function BuildForMutation(const ATarget: TAtlasTestTarget; const ADone: TAtlasTestsBuildDone;
  out AReason: string): Boolean;
const
  cRequestedBy = 'mutation';
var
  mJobs: IAtlasBuildJobs;
  mJob: TAtlasBuildJob;
  mDone: TAtlasTestsBuildDone;
begin
  if not BuildJobs(mJobs) then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.TestsNoBuildRunner);
    Exit(False);
  end;
  mDone := ADone;
  mJob := Default(TAtlasBuildJob);
  mJob.Project := ATarget.Project;
  mJob.Kind := TAtlasBuildJobKind.Build;
  mJob.Configuration := ATarget.Configuration;
  mJob.Platform := ATarget.Platform;
  mJob.RequestedBy := cRequestedBy;
  Result := mJobs.Start(mJob,
    procedure(const AResult: TAtlasBuildJobResult)
    begin
      mDone(AResult.Succeeded, AResult.OutputFile, AResult.Error);
    end, AReason);
end;

procedure ShowProblems(const AProblems: TArray<TPair<string, TAtlasProblem>>);
begin
  if TAtlasProblemsController.Current <> nil then
  begin
    TAtlasProblemsController.Current.SetTests(AProblems);
  end;
end;

procedure ClearProblems;
begin
  if TAtlasProblemsController.Current <> nil then
  begin
    TAtlasProblemsController.Current.ClearTests;
  end;
end;

procedure ResolveTestTarget(ATests: TAtlasIdeTests; const AThen: TAtlasAffectedTargetProc);
var
  mThen: TAtlasAffectedTargetProc;
begin
  mThen := AThen;
  ATests.ResolveProject('',
    procedure(const AProject: IOTAProject)
    begin
      mThen(TAtlasIdeTests.TargetOf(AProject, nil));
    end);
end;

procedure WarnTestsOff;
begin
  TAtlasIdeHost.Warning(TAtlasStrings.Text(TAtlasTextId.TestsRunOff));
end;

procedure SetUpLeakCheck(const AScope: IAtlasModuleScope);
begin
  TAtlasIdeLeakSetup.Run(AScope);
end;

function ServerPath: string;
var
  mArguments: string;
begin
  Result := TAtlasCodeInsightPaths.ServerPath(mArguments);
end;

function DebugWanted: Boolean;
begin
  Result := TAtlasTestDebug.DebugWanted(TAtlasIdeSettings.Current);
end;

/// <summary>Ende eines Laufs in die Projekt-Zusammenfassung (#69, Karte Tests) und an jeden IAtlasTestsListener
/// (Schnellaktionen der Willkommensseite).</summary>
procedure AnnounceTests(const AProject: string; const ATests: TAtlasProjectTests);
var
  mItem: IInterface;
  mListener: IAtlasTestsListener;
  mPassed, mFailed: Integer;
begin
  if TAtlasIdeProjectSummaries.Current <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        TAtlasIdeProjectSummaries.Current.RecordTests(AProject, ATests);
      end);
  end;
  mPassed := ATests.Passed;
  mFailed := ATests.Failed + ATests.Errors;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasTestsListener) do
  begin
    if Supports(mItem, IAtlasTestsListener, mListener) then
    begin
      TAtlasGuard.Run(TAtlasFeature.Build,
        procedure
        begin
          mListener.TestsFinished(AProject, mPassed, mFailed);
        end);
    end;
  end;
end;

function LastFailed(AProject: string): TArray<string>;
begin
  Result := TAtlasProjectSummaries.FailedTestsOf(TAtlasProjectSummaries.DefaultFolder, AProject);
end;

end.
