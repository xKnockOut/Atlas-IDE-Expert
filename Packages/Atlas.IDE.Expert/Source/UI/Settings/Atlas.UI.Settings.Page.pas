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
// nicht; die IDE-Schicht liefert Texte und führt die Befehle über OnIndexMetrics, OnIndexRebuild,
// OnIndexClear aus. Im Seitenkopf steht das Atlas-Symbol (#751) passend zu Thema und Skalierung.
// Jeder Reiter bleibt niedriger als die Seite: Sonst scrollt die IDE ihren Bereich beim Reiterwechsel
// zum Fokus, und die Seite „springt“.
// Reiter Vervollständigung: angeheftete Favoriten (#458) an/aus, Liste („TDataSet.Open“) mit „Entfernen“
// und „Alle entfernen“. Die Seite kennt die Ablage nicht; OnFavorites liefert die Liste, OnRemoveFavorites
// löst die Schlüssel sofort (nicht erst mit OK).

interface

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
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
  Atlas.Core.Projects.Summary,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.SafeMode,
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

  TAtlasSettingsPage = class(TFrame)
  private
    FPages: TPageControl;
    FSheet: TTabSheet;
    // Reiter hängen erst mit dem Fensterhandle am PageControl (CreateWnd): Die IDE und die Tests
    // erzeugen die Seite, bevor sie ein übergeordnetes Fenster hat.
    FSheets: TArray<TTabSheet>;
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
    FPreview: TCheckBox;
    FHoverTooltip: TCheckBox;
    FXmlDocFull: TCheckBox;
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
    FNotes: TCheckBox;
    FBookmarksNamed: TCheckBox;
    FBookmarksShared: TCheckBox;
    FCodeLensTestUnit: TCheckBox;
    /// <summary>Code Lens mit Code-Metriken (#66).</summary>
    FCodeLensMetrics: TCheckBox;
    /// <summary>Befehl in der Befehlspalette (#68).</summary>
    FTodoList: TCheckBox;
    /// <summary>Befehl in der Befehlspalette (#97).</summary>
    FBaselineUpdate: TCheckBox;
    /// <summary>Befehl in der Befehlspalette (#66).</summary>
    FMetricsReport: TCheckBox;
    FPairGuides: TCheckBox;
    FPairOwners: TCheckBox;
    FPairGuideWidth: TEdit;
    FPairGuideOpacity: TEdit;
    // Eigene Paarfarben je Thema, eine Fläche je Tiefe.
    FLightSwatches: array[0..4] of TShape;
    FDarkSwatches: array[0..4] of TShape;
    FProblems: TCheckBox;
    FProblemsList: TCheckBox;
    FStatusField: TCheckBox;
    FDiagnosticMode: TCheckBox;
    FSetupChecklist: TCheckBox;
    FShortcutTips: TCheckBox;
    FShortcutTipsScope: TAtlasChoiceBox;
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
    FOnIndexMetrics: TFunc<string>;
    FOnIndexRebuild: TFunc<string>;
    FOnIndexClear: TFunc<string>;
    FConfirmClear: TFunc<Boolean>;
    FAfterSave: TAtlasChoiceBox;
    FCheckDelay: TEdit;
    FCheckMax: TEdit;
    FActionsKey: TEdit;
    FExpandKey: TEdit;
    FShrinkKey: TEdit;
    FImplementationKey: TEdit;
    FTypeDefinitionKey: TEdit;
    FMethodToggle: TCheckBox;
    FMethodToggleUpKey: TEdit;
    FMethodToggleDownKey: TEdit;
    FTestUnitKey: TEdit;
    FBookmarkKey: TEdit;
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
    FUnitSearchMultiSelect: TCheckBox;
    FUnitSearchActions: TCheckBox;
    FUnitSearchAddUses: TCheckBox;
    FUnitSearchKey: TEdit;
    FWelcomeEnabled: TCheckBox;
    FWelcomeHost: TAtlasChoiceBox;
    FWelcomeLayout: TCheckBox;
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
    /// <summary>Beschriftung in einer Zeile, darunter ein Textfeld über die ganze Breite (#766).</summary>
    function AddTextLine(const ACaption: string): TEdit;
    procedure ResetWidthsClick(Sender: TObject);
    procedure HangTestClick(Sender: TObject);
    procedure DiagnosticModeClick(Sender: TObject);
    procedure PairColorsClick(Sender: TObject);
    procedure FuseEnableSelectedClick(Sender: TObject);
    procedure FuseEnableAllClick(Sender: TObject);
    procedure AddFuseSection;
    procedure AddIndexSection;
    procedure AddSafeSection;
    procedure AddUndoSection;
    procedure AddUnitSearchSection;
    procedure AddWelcomeSection;
    procedure AddUpdatesSection;
    procedure AddBugReportSection;
    procedure IndexRefreshClick(Sender: TObject);
    procedure IndexRebuildClick(Sender: TObject);
    procedure IndexClearClick(Sender: TObject);
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
  public
    constructor Create(AOwner: TComponent); override;
    procedure LoadFrom(const ASettings: TAtlasPluginSettings);
    procedure SaveTo(var ASettings: TAtlasPluginSettings);
    /// <summary>Liste der abgeschalteten Features und Quellen neu lesen (#493).</summary>
    procedure RefreshFuse;
    /// <summary>Kennzahlen des Index neu holen und anzeigen (#492).</summary>
    procedure RefreshIndex;
    /// <summary>Liste der angehefteten Favoriten neu lesen (#458).</summary>
    procedure RefreshFavorites;
    /// <summary>Reiter der Seite, einer je Bereich (#227).</summary>
    property Pages: TPageControl read FPages;
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
    /// <summary>Zeile mit „Wächter testen“; nur im Diagnosemodus sichtbar (Code-Review S-07).</summary>
    property HangTestRow: TWinControl read FHangTestRow;
    property SetupChecklist: TCheckBox read FSetupChecklist;
    property ShortcutTips: TCheckBox read FShortcutTips;
    property ShortcutTipsScope: TAtlasChoiceBox read FShortcutTipsScope;
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
    property RedoKey: TEdit read FRedoKey;
    property UpdatesCheck: TCheckBox read FUpdatesCheck;
    property BugReportAnonymize: TCheckBox read FBugReportAnonymize;
    /// <summary>Zum Testen: Willkommensseite (#753).</summary>
    property WelcomeEnabled: TCheckBox read FWelcomeEnabled;
    property WelcomeHost: TAtlasChoiceBox read FWelcomeHost;
    property WelcomeLayout: TCheckBox read FWelcomeLayout;
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
    /// <summary>Kennzahlen als Text; nil = nicht verfügbar.</summary>
    property OnIndexMetrics: TFunc<string> read FOnIndexMetrics write FOnIndexMetrics;
    /// <summary>„Index neu aufbauen“ bzw. „Index löschen“ ausführen; Ergebnis als Meldung.</summary>
    property OnIndexRebuild: TFunc<string> read FOnIndexRebuild write FOnIndexRebuild;
    property OnIndexClear: TFunc<string> read FOnIndexClear write FOnIndexClear;
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
    /// <summary>Zum Testen: benannte Lesezeichen (#622).</summary>
    property BookmarksNamedCheck: TCheckBox read FBookmarksNamed;
    property BookmarksSharedCheck: TCheckBox read FBookmarksShared;
    property BookmarkKey: TEdit read FBookmarkKey;
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
  Atlas.Core.Product.Version,
  Atlas.Core.Updates.Check,
  Atlas.Core.Undo.Contract,
  Atlas.Core.Undo.Names,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.Core.Welcome.Trends,
  Atlas.Core.Commands.ShortcutTips;

