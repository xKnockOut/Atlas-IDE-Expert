unit Atlas.Core.Settings.Plugin;

// Einstellungen des IDE-Plugins (#227, Teil Vervollständigung), ohne VCL und
// ohne Registry: Vorgaben, Grenzen, Lesen und Schreiben über einen Speicher.
// Die IDE-Schicht speichert in HKCU\Software\Atlas\IdePlugin, Tests im
// Arbeitsspeicher. Breiten in logischen Pixeln (96 dpi, #412).
// Die Server-Einstellungen unter den Feldern (Index, Speicher, XMLDoc,
// Inlay-Hints, Schnellbefehle, Kompilieren nach dem Speichern) liegen in
// %APPDATA%\Atlas\settings.json; TAtlasRoutedSettingsStore leitet sie dorthin
// (Atlas.Core.Settings.Scopes).

interface

uses
  System.SysUtils,
  Atlas.Core.Style.Palette;

type
  /// <summary>Ablage für Einstellungen; Werte als ganze Zahlen (Wahrheitswerte 0/1).</summary>
  IAtlasSettingsStore = interface
    ['{4C8E2A17-9B3D-4F61-A5E2-7D0C1B9F3E84}']
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

  TAtlasPluginSettings = record
  public const
    MinVisibleRows = 5;
    MaxVisibleRows = 20;
    MinListWidth = 240;
    MaxListWidth = 720;
    MinPanelWidth = 220;
    MaxPanelWidth = 600;
    MinHangThreshold = 100;
    MaxHangThreshold = 10000;
    /// <summary>Wie TAtlasTimeLimit.MinMs/MaxMs (#493).</summary>
    MinProviderTimeLimit = 50;
    MaxProviderTimeLimit = 5000;
    MinCheckDelay = 500;
    MaxCheckDelay = 10000;
    MinCheckMax = 200;
    MaxCheckMax = 20000;
    MaxXmlDocLines = 50;
    /// <summary>Verzögerung bis zum automatischen Öffnen der Liste (ARG-046, #227); 0 = sofort.</summary>
    MaxOpenDelay = 2000;
    /// <summary>Speichergrenze des Symbolindex im Server (#492); 0 = unbegrenzt.</summary>
    MaxMemoryBudgetMb = 65536;
    /// <summary>Grenzen für safeMode.startupTimeoutMs und safeMode.keepSettingsHistory (#722).</summary>
    MinSafeStartupTimeout = 1000;
    MaxSafeStartupTimeout = 120000;
    MaxSafeSettingsHistory = 50;
    /// <summary>Grenzen für undo.multiFile.depth und undo.multiFile.maxSizeMb (#721).</summary>
    MinUndoDepth = 1;
    MaxUndoDepth = 200;
    MinUndoMaxSizeMb = 1;
    MaxUndoMaxSizeMb = 1024;
    /// <summary>Grenzen für welcomePage.maxProjects (#592); wie TAtlasWelcomeProjects.MinMax/MaxMax.</summary>
    MinWelcomeProjects = 1;
    MaxWelcomeProjects = 30;
    /// <summary>Grenzen der Stunden für welcomePage.unsaved.* (#762); wie TAtlasWelcomeUnsaved.MaxHours.</summary>
    MinUnsavedHours = 0;
    MaxUnsavedHours = 8760;
    MinPairGuideWidth = 1;
    MaxPairGuideWidth = 3;
    MinPairGuideOpacity = 10;
    MaxPairGuideOpacity = 100;
    /// <summary>Vorgabe für welcomePage.help.reportUrl (#766): Seite für neue Issues des Atlas-Repositorys.
    /// </summary>
    DefaultHelpReportUrl = 'https://github.com/xKnockOut/Atlas-IDE-Expert/issues/new';
  public
    /// <summary>Hauptschalter (#407): aus = eingebaute Code Insight der IDE.</summary>
    Enabled: Boolean;
    /// <summary>Sichtbare Zeilen der Liste (#413).</summary>
    VisibleRows: Integer;
    /// <summary>Von Hand gezogene Breite der Liste, 0 = automatisch (#416).</summary>
    ListWidth: Integer;
    /// <summary>Breite des Detailpanels (#416).</summary>
    PanelWidth: Integer;
    /// <summary>Detailpanel eingeklappt (#428).</summary>
    PanelCollapsed: Boolean;
    /// <summary>Klammern beim Übernehmen von Methoden (#430).</summary>
    AutoParentheses: Boolean;
    /// <summary>Schreibweise des getippten Worts beim Übernehmen korrigieren (#433).</summary>
    FixCase: Boolean;
    /// <summary>Übernehmen über "(", ";" und "." (#429).</summary>
    CommitCharacters: Boolean;
    /// <summary>Unit beim Übernehmen automatisch in uses eintragen (#180).</summary>
    AutoUses: Boolean;
    /// <summary>Parameter-Hint bei "(" und "," (#436).</summary>
    ParameterHints: Boolean;
    /// <summary>Millisekunden zwischen automatischem Auslösen (".") und dem Öffnen der Liste (ARG-046).</summary>
    OpenDelayMs: Integer;
    /// <summary>Tastenkürzel der Befehlspalette und der Syntaxprüfung (TShortCut, 0 = keins, #494).</summary>
    PaletteKey: Integer;
    CheckKey: Integer;
    /// <summary>Kürzel auch belegen, wenn die IDE oder eine andere Erweiterung es schon nutzt.</summary>
    PaletteKeyPriority: Boolean;
    CheckKeyPriority: Boolean;
    /// <summary>Eigene Tasten für Vervollständigung und Parameter-Hint (#494), 0 = die Taste der IDE
    /// (Strg+Leer bzw. Strg+Umschalt+Leer über Code Insight); sonst belegt Atlas sie zusätzlich.</summary>
    CompletionKey: Integer;
    SignatureKey: Integer;
    CompletionKeyPriority: Boolean;
    SignatureKeyPriority: Boolean;
    /// <summary>Filter-Chips über der Liste (#422).</summary>
    FilterChips: Boolean;
    /// <summary>Lernende Gewichtung (#418).</summary>
    Learning: Boolean;
    /// <summary>Favoriten anheften (#458): Strg+D bzw. Stern in der Liste, angeheftete Einträge stehen oben;
    /// gespeichert in %APPDATA%\Atlas\favorites.json.</summary>
    Favorites: Boolean;
    /// <summary>Geerbte Member nachrangig und gruppiert (#419).</summary>
    GroupInherited: Boolean;
    /// <summary>Vorschau des gewählten Eintrags im Editor (#434).</summary>
    Preview: Boolean;
    /// <summary>Eigener Hover-Tooltip (#442).</summary>
    HoverTooltip: Boolean;
    /// <summary>Ab so vielen Millisekunden ohne Antwort gilt die IDE als hängend (#501).</summary>
    HangThresholdMs: Integer;
    /// <summary>Zeitlimit für Aufrufe von Datenquellen aus dem Hauptthread (#493); länger gilt als Fehler.</summary>
    ProviderTimeLimitMs: Integer;
    /// <summary>Hinweis im Meldungsfenster nach langen Hängern (ab 2 s, #501).</summary>
    HangHint: Boolean;
    /// <summary>Extern geänderte Dateien ohne eigene Änderungen still neu laden (#536).</summary>
    ReloadExternal: Boolean;
    /// <summary>Klammer- und Blockpaare nach Tiefe färben (#514).</summary>
    PairColors: Boolean;
    /// <summary>Inaktive {$IFDEF}-Zweige im Editor ausgrauen (#615).</summary>
    InactiveDim: Boolean;
    /// <summary>Änderungen des Servers an nicht geöffneten Dateien: im Editor öffnen (an) oder
    /// direkt auf die Platte schreiben (aus, #397).</summary>
    OpenForEdits: Boolean;
    /// <summary>Parameternamen vor Literal-Argumenten als Inlay-Hints (#401); standardmäßig aus.</summary>
    InlayHints: Boolean;
    /// <summary>Persönliche Notizen an Codezeilen (#545): Symbol in der Rinne, Befehle und Liste; gespeichert in
    /// %LOCALAPPDATA%\Atlas\Notes\, nie im Quelltext.</summary>
    Notes: Boolean;
    /// <summary>Pfad zu AtlasServer.exe; leer: neben dem Plugin bzw. Output\Win64\Debug\Bin.</summary>
    ServerPath: string;
    /// <summary>Blocklinien in den Paarfarben statt der Strukturhervorhebung der IDE (#514).</summary>
    PairGuides: Boolean;
    /// <summary>Schlüsselwörter der Anweisung (if, then, else, for, do, procedure …) in der Farbe ihres
    /// Blocks; Blocklinien beginnen an der Anweisung (#653). Wirkt nur mit PairColors.</summary>
    PairOwners: Boolean;
    /// <summary>Breite der Blocklinien in Pixeln bei 100 % (1–3, #653).</summary>
    PairGuideWidth: Integer;
    /// <summary>Deckkraft der Blocklinien in Prozent; der Rest ist Hintergrund.</summary>
    PairGuideOpacity: Integer;
    /// <summary>Eigene Paarfarben je Thema („#RRGGBB,…“, fünf Stück); leer = Standardpalette.</summary>
    PairColorsLight: string;
    PairColorsDark: string;
    /// <summary>Probleme im Editor unterstreichen und im Meldungsfenster auflisten (#398).</summary>
    Problems: Boolean;
    /// <summary>Probleme zusätzlich im Meldungsfenster auflisten (Gruppe „Atlas-Probleme“); nur mit Problems.</summary>
    ProblemsList: Boolean;
    /// <summary>Syntaxprüfung des Compilers nach dem Speichern (#548). Schließt CompileOnSave aus: Die
    /// Optionsseite bietet eine Auswahl „Nach dem Speichern“ (aus, Syntaxprüfung, Kompilieren).</summary>
    CheckOnSave: Boolean;
    /// <summary>Der Server kompiliert nach dem Speichern im Hintergrund (compiler.onSave, #40).</summary>
    CompileOnSave: Boolean;
    /// <summary>Wartezeit nach dem letzten Speichern.</summary>
    CheckOnSaveDelayMs: Integer;
    /// <summary>Höchstdauer einer Prüfung; darüber nur noch von Hand (Strg+Alt+F9).</summary>
    CheckOnSaveMaxMs: Integer;
    /// <summary>Tastenkürzel im Editor (#399, TShortCut, 0 = keins): Code-Aktionen, Auswahl erweitern und
    /// verkleinern, Gehe zu Implementierung und zu Typdefinition.</summary>
    ActionsKey: Integer;
    ExpandKey: Integer;
    ShrinkKey: Integer;
    ImplementationKey: Integer;
    TypeDefinitionKey: Integer;
    /// <summary>Zwischen Deklaration und Implementierung wechseln (#775); aus: Atlas belegt die Tasten nicht,
    /// die Klassennavigation der IDE gilt.</summary>
    MethodToggle: Boolean;
    /// <summary>Tasten für den Wechsel (#775, TShortCut, 0 = keine): Strg+Umschalt+↑ und Strg+Umschalt+↓.</summary>
    MethodToggleUpKey: Integer;
    MethodToggleDownKey: Integer;
    /// <summary>Zwischen Unit und Testunit wechseln (#189, TShortCut, 0 = keins).</summary>
    TestUnitKey: Integer;
    /// <summary>Code Lens „Testunit“ bzw. „Unit“ hinter der Zeile unit … (#189, codeLens.testUnit);
    /// der Befehl bleibt auch ohne sie verfügbar.</summary>
    CodeLensTestUnit: Boolean;
    /// <summary>Die Editor-Kürzel auch belegen, wenn die IDE oder eine andere Erweiterung sie nutzt.</summary>
    EditorKeysPriority: Boolean;
    /// <summary>Schnellbefehle mit „/“ nach Enter und „///“-Gerüste beim Server auslösen (#399).</summary>
    SlashCommands: Boolean;
    /// <summary>Code-Vorlagen in der Vervollständigung (#51, completion.snippets).</summary>
    Snippets: Boolean;
    /// <summary>Live Templates der IDE als Code-Vorlagen einlesen (#51, completion.importIdeTemplates).</summary>
    ImportIdeTemplates: Boolean;
    /// <summary>Umfang des Symbolindex für alle Projekte (#652, index.* in settings.json).</summary>
    IndexProjectGroup: Boolean;
    IndexSearchPaths: Boolean;
    IndexLibraryPaths: Boolean;
    /// <summary>Verwendungen der Bezeichner mit indizieren (#492, index.usages).</summary>
    IndexUsages: Boolean;
    /// <summary>Speichergrenze des Symbolindex in MB (#492, memoryBudgetMb); darüber lagert der Server
    /// zuerst die Verwendungen aus. 0 = unbegrenzt.</summary>
    MemoryBudgetMb: Integer;
    /// <summary>XMLDoc in Tooltip und Detailpanel vollständig (#654, hints.xmlDocFull in settings.json); aus =
    /// Kurzform.</summary>
    XmlDocFull: Boolean;
    /// <summary>Höchstens so viele Zeilen Doku ohne Scrollen, 0 = bis zur Bildschirmhöhe (#654).</summary>
    XmlDocMaxLines: Integer;
    /// <summary>Atlas-Feld in der Statusleiste (#591, statusField.enabled).</summary>
    StatusField: Boolean;
    /// <summary>Kennungen der Zeilen, die im Fenster des Felds nicht erscheinen, durch Komma getrennt
    /// (#591, statusField.hidden).</summary>
    StatusFieldHidden: string;
    /// <summary>Kurztext neben „Atlas“ (#591, statusField.showSummary).</summary>
    StatusFieldSummary: Boolean;
    /// <summary>Womit das Feld die Schnellschalter öffnet: 'both' (Rechts- und Doppelklick, Vorgabe),
    /// 'rightClick' oder 'doubleClick' (statusField.openToggles).</summary>
    StatusFieldToggles: string;
    /// <summary>Wo der Fortschritt beim Aufbau des Symbol-Index steht: 'statusField' (Vorgabe; mit
    /// abgeschaltetem Statusfeld im Menütitel), 'menu' (Titel des Menüs Atlas) oder 'off'
    /// (statusField.indexProgress).</summary>
    IndexProgressPlace: string;
    /// <summary>Tastenkürzel für das Fenster der Schnellschalter (#604, TShortCut, 0 = keins) und Vorrang wie
    /// bei den anderen Atlas-Tasten (#494).</summary>
    QuickToggleKey: Integer;
    QuickToggleKeyPriority: Boolean;
    /// <summary>Diagnosemodus (#479, diagnosticMode.enabled): Diagnosefenster mit Zeitmessung je Abfrage der
    /// Vervollständigung; Vorgabe aus. Aus heißt: keine Messung, kein Fenster, keine Statuszeile.</summary>
    DiagnosticMode: Boolean;
    /// <summary>Tastenkürzel, das den Diagnosemodus umschaltet (#479, TShortCut, 0 = keins); Vorgabe
    /// Strg+Alt+Umschalt+D, weil Strg+Alt+Umschalt+A den Schnellschaltern (#604) gehört. Vorrang wie bei den
    /// anderen Atlas-Tasten (#494).</summary>
    DiagnosticModeKey: Integer;
    DiagnosticModeKeyPriority: Boolean;
    /// <summary>Prüfliste „Atlas-Einrichtung“ beim IDE-Start zeigen, solange nicht alles grün ist (#625,
    /// ui.setupChecklist); aus: nur auf Abruf (Menü Atlas, Befehlspalette, Statusfeld).</summary>
    SetupChecklist: Boolean;
    /// <summary>Die Prüfliste war schon einmal offen (#625); vorher öffnet sie beim Start in jedem Fall. Kein
    /// Schlüssel in atlas.json, nur Zustand des Plugins.</summary>
    SetupChecklistSeen: Boolean;
    /// <summary>Tastenkürzel-Übersicht (#520): Menüeintrag *Atlas › Tastenkürzel-Übersicht…* und Befehl der
    /// Palette; aus: beide ausgeblendet.</summary>
    KeyOverview: Boolean;
    /// <summary>Beim Start die Tasten von Atlas gegen alle Belegungen prüfen und jeden Konflikt einmal in der
    /// Meldungsansicht melden (#520).</summary>
    KeyStartupCheck: Boolean;
    /// <summary>Tastenkürzel-Tipps (#600, shortcutTips.enabled): nach einem Aufruf per Maus kurz das Kürzel
    /// zeigen; aus: Atlas beobachtet keine Aufrufe und zählt nichts.</summary>
    ShortcutTips: Boolean;
    /// <summary>atlas (nur Befehle von Atlas) oder all (auch die der IDE und anderer Erweiterungen,
    /// shortcutTips.scope).</summary>
    ShortcutTipsScope: string;
    /// <summary>Abgesicherter Start (#722): nach einem Absturz fragen (safeMode.askAfterCrash).</summary>
    SafeAskAfterCrash: Boolean;
    /// <summary>Nach zwei Abstürzen kurz hintereinander ohne Rückfrage abgesichert
    /// (safeMode.autoAfterRepeatedCrash).</summary>
    SafeAutoAfterRepeatedCrash: Boolean;
    /// <summary>Taste beim Laden für den abgesicherten Start: shift, ctrl, none (safeMode.startupKey).</summary>
    SafeStartupKey: string;
    /// <summary>Längste Ladezeit; länger gilt beim nächsten Start wie ein Absturz
    /// (safeMode.startupTimeoutMs).</summary>
    SafeStartupTimeoutMs: Integer;
    /// <summary>Gemerkte Einstellungsstände zum Zurücksetzen (safeMode.keepSettingsHistory).</summary>
    SafeKeepSettingsHistory: Integer;
    /// <summary>Dateiübergreifendes Zurücknehmen von Atlas-Änderungen (#721, undo.multiFile).</summary>
    UndoMultiFile: Boolean;
    /// <summary>Anzahl gemerkter Änderungssätze (undo.multiFile.depth).</summary>
    UndoMultiFileDepth: Integer;
    /// <summary>Protokoll über einen IDE-Neustart hinweg sichern (undo.multiFile.persist).</summary>
    UndoMultiFilePersist: Boolean;
    /// <summary>Größte Größe des gesicherten Protokolls in MB (undo.multiFile.maxSizeMb).</summary>
    UndoMultiFileMaxSizeMb: Integer;
    /// <summary>partial oder abort (undo.multiFile.onConflict).</summary>
    UndoMultiFileOnConflict: string;
    /// <summary>recycleBin, delete oder keep (undo.multiFile.newFiles).</summary>
    UndoMultiFileNewFiles: string;
    /// <summary>Tastenkürzel „Letzte Atlas-Änderung zurücknehmen“ und „… wiederherstellen“ (#721, wie die
    /// Editor-Kürzel aus #399 änderbar, TShortCut, 0 = keins).</summary>
    UndoKey: Integer;
    RedoKey: Integer;
    /// <summary>Einmal täglich nach einer neuen Version sehen (#495, updates.check); Vorgabe aus, beim ersten
    /// Start wird gefragt.</summary>
    UpdatesCheck: Boolean;
    /// <summary>Fehlerbericht anonymisieren (#108, diagnostics.bugReport.anonymize): Pfade, Benutzername und
    /// Bezeichner ersetzen; Vorgabe an.</summary>
    BugReportAnonymize: Boolean;
    /// <summary>Hauptschalter für das Fenster „Units suchen“ (#777, unitSearch.enabled); Vorgabe an.</summary>
    UnitSearchEnabled: Boolean;
    /// <summary>Strg+F12 und Ansicht › Units öffnen das Atlas-Fenster statt des IDE-Dialogs (#777, unitSearch.replaceIdeDialog); Vorgabe an.</summary>
    UnitSearchReplaceIdeDialog: Boolean;
    /// <summary>Eingeklappte Gruppen je Projektgruppe merken (#777, unitSearch.rememberCollapsed); Vorgabe an.</summary>
    UnitSearchRememberCollapsed: Boolean;
    /// <summary>Chipzeile mit Herkunft und Art (#777, unitSearch.filters); Vorgabe an.</summary>
    UnitSearchFilters: Boolean;
    /// <summary>Tippsyntax p:/t: im Suchfeld (#777, unitSearch.filterSyntax); Vorgabe an.</summary>
    UnitSearchFilterSyntax: Boolean;
    /// <summary>Vorschaubereich (#777, unitSearch.preview); Vorgabe an.</summary>
    UnitSearchPreview: Boolean;
    /// <summary>Formularskizze in der Vorschau (#777, unitSearch.preview.form); Vorgabe an.</summary>
    UnitSearchPreviewForm: Boolean;
    /// <summary>„Verwendet von“ in der Vorschau (#777, unitSearch.preview.usedBy); Vorgabe an.</summary>
    UnitSearchPreviewUsedBy: Boolean;
    /// <summary>Häkchen und Mehrfachauswahl (#777, unitSearch.multiSelect); Vorgabe an.</summary>
    UnitSearchMultiSelect: Boolean;
    /// <summary>Aktionsleiste (#777, unitSearch.actions); Vorgabe an.</summary>
    UnitSearchActions: Boolean;
    /// <summary>Aktion „In uses aufnehmen“ (#777, unitSearch.actions.addUses); Vorgabe an.</summary>
    UnitSearchActionsAddUses: Boolean;
    /// <summary>Pfadanzeige in der zweiten Zeile (#777, unitSearch.pathStyle): relative, compact, absolute.</summary>
    UnitSearchPathStyle: string;
    /// <summary>Gruppierung (#777, unitSearch.groupBy): none, project, folder.</summary>
    UnitSearchGroupBy: string;
    /// <summary>Vorgewählte Herkunft (#777, unitSearch.defaultScope): project, group, searchPath, library.</summary>
    UnitSearchDefaultScope: string;
    /// <summary>Eigenes Kürzel für das Atlas-Fenster (#777, TShortCut, 0 = keins); Strg+F12 über replaceIdeDialog.</summary>
    UnitSearchKey: Integer;
    /// <summary>Hauptschalter der Atlas-Willkommensseite (#753, welcomePage.enabled): Atlas-Bereiche auf der
    /// Willkommensseite der IDE und Fenster „Atlas-Start“.</summary>
    WelcomePage: Boolean;
    /// <summary>Wo die Bereiche erscheinen: welcomePage oder dockWindow (welcomePage.host); ohne Schnittstelle
    /// der IDE immer dockWindow.</summary>
    WelcomePageHost: string;
    /// <summary>off oder atlas (welcomePage.layout); setzt der Befehl „Atlas-Layout anwenden“.</summary>
    WelcomePageLayout: string;
    /// <summary>Kopf mit Symbol und Version (welcomePage.header) und Grußzeile darin (welcomePage.greeting).</summary>
    WelcomePageHeader: Boolean;
    WelcomePageGreeting: Boolean;
    /// <summary>Suchfeld im Kopf (#760, welcomePage.search) und dessen Gruppe „Symbole“ (welcomePage.search.symbols,
    /// braucht laufenden Server).</summary>
    WelcomePageSearch: Boolean;
    WelcomePageSearchSymbols: Boolean;
    /// <summary>Taste für den Fokus ins Suchfeld, solange die Willkommensseite aktiv ist (TShortCut; 0 = keine).</summary>
    WelcomePageSearchKey: Integer;
    /// <summary>Karte „Neu in Atlas“ (#756, welcomePage.whatsNew): off, afterUpdate (einmalig nach einem
    /// Versionswechsel) oder always.</summary>
    WelcomePageWhatsNew: string;
    /// <summary>Zuletzt gesehene Version der Karte „Neu in Atlas“ (#756); kein Schlüssel in atlas.json, nur
    /// Zustand des Plugins. '' vor dem ersten Start.</summary>
    WhatsNewSeen: string;
    /// <summary>Bereich „Projekte“ mit Zustand je Projekt (#592, welcomePage.projectStatus).</summary>
    WelcomePageProjectStatus: Boolean;
    /// <summary>Anzahl der gezeigten Projekte (#592, welcomePage.maxProjects, 1–30).</summary>
    WelcomePageMaxProjects: Integer;
    /// <summary>Branch und Änderungen beim Anzeigen frisch abfragen (#592, welcomePage.refreshVcs); sonst gilt
    /// der gespeicherte Stand.</summary>
    WelcomePageRefreshVcs: Boolean;
    /// <summary>Bereich „Nicht gesichert“ (#762, welcomePage.unsaved).</summary>
    WelcomePageUnsaved: Boolean;
    /// <summary>Nicht Gesichertes erst ab diesem Alter zeigen (#762, welcomePage.unsaved.minAgeHours, 0–8760).</summary>
    WelcomePageUnsavedMinAgeHours: Integer;
    /// <summary>Ab diesem Alter gelb (#762, welcomePage.unsaved.warnHours, 0–8760).</summary>
    WelcomePageUnsavedWarnHours: Integer;
    /// <summary>Ab diesem Alter rot (#762, welcomePage.unsaved.alertHours, 0–8760, nie unter warnHours).</summary>
    WelcomePageUnsavedAlertHours: Integer;
    /// <summary>Bereich ausblenden, wenn nichts zu zeigen ist (#762, welcomePage.unsaved.hideWhenClean).</summary>
    WelcomePageUnsavedHideWhenClean: Boolean;
    /// <summary>Zustandskachel „Atlas“ (#754, welcomePage.statusTile).</summary>
    WelcomePageStatusTile: Boolean;
    /// <summary>Zustandskachel nur zeigen, wenn eine Zeile gelb oder rot ist (#754,
    /// welcomePage.statusTile.onlyProblems).</summary>
    WelcomePageStatusTileOnlyProblems: Boolean;
    /// <summary>Karte „Atlas entdecken“ (#757, welcomePage.discover).</summary>
    WelcomePageDiscover: Boolean;
    /// <summary>Nutzung je Befehl lokal zählen (#757, tips.usageTracking; %LOCALAPPDATA%\Atlas\usage.json); aus =
    /// Tipps der Reihe nach ohne Bezug zur Nutzung, auch für die Tastenkürzel-Tipps (#600).</summary>
    TipsUsageTracking: Boolean;
    /// <summary>Bereich „Hilfe und Rückmeldung“ (#766, welcomePage.help): Atlas-Doku, Tastenkürzel, Problem
    /// melden.</summary>
    WelcomePageHelp: Boolean;
    /// <summary>Ziel für „Issue-Seite öffnen“ (#766, welcomePage.help.reportUrl); nur http:// und https://, sonst
    /// die Vorgabe.</summary>
    WelcomePageHelpReportUrl: string;
    /// <summary>Ordner für das Diagnosepaket (#766, welcomePage.help.reportFolder); '' = Desktop.</summary>
    WelcomePageHelpReportFolder: string;
    class function Defaults: TAtlasPluginSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    procedure Load(const AStore: IAtlasSettingsStore);
    procedure Save(const AStore: IAtlasSettingsStore);
    /// <summary>Rechtsklick auf das Statusfeld öffnet die Schnellschalter (StatusFieldToggles).</summary>
    function StatusTogglesOnRightClick: Boolean;
    /// <summary>Doppelklick auf das Statusfeld öffnet die Schnellschalter (StatusFieldToggles).</summary>
    function StatusTogglesOnDoubleClick: Boolean;
    /// <summary>Statusfeld zeigt den Fortschritt des Symbol-Index (IndexProgressPlace).</summary>
    function IndexProgressInField: Boolean;
    /// <summary>Titel des Menüs Atlas zeigt den Fortschritt (IndexProgressPlace, Statusfeld aus).</summary>
    function IndexProgressInMenu: Boolean;
  end;

