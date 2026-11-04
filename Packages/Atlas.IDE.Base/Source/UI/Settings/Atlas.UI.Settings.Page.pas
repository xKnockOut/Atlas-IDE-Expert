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
// Bereich Issue-Tracker (#1280): nur der Modulschalter; Tracker, Abfrage, Start-Optionen, Muster und Zugang
// (issues.*) baut das Modul Tracker als Abschnitt (#1455). Auf der Willkommensseite bleibt nur die Sektion an/aus
// mit dem Sprung „Tracker-Einstellungen …“.
// Abschnitte der Module (#1455, ADR 0017 Entscheidung 3): Jeder IAtlasSettingsSectionProvider der Registry liefert
// der Seite einen eigenen Abschnitt, den sie in den Reiter seines Bereichs baut (Bausteine über
// IAtlasSettingsSectionHost). Geht ein Modul, schließt die Seite seinen Abschnitt; seine Werte bleiben erhalten.

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
  Atlas.Core.Build.PipelineSettings,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Vcs,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.SafeMode,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Settings.History,
  Atlas.Core.Modules.Contract,
  Atlas.UI.Settings.Contract,
  Atlas.Core.Settings.Groups,
  Atlas.Core.Editor.Overview,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Core.Settings.EventBreakNames,
  Atlas.Text.StepFilter,
  Atlas.Core.Settings.Reassigned,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.ToolCheck,
  Atlas.Core.Vcs.ServerAccess,
  Atlas.Core.Vcs.ServerCheck,
  Atlas.Core.Vcs.BranchPlan,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Settings.Group,
  Atlas.UI.Strings,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol,
  Atlas.UI.EditorToolbar.Customize;

type
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

  /// <summary>„Hinzufügen …“ der Tabelle Projekte der Versionsverwaltung (#1286): .dproj bzw. .groupproj (AFolder
  /// False) oder Ordner wählen; False bei Abbruch.</summary>
  TAtlasProjectBrowseEvent = reference to function(AFolder: Boolean; out APath: string): Boolean;
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

  /// <summary>Feld eines Modul-Abschnitts an einer Plugin-Einstellung (#1455): Name, Element der Seite, bei einer
  /// Auswahl die gespeicherten Werte je Eintrag.</summary>
  TAtlasSettingsSectionBinding = record
    Name: string;
    Control: TControl;
    Values: TArray<string>;
  end;

  TAtlasSettingsPage = class(TFrame)
  private
    FPages: TPageControl;
    /// <summary>Abschnitte der Module (#1455) mit ihrer Anmeldung und ihrem Host, gleicher Index.</summary>
    FSections: TArray<IAtlasSettingsSection>;
    FSectionProviders: TArray<IAtlasSettingsSectionProvider>;
    FSectionHosts: TArray<IAtlasSettingsSectionHost>;
    FSectionBindings: TArray<TAtlasSettingsSectionBinding>;
    /// <summary>Reiter, die erst für einen Abschnitt entstanden sind: Bereich und Index in FSheets.</summary>
    FSectionAreas: TArray<TPair<string, Integer>>;
    FSectionWatch: IAtlasRegistryListener;
    FSectionWatchRegistration: IAtlasRegistration;
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
    /// <summary>Fenster „Atlas-Server“ (#1356).</summary>
    FServerStatusWindow: TCheckBox;
    // Architekturübersicht (#1118).
    FArchitecture: TCheckBox;
    /// <summary>Modul-Schalter (#1454) mit ihren Namen in TAtlasPluginSettings.Load/Save, gleiche Reihenfolge.
    /// </summary>
    FModuleChecks: TArray<TCheckBox>;
    FModuleNames: TArray<string>;
    FArchitectureScope: TAtlasChoiceBox;
    FArchitectureLibrary: TCheckBox;
    FArchitectureCentral: TEdit;
    FQuery: TCheckBox;
    // Hotspots (#1354).
    FHotspots: TCheckBox;
    FHotspotsMonths: TEdit;
    FHotspotsMinCommits: TEdit;
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
    /// Erzeugen“, Umfang in einer Gruppe, Wartezeit, ausgeschlossene Projekte, Konfiguration und Plattform
    /// (#1293).</summary>
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
    FOpenBuildConfig: TEdit;
    FOpenBuildPlatform: TAtlasChoiceBox;
    /// <summary>DUnitX-Tests ausführen (#69): Befehle, vorher bauen, nach dem Build; Build ohne Hinweise (#530).
    /// </summary>
    FTestRun: TCheckBox;
    FTestsBuildFirst: TCheckBox;
    FTestsAfterBuild: TCheckBox;
    FTestsAffected: TCheckBox;
    FTestsAffectedDepth: TEdit;
    FTestsAffectedBeforeCommit: TCheckBox;
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
    // Was der Kopf zeigt: Typen, Routinen, große Anweisungsblöcke (#1230).
    FStickyScrollTypes: TCheckBox;
    FStickyScrollRoutines: TCheckBox;
    FStickyScrollBlocks: TCheckBox;
    FStickyScrollLoops: TCheckBox;
    FStickyScrollTry: TCheckBox;
    FStickyScrollCase: TCheckBox;
    FStickyScrollWith: TCheckBox;
    FStickyScrollBlockMinLines: TEdit;
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
    FEditorDesignerBar: TCheckBox;
    FDesignerSearchKey: TEdit;
    FDesignerSearchStyle: TAtlasChoiceBox;
    FDesignerTabOrderClick: TCheckBox;
    FDesignerAlign: TCheckBox;
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
    FFixBulk: TCheckBox;
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
    FUnitSearchFormCaptions: TCheckBox;
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
    FSearchFromFirst: TCheckBox;
    FOnBrowseProject: TAtlasProjectBrowseEvent;
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
    /// <summary>AControl hat ein Fenster bzw. bekommt eines, sobald die Seite eines hat (Einträge von Listen und
    /// Bäumen leben im Fenster; auf noch nicht gezeigten Reitern fehlt es sonst).</summary>
    function ListReady(AControl: TWinControl): Boolean;
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
    /// <summary>Modul-Schalter AName (#1454) auf der aktuellen Seite; Beschriftung aus dem Plugin-Katalog
    /// (x-caption bzw. x-captionEn).</summary>
    function AddModuleSwitch(const AName: string): TCheckBox;
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
    procedure EditorToolbarCustomizeClick(Sender: TObject);
    procedure AddTeamFileSection;
    procedure TeamFileClick(Sender: TObject);
    procedure TeamFileOpenClick(Sender: TObject);
    procedure SetOnTeamFile(const AValue: TFunc<TAtlasTeamSettings>);
    /// <summary>Beschriftung über die ganze Breite mit Zeilenumbruch.</summary>
    function AddWrappedLabel(AHeight: Integer; const ACaption: string): TLabel;
    /// <summary>Seite der Einstellung AName eines Moduls; ohne das Modul die Seite seines Schalters AFallback.
    /// </summary>
    procedure SelectModulePage(const AName, AFallback: string);
    /// <summary>Zeile mit Beschriftung links und AControl rechts daneben (Verbindungen, Projekte).</summary>
    function AddFieldRow(AId: TAtlasTextId; AControl: TWinControl; AWidth: Integer): TWinControl;
    function AddRowButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TAtlasTextId;
      AClick: TNotifyEvent): TButton;
    class procedure AddListColumn(AList: TListView; AId: TAtlasTextId; AWidth: Integer); static;
    /// <summary>„Hinzufügen …“ ohne OnBrowseProject: Datei- bzw. Ordnerauswahl von Windows.</summary>
    function BrowseProject(AFolder: Boolean; out APath: string): Boolean;
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
    procedure AddSheetCaption(const ACaption: string);
    procedure AddTitleText(const ACaption: string);
    /// <summary>Reiter des Bereichs AArea (x-area); -1 ohne.</summary>
    function SheetOfArea(const AArea: string): Integer;
    /// <summary>Abschnitte der Module aus der Registry bauen und auf Abmeldungen hören (#1455).</summary>
    procedure AddModuleSections;
    procedure AddModuleSection(const AProvider: IAtlasSettingsSectionProvider);
    procedure AddSectionBinding(const AName: string; AControl: TControl; const AValues: TArray<string>);
    function SectionValues(const AStore: IAtlasMemorySettingsStore): IAtlasSettingsValues;
    procedure LoadSections(const ASettings: TAtlasPluginSettings);
    procedure SaveSections(var ASettings: TAtlasPluginSettings);
    procedure WriteText(const AStore: IAtlasMemorySettingsStore; const AName, AText: string);
    /// <summary>Abschnitte abgemeldeter Module schließen (Regel 3).</summary>
    procedure DropMissingSections;
    procedure CloseSections;
    procedure AddBuiltSection(const AProvider: IAtlasSettingsSectionProvider; const ASection: IAtlasSettingsSection);
    /// <summary>Die Seite hat ein Fenster: Abschnitte füllen ihre Listen.</summary>
    procedure SectionsWindowReady;
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
    /// <summary>Zum Testen: Zahl der gebauten Abschnitte der Module (#1455).</summary>
    function SectionCount: Integer;
    /// <summary>Einstellung AName (Registry-Name) mit Vorgabe AArgument zeigen (z. B. „zuordnen …“ mit dem
    /// Projekt): Der Abschnitt des Moduls, dem sie gehört, legt an bzw. wählt (#1455). False ohne Abschnitt dazu.
    /// </summary>
    function ShowSettingArgument(const AName, AArgument: string): Boolean;
    /// <summary>Gebundenes Element der Einstellung AName (Registry-Name); nil ohne (Modul fehlt).</summary>
    function ControlOfSetting(const AName: string): TControl;
    /// <summary>Zum Testen: Zahl der Reiter (Bereiche).</summary>
    function SheetCountForTests: Integer;
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
    property ServerStatusWindow: TCheckBox read FServerStatusWindow;
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
    property StickyScrollTypes: TCheckBox read FStickyScrollTypes;
    property StickyScrollRoutines: TCheckBox read FStickyScrollRoutines;
    property StickyScrollBlocks: TCheckBox read FStickyScrollBlocks;
    property StickyScrollLoops: TCheckBox read FStickyScrollLoops;
    property StickyScrollTry: TCheckBox read FStickyScrollTry;
    property StickyScrollCase: TCheckBox read FStickyScrollCase;
    property StickyScrollWith: TCheckBox read FStickyScrollWith;
    property StickyScrollBlockMinLines: TEdit read FStickyScrollBlockMinLines;
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
    /// <summary>Zum Testen: Editorleiste (#1101).</summary>
    property EditorToolbarItemsEdit: TEdit read FEditorToolbarItems;
    property EditorToolbarPositionBox: TAtlasChoiceBox read FEditorToolbarPosition;
    property EditorToolbarCustomizeButton: TButton read FEditorToolbarCustomize;
    property EditorStatusBarItemsEdit: TEdit read FEditorStatusBarItems;
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
    property OpenBuildConfigEdit: TEdit read FOpenBuildConfig;
    property OpenBuildPlatformChoice: TAtlasChoiceBox read FOpenBuildPlatform;
    /// <summary>Zum Testen: Tests ausführen (#69).</summary>
    property CodeLensTestsCheck: TCheckBox read FCodeLensTests;
    property TestRunCheck: TCheckBox read FTestRun;
    property TestsBuildFirstCheck: TCheckBox read FTestsBuildFirst;
    property TestsAfterBuildCheck: TCheckBox read FTestsAfterBuild;
    property TestsAffectedCheck: TCheckBox read FTestsAffected;
    property TestsAffectedDepthEdit: TEdit read FTestsAffectedDepth;
    property TestsAffectedBeforeCommitCheck: TCheckBox read FTestsAffectedBeforeCommit;
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
    property QueryCheck: TCheckBox read FQuery;
    property HotspotsCheck: TCheckBox read FHotspots;
    property HotspotsMonthsEdit: TEdit read FHotspotsMonths;
    property HotspotsMinCommitsEdit: TEdit read FHotspotsMinCommits;
    property ProblemsWindowScopeChoice: TAtlasChoiceBox read FProblemsWindowScope;
    property ProblemsWindowGroupByChoice: TAtlasChoiceBox read FProblemsWindowGroupBy;
    property ProblemsWindowCompilerCheck: TCheckBox read FProblemsWindowCompiler;
    property ProblemsWindowFollowCursorCheck: TCheckBox read FProblemsWindowFollowCursor;
    property ProblemsWindowOpenFirstCheck: TCheckBox read FProblemsWindowOpenFirst;
    property ProblemsWindowClosedUnitsChoice: TAtlasChoiceBox read FProblemsWindowClosedUnits;
    property ProblemsWindowShowCleanActiveCheck: TCheckBox read FProblemsWindowShowCleanActive;
    property ProblemsLiveCheck: TCheckBox read FProblemsLive;
    property FixBulkCheck: TCheckBox read FFixBulk;
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
    /// <summary>Befehle für „Leiste anpassen …“ der Editorleiste (#1101): Atlas-Befehle der Palette.</summary>
    property OnToolbarCommands: TFunc<TArray<TAtlasToolbarCommandInfo>> read FOnToolbarCommands
      write FOnToolbarCommands;
    /// <summary>Projektdatei .atlas des aktiven Projekts (#486) für die Anzeige „aus .atlas“; nil = keine.</summary>
    property OnTeamFile: TFunc<TAtlasTeamSettings> read FOnTeamFile write SetOnTeamFile;
    /// <summary>„Projektdatei öffnen“: anlegen, falls es sie nicht gibt, und im Editor öffnen (#486).</summary>
    property OnOpenTeamFile: TProc read FOnOpenTeamFile write FOnOpenTeamFile;
    /// <summary>Anzeige der Projektdatei neu aufbauen (#486).</summary>
    procedure RefreshTeamFile;
    /// <summary>„Hinzufügen …“ der Projekttabellen (#1261, #1286); nil = Datei- bzw. Ordnerauswahl von Windows.
    /// </summary>
    property OnBrowseProject: TAtlasProjectBrowseEvent read FOnBrowseProject write FOnBrowseProject;
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
    /// <summary>Zustand ohne Prozess: „verwendet: &lt;Pfad&gt; (PATH)“, „fehlt“, „fehlt: &lt;Pfad&gt; …“.</summary>
    class function VcsLocationText(const ALocation: TAtlasVcsToolLocation): string; static;
    /// <summary>Ergebnis von „Prüfen“: „gefunden · git version 2.47.1 · &lt;Pfad&gt; (PATH)“ usw.</summary>
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
    property VcsProjectAddButton: TButton read FVcsProjectAdd;
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
  Atlas.Core.Build.Verdict,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Projects.Matching,
  Atlas.Core.Problems.InlineHints,
  Atlas.Core.Product.Version,
  Atlas.Core.Updates.Check,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Undo.Names,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Build.OpenBuildSettings,
  Atlas.Core.Settings.FolderList,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Settings.Transfer,
  Atlas.Core.Settings.Experimental,
  Atlas.Core.Settings.StoreValues,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.Settings.StatusBarItems,
  Atlas.UI.Notifications.Window;

const
  /// <summary>Werte von vcs.branch.git.base, .push und .uncommitted (#1289) in der Reihenfolge der Auswahl.
  /// </summary>
  cVcsGitBases: array[0..2] of string = ('remote', 'local', 'current');
  cVcsGitPushes: array[0..1] of string = ('later', 'now');
  cVcsGitUncommitted: array[0..2] of string = ('carry', 'stash', 'ask');
  /// <summary>Spalten, Felder und Knöpfe der Tabellen Projekte und Server der Versionsverwaltung (#1286, #1287).
  /// </summary>
  cVcsMatchColumn = 230;
  cVcsKindColumn = 90;
  cVcsBranchColumn = 100;
  cVcsSourceColumn = 150;
  cVcsWideField = 376;
  cVcsField = 180;
  cVcsButtonGap = 6;
  cVcsAddCurrentWidth = 180;
  cVcsAddWidth = 110;
  cVcsRemoveWidth = 100;
  cVcsServerProjectColumn = 170;
  cVcsServerServerColumn = 200;
  cVcsServerStateColumn = 180;
  cVcsCheckWidth = 100;
  cVcsCheckAllWidth = 110;
  cRowButtonTop = 3;
  cSectionKeyMissing = 'Einstellung %s ist keine Plugin-Einstellung';
  cSectionChoiceMismatch = 'Auswahl %s: Anzeige und Werte verschieden lang';

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
  begin
    if SameText(AValues[Index], AValue) then
    begin
      Exit(Index);
    end;
  end;
  Result := 0;
