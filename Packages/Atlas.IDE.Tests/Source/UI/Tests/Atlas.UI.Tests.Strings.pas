unit Atlas.UI.Tests.Strings;

// Oberflächentexte des Moduls Tests auf Deutsch und Englisch (ADR 0017, #1455). Die Sprache
// bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu, ein Sprachwechsel braucht
// daher keine eigene Meldung. Kerntexte bleiben in `Atlas.UI.Strings`.

interface

{$SCOPEDENUMS ON}

type
  TAtlasTestsTextId = (
    TestsRunCommand, TestsRunFailedCommand, TestsNoProject, TestsNoFailed, TestsBusy, TestsPlatform,
    TestsBuildRefused, TestsBuildFailed, TestsNoExe, TestsStarted, TestsTimedOut, TestsNoReport, TestsNoTests,
    TestsFinished, TestsProblem, TestsProblemValues, TestsLensRun, TestsLensRunFixture, TestsLensPassed,
    TestsLensFailed, TestsLensRunning, TestsDebugCommand, TestsRunHereCommand, TestsLensDebug, TestsLensRunCase,
    TestsNoTestAtCursor, TestsDebugOff, TestsDebugBusy, TestsDebugRunning, TestsDebugStarted, TestsDebugBreak,
    TestsDebugFailed, TestsDebugNoProcess, TestsDebugFinished, TestsDebugKeptParameters, TestsChooseProject,
    TestsChoiceSaveFailed, TestsAffectedCommand, TestsAffectedRunning, TestsAffectedFound, TestsAffectedNone,
    TestsAffectedAll, TestsAffectedFailed, TestsAffectedOff, TestsAffectedNoProject, TestsAffectedHookForeign,
    TestsAffectedHookInstalled,
    WelcomeQuickReasonTestsOff, WelcomeQuickReasonNotOpened,
    SettingsCodeLensTests, SettingsTestRun, SettingsTestsBuildFirst, SettingsTestsAfterBuild, SettingsTestDebug,
    SettingsTestBreakAtStart, SettingsTestsAffected, SettingsTestsAffectedDepth, SettingsTestsAffectedBeforeCommit);

  TAtlasTestsStrings = class
  public
    class function Text(AId: TAtlasTestsTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasTestsTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  Texts: array[TAtlasLanguage, TAtlasTestsTextId] of string = (
    ('Tests ausführen',
     'Fehlgeschlagene Tests erneut ausführen',
     'Tests: Kein DUnitX-Testprojekt in der Projektgruppe (Hauptdatei mit DUnitX.TestFramework).',
     'Tests: Keine fehlgeschlagenen Tests von %s bekannt.',
     'Tests: Es läuft schon ein Testlauf.',
     'Tests: %s ist für %s eingestellt; Atlas startet nur Windows-Tests (Win32, Win64).',
     'Tests: %s nicht gebaut: %s',
     'Tests: Build von %s fehlgeschlagen, Tests nicht gestartet.',
     'Tests: Test-EXE von %s fehlt (%s); erst bauen oder „Vor den Tests bauen“ einschalten.',
     'Tests von %s laufen (%s, %s) …',
     'Tests: %s nach %d s abgebrochen (Zeitlimit).',
     'Tests: %s lieferte keinen Bericht (Exitcode %d). Letzte Ausgabe:',
     'Tests: %s enthält keine Tests (oder der Filter traf keinen).',
     'Tests %s: %d bestanden, %d fehlgeschlagen, %d Fehler, %d übersprungen (%s s)',
     'Test %s fehlgeschlagen: %s',
     'Test %s fehlgeschlagen: erwartet %s, erhalten %s',
     'Test ausführen',
     'Tests der Klasse ausführen',
     '%s · bestanden',
     '%s · fehlgeschlagen',
     'Tests laufen …',
     'Test am Cursor debuggen',
     'Test am Cursor ausführen',
     'Debuggen',
     'Fall ausführen',
     'Tests: Am Cursor steht kein DUnitX-Test (Testmethode, [TestCase] oder [TestFixture]).',
     'Tests: „Test debuggen“ ist ausgeschaltet (Tools › Optionen › Atlas › Debuggen).',
     'Tests: Es läuft schon ein Test im Debugger.',
     'Tests: Der Debugger läuft schon; erst beenden.',
     'Tests: %s startet %s im Debugger (%s, %s) …',
     'Tests: Einmaliger Haltepunkt in Zeile %d; Atlas entfernt ihn nach dem Halt.',
     'Tests: %s ließ sich nicht im Debugger starten: %s',
     'Tests: Die Test-EXE von %s ist nicht gestartet; Startparameter und aktives Projekt zurückgestellt.',
     'Tests: Debuggen von %s beendet; aktives Projekt und Startparameter wie vorher.',
     'Tests: Die Startparameter von %s wurden während des Laufs geändert und bleiben, wie sie sind.',
     'Testprojekt wählen (Atlas merkt sich die Wahl)',
     'Tests: Die Wahl des Testprojekts ließ sich nicht speichern.',
     'Betroffene Tests ausführen',
     'Atlas ermittelt die betroffenen Tests …',
     'Betroffene Tests gegenüber %s (Tiefe %d): %d',
     'Keine betroffenen Tests gegenüber %s.',
     'Alle Tests nötig: %s',
     'Betroffene Tests: %s',
     'Betroffene Tests sind ausgeschaltet (tests.affected).',
     'Betroffene Tests: Kein Projekt geöffnet.',
     'Betroffene Tests vor dem Commit: In %s liegt schon ein fremder pre-commit-Hook; Atlas lässt ihn stehen.',
     'Betroffene Tests vor dem Commit: pre-commit-Hook in %s angelegt.',
    '„Tests ausführen“ ist ausgeschaltet',
    'Projekt nicht geöffnet',
     'Code Lens „Test ausführen“ an [TestFixture] und [Test]',
     'DUnitX-Tests ausführen (Befehle, Code Lens, Fehlschläge als Probleme)',
     'Vor den Tests bauen (sonst läuft die vorhandene Test-EXE)',
     'Tests nach erfolgreichem Build automatisch ausführen',
     'Test debuggen (Befehl „Test am Cursor debuggen“, Kontextmenü, Marke „Debuggen“ der Code Lens)',
     'Beim Test-Debuggen am Anfang der Methode anhalten (einmaliger Haltepunkt)',
     'Befehl „Betroffene Tests ausführen“: nur die Tests, die die Änderungen gegenüber main bzw. BASE erreichen',
     'Ebenen von der Änderung bis zum Test (1 bis 5):',
     'Vor dem Commit anbieten (Git-Hook pre-commit, nur Git)'),
    ('Run tests',
     'Re-run failed tests',
     'Tests: No DUnitX test project in the project group (main file using DUnitX.TestFramework).',
     'Tests: No failed tests of %s known.',
     'Tests: A test run is already in progress.',
     'Tests: %s targets %s; Atlas only starts Windows tests (Win32, Win64).',
     'Tests: %s not built: %s',
     'Tests: Build of %s failed, tests not started.',
     'Tests: Test EXE of %s is missing (%s); build first or turn on “Build before running tests”.',
     'Running tests of %s (%s, %s) …',
     'Tests: %s stopped after %d s (time limit).',
     'Tests: %s produced no report (exit code %d). Last output:',
     'Tests: %s contains no tests (or the filter matched none).',
     'Tests %s: %d passed, %d failed, %d errors, %d skipped (%s s)',
     'Test %s failed: %s',
     'Test %s failed: expected %s, actual %s',
     'Run test',
     'Run tests of class',
     '%s · passed',
     '%s · failed',
     'Tests running …',
     'Debug test at cursor',
     'Run test at cursor',
     'Debug',
     'Run case',
     'Tests: There is no DUnitX test at the cursor (test method, [TestCase] or [TestFixture]).',
     'Tests: “Debug test” is switched off (Tools › Options › Atlas › Debugging).',
     'Tests: A test is already running in the debugger.',
     'Tests: The debugger is already running; stop it first.',
     'Tests: %s starts %s in the debugger (%s, %s) …',
     'Tests: One-time breakpoint at line %d; Atlas removes it after the stop.',
     'Tests: %s could not be started in the debugger: %s',
     'Tests: The test EXE of %s did not start; run parameters and active project restored.',
     'Tests: Debugging %s finished; active project and run parameters as before.',
     'Tests: The run parameters of %s were changed during the run and stay as they are.',
     'Choose test project (Atlas remembers the choice)',
     'Tests: The choice of the test project could not be saved.',
     'Run affected tests',
     'Atlas is determining the affected tests …',
     'Affected tests against %s (depth %d): %d',
     'No affected tests against %s.',
     'All tests needed: %s',
     'Affected tests: %s',
     'Affected tests are switched off (tests.affected).',
     'Affected tests: no project open.',
     'Affected tests before commit: %s already holds a foreign pre-commit hook; Atlas leaves it alone.',
     'Affected tests before commit: pre-commit hook created in %s.',
    '“Run tests” is switched off',
    'Project not opened',
     'Code lens “Run test” at [TestFixture] and [Test]',
     'Run DUnitX tests (commands, code lens, failures as problems)',
     'Build before running tests (otherwise the existing test EXE runs)',
     'Run tests automatically after a successful build',
     'Debug test (command “Debug test at cursor”, context menu, code lens mark “Debug”)',
     'Stop at the start of the method when debugging a test (one-time breakpoint)',
     'Command “Run affected tests”: only the tests reached by the changes against main or BASE',
     'Levels from the change to the test (1 to 5):',
     'Offer before committing (Git pre-commit hook, Git only)'));

{ TAtlasTestsStrings }

class function TAtlasTestsStrings.Text(AId: TAtlasTestsTextId): string;
begin
  Result := Texts[TAtlasStrings.Language, AId];
end;

class function TAtlasTestsStrings.Fmt(AId: TAtlasTestsTextId; const AArgs: array of const): string;
begin
  Result := Format(Texts[TAtlasStrings.Language, AId], AArgs);
end;

end.
