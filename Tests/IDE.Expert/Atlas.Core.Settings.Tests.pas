unit Atlas.Core.Settings.Tests;

// Tests für die Einstellungen des Plugins (#227, Teil Vervollständigung).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPluginSettingsTests = class
  public
    [Test]
    procedure EmptyStoreGivesDefaults;
    /// <summary>Der alte Registry-Name ProblemsList (meist die Vorgabe „an“ von vor #909) gilt nicht mehr.</summary>
    [Test]
    procedure MessageListIgnoresFormerRegistryName;
    [Test]
    procedure ProblemsWindowOptions;
    /// <summary>Aktualisierung der Prüfung (problems.update, problems.liveDelayMs), Übernahme von problems.live.
    /// </summary>
    [Test]
    procedure ProblemsUpdateOptions;
    /// <summary>#1108: offene Units zuerst, nicht geöffnete Units, aktive Unit ohne Befunde.</summary>
    [Test]
    procedure ProblemsWindowOpenFirstOptions;
    [Test]
    procedure SaveAndLoadRoundTrip;
    [Test]
    procedure ClampsOutOfRangeValues;
    [Test]
    procedure ClampsNormalizedRanges;
    [Test]
    procedure NormalizesUpdateChoices;
    [Test]
    procedure IndexOptionsGoToGlobalFile;
    [Test]
    procedure XmlDocOptionsGoToGlobalFile;
    /// <summary>#1841: hover.membersMaxLines mit Vorgabe 15 und Grenzen 0..100.</summary>
    [Test]
    procedure HoverMembersMaxLinesRoundTrip;
    /// <summary>#2168: tests.log an, tests.log.maxLines mit Vorgabe 2000 und Grenzen 100..100000.</summary>
    [Test]
    procedure TestsLogRoundTrip;
    /// <summary>#1919: hover.signatureParams mit Vorgabe an.</summary>
    [Test]
    procedure HoverSignatureParamsRoundTrip;
    /// <summary>#54: hover.explainMessages ist an und lässt sich abschalten.</summary>
    [Test]
    procedure HoverExplainMessagesRoundTrip;
    /// <summary>#145: hover.ruleExamples mit Vorgabe an.</summary>
    [Test]
    procedure HoverRuleExamplesRoundTrip;
    /// <summary>#1818: editor.trackLines mit Vorgabe an.</summary>
    [Test]
    procedure TrackLinesRoundTrip;
    /// <summary>#1890: suggestions.* mit Vorgaben und Grenzen.</summary>
    [Test]
    procedure LearnedSuggestionsRoundTrip;
    /// <summary>#1819: problems.ideErrors mit Vorgabe aus.</summary>
    [Test]
    procedure IdeErrorsRoundTrip;
    /// <summary>#1817: commands.projectContextMenu mit Vorgabe an.</summary>
    [Test]
    procedure ProjectContextMenuRoundTrip;
    /// <summary>#1821: generate.galleryWizards mit Vorgabe an.</summary>
    [Test]
    procedure GalleryWizardsRoundTrip;
    /// <summary>#2102: commands.editorContextMenu.contextual (Vorgabe an) und .groups (Vorgabe alle, normalisiert).
    /// </summary>
    [Test]
    procedure EditorContextMenuRoundTrip;
    [Test]
    procedure AcceptOptionsRoundTrip;
    [Test]
    procedure OneActionAfterSaving;
    [Test]
    procedure CompletionVariantBranchOption;
    /// <summary>Benachrichtigungszentrale (#601): Vorgaben, Grenzen, Verhalten je Quelle, Speichern und Laden.
    /// </summary>
    [Test]
    procedure NotificationOptions;
    [Test]
    procedure CompletionListModeOptions;
    /// <summary>„Datei jetzt prüfen“ (#1744): Vorgabe, Grenzen, Speichern und Laden.</summary>
    [Test]
    procedure CheckFileKeyOption;
  end;

  [TestFixture]
  TAtlasSettingsScopesTests = class
  public
    [Test]
    procedure RoutesServerSettingsToGlobalFile;
    [Test]
    procedure ArchitectureSettingsLiveInGlobalFile;
    [Test]
    procedure KeepsCommentsAndOtherKeys;
    [Test]
    procedure MigratesRegistryValuesOnce;
    [Test]
    procedure LeavesBrokenFileAlone;
    [Test]
    procedure SplitsSchemaByScope;
    /// <summary>Jede Beschreibung des Schemas gibt es auch englisch (#1458); ohne englischen Text die deutsche.
    /// </summary>
    [Test]
    procedure SchemaDescriptionsInBothLanguages;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.Scopes,
  Atlas.Core.Settings.TestSupport;

{ TAtlasPluginSettingsTests }

/// <summary>Vorgaben für Test aus dem Debug-Halt, Vergleich, Fenster „Atlas-Tests“ und Testlisten.</summary>
procedure AssertTestWindowDefaults(const ASettings: TAtlasPluginSettings);
begin
  Assert.IsTrue(ASettings.TestsFromDebugStop, 'Test aus dem Debug-Halt standardmäßig an (#1873)');
  Assert.IsTrue(ASettings.TestsFromDebugStopFields, 'Felder anbieten standardmäßig an (#1873)');
  Assert.IsFalse(ASettings.TestsFromDebugStopProperties, 'Getter standardmäßig aus (#1873)');
  Assert.AreEqual(20, ASettings.TestsFromDebugStopMaxArray, 'Array-Grenze standardmäßig 20 (#1873)');
  Assert.IsTrue(ASettings.TestsCompare, 'Vergleich erwartet/erhalten standardmäßig an (#1779)');
  Assert.IsTrue(ASettings.TestsCompareFormat, 'JSON/XML einrücken standardmäßig an (#1779)');
  Assert.IsTrue(ASettings.TestsCaseTable, 'TestCase-Tabelle standardmäßig an (#1879)');
  Assert.IsTrue(ASettings.TestsBoundaryCases, 'Grenzfälle standardmäßig an (#2173)');
  Assert.AreEqual(20, ASettings.TestsBoundaryMax, 'höchstens 20 Grenzfälle (#2173)');
  Assert.IsTrue(ASettings.TestsApprovalFiles, 'Vergleichsdateien standardmäßig an (#1881)');
  Assert.IsTrue(ASettings.TestsShowDuration, 'Dauer an der Testmarke standardmäßig an (#1772)');
  Assert.IsTrue(ASettings.TestsWindow, 'Fenster „Atlas-Tests“ standardmäßig an (#1776)');
  Assert.IsTrue(ASettings.TestsLists, 'Testlisten standardmäßig an (#2167)');
  Assert.AreEqual($C052, ASettings.TestsListsRunKey, 'Testliste mit Strg+Alt+R (#2167)');
  Assert.IsTrue(ASettings.EditorStatusBarTests, 'Teststand in der Statusleiste standardmäßig an (#1777)');
  Assert.AreEqual(500, ASettings.TestsSlowMs, 'langsam ab 500 ms (#1772)');
  Assert.IsTrue(ASettings.TestsLeaks, 'Lecks je Test standardmäßig an (#1774)');
  Assert.AreEqual(20, ASettings.TestsRepeatCount, 'N-mal ausführen: Vorgabe 20 (#1782)');
  Assert.IsTrue(ASettings.TestsFlaky, 'wackelnde Tests standardmäßig an (#1773)');
  Assert.AreEqual(10, ASettings.TestsFlakyRuns, 'zehn Läufe je Test (#1773)');
  Assert.IsFalse(ASettings.TestsMutation, 'Mutationslauf standardmäßig aus, experimentell (#1460)');
  Assert.AreEqual(60, ASettings.TestsMutationTimeoutSec, '60 s je Mutant (#1460)');
  Assert.AreEqual('', ASettings.TestsMutationOperators, 'alle Operatoren (#1460)');
end;

/// <summary>Vorgaben für Editor, Code Lens und Tests.</summary>
procedure AssertEditorDefaults(const ASettings: TAtlasPluginSettings);
begin
  Assert.IsTrue(ASettings.Enabled);
  Assert.AreEqual(9, ASettings.VisibleRows);
  Assert.AreEqual(0, ASettings.ListWidth, 'Liste automatisch');
  Assert.AreEqual(320, ASettings.PanelWidth);
  Assert.IsTrue(ASettings.AutoParentheses);
  Assert.IsFalse(ASettings.Preview, 'Vorschau standardmäßig aus (#434)');
  Assert.IsTrue(ASettings.OpenForEdits, 'Nicht geöffnete Dateien öffnen (#397)');
  Assert.IsFalse(ASettings.InlayHints, 'Inlay-Hints standardmäßig aus (#401)');
  Assert.AreEqual($800D, ASettings.ActionsKey, 'Code-Aktionen: Alt+Enter (#399)');
  Assert.AreEqual(0, ASettings.TypeDefinitionKey, 'Typdefinition ohne Kürzel');
  Assert.IsTrue(ASettings.MethodToggle, 'Deklaration/Implementierung wechseln standardmäßig an (#775)');
  Assert.AreEqual($6026, ASettings.MethodToggleUpKey, 'Strg+Umschalt+Hoch (#775)');
  Assert.AreEqual($6028, ASettings.MethodToggleDownKey, 'Strg+Umschalt+Runter (#775)');
  Assert.AreEqual(0, ASettings.TestUnitKey, 'Testunit-Wechsel ohne Kürzel (#189)');
  Assert.IsTrue(ASettings.CodeLensTestUnit, 'Code Lens Testunit standardmäßig an (#189)');
  Assert.IsTrue(ASettings.CodeLensMetrics, 'Code Lens Metriken standardmäßig an (#66)');
  Assert.IsTrue(ASettings.ReferencesInferred, 'erschlossene Verwendungen standardmäßig an (#1119)');
  Assert.IsFalse(ASettings.ReferencesTextMatches, 'Textfunde standardmäßig aus (#1119)');
  Assert.IsTrue(ASettings.Impact, 'Auswirkungen anzeigen standardmäßig an (#1120)');
  Assert.AreEqual(2, ASettings.ImpactDepth, 'Tiefe der Auswirkungsanalyse standardmäßig 2 (#1120)');
  Assert.IsTrue(ASettings.CodeLensTests, 'Code Lens „Test ausführen“ standardmäßig an (#69)');
  Assert.IsTrue(ASettings.TestCoverage, 'Testabdeckung in der Rinne standardmäßig an (#275)');
  Assert.IsTrue(ASettings.TestRun, 'Tests ausführen standardmäßig da (#69)');
  Assert.IsFalse(ASettings.TestsAfterBuild, 'Tests nach dem Build standardmäßig aus (#69)');
  Assert.IsTrue(ASettings.TestsAffected, 'Betroffene Tests standardmäßig an (#1353)');
  Assert.IsTrue(ASettings.TestsLeakSetup, 'Leckprüfung einrichten standardmäßig an (#1880)');
  Assert.AreEqual(3, ASettings.TestsAffectedDepth, 'Tiefe der betroffenen Tests standardmäßig 3 (#1353)');
  Assert.IsFalse(ASettings.TestsAffectedBeforeCommit, 'Angebot vor dem Commit standardmäßig aus (#1353)');
  Assert.IsTrue(ASettings.TestsBuildFirst, 'vor den Tests bauen standardmäßig an (#69)');
  Assert.IsTrue(ASettings.TestsStale, 'veraltete Testergebnisse standardmäßig an (#1770)');
  Assert.IsFalse(ASettings.TestsStaleUnits, 'veraltet über geänderte Units standardmäßig aus (#1770)');
  Assert.IsTrue(ASettings.CodeLensCoveredBy, 'Marke „getestet von“ standardmäßig an (#1778)');
  Assert.IsFalse(ASettings.OwnershipHints, 'Marke „Wer gibt das frei?“ standardmäßig aus (#1877)');
  Assert.IsFalse(ASettings.OwnershipHintsOnlyProblems, 'nur Problemfälle standardmäßig aus (#1877)');
  Assert.AreEqual(1, ASettings.TestsCoveredByDepth, 'Tiefe „getestet von“ standardmäßig 1 (#1778)');
  Assert.IsFalse(ASettings.TestsCoveredByPrivate, '„getestet von“ an privaten Methoden standardmäßig aus (#1778)');
  Assert.IsTrue(ASettings.CodeLensUntested, 'Marke „n von m Methoden getestet“ standardmäßig an (#1783)');
  Assert.AreEqual(50, ASettings.TestsUntestedWarnPercent, 'gelb unter 50 % standardmäßig (#1783)');
  Assert.IsFalse(ASettings.TestsOnSave, 'Tests beim Speichern standardmäßig aus (#1775)');
  Assert.AreEqual(50, ASettings.TestsOnSaveMax, 'höchstens 50 Tests im Hintergrund (#1775)');
  Assert.IsTrue(ASettings.TestsFailureAtAssert, 'Fehlschlag an der Assert-Zeile standardmäßig an (#1771)');
  Assert.IsTrue(ASettings.TestsFailureInline, 'erwartet/erhalten hinter der Zeile standardmäßig an (#1771)');
  AssertTestWindowDefaults(ASettings);
