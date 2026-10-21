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

interface

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  System.Generics.Collections,
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
  Atlas.Core.Welcome.QuickActions,
  Atlas.Core.Welcome.Layouts,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.SafeMode,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Groups,
  Atlas.Core.Editor.Overview,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Settings.Group,
  Atlas.UI.Strings,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol;

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
    FOpenDelay: TEdit;
    FAutoWidth: TCheckBox;
    FFilterChips: TCheckBox;
    FLearning: TCheckBox;
    FGroupInherited: TCheckBox;
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
    /// <summary>DUnitX-Tests ausführen (#69): Befehle, vorher bauen, nach dem Build; Build ohne Hinweise (#530).
    /// </summary>
    FTestRun: TCheckBox;
    FTestsBuildFirst: TCheckBox;
    FTestsAfterBuild: TCheckBox;
    FBuildZeroHints: TCheckBox;
    /// <summary>Release-Build-Wächter (#533): Schalter, build.gate, weitere Release-Konfigurationen und je Prüfung
    /// ein Haken (ohne Sollwert) bzw. eine Auswahl „nicht prüfen / Soll aus / Soll an“.</summary>
    FReleaseGuard: TCheckBox;
    FBuildGate: TAtlasChoiceBox;
    FReleaseConfigs: TEdit;
    FReleaseCheckBoxes: array[TAtlasReleaseCheck] of TCheckBox;
    FReleaseCheckChoices: array[TAtlasReleaseCheck] of TAtlasChoiceBox;
    /// <summary>Startprofile (#575): Befehl, Statusfeld.</summary>
    FStartProfiles: TCheckBox;
    FStartProfilesStatusField: TCheckBox;
    /// <summary>Einzelnen Test debuggen (#585): Befehle und Marke, Haltepunkt am Anfang der Methode.</summary>
    FTestDebug: TCheckBox;
    FTestBreakAtStart: TCheckBox;
    FActionsKey: TEdit;
    FExpandKey: TEdit;
    FShrinkKey: TEdit;
    FImplementationKey: TEdit;
    FTypeDefinitionKey: TEdit;
    FMethodToggle: TCheckBox;
    FMethodToggleUpKey: TEdit;
    FMethodToggleDownKey: TEdit;
    FTestUnitKey: TEdit;
    FNavHistory: TCheckBox;
    FNavBackKey: TEdit;
    FNavForwardKey: TEdit;
    FLastEditKey: TEdit;
    FPeek: TCheckBox;
    FPeekHeightLines: TEdit;
    FPeekShowImplementation: TCheckBox;
    FPeekDefinitionKey: TEdit;
    FPeekReferencesKey: TEdit;
    FOutline: TCheckBox;
    FOutlineAlphabetical: TCheckBox;
    FOutlineFollowCursor: TCheckBox;
    FBreadcrumbs: TCheckBox;
    FBreadcrumbsShowUnit: TCheckBox;
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
    FContinueComments: TCheckBox;
    FContinueCommentsLineComments: TCheckBox;
    FContinueCommentsLists: TCheckBox;
    FContinueCommentsBlockPrefix: TEdit;
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
    /// <summary>„Element ausblenden …“ (#628).</summary>
    FHideElementKey: TEdit;
    /// <summary>Nächster/vorheriger Befund (#509).</summary>
    FNextProblemKey: TEdit;
    FPreviousProblemKey: TEdit;
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
    FWelcomeEnabled: TCheckBox;
    FWelcomeHost: TAtlasChoiceBox;
    FWelcomeLayout: TCheckBox;
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
    FWelcomeIssuesTracker: TAtlasChoiceBox;
    FWelcomeIssuesQuery: TEdit;
    FWelcomeIssuesStart: TAtlasChoiceBox;
    FWelcomeIssuesBranchPattern: TEdit;
    FWelcomeIssuesBranchBase: TEdit;
    FWelcomeIssuesCommitPattern: TEdit;
    FTrackerLogin: TCheckBox;
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
    procedure LoadRelease(const ASettings: TAtlasPluginSettings);
    procedure SaveRelease(var ASettings: TAtlasPluginSettings);
    procedure AddUndoSection;
    procedure AddUnitSearchSection;
    procedure AddWelcomeSection;
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
    /// <summary>Zum Testen: Kommentar beim Enter fortsetzen (#696).</summary>
    property ContinueComments: TCheckBox read FContinueComments;
    property ContinueCommentsLists: TCheckBox read FContinueCommentsLists;
    property ContinueCommentsBlockPrefix: TEdit read FContinueCommentsBlockPrefix;
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
    property WelcomeHost: TAtlasChoiceBox read FWelcomeHost;
    property WelcomeLayout: TCheckBox read FWelcomeLayout;
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
    property WelcomeIssuesTracker: TAtlasChoiceBox read FWelcomeIssuesTracker;
    property WelcomeIssuesQuery: TEdit read FWelcomeIssuesQuery;
    property WelcomeIssuesStart: TAtlasChoiceBox read FWelcomeIssuesStart;
    property WelcomeIssuesBranchPattern: TEdit read FWelcomeIssuesBranchPattern;
    property WelcomeIssuesBranchBase: TEdit read FWelcomeIssuesBranchBase;
    property WelcomeIssuesCommitPattern: TEdit read FWelcomeIssuesCommitPattern;
    property TrackerLogin: TCheckBox read FTrackerLogin;
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
    /// <summary>Zum Testen: Tests ausführen (#69).</summary>
    property CodeLensTestsCheck: TCheckBox read FCodeLensTests;
    property TestRunCheck: TCheckBox read FTestRun;
    property TestsBuildFirstCheck: TCheckBox read FTestsBuildFirst;
    property TestsAfterBuildCheck: TCheckBox read FTestsAfterBuild;
    property BuildZeroHintsCheck: TCheckBox read FBuildZeroHints;
    /// <summary>Zum Testen: Release-Build-Wächter (#533).</summary>
    property ReleaseGuardCheck: TCheckBox read FReleaseGuard;
    property BuildGateChoice: TAtlasChoiceBox read FBuildGate;
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
    /// <summary>Zum Testen: benannte Lesezeichen (#622).</summary>
    property BookmarksNamedCheck: TCheckBox read FBookmarksNamed;
    property BookmarksSharedCheck: TCheckBox read FBookmarksShared;
    property BookmarkKey: TEdit read FBookmarkKey;
    /// <summary>Zum Testen: Blockende-Beschriftungen (#620) und Taste „Element ausblenden …“ (#628).</summary>
    property BlockEndLabelsCheck: TCheckBox read FBlockEndLabels;
    /// <summary>Zum Testen: Typmarken von Inline-Variablen (#453).</summary>
    property InlayTypeHintsCheck: TCheckBox read FInlayTypeHints;
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
    property RecursionMarkersDepthEdit: TEdit read FRecursionMarkersDepth;
    property HideElementKey: TEdit read FHideElementKey;
    /// <summary>Zum Testen: Fehlertext am Zeilenende, Zähler und Sprungtasten (#509).</summary>
    property InlineDiagnostics: TAtlasChoiceBox read FInlineDiagnostics;
    property ProblemsStatusCounterCheck: TCheckBox read FProblemsStatusCounter;
    property NextProblemKey: TEdit read FNextProblemKey;
    property PreviousProblemKey: TEdit read FPreviousProblemKey;
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
    /// <summary>„Gesperrte Tipps wieder zeigen“ der Karte „Atlas entdecken“ (#757).</summary>
    property OnUnblockTips: TProc read FOnUnblockTips write FOnUnblockTips;
    /// <summary>Projektdatei .atlas des aktiven Projekts (#486) für die Anzeige „aus .atlas“; nil = keine.</summary>
    property OnTeamFile: TFunc<TAtlasTeamSettings> read FOnTeamFile write SetOnTeamFile;
    /// <summary>„Projektdatei öffnen“: anlegen, falls es sie nicht gibt, und im Editor öffnen (#486).</summary>
    property OnOpenTeamFile: TProc read FOnOpenTeamFile write FOnOpenTeamFile;
    /// <summary>Anzeige der Projektdatei neu aufbauen (#486).</summary>
    procedure RefreshTeamFile;
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
  Atlas.Core.Documentation.Contract,
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
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Settings.Transfer,
  Atlas.Core.Settings.Experimental,
  Atlas.UI.Notifications.Window;

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