implementation

uses
  System.Math,
  System.StrUtils;

/// <summary>http:// oder https:// mit etwas danach, ohne Leer- und Steuerzeichen (#766).</summary>
function IsWebAddress(const AValue: string): Boolean;
var
  Index: Integer;
begin
  Result := (StartsText('https://', AValue) and (Length(AValue) > 8)) or
    (StartsText('http://', AValue) and (Length(AValue) > 7));
  if not Result then
    Exit;
  for Index := 1 to Length(AValue) do
    if Ord(AValue[Index]) <= 32 then
      Exit(False);
end;

// Eigene Paarfarben einheitlich schreiben; ungültig = leer (Standardpalette).
function NormalPairs(const AText: string): string;
var
  Pairs: TAtlasPairColors;
begin
  if TAtlasColors.ParsePairs(AText, Pairs) then
    Result := TAtlasColors.PairsText(Pairs)
  else
    Result := '';
end;

/// <summary>AValue, wenn er (ohne Groß-/Kleinschreibung) unter AAllowed steht, in deren Schreibweise;
/// sonst der erste erlaubte Wert.</summary>
function Choice(const AValue: string; const AAllowed: array of string): string;
var
  Item: string;
begin
  for Item in AAllowed do
    if SameText(Trim(AValue), Item) then
      Exit(Item);
  Result := AAllowed[0];
