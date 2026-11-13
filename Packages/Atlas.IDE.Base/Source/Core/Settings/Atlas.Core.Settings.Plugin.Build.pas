unit Atlas.Core.Settings.Plugin.Build;

// Einstellungen des IDE-Plugins, Bereich Build (build.*, tests.*, taskRunner.*) (#227):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

const
  cMinCheckDelay = 500;
  cMaxCheckDelay = 10000;
  cMinCheckMax = 200;
  cMaxCheckMax = 20000;
  /// <summary>Grenzen für tests.affectedDepth (#1353).</summary>
  cMinTestsAffectedDepth = 1;
  cMaxTestsAffectedDepth = 5;
  cDefaultTestsAffectedDepth = 3;
  /// <summary>Grenzen für tests.coveredBy.depth (#1778).</summary>
  cMinTestsCoveredByDepth = 1;
  cMaxTestsCoveredByDepth = 5;
  /// <summary>Grenzen für tests.untested.warnPercent (#1783).</summary>
  cMinTestsUntestedWarnPercent = 0;
  cMaxTestsUntestedWarnPercent = 100;
  cDefaultTestsUntestedWarnPercent = 50;
  /// <summary>Grenzen für tests.onSave.max (#1775).</summary>
  cMinTestsOnSaveMax = 1;
  cMaxTestsOnSaveMax = 1000;
  cDefaultTestsOnSaveMax = 50;
  /// <summary>Grenzen und Vorgabe für tests.slowMs (#1772).</summary>
  cMinTestsSlowMs = 50;
  cMaxTestsSlowMs = 60000;
  cDefaultTestsSlowMs = 500;
  /// <summary>Taste „Zuletzt benutzte Testliste ausführen“ (#2167): Strg+Alt+R.</summary>
  cDefaultTestsListsRunKey = $C052;