function TAtlasChoiceBox.GetChoice: Integer;
begin
  if HandleAllocated then
    FChoice := ItemIndex;
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
  // Code-Vorlagen (#51).
  FSnippets := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSnippets));
  FImportIdeTemplates := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsImportIdeTemplates));
  // Vorlagen aus der Projektdatei (#486); leer ohne .atlas.
  FTeamSnippets := AddWrappedLabel(20, '');

  AddSheet(TAtlasTextId.SettingsTabEditor);
  FHoverTooltip := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHover));
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
  // Beschriftung hinter dem end langer Blöcke (#620).
  FBlockEndLabels := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBlockEndLabels));
  FBlockEndLabelsMinLines := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsBlockEndLabelsMinLines));
  FDimUnusedUses := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDimUnusedUses));
  // Brotkrumenleiste (#590).
  FBreadcrumbs := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBreadcrumbs));
  FBreadcrumbsShowUnit := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBreadcrumbsShowUnit));
  FBreadcrumbsKey := AddKey(TAtlasStrings.Text(TAtlasTextId.BreadcrumbsCommand));
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
  // Startprofile (#575).
  FStartProfiles := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStartProfiles));
  FStartProfilesStatusField := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStartProfilesStatusField));
  // Beim Öffnen eines Projekts oder einer Projektgruppe einmal bauen (build.onOpen).
  AddOpenBuildSection;

  // Release-Build-Wächter (#533).
  AddSheet(TAtlasTextId.SettingsTabRelease);
  AddReleaseSection;

  // Einzelnen Test im Debugger starten (#585); die Code Lens dazu steht unter Editor (codeLens.tests).
  AddSheet(TAtlasTextId.SettingsTabDebug);
  FTestDebug := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestDebug));
  FTestBreakAtStart := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestBreakAtStart));

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
  FTestUnitKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorTestUnit));
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
  FOutline := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOutline));
  FOutlineAlphabetical := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOutlineAlphabetical));
  FOutlineFollowCursor := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOutlineFollowCursor));
  // „Lesezeichen setzen…“ (#622).
  FBookmarkKey := AddKey(TAtlasStrings.Text(TAtlasTextId.BookmarksMenuAdd));
  // „Element ausblenden …“ am gezeichneten Element (#628).
  FHideElementKey := AddKey(TAtlasStrings.Text(TAtlasTextId.HideElementCommand));
  // Nächster/vorheriger Befund (#509).
  FNextProblemKey := AddKey(TAtlasStrings.Text(TAtlasTextId.ProblemNextCommand));
  FPreviousProblemKey := AddKey(TAtlasStrings.Text(TAtlasTextId.ProblemPreviousCommand));
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
  Bind('OverviewRuler', FOverviewRuler);
  Bind('RecursionMarkers', FRecursionMarkers);
  Bind('InlineDiagnostics', FInlineDiagnostics);
  Bind('ProblemsStatusCounter', FProblemsStatusCounter);
  Bind('InlayHints', FInlayHints);
  Bind('InlayTypeHints', FInlayTypeHints);
  Bind('Problems', FProblems);
  Bind('Notes', FNotes);
  Bind('BookmarksNamed', FBookmarksNamed);
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
  Text: TLabel;
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
  Text := TLabel.Create(Self);
  Text.Parent := FExperimentalBanner;
  Text.Align := alClient;
  Text.Layout := tlCenter;
  Text.WordWrap := True;
  Text.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsExperimentalOff);
