unit Atlas.IDE.Tests.Composition;

// Modul Tests (#1455): einzige Unit, die den Testläufer für DUnitX
// (#69), „Test am Cursor ausführen bzw. debuggen“ (#585), die Code Lens der
// Tests und „Betroffene Tests ausführen“ (#1353) erzeugt. Sie meldet in ihrer
// Initialisierung das Modul „atlas.tests“ (Modulschalter tests, #1454) bei
// der Registry von Base an und stellt über dessen Scope bereit:
// - den Teil Tests der Feature-Tabelle,
// - Befehle (Palette), die Einträge „Betroffene Tests ausführen“,
//   „Veraltete Tests ausführen“ (#1770), „Erwartet und erhalten
//   vergleichen“ (#1779), „Langsamste Tests zeigen“ (#1772), „Wackelnde
//   Tests zeigen“ (#1773, Atlas.IDE.Tests.Flaky) und
//   „Liegengebliebene .received-Dateien löschen“ (#1881) im Atlas-Menü,
//   „TestCase-Tabelle bearbeiten …“ (#1879) in der Palette und im
//   Kontextmenü einer Testunit, das Fenster „Atlas-Tests“ (#1776, Ansicht,
//   Atlas-Menü, Palette; Atlas.IDE.Tests.Explorer) mit Testlisten (#2167,
//   Atlas.IDE.Tests.Lists; „Testliste ausführen: <Name>“ in der Palette, Taste
//   tests.lists.runKey für die zuletzt benutzte), der Teststand in der
//   Statusleiste (#1777, Atlas.IDE.Tests.StatusField), „Test ausführen“/„Test debuggen“ im
//   Kontextmenü und „Tests dieser Unit ausführen“ im Kontextmenü der
//   Projektverwaltung (#1817: Testunits der gewählten Units nach Namen in der
//   Projektgruppe, nur solche
//   mit Fixtures; ohne eine meldet das Modul es in der Meldungsansicht) und
//   den Assistenten „DUnitX-Testunit zu Unit …“ in Datei › Neu › Weitere
//   (#1821: Unit der Projektgruppe wählen, die Unit im Editor vorgewählt;
//   angelegt wie „Zur Testunit wechseln“ von Base), „Leckprüfung
//   einrichten …“ im Kontextmenü der Projektverwaltung und in der Palette
//   (#1880, Atlas.IDE.Tests.LeakSetup über Composition.Hooks) und „Test aus
//   dem Debug-Halt anlegen …“ (#1873, über Atlas.IDE.Tests.Composition.Cases; Palette,
//   Kontextmenü beim Debuggen, Knopf der Exception-Leiste über die Kennung),
//   „Test am Cursor N-mal ausführen …“, „Tests der Klasse in zufälliger
//   Reihenfolge ausführen“, „Mit dieser Reihenfolge erneut ausführen“ und
//   „Testserie abbrechen“ (#1782, Atlas.IDE.Tests.Series; Kontextmenü einer
//   Testunit und Palette; der Prozessläufer fragt den Abbruch der Serie ab),
// - die Marke „getestet von“ an Methoden normaler Units (#1778),
// - die Ablage des letzten Testlaufs für KI-Assistenten (#2409, tests.lastRun; Atlas.IDE.Tests.LastRun),
// - die Schicht der Testabdeckung in der Rinne (#275, IAtlasGutterLayer) mit den Befehlen „Testabdeckung laden …“
//   und „Testabdeckung ausblenden“; ihr Zustand ist ein eigener Teil der Feature-Tabelle (läuft auch ohne
//   tests.run, solange tests.coverage an ist),
// - den Mutationslauf (#1460, tests.mutation; Atlas.IDE.Tests.Mutation) mit den Befehlen „Mutationen der Methode
//   prüfen“, „… der Unit“, „… geänderter Methoden“ und „Mutationslauf abbrechen“ (Palette, Atlas-Menü, Kontextmenü
//   normaler Units) und seine Schicht in der Rinne (Atlas.IDE.Tests.MutationMarks),
// - Hörer für Einstellungen und bewertete Builds (Tests nach dem Build) und für
//   gespeicherte Dateien (betroffene Tests im Hintergrund, #1775),
// - IAtlasTestRunner (Base: Auswirkungsanalyse #1120, Willkommensseite) und
//   IAtlasTestsSource (Atlas.IDE.Base.Foundation.Tests, Willkommensseite); das Ende eines
//   Laufs schreibt das Modul in die Projekt-Zusammenfassung von Base
//   (TAtlasIdeProjectSummaries, #69) und meldet es jedem IAtlasTestsListener,
// - IAtlasTestValues (#1779): „Vergleichen“ im Befund-Hover von Base und auf
//   der Kachel „Testergebnisse“ der Willkommensseite.
// Gebaut wird über den Läufer der Builds auf Auftrag der Build-Pipeline
// (IAtlasBuildJobs aus Atlas.IDE.Base.Foundation.BuildPipeline, ohne Modul nicht), die
// Probleme gehen an das Problemfenster von Base; die fehlgeschlagenen Tests des
// letzten Laufs liest das Modul aus den Projektdateien (TAtlasProjectSummaries),
// auch ohne Willkommensseite.
// Diese Haken stehen in Atlas.IDE.Tests.Composition.Hooks. Die Modulklasse (Adapters.Module), die Läufe
// (Adapters.Runs) und die Werte für „Vergleichen“ (Adapters.Values) erzeugt die Unit nur.
// Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