end;

/// <summary>Vorgaben für Build, Startprofile und „Test debuggen“.</summary>
procedure AssertBuildDefaults(const ASettings: TAtlasPluginSettings);
begin
  Assert.IsFalse(ASettings.BuildZeroHints, 'build.zeroHints standardmäßig aus (#530)');
  Assert.IsTrue(ASettings.ShowInterfaceCost, 'build.showInterfaceCost standardmäßig an (#554)');
  Assert.IsTrue(ASettings.BuildCompilerSwitches, 'build.compilerSwitches (#558)');
  Assert.IsFalse(ASettings.BuildSwitchesInStatusBar, 'build.showSwitchesInStatusBar (#558)');
  Assert.IsTrue(ASettings.StartProfiles, 'Startprofile standardmäßig an (#575)');
  Assert.IsTrue(ASettings.StartProfilesStatusField, 'Startprofil in der Statusleiste standardmäßig an (#575)');
  Assert.IsTrue(ASettings.TestDebug, 'Test debuggen standardmäßig da (#585)');
  Assert.IsTrue(ASettings.TestBreakAtStart, 'debug.testBreakAtStart standardmäßig an (#585)');
end;
/// <summary>Vorgaben für Debugger, Befehle und Tasten.</summary>
procedure AssertDebugDefaults(const ASettings: TAtlasPluginSettings);
begin
  Assert.IsTrue(ASettings.DebugHoverValues, 'debug.hoverValues standardmäßig an (#891)');
  Assert.IsTrue(ASettings.DebugExplainUnavailable, 'debug.explainUnavailable (#840)');
  Assert.IsTrue(ASettings.DebugCompletionInDialogs, 'debug.completionInDialogs (#538)');
  Assert.IsTrue(ASettings.DebugEvaluateWindow, 'debug.evaluateWindow (#784)');
  Assert.IsTrue(ASettings.DebugEvaluateReplaceCtrlF7, 'debug.evaluateWindow.replaceCtrlF7 (#784)');
  Assert.IsTrue(ASettings.DebugExplainAccessViolation, 'debug.explainAccessViolation (#865)');
  Assert.IsFalse(ASettings.DebugExplainAccessViolationAllowCalls, 'debug.explainAccessViolation.allowCalls (#865)');
  Assert.AreEqual('', ASettings.DebugParallelStacksWaitRoutines, 'debug.parallelStacks.waitRoutines (#837)');
  Assert.AreEqual(64, ASettings.DebugParallelStacksMaxThreads, 'debug.parallelStacks.maxThreads (#837)');
  Assert.IsFalse(ASettings.DebugThreadFreeze, 'debug.threadFreeze (#852)');
  Assert.IsFalse(ASettings.DebugAsyncOrigin, 'debug.asyncOrigin (#859)');
  Assert.AreEqual(20, ASettings.DebugAsyncOriginMaxPerSite, 'debug.asyncOrigin.maxPerSite (#859)');
  Assert.IsTrue(ASettings.DebugThreadsInSource, 'debug.threadsInSource (#852)');
  Assert.IsTrue(ASettings.DebugParallelStacks, 'debug.parallelStacks (#837)');
  Assert.IsTrue(ASettings.DebugCallStackWindow, 'debug.callStackWindow (#843)');
  Assert.IsTrue(ASettings.DebugCallStackWindowEvaluateParams, 'debug.callStackWindow.evaluateParams (#843)');
  Assert.IsTrue(ASettings.DebugDeadlocks, 'debug.deadlocks (#587)');
  Assert.IsTrue(ASettings.DebugLeakReport, 'debug.leakReport (#1875)');
  Assert.IsTrue(ASettings.DebugLeakReportCompare, 'debug.leakReport.compare (#1875)');
  Assert.IsTrue(ASettings.DebugLeakReportWindow, 'debug.leakReport.window (#1875)');
  Assert.IsTrue(ASettings.DebugModuleOfAddress, 'debug.moduleOfAddress (#1820)');
  Assert.IsTrue(ASettings.DebugExceptionHistory, 'debug.exceptionHistory (#517)');
  Assert.IsTrue(ASettings.DebugJustMyCode, 'debug.justMyCode (#578)');
  Assert.IsFalse(ASettings.DebugExceptionBanner, 'debug.exceptionBanner (#783)');
  Assert.IsTrue(ASettings.DebugExceptionBannerIgnoreAtLocation, 'debug.exceptionBanner.ignoreAtLocation (#783)');
  Assert.IsTrue(ASettings.DebugInlineValues, 'debug.inlineValues (#508)');
  Assert.AreEqual(5, ASettings.DebugInlineValuesPerLine, 'debug.inlineValuesPerLine (#508)');
  Assert.IsTrue(ASettings.DebugMemoryTimeline, 'debug.memoryTimeline (#858)');
  Assert.AreEqual(1000, ASettings.DebugMemoryTimelineIntervalMs, 'debug.memoryTimeline.intervalMs (#858)');
  Assert.IsFalse(ASettings.DebugProfiler, 'debug.profiler (#2057)');
  Assert.AreEqual(10, ASettings.DebugProfilerIntervalMs, 'debug.profiler.intervalMs (#2057)');
  Assert.IsFalse(ASettings.DebugMemoryTimelineObjectCount, 'debug.memoryTimeline.objectCount (#858)');
  Assert.IsTrue(ASettings.DebugWhyHere, 'debug.whyHere (#1878)');
  Assert.AreEqual(3, ASettings.DebugWhyHereDepth, 'debug.whyHere.depth (#1878)');
  Assert.IsTrue(ASettings.DebugVariablesWindow, 'debug.variablesWindow (#853)');
  Assert.AreEqual(3, ASettings.DebugVariablesSearchDepth, 'debug.variablesWindow.searchDepth (#853)');
  Assert.AreEqual(500, ASettings.DebugVariablesSearchLimit, 'debug.variablesWindow.searchLimit (#853)');
  Assert.IsTrue(ASettings.DebugPredictConditions, 'debug.predictConditions (#2169)');
  Assert.IsTrue(ASettings.DebugPredictDimSkipped, 'debug.predictConditions.dimSkipped (#2169)');
  Assert.AreEqual(20, ASettings.DebugPredictLines, 'debug.predictConditions.lines (#2169)');
  Assert.IsTrue(ASettings.DebugEditValues, 'debug.editValues (#868)');
  Assert.IsTrue(ASettings.DebugHoverExpand, 'debug.hoverExpand (#895)');
  Assert.IsTrue(ASettings.DebugHoverChanges, 'debug.hoverChanges (#895)');
  Assert.AreEqual(100, ASettings.DebugHoverMaxChildren, 'debug.hoverMaxChildren (#895)');
  Assert.IsTrue(ASettings.DebugPinnedValues, 'debug.pinnedValues (#526)');
  Assert.AreEqual('', ASettings.DebugOwnCodeFolders, 'debug.ownCodeFolders leer (#578)');
  Assert.IsTrue(ASettings.TodoList, 'Befehl standardmäßig da (#68)');
  Assert.IsTrue(ASettings.MetricsReport, 'Befehl standardmäßig da (#66)');
  Assert.IsTrue(ASettings.TeamFile, 'Projektdatei standardmäßig an (#486)');
  Assert.IsTrue(ASettings.McpBuild, 'Builds für Claude Code standardmäßig erlaubt (#261)');
  Assert.IsTrue(ASettings.BaselineUpdate, 'Befehl standardmäßig da (#97)');
  Assert.IsTrue(ASettings.SlashCommands, 'Schnellbefehle standardmäßig an (#399)');
  Assert.IsTrue(ASettings.Snippets, 'Code-Vorlagen standardmäßig an (#51)');
  Assert.IsTrue(ASettings.ImportIdeTemplates, 'Live Templates der IDE standardmäßig an (#51)');
  // Vervollständigung und Parameter-Hint über die Tasten der IDE, ohne eigene Belegung (#494).
  Assert.AreEqual(0, ASettings.CompletionKey);
  Assert.AreEqual(0, ASettings.SignatureKey);
  Assert.IsFalse(ASettings.SignatureKeyPriority);
  Assert.AreEqual(200, ASettings.ProviderTimeLimitMs, 'Zeitlimit für Quellen (#493)');
  Assert.AreEqual($E041, ASettings.QuickToggleKey, 'Schnellschalter: Strg+Umschalt+Alt+A (#604)');
  Assert.IsFalse(ASettings.QuickToggleKeyPriority);
