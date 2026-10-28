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
    [Test]
    procedure ProblemsWindowOptions;
    /// <summary>#1108: offene Units zuerst, nicht geöffnete Units, aktive Unit ohne Befunde.</summary>
    [Test]
    procedure ProblemsWindowOpenFirstOptions;
    /// <summary>#1101: Atlas-Editorleiste, Lage, Belegung, Rücksprung, Text, Tasten der Abschnittssprünge.</summary>
    [Test]
    procedure EditorToolbarOptions;
    /// <summary>#1155: Atlas-Statusleiste an, alle Elemente in Vorgabe-Reihenfolge; Bereinigen, Speichern, Laden.
    /// </summary>
    [Test]
    procedure EditorStatusBarOptions;
    /// <summary>#1122: Aufrufdiagramm standardmäßig an, abschaltbar, übersteht Speichern und Laden.</summary>
    [Test]
    procedure CallHierarchyDiagramOption;
    /// <summary>Schnelle Lesezeichen (#1104): Vorgaben laut Issue, Grenzen, Speichern und Laden.</summary>
    [Test]
    procedure QuickBookmarkOptions;
    [Test]
    procedure SaveAndLoadRoundTrip;
    [Test]
    procedure ClampsOutOfRangeValues;
    [Test]
    procedure IndexOptionsGoToGlobalFile;
    [Test]
    procedure XmlDocOptionsGoToGlobalFile;
    /// <summary>#1260: issues.connections als JSON-Liste in settings.json, nie in der Registry; leere Liste
    /// ohne Eintrag, kaputter Text nie in die Datei.</summary>
    [Test]
    procedure IssuesConnectionsGoToGlobalFile;
    [Test]
    procedure AcceptOptionsRoundTrip;
    [Test]
    procedure OneActionAfterSaving;
    [Test]
    procedure UnitSearchOptions;
    [Test]
    procedure QuickOpenOptions;
    [Test]
    procedure NavHistoryOptions;
    [Test]
    procedure PeekOptions;
    [Test]
    procedure DataFlowOptions;
    /// <summary>Gliederungsfenster (#537): an, Quelltextreihenfolge, Cursor folgen; Speichern und Laden.</summary>
    [Test]
    procedure OutlineOptions;
    [Test]
    procedure CompletionVariantBranchOption;
    [Test]
    procedure BreadcrumbsOptions;
    [Test]
    procedure JumpToMatchOptions;
    [Test]
    procedure MoveLinesOptions;
    /// <summary>Kommentar beim Enter fortsetzen (#696): Vorgaben, Speichern, Laden, Präfix normalisieren.</summary>
    [Test]
    procedure ContinueCommentsOptions;
    /// <summary>Anweisung vervollständigen (#697): Vorgaben, Speichern, Laden, unbekannte Werte.</summary>
    [Test]
    procedure CompleteStatementOptions;
    /// <summary>#43: Befehl „Formatieren“ mit eigenem Kürzel.</summary>
    [Test]
    procedure FormatCodeOptions;
    [Test]
    procedure ContinuePatternOptions;
    [Test]
    procedure MultiCursorOptions;
    [Test]
    procedure SmartPasteOptions;
    [Test]
    procedure StickyScrollOptions;
    [Test]
    procedure MinimapOptions;
    /// <summary>Änderungsmarken und Zeilenhistorie (#507): Vorgaben, Tasten, Speichern und Laden.</summary>
    [Test]
    procedure GitChangeOptions;
    /// <summary>Atlas-Spalte in der Zeilenleiste (#768): Vorgaben, Unterschalter, Speichern und Laden.</summary>
    [Test]
    procedure GutterColumnOptions;
    /// <summary>Gleichen Text hervorheben (#709): Vorgaben, Grenzen, Speichern und Laden.</summary>
    [Test]
    procedure SelectionMatchesOptions;
    /// <summary>Blockkommentar umschalten (#703): Vorgaben, Auswahlwerte normalisiert, Speichern und Laden.</summary>
    [Test]
    procedure ToggleBlockCommentOptions;
    /// <summary>Neue Zeile ober- oder unterhalb (#700): Vorgaben, Speichern und Laden.</summary>
    [Test]
    procedure NewLineAroundOptions;
    /// <summary>Umschließung entfernen (#657): Vorgaben, Speichern und Laden, Kürzel normalisiert.</summary>
    [Test]
    procedure UnwrapOptions;
    [Test]
    procedure ExpressionTypeOptions;
    /// <summary>Methodenrümpfe in Deklarationsreihenfolge (#660): Vorgabe, Werte normalisiert, Speichern und
    /// Laden.</summary>
    [Test]
    procedure MethodPlacementOptions;
    [Test]
    procedure SafeDeleteOptions;
    /// <summary>Markierung beim Tippen umschließen (#672): Vorgaben, Speichern und Laden.</summary>
    [Test]
    procedure WrapSelectionOptions;
    /// <summary>Übersichtsleiste (#519): Vorgaben, Arten normalisiert, Speichern und Laden.</summary>
    [Test]
    procedure OverviewRulerOptions;
    [Test]
    procedure DebugVisualizerOptions;
    [Test]
    procedure DebugDisplayRuleOptions;
    [Test]
    procedure DebugStepIntoTargetOptions;
    [Test]
    procedure DebugBreakOnNextEventOptions;
    [Test]
    procedure DebugStepFilterOptions;
    /// <summary>Erzeugen-Menü (#719): Vorgaben, Normalisieren, Speichern und Laden.</summary>
    [Test]
    procedure GenerateMenuOptions;
    /// <summary>Ausblenden am Element (#628): Blockende-Beschriftung und Taste, Vorgaben, Speichern und Laden.
    /// </summary>
    [Test]
    procedure HideElementOptions;
    /// <summary>Benachrichtigungszentrale (#601): Vorgaben, Grenzen, Verhalten je Quelle, Speichern und Laden.
    /// </summary>
    [Test]
    procedure NotificationOptions;
    /// <summary>Schnellaktionen der Willkommensseite (#764): Vorgaben, Normalisieren, Speichern und Laden.</summary>
    [Test]
    procedure WelcomeQuickActionOptions;
    /// <summary>Meine Issues (#765): Vorgaben, Normalisieren (Leerzeichen am Ende des Commit-Musters bleibt),
    /// Speichern und Laden.</summary>
    [Test]
    procedure WelcomeIssuesOptions;
    /// <summary>Release-Build-Wächter (#533): build.releaseGuard, build.gate, build.releaseConfigs und
    /// build.releaseChecks mit Vorgaben, Normalisieren, Speichern und Laden.</summary>
    [Test]
    procedure ReleaseGuardOptions;
    [Test]
    procedure TasksOptions;
    /// <summary>Prüfung vor dem Compile (#529): build.gateTimeoutMs mit Vorgabe, Grenzen, Speichern und Laden.
    /// </summary>
    [Test]
    procedure BuildGateTimeoutOption;
    /// <summary>Schranke für Hinweise und Warnungen (#530): build.summary und build.warningsAsErrors mit Vorgaben,
    /// Normalisieren, Speichern und Laden.</summary>
    [Test]
    procedure BuildSummaryOptions;
    /// <summary>Beim Öffnen bauen: build.onOpen, build.onOpenKind, build.onOpenScope, build.onOpenDelayMs und
    /// build.onOpenExclude mit Vorgaben, Normalisieren, Speichern und Laden.</summary>
    [Test]
    procedure BuildOnOpenOptions;
    [Test]
    procedure CompletionListModeOptions;
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
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Welcome.QuickActions,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tracker.Naming,
  Atlas.Core.Welcome.Issues,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.Scopes,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.Settings.StatusBarItems;

type
  TMemoryStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FValues: TDictionary<string, Integer>;
    FStrings: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

{ TMemoryStore }

constructor TMemoryStore.Create;
begin
  inherited Create;
  FValues := TDictionary<string, Integer>.Create;
  FStrings := TDictionary<string, string>.Create;
end;

destructor TMemoryStore.Destroy;
begin
  FStrings.Free;
  FValues.Free;
  inherited Destroy;
end;

function TMemoryStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  if not FValues.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TMemoryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

function TMemoryStore.ReadString(const AName, ADefault: string): string;
begin
  if not FStrings.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TMemoryStore.WriteString(const AName, AValue: string);
begin
  FStrings.AddOrSetValue(AName, AValue);
end;

{ TAtlasPluginSettingsTests }