end;

function BoolValue(AValue: Boolean): Integer;
begin
  if AValue then
    Result := 1
  else
    Result := 0;
end;

{ TAtlasPluginSettings }

class function TAtlasPluginSettings.Defaults: TAtlasPluginSettings;
begin
  Result.Enabled := True;
  Result.VisibleRows := 9;
  Result.ListWidth := 0;
  Result.PanelWidth := 320;
  Result.PanelCollapsed := False;
  Result.AutoParentheses := True;
  Result.FixCase := True;
  Result.CommitCharacters := True;
  Result.AutoUses := True;
  Result.ParameterHints := True;
  Result.OpenDelayMs := 150;
  Result.PaletteKey := $6050; // Strg+Umschalt+P
  Result.CheckKey := $C078; // Strg+Alt+F9
  Result.PaletteKeyPriority := False;
  Result.CheckKeyPriority := False;
  Result.CompletionKey := 0;
  Result.SignatureKey := 0;
  Result.CompletionKeyPriority := False;
  Result.SignatureKeyPriority := False;
  Result.FilterChips := True;
  Result.Learning := True;
  Result.Favorites := True;
  Result.GroupInherited := True;
  Result.Preview := False;
  Result.HoverTooltip := True;
  Result.HangThresholdMs := 500;
  Result.ProviderTimeLimitMs := 200;
  Result.HangHint := True;
  Result.ReloadExternal := True;
  Result.PairColors := True;
  Result.InactiveDim := True;
  Result.OpenForEdits := True;
  Result.InlayHints := False;
  Result.Notes := True;
  Result.ServerPath := '';
  Result.PairGuides := True;
  Result.PairOwners := True;
  Result.PairGuideWidth := 1;
  Result.PairGuideOpacity := 75;
  Result.PairColorsLight := '';
  Result.PairColorsDark := '';
  Result.Problems := True;
  Result.ProblemsList := True;
  // Die Prüfung in der IDE zeigt deren Fortschritt; Standard ist die Prüfung des Servers mit dcc (compiler.onSave).
  Result.CheckOnSave := False;
  Result.CompileOnSave := False;
  Result.CheckOnSaveDelayMs := 2000;
  Result.CheckOnSaveMaxMs := 1500;
  Result.ActionsKey := $800D; // Alt+Enter
  Result.ExpandKey := $4057; // Strg+W
  Result.ShrinkKey := $6057; // Strg+Umschalt+W
  Result.ImplementationKey := $C049; // Strg+Alt+I
  Result.TypeDefinitionKey := 0;
  Result.MethodToggle := True;
  Result.MethodToggleUpKey := $6026; // Strg+Umschalt+↑
  Result.MethodToggleDownKey := $6028; // Strg+Umschalt+↓
  Result.TestUnitKey := 0;
  Result.CodeLensTestUnit := True;
  Result.EditorKeysPriority := False;
  Result.SlashCommands := True;
  Result.Snippets := True;
  Result.ImportIdeTemplates := True;
  // Wie die Vorgaben im Schema (atlas.schema.json, index).
  Result.IndexProjectGroup := True;
  Result.IndexSearchPaths := True;
  Result.IndexLibraryPaths := False;
  Result.IndexUsages := True;
  Result.MemoryBudgetMb := 768;
  Result.XmlDocFull := True;
  Result.XmlDocMaxLines := 0;
  Result.StatusField := True;
  Result.StatusFieldHidden := '';
  Result.StatusFieldSummary := True;
  Result.StatusFieldToggles := 'both';
  Result.IndexProgressPlace := 'statusField';
  Result.QuickToggleKey := $E041; // Strg+Umschalt+Alt+A
  Result.QuickToggleKeyPriority := False;
  Result.DiagnosticMode := False;
  Result.DiagnosticModeKey := $E044; // Strg+Umschalt+Alt+D
  Result.DiagnosticModeKeyPriority := False;
  Result.SetupChecklist := True;
  Result.SetupChecklistSeen := False;
  Result.KeyOverview := True;
  Result.KeyStartupCheck := True;
  Result.ShortcutTips := True;
  Result.ShortcutTipsScope := 'all';
  Result.SafeAskAfterCrash := True;
  Result.SafeAutoAfterRepeatedCrash := True;
  Result.SafeStartupKey := 'shift';
  Result.SafeStartupTimeoutMs := 10000;
  Result.SafeKeepSettingsHistory := 5;
  Result.UndoMultiFile := True;
  Result.UndoMultiFileDepth := 20;
  Result.UndoMultiFilePersist := True;
  Result.UndoMultiFileMaxSizeMb := 50;
  Result.UndoMultiFileOnConflict := 'partial';
  Result.UndoMultiFileNewFiles := 'recycleBin';
  Result.UndoKey := $C05A; // Strg+Alt+Z
  Result.RedoKey := $E05A; // Strg+Alt+Umschalt+Z
  Result.UpdatesCheck := False;
  Result.BugReportAnonymize := True;
  Result.UnitSearchEnabled := True;
  Result.UnitSearchReplaceIdeDialog := True;
  Result.UnitSearchRememberCollapsed := True;
  Result.UnitSearchFilters := True;
  Result.UnitSearchFilterSyntax := True;
  Result.UnitSearchPreview := True;
  Result.UnitSearchPreviewForm := True;
  Result.UnitSearchPreviewUsedBy := True;
  Result.UnitSearchMultiSelect := True;
  Result.UnitSearchActions := True;
  Result.UnitSearchActionsAddUses := True;
  Result.UnitSearchPathStyle := 'relative';
  Result.UnitSearchGroupBy := 'project';
  Result.UnitSearchDefaultScope := 'group';
  Result.UnitSearchKey := 0;
  Result.WelcomePage := True;
  Result.WelcomePageHost := 'welcomePage';
  Result.WelcomePageLayout := 'off';
  Result.WelcomePageHeader := True;
  Result.WelcomePageGreeting := True;
  Result.WelcomePageSearch := True;
  Result.WelcomePageSearchSymbols := True;
  Result.WelcomePageSearchKey := $4045; // Strg+E
  Result.WelcomePageWhatsNew := 'afterUpdate';
  Result.WhatsNewSeen := '';
  Result.WelcomePageProjectStatus := True;
  Result.WelcomePageMaxProjects := 8;
  Result.WelcomePageRefreshVcs := True;
  Result.WelcomePageUnsaved := True;
  Result.WelcomePageUnsavedMinAgeHours := 0;
  Result.WelcomePageUnsavedWarnHours := 24;
  Result.WelcomePageUnsavedAlertHours := 72;
  Result.WelcomePageUnsavedHideWhenClean := False;
  Result.WelcomePageStatusTile := True;
  Result.WelcomePageStatusTileOnlyProblems := False;
  Result.WelcomePageDiscover := True;
  Result.TipsUsageTracking := True;
  Result.WelcomePageHelp := True;
  Result.WelcomePageHelpReportUrl := DefaultHelpReportUrl;
  Result.WelcomePageHelpReportFolder := '';