/// <summary>Bezeichnung einer Reihe des Projektverlaufs (#758) wie auf ihrer Kachel.</summary>
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
  Series: TAtlasTrendSeries;
begin
  inherited Create(AOwner);
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
  // Reiter je Bereich (#227); jeder stapelt seine Elemente neu von oben. Viele Reiter: in Zeilen.
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.AlignWithMargins := True;
  FPages.MultiLine := True;
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
  // Prüfliste der Einrichtung beim Start (#625); aus: nur auf Abruf.
  FSetupChecklist := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSetupChecklist));
  // Tastenkürzel-Tipps (#600); Reihenfolge wie TAtlasTipScope: atlas, all.
  FShortcutTips := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsShortcutTips));
  FShortcutTipsScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsShortcutTipsScope),
    [TAtlasStrings.Text(TAtlasTextId.SettingsShortcutTipsAtlas), TAtlasStrings.Text(TAtlasTextId.SettingsShortcutTipsAll)]);

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
  FFilterChips := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsChips));
  FLearning := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsLearning));
  FFavorites := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsFavorites));
  FGroupInherited := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGroupInherited));
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
  // XMLDoc in Tooltip und Detailpanel (#654); gespeichert in settings.json (hints.*, #227).
  FXmlDocFull := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocFull));
  FXmlDocMaxLines := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocMaxLines));
  FPairColors := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairs));
  FPairGuides := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuides));
  // Anweisungen mitfärben, Linienbreite und Deckkraft (#653); wirken nur mit der Paarfärbung.
  FPairOwners := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairOwners));
  FPairGuideWidth := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuideWidth));
  FPairGuideOpacity := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuideOpacity));
  FPairColors.OnClick := PairColorsClick;
  FInactiveDim := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInactiveDim));
  FInlayHints := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayHints));
  // Persönliche Notizen an Codezeilen (#545).
  FNotes := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsNotes));
  // Benannte Lesezeichen (#622): Funktion und Ablage für das Team; die Taste steht bei den Editorbefehlen.
  FBookmarksNamed := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBookmarksNamed));
  FBookmarksShared := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBookmarksShared));
  FCodeLensTestUnit := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCodeLensTestUnit));
  FCodeLensMetrics := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCodeLensMetrics));
  FTodoList := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTodoList));
  FBaselineUpdate := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBaselineUpdate));
  FMetricsReport := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMetricsReport));

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
  // Reihenfolge: nichts, Syntaxprüfung (CheckOnSave), Kompilieren (CompileOnSave).
  FAfterSave := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsCheckOnSave),
    [TAtlasStrings.Text(TAtlasTextId.SettingsAfterSaveNone), TAtlasStrings.Text(TAtlasTextId.SettingsAfterSaveCheck),
    TAtlasStrings.Text(TAtlasTextId.SettingsAfterSaveCompile)]);
  FCheckDelay := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsCheckDelay));
  FCheckMax := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsCheckMax));

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
  FTestUnitKey := AddKey(TAtlasStrings.Text(TAtlasTextId.EditorTestUnit));
  // „Lesezeichen setzen…“ (#622).
  FBookmarkKey := AddKey(TAtlasStrings.Text(TAtlasTextId.BookmarksMenuAdd));
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
end;