end;

type
  /// <summary>Host und Wächter der Abschnitte lösen sich von der Seite, wenn sie schließt (#1455).</summary>
  IAtlasSettingsDetachable = interface
    ['{816EC08A-0148-46B9-AD92-1374D8305711}']
    procedure Detach;
  end;

  /// <summary>Bausteine der Seite für einen Abschnitt eines Moduls (#1455). Hält die Seite nur, solange sie lebt;
  /// nach dem Schließen der Seite tut er nichts mehr.</summary>
  TAtlasSettingsSectionHost = class(TInterfacedObject, IAtlasSettingsSectionHost, IAtlasSettingsDetachable)
  private
    FPage: TAtlasSettingsPage;
    function NameOf(const AKey: string): string;
  public
    constructor Create(APage: TAtlasSettingsPage);
    procedure Detach;
    procedure AddTitle(const ACaption: string);
    function AddHint(const AText: string; AHeight: Integer): TControl;
    function AddSwitch(const AKey, ACaption: string): TControl;
    function AddNumber(const AKey, ACaption: string): TControl;
    function AddText(const AKey, ACaption: string): TControl;
    function AddChoice(const AKey, ACaption: string; const ACaptions, AValues: TArray<string>): TControl;
    function AddRow(AHeight: Integer; const AKeys: TArray<string>): TWinControl;
    procedure Attach(ARow, AAnchor: TControl);
    procedure Changed;
    procedure Allow(AControl: TControl; AEnabled: Boolean);
    function ListReady(AControl: TWinControl): Boolean;
    function Reveal(const AKey: string): Boolean;
  end;

  /// <summary>Hört für die Seite auf die Registry: Geht ein Modul, schließt die Seite seinen Abschnitt (Regel 2).
  /// </summary>
  TAtlasSettingsSectionWatch = class(TInterfacedObject, IAtlasRegistryListener, IAtlasSettingsDetachable)
  private
    FPage: TAtlasSettingsPage;
  public
    constructor Create(APage: TAtlasSettingsPage);
    procedure Detach;
    procedure RegistryChanged(const AChange: TAtlasRegistryChange);
  end;

{ TAtlasSettingsSectionHost }

constructor TAtlasSettingsSectionHost.Create(APage: TAtlasSettingsPage);
begin
  inherited Create;
  FPage := APage;
end;

procedure TAtlasSettingsSectionHost.Detach;
begin
  FPage := nil;
end;

function TAtlasSettingsSectionHost.NameOf(const AKey: string): string;
begin
  Result := TAtlasSettingsStoreValues.PluginName(FPage.Catalog, AKey);
  if Result = '' then
  begin
    raise EAtlasSettingsKey.CreateFmt(cSectionKeyMissing, [AKey]);
  end;
end;

procedure TAtlasSettingsSectionHost.AddTitle(const ACaption: string);
begin
  if FPage <> nil then
  begin
    FPage.AddTitleText(ACaption);
  end;
end;

function TAtlasSettingsSectionHost.AddHint(const AText: string; AHeight: Integer): TControl;
begin
  Result := nil;
  if FPage <> nil then
  begin
    Result := FPage.AddWrappedLabel(AHeight, AText);
  end;
end;

function TAtlasSettingsSectionHost.AddSwitch(const AKey, ACaption: string): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := NameOf(AKey);
  Result := FPage.AddCheck(ACaption);
  FPage.AddSectionBinding(mName, Result, nil);
end;

function TAtlasSettingsSectionHost.AddNumber(const AKey, ACaption: string): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := NameOf(AKey);
  Result := FPage.AddNumber(ACaption);
  FPage.AddSectionBinding(mName, Result, nil);
end;

function TAtlasSettingsSectionHost.AddText(const AKey, ACaption: string): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := NameOf(AKey);
  Result := FPage.AddTextLine(ACaption);
  FPage.AddSectionBinding(mName, Result, nil);
end;

function TAtlasSettingsSectionHost.AddChoice(const AKey, ACaption: string;
  const ACaptions, AValues: TArray<string>): TControl;
var
  mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  if Length(ACaptions) <> Length(AValues) then
  begin
    raise EAtlasSettingsKey.CreateFmt(cSectionChoiceMismatch, [AKey]);
  end;
  mName := NameOf(AKey);
  Result := FPage.AddChoice(ACaption, ACaptions);
  FPage.AddSectionBinding(mName, Result, AValues);
end;

function TAtlasSettingsSectionHost.AddRow(AHeight: Integer; const AKeys: TArray<string>): TWinControl;
var
  mNames: TArray<string>;
  mKey, mName: string;
begin
  Result := nil;
  if FPage = nil then
  begin
    Exit;
  end;
  mNames := nil;
  for mKey in AKeys do
  begin
    mNames := mNames + [NameOf(mKey)];
  end;
  Result := FPage.AddPanel(AHeight);
  if Length(mNames) > 0 then
  begin
    // Die Bindung hängt an der Zeile der Seite, nie an Elementen des Moduls: Die gibt das Modul in Close frei.
    FPage.FMarks.Bind(Result, mNames);
    for mName in mNames do
    begin
      FPage.Bind(mName, Result);
    end;
  end;
end;

procedure TAtlasSettingsSectionHost.Attach(ARow, AAnchor: TControl);
begin
  if FPage <> nil then
  begin
    FPage.Attach(ARow, AAnchor);
  end;
end;

procedure TAtlasSettingsSectionHost.Changed;
begin
  if FPage <> nil then
  begin
    FPage.RefreshMarks;
  end;
end;

procedure TAtlasSettingsSectionHost.Allow(AControl: TControl; AEnabled: Boolean);
begin
  if (FPage <> nil) and (AControl <> nil) then
  begin
    FPage.Allow(AControl, AEnabled);
  end;
end;

function TAtlasSettingsSectionHost.ListReady(AControl: TWinControl): Boolean;
begin
  Result := (FPage <> nil) and (AControl <> nil) and FPage.ListReady(AControl);
end;

function TAtlasSettingsSectionHost.Reveal(const AKey: string): Boolean;
var
  mName: string;
begin
  Result := False;
  if FPage = nil then
  begin
    Exit;
  end;
  mName := TAtlasSettingsStoreValues.PluginName(FPage.Catalog, AKey);
  Result := (mName <> '') and FPage.Reveal(mName);
end;

{ TAtlasSettingsSectionWatch }

constructor TAtlasSettingsSectionWatch.Create(APage: TAtlasSettingsPage);
begin
  inherited Create;
  FPage := APage;
end;

procedure TAtlasSettingsSectionWatch.Detach;
begin
  FPage := nil;
end;

procedure TAtlasSettingsSectionWatch.RegistryChanged(const AChange: TAtlasRegistryChange);
begin
  if (FPage <> nil) and IsEqualGUID(AChange.IID, IAtlasSettingsSectionProvider) then
  begin
    FPage.DropMissingSections;
  end;
end;

/// <summary>Zeigen AFirst und ASecond auf dasselbe Objekt (Vergleich über IInterface, nicht über die
/// Schnittstelle)?</summary>
function SameInstance(const AFirst, ASecond: IInterface): Boolean;
begin
  Result := (AFirst as IInterface) = (ASecond as IInterface);
end;

{ TAtlasSettingsPage }


constructor TAtlasSettingsPage.Create(AOwner: TComponent);
var
  Panel: TWinControl;
  Title: TLabel;
  Button: TButton;
  mIndex: Integer;
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
  // Modul-Schalter (#1454): je Modul auf dem Hauptknoten seines Bereichs, ganz oben.
  AddModuleSwitch('AnalysisEnabled');
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
  // Fenster „Atlas-Server“ (#1356).
  FServerStatusWindow := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsServerStatusWindow));
  // Architekturübersicht (#1118): Unterpunkt „Architektur“ über x-node; Reihenfolge wie die Werte von
  // architecture.scope (projectGroup, project).
  FArchitecture := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsArchitecture));
  FArchitectureScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsArchitectureScope),
    [TAtlasStrings.Text(TAtlasTextId.ArchitectureScopeGroup), TAtlasStrings.Text(TAtlasTextId.ArchitectureScopeProject)]);
  FArchitectureLibrary := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsArchitectureLibrary));
  FArchitectureCentral := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsArchitectureCentral));
  // Code-Abfragen (#1351): Fenster „Atlas-Abfrage“, Befehl und Menüeintrag; Unterpunkt über x-node.
  FQuery := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsQuery));
  // Hotspots (#1354): Unterpunkt „Hotspots“ über x-node.
  FHotspots := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHotspots));
  FHotspotsMonths := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsHotspotsMonths));
  FHotspotsMinCommits := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsHotspotsMinCommits));
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
  AddModuleSwitch('BookmarksEnabled');
  AddModuleSwitch('DesignerEnabled');
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
  // Designer-Leiste im Formular-Designer (#1442).
  FEditorDesignerBar := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEditorDesignerBar));
  FDesignerSearchKey := AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsDesignerSearchKey));
  FDesignerSearchStyle := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsDesignerSearchStyle),
    [TAtlasStrings.Text(TAtlasTextId.SettingsDesignerSearchWindow),
    TAtlasStrings.Text(TAtlasTextId.SettingsDesignerSearchPopup)]);
  FDesignerTabOrderClick := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDesignerTabOrderClick));
  FDesignerAlign := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDesignerAlign));
  // Mitlaufender Kopf (#506, experimentell).
  FStickyScroll := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScroll));
  FStickyScrollMaxLines := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollMaxLines));
  FStickyScrollTypes := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollTypes));
  FStickyScrollRoutines := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollRoutines));
  FStickyScrollBlocks := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollBlocks));
  FStickyScrollLoops := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollLoops));
  FStickyScrollTry := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollTry));
  FStickyScrollCase := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollCase));
  FStickyScrollWith := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollWith));
  FStickyScrollBlockMinLines := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollBlockMinLines));
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
  AddModuleSwitch('BuildToolsEnabled');
  AddModuleSwitch('BuildPipelineEnabled');
  AddModuleSwitch('TestsEnabled');
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
  // Betroffene Tests (#1353).
  FTestsAffected := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestsAffected));
  FTestsAffectedDepth := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsTestsAffectedDepth));
  FTestsAffectedBeforeCommit := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestsAffectedBeforeCommit));
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
  AddModuleSwitch('RuleChecksEnabled');
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
  // Sammelkorrektur im Kontextmenü des Fensters (#1352).
  FFixBulk := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsFixBulk));
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
  AddModuleSwitch('DebugEnabled');
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
  AddModuleSwitch('SearchEnabled');
  AddUnitSearchSection;

  // Willkommensseite (#753): Base zeigt nur den Modulschalter; die Einstellungen der Seite baut das Modul als
  // Abschnitt (#1456, Atlas.UI.Welcome.SettingsSection).
  AddSheet(TAtlasTextId.SettingsTabWelcome);
  AddModuleSwitch('WelcomePage');

  // Issue-Tracker (#1280): eigener Bereich; die Willkommensseite schaltet nur, ob „Meine Issues“ erscheint.
  // Die Einstellungen darin baut das Modul Tracker als Abschnitt (#1455, Atlas.UI.Tracker.SettingsSection).
  AddSheet(TAtlasTextId.SettingsTabIssues);
  AddModuleSwitch('IssuesEnabled');

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
  Bind('QueryEnabled', FQuery);
  Bind('HotspotsEnabled', FHotspots);
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
  Bind('ExperimentalEnabled', FExperimentalEnabled);
  for mIndex := 0 to High(FModuleChecks) do
  begin
    Bind(FModuleNames[mIndex], FModuleChecks[mIndex]);
  end;
  BindControls;
  AddModuleSections;
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
  begin
    FMarks.ApplyFilter(TAtlasSettingsFilter(FFilter.Choice));
  end;
  // Knoten ohne Treffer fallen aus dem Baum (#890).
  if ListReady(FTree) then
  begin
    FillTree;
  end;
end;

procedure TAtlasSettingsPage.Bind(const AKey: string; AControl: TControl);
begin
  if AControl = nil then
  begin
    Exit;
  end;
  FRevealKeys := FRevealKeys + [AKey];
  FRevealControls := FRevealControls + [AControl];
end;

function TAtlasSettingsPage.ControlOf(const AKey: string): TControl;
var
  Index: Integer;
begin
  for Index := 0 to High(FRevealKeys) do
  begin
    if SameText(FRevealKeys[Index], AKey) then
    begin
      Exit(FRevealControls[Index]);
    end;
  end;
  Result := nil;
end;

function TAtlasSettingsPage.Reveal(const AKey: string): Boolean;
begin
  Result := ControlOf(AKey) <> nil;
  if not Result then
  begin
    Exit;
  end;
  if HandleAllocated then
  begin
    ApplyReveal(AKey);
  end
  else
  begin
    FPendingReveal := AKey;
  end;
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
  begin
    Exit;
  end;
  // Gesperrt (#890): den Hauptschalter zeigen, der sie freigibt.
  Names := FMarks.NamesOf(Control);
  if (Length(Names) > 0) and (FGroups <> nil) then
  begin
    Lock := LockOfName(Names[0]);
    if Lock.Locked then
    begin
      Master := FMarks.ControlOfName(Lock.Master);
      if Master <> nil then
      begin
        Control := Master;
      end;
    end;
  end;
  // Knoten des Elements wählen, wie ein Klick im Baum links.
  SelectPage(PageOf(Control));
  // Ins Bild rollen.
  mParent := Control.Parent;
  while (mParent <> nil) and not (mParent is TScrollBox) do
  begin
    mParent := mParent.Parent;
  end;
  if mParent is TScrollBox then
  begin
    TScrollBox(mParent).ScrollInView(Control);
  end;
  // Zeile hervorheben: Kontrollkästchen fett, sonst die Beschriftung der Zeile.
  if Control is TCheckBox then
  begin
    TCheckBox(Control).Font.Style := [fsBold];
  end
  else if Control.Parent <> nil then
  begin
    for Child := 0 to Control.Parent.ControlCount - 1 do
    begin
      if Control.Parent.Controls[Child] is TLabel then
      begin
        TLabel(Control.Parent.Controls[Child]).Font.Style := [fsBold];
      end;
    end;
  end;
  // Nur mit sichtbarer Form: CanFocus allein lässt eine noch verborgene Form durch („kann den Fokus nicht erhalten“).
  if (Control is TWinControl) and TWinControl(Control).CanFocus and (GetParentForm(Control) <> nil) and
    GetParentForm(Control).Visible then
  begin
    TWinControl(Control).SetFocus;
  end;
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

procedure TAtlasSettingsPage.VcsExternalsRulesChange(Sender: TObject);
var
  mRules: TArray<TAtlasVcsExternalRule>;
  mInvalid: string;
