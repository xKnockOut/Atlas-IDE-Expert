unit Atlas.IDE.Tests.Composition;

// Modul Tests (#1455, ADR 0017): einzige Unit, die den Testläufer für DUnitX
// (#69), „Test am Cursor ausführen bzw. debuggen“ (#585), die Code Lens der
// Tests und „Betroffene Tests ausführen“ (#1353) erzeugt. Sie meldet in ihrer
// Initialisierung das Modul „atlas.tests“ (Modulschalter tests, #1454) bei
// der Registry von Base an und stellt über dessen Scope bereit:
// - den Teil Tests der Feature-Tabelle,
// - Befehle (Palette), den Eintrag „Betroffene Tests ausführen“ im
//   Atlas-Menü und „Test ausführen“/„Test debuggen“ im Kontextmenü,
// - Hörer für Einstellungen und bewertete Builds (Tests nach dem Build),
// - IAtlasTestRunner (Base: Auswirkungsanalyse #1120, Willkommensseite) und
//   IAtlasTestsSource (Atlas.IDE.Contracts, Willkommensseite); das Ende eines
//   Laufs schreibt das Modul in die Projekt-Zusammenfassung von Base
//   (TAtlasIdeProjectSummaries, #69) und meldet es jedem IAtlasTestsListener.
// Gebaut wird über den Läufer der Builds auf Auftrag der Build-Pipeline
// (IAtlasBuildJobs aus Atlas.IDE.Contracts, ohne Modul nicht), die Probleme gehen an das Problemfenster von
// Base; die fehlgeschlagenen Tests des letzten Laufs liest das Modul aus den
// Projektdateien (TAtlasProjectSummaries), auch ohne Willkommensseite.
// Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Verdict,
  Atlas.IDE.Contracts.Tests,
  Atlas.IDE.Contracts.BuildPipeline;

type
  TAtlasTestsModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasAppliesSettings, IAtlasBuildVerdictListener, IAtlasTestRunner, IAtlasTestsSource)
  public const
    ModuleId = 'atlas.tests';
    Switch = 'tests';
  private
    FActive: Boolean;
    class function Parts: TArray<IAtlasFeaturePart>; static;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    procedure ApplySettings;
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
    procedure RunTests(const AFileName: string; const ATests: TArray<string>);
    function RunProject(const ATestProject: string; out AReason: string): Boolean;
    function DebugByName(const AProject, AFullName: string; out AReason: string): Boolean;
    function LocateByName(const AProject, AFullName: string; out AFileName: string; out ALine: Integer): Boolean;
    function Busy: Boolean;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Adapters.ProcessRunner,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.Debug,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.CodeInsight.Manager,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.Projects.Summaries,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Debug,
  Atlas.IDE.Tests.Lens,
  Atlas.IDE.Tests.Affected,
  Atlas.UI.Strings,
  Atlas.UI.Tests.Strings;

var
  GScope: IAtlasModuleScope;
  GTests: TAtlasIdeTests;
  GDebugger: TAtlasIdeTestDebugger;
  GLens: TAtlasIdeTestsLens;

{ Sichtbarkeit }

function TestsVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestRun and (GTests <> nil);
end;

function AffectedTestsVisible: Boolean;
begin
  Result := TAtlasIdeAffectedTests.Enabled and (GTests <> nil);
end;

function TestDebugVisible: Boolean;
begin
  Result := TAtlasTestDebug.DebugWanted(TAtlasIdeSettings.Current) and (GDebugger <> nil);
end;

{ Läufer }

/// <summary>Prozessläufer der Versionsverwaltung für das Testprogramm; eigene Routine, damit die Referenz nichts aus
/// StartTests einfängt.</summary>
function TestsProcess: TAtlasTestsRunnerFactory;
begin
  Result :=
    function(ACancelled: TFunc<Boolean>): IAtlasVcsRunner
    begin
      Result := TAtlasVcsProcessRunner.Create(False, ACancelled);
    end;
end;

/// <summary>Builds auf Auftrag des Moduls Build-Pipeline (Vertrag); False ohne laufendes Modul.</summary>
function BuildJobs(out AJobs: IAtlasBuildJobs): Boolean;
var
  mItem: IInterface;
begin
  AJobs := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasBuildJobs) do
    if Supports(mItem, IAtlasBuildJobs, AJobs) then
      Exit(True);
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
    TAtlasProblemsController.Current.SetTests(AProblems);
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
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        TAtlasIdeProjectSummaries.Current.RecordTests(AProject, ATests);
      end);
  mPassed := ATests.Passed;
  mFailed := ATests.Failed + ATests.Errors;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasTestsListener) do
    if Supports(mItem, IAtlasTestsListener, mListener) then
      TAtlasGuard.Run(TAtlasFeature.Build,
        procedure
        begin
          mListener.TestsFinished(AProject, mPassed, mFailed);
        end);
end;

