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
  Assert.IsTrue(ASettings.TestsFromDebugStop, 'Test aus dem Debug-Halt standardmäßig an (#1873)');
  Assert.IsTrue(ASettings.TestsFromDebugStopFields, 'Felder anbieten standardmäßig an (#1873)');
  Assert.IsFalse(ASettings.TestsFromDebugStopProperties, 'Getter standardmäßig aus (#1873)');
  Assert.AreEqual(20, ASettings.TestsFromDebugStopMaxArray, 'Array-Grenze standardmäßig 20 (#1873)');
  Assert.IsTrue(ASettings.TestsCompare, 'Vergleich erwartet/erhalten standardmäßig an (#1779)');
  Assert.IsTrue(ASettings.TestsCompareFormat, 'JSON/XML einrücken standardmäßig an (#1779)');
  Assert.IsTrue(ASettings.TestsCaseTable, 'TestCase-Tabelle standardmäßig an (#1879)');
  Assert.IsTrue(ASettings.TestsApprovalFiles, 'Vergleichsdateien standardmäßig an (#1881)');
  Assert.IsTrue(ASettings.TestsShowDuration, 'Dauer an der Testmarke standardmäßig an (#1772)');
  Assert.IsTrue(ASettings.TestsWindow, 'Fenster „Atlas-Tests“ standardmäßig an (#1776)');
  Assert.IsTrue(ASettings.EditorStatusBarTests, 'Teststand in der Statusleiste standardmäßig an (#1777)');
  Assert.AreEqual(500, ASettings.TestsSlowMs, 'langsam ab 500 ms (#1772)');
  Assert.IsTrue(ASettings.TestsLeaks, 'Lecks je Test standardmäßig an (#1774)');
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
  Assert.IsTrue(ASettings.DebugWhyHere, 'debug.whyHere (#1878)');
  Assert.AreEqual(3, ASettings.DebugWhyHereDepth, 'debug.whyHere.depth (#1878)');
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
  Store: IAtlasSettingsStore;
  Settings: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  AssertEditorDefaults(Settings);
  AssertBuildDefaults(Settings);
  AssertDebugDefaults(Settings);
  AssertToolDefaults(Settings);
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
  ASettings.TestsFromDebugStop := False;
  ASettings.TestsFromDebugStopFields := False;
  ASettings.TestsFromDebugStopProperties := True;
  ASettings.TestsFromDebugStopMaxArray := 7;
  ASettings.TestsCompare := False;
  ASettings.TestsCompareFormat := False;
  ASettings.TestsCaseTable := False;
  ASettings.TestsApprovalFiles := False;
  ASettings.TestsShowDuration := False;
  ASettings.TestsWindow := False;
  ASettings.EditorStatusBarTests := False;
  ASettings.TestsSlowMs := 1000;
  ASettings.TestsLeaks := False;
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
  ASettings.DebugWhyHere := False;
  ASettings.DebugWhyHereDepth := 6;
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
  ASettings.DiagnosticModeKey := $6044;
end;
/// <summary>Rundreise: Diagnose, Start, Zurücknehmen und Blocklinien von der Vorgabe abweichend setzen.</summary>
procedure SetRoundTripTools(var ASettings: TAtlasPluginSettings);
begin
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
  Assert.IsFalse(ALoaded.TestsFromDebugStop, 'tests.fromDebugStop (#1873)');
  Assert.IsFalse(ALoaded.TestsFromDebugStopFields, 'tests.fromDebugStop.fields (#1873)');
  Assert.IsTrue(ALoaded.TestsFromDebugStopProperties, 'tests.fromDebugStop.properties (#1873)');
  Assert.AreEqual(7, ALoaded.TestsFromDebugStopMaxArray, 'tests.fromDebugStop.maxArray (#1873)');
  Assert.IsFalse(ALoaded.TestsCompare, 'tests.compare (#1779)');
  Assert.IsFalse(ALoaded.TestsCompareFormat, 'tests.compare.format (#1779)');
  Assert.IsFalse(ALoaded.TestsCaseTable, 'tests.testCaseTable (#1879)');
  Assert.IsFalse(ALoaded.TestsApprovalFiles, 'tests.approvalFiles (#1881)');
  Assert.IsFalse(ALoaded.TestsShowDuration, 'tests.showDuration (#1772)');
  Assert.IsFalse(ALoaded.TestsWindow, 'tests.window (#1776)');
  Assert.IsFalse(ALoaded.EditorStatusBarTests, 'editor.statusBar.tests (#1777)');
  Assert.AreEqual(1000, ALoaded.TestsSlowMs, 'tests.slowMs (#1772)');
  Assert.IsFalse(ALoaded.TestsLeaks, 'tests.leaks (#1774)');
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
  Assert.IsFalse(ALoaded.DebugWhyHere, 'debug.whyHere (#1878)');
  Assert.AreEqual(6, ALoaded.DebugWhyHereDepth, 'debug.whyHere.depth (#1878)');
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
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Settings := TAtlasPluginSettings.Defaults;
  SetRoundTripEditor(Settings);
  SetRoundTripDebug(Settings);
  SetRoundTripTools(Settings);
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  AssertRoundTripEditor(Loaded);
  AssertRoundTripDebug(Loaded);
  AssertRoundTripTools(Loaded);
  Assert.AreEqual('', TAtlasPluginSettings.Defaults.ServerPath, 'Standard: leer');