implementation

uses
  System.SysUtils,
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.Plugin.Build.Contract,
  Atlas.IDE.Base.Foundation.Tests,
  Atlas.UI.Tests.SettingsSection,
  Atlas.Text.Product.Version,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.IDE.Base.Core.ModuleHost,
  Atlas.VersionControl.Repository.Contract,
  Atlas.VersionControl.Repository.Providers.ProcessRunner,
  Atlas.IDE.Base.Core.Modules.FeatureParts,
  Atlas.IDE.Foundation.Settings,
  Atlas.Core.Tests.Debug, // TAtlasTestCompareHooks
  Atlas.IDE.Tests.Output,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.OnSave,
  Atlas.IDE.Tests.Composition.Hooks,
  Atlas.IDE.Tests.Debug,
  Atlas.IDE.Tests.Lens,
  Atlas.IDE.Tests.CoveredBy,
  Atlas.IDE.Tests.Composition.Cases,
  Atlas.IDE.Tests.Affected,
  Atlas.IDE.Tests.Composition.Explorer,
  Atlas.IDE.Tests.Series,
  Atlas.IDE.Tests.Composition.Coverage,
  Atlas.IDE.Tests.Composition.Results,
  Atlas.IDE.Tests.Adapters.Module,
  Atlas.IDE.Tests.Adapters.Runs,
  Atlas.IDE.Tests.Adapters.Values,
  Atlas.UI.Tests.Strings;

var
  GScope: IAtlasModuleScope;
  GOutput: TAtlasIdeTestsOutput;
  GTests: TAtlasIdeTests;
  GOnSave: TAtlasIdeTestsOnSave;
  GDebugger: TAtlasIdeTestDebugger;
  GLens: TAtlasIdeTestsLens;
  GCoveredBy: TAtlasIdeCoveredByLens;
  /// <summary>Serien (#1782) und ihr Abbruchwunsch, den der Prozessläufer liest; GStopRef hält ihn.</summary>
  GSeries: TAtlasIdeTestSeries;
  GStop: TAtlasIdeTestStop;
  GStopRef: IInterface;

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
  Result := DebugWanted and (GDebugger <> nil);
end;

{ Läufer }

/// <summary>Abbruch des Läufers (ACancelled, Entladen) oder der Serie (AStop, #1782); AKeep hält AStop am Leben,
/// solange der Thread des Laufs fragt.</summary>
function StopOrCancelled(const ACancelled: TFunc<Boolean>; AStop: TAtlasIdeTestStop;
  const AKeep: IInterface): TFunc<Boolean>;
var
  mCancelled: TFunc<Boolean>;
  mStop: TAtlasIdeTestStop;
  mKeep: IInterface;