begin
  // Ungültige Zeile: Hinweis; gespeichert bleiben dann die bisherigen Regeln (SaveTo).
  if TAtlasVcsExternalRules.RulesOfText(FVcsExternalsRules.Text, mRules, mInvalid) then
  begin
    FVcsExternalsRulesError.Caption := '';
  end
  else
  begin
    FVcsExternalsRulesError.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsExternalsRulesInvalid, [mInvalid]);
  end;
  RefreshMarks;
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
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsToolConfiguredMissing, [ALocation.Configured]);
  end
  else if ALocation.Executable = '' then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsVcsToolMissing);
  end
  else
  begin
    Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsToolWouldUse,
      [ALocation.Executable, VcsSourceText(ALocation.Source)]);
  end;
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
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectNone));
  end;
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
  begin
    mSource := mSource + TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectMainBranch, [AState.MainBranch]);
  end;
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
  begin
    mHead := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectSvnPath,
      [AState.Head.Branch, AState.Head.ShortRevision(AState.WorkingCopy.Kind)]);
  end
  else if AState.Head.Detached then
  begin
    mHead := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectDetached,
      [AState.Head.ShortRevision(AState.WorkingCopy.Kind)]);
  end
  else
  begin
    mHead := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectBranch,
      [AState.Head.Branch, AState.Head.ShortRevision(AState.WorkingCopy.Kind)]);
  end;
  if AState.Head.Upstream <> '' then
  begin
    mHead := mHead + TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectUpstream, [AState.Head.Upstream]);
  end;
  Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectLine, [mName, mKind, AState.WorkingCopy.Root]) +
    sLineBreak + mHead + sLineBreak + mSource;
end;

procedure TAtlasSettingsPage.RefreshVcsTool(AKind: TAtlasVcsKind);
begin
  if FVcsStates[AKind] = nil then
  begin
    Exit;
  end;
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
    begin
      mDialog.FileName := TAtlasVcsTools.ProgramName(mKind) + '.exe';
    end;
    if mDialog.Execute then
    begin
      FVcsPaths[mKind].Text := mDialog.FileName;
    end;
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
  begin
    Exit;
  end;
  FVcsStates[mKind].Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsToolChecking);
  Allow(FVcsCheck[mKind], False);
  FOnVcsCheck(mKind, Trim(FVcsPaths[mKind].Text));
end;

procedure TAtlasSettingsPage.VcsCheckDone(const ACheck: TAtlasVcsToolCheck);
begin
  if (ACheck.Kind = TAtlasVcsKind.None) or (FVcsStates[ACheck.Kind] = nil) then
  begin
    Exit;
  end;
  FVcsStates[ACheck.Kind].Caption := VcsCheckText(ACheck);
  Allow(FVcsCheck[ACheck.Kind], True);
end;

procedure TAtlasSettingsPage.RefreshVcsProject;
begin
  FVcsProjectAsked := True;
  if not Assigned(FOnVcsProject) then
  begin
    Exit;
  end;
  FVcsProjectInfo.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectQuerying);
  FOnVcsProject();
end;

procedure TAtlasSettingsPage.VcsProjectDone(const AState: TAtlasVcsProjectState);
begin
  if FVcsProjectInfo <> nil then
  begin
    FVcsProjectInfo.Caption := VcsProjectText(AState);
  end;
  // Für „Aktuelles Projekt hinzufügen“: die erkannte Art vorbelegen.
  FVcsDetectedProject := AState.ProjectFile;
  FVcsDetectedKind := AState.WorkingCopy.Kind;
end;

procedure TAtlasSettingsPage.SheetShown(ASheet: TTabSheet);
var
  mParent: TControl;
begin
  if (ASheet = nil) or FVcsProjectAsked or (FVcsProvider = nil) then
  begin
    Exit;
  end;
  mParent := FVcsProvider;
  while (mParent <> nil) and (mParent <> ASheet) do
  begin
    mParent := mParent.Parent;
  end;
  if mParent <> nil then
  begin
    RefreshVcsProject;
  end;
end;

procedure TAtlasSettingsPage.VcsLinkClick(Sender: TObject);
begin
  if Sender = FVcsLinkEditor then
  begin
    SelectPage(PageOf(FGitGutter));
  end
  else if Sender = FVcsLinkWelcome then
  begin
    SelectModulePage('WelcomePageRefreshVcs', 'WelcomePage');
  end
  else if Sender = FVcsLinkIssues then
  begin
    SelectModulePage('IssuesBranchPattern', 'IssuesEnabled');
  end;
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
  AddListColumn(FVcsProjectList, TAtlasTextId.SettingsIssuesProjectMatch, cVcsMatchColumn);
  AddListColumn(FVcsProjectList, TAtlasTextId.SettingsVcsProjectsKind, cVcsKindColumn);
  AddListColumn(FVcsProjectList, TAtlasTextId.SettingsVcsProjectsMainBranch, cVcsBranchColumn);
  AddListColumn(FVcsProjectList, TAtlasTextId.SettingsIssuesProjectSource, cVcsSourceColumn);
  FVcsProjectMatch := TEdit.Create(Self);
  FVcsProjectMatch.OnChange := VcsProjectMatchChange;
  mPanel := AddFieldRow(TAtlasTextId.SettingsIssuesProjectMatch, FVcsProjectMatch, cVcsWideField);
  FVcsProjectMatch.Anchors := [akLeft, akTop, akRight];
  Attach(mPanel, FVcsProjectList);
  // Reihenfolge wie die Werte von vcs.projects[].provider (auto, git, svn, off).
  FVcsProjectProvider := TAtlasChoiceBox.Create(Self);
  FVcsProjectProvider.OnChange := VcsProjectProviderChange;
  Attach(AddFieldRow(TAtlasTextId.SettingsVcsProjectsKind, FVcsProjectProvider, cVcsField), FVcsProjectList);
  FVcsProjectProvider.SetChoices(TArray<string>.Create(VcsProviderCaption('auto'), VcsProviderCaption('git'),
    VcsProviderCaption('svn'), VcsProviderCaption('off')));
  FVcsProjectMainBranch := TEdit.Create(Self);
  FVcsProjectMainBranch.OnChange := VcsProjectMainBranchChange;
  Attach(AddFieldRow(TAtlasTextId.SettingsVcsProjectsMainBranch, FVcsProjectMainBranch, cVcsField),
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
  mPanel := AddPanel(32);
  FVcsProjectAddCurrent := AddRowButton(mPanel, 0, cVcsAddCurrentWidth, TAtlasTextId.SettingsIssuesProjectAddCurrent,
    VcsProjectAddCurrentClick);
  FVcsProjectAdd := AddRowButton(mPanel, cVcsAddCurrentWidth + cVcsButtonGap, cVcsAddWidth,
    TAtlasTextId.SettingsIssuesProjectAdd, VcsProjectAddClick);
  FVcsProjectRemove := AddRowButton(mPanel, cVcsAddCurrentWidth + cVcsAddWidth + cVcsButtonGap + cVcsButtonGap,
    cVcsRemoveWidth, TAtlasTextId.SettingsIssuesConnectionRemove,
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
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectTeam);
  end
  else if VcsProjectCovered(AMapping) then
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectCovered);
  end
  else
  begin
    Result := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectPersonal);
  end;
end;

procedure TAtlasSettingsPage.VcsProjectShowItem(AIndex: Integer);
var
  mRows: TArray<TAtlasVcsProjectMapping>;
  mItem: TListItem;
  mBranch: string;
begin
  mRows := VcsProjectRows;
  if (AIndex < 0) or (AIndex > High(mRows)) or not ListReady(FVcsProjectList) or
    (AIndex >= FVcsProjectList.Items.Count) then
  begin
    Exit;
  end;
  mItem := FVcsProjectList.Items[AIndex];
  mItem.Caption := mRows[AIndex].Match;
  mBranch := mRows[AIndex].MainBranch;
  if mBranch = '' then
  begin
    mBranch := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsGuess);
  end;
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
  begin
    Exit;
  end;
  FVcsContext := TAtlasVcsProjectContext.Empty;
  if Assigned(FOnVcsContext) then
  begin
    FVcsContext := FOnVcsContext();
  end;
  mRows := VcsProjectRows;
  if FVcsProjectSelected > High(mRows) then
  begin
    FVcsProjectSelected := High(mRows);
  end;
  if ListReady(FVcsProjectList) then
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
      begin
        FVcsProjectList.Items[FVcsProjectSelected].Selected := True;
      end;
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
  begin
    FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectReadOnly);
  end
  else if VcsProjectCovered(AMapping) then
  begin
    FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsCoveredHint);
  end
  else
  begin
    FVcsProjectNote.Caption := '';
  end;
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
  begin
    Exit;
  end;
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
  begin
    Sender.Canvas.Font.Color := clGrayText;
  end;
  DefaultDraw := True;
end;

procedure TAtlasSettingsPage.VcsProjectMatchChange(Sender: TObject);
var
  mMatch: string;
  mOther: Integer;
begin
  if FVcsProjectFilling or not VcsProjectEditable then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  mBranch := Trim(FVcsProjectMainBranch.Text);
  // Wie der Server (vcs.projects[].mainBranch): ein Branchname ohne Leerraum.
  for mIndex := 1 to Length(mBranch) do
  begin
    if CharInSet(mBranch[mIndex], [' ', #9]) then
    begin
      FVcsProjectNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsBranchInvalid);
      Exit;
    end;
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
  begin
    Exit;
  end;
  mIndex := TAtlasVcsProjects.IndexOfMatch(FVcsProjects, AMatch);
  if mIndex < 0 then
  begin
    FVcsProjects := FVcsProjects + [TAtlasVcsProjectMapping.Create(AMatch, AProvider, '')];
    mIndex := High(FVcsProjects);
  end;
  FVcsProjectSelected := mIndex;
  RefreshVcsProjects;
  if FVcsProjectMainBranch.CanFocus and FVcsProjectMainBranch.Showing then
  begin
    FVcsProjectMainBranch.SetFocus;
  end;
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
      TAtlasVcsKind.None: ;
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
  if BrowseProject(False, mPath) then
  begin
    VcsProjectAdd(mPath, 'auto');
  end;
end;

procedure TAtlasSettingsPage.VcsProjectAddFolderClick(Sender: TObject);
var
  mPath: string;
begin
  if BrowseProject(True, mPath) then
  begin
    VcsProjectAdd(mPath, 'auto');
  end;
end;

procedure TAtlasSettingsPage.VcsProjectRemoveClick(Sender: TObject);
begin
  if not VcsProjectEditable then
  begin
    Exit;
  end;
  Delete(FVcsProjects, FVcsProjectSelected, 1);
  if FVcsProjectSelected > High(VcsProjectRows) then
  begin
    FVcsProjectSelected := High(VcsProjectRows);
  end;
  RefreshVcsProjects;
end;

function TAtlasSettingsPage.VcsProjectsJson: string;
var
  mKept: TArray<TAtlasVcsProjectMapping>;
  mMapping: TAtlasVcsProjectMapping;
begin
  mKept := nil;
  for mMapping in FVcsProjects do
  begin
    if (mMapping.Match <> '') and (TAtlasVcsProjects.IndexOfMatch(mKept, mMapping.Match) < 0) then
    begin
      mKept := mKept + [mMapping];
    end;
  end;
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
  AddListColumn(FVcsServerList, TAtlasTextId.SettingsVcsServerProject, cVcsServerProjectColumn);
  AddListColumn(FVcsServerList, TAtlasTextId.SettingsVcsServerServer, cVcsServerServerColumn);
  AddListColumn(FVcsServerList, TAtlasTextId.SettingsVcsServerState, cVcsServerStateColumn);
  mPanel := AddPanel(32);
  FVcsServerCheck := AddRowButton(mPanel, 0, cVcsCheckWidth, TAtlasTextId.SettingsVcsServerCheck, VcsServerCheckClick);
  FVcsServerCheckAll := AddRowButton(mPanel, cVcsCheckWidth + cVcsButtonGap, cVcsCheckAllWidth,
    TAtlasTextId.SettingsVcsServerCheckAll, VcsServerCheckAllClick);
  FVcsServerLogin := AddRowButton(mPanel, cVcsCheckWidth + cVcsCheckAllWidth + cVcsButtonGap + cVcsButtonGap,
    cVcsCheckAllWidth, TAtlasTextId.SettingsVcsServerLogin, VcsServerLoginClick);
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
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerChecking));
  end;
  case ACheck.State of
    TAtlasVcsServerState.Reachable:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsServerReachable,
        [FormatDateTime('hh:nn', ACheck.CheckedAt, FormatSettings)]);
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
    begin
      Exit;
    end;
    for mRow in FVcsServerRows do
    begin
      if SameText(mRow.Folder, AFolder) then
      begin
        Exit;
      end;
    end;
    mRow.Name := AName;
    mRow.Folder := AFolder;
    mRow.Check := TAtlasVcsServerCheck.Empty;
    if Assigned(FOnVcsServerState) then
    begin
      mRow.Check := FOnVcsServerState(AFolder);
    end;
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
  begin
    Exit;
  end;
  mOld := FVcsServerRows;
  FVcsServerRows := nil;
  // Erst das aktuelle Projekt, dann die Zeilen der Tabelle Projekte; .dproj und .groupproj gelten für ihren Ordner.
  if FVcsContext.ProjectFile <> '' then
  begin
    AddRow(ExtractFileName(TAtlasProjectMatching.CurrentMatch(FVcsContext.ProjectFile, FVcsContext.GroupFile)),
      ExtractFileDir(FVcsContext.ProjectFile));
  end;
  for mMapping in VcsProjectRows do
  begin
    if mMapping.Kind = TAtlasProjectMatch.Folder then
    begin
      AddRow(ExtractFileName(ExcludeTrailingPathDelimiter(mMapping.Match)),
        ExcludeTrailingPathDelimiter(mMapping.Match));
    end
    else
    begin
      AddRow(ExtractFileName(mMapping.Match), ExtractFileDir(mMapping.Match));
    end;
  end;
  if FVcsServerExtra <> '' then
  begin
    AddRow(ExtractFileName(FVcsServerExtra), FVcsServerExtra);
  end;
  // Laufende Prüfungen bleiben sichtbar.
  for mIndex := 0 to High(FVcsServerRows) do
  begin
    for mOldRow in mOld do
    begin
      if mOldRow.Checking and SameText(mOldRow.Folder, FVcsServerRows[mIndex].Folder) then
      begin
        FVcsServerRows[mIndex].Checking := True;
      end;
    end;
  end;
  if FVcsServerSelected > High(FVcsServerRows) then
  begin
    FVcsServerSelected := High(FVcsServerRows);
  end;
  if (FVcsServerSelected < 0) and (Length(FVcsServerRows) > 0) then
  begin
    FVcsServerSelected := 0;
  end;
  if ListReady(FVcsServerList) then
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
      begin
        FVcsServerList.Items[FVcsServerSelected].Selected := True;
      end;
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
  if (AIndex < 0) or (AIndex > High(FVcsServerRows)) or not ListReady(FVcsServerList) or
    (AIndex >= FVcsServerList.Items.Count) then
  begin
    Exit;
  end;
  mItem := FVcsServerList.Items[AIndex];
  mItem.Caption := FVcsServerRows[AIndex].Name;
  mServer := FVcsServerRows[AIndex].Check.ServerText;
  if mServer = '' then
  begin
    mServer := '–';
  end;
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
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  FVcsServerExtra := ExcludeTrailingPathDelimiter(Trim(AFolder));
  RefreshVcsServers;
  for mIndex := 0 to High(FVcsServerRows) do
  begin
    if SameText(FVcsServerRows[mIndex].Folder, FVcsServerExtra) then
    begin
      FVcsServerSelected := mIndex;
      if ListReady(FVcsServerList) and (mIndex < FVcsServerList.Items.Count) then
      begin
        FVcsServerList.Items[mIndex].Selected := True;
      end;
      SelectPage(PageOf(FVcsServerList));
      VcsServerStart(mIndex);
      Break;
    end;
  end;
end;

procedure TAtlasSettingsPage.VcsServerDone(const AFolder: string; const ACheck: TAtlasVcsServerCheck);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FVcsServerRows) do
  begin
    if SameText(FVcsServerRows[mIndex].Folder, AFolder) then
    begin
      FVcsServerRows[mIndex].Check := ACheck;
      FVcsServerRows[mIndex].Checking := False;
      VcsServerShowItem(mIndex);
    end;
  end;
  if FVcsServerNote <> nil then
  begin
    FVcsServerNote.Caption := '';
  end;
  VcsServerFillButtons;
end;

procedure TAtlasSettingsPage.VcsServerSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not Selected or (Item = nil) then
  begin
    Exit;
  end;
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
  begin
    VcsServerStart(mIndex);
  end;
