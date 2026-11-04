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
    /// <summary>Aktualisierung der Prüfung (problems.update, problems.liveDelayMs), Übernahme von problems.live.
    /// </summary>
    [Test]
    procedure ProblemsUpdateOptions;
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
    /// <summary>#1442: Designer-Leiste Vorgabe an; Speichern und Laden.</summary>
    [Test]
    procedure EditorDesignerBarOptions;
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
    /// <summary>#1261: issues.projects wie die Verbindungen als JSON-Liste in settings.json.</summary>
    [Test]
    procedure IssuesProjectsGoToGlobalFile;
    /// <summary>#1262: issues.queries wie die Verbindungen als JSON-Liste in settings.json; issues.queryPicker
    /// bleibt in der Registry.</summary>
    [Test]
    procedure IssuesQueriesGoToGlobalFile;
    /// <summary>#1285: vcs.provider, vcs.git.path, vcs.svn.path und vcs.timeoutSeconds in settings.json (der
    /// Server liest dieselben Werte), nie in der Registry; ungültige Werte werden zur Vorgabe. #1288:
    /// vcs.branch.confirm nur im Plugin (Registry).</summary>
    [Test]
    procedure VcsSettingsGoToGlobalFile;
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
    /// <summary>Tracker nachführen (#1266): Vorgaben, Normalisieren und Speichern.</summary>
    [Test]
    procedure IssuesSyncOptions;
    /// <summary>Zeiterfassung (#1267): ab Werk aus, Leerlauf 10, Rundung 5, Grenzen, Speichern und Laden.</summary>
    [Test]
    procedure IssuesTimeOptions;
    /// <summary>Kommentar-Editor (#1278): Schalter und Textbausteine mit Vorgaben, Normalisieren und Speichern.</summary>
    [Test]
    procedure IssuesCommentOptions;
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
  Atlas.Core.Tracker.MyIssues,
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
  begin
    Result := ADefault;
  end;
end;

procedure TMemoryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

function TMemoryStore.ReadString(const AName, ADefault: string): string;
begin
  if not FStrings.TryGetValue(AName, Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TMemoryStore.WriteString(const AName, AValue: string);
begin
  FStrings.AddOrSetValue(AName, AValue);
end;

{ TAtlasPluginSettingsTests }

/// <summary>Vorgaben für Editor, Code Lens, Tests und Build.</summary>
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
  Assert.AreEqual(3, ASettings.TestsAffectedDepth, 'Tiefe der betroffenen Tests standardmäßig 3 (#1353)');
  Assert.IsFalse(ASettings.TestsAffectedBeforeCommit, 'Angebot vor dem Commit standardmäßig aus (#1353)');
  Assert.IsTrue(ASettings.TestsBuildFirst, 'vor den Tests bauen standardmäßig an (#69)');
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
  Assert.IsTrue(ASettings.DebugExceptionHistory, 'debug.exceptionHistory (#517)');
  Assert.IsTrue(ASettings.DebugJustMyCode, 'debug.justMyCode (#578)');
  Assert.IsFalse(ASettings.DebugExceptionBanner, 'debug.exceptionBanner (#783)');
  Assert.IsTrue(ASettings.DebugExceptionBannerIgnoreAtLocation, 'debug.exceptionBanner.ignoreAtLocation (#783)');
  Assert.IsTrue(ASettings.DebugInlineValues, 'debug.inlineValues (#508)');
  Assert.AreEqual(5, ASettings.DebugInlineValuesPerLine, 'debug.inlineValuesPerLine (#508)');
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
  Assert.IsTrue(ASettings.BugReportAnonymize, 'Fehlerbericht anonymisiert');
  Assert.IsTrue(ASettings.PairOwners, 'Anweisungen mitfärben standardmäßig an (#653)');
  Assert.AreEqual(1, ASettings.PairGuideWidth, 'Blocklinien 1 px');
  Assert.AreEqual(75, ASettings.PairGuideOpacity, 'Blocklinien 75 % Deckkraft');
  Assert.IsFalse(ASettings.ProblemsList, 'Liste „Atlas-Probleme“ seit dem Prüffenster (#909) standardmäßig aus');
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
  ASettings.DebugExceptionHistory := False;
  ASettings.DebugJustMyCode := False;
  ASettings.DebugExceptionBanner := True;
  ASettings.DebugExceptionBannerIgnoreAtLocation := False;
  ASettings.DebugInlineValues := False;
  ASettings.DebugInlineValuesPerLine := 7;
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
  ASettings.BugReportAnonymize := False;
  ASettings.ProblemsList := True;
  ASettings.PairOwners := False;
  ASettings.PairGuideWidth := 3;
  ASettings.PairGuideOpacity := 80;
  ASettings.PairColorsDark := '#112233, #445566,#778899,#aabbcc,#DDEEFF';
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
  Assert.IsFalse(ALoaded.DebugExceptionHistory, 'debug.exceptionHistory (#517)');
  Assert.IsFalse(ALoaded.DebugJustMyCode, 'debug.justMyCode (#578)');
  Assert.IsTrue(ALoaded.DebugExceptionBanner, 'debug.exceptionBanner (#783)');
  Assert.IsFalse(ALoaded.DebugExceptionBannerIgnoreAtLocation, 'debug.exceptionBanner.ignoreAtLocation (#783)');
  Assert.IsFalse(ALoaded.DebugInlineValues, 'debug.inlineValues (#508)');
  Assert.AreEqual(7, ALoaded.DebugInlineValuesPerLine, 'debug.inlineValuesPerLine (#508)');
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
  Assert.IsTrue(ALoaded.ProblemsList, 'Liste „Atlas-Probleme“ eingeschaltet');
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
  Assert.IsFalse(ALoaded.BugReportAnonymize);
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

procedure TAtlasPluginSettingsTests.IssuesProjectsGoToGlobalFile;
const
  cList = '[{"match": "C:\\Projekte\\Kasse\\Kasse.groupproj", "connection": "Firma", "project": "KASSE"}]';
var
  mRegistry, mStore: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('[]', mSettings.IssuesProjects);
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mSettings.Save(mStore);
  Assert.IsFalse(mRouted.Text.Contains('projects'), 'leere Liste ohne Eintrag: ' + mRouted.Text);
  mSettings.IssuesProjects := cList;
  mSettings.Save(mStore);
  Assert.Contains(mRouted.Text, '"projects": [{"match": ');
  Assert.AreEqual('', mRegistry.ReadString('IssuesProjects', ''), 'nicht in der Registry');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.IssuesProjects.Contains('"KASSE"'), mLoaded.IssuesProjects);
  mRouted := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, '{"issues": {"projects": 3}}');
  mStore := mRouted;
  mLoaded.Load(mStore);
  Assert.AreEqual('[]', mLoaded.IssuesProjects, 'falsche Art: Vorgabe');
  Assert.IsTrue(MatchText('issues.projects', TAtlasSettingsScopes.IdeManagedPaths), 'nicht im Dialog');