begin
  mCancelled := ACancelled;
  mStop := AStop;
  mKeep := AKeep;
  Result :=
    function: Boolean
    begin
      Result := ((mKeep <> nil) and mStop.Requested) or (Assigned(mCancelled) and mCancelled());
    end;
end;

/// <summary>Prozessläufer der Versionsverwaltung für das Testprogramm; eigene Routine, damit die Referenz nichts aus
/// StartTests einfängt. Bricht auch ab, wenn eine Serie abgebrochen wird (AStop, #1782).</summary>
function TestsProcess(AStop: TAtlasIdeTestStop): TAtlasTestsRunnerFactory;
var
  mStop: TAtlasIdeTestStop;
  mKeep: IInterface;
begin
  mStop := AStop;
  mKeep := AStop;
  Result :=
    function(ACancelled: TFunc<Boolean>): IAtlasVcsRunner
    begin
      Result := TAtlasVcsProcessRunner.Create(False, StopOrCancelled(ACancelled, mStop, mKeep));
    end;
end;

procedure RunAtCursor;
begin
  if GDebugger <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GDebugger.RunAtCursor);
  end;
end;

procedure DebugAtCursor;
begin
  if GDebugger <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GDebugger.DebugAtCursor);
  end;
end;

{ Betroffene Tests (#1353) }

procedure AffectedRunTests(const AFileName: string; const ATests: TArray<string>);
begin
  if GTests <> nil then
  begin
    GTests.RunTests(AFileName, ATests, False);
  end;
end;

procedure AffectedRunAll;
begin
  if GTests <> nil then
  begin
    GTests.RunAll;
  end;
end;

procedure AffectedResolveTarget(const AThen: TAtlasAffectedTargetProc);
begin
  if GTests <> nil then
  begin
    ResolveTestTarget(GTests, AThen);
  end;
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

/// <summary>Scope des Moduls für die Anfragen der Marke „getestet von“ (#1778).</summary>
function ModuleScope: IAtlasModuleScope;
begin
  Result := GScope;
end;

/// <summary>Knopf „Vergleichen“ der Testmarke (#1779); die Lens lebt kürzer als der Vergleich.</summary>
function CompareHooks: TAtlasTestCompareHooks;
begin
  Result := ResultCompareHooks;
  // Serie (#1782): ihr Ergebnis an der Marke.
  Result.Series := GSeries.MarkOf;
end;

procedure StartTests;
begin
  GOutput := TAtlasIdeTestsOutput.Create;
  GStop := TAtlasIdeTestStop.Create;
  GStopRef := GStop;
  GTests := TAtlasIdeTests.Create(TestsProcess(GStop), GOutput);
  GTests.OnBuild := BuildForTests;
  GTests.OnProblems := ShowProblems;
  GTests.OnFinished := AnnounceTests;
  GTests.OnLastFailed := LastFailed;
  // Auswertungen nach dem Lauf: veraltete Ergebnisse, letzter Testlauf, Vergleich, langsamste Tests.
  StartResults(GTests);
  // Einzelner Test ausführen bzw. debuggen (#585), auch aus dem Kontextmenü und der Lens.
  GDebugger := TAtlasIdeTestDebugger.Create(GTests);
  // Tests N-mal bzw. in zufälliger Reihenfolge (#1782): Läufe im Hintergrund über den Läufer.
  GSeries := TAtlasIdeTestSeries.Create(GTests, GOutput, GStop);
  // Wackelnde Tests (#1773), Fenster „Atlas-Tests“ (#1776), Testlisten (#2167) und Teststand (#1777); das Fenster
  // hängt sich als OnReported an, die wackelnden Tests reichen den Lauf an die langsamsten Tests weiter.
  StartExplorer(GTests, GDebugger, GSeries, StaleKeys(), ResultsReported());
  // Lauf ging schief (#2467): Fenster „Atlas-Tests“ öffnen.
  GOutput.OnEnded := ExplorerRunEnded;
  GLens := TAtlasIdeTestsLens.Create(GTests, GDebugger, StateQueries(StaleKeys()), CompareHooks);
  // Marke „getestet von“ an Methoden normaler Units (#1778).
  GCoveredBy := TAtlasIdeCoveredByLens.Create(GTests, ModuleScope, StaleKeys());
  // TestCase-Tabelle (#1879): Befehl und Marke „Tabelle“ der Lens; Grenzfälle (#2173) vorn in OnReported.
  // Ungetestete Methoden des Projekts (#1783) ebenda.
  StartCases(GScope, GTests, GDebugger, GOutput, ModuleScope);
  GLens.OnTable := OpenCaseTable;
  TAtlasIdeAffectedTests.Install(AffectedHooks);
  // Betroffene Tests beim Speichern (#1775): im Hintergrund über den Läufer.
  GOnSave := TAtlasIdeTestsOnSave.Create(GTests, GOutput);
  // Mutationslauf (#1460): Projektwahl und Ausgabe des Läufers, eigener Prozessläufer, Build des Schattenprojekts.
  StartMutation(GScope, GTests, GOutput, TestsProcess(GStop));
end;

procedure StopTests;
begin
  // tests.run aus (oder Modul aus): pre-commit-Hook entfernen, solange die Haken noch stehen; beim Entladen bleibt
  // er (Einstellung an).
  if not TAtlasIdeAffectedTests.Enabled then
  begin
    TAtlasIdeAffectedTests.ApplySettings;
  end;
  TAtlasIdeAffectedTests.Uninstall;
  // Mutationslauf (#1460) vor dem Läufer, dessen Projektwahl und Ausgabe er nutzt; schließt sein Schattenprojekt.
  StopMutation;
  // Tests beim Speichern (#1775) vor dem Läufer: Uninstall hat ihre offenen Anfragen schon verworfen.
  FreeAndNil(GOnSave);
  // Erst die Lens (sie zeigt auf Läufer und Debugger-Teil), dann der Debugger-Teil (stellt eine laufende Sitzung
  // zurück), dann langsamste Tests (#1772), Vergleich (#1779) und Stände der veralteten Ergebnisse (#1770), dann
  // der Läufer; seine Probleme verschwinden mit ihm.
  if GTests <> nil then
  begin
    GTests.OnReported := nil;
  end;
  // Der Teststand (#1777) liest aus dem Fenster „Atlas-Tests“ (#1776), das auf Läufer und Debugger-Teil zeigt:
  // vor allen. Vorher erreicht das Ende eines Laufs das Fenster nicht mehr (#2467).
  if GOutput <> nil then
  begin
    GOutput.OnEnded := nil;
  end;
  StopExplorer;
  FreeAndNil(GCoveredBy);
  FreeAndNil(GLens);
  // Serie (#1782) nach Fenster und Lens, die auf sie zeigen; vor dem Läufer, dessen Ende sie erwartet.
  FreeAndNil(GSeries);
  StopCases(GTests);
  FreeAndNil(GDebugger);
  // Wackelnde Tests (#1773) nach Fenster und Lens, die sie abfragen.
  StopFlakyTests;
  StopResults;
  try
    FreeAndNil(GTests);
    FreeAndNil(GOutput);
    GStop := nil;
    GStopRef := nil;
  finally
    ClearProblems;
  end;
end;

function TestsStarted: Boolean;
begin
  Result := GTests <> nil;
end;

{ Befehle }

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
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GTests.RunAll);
  end;
end;

procedure RunFailed;
begin
  if GTests <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GTests.RunFailed);
  end;