end;

procedure TAtlasSettingsPage.VcsServerLoginClick(Sender: TObject);
var
  mRow: TAtlasVcsServerRow;
begin
  if (FVcsServerSelected < 0) or (FVcsServerSelected > High(FVcsServerRows)) or not Assigned(FOnVcsServerLogin) then
  begin
    Exit;
  end;
  mRow := FVcsServerRows[FVcsServerSelected];
  if not mRow.Check.CanLogin then
  begin
    Exit;
  end;
  if FOnVcsServerLogin(mRow.Folder, mRow.Check) then
  begin
    // Nach dem Schließen der Konsole prüft der Aufrufer erneut und meldet VcsServerDone.
    FVcsServerRows[FVcsServerSelected].Checking := True;
    VcsServerShowItem(FVcsServerSelected);
    FVcsServerNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginOpen);
  end
  else
  begin
    FVcsServerNote.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginFailed);
  end;
  VcsServerFillButtons;
end;

procedure TAtlasSettingsPage.SelectModulePage(const AName, AFallback: string);
var
  mControl: TControl;
begin
  // Die Einstellungen baut das Modul (Tracker #1455, Willkommensseite #1456); fehlt es, bleibt der Reiter mit
  // seinem Modulschalter.
  mControl := ControlOfSetting(AName);
  if mControl = nil then
  begin
    mControl := ControlOfSetting(AFallback);
  end;
  if mControl <> nil then
  begin
    SelectPage(PageOf(mControl));
  end;
end;

function TAtlasSettingsPage.AddFieldRow(AId: TAtlasTextId; AControl: TWinControl;
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

function TAtlasSettingsPage.AddRowButton(AParent: TWinControl; ALeft, AWidth: Integer; AId: TAtlasTextId;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := TAtlasStrings.Text(AId);
  Result.Left := ALeft;
  Result.Top := cRowButtonTop;
  Result.Width := AWidth;
  Result.OnClick := AClick;
end;

class procedure TAtlasSettingsPage.AddListColumn(AList: TListView; AId: TAtlasTextId; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := TAtlasStrings.Text(AId);
  mColumn.Width := AWidth;
end;

function TAtlasSettingsPage.BrowseProject(AFolder: Boolean; out APath: string): Boolean;
var
  mFolder: TFileOpenDialog;
  mFile: TOpenDialog;
begin
  APath := '';
  if Assigned(FOnBrowseProject) then
  begin
    Exit(FOnBrowseProject(AFolder, APath));
  end;
  if AFolder then
  begin
    mFolder := TFileOpenDialog.Create(nil);
    try
      mFolder.Options := mFolder.Options + [fdoPickFolders, fdoPathMustExist];
      Result := mFolder.Execute;
      if Result then
      begin
        APath := mFolder.FileName;
      end;
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
    begin
      APath := mFile.FileName;
    end;
  finally
    mFile.Free;
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

const
  /// <summary>Zielplattformen für Bauen beim Öffnen (#1293), Namen wie in der IDE; Eintrag 0 = wie im Projekt.
  /// </summary>
  OpenBuildPlatforms: array[0..7] of string = ('', 'Win32', 'Win64', 'Win64x', 'Linux64', 'OSXARM64', 'Android64',
    'iOSDevice64');

procedure TAtlasSettingsPage.AddOpenBuildSection;
begin
  AddTitle(TAtlasTextId.SettingsOpenBuildTitle);
  // Reihenfolge: nicht bauen, dann wie TAtlasOpenBuildSettings.KindNames (check, make, build).
  FOpenBuild := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuild),
    [TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildNone), TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildCheck),
    TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildMake), TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildBuild)]);
  // Reihenfolge wie TAtlasOpenBuildScope: alle, nur das aktive.
  FOpenBuildScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildScope),
    [TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildScopeAll),
    TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildScopeActive)]);
  FOpenBuildDelay := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildDelay));
  FOpenBuildExclude := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildExclude));
  FOpenBuildConfig := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildConfig));
  // Auswahl statt Freitext (#1293): Tippfehler griffen still nicht; der leere Eintrag heißt wie im Projekt.
  FOpenBuildPlatform := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildPlatform), OpenBuildPlatforms);
end;

procedure TAtlasSettingsPage.LoadOpenBuild(const ASettings: TAtlasPluginSettings);
var
  Index: Integer;
begin
  FOpenBuild.Choice := 0;
  if ASettings.BuildOnOpen then
  begin
    for Index := Low(TAtlasOpenBuildSettings.KindNames) to High(TAtlasOpenBuildSettings.KindNames) do
    begin
      if SameText(TAtlasOpenBuildSettings.KindNames[Index],
        TAtlasOpenBuildSettings.KindName(TAtlasOpenBuildSettings.KindOf(ASettings.BuildOnOpenKind))) then
      begin
        FOpenBuild.Choice := Index + 1;
      end;
    end;
  end;
  FOpenBuildScope.Choice := Ord(TAtlasOpenBuildSettings.ScopeOf(ASettings.BuildOnOpenScope));
  FOpenBuildDelay.Text := IntToStr(ASettings.BuildOnOpenDelayMs);
  FOpenBuildExclude.Text := TAtlasOpenBuildSettings.NormalizedExclude(ASettings.BuildOnOpenExclude);
  FOpenBuildConfig.Text := ASettings.BuildOnOpenConfig;
  FOpenBuildPlatform.Choice := 0;
  for Index := 1 to High(OpenBuildPlatforms) do
  begin
    if TAtlasOpenBuildSettings.PickTarget(ASettings.BuildOnOpenPlatform, [OpenBuildPlatforms[Index]]) <> '' then
    begin
      FOpenBuildPlatform.Choice := Index;
    end;
  end;
end;

procedure TAtlasSettingsPage.SaveOpenBuild(var ASettings: TAtlasPluginSettings);
begin
  // „nicht bauen“ behält die Art für das nächste Einschalten (Schnellschalter).
  ASettings.BuildOnOpen := FOpenBuild.Choice > 0;
  if (FOpenBuild.Choice > 0) and (FOpenBuild.Choice - 1 <= High(TAtlasOpenBuildSettings.KindNames)) then
  begin
    ASettings.BuildOnOpenKind := TAtlasOpenBuildSettings.KindNames[FOpenBuild.Choice - 1];
  end;
  if (FOpenBuildScope.Choice >= Ord(Low(TAtlasOpenBuildScope))) and
    (FOpenBuildScope.Choice <= Ord(High(TAtlasOpenBuildScope))) then
  begin
    ASettings.BuildOnOpenScope := TAtlasOpenBuildSettings.ScopeNames[TAtlasOpenBuildScope(FOpenBuildScope.Choice)];
  end;
  ASettings.BuildOnOpenDelayMs := StrToIntDef(FOpenBuildDelay.Text, ASettings.BuildOnOpenDelayMs);
  ASettings.BuildOnOpenExclude := TAtlasOpenBuildSettings.NormalizedExclude(FOpenBuildExclude.Text);
  ASettings.BuildOnOpenConfig := Trim(FOpenBuildConfig.Text);
  ASettings.BuildOnOpenPlatform := '';
  if (FOpenBuildPlatform.Choice > 0) and (FOpenBuildPlatform.Choice <= High(OpenBuildPlatforms)) then
  begin
    ASettings.BuildOnOpenPlatform := OpenBuildPlatforms[FOpenBuildPlatform.Choice];
  end;
end;

procedure TAtlasSettingsPage.AddTasksSection;
begin
  AddTitle(TAtlasTextId.SettingsTasksTitle);
  FTasksEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTasksEnabled));
  FTasksProblemsFromOutput := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTasksProblemsFromOutput));
  // Reihenfolge wie TasksBeforeBuildNames: off, warn, block.
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
  mIndex: Integer;
begin
  FTasksEnabled.Checked := ASettings.TasksEnabled;
  FTasksProblemsFromOutput.Checked := ASettings.TasksProblemsFromOutput;
  // Unbekannt = „off“ wie beim Lesen der Einstellungen.
  FTasksBeforeBuild.Choice := 0;
  for mIndex := Low(TasksBeforeBuildNames) to High(TasksBeforeBuildNames) do
  begin
    if SameText(Trim(ASettings.TasksBeforeBuild), TasksBeforeBuildNames[mIndex]) then
    begin
      FTasksBeforeBuild.Choice := mIndex;
    end;
  end;
  FTasksSaveBeforeRun.Checked := ASettings.TasksSaveBeforeRun;
  FTasksRunChecksParallel.Checked := ASettings.TasksRunChecksParallel;
  FTasksOnlyFindings.Checked := ASettings.TasksOnlyFindings;
end;

procedure TAtlasSettingsPage.SaveTasks(var ASettings: TAtlasPluginSettings);
begin
  ASettings.TasksEnabled := FTasksEnabled.Checked;
  ASettings.TasksProblemsFromOutput := FTasksProblemsFromOutput.Checked;
  if (FTasksBeforeBuild.Choice >= Low(TasksBeforeBuildNames)) and
    (FTasksBeforeBuild.Choice <= High(TasksBeforeBuildNames)) then
  begin
    ASettings.TasksBeforeBuild := TasksBeforeBuildNames[FTasksBeforeBuild.Choice];
  end;
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
  begin
    if TAtlasBuildPipelineSettings.HasTarget[Check] then
    begin
      FReleaseCheckChoices[Check] := AddChoice(TAtlasStrings.Text(Captions[Check]),
        [TAtlasStrings.Text(TAtlasTextId.SettingsReleaseNotChecked),
        TAtlasStrings.Text(TAtlasTextId.SettingsReleaseExpectOff),
        TAtlasStrings.Text(TAtlasTextId.SettingsReleaseExpectOn)]);
    end
    else
    begin
      FReleaseCheckBoxes[Check] := AddCheck(TAtlasStrings.Text(Captions[Check]));
    end;
  end;
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
  FReleaseConfigs.Text := TAtlasBuildPipelineSettings.NormalizedConfigurations(ASettings.ReleaseConfigs);
  Checks := TAtlasReleaseChecks.Parse(ASettings.ReleaseChecks);
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    if FReleaseCheckChoices[Check] <> nil then
    begin
      if not Checks.Items[Check].Enabled then
      begin
        FReleaseCheckChoices[Check].Choice := 0;
      end
      else if Checks.Items[Check].Expected then
      begin
        FReleaseCheckChoices[Check].Choice := 2;
      end
      else
      begin
        FReleaseCheckChoices[Check].Choice := 1;
      end;
    end
    else if FReleaseCheckBoxes[Check] <> nil then
    begin
      FReleaseCheckBoxes[Check].Checked := Checks.Items[Check].Enabled;
    end;
  end;
end;

procedure TAtlasSettingsPage.SaveRelease(var ASettings: TAtlasPluginSettings);
var
  Checks: TAtlasReleaseChecks;
  Check: TAtlasReleaseCheck;
begin
  ASettings.ReleaseGuard := FReleaseGuard.Checked;
  ASettings.ReleaseConfigs := TAtlasBuildPipelineSettings.NormalizedConfigurations(FReleaseConfigs.Text);
  Checks := TAtlasReleaseChecks.Parse(ASettings.ReleaseChecks);
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    if FReleaseCheckChoices[Check] <> nil then
    begin
      if FReleaseCheckChoices[Check].Choice >= 0 then
      begin
        Checks.Items[Check].Enabled := FReleaseCheckChoices[Check].Choice > 0;
        if FReleaseCheckChoices[Check].Choice > 0 then
        begin
          Checks.Items[Check].Expected := FReleaseCheckChoices[Check].Choice = 2;
        end;
      end;
    end
    else if FReleaseCheckBoxes[Check] <> nil then
    begin
      Checks.Items[Check].Enabled := FReleaseCheckBoxes[Check].Checked;
    end;
  end;
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
  Kind: TAtlasOverviewKind;
  VisualizerKind: TAtlasVisualizerKind;
  StepFilterKind: TStepFilterKind;
  Target: TAtlasReassignedTarget;
  mIndex: Integer;
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
  FMarks.Bind(FEditorDesignerBar, ['EditorDesignerBar']);
  FMarks.Bind(FDesignerSearchKey, ['DesignerSearchKey']);
  FMarks.Bind(FDesignerSearchStyle, ['DesignerSearchStyle']);
  FMarks.Bind(FDesignerTabOrderClick, ['DesignerTabOrderClick']);
  FMarks.Bind(FDesignerAlign, ['DesignerAlign']);
  FMarks.Bind(FEditorStatusBarItems, ['EditorStatusBarItems']);
  FMarks.Bind(FStickyScroll, ['StickyScroll']);
  FMarks.Bind(FStickyScrollMaxLines, ['StickyScrollMaxLines']);
  FMarks.Bind(FStickyScrollTypes, ['StickyScrollTypes']);
  FMarks.Bind(FStickyScrollRoutines, ['StickyScrollRoutines']);
  FMarks.Bind(FStickyScrollBlocks, ['StickyScrollBlocks']);
  FMarks.Bind(FStickyScrollLoops, ['StickyScrollLoops']);
  FMarks.Bind(FStickyScrollTry, ['StickyScrollTry']);
  FMarks.Bind(FStickyScrollCase, ['StickyScrollCase']);
  FMarks.Bind(FStickyScrollWith, ['StickyScrollWith']);
  FMarks.Bind(FStickyScrollBlockMinLines, ['StickyScrollBlockMinLines']);
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
  begin
    FMarks.Bind(FReassignedTargets[Target], ['ReassignedTargets']);
  end;
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
  begin
    FMarks.Bind(FOverviewKinds[Kind], ['OverviewRulerKinds']);
  end;
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
  FMarks.Bind(FFixBulk, ['FixBulk']);
  FMarks.Bind(FProblemsCompilerMerge, ['ProblemsCompilerMerge']);
  FMarks.Bind(FProblemsShowCompilerCode, ['ProblemsShowCompilerCode']);
  FMarks.Bind(FHoverProblemActions, ['HoverProblemActions']);
  FMarks.Bind(FProblemsStatusCounter, ['ProblemsStatusCounter']);
  FMarks.Bind(FStatusField, ['StatusField']);
  FMarks.Bind(FDiagnosticMode, ['DiagnosticMode']);
  FMarks.Bind(FDiagnosticsProcesses, ['DiagnosticsProcesses']);
  FMarks.Bind(FServerStatusWindow, ['ServerStatusWindow']);
  FMarks.Bind(FArchitecture, ['ArchitectureEnabled']);
  FMarks.Bind(FArchitectureScope, ['ArchitectureScope']);
  FMarks.Bind(FArchitectureLibrary, ['ArchitectureIncludeLibraryUnits']);
  FMarks.Bind(FArchitectureCentral, ['ArchitectureCentralUnits']);
  FMarks.Bind(FQuery, ['QueryEnabled']);
  FMarks.Bind(FHotspots, ['HotspotsEnabled']);
  FMarks.Bind(FHotspotsMonths, ['HotspotsMonths']);
  FMarks.Bind(FHotspotsMinCommits, ['HotspotsCouplingMinCommits']);
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
  FMarks.Bind(FTestsAffected, ['TestsAffected']);
  FMarks.Bind(FTestsAffectedDepth, ['TestsAffectedDepth']);
  FMarks.Bind(FTestsAffectedBeforeCommit, ['TestsAffectedBeforeCommit']);
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
  begin
    FMarks.Bind(FDebugVisualizerKinds[VisualizerKind], ['DebugVisualizerTypes']);
  end;
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
  begin
    FMarks.Bind(FDebugStepFilterKinds[StepFilterKind], ['DebugStepFilterKinds']);
  end;
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
  FMarks.Bind(FUnitSearchFormCaptions, ['UnitSearchFormCaptions']);
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
  FMarks.Bind(FSearchFromFirst, ['SearchFromFirstHit']);
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
  FMarks.Bind(FOpenBuildConfig, ['BuildOnOpenConfig']);
  FMarks.Bind(FOpenBuildPlatform, ['BuildOnOpenPlatform']);
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
  // Modul-Schalter (#1454).
  for mIndex := 0 to High(FModuleChecks) do
  begin
    FMarks.Bind(FModuleChecks[mIndex], [FModuleNames[mIndex]]);
  end;