procedure TAtlasPluginSettingsTests.EmptyStoreGivesDefaults;
var
  Store: IAtlasSettingsStore;
  Settings: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.IsTrue(Settings.Enabled);
  Assert.AreEqual(9, Settings.VisibleRows);
  Assert.AreEqual(0, Settings.ListWidth, 'Liste automatisch');
  Assert.AreEqual(320, Settings.PanelWidth);
  Assert.IsTrue(Settings.AutoParentheses);
  Assert.IsFalse(Settings.Preview, 'Vorschau standardmäßig aus (#434)');
  Assert.IsTrue(Settings.OpenForEdits, 'Nicht geöffnete Dateien öffnen (#397)');
  Assert.IsFalse(Settings.InlayHints, 'Inlay-Hints standardmäßig aus (#401)');
  Assert.AreEqual($800D, Settings.ActionsKey, 'Code-Aktionen: Alt+Enter (#399)');
  Assert.AreEqual(0, Settings.TypeDefinitionKey, 'Typdefinition ohne Kürzel');
  Assert.IsTrue(Settings.MethodToggle, 'Deklaration/Implementierung wechseln standardmäßig an (#775)');
  Assert.AreEqual($6026, Settings.MethodToggleUpKey, 'Strg+Umschalt+Hoch (#775)');
  Assert.AreEqual($6028, Settings.MethodToggleDownKey, 'Strg+Umschalt+Runter (#775)');
  Assert.AreEqual(0, Settings.TestUnitKey, 'Testunit-Wechsel ohne Kürzel (#189)');
  Assert.IsTrue(Settings.CodeLensTestUnit, 'Code Lens Testunit standardmäßig an (#189)');
  Assert.IsTrue(Settings.CodeLensMetrics, 'Code Lens Metriken standardmäßig an (#66)');
  Assert.IsTrue(Settings.ReferencesInferred, 'erschlossene Verwendungen standardmäßig an (#1119)');
  Assert.IsFalse(Settings.ReferencesTextMatches, 'Textfunde standardmäßig aus (#1119)');
  Assert.IsTrue(Settings.Impact, 'Auswirkungen anzeigen standardmäßig an (#1120)');
  Assert.AreEqual(2, Settings.ImpactDepth, 'Tiefe der Auswirkungsanalyse standardmäßig 2 (#1120)');
  Assert.IsTrue(Settings.CodeLensTests, 'Code Lens „Test ausführen“ standardmäßig an (#69)');
  Assert.IsTrue(Settings.TestRun, 'Tests ausführen standardmäßig da (#69)');
  Assert.IsFalse(Settings.TestsAfterBuild, 'Tests nach dem Build standardmäßig aus (#69)');
  Assert.IsTrue(Settings.TestsBuildFirst, 'vor den Tests bauen standardmäßig an (#69)');
  Assert.IsFalse(Settings.BuildZeroHints, 'build.zeroHints standardmäßig aus (#530)');
  Assert.IsTrue(Settings.ShowInterfaceCost, 'build.showInterfaceCost standardmäßig an (#554)');
  Assert.IsTrue(Settings.BuildCompilerSwitches, 'build.compilerSwitches (#558)');
  Assert.IsFalse(Settings.BuildSwitchesInStatusBar, 'build.showSwitchesInStatusBar (#558)');
  Assert.IsTrue(Settings.StartProfiles, 'Startprofile standardmäßig an (#575)');
  Assert.IsTrue(Settings.StartProfilesStatusField, 'Startprofil in der Statusleiste standardmäßig an (#575)');
  Assert.IsTrue(Settings.TestDebug, 'Test debuggen standardmäßig da (#585)');
  Assert.IsTrue(Settings.TestBreakAtStart, 'debug.testBreakAtStart standardmäßig an (#585)');
  Assert.IsTrue(Settings.DebugHoverValues, 'debug.hoverValues standardmäßig an (#891)');
  Assert.IsTrue(Settings.DebugExplainUnavailable, 'debug.explainUnavailable (#840)');
  Assert.IsTrue(Settings.DebugCompletionInDialogs, 'debug.completionInDialogs (#538)');
  Assert.IsTrue(Settings.DebugEvaluateWindow, 'debug.evaluateWindow (#784)');
  Assert.IsTrue(Settings.DebugEvaluateReplaceCtrlF7, 'debug.evaluateWindow.replaceCtrlF7 (#784)');
  Assert.IsTrue(Settings.DebugExplainAccessViolation, 'debug.explainAccessViolation (#865)');
  Assert.IsFalse(Settings.DebugExplainAccessViolationAllowCalls, 'debug.explainAccessViolation.allowCalls (#865)');
  Assert.IsTrue(Settings.DebugExceptionHistory, 'debug.exceptionHistory (#517)');
  Assert.IsTrue(Settings.DebugJustMyCode, 'debug.justMyCode (#578)');
  Assert.IsFalse(Settings.DebugExceptionBanner, 'debug.exceptionBanner (#783)');
  Assert.IsTrue(Settings.DebugExceptionBannerIgnoreAtLocation, 'debug.exceptionBanner.ignoreAtLocation (#783)');
  Assert.IsTrue(Settings.DebugInlineValues, 'debug.inlineValues (#508)');
  Assert.AreEqual(5, Settings.DebugInlineValuesPerLine, 'debug.inlineValuesPerLine (#508)');
  Assert.AreEqual('', Settings.DebugOwnCodeFolders, 'debug.ownCodeFolders leer (#578)');
  Assert.IsTrue(Settings.TodoList, 'Befehl standardmäßig da (#68)');
  Assert.IsTrue(Settings.MetricsReport, 'Befehl standardmäßig da (#66)');
  Assert.IsTrue(Settings.TeamFile, 'Projektdatei standardmäßig an (#486)');
  Assert.IsTrue(Settings.McpBuild, 'Builds für Claude Code standardmäßig erlaubt (#261)');
  Assert.IsTrue(Settings.BaselineUpdate, 'Befehl standardmäßig da (#97)');
  Assert.IsTrue(Settings.SlashCommands, 'Schnellbefehle standardmäßig an (#399)');
  Assert.IsTrue(Settings.Snippets, 'Code-Vorlagen standardmäßig an (#51)');
  Assert.IsTrue(Settings.ImportIdeTemplates, 'Live Templates der IDE standardmäßig an (#51)');
  // Vervollständigung und Parameter-Hint über die Tasten der IDE, ohne eigene Belegung (#494).
  Assert.AreEqual(0, Settings.CompletionKey);
  Assert.AreEqual(0, Settings.SignatureKey);
  Assert.IsFalse(Settings.SignatureKeyPriority);
  Assert.AreEqual(200, Settings.ProviderTimeLimitMs, 'Zeitlimit für Quellen (#493)');
  Assert.AreEqual($E041, Settings.QuickToggleKey, 'Schnellschalter: Strg+Umschalt+Alt+A (#604)');
  Assert.IsFalse(Settings.QuickToggleKeyPriority);
  // Diagnosemodus (#479): aus; Taste Strg+Umschalt+Alt+D, weil A den Schnellschaltern gehört.
  Assert.IsFalse(Settings.DiagnosticMode);
  Assert.AreEqual($E044, Settings.DiagnosticModeKey);
  Assert.IsFalse(Settings.DiagnosticModeKeyPriority);
  // Prozesse am Projekt (#62).
  Assert.IsTrue(Settings.DiagnosticsProcesses);
  // Einrichtung mit Prüfliste (#625): beim Start zeigen, solange nicht alles grün ist; noch nie gesehen.
  Assert.IsTrue(Settings.SetupChecklist);
  Assert.IsFalse(Settings.SetupChecklistSeen);
  // Tastenkürzel-Übersicht (#520): Menüeintrag und Startprüfung an.
  Assert.IsTrue(Settings.KeyOverview);
  Assert.IsTrue(Settings.KeyStartupCheck);
  // Tastenkürzel-Tipps (#600): an, für Atlas und IDE.
  Assert.IsTrue(Settings.ShortcutTips);
  Assert.AreEqual('all', Settings.ShortcutTipsScope);
  // Abgesicherter Start (#722).
  Assert.IsTrue(Settings.SafeAskAfterCrash);
  Assert.IsTrue(Settings.SafeAutoAfterRepeatedCrash);
  Assert.AreEqual('shift', Settings.SafeStartupKey);
  Assert.AreEqual(30000, Settings.SafeStartupTimeoutMs);
  Assert.AreEqual(5, Settings.SafeKeepSettingsHistory);
  // Dateiübergreifendes Zurücknehmen (#721).
  Assert.IsTrue(Settings.UndoMultiFile);
  Assert.AreEqual(20, Settings.UndoMultiFileDepth);
  Assert.IsTrue(Settings.UndoMultiFilePersist);
  Assert.AreEqual(50, Settings.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('partial', Settings.UndoMultiFileOnConflict);
  Assert.AreEqual('recycleBin', Settings.UndoMultiFileNewFiles);
  Assert.AreEqual($C05A, Settings.UndoKey, 'Strg+Alt+Z');
  Assert.AreEqual($E05A, Settings.RedoKey, 'Strg+Alt+Umschalt+Z');
  Assert.IsFalse(Settings.UpdatesCheck, 'Update-Prüfung nur nach Zustimmung');
  Assert.IsTrue(Settings.BugReportAnonymize, 'Fehlerbericht anonymisiert');
  Assert.IsTrue(Settings.PairOwners, 'Anweisungen mitfärben standardmäßig an (#653)');
  Assert.AreEqual(1, Settings.PairGuideWidth, 'Blocklinien 1 px');
  Assert.AreEqual(75, Settings.PairGuideOpacity, 'Blocklinien 75 % Deckkraft');
  Assert.IsFalse(Settings.ProblemsList, 'Liste „Atlas-Probleme“ seit dem Prüffenster (#909) standardmäßig aus');
  Assert.IsTrue(Settings.Favorites, 'Favoriten anheften standardmäßig an (#458)');
  Assert.IsTrue(Settings.Notes, 'Notizen standardmäßig an (#545)');
  Assert.IsTrue(Settings.BookmarksNamed, 'Benannte Lesezeichen standardmäßig an (#622)');
  Assert.IsFalse(Settings.BookmarksShared, 'Lesezeichen standardmäßig lokal, nicht im Repository (#622)');
  Assert.AreEqual($C04B, Settings.BookmarkKey, 'Strg+Alt+K (#622)');
end;

procedure TAtlasPluginSettingsTests.SaveAndLoadRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Settings := TAtlasPluginSettings.Defaults;
  Settings.Enabled := False;
  Settings.VisibleRows := 14;
  Settings.ListWidth := 500;
  Settings.PanelWidth := 400;
  Settings.PanelCollapsed := True;
  Settings.Learning := False;
  Settings.Favorites := False;
  Settings.Notes := False;
  Settings.BookmarksNamed := False;
  Settings.BookmarksShared := True;
  Settings.BookmarkKey := $C04C;
  Settings.Preview := True;
  Settings.OpenForEdits := False;
  Settings.InlayHints := True;
  Settings.ActionsKey := 0;
  Settings.ExpandKey := $4041;
  Settings.TypeDefinitionKey := $C054;
  Settings.MethodToggle := False;
  Settings.MethodToggleUpKey := 0;
  Settings.MethodToggleDownKey := $C044; // Strg+Alt+D
  Settings.TestUnitKey := $6054;
  Settings.CodeLensTestUnit := False;
  Settings.CodeLensMetrics := False;
  Settings.CodeLensTests := False;
  Settings.TestRun := False;
  Settings.TestsAfterBuild := True;
  Settings.TestsBuildFirst := False;
  Settings.BuildZeroHints := True;
  Settings.ShowInterfaceCost := False;
  Settings.BuildCompilerSwitches := False;
  Settings.BuildSwitchesInStatusBar := True;
  Settings.StartProfiles := False;
  Settings.StartProfilesStatusField := False;
  Settings.TestDebug := False;
  Settings.TestBreakAtStart := False;
  Settings.DebugHoverValues := False;
  Settings.DebugExplainUnavailable := False;
  Settings.DebugCompletionInDialogs := False;
  Settings.DebugEvaluateWindow := False;
  Settings.DebugEvaluateReplaceCtrlF7 := False;
  Settings.DebugExplainAccessViolation := False;
  Settings.DebugExplainAccessViolationAllowCalls := True;
  Settings.DebugExceptionHistory := False;
  Settings.DebugJustMyCode := False;
  Settings.DebugExceptionBanner := True;
  Settings.DebugExceptionBannerIgnoreAtLocation := False;
  Settings.DebugInlineValues := False;
  Settings.DebugInlineValuesPerLine := 7;
  Settings.DebugOwnCodeFolders := '  C:\Komponenten;D:\Lib ';
  Settings.TodoList := False;
  Settings.MetricsReport := False;
  Settings.TeamFile := False;
  Settings.McpBuild := False;
  Settings.BaselineUpdate := False;
  Settings.EditorKeysPriority := True;
  Settings.SlashCommands := False;
  Settings.Snippets := False;
  Settings.ImportIdeTemplates := False;
  Settings.ServerPath := '  D:\Atlas\AtlasServer.exe ';
  Settings.SignatureKey := $6048; // Strg+Umschalt+H
  Settings.SignatureKeyPriority := True;
  Settings.CompletionKey := $4020; // Strg+Leer
  Settings.ProviderTimeLimitMs := 350;
  Settings.QuickToggleKey := $6051;
  Settings.QuickToggleKeyPriority := True;
  Settings.DiagnosticMode := True;
  Settings.DiagnosticModeKey := $6044;
  Settings.DiagnosticModeKeyPriority := True;
  Settings.DiagnosticsProcesses := False;
  Settings.SetupChecklist := False;
  Settings.SetupChecklistSeen := True;
  Settings.KeyOverview := False;
  Settings.KeyStartupCheck := False;
  Settings.ShortcutTips := False;
  Settings.ShortcutTipsScope := 'atlas';
  Settings.SafeAskAfterCrash := False;
  Settings.SafeAutoAfterRepeatedCrash := False;
  Settings.SafeStartupKey := 'none';
  Settings.SafeStartupTimeoutMs := 30000;
  Settings.SafeKeepSettingsHistory := 0;
  Settings.UndoMultiFile := False;
  Settings.UndoMultiFileDepth := 7;
  Settings.UndoMultiFilePersist := False;
  Settings.UndoMultiFileMaxSizeMb := 3;
  Settings.UndoMultiFileOnConflict := 'abort';
  Settings.UndoMultiFileNewFiles := 'keep';
  Settings.UndoKey := 0;
  Settings.RedoKey := $C059;
  Settings.UpdatesCheck := True;
  Settings.BugReportAnonymize := False;
  Settings.ProblemsList := True;
  Settings.PairOwners := False;
  Settings.PairGuideWidth := 3;
  Settings.PairGuideOpacity := 80;
  Settings.PairColorsDark := '#112233, #445566,#778899,#aabbcc,#DDEEFF';
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Enabled);
  Assert.AreEqual(14, Loaded.VisibleRows);
  Assert.AreEqual(500, Loaded.ListWidth);
  Assert.AreEqual(400, Loaded.PanelWidth);
  Assert.IsTrue(Loaded.PanelCollapsed);
  Assert.IsFalse(Loaded.Learning);
  Assert.IsFalse(Loaded.Favorites, 'Favoriten abschaltbar (#458)');
  Assert.IsFalse(Loaded.Notes, 'Notizen abschaltbar (#545)');
  Assert.IsFalse(Loaded.BookmarksNamed, 'Benannte Lesezeichen abschaltbar (#622)');
  Assert.IsTrue(Loaded.BookmarksShared, 'Lesezeichen für das Team (#622)');
  Assert.AreEqual($C04C, Loaded.BookmarkKey);
  Assert.IsTrue(Loaded.Preview);
  Assert.IsFalse(Loaded.OpenForEdits);
  Assert.IsTrue(Loaded.InlayHints);
  Assert.AreEqual(0, Loaded.ActionsKey, '0 = keine Taste');
  Assert.AreEqual($4041, Loaded.ExpandKey);
  Assert.AreEqual($6057, Loaded.ShrinkKey);
  Assert.AreEqual($C054, Loaded.TypeDefinitionKey);
  Assert.IsFalse(Loaded.MethodToggle);
  Assert.AreEqual(0, Loaded.MethodToggleUpKey, '0 = keine Taste');
  Assert.AreEqual($C044, Loaded.MethodToggleDownKey);
  Assert.AreEqual($6054, Loaded.TestUnitKey);
  Assert.IsFalse(Loaded.CodeLensTestUnit);
  Assert.IsFalse(Loaded.CodeLensMetrics);
  Assert.IsFalse(Loaded.CodeLensTests);
  Assert.IsFalse(Loaded.TestRun);
  Assert.IsTrue(Loaded.TestsAfterBuild);
  Assert.IsFalse(Loaded.TestsBuildFirst);
  Assert.IsTrue(Loaded.BuildZeroHints);
  Assert.IsFalse(Loaded.ShowInterfaceCost, 'build.showInterfaceCost (#554)');
  Assert.IsFalse(Loaded.BuildCompilerSwitches);
  Assert.IsTrue(Loaded.BuildSwitchesInStatusBar);
  Assert.IsFalse(Loaded.StartProfiles);
  Assert.IsFalse(Loaded.StartProfilesStatusField);
  Assert.IsFalse(Loaded.TestDebug, 'Test debuggen (#585)');
  Assert.IsFalse(Loaded.TestBreakAtStart, 'debug.testBreakAtStart (#585)');
  Assert.IsFalse(Loaded.DebugHoverValues, 'debug.hoverValues (#891)');
  Assert.IsFalse(Loaded.DebugExplainUnavailable, 'debug.explainUnavailable (#840)');
  Assert.IsFalse(Loaded.DebugCompletionInDialogs, 'debug.completionInDialogs (#538)');
  Assert.IsFalse(Loaded.DebugEvaluateWindow, 'debug.evaluateWindow (#784)');
  Assert.IsFalse(Loaded.DebugEvaluateReplaceCtrlF7, 'debug.evaluateWindow.replaceCtrlF7 (#784)');
  Assert.IsFalse(Loaded.DebugExplainAccessViolation, 'debug.explainAccessViolation (#865)');
  Assert.IsTrue(Loaded.DebugExplainAccessViolationAllowCalls, 'debug.explainAccessViolation.allowCalls (#865)');
  Assert.IsFalse(Loaded.DebugExceptionHistory, 'debug.exceptionHistory (#517)');
  Assert.IsFalse(Loaded.DebugJustMyCode, 'debug.justMyCode (#578)');
  Assert.IsTrue(Loaded.DebugExceptionBanner, 'debug.exceptionBanner (#783)');
  Assert.IsFalse(Loaded.DebugExceptionBannerIgnoreAtLocation, 'debug.exceptionBanner.ignoreAtLocation (#783)');
  Assert.IsFalse(Loaded.DebugInlineValues, 'debug.inlineValues (#508)');
  Assert.AreEqual(7, Loaded.DebugInlineValuesPerLine, 'debug.inlineValuesPerLine (#508)');
  Assert.AreEqual('C:\Komponenten;D:\Lib', Loaded.DebugOwnCodeFolders, 'debug.ownCodeFolders ohne Leerraum (#578)');
  Assert.IsFalse(Loaded.TodoList);
  Assert.IsFalse(Loaded.MetricsReport);
  Assert.IsFalse(Loaded.TeamFile);
  Assert.IsFalse(Loaded.McpBuild);
  Assert.IsFalse(Loaded.BaselineUpdate);
  Assert.IsTrue(Loaded.EditorKeysPriority);
  Assert.IsFalse(Loaded.SlashCommands);
  Assert.IsFalse(Loaded.Snippets);
  Assert.IsFalse(Loaded.ImportIdeTemplates);
  Assert.IsFalse(Loaded.PairOwners);
  Assert.AreEqual(3, Loaded.PairGuideWidth);
  Assert.AreEqual(80, Loaded.PairGuideOpacity);
  Assert.AreEqual('#112233,#445566,#778899,#AABBCC,#DDEEFF', Loaded.PairColorsDark, 'einheitlich geschrieben');
  Assert.IsTrue(Loaded.ProblemsList, 'Liste „Atlas-Probleme“ eingeschaltet');
  Assert.IsTrue(Loaded.Problems, 'Wellenlinien bleiben an');
  Assert.AreEqual('D:\Atlas\AtlasServer.exe', Loaded.ServerPath, 'Serverpfad ohne Leerraum');
  Assert.AreEqual($6048, Loaded.SignatureKey);
  Assert.IsTrue(Loaded.SignatureKeyPriority);
  Assert.AreEqual($4020, Loaded.CompletionKey);
  Assert.IsFalse(Loaded.CompletionKeyPriority);
  Assert.AreEqual(350, Loaded.ProviderTimeLimitMs);
  Assert.AreEqual($6051, Loaded.QuickToggleKey);
  Assert.IsTrue(Loaded.QuickToggleKeyPriority);
  Assert.IsTrue(Loaded.DiagnosticMode);
  Assert.AreEqual($6044, Loaded.DiagnosticModeKey);
  Assert.IsTrue(Loaded.DiagnosticModeKeyPriority);
  Assert.IsFalse(Loaded.DiagnosticsProcesses);
  Assert.IsFalse(Loaded.SetupChecklist);
  Assert.IsTrue(Loaded.SetupChecklistSeen);
  Assert.IsFalse(Loaded.KeyOverview);
  Assert.IsFalse(Loaded.KeyStartupCheck);
  Assert.IsFalse(Loaded.ShortcutTips);
  Assert.AreEqual('atlas', Loaded.ShortcutTipsScope);
  Assert.IsFalse(Loaded.SafeAskAfterCrash);
  Assert.IsFalse(Loaded.SafeAutoAfterRepeatedCrash);
  Assert.AreEqual('none', Loaded.SafeStartupKey);
  Assert.AreEqual(30000, Loaded.SafeStartupTimeoutMs);
  Assert.AreEqual(0, Loaded.SafeKeepSettingsHistory);
  Assert.IsFalse(Loaded.UndoMultiFile);
  Assert.AreEqual(7, Loaded.UndoMultiFileDepth);
  Assert.IsFalse(Loaded.UndoMultiFilePersist);
  Assert.AreEqual(3, Loaded.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('abort', Loaded.UndoMultiFileOnConflict);
  Assert.AreEqual('keep', Loaded.UndoMultiFileNewFiles);
  Assert.AreEqual(0, Loaded.UndoKey);
  Assert.AreEqual($C059, Loaded.RedoKey);
  Assert.IsTrue(Loaded.UpdatesCheck);
  Assert.IsFalse(Loaded.BugReportAnonymize);
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
  Assert.AreEqual(TAtlasPluginSettings.MaxMemoryBudgetMb, Loaded.MemoryBudgetMb);
end;

procedure TAtlasPluginSettingsTests.IssuesConnectionsGoToGlobalFile;
const
  cList = '[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local"}]';
var
  mRegistry, mStore: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('[]', mSettings.IssuesConnections);
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mSettings.Save(mStore);
  Assert.IsFalse(mRouted.Text.Contains('issues'), 'leere Liste ohne Eintrag: ' + mRouted.Text);
  mSettings.IssuesConnections := cList;
  mSettings.Save(mStore);
  Assert.Contains(mRouted.Text, '"connections": [{"name": "Firma"');
  Assert.AreEqual('', mRegistry.ReadString('IssuesConnections', ''), 'nicht in der Registry');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.IssuesConnections.Contains('"Firma"'), mLoaded.IssuesConnections);
  // Kaputter Text kommt nie in die Datei; der gespeicherte Stand bleibt.
  mStore.WriteString('IssuesConnections', '[{"name": ');
  Assert.Contains(mRouted.Text, '"Firma"');
  // Falsche Art in der Datei (der Server meldet sie): Vorgabe.
  mRouted := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, '{"issues": {"connections": "Firma"}}');
  mStore := mRouted;
  mLoaded.Load(mStore);
  Assert.AreEqual('[]', mLoaded.IssuesConnections);
  Assert.IsTrue(MatchText('issues.connections', TAtlasSettingsScopes.IdeManagedPaths), 'nicht im Dialog');
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
  Assert.AreEqual(TAtlasPluginSettings.MaxXmlDocLines, Loaded.XmlDocMaxLines);
  Store.WriteInteger('XmlDocMaxLines', -3);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.XmlDocMaxLines);
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
  Assert.AreEqual(TAtlasPluginSettings.MaxOpenDelay, Loaded.OpenDelayMs);
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
  Assert.AreEqual(TAtlasPluginSettings.MinProviderTimeLimit, Settings.ProviderTimeLimitMs);
  Assert.AreEqual(0, Settings.SignatureKey, 'kein gültiges Kürzel');
  Store.WriteInteger('PairGuideWidth', 7);
  Store.WriteInteger('PairGuideOpacity', 0);
  Store.WriteString('PairColorsLight', '#123456,blau');
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MaxPairGuideWidth, Settings.PairGuideWidth);
  Assert.AreEqual(TAtlasPluginSettings.MinPairGuideOpacity, Settings.PairGuideOpacity);
  Assert.AreEqual('', Settings.PairColorsLight, 'ungültige Farben = Standard');
  Assert.AreEqual(TAtlasPluginSettings.MaxVisibleRows, Settings.VisibleRows);
  Assert.AreEqual(TAtlasPluginSettings.MinListWidth, Settings.ListWidth);
  Assert.AreEqual(TAtlasPluginSettings.MaxPanelWidth, Settings.PanelWidth);
  Assert.AreEqual(TAtlasPluginSettings.MinSafeStartupTimeout, Settings.SafeStartupTimeoutMs);
  Assert.AreEqual(TAtlasPluginSettings.MaxSafeSettingsHistory, Settings.SafeKeepSettingsHistory);
  Assert.AreEqual('shift', Settings.SafeStartupKey, 'unbekannte Taste: Umschalt');
  Assert.AreEqual(TAtlasPluginSettings.MinUndoDepth, Settings.UndoMultiFileDepth);
  Assert.AreEqual(TAtlasPluginSettings.MaxUndoMaxSizeMb, Settings.UndoMultiFileMaxSizeMb);
  Assert.AreEqual('abort', Settings.UndoMultiFileOnConflict);
  Assert.AreEqual('recycleBin', Settings.UndoMultiFileNewFiles, 'unbekannt: Papierkorb');
  // shortcutTips.scope (#600): nur atlas oder all.
  Assert.AreEqual('atlas', Settings.ShortcutTipsScope);
  Settings.ShortcutTipsScope := 'ide';
  Settings.Normalize;
  Assert.AreEqual('all', Settings.ShortcutTipsScope, 'unbekannt: all');
  // navigation.impactDepth (#1120): 1 bis 5.
  Settings.ImpactDepth := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinImpactDepth, Settings.ImpactDepth);
  Settings.ImpactDepth := 9;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxImpactDepth, Settings.ImpactDepth);
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

