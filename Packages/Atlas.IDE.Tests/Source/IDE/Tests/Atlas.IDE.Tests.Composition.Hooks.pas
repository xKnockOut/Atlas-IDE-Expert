unit Atlas.IDE.Tests.Composition.Hooks;

// Haken des Testläufers (A-09), aus Atlas.IDE.Tests.Composition gelöst; die
// Composition setzt sie in StartTests:
// - OnBuild: vor den Tests bauen über IAtlasBuildJobs der Build-Pipeline
//   (Atlas.IDE.Contracts.BuildPipeline, ohne Modul nicht),
// - OnProblems: Fehlschläge ins Problemfenster von Base,
// - OnFinished: Projekt-Zusammenfassung (TAtlasIdeProjectSummaries, #69) und
//   jeder IAtlasTestsListener (Schnellaktionen der Willkommensseite),
// - OnLastFailed: fehlgeschlagene Tests des letzten Laufs aus den
//   Projektdateien (TAtlasProjectSummaries), auch ohne Willkommensseite.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.IDE.Tests.Runner;

/// <summary>Vor den Tests bauen: über die Builds auf Auftrag (#261) der Build-Pipeline, Auftraggeber "tests".
/// </summary>
function BuildForTests(const AProject: string; const ADone: TAtlasTestsBuildDone; out AReason: string): Boolean;
procedure ShowProblems(const AProblems: TArray<TPair<string, TAtlasProblem>>);
/// <summary>Ende eines Laufs in die Projekt-Zusammenfassung und an jeden IAtlasTestsListener.</summary>
procedure AnnounceTests(const AProject: string; const ATests: TAtlasProjectTests);
function LastFailed(AProject: string): TArray<string>;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Tests.Run,
  Atlas.IDE.Contracts.Tests,
  Atlas.IDE.Contracts.BuildPipeline,
  Atlas.IDE.Problems.Controller,
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
  mJob.RequestedBy := TAtlasTestRun.RequestedBy;
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