end;

{ Serien (#1782) }

function SeriesVisible: Boolean;
begin
  Result := TestsVisible and (GSeries <> nil);
end;

function ShuffleAgainVisible: Boolean;
begin
  Result := SeriesVisible and GSeries.CanShuffleAgain;
end;

function CancelSeriesVisible: Boolean;
begin
  Result := SeriesVisible and GSeries.Running;
end;

procedure RepeatTest;
begin
  if GSeries <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GSeries.RepeatAtCursor);
  end;
end;

procedure ShuffleTests;
begin
  if GSeries <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GSeries.ShuffleAtCursor);
  end;
end;

procedure ShuffleTestsAgain;
begin
  if GSeries <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GSeries.ShuffleAgain);
  end;
end;

procedure CancelSeries;
begin
  if GSeries <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GSeries.Cancel);
  end;
end;

{ TestCase-Tabelle (#1879), Grenzfälle (#2173) }

function CaseTableVisible: Boolean;
begin
  Result := TestsVisible and CaseTableWanted;
end;

function BoundaryCasesVisible: Boolean;
begin
  Result := TestsVisible and BoundaryCasesWanted;
end;

{ Projektverwaltung (#1817) }

function ProjectUnitTestsVisible: Boolean;
begin
  Result := TestsVisible and ProjectUnitsSelected;
end;

procedure RunProjectUnitTests;
begin
  RunSelectedUnitTests(GTests);
end;

{ Test aus dem Debug-Halt (#1873) }

procedure TestFromDebugStop;
begin
  RunTestFromDebug(GScope);
end;

{ Leckprüfung einrichten (#1880) }

function LeakSetupVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestsLeakSetup;
end;

procedure RunLeakSetup;
begin
  SetUpLeakCheck(GScope);
end;

function Described(const ACommand: TAtlasModuleCommand; ADescription: TAtlasTestsTextId): TAtlasModuleCommand;
begin
  Result := ACommand;
  Result.Description := TAtlasTestsStrings.Text(ADescription);
end;

/// <summary>Befehle des Moduls (Palette, Menüs, Kontextmenüs).</summary>
function ModuleCommands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Betroffene Tests (#1353): sichtbar mit tests.affected und tests.run.
    Command('Atlas.RunAffectedTests', TAtlasTestsTextId.TestsAffectedCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Build, TAtlasIdeAffectedTests.Run), AffectedTestsVisible),
    // Fenster „Atlas-Tests“ (#1776): sichtbar mit tests.window.
    Described(Command('Atlas.TestExplorer', TAtlasTestsTextId.ExplorerCommand, ShowExplorer, ExplorerVisible),
      TAtlasTestsTextId.ExplorerHint),
    // DUnitX-Tests (#69): sichtbar, solange TestRun an ist und der Läufer läuft.
    Command('Atlas.RunTests', TAtlasTestsTextId.TestsRunCommand, RunAll, TestsVisible),
    Command('Atlas.RunFailedTests', TAtlasTestsTextId.TestsRunFailedCommand, RunFailed, TestsVisible),
    // Veraltete Ergebnisse (#1770): sichtbar mit tests.stale.
    Command('Atlas.RunStaleTests', TAtlasTestsTextId.TestsRunStaleCommand, RunStale, StaleTestsVisible),
    // Erwartet und erhalten eines Fehlschlags (#1779): sichtbar mit tests.compare.
    Command('Atlas.CompareTestValues', TAtlasTestsTextId.TestsCompareCommand, CompareValues, CompareVisible),
    // Wackelnde Tests (#1773): Fenster „Atlas-Tests“ mit dem Filter „wackelt“; sichtbar mit tests.flaky.
    Described(Command('Atlas.ShowFlakyTests', TAtlasTestsTextId.TestsFlakyCommand, ShowFlaky, FlakyVisible),
      TAtlasTestsTextId.TestsFlakyHint),
    // Langsamste Tests (#1772): sichtbar mit tests.showDuration.
    Command('Atlas.ShowSlowestTests', TAtlasTestsTextId.TestsSlowestCommand, ShowSlowest, SlowestVisible),
    // [TestCase]-Fälle als Tabelle (#1879): sichtbar mit tests.testCaseTable.
    Command('Atlas.EditTestCases', TAtlasTestsTextId.TestsCaseTableCommand, EditCaseTable, CaseTableVisible),
    // Grenzfälle als Testfälle (#2173): sichtbar mit tests.boundaryCases.
    Command('Atlas.SuggestBoundaryCases', TAtlasTestsTextId.TestsBoundaryCommand, SuggestBoundaryCases,
      BoundaryCasesVisible),
    // Vergleichsdateien (#1881): sichtbar mit tests.approvalFiles.
    Command('Atlas.CleanApprovalFiles', TAtlasTestsTextId.TestsApprovalCleanCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Build, CleanApprovalFiles), ApprovalFilesVisible),
    // Ungetestete Methoden des Projekts (#1783): sichtbar mit TestRun.
    Described(Command('Atlas.ListUntestedMethods', TAtlasTestsTextId.UntestedProjectCommand, ListUntested,
      TestsVisible), TAtlasTestsTextId.UntestedProjectHint),
    // Einzelner Test am Cursor (#585): ausführen (mit TestRun) und im Debugger (mit TestDebug).
    Command('Atlas.RunTest', TAtlasTestsTextId.TestsRunHereCommand, RunAtCursor, TestsVisible),
    Command('Atlas.DebugTest', TAtlasTestsTextId.TestsDebugCommand, DebugAtCursor, TestDebugVisible),
    // Serien (#1782): N-mal, zufällige Reihenfolge, gleiche Reihenfolge erneut, abbrechen.
    Command('Atlas.RepeatTest', TAtlasTestsTextId.SeriesRepeatCommand, RepeatTest, SeriesVisible),
    Command('Atlas.ShuffleTests', TAtlasTestsTextId.SeriesShuffleCommand, ShuffleTests, SeriesVisible),
    Command('Atlas.ShuffleTestsAgain', TAtlasTestsTextId.SeriesShuffleAgainCommand, ShuffleTestsAgain,
      ShuffleAgainVisible),
    Command('Atlas.CancelTestSeries', TAtlasTestsTextId.SeriesCancelCommand, CancelSeries, CancelSeriesVisible),
    // Kontextmenü der Projektverwaltung (#1817); außerhalb unsichtbar.
    Command('Atlas.ProjectRunUnitTests', TAtlasTestsTextId.TestsProjectRunUnit,
      TAtlasGuard.Wrap(TAtlasFeature.Build, RunProjectUnitTests), ProjectUnitTestsVisible),
    // Assistent in Datei › Neu › Weitere (#1821); auch in der Palette.
    Described(Command('Atlas.NewTestUnitFor', TAtlasTestsTextId.TestsGalleryTestUnit,
      TAtlasGuard.Wrap(TAtlasFeature.Generate, NewTestUnitFor), nil),
      TAtlasTestsTextId.TestsGalleryTestUnitHint),
    // Test aus dem Debug-Halt (#1873): sichtbar mit tests.fromDebugStop und einem Modul, das den Halt liefert.
    Command(TestFromDebugCommand, TAtlasTestsTextId.TestsFromDebugCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Generate, TestFromDebugStop), TestFromDebugVisible),
    // Leckprüfung einrichten (#1880): Projektverwaltung und Palette, mit tests.leakSetup.
    Described(Command('Atlas.LeakSetup', TAtlasTestsTextId.LeakSetupCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Build, RunLeakSetup), LeakSetupVisible), TAtlasTestsTextId.LeakSetupHint),
    // Testabdeckung (#275): sichtbar mit tests.coverage; ausblenden nur mit geladenem Bericht.
    Command('Atlas.LoadTestCoverage', TAtlasTestsTextId.CoverageLoadCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Build, LoadCoverage), CoverageVisible),
    Command('Atlas.ClearTestCoverage', TAtlasTestsTextId.CoverageClearCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Build, ClearCoverage), CoverageClearVisible),
    // Mutationslauf (#1460): sichtbar mit tests.mutation und tests.run; abbrechen nur, solange er läuft.
    Command('Atlas.MutateMethod', TAtlasTestsTextId.MutationMethodCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Build, MutateMethod), MutationIdle),
    Command('Atlas.MutateUnit', TAtlasTestsTextId.MutationUnitCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Build, MutateUnit), MutationIdle),
    Command('Atlas.MutateChanged', TAtlasTestsTextId.MutationChangedCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Build, MutateChanged), MutationIdle),
    Command('Atlas.CancelMutation', TAtlasTestsTextId.MutationCancelCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Build, CancelMutation), MutationRunning)];
  // Testlisten (#2167): je Liste ein Befehl, mit tests.lists.
  Result := Result + ListCommands;