end;

procedure TAtlasPluginSettingsTests.IssuesQueriesGoToGlobalFile;
const
  cList = '[{"name": "Sprint", "query": "#{Aktueller Sprint}", "connection": "Firma"}]';
var
  mRegistry, mStore: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mSettings.Save(mStore);
  Assert.IsFalse(mRouted.Text.Contains('queries'), 'leere Liste ohne Eintrag: ' + mRouted.Text);
  mSettings.IssuesQueries := cList;
  mSettings.IssuesQueryPicker := False;
  mSettings.Save(mStore);
  Assert.Contains(mRouted.Text, '"queries": [{"name": ');
  Assert.AreEqual('', mRegistry.ReadString('IssuesQueries', ''), 'nicht in der Registry');
  Assert.AreEqual(0, mRegistry.ReadInteger('IssuesQueryPicker', 1), 'Klappliste in der Registry');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.IssuesQueries.Contains('"Sprint"'), mLoaded.IssuesQueries);
  Assert.IsFalse(mLoaded.IssuesQueryPicker);
  Assert.IsTrue(MatchText('issues.queries', TAtlasSettingsScopes.IdeManagedPaths), 'nicht im Dialog');
end;

/// <summary>#1285: Art, Werkzeugpfade und Zeitlimit in settings.json, ungültige Werte zur Vorgabe.</summary>
procedure VcsToolSettingsGoToGlobalFile;
const
  cGit = 'D:\Portable\Git\cmd\git.exe';
var
  mRegistry, mStore: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('auto', mSettings.VcsProvider);
  Assert.AreEqual('', mSettings.VcsGitPath, 'leer = automatisch suchen');
  Assert.AreEqual('', mSettings.VcsSvnPath);
  Assert.AreEqual(15, mSettings.VcsTimeoutSeconds);
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mSettings.VcsProvider := 'svn';
  mSettings.VcsGitPath := cGit;
  mSettings.VcsTimeoutSeconds := 60;
  mSettings.Save(mStore);
  Assert.Contains(mRouted.Text, '"provider": "svn"');
  Assert.Contains(mRouted.Text, '"timeoutSeconds": 60');
  Assert.Contains(mRouted.Text, '"git": {');
  Assert.AreEqual('', mRegistry.ReadString('VcsGitPath', ''), 'nicht in der Registry');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.AreEqual('svn', mLoaded.VcsProvider);
  Assert.AreEqual(cGit, mLoaded.VcsGitPath);
  Assert.AreEqual('', mLoaded.VcsSvnPath);
  Assert.AreEqual(60, mLoaded.VcsTimeoutSeconds);
  mRouted := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create,
    '{"vcs": {"provider": "cvs", "svn": {"path": "  s.exe "}, "timeoutSeconds": 0}}');
  mStore := mRouted;
  mLoaded.Load(mStore);
  Assert.AreEqual('auto', mLoaded.VcsProvider, 'unbekannte Art: Vorgabe');
  Assert.AreEqual('s.exe', mLoaded.VcsSvnPath, 'ohne Leerzeichen');
  Assert.AreEqual(15, mLoaded.VcsTimeoutSeconds, 'außerhalb 1 bis 300: Vorgabe');
end;

/// <summary>#1286 vcs.projects in settings.json, #1288 vcs.branch.confirm in der Registry.</summary>
procedure VcsProjectsAndBranchConfirm;
var
  mRegistry, mStore: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  // #1286: vcs.projects als JSON-Liste wie issues.projects.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('[]', mSettings.VcsProjects);
  mRouted := TAtlasRoutedSettingsStore.Create(TMemoryStore.Create, '');
  mStore := mRouted;
  mSettings.VcsProjects := '[{"match": "C:\\Kasse", "provider": "svn", "mainBranch": "trunk"}]';
  mSettings.Save(mStore);
  Assert.Contains(mRouted.Text, '"projects": [{"match": ');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.VcsProjects.Contains('"trunk"'), mLoaded.VcsProjects);
  // #1288: vcs.branch.confirm betrifft nur das Plugin und bleibt in der Registry; Vorgabe: Dialog zeigen.
  Assert.IsTrue(mSettings.VcsBranchConfirm);
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  mSettings.VcsBranchConfirm := False;
  mSettings.Save(mStore);
  Assert.AreEqual(0, mRegistry.ReadInteger('VcsBranchConfirm', 1));
  Assert.IsFalse(mRouted.Text.Contains('confirm'), 'nicht in settings.json');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.VcsBranchConfirm);
end;

/// <summary>#1290: vcs.branch.svn.* in der Registry, Vorgaben und Normalisierung.</summary>
procedure VcsBranchSvnOptions(const ARegistry, AStore: IAtlasSettingsStore; ARouted: TAtlasRoutedSettingsStore);
var
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  // #1290: vcs.branch.svn.* ebenfalls persönlich (Registry), mit Vorgaben und Normalisierung.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('{projektwurzel}/branches/{name}', mSettings.VcsBranchSvnLocation);
  Assert.AreEqual('head', mSettings.VcsBranchSvnSource);
  Assert.AreEqual('switch', mSettings.VcsBranchSvnAfter);
  Assert.AreEqual('..\{projekt}-{kennung}', mSettings.VcsBranchSvnCheckoutFolder);
  Assert.AreEqual('{kennung} Branch für {titel}', mSettings.VcsBranchSvnMessage);
  mSettings.VcsBranchSvnLocation := '^/branches/{kennung}';
  mSettings.VcsBranchSvnSource := 'workingCopy';
  mSettings.VcsBranchSvnAfter := 'checkout';
  mSettings.VcsBranchSvnCheckoutFolder := 'D:\Branches\{name}';
  mSettings.VcsBranchSvnMessage := 'Neu: {kennung}';
  mSettings.Save(AStore);
  Assert.AreEqual('checkout', ARegistry.ReadString('VcsBranchSvnAfter', ''));
  Assert.IsFalse(ARouted.Text.Contains('svn": {"location'), 'nicht in settings.json');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(AStore);
  Assert.AreEqual('^/branches/{kennung}', mLoaded.VcsBranchSvnLocation);
  Assert.AreEqual('workingCopy', mLoaded.VcsBranchSvnSource);
  Assert.AreEqual('checkout', mLoaded.VcsBranchSvnAfter);
  Assert.AreEqual('D:\Branches\{name}', mLoaded.VcsBranchSvnCheckoutFolder);
  Assert.AreEqual('Neu: {kennung}', mLoaded.VcsBranchSvnMessage);
  ARegistry.WriteString('VcsBranchSvnLocation', 'branches/{name}');
  ARegistry.WriteString('VcsBranchSvnSource', 'gestern');
  ARegistry.WriteString('VcsBranchSvnAfter', '');
  ARegistry.WriteString('VcsBranchSvnCheckoutFolder', '  ');
  ARegistry.WriteString('VcsBranchSvnMessage', '');
  mLoaded.Load(AStore);
  Assert.AreEqual('{projektwurzel}/branches/{name}', mLoaded.VcsBranchSvnLocation, 'ohne {projektwurzel} oder ^/');
  Assert.AreEqual('head', mLoaded.VcsBranchSvnSource);
  Assert.AreEqual('switch', mLoaded.VcsBranchSvnAfter);
  Assert.AreEqual('..\{projekt}-{kennung}', mLoaded.VcsBranchSvnCheckoutFolder);
  Assert.AreEqual('{kennung} Branch für {titel}', mLoaded.VcsBranchSvnMessage);