end;

procedure TAtlasSettingsPage.AddFilterRow;
var
  Caption: TLabel;
begin
  FFilterRow := TAtlasSettingsRow.Create(Self);
  FFilterRow.Parent := Self;
  FFilterRow.Align := alBottom;
  FFilterRow.AlignWithMargins := True;
  FFilterRow.Height := 26;
  Caption := TLabel.Create(Self);
  Caption.Parent := FFilterRow;
  Caption.Left := 0;
  Caption.Top := 5;
  Caption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsFilter);
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
  Parent: TWinControl;
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
  Parent := Control.Parent;
  while (Parent <> nil) and not (Parent is TScrollBox) do
    Parent := Parent.Parent;
  if Parent is TScrollBox then
    TScrollBox(Parent).ScrollInView(Control);
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
  Action: TAtlasQuickAction;
  Panel: TWinControl;
begin
  // Atlas-Bereiche auf der Willkommensseite (#753).
  FWelcomeEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeEnabled));
  // Reihenfolge wie welcomePage.host: welcomePage, dockWindow.
  FWelcomeHost := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHost),
    [TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHostPage),
    TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHostWindow)]);
  FWelcomeLayout := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeLayout));
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
  // Meine Issues (#765): Tracker aus .atlas, Abfrage, „Beginnen“ und Muster.
  FWelcomeIssues := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssues));
  FWelcomeIssuesTracker := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssuesTracker),
    [TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssuesTrackerTeam), 'GitHub', 'YouTrack']);
  FWelcomeIssuesQuery := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssuesQuery));
  FWelcomeIssuesStart := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssuesStart),
    [TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssuesStartBranch),
    TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssuesStartRemember)]);
  FWelcomeIssuesBranchPattern := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssuesBranchPattern));
  FWelcomeIssuesBranchBase := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssuesBranchBase));
  FWelcomeIssuesCommitPattern := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeIssuesCommitPattern));
  FTrackerLogin := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTrackerLogin));
  // Schnellaktionen je Projekt (#764): Schalter, je Knopf ein Häkchen, Programm für „Konsole“, zwei Tasten.
  FWelcomeQuickActions := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeQuickActions));
  for Action := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
    FWelcomeQuickActionsItems[Action] := AddCheck(TAtlasStrings.Fmt(TAtlasTextId.SettingsWelcomeQuickActionsItem,
      [QuickActionTitle(Action)]));
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
  Left: Integer;