procedure TAtlasPluginSettingsTests.GenerateMenuOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.GenerateMenu, 'standardmäßig an');
  Assert.AreEqual($802D, Settings.GenerateMenuKey, 'Alt+Einfg');
  Assert.AreEqual('generate,surround,templates', Settings.GenerateMenuGroups);
  Assert.AreEqual('', Settings.GenerateMenuHidden);
  Assert.IsTrue(Settings.GenerateMenuRecentFirst);
  Assert.IsTrue(Settings.GenerateMenuShowCommandNames);
  // Unbekannte Gruppen entfallen, Reihenfolge bleibt; Ausgeblendete ohne Leere und Doppelte.
  Settings.GenerateMenuGroups := ' Templates; quatsch, generate ';
  Settings.GenerateMenuHidden := '/json, , /json,tryf';
  Settings.Normalize;
  Assert.AreEqual('templates,generate', Settings.GenerateMenuGroups);
  Assert.AreEqual('/json, tryf', Settings.GenerateMenuHidden);
  Settings.GenerateMenuGroups := 'nichts';
  Settings.Normalize;
  Assert.AreEqual('generate,surround,templates', Settings.GenerateMenuGroups, 'ohne bekannte Gruppe: Vorgabe');
  // Speichern und Laden.
  Settings.GenerateMenu := False;
  Settings.GenerateMenuKey := 0;
  Settings.GenerateMenuGroups := 'surround,generate';
  Settings.GenerateMenuRecentFirst := False;
  Settings.GenerateMenuShowCommandNames := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.GenerateMenu, 'abschaltbar');
  Assert.AreEqual(0, Loaded.GenerateMenuKey, '0 = keine Taste');
  Assert.AreEqual('surround,generate', Loaded.GenerateMenuGroups);
  Assert.AreEqual('/json, tryf', Loaded.GenerateMenuHidden);
  Assert.IsFalse(Loaded.GenerateMenuRecentFirst);
  Assert.IsFalse(Loaded.GenerateMenuShowCommandNames);
end;

procedure TAtlasPluginSettingsTests.WelcomeIssuesOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(Settings.WelcomePageIssues, 'standardmäßig aus: kein Netzzugriff');
  Assert.AreEqual('', Settings.IssuesTracker, 'aus der .atlas');
  Assert.AreEqual('', Settings.IssuesQuery);
  Assert.AreEqual('branch', Settings.IssuesStart);
  Assert.AreEqual('', Settings.IssuesBranchPattern, 'je Versionsverwaltung');
  Assert.AreEqual('', Settings.IssuesBranchBase);
  Assert.AreEqual('{kennung} ', Settings.IssuesCommitPattern);
  Assert.IsTrue(Settings.TrackerLogin);
  Assert.IsTrue(Settings.IssuesPreview, 'Vorschau (#1264) an');
  Assert.IsTrue(Settings.IssuesPreviewComments);
  Assert.IsTrue(Settings.IssuesAttach, 'Anhängen (#1276) an');
  Assert.AreEqual('', Settings.IssuesAttachLogFiles);
  Assert.AreEqual(1920, Settings.IssuesAttachMaxImageWidth);
  // Die Einstellungen kennen den Bereich nicht (A-09): dieselben Werte wie dort.
  Assert.AreEqual(TAtlasTrackerNaming.CommitPattern, Settings.IssuesCommitPattern);
  Assert.AreEqual(TAtlasWelcomeIssues.StartName(TAtlasIssueStart.Branch), TAtlasPluginSettings.IssuesStartBranch);
  Assert.AreEqual(TAtlasWelcomeIssues.StartName(TAtlasIssueStart.Remember),
    TAtlasPluginSettings.IssuesStartRemember);
  // Normalisieren.
  Settings.IssuesTracker := ' YouTrack ';
  Settings.IssuesQuery := '  for: me'#13#10'#Unresolved  ';
  Settings.IssuesStart := 'REMEMBER';
  Settings.IssuesBranchPattern := ' bugfix/{kennung} ';
  Settings.IssuesBranchBase := ' develop ';
  Settings.IssuesCommitPattern := '[{kennung}] ';
  Settings.Normalize;
  Assert.AreEqual('youtrack', Settings.IssuesTracker);
  Assert.AreEqual('for: me  #Unresolved', Settings.IssuesQuery, 'einzeilig');
  Assert.AreEqual('remember', Settings.IssuesStart);
  Assert.AreEqual('bugfix/{kennung}', Settings.IssuesBranchPattern);
  Assert.AreEqual('develop', Settings.IssuesBranchBase);
  Assert.AreEqual('[{kennung}] ', Settings.IssuesCommitPattern, 'Leerzeichen am Ende bleibt');
  Settings.IssuesTracker := 'jira';
  Settings.IssuesStart := 'egal';
  Settings.IssuesCommitPattern := '';
  Settings.Normalize;
  Assert.AreEqual('', Settings.IssuesTracker);
  Assert.AreEqual('branch', Settings.IssuesStart);
  Assert.AreEqual('', Settings.IssuesCommitPattern, 'leer = aus');
  // Speichern und Laden.
  Settings.WelcomePageIssues := True;
  Settings.IssuesTracker := 'github';
  Settings.IssuesQuery := 'label:bug';
  Settings.IssuesStart := 'remember';
  Settings.IssuesBranchPattern := 'issue/{nummer}';
  Settings.IssuesBranchBase := 'trunk';
  Settings.IssuesCommitPattern := '{kennung}: ';
  Settings.TrackerLogin := False;
  Settings.IssuesPreview := False;
  Settings.IssuesPreviewComments := False;
  Settings.IssuesAttach := False;
  Settings.IssuesAttachLogFiles := '$(ProjectDir)\logs\*.log;C:\Temp\app.log';
  Settings.IssuesAttachMaxImageWidth := 1280;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.WelcomePageIssues);
  Assert.AreEqual('github', Loaded.IssuesTracker);
  Assert.AreEqual('label:bug', Loaded.IssuesQuery);
  Assert.AreEqual('remember', Loaded.IssuesStart);
  Assert.AreEqual('issue/{nummer}', Loaded.IssuesBranchPattern);
  Assert.AreEqual('trunk', Loaded.IssuesBranchBase);
  Assert.AreEqual('{kennung}: ', Loaded.IssuesCommitPattern);
  Assert.IsFalse(Loaded.TrackerLogin);
  Assert.IsFalse(Loaded.IssuesPreview);
  Assert.IsFalse(Loaded.IssuesPreviewComments);
  Assert.IsFalse(Loaded.IssuesAttach);
  Assert.AreEqual('$(ProjectDir)\logs\*.log;C:\Temp\app.log', Loaded.IssuesAttachLogFiles);
  Assert.AreEqual(1280, Loaded.IssuesAttachMaxImageWidth);
  // Bildbreite außerhalb 320–7680 wird begrenzt.
  Settings.IssuesAttachMaxImageWidth := 50;
  Settings.Normalize;
  Assert.AreEqual(320, Settings.IssuesAttachMaxImageWidth);
  Settings.IssuesAttachMaxImageWidth := 100000;
  Settings.Normalize;
  Assert.AreEqual(7680, Settings.IssuesAttachMaxImageWidth);
