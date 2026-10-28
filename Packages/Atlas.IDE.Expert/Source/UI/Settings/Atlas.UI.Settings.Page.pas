unit Atlas.UI.Settings.Page;

// Seite „Atlas“ unter Tools › Optionen › Drittanbieter (#227). Reine VCL, im Code aufgebaut: Reiter je
// Bereich, darin Steuerelemente untereinander; die IDE skaliert sie mit dem Dialog. Die DFM ist leer;
// TCustomFrame.Create verlangt für abgeleitete Frames eine Ressource. Laden und Speichern über
// TAtlasPluginSettings; die IDE-Schicht liest und schreibt die Registry.
// Die Tastenkürzel von Befehlspalette und Prüfung stehen auf der eigenen Seite „Tastenkonflikte“
// (Atlas.UI.Settings.Keys, #494). Der Reiter „Robustheit“ zeigt, was die Sicherung nach wiederholten
// Fehlern abgeschaltet hat, und schaltet es wieder ein (#493).
// Abschnitt Symbolindex (#492): Verwendungen an/aus, Speichergrenze, Kennzahlen (Units, Deklarationen,
// Größe, letzte Aktualisierung), „Index neu aufbauen“ und „Index löschen“. Die Seite kennt den Server
// nicht; die IDE-Schicht führt die Befehle über OnIndexMetrics, OnIndexRebuild, OnIndexClear im
// Hintergrund aus und meldet den Text mit IndexAnswered (#874). Bis dahin steht „Frage den Server …“ da,
// und die drei Knöpfe sind gesperrt; der Dialog bleibt bedienbar, auch wenn der Server gerade indexiert.
// Im Seitenkopf steht das Atlas-Symbol (#751) passend zu Thema und Skalierung.
// Jeder Reiter bleibt niedriger als die Seite: Sonst scrollt die IDE ihren Bereich beim Reiterwechsel
// zum Fokus, und die Seite „springt“.
// Reiter Vervollständigung: angeheftete Favoriten (#458) an/aus, Liste („TDataSet.Open“) mit „Entfernen“
// und „Alle entfernen“. Die Seite kennt die Ablage nicht; OnFavorites liefert die Liste, OnRemoveFavorites
// löst die Schlüssel sofort (nicht erst mit OK).
// Reveal (#628, „Einstellungen dazu …“ am gezeichneten Element): wählt den Reiter einer Einstellung über ihren
// Schlüssel (Name der Plugin-Einstellung), rollt sie ins Bild, setzt den Fokus und hebt die Zeile fett hervor.
// Bereich Prüfregeln (#909): Die Regeln selbst stehen in den Dialogen der Einstellungsdateien (atlas.json des
// Projekts, settings.json über „Weitere globale Einstellungen“) mit einem Knoten je Gruppe; im Hauptknoten der
// Weg dorthin (OnRulesProject, OnRulesGlobal). Unterknoten „Prüffenster“ (problems.window*, problems.live),
// „Compiler vorab“ (problems.compilerMerge, problems.showCompilerCode) und „Profile und Baseline“.
// Bereich Versionsverwaltung (#1285): Art (vcs.provider), Programme git und svn mit eigenem Pfad, „…“ und
// „Prüfen“ (Version und Fundort, im Hintergrund über OnVcsCheck), Zeitlimit je Aufruf und „Aktuelles Projekt“
// (beim ersten Zeigen der Seite einmal im Hintergrund abgefragt, OnVcsProject); Links auf die Seiten, die die
// Anzeige steuern. Ohne Klick startet kein Prozess: Beim Öffnen zeigt OnVcsLocate nur, welche Datei gälte.
// Bereich Issue-Tracker (#1280): Tracker, Abfrage, Start-Optionen, Muster und Zugang (issues.*); auf der
// Willkommensseite bleibt nur die Sektion an/aus mit dem Sprung „Tracker-Einstellungen …“.

interface

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  System.Generics.Collections,
  System.JSON,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.Menus,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Build.ReleaseGuard,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Vcs,
  Atlas.Core.Welcome.QuickActions,
  Atlas.Core.Welcome.Layouts,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.SafeMode,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Groups,
  Atlas.Core.Editor.Overview,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Core.Settings.EventBreakNames,
  Atlas.Text.StepFilter,
  Atlas.Core.Settings.Reassigned,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Tracker.QueryTest,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.ToolCheck,
  Atlas.Core.Vcs.ServerAccess,
  Atlas.Core.Vcs.ServerCheck,
  Atlas.Core.Vcs.BranchPlan,
  Atlas.Core.Tracker.Workflow,
  Atlas.UI.Tracker.ValueBox,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Settings.Group,
  Atlas.UI.Strings,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol,
  Atlas.UI.EditorToolbar.Customize;

type
  /// <summary>Auswahlliste, die Einträge und Auswahl ohne Fensterhandle hält: Die IDE erzeugt und lädt die
  /// Optionsseiten, bevor sie ein übergeordnetes Fenster haben; Items.Add bräuchte dann schon eins.</summary>
  TAtlasChoiceBox = class(TComboBox)
  private
    FChoices: TArray<string>;
    FChoice: Integer;
    function GetChoice: Integer;
    procedure SetChoice(AValue: Integer);
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetChoices(const AItems: array of string);
    /// <summary>Gewählter Eintrag, -1 = keiner; gilt auch ohne Fenster.</summary>
    property Choice: Integer read GetChoice write SetChoice;
  end;

  /// <summary>Zeile der Optionsseite (Beschriftung und Eingabefeld): zeichnet nichts selbst, der
  /// Hintergrund des Reiters scheint durch.</summary>
  TAtlasSettingsRow = class(TWinControl)
  public
    constructor Create(AOwner: TComponent); override;
  end;

  /// <summary>Import (#723): AProfile True = erst ein eingebautes Profil wählen. True, wenn AResult gilt (die
  /// IDE hat schon gespeichert).</summary>
  TAtlasSettingsImportEvent = reference to function(const ACurrent: TAtlasPluginSettings; AProfile: Boolean;
    out AResult: TAtlasPluginSettings): Boolean;
  /// <summary>„Alles zurücksetzen“ (#723) mit Rückfrage; True, wenn AResult gilt.</summary>
  TAtlasSettingsResetEvent = reference to function(const ACurrent: TAtlasPluginSettings;
    out AResult: TAtlasPluginSettings): Boolean;

  /// <summary>Name eines Layouts der Willkommensseite erfragen (#767); False = abgebrochen.</summary>
  TAtlasSettingsAskName = reference to function(const APrompt: string; var AName: string): Boolean;
  /// <summary>Meldung (AQuestion False) oder Rückfrage mit Ja/Nein; True = Ja bzw. gelesen.</summary>
  TAtlasSettingsConfirm = reference to function(const AText: string; AQuestion: Boolean): Boolean;

  /// <summary>Zustand des Tokens einer Tracker-Verbindung (#1260), ohne Netz.</summary>
  TAtlasTrackerStateEvent = reference to function(const AConnection: TAtlasTrackerConnection): TAtlasTrackerTokenStatus;
  /// <summary>Knopf an einer Tracker-Verbindung (#1260): Token hinterlegen, prüfen, entfernen.</summary>
  TAtlasTrackerConnectionEvent = reference to procedure(const AConnection: TAtlasTrackerConnection);
  /// <summary>„Hinzufügen …“ der Tabelle Projekte (#1261): .dproj bzw. .groupproj (AFolder False) oder Ordner
  /// wählen; False bei Abbruch.</summary>
  TAtlasTrackerBrowseEvent = reference to function(AFolder: Boolean; out APath: string): Boolean;
  TAtlasQueryTestDone = reference to procedure(const AResult: TAtlasTrackerQueryTestResult);
  /// <summary>„Testen“ im Dialog „Abfrage bearbeiten“ (#1263): ATarget (Abfrage, Projekt, Sprache) über
  /// AConnection im Hintergrund abfragen und ADone im Hauptthread aufrufen.</summary>
  TAtlasQueryTestEvent = reference to procedure(const AConnection: TAtlasTrackerConnection;
    const ATarget: TAtlasTrackerTarget; const ADone: TAtlasQueryTestDone);
  /// <summary>„Bearbeiten …“ der Tabelle Abfragen (#1263): AQuery im Dialog ändern; True bei OK. ATaken: Namen der
  /// übrigen Abfragen.</summary>
  TAtlasTrackerQueryEditEvent = reference to function(var AQuery: TAtlasTrackerQuery;
    const AConnections: TArray<TAtlasTrackerConnection>; const ATaken: TArray<string>): Boolean;
  /// <summary>Fundort von git bzw. svn für den eingetragenen Pfad APath (#1285), nur Dateiprüfung, kein Prozess.
  /// </summary>
  TAtlasVcsLocateEvent = reference to function(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation;
  /// <summary>„Prüfen“ (#1285) für git bzw. svn unter APath im Hintergrund; das Ergebnis meldet VcsCheckDone.
  /// </summary>
  TAtlasVcsCheckEvent = reference to procedure(AKind: TAtlasVcsKind; const APath: string);
  /// <summary>Tabelle „Server“ (#1287): AFolder prüfen; das Ergebnis meldet VcsServerDone.</summary>
  TAtlasVcsServerCheckEvent = reference to procedure(const AFolder: string);
  /// <summary>„Anmelden …“ für ACheck; True, wenn die Konsole offen ist (nach dem Schließen prüft der Aufrufer
  /// erneut und meldet VcsServerDone).</summary>
  TAtlasVcsServerLoginEvent = reference to function(const AFolder: string; const ACheck: TAtlasVcsServerCheck):
    Boolean;

  /// <summary>Zeile der Tabelle „Server“: Projekt (Anzeige), Ordner und letzter Zustand.</summary>
  TAtlasVcsServerRow = record
    Name: string;
    Folder: string;
    Check: TAtlasVcsServerCheck;
    Checking: Boolean;
  end;
  /// <summary>„Werte vom Tracker laden“ (#1266) für AConnection mit dem Zustandsfeld AStateField; das Ergebnis meldet
  /// TrackerValuesDone.</summary>
  TAtlasTrackerValuesEvent = reference to procedure(const AConnection: TAtlasTrackerConnection;
    const AStateField: string);

  /// <summary>Seite eines Knotens im Baum (#890): der Bereich selbst (Node leer) oder ein Unterpunkt.</summary>
  TAtlasSettingsNodePage = record
    Sheet: TTabSheet;
    Box: TScrollBox;
    /// <summary>Index des Bereichs in FSheets.</summary>
    Area: Integer;
    /// <summary>Id aus x-nodes; leer = Hauptknoten des Bereichs.</summary>
    Node: string;
    Caption: string;
    /// <summary>Grund einer Sperre durch einen Hauptschalter auf einer anderen Seite.</summary>
    Banner: TLabel;
    /// <summary>Im Baum grau: nichts auf der Seite wirkt (aus oder gesperrt).</summary>
    Gray: Boolean;
  end;

  TAtlasSettingsPage = class(TFrame)
  private
    FPages: TPageControl;
    /// <summary>Bereiche und ihre Unterpunkte als Baum links (#890; vorher eine Liste).</summary>
    FTree: TTreeView;
    FSheet: TTabSheet;
    /// <summary>Rollbarer Inhalt des aktuellen Reiters; nimmt die Elemente auf.</summary>
    FContent: TScrollBox;
    // Reiter hängen erst mit dem Fensterhandle am PageControl (CreateWnd): Die IDE und die Tests
    // erzeugen die Seite, bevor sie ein übergeordnetes Fenster hat.
    FSheets: TArray<TTabSheet>;
    /// <summary>Rollbarer Inhalt je Bereich, gleicher Index wie FSheets.</summary>
    FBoxes: TArray<TScrollBox>;
    FEnabled: TCheckBox;
    FServerPath: TEdit;
    FServerBrowse: TButton;
    FServerStatus: TLabel;
    FServerVersion: TLabel;
    FSymbol: TAtlasSymbolImage;
    FOnServerVersion: TFunc<string, string>;
    FDefaultServerPath: string;
    FRowsLabel: TLabel;
    FRows: TEdit;
    FRowsUpDown: TUpDown;
    FPanelCollapsed: TCheckBox;
    FSelectionMarker: TCheckBox;
    FAutoParentheses: TCheckBox;
    FFixCase: TCheckBox;
    // ARG-046 (#227): Commit-Zeichen, uses, Parameter-Hint, Verzögerung, automatische Breite.
    FCommitChars: TCheckBox;
    FAutoUses: TCheckBox;
    FParameterHints: TCheckBox;
    // Platzhalter von Format im Parameter-Hint (#451).
    FFormatPlaceholders: TCheckBox;
    FOpenDelay: TEdit;
    FAutoWidth: TCheckBox;
    FFilterChips: TCheckBox;
    FLearning: TCheckBox;
    FGroupInherited: TCheckBox;
    FCompletionVariantBranch: TCheckBox;
    /// <summary>Listenmodus beim Tippen und sein Geltungsbereich (#497).</summary>
    FListMode: TAtlasChoiceBox;
    FListScope: TAtlasChoiceBox;
    FPreview: TCheckBox;
    FHoverTooltip: TCheckBox;
    FXmlDocExpand: TAtlasChoiceBox;
    FXmlDocMaxLines: TEdit;
    FHangThreshold: TEdit;
    FHangHint: TCheckBox;
    FProviderTimeLimit: TEdit;
    FFuseList: TListBox;
    FFuseEnableSelected: TButton;
    FFuseEnableAll: TButton;
    FReloadExternal: TCheckBox;
    FPairColors: TCheckBox;
    FInactiveDim: TCheckBox;
    FOpenForEdits: TCheckBox;
    FInlayHints: TCheckBox;
    /// <summary>Typmarken von Inline-Variablen (#453).</summary>
    FInlayTypeHints: TCheckBox;
    /// <summary>Include-Symbole hinter {$I} (#860).</summary>
    FInlayDefineHints: TCheckBox;
    /// <summary>Codes von Steuerzeichen wie ^C (#862).</summary>
    FInlayCharHints: TCheckBox;
    /// <summary>Marken „ohne Self“ (#686).</summary>
    FInlayMethodHints: TCheckBox;
    /// <summary>Blockende-Beschriftungen (#620).</summary>
    FBlockEndLabels: TCheckBox;
    FBlockEndLabelsMinLines: TEdit;
    FDimUnusedUses: TCheckBox;
    FRecursionMarkers: TCheckBox;
    FRecursionMarkersDepth: TEdit;
    /// <summary>Fehlertext am Zeilenende (#509): aus, nur Fehler, Fehler und Warnungen, alle.</summary>
    FInlineDiagnostics: TAtlasChoiceBox;
    FNotes: TCheckBox;
    FBookmarksNamed: TCheckBox;
    FBookmarksShared: TCheckBox;
    FQuickBookmarks: TCheckBox;
    FQuickBookmarksGutter: TCheckBox;
    FQuickBookmarksGutterClick: TCheckBox;
    FQuickBookmarksNumberedKeys: TCheckBox;
    FQuickBookmarkKey: TEdit;
    FQuickBookmarkChordWait: TEdit;
    FQuickBookmarksScope: TAtlasChoiceBox;
    FQuickBookmarksImportIde: TCheckBox;
    FCodeLensTestUnit: TCheckBox;
    /// <summary>Code Lens mit Code-Metriken (#66).</summary>
    FCodeLensMetrics: TCheckBox;
    FMetrics: TCheckBox;
    /// <summary>Code Lens „Test ausführen“ (#69, codeLens.tests).</summary>
    FCodeLensTests: TCheckBox;
    /// <summary>Befehl in der Befehlspalette (#68).</summary>
    FTodoList: TCheckBox;
    /// <summary>Befehl in der Befehlspalette (#97).</summary>
    FBaselineUpdate: TCheckBox;
    /// <summary>Befehl in der Befehlspalette (#66).</summary>
    FMetricsReport: TCheckBox;
    /// <summary>Befehle in der Befehlspalette (#309).</summary>
    FDfmPropertyRules: TCheckBox;
    FPairGuides: TCheckBox;
    FPairOwners: TCheckBox;
    FPairGuideWidth: TEdit;
    FPairGuideOpacity: TEdit;
    // Eigene Paarfarben je Thema, eine Fläche je Tiefe.
    FLightSwatches: array[0..4] of TShape;
    FDarkSwatches: array[0..4] of TShape;
    FProblems: TCheckBox;
    FProblemsList: TCheckBox;
    /// <summary>Zähler in der Statusleiste (#509).</summary>
    FProblemsStatusCounter: TCheckBox;
    FStatusField: TCheckBox;
    FDiagnosticMode: TCheckBox;
    /// <summary>„Prozesse am Projekt…“ (#62).</summary>
    FDiagnosticsProcesses: TCheckBox;
    // Architekturübersicht (#1118).
    FArchitecture: TCheckBox;
    FArchitectureScope: TAtlasChoiceBox;
    FArchitectureLibrary: TCheckBox;
    FArchitectureCentral: TEdit;
    FSetupChecklist: TCheckBox;
    FShortcutTips: TCheckBox;
    FShortcutTipsScope: TAtlasChoiceBox;
    // Benachrichtigungszentrale (#601); FNotificationsSpec hält notifications.sources, die beiden Auswahllisten
    // zeigen und ändern das Verhalten der gewählten Quelle.
    FNotifications: TCheckBox;
    FNotificationsMax: TEdit;
    FNotificationSource: TAtlasChoiceBox;
    FNotificationMode: TAtlasChoiceBox;
    FNotificationsSpec: string;
    FNotificationsKey: TEdit;
    FStatusSummary: TCheckBox;
    FStatusToggles: TAtlasChoiceBox;
    FIndexProgress: TAtlasChoiceBox;
    FStatusHidden: TEdit;
    FIndexGroup: TCheckBox;
    FIndexSearch: TCheckBox;
    FIndexLibrary: TCheckBox;
    FIndexUsages: TCheckBox;
    FMemoryBudget: TEdit;
    FIndexInfo: TLabel;
    FIndexRefresh: TButton;
    FIndexRebuild: TButton;
    FIndexClear: TButton;
    FOnIndexMetrics: TProc;
    FOnIndexRebuild: TProc;
    FOnIndexClear: TProc;
    /// <summary>Ein Befehl des Index läuft; Antwort über IndexAnswered (#874).</summary>
    FIndexBusy: Boolean;
    FConfirmClear: TFunc<Boolean>;
    FAfterSave: TAtlasChoiceBox;
    FCheckDelay: TEdit;
    FCheckMax: TEdit;
    FMcpBuild: TCheckBox;
    /// <summary>Beim Öffnen bauen (build.onOpen*): eine Auswahl „nicht bauen / Syntaxprüfung / Compilieren /
    /// Erzeugen“, Umfang in einer Gruppe, Wartezeit und ausgeschlossene Projekte.</summary>
    FOpenBuild: TAtlasChoiceBox;
    FOpenBuildScope: TAtlasChoiceBox;
    FOpenBuildDelay: TEdit;
    FOpenBuildExclude: TEdit;
    /// <summary>Projektaufgaben (#900, tasks.*): Schalter, Befunde, vor dem Build (aus / warnen / abbrechen),
    /// speichern, Prüfungen gleichzeitig, nur Befunde in der Ausgabe.</summary>
    FTasksEnabled: TCheckBox;
    FTasksProblemsFromOutput: TCheckBox;
    FTasksBeforeBuild: TAtlasChoiceBox;
    FTasksSaveBeforeRun: TCheckBox;
    FTasksRunChecksParallel: TCheckBox;
    FTasksOnlyFindings: TCheckBox;
    /// <summary>DUnitX-Tests ausführen (#69): Befehle, vorher bauen, nach dem Build; Build ohne Hinweise (#530).
    /// </summary>
    FTestRun: TCheckBox;
    FTestsBuildFirst: TCheckBox;
    FTestsAfterBuild: TCheckBox;
    FBuildZeroHints: TCheckBox;
    /// <summary>Kosten einer interface-Änderung in der Statusleiste (#554).</summary>
    FShowInterfaceCost: TCheckBox;
    /// <summary>Schranke für Hinweise und Warnungen (#530): Zusammenfassung und Codes, die als Fehler zählen.
    /// </summary>
    FBuildSummary: TCheckBox;
    FBuildWarningsAsErrors: TEdit;
    /// <summary>Wirksame Compiler-Schalter (#558): Fenster und Feld in der Statusleiste.</summary>
    FBuildCompilerSwitches: TCheckBox;
    FBuildSwitchesInStatusBar: TCheckBox;
    /// <summary>Prüfung vor dem Compile (#529): build.gate (gilt auch für den Release-Wächter) und ihr Zeitlimit.
    /// </summary>
    FBuildGate: TAtlasChoiceBox;
    FBuildGateTimeout: TEdit;
    /// <summary>Release-Build-Wächter (#533): Schalter, weitere Release-Konfigurationen und je Prüfung ein Haken
    /// (ohne Sollwert) bzw. eine Auswahl „nicht prüfen / Soll aus / Soll an“.</summary>
    FReleaseGuard: TCheckBox;
    FReleaseConfigs: TEdit;
    FReleaseCheckBoxes: array[TAtlasReleaseCheck] of TCheckBox;
    FReleaseCheckChoices: array[TAtlasReleaseCheck] of TAtlasChoiceBox;
    /// <summary>Startprofile (#575): Befehl, Statusfeld.</summary>
    FStartProfiles: TCheckBox;
    FStartProfilesStatusField: TCheckBox;
    /// <summary>Einzelnen Test debuggen (#585): Befehle und Marke, Haltepunkt am Anfang der Methode.</summary>
    FTestDebug: TCheckBox;
    FTestBreakAtStart: TCheckBox;
    FDebugHoverValues: TCheckBox;
    /// <summary>Visualisierer für häufige Typen (#835).</summary>
    FDebugVisualizers: TCheckBox;
    FDebugVisualizerKinds: array[TAtlasVisualizerKind] of TCheckBox;
    FDebugVisualizerNameFields: TEdit;
    FDebugVisualizerMaxLength: TEdit;
    FDebugVisualizerTimeout: TEdit;
    FDebugVisualizerMaxImagePixels: TEdit;
    FDebugVisualizerEvaluation: TAtlasChoiceBox;
    /// <summary>Eigene Wertdarstellungen (#854).</summary>
    FDebugDisplayRules: TCheckBox;
    FDebugDisplayRulesAllowCalls: TCheckBox;
    /// <summary>Gezielt hineinspringen (#836).</summary>
    FDebugStepIntoTarget: TCheckBox;
    FDebugStepFilters: TCheckBox;
    FDebugStepFilterKinds: array[TStepFilterKind] of TCheckBox;
    FDebugStepFilterPatterns: TEdit;
    FDebugStepIntoTargetKey: TEdit;
    FDebugBreakOnNextEvent: TCheckBox;
    FDebugBreakOnNextEventExcluded: TEdit;
    FDebugExplainUnavailable: TCheckBox;
    FDebugCompletionInDialogs: TCheckBox;
    FDebugEvaluateWindow: TCheckBox;
    FDebugEvaluateReplaceCtrlF7: TCheckBox;
    FDebugExplainAccessViolation: TCheckBox;
    FDebugExplainAccessViolationAllowCalls: TCheckBox;
    FDebugExceptionHistory: TCheckBox;
    FDebugJustMyCode: TCheckBox;
    FDebugExceptionBanner: TCheckBox;
    FDebugExceptionBannerIgnoreAtLocation: TCheckBox;
    FDebugInlineValues: TCheckBox;
    FDebugInlineValuesPerLine: TEdit;
    FDebugOwnCodeFolders: TEdit;
    FActionsKey: TEdit;
    FExpandKey: TEdit;
    FShrinkKey: TEdit;
    FImplementationKey: TEdit;
    FTypeDefinitionKey: TEdit;
    FMethodToggle: TCheckBox;
    FMethodToggleUpKey: TEdit;
    FMethodToggleDownKey: TEdit;
    FTestUnitKey: TEdit;
    FGotoInterfaceKey: TEdit;
    FGotoImplementationKey: TEdit;
    FNavHistory: TCheckBox;
    FNavBackKey: TEdit;
    FNavForwardKey: TEdit;
    FLastEditKey: TEdit;
    FPeek: TCheckBox;
    FPeekHeightLines: TEdit;
    FPeekShowImplementation: TCheckBox;
    FDataFlow: TCheckBox;
    FDataFlowMaxDepth: TEdit;
    FDataFlowExcludeTests: TCheckBox;
    FPeekDefinitionKey: TEdit;
    FPeekReferencesKey: TEdit;
    FReferencesInferred: TCheckBox;
    FReferencesTextMatches: TCheckBox;
    FCallHierarchyDiagram: TCheckBox;
    FImpact: TCheckBox;
    FImpactDepth: TEdit;
    FOutline: TCheckBox;
    FOutlineAlphabetical: TCheckBox;
    FOutlineFollowCursor: TCheckBox;
    FOutlineConditions: TCheckBox;
    FBreadcrumbs: TCheckBox;
    FBreadcrumbsShowUnit: TCheckBox;
    FBreadcrumbsIdeColors: TCheckBox;
    FBreadcrumbsHideIdeToolbar: TCheckBox;
    // Mitlaufender Kopf (#506).
    FStickyScroll: TCheckBox;
    FStickyScrollMaxLines: TEdit;
    FMinimap: TCheckBox;
    FMinimapRender: TAtlasChoiceBox;
    FMinimapWidth: TEdit;
    FMinimapScale: TEdit;
    FMinimapMaxColumn: TEdit;
    FMinimapSide: TAtlasChoiceBox;
    FMinimapShowSlider: TAtlasChoiceBox;
    FMinimapSectionHeaders: TCheckBox;
    FMinimapHighlightMethod: TCheckBox;
    FMinimapMarkers: TCheckBox;
    FMinimapClickJumps: TCheckBox;
    FBreadcrumbsKey: TEdit;
    FEditorToolbar: TCheckBox;
    FEditorToolbarPosition: TAtlasChoiceBox;
    FEditorToolbarItems: TEdit;
    FEditorToolbarReturnButton: TCheckBox;
    FEditorToolbarLabels: TCheckBox;
    FEditorToolbarCustomize: TButton;
    FEditorStatusBar: TCheckBox;
    FEditorStatusBarItems: TEdit;
    FOnToolbarCommands: TFunc<TArray<TAtlasToolbarCommandInfo>>;
    FGitGutter: TCheckBox;
    FGitBlame: TCheckBox;
    FGutterColumn: TCheckBox;
    FGutterColumnProblems: TCheckBox;
    FGutterColumnCodeActions: TCheckBox;
    FGutterColumnOverrides: TCheckBox;
    FSelectionMatches: TCheckBox;
    FSelectionMatchesMinLength: TEdit;
    FSelectionMatchesCaseSensitive: TCheckBox;
    FSelectionMatchesWholeWord: TCheckBox;
    FSelectionMatchesNavigateF3: TCheckBox;
    FSelectionMatchesMaxMatches: TEdit;
    FExitPoints: TCheckBox;
    FExitPointsExceptions: TCheckBox;
    FExitPointsLoops: TCheckBox;
    FExitPointsBadge: TCheckBox;
    FReassigned: TCheckBox;
    FReassignedTargets: array[TAtlasReassignedTarget] of TCheckBox;
    FReassignedStyle: TAtlasChoiceBox;
    FReassignedColor: TEdit;
    FExpressionType: TCheckBox;
    FExpressionTypeConversions: TCheckBox;
    FExpressionTypeConstValue: TCheckBox;
    FExpressionTypeKey: TEdit;
    FMethodPlacement: TAtlasChoiceBox;
    FNextChangeKey: TEdit;
    FPreviousChangeKey: TEdit;
    FOverviewRuler: TCheckBox;
    FOverviewKinds: array[TAtlasOverviewKind] of TCheckBox;
    FJumpToMatch: TCheckBox;
    FJumpToMatchKey: TEdit;
    FJumpToMatchSelectKey: TEdit;
    FMoveLines: TCheckBox;
    FMoveLinesUpKey: TEdit;
    FMoveLinesDownKey: TEdit;
    FDuplicateLinesUpKey: TEdit;
    FDuplicateLinesDownKey: TEdit;
    FToggleBlockComment: TCheckBox;
    FToggleBlockCommentKey: TEdit;
    FToggleBlockCommentStyle: TAtlasChoiceBox;
    FToggleBlockCommentFallback: TAtlasChoiceBox;
    FToggleBlockCommentOwnLines: TCheckBox;
    FToggleBlockCommentScope: TAtlasChoiceBox;
    FNewLineAround: TCheckBox;
    FNewLineBelowKey: TEdit;
    FNewLineAboveKey: TEdit;
    FNewLineAroundStatementAware: TCheckBox;
    FUnwrap: TCheckBox;
    FUnwrapKey: TEdit;
    FSafeDelete: TCheckBox;
    FSafeDeleteKey: TEdit;
    FContinueComments: TCheckBox;
    FContinueCommentsLineComments: TCheckBox;
    FContinueCommentsLists: TCheckBox;
    FContinueCommentsBlockPrefix: TEdit;
    FWrapSelection: TCheckBox;
    FWrapSelectionChars: TEdit;
    FCompleteStatement: TCheckBox;
    FCompleteStatementKey: TEdit;
    FCompleteStatementBeginEnd: TAtlasChoiceBox;
    FCompleteStatementTryKind: TAtlasChoiceBox;
    FCompleteStatementMethodBody: TCheckBox;
    FFormatCode: TCheckBox;
    FFormatCodeKey: TEdit;
    FContinuePattern: TCheckBox;
    FContinuePatternMinLines: TEdit;
    // Mehrere Einfügemarken (#589).
    FMultiCursor: TCheckBox;
    FLinkedEditing: TCheckBox;
    FSmartPaste: TAtlasChoiceBox;
    FMultiCursorModifier: TAtlasChoiceBox;
    FMultiCursorNextKey: TEdit;
    FMultiCursorSkipKey: TEdit;
    FMultiCursorLineEndsKey: TEdit;
    FMultiCursorAboveKey: TEdit;
    FMultiCursorBelowKey: TEdit;
    FBookmarkKey: TEdit;
    FNextBookmarkKey: TEdit;
    FPreviousBookmarkKey: TEdit;
    /// <summary>„Element ausblenden …“ (#628).</summary>
    FHideElementKey: TEdit;
    /// <summary>Nächster/vorheriger Befund (#509).</summary>
    FNextProblemKey: TEdit;
    FPreviousProblemKey: TEdit;
    FProblemsWindowKey: TEdit;
    FCreateIssueKey: TEdit;
    /// <summary>Fenster „Atlas-Prüfung“, laufende Prüfung und Aktionszeile im Hover (#909).</summary>
    FProblemsWindow: TCheckBox;
    FProblemsWindowScope: TAtlasChoiceBox;
    FProblemsWindowGroupBy: TAtlasChoiceBox;
    FProblemsWindowCompiler: TCheckBox;
    FProblemsWindowFollowCursor: TCheckBox;
    FProblemsWindowOpenFirst: TCheckBox;
    FProblemsWindowClosedUnits: TAtlasChoiceBox;
    FProblemsWindowShowCleanActive: TCheckBox;
    FProblemsLive: TCheckBox;
    FProblemsCompilerMerge: TAtlasChoiceBox;
    FProblemsShowCompilerCode: TCheckBox;
    FHoverProblemActions: TCheckBox;
    /// <summary>Bereich Prüfregeln (#909): Index in FSheets. Die Regeln selbst stehen in den Dialogen der
    /// Einstellungsdateien (Projekt und global); hier Prüffenster, Compiler vorab, Profile und Baseline.</summary>
    FRulesArea: Integer;
    FOnRulesProject: TProc;
    FOnRulesGlobal: TProc;
    FOnBaselineInfo: TFunc<string>;
    FOnBaselineUpdate: TFunc<string>;
    FOnBaselineDelete: TFunc<string>;
    FBaselineInfo: TLabel;
    FRulesProject: TButton;
    FRulesGlobal: TButton;
    FBaselineUpdateButton: TButton;
    FBaselineDelete: TButton;
    FUndoKey: TEdit;
    FRedoKey: TEdit;
    FEditorKeysPriority: TCheckBox;
    FSlashCommands: TCheckBox;
    /// <summary>Erzeugen-Menü (#719).</summary>
    FGenerateMenu: TCheckBox;
    FGenerateMenuKey: TEdit;
    FGenerateMenuGroups: TEdit;
    FGenerateMenuHidden: TEdit;
    FGenerateMenuRecentFirst: TCheckBox;
    FGenerateMenuShowCommandNames: TCheckBox;
    FSnippets: TCheckBox;
    FImportIdeTemplates: TCheckBox;
    // Projektdatei .atlas (#486): Schalter, Anzeige der Werte „aus .atlas“, Öffnen; Hinweis bei den Vorlagen.
    FTeamFile: TCheckBox;
    FTeamFileInfo: TLabel;
    FTeamFileOpen: TButton;
    FTeamSnippets: TLabel;
    FOnTeamFile: TFunc<TAtlasTeamSettings>;
    FOnOpenTeamFile: TProc;
    FSafeAsk: TCheckBox;
    FSafeAuto: TCheckBox;
    FSafeKey: TAtlasChoiceBox;
    FSafeTimeout: TEdit;
    FSafeHistory: TEdit;
    FUndoEnabled: TCheckBox;
    FUndoDepth: TEdit;
    FUndoPersist: TCheckBox;
    FUndoMaxSize: TEdit;
    FUndoOnConflict: TAtlasChoiceBox;
    FUndoNewFiles: TAtlasChoiceBox;
    FUpdatesCheck: TCheckBox;
    FBugReportAnonymize: TCheckBox;
    // Units suchen (#777).
    FUnitSearchEnabled: TCheckBox;
    FUnitSearchReplace: TCheckBox;
    FUnitSearchReplaceUseUnit: TCheckBox;
    FUnitSearchReplaceForms: TCheckBox;
    FUnitSearchPathStyle: TAtlasChoiceBox;
    FUnitSearchGroupBy: TAtlasChoiceBox;
    FUnitSearchRememberCollapsed: TCheckBox;
    FUnitSearchFilters: TCheckBox;
    FUnitSearchDefaultScope: TAtlasChoiceBox;
    FUnitSearchFilterSyntax: TCheckBox;
    FUnitSearchPreview: TCheckBox;
    FUnitSearchPreviewForm: TCheckBox;
    FUnitSearchPreviewUsedBy: TCheckBox;
    FUnitSearchPreviewAutoCollapse: TCheckBox;
    FUnitSearchMultiSelect: TCheckBox;
    FUnitSearchActions: TCheckBox;
    FUnitSearchAddUses: TCheckBox;
    FUnitSearchKey: TEdit;
    FQuickOpen: TCheckBox;
    FQuickOpenLibrary: TCheckBox;
    FQuickOpenKey: TEdit;
    FSearchReplace: TCheckBox;
    FSearchMessages: TCheckBox;
    FSearchReplaceBar: TCheckBox;
    FSearchRegex: TCheckBox;
    FSearchHistory: TEdit;
    FSearchMultiFile: TCheckBox;
    FWelcomeEnabled: TCheckBox;
    FWelcomeOpenOnStart: TCheckBox;
    FWelcomeOpenWhenNoProject: TCheckBox;
    // Freies Layout (#767): Schalter, Spalten, aktives Layout und dessen Verwaltung. FPageLayouts ist das
    // Modell der Seite; erst OK schreibt es in die Einstellungen.
    FWelcomeCustomLayout: TCheckBox;
    FWelcomeColumns: TEdit;
    FWelcomeActiveLayout: TAtlasChoiceBox;
    FWelcomeLayoutNew: TButton;
    FWelcomeLayoutRename: TButton;
    FWelcomeLayoutDelete: TButton;
    FPageLayouts: TAtlasWelcomeLayouts;
    FOnAskLayoutName: TAtlasSettingsAskName;
    FOnConfirmLayout: TAtlasSettingsConfirm;
    FWelcomeHeader: TCheckBox;
    FWelcomeGreeting: TCheckBox;
    FWelcomeSearch: TCheckBox;
    FWelcomeSearchSymbols: TCheckBox;
    FWelcomeSearchKey: TEdit;
    FWelcomeWhatsNew: TAtlasChoiceBox;
    FWelcomeContinue: TCheckBox;
    FWelcomeContinueCount: TEdit;
    FWelcomeContinueIncoming: TCheckBox;
    FWelcomeContinueFetch: TCheckBox;
    FWelcomeSaved: TCheckBox;
    FWelcomeProjects: TCheckBox;
    FWelcomeMaxProjects: TEdit;
    FWelcomeRefreshVcs: TCheckBox;
    FWelcomeTrends: TCheckBox;
    FWelcomeTrendsPoints: TEdit;
    FWelcomeTrendsSeries: array[TAtlasTrendSeries] of TCheckBox;
    FWelcomeTests: TCheckBox;
    FWelcomeTestsMaxFailures: TEdit;
    FWelcomeTestsCi: TCheckBox;
    FWelcomeTestsCiProvider: TAtlasChoiceBox;
    FWelcomeTestsCiInterval: TEdit;
    FWelcomeTestsCiNotify: TCheckBox;
    FCiLogin: TCheckBox;
    FWelcomeIssues: TCheckBox;
    FIssuesTracker: TAtlasChoiceBox;
    FIssuesStart: TAtlasChoiceBox;
    FIssuesBranchPattern: TEdit;
    FIssuesBranchBase: TEdit;
    FIssuesCommitPattern: TEdit;
    FTrackerLogin: TCheckBox;
    FIssuesPreview: TCheckBox;
    FIssuesPreviewComments: TCheckBox;
    FIssuesCodeLinks: TCheckBox;
    FIssuesBlameLinks: TCheckBox;
    FIssuesBlameMaxRevisions: TEdit;
    // Zustand im Tracker beim Beginnen und Beenden (#1266).
    FIssuesSyncState: TCheckBox;
    FIssuesStateField: TAtlasValueBox;
    FIssuesAssigneeField: TAtlasValueBox;
    FIssuesStartState: TAtlasValueBox;
    FIssuesAssignOnStart: TCheckBox;
    FIssuesStartComment: TEdit;
    FIssuesEndStates: TEdit;
    FIssuesEndComment: TEdit;
    FIssuesLoadValues: TButton;
    FIssuesValuesNote: TLabel;
    // Zeiterfassung (#1267).
    FIssuesTimeTracking: TCheckBox;
    FIssuesIdleMinutes: TEdit;
    FIssuesTimeRounding: TEdit;
    FIssuesPreviewChecklists: TCheckBox;
    FIssuesChecklistStatus: TCheckBox;
    FWelcomeIssuesLink: TButton;
    // Tracker-Verbindungen (#1260): Tabelle, Felder der gewählten Zeile, Knöpfe.
    FIssuesConnections: TListView;
    FIssuesConnectionName: TEdit;
    FIssuesConnectionProvider: TAtlasChoiceBox;
    FIssuesConnectionUrl: TEdit;
    FIssuesConnectionNote: TLabel;
    FIssuesConnectionAdd: TButton;
    FIssuesConnectionRemove: TButton;
    FIssuesConnectionToken: TButton;
    FIssuesConnectionCheck: TButton;
    // Werte der gewählten Verbindung für Zustand und Zuständigkeit (#1266); leer = globale Einstellung.
    FIssuesConnectionStateField: TAtlasValueBox;
    FIssuesConnectionAssigneeField: TAtlasValueBox;
    FIssuesConnectionStartState: TAtlasValueBox;
    FIssuesConnectionEndStates: TEdit;
    FOnTrackerValues: TAtlasTrackerValuesEvent;
    /// <summary>Persönliche Verbindungen, wie die Seite sie zeigt; gespeichert werden die mit Adresse.</summary>
    FTrackerConnections: TArray<TAtlasTrackerConnection>;
    /// <summary>Verbindung aus der .atlas des aktiven Projekts (schreibgeschützt), hinter den persönlichen.</summary>
    FTrackerTeam: TArray<TAtlasTrackerConnection>;
    FTrackerProviderNames: TArray<string>;
    FTrackerProviderCaptions: TArray<string>;
    /// <summary>Server (CredentialTarget), deren Prüfung läuft.</summary>
    FTrackerChecking: TArray<string>;
    /// <summary>Gewählte Zeile; -1 = keine.</summary>
    FTrackerSelected: Integer;
    /// <summary>Die Seite füllt die Felder selbst: OnChange übernimmt nichts.</summary>
    FTrackerFilling: Boolean;
    FOnTrackerState: TAtlasTrackerStateEvent;
    FOnTrackerToken: TAtlasTrackerConnectionEvent;
    FOnTrackerCheck: TAtlasTrackerConnectionEvent;
    FOnTrackerRemove: TAtlasTrackerConnectionEvent;
    FOnTrackerTeam: TFunc<TArray<TAtlasTrackerConnection>>;
    // Zuordnung Delphi-Projekt → Tracker-Projekt (#1261): Tabelle, Felder der gewählten Zeile, Knöpfe.
    FIssuesProjects: TListView;
    FIssuesProjectMatch: TEdit;
    FIssuesProjectConnection: TAtlasChoiceBox;
    FIssuesProjectProject: TEdit;
    FIssuesProjectNote: TLabel;
    FIssuesProjectAddCurrent: TButton;
    FIssuesProjectAdd: TButton;
    FIssuesProjectRemove: TButton;
    FIssuesProjectAddMenu: TPopupMenu;
    /// <summary>Persönliche Zeilen, wie die Seite sie zeigt; gespeichert werden die mit Pfad und Verbindung.
    /// </summary>
    FTrackerProjects: TArray<TAtlasTrackerProjectMapping>;
    /// <summary>Aktives Projekt, geöffnete .groupproj und Zeile aus der .atlas (beim Aufbau der Tabelle).</summary>
    FTrackerContext: TAtlasTrackerProjectContext;
    /// <summary>Namen der Verbindungen in der Auswahl der Zeile.</summary>
    FTrackerProjectChoices: TArray<string>;
    FTrackerProjectSelected: Integer;
    FTrackerProjectFilling: Boolean;
    FOnTrackerContext: TFunc<TAtlasTrackerProjectContext>;
    FOnTrackerBrowse: TAtlasTrackerBrowseEvent;
    // Benannte Abfragen (#1262).
    FIssuesQueries: TListView;
    FIssuesQueryName: TEdit;
    FIssuesQueryText: TEdit;
    FIssuesQueryConnection: TAtlasChoiceBox;
    FIssuesQueryProject: TEdit;
    FIssuesQueryNote: TLabel;
    FIssuesQueryAdd: TButton;
    FIssuesQueryRemove: TButton;
    FIssuesQueryEdit: TButton;
    FOnTrackerQueryTest: TAtlasQueryTestEvent;
    FOnTrackerQueryEdit: TAtlasTrackerQueryEditEvent;
    FIssuesQueryPicker: TCheckBox;
    FIssuesCreate: TCheckBox;
    FIssuesCreateIncludeCode: TCheckBox;
    /// <summary>Zeilen, wie die Seite sie zeigt; gespeichert werden die mit Name und Abfrage.</summary>
    FTrackerQueries: TArray<TAtlasTrackerQuery>;
    FTrackerQuerySelected: Integer;
    FTrackerQueryFilling: Boolean;
    // Versionsverwaltung (#1285): Art, je Programm Pfad, „…“, „Prüfen“ und Zustand, Zeitlimit, aktuelles Projekt.
    FVcsProvider: TAtlasChoiceBox;
    FVcsPaths: array[TAtlasVcsKind] of TEdit;
    FVcsBrowse: array[TAtlasVcsKind] of TButton;
    FVcsCheck: array[TAtlasVcsKind] of TButton;
    FVcsStates: array[TAtlasVcsKind] of TLabel;
    FVcsTimeout: TEdit;
    FVcsBranchConfirm: TCheckBox;
    FVcsBranchSvnLocation: TEdit;
    FVcsBranchSvnSource: TAtlasChoiceBox;
    FVcsBranchSvnAfter: TAtlasChoiceBox;
    FVcsBranchSvnFolder: TEdit;
    FVcsBranchSvnMessage: TEdit;
    FVcsExternalsOnBranch: TAtlasChoiceBox;
    FVcsExternalsSuggest: TAtlasChoiceBox;
    FVcsExternalsRules: TMemo;
    FVcsExternalsRulesError: TLabel;
    FVcsExternalsShow: TCheckBox;
    FVcsExternalsUpdate: TAtlasChoiceBox;
    FVcsBranchGitBase: TAtlasChoiceBox;
    FVcsBranchGitPush: TAtlasChoiceBox;
    FVcsBranchGitUncommitted: TAtlasChoiceBox;
    FVcsBranchGitWorktree: TCheckBox;
    FVcsBranchGitWorktreeFolder: TEdit;
    FVcsProjectInfo: TLabel;
    FVcsLinkEditor: TButton;
    FVcsLinkWelcome: TButton;
    FVcsLinkIssues: TButton;
    /// <summary>„Aktuelles Projekt“ wurde schon abgefragt (einmal je Öffnen der Seite).</summary>
    FVcsProjectAsked: Boolean;
    FOnVcsLocate: TAtlasVcsLocateEvent;
    FOnVcsCheck: TAtlasVcsCheckEvent;
    FOnVcsProject: TProc;
    // Art und Hauptbranch je Projekt (#1286): Tabelle wie die Zuordnung auf der Seite Issue-Tracker.
    FVcsProjectList: TListView;
    FVcsProjectMatch: TEdit;
    FVcsProjectProvider: TAtlasChoiceBox;
    FVcsProjectMainBranch: TEdit;
    FVcsProjectNote: TLabel;
    FVcsProjectAddCurrent: TButton;
    FVcsProjectAdd: TButton;
    FVcsProjectRemove: TButton;
    FVcsProjectAddMenu: TPopupMenu;
    /// <summary>Persönliche Zeilen, wie die Seite sie zeigt; gespeichert werden die mit Pfad.</summary>
    FVcsProjects: TArray<TAtlasVcsProjectMapping>;
    /// <summary>Aktives Projekt, geöffnete .groupproj und Zeile aus der .atlas (beim Aufbau der Tabelle).</summary>
    FVcsContext: TAtlasVcsProjectContext;
    FVcsProjectSelected: Integer;
    FVcsProjectFilling: Boolean;
    /// <summary>Art der Arbeitskopie aus der letzten Abfrage „Aktuelles Projekt“ (für „Aktuelles Projekt
    /// hinzufügen“); None ohne.</summary>
    FVcsDetectedKind: TAtlasVcsKind;
    FVcsDetectedProject: string;
    FOnVcsContext: TFunc<TAtlasVcsProjectContext>;
    // Serverzugang (#1287): Zeilen aus aktuellem Projekt und Tabelle Projekte, Zustand nur aus der Sitzung.
    FVcsServerList: TListView;
    FVcsServerCheck: TButton;
    FVcsServerCheckAll: TButton;
    FVcsServerLogin: TButton;
    FVcsServerNote: TLabel;
    FVcsServerRows: TArray<TAtlasVcsServerRow>;
    FVcsServerSelected: Integer;
    /// <summary>Ordner aus „prüfen …“ der Willkommensseite, der nicht in der Tabelle Projekte steht.</summary>
    FVcsServerExtra: string;
    FOnVcsServerState: TFunc<string, TAtlasVcsServerCheck>;
    FOnVcsServerCheck: TAtlasVcsServerCheckEvent;
    FOnVcsServerLogin: TAtlasVcsServerLoginEvent;
    FWelcomeQuickActions: TCheckBox;
    FWelcomeQuickActionsItems: array[TAtlasQuickAction] of TCheckBox;
    FWelcomeQuickActionsConsole: TEdit;
    FWelcomeQuickActionsBuildKey: TEdit;
    FWelcomeQuickActionsTestKey: TEdit;
    FWelcomeUnsaved: TCheckBox;
    FWelcomeUnsavedMinAge: TEdit;
    FWelcomeUnsavedWarn: TEdit;
    FWelcomeUnsavedAlert: TEdit;
    FWelcomeUnsavedHideClean: TCheckBox;
    FWelcomeStatusTile: TCheckBox;
    FWelcomeStatusTileOnlyProblems: TCheckBox;
    FWelcomeDiscover: TCheckBox;
    FTipsUsageTracking: TCheckBox;
    FResetUsage: TButton;
    FUnblockTips: TButton;
    FOnResetUsage: TProc;
    FOnUnblockTips: TProc;
    FWelcomeHelp: TCheckBox;
    FWelcomeHelpReportUrl: TEdit;
    FWelcomeHelpReportFolder: TEdit;
    FWelcomeHelpFolderBrowse: TButton;
    FWelcomeProjectSetup: TCheckBox;
    FWelcomeNewFromTemplate: TCheckBox;
    FVersion: TLabel;
    FResetHistory: TButton;
    // Favoriten (#458): Schalter, Liste und Schlüssel je Zeile.
    FFavorites: TCheckBox;
    FFavoritesList: TListBox;
    FFavoritesRemove: TButton;
    FFavoritesRemoveAll: TButton;
    FFavoriteKeys: TArray<string>;
    FOnFavorites: TFunc<TArray<TAtlasFavorite>>;
    FOnRemoveFavorites: TProc<TArray<string>>;
    FResetWidths: TButton;
    FHangTest: TButton;
    FHangTestRow: TWinControl;
    FWidths: TAtlasPluginSettings;
    FNextTop: Integer;
    FOnResetHistory: TProc;
    /// <summary>Schlüssel und Steuerelement für Reveal (#628).</summary>
    FRevealKeys: TArray<string>;
    FRevealControls: TArray<TControl>;
    /// <summary>Reveal vor dem Fenster: folgt in CreateWnd.</summary>
    FPendingReveal: string;
    // Einstellungen übertragen (#723): Schalter, Knöpfe unten, Punkte an geänderten Werten.
    FSettingsExportImport: TCheckBox;
    FSettingsMarkModified: TCheckBox;
    FSettingsBackupBeforeImport: TCheckBox;
    FSettingsExportSecrets: TAtlasChoiceBox;
    FTransferBar: TWinControl;
    /// <summary>Hauptschalter der experimentellen Funktionen (#834), Hinweis darüber und Filter unten.</summary>
    FExperimentalEnabled: TCheckBox;
    FExperimentalBanner: TWinControl;
    FFilterRow: TWinControl;
    FFilter: TAtlasChoiceBox;
    FExportButton: TButton;
    FImportButton: TButton;
    FProfileButton: TButton;
    FResetPageButton: TButton;
    FResetAllButton: TButton;
    FMarks: TAtlasSettingsMarks;
    FCatalog: TAtlasSettingsCatalog;
    FOnExportSettings: TProc<TAtlasPluginSettings>;
    FOnImportSettings: TAtlasSettingsImportEvent;
    FOnResetAllSettings: TAtlasSettingsResetEvent;
    FGroups: TAtlasSettingsGroups;
    FNodePages: TArray<TAtlasSettingsNodePage>;
    FFrames: TArray<TAtlasSettingsGroup>;
    /// <summary>Rahmen „Funktionen in diesem Bereich“ auf den Hauptknoten.</summary>
    FOverviews: TArray<TAtlasSettingsGroup>;
    /// <summary>Zeile ohne eigene Einstellung → Element, zu dem sie gehört (Liste und Knöpfe einer Funktion).</summary>
    FAttached: TDictionary<TControl, TControl>;
    /// <summary>Von der Seite selbst abgeschaltet (Liste leer, kein Server); bleibt aus, auch ohne Sperre.</summary>
    FOwnOff: TList<TControl>;
    /// <summary>Durch einen Hauptschalter gesperrt.</summary>
    FLockedControls: TList<TControl>;
    /// <summary>Spiegel der Hauptschalter in der Übersicht und ihr Original, gleicher Index.</summary>
    FMirrors: TArray<TCheckBox>;
    FMirrored: TArray<TCheckBox>;
    FPlaceTop: Integer;
    FSyncing: Boolean;
    FFillingTree: Boolean;
    // Gewählte Seite und aufgeklappte Bereiche bis zum nächsten Öffnen (ohne verwaltete Typen: Leckmonitor).
    class var FLastPage: Integer;
    class var FExpandedAreas: set of Byte;
    class var FStateKnown: Boolean;
  private
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure TreeExpanded(Sender: TObject; Node: TTreeNode);
    procedure TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    /// <summary>ARow (ohne eigene Einstellung) gehört zur Funktion von AAnchor: gleicher Rahmen, gleiche Sperre.
    /// </summary>
    procedure Attach(ARow, AAnchor: TControl);
    /// <summary>Seite des Knotens ANode im Bereich AArea; legt sie bei Bedarf an.</summary>
    function AddNodePage(AArea: Integer; const ANode: string): Integer;
    procedure Place(AControl: TControl; AHolder: TWinControl);
    /// <summary>Verteilt die Zeilen aller Bereiche auf Knoten und Rahmen (aus dem Schema).</summary>
    procedure BuildNodes;
    procedure BuildArea(AArea: Integer);
    procedure AddOverview(AArea: Integer);
    procedure MirrorClick(Sender: TObject);
    procedure DetailsClick(Sender: TObject);
    function IsOverview(AFrame: TAtlasSettingsGroup): Boolean;
    function PageOf(AControl: TControl): Integer;
    function ActiveNode: Integer;
    procedure SelectPage(AIndex: Integer);
    function PageShown(AIndex: Integer): Boolean;
    procedure FillTree;
    procedure RefreshTree;
    function IsOn(const AName: string): Boolean;
    function LockOfName(const AName: string): TAtlasSettingsLock;
    function LockText(const ALock: TAtlasSettingsLock): string;
    procedure SetLocked(AControl: TControl; ALocked: Boolean);
    /// <summary>Statt Enabled := AValue: Eine Sperre durch den Hauptschalter bleibt bestehen.</summary>
    procedure Allow(AControl: TControl; AValue: Boolean);
    procedure ApplyLocks(AContainer: TWinControl; ALocked: Boolean; var AOutside: TArray<string>);
    function PageGray(AIndex: Integer): Boolean;
    procedure Bind(const AKey: string; AControl: TControl);
    procedure ApplyReveal(const AKey: string);
    function AddNodePageCaption(AArea: Integer; const ANode, ACaption: string): Integer;
    procedure AddRulePages;
    procedure AddRulesLinks;
    procedure SetOnBaselineInfo(const AValue: TFunc<string>);
    procedure RulesProjectClick(Sender: TObject);
    procedure RulesGlobalClick(Sender: TObject);
    procedure BaselineUpdateClick(Sender: TObject);
    procedure BaselineDeleteClick(Sender: TObject);
  protected
    procedure CreateWnd; override;
  private
    /// <summary>Neuer Reiter; die folgenden Add… setzen ihre Elemente darauf.</summary>
    procedure AddSheet(AId: TAtlasTextId);
    function AddCheck(const ACaption: string): TCheckBox;
    function AddPanel(AHeight: Integer): TWinControl;
    function AddNumber(const ACaption: string): TEdit;
    function AddChoice(const ACaption: string; const AItems: array of string): TAtlasChoiceBox;
    /// <summary>Fett gesetzte Überschrift eines Abschnitts.</summary>
    procedure AddTitle(AId: TAtlasTextId);
    /// <summary>Kürzel ohne eigenen Vorrang; der gilt für die Gruppe (#399). Palette und Prüfung stehen auf der
    /// Seite „Tastenkonflikte“ (#494).</summary>
    function AddKey(const ACaption: string): TEdit;
    procedure ResetHistoryClick(Sender: TObject);
    procedure AddFavoritesSection;
    procedure FavoritesRemoveClick(Sender: TObject);
    procedure FavoritesRemoveAllClick(Sender: TObject);
    procedure SetOnFavorites(const AValue: TFunc<TArray<TAtlasFavorite>>);
    procedure ResetUsageClick(Sender: TObject);
    procedure EditorToolbarCustomizeClick(Sender: TObject);
    procedure UnblockTipsClick(Sender: TObject);
    procedure AddTeamFileSection;
    procedure TeamFileClick(Sender: TObject);
    procedure TeamFileOpenClick(Sender: TObject);
    procedure SetOnTeamFile(const AValue: TFunc<TAtlasTeamSettings>);
    /// <summary>Beschriftung über die ganze Breite mit Zeilenumbruch.</summary>
    function AddWrappedLabel(AHeight: Integer; const ACaption: string): TLabel;
    procedure HelpFolderBrowseClick(Sender: TObject);
    /// <summary>Knöpfe „Neu …“, „Umbenennen …“ und „Löschen“ rechts neben der Auswahl des Layouts (#767).
    /// </summary>
    procedure AddWelcomeLayoutButtons;
    procedure WelcomeLayoutChange(Sender: TObject);
    procedure WelcomeLayoutNewClick(Sender: TObject);
    /// <summary>„Tracker-Einstellungen …“ (#1280): zeigt die Seite Issue-Tracker.</summary>
    procedure WelcomeIssuesLinkClick(Sender: TObject);
    procedure AddTrackerConnectionsSection;
    /// <summary>Gespeichert werden Verbindungen mit Name und gültiger Adresse.</summary>
    function TrackerConnectionsJson: string;
    function TrackerRows: TArray<TAtlasTrackerConnection>;
    function TrackerProviderCaption(const AName: string): string;
    function TrackerStateText(const AConnection: TAtlasTrackerConnection): string;
    function TrackerEditable: Boolean;
    procedure TrackerFillFields;
    procedure TrackerSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure TrackerNameChange(Sender: TObject);
    procedure TrackerProviderChange(Sender: TObject);
    procedure TrackerUrlChange(Sender: TObject);
    procedure TrackerAddClick(Sender: TObject);
    procedure TrackerRemoveClick(Sender: TObject);
    procedure TrackerTokenClick(Sender: TObject);
    procedure TrackerCheckClick(Sender: TObject);
    /// <summary>Zeile mit Beschriftung links und AControl rechts daneben (Verbindungen, Projekte).</summary>
    function AddTrackerLabelled(AId: TAtlasTextId; AControl: TWinControl; AWidth: Integer): TWinControl;
    function AddTrackerButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TAtlasTextId;
      AClick: TNotifyEvent): TButton;
    procedure AddTrackerColumn(AList: TListView; AId: TAtlasTextId; AWidth: Integer);
    /// <summary>Grauer Hinweis unter einer Tabelle.</summary>
    procedure AddTrackerHint(AId: TAtlasTextId; AAnchor: TControl);
    procedure AddTrackerProjectsSection;
    function TrackerProjectsJson: string;
    function TrackerProjectRows: TArray<TAtlasTrackerProjectMapping>;
    function TrackerProjectEditable: Boolean;
    function TrackerProjectSourceText(const AMapping: TAtlasTrackerProjectMapping): string;
    function TrackerProjectCovered(const AMapping: TAtlasTrackerProjectMapping): Boolean;
    procedure TrackerProjectFillFields;
    procedure TrackerProjectNoteFor(const AMapping: TAtlasTrackerProjectMapping);
    procedure TrackerProjectSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure TrackerProjectDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure TrackerProjectMatchChange(Sender: TObject);
    procedure TrackerProjectConnectionChange(Sender: TObject);
    procedure TrackerProjectProjectChange(Sender: TObject);
    procedure TrackerProjectAddCurrentClick(Sender: TObject);
    procedure TrackerProjectAddClick(Sender: TObject);
    procedure TrackerProjectAddFileClick(Sender: TObject);
    procedure TrackerProjectAddFolderClick(Sender: TObject);
    procedure TrackerProjectRemoveClick(Sender: TObject);
    /// <summary>Neue Zeile für AMatch (oder die vorhandene) wählen; Verbindung = erste persönliche.</summary>
    procedure TrackerProjectAdd(const AMatch: string);
    /// <summary>„Hinzufügen …“ ohne OnTrackerBrowse: Datei- bzw. Ordnerauswahl von Windows.</summary>
    function TrackerBrowse(AFolder: Boolean; out APath: string): Boolean;
    procedure AddTrackerQueriesSection;
    function TrackerQueriesJson: string;
    function TrackerQueryEditable: Boolean;
    /// <summary>Verbindung der Zeile in der Auswahl: 0 = „(alle)“, dann die Verbindungen.</summary>
    function TrackerQueryConnectionChoice(const AConnection: string): Integer;
    procedure TrackerQueryFillFields;
    procedure TrackerQueryNoteFor(const AQuery: TAtlasTrackerQuery);
    procedure TrackerQuerySelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure TrackerQueryNameChange(Sender: TObject);
    procedure TrackerQueryTextChange(Sender: TObject);
    procedure TrackerQueryConnectionChange(Sender: TObject);
    procedure TrackerQueryProjectChange(Sender: TObject);
    procedure TrackerQueryAddClick(Sender: TObject);
    procedure TrackerQueryRemoveClick(Sender: TObject);
    procedure TrackerQueryEditClick(Sender: TObject);
    procedure TrackerQueryRowChanged;
    /// <summary>Zustandsfeld, Benutzerfeld, Zustand beim Beginnen oder Zielzustände der gewählten Verbindung.</summary>
    procedure TrackerWorkflowChange(Sender: TObject);
    procedure TrackerLoadValuesClick(Sender: TObject);
    /// <summary>Verbindung für „Werte vom Tracker laden“: die gewählte mit Adresse, sonst die erste mit Adresse.
    /// </summary>
    function TrackerValuesConnection(out AConnection: TAtlasTrackerConnection): Boolean;
    /// <summary>Beschriftung links, Klappliste mit Eingabe daneben.</summary>
    function AddValueBox(const ACaption: string): TAtlasValueBox;
    procedure WelcomeLayoutRenameClick(Sender: TObject);
    procedure WelcomeLayoutDeleteClick(Sender: TObject);
    /// <summary>Ob das Häkchen bzw. die Auswahl des Bereichs AId ihn zeigt („Neu in Atlas“: nicht „Aus“).
    /// </summary>
    function WelcomeSectionShown(const AId: string; out AShown: Boolean): Boolean;
    procedure ShowWelcomeSection(const AId: string; AShown: Boolean);
    /// <summary>Spalten und Sichtbarkeit der Steuerelemente ins aktive Layout von FPageLayouts.</summary>
    procedure KeepWelcomeLayout;
    /// <summary>FPageLayouts auf die Seite: Namen, Auswahl, Spalten; AVisibility auch die Häkchen der
    /// Bereiche.</summary>
    procedure ShowWelcomeLayouts(AVisibility: Boolean);
    function AskLayoutName(var AName: string): Boolean;
    function ConfirmLayout(const AText: string; AQuestion: Boolean): Boolean;
    /// <summary>Beschriftung in einer Zeile, darunter ein Textfeld über die ganze Breite (#766).</summary>
    function AddTextLine(const ACaption: string): TEdit;
    procedure ResetWidthsClick(Sender: TObject);
    procedure HangTestClick(Sender: TObject);
    procedure DiagnosticModeClick(Sender: TObject);
    procedure ExperimentalAllowClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    /// <summary>Kopfzeile mit Hinweis und Knopf „Erlauben“, solange experimental.enabled aus ist (#834).</summary>
    procedure AddExperimentalBanner;
    /// <summary>Zeile unten mit dem Filter Alle / Geändert / Nur experimentelle (#834).</summary>
    procedure AddFilterRow;
    procedure FuseEnableSelectedClick(Sender: TObject);
    procedure FuseEnableAllClick(Sender: TObject);
    procedure AddFuseSection;
    procedure AddIndexSection;
    procedure AddSafeSection;
    /// <summary>Zeile „Verhalten je Quelle“ (#601): Quelle und Verhalten nebeneinander.</summary>
    procedure AddNotificationSources;
    procedure NotificationSourceChange(Sender: TObject);
    procedure NotificationModeChange(Sender: TObject);
    procedure AddReleaseSection;
    procedure AddOpenBuildSection;
    procedure LoadOpenBuild(const ASettings: TAtlasPluginSettings);
    procedure SaveOpenBuild(var ASettings: TAtlasPluginSettings);
    procedure AddTasksSection;
    procedure LoadTasks(const ASettings: TAtlasPluginSettings);
    procedure SaveTasks(var ASettings: TAtlasPluginSettings);
    procedure LoadRelease(const ASettings: TAtlasPluginSettings);
    procedure SaveRelease(var ASettings: TAtlasPluginSettings);
    procedure AddUndoSection;
    procedure AddUnitSearchSection;
    procedure AddWelcomeSection;
    /// <summary>Seite Issue-Tracker (#1280): Anbieter, Abfrage, „Beginnen“, Muster und Zugang (issues.*).</summary>
    procedure AddIssuesSection;
    /// <summary>Seite Versionsverwaltung (#1285).</summary>
    procedure AddVcsSection;
    procedure AddVcsExternalsSection;
    procedure AddVcsTool(AKind: TAtlasVcsKind; ACaption: TAtlasTextId);
    function AddVcsLink(AParent: TWinControl; ALeft: Integer; ACaption: TAtlasTextId): TButton;
    procedure VcsPathChange(Sender: TObject);
    procedure VcsExternalsRulesChange(Sender: TObject);
    procedure VcsBrowseClick(Sender: TObject);
    procedure VcsCheckClick(Sender: TObject);
    procedure VcsLinkClick(Sender: TObject);
    /// <summary>Tabelle Projekte (#1286): Art und Hauptbranch je .dproj, .groupproj oder Ordner.</summary>
    procedure AddVcsProjectsSection;
    function VcsProjectRows: TArray<TAtlasVcsProjectMapping>;
    function VcsProjectEditable: Boolean;
    function VcsProjectCovered(const AMapping: TAtlasVcsProjectMapping): Boolean;
    function VcsProjectSourceText(const AMapping: TAtlasVcsProjectMapping): string;
    procedure VcsProjectShowItem(AIndex: Integer);
    procedure VcsProjectFillFields;
    procedure VcsProjectNoteFor(const AMapping: TAtlasVcsProjectMapping);
    procedure VcsProjectSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure VcsProjectDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure VcsProjectMatchChange(Sender: TObject);
    procedure VcsProjectProviderChange(Sender: TObject);
    procedure VcsProjectMainBranchChange(Sender: TObject);
    procedure VcsProjectAddCurrentClick(Sender: TObject);
    procedure VcsProjectAddClick(Sender: TObject);
    procedure VcsProjectAddFileClick(Sender: TObject);
    procedure VcsProjectAddFolderClick(Sender: TObject);
    procedure VcsProjectRemoveClick(Sender: TObject);
    /// <summary>Zeile für AMatch anlegen (Art AProvider) bzw. wählen.</summary>
    procedure VcsProjectAdd(const AMatch, AProvider: string);
    function VcsProjectsJson: string;
    /// <summary>Tabelle „Server“ (#1287).</summary>
    procedure AddVcsServersSection;
    procedure VcsServerShowItem(AIndex: Integer);
    procedure VcsServerFillButtons;
    procedure VcsServerStart(AIndex: Integer);
    procedure VcsServerSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure VcsServerCheckClick(Sender: TObject);
    procedure VcsServerCheckAllClick(Sender: TObject);
    procedure VcsServerLoginClick(Sender: TObject);
    /// <summary>Zustand ohne Prozess: welche Datei für AKind gälte (OnVcsLocate).</summary>
    procedure RefreshVcsTool(AKind: TAtlasVcsKind);
    /// <summary>Beim Zeigen eines Reiters: die Seite Versionsverwaltung fragt einmal „Aktuelles Projekt“ ab.
    /// </summary>
    procedure SheetShown(ASheet: TTabSheet);
    /// <summary>Abschnitt „Zustand im Tracker“ (#1266) der Seite Issue-Tracker.</summary>
    procedure AddIssuesWorkflowSection;
    procedure AddIssuesTimeSection;
    procedure AddUpdatesSection;
    procedure AddBugReportSection;
    procedure IndexRefreshClick(Sender: TObject);
    procedure IndexRebuildClick(Sender: TObject);
    procedure IndexClearClick(Sender: TObject);
    procedure UpdateIndexButtons;
    /// <summary>Startet ACommand und zeigt bis zur Antwort „Frage den Server …“ (#874).</summary>
    procedure StartIndexCommand(const ACommand: TProc);
    /// <summary>Zeile mit Beschriftung und fünf Farbflächen.</summary>
    procedure AddSwatches(const ACaption: string; var ASwatches: array of TShape);
    procedure SwatchMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ResetColorsClick(Sender: TObject);
    class procedure ShowPairs(const ASwatches: array of TShape; const APairs: TAtlasPairColors); static;
    /// <summary>Farben der Flächen als Einstellung; gleich der Palette = leer.</summary>
    class function PairsSetting(const ASwatches: array of TShape; const ADefault: TAtlasPairColors): string; static;
    procedure ServerBrowseClick(Sender: TObject);
    procedure ServerPathChange(Sender: TObject);
    procedure SetDefaultServerPath(const AValue: string);
    procedure SetOnServerVersion(const AValue: TFunc<string, string>);
    procedure AutoWidthClick(Sender: TObject);
    procedure LoadControls(const ASettings: TAtlasPluginSettings);
    procedure AddTransferSection;
    /// <summary>Bindet die Elemente an ihre Einstellungen (Punkt, Kontextmenü, Zurücksetzen je Seite).</summary>
    procedure BindControls;
    procedure MarksChanged(Sender: TObject);
    procedure ResetPageClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
    procedure ProfileClick(Sender: TObject);
    procedure ResetAllClick(Sender: TObject);
    function Catalog: TAtlasSettingsCatalog;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Werte der Seite (ungespeichert) über den zuletzt geladenen.</summary>
    function CurrentSettings: TAtlasPluginSettings;
    /// <summary>Punkte an geänderten Werten und Knöpfe neu setzen (#723).</summary>
    procedure RefreshMarks;
    /// <summary>Einstellungen ANames (Registry-Namen) auf der Seite auf den Standard setzen; gespeichert wird
    /// erst mit OK (#723).</summary>
    procedure ResetNames(const ANames: TArray<string>);
    /// <summary>Alle Einstellungen des sichtbaren Reiters auf den Standard setzen (#723).</summary>
    procedure ResetPage;
    /// <summary>„Exportieren…“ mit den Werten der Seite (#723).</summary>
    property OnExportSettings: TProc<TAtlasPluginSettings> read FOnExportSettings write FOnExportSettings;
    /// <summary>„Importieren…“ und „Profil laden…“ (#723).</summary>
    property OnImportSettings: TAtlasSettingsImportEvent read FOnImportSettings write FOnImportSettings;
    /// <summary>„Alles zurücksetzen…“ (#723).</summary>
    property OnResetAllSettings: TAtlasSettingsResetEvent read FOnResetAllSettings write FOnResetAllSettings;
    /// <summary>Zum Testen: Übertragen (#723).</summary>
    property Marks: TAtlasSettingsMarks read FMarks;
    property TransferBar: TWinControl read FTransferBar;
    property SettingsExportImportCheck: TCheckBox read FSettingsExportImport;
    property SettingsMarkModifiedCheck: TCheckBox read FSettingsMarkModified;
    property SettingsBackupBeforeImportCheck: TCheckBox read FSettingsBackupBeforeImport;
    property SettingsExportSecretsChoice: TAtlasChoiceBox read FSettingsExportSecrets;
    property ExportButton: TButton read FExportButton;
    property ImportButton: TButton read FImportButton;
    property ResetPageButton: TButton read FResetPageButton;
    property ResetAllButton: TButton read FResetAllButton;
    procedure LoadFrom(const ASettings: TAtlasPluginSettings);
    procedure SaveTo(var ASettings: TAtlasPluginSettings);
    /// <summary>Liste der abgeschalteten Features und Quellen neu lesen (#493).</summary>
    procedure RefreshFuse;
    /// <summary>Kennzahlen des Index neu holen und anzeigen (#492).</summary>
    procedure RefreshIndex;
    /// <summary>Antwort auf OnIndexMetrics, OnIndexRebuild oder OnIndexClear (#874): Text anzeigen, Knöpfe
    /// wieder frei. Darf auch noch während des Ereignisses kommen.</summary>
    procedure IndexAnswered(const AText: string);
    /// <summary>Wartet die Seite auf eine Antwort des Index (#874)?</summary>
    function IndexBusy: Boolean;
    /// <summary>Liste der angehefteten Favoriten neu lesen (#458).</summary>
    procedure RefreshFavorites;
    /// <summary>Zeigt die Einstellung AKey (Name der Plugin-Einstellung, #628): Reiter, ins Bild rollen, Fokus,
    /// Zeile fett. False, wenn die Seite den Schlüssel nicht kennt; ohne Fenster folgt es in CreateWnd.</summary>
    function Reveal(const AKey: string): Boolean;
    /// <summary>Steuerelement zu AKey; nil, wenn die Seite den Schlüssel nicht kennt.</summary>
    function ControlOf(const AKey: string): TControl;
    /// <summary>Reiter der Seite, einer je Bereich (#227).</summary>
    property Pages: TPageControl read FPages;
    /// <summary>Baum der Bereiche und Unterpunkte links; schaltet Pages um (#890).</summary>
    property Navigation: TTreeView read FTree;
    /// <summary>Sperren, Grund, Spiegel und graue Knoten nach den aktuellen Werten (#890).</summary>
    procedure UpdateLocks;
    property Groups: TAtlasSettingsGroups read FGroups;
    /// <summary>Zum Testen: Rahmen des Hauptschalters AName (Registry-Name); nil ohne Rahmen.</summary>
    function FrameOf(const AName: string): TAtlasSettingsGroup;
    /// <summary>Zum Testen: Reiter des Unterpunkts ANode (Id aus x-nodes).</summary>
    function NodeSheet(const ANode: string): TTabSheet;
    /// <summary>Zum Testen: Spiegel des Hauptschalters AName in der Übersicht seines Bereichs.</summary>
    function OverviewMirror(const AName: string): TCheckBox;
    function SheetGray(ASheet: TTabSheet): Boolean;
    /// <summary>Id des Unterpunkts zu ASheet; leer beim Hauptknoten.</summary>
    function NodeOfSheet(ASheet: TTabSheet): string;
    /// <summary>Gemerkte Auswahl und aufgeklappte Bereiche vergessen (Tests).</summary>
    class procedure ForgetTreeState; static;
    /// <summary>Zum Testen: Liste und Schaltflächen der Sicherung.</summary>
    property FuseList: TListBox read FFuseList;
    property FuseEnableSelected: TButton read FFuseEnableSelected;
    property FuseEnableAll: TButton read FFuseEnableAll;
    /// <summary>Zum Testen: Kennzahlen und Schaltflächen des Index.</summary>
    property IndexInfo: TLabel read FIndexInfo;
    property IndexRebuild: TButton read FIndexRebuild;
    property IndexClear: TButton read FIndexClear;
    /// <summary>Zum Testen: Einstellungen des Statusfelds (#591).</summary>
    property StatusField: TCheckBox read FStatusField;
    property DiagnosticMode: TCheckBox read FDiagnosticMode;
    property ExperimentalEnabled: TCheckBox read FExperimentalEnabled;
    property ExperimentalBanner: TWinControl read FExperimentalBanner;
    property Filter: TAtlasChoiceBox read FFilter;
    /// <summary>Zeile mit „Wächter testen“; nur im Diagnosemodus sichtbar (Code-Review S-07).</summary>
    property HangTestRow: TWinControl read FHangTestRow;
    property SetupChecklist: TCheckBox read FSetupChecklist;
    property ShortcutTips: TCheckBox read FShortcutTips;
    property ShortcutTipsScope: TAtlasChoiceBox read FShortcutTipsScope;
    /// <summary>Zum Testen: Benachrichtigungszentrale (#601).</summary>
    property Notifications: TCheckBox read FNotifications;
    property NotificationsMax: TEdit read FNotificationsMax;
    property NotificationSource: TAtlasChoiceBox read FNotificationSource;
    property NotificationMode: TAtlasChoiceBox read FNotificationMode;
    property NotificationsSpec: string read FNotificationsSpec;
    property NotificationsKey: TEdit read FNotificationsKey;
    property StatusSummary: TCheckBox read FStatusSummary;
    property StatusToggles: TAtlasChoiceBox read FStatusToggles;
    property IndexProgress: TAtlasChoiceBox read FIndexProgress;
    property StatusHidden: TEdit read FStatusHidden;
    /// <summary>Zum Testen: abgesicherter Start (#722).</summary>
    property SafeAsk: TCheckBox read FSafeAsk;
    property SafeAuto: TCheckBox read FSafeAuto;
    property SafeKey: TAtlasChoiceBox read FSafeKey;
    property SafeTimeout: TEdit read FSafeTimeout;
    property SafeHistory: TEdit read FSafeHistory;
    /// <summary>Zum Testen: Atlas-Änderungen über mehrere Dateien (#721).</summary>
    property UndoEnabled: TCheckBox read FUndoEnabled;
    property UndoDepth: TEdit read FUndoDepth;
    property UndoPersist: TCheckBox read FUndoPersist;
    property UndoMaxSize: TEdit read FUndoMaxSize;
    property UndoOnConflict: TAtlasChoiceBox read FUndoOnConflict;
    property UndoNewFiles: TAtlasChoiceBox read FUndoNewFiles;
    property UndoKey: TEdit read FUndoKey;
    /// <summary>Zum Testen: Deklaration/Implementierung wechseln (#775).</summary>
    property MethodToggle: TCheckBox read FMethodToggle;
    property MethodToggleUpKey: TEdit read FMethodToggleUpKey;
    property MethodToggleDownKey: TEdit read FMethodToggleDownKey;
    /// <summary>Zum Testen: Zeilen verschieben und duplizieren (#634).</summary>
    property MoveLines: TCheckBox read FMoveLines;
    property MoveLinesUpKey: TEdit read FMoveLinesUpKey;
    property DuplicateLinesDownKey: TEdit read FDuplicateLinesDownKey;
    property ToggleBlockComment: TCheckBox read FToggleBlockComment;
    property ToggleBlockCommentKey: TEdit read FToggleBlockCommentKey;
    property ToggleBlockCommentStyle: TAtlasChoiceBox read FToggleBlockCommentStyle;
    property ToggleBlockCommentFallback: TAtlasChoiceBox read FToggleBlockCommentFallback;
    property ToggleBlockCommentOwnLines: TCheckBox read FToggleBlockCommentOwnLines;
    property ToggleBlockCommentScope: TAtlasChoiceBox read FToggleBlockCommentScope;
    /// <summary>Zum Testen: Neue Zeile ober- oder unterhalb (#700).</summary>
    property NewLineAround: TCheckBox read FNewLineAround;
    property NewLineBelowKey: TEdit read FNewLineBelowKey;
    property NewLineAboveKey: TEdit read FNewLineAboveKey;
    property NewLineAroundStatementAware: TCheckBox read FNewLineAroundStatementAware;
    /// <summary>Zum Testen: Umschließung entfernen (#657).</summary>
    property Unwrap: TCheckBox read FUnwrap;
    property UnwrapKey: TEdit read FUnwrapKey;
    /// <summary>Zum Testen: Sicher löschen (#716).</summary>
    property SafeDelete: TCheckBox read FSafeDelete;
    property SafeDeleteKey: TEdit read FSafeDeleteKey;
    /// <summary>Zum Testen: Kommentar beim Enter fortsetzen (#696).</summary>
    property ContinueComments: TCheckBox read FContinueComments;
    property ContinueCommentsLists: TCheckBox read FContinueCommentsLists;
    property ContinueCommentsBlockPrefix: TEdit read FContinueCommentsBlockPrefix;
    /// <summary>Zum Testen: Markierung beim Tippen umschließen (#672).</summary>
    property WrapSelection: TCheckBox read FWrapSelection;
    property WrapSelectionChars: TEdit read FWrapSelectionChars;
    /// <summary>Zum Testen: Anweisung vervollständigen (#697).</summary>
    property CompleteStatement: TCheckBox read FCompleteStatement;
    property CompleteStatementKey: TEdit read FCompleteStatementKey;
    property CompleteStatementBeginEnd: TAtlasChoiceBox read FCompleteStatementBeginEnd;
    property CompleteStatementTryKind: TAtlasChoiceBox read FCompleteStatementTryKind;
    property CompleteStatementMethodBody: TCheckBox read FCompleteStatementMethodBody;
    property FormatCode: TCheckBox read FFormatCode;
    property FormatCodeKey: TEdit read FFormatCodeKey;
    property ContinuePattern: TCheckBox read FContinuePattern;
    property ContinuePatternMinLines: TEdit read FContinuePatternMinLines;
    property MultiCursor: TCheckBox read FMultiCursor;
    property StickyScroll: TCheckBox read FStickyScroll;
    property StickyScrollMaxLines: TEdit read FStickyScrollMaxLines;
    property Minimap: TCheckBox read FMinimap;
    property MinimapRender: TAtlasChoiceBox read FMinimapRender;
    property MinimapWidth: TEdit read FMinimapWidth;
    property LinkedEditing: TCheckBox read FLinkedEditing;
    property SmartPaste: TAtlasChoiceBox read FSmartPaste;
    property MultiCursorModifier: TAtlasChoiceBox read FMultiCursorModifier;
    property MultiCursorNextKey: TEdit read FMultiCursorNextKey;
    property MultiCursorSkipKey: TEdit read FMultiCursorSkipKey;
    property MultiCursorLineEndsKey: TEdit read FMultiCursorLineEndsKey;
    property MultiCursorAboveKey: TEdit read FMultiCursorAboveKey;
    property MultiCursorBelowKey: TEdit read FMultiCursorBelowKey;
    property RedoKey: TEdit read FRedoKey;
    property UpdatesCheck: TCheckBox read FUpdatesCheck;
    property BugReportAnonymize: TCheckBox read FBugReportAnonymize;
    /// <summary>Zum Testen: Willkommensseite (#753).</summary>
    property WelcomeEnabled: TCheckBox read FWelcomeEnabled;
    property WelcomeOpenOnStart: TCheckBox read FWelcomeOpenOnStart;
    property WelcomeOpenWhenNoProject: TCheckBox read FWelcomeOpenWhenNoProject;
    /// <summary>Zum Testen: freies Layout (#767).</summary>
    property WelcomeCustomLayout: TCheckBox read FWelcomeCustomLayout;
    property WelcomeColumns: TEdit read FWelcomeColumns;
    property WelcomeActiveLayout: TAtlasChoiceBox read FWelcomeActiveLayout;
    property WelcomeLayoutNew: TButton read FWelcomeLayoutNew;
    property WelcomeLayoutRename: TButton read FWelcomeLayoutRename;
    property WelcomeLayoutDelete: TButton read FWelcomeLayoutDelete;
    property PageLayouts: TAtlasWelcomeLayouts read FPageLayouts;
    /// <summary>Wählt das Layout AIndex wie die Auswahlliste (#767).</summary>
    procedure SelectWelcomeLayout(AIndex: Integer);
    /// <summary>Namensabfrage für „Neu …“ und „Umbenennen …“; Standard: InputQuery.</summary>
    property OnAskLayoutName: TAtlasSettingsAskName read FOnAskLayoutName write FOnAskLayoutName;
    /// <summary>Rückfrage vor „Löschen“ und Meldung bei doppeltem Namen; Standard: Dialog.</summary>
    property OnConfirmLayout: TAtlasSettingsConfirm read FOnConfirmLayout write FOnConfirmLayout;
    property WelcomeHeader: TCheckBox read FWelcomeHeader;
    property WelcomeGreeting: TCheckBox read FWelcomeGreeting;
    property WelcomeSearch: TCheckBox read FWelcomeSearch;
    property WelcomeSearchSymbols: TCheckBox read FWelcomeSearchSymbols;
    property WelcomeSearchKey: TEdit read FWelcomeSearchKey;
    property WelcomeWhatsNew: TAtlasChoiceBox read FWelcomeWhatsNew;
    property WelcomeContinue: TCheckBox read FWelcomeContinue;
    property WelcomeContinueCount: TEdit read FWelcomeContinueCount;
    property WelcomeContinueIncoming: TCheckBox read FWelcomeContinueIncoming;
    property WelcomeContinueFetch: TCheckBox read FWelcomeContinueFetch;
    property WelcomeSaved: TCheckBox read FWelcomeSaved;
    property WelcomeProjects: TCheckBox read FWelcomeProjects;
    property WelcomeMaxProjects: TEdit read FWelcomeMaxProjects;
    property WelcomeRefreshVcs: TCheckBox read FWelcomeRefreshVcs;
    /// <summary>Zum Testen: Bereich „Projektverlauf“ (#758).</summary>
    property WelcomeTrends: TCheckBox read FWelcomeTrends;
    property WelcomeTrendsPoints: TEdit read FWelcomeTrendsPoints;
    function WelcomeTrendsSeries(ASeries: TAtlasTrendSeries): TCheckBox;
    /// <summary>Zum Testen: Bereich „Testergebnisse“ (#763).</summary>
    property WelcomeTests: TCheckBox read FWelcomeTests;
    property WelcomeTestsMaxFailures: TEdit read FWelcomeTestsMaxFailures;
    property WelcomeTestsCi: TCheckBox read FWelcomeTestsCi;
    property WelcomeTestsCiProvider: TAtlasChoiceBox read FWelcomeTestsCiProvider;
    property WelcomeTestsCiInterval: TEdit read FWelcomeTestsCiInterval;
    property WelcomeTestsCiNotify: TCheckBox read FWelcomeTestsCiNotify;
    property CiLogin: TCheckBox read FCiLogin;
    property WelcomeIssues: TCheckBox read FWelcomeIssues;
    property IssuesTracker: TAtlasChoiceBox read FIssuesTracker;
    property IssuesStart: TAtlasChoiceBox read FIssuesStart;
    property IssuesBranchPattern: TEdit read FIssuesBranchPattern;
    property IssuesBranchBase: TEdit read FIssuesBranchBase;
    property IssuesCommitPattern: TEdit read FIssuesCommitPattern;
    property TrackerLogin: TCheckBox read FTrackerLogin;
    property IssuesPreview: TCheckBox read FIssuesPreview;
    property IssuesPreviewComments: TCheckBox read FIssuesPreviewComments;
    property IssuesCodeLinks: TCheckBox read FIssuesCodeLinks;
    property IssuesBlameLinks: TCheckBox read FIssuesBlameLinks;
    property IssuesBlameMaxRevisions: TEdit read FIssuesBlameMaxRevisions;
    property IssuesSyncState: TCheckBox read FIssuesSyncState;
    property IssuesStateField: TAtlasValueBox read FIssuesStateField;
    property IssuesAssigneeField: TAtlasValueBox read FIssuesAssigneeField;
    property IssuesStartState: TAtlasValueBox read FIssuesStartState;
    property IssuesAssignOnStart: TCheckBox read FIssuesAssignOnStart;
    property IssuesStartComment: TEdit read FIssuesStartComment;
    property IssuesEndStates: TEdit read FIssuesEndStates;
    property IssuesEndComment: TEdit read FIssuesEndComment;
    property IssuesLoadValues: TButton read FIssuesLoadValues;
    property IssuesValuesNote: TLabel read FIssuesValuesNote;
    property IssuesTimeTracking: TCheckBox read FIssuesTimeTracking;
    property IssuesIdleMinutes: TEdit read FIssuesIdleMinutes;
    property IssuesTimeRounding: TEdit read FIssuesTimeRounding;
    property IssuesConnectionStateField: TAtlasValueBox read FIssuesConnectionStateField;
    property IssuesConnectionAssigneeField: TAtlasValueBox read FIssuesConnectionAssigneeField;
    property IssuesConnectionStartState: TAtlasValueBox read FIssuesConnectionStartState;
    property IssuesConnectionEndStates: TEdit read FIssuesConnectionEndStates;
    property IssuesPreviewChecklists: TCheckBox read FIssuesPreviewChecklists;
    property IssuesChecklistStatus: TCheckBox read FIssuesChecklistStatus;
    property WelcomeIssuesLink: TButton read FWelcomeIssuesLink;
    /// <summary>Zum Testen: Tracker-Verbindungen (#1260).</summary>
    property IssuesConnections: TListView read FIssuesConnections;
    property IssuesConnectionName: TEdit read FIssuesConnectionName;
    property IssuesConnectionProvider: TAtlasChoiceBox read FIssuesConnectionProvider;
    property IssuesConnectionUrl: TEdit read FIssuesConnectionUrl;
    property IssuesConnectionNote: TLabel read FIssuesConnectionNote;
    property IssuesConnectionAdd: TButton read FIssuesConnectionAdd;
    property IssuesConnectionRemove: TButton read FIssuesConnectionRemove;
    property IssuesConnectionToken: TButton read FIssuesConnectionToken;
    property IssuesConnectionCheck: TButton read FIssuesConnectionCheck;
    /// <summary>Persönliche Verbindungen, wie die Seite sie gerade zeigt.</summary>
    property TrackerConnections: TArray<TAtlasTrackerConnection> read FTrackerConnections;
    /// <summary>Zum Testen: Zuordnung Delphi-Projekt → Tracker-Projekt (#1261).</summary>
    property IssuesProjects: TListView read FIssuesProjects;
    property IssuesProjectMatch: TEdit read FIssuesProjectMatch;
    property IssuesProjectConnection: TAtlasChoiceBox read FIssuesProjectConnection;
    property IssuesProjectProject: TEdit read FIssuesProjectProject;
    property IssuesProjectNote: TLabel read FIssuesProjectNote;
    property IssuesProjectAddCurrent: TButton read FIssuesProjectAddCurrent;
    property IssuesProjectAdd: TButton read FIssuesProjectAdd;
    property IssuesProjectRemove: TButton read FIssuesProjectRemove;
    property IssuesProjectAddMenu: TPopupMenu read FIssuesProjectAddMenu;
    /// <summary>Persönliche Zeilen, wie die Seite sie gerade zeigt.</summary>
    property TrackerProjects: TArray<TAtlasTrackerProjectMapping> read FTrackerProjects;
    /// <summary>Zum Testen: benannte Abfragen (#1262).</summary>
    property IssuesQueries: TListView read FIssuesQueries;
    property IssuesQueryName: TEdit read FIssuesQueryName;
    property IssuesQueryText: TEdit read FIssuesQueryText;
    property IssuesQueryConnection: TAtlasChoiceBox read FIssuesQueryConnection;
    property IssuesQueryProject: TEdit read FIssuesQueryProject;
    property IssuesQueryNote: TLabel read FIssuesQueryNote;
    property IssuesQueryAdd: TButton read FIssuesQueryAdd;
    property IssuesQueryRemove: TButton read FIssuesQueryRemove;
    property IssuesQueryEdit: TButton read FIssuesQueryEdit;
    property IssuesQueryPicker: TCheckBox read FIssuesQueryPicker;
    property IssuesCreate: TCheckBox read FIssuesCreate;
    property IssuesCreateIncludeCode: TCheckBox read FIssuesCreateIncludeCode;
    property TrackerQueries: TArray<TAtlasTrackerQuery> read FTrackerQueries;
    /// <summary>Zum Testen: Schnellaktionen je Projekt (#764).</summary>
    property WelcomeQuickActions: TCheckBox read FWelcomeQuickActions;
    function WelcomeQuickActionsItem(AAction: TAtlasQuickAction): TCheckBox;
    property WelcomeQuickActionsConsole: TEdit read FWelcomeQuickActionsConsole;
    property WelcomeQuickActionsBuildKey: TEdit read FWelcomeQuickActionsBuildKey;
    property WelcomeQuickActionsTestKey: TEdit read FWelcomeQuickActionsTestKey;
    property WelcomeUnsaved: TCheckBox read FWelcomeUnsaved;
    property WelcomeUnsavedMinAge: TEdit read FWelcomeUnsavedMinAge;
    property WelcomeUnsavedWarn: TEdit read FWelcomeUnsavedWarn;
    property WelcomeUnsavedAlert: TEdit read FWelcomeUnsavedAlert;
    property WelcomeUnsavedHideClean: TCheckBox read FWelcomeUnsavedHideClean;
    property WelcomeStatusTile: TCheckBox read FWelcomeStatusTile;
    property WelcomeStatusTileOnlyProblems: TCheckBox read FWelcomeStatusTileOnlyProblems;
    /// <summary>Zum Testen: Karte „Atlas entdecken“ und Zählung (#757).</summary>
    property WelcomeDiscover: TCheckBox read FWelcomeDiscover;
    property TipsUsageTracking: TCheckBox read FTipsUsageTracking;
    property ResetUsageButton: TButton read FResetUsage;
    /// <summary>Zum Testen: Editorleiste (#1101).</summary>
    property EditorToolbarItemsEdit: TEdit read FEditorToolbarItems;
    property EditorToolbarPositionBox: TAtlasChoiceBox read FEditorToolbarPosition;
    property EditorToolbarCustomizeButton: TButton read FEditorToolbarCustomize;
    property EditorStatusBarItemsEdit: TEdit read FEditorStatusBarItems;
    property UnblockTipsButton: TButton read FUnblockTips;
    /// <summary>Zum Testen: Bereich „Hilfe und Rückmeldung“ (#766).</summary>
    property WelcomeHelp: TCheckBox read FWelcomeHelp;
    property WelcomeHelpReportUrl: TEdit read FWelcomeHelpReportUrl;
    property WelcomeHelpReportFolder: TEdit read FWelcomeHelpReportFolder;
    /// <summary>Zum Testen: Einrichtungskarte und „Neu mit Atlas“ (#759).</summary>
    property WelcomeProjectSetup: TCheckBox read FWelcomeProjectSetup;
    property WelcomeNewFromTemplate: TCheckBox read FWelcomeNewFromTemplate;
    property VersionLabel: TLabel read FVersion;
    /// <summary>Kennzahlen im Hintergrund holen; den Text liefert IndexAnswered. nil = nicht verfügbar.</summary>
    property OnIndexMetrics: TProc read FOnIndexMetrics write FOnIndexMetrics;
    /// <summary>„Index neu aufbauen“ bzw. „Index löschen“ im Hintergrund; das Ergebnis liefert IndexAnswered.</summary>
    property OnIndexRebuild: TProc read FOnIndexRebuild write FOnIndexRebuild;
    property OnIndexClear: TProc read FOnIndexClear write FOnIndexClear;
    /// <summary>Rückfrage vor dem Löschen; Standard: Dialog mit Ja/Nein.</summary>
    property ConfirmClear: TFunc<Boolean> read FConfirmClear write FConfirmClear;
    /// <summary>„Verlauf zurücksetzen“ der lernenden Gewichtung (#418).</summary>
    property OnResetHistory: TProc read FOnResetHistory write FOnResetHistory;
    /// <summary>Angeheftete Favoriten (#458) für die Liste; nil = keine Liste.</summary>
    property OnFavorites: TFunc<TArray<TAtlasFavorite>> read FOnFavorites write SetOnFavorites;
    /// <summary>Favoriten mit diesen Schlüsseln lösen (#458, „Entfernen“, „Alle entfernen“).</summary>
    property OnRemoveFavorites: TProc<TArray<string>> read FOnRemoveFavorites write FOnRemoveFavorites;
    /// <summary>Zum Testen: Favoriten (#458).</summary>
    property FavoritesCheck: TCheckBox read FFavorites;
    property NotesCheck: TCheckBox read FNotes;
    property McpBuildCheck: TCheckBox read FMcpBuild;
    /// <summary>Zum Testen: Beim Öffnen bauen.</summary>
    property OpenBuildChoice: TAtlasChoiceBox read FOpenBuild;
    property OpenBuildScopeChoice: TAtlasChoiceBox read FOpenBuildScope;
    /// <summary>Zum Testen: Listenmodus der Vervollständigung (#497).</summary>
    property ListModeChoice: TAtlasChoiceBox read FListMode;
    property ListScopeChoice: TAtlasChoiceBox read FListScope;
    property OpenBuildDelayEdit: TEdit read FOpenBuildDelay;
    property OpenBuildExcludeEdit: TEdit read FOpenBuildExclude;
    /// <summary>Zum Testen: Projektaufgaben (#900).</summary>
    property TasksEnabledCheck: TCheckBox read FTasksEnabled;
    property TasksProblemsFromOutputCheck: TCheckBox read FTasksProblemsFromOutput;
    property TasksBeforeBuildChoice: TAtlasChoiceBox read FTasksBeforeBuild;
    property TasksSaveBeforeRunCheck: TCheckBox read FTasksSaveBeforeRun;
    property TasksRunChecksParallelCheck: TCheckBox read FTasksRunChecksParallel;
    property TasksOnlyFindingsCheck: TCheckBox read FTasksOnlyFindings;
    /// <summary>Zum Testen: Tests ausführen (#69).</summary>
    property CodeLensTestsCheck: TCheckBox read FCodeLensTests;
    property TestRunCheck: TCheckBox read FTestRun;
    property TestsBuildFirstCheck: TCheckBox read FTestsBuildFirst;
    property TestsAfterBuildCheck: TCheckBox read FTestsAfterBuild;
    property BuildZeroHintsCheck: TCheckBox read FBuildZeroHints;
    property ShowInterfaceCostCheck: TCheckBox read FShowInterfaceCost;
    /// <summary>Zum Testen: Alt+F11 und Umschalt+F12 übernehmen (#786).</summary>
    property UnitSearchReplaceUseUnitCheck: TCheckBox read FUnitSearchReplaceUseUnit;
    property UnitSearchReplaceFormsCheck: TCheckBox read FUnitSearchReplaceForms;
    /// <summary>Zum Testen: Schranke für Hinweise und Warnungen (#530).</summary>
    property BuildSummaryCheck: TCheckBox read FBuildSummary;
    property BuildWarningsAsErrorsEdit: TEdit read FBuildWarningsAsErrors;
    /// <summary>Zum Testen: Prüfung vor dem Compile (#529).</summary>
    property BuildGateChoice: TAtlasChoiceBox read FBuildGate;
    property BuildGateTimeoutEdit: TEdit read FBuildGateTimeout;
    property BuildCompilerSwitchesCheck: TCheckBox read FBuildCompilerSwitches;
    property BuildSwitchesInStatusBarCheck: TCheckBox read FBuildSwitchesInStatusBar;
    /// <summary>Zum Testen: Release-Build-Wächter (#533).</summary>
    property ReleaseGuardCheck: TCheckBox read FReleaseGuard;
    property ReleaseConfigsEdit: TEdit read FReleaseConfigs;
    /// <summary>Haken einer Prüfung ohne Sollwert; nil für Prüfungen mit Sollwert.</summary>
    function ReleaseCheckBox(ACheck: TAtlasReleaseCheck): TCheckBox;
    /// <summary>Auswahl einer Prüfung mit Sollwert (0 = nicht prüfen, 1 = Soll aus, 2 = Soll an); sonst nil.</summary>
    function ReleaseCheckChoice(ACheck: TAtlasReleaseCheck): TAtlasChoiceBox;
    /// <summary>Zum Testen: Startprofile (#575).</summary>
    property StartProfilesCheck: TCheckBox read FStartProfiles;
    property StartProfilesStatusFieldCheck: TCheckBox read FStartProfilesStatusField;
    /// <summary>Zum Testen: Test debuggen (#585).</summary>
    property TestDebugCheck: TCheckBox read FTestDebug;
    property TestBreakAtStartCheck: TCheckBox read FTestBreakAtStart;
    property DebugHoverValuesCheck: TCheckBox read FDebugHoverValues;
    property DebugVisualizersCheck: TCheckBox read FDebugVisualizers;
    property DebugVisualizerNameFieldsEdit: TEdit read FDebugVisualizerNameFields;
    property DebugVisualizerMaxLengthEdit: TEdit read FDebugVisualizerMaxLength;
    property DebugVisualizerEvaluationBox: TAtlasChoiceBox read FDebugVisualizerEvaluation;
    property DebugDisplayRulesCheck: TCheckBox read FDebugDisplayRules;
    property DebugDisplayRulesAllowCallsCheck: TCheckBox read FDebugDisplayRulesAllowCalls;
    property DebugStepIntoTargetCheck: TCheckBox read FDebugStepIntoTarget;
    property DebugStepFiltersCheck: TCheckBox read FDebugStepFilters;
    function DebugStepFilterKindCheck(AKind: TStepFilterKind): TCheckBox;
    property DebugStepFilterPatternsEdit: TEdit read FDebugStepFilterPatterns;
    property DebugStepIntoTargetKeyEdit: TEdit read FDebugStepIntoTargetKey;
    property DebugBreakOnNextEventCheck: TCheckBox read FDebugBreakOnNextEvent;
    property DebugBreakOnNextEventExcludedEdit: TEdit read FDebugBreakOnNextEventExcluded;
    function DebugVisualizerKindCheck(AKind: TAtlasVisualizerKind): TCheckBox;
    property DebugExplainUnavailableCheck: TCheckBox read FDebugExplainUnavailable;
    property DebugCompletionInDialogsCheck: TCheckBox read FDebugCompletionInDialogs;
    property DebugEvaluateWindowCheck: TCheckBox read FDebugEvaluateWindow;
    property DebugEvaluateReplaceCtrlF7Check: TCheckBox read FDebugEvaluateReplaceCtrlF7;
    property DebugExplainAccessViolationCheck: TCheckBox read FDebugExplainAccessViolation;
    property DebugExplainAccessViolationAllowCallsCheck: TCheckBox read FDebugExplainAccessViolationAllowCalls;
    property DebugExceptionHistoryCheck: TCheckBox read FDebugExceptionHistory;
    property DebugJustMyCodeCheck: TCheckBox read FDebugJustMyCode;
    property DebugExceptionBannerCheck: TCheckBox read FDebugExceptionBanner;
    property DebugExceptionBannerIgnoreAtLocationCheck: TCheckBox read FDebugExceptionBannerIgnoreAtLocation;
    property DebugInlineValuesCheck: TCheckBox read FDebugInlineValues;
    property DebugInlineValuesPerLineEdit: TEdit read FDebugInlineValuesPerLine;
    property DebugOwnCodeFoldersEdit: TEdit read FDebugOwnCodeFolders;
    /// <summary>Zum Testen: benannte Lesezeichen (#622).</summary>
    property BookmarksNamedCheck: TCheckBox read FBookmarksNamed;
    property BookmarksSharedCheck: TCheckBox read FBookmarksShared;
    property BookmarkKey: TEdit read FBookmarkKey;
    /// <summary>Zum Testen: schnelle Lesezeichen (#1104).</summary>
    property QuickBookmarksCheck: TCheckBox read FQuickBookmarks;
    property QuickBookmarksGutterCheck: TCheckBox read FQuickBookmarksGutter;
    property QuickBookmarksGutterClickCheck: TCheckBox read FQuickBookmarksGutterClick;
    property QuickBookmarksNumberedKeysCheck: TCheckBox read FQuickBookmarksNumberedKeys;
    property QuickBookmarkKeyEdit: TEdit read FQuickBookmarkKey;
    property QuickBookmarkChordWaitEdit: TEdit read FQuickBookmarkChordWait;
    property QuickBookmarksScopeBox: TAtlasChoiceBox read FQuickBookmarksScope;
    property QuickBookmarksImportIdeCheck: TCheckBox read FQuickBookmarksImportIde;
    property NextBookmarkKeyEdit: TEdit read FNextBookmarkKey;
    property PreviousBookmarkKeyEdit: TEdit read FPreviousBookmarkKey;
    /// <summary>Zum Testen: Blockende-Beschriftungen (#620) und Taste „Element ausblenden …“ (#628).</summary>
    property BlockEndLabelsCheck: TCheckBox read FBlockEndLabels;
    /// <summary>Zum Testen: Typmarken von Inline-Variablen (#453).</summary>
    property InlayTypeHintsCheck: TCheckBox read FInlayTypeHints;
    /// <summary>Zum Testen: Include-Symbole hinter {$I} (#860).</summary>
    property InlayDefineHintsCheck: TCheckBox read FInlayDefineHints;
    /// <summary>Zum Testen: Codes von Steuerzeichen (#862).</summary>
    property InlayCharHintsCheck: TCheckBox read FInlayCharHints;
    /// <summary>Zum Testen: Marken „ohne Self“ (#686).</summary>
    property InlayMethodHintsCheck: TCheckBox read FInlayMethodHints;
    property BlockEndLabelsMinLinesEdit: TEdit read FBlockEndLabelsMinLines;
    property DimUnusedUsesCheck: TCheckBox read FDimUnusedUses;
    property RecursionMarkersCheck: TCheckBox read FRecursionMarkers;
    property GutterColumnCheck: TCheckBox read FGutterColumn;
    property GutterColumnProblemsCheck: TCheckBox read FGutterColumnProblems;
    property GutterColumnCodeActionsCheck: TCheckBox read FGutterColumnCodeActions;
    property GutterColumnOverridesCheck: TCheckBox read FGutterColumnOverrides;
    property SelectionMatchesCheck: TCheckBox read FSelectionMatches;
    property SelectionMatchesMinLength: TEdit read FSelectionMatchesMinLength;
    property SelectionMatchesCaseSensitiveCheck: TCheckBox read FSelectionMatchesCaseSensitive;
    property SelectionMatchesWholeWordCheck: TCheckBox read FSelectionMatchesWholeWord;
    property SelectionMatchesNavigateF3Check: TCheckBox read FSelectionMatchesNavigateF3;
    property SelectionMatchesMaxMatches: TEdit read FSelectionMatchesMaxMatches;
    property ExitPointsCheck: TCheckBox read FExitPoints;
    property ExitPointsExceptionsCheck: TCheckBox read FExitPointsExceptions;
    property ExitPointsLoopsCheck: TCheckBox read FExitPointsLoops;
    property ExitPointsBadgeCheck: TCheckBox read FExitPointsBadge;
    property ReassignedCheck: TCheckBox read FReassigned;
    /// <summary>Zum Testen: Häkchen je Art, Linie und Farbe (#712).</summary>
    function ReassignedTargetCheck(ATarget: TAtlasReassignedTarget): TCheckBox;
    property ReassignedStyleBox: TAtlasChoiceBox read FReassignedStyle;
    property ReassignedColorEdit: TEdit read FReassignedColor;
    /// <summary>Zum Testen: Typ des markierten Ausdrucks (#689).</summary>
    property ExpressionTypeCheck: TCheckBox read FExpressionType;
    property ExpressionTypeConversionsCheck: TCheckBox read FExpressionTypeConversions;
    property ExpressionTypeConstValueCheck: TCheckBox read FExpressionTypeConstValue;
    property ExpressionTypeKey: TEdit read FExpressionTypeKey;
    /// <summary>Zum Testen: Methodenrümpfe in Deklarationsreihenfolge (#660).</summary>
    property MethodPlacementBox: TAtlasChoiceBox read FMethodPlacement;
    property RecursionMarkersDepthEdit: TEdit read FRecursionMarkersDepth;
    property DataFlowCheck: TCheckBox read FDataFlow;
    property DataFlowMaxDepthEdit: TEdit read FDataFlowMaxDepth;
    property DataFlowExcludeTestsCheck: TCheckBox read FDataFlowExcludeTests;
    property HideElementKey: TEdit read FHideElementKey;
    /// <summary>Zum Testen: Fehlertext am Zeilenende, Zähler und Sprungtasten (#509).</summary>
    property InlineDiagnostics: TAtlasChoiceBox read FInlineDiagnostics;
    property ProblemsStatusCounterCheck: TCheckBox read FProblemsStatusCounter;
    property NextProblemKey: TEdit read FNextProblemKey;
    property PreviousProblemKey: TEdit read FPreviousProblemKey;
    property ProblemsWindowKey: TEdit read FProblemsWindowKey;
    property CreateIssueKey: TEdit read FCreateIssueKey;
    /// <summary>Zum Testen: Prüffenster und Seite Prüfregeln (#909).</summary>
    property ProblemsWindowCheck: TCheckBox read FProblemsWindow;
    property ArchitectureCheck: TCheckBox read FArchitecture;
    property ArchitectureScopeChoice: TAtlasChoiceBox read FArchitectureScope;
    property ArchitectureCentralEdit: TEdit read FArchitectureCentral;
    property ProblemsWindowScopeChoice: TAtlasChoiceBox read FProblemsWindowScope;
    property ProblemsWindowGroupByChoice: TAtlasChoiceBox read FProblemsWindowGroupBy;
    property ProblemsWindowCompilerCheck: TCheckBox read FProblemsWindowCompiler;
    property ProblemsWindowFollowCursorCheck: TCheckBox read FProblemsWindowFollowCursor;
    property ProblemsWindowOpenFirstCheck: TCheckBox read FProblemsWindowOpenFirst;
    property ProblemsWindowClosedUnitsChoice: TAtlasChoiceBox read FProblemsWindowClosedUnits;
    property ProblemsWindowShowCleanActiveCheck: TCheckBox read FProblemsWindowShowCleanActive;
    property ProblemsLiveCheck: TCheckBox read FProblemsLive;
    property ProblemsCompilerMergeChoice: TAtlasChoiceBox read FProblemsCompilerMerge;
    property ProblemsShowCompilerCodeCheck: TCheckBox read FProblemsShowCompilerCode;
    property HoverProblemActionsCheck: TCheckBox read FHoverProblemActions;
    property RulesProjectButton: TButton read FRulesProject;
    property RulesGlobalButton: TButton read FRulesGlobal;
    /// <summary>„Projekt-Prüfregeln bearbeiten …“: Projektdialog öffnen.</summary>
    property OnRulesProject: TProc read FOnRulesProject write FOnRulesProject;
    /// <summary>„Globale Prüfregeln bearbeiten …“: Dialog der globalen Einstellungen öffnen.</summary>
    property OnRulesGlobal: TProc read FOnRulesGlobal write FOnRulesGlobal;
    /// <summary>Baseline des aktiven Projekts: Text, neu erzeugen, löschen (Ergebnis als Text).</summary>
    property OnBaselineInfo: TFunc<string> read FOnBaselineInfo write SetOnBaselineInfo;
    property OnBaselineUpdate: TFunc<string> read FOnBaselineUpdate write FOnBaselineUpdate;
    property OnBaselineDelete: TFunc<string> read FOnBaselineDelete write FOnBaselineDelete;
    property BaselineInfoLabel: TLabel read FBaselineInfo;
    /// <summary>Zum Testen: Erzeugen-Menü (#719).</summary>
    property GenerateMenuCheck: TCheckBox read FGenerateMenu;
    property GenerateMenuKey: TEdit read FGenerateMenuKey;
    property GenerateMenuGroups: TEdit read FGenerateMenuGroups;
    property GenerateMenuHidden: TEdit read FGenerateMenuHidden;
    property GenerateMenuRecentFirstCheck: TCheckBox read FGenerateMenuRecentFirst;
    property GenerateMenuShowCommandNamesCheck: TCheckBox read FGenerateMenuShowCommandNames;
    property FavoritesList: TListBox read FFavoritesList;
    property FavoritesRemove: TButton read FFavoritesRemove;
    property FavoritesRemoveAll: TButton read FFavoritesRemoveAll;
    /// <summary>„Zählung zurücksetzen“ der Nutzung je Befehl (#757).</summary>
    property OnResetUsage: TProc read FOnResetUsage write FOnResetUsage;
    /// <summary>Befehle für „Leiste anpassen …“ der Editorleiste (#1101): Atlas-Befehle der Palette.</summary>
    property OnToolbarCommands: TFunc<TArray<TAtlasToolbarCommandInfo>> read FOnToolbarCommands
      write FOnToolbarCommands;
    /// <summary>„Gesperrte Tipps wieder zeigen“ der Karte „Atlas entdecken“ (#757).</summary>
    property OnUnblockTips: TProc read FOnUnblockTips write FOnUnblockTips;
    /// <summary>Projektdatei .atlas des aktiven Projekts (#486) für die Anzeige „aus .atlas“; nil = keine.</summary>
    property OnTeamFile: TFunc<TAtlasTeamSettings> read FOnTeamFile write SetOnTeamFile;
    /// <summary>„Projektdatei öffnen“: anlegen, falls es sie nicht gibt, und im Editor öffnen (#486).</summary>
    property OnOpenTeamFile: TProc read FOnOpenTeamFile write FOnOpenTeamFile;
    /// <summary>Anzeige der Projektdatei neu aufbauen (#486).</summary>
    procedure RefreshTeamFile;
    /// <summary>Tracker-Verbindungen (#1260): Zustand je Server (ohne Netz); nil = „fehlt“.</summary>
    property OnTrackerState: TAtlasTrackerStateEvent read FOnTrackerState write FOnTrackerState;
    /// <summary>„Token hinterlegen …“ für die gewählte Verbindung; danach RefreshTrackerConnections.</summary>
    property OnTrackerToken: TAtlasTrackerConnectionEvent read FOnTrackerToken write FOnTrackerToken;
    /// <summary>„Verbindung prüfen“ im Hintergrund; das Ergebnis meldet TrackerCheckDone.</summary>
    property OnTrackerCheck: TAtlasTrackerConnectionEvent read FOnTrackerCheck write FOnTrackerCheck;
    /// <summary>Vor dem Entfernen einer Verbindung: fragt, ob das Token mit entfernt werden soll.</summary>
    property OnTrackerRemove: TAtlasTrackerConnectionEvent read FOnTrackerRemove write FOnTrackerRemove;
    /// <summary>„Testen“ im Dialog „Abfrage bearbeiten“ (#1263); nil = Knopf gesperrt.</summary>
    property OnTrackerQueryTest: TAtlasQueryTestEvent read FOnTrackerQueryTest write FOnTrackerQueryTest;
    /// <summary>Statt des Dialogs (Tests); nil = TAtlasTrackerQueryDialog.</summary>
    property OnTrackerQueryEdit: TAtlasTrackerQueryEditEvent read FOnTrackerQueryEdit write FOnTrackerQueryEdit;
    /// <summary>Verbindung aus der .atlas des aktiven Projekts; leer ohne.</summary>
    property OnTrackerTeam: TFunc<TArray<TAtlasTrackerConnection>> read FOnTrackerTeam write FOnTrackerTeam;
    /// <summary>„Werte vom Tracker laden“ (#1266) im Hintergrund; das Ergebnis meldet TrackerValuesDone.</summary>
    property OnTrackerValues: TAtlasTrackerValuesEvent read FOnTrackerValues write FOnTrackerValues;
    /// <summary>Anbieter der Auswahl (Name wie in issues.connections, Anzeigename); Vorgabe YouTrack und GitHub.
    /// </summary>
    procedure SetTrackerProviders(const ANames, ACaptions: TArray<string>);
    /// <summary>Tabelle der Verbindungen neu aufbauen (Zustand, .atlas); ohne Fenster folgt es in CreateWnd.
    /// </summary>
    procedure RefreshTrackerConnections;
    /// <summary>Prüfung von AConnection ist fertig; der Zustand kommt über OnTrackerState.</summary>
    procedure TrackerCheckDone(const AConnection: TAtlasTrackerConnection);
    /// <summary>Tabelle Projekte (#1261): aktives Projekt, geöffnete .groupproj und Zeile aus der .atlas; nil =
    /// ohne Projekt.</summary>
    property OnTrackerContext: TFunc<TAtlasTrackerProjectContext> read FOnTrackerContext write FOnTrackerContext;
    /// <summary>„Hinzufügen …“ (#1261); nil = Datei- bzw. Ordnerauswahl von Windows.</summary>
    property OnTrackerBrowse: TAtlasTrackerBrowseEvent read FOnTrackerBrowse write FOnTrackerBrowse;
    /// <summary>Tabelle Projekte neu aufbauen (Kontext, Verbindungen); ohne Fenster folgt es in CreateWnd.</summary>
    procedure RefreshTrackerProjects;
    /// <summary>„zuordnen …“ aus „Meine Issues“ (#1261): Zeile für AMatch anlegen bzw. wählen und zeigen.</summary>
    procedure AssignTrackerProject(const AMatch: string);
    /// <summary>Tabelle Abfragen neu aufbauen (Auswahl der Verbindungen); ohne Fenster folgt es in CreateWnd.
    /// </summary>
    procedure RefreshTrackerQueries;
    /// <summary>Versionsverwaltung (#1285): Fundort ohne Prozess für den eingetragenen Pfad; nil = keine Anzeige.
    /// </summary>
    property OnVcsLocate: TAtlasVcsLocateEvent read FOnVcsLocate write FOnVcsLocate;
    /// <summary>„Prüfen“ im Hintergrund; das Ergebnis meldet VcsCheckDone.</summary>
    property OnVcsCheck: TAtlasVcsCheckEvent read FOnVcsCheck write FOnVcsCheck;
    /// <summary>„Aktuelles Projekt“ im Hintergrund abfragen; das Ergebnis meldet VcsProjectDone.</summary>
    property OnVcsProject: TProc read FOnVcsProject write FOnVcsProject;
    /// <summary>Tabelle Projekte (#1286): aktives Projekt, geöffnete .groupproj und Zeile aus der .atlas; nil =
    /// ohne Projekt.</summary>
    property OnVcsContext: TFunc<TAtlasVcsProjectContext> read FOnVcsContext write FOnVcsContext;
    /// <summary>Tabelle Projekte der Versionsverwaltung neu aufbauen; ohne Fenster folgt es in CreateWnd.
    /// </summary>
    procedure RefreshVcsProjects;
    /// <summary>Tabelle „Server“ (#1287): Zeile je Projekt (aktuelles Projekt, Zeilen der Tabelle Projekte), je
    /// Ordner einmal; Zustand aus OnVcsServerState. Ohne Fenster folgt es in CreateWnd.</summary>
    procedure RefreshVcsServers;
    /// <summary>„Anmeldung am Server nötig – prüfen …“ (#1287): Zeile für AFolder zeigen (auch ohne Zeile in der
    /// Tabelle Projekte), wählen und prüfen.</summary>
    procedure RevealVcsServer(const AFolder: string);
    /// <summary>Ergebnis einer Prüfung für AFolder zeigen.</summary>
    procedure VcsServerDone(const AFolder: string; const ACheck: TAtlasVcsServerCheck);
    /// <summary>Letztes Ergebnis je Ordner aus dieser Sitzung; nil = „nicht geprüft“.</summary>
    property OnVcsServerState: TFunc<string, TAtlasVcsServerCheck> read FOnVcsServerState write FOnVcsServerState;
    /// <summary>„Prüfen“ im Hintergrund; nil = Knöpfe gesperrt.</summary>
    property OnVcsServerCheck: TAtlasVcsServerCheckEvent read FOnVcsServerCheck write FOnVcsServerCheck;
    property OnVcsServerLogin: TAtlasVcsServerLoginEvent read FOnVcsServerLogin write FOnVcsServerLogin;
    /// <summary>Ergebnis von „Prüfen“ zeigen.</summary>
    procedure VcsCheckDone(const ACheck: TAtlasVcsToolCheck);
    /// <summary>Ergebnis der Abfrage „Aktuelles Projekt“ zeigen.</summary>
    procedure VcsProjectDone(const AState: TAtlasVcsProjectState);
    /// <summary>„Aktuelles Projekt“ jetzt abfragen (sonst beim ersten Zeigen der Seite).</summary>
    procedure RefreshVcsProject;
    /// <summary>Fundort als Text: „PATH“, „bekannter Ordner“, „eigener Pfad“.</summary>
    class function VcsSourceText(ASource: TAtlasVcsToolSource): string; static;
    /// <summary>Zustand ohne Prozess: „verwendet: <Pfad> (PATH)“, „fehlt“, „fehlt: <Pfad> …“.</summary>
    class function VcsLocationText(const ALocation: TAtlasVcsToolLocation): string; static;
    /// <summary>Ergebnis von „Prüfen“: „gefunden · git version 2.47.1 · <Pfad> (PATH)“ usw.</summary>
    class function VcsCheckText(const ACheck: TAtlasVcsToolCheck): string; static;
    /// <summary>Gruppe „Aktuelles Projekt“: Projekt, Art, Wurzel, Branch bzw. SVN-Pfad, Revision, verfolgter
    /// Branch und woher die Art kommt; mehrere Zeilen.</summary>
    class function VcsProjectText(const AState: TAtlasVcsProjectState): string; static;
    /// <summary>Zum Testen: Versionsverwaltung (#1285).</summary>
    property VcsProviderChoice: TAtlasChoiceBox read FVcsProvider;
    property VcsTimeout: TEdit read FVcsTimeout;
    /// <summary>Zum Testen: vcs.branch.confirm (#1288).</summary>
    property VcsBranchConfirm: TCheckBox read FVcsBranchConfirm;
    /// <summary>Zum Testen: vcs.branch.svn.* (#1290).</summary>
    property VcsBranchSvnLocation: TEdit read FVcsBranchSvnLocation;
    property VcsBranchSvnSource: TAtlasChoiceBox read FVcsBranchSvnSource;
    property VcsBranchSvnAfter: TAtlasChoiceBox read FVcsBranchSvnAfter;
    property VcsBranchSvnFolder: TEdit read FVcsBranchSvnFolder;
    property VcsBranchSvnMessage: TEdit read FVcsBranchSvnMessage;
    /// <summary>Zum Testen: vcs.externals.* (#1291).</summary>
    property VcsExternalsOnBranch: TAtlasChoiceBox read FVcsExternalsOnBranch;
    property VcsExternalsSuggest: TAtlasChoiceBox read FVcsExternalsSuggest;
    property VcsExternalsRules: TMemo read FVcsExternalsRules;
    property VcsExternalsRulesError: TLabel read FVcsExternalsRulesError;
    property VcsExternalsShow: TCheckBox read FVcsExternalsShow;
    property VcsExternalsUpdate: TAtlasChoiceBox read FVcsExternalsUpdate;
    /// <summary>Zum Testen: vcs.branch.git.* (#1289); Auswahl in der Reihenfolge der Werte im Schema.</summary>
    property VcsBranchGitBase: TAtlasChoiceBox read FVcsBranchGitBase;
    property VcsBranchGitPush: TAtlasChoiceBox read FVcsBranchGitPush;
    property VcsBranchGitUncommitted: TAtlasChoiceBox read FVcsBranchGitUncommitted;
    property VcsBranchGitWorktree: TCheckBox read FVcsBranchGitWorktree;
    property VcsBranchGitWorktreeFolder: TEdit read FVcsBranchGitWorktreeFolder;
    property VcsProjectInfo: TLabel read FVcsProjectInfo;
    property VcsLinkEditor: TButton read FVcsLinkEditor;
    property VcsLinkWelcome: TButton read FVcsLinkWelcome;
    property VcsLinkIssues: TButton read FVcsLinkIssues;
    /// <summary>Zum Testen: Art und Hauptbranch je Projekt (#1286).</summary>
    property VcsProjectList: TListView read FVcsProjectList;
    property VcsProjectMatch: TEdit read FVcsProjectMatch;
    property VcsProjectProvider: TAtlasChoiceBox read FVcsProjectProvider;
    property VcsProjectMainBranch: TEdit read FVcsProjectMainBranch;
    property VcsProjectNote: TLabel read FVcsProjectNote;
    property VcsProjectAddCurrent: TButton read FVcsProjectAddCurrent;
    property VcsProjectAdd: TButton read FVcsProjectAdd;
    property VcsProjectRemove: TButton read FVcsProjectRemove;
    property VcsProjectAddMenu: TPopupMenu read FVcsProjectAddMenu;
    /// <summary>Persönliche Zeilen, wie die Seite sie gerade zeigt.</summary>
    property VcsProjects: TArray<TAtlasVcsProjectMapping> read FVcsProjects;
    /// <summary>Zum Testen: Serverzugang (#1287).</summary>
    property VcsServerList: TListView read FVcsServerList;
    property VcsServerCheck: TButton read FVcsServerCheck;
    property VcsServerCheckAll: TButton read FVcsServerCheckAll;
    property VcsServerLogin: TButton read FVcsServerLogin;
    property VcsServerNote: TLabel read FVcsServerNote;
    property VcsServerRows: TArray<TAtlasVcsServerRow> read FVcsServerRows;
    /// <summary>Spalte Zustand: „nicht geprüft“, „wird geprüft …“, „erreichbar · geprüft 14:05“, „Anmeldung nötig“ …
    /// </summary>
    class function VcsServerStateText(const ACheck: TAtlasVcsServerCheck; AChecking: Boolean): string; static;
    /// <summary>Art und Name der Art („Automatisch“, „Git“, „SVN“, „Aus“) zu "auto", "git", "svn", "off".
    /// </summary>
    class function VcsProviderCaption(const AProvider: string): string; static;
    function VcsPath(AKind: TAtlasVcsKind): TEdit;
    function VcsCheckButton(AKind: TAtlasVcsKind): TButton;
    function VcsState(AKind: TAtlasVcsKind): TLabel;
    /// <summary>Werte vom Tracker sind da (#1266): AError '' = geladen, sonst der Grund für die Zeile unter dem Knopf.
    /// </summary>
    procedure TrackerValuesDone(const AValues: TAtlasTrackerValueSet; const AError: string);
    /// <summary>Zum Testen: Projektdatei (#486).</summary>
    property TeamFileCheck: TCheckBox read FTeamFile;
    property TeamFileInfo: TLabel read FTeamFileInfo;
    property TeamFileOpenButton: TButton read FTeamFileOpen;
    property TeamSnippetsLabel: TLabel read FTeamSnippets;
    /// <summary>Server, der bei leerem Pfad gilt (für die Anzeige „Verwendet: …“).</summary>
    property DefaultServerPath: string read FDefaultServerPath write SetDefaultServerPath;
    /// <summary>Version des Servers unter dem Pfad als Text ('' = unbekannt); nil = keine Anzeige.</summary>
    property OnServerVersion: TFunc<string, string> read FOnServerVersion write SetOnServerVersion;
    /// <summary>Zum Testen: Optionen aus ARG-046.</summary>
    property CommitChars: TCheckBox read FCommitChars;
    property AutoUses: TCheckBox read FAutoUses;
    property ParameterHints: TCheckBox read FParameterHints;
    property FormatPlaceholders: TCheckBox read FFormatPlaceholders;
    property OpenDelay: TEdit read FOpenDelay;
    property AutoWidth: TCheckBox read FAutoWidth;
    property Symbol: TAtlasSymbolImage read FSymbol;
    property ServerVersion: TLabel read FServerVersion;
  end;

implementation

{$R *.dfm}

uses
  System.Math,
  System.StrUtils,
  Atlas.UI.Settings.QueryDialog,
  Atlas.Core.Build.Gate,
  Atlas.Core.Build.Verdict,
  Atlas.Core.Debug.OwnCode,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Projects.Matching,
  Atlas.Core.Problems.InlineHints,
  Atlas.Core.Product.Version,
  Atlas.Core.Updates.Check,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Undo.Names,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.Core.Welcome.Trends,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Build.OpenBuild,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Settings.Transfer,
  Atlas.Core.Settings.Experimental,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.Settings.StatusBarItems,
  Atlas.UI.Notifications.Window;

const
  /// <summary>Werte von vcs.branch.git.base, .push und .uncommitted (#1289) in der Reihenfolge der Auswahl.
  /// </summary>
  cVcsGitBases: array[0..2] of string = ('remote', 'local', 'current');
  cVcsGitPushes: array[0..1] of string = ('later', 'now');
  cVcsGitUncommitted: array[0..2] of string = ('carry', 'stash', 'ask');

/// <summary>Bezeichnung einer Reihe des Projektverlaufs (#758) wie auf ihrer Kachel.</summary>
function QuickActionTitle(AAction: TAtlasQuickAction): string;
begin
  // Beschriftung des Knopfs ohne „ ▾“ (#764).
  case AAction of
    TAtlasQuickAction.Build:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickBuild);
    TAtlasQuickAction.Tests:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickTests);
    TAtlasQuickAction.Run:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickRun);
    TAtlasQuickAction.Pull:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickPull);
    TAtlasQuickAction.Folder:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickFolder);
    TAtlasQuickAction.Tasks:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickTasks);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickConsole);
  end;
  Result := Trim(StringReplace(Result, #$25BE, '', [rfReplaceAll]));
end;

function TrendSeriesTitle(ASeries: TAtlasTrendSeries): string;
begin
  case ASeries of
    TAtlasTrendSeries.Warnings:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsWarnings);
    TAtlasTrendSeries.RuleHits:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsRuleHits);
    TAtlasTrendSeries.Todos:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsTodos);
    TAtlasTrendSeries.Duration:
      Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsDuration);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.WelcomeTrendsMethodLength);
  end;
end;

{ TAtlasChoiceBox }

constructor TAtlasChoiceBox.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Style := csDropDownList;
  FChoice := -1;
end;

procedure TAtlasChoiceBox.SetChoices(const AItems: array of string);
var
  Index: Integer;
begin
  SetLength(FChoices, Length(AItems));
  for Index := 0 to High(AItems) do
    FChoices[Index] := AItems[Index];
  if HandleAllocated then
  begin
    Items.Clear;
    for Index := 0 to High(FChoices) do
      Items.Add(FChoices[Index]);
    ItemIndex := FChoice;
  end;
end;

procedure TAtlasChoiceBox.CreateWnd;
var
  Item: string;
begin
  inherited CreateWnd;
  if Items.Count = 0 then
    for Item in FChoices do
      Items.Add(Item);
  ItemIndex := FChoice;
end;

procedure TAtlasChoiceBox.DestroyWnd;
begin
  // Auswahl sichern, bevor das Fenster wegfällt (RecreateWnd); CreateWnd setzt sie wieder. So ändert der
  // Getter nichts (getter-side-effect, #1052).
  FChoice := ItemIndex;
  inherited DestroyWnd;
end;

function TAtlasChoiceBox.GetChoice: Integer;
begin
  if HandleAllocated then
    Result := ItemIndex
  else
    Result := FChoice;
end;

procedure TAtlasChoiceBox.SetChoice(AValue: Integer);
begin
  FChoice := AValue;
  if HandleAllocated then
    ItemIndex := AValue;
end;

{ TAtlasSettingsRow }

constructor TAtlasSettingsRow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csAcceptsControls, csParentBackground] - [csOpaque];
  ParentBackground := True;
  ParentColor := True;
end;

const
  // Linke Kante der Eingabefelder; Platz für die längste Beschriftung („Breite der Blocklinien …“).
  FieldLeft = 280;
  /// <summary>Werte von problems.window.scope und problems.window.groupBy in der Reihenfolge der Auswahl (#909).
  /// </summary>
  ScopeValues: array[0..2] of string = ('file', 'project', 'group');
  GroupByValues: array[0..3] of string = ('none', 'file', 'rule', 'category');
  /// <summary>Werte von problems.window.closedUnits in der Reihenfolge der Auswahl (#1108).</summary>
  ClosedUnitsValues: array[0..2] of string = ('dimmed', 'normal', 'hidden');
  /// <summary>Werte von problems.compilerMerge in der Reihenfolge der Auswahl (#1024).</summary>
  CompilerMergeValues: array[0..1] of string = ('merge', 'both');

const
  // Reihenfolge der Auswahllisten von „Units suchen“ (#777) wie die Werte der Einstellungen.
  UnitSearchPathStyles: array[0..2] of string = ('relative', 'compact', 'absolute');
  UnitSearchGroupings: array[0..2] of string = ('project', 'folder', 'none');
  UnitSearchScopes: array[0..3] of string = ('group', 'project', 'searchPath', 'library');

function ChoiceOf(const AValue: string; const AValues: array of string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(AValues) do
    if SameText(AValues[Index], AValue) then
      Exit(Index);
  Result := 0;
end;

{ TAtlasSettingsPage }

constructor TAtlasSettingsPage.Create(AOwner: TComponent);
var
  Panel: TWinControl;
  Title: TLabel;
  Button: TButton;
begin
  inherited Create(AOwner);
  FAttached := TDictionary<TControl, TControl>.Create;
  FOwnOff := TList<TControl>.Create;
  FLockedControls := TList<TControl>.Create;
  Name := 'AtlasSettingsPage';
  Width := 480;
  // Die Reiter tragen den Inhalt; scrollt die Seite selbst, springt sie beim Reiterwechsel zum Fokus.
  AutoScroll := False;
  // Mit Reitern reicht die Höhe des längsten Reiters; höher, und die IDE scrollt ihren Bereich beim
  // Reiterwechsel zum Fokus (die Seite „springt“).
  Height := 440;
  // Kopf mit Symbol (#751) und Titel.
  Panel := TAtlasSettingsRow.Create(Self);
  Panel.Parent := Self;
  Panel.Align := alTop;
  Panel.Height := 40;
  FSymbol := TAtlasSymbolImage.Create(Self);
  FSymbol.Parent := Panel;
  FSymbol.LogicalSize := TAtlasSymbol.HeaderSize;
  FSymbol.Left := 4;
  FSymbol.Top := 4;
  Title := TLabel.Create(Self);
  Title.Parent := Panel;
  Title.Left := 44;
  Title.Top := 12;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsTitle);
  Title.Font.Style := [fsBold];
  AddExperimentalBanner;
  // Reiter je Bereich (#227); jeder stapelt seine Elemente neu von oben. Viele Reiter: in Zeilen.
  // Bereiche und Unterpunkte als Baum links (#890); die Reiter selbst bleiben unsichtbar, der Baum schaltet sie um.
  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alLeft;
  FTree.AlignWithMargins := True;
  FTree.Width := 170;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.OnChange := TreeChange;
  FTree.OnExpanded := TreeExpanded;
  FTree.OnCollapsed := TreeExpanded;
  FTree.OnCustomDrawItem := TreeCustomDrawItem;
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.AlignWithMargins := True;
  FPages.Top := 100;

  AddSheet(TAtlasTextId.SettingsTabGeneral);
  FEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEnabled));
  // Wo der Server liegt; leer gilt der Standard neben dem Plugin.
  Panel := AddPanel(20);
  Title := TLabel.Create(Self);
  Title.Parent := Panel;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsServerPath);
  Title.Left := 0;
  Title.Top := 3;
  // Pfad in eigener Zeile: Die Beschriftung ist lang, das Feld braucht die Breite.
  Panel := AddPanel(26);
  FServerPath := TEdit.Create(Self);
  FServerPath.Parent := Panel;
  FServerPath.Left := 0;
  FServerPath.Top := 1;
  FServerPath.Width := 430;
  FServerPath.Anchors := [akLeft, akTop, akRight];
  FServerPath.OnChange := ServerPathChange;
  FServerBrowse := TButton.Create(Self);
  FServerBrowse.Parent := Panel;
  FServerBrowse.Caption := '…';
  FServerBrowse.Left := 436;
  FServerBrowse.Top := 0;
  FServerBrowse.Width := 30;
  FServerBrowse.Anchors := [akTop, akRight];
  FServerBrowse.OnClick := ServerBrowseClick;
  Panel := AddPanel(18);
  FServerStatus := TLabel.Create(Self);
  FServerStatus.Parent := Panel;
  FServerStatus.Left := 0;
  FServerStatus.Top := 0;
  FServerStatus.Font.Color := clGrayText;
  Panel := AddPanel(18);
  FServerVersion := TLabel.Create(Self);
  FServerVersion.Parent := Panel;
  FServerVersion.Left := 0;
  FServerVersion.Top := 0;
  FServerVersion.Font.Color := clGrayText;
  FReloadExternal := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReload));
  // Änderungen des Servers an nicht geöffneten Dateien (#397).
  FOpenForEdits := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOpenForEdits));
  // Atlas-Statusfeld (#591).
  FStatusField := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStatusField));
  FStatusSummary := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStatusSummary));
  FStatusToggles := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsStatusToggles),
    [TAtlasStrings.Text(TAtlasTextId.SettingsStatusTogglesBoth),
    TAtlasStrings.Text(TAtlasTextId.SettingsStatusTogglesRight),
    TAtlasStrings.Text(TAtlasTextId.SettingsStatusTogglesDouble)]);
  FIndexProgress := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsIndexProgress),
    [TAtlasStrings.Text(TAtlasTextId.SettingsIndexProgressField),
    TAtlasStrings.Text(TAtlasTextId.SettingsIndexProgressMenu),
    TAtlasStrings.Text(TAtlasTextId.SettingsIndexProgressOff)]);
  FStatusHidden := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsStatusHidden));
  FStatusHidden.NumbersOnly := False;
  FStatusHidden.Width := 180;
  // Diagnosemodus (#479); Taste auf der Seite „Tastenkonflikte“.
  FDiagnosticMode := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDiagnosticMode));
  // Menüeintrag „Prozesse am Projekt…“ (#62).
  FDiagnosticsProcesses := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDiagnosticsProcesses));
  // Architekturübersicht (#1118): Unterpunkt „Architektur“ über x-node; Reihenfolge wie die Werte von
  // architecture.scope (projectGroup, project).
  FArchitecture := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsArchitecture));
  FArchitectureScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsArchitectureScope),
    [TAtlasStrings.Text(TAtlasTextId.ArchitectureScopeGroup), TAtlasStrings.Text(TAtlasTextId.ArchitectureScopeProject)]);
  FArchitectureLibrary := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsArchitectureLibrary));
  FArchitectureCentral := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsArchitectureCentral));
  // Prüfliste der Einrichtung beim Start (#625); aus: nur auf Abruf.
  FSetupChecklist := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSetupChecklist));
  // Hauptschalter der experimentellen Funktionen (#834).
  FExperimentalEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExperimentalEnabled));
  // Tastenkürzel-Tipps (#600); Reihenfolge wie TAtlasTipScope: atlas, all.
  FShortcutTips := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsShortcutTips));
  FShortcutTipsScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsShortcutTipsScope),
    [TAtlasStrings.Text(TAtlasTextId.SettingsShortcutTipsAtlas), TAtlasStrings.Text(TAtlasTextId.SettingsShortcutTipsAll)]);
  // Benachrichtigungszentrale (#601); Taste auf dem Reiter Befehle.
  FNotifications := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsNotifications));
  FNotificationsMax := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsNotificationsMax));
  AddNotificationSources;
  // Einstellungen exportieren, importieren und zurücksetzen (#723).
  AddTransferSection;

  // Liste der Vervollständigung.
  AddSheet(TAtlasTextId.SettingsTabCompletion);
  Panel := AddPanel(26);
  FRowsLabel := TLabel.Create(Self);
  FRowsLabel.Parent := Panel;
  FRowsLabel.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsRows);
  FRowsLabel.Left := 0;
  FRowsLabel.Top := 5;
  FRows := TEdit.Create(Self);
  FRows.Parent := Panel;
  FRows.Left := FieldLeft;
  FRows.Top := 1;
  FRows.Width := 44;
  FRows.NumbersOnly := True;
  FRowsUpDown := TUpDown.Create(Self);
  FRowsUpDown.Parent := Panel;
  FRowsUpDown.Associate := FRows;
  FRowsUpDown.Min := TAtlasPluginSettings.MinVisibleRows;
  FRowsUpDown.Max := TAtlasPluginSettings.MaxVisibleRows;
  FAutoWidth := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsAutoWidth));
  FAutoWidth.OnClick := AutoWidthClick;
  FOpenDelay := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsOpenDelay));
  FPanelCollapsed := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPanelCollapsed));
  FSelectionMarker := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMarker));
  FFilterChips := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsChips));
  FLearning := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsLearning));
  FFavorites := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsFavorites));
  FGroupInherited := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGroupInherited));
  FCompletionVariantBranch := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCompletionVariantBranch));
  // In der Reihenfolge von TAtlasListMode bzw. TAtlasListScope.
  FListMode := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsListMode),
    [TAtlasStrings.Text(TAtlasTextId.SettingsListModeFilter), TAtlasStrings.Text(TAtlasTextId.SettingsListModeAll),
    TAtlasStrings.Text(TAtlasTextId.SettingsListModeRest)]);
  FListScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsListScope),
    [TAtlasStrings.Text(TAtlasTextId.SettingsListScopeMembers),
    TAtlasStrings.Text(TAtlasTextId.SettingsListScopeEverywhere)]);
  FPreview := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPreview));
  Panel := AddPanel(32);
  FResetHistory := TButton.Create(Self);
  FResetHistory.Parent := Panel;
  FResetHistory.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsResetHistory);
  FResetHistory.Left := 0;
  FResetHistory.Top := 3;
  FResetHistory.Width := 150;
  FResetHistory.OnClick := ResetHistoryClick;
  FResetWidths := TButton.Create(Self);
  FResetWidths.Parent := Panel;
  FResetWidths.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsResetWidths);
  FResetWidths.Left := 160;
  FResetWidths.Top := 3;
  FResetWidths.Width := 150;
  FResetWidths.OnClick := ResetWidthsClick;
  AddFavoritesSection;

  // Was beim Übernehmen eingefügt wird.
  AddSheet(TAtlasTextId.SettingsTabInsert);
  FAutoParentheses := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsParentheses));
  FFixCase := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsFixCase));
  FCommitChars := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCommitChars));
  FAutoUses := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsAutoUses));
  FParameterHints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsParameterHints));
  FFormatPlaceholders := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsFormatPlaceholders));
  // Code-Vorlagen (#51).
  FSnippets := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSnippets));
  FImportIdeTemplates := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsImportIdeTemplates));
  // Vorlagen aus der Projektdatei (#486); leer ohne .atlas.
  FTeamSnippets := AddWrappedLabel(20, '');

  AddSheet(TAtlasTextId.SettingsTabEditor);
  FHoverTooltip := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHover));
  // Aktionszeile unter Befunden im Hover (#909).
  FHoverProblemActions := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHoverProblemActions));
  // XMLDoc in Tooltip und Detailpanel (#654, #770): zu- oder aufgeklappt beim Öffnen; gespeichert in
  // settings.json (hints.*, #227).
  FXmlDocExpand := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocExpand),
    [TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocCollapsed), TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocLast),
    TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocExpanded)]);
  FXmlDocMaxLines := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocMaxLines));
  FPairColors := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairs));
  FPairGuides := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuides));
  // Anweisungen mitfärben, Linienbreite und Deckkraft (#653); wirken nur mit der Paarfärbung.
  FPairOwners := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairOwners));
  FPairGuideWidth := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuideWidth));
  FPairGuideOpacity := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuideOpacity));
  FInactiveDim := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInactiveDim));
  FInlayHints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayHints));
  // Typmarken von Inline-Variablen (#453), unabhängig von den Parameternamen.
  FInlayTypeHints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayTypeHints));
  // Symbole aus Include-Dateien hinter {$I} (#860).
  FInlayDefineHints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayDefineHints));
  // Code hinter Steuerzeichen wie ^C (#862).
  FInlayCharHints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayCharHints));
  // Marke „ohne Self“ hinter Methoden, die Self nicht brauchen (#686).
  FInlayMethodHints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayMethodHints));
  // Beschriftung hinter dem end langer Blöcke (#620).
  FBlockEndLabels := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBlockEndLabels));
  FBlockEndLabelsMinLines := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsBlockEndLabelsMinLines));
  FDimUnusedUses := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDimUnusedUses));
  // Brotkrumenleiste (#590).
  FBreadcrumbs := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBreadcrumbs));
  FBreadcrumbsShowUnit := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBreadcrumbsShowUnit));
  FBreadcrumbsIdeColors := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBreadcrumbsIdeColors));
  FBreadcrumbsHideIdeToolbar := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBreadcrumbsHideIdeToolbar));
  FBreadcrumbsKey := AddKey(TAtlasStrings.Text(TAtlasTextId.BreadcrumbsCommand));
  // Atlas-Editorleiste (#1101).
  FEditorToolbar := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEditorToolbar));
  FEditorToolbarPosition := AddChoice(TAtlasStrings.Text(TAtlasTextId.EditorToolbarPosition),
    [TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionBelow),
    TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionAbove),
    TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionInline)]);
  FEditorToolbarItems := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsEditorToolbarItems));
  Panel := AddPanel(32);
  FEditorToolbarCustomize := TButton.Create(Self);
  FEditorToolbarCustomize.Parent := Panel;
  FEditorToolbarCustomize.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsEditorToolbarCustomize);
  FEditorToolbarCustomize.Left := 0;
  FEditorToolbarCustomize.Top := 3;
  FEditorToolbarCustomize.Width := 180;
  FEditorToolbarCustomize.OnClick := EditorToolbarCustomizeClick;
  Attach(Panel, FEditorToolbarItems);
  FEditorToolbarReturnButton := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEditorToolbarReturnButton));
  FEditorToolbarLabels := AddCheck(TAtlasStrings.Text(TAtlasTextId.EditorToolbarLabels));
  // Atlas-Statusleiste unten im Editorfenster (#1155).
  FEditorStatusBar := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEditorStatusBar));
  FEditorStatusBarItems := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsEditorStatusBarItems));
  // Aufrufdiagramm (#1122).
  FCallHierarchyDiagram := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCallHierarchyDiagram));
  // Mitlaufender Kopf (#506, experimentell).
  FStickyScroll := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScroll));
  FStickyScrollMaxLines := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollMaxLines));
  // Minimap neben der Scrollleiste (#873, experimentell).
  FMinimap := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMinimap));
  FMinimapRender := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapRender),
    [TAtlasStrings.Text(TAtlasTextId.SettingsMinimapBlocks), TAtlasStrings.Text(TAtlasTextId.SettingsMinimapCharacters)]);
  FMinimapWidth := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapWidth));
  FMinimapScale := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapScale));
  FMinimapMaxColumn := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapMaxColumn));
  FMinimapSide := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapSide),
    [TAtlasStrings.Text(TAtlasTextId.SettingsMinimapRight), TAtlasStrings.Text(TAtlasTextId.SettingsMinimapLeft)]);
  FMinimapShowSlider := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapSlider),
    [TAtlasStrings.Text(TAtlasTextId.SettingsMinimapSliderAlways),
    TAtlasStrings.Text(TAtlasTextId.SettingsMinimapSliderHover)]);
  FMinimapSectionHeaders := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapHeaders));
  FMinimapHighlightMethod := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapMethod));
  FMinimapMarkers := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapMarkers));
  FMinimapClickJumps := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapClickJumps));
  // Änderungsmarken und Zeilenhistorie (#507).
  FGitGutter := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGitGutter));
  FNextChangeKey := AddKey(TAtlasStrings.Text(TAtlasTextId.NextChangeCommand));
  FPreviousChangeKey := AddKey(TAtlasStrings.Text(TAtlasTextId.PreviousChangeCommand));
  FGitBlame := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGitBlame));
  // Atlas-Spalte in der Zeilenleiste (#768): Hauptschalter und je Symbolart ein Häkchen.
  FGutterColumn := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGutterColumn));
  FGutterColumnProblems := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGutterColumnProblems));
  FGutterColumnCodeActions := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGutterColumnActions));
  FGutterColumnOverrides := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGutterColumnOverrides));
  // Gleichen Text wie die Markierung hervorheben (#709).
  FSelectionMatches := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMatches));
  FSelectionMatchesMinLength := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMatchesMinLength));
  FSelectionMatchesCaseSensitive := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMatchesCase));
  FSelectionMatchesWholeWord := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMatchesWholeWord));
  FSelectionMatchesNavigateF3 := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMatchesF3));
  FSelectionMatchesMaxMatches := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMatchesMax));
  // Austrittspunkte hervorheben (#698).
  FExitPoints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExitPoints));
  FExitPointsExceptions := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExitPointsExceptions));
  FExitPointsLoops := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExitPointsLoops));
  FExitPointsBadge := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExitPointsBadge));
  // Neu zugewiesene Variablen (#712): an/aus, je Art ein Häkchen, Linie und Farbe.
  FReassigned := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReassigned));
  FReassignedTargets[TAtlasReassignedTarget.Locals] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedLocals));
  FReassignedTargets[TAtlasReassignedTarget.LoopVars] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedLoopVars));
  FReassignedTargets[TAtlasReassignedTarget.ValueParams] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedValueParams));
  FReassignedTargets[TAtlasReassignedTarget.VarParams] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedVarParams));
  FReassignedTargets[TAtlasReassignedTarget.Fields] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedFields));
  FReassignedStyle := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedStyle),
    [TAtlasStrings.Text(TAtlasTextId.SettingsReassignedStyleDotted),
    TAtlasStrings.Text(TAtlasTextId.SettingsReassignedStyleSolid),
    TAtlasStrings.Text(TAtlasTextId.SettingsReassignedStyleWavy)]);
  FReassignedColor := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsReassignedColor));
  // Typ des markierten Ausdrucks (#689): an/aus, Umwandlungen, Wert und Kürzel.
  FExpressionType := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExpressionType));
  FExpressionTypeConversions := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExpressionTypeConversions));
  FExpressionTypeConstValue := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExpressionTypeConstValue));
  FExpressionTypeKey := AddKey(TAtlasStrings.Text(TAtlasTextId.ExpressionTypeCommand));
  // Methodenrümpfe in Deklarationsreihenfolge (#660): wie die Deklaration, alphabetisch oder aus.
  FMethodPlacement := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsMethodPlacement),
    [TAtlasStrings.Text(TAtlasTextId.SettingsMethodPlacementDeclaration),
    TAtlasStrings.Text(TAtlasTextId.SettingsMethodPlacementAlphabetical),
    TAtlasStrings.Text(TAtlasTextId.SettingsMethodPlacementOff)]);
  // Übersichtsleiste (#519): an/aus und je Art ein Häkchen.
  FOverviewRuler := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewRuler));
  FOverviewKinds[TAtlasOverviewKind.Diagnostics] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewDiagnostics));
  FOverviewKinds[TAtlasOverviewKind.Search] := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewSearch));
  FOverviewKinds[TAtlasOverviewKind.Changes] := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewChanges));
  FOverviewKinds[TAtlasOverviewKind.Breakpoints] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewBreakpoints));
  // Kommentar beim Enter fortsetzen (#696).
  FContinueComments := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsContinueComments));
  FContinueCommentsLineComments := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsContinueCommentsLineComments));
  FContinueCommentsLists := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsContinueCommentsLists));
  FContinueCommentsBlockPrefix := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsContinueCommentsBlockPrefix));
  // Markierung beim Tippen umschließen (#672).
  FWrapSelection := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWrapSelection));
  FWrapSelectionChars := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsWrapSelectionChars));
  // Anweisung vervollständigen (#697).
  FCompleteStatement := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCompleteStatement));
  FCompleteStatementKey := AddKey(TAtlasStrings.Text(TAtlasTextId.CompleteStatementCommand));
  FCompleteStatementBeginEnd := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsCompleteStatementBeginEnd),
    [TAtlasStrings.Text(TAtlasTextId.SettingsBeginEndAlways),
    TAtlasStrings.Text(TAtlasTextId.SettingsBeginEndMultiLine), TAtlasStrings.Text(TAtlasTextId.SettingsBeginEndNever)]);
  FCompleteStatementTryKind := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsCompleteStatementTryKind),
    [TAtlasStrings.Text(TAtlasTextId.CompleteStatementTryFinally),
    TAtlasStrings.Text(TAtlasTextId.CompleteStatementTryExcept), TAtlasStrings.Text(TAtlasTextId.SettingsTryKindAsk)]);
  FCompleteStatementMethodBody := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCompleteStatementMethodBody));
  // Formatieren (#43).
  FFormatCode := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsFormatCode));
  FFormatCodeKey := AddKey(TAtlasStrings.Text(TAtlasTextId.FormatCodeCommand));
  // Muster fortsetzen (#671).
  FContinuePattern := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsContinuePattern));
  FContinuePatternMinLines := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsContinuePatternMinLines));
  // Mehrere Einfügemarken (#589, experimentell).
  FMultiCursor := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursor));
  FMultiCursorModifier := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorModifier),
    [TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorAlt),
    TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorCtrl)]);
  FMultiCursorNextKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorNext));
  FMultiCursorSkipKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorSkip));
  FMultiCursorLineEndsKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorLineEnds));
  FMultiCursorAboveKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorAbove));
  FMultiCursorBelowKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMultiCursorBelow));
  // Bezeichner live mitziehen (#658, experimentell).
  FLinkedEditing := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsLinkedEditing));
  // Einfügen mit uses-Ergänzung (#515, experimentell).
  FSmartPaste := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsSmartPaste),
    [TAtlasStrings.Text(TAtlasTextId.SettingsSmartPasteOff), TAtlasStrings.Text(TAtlasTextId.SettingsSmartPasteUses),
    TAtlasStrings.Text(TAtlasTextId.SettingsSmartPasteIndent),
    TAtlasStrings.Text(TAtlasTextId.SettingsSmartPasteBoth)]);
  FOverviewKinds[TAtlasOverviewKind.Bookmarks] := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewBookmarks));
  FOverviewKinds[TAtlasOverviewKind.Cursor] := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOverviewCursor));
  // Rekursionssymbole im Rand (#623).
  FRecursionMarkers := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsRecursionMarkers));
  FRecursionMarkersDepth := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsRecursionMarkersDepth));
  // Fehlertext am Zeilenende (#509); die Reihenfolge folgt TAtlasInlineDiagnosticsMode.
  FInlineDiagnostics := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsInlineDiagnostics),
    [TAtlasStrings.Text(TAtlasTextId.SettingsInlineDiagnosticsOff),
    TAtlasStrings.Text(TAtlasTextId.SettingsInlineDiagnosticsErrors),
    TAtlasStrings.Text(TAtlasTextId.SettingsInlineDiagnosticsWarnings),
    TAtlasStrings.Text(TAtlasTextId.SettingsInlineDiagnosticsAll)]);
  // Persönliche Notizen an Codezeilen (#545).
  FNotes := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsNotes));
  // Benannte Lesezeichen (#622): Funktion und Ablage für das Team; die Taste steht bei den Editorbefehlen.
  FBookmarksNamed := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBookmarksNamed));
  FBookmarksShared := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBookmarksShared));
  // Schnelle Lesezeichen (#1104): Spalte, Tasten, Akkord-Wartezeit, Sprungbereich, Übernahme der IDE-Lesezeichen.
  FQuickBookmarks := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarks));
  FQuickBookmarksGutter := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksGutter));
  FQuickBookmarksGutterClick := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksGutterClick));
  FQuickBookmarksNumberedKeys := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksNumberedKeys));
  FQuickBookmarkKey := AddKey(TAtlasStrings.Text(TAtlasTextId.QuickBookmarkToggleCommand));
  FQuickBookmarkChordWait := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarkChordWait));
  // Reihenfolge wie AtlasQuickBookmarkScopes.
  FQuickBookmarksScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksScope),
    [TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksScopeProject),
    TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksScopeFile)]);
  FQuickBookmarksImportIde := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickBookmarksImportIde));
  FCodeLensTestUnit := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCodeLensTestUnit));
  FCodeLensMetrics := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCodeLensMetrics));
  FMetrics := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMetricsAll));
  FCodeLensTests := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCodeLensTests));
  FTodoList := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTodoList));
  FBaselineUpdate := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBaselineUpdate));
  FMetricsReport := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMetricsReport));
  FDfmPropertyRules := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDfmPropertyRules));

  // Eigene Paarfarben und deren Reihenfolge je Thema.
  AddSheet(TAtlasTextId.SettingsTabColors);
  AddSwatches(TAtlasStrings.Text(TAtlasTextId.SettingsPairColorsLight), FLightSwatches);
  AddSwatches(TAtlasStrings.Text(TAtlasTextId.SettingsPairColorsDark), FDarkSwatches);
  Panel := AddPanel(22);
  Title := TLabel.Create(Self);
  Title.Parent := Panel;
  Title.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsPairColorsHint);
  Title.Left := 0;
  Title.Top := 3;
  Title.Font.Color := clGrayText;
  Panel := AddPanel(32);
  Button := TButton.Create(Self);
  Button.Parent := Panel;
  Button.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsPairColorsReset);
  Button.Left := 0;
  Button.Top := 3;
  Button.Width := 150;
  Button.OnClick := ResetColorsClick;
  Attach(Panel, FLightSwatches[0]);

  // Umfang des Index für alle Projekte, gespeichert in settings.json (index.*, #652, #227).
  AddSheet(TAtlasTextId.SettingsTabIndex);
  FIndexGroup := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexGroup));
  FIndexSearch := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexSearch));
  FIndexLibrary := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexLibrary));
  AddIndexSection;

  // Probleme im Editor und eine Aktion nach dem Speichern (#398, #548): Syntaxprüfung der IDE oder
  // Kompilieren durch den Server (compiler.onSave in settings.json), nie beides.
  AddSheet(TAtlasTextId.SettingsTabCompiler);
  FProblems := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblems));
  FProblemsList := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsList));
  FProblemsStatusCounter := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsStatusCounter));
  // Reihenfolge: nichts, Syntaxprüfung (CheckOnSave), Kompilieren (CompileOnSave).
  FAfterSave := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsCheckOnSave),
    [TAtlasStrings.Text(TAtlasTextId.SettingsAfterSaveNone), TAtlasStrings.Text(TAtlasTextId.SettingsAfterSaveCheck),
    TAtlasStrings.Text(TAtlasTextId.SettingsAfterSaveCompile)]);
  FCheckDelay := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsCheckDelay));
  FCheckMax := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsCheckMax));
  // Claude Code baut über diese IDE (#261, build_project), z. B. ohne Kommandozeilen-Compiler.
  FMcpBuild := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMcpBuild));
  // DUnitX-Tests ausführen (#69).
  FTestRun := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestRun));
  FTestsBuildFirst := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestsBuildFirst));
  FTestsAfterBuild := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestsAfterBuild));
  FBuildZeroHints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBuildZeroHints));
  FShowInterfaceCost := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsShowInterfaceCost));
  // Schranke für Hinweise und Warnungen (#530).
  FBuildSummary := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBuildSummary));
  FBuildWarningsAsErrors := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsBuildWarningsAsErrors));
  // Prüfung vor dem Compile (#529); Reihenfolge wie TAtlasBuildGate: off, warn, block.
  FBuildGate := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsBuildGate),
    [TAtlasStrings.Text(TAtlasTextId.SettingsBuildGateOff), TAtlasStrings.Text(TAtlasTextId.SettingsBuildGateWarn),
    TAtlasStrings.Text(TAtlasTextId.SettingsBuildGateBlock)]);
  FBuildGateTimeout := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsBuildGateTimeout));
  // Wirksame Compiler-Schalter an der Cursorposition (#558).
  FBuildCompilerSwitches := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBuildCompilerSwitches));
  FBuildSwitchesInStatusBar := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBuildSwitchesInStatusBar));
  // Startprofile (#575).
  FStartProfiles := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStartProfiles));
  FStartProfilesStatusField := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStartProfilesStatusField));
  // Beim Öffnen eines Projekts oder einer Projektgruppe einmal bauen (build.onOpen).
  AddOpenBuildSection;
  // Projektaufgaben aus atlas.json (#900).
  AddTasksSection;

  // Prüfregeln (#909): oben der Weg zu den Regeln (sie stehen in den Dialogen der Einstellungsdateien), darunter
  // das Fenster „Atlas-Prüfung“ und die laufende Prüfung (Unterpunkt „Prüffenster“). „Profile und Baseline“
  // entsteht in AddRulePages.
  AddSheet(TAtlasTextId.SettingsTabRules);
  FRulesArea := High(FSheets);
  AddRulesLinks;
  FProblemsWindow := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindow));
  FProblemsWindowScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowScope),
    [TAtlasStrings.Text(TAtlasTextId.ProblemsScopeFile), TAtlasStrings.Text(TAtlasTextId.ProblemsScopeProject),
    TAtlasStrings.Text(TAtlasTextId.ProblemsScopeGroup)]);
  FProblemsWindowGroupBy := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowGroupBy),
    [TAtlasStrings.Text(TAtlasTextId.ProblemsGroupNone), TAtlasStrings.Text(TAtlasTextId.ProblemsGroupFile),
    TAtlasStrings.Text(TAtlasTextId.ProblemsGroupRule), TAtlasStrings.Text(TAtlasTextId.ProblemsGroupCategory)]);
  FProblemsWindowCompiler := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowCompiler));
  FProblemsWindowFollowCursor := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowFollowCursor));
  // Offene Units zuerst (#1108); der Hauptschalter sperrt die beiden Zeilen darunter (x-parent).
  FProblemsWindowOpenFirst := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowOpenFirst));
  FProblemsWindowClosedUnits := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowClosedUnits),
    [TAtlasStrings.Text(TAtlasTextId.ProblemsClosedDimmed), TAtlasStrings.Text(TAtlasTextId.ProblemsClosedNormal),
    TAtlasStrings.Text(TAtlasTextId.ProblemsClosedHidden)]);
  FProblemsWindowShowCleanActive := AddCheck(
    TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowShowCleanActive));
  FProblemsLive := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsLive));
  // Gruppe „Compiler vorab“ (#1024): stehen über x-node im Knoten der Gruppe unter dem Regel-Editor.
  FProblemsCompilerMerge := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsCompilerMerge),
    [TAtlasStrings.Text(TAtlasTextId.ProblemsCompilerMergeMerge),
    TAtlasStrings.Text(TAtlasTextId.ProblemsCompilerMergeBoth)]);
  FProblemsShowCompilerCode := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsShowCompilerCode));

  // Release-Build-Wächter (#533).
  AddSheet(TAtlasTextId.SettingsTabRelease);
  AddReleaseSection;

  // Einzelnen Test im Debugger starten (#585); die Code Lens dazu steht unter Editor (codeLens.tests).
  AddSheet(TAtlasTextId.SettingsTabDebug);
  FTestDebug := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestDebug));
  FTestBreakAtStart := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestBreakAtStart));
  // Variablenwerte im Hover beim Debuggen (#891).
  FDebugHoverValues := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugHoverValues));
  // Visualisierer für häufige Typen (#835): Hauptschalter, Arten, Namensfelder, Grenzen, Auswertung.
  FDebugVisualizers := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugVisualizers));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Lists] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindLists));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Dictionaries] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindDictionaries));
  FDebugVisualizerKinds[TAtlasVisualizerKind.DataSets] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindDataSets));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Bytes] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindBytes));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Json] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindJson));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Colors] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindColors));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Guid] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindGuid));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Geometry] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindGeometry));
  FDebugVisualizerKinds[TAtlasVisualizerKind.Graphics] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.DebugVisualizerKindGraphics));
  FDebugVisualizerNameFields := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsDebugVisualizerNameFields));
  FDebugVisualizerMaxLength := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsDebugVisualizerMaxLength));
  FDebugVisualizerTimeout := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsDebugVisualizerTimeout));
  FDebugVisualizerMaxImagePixels := AddNumber(
    TAtlasStrings.Text(TAtlasTextId.SettingsDebugVisualizerMaxImagePixels));
  FDebugVisualizerEvaluation := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsDebugVisualizerEvaluation),
    [TAtlasStrings.Text(TAtlasTextId.DebugVisualizerEvaluationFields),
    TAtlasStrings.Text(TAtlasTextId.DebugVisualizerEvaluationProperties),
    TAtlasStrings.Text(TAtlasTextId.DebugVisualizerEvaluationCalls)]);
  // Eigene Wertdarstellungen (#854): Schalter und Aufrufe in Vorlagen.
  FDebugDisplayRules := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugDisplayRules));
  FDebugDisplayRulesAllowCalls := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugDisplayRulesAllowCalls));
  // Gezielt hineinspringen (#836): Schalter und Tastenkürzel.
  FDebugStepIntoTarget := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugStepIntoTarget));
  // Schrittfilter beim Hineinspringen (#850): Schalter, Arten, Muster.
  FDebugStepFilters := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugStepFilters));
  FDebugStepFilterKinds[TStepFilterKind.Getters] := AddCheck(TAtlasStrings.Text(TAtlasTextId.StepFilterKindGetters));
  FDebugStepFilterKinds[TStepFilterKind.Setters] := AddCheck(TAtlasStrings.Text(TAtlasTextId.StepFilterKindSetters));
  FDebugStepFilterKinds[TStepFilterKind.Trivial] := AddCheck(TAtlasStrings.Text(TAtlasTextId.StepFilterKindTrivial));
  FDebugStepFilterKinds[TStepFilterKind.Operators] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.StepFilterKindOperators));
  FDebugStepFilterKinds[TStepFilterKind.EmptyConstructors] :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.StepFilterKindEmptyConstructors));
  FDebugStepFilterPatterns := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsDebugStepFilterPatterns));
  FDebugStepIntoTargetKey := AddKey(TAtlasStrings.Text(TAtlasTextId.StepIntoTargetCommand));
  // Beim nächsten Ereignis anhalten (#856): Schalter und ausgenommene Ereignisse.
  FDebugBreakOnNextEvent := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugBreakOnNextEvent));
  FDebugBreakOnNextEventExcluded := AddTextLine(
    TAtlasStrings.Text(TAtlasTextId.SettingsDebugBreakOnNextEventExcluded));
  // „kein Zugriff auf Wert“ erklären (#840).
  FDebugExplainUnavailable := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugExplainUnavailable));
  // Vervollständigung in Debugger-Dialogen (#538).
  FDebugCompletionInDialogs := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugCompletionInDialogs));
  // Fenster „Auswerten“ (#784).
  FDebugEvaluateWindow := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugEvaluateWindow));
  FDebugEvaluateReplaceCtrlF7 := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugEvaluateReplaceCtrlF7));
  // Zugriffsverletzung erklären (#865)
  FDebugExplainAccessViolation := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugExplainAccessViolation));
  FDebugExplainAccessViolationAllowCalls :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugExplainAccessViolationAllowCalls));
  // Exception-Verlauf beim Debuggen (#517).
  FDebugExceptionHistory := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugExceptionHistory));
  // Nur eigener Code beim Debuggen (#578).
  FDebugJustMyCode := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugJustMyCode));
  FDebugOwnCodeFolders := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsDebugOwnCodeFolders));
  // Exception-Leiste beim Debuggen (#783).
  FDebugExceptionBanner := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugExceptionBanner));
  FDebugExceptionBannerIgnoreAtLocation :=
    AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugExceptionBannerIgnoreAtLocation));
  // Werte im Editor beim Debuggen (#508).
  FDebugInlineValues := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDebugInlineValues));
  FDebugInlineValuesPerLine := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsDebugInlineValuesPerLine));

  // Editorbefehle (#399): ein Vorrang für alle.
  AddSheet(TAtlasTextId.SettingsTabCommands);
  FActionsKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorActions));
  FExpandKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorExpand));
  FShrinkKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorShrink));
  FImplementationKey := AddKey(TAtlasStrings.Text(TAtlasTextId.MenuImplementations));
  FTypeDefinitionKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorTypeDefinition));
  // Deklaration ⇄ Implementierung (#775); aus: Klassennavigation der IDE.
  FMethodToggle := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMethodToggle));
  FMethodToggleUpKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMethodToggleUp));
  FMethodToggleDownKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMethodToggleDown));
  // Sprung zum Gegenstück (#635); aus: beide Tasten bleiben frei.
  FJumpToMatch := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsJumpToMatch));
  FJumpToMatchKey := AddKey(TAtlasStrings.Text(TAtlasTextId.JumpToMatchCommand));
  FJumpToMatchSelectKey := AddKey(TAtlasStrings.Text(TAtlasTextId.JumpToMatchSelectCommand));
  // Zeilen verschieben und duplizieren (#634); aus: die Tasten bleiben der IDE.
  FMoveLines := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMoveLines));
  FMoveLinesUpKey := AddKey(TAtlasStrings.Text(TAtlasTextId.MoveLinesUpCommand));
  FMoveLinesDownKey := AddKey(TAtlasStrings.Text(TAtlasTextId.MoveLinesDownCommand));
  FDuplicateLinesUpKey := AddKey(TAtlasStrings.Text(TAtlasTextId.DuplicateLinesUpCommand));
  FDuplicateLinesDownKey := AddKey(TAtlasStrings.Text(TAtlasTextId.DuplicateLinesDownCommand));
  // Blockkommentar umschalten (#703).
  FToggleBlockComment := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsToggleBlockComment));
  FToggleBlockCommentKey := AddKey(TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentCommand));
  FToggleBlockCommentStyle := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsToggleBlockCommentStyle),
    [TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentBraces),
    TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentParens)]);
  FToggleBlockCommentFallback := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsToggleBlockCommentFallback),
    [TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentLineComments),
    TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentRefuse)]);
  FToggleBlockCommentOwnLines := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsToggleBlockCommentOwnLines));
  FToggleBlockCommentScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsToggleBlockCommentScope),
    [TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentStatement),
    TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentLine)]);
  // Neue Zeile ober- oder unterhalb (#700).
  FNewLineAround := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsNewLineAround));
  FNewLineBelowKey := AddKey(TAtlasStrings.Text(TAtlasTextId.NewLineBelowCommand));
  FNewLineAboveKey := AddKey(TAtlasStrings.Text(TAtlasTextId.NewLineAboveCommand));
  FNewLineAroundStatementAware := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsNewLineAroundStatementAware));
  // Umschließung entfernen (#657).
  FUnwrap := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnwrap));
  FUnwrapKey := AddKey(TAtlasStrings.Text(TAtlasTextId.UnwrapCommand));
  // Sicher löschen (#716).
  FSafeDelete := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSafeDelete));
  FSafeDeleteKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SafeDeleteCommand));
  FTestUnitKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorTestUnit));
  // Abschnittssprünge der Editorleiste (#1101), auch ohne die Leiste.
  FGotoInterfaceKey := AddKey(TAtlasStrings.Text(TAtlasTextId.GotoInterfaceCommand));
  FGotoImplementationKey := AddKey(TAtlasStrings.Text(TAtlasTextId.GotoImplementationCommand));
  // Navigationsverlauf über Dateien (#504).
  FNavHistory := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsNavHistory));
  FNavBackKey := AddKey(TAtlasStrings.Text(TAtlasTextId.NavBackCommand));
  FNavForwardKey := AddKey(TAtlasStrings.Text(TAtlasTextId.NavForwardCommand));
  FLastEditKey := AddKey(TAtlasStrings.Text(TAtlasTextId.NavLastEditCommand));
  // Definition und Referenzen einblenden (#505).
  FPeek := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPeek));
  FPeekHeightLines := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsPeekHeight));
  FPeekShowImplementation := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPeekImplementation));
  FPeekDefinitionKey := AddKey(TAtlasStrings.Text(TAtlasTextId.PeekDefinitionCommand));
  FPeekReferencesKey := AddKey(TAtlasStrings.Text(TAtlasTextId.PeekReferencesCommand));
  // Treffersicherheit der Verwendungen (#1119).
  FReferencesInferred := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReferencesInferred));
  FReferencesTextMatches := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReferencesTextMatches));
  // Auswirkungsanalyse (#1120).
  FImpact := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsImpact));
  FImpactDepth := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsImpactDepth));
  // Datenfluss im Ergebnisfenster (#690).
  FDataFlow := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDataFlow));
  FDataFlowMaxDepth := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsDataFlowMaxDepth));
  FDataFlowExcludeTests := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDataFlowExcludeTests));
  FOutline := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOutline));
  FOutlineAlphabetical := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOutlineAlphabetical));
  FOutlineFollowCursor := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOutlineFollowCursor));
  FOutlineConditions := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOutlineConditions));
  // „Lesezeichen setzen…“ (#622).
  FBookmarkKey := AddKey(TAtlasStrings.Text(TAtlasTextId.BookmarksMenuAdd));
  // Nächstes/voriges Lesezeichen (#1104), ohne Vorgabe.
  FNextBookmarkKey := AddKey(TAtlasStrings.Text(TAtlasTextId.NextBookmarkCommand));
  FPreviousBookmarkKey := AddKey(TAtlasStrings.Text(TAtlasTextId.PreviousBookmarkCommand));
  // „Element ausblenden …“ am gezeichneten Element (#628).
  FHideElementKey := AddKey(TAtlasStrings.Text(TAtlasTextId.HideElementCommand));
  // Nächster/vorheriger Befund (#509).
  FNextProblemKey := AddKey(TAtlasStrings.Text(TAtlasTextId.ProblemNextCommand));
  FPreviousProblemKey := AddKey(TAtlasStrings.Text(TAtlasTextId.ProblemPreviousCommand));
  // Fenster „Atlas-Prüfung“ (#909).
  FProblemsWindowKey := AddKey(TAtlasStrings.Text(TAtlasTextId.ProblemsWindowCommand));
  // „Issue anlegen …“ (#1268), ohne Vorgabe.
  FCreateIssueKey := AddKey(TAtlasStrings.Text(TAtlasTextId.CreateIssueCommand));
  FUndoKey := AddKey(TAtlasStrings.Text(TAtlasTextId.UndoMenu));
  FRedoKey := AddKey(TAtlasStrings.Text(TAtlasTextId.RedoMenu));
  FEditorKeysPriority := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEditorKeysPriority));
  FSlashCommands := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSlashCommands));
  // Erzeugen-Menü (#719): Schnellbefehle, Vorlagen und Code-Aktionen an der Cursorstelle.
  FGenerateMenu := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGenerateMenu));
  FGenerateMenuKey := AddKey(TAtlasStrings.Text(TAtlasTextId.GenerateMenuCommand));
  FGenerateMenuGroups := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsGenerateMenuGroups));
  FGenerateMenuHidden := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsGenerateMenuHidden));
  FGenerateMenuRecentFirst := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGenerateMenuRecentFirst));
  FGenerateMenuShowCommandNames := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGenerateMenuShowCommandNames));
  // Liste der Benachrichtigungen (#601).
  FNotificationsKey := AddKey(TAtlasStrings.Text(TAtlasTextId.NotificationsCommand));

  AddSheet(TAtlasTextId.SettingsTabRobustness);
  // Einfrier-Wächter (#501).
  FHangThreshold := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsHangThreshold));
  FHangHint := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHangHint));
  // Blockierschutz für Datenquellen (#493).
  FProviderTimeLimit := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsProviderTimeLimit));
  Panel := AddPanel(32);
  // Künstlicher Hänger (#501) nur im Diagnosemodus (#479), nicht neben den regulären Einstellungen (S-07).
  FHangTestRow := Panel;
  FHangTestRow.Visible := False;
  FDiagnosticMode.OnClick := DiagnosticModeClick;
  FHangTest := TButton.Create(Self);
  FHangTest.Parent := Panel;
  FHangTest.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsHangTest);
  FHangTest.Left := 0;
  FHangTest.Top := 3;
  FHangTest.Width := 150;
  FHangTest.OnClick := HangTestClick;
  AddFuseSection;

  // Abgesicherter Start, Updates und Fehlerbericht (#722, #495, #108).
  AddSheet(TAtlasTextId.SettingsTabStartup);
  AddSafeSection;
  AddUpdatesSection;
  AddBugReportSection;

  AddSheet(TAtlasTextId.SettingsTabUndo);
  AddUndoSection;

  AddSheet(TAtlasTextId.SettingsTabUnitSearch);
  AddUnitSearchSection;

  AddSheet(TAtlasTextId.SettingsTabWelcome);
  AddWelcomeSection;

  // Issue-Tracker (#1280): eigener Bereich; die Willkommensseite schaltet nur, ob „Meine Issues“ erscheint.
  AddSheet(TAtlasTextId.SettingsTabIssues);
  AddIssuesSection;

  // Versionsverwaltung (#1285): neben dem Issue-Tracker; Verhalten unter vcs.*.
  AddSheet(TAtlasTextId.SettingsTabVcs);
  AddVcsSection;

  AddSheet(TAtlasTextId.SettingsTabTeamFile);
  AddTeamFileSection;

  // „Einstellungen dazu …“ am gezeichneten Element (#628) und an Bereichen der Willkommensseite (#767).
  Bind('CodeLensMetrics', FCodeLensMetrics);
  Bind('CodeLensTests', FCodeLensTests);
  Bind('CodeLensTestUnit', FCodeLensTestUnit);
  Bind('BlockEndLabels', FBlockEndLabels);
  Bind('DimUnusedUses', FDimUnusedUses);
  Bind('Breadcrumbs', FBreadcrumbs);
  Bind('GitGutter', FGitGutter);
  Bind('GitBlame', FGitBlame);
  Bind('GutterColumn', FGutterColumn);
  Bind('SelectionMatches', FSelectionMatches);
  Bind('ExitPoints', FExitPoints);
  Bind('Reassigned', FReassigned);
  Bind('ExpressionType', FExpressionType);
  Bind('OverviewRuler', FOverviewRuler);
  Bind('RecursionMarkers', FRecursionMarkers);
  Bind('InlineDiagnostics', FInlineDiagnostics);
  Bind('ProblemsStatusCounter', FProblemsStatusCounter);
  Bind('InlayHints', FInlayHints);
  Bind('InlayTypeHints', FInlayTypeHints);
  Bind('InlayDefineHints', FInlayDefineHints);
  Bind('InlayCharHints', FInlayCharHints);
  Bind('InlayMethodHints', FInlayMethodHints);
  Bind('Problems', FProblems);
  Bind('ProblemsWindow', FProblemsWindow);
  Bind('ArchitectureEnabled', FArchitecture);
  Bind('ProblemsLive', FProblemsLive);
  Bind('HoverProblemActions', FHoverProblemActions);
  Bind('Notes', FNotes);
  Bind('BookmarksNamed', FBookmarksNamed);
  Bind('QuickBookmarksGutter', FQuickBookmarksGutter);
  Bind('PairColors', FPairColors);
  Bind('PairGuides', FPairGuides);
  Bind('PairOwners', FPairOwners);
  Bind('InactiveDim', FInactiveDim);
  Bind('Preview', FPreview);
  Bind('HideElementKey', FHideElementKey);
  Bind('ContinuePattern', FContinuePattern);
  Bind('WelcomePage', FWelcomeEnabled);
  Bind('WelcomePageHeader', FWelcomeHeader);
  Bind('WelcomePageSearch', FWelcomeSearch);
  Bind('WelcomePageWhatsNew', FWelcomeWhatsNew);
  Bind('WelcomePageContinue', FWelcomeContinue);
  Bind('WelcomePageProjectStatus', FWelcomeProjects);
  Bind('WelcomePageTrends', FWelcomeTrends);
  Bind('WelcomePageTests', FWelcomeTests);
  Bind('WelcomePageUnsaved', FWelcomeUnsaved);
  Bind('WelcomePageStatusTile', FWelcomeStatusTile);
  Bind('WelcomePageDiscover', FWelcomeDiscover);
  Bind('WelcomePageHelp', FWelcomeHelp);
  Bind('WelcomePageProjectSetup', FWelcomeProjectSetup);
  Bind('WelcomePageIssues', FWelcomeIssues);
  Bind('WelcomePageCustomLayout', FWelcomeCustomLayout);
  Bind('WelcomePageColumns', FWelcomeColumns);
  Bind('WelcomePageActiveLayout', FWelcomeActiveLayout);
  Bind('WelcomePageLayouts', FWelcomeActiveLayout);
  Bind('ExperimentalEnabled', FExperimentalEnabled);
  BindControls;
  AddFilterRow;
  BuildNodes;
end;

procedure TAtlasSettingsPage.AddExperimentalBanner;
var
  mText: TLabel;
  Button: TButton;
begin
  FExperimentalBanner := TAtlasSettingsRow.Create(Self);
  FExperimentalBanner.Parent := Self;
  FExperimentalBanner.Align := alTop;
  FExperimentalBanner.AlignWithMargins := True;
  FExperimentalBanner.Top := 50;
  FExperimentalBanner.Height := 28;
  FExperimentalBanner.Visible := False;
  Button := TButton.Create(Self);
  Button.Parent := FExperimentalBanner;
  Button.Align := alRight;
  Button.Width := 90;
  Button.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsExperimentalAllow);
  Button.OnClick := ExperimentalAllowClick;
  mText := TLabel.Create(Self);
  mText.Parent := FExperimentalBanner;
  mText.Align := alClient;
  mText.Layout := tlCenter;
  mText.WordWrap := True;
  mText.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsExperimentalOff);
end;

procedure TAtlasSettingsPage.AddFilterRow;
var
  mCaption: TLabel;
begin
  FFilterRow := TAtlasSettingsRow.Create(Self);
  FFilterRow.Parent := Self;
  FFilterRow.Align := alBottom;
  FFilterRow.AlignWithMargins := True;
  FFilterRow.Height := 26;
  mCaption := TLabel.Create(Self);
  mCaption.Parent := FFilterRow;
  mCaption.Left := 0;
  mCaption.Top := 5;
  mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsFilter);
  // Reihenfolge wie TAtlasSettingsFilter.
  FFilter := TAtlasChoiceBox.Create(Self);
  FFilter.Parent := FFilterRow;
  FFilter.Left := 60;
  FFilter.Top := 1;
  FFilter.Width := 180;
  FFilter.SetChoices([TAtlasStrings.Text(TAtlasTextId.SettingsFilterAll),
    TAtlasStrings.Text(TAtlasTextId.SettingsFilterModified),
    TAtlasStrings.Text(TAtlasTextId.SettingsFilterExperimental)]);
  FFilter.Choice := 0;
  FFilter.OnChange := FilterChange;
  FMarks.MarkExperimental(TAtlasExperimental.PluginNames(Catalog));
end;

procedure TAtlasSettingsPage.ExperimentalAllowClick(Sender: TObject);
begin
  // Wie ein Klick auf das Kontrollkästchen: Punkte und Hinweis folgen über die Bindung.
  FExperimentalEnabled.Checked := True;
end;

procedure TAtlasSettingsPage.FilterChange(Sender: TObject);
begin
  if (FFilter.Choice >= Ord(Low(TAtlasSettingsFilter))) and (FFilter.Choice <= Ord(High(TAtlasSettingsFilter))) then
    FMarks.ApplyFilter(TAtlasSettingsFilter(FFilter.Choice));
  // Knoten ohne Treffer fallen aus dem Baum (#890).
  if FTree.HandleAllocated then
    FillTree;
end;

procedure TAtlasSettingsPage.Bind(const AKey: string; AControl: TControl);
begin
  if AControl = nil then
    Exit;
  FRevealKeys := FRevealKeys + [AKey];
  FRevealControls := FRevealControls + [AControl];
end;

function TAtlasSettingsPage.ControlOf(const AKey: string): TControl;
var
  Index: Integer;
begin
  for Index := 0 to High(FRevealKeys) do
    if SameText(FRevealKeys[Index], AKey) then
      Exit(FRevealControls[Index]);
  Result := nil;
end;

function TAtlasSettingsPage.Reveal(const AKey: string): Boolean;
begin
  Result := ControlOf(AKey) <> nil;
  if not Result then
    Exit;
  if HandleAllocated then
    ApplyReveal(AKey)
  else
    FPendingReveal := AKey;
end;

procedure TAtlasSettingsPage.ApplyReveal(const AKey: string);
var
  Control, Master: TControl;
  mParent: TWinControl;
  Child: Integer;
  Names: TArray<string>;
  Lock: TAtlasSettingsLock;
begin
  FPendingReveal := '';
  Control := ControlOf(AKey);
  if Control = nil then
    Exit;
  // Gesperrt (#890): den Hauptschalter zeigen, der sie freigibt.
  Names := FMarks.NamesOf(Control);
  if (Length(Names) > 0) and (FGroups <> nil) then
  begin
    Lock := LockOfName(Names[0]);
    if Lock.Locked then
    begin
      Master := FMarks.ControlOfName(Lock.Master);
      if Master <> nil then
        Control := Master;
    end;
  end;
  // Knoten des Elements wählen, wie ein Klick im Baum links.
  SelectPage(PageOf(Control));
  // Ins Bild rollen.
  mParent := Control.Parent;
  while (mParent <> nil) and not (mParent is TScrollBox) do
    mParent := mParent.Parent;
  if mParent is TScrollBox then
    TScrollBox(mParent).ScrollInView(Control);
  // Zeile hervorheben: Kontrollkästchen fett, sonst die Beschriftung der Zeile.
  if Control is TCheckBox then
    TCheckBox(Control).Font.Style := [fsBold]
  else if Control.Parent <> nil then
    for Child := 0 to Control.Parent.ControlCount - 1 do
      if Control.Parent.Controls[Child] is TLabel then
        TLabel(Control.Parent.Controls[Child]).Font.Style := [fsBold];
  // Nur mit sichtbarer Form: CanFocus allein lässt eine noch verborgene Form durch („kann den Fokus nicht erhalten“).
  if (Control is TWinControl) and TWinControl(Control).CanFocus and (GetParentForm(Control) <> nil) and
    GetParentForm(Control).Visible then
    TWinControl(Control).SetFocus;
end;

procedure TAtlasSettingsPage.AddWelcomeSection;
var
  Series: TAtlasTrendSeries;
  mAction: TAtlasQuickAction;
  Panel: TWinControl;
begin
  // Atlas-Willkommensseite im Fenster „Atlas-Start“ (#753, #1114).
  FWelcomeEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeEnabled));
  FWelcomeOpenOnStart := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeOpenOnStart));
  FWelcomeOpenWhenNoProject := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeOpenWhenNoProject));
  // Freies Layout (#767): Bearbeitungsmodus „Seite anpassen“, Spalten, benannte Layouts.
  FWelcomeCustomLayout := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeCustomLayout));
  FWelcomeColumns := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeColumns));
  FWelcomeActiveLayout := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeActiveLayout),
    [TAtlasWelcomeLayout.DefaultName]);
  FWelcomeActiveLayout.OnChange := WelcomeLayoutChange;
  AddWelcomeLayoutButtons;
  FPageLayouts := TAtlasWelcomeLayouts.Defaults;
  FWelcomeHeader := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHeader));
  FWelcomeGreeting := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeGreeting));
  FWelcomeSearch := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeSearch));
  FWelcomeSearchSymbols := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeSearchSymbols));
  FWelcomeSearchKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeSearchKey));
  // Karte „Neu in Atlas“ (#756); Reihenfolge wie TAtlasWhatsNewMode: off, afterUpdate, always.
  FWelcomeWhatsNew := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeWhatsNew),
    [TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeWhatsNewOff),
    TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeWhatsNewAfterUpdate),
    TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeWhatsNewAlways)]);
  // Bereich „Weiterarbeiten“ (#755).
  FWelcomeContinue := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeContinue));
  FWelcomeContinueCount := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeContinueCount));
  FWelcomeContinueIncoming := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeContinueIncoming));
  FWelcomeContinueFetch := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeContinueFetch));
  FWelcomeSaved := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeSaved));
  // Bereich „Projekte“ (#592).
  FWelcomeProjects := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeProjects));
  FWelcomeMaxProjects := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeMaxProjects));
  FWelcomeRefreshVcs := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeRefreshVcs));
  // Bereich „Projektverlauf“ (#758): Schalter, Anzahl der Builds und je Reihe ein Kontrollkästchen.
  FWelcomeTrends := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeTrends));
  FWelcomeTrendsPoints := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeTrendsPoints));
  for Series := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
    FWelcomeTrendsSeries[Series] := AddCheck(TAtlasStrings.Fmt(TAtlasTextId.SettingsWelcomeTrendsSeries,
      [TrendSeriesTitle(Series)]));
  // Bereich „Testergebnisse“ (#763): lokal und vom Build-Server; Anbieter in der Reihenfolge von
  // TAtlasPluginSettings (bisher nur Jenkins).
  FWelcomeTests := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeTests));
  FWelcomeTestsMaxFailures := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeTestsMaxFailures));
  FWelcomeTestsCi := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeTestsCi));
  FWelcomeTestsCiProvider := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeTestsCiProvider),
    [TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeTestsCiJenkins)]);
  FWelcomeTestsCiInterval := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeTestsCiInterval));
  FWelcomeTestsCiNotify := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeTestsCiNotify));
  FCiLogin := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCiLogin));
  // Meine Issues (#765): nur der Bereich; Tracker, Abfrage und Muster stehen auf der Seite Issue-Tracker (#1280).
  FWelcomeIssues := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssues));
  Panel := AddPanel(32);
  FWelcomeIssuesLink := TButton.Create(Self);
  FWelcomeIssuesLink.Parent := Panel;
  FWelcomeIssuesLink.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssuesLink);
  FWelcomeIssuesLink.Left := 0;
  FWelcomeIssuesLink.Top := 3;
  FWelcomeIssuesLink.Width := 200;
  FWelcomeIssuesLink.OnClick := WelcomeIssuesLinkClick;
  Attach(Panel, FWelcomeIssues);
  // Schnellaktionen je Projekt (#764): Schalter, je Knopf ein Häkchen, Programm für „Konsole“, zwei Tasten.
  FWelcomeQuickActions := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeQuickActions));
  for mAction := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
    FWelcomeQuickActionsItems[mAction] := AddCheck(TAtlasStrings.Fmt(TAtlasTextId.SettingsWelcomeQuickActionsItem,
      [QuickActionTitle(mAction)]));
  FWelcomeQuickActionsConsole := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeQuickActionsConsole));
  FWelcomeQuickActionsBuildKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeQuickActionsBuildKey));
  FWelcomeQuickActionsTestKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeQuickActionsTestKey));
  // Bereich „Nicht gesichert“ (#762).
  FWelcomeUnsaved := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeUnsaved));
  FWelcomeUnsavedMinAge := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeUnsavedMinAge));
  FWelcomeUnsavedWarn := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeUnsavedWarn));
  FWelcomeUnsavedAlert := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeUnsavedAlert));
  FWelcomeUnsavedHideClean := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeUnsavedHideClean));
  // Zustandskachel „Atlas“ (#754).
  FWelcomeStatusTile := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeStatusTile));
  FWelcomeStatusTileOnlyProblems := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeStatusTileOnlyProblems));
  // Karte „Atlas entdecken“ und Nutzungszählung (#757).
  FWelcomeDiscover := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeDiscover));
  FTipsUsageTracking := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTipsUsageTracking));
  Panel := AddPanel(32);
  FResetUsage := TButton.Create(Self);
  FResetUsage.Parent := Panel;
  FResetUsage.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsResetUsage);
  FResetUsage.Left := 0;
  FResetUsage.Top := 3;
  FResetUsage.Width := 180;
  FResetUsage.OnClick := ResetUsageClick;
  FUnblockTips := TButton.Create(Self);
  FUnblockTips.Parent := Panel;
  FUnblockTips.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsUnblockTips);
  FUnblockTips.Left := 190;
  FUnblockTips.Top := 3;
  FUnblockTips.Width := 200;
  FUnblockTips.OnClick := UnblockTipsClick;
  Attach(Panel, FWelcomeDiscover);
  // Bereich „Hilfe und Rückmeldung“ (#766): Schalter, Ziel der Issue-Seite, Ordner der ZIP.
  FWelcomeHelp := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHelp));
  FWelcomeHelpReportUrl := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHelpReportUrl));
  FWelcomeHelpReportFolder := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHelpReportFolder));
  FWelcomeHelpReportFolder.TextHint := TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHelpDesktop);
  FWelcomeHelpReportFolder.Width := FWelcomeHelpReportFolder.Width - 36;
  FWelcomeHelpFolderBrowse := TButton.Create(Self);
  FWelcomeHelpFolderBrowse.Parent := FWelcomeHelpReportFolder.Parent;
  FWelcomeHelpFolderBrowse.Caption := '…';
  FWelcomeHelpFolderBrowse.Left := FWelcomeHelpReportFolder.Left + FWelcomeHelpReportFolder.Width + 6;
  FWelcomeHelpFolderBrowse.Top := 0;
  FWelcomeHelpFolderBrowse.Width := 30;
  FWelcomeHelpFolderBrowse.Anchors := [akTop, akRight];
  FWelcomeHelpFolderBrowse.OnClick := HelpFolderBrowseClick;
  // Karte „Projekt für Atlas einrichten“ und Knöpfe „Neu mit Atlas“ (#759).
  FWelcomeProjectSetup := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeProjectSetup));
  FWelcomeNewFromTemplate := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeNewFromTemplate));
end;

procedure TAtlasSettingsPage.AddIssuesSection;
begin
  // Verbindungen zuerst (#1260, Mockup IT1): Tabelle mit Token-Zustand, darunter die gewählte Zeile.
  AddTrackerConnectionsSection;
  // Danach die Zuordnung der Delphi-Projekte (#1261, Mockup IT2).
  AddTrackerProjectsSection;
  // Benannte Abfragen und Klappliste (#1262, Mockup IT3).
  AddTrackerQueriesSection;
  // Anbieter (Vorgabe aus der .atlas), „Beginnen“, Muster für Branch und Commit, Zugang (#765).
  FIssuesTracker := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesTracker),
    [TAtlasStrings.Text(TAtlasTextId.SettingsIssuesTrackerTeam), 'GitHub', 'YouTrack']);
  FIssuesStart := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesStart),
    [TAtlasStrings.Text(TAtlasTextId.SettingsIssuesStartBranch),
    TAtlasStrings.Text(TAtlasTextId.SettingsIssuesStartRemember)]);
  FIssuesBranchPattern := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesBranchPattern));
  FIssuesBranchBase := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesBranchBase));
  FIssuesCommitPattern := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesCommitPattern));
  FTrackerLogin := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTrackerLogin));
  // Issue-Vorschau (#1264): Hauptschalter, Kommentare darunter.
  FIssuesPreview := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesPreview));
  FIssuesPreviewComments := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesPreviewComments));
  FIssuesCodeLinks := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesCodeLinks));
  // Issues in der Zeilenhistorie (#1275): Schalter, darunter die Grenze für „Issues zu dieser Methode“.
  FIssuesBlameLinks := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesBlameLinks));
  FIssuesBlameMaxRevisions := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesBlameMaxRevisions));
  AddIssuesWorkflowSection;
  AddIssuesTimeSection;
  // Checklisten (#1273): in der Vorschau unter deren Hauptschalter, das Statusfeld eigenständig.
  FIssuesPreviewChecklists := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesPreviewChecklists));
  FIssuesChecklistStatus := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesChecklistStatus));
end;

procedure TAtlasSettingsPage.AddIssuesTimeSection;
begin
  // Zeiterfassung (#1267): Hauptschalter, Leerlauf und Rundung (x-parent issues.timeTracking).
  AddTitle(TAtlasTextId.SettingsIssuesTimeTitle);
  FIssuesTimeTracking := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesTimeTracking));
  FIssuesIdleMinutes := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesIdleMinutes));
  FIssuesTimeRounding := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesTimeRounding));
end;

procedure TAtlasSettingsPage.AddIssuesWorkflowSection;
var
  mPanel: TWinControl;
begin
  // Zustand im Tracker (#1266): Schalter, Felder und Zustände mit Werten vom Tracker, Vorlagen der Kommentare.
  AddTitle(TAtlasTextId.SettingsIssuesWorkflowTitle);
  FIssuesSyncState := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesSyncState));
  FIssuesStateField := AddValueBox(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesStateField));
  FIssuesAssigneeField := AddValueBox(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesAssigneeField));
  FIssuesStartState := AddValueBox(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesStartState));
  FIssuesAssignOnStart := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesAssignOnStart));
  FIssuesStartComment := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesStartComment));
  FIssuesEndStates := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesEndStates));
  FIssuesEndComment := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesEndComment));
  mPanel := AddPanel(30);
  FIssuesLoadValues := TButton.Create(Self);
  FIssuesLoadValues.Parent := mPanel;
  FIssuesLoadValues.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesLoadValues);
  FIssuesLoadValues.Left := 0;
  FIssuesLoadValues.Top := 3;
  FIssuesLoadValues.Width := 180;
  FIssuesLoadValues.OnClick := TrackerLoadValuesClick;
  FIssuesValuesNote := TLabel.Create(Self);
  FIssuesValuesNote.Parent := mPanel;
  FIssuesValuesNote.Left := 190;
  FIssuesValuesNote.Top := 7;
  FIssuesValuesNote.Font.Color := clGrayText;
  FIssuesValuesNote.Caption := '';
end;

function TAtlasSettingsPage.AddValueBox(const ACaption: string): TAtlasValueBox;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  mPanel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := mPanel;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := 5;
  Result := TAtlasValueBox.Create(Self);
  Result.Parent := mPanel;
  Result.Left := FieldLeft;
  Result.Top := 1;
  Result.Width := 180;
end;

procedure TAtlasSettingsPage.AddVcsSection;
var
  mPanel: TWinControl;
begin
  // Art (#571): Reihenfolge wie die Werte von vcs.provider (auto, git, svn, off).
  AddTitle(TAtlasTextId.SettingsVcsKindTitle);
  FVcsProvider := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProvider),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderAuto), TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderGit),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderSvn), TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderOff)]);
  FVcsProvider.Width := 220;
  // Programme: eigener Pfad mit „…“ und „Prüfen“, darunter der Zustand.
  AddTitle(TAtlasTextId.SettingsVcsToolsTitle);
  AddVcsTool(TAtlasVcsKind.Git, TAtlasTextId.SettingsVcsGitPath);
  AddVcsTool(TAtlasVcsKind.Svn, TAtlasTextId.SettingsVcsSvnPath);
  FVcsTimeout := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsVcsTimeout));
  // Aktuelles Projekt: nur Anzeige, beim ersten Zeigen der Seite einmal im Hintergrund abgefragt.
  AddTitle(TAtlasTextId.SettingsVcsProjectTitle);
  FVcsProjectInfo := AddWrappedLabel(70, TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectNone));
  AddVcsProjectsSection;
  AddVcsServersSection;
  // Seiten, die die Anzeige steuern: Verhalten unter vcs.*, dort nur, ob etwas erscheint (wie #1280).
  AddTitle(TAtlasTextId.SettingsVcsLinksTitle);
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsLinksHint)).Font.Color := clGrayText;
  mPanel := AddPanel(32);
  FVcsLinkEditor := AddVcsLink(mPanel, 0, TAtlasTextId.SettingsVcsLinkEditor);
  FVcsLinkWelcome := AddVcsLink(mPanel, 156, TAtlasTextId.SettingsVcsLinkWelcome);
  FVcsLinkIssues := AddVcsLink(mPanel, 312, TAtlasTextId.SettingsVcsLinkIssues);
  // Unterpunkt „Branches“ (#1288, x-node vcs.branches): Dialog „Branch anlegen“ vor „Beginnen“; die Optionen aus
  // #1289 und #1290 kommen hier dazu.
  AddTitle(TAtlasTextId.SettingsVcsBranchTitle);
  FVcsBranchConfirm := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchConfirm));
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchHint)).Font.Color := clGrayText;
  // Gruppe „SVN“ (#1290): Vorgaben für Ort, Quelle, Danach und Nachricht im Dialog „Branch anlegen“; Reihenfolge der
  // Auswahl wie die Werte von vcs.branch.svn.source bzw. .after.
  AddTitle(TAtlasTextId.SettingsVcsBranchSvnTitle);
  FVcsBranchSvnLocation := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnLocation));
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnLocationHint)).Font.Color := clGrayText;
  FVcsBranchSvnSource := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnSource),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnSourceHead),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnSourceWorkingCopy)]);
  FVcsBranchSvnSource.Width := 260;
  FVcsBranchSvnAfter := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnAfter),
    [TAtlasStrings.Text(TAtlasTextId.VcsBranchAfterSwitch), TAtlasStrings.Text(TAtlasTextId.VcsBranchAfterCheckout),
    TAtlasStrings.Text(TAtlasTextId.VcsBranchAfterNone)]);
  FVcsBranchSvnAfter.Width := 260;
  FVcsBranchSvnFolder := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnFolder));
  FVcsBranchSvnMessage := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnMessage));
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchSvnMessageHint)).Font.Color := clGrayText;
  AddVcsExternalsSection;
end;

procedure TAtlasSettingsPage.AddVcsExternalsSection;
var
  mPanel: TWinControl;
  mCaption: TLabel;
begin
  // Unterpunkt „Externals“ (#1291, x-node vcs.externals): Vorgaben je External im Dialog „Branch anlegen“;
  // Reihenfolge der Auswahl wie die Werte von vcs.externals.onBranch bzw. .suggestBranch.
  AddTitle(TAtlasTextId.SettingsVcsExternalsTitle);
  FVcsExternalsOnBranch := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsOnBranch),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsOnBranchPin),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsOnBranchKeep),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsOnBranchAsk)]);
  FVcsExternalsOnBranch.Width := 260;
  FVcsExternalsSuggest := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsSuggest),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsSuggestModified),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsSuggestNever),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsSuggestAlways)]);
  FVcsExternalsSuggest.Width := 260;
  mPanel := AddPanel(20);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := mPanel;
  mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsRules);
  mCaption.Left := 0;
  mCaption.Top := 3;
  mPanel := AddPanel(84);
  FVcsExternalsRules := TMemo.Create(Self);
  FVcsExternalsRules.Parent := mPanel;
  FVcsExternalsRules.SetBounds(0, 1, 466, 80);
  FVcsExternalsRules.Anchors := [akLeft, akTop, akRight];
  FVcsExternalsRules.ScrollBars := ssVertical;
  FVcsExternalsRules.WordWrap := False;
  FVcsExternalsRules.OnChange := VcsExternalsRulesChange;
  FVcsExternalsRulesError := AddWrappedLabel(20, '');
  FVcsExternalsRulesError.Font.Color := clRed;
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsRulesHint)).Font.Color := clGrayText;
  // Arbeitskopien der Gruppe und Aktualisieren (#1292); Reihenfolge wie vcs.externals.update.
  FVcsExternalsShow := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsShow));
  FVcsExternalsUpdate := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsUpdate),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsUpdateWith),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsUpdateWithout),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsExternalsUpdateAsk)]);
  FVcsExternalsUpdate.Width := 260;
end;

procedure TAtlasSettingsPage.VcsExternalsRulesChange(Sender: TObject);
var
  mRules: TArray<TAtlasVcsExternalRule>;
  mInvalid: string;
begin
  // Ungültige Zeile: Hinweis; gespeichert bleiben dann die bisherigen Regeln (SaveTo).
  if TAtlasVcsBranchPlan.RulesOfText(FVcsExternalsRules.Text, mRules, mInvalid) then
    FVcsExternalsRulesError.Caption := ''
  else
    FVcsExternalsRulesError.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsExternalsRulesInvalid, [mInvalid]);
  RefreshMarks;
  // Gruppe „Git“ (#1289): Vorgaben im Dialog und für „Beginnen“ ohne Dialog; Reihenfolge wie die Werte.
  AddTitle(TAtlasTextId.SettingsVcsBranchGitTitle);
  FVcsBranchGitBase := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitBase),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitBaseRemote),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitBaseLocal),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitBaseCurrent)]);
  FVcsBranchGitBase.Width := 320;
  FVcsBranchGitPush := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitPush),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitPushLater),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitPushNow)]);
  FVcsBranchGitPush.Width := 320;
  FVcsBranchGitUncommitted := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitUncommitted),
    [TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitCarry),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitStash),
    TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitAsk)]);
  FVcsBranchGitUncommitted.Width := 320;
  FVcsBranchGitWorktree := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitWorktree));
  FVcsBranchGitWorktreeFolder := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitWorktreeFolder));
  AddWrappedLabel(52, TAtlasStrings.Text(TAtlasTextId.SettingsVcsBranchGitHint)).Font.Color := clGrayText;
end;

procedure TAtlasSettingsPage.AddVcsTool(AKind: TAtlasVcsKind; ACaption: TAtlasTextId);
var
  mPanel: TWinControl;
  mEdit: TEdit;
  mButton: TButton;
  mState: TLabel;
begin
  mEdit := AddTextLine(TAtlasStrings.Text(ACaption));
  mEdit.Width := 466 - 2 * 36 - 60;
  mEdit.Tag := Ord(AKind);
  mEdit.OnChange := VcsPathChange;
  mPanel := mEdit.Parent;
  mButton := TButton.Create(Self);
  mButton.Parent := mPanel;
  mButton.Caption := '…';
  mButton.Left := mEdit.Left + mEdit.Width + 6;
  mButton.Top := 0;
  mButton.Width := 30;
  mButton.Anchors := [akTop, akRight];
  mButton.Tag := Ord(AKind);
  mButton.OnClick := VcsBrowseClick;
  FVcsBrowse[AKind] := mButton;
  mButton := TButton.Create(Self);
  mButton.Parent := mPanel;
  mButton.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsCheck);
  mButton.Left := FVcsBrowse[AKind].Left + 36;
  mButton.Top := 0;
  mButton.Width := 90;
  mButton.Anchors := [akTop, akRight];
  mButton.Tag := Ord(AKind);
  mButton.OnClick := VcsCheckClick;
  FVcsCheck[AKind] := mButton;
  FVcsPaths[AKind] := mEdit;
  mPanel := AddPanel(18);
  mState := TLabel.Create(Self);
  mState.Parent := mPanel;
  mState.Left := 0;
  mState.Top := 0;
  mState.ShowAccelChar := False;
  mState.Font.Color := clGrayText;
  FVcsStates[AKind] := mState;
  Attach(mPanel, mEdit);
end;

function TAtlasSettingsPage.AddVcsLink(AParent: TWinControl; ALeft: Integer; ACaption: TAtlasTextId): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := TAtlasStrings.Text(ACaption);
  Result.Left := ALeft;
  Result.Top := 3;
  Result.Width := 150;
  Result.OnClick := VcsLinkClick;
end;

function TAtlasSettingsPage.VcsPath(AKind: TAtlasVcsKind): TEdit;
begin
  Result := FVcsPaths[AKind];
end;

function TAtlasSettingsPage.VcsCheckButton(AKind: TAtlasVcsKind): TButton;
begin
  Result := FVcsCheck[AKind];
end;

function TAtlasSettingsPage.VcsState(AKind: TAtlasVcsKind): TLabel;
begin
  Result := FVcsStates[AKind];
end;

class function TAtlasSettingsPage.VcsSourceText(ASource: TAtlasVcsToolSource): string;
begin
  case ASource of
    TAtlasVcsToolSource.Path:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsSourcePath);
    TAtlasVcsToolSource.KnownDir:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsSourceKnownDir);
    TAtlasVcsToolSource.Configured:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsSourceConfigured);
  else
    Result := '';
  end;
end;

class function TAtlasSettingsPage.VcsLocationText(const ALocation: TAtlasVcsToolLocation): string;
begin
  if ALocation.Source = TAtlasVcsToolSource.ConfiguredMissing then
    Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsToolConfiguredMissing, [ALocation.Configured])
  else if ALocation.Executable = '' then
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsToolMissing)
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsToolWouldUse,
      [ALocation.Executable, VcsSourceText(ALocation.Source)]);
end;

class function TAtlasSettingsPage.VcsCheckText(const ACheck: TAtlasVcsToolCheck): string;
begin
  case ACheck.State of
    TAtlasVcsToolState.Found:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsToolFound,
        [ACheck.Version, ACheck.Location.Executable, VcsSourceText(ACheck.Location.Source)]);
    TAtlasVcsToolState.StartFailed:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsToolStartFailed, [ACheck.ExitCode]);
    TAtlasVcsToolState.NoAnswer:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsToolNoAnswer);
    TAtlasVcsToolState.NotRecognized:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsToolNotRecognized,
        [TAtlasVcsTools.ProgramName(ACheck.Kind)]);
  else
    Result := VcsLocationText(ACheck.Location);
  end;
end;

class function TAtlasSettingsPage.VcsProjectText(const AState: TAtlasVcsProjectState): string;
var
  mName, mKind, mHead, mSource: string;
begin
  if AState.ProjectFile = '' then
    Exit(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectNone));
  mName := ExtractFileName(AState.ProjectFile);
  case AState.Source of
    TAtlasVcsProviderSource.Project:
      mSource := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsSourceProject, [AState.SourceMatch]);
    TAtlasVcsProviderSource.TeamFile:
      mSource := TAtlasStrings.Text(TAtlasTextId.SettingsVcsSourceTeamFile);
  else
    mSource := TAtlasStrings.Text(TAtlasTextId.SettingsVcsSourceSetting);
  end;
  if AState.MainBranch <> '' then
    mSource := mSource + TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectMainBranch, [AState.MainBranch]);
  mKind := AtlasVcsKindName(AState.WorkingCopy.Kind);
  case AState.Outcome of
    TAtlasVcsOutcome.Disabled:
      Exit(TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectDisabled, [mName]) + sLineBreak + mSource);
    TAtlasVcsOutcome.NoWorkingCopy:
      Exit(TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectNoWorkingCopy, [mName]) + sLineBreak + mSource);
    TAtlasVcsOutcome.ToolMissing:
      Exit(TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectToolMissing,
        [mName, mKind, TAtlasVcsTools.ProgramName(AState.WorkingCopy.Kind)]) + sLineBreak + mSource);
    TAtlasVcsOutcome.Ok:
      ;
  else
    Exit(TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectFailed, [mName, mKind, AtlasVcsOutcomeName(AState.Outcome)]) +
      sLineBreak + mSource);
  end;
  if AState.WorkingCopy.Kind = TAtlasVcsKind.Svn then
    mHead := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectSvnPath,
      [AState.Head.Branch, AState.Head.ShortRevision(AState.WorkingCopy.Kind)])
  else if AState.Head.Detached then
    mHead := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectDetached,
      [AState.Head.ShortRevision(AState.WorkingCopy.Kind)])
  else
    mHead := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectBranch,
      [AState.Head.Branch, AState.Head.ShortRevision(AState.WorkingCopy.Kind)]);
  if AState.Head.Upstream <> '' then
    mHead := mHead + TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectUpstream, [AState.Head.Upstream]);
  Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectLine, [mName, mKind, AState.WorkingCopy.Root]) +
    sLineBreak + mHead + sLineBreak + mSource;
end;

procedure TAtlasSettingsPage.RefreshVcsTool(AKind: TAtlasVcsKind);
begin
  if FVcsStates[AKind] = nil then
    Exit;
  if not Assigned(FOnVcsLocate) then
  begin
    FVcsStates[AKind].Caption := '';
    Exit;
  end;
  FVcsStates[AKind].Caption := VcsLocationText(FOnVcsLocate(AKind, Trim(FVcsPaths[AKind].Text)));
end;

procedure TAtlasSettingsPage.VcsPathChange(Sender: TObject);
begin
  // Nur Dateiprüfung; „Prüfen“ startet erst auf Klick einen Prozess.
  RefreshVcsTool(TAtlasVcsKind((Sender as TComponent).Tag));
end;

procedure TAtlasSettingsPage.VcsBrowseClick(Sender: TObject);
var
  mKind: TAtlasVcsKind;
  mDialog: TOpenDialog;
begin
  mKind := TAtlasVcsKind((Sender as TComponent).Tag);
  mDialog := TOpenDialog.Create(nil);
  try
    mDialog.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsVcsFilter);
    mDialog.Options := mDialog.Options + [ofFileMustExist];
    mDialog.FileName := Trim(FVcsPaths[mKind].Text);
    if mDialog.FileName = '' then
      mDialog.FileName := TAtlasVcsTools.ProgramName(mKind) + '.exe';
    if mDialog.Execute then
      FVcsPaths[mKind].Text := mDialog.FileName;
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasSettingsPage.VcsCheckClick(Sender: TObject);
var
  mKind: TAtlasVcsKind;
begin
  mKind := TAtlasVcsKind((Sender as TComponent).Tag);
  if not Assigned(FOnVcsCheck) then
    Exit;
  FVcsStates[mKind].Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsToolChecking);
  Allow(FVcsCheck[mKind], False);
  FOnVcsCheck(mKind, Trim(FVcsPaths[mKind].Text));
end;

procedure TAtlasSettingsPage.VcsCheckDone(const ACheck: TAtlasVcsToolCheck);
begin
  if (ACheck.Kind = TAtlasVcsKind.None) or (FVcsStates[ACheck.Kind] = nil) then
    Exit;
  FVcsStates[ACheck.Kind].Caption := VcsCheckText(ACheck);
  Allow(FVcsCheck[ACheck.Kind], True);
end;

procedure TAtlasSettingsPage.RefreshVcsProject;
begin
  FVcsProjectAsked := True;
  if not Assigned(FOnVcsProject) then
    Exit;
  FVcsProjectInfo.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectQuerying);
  FOnVcsProject();
end;

procedure TAtlasSettingsPage.VcsProjectDone(const AState: TAtlasVcsProjectState);
begin
  if FVcsProjectInfo <> nil then
    FVcsProjectInfo.Caption := VcsProjectText(AState);
  // Für „Aktuelles Projekt hinzufügen“: die erkannte Art vorbelegen.
  FVcsDetectedProject := AState.ProjectFile;
  FVcsDetectedKind := AState.WorkingCopy.Kind;
end;

procedure TAtlasSettingsPage.SheetShown(ASheet: TTabSheet);
var
  mParent: TControl;
begin
  if (ASheet = nil) or FVcsProjectAsked or (FVcsProvider = nil) then
    Exit;
  mParent := FVcsProvider;
  while (mParent <> nil) and (mParent <> ASheet) do
    mParent := mParent.Parent;
  if mParent <> nil then
    RefreshVcsProject;
end;

procedure TAtlasSettingsPage.VcsLinkClick(Sender: TObject);
begin
  if Sender = FVcsLinkEditor then
    SelectPage(PageOf(FGitGutter))
  else if Sender = FVcsLinkWelcome then
    SelectPage(PageOf(FWelcomeRefreshVcs))
  else if Sender = FVcsLinkIssues then
    SelectPage(PageOf(FIssuesBranchPattern));
end;

// Art und Hauptbranch je Projekt (#1286): wie die Tabelle Projekte der Seite Issue-Tracker (#1261), dieselbe
// Auflösung (Atlas.Core.Projects.Matching).

procedure TAtlasSettingsPage.AddVcsProjectsSection;

  function AddMenuItem(AId: TAtlasTextId; AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(Self);
    Result.Caption := TAtlasStrings.Text(AId);
    Result.OnClick := AClick;
    FVcsProjectAddMenu.Items.Add(Result);
  end;

var
  mPanel: TWinControl;
  mHint: TLabel;
begin
  FVcsProjectSelected := -1;
  FVcsContext := TAtlasVcsProjectContext.Empty;
  FVcsDetectedKind := TAtlasVcsKind.None;
  AddTitle(TAtlasTextId.SettingsVcsProjects);
  mPanel := AddPanel(110);
  // Die Zeilen erst mit Fenster (RefreshVcsProjects, auch aus CreateWnd).
  FVcsProjectList := TListView.Create(Self);
  FVcsProjectList.Parent := mPanel;
  FVcsProjectList.Align := alClient;
  FVcsProjectList.ViewStyle := vsReport;
  FVcsProjectList.ReadOnly := True;
  FVcsProjectList.RowSelect := True;
  FVcsProjectList.HideSelection := False;
  FVcsProjectList.OnSelectItem := VcsProjectSelectItem;
  FVcsProjectList.OnCustomDrawItem := VcsProjectDrawItem;
  AddTrackerColumn(FVcsProjectList, TAtlasTextId.SettingsIssuesProjectMatch, 230);
  AddTrackerColumn(FVcsProjectList, TAtlasTextId.SettingsVcsProjectsKind, 90);
  AddTrackerColumn(FVcsProjectList, TAtlasTextId.SettingsVcsProjectsMainBranch, 100);
  AddTrackerColumn(FVcsProjectList, TAtlasTextId.SettingsIssuesProjectSource, 150);
  FVcsProjectMatch := TEdit.Create(Self);
  FVcsProjectMatch.OnChange := VcsProjectMatchChange;
  mPanel := AddTrackerLabelled(TAtlasTextId.SettingsIssuesProjectMatch, FVcsProjectMatch, 376);
  FVcsProjectMatch.Anchors := [akLeft, akTop, akRight];
  Attach(mPanel, FVcsProjectList);
  // Reihenfolge wie die Werte von vcs.projects[].provider (auto, git, svn, off).
  FVcsProjectProvider := TAtlasChoiceBox.Create(Self);
  FVcsProjectProvider.OnChange := VcsProjectProviderChange;
  Attach(AddTrackerLabelled(TAtlasTextId.SettingsVcsProjectsKind, FVcsProjectProvider, 180), FVcsProjectList);
  FVcsProjectProvider.SetChoices(TArray<string>.Create(VcsProviderCaption('auto'), VcsProviderCaption('git'),
    VcsProviderCaption('svn'), VcsProviderCaption('off')));
  FVcsProjectMainBranch := TEdit.Create(Self);
  FVcsProjectMainBranch.OnChange := VcsProjectMainBranchChange;
  Attach(AddTrackerLabelled(TAtlasTextId.SettingsVcsProjectsMainBranch, FVcsProjectMainBranch, 180),
    FVcsProjectList);
  FVcsProjectMainBranch.TextHint := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsGuess);
  // Grund, warum eine Zeile nicht greift oder nicht übernommen wird (.atlas, Pfad doppelt, Leerraum).
  mPanel := AddPanel(18);
  FVcsProjectNote := TLabel.Create(Self);
  FVcsProjectNote.Parent := mPanel;
  FVcsProjectNote.Left := 90;
  FVcsProjectNote.Top := 1;
  FVcsProjectNote.Font.Color := clRed;
  Attach(mPanel, FVcsProjectList);
  // Zustand und Zuständigkeit je Verbindung (#1266); leer gilt „Zustand im Tracker“ weiter unten.
  FIssuesConnectionStateField := TAtlasValueBox.Create(Self);
  FIssuesConnectionStateField.OnChange := TrackerWorkflowChange;
  Attach(AddLabelled(TAtlasTextId.SettingsIssuesConnectionStateField, FIssuesConnectionStateField, 180),
    FIssuesConnections);
  FIssuesConnectionAssigneeField := TAtlasValueBox.Create(Self);
  FIssuesConnectionAssigneeField.OnChange := TrackerWorkflowChange;
  Attach(AddLabelled(TAtlasTextId.SettingsIssuesConnectionAssigneeField, FIssuesConnectionAssigneeField, 180),
    FIssuesConnections);
  FIssuesConnectionStartState := TAtlasValueBox.Create(Self);
  FIssuesConnectionStartState.OnChange := TrackerWorkflowChange;
  Attach(AddLabelled(TAtlasTextId.SettingsIssuesConnectionStartState, FIssuesConnectionStartState, 180),
    FIssuesConnections);
  FIssuesConnectionEndStates := TEdit.Create(Self);
  FIssuesConnectionEndStates.OnChange := TrackerWorkflowChange;
  mPanel := AddLabelled(TAtlasTextId.SettingsIssuesConnectionEndStates, FIssuesConnectionEndStates, 376);
  FIssuesConnectionEndStates.Anchors := [akLeft, akTop, akRight];
  Attach(mPanel, FIssuesConnections);
  mPanel := AddPanel(18);
  mHint := TLabel.Create(Self);
  mHint.Parent := mPanel;
  mHint.Left := 90;
  mHint.Top := 1;
  mHint.Font.Color := clGrayText;
  mHint.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionStatesHint);
  Attach(mPanel, FIssuesConnections);
  mPanel := AddPanel(32);
  FVcsProjectAddCurrent := AddTrackerButton(mPanel, 0, 180, TAtlasTextId.SettingsIssuesProjectAddCurrent,
    VcsProjectAddCurrentClick);
  FVcsProjectAdd := AddTrackerButton(mPanel, 186, 110, TAtlasTextId.SettingsIssuesProjectAdd, VcsProjectAddClick);
  FVcsProjectRemove := AddTrackerButton(mPanel, 302, 100, TAtlasTextId.SettingsIssuesConnectionRemove,
    VcsProjectRemoveClick);
  Attach(mPanel, FVcsProjectList);
  // „Hinzufügen …“: Projektdatei oder Ordner (z. B. ein Paketordner aus SVN-Externals).
  FVcsProjectAddMenu := TPopupMenu.Create(Self);
  AddMenuItem(TAtlasTextId.SettingsIssuesProjectAddFile, VcsProjectAddFileClick);
  AddMenuItem(TAtlasTextId.SettingsIssuesProjectAddFolder, VcsProjectAddFolderClick);
  mHint := AddWrappedLabel(52, TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsHint));
  mHint.Font.Color := clGrayText;
  Attach(mHint.Parent, FVcsProjectList);
end;

class function TAtlasSettingsPage.VcsProviderCaption(const AProvider: string): string;
begin
  case IndexText(AProvider, ['git', 'svn', 'off']) of
    0:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderGit);
    1:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderSvn);
    2:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderOff);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderAuto);
  end;
end;

function TAtlasSettingsPage.VcsProjectRows: TArray<TAtlasVcsProjectMapping>;
begin
  Result := FVcsProjects + FVcsContext.Team;
end;

function TAtlasSettingsPage.VcsProjectEditable: Boolean;
begin
  Result := (FVcsProjectSelected >= 0) and (FVcsProjectSelected < Length(FVcsProjects));
end;

function TAtlasSettingsPage.VcsProjectCovered(const AMapping: TAtlasVcsProjectMapping): Boolean;
begin
  Result := TAtlasVcsProjects.Covered(AMapping, FVcsContext.HasTeam, FVcsContext.ProjectFile,
    FVcsContext.GroupFile);
end;

function TAtlasSettingsPage.VcsProjectSourceText(const AMapping: TAtlasVcsProjectMapping): string;
begin
  if AMapping.ReadOnly then
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectTeam)
  else if VcsProjectCovered(AMapping) then
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectCovered)
  else
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectPersonal);
end;

procedure TAtlasSettingsPage.VcsProjectShowItem(AIndex: Integer);
var
  mRows: TArray<TAtlasVcsProjectMapping>;
  mItem: TListItem;
  mBranch: string;
begin
  mRows := VcsProjectRows;
  if (AIndex < 0) or (AIndex > High(mRows)) or not FVcsProjectList.HandleAllocated or
    (AIndex >= FVcsProjectList.Items.Count) then
    Exit;
  mItem := FVcsProjectList.Items[AIndex];
  mItem.Caption := mRows[AIndex].Match;
  mBranch := mRows[AIndex].MainBranch;
  if mBranch = '' then
    mBranch := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsGuess);
  mItem.SubItems.Clear;
  mItem.SubItems.Add(VcsProviderCaption(mRows[AIndex].Provider));
  mItem.SubItems.Add(mBranch);
  mItem.SubItems.Add(VcsProjectSourceText(mRows[AIndex]));
end;

procedure TAtlasSettingsPage.RefreshVcsProjects;
var
  mRows: TArray<TAtlasVcsProjectMapping>;
  mIndex: Integer;
begin
  if FVcsProjectList = nil then
    Exit;
  FVcsContext := TAtlasVcsProjectContext.Empty;
  if Assigned(FOnVcsContext) then
    FVcsContext := FOnVcsContext();
  mRows := VcsProjectRows;
  if FVcsProjectSelected > High(mRows) then
    FVcsProjectSelected := High(mRows);
  if FVcsProjectList.HandleAllocated then
  begin
    FVcsProjectFilling := True;
    FVcsProjectList.Items.BeginUpdate;
    try
      FVcsProjectList.Items.Clear;
      for mIndex := 0 to High(mRows) do
      begin
        FVcsProjectList.Items.Add;
        VcsProjectShowItem(mIndex);
      end;
      if FVcsProjectSelected >= 0 then
        FVcsProjectList.Items[FVcsProjectSelected].Selected := True;
    finally
      FVcsProjectList.Items.EndUpdate;
      FVcsProjectFilling := False;
    end;
  end;
  VcsProjectFillFields;
  RefreshVcsServers;
end;

procedure TAtlasSettingsPage.VcsProjectNoteFor(const AMapping: TAtlasVcsProjectMapping);
begin
  if AMapping.ReadOnly then
    FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectReadOnly)
  else if VcsProjectCovered(AMapping) then
    FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsCoveredHint)
  else
    FVcsProjectNote.Caption := '';
end;

procedure TAtlasSettingsPage.VcsProjectFillFields;
var
  mRows: TArray<TAtlasVcsProjectMapping>;
  mSelected, mEditable: Boolean;
begin
  mRows := VcsProjectRows;
  mSelected := (FVcsProjectSelected >= 0) and (FVcsProjectSelected <= High(mRows));
  mEditable := VcsProjectEditable;
  FVcsProjectFilling := True;
  try
    if mSelected then
    begin
      FVcsProjectMatch.Text := mRows[FVcsProjectSelected].Match;
      FVcsProjectMainBranch.Text := mRows[FVcsProjectSelected].MainBranch;
      FVcsProjectProvider.Choice := Max(0, IndexText(mRows[FVcsProjectSelected].Provider,
        ['auto', 'git', 'svn', 'off']));
      VcsProjectNoteFor(mRows[FVcsProjectSelected]);
    end
    else
    begin
      FVcsProjectMatch.Text := '';
      FVcsProjectMainBranch.Text := '';
      FVcsProjectProvider.Choice := -1;
      FVcsProjectNote.Caption := '';
    end;
  finally
    FVcsProjectFilling := False;
  end;
  Allow(FVcsProjectMatch, mEditable);
  Allow(FVcsProjectProvider, mEditable);
  Allow(FVcsProjectMainBranch, mEditable);
  Allow(FVcsProjectRemove, mEditable);
  Allow(FVcsProjectAddCurrent, FVcsContext.ProjectFile <> '');
end;

procedure TAtlasSettingsPage.VcsProjectSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FVcsProjectFilling or not Selected or (Item = nil) then
    Exit;
  FVcsProjectSelected := Item.Index;
  VcsProjectFillFields;
end;

procedure TAtlasSettingsPage.VcsProjectDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mRows: TArray<TAtlasVcsProjectMapping>;
begin
  // Von der .atlas überdeckte persönliche Zeile grau.
  mRows := VcsProjectRows;
  if (Item <> nil) and (Item.Index <= High(mRows)) and VcsProjectCovered(mRows[Item.Index]) then
    Sender.Canvas.Font.Color := clGrayText;
  DefaultDraw := True;
end;

procedure TAtlasSettingsPage.VcsProjectMatchChange(Sender: TObject);
var
  mMatch: string;
  mOther: Integer;
begin
  if FVcsProjectFilling or not VcsProjectEditable then
    Exit;
  mMatch := Trim(FVcsProjectMatch.Text);
  // Ein Pfad hat höchstens eine persönliche Zeile.
  mOther := TAtlasVcsProjects.IndexOfMatch(FVcsProjects, mMatch);
  if (mMatch <> '') and (mOther >= 0) and (mOther <> FVcsProjectSelected) then
  begin
    FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatchTaken);
    Exit;
  end;
  FVcsProjects[FVcsProjectSelected].Match := mMatch;
  VcsProjectNoteFor(FVcsProjects[FVcsProjectSelected]);
  VcsProjectShowItem(FVcsProjectSelected);
end;

procedure TAtlasSettingsPage.VcsProjectProviderChange(Sender: TObject);
var
  mChoice: Integer;
begin
  mChoice := FVcsProjectProvider.Choice;
  if FVcsProjectFilling or not VcsProjectEditable or (mChoice < 0) or (mChoice > 3) then
    Exit;
  case mChoice of
    1:
      FVcsProjects[FVcsProjectSelected].Provider := 'git';
    2:
      FVcsProjects[FVcsProjectSelected].Provider := 'svn';
    3:
      FVcsProjects[FVcsProjectSelected].Provider := 'off';
  else
    FVcsProjects[FVcsProjectSelected].Provider := 'auto';
  end;
  VcsProjectShowItem(FVcsProjectSelected);
end;

procedure TAtlasSettingsPage.VcsProjectMainBranchChange(Sender: TObject);
var
  mBranch: string;
  mIndex: Integer;
begin
  if FVcsProjectFilling or not VcsProjectEditable then
    Exit;
  mBranch := Trim(FVcsProjectMainBranch.Text);
  // Wie der Server (vcs.projects[].mainBranch): ein Branchname ohne Leerraum.
  for mIndex := 1 to Length(mBranch) do
    if CharInSet(mBranch[mIndex], [' ', #9]) then
    begin
      FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsBranchInvalid);
      Exit;
    end;
  FVcsProjects[FVcsProjectSelected].MainBranch := mBranch;
  VcsProjectNoteFor(FVcsProjects[FVcsProjectSelected]);
  VcsProjectShowItem(FVcsProjectSelected);
end;

procedure TAtlasSettingsPage.VcsProjectAdd(const AMatch, AProvider: string);
var
  mIndex: Integer;
begin
  if Trim(AMatch) = '' then
    Exit;
  mIndex := TAtlasVcsProjects.IndexOfMatch(FVcsProjects, AMatch);
  if mIndex < 0 then
  begin
    FVcsProjects := FVcsProjects + [TAtlasVcsProjectMapping.Create(AMatch, AProvider, '')];
    mIndex := High(FVcsProjects);
  end;
  FVcsProjectSelected := mIndex;
  RefreshVcsProjects;
  if FVcsProjectMainBranch.CanFocus then
    FVcsProjectMainBranch.SetFocus;
end;

procedure TAtlasSettingsPage.VcsProjectAddCurrentClick(Sender: TObject);
var
  mMatch, mProvider: string;
begin
  RefreshVcsProjects;
  if FVcsContext.ProjectFile = '' then
  begin
    FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectNoProject);
    Exit;
  end;
  // Die geöffnete .groupproj, sonst die aktive .dproj; Art vorbelegt mit der erkannten Arbeitskopie.
  mMatch := TAtlasProjectMatching.CurrentMatch(FVcsContext.ProjectFile, FVcsContext.GroupFile);
  mProvider := 'auto';
  if SameText(FVcsDetectedProject, FVcsContext.ProjectFile) then
    case FVcsDetectedKind of
      TAtlasVcsKind.Git:
        mProvider := 'git';
      TAtlasVcsKind.Svn:
        mProvider := 'svn';
    end;
  VcsProjectAdd(mMatch, mProvider);
end;

procedure TAtlasSettingsPage.VcsProjectAddClick(Sender: TObject);
begin
  // Unter dem Knopf aufklappen.
  FVcsProjectAddMenu.Popup(FVcsProjectAdd.ClientOrigin.X, FVcsProjectAdd.ClientOrigin.Y + FVcsProjectAdd.Height);
end;

procedure TAtlasSettingsPage.VcsProjectAddFileClick(Sender: TObject);
var
  mPath: string;
begin
  if TrackerBrowse(False, mPath) then
    VcsProjectAdd(mPath, 'auto');
end;

procedure TAtlasSettingsPage.VcsProjectAddFolderClick(Sender: TObject);
var
  mPath: string;
begin
  if TrackerBrowse(True, mPath) then
    VcsProjectAdd(mPath, 'auto');
end;

procedure TAtlasSettingsPage.VcsProjectRemoveClick(Sender: TObject);
begin
  if not VcsProjectEditable then
    Exit;
  Delete(FVcsProjects, FVcsProjectSelected, 1);
  if FVcsProjectSelected > High(VcsProjectRows) then
    FVcsProjectSelected := High(VcsProjectRows);
  RefreshVcsProjects;
end;

function TAtlasSettingsPage.VcsProjectsJson: string;
var
  mKept: TArray<TAtlasVcsProjectMapping>;
  mMapping: TAtlasVcsProjectMapping;
begin
  mKept := nil;
  for mMapping in FVcsProjects do
    if (mMapping.Match <> '') and (TAtlasVcsProjects.IndexOfMatch(mKept, mMapping.Match) < 0) then
      mKept := mKept + [mMapping];
  Result := TAtlasVcsProjects.ToJson(mKept);
end;

// Serverzugang (#1287): nur auf Klick, Zustand aus der Sitzung.

procedure TAtlasSettingsPage.AddVcsServersSection;
var
  mPanel: TWinControl;
  mHint: TLabel;
begin
  FVcsServerSelected := -1;
  AddTitle(TAtlasTextId.SettingsVcsServers);
  mPanel := AddPanel(96);
  FVcsServerList := TListView.Create(Self);
  FVcsServerList.Parent := mPanel;
  FVcsServerList.Align := alClient;
  FVcsServerList.ViewStyle := vsReport;
  FVcsServerList.ReadOnly := True;
  FVcsServerList.RowSelect := True;
  FVcsServerList.HideSelection := False;
  FVcsServerList.OnSelectItem := VcsServerSelectItem;
  AddTrackerColumn(FVcsServerList, TAtlasTextId.SettingsVcsServerProject, 170);
  AddTrackerColumn(FVcsServerList, TAtlasTextId.SettingsVcsServerServer, 200);
  AddTrackerColumn(FVcsServerList, TAtlasTextId.SettingsVcsServerState, 180);
  mPanel := AddPanel(32);
  FVcsServerCheck := AddTrackerButton(mPanel, 0, 100, TAtlasTextId.SettingsVcsServerCheck, VcsServerCheckClick);
  FVcsServerCheckAll := AddTrackerButton(mPanel, 106, 110, TAtlasTextId.SettingsVcsServerCheckAll,
    VcsServerCheckAllClick);
  FVcsServerLogin := AddTrackerButton(mPanel, 222, 110, TAtlasTextId.SettingsVcsServerLogin, VcsServerLoginClick);
  Attach(mPanel, FVcsServerList);
  mPanel := AddPanel(18);
  FVcsServerNote := TLabel.Create(Self);
  FVcsServerNote.Parent := mPanel;
  FVcsServerNote.Left := 0;
  FVcsServerNote.Top := 1;
  Attach(mPanel, FVcsServerList);
  mHint := AddWrappedLabel(52, TAtlasStrings.Text(TAtlasTextId.SettingsVcsServersHint));
  mHint.Font.Color := clGrayText;
  Attach(mHint.Parent, FVcsServerList);
end;

class function TAtlasSettingsPage.VcsServerStateText(const ACheck: TAtlasVcsServerCheck;
  AChecking: Boolean): string;
begin
  if AChecking then
    Exit(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerChecking));
  case ACheck.State of
    TAtlasVcsServerState.Reachable:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsServerReachable,
        [FormatDateTime('hh:nn', ACheck.CheckedAt)]);
    TAtlasVcsServerState.LoginNeeded:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginNeeded);
    TAtlasVcsServerState.Unreachable:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerUnreachable);
    TAtlasVcsServerState.NoServer:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerNoServer);
    TAtlasVcsServerState.ToolMissing:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerToolMissing);
    TAtlasVcsServerState.Failed:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerFailed);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerUnknown);
  end;
end;

procedure TAtlasSettingsPage.RefreshVcsServers;

  procedure AddRow(const AName, AFolder: string);
  var
    mRow: TAtlasVcsServerRow;
  begin
    if AFolder = '' then
      Exit;
    for mRow in FVcsServerRows do
      if SameText(mRow.Folder, AFolder) then
        Exit;
    mRow.Name := AName;
    mRow.Folder := AFolder;
    mRow.Check := TAtlasVcsServerCheck.Empty;
    if Assigned(FOnVcsServerState) then
      mRow.Check := FOnVcsServerState(AFolder);
    mRow.Checking := False;
    FVcsServerRows := FVcsServerRows + [mRow];
  end;

var
  mOld: TArray<TAtlasVcsServerRow>;
  mOldRow: TAtlasVcsServerRow;
  mMapping: TAtlasVcsProjectMapping;
  mIndex: Integer;
begin
  if FVcsServerList = nil then
    Exit;
  mOld := FVcsServerRows;
  FVcsServerRows := nil;
  // Erst das aktuelle Projekt, dann die Zeilen der Tabelle Projekte; .dproj und .groupproj gelten für ihren Ordner.
  if FVcsContext.ProjectFile <> '' then
    AddRow(ExtractFileName(TAtlasProjectMatching.CurrentMatch(FVcsContext.ProjectFile, FVcsContext.GroupFile)),
      ExtractFileDir(FVcsContext.ProjectFile));
  for mMapping in VcsProjectRows do
    if mMapping.Kind = TAtlasProjectMatch.Folder then
      AddRow(ExtractFileName(ExcludeTrailingPathDelimiter(mMapping.Match)),
        ExcludeTrailingPathDelimiter(mMapping.Match))
    else
      AddRow(ExtractFileName(mMapping.Match), ExtractFileDir(mMapping.Match));
  if FVcsServerExtra <> '' then
    AddRow(ExtractFileName(FVcsServerExtra), FVcsServerExtra);
  // Laufende Prüfungen bleiben sichtbar.
  for mIndex := 0 to High(FVcsServerRows) do
    for mOldRow in mOld do
      if mOldRow.Checking and SameText(mOldRow.Folder, FVcsServerRows[mIndex].Folder) then
        FVcsServerRows[mIndex].Checking := True;
  if FVcsServerSelected > High(FVcsServerRows) then
    FVcsServerSelected := High(FVcsServerRows);
  if (FVcsServerSelected < 0) and (Length(FVcsServerRows) > 0) then
    FVcsServerSelected := 0;
  if FVcsServerList.HandleAllocated then
  begin
    FVcsServerList.Items.BeginUpdate;
    try
      FVcsServerList.Items.Clear;
      for mIndex := 0 to High(FVcsServerRows) do
      begin
        FVcsServerList.Items.Add;
        VcsServerShowItem(mIndex);
      end;
      if FVcsServerSelected >= 0 then
        FVcsServerList.Items[FVcsServerSelected].Selected := True;
    finally
      FVcsServerList.Items.EndUpdate;
    end;
  end;
  VcsServerFillButtons;
end;

procedure TAtlasSettingsPage.VcsServerShowItem(AIndex: Integer);
var
  mItem: TListItem;
  mServer: string;
begin
  if (AIndex < 0) or (AIndex > High(FVcsServerRows)) or not FVcsServerList.HandleAllocated or
    (AIndex >= FVcsServerList.Items.Count) then
    Exit;
  mItem := FVcsServerList.Items[AIndex];
  mItem.Caption := FVcsServerRows[AIndex].Name;
  mServer := FVcsServerRows[AIndex].Check.ServerText;
  if mServer = '' then
    mServer := '–';
  mItem.SubItems.Clear;
  mItem.SubItems.Add(mServer);
  mItem.SubItems.Add(VcsServerStateText(FVcsServerRows[AIndex].Check, FVcsServerRows[AIndex].Checking));
end;

procedure TAtlasSettingsPage.VcsServerFillButtons;
var
  mSelected: Boolean;
begin
  mSelected := (FVcsServerSelected >= 0) and (FVcsServerSelected <= High(FVcsServerRows));
  Allow(FVcsServerCheck, mSelected and Assigned(FOnVcsServerCheck) and
    not FVcsServerRows[Max(0, FVcsServerSelected)].Checking);
  Allow(FVcsServerCheckAll, (Length(FVcsServerRows) > 0) and Assigned(FOnVcsServerCheck));
  Allow(FVcsServerLogin, mSelected and Assigned(FOnVcsServerLogin) and
    FVcsServerRows[Max(0, FVcsServerSelected)].Check.CanLogin);
end;

procedure TAtlasSettingsPage.VcsServerStart(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FVcsServerRows)) or not Assigned(FOnVcsServerCheck) or
    FVcsServerRows[AIndex].Checking then
    Exit;
  FVcsServerRows[AIndex].Checking := True;
  VcsServerShowItem(AIndex);
  VcsServerFillButtons;
  FOnVcsServerCheck(FVcsServerRows[AIndex].Folder);
end;

procedure TAtlasSettingsPage.RevealVcsServer(const AFolder: string);
var
  mIndex: Integer;
begin
  if (FVcsServerList = nil) or (Trim(AFolder) = '') then
    Exit;
  FVcsServerExtra := ExcludeTrailingPathDelimiter(Trim(AFolder));
  RefreshVcsServers;
  for mIndex := 0 to High(FVcsServerRows) do
    if SameText(FVcsServerRows[mIndex].Folder, FVcsServerExtra) then
    begin
      FVcsServerSelected := mIndex;
      if FVcsServerList.HandleAllocated and (mIndex < FVcsServerList.Items.Count) then
        FVcsServerList.Items[mIndex].Selected := True;
      SelectPage(PageOf(FVcsServerList));
      VcsServerStart(mIndex);
      Break;
    end;
end;

procedure TAtlasSettingsPage.VcsServerDone(const AFolder: string; const ACheck: TAtlasVcsServerCheck);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FVcsServerRows) do
    if SameText(FVcsServerRows[mIndex].Folder, AFolder) then
    begin
      FVcsServerRows[mIndex].Check := ACheck;
      FVcsServerRows[mIndex].Checking := False;
      VcsServerShowItem(mIndex);
    end;
  if FVcsServerNote <> nil then
    FVcsServerNote.Caption := '';
  VcsServerFillButtons;
end;

procedure TAtlasSettingsPage.VcsServerSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not Selected or (Item = nil) then
    Exit;
  FVcsServerSelected := Item.Index;
  VcsServerFillButtons;
end;

procedure TAtlasSettingsPage.VcsServerCheckClick(Sender: TObject);
begin
  VcsServerStart(FVcsServerSelected);
end;

procedure TAtlasSettingsPage.VcsServerCheckAllClick(Sender: TObject);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FVcsServerRows) do
    VcsServerStart(mIndex);
end;

procedure TAtlasSettingsPage.VcsServerLoginClick(Sender: TObject);
var
  mRow: TAtlasVcsServerRow;
begin
  if (FVcsServerSelected < 0) or (FVcsServerSelected > High(FVcsServerRows)) or not Assigned(FOnVcsServerLogin) then
    Exit;
  mRow := FVcsServerRows[FVcsServerSelected];
  if not mRow.Check.CanLogin then
    Exit;
  if FOnVcsServerLogin(mRow.Folder, mRow.Check) then
  begin
    // Nach dem Schließen der Konsole prüft der Aufrufer erneut und meldet VcsServerDone.
    FVcsServerRows[FVcsServerSelected].Checking := True;
    VcsServerShowItem(FVcsServerSelected);
    FVcsServerNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginOpen);
  end
  else
    FVcsServerNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginFailed);
  VcsServerFillButtons;
end;

procedure TAtlasSettingsPage.WelcomeIssuesLinkClick(Sender: TObject);
begin
  // Hauptknoten der Seite Issue-Tracker: dort steht der Anbieter.
  SelectPage(PageOf(FIssuesTracker));
end;

procedure TAtlasSettingsPage.AddTrackerConnectionsSection;
var
  mPanel: TWinControl;
begin
  FTrackerSelected := -1;
  FTrackerProviderNames := TArray<string>.Create('youtrack', 'github');
  FTrackerProviderCaptions := TArray<string>.Create('YouTrack', 'GitHub');
  AddTitle(TAtlasTextId.SettingsIssuesConnections);
  mPanel := AddPanel(110);
  // Die Zeilen brauchen ein Fenster: RefreshTrackerConnections füllt sie (auch aus CreateWnd).
  FIssuesConnections := TListView.Create(Self);
  FIssuesConnections.Parent := mPanel;
  FIssuesConnections.Align := alClient;
  FIssuesConnections.ViewStyle := vsReport;
  FIssuesConnections.ReadOnly := True;
  FIssuesConnections.RowSelect := True;
  FIssuesConnections.HideSelection := False;
  FIssuesConnections.OnSelectItem := TrackerSelectItem;
  AddTrackerColumn(FIssuesConnections, TAtlasTextId.SettingsIssuesConnectionName, 110);
  AddTrackerColumn(FIssuesConnections, TAtlasTextId.SettingsIssuesConnectionProvider, 80);
  AddTrackerColumn(FIssuesConnections, TAtlasTextId.SettingsIssuesConnectionUrl, 200);
  AddTrackerColumn(FIssuesConnections, TAtlasTextId.SettingsIssuesConnectionToken, 170);
  FIssuesConnectionName := TEdit.Create(Self);
  FIssuesConnectionName.OnChange := TrackerNameChange;
  Attach(AddTrackerLabelled(TAtlasTextId.SettingsIssuesConnectionName, FIssuesConnectionName, 180),
    FIssuesConnections);
  FIssuesConnectionProvider := TAtlasChoiceBox.Create(Self);
  FIssuesConnectionProvider.SetChoices(FTrackerProviderCaptions);
  FIssuesConnectionProvider.OnChange := TrackerProviderChange;
  Attach(AddTrackerLabelled(TAtlasTextId.SettingsIssuesConnectionProvider, FIssuesConnectionProvider, 180),
    FIssuesConnections);
  FIssuesConnectionUrl := TEdit.Create(Self);
  FIssuesConnectionUrl.OnChange := TrackerUrlChange;
  mPanel := AddTrackerLabelled(TAtlasTextId.SettingsIssuesConnectionUrl, FIssuesConnectionUrl, 376);
  FIssuesConnectionUrl.Anchors := [akLeft, akTop, akRight];
  Attach(mPanel, FIssuesConnections);
  // Grund, warum eine Eingabe nicht übernommen wird (nur https, Name vergeben …).
  mPanel := AddPanel(18);
  FIssuesConnectionNote := TLabel.Create(Self);
  FIssuesConnectionNote.Parent := mPanel;
  FIssuesConnectionNote.Left := 90;
  FIssuesConnectionNote.Top := 1;
  FIssuesConnectionNote.Font.Color := clRed;
  Attach(mPanel, FIssuesConnections);
  mPanel := AddPanel(32);
  FIssuesConnectionAdd := AddTrackerButton(mPanel, 0, 100, TAtlasTextId.SettingsIssuesConnectionAdd,
    TrackerAddClick);
  FIssuesConnectionRemove := AddTrackerButton(mPanel, 106, 100, TAtlasTextId.SettingsIssuesConnectionRemove,
    TrackerRemoveClick);
  FIssuesConnectionToken := AddTrackerButton(mPanel, 212, 140, TAtlasTextId.SettingsIssuesConnectionEnterToken,
    TrackerTokenClick);
  FIssuesConnectionCheck := AddTrackerButton(mPanel, 358, 140, TAtlasTextId.SettingsIssuesConnectionCheck,
    TrackerCheckClick);
  Attach(mPanel, FIssuesConnections);
  AddTrackerHint(TAtlasTextId.SettingsIssuesConnectionsHint, FIssuesConnections);
end;

function TAtlasSettingsPage.AddTrackerLabelled(AId: TAtlasTextId; AControl: TWinControl;
  AWidth: Integer): TWinControl;
var
  mCaption: TLabel;
begin
  Result := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Result;
  mCaption.Caption := TAtlasStrings.Text(AId) + ':';
  mCaption.Left := 0;
  mCaption.Top := 5;
  AControl.Parent := Result;
  AControl.Left := 90;
  AControl.Top := 1;
  AControl.Width := AWidth;
end;

function TAtlasSettingsPage.AddTrackerButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TAtlasTextId;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := TAtlasStrings.Text(AId);
  Result.Left := ALeft;
  Result.Top := 3;
  Result.Width := AWidth;
  Result.OnClick := AClick;
end;

procedure TAtlasSettingsPage.AddTrackerColumn(AList: TListView; AId: TAtlasTextId; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := TAtlasStrings.Text(AId);
  mColumn.Width := AWidth;
end;

procedure TAtlasSettingsPage.AddTrackerHint(AId: TAtlasTextId; AAnchor: TControl);
var
  mPanel: TWinControl;
  mHint: TLabel;
begin
  mPanel := AddPanel(34);
  mHint := TLabel.Create(Self);
  mHint.Parent := mPanel;
  mHint.Align := alClient;
  mHint.WordWrap := True;
  mHint.Font.Color := clGrayText;
  mHint.Caption := TAtlasStrings.Text(AId);
  Attach(mPanel, AAnchor);
end;

procedure TAtlasSettingsPage.SetTrackerProviders(const ANames, ACaptions: TArray<string>);
begin
  if (Length(ANames) = 0) or (Length(ANames) <> Length(ACaptions)) then
    Exit;
  FTrackerProviderNames := ANames;
  FTrackerProviderCaptions := ACaptions;
  FIssuesConnectionProvider.SetChoices(ACaptions);
  RefreshTrackerConnections;
end;

function TAtlasSettingsPage.TrackerRows: TArray<TAtlasTrackerConnection>;
begin
  Result := FTrackerConnections + FTrackerTeam;
end;

function TAtlasSettingsPage.TrackerProviderCaption(const AName: string): string;
var
  mIndex: Integer;
begin
  for mIndex := 0 to Min(High(FTrackerProviderNames), High(FTrackerProviderCaptions)) do
    if SameText(FTrackerProviderNames[mIndex], AName) then
      Exit(FTrackerProviderCaptions[mIndex]);
  Result := AName;
end;

function TAtlasSettingsPage.TrackerStateText(const AConnection: TAtlasTrackerConnection): string;
var
  mStatus: TAtlasTrackerTokenStatus;
begin
  if MatchText(AConnection.Target.CredentialTarget, FTrackerChecking) then
    Exit(TAtlasStrings.Text(TAtlasTextId.TrackerTokenChecking));
  mStatus := TAtlasTrackerTokenStatus.Stored(False);
  if Assigned(FOnTrackerState) and (AConnection.Target.Server <> '') then
    mStatus := FOnTrackerState(AConnection);
  case mStatus.State of
    TAtlasTrackerTokenState.Saved:
      Result := TAtlasStrings.Text(TAtlasTextId.TrackerTokenSaved);
    TAtlasTrackerTokenState.Verified:
      Result := TAtlasStrings.Fmt(TAtlasTextId.TrackerTokenVerified, [FormatDateTime('hh:nn', mStatus.CheckedAt)]);
    TAtlasTrackerTokenState.Rejected:
      Result := TAtlasStrings.Text(TAtlasTextId.TrackerTokenRejected);
    TAtlasTrackerTokenState.Unreachable:
      Result := TAtlasStrings.Text(TAtlasTextId.TrackerTokenUnreachable);
    TAtlasTrackerTokenState.Unexpected:
      if mStatus.HttpStatus > 0 then
        Result := TAtlasStrings.Fmt(TAtlasTextId.TrackerTokenUnexpectedStatus, [mStatus.HttpStatus])
      else
        Result := TAtlasStrings.Text(TAtlasTextId.TrackerTokenUnexpected);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.TrackerTokenMissing);
  end;
end;

function TAtlasSettingsPage.TrackerEditable: Boolean;
begin
  Result := (FTrackerSelected >= 0) and (FTrackerSelected < Length(FTrackerConnections));
end;

procedure TAtlasSettingsPage.RefreshTrackerConnections;
var
  mRows: TArray<TAtlasTrackerConnection>;
  mRow: TAtlasTrackerConnection;
  mItem: TListItem;
begin
  if FIssuesConnections = nil then
    Exit;
  FTrackerTeam := nil;
  if Assigned(FOnTrackerTeam) then
    FTrackerTeam := FOnTrackerTeam();
  mRows := TrackerRows;
  if FTrackerSelected > High(mRows) then
    FTrackerSelected := High(mRows);
  // Wie die Liste der Favoriten: ohne Fenster folgt das in CreateWnd.
  if FIssuesConnections.HandleAllocated then
  begin
    FTrackerFilling := True;
    FIssuesConnections.Items.BeginUpdate;
    try
      FIssuesConnections.Items.Clear;
      for mRow in mRows do
      begin
        mItem := FIssuesConnections.Items.Add;
        if mRow.ReadOnly then
          mItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsIssuesConnectionTeam, [mRow.Name])
        else
          mItem.Caption := mRow.Name;
        mItem.SubItems.Add(TrackerProviderCaption(mRow.Provider));
        mItem.SubItems.Add(mRow.Url);
        mItem.SubItems.Add(TrackerStateText(mRow));
      end;
      if FTrackerSelected >= 0 then
        FIssuesConnections.Items[FTrackerSelected].Selected := True;
    finally
      FIssuesConnections.Items.EndUpdate;
      FTrackerFilling := False;
    end;
  end;
  TrackerFillFields;
  // Die Auswahl der Verbindung in der Tabelle Projekte folgt den Verbindungen.
  RefreshTrackerProjects;
end;

procedure TAtlasSettingsPage.TrackerFillFields;
var
  mRows: TArray<TAtlasTrackerConnection>;
  mRow: TAtlasTrackerConnection;
  mIndex: Integer;
  mSelected, mEditable, mHasUrl: Boolean;
begin
  mRows := TrackerRows;
  mSelected := (FTrackerSelected >= 0) and (FTrackerSelected <= High(mRows));
  mEditable := TrackerEditable;
  FTrackerFilling := True;
  try
    if mSelected then
    begin
      mRow := mRows[FTrackerSelected];
      FIssuesConnectionName.Text := mRow.Name;
      FIssuesConnectionUrl.Text := mRow.Url;
      FIssuesConnectionProvider.Choice := -1;
      for mIndex := 0 to High(FTrackerProviderNames) do
        if SameText(FTrackerProviderNames[mIndex], mRow.Provider) then
          FIssuesConnectionProvider.Choice := mIndex;
    end
    else
    begin
      FIssuesConnectionName.Text := '';
      FIssuesConnectionUrl.Text := '';
      FIssuesConnectionProvider.Choice := -1;
    end;
  finally
    FTrackerFilling := False;
  end;
  mHasUrl := mSelected and (mRows[FTrackerSelected].Url <> '');
  if mSelected and not mEditable then
    FIssuesConnectionNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionReadOnly)
  else if mEditable and not mHasUrl then
    FIssuesConnectionNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionUrlEmpty)
  else
    FIssuesConnectionNote.Caption := '';
  Allow(FIssuesConnectionName, mEditable);
  Allow(FIssuesConnectionProvider, mEditable);
  Allow(FIssuesConnectionUrl, mEditable);
  Allow(FIssuesConnectionStateField, mEditable);
  Allow(FIssuesConnectionAssigneeField, mEditable);
  Allow(FIssuesConnectionStartState, mEditable);
  Allow(FIssuesConnectionEndStates, mEditable);
  Allow(FIssuesConnectionRemove, mEditable);
  // Token und Prüfung auch für die Verbindung aus der .atlas, nicht ohne gültige Adresse.
  Allow(FIssuesConnectionToken, mHasUrl and Assigned(FOnTrackerToken));
  Allow(FIssuesConnectionCheck, mHasUrl and Assigned(FOnTrackerCheck));
end;

procedure TAtlasSettingsPage.TrackerSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FTrackerFilling or not Selected or (Item = nil) then
    Exit;
  FTrackerSelected := Item.Index;
  TrackerFillFields;
end;

procedure TAtlasSettingsPage.TrackerNameChange(Sender: TObject);
var
  mName, mOld: string;
  mIndex: Integer;
begin
  if FTrackerFilling or not TrackerEditable then
    Exit;
  mName := Trim(FIssuesConnectionName.Text);
  if TAtlasTrackerConnections.NameTaken(FTrackerConnections, mName, FTrackerSelected) then
  begin
    FIssuesConnectionNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionNameTaken);
    Exit;
  end;
  FIssuesConnectionNote.Caption := '';
  // Zeilen der Tabelle Projekte verweisen per Name: umbenennen statt sie ins Leere zeigen zu lassen (#1261).
  mOld := FTrackerConnections[FTrackerSelected].Name;
  for mIndex := 0 to High(FTrackerProjects) do
    if (mOld <> '') and SameText(FTrackerProjects[mIndex].Connection, mOld) then
      FTrackerProjects[mIndex].Connection := mName;
  // Ebenso die Abfragen mit dieser Verbindung (#1262).
  TAtlasTrackerQueries.RenameConnection(FTrackerQueries, mOld, mName);
  FTrackerConnections[FTrackerSelected].Name := mName;
  if FIssuesConnections.HandleAllocated and (FTrackerSelected < FIssuesConnections.Items.Count) then
    FIssuesConnections.Items[FTrackerSelected].Caption := mName;
  RefreshTrackerProjects;
end;

procedure TAtlasSettingsPage.TrackerProviderChange(Sender: TObject);
var
  mChoice: Integer;
begin
  mChoice := FIssuesConnectionProvider.Choice;
  if FTrackerFilling or not TrackerEditable or (mChoice < 0) or (mChoice > High(FTrackerProviderNames)) then
    Exit;
  FTrackerConnections[FTrackerSelected].Provider := FTrackerProviderNames[mChoice];
  if FIssuesConnections.HandleAllocated and (FTrackerSelected < FIssuesConnections.Items.Count) then
    FIssuesConnections.Items[FTrackerSelected].SubItems[0] := FTrackerProviderCaptions[mChoice];
end;

procedure TAtlasSettingsPage.TrackerUrlChange(Sender: TObject);
var
  mConnection: TAtlasTrackerConnection;
begin
  if FTrackerFilling or not TrackerEditable then
    Exit;
  // Nur gültige Adressen übernehmen: http oder ein Benutzer in der Adresse werden abgewiesen, mit Grund.
  case TAtlasTrackerConnections.CheckUrl(FIssuesConnectionUrl.Text) of
    TAtlasTrackerUrlCheck.Empty:
      FIssuesConnectionNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionUrlEmpty);
    TAtlasTrackerUrlCheck.NotHttps:
      FIssuesConnectionNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionUrlHttps);
    TAtlasTrackerUrlCheck.WithUser:
      FIssuesConnectionNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionUrlUser);
    TAtlasTrackerUrlCheck.Invalid:
      FIssuesConnectionNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionUrlInvalid);
  else
    begin
      FIssuesConnectionNote.Caption := '';
      // WithUrl behält Zustandsfeld, Zielzustände usw. (#1266).
      mConnection := FTrackerConnections[FTrackerSelected].WithUrl(FIssuesConnectionUrl.Text);
      FTrackerConnections[FTrackerSelected] := mConnection;
      if FIssuesConnections.HandleAllocated and (FTrackerSelected < FIssuesConnections.Items.Count) then
      begin
        FIssuesConnections.Items[FTrackerSelected].SubItems[1] := mConnection.Url;
        FIssuesConnections.Items[FTrackerSelected].SubItems[2] := TrackerStateText(mConnection);
      end;
      Allow(FIssuesConnectionToken, Assigned(FOnTrackerToken));
      Allow(FIssuesConnectionCheck, Assigned(FOnTrackerCheck));
    end;
  end;
end;

procedure TAtlasSettingsPage.TrackerAddClick(Sender: TObject);
begin
  // Neue Zeile ohne Adresse: gespeichert wird sie erst mit gültiger Adresse.
  FTrackerConnections := FTrackerConnections + [TAtlasTrackerConnection.Create(
    TAtlasTrackerConnections.FreeName(TrackerRows, TAtlasStrings.Text(TAtlasTextId.SettingsIssuesConnectionNew)),
    FTrackerProviderNames[0], '')];
  FTrackerSelected := High(FTrackerConnections);
  RefreshTrackerConnections;
  if FIssuesConnectionName.CanFocus then
    FIssuesConnectionName.SetFocus;
end;

procedure TAtlasSettingsPage.TrackerRemoveClick(Sender: TObject);
var
  mConnection: TAtlasTrackerConnection;
begin
  if not TrackerEditable then
    Exit;
  mConnection := FTrackerConnections[FTrackerSelected];
  // Die Rückfrage zum Token (Anmeldespeicher) stellt die IDE; die Zeile geht in jedem Fall.
  if Assigned(FOnTrackerRemove) and (mConnection.Target.Server <> '') then
    FOnTrackerRemove(mConnection);
  Delete(FTrackerConnections, FTrackerSelected, 1);
  if FTrackerSelected > High(TrackerRows) then
    FTrackerSelected := High(TrackerRows);
  RefreshTrackerConnections;
end;

procedure TAtlasSettingsPage.TrackerTokenClick(Sender: TObject);
var
  mRows: TArray<TAtlasTrackerConnection>;
begin
  mRows := TrackerRows;
  if not Assigned(FOnTrackerToken) or (FTrackerSelected < 0) or (FTrackerSelected > High(mRows)) then
    Exit;
  FOnTrackerToken(mRows[FTrackerSelected]);
  RefreshTrackerConnections;
end;

procedure TAtlasSettingsPage.TrackerCheckClick(Sender: TObject);
var
  mRows: TArray<TAtlasTrackerConnection>;
  mServer: string;
begin
  mRows := TrackerRows;
  if not Assigned(FOnTrackerCheck) or (FTrackerSelected < 0) or (FTrackerSelected > High(mRows)) then
    Exit;
  mServer := mRows[FTrackerSelected].Target.CredentialTarget;
  if (mServer = '') or MatchText(mServer, FTrackerChecking) then
    Exit;
  FTrackerChecking := FTrackerChecking + [mServer];
  RefreshTrackerConnections;
  FOnTrackerCheck(mRows[FTrackerSelected]);
end;

procedure TAtlasSettingsPage.TrackerCheckDone(const AConnection: TAtlasTrackerConnection);
var
  mIndex: Integer;
  mStatus: TAtlasTrackerTokenStatus;
begin
  for mIndex := High(FTrackerChecking) downto 0 do
    if SameText(FTrackerChecking[mIndex], AConnection.Target.CredentialTarget) then
      Delete(FTrackerChecking, mIndex, 1);
  // Erkannte Sprache der Oberfläche (#1263) an den persönlichen Verbindungen zu diesem Server merken; gespeichert
  // mit OK.
  if Assigned(FOnTrackerState) then
  begin
    mStatus := FOnTrackerState(AConnection);
    if mStatus.Language <> '' then
      for mIndex := 0 to High(FTrackerConnections) do
        if SameText(FTrackerConnections[mIndex].Target.CredentialTarget, AConnection.Target.CredentialTarget) then
          FTrackerConnections[mIndex].Language := mStatus.Language;
  end;
  RefreshTrackerConnections;
end;

function TAtlasSettingsPage.TrackerConnectionsJson: string;
var
  mKept: TArray<TAtlasTrackerConnection>;
  mConnection: TAtlasTrackerConnection;
begin
  mKept := nil;
  for mConnection in FTrackerConnections do
    if (mConnection.Name <> '') and (mConnection.Provider <> '') and
      (TAtlasTrackerConnections.CheckUrl(mConnection.Url) = TAtlasTrackerUrlCheck.Valid) and
      (TAtlasTrackerConnections.IndexOfName(mKept, mConnection.Name) < 0) then
      mKept := mKept + [mConnection];
  Result := TAtlasTrackerConnections.ToJson(mKept);
end;

procedure TAtlasSettingsPage.AddTrackerProjectsSection;

  function AddMenuItem(AId: TAtlasTextId; AClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(Self);
    Result.Caption := TAtlasStrings.Text(AId);
    Result.OnClick := AClick;
    FIssuesProjectAddMenu.Items.Add(Result);
  end;

var
  mPanel: TWinControl;
begin
  FTrackerProjectSelected := -1;
  FTrackerContext := TAtlasTrackerProjectContext.Empty;
  AddTitle(TAtlasTextId.SettingsIssuesProjects);
  mPanel := AddPanel(110);
  // Wie die Verbindungen: die Zeilen erst mit Fenster (RefreshTrackerProjects, auch aus CreateWnd).
  FIssuesProjects := TListView.Create(Self);
  FIssuesProjects.Parent := mPanel;
  FIssuesProjects.Align := alClient;
  FIssuesProjects.ViewStyle := vsReport;
  FIssuesProjects.ReadOnly := True;
  FIssuesProjects.RowSelect := True;
  FIssuesProjects.HideSelection := False;
  FIssuesProjects.OnSelectItem := TrackerProjectSelectItem;
  FIssuesProjects.OnCustomDrawItem := TrackerProjectDrawItem;
  AddTrackerColumn(FIssuesProjects, TAtlasTextId.SettingsIssuesProjectMatch, 230);
  AddTrackerColumn(FIssuesProjects, TAtlasTextId.SettingsIssuesProjectConnection, 100);
  AddTrackerColumn(FIssuesProjects, TAtlasTextId.SettingsIssuesProjectProject, 100);
  AddTrackerColumn(FIssuesProjects, TAtlasTextId.SettingsIssuesProjectSource, 150);
  FIssuesProjectMatch := TEdit.Create(Self);
  FIssuesProjectMatch.OnChange := TrackerProjectMatchChange;
  mPanel := AddTrackerLabelled(TAtlasTextId.SettingsIssuesProjectMatch, FIssuesProjectMatch, 376);
  FIssuesProjectMatch.Anchors := [akLeft, akTop, akRight];
  Attach(mPanel, FIssuesProjects);
  FIssuesProjectConnection := TAtlasChoiceBox.Create(Self);
  FIssuesProjectConnection.OnChange := TrackerProjectConnectionChange;
  Attach(AddTrackerLabelled(TAtlasTextId.SettingsIssuesProjectConnection, FIssuesProjectConnection, 180),
    FIssuesProjects);
  FIssuesProjectProject := TEdit.Create(Self);
  FIssuesProjectProject.OnChange := TrackerProjectProjectChange;
  Attach(AddTrackerLabelled(TAtlasTextId.SettingsIssuesProjectProject, FIssuesProjectProject, 180),
    FIssuesProjects);
  // Grund, warum eine Zeile nicht greift (Verbindung fehlt, von .atlas überdeckt …).
  mPanel := AddPanel(18);
  FIssuesProjectNote := TLabel.Create(Self);
  FIssuesProjectNote.Parent := mPanel;
  FIssuesProjectNote.Left := 90;
  FIssuesProjectNote.Top := 1;
  FIssuesProjectNote.Font.Color := clRed;
  Attach(mPanel, FIssuesProjects);
  mPanel := AddPanel(32);
  FIssuesProjectAddCurrent := AddTrackerButton(mPanel, 0, 180, TAtlasTextId.SettingsIssuesProjectAddCurrent,
    TrackerProjectAddCurrentClick);
  FIssuesProjectAdd := AddTrackerButton(mPanel, 186, 110, TAtlasTextId.SettingsIssuesProjectAdd,
    TrackerProjectAddClick);
  FIssuesProjectRemove := AddTrackerButton(mPanel, 302, 100, TAtlasTextId.SettingsIssuesConnectionRemove,
    TrackerProjectRemoveClick);
  Attach(mPanel, FIssuesProjects);
  // „Hinzufügen …“: Projektdatei oder Ordner.
  FIssuesProjectAddMenu := TPopupMenu.Create(Self);
  AddMenuItem(TAtlasTextId.SettingsIssuesProjectAddFile, TrackerProjectAddFileClick);
  AddMenuItem(TAtlasTextId.SettingsIssuesProjectAddFolder, TrackerProjectAddFolderClick);
  AddTrackerHint(TAtlasTextId.SettingsIssuesProjectsHint, FIssuesProjects);
end;

function TAtlasSettingsPage.TrackerProjectRows: TArray<TAtlasTrackerProjectMapping>;
begin
  Result := FTrackerProjects + FTrackerContext.Team;
end;

function TAtlasSettingsPage.TrackerProjectEditable: Boolean;
begin
  Result := (FTrackerProjectSelected >= 0) and (FTrackerProjectSelected < Length(FTrackerProjects));
end;

function TAtlasSettingsPage.TrackerProjectCovered(const AMapping: TAtlasTrackerProjectMapping): Boolean;
begin
  Result := TAtlasTrackerProjects.Covered(AMapping, FTrackerContext.HasTeam, FTrackerContext.ProjectFile,
    FTrackerContext.GroupFile);
end;

function TAtlasSettingsPage.TrackerProjectSourceText(const AMapping: TAtlasTrackerProjectMapping): string;
begin
  if AMapping.ReadOnly then
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectTeam)
  else if TrackerProjectCovered(AMapping) then
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectCovered)
  else
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectPersonal);
end;

procedure TAtlasSettingsPage.RefreshTrackerProjects;
var
  mRows: TArray<TAtlasTrackerProjectMapping>;
  mRow: TAtlasTrackerProjectMapping;
  mItem: TListItem;
  mConnection: TAtlasTrackerConnection;
begin
  if FIssuesProjects = nil then
    Exit;
  FTrackerContext := TAtlasTrackerProjectContext.Empty;
  if Assigned(FOnTrackerContext) then
    FTrackerContext := FOnTrackerContext();
  // Auswahl der Verbindung: die persönlichen mit Namen (eine Zeile verweist per Name auf sie).
  FTrackerProjectChoices := nil;
  for mConnection in FTrackerConnections do
    if (mConnection.Name <> '') and not MatchText(mConnection.Name, FTrackerProjectChoices) then
      FTrackerProjectChoices := FTrackerProjectChoices + [mConnection.Name];
  FTrackerProjectFilling := True;
  try
    FIssuesProjectConnection.SetChoices(FTrackerProjectChoices);
  finally
    FTrackerProjectFilling := False;
  end;
  mRows := TrackerProjectRows;
  if FTrackerProjectSelected > High(mRows) then
    FTrackerProjectSelected := High(mRows);
  if FIssuesProjects.HandleAllocated then
  begin
    FTrackerProjectFilling := True;
    FIssuesProjects.Items.BeginUpdate;
    try
      FIssuesProjects.Items.Clear;
      for mRow in mRows do
      begin
        mItem := FIssuesProjects.Items.Add;
        mItem.Caption := mRow.Match;
        mItem.SubItems.Add(mRow.Connection);
        mItem.SubItems.Add(mRow.Project);
        mItem.SubItems.Add(TrackerProjectSourceText(mRow));
      end;
      if FTrackerProjectSelected >= 0 then
        FIssuesProjects.Items[FTrackerProjectSelected].Selected := True;
    finally
      FIssuesProjects.Items.EndUpdate;
      FTrackerProjectFilling := False;
    end;
  end;
  TrackerProjectFillFields;
  // Die Auswahl der Verbindung in der Tabelle Abfragen folgt ebenfalls den Verbindungen.
  RefreshTrackerQueries;
end;

procedure TAtlasSettingsPage.TrackerProjectNoteFor(const AMapping: TAtlasTrackerProjectMapping);
begin
  if AMapping.ReadOnly then
    FIssuesProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectReadOnly)
  else if Length(FTrackerProjectChoices) = 0 then
    FIssuesProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectNoConnection)
  else if not MatchText(AMapping.Connection, FTrackerProjectChoices) then
    FIssuesProjectNote.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsIssuesProjectConnectionMissing,
      [AMapping.Connection])
  else if TrackerProjectCovered(AMapping) then
    FIssuesProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectCoveredHint)
  else
    FIssuesProjectNote.Caption := '';
end;

procedure TAtlasSettingsPage.TrackerProjectFillFields;
var
  mRows: TArray<TAtlasTrackerProjectMapping>;
  mSelected, mEditable: Boolean;
  mIndex: Integer;
begin
  mRows := TrackerProjectRows;
  mSelected := (FTrackerProjectSelected >= 0) and (FTrackerProjectSelected <= High(mRows));
  mEditable := TrackerProjectEditable;
  FTrackerProjectFilling := True;
  try
    if mSelected then
    begin
      FIssuesProjectMatch.Text := mRows[FTrackerProjectSelected].Match;
      FIssuesProjectProject.Text := mRows[FTrackerProjectSelected].Project;
      FIssuesProjectConnection.Choice := -1;
      for mIndex := 0 to High(FTrackerProjectChoices) do
        if SameText(FTrackerProjectChoices[mIndex], mRows[FTrackerProjectSelected].Connection) then
          FIssuesProjectConnection.Choice := mIndex;
      TrackerProjectNoteFor(mRows[FTrackerProjectSelected]);
    end
    else
    begin
      FIssuesProjectMatch.Text := '';
      FIssuesProjectProject.Text := '';
      FIssuesProjectConnection.Choice := -1;
      FIssuesProjectNote.Caption := '';
      if Length(FTrackerProjectChoices) = 0 then
        FIssuesProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectNoConnection);
    end;
  finally
    FTrackerProjectFilling := False;
  end;
  Allow(FIssuesProjectMatch, mEditable);
  Allow(FIssuesProjectConnection, mEditable and (Length(FTrackerProjectChoices) > 0));
  Allow(FIssuesProjectProject, mEditable);
  Allow(FIssuesProjectRemove, mEditable);
  Allow(FIssuesProjectAddCurrent, FTrackerContext.ProjectFile <> '');
end;

procedure TAtlasSettingsPage.TrackerProjectSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FTrackerProjectFilling or not Selected or (Item = nil) then
    Exit;
  FTrackerProjectSelected := Item.Index;
  TrackerProjectFillFields;
end;

procedure TAtlasSettingsPage.TrackerProjectDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mRows: TArray<TAtlasTrackerProjectMapping>;
begin
  // Von der .atlas überdeckte persönliche Zeile grau (Mockup IT2).
  mRows := TrackerProjectRows;
  if (Item <> nil) and (Item.Index <= High(mRows)) and TrackerProjectCovered(mRows[Item.Index]) then
    Sender.Canvas.Font.Color := clGrayText;
  DefaultDraw := True;
end;

procedure TAtlasSettingsPage.TrackerProjectMatchChange(Sender: TObject);
var
  mMatch: string;
  mOther: Integer;
begin
  if FTrackerProjectFilling or not TrackerProjectEditable then
    Exit;
  mMatch := Trim(FIssuesProjectMatch.Text);
  // Ein Pfad hat höchstens eine persönliche Zeile.
  mOther := TAtlasTrackerProjects.IndexOfMatch(FTrackerProjects, mMatch);
  if (mMatch <> '') and (mOther >= 0) and (mOther <> FTrackerProjectSelected) then
  begin
    FIssuesProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatchTaken);
    Exit;
  end;
  FTrackerProjects[FTrackerProjectSelected].Match := mMatch;
  TrackerProjectNoteFor(FTrackerProjects[FTrackerProjectSelected]);
  if FIssuesProjects.HandleAllocated and (FTrackerProjectSelected < FIssuesProjects.Items.Count) then
  begin
    FIssuesProjects.Items[FTrackerProjectSelected].Caption := mMatch;
    FIssuesProjects.Items[FTrackerProjectSelected].SubItems[2] :=
      TrackerProjectSourceText(FTrackerProjects[FTrackerProjectSelected]);
  end;
end;

procedure TAtlasSettingsPage.TrackerProjectConnectionChange(Sender: TObject);
var
  mChoice: Integer;
begin
  mChoice := FIssuesProjectConnection.Choice;
  if FTrackerProjectFilling or not TrackerProjectEditable or (mChoice < 0) or
    (mChoice > High(FTrackerProjectChoices)) then
    Exit;
  FTrackerProjects[FTrackerProjectSelected].Connection := FTrackerProjectChoices[mChoice];
  TrackerProjectNoteFor(FTrackerProjects[FTrackerProjectSelected]);
  if FIssuesProjects.HandleAllocated and (FTrackerProjectSelected < FIssuesProjects.Items.Count) then
    FIssuesProjects.Items[FTrackerProjectSelected].SubItems[0] := FTrackerProjectChoices[mChoice];
end;

procedure TAtlasSettingsPage.TrackerProjectProjectChange(Sender: TObject);
begin
  if FTrackerProjectFilling or not TrackerProjectEditable then
    Exit;
  FTrackerProjects[FTrackerProjectSelected].Project := Trim(FIssuesProjectProject.Text);
  if FIssuesProjects.HandleAllocated and (FTrackerProjectSelected < FIssuesProjects.Items.Count) then
    FIssuesProjects.Items[FTrackerProjectSelected].SubItems[1] := FTrackerProjects[FTrackerProjectSelected].Project;
end;

procedure TAtlasSettingsPage.TrackerProjectAdd(const AMatch: string);
var
  mIndex: Integer;
  mConnection: string;
begin
  if Trim(AMatch) = '' then
    Exit;
  mIndex := TAtlasTrackerProjects.IndexOfMatch(FTrackerProjects, AMatch);
  if mIndex < 0 then
  begin
    // Vorbelegt mit der ersten Verbindung; das Tracker-Projekt trägt man selbst ein.
    mConnection := '';
    if Length(FTrackerProjectChoices) > 0 then
      mConnection := FTrackerProjectChoices[0];
    FTrackerProjects := FTrackerProjects + [TAtlasTrackerProjectMapping.Create(AMatch, mConnection, '')];
    mIndex := High(FTrackerProjects);
  end;
  FTrackerProjectSelected := mIndex;
  RefreshTrackerProjects;
  if FIssuesProjectProject.CanFocus then
    FIssuesProjectProject.SetFocus;
end;

procedure TAtlasSettingsPage.AssignTrackerProject(const AMatch: string);
begin
  TrackerProjectAdd(AMatch);
  SelectPage(PageOf(FIssuesProjects));
end;

procedure TAtlasSettingsPage.TrackerProjectAddCurrentClick(Sender: TObject);
begin
  RefreshTrackerProjects;
  if FTrackerContext.ProjectFile = '' then
  begin
    FIssuesProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectNoProject);
    Exit;
  end;
  // Die geöffnete .groupproj, sonst die aktive .dproj.
  TrackerProjectAdd(TAtlasTrackerProjects.CurrentMatch(FTrackerContext.ProjectFile, FTrackerContext.GroupFile));
end;

procedure TAtlasSettingsPage.TrackerProjectAddClick(Sender: TObject);
begin
  // Unter dem Knopf aufklappen.
  FIssuesProjectAddMenu.Popup(FIssuesProjectAdd.ClientOrigin.X,
    FIssuesProjectAdd.ClientOrigin.Y + FIssuesProjectAdd.Height);
end;

function TAtlasSettingsPage.TrackerBrowse(AFolder: Boolean; out APath: string): Boolean;
var
  mFolder: TFileOpenDialog;
  mFile: TOpenDialog;
begin
  APath := '';
  if Assigned(FOnTrackerBrowse) then
    Exit(FOnTrackerBrowse(AFolder, APath));
  if AFolder then
  begin
    mFolder := TFileOpenDialog.Create(nil);
    try
      mFolder.Options := mFolder.Options + [fdoPickFolders, fdoPathMustExist];
      Result := mFolder.Execute;
      if Result then
        APath := mFolder.FileName;
    finally
      mFolder.Free;
    end;
    Exit;
  end;
  mFile := TOpenDialog.Create(nil);
  try
    mFile.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectFileFilter);
    mFile.Options := mFile.Options + [ofFileMustExist];
    Result := mFile.Execute;
    if Result then
      APath := mFile.FileName;
  finally
    mFile.Free;
  end;
end;

procedure TAtlasSettingsPage.TrackerProjectAddFileClick(Sender: TObject);
var
  mPath: string;
begin
  if TrackerBrowse(False, mPath) then
    TrackerProjectAdd(mPath);
end;

procedure TAtlasSettingsPage.TrackerProjectAddFolderClick(Sender: TObject);
var
  mPath: string;
begin
  if TrackerBrowse(True, mPath) then
    TrackerProjectAdd(mPath);
end;

procedure TAtlasSettingsPage.TrackerProjectRemoveClick(Sender: TObject);
begin
  if not TrackerProjectEditable then
    Exit;
  Delete(FTrackerProjects, FTrackerProjectSelected, 1);
  if FTrackerProjectSelected > High(TrackerProjectRows) then
    FTrackerProjectSelected := High(TrackerProjectRows);
  RefreshTrackerProjects;
end;

function TAtlasSettingsPage.TrackerProjectsJson: string;
var
  mKept: TArray<TAtlasTrackerProjectMapping>;
  mMapping: TAtlasTrackerProjectMapping;
begin
  mKept := nil;
  for mMapping in FTrackerProjects do
    if (mMapping.Match <> '') and (mMapping.Connection <> '') and
      (TAtlasTrackerProjects.IndexOfMatch(mKept, mMapping.Match) < 0) then
      mKept := mKept + [mMapping];
  Result := TAtlasTrackerProjects.ToJson(mKept);
end;

procedure TAtlasSettingsPage.AddTrackerQueriesSection;
var
  mPanel: TWinControl;
begin
  FTrackerQuerySelected := -1;
  FTrackerQueries := nil;
  AddTitle(TAtlasTextId.SettingsIssuesQueries);
  mPanel := AddPanel(96);
  // Wie die Verbindungen: die Zeilen erst mit Fenster (RefreshTrackerQueries, auch aus CreateWnd).
  FIssuesQueries := TListView.Create(Self);
  FIssuesQueries.Parent := mPanel;
  FIssuesQueries.Align := alClient;
  FIssuesQueries.ViewStyle := vsReport;
  FIssuesQueries.ReadOnly := True;
  FIssuesQueries.RowSelect := True;
  FIssuesQueries.HideSelection := False;
  FIssuesQueries.OnSelectItem := TrackerQuerySelectItem;
  AddTrackerColumn(FIssuesQueries, TAtlasTextId.SettingsIssuesQueryName, 130);
  AddTrackerColumn(FIssuesQueries, TAtlasTextId.SettingsIssuesQuery, 230);
  AddTrackerColumn(FIssuesQueries, TAtlasTextId.SettingsIssuesProjectConnection, 100);
  AddTrackerColumn(FIssuesQueries, TAtlasTextId.SettingsIssuesProjectProject, 100);
  FIssuesQueryName := TEdit.Create(Self);
  FIssuesQueryName.OnChange := TrackerQueryNameChange;
  Attach(AddTrackerLabelled(TAtlasTextId.SettingsIssuesQueryName, FIssuesQueryName, 180), FIssuesQueries);
  FIssuesQueryText := TEdit.Create(Self);
  FIssuesQueryText.OnChange := TrackerQueryTextChange;
  mPanel := AddTrackerLabelled(TAtlasTextId.SettingsIssuesQuery, FIssuesQueryText, 376);
  FIssuesQueryText.Anchors := [akLeft, akTop, akRight];
  Attach(mPanel, FIssuesQueries);
  FIssuesQueryConnection := TAtlasChoiceBox.Create(Self);
  FIssuesQueryConnection.OnChange := TrackerQueryConnectionChange;
  Attach(AddTrackerLabelled(TAtlasTextId.SettingsIssuesProjectConnection, FIssuesQueryConnection, 180),
    FIssuesQueries);
  FIssuesQueryProject := TEdit.Create(Self);
  FIssuesQueryProject.OnChange := TrackerQueryProjectChange;
  Attach(AddTrackerLabelled(TAtlasTextId.SettingsIssuesProjectProject, FIssuesQueryProject, 180), FIssuesQueries);
  // Grund, warum eine Zeile nicht gespeichert wird (Name doppelt, Abfrage fehlt), bzw. die Vorgabe ohne Zeilen.
  mPanel := AddPanel(18);
  FIssuesQueryNote := TLabel.Create(Self);
  FIssuesQueryNote.Parent := mPanel;
  FIssuesQueryNote.Left := 90;
  FIssuesQueryNote.Top := 1;
  Attach(mPanel, FIssuesQueries);
  mPanel := AddPanel(32);
  FIssuesQueryAdd := AddTrackerButton(mPanel, 0, 110, TAtlasTextId.SettingsIssuesProjectAdd, TrackerQueryAddClick);
  FIssuesQueryRemove := AddTrackerButton(mPanel, 116, 100, TAtlasTextId.SettingsIssuesConnectionRemove,
    TrackerQueryRemoveClick);
  // Dialog mit Vorlagen und „Testen“ (#1263); auch Doppelklick auf eine Zeile.
  FIssuesQueryEdit := AddTrackerButton(mPanel, 222, 110, TAtlasTextId.SettingsIssuesQueryEdit,
    TrackerQueryEditClick);
  FIssuesQueries.OnDblClick := TrackerQueryEditClick;
  Attach(mPanel, FIssuesQueries);
  AddTrackerHint(TAtlasTextId.SettingsIssuesQueriesHint, FIssuesQueries);
  FIssuesQueryPicker := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesQueryPicker));
  // „Issue anlegen …“ im Editor und bei Befunden (#1268).
  FIssuesCreate := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesCreate));
  FIssuesCreateIncludeCode := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesCreateIncludeCode));
end;

function TAtlasSettingsPage.TrackerQueryEditable: Boolean;
begin
  Result := (FTrackerQuerySelected >= 0) and (FTrackerQuerySelected <= High(FTrackerQueries));
end;

function TAtlasSettingsPage.TrackerQueryConnectionChoice(const AConnection: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  if AConnection = '' then
    Exit;
  Result := -1;
  for mIndex := 0 to High(FTrackerProjectChoices) do
    if SameText(FTrackerProjectChoices[mIndex], AConnection) then
      Exit(mIndex + 1);
end;

procedure TAtlasSettingsPage.RefreshTrackerQueries;
var
  mQuery: TAtlasTrackerQuery;
  mItem: TListItem;
begin
  if FIssuesQueries = nil then
    Exit;
  // Auswahl: „(alle)“, dann die Verbindungen mit Namen (wie bei den Projekten).
  FTrackerQueryFilling := True;
  try
    FIssuesQueryConnection.SetChoices(TArray<string>.Create(TAtlasStrings.Text(
      TAtlasTextId.SettingsIssuesQueryAny)) + FTrackerProjectChoices);
  finally
    FTrackerQueryFilling := False;
  end;
  if FTrackerQuerySelected > High(FTrackerQueries) then
    FTrackerQuerySelected := High(FTrackerQueries);
  if FIssuesQueries.HandleAllocated then
  begin
    FTrackerQueryFilling := True;
    FIssuesQueries.Items.BeginUpdate;
    try
      FIssuesQueries.Items.Clear;
      for mQuery in FTrackerQueries do
      begin
        mItem := FIssuesQueries.Items.Add;
        mItem.Caption := mQuery.Name;
        mItem.SubItems.Add(mQuery.Query);
        mItem.SubItems.Add(mQuery.Connection);
        mItem.SubItems.Add(mQuery.Project);
      end;
      if FTrackerQuerySelected >= 0 then
        FIssuesQueries.Items[FTrackerQuerySelected].Selected := True;
    finally
      FIssuesQueries.Items.EndUpdate;
      FTrackerQueryFilling := False;
    end;
  end;
  TrackerQueryFillFields;
end;

procedure TAtlasSettingsPage.TrackerQueryNoteFor(const AQuery: TAtlasTrackerQuery);
begin
  if AQuery.Query = '' then
    FIssuesQueryNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesQueryEmpty)
  else if (AQuery.Connection <> '') and (TrackerQueryConnectionChoice(AQuery.Connection) < 0) then
    FIssuesQueryNote.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsIssuesProjectConnectionMissing,
      [AQuery.Connection])
  else
    FIssuesQueryNote.Caption := '';
end;

procedure TAtlasSettingsPage.TrackerQueryFillFields;
var
  mEditable: Boolean;
begin
  mEditable := TrackerQueryEditable;
  FTrackerQueryFilling := True;
  try
    if mEditable then
    begin
      FIssuesQueryName.Text := FTrackerQueries[FTrackerQuerySelected].Name;
      FIssuesQueryText.Text := FTrackerQueries[FTrackerQuerySelected].Query;
      FIssuesQueryProject.Text := FTrackerQueries[FTrackerQuerySelected].Project;
      FIssuesQueryConnection.Choice :=
        TrackerQueryConnectionChoice(FTrackerQueries[FTrackerQuerySelected].Connection);
      TrackerQueryNoteFor(FTrackerQueries[FTrackerQuerySelected]);
      FIssuesConnectionStateField.Value := mRow.StateField;
      FIssuesConnectionAssigneeField.Value := mRow.AssigneeField;
      FIssuesConnectionStartState.Value := mRow.StartState;
      FIssuesConnectionEndStates.Text := TAtlasTrackerWorkflow.ListText(mRow.EndStates);
    end
    else
    begin
      FIssuesQueryName.Text := '';
      FIssuesQueryText.Text := '';
      FIssuesQueryProject.Text := '';
      FIssuesQueryConnection.Choice := 0;
      FIssuesQueryNote.Caption := '';
      // Ohne eigene Zeilen gilt die Vorgabe je Anbieter.
      if Length(FTrackerQueries) = 0 then
        FIssuesQueryNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesQueriesNone);
      FIssuesConnectionStateField.Value := '';
      FIssuesConnectionAssigneeField.Value := '';
      FIssuesConnectionStartState.Value := '';
      FIssuesConnectionEndStates.Text := '';
    end;
  finally
    FTrackerQueryFilling := False;
  end;
  Allow(FIssuesQueryName, mEditable);
  Allow(FIssuesQueryText, mEditable);
  Allow(FIssuesQueryConnection, mEditable);
  Allow(FIssuesQueryProject, mEditable);
  Allow(FIssuesQueryRemove, mEditable);
  Allow(FIssuesQueryEdit, mEditable);
end;

procedure TAtlasSettingsPage.TrackerQuerySelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if FTrackerQueryFilling or not Selected or (Item = nil) then
    Exit;
  FTrackerQuerySelected := Item.Index;
  TrackerQueryFillFields;
end;

procedure TAtlasSettingsPage.TrackerQueryRowChanged;
var
  mQuery: TAtlasTrackerQuery;
  mItem: TListItem;
begin
  mQuery := FTrackerQueries[FTrackerQuerySelected];
  TrackerQueryNoteFor(mQuery);
  if not FIssuesQueries.HandleAllocated or (FTrackerQuerySelected >= FIssuesQueries.Items.Count) then
    Exit;
  mItem := FIssuesQueries.Items[FTrackerQuerySelected];
  mItem.Caption := mQuery.Name;
  mItem.SubItems[0] := mQuery.Query;
  mItem.SubItems[1] := mQuery.Connection;
  mItem.SubItems[2] := mQuery.Project;
end;

procedure TAtlasSettingsPage.TrackerQueryNameChange(Sender: TObject);
var
  mName: string;
  mOther: Integer;
begin
  if FTrackerQueryFilling or not TrackerQueryEditable then
    Exit;
  mName := Trim(FIssuesQueryName.Text);
  // Die Klappliste unterscheidet die Abfragen am Namen.
  mOther := TAtlasTrackerQueries.IndexOfName(FTrackerQueries, mName);
  if (mName = '') or ((mOther >= 0) and (mOther <> FTrackerQuerySelected)) then
  begin
    FIssuesQueryNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesQueryNameTaken);
    Exit;
  end;
  FTrackerQueries[FTrackerQuerySelected].Name := mName;
  TrackerQueryRowChanged;
end;

procedure TAtlasSettingsPage.TrackerQueryTextChange(Sender: TObject);
var
  mQuery: TAtlasTrackerQuery;
begin
  if FTrackerQueryFilling or not TrackerQueryEditable then
    Exit;
  // Einzeilig wie beim Lesen (TAtlasTrackerQuery.Create).
  mQuery := FTrackerQueries[FTrackerQuerySelected];
  FTrackerQueries[FTrackerQuerySelected] := TAtlasTrackerQuery.Create(mQuery.Name, FIssuesQueryText.Text,
    mQuery.Connection, mQuery.Project);
  TrackerQueryRowChanged;
end;

procedure TAtlasSettingsPage.TrackerQueryConnectionChange(Sender: TObject);
var
  mChoice: Integer;
begin
  mChoice := FIssuesQueryConnection.Choice;
  if FTrackerQueryFilling or not TrackerQueryEditable or (mChoice < 0) or
    (mChoice > Length(FTrackerProjectChoices)) then
    Exit;
  if mChoice = 0 then
    FTrackerQueries[FTrackerQuerySelected].Connection := ''
  else
    FTrackerQueries[FTrackerQuerySelected].Connection := FTrackerProjectChoices[mChoice - 1];
  TrackerQueryRowChanged;
end;

procedure TAtlasSettingsPage.TrackerQueryProjectChange(Sender: TObject);
begin
  if FTrackerQueryFilling or not TrackerQueryEditable then
    Exit;
  FTrackerQueries[FTrackerQuerySelected].Project := Trim(FIssuesQueryProject.Text);
  TrackerQueryRowChanged;
end;

procedure TAtlasSettingsPage.TrackerQueryAddClick(Sender: TObject);
var
  mBase, mName: string;
  mNumber: Integer;
begin
  // Neue Zeile ohne Abfrage: gespeichert wird sie erst mit Abfrage.
  mBase := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesQueryNew);
  mName := mBase;
  mNumber := 1;
  while TAtlasTrackerQueries.IndexOfName(FTrackerQueries, mName) >= 0 do
  begin
    Inc(mNumber);
    mName := mBase + ' ' + IntToStr(mNumber);
  end;
  FTrackerQueries := FTrackerQueries + [TAtlasTrackerQuery.Create(mName, '', '', '')];
  FTrackerQuerySelected := High(FTrackerQueries);
  RefreshTrackerQueries;
  if FIssuesQueryText.CanFocus then
    FIssuesQueryText.SetFocus;
end;

procedure TAtlasSettingsPage.TrackerQueryRemoveClick(Sender: TObject);
begin
  if not TrackerQueryEditable then
    Exit;
  Delete(FTrackerQueries, FTrackerQuerySelected, 1);
  if FTrackerQuerySelected > High(FTrackerQueries) then
    FTrackerQuerySelected := High(FTrackerQueries);
  RefreshTrackerQueries;
end;

procedure TAtlasSettingsPage.TrackerQueryEditClick(Sender: TObject);
var
  mQuery: TAtlasTrackerQuery;
  mTaken: TArray<string>;
  mIndex: Integer;
  mOk: Boolean;
begin
  if not TrackerQueryEditable then
    Exit;
  mQuery := FTrackerQueries[FTrackerQuerySelected];
  mTaken := nil;
  for mIndex := 0 to High(FTrackerQueries) do
    if mIndex <> FTrackerQuerySelected then
      mTaken := mTaken + [FTrackerQueries[mIndex].Name];
  if Assigned(FOnTrackerQueryEdit) then
    mOk := FOnTrackerQueryEdit(mQuery, TrackerRows, mTaken)
  else
    mOk := TAtlasTrackerQueryDialog.Execute(mQuery, TrackerRows, mTaken, FOnTrackerQueryTest);
  if not mOk then
    Exit;
  FTrackerQueries[FTrackerQuerySelected] := mQuery;
  RefreshTrackerQueries;
end;

procedure TAtlasSettingsPage.TrackerWorkflowChange(Sender: TObject);
begin
  if FTrackerFilling or not TrackerEditable then
    Exit;
  FTrackerConnections[FTrackerSelected].StateField := FIssuesConnectionStateField.Value;
  FTrackerConnections[FTrackerSelected].AssigneeField := FIssuesConnectionAssigneeField.Value;
  FTrackerConnections[FTrackerSelected].StartState := FIssuesConnectionStartState.Value;
  FTrackerConnections[FTrackerSelected].EndStates := TAtlasTrackerWorkflow.ParseList(FIssuesConnectionEndStates.Text);
end;

function TAtlasSettingsPage.TrackerValuesConnection(out AConnection: TAtlasTrackerConnection): Boolean;
var
  mRows: TArray<TAtlasTrackerConnection>;
  mRow: TAtlasTrackerConnection;
begin
  mRows := TrackerRows;
  if (FTrackerSelected >= 0) and (FTrackerSelected <= High(mRows)) and
    (mRows[FTrackerSelected].Target.Server <> '') then
  begin
    AConnection := mRows[FTrackerSelected];
    Exit(True);
  end;
  for mRow in mRows do
    if mRow.Target.Server <> '' then
    begin
      AConnection := mRow;
      Exit(True);
    end;
  AConnection := TAtlasTrackerConnection.Create('', '', '');
  Result := False;
end;

procedure TAtlasSettingsPage.TrackerLoadValuesClick(Sender: TObject);
var
  mConnection: TAtlasTrackerConnection;
  mField: string;
begin
  if not Assigned(FOnTrackerValues) then
    Exit;
  if not TrackerValuesConnection(mConnection) then
  begin
    FIssuesValuesNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesValuesNoConnection);
    Exit;
  end;
  // Zustände zum Feld der Verbindung, sonst zum globalen Feld.
  mField := mConnection.StateField;
  if mField = '' then
    mField := FIssuesStateField.Value;
  FIssuesValuesNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesValuesLoading);
  FIssuesLoadValues.Enabled := False;
  FOnTrackerValues(mConnection, mField);
end;

procedure TAtlasSettingsPage.TrackerValuesDone(const AValues: TAtlasTrackerValueSet; const AError: string);
begin
  FIssuesLoadValues.Enabled := True;
  if AError <> '' then
  begin
    FIssuesValuesNote.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsIssuesValuesFailed, [AError]);
    Exit;
  end;
  // Vorschläge für die globalen Felder und die der Verbindung; eingegebene Texte bleiben.
  FIssuesStateField.SetValues(AValues.StateFields);
  FIssuesAssigneeField.SetValues(AValues.UserFields);
  FIssuesStartState.SetValues(AValues.States);
  FIssuesConnectionStateField.SetValues(AValues.StateFields);
  FIssuesConnectionAssigneeField.SetValues(AValues.UserFields);
  FIssuesConnectionStartState.SetValues(AValues.States);
  FIssuesValuesNote.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsIssuesValuesLoaded,
    [Length(AValues.States), Length(AValues.StateFields) + Length(AValues.UserFields)]);
end;

function TAtlasSettingsPage.TrackerQueriesJson: string;
var
  mKept: TArray<TAtlasTrackerQuery>;
  mQuery: TAtlasTrackerQuery;
begin
  mKept := nil;
  for mQuery in FTrackerQueries do
    if (mQuery.Name <> '') and (mQuery.Query <> '') and (TAtlasTrackerQueries.IndexOfName(mKept, mQuery.Name) < 0) then
      mKept := mKept + [mQuery];
  Result := TAtlasTrackerQueries.ToJson(mKept);
end;

procedure TAtlasSettingsPage.AddWelcomeLayoutButtons;

  function AddButton(ALeft: Integer; AId: TAtlasTextId; AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := FWelcomeActiveLayout.Parent;
    Result.Caption := TAtlasStrings.Text(AId);
    Result.Left := ALeft;
    Result.Top := 0;
    Result.Width := 96;
    Result.OnClick := AClick;
  end;

var
  mLeft: Integer;
begin
  mLeft := FWelcomeActiveLayout.Left + FWelcomeActiveLayout.Width + 6;
  FWelcomeLayoutNew := AddButton(mLeft, TAtlasTextId.SettingsWelcomeLayoutNew, WelcomeLayoutNewClick);
  FWelcomeLayoutRename := AddButton(mLeft + 102, TAtlasTextId.SettingsWelcomeLayoutRename,
    WelcomeLayoutRenameClick);
  FWelcomeLayoutDelete := AddButton(mLeft + 204, TAtlasTextId.SettingsWelcomeLayoutDelete,
    WelcomeLayoutDeleteClick);
end;

function TAtlasSettingsPage.WelcomeSectionShown(const AId: string; out AShown: Boolean): Boolean;
var
  Check: TCheckBox;
begin
  Result := True;
  AShown := False;
  if AId = TAtlasWelcomeIds.News then
  begin
    AShown := FWelcomeWhatsNew.Choice > 0;
    Exit;
  end;
  Check := nil;
  if AId = TAtlasWelcomeIds.Continue then
    Check := FWelcomeContinue
  else if AId = TAtlasWelcomeIds.Projects then
    Check := FWelcomeProjects
  else if AId = TAtlasWelcomeIds.History then
    Check := FWelcomeTrends
  else if AId = TAtlasWelcomeIds.Tests then
    Check := FWelcomeTests
  else if AId = TAtlasWelcomeIds.State then
    Check := FWelcomeStatusTile
  else if AId = TAtlasWelcomeIds.Unsaved then
    Check := FWelcomeUnsaved
  else if AId = TAtlasWelcomeIds.Discover then
    Check := FWelcomeDiscover
  else if AId = TAtlasWelcomeIds.Setup then
    Check := FWelcomeProjectSetup
  else if AId = TAtlasWelcomeIds.Issues then
    Check := FWelcomeIssues
  else if AId = TAtlasWelcomeIds.Help then
    Check := FWelcomeHelp;
  Result := Check <> nil;
  if Result then
    AShown := Check.Checked;
end;

procedure TAtlasSettingsPage.ShowWelcomeSection(const AId: string; AShown: Boolean);
var
  Shown: Boolean;
begin
  if not WelcomeSectionShown(AId, Shown) or (Shown = AShown) then
    Exit;
  if AId = TAtlasWelcomeIds.News then
  begin
    // Einschalten heißt „nach einem Update“, wie die Vorgabe.
    FWelcomeWhatsNew.Choice := Ord(TAtlasWhatsNewMode.AfterUpdate);
    if not AShown then
      FWelcomeWhatsNew.Choice := Ord(TAtlasWhatsNewMode.Off);
  end
  else if AId = TAtlasWelcomeIds.Continue then
    FWelcomeContinue.Checked := AShown
  else if AId = TAtlasWelcomeIds.Projects then
    FWelcomeProjects.Checked := AShown
  else if AId = TAtlasWelcomeIds.History then
    FWelcomeTrends.Checked := AShown
  else if AId = TAtlasWelcomeIds.Tests then
    FWelcomeTests.Checked := AShown
  else if AId = TAtlasWelcomeIds.State then
    FWelcomeStatusTile.Checked := AShown
  else if AId = TAtlasWelcomeIds.Unsaved then
    FWelcomeUnsaved.Checked := AShown
  else if AId = TAtlasWelcomeIds.Discover then
    FWelcomeDiscover.Checked := AShown
  else if AId = TAtlasWelcomeIds.Setup then
    FWelcomeProjectSetup.Checked := AShown
  else if AId = TAtlasWelcomeIds.Issues then
    FWelcomeIssues.Checked := AShown
  else if AId = TAtlasWelcomeIds.Help then
    FWelcomeHelp.Checked := AShown;
end;

procedure TAtlasSettingsPage.KeepWelcomeLayout;
var
  Layout: TAtlasWelcomeLayout;
  Item: TAtlasWelcomeCatalogItem;
  Shown: Boolean;
begin
  Layout := FPageLayouts.Current;
  Layout := Layout.WithColumns(EnsureRange(StrToIntDef(Trim(FWelcomeColumns.Text), Layout.Columns),
    TAtlasWelcomeLayout.MinColumns, TAtlasWelcomeLayout.MaxColumns));
  for Item in TAtlasWelcomeCustomizing.Catalog do
    if WelcomeSectionShown(Item.Id, Shown) and (Layout.IndexOf(Item.Id) >= 0) then
      Layout := Layout.WithVisible(Item.Id, Shown);
  FPageLayouts := FPageLayouts.WithCurrent(Layout);
end;

procedure TAtlasSettingsPage.ShowWelcomeLayouts(AVisibility: Boolean);
var
  Layout: TAtlasWelcomeLayout;
  Slot: TAtlasWelcomeSlot;
begin
  Layout := FPageLayouts.Current;
  FWelcomeActiveLayout.SetChoices(FPageLayouts.Names);
  FWelcomeActiveLayout.Choice := FPageLayouts.Active;
  FWelcomeColumns.Text := IntToStr(Layout.Columns);
  Allow(FWelcomeLayoutDelete, Length(FPageLayouts.Items) > 1);
  if AVisibility then
    for Slot in Layout.Slots do
      ShowWelcomeSection(Slot.Id, Slot.Visible);
end;

procedure TAtlasSettingsPage.SelectWelcomeLayout(AIndex: Integer);
var
  Layouts: TAtlasWelcomeLayouts;
begin
  if (AIndex < 0) or (AIndex > High(FPageLayouts.Items)) or (AIndex = FPageLayouts.Active) then
    Exit;
  // Das bisherige Layout merkt sich Spalten und Sichtbarkeit, das neue setzt seine.
  KeepWelcomeLayout;
  if FPageLayouts.Activated(FPageLayouts.Items[AIndex].Name, Layouts) then
    FPageLayouts := Layouts;
  ShowWelcomeLayouts(True);
end;

procedure TAtlasSettingsPage.WelcomeLayoutChange(Sender: TObject);
begin
  SelectWelcomeLayout(FWelcomeActiveLayout.Choice);
end;

procedure TAtlasSettingsPage.WelcomeLayoutNewClick(Sender: TObject);
var
  mName: string;
  Layouts: TAtlasWelcomeLayouts;
begin
  mName := '';
  if not AskLayoutName(mName) or (Trim(mName) = '') then
    Exit;
  KeepWelcomeLayout;
  if not FPageLayouts.Added(Trim(mName), Layouts) then
  begin
    ConfirmLayout(TAtlasStrings.Fmt(TAtlasTextId.WelcomeArrangeLayoutTaken, [Trim(mName)]), False);
    Exit;
  end;
  // Die Kopie übernimmt die Sichtbarkeit; die Häkchen bleiben.
  FPageLayouts := Layouts;
  ShowWelcomeLayouts(False);
end;

procedure TAtlasSettingsPage.WelcomeLayoutRenameClick(Sender: TObject);
var
  mName: string;
  Layouts: TAtlasWelcomeLayouts;
begin
  mName := FPageLayouts.ActiveName;
  if not AskLayoutName(mName) or (Trim(mName) = '') or (Trim(mName) = FPageLayouts.ActiveName) then
    Exit;
  if not FPageLayouts.Renamed(Trim(mName), Layouts) then
  begin
    ConfirmLayout(TAtlasStrings.Fmt(TAtlasTextId.WelcomeArrangeLayoutTaken, [Trim(mName)]), False);
    Exit;
  end;
  FPageLayouts := Layouts;
  ShowWelcomeLayouts(False);
end;

procedure TAtlasSettingsPage.WelcomeLayoutDeleteClick(Sender: TObject);
var
  Layouts: TAtlasWelcomeLayouts;
begin
  if (Length(FPageLayouts.Items) < 2) or
    not ConfirmLayout(TAtlasStrings.Fmt(TAtlasTextId.WelcomeArrangeDeleteConfirm, [FPageLayouts.ActiveName]),
    True) then
    Exit;
  if not FPageLayouts.Deleted(Layouts) then
    Exit;
  FPageLayouts := Layouts;
  ShowWelcomeLayouts(True);
end;

function TAtlasSettingsPage.AskLayoutName(var AName: string): Boolean;
begin
  if Assigned(FOnAskLayoutName) then
    Exit(FOnAskLayoutName(TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeLayoutName), AName));
  Result := InputQuery(TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeCustomize),
    TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeLayoutName), AName);
end;

function TAtlasSettingsPage.ConfirmLayout(const AText: string; AQuestion: Boolean): Boolean;
begin
  if Assigned(FOnConfirmLayout) then
    Exit(FOnConfirmLayout(AText, AQuestion));
  if AQuestion then
    Result := MessageDlg(AText, mtConfirmation, [mbYes, mbNo], 0) = mrYes
  else
  begin
    MessageDlg(AText, mtInformation, [mbOK], 0);
    Result := True;
  end;
end;

function TAtlasSettingsPage.ReassignedTargetCheck(ATarget: TAtlasReassignedTarget): TCheckBox;
begin
  Result := FReassignedTargets[ATarget];
end;

function TAtlasSettingsPage.AddTextLine(const ACaption: string): TEdit;
var
  Panel: TWinControl;
  Heading: TLabel;
begin
  Panel := AddPanel(20);
  Heading := TLabel.Create(Self);
  Heading.Parent := Panel;
  Heading.Caption := ACaption;
  Heading.Left := 0;
  Heading.Top := 3;
  // Eigene Zeile für das Feld: Adressen und Pfade brauchen die Breite.
  Panel := AddPanel(26);
  Result := TEdit.Create(Self);
  Result.Parent := Panel;
  Result.Left := 0;
  Result.Top := 1;
  Result.Width := 466;
  Result.Anchors := [akLeft, akTop, akRight];
end;

procedure TAtlasSettingsPage.HelpFolderBrowseClick(Sender: TObject);
var
  Dialog: TFileOpenDialog;
begin
  Dialog := TFileOpenDialog.Create(Self);
  try
    Dialog.Options := Dialog.Options + [fdoPickFolders, fdoPathMustExist];
    if FWelcomeHelpReportFolder.Text <> '' then
      Dialog.DefaultFolder := FWelcomeHelpReportFolder.Text;
    if Dialog.Execute then
      FWelcomeHelpReportFolder.Text := Dialog.FileName;
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasSettingsPage.AddOpenBuildSection;
begin
  AddTitle(TAtlasTextId.SettingsOpenBuildTitle);
  // Reihenfolge: nicht bauen, dann wie TAtlasOpenBuild.KindNames (check, make, build).
  FOpenBuild := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuild),
    [TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildNone), TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildCheck),
    TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildMake), TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildBuild)]);
  // Reihenfolge wie TAtlasOpenBuildScope: alle, nur das aktive.
  FOpenBuildScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildScope),
    [TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildScopeAll),
    TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildScopeActive)]);
  FOpenBuildDelay := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildDelay));
  FOpenBuildExclude := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildExclude));
end;

procedure TAtlasSettingsPage.LoadOpenBuild(const ASettings: TAtlasPluginSettings);
var
  Index: Integer;
begin
  FOpenBuild.Choice := 0;
  if ASettings.BuildOnOpen then
    for Index := Low(TAtlasOpenBuild.KindNames) to High(TAtlasOpenBuild.KindNames) do
      if SameText(TAtlasOpenBuild.KindNames[Index],
        TAtlasOpenBuild.KindName(TAtlasOpenBuild.KindOf(ASettings.BuildOnOpenKind))) then
        FOpenBuild.Choice := Index + 1;
  FOpenBuildScope.Choice := Ord(TAtlasOpenBuild.ScopeOf(ASettings.BuildOnOpenScope));
  FOpenBuildDelay.Text := IntToStr(ASettings.BuildOnOpenDelayMs);
  FOpenBuildExclude.Text := TAtlasOpenBuild.NormalizedExclude(ASettings.BuildOnOpenExclude);
end;

procedure TAtlasSettingsPage.SaveOpenBuild(var ASettings: TAtlasPluginSettings);
begin
  // „nicht bauen“ behält die Art für das nächste Einschalten (Schnellschalter).
  ASettings.BuildOnOpen := FOpenBuild.Choice > 0;
  if (FOpenBuild.Choice > 0) and (FOpenBuild.Choice - 1 <= High(TAtlasOpenBuild.KindNames)) then
    ASettings.BuildOnOpenKind := TAtlasOpenBuild.KindNames[FOpenBuild.Choice - 1];
  if (FOpenBuildScope.Choice >= Ord(Low(TAtlasOpenBuildScope))) and
    (FOpenBuildScope.Choice <= Ord(High(TAtlasOpenBuildScope))) then
    ASettings.BuildOnOpenScope := TAtlasOpenBuild.ScopeNames[TAtlasOpenBuildScope(FOpenBuildScope.Choice)];
  ASettings.BuildOnOpenDelayMs := StrToIntDef(FOpenBuildDelay.Text, ASettings.BuildOnOpenDelayMs);
  ASettings.BuildOnOpenExclude := TAtlasOpenBuild.NormalizedExclude(FOpenBuildExclude.Text);
end;

procedure TAtlasSettingsPage.AddTasksSection;
begin
  AddTitle(TAtlasTextId.SettingsTasksTitle);
  FTasksEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTasksEnabled));
  FTasksProblemsFromOutput := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTasksProblemsFromOutput));
  // Reihenfolge wie TAtlasTaskBeforeBuild: off, warn, block.
  FTasksBeforeBuild := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsTasksBeforeBuild),
    [TAtlasStrings.Text(TAtlasTextId.SettingsTasksBeforeBuildOff),
    TAtlasStrings.Text(TAtlasTextId.SettingsTasksBeforeBuildWarn),
    TAtlasStrings.Text(TAtlasTextId.SettingsTasksBeforeBuildBlock)]);
  FTasksSaveBeforeRun := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTasksSaveBeforeRun));
  FTasksRunChecksParallel := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTasksRunChecksParallel));
  FTasksOnlyFindings := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTasksOnlyFindings));
end;

procedure TAtlasSettingsPage.LoadTasks(const ASettings: TAtlasPluginSettings);
var
  Mode: TAtlasTaskBeforeBuild;
begin
  FTasksEnabled.Checked := ASettings.TasksEnabled;
  FTasksProblemsFromOutput.Checked := ASettings.TasksProblemsFromOutput;
  TAtlasTasks.TryBeforeBuild(ASettings.TasksBeforeBuild, Mode);
  FTasksBeforeBuild.Choice := Ord(Mode);
  FTasksSaveBeforeRun.Checked := ASettings.TasksSaveBeforeRun;
  FTasksRunChecksParallel.Checked := ASettings.TasksRunChecksParallel;
  FTasksOnlyFindings.Checked := ASettings.TasksOnlyFindings;
end;

procedure TAtlasSettingsPage.SaveTasks(var ASettings: TAtlasPluginSettings);
begin
  ASettings.TasksEnabled := FTasksEnabled.Checked;
  ASettings.TasksProblemsFromOutput := FTasksProblemsFromOutput.Checked;
  if (FTasksBeforeBuild.Choice >= Ord(Low(TAtlasTaskBeforeBuild))) and
    (FTasksBeforeBuild.Choice <= Ord(High(TAtlasTaskBeforeBuild))) then
    ASettings.TasksBeforeBuild := TAtlasTasks.BeforeBuildNames[TAtlasTaskBeforeBuild(FTasksBeforeBuild.Choice)];
  ASettings.TasksSaveBeforeRun := FTasksSaveBeforeRun.Checked;
  ASettings.TasksRunChecksParallel := FTasksRunChecksParallel.Checked;
  ASettings.TasksOnlyFindings := FTasksOnlyFindings.Checked;
end;

procedure TAtlasSettingsPage.AddReleaseSection;
const
  Captions: array[TAtlasReleaseCheck] of TAtlasTextId = (TAtlasTextId.SettingsReleaseCheckDebugDefine,
    TAtlasTextId.SettingsReleaseCheckDebugInfo, TAtlasTextId.SettingsReleaseCheckStackFrames,
    TAtlasTextId.SettingsReleaseCheckAssertions, TAtlasTextId.SettingsReleaseCheckRangeChecks,
    TAtlasTextId.SettingsReleaseCheckOverflowChecks, TAtlasTextId.SettingsReleaseCheckMemoryLeaks,
    TAtlasTextId.SettingsReleaseCheckVersionInfo, TAtlasTextId.SettingsReleaseCheckOutputFolder);
var
  Check: TAtlasReleaseCheck;
begin
  FReleaseGuard := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReleaseGuard));
  // build.gate steht beim Compiler (#529) und gilt auch hier.
  FReleaseConfigs := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsReleaseConfigs));
  AddTitle(TAtlasTextId.SettingsReleaseChecksTitle);
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
    if TAtlasReleaseGuard.HasTarget[Check] then
      FReleaseCheckChoices[Check] := AddChoice(TAtlasStrings.Text(Captions[Check]),
        [TAtlasStrings.Text(TAtlasTextId.SettingsReleaseNotChecked),
        TAtlasStrings.Text(TAtlasTextId.SettingsReleaseExpectOff),
        TAtlasStrings.Text(TAtlasTextId.SettingsReleaseExpectOn)])
    else
      FReleaseCheckBoxes[Check] := AddCheck(TAtlasStrings.Text(Captions[Check]));
end;

function TAtlasSettingsPage.ReleaseCheckBox(ACheck: TAtlasReleaseCheck): TCheckBox;
begin
  Result := FReleaseCheckBoxes[ACheck];
end;

function TAtlasSettingsPage.ReleaseCheckChoice(ACheck: TAtlasReleaseCheck): TAtlasChoiceBox;
begin
  Result := FReleaseCheckChoices[ACheck];
end;

procedure TAtlasSettingsPage.LoadRelease(const ASettings: TAtlasPluginSettings);
var
  Checks: TAtlasReleaseChecks;
  Check: TAtlasReleaseCheck;
begin
  FReleaseGuard.Checked := ASettings.ReleaseGuard;
  FReleaseConfigs.Text := TAtlasReleaseGuard.NormalizedConfigurations(ASettings.ReleaseConfigs);
  Checks := TAtlasReleaseChecks.Parse(ASettings.ReleaseChecks);
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
    if FReleaseCheckChoices[Check] <> nil then
    begin
      if not Checks.Items[Check].Enabled then
        FReleaseCheckChoices[Check].Choice := 0
      else if Checks.Items[Check].Expected then
        FReleaseCheckChoices[Check].Choice := 2
      else
        FReleaseCheckChoices[Check].Choice := 1;
    end
    else if FReleaseCheckBoxes[Check] <> nil then
      FReleaseCheckBoxes[Check].Checked := Checks.Items[Check].Enabled;
end;

procedure TAtlasSettingsPage.SaveRelease(var ASettings: TAtlasPluginSettings);
var
  Checks: TAtlasReleaseChecks;
  Check: TAtlasReleaseCheck;
begin
  ASettings.ReleaseGuard := FReleaseGuard.Checked;
  ASettings.ReleaseConfigs := TAtlasReleaseGuard.NormalizedConfigurations(FReleaseConfigs.Text);
  Checks := TAtlasReleaseChecks.Parse(ASettings.ReleaseChecks);
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
    if FReleaseCheckChoices[Check] <> nil then
    begin
      if FReleaseCheckChoices[Check].Choice >= 0 then
      begin
        Checks.Items[Check].Enabled := FReleaseCheckChoices[Check].Choice > 0;
        if FReleaseCheckChoices[Check].Choice > 0 then
          Checks.Items[Check].Expected := FReleaseCheckChoices[Check].Choice = 2;
      end;
    end
    else if FReleaseCheckBoxes[Check] <> nil then
      Checks.Items[Check].Enabled := FReleaseCheckBoxes[Check].Checked;
  ASettings.ReleaseChecks := Checks.ToText;
end;

procedure TAtlasSettingsPage.AddTransferSection;
const
  BarHeight = 66;
  ButtonHeight = 25;
  Row2 = 34;

  function AddButton(const ACaption: string; ALeft, ATop, AWidth: Integer; const AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := FTransferBar;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, AWidth, ButtonHeight);
    Result.OnClick := AClick;
  end;

begin
  AddTitle(TAtlasTextId.SettingsTransferTitle);
  FSettingsExportImport := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsExportImport));
  FSettingsMarkModified := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMarkModified));
  FSettingsBackupBeforeImport := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBackupBeforeImport));
  FSettingsExportSecrets := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsExportSecrets),
    [TAtlasStrings.Text(TAtlasTextId.SettingsExportSecretsOmit),
    TAtlasStrings.Text(TAtlasTextId.SettingsExportSecretsPlaceholder)]);
  // Knöpfe unten über die ganze Seite; ohne settings.exportImport ausgeblendet (RefreshMarks).
  FTransferBar := TAtlasSettingsRow.Create(Self);
  FTransferBar.Parent := Self;
  FTransferBar.Align := alBottom;
  FTransferBar.AlignWithMargins := True;
  FTransferBar.Height := BarHeight;
  FExportButton := AddButton(TAtlasStrings.Text(TAtlasTextId.SettingsExportButton), 0, 4, 120, ExportClick);
  FImportButton := AddButton(TAtlasStrings.Text(TAtlasTextId.SettingsImportButton), 126, 4, 120, ImportClick);
  FProfileButton := AddButton(TAtlasStrings.Text(TAtlasTextId.SettingsProfileButton), 252, 4, 120, ProfileClick);
  FResetPageButton := AddButton(TAtlasStrings.Text(TAtlasTextId.SettingsResetPageButton), 0, Row2, 150,
    ResetPageClick);
  FResetAllButton := AddButton(TAtlasStrings.Text(TAtlasTextId.SettingsResetAllButton), 156, Row2, 150,
    ResetAllClick);
  FMarks := TAtlasSettingsMarks.Create(Self);
  FMarks.OnChanged := MarksChanged;
  FMarks.OnResetPage := ResetPageClick;
  FMarks.OnReset :=
    procedure(ANames: TArray<string>)
    begin
      ResetNames(ANames);
    end;
end;

procedure TAtlasSettingsPage.BindControls;
var
  Check: TAtlasReleaseCheck;
  Series: TAtlasTrendSeries;
  mAction: TAtlasQuickAction;
  Kind: TAtlasOverviewKind;
  VisualizerKind: TAtlasVisualizerKind;
  StepFilterKind: TStepFilterKind;
  Target: TAtlasReassignedTarget;
begin
  // Aus SaveTo: Element und die Einstellungen, die es schreibt. Listen aus mehreren Haken zeigen keinen Punkt
  // (der gälte für jeden Haken), lassen sich aber zurücksetzen.
  FMarks.Bind(FEnabled, ['Enabled']);
  FMarks.Bind(FActionsKey, ['ActionsKey']);
  FMarks.Bind(FExpandKey, ['ExpandKey']);
  FMarks.Bind(FShrinkKey, ['ShrinkKey']);
  FMarks.Bind(FImplementationKey, ['ImplementationKey']);
  FMarks.Bind(FTypeDefinitionKey, ['TypeDefinitionKey']);
  FMarks.Bind(FMethodToggle, ['MethodToggle']);
  FMarks.Bind(FMethodToggleUpKey, ['MethodToggleUpKey']);
  FMarks.Bind(FMethodToggleDownKey, ['MethodToggleDownKey']);
  FMarks.Bind(FTestUnitKey, ['TestUnitKey']);
  FMarks.Bind(FGotoInterfaceKey, ['GotoInterfaceKey']);
  FMarks.Bind(FGotoImplementationKey, ['GotoImplementationKey']);
  FMarks.Bind(FNavHistory, ['NavHistory']);
  FMarks.Bind(FNavBackKey, ['NavBackKey']);
  FMarks.Bind(FNavForwardKey, ['NavForwardKey']);
  FMarks.Bind(FLastEditKey, ['LastEditKey']);
  FMarks.Bind(FPeek, ['Peek']);
  FMarks.Bind(FPeekHeightLines, ['PeekHeightLines']);
  FMarks.Bind(FPeekShowImplementation, ['PeekShowImplementation']);
  FMarks.Bind(FDataFlow, ['DataFlow']);
  FMarks.Bind(FDataFlowMaxDepth, ['DataFlowMaxDepth']);
  FMarks.Bind(FDataFlowExcludeTests, ['DataFlowExcludeTests']);
  FMarks.Bind(FPeekDefinitionKey, ['PeekDefinitionKey']);
  FMarks.Bind(FPeekReferencesKey, ['PeekReferencesKey']);
  FMarks.Bind(FReferencesInferred, ['ReferencesInferred']);
  FMarks.Bind(FReferencesTextMatches, ['ReferencesTextMatches']);
  FMarks.Bind(FCallHierarchyDiagram, ['CallHierarchyDiagram']);
  FMarks.Bind(FImpact, ['Impact']);
  FMarks.Bind(FImpactDepth, ['ImpactDepth']);
  FMarks.Bind(FOutline, ['Outline']);
  FMarks.Bind(FOutlineAlphabetical, ['OutlineAlphabetical']);
  FMarks.Bind(FOutlineFollowCursor, ['OutlineFollowCursor']);
  FMarks.Bind(FOutlineConditions, ['OutlineConditions']);
  FMarks.Bind(FBreadcrumbs, ['Breadcrumbs']);
  FMarks.Bind(FBreadcrumbsShowUnit, ['BreadcrumbsShowUnit']);
  FMarks.Bind(FBreadcrumbsIdeColors, ['BreadcrumbsIdeColors']);
  FMarks.Bind(FBreadcrumbsHideIdeToolbar, ['BreadcrumbsHideIdeToolbar']);
  FMarks.Bind(FBreadcrumbsKey, ['BreadcrumbsKey']);
  FMarks.Bind(FEditorToolbar, ['EditorToolbar']);
  FMarks.Bind(FEditorToolbarPosition, ['EditorToolbarPosition']);
  FMarks.Bind(FEditorToolbarItems, ['EditorToolbarItems']);
  FMarks.Bind(FEditorToolbarReturnButton, ['EditorToolbarReturnButton']);
  FMarks.Bind(FEditorToolbarLabels, ['EditorToolbarLabels']);
  FMarks.Bind(FEditorStatusBar, ['EditorStatusBar']);
  FMarks.Bind(FEditorStatusBarItems, ['EditorStatusBarItems']);
  FMarks.Bind(FStickyScroll, ['StickyScroll']);
  FMarks.Bind(FStickyScrollMaxLines, ['StickyScrollMaxLines']);
  FMarks.Bind(FMinimap, ['Minimap']);
  FMarks.Bind(FMinimapRender, ['MinimapRender']);
  FMarks.Bind(FMinimapWidth, ['MinimapWidth']);
  FMarks.Bind(FMinimapScale, ['MinimapScale']);
  FMarks.Bind(FMinimapMaxColumn, ['MinimapMaxColumn']);
  FMarks.Bind(FMinimapSide, ['MinimapSide']);
  FMarks.Bind(FMinimapShowSlider, ['MinimapShowSlider']);
  FMarks.Bind(FMinimapSectionHeaders, ['MinimapSectionHeaders']);
  FMarks.Bind(FMinimapHighlightMethod, ['MinimapHighlightMethod']);
  FMarks.Bind(FMinimapMarkers, ['MinimapMarkers']);
  FMarks.Bind(FMinimapClickJumps, ['MinimapClickJumps']);
  FMarks.Bind(FGitGutter, ['GitGutter']);
  FMarks.Bind(FGitBlame, ['GitBlame']);
  FMarks.Bind(FGutterColumn, ['GutterColumn']);
  FMarks.Bind(FGutterColumnProblems, ['GutterColumnProblems']);
  FMarks.Bind(FGutterColumnCodeActions, ['GutterColumnCodeActions']);
  FMarks.Bind(FGutterColumnOverrides, ['GutterColumnOverrides']);
  FMarks.Bind(FSelectionMatches, ['SelectionMatches']);
  FMarks.Bind(FSelectionMatchesMinLength, ['SelectionMatchesMinLength']);
  FMarks.Bind(FSelectionMatchesCaseSensitive, ['SelectionMatchesCaseSensitive']);
  FMarks.Bind(FSelectionMatchesWholeWord, ['SelectionMatchesWholeWord']);
  FMarks.Bind(FSelectionMatchesNavigateF3, ['SelectionMatchesNavigateF3']);
  FMarks.Bind(FSelectionMatchesMaxMatches, ['SelectionMatchesMaxMatches']);
  FMarks.Bind(FExitPoints, ['ExitPoints']);
  FMarks.Bind(FExitPointsExceptions, ['ExitPointsExceptions']);
  FMarks.Bind(FExitPointsLoops, ['ExitPointsLoops']);
  FMarks.Bind(FExitPointsBadge, ['ExitPointsBadge']);
  FMarks.Bind(FReassigned, ['Reassigned']);
  for Target := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
    FMarks.Bind(FReassignedTargets[Target], ['ReassignedTargets']);
  FMarks.Bind(FReassignedStyle, ['ReassignedStyle']);
  FMarks.Bind(FReassignedColor, ['ReassignedColor']);
  FMarks.Bind(FExpressionType, ['ExpressionType']);
  FMarks.Bind(FExpressionTypeConversions, ['ExpressionTypeConversions']);
  FMarks.Bind(FExpressionTypeConstValue, ['ExpressionTypeConstValue']);
  FMarks.Bind(FExpressionTypeKey, ['ExpressionTypeKey']);
  FMarks.Bind(FMethodPlacement, ['MethodPlacement']);
  FMarks.Bind(FNextChangeKey, ['NextChangeKey']);
  FMarks.Bind(FPreviousChangeKey, ['PreviousChangeKey']);
  FMarks.Bind(FOverviewRuler, ['OverviewRuler']);
  for Kind := Low(TAtlasOverviewKind) to High(TAtlasOverviewKind) do
    FMarks.Bind(FOverviewKinds[Kind], ['OverviewRulerKinds']);
  FMarks.Bind(FJumpToMatch, ['JumpToMatch']);
  FMarks.Bind(FJumpToMatchKey, ['JumpToMatchKey']);
  FMarks.Bind(FJumpToMatchSelectKey, ['JumpToMatchSelectKey']);
  FMarks.Bind(FMoveLines, ['MoveLines']);
  FMarks.Bind(FMoveLinesUpKey, ['MoveLinesUpKey']);
  FMarks.Bind(FMoveLinesDownKey, ['MoveLinesDownKey']);
  FMarks.Bind(FDuplicateLinesUpKey, ['DuplicateLinesUpKey']);
  FMarks.Bind(FDuplicateLinesDownKey, ['DuplicateLinesDownKey']);
  FMarks.Bind(FToggleBlockComment, ['ToggleBlockComment']);
  FMarks.Bind(FToggleBlockCommentKey, ['ToggleBlockCommentKey']);
  FMarks.Bind(FToggleBlockCommentStyle, ['ToggleBlockCommentStyle']);
  FMarks.Bind(FToggleBlockCommentFallback, ['ToggleBlockCommentFallback']);
  FMarks.Bind(FToggleBlockCommentOwnLines, ['ToggleBlockCommentOwnLines']);
  FMarks.Bind(FToggleBlockCommentScope, ['ToggleBlockCommentWithoutSelection']);
  FMarks.Bind(FNewLineAround, ['NewLineAround']);
  FMarks.Bind(FNewLineBelowKey, ['NewLineBelowKey']);
  FMarks.Bind(FNewLineAboveKey, ['NewLineAboveKey']);
  FMarks.Bind(FNewLineAroundStatementAware, ['NewLineAroundStatementAware']);
  FMarks.Bind(FUnwrap, ['Unwrap']);
  FMarks.Bind(FUnwrapKey, ['UnwrapKey']);
  FMarks.Bind(FSafeDelete, ['SafeDelete']);
  FMarks.Bind(FSafeDeleteKey, ['SafeDeleteKey']);
  FMarks.Bind(FContinueComments, ['ContinueComments']);
  FMarks.Bind(FContinueCommentsLineComments, ['ContinueCommentsLineComments']);
  FMarks.Bind(FContinueCommentsLists, ['ContinueCommentsLists']);
  FMarks.Bind(FContinueCommentsBlockPrefix, ['ContinueCommentsBlockPrefix']);
  FMarks.Bind(FWrapSelection, ['WrapSelection']);
  FMarks.Bind(FWrapSelectionChars, ['WrapSelectionChars']);
  FMarks.Bind(FCompleteStatement, ['CompleteStatement']);
  FMarks.Bind(FCompleteStatementKey, ['CompleteStatementKey']);
  FMarks.Bind(FCompleteStatementBeginEnd, ['CompleteStatementBeginEnd']);
  FMarks.Bind(FCompleteStatementTryKind, ['CompleteStatementTryKind']);
  FMarks.Bind(FCompleteStatementMethodBody, ['CompleteStatementMethodBody']);
  FMarks.Bind(FFormatCode, ['FormatCode']);
  FMarks.Bind(FFormatCodeKey, ['FormatCodeKey']);
  FMarks.Bind(FContinuePattern, ['ContinuePattern']);
  FMarks.Bind(FContinuePatternMinLines, ['ContinuePatternMinLines']);
  FMarks.Bind(FMultiCursor, ['MultiCursor']);
  FMarks.Bind(FMultiCursorModifier, ['MultiCursorModifier']);
  FMarks.Bind(FMultiCursorNextKey, ['MultiCursorNextKey']);
  FMarks.Bind(FMultiCursorSkipKey, ['MultiCursorSkipKey']);
  FMarks.Bind(FMultiCursorLineEndsKey, ['MultiCursorLineEndsKey']);
  FMarks.Bind(FMultiCursorAboveKey, ['MultiCursorAboveKey']);
  FMarks.Bind(FMultiCursorBelowKey, ['MultiCursorBelowKey']);
  FMarks.Bind(FLinkedEditing, ['LinkedEditing']);
  FMarks.Bind(FSmartPaste, ['SmartPaste']);
  FMarks.Bind(FBookmarkKey, ['BookmarkKey']);
  FMarks.Bind(FNextBookmarkKey, ['NextBookmarkKey']);
  FMarks.Bind(FPreviousBookmarkKey, ['PreviousBookmarkKey']);
  FMarks.Bind(FHideElementKey, ['HideElementKey']);
  FMarks.Bind(FNextProblemKey, ['NextProblemKey']);
  FMarks.Bind(FPreviousProblemKey, ['PreviousProblemKey']);
  FMarks.Bind(FProblemsWindowKey, ['ProblemsWindowKey']);
  FMarks.Bind(FCreateIssueKey, ['CreateIssueKey']);
  FMarks.Bind(FUndoKey, ['UndoKey']);
  FMarks.Bind(FRedoKey, ['RedoKey']);
  FMarks.Bind(FUpdatesCheck, ['UpdatesCheck']);
  FMarks.Bind(FBugReportAnonymize, ['BugReportAnonymize']);
  FMarks.Bind(FEditorKeysPriority, ['EditorKeysPriority']);
  FMarks.Bind(FSlashCommands, ['SlashCommands']);
  FMarks.Bind(FGenerateMenu, ['GenerateMenu']);
  FMarks.Bind(FGenerateMenuKey, ['GenerateMenuKey']);
  FMarks.Bind(FNotificationsKey, ['NotificationsKey']);
  FMarks.Bind(FGenerateMenuGroups, ['GenerateMenuGroups']);
  FMarks.Bind(FGenerateMenuHidden, ['GenerateMenuHidden']);
  FMarks.Bind(FGenerateMenuRecentFirst, ['GenerateMenuRecentFirst']);
  FMarks.Bind(FGenerateMenuShowCommandNames, ['GenerateMenuShowCommandNames']);
  FMarks.Bind(FRows, ['VisibleRows']);
  FMarks.Bind(FPanelCollapsed, ['PanelCollapsed']);
  FMarks.Bind(FSelectionMarker, ['SelectionMarker']);
  FMarks.Bind(FAutoParentheses, ['AutoParentheses']);
  FMarks.Bind(FFixCase, ['FixCase']);
  FMarks.Bind(FCommitChars, ['CommitCharacters']);
  FMarks.Bind(FAutoUses, ['AutoUses']);
  FMarks.Bind(FParameterHints, ['ParameterHints']);
  FMarks.Bind(FFormatPlaceholders, ['FormatPlaceholders']);
  FMarks.Bind(FOpenDelay, ['OpenDelayMs']);
  FMarks.Bind(FFilterChips, ['FilterChips']);
  FMarks.Bind(FLearning, ['Learning']);
  FMarks.Bind(FFavorites, ['Favorites']);
  FMarks.Bind(FGroupInherited, ['GroupInherited']);
  FMarks.Bind(FCompletionVariantBranch, ['CompletionVariantBranch']);
  FMarks.Bind(FListMode, ['CompletionListMode']);
  FMarks.Bind(FListScope, ['CompletionListScope']);
  FMarks.Bind(FPreview, ['Preview']);
  FMarks.Bind(FSnippets, ['Snippets']);
  FMarks.Bind(FImportIdeTemplates, ['ImportIdeTemplates']);
  FMarks.Bind(FTeamFile, ['TeamFile']);
  FMarks.Bind(FHoverTooltip, ['HoverTooltip']);
  FMarks.Bind(FXmlDocExpand, ['XmlDocExpand']);
  FMarks.Bind(FXmlDocMaxLines, ['XmlDocMaxLines']);
  FMarks.Bind(FHangThreshold, ['HangThresholdMs']);
  FMarks.Bind(FProviderTimeLimit, ['ProviderTimeLimitMs']);
  FMarks.Bind(FHangHint, ['HangHint']);
  FMarks.Bind(FReloadExternal, ['ReloadExternal']);
  FMarks.Bind(FOpenForEdits, ['OpenForEdits']);
  FMarks.Bind(FPairColors, ['PairColors']);
  FMarks.Bind(FInactiveDim, ['InactiveDim']);
  FMarks.Bind(FInlayHints, ['InlayHints']);
  FMarks.Bind(FInlayTypeHints, ['InlayTypeHints']);
  FMarks.Bind(FInlayDefineHints, ['InlayDefineHints']);
  FMarks.Bind(FInlayCharHints, ['InlayCharHints']);
  FMarks.Bind(FInlayMethodHints, ['InlayMethodHints']);
  FMarks.Bind(FBlockEndLabels, ['BlockEndLabels']);
  FMarks.Bind(FBlockEndLabelsMinLines, ['BlockEndLabelsMinLines']);
  FMarks.Bind(FDimUnusedUses, ['DimUnusedUses']);
  FMarks.Bind(FRecursionMarkers, ['RecursionMarkers']);
  FMarks.Bind(FRecursionMarkersDepth, ['RecursionMarkersDepth']);
  FMarks.Bind(FInlineDiagnostics, ['InlineDiagnostics']);
  FMarks.Bind(FNotes, ['Notes']);
  FMarks.Bind(FBookmarksNamed, ['BookmarksNamed']);
  FMarks.Bind(FBookmarksShared, ['BookmarksShared']);
  FMarks.Bind(FQuickBookmarks, ['QuickBookmarks']);
  FMarks.Bind(FQuickBookmarksGutter, ['QuickBookmarksGutter']);
  FMarks.Bind(FQuickBookmarksGutterClick, ['QuickBookmarksGutterClick']);
  FMarks.Bind(FQuickBookmarksNumberedKeys, ['QuickBookmarksNumberedKeys']);
  FMarks.Bind(FQuickBookmarkKey, ['QuickBookmarkKey']);
  FMarks.Bind(FQuickBookmarkChordWait, ['QuickBookmarkChordWait']);
  FMarks.Bind(FQuickBookmarksScope, ['QuickBookmarksScope']);
  FMarks.Bind(FQuickBookmarksImportIde, ['QuickBookmarksImportIde']);
  FMarks.Bind(FCodeLensTestUnit, ['CodeLensTestUnit']);
  FMarks.Bind(FCodeLensMetrics, ['CodeLensMetrics']);
  FMarks.Bind(FMetrics, ['Metrics']);
  FMarks.Bind(FCodeLensTests, ['CodeLensTests']);
  FMarks.Bind(FTodoList, ['TodoList']);
  FMarks.Bind(FBaselineUpdate, ['BaselineUpdate']);
  FMarks.Bind(FMetricsReport, ['MetricsReport']);
  FMarks.Bind(FDfmPropertyRules, ['DfmPropertyRules']);
  FMarks.Bind(FPairGuides, ['PairGuides']);
  FMarks.Bind(FPairOwners, ['PairOwners']);
  FMarks.Bind(FPairGuideWidth, ['PairGuideWidth']);
  FMarks.Bind(FPairGuideOpacity, ['PairGuideOpacity']);
  FMarks.Bind(FLightSwatches[0], ['PairColorsLight']);
  FMarks.Bind(FDarkSwatches[0], ['PairColorsDark']);
  FMarks.Bind(FProblems, ['Problems']);
  FMarks.Bind(FProblemsList, ['ProblemsList']);
  FMarks.Bind(FProblemsWindow, ['ProblemsWindow']);
  FMarks.Bind(FProblemsWindowScope, ['ProblemsWindowScope']);
  FMarks.Bind(FProblemsWindowGroupBy, ['ProblemsWindowGroupBy']);
  FMarks.Bind(FProblemsWindowCompiler, ['ProblemsWindowCompiler']);
  FMarks.Bind(FProblemsWindowFollowCursor, ['ProblemsWindowFollowCursor']);
  FMarks.Bind(FProblemsWindowOpenFirst, ['ProblemsWindowOpenFirst']);
  FMarks.Bind(FProblemsWindowClosedUnits, ['ProblemsWindowClosedUnits']);
  FMarks.Bind(FProblemsWindowShowCleanActive, ['ProblemsWindowShowCleanActive']);
  FMarks.Bind(FProblemsLive, ['ProblemsLive']);
  FMarks.Bind(FProblemsCompilerMerge, ['ProblemsCompilerMerge']);
  FMarks.Bind(FProblemsShowCompilerCode, ['ProblemsShowCompilerCode']);
  FMarks.Bind(FHoverProblemActions, ['HoverProblemActions']);
  FMarks.Bind(FProblemsStatusCounter, ['ProblemsStatusCounter']);
  FMarks.Bind(FStatusField, ['StatusField']);
  FMarks.Bind(FDiagnosticMode, ['DiagnosticMode']);
  FMarks.Bind(FDiagnosticsProcesses, ['DiagnosticsProcesses']);
  FMarks.Bind(FArchitecture, ['ArchitectureEnabled']);
  FMarks.Bind(FArchitectureScope, ['ArchitectureScope']);
  FMarks.Bind(FArchitectureLibrary, ['ArchitectureIncludeLibraryUnits']);
  FMarks.Bind(FArchitectureCentral, ['ArchitectureCentralUnits']);
  FMarks.Bind(FExperimentalEnabled, ['ExperimentalEnabled']);
  FMarks.Bind(FSetupChecklist, ['SetupChecklist']);
  FMarks.Bind(FShortcutTips, ['ShortcutTips']);
  FMarks.Bind(FShortcutTipsScope, ['ShortcutTipsScope']);
  FMarks.Bind(FNotifications, ['Notifications']);
  FMarks.Bind(FNotificationsMax, ['NotificationsMaxEntries']);
  FMarks.Bind(FNotificationSource, ['NotificationsSources']);
  FMarks.Bind(FStatusSummary, ['StatusFieldSummary']);
  FMarks.Bind(FStatusToggles, ['StatusFieldToggles']);
  FMarks.Bind(FIndexProgress, ['IndexProgressPlace']);
  FMarks.Bind(FStatusHidden, ['StatusFieldHidden']);
  FMarks.Bind(FIndexGroup, ['IndexProjectGroup']);
  FMarks.Bind(FIndexSearch, ['IndexSearchPaths']);
  FMarks.Bind(FIndexLibrary, ['IndexLibraryPaths']);
  FMarks.Bind(FIndexUsages, ['IndexUsages']);
  FMarks.Bind(FMemoryBudget, ['MemoryBudgetMb']);
  FMarks.Bind(FAfterSave, ['CheckOnSave', 'CompileOnSave']);
  FMarks.Bind(FCheckDelay, ['CheckOnSaveDelayMs']);
  FMarks.Bind(FCheckMax, ['CheckOnSaveMaxMs']);
  FMarks.Bind(FMcpBuild, ['McpBuild']);
  FMarks.Bind(FTestRun, ['TestRun']);
  FMarks.Bind(FTestsBuildFirst, ['TestsBuildFirst']);
  FMarks.Bind(FTestsAfterBuild, ['TestsAfterBuild']);
  FMarks.Bind(FBuildZeroHints, ['BuildZeroHints']);
  FMarks.Bind(FShowInterfaceCost, ['ShowInterfaceCost']);
  FMarks.Bind(FBuildSummary, ['BuildSummary']);
  FMarks.Bind(FBuildWarningsAsErrors, ['BuildWarningsAsErrors']);
  FMarks.Bind(FBuildGateTimeout, ['BuildGateTimeoutMs']);
  FMarks.Bind(FBuildCompilerSwitches, ['BuildCompilerSwitches']);
  FMarks.Bind(FBuildSwitchesInStatusBar, ['BuildSwitchesInStatusBar']);
  FMarks.Bind(FStartProfiles, ['StartProfiles']);
  FMarks.Bind(FStartProfilesStatusField, ['StartProfilesStatusField']);
  FMarks.Bind(FTestDebug, ['TestDebug']);
  FMarks.Bind(FTestBreakAtStart, ['TestBreakAtStart']);
  FMarks.Bind(FDebugHoverValues, ['DebugHoverValues']);
  FMarks.Bind(FDebugVisualizers, ['DebugVisualizers']);
  for VisualizerKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
    FMarks.Bind(FDebugVisualizerKinds[VisualizerKind], ['DebugVisualizerTypes']);
  FMarks.Bind(FDebugVisualizerNameFields, ['DebugVisualizerNameFields']);
  FMarks.Bind(FDebugVisualizerMaxLength, ['DebugVisualizerMaxLength']);
  FMarks.Bind(FDebugVisualizerTimeout, ['DebugVisualizerTimeoutMs']);
  FMarks.Bind(FDebugVisualizerMaxImagePixels, ['DebugVisualizerMaxImagePixels']);
  FMarks.Bind(FDebugVisualizerEvaluation, ['DebugVisualizerEvaluation']);
  FMarks.Bind(FDebugDisplayRules, ['DebugDisplayRules']);
  FMarks.Bind(FDebugDisplayRulesAllowCalls, ['DebugDisplayRulesAllowCalls']);
  FMarks.Bind(FDebugStepIntoTarget, ['DebugStepIntoTarget']);
  FMarks.Bind(FDebugStepFilters, ['DebugStepFilters']);
  for StepFilterKind := Low(TStepFilterKind) to High(TStepFilterKind) do
    FMarks.Bind(FDebugStepFilterKinds[StepFilterKind], ['DebugStepFilterKinds']);
  FMarks.Bind(FDebugStepFilterPatterns, ['DebugStepFilterPatterns']);
  FMarks.Bind(FDebugStepIntoTargetKey, ['DebugStepIntoTargetKey']);
  FMarks.Bind(FDebugBreakOnNextEvent, ['DebugBreakOnNextEvent']);
  FMarks.Bind(FDebugBreakOnNextEventExcluded, ['DebugBreakOnNextEventExcluded']);
  FMarks.Bind(FDebugExplainUnavailable, ['DebugExplainUnavailable']);
  FMarks.Bind(FDebugCompletionInDialogs, ['DebugCompletionInDialogs']);
  FMarks.Bind(FDebugEvaluateWindow, ['DebugEvaluateWindow']);
  FMarks.Bind(FDebugEvaluateReplaceCtrlF7, ['DebugEvaluateReplaceCtrlF7']);
  FMarks.Bind(FDebugExplainAccessViolation, ['DebugExplainAccessViolation']);
  FMarks.Bind(FDebugExplainAccessViolationAllowCalls, ['DebugExplainAccessViolationAllowCalls']);
  FMarks.Bind(FDebugExceptionHistory, ['DebugExceptionHistory']);
  FMarks.Bind(FDebugJustMyCode, ['DebugJustMyCode']);
  FMarks.Bind(FDebugExceptionBanner, ['DebugExceptionBanner']);
  FMarks.Bind(FDebugExceptionBannerIgnoreAtLocation, ['DebugExceptionBannerIgnoreAtLocation']);
  FMarks.Bind(FDebugInlineValues, ['DebugInlineValues']);
  FMarks.Bind(FDebugInlineValuesPerLine, ['DebugInlineValuesPerLine']);
  FMarks.Bind(FDebugOwnCodeFolders, ['DebugOwnCodeFolders']);
  FMarks.Bind(FSafeAsk, ['SafeAskAfterCrash']);
  FMarks.Bind(FSafeAuto, ['SafeAutoAfterRepeatedCrash']);
  FMarks.Bind(FSafeKey, ['SafeStartupKey']);
  FMarks.Bind(FSafeTimeout, ['SafeStartupTimeoutMs']);
  FMarks.Bind(FSafeHistory, ['SafeKeepSettingsHistory']);
  FMarks.Bind(FUndoEnabled, ['UndoMultiFile']);
  FMarks.Bind(FUndoDepth, ['UndoMultiFileDepth']);
  FMarks.Bind(FUndoPersist, ['UndoMultiFilePersist']);
  FMarks.Bind(FUndoMaxSize, ['UndoMultiFileMaxSizeMb']);
  FMarks.Bind(FUndoOnConflict, ['UndoMultiFileOnConflict']);
  FMarks.Bind(FUndoNewFiles, ['UndoMultiFileNewFiles']);
  FMarks.Bind(FUnitSearchEnabled, ['UnitSearchEnabled']);
  FMarks.Bind(FUnitSearchReplace, ['UnitSearchReplaceIdeDialog']);
  FMarks.Bind(FUnitSearchReplaceUseUnit, ['UnitSearchReplaceUseUnitDialog']);
  FMarks.Bind(FUnitSearchReplaceForms, ['UnitSearchReplaceFormsDialog']);
  FMarks.Bind(FUnitSearchKey, ['UnitSearchKey']);
  FMarks.Bind(FUnitSearchPathStyle, ['UnitSearchPathStyle']);
  FMarks.Bind(FUnitSearchGroupBy, ['UnitSearchGroupBy']);
  FMarks.Bind(FUnitSearchRememberCollapsed, ['UnitSearchRememberCollapsed']);
  FMarks.Bind(FUnitSearchFilters, ['UnitSearchFilters']);
  FMarks.Bind(FUnitSearchDefaultScope, ['UnitSearchDefaultScope']);
  FMarks.Bind(FUnitSearchFilterSyntax, ['UnitSearchFilterSyntax']);
  FMarks.Bind(FUnitSearchPreview, ['UnitSearchPreview']);
  FMarks.Bind(FUnitSearchPreviewForm, ['UnitSearchPreviewForm']);
  FMarks.Bind(FUnitSearchPreviewUsedBy, ['UnitSearchPreviewUsedBy']);
  FMarks.Bind(FUnitSearchPreviewAutoCollapse, ['UnitSearchPreviewAutoCollapse']);
  FMarks.Bind(FUnitSearchMultiSelect, ['UnitSearchMultiSelect']);
  FMarks.Bind(FUnitSearchActions, ['UnitSearchActions']);
  FMarks.Bind(FUnitSearchAddUses, ['UnitSearchActionsAddUses']);
  FMarks.Bind(FQuickOpen, ['QuickOpen']);
  FMarks.Bind(FQuickOpenLibrary, ['QuickOpenLibrary']);
  FMarks.Bind(FQuickOpenKey, ['QuickOpenKey']);
  FMarks.Bind(FSearchReplace, ['SearchReplaceIde']);
  FMarks.Bind(FSearchMessages, ['SearchResultsInMessages']);
  FMarks.Bind(FSearchReplaceBar, ['SearchReplace']);
  FMarks.Bind(FSearchRegex, ['SearchRegex']);
  FMarks.Bind(FSearchHistory, ['SearchHistory']);
  FMarks.Bind(FSearchMultiFile, ['SearchMultiFile']);
  FMarks.Bind(FWelcomeEnabled, ['WelcomePage']);
  FMarks.Bind(FWelcomeOpenOnStart, ['WelcomePageOpenOnStart']);
  FMarks.Bind(FWelcomeOpenWhenNoProject, ['WelcomePageOpenWhenNoProject']);
  FMarks.Bind(FWelcomeCustomLayout, ['WelcomePageCustomLayout']);
  FMarks.Bind(FWelcomeColumns, ['WelcomePageColumns']);
  FMarks.Bind(FWelcomeActiveLayout, ['WelcomePageActiveLayout', 'WelcomePageLayouts']);
  FMarks.Bind(FWelcomeHeader, ['WelcomePageHeader']);
  FMarks.Bind(FWelcomeGreeting, ['WelcomePageGreeting']);
  FMarks.Bind(FWelcomeSearch, ['WelcomePageSearch']);
  FMarks.Bind(FWelcomeSearchSymbols, ['WelcomePageSearchSymbols']);
  FMarks.Bind(FWelcomeSearchKey, ['WelcomePageSearchKey']);
  FMarks.Bind(FWelcomeWhatsNew, ['WelcomePageWhatsNew']);
  FMarks.Bind(FWelcomeContinue, ['WelcomePageContinue']);
  FMarks.Bind(FWelcomeContinueCount, ['WelcomePageContinueCount']);
  FMarks.Bind(FWelcomeContinueIncoming, ['WelcomePageContinueIncoming']);
  FMarks.Bind(FWelcomeContinueFetch, ['WelcomePageContinueFetch']);
  FMarks.Bind(FWelcomeSaved, ['WelcomePageSaved']);
  FMarks.Bind(FWelcomeProjects, ['WelcomePageProjectStatus']);
  FMarks.Bind(FWelcomeMaxProjects, ['WelcomePageMaxProjects']);
  FMarks.Bind(FWelcomeRefreshVcs, ['WelcomePageRefreshVcs']);
  FMarks.Bind(FWelcomeTrends, ['WelcomePageTrends']);
  FMarks.Bind(FWelcomeTrendsPoints, ['WelcomePageTrendsPoints']);
  FMarks.Bind(FWelcomeTests, ['WelcomePageTests']);
  FMarks.Bind(FWelcomeTestsMaxFailures, ['WelcomePageTestsMaxFailures']);
  FMarks.Bind(FWelcomeTestsCi, ['WelcomePageTestsCi']);
  FMarks.Bind(FWelcomeTestsCiInterval, ['WelcomePageTestsCiIntervalMinutes']);
  FMarks.Bind(FWelcomeTestsCiNotify, ['WelcomePageTestsCiNotify']);
  FMarks.Bind(FCiLogin, ['CiLogin']);
  FMarks.Bind(FWelcomeQuickActions, ['WelcomePageQuickActions']);
  FMarks.Bind(FWelcomeQuickActionsConsole, ['WelcomePageQuickActionsConsole']);
  FMarks.Bind(FWelcomeQuickActionsBuildKey, ['WelcomePageQuickActionsBuildKey']);
  FMarks.Bind(FWelcomeQuickActionsTestKey, ['WelcomePageQuickActionsTestKey']);
  FMarks.Bind(FWelcomeUnsaved, ['WelcomePageUnsaved']);
  FMarks.Bind(FWelcomeUnsavedMinAge, ['WelcomePageUnsavedMinAgeHours']);
  FMarks.Bind(FWelcomeUnsavedWarn, ['WelcomePageUnsavedWarnHours']);
  FMarks.Bind(FWelcomeUnsavedAlert, ['WelcomePageUnsavedAlertHours']);
  FMarks.Bind(FWelcomeUnsavedHideClean, ['WelcomePageUnsavedHideWhenClean']);
  FMarks.Bind(FWelcomeStatusTile, ['WelcomePageStatusTile']);
  FMarks.Bind(FWelcomeStatusTileOnlyProblems, ['WelcomePageStatusTileOnlyProblems']);
  FMarks.Bind(FWelcomeDiscover, ['WelcomePageDiscover']);
  FMarks.Bind(FTipsUsageTracking, ['TipsUsageTracking']);
  FMarks.Bind(FWelcomeHelp, ['WelcomePageHelp']);
  FMarks.Bind(FWelcomeHelpReportUrl, ['WelcomePageHelpReportUrl']);
  FMarks.Bind(FWelcomeHelpReportFolder, ['WelcomePageHelpReportFolder']);
  FMarks.Bind(FWelcomeProjectSetup, ['WelcomePageProjectSetup']);
  FMarks.Bind(FWelcomeNewFromTemplate, ['WelcomePageNewFromTemplate']);
  FMarks.Bind(FWelcomeIssues, ['WelcomePageIssues']);
  FMarks.Bind(FIssuesTracker, ['IssuesTracker']);
  FMarks.Bind(FIssuesStart, ['IssuesStart']);
  FMarks.Bind(FIssuesBranchPattern, ['IssuesBranchPattern']);
  FMarks.Bind(FIssuesBranchBase, ['IssuesBranchBase']);
  FMarks.Bind(FIssuesCommitPattern, ['IssuesCommitPattern']);
  FMarks.Bind(FTrackerLogin, ['TrackerLogin']);
  FMarks.Bind(FIssuesPreview, ['IssuesPreview']);
  FMarks.Bind(FIssuesPreviewComments, ['IssuesPreviewComments']);
  FMarks.Bind(FIssuesCodeLinks, ['IssuesCodeLinks']);
  FMarks.Bind(FIssuesBlameLinks, ['IssuesBlameLinks']);
  FMarks.Bind(FIssuesBlameMaxRevisions, ['IssuesBlameMaxRevisions']);
  FMarks.Bind(FIssuesPreviewChecklists, ['IssuesPreviewChecklists']);
  FMarks.Bind(FIssuesChecklistStatus, ['IssuesChecklistStatus']);
  FMarks.Bind(FIssuesConnections, ['IssuesConnections']);
  FMarks.Bind(FIssuesProjects, ['IssuesProjects']);
  FMarks.Bind(FIssuesQueries, ['IssuesQueries']);
  FMarks.Bind(FIssuesQueryPicker, ['IssuesQueryPicker']);
  FMarks.Bind(FIssuesCreate, ['IssuesCreate']);
  FMarks.Bind(FIssuesCreateIncludeCode, ['IssuesCreateIncludeCode']);
  FMarks.Bind(FVcsProvider, ['VcsProvider']);
  FMarks.Bind(FVcsProjectList, ['VcsProjects']);
  FMarks.Bind(FVcsPaths[TAtlasVcsKind.Git], ['VcsGitPath']);
  FMarks.Bind(FVcsPaths[TAtlasVcsKind.Svn], ['VcsSvnPath']);
  FMarks.Bind(FVcsTimeout, ['VcsTimeoutSeconds']);
  FMarks.Bind(FVcsBranchConfirm, ['VcsBranchConfirm']);
  FMarks.Bind(FVcsBranchSvnLocation, ['VcsBranchSvnLocation']);
  FMarks.Bind(FVcsBranchSvnSource, ['VcsBranchSvnSource']);
  FMarks.Bind(FVcsBranchSvnAfter, ['VcsBranchSvnAfter']);
  FMarks.Bind(FVcsBranchSvnFolder, ['VcsBranchSvnCheckoutFolder']);
  FMarks.Bind(FVcsBranchSvnMessage, ['VcsBranchSvnMessage']);
  FMarks.Bind(FVcsExternalsOnBranch, ['VcsExternalsOnBranch']);
  FMarks.Bind(FVcsExternalsSuggest, ['VcsExternalsSuggestBranch']);
  FMarks.Bind(FVcsExternalsRules, ['VcsExternalsRules']);
  FMarks.Bind(FVcsExternalsShow, ['VcsExternalsShow']);
  FMarks.Bind(FVcsExternalsUpdate, ['VcsExternalsUpdate']);
  FMarks.Bind(FVcsBranchGitBase, ['VcsBranchGitBase']);
  FMarks.Bind(FVcsBranchGitPush, ['VcsBranchGitPush']);
  FMarks.Bind(FVcsBranchGitUncommitted, ['VcsBranchGitUncommitted']);
  FMarks.Bind(FVcsBranchGitWorktree, ['VcsBranchGitWorktree']);
  FMarks.Bind(FVcsBranchGitWorktreeFolder, ['VcsBranchGitWorktreeFolder']);
  FMarks.Bind(FIssuesSyncState, ['IssuesSyncState']);
  FMarks.Bind(FIssuesStateField, ['IssuesStateField']);
  FMarks.Bind(FIssuesAssigneeField, ['IssuesAssigneeField']);
  FMarks.Bind(FIssuesStartState, ['IssuesStartState']);
  FMarks.Bind(FIssuesAssignOnStart, ['IssuesAssignOnStart']);
  FMarks.Bind(FIssuesStartComment, ['IssuesStartComment']);
  FMarks.Bind(FIssuesEndStates, ['IssuesEndStates']);
  FMarks.Bind(FIssuesEndComment, ['IssuesEndComment']);
  FMarks.Bind(FIssuesTimeTracking, ['IssuesTimeTracking']);
  FMarks.Bind(FIssuesIdleMinutes, ['IssuesIdleMinutes']);
  FMarks.Bind(FIssuesTimeRounding, ['IssuesTimeRounding']);
  FMarks.Bind(FOpenBuild, ['BuildOnOpen', 'BuildOnOpenKind']);
  FMarks.Bind(FOpenBuildScope, ['BuildOnOpenScope']);
  FMarks.Bind(FOpenBuildDelay, ['BuildOnOpenDelayMs']);
  FMarks.Bind(FOpenBuildExclude, ['BuildOnOpenExclude']);
  FMarks.Bind(FTasksEnabled, ['TasksEnabled']);
  FMarks.Bind(FTasksProblemsFromOutput, ['TasksProblemsFromOutput']);
  FMarks.Bind(FTasksBeforeBuild, ['TasksBeforeBuild']);
  FMarks.Bind(FTasksSaveBeforeRun, ['TasksSaveBeforeRun']);
  FMarks.Bind(FTasksRunChecksParallel, ['TasksRunChecksParallel']);
  FMarks.Bind(FTasksOnlyFindings, ['TasksOnlyFindings']);
  FMarks.Bind(FReleaseGuard, ['ReleaseGuard']);
  FMarks.Bind(FBuildGate, ['BuildGate']);
  FMarks.Bind(FReleaseConfigs, ['ReleaseConfigs']);
  FMarks.Bind(FSettingsExportImport, ['SettingsExportImport']);
  FMarks.Bind(FSettingsMarkModified, ['SettingsMarkModified']);
  FMarks.Bind(FSettingsBackupBeforeImport, ['SettingsBackupBeforeImport']);
  FMarks.Bind(FSettingsExportSecrets, ['SettingsExportSecrets']);
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    FMarks.Bind(FReleaseCheckBoxes[Check], ['ReleaseChecks'], False);
    FMarks.Bind(FReleaseCheckChoices[Check], ['ReleaseChecks'], False);
  end;
  for Series := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
    FMarks.Bind(FWelcomeTrendsSeries[Series], ['WelcomePageTrendsSeries'], False);
  for mAction := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
    FMarks.Bind(FWelcomeQuickActionsItems[mAction], ['WelcomePageQuickActionsItems'], False);
end;

destructor TAtlasSettingsPage.Destroy;
begin
  FreeAndNil(FGroups);
  FreeAndNil(FCatalog);
  FreeAndNil(FAttached);
  FreeAndNil(FOwnOff);
  FreeAndNil(FLockedControls);
  inherited;
end;

function TAtlasSettingsPage.Catalog: TAtlasSettingsCatalog;
begin
  if FCatalog = nil then
    FCatalog := TAtlasSettingsCatalog.CreateDefault;
  Result := FCatalog;
end;

function TAtlasSettingsPage.CurrentSettings: TAtlasPluginSettings;
begin
  Result := FWidths;
  SaveTo(Result);
end;

procedure TAtlasSettingsPage.RefreshMarks;
var
  Modified: TArray<string>;
begin
  FTransferBar.Visible := FSettingsExportImport.Checked;
  Modified := nil;
  if FSettingsMarkModified.Checked then
    Modified := TAtlasSettingsTransfer.ModifiedNames(Catalog, CurrentSettings);
  FMarks.Show(Modified, FSettingsMarkModified.Checked);
  FExperimentalBanner.Visible := FMarks.HasExperimental and not FExperimentalEnabled.Checked;
  UpdateLocks;
  // Geänderte Werte ändern sich mit jeder Eingabe; der Filter folgt, auch im Baum.
  if FMarks.Filter = sfModified then
  begin
    FMarks.ApplyFilter(sfModified);
    if FTree.HandleAllocated then
      FillTree;
  end;
end;

procedure TAtlasSettingsPage.MarksChanged(Sender: TObject);
begin
  RefreshMarks;
end;

procedure TAtlasSettingsPage.ResetNames(const ANames: TArray<string>);
begin
  if Length(ANames) = 0 then
    Exit;
  LoadFrom(TAtlasSettingsTransfer.ResetNames(Catalog, CurrentSettings, ANames));
end;

procedure TAtlasSettingsPage.ResetPage;
var
  Current, Index: Integer;
  Names: TArray<string>;
begin
  // Ohne Fenster hängen die Reiter noch nicht am PageControl.
  Current := ActiveNode;
  if Current < 0 then
    Exit;
  // Unterpunkt: nur seine Einstellungen; Hauptknoten: der ganze Bereich mit allen Unterpunkten (#890).
  if FNodePages[Current].Node <> '' then
    Names := FMarks.NamesIn(FNodePages[Current].Box)
  else
  begin
    Names := nil;
    for Index := 0 to High(FNodePages) do
      if FNodePages[Index].Area = FNodePages[Current].Area then
        Names := Names + FMarks.NamesIn(FNodePages[Index].Box);
  end;
  ResetNames(Names);
end;

procedure TAtlasSettingsPage.ResetPageClick(Sender: TObject);
begin
  ResetPage;
end;

procedure TAtlasSettingsPage.ExportClick(Sender: TObject);
begin
  if Assigned(FOnExportSettings) then
    FOnExportSettings(CurrentSettings);
end;

procedure TAtlasSettingsPage.ImportClick(Sender: TObject);
var
  Imported: TAtlasPluginSettings;
begin
  if Assigned(FOnImportSettings) and FOnImportSettings(CurrentSettings, False, Imported) then
    LoadFrom(Imported);
end;

procedure TAtlasSettingsPage.ProfileClick(Sender: TObject);
var
  Imported: TAtlasPluginSettings;
begin
  if Assigned(FOnImportSettings) and FOnImportSettings(CurrentSettings, True, Imported) then
    LoadFrom(Imported);
end;

procedure TAtlasSettingsPage.ResetAllClick(Sender: TObject);
var
  Reset: TAtlasPluginSettings;
begin
  if Assigned(FOnResetAllSettings) and FOnResetAllSettings(CurrentSettings, Reset) then
    LoadFrom(Reset);
end;

procedure TAtlasSettingsPage.AddSheet(AId: TAtlasTextId);
begin
  FSheet := TTabSheet.Create(Self);
  FSheet.Caption := TAtlasStrings.Text(AId);
  FSheets := FSheets + [FSheet];
  // Rollbar: Lange Reiter passten sonst nicht in die Optionsseite und wurden abgeschnitten.
  FContent := TScrollBox.Create(Self);
  FBoxes := FBoxes + [FContent];
  FContent.Parent := FSheet;
  FContent.Align := alClient;
  FContent.BorderStyle := bsNone;
  FContent.ParentBackground := True;
  FContent.VertScrollBar.Tracking := True;
  FContent.HorzScrollBar.Visible := False;
  FNextTop := 100;
end;

procedure TAtlasSettingsPage.CreateWnd;
var
  Page: TAtlasSettingsNodePage;
begin
  inherited CreateWnd;
  // Je Knoten ein Reiter, in der Reihenfolge des Baums.
  for Page in FNodePages do
    if Page.Sheet.PageControl = nil then
    begin
      Page.Sheet.PageControl := FPages;
      Page.Sheet.TabVisible := False;
    end;
  // Der Baum braucht ein Fenster für seine Knoten (wie die Reiter); zeigt die zuletzt gewählte Seite.
  FillTree;
  // Die Liste der Sicherung braucht ein Fenster; vorher bleibt sie leer.
  RefreshFuse;
  RefreshFavorites;
  RefreshTrackerConnections;
  RefreshVcsProjects;
  // Gewünschte Einstellung (#628) erst mit Fenster zeigen.
  if FPendingReveal <> '' then
    ApplyReveal(FPendingReveal);
end;

// Baum, Rahmen und Sperren (#890).

type
  /// <summary>Art einer Zeile beim Aufteilen eines Bereichs: mit Einstellung, angehängt, Beschriftung, sonst.
  /// </summary>
  TAtlasRowKind = (rkBound, rkAttached, rkLabel, rkOther);

/// <summary>Liegt AControl in AParent (oder ist es selbst)?</summary>
function Inside(AControl, AParent: TControl): Boolean;
var
  Parent: TControl;
begin
  Parent := AControl;
  while (Parent <> nil) and (Parent <> AParent) do
    Parent := Parent.Parent;
  Result := Parent <> nil;
end;

/// <summary>Zeilen von ABox in der Reihenfolge von oben nach unten.</summary>
function SortedRows(ABox: TWinControl): TArray<TControl>;
var
  Index, Position: Integer;
  Control: TControl;
begin
  Result := nil;
  for Index := 0 to ABox.ControlCount - 1 do
  begin
    Control := ABox.Controls[Index];
    Position := Length(Result);
    while (Position > 0) and (Result[Position - 1].Top > Control.Top) do
      Dec(Position);
    Insert(Control, Result, Position);
  end;
end;

/// <summary>Zeile nur mit einer Beschriftung (Überschrift, Hinweis, Beschriftung über einem Textfeld).</summary>
function IsLabelRow(AControl: TControl): Boolean;
begin
  Result := (AControl is TAtlasSettingsRow) and (TWinControl(AControl).ControlCount = 1) and
    (TWinControl(AControl).Controls[0] is TLabel);
end;

procedure AddUnique(var AList: TArray<string>; const AText: string);
var
  Item: string;
begin
  for Item in AList do
    if Item = AText then
      Exit;
  AList := AList + [AText];
end;

function PageIndexOf(ANode: TTreeNode): Integer;
begin
  Result := -1;
  if ANode <> nil then
    Result := Integer(NativeInt(ANode.Data));
end;

procedure TAtlasSettingsPage.Attach(ARow, AAnchor: TControl);
begin
  if (ARow <> nil) and (AAnchor <> nil) then
    FAttached.AddOrSetValue(ARow, AAnchor);
end;

function TAtlasSettingsPage.AddNodePage(AArea: Integer; const ANode: string): Integer;
begin
  if ANode = '' then
    Result := AddNodePageCaption(AArea, ANode, '')
  else
    Result := AddNodePageCaption(AArea, ANode, FGroups.NodeCaption(ANode, TAtlasStrings.Language = TAtlasLanguage.English));
end;

function TAtlasSettingsPage.AddNodePageCaption(AArea: Integer; const ANode, ACaption: string): Integer;
var
  Page: TAtlasSettingsNodePage;
  Index: Integer;
begin
  for Index := 0 to High(FNodePages) do
    if (FNodePages[Index].Area = AArea) and SameText(FNodePages[Index].Node, ANode) then
      Exit(Index);
  Page := Default(TAtlasSettingsNodePage);
  Page.Area := AArea;
  Page.Node := ANode;
  if ANode = '' then
  begin
    Page.Sheet := FSheets[AArea];
    Page.Box := FBoxes[AArea];
    Page.Caption := FSheets[AArea].Caption;
  end
  else
  begin
    Page.Caption := ACaption;
    Page.Sheet := TTabSheet.Create(Self);
    Page.Sheet.Caption := Page.Caption;
    Page.Box := TScrollBox.Create(Self);
    Page.Box.Parent := Page.Sheet;
    Page.Box.Align := alClient;
    Page.Box.BorderStyle := bsNone;
    Page.Box.ParentBackground := True;
    Page.Box.VertScrollBar.Tracking := True;
    Page.Box.HorzScrollBar.Visible := False;
  end;
  // Hinweis auf eine Sperre durch einen Hauptschalter auf einer anderen Seite, immer ganz oben.
  Page.Banner := TLabel.Create(Self);
  Page.Banner.Parent := Page.Box;
  Page.Banner.Align := alTop;
  Page.Banner.AlignWithMargins := True;
  Page.Banner.Top := 0;
  Page.Banner.WordWrap := True;
  Page.Banner.ShowAccelChar := False;
  Page.Banner.Font.Style := [fsItalic];
  Page.Banner.Visible := False;
  FMarks.Pin(Page.Banner);
  FNodePages := FNodePages + [Page];
  Result := High(FNodePages);
end;

// Prüfregeln (#909).

procedure TAtlasSettingsPage.AddRulesLinks;
var
  Row: TWinControl;

  function AddLink(const ACaption: string; ALeft: Integer; AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := Row;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, 1, 210, 25);
    Result.OnClick := AClick;
  end;

begin
  // Die Regeln stehen in atlas.json des Projekts und in settings.json („Weitere globale Einstellungen“), mit
  // einem Knoten je Gruppe; hier nur der Weg dorthin.
  AddWrappedLabel(34, TAtlasStrings.Text(TAtlasTextId.RulesGlobalNote));
  Row := AddPanel(28);
  FRulesProject := AddLink(TAtlasStrings.Text(TAtlasTextId.RulesProjectButton), 0, RulesProjectClick);
  FRulesGlobal := AddLink(TAtlasStrings.Text(TAtlasTextId.RulesGlobalButton), 216, RulesGlobalClick);
end;

procedure TAtlasSettingsPage.AddRulePages;
var
  Page: Integer;
  Box: TScrollBox;
  Row: TWinControl;
  mText: TLabel;

  function AddRow(ATop: Integer): TWinControl;
  begin
    Result := TAtlasSettingsRow.Create(Self);
    Result.Parent := Box;
    Result.Align := alTop;
    Result.AlignWithMargins := True;
    Result.Height := 28;
    Result.Top := ATop;
  end;

  function AddButton(AParent: TWinControl; const ACaption: string; ALeft: Integer;
    AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := AParent;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, 1, 210, 25);
    Result.OnClick := AClick;
  end;

begin
  // „Profile und Baseline“: Profile gelten je Projekt (atlas.json), die Baseline je Projekt.
  Page := AddNodePageCaption(FRulesArea, 'rules.profiles', TAtlasStrings.Text(TAtlasTextId.RulesProfilesNode));
  Box := FNodePages[Page].Box;
  mText := TLabel.Create(Self);
  mText.Parent := Box;
  mText.Align := alTop;
  mText.AlignWithMargins := True;
  mText.WordWrap := True;
  mText.ShowAccelChar := False;
  mText.Caption := TAtlasStrings.Text(TAtlasTextId.RulesProfilesText);
  mText.Top := 1000;
  mText := TLabel.Create(Self);
  mText.Parent := Box;
  mText.Align := alTop;
  mText.AlignWithMargins := True;
  mText.ShowAccelChar := False;
  mText.Font.Style := [fsBold];
  mText.Caption := TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineTitle);
  mText.Top := 3000;
  FBaselineInfo := TLabel.Create(Self);
  FBaselineInfo.Parent := Box;
  FBaselineInfo.Align := alTop;
  FBaselineInfo.AlignWithMargins := True;
  FBaselineInfo.WordWrap := True;
  FBaselineInfo.ShowAccelChar := False;
  FBaselineInfo.Caption := TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineNone);
  FBaselineInfo.Top := 4000;
  Row := AddRow(5000);
  FBaselineUpdateButton := AddButton(Row, TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineUpdate), 0,
    BaselineUpdateClick);
  FBaselineDelete := AddButton(Row, TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineDelete), 216,
    BaselineDeleteClick);
end;

procedure TAtlasSettingsPage.SetOnBaselineInfo(const AValue: TFunc<string>);
begin
  FOnBaselineInfo := AValue;
  if Assigned(FOnBaselineInfo) and (FBaselineInfo <> nil) then
    FBaselineInfo.Caption := FOnBaselineInfo();
end;

procedure TAtlasSettingsPage.RulesProjectClick(Sender: TObject);
begin
  if Assigned(FOnRulesProject) then
    FOnRulesProject();
end;

procedure TAtlasSettingsPage.RulesGlobalClick(Sender: TObject);
begin
  if Assigned(FOnRulesGlobal) then
    FOnRulesGlobal();
end;

procedure TAtlasSettingsPage.BaselineUpdateClick(Sender: TObject);
begin
  if Assigned(FOnBaselineUpdate) then
    FBaselineInfo.Caption := FOnBaselineUpdate();
end;

procedure TAtlasSettingsPage.BaselineDeleteClick(Sender: TObject);
begin
  if Assigned(FOnBaselineDelete) and ConfirmLayout(TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineDeleteConfirm),
    True) then
    FBaselineInfo.Caption := FOnBaselineDelete();
end;

procedure TAtlasSettingsPage.Place(AControl: TControl; AHolder: TWinControl);
begin
  if AHolder is TAtlasSettingsGroup then
    TAtlasSettingsGroup(AHolder).AddRow(AControl)
  else
  begin
    AControl.Parent := AHolder;
    AControl.Align := alTop;
    AControl.AlignWithMargins := True;
    // alTop ordnet nach Top: jede Zeile unter die vorige.
    AControl.Top := FPlaceTop;
    Inc(FPlaceTop, 100);
  end;
end;

procedure TAtlasSettingsPage.BuildNodes;
var
  Area: Integer;
  Frame: TAtlasSettingsGroup;
begin
  FGroups := TAtlasSettingsGroups.Create(Catalog);
  for Area := 0 to High(FSheets) do
    BuildArea(Area);
  AddRulePages;
  for Frame in FFrames do
    if not (Frame.Parent is TAtlasSettingsGroup) then
      Frame.AdjustHeight;
  for Area := 0 to High(FSheets) do
    AddOverview(Area);
  UpdateLocks;
end;

procedure TAtlasSettingsPage.BuildArea(AArea: Integer);
var
  Rows: TArray<TControl>;
  Kinds: TArray<TAtlasRowKind>;
  Names: TArray<string>;
  RowPages: TArray<Integer>;
  Holders: TArray<TWinControl>;
  Frames: TArray<TAtlasSettingsGroup>;
  Resolved: TArray<Boolean>;
  Main, Index, Other, Page: Integer;
  Frame: TAtlasSettingsGroup;

  // Erster Name der Zeile, den der Katalog kennt; '' ohne Einstellung.
  function KnownName(AControl: TControl): string;
  var
    Candidate: string;
  begin
    Result := '';
    for Candidate in FMarks.NamesWithin(AControl) do
      if FGroups.Contains(Candidate) then
        Exit(Candidate);
  end;

  // Hängt eine Zeile an einem Element in AControl (Liste und Knöpfe einer Funktion)?
  function HasAttached(AControl: TControl): Boolean;
  var
    Item: TPair<TControl, TControl>;
  begin
    for Item in FAttached do
      if Inside(Item.Value, AControl) then
        Exit(True);
    Result := False;
  end;

  function RowOfAnchor(AAnchor: TControl): Integer;
  var
    Candidate: Integer;
  begin
    for Candidate := 0 to High(Rows) do
      if Inside(AAnchor, Rows[Candidate]) then
        Exit(Candidate);
    Result := -1;
  end;

  // Rahmen des Hauptschalters AName, wenn er auf der Seite APage steht; sonst nil.
  function FrameFor(const AName: string; APage: Integer): TAtlasSettingsGroup;
  var
    Candidate: Integer;
  begin
    Result := nil;
    if AName = '' then
      Exit;
    for Candidate := 0 to High(Rows) do
      if (Frames[Candidate] <> nil) and (RowPages[Candidate] = APage) and SameText(Names[Candidate], AName) then
        Exit(Frames[Candidate]);
  end;

begin
  FPlaceTop := 1000;
  Rows := SortedRows(FBoxes[AArea]);
  Main := AddNodePage(AArea, '');
  SetLength(Kinds, Length(Rows));
  SetLength(Names, Length(Rows));
  SetLength(RowPages, Length(Rows));
  SetLength(Holders, Length(Rows));
  SetLength(Frames, Length(Rows));
  SetLength(Resolved, Length(Rows));
  for Index := 0 to High(Rows) do
  begin
    Names[Index] := KnownName(Rows[Index]);
    RowPages[Index] := Main;
    Holders[Index] := FNodePages[Main].Box;
    Frames[Index] := nil;
    Resolved[Index] := False;
    if Names[Index] <> '' then
      Kinds[Index] := rkBound
    else if FAttached.ContainsKey(Rows[Index]) then
      Kinds[Index] := rkAttached
    else if IsLabelRow(Rows[Index]) then
      Kinds[Index] := rkLabel
    else
      Kinds[Index] := rkOther;
  end;
  // Unterpunkt jeder Einstellung; Hauptschalter (auch Kontrollkästchen mit angehängter Liste) bekommen einen Rahmen.
  for Index := 0 to High(Rows) do
    if Kinds[Index] = rkBound then
    begin
      RowPages[Index] := AddNodePage(AArea, FGroups.NodeOf(Names[Index]));
      if FGroups.IsMaster(Names[Index]) or ((Rows[Index] is TCheckBox) and HasAttached(Rows[Index])) then
      begin
        Frames[Index] := TAtlasSettingsGroup.Create(Self);
        FFrames := FFrames + [Frames[Index]];
      end;
    end;
  // Behälter: der Rahmen des Hauptschalters auf derselben Seite, sonst die Seite selbst.
  for Index := 0 to High(Rows) do
    if Kinds[Index] = rkBound then
    begin
      Holders[Index] := FNodePages[RowPages[Index]].Box;
      Frame := FrameFor(FGroups.ParentOf(Names[Index]), RowPages[Index]);
      if Frame <> nil then
        Holders[Index] := Frame;
      Resolved[Index] := True;
    end;
  // Zeilen ohne eigene Einstellung, die zu einer gehören (Liste, Knöpfe): in deren Rahmen.
  for Index := 0 to High(Rows) do
    if Kinds[Index] = rkAttached then
    begin
      Other := RowOfAnchor(FAttached[Rows[Index]]);
      if (Other < 0) or not Resolved[Other] then
        Continue;
      RowPages[Index] := RowPages[Other];
      Holders[Index] := Holders[Other];
      if Frames[Other] <> nil then
        Holders[Index] := Frames[Other];
      Resolved[Index] := True;
    end;
  // Übrige Zeilen (Serverpfad, Knöpfe des Bereichs): oben auf der Seite der Zeile davor.
  Page := Main;
  for Index := 0 to High(Rows) do
    if Resolved[Index] then
      Page := RowPages[Index]
    else if Kinds[Index] <> rkLabel then
    begin
      RowPages[Index] := Page;
      Holders[Index] := FNodePages[Page].Box;
      Resolved[Index] := True;
    end;
  // Überschriften und Beschriftungen gehören zur Zeile darunter, am Ende des Bereichs zur Zeile darüber.
  for Index := High(Rows) downto 0 do
    if not Resolved[Index] and (Index < High(Rows)) and Resolved[Index + 1] then
    begin
      RowPages[Index] := RowPages[Index + 1];
      Holders[Index] := Holders[Index + 1];
      Resolved[Index] := True;
    end;
  for Index := 1 to High(Rows) do
    if not Resolved[Index] then
    begin
      RowPages[Index] := RowPages[Index - 1];
      Holders[Index] := Holders[Index - 1];
      Resolved[Index] := True;
    end;
  for Index := 0 to High(Rows) do
    if Frames[Index] <> nil then
    begin
      Place(Frames[Index], Holders[Index]);
      Frames[Index].SetMaster(Rows[Index], Names[Index]);
      // Rahmen, Hauptschalter und Grund der Sperre bleiben beim Filtern stehen.
      FMarks.Pin(Frames[Index]);
      FMarks.Pin(Rows[Index]);
      FMarks.Pin(Frames[Index].Reason);
    end
    else
      Place(Rows[Index], Holders[Index]);
end;

procedure TAtlasSettingsPage.AddOverview(AArea: Integer);
var
  Overview, Frame: TAtlasSettingsGroup;
  mCaption, Details: TLabel;
  Row: TWinControl;
  Mirror: TCheckBox;
  Main, Index, Child: Integer;
  Box: TScrollBox;
begin
  // Hauptknoten: je Hauptschalter der Unterpunkte eine Zeile mit Spiegel und „Details“.
  Main := AddNodePage(AArea, '');
  Overview := nil;
  for Index := 0 to High(FNodePages) do
  begin
    if (FNodePages[Index].Area <> AArea) or (FNodePages[Index].Node = '') then
      Continue;
    Box := FNodePages[Index].Box;
    for Child := 0 to Box.ControlCount - 1 do
    begin
      if not (Box.Controls[Child] is TAtlasSettingsGroup) then
        Continue;
      Frame := TAtlasSettingsGroup(Box.Controls[Child]);
      if Frame.Master = nil then
        Continue;
      if Overview = nil then
      begin
        Overview := TAtlasSettingsGroup.Create(Self);
        FPlaceTop := 100000;
        Place(Overview, FNodePages[Main].Box);
        mCaption := TLabel.Create(Self);
        mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsOverviewTitle);
        mCaption.Font.Style := [fsBold];
        Overview.SetMaster(mCaption, '');
        FOverviews := FOverviews + [Overview];
        FMarks.Pin(Overview);
      end;
      Row := TAtlasSettingsRow.Create(Self);
      Row.Height := 24;
      Overview.AddRow(Row);
      Details := TLabel.Create(Self);
      Details.Parent := Row;
      Details.Align := alRight;
      Details.AlignWithMargins := True;
      Details.Layout := tlCenter;
      Details.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsOverviewDetails);
      Details.Font.Style := [fsUnderline];
      Details.Font.Color := clHotLight;
      Details.Cursor := crHandPoint;
      Details.Tag := Index;
      Details.OnClick := DetailsClick;
      if Frame.Master is TCheckBox then
      begin
        Mirror := TCheckBox.Create(Self);
        Mirror.Parent := Row;
        Mirror.Align := alClient;
        Mirror.Caption := FMarks.TextOfName(Frame.MasterName);
        Mirror.Tag := Length(FMirrors);
        Mirror.OnClick := MirrorClick;
        FMirrors := FMirrors + [Mirror];
        FMirrored := FMirrored + [TCheckBox(Frame.Master)];
      end
      else
      begin
        mCaption := TLabel.Create(Self);
        mCaption.Parent := Row;
        mCaption.Align := alClient;
        mCaption.Layout := tlCenter;
        mCaption.Caption := FMarks.TextOfName(Frame.MasterName);
      end;
    end;
  end;
  if Overview <> nil then
    Overview.AdjustHeight;
end;

procedure TAtlasSettingsPage.MirrorClick(Sender: TObject);
var
  Index: Integer;
begin
  if FSyncing or not (Sender is TCheckBox) then
    Exit;
  Index := TCheckBox(Sender).Tag;
  if (Index >= 0) and (Index <= High(FMirrored)) then
    FMirrored[Index].Checked := TCheckBox(Sender).Checked;
end;

procedure TAtlasSettingsPage.DetailsClick(Sender: TObject);
begin
  if Sender is TControl then
    SelectPage(TControl(Sender).Tag);
end;

function TAtlasSettingsPage.IsOverview(AFrame: TAtlasSettingsGroup): Boolean;
var
  Overview: TAtlasSettingsGroup;
begin
  for Overview in FOverviews do
    if Overview = AFrame then
      Exit(True);
  Result := False;
end;

function TAtlasSettingsPage.PageOf(AControl: TControl): Integer;
var
  mParent: TControl;
  Index: Integer;
begin
  Result := -1;
  mParent := AControl;
  while (mParent <> nil) and not (mParent is TTabSheet) do
    mParent := mParent.Parent;
  if mParent = nil then
    Exit;
  for Index := 0 to High(FNodePages) do
    if FNodePages[Index].Sheet = mParent then
      Exit(Index);
end;

function TAtlasSettingsPage.ActiveNode: Integer;
var
  Index: Integer;
begin
  Result := -1;
  if FPages.ActivePage = nil then
    Exit;
  for Index := 0 to High(FNodePages) do
    if FNodePages[Index].Sheet = FPages.ActivePage then
      Exit(Index);
end;

procedure TAtlasSettingsPage.SelectPage(AIndex: Integer);
var
  Index: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FNodePages)) then
    Exit;
  FPages.ActivePage := FNodePages[AIndex].Sheet;
  SheetShown(FNodePages[AIndex].Sheet);
  if not FTree.HandleAllocated then
    Exit;
  for Index := 0 to FTree.Items.Count - 1 do
    if PageIndexOf(FTree.Items[Index]) = AIndex then
    begin
      FTree.Selected := FTree.Items[Index];
      Break;
    end;
end;

function TAtlasSettingsPage.PageShown(AIndex: Integer): Boolean;
var
  Index: Integer;
begin
  // Der Filter blendet Unterpunkte ohne Treffer aus; ein Bereich bleibt, solange einer seiner Punkte trifft.
  if (FMarks.Filter = sfAll) or FMarks.HasMatch(FNodePages[AIndex].Box) then
    Exit(True);
  if FNodePages[AIndex].Node = '' then
    for Index := 0 to High(FNodePages) do
      if (Index <> AIndex) and (FNodePages[Index].Area = FNodePages[AIndex].Area) and
        FMarks.HasMatch(FNodePages[Index].Box) then
        Exit(True);
  Result := False;
end;

procedure TAtlasSettingsPage.FillTree;
var
  Index, Area, Selected: Integer;
  AreaNodes: TArray<TTreeNode>;
  Node, Wanted: TTreeNode;
begin
  SetLength(AreaNodes, Length(FSheets));
  Wanted := nil;
  Selected := ActiveNode;
  if (Selected < 0) and FStateKnown then
    Selected := FLastPage;
  FFillingTree := True;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    for Index := 0 to High(FNodePages) do
    begin
      if not PageShown(Index) then
        Continue;
      Area := FNodePages[Index].Area;
      if FNodePages[Index].Node = '' then
      begin
        Node := FTree.Items.AddObject(nil, FNodePages[Index].Caption, Pointer(NativeInt(Index)));
        AreaNodes[Area] := Node;
      end
      else
        Node := FTree.Items.AddChildObject(AreaNodes[Area], FNodePages[Index].Caption, Pointer(NativeInt(Index)));
      if Index = Selected then
        Wanted := Node;
    end;
    if (Wanted = nil) and (FTree.Items.Count > 0) then
      Wanted := FTree.Items[0];
    // Aufgeklappt wie beim letzten Mal; beim ersten Öffnen der Bereich der gewählten Seite.
    for Index := 0 to FTree.Items.Count - 1 do
    begin
      Node := FTree.Items[Index];
      if (Node.Level = 0) and Node.HasChildren then
      begin
        Area := FNodePages[PageIndexOf(Node)].Area;
        Node.Expanded := FStateKnown and (Area <= High(Byte)) and (Byte(Area) in FExpandedAreas);
      end;
    end;
    if Wanted <> nil then
    begin
      if Wanted.Parent <> nil then
        Wanted.Parent.Expanded := True
      else if not FStateKnown and Wanted.HasChildren then
        Wanted.Expanded := True;
      FTree.Selected := Wanted;
      FPages.ActivePage := FNodePages[PageIndexOf(Wanted)].Sheet;
    end;
  finally
    FTree.Items.EndUpdate;
    FFillingTree := False;
  end;
  RefreshTree;
end;

procedure TAtlasSettingsPage.RefreshTree;
var
  Index, Page: Integer;
  Node: TTreeNode;
  mText: string;
begin
  if not FTree.HandleAllocated then
    Exit;
  for Index := 0 to FTree.Items.Count - 1 do
  begin
    Node := FTree.Items[Index];
    Page := PageIndexOf(Node);
    if (Page < 0) or (Page > High(FNodePages)) then
      Continue;
    // Punkt wie an den Einstellungen: Auf dieser Seite ist etwas geändert.
    mText := FNodePages[Page].Caption;
    if FMarks.HasMarked(FNodePages[Page].Box) then
      mText := TAtlasSettingsMarks.Dot + mText;
    if Node.Text <> mText then
      Node.Text := mText;
  end;
  FTree.Invalidate;
end;

procedure TAtlasSettingsPage.TreeChange(Sender: TObject; Node: TTreeNode);
var
  Index: Integer;
begin
  Index := PageIndexOf(Node);
  if (Index < 0) or (Index > High(FNodePages)) or (csDestroying in ComponentState) then
    Exit;
  FPages.ActivePage := FNodePages[Index].Sheet;
  SheetShown(FNodePages[Index].Sheet);
  // Beim Neuaufbau des Baums wählt er selbst; gemerkt wird nur die Wahl des Nutzers.
  if FFillingTree then
    Exit;
  FLastPage := Index;
  FStateKnown := True;
end;

procedure TAtlasSettingsPage.TreeExpanded(Sender: TObject; Node: TTreeNode);
var
  Index, Area: Integer;
begin
  Index := PageIndexOf(Node);
  if FFillingTree or (csDestroying in ComponentState) or (Index < 0) or (Index > High(FNodePages)) then
    Exit;
  Area := FNodePages[Index].Area;
  if (Area < 0) or (Area > High(Byte)) then
    Exit;
  if Node.Expanded then
    Include(FExpandedAreas, Byte(Area))
  else
    Exclude(FExpandedAreas, Byte(Area));
  FStateKnown := True;
end;

procedure TAtlasSettingsPage.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
  var DefaultDraw: Boolean);
var
  Index: Integer;
begin
  DefaultDraw := True;
  // Abgeschaltete oder gesperrte Unterpunkte grau.
  Index := PageIndexOf(Node);
  if (Index >= 0) and (Index <= High(FNodePages)) and FNodePages[Index].Gray and not (cdsSelected in State) then
    Sender.Canvas.Font.Color := clGrayText;
end;

function TAtlasSettingsPage.IsOn(const AName: string): Boolean;
var
  Control: TControl;
begin
  // Kontrollkästchen: angehakt; Auswahl (etwa „Beim Öffnen bauen“): ein Eintrag außer dem ersten („nicht …“).
  Control := FMarks.ControlOfName(AName);
  if Control is TCheckBox then
    Result := TCheckBox(Control).Checked
  else if Control is TAtlasChoiceBox then
    Result := TAtlasChoiceBox(Control).Choice > 0
  else
    Result := True;
end;

function TAtlasSettingsPage.LockOfName(const AName: string): TAtlasSettingsLock;
begin
  Result := FGroups.LockOf(AName, IsOn, FExperimentalEnabled.Checked);
end;

function TAtlasSettingsPage.LockText(const ALock: TAtlasSettingsLock): string;
var
  Page, Entry: Integer;
  Where, mCaption: string;
begin
  Result := '';
  case ALock.Reason of
    lrExperimental:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsLockedExperimental);
    lrMasterOff:
      begin
        mCaption := FMarks.TextOfName(ALock.Master);
        if mCaption = '' then
          mCaption := FGroups.KeyOf(ALock.Master);
        Where := '';
        Page := PageOf(FMarks.ControlOfName(ALock.Master));
        if Page >= 0 then
        begin
          Where := FSheets[FNodePages[Page].Area].Caption;
          if FNodePages[Page].Node <> '' then
            Where := Where + ' › ' + FNodePages[Page].Caption;
        end
        else
        begin
          Entry := Catalog.IndexOfName(ALock.Master);
          if Entry >= 0 then
            Where := Catalog.Entries[Entry].Page;
        end;
        Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsLockedMaster, [mCaption, Where]);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TAtlasSettingsPage.SetLocked(AControl: TControl; ALocked: Boolean);
var
  Index: Integer;
begin
  if AControl = nil then
    Exit;
  if not ALocked then
    FLockedControls.Remove(AControl)
  else if not FLockedControls.Contains(AControl) then
    FLockedControls.Add(AControl);
  AControl.Enabled := not ALocked and not FOwnOff.Contains(AControl);
  if (AControl is TWinControl) and not (AControl is TAtlasSettingsGroup) then
    for Index := 0 to TWinControl(AControl).ControlCount - 1 do
      SetLocked(TWinControl(AControl).Controls[Index], ALocked);
end;

procedure TAtlasSettingsPage.Allow(AControl: TControl; AValue: Boolean);
begin
  // Eigene Logik der Seite (Liste leer, Server fehlt); eine Sperre durch den Hauptschalter bleibt bestehen.
  if AValue then
    FOwnOff.Remove(AControl)
  else if not FOwnOff.Contains(AControl) then
    FOwnOff.Add(AControl);
  AControl.Enabled := AValue and not FLockedControls.Contains(AControl);
end;

procedure TAtlasSettingsPage.ApplyLocks(AContainer: TWinControl; ALocked: Boolean; var AOutside: TArray<string>);
var
  Index: Integer;
  Control, Anchor: TControl;
  Frame: TAtlasSettingsGroup;
  Lock: TAtlasSettingsLock;
  Locked, MasterLocked: Boolean;
  Setting: string;
  Names: TArray<string>;
begin
  for Index := 0 to AContainer.ControlCount - 1 do
  begin
    Control := AContainer.Controls[Index];
    if (AContainer is TAtlasSettingsGroup) and ((Control = TAtlasSettingsGroup(AContainer).Master) or
      (Control = TAtlasSettingsGroup(AContainer).Reason)) then
      Continue;
    if Control is TAtlasSettingsGroup then
    begin
      Frame := TAtlasSettingsGroup(Control);
      if IsOverview(Frame) or (Frame.Master = nil) then
        Continue;
      // Der Hauptschalter selbst: gesperrt durch einen Rahmen darüber, einen Schalter woanders oder experimentell.
      Lock := LockOfName(Frame.MasterName);
      MasterLocked := ALocked or Lock.Locked;
      SetLocked(Frame.Master, MasterLocked);
      if Lock.Locked and not ALocked then
        Frame.ShowReason(LockText(Lock))
      else
        Frame.ShowReason('');
      ApplyLocks(Frame, MasterLocked or not IsOn(Frame.MasterName), AOutside);
      Continue;
    end;
    Locked := ALocked;
    if not Locked then
    begin
      // Zeile ohne Rahmen: ihr Hauptschalter steht auf einer anderen Seite (Grund oben auf der Seite).
      Names := FMarks.NamesWithin(Control);
      if (Length(Names) = 0) and FAttached.TryGetValue(Control, Anchor) then
        Names := FMarks.NamesWithin(Anchor);
      for Setting in Names do
      begin
        Lock := LockOfName(Setting);
        if Lock.Locked then
        begin
          Locked := True;
          if Lock.Reason = lrMasterOff then
            AddUnique(AOutside, LockText(Lock));
        end;
      end;
    end;
    SetLocked(Control, Locked);
  end;
end;

function TAtlasSettingsPage.PageGray(AIndex: Integer): Boolean;
var
  Box: TScrollBox;
  Index: Integer;
  Control: TControl;
  Frame: TAtlasSettingsGroup;
  Any: Boolean;
begin
  // Grau, wenn nichts auf der Seite wirkt: jeder Rahmen aus oder gesperrt, jede übrige Einstellung gesperrt.
  Box := FNodePages[AIndex].Box;
  Any := False;
  for Index := 0 to Box.ControlCount - 1 do
  begin
    Control := Box.Controls[Index];
    if Control is TAtlasSettingsGroup then
    begin
      Frame := TAtlasSettingsGroup(Control);
      if IsOverview(Frame) or (Frame.Master = nil) then
        Continue;
      Any := True;
      if Frame.Master.Enabled and IsOn(Frame.MasterName) then
        Exit(False);
    end
    else if Length(FMarks.NamesWithin(Control)) > 0 then
    begin
      Any := True;
      if Control.Enabled then
        Exit(False);
    end;
  end;
  Result := Any;
end;

procedure TAtlasSettingsPage.UpdateLocks;
var
  Index: Integer;
  Outside: TArray<string>;
begin
  if FGroups = nil then
    Exit;
  for Index := 0 to High(FNodePages) do
  begin
    Outside := nil;
    ApplyLocks(FNodePages[Index].Box, False, Outside);
    FNodePages[Index].Banner.Caption := string.Join(sLineBreak, Outside);
    FNodePages[Index].Banner.Visible := Length(Outside) > 0;
  end;
  // Spiegel in der Übersicht folgen ihrem Hauptschalter.
  FSyncing := True;
  try
    for Index := 0 to High(FMirrors) do
    begin
      FMirrors[Index].Checked := FMirrored[Index].Checked;
      FMirrors[Index].Enabled := FMirrored[Index].Enabled;
    end;
  finally
    FSyncing := False;
  end;
  for Index := 0 to High(FNodePages) do
    FNodePages[Index].Gray := PageGray(Index);
  RefreshTree;
end;

function TAtlasSettingsPage.FrameOf(const AName: string): TAtlasSettingsGroup;
var
  Frame: TAtlasSettingsGroup;
begin
  for Frame in FFrames do
    if SameText(Frame.MasterName, AName) then
      Exit(Frame);
  Result := nil;
end;

function TAtlasSettingsPage.NodeSheet(const ANode: string): TTabSheet;
var
  Page: TAtlasSettingsNodePage;
begin
  for Page in FNodePages do
    if (ANode <> '') and SameText(Page.Node, ANode) then
      Exit(Page.Sheet);
  Result := nil;
end;

function TAtlasSettingsPage.OverviewMirror(const AName: string): TCheckBox;
var
  Frame: TAtlasSettingsGroup;
  Index: Integer;
begin
  Result := nil;
  Frame := FrameOf(AName);
  if Frame = nil then
    Exit;
  for Index := 0 to High(FMirrored) do
    if FMirrored[Index] = Frame.Master then
      Exit(FMirrors[Index]);
end;

function TAtlasSettingsPage.SheetGray(ASheet: TTabSheet): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to High(FNodePages) do
    if FNodePages[Index].Sheet = ASheet then
      Exit(FNodePages[Index].Gray);
  Result := False;
end;

function TAtlasSettingsPage.NodeOfSheet(ASheet: TTabSheet): string;
var
  Page: TAtlasSettingsNodePage;
begin
  for Page in FNodePages do
    if Page.Sheet = ASheet then
      Exit(Page.Node);
  Result := '';
end;

class procedure TAtlasSettingsPage.ForgetTreeState;
begin
  FStateKnown := False;
  FLastPage := 0;
  FExpandedAreas := [];
end;


procedure TAtlasSettingsPage.AddFavoritesSection;
var
  Panel: TWinControl;
begin
  AddTitle(TAtlasTextId.SettingsFavoritesTitle);
  Panel := AddPanel(80);
  FFavoritesList := TListBox.Create(Self);
  FFavoritesList.Parent := Panel;
  FFavoritesList.Align := alClient;
  FFavoritesList.MultiSelect := True;
  Panel := AddPanel(32);
  FFavoritesRemove := TButton.Create(Self);
  FFavoritesRemove.Parent := Panel;
  FFavoritesRemove.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsFavoritesRemove);
  FFavoritesRemove.Left := 0;
  FFavoritesRemove.Top := 3;
  FFavoritesRemove.Width := 150;
  FFavoritesRemove.OnClick := FavoritesRemoveClick;
  FFavoritesRemoveAll := TButton.Create(Self);
  FFavoritesRemoveAll.Parent := Panel;
  FFavoritesRemoveAll.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsFavoritesRemoveAll);
  FFavoritesRemoveAll.Left := 160;
  FFavoritesRemoveAll.Top := 3;
  FFavoritesRemoveAll.Width := 150;
  FFavoritesRemoveAll.OnClick := FavoritesRemoveAllClick;
  Attach(FFavoritesList.Parent, FFavorites);
  Attach(Panel, FFavorites);
end;

procedure TAtlasSettingsPage.SetOnFavorites(const AValue: TFunc<TArray<TAtlasFavorite>>);
begin
  FOnFavorites := AValue;
  RefreshFavorites;
end;

procedure TAtlasSettingsPage.RefreshFavorites;
var
  Favorites: TArray<TAtlasFavorite>;
  Favorite: TAtlasFavorite;
  Any: Boolean;
begin
  // Wie die Liste der Sicherung: ohne Fenster folgt das in CreateWnd.
  if not HandleAllocated then
    Exit;
  Favorites := nil;
  if Assigned(FOnFavorites) then
    Favorites := FOnFavorites();
  FFavoriteKeys := nil;
  Any := Length(Favorites) > 0;
  FFavoritesList.Items.BeginUpdate;
  try
    FFavoritesList.Items.Clear;
    for Favorite in Favorites do
    begin
      FFavoritesList.Items.Add(Favorite.DisplayName);
      FFavoriteKeys := FFavoriteKeys + [Favorite.Key];
    end;
    if not Any then
      FFavoritesList.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsFavoritesNone));
  finally
    FFavoritesList.Items.EndUpdate;
  end;
  Allow(FFavoritesList, Any);
  Allow(FFavoritesRemove, Any and Assigned(FOnRemoveFavorites));
  Allow(FFavoritesRemoveAll, Any and Assigned(FOnRemoveFavorites));
end;

procedure TAtlasSettingsPage.FavoritesRemoveClick(Sender: TObject);
var
  Keys: TArray<string>;
  Index: Integer;
begin
  if not Assigned(FOnRemoveFavorites) then
    Exit;
  Keys := nil;
  for Index := 0 to Min(FFavoritesList.Items.Count, Length(FFavoriteKeys)) - 1 do
    if FFavoritesList.Selected[Index] then
      Keys := Keys + [FFavoriteKeys[Index]];
  if Length(Keys) = 0 then
    Exit;
  FOnRemoveFavorites(Keys);
  RefreshFavorites;
end;

procedure TAtlasSettingsPage.FavoritesRemoveAllClick(Sender: TObject);
begin
  if not Assigned(FOnRemoveFavorites) or (Length(FFavoriteKeys) = 0) then
    Exit;
  FOnRemoveFavorites(Copy(FFavoriteKeys));
  RefreshFavorites;
end;

procedure TAtlasSettingsPage.AddTitle(AId: TAtlasTextId);
var
  Panel: TWinControl;
  mCaption: TLabel;
begin
  Panel := AddPanel(22);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Panel;
  mCaption.Caption := TAtlasStrings.Text(AId);
  mCaption.Font.Style := [fsBold];
  mCaption.Left := 0;
  mCaption.Top := 4;
end;

procedure TAtlasSettingsPage.AddIndexSection;
var
  Panel: TWinControl;
begin
  // Symbolindex (#492): Verwendungen, Speichergrenze, Kennzahlen und Verwaltung.
  AddTitle(TAtlasTextId.SettingsIndexTitle);
  FIndexUsages := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsIndexUsages));
  FMemoryBudget := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsMemoryBudget));
  Panel := AddPanel(66);
  FIndexInfo := TLabel.Create(Self);
  FIndexInfo.Parent := Panel;
  FIndexInfo.Left := 0;
  FIndexInfo.Top := 2;
  FIndexInfo.Font.Color := clGrayText;
  Panel := AddPanel(32);
  FIndexRefresh := TButton.Create(Self);
  FIndexRefresh.Parent := Panel;
  FIndexRefresh.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIndexRefresh);
  FIndexRefresh.Left := 0;
  FIndexRefresh.Top := 3;
  FIndexRefresh.Width := 150;
  FIndexRefresh.OnClick := IndexRefreshClick;
  FIndexRebuild := TButton.Create(Self);
  FIndexRebuild.Parent := Panel;
  FIndexRebuild.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIndexRebuild);
  FIndexRebuild.Left := 160;
  FIndexRebuild.Top := 3;
  FIndexRebuild.Width := 150;
  FIndexRebuild.OnClick := IndexRebuildClick;
  FIndexClear := TButton.Create(Self);
  FIndexClear.Parent := Panel;
  FIndexClear.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIndexClear);
  FIndexClear.Left := 320;
  FIndexClear.Top := 3;
  FIndexClear.Width := 150;
  FIndexClear.OnClick := IndexClearClick;
  // Ohne Server (Ereignisse nicht gesetzt) sind die Befehle aus.
  RefreshIndex;
end;

procedure TAtlasSettingsPage.UpdateIndexButtons;
begin
  Allow(FIndexRefresh, Assigned(FOnIndexMetrics) and not FIndexBusy);
  Allow(FIndexRebuild, Assigned(FOnIndexRebuild) and not FIndexBusy);
  Allow(FIndexClear, Assigned(FOnIndexClear) and not FIndexBusy);
end;

procedure TAtlasSettingsPage.StartIndexCommand(const ACommand: TProc);
begin
  if not Assigned(ACommand) or FIndexBusy then
    Exit;
  FIndexBusy := True;
  FIndexInfo.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIndexAsking);
  UpdateIndexButtons;
  ACommand();
end;

procedure TAtlasSettingsPage.IndexAnswered(const AText: string);
begin
  FIndexBusy := False;
  FIndexInfo.Caption := AText;
  UpdateIndexButtons;
end;

function TAtlasSettingsPage.IndexBusy: Boolean;
begin
  Result := FIndexBusy;
end;

procedure TAtlasSettingsPage.RefreshIndex;
begin
  if Assigned(FOnIndexMetrics) then
    StartIndexCommand(FOnIndexMetrics)
  else if not FIndexBusy then
    FIndexInfo.Caption := '';
  UpdateIndexButtons;
end;

procedure TAtlasSettingsPage.IndexRefreshClick(Sender: TObject);
begin
  RefreshIndex;
end;

procedure TAtlasSettingsPage.IndexRebuildClick(Sender: TObject);
begin
  StartIndexCommand(FOnIndexRebuild);
end;

procedure TAtlasSettingsPage.IndexClearClick(Sender: TObject);
var
  Confirmed: Boolean;
begin
  if not Assigned(FOnIndexClear) then
    Exit;
  if Assigned(FConfirmClear) then
    Confirmed := FConfirmClear()
  else
    Confirmed := MessageDlg(TAtlasStrings.Text(TAtlasTextId.SettingsIndexClearConfirm), mtConfirmation,
      [mbYes, mbNo], 0) = mrYes;
  if Confirmed then
    StartIndexCommand(FOnIndexClear);
end;

procedure TAtlasSettingsPage.AddFuseSection;
var
  Panel: TWinControl;
begin
  AddTitle(TAtlasTextId.SettingsFuseTitle);
  Panel := AddPanel(64);
  FFuseList := TListBox.Create(Self);
  FFuseList.Parent := Panel;
  FFuseList.Align := alClient;
  FFuseList.MultiSelect := True;
  Panel := AddPanel(32);
  FFuseEnableSelected := TButton.Create(Self);
  FFuseEnableSelected.Parent := Panel;
  FFuseEnableSelected.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsFuseEnableSelected);
  FFuseEnableSelected.Left := 0;
  FFuseEnableSelected.Top := 3;
  FFuseEnableSelected.Width := 150;
  FFuseEnableSelected.OnClick := FuseEnableSelectedClick;
  FFuseEnableAll := TButton.Create(Self);
  FFuseEnableAll.Parent := Panel;
  FFuseEnableAll.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsFuseEnableAll);
  FFuseEnableAll.Left := 160;
  FFuseEnableAll.Top := 3;
  FFuseEnableAll.Width := 150;
  FFuseEnableAll.OnClick := FuseEnableAllClick;
end;

procedure TAtlasSettingsPage.RefreshFuse;
var
  Feature: TAtlasFeature;
  mName: string;
  Any: Boolean;
begin
  // Ohne Fenster (IDE erzeugt die Seite vor dem Einhängen) folgt das in CreateWnd.
  if not HandleAllocated then
    Exit;
  FFuseList.Items.BeginUpdate;
  try
    FFuseList.Items.Clear;
    // Objects: Feature + 1; nil bei einer Quelle (Name im Text).
    for Feature in TAtlasGuard.DisabledSet do
      FFuseList.Items.AddObject(TAtlasGuard.FeatureName(Feature), TObject(NativeInt(Ord(Feature) + 1)));
    for mName in TAtlasGuard.DisabledProviders do
      FFuseList.Items.AddObject(mName, nil);
    Any := FFuseList.Items.Count > 0;
    if not Any then
      FFuseList.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsFuseNone));
  finally
    FFuseList.Items.EndUpdate;
  end;
  Allow(FFuseList, Any);
  Allow(FFuseEnableSelected, Any);
  Allow(FFuseEnableAll, Any);
end;

procedure TAtlasSettingsPage.FuseEnableSelectedClick(Sender: TObject);
var
  Index: Integer;
  mTag: NativeInt;
begin
  for Index := 0 to FFuseList.Items.Count - 1 do
    if FFuseList.Selected[Index] then
    begin
      mTag := NativeInt(FFuseList.Items.Objects[Index]);
      if mTag > 0 then
        TAtlasGuard.Enable(TAtlasFeature(mTag - 1))
      else
        TAtlasGuard.EnableProvider(FFuseList.Items[Index]);
    end;
  RefreshFuse;
end;

procedure TAtlasSettingsPage.FuseEnableAllClick(Sender: TObject);
begin
  TAtlasGuard.EnableAll;
  RefreshFuse;
end;

procedure TAtlasSettingsPage.AddSafeSection;
var
  Panel: TWinControl;
  mCaption: TLabel;
begin
  // Abgesicherter Start nach einem Absturz (#722).
  AddTitle(TAtlasTextId.SettingsSafeTitle);
  FSafeAsk := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSafeAsk));
  FSafeAuto := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSafeAuto));
  Panel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Panel;
  mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsSafeKey);
  mCaption.Left := 0;
  mCaption.Top := 5;
  FSafeKey := TAtlasChoiceBox.Create(Self);
  FSafeKey.Parent := Panel;
  FSafeKey.Left := FieldLeft;
  FSafeKey.Top := 1;
  FSafeKey.Width := 120;
  // Reihenfolge wie TAtlasStartupKey ohne None vorn: Umschalt, Strg, keine.
  FSafeKey.SetChoices([TAtlasStrings.Text(TAtlasTextId.SettingsSafeKeyShift),
    TAtlasStrings.Text(TAtlasTextId.SettingsSafeKeyCtrl), TAtlasStrings.Text(TAtlasTextId.SettingsSafeKeyNone)]);
  FSafeTimeout := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSafeTimeout));
  FSafeHistory := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSafeHistory));
end;

procedure TAtlasSettingsPage.AddUnitSearchSection;
begin
  FUnitSearchEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchEnabled));
  FUnitSearchReplace := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchReplace));
  FUnitSearchReplaceUseUnit := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchReplaceUseUnit));
  FUnitSearchReplaceForms := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchReplaceForms));
  FUnitSearchKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchKey));
  FUnitSearchPathStyle := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPathStyle),
    [TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPathRelative),
    TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPathCompact),
    TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPathAbsolute)]);
  FUnitSearchGroupBy := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchGroupBy),
    [TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupProject), TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupFolder),
    TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupNone)]);
  FUnitSearchRememberCollapsed := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchRememberCollapsed));
  FUnitSearchFilters := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchFilters));
  FUnitSearchDefaultScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchDefaultScope),
    [TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginGroup), TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginActive),
    TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginSearchPath),
    TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginLibrary)]);
  FUnitSearchFilterSyntax := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchFilterSyntax));
  FUnitSearchPreview := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPreview));
  FUnitSearchPreviewForm := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPreviewForm));
  FUnitSearchPreviewUsedBy := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPreviewUsedBy));
  FUnitSearchPreviewAutoCollapse := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchPreviewAutoCollapse));
  FUnitSearchMultiSelect := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchMultiSelect));
  FUnitSearchActions := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchActions));
  FUnitSearchAddUses := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchAddUses));
  // Datei und Symbol schnell öffnen (#503).
  AddTitle(TAtlasTextId.QuickOpenTitle);
  FQuickOpen := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickOpen));
  FQuickOpenLibrary := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuickOpenLibrary));
  FQuickOpenKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsQuickOpenKey));
  // Suchleiste im Editor (#878).
  AddTitle(TAtlasTextId.SettingsSearchTitle);
  FSearchReplace := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSearchReplace));
  FSearchMessages := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSearchMessages));
  // Ersetzen, Regex, Verlauf und Bereiche über Dateien (#893).
  FSearchReplaceBar := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSearchReplaceBar));
  FSearchRegex := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSearchRegex));
  FSearchHistory := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSearchHistory));
  FSearchMultiFile := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSearchMultiFile));
end;

procedure TAtlasSettingsPage.AddUndoSection;
begin
  // Atlas-Änderungen über mehrere Dateien zurücknehmen (#721).
  AddTitle(TAtlasTextId.SettingsUndoTitle);
  FUndoEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUndoEnabled));
  FUndoDepth := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsUndoDepth));
  FUndoPersist := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUndoPersist));
  FUndoMaxSize := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsUndoMaxSize));
  // Reihenfolge wie TAtlasUndoConflictMode und TAtlasNewFilesMode.
  FUndoOnConflict := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsUndoOnConflict),
    [TAtlasStrings.Text(TAtlasTextId.SettingsUndoPartial), TAtlasStrings.Text(TAtlasTextId.SettingsUndoAbort)]);
  FUndoNewFiles := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsUndoNewFiles),
    [TAtlasStrings.Text(TAtlasTextId.SettingsUndoRecycle), TAtlasStrings.Text(TAtlasTextId.SettingsUndoDelete),
    TAtlasStrings.Text(TAtlasTextId.SettingsUndoKeep)]);
end;

procedure TAtlasSettingsPage.AddUpdatesSection;
var
  Panel: TWinControl;
begin
  // Version und Update-Prüfung (#495).
  AddTitle(TAtlasTextId.SettingsUpdatesTitle);
  Panel := AddPanel(20);
  FVersion := TLabel.Create(Self);
  FVersion.Parent := Panel;
  FVersion.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsVersion, [TAtlasPluginVersion.Version,
    TAtlasUpdates.IdeVersion]);
  FVersion.Left := 0;
  FVersion.Top := 2;
  FUpdatesCheck := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUpdatesCheck));
end;

procedure TAtlasSettingsPage.AddBugReportSection;
begin
  // Fehlerbericht (#108).
  AddTitle(TAtlasTextId.SettingsBugReportTitle);
  FBugReportAnonymize := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBugReportAnonymize));
end;

function TAtlasSettingsPage.AddChoice(const ACaption: string; const AItems: array of string): TAtlasChoiceBox;
var
  Panel: TWinControl;
  mCaption: TLabel;
begin
  Panel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Panel;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := 5;
  Result := TAtlasChoiceBox.Create(Self);
  Result.Parent := Panel;
  Result.Left := FieldLeft;
  Result.Top := 1;
  Result.Width := 180;
  Result.SetChoices(AItems);
end;

function TAtlasSettingsPage.DebugVisualizerKindCheck(AKind: TAtlasVisualizerKind): TCheckBox;
begin
  Result := FDebugVisualizerKinds[AKind];
end;

function TAtlasSettingsPage.DebugStepFilterKindCheck(AKind: TStepFilterKind): TCheckBox;
begin
  Result := FDebugStepFilterKinds[AKind];
end;

function TAtlasSettingsPage.AddCheck(const ACaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := FContent;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Caption := ACaption;
  // alTop stapelt nach Top: jedes neue Element unter das vorige.
  Result.Top := FNextTop;
  Inc(FNextTop, 100);
end;

function TAtlasSettingsPage.AddPanel(AHeight: Integer): TWinControl;
begin
  // Kein TPanel: Das zeichnet im IDE-Thema einen eigenen Hintergrund (dunkle Streifen im Reiter).
  Result := TAtlasSettingsRow.Create(Self);
  Result.Parent := FContent;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Height := AHeight;
  Result.Top := FNextTop;
  Inc(FNextTop, 100);
end;

procedure TAtlasSettingsPage.AddNotificationSources;
var
  Panel: TWinControl;
  mCaption: TLabel;
  Names: TArray<string>;
  Source: string;
begin
  Panel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Panel;
  mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsNotificationsSources);
  mCaption.Left := 0;
  mCaption.Top := 5;
  Names := nil;
  for Source in TAtlasNotificationSources.Known do
    Names := Names + [TAtlasNotificationsWindow.SourceCaption(Source)];
  FNotificationSource := TAtlasChoiceBox.Create(Self);
  FNotificationSource.Parent := Panel;
  FNotificationSource.Left := FieldLeft;
  FNotificationSource.Top := 1;
  FNotificationSource.Width := 180;
  FNotificationSource.SetChoices(Names);
  FNotificationSource.Choice := 0;
  FNotificationSource.OnChange := NotificationSourceChange;
  // Reihenfolge wie TAtlasNotificationMode: einblenden und sammeln, nur sammeln, aus.
  FNotificationMode := TAtlasChoiceBox.Create(Self);
  FNotificationMode.Parent := Panel;
  FNotificationMode.Left := FieldLeft + 186;
  FNotificationMode.Top := 1;
  FNotificationMode.Width := 170;
  FNotificationMode.SetChoices([TAtlasStrings.Text(TAtlasTextId.NotificationsModeShow),
    TAtlasStrings.Text(TAtlasTextId.NotificationsModeCollect), TAtlasStrings.Text(TAtlasTextId.NotificationsModeOff)]);
  FNotificationMode.Choice := 0;
  FNotificationMode.OnChange := NotificationModeChange;
end;

procedure TAtlasSettingsPage.NotificationSourceChange(Sender: TObject);
var
  Known: TArray<string>;
begin
  Known := TAtlasNotificationSources.Known;
  if (FNotificationSource.Choice < 0) or (FNotificationSource.Choice > High(Known)) then
    Exit;
  FNotificationMode.Choice := Ord(TAtlasNotificationSources.ModeIn(FNotificationsSpec,
    Known[FNotificationSource.Choice]));
end;

procedure TAtlasSettingsPage.NotificationModeChange(Sender: TObject);
var
  Known: TArray<string>;
begin
  Known := TAtlasNotificationSources.Known;
  if (FNotificationSource.Choice < 0) or (FNotificationSource.Choice > High(Known)) or
    (FNotificationMode.Choice < Ord(Low(TAtlasNotificationMode))) or
    (FNotificationMode.Choice > Ord(High(TAtlasNotificationMode))) then
    Exit;
  FNotificationsSpec := TAtlasNotificationSources.WithMode(FNotificationsSpec, Known[FNotificationSource.Choice],
    TAtlasNotificationMode(FNotificationMode.Choice));
end;

function TAtlasSettingsPage.AddKey(const ACaption: string): TEdit;
var
  Panel: TWinControl;
  mCaption: TLabel;
begin
  Panel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Panel;
  mCaption.Caption := StringReplace(ACaption, '…', '', []);
  mCaption.Left := 0;
  mCaption.Top := 5;
  // Als Text wie im Menü ("Strg+Umschalt+P"); leer = keine Taste.
  Result := TEdit.Create(Self);
  Result.Parent := Panel;
  Result.Left := FieldLeft;
  Result.Top := 1;
  Result.Width := 140;
end;

procedure TAtlasSettingsPage.AddSwatches(const ACaption: string; var ASwatches: array of TShape);
var
  Panel: TWinControl;
  mCaption: TLabel;
  Index: Integer;
begin
  Panel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Panel;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := 5;
  for Index := 0 to High(ASwatches) do
  begin
    ASwatches[Index] := TShape.Create(Self);
    ASwatches[Index].Parent := Panel;
    ASwatches[Index].SetBounds(FieldLeft + Index * 34, 1, 28, 22);
    ASwatches[Index].Pen.Color := clGray;
    ASwatches[Index].Cursor := crHandPoint;
    ASwatches[Index].Hint := IntToStr(Index + 1);
    ASwatches[Index].ShowHint := True;
    ASwatches[Index].OnMouseDown := SwatchMouseDown;
  end;
end;

procedure TAtlasSettingsPage.SwatchMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
var
  Dialog: TColorDialog;
begin
  if Button <> mbLeft then
    Exit;
  Dialog := TColorDialog.Create(nil);
  try
    Dialog.Color := TShape(Sender).Brush.Color;
    Dialog.Options := Dialog.Options + [cdFullOpen];
    if Dialog.Execute then
      TShape(Sender).Brush.Color := Dialog.Color;
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasSettingsPage.ResetColorsClick(Sender: TObject);
begin
  ShowPairs(FLightSwatches, TAtlasColors.Light.Pairs);
  ShowPairs(FDarkSwatches, TAtlasColors.Dark.Pairs);
end;

class procedure TAtlasSettingsPage.ShowPairs(const ASwatches: array of TShape; const APairs: TAtlasPairColors);
var
  Index: Integer;
begin
  for Index := 0 to High(ASwatches) do
    ASwatches[Index].Brush.Color := TColor(APairs[Index]);
end;

class function TAtlasSettingsPage.PairsSetting(const ASwatches: array of TShape;
  const ADefault: TAtlasPairColors): string;
var
  Pairs: TAtlasPairColors;
  Index: Integer;
begin
  for Index := 0 to High(Pairs) do
    Pairs[Index] := TAtlasColor(ColorToRGB(ASwatches[Index].Brush.Color));
  Result := TAtlasColors.PairsText(Pairs);
  if Result = TAtlasColors.PairsText(ADefault) then
    Result := '';
end;

function TAtlasSettingsPage.AddNumber(const ACaption: string): TEdit;
var
  Panel: TWinControl;
  mCaption: TLabel;
begin
  Panel := AddPanel(26);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Panel;
  mCaption.Caption := ACaption;
  mCaption.Left := 0;
  mCaption.Top := 5;
  Result := TEdit.Create(Self);
  Result.Parent := Panel;
  Result.Left := FieldLeft;
  Result.Top := 1;
  Result.Width := 60;
  Result.NumbersOnly := True;
end;

function TAtlasSettingsPage.WelcomeTrendsSeries(ASeries: TAtlasTrendSeries): TCheckBox;
begin
  Result := FWelcomeTrendsSeries[ASeries];
end;

function TAtlasSettingsPage.WelcomeQuickActionsItem(AAction: TAtlasQuickAction): TCheckBox;
begin
  Result := FWelcomeQuickActionsItems[AAction];
end;

procedure TAtlasSettingsPage.LoadFrom(const ASettings: TAtlasPluginSettings);
begin
  // Während des Ladens lösen die Elemente keine Neuberechnung der Punkte aus.
  FMarks.BeginLoad;
  try
    LoadControls(ASettings);
  finally
    FMarks.EndLoad;
  end;
  RefreshMarks;
end;

procedure TAtlasSettingsPage.LoadControls(const ASettings: TAtlasPluginSettings);
var
  Shown: TAtlasTrendSeriesList;
  Series, Wanted: TAtlasTrendSeries;
  Items: TAtlasQuickActions;
  mAction: TAtlasQuickAction;
  Kind: TAtlasOverviewKind;
  Kinds: TAtlasOverviewKinds;
  VisualizerKind: TAtlasVisualizerKind;
  StepFilterKind: TStepFilterKind;
  VisualizerKinds: TAtlasVisualizerKinds;
  StepFilterKinds: TStepFilterKinds;
  Target: TAtlasReassignedTarget;
  Targets: TAtlasReassignedTargets;
begin
  FWidths := ASettings;
  FEnabled.Checked := ASettings.Enabled;
  FServerPath.Text := ASettings.ServerPath;
  FActionsKey.Text := ShortCutToText(TShortCut(ASettings.ActionsKey));
  FExpandKey.Text := ShortCutToText(TShortCut(ASettings.ExpandKey));
  FShrinkKey.Text := ShortCutToText(TShortCut(ASettings.ShrinkKey));
  FImplementationKey.Text := ShortCutToText(TShortCut(ASettings.ImplementationKey));
  FTypeDefinitionKey.Text := ShortCutToText(TShortCut(ASettings.TypeDefinitionKey));
  FMethodToggle.Checked := ASettings.MethodToggle;
  FMethodToggleUpKey.Text := ShortCutToText(TShortCut(ASettings.MethodToggleUpKey));
  FMethodToggleDownKey.Text := ShortCutToText(TShortCut(ASettings.MethodToggleDownKey));
  FTestUnitKey.Text := ShortCutToText(TShortCut(ASettings.TestUnitKey));
  FGotoInterfaceKey.Text := ShortCutToText(TShortCut(ASettings.GotoInterfaceKey));
  FGotoImplementationKey.Text := ShortCutToText(TShortCut(ASettings.GotoImplementationKey));
  FNavHistory.Checked := ASettings.NavHistory;
  FNavBackKey.Text := ShortCutToText(TShortCut(ASettings.NavBackKey));
  FNavForwardKey.Text := ShortCutToText(TShortCut(ASettings.NavForwardKey));
  FLastEditKey.Text := ShortCutToText(TShortCut(ASettings.LastEditKey));
  FPeek.Checked := ASettings.Peek;
  FPeekHeightLines.Text := IntToStr(ASettings.PeekHeightLines);
  FPeekShowImplementation.Checked := ASettings.PeekShowImplementation;
  FDataFlow.Checked := ASettings.DataFlow;
  FDataFlowMaxDepth.Text := IntToStr(ASettings.DataFlowMaxDepth);
  FDataFlowExcludeTests.Checked := ASettings.DataFlowExcludeTests;
  FPeekDefinitionKey.Text := ShortCutToText(TShortCut(ASettings.PeekDefinitionKey));
  FPeekReferencesKey.Text := ShortCutToText(TShortCut(ASettings.PeekReferencesKey));
  FReferencesInferred.Checked := ASettings.ReferencesInferred;
  FReferencesTextMatches.Checked := ASettings.ReferencesTextMatches;
  FCallHierarchyDiagram.Checked := ASettings.CallHierarchyDiagram;
  FImpact.Checked := ASettings.Impact;
  FImpactDepth.Text := IntToStr(ASettings.ImpactDepth);
  FOutline.Checked := ASettings.Outline;
  FOutlineAlphabetical.Checked := ASettings.OutlineAlphabetical;
  FOutlineFollowCursor.Checked := ASettings.OutlineFollowCursor;
  FOutlineConditions.Checked := ASettings.OutlineConditions;
  FBreadcrumbs.Checked := ASettings.Breadcrumbs;
  FBreadcrumbsShowUnit.Checked := ASettings.BreadcrumbsShowUnit;
  FBreadcrumbsIdeColors.Checked := ASettings.BreadcrumbsIdeColors;
  FBreadcrumbsHideIdeToolbar.Checked := ASettings.BreadcrumbsHideIdeToolbar;
  FBreadcrumbsKey.Text := ShortCutToText(TShortCut(ASettings.BreadcrumbsKey));
  FEditorToolbar.Checked := ASettings.EditorToolbar;
  FEditorToolbarPosition.Choice := Max(0, IndexText(ASettings.EditorToolbarPosition, AtlasToolbarPositions));
  FEditorToolbarItems.Text := ASettings.EditorToolbarItems;
  FEditorToolbarReturnButton.Checked := ASettings.EditorToolbarReturnButton;
  FEditorToolbarLabels.Checked := ASettings.EditorToolbarLabels;
  FEditorStatusBar.Checked := ASettings.EditorStatusBar;
  FEditorStatusBarItems.Text := ASettings.EditorStatusBarItems;
  FStickyScroll.Checked := ASettings.StickyScroll;
  FStickyScrollMaxLines.Text := IntToStr(ASettings.StickyScrollMaxLines);
  FMinimap.Checked := ASettings.Minimap;
  FMinimapRender.Choice := Max(0, IndexText(ASettings.MinimapRender, ['blocks', 'characters']));
  FMinimapWidth.Text := IntToStr(ASettings.MinimapWidth);
  FMinimapScale.Text := IntToStr(ASettings.MinimapScale);
  FMinimapMaxColumn.Text := IntToStr(ASettings.MinimapMaxColumn);
  FMinimapSide.Choice := Max(0, IndexText(ASettings.MinimapSide, ['right', 'left']));
  FMinimapShowSlider.Choice := Max(0, IndexText(ASettings.MinimapShowSlider, ['always', 'mouseover']));
  FMinimapSectionHeaders.Checked := ASettings.MinimapSectionHeaders;
  FMinimapHighlightMethod.Checked := ASettings.MinimapHighlightMethod;
  FMinimapMarkers.Checked := ASettings.MinimapMarkers;
  FMinimapClickJumps.Checked := ASettings.MinimapClickJumps;
  FGitGutter.Checked := ASettings.GitGutter;
  FGitBlame.Checked := ASettings.GitBlame;
  FGutterColumn.Checked := ASettings.GutterColumn;
  FGutterColumnProblems.Checked := ASettings.GutterColumnProblems;
  FGutterColumnCodeActions.Checked := ASettings.GutterColumnCodeActions;
  FGutterColumnOverrides.Checked := ASettings.GutterColumnOverrides;
  FSelectionMatches.Checked := ASettings.SelectionMatches;
  FSelectionMatchesMinLength.Text := IntToStr(ASettings.SelectionMatchesMinLength);
  FSelectionMatchesCaseSensitive.Checked := ASettings.SelectionMatchesCaseSensitive;
  FSelectionMatchesWholeWord.Checked := ASettings.SelectionMatchesWholeWord;
  FSelectionMatchesNavigateF3.Checked := ASettings.SelectionMatchesNavigateF3;
  FSelectionMatchesMaxMatches.Text := IntToStr(ASettings.SelectionMatchesMaxMatches);
  FExitPoints.Checked := ASettings.ExitPoints;
  FExitPointsExceptions.Checked := ASettings.ExitPointsExceptions;
  FExitPointsLoops.Checked := ASettings.ExitPointsLoops;
  FExitPointsBadge.Checked := ASettings.ExitPointsBadge;
  FReassigned.Checked := ASettings.Reassigned;
  Targets := TAtlasReassignedNames.ParseTargets(ASettings.ReassignedTargets);
  for Target := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
    FReassignedTargets[Target].Checked := Target in Targets;
  FReassignedStyle.Choice := Ord(TAtlasReassignedNames.StyleOf(ASettings.ReassignedStyle));
  FReassignedColor.Text := ASettings.ReassignedColor;
  FExpressionType.Checked := ASettings.ExpressionType;
  FExpressionTypeConversions.Checked := ASettings.ExpressionTypeConversions;
  FExpressionTypeConstValue.Checked := ASettings.ExpressionTypeConstValue;
  FExpressionTypeKey.Text := ShortCutToText(TShortCut(ASettings.ExpressionTypeKey));
  FMethodPlacement.Choice := Max(0, IndexText(ASettings.MethodPlacement, AtlasMethodPlacements));
  FNextChangeKey.Text := ShortCutToText(TShortCut(ASettings.NextChangeKey));
  FPreviousChangeKey.Text := ShortCutToText(TShortCut(ASettings.PreviousChangeKey));
  FOverviewRuler.Checked := ASettings.OverviewRuler;
  Kinds := TAtlasOverview.Kinds(ASettings.OverviewRulerKinds);
  for Kind := Low(TAtlasOverviewKind) to High(TAtlasOverviewKind) do
    FOverviewKinds[Kind].Checked := Kind in Kinds;
  FJumpToMatch.Checked := ASettings.JumpToMatch;
  FJumpToMatchKey.Text := ShortCutToText(TShortCut(ASettings.JumpToMatchKey));
  FJumpToMatchSelectKey.Text := ShortCutToText(TShortCut(ASettings.JumpToMatchSelectKey));
  FMoveLines.Checked := ASettings.MoveLines;
  FMoveLinesUpKey.Text := ShortCutToText(TShortCut(ASettings.MoveLinesUpKey));
  FMoveLinesDownKey.Text := ShortCutToText(TShortCut(ASettings.MoveLinesDownKey));
  FDuplicateLinesUpKey.Text := ShortCutToText(TShortCut(ASettings.DuplicateLinesUpKey));
  FDuplicateLinesDownKey.Text := ShortCutToText(TShortCut(ASettings.DuplicateLinesDownKey));
  FToggleBlockComment.Checked := ASettings.ToggleBlockComment;
  FToggleBlockCommentKey.Text := ShortCutToText(TShortCut(ASettings.ToggleBlockCommentKey));
  FToggleBlockCommentStyle.Choice := Max(0, IndexText(ASettings.ToggleBlockCommentStyle, ['braces', 'parens']));
  FToggleBlockCommentFallback.Choice := Max(0, IndexText(ASettings.ToggleBlockCommentFallback,
    ['lineComments', 'refuse']));
  FToggleBlockCommentOwnLines.Checked := ASettings.ToggleBlockCommentOwnLines;
  FToggleBlockCommentScope.Choice := Max(0, IndexText(ASettings.ToggleBlockCommentWithoutSelection,
    ['statement', 'line']));
  FNewLineAround.Checked := ASettings.NewLineAround;
  FNewLineBelowKey.Text := ShortCutToText(TShortCut(ASettings.NewLineBelowKey));
  FNewLineAboveKey.Text := ShortCutToText(TShortCut(ASettings.NewLineAboveKey));
  FNewLineAroundStatementAware.Checked := ASettings.NewLineAroundStatementAware;
  FUnwrap.Checked := ASettings.Unwrap;
  FUnwrapKey.Text := ShortCutToText(TShortCut(ASettings.UnwrapKey));
  FSafeDelete.Checked := ASettings.SafeDelete;
  FSafeDeleteKey.Text := ShortCutToText(TShortCut(ASettings.SafeDeleteKey));
  FContinueComments.Checked := ASettings.ContinueComments;
  FContinueCommentsLineComments.Checked := ASettings.ContinueCommentsLineComments;
  FContinueCommentsLists.Checked := ASettings.ContinueCommentsLists;
  FContinueCommentsBlockPrefix.Text := ASettings.ContinueCommentsBlockPrefix;
  FWrapSelection.Checked := ASettings.WrapSelection;
  FWrapSelectionChars.Text := ASettings.WrapSelectionChars;
  FCompleteStatement.Checked := ASettings.CompleteStatement;
  FCompleteStatementKey.Text := ShortCutToText(TShortCut(ASettings.CompleteStatementKey));
  // Reihenfolge der Auswahl: always, multiLine, never bzw. finally, except, ask.
  FCompleteStatementBeginEnd.Choice := 1;
  if ASettings.CompleteStatementBeginEnd = TAtlasPluginSettings.BeginEndAlways then
    FCompleteStatementBeginEnd.Choice := 0
  else if ASettings.CompleteStatementBeginEnd = TAtlasPluginSettings.BeginEndNever then
    FCompleteStatementBeginEnd.Choice := 2;
  FCompleteStatementTryKind.Choice := 0;
  if ASettings.CompleteStatementTryKind = TAtlasPluginSettings.TryKindExcept then
    FCompleteStatementTryKind.Choice := 1
  else if ASettings.CompleteStatementTryKind = TAtlasPluginSettings.TryKindAsk then
    FCompleteStatementTryKind.Choice := 2;
  FCompleteStatementMethodBody.Checked := ASettings.CompleteStatementMethodBody;
  FFormatCode.Checked := ASettings.FormatCode;
  FFormatCodeKey.Text := ShortCutToText(TShortCut(ASettings.FormatCodeKey));
  FContinuePattern.Checked := ASettings.ContinuePattern;
  FContinuePatternMinLines.Text := IntToStr(ASettings.ContinuePatternMinLines);
  FMultiCursor.Checked := ASettings.MultiCursor;
  FLinkedEditing.Checked := ASettings.LinkedEditing;
  FSmartPaste.Choice := Max(0, IndexText(ASettings.SmartPaste, ['off', 'uses', 'indent', 'both']));
  FMultiCursorModifier.Choice := 0;
  if ASettings.MultiCursorModifier = TAtlasPluginSettings.MultiCursorModifierCtrl then
    FMultiCursorModifier.Choice := 1;
  FMultiCursorNextKey.Text := ShortCutToText(TShortCut(ASettings.MultiCursorNextKey));
  FMultiCursorSkipKey.Text := ShortCutToText(TShortCut(ASettings.MultiCursorSkipKey));
  FMultiCursorLineEndsKey.Text := ShortCutToText(TShortCut(ASettings.MultiCursorLineEndsKey));
  FMultiCursorAboveKey.Text := ShortCutToText(TShortCut(ASettings.MultiCursorAboveKey));
  FMultiCursorBelowKey.Text := ShortCutToText(TShortCut(ASettings.MultiCursorBelowKey));
  FBookmarkKey.Text := ShortCutToText(TShortCut(ASettings.BookmarkKey));
  FNextBookmarkKey.Text := ShortCutToText(TShortCut(ASettings.NextBookmarkKey));
  FPreviousBookmarkKey.Text := ShortCutToText(TShortCut(ASettings.PreviousBookmarkKey));
  FHideElementKey.Text := ShortCutToText(TShortCut(ASettings.HideElementKey));
  FNextProblemKey.Text := ShortCutToText(TShortCut(ASettings.NextProblemKey));
  FPreviousProblemKey.Text := ShortCutToText(TShortCut(ASettings.PreviousProblemKey));
  FProblemsWindowKey.Text := ShortCutToText(TShortCut(ASettings.ProblemsWindowKey));
  FCreateIssueKey.Text := ShortCutToText(TShortCut(ASettings.CreateIssueKey));
  FEditorKeysPriority.Checked := ASettings.EditorKeysPriority;
  FSlashCommands.Checked := ASettings.SlashCommands;
  FGenerateMenu.Checked := ASettings.GenerateMenu;
  FGenerateMenuKey.Text := ShortCutToText(TShortCut(ASettings.GenerateMenuKey));
  FNotificationsKey.Text := ShortCutToText(TShortCut(ASettings.NotificationsKey));
  FGenerateMenuGroups.Text := ASettings.GenerateMenuGroups;
  FGenerateMenuHidden.Text := ASettings.GenerateMenuHidden;
  FGenerateMenuRecentFirst.Checked := ASettings.GenerateMenuRecentFirst;
  FGenerateMenuShowCommandNames.Checked := ASettings.GenerateMenuShowCommandNames;
  ServerPathChange(nil);
  FRowsUpDown.Position := ASettings.VisibleRows;
  FPanelCollapsed.Checked := ASettings.PanelCollapsed;
  FSelectionMarker.Checked := ASettings.SelectionMarker;
  FAutoParentheses.Checked := ASettings.AutoParentheses;
  FFixCase.Checked := ASettings.FixCase;
  FCommitChars.Checked := ASettings.CommitCharacters;
  FAutoUses.Checked := ASettings.AutoUses;
  FParameterHints.Checked := ASettings.ParameterHints;
  FFormatPlaceholders.Checked := ASettings.FormatPlaceholders;
  FOpenDelay.Text := IntToStr(ASettings.OpenDelayMs);
  FAutoWidth.OnClick := nil;
  FAutoWidth.Checked := ASettings.ListWidth = 0;
  FAutoWidth.OnClick := AutoWidthClick;
  FFilterChips.Checked := ASettings.FilterChips;
  FLearning.Checked := ASettings.Learning;
  FFavorites.Checked := ASettings.Favorites;
  FGroupInherited.Checked := ASettings.GroupInherited;
  FCompletionVariantBranch.Checked := ASettings.CompletionVariantBranch;
  FListMode.Choice := Ord(TAtlasListModes.ModeOf(ASettings.CompletionListMode));
  FListScope.Choice := Ord(TAtlasListModes.ScopeOf(ASettings.CompletionListScope));
  FPreview.Checked := ASettings.Preview;
  FSnippets.Checked := ASettings.Snippets;
  FImportIdeTemplates.Checked := ASettings.ImportIdeTemplates;
  FTeamFile.Checked := ASettings.TeamFile;
  RefreshTeamFile;
  FHoverTooltip.Checked := ASettings.HoverTooltip;
  FHoverProblemActions.Checked := ASettings.HoverProblemActions;
  FXmlDocExpand.Choice := Ord(TAtlasDocDisplay.ExpandOf(ASettings.XmlDocExpand));
  FXmlDocMaxLines.Text := IntToStr(ASettings.XmlDocMaxLines);
  FHangThreshold.Text := IntToStr(ASettings.HangThresholdMs);
  FProviderTimeLimit.Text := IntToStr(ASettings.ProviderTimeLimitMs);
  FHangHint.Checked := ASettings.HangHint;
  FReloadExternal.Checked := ASettings.ReloadExternal;
  FOpenForEdits.Checked := ASettings.OpenForEdits;
  FPairColors.Checked := ASettings.PairColors;
  FInactiveDim.Checked := ASettings.InactiveDim;
  FInlayHints.Checked := ASettings.InlayHints;
  FInlayTypeHints.Checked := ASettings.InlayTypeHints;
  FInlayDefineHints.Checked := ASettings.InlayDefineHints;
  FInlayCharHints.Checked := ASettings.InlayCharHints;
  FInlayMethodHints.Checked := ASettings.InlayMethodHints;
  FBlockEndLabels.Checked := ASettings.BlockEndLabels;
  FBlockEndLabelsMinLines.Text := IntToStr(ASettings.BlockEndLabelsMinLines);
  FDimUnusedUses.Checked := ASettings.DimUnusedUses;
  FRecursionMarkers.Checked := ASettings.RecursionMarkers;
  FRecursionMarkersDepth.Text := IntToStr(ASettings.RecursionMarkersDepth);
  FInlineDiagnostics.Choice := Ord(TAtlasInlineDiagnostics.ModeOf(ASettings.InlineDiagnostics));
  FNotes.Checked := ASettings.Notes;
  FBookmarksNamed.Checked := ASettings.BookmarksNamed;
  FBookmarksShared.Checked := ASettings.BookmarksShared;
  FQuickBookmarks.Checked := ASettings.QuickBookmarks;
  FQuickBookmarksGutter.Checked := ASettings.QuickBookmarksGutter;
  FQuickBookmarksGutterClick.Checked := ASettings.QuickBookmarksGutterClick;
  FQuickBookmarksNumberedKeys.Checked := ASettings.QuickBookmarksNumberedKeys;
  FQuickBookmarkKey.Text := ShortCutToText(TShortCut(ASettings.QuickBookmarkKey));
  FQuickBookmarkChordWait.Text := IntToStr(ASettings.QuickBookmarkChordWait);
  FQuickBookmarksScope.Choice := Max(0, IndexText(ASettings.QuickBookmarksScope, AtlasQuickBookmarkScopes));
  FQuickBookmarksImportIde.Checked := ASettings.QuickBookmarksImportIde;
  FCodeLensTestUnit.Checked := ASettings.CodeLensTestUnit;
  FCodeLensMetrics.Checked := ASettings.CodeLensMetrics;
  FMetrics.Checked := ASettings.Metrics;
  FCodeLensTests.Checked := ASettings.CodeLensTests;
  FTodoList.Checked := ASettings.TodoList;
  FBaselineUpdate.Checked := ASettings.BaselineUpdate;
  FMetricsReport.Checked := ASettings.MetricsReport;
  FDfmPropertyRules.Checked := ASettings.DfmPropertyRules;
  FPairGuides.Checked := ASettings.PairGuides;
  FPairOwners.Checked := ASettings.PairOwners;
  FPairGuideWidth.Text := IntToStr(ASettings.PairGuideWidth);
  FPairGuideOpacity.Text := IntToStr(ASettings.PairGuideOpacity);
  ShowPairs(FLightSwatches, TAtlasColors.Light.WithPairs(ASettings.PairColorsLight).Pairs);
  ShowPairs(FDarkSwatches, TAtlasColors.Dark.WithPairs(ASettings.PairColorsDark).Pairs);
  FProblems.Checked := ASettings.Problems;
  FProblemsList.Checked := ASettings.ProblemsList;
  FProblemsWindow.Checked := ASettings.ProblemsWindow;
  FProblemsWindowScope.Choice := Max(0, IndexText(ASettings.ProblemsWindowScope, ScopeValues));
  FProblemsWindowGroupBy.Choice := Max(0, IndexText(ASettings.ProblemsWindowGroupBy, GroupByValues));
  FProblemsWindowCompiler.Checked := ASettings.ProblemsWindowCompiler;
  FProblemsWindowFollowCursor.Checked := ASettings.ProblemsWindowFollowCursor;
  FProblemsWindowOpenFirst.Checked := ASettings.ProblemsWindowOpenFirst;
  FProblemsWindowClosedUnits.Choice := Max(0, IndexText(ASettings.ProblemsWindowClosedUnits, ClosedUnitsValues));
  FProblemsWindowShowCleanActive.Checked := ASettings.ProblemsWindowShowCleanActive;
  FProblemsCompilerMerge.Choice := Max(0, IndexText(ASettings.ProblemsCompilerMerge, CompilerMergeValues));
  FProblemsShowCompilerCode.Checked := ASettings.ProblemsShowCompilerCode;
  FProblemsLive.Checked := ASettings.ProblemsLive;
  FProblemsStatusCounter.Checked := ASettings.ProblemsStatusCounter;
  FStatusField.Checked := ASettings.StatusField;
  FDiagnosticMode.Checked := ASettings.DiagnosticMode;
  FDiagnosticsProcesses.Checked := ASettings.DiagnosticsProcesses;
  FArchitecture.Checked := ASettings.ArchitectureEnabled;
  FArchitectureScope.Choice := Max(0, IndexText(ASettings.ArchitectureScope, ['projectGroup', 'project']));
  FArchitectureLibrary.Checked := ASettings.ArchitectureIncludeLibraryUnits;
  FArchitectureCentral.Text := IntToStr(ASettings.ArchitectureCentralUnits);
  FExperimentalEnabled.Checked := ASettings.ExperimentalEnabled;
  // Checked löst OnClick nur bei einer Änderung aus.
  FHangTestRow.Visible := ASettings.DiagnosticMode;
  FSetupChecklist.Checked := ASettings.SetupChecklist;
  FShortcutTips.Checked := ASettings.ShortcutTips;
  FShortcutTipsScope.Choice := Ord(TAtlasShortcutTips.ScopeOf(ASettings.ShortcutTipsScope));
  FNotifications.Checked := ASettings.Notifications;
  FNotificationsMax.Text := IntToStr(ASettings.NotificationsMaxEntries);
  FNotificationsSpec := ASettings.NotificationsSources;
  NotificationSourceChange(nil);
  FStatusSummary.Checked := ASettings.StatusFieldSummary;
  if not ASettings.StatusTogglesOnDoubleClick then
    FStatusToggles.Choice := 1
  else if not ASettings.StatusTogglesOnRightClick then
    FStatusToggles.Choice := 2
  else
    FStatusToggles.Choice := 0;
  if SameText(ASettings.IndexProgressPlace, 'menu') then
    FIndexProgress.Choice := 1
  else if SameText(ASettings.IndexProgressPlace, 'off') then
    FIndexProgress.Choice := 2
  else
    FIndexProgress.Choice := 0;
  FStatusHidden.Text := ASettings.StatusFieldHidden;
  FIndexGroup.Checked := ASettings.IndexProjectGroup;
  FIndexSearch.Checked := ASettings.IndexSearchPaths;
  FIndexLibrary.Checked := ASettings.IndexLibraryPaths;
  FIndexUsages.Checked := ASettings.IndexUsages;
  FMemoryBudget.Text := IntToStr(ASettings.MemoryBudgetMb);
  FAfterSave.Choice := 0;
  if ASettings.CheckOnSave then
    FAfterSave.Choice := 1
  else if ASettings.CompileOnSave then
    FAfterSave.Choice := 2;
  FCheckDelay.Text := IntToStr(ASettings.CheckOnSaveDelayMs);
  FCheckMax.Text := IntToStr(ASettings.CheckOnSaveMaxMs);
  FMcpBuild.Checked := ASettings.McpBuild;
  LoadOpenBuild(ASettings);
  LoadTasks(ASettings);
  FTestRun.Checked := ASettings.TestRun;
  FTestsBuildFirst.Checked := ASettings.TestsBuildFirst;
  FTestsAfterBuild.Checked := ASettings.TestsAfterBuild;
  FBuildZeroHints.Checked := ASettings.BuildZeroHints;
  FShowInterfaceCost.Checked := ASettings.ShowInterfaceCost;
  FBuildSummary.Checked := ASettings.BuildSummary;
  FBuildWarningsAsErrors.Text := TAtlasBuildVerdicts.NormalizeCodes(ASettings.BuildWarningsAsErrors);
  FBuildGate.Choice := Ord(TAtlasReleaseGuard.GateOf(ASettings.BuildGate));
  FBuildGateTimeout.Text := IntToStr(ASettings.BuildGateTimeoutMs);
  FBuildCompilerSwitches.Checked := ASettings.BuildCompilerSwitches;
  FBuildSwitchesInStatusBar.Checked := ASettings.BuildSwitchesInStatusBar;
  LoadRelease(ASettings);
  FStartProfiles.Checked := ASettings.StartProfiles;
  FStartProfilesStatusField.Checked := ASettings.StartProfilesStatusField;
  FTestDebug.Checked := ASettings.TestDebug;
  FTestBreakAtStart.Checked := ASettings.TestBreakAtStart;
  FDebugHoverValues.Checked := ASettings.DebugHoverValues;
  FDebugVisualizers.Checked := ASettings.DebugVisualizers;
  VisualizerKinds := TAtlasVisualizerSettings.ParseKinds(ASettings.DebugVisualizerTypes);
  for VisualizerKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
    FDebugVisualizerKinds[VisualizerKind].Checked := VisualizerKind in VisualizerKinds;
  FDebugVisualizerNameFields.Text := ASettings.DebugVisualizerNameFields;
  FDebugVisualizerMaxLength.Text := IntToStr(ASettings.DebugVisualizerMaxLength);
  FDebugVisualizerTimeout.Text := IntToStr(ASettings.DebugVisualizerTimeoutMs);
  FDebugVisualizerMaxImagePixels.Text := IntToStr(ASettings.DebugVisualizerMaxImagePixels);
  FDebugVisualizerEvaluation.Choice := Ord(TAtlasVisualizerSettings.ParseEvaluation(ASettings.DebugVisualizerEvaluation));
  FDebugDisplayRules.Checked := ASettings.DebugDisplayRules;
  FDebugDisplayRulesAllowCalls.Checked := ASettings.DebugDisplayRulesAllowCalls;
  FDebugStepIntoTarget.Checked := ASettings.DebugStepIntoTarget;
  FDebugStepFilters.Checked := ASettings.DebugStepFilters;
  StepFilterKinds := TStepFilterNames.ParseKinds(ASettings.DebugStepFilterKinds);
  for StepFilterKind := Low(TStepFilterKind) to High(TStepFilterKind) do
    FDebugStepFilterKinds[StepFilterKind].Checked := StepFilterKind in StepFilterKinds;
  FDebugStepFilterPatterns.Text := ASettings.DebugStepFilterPatterns;
  FDebugStepIntoTargetKey.Text := ShortCutToText(TShortCut(ASettings.DebugStepIntoTargetKey));
  FDebugBreakOnNextEvent.Checked := ASettings.DebugBreakOnNextEvent;
  FDebugBreakOnNextEventExcluded.Text := ASettings.DebugBreakOnNextEventExcluded;
  FDebugExplainUnavailable.Checked := ASettings.DebugExplainUnavailable;
  FDebugCompletionInDialogs.Checked := ASettings.DebugCompletionInDialogs;
  FDebugEvaluateWindow.Checked := ASettings.DebugEvaluateWindow;
  FDebugEvaluateReplaceCtrlF7.Checked := ASettings.DebugEvaluateReplaceCtrlF7;
  FDebugExplainAccessViolation.Checked := ASettings.DebugExplainAccessViolation;
  FDebugExplainAccessViolationAllowCalls.Checked := ASettings.DebugExplainAccessViolationAllowCalls;
  FDebugExceptionHistory.Checked := ASettings.DebugExceptionHistory;
  FDebugJustMyCode.Checked := ASettings.DebugJustMyCode;
  FDebugExceptionBanner.Checked := ASettings.DebugExceptionBanner;
  FDebugExceptionBannerIgnoreAtLocation.Checked := ASettings.DebugExceptionBannerIgnoreAtLocation;
  FDebugInlineValues.Checked := ASettings.DebugInlineValues;
  FDebugInlineValuesPerLine.Text := IntToStr(ASettings.DebugInlineValuesPerLine);
  FDebugOwnCodeFolders.Text := ASettings.DebugOwnCodeFolders;
  FSafeAsk.Checked := ASettings.SafeAskAfterCrash;
  FSafeAuto.Checked := ASettings.SafeAutoAfterRepeatedCrash;
  case TAtlasSafeMode.KeyOf(ASettings.SafeStartupKey) of
    TAtlasStartupKey.Ctrl:
      FSafeKey.Choice := 1;
    TAtlasStartupKey.None:
      FSafeKey.Choice := 2;
  else
    FSafeKey.Choice := 0;
  end;
  FSafeTimeout.Text := IntToStr(ASettings.SafeStartupTimeoutMs);
  FSafeHistory.Text := IntToStr(ASettings.SafeKeepSettingsHistory);
  FUndoEnabled.Checked := ASettings.UndoMultiFile;
  FUndoDepth.Text := IntToStr(ASettings.UndoMultiFileDepth);
  FUndoPersist.Checked := ASettings.UndoMultiFilePersist;
  FUndoMaxSize.Text := IntToStr(ASettings.UndoMultiFileMaxSizeMb);
  FUndoOnConflict.Choice := Ord(TAtlasUndoNames.ParseConflictMode(ASettings.UndoMultiFileOnConflict));
  FUndoNewFiles.Choice := Ord(TAtlasUndoNames.ParseNewFiles(ASettings.UndoMultiFileNewFiles));
  FUndoKey.Text := ShortCutToText(TShortCut(ASettings.UndoKey));
  FRedoKey.Text := ShortCutToText(TShortCut(ASettings.RedoKey));
  FUpdatesCheck.Checked := ASettings.UpdatesCheck;
  FBugReportAnonymize.Checked := ASettings.BugReportAnonymize;
  FUnitSearchEnabled.Checked := ASettings.UnitSearchEnabled;
  FUnitSearchReplace.Checked := ASettings.UnitSearchReplaceIdeDialog;
  FUnitSearchReplaceUseUnit.Checked := ASettings.UnitSearchReplaceUseUnitDialog;
  FUnitSearchReplaceForms.Checked := ASettings.UnitSearchReplaceFormsDialog;
  FUnitSearchKey.Text := ShortCutToText(TShortCut(ASettings.UnitSearchKey));
  FUnitSearchPathStyle.Choice := ChoiceOf(ASettings.UnitSearchPathStyle, UnitSearchPathStyles);
  FUnitSearchGroupBy.Choice := ChoiceOf(ASettings.UnitSearchGroupBy, UnitSearchGroupings);
  FUnitSearchRememberCollapsed.Checked := ASettings.UnitSearchRememberCollapsed;
  FUnitSearchFilters.Checked := ASettings.UnitSearchFilters;
  FUnitSearchDefaultScope.Choice := ChoiceOf(ASettings.UnitSearchDefaultScope, UnitSearchScopes);
  FUnitSearchFilterSyntax.Checked := ASettings.UnitSearchFilterSyntax;
  FUnitSearchPreview.Checked := ASettings.UnitSearchPreview;
  FUnitSearchPreviewForm.Checked := ASettings.UnitSearchPreviewForm;
  FUnitSearchPreviewUsedBy.Checked := ASettings.UnitSearchPreviewUsedBy;
  FUnitSearchPreviewAutoCollapse.Checked := ASettings.UnitSearchPreviewAutoCollapse;
  FUnitSearchMultiSelect.Checked := ASettings.UnitSearchMultiSelect;
  FUnitSearchActions.Checked := ASettings.UnitSearchActions;
  FUnitSearchAddUses.Checked := ASettings.UnitSearchActionsAddUses;
  FQuickOpen.Checked := ASettings.QuickOpen;
  FQuickOpenLibrary.Checked := ASettings.QuickOpenLibrary;
  FQuickOpenKey.Text := ShortCutToText(TShortCut(ASettings.QuickOpenKey));
  FSearchReplace.Checked := ASettings.SearchReplaceIde;
  FSearchMessages.Checked := ASettings.SearchResultsInMessages;
  FSearchReplaceBar.Checked := ASettings.SearchReplace;
  FSearchRegex.Checked := ASettings.SearchRegex;
  FSearchHistory.Text := IntToStr(ASettings.SearchHistory);
  FSearchMultiFile.Checked := ASettings.SearchMultiFile;
  FWelcomeEnabled.Checked := ASettings.WelcomePage;
  FWelcomeOpenOnStart.Checked := ASettings.WelcomePageOpenOnStart;
  FWelcomeOpenWhenNoProject.Checked := ASettings.WelcomePageOpenWhenNoProject;
  FWelcomeHeader.Checked := ASettings.WelcomePageHeader;
  FWelcomeGreeting.Checked := ASettings.WelcomePageGreeting;
  FWelcomeSearch.Checked := ASettings.WelcomePageSearch;
  FWelcomeSearchSymbols.Checked := ASettings.WelcomePageSearchSymbols;
  FWelcomeSearchKey.Text := ShortCutToText(TShortCut(ASettings.WelcomePageSearchKey));
  FWelcomeWhatsNew.Choice := Ord(TAtlasWhatsNew.ModeOf(ASettings.WelcomePageWhatsNew));
  FWelcomeContinue.Checked := ASettings.WelcomePageContinue;
  FWelcomeContinueCount.Text := IntToStr(ASettings.WelcomePageContinueCount);
  FWelcomeContinueIncoming.Checked := ASettings.WelcomePageContinueIncoming;
  FWelcomeContinueFetch.Checked := ASettings.WelcomePageContinueFetch;
  FWelcomeSaved.Checked := ASettings.WelcomePageSaved;
  FWelcomeProjects.Checked := ASettings.WelcomePageProjectStatus;
  FWelcomeMaxProjects.Text := IntToStr(ASettings.WelcomePageMaxProjects);
  FWelcomeRefreshVcs.Checked := ASettings.WelcomePageRefreshVcs;
  FWelcomeTrends.Checked := ASettings.WelcomePageTrends;
  FWelcomeTrendsPoints.Text := IntToStr(ASettings.WelcomePageTrendsPoints);
  Shown := TAtlasWelcomeTrends.ParseSeries(ASettings.WelcomePageTrendsSeries);
  for Series := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
  begin
    FWelcomeTrendsSeries[Series].Checked := False;
    for Wanted in Shown do
      if Wanted = Series then
        FWelcomeTrendsSeries[Series].Checked := True;
  end;
  FWelcomeTests.Checked := ASettings.WelcomePageTests;
  FWelcomeTestsMaxFailures.Text := IntToStr(ASettings.WelcomePageTestsMaxFailures);
  FWelcomeTestsCi.Checked := ASettings.WelcomePageTestsCi;
  // Einziger Anbieter bisher: jenkins.
  FWelcomeTestsCiProvider.Choice := 0;
  FWelcomeTestsCiInterval.Text := IntToStr(ASettings.WelcomePageTestsCiIntervalMinutes);
  FWelcomeTestsCiNotify.Checked := ASettings.WelcomePageTestsCiNotify;
  FCiLogin.Checked := ASettings.CiLogin;
  FWelcomeIssues.Checked := ASettings.WelcomePageIssues;
  if SameText(ASettings.IssuesTracker, 'github') then
    FIssuesTracker.Choice := 1
  else if SameText(ASettings.IssuesTracker, 'youtrack') then
    FIssuesTracker.Choice := 2
  else
    FIssuesTracker.Choice := 0;
  if SameText(ASettings.IssuesStart, TAtlasPluginSettings.IssuesStartRemember) then
    FIssuesStart.Choice := 1
  else
    FIssuesStart.Choice := 0;
  FIssuesBranchPattern.Text := ASettings.IssuesBranchPattern;
  FIssuesBranchBase.Text := ASettings.IssuesBranchBase;
  FIssuesCommitPattern.Text := ASettings.IssuesCommitPattern;
  FTrackerLogin.Checked := ASettings.TrackerLogin;
  FIssuesPreview.Checked := ASettings.IssuesPreview;
  FIssuesPreviewComments.Checked := ASettings.IssuesPreviewComments;
  FIssuesCodeLinks.Checked := ASettings.IssuesCodeLinks;
  FIssuesBlameLinks.Checked := ASettings.IssuesBlameLinks;
  FIssuesBlameMaxRevisions.Text := IntToStr(ASettings.IssuesBlameMaxRevisions);
  FIssuesSyncState.Checked := ASettings.IssuesSyncState;
  FIssuesStateField.Value := ASettings.IssuesStateField;
  FIssuesAssigneeField.Value := ASettings.IssuesAssigneeField;
  FIssuesStartState.Value := ASettings.IssuesStartState;
  FIssuesAssignOnStart.Checked := ASettings.IssuesAssignOnStart;
  FIssuesStartComment.Text := ASettings.IssuesStartComment;
  FIssuesEndStates.Text := ASettings.IssuesEndStates;
  FIssuesEndComment.Text := ASettings.IssuesEndComment;
  FIssuesTimeTracking.Checked := ASettings.IssuesTimeTracking;
  FIssuesIdleMinutes.Text := IntToStr(ASettings.IssuesIdleMinutes);
  FIssuesTimeRounding.Text := IntToStr(ASettings.IssuesTimeRounding);
  FIssuesPreviewChecklists.Checked := ASettings.IssuesPreviewChecklists;
  FIssuesChecklistStatus.Checked := ASettings.IssuesChecklistStatus;
  FTrackerConnections := TAtlasTrackerConnections.Read(ASettings.IssuesConnections);
  FTrackerSelected := -1;
  if Length(FTrackerConnections) > 0 then
    FTrackerSelected := 0;
  // Zuordnung (#1261) vor dem Aufbau: RefreshTrackerConnections baut die Tabelle Projekte mit.
  FTrackerProjects := TAtlasTrackerProjects.Read(ASettings.IssuesProjects);
  FTrackerProjectSelected := -1;
  if Length(FTrackerProjects) > 0 then
    FTrackerProjectSelected := 0;
  // Ebenso die Abfragen (#1262): RefreshTrackerProjects baut sie mit.
  FTrackerQueries := TAtlasTrackerQueries.Read(ASettings.IssuesQueries);
  FTrackerQuerySelected := -1;
  if Length(FTrackerQueries) > 0 then
    FTrackerQuerySelected := 0;
  FIssuesQueryPicker.Checked := ASettings.IssuesQueryPicker;
  FIssuesCreate.Checked := ASettings.IssuesCreate;
  FIssuesCreateIncludeCode.Checked := ASettings.IssuesCreateIncludeCode;
  RefreshTrackerConnections;
  FVcsProvider.Choice := Max(0, IndexText(ASettings.VcsProvider, ['auto', 'git', 'svn', 'off']));
  FVcsPaths[TAtlasVcsKind.Git].Text := ASettings.VcsGitPath;
  FVcsPaths[TAtlasVcsKind.Svn].Text := ASettings.VcsSvnPath;
  FVcsTimeout.Text := IntToStr(ASettings.VcsTimeoutSeconds);
  FVcsBranchConfirm.Checked := ASettings.VcsBranchConfirm;
  FVcsBranchSvnLocation.Text := ASettings.VcsBranchSvnLocation;
  FVcsBranchSvnSource.Choice := Ord(AtlasVcsSvnSourceOf(ASettings.VcsBranchSvnSource));
  FVcsBranchSvnAfter.Choice := Ord(AtlasVcsSvnAfterOf(ASettings.VcsBranchSvnAfter));
  FVcsBranchSvnFolder.Text := ASettings.VcsBranchSvnCheckoutFolder;
  FVcsBranchSvnMessage.Text := ASettings.VcsBranchSvnMessage;
  FVcsExternalsOnBranch.Choice := Max(0, IndexText(ASettings.VcsExternalsOnBranch, ['pin', 'keep', 'ask']));
  FVcsExternalsSuggest.Choice := Max(0, IndexText(ASettings.VcsExternalsSuggestBranch,
    ['modified', 'never', 'always']));
  FVcsExternalsRules.Text := TAtlasVcsBranchPlan.RulesText(TAtlasVcsBranchPlan.RulesOf(ASettings.VcsExternalsRules));
  FVcsExternalsShow.Checked := ASettings.VcsExternalsShow;
  FVcsExternalsUpdate.Choice := Ord(AtlasVcsExternalsUpdateOf(ASettings.VcsExternalsUpdate));
  FVcsBranchGitBase.Choice := Max(0, IndexText(ASettings.VcsBranchGitBase, cVcsGitBases));
  FVcsBranchGitPush.Choice := Max(0, IndexText(ASettings.VcsBranchGitPush, cVcsGitPushes));
  FVcsBranchGitUncommitted.Choice := Max(0, IndexText(ASettings.VcsBranchGitUncommitted, cVcsGitUncommitted));
  FVcsBranchGitWorktree.Checked := ASettings.VcsBranchGitWorktree;
  FVcsBranchGitWorktreeFolder.Text := ASettings.VcsBranchGitWorktreeFolder;
  RefreshVcsTool(TAtlasVcsKind.Git);
  RefreshVcsTool(TAtlasVcsKind.Svn);
  FVcsProjects := TAtlasVcsProjects.Read(ASettings.VcsProjects);
  FVcsProjectSelected := -1;
  if Length(FVcsProjects) > 0 then
    FVcsProjectSelected := 0;
  RefreshVcsProjects;
  FWelcomeQuickActions.Checked := ASettings.WelcomePageQuickActions;
  Items := TAtlasWelcomeQuickActions.ParseItems(ASettings.WelcomePageQuickActionsItems);
  for mAction := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
    FWelcomeQuickActionsItems[mAction].Checked := mAction in Items;
  FWelcomeQuickActionsConsole.Text := ASettings.WelcomePageQuickActionsConsole;
  FWelcomeQuickActionsBuildKey.Text := ShortCutToText(TShortCut(ASettings.WelcomePageQuickActionsBuildKey));
  FWelcomeQuickActionsTestKey.Text := ShortCutToText(TShortCut(ASettings.WelcomePageQuickActionsTestKey));
  FWelcomeUnsaved.Checked := ASettings.WelcomePageUnsaved;
  FWelcomeUnsavedMinAge.Text := IntToStr(ASettings.WelcomePageUnsavedMinAgeHours);
  FWelcomeUnsavedWarn.Text := IntToStr(ASettings.WelcomePageUnsavedWarnHours);
  FWelcomeUnsavedAlert.Text := IntToStr(ASettings.WelcomePageUnsavedAlertHours);
  FWelcomeUnsavedHideClean.Checked := ASettings.WelcomePageUnsavedHideWhenClean;
  FWelcomeStatusTile.Checked := ASettings.WelcomePageStatusTile;
  FWelcomeStatusTileOnlyProblems.Checked := ASettings.WelcomePageStatusTileOnlyProblems;
  FWelcomeDiscover.Checked := ASettings.WelcomePageDiscover;
  FTipsUsageTracking.Checked := ASettings.TipsUsageTracking;
  FWelcomeHelp.Checked := ASettings.WelcomePageHelp;
  FWelcomeHelpReportUrl.Text := ASettings.WelcomePageHelpReportUrl;
  FWelcomeHelpReportFolder.Text := ASettings.WelcomePageHelpReportFolder;
  FWelcomeProjectSetup.Checked := ASettings.WelcomePageProjectSetup;
  FWelcomeNewFromTemplate.Checked := ASettings.WelcomePageNewFromTemplate;
  // Freies Layout (#767): die Häkchen der Bereiche stehen schon; das Modell liest sie aus ASettings.
  FWelcomeCustomLayout.Checked := ASettings.WelcomePageCustomLayout;
  FPageLayouts := TAtlasWelcomeCustomizing.Load(ASettings);
  ShowWelcomeLayouts(False);
  FSettingsExportImport.Checked := ASettings.SettingsExportImport;
  FSettingsMarkModified.Checked := ASettings.SettingsMarkModified;
  FSettingsBackupBeforeImport.Checked := ASettings.SettingsBackupBeforeImport;
  FSettingsExportSecrets.Choice := Ord(ASettings.SettingsExportSecrets = 'placeholder');
  RefreshFuse;
  RefreshIndex;
end;

procedure TAtlasSettingsPage.SaveTo(var ASettings: TAtlasPluginSettings);
var
  Shown: TAtlasTrendSeriesList;
  Series: TAtlasTrendSeries;
  Items: TAtlasQuickActions;
  mAction: TAtlasQuickAction;
  Kind: TAtlasOverviewKind;
  Kinds: TAtlasOverviewKinds;
  VisualizerKind: TAtlasVisualizerKind;
  StepFilterKind: TStepFilterKind;
  VisualizerKinds: TAtlasVisualizerKinds;
  StepFilterKinds: TStepFilterKinds;
  Target: TAtlasReassignedTarget;
  Targets: TAtlasReassignedTargets;
  mRules: TArray<TAtlasVcsExternalRule>;
  mInvalid: string;
begin
  ASettings.Enabled := FEnabled.Checked;
  ASettings.ServerPath := Trim(FServerPath.Text);
  ASettings.ActionsKey := Integer(TextToShortCut(Trim(FActionsKey.Text)));
  ASettings.ExpandKey := Integer(TextToShortCut(Trim(FExpandKey.Text)));
  ASettings.ShrinkKey := Integer(TextToShortCut(Trim(FShrinkKey.Text)));
  ASettings.ImplementationKey := Integer(TextToShortCut(Trim(FImplementationKey.Text)));
  ASettings.TypeDefinitionKey := Integer(TextToShortCut(Trim(FTypeDefinitionKey.Text)));
  ASettings.MethodToggle := FMethodToggle.Checked;
  ASettings.MethodToggleUpKey := Integer(TextToShortCut(Trim(FMethodToggleUpKey.Text)));
  ASettings.MethodToggleDownKey := Integer(TextToShortCut(Trim(FMethodToggleDownKey.Text)));
  ASettings.TestUnitKey := Integer(TextToShortCut(Trim(FTestUnitKey.Text)));
  ASettings.GotoInterfaceKey := Integer(TextToShortCut(Trim(FGotoInterfaceKey.Text)));
  ASettings.GotoImplementationKey := Integer(TextToShortCut(Trim(FGotoImplementationKey.Text)));
  ASettings.NavHistory := FNavHistory.Checked;
  ASettings.NavBackKey := Integer(TextToShortCut(Trim(FNavBackKey.Text)));
  ASettings.NavForwardKey := Integer(TextToShortCut(Trim(FNavForwardKey.Text)));
  ASettings.LastEditKey := Integer(TextToShortCut(Trim(FLastEditKey.Text)));
  ASettings.Peek := FPeek.Checked;
  ASettings.PeekHeightLines := StrToIntDef(FPeekHeightLines.Text, ASettings.PeekHeightLines);
  ASettings.PeekShowImplementation := FPeekShowImplementation.Checked;
  ASettings.DataFlow := FDataFlow.Checked;
  ASettings.DataFlowMaxDepth := StrToIntDef(FDataFlowMaxDepth.Text, ASettings.DataFlowMaxDepth);
  ASettings.DataFlowExcludeTests := FDataFlowExcludeTests.Checked;
  ASettings.PeekDefinitionKey := Integer(TextToShortCut(Trim(FPeekDefinitionKey.Text)));
  ASettings.PeekReferencesKey := Integer(TextToShortCut(Trim(FPeekReferencesKey.Text)));
  ASettings.ReferencesInferred := FReferencesInferred.Checked;
  ASettings.ReferencesTextMatches := FReferencesTextMatches.Checked;
  ASettings.CallHierarchyDiagram := FCallHierarchyDiagram.Checked;
  ASettings.Impact := FImpact.Checked;
  ASettings.ImpactDepth := StrToIntDef(FImpactDepth.Text, ASettings.ImpactDepth);
  ASettings.Outline := FOutline.Checked;
  ASettings.OutlineAlphabetical := FOutlineAlphabetical.Checked;
  ASettings.OutlineFollowCursor := FOutlineFollowCursor.Checked;
  ASettings.OutlineConditions := FOutlineConditions.Checked;
  ASettings.Breadcrumbs := FBreadcrumbs.Checked;
  ASettings.BreadcrumbsShowUnit := FBreadcrumbsShowUnit.Checked;
  ASettings.BreadcrumbsIdeColors := FBreadcrumbsIdeColors.Checked;
  ASettings.BreadcrumbsHideIdeToolbar := FBreadcrumbsHideIdeToolbar.Checked;
  ASettings.BreadcrumbsKey := Integer(TextToShortCut(Trim(FBreadcrumbsKey.Text)));
  ASettings.EditorToolbar := FEditorToolbar.Checked;
  ASettings.EditorToolbarPosition := AtlasToolbarPositions[EnsureRange(FEditorToolbarPosition.Choice, 0,
    High(AtlasToolbarPositions))];
  ASettings.EditorToolbarItems := TAtlasToolbarItems.Normalize(FEditorToolbarItems.Text);
  ASettings.EditorToolbarReturnButton := FEditorToolbarReturnButton.Checked;
  ASettings.EditorToolbarLabels := FEditorToolbarLabels.Checked;
  ASettings.EditorStatusBar := FEditorStatusBar.Checked;
  ASettings.EditorStatusBarItems := TAtlasStatusBarItems.Normalize(FEditorStatusBarItems.Text);
  ASettings.StickyScroll := FStickyScroll.Checked;
  ASettings.StickyScrollMaxLines := StrToIntDef(FStickyScrollMaxLines.Text, ASettings.StickyScrollMaxLines);
  ASettings.Minimap := FMinimap.Checked;
  ASettings.MinimapRender := 'blocks';
  if FMinimapRender.Choice = 1 then
    ASettings.MinimapRender := 'characters';
  ASettings.MinimapWidth := StrToIntDef(FMinimapWidth.Text, ASettings.MinimapWidth);
  ASettings.MinimapScale := StrToIntDef(FMinimapScale.Text, ASettings.MinimapScale);
  ASettings.MinimapMaxColumn := StrToIntDef(FMinimapMaxColumn.Text, ASettings.MinimapMaxColumn);
  ASettings.MinimapSide := 'right';
  if FMinimapSide.Choice = 1 then
    ASettings.MinimapSide := 'left';
  ASettings.MinimapShowSlider := 'always';
  if FMinimapShowSlider.Choice = 1 then
    ASettings.MinimapShowSlider := 'mouseover';
  ASettings.MinimapSectionHeaders := FMinimapSectionHeaders.Checked;
  ASettings.MinimapHighlightMethod := FMinimapHighlightMethod.Checked;
  ASettings.MinimapMarkers := FMinimapMarkers.Checked;
  ASettings.MinimapClickJumps := FMinimapClickJumps.Checked;
  ASettings.GitGutter := FGitGutter.Checked;
  ASettings.GitBlame := FGitBlame.Checked;
  ASettings.GutterColumn := FGutterColumn.Checked;
  ASettings.GutterColumnProblems := FGutterColumnProblems.Checked;
  ASettings.GutterColumnCodeActions := FGutterColumnCodeActions.Checked;
  ASettings.GutterColumnOverrides := FGutterColumnOverrides.Checked;
  ASettings.SelectionMatches := FSelectionMatches.Checked;
  ASettings.SelectionMatchesMinLength := StrToIntDef(FSelectionMatchesMinLength.Text,
    ASettings.SelectionMatchesMinLength);
  ASettings.SelectionMatchesCaseSensitive := FSelectionMatchesCaseSensitive.Checked;
  ASettings.SelectionMatchesWholeWord := FSelectionMatchesWholeWord.Checked;
  ASettings.SelectionMatchesNavigateF3 := FSelectionMatchesNavigateF3.Checked;
  ASettings.SelectionMatchesMaxMatches := StrToIntDef(FSelectionMatchesMaxMatches.Text,
    ASettings.SelectionMatchesMaxMatches);
  ASettings.ExitPoints := FExitPoints.Checked;
  ASettings.ExitPointsExceptions := FExitPointsExceptions.Checked;
  ASettings.ExitPointsLoops := FExitPointsLoops.Checked;
  ASettings.ExitPointsBadge := FExitPointsBadge.Checked;
  ASettings.Reassigned := FReassigned.Checked;
  Targets := [];
  for Target := Low(TAtlasReassignedTarget) to High(TAtlasReassignedTarget) do
    if FReassignedTargets[Target].Checked then
      Include(Targets, Target);
  ASettings.ReassignedTargets := TAtlasReassignedNames.TargetsText(Targets);
  ASettings.ReassignedStyle := TAtlasReassignedNames.Styles[TAtlasReassignedStyle(EnsureRange(
    FReassignedStyle.Choice, 0, Ord(High(TAtlasReassignedStyle))))];
  ASettings.ReassignedColor := TAtlasReassignedNames.NormalizeColor(FReassignedColor.Text);
  ASettings.ExpressionType := FExpressionType.Checked;
  ASettings.ExpressionTypeConversions := FExpressionTypeConversions.Checked;
  ASettings.ExpressionTypeConstValue := FExpressionTypeConstValue.Checked;
  ASettings.ExpressionTypeKey := Integer(TextToShortCut(Trim(FExpressionTypeKey.Text)));
  ASettings.MethodPlacement := AtlasMethodPlacements[EnsureRange(FMethodPlacement.Choice, 0,
    High(AtlasMethodPlacements))];
  ASettings.NextChangeKey := Integer(TextToShortCut(Trim(FNextChangeKey.Text)));
  ASettings.PreviousChangeKey := Integer(TextToShortCut(Trim(FPreviousChangeKey.Text)));
  ASettings.OverviewRuler := FOverviewRuler.Checked;
  Kinds := [];
  for Kind := Low(TAtlasOverviewKind) to High(TAtlasOverviewKind) do
    if FOverviewKinds[Kind].Checked then
      Include(Kinds, Kind);
  ASettings.OverviewRulerKinds := TAtlasOverview.KindsText(Kinds);
  ASettings.JumpToMatch := FJumpToMatch.Checked;
  ASettings.JumpToMatchKey := Integer(TextToShortCut(Trim(FJumpToMatchKey.Text)));
  ASettings.JumpToMatchSelectKey := Integer(TextToShortCut(Trim(FJumpToMatchSelectKey.Text)));
  ASettings.MoveLines := FMoveLines.Checked;
  ASettings.MoveLinesUpKey := Integer(TextToShortCut(Trim(FMoveLinesUpKey.Text)));
  ASettings.MoveLinesDownKey := Integer(TextToShortCut(Trim(FMoveLinesDownKey.Text)));
  ASettings.DuplicateLinesUpKey := Integer(TextToShortCut(Trim(FDuplicateLinesUpKey.Text)));
  ASettings.DuplicateLinesDownKey := Integer(TextToShortCut(Trim(FDuplicateLinesDownKey.Text)));
  ASettings.ToggleBlockComment := FToggleBlockComment.Checked;
  ASettings.ToggleBlockCommentKey := Integer(TextToShortCut(Trim(FToggleBlockCommentKey.Text)));
  ASettings.ToggleBlockCommentStyle := 'braces';
  if FToggleBlockCommentStyle.Choice = 1 then
    ASettings.ToggleBlockCommentStyle := 'parens';
  ASettings.ToggleBlockCommentFallback := 'lineComments';
  if FToggleBlockCommentFallback.Choice = 1 then
    ASettings.ToggleBlockCommentFallback := 'refuse';
  ASettings.ToggleBlockCommentOwnLines := FToggleBlockCommentOwnLines.Checked;
  ASettings.ToggleBlockCommentWithoutSelection := 'statement';
  if FToggleBlockCommentScope.Choice = 1 then
    ASettings.ToggleBlockCommentWithoutSelection := 'line';
  ASettings.NewLineAround := FNewLineAround.Checked;
  ASettings.NewLineBelowKey := Integer(TextToShortCut(Trim(FNewLineBelowKey.Text)));
  ASettings.NewLineAboveKey := Integer(TextToShortCut(Trim(FNewLineAboveKey.Text)));
  ASettings.NewLineAroundStatementAware := FNewLineAroundStatementAware.Checked;
  ASettings.Unwrap := FUnwrap.Checked;
  ASettings.UnwrapKey := Integer(TextToShortCut(Trim(FUnwrapKey.Text)));
  ASettings.SafeDelete := FSafeDelete.Checked;
  ASettings.SafeDeleteKey := Integer(TextToShortCut(Trim(FSafeDeleteKey.Text)));
  ASettings.ContinueComments := FContinueComments.Checked;
  ASettings.ContinueCommentsLineComments := FContinueCommentsLineComments.Checked;
  ASettings.ContinueCommentsLists := FContinueCommentsLists.Checked;
  // Leerraum am Rand gehört zum Präfix (' * ').
  ASettings.ContinueCommentsBlockPrefix := FContinueCommentsBlockPrefix.Text;
  ASettings.WrapSelection := FWrapSelection.Checked;
  ASettings.WrapSelectionChars := Trim(FWrapSelectionChars.Text);
  ASettings.CompleteStatement := FCompleteStatement.Checked;
  ASettings.CompleteStatementKey := Integer(TextToShortCut(Trim(FCompleteStatementKey.Text)));
  case FCompleteStatementBeginEnd.Choice of
    0:
      ASettings.CompleteStatementBeginEnd := TAtlasPluginSettings.BeginEndAlways;
    2:
      ASettings.CompleteStatementBeginEnd := TAtlasPluginSettings.BeginEndNever;
  else
    ASettings.CompleteStatementBeginEnd := TAtlasPluginSettings.BeginEndMultiLine;
  end;
  case FCompleteStatementTryKind.Choice of
    1:
      ASettings.CompleteStatementTryKind := TAtlasPluginSettings.TryKindExcept;
    2:
      ASettings.CompleteStatementTryKind := TAtlasPluginSettings.TryKindAsk;
  else
    ASettings.CompleteStatementTryKind := TAtlasPluginSettings.TryKindFinally;
  end;
  ASettings.CompleteStatementMethodBody := FCompleteStatementMethodBody.Checked;
  ASettings.FormatCode := FFormatCode.Checked;
  ASettings.FormatCodeKey := Integer(TextToShortCut(Trim(FFormatCodeKey.Text)));
  ASettings.ContinuePattern := FContinuePattern.Checked;
  ASettings.ContinuePatternMinLines := StrToIntDef(FContinuePatternMinLines.Text, ASettings.ContinuePatternMinLines);
  ASettings.MultiCursor := FMultiCursor.Checked;
  ASettings.LinkedEditing := FLinkedEditing.Checked;
  ASettings.SmartPaste := 'off';
  case FSmartPaste.Choice of
    1:
      ASettings.SmartPaste := 'uses';
    2:
      ASettings.SmartPaste := 'indent';
    3:
      ASettings.SmartPaste := 'both';
  end;
  ASettings.MultiCursorModifier := TAtlasPluginSettings.MultiCursorModifierAlt;
  if FMultiCursorModifier.Choice = 1 then
    ASettings.MultiCursorModifier := TAtlasPluginSettings.MultiCursorModifierCtrl;
  ASettings.MultiCursorNextKey := Integer(TextToShortCut(Trim(FMultiCursorNextKey.Text)));
  ASettings.MultiCursorSkipKey := Integer(TextToShortCut(Trim(FMultiCursorSkipKey.Text)));
  ASettings.MultiCursorLineEndsKey := Integer(TextToShortCut(Trim(FMultiCursorLineEndsKey.Text)));
  ASettings.MultiCursorAboveKey := Integer(TextToShortCut(Trim(FMultiCursorAboveKey.Text)));
  ASettings.MultiCursorBelowKey := Integer(TextToShortCut(Trim(FMultiCursorBelowKey.Text)));
  ASettings.BookmarkKey := Integer(TextToShortCut(Trim(FBookmarkKey.Text)));
  ASettings.NextBookmarkKey := Integer(TextToShortCut(Trim(FNextBookmarkKey.Text)));
  ASettings.PreviousBookmarkKey := Integer(TextToShortCut(Trim(FPreviousBookmarkKey.Text)));
  ASettings.HideElementKey := Integer(TextToShortCut(Trim(FHideElementKey.Text)));
  ASettings.NextProblemKey := Integer(TextToShortCut(Trim(FNextProblemKey.Text)));
  ASettings.PreviousProblemKey := Integer(TextToShortCut(Trim(FPreviousProblemKey.Text)));
  ASettings.ProblemsWindowKey := Integer(TextToShortCut(Trim(FProblemsWindowKey.Text)));
  ASettings.CreateIssueKey := Integer(TextToShortCut(Trim(FCreateIssueKey.Text)));
  ASettings.UndoKey := Integer(TextToShortCut(Trim(FUndoKey.Text)));
  ASettings.RedoKey := Integer(TextToShortCut(Trim(FRedoKey.Text)));
  ASettings.UpdatesCheck := FUpdatesCheck.Checked;
  ASettings.BugReportAnonymize := FBugReportAnonymize.Checked;
  ASettings.EditorKeysPriority := FEditorKeysPriority.Checked;
  ASettings.SlashCommands := FSlashCommands.Checked;
  ASettings.GenerateMenu := FGenerateMenu.Checked;
  ASettings.GenerateMenuKey := Integer(TextToShortCut(Trim(FGenerateMenuKey.Text)));
  ASettings.NotificationsKey := Integer(TextToShortCut(Trim(FNotificationsKey.Text)));
  ASettings.GenerateMenuGroups := Trim(FGenerateMenuGroups.Text);
  ASettings.GenerateMenuHidden := Trim(FGenerateMenuHidden.Text);
  ASettings.GenerateMenuRecentFirst := FGenerateMenuRecentFirst.Checked;
  ASettings.GenerateMenuShowCommandNames := FGenerateMenuShowCommandNames.Checked;
  ASettings.VisibleRows := FRowsUpDown.Position;
  ASettings.PanelCollapsed := FPanelCollapsed.Checked;
  ASettings.SelectionMarker := FSelectionMarker.Checked;
  ASettings.AutoParentheses := FAutoParentheses.Checked;
  ASettings.FixCase := FFixCase.Checked;
  ASettings.CommitCharacters := FCommitChars.Checked;
  ASettings.AutoUses := FAutoUses.Checked;
  ASettings.ParameterHints := FParameterHints.Checked;
  ASettings.FormatPlaceholders := FFormatPlaceholders.Checked;
  ASettings.OpenDelayMs := StrToIntDef(FOpenDelay.Text, ASettings.OpenDelayMs);
  ASettings.FilterChips := FFilterChips.Checked;
  ASettings.Learning := FLearning.Checked;
  ASettings.Favorites := FFavorites.Checked;
  ASettings.GroupInherited := FGroupInherited.Checked;
  ASettings.CompletionVariantBranch := FCompletionVariantBranch.Checked;
  if (FListMode.Choice >= Ord(Low(TAtlasListMode))) and (FListMode.Choice <= Ord(High(TAtlasListMode))) then
    ASettings.CompletionListMode := TAtlasListModes.ModeNames[TAtlasListMode(FListMode.Choice)];
  if (FListScope.Choice >= Ord(Low(TAtlasListScope))) and (FListScope.Choice <= Ord(High(TAtlasListScope))) then
    ASettings.CompletionListScope := TAtlasListModes.ScopeNames[TAtlasListScope(FListScope.Choice)];
  ASettings.Preview := FPreview.Checked;
  ASettings.Snippets := FSnippets.Checked;
  ASettings.ImportIdeTemplates := FImportIdeTemplates.Checked;
  ASettings.TeamFile := FTeamFile.Checked;
  ASettings.HoverTooltip := FHoverTooltip.Checked;
  ASettings.HoverProblemActions := FHoverProblemActions.Checked;
  ASettings.XmlDocExpand := TAtlasDocDisplay.ExpandName(TAtlasDocExpand(EnsureRange(FXmlDocExpand.Choice, 0, 2)));
  ASettings.XmlDocMaxLines := StrToIntDef(FXmlDocMaxLines.Text, ASettings.XmlDocMaxLines);
  ASettings.HangThresholdMs := StrToIntDef(FHangThreshold.Text, ASettings.HangThresholdMs);
  ASettings.ProviderTimeLimitMs := StrToIntDef(FProviderTimeLimit.Text, ASettings.ProviderTimeLimitMs);
  ASettings.HangHint := FHangHint.Checked;
  ASettings.ReloadExternal := FReloadExternal.Checked;
  ASettings.OpenForEdits := FOpenForEdits.Checked;
  ASettings.PairColors := FPairColors.Checked;
  ASettings.InactiveDim := FInactiveDim.Checked;
  ASettings.InlayHints := FInlayHints.Checked;
  ASettings.InlayTypeHints := FInlayTypeHints.Checked;
  ASettings.InlayDefineHints := FInlayDefineHints.Checked;
  ASettings.InlayCharHints := FInlayCharHints.Checked;
  ASettings.InlayMethodHints := FInlayMethodHints.Checked;
  ASettings.BlockEndLabels := FBlockEndLabels.Checked;
  ASettings.BlockEndLabelsMinLines := StrToIntDef(FBlockEndLabelsMinLines.Text, ASettings.BlockEndLabelsMinLines);
  ASettings.DimUnusedUses := FDimUnusedUses.Checked;
  ASettings.RecursionMarkers := FRecursionMarkers.Checked;
  ASettings.RecursionMarkersDepth := StrToIntDef(FRecursionMarkersDepth.Text, ASettings.RecursionMarkersDepth);
  ASettings.InlineDiagnostics := TAtlasInlineDiagnostics.ModeName(
    TAtlasInlineDiagnosticsMode(EnsureRange(FInlineDiagnostics.Choice, 0, Ord(High(TAtlasInlineDiagnosticsMode)))));
  ASettings.Notes := FNotes.Checked;
  ASettings.BookmarksNamed := FBookmarksNamed.Checked;
  ASettings.BookmarksShared := FBookmarksShared.Checked;
  ASettings.QuickBookmarks := FQuickBookmarks.Checked;
  ASettings.QuickBookmarksGutter := FQuickBookmarksGutter.Checked;
  ASettings.QuickBookmarksGutterClick := FQuickBookmarksGutterClick.Checked;
  ASettings.QuickBookmarksNumberedKeys := FQuickBookmarksNumberedKeys.Checked;
  ASettings.QuickBookmarkKey := Integer(TextToShortCut(Trim(FQuickBookmarkKey.Text)));
  ASettings.QuickBookmarkChordWait := EnsureRange(StrToIntDef(Trim(FQuickBookmarkChordWait.Text),
    ASettings.QuickBookmarkChordWait), 0, TAtlasPluginSettings.MaxQuickChordWait);
  ASettings.QuickBookmarksScope := AtlasQuickBookmarkScopes[EnsureRange(FQuickBookmarksScope.Choice, 0,
    High(AtlasQuickBookmarkScopes))];
  ASettings.QuickBookmarksImportIde := FQuickBookmarksImportIde.Checked;
  ASettings.CodeLensTestUnit := FCodeLensTestUnit.Checked;
  ASettings.CodeLensMetrics := FCodeLensMetrics.Checked;
  ASettings.Metrics := FMetrics.Checked;
  ASettings.CodeLensTests := FCodeLensTests.Checked;
  ASettings.TodoList := FTodoList.Checked;
  ASettings.BaselineUpdate := FBaselineUpdate.Checked;
  ASettings.MetricsReport := FMetricsReport.Checked;
  ASettings.DfmPropertyRules := FDfmPropertyRules.Checked;
  ASettings.PairGuides := FPairGuides.Checked;
  ASettings.PairOwners := FPairOwners.Checked;
  ASettings.PairGuideWidth := StrToIntDef(FPairGuideWidth.Text, ASettings.PairGuideWidth);
  ASettings.PairGuideOpacity := StrToIntDef(FPairGuideOpacity.Text, ASettings.PairGuideOpacity);
  ASettings.PairColorsLight := PairsSetting(FLightSwatches, TAtlasColors.Light.Pairs);
  ASettings.PairColorsDark := PairsSetting(FDarkSwatches, TAtlasColors.Dark.Pairs);
  ASettings.Problems := FProblems.Checked;
  ASettings.ProblemsList := FProblemsList.Checked;
  ASettings.ProblemsWindow := FProblemsWindow.Checked;
  if (FProblemsWindowScope.Choice >= 0) and (FProblemsWindowScope.Choice <= High(ScopeValues)) then
    ASettings.ProblemsWindowScope := ScopeValues[FProblemsWindowScope.Choice];
  if (FProblemsWindowGroupBy.Choice >= 0) and (FProblemsWindowGroupBy.Choice <= High(GroupByValues)) then
    ASettings.ProblemsWindowGroupBy := GroupByValues[FProblemsWindowGroupBy.Choice];
  ASettings.ProblemsWindowCompiler := FProblemsWindowCompiler.Checked;
  ASettings.ProblemsWindowFollowCursor := FProblemsWindowFollowCursor.Checked;
  ASettings.ProblemsWindowOpenFirst := FProblemsWindowOpenFirst.Checked;
  if (FProblemsWindowClosedUnits.Choice >= 0) and (FProblemsWindowClosedUnits.Choice <= High(ClosedUnitsValues)) then
    ASettings.ProblemsWindowClosedUnits := ClosedUnitsValues[FProblemsWindowClosedUnits.Choice];
  ASettings.ProblemsWindowShowCleanActive := FProblemsWindowShowCleanActive.Checked;
  if (FProblemsCompilerMerge.Choice >= 0) and (FProblemsCompilerMerge.Choice <= High(CompilerMergeValues)) then
    ASettings.ProblemsCompilerMerge := CompilerMergeValues[FProblemsCompilerMerge.Choice];
  ASettings.ProblemsShowCompilerCode := FProblemsShowCompilerCode.Checked;
  ASettings.ProblemsLive := FProblemsLive.Checked;
  ASettings.ProblemsStatusCounter := FProblemsStatusCounter.Checked;
  ASettings.StatusField := FStatusField.Checked;
  ASettings.DiagnosticMode := FDiagnosticMode.Checked;
  ASettings.DiagnosticsProcesses := FDiagnosticsProcesses.Checked;
  ASettings.ArchitectureEnabled := FArchitecture.Checked;
  if FArchitectureScope.Choice = 1 then
    ASettings.ArchitectureScope := 'project'
  else
    ASettings.ArchitectureScope := 'projectGroup';
  ASettings.ArchitectureIncludeLibraryUnits := FArchitectureLibrary.Checked;
  ASettings.ArchitectureCentralUnits := StrToIntDef(FArchitectureCentral.Text, ASettings.ArchitectureCentralUnits);
  ASettings.ExperimentalEnabled := FExperimentalEnabled.Checked;
  ASettings.SetupChecklist := FSetupChecklist.Checked;
  ASettings.ShortcutTips := FShortcutTips.Checked;
  ASettings.ShortcutTipsScope := TAtlasShortcutTips.ScopeName(TAtlasTipScope(EnsureRange(FShortcutTipsScope.Choice,
    Ord(Low(TAtlasTipScope)), Ord(High(TAtlasTipScope)))));
  ASettings.Notifications := FNotifications.Checked;
  ASettings.NotificationsMaxEntries := StrToIntDef(Trim(FNotificationsMax.Text), ASettings.NotificationsMaxEntries);
  ASettings.NotificationsSources := TAtlasNotificationSources.Normalize(FNotificationsSpec);
  ASettings.StatusFieldSummary := FStatusSummary.Checked;
  case FStatusToggles.Choice of
    1:
      ASettings.StatusFieldToggles := 'rightClick';
    2:
      ASettings.StatusFieldToggles := 'doubleClick';
  else
    ASettings.StatusFieldToggles := 'both';
  end;
  case FIndexProgress.Choice of
    1:
      ASettings.IndexProgressPlace := 'menu';
    2:
      ASettings.IndexProgressPlace := 'off';
  else
    ASettings.IndexProgressPlace := 'statusField';
  end;
  ASettings.StatusFieldHidden := Trim(FStatusHidden.Text);
  ASettings.IndexProjectGroup := FIndexGroup.Checked;
  ASettings.IndexSearchPaths := FIndexSearch.Checked;
  ASettings.IndexLibraryPaths := FIndexLibrary.Checked;
  ASettings.IndexUsages := FIndexUsages.Checked;
  ASettings.MemoryBudgetMb := StrToIntDef(FMemoryBudget.Text, ASettings.MemoryBudgetMb);
  ASettings.CheckOnSave := FAfterSave.Choice = 1;
  ASettings.CompileOnSave := FAfterSave.Choice = 2;
  ASettings.CheckOnSaveDelayMs := StrToIntDef(FCheckDelay.Text, ASettings.CheckOnSaveDelayMs);
  ASettings.CheckOnSaveMaxMs := StrToIntDef(FCheckMax.Text, ASettings.CheckOnSaveMaxMs);
  ASettings.McpBuild := FMcpBuild.Checked;
  SaveOpenBuild(ASettings);
  SaveTasks(ASettings);
  ASettings.TestRun := FTestRun.Checked;
  ASettings.TestsBuildFirst := FTestsBuildFirst.Checked;
  ASettings.TestsAfterBuild := FTestsAfterBuild.Checked;
  ASettings.BuildZeroHints := FBuildZeroHints.Checked;
  ASettings.ShowInterfaceCost := FShowInterfaceCost.Checked;
  ASettings.BuildSummary := FBuildSummary.Checked;
  // Ungültige Einträge fallen weg; gespeichert wird die einheitliche Form „W1035, H2164“.
  ASettings.BuildWarningsAsErrors := TAtlasBuildVerdicts.NormalizeCodes(FBuildWarningsAsErrors.Text);
  if (FBuildGate.Choice >= Ord(Low(TAtlasBuildGate))) and (FBuildGate.Choice <= Ord(High(TAtlasBuildGate))) then
    ASettings.BuildGate := TAtlasReleaseGuard.GateNames[TAtlasBuildGate(FBuildGate.Choice)];
  ASettings.BuildGateTimeoutMs := EnsureRange(StrToIntDef(FBuildGateTimeout.Text, ASettings.BuildGateTimeoutMs),
    TAtlasBuildGateCheck.MinTimeoutMs, TAtlasBuildGateCheck.MaxTimeoutMs);
  ASettings.BuildCompilerSwitches := FBuildCompilerSwitches.Checked;
  ASettings.BuildSwitchesInStatusBar := FBuildSwitchesInStatusBar.Checked;
  SaveRelease(ASettings);
  ASettings.StartProfiles := FStartProfiles.Checked;
  ASettings.StartProfilesStatusField := FStartProfilesStatusField.Checked;
  ASettings.TestDebug := FTestDebug.Checked;
  ASettings.TestBreakAtStart := FTestBreakAtStart.Checked;
  ASettings.DebugHoverValues := FDebugHoverValues.Checked;
  ASettings.DebugVisualizers := FDebugVisualizers.Checked;
  VisualizerKinds := [];
  for VisualizerKind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
    if FDebugVisualizerKinds[VisualizerKind].Checked then
      Include(VisualizerKinds, VisualizerKind);
  ASettings.DebugVisualizerTypes := TAtlasVisualizerSettings.KindsText(VisualizerKinds);
  ASettings.DebugVisualizerNameFields := TAtlasVisualizerSettings.NormalizeNameFields(FDebugVisualizerNameFields.Text);
  ASettings.DebugVisualizerMaxLength := StrToIntDef(Trim(FDebugVisualizerMaxLength.Text),
    ASettings.DebugVisualizerMaxLength);
  ASettings.DebugVisualizerTimeoutMs := StrToIntDef(Trim(FDebugVisualizerTimeout.Text),
    ASettings.DebugVisualizerTimeoutMs);
  ASettings.DebugVisualizerMaxImagePixels := StrToIntDef(Trim(FDebugVisualizerMaxImagePixels.Text),
    ASettings.DebugVisualizerMaxImagePixels);
  ASettings.DebugVisualizerEvaluation := TAtlasVisualizerSettings.EvaluationNames[TAtlasVisualizerEvaluation(
    EnsureRange(FDebugVisualizerEvaluation.Choice, 0, Ord(High(TAtlasVisualizerEvaluation))))];
  ASettings.DebugDisplayRules := FDebugDisplayRules.Checked;
  ASettings.DebugDisplayRulesAllowCalls := FDebugDisplayRulesAllowCalls.Checked;
  ASettings.DebugStepIntoTarget := FDebugStepIntoTarget.Checked;
  ASettings.DebugStepFilters := FDebugStepFilters.Checked;
  StepFilterKinds := [];
  for StepFilterKind := Low(TStepFilterKind) to High(TStepFilterKind) do
    if FDebugStepFilterKinds[StepFilterKind].Checked then
      Include(StepFilterKinds, StepFilterKind);
  ASettings.DebugStepFilterKinds := TStepFilterNames.KindsText(StepFilterKinds);
  ASettings.DebugStepFilterPatterns := TStepFilterNames.NormalizePatterns(FDebugStepFilterPatterns.Text);
  ASettings.DebugStepIntoTargetKey := Integer(TextToShortCut(Trim(FDebugStepIntoTargetKey.Text)));
  ASettings.DebugBreakOnNextEvent := FDebugBreakOnNextEvent.Checked;
  ASettings.DebugBreakOnNextEventExcluded := TAtlasEventBreakSettings.NormalizeExcluded(FDebugBreakOnNextEventExcluded.Text);
  ASettings.DebugExplainUnavailable := FDebugExplainUnavailable.Checked;
  ASettings.DebugCompletionInDialogs := FDebugCompletionInDialogs.Checked;
  ASettings.DebugEvaluateWindow := FDebugEvaluateWindow.Checked;
  ASettings.DebugEvaluateReplaceCtrlF7 := FDebugEvaluateReplaceCtrlF7.Checked;
  ASettings.DebugExplainAccessViolation := FDebugExplainAccessViolation.Checked;
  ASettings.DebugExplainAccessViolationAllowCalls := FDebugExplainAccessViolationAllowCalls.Checked;
  ASettings.DebugExceptionHistory := FDebugExceptionHistory.Checked;
  ASettings.DebugJustMyCode := FDebugJustMyCode.Checked;
  ASettings.DebugExceptionBanner := FDebugExceptionBanner.Checked;
  ASettings.DebugExceptionBannerIgnoreAtLocation := FDebugExceptionBannerIgnoreAtLocation.Checked;
  ASettings.DebugInlineValues := FDebugInlineValues.Checked;
  ASettings.DebugInlineValuesPerLine := StrToIntDef(FDebugInlineValuesPerLine.Text, ASettings.DebugInlineValuesPerLine);
  ASettings.DebugOwnCodeFolders := TAtlasDebugOwnCode.FoldersText(TAtlasDebugOwnCode.ParseFolders(
    FDebugOwnCodeFolders.Text));
  ASettings.SafeAskAfterCrash := FSafeAsk.Checked;
  ASettings.SafeAutoAfterRepeatedCrash := FSafeAuto.Checked;
  case FSafeKey.Choice of
    1:
      ASettings.SafeStartupKey := TAtlasSafeMode.KeyText(TAtlasStartupKey.Ctrl);
    2:
      ASettings.SafeStartupKey := TAtlasSafeMode.KeyText(TAtlasStartupKey.None);
  else
    ASettings.SafeStartupKey := TAtlasSafeMode.KeyText(TAtlasStartupKey.Shift);
  end;
  ASettings.SafeStartupTimeoutMs := StrToIntDef(FSafeTimeout.Text, ASettings.SafeStartupTimeoutMs);
  ASettings.SafeKeepSettingsHistory := StrToIntDef(FSafeHistory.Text, ASettings.SafeKeepSettingsHistory);
  ASettings.UndoMultiFile := FUndoEnabled.Checked;
  ASettings.UndoMultiFileDepth := StrToIntDef(FUndoDepth.Text, ASettings.UndoMultiFileDepth);
  ASettings.UndoMultiFilePersist := FUndoPersist.Checked;
  ASettings.UndoMultiFileMaxSizeMb := StrToIntDef(FUndoMaxSize.Text, ASettings.UndoMultiFileMaxSizeMb);
  ASettings.UndoMultiFileOnConflict := TAtlasUndoNames.ConflictModeName(TAtlasUndoConflictMode(
    Max(0, FUndoOnConflict.Choice)));
  ASettings.UndoMultiFileNewFiles := TAtlasUndoNames.NewFilesName(TAtlasNewFilesMode(Max(0, FUndoNewFiles.Choice)));
  ASettings.UnitSearchEnabled := FUnitSearchEnabled.Checked;
  ASettings.UnitSearchReplaceIdeDialog := FUnitSearchReplace.Checked;
  ASettings.UnitSearchReplaceUseUnitDialog := FUnitSearchReplaceUseUnit.Checked;
  ASettings.UnitSearchReplaceFormsDialog := FUnitSearchReplaceForms.Checked;
  ASettings.UnitSearchKey := Integer(TextToShortCut(Trim(FUnitSearchKey.Text)));
  ASettings.UnitSearchPathStyle := UnitSearchPathStyles[EnsureRange(FUnitSearchPathStyle.Choice, 0, 2)];
  ASettings.UnitSearchGroupBy := UnitSearchGroupings[EnsureRange(FUnitSearchGroupBy.Choice, 0, 2)];
  ASettings.UnitSearchRememberCollapsed := FUnitSearchRememberCollapsed.Checked;
  ASettings.UnitSearchFilters := FUnitSearchFilters.Checked;
  ASettings.UnitSearchDefaultScope := UnitSearchScopes[EnsureRange(FUnitSearchDefaultScope.Choice, 0, 3)];
  ASettings.UnitSearchFilterSyntax := FUnitSearchFilterSyntax.Checked;
  ASettings.UnitSearchPreview := FUnitSearchPreview.Checked;
  ASettings.UnitSearchPreviewForm := FUnitSearchPreviewForm.Checked;
  ASettings.UnitSearchPreviewUsedBy := FUnitSearchPreviewUsedBy.Checked;
  ASettings.UnitSearchPreviewAutoCollapse := FUnitSearchPreviewAutoCollapse.Checked;
  ASettings.UnitSearchMultiSelect := FUnitSearchMultiSelect.Checked;
  ASettings.UnitSearchActions := FUnitSearchActions.Checked;
  ASettings.UnitSearchActionsAddUses := FUnitSearchAddUses.Checked;
  ASettings.QuickOpen := FQuickOpen.Checked;
  ASettings.QuickOpenLibrary := FQuickOpenLibrary.Checked;
  ASettings.QuickOpenKey := Integer(TextToShortCut(Trim(FQuickOpenKey.Text)));
  ASettings.SearchReplaceIde := FSearchReplace.Checked;
  ASettings.SearchResultsInMessages := FSearchMessages.Checked;
  ASettings.SearchReplace := FSearchReplaceBar.Checked;
  ASettings.SearchRegex := FSearchRegex.Checked;
  ASettings.SearchHistory := StrToIntDef(FSearchHistory.Text, ASettings.SearchHistory);
  ASettings.SearchMultiFile := FSearchMultiFile.Checked;
  ASettings.WelcomePage := FWelcomeEnabled.Checked;
  ASettings.WelcomePageOpenOnStart := FWelcomeOpenOnStart.Checked;
  ASettings.WelcomePageOpenWhenNoProject := FWelcomeOpenWhenNoProject.Checked;
  ASettings.WelcomePageHeader := FWelcomeHeader.Checked;
  ASettings.WelcomePageGreeting := FWelcomeGreeting.Checked;
  ASettings.WelcomePageSearch := FWelcomeSearch.Checked;
  ASettings.WelcomePageSearchSymbols := FWelcomeSearchSymbols.Checked;
  ASettings.WelcomePageSearchKey := Integer(TextToShortCut(Trim(FWelcomeSearchKey.Text)));
  ASettings.WelcomePageWhatsNew := TAtlasWhatsNew.ModeName(TAtlasWhatsNewMode(EnsureRange(FWelcomeWhatsNew.Choice,
    Ord(Low(TAtlasWhatsNewMode)), Ord(High(TAtlasWhatsNewMode)))));
  ASettings.WelcomePageContinue := FWelcomeContinue.Checked;
  ASettings.WelcomePageContinueCount := StrToIntDef(Trim(FWelcomeContinueCount.Text),
    ASettings.WelcomePageContinueCount);
  ASettings.WelcomePageContinueIncoming := FWelcomeContinueIncoming.Checked;
  ASettings.WelcomePageContinueFetch := FWelcomeContinueFetch.Checked;
  ASettings.WelcomePageSaved := FWelcomeSaved.Checked;
  ASettings.WelcomePageProjectStatus := FWelcomeProjects.Checked;
  ASettings.WelcomePageMaxProjects := StrToIntDef(Trim(FWelcomeMaxProjects.Text), ASettings.WelcomePageMaxProjects);
  ASettings.WelcomePageRefreshVcs := FWelcomeRefreshVcs.Checked;
  ASettings.WelcomePageTrends := FWelcomeTrends.Checked;
  ASettings.WelcomePageTrendsPoints := StrToIntDef(Trim(FWelcomeTrendsPoints.Text),
    ASettings.WelcomePageTrendsPoints);
  Shown := nil;
  for Series := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
    if FWelcomeTrendsSeries[Series].Checked then
      Shown := Shown + [Series];
  ASettings.WelcomePageTrendsSeries := TAtlasWelcomeTrends.SeriesText(Shown);
  ASettings.WelcomePageTests := FWelcomeTests.Checked;
  ASettings.WelcomePageTestsMaxFailures := StrToIntDef(Trim(FWelcomeTestsMaxFailures.Text),
    ASettings.WelcomePageTestsMaxFailures);
  ASettings.WelcomePageTestsCi := FWelcomeTestsCi.Checked;
  ASettings.WelcomePageTestsCiProvider := TAtlasPluginSettings.DefaultCiProvider;
  ASettings.WelcomePageTestsCiIntervalMinutes := StrToIntDef(Trim(FWelcomeTestsCiInterval.Text),
    ASettings.WelcomePageTestsCiIntervalMinutes);
  ASettings.WelcomePageTestsCiNotify := FWelcomeTestsCiNotify.Checked;
  ASettings.CiLogin := FCiLogin.Checked;
  ASettings.WelcomePageIssues := FWelcomeIssues.Checked;
  case FIssuesTracker.Choice of
    1:
      ASettings.IssuesTracker := 'github';
    2:
      ASettings.IssuesTracker := 'youtrack';
  else
    ASettings.IssuesTracker := '';
  end;
  if FIssuesStart.Choice = 1 then
    ASettings.IssuesStart := TAtlasPluginSettings.IssuesStartRemember
  else
    ASettings.IssuesStart := TAtlasPluginSettings.IssuesStartBranch;
  ASettings.IssuesBranchPattern := Trim(FIssuesBranchPattern.Text);
  ASettings.IssuesBranchBase := Trim(FIssuesBranchBase.Text);
  // Nicht gekürzt: Das Leerzeichen am Ende von "{kennung} " trennt Kennung und Nachricht.
  ASettings.IssuesCommitPattern := FIssuesCommitPattern.Text;
  ASettings.TrackerLogin := FTrackerLogin.Checked;
  ASettings.IssuesPreview := FIssuesPreview.Checked;
  ASettings.IssuesPreviewComments := FIssuesPreviewComments.Checked;
  ASettings.IssuesCodeLinks := FIssuesCodeLinks.Checked;
  ASettings.IssuesBlameLinks := FIssuesBlameLinks.Checked;
  ASettings.IssuesBlameMaxRevisions := StrToIntDef(FIssuesBlameMaxRevisions.Text, ASettings.IssuesBlameMaxRevisions);
  ASettings.IssuesSyncState := FIssuesSyncState.Checked;
  ASettings.IssuesStateField := FIssuesStateField.Value;
  ASettings.IssuesAssigneeField := FIssuesAssigneeField.Value;
  ASettings.IssuesStartState := FIssuesStartState.Value;
  ASettings.IssuesAssignOnStart := FIssuesAssignOnStart.Checked;
  ASettings.IssuesStartComment := FIssuesStartComment.Text;
  ASettings.IssuesEndStates := TAtlasTrackerWorkflow.ListText(TAtlasTrackerWorkflow.ParseList(FIssuesEndStates.Text));
  ASettings.IssuesEndComment := FIssuesEndComment.Text;
  ASettings.IssuesTimeTracking := FIssuesTimeTracking.Checked;
  ASettings.IssuesIdleMinutes := StrToIntDef(Trim(FIssuesIdleMinutes.Text), ASettings.IssuesIdleMinutes);
  ASettings.IssuesTimeRounding := StrToIntDef(Trim(FIssuesTimeRounding.Text), ASettings.IssuesTimeRounding);
  ASettings.IssuesPreviewChecklists := FIssuesPreviewChecklists.Checked;
  ASettings.IssuesChecklistStatus := FIssuesChecklistStatus.Checked;
  ASettings.IssuesConnections := TrackerConnectionsJson;
  ASettings.IssuesProjects := TrackerProjectsJson;
  ASettings.IssuesQueries := TrackerQueriesJson;
  ASettings.IssuesQueryPicker := FIssuesQueryPicker.Checked;
  ASettings.IssuesCreate := FIssuesCreate.Checked;
  ASettings.IssuesCreateIncludeCode := FIssuesCreateIncludeCode.Checked;
  case FVcsProvider.Choice of
    1:
      ASettings.VcsProvider := 'git';
    2:
      ASettings.VcsProvider := 'svn';
    3:
      ASettings.VcsProvider := 'off';
  else
    ASettings.VcsProvider := 'auto';
  end;
  ASettings.VcsGitPath := Trim(FVcsPaths[TAtlasVcsKind.Git].Text);
  ASettings.VcsSvnPath := Trim(FVcsPaths[TAtlasVcsKind.Svn].Text);
  ASettings.VcsTimeoutSeconds := StrToIntDef(FVcsTimeout.Text, ASettings.VcsTimeoutSeconds);
  ASettings.VcsBranchConfirm := FVcsBranchConfirm.Checked;
  ASettings.VcsBranchSvnLocation := Trim(FVcsBranchSvnLocation.Text);
  if FVcsBranchSvnSource.Choice = Ord(TAtlasVcsSvnSource.WorkingCopy) then
    ASettings.VcsBranchSvnSource := 'workingCopy'
  else
    ASettings.VcsBranchSvnSource := 'head';
  case FVcsBranchSvnAfter.Choice of
    Ord(TAtlasVcsSvnAfter.Checkout):
      ASettings.VcsBranchSvnAfter := 'checkout';
    Ord(TAtlasVcsSvnAfter.None):
      ASettings.VcsBranchSvnAfter := 'none';
  else
    ASettings.VcsBranchSvnAfter := 'switch';
  end;
  ASettings.VcsBranchSvnCheckoutFolder := Trim(FVcsBranchSvnFolder.Text);
  ASettings.VcsBranchSvnMessage := Trim(FVcsBranchSvnMessage.Text);
  case FVcsExternalsOnBranch.Choice of
    1:
      ASettings.VcsExternalsOnBranch := 'keep';
    2:
      ASettings.VcsExternalsOnBranch := 'ask';
  else
    ASettings.VcsExternalsOnBranch := 'pin';
  end;
  case FVcsExternalsSuggest.Choice of
    1:
      ASettings.VcsExternalsSuggestBranch := 'never';
    2:
      ASettings.VcsExternalsSuggestBranch := 'always';
  else
    ASettings.VcsExternalsSuggestBranch := 'modified';
  end;
  // Mit ungültiger Zeile bleiben die bisherigen Regeln (Hinweis unter dem Feld).
  if TAtlasVcsBranchPlan.RulesOfText(FVcsExternalsRules.Text, mRules, mInvalid) then
    ASettings.VcsExternalsRules := TAtlasVcsBranchPlan.RulesJson(mRules);
  ASettings.VcsExternalsShow := FVcsExternalsShow.Checked;
  case FVcsExternalsUpdate.Choice of
    1:
      ASettings.VcsExternalsUpdate := 'without';
    2:
      ASettings.VcsExternalsUpdate := 'ask';
  else
    ASettings.VcsExternalsUpdate := 'with';
  end;
  ASettings.VcsBranchGitBase := cVcsGitBases[EnsureRange(FVcsBranchGitBase.Choice, 0, High(cVcsGitBases))];
  ASettings.VcsBranchGitPush := cVcsGitPushes[EnsureRange(FVcsBranchGitPush.Choice, 0, High(cVcsGitPushes))];
  ASettings.VcsBranchGitUncommitted := cVcsGitUncommitted[EnsureRange(FVcsBranchGitUncommitted.Choice, 0,
    High(cVcsGitUncommitted))];
  ASettings.VcsBranchGitWorktree := FVcsBranchGitWorktree.Checked;
  ASettings.VcsBranchGitWorktreeFolder := Trim(FVcsBranchGitWorktreeFolder.Text);
  ASettings.VcsProjects := VcsProjectsJson;
  ASettings.WelcomePageQuickActions := FWelcomeQuickActions.Checked;
  Items := [];
  for mAction := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
    if FWelcomeQuickActionsItems[mAction].Checked then
      Include(Items, mAction);
  ASettings.WelcomePageQuickActionsItems := TAtlasWelcomeQuickActions.ItemsText(Items);
  ASettings.WelcomePageQuickActionsConsole := TAtlasWelcomeQuickActions.NormalizedConsole(
    FWelcomeQuickActionsConsole.Text);
  ASettings.WelcomePageQuickActionsBuildKey := Integer(TextToShortCut(Trim(FWelcomeQuickActionsBuildKey.Text)));
  ASettings.WelcomePageQuickActionsTestKey := Integer(TextToShortCut(Trim(FWelcomeQuickActionsTestKey.Text)));
  ASettings.WelcomePageUnsaved := FWelcomeUnsaved.Checked;
  ASettings.WelcomePageUnsavedMinAgeHours := StrToIntDef(Trim(FWelcomeUnsavedMinAge.Text),
    ASettings.WelcomePageUnsavedMinAgeHours);
  ASettings.WelcomePageUnsavedWarnHours := StrToIntDef(Trim(FWelcomeUnsavedWarn.Text),
    ASettings.WelcomePageUnsavedWarnHours);
  ASettings.WelcomePageUnsavedAlertHours := StrToIntDef(Trim(FWelcomeUnsavedAlert.Text),
    ASettings.WelcomePageUnsavedAlertHours);
  ASettings.WelcomePageUnsavedHideWhenClean := FWelcomeUnsavedHideClean.Checked;
  ASettings.WelcomePageStatusTile := FWelcomeStatusTile.Checked;
  ASettings.WelcomePageStatusTileOnlyProblems := FWelcomeStatusTileOnlyProblems.Checked;
  ASettings.WelcomePageDiscover := FWelcomeDiscover.Checked;
  ASettings.TipsUsageTracking := FTipsUsageTracking.Checked;
  ASettings.WelcomePageHelp := FWelcomeHelp.Checked;
  ASettings.WelcomePageHelpReportUrl := Trim(FWelcomeHelpReportUrl.Text);
  ASettings.WelcomePageHelpReportFolder := Trim(FWelcomeHelpReportFolder.Text);
  ASettings.WelcomePageProjectSetup := FWelcomeProjectSetup.Checked;
  ASettings.WelcomePageNewFromTemplate := FWelcomeNewFromTemplate.Checked;
  // Freies Layout (#767): nach allen Häkchen, denn Stored liest die Sichtbarkeit aus ASettings.
  ASettings.WelcomePageCustomLayout := FWelcomeCustomLayout.Checked;
  KeepWelcomeLayout;
  ASettings := TAtlasWelcomeCustomizing.Stored(ASettings, FPageLayouts);
  ASettings.SettingsExportImport := FSettingsExportImport.Checked;
  ASettings.SettingsMarkModified := FSettingsMarkModified.Checked;
  ASettings.SettingsBackupBeforeImport := FSettingsBackupBeforeImport.Checked;
  ASettings.SettingsExportSecrets := 'omit';
  if FSettingsExportSecrets.Choice = 1 then
    ASettings.SettingsExportSecrets := 'placeholder';
  ASettings.ListWidth := FWidths.ListWidth;
  ASettings.PanelWidth := FWidths.PanelWidth;
  ASettings.Normalize;
end;

procedure TAtlasSettingsPage.SetDefaultServerPath(const AValue: string);
begin
  FDefaultServerPath := AValue;
  ServerPathChange(nil);
end;

procedure TAtlasSettingsPage.ServerPathChange(Sender: TObject);
var
  Path, Version: string;
begin
  Path := Trim(FServerPath.Text);
  if Path = '' then
    Path := FDefaultServerPath;
  if Path = '' then
    FServerStatus.Caption := ''
  else if FileExists(Path) then
    FServerStatus.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsServerFound, [Path])
  else
    FServerStatus.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsServerMissing, [Path]);
  // Version des Servers (#227): aus der Datei bzw. vom laufenden Server.
  Version := '';
  if Assigned(FOnServerVersion) and (Path <> '') and FileExists(Path) then
  begin
    Version := FOnServerVersion(Path);
    if Version = '' then
      Version := TAtlasStrings.Text(TAtlasTextId.SettingsServerVersionUnknown)
    else
      Version := TAtlasStrings.Fmt(TAtlasTextId.SettingsServerVersion, [Version]);
  end;
  FServerVersion.Caption := Version;
end;

procedure TAtlasSettingsPage.SetOnServerVersion(const AValue: TFunc<string, string>);
begin
  FOnServerVersion := AValue;
  ServerPathChange(nil);
end;

procedure TAtlasSettingsPage.AutoWidthClick(Sender: TObject);
begin
  // Automatisch: gezogene Breite vergessen; aus: die zuletzt gezogene bzw. die Vorgabe.
  if FAutoWidth.Checked then
    FWidths.ListWidth := 0
  else if FWidths.ListWidth = 0 then
    FWidths.ListWidth := TAtlasPluginSettings.MinListWidth + 160;
end;

procedure TAtlasSettingsPage.ServerBrowseClick(Sender: TObject);
var
  Dialog: TOpenDialog;
begin
  Dialog := TOpenDialog.Create(nil);
  try
    Dialog.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsServerFilter);
    Dialog.Options := Dialog.Options + [ofFileMustExist];
    if Trim(FServerPath.Text) <> '' then
      Dialog.FileName := Trim(FServerPath.Text)
    else if FDefaultServerPath <> '' then
      Dialog.InitialDir := ExtractFilePath(FDefaultServerPath);
    if Dialog.Execute then
      FServerPath.Text := Dialog.FileName;
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasSettingsPage.ResetHistoryClick(Sender: TObject);
begin
  if Assigned(FOnResetHistory) then
    FOnResetHistory();
  Allow(FResetHistory, False);
end;

/// <summary>„Leiste anpassen …“ (#1101): Dialog auf den Werten der Seite; übernommen wird erst mit OK der Optionen.
/// </summary>
procedure TAtlasSettingsPage.EditorToolbarCustomizeClick(Sender: TObject);
var
  Commands: TArray<TAtlasToolbarCommandInfo>;
  Config: TAtlasToolbarConfig;
begin
  Commands := nil;
  if Assigned(FOnToolbarCommands) then
    Commands := FOnToolbarCommands();
  Config.Items := TAtlasToolbarItems.Parse(FEditorToolbarItems.Text);
  Config.Labels := FEditorToolbarLabels.Checked;
  Config.Position := AtlasToolbarPositions[EnsureRange(FEditorToolbarPosition.Choice, 0,
    High(AtlasToolbarPositions))];
  if not TAtlasToolbarCustomizeDialog.Execute(Commands, Config) then
    Exit;
  FEditorToolbarItems.Text := TAtlasToolbarItems.Format(Config.Items);
  FEditorToolbarLabels.Checked := Config.Labels;
  FEditorToolbarPosition.Choice := Max(0, IndexText(Config.Position, AtlasToolbarPositions));
end;

procedure TAtlasSettingsPage.ResetUsageClick(Sender: TObject);
begin
  if Assigned(FOnResetUsage) then
    FOnResetUsage();
  Allow(FResetUsage, False);
end;

procedure TAtlasSettingsPage.UnblockTipsClick(Sender: TObject);
begin
  if Assigned(FOnUnblockTips) then
    FOnUnblockTips();
  Allow(FUnblockTips, False);
end;

function TAtlasSettingsPage.AddWrappedLabel(AHeight: Integer; const ACaption: string): TLabel;
var
  Panel: TWinControl;
begin
  Panel := AddPanel(AHeight);
  Result := TLabel.Create(Self);
  Result.Parent := Panel;
  Result.AutoSize := False;
  Result.Align := alClient;
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
  Result.Caption := ACaption;
end;

procedure TAtlasSettingsPage.AddTeamFileSection;
var
  Panel: TWinControl;
begin
  // Projektdatei .atlas (#486): Schalter, Erklärung, „Projektdatei öffnen“ und jeder Wert mit „aus .atlas“.
  FTeamFile := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTeamFile));
  FTeamFile.OnClick := TeamFileClick;
  Attach(AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileHint)).Parent, FTeamFile);
  Panel := AddPanel(32);
  FTeamFileOpen := TButton.Create(Self);
  FTeamFileOpen.Parent := Panel;
  FTeamFileOpen.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileOpen);
  FTeamFileOpen.Left := 0;
  FTeamFileOpen.Top := 3;
  FTeamFileOpen.Width := 180;
  FTeamFileOpen.OnClick := TeamFileOpenClick;
  Attach(Panel, FTeamFile);
  FTeamFileInfo := AddWrappedLabel(180, '');
  Attach(FTeamFileInfo.Parent, FTeamFile);
  RefreshTeamFile;
end;

procedure TAtlasSettingsPage.TeamFileClick(Sender: TObject);
begin
  RefreshTeamFile;
end;

procedure TAtlasSettingsPage.TeamFileOpenClick(Sender: TObject);
begin
  if Assigned(FOnOpenTeamFile) then
    FOnOpenTeamFile();
  RefreshTeamFile;
end;

procedure TAtlasSettingsPage.SetOnTeamFile(const AValue: TFunc<TAtlasTeamSettings>);
begin
  FOnTeamFile := AValue;
  RefreshTeamFile;
end;

procedure TAtlasSettingsPage.RefreshTeamFile;
var
  Team: TAtlasTeamSettings;
  Value: TAtlasTeamValue;
  Lines: TArray<string>;
begin
  // Ausgeschaltet wird die Datei nicht gelesen.
  Team := TAtlasTeamFile.Empty;
  if FTeamFile.Checked and Assigned(FOnTeamFile) then
    Team := FOnTeamFile();
  FTeamSnippets.Caption := '';
  if Team.Valid and (Team.Snippets <> '') then
    FTeamSnippets.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamSnippets, [Team.Snippets]);
  if not FTeamFile.Checked then
    Lines := [TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileOff)]
  else if Team.Project = '' then
    Lines := [TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileNoProject)]
  else if not Team.Exists then
    Lines := [TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileMissing)]
  else
  begin
    Lines := [TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileLocation, [Team.FileName])];
    if not Team.Valid then
      Lines := Lines + [TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileInvalid)]
    else
    begin
      for Value in TAtlasTeamFile.Values(Team) do
        Lines := Lines + [TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileValue, [Value.Key, Value.Value])];
      if Length(Lines) = 1 then
        Lines := Lines + [TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileNoValues)];
      if Length(Team.Issues) > 0 then
        Lines := Lines + [TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileIssues, [Length(Team.Issues)])];
    end;
  end;
  FTeamFileInfo.Caption := string.Join(sLineBreak, Lines);
  Allow(FTeamFileOpen, FTeamFile.Checked and (Team.Project <> ''));
end;

procedure TAtlasSettingsPage.HangTestClick(Sender: TObject);
var
  Activity: IInterface;
begin
  // Künstlicher Hänger für den Einfrier-Wächter (#501): erscheint im Protokoll mit dieser Aktion.
  Activity := TAtlasActivity.Scope('Wächter-Test');
  Sleep(1000); // lsp-ignore: blocking-call-in-main-thread
end;

procedure TAtlasSettingsPage.DiagnosticModeClick(Sender: TObject);
begin
  FHangTestRow.Visible := FDiagnosticMode.Checked;
end;

procedure TAtlasSettingsPage.ResetWidthsClick(Sender: TObject);
begin
  FWidths.ListWidth := TAtlasPluginSettings.Defaults.ListWidth;
  FWidths.PanelWidth := TAtlasPluginSettings.Defaults.PanelWidth;
  FAutoWidth.OnClick := nil;
  FAutoWidth.Checked := FWidths.ListWidth = 0;
  FAutoWidth.OnClick := AutoWidthClick;
  Allow(FResetWidths, False);
end;

end.