end;

/// <summary>#1291: vcs.externals.* in der Registry, Vorgaben und Normalisierung.</summary>
procedure VcsExternalsBranchOptions(const ARegistry, AStore: IAtlasSettingsStore; ARouted: TAtlasRoutedSettingsStore);
var
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  // #1291: vcs.externals.* persönlich (Registry), mit Vorgaben und Normalisierung.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('pin', mSettings.VcsExternalsOnBranch);
  Assert.AreEqual('modified', mSettings.VcsExternalsSuggestBranch);
  Assert.AreEqual('[]', mSettings.VcsExternalsRules);
  mSettings.VcsExternalsOnBranch := 'ask';
  mSettings.VcsExternalsSuggestBranch := 'always';
  mSettings.VcsExternalsRules := '[{"source": "^/Packages/Basis", "onBranch": "keep"}]';
  mSettings.Save(AStore);
  Assert.AreEqual('ask', ARegistry.ReadString('VcsExternalsOnBranch', ''));
  Assert.IsFalse(ARouted.Text.Contains('externals'), 'nicht in settings.json');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(AStore);
  Assert.AreEqual('ask', mLoaded.VcsExternalsOnBranch);
  Assert.AreEqual('always', mLoaded.VcsExternalsSuggestBranch);
  Assert.AreEqual('[{"source": "^/Packages/Basis", "onBranch": "keep"}]', mLoaded.VcsExternalsRules);
  ARegistry.WriteString('VcsExternalsOnBranch', 'branch');
  ARegistry.WriteString('VcsExternalsSuggestBranch', 'KEEP');
  ARegistry.WriteString('VcsExternalsRules', ' ');
  mLoaded.Load(AStore);
  Assert.AreEqual('pin', mLoaded.VcsExternalsOnBranch, 'branch ist keine Vorgabe für alle');
  Assert.AreEqual('modified', mLoaded.VcsExternalsSuggestBranch);
  Assert.AreEqual('[]', mLoaded.VcsExternalsRules);
end;

/// <summary>#1292: vcs.externals.show und .update in der Registry.</summary>
procedure VcsExternalsShowOptions(const ARegistry, AStore: IAtlasSettingsStore; ARouted: TAtlasRoutedSettingsStore);
var
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  // #1292: vcs.externals.show und .update ebenfalls persönlich.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.VcsExternalsShow);
  Assert.AreEqual('with', mSettings.VcsExternalsUpdate);
  mSettings.VcsExternalsShow := False;
  mSettings.VcsExternalsUpdate := 'ask';
  mSettings.Save(AStore);
  Assert.AreEqual(0, ARegistry.ReadInteger('VcsExternalsShow', 1));
  Assert.AreEqual('ask', ARegistry.ReadString('VcsExternalsUpdate', ''));
  Assert.IsFalse(ARouted.Text.Contains('externals'), 'nicht in settings.json');
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(AStore);
  Assert.IsFalse(mLoaded.VcsExternalsShow);
  Assert.AreEqual('ask', mLoaded.VcsExternalsUpdate);
  ARegistry.WriteString('VcsExternalsUpdate', 'immer');
  mLoaded.Load(AStore);
  Assert.AreEqual('with', mLoaded.VcsExternalsUpdate);
end;

procedure TAtlasPluginSettingsTests.VcsSettingsGoToGlobalFile;
var
  mRegistry, mStore: IAtlasSettingsStore;
  mRouted: TAtlasRoutedSettingsStore;
begin
  VcsToolSettingsGoToGlobalFile;
  VcsProjectsAndBranchConfirm;
  mRegistry := TMemoryStore.Create;
  mRouted := TAtlasRoutedSettingsStore.Create(mRegistry, '');
  mStore := mRouted;
  VcsBranchSvnOptions(mRegistry, mStore, mRouted);
  VcsExternalsBranchOptions(mRegistry, mStore, mRouted);
  VcsExternalsShowOptions(mRegistry, mStore, mRouted);
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
  // tests.affectedDepth (#1353): 1 bis 5.
  Settings.TestsAffectedDepth := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinTestsAffectedDepth, Settings.TestsAffectedDepth);
  Settings.TestsAffectedDepth := 7;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxTestsAffectedDepth, Settings.TestsAffectedDepth);
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