end;

procedure ApplyModuleSettings;
begin
  // tests.affectedBeforeCommit (#1353): pre-commit-Hook anlegen bzw. entfernen.
  if GTests <> nil then
  begin
    TAtlasIdeAffectedTests.ApplySettings;
  end;
  // tests.onSave aus (#1775): Warteschlange und Statuszeile weg.
  if GOnSave <> nil then
  begin
    GOnSave.ApplySettings;
  end;
  // tests.window (#1776), tests.lists (#2167) und editor.statusBar.tests (#1777).
  ApplyExplorerSettings;
end;

procedure ModuleThemeChanged;
begin
  ExplorerThemeChanged;
end;

function ModuleHooks: TAtlasTestsModuleHooks;
begin
  Result := Default(TAtlasTestsModuleHooks);
  Result.Commands := ModuleCommands;
  Result.Keys := ListKeys;
  Result.ApplySettings := ApplyModuleSettings;
  Result.ThemeChanged := ModuleThemeChanged;
end;

{ Läufe }

function CurrentTests: TAtlasIdeTests;
begin
  Result := GTests;
end;

function CurrentDebugger: TAtlasIdeTestDebugger;
begin
  Result := GDebugger;
end;

function CurrentOnSave: TAtlasIdeTestsOnSave;
begin
  Result := GOnSave;