end;

destructor TAtlasSettingsPage.Destroy;
begin
  // Zuerst die Abschnitte: Ihre Elemente liegen in Zeilen der Seite.
  CloseSections;
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
  begin
    FCatalog := TAtlasSettingsCatalog.CreateDefault;
  end;
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
  begin
    Modified := TAtlasSettingsTransfer.ModifiedNames(Catalog, CurrentSettings);
  end;
  FMarks.Show(Modified, FSettingsMarkModified.Checked);
  FExperimentalBanner.Visible := FMarks.HasExperimental and not FExperimentalEnabled.Checked;
  UpdateLocks;
  // Geänderte Werte ändern sich mit jeder Eingabe; der Filter folgt, auch im Baum.
  if FMarks.Filter = sfModified then
  begin
    FMarks.ApplyFilter(sfModified);
    if ListReady(FTree) then
    begin
      FillTree;
    end;
  end;
end;

procedure TAtlasSettingsPage.MarksChanged(Sender: TObject);
begin
  RefreshMarks;
end;

procedure TAtlasSettingsPage.ResetNames(const ANames: TArray<string>);
begin
  if Length(ANames) = 0 then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  // Unterpunkt: nur seine Einstellungen; Hauptknoten: der ganze Bereich mit allen Unterpunkten (#890).
  if FNodePages[Current].Node <> '' then
  begin
    Names := FMarks.NamesIn(FNodePages[Current].Box);
  end
  else
  begin
    Names := nil;
    for Index := 0 to High(FNodePages) do
    begin
      if FNodePages[Index].Area = FNodePages[Current].Area then
      begin
        Names := Names + FMarks.NamesIn(FNodePages[Index].Box);
      end;
    end;
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
  begin
    FOnExportSettings(CurrentSettings);
  end;
end;

procedure TAtlasSettingsPage.ImportClick(Sender: TObject);
var
  Imported: TAtlasPluginSettings;
begin
  if Assigned(FOnImportSettings) and FOnImportSettings(CurrentSettings, False, Imported) then
  begin
    LoadFrom(Imported);
  end;
end;

procedure TAtlasSettingsPage.ProfileClick(Sender: TObject);
var
  Imported: TAtlasPluginSettings;
begin
  if Assigned(FOnImportSettings) and FOnImportSettings(CurrentSettings, True, Imported) then
  begin
    LoadFrom(Imported);
  end;
end;

procedure TAtlasSettingsPage.ResetAllClick(Sender: TObject);
var
  Reset: TAtlasPluginSettings;
begin
  if Assigned(FOnResetAllSettings) and FOnResetAllSettings(CurrentSettings, Reset) then
  begin
    LoadFrom(Reset);
  end;
end;

procedure TAtlasSettingsPage.AddSheet(AId: TAtlasTextId);
begin
  AddSheetCaption(TAtlasStrings.Text(AId));
end;

procedure TAtlasSettingsPage.CreateWnd;
var
  Page: TAtlasSettingsNodePage;
begin
  inherited CreateWnd;
  // Je Knoten ein Reiter, in der Reihenfolge des Baums.
  for Page in FNodePages do
  begin
    if Page.Sheet.PageControl = nil then
    begin
      Page.Sheet.PageControl := FPages;
      Page.Sheet.TabVisible := False;
    end;
  end;
  // Der Baum braucht ein Fenster für seine Knoten (wie die Reiter); zeigt die zuletzt gewählte Seite.
  FillTree;
  // Die Liste der Sicherung braucht ein Fenster; vorher bleibt sie leer.
  RefreshFuse;
  RefreshFavorites;
  RefreshVcsProjects;
  // Abschnitte der Module (#1455) füllen ihre Listen erst mit Fenster.
  SectionsWindowReady;
  // Gewünschte Einstellung (#628) erst mit Fenster zeigen.
  if FPendingReveal <> '' then
  begin
    ApplyReveal(FPendingReveal);
  end;
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
  begin
    Parent := Parent.Parent;
  end;
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
    begin
      Dec(Position);
    end;
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
  begin
    if Item = AText then
    begin
      Exit;
    end;
  end;
  AList := AList + [AText];
end;

function PageIndexOf(ANode: TTreeNode): Integer;
begin
  Result := -1;
  if ANode <> nil then
  begin
    Result := Integer(NativeInt(ANode.Data));
  end;
end;

procedure TAtlasSettingsPage.Attach(ARow, AAnchor: TControl);
begin
  if (ARow <> nil) and (AAnchor <> nil) then
  begin
    FAttached.AddOrSetValue(ARow, AAnchor);
  end;
end;

function TAtlasSettingsPage.AddNodePage(AArea: Integer; const ANode: string): Integer;
begin
  if ANode = '' then
  begin
    Result := AddNodePageCaption(AArea, ANode, '');
  end
  else
  begin
    Result := AddNodePageCaption(AArea, ANode, FGroups.NodeCaption(ANode, TAtlasStrings.Language = TAtlasLanguage.English));
  end;
end;

function TAtlasSettingsPage.AddNodePageCaption(AArea: Integer; const ANode, ACaption: string): Integer;
var
  Page: TAtlasSettingsNodePage;
  Index: Integer;
begin
  for Index := 0 to High(FNodePages) do
  begin
    if (FNodePages[Index].Area = AArea) and SameText(FNodePages[Index].Node, ANode) then
    begin
      Exit(Index);
    end;
  end;
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
  begin
    FBaselineInfo.Caption := FOnBaselineInfo();
  end;
end;

procedure TAtlasSettingsPage.RulesProjectClick(Sender: TObject);
begin
  if Assigned(FOnRulesProject) then
  begin
    FOnRulesProject();
  end;
end;

procedure TAtlasSettingsPage.RulesGlobalClick(Sender: TObject);
begin
  if Assigned(FOnRulesGlobal) then
  begin
    FOnRulesGlobal();
  end;
end;

procedure TAtlasSettingsPage.BaselineUpdateClick(Sender: TObject);
begin
  if Assigned(FOnBaselineUpdate) then
  begin
    FBaselineInfo.Caption := FOnBaselineUpdate();
  end;
end;

procedure TAtlasSettingsPage.BaselineDeleteClick(Sender: TObject);
begin
  if Assigned(FOnBaselineDelete) and (MessageDlg(TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineDeleteConfirm),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes) then
  begin
    FBaselineInfo.Caption := FOnBaselineDelete();
  end;
end;

procedure TAtlasSettingsPage.Place(AControl: TControl; AHolder: TWinControl);
begin
  if AHolder is TAtlasSettingsGroup then
  begin
    TAtlasSettingsGroup(AHolder).AddRow(AControl);
  end
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
  begin
    BuildArea(Area);
  end;
  AddRulePages;
  for Frame in FFrames do
  begin
    if not (Frame.Parent is TAtlasSettingsGroup) then
    begin
      Frame.AdjustHeight;
    end;
  end;
  for Area := 0 to High(FSheets) do
  begin
    AddOverview(Area);
  end;
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
    begin
      if FGroups.Contains(Candidate) then
      begin
        Exit(Candidate);
      end;
    end;
  end;

  // Hängt eine Zeile an einem Element in AControl (Liste und Knöpfe einer Funktion)?
  function HasAttached(AControl: TControl): Boolean;
  var
    Item: TPair<TControl, TControl>;
  begin
    for Item in FAttached do
    begin
      if Inside(Item.Value, AControl) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  function RowOfAnchor(AAnchor: TControl): Integer;
  var
    Candidate: Integer;
  begin
    for Candidate := 0 to High(Rows) do
    begin
      if Inside(AAnchor, Rows[Candidate]) then
      begin
        Exit(Candidate);
      end;
    end;
    Result := -1;
  end;

  // Rahmen des Hauptschalters AName, wenn er auf der Seite APage steht; sonst nil.
  function FrameFor(const AName: string; APage: Integer): TAtlasSettingsGroup;
  var
    Candidate: Integer;
  begin
    Result := nil;
    if AName = '' then
    begin
      Exit;
    end;
    for Candidate := 0 to High(Rows) do
    begin
      if (Frames[Candidate] <> nil) and (RowPages[Candidate] = APage) and SameText(Names[Candidate], AName) then
      begin
        Exit(Frames[Candidate]);
      end;
    end;
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
    begin
      Kinds[Index] := rkBound;
    end
    else if FAttached.ContainsKey(Rows[Index]) then
    begin
      Kinds[Index] := rkAttached;
    end
    else if IsLabelRow(Rows[Index]) then
    begin
      Kinds[Index] := rkLabel;
    end
    else
    begin
      Kinds[Index] := rkOther;
    end;
  end;
  // Unterpunkt jeder Einstellung; Hauptschalter (auch Kontrollkästchen mit angehängter Liste) bekommen einen Rahmen.
  for Index := 0 to High(Rows) do
  begin
    if Kinds[Index] = rkBound then
    begin
      RowPages[Index] := AddNodePage(AArea, FGroups.NodeOf(Names[Index]));
      if FGroups.IsMaster(Names[Index]) or ((Rows[Index] is TCheckBox) and HasAttached(Rows[Index])) then
      begin
        Frames[Index] := TAtlasSettingsGroup.Create(Self);
        FFrames := FFrames + [Frames[Index]];
      end;
    end;
  end;
  // Behälter: der Rahmen des Hauptschalters auf derselben Seite, sonst die Seite selbst.
  for Index := 0 to High(Rows) do
  begin
    if Kinds[Index] = rkBound then
    begin
      Holders[Index] := FNodePages[RowPages[Index]].Box;
      Frame := FrameFor(FGroups.ParentOf(Names[Index]), RowPages[Index]);
      if Frame <> nil then
      begin
        Holders[Index] := Frame;
      end;
      Resolved[Index] := True;
    end;
  end;
  // Zeilen ohne eigene Einstellung, die zu einer gehören (Liste, Knöpfe): in deren Rahmen.
  for Index := 0 to High(Rows) do
  begin
    if Kinds[Index] = rkAttached then
    begin
      Other := RowOfAnchor(FAttached[Rows[Index]]);
      if (Other < 0) or not Resolved[Other] then
      begin
        Continue;
      end;
      RowPages[Index] := RowPages[Other];
      Holders[Index] := Holders[Other];
      if Frames[Other] <> nil then
      begin
        Holders[Index] := Frames[Other];
      end;
      Resolved[Index] := True;
    end;
  end;
  // Übrige Zeilen (Serverpfad, Knöpfe des Bereichs): oben auf der Seite der Zeile davor.
  Page := Main;
  for Index := 0 to High(Rows) do
  begin
    if Resolved[Index] then
    begin
      Page := RowPages[Index];
    end
    else if Kinds[Index] <> rkLabel then
    begin
      RowPages[Index] := Page;
      Holders[Index] := FNodePages[Page].Box;
      Resolved[Index] := True;
    end;
  end;
  // Überschriften und Beschriftungen gehören zur Zeile darunter, am Ende des Bereichs zur Zeile darüber.
  for Index := High(Rows) downto 0 do
  begin
    if not Resolved[Index] and (Index < High(Rows)) and Resolved[Index + 1] then
    begin
      RowPages[Index] := RowPages[Index + 1];
      Holders[Index] := Holders[Index + 1];
      Resolved[Index] := True;
    end;
  end;
  for Index := 1 to High(Rows) do
  begin
    if not Resolved[Index] then
    begin
      RowPages[Index] := RowPages[Index - 1];
      Holders[Index] := Holders[Index - 1];
      Resolved[Index] := True;
    end;
  end;
  for Index := 0 to High(Rows) do
  begin
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
    begin
      Place(Rows[Index], Holders[Index]);
    end;
  end;
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
    begin
      Continue;
    end;
    Box := FNodePages[Index].Box;
    for Child := 0 to Box.ControlCount - 1 do
    begin
      if not (Box.Controls[Child] is TAtlasSettingsGroup) then
      begin
        Continue;
      end;
      Frame := TAtlasSettingsGroup(Box.Controls[Child]);
      if Frame.Master = nil then
      begin
        Continue;
      end;
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
  begin
    Overview.AdjustHeight;
  end;
end;

procedure TAtlasSettingsPage.MirrorClick(Sender: TObject);
var
  Index: Integer;
begin
  if FSyncing or not (Sender is TCheckBox) then
  begin
    Exit;
  end;
  Index := TCheckBox(Sender).Tag;
  if (Index >= 0) and (Index <= High(FMirrored)) then
  begin
    FMirrored[Index].Checked := TCheckBox(Sender).Checked;
  end;
end;

procedure TAtlasSettingsPage.DetailsClick(Sender: TObject);
begin
  if Sender is TControl then
  begin
    SelectPage(TControl(Sender).Tag);
  end;
end;

function TAtlasSettingsPage.IsOverview(AFrame: TAtlasSettingsGroup): Boolean;
var
  Overview: TAtlasSettingsGroup;
begin
  for Overview in FOverviews do
  begin
    if Overview = AFrame then
    begin
      Exit(True);
    end;
  end;
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
  begin
    mParent := mParent.Parent;
  end;
  if mParent = nil then
  begin
    Exit;
  end;
  for Index := 0 to High(FNodePages) do
  begin
    if FNodePages[Index].Sheet = mParent then
    begin
      Exit(Index);
    end;
  end;
end;

function TAtlasSettingsPage.ActiveNode: Integer;
var
  Index: Integer;
begin
  Result := -1;
  if FPages.ActivePage = nil then
  begin
    Exit;
  end;
  for Index := 0 to High(FNodePages) do
  begin
    if FNodePages[Index].Sheet = FPages.ActivePage then
    begin
      Exit(Index);
    end;
  end;
end;

procedure TAtlasSettingsPage.SelectPage(AIndex: Integer);
var
  Index: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FNodePages)) then
  begin
    Exit;
  end;
  FPages.ActivePage := FNodePages[AIndex].Sheet;
  SheetShown(FNodePages[AIndex].Sheet);
  if not ListReady(FTree) then
  begin
    Exit;
  end;
  for Index := 0 to FTree.Items.Count - 1 do
  begin
    if PageIndexOf(FTree.Items[Index]) = AIndex then
    begin
      FTree.Selected := FTree.Items[Index];
      Break;
    end;
  end;
end;

function TAtlasSettingsPage.PageShown(AIndex: Integer): Boolean;
var
  Index: Integer;
begin
  // Der Filter blendet Unterpunkte ohne Treffer aus; ein Bereich bleibt, solange einer seiner Punkte trifft.
  if (FMarks.Filter = sfAll) or FMarks.HasMatch(FNodePages[AIndex].Box) then
  begin
    Exit(True);
  end;
  if FNodePages[AIndex].Node = '' then
  begin
    for Index := 0 to High(FNodePages) do
    begin
      if (Index <> AIndex) and (FNodePages[Index].Area = FNodePages[AIndex].Area) and
        FMarks.HasMatch(FNodePages[Index].Box) then
      begin
        Exit(True);
      end;
    end;
  end;
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
  begin
    Selected := FLastPage;
  end;
  FFillingTree := True;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    for Index := 0 to High(FNodePages) do
    begin
      if not PageShown(Index) then
      begin
        Continue;
      end;
      Area := FNodePages[Index].Area;
      if FNodePages[Index].Node = '' then
      begin
        Node := FTree.Items.AddObject(nil, FNodePages[Index].Caption, Pointer(NativeInt(Index)));
        AreaNodes[Area] := Node;
      end
      else
      begin
        Node := FTree.Items.AddChildObject(AreaNodes[Area], FNodePages[Index].Caption, Pointer(NativeInt(Index)));
      end;
      if Index = Selected then
      begin
        Wanted := Node;
      end;
    end;
    if (Wanted = nil) and (FTree.Items.Count > 0) then
    begin
      Wanted := FTree.Items[0];
    end;
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
      begin
        Wanted.Parent.Expanded := True;
      end
      else if not FStateKnown and Wanted.HasChildren then
      begin
        Wanted.Expanded := True;
      end;
      FTree.Selected := Wanted;
      FPages.ActivePage := FNodePages[PageIndexOf(Wanted)].Sheet;
    end;
  finally
    FTree.Items.EndUpdate;
    FFillingTree := False;
  end;
  RefreshTree;