/// <summary>Meine Issues (#765): Vorgaben.</summary>
procedure AssertIssuesDefaults(const ASettings: TAtlasPluginSettings);
begin
  Assert.IsFalse(ASettings.WelcomePageIssues, 'standardmäßig aus: kein Netzzugriff');
  Assert.AreEqual('', ASettings.IssuesTracker, 'aus der .atlas');
  Assert.AreEqual('[]', ASettings.IssuesQueries, 'je Anbieter „Mir zugewiesen“ (#1262)');
  Assert.IsTrue(ASettings.IssuesQueryPicker);
  Assert.IsTrue(ASettings.IssuesCreate, '„Issue anlegen …“ an (#1268)');
  Assert.IsTrue(ASettings.IssuesCreateIncludeCode, 'Codeausschnitt vorgeschlagen (#1268)');
  Assert.AreEqual(0, ASettings.CreateIssueKey, 'frei belegbar, ohne Vorgabe');
  Assert.AreEqual('branch', ASettings.IssuesStart);
  Assert.AreEqual('', ASettings.IssuesBranchPattern, 'je Versionsverwaltung');
  Assert.AreEqual('', ASettings.IssuesBranchBase);
  Assert.AreEqual('{kennung} ', ASettings.IssuesCommitPattern);
  Assert.IsTrue(ASettings.TrackerLogin);
  Assert.IsTrue(ASettings.IssuesPreview, 'Vorschau (#1264) an');
  Assert.IsTrue(ASettings.IssuesPreviewComments);
  Assert.IsTrue(ASettings.IssuesCodeLinks);
  Assert.IsTrue(ASettings.IssuesBlameLinks);
  Assert.AreEqual(200, ASettings.IssuesBlameMaxRevisions);
  Assert.IsTrue(ASettings.IssuesPreviewChecklists);
  Assert.IsTrue(ASettings.IssuesChecklistStatus);
  Assert.IsTrue(ASettings.IssuesPreviewLinks, 'Verknüpfungen als Baum (#1279) an');
  Assert.IsTrue(ASettings.IssuesWarnBlocked, 'Warnung beim Beginnen (#1279) an');
  Assert.IsTrue(ASettings.IssuesBoard, 'Board (#1272) an');
  Assert.IsTrue(ASettings.IssuesBoardConfirmMove, 'Rückfrage beim Ziehen an');
  Assert.IsTrue(ASettings.IssuesBoardOnlyMine, 'Board öffnet mit „Nur meine“');
  Assert.IsTrue(ASettings.WelcomePageSprint, 'Sprint-Kachel (#1277) an');
  Assert.IsTrue(ASettings.IssuesSprintBurndown, 'Burndown an');
  Assert.IsTrue(ASettings.IssuesSprintCompare, 'Vergleich mit dem Vorsprint an');
  Assert.IsTrue(ASettings.IssuesPaletteSearch, 'Palettensuche (#1270) an');
  Assert.IsTrue(ASettings.IssuesPreviewDevelopment, 'Reiter „Entwicklung“ (#1269)');
  Assert.IsFalse(ASettings.IssuesNotify, 'Meldungen (#1271) aus');
  Assert.AreEqual(10, ASettings.IssuesNotifyIntervalMinutes);
  Assert.AreEqual('assignedOrCreated', ASettings.IssuesNotifyScope);
  Assert.IsTrue(ASettings.IssuesAttach, 'Anhängen (#1276) an');
  Assert.AreEqual('', ASettings.IssuesAttachLogFiles);
  Assert.AreEqual(1920, ASettings.IssuesAttachMaxImageWidth);
  // Die Einstellungen kennen den Bereich nicht (A-09): dieselben Werte wie dort.
  Assert.AreEqual(TAtlasTrackerNaming.CommitPattern, ASettings.IssuesCommitPattern);
  Assert.AreEqual(TAtlasMyIssues.StartName(TAtlasIssueStart.Branch), TAtlasPluginSettings.IssuesStartBranch);
  Assert.AreEqual(TAtlasMyIssues.StartName(TAtlasIssueStart.Remember),
    TAtlasPluginSettings.IssuesStartRemember);
end;

/// <summary>Meine Issues (#765, #1271): Normalisieren.</summary>
procedure NormalizeIssuesOptions(var ASettings: TAtlasPluginSettings);
begin
  // Normalisieren.
  ASettings.IssuesTracker := ' YouTrack ';
  ASettings.IssuesQueries := '  ';
  ASettings.IssuesStart := 'REMEMBER';
  ASettings.IssuesBranchPattern := ' bugfix/{kennung} ';
  ASettings.IssuesBranchBase := ' develop ';
  ASettings.IssuesCommitPattern := '[{kennung}] ';
  ASettings.Normalize;
  Assert.AreEqual('youtrack', ASettings.IssuesTracker);
  Assert.AreEqual('[]', ASettings.IssuesQueries, 'leer = keine');
  Assert.AreEqual('remember', ASettings.IssuesStart);
  Assert.AreEqual('bugfix/{kennung}', ASettings.IssuesBranchPattern);
  Assert.AreEqual('develop', ASettings.IssuesBranchBase);
  Assert.AreEqual('[{kennung}] ', ASettings.IssuesCommitPattern, 'Leerzeichen am Ende bleibt');
  ASettings.IssuesTracker := 'jira';
  ASettings.IssuesStart := 'egal';
  ASettings.IssuesCommitPattern := '';
  ASettings.IssuesBlameMaxRevisions := 0;
  ASettings.Normalize;
  Assert.AreEqual(1, ASettings.IssuesBlameMaxRevisions, 'unter 1: 1');
  ASettings.IssuesBlameMaxRevisions := 100000;
  ASettings.Normalize;
  Assert.AreEqual(5000, ASettings.IssuesBlameMaxRevisions, 'über 5000: 5000');
  Assert.AreEqual('', ASettings.IssuesTracker);
  Assert.AreEqual('branch', ASettings.IssuesStart);
  Assert.AreEqual('', ASettings.IssuesCommitPattern, 'leer = aus');
  // #1271: Abstand begrenzt, unbekannter Umfang fällt auf den Standard.
  ASettings.IssuesNotifyIntervalMinutes := 1;
  ASettings.IssuesNotifyScope := ' WATCHED ';
  ASettings.Normalize;
  Assert.AreEqual(2, ASettings.IssuesNotifyIntervalMinutes, 'mindestens 2 Minuten');
  Assert.AreEqual('watched', ASettings.IssuesNotifyScope);
  ASettings.IssuesNotifyIntervalMinutes := 100000;
  ASettings.IssuesNotifyScope := 'alles';
  ASettings.Normalize;
  Assert.AreEqual(1440, ASettings.IssuesNotifyIntervalMinutes, 'höchstens ein Tag');
  Assert.AreEqual('assignedOrCreated', ASettings.IssuesNotifyScope);
end;