end;
/// <summary>Vorgaben für Diagnose, Einrichtung, Start, Zurücknehmen und Lesezeichen.</summary>
procedure AssertToolDefaults(const ASettings: TAtlasPluginSettings);
begin
  // Diagnosemodus (#479): aus; Taste Strg+Umschalt+Alt+D, weil A den Schnellschaltern gehört.
  Assert.IsFalse(ASettings.DiagnosticMode);
  Assert.AreEqual($E044, ASettings.DiagnosticModeKey);
  Assert.IsFalse(ASettings.DiagnosticModeKeyPriority);
  // Prozesse am Projekt (#62).
  Assert.IsTrue(ASettings.DiagnosticsProcesses);
  Assert.IsTrue(ASettings.ServerStatusWindow, 'Fenster „Atlas-Server“ (#1356) an');
  // Einrichtung mit Prüfliste (#625): beim Start zeigen, solange nicht alles grün ist; noch nie gesehen.
  Assert.IsTrue(ASettings.SetupChecklist);
  Assert.IsFalse(ASettings.SetupChecklistSeen);
  // Tastenkürzel-Übersicht (#520): Menüeintrag und Startprüfung an.
  Assert.IsTrue(ASettings.KeyOverview);
  Assert.IsTrue(ASettings.KeyStartupCheck);
  // Tastenkürzel-Tipps (#600): an, für Atlas und IDE.
  Assert.IsTrue(ASettings.ShortcutTips);
  Assert.AreEqual('all', ASettings.ShortcutTipsScope);
  // Abgesicherter Start (#722).
  Assert.IsTrue(ASettings.SafeAskAfterCrash);
  Assert.IsTrue(ASettings.SafeAutoAfterRepeatedCrash);
  Assert.AreEqual('shift', ASettings.SafeStartupKey);
  Assert.AreEqual(30000, ASettings.SafeStartupTimeoutMs);
  Assert.AreEqual(5, ASettings.SafeKeepSettingsHistory);
  // Dateiübergreifendes Zurücknehmen (#721).
  Assert.IsTrue(ASettings.UndoMultiFile);
  Assert.AreEqual(20, ASettings.UndoMultiFileDepth);
  Assert.IsTrue(ASettings.UndoMultiFilePersist);
  Assert.AreEqual(50, ASettings.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('partial', ASettings.UndoMultiFileOnConflict);
  Assert.AreEqual('recycleBin', ASettings.UndoMultiFileNewFiles);
  Assert.AreEqual($C05A, ASettings.UndoKey, 'Strg+Alt+Z');
  Assert.AreEqual($E05A, ASettings.RedoKey, 'Strg+Alt+Umschalt+Z');
  Assert.IsFalse(ASettings.UpdatesCheck, 'Update-Prüfung nur nach Zustimmung');
  // Update-Installer (#1519).
  Assert.AreEqual('ask', ASettings.UpdatesInstall);
  Assert.AreEqual('stable', ASettings.UpdatesChannel);
  Assert.AreEqual('ask', ASettings.UpdatesNewModules);
  // Modul Hilfe (#1886).
  Assert.IsTrue(ASettings.HelpEnabled, 'F1-Hilfe an');
  Assert.AreEqual(TAtlasPluginSettings.cHelpSourceOnline, ASettings.HelpSource);
  Assert.IsTrue(ASettings.DiagnosticsEditionCheck);
  Assert.IsFalse(ASettings.EditionNoticeShown);
  Assert.IsTrue(ASettings.BugReportAnonymize, 'Fehlerbericht anonymisiert');
  Assert.IsFalse(ASettings.LogNames, 'atlas.log anonym (#1478)');
  Assert.IsTrue(ASettings.PairOwners, 'Anweisungen mitfärben standardmäßig an (#653)');
  Assert.AreEqual(1, ASettings.PairGuideWidth, 'Blocklinien 1 px');
  Assert.AreEqual(75, ASettings.PairGuideOpacity, 'Blocklinien 75 % Deckkraft');
  Assert.AreEqual('deeper', ASettings.NestedRoutines, 'lokale Routinen eine Stufe tiefer (#1788)');
  Assert.IsFalse(ASettings.NestedRoutineBand, 'Band lokaler Routinen standardmäßig aus (#1788)');
  Assert.AreEqual('', ASettings.NestedRoutineColorDark, 'Farbe der Palette (#1788)');
  Assert.IsFalse(ASettings.ProblemsMessageList, 'Liste „Atlas-Probleme“ seit dem Prüffenster (#909) standardmäßig aus');
  Assert.IsTrue(ASettings.Favorites, 'Favoriten anheften standardmäßig an (#458)');
  Assert.IsTrue(ASettings.Notes, 'Notizen standardmäßig an (#545)');
  Assert.IsTrue(ASettings.BookmarksNamed, 'Benannte Lesezeichen standardmäßig an (#622)');
  Assert.IsFalse(ASettings.BookmarksShared, 'Lesezeichen standardmäßig lokal, nicht im Repository (#622)');
  Assert.AreEqual($C04B, ASettings.BookmarkKey, 'Strg+Alt+K (#622)');
end;
procedure TAtlasPluginSettingsTests.EmptyStoreGivesDefaults;
var
  mStore: IAtlasSettingsStore;
  mSettings: TAtlasPluginSettings;
begin
  mStore := TMemoryStore.Create;
  mSettings := Default(TAtlasPluginSettings);
  mSettings.Load(mStore);
  AssertEditorDefaults(mSettings);
  AssertBuildDefaults(mSettings);
  AssertDebugDefaults(mSettings);
  AssertToolDefaults(mSettings);
end;
/// <summary>Rundreise: Test aus dem Debug-Halt, Vergleich, Fenster „Atlas-Tests“ und Testlisten abweichend
/// setzen.</summary>
procedure SetRoundTripTestWindow(var ASettings: TAtlasPluginSettings);
begin
  ASettings.TestsFromDebugStop := False;
  ASettings.TestsFromDebugStopFields := False;
  ASettings.TestsFromDebugStopProperties := True;
  ASettings.TestsFromDebugStopMaxArray := 7;
  ASettings.TestsCompare := False;
  ASettings.TestsCompareFormat := False;
  ASettings.TestsCaseTable := False;
  ASettings.TestsBoundaryCases := False;
  ASettings.TestsBoundaryMax := 7;
  ASettings.TestsApprovalFiles := False;
  ASettings.TestsShowDuration := False;
  ASettings.TestsWindow := False;
  ASettings.TestsLists := False;
  ASettings.TestsListsRunKey := 0;
  ASettings.TestsSlowMs := 1000;
  ASettings.TestsLeaks := False;
  ASettings.TestsRepeatCount := 50;
  ASettings.TestsFlaky := False;
  ASettings.TestsFlakyRuns := 20;
  ASettings.TestsMutation := True;
  ASettings.TestsMutationTimeoutSec := 30;
  ASettings.TestsMutationOperators := 'boundary, not';
end;

/// <summary>Rundreise: Editor, Code Lens, Tests und Build von der Vorgabe abweichend setzen.</summary>
procedure SetRoundTripEditor(var ASettings: TAtlasPluginSettings);
begin
  ASettings.Enabled := False;
  ASettings.VisibleRows := 14;
  ASettings.ListWidth := 500;
  ASettings.PanelWidth := 400;
  ASettings.PanelCollapsed := True;
  ASettings.Learning := False;
  ASettings.Favorites := False;
  ASettings.Notes := False;
  ASettings.BookmarksNamed := False;
  ASettings.BookmarksShared := True;
  ASettings.BookmarkKey := $C04C;
  ASettings.Preview := True;
  ASettings.OpenForEdits := False;
  ASettings.InlayHints := True;
  ASettings.ActionsKey := 0;
  ASettings.ExpandKey := $4041;
  ASettings.TypeDefinitionKey := $C054;
  ASettings.MethodToggle := False;
  ASettings.MethodToggleUpKey := 0;
  ASettings.MethodToggleDownKey := $C044; // Strg+Alt+D
  ASettings.TestUnitKey := $6054;
  ASettings.CodeLensTestUnit := False;
  ASettings.CodeLensMetrics := False;
  ASettings.CodeLensTests := False;
  ASettings.TestCoverage := False;
  ASettings.TestRun := False;
  ASettings.TestsAfterBuild := True;
  ASettings.TestsBuildFirst := False;
  ASettings.TestsStale := False;
  ASettings.TestsStaleUnits := True;
  ASettings.CodeLensCoveredBy := False;
  ASettings.OwnershipHints := True;
  ASettings.OwnershipHintsOnlyProblems := True;
  ASettings.TestsCoveredByDepth := 3;
  ASettings.TestsCoveredByPrivate := True;
  ASettings.CodeLensUntested := False;
  ASettings.TestsUntestedWarnPercent := 75;
  ASettings.TestsOnSave := True;
  ASettings.TestsOnSaveMax := 12;
  ASettings.TestsFailureAtAssert := False;
  ASettings.TestsFailureInline := False;
  SetRoundTripTestWindow(ASettings);
  ASettings.BuildZeroHints := True;
  ASettings.ShowInterfaceCost := False;
  ASettings.BuildCompilerSwitches := False;
  ASettings.BuildSwitchesInStatusBar := True;
  ASettings.StartProfiles := False;
  ASettings.StartProfilesStatusField := False;
end;
/// <summary>Rundreise: Debugger, Befehle und Tasten von der Vorgabe abweichend setzen.</summary>
procedure SetRoundTripDebug(var ASettings: TAtlasPluginSettings);
begin
  ASettings.TestDebug := False;
  ASettings.TestBreakAtStart := False;
  ASettings.DebugHoverValues := False;
  ASettings.DebugExplainUnavailable := False;
  ASettings.DebugCompletionInDialogs := False;
  ASettings.DebugEvaluateWindow := False;
  ASettings.DebugEvaluateReplaceCtrlF7 := False;
  ASettings.DebugExplainAccessViolation := False;
  ASettings.DebugExplainAccessViolationAllowCalls := True;
  ASettings.DebugModuleOfAddress := False;
  ASettings.DebugDeadlocks := False;
  ASettings.DebugLeakReport := False;
  ASettings.DebugLeakReportCompare := False;
  ASettings.DebugLeakReportWindow := False;
  ASettings.DebugParallelStacks := False;
  ASettings.DebugCallStackWindow := False;
  ASettings.DebugCallStackWindowEvaluateParams := False;
  ASettings.DebugThreadsInSource := False;
  ASettings.DebugThreadFreeze := True;
  ASettings.DebugAsyncOrigin := True;
  ASettings.DebugAsyncOriginMaxPerSite := 5;
  ASettings.DebugParallelStacksWaitRoutines := 'TMonitor.Enter;MyLock.Acquire';
  ASettings.DebugParallelStacksMaxThreads := 16;
  ASettings.DebugExceptionHistory := False;
  ASettings.DebugJustMyCode := False;
  ASettings.DebugExceptionBanner := True;
  ASettings.DebugExceptionBannerIgnoreAtLocation := False;
  ASettings.DebugInlineValues := False;
  ASettings.DebugInlineValuesPerLine := 7;
  ASettings.DebugMemoryTimeline := False;
  ASettings.DebugMemoryTimelineIntervalMs := 2500;
  ASettings.DebugProfiler := True;
  ASettings.DebugProfilerIntervalMs := 25;
  ASettings.DebugMemoryTimelineObjectCount := True;
  ASettings.DebugWhyHere := False;
  ASettings.DebugWhyHereDepth := 6;
  ASettings.DebugVariablesWindow := False;
  ASettings.DebugVariablesSearchDepth := 5;
  ASettings.DebugVariablesSearchLimit := 250;
  ASettings.DebugPredictConditions := False;
  ASettings.DebugPredictDimSkipped := False;
  ASettings.DebugPredictLines := 40;
  ASettings.DebugEditValues := False;
  ASettings.DebugHoverExpand := False;
  ASettings.DebugHoverChanges := False;
  ASettings.DebugHoverMaxChildren := 250;
  ASettings.DebugPinnedValues := False;
  ASettings.DebugOwnCodeFolders := '  C:\Komponenten;D:\Lib ';
  ASettings.TodoList := False;
  ASettings.MetricsReport := False;
  ASettings.TeamFile := False;
  ASettings.McpBuild := False;
  ASettings.BaselineUpdate := False;
  ASettings.EditorKeysPriority := True;
  ASettings.SlashCommands := False;
  ASettings.Snippets := False;
  ASettings.ImportIdeTemplates := False;
  ASettings.ServerPath := '  D:\Atlas\AtlasServer.exe ';
  ASettings.SignatureKey := $6048; // Strg+Umschalt+H
  ASettings.SignatureKeyPriority := True;
  ASettings.CompletionKey := $4020; // Strg+Leer
  ASettings.ProviderTimeLimitMs := 350;
  ASettings.QuickToggleKey := $6051;
  ASettings.QuickToggleKeyPriority := True;
  ASettings.DiagnosticMode := True;
end;
/// <summary>Rundreise: Diagnose, Start, Zurücknehmen und Blocklinien von der Vorgabe abweichend setzen.</summary>
procedure SetRoundTripTools(var ASettings: TAtlasPluginSettings);
begin
  ASettings.DiagnosticModeKey := $6044;
  ASettings.DiagnosticModeKeyPriority := True;
  ASettings.DiagnosticsProcesses := False;
  ASettings.ServerStatusWindow := False;
  ASettings.SetupChecklist := False;
  ASettings.SetupChecklistSeen := True;
  ASettings.KeyOverview := False;
  ASettings.KeyStartupCheck := False;
  ASettings.ShortcutTips := False;
  ASettings.ShortcutTipsScope := 'atlas';
  ASettings.SafeAskAfterCrash := False;
  ASettings.SafeAutoAfterRepeatedCrash := False;
  ASettings.SafeStartupKey := 'none';
  ASettings.SafeStartupTimeoutMs := 30000;
  ASettings.SafeKeepSettingsHistory := 0;
  ASettings.UndoMultiFile := False;
  ASettings.UndoMultiFileDepth := 7;
  ASettings.UndoMultiFilePersist := False;
  ASettings.UndoMultiFileMaxSizeMb := 3;
  ASettings.UndoMultiFileOnConflict := 'abort';
  ASettings.UndoMultiFileNewFiles := 'keep';
  ASettings.UndoKey := 0;
  ASettings.RedoKey := $C059;
  ASettings.UpdatesCheck := True;
  ASettings.UpdatesInstall := 'auto';
  ASettings.UpdatesChannel := 'prerelease';
  ASettings.UpdatesNewModules := 'skip';
  ASettings.HelpEnabled := False;
  ASettings.HelpSource := TAtlasPluginSettings.cHelpSourceLocal;
  ASettings.DiagnosticsEditionCheck := False;
  ASettings.EditionNoticeShown := True;
  ASettings.BugReportAnonymize := False;
  ASettings.LogNames := True;
  ASettings.ProblemsMessageList := True;
  ASettings.PairOwners := False;
  ASettings.PairGuideWidth := 3;
  ASettings.PairGuideOpacity := 80;
  ASettings.PairColorsDark := '#112233, #445566,#778899,#aabbcc,#DDEEFF';
  ASettings.NestedRoutines := 'color';
  ASettings.NestedRoutineBand := True;
  ASettings.NestedRoutineColorLight := ' #a85a00 ';
end;
/// <summary>Rundreise: Test aus dem Debug-Halt, Vergleich, Fenster „Atlas-Tests“ und Testlisten gelesen.</summary>
procedure AssertRoundTripTestWindow(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsFalse(ALoaded.TestsFromDebugStop, 'tests.fromDebugStop (#1873)');
  Assert.IsFalse(ALoaded.TestsFromDebugStopFields, 'tests.fromDebugStop.fields (#1873)');
  Assert.IsTrue(ALoaded.TestsFromDebugStopProperties, 'tests.fromDebugStop.properties (#1873)');
  Assert.AreEqual(7, ALoaded.TestsFromDebugStopMaxArray, 'tests.fromDebugStop.maxArray (#1873)');
  Assert.IsFalse(ALoaded.TestsCompare, 'tests.compare (#1779)');
  Assert.IsFalse(ALoaded.TestsCompareFormat, 'tests.compare.format (#1779)');
  Assert.IsFalse(ALoaded.TestsCaseTable, 'tests.testCaseTable (#1879)');
  Assert.IsFalse(ALoaded.TestsBoundaryCases, 'tests.boundaryCases (#2173)');
  Assert.AreEqual(7, ALoaded.TestsBoundaryMax, 'tests.boundaryCases.maxCases (#2173)');
  Assert.IsFalse(ALoaded.TestsApprovalFiles, 'tests.approvalFiles (#1881)');
  Assert.IsFalse(ALoaded.TestsShowDuration, 'tests.showDuration (#1772)');
  Assert.IsFalse(ALoaded.TestsWindow, 'tests.window (#1776)');
  Assert.IsFalse(ALoaded.TestsLists, 'tests.lists (#2167)');
  Assert.AreEqual(0, ALoaded.TestsListsRunKey, 'tests.lists.runKey (#2167)');
  Assert.AreEqual(1000, ALoaded.TestsSlowMs, 'tests.slowMs (#1772)');
  Assert.IsFalse(ALoaded.TestsLeaks, 'tests.leaks (#1774)');
  Assert.AreEqual(50, ALoaded.TestsRepeatCount, 'tests.repeat.count (#1782)');
  Assert.IsFalse(ALoaded.TestsFlaky, 'tests.flaky (#1773)');
  Assert.AreEqual(20, ALoaded.TestsFlakyRuns, 'tests.flaky.runs (#1773)');
  Assert.IsTrue(ALoaded.TestsMutation, 'tests.mutation (#1460)');
  Assert.AreEqual(30, ALoaded.TestsMutationTimeoutSec, 'tests.mutation.timeoutSec (#1460)');
  Assert.AreEqual('boundary, not', ALoaded.TestsMutationOperators, 'tests.mutation.operators (#1460)');
end;

/// <summary>Rundreise: Editor, Code Lens, Tests und Build gelesen.</summary>
procedure AssertRoundTripEditor(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsFalse(ALoaded.Enabled);
  Assert.AreEqual(14, ALoaded.VisibleRows);
  Assert.AreEqual(500, ALoaded.ListWidth);
  Assert.AreEqual(400, ALoaded.PanelWidth);
  Assert.IsTrue(ALoaded.PanelCollapsed);
  Assert.IsFalse(ALoaded.Learning);
  Assert.IsFalse(ALoaded.Favorites, 'Favoriten abschaltbar (#458)');
  Assert.IsFalse(ALoaded.Notes, 'Notizen abschaltbar (#545)');
  Assert.IsFalse(ALoaded.BookmarksNamed, 'Benannte Lesezeichen abschaltbar (#622)');
  Assert.IsTrue(ALoaded.BookmarksShared, 'Lesezeichen für das Team (#622)');
  Assert.AreEqual($C04C, ALoaded.BookmarkKey);
  Assert.IsTrue(ALoaded.Preview);
  Assert.IsFalse(ALoaded.OpenForEdits);
  Assert.IsTrue(ALoaded.InlayHints);
  Assert.AreEqual(0, ALoaded.ActionsKey, '0 = keine Taste');
  Assert.AreEqual($4041, ALoaded.ExpandKey);
  Assert.AreEqual($6057, ALoaded.ShrinkKey);
  Assert.AreEqual($C054, ALoaded.TypeDefinitionKey);
  Assert.IsFalse(ALoaded.MethodToggle);
  Assert.AreEqual(0, ALoaded.MethodToggleUpKey, '0 = keine Taste');
  Assert.AreEqual($C044, ALoaded.MethodToggleDownKey);
  Assert.AreEqual($6054, ALoaded.TestUnitKey);
  Assert.IsFalse(ALoaded.CodeLensTestUnit);
  Assert.IsFalse(ALoaded.CodeLensMetrics);
  Assert.IsFalse(ALoaded.CodeLensTests);
  Assert.IsFalse(ALoaded.TestCoverage, 'tests.coverage (#275)');
  Assert.IsFalse(ALoaded.TestRun);
  Assert.IsTrue(ALoaded.TestsAfterBuild);
  Assert.IsFalse(ALoaded.TestsBuildFirst);
  Assert.IsFalse(ALoaded.TestsStale, 'tests.stale (#1770)');
  Assert.IsTrue(ALoaded.TestsStaleUnits, 'tests.stale.units (#1770)');
  Assert.IsFalse(ALoaded.CodeLensCoveredBy, 'codeLens.coveredBy (#1778)');
  Assert.IsTrue(ALoaded.OwnershipHints, 'editor.ownershipHints (#1877)');
  Assert.IsTrue(ALoaded.OwnershipHintsOnlyProblems, 'editor.ownershipHints.onlyProblems (#1877)');
  Assert.AreEqual(3, ALoaded.TestsCoveredByDepth, 'tests.coveredBy.depth (#1778)');
  Assert.IsTrue(ALoaded.TestsCoveredByPrivate, 'tests.coveredBy.private (#1778)');
  Assert.IsFalse(ALoaded.CodeLensUntested, 'codeLens.untested (#1783)');
  Assert.AreEqual(75, ALoaded.TestsUntestedWarnPercent, 'tests.untested.warnPercent (#1783)');
  Assert.IsTrue(ALoaded.TestsOnSave, 'tests.onSave (#1775)');
  Assert.AreEqual(12, ALoaded.TestsOnSaveMax, 'tests.onSave.max (#1775)');
  Assert.IsFalse(ALoaded.TestsFailureAtAssert, 'tests.failureAtAssert (#1771)');
  Assert.IsFalse(ALoaded.TestsFailureInline, 'tests.failureInline (#1771)');
  AssertRoundTripTestWindow(ALoaded);
  Assert.IsTrue(ALoaded.BuildZeroHints);
  Assert.IsFalse(ALoaded.ShowInterfaceCost, 'build.showInterfaceCost (#554)');
  Assert.IsFalse(ALoaded.BuildCompilerSwitches);
  Assert.IsTrue(ALoaded.BuildSwitchesInStatusBar);
  Assert.IsFalse(ALoaded.StartProfiles);
  Assert.IsFalse(ALoaded.StartProfilesStatusField);
end;
/// <summary>Rundreise: Debugger, Befehle und Blocklinien gelesen.</summary>
procedure AssertRoundTripDebug(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsFalse(ALoaded.TestDebug, 'Test debuggen (#585)');
  Assert.IsFalse(ALoaded.TestBreakAtStart, 'debug.testBreakAtStart (#585)');
  Assert.IsFalse(ALoaded.DebugHoverValues, 'debug.hoverValues (#891)');
  Assert.IsFalse(ALoaded.DebugExplainUnavailable, 'debug.explainUnavailable (#840)');
  Assert.IsFalse(ALoaded.DebugCompletionInDialogs, 'debug.completionInDialogs (#538)');
  Assert.IsFalse(ALoaded.DebugEvaluateWindow, 'debug.evaluateWindow (#784)');
  Assert.IsFalse(ALoaded.DebugEvaluateReplaceCtrlF7, 'debug.evaluateWindow.replaceCtrlF7 (#784)');
  Assert.IsFalse(ALoaded.DebugExplainAccessViolation, 'debug.explainAccessViolation (#865)');
  Assert.IsTrue(ALoaded.DebugExplainAccessViolationAllowCalls, 'debug.explainAccessViolation.allowCalls (#865)');
  Assert.AreEqual('TMonitor.Enter;MyLock.Acquire', ALoaded.DebugParallelStacksWaitRoutines);
  Assert.AreEqual(16, ALoaded.DebugParallelStacksMaxThreads);
  Assert.IsTrue(ALoaded.DebugThreadFreeze, 'debug.threadFreeze (#852)');
  Assert.IsTrue(ALoaded.DebugAsyncOrigin, 'debug.asyncOrigin (#859)');
  Assert.AreEqual(5, ALoaded.DebugAsyncOriginMaxPerSite);
  Assert.IsFalse(ALoaded.DebugThreadsInSource, 'debug.threadsInSource (#852)');
  Assert.IsFalse(ALoaded.DebugParallelStacks, 'debug.parallelStacks (#837)');
  Assert.IsFalse(ALoaded.DebugCallStackWindow, 'debug.callStackWindow (#843)');
  Assert.IsFalse(ALoaded.DebugCallStackWindowEvaluateParams, 'debug.callStackWindow.evaluateParams (#843)');
  Assert.IsFalse(ALoaded.DebugDeadlocks, 'debug.deadlocks (#587)');
  Assert.IsFalse(ALoaded.DebugLeakReport, 'debug.leakReport (#1875)');
  Assert.IsFalse(ALoaded.DebugLeakReportCompare, 'debug.leakReport.compare (#1875)');
  Assert.IsFalse(ALoaded.DebugLeakReportWindow, 'debug.leakReport.window (#1875)');
  Assert.IsFalse(ALoaded.DebugModuleOfAddress, 'debug.moduleOfAddress (#1820)');

  Assert.IsFalse(ALoaded.DebugExceptionHistory, 'debug.exceptionHistory (#517)');
  Assert.IsFalse(ALoaded.DebugJustMyCode, 'debug.justMyCode (#578)');
  Assert.IsTrue(ALoaded.DebugExceptionBanner, 'debug.exceptionBanner (#783)');
  Assert.IsFalse(ALoaded.DebugExceptionBannerIgnoreAtLocation, 'debug.exceptionBanner.ignoreAtLocation (#783)');
  Assert.IsFalse(ALoaded.DebugInlineValues, 'debug.inlineValues (#508)');
  Assert.AreEqual(7, ALoaded.DebugInlineValuesPerLine, 'debug.inlineValuesPerLine (#508)');
  Assert.IsFalse(ALoaded.DebugMemoryTimeline, 'debug.memoryTimeline (#858)');
  Assert.AreEqual(2500, ALoaded.DebugMemoryTimelineIntervalMs, 'debug.memoryTimeline.intervalMs (#858)');
  Assert.IsTrue(ALoaded.DebugProfiler, 'debug.profiler (#2057)');
  Assert.AreEqual(25, ALoaded.DebugProfilerIntervalMs, 'debug.profiler.intervalMs (#2057)');
  Assert.IsTrue(ALoaded.DebugMemoryTimelineObjectCount, 'debug.memoryTimeline.objectCount (#858)');
  Assert.IsFalse(ALoaded.DebugWhyHere, 'debug.whyHere (#1878)');
  Assert.AreEqual(6, ALoaded.DebugWhyHereDepth, 'debug.whyHere.depth (#1878)');
  Assert.IsFalse(ALoaded.DebugVariablesWindow, 'debug.variablesWindow (#853)');
  Assert.AreEqual(5, ALoaded.DebugVariablesSearchDepth, 'debug.variablesWindow.searchDepth (#853)');
  Assert.AreEqual(250, ALoaded.DebugVariablesSearchLimit, 'debug.variablesWindow.searchLimit (#853)');
  Assert.IsFalse(ALoaded.DebugPredictConditions, 'debug.predictConditions (#2169)');
  Assert.IsFalse(ALoaded.DebugPredictDimSkipped, 'debug.predictConditions.dimSkipped (#2169)');
  Assert.AreEqual(40, ALoaded.DebugPredictLines, 'debug.predictConditions.lines (#2169)');
  Assert.IsFalse(ALoaded.DebugEditValues, 'debug.editValues (#868)');
  Assert.IsFalse(ALoaded.DebugHoverExpand, 'debug.hoverExpand (#895)');
  Assert.IsFalse(ALoaded.DebugHoverChanges, 'debug.hoverChanges (#895)');
  Assert.AreEqual(250, ALoaded.DebugHoverMaxChildren, 'debug.hoverMaxChildren (#895)');
  Assert.IsFalse(ALoaded.DebugPinnedValues, 'debug.pinnedValues (#526)');
  Assert.AreEqual('C:\Komponenten;D:\Lib', ALoaded.DebugOwnCodeFolders, 'debug.ownCodeFolders ohne Leerraum (#578)');
  Assert.IsFalse(ALoaded.TodoList);
  Assert.IsFalse(ALoaded.MetricsReport);
  Assert.IsFalse(ALoaded.TeamFile);
  Assert.IsFalse(ALoaded.McpBuild);
  Assert.IsFalse(ALoaded.BaselineUpdate);
  Assert.IsTrue(ALoaded.EditorKeysPriority);
  Assert.IsFalse(ALoaded.SlashCommands);
  Assert.IsFalse(ALoaded.Snippets);
  Assert.IsFalse(ALoaded.ImportIdeTemplates);
  Assert.IsFalse(ALoaded.PairOwners);
  Assert.AreEqual(3, ALoaded.PairGuideWidth);
  Assert.AreEqual(80, ALoaded.PairGuideOpacity);
  Assert.AreEqual('#112233,#445566,#778899,#AABBCC,#DDEEFF', ALoaded.PairColorsDark, 'einheitlich geschrieben');
  Assert.AreEqual('color', ALoaded.NestedRoutines);
  Assert.IsTrue(ALoaded.NestedRoutineBand);
  Assert.AreEqual('#A85A00', ALoaded.NestedRoutineColorLight, 'einheitlich geschrieben');
  Assert.IsTrue(ALoaded.ProblemsMessageList, 'Liste „Atlas-Probleme“ eingeschaltet');
end;
/// <summary>Rundreise: Serverpfad, Tasten, Diagnose, Start und Zurücknehmen gelesen.</summary>
procedure AssertRoundTripTools(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsTrue(ALoaded.Problems, 'Wellenlinien bleiben an');
  Assert.AreEqual('D:\Atlas\AtlasServer.exe', ALoaded.ServerPath, 'Serverpfad ohne Leerraum');
  Assert.AreEqual($6048, ALoaded.SignatureKey);
  Assert.IsTrue(ALoaded.SignatureKeyPriority);
  Assert.AreEqual($4020, ALoaded.CompletionKey);
  Assert.IsFalse(ALoaded.CompletionKeyPriority);
  Assert.AreEqual(350, ALoaded.ProviderTimeLimitMs);
  Assert.AreEqual($6051, ALoaded.QuickToggleKey);
  Assert.IsTrue(ALoaded.QuickToggleKeyPriority);
  Assert.IsTrue(ALoaded.DiagnosticMode);
  Assert.AreEqual($6044, ALoaded.DiagnosticModeKey);
  Assert.IsTrue(ALoaded.DiagnosticModeKeyPriority);
  Assert.IsFalse(ALoaded.DiagnosticsProcesses);
  Assert.IsFalse(ALoaded.ServerStatusWindow);
  Assert.IsFalse(ALoaded.SetupChecklist);
  Assert.IsTrue(ALoaded.SetupChecklistSeen);
  Assert.IsFalse(ALoaded.KeyOverview);
  Assert.IsFalse(ALoaded.KeyStartupCheck);
  Assert.IsFalse(ALoaded.ShortcutTips);
  Assert.AreEqual('atlas', ALoaded.ShortcutTipsScope);
  Assert.IsFalse(ALoaded.SafeAskAfterCrash);
  Assert.IsFalse(ALoaded.SafeAutoAfterRepeatedCrash);
  Assert.AreEqual('none', ALoaded.SafeStartupKey);
  Assert.AreEqual(30000, ALoaded.SafeStartupTimeoutMs);
  Assert.AreEqual(0, ALoaded.SafeKeepSettingsHistory);
  Assert.IsFalse(ALoaded.UndoMultiFile);
  Assert.AreEqual(7, ALoaded.UndoMultiFileDepth);
  Assert.IsFalse(ALoaded.UndoMultiFilePersist);
  Assert.AreEqual(3, ALoaded.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('abort', ALoaded.UndoMultiFileOnConflict);
  Assert.AreEqual('keep', ALoaded.UndoMultiFileNewFiles);
  Assert.AreEqual(0, ALoaded.UndoKey);
  Assert.AreEqual($C059, ALoaded.RedoKey);
  Assert.IsTrue(ALoaded.UpdatesCheck);
  Assert.AreEqual('auto', ALoaded.UpdatesInstall);
  Assert.AreEqual('prerelease', ALoaded.UpdatesChannel);
  Assert.AreEqual('skip', ALoaded.UpdatesNewModules);
  Assert.IsFalse(ALoaded.HelpEnabled);
  Assert.AreEqual(TAtlasPluginSettings.cHelpSourceLocal, ALoaded.HelpSource);
  Assert.IsFalse(ALoaded.DiagnosticsEditionCheck);
  Assert.IsTrue(ALoaded.EditionNoticeShown);
  Assert.IsFalse(ALoaded.BugReportAnonymize);
  Assert.IsTrue(ALoaded.LogNames);
end;
procedure TAtlasPluginSettingsTests.SaveAndLoadRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mStore := TMemoryStore.Create;
  mSettings := TAtlasPluginSettings.Defaults;
  SetRoundTripEditor(mSettings);
  SetRoundTripDebug(mSettings);
  SetRoundTripTools(mSettings);
  mSettings.Save(mStore);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  AssertRoundTripEditor(mLoaded);
  AssertRoundTripDebug(mLoaded);
  AssertRoundTripTools(mLoaded);
  Assert.AreEqual('', TAtlasPluginSettings.Defaults.ServerPath, 'Standard: leer');
end;
procedure TAtlasPluginSettingsTests.IndexOptionsGoToGlobalFile;
var
  mRegistry: IAtlasSettingsStore;
  mStore: TAtlasRoutedSettingsStore;
  mKeep: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  // Index und Speicher gelten für alle Projekte und stehen in settings.json (#652), nicht in der Registry.
  mRegistry := TMemoryStore.Create;
  mStore := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mKeep := mStore;
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.IndexSearchPaths := False;
  mSettings.IndexLibraryPaths := True;
  mSettings.IndexUsages := False;
  mSettings.MemoryBudgetMb := 512;
  mSettings.Save(mStore);
  Assert.AreEqual(-1, mRegistry.ReadInteger('IndexSearchPaths', -1), 'nicht in der Registry');
  Assert.Contains(mStore.Text, '"searchPaths": false');
  Assert.Contains(mStore.Text, '"libraryPaths": true');
  Assert.Contains(mStore.Text, '"memoryBudgetMb": 512');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.IndexProjectGroup);
  Assert.IsFalse(mLoaded.IndexSearchPaths);
  Assert.IsTrue(mLoaded.IndexLibraryPaths);
  Assert.IsFalse(mLoaded.IndexUsages);
  Assert.AreEqual(512, mLoaded.MemoryBudgetMb);
  // Speichergrenze (#492): 0 = unbegrenzt, nicht negativ, höchstens 64 GB.
  mStore.WriteInteger('MemoryBudgetMb', -5);
  mLoaded.Load(mStore);
  Assert.AreEqual(0, mLoaded.MemoryBudgetMb);
  mStore.WriteInteger('MemoryBudgetMb', 999999);
  mLoaded.Load(mStore);
  Assert.AreEqual(TAtlasPluginSettings.cMaxMemoryBudgetMb, mLoaded.MemoryBudgetMb);
end;
procedure TAtlasPluginSettingsTests.XmlDocOptionsGoToGlobalFile;
var
  mStore, mInner: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  // #654, #770: XmlDocExpand/XmlDocMaxLines als hints in settings.json.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('last', mSettings.XmlDocExpand);
  Assert.AreEqual(0, mSettings.XmlDocMaxLines);
  mRouted := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, '');
  mStore := mRouted;
  mSettings.XmlDocExpand := 'collapsed';
  mSettings.XmlDocMaxLines := 12;
  mSettings.Save(mStore);
  Assert.AreEqual('collapsed', mStore.ReadString('XmlDocExpand', ''));
  Assert.AreEqual(12, mStore.ReadInteger('XmlDocMaxLines', 0));
  Assert.Contains(mRouted.Text, '"xmlDocExpand": "collapsed"');
  Assert.Contains(mRouted.Text, '"xmlDocMaxLines": 12');
  Assert.IsFalse(mRouted.Text.Contains('xmlDocFull'), mRouted.Text);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.AreEqual('collapsed', mLoaded.XmlDocExpand);
  Assert.AreEqual(12, mLoaded.XmlDocMaxLines);
  // Unbekannter Wert: Vorgabe.
  mStore.WriteString('XmlDocExpand', 'halb');
  mLoaded.Load(mStore);
  Assert.AreEqual('last', mLoaded.XmlDocExpand);
  // Vor #770: xmlDocFull aus settings.json bzw. der Registry wird übernommen, aber nie geschrieben.
  mRouted := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, '{"hints": {"xmlDocFull": true}}');
  mStore := mRouted;
  mLoaded.Load(mStore);
  Assert.AreEqual('expanded', mLoaded.XmlDocExpand);
  mStore.WriteInteger('XmlDocFull', 0);
  Assert.Contains(mRouted.Text, '"xmlDocFull": true');
  mInner := TMemoryStore.Create;
  mInner.WriteInteger('XmlDocFull', 0);
  mRouted := TAtlasRoutedSettingsStore.Create(mInner, '');
  mStore := mRouted;
  mRouted.Migrate;
  mLoaded.Load(mStore);
  Assert.AreEqual('collapsed', mLoaded.XmlDocExpand);
  Assert.IsFalse(mRouted.Text.Contains('xmlDocFull'), mRouted.Text);
  // Grenzen 0..50.
  mStore.WriteInteger('XmlDocMaxLines', 99);
  mLoaded.Load(mStore);
  Assert.AreEqual(TAtlasPluginSettings.cMaxXmlDocLines, mLoaded.XmlDocMaxLines);
  mStore.WriteInteger('XmlDocMaxLines', -3);
  mLoaded.Load(mStore);
  Assert.AreEqual(0, mLoaded.XmlDocMaxLines);
end;
procedure TAtlasPluginSettingsTests.HoverMembersMaxLinesRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual(15, mSettings.HoverMembersMaxLines);
  mStore := TMemoryStore.Create;
  mSettings.HoverMembersMaxLines := 8;
  mSettings.Save(mStore);
  Assert.AreEqual(8, mStore.ReadInteger('HoverMembersMaxLines', 0));
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.AreEqual(8, mLoaded.HoverMembersMaxLines);
  mStore.WriteInteger('HoverMembersMaxLines', 500);
  mLoaded.Load(mStore);
  Assert.AreEqual(TAtlasPluginSettings.cMaxHoverMembersLines, mLoaded.HoverMembersMaxLines);
  mStore.WriteInteger('HoverMembersMaxLines', -1);
  mLoaded.Load(mStore);
  Assert.AreEqual(0, mLoaded.HoverMembersMaxLines);
end;

procedure TAtlasPluginSettingsTests.TestsLogRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.TestsLog);
  Assert.AreEqual(2000, mSettings.TestsLogMaxLines);
  mStore := TMemoryStore.Create;
  mSettings.TestsLog := False;
  mSettings.TestsLogMaxLines := 500;
  mSettings.Save(mStore);
  Assert.AreEqual(0, mStore.ReadInteger('TestsLog', 1));
  Assert.AreEqual(500, mStore.ReadInteger('TestsLogMaxLines', 0));
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.TestsLog);
  Assert.AreEqual(500, mLoaded.TestsLogMaxLines);
  mStore.WriteInteger('TestsLogMaxLines', 10);
  mLoaded.Load(mStore);
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsLogMaxLines, mLoaded.TestsLogMaxLines);
  mStore.WriteInteger('TestsLogMaxLines', 1000000);
  mLoaded.Load(mStore);
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsLogMaxLines, mLoaded.TestsLogMaxLines);
end;