end;

procedure TAtlasPluginSettings.Normalize;
begin
  VisibleRows := EnsureRange(VisibleRows, MinVisibleRows, MaxVisibleRows);
  if ListWidth <> 0 then
    ListWidth := EnsureRange(ListWidth, MinListWidth, MaxListWidth);
  PanelWidth := EnsureRange(PanelWidth, MinPanelWidth, MaxPanelWidth);
  HangThresholdMs := EnsureRange(HangThresholdMs, MinHangThreshold, MaxHangThreshold);
  ProviderTimeLimitMs := EnsureRange(ProviderTimeLimitMs, MinProviderTimeLimit, MaxProviderTimeLimit);
  CheckOnSaveDelayMs := EnsureRange(CheckOnSaveDelayMs, MinCheckDelay, MaxCheckDelay);
  CheckOnSaveMaxMs := EnsureRange(CheckOnSaveMaxMs, MinCheckMax, MaxCheckMax);
  // Nach dem Speichern genau eins von beiden: Die Syntaxprüfung der IDE gewinnt.
  if CheckOnSave then
    CompileOnSave := False;
  XmlDocMaxLines := EnsureRange(XmlDocMaxLines, 0, MaxXmlDocLines);
  OpenDelayMs := EnsureRange(OpenDelayMs, 0, MaxOpenDelay);
  MemoryBudgetMb := EnsureRange(MemoryBudgetMb, 0, MaxMemoryBudgetMb);
  // TShortCut ist ein Word.
  PaletteKey := EnsureRange(PaletteKey, 0, $FFFF);
  WelcomePageSearchKey := EnsureRange(WelcomePageSearchKey, 0, $FFFF);
  WelcomePageMaxProjects := EnsureRange(WelcomePageMaxProjects, MinWelcomeProjects, MaxWelcomeProjects);
  WelcomePageUnsavedMinAgeHours := EnsureRange(WelcomePageUnsavedMinAgeHours, MinUnsavedHours, MaxUnsavedHours);
  WelcomePageUnsavedWarnHours := EnsureRange(WelcomePageUnsavedWarnHours, MinUnsavedHours, MaxUnsavedHours);
  // Rot nie vor gelb.
  WelcomePageUnsavedAlertHours := EnsureRange(WelcomePageUnsavedAlertHours, WelcomePageUnsavedWarnHours,
    MaxUnsavedHours);
  CheckKey := EnsureRange(CheckKey, 0, $FFFF);
  CompletionKey := EnsureRange(CompletionKey, 0, $FFFF);
  SignatureKey := EnsureRange(SignatureKey, 0, $FFFF);
  QuickToggleKey := EnsureRange(QuickToggleKey, 0, $FFFF);
  DiagnosticModeKey := EnsureRange(DiagnosticModeKey, 0, $FFFF);
  SafeStartupTimeoutMs := EnsureRange(SafeStartupTimeoutMs, MinSafeStartupTimeout, MaxSafeStartupTimeout);
  SafeKeepSettingsHistory := EnsureRange(SafeKeepSettingsHistory, 0, MaxSafeSettingsHistory);
  if SameText(Trim(StatusFieldToggles), 'rightClick') then
    StatusFieldToggles := 'rightClick'
  else if SameText(Trim(StatusFieldToggles), 'doubleClick') then
    StatusFieldToggles := 'doubleClick'
  else
    StatusFieldToggles := 'both';
  if SameText(Trim(IndexProgressPlace), 'menu') then
    IndexProgressPlace := 'menu'
  else if SameText(Trim(IndexProgressPlace), 'off') then
    IndexProgressPlace := 'off'
  else
    IndexProgressPlace := 'statusField';
  SafeStartupKey := LowerCase(Trim(SafeStartupKey));
  if (SafeStartupKey <> 'shift') and (SafeStartupKey <> 'ctrl') and (SafeStartupKey <> 'none') then
    SafeStartupKey := 'shift';
  UndoMultiFileDepth := EnsureRange(UndoMultiFileDepth, MinUndoDepth, MaxUndoDepth);
  UndoMultiFileMaxSizeMb := EnsureRange(UndoMultiFileMaxSizeMb, MinUndoMaxSizeMb, MaxUndoMaxSizeMb);
  if SameText(Trim(UndoMultiFileOnConflict), 'abort') then
    UndoMultiFileOnConflict := 'abort'
  else
    UndoMultiFileOnConflict := 'partial';
  if SameText(Trim(UndoMultiFileNewFiles), 'delete') then
    UndoMultiFileNewFiles := 'delete'
  else if SameText(Trim(UndoMultiFileNewFiles), 'keep') then
    UndoMultiFileNewFiles := 'keep'
  else
    UndoMultiFileNewFiles := 'recycleBin';
  UndoKey := EnsureRange(UndoKey, 0, $FFFF);
  RedoKey := EnsureRange(RedoKey, 0, $FFFF);
  MethodToggleUpKey := EnsureRange(MethodToggleUpKey, 0, $FFFF);
  MethodToggleDownKey := EnsureRange(MethodToggleDownKey, 0, $FFFF);
  PairGuideWidth := EnsureRange(PairGuideWidth, MinPairGuideWidth, MaxPairGuideWidth);
  PairGuideOpacity := EnsureRange(PairGuideOpacity, MinPairGuideOpacity, MaxPairGuideOpacity);
  PairColorsLight := NormalPairs(PairColorsLight);
  PairColorsDark := NormalPairs(PairColorsDark);
  UnitSearchPathStyle := Choice(UnitSearchPathStyle, ['relative', 'compact', 'absolute']);
  UnitSearchGroupBy := Choice(UnitSearchGroupBy, ['project', 'folder', 'none']);
  UnitSearchDefaultScope := Choice(UnitSearchDefaultScope, ['group', 'project', 'searchPath', 'library']);
  UnitSearchKey := EnsureRange(UnitSearchKey, 0, $FFFF);
  if SameText(Trim(WelcomePageHost), 'dockWindow') then
    WelcomePageHost := 'dockWindow'
  else
    WelcomePageHost := 'welcomePage';
  if SameText(Trim(WelcomePageLayout), 'atlas') then
    WelcomePageLayout := 'atlas'
  else
    WelcomePageLayout := 'off';
  if SameText(Trim(WelcomePageWhatsNew), 'off') then
    WelcomePageWhatsNew := 'off'
  else if SameText(Trim(WelcomePageWhatsNew), 'always') then
    WelcomePageWhatsNew := 'always'
  else
    WelcomePageWhatsNew := 'afterUpdate';
  WhatsNewSeen := Trim(WhatsNewSeen);
  if SameText(Trim(ShortcutTipsScope), 'atlas') then
    ShortcutTipsScope := 'atlas'
  else
    ShortcutTipsScope := 'all';
  // Nur Webadressen: „Issue-Seite öffnen“ übergibt das Ziel dem Browser (#766).
  WelcomePageHelpReportUrl := Trim(WelcomePageHelpReportUrl);
  if not IsWebAddress(WelcomePageHelpReportUrl) then
    WelcomePageHelpReportUrl := DefaultHelpReportUrl;
  WelcomePageHelpReportFolder := Trim(WelcomePageHelpReportFolder);