/// <summary>Meine Issues: alle Werte von der Vorgabe abweichend setzen.</summary>
procedure SetIssuesOptions(var ASettings: TAtlasPluginSettings);
begin
  // Speichern und Laden.
  ASettings.WelcomePageIssues := True;
  ASettings.IssuesTracker := 'github';
  ASettings.IssuesQueries := '[{"name": "Bugs", "query": "label:bug"}]';
  ASettings.IssuesQueryPicker := False;
  ASettings.IssuesCreate := False;
  ASettings.IssuesCreateIncludeCode := False;
  ASettings.CreateIssueKey := $4049;
  ASettings.IssuesStart := 'remember';
  ASettings.IssuesBranchPattern := 'issue/{nummer}';
  ASettings.IssuesBranchBase := 'trunk';
  ASettings.IssuesCommitPattern := '{kennung}: ';
  ASettings.TrackerLogin := False;
  ASettings.IssuesPreview := False;
  ASettings.IssuesPreviewComments := False;
  ASettings.IssuesCodeLinks := False;
  ASettings.IssuesBlameLinks := False;
  ASettings.IssuesBlameMaxRevisions := 75;
  ASettings.IssuesPreviewChecklists := False;
  ASettings.IssuesChecklistStatus := False;
  ASettings.IssuesPreviewLinks := False;
  ASettings.IssuesWarnBlocked := False;
  ASettings.IssuesBoard := False;
  ASettings.IssuesBoardConfirmMove := False;
  ASettings.IssuesBoardOnlyMine := False;
  ASettings.WelcomePageSprint := False;
  ASettings.IssuesSprintBurndown := False;
  ASettings.IssuesSprintCompare := False;
  ASettings.IssuesPaletteSearch := False;
  ASettings.IssuesPreviewDevelopment := False;
  ASettings.IssuesNotify := True;
  ASettings.IssuesNotifyIntervalMinutes := 5;
  ASettings.IssuesNotifyScope := 'assigned';
  ASettings.IssuesAttach := False;
  ASettings.IssuesAttachLogFiles := '$(ProjectDir)\logs\*.log;C:\Temp\app.log';
  ASettings.IssuesAttachMaxImageWidth := 1280;
end;

/// <summary>Meine Issues: gespeicherte Werte gelesen.</summary>
procedure AssertIssuesLoaded(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsTrue(ALoaded.WelcomePageIssues);
  Assert.AreEqual('github', ALoaded.IssuesTracker);
  Assert.AreEqual('[{"name": "Bugs", "query": "label:bug"}]', ALoaded.IssuesQueries);
  Assert.IsFalse(ALoaded.IssuesQueryPicker);
  Assert.IsFalse(ALoaded.IssuesCreate);
  Assert.IsFalse(ALoaded.IssuesCreateIncludeCode);
  Assert.AreEqual($4049, ALoaded.CreateIssueKey, 'Strg+I');
  Assert.AreEqual('remember', ALoaded.IssuesStart);
  Assert.AreEqual('issue/{nummer}', ALoaded.IssuesBranchPattern);
  Assert.AreEqual('trunk', ALoaded.IssuesBranchBase);
  Assert.AreEqual('{kennung}: ', ALoaded.IssuesCommitPattern);
  Assert.IsFalse(ALoaded.TrackerLogin);
  Assert.IsFalse(ALoaded.IssuesPreview);
  Assert.IsFalse(ALoaded.IssuesPreviewComments);
  Assert.IsFalse(ALoaded.IssuesCodeLinks);
  Assert.IsFalse(ALoaded.IssuesBlameLinks);
  Assert.AreEqual(75, ALoaded.IssuesBlameMaxRevisions);
  Assert.IsFalse(ALoaded.IssuesPaletteSearch);
  Assert.IsFalse(ALoaded.IssuesPreviewChecklists);
  Assert.IsFalse(ALoaded.IssuesChecklistStatus);
  Assert.IsFalse(ALoaded.IssuesPreviewLinks);
  Assert.IsFalse(ALoaded.IssuesWarnBlocked);
  Assert.IsFalse(ALoaded.IssuesBoard);
  Assert.IsFalse(ALoaded.IssuesBoardConfirmMove);
  Assert.IsFalse(ALoaded.IssuesBoardOnlyMine);
  Assert.IsFalse(ALoaded.WelcomePageSprint);
  Assert.IsFalse(ALoaded.IssuesSprintBurndown);
  Assert.IsFalse(ALoaded.IssuesSprintCompare);
  Assert.IsFalse(ALoaded.IssuesPreviewDevelopment);
  Assert.IsTrue(ALoaded.IssuesNotify);
  Assert.AreEqual(5, ALoaded.IssuesNotifyIntervalMinutes);
  Assert.AreEqual('assigned', ALoaded.IssuesNotifyScope);
  Assert.IsFalse(ALoaded.IssuesAttach);
  Assert.AreEqual('$(ProjectDir)\logs\*.log;C:\Temp\app.log', ALoaded.IssuesAttachLogFiles);
  Assert.AreEqual(1280, ALoaded.IssuesAttachMaxImageWidth);
end;

procedure TAtlasPluginSettingsTests.WelcomeIssuesOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  AssertIssuesDefaults(Settings);
  NormalizeIssuesOptions(Settings);
  SetIssuesOptions(Settings);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  AssertIssuesLoaded(Loaded);
  // Bildbreite außerhalb 320–7680 wird begrenzt.
  Settings.IssuesAttachMaxImageWidth := 50;
  Settings.Normalize;
  Assert.AreEqual(320, Settings.IssuesAttachMaxImageWidth);
  Settings.IssuesAttachMaxImageWidth := 100000;
  Settings.Normalize;
  Assert.AreEqual(7680, Settings.IssuesAttachMaxImageWidth);
end;

procedure TAtlasPluginSettingsTests.IssuesSyncOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.IssuesSyncState, 'an: geschrieben wird trotzdem nur nach Senden bzw. Beginnen');
  Assert.AreEqual('State', mSettings.IssuesStateField);
  Assert.AreEqual('Assignee', mSettings.IssuesAssigneeField);
  Assert.AreEqual('', mSettings.IssuesStartState, 'Zustand beim Beginnen nicht ändern');
  Assert.IsFalse(mSettings.IssuesAssignOnStart);
  Assert.AreEqual('', mSettings.IssuesStartComment);
  Assert.AreEqual('', mSettings.IssuesEndStates);
  Assert.AreEqual('Erledigt in {branch}.\n{commits}', mSettings.IssuesEndComment);
  // Normalisieren: Felder ohne Leerraum außen, leer = Vorgabe; Vorlagen einzeilig mit \n.
  mSettings.IssuesStateField := '  Status ';
  mSettings.IssuesAssigneeField := '';
  mSettings.IssuesStartState := ' In Arbeit ';
  mSettings.IssuesStartComment := 'Beginne {kennung}'#13#10'in {branch}';
  mSettings.IssuesEndStates := ' Zur Prüfung, Erledigt ';
  mSettings.IssuesEndComment := StringOfChar('x', TAtlasPluginSettings.MaxIssuesTemplate + 10);
  mSettings.Normalize;
  Assert.AreEqual('Status', mSettings.IssuesStateField);
  Assert.AreEqual('Assignee', mSettings.IssuesAssigneeField, 'leer = Vorgabe');
  Assert.AreEqual('In Arbeit', mSettings.IssuesStartState);
  Assert.AreEqual('Beginne {kennung}\nin {branch}', mSettings.IssuesStartComment);
  Assert.AreEqual('Zur Prüfung, Erledigt', mSettings.IssuesEndStates);
  Assert.AreEqual(TAtlasPluginSettings.MaxIssuesTemplate, Integer(Length(mSettings.IssuesEndComment)));
  // Speichern und Laden.
  mSettings.IssuesSyncState := False;
  mSettings.IssuesAssignOnStart := True;
  mSettings.IssuesEndComment := 'Fertig: {pr}';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.IssuesSyncState);
  Assert.AreEqual('Status', mLoaded.IssuesStateField);
  Assert.AreEqual('Assignee', mLoaded.IssuesAssigneeField);
  Assert.AreEqual('In Arbeit', mLoaded.IssuesStartState);
  Assert.IsTrue(mLoaded.IssuesAssignOnStart);
  Assert.AreEqual('Beginne {kennung}\nin {branch}', mLoaded.IssuesStartComment);
  Assert.AreEqual('Zur Prüfung, Erledigt', mLoaded.IssuesEndStates);
  Assert.AreEqual('Fertig: {pr}', mLoaded.IssuesEndComment);