end;
procedure TAtlasPluginSettingsTests.IndexOptionsGoToGlobalFile;
var
  Registry: IAtlasSettingsStore;
  Store: TAtlasRoutedSettingsStore;
  Keep: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // Index und Speicher gelten für alle Projekte und stehen in settings.json (#652), nicht in der Registry.
  Registry := TMemoryStore.Create;
  Store := TAtlasRoutedSettingsStore.Create(Registry, '');
  Keep := Store;
  Settings := TAtlasPluginSettings.Defaults;
  Settings.IndexSearchPaths := False;
  Settings.IndexLibraryPaths := True;
  Settings.IndexUsages := False;
  Settings.MemoryBudgetMb := 512;
  Settings.Save(Store);
  Assert.AreEqual(-1, Registry.ReadInteger('IndexSearchPaths', -1), 'nicht in der Registry');
  Assert.Contains(Store.Text, '"searchPaths": false');
  Assert.Contains(Store.Text, '"libraryPaths": true');
  Assert.Contains(Store.Text, '"memoryBudgetMb": 512');
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.IndexProjectGroup);
  Assert.IsFalse(Loaded.IndexSearchPaths);
  Assert.IsTrue(Loaded.IndexLibraryPaths);
  Assert.IsFalse(Loaded.IndexUsages);
  Assert.AreEqual(512, Loaded.MemoryBudgetMb);
  // Speichergrenze (#492): 0 = unbegrenzt, nicht negativ, höchstens 64 GB.
  Store.WriteInteger('MemoryBudgetMb', -5);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.MemoryBudgetMb);
  Store.WriteInteger('MemoryBudgetMb', 999999);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.cMaxMemoryBudgetMb, Loaded.MemoryBudgetMb);
end;
procedure TAtlasPluginSettingsTests.XmlDocOptionsGoToGlobalFile;
var
  Store, Inner: IAtlasSettingsStore;
  Routed: TAtlasRoutedSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // #654, #770: XmlDocExpand/XmlDocMaxLines als hints in settings.json.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('last', Settings.XmlDocExpand);
  Assert.AreEqual(0, Settings.XmlDocMaxLines);
  Routed := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, '');
  Store := Routed;
  Settings.XmlDocExpand := 'collapsed';
  Settings.XmlDocMaxLines := 12;
  Settings.Save(Store);
  Assert.AreEqual('collapsed', Store.ReadString('XmlDocExpand', ''));
  Assert.AreEqual(12, Store.ReadInteger('XmlDocMaxLines', 0));
  Assert.Contains(Routed.Text, '"xmlDocExpand": "collapsed"');
  Assert.Contains(Routed.Text, '"xmlDocMaxLines": 12');
  Assert.IsFalse(Routed.Text.Contains('xmlDocFull'), Routed.Text);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.AreEqual('collapsed', Loaded.XmlDocExpand);
  Assert.AreEqual(12, Loaded.XmlDocMaxLines);
  // Unbekannter Wert: Vorgabe.
  Store.WriteString('XmlDocExpand', 'halb');
  Loaded.Load(Store);
  Assert.AreEqual('last', Loaded.XmlDocExpand);
  // Vor #770: xmlDocFull aus settings.json bzw. der Registry wird übernommen, aber nie geschrieben.
  Routed := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, '{"hints": {"xmlDocFull": true}}');
  Store := Routed;
  Loaded.Load(Store);
  Assert.AreEqual('expanded', Loaded.XmlDocExpand);
  Store.WriteInteger('XmlDocFull', 0);
  Assert.Contains(Routed.Text, '"xmlDocFull": true');
  Inner := TMemoryStore.Create;
  Inner.WriteInteger('XmlDocFull', 0);
  Routed := TAtlasRoutedSettingsStore.Create(Inner, '');
  Store := Routed;
  Routed.Migrate;
  Loaded.Load(Store);
  Assert.AreEqual('collapsed', Loaded.XmlDocExpand);
  Assert.IsFalse(Routed.Text.Contains('xmlDocFull'), Routed.Text);
  // Grenzen 0..50.
  Store.WriteInteger('XmlDocMaxLines', 99);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.cMaxXmlDocLines, Loaded.XmlDocMaxLines);
  Store.WriteInteger('XmlDocMaxLines', -3);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.XmlDocMaxLines);
end;
procedure TAtlasPluginSettingsTests.HoverMembersMaxLinesRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual(15, Settings.HoverMembersMaxLines);
  Store := TMemoryStore.Create;
  Settings.HoverMembersMaxLines := 8;
  Settings.Save(Store);
  Assert.AreEqual(8, Store.ReadInteger('HoverMembersMaxLines', 0));
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.AreEqual(8, Loaded.HoverMembersMaxLines);
  Store.WriteInteger('HoverMembersMaxLines', 500);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.cMaxHoverMembersLines, Loaded.HoverMembersMaxLines);
  Store.WriteInteger('HoverMembersMaxLines', -1);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.HoverMembersMaxLines);
end;