begin
  Left := FWelcomeActiveLayout.Left + FWelcomeActiveLayout.Width + 6;
  FWelcomeLayoutNew := AddButton(Left, TAtlasTextId.SettingsWelcomeLayoutNew, WelcomeLayoutNewClick);
  FWelcomeLayoutRename := AddButton(Left + 102, TAtlasTextId.SettingsWelcomeLayoutRename,
    WelcomeLayoutRenameClick);
  FWelcomeLayoutDelete := AddButton(Left + 204, TAtlasTextId.SettingsWelcomeLayoutDelete,
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
  Name: string;
  Layouts: TAtlasWelcomeLayouts;
begin
  Name := '';
  if not AskLayoutName(Name) or (Trim(Name) = '') then
    Exit;
  KeepWelcomeLayout;
  if not FPageLayouts.Added(Trim(Name), Layouts) then
  begin
    ConfirmLayout(TAtlasStrings.Fmt(TAtlasTextId.WelcomeArrangeLayoutTaken, [Trim(Name)]), False);
    Exit;
  end;
  // Die Kopie übernimmt die Sichtbarkeit; die Häkchen bleiben.
  FPageLayouts := Layouts;
  ShowWelcomeLayouts(False);
end;

procedure TAtlasSettingsPage.WelcomeLayoutRenameClick(Sender: TObject);
var
  Name: string;
  Layouts: TAtlasWelcomeLayouts;
begin
  Name := FPageLayouts.ActiveName;
  if not AskLayoutName(Name) or (Trim(Name) = '') or (Trim(Name) = FPageLayouts.ActiveName) then
    Exit;
  if not FPageLayouts.Renamed(Trim(Name), Layouts) then
  begin
    ConfirmLayout(TAtlasStrings.Fmt(TAtlasTextId.WelcomeArrangeLayoutTaken, [Trim(Name)]), False);
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
  // Reihenfolge wie TAtlasBuildGate: off, warn, block.
  FBuildGate := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsBuildGate),
    [TAtlasStrings.Text(TAtlasTextId.SettingsBuildGateOff), TAtlasStrings.Text(TAtlasTextId.SettingsBuildGateWarn),
    TAtlasStrings.Text(TAtlasTextId.SettingsBuildGateBlock)]);
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
  FBuildGate.Choice := Ord(TAtlasReleaseGuard.GateOf(ASettings.BuildGate));
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
  if (FBuildGate.Choice >= Ord(Low(TAtlasBuildGate))) and (FBuildGate.Choice <= Ord(High(TAtlasBuildGate))) then
    ASettings.BuildGate := TAtlasReleaseGuard.GateNames[TAtlasBuildGate(FBuildGate.Choice)];
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
  Action: TAtlasQuickAction;
  Kind: TAtlasOverviewKind;
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
  FMarks.Bind(FNavHistory, ['NavHistory']);
  FMarks.Bind(FNavBackKey, ['NavBackKey']);
  FMarks.Bind(FNavForwardKey, ['NavForwardKey']);
  FMarks.Bind(FLastEditKey, ['LastEditKey']);
  FMarks.Bind(FPeek, ['Peek']);
  FMarks.Bind(FPeekHeightLines, ['PeekHeightLines']);
  FMarks.Bind(FPeekShowImplementation, ['PeekShowImplementation']);
  FMarks.Bind(FPeekDefinitionKey, ['PeekDefinitionKey']);
  FMarks.Bind(FPeekReferencesKey, ['PeekReferencesKey']);
  FMarks.Bind(FOutline, ['Outline']);
  FMarks.Bind(FOutlineAlphabetical, ['OutlineAlphabetical']);
  FMarks.Bind(FOutlineFollowCursor, ['OutlineFollowCursor']);
  FMarks.Bind(FBreadcrumbs, ['Breadcrumbs']);
  FMarks.Bind(FBreadcrumbsShowUnit, ['BreadcrumbsShowUnit']);
  FMarks.Bind(FBreadcrumbsKey, ['BreadcrumbsKey']);
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
  FMarks.Bind(FContinueComments, ['ContinueComments']);
  FMarks.Bind(FContinueCommentsLineComments, ['ContinueCommentsLineComments']);
  FMarks.Bind(FContinueCommentsLists, ['ContinueCommentsLists']);
  FMarks.Bind(FContinueCommentsBlockPrefix, ['ContinueCommentsBlockPrefix']);
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
  FMarks.Bind(FHideElementKey, ['HideElementKey']);
  FMarks.Bind(FNextProblemKey, ['NextProblemKey']);
  FMarks.Bind(FPreviousProblemKey, ['PreviousProblemKey']);
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
  FMarks.Bind(FOpenDelay, ['OpenDelayMs']);
  FMarks.Bind(FFilterChips, ['FilterChips']);
  FMarks.Bind(FLearning, ['Learning']);
  FMarks.Bind(FFavorites, ['Favorites']);
  FMarks.Bind(FGroupInherited, ['GroupInherited']);
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
  FMarks.Bind(FBlockEndLabels, ['BlockEndLabels']);
  FMarks.Bind(FBlockEndLabelsMinLines, ['BlockEndLabelsMinLines']);
  FMarks.Bind(FDimUnusedUses, ['DimUnusedUses']);
  FMarks.Bind(FRecursionMarkers, ['RecursionMarkers']);
  FMarks.Bind(FRecursionMarkersDepth, ['RecursionMarkersDepth']);
  FMarks.Bind(FInlineDiagnostics, ['InlineDiagnostics']);
  FMarks.Bind(FNotes, ['Notes']);
  FMarks.Bind(FBookmarksNamed, ['BookmarksNamed']);
  FMarks.Bind(FBookmarksShared, ['BookmarksShared']);
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
  FMarks.Bind(FProblemsStatusCounter, ['ProblemsStatusCounter']);
  FMarks.Bind(FStatusField, ['StatusField']);
  FMarks.Bind(FDiagnosticMode, ['DiagnosticMode']);
  FMarks.Bind(FDiagnosticsProcesses, ['DiagnosticsProcesses']);
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
  FMarks.Bind(FStartProfiles, ['StartProfiles']);
  FMarks.Bind(FStartProfilesStatusField, ['StartProfilesStatusField']);
  FMarks.Bind(FTestDebug, ['TestDebug']);
  FMarks.Bind(FTestBreakAtStart, ['TestBreakAtStart']);
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
  FMarks.Bind(FWelcomeEnabled, ['WelcomePage']);
  FMarks.Bind(FWelcomeHost, ['WelcomePageHost']);
  FMarks.Bind(FWelcomeLayout, ['WelcomePageLayout']);
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
  FMarks.Bind(FWelcomeIssuesTracker, ['WelcomePageIssuesTracker']);
  FMarks.Bind(FWelcomeIssuesQuery, ['WelcomePageIssuesQuery']);
  FMarks.Bind(FWelcomeIssuesStart, ['WelcomePageIssuesStart']);
  FMarks.Bind(FWelcomeIssuesBranchPattern, ['WelcomePageIssuesBranchPattern']);
  FMarks.Bind(FWelcomeIssuesBranchBase, ['WelcomePageIssuesBranchBase']);
  FMarks.Bind(FWelcomeIssuesCommitPattern, ['WelcomePageIssuesCommitPattern']);
  FMarks.Bind(FTrackerLogin, ['TrackerLogin']);
  FMarks.Bind(FOpenBuild, ['BuildOnOpen', 'BuildOnOpenKind']);
  FMarks.Bind(FOpenBuildScope, ['BuildOnOpenScope']);
  FMarks.Bind(FOpenBuildDelay, ['BuildOnOpenDelayMs']);
  FMarks.Bind(FOpenBuildExclude, ['BuildOnOpenExclude']);
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
  for Action := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
    FMarks.Bind(FWelcomeQuickActionsItems[Action], ['WelcomePageQuickActionsItems'], False);
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
    Page.Caption := FGroups.NodeCaption(ANode, TAtlasStrings.Language = TAtlasLanguage.English);
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
  Caption, Details: TLabel;
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
        Caption := TLabel.Create(Self);
        Caption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsOverviewTitle);
        Caption.Font.Style := [fsBold];
        Overview.SetMaster(Caption, '');
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
        Caption := TLabel.Create(Self);
        Caption.Parent := Row;
        Caption.Align := alClient;
        Caption.Layout := tlCenter;
        Caption.Caption := FMarks.TextOfName(Frame.MasterName);
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
  Parent: TControl;
  Index: Integer;