end;

procedure TAtlasPluginSettingsTests.IssuesTimeOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(mSettings.IssuesTimeTracking, 'ab Werk aus');
  Assert.AreEqual(10, mSettings.IssuesIdleMinutes);
  Assert.AreEqual(5, mSettings.IssuesTimeRounding);
  mSettings.IssuesIdleMinutes := 0;
  mSettings.IssuesTimeRounding := 500;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinIssuesIdleMinutes, mSettings.IssuesIdleMinutes);
  Assert.AreEqual(TAtlasPluginSettings.MaxIssuesTimeRounding, mSettings.IssuesTimeRounding);
  mSettings.IssuesTimeTracking := True;
  mSettings.IssuesIdleMinutes := 15;
  mSettings.IssuesTimeRounding := 15;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.IssuesTimeTracking);
  Assert.AreEqual(15, mLoaded.IssuesIdleMinutes);
  Assert.AreEqual(15, mLoaded.IssuesTimeRounding);
end;

procedure TAtlasPluginSettingsTests.IssuesCommentOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.IssuesCommentEditor, 'Kommentar-Editor ist vorgegeben an');
  Assert.AreEqual(TAtlasPluginSettings.DefaultIssuesCommentSnippets, mSettings.IssuesCommentSnippets, 'zwei Vorgabe-Bausteine');
  // Normalisieren: leer = keine Bausteine, nicht die Vorgabe.
  mSettings.IssuesCommentSnippets := '   ';
  mSettings.Normalize;
  Assert.AreEqual('[]', mSettings.IssuesCommentSnippets);
  // Speichern und Laden.
  mSettings.IssuesCommentEditor := False;
  mSettings.IssuesCommentSnippets := '[{"name":"Danke","text":"Danke!"}]';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.IssuesCommentEditor);
  Assert.AreEqual('[{"name":"Danke","text":"Danke!"}]', mLoaded.IssuesCommentSnippets);
end;

/// <summary>Ausblenden am Element: Werte von der Vorgabe abweichend setzen.</summary>
procedure SetHideElementOptions(var ASettings: TAtlasPluginSettings);
begin
  ASettings.BlockEndLabels := False;
  ASettings.BlockEndLabelsMinLines := 40;
  ASettings.DimUnusedUses := False;
  ASettings.RecursionMarkers := False;
  ASettings.RecursionMarkersDepth := 7;
  ASettings.ExitPoints := False;
  ASettings.ExitPointsExceptions := False;
  ASettings.ExitPointsLoops := False;
  ASettings.ExitPointsBadge := False;
  ASettings.Reassigned := False;
  ASettings.ReassignedTargets := 'fields,locals';
  ASettings.ReassignedStyle := 'wavy';
  ASettings.ReassignedColor := '#00ff80';
  ASettings.ExpressionType := False;
  ASettings.ExpressionTypeConversions := False;
  ASettings.ExpressionTypeConstValue := False;
  ASettings.ExpressionTypeKey := $4054;
  ASettings.InlineDiagnostics := 'off';
  ASettings.ProblemsStatusCounter := False;
  ASettings.NextProblemKey := 0;
  ASettings.PreviousProblemKey := $6077;
  ASettings.HideElementKey := 0;
end;