end;

procedure TAtlasPluginSettings.Load(const AStore: IAtlasSettingsStore);
var
  Default: TAtlasPluginSettings;
begin
  Default := Defaults;
  Enabled := AStore.ReadInteger('Enabled', BoolValue(Default.Enabled)) <> 0;
  VisibleRows := AStore.ReadInteger('VisibleRows', Default.VisibleRows);
  ListWidth := AStore.ReadInteger('ListWidth', Default.ListWidth);
  PanelWidth := AStore.ReadInteger('PanelWidth', Default.PanelWidth);
  PanelCollapsed := AStore.ReadInteger('PanelCollapsed', BoolValue(Default.PanelCollapsed)) <> 0;
  AutoParentheses := AStore.ReadInteger('AutoParentheses', BoolValue(Default.AutoParentheses)) <> 0;
  FixCase := AStore.ReadInteger('FixCase', BoolValue(Default.FixCase)) <> 0;
  CommitCharacters := AStore.ReadInteger('CommitCharacters', BoolValue(Default.CommitCharacters)) <> 0;
  AutoUses := AStore.ReadInteger('AutoUses', BoolValue(Default.AutoUses)) <> 0;
  ParameterHints := AStore.ReadInteger('ParameterHints', BoolValue(Default.ParameterHints)) <> 0;
  OpenDelayMs := AStore.ReadInteger('OpenDelayMs', Default.OpenDelayMs);
  PaletteKey := AStore.ReadInteger('PaletteKey', Default.PaletteKey);
  CheckKey := AStore.ReadInteger('CheckKey', Default.CheckKey);
  PaletteKeyPriority := AStore.ReadInteger('PaletteKeyPriority', BoolValue(Default.PaletteKeyPriority)) <> 0;
  CheckKeyPriority := AStore.ReadInteger('CheckKeyPriority', BoolValue(Default.CheckKeyPriority)) <> 0;
  CompletionKey := AStore.ReadInteger('CompletionKey', Default.CompletionKey);
  SignatureKey := AStore.ReadInteger('SignatureKey', Default.SignatureKey);
  CompletionKeyPriority := AStore.ReadInteger('CompletionKeyPriority', BoolValue(Default.CompletionKeyPriority)) <> 0;
  SignatureKeyPriority := AStore.ReadInteger('SignatureKeyPriority', BoolValue(Default.SignatureKeyPriority)) <> 0;
  FilterChips := AStore.ReadInteger('FilterChips', BoolValue(Default.FilterChips)) <> 0;
  Learning := AStore.ReadInteger('Learning', BoolValue(Default.Learning)) <> 0;
  Favorites := AStore.ReadInteger('Favorites', BoolValue(Default.Favorites)) <> 0;
  GroupInherited := AStore.ReadInteger('GroupInherited', BoolValue(Default.GroupInherited)) <> 0;
  Preview := AStore.ReadInteger('Preview', BoolValue(Default.Preview)) <> 0;
  HoverTooltip := AStore.ReadInteger('HoverTooltip', BoolValue(Default.HoverTooltip)) <> 0;
  HangThresholdMs := AStore.ReadInteger('HangThresholdMs', Default.HangThresholdMs);
  ProviderTimeLimitMs := AStore.ReadInteger('ProviderTimeLimitMs', Default.ProviderTimeLimitMs);
  HangHint := AStore.ReadInteger('HangHint', BoolValue(Default.HangHint)) <> 0;
  ReloadExternal := AStore.ReadInteger('ReloadExternal', BoolValue(Default.ReloadExternal)) <> 0;
  PairColors := AStore.ReadInteger('PairColors', BoolValue(Default.PairColors)) <> 0;
  InactiveDim := AStore.ReadInteger('InactiveDim', BoolValue(Default.InactiveDim)) <> 0;
  OpenForEdits := AStore.ReadInteger('OpenForEdits', BoolValue(Default.OpenForEdits)) <> 0;
  InlayHints := AStore.ReadInteger('InlayHints', BoolValue(Default.InlayHints)) <> 0;
  Notes := AStore.ReadInteger('Notes', BoolValue(Default.Notes)) <> 0;
  ServerPath := Trim(AStore.ReadString('ServerPath', Default.ServerPath));
  PairGuides := AStore.ReadInteger('PairGuides', BoolValue(Default.PairGuides)) <> 0;
  PairOwners := AStore.ReadInteger('PairOwners', BoolValue(Default.PairOwners)) <> 0;
  PairGuideWidth := AStore.ReadInteger('PairGuideWidth', Default.PairGuideWidth);
  PairGuideOpacity := AStore.ReadInteger('PairGuideOpacity', Default.PairGuideOpacity);
  PairColorsLight := AStore.ReadString('PairColorsLight', Default.PairColorsLight);
  PairColorsDark := AStore.ReadString('PairColorsDark', Default.PairColorsDark);
  Problems := AStore.ReadInteger('Problems', BoolValue(Default.Problems)) <> 0;
  ProblemsList := AStore.ReadInteger('ProblemsList', BoolValue(Default.ProblemsList)) <> 0;
  CheckOnSave := AStore.ReadInteger('CheckOnSave', BoolValue(Default.CheckOnSave)) <> 0;
  CheckOnSaveDelayMs := AStore.ReadInteger('CheckOnSaveDelayMs', Default.CheckOnSaveDelayMs);
  CheckOnSaveMaxMs := AStore.ReadInteger('CheckOnSaveMaxMs', Default.CheckOnSaveMaxMs);
  CompileOnSave := AStore.ReadInteger('CompileOnSave', BoolValue(Default.CompileOnSave)) <> 0;
  ActionsKey := AStore.ReadInteger('ActionsKey', Default.ActionsKey);
  ExpandKey := AStore.ReadInteger('ExpandKey', Default.ExpandKey);
  ShrinkKey := AStore.ReadInteger('ShrinkKey', Default.ShrinkKey);
  ImplementationKey := AStore.ReadInteger('ImplementationKey', Default.ImplementationKey);
  TypeDefinitionKey := AStore.ReadInteger('TypeDefinitionKey', Default.TypeDefinitionKey);
  MethodToggle := AStore.ReadInteger('MethodToggle', BoolValue(Default.MethodToggle)) <> 0;
  MethodToggleUpKey := AStore.ReadInteger('MethodToggleUpKey', Default.MethodToggleUpKey);
  MethodToggleDownKey := AStore.ReadInteger('MethodToggleDownKey', Default.MethodToggleDownKey);
  TestUnitKey := AStore.ReadInteger('TestUnitKey', Default.TestUnitKey);
  CodeLensTestUnit := AStore.ReadInteger('CodeLensTestUnit', BoolValue(Default.CodeLensTestUnit)) <> 0;
  EditorKeysPriority := AStore.ReadInteger('EditorKeysPriority', BoolValue(Default.EditorKeysPriority)) <> 0;
  SlashCommands := AStore.ReadInteger('SlashCommands', BoolValue(Default.SlashCommands)) <> 0;
  Snippets := AStore.ReadInteger('Snippets', BoolValue(Default.Snippets)) <> 0;
  ImportIdeTemplates := AStore.ReadInteger('ImportIdeTemplates', BoolValue(Default.ImportIdeTemplates)) <> 0;
  IndexProjectGroup := AStore.ReadInteger('IndexProjectGroup', BoolValue(Default.IndexProjectGroup)) <> 0;
  IndexSearchPaths := AStore.ReadInteger('IndexSearchPaths', BoolValue(Default.IndexSearchPaths)) <> 0;
  IndexLibraryPaths := AStore.ReadInteger('IndexLibraryPaths', BoolValue(Default.IndexLibraryPaths)) <> 0;
  IndexUsages := AStore.ReadInteger('IndexUsages', BoolValue(Default.IndexUsages)) <> 0;
  MemoryBudgetMb := AStore.ReadInteger('MemoryBudgetMb', Default.MemoryBudgetMb);
  XmlDocFull := AStore.ReadInteger('XmlDocFull', BoolValue(Default.XmlDocFull)) <> 0;
  XmlDocMaxLines := AStore.ReadInteger('XmlDocMaxLines', Default.XmlDocMaxLines);
  StatusField := AStore.ReadInteger('StatusField', BoolValue(Default.StatusField)) <> 0;
  StatusFieldHidden := Trim(AStore.ReadString('StatusFieldHidden', Default.StatusFieldHidden));
  StatusFieldSummary := AStore.ReadInteger('StatusFieldSummary', BoolValue(Default.StatusFieldSummary)) <> 0;
  StatusFieldToggles := AStore.ReadString('StatusFieldToggles', Default.StatusFieldToggles);
  IndexProgressPlace := AStore.ReadString('IndexProgressPlace', Default.IndexProgressPlace);
  QuickToggleKey := AStore.ReadInteger('QuickToggleKey', Default.QuickToggleKey);
  QuickToggleKeyPriority :=
    AStore.ReadInteger('QuickToggleKeyPriority', BoolValue(Default.QuickToggleKeyPriority)) <> 0;
  DiagnosticMode := AStore.ReadInteger('DiagnosticMode', BoolValue(Default.DiagnosticMode)) <> 0;
  DiagnosticModeKey := AStore.ReadInteger('DiagnosticModeKey', Default.DiagnosticModeKey);
  DiagnosticModeKeyPriority :=
    AStore.ReadInteger('DiagnosticModeKeyPriority', BoolValue(Default.DiagnosticModeKeyPriority)) <> 0;
  SetupChecklist := AStore.ReadInteger('SetupChecklist', BoolValue(Default.SetupChecklist)) <> 0;
  SetupChecklistSeen := AStore.ReadInteger('SetupChecklistSeen', BoolValue(Default.SetupChecklistSeen)) <> 0;
  KeyOverview := AStore.ReadInteger('KeyOverview', BoolValue(Default.KeyOverview)) <> 0;
  KeyStartupCheck := AStore.ReadInteger('KeyStartupCheck', BoolValue(Default.KeyStartupCheck)) <> 0;
  ShortcutTips := AStore.ReadInteger('ShortcutTips', BoolValue(Default.ShortcutTips)) <> 0;
  ShortcutTipsScope := AStore.ReadString('ShortcutTipsScope', Default.ShortcutTipsScope);
  SafeAskAfterCrash := AStore.ReadInteger('SafeAskAfterCrash', BoolValue(Default.SafeAskAfterCrash)) <> 0;
  SafeAutoAfterRepeatedCrash :=
    AStore.ReadInteger('SafeAutoAfterRepeatedCrash', BoolValue(Default.SafeAutoAfterRepeatedCrash)) <> 0;
  SafeStartupKey := AStore.ReadString('SafeStartupKey', Default.SafeStartupKey);
  SafeStartupTimeoutMs := AStore.ReadInteger('SafeStartupTimeoutMs', Default.SafeStartupTimeoutMs);
  SafeKeepSettingsHistory := AStore.ReadInteger('SafeKeepSettingsHistory', Default.SafeKeepSettingsHistory);
  UndoMultiFile := AStore.ReadInteger('UndoMultiFile', BoolValue(Default.UndoMultiFile)) <> 0;
  UndoMultiFileDepth := AStore.ReadInteger('UndoMultiFileDepth', Default.UndoMultiFileDepth);
  UndoMultiFilePersist := AStore.ReadInteger('UndoMultiFilePersist', BoolValue(Default.UndoMultiFilePersist)) <> 0;
  UndoMultiFileMaxSizeMb := AStore.ReadInteger('UndoMultiFileMaxSizeMb', Default.UndoMultiFileMaxSizeMb);
  UndoMultiFileOnConflict := AStore.ReadString('UndoMultiFileOnConflict', Default.UndoMultiFileOnConflict);
  UndoMultiFileNewFiles := AStore.ReadString('UndoMultiFileNewFiles', Default.UndoMultiFileNewFiles);
  UndoKey := AStore.ReadInteger('UndoKey', Default.UndoKey);
  RedoKey := AStore.ReadInteger('RedoKey', Default.RedoKey);
  UpdatesCheck := AStore.ReadInteger('UpdatesCheck', BoolValue(Default.UpdatesCheck)) <> 0;
  BugReportAnonymize := AStore.ReadInteger('BugReportAnonymize', BoolValue(Default.BugReportAnonymize)) <> 0;
  UnitSearchEnabled := AStore.ReadInteger('UnitSearchEnabled', BoolValue(Default.UnitSearchEnabled)) <> 0;
  UnitSearchReplaceIdeDialog := AStore.ReadInteger('UnitSearchReplaceIdeDialog', BoolValue(Default.UnitSearchReplaceIdeDialog)) <> 0;
  UnitSearchRememberCollapsed := AStore.ReadInteger('UnitSearchRememberCollapsed', BoolValue(Default.UnitSearchRememberCollapsed)) <> 0;
  UnitSearchFilters := AStore.ReadInteger('UnitSearchFilters', BoolValue(Default.UnitSearchFilters)) <> 0;
  UnitSearchFilterSyntax := AStore.ReadInteger('UnitSearchFilterSyntax', BoolValue(Default.UnitSearchFilterSyntax)) <> 0;
  UnitSearchPreview := AStore.ReadInteger('UnitSearchPreview', BoolValue(Default.UnitSearchPreview)) <> 0;
  UnitSearchPreviewForm := AStore.ReadInteger('UnitSearchPreviewForm', BoolValue(Default.UnitSearchPreviewForm)) <> 0;
  UnitSearchPreviewUsedBy := AStore.ReadInteger('UnitSearchPreviewUsedBy', BoolValue(Default.UnitSearchPreviewUsedBy)) <> 0;
  UnitSearchMultiSelect := AStore.ReadInteger('UnitSearchMultiSelect', BoolValue(Default.UnitSearchMultiSelect)) <> 0;
  UnitSearchActions := AStore.ReadInteger('UnitSearchActions', BoolValue(Default.UnitSearchActions)) <> 0;
  UnitSearchActionsAddUses := AStore.ReadInteger('UnitSearchActionsAddUses', BoolValue(Default.UnitSearchActionsAddUses)) <> 0;
  UnitSearchPathStyle := AStore.ReadString('UnitSearchPathStyle', Default.UnitSearchPathStyle);
  UnitSearchGroupBy := AStore.ReadString('UnitSearchGroupBy', Default.UnitSearchGroupBy);
  UnitSearchDefaultScope := AStore.ReadString('UnitSearchDefaultScope', Default.UnitSearchDefaultScope);
  UnitSearchKey := AStore.ReadInteger('UnitSearchKey', Default.UnitSearchKey);
  WelcomePage := AStore.ReadInteger('WelcomePage', BoolValue(Default.WelcomePage)) <> 0;
  WelcomePageHost := AStore.ReadString('WelcomePageHost', Default.WelcomePageHost);
  WelcomePageLayout := AStore.ReadString('WelcomePageLayout', Default.WelcomePageLayout);
  WelcomePageHeader := AStore.ReadInteger('WelcomePageHeader', BoolValue(Default.WelcomePageHeader)) <> 0;
  WelcomePageGreeting := AStore.ReadInteger('WelcomePageGreeting', BoolValue(Default.WelcomePageGreeting)) <> 0;
  WelcomePageSearch := AStore.ReadInteger('WelcomePageSearch', BoolValue(Default.WelcomePageSearch)) <> 0;
  WelcomePageSearchSymbols := AStore.ReadInteger('WelcomePageSearchSymbols',
    BoolValue(Default.WelcomePageSearchSymbols)) <> 0;
  WelcomePageSearchKey := AStore.ReadInteger('WelcomePageSearchKey', Default.WelcomePageSearchKey);
  WelcomePageWhatsNew := AStore.ReadString('WelcomePageWhatsNew', Default.WelcomePageWhatsNew);
  WhatsNewSeen := AStore.ReadString('WhatsNewSeen', Default.WhatsNewSeen);
  WelcomePageProjectStatus := AStore.ReadInteger('WelcomePageProjectStatus',
    BoolValue(Default.WelcomePageProjectStatus)) <> 0;
  WelcomePageMaxProjects := AStore.ReadInteger('WelcomePageMaxProjects', Default.WelcomePageMaxProjects);
  WelcomePageRefreshVcs := AStore.ReadInteger('WelcomePageRefreshVcs', BoolValue(Default.WelcomePageRefreshVcs)) <> 0;
  WelcomePageUnsaved := AStore.ReadInteger('WelcomePageUnsaved', BoolValue(Default.WelcomePageUnsaved)) <> 0;
  WelcomePageUnsavedMinAgeHours := AStore.ReadInteger('WelcomePageUnsavedMinAgeHours',
    Default.WelcomePageUnsavedMinAgeHours);
  WelcomePageUnsavedWarnHours := AStore.ReadInteger('WelcomePageUnsavedWarnHours', Default.WelcomePageUnsavedWarnHours);
  WelcomePageUnsavedAlertHours := AStore.ReadInteger('WelcomePageUnsavedAlertHours',
    Default.WelcomePageUnsavedAlertHours);
  WelcomePageUnsavedHideWhenClean := AStore.ReadInteger('WelcomePageUnsavedHideWhenClean',
    BoolValue(Default.WelcomePageUnsavedHideWhenClean)) <> 0;
  WelcomePageStatusTile := AStore.ReadInteger('WelcomePageStatusTile', BoolValue(Default.WelcomePageStatusTile)) <> 0;
  WelcomePageStatusTileOnlyProblems := AStore.ReadInteger('WelcomePageStatusTileOnlyProblems',
    BoolValue(Default.WelcomePageStatusTileOnlyProblems)) <> 0;
  WelcomePageDiscover := AStore.ReadInteger('WelcomePageDiscover', BoolValue(Default.WelcomePageDiscover)) <> 0;
  TipsUsageTracking := AStore.ReadInteger('TipsUsageTracking', BoolValue(Default.TipsUsageTracking)) <> 0;
  WelcomePageHelp := AStore.ReadInteger('WelcomePageHelp', BoolValue(Default.WelcomePageHelp)) <> 0;
  WelcomePageHelpReportUrl := AStore.ReadString('WelcomePageHelpReportUrl', Default.WelcomePageHelpReportUrl);
  WelcomePageHelpReportFolder := AStore.ReadString('WelcomePageHelpReportFolder',
    Default.WelcomePageHelpReportFolder);
  Normalize;