procedure TAtlasPluginSettingsTests.HoverSignatureParamsRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.HoverSignatureParams);
  mStore := TMemoryStore.Create;
  mSettings.HoverSignatureParams := False;
  mSettings.Save(mStore);
  Assert.AreEqual(0, mStore.ReadInteger('HoverSignatureParams', 1));
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.HoverSignatureParams);
end;

procedure TAtlasPluginSettingsTests.HoverExplainMessagesRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.HoverExplainMessages);
  mStore := TMemoryStore.Create;
  mSettings.HoverExplainMessages := False;
  mSettings.Save(mStore);
  Assert.AreEqual(0, mStore.ReadInteger('HoverExplainMessages', 1));
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.HoverExplainMessages);
end;

procedure TAtlasPluginSettingsTests.HoverRuleExamplesRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.HoverRuleExamples);
  mStore := TMemoryStore.Create;
  mSettings.HoverRuleExamples := False;
  mSettings.Save(mStore);
  Assert.AreEqual(0, mStore.ReadInteger('HoverRuleExamples', 1));
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.HoverRuleExamples);
end;

procedure TAtlasPluginSettingsTests.IdeErrorsRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(mSettings.ProblemsIdeErrors, 'Vorgabe aus');
  mStore := TMemoryStore.Create;
  mSettings.ProblemsIdeErrors := True;
  mSettings.Save(mStore);
  Assert.AreEqual(1, mStore.ReadInteger('ProblemsIdeErrors', 0));
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.ProblemsIdeErrors);
end;