end;

function TAtlasSettingsPage.ListReady(AControl: TWinControl): Boolean;
begin
  if not AControl.HandleAllocated and HandleAllocated then
  begin
    AControl.HandleNeeded;
  end;
  Result := AControl.HandleAllocated;
end;

procedure TAtlasSettingsPage.RefreshTree;
var
  Index, Page: Integer;
  Node: TTreeNode;
  mText: string;
begin
  if not ListReady(FTree) then
  begin
    Exit;
  end;
  for Index := 0 to FTree.Items.Count - 1 do
  begin
    Node := FTree.Items[Index];
    Page := PageIndexOf(Node);
    if (Page < 0) or (Page > High(FNodePages)) then
    begin
      Continue;
    end;
    // Punkt wie an den Einstellungen: Auf dieser Seite ist etwas geändert.
    mText := FNodePages[Page].Caption;
    if FMarks.HasMarked(FNodePages[Page].Box) then
    begin
      mText := TAtlasSettingsMarks.Dot + mText;
    end;
    if Node.Text <> mText then
    begin
      Node.Text := mText;
    end;
  end;
  FTree.Invalidate;
end;

procedure TAtlasSettingsPage.TreeChange(Sender: TObject; Node: TTreeNode);
var
  Index: Integer;
begin
  Index := PageIndexOf(Node);
  if (Index < 0) or (Index > High(FNodePages)) or (csDestroying in ComponentState) then
  begin
    Exit;
  end;
  FPages.ActivePage := FNodePages[Index].Sheet;
  SheetShown(FNodePages[Index].Sheet);
  // Beim Neuaufbau des Baums wählt er selbst; gemerkt wird nur die Wahl des Nutzers.
  if FFillingTree then
  begin
    Exit;
  end;
  FLastPage := Index;
  FStateKnown := True;
end;

procedure TAtlasSettingsPage.TreeExpanded(Sender: TObject; Node: TTreeNode);
var
  Index, Area: Integer;
begin
  Index := PageIndexOf(Node);
  if FFillingTree or (csDestroying in ComponentState) or (Index < 0) or (Index > High(FNodePages)) then
  begin
    Exit;
  end;
  Area := FNodePages[Index].Area;
  if (Area < 0) or (Area > High(Byte)) then
  begin
    Exit;
  end;
  if Node.Expanded then
  begin
    Include(FExpandedAreas, Byte(Area));
  end
  else
  begin
    Exclude(FExpandedAreas, Byte(Area));
  end;
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
  begin
    Sender.Canvas.Font.Color := clGrayText;
  end;
end;

function TAtlasSettingsPage.IsOn(const AName: string): Boolean;
var
  Control: TControl;
begin
  // Kontrollkästchen: angehakt; Auswahl (etwa „Beim Öffnen bauen“): ein Eintrag außer dem ersten („nicht …“).
  Control := FMarks.ControlOfName(AName);
  if Control is TCheckBox then
  begin
    Result := TCheckBox(Control).Checked;
  end
  else if Control is TAtlasChoiceBox then
  begin
    Result := TAtlasChoiceBox(Control).Choice > 0;
  end
  else
  begin
    Result := True;
  end;
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
        begin
          mCaption := FGroups.KeyOf(ALock.Master);
        end;
        Where := '';
        Page := PageOf(FMarks.ControlOfName(ALock.Master));
        if Page >= 0 then
        begin
          Where := FSheets[FNodePages[Page].Area].Caption;
          if FNodePages[Page].Node <> '' then
          begin
            Where := Where + ' › ' + FNodePages[Page].Caption;
          end;
        end
        else
        begin
          Entry := Catalog.IndexOfName(ALock.Master);
          if Entry >= 0 then
          begin
            Where := Catalog.Entries[Entry].Page;
          end;
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
  begin
    Exit;
  end;
  if not ALocked then
  begin
    FLockedControls.Remove(AControl);
  end
  else if not FLockedControls.Contains(AControl) then
  begin
    FLockedControls.Add(AControl);
  end;
  AControl.Enabled := not ALocked and not FOwnOff.Contains(AControl);
  if (AControl is TWinControl) and not (AControl is TAtlasSettingsGroup) then
  begin
    for Index := 0 to TWinControl(AControl).ControlCount - 1 do
    begin
      SetLocked(TWinControl(AControl).Controls[Index], ALocked);
    end;
  end;
end;

procedure TAtlasSettingsPage.Allow(AControl: TControl; AValue: Boolean);
begin
  // Eigene Logik der Seite (Liste leer, Server fehlt); eine Sperre durch den Hauptschalter bleibt bestehen.
  if AValue then
  begin
    FOwnOff.Remove(AControl);
  end
  else if not FOwnOff.Contains(AControl) then
  begin
    FOwnOff.Add(AControl);
  end;
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
    begin
      Continue;
    end;
    if Control is TAtlasSettingsGroup then
    begin
      Frame := TAtlasSettingsGroup(Control);
      if IsOverview(Frame) or (Frame.Master = nil) then
      begin
        Continue;
      end;
      // Der Hauptschalter selbst: gesperrt durch einen Rahmen darüber, einen Schalter woanders oder experimentell.
      Lock := LockOfName(Frame.MasterName);
      MasterLocked := ALocked or Lock.Locked;
      SetLocked(Frame.Master, MasterLocked);
      if Lock.Locked and not ALocked then
      begin
        Frame.ShowReason(LockText(Lock));
      end
      else
      begin
        Frame.ShowReason('');
      end;
      ApplyLocks(Frame, MasterLocked or not IsOn(Frame.MasterName), AOutside);
      Continue;
    end;
    Locked := ALocked;
    if not Locked then
    begin
      // Zeile ohne Rahmen: ihr Hauptschalter steht auf einer anderen Seite (Grund oben auf der Seite).
      Names := FMarks.NamesWithin(Control);
      if (Length(Names) = 0) and FAttached.TryGetValue(Control, Anchor) then
      begin
        Names := FMarks.NamesWithin(Anchor);
      end;
      for Setting in Names do
      begin
        Lock := LockOfName(Setting);
        if Lock.Locked then
        begin
          Locked := True;
          if Lock.Reason = lrMasterOff then
          begin
            AddUnique(AOutside, LockText(Lock));
          end;
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
      begin
        Continue;
      end;
      Any := True;
      if Frame.Master.Enabled and IsOn(Frame.MasterName) then
      begin
        Exit(False);
      end;
    end
    else if Length(FMarks.NamesWithin(Control)) > 0 then
    begin
      Any := True;
      if Control.Enabled then
      begin
        Exit(False);
      end;
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
  begin
    Exit;
  end;
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
  begin
    FNodePages[Index].Gray := PageGray(Index);
  end;
  RefreshTree;
end;

function TAtlasSettingsPage.FrameOf(const AName: string): TAtlasSettingsGroup;
var
  Frame: TAtlasSettingsGroup;
begin
  for Frame in FFrames do
  begin
    if SameText(Frame.MasterName, AName) then
    begin
      Exit(Frame);
    end;
  end;
  Result := nil;
end;

function TAtlasSettingsPage.NodeSheet(const ANode: string): TTabSheet;
var
  Page: TAtlasSettingsNodePage;
begin
  for Page in FNodePages do
  begin
    if (ANode <> '') and SameText(Page.Node, ANode) then
    begin
      Exit(Page.Sheet);
    end;
  end;
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
  begin
    Exit;
  end;
  for Index := 0 to High(FMirrored) do
  begin
    if FMirrored[Index] = Frame.Master then
    begin
      Exit(FMirrors[Index]);
    end;
  end;
end;

function TAtlasSettingsPage.SheetGray(ASheet: TTabSheet): Boolean;
var
  Index: Integer;
begin
  for Index := 0 to High(FNodePages) do
  begin
    if FNodePages[Index].Sheet = ASheet then
    begin
      Exit(FNodePages[Index].Gray);
    end;
  end;
  Result := False;
end;

function TAtlasSettingsPage.NodeOfSheet(ASheet: TTabSheet): string;
var
  Page: TAtlasSettingsNodePage;
begin
  for Page in FNodePages do
  begin
    if Page.Sheet = ASheet then
    begin
      Exit(Page.Node);
    end;
  end;
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
  begin
    Exit;
  end;
  Favorites := nil;
  if Assigned(FOnFavorites) then
  begin
    Favorites := FOnFavorites();
  end;
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
    begin
      FFavoritesList.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsFavoritesNone));
    end;
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
  begin
    Exit;
  end;
  Keys := nil;
  for Index := 0 to Min(FFavoritesList.Items.Count, Length(FFavoriteKeys)) - 1 do
  begin
    if FFavoritesList.Selected[Index] then
    begin
      Keys := Keys + [FFavoriteKeys[Index]];
    end;
  end;
  if Length(Keys) = 0 then
  begin
    Exit;
  end;
  FOnRemoveFavorites(Keys);
  RefreshFavorites;
end;

procedure TAtlasSettingsPage.FavoritesRemoveAllClick(Sender: TObject);
begin
  if not Assigned(FOnRemoveFavorites) or (Length(FFavoriteKeys) = 0) then
  begin
    Exit;
  end;
  FOnRemoveFavorites(Copy(FFavoriteKeys));
  RefreshFavorites;
end;

procedure TAtlasSettingsPage.AddTitle(AId: TAtlasTextId);
begin
  AddTitleText(TAtlasStrings.Text(AId));
end;

procedure TAtlasSettingsPage.AddTitleText(const ACaption: string);
var
  Panel: TWinControl;
  mCaption: TLabel;
begin
  Panel := AddPanel(22);
  mCaption := TLabel.Create(Self);
  mCaption.Parent := Panel;
  mCaption.Caption := ACaption;
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
  begin
    Exit;
  end;
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
  begin
    StartIndexCommand(FOnIndexMetrics);
  end
  else if not FIndexBusy then
  begin
    FIndexInfo.Caption := '';
  end;
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
  begin
    Exit;
  end;
  if Assigned(FConfirmClear) then
  begin
    Confirmed := FConfirmClear();
  end
  else
  begin
    Confirmed := MessageDlg(TAtlasStrings.Text(TAtlasTextId.SettingsIndexClearConfirm), mtConfirmation,
      [mbYes, mbNo], 0) = mrYes;
  end;
  if Confirmed then
  begin
    StartIndexCommand(FOnIndexClear);
  end;
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
  begin
    Exit;
  end;
  FFuseList.Items.BeginUpdate;
  try
    FFuseList.Items.Clear;
    // Objects: Feature + 1; nil bei einer Quelle (Name im Text).
    for Feature in TAtlasGuard.DisabledSet do
    begin
      FFuseList.Items.AddObject(TAtlasGuard.FeatureName(Feature), TObject(NativeInt(Ord(Feature) + 1)));
    end;
    for mName in TAtlasGuard.DisabledProviders do
    begin
      FFuseList.Items.AddObject(mName, nil);
    end;
    Any := FFuseList.Items.Count > 0;
    if not Any then
    begin
      FFuseList.Items.Add(TAtlasStrings.Text(TAtlasTextId.SettingsFuseNone));
    end;
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
  begin
    if FFuseList.Selected[Index] then
    begin
      mTag := NativeInt(FFuseList.Items.Objects[Index]);
      if mTag > 0 then
      begin
        TAtlasGuard.Enable(TAtlasFeature(mTag - 1));
      end
      else
      begin
        TAtlasGuard.EnableProvider(FFuseList.Items[Index]);
      end;
    end;
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
  FUnitSearchFormCaptions := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchFormCaptions));
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
  FSearchFromFirst := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSearchFromFirst));
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

function TAtlasSettingsPage.AddModuleSwitch(const AName: string): TCheckBox;
var
  mIndex: Integer;
  mCaption: string;
begin
  mCaption := AName;
  mIndex := Catalog.IndexOfName(AName);
  if mIndex >= 0 then
  begin
    if TAtlasStrings.Language = TAtlasLanguage.English then
    begin
      mCaption := Catalog[mIndex].CaptionEn;
    end
    else
    begin
      mCaption := Catalog[mIndex].Caption;
    end;
  end;
  Result := AddCheck(mCaption);
  FModuleChecks := FModuleChecks + [Result];
  FModuleNames := FModuleNames + [AName];
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
  begin
    Names := Names + [TAtlasNotificationsWindow.SourceCaption(Source)];
  end;
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
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  Dialog := TColorDialog.Create(nil);
  try
    Dialog.Color := TShape(Sender).Brush.Color;
    Dialog.Options := Dialog.Options + [cdFullOpen];
    if Dialog.Execute then
    begin
      TShape(Sender).Brush.Color := Dialog.Color;
    end;
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
  begin
    ASwatches[Index].Brush.Color := TColor(APairs[Index]);
  end;
end;

class function TAtlasSettingsPage.PairsSetting(const ASwatches: array of TShape;
  const ADefault: TAtlasPairColors): string;
var
  Pairs: TAtlasPairColors;
  Index: Integer;
begin
  for Index := 0 to High(Pairs) do
  begin
    Pairs[Index] := TAtlasColor(ColorToRGB(ASwatches[Index].Brush.Color));
  end;
  Result := TAtlasColors.PairsText(Pairs);
  if Result = TAtlasColors.PairsText(ADefault) then
  begin
    Result := '';
  end;
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

procedure TAtlasSettingsPage.LoadFrom(const ASettings: TAtlasPluginSettings);
begin
  // Während des Ladens lösen die Elemente keine Neuberechnung der Punkte aus.
  FMarks.BeginLoad;
  try
    LoadControls(ASettings);
    LoadSections(ASettings);
  finally
    FMarks.EndLoad;
  end;
  RefreshMarks;
end;