begin
  Result := -1;
  Parent := AControl;
  while (Parent <> nil) and not (Parent is TTabSheet) do
    Parent := Parent.Parent;
  if Parent = nil then
    Exit;
  for Index := 0 to High(FNodePages) do
    if FNodePages[Index].Sheet = Parent then
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
  Text: string;
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
    Text := FNodePages[Page].Caption;
    if FMarks.HasMarked(FNodePages[Page].Box) then
      Text := TAtlasSettingsMarks.Dot + Text;
    if Node.Text <> Text then
      Node.Text := Text;
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
  Where, Caption: string;
begin
  Result := '';
  case ALock.Reason of
    lrExperimental:
      Result := TAtlasStrings.Text(TAtlasTextId.SettingsLockedExperimental);
    lrMasterOff:
      begin
        Caption := FMarks.TextOfName(ALock.Master);
        if Caption = '' then
          Caption := FGroups.KeyOf(ALock.Master);
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
        Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsLockedMaster, [Caption, Where]);
      end;
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
  Caption: TLabel;
begin
  Panel := AddPanel(22);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := TAtlasStrings.Text(AId);
  Caption.Font.Style := [fsBold];
  Caption.Left := 0;
  Caption.Top := 4;
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
  Name: string;
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
    for Name in TAtlasGuard.DisabledProviders do
      FFuseList.Items.AddObject(Name, nil);
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
  Tag: NativeInt;