end;

procedure TAtlasPluginSettingsTests.HideElementOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.BlockEndLabels, 'Blockende-Beschriftung standardmäßig an');
  Assert.AreEqual($40BE, Settings.HideElementKey, 'Strg+.');
  Settings.HideElementKey := -5;
  Settings.Normalize;
  Assert.AreEqual(0, Settings.HideElementKey, 'negativ = keine Taste');
  Assert.AreEqual(25, TAtlasPluginSettings.Defaults.BlockEndLabelsMinLines, 'Mindestlänge (#620)');
  Assert.IsTrue(Settings.DimUnusedUses, 'ungenutzte uses standardmäßig abgeblendet (#621)');
  // Fehlertext am Zeilenende, Zähler und Sprungtasten (#509).
  Assert.AreEqual('errors', Settings.InlineDiagnostics);
  Assert.IsTrue(Settings.ProblemsStatusCounter);
  Assert.AreEqual($C077, Settings.NextProblemKey);
  Assert.AreEqual($E077, Settings.PreviousProblemKey);
  Settings.InlineDiagnostics := 'ALL';
  Settings.Normalize;
  Assert.AreEqual('all', Settings.InlineDiagnostics, 'Schreibweise des Schemas');
  Settings.InlineDiagnostics := 'unsinn';
  Settings.Normalize;
  Assert.AreEqual('errors', Settings.InlineDiagnostics, 'Unbekanntes = Vorgabe');
  Settings.BlockEndLabelsMinLines := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinBlockEndLines, Settings.BlockEndLabelsMinLines, 'unten begrenzt');
  Settings.BlockEndLabelsMinLines := 5000;
  Settings.DebugInlineValuesPerLine := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinInlineValuesPerLine, Settings.DebugInlineValuesPerLine,
    'debug.inlineValuesPerLine unten begrenzt (#508)');
  Assert.AreEqual(TAtlasPluginSettings.MaxBlockEndLines, Settings.BlockEndLabelsMinLines, 'oben begrenzt');
  Settings.BlockEndLabels := False;
  Settings.BlockEndLabelsMinLines := 40;
  Settings.DimUnusedUses := False;
  Settings.RecursionMarkers := False;
  Settings.RecursionMarkersDepth := 7;
  Settings.ExitPoints := False;
  Settings.ExitPointsExceptions := False;
  Settings.ExitPointsLoops := False;
  Settings.ExitPointsBadge := False;
  Settings.Reassigned := False;
  Settings.ReassignedTargets := 'fields,locals';
  Settings.ReassignedStyle := 'wavy';
  Settings.ReassignedColor := '#00ff80';
  Settings.ExpressionType := False;
  Settings.ExpressionTypeConversions := False;
  Settings.ExpressionTypeConstValue := False;
  Settings.ExpressionTypeKey := $4054;
  Settings.InlineDiagnostics := 'off';
  Settings.ProblemsStatusCounter := False;
  Settings.NextProblemKey := 0;
  Settings.PreviousProblemKey := $6077;
  Settings.HideElementKey := 0;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.BlockEndLabels, 'abschaltbar');
  Assert.AreEqual(40, Loaded.BlockEndLabelsMinLines);
  Assert.IsFalse(Loaded.DimUnusedUses, 'uses-Abblenden abschaltbar');
  Assert.IsFalse(Loaded.RecursionMarkers, 'Rekursionssymbole abschaltbar (#623)');
  Assert.AreEqual(7, Loaded.RecursionMarkersDepth);
  Assert.IsFalse(Loaded.ExitPoints, 'Austrittspunkte abschaltbar (#698)');
  Assert.IsFalse(Loaded.ExitPointsExceptions);
  Assert.IsFalse(Loaded.ExitPointsLoops);
  Assert.IsFalse(Loaded.ExitPointsBadge);
  Assert.IsFalse(Loaded.Reassigned, 'Unterstreichung abschaltbar (#712)');
  Assert.AreEqual('locals,fields', Loaded.ReassignedTargets, 'feste Reihenfolge');
  Assert.AreEqual('wavy', Loaded.ReassignedStyle);
  Assert.AreEqual('#00FF80', Loaded.ReassignedColor);
  Assert.IsFalse(Loaded.ExpressionType, 'Typ des Ausdrucks abschaltbar (#689)');
  Assert.IsFalse(Loaded.ExpressionTypeConversions);
  Assert.IsFalse(Loaded.ExpressionTypeConstValue);
  Assert.AreEqual($4054, Loaded.ExpressionTypeKey);
  Assert.AreEqual('off', Loaded.InlineDiagnostics, 'Fehlertext abschaltbar');
  Assert.IsFalse(Loaded.ProblemsStatusCounter, 'Zähler abschaltbar');
  Assert.AreEqual(0, Loaded.NextProblemKey);
  Assert.AreEqual($6077, Loaded.PreviousProblemKey);
  Assert.AreEqual(0, Loaded.HideElementKey, '0 = keine Taste');
end;

procedure TAtlasPluginSettingsTests.WelcomeQuickActionOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.WelcomePageQuickActions, 'standardmäßig an');
  Assert.AreEqual('build,tests,run,pull,folder,console,tasks', Settings.WelcomePageQuickActionsItems);
  Assert.AreEqual('wt.exe', Settings.WelcomePageQuickActionsConsole);
  Assert.AreEqual($4042, Settings.WelcomePageQuickActionsBuildKey, 'Strg+B');
  Assert.AreEqual($4054, Settings.WelcomePageQuickActionsTestKey, 'Strg+T');
  // Die Einstellungen kennen die Willkommensseite nicht (A-09): dieselben Vorgaben und Namen wie dort.
  Assert.AreEqual(TAtlasWelcomeQuickActions.DefaultItems, Settings.WelcomePageQuickActionsItems);
  Assert.AreEqual(TAtlasWelcomeQuickActions.DefaultConsole, Settings.WelcomePageQuickActionsConsole);
  Assert.AreEqual(TAtlasWelcomeQuickActions.DefaultBuildKey, Settings.WelcomePageQuickActionsBuildKey);
  Assert.AreEqual(TAtlasWelcomeQuickActions.DefaultTestKey, Settings.WelcomePageQuickActionsTestKey);
  Settings.WelcomePageQuickActionsItems := 'folder,unbekannt;RUN tests console pull build';
  Settings.Normalize;
  Assert.AreEqual(TAtlasWelcomeQuickActions.NormalizedItems('folder,unbekannt;RUN tests console pull build'),
    Settings.WelcomePageQuickActionsItems);
  // Normalisieren: bekannte Namen in fester Reihenfolge, leeres Programm = wt.exe, Tasten als Word.
  Settings.WelcomePageQuickActionsItems := ' Console; BUILD pull, unbekannt, build ';
  Settings.WelcomePageQuickActionsConsole := '   ';
  Settings.WelcomePageQuickActionsBuildKey := -5;
  Settings.WelcomePageQuickActionsTestKey := $1FFFF;
  Settings.Normalize;
  Assert.AreEqual('build,pull,console', Settings.WelcomePageQuickActionsItems);
  Assert.AreEqual(TAtlasWelcomeQuickActions.DefaultConsole, Settings.WelcomePageQuickActionsConsole);
  Assert.AreEqual(0, Settings.WelcomePageQuickActionsBuildKey);
  Assert.AreEqual($FFFF, Settings.WelcomePageQuickActionsTestKey);
  // Leere Liste bleibt leer (kein Knopf).
  Settings.WelcomePageQuickActionsItems := '';
  Settings.Normalize;
  Assert.AreEqual('', Settings.WelcomePageQuickActionsItems);
  // Speichern und Laden.
  Settings.WelcomePageQuickActions := False;
  Settings.WelcomePageQuickActionsItems := 'tests,folder';
  Settings.WelcomePageQuickActionsConsole := 'pwsh.exe';
  Settings.WelcomePageQuickActionsBuildKey := $C042;
  Settings.WelcomePageQuickActionsTestKey := 0;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.WelcomePageQuickActions);
  Assert.AreEqual('tests,folder', Loaded.WelcomePageQuickActionsItems);
  Assert.AreEqual('pwsh.exe', Loaded.WelcomePageQuickActionsConsole);
  Assert.AreEqual($C042, Loaded.WelcomePageQuickActionsBuildKey);
  Assert.AreEqual(0, Loaded.WelcomePageQuickActionsTestKey);
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
  Assert.AreEqual(TAtlasNotificationCenter.MinEntries, TAtlasPluginSettings.MinNotificationEntries);
  Assert.AreEqual(TAtlasNotificationCenter.MaxMaxEntries, TAtlasPluginSettings.MaxNotificationEntries);
  Assert.AreEqual(TAtlasNotificationCenter.DefaultMaxEntries, Settings.NotificationsMaxEntries);
  Settings.NotificationsMaxEntries := 3;
  Settings.NotificationsSources := ' ShortcutTips = COLLECT ; server=show, build=laut, reload=off ';
  Settings.NotificationsKey := -1;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinNotificationEntries, Settings.NotificationsMaxEntries);
  Assert.AreEqual('ShortcutTips=collect, reload=off', Settings.NotificationsSources,
    'show entfällt, unbekanntes Verhalten auch');
  Assert.AreEqual(0, Settings.NotificationsKey);
  Settings.NotificationsMaxEntries := 5000;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxNotificationEntries, Settings.NotificationsMaxEntries);
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

procedure TAtlasPluginSettingsTests.ReleaseGuardOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ReleaseGuard, 'Release-Wächter standardmäßig an');
  Assert.AreEqual('off', Settings.BuildGate, 'build.gate standardmäßig off (#529)');
  Assert.AreEqual('Release', Settings.ReleaseConfigs);
  Assert.AreEqual('debugDefine,debugInfo=off,stackFrames=off,assertions=off,rangeChecks=off,overflowChecks=off,' +
    'memoryLeaks,versionInfo,outputFolder', Settings.ReleaseChecks, 'alle Prüfungen an, Sollwerte aus');
  // Leeres Speicher-Objekt: Vorgaben.
  Store := TMemoryStore.Create;
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.AreEqual(Settings.ReleaseChecks, Loaded.ReleaseChecks);
  // Normalisieren: unbekannter Modus = off, Liste ohne Doppelte, Prüfungen vollständig in fester Reihenfolge.
  Settings.BuildGate := 'BLOCK';
  Settings.ReleaseConfigs := 'Release; Ship,, ship';
  Settings.ReleaseChecks := '-assertions, rangeChecks=on, quatsch';
  Settings.Normalize;
  Assert.AreEqual('block', Settings.BuildGate);
  Assert.AreEqual('Release, Ship', Settings.ReleaseConfigs);
  Assert.AreEqual('debugDefine,debugInfo=off,stackFrames=off,-assertions=off,rangeChecks=on,overflowChecks=off,' +
    'memoryLeaks,versionInfo,outputFolder', Settings.ReleaseChecks);
  Settings.BuildGate := 'streng';
  Settings.Normalize;
  Assert.AreEqual('off', Settings.BuildGate);
  // Speichern und Laden.
  Settings.ReleaseGuard := False;
  Settings.BuildGate := 'warn';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.ReleaseGuard, 'abschaltbar');
  Assert.AreEqual('warn', Loaded.BuildGate);
  Assert.AreEqual('Release, Ship', Loaded.ReleaseConfigs);
  Assert.AreEqual(Settings.ReleaseChecks, Loaded.ReleaseChecks);
end;

procedure TAtlasPluginSettingsTests.TasksOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
  Mode: TAtlasTaskBeforeBuild;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.TasksEnabled, 'tasks.enabled standardmäßig an (#900)');
  Assert.IsTrue(Settings.TasksProblemsFromOutput);
  Assert.AreEqual('off', Settings.TasksBeforeBuild);
  Assert.IsTrue(Settings.TasksSaveBeforeRun);
  Assert.IsFalse(Settings.TasksRunChecksParallel);
  Assert.IsFalse(Settings.TasksOnlyFindings);
  // Normalisieren: Groß-/Kleinschreibung egal, Unbekanntes = off.
  Settings.TasksBeforeBuild := ' Block ';
  Settings.Normalize;
  Assert.AreEqual('block', Settings.TasksBeforeBuild);
  Settings.TasksBeforeBuild := 'immer';
  Settings.Normalize;
  Assert.AreEqual('off', Settings.TasksBeforeBuild);
  // Die Einstellungen kennen die Projektaufgaben nicht (A-09): dieselben Werte wie dort.
  for Mode := Low(TAtlasTaskBeforeBuild) to High(TAtlasTaskBeforeBuild) do
  begin
    Settings.TasksBeforeBuild := UpperCase(TAtlasTasks.BeforeBuildNames[Mode]);
    Settings.Normalize;
    Assert.AreEqual(TAtlasTasks.BeforeBuildNames[Mode], Settings.TasksBeforeBuild);
  end;
  // Speichern und Laden, jede Einstellung abweichend von der Vorgabe.
  Settings.TasksEnabled := False;
  Settings.TasksProblemsFromOutput := False;
  Settings.TasksBeforeBuild := 'warn';
  Settings.TasksSaveBeforeRun := False;
  Settings.TasksRunChecksParallel := True;
  Settings.TasksOnlyFindings := True;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.TasksEnabled, 'abschaltbar');
  Assert.IsFalse(Loaded.TasksProblemsFromOutput);
  Assert.AreEqual('warn', Loaded.TasksBeforeBuild);
  Assert.IsFalse(Loaded.TasksSaveBeforeRun);
  Assert.IsTrue(Loaded.TasksRunChecksParallel);
  Assert.IsTrue(Loaded.TasksOnlyFindings);
