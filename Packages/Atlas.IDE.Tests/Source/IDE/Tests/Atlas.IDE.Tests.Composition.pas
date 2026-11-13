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
// - die Schicht der Testabdeckung in der Rinne (#275, IAtlasGutterLayer) mit den Befehlen „Testabdeckung laden …“
//   und „Testabdeckung ausblenden“; ihr Zustand ist ein eigener Teil der Feature-Tabelle (läuft auch ohne
//   tests.run, solange tests.coverage an ist),
// - Hörer für Einstellungen und bewertete Builds (Tests nach dem Build) und für
//   gespeicherte Dateien (betroffene Tests im Hintergrund, #1775),
// - IAtlasTestRunner (Base: Auswirkungsanalyse #1120, Willkommensseite) und
//   IAtlasTestsSource (Atlas.IDE.Contracts.Tests, Willkommensseite); das Ende eines
//   Laufs schreibt das Modul in die Projekt-Zusammenfassung von Base
//   (TAtlasIdeProjectSummaries, #69) und meldet es jedem IAtlasTestsListener,
// - IAtlasTestValues (#1779): „Vergleichen“ im Befund-Hover von Base und auf
//   der Kachel „Testergebnisse“ der Willkommensseite.
// Gebaut wird über den Läufer der Builds auf Auftrag der Build-Pipeline
// (IAtlasBuildJobs aus Atlas.IDE.Contracts.BuildPipeline, ohne Modul nicht), die
// Probleme gehen an das Problemfenster von Base; die fehlgeschlagenen Tests des
// letzten Laufs liest das Modul aus den Projektdateien (TAtlasProjectSummaries),
// auch ohne Willkommensseite.
// Diese Haken stehen in Atlas.IDE.Tests.Composition.Hooks.
// Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Verdict,
  Atlas.IDE.Contracts.Tests;

type
  TAtlasTestsModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasAppliesSettings, IAtlasBuildVerdictListener, IAtlasTestRunner, IAtlasTestsSource, IAtlasFollowsSaves,
    IAtlasTestValues, IAtlasFollowsTheme, IAtlasKeySource)
  public const
    cModuleId = 'atlas.tests';
    cSwitch = 'tests';
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
    function Keys: TArray<TAtlasModuleKey>;
    procedure ApplySettings;
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
    procedure RunTests(const AFileName: string; const ATests: TArray<string>);
    function RunProject(const ATestProject: string; out AReason: string): Boolean;
    function DebugByName(const AProject, AFullName: string; out AReason: string): Boolean;
    function LocateByName(const AProject, AFullName: string; out AFileName: string; out ALine: Integer): Boolean;
    function Busy: Boolean;
    procedure FileSaved(const AFileName: string);
    function HasValuesAt(ALine: Integer): Boolean;
    procedure CompareAt(ALine: Integer);
    function HasValues(const AFullName: string): Boolean;
    procedure Compare(const AFullName: string);
    procedure ThemeChanged;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.UI.Tests.SettingsSection,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Adapters.ProcessRunner,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tests.Output,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.OnSave,
  Atlas.IDE.Tests.Composition.Hooks,
  Atlas.IDE.Tests.Debug,
  Atlas.IDE.Tests.Lens,
  Atlas.IDE.Tests.CoveredBy,
  Atlas.IDE.Tests.Stale,
  Atlas.IDE.Tests.Compare,
  Atlas.IDE.Tests.ApprovalFiles,
  Atlas.IDE.Tests.Slowest,
  Atlas.IDE.Tests.Composition.Cases,
  Atlas.IDE.Tests.Affected,
  Atlas.IDE.Tests.UnitCommands,
  Atlas.IDE.Tests.Explorer,
  Atlas.IDE.Tests.Series,
  Atlas.IDE.Tests.Flaky,
  Atlas.IDE.Tests.StatusField,
  Atlas.IDE.Tests.Coverage,
  Atlas.UI.Tests.Strings;