procedure TAtlasPluginSettingsTests.TestsLogRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.TestsLog);
  Assert.AreEqual(2000, Settings.TestsLogMaxLines);
  Store := TMemoryStore.Create;
  Settings.TestsLog := False;
  Settings.TestsLogMaxLines := 500;
  Settings.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('TestsLog', 1));
  Assert.AreEqual(500, Store.ReadInteger('TestsLogMaxLines', 0));
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.TestsLog);
  Assert.AreEqual(500, Loaded.TestsLogMaxLines);
  Store.WriteInteger('TestsLogMaxLines', 10);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsLogMaxLines, Loaded.TestsLogMaxLines);
  Store.WriteInteger('TestsLogMaxLines', 1000000);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsLogMaxLines, Loaded.TestsLogMaxLines);
end;

procedure TAtlasPluginSettingsTests.HoverSignatureParamsRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.HoverSignatureParams);
  Store := TMemoryStore.Create;
  Settings.HoverSignatureParams := False;
  Settings.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('HoverSignatureParams', 1));
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.HoverSignatureParams);
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
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.TrackLines);
  Store := TMemoryStore.Create;
  Settings.TrackLines := False;
  Settings.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('TrackLines', 1));
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.TrackLines);
end;

procedure TAtlasPluginSettingsTests.LearnedSuggestionsRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.SuggestionsLearned);
  Assert.AreEqual(300, Settings.SuggestionsDelayMs);
  Assert.AreEqual(70, Settings.SuggestionsMinShare);
  Assert.AreEqual(5, Settings.SuggestionsMinCount);
  Assert.IsTrue(Settings.SuggestionsLearnFromUsage);
  Store := TMemoryStore.Create;
  Settings.SuggestionsLearned := False;
  Settings.SuggestionsDelayMs := 500;
  Settings.SuggestionsMinShare := 80;
  Settings.SuggestionsMinCount := 3;
  Settings.SuggestionsLearnFromUsage := False;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.SuggestionsLearned);
  Assert.AreEqual(500, Loaded.SuggestionsDelayMs);
  Assert.AreEqual(80, Loaded.SuggestionsMinShare);
  Assert.AreEqual(3, Loaded.SuggestionsMinCount);
  Assert.IsFalse(Loaded.SuggestionsLearnFromUsage);
  Store.WriteInteger('SuggestionsDelayMs', 10);
  Store.WriteInteger('SuggestionsMinShare', 20);
  Store.WriteInteger('SuggestionsMinCount', 1000);
  Loaded.Load(Store);
  Assert.AreEqual(100, Loaded.SuggestionsDelayMs);
  Assert.AreEqual(50, Loaded.SuggestionsMinShare);
  Assert.AreEqual(100, Loaded.SuggestionsMinCount);
end;

procedure TAtlasPluginSettingsTests.ProjectContextMenuRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ProjectContextMenu);
  Store := TMemoryStore.Create;
  Settings.ProjectContextMenu := False;
  Settings.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('ProjectContextMenu', 1));
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.ProjectContextMenu);
end;

procedure TAtlasPluginSettingsTests.GalleryWizardsRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.GalleryWizards);
  Store := TMemoryStore.Create;
  Settings.GalleryWizards := False;
  Settings.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('GalleryWizards', 1));
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.GalleryWizards);
end;

procedure TAtlasPluginSettingsTests.EditorContextMenuRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.EditorContextMenuContextual);
  Assert.AreEqual('navigation,edit,analysis,findings,debug,tests,notes', Settings.EditorContextMenuGroups);
  Settings.EditorContextMenuContextual := False;
  Settings.EditorContextMenuGroups := 'notes; quatsch, Debug';
  Settings.Normalize;
  Assert.AreEqual('debug,notes', Settings.EditorContextMenuGroups);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.EditorContextMenuContextual);
  Assert.AreEqual('debug,notes', Loaded.EditorContextMenuGroups);
end;

procedure TAtlasPluginSettingsTests.AcceptOptionsRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // ARG-046 (#227): Commit-Zeichen, uses, Parameter-Hint, Verzögerung bis zum Öffnen.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.CommitCharacters);
  Assert.IsTrue(Settings.AutoUses);
  Assert.IsTrue(Settings.ParameterHints);
  Assert.IsTrue(Settings.FormatPlaceholders);
  Assert.AreEqual(150, Settings.OpenDelayMs);
  // Auswahl mit Rahmen und Marke (#447).
  Assert.IsTrue(Settings.SelectionMarker);
  Store := TMemoryStore.Create;
  Settings.CommitCharacters := False;
  Settings.SelectionMarker := False;
  Settings.AutoUses := False;
  Settings.ParameterHints := False;
  Settings.FormatPlaceholders := False;
  Settings.OpenDelayMs := 400;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.CommitCharacters);
  Assert.IsFalse(Loaded.SelectionMarker);
  Assert.IsFalse(Loaded.AutoUses);
  Assert.IsFalse(Loaded.ParameterHints);
  Assert.IsFalse(Loaded.FormatPlaceholders);
  Assert.AreEqual(400, Loaded.OpenDelayMs);
  Store.WriteInteger('OpenDelayMs', 99999);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.cMaxOpenDelay, Loaded.OpenDelayMs);
  Store.WriteInteger('OpenDelayMs', -1);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.OpenDelayMs);