type
  /// <summary>Plugin-Einstellungen: Compiler, Build, Tests und Aufgaben.</summary>
  TAtlasPluginBuildSettings = record
    /// <summary>Syntaxprüfung des Compilers nach dem Speichern (#548). Schließt CompileOnSave aus: Die
    /// Optionsseite bietet eine Auswahl „Nach dem Speichern“ (aus, Syntaxprüfung, Kompilieren).</summary>
    CheckOnSave: Boolean;
    /// <summary>Der Server kompiliert nach dem Speichern im Hintergrund (compiler.onSave, #40).</summary>
    CompileOnSave: Boolean;
    /// <summary>Wartezeit nach dem letzten Speichern.</summary>
    CheckOnSaveDelayMs: Integer;
    /// <summary>Höchstdauer einer Prüfung; darüber nur noch von Hand (Strg+Alt+F9).</summary>
    CheckOnSaveMaxMs: Integer;
    /// <summary>Ein KI-Assistent darf über das MCP-Werkzeug build_project offene Projekte in dieser IDE bauen (#261),
    /// z. B. in der Starter Edition ohne Kommandozeilen-Compiler.</summary>
    McpBuild: Boolean;
    /// <summary>Modul-Schalter assistants.enabled (#1888): KI-Assistenten nehmen Aufträge in der IDE an (Builds,
    /// Schreiben in offene Dateien); aus = kein Eingang, der MCP-Server meldet „nicht angenommen“.</summary>
    AssistantsEnabled: Boolean;
    /// <summary>assistants.edit (#1888, #397): KI-Assistenten schreiben in offene Dateien über den Eingang des
    /// Plugins; aus = der MCP-Server bekommt „nicht angenommen“ und fasst offene Dateien nicht an.</summary>
    AssistantsEdit: Boolean;
    /// <summary>Beim Öffnen eines Projekts oder einer Projektgruppe einmal bauen (build.onOpen): sobald die IDE
    /// ruhig ist, über den Compiler der IDE (mit eingeschalteter Hintergrundcompilierung der IDE ohne zu
    /// blockieren). Aus = kein Bau beim Öffnen.</summary>
    BuildOnOpen: Boolean;
    /// <summary>Art des Baus beim Öffnen (build.onOpenKind): check (Syntaxprüfung), make (Compilieren) oder build
    /// (Erzeugen).</summary>
    BuildOnOpenKind: string;
    /// <summary>Bei einer Projektgruppe alle Projekte (all) oder nur das aktive (active) (build.onOpenScope).
    /// </summary>
    BuildOnOpenScope: string;
    /// <summary>Wartezeit nach dem Öffnen und nach der letzten Eingabe (build.onOpenDelayMs).</summary>
    BuildOnOpenDelayMs: Integer;
    /// <summary>Projekte, die beim Öffnen nicht gebaut werden (build.onOpenExclude), Namen ohne Endung, durch
    /// Komma getrennt, z. B. ein in der IDE installiertes Package.</summary>
    BuildOnOpenExclude: string;
    /// <summary>Konfiguration für den Lauf beim Öffnen (build.onOpenConfig, #1293), z. B. Debug; '' = wie im
    /// Projekt. Kennt ein Projekt sie nicht, gilt dort die Einstellung des Projekts.</summary>
    BuildOnOpenConfig: string;
    /// <summary>Zielplattform für den Lauf beim Öffnen (build.onOpenPlatform, #1293), z. B. Win64; '' = wie im
    /// Projekt. Ist sie in einem Projekt nicht aktiviert, gilt dort die Einstellung des Projekts.</summary>
    BuildOnOpenPlatform: string;
    /// <summary>Laufendes Programm vor dem Build beenden (build.stopRunningProgram, #551): ask (Rückfrage), always
    /// (ohne Rückfrage beenden) oder never (nichts tun). Programme im Debugger der IDE bleiben unberührt.</summary>
    BuildStopRunningProgram: string;
    /// <summary>Befehle „Tests ausführen“ und „Fehlgeschlagene Tests erneut ausführen“ (#69, Atlas.RunTests,
    /// Atlas.RunFailedTests); aus = Befehle, Code Lens und Lauf nach dem Build verschwinden.</summary>
    TestRun: Boolean;
    /// <summary>Tests nach jedem erfolgreichen Build des Testprojekts automatisch ausführen (#69, über die
    /// Compile-Ereignisse #527).</summary>
    TestsAfterBuild: Boolean;
    /// <summary>Vor „Tests ausführen“ das Testprojekt bauen (make); aus = die vorhandene Test-EXE läuft.</summary>
    TestsBuildFirst: Boolean;
    /// <summary>Befehl „Betroffene Tests ausführen“ (#1353, Atlas.RunAffectedTests); tests.affected in settings.json,
    /// der Server liest denselben Wert (--affected-tests, get_affected_tests).</summary>
    TestsAffected: Boolean;
    /// <summary>Befehl „Leckprüfung einrichten …“ (#1880, tests.leakSetup).</summary>
    TestsLeakSetup: Boolean;
    /// <summary>Ebenen von der Änderung bis zum Test (#1353, tests.affectedDepth), MinTestsAffectedDepth bis
    /// MaxTestsAffectedDepth.</summary>
    TestsAffectedDepth: Integer;
    /// <summary>Vor jedem git commit die betroffenen Tests anbieten (#1353): Atlas legt dafür einen
    /// pre-commit-Hook an (Atlas.Core.Tests.AffectedHook).</summary>
    TestsAffectedBeforeCommit: Boolean;
    /// <summary>Veraltete Testergebnisse (#1770, tests.stale): Wurde der Rumpf eines Tests seit dem Lauf geändert
    /// (ohne Leerraum und Kommentare), zeigt die Code Lens den alten Stand grau „(veraltet)“ und die Zählung nimmt ihn
    /// nicht als bestanden; dazu der Befehl „Veraltete Tests ausführen“. Aus = Stand wie nach dem Lauf.</summary>
    TestsStale: Boolean;
    /// <summary>Auch Änderungen an den Units, die die Testunit verwendet und die im Testprojekt liegen, machen das
    /// Ergebnis veraltet (#1770, tests.stale.units).</summary>
    TestsStaleUnits: Boolean;
    /// <summary>Ebenen vom Test bis zur Methode für die Marke „getestet von“ (#1778, tests.coveredBy.depth);
    /// 1 = nur Tests, die die Methode direkt aufrufen.</summary>
    TestsCoveredByDepth: Integer;
    /// <summary>Marke „getestet von“ auch an privaten und geschützten Methoden (#1778, tests.coveredBy.private).
    /// </summary>
    TestsCoveredByPrivate: Boolean;
    /// <summary>Unter diesem Anteil getesteter Methoden ist die Marke „n von m Methoden getestet“ gelb (#1783,
    /// tests.untested.warnPercent).</summary>
    TestsUntestedWarnPercent: Integer;
    /// <summary>Betroffene Tests nach dem Speichern im Hintergrund ausführen (#1775, tests.onSave): kein Fenster,
    /// Fortschritt und Ergebnis im Atlas-Statusfeld.</summary>
    TestsOnSave: Boolean;
    /// <summary>Mehr betroffene Tests als diese: kein Lauf im Hintergrund, nur ein Hinweis (#1775, tests.onSave.max),
    /// cMinTestsOnSaveMax bis cMaxTestsOnSaveMax.</summary>
    TestsOnSaveMax: Integer;
    /// <summary>Fehlschlag an der Anweisung statt am Methodenkopf (#1771, tests.failureAtAssert): Zeile aus dem
    /// Stacktrace des Berichts, sonst der eine Assert, dessen erwarteter Wert passt.</summary>
    TestsFailureAtAssert: Boolean;
    /// <summary>Hinter der Assert-Zeile kurz „erwartet 4, erhalten 3“ statt der ganzen Meldung (#1771,
    /// tests.failureInline).</summary>
    TestsFailureInline: Boolean;
    /// <summary>Befehl „Erwartet und erhalten vergleichen“ (#1779, tests.compare): Fenster mit beiden Werten in zwei
    /// Spalten, Unterschiede zeichengenau.</summary>
    TestsCompare: Boolean;
    /// <summary>JSON und XML vor dem Vergleich gleich einrücken (#1779, tests.compare.format).</summary>
    TestsCompareFormat: Boolean;
    /// <summary>Meldungen der Hilfs-Unit Atlas.Testing.Approval erkennen: Abweichung an der Testmarke, übernehmen,
    /// aufräumen (#1881, tests.approvalFiles).</summary>
    TestsApprovalFiles: Boolean;
    /// <summary>Dauer an den Marken der Testlinse, langsame Tests gelb, die langsamsten auf der Willkommensseite
    /// (#1772, tests.showDuration).</summary>
    TestsShowDuration: Boolean;
    /// <summary>Andockbares Fenster „Atlas-Tests“ mit allen Tests des Testprojekts (#1776, tests.window).</summary>
    TestsWindow: Boolean;
    /// <summary>Testlisten im Fenster „Atlas-Tests“ (#2167, tests.lists).</summary>
    TestsLists: Boolean;
    /// <summary>Taste für die zuletzt benutzte Testliste (#2167, tests.lists.runKey; TShortCut, 0 = keine).</summary>
    TestsListsRunKey: Integer;
    /// <summary>Ab dieser Dauer (Millisekunden) gilt ein Test als langsam (#1772, tests.slowMs), cMinTestsSlowMs bis
    /// cMaxTestsSlowMs.</summary>
    TestsSlowMs: Integer;
    /// <summary>[TestCase]-Fälle als Tabelle: Marke an der Testmethode und Befehl (#1879, tests.testCaseTable).
    /// </summary>
    TestsCaseTable: Boolean;
    /// <summary>Lecks je Test (#1774, tests.leaks): Ein Test, den DUnitX nur wegen eines Lecks als fehlgeschlagen
    /// meldet, gilt als bestanden mit Leck (gelbe Marke, Warnung in Atlas-Probleme). Aus = wie im Bericht.</summary>
    TestsLeaks: Boolean;
    /// <summary>Ein Build gilt nur ohne Warnungen und Hinweise als erfolgreich (build.zeroHints, #530); Meldungen
    /// in der Basislinie zählen nicht. Bewertung in Atlas.Core.Build.Verdict.</summary>
    BuildZeroHints: Boolean;
    /// <summary>Kosten einer Änderung im interface-Teil in der Statusleiste (#554, build.showInterfaceCost):
    /// „interface-Änderung: N Units werden neu kompiliert“, solange die Einfügemarke im interface steht. Aus = kein
    /// Feld.</summary>
    ShowInterfaceCost: Boolean;
    /// <summary>Zusammenfassung nach jedem Build in der Atlas-Gruppe des Meldungsfensters (build.summary, #530).
    /// Ein Build, den zeroHints oder warningsAsErrors scheitern lassen, wird auch ohne sie gemeldet.</summary>
    BuildSummary: Boolean;
    /// <summary>Codes von Warnungen und Hinweisen, die als Fehler zählen (build.warningsAsErrors, #530), z. B.
    /// "W1035, H2164"; gespeichert in der Form von TAtlasBuildVerdicts.NormalizeCodes.</summary>
    BuildWarningsAsErrors: string;
    /// <summary>Fenster „Compiler-Schalter“ (#558, build.compilerSwitches, Befehl Atlas.CompilerSwitches): wirksame
    /// Schalter R, Q, O, C, I, A, HINTS, WARNINGS, abgeschaltete Warnungen und aktive Symbole an der Cursorposition
    /// mit Herkunft (Projektoption, Include-Datei, Direktive mit Zeile); Abweichungen von der .dproj hervorgehoben.
    /// Aus = kein Fenster, kein Befehl, keine Anfrage.</summary>
    BuildCompilerSwitches: Boolean;
    /// <summary>Feld in der Statusleiste mit den Schaltern, die an der Cursorposition von der .dproj abweichen („R−
    /// Q− HINTS OFF“; #558, build.showSwitchesInStatusBar); ohne Abweichung kein Feld. Ein Klick öffnet das Fenster
    /// „Compiler-Schalter“.</summary>
    BuildSwitchesInStatusBar: Boolean;
    /// <summary>Release-Build-Wächter (#533, build.releaseGuard): vor make und build in einer Release-Konfiguration
    /// die Projektoptionen prüfen, dazu der Befehl „Release-Build prüfen“ (Atlas.CheckRelease) mit Tipp. Aus = keine
    /// Prüfung, Befehl und Tipp verschwinden.</summary>
    ReleaseGuard: Boolean;
    /// <summary>Verhalten bei Verstößen (build.gate, #529): off, warn oder block (bricht den Build ab). Gilt für die
    /// Prüfung vor dem Kompilieren (off = keine Prüfung) und den Release-Wächter (#533, off und warn melden nur).
    /// </summary>
    BuildGate: string;
    /// <summary>Projektaufgaben (#900, tasks.enabled): Aufgaben aus dem Abschnitt „tasks“ von atlas.json mit Befehlen,
    /// Menü Atlas › Aufgaben, Tasten je Aufgabe, Statusfeld und Schnellaktion. Aus = keine Befehle, kein Menü, keine
    /// Tasten und kein Lauf vor dem Build.</summary>
    TasksEnabled: Boolean;
    /// <summary>Fundstellen der Ausgabe als Befunde in Problemliste und Editor (tasks.problemsFromOutput); aus = nur
    /// die Ausgabe im Register „Atlas-Aufgaben“.</summary>
    TasksProblemsFromOutput: Boolean;
    /// <summary>Aufgaben der Gruppe „check“ vor jedem Compile/Build (tasks.beforeBuild): off, warn (Build läuft,
    /// Befunde erscheinen) oder block (Exit-Code ungleich 0 oder Fehler brechen den Build ab). „beforeBuild“ einer
    /// Aufgabe überschreibt den Wert.</summary>
    TasksBeforeBuild: string;
    /// <summary>Geänderte Dateien vor dem Start einer Aufgabe speichern (tasks.saveBeforeRun).</summary>
    TasksSaveBeforeRun: Boolean;
    /// <summary>„Alle Prüfungen ausführen“ und der Lauf vor dem Build starten die check-Aufgaben gleichzeitig
    /// (tasks.runChecksParallel); aus = nacheinander.</summary>
    TasksRunChecksParallel: Boolean;
    /// <summary>Register „Atlas-Aufgaben“ zeigt nur die erkannten Fundstellen (tasks.onlyFindings); aus = die ganze
    /// Ausgabe. Umschaltbar über den Befehl „Aufgaben: nur Befunde / ganze Ausgabe“.</summary>
    TasksOnlyFindings: Boolean;
    /// <summary>Zeitlimit der Prüfung vor dem Kompilieren in ms (build.gateTimeoutMs, #529); danach läuft der
    /// Compile ungeprüft.</summary>
    BuildGateTimeoutMs: Integer;
    /// <summary>Konfigurationen, die außer „Release“ als Release gelten (build.releaseConfigs), durch Komma
    /// getrennt.</summary>
    ReleaseConfigs: string;
    /// <summary>Prüfungen des Release-Wächters mit an/aus und Sollwert (build.releaseChecks), Textform wie
    /// TAtlasReleaseChecks.ToText, z. B. "debugDefine,debugInfo=off,-assertions=off,…".</summary>
    ReleaseChecks: string;
    /// <summary>Modul-Schalter tests.enabled (#1454): DUnitX-Tests; aus = die wirksamen Werte aller Einstellungen des
    /// Moduls sind
    /// „aus“ (TAtlasModuleSwitches), gespeichert bleiben sie.</summary>
    TestsEnabled: Boolean;
    /// <summary>Modul-Schalter buildTools.enabled (#1454): Build-Werkzeuge; aus = die wirksamen Werte aller
    /// Einstellungen des Moduls sind
    /// „aus“ (TAtlasModuleSwitches), gespeichert bleiben sie.</summary>
    BuildToolsEnabled: Boolean;
    /// <summary>Modul-Schalter buildPipeline.enabled (#1455): Build-Pipeline; aus = die wirksamen Werte aller
    /// Einstellungen des Moduls sind „aus“ (TAtlasModuleSwitches), gespeichert bleiben sie.</summary>
    BuildPipelineEnabled: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginBuildSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
    /// <summary>Vorgaben der Tests (tests.*).</summary>
    procedure DefaultTests;
    /// <summary>Einstellungen der Tests (tests.*) über AIo lesen bzw. schreiben.</summary>
    procedure ExchangeTests(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.OpenBuildSettings,
  Atlas.Core.Build.PipelineSettings,
  Atlas.Core.Build.Verdict;

/// <summary>Bekannter Wert aus ANames klein (tasks.beforeBuild, build.stopRunningProgram), sonst der erste.</summary>
function NormalizedName(const AText: string; const ANames: array of string): string;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if SameText(Trim(AText), mName) then
    begin
      Exit(mName);
    end;
  end;
  Result := ANames[0];
end;

{ TAtlasPluginBuildSettings }

class function TAtlasPluginBuildSettings.Defaults: TAtlasPluginBuildSettings;
begin
  // Die Prüfung in der IDE zeigt deren Fortschritt; Standard ist die Prüfung des Servers mit dcc (compiler.onSave).
  Result.CheckOnSave := False;
  Result.CompileOnSave := False;
  Result.CheckOnSaveDelayMs := 2000;
  Result.CheckOnSaveMaxMs := 1500;
  Result.McpBuild := True;
  Result.AssistantsEnabled := True;
  Result.AssistantsEdit := True;
  Result.BuildOnOpen := False;
  Result.BuildOnOpenKind := TAtlasOpenBuildSettings.KindName(TAtlasCompileKind.Make);
  Result.BuildOnOpenScope := TAtlasOpenBuildSettings.cScopeNames[TAtlasOpenBuildScope.All];
  Result.BuildOnOpenDelayMs := TAtlasOpenBuildSettings.cDefaultDelayMs;
  Result.BuildOnOpenExclude := '';
  Result.BuildOnOpenConfig := '';
  Result.BuildOnOpenPlatform := '';
  Result.BuildStopRunningProgram := cStopRunningProgramNames[0];
  Result.DefaultTests;
  Result.BuildZeroHints := False;
  Result.ShowInterfaceCost := True;
  Result.BuildSummary := True;
  Result.BuildWarningsAsErrors := '';
  Result.BuildCompilerSwitches := True;
  Result.BuildSwitchesInStatusBar := False;
  Result.ReleaseGuard := True;
  Result.BuildGate := 'off';
  Result.TasksEnabled := True;
  Result.TasksProblemsFromOutput := True;
  Result.TasksBeforeBuild := 'off';
  Result.TasksSaveBeforeRun := True;
  Result.TasksRunChecksParallel := False;
  Result.TasksOnlyFindings := False;
  Result.BuildGateTimeoutMs := TAtlasBuildPipelineSettings.cGateDefaultTimeoutMs;
  Result.ReleaseConfigs := TAtlasBuildPipelineSettings.cReleaseConfiguration;
  Result.ReleaseChecks := TAtlasReleaseChecks.Defaults.ToText;
  Result.TestsEnabled := True;
  Result.BuildToolsEnabled := True;
  Result.BuildPipelineEnabled := True;
end;

procedure TAtlasPluginBuildSettings.Normalize;
begin
  CheckOnSaveDelayMs := EnsureRange(CheckOnSaveDelayMs, cMinCheckDelay, cMaxCheckDelay);
  CheckOnSaveMaxMs := EnsureRange(CheckOnSaveMaxMs, cMinCheckMax, cMaxCheckMax);
  BuildOnOpenKind := TAtlasOpenBuildSettings.KindName(TAtlasOpenBuildSettings.KindOf(BuildOnOpenKind));
  BuildOnOpenScope := TAtlasOpenBuildSettings.cScopeNames[TAtlasOpenBuildSettings.ScopeOf(BuildOnOpenScope)];
  BuildOnOpenDelayMs := EnsureRange(BuildOnOpenDelayMs, TAtlasOpenBuildSettings.cMinDelayMs,
    TAtlasOpenBuildSettings.cMaxDelayMs);
  BuildOnOpenExclude := TAtlasOpenBuildSettings.NormalizedExclude(BuildOnOpenExclude);
  BuildOnOpenConfig := Trim(BuildOnOpenConfig);
  BuildOnOpenPlatform := Trim(BuildOnOpenPlatform);
  BuildStopRunningProgram := NormalizedName(BuildStopRunningProgram, cStopRunningProgramNames);
  // Nach dem Speichern genau eins von beiden: Die Syntaxprüfung der IDE gewinnt.
  if CheckOnSave then
  begin
    CompileOnSave := False;
  end;
  BuildGate := TAtlasBuildPipelineSettings.cGateNames[TAtlasBuildPipelineSettings.GateOf(BuildGate)];
  TasksBeforeBuild := NormalizedName(TasksBeforeBuild, cTasksBeforeBuildNames);
  BuildGateTimeoutMs := EnsureRange(BuildGateTimeoutMs, TAtlasBuildPipelineSettings.cGateMinTimeoutMs,
    TAtlasBuildPipelineSettings.cGateMaxTimeoutMs);
  ReleaseConfigs := TAtlasBuildPipelineSettings.NormalizedConfigurations(ReleaseConfigs);
  BuildWarningsAsErrors := TAtlasBuildVerdicts.NormalizeCodes(BuildWarningsAsErrors);
  ReleaseChecks := TAtlasReleaseChecks.Normalized(ReleaseChecks);
  TestsAffectedDepth := EnsureRange(TestsAffectedDepth, cMinTestsAffectedDepth, cMaxTestsAffectedDepth);
  TestsCoveredByDepth := EnsureRange(TestsCoveredByDepth, cMinTestsCoveredByDepth, cMaxTestsCoveredByDepth);
  TestsUntestedWarnPercent := EnsureRange(TestsUntestedWarnPercent, cMinTestsUntestedWarnPercent,
    cMaxTestsUntestedWarnPercent);
  TestsOnSaveMax := EnsureRange(TestsOnSaveMax, cMinTestsOnSaveMax, cMaxTestsOnSaveMax);
  TestsSlowMs := EnsureRange(TestsSlowMs, cMinTestsSlowMs, cMaxTestsSlowMs);
  TestsListsRunKey := EnsureRange(TestsListsRunKey, 0, $FFFF);
end;

procedure TAtlasPluginBuildSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('CheckOnSave', CheckOnSave);
  AIo.Flag('CompileOnSave', CompileOnSave);
  AIo.Number('CheckOnSaveDelayMs', CheckOnSaveDelayMs);
  AIo.Number('CheckOnSaveMaxMs', CheckOnSaveMaxMs);
  AIo.Flag('McpBuild', McpBuild);
  AIo.Flag('AssistantsEnabled', AssistantsEnabled);
  AIo.Flag('AssistantsEdit', AssistantsEdit);
  AIo.Flag('BuildOnOpen', BuildOnOpen);
  AIo.Text('BuildOnOpenKind', BuildOnOpenKind);
  AIo.Text('BuildOnOpenScope', BuildOnOpenScope);
  AIo.Number('BuildOnOpenDelayMs', BuildOnOpenDelayMs);
  AIo.Text('BuildOnOpenExclude', BuildOnOpenExclude);
  AIo.Text('BuildOnOpenConfig', BuildOnOpenConfig);
  AIo.Text('BuildOnOpenPlatform', BuildOnOpenPlatform);
  AIo.Text('BuildStopRunningProgram', BuildStopRunningProgram);
  ExchangeTests(AIo);
  AIo.Flag('BuildZeroHints', BuildZeroHints);
  AIo.Flag('ShowInterfaceCost', ShowInterfaceCost);
  AIo.Flag('BuildSummary', BuildSummary);
  AIo.Text('BuildWarningsAsErrors', BuildWarningsAsErrors);
  AIo.Flag('BuildCompilerSwitches', BuildCompilerSwitches);
  AIo.Flag('BuildSwitchesInStatusBar', BuildSwitchesInStatusBar);
  AIo.Flag('ReleaseGuard', ReleaseGuard);
  AIo.Text('BuildGate', BuildGate);
  AIo.Flag('TasksEnabled', TasksEnabled);
  AIo.Flag('TasksProblemsFromOutput', TasksProblemsFromOutput);
  AIo.Text('TasksBeforeBuild', TasksBeforeBuild);
  AIo.Flag('TasksSaveBeforeRun', TasksSaveBeforeRun);
  AIo.Flag('TasksRunChecksParallel', TasksRunChecksParallel);
  AIo.Flag('TasksOnlyFindings', TasksOnlyFindings);
  AIo.Number('BuildGateTimeoutMs', BuildGateTimeoutMs);
  AIo.Text('ReleaseConfigs', ReleaseConfigs);
  AIo.Text('ReleaseChecks', ReleaseChecks);
  AIo.Flag('TestsEnabled', TestsEnabled);
  AIo.Flag('BuildToolsEnabled', BuildToolsEnabled);
  AIo.Flag('BuildPipelineEnabled', BuildPipelineEnabled);
end;

procedure TAtlasPluginBuildSettings.DefaultTests;
begin
  TestRun := True;
  TestsAfterBuild := False;
  TestsBuildFirst := True;
  TestsAffected := True;
  TestsLeakSetup := True;
  TestsAffectedDepth := cDefaultTestsAffectedDepth;
  TestsAffectedBeforeCommit := False;
  TestsStale := True;
  TestsStaleUnits := False;
  TestsCoveredByDepth := 1;
  TestsCoveredByPrivate := False;
  TestsUntestedWarnPercent := cDefaultTestsUntestedWarnPercent;
  TestsOnSave := False;
  TestsOnSaveMax := cDefaultTestsOnSaveMax;
  TestsFailureAtAssert := True;
  TestsFailureInline := True;
  TestsCompare := True;
  TestsCompareFormat := True;
  TestsApprovalFiles := True;
  TestsShowDuration := True;
  TestsWindow := True;
  TestsLists := True;
  TestsListsRunKey := cDefaultTestsListsRunKey;
  TestsSlowMs := cDefaultTestsSlowMs;
  TestsCaseTable := True;
  TestsLeaks := True;
end;

procedure TAtlasPluginBuildSettings.ExchangeTests(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('TestRun', TestRun);
  AIo.Flag('TestsAfterBuild', TestsAfterBuild);
  AIo.Flag('TestsBuildFirst', TestsBuildFirst);
  AIo.Flag('TestsAffected', TestsAffected);
  AIo.Flag('TestsLeakSetup', TestsLeakSetup);
  AIo.Number('TestsAffectedDepth', TestsAffectedDepth);
  AIo.Flag('TestsAffectedBeforeCommit', TestsAffectedBeforeCommit);
  AIo.Flag('TestsStale', TestsStale);
  AIo.Flag('TestsStaleUnits', TestsStaleUnits);
  AIo.Number('TestsCoveredByDepth', TestsCoveredByDepth);
  AIo.Flag('TestsCoveredByPrivate', TestsCoveredByPrivate);
  AIo.Number('TestsUntestedWarnPercent', TestsUntestedWarnPercent);
  AIo.Flag('TestsOnSave', TestsOnSave);
  AIo.Number('TestsOnSaveMax', TestsOnSaveMax);
  AIo.Flag('TestsFailureAtAssert', TestsFailureAtAssert);
  AIo.Flag('TestsFailureInline', TestsFailureInline);
  AIo.Flag('TestsCompare', TestsCompare);
  AIo.Flag('TestsCompareFormat', TestsCompareFormat);
  AIo.Flag('TestsApprovalFiles', TestsApprovalFiles);
  AIo.Flag('TestsShowDuration', TestsShowDuration);
  AIo.Flag('TestsWindow', TestsWindow);
  AIo.Flag('TestsLists', TestsLists);
  AIo.Number('TestsListsRunKey', TestsListsRunKey);
  AIo.Number('TestsSlowMs', TestsSlowMs);
  AIo.Flag('TestsCaseTable', TestsCaseTable);
  AIo.Flag('TestsLeaks', TestsLeaks);
end;

end.