var
  GScope: IAtlasModuleScope;
  GOutput: TAtlasIdeTestsOutput;
  GTests: TAtlasIdeTests;
  GOnSave: TAtlasIdeTestsOnSave;
  GDebugger: TAtlasIdeTestDebugger;
  GLens: TAtlasIdeTestsLens;
  GCoveredBy: TAtlasIdeCoveredByLens;
  GStale: TAtlasIdeStaleTests;
  GCompare: TAtlasIdeTestCompare;
  GSlowest: TAtlasIdeTestSlowest;
  GExplorer: TAtlasIdeTestExplorer;
  /// <summary>Serien (#1782) und ihr Abbruchwunsch, den der Prozessläufer liest; GStopRef hält ihn.</summary>
  GSeries: TAtlasIdeTestSeries;
  GStop: TAtlasIdeTestStop;
  GStopRef: IInterface;
  GFlaky: TAtlasIdeFlakyTests;
  GLists: TAtlasIdeTestLists;
  GStatusField: TAtlasIdeTestStatusField;

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
  Result := Default(TAtlasTestCompareHooks);
  Result.CanCompare := GCompare.CanCompare;
  Result.Show := GCompare.Show;
  // Vergleichsdateien (#1881): „Abweichung · Vergleich“ statt „Vergleichen“.
  Result.Caption := GCompare.CaptionOf;
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
  // Veraltete Ergebnisse (#1770): Stand je Test nach jedem Lauf.
  GStale := TAtlasIdeStaleTests.Create(GTests);
  // Erwartet und erhalten vergleichen (#1779): Fehlschläge mit Werten; reicht den Lauf an die Stände weiter.
  GCompare := TAtlasIdeTestCompare.Create(GTests, GStale.Remember);
  // Langsamste Tests (#1772): Ergebnisse des Testprojekts; reicht den Lauf an den Vergleich weiter.
  GSlowest := TAtlasIdeTestSlowest.Create(GTests, GCompare.Remember);
  // Einzelner Test ausführen bzw. debuggen (#585), auch aus dem Kontextmenü und der Lens.
  GDebugger := TAtlasIdeTestDebugger.Create(GTests);
  // Tests N-mal bzw. in zufälliger Reihenfolge (#1782): Läufe im Hintergrund über den Läufer.
  GSeries := TAtlasIdeTestSeries.Create(GTests, GOutput, GStop);
  // Wackelnde Tests (#1773): Verlauf je Test; reicht den Lauf an die langsamsten Tests weiter.
  GFlaky := TAtlasIdeFlakyTests.Create(GTests, GSlowest.Remember);
  // Fenster „Atlas-Tests“ (#1776): Ergebnisse je Testprojekt; reicht den Lauf an die wackelnden Tests weiter.
  // Testlisten (#2167): vor dem Fenster, das sie über TAtlasIdeTestLists.Instance findet, und nach ihm frei.
  GLists := TAtlasIdeTestLists.Create(GTests);
  GExplorer := TAtlasIdeTestExplorer.Create(GTests, GDebugger, GSeries, GFlaky.QueriesWith(GStale.StaleIn),
    GFlaky.Remember);
  GTests.OnReported := GExplorer.Remember;
  GStatusField := TAtlasIdeTestStatusField.Create(GTests, GExplorer);
  GLens := TAtlasIdeTestsLens.Create(GTests, GDebugger, GFlaky.QueriesWith(GStale.StaleIn), CompareHooks);
  // Marke „getestet von“ an Methoden normaler Units (#1778).
  GCoveredBy := TAtlasIdeCoveredByLens.Create(GTests, ModuleScope, GStale.StaleIn);
  // TestCase-Tabelle (#1879): Befehl und Marke „Tabelle“ der Lens; Grenzfälle (#2173) vorn in OnReported.
  // Ungetestete Methoden des Projekts (#1783) ebenda.
  StartCases(GScope, GTests, GDebugger, GOutput, ModuleScope);
  GLens.OnTable := OpenCaseTable;
  TAtlasIdeAffectedTests.Install(AffectedHooks);
  // Betroffene Tests beim Speichern (#1775): im Hintergrund über den Läufer.
  GOnSave := TAtlasIdeTestsOnSave.Create(GTests, GOutput);
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
  // vor allen.
  FreeAndNil(GStatusField);
  FreeAndNil(GExplorer);
  FreeAndNil(GLists);
  FreeAndNil(GCoveredBy);
  FreeAndNil(GLens);
  // Serie (#1782) nach Fenster und Lens, die auf sie zeigen; vor dem Läufer, dessen Ende sie erwartet.
  FreeAndNil(GSeries);
  StopCases(GTests);
  FreeAndNil(GDebugger);
  // Wackelnde Tests (#1773) nach Fenster und Lens, die sie abfragen.
  FreeAndNil(GFlaky);
  FreeAndNil(GSlowest);
  FreeAndNil(GCompare);
  FreeAndNil(GStale);
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