/// <summary>Ausblenden am Element: gespeicherte Werte gelesen.</summary>
procedure AssertHideElementLoaded(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsFalse(ALoaded.BlockEndLabels, 'abschaltbar');
  Assert.AreEqual(40, ALoaded.BlockEndLabelsMinLines);
  Assert.IsFalse(ALoaded.DimUnusedUses, 'uses-Abblenden abschaltbar');
  Assert.IsFalse(ALoaded.RecursionMarkers, 'Rekursionssymbole abschaltbar (#623)');
  Assert.AreEqual(7, ALoaded.RecursionMarkersDepth);
  Assert.IsFalse(ALoaded.ExitPoints, 'Austrittspunkte abschaltbar (#698)');
  Assert.IsFalse(ALoaded.ExitPointsExceptions);
  Assert.IsFalse(ALoaded.ExitPointsLoops);
  Assert.IsFalse(ALoaded.ExitPointsBadge);
  Assert.IsFalse(ALoaded.Reassigned, 'Unterstreichung abschaltbar (#712)');
  Assert.AreEqual('locals,fields', ALoaded.ReassignedTargets, 'feste Reihenfolge');
  Assert.AreEqual('wavy', ALoaded.ReassignedStyle);
  Assert.AreEqual('#00FF80', ALoaded.ReassignedColor);
  Assert.IsFalse(ALoaded.ExpressionType, 'Typ des Ausdrucks abschaltbar (#689)');
  Assert.IsFalse(ALoaded.ExpressionTypeConversions);
  Assert.IsFalse(ALoaded.ExpressionTypeConstValue);
  Assert.AreEqual($4054, ALoaded.ExpressionTypeKey);
  Assert.AreEqual('off', ALoaded.InlineDiagnostics, 'Fehlertext abschaltbar');
  Assert.IsFalse(ALoaded.ProblemsStatusCounter, 'Zähler abschaltbar');
  Assert.AreEqual(0, ALoaded.NextProblemKey);
  Assert.AreEqual($6077, ALoaded.PreviousProblemKey);
  Assert.AreEqual(0, ALoaded.HideElementKey, '0 = keine Taste');
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
  SetHideElementOptions(Settings);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  AssertHideElementLoaded(Loaded);
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
  Assert.AreEqual('', Settings.BuildOnOpenConfig, 'wie im Projekt (#1293)');
  Assert.AreEqual('', Settings.BuildOnOpenPlatform, 'wie im Projekt (#1293)');
  // Normalisieren: unbekannte Art = make, unbekannter Umfang = all, Wartezeit in den Grenzen, Liste ohne Endung
  // und Doppelte.
  Settings.BuildOnOpenKind := 'BUILD';
  Settings.BuildOnOpenScope := 'Active';
  Settings.BuildOnOpenDelayMs := 10;
  Settings.BuildOnOpenExclude := ' Atlas.IDE.Expert.dproj; atlas.ide.expert,, Demo ';
  Settings.BuildOnOpenConfig := ' Debug ';
  Settings.BuildOnOpenPlatform := ' Win64 ';
  Settings.Normalize;
  Assert.AreEqual('Debug', Settings.BuildOnOpenConfig);
  Assert.AreEqual('Win64', Settings.BuildOnOpenPlatform);
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
  Assert.AreEqual('Debug', Loaded.BuildOnOpenConfig);
  Assert.AreEqual('Win64', Loaded.BuildOnOpenPlatform);
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

/// <summary>Units suchen (#777): Werte von der Vorgabe abweichend setzen.</summary>
procedure SetUnitSearchOptions(var ASettings: TAtlasPluginSettings);
begin
  // Speichern und Laden.
  ASettings.UnitSearchEnabled := False;
  ASettings.UnitSearchReplaceIdeDialog := False;
  ASettings.UnitSearchReplaceUseUnitDialog := False;
  ASettings.UnitSearchReplaceFormsDialog := False;
  ASettings.UnitSearchRememberCollapsed := False;
  ASettings.UnitSearchFilters := False;
  ASettings.UnitSearchFilterSyntax := False;
  ASettings.UnitSearchFormCaptions := False;
  ASettings.UnitSearchPreview := False;
  ASettings.UnitSearchPreviewForm := False;
  ASettings.UnitSearchPreviewUsedBy := False;
  ASettings.UnitSearchPreviewAutoCollapse := False;
  ASettings.UnitSearchMultiSelect := False;
  ASettings.UnitSearchActions := False;
  ASettings.UnitSearchActionsAddUses := False;
  ASettings.UnitSearchPathStyle := 'compact';
  ASettings.UnitSearchDefaultScope := 'library';
  ASettings.UnitSearchKey := $6055;
  // Suchleiste (#878): Liste in den Meldungen abschaltbar.
  ASettings.SearchResultsInMessages := False;
end;

/// <summary>Units suchen (#777): gespeicherte Werte gelesen.</summary>
procedure AssertUnitSearchLoaded(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsFalse(ALoaded.UnitSearchEnabled);
  Assert.IsFalse(ALoaded.UnitSearchReplaceIdeDialog);
  Assert.IsFalse(ALoaded.UnitSearchReplaceUseUnitDialog);
  Assert.IsFalse(ALoaded.UnitSearchReplaceFormsDialog);
  Assert.IsFalse(ALoaded.SearchResultsInMessages);
  Assert.IsFalse(ALoaded.UnitSearchRememberCollapsed);
  Assert.IsFalse(ALoaded.UnitSearchFilters);
  Assert.IsFalse(ALoaded.UnitSearchFilterSyntax);
  Assert.IsFalse(ALoaded.UnitSearchFormCaptions);
  Assert.IsFalse(ALoaded.UnitSearchPreview);
  Assert.IsFalse(ALoaded.UnitSearchPreviewForm);
  Assert.IsFalse(ALoaded.UnitSearchPreviewUsedBy);
  Assert.IsFalse(ALoaded.UnitSearchPreviewAutoCollapse);
  Assert.IsFalse(ALoaded.UnitSearchMultiSelect);
  Assert.IsFalse(ALoaded.UnitSearchActions);
  Assert.IsFalse(ALoaded.UnitSearchActionsAddUses);
  Assert.AreEqual('compact', ALoaded.UnitSearchPathStyle);
  Assert.AreEqual('folder', ALoaded.UnitSearchGroupBy);
  Assert.AreEqual('library', ALoaded.UnitSearchDefaultScope);
  Assert.AreEqual($6055, ALoaded.UnitSearchKey);
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
  Assert.IsTrue(Settings.UnitSearchFormCaptions);
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
  SetUnitSearchOptions(Settings);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  AssertUnitSearchLoaded(Loaded);
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
  // #506: nicht mehr experimentell, also an; drei Zeilen; Grenzen 1 bis 10.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.StickyScroll);
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
  // #1230: if/else-Blöcke an, ab 25 Zeilen; Grenzen 5 bis 1000.
  Assert.IsTrue(Settings.StickyScrollBlocks);
  Assert.AreEqual(25, Settings.StickyScrollBlockMinLines);
  Settings.StickyScrollBlocks := False;
  Settings.StickyScrollBlockMinLines := 40;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.StickyScrollBlocks);
  Assert.AreEqual(40, Loaded.StickyScrollBlockMinLines);
  Loaded.StickyScrollBlockMinLines := 1;
  Loaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinStickyBlockLines, Loaded.StickyScrollBlockMinLines);
  // Was der Kopf zeigt: Typen und Routinen an, weitere Anweisungsblöcke aus; jede Art einzeln gespeichert.
  Assert.IsTrue(Settings.StickyScrollTypes and Settings.StickyScrollRoutines);
  Assert.IsFalse(Settings.StickyScrollLoops or Settings.StickyScrollTry or Settings.StickyScrollCase or
    Settings.StickyScrollWith);
  Settings.StickyScrollTypes := False;
  Settings.StickyScrollLoops := True;
  Settings.StickyScrollCase := True;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.StickyScrollTypes);
  Assert.IsTrue(Loaded.StickyScrollRoutines);
  Assert.IsTrue(Loaded.StickyScrollLoops);
  Assert.IsFalse(Loaded.StickyScrollTry);
  Assert.IsTrue(Loaded.StickyScrollCase);
  Assert.IsFalse(Loaded.StickyScrollWith);
end;