procedure TAtlasSettingsPage.LoadControls(const ASettings: TAtlasPluginSettings);
var
  Kind: TAtlasOverviewKind;
  Kinds: TAtlasOverviewKinds;
  VisualizerKind: TAtlasVisualizerKind;
  StepFilterKind: TStepFilterKind;
  VisualizerKinds: TAtlasVisualizerKinds;
  StepFilterKinds: TStepFilterKinds;
  Target: TAtlasReassignedTarget;
  Targets: TAtlasReassignedTargets;
  mStore: IAtlasMemorySettingsStore;
  mIndex: Integer;
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
  FEditorDesignerBar.Checked := ASettings.EditorDesignerBar;
  FDesignerSearchKey.Text := ShortCutToText(TShortCut(ASettings.DesignerSearchKey));
  FDesignerSearchStyle.Choice := Ord(SameText(ASettings.DesignerSearchStyle,
    TAtlasPluginSettings.DesignerSearchPopup));
  FDesignerTabOrderClick.Checked := ASettings.DesignerTabOrderClick;
  FDesignerAlign.Checked := ASettings.DesignerAlign;
  FEditorStatusBarItems.Text := ASettings.EditorStatusBarItems;
  FStickyScroll.Checked := ASettings.StickyScroll;
  FStickyScrollMaxLines.Text := IntToStr(ASettings.StickyScrollMaxLines);
  FStickyScrollTypes.Checked := ASettings.StickyScrollTypes;
  FStickyScrollRoutines.Checked := ASettings.StickyScrollRoutines;
  FStickyScrollBlocks.Checked := ASettings.StickyScrollBlocks;
  FStickyScrollLoops.Checked := ASettings.StickyScrollLoops;
  FStickyScrollTry.Checked := ASettings.StickyScrollTry;
  FStickyScrollCase.Checked := ASettings.StickyScrollCase;
  FStickyScrollWith.Checked := ASettings.StickyScrollWith;
  FStickyScrollBlockMinLines.Text := IntToStr(ASettings.StickyScrollBlockMinLines);
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
  begin
    FReassignedTargets[Target].Checked := Target in Targets;
  end;
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
  begin
    FOverviewKinds[Kind].Checked := Kind in Kinds;
  end;
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
  begin
    FCompleteStatementBeginEnd.Choice := 0;
  end
  else if ASettings.CompleteStatementBeginEnd = TAtlasPluginSettings.BeginEndNever then
  begin
    FCompleteStatementBeginEnd.Choice := 2;
  end;
  FCompleteStatementTryKind.Choice := 0;
  if ASettings.CompleteStatementTryKind = TAtlasPluginSettings.TryKindExcept then
  begin
    FCompleteStatementTryKind.Choice := 1;
  end
  else if ASettings.CompleteStatementTryKind = TAtlasPluginSettings.TryKindAsk then
  begin
    FCompleteStatementTryKind.Choice := 2;
  end;
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
  begin
    FMultiCursorModifier.Choice := 1;
  end;
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
  FFixBulk.Checked := ASettings.FixBulk;
  FProblemsStatusCounter.Checked := ASettings.ProblemsStatusCounter;
  FStatusField.Checked := ASettings.StatusField;
  FDiagnosticMode.Checked := ASettings.DiagnosticMode;
  FDiagnosticsProcesses.Checked := ASettings.DiagnosticsProcesses;
  FServerStatusWindow.Checked := ASettings.ServerStatusWindow;
  FArchitecture.Checked := ASettings.ArchitectureEnabled;
  FArchitectureScope.Choice := Max(0, IndexText(ASettings.ArchitectureScope, ['projectGroup', 'project']));
  FArchitectureLibrary.Checked := ASettings.ArchitectureIncludeLibraryUnits;
  FArchitectureCentral.Text := IntToStr(ASettings.ArchitectureCentralUnits);
  FQuery.Checked := ASettings.QueryEnabled;
  FHotspots.Checked := ASettings.HotspotsEnabled;
  FHotspotsMonths.Text := IntToStr(ASettings.HotspotsMonths);
  FHotspotsMinCommits.Text := IntToStr(ASettings.HotspotsCouplingMinCommits);
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
  begin
    FStatusToggles.Choice := 1;
  end
  else if not ASettings.StatusTogglesOnRightClick then
  begin
    FStatusToggles.Choice := 2;
  end
  else
  begin
    FStatusToggles.Choice := 0;
  end;
  if SameText(ASettings.IndexProgressPlace, 'menu') then
  begin
    FIndexProgress.Choice := 1;
  end
  else if SameText(ASettings.IndexProgressPlace, 'off') then
  begin
    FIndexProgress.Choice := 2;
  end
  else
  begin
    FIndexProgress.Choice := 0;
  end;
  FStatusHidden.Text := ASettings.StatusFieldHidden;
  FIndexGroup.Checked := ASettings.IndexProjectGroup;
  FIndexSearch.Checked := ASettings.IndexSearchPaths;
  FIndexLibrary.Checked := ASettings.IndexLibraryPaths;
  FIndexUsages.Checked := ASettings.IndexUsages;
  FMemoryBudget.Text := IntToStr(ASettings.MemoryBudgetMb);
  FAfterSave.Choice := 0;
  if ASettings.CheckOnSave then
  begin
    FAfterSave.Choice := 1;
  end
  else if ASettings.CompileOnSave then
  begin
    FAfterSave.Choice := 2;
  end;
  FCheckDelay.Text := IntToStr(ASettings.CheckOnSaveDelayMs);
  FCheckMax.Text := IntToStr(ASettings.CheckOnSaveMaxMs);
  FMcpBuild.Checked := ASettings.McpBuild;
  LoadOpenBuild(ASettings);
  LoadTasks(ASettings);
  FTestRun.Checked := ASettings.TestRun;
  FTestsBuildFirst.Checked := ASettings.TestsBuildFirst;
  FTestsAfterBuild.Checked := ASettings.TestsAfterBuild;
  FTestsAffected.Checked := ASettings.TestsAffected;
  FTestsAffectedDepth.Text := IntToStr(ASettings.TestsAffectedDepth);
  FTestsAffectedBeforeCommit.Checked := ASettings.TestsAffectedBeforeCommit;
  FBuildZeroHints.Checked := ASettings.BuildZeroHints;
  FShowInterfaceCost.Checked := ASettings.ShowInterfaceCost;
  FBuildSummary.Checked := ASettings.BuildSummary;
  FBuildWarningsAsErrors.Text := TAtlasBuildVerdicts.NormalizeCodes(ASettings.BuildWarningsAsErrors);
  FBuildGate.Choice := Ord(TAtlasBuildPipelineSettings.GateOf(ASettings.BuildGate));
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
  begin
    FDebugVisualizerKinds[VisualizerKind].Checked := VisualizerKind in VisualizerKinds;
  end;
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
  begin
    FDebugStepFilterKinds[StepFilterKind].Checked := StepFilterKind in StepFilterKinds;
  end;
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
  FUnitSearchFormCaptions.Checked := ASettings.UnitSearchFormCaptions;
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
  FSearchFromFirst.Checked := ASettings.SearchFromFirstHit;
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
  FVcsExternalsRules.Text := TAtlasVcsExternalRules.RulesText(TAtlasVcsExternalRules.RulesOf(ASettings.VcsExternalsRules));
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
  begin
    FVcsProjectSelected := 0;
  end;
  RefreshVcsProjects;
  FSettingsExportImport.Checked := ASettings.SettingsExportImport;
  FSettingsMarkModified.Checked := ASettings.SettingsMarkModified;
  FSettingsBackupBeforeImport.Checked := ASettings.SettingsBackupBeforeImport;
  FSettingsExportSecrets.Choice := Ord(ASettings.SettingsExportSecrets = 'placeholder');
  // Modul-Schalter (#1454) über ihre Namen; ohne Eintrag an.
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  for mIndex := 0 to High(FModuleChecks) do
  begin
    FModuleChecks[mIndex].Checked := mStore.ReadInteger(FModuleNames[mIndex], 1) <> 0;
  end;
  RefreshFuse;
  RefreshIndex;
end;

procedure TAtlasSettingsPage.SaveTo(var ASettings: TAtlasPluginSettings);
var
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
  mStore: IAtlasMemorySettingsStore;
  mIndex: Integer;
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
  ASettings.EditorDesignerBar := FEditorDesignerBar.Checked;
  ASettings.DesignerSearchKey := Integer(TextToShortCut(Trim(FDesignerSearchKey.Text)));
  if FDesignerSearchStyle.Choice = 1 then
  begin
    ASettings.DesignerSearchStyle := TAtlasPluginSettings.DesignerSearchPopup;
  end
  else
  begin
    ASettings.DesignerSearchStyle := TAtlasPluginSettings.DesignerSearchWindow;
  end;
  ASettings.DesignerTabOrderClick := FDesignerTabOrderClick.Checked;
  ASettings.DesignerAlign := FDesignerAlign.Checked;
  ASettings.EditorStatusBarItems := TAtlasStatusBarItems.Normalize(FEditorStatusBarItems.Text);
  ASettings.StickyScroll := FStickyScroll.Checked;
  ASettings.StickyScrollMaxLines := StrToIntDef(FStickyScrollMaxLines.Text, ASettings.StickyScrollMaxLines);
  ASettings.StickyScrollTypes := FStickyScrollTypes.Checked;
  ASettings.StickyScrollRoutines := FStickyScrollRoutines.Checked;
  ASettings.StickyScrollBlocks := FStickyScrollBlocks.Checked;
  ASettings.StickyScrollLoops := FStickyScrollLoops.Checked;
  ASettings.StickyScrollTry := FStickyScrollTry.Checked;
  ASettings.StickyScrollCase := FStickyScrollCase.Checked;
  ASettings.StickyScrollWith := FStickyScrollWith.Checked;
  ASettings.StickyScrollBlockMinLines := StrToIntDef(FStickyScrollBlockMinLines.Text,
    ASettings.StickyScrollBlockMinLines);
  ASettings.Minimap := FMinimap.Checked;
  ASettings.MinimapRender := 'blocks';
  if FMinimapRender.Choice = 1 then
  begin
    ASettings.MinimapRender := 'characters';
  end;
  ASettings.MinimapWidth := StrToIntDef(FMinimapWidth.Text, ASettings.MinimapWidth);
  ASettings.MinimapScale := StrToIntDef(FMinimapScale.Text, ASettings.MinimapScale);
  ASettings.MinimapMaxColumn := StrToIntDef(FMinimapMaxColumn.Text, ASettings.MinimapMaxColumn);
  ASettings.MinimapSide := 'right';
  if FMinimapSide.Choice = 1 then
  begin
    ASettings.MinimapSide := 'left';
  end;
  ASettings.MinimapShowSlider := 'always';
  if FMinimapShowSlider.Choice = 1 then
  begin
    ASettings.MinimapShowSlider := 'mouseover';
  end;
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
  begin
    if FReassignedTargets[Target].Checked then
    begin
      Include(Targets, Target);
    end;
  end;
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
  begin
    if FOverviewKinds[Kind].Checked then
    begin
      Include(Kinds, Kind);
    end;
  end;
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
  begin
    ASettings.ToggleBlockCommentStyle := 'parens';
  end;
  ASettings.ToggleBlockCommentFallback := 'lineComments';
  if FToggleBlockCommentFallback.Choice = 1 then
  begin
    ASettings.ToggleBlockCommentFallback := 'refuse';
  end;
  ASettings.ToggleBlockCommentOwnLines := FToggleBlockCommentOwnLines.Checked;
  ASettings.ToggleBlockCommentWithoutSelection := 'statement';
  if FToggleBlockCommentScope.Choice = 1 then
  begin
    ASettings.ToggleBlockCommentWithoutSelection := 'line';
  end;
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
  begin
    ASettings.MultiCursorModifier := TAtlasPluginSettings.MultiCursorModifierCtrl;
  end;
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
  begin
    ASettings.CompletionListMode := TAtlasListModes.ModeNames[TAtlasListMode(FListMode.Choice)];
  end;
  if (FListScope.Choice >= Ord(Low(TAtlasListScope))) and (FListScope.Choice <= Ord(High(TAtlasListScope))) then
  begin
    ASettings.CompletionListScope := TAtlasListModes.ScopeNames[TAtlasListScope(FListScope.Choice)];
  end;
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
  begin
    ASettings.ProblemsWindowScope := ScopeValues[FProblemsWindowScope.Choice];
  end;
  if (FProblemsWindowGroupBy.Choice >= 0) and (FProblemsWindowGroupBy.Choice <= High(GroupByValues)) then
  begin
    ASettings.ProblemsWindowGroupBy := GroupByValues[FProblemsWindowGroupBy.Choice];
  end;
  ASettings.ProblemsWindowCompiler := FProblemsWindowCompiler.Checked;
  ASettings.ProblemsWindowFollowCursor := FProblemsWindowFollowCursor.Checked;
  ASettings.ProblemsWindowOpenFirst := FProblemsWindowOpenFirst.Checked;
  if (FProblemsWindowClosedUnits.Choice >= 0) and (FProblemsWindowClosedUnits.Choice <= High(ClosedUnitsValues)) then
  begin
    ASettings.ProblemsWindowClosedUnits := ClosedUnitsValues[FProblemsWindowClosedUnits.Choice];
  end;
  ASettings.ProblemsWindowShowCleanActive := FProblemsWindowShowCleanActive.Checked;
  if (FProblemsCompilerMerge.Choice >= 0) and (FProblemsCompilerMerge.Choice <= High(CompilerMergeValues)) then
  begin
    ASettings.ProblemsCompilerMerge := CompilerMergeValues[FProblemsCompilerMerge.Choice];
  end;
  ASettings.ProblemsShowCompilerCode := FProblemsShowCompilerCode.Checked;
  ASettings.ProblemsLive := FProblemsLive.Checked;
  ASettings.FixBulk := FFixBulk.Checked;
  ASettings.ProblemsStatusCounter := FProblemsStatusCounter.Checked;
  ASettings.StatusField := FStatusField.Checked;
  ASettings.DiagnosticMode := FDiagnosticMode.Checked;
  ASettings.DiagnosticsProcesses := FDiagnosticsProcesses.Checked;
  ASettings.ServerStatusWindow := FServerStatusWindow.Checked;
  ASettings.ArchitectureEnabled := FArchitecture.Checked;
  if FArchitectureScope.Choice = 1 then
  begin
    ASettings.ArchitectureScope := 'project';
  end
  else
  begin
    ASettings.ArchitectureScope := 'projectGroup';
  end;
  ASettings.ArchitectureIncludeLibraryUnits := FArchitectureLibrary.Checked;
  ASettings.ArchitectureCentralUnits := StrToIntDef(FArchitectureCentral.Text, ASettings.ArchitectureCentralUnits);
  ASettings.QueryEnabled := FQuery.Checked;
  ASettings.HotspotsEnabled := FHotspots.Checked;
  ASettings.HotspotsMonths := StrToIntDef(FHotspotsMonths.Text, ASettings.HotspotsMonths);
  ASettings.HotspotsCouplingMinCommits := StrToIntDef(FHotspotsMinCommits.Text, ASettings.HotspotsCouplingMinCommits);
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
  ASettings.TestsAffected := FTestsAffected.Checked;
  ASettings.TestsAffectedDepth := StrToIntDef(FTestsAffectedDepth.Text, ASettings.TestsAffectedDepth);
  ASettings.TestsAffectedBeforeCommit := FTestsAffectedBeforeCommit.Checked;
  ASettings.BuildZeroHints := FBuildZeroHints.Checked;
  ASettings.ShowInterfaceCost := FShowInterfaceCost.Checked;
  ASettings.BuildSummary := FBuildSummary.Checked;
  // Ungültige Einträge fallen weg; gespeichert wird die einheitliche Form „W1035, H2164“.
  ASettings.BuildWarningsAsErrors := TAtlasBuildVerdicts.NormalizeCodes(FBuildWarningsAsErrors.Text);
  if (FBuildGate.Choice >= Ord(Low(TAtlasBuildGate))) and (FBuildGate.Choice <= Ord(High(TAtlasBuildGate))) then
  begin
    ASettings.BuildGate := TAtlasBuildPipelineSettings.GateNames[TAtlasBuildGate(FBuildGate.Choice)];
  end;
  ASettings.BuildGateTimeoutMs := EnsureRange(StrToIntDef(FBuildGateTimeout.Text, ASettings.BuildGateTimeoutMs),
    TAtlasBuildPipelineSettings.GateMinTimeoutMs, TAtlasBuildPipelineSettings.GateMaxTimeoutMs);
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
  begin
    if FDebugVisualizerKinds[VisualizerKind].Checked then
    begin
      Include(VisualizerKinds, VisualizerKind);
    end;
  end;
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
  begin
    if FDebugStepFilterKinds[StepFilterKind].Checked then
    begin
      Include(StepFilterKinds, StepFilterKind);
    end;
  end;
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
  ASettings.DebugOwnCodeFolders := TAtlasFolderList.Text(FDebugOwnCodeFolders.Text);
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
  ASettings.UnitSearchFormCaptions := FUnitSearchFormCaptions.Checked;
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
  ASettings.SearchFromFirstHit := FSearchFromFirst.Checked;
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
  begin
    ASettings.VcsBranchSvnSource := 'workingCopy';
  end
  else
  begin
    ASettings.VcsBranchSvnSource := 'head';
  end;
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
  if TAtlasVcsExternalRules.RulesOfText(FVcsExternalsRules.Text, mRules, mInvalid) then
  begin
    ASettings.VcsExternalsRules := TAtlasVcsExternalRules.RulesJson(mRules);
  end;
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
  ASettings.SettingsExportImport := FSettingsExportImport.Checked;
  ASettings.SettingsMarkModified := FSettingsMarkModified.Checked;
  ASettings.SettingsBackupBeforeImport := FSettingsBackupBeforeImport.Checked;
  ASettings.SettingsExportSecrets := 'omit';
  if FSettingsExportSecrets.Choice = 1 then
  begin
    ASettings.SettingsExportSecrets := 'placeholder';
  end;
  ASettings.ListWidth := FWidths.ListWidth;
  ASettings.PanelWidth := FWidths.PanelWidth;
  // Modul-Schalter (#1454) über ihre Namen.
  if Length(FModuleChecks) > 0 then
  begin
    mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
    for mIndex := 0 to High(FModuleChecks) do
    begin
      mStore.WriteInteger(FModuleNames[mIndex], Ord(FModuleChecks[mIndex].Checked));
    end;
    ASettings.Load(mStore);
  end;
  SaveSections(ASettings);
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
  begin
    Path := FDefaultServerPath;
  end;
  if Path = '' then
  begin
    FServerStatus.Caption := '';
  end
  else if FileExists(Path) then
  begin
    FServerStatus.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsServerFound, [Path]);
  end
  else
  begin
    FServerStatus.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsServerMissing, [Path]);
  end;
  // Version des Servers (#227): aus der Datei bzw. vom laufenden Server.
  Version := '';
  if Assigned(FOnServerVersion) and (Path <> '') and FileExists(Path) then
  begin
    Version := FOnServerVersion(Path);
    if Version = '' then
    begin
      Version := TAtlasStrings.Text(TAtlasTextId.SettingsServerVersionUnknown);
    end
    else
    begin
      Version := TAtlasStrings.Fmt(TAtlasTextId.SettingsServerVersion, [Version]);
    end;
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
  begin
    FWidths.ListWidth := 0;
  end
  else if FWidths.ListWidth = 0 then
  begin
    FWidths.ListWidth := TAtlasPluginSettings.MinListWidth + 160;
  end;
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
    begin
      Dialog.FileName := Trim(FServerPath.Text);
    end
    else if FDefaultServerPath <> '' then
    begin
      Dialog.InitialDir := ExtractFilePath(FDefaultServerPath);
    end;
    if Dialog.Execute then
    begin
      FServerPath.Text := Dialog.FileName;
    end;
  finally
    Dialog.Free;
  end;