end;

procedure TAtlasPluginSettings.Save(const AStore: IAtlasSettingsStore);
begin
  Normalize;
  AStore.WriteInteger('Enabled', BoolValue(Enabled));
  AStore.WriteInteger('VisibleRows', VisibleRows);
  AStore.WriteInteger('ListWidth', ListWidth);
  AStore.WriteInteger('PanelWidth', PanelWidth);
  AStore.WriteInteger('PanelCollapsed', BoolValue(PanelCollapsed));
  AStore.WriteInteger('AutoParentheses', BoolValue(AutoParentheses));
  AStore.WriteInteger('FixCase', BoolValue(FixCase));
  AStore.WriteInteger('CommitCharacters', BoolValue(CommitCharacters));
  AStore.WriteInteger('AutoUses', BoolValue(AutoUses));
  AStore.WriteInteger('ParameterHints', BoolValue(ParameterHints));
  AStore.WriteInteger('OpenDelayMs', OpenDelayMs);
  AStore.WriteInteger('PaletteKey', PaletteKey);
  AStore.WriteInteger('CheckKey', CheckKey);
  AStore.WriteInteger('PaletteKeyPriority', BoolValue(PaletteKeyPriority));
  AStore.WriteInteger('CheckKeyPriority', BoolValue(CheckKeyPriority));
  AStore.WriteInteger('CompletionKey', CompletionKey);
  AStore.WriteInteger('SignatureKey', SignatureKey);
  AStore.WriteInteger('CompletionKeyPriority', BoolValue(CompletionKeyPriority));
  AStore.WriteInteger('SignatureKeyPriority', BoolValue(SignatureKeyPriority));
  AStore.WriteInteger('FilterChips', BoolValue(FilterChips));
  AStore.WriteInteger('Learning', BoolValue(Learning));
  AStore.WriteInteger('Favorites', BoolValue(Favorites));
  AStore.WriteInteger('GroupInherited', BoolValue(GroupInherited));
  AStore.WriteInteger('Preview', BoolValue(Preview));
  AStore.WriteInteger('HoverTooltip', BoolValue(HoverTooltip));
  AStore.WriteInteger('HangThresholdMs', HangThresholdMs);
  AStore.WriteInteger('ProviderTimeLimitMs', ProviderTimeLimitMs);
  AStore.WriteInteger('HangHint', BoolValue(HangHint));
  AStore.WriteInteger('ReloadExternal', BoolValue(ReloadExternal));
  AStore.WriteInteger('PairColors', BoolValue(PairColors));
  AStore.WriteInteger('InactiveDim', BoolValue(InactiveDim));
  AStore.WriteInteger('OpenForEdits', BoolValue(OpenForEdits));
  AStore.WriteInteger('InlayHints', BoolValue(InlayHints));
  AStore.WriteInteger('Notes', BoolValue(Notes));
  AStore.WriteString('ServerPath', Trim(ServerPath));
  AStore.WriteInteger('PairGuides', BoolValue(PairGuides));
  AStore.WriteInteger('PairOwners', BoolValue(PairOwners));
  AStore.WriteInteger('PairGuideWidth', PairGuideWidth);
  AStore.WriteInteger('PairGuideOpacity', PairGuideOpacity);
  AStore.WriteString('PairColorsLight', PairColorsLight);
  AStore.WriteString('PairColorsDark', PairColorsDark);
  AStore.WriteInteger('Problems', BoolValue(Problems));
  AStore.WriteInteger('ProblemsList', BoolValue(ProblemsList));
  AStore.WriteInteger('CheckOnSave', BoolValue(CheckOnSave));
  AStore.WriteInteger('CheckOnSaveDelayMs', CheckOnSaveDelayMs);
  AStore.WriteInteger('CheckOnSaveMaxMs', CheckOnSaveMaxMs);
  AStore.WriteInteger('CompileOnSave', BoolValue(CompileOnSave));
  AStore.WriteInteger('ActionsKey', ActionsKey);
  AStore.WriteInteger('ExpandKey', ExpandKey);
  AStore.WriteInteger('ShrinkKey', ShrinkKey);
  AStore.WriteInteger('ImplementationKey', ImplementationKey);
  AStore.WriteInteger('TypeDefinitionKey', TypeDefinitionKey);
  AStore.WriteInteger('MethodToggle', BoolValue(MethodToggle));
  AStore.WriteInteger('MethodToggleUpKey', MethodToggleUpKey);
  AStore.WriteInteger('MethodToggleDownKey', MethodToggleDownKey);
  AStore.WriteInteger('TestUnitKey', TestUnitKey);
  AStore.WriteInteger('CodeLensTestUnit', BoolValue(CodeLensTestUnit));
  AStore.WriteInteger('EditorKeysPriority', BoolValue(EditorKeysPriority));
  AStore.WriteInteger('SlashCommands', BoolValue(SlashCommands));
  AStore.WriteInteger('Snippets', BoolValue(Snippets));
  AStore.WriteInteger('ImportIdeTemplates', BoolValue(ImportIdeTemplates));
  AStore.WriteInteger('IndexProjectGroup', BoolValue(IndexProjectGroup));
  AStore.WriteInteger('IndexSearchPaths', BoolValue(IndexSearchPaths));
  AStore.WriteInteger('IndexLibraryPaths', BoolValue(IndexLibraryPaths));
  AStore.WriteInteger('IndexUsages', BoolValue(IndexUsages));
  AStore.WriteInteger('MemoryBudgetMb', MemoryBudgetMb);
  AStore.WriteInteger('XmlDocFull', BoolValue(XmlDocFull));
  AStore.WriteInteger('XmlDocMaxLines', XmlDocMaxLines);
  AStore.WriteInteger('StatusField', BoolValue(StatusField));
  AStore.WriteString('StatusFieldHidden', Trim(StatusFieldHidden));
  AStore.WriteInteger('StatusFieldSummary', BoolValue(StatusFieldSummary));
  AStore.WriteString('StatusFieldToggles', StatusFieldToggles);
  AStore.WriteString('IndexProgressPlace', IndexProgressPlace);
  AStore.WriteInteger('QuickToggleKey', QuickToggleKey);
  AStore.WriteInteger('QuickToggleKeyPriority', BoolValue(QuickToggleKeyPriority));
  AStore.WriteInteger('DiagnosticMode', BoolValue(DiagnosticMode));
  AStore.WriteInteger('DiagnosticModeKey', DiagnosticModeKey);
  AStore.WriteInteger('DiagnosticModeKeyPriority', BoolValue(DiagnosticModeKeyPriority));
  AStore.WriteInteger('SetupChecklist', BoolValue(SetupChecklist));
  AStore.WriteInteger('SetupChecklistSeen', BoolValue(SetupChecklistSeen));
  AStore.WriteInteger('KeyOverview', BoolValue(KeyOverview));
  AStore.WriteInteger('KeyStartupCheck', BoolValue(KeyStartupCheck));
  AStore.WriteInteger('ShortcutTips', BoolValue(ShortcutTips));
  AStore.WriteString('ShortcutTipsScope', ShortcutTipsScope);
  AStore.WriteInteger('SafeAskAfterCrash', BoolValue(SafeAskAfterCrash));
  AStore.WriteInteger('SafeAutoAfterRepeatedCrash', BoolValue(SafeAutoAfterRepeatedCrash));
  AStore.WriteString('SafeStartupKey', SafeStartupKey);
  AStore.WriteInteger('SafeStartupTimeoutMs', SafeStartupTimeoutMs);
  AStore.WriteInteger('SafeKeepSettingsHistory', SafeKeepSettingsHistory);
  AStore.WriteInteger('UndoMultiFile', BoolValue(UndoMultiFile));
  AStore.WriteInteger('UndoMultiFileDepth', UndoMultiFileDepth);
  AStore.WriteInteger('UndoMultiFilePersist', BoolValue(UndoMultiFilePersist));
  AStore.WriteInteger('UndoMultiFileMaxSizeMb', UndoMultiFileMaxSizeMb);
  AStore.WriteString('UndoMultiFileOnConflict', UndoMultiFileOnConflict);
  AStore.WriteString('UndoMultiFileNewFiles', UndoMultiFileNewFiles);
  AStore.WriteInteger('UndoKey', UndoKey);
  AStore.WriteInteger('RedoKey', RedoKey);
  AStore.WriteInteger('UpdatesCheck', BoolValue(UpdatesCheck));
  AStore.WriteInteger('BugReportAnonymize', BoolValue(BugReportAnonymize));
  AStore.WriteInteger('UnitSearchEnabled', BoolValue(UnitSearchEnabled));
  AStore.WriteInteger('UnitSearchReplaceIdeDialog', BoolValue(UnitSearchReplaceIdeDialog));
  AStore.WriteInteger('UnitSearchRememberCollapsed', BoolValue(UnitSearchRememberCollapsed));
  AStore.WriteInteger('UnitSearchFilters', BoolValue(UnitSearchFilters));
  AStore.WriteInteger('UnitSearchFilterSyntax', BoolValue(UnitSearchFilterSyntax));
  AStore.WriteInteger('UnitSearchPreview', BoolValue(UnitSearchPreview));
  AStore.WriteInteger('UnitSearchPreviewForm', BoolValue(UnitSearchPreviewForm));
  AStore.WriteInteger('UnitSearchPreviewUsedBy', BoolValue(UnitSearchPreviewUsedBy));
  AStore.WriteInteger('UnitSearchMultiSelect', BoolValue(UnitSearchMultiSelect));
  AStore.WriteInteger('UnitSearchActions', BoolValue(UnitSearchActions));
  AStore.WriteInteger('UnitSearchActionsAddUses', BoolValue(UnitSearchActionsAddUses));
  AStore.WriteString('UnitSearchPathStyle', UnitSearchPathStyle);
  AStore.WriteString('UnitSearchGroupBy', UnitSearchGroupBy);
  AStore.WriteString('UnitSearchDefaultScope', UnitSearchDefaultScope);
  AStore.WriteInteger('UnitSearchKey', UnitSearchKey);
  AStore.WriteInteger('WelcomePage', BoolValue(WelcomePage));
  AStore.WriteString('WelcomePageHost', WelcomePageHost);
  AStore.WriteString('WelcomePageLayout', WelcomePageLayout);
  AStore.WriteInteger('WelcomePageHeader', BoolValue(WelcomePageHeader));
  AStore.WriteInteger('WelcomePageGreeting', BoolValue(WelcomePageGreeting));
  AStore.WriteInteger('WelcomePageSearch', BoolValue(WelcomePageSearch));
  AStore.WriteInteger('WelcomePageSearchSymbols', BoolValue(WelcomePageSearchSymbols));
  AStore.WriteInteger('WelcomePageSearchKey', WelcomePageSearchKey);
  AStore.WriteString('WelcomePageWhatsNew', WelcomePageWhatsNew);
  AStore.WriteString('WhatsNewSeen', WhatsNewSeen);
  AStore.WriteInteger('WelcomePageProjectStatus', BoolValue(WelcomePageProjectStatus));
  AStore.WriteInteger('WelcomePageMaxProjects', WelcomePageMaxProjects);
  AStore.WriteInteger('WelcomePageRefreshVcs', BoolValue(WelcomePageRefreshVcs));
  AStore.WriteInteger('WelcomePageUnsaved', BoolValue(WelcomePageUnsaved));
  AStore.WriteInteger('WelcomePageUnsavedMinAgeHours', WelcomePageUnsavedMinAgeHours);
  AStore.WriteInteger('WelcomePageUnsavedWarnHours', WelcomePageUnsavedWarnHours);
  AStore.WriteInteger('WelcomePageUnsavedAlertHours', WelcomePageUnsavedAlertHours);
  AStore.WriteInteger('WelcomePageUnsavedHideWhenClean', BoolValue(WelcomePageUnsavedHideWhenClean));
  AStore.WriteInteger('WelcomePageStatusTile', BoolValue(WelcomePageStatusTile));
  AStore.WriteInteger('WelcomePageStatusTileOnlyProblems', BoolValue(WelcomePageStatusTileOnlyProblems));
  AStore.WriteInteger('WelcomePageDiscover', BoolValue(WelcomePageDiscover));
  AStore.WriteInteger('TipsUsageTracking', BoolValue(TipsUsageTracking));
  AStore.WriteInteger('WelcomePageHelp', BoolValue(WelcomePageHelp));
  AStore.WriteString('WelcomePageHelpReportUrl', WelcomePageHelpReportUrl);
  AStore.WriteString('WelcomePageHelpReportFolder', WelcomePageHelpReportFolder);
end;

function TAtlasPluginSettings.StatusTogglesOnRightClick: Boolean;
begin
  Result := not SameText(Trim(StatusFieldToggles), 'doubleClick');
end;

function TAtlasPluginSettings.StatusTogglesOnDoubleClick: Boolean;
begin
  Result := not SameText(Trim(StatusFieldToggles), 'rightClick');
end;

function TAtlasPluginSettings.IndexProgressInField: Boolean;
begin
  Result := StatusField and SameText(Trim(IndexProgressPlace), 'statusField');
end;

function TAtlasPluginSettings.IndexProgressInMenu: Boolean;
begin
  Result := SameText(Trim(IndexProgressPlace), 'menu') or
    (not StatusField and SameText(Trim(IndexProgressPlace), 'statusField'));
end;

end.