end;

procedure TAtlasPluginSettingsTests.BuildGateTimeoutOption;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual(300, Settings.BuildGateTimeoutMs, 'Vorgabe 300 ms');
  Settings.BuildGateTimeoutMs := 1;
  Settings.Normalize;
  Assert.AreEqual(50, Settings.BuildGateTimeoutMs, 'untere Grenze');
  Settings.BuildGateTimeoutMs := 100000;
  Settings.Normalize;
  Assert.AreEqual(10000, Settings.BuildGateTimeoutMs, 'obere Grenze');
  Settings.BuildGateTimeoutMs := 750;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.AreEqual(750, Loaded.BuildGateTimeoutMs);
end;

procedure TAtlasPluginSettingsTests.BuildSummaryOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.BuildSummary, 'Zusammenfassung standardmäßig an');
  Assert.AreEqual('', Settings.BuildWarningsAsErrors);
  Settings.BuildSummary := False;
  Settings.BuildWarningsAsErrors := 'w1035; H2164 x123 W1035';
  Settings.Normalize;
  Assert.AreEqual('W1035, H2164', Settings.BuildWarningsAsErrors, 'groß, ohne Doppelte und Ungültiges');
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.BuildSummary);
  Assert.AreEqual('W1035, H2164', Loaded.BuildWarningsAsErrors);
end;

procedure TAtlasPluginSettingsTests.BuildOnOpenOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(Settings.BuildOnOpen, 'standardmäßig aus');
  Assert.AreEqual('make', Settings.BuildOnOpenKind);
  Assert.AreEqual('all', Settings.BuildOnOpenScope);
  Assert.AreEqual(3000, Settings.BuildOnOpenDelayMs);
  Assert.AreEqual('', Settings.BuildOnOpenExclude);
  // Normalisieren: unbekannte Art = make, unbekannter Umfang = all, Wartezeit in den Grenzen, Liste ohne Endung
  // und Doppelte.
  Settings.BuildOnOpenKind := 'BUILD';
  Settings.BuildOnOpenScope := 'Active';
  Settings.BuildOnOpenDelayMs := 10;
  Settings.BuildOnOpenExclude := ' Atlas.IDE.Expert.dproj; atlas.ide.expert,, Demo ';
  Settings.Normalize;
  Assert.AreEqual('build', Settings.BuildOnOpenKind);
  Assert.AreEqual('active', Settings.BuildOnOpenScope);
  Assert.AreEqual(500, Settings.BuildOnOpenDelayMs);
  Assert.AreEqual('Atlas.IDE.Expert, Demo', Settings.BuildOnOpenExclude);
  Settings.BuildOnOpenKind := 'erzeugen';
  Settings.BuildOnOpenScope := 'keins';
  Settings.BuildOnOpenDelayMs := 999999;
  Settings.Normalize;
  Assert.AreEqual('make', Settings.BuildOnOpenKind);
  Assert.AreEqual('all', Settings.BuildOnOpenScope);
  Assert.AreEqual(60000, Settings.BuildOnOpenDelayMs);
  // Speichern und Laden.
  Settings.BuildOnOpen := True;
  Settings.BuildOnOpenKind := 'check';
  Settings.BuildOnOpenScope := 'active';
  Settings.BuildOnOpenDelayMs := 5000;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.BuildOnOpen);
  Assert.AreEqual('check', Loaded.BuildOnOpenKind);
  Assert.AreEqual('active', Loaded.BuildOnOpenScope);
  Assert.AreEqual(5000, Loaded.BuildOnOpenDelayMs);
  Assert.AreEqual('Atlas.IDE.Expert, Demo', Loaded.BuildOnOpenExclude);
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
    Settings.CompletionListMode := TAtlasListModes.ModeNames[Mode];
    Settings.Normalize;
    Assert.AreEqual(TAtlasListModes.ModeNames[Mode], Settings.CompletionListMode);
  end;
  for Scope := Low(TAtlasListScope) to High(TAtlasListScope) do
  begin
    Settings.CompletionListScope := TAtlasListModes.ScopeNames[Scope];
    Settings.Normalize;
    Assert.AreEqual(TAtlasListModes.ScopeNames[Scope], Settings.CompletionListScope);
  end;
end;

procedure TAtlasPluginSettingsTests.UnitSearchOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Units suchen (#777): alles an, Strg+F12 übernommen, Gruppen nach Projekt, Herkunft Projektgruppe.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.UnitSearchEnabled);
  Assert.IsTrue(Settings.UnitSearchReplaceIdeDialog, 'überschreibt Strg+F12 standardmäßig');
  Assert.IsTrue(Settings.UnitSearchReplaceUseUnitDialog, 'überschreibt Alt+F11 standardmäßig (#786)');
  Assert.IsTrue(Settings.UnitSearchReplaceFormsDialog, 'überschreibt Umschalt+F12 standardmäßig (#786)');
  Assert.IsTrue(Settings.UnitSearchRememberCollapsed);
  Assert.IsTrue(Settings.UnitSearchFilters);
  Assert.IsTrue(Settings.UnitSearchFilterSyntax);
  Assert.IsTrue(Settings.UnitSearchPreview);
  Assert.IsTrue(Settings.UnitSearchPreviewForm);
  Assert.IsTrue(Settings.UnitSearchPreviewUsedBy);
  Assert.IsTrue(Settings.UnitSearchPreviewAutoCollapse);
  Assert.IsTrue(Settings.UnitSearchMultiSelect);
  Assert.IsTrue(Settings.UnitSearchActions);
  Assert.IsTrue(Settings.UnitSearchActionsAddUses);
  Assert.AreEqual('relative', Settings.UnitSearchPathStyle);
  Assert.AreEqual('project', Settings.UnitSearchGroupBy);
  Assert.AreEqual('group', Settings.UnitSearchDefaultScope);
  Assert.AreEqual(0, Settings.UnitSearchKey);
  // Unbekannte Werte fallen auf die Vorgabe zurück, Groß-/Kleinschrift wird vereinheitlicht.
  Settings.UnitSearchPathStyle := 'irgendwie';
  Settings.UnitSearchGroupBy := 'FOLDER';
  Settings.UnitSearchDefaultScope := 'searchpath';
  Settings.Normalize;
  Assert.AreEqual('relative', Settings.UnitSearchPathStyle);
  Assert.AreEqual('folder', Settings.UnitSearchGroupBy);
  Assert.AreEqual('searchPath', Settings.UnitSearchDefaultScope);
  // Speichern und Laden.
  Settings.UnitSearchEnabled := False;
  Settings.UnitSearchReplaceIdeDialog := False;
  Settings.UnitSearchReplaceUseUnitDialog := False;
  Settings.UnitSearchReplaceFormsDialog := False;
  Settings.UnitSearchRememberCollapsed := False;
  Settings.UnitSearchFilters := False;
  Settings.UnitSearchFilterSyntax := False;
  Settings.UnitSearchPreview := False;
  Settings.UnitSearchPreviewForm := False;
  Settings.UnitSearchPreviewUsedBy := False;
  Settings.UnitSearchPreviewAutoCollapse := False;
  Settings.UnitSearchMultiSelect := False;
  Settings.UnitSearchActions := False;
  Settings.UnitSearchActionsAddUses := False;
  Settings.UnitSearchPathStyle := 'compact';
  Settings.UnitSearchDefaultScope := 'library';
  Settings.UnitSearchKey := $6055;
  // Suchleiste (#878): Liste in den Meldungen abschaltbar.
  Settings.SearchResultsInMessages := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.UnitSearchEnabled);
  Assert.IsFalse(Loaded.UnitSearchReplaceIdeDialog);
  Assert.IsFalse(Loaded.UnitSearchReplaceUseUnitDialog);
  Assert.IsFalse(Loaded.UnitSearchReplaceFormsDialog);
  Assert.IsFalse(Loaded.SearchResultsInMessages);
  Assert.IsFalse(Loaded.UnitSearchRememberCollapsed);
  Assert.IsFalse(Loaded.UnitSearchFilters);
  Assert.IsFalse(Loaded.UnitSearchFilterSyntax);
  Assert.IsFalse(Loaded.UnitSearchPreview);
  Assert.IsFalse(Loaded.UnitSearchPreviewForm);
  Assert.IsFalse(Loaded.UnitSearchPreviewUsedBy);
  Assert.IsFalse(Loaded.UnitSearchPreviewAutoCollapse);
  Assert.IsFalse(Loaded.UnitSearchMultiSelect);
  Assert.IsFalse(Loaded.UnitSearchActions);
  Assert.IsFalse(Loaded.UnitSearchActionsAddUses);
  Assert.AreEqual('compact', Loaded.UnitSearchPathStyle);
  Assert.AreEqual('folder', Loaded.UnitSearchGroupBy);
  Assert.AreEqual('library', Loaded.UnitSearchDefaultScope);
  Assert.AreEqual($6055, Loaded.UnitSearchKey);
end;

procedure TAtlasPluginSettingsTests.QuickOpenOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Schnell öffnen (#503): an, ohne RTL/VCL-Quellen, Strg+P.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.QuickOpen);
  Assert.IsFalse(Settings.QuickOpenLibrary);
  Assert.AreEqual($4050, Settings.QuickOpenKey);
  Settings.QuickOpenKey := $1FFFF;
  Settings.Normalize;
  Assert.AreEqual($FFFF, Settings.QuickOpenKey);
  Settings.QuickOpen := False;
  Settings.QuickOpenLibrary := True;
  Settings.QuickOpenKey := $6050;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.QuickOpen);
  Assert.IsTrue(Loaded.QuickOpenLibrary);
  Assert.AreEqual($6050, Loaded.QuickOpenKey);
end;

procedure TAtlasPluginSettingsTests.NavHistoryOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Navigationsverlauf (#504): an, Alt+Links, Alt+Rechts, Strg+Alt+Q.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.NavHistory);
  Assert.AreEqual($8025, Settings.NavBackKey);
  Assert.AreEqual($8027, Settings.NavForwardKey);
  Assert.AreEqual($C051, Settings.LastEditKey);
  Settings.NavHistory := False;
  Settings.NavBackKey := 0;
  Settings.NavForwardKey := $C027;
  Settings.LastEditKey := -5;
  Settings.Normalize;
  Assert.AreEqual(0, Settings.LastEditKey);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.NavHistory);
  Assert.AreEqual(0, Loaded.NavBackKey);
  Assert.AreEqual($C027, Loaded.NavForwardKey);
  Assert.AreEqual(0, Loaded.LastEditKey);
end;

procedure TAtlasPluginSettingsTests.PeekOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Definition einblenden (#505): an, 15 Zeilen, mit Implementierung, Alt+F12 und Umschalt+Alt+F12.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.Peek);
  Assert.AreEqual(15, Settings.PeekHeightLines);
  Assert.IsTrue(Settings.PeekShowImplementation);
  Assert.AreEqual($807B, Settings.PeekDefinitionKey);
  Assert.AreEqual($A07B, Settings.PeekReferencesKey);
  Settings.PeekHeightLines := 2;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinPeekLines, Settings.PeekHeightLines);
  Settings.PeekHeightLines := 1000;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxPeekLines, Settings.PeekHeightLines);
  Settings.Peek := False;
  Settings.PeekHeightLines := 20;
  Settings.PeekShowImplementation := False;
  Settings.PeekDefinitionKey := 0;
  Settings.PeekReferencesKey := $C07B;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Peek);
  Assert.AreEqual(20, Loaded.PeekHeightLines);
  Assert.IsFalse(Loaded.PeekShowImplementation);
  Assert.AreEqual(0, Loaded.PeekDefinitionKey);
  Assert.AreEqual($C07B, Loaded.PeekReferencesKey);
end;

procedure TAtlasPluginSettingsTests.DataFlowOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Datenfluss (#690): an, Tiefe 6, Tests sichtbar.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DataFlow, 'navigation.dataFlow (#690)');
  Assert.AreEqual(6, Settings.DataFlowMaxDepth);
  Assert.IsFalse(Settings.DataFlowExcludeTests);
  Settings.DataFlowMaxDepth := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinDataFlowDepth, Settings.DataFlowMaxDepth);
  Settings.DataFlowMaxDepth := 99;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxDataFlowDepth, Settings.DataFlowMaxDepth);
  Settings.DataFlow := False;
  Settings.DataFlowMaxDepth := 3;
  Settings.DataFlowExcludeTests := True;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.DataFlow);
  Assert.AreEqual(3, Loaded.DataFlowMaxDepth);
  Assert.IsTrue(Loaded.DataFlowExcludeTests);
end;

procedure TAtlasPluginSettingsTests.OutlineOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.Outline);
  Assert.IsFalse(Settings.OutlineAlphabetical);
  Assert.IsTrue(Settings.OutlineFollowCursor);
  Assert.IsTrue(Settings.OutlineConditions);
  Settings.Outline := False;
  Settings.OutlineAlphabetical := True;
  Settings.OutlineFollowCursor := False;
  Settings.OutlineConditions := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Outline);
  Assert.IsTrue(Loaded.OutlineAlphabetical);
  Assert.IsFalse(Loaded.OutlineFollowCursor);
  Assert.IsFalse(Loaded.OutlineConditions);
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