end;
procedure TAtlasPluginSettingsTests.ClampsOutOfRangeValues;
var
  Store: IAtlasSettingsStore;
  Settings: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Store.WriteInteger('VisibleRows', 99);
  Store.WriteInteger('ListWidth', 50);
  Store.WriteInteger('PanelWidth', 5000);
  Store.WriteInteger('SignatureKey', -3);
  Store.WriteInteger('ProviderTimeLimitMs', 10);
  Store.WriteInteger('SafeStartupTimeoutMs', 5);
  Store.WriteInteger('SafeKeepSettingsHistory', 1000);
  Store.WriteString('SafeStartupKey', ' Alt ');
  Store.WriteInteger('UndoMultiFileDepth', 0);
  Store.WriteInteger('UndoMultiFileMaxSizeMb', 100000);
  Store.WriteString('UndoMultiFileOnConflict', ' ABORT ');
  Store.WriteString('UndoMultiFileNewFiles', 'irgendwas');
  Store.WriteString('ShortcutTipsScope', ' ATLAS ');
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.cMinProviderTimeLimit, Settings.ProviderTimeLimitMs);
  Assert.AreEqual(0, Settings.SignatureKey, 'kein gültiges Kürzel');
  Store.WriteInteger('PairGuideWidth', 7);
  Store.WriteInteger('PairGuideOpacity', 0);
  Store.WriteString('PairColorsLight', '#123456,blau');
  Store.WriteString('NestedRoutines', 'irgendwie');
  Store.WriteString('NestedRoutineColorDark', 'blau');
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.cMaxPairGuideWidth, Settings.PairGuideWidth);
  Assert.AreEqual(TAtlasPluginSettings.cMinPairGuideOpacity, Settings.PairGuideOpacity);
  Assert.AreEqual('', Settings.PairColorsLight, 'ungültige Farben = Standard');
  Assert.AreEqual('deeper', Settings.NestedRoutines, 'unbekannte Färbung = Vorgabe (#1788)');
  Assert.AreEqual('', Settings.NestedRoutineColorDark, 'ungültige Farbe = Palette (#1788)');
  Assert.AreEqual(TAtlasPluginSettings.cMaxVisibleRows, Settings.VisibleRows);
  Assert.AreEqual(TAtlasPluginSettings.cMinListWidth, Settings.ListWidth);
  Assert.AreEqual(TAtlasPluginSettings.cMaxPanelWidth, Settings.PanelWidth);
  Assert.AreEqual(TAtlasPluginSettings.cMinSafeStartupTimeout, Settings.SafeStartupTimeoutMs);
  Assert.AreEqual(TAtlasPluginSettings.cMaxSafeSettingsHistory, Settings.SafeKeepSettingsHistory);
  Assert.AreEqual('shift', Settings.SafeStartupKey, 'unbekannte Taste: Umschalt');
  Assert.AreEqual(TAtlasPluginSettings.cMinUndoDepth, Settings.UndoMultiFileDepth);
  Assert.AreEqual(TAtlasPluginSettings.cMaxUndoMaxSizeMb, Settings.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('abort', Settings.UndoMultiFileOnConflict);
  Assert.AreEqual('recycleBin', Settings.UndoMultiFileNewFiles, 'unbekannt: Papierkorb');
  // shortcutTips.scope (#600): nur atlas oder all.
  Assert.AreEqual('atlas', Settings.ShortcutTipsScope);
end;

procedure TAtlasPluginSettingsTests.ClampsNormalizedRanges;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := Default(TAtlasPluginSettings);
  Settings.Normalize;
  // navigation.impactDepth (#1120): 1 bis 5.
  Settings.ImpactDepth := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinImpactDepth, Settings.ImpactDepth);
  Settings.ImpactDepth := 9;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxImpactDepth, Settings.ImpactDepth);
  // tests.affectedDepth (#1353): 1 bis 5.
  Settings.TestsAffectedDepth := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsAffectedDepth, Settings.TestsAffectedDepth);
  Settings.TestsAffectedDepth := 7;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsAffectedDepth, Settings.TestsAffectedDepth);
  // tests.coveredBy.depth (#1778): 1 bis 5.
  Settings.TestsCoveredByDepth := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsCoveredByDepth, Settings.TestsCoveredByDepth);
  Settings.TestsCoveredByDepth := 7;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsCoveredByDepth, Settings.TestsCoveredByDepth);
  // tests.fromDebugStop.maxArray (#1873): 0 bis 1000.
  Settings.TestsFromDebugStopMaxArray := -1;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsFromDebugStopMaxArray, Settings.TestsFromDebugStopMaxArray);
  Settings.TestsFromDebugStopMaxArray := 5000;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsFromDebugStopMaxArray, Settings.TestsFromDebugStopMaxArray);
  // tests.untested.warnPercent (#1783): 0 bis 100.
  Settings.TestsUntestedWarnPercent := -5;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsUntestedWarnPercent, Settings.TestsUntestedWarnPercent);
  Settings.TestsUntestedWarnPercent := 150;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsUntestedWarnPercent, Settings.TestsUntestedWarnPercent);
  // tests.onSave.max (#1775): 1 bis 1000.
  Settings.TestsOnSaveMax := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsOnSaveMax, Settings.TestsOnSaveMax);
  Settings.TestsOnSaveMax := 5000;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsOnSaveMax, Settings.TestsOnSaveMax);
  // tests.slowMs (#1772): 50 bis 60000.
  Settings.TestsSlowMs := 10;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTestsSlowMs, Settings.TestsSlowMs);
  Settings.TestsSlowMs := 100000;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTestsSlowMs, Settings.TestsSlowMs);
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
  Settings: TAtlasPluginSettings;