function LastFailed(AProject: string): TArray<string>;
begin
  Result := TAtlasProjectSummaries.FailedTestsOf(TAtlasProjectSummaries.DefaultFolder, AProject);
end;

procedure RunAtCursor;
begin
  if GDebugger <> nil then
    TAtlasGuard.Run(TAtlasFeature.Build, GDebugger.RunAtCursor);
end;

procedure DebugAtCursor;
begin
  if GDebugger <> nil then
    TAtlasGuard.Run(TAtlasFeature.Build, GDebugger.DebugAtCursor);
end;

{ Betroffene Tests (#1353) }

procedure AffectedRunTests(const AFileName: string; const ATests: TArray<string>);
begin
  if GTests <> nil then
    GTests.RunTests(AFileName, ATests);
end;

procedure AffectedRunAll;
begin
  if GTests <> nil then
    GTests.RunAll;
end;

procedure AffectedResolveTarget(const AThen: TAtlasAffectedTargetProc);
var
  mThen: TAtlasAffectedTargetProc;
begin
  if GTests = nil then
    Exit;
  mThen := AThen;
  GTests.ResolveProject('',
    procedure(const AProject: IOTAProject)
    begin
      mThen(TAtlasIdeTests.TargetOf(AProject, nil));
    end);
end;

function ServerPath: string;
var
  mArguments: string;
begin
  Result := TAtlasCodeInsightManager.ServerPath(mArguments);
end;

function AffectedHooks: TAtlasAffectedTestsHooks;
begin
  Result := Default(TAtlasAffectedTestsHooks);
  Result.RunTests := AffectedRunTests;
  Result.RunAll := AffectedRunAll;
  Result.ResolveTarget := AffectedResolveTarget;
  Result.ServerPath := ServerPath;
end;

{ Teil Tests }

procedure StartTests;
begin
  GTests := TAtlasIdeTests.Create(TestsProcess());
  GTests.OnBuild := BuildForTests;
  GTests.OnProblems := ShowProblems;
  GTests.OnFinished := AnnounceTests;
  GTests.OnLastFailed := LastFailed;
  // Einzelner Test ausführen bzw. debuggen (#585), auch aus dem Kontextmenü und der Lens.
  GDebugger := TAtlasIdeTestDebugger.Create(GTests);
  GLens := TAtlasIdeTestsLens.Create(GTests, GDebugger);
  TAtlasIdeAffectedTests.Install(AffectedHooks);
end;

procedure StopTests;
begin
  // tests.run aus (oder Modul aus): pre-commit-Hook entfernen, solange die Haken noch stehen; beim Entladen bleibt
  // er (Einstellung an).
  if not TAtlasIdeAffectedTests.Enabled then
    TAtlasIdeAffectedTests.ApplySettings;
  TAtlasIdeAffectedTests.Uninstall;
  // Erst die Lens (sie zeigt auf Läufer und Debugger-Teil), dann der Debugger-Teil (stellt eine laufende Sitzung
  // zurück), dann der Läufer; seine Probleme verschwinden mit ihm.
  FreeAndNil(GLens);
  FreeAndNil(GDebugger);
  try
    FreeAndNil(GTests);
  finally
    if TAtlasProblemsController.Current <> nil then
      TAtlasProblemsController.Current.ClearTests;
  end;
end;

function TestsStarted: Boolean;
begin
  Result := GTests <> nil;
end;

{ Befehle }

function Guarded(AFeature: TAtlasFeature; const AProc: TProc): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasGuard.Run(AFeature, AProc);
    end;
end;

function Command(const AId: string; ACaption: TAtlasTestsTextId; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := TAtlasTestsStrings.Text(ACaption);
  Result.Run := ARun;
  Result.Visible := AVisible;
end;

procedure RunAll;
begin
  if GTests <> nil then
    TAtlasGuard.Run(TAtlasFeature.Build, GTests.RunAll);
end;

procedure RunFailed;
begin
  if GTests <> nil then
    TAtlasGuard.Run(TAtlasFeature.Build, GTests.RunFailed);
end;

{ TAtlasTestsModule }

function TAtlasTestsModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := ModuleId;
  Result.Name := 'Tests';
  Result.Version := TAtlasVersion.Version;
  Result.Handle := HInstance;
  // Der Läufer baut und startet Programme: nur im normalen Start.
  Result.MinLevel := TAtlasSafeLevel.Normal;
  Result.Switch := Switch;
end;

procedure TAtlasTestsModule.Start;
begin
  FActive := True;
end;

procedure TAtlasTestsModule.Stop;
begin
  FActive := False;
end;

function TAtlasTestsModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasTestsModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Betroffene Tests (#1353): sichtbar mit tests.affected und tests.run.
    Command('Atlas.RunAffectedTests', TAtlasTestsTextId.TestsAffectedCommand,
      Guarded(TAtlasFeature.Build, TAtlasIdeAffectedTests.Run), AffectedTestsVisible),
    // DUnitX-Tests (#69): sichtbar, solange TestRun an ist und der Läufer läuft.
    Command('Atlas.RunTests', TAtlasTestsTextId.TestsRunCommand, RunAll, TestsVisible),
    Command('Atlas.RunFailedTests', TAtlasTestsTextId.TestsRunFailedCommand, RunFailed, TestsVisible),
    // Einzelner Test am Cursor (#585): ausführen (mit TestRun) und im Debugger (mit TestDebug).
    Command('Atlas.RunTest', TAtlasTestsTextId.TestsRunHereCommand, RunAtCursor, TestsVisible),
    Command('Atlas.DebugTest', TAtlasTestsTextId.TestsDebugCommand, DebugAtCursor, TestDebugVisible)];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

function TAtlasTestsModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    MenuEntry('Atlas.RunAffectedTests', TAtlasMenuPlace.AtlasMenu),
    // Test am Cursor (#585) im Untermenü „Atlas“ des Editors.
    MenuEntry('Atlas.RunTest', TAtlasMenuPlace.EditorContext),
    MenuEntry('Atlas.DebugTest', TAtlasMenuPlace.EditorContext)];
end;

procedure TAtlasTestsModule.ApplySettings;
begin
  // tests.affectedBeforeCommit (#1353): pre-commit-Hook anlegen bzw. entfernen.
  if GTests <> nil then
    TAtlasIdeAffectedTests.ApplySettings;
end;

procedure TAtlasTestsModule.BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
begin
  // Tests nach dem Build (#69), nach derselben Bewertung wie Zusammenfassung und Benachrichtigung (#530).
  if GTests <> nil then
    GTests.BuildFinished(AProject, AVerdict.Effective);
end;

procedure TAtlasTestsModule.RunTests(const AFileName: string; const ATests: TArray<string>);
begin
  if GTests <> nil then
    GTests.RunTests(AFileName, ATests)
  else
    TAtlasIdeHost.Warning(TAtlasStrings.Text(TAtlasTextId.TestsRunOff));
end;

function TAtlasTestsModule.RunProject(const ATestProject: string; out AReason: string): Boolean;
begin
  if GTests = nil then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonTestsOff);
    Exit(False);
  end;
  Result := GTests.RunProject(ATestProject, AReason);
end;

function TAtlasTestsModule.DebugByName(const AProject, AFullName: string; out AReason: string): Boolean;
begin
  AReason := '';
  Result := False;
  if GDebugger <> nil then
    Result := GDebugger.DebugByName(AProject, AFullName, AReason);
end;

function TAtlasTestsModule.LocateByName(const AProject, AFullName: string; out AFileName: string;
  out ALine: Integer): Boolean;
begin
  Result := TAtlasIdeTestDebugger.LocateByName(AProject, AFullName, AFileName, ALine);
end;

function TAtlasTestsModule.Busy: Boolean;
begin
  Result := (GTests <> nil) and GTests.Busy;
end;

class function TAtlasTestsModule.Parts: TArray<IAtlasFeaturePart>;
begin
  // DUnitX-Tests (#69): nur im normalen Start und solange TestRun an ist; baut über den Läufer von Base.
  Result := [
    TAtlasFeaturePart.When('Tests',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.TestRun;
      end, TestsStarted, StartTests, StopTests)];
end;

class function TAtlasTestsModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasTestsModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  mRegistry := AtlasModuleRegistry;
  if (mRegistry = nil) or (GScope <> nil) then
    Exit;
  // Regel 7: zuerst die Vertragsversion von Base (FindClassHInstance einer Base-Klasse, Regel 8).
  if TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), cAtlasCoreContractVersion) <>
    ccMatch then
  begin
    TAtlasGuard.Log('Modul ' + ModuleId + ': Vertragsversion von Base passt nicht, nicht angemeldet');
    Exit;
  end;
  mModule := TAtlasTestsModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
    GScope.Provide(IAtlasFeaturePart, mPart);
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasBuildVerdictListener, mRef);
  GScope.Provide(IAtlasTestRunner, mRef);
  // Vertrag zwischen Modulen: Karte Tests (#763) und Schnellaktionen (#764) der Willkommensseite.
  GScope.Provide(IAtlasTestsSource, mRef);
  Result := True;
end;

class procedure TAtlasTestsModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
    Exit;
  GScope := nil;
  // Regel 5: nur, solange Base noch läuft; sonst hat Base das Modul schon gestoppt und abgemeldet.
  mRegistry := AtlasModuleRegistry;
  if mRegistry <> nil then
    for mFailure in mRegistry.UnregisterModule(ModuleId) do
      TAtlasGuard.Log('Modul ' + ModuleId + ' nicht sauber abgemeldet: ' + mFailure);
end;

initialization
  TAtlasTestsModule.RegisterModule;

finalization
  TAtlasTestsModule.UnregisterModule;

end.