procedure TAtlasSettingsPage.AddWelcomeSection;
var
  Panel: TWinControl;
begin
  // Atlas-Bereiche auf der Willkommensseite (#753).
  FWelcomeEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeEnabled));
  // Reihenfolge wie welcomePage.host: welcomePage, dockWindow.
  FWelcomeHost := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHost),
    [TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHostPage),
    TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeHostWindow)]);
  FWelcomeLayout := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsWelcomeLayout));
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

procedure TAtlasSettingsPage.AddSheet(AId: TAtlasTextId);
begin
  FSheet := TTabSheet.Create(Self);
  FSheet.Caption := TAtlasStrings.Text(AId);
  FSheets := FSheets + [FSheet];
  FNextTop := 100;
end;

procedure TAtlasSettingsPage.CreateWnd;
var
  Sheet: TTabSheet;
begin
  inherited CreateWnd;
  for Sheet in FSheets do
    if Sheet.PageControl = nil then
      Sheet.PageControl := FPages;
  if FPages.PageCount > 0 then
    FPages.ActivePageIndex := 0;
  // Die Liste der Sicherung braucht ein Fenster; vorher bleibt sie leer.
  RefreshFuse;
  RefreshFavorites;
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
  FFavoritesList.Enabled := Any;
  FFavoritesRemove.Enabled := Any and Assigned(FOnRemoveFavorites);
  FFavoritesRemoveAll.Enabled := Any and Assigned(FOnRemoveFavorites);
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