begin
  // Eine Auswahl „Nach dem Speichern“: Syntaxprüfung der IDE oder Kompilieren im Server, nie beides.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(Settings.CheckOnSave);
  Assert.IsFalse(Settings.CompileOnSave);
  Settings.CompileOnSave := True;
  Settings.Normalize;
  Assert.IsTrue(Settings.CompileOnSave);
  Settings.CheckOnSave := True;
  Settings.Normalize;
  Assert.IsTrue(Settings.CheckOnSave);
  Assert.IsFalse(Settings.CompileOnSave);
end;
procedure TAtlasPluginSettingsTests.NotificationOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.Notifications, 'standardmäßig an');
  Assert.AreEqual('', Settings.NotificationsSources, 'alle Quellen zeigen');
  Assert.AreEqual(200, Settings.NotificationsMaxEntries);
  Assert.AreEqual($E04E, Settings.NotificationsKey, 'Strg+Umschalt+Alt+N');
  // Grenzen wie in der Zentrale.
  Assert.AreEqual(TAtlasNotificationCenter.cMinEntries, TAtlasPluginSettings.cMinNotificationEntries);
  Assert.AreEqual(TAtlasNotificationCenter.cMaxMaxEntries, TAtlasPluginSettings.cMaxNotificationEntries);
  Assert.AreEqual(TAtlasNotificationCenter.cDefaultMaxEntries, Settings.NotificationsMaxEntries);
  Settings.NotificationsMaxEntries := 3;
  Settings.NotificationsSources := ' ShortcutTips = COLLECT ; server=show, build=laut, reload=off ';
  Settings.NotificationsKey := -1;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinNotificationEntries, Settings.NotificationsMaxEntries);
  Assert.AreEqual('ShortcutTips=collect, reload=off', Settings.NotificationsSources,
    'show entfällt, unbekanntes Verhalten auch');
  Assert.AreEqual(0, Settings.NotificationsKey);
  Settings.NotificationsMaxEntries := 5000;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxNotificationEntries, Settings.NotificationsMaxEntries);
  // Speichern und Laden.
  Settings.Notifications := False;
  Settings.NotificationsMaxEntries := 50;
  Settings.NotificationsKey := $C04E;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Notifications, 'abschaltbar');
  Assert.AreEqual('ShortcutTips=collect, reload=off', Loaded.NotificationsSources);
  Assert.AreEqual(50, Loaded.NotificationsMaxEntries);
  Assert.AreEqual($C04E, Loaded.NotificationsKey);
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
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
  Mode: TAtlasListMode;
  Scope: TAtlasListScope;
begin
  // Listenmodus der Vervollständigung (#497): standardmäßig nur Treffer, gilt in Mitgliederlisten.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('filter', Settings.CompletionListMode);
  Assert.AreEqual('members', Settings.CompletionListScope);
  Settings.CompletionListMode := 'REST';
  Settings.CompletionListScope := 'Everywhere';
  Settings.Normalize;
  Assert.AreEqual('rest', Settings.CompletionListMode);
  Assert.AreEqual('everywhere', Settings.CompletionListScope);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.AreEqual('rest', Loaded.CompletionListMode);
  Assert.AreEqual('everywhere', Loaded.CompletionListScope);
  Settings.CompletionListMode := 'alles';
  Settings.CompletionListScope := 'nirgends';
  Settings.Normalize;
  Assert.AreEqual('filter', Settings.CompletionListMode);
  Assert.AreEqual('members', Settings.CompletionListScope);
  // Dieselben Namen wie TAtlasListModes in der Vervollständigung.
  for Mode := Low(TAtlasListMode) to High(TAtlasListMode) do
  begin
    Settings.CompletionListMode := TAtlasListModes.cModeNames[Mode];
    Settings.Normalize;
    Assert.AreEqual(TAtlasListModes.cModeNames[Mode], Settings.CompletionListMode);
  end;
  for Scope := Low(TAtlasListScope) to High(TAtlasListScope) do
  begin
    Settings.CompletionListScope := TAtlasListModes.cScopeNames[Scope];
    Settings.Normalize;
    Assert.AreEqual(TAtlasListModes.cScopeNames[Scope], Settings.CompletionListScope);
  end;
end;
procedure TAtlasPluginSettingsTests.CompletionVariantBranchOption;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Marke „Zweig 0“ an Feldern varianter Records (#846): Vorgabe an, abschaltbar.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.CompletionVariantBranch);
  Settings.CompletionVariantBranch := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.CompletionVariantBranch);