procedure TAtlasPluginSettingsTests.TrackLinesRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.TrackLines);
  mStore := TMemoryStore.Create;
  mSettings.TrackLines := False;
  mSettings.Save(mStore);
  Assert.AreEqual(0, mStore.ReadInteger('TrackLines', 1));
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.TrackLines);
end;

procedure TAtlasPluginSettingsTests.LearnedSuggestionsRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.SuggestionsLearned);
  Assert.AreEqual(300, mSettings.SuggestionsDelayMs);
  Assert.AreEqual(70, mSettings.SuggestionsMinShare);
  Assert.AreEqual(5, mSettings.SuggestionsMinCount);
  Assert.IsTrue(mSettings.SuggestionsLearnFromUsage);
  mStore := TMemoryStore.Create;
  mSettings.SuggestionsLearned := False;
  mSettings.SuggestionsDelayMs := 500;
  mSettings.SuggestionsMinShare := 80;
  mSettings.SuggestionsMinCount := 3;
  mSettings.SuggestionsLearnFromUsage := False;
  mSettings.Save(mStore);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.SuggestionsLearned);
  Assert.AreEqual(500, mLoaded.SuggestionsDelayMs);
  Assert.AreEqual(80, mLoaded.SuggestionsMinShare);
  Assert.AreEqual(3, mLoaded.SuggestionsMinCount);
  Assert.IsFalse(mLoaded.SuggestionsLearnFromUsage);
  mStore.WriteInteger('SuggestionsDelayMs', 10);
  mStore.WriteInteger('SuggestionsMinShare', 20);
  mStore.WriteInteger('SuggestionsMinCount', 1000);
  mLoaded.Load(mStore);
  Assert.AreEqual(100, mLoaded.SuggestionsDelayMs);
  Assert.AreEqual(50, mLoaded.SuggestionsMinShare);
  Assert.AreEqual(100, mLoaded.SuggestionsMinCount);