procedure TAtlasPluginSettingsTests.MinimapOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #873: experimentell, also aus; Vorgaben laut Issue; Speichern, Laden, Klemmen.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(Settings.Minimap);
  Assert.AreEqual('characters', Settings.MinimapRender);
  Assert.AreEqual(120, Settings.MinimapWidth);
  Assert.AreEqual(2, Settings.MinimapScale);
  Assert.AreEqual(120, Settings.MinimapMaxColumn);
  Assert.AreEqual('right', Settings.MinimapSide);
  Assert.AreEqual('always', Settings.MinimapShowSlider);
  Assert.IsTrue(Settings.MinimapSectionHeaders and Settings.MinimapHighlightMethod and Settings.MinimapMarkers and
    Settings.MinimapClickJumps);
  Assert.IsFalse(Settings.MinimapNoticeShown);
  Settings.Minimap := True;
  Settings.MinimapRender := 'blocks';
  Settings.MinimapWidth := 90;
  Settings.MinimapScale := 3;
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
  Assert.AreEqual('blocks', Loaded.MinimapRender);
  Assert.AreEqual(90, Loaded.MinimapWidth);
  Assert.AreEqual(3, Loaded.MinimapScale);
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
  Assert.AreEqual('characters', Loaded.MinimapRender);
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
  ASettings.ProblemsWindowGroupBy := 'category';
  ASettings.ProblemsWindowColumns := 'kind:70,-rule';
  ASettings.ProblemsWindowCompiler := True;
  ASettings.ProblemsWindowFollowCursor := False;
  ASettings.ProblemsWindowKey := $C051;
  ASettings.ProblemsUpdate := 'save';
  ASettings.ProblemsLiveDelayMs := 900;
  ASettings.FixBulk := False;
  ASettings.HoverProblemActions := False;
  ASettings.ProblemsList := True;
  ASettings.ProblemsCompilerMerge := 'both';
  ASettings.ProblemsShowCompilerCode := False;
end;

/// <summary>Fenster „Atlas-Prüfung“ (#909): gespeicherte Werte gelesen.</summary>
procedure AssertProblemsWindowLoaded(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsFalse(ALoaded.ProblemsWindow);
  Assert.AreEqual('file', ALoaded.ProblemsWindowScope);
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
  Assert.IsTrue(ALoaded.ProblemsList);
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
  Assert.AreEqual('file', Settings.ProblemsWindowGroupBy);
  Assert.AreEqual('', Settings.ProblemsWindowColumns);
  Assert.IsFalse(Settings.ProblemsWindowCompiler);
  Assert.IsTrue(Settings.ProblemsWindowFollowCursor);
  Assert.AreEqual($C050, Settings.ProblemsWindowKey, 'Strg+Alt+P');
  Assert.IsTrue(Settings.FixBulk, 'Sammelkorrektur (#1352) an');
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

procedure TAtlasPluginSettingsTests.EditorDesignerBarOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.EditorDesignerBar);
  Assert.AreEqual(32988, Settings.DesignerSearchKey, 'Alt+^');
  Assert.AreEqual(TAtlasPluginSettings.DesignerSearchWindow, Settings.DesignerSearchStyle, 'großes Fenster');
  Assert.IsFalse(Settings.DesignerTabOrderClick, 'experimentell: aus');
  Assert.IsFalse(Settings.DesignerAlign, 'experimentell: aus');
  Settings.EditorDesignerBar := False;
  Settings.DesignerSearchKey := 0;
  Settings.DesignerSearchStyle := TAtlasPluginSettings.DesignerSearchPopup;
  Settings.DesignerTabOrderClick := True;
  Settings.DesignerAlign := True;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.EditorDesignerBar);
  Assert.AreEqual(0, Loaded.DesignerSearchKey, 'keine Taste');
  Assert.AreEqual(TAtlasPluginSettings.DesignerSearchPopup, Loaded.DesignerSearchStyle);
  Assert.IsTrue(Loaded.DesignerTabOrderClick);
  Assert.IsTrue(Loaded.DesignerAlign);
  Store.WriteString('DesignerSearchStyle', 'riesig');
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.DesignerSearchWindow, Loaded.DesignerSearchStyle, 'Unbekanntes: Vorgabe');
end;

/// <summary>Schnelle Lesezeichen (#1104): Werte von der Vorgabe abweichend setzen.</summary>
procedure SetQuickBookmarkOptions(var ASettings: TAtlasPluginSettings);
begin
  ASettings.QuickBookmarks := False;
  ASettings.QuickBookmarksGutter := False;
  ASettings.QuickBookmarksGutterClick := False;
  ASettings.QuickBookmarksNumberedKeys := False;
  ASettings.QuickBookmarkKey := $604C;
  ASettings.QuickBookmarkKeyPriority := False;
  ASettings.QuickBookmarkChordWait := 500;
  ASettings.QuickBookmarkSetKey := $C031;
  ASettings.QuickBookmarkSetKeyPriority := False;
  ASettings.QuickBookmarkJumpKey := $8031;
  ASettings.QuickBookmarkJumpKeyPriority := False;
  ASettings.QuickBookmarksScope := 'file';
  ASettings.QuickBookmarksImportIde := False;
  ASettings.NextBookmarkKey := $4071;
  ASettings.PreviousBookmarkKey := $6071;
end;

/// <summary>Schnelle Lesezeichen (#1104): gespeicherte Werte gelesen.</summary>
procedure AssertQuickBookmarkLoaded(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsFalse(ALoaded.QuickBookmarks);
  Assert.IsFalse(ALoaded.QuickBookmarksGutter);
  Assert.IsFalse(ALoaded.QuickBookmarksGutterClick);
  Assert.IsFalse(ALoaded.QuickBookmarksNumberedKeys);
  Assert.AreEqual($604C, ALoaded.QuickBookmarkKey);
  Assert.IsFalse(ALoaded.QuickBookmarkKeyPriority);
  Assert.AreEqual(500, ALoaded.QuickBookmarkChordWait);
  Assert.AreEqual($C031, ALoaded.QuickBookmarkSetKey);
  Assert.IsFalse(ALoaded.QuickBookmarkSetKeyPriority);
  Assert.AreEqual($8031, ALoaded.QuickBookmarkJumpKey);
  Assert.IsFalse(ALoaded.QuickBookmarkJumpKeyPriority);
  Assert.AreEqual('file', ALoaded.QuickBookmarksScope);
  Assert.IsFalse(ALoaded.QuickBookmarksImportIde);
  Assert.AreEqual($4071, ALoaded.NextBookmarkKey);
  Assert.AreEqual($6071, ALoaded.PreviousBookmarkKey);
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
  SetQuickBookmarkOptions(Settings);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  AssertQuickBookmarkLoaded(Loaded);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginSettingsTests);
  TDUnitX.RegisterTestFixture(TAtlasSettingsScopesTests);

end.