end;
{ TAtlasSettingsScopesTests }

procedure TAtlasSettingsScopesTests.RoutesServerSettingsToGlobalFile;
var
  Registry: IAtlasSettingsStore;
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
  Setting: TAtlasRoutedSetting;
begin
  Registry := TMemoryStore.Create;
  Routed := TAtlasRoutedSettingsStore.Create(Registry, '');
  Store := Routed;
  Store.WriteInteger('SlashCommands', 0);
  Store.WriteInteger('InlayHints', 1);
  Store.WriteInteger('CompileOnSave', 1);
  Store.WriteInteger('CodeLensMetrics', 0);
  Store.WriteInteger('ReferencesInferred', 0);
  Store.WriteInteger('ReferencesTextMatches', 1);
  Store.WriteInteger('Impact', 0);
  Store.WriteInteger('ImpactDepth', 4);
  Store.WriteInteger('PairColors', 0);
  Store.WriteString('ServerPath', 'C:\Atlas\AtlasServer.exe');
  Assert.Contains(Routed.Text, '"slashCommands": {');
  Assert.Contains(Routed.Text, '"enabled": false');
  Assert.Contains(Routed.Text, '"parameterNames": true');
  Assert.Contains(Routed.Text, '"onSave": true');
  Assert.Contains(Routed.Text, '"metrics": false', 'codeLens.metrics in settings.json (#66)');
  // Treffersicherheit (#1119): Server und Plugin lesen denselben Wert.
  Assert.Contains(Routed.Text, '"references": {');
  Assert.Contains(Routed.Text, '"inferred": false');
  Assert.Contains(Routed.Text, '"textMatches": true');
  // Auswirkungsanalyse (#1120): navigation.* für Plugin, Server und MCP.
  Assert.Contains(Routed.Text, '"navigation": {');
  Assert.Contains(Routed.Text, '"impact": false');
  Assert.Contains(Routed.Text, '"impactDepth": 4');
  Assert.AreEqual(4, Store.ReadInteger('ImpactDepth', 2));
  Assert.AreEqual(0, Store.ReadInteger('ReferencesInferred', 1));
  Assert.AreEqual(-1, Registry.ReadInteger('ReferencesInferred', -1));
  // Reine Plugin-Werte bleiben in der Registry.
  Assert.DoesNotContain(Routed.Text, 'PairColors');
  Assert.AreEqual(0, Registry.ReadInteger('PairColors', 1));
  Assert.AreEqual('C:\Atlas\AtlasServer.exe', Registry.ReadString('ServerPath', ''));
  Assert.AreEqual(-1, Registry.ReadInteger('SlashCommands', -1));
  Assert.IsTrue(TAtlasSettingsScopes.TryRouted('indexusages', Setting));
  Assert.AreEqual('index.usages', Setting.Path);
  Assert.IsFalse(TAtlasSettingsScopes.TryRouted('PairColors', Setting));
  Assert.AreEqual(Integer(Length(TAtlasSettingsScopes.Routed) + 1), Integer(Length(TAtlasSettingsScopes.IdeManagedPaths)));
  Assert.AreEqual('delphiVersion', TAtlasSettingsScopes.IdeManagedPaths[0]);
end;
procedure TAtlasSettingsScopesTests.ArchitectureSettingsLiveInGlobalFile;
var
  Registry: IAtlasSettingsStore;
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // Architekturübersicht (#1118): Plugin und Server lesen architecture.* aus settings.json.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ArchitectureEnabled);
  Assert.AreEqual('projectGroup', Settings.ArchitectureScope);
  Assert.IsFalse(Settings.ArchitectureIncludeLibraryUnits);
  Assert.AreEqual(15, Settings.ArchitectureCentralUnits);
  Registry := TMemoryStore.Create;
  Routed := TAtlasRoutedSettingsStore.Create(Registry, '');
  Store := Routed;
  Settings.ArchitectureEnabled := False;
  Settings.ArchitectureScope := 'project';
  Settings.ArchitectureIncludeLibraryUnits := True;
  Settings.ArchitectureCentralUnits := 30;
  Settings.Save(Store);
  Assert.Contains(Routed.Text, '"architecture": {');
  Assert.Contains(Routed.Text, '"scope": "project"');
  Assert.Contains(Routed.Text, '"includeLibraryUnits": true');
  Assert.Contains(Routed.Text, '"centralUnits": 30');
  Assert.AreEqual(-1, Registry.ReadInteger('ArchitectureEnabled', -1), 'nicht in der Registry');
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.ArchitectureEnabled);
  Assert.AreEqual('project', Loaded.ArchitectureScope);
  Assert.IsTrue(Loaded.ArchitectureIncludeLibraryUnits);
  Assert.AreEqual(30, Loaded.ArchitectureCentralUnits);
  // Unbekannter Umfang und Zahl außerhalb der Grenzen fallen auf gültige Werte.
  Loaded.ArchitectureScope := 'irgendwas';
  Loaded.ArchitectureCentralUnits := 0;
  Loaded.Normalize;
  Assert.AreEqual('projectGroup', Loaded.ArchitectureScope);
  Assert.AreEqual(5, Loaded.ArchitectureCentralUnits);
  // Der Zustand „Fenster einmal rechts angelegt“ bleibt in der Registry.
  Assert.IsFalse(TAtlasPluginSettings.Defaults.ArchitectureWindowPlaced);
  Loaded.ArchitectureWindowPlaced := True;
  Loaded.Save(Store);
  Assert.AreEqual(1, Registry.ReadInteger('ArchitectureWindowPlaced', -1));
  // Ebenso für das Fenster „Unit-Beziehungen“ (#593).
  Assert.IsFalse(TAtlasPluginSettings.Defaults.UnitRelationsWindowPlaced);
  Loaded.UnitRelationsWindowPlaced := True;
  Loaded.Save(Store);
  Assert.AreEqual(1, Registry.ReadInteger('UnitRelationsWindowPlaced', -1));