end;

procedure TAtlasSettingsPage.ResetHistoryClick(Sender: TObject);
begin
  if Assigned(FOnResetHistory) then
  begin
    FOnResetHistory();
  end;
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
  begin
    Commands := FOnToolbarCommands();
  end;
  Config.Items := TAtlasToolbarItems.Parse(FEditorToolbarItems.Text);
  Config.Labels := FEditorToolbarLabels.Checked;
  Config.Position := AtlasToolbarPositions[EnsureRange(FEditorToolbarPosition.Choice, 0,
    High(AtlasToolbarPositions))];
  if not TAtlasToolbarCustomizeDialog.Execute(Commands, Config) then
  begin
    Exit;
  end;
  FEditorToolbarItems.Text := TAtlasToolbarItems.Format(Config.Items);
  FEditorToolbarLabels.Checked := Config.Labels;
  FEditorToolbarPosition.Choice := Max(0, IndexText(Config.Position, AtlasToolbarPositions));
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
  begin
    FOnOpenTeamFile();
  end;
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
  Issue: TAtlasTeamIssue;
  InvalidText: string;
  Lines: TArray<string>;
begin
  // Ausgeschaltet wird die Datei nicht gelesen.
  Team := TAtlasTeamFile.Empty;
  if FTeamFile.Checked and Assigned(FOnTeamFile) then
  begin
    Team := FOnTeamFile();
  end;
  FTeamSnippets.Caption := '';
  if Team.Valid and (Team.Snippets <> '') then
  begin
    FTeamSnippets.Caption := TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamSnippets, [Team.Snippets]);
  end;
  if not FTeamFile.Checked then
  begin
    Lines := [TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileOff)];
  end
  else if Team.Project = '' then
  begin
    Lines := [TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileNoProject)];
  end
  else if not Team.Exists then
  begin
    Lines := [TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileMissing)];
  end
  else
  begin
    Lines := [TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileLocation, [Team.FileName])];
    if not Team.Valid then
    begin
      // Mit Zeile und Spalte, wenn bekannt: Dort steht der Fehler im JSON.
      InvalidText := TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileInvalid);
      for Issue in Team.Issues do
      begin
        if (Issue.Kind = TAtlasTeamIssueKind.Syntax) and (Issue.Line > 0) then
        begin
          InvalidText := TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileInvalidAt, [Issue.Line, Issue.Column]);
          Break;
        end;
      end;
      Lines := Lines + [InvalidText];
    end
    else
    begin
      for Value in TAtlasTeamFile.Values(Team) do
      begin
        Lines := Lines + [TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileValue, [Value.Key, Value.Value])];
      end;
      if Length(Lines) = 1 then
      begin
        Lines := Lines + [TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileNoValues)];
      end;
      if Length(Team.Issues) > 0 then
      begin
        Lines := Lines + [TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileIssues, [Length(Team.Issues)])];
      end;
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


procedure TAtlasSettingsPage.AddSheetCaption(const ACaption: string);
begin
  FSheet := TTabSheet.Create(Self);
  FSheet.Caption := ACaption;
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

function TAtlasSettingsPage.SheetOfArea(const AArea: string): Integer;
var
  mSheet, mIndex: Integer;
  mName: string;
begin
  // Reiter eines Bereichs: der erste, auf dem eine Einstellung dieses Bereichs (x-area) steht.
  for mSheet := 0 to High(FBoxes) do
  begin
    for mName in FMarks.NamesIn(FBoxes[mSheet]) do
    begin
      mIndex := Catalog.IndexOfName(mName);
      if (mIndex >= 0) and SameText(Catalog[mIndex].Area, AArea) then
      begin
        Exit(mSheet);
      end;
    end;
  end;
  for mSheet := 0 to High(FSectionAreas) do
  begin
    if SameText(FSectionAreas[mSheet].Key, AArea) then
    begin
      Exit(FSectionAreas[mSheet].Value);
    end;
  end;
  Result := -1;
end;

procedure TAtlasSettingsPage.AddModuleSections;
var
  mItem: IInterface;
  mProvider: IAtlasSettingsSectionProvider;
begin
  // Abschnitte der Module (#1455): in den Reiter ihres Bereichs, hinter die Einstellungen von Base.
  for mItem in AtlasModuleRegistry.FindAll(IAtlasSettingsSectionProvider) do
  begin
    if Supports(mItem, IAtlasSettingsSectionProvider, mProvider) then
    begin
      AddModuleSection(mProvider);
    end;
  end;
  FSectionWatch := TAtlasSettingsSectionWatch.Create(Self);
  FSectionWatchRegistration := AtlasModuleRegistry.Subscribe(FSectionWatch);
end;

procedure TAtlasSettingsPage.AddModuleSection(const AProvider: IAtlasSettingsSectionProvider);
var
  mSection: IAtlasSettingsSection;
begin
  try
    mSection := AProvider.CreateSection;
  except
    on E: Exception do
    begin
      TAtlasGuard.ReportProvider('settings', E);
      Exit;
    end;
  end;
  if mSection = nil then
  begin
    Exit;
  end;
  AddBuiltSection(AProvider, mSection);
end;

procedure TAtlasSettingsPage.AddBuiltSection(const AProvider: IAtlasSettingsSectionProvider;
  const ASection: IAtlasSettingsSection);
var
  mSheet, mIndex: Integer;
  mControl: TControl;
  mHost: TAtlasSettingsSectionHost;
  mHostRef: IAtlasSettingsSectionHost;
begin
  mSheet := SheetOfArea(ASection.AreaId);
  if mSheet < 0 then
  begin
    // Unbekannter Bereich: eigener Reiter mit der Beschriftung des Katalogs (sonst die Id).
    AddSheetCaption(Catalog.AreaCaption(ASection.AreaId, TAtlasStrings.Language = TAtlasLanguage.English));
    mSheet := High(FSheets);
    FSectionAreas := FSectionAreas + [TPair<string, Integer>.Create(ASection.AreaId, mSheet)];
  end;
  FSheet := FSheets[mSheet];
  FContent := FBoxes[mSheet];
  // Neue Zeilen unter die vorhandenen: alTop ordnet nach Top.
  FNextTop := 100;
  for mIndex := 0 to FContent.ControlCount - 1 do
  begin
    mControl := FContent.Controls[mIndex];
    FNextTop := Max(FNextTop, mControl.Top + mControl.Height + 100);
  end;
  mHost := TAtlasSettingsSectionHost.Create(Self);
  mHostRef := mHost;
  try
    ASection.Build(mHostRef);
  except
    on E: Exception do
    begin
      // Ein fehlerhafter Abschnitt darf den Optionsdialog nicht verhindern; er bleibt zu und wird gemeldet.
      mHost.Detach;
      TAtlasGuard.ReportProvider('settings:' + ASection.OwnerId, E);
      ASection.Close;
      Exit;
    end;
  end;
  FSections := FSections + [ASection];
  FSectionProviders := FSectionProviders + [AProvider];
  FSectionHosts := FSectionHosts + [mHostRef];
end;

procedure TAtlasSettingsPage.AddSectionBinding(const AName: string; AControl: TControl;
  const AValues: TArray<string>);
var
  mBinding: TAtlasSettingsSectionBinding;
begin
  FMarks.Bind(AControl, [AName]);
  Bind(AName, AControl);
  mBinding := Default(TAtlasSettingsSectionBinding);
  mBinding.Name := AName;
  mBinding.Control := AControl;
  mBinding.Values := AValues;
  FSectionBindings := FSectionBindings + [mBinding];
end;

function TAtlasSettingsPage.SectionValues(const AStore: IAtlasMemorySettingsStore): IAtlasSettingsValues;
begin
  Result := TAtlasSettingsStoreValues.Create(Catalog, AStore,
    TAtlasMemorySettingsStore.FromSettings(TAtlasPluginSettings.Defaults));
end;

procedure TAtlasSettingsPage.LoadSections(const ASettings: TAtlasPluginSettings);
var
  mStore: IAtlasMemorySettingsStore;
  mValues: IAtlasSettingsValues;
  mBinding: TAtlasSettingsSectionBinding;
  mSection: IAtlasSettingsSection;
  mText: string;
begin
  if (Length(FSections) = 0) and (Length(FSectionBindings) = 0) then
  begin
    Exit;
  end;
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  for mBinding in FSectionBindings do
  begin
    mText := mStore.Text(mBinding.Name);
    if mBinding.Control is TCheckBox then
    begin
      TCheckBox(mBinding.Control).Checked := mStore.ReadInteger(mBinding.Name, 0) <> 0;
    end
    else if mBinding.Control is TAtlasChoiceBox then
    begin
      TAtlasChoiceBox(mBinding.Control).Choice := ChoiceOf(mText, mBinding.Values);
    end
    else if mBinding.Control is TEdit then
    begin
      TEdit(mBinding.Control).Text := mText;
    end;
  end;
  mValues := SectionValues(mStore);
  for mSection in FSections do
  begin
    mSection.Load(mValues);
  end;
end;

procedure TAtlasSettingsPage.SaveSections(var ASettings: TAtlasPluginSettings);
var
  mStore: IAtlasMemorySettingsStore;
  mBinding: TAtlasSettingsSectionBinding;
  mSection: IAtlasSettingsSection;
  mChoice: Integer;
  mValues: IAtlasSettingsValues;
begin
  if (Length(FSections) = 0) and (Length(FSectionBindings) = 0) then
  begin
    Exit;
  end;
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  for mBinding in FSectionBindings do
  begin
    if mBinding.Control is TCheckBox then
    begin
      mStore.WriteInteger(mBinding.Name, Ord(TCheckBox(mBinding.Control).Checked));
    end
    else if mBinding.Control is TAtlasChoiceBox then
    begin
      mChoice := TAtlasChoiceBox(mBinding.Control).Choice;
      if (mChoice >= 0) and (mChoice <= High(mBinding.Values)) then
      begin
        WriteText(mStore, mBinding.Name, mBinding.Values[mChoice]);
      end;
    end
    else if mBinding.Control is TEdit then
    begin
      WriteText(mStore, mBinding.Name, Trim(TEdit(mBinding.Control).Text));
    end;
  end;
  mValues := SectionValues(mStore);
  for mSection in FSections do
  begin
    mSection.Save(mValues);
  end;
  ASettings.Load(mStore);
end;

procedure TAtlasSettingsPage.WriteText(const AStore: IAtlasMemorySettingsStore; const AName, AText: string);
var
  mValue: Integer;
begin
  // Zahlen stehen als Zahl im Speicher (wie TAtlasPluginSettings.Save), alles andere als Text.
  if AStore.HasInteger(AName) then
  begin
    if TryStrToInt(AText, mValue) then
    begin
      AStore.WriteInteger(AName, mValue);
    end;
  end
  else
  begin
    AStore.WriteString(AName, AText);
  end;
end;

procedure TAtlasSettingsPage.DropMissingSections;
var
  mCurrent: TArray<IInterface>;
  mKeep: TArray<IAtlasSettingsSection>;
  mKeepProviders: TArray<IAtlasSettingsSectionProvider>;
  mKeepHosts: TArray<IAtlasSettingsSectionHost>;
  mIndex: Integer;
  mItem: IInterface;
  mFound: Boolean;
begin
  // Ein abgemeldetes Modul erreicht danach nichts mehr (Regel 3): Abschnitt schließen und vergessen. Seine
  // Werte bleiben, gebundene Felder gehören der Seite. Neue Abschnitte zeigt erst die nächste Seite.
  mCurrent := AtlasModuleRegistry.FindAll(IAtlasSettingsSectionProvider);
  mKeep := nil;
  mKeepProviders := nil;
  mKeepHosts := nil;
  for mIndex := 0 to High(FSections) do
  begin
    mFound := False;
    for mItem in mCurrent do
    begin
      if SameInstance(mItem, FSectionProviders[mIndex]) then
      begin
        mFound := True;
      end;
    end;
    if mFound then
    begin
      mKeep := mKeep + [FSections[mIndex]];
      mKeepProviders := mKeepProviders + [FSectionProviders[mIndex]];
      mKeepHosts := mKeepHosts + [FSectionHosts[mIndex]];
    end
    else
    begin
      (FSectionHosts[mIndex] as IAtlasSettingsDetachable).Detach;
      FSections[mIndex].Close;
    end;
  end;
  FSections := mKeep;
  FSectionProviders := mKeepProviders;
  FSectionHosts := mKeepHosts;
end;

procedure TAtlasSettingsPage.CloseSections;
var
  mIndex: Integer;
begin
  if FSectionWatch <> nil then
  begin
    (FSectionWatch as IAtlasSettingsDetachable).Detach;
  end;
  if FSectionWatchRegistration <> nil then
  begin
    FSectionWatchRegistration.Revoke;
  end;
  FSectionWatchRegistration := nil;
  FSectionWatch := nil;
  for mIndex := 0 to High(FSections) do
  begin
    (FSectionHosts[mIndex] as IAtlasSettingsDetachable).Detach;
    FSections[mIndex].Close;
  end;
  FSections := nil;
  FSectionProviders := nil;
  FSectionHosts := nil;
  FSectionBindings := nil;
end;

procedure TAtlasSettingsPage.SectionsWindowReady;
var
  mSection: IAtlasSettingsSection;
begin
  for mSection in FSections do
  begin
    mSection.WindowReady;
  end;
end;

function TAtlasSettingsPage.ShowSettingArgument(const AName, AArgument: string): Boolean;
var
  mIndex: Integer;
  mKey: string;
  mSection: IAtlasSettingsSection;
begin
  Result := False;
  mIndex := Catalog.IndexOfName(AName);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mKey := Catalog[mIndex].Key;
  for mSection in FSections do
  begin
    if mSection.Show(mKey, AArgument) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasSettingsPage.ControlOfSetting(const AName: string): TControl;
begin
  Result := FMarks.ControlOfName(AName);
end;

function TAtlasSettingsPage.SectionCount: Integer;
begin
  Result := Length(FSections);
end;

function TAtlasSettingsPage.SheetCountForTests: Integer;
begin
  Result := Length(FSheets);
end;

end.