begin
  for Index := 0 to FFuseList.Items.Count - 1 do
    if FFuseList.Selected[Index] then
    begin
      Tag := NativeInt(FFuseList.Items.Objects[Index]);
      if Tag > 0 then
        TAtlasGuard.Enable(TAtlasFeature(Tag - 1))
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
  Caption: TLabel;
begin
  // Abgesicherter Start nach einem Absturz (#722).
  AddTitle(TAtlasTextId.SettingsSafeTitle);
  FSafeAsk := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSafeAsk));
  FSafeAuto := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSafeAuto));
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsSafeKey);
  Caption.Left := 0;
  Caption.Top := 5;
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
  Caption: TLabel;
begin
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := ACaption;
  Caption.Left := 0;
  Caption.Top := 5;
  Result := TAtlasChoiceBox.Create(Self);
  Result.Parent := Panel;
  Result.Left := FieldLeft;
  Result.Top := 1;
  Result.Width := 180;
  Result.SetChoices(AItems);
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
  Caption: TLabel;
  Names: TArray<string>;
  Source: string;
begin
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsNotificationsSources);
  Caption.Left := 0;
  Caption.Top := 5;
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
  Caption: TLabel;
begin
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := StringReplace(ACaption, '…', '', []);
  Caption.Left := 0;
  Caption.Top := 5;
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
  Caption: TLabel;
  Index: Integer;
begin
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := ACaption;
  Caption.Left := 0;
  Caption.Top := 5;
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
  Caption: TLabel;