end;

procedure TAtlasPluginSettingsTests.ProjectContextMenuRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.ProjectContextMenu);
  mStore := TMemoryStore.Create;
  mSettings.ProjectContextMenu := False;
  mSettings.Save(mStore);
  Assert.AreEqual(0, mStore.ReadInteger('ProjectContextMenu', 1));
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.ProjectContextMenu);
end;

procedure TAtlasPluginSettingsTests.GalleryWizardsRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.GalleryWizards);
  mStore := TMemoryStore.Create;
  mSettings.GalleryWizards := False;
  mSettings.Save(mStore);
  Assert.AreEqual(0, mStore.ReadInteger('GalleryWizards', 1));
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.GalleryWizards);
end;

procedure TAtlasPluginSettingsTests.EditorContextMenuRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.EditorContextMenuContextual);
  Assert.AreEqual('navigation,edit,analysis,findings,debug,tests,notes', mSettings.EditorContextMenuGroups);
  mSettings.EditorContextMenuContextual := False;
  mSettings.EditorContextMenuGroups := 'notes; quatsch, Debug';
  mSettings.Normalize;
  Assert.AreEqual('debug,notes', mSettings.EditorContextMenuGroups);
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.EditorContextMenuContextual);
  Assert.AreEqual('debug,notes', mLoaded.EditorContextMenuGroups);
end;

procedure TAtlasPluginSettingsTests.AcceptOptionsRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  // ARG-046 (#227): Commit-Zeichen, uses, Parameter-Hint, Verzögerung bis zum Öffnen.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.CommitCharacters);
  Assert.IsTrue(mSettings.AutoUses);
  Assert.IsTrue(mSettings.ParameterHints);
  Assert.IsTrue(mSettings.FormatPlaceholders);
  Assert.AreEqual(150, mSettings.OpenDelayMs);
  // Auswahl mit Rahmen und Marke (#447).
  Assert.IsTrue(mSettings.SelectionMarker);
  mStore := TMemoryStore.Create;
  mSettings.CommitCharacters := False;
  mSettings.SelectionMarker := False;
  mSettings.AutoUses := False;
  mSettings.ParameterHints := False;
  mSettings.FormatPlaceholders := False;
  mSettings.OpenDelayMs := 400;
  mSettings.Save(mStore);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.CommitCharacters);
  Assert.IsFalse(mLoaded.SelectionMarker);
  Assert.IsFalse(mLoaded.AutoUses);
  Assert.IsFalse(mLoaded.ParameterHints);
  Assert.IsFalse(mLoaded.FormatPlaceholders);
  Assert.AreEqual(400, mLoaded.OpenDelayMs);
  mStore.WriteInteger('OpenDelayMs', 99999);
  mLoaded.Load(mStore);
  Assert.AreEqual(TAtlasPluginSettings.cMaxOpenDelay, mLoaded.OpenDelayMs);
  mStore.WriteInteger('OpenDelayMs', -1);
  mLoaded.Load(mStore);
  Assert.AreEqual(0, mLoaded.OpenDelayMs);
end;
procedure TAtlasPluginSettingsTests.ClampsOutOfRangeValues;
var
  mStore: IAtlasSettingsStore;
  mSettings: TAtlasPluginSettings;
begin
  mStore := TMemoryStore.Create;
  mStore.WriteInteger('VisibleRows', 99);
  mStore.WriteInteger('ListWidth', 50);
  mStore.WriteInteger('PanelWidth', 5000);
  mStore.WriteInteger('SignatureKey', -3);
  mStore.WriteInteger('ProviderTimeLimitMs', 10);
  mStore.WriteInteger('SafeStartupTimeoutMs', 5);
  mStore.WriteInteger('SafeKeepSettingsHistory', 1000);
  mStore.WriteString('SafeStartupKey', ' Alt ');
  mStore.WriteInteger('UndoMultiFileDepth', 0);
  mStore.WriteInteger('UndoMultiFileMaxSizeMb', 100000);
  mStore.WriteString('UndoMultiFileOnConflict', ' ABORT ');
  mStore.WriteString('UndoMultiFileNewFiles', 'irgendwas');
  mStore.WriteString('ShortcutTipsScope', ' ATLAS ');
  mSettings := Default(TAtlasPluginSettings);
  mSettings.Load(mStore);
  Assert.AreEqual(TAtlasPluginSettings.cMinProviderTimeLimit, mSettings.ProviderTimeLimitMs);
  Assert.AreEqual(0, mSettings.SignatureKey, 'kein gültiges Kürzel');
  mStore.WriteInteger('PairGuideWidth', 7);
  mStore.WriteInteger('PairGuideOpacity', 0);
  mStore.WriteString('PairColorsLight', '#123456,blau');
  mStore.WriteString('NestedRoutines', 'irgendwie');
  mStore.WriteString('NestedRoutineColorDark', 'blau');
  mSettings := Default(TAtlasPluginSettings);
  mSettings.Load(mStore);
  Assert.AreEqual(TAtlasPluginSettings.cMaxPairGuideWidth, mSettings.PairGuideWidth);
  Assert.AreEqual(TAtlasPluginSettings.cMinPairGuideOpacity, mSettings.PairGuideOpacity);
  Assert.AreEqual('', mSettings.PairColorsLight, 'ungültige Farben = Standard');
  Assert.AreEqual('deeper', mSettings.NestedRoutines, 'unbekannte Färbung = Vorgabe (#1788)');
  Assert.AreEqual('', mSettings.NestedRoutineColorDark, 'ungültige Farbe = Palette (#1788)');
  Assert.AreEqual(TAtlasPluginSettings.cMaxVisibleRows, mSettings.VisibleRows);
  Assert.AreEqual(TAtlasPluginSettings.cMinListWidth, mSettings.ListWidth);
  Assert.AreEqual(TAtlasPluginSettings.cMaxPanelWidth, mSettings.PanelWidth);
  Assert.AreEqual(TAtlasPluginSettings.cMinSafeStartupTimeout, mSettings.SafeStartupTimeoutMs);
  Assert.AreEqual(TAtlasPluginSettings.cMaxSafeSettingsHistory, mSettings.SafeKeepSettingsHistory);
  Assert.AreEqual('shift', mSettings.SafeStartupKey, 'unbekannte Taste: Umschalt');
  Assert.AreEqual(TAtlasPluginSettings.cMinUndoDepth, mSettings.UndoMultiFileDepth);
  Assert.AreEqual(TAtlasPluginSettings.cMaxUndoMaxSizeMb, mSettings.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('abort', mSettings.UndoMultiFileOnConflict);
  Assert.AreEqual('recycleBin', mSettings.UndoMultiFileNewFiles, 'unbekannt: Papierkorb');
  // shortcutTips.scope (#600): nur atlas oder all.
  Assert.AreEqual('atlas', mSettings.ShortcutTipsScope);
end;

procedure TAtlasPluginSettingsTests.ClampsNormalizedRanges;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := Default(TAtlasPluginSettings);
  mSettings.Normalize;
  // navigation.impactDepth (#1120): 1 bis 5.
  mSettings.ImpactDepth := 0;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinImpactDepth, mSettings.ImpactDepth);
  mSettings.ImpactDepth := 9;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxImpactDepth, mSettings.ImpactDepth);
  // tests.affectedDepth (#1353): 1 bis 5.
  mSettings.TestsAffectedDepth := 0;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsAffectedDepth, mSettings.TestsAffectedDepth);
  mSettings.TestsAffectedDepth := 7;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsAffectedDepth, mSettings.TestsAffectedDepth);
  // tests.coveredBy.depth (#1778): 1 bis 5.
  mSettings.TestsCoveredByDepth := 0;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsCoveredByDepth, mSettings.TestsCoveredByDepth);
  mSettings.TestsCoveredByDepth := 7;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsCoveredByDepth, mSettings.TestsCoveredByDepth);
  // tests.fromDebugStop.maxArray (#1873): 0 bis 1000.
  mSettings.TestsFromDebugStopMaxArray := -1;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsFromDebugStopMaxArray, mSettings.TestsFromDebugStopMaxArray);
  mSettings.TestsFromDebugStopMaxArray := 5000;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsFromDebugStopMaxArray, mSettings.TestsFromDebugStopMaxArray);
  // tests.untested.warnPercent (#1783): 0 bis 100.
  mSettings.TestsUntestedWarnPercent := -5;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsUntestedWarnPercent, mSettings.TestsUntestedWarnPercent);
  mSettings.TestsUntestedWarnPercent := 150;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsUntestedWarnPercent, mSettings.TestsUntestedWarnPercent);
  // tests.onSave.max (#1775): 1 bis 1000.
  mSettings.TestsOnSaveMax := 0;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsOnSaveMax, mSettings.TestsOnSaveMax);
  mSettings.TestsOnSaveMax := 5000;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsOnSaveMax, mSettings.TestsOnSaveMax);
  // tests.slowMs (#1772): 50 bis 60000.
  mSettings.TestsSlowMs := 10;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsSlowMs, mSettings.TestsSlowMs);
  mSettings.TestsSlowMs := 100000;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsSlowMs, mSettings.TestsSlowMs);
  // tests.repeat.count (#1782): 2 bis 1000.
  mSettings.TestsRepeatCount := 1;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsRepeatCount, mSettings.TestsRepeatCount);
  mSettings.TestsRepeatCount := 5000;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsRepeatCount, mSettings.TestsRepeatCount);
  // tests.flaky.runs (#1773): 3 bis 50.
  mSettings.TestsFlakyRuns := 1;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsFlakyRuns, mSettings.TestsFlakyRuns);
  mSettings.TestsFlakyRuns := 500;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsFlakyRuns, mSettings.TestsFlakyRuns);
  // tests.boundaryCases.maxCases (#2173): 1 bis 200.
  mSettings.TestsBoundaryMax := 0;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsBoundaryMax, mSettings.TestsBoundaryMax);
  mSettings.TestsBoundaryMax := 500;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsBoundaryMax, mSettings.TestsBoundaryMax);
  // tests.mutation.timeoutSec (#1460): 5 bis 3600.
  mSettings.TestsMutationTimeoutSec := 1;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsMutationTimeoutSec, mSettings.TestsMutationTimeoutSec);
  mSettings.TestsMutationTimeoutSec := 100000;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsMutationTimeoutSec, mSettings.TestsMutationTimeoutSec);
end;

procedure TAtlasPluginSettingsTests.NormalizesUpdateChoices;
var
  mSettings: TAtlasPluginSettings;
begin
  // updates.install, updates.channel, updates.newModules (#1519): unbekannt = Standard.
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.UpdatesInstall := 'immer';
  mSettings.UpdatesChannel := 'nightly';
  mSettings.UpdatesNewModules := 'alle';
  mSettings.HelpSource := 'Offline';
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cHelpSourceOnline, mSettings.HelpSource, 'unbekannte Quelle: online');
  Assert.AreEqual('ask', mSettings.UpdatesInstall);
  Assert.AreEqual('stable', mSettings.UpdatesChannel);
  Assert.AreEqual('ask', mSettings.UpdatesNewModules);
end;

procedure TAtlasPluginSettingsTests.OneActionAfterSaving;
var
  mSettings: TAtlasPluginSettings;
begin
  // Eine Auswahl „Nach dem Speichern“: Syntaxprüfung der IDE oder Kompilieren im Server, nie beides.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(mSettings.CheckOnSave);
  Assert.IsFalse(mSettings.CompileOnSave);
  mSettings.CompileOnSave := True;
  mSettings.Normalize;
  Assert.IsTrue(mSettings.CompileOnSave);
  mSettings.CheckOnSave := True;
  mSettings.Normalize;
  Assert.IsTrue(mSettings.CheckOnSave);
  Assert.IsFalse(mSettings.CompileOnSave);