procedure TAtlasPluginSettingsTests.BreadcrumbsOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.Breadcrumbs);
  Assert.IsFalse(Settings.BreadcrumbsShowUnit);
  Assert.IsTrue(Settings.BreadcrumbsIdeColors, 'Farben der IDE');
  Assert.IsTrue(Settings.BreadcrumbsHideIdeToolbar, 'Navigationsleiste der IDE aus');
  Assert.AreEqual($60BE, Settings.BreadcrumbsKey, 'Strg+Umschalt+.');
  Settings.Breadcrumbs := False;
  Settings.BreadcrumbsShowUnit := True;
  Settings.BreadcrumbsIdeColors := False;
  Settings.BreadcrumbsHideIdeToolbar := False;
  Settings.BreadcrumbsKey := 0;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Breadcrumbs);
  Assert.IsTrue(Loaded.BreadcrumbsShowUnit);
  Assert.IsFalse(Loaded.BreadcrumbsIdeColors);
  Assert.IsFalse(Loaded.BreadcrumbsHideIdeToolbar);
  Assert.AreEqual(0, Loaded.BreadcrumbsKey);
  Loaded.BreadcrumbsKey := -5;
  Loaded.Normalize;
  Assert.AreEqual(0, Loaded.BreadcrumbsKey);
end;

procedure TAtlasPluginSettingsTests.JumpToMatchOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.JumpToMatch);
  Assert.AreEqual($40BA, Settings.JumpToMatchKey, 'Strg+Ü');
  Assert.AreEqual($60BA, Settings.JumpToMatchSelectKey, 'Strg+Umschalt+Ü');
  Settings.JumpToMatch := False;
  Settings.JumpToMatchKey := $4042;
  Settings.JumpToMatchSelectKey := 0;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.JumpToMatch);
  Assert.AreEqual($4042, Loaded.JumpToMatchKey);
  Assert.AreEqual(0, Loaded.JumpToMatchSelectKey);
  Loaded.JumpToMatchKey := $1FFFF;
  Loaded.Normalize;
  Assert.AreEqual($FFFF, Loaded.JumpToMatchKey);
end;

procedure TAtlasPluginSettingsTests.MoveLinesOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.MoveLines);
  Assert.AreEqual($8026, Settings.MoveLinesUpKey, 'Alt+↑');
  Assert.AreEqual($8028, Settings.MoveLinesDownKey, 'Alt+↓');
  Assert.AreEqual($A026, Settings.DuplicateLinesUpKey, 'Umschalt+Alt+↑');
  Assert.AreEqual($A028, Settings.DuplicateLinesDownKey, 'Umschalt+Alt+↓');
  Settings.MoveLines := False;
  Settings.MoveLinesUpKey := 0;
  Settings.DuplicateLinesDownKey := $C044;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.MoveLines);
  Assert.AreEqual(0, Loaded.MoveLinesUpKey);
  Assert.AreEqual($8028, Loaded.MoveLinesDownKey);
  Assert.AreEqual($C044, Loaded.DuplicateLinesDownKey);
  Loaded.DuplicateLinesUpKey := $20000;
  Loaded.Normalize;
  Assert.AreEqual($FFFF, Loaded.DuplicateLinesUpKey);
end;

procedure TAtlasPluginSettingsTests.ContinueCommentsOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ContinueComments);
  Assert.IsTrue(Settings.ContinueCommentsLineComments);
  Assert.IsTrue(Settings.ContinueCommentsLists);
  Assert.AreEqual('', Settings.ContinueCommentsBlockPrefix);
  Settings.ContinueComments := False;
  Settings.ContinueCommentsLists := False;
  Settings.ContinueCommentsBlockPrefix := ' * ';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.ContinueComments);
  Assert.IsTrue(Loaded.ContinueCommentsLineComments);
  Assert.IsFalse(Loaded.ContinueCommentsLists);
  // Leerraum am Rand bleibt.
  Assert.AreEqual(' * ', Loaded.ContinueCommentsBlockPrefix);
  Loaded.ContinueCommentsBlockPrefix := ' *'#9'1234567890';
  Loaded.Normalize;
  Assert.AreEqual(' * 12345', Loaded.ContinueCommentsBlockPrefix);
  Loaded.ContinueCommentsBlockPrefix := '   ';
  Loaded.Normalize;
  Assert.AreEqual('', Loaded.ContinueCommentsBlockPrefix);
end;

procedure TAtlasPluginSettingsTests.CompleteStatementOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.CompleteStatement);
  Assert.AreEqual($600D, Settings.CompleteStatementKey, 'Strg+Umschalt+Enter');
  Assert.AreEqual('multiLine', Settings.CompleteStatementBeginEnd);
  Assert.AreEqual('finally', Settings.CompleteStatementTryKind);
  Assert.IsTrue(Settings.CompleteStatementMethodBody);
  Settings.CompleteStatement := False;
  Settings.CompleteStatementKey := 0;
  Settings.CompleteStatementBeginEnd := 'always';
  Settings.CompleteStatementTryKind := 'ask';
  Settings.CompleteStatementMethodBody := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.CompleteStatement);
  Assert.AreEqual(0, Loaded.CompleteStatementKey);
  Assert.AreEqual('always', Loaded.CompleteStatementBeginEnd);
  Assert.AreEqual('ask', Loaded.CompleteStatementTryKind);
  Assert.IsFalse(Loaded.CompleteStatementMethodBody);
  // Unbekannte Werte fallen auf die Vorgabe zurück, Groß-/Kleinschreibung wird angeglichen.
  Loaded.CompleteStatementBeginEnd := 'MULTILINE';
  Loaded.CompleteStatementTryKind := 'irgendwas';
  Loaded.Normalize;
  Assert.AreEqual('multiLine', Loaded.CompleteStatementBeginEnd);
  Assert.AreEqual('finally', Loaded.CompleteStatementTryKind);
end;

procedure TAtlasPluginSettingsTests.FormatCodeOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.FormatCode);
  Assert.AreEqual($E04C, Settings.FormatCodeKey, 'Strg+Umschalt+Alt+L');
  Settings.FormatCode := False;
  Settings.FormatCodeKey := $C046;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.FormatCode);
  Assert.AreEqual($C046, Loaded.FormatCodeKey);
  Loaded.FormatCodeKey := -5;
  Loaded.Normalize;
  Assert.AreEqual(0, Loaded.FormatCodeKey);
end;

procedure TAtlasPluginSettingsTests.StickyScrollOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #506: experimentell, also aus; drei Zeilen; Grenzen 1 bis 10.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(Settings.StickyScroll);
  Assert.AreEqual(3, Settings.StickyScrollMaxLines);
  Settings.StickyScroll := True;
  Settings.StickyScrollMaxLines := 5;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.StickyScroll);
  Assert.AreEqual(5, Loaded.StickyScrollMaxLines);
  Loaded.StickyScrollMaxLines := 0;
  Loaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinStickyLines, Loaded.StickyScrollMaxLines);
  Loaded.StickyScrollMaxLines := 99;
  Loaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxStickyLines, Loaded.StickyScrollMaxLines);
end;

procedure TAtlasPluginSettingsTests.MinimapOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #873: experimentell, also aus; Vorgaben laut Issue; Speichern, Laden, Klemmen.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(Settings.Minimap);
  Assert.AreEqual('blocks', Settings.MinimapRender);
  Assert.AreEqual(120, Settings.MinimapWidth);
  Assert.AreEqual(1, Settings.MinimapScale);
  Assert.AreEqual(120, Settings.MinimapMaxColumn);
  Assert.AreEqual('right', Settings.MinimapSide);
  Assert.AreEqual('always', Settings.MinimapShowSlider);
  Assert.IsTrue(Settings.MinimapSectionHeaders and Settings.MinimapHighlightMethod and Settings.MinimapMarkers and
    Settings.MinimapClickJumps);
  Assert.IsFalse(Settings.MinimapNoticeShown);
  Settings.Minimap := True;
  Settings.MinimapRender := 'characters';
  Settings.MinimapWidth := 90;
  Settings.MinimapScale := 2;
  Settings.MinimapMaxColumn := 80;
  Settings.MinimapSide := 'left';
  Settings.MinimapShowSlider := 'mouseover';
  Settings.MinimapSectionHeaders := False;
  Settings.MinimapHighlightMethod := False;
  Settings.MinimapMarkers := False;
  Settings.MinimapClickJumps := False;
  Settings.MinimapNoticeShown := True;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.Minimap);
  Assert.AreEqual('characters', Loaded.MinimapRender);
  Assert.AreEqual(90, Loaded.MinimapWidth);
  Assert.AreEqual(2, Loaded.MinimapScale);
  Assert.AreEqual(80, Loaded.MinimapMaxColumn);
  Assert.AreEqual('left', Loaded.MinimapSide);
  Assert.AreEqual('mouseover', Loaded.MinimapShowSlider);
  Assert.IsFalse(Loaded.MinimapSectionHeaders or Loaded.MinimapHighlightMethod or Loaded.MinimapMarkers or
    Loaded.MinimapClickJumps);
  Assert.IsTrue(Loaded.MinimapNoticeShown);
  Loaded.MinimapRender := 'pixel';
  Loaded.MinimapSide := 'oben';
  Loaded.MinimapShowSlider := '';
  Loaded.MinimapWidth := 1;
  Loaded.MinimapScale := 9;
  Loaded.MinimapMaxColumn := 100000;
  Loaded.Normalize;
  Assert.AreEqual('blocks', Loaded.MinimapRender);
  Assert.AreEqual('right', Loaded.MinimapSide);
  Assert.AreEqual('always', Loaded.MinimapShowSlider);
  Assert.AreEqual(TAtlasPluginSettings.MinMinimapWidth, Loaded.MinimapWidth);
  Assert.AreEqual(TAtlasPluginSettings.MaxMinimapScale, Loaded.MinimapScale);
  Assert.AreEqual(TAtlasPluginSettings.MaxMinimapColumn, Loaded.MinimapMaxColumn);
end;

procedure TAtlasPluginSettingsTests.MultiCursorOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #589: experimentell, also aus; Klick mit Alt; Kürzel Strg+D, Alt+Umschalt+I, Strg+Alt+↑/↓.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(Settings.MultiCursor);
  // #658 ebenso experimentell.
  Assert.IsFalse(Settings.LinkedEditing);
  Assert.AreEqual('alt', Settings.MultiCursorModifier);
  Assert.AreEqual($4044, Settings.MultiCursorNextKey, 'Strg+D');
  Assert.AreEqual($4044, Settings.MultiCursorSkipKey, 'Strg+K, Strg+D');
  Assert.AreEqual($A049, Settings.MultiCursorLineEndsKey, 'Alt+Umschalt+I');
  Assert.AreEqual($C026, Settings.MultiCursorAboveKey, 'Strg+Alt+Hoch');
  Assert.AreEqual($C028, Settings.MultiCursorBelowKey, 'Strg+Alt+Runter');
  Settings.MultiCursor := True;
  Settings.LinkedEditing := True;
  Settings.MultiCursorModifier := 'ctrl';
  Settings.MultiCursorNextKey := 0;
  Settings.MultiCursorSkipKey := $4053;
  Settings.MultiCursorLineEndsKey := $C049;
  Settings.MultiCursorAboveKey := $A026;
  Settings.MultiCursorBelowKey := $A028;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.MultiCursor);
  Assert.IsTrue(Loaded.LinkedEditing);
  Assert.AreEqual('ctrl', Loaded.MultiCursorModifier);
  Assert.AreEqual(0, Loaded.MultiCursorNextKey);
  Assert.AreEqual($4053, Loaded.MultiCursorSkipKey);
  Assert.AreEqual($C049, Loaded.MultiCursorLineEndsKey);
  Assert.AreEqual($A026, Loaded.MultiCursorAboveKey);
  Assert.AreEqual($A028, Loaded.MultiCursorBelowKey);
  // Unbekannte Taste fällt auf alt zurück; Kürzel bleiben ein Word.
  Loaded.MultiCursorModifier := 'shift';
  Loaded.MultiCursorBelowKey := $1FFFF;
  Loaded.Normalize;
  Assert.AreEqual('alt', Loaded.MultiCursorModifier);
  Assert.AreEqual($FFFF, Loaded.MultiCursorBelowKey);
  Loaded.MultiCursorModifier := 'CTRL';
  Loaded.Normalize;
  Assert.AreEqual('ctrl', Loaded.MultiCursorModifier);
end;

procedure TAtlasPluginSettingsTests.SmartPasteOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #515: experimentell, also aus; vier Werte, Unbekanntes fällt auf off zurück.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('off', Settings.SmartPaste);
  Settings.SmartPaste := 'indent';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.AreEqual('indent', Loaded.SmartPaste);
  Loaded.SmartPaste := 'BOTH';
  Loaded.Normalize;
  Assert.AreEqual('both', Loaded.SmartPaste);
  Loaded.SmartPaste := 'immer';
  Loaded.Normalize;
  Assert.AreEqual('off', Loaded.SmartPaste);
end;

procedure TAtlasPluginSettingsTests.ContinuePatternOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ContinuePattern);
  Assert.AreEqual(2, Settings.ContinuePatternMinLines);
  Settings.ContinuePattern := False;
  Settings.ContinuePatternMinLines := 4;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.ContinuePattern);
  Assert.AreEqual(4, Loaded.ContinuePatternMinLines);
  // Nur 2 bis 5 Zeilen.
  Loaded.ContinuePatternMinLines := 1;
  Loaded.Normalize;
  Assert.AreEqual(2, Loaded.ContinuePatternMinLines);
  Loaded.ContinuePatternMinLines := 9;
  Loaded.Normalize;
  Assert.AreEqual(5, Loaded.ContinuePatternMinLines);
end;

procedure TAtlasPluginSettingsTests.GutterColumnOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Atlas-Spalte in der Zeilenleiste (#768): Hauptschalter und Unterschalter standardmäßig an, je einzeln aus.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.GutterColumn);
  Assert.IsTrue(Settings.GutterColumnProblems);
  Assert.IsTrue(Settings.GutterColumnCodeActions);
  Assert.IsTrue(Settings.GutterColumnOverrides);
  Settings.GutterColumn := False;
  Settings.GutterColumnCodeActions := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.GutterColumn);
  Assert.IsTrue(Loaded.GutterColumnProblems);
  Assert.IsFalse(Loaded.GutterColumnCodeActions);
  Assert.IsTrue(Loaded.GutterColumnOverrides);
  Loaded.GutterColumnOverrides := False;
  Loaded.Save(Store);
  Settings := TAtlasPluginSettings.Defaults;
  Settings.Load(Store);
  Assert.IsFalse(Settings.GutterColumnOverrides);