end;
procedure TAtlasSettingsScopesTests.KeepsCommentsAndOtherKeys;
const
  Original = '{'#13#10'  // eigene Notiz'#13#10'  "language": "en",'#13#10'  "index": {"usages": true}'#13#10'}'#13#10;
var
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
begin
  Routed := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, Original);
  Store := Routed;
  // Gleicher Wert: Der Text bleibt genau gleich.
  Store.WriteInteger('IndexUsages', 1);
  Assert.AreEqual(Original, Routed.Text);
  Store.WriteInteger('IndexUsages', 0);
  Assert.Contains(Routed.Text, '// eigene Notiz');
  Assert.Contains(Routed.Text, '"language": "en"');
  Assert.Contains(Routed.Text, '"usages": false');
  Assert.AreEqual(0, Store.ReadInteger('IndexUsages', 1));
end;
procedure TAtlasSettingsScopesTests.MigratesRegistryValuesOnce;
var
  Registry: IAtlasSettingsStore;
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
begin
  // Bis hierher lagen Index und XMLDoc in der Registry; settings.json übernimmt sie einmal.
  Registry := TMemoryStore.Create;
  Registry.WriteInteger('IndexLibraryPaths', 1);
  Registry.WriteInteger('XmlDocMaxLines', 7);
  Routed := TAtlasRoutedSettingsStore.Create(Registry, '{"index": {"libraryPaths": false}}');
  Store := Routed;
  // Ohne Wert in settings.json gilt bis zur Übernahme der alte Wert.
  Assert.AreEqual(7, Store.ReadInteger('XmlDocMaxLines', 0));
  Assert.AreEqual(0, Store.ReadInteger('IndexLibraryPaths', 1), 'settings.json gewinnt');
  Assert.IsTrue(Routed.Migrate);
  Assert.Contains(Routed.Text, '"xmlDocMaxLines": 7');
  Assert.Contains(Routed.Text, '"libraryPaths": false');
  Assert.IsFalse(Routed.Migrate, 'nur einmal');
end;
procedure TAtlasSettingsScopesTests.LeavesBrokenFileAlone;
var
  Registry: IAtlasSettingsStore;
  Routed: TAtlasRoutedSettingsStore;
  Store: IAtlasSettingsStore;
begin
  Registry := TMemoryStore.Create;
  Registry.WriteInteger('IndexUsages', 0);
  Routed := TAtlasRoutedSettingsStore.Create(Registry, '{"index": ');
  Store := Routed;
  Assert.IsFalse(Routed.Migrate);
  Store.WriteInteger('IndexSearchPaths', 0);
  Assert.AreEqual('{"index": ', Routed.Text);
  Assert.AreEqual(0, Store.ReadInteger('IndexUsages', 1));
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
  Fields, Project, Global: TArray<TAtlasSettingField>;
  Field: TAtlasSettingField;
  Paths: string;