{ Veraltete Tests (#1770) }

function StaleTestsVisible: Boolean;
begin
  Result := TestsVisible and TAtlasIdeSettings.Current.TestsStale;
end;

procedure RunStale;
begin
  if GStale <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GStale.Run);
  end;
end;

{ Erwartet und erhalten vergleichen (#1779) }

function CompareVisible: Boolean;
begin
  Result := TestsVisible and TAtlasIdeSettings.Current.TestsCompare;
end;

procedure CompareValues;
begin
  if GCompare <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GCompare.Run);
  end;
end;

{ Testabdeckung (#275) }

function CoverageVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TestCoverage and TAtlasIdeTestCoverage.Started;
end;

function CoverageClearVisible: Boolean;
begin
  Result := CoverageVisible and TAtlasIdeTestCoverage.Loaded;
end;

{ Langsamste Tests (#1772) }

function SlowestVisible: Boolean;
begin
  Result := TestsVisible and TAtlasIdeSettings.Current.TestsShowDuration;
end;

procedure ShowSlowest;
begin
  if GSlowest <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, GSlowest.Run);
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

{ Vergleichsdateien (#1881) }

function ApprovalFilesVisible: Boolean;
begin
  Result := TestsVisible and TAtlasIdeSettings.Current.TestsApprovalFiles;
end;

procedure CleanApprovalFiles;
var
  mProject: string;
begin
  // Testprojekt des letzten Laufs; ohne Lauf das aktive Projekt.
  mProject := '';
  if GCompare <> nil then
  begin
    mProject := GCompare.LastProject;
  end;
  if GTests <> nil then
  begin
    TAtlasIdeApprovalFiles.Clean(GTests, mProject);
  end;
end;

{ Fenster „Atlas-Tests“ (#1776) }

/// <summary>Fenster „Atlas-Tests“ mit allen Tests.</summary>
procedure ShowAll;
begin
  GExplorer.Show(False);
end;

/// <summary>Fenster „Atlas-Tests“ nur mit wackelnden Tests (#1773).</summary>
procedure ShowFlakyOnly;
begin
  GExplorer.Show(True);
end;

function ExplorerVisible: Boolean;
begin
  Result := TestsVisible and TAtlasIdeTestExplorer.Wanted and (GExplorer <> nil);
end;

procedure ShowExplorer;
begin
  if GExplorer <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, ShowAll);
  end;
end;

{ Wackelnde Tests (#1773) }

function FlakyVisible: Boolean;
begin
  Result := ExplorerVisible and TAtlasIdeSettings.Current.TestsFlaky;
end;

procedure ShowFlaky;
begin
  if GExplorer <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, ShowFlakyOnly);
  end;
end;

{ Projektverwaltung (#1817) }

function ProjectUnitTestsVisible: Boolean;
begin
  Result := TestsVisible and TAtlasIdeTestUnitCommands.HasProjectUnits;
end;

procedure RunProjectUnitTests;
begin
  TAtlasIdeTestUnitCommands.RunProjectUnits(GTests);
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

{ Testlisten (#2167) }

/// <summary>Befehl „Testliste ausführen: AName“; eigene Routine, damit jeder Befehl seinen Namen fängt.</summary>
function ListCommand(const AName: string): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := 'Atlas.RunTestList:' + AName;
  Result.Caption := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.ListsRunCommand, [AName]);
  Result.Description := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsRunCommandHint);
  Result.Run :=
    procedure
    begin
      if GLists <> nil then
      begin
        TAtlasGuard.Run(TAtlasFeature.Build,
          procedure
          begin
            GLists.RunByName(AName);
          end);
      end;
    end;
end;

/// <summary>Je Testliste des gewählten Testprojekts ein Befehl der Palette.</summary>
function ListCommands: TArray<TAtlasModuleCommand>;
var
  mName: string;
begin
  Result := nil;
  if (GLists = nil) or not TestsVisible then
  begin
    Exit;
  end;
  for mName in GLists.Names do
  begin
    Result := Result + [ListCommand(mName)];
  end;
end;

/// <summary>Zuletzt benutzte Testliste ausführen; False ohne eine (die Taste geht dann an die IDE).</summary>
function RunLastList: Boolean;
begin
  Result := (GLists <> nil) and GLists.RunLast;
end;

{ TAtlasTestsModule }

function TAtlasTestsModule.Info: TAtlasModuleInfo;
begin
  // Der Läufer baut und startet Programme: nur im normalen Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Tests', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Normal, cSwitch);
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
      Guarded(TAtlasFeature.Build, CleanApprovalFiles), ApprovalFilesVisible),
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
      Guarded(TAtlasFeature.Build, RunProjectUnitTests), ProjectUnitTestsVisible),
    // Assistent in Datei › Neu › Weitere (#1821); auch in der Palette.
    Described(Command('Atlas.NewTestUnitFor', TAtlasTestsTextId.TestsGalleryTestUnit,
      Guarded(TAtlasFeature.Generate, TAtlasIdeTestUnitCommands.NewTestUnitFor), nil),
      TAtlasTestsTextId.TestsGalleryTestUnitHint),
    // Test aus dem Debug-Halt (#1873): sichtbar mit tests.fromDebugStop und einem Modul, das den Halt liefert.
    Command(TestFromDebugCommand, TAtlasTestsTextId.TestsFromDebugCommand,
      Guarded(TAtlasFeature.Generate, TestFromDebugStop), TestFromDebugVisible),
    // Leckprüfung einrichten (#1880): Projektverwaltung und Palette, mit tests.leakSetup.
    Described(Command('Atlas.LeakSetup', TAtlasTestsTextId.LeakSetupCommand,
      Guarded(TAtlasFeature.Build, RunLeakSetup), LeakSetupVisible), TAtlasTestsTextId.LeakSetupHint),
    // Testabdeckung (#275): sichtbar mit tests.coverage; ausblenden nur mit geladenem Bericht.
    Command('Atlas.LoadTestCoverage', TAtlasTestsTextId.CoverageLoadCommand,
      Guarded(TAtlasFeature.Build, TAtlasIdeTestCoverage.Choose), CoverageVisible),
    Command('Atlas.ClearTestCoverage', TAtlasTestsTextId.CoverageClearCommand,
      Guarded(TAtlasFeature.Build, TAtlasIdeTestCoverage.Clear), CoverageClearVisible)];
  // Testlisten (#2167): je Liste ein Befehl, mit tests.lists.
  Result := Result + ListCommands;
end;

function TAtlasTestsModule.Keys: TArray<TAtlasModuleKey>;
var
  mKey: TAtlasModuleKey;
begin
  Result := nil;
  // Zuletzt benutzte Testliste (#2167): ohne Liste geht die Taste an die IDE weiter.
  if not TAtlasIdeTestLists.Wanted or (TAtlasIdeSettings.Current.TestsListsRunKey = 0) then
  begin
    Exit;
  end;
  mKey := Default(TAtlasModuleKey);
  mKey.Id := 'Atlas.RunLastTestList';
  mKey.Caption := TAtlasTestsStrings.Text(TAtlasTestsTextId.ListsRunLast);
  mKey.Key := TAtlasIdeSettings.Current.TestsListsRunKey;
  mKey.Attempt := RunLastList;
  Result := [mKey];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

/// <summary>Ist die Datei eine DUnitX-Testunit?</summary>
function InTestUnit(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := AContext.TestUnit;
end;

/// <summary>Läuft eine Debug-Sitzung?</summary>
function WhileDebugging(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := AContext.Debugging;
end;

/// <summary>Eintrag im Untermenü „Tests“ von Atlas im Kontextmenü des Editors; nur in einer Testunit.</summary>
function ContextEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.EditorContext);
  Result.Section := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsEditorMenuGroup);
  Result.Group := 'tests';
  Result.When := InTestUnit;
end;

/// <summary>Eintrag im Untermenü „Tests“ des Kontextmenüs, nur beim Debuggen (#1873).</summary>
function DebugContextEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := ContextEntry(ACommandId);
  Result.When := WhileDebugging;
end;

/// <summary>Ist die Datei eine Unit (.pas), aber keine Testunit?</summary>
function InCodeUnit(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := not AContext.TestUnit and SameText(ExtractFileExt(AContext.FileName), '.pas');
end;

/// <summary>Wie ContextEntry, aber nur außerhalb von Testunits.</summary>
function CodeContextEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := ContextEntry(ACommandId);
  Result.When := InCodeUnit;
end;

function TAtlasTestsModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [
    // Fenster „Atlas-Tests“ (#1776) unter Ansicht › Atlas und im Atlas-Menü.
    MenuEntry('Atlas.TestExplorer', TAtlasMenuPlace.ViewMenu),
    MenuEntry('Atlas.TestExplorer', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.RunAffectedTests', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.RunStaleTests', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.CompareTestValues', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.LoadTestCoverage', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.ClearTestCoverage', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.ShowSlowestTests', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.ShowFlakyTests', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.CleanApprovalFiles', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.ListUntestedMethods', TAtlasMenuPlace.AtlasMenu),
    // Test am Cursor (#585) im Untermenü „Atlas“ des Editors.
    ContextEntry('Atlas.RunTest'),
    ContextEntry('Atlas.DebugTest'),
    ContextEntry('Atlas.RepeatTest'),
    ContextEntry('Atlas.ShuffleTests'),
    ContextEntry('Atlas.ShuffleTestsAgain'),
    ContextEntry('Atlas.CancelTestSeries'),
    DebugContextEntry(TestFromDebugCommand),
    ContextEntry('Atlas.CompareTestValues'),
    ContextEntry('Atlas.EditTestCases'),
    // Grenzfälle (#2173) an Routinen normaler Units.
    CodeContextEntry('Atlas.SuggestBoundaryCases'),
    MenuEntry('-', TAtlasMenuPlace.ProjectContext),
    MenuEntry('Atlas.ProjectRunUnitTests', TAtlasMenuPlace.ProjectContext),
    MenuEntry('Atlas.LeakSetup', TAtlasMenuPlace.ProjectContext),
    MenuEntry('Atlas.NewTestUnitFor', TAtlasMenuPlace.Gallery)];
end;

procedure TAtlasTestsModule.ApplySettings;
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
  // tests.window aus (#1776): Fenster weg.
  if GExplorer <> nil then
  begin
    GExplorer.ApplySettings;
  end;
  // tests.lists (#2167): Reiter zeigen bzw. verbergen.
  if GLists <> nil then
  begin
    GLists.ApplySettings;
  end;
  // editor.statusBar.tests (#1777): Feld neu bzw. weg.
  if GStatusField <> nil then
  begin
    GStatusField.ApplySettings;
  end;
end;

procedure TAtlasTestsModule.ThemeChanged;
begin
  if GExplorer <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build, TAtlasIdeTestExplorer.ThemeChanged);
  end;
end;

procedure TAtlasTestsModule.BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
begin
  // Tests nach dem Build (#69), nach derselben Bewertung wie Zusammenfassung und Benachrichtigung (#530).
  if GTests <> nil then
  begin
    GTests.BuildFinished(AProject, AVerdict.Effective);
  end;
end;

procedure TAtlasTestsModule.RunTests(const AFileName: string; const ATests: TArray<string>);
begin
  if GTests <> nil then
  begin
    GTests.RunTests(AFileName, ATests, False);
  end
  else
  begin
    WarnTestsOff;
  end;
end;

function TAtlasTestsModule.RunProject(const ATestProject: string; out AReason: string): Boolean;
begin
  if GTests = nil then
  begin
    AReason := TAtlasTestsStrings.Text(TAtlasTestsTextId.WelcomeQuickReasonTestsOff);
    Exit(False);
  end;
  Result := GTests.RunProject(ATestProject, AReason);
end;

function TAtlasTestsModule.DebugByName(const AProject, AFullName: string; out AReason: string): Boolean;
begin
  AReason := '';
  Result := False;
  if GDebugger <> nil then
  begin
    Result := GDebugger.DebugByName(AProject, AFullName, AReason);
  end;
end;

function TAtlasTestsModule.LocateByName(const AProject, AFullName: string; out AFileName: string;
  out ALine: Integer): Boolean;
begin
  Result := TAtlasIdeTestDebugger.LocateByName(AProject, AFullName, AFileName, ALine);
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasTestsCompilerSection.ProvideIn(GScope);
  TAtlasTestsDebugSection.ProvideIn(GScope);
  TAtlasTestsEditorSection.ProvideIn(GScope);
end;

procedure TAtlasTestsModule.FileSaved(const AFileName: string);
begin
  // Fenster „Atlas-Tests“ (#1776): gespeicherte Testunit neu lesen.
  if GExplorer <> nil then
  begin
    GExplorer.FileSaved(AFileName);
  end;
  // Betroffene Tests beim Speichern (#1775).
  if GOnSave <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.Build,
      procedure
      begin
        GOnSave.FileSaved(AFileName);
      end);
  end;
end;

function TAtlasTestsModule.Busy: Boolean;
begin
  Result := (GTests <> nil) and GTests.Busy;
end;

function TAtlasTestsModule.HasValuesAt(ALine: Integer): Boolean;
begin
  Result := (GCompare <> nil) and GCompare.HasValuesAt(ALine);
end;

procedure TAtlasTestsModule.CompareAt(ALine: Integer);
begin
  if GCompare <> nil then
  begin
    GCompare.CompareAt(ALine);
  end;
end;

function TAtlasTestsModule.HasValues(const AFullName: string): Boolean;
begin
  Result := (GCompare <> nil) and GCompare.HasValues(AFullName);
end;

procedure TAtlasTestsModule.Compare(const AFullName: string);
begin
  if GCompare <> nil then
  begin
    GCompare.CompareTest(AFullName);
  end;
end;

class function TAtlasTestsModule.Parts: TArray<IAtlasFeaturePart>;
begin
  // DUnitX-Tests (#69): nur im normalen Start und solange TestRun an ist; baut über den Läufer von Base.
  Result := [
    TAtlasFeaturePart.When('Tests',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.TestRun;
      end, TestsStarted, StartTests, StopTests),
    // Testabdeckung (#275): liest nur einen Bericht, baut und startet nichts; unabhängig von tests.run.
    TAtlasFeaturePart.When('TestCoverage',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.TestCoverage;
      end, TAtlasIdeTestCoverage.Started, TAtlasIdeTestCoverage.Start, TAtlasIdeTestCoverage.Stop)];
end;

class function TAtlasTestsModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasTestsModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(cModuleId, cAtlasCoreContractVersion, GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasTestsModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasBuildVerdictListener, mRef);
  GScope.Provide(IAtlasFollowsSaves, mRef);
  GScope.Provide(IAtlasFollowsTheme, mRef);
  GScope.Provide(IAtlasKeySource, mRef);
  GScope.Provide(IAtlasTestRunner, mRef);
  // Vertrag zwischen Modulen: Karte Tests (#763) und Schnellaktionen (#764) der Willkommensseite.
  GScope.Provide(IAtlasTestsSource, mRef);
  // „Vergleichen“ (#1779) im Befund-Hover und auf der Kachel „Testergebnisse“.
  GScope.Provide(IAtlasTestValues, mRef);
  // Balken der Testabdeckung in der Rinne (#275).
  TAtlasIdeTestCoverage.ProvideIn(GScope);
  ProvideSettingsSections;
  Result := True;
end;

class procedure TAtlasTestsModule.UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, cModuleId, HInstance, nil);
end;

initialization
  TAtlasTestsModule.RegisterModule;

finalization
  TAtlasTestsModule.UnregisterModule;

end.