end;

procedure TAtlasPluginSettingsTests.SelectionMatchesOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.SelectionMatches);
  Assert.AreEqual(3, Settings.SelectionMatchesMinLength);
  Assert.IsFalse(Settings.SelectionMatchesCaseSensitive);
  Assert.IsFalse(Settings.SelectionMatchesWholeWord);
  Assert.IsTrue(Settings.SelectionMatchesNavigateF3);
  Assert.AreEqual(1000, Settings.SelectionMatchesMaxMatches);
  Settings.SelectionMatches := False;
  Settings.SelectionMatchesMinLength := 5;
  Settings.SelectionMatchesCaseSensitive := True;
  Settings.SelectionMatchesWholeWord := True;
  Settings.SelectionMatchesNavigateF3 := False;
  Settings.SelectionMatchesMaxMatches := 250;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.SelectionMatches);
  Assert.AreEqual(5, Loaded.SelectionMatchesMinLength);
  Assert.IsTrue(Loaded.SelectionMatchesCaseSensitive);
  Assert.IsTrue(Loaded.SelectionMatchesWholeWord);
  Assert.IsFalse(Loaded.SelectionMatchesNavigateF3);
  Assert.AreEqual(250, Loaded.SelectionMatchesMaxMatches);
  // Grenzen: Mindestlänge 1 bis 100, Treffer 1 bis 100000.
  Loaded.SelectionMatchesMinLength := 0;
  Loaded.SelectionMatchesMaxMatches := 0;
  Loaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinSelectionMatchLength, Loaded.SelectionMatchesMinLength);
  Assert.AreEqual(TAtlasPluginSettings.MinSelectionMatches, Loaded.SelectionMatchesMaxMatches);
  Loaded.SelectionMatchesMinLength := 500;
  Loaded.SelectionMatchesMaxMatches := 5000000;
  Loaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxSelectionMatchLength, Loaded.SelectionMatchesMinLength);
  Assert.AreEqual(TAtlasPluginSettings.MaxSelectionMatches, Loaded.SelectionMatchesMaxMatches);
end;

procedure TAtlasPluginSettingsTests.ToggleBlockCommentOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ToggleBlockComment);
  Assert.AreEqual($A041, Settings.ToggleBlockCommentKey, 'Umschalt+Alt+A');
  Assert.AreEqual('braces', Settings.ToggleBlockCommentStyle);
  Assert.AreEqual('lineComments', Settings.ToggleBlockCommentFallback);
  Assert.IsFalse(Settings.ToggleBlockCommentOwnLines);
  Assert.AreEqual('statement', Settings.ToggleBlockCommentWithoutSelection);
  Settings.ToggleBlockComment := False;
  Settings.ToggleBlockCommentKey := 0;
  Settings.ToggleBlockCommentStyle := 'parens';
  Settings.ToggleBlockCommentFallback := 'refuse';
  Settings.ToggleBlockCommentOwnLines := True;
  Settings.ToggleBlockCommentWithoutSelection := 'line';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.ToggleBlockComment);
  Assert.AreEqual(0, Loaded.ToggleBlockCommentKey);
  Assert.AreEqual('parens', Loaded.ToggleBlockCommentStyle);
  Assert.AreEqual('refuse', Loaded.ToggleBlockCommentFallback);
  Assert.IsTrue(Loaded.ToggleBlockCommentOwnLines);
  Assert.AreEqual('line', Loaded.ToggleBlockCommentWithoutSelection);
  // Unbekannte Werte fallen auf die Vorgabe zurück.
  Loaded.ToggleBlockCommentStyle := 'eckig';
  Loaded.ToggleBlockCommentFallback := '';
  Loaded.ToggleBlockCommentWithoutSelection := 'block';
  Loaded.Normalize;
  Assert.AreEqual('braces', Loaded.ToggleBlockCommentStyle);
  Assert.AreEqual('lineComments', Loaded.ToggleBlockCommentFallback);
  Assert.AreEqual('statement', Loaded.ToggleBlockCommentWithoutSelection);
end;

procedure TAtlasPluginSettingsTests.WrapSelectionOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.WrapSelection);
  Assert.AreEqual('([{''', Settings.WrapSelectionChars);
  Settings.WrapSelection := False;
  Settings.WrapSelectionChars := '(<';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.WrapSelection);
  Assert.AreEqual('(<', Loaded.WrapSelectionChars);
end;

procedure TAtlasPluginSettingsTests.NewLineAroundOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.NewLineAround);
  Assert.AreEqual($200D, Settings.NewLineBelowKey, 'Umschalt+Enter');
  Assert.AreEqual($C00D, Settings.NewLineAboveKey, 'Strg+Alt+Enter');
  Assert.IsTrue(Settings.NewLineAroundStatementAware);
  Settings.NewLineAround := False;
  Settings.NewLineBelowKey := 0;
  Settings.NewLineAboveKey := $600D;
  Settings.NewLineAroundStatementAware := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.NewLineAround);
  Assert.AreEqual(0, Loaded.NewLineBelowKey);
  Assert.AreEqual($600D, Loaded.NewLineAboveKey);
  Assert.IsFalse(Loaded.NewLineAroundStatementAware);
  Loaded.NewLineBelowKey := -5;
  Loaded.Normalize;
  Assert.AreEqual(0, Loaded.NewLineBelowKey);
end;

procedure TAtlasPluginSettingsTests.ExpressionTypeOptions;
var
  Settings: TAtlasPluginSettings;
begin
  // Typ des markierten Ausdrucks (#689): an, mit Umwandlungen und Wert, Strg+Umschalt+T.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ExpressionType);
  Assert.IsTrue(Settings.ExpressionTypeConversions);
  Assert.IsTrue(Settings.ExpressionTypeConstValue);
  Assert.AreEqual($6054, Settings.ExpressionTypeKey, 'Strg+Umschalt+T');
  Settings.ExpressionTypeKey := $1FFFF;
  Settings.Normalize;
  Assert.AreEqual($FFFF, Settings.ExpressionTypeKey);
  Settings.ExpressionTypeKey := -3;
  Settings.Normalize;
  Assert.AreEqual(0, Settings.ExpressionTypeKey);
end;

procedure TAtlasPluginSettingsTests.MethodPlacementOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('declaration', Settings.MethodPlacement);
  Settings.MethodPlacement := 'Alphabetical';
  Settings.Normalize;
  Assert.AreEqual('alphabetical', Settings.MethodPlacement);
  Settings.MethodPlacement := 'irgendwie';
  Settings.Normalize;
  Assert.AreEqual('declaration', Settings.MethodPlacement, 'Unbekanntes wird zur Vorgabe');
  Settings.MethodPlacement := 'off';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.AreEqual('off', Loaded.MethodPlacement, 'abschaltbar');
end;

procedure TAtlasPluginSettingsTests.UnwrapOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.Unwrap);
  Assert.AreEqual($602E, Settings.UnwrapKey, 'Strg+Umschalt+Entf');
  Settings.Unwrap := False;
  Settings.UnwrapKey := $402E;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Unwrap);
  Assert.AreEqual($402E, Loaded.UnwrapKey);
  Loaded.UnwrapKey := $1FFFF;
  Loaded.Normalize;
  Assert.AreEqual($FFFF, Loaded.UnwrapKey);
end;

procedure TAtlasPluginSettingsTests.SafeDeleteOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.SafeDelete);
  Assert.AreEqual($802E, Settings.SafeDeleteKey, 'Alt+Entf');
  Settings.SafeDelete := False;
  Settings.SafeDeleteKey := $402E;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.SafeDelete);
  Assert.AreEqual($402E, Loaded.SafeDeleteKey);
  Loaded.SafeDeleteKey := -1;
  Loaded.Normalize;
  Assert.AreEqual(0, Loaded.SafeDeleteKey);
end;

procedure TAtlasPluginSettingsTests.GitChangeOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.GitGutter);
  Assert.IsFalse(Settings.GitBlame, 'blame nur auf Wunsch');
  Assert.AreEqual($C022, Settings.NextChangeKey, 'Strg+Alt+Bild↓');
  Assert.AreEqual($C021, Settings.PreviousChangeKey, 'Strg+Alt+Bild↑');
  Settings.GitGutter := False;
  Settings.GitBlame := True;
  Settings.NextChangeKey := 0;
  Settings.PreviousChangeKey := $4074;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.GitGutter);
  Assert.IsTrue(Loaded.GitBlame);
  Assert.AreEqual(0, Loaded.NextChangeKey);
  Assert.AreEqual($4074, Loaded.PreviousChangeKey);
  Loaded.NextChangeKey := -1;
  Loaded.PreviousChangeKey := $20000;
  Loaded.Normalize;
  Assert.AreEqual(0, Loaded.NextChangeKey);
  Assert.AreEqual($FFFF, Loaded.PreviousChangeKey);
end;

procedure TAtlasPluginSettingsTests.OverviewRulerOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.OverviewRuler);
  Assert.AreEqual('diagnostics,search,changes,breakpoints,bookmarks,cursor', Settings.OverviewRulerKinds);
  Settings.OverviewRuler := False;
  Settings.OverviewRulerKinds := 'changes,diagnostics';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.OverviewRuler);
  Loaded.Normalize;
  Assert.AreEqual('diagnostics,changes', Loaded.OverviewRulerKinds, 'feste Reihenfolge');
  Loaded.OverviewRulerKinds := 'gibtsnicht, cursor';
  Loaded.Normalize;
  Assert.AreEqual('cursor', Loaded.OverviewRulerKinds);
  Loaded.OverviewRulerKinds := '';
  Loaded.Normalize;
  Assert.AreEqual('', Loaded.OverviewRulerKinds, 'leer = keine Marken');
end;

procedure TAtlasPluginSettingsTests.DebugDisplayRuleOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #854: an, Aufrufe aus; beide überleben Speichern und Laden.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DebugDisplayRules);
  Assert.IsFalse(Settings.DebugDisplayRulesAllowCalls);
  Settings.DebugDisplayRules := False;
  Settings.DebugDisplayRulesAllowCalls := True;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Loaded.Normalize;
  Assert.IsFalse(Loaded.DebugDisplayRules);
  Assert.IsTrue(Loaded.DebugDisplayRulesAllowCalls);
end;

procedure TAtlasPluginSettingsTests.DebugStepIntoTargetOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #836: an mit Strg+Alt+F7; Schalter und Taste überleben Speichern und Laden, 0 = keine Taste.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DebugStepIntoTarget);
  Assert.AreEqual($C076, Settings.DebugStepIntoTargetKey);
  Settings.DebugStepIntoTarget := False;
  Settings.DebugStepIntoTargetKey := 0;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Loaded.Normalize;
  Assert.IsFalse(Loaded.DebugStepIntoTarget);
  Assert.AreEqual(0, Loaded.DebugStepIntoTargetKey);
  Loaded.DebugStepIntoTargetKey := -5;
  Loaded.Normalize;
  Assert.AreEqual(0, Loaded.DebugStepIntoTargetKey);
end;

procedure TAtlasPluginSettingsTests.DebugBreakOnNextEventOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #856: an, ausgenommen OnPaint, OnMouseMove und OnUpdate; die Liste wird beim Normalisieren bereinigt.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DebugBreakOnNextEvent);
  Assert.AreEqual('OnPaint, OnMouseMove, OnUpdate', Settings.DebugBreakOnNextEventExcluded);
  Settings.DebugBreakOnNextEvent := False;
  Settings.DebugBreakOnNextEventExcluded := 'OnPaint, OnResize';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Loaded.Normalize;
  Assert.IsFalse(Loaded.DebugBreakOnNextEvent);
  Assert.AreEqual('OnPaint, OnResize', Loaded.DebugBreakOnNextEventExcluded);
  Loaded.DebugBreakOnNextEventExcluded := ' OnPaint ;; OnResize,';
  Loaded.Normalize;
  Assert.AreEqual('OnPaint, OnResize', Loaded.DebugBreakOnNextEventExcluded);
end;

procedure TAtlasPluginSettingsTests.DebugStepFilterOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #850: an, Getter und triviale Routinen, keine Muster; alles überlebt Speichern und Laden, Normalize bereinigt.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DebugStepFilters);
  Assert.AreEqual('getters,trivial', Settings.DebugStepFilterKinds);
  Assert.AreEqual('', Settings.DebugStepFilterPatterns);
  Settings.DebugStepFilters := False;
  Settings.DebugStepFilterKinds := 'Operators, setters, quatsch';
  Settings.DebugStepFilterPatterns := ' *.Log* ;; TBasisForm.*;*.log*';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Loaded.Normalize;
  Assert.IsFalse(Loaded.DebugStepFilters);
  Assert.AreEqual('setters,operators', Loaded.DebugStepFilterKinds);
  Assert.AreEqual('*.Log*;TBasisForm.*', Loaded.DebugStepFilterPatterns);
end;