begin
  Panel := AddPanel(26);
  Caption := TLabel.Create(Self);
  Caption.Parent := Panel;
  Caption.Caption := ACaption;
  Caption.Left := 0;
  Caption.Top := 5;
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
  Action: TAtlasQuickAction;
  Kind: TAtlasOverviewKind;
  Kinds: TAtlasOverviewKinds;
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
  FNavHistory.Checked := ASettings.NavHistory;
  FNavBackKey.Text := ShortCutToText(TShortCut(ASettings.NavBackKey));
  FNavForwardKey.Text := ShortCutToText(TShortCut(ASettings.NavForwardKey));
  FLastEditKey.Text := ShortCutToText(TShortCut(ASettings.LastEditKey));
  FPeek.Checked := ASettings.Peek;
  FPeekHeightLines.Text := IntToStr(ASettings.PeekHeightLines);
  FPeekShowImplementation.Checked := ASettings.PeekShowImplementation;
  FPeekDefinitionKey.Text := ShortCutToText(TShortCut(ASettings.PeekDefinitionKey));
  FPeekReferencesKey.Text := ShortCutToText(TShortCut(ASettings.PeekReferencesKey));
  FOutline.Checked := ASettings.Outline;
  FOutlineAlphabetical.Checked := ASettings.OutlineAlphabetical;
  FOutlineFollowCursor.Checked := ASettings.OutlineFollowCursor;
  FBreadcrumbs.Checked := ASettings.Breadcrumbs;
  FBreadcrumbsShowUnit.Checked := ASettings.BreadcrumbsShowUnit;
  FBreadcrumbsKey.Text := ShortCutToText(TShortCut(ASettings.BreadcrumbsKey));
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
  FContinueComments.Checked := ASettings.ContinueComments;
  FContinueCommentsLineComments.Checked := ASettings.ContinueCommentsLineComments;
  FContinueCommentsLists.Checked := ASettings.ContinueCommentsLists;
  FContinueCommentsBlockPrefix.Text := ASettings.ContinueCommentsBlockPrefix;
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
  FHideElementKey.Text := ShortCutToText(TShortCut(ASettings.HideElementKey));
  FNextProblemKey.Text := ShortCutToText(TShortCut(ASettings.NextProblemKey));
  FPreviousProblemKey.Text := ShortCutToText(TShortCut(ASettings.PreviousProblemKey));
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
  FOpenDelay.Text := IntToStr(ASettings.OpenDelayMs);
  FAutoWidth.OnClick := nil;
  FAutoWidth.Checked := ASettings.ListWidth = 0;
  FAutoWidth.OnClick := AutoWidthClick;
  FFilterChips.Checked := ASettings.FilterChips;
  FLearning.Checked := ASettings.Learning;
  FFavorites.Checked := ASettings.Favorites;
  FGroupInherited.Checked := ASettings.GroupInherited;
  FListMode.Choice := Ord(TAtlasListModes.ModeOf(ASettings.CompletionListMode));
  FListScope.Choice := Ord(TAtlasListModes.ScopeOf(ASettings.CompletionListScope));
  FPreview.Checked := ASettings.Preview;
  FSnippets.Checked := ASettings.Snippets;
  FImportIdeTemplates.Checked := ASettings.ImportIdeTemplates;
  FTeamFile.Checked := ASettings.TeamFile;
  RefreshTeamFile;
  FHoverTooltip.Checked := ASettings.HoverTooltip;
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
  FBlockEndLabels.Checked := ASettings.BlockEndLabels;
  FBlockEndLabelsMinLines.Text := IntToStr(ASettings.BlockEndLabelsMinLines);
  FDimUnusedUses.Checked := ASettings.DimUnusedUses;
  FRecursionMarkers.Checked := ASettings.RecursionMarkers;
  FRecursionMarkersDepth.Text := IntToStr(ASettings.RecursionMarkersDepth);
  FInlineDiagnostics.Choice := Ord(TAtlasInlineDiagnostics.ModeOf(ASettings.InlineDiagnostics));
  FNotes.Checked := ASettings.Notes;
  FBookmarksNamed.Checked := ASettings.BookmarksNamed;
  FBookmarksShared.Checked := ASettings.BookmarksShared;
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
  FProblemsStatusCounter.Checked := ASettings.ProblemsStatusCounter;
  FStatusField.Checked := ASettings.StatusField;
  FDiagnosticMode.Checked := ASettings.DiagnosticMode;
  FDiagnosticsProcesses.Checked := ASettings.DiagnosticsProcesses;
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
  FTestRun.Checked := ASettings.TestRun;
  FTestsBuildFirst.Checked := ASettings.TestsBuildFirst;
  FTestsAfterBuild.Checked := ASettings.TestsAfterBuild;
  FBuildZeroHints.Checked := ASettings.BuildZeroHints;
  LoadRelease(ASettings);
  FStartProfiles.Checked := ASettings.StartProfiles;
  FStartProfilesStatusField.Checked := ASettings.StartProfilesStatusField;
  FTestDebug.Checked := ASettings.TestDebug;
  FTestBreakAtStart.Checked := ASettings.TestBreakAtStart;
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
  FWelcomeEnabled.Checked := ASettings.WelcomePage;
  FWelcomeHost.Choice := 0;
  if ASettings.WelcomePageHost = 'dockWindow' then
    FWelcomeHost.Choice := 1;
  FWelcomeLayout.Checked := ASettings.WelcomePageLayout = 'atlas';
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
  if SameText(ASettings.WelcomePageIssuesTracker, 'github') then
    FWelcomeIssuesTracker.Choice := 1
  else if SameText(ASettings.WelcomePageIssuesTracker, 'youtrack') then
    FWelcomeIssuesTracker.Choice := 2
  else
    FWelcomeIssuesTracker.Choice := 0;
  FWelcomeIssuesQuery.Text := ASettings.WelcomePageIssuesQuery;
  if SameText(ASettings.WelcomePageIssuesStart, TAtlasPluginSettings.IssuesStartRemember) then
    FWelcomeIssuesStart.Choice := 1
  else
    FWelcomeIssuesStart.Choice := 0;
  FWelcomeIssuesBranchPattern.Text := ASettings.WelcomePageIssuesBranchPattern;
  FWelcomeIssuesBranchBase.Text := ASettings.WelcomePageIssuesBranchBase;
  FWelcomeIssuesCommitPattern.Text := ASettings.WelcomePageIssuesCommitPattern;
  FTrackerLogin.Checked := ASettings.TrackerLogin;
  FWelcomeQuickActions.Checked := ASettings.WelcomePageQuickActions;
  Items := TAtlasWelcomeQuickActions.ParseItems(ASettings.WelcomePageQuickActionsItems);
  for Action := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
    FWelcomeQuickActionsItems[Action].Checked := Action in Items;
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
  Action: TAtlasQuickAction;
  Kind: TAtlasOverviewKind;
  Kinds: TAtlasOverviewKinds;
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
  ASettings.NavHistory := FNavHistory.Checked;
  ASettings.NavBackKey := Integer(TextToShortCut(Trim(FNavBackKey.Text)));
  ASettings.NavForwardKey := Integer(TextToShortCut(Trim(FNavForwardKey.Text)));
  ASettings.LastEditKey := Integer(TextToShortCut(Trim(FLastEditKey.Text)));
  ASettings.Peek := FPeek.Checked;
  ASettings.PeekHeightLines := StrToIntDef(FPeekHeightLines.Text, ASettings.PeekHeightLines);
  ASettings.PeekShowImplementation := FPeekShowImplementation.Checked;
  ASettings.PeekDefinitionKey := Integer(TextToShortCut(Trim(FPeekDefinitionKey.Text)));
  ASettings.PeekReferencesKey := Integer(TextToShortCut(Trim(FPeekReferencesKey.Text)));
  ASettings.Outline := FOutline.Checked;
  ASettings.OutlineAlphabetical := FOutlineAlphabetical.Checked;
  ASettings.OutlineFollowCursor := FOutlineFollowCursor.Checked;
  ASettings.Breadcrumbs := FBreadcrumbs.Checked;
  ASettings.BreadcrumbsShowUnit := FBreadcrumbsShowUnit.Checked;
  ASettings.BreadcrumbsKey := Integer(TextToShortCut(Trim(FBreadcrumbsKey.Text)));
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
  ASettings.ContinueComments := FContinueComments.Checked;
  ASettings.ContinueCommentsLineComments := FContinueCommentsLineComments.Checked;
  ASettings.ContinueCommentsLists := FContinueCommentsLists.Checked;
  // Leerraum am Rand gehört zum Präfix (' * ').
  ASettings.ContinueCommentsBlockPrefix := FContinueCommentsBlockPrefix.Text;
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
  ASettings.HideElementKey := Integer(TextToShortCut(Trim(FHideElementKey.Text)));
  ASettings.NextProblemKey := Integer(TextToShortCut(Trim(FNextProblemKey.Text)));
  ASettings.PreviousProblemKey := Integer(TextToShortCut(Trim(FPreviousProblemKey.Text)));
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
  ASettings.OpenDelayMs := StrToIntDef(FOpenDelay.Text, ASettings.OpenDelayMs);
  ASettings.FilterChips := FFilterChips.Checked;
  ASettings.Learning := FLearning.Checked;
  ASettings.Favorites := FFavorites.Checked;
  ASettings.GroupInherited := FGroupInherited.Checked;
  if (FListMode.Choice >= Ord(Low(TAtlasListMode))) and (FListMode.Choice <= Ord(High(TAtlasListMode))) then
    ASettings.CompletionListMode := TAtlasListModes.ModeNames[TAtlasListMode(FListMode.Choice)];
  if (FListScope.Choice >= Ord(Low(TAtlasListScope))) and (FListScope.Choice <= Ord(High(TAtlasListScope))) then
    ASettings.CompletionListScope := TAtlasListModes.ScopeNames[TAtlasListScope(FListScope.Choice)];
  ASettings.Preview := FPreview.Checked;
  ASettings.Snippets := FSnippets.Checked;
  ASettings.ImportIdeTemplates := FImportIdeTemplates.Checked;
  ASettings.TeamFile := FTeamFile.Checked;
  ASettings.HoverTooltip := FHoverTooltip.Checked;
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
  ASettings.ProblemsStatusCounter := FProblemsStatusCounter.Checked;
  ASettings.StatusField := FStatusField.Checked;
  ASettings.DiagnosticMode := FDiagnosticMode.Checked;
  ASettings.DiagnosticsProcesses := FDiagnosticsProcesses.Checked;
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
  ASettings.TestRun := FTestRun.Checked;
  ASettings.TestsBuildFirst := FTestsBuildFirst.Checked;
  ASettings.TestsAfterBuild := FTestsAfterBuild.Checked;
  ASettings.BuildZeroHints := FBuildZeroHints.Checked;
  SaveRelease(ASettings);
  ASettings.StartProfiles := FStartProfiles.Checked;
  ASettings.StartProfilesStatusField := FStartProfilesStatusField.Checked;
  ASettings.TestDebug := FTestDebug.Checked;
  ASettings.TestBreakAtStart := FTestBreakAtStart.Checked;
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
  ASettings.WelcomePage := FWelcomeEnabled.Checked;
  ASettings.WelcomePageHost := 'welcomePage';
  if FWelcomeHost.Choice = 1 then
    ASettings.WelcomePageHost := 'dockWindow';
  ASettings.WelcomePageLayout := 'off';
  if FWelcomeLayout.Checked then
    ASettings.WelcomePageLayout := 'atlas';
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
  case FWelcomeIssuesTracker.Choice of
    1:
      ASettings.WelcomePageIssuesTracker := 'github';
    2:
      ASettings.WelcomePageIssuesTracker := 'youtrack';
  else
    ASettings.WelcomePageIssuesTracker := '';
  end;
  ASettings.WelcomePageIssuesQuery := Trim(FWelcomeIssuesQuery.Text);
  if FWelcomeIssuesStart.Choice = 1 then
    ASettings.WelcomePageIssuesStart := TAtlasPluginSettings.IssuesStartRemember
  else
    ASettings.WelcomePageIssuesStart := TAtlasPluginSettings.IssuesStartBranch;
  ASettings.WelcomePageIssuesBranchPattern := Trim(FWelcomeIssuesBranchPattern.Text);
  ASettings.WelcomePageIssuesBranchBase := Trim(FWelcomeIssuesBranchBase.Text);
  // Nicht gekürzt: Das Leerzeichen am Ende von "{kennung} " trennt Kennung und Nachricht.
  ASettings.WelcomePageIssuesCommitPattern := FWelcomeIssuesCommitPattern.Text;
  ASettings.TrackerLogin := FTrackerLogin.Checked;
  ASettings.WelcomePageQuickActions := FWelcomeQuickActions.Checked;
  Items := [];
  for Action := Low(TAtlasQuickAction) to High(TAtlasQuickAction) do
    if FWelcomeQuickActionsItems[Action].Checked then
      Include(Items, Action);
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
  Sleep(1000);
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