end;
procedure TAtlasPluginSettingsTests.NotificationOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.Notifications, 'standardmäßig an');
  Assert.AreEqual('', mSettings.NotificationsSources, 'alle Quellen zeigen');
  Assert.AreEqual(200, mSettings.NotificationsMaxEntries);
  Assert.AreEqual($E04E, mSettings.NotificationsKey, 'Strg+Umschalt+Alt+N');
  // Grenzen wie in der Zentrale.
  Assert.AreEqual(TAtlasNotificationCenter.cMinEntries, TAtlasPluginSettings.cMinNotificationEntries);
  Assert.AreEqual(TAtlasNotificationCenter.cMaxMaxEntries, TAtlasPluginSettings.cMaxNotificationEntries);
  Assert.AreEqual(TAtlasNotificationCenter.cDefaultMaxEntries, mSettings.NotificationsMaxEntries);
  mSettings.NotificationsMaxEntries := 3;
  mSettings.NotificationsSources := ' ShortcutTips = COLLECT ; server=show, build=laut, reload=off ';
  mSettings.NotificationsKey := -1;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinNotificationEntries, mSettings.NotificationsMaxEntries);
  Assert.AreEqual('ShortcutTips=collect, reload=off', mSettings.NotificationsSources,
    'show entfällt, unbekanntes Verhalten auch');
  Assert.AreEqual(0, mSettings.NotificationsKey);
  mSettings.NotificationsMaxEntries := 5000;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxNotificationEntries, mSettings.NotificationsMaxEntries);
  // Speichern und Laden.
  mSettings.Notifications := False;
  mSettings.NotificationsMaxEntries := 50;
  mSettings.NotificationsKey := $C04E;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.Notifications, 'abschaltbar');
  Assert.AreEqual('ShortcutTips=collect, reload=off', mLoaded.NotificationsSources);
  Assert.AreEqual(50, mLoaded.NotificationsMaxEntries);
  Assert.AreEqual($C04E, mLoaded.NotificationsKey);
end;
procedure TAtlasPluginSettingsTests.CheckFileKeyOption;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual($E050, mSettings.CheckFileKey, 'Strg+Umschalt+Alt+P');
  mSettings.CheckFileKey := -1;
  mSettings.Normalize;
  Assert.AreEqual(0, mSettings.CheckFileKey, 'ungültig = keins');
  mSettings.CheckFileKey := $70000;
  mSettings.Normalize;
  Assert.AreEqual($FFFF, mSettings.CheckFileKey);
  mSettings.CheckFileKey := $4050;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.AreEqual($4050, mLoaded.CheckFileKey, 'Strg+P');
  mSettings.CheckFileKey := 0;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.AreEqual(0, mLoaded.CheckFileKey, 'leer bleibt leer');
end;
procedure TAtlasPluginSettingsTests.CompletionListModeOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
  mMode: TAtlasListMode;
  mScope: TAtlasListScope;
begin
  // Listenmodus der Vervollständigung (#497): standardmäßig nur Treffer, gilt in Mitgliederlisten.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('filter', mSettings.CompletionListMode);
  Assert.AreEqual('members', mSettings.CompletionListScope);
  mSettings.CompletionListMode := 'REST';
  mSettings.CompletionListScope := 'Everywhere';
  mSettings.Normalize;
  Assert.AreEqual('rest', mSettings.CompletionListMode);
  Assert.AreEqual('everywhere', mSettings.CompletionListScope);
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.AreEqual('rest', mLoaded.CompletionListMode);
  Assert.AreEqual('everywhere', mLoaded.CompletionListScope);
  mSettings.CompletionListMode := 'alles';
  mSettings.CompletionListScope := 'nirgends';
  mSettings.Normalize;
  Assert.AreEqual('filter', mSettings.CompletionListMode);
  Assert.AreEqual('members', mSettings.CompletionListScope);
  // Dieselben Namen wie TAtlasListModes in der Vervollständigung.
  for mMode := Low(TAtlasListMode) to High(TAtlasListMode) do
  begin
    mSettings.CompletionListMode := TAtlasListModes.cModeNames[mMode];
    mSettings.Normalize;
    Assert.AreEqual(TAtlasListModes.cModeNames[mMode], mSettings.CompletionListMode);
  end;
  for mScope := Low(TAtlasListScope) to High(TAtlasListScope) do
  begin
    mSettings.CompletionListScope := TAtlasListModes.cScopeNames[mScope];
    mSettings.Normalize;
    Assert.AreEqual(TAtlasListModes.cScopeNames[mScope], mSettings.CompletionListScope);
  end;
end;
procedure TAtlasPluginSettingsTests.CompletionVariantBranchOption;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // Marke „Zweig 0“ an Feldern varianter Records (#846): Vorgabe an, abschaltbar.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.CompletionVariantBranch);
  mSettings.CompletionVariantBranch := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.CompletionVariantBranch);
end;
{ TAtlasSettingsScopesTests }

procedure TAtlasSettingsScopesTests.RoutesServerSettingsToGlobalFile;
var
  mRegistry: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mStore: IAtlasSettingsStore;
  mSetting: TAtlasRoutedSetting;
begin
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mStore.WriteInteger('SlashCommands', 0);
  mStore.WriteInteger('InlayHints', 1);
  mStore.WriteInteger('CompileOnSave', 1);
  mStore.WriteInteger('CodeLensMetrics', 0);
  mStore.WriteInteger('ReferencesInferred', 0);
  mStore.WriteInteger('ReferencesTextMatches', 1);
  mStore.WriteInteger('Impact', 0);
  mStore.WriteInteger('ImpactDepth', 4);
  mStore.WriteInteger('PairColors', 0);
  mStore.WriteString('ServerPath', 'C:\Atlas\AtlasServer.exe');
  Assert.Contains(mRouted.Text, '"slashCommands": {');
  Assert.Contains(mRouted.Text, '"enabled": false');
  Assert.Contains(mRouted.Text, '"parameterNames": true');
  Assert.Contains(mRouted.Text, '"onSave": true');
  Assert.Contains(mRouted.Text, '"metrics": false', 'codeLens.metrics in settings.json (#66)');
  // Treffersicherheit (#1119): Server und Plugin lesen denselben Wert.
  Assert.Contains(mRouted.Text, '"references": {');
  Assert.Contains(mRouted.Text, '"inferred": false');
  Assert.Contains(mRouted.Text, '"textMatches": true');
  // Auswirkungsanalyse (#1120): navigation.* für Plugin, Server und MCP.
  Assert.Contains(mRouted.Text, '"navigation": {');
  Assert.Contains(mRouted.Text, '"impact": false');
  Assert.Contains(mRouted.Text, '"impactDepth": 4');
  Assert.AreEqual(4, mStore.ReadInteger('ImpactDepth', 2));
  Assert.AreEqual(0, mStore.ReadInteger('ReferencesInferred', 1));
  Assert.AreEqual(-1, mRegistry.ReadInteger('ReferencesInferred', -1));
  // Reine Plugin-Werte bleiben in der Registry.
  Assert.DoesNotContain(mRouted.Text, 'PairColors');
  Assert.AreEqual(0, mRegistry.ReadInteger('PairColors', 1));
  Assert.AreEqual('C:\Atlas\AtlasServer.exe', mRegistry.ReadString('ServerPath', ''));
  Assert.AreEqual(-1, mRegistry.ReadInteger('SlashCommands', -1));
  Assert.IsTrue(TAtlasSettingsScopes.TryRouted('indexusages', mSetting));
  Assert.AreEqual('index.usages', mSetting.Path);
  Assert.IsFalse(TAtlasSettingsScopes.TryRouted('PairColors', mSetting));
  Assert.AreEqual(Integer(Length(TAtlasSettingsScopes.Routed) + 1),
    Integer(Length(TAtlasSettingsScopes.IdeManagedPaths)));
  Assert.AreEqual('delphiVersion', TAtlasSettingsScopes.IdeManagedPaths[0]);
end;
procedure TAtlasSettingsScopesTests.ArchitectureSettingsLiveInGlobalFile;
var
  mRegistry: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  // Architekturübersicht (#1118): Plugin und Server lesen architecture.* aus settings.json.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.ArchitectureEnabled);
  Assert.AreEqual('projectGroup', mSettings.ArchitectureScope);
  Assert.IsFalse(mSettings.ArchitectureIncludeLibraryUnits);
  Assert.AreEqual(15, mSettings.ArchitectureCentralUnits);
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mSettings.ArchitectureEnabled := False;
  mSettings.ArchitectureScope := 'project';
  mSettings.ArchitectureIncludeLibraryUnits := True;
  mSettings.ArchitectureCentralUnits := 30;
  mSettings.Save(mStore);
  Assert.Contains(mRouted.Text, '"architecture": {');
  Assert.Contains(mRouted.Text, '"scope": "project"');
  Assert.Contains(mRouted.Text, '"includeLibraryUnits": true');
  Assert.Contains(mRouted.Text, '"centralUnits": 30');
  Assert.AreEqual(-1, mRegistry.ReadInteger('ArchitectureEnabled', -1), 'nicht in der Registry');
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.ArchitectureEnabled);
  Assert.AreEqual('project', mLoaded.ArchitectureScope);
  Assert.IsTrue(mLoaded.ArchitectureIncludeLibraryUnits);
  Assert.AreEqual(30, mLoaded.ArchitectureCentralUnits);
  // Unbekannter Umfang und Zahl außerhalb der Grenzen fallen auf gültige Werte.
  mLoaded.ArchitectureScope := 'irgendwas';
  mLoaded.ArchitectureCentralUnits := 0;
  mLoaded.Normalize;
  Assert.AreEqual('projectGroup', mLoaded.ArchitectureScope);
  Assert.AreEqual(5, mLoaded.ArchitectureCentralUnits);
  // Der Zustand „Fenster einmal rechts angelegt“ bleibt in der Registry.
  Assert.IsFalse(TAtlasPluginSettings.Defaults.ArchitectureWindowPlaced);
  mLoaded.ArchitectureWindowPlaced := True;
  mLoaded.Save(mStore);
  Assert.AreEqual(1, mRegistry.ReadInteger('ArchitectureWindowPlaced', -1));
  // Ebenso für das Fenster „Unit-Beziehungen“ (#593).
  Assert.IsFalse(TAtlasPluginSettings.Defaults.UnitRelationsWindowPlaced);
  mLoaded.UnitRelationsWindowPlaced := True;
  mLoaded.Save(mStore);
  Assert.AreEqual(1, mRegistry.ReadInteger('UnitRelationsWindowPlaced', -1));
end;
procedure TAtlasSettingsScopesTests.KeepsCommentsAndOtherKeys;
const
  cOriginal = '{'#13#10'  // eigene Notiz'#13#10'  "language": "en",'#13#10'  "index": {"usages": true}'#13#10'}'#13#10;
var
  mRouted: TAtlasRoutedSettingsStore;
  mStore: IAtlasSettingsStore;
begin
  mRouted := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, cOriginal);
  mStore := mRouted;
  // Gleicher Wert: Der Text bleibt genau gleich.
  mStore.WriteInteger('IndexUsages', 1);
  Assert.AreEqual(cOriginal, mRouted.Text);
  mStore.WriteInteger('IndexUsages', 0);
  Assert.Contains(mRouted.Text, '// eigene Notiz');
  Assert.Contains(mRouted.Text, '"language": "en"');
  Assert.Contains(mRouted.Text, '"usages": false');
  Assert.AreEqual(0, mStore.ReadInteger('IndexUsages', 1));
end;
procedure TAtlasSettingsScopesTests.MigratesRegistryValuesOnce;
var
  mRegistry: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mStore: IAtlasSettingsStore;
begin
  // Bis hierher lagen Index und XMLDoc in der Registry; settings.json übernimmt sie einmal.
  mRegistry := TMemoryStore.Create;
  mRegistry.WriteInteger('IndexLibraryPaths', 1);
  mRegistry.WriteInteger('XmlDocMaxLines', 7);
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '{"index": {"libraryPaths": false}}');
  mStore := mRouted;
  // Ohne Wert in settings.json gilt bis zur Übernahme der alte Wert.
  Assert.AreEqual(7, mStore.ReadInteger('XmlDocMaxLines', 0));
  Assert.AreEqual(0, mStore.ReadInteger('IndexLibraryPaths', 1), 'settings.json gewinnt');
  Assert.IsTrue(mRouted.Migrate);
  Assert.Contains(mRouted.Text, '"xmlDocMaxLines": 7');
  Assert.Contains(mRouted.Text, '"libraryPaths": false');
  Assert.IsFalse(mRouted.Migrate, 'nur einmal');
end;
procedure TAtlasSettingsScopesTests.LeavesBrokenFileAlone;
var
  mRegistry: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mStore: IAtlasSettingsStore;
begin
  mRegistry := TMemoryStore.Create;
  mRegistry.WriteInteger('IndexUsages', 0);
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '{"index": ');
  mStore := mRouted;
  Assert.IsFalse(mRouted.Migrate);
  mStore.WriteInteger('IndexSearchPaths', 0);
  Assert.AreEqual('{"index": ', mRouted.Text);
  Assert.AreEqual(0, mStore.ReadInteger('IndexUsages', 1));
end;
procedure TAtlasSettingsScopesTests.SchemaDescriptionsInBothLanguages;
var
  mFields: TArray<TAtlasSettingField>;
  mField: TAtlasSettingField;
  mMissing: string;