procedure TAtlasPluginSettingsTests.DebugVisualizerOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DebugVisualizers);
  Assert.AreEqual('lists,dictionaries,dataSets,bytes,json,colors,guid,geometry,graphics',
    Settings.DebugVisualizerTypes);
  Assert.AreEqual('Name,Caption,Text', Settings.DebugVisualizerNameFields);
  Assert.AreEqual(120, Settings.DebugVisualizerMaxLength);
  Assert.AreEqual(200, Settings.DebugVisualizerTimeoutMs);
  Assert.AreEqual(4000000, Settings.DebugVisualizerMaxImagePixels);
  Assert.AreEqual('properties', Settings.DebugVisualizerEvaluation);
  Settings.DebugVisualizers := False;
  Settings.DebugVisualizerTypes := 'json,lists';
  Settings.DebugVisualizerNameFields := 'Bezeichnung';
  Settings.DebugVisualizerMaxLength := 80;
  Settings.DebugVisualizerTimeoutMs := 500;
  Settings.DebugVisualizerMaxImagePixels := 100000;
  Settings.DebugVisualizerEvaluation := 'calls';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Loaded.Normalize;
  Assert.IsFalse(Loaded.DebugVisualizers);
  Assert.AreEqual('lists,json', Loaded.DebugVisualizerTypes, 'feste Reihenfolge');
  Assert.AreEqual('Bezeichnung', Loaded.DebugVisualizerNameFields);
  Assert.AreEqual(80, Loaded.DebugVisualizerMaxLength);
  Assert.AreEqual(500, Loaded.DebugVisualizerTimeoutMs);
  Assert.AreEqual(100000, Loaded.DebugVisualizerMaxImagePixels);
  Assert.AreEqual('calls', Loaded.DebugVisualizerEvaluation);
  // Grenzen und unbekannte Werte.
  Loaded.DebugVisualizerTypes := 'gibtsnicht, Colors';
  Loaded.DebugVisualizerNameFields := ' Name , ,Name, Text ';
  Loaded.DebugVisualizerMaxLength := 5;
  Loaded.DebugVisualizerTimeoutMs := 100000;
  Loaded.DebugVisualizerMaxImagePixels := 1;
  Loaded.DebugVisualizerEvaluation := 'alles';
  Loaded.Normalize;
  Assert.AreEqual('colors', Loaded.DebugVisualizerTypes);
  Assert.AreEqual('Name,Text', Loaded.DebugVisualizerNameFields);
  Assert.AreEqual(20, Loaded.DebugVisualizerMaxLength);
  Assert.AreEqual(5000, Loaded.DebugVisualizerTimeoutMs);
  Assert.AreEqual(10000, Loaded.DebugVisualizerMaxImagePixels);
  Assert.AreEqual('fields', Loaded.DebugVisualizerEvaluation, 'unbekannt = erster Wert');
  Loaded.DebugVisualizerTypes := '';
  Loaded.Normalize;
  Assert.AreEqual('', Loaded.DebugVisualizerTypes, 'leer = keine Art');
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
    Paths := Paths + Field.Path + '|';
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
    if Field.Path = 'diagnostics.usesCycleLive' then
    begin
      Assert.AreEqual('Prüfregeln', Field.Page);
      Assert.AreEqual('true', Field.DefaultJson);
    end;
  Paths := '|';
  for Field in Global do
    Paths := Paths + Field.Path + '|';
  Assert.Contains(Paths, '|language|');
  Assert.Contains(Paths, '|completion.matching|');
  // Versionsverwaltung (#571): im Dialog der globalen Einstellungen, Seite Allgemein, als Auswahl.
  Assert.Contains(Paths, '|vcs.provider|');
  for Field in Global do
    if Field.Path = 'vcs.provider' then
    begin
      Assert.AreEqual('Allgemein', Field.Page);
      Assert.AreEqual('"auto"', Field.DefaultJson);
      Assert.AreEqual(4, Integer(Length(Field.Choices)));
      Assert.AreEqual('"off"', Field.Choices[3]);
    end;
  // Auf den Reitern der Optionsseite bzw. von der IDE gesetzt: nicht noch einmal im Dialog.
  Assert.DoesNotContain(Paths, '|index.projectGroup|');
  Assert.DoesNotContain(Paths, '|hints.xmlDocFull|');
  Assert.DoesNotContain(Paths, '|delphiVersion|');
  // rules gilt an beiden Orten (x-scope "both"): Tabelle auch in den globalen Einstellungen.
  Assert.Contains(Paths, '|rules|');
  // Jedes umgeleitete Feld ist im Schema global.
  for Field in Fields do
    if Pos('|' + Field.Path + '|',
      '|index.projectGroup|memoryBudgetMb|compiler.onSave|slashCommands.enabled|references.inferred|') > 0 then
      Assert.IsTrue(Field.Global, Field.Path);
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
  Assert.AreEqual('file', Settings.ProblemsWindowGroupBy);
  Assert.AreEqual('', Settings.ProblemsWindowColumns);
  Assert.IsFalse(Settings.ProblemsWindowCompiler);
  Assert.IsTrue(Settings.ProblemsWindowFollowCursor);
  Assert.AreEqual($C050, Settings.ProblemsWindowKey, 'Strg+Alt+P');
  Assert.IsTrue(Settings.ProblemsLive);
  Assert.IsTrue(Settings.HoverProblemActions);
  Assert.IsFalse(Settings.ProblemsList, 'Meldungsfenster-Gruppe seit dem Prüffenster aus');
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
  Settings.ProblemsWindowGroupBy := 'unsinn';
  Settings.ProblemsWindowKey := -1;
  Settings.Normalize;
  Assert.AreEqual('project', Settings.ProblemsWindowScope);
  Assert.AreEqual('file', Settings.ProblemsWindowGroupBy, 'Unbekanntes = Vorgabe');
  Assert.AreEqual(0, Settings.ProblemsWindowKey);
  Settings.ProblemsWindow := False;
  Settings.ProblemsWindowScope := 'file';
  Settings.ProblemsWindowGroupBy := 'category';
  Settings.ProblemsWindowColumns := 'kind:70,-rule';
  Settings.ProblemsWindowCompiler := True;
  Settings.ProblemsWindowFollowCursor := False;
  Settings.ProblemsWindowKey := $C051;
  Settings.ProblemsLive := False;
  Settings.HoverProblemActions := False;
  Settings.ProblemsList := True;
  Settings.ProblemsCompilerMerge := 'both';
  Settings.ProblemsShowCompilerCode := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.ProblemsWindow);
  Assert.AreEqual('file', Loaded.ProblemsWindowScope);
  Assert.AreEqual('category', Loaded.ProblemsWindowGroupBy);
  Assert.AreEqual('kind:70,-rule', Loaded.ProblemsWindowColumns);
  Assert.IsTrue(Loaded.ProblemsWindowCompiler);
  Assert.IsFalse(Loaded.ProblemsWindowFollowCursor);
  Assert.AreEqual($C051, Loaded.ProblemsWindowKey);
  Assert.IsFalse(Loaded.ProblemsLive);
  Assert.IsFalse(Loaded.HoverProblemActions);
  Assert.AreEqual('both', Loaded.ProblemsCompilerMerge);
  Assert.IsFalse(Loaded.ProblemsShowCompilerCode);
  Assert.IsTrue(Loaded.ProblemsList);
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

procedure TAtlasPluginSettingsTests.CallHierarchyDiagramOption;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.CallHierarchyDiagram, 'Aufrufdiagramm standardmäßig an');
  Settings.CallHierarchyDiagram := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('CallHierarchyDiagram', 1));
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.CallHierarchyDiagram);
end;

procedure TAtlasPluginSettingsTests.EditorToolbarOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.EditorToolbar);
  Assert.AreEqual('belowBreadcrumbs', Settings.EditorToolbarPosition);
  Assert.AreEqual(TAtlasToolbarItems.DefaultText, Settings.EditorToolbarItems);
  Assert.IsTrue(Settings.EditorToolbarReturnButton);
  Assert.IsFalse(Settings.EditorToolbarLabels);
  Assert.AreEqual(0, Settings.GotoInterfaceKey, 'keine Taste');
  Assert.AreEqual(0, Settings.GotoImplementationKey, 'keine Taste');
  Settings.EditorToolbarPosition := 'INBREADCRUMBS';
  Settings.EditorToolbarItems := '|, Atlas.GotoInterface ,|,|,Atlas.NavBack,Atlas.navback,|';
  Settings.GotoInterfaceKey := $1FFFF;
  Settings.GotoImplementationKey := -3;
  Settings.Normalize;
  Assert.AreEqual('inBreadcrumbs', Settings.EditorToolbarPosition);
  Assert.AreEqual('Atlas.GotoInterface,|,Atlas.NavBack', Settings.EditorToolbarItems);
  Assert.AreEqual($FFFF, Settings.GotoInterfaceKey);
  Assert.AreEqual(0, Settings.GotoImplementationKey);
  Settings.EditorToolbarPosition := 'oben';
  Settings.Normalize;
  Assert.AreEqual('belowBreadcrumbs', Settings.EditorToolbarPosition, 'Unbekanntes = Vorgabe');
  Settings.EditorToolbar := False;
  Settings.EditorToolbarPosition := 'aboveBreadcrumbs';
  Settings.EditorToolbarItems := '';
  Settings.EditorToolbarReturnButton := False;
  Settings.EditorToolbarLabels := True;
  Settings.GotoInterfaceKey := $6049;
  Settings.GotoImplementationKey := $604D;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.EditorToolbar);
  Assert.AreEqual('aboveBreadcrumbs', Loaded.EditorToolbarPosition);
  Assert.AreEqual('', Loaded.EditorToolbarItems, 'alle Knöpfe entfernt bleibt leer');
  Assert.IsFalse(Loaded.EditorToolbarReturnButton);
  Assert.IsTrue(Loaded.EditorToolbarLabels);
  Assert.AreEqual($6049, Loaded.GotoInterfaceKey);
  Assert.AreEqual($604D, Loaded.GotoImplementationKey);
end;

procedure TAtlasPluginSettingsTests.EditorStatusBarOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.EditorStatusBar);
  Assert.AreEqual('status,findings,liveCheck,method', Settings.EditorStatusBarItems);
  Assert.AreEqual(TAtlasStatusBarItems.DefaultText, Settings.EditorStatusBarItems);
  Settings.EditorStatusBarItems := ' METHOD, zahnrad ,status,method';
  Settings.Normalize;
  Assert.AreEqual('method,status', Settings.EditorStatusBarItems, 'nur bekannte, jedes einmal');
  Settings.EditorStatusBar := False;
  Settings.EditorStatusBarItems := '';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.EditorStatusBar);
  Assert.AreEqual('', Loaded.EditorStatusBarItems, 'alle Elemente aus bleibt leer');
end;

procedure TAtlasPluginSettingsTests.QuickBookmarkOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.QuickBookmarks);
  Assert.IsTrue(Settings.QuickBookmarksGutter);
  Assert.IsTrue(Settings.QuickBookmarksGutterClick);
  Assert.IsTrue(Settings.QuickBookmarksNumberedKeys);
  Assert.AreEqual($604B, Settings.QuickBookmarkKey, 'Strg+Umschalt+K');
  Assert.IsTrue(Settings.QuickBookmarkKeyPriority);
  Assert.AreEqual(800, Settings.QuickBookmarkChordWait);
  Assert.AreEqual($6031, Settings.QuickBookmarkSetKey, 'Strg+Umschalt+1');
  Assert.AreEqual($4031, Settings.QuickBookmarkJumpKey, 'Strg+1');
  Assert.AreEqual('project', Settings.QuickBookmarksScope);
  Assert.IsTrue(Settings.QuickBookmarksImportIde);
  Assert.AreEqual(0, Settings.NextBookmarkKey, 'ohne voreingestellte Taste');
  Assert.AreEqual(0, Settings.PreviousBookmarkKey);
  Settings.QuickBookmarkChordWait := 99999;
  Settings.QuickBookmarksScope := 'FILE';
  Settings.QuickBookmarkKey := -1;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxQuickChordWait, Settings.QuickBookmarkChordWait);
  Assert.AreEqual('file', Settings.QuickBookmarksScope);
  Assert.AreEqual(0, Settings.QuickBookmarkKey);
  Settings.QuickBookmarksScope := 'irgendwo';
  Settings.QuickBookmarkChordWait := -5;
  Settings.Normalize;
  Assert.AreEqual('project', Settings.QuickBookmarksScope);
  Assert.AreEqual(0, Settings.QuickBookmarkChordWait);
  Settings.QuickBookmarks := False;
  Settings.QuickBookmarksGutter := False;
  Settings.QuickBookmarksGutterClick := False;
  Settings.QuickBookmarksNumberedKeys := False;
  Settings.QuickBookmarkKey := $604C;
  Settings.QuickBookmarkKeyPriority := False;
  Settings.QuickBookmarkChordWait := 500;
  Settings.QuickBookmarkSetKey := $C031;
  Settings.QuickBookmarkSetKeyPriority := False;
  Settings.QuickBookmarkJumpKey := $8031;
  Settings.QuickBookmarkJumpKeyPriority := False;
  Settings.QuickBookmarksScope := 'file';
  Settings.QuickBookmarksImportIde := False;
  Settings.NextBookmarkKey := $4071;
  Settings.PreviousBookmarkKey := $6071;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.QuickBookmarks);
  Assert.IsFalse(Loaded.QuickBookmarksGutter);
  Assert.IsFalse(Loaded.QuickBookmarksGutterClick);
  Assert.IsFalse(Loaded.QuickBookmarksNumberedKeys);
  Assert.AreEqual($604C, Loaded.QuickBookmarkKey);
  Assert.IsFalse(Loaded.QuickBookmarkKeyPriority);
  Assert.AreEqual(500, Loaded.QuickBookmarkChordWait);
  Assert.AreEqual($C031, Loaded.QuickBookmarkSetKey);
  Assert.IsFalse(Loaded.QuickBookmarkSetKeyPriority);
  Assert.AreEqual($8031, Loaded.QuickBookmarkJumpKey);
  Assert.IsFalse(Loaded.QuickBookmarkJumpKeyPriority);
  Assert.AreEqual('file', Loaded.QuickBookmarksScope);
  Assert.IsFalse(Loaded.QuickBookmarksImportIde);
  Assert.AreEqual($4071, Loaded.NextBookmarkKey);
  Assert.AreEqual($6071, Loaded.PreviousBookmarkKey);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginSettingsTests);
  TDUnitX.RegisterTestFixture(TAtlasSettingsScopesTests);

end.
