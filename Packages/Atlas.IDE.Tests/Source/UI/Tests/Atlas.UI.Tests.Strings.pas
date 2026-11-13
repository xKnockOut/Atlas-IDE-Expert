unit Atlas.UI.Tests.Strings;

// Oberflächentexte des Moduls Tests auf Deutsch und Englisch (#1455). Die Sprache
// bestimmt Base (`TAtlasStrings.Language`); jeder Aufruf liest sie neu, ein Sprachwechsel braucht
// daher keine eigene Meldung. Kerntexte bleiben in `Atlas.UI.Strings`.

interface

{$SCOPEDENUMS ON}

type
  TAtlasTestsTextId = (
    TestsRunCommand, TestsRunFailedCommand, TestsNoProject, TestsNoFailed, TestsBusy, TestsPlatform,
    TestsBuildRefused, TestsBuildFailed, TestsNoExe, TestsStarted, TestsTimedOut, TestsNoReport, TestsNoTests,
    TestsFinished, TestsProblem, TestsProblemValues, TestsLensRun, TestsLensRunFixture, TestsLensPassed,
    TestsLensFailed, TestsLensPartial, TestsLensRunning, TestsDebugCommand, TestsRunHereCommand, TestsLensDebug,
    TestsLensRunCase, TestsNoTestAtCursor, TestsDebugOff, TestsDebugBusy, TestsDebugRunning, TestsDebugStarted,
    TestsDebugBreak,
    TestsDebugFailed, TestsDebugNoProcess, TestsDebugFinished, TestsDebugKeptParameters, TestsChooseProject,
    TestsChoiceSaveFailed, TestsAffectedCommand, TestsAffectedRunning, TestsAffectedFound, TestsAffectedNone,
    TestsAffectedAll, TestsAffectedFailed, TestsAffectedOff, TestsAffectedNoProject, TestsAffectedHookForeign,
    TestsAffectedHookInstalled,
    WelcomeQuickReasonTestsOff, WelcomeQuickReasonNotOpened,
    SettingsCodeLensTests, SettingsTestRun, SettingsTestsBuildFirst, SettingsTestsAfterBuild, SettingsTestDebug,
    SettingsTestBreakAtStart, SettingsTestsAffected, SettingsTestsAffectedDepth, SettingsTestsAffectedBeforeCommit,
    TestsHookPurpose, TestsHookRemoval, TestsHookExitCodes, TestsHookNoTerminal, TestsHookAskRun,
    TestsHookAskCommit, TestsEditorMenuGroup,
    // Kontextmenü der Projektverwaltung (#1817).
    TestsProjectRunUnit, TestsProjectNoTestUnit,
    // Assistent der Objektgalerie (#1821).
    TestsGalleryTestUnit, TestsGalleryTestUnitHint, TestsGalleryChooseUnit, TestsGalleryNoUnits,
    // Veraltete Ergebnisse (#1770).
    TestsLensStale, TestsRunStaleCommand, TestsNoStale, SettingsTestsStale, SettingsTestsStaleUnits,
    // Marke „getestet von“ (#1778).
    CoveredByOne, CoveredByMany, CoveredByNone, CoveredByPassed, CoveredByFailed, CoveredByPartial, CoveredByListTitle,
    CoveredByIncomplete, SettingsCodeLensCoveredBy, SettingsTestsCoveredByDepth, SettingsTestsCoveredByPrivate);

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
  cTexts: array[TAtlasLanguage, TAtlasTestsTextId] of string = (
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
     '%s · %d/%d bestanden',
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
     'Vor dem Commit anbieten (Git-Hook pre-commit, nur Git)',
     'Von Atlas angelegt (tests.affectedBeforeCommit): nennt vor dem Commit die betroffenen Tests und führt sie im Terminal auf Wunsch aus.',
     'Entfernen: Einstellung ausschalten oder diese Datei löschen.',
     '0 = Liste (leer: keine betroffenen Tests), 2 = alle Tests nötig, sonst (3 = aus, Fehler) nichts tun.',
     'Ohne Terminal (Commit aus der IDE) bleibt es bei der Liste.',
     'Atlas: Betroffene Tests jetzt ausführen (Test-EXE ohne neuen Build)? [j/N] ',
     'Atlas: Tests fehlgeschlagen. Trotzdem committen? [j/N] ',
     'Tests',
     'Tests dieser Unit ausführen',
     'Tests: Keine Testunit mit DUnitX-Tests zu %s gefunden.',
     'DUnitX-Testunit zu Unit …',
     'Legt zu einer Unit der Projektgruppe eine Testunit mit Fixture und je öffentlicher Methode einem Test an ' +
     'und trägt sie ins Testprojekt ein; gibt es sie schon, öffnet Atlas sie.',
     'Unit, zu der die Testunit entsteht:',
     'Tests: Keine Unit in der Projektgruppe.',
     '%s (veraltet)',
     'Veraltete Tests ausführen',
     'Tests: Keine veralteten Tests (seit dem Lauf nichts geändert).',
     'Geänderte Tests als veraltet zeigen (grau „(veraltet)“, Befehl „Veraltete Tests ausführen“)',
     'Auch Änderungen in verwendeten Units des Testprojekts zählen',
     '1 Test',
     '%d Tests',
     'kein Test · Test anlegen',
     '%s · bestanden',
     '%s · fehlgeschlagen',
     '%s · %d/%d bestanden',
     'Getestet von (Klick: zum Test springen)',
     '%s (unvollständig)',
     'Marke „getestet von“ an Methoden normaler Units (Klick führt genau diese Tests aus)',
     'Ebenen vom Test bis zur Methode (1 bis 5):',
     'Auch private und geschützte Methoden'),
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
     '%s · %d/%d passed',
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
     'Offer before committing (Git pre-commit hook, Git only)',
     'Created by Atlas (tests.affectedBeforeCommit): lists the affected tests before the commit and runs them in the terminal on request.',
     'To remove: turn the setting off or delete this file.',
     '0 = list (empty: no affected tests), 2 = all tests needed, otherwise (3 = off, error) do nothing.',
     'Without a terminal (commit from the IDE) only the list is shown.',
     'Atlas: Run the affected tests now (test EXE without a new build)? [y/N] ',
     'Atlas: Tests failed. Commit anyway? [y/N] ',
     'Tests',
     'Run tests for this unit',
     'Tests: No test unit with DUnitX tests found for %s.',
     'DUnitX test unit for unit…',
     'Creates a test unit with a fixture and one test per public method for a unit of the project group and ' +
     'adds it to the test project; if it already exists, Atlas opens it.',
     'Unit to create the test unit for:',
     'Tests: No unit in the project group.',
     '%s (outdated)',
     'Run outdated tests',
     'Tests: No outdated tests (nothing changed since the run).',
     'Show changed tests as outdated (grey “(outdated)”, command “Run outdated tests”)',
     'Changes in used units of the test project count too',
     '1 test',
     '%d tests',
     'no test · create test',
     '%s · passed',
     '%s · failed',
     '%s · %d/%d passed',
     'Tested by (click: go to the test)',
     '%s (incomplete)',
     '“Tested by” mark on methods of normal units (a click runs exactly these tests)',
     'Levels from the test to the method (1 to 5):',
     'Private and protected methods too'));

{ TAtlasTestsStrings }

class function TAtlasTestsStrings.Text(AId: TAtlasTestsTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasTestsStrings.Fmt(AId: TAtlasTestsTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