begin
  mMissing := '';
  for mField in TAtlasSettingsSchema.Fields(AtlasSchemaJson) do
  begin
    if (mField.Description <> '') and (mField.DescriptionEn = '') then
    begin
      mMissing := mMissing + mField.Path + ' ';
    end;
  end;
  Assert.AreEqual('', mMissing);
  mFields := TAtlasSettingsSchema.Fields('{"properties": {"a": {"type": "boolean", "description": "Schalter", ' +
    '"x-description-en": "Switch"}, "b": {"type": "boolean", "description": "Nur deutsch"}}}');
  Assert.AreEqual(Integer(2), Integer(Length(mFields)));
  Assert.AreEqual('Switch', mFields[0].DescriptionFor(True));
  Assert.AreEqual('Schalter', mFields[0].DescriptionFor(False));
  Assert.AreEqual('Nur deutsch', mFields[1].DescriptionFor(True));
  mFields := nil;
end;

procedure TAtlasSettingsScopesTests.SplitsSchemaByScope;
var
  mFields, mProject, mGlobal: TArray<TAtlasSettingField>;
  mField: TAtlasSettingField;
  mPaths: string;
begin
  mFields := TAtlasSettingsSchema.Fields(AtlasSchemaJson);
  mProject := TAtlasSettingsSchema.ForScope(mFields, False, nil);
  mGlobal := TAtlasSettingsSchema.ForScope(mFields, True, TAtlasSettingsScopes.IdeManagedPaths);
  mPaths := '|';
  for mField in mProject do
  begin
    mPaths := mPaths + mField.Path + '|';
  end;
  Assert.Contains(mPaths, '|rules|');
  Assert.Contains(mPaths, '|index.exclude|');
  Assert.Contains(mPaths, '|completion.senderCast|');
  Assert.DoesNotContain(mPaths, '|index.projectGroup|');
  Assert.DoesNotContain(mPaths, '|language|');
  // Unit-Zyklus beim Tippen (#896): Glied mit eigener Seite und eigenem Ort im sonst globalen diagnostics.
  Assert.Contains(mPaths, '|diagnostics.usesCycleLive|');
  Assert.Contains(mPaths, '|diagnostics.usesCycleImplementation|');
  Assert.DoesNotContain(mPaths, '|diagnostics.log|');
  for mField in mProject do
  begin
    if mField.Path = 'diagnostics.usesCycleLive' then
    begin
      Assert.AreEqual('Prüfregeln', mField.Page);
      Assert.AreEqual('true', mField.DefaultJson);
    end;
  end;
  mPaths := '|';
  for mField in mGlobal do
  begin
    mPaths := mPaths + mField.Path + '|';
  end;
  Assert.Contains(mPaths, '|language|');
  Assert.Contains(mPaths, '|completion.matching|');
  // Versionsverwaltung (#571) hat seit #1285 eine eigene Seite, Issue-Tracker seit #1260: Das ganze Objekt
  // ("vcs", "issues") enthält Glieder dieser Seiten und steht deshalb nicht im Dialog.
  Assert.DoesNotContain(mPaths, '|vcs|');
  Assert.DoesNotContain(mPaths, '|vcs.provider|');
  Assert.DoesNotContain(mPaths, '|issues|');
  for mField in mFields do
  begin
    if mField.Path = 'vcs' then
    begin
      Assert.IsTrue(mField.Global, 'vcs bleibt global');
    end;
  end;
  // Auf den Reitern der Optionsseite bzw. von der IDE gesetzt: nicht noch einmal im Dialog.
  Assert.DoesNotContain(mPaths, '|index.projectGroup|');
  Assert.DoesNotContain(mPaths, '|hints.xmlDocFull|');
  Assert.DoesNotContain(mPaths, '|delphiVersion|');
  // rules gilt an beiden Orten (x-scope "both"): Tabelle auch in den globalen Einstellungen.
  Assert.Contains(mPaths, '|rules|');
  // Jedes umgeleitete Feld ist im Schema global.
  for mField in mFields do
  begin
    if Pos('|' + mField.Path + '|',
      '|index.projectGroup|memoryBudgetMb|compiler.onSave|slashCommands.enabled|references.inferred|') > 0 then
    begin
      Assert.IsTrue(mField.Global, mField.Path);
    end;
  end;
end;
/// <summary>Fenster „Atlas-Prüfung“ (#909): Werte von der Vorgabe abweichend setzen.</summary>
procedure SetProblemsWindowOptions(var ASettings: TAtlasPluginSettings);
begin
  ASettings.ProblemsWindow := False;
  ASettings.ProblemsWindowScope := 'file';
  ASettings.ProblemsWindowScopeProjects := False;
  ASettings.ProblemsWindowScopeProject := 'Atlas.IDE.Base';
  ASettings.ProblemsWindowGroupBy := 'category';
  ASettings.ProblemsWindowColumns := 'kind:70,-rule';
  ASettings.ProblemsWindowCompiler := True;
  ASettings.ProblemsWindowFollowCursor := False;
  ASettings.ProblemsWindowKey := $C051;
  ASettings.ProblemsUpdate := 'save';
  ASettings.ProblemsLiveDelayMs := 900;
  ASettings.FixBulk := False;
  ASettings.HoverProblemActions := False;
  ASettings.ProblemsMessageList := True;
  ASettings.ProblemsCompilerMerge := 'both';
  ASettings.ProblemsShowCompilerCode := False;
end;
/// <summary>Fenster „Atlas-Prüfung“ (#909): gespeicherte Werte gelesen.</summary>
procedure AssertProblemsWindowLoaded(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsFalse(ALoaded.ProblemsWindow);
  Assert.AreEqual('file', ALoaded.ProblemsWindowScope);
  Assert.IsFalse(ALoaded.ProblemsWindowScopeProjects);
  Assert.AreEqual('Atlas.IDE.Base', ALoaded.ProblemsWindowScopeProject);
  Assert.AreEqual('category', ALoaded.ProblemsWindowGroupBy);
  Assert.AreEqual('kind:70,-rule', ALoaded.ProblemsWindowColumns);
  Assert.IsTrue(ALoaded.ProblemsWindowCompiler);
  Assert.IsFalse(ALoaded.ProblemsWindowFollowCursor);
  Assert.AreEqual($C051, ALoaded.ProblemsWindowKey);
  Assert.AreEqual('save', ALoaded.ProblemsUpdate);
  Assert.AreEqual(900, ALoaded.ProblemsLiveDelayMs);
  Assert.IsFalse(ALoaded.FixBulk);
  Assert.IsFalse(ALoaded.HoverProblemActions);
  Assert.AreEqual('both', ALoaded.ProblemsCompilerMerge);
  Assert.IsFalse(ALoaded.ProblemsShowCompilerCode);
  Assert.IsTrue(ALoaded.ProblemsMessageList);
end;
procedure TAtlasPluginSettingsTests.MessageListIgnoresFormerRegistryName;
var
  mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mStore := TMemoryStore.Create;
  mStore.WriteInteger('ProblemsList', 1);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.ProblemsMessageList, 'ProblemsList von vor #909 bleibt unbeachtet');
  mStore.WriteInteger('ProblemsMessageList', 1);
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.ProblemsMessageList, 'Neuer Name gilt');
end;

procedure TAtlasPluginSettingsTests.ProblemsUpdateOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('live', mSettings.ProblemsUpdate);
  Assert.AreEqual(400, mSettings.ProblemsLiveDelayMs);
  // Rundweg.
  mSettings.ProblemsUpdate := 'manual';
  mSettings.ProblemsLiveDelayMs := 1500;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.AreEqual('manual', mLoaded.ProblemsUpdate);
  Assert.AreEqual(1500, mLoaded.ProblemsLiveDelayMs);
  // Grenzen und unbekannte Werte.
  mSettings.ProblemsUpdate := 'SAVE';
  mSettings.ProblemsLiveDelayMs := 20;
  mSettings.Normalize;
  Assert.AreEqual('save', mSettings.ProblemsUpdate);
  Assert.AreEqual(100, mSettings.ProblemsLiveDelayMs);
  mSettings.ProblemsUpdate := 'manuell';
  mSettings.ProblemsLiveDelayMs := 99999;
  mSettings.Normalize;
  Assert.AreEqual('live', mSettings.ProblemsUpdate, 'Unbekanntes = Vorgabe');
  Assert.AreEqual(10000, mSettings.ProblemsLiveDelayMs);
  // Vor problems.update: problems.live aus wird „beim Speichern“, an bleibt live.
  mStore := TMemoryStore.Create;
  mStore.WriteInteger('ProblemsLive', 0);
  mLoaded.Load(mStore);
  Assert.AreEqual('save', mLoaded.ProblemsUpdate);
  mStore.WriteInteger('ProblemsLive', 1);
  mLoaded.Load(mStore);
  Assert.AreEqual('live', mLoaded.ProblemsUpdate);
  // Ein gespeicherter neuer Wert geht vor.
  mStore.WriteInteger('ProblemsLive', 0);
  mStore.WriteString('ProblemsUpdate', 'manual');
  mLoaded.Load(mStore);
  Assert.AreEqual('manual', mLoaded.ProblemsUpdate);
end;

procedure TAtlasPluginSettingsTests.ProblemsWindowOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // Fenster „Atlas-Prüfung“, laufende Prüfung und Aktionen im Befund-Hover (#909).
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.ProblemsWindow);
  Assert.AreEqual('group', mSettings.ProblemsWindowScope);
  Assert.IsTrue(mSettings.ProblemsWindowScopeProjects, 'Einzelprojekte (#1843) an');
  Assert.AreEqual('', mSettings.ProblemsWindowScopeProject, 'aktives Projekt');
  Assert.AreEqual('file', mSettings.ProblemsWindowGroupBy);
  Assert.AreEqual('', mSettings.ProblemsWindowColumns);
  Assert.IsFalse(mSettings.ProblemsWindowCompiler);
  Assert.IsTrue(mSettings.ProblemsWindowFollowCursor);
  Assert.AreEqual($C050, mSettings.ProblemsWindowKey, 'Strg+Alt+P');
  Assert.IsTrue(mSettings.FixBulk, 'Sammelkorrektur (#1352) an');
  Assert.IsTrue(mSettings.HoverProblemActions);
  Assert.IsFalse(mSettings.ProblemsMessageList, 'Meldungsfenster-Gruppe seit dem Prüffenster aus');
  // Gruppe „Compiler vorab“ (#1024).
  Assert.AreEqual('merge', mSettings.ProblemsCompilerMerge);
  Assert.IsTrue(mSettings.ProblemsShowCompilerCode);
  mSettings.ProblemsCompilerMerge := 'BOTH';
  mSettings.Normalize;
  Assert.AreEqual('both', mSettings.ProblemsCompilerMerge);
  mSettings.ProblemsCompilerMerge := 'beides';
  mSettings.Normalize;
  Assert.AreEqual('merge', mSettings.ProblemsCompilerMerge, 'Unbekanntes = Vorgabe');
  mSettings.ProblemsWindowScope := 'PROJECT';
  mSettings.ProblemsWindowScopeProject := '  Atlas.Tests ';
  mSettings.ProblemsWindowGroupBy := 'unsinn';
  mSettings.ProblemsWindowKey := -1;
  mSettings.Normalize;
  Assert.AreEqual('project', mSettings.ProblemsWindowScope);
  Assert.AreEqual('Atlas.Tests', mSettings.ProblemsWindowScopeProject);
  Assert.AreEqual('file', mSettings.ProblemsWindowGroupBy, 'Unbekanntes = Vorgabe');
  Assert.AreEqual(0, mSettings.ProblemsWindowKey);
  SetProblemsWindowOptions(mSettings);
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  AssertProblemsWindowLoaded(mLoaded);
end;
procedure TAtlasPluginSettingsTests.ProblemsWindowOpenFirstOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.ProblemsWindowOpenFirst);
  Assert.AreEqual('dimmed', mSettings.ProblemsWindowClosedUnits);
  Assert.IsTrue(mSettings.ProblemsWindowShowCleanActive);
  mSettings.ProblemsWindowClosedUnits := 'HIDDEN';
  mSettings.Normalize;
  Assert.AreEqual('hidden', mSettings.ProblemsWindowClosedUnits);
  mSettings.ProblemsWindowClosedUnits := 'grau';
  mSettings.Normalize;
  Assert.AreEqual('dimmed', mSettings.ProblemsWindowClosedUnits, 'Unbekanntes = Vorgabe');
  mSettings.ProblemsWindowOpenFirst := False;
  mSettings.ProblemsWindowClosedUnits := 'normal';
  mSettings.ProblemsWindowShowCleanActive := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.ProblemsWindowOpenFirst);
  Assert.AreEqual('normal', mLoaded.ProblemsWindowClosedUnits);
  Assert.IsFalse(mLoaded.ProblemsWindowShowCleanActive);
end;
initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginSettingsTests);
  TDUnitX.RegisterTestFixture(TAtlasSettingsScopesTests);

end.