procedure TAtlasSettingsPage.RefreshIndex;
begin
  if Assigned(FOnIndexMetrics) then
    FIndexInfo.Caption := FOnIndexMetrics()
  else
    FIndexInfo.Caption := '';
  FIndexRebuild.Enabled := Assigned(FOnIndexRebuild);
  FIndexClear.Enabled := Assigned(FOnIndexClear);
end;

procedure TAtlasSettingsPage.IndexRefreshClick(Sender: TObject);
begin
  RefreshIndex;
end;

procedure TAtlasSettingsPage.IndexRebuildClick(Sender: TObject);
begin
  if Assigned(FOnIndexRebuild) then
    FIndexInfo.Caption := FOnIndexRebuild();
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
    FIndexInfo.Caption := FOnIndexClear();
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
  FFuseList.Enabled := Any;
  FFuseEnableSelected.Enabled := Any;
  FFuseEnableAll.Enabled := Any;
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
  FUnitSearchMultiSelect := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchMultiSelect));
  FUnitSearchActions := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchActions));
  FUnitSearchAddUses := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnitSearchAddUses));
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
  Result.Parent := FSheet;
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
  Result.Parent := FSheet;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Height := AHeight;
  Result.Top := FNextTop;
  Inc(FNextTop, 100);
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

procedure TAtlasSettingsPage.PairColorsClick(Sender: TObject);
begin
  FPairOwners.Enabled := FPairColors.Checked;
  FPairGuides.Enabled := FPairColors.Checked;
  FPairGuideWidth.Enabled := FPairColors.Checked;
  FPairGuideOpacity.Enabled := FPairColors.Checked;
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

procedure TAtlasSettingsPage.LoadFrom(const ASettings: TAtlasPluginSettings);
var
  Shown: TAtlasTrendSeriesList;
  Series, Wanted: TAtlasTrendSeries;
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
  FBookmarkKey.Text := ShortCutToText(TShortCut(ASettings.BookmarkKey));
  FEditorKeysPriority.Checked := ASettings.EditorKeysPriority;
  FSlashCommands.Checked := ASettings.SlashCommands;
  FGenerateMenu.Checked := ASettings.GenerateMenu;
  FGenerateMenuKey.Text := ShortCutToText(TShortCut(ASettings.GenerateMenuKey));
  FGenerateMenuGroups.Text := ASettings.GenerateMenuGroups;
  FGenerateMenuHidden.Text := ASettings.GenerateMenuHidden;
  FGenerateMenuRecentFirst.Checked := ASettings.GenerateMenuRecentFirst;
  FGenerateMenuShowCommandNames.Checked := ASettings.GenerateMenuShowCommandNames;
  ServerPathChange(nil);
  FRowsUpDown.Position := ASettings.VisibleRows;
  FPanelCollapsed.Checked := ASettings.PanelCollapsed;
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
  FPreview.Checked := ASettings.Preview;
  FSnippets.Checked := ASettings.Snippets;
  FImportIdeTemplates.Checked := ASettings.ImportIdeTemplates;
  FTeamFile.Checked := ASettings.TeamFile;
  RefreshTeamFile;
  FHoverTooltip.Checked := ASettings.HoverTooltip;
  FXmlDocFull.Checked := ASettings.XmlDocFull;
  FXmlDocMaxLines.Text := IntToStr(ASettings.XmlDocMaxLines);
  FHangThreshold.Text := IntToStr(ASettings.HangThresholdMs);
  FProviderTimeLimit.Text := IntToStr(ASettings.ProviderTimeLimitMs);
  FHangHint.Checked := ASettings.HangHint;
  FReloadExternal.Checked := ASettings.ReloadExternal;
  FOpenForEdits.Checked := ASettings.OpenForEdits;
  FPairColors.Checked := ASettings.PairColors;
  FInactiveDim.Checked := ASettings.InactiveDim;
  FInlayHints.Checked := ASettings.InlayHints;
  FNotes.Checked := ASettings.Notes;
  FBookmarksNamed.Checked := ASettings.BookmarksNamed;
  FBookmarksShared.Checked := ASettings.BookmarksShared;
  FCodeLensTestUnit.Checked := ASettings.CodeLensTestUnit;
  FCodeLensMetrics.Checked := ASettings.CodeLensMetrics;
  FTodoList.Checked := ASettings.TodoList;
  FBaselineUpdate.Checked := ASettings.BaselineUpdate;
  FMetricsReport.Checked := ASettings.MetricsReport;
  FPairGuides.Checked := ASettings.PairGuides;
  FPairOwners.Checked := ASettings.PairOwners;
  FPairGuideWidth.Text := IntToStr(ASettings.PairGuideWidth);
  FPairGuideOpacity.Text := IntToStr(ASettings.PairGuideOpacity);
  PairColorsClick(nil);
  ShowPairs(FLightSwatches, TAtlasColors.Light.WithPairs(ASettings.PairColorsLight).Pairs);
  ShowPairs(FDarkSwatches, TAtlasColors.Dark.WithPairs(ASettings.PairColorsDark).Pairs);
  FProblems.Checked := ASettings.Problems;
  FProblemsList.Checked := ASettings.ProblemsList;
  FStatusField.Checked := ASettings.StatusField;
  FDiagnosticMode.Checked := ASettings.DiagnosticMode;
  // Checked löst OnClick nur bei einer Änderung aus.
  FHangTestRow.Visible := ASettings.DiagnosticMode;
  FSetupChecklist.Checked := ASettings.SetupChecklist;
  FShortcutTips.Checked := ASettings.ShortcutTips;
  FShortcutTipsScope.Choice := Ord(TAtlasShortcutTips.ScopeOf(ASettings.ShortcutTipsScope));
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
  FUnitSearchMultiSelect.Checked := ASettings.UnitSearchMultiSelect;
  FUnitSearchActions.Checked := ASettings.UnitSearchActions;
  FUnitSearchAddUses.Checked := ASettings.UnitSearchActionsAddUses;
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
  RefreshFuse;
  RefreshIndex;