end;

function RunsHooks: TAtlasTestsRunsHooks;
begin
  Result := Default(TAtlasTestsRunsHooks);
  Result.Tests := CurrentTests;
  Result.Debugger := CurrentDebugger;
  Result.OnSave := CurrentOnSave;
  Result.MutationBusy := MutationBusy;
  Result.WarnTestsOff := WarnTestsOff;
  Result.ExplorerFileSaved := ExplorerFileSaved;
end;

{ Anmeldung }

function Parts: TArray<IAtlasFeaturePart>;
begin
  // DUnitX-Tests (#69): nur im normalen Start und solange TestRun an ist; baut über den Läufer von Base.
  Result := [
    TAtlasFeaturePart.When('Tests',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.TestRun;
      end, TestsStarted, StartTests, StopTests),
    // Testabdeckung (#275): liest nur einen Bericht, baut und startet nichts; unabhängig von tests.run.
    CoveragePart];
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasTestsCompilerSection.ProvideIn(GScope);
  TAtlasTestsDebugSection.ProvideIn(GScope);
  TAtlasTestsEditorSection.ProvideIn(GScope);
end;

/// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
/// nicht passt.</summary>
function RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasTestsModule;
  mRef: IInterface;
  mRuns: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(TAtlasTestsModule.cModuleId, cAtlasCoreContractVersion, TAtlasVersion.cVersion,
    GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasTestsModule.Create(ModuleHooks);
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasFollowsTheme, mRef);
  GScope.Provide(IAtlasKeySource, mRef);
  mRuns := TAtlasTestsRuns.Create(RunsHooks) as IAtlasTestRunner;
  GScope.Provide(IAtlasBuildVerdictListener, mRuns);
  GScope.Provide(IAtlasFollowsSaves, mRuns);
  GScope.Provide(IAtlasTestRunner, mRuns);
  // Vertrag zwischen Modulen: Karte Tests (#763) und Schnellaktionen (#764) der Willkommensseite.
  GScope.Provide(IAtlasTestsSource, mRuns);
  // „Vergleichen“ (#1779) im Befund-Hover und auf der Kachel „Testergebnisse“.
  GScope.Provide(IAtlasTestValues, TAtlasTestsValues.Create(ResultCompare) as IAtlasTestValues);
  // Balken der Testabdeckung (#275) und Ergebnisse des Mutationslaufs (#1460) in der Rinne.
  ProvideGutterMarks(GScope);
  ProvideSettingsSections;
  Result := True;
end;

procedure UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, TAtlasTestsModule.cModuleId, HInstance, nil);
end;

initialization
  RegisterModule;

finalization
  UnregisterModule;

end.