begin
  Fields := TAtlasSettingsSchema.Fields(AtlasSchemaJson);
  Project := TAtlasSettingsSchema.ForScope(Fields, False, nil);
  Global := TAtlasSettingsSchema.ForScope(Fields, True, TAtlasSettingsScopes.IdeManagedPaths);
  Paths := '|';
  for Field in Project do
  begin
    Paths := Paths + Field.Path + '|';
  end;
  Assert.Contains(Paths, '|rules|');
  Assert.Contains(Paths, '|index.exclude|');
  Assert.Contains(Paths, '|completion.senderCast|');
  Assert.DoesNotContain(Paths, '|index.projectGroup|');
  Assert.DoesNotContain(Paths, '|language|');
  // Unit-Zyklus beim Tippen (#896): Glied mit eigener Seite und eigenem Ort im sonst globalen diagnostics.
  Assert.Contains(Paths, '|diagnostics.usesCycleLive|');
  Assert.Contains(Paths, '|diagnostics.usesCycleImplementation|');
  Assert.DoesNotContain(Paths, '|diagnostics.log|');
  for Field in Project do
  begin
    if Field.Path = 'diagnostics.usesCycleLive' then
    begin
      Assert.AreEqual('Prüfregeln', Field.Page);
      Assert.AreEqual('true', Field.DefaultJson);
    end;
  end;
  Paths := '|';
  for Field in Global do
  begin
    Paths := Paths + Field.Path + '|';
  end;
  Assert.Contains(Paths, '|language|');
  Assert.Contains(Paths, '|completion.matching|');
  // Versionsverwaltung (#571) hat seit #1285 eine eigene Seite, Issue-Tracker seit #1260: Das ganze Objekt
  // ("vcs", "issues") enthält Glieder dieser Seiten und steht deshalb nicht im Dialog.
  Assert.DoesNotContain(Paths, '|vcs|');
  Assert.DoesNotContain(Paths, '|vcs.provider|');
  Assert.DoesNotContain(Paths, '|issues|');
  for Field in Fields do
  begin
    if Field.Path = 'vcs' then
    begin
      Assert.IsTrue(Field.Global, 'vcs bleibt global');
    end;
  end;
  // Auf den Reitern der Optionsseite bzw. von der IDE gesetzt: nicht noch einmal im Dialog.
  Assert.DoesNotContain(Paths, '|index.projectGroup|');
  Assert.DoesNotContain(Paths, '|hints.xmlDocFull|');
  Assert.DoesNotContain(Paths, '|delphiVersion|');
  // rules gilt an beiden Orten (x-scope "both"): Tabelle auch in den globalen Einstellungen.
  Assert.Contains(Paths, '|rules|');
  // Jedes umgeleitete Feld ist im Schema global.
  for Field in Fields do
  begin
    if Pos('|' + Field.Path + '|',
      '|index.projectGroup|memoryBudgetMb|compiler.onSave|slashCommands.enabled|references.inferred|') > 0 then
    begin
      Assert.IsTrue(Field.Global, Field.Path);
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
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Fenster „Atlas-Prüfung“, laufende Prüfung und Aktionen im Befund-Hover (#909).
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ProblemsWindow);
  Assert.AreEqual('group', Settings.ProblemsWindowScope);
  Assert.IsTrue(Settings.ProblemsWindowScopeProjects, 'Einzelprojekte (#1843) an');
  Assert.AreEqual('', Settings.ProblemsWindowScopeProject, 'aktives Projekt');
  Assert.AreEqual('file', Settings.ProblemsWindowGroupBy);
  Assert.AreEqual('', Settings.ProblemsWindowColumns);
  Assert.IsFalse(Settings.ProblemsWindowCompiler);
  Assert.IsTrue(Settings.ProblemsWindowFollowCursor);
  Assert.AreEqual($C050, Settings.ProblemsWindowKey, 'Strg+Alt+P');
  Assert.IsTrue(Settings.FixBulk, 'Sammelkorrektur (#1352) an');
  Assert.IsTrue(Settings.HoverProblemActions);
  Assert.IsFalse(Settings.ProblemsMessageList, 'Meldungsfenster-Gruppe seit dem Prüffenster aus');
  // Gruppe „Compiler vorab“ (#1024).
  Assert.AreEqual('merge', Settings.ProblemsCompilerMerge);
  Assert.IsTrue(Settings.ProblemsShowCompilerCode);
  Settings.ProblemsCompilerMerge := 'BOTH';
  Settings.Normalize;
  Assert.AreEqual('both', Settings.ProblemsCompilerMerge);
  Settings.ProblemsCompilerMerge := 'beides';
  Settings.Normalize;
  Assert.AreEqual('merge', Settings.ProblemsCompilerMerge, 'Unbekanntes = Vorgabe');
  Settings.ProblemsWindowScope := 'PROJECT';
  Settings.ProblemsWindowScopeProject := '  Atlas.Tests ';
  Settings.ProblemsWindowGroupBy := 'unsinn';
  Settings.ProblemsWindowKey := -1;
  Settings.Normalize;
  Assert.AreEqual('project', Settings.ProblemsWindowScope);
  Assert.AreEqual('Atlas.Tests', Settings.ProblemsWindowScopeProject);
  Assert.AreEqual('file', Settings.ProblemsWindowGroupBy, 'Unbekanntes = Vorgabe');
  Assert.AreEqual(0, Settings.ProblemsWindowKey);
  SetProblemsWindowOptions(Settings);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  AssertProblemsWindowLoaded(Loaded);
end;
procedure TAtlasPluginSettingsTests.ProblemsWindowOpenFirstOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ProblemsWindowOpenFirst);
  Assert.AreEqual('dimmed', Settings.ProblemsWindowClosedUnits);
  Assert.IsTrue(Settings.ProblemsWindowShowCleanActive);
  Settings.ProblemsWindowClosedUnits := 'HIDDEN';
  Settings.Normalize;
  Assert.AreEqual('hidden', Settings.ProblemsWindowClosedUnits);
  Settings.ProblemsWindowClosedUnits := 'grau';
  Settings.Normalize;
  Assert.AreEqual('dimmed', Settings.ProblemsWindowClosedUnits, 'Unbekanntes = Vorgabe');
  Settings.ProblemsWindowOpenFirst := False;
  Settings.ProblemsWindowClosedUnits := 'normal';
  Settings.ProblemsWindowShowCleanActive := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.ProblemsWindowOpenFirst);
  Assert.AreEqual('normal', Loaded.ProblemsWindowClosedUnits);
  Assert.IsFalse(Loaded.ProblemsWindowShowCleanActive);
end;
initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginSettingsTests);
  TDUnitX.RegisterTestFixture(TAtlasSettingsScopesTests);

end.