end;

procedure TAtlasSettingsPage.SaveTo(var ASettings: TAtlasPluginSettings);
var
  Shown: TAtlasTrendSeriesList;
  Series: TAtlasTrendSeries;
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
  ASettings.BookmarkKey := Integer(TextToShortCut(Trim(FBookmarkKey.Text)));
  ASettings.UndoKey := Integer(TextToShortCut(Trim(FUndoKey.Text)));
  ASettings.RedoKey := Integer(TextToShortCut(Trim(FRedoKey.Text)));
  ASettings.UpdatesCheck := FUpdatesCheck.Checked;
  ASettings.BugReportAnonymize := FBugReportAnonymize.Checked;
  ASettings.EditorKeysPriority := FEditorKeysPriority.Checked;
  ASettings.SlashCommands := FSlashCommands.Checked;
  ASettings.GenerateMenu := FGenerateMenu.Checked;
  ASettings.GenerateMenuKey := Integer(TextToShortCut(Trim(FGenerateMenuKey.Text)));
  ASettings.GenerateMenuGroups := Trim(FGenerateMenuGroups.Text);
  ASettings.GenerateMenuHidden := Trim(FGenerateMenuHidden.Text);
  ASettings.GenerateMenuRecentFirst := FGenerateMenuRecentFirst.Checked;
  ASettings.GenerateMenuShowCommandNames := FGenerateMenuShowCommandNames.Checked;
  ASettings.VisibleRows := FRowsUpDown.Position;
  ASettings.PanelCollapsed := FPanelCollapsed.Checked;
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
  ASettings.Preview := FPreview.Checked;
  ASettings.Snippets := FSnippets.Checked;
  ASettings.ImportIdeTemplates := FImportIdeTemplates.Checked;
  ASettings.TeamFile := FTeamFile.Checked;
  ASettings.HoverTooltip := FHoverTooltip.Checked;
  ASettings.XmlDocFull := FXmlDocFull.Checked;
  ASettings.XmlDocMaxLines := StrToIntDef(FXmlDocMaxLines.Text, ASettings.XmlDocMaxLines);
  ASettings.HangThresholdMs := StrToIntDef(FHangThreshold.Text, ASettings.HangThresholdMs);
  ASettings.ProviderTimeLimitMs := StrToIntDef(FProviderTimeLimit.Text, ASettings.ProviderTimeLimitMs);
  ASettings.HangHint := FHangHint.Checked;
  ASettings.ReloadExternal := FReloadExternal.Checked;
  ASettings.OpenForEdits := FOpenForEdits.Checked;
  ASettings.PairColors := FPairColors.Checked;
  ASettings.InactiveDim := FInactiveDim.Checked;
  ASettings.InlayHints := FInlayHints.Checked;
  ASettings.Notes := FNotes.Checked;
  ASettings.BookmarksNamed := FBookmarksNamed.Checked;
  ASettings.BookmarksShared := FBookmarksShared.Checked;
  ASettings.CodeLensTestUnit := FCodeLensTestUnit.Checked;
  ASettings.CodeLensMetrics := FCodeLensMetrics.Checked;
  ASettings.TodoList := FTodoList.Checked;
  ASettings.BaselineUpdate := FBaselineUpdate.Checked;
  ASettings.MetricsReport := FMetricsReport.Checked;
  ASettings.PairGuides := FPairGuides.Checked;
  ASettings.PairOwners := FPairOwners.Checked;
  ASettings.PairGuideWidth := StrToIntDef(FPairGuideWidth.Text, ASettings.PairGuideWidth);
  ASettings.PairGuideOpacity := StrToIntDef(FPairGuideOpacity.Text, ASettings.PairGuideOpacity);
  ASettings.PairColorsLight := PairsSetting(FLightSwatches, TAtlasColors.Light.Pairs);
  ASettings.PairColorsDark := PairsSetting(FDarkSwatches, TAtlasColors.Dark.Pairs);
  ASettings.Problems := FProblems.Checked;
  ASettings.ProblemsList := FProblemsList.Checked;
  ASettings.StatusField := FStatusField.Checked;
  ASettings.DiagnosticMode := FDiagnosticMode.Checked;
  ASettings.SetupChecklist := FSetupChecklist.Checked;
  ASettings.ShortcutTips := FShortcutTips.Checked;
  ASettings.ShortcutTipsScope := TAtlasShortcutTips.ScopeName(TAtlasTipScope(EnsureRange(FShortcutTipsScope.Choice,
    Ord(Low(TAtlasTipScope)), Ord(High(TAtlasTipScope)))));
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
  ASettings.UnitSearchMultiSelect := FUnitSearchMultiSelect.Checked;
  ASettings.UnitSearchActions := FUnitSearchActions.Checked;
  ASettings.UnitSearchActionsAddUses := FUnitSearchAddUses.Checked;
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
  FResetHistory.Enabled := False;
end;

procedure TAtlasSettingsPage.ResetUsageClick(Sender: TObject);
begin
  if Assigned(FOnResetUsage) then
    FOnResetUsage();
  FResetUsage.Enabled := False;
end;

procedure TAtlasSettingsPage.UnblockTipsClick(Sender: TObject);
begin
  if Assigned(FOnUnblockTips) then
    FOnUnblockTips();
  FUnblockTips.Enabled := False;
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
  AddWrappedLabel(36, TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileHint));
  Panel := AddPanel(32);
  FTeamFileOpen := TButton.Create(Self);
  FTeamFileOpen.Parent := Panel;
  FTeamFileOpen.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileOpen);
  FTeamFileOpen.Left := 0;
  FTeamFileOpen.Top := 3;
  FTeamFileOpen.Width := 180;
  FTeamFileOpen.OnClick := TeamFileOpenClick;
  FTeamFileInfo := AddWrappedLabel(180, '');
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
  FTeamFileOpen.Enabled := FTeamFile.Checked and (Team.Project <> '');
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
  FResetWidths.Enabled := False;
end;

end.
