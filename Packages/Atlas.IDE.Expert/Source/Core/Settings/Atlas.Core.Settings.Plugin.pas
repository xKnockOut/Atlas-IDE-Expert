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

const
  /// <summary>Werte von bookmarks.quick.scope (#1104) in der Reihenfolge der Optionsseite.</summary>
  AtlasQuickBookmarkScopes: array[0..1] of string = ('project', 'file');

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
    MinPeekLines = 5;
    MaxPeekLines = 60;
    /// <summary>Grenzen für editor.stickyScrollMaxLines (#506).</summary>
    MinStickyLines = 1;
    MaxStickyLines = 10;
    /// <summary>Grenzen für highlight.selectionMatches.minLength und .maxMatches (#709).</summary>
    MinSelectionMatchLength = 1;
    MaxSelectionMatchLength = 100;
    MinSelectionMatches = 1;
    MaxSelectionMatches = 100000;
    /// <summary>Grenzen für editor.minimap.width, .scale und .maxColumn (#873).</summary>
    MinMinimapWidth = 40;
    MaxMinimapWidth = 400;
    MinMinimapScale = 1;
    MaxMinimapScale = 3;
    MinMinimapColumn = 20;
    MaxMinimapColumn = 500;
    /// <summary>Grenzen für editor.blockEndLabels.minLines (#620).</summary>
    MinBlockEndLines = 1;
    MaxBlockEndLines = 1000;
    /// <summary>Höchste Wartezeit in ms auf den zweiten Teil der Faltungsakkorde (#1104,
    /// bookmarks.quick.chordWait).</summary>
    MaxQuickChordWait = 5000;
    /// <summary>Grenzen für editor.recursionMarkers.depth (#623); wie TRecursionAnalysis im Server.</summary>
    MinRecursionDepth = 1;
    MaxRecursionDepth = 16;
    /// <summary>Muster fortsetzen (#671): Mindestzahl gleichförmiger Zeilen.</summary>
    MinPatternLines = 2;
    MaxPatternLines = 5;
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
    /// <summary>Spalten der Willkommensseite (#767, welcomePage.columns).</summary>
    MinWelcomeColumns = 1;
    MaxWelcomeColumns = 3;
    /// <summary>Name des Layouts, das Atlas anlegt (#767, welcomePage.activeLayout).</summary>
    DefaultWelcomeLayoutName = 'Standard';
    /// <summary>Grenzen der Stunden für welcomePage.unsaved.* (#762); wie TAtlasWelcomeUnsaved.MaxHours.</summary>
    MinUnsavedHours = 0;
    MaxUnsavedHours = 8760;
    /// <summary>Grenzen für welcomePage.continue.count (#755); wie TAtlasWelcomeContinue.MinCount/MaxCount.</summary>
    MinContinueCount = 1;
    MaxContinueCount = 20;
    /// <summary>Grenzen für welcomePage.trends.points (#758); wie TAtlasProjectTrendLog.MinPoints/MaxPoints.</summary>
    MinTrendPoints = 2;
    MaxTrendPoints = 100;
    /// <summary>Grenzen für welcomePage.tests.maxFailures und welcomePage.tests.ci.intervalMinutes (#763); wie
    /// TAtlasWelcomeTestResults (Test prüft Gleichheit).</summary>
    MinTestFailures = 1;
    MaxTestFailures = 50;
    MinCiIntervalMinutes = 1;
    MaxCiIntervalMinutes = 1440;
    /// <summary>Vorgabe für welcomePage.tests.ci.provider (#763).</summary>
    DefaultCiProvider = 'jenkins';
    /// <summary>Werte von welcomePage.issues.start (#765); wie TAtlasWelcomeIssues.StartName.</summary>
    IssuesStartBranch = 'branch';
    IssuesStartRemember = 'remember';
    /// <summary>Vorgabe für welcomePage.issues.commitPattern (#765); wie TAtlasTrackerNaming.CommitPattern.
    /// </summary>
    DefaultIssuesCommitPattern = '{kennung} ';
    /// <summary>Höchstlänge der Texte unter welcomePage.issues.* (#765).</summary>
    MaxIssuesText = 200;
    /// <summary>Werte von editor.completeStatement.beginEnd und .tryKind (#697).</summary>
    BeginEndAlways = 'always';
    BeginEndMultiLine = 'multiLine';
    BeginEndNever = 'never';
    TryKindFinally = 'finally';
    TryKindExcept = 'except';
    TryKindAsk = 'ask';
    /// <summary>Werte von editor.multiCursorModifier (#589): Taste für den Klick mit neuer Marke.</summary>
    MultiCursorModifierAlt = 'alt';
    MultiCursorModifierCtrl = 'ctrl';
    /// <summary>Grenzen für notifications.maxEntries (#601); wie TAtlasNotificationCenter.MinEntries/MaxMaxEntries
    /// (Test prüft Gleichheit).</summary>
    MinNotificationEntries = 10;
    MaxNotificationEntries = 1000;
    /// <summary>Vorgabe für welcomePage.trends.series (#758): alle Reihen, Namen wie
    /// TAtlasProjectSummaries.TrendKeys.</summary>
    DefaultTrendSeries = 'warnings,ruleHits,todos,duration,methodLength';
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
    /// <summary>Gewählter Eintrag mit Rahmen und Marke statt nur farbig (#447).</summary>
    SelectionMarker: Boolean;
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
    /// <summary>Marke „Zweig 0“ an Feldern varianter Records (#846, completion.variantBranch).</summary>
    CompletionVariantBranch: Boolean;
    /// <summary>Beim Tippen nur Treffer (filter), alle Einträge mit Treffern oben (all) oder Treffer und darunter
    /// gedämpft der Rest (rest) (completion.listMode, #497).</summary>
    CompletionListMode: string;
    /// <summary>Wo der Listenmodus gilt: Mitgliederlisten nach "." (members) oder überall (everywhere)
    /// (completion.listMode.scope, #497).</summary>
    CompletionListScope: string;
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
    /// <summary>Abgeleiteter Typ von var X := …, const X = … und for var X in … als Marke (#453,
    /// inlayHints.inferredTypes); unabhängig von InlayHints.</summary>
    InlayTypeHints: Boolean;
    /// <summary>Symbole aus Include-Dateien hinter {$I} („definiert COMPLIB_VCL“, #860,
    /// inlayHints.includeDefines); unabhängig von InlayHints.</summary>
    InlayDefineHints: Boolean;
    /// <summary>Code hinter Steuerzeichen wie ^C in Konstanten („#3“, #862, inlayHints.controlChars).</summary>
    InlayCharHints: Boolean;
    /// <summary>Beschriftung hinter dem end langer Blöcke (#620, editor.blockEndLabels): „// TKunde.Speichern“ in
    /// grauer Pille; Quelle sind die Endmarken des Servers (inlayHints.endMarkers, Mindestlänge
    /// inlayHints.endMarkerMinLines in atlas.json); unabhängig von InlayHints.</summary>
    BlockEndLabels: Boolean;
    /// <summary>Beschriftung erst ab so vielen Zeilen Blocklänge (#620, editor.blockEndLabels.minLines); geht mit
    /// der Anfrage an den Server und ersetzt dort inlayHints.endMarkerMinLines.</summary>
    BlockEndLabelsMinLines: Integer;
    /// <summary>Ungenutzte uses-Einträge abblenden (#621, editor.dimUnusedUses); der Tooltip nennt den Grund und
    /// bietet Entfernen und Verschieben an. Aus: weder Abblenden noch Hinweise.</summary>
    DimUnusedUses: Boolean;
    /// <summary>Rekursionssymbol (↻) in der Rinne neben Aufrufen, die zur Methode zurückführen (#623,
    /// editor.recursionMarkers); der Tooltip zeigt die Kette, jede Methode anklickbar.</summary>
    RecursionMarkers: Boolean;
    /// <summary>Höchstens so viele Methoden auf einem Kreis (#623, editor.recursionMarkers.depth).</summary>
    RecursionMarkersDepth: Integer;
    /// <summary>Persönliche Notizen an Codezeilen (#545): Symbol in der Rinne, Befehle und Liste; gespeichert in
    /// %LOCALAPPDATA%\Atlas\Notes\, nie im Quelltext.</summary>
    Notes: Boolean;
    /// <summary>Benannte Lesezeichen (#622, bookmarks.named): Befehle, Seitenfenster „Lesezeichen“ und Symbol in der
    /// Rinne; aus = die Funktion ruht, die nummerierten Lesezeichen der IDE bleiben unberührt.</summary>
    BookmarksNamed: Boolean;
    /// <summary>Lesezeichen im Repository für das Team speichern (#622, bookmarks.shared): atlas-bookmarks.json
    /// statt der lokalen .atlas-bookmarks.json neben der .dproj.</summary>
    BookmarksShared: Boolean;
    /// <summary>„Lesezeichen setzen…“ (#622, TShortCut, 0 = keins; Vorgabe Strg+Alt+K).</summary>
    BookmarkKey: Integer;
    /// <summary>„Element ausblenden …“ (#628, TShortCut, 0 = keins; Vorgabe Strg+.): Menü „Ausblenden“ für das von
    /// Atlas gezeichnete Element in der Cursorzeile; ohne Element geht die Taste an die IDE (IDE Insight).</summary>
    HideElementKey: Integer;
    /// <summary>Atlas-Suche ersetzt die IDE-Suche (#878, search.replaceIdeSearch): Strg+F öffnet die Suchleiste
    /// unter dem Editor, F3/Umschalt+F3 springen in der zuletzt benutzten Atlas-Suche; aus = Suchen der IDE wie
    /// bisher. Vorgabe an.</summary>
    SearchReplaceIde: Boolean;
    /// <summary>Treffer der Atlas-Suche im Reiter „Atlas-Suche“ des Fensters Meldungen auflisten (#878,
    /// search.resultsInMessages; Enter bzw. „In Meldungen“ in der Suchleiste). Vorgabe an.</summary>
    SearchResultsInMessages: Boolean;
    /// <summary>Taste für die Atlas-Suchleiste (#878, TShortCut, 0 = keine; Vorgabe Strg+F).</summary>
    SearchKey: Integer;
    /// <summary>Nächster Treffer der letzten Atlas-Suche (#878; Vorgabe F3).</summary>
    SearchNextKey: Integer;
    /// <summary>Voriger Treffer der letzten Atlas-Suche (#878; Vorgabe Umschalt+F3).</summary>
    SearchPreviousKey: Integer;
    /// <summary>„In Methode suchen“ (#877): Suchleiste mit Bereich Methode und dem Bezeichner am Cursor; gilt
    /// auch mit search.replaceIdeSearch aus (Vorgabe Strg+Umschalt+Alt+F).</summary>
    SearchMethodKey: Integer;
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
    /// <summary>Probleme zusätzlich im Meldungsfenster auflisten (Gruppe „Atlas-Probleme“); nur mit Problems. Seit dem
    /// Fenster „Atlas-Prüfung“ (#909) Vorgabe aus.</summary>
    ProblemsList: Boolean;
    /// <summary>Fenster „Atlas-Prüfung“ (#909): verfügbar (aus = kein Menüeintrag, kein Fenster); nur mit Problems.
    /// </summary>
    ProblemsWindow: Boolean;
    /// <summary>Bereich des Fensters: 'file', 'project', 'group' (Vorgabe).</summary>
    ProblemsWindowScope: string;
    /// <summary>Gruppierung: 'none', 'file' (Vorgabe), 'rule', 'category'.</summary>
    ProblemsWindowGroupBy: string;
    /// <summary>Spalten mit Reihenfolge, Breite und Sichtbarkeit ("kind:70,-rule,…", TAtlasFindings.ParseColumns); '' =
    /// alle in der Vorgabe-Reihenfolge.</summary>
    ProblemsWindowColumns: string;
    /// <summary>Compilermeldungen (dcc) im Fenster mit anzeigen.</summary>
    ProblemsWindowCompiler: Boolean;
    /// <summary>Eintrag zur Cursorzeile im Fenster markieren.</summary>
    ProblemsWindowFollowCursor: Boolean;
    /// <summary>Offene Units zuerst (#1108): aktive Unit oben angepinnt, geöffnete darunter, nicht geöffnete danach;
    /// Hauptschalter von ProblemsWindowClosedUnits und ProblemsWindowShowCleanActive.</summary>
    ProblemsWindowOpenFirst: Boolean;
    /// <summary>Nicht geöffnete Units: 'dimmed' (Vorgabe, ausgegraut), 'normal' (nur einsortiert), 'hidden'.</summary>
    ProblemsWindowClosedUnits: string;
    /// <summary>Aktive Unit auch ohne Befunde oben zeigen („Keine Befunde“ bzw. „wird geprüft …“).</summary>
    ProblemsWindowShowCleanActive: Boolean;
    /// <summary>Bestätigt der Build einen Atlas-Befund (gleiche Zeile, gleicher Code, #1024): 'merge' (Vorgabe)
    /// zeigt nur den Atlas-Befund mit Marke „Atlas + dcc“, 'both' beide Meldungen.</summary>
    ProblemsCompilerMerge: string;
    /// <summary>Compilercode (E2035 …) in Meldung, Spalte „Compiler“ und Hover zeigen (#1024).</summary>
    ProblemsShowCompilerCode: Boolean;
    /// <summary>Fenster öffnen (TShortCut, 0 = keins; Vorgabe Strg+Alt+P).</summary>
    ProblemsWindowKey: Integer;
    /// <summary>Kürzel „Zum interface-Teil“ (#1101, keys.gotoInterface); 0 = keins.</summary>
    GotoInterfaceKey: Integer;
    /// <summary>Kürzel „Zum implementation-Teil“ (#1101, keys.gotoImplementation); 0 = keins.</summary>
    GotoImplementationKey: Integer;
    /// <summary>Laufende Prüfung beim Tippen (#909); aus = Prüfung der offenen Datei nur beim Speichern.</summary>
    ProblemsLive: Boolean;
    /// <summary>Aktionszeile im Befund-Hover (#909): Schnellkorrektur, für diese Zeile unterdrücken, Regel einstellen.
    /// </summary>
    HoverProblemActions: Boolean;
    /// <summary>Fehlertext am Zeilenende (#509): 'off', 'errors' (Vorgabe), 'errorsAndWarnings', 'all'; nur mit
    /// Problems.</summary>
    InlineDiagnostics: string;
    /// <summary>Zähler „Fehler/Warnungen/Hinweise“ in der Statusleiste (#509); Klick öffnet die Liste.</summary>
    ProblemsStatusCounter: Boolean;
    /// <summary>Nächster bzw. vorheriger Befund in der Datei (#509, TShortCut, 0 = keins; Vorgabe Strg+Alt+F8
    /// und Strg+Alt+Umschalt+F8).</summary>
    NextProblemKey: Integer;
    PreviousProblemKey: Integer;
    /// <summary>Syntaxprüfung des Compilers nach dem Speichern (#548). Schließt CompileOnSave aus: Die
    /// Optionsseite bietet eine Auswahl „Nach dem Speichern“ (aus, Syntaxprüfung, Kompilieren).</summary>
    CheckOnSave: Boolean;
    /// <summary>Der Server kompiliert nach dem Speichern im Hintergrund (compiler.onSave, #40).</summary>
    CompileOnSave: Boolean;
    /// <summary>Wartezeit nach dem letzten Speichern.</summary>
    CheckOnSaveDelayMs: Integer;
    /// <summary>Höchstdauer einer Prüfung; darüber nur noch von Hand (Strg+Alt+F9).</summary>
    CheckOnSaveMaxMs: Integer;
    /// <summary>Claude Code darf über das MCP-Werkzeug build_project offene Projekte in dieser IDE bauen (#261),
    /// z. B. in der Starter Edition ohne Kommandozeilen-Compiler.</summary>
    McpBuild: Boolean;
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
    /// <summary>Code Lens mit den Kennzahlen jeder Methode (#66, codeLens.metrics; liegt in settings.json):
    /// Länge, Tiefe, zyklomatische und kognitive Komplexität, Parameter.</summary>
    CodeLensMetrics: Boolean;
    /// <summary>Kennzahlen überhaupt ("metrics", settings.json): aus schaltet die Code Lens der Kennzahlen und
    /// die Regeln metric-* ab; ein Projekt übersteuert je Regel in atlas.json unter "rules".</summary>
    Metrics: Boolean;
    /// <summary>Code Lens „Test ausführen“ an Fixtures und Tests von DUnitX (#69, codeLens.tests; gemeinsamer
    /// Schlüssel mit „Test debuggen“ #585).</summary>
    CodeLensTests: Boolean;
    /// <summary>Befehle „Tests ausführen“ und „Fehlgeschlagene Tests erneut ausführen“ (#69, Atlas.RunTests,
    /// Atlas.RunFailedTests); aus = Befehle, Code Lens und Lauf nach dem Build verschwinden.</summary>
    TestRun: Boolean;
    /// <summary>Tests nach jedem erfolgreichen Build des Testprojekts automatisch ausführen (#69, über die
    /// Compile-Ereignisse #527).</summary>
    TestsAfterBuild: Boolean;
    /// <summary>Vor „Tests ausführen“ das Testprojekt bauen (make); aus = die vorhandene Test-EXE läuft.</summary>
    TestsBuildFirst: Boolean;
    /// <summary>Ein Build gilt nur ohne Warnungen und Hinweise als erfolgreich (build.zeroHints, #530). Wirkt
    /// bisher auf „Tests nach dem Build“ (#69).</summary>
    BuildZeroHints: Boolean;
    /// <summary>Release-Build-Wächter (#533, build.releaseGuard): vor make und build in einer Release-Konfiguration
    /// die Projektoptionen prüfen, dazu der Befehl „Release-Build prüfen“ (Atlas.CheckRelease) mit Tipp. Aus = keine
    /// Prüfung, Befehl und Tipp verschwinden.</summary>
    ReleaseGuard: Boolean;
    /// <summary>Verhalten bei Verstößen (build.gate, #529): off, warn (beide melden nur) oder block (bricht den
    /// Build ab). Wirkt bisher nur auf den Release-Wächter.</summary>
    BuildGate: string;
    /// <summary>Konfigurationen, die außer „Release“ als Release gelten (build.releaseConfigs), durch Komma
    /// getrennt.</summary>
    ReleaseConfigs: string;
    /// <summary>Prüfungen des Release-Wächters mit an/aus und Sollwert (build.releaseChecks), Textform wie
    /// TAtlasReleaseChecks.ToText, z. B. "debugDefine,debugInfo=off,-assertions=off,…".</summary>
    ReleaseChecks: string;
    /// <summary>Einzelnen Test im Debugger starten (#585, tests.debug): Befehl „Test am Cursor debuggen“
    /// (Atlas.DebugTest) mit Tipp, Eintrag im Kontextmenü und Marke „Debuggen“ der Code Lens; braucht TestRun. Aus
    /// = Befehl, Tipp und Marke verschwinden.</summary>
    TestDebug: Boolean;
    /// <summary>Beim Test-Debuggen am Anfang der Methode anhalten (#585, debug.testBreakAtStart): einmaliger
    /// Haltepunkt an der ersten Anweisung, nach dem Halt entfernt.</summary>
    TestBreakAtStart: Boolean;
    /// <summary>Variablenwerte im Hover beim Debuggen (#891, debug.hoverValues): Bei angehaltenem Prozess wertet
    /// Atlas den Ausdruck unter der Maus über den Debugger der IDE aus und zeigt den Wert oben im Tooltip (bzw.
    /// im Tooltip der IDE, wenn der eigene aus ist); aus = kein Wert.</summary>
    DebugHoverValues: Boolean;
    /// <summary>Startprofile (#575, startProfiles.enabled): Befehl „Startprofil: …“ (Atlas.StartProfile) mit Tipp,
    /// Feld in der Statusleiste und Setzen der Startoptionen des Projekts; aus = Befehl, Tipp und Feld
    /// verschwinden, die Startoptionen der IDE bleiben, wie sie sind.</summary>
    StartProfiles: Boolean;
    /// <summary>Aktives Startprofil als Feld in der Statusleiste des Editors (#575, startProfiles.statusField);
    /// Klick öffnet die Auswahl.</summary>
    StartProfilesStatusField: Boolean;
    /// <summary>Befehl „TODOs des Projekts“ (#68, Atlas.TodoList); aus = der Befehl verschwindet.</summary>
    TodoList: Boolean;
    /// <summary>Befehl „Baseline des Projekts aktualisieren“ (#97, Atlas.UpdateBaseline) in der Befehlspalette;
    /// aus = der Befehl und sein Tipp verschwinden. Die Baseline selbst wirkt weiter.</summary>
    BaselineUpdate: Boolean;
    /// <summary>Befehl „Metrikbericht des Projekts“ (#66, Atlas.MetricsReport) in der Befehlspalette; aus = der
    /// Befehl verschwindet. Die Zusammenfassung nach dem Build hängt an der Willkommensseite.</summary>
    MetricsReport: Boolean;
    /// <summary>Befehle „Eigenschaftsregeln anwenden“ (#309) für Formular, Projekt und Projektgruppe in der
    /// Befehlspalette; aus = die Befehle verschwinden. Regel dfm-property und Schnellkorrektur bleiben.</summary>
    DfmPropertyRules: Boolean;
    /// <summary>Projektdatei .atlas lesen (#486): Einstellungen für alle im Team aus dem Repository, Vorrang vor
    /// den persönlichen; dazu der Befehl „Projektdatei .atlas öffnen“ (Atlas.TeamFile) mit Tipp. Aus = nur die
    /// persönlichen Einstellungen gelten, Befehl und Tipp verschwinden.</summary>
    TeamFile: Boolean;
    /// <summary>Die Editor-Kürzel auch belegen, wenn die IDE oder eine andere Erweiterung sie nutzt.</summary>
    EditorKeysPriority: Boolean;
    /// <summary>Schnellbefehle mit „/“ nach Enter und „///“-Gerüste beim Server auslösen (#399).</summary>
    SlashCommands: Boolean;
    /// <summary>Erzeugen-Menü (#719, keys.generateMenu): Alt+Einfg, Kontextmenü und Befehlspalette; aus = die Funktion
    /// ruht und das Kürzel bleibt frei.</summary>
    GenerateMenu: Boolean;
    /// <summary>Tastenkürzel des Erzeugen-Menüs (#719, keys.generateMenu.key; TShortCut, 0 = keins; Vorgabe Alt+Einfg).
    /// </summary>
    GenerateMenuKey: Integer;
    /// <summary>Gruppen in ihrer Reihenfolge (#719, keys.generateMenu.groups): generate, surround, templates,
    /// kommagetrennt; fehlt eine, fehlt sie im Menü.</summary>
    GenerateMenuGroups: string;
    /// <summary>Ausgeblendete Einträge (#719, keys.generateMenu.hidden): Kennungen wie slash:json oder Namen wie /json,
    /// tryf; kommagetrennt.</summary>
    GenerateMenuHidden: string;
    /// <summary>Zuletzt gewählte Einträge oben (#719, keys.generateMenu.recentFirst).</summary>
    GenerateMenuRecentFirst: Boolean;
    /// <summary>Befehlsnamen (/name) rechts in der Zeile (#719, keys.generateMenu.showCommandNames).</summary>
    GenerateMenuShowCommandNames: Boolean;
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
    /// <summary>XMLDoc in Tooltip und Detailpanel beim Öffnen (#770, hints.xmlDocExpand in settings.json):
    /// collapsed, last (wie zuletzt), expanded. Ersetzt XmlDocFull (1 = expanded, 0 = collapsed).</summary>
    XmlDocExpand: string;
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
    /// <summary>Menüeintrag „Prozesse am Projekt…“ (#62, diagnostics.processes): Index-Cache, Sperre und
    /// angemeldete LSP- und MCP-Prozesse; Vorgabe an.</summary>
    DiagnosticsProcesses: Boolean;
    /// <summary>Architekturübersicht (#1118, architecture.enabled in settings.json): Fenster „Atlas-Architektur“,
    /// Bericht und get_architecture; Vorgabe an.</summary>
    ArchitectureEnabled: Boolean;
    /// <summary>Umfang der Übersicht (architecture.scope): 'project' oder 'projectGroup' (Vorgabe).</summary>
    ArchitectureScope: string;
    /// <summary>Bibliotheks-Units (RTL, VCL, Fremdbibliotheken) mitzählen (architecture.includeLibraryUnits).
    /// </summary>
    ArchitectureIncludeLibraryUnits: Boolean;
    /// <summary>So viele zentrale Units (architecture.centralUnits, 5–100, Vorgabe 15).</summary>
    ArchitectureCentralUnits: Integer;
    /// <summary>Zustand: Das Fenster „Atlas-Architektur“ wurde einmal rechts neben die Projektverwaltung
    /// gelegt (ui.architectureWindowPlaced); danach gilt die Lage aus dem Desktop der IDE.</summary>
    ArchitectureWindowPlaced: Boolean;
    /// <summary>Befehl „Weg zwischen Symbolen…“ mit Menü- und Kontextmenüeintrag (#1117, navigation.symbolPath in
    /// settings.json); Vorgabe an.</summary>
    SymbolPath: Boolean;
    /// <summary>Hauptschalter der experimentellen Funktionen (#834, experimental.enabled, liegt in settings.json):
    /// aus = keine Einstellung mit x-experimental wirkt, auch wenn sie an ist; Vorgabe aus.</summary>
    ExperimentalEnabled: Boolean;
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
    /// <summary>Langsamer Start ab dieser Zeit bis zur freien Nachrichtenschleife: Atlas nennt seine Startanteile
    /// im Meldungsfenster; kein Absturz, abgesichert startet Atlas deshalb nicht (safeMode.startupTimeoutMs,
    /// Bericht N4).</summary>
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
    /// <summary>Abschnitte der Vorschau einklappen, wenn sie nicht passen (#876,
    /// unitSearch.preview.autoCollapse); Vorgabe an.</summary>
    UnitSearchPreviewAutoCollapse: Boolean;
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
    /// <summary>Datei und Symbol schnell öffnen (#503, quickOpen.enabled): Fenster mit Präfixen @, #, :.</summary>
    QuickOpen: Boolean;
    /// <summary>Auch die Quellen von RTL/VCL ($(BDS)\source) auflisten (#503, quickOpen.librarySources).</summary>
    QuickOpenLibrary: Boolean;
    /// <summary>Kürzel für „Schnell öffnen“ (#503, keys.quickOpen, TShortCut, 0 = keins); Vorgabe Strg+P.</summary>
    QuickOpenKey: Integer;
    /// <summary>Navigationsverlauf über Dateien (#504, navHistory.enabled): Sprünge und Bearbeitungsstellen
    /// merken, Zurück/Vor, letzte Bearbeitungsstelle, Liste.</summary>
    NavHistory: Boolean;
    /// <summary>Kürzel „Zurück“ (#504, keys.navBack, TShortCut, 0 = keins); Vorgabe Alt+Links.</summary>
    NavBackKey: Integer;
    /// <summary>Kürzel „Vor“ (#504, keys.navForward); Vorgabe Alt+Rechts.</summary>
    NavForwardKey: Integer;
    /// <summary>Kürzel „Letzte Bearbeitungsstelle“ (#504, keys.lastEdit); Vorgabe Strg+Alt+Q.</summary>
    LastEditKey: Integer;
    /// <summary>Definition und Referenzen einblenden (#505, peek.enabled).</summary>
    Peek: Boolean;
    /// <summary>Höhe des Peek-Fensters in Editorzeilen (#505, peek.heightLines), MinPeekLines bis MaxPeekLines.</summary>
    PeekHeightLines: Integer;
    /// <summary>Bei Routinen auch die Implementierung zeigen (#505, peek.showImplementation).</summary>
    PeekShowImplementation: Boolean;
    /// <summary>Kürzel „Definition einblenden“ (#505, keys.peekDefinition); Vorgabe Alt+F12.</summary>
    PeekDefinitionKey: Integer;
    /// <summary>Kürzel „Referenzen einblenden“ (#505, keys.peekReferences); Vorgabe Umschalt+Alt+F12.</summary>
    PeekReferencesKey: Integer;
    /// <summary>Fenster „Gliederung“ (#537, outline.enabled).</summary>
    Outline: Boolean;
    /// <summary>Gliederung alphabetisch sortieren (#537, outline.alphabetical).</summary>
    OutlineAlphabetical: Boolean;
    /// <summary>Eintrag am Cursor hervorheben (#537, outline.followCursor).</summary>
    OutlineFollowCursor: Boolean;
    /// <summary>Bedingung des aktiven {$IFDEF}-Zweigs hinter dem Eintrag (#845, outline.conditions).</summary>
    OutlineConditions: Boolean;
    /// <summary>Brotkrumenleiste über dem Editor (#590, editor.breadcrumbs).</summary>
    Breadcrumbs: Boolean;
    /// <summary>Unit-Namen als erstes Glied (#590, editor.breadcrumbsShowUnit).</summary>
    BreadcrumbsShowUnit: Boolean;
    /// <summary>Brotkrumenleiste in den Farben der IDE-Werkzeugleisten statt der Atlas-Palette
    /// (editor.breadcrumbsIdeColors).</summary>
    BreadcrumbsIdeColors: Boolean;
    /// <summary>Navigationsleiste der IDE („Typ suchen“/„Methode suchen“) ausblenden, solange die
    /// Brotkrumenleiste an ist (editor.breadcrumbsHideIdeToolbar).</summary>
    BreadcrumbsHideIdeToolbar: Boolean;
    /// <summary>Atlas-Editorleiste mit Symbolen über dem Editor (#1101, editor.toolbar); Hauptschalter.</summary>
    EditorToolbar: Boolean;
    /// <summary>Lage zur Brotkrumenleiste: belowBreadcrumbs, aboveBreadcrumbs oder inBreadcrumbs (#1101,
    /// editor.toolbar.position).</summary>
    EditorToolbarPosition: string;
    /// <summary>Knöpfe in Reihenfolge: Befehlskennungen, durch Komma getrennt, „|“ = Trennstrich (#1101,
    /// editor.toolbar.items); leer = keine Knöpfe.</summary>
    EditorToolbarItems: string;
    /// <summary>Knopf „Zurück zu Zeile …“ nach Abschnittssprüngen (#1101, editor.toolbar.returnButton).</summary>
    EditorToolbarReturnButton: Boolean;
    /// <summary>Text neben den Symbolen (#1101, editor.toolbar.labels).</summary>
    EditorToolbarLabels: Boolean;
    /// <summary>Schnelle Lesezeichen, nummeriert und unnummeriert (#1104, bookmarks.quick); Hauptschalter.</summary>
    QuickBookmarks: Boolean;
    /// <summary>Spalte links der Zeilennummern mit den Markern (#1104, bookmarks.quick.gutter).</summary>
    QuickBookmarksGutter: Boolean;
    /// <summary>Linksklick in die Spalte setzt und entfernt Lesezeichen (#1104, bookmarks.quick.gutterClick).
    /// </summary>
    QuickBookmarksGutterClick: Boolean;
    /// <summary>Tasten für Nummern 1–9 von der IDE übernehmen (#1104, bookmarks.quick.numberedKeys).</summary>
    QuickBookmarksNumberedKeys: Boolean;
    /// <summary>Taste für unnummerierte Lesezeichen (#1104, bookmarks.quick.key); 0 = keine.</summary>
    QuickBookmarkKey: Integer;
    /// <summary>Vorrang für QuickBookmarkKey vor der Faltung der IDE (#1104, bookmarks.quick.keyPriority).</summary>
    QuickBookmarkKeyPriority: Boolean;
    /// <summary>Wartezeit in ms auf den zweiten Faltungsakkordteil, 0 bis MaxQuickChordWait; 0 = die Taste bleibt
    /// bei der IDE (#1104, bookmarks.quick.chordWait).</summary>
    QuickBookmarkChordWait: Integer;
    /// <summary>Taste für „Lesezeichen 1 setzen“; 2–9 mit denselben Umschalttasten (#1104,
    /// bookmarks.quick.setKey); 0 = keine.</summary>
    QuickBookmarkSetKey: Integer;
    /// <summary>Vorrang vor „Lesezeichen umschalten“ der IDE (#1104, bookmarks.quick.setKeyPriority).</summary>
    QuickBookmarkSetKeyPriority: Boolean;
    /// <summary>Taste für „Zu Lesezeichen 1 springen“; 2–9 mit denselben Umschalttasten (#1104,
    /// bookmarks.quick.jumpKey); 0 = keine.</summary>
    QuickBookmarkJumpKey: Integer;
    /// <summary>Vorrang vor „Zu Lesezeichen springen“ der IDE (#1104, bookmarks.quick.jumpKeyPriority).</summary>
    QuickBookmarkJumpKeyPriority: Boolean;
    /// <summary>Sprungbereich von Strg+1…9: project oder file (#1104, bookmarks.quick.scope).</summary>
    QuickBookmarksScope: string;
    /// <summary>Vorhandene IDE-Lesezeichen 1–9 übernehmen und dort entfernen (#1104, bookmarks.quick.importIde).
    /// </summary>
    QuickBookmarksImportIde: Boolean;
    /// <summary>Taste „Nächstes Lesezeichen“ (#1104, keys.nextBookmark); 0 = keine.</summary>
    NextBookmarkKey: Integer;
    /// <summary>Taste „Voriges Lesezeichen“ (#1104, keys.previousBookmark); 0 = keine.</summary>
    PreviousBookmarkKey: Integer;
    /// <summary>Mitlaufender Kopf (#506, editor.stickyScroll, experimentell).</summary>
    StickyScroll: Boolean;
    /// <summary>Höchstzahl seiner Zeilen, MinStickyLines bis MaxStickyLines (#506,
    /// editor.stickyScrollMaxLines).</summary>
    StickyScrollMaxLines: Integer;
    /// <summary>Minimap neben der Scrollleiste (#873, editor.minimap, experimentell).</summary>
    Minimap: Boolean;
    /// <summary>Darstellung: blocks oder characters (#873, editor.minimap.render).</summary>
    MinimapRender: string;
    /// <summary>Breite in Pixeln bei 96 DPI, MinMinimapWidth bis MaxMinimapWidth (#873).</summary>
    MinimapWidth: Integer;
    /// <summary>Maßstab 1 bis 3, Pixel je Zeile = 2 × Maßstab (#873).</summary>
    MinimapScale: Integer;
    /// <summary>Höchste gezeigte Spalte (#873).</summary>
    MinimapMaxColumn: Integer;
    /// <summary>Seite: right oder left (#873).</summary>
    MinimapSide: string;
    /// <summary>Schieber: always oder mouseover (#873).</summary>
    MinimapShowSlider: string;
    /// <summary>Überschriften für Klassen und Methoden (#873).</summary>
    MinimapSectionHeaders: Boolean;
    /// <summary>Aktuelle Methode hinterlegen (#873).</summary>
    MinimapHighlightMethod: Boolean;
    /// <summary>Marken zeigen: Fehler, Suchtreffer, Git-Änderungen (#873).</summary>
    MinimapMarkers: Boolean;
    /// <summary>Klick springt an die Stelle; sonst scrollt er nur (#873).</summary>
    MinimapClickJumps: Boolean;
    /// <summary>Hinweis „IDE-Minimap ist auch sichtbar“ schon gezeigt (#873, interner Zustand).</summary>
    MinimapNoticeShown: Boolean;
    /// <summary>Kürzel „Brotkrumenleiste“ (#590, keys.breadcrumbs); Vorgabe Strg+Umschalt+Punkt.</summary>
    BreadcrumbsKey: Integer;
    /// <summary>Änderungsmarken in der Rinne (#507, editor.gitGutter).</summary>
    GitGutter: Boolean;
    /// <summary>Zeilenhistorie am Ende der Cursorzeile (#507, editor.gitBlame).</summary>
    GitBlame: Boolean;
    /// <summary>Atlas-Spalte in der Zeilenleiste (#768, editor.gutterColumn).</summary>
    GutterColumn: Boolean;
    /// <summary>Problemsymbole in der Spalte (#768, editor.gutterColumn.problems).</summary>
    GutterColumnProblems: Boolean;
    /// <summary>Glühbirne für Code-Aktionen der Cursorzeile (#768, editor.gutterColumn.codeActions).</summary>
    GutterColumnCodeActions: Boolean;
    /// <summary>„überschreibt“/„wird überschrieben“ an Methoden (#768, editor.gutterColumn.overrides).</summary>
    GutterColumnOverrides: Boolean;
    /// <summary>Gleichen Text wie die Markierung hervorheben (#709, highlight.selectionMatches).</summary>
    SelectionMatches: Boolean;
    /// <summary>Mindestlänge der Markierung, MinMinLength bis MaxMinLength von TAtlasSelectionMatches (#709).
    /// </summary>
    SelectionMatchesMinLength: Integer;
    /// <summary>Groß-/Kleinschreibung beachten (#709).</summary>
    SelectionMatchesCaseSensitive: Boolean;
    /// <summary>Nur ganze Wörter (#709).</summary>
    SelectionMatchesWholeWord: Boolean;
    /// <summary>F3/Umschalt+F3 springt zwischen den Treffern, solange die Markierung steht (#709).</summary>
    SelectionMatchesNavigateF3: Boolean;
    /// <summary>Höchstzahl der Treffer (#709).</summary>
    SelectionMatchesMaxMatches: Integer;
    /// <summary>Blockkommentar umschalten (#703, keys.toggleBlockComment); aus = Kürzel frei.</summary>
    ToggleBlockComment: Boolean;
    /// <summary>Kürzel „Blockkommentar umschalten“ (#703); Vorgabe Umschalt+Alt+A.</summary>
    ToggleBlockCommentKey: Integer;
    /// <summary>Bevorzugte Form: "braces" ({ }) oder "parens" ((* *)) (#703).</summary>
    ToggleBlockCommentStyle: string;
    /// <summary>Wenn } und *) vorkommen: "lineComments" (// je Zeile) oder "refuse" (#703).</summary>
    ToggleBlockCommentFallback: string;
    /// <summary>Mehrzeilig: Kommentarzeichen in eigene Zeilen (#703).</summary>
    ToggleBlockCommentOwnLines: Boolean;
    /// <summary>Ohne Markierung: "statement" (Anweisung) oder "line" (Zeile) (#703).</summary>
    ToggleBlockCommentWithoutSelection: string;
    /// <summary>Neue Zeile ober- oder unterhalb (#700, keys.newLineAround); aus = Tasten frei.</summary>
    NewLineAround: Boolean;
    /// <summary>Kürzel „Neue Zeile darunter“ (#700); Vorgabe Umschalt+Enter.</summary>
    NewLineBelowKey: Integer;
    /// <summary>Kürzel „Neue Zeile darüber“ (#700); Vorgabe Strg+Alt+Enter.</summary>
    NewLineAboveKey: Integer;
    /// <summary>Mehrzeilige Anweisungen als Ganzes: Bezug ist ihr Ende bzw. Anfang (#700).</summary>
    NewLineAroundStatementAware: Boolean;
    /// <summary>Umschließung entfernen (#657, keys.unwrap): Kürzel und Liste; aus = Kürzel frei, kein
    /// Menüeintrag.</summary>
    Unwrap: Boolean;
    /// <summary>Kürzel „Umschließung entfernen“ (#657); Vorgabe Strg+Umschalt+Entf.</summary>
    UnwrapKey: Integer;
    /// <summary>Kürzel „Nächste Änderung“ (#507, keys.nextChange); Vorgabe Strg+Alt+Bild↓.</summary>
    NextChangeKey: Integer;
    /// <summary>Kürzel „Vorherige Änderung“ (#507, keys.previousChange); Vorgabe Strg+Alt+Bild↑.</summary>
    PreviousChangeKey: Integer;
    /// <summary>Übersichtsleiste an der Scrollleiste (#519, editor.overviewRuler).</summary>
    OverviewRuler: Boolean;
    /// <summary>Arten der Übersichtsleiste, kommagetrennt (#519, editor.overviewRulerKinds); siehe
    /// TAtlasOverviewKindNames.</summary>
    OverviewRulerKinds: string;
    /// <summary>Sprung zum Gegenstück (#635, keys.jumpToMatch).</summary>
    JumpToMatch: Boolean;
    /// <summary>Kürzel „Zum Gegenstück springen“ (#635, keys.jumpToMatchShortcut); Vorgabe Strg+Ü.</summary>
    JumpToMatchKey: Integer;
    /// <summary>Kürzel „Bis zum Gegenstück markieren“ (#635, keys.jumpToMatchSelect); Vorgabe Strg+Umschalt+Ü.</summary>
    JumpToMatchSelectKey: Integer;
    /// <summary>Zeilen und Methoden verschieben und duplizieren (#634, keys.moveLines).</summary>
    MoveLines: Boolean;
    /// <summary>Kürzel „Zeilen nach oben verschieben“ (#634, keys.moveLinesUp); Vorgabe Alt+↑.</summary>
    MoveLinesUpKey: Integer;
    /// <summary>Kürzel „Zeilen nach unten verschieben“ (#634, keys.moveLinesDown); Vorgabe Alt+↓.</summary>
    MoveLinesDownKey: Integer;
    /// <summary>Kürzel „Zeilen darüber duplizieren“ (#634, keys.duplicateLinesUp); Vorgabe Umschalt+Alt+↑.</summary>
    DuplicateLinesUpKey: Integer;
    /// <summary>Kürzel „Zeilen darunter duplizieren“ (#634, keys.duplicateLinesDown); Vorgabe Umschalt+Alt+↓.
    /// </summary>
    DuplicateLinesDownKey: Integer;
    /// <summary>Kommentar beim Enter fortsetzen (#696, editor.continueComments).</summary>
    ContinueComments: Boolean;
    /// <summary>Auch //-Zeilen fortsetzen, nicht nur /// (#696, editor.continueComments.lineComments).</summary>
    ContinueCommentsLineComments: Boolean;
    /// <summary>Aufzählungen fortsetzen und hochzählen (#696, editor.continueComments.lists).</summary>
    ContinueCommentsLists: Boolean;
    /// <summary>Präfix in Blockkommentaren, etwa ' * '; leer = nur einrücken (#696,
    /// editor.continueComments.blockPrefix).</summary>
    ContinueCommentsBlockPrefix: string;
    /// <summary>Markierung beim Tippen eines öffnenden Zeichens umschließen (#672, editor.wrapSelection).</summary>
    WrapSelection: Boolean;
    /// <summary>Zeichen, die umschließen, aus ([{'&lt; (#672, editor.wrapSelection.chars).</summary>
    WrapSelectionChars: string;
    /// <summary>Anweisung vervollständigen (#697, editor.completeStatement).</summary>
    CompleteStatement: Boolean;
    /// <summary>Kürzel „Anweisung vervollständigen“ (#697, keys.completeStatement); Vorgabe Strg+Umschalt+Enter.
    /// </summary>
    CompleteStatementKey: Integer;
    /// <summary>begin/end ergänzen: BeginEndAlways, BeginEndMultiLine, BeginEndNever (#697,
    /// editor.completeStatement.beginEnd).</summary>
    CompleteStatementBeginEnd: string;
    /// <summary>Gerüst nach try: TryKindFinally, TryKindExcept, TryKindAsk (#697, editor.completeStatement.tryKind).
    /// </summary>
    CompleteStatementTryKind: string;
    /// <summary>Methodenrumpf anlegen (#697, editor.completeStatement.methodBody).</summary>
    CompleteStatementMethodBody: Boolean;
    /// <summary>Befehl „Formatieren“ für Datei oder Auswahl (#43, editor.format).</summary>
    FormatCode: Boolean;
    /// <summary>Kürzel „Formatieren“ (#43, keys.format); Vorgabe Strg+Umschalt+Alt+F, weil Strg+D die
    /// Mehrfachmarken haben und RAD Studio 13 keinen eigenen Formatierer mehr hat.</summary>
    FormatCodeKey: Integer;
    /// <summary>Nächste Zeile eines erkannten Musters als Schattentext vorschlagen (#671, editor.continuePattern).
    /// </summary>
    ContinuePattern: Boolean;
    /// <summary>Mindestzahl gleichförmiger Zeilen, MinPatternLines bis MaxPatternLines (#671,
    /// editor.continuePattern.minLines).</summary>
    ContinuePatternMinLines: Integer;
    /// <summary>Mehrere Einfügemarken (#589, editor.multiCursor, experimentell).</summary>
    MultiCursor: Boolean;
    /// <summary>Lokale Bezeichner beim Tippen mitziehen (#658, editor.linkedEditing, experimentell).</summary>
    LinkedEditing: Boolean;
    /// <summary>Einfügen mit uses-Ergänzung (#515, editor.smartPaste, experimentell): off, uses, indent, both.
    /// </summary>
    SmartPaste: string;
    /// <summary>MultiCursorModifierAlt oder MultiCursorModifierCtrl (#589, editor.multiCursorModifier).</summary>
    MultiCursorModifier: string;
    /// <summary>Kürzel der Mehrfachmarken (#589, keys.multiCursor.*): nächstes Vorkommen (Strg+D), Überspringen
    /// (zweite Taste nach Strg+K, Vorgabe Strg+D), Marken an den Zeilenenden (Alt+Umschalt+I), Marke darüber
    /// bzw. darunter (Strg+Alt+↑/↓).</summary>
    MultiCursorNextKey: Integer;
    MultiCursorSkipKey: Integer;
    MultiCursorLineEndsKey: Integer;
    MultiCursorAboveKey: Integer;
    MultiCursorBelowKey: Integer;
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
    /// <summary>Karte „Projekt für Atlas einrichten“ und Befehl Atlas.ProjectSetup (#759,
    /// welcomePage.projectSetup); aus = kein Bereich, auch keine Knöpfe „Neu mit Atlas“.</summary>
    WelcomePageProjectSetup: Boolean;
    /// <summary>Knöpfe „Neu mit Atlas“ (Unit, Formular, Testklasse) unter der Karte (#759,
    /// welcomePage.newFromTemplate).</summary>
    WelcomePageNewFromTemplate: Boolean;
    /// <summary>Bereich „Weiterarbeiten“ (#755, welcomePage.continue): Arbeitsstände merken und fortsetzen.
    /// </summary>
    WelcomePageContinue: Boolean;
    /// <summary>Anzahl der Arbeitsstände (#755, welcomePage.continue.count, 1–20).</summary>
    WelcomePageContinueCount: Integer;
    /// <summary>„Neu seit deinem letzten Öffnen“: eingehende Commits (#755, welcomePage.continue.incoming).</summary>
    WelcomePageContinueIncoming: Boolean;
    /// <summary>Vor dem Anzeigen im Hintergrund fetch ausführen (#755, welcomePage.continue.fetch).</summary>
    WelcomePageContinueFetch: Boolean;
    /// <summary>Reiter „Gemerkt“ mit Notizen, Lesezeichen und Favoriten (#755, welcomePage.saved).</summary>
    WelcomePageSaved: Boolean;
    /// <summary>Bereich „Projektverlauf“ (#758, welcomePage.trends): Messpunkte je Build mitschreiben und als
    /// Linien zeigen; aus = kein Bereich, nichts wird mitgeschrieben.</summary>
    WelcomePageTrends: Boolean;
    /// <summary>Gespeicherte Builds je Projekt (#758, welcomePage.trends.points, 2–100).</summary>
    WelcomePageTrendsPoints: Integer;
    /// <summary>Gezeigte Reihen (#758, welcomePage.trends.series): Namen durch Komma getrennt, in der Reihenfolge
    /// warnings, ruleHits, todos, duration, methodLength; '' = keine.</summary>
    WelcomePageTrendsSeries: string;
    /// <summary>Bereich „Testergebnisse“ (#763, welcomePage.tests): letzter Testlauf je Projekt mit den
    /// fehlgeschlagenen Tests; aus = kein Bereich.</summary>
    WelcomePageTests: Boolean;
    /// <summary>Höchstens so viele fehlgeschlagene Tests in der Liste (#763, welcomePage.tests.maxFailures, 1–50).
    /// </summary>
    WelcomePageTestsMaxFailures: Integer;
    /// <summary>Build-Server abfragen (#763, welcomePage.tests.ci); aus = kein Netzzugriff. Server und Job stehen
    /// in .atlas (ci.url, ci.job).</summary>
    WelcomePageTestsCi: Boolean;
    /// <summary>Anbieter, wenn .atlas keinen nennt (#763, welcomePage.tests.ci.provider): "jenkins".</summary>
    WelcomePageTestsCiProvider: string;
    /// <summary>Höchstens alle so viele Minuten fragen (#763, welcomePage.tests.ci.intervalMinutes, 1–1440).
    /// </summary>
    WelcomePageTestsCiIntervalMinutes: Integer;
    /// <summary>Hinweis in der Benachrichtigungszentrale, wenn der Build auf dem Server rot wird (#763,
    /// welcomePage.tests.ci.notify).</summary>
    WelcomePageTestsCiNotify: Boolean;
    /// <summary>Schnellaktionen je Projekt in „Projekte“ und „Weiterarbeiten“ (#764, welcomePage.quickActions):
    /// Knöpfe in der Zeile unter der Maus bzw. mit dem Fokus; aus = keine Knöpfe, keine Tasten.</summary>
    WelcomePageQuickActions: Boolean;
    /// <summary>Gezeigte Knöpfe (#764, welcomePage.quickActions.items): Namen durch Komma getrennt, in der
    /// Reihenfolge build, tests, run, pull, folder, console; '' = keiner.</summary>
    WelcomePageQuickActionsItems: string;
    /// <summary>Programm für „Konsole“ (#764, welcomePage.quickActions.console): wt.exe (Vorgabe), cmd.exe,
    /// powershell.exe, pwsh.exe oder ein anderes; ohne Windows-Terminal nimmt Atlas cmd.exe.</summary>
    WelcomePageQuickActionsConsole: string;
    /// <summary>Taste für „Öffnen und bauen“ bzw. „Tests“ in der Zeile mit dem Fokus (#764, TShortCut; 0 = keine).
    /// </summary>
    WelcomePageQuickActionsBuildKey: Integer;
    WelcomePageQuickActionsTestKey: Integer;
    /// <summary>Befehl „Zugang zum Build-Server hinterlegen …“ (#763, Atlas.CiLogin) in der Befehlspalette und im
    /// Kontextmenü des Bereichs; aus = der Befehl und sein Tipp verschwinden.</summary>
    CiLogin: Boolean;
    /// <summary>Bereich „Meine Issues“ (#765, welcomePage.issues): offene Issues aus dem Tracker der .atlas
    /// (Abschnitt tracker) mit „Beginnen“; aus = kein Bereich, keine Abfrage, kein Netzzugriff.</summary>
    WelcomePageIssues: Boolean;
    /// <summary>Tracker (#765, welcomePage.issues.tracker): '' = aus der .atlas, "github" oder "youtrack".</summary>
    WelcomePageIssuesTracker: string;
    /// <summary>Abfrage in der Sprache des Trackers (#765, welcomePage.issues.query); '' = Vorgabe des Trackers
    /// (GitHub "assignee:@me state:open", YouTrack "for: me #Unresolved").</summary>
    WelcomePageIssuesQuery: string;
    /// <summary>„Beginnen“ (#765, welcomePage.issues.start): "branch" legt einen Branch an und checkt ihn aus,
    /// "remember" merkt nur das Issue.</summary>
    WelcomePageIssuesStart: string;
    /// <summary>Muster für den Branch (#765, welcomePage.issues.branchPattern) mit {kennung}, {nummer},
    /// {kurztitel}; '' = Git feature/{kennung}-{kurztitel}, SVN {kennung}-{kurztitel} unter ^/branches/.</summary>
    WelcomePageIssuesBranchPattern: string;
    /// <summary>Basis des Branchs (#765, welcomePage.issues.branchBase); '' = Git main (sonst master), SVN trunk.
    /// </summary>
    WelcomePageIssuesBranchBase: string;
    /// <summary>Anfang der Commit-Nachricht, solange ein Issue aktiv ist (#765, welcomePage.issues.commitPattern);
    /// '' = aus. Nicht gekürzt: das Leerzeichen der Vorgabe "{kennung} " bleibt.</summary>
    WelcomePageIssuesCommitPattern: string;
    /// <summary>Befehl „Zugang zum Issue-Tracker hinterlegen …“ (#765, Atlas.TrackerLogin) in der Befehlspalette
    /// und im Kontextmenü des Bereichs; aus = der Befehl und sein Tipp verschwinden.</summary>
    TrackerLogin: Boolean;
    /// <summary>Willkommensseite frei anordnen (#767, welcomePage.customLayout): Bearbeitungsleiste „Seite
    /// anpassen“, Rechtsklick „Ausblenden“ und Befehl Atlas.WelcomeCustomize; aus = festes Atlas-Layout.</summary>
    WelcomePageCustomLayout: Boolean;
    /// <summary>Spalten des aktiven Layouts (#767, welcomePage.columns, 1–3).</summary>
    WelcomePageColumns: Integer;
    /// <summary>Gespeicherte Layouts als JSON-Liste (#767, welcomePage.layouts); '' = nur das Layout „Standard“
    /// mit den Plätzen von Atlas.</summary>
    WelcomePageLayouts: string;
    /// <summary>Name des aktiven Layouts (#767, welcomePage.activeLayout); unbekannt = das erste Layout.</summary>
    WelcomePageActiveLayout: string;
    /// <summary>Benachrichtigungszentrale (#601, notifications.enabled): Hinweise sammeln, Zähler im
    /// Atlas-Statusfeld, Liste und Befehl Atlas.Notifications; aus = jede Funktion zeigt ihre Einblendung wie
    /// vor #601, nichts wird gesammelt.</summary>
    Notifications: Boolean;
    /// <summary>Verhalten je Quelle (#601, notifications.sources): "quelle=verhalten" mit Komma getrennt,
    /// verhalten show, collect oder off; nicht genannte Quellen zeigen (show).</summary>
    NotificationsSources: string;
    /// <summary>Höchstens so viele Einträge in der Liste (#601, notifications.maxEntries, 10–1000).</summary>
    NotificationsMaxEntries: Integer;
    /// <summary>Tastenkürzel für die Liste der Benachrichtigungen (#601, TShortCut, 0 = keins); Vorrang wie die
    /// Editorbefehle (EditorKeysPriority, #399).</summary>
    NotificationsKey: Integer;
    /// <summary>Einstellungen exportieren, importieren und zurücksetzen (#723, settings.exportImport): Befehle der
    /// Befehlspalette, Knöpfe der Optionsseite und Kontextmenü „Auf Standard zurücksetzen“; aus = alles davon
    /// verschwindet samt Tipps.</summary>
    SettingsExportImport: Boolean;
    /// <summary>Geänderte Werte auf der Optionsseite mit einem Punkt vor der Beschriftung markieren (#723,
    /// settings.markModified).</summary>
    SettingsMarkModified: Boolean;
    /// <summary>Vor jedem Import und vor „Alles zurücksetzen“ den aktuellen Stand als Datei sichern (#723,
    /// settings.backupBeforeImport; %APPDATA%\Atlas\Backups).</summary>
    SettingsBackupBeforeImport: Boolean;
    /// <summary>Zugangsdaten beim Export (#723, settings.exportSecrets): "omit" lässt sie aus, "placeholder"
    /// schreibt den Platzhalter.</summary>
    SettingsExportSecrets: string;
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
  System.StrUtils,
  Atlas.Core.Generate.Contract,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.ReleaseGuard,
  Atlas.Core.Build.OpenBuild,
  Atlas.Core.Settings.OverviewKinds,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Settings.ToolbarItems;

const
  /// <summary>Reihen des Projektverlaufs (#758) wie TAtlasProjectSummaries.TrendKeys (Test prüft Gleichheit).</summary>
  TrendSeriesNames: array[0..4] of string = ('warnings', 'ruleHits', 'todos', 'duration', 'methodLength');
  /// <summary>Wie TAtlasListModes.ModeNames bzw. ScopeNames (#497); Settings darf Completion nicht einbinden
  /// (A-09), der Test prüft Gleichheit.</summary>
  CompletionListModeNames: array[0..2] of string = ('filter', 'all', 'rest');
  CompletionListScopeNames: array[0..1] of string = ('members', 'everywhere');

/// <summary>Bekannte Reihen aus AText (Komma, Semikolon, Leerzeichen; Groß-/Kleinschreibung egal) in fester
/// Reihenfolge, jede einmal.</summary>
const
  // Bekannte CI-Anbieter für welcomePage.tests.ci.provider (#763).
  CiProviders: array[0..0] of string = ('jenkins');

const
  /// <summary>Knöpfe der Schnellaktionen (#764) wie TAtlasWelcomeQuickActions.Names (Test prüft Gleichheit; die
  /// Einstellungen kennen die Willkommensseite nicht, A-09).</summary>
  QuickActionNames: array[0..5] of string = ('build', 'tests', 'run', 'pull', 'folder', 'console');
  QuickActionsDefaultConsole = 'wt.exe';

/// <summary>Bekannte Knöpfe aus AText (Komma, Semikolon, Leerzeichen; Groß-/Kleinschreibung egal) in fester
/// Reihenfolge, jeder einmal; '' = keiner.</summary>
function NormalizedQuickActionItems(const AText: string): string;
var
  Part: string;
  Index: Integer;
  Wanted: array[0..5] of Boolean;
begin
  for Index := Low(Wanted) to High(Wanted) do
    Wanted[Index] := False;
  for Part in AText.Split([',', ';', ' ']) do
    for Index := Low(QuickActionNames) to High(QuickActionNames) do
      if SameText(Trim(Part), QuickActionNames[Index]) then
        Wanted[Index] := True;
  Result := '';
  for Index := Low(QuickActionNames) to High(QuickActionNames) do
    if Wanted[Index] then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + QuickActionNames[Index];
    end;
end;

/// <summary>Programm für „Konsole“ getrimmt; leer = wt.exe.</summary>
function NormalizedQuickActionConsole(const AText: string): string;
begin
  Result := Trim(AText);
  if Result = '' then
    Result := QuickActionsDefaultConsole;
end;

/// <summary>Bekannter CI-Anbieter in Kleinbuchstaben; sonst die Vorgabe.</summary>
function NormalizedCiProvider(const AText: string): string;
var
  Name: string;
begin
  for Name in CiProviders do
    if SameText(Trim(AText), Name) then
      Exit(Name);
  Result := TAtlasPluginSettings.DefaultCiProvider;
end;

/// <summary>"github", "youtrack" oder '' (aus der .atlas).</summary>
function NormalizedIssuesTracker(const AText: string): string;
begin
  Result := LowerCase(Trim(AText));
  if (Result <> 'github') and (Result <> 'youtrack') then
    Result := '';
end;

function NormalizedIssuesStart(const AText: string): string;
begin
  if SameText(Trim(AText), TAtlasPluginSettings.IssuesStartRemember) then
    Result := TAtlasPluginSettings.IssuesStartRemember
  else
    Result := TAtlasPluginSettings.IssuesStartBranch;
end;

/// <summary>Präfix für Blockkommentare (#696): Steuerzeichen werden Leerzeichen, höchstens acht Zeichen; Leerraum
/// am Rand bleibt (' * ').</summary>
function NormalizedBlockPrefix(const AText: string): string;
var
  Index: Integer;
begin
  Result := Copy(AText, 1, 8);
  for Index := 1 to Length(Result) do
    if Ord(Result[Index]) < 32 then
      Result[Index] := ' ';
  // Nur Leerraum ist kein Präfix.
  if Trim(Result) = '' then
    Result := '';
end;

/// <summary>Ohne Zeilenumbrüche und Steuerzeichen, höchstens MaxIssuesText Zeichen; ATrim kürzt Leerraum am Rand.
/// </summary>
function NormalizedIssuesText(const AText: string; ATrim: Boolean): string;
var
  Index: Integer;
begin
  Result := AText;
  for Index := 1 to Length(Result) do
    if Ord(Result[Index]) < 32 then
      Result[Index] := ' ';
  if ATrim then
    Result := Trim(Result);
  if Length(Result) > TAtlasPluginSettings.MaxIssuesText then
    Result := Copy(Result, 1, TAtlasPluginSettings.MaxIssuesText);
end;

function NormalizedTrendSeries(const AText: string): string;
var
  Parts: TArray<string>;
  Part: string;
  Index: Integer;
  Wanted: array[0..4] of Boolean;
begin
  for Index := Low(Wanted) to High(Wanted) do
    Wanted[Index] := False;
  Parts := AText.Split([',', ';', ' ']);
  for Part in Parts do
    for Index := Low(TrendSeriesNames) to High(TrendSeriesNames) do
      if SameText(Trim(Part), TrendSeriesNames[Index]) then
        Wanted[Index] := True;
  Result := '';
  for Index := Low(TrendSeriesNames) to High(TrendSeriesNames) do
    if Wanted[Index] then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + TrendSeriesNames[Index];
    end;
end;

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
  Result.SelectionMarker := True;
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
  Result.CompletionVariantBranch := True;
  Result.CompletionListMode := CompletionListModeNames[0];
  Result.CompletionListScope := CompletionListScopeNames[0];
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
  Result.InlayTypeHints := True;
  Result.InlayDefineHints := True;
  Result.InlayCharHints := True;
  Result.BlockEndLabels := True;
  Result.BlockEndLabelsMinLines := 25;
  Result.DimUnusedUses := True;
  Result.RecursionMarkers := True;
  Result.RecursionMarkersDepth := 4;
  Result.Notes := True;
  Result.BookmarksNamed := True;
  Result.BookmarksShared := False;
  Result.BookmarkKey := $C04B; // Strg+Alt+K
  Result.HideElementKey := $40BE; // Strg+.
  Result.SearchReplaceIde := True;
  Result.SearchResultsInMessages := True;
  Result.SearchKey := $4046; // Strg+F
  Result.SearchNextKey := $72; // F3
  Result.SearchPreviousKey := $2072; // Umschalt+F3
  Result.SearchMethodKey := $E046; // Strg+Umschalt+Alt+F
  Result.ServerPath := '';
  Result.PairGuides := True;
  Result.PairOwners := True;
  Result.PairGuideWidth := 1;
  Result.PairGuideOpacity := 75;
  Result.PairColorsLight := '';
  Result.PairColorsDark := '';
  Result.Problems := True;
  Result.ProblemsList := False;
  Result.ProblemsWindow := True;
  Result.ProblemsWindowScope := 'group';
  Result.ProblemsWindowGroupBy := 'file';
  Result.ProblemsWindowColumns := '';
  Result.ProblemsWindowCompiler := False;
  Result.ProblemsWindowFollowCursor := True;
  Result.ProblemsWindowOpenFirst := True;
  Result.ProblemsWindowClosedUnits := 'dimmed';
  Result.ProblemsWindowShowCleanActive := True;
  Result.ProblemsCompilerMerge := 'merge';
  Result.ProblemsShowCompilerCode := True;
  Result.ProblemsWindowKey := $C050; // Strg+Alt+P
  Result.GotoInterfaceKey := 0;
  Result.GotoImplementationKey := 0;
  Result.ProblemsLive := True;
  Result.HoverProblemActions := True;
  Result.InlineDiagnostics := 'errors';
  Result.ProblemsStatusCounter := True;
  Result.NextProblemKey := $C077; // Strg+Alt+F8
  Result.PreviousProblemKey := $E077; // Strg+Alt+Umschalt+F8
  // Die Prüfung in der IDE zeigt deren Fortschritt; Standard ist die Prüfung des Servers mit dcc (compiler.onSave).
  Result.CheckOnSave := False;
  Result.CompileOnSave := False;
  Result.CheckOnSaveDelayMs := 2000;
  Result.CheckOnSaveMaxMs := 1500;
  Result.McpBuild := True;
  Result.BuildOnOpen := False;
  Result.BuildOnOpenKind := TAtlasOpenBuild.KindName(TAtlasCompileKind.Make);
  Result.BuildOnOpenScope := TAtlasOpenBuild.ScopeNames[TAtlasOpenBuildScope.All];
  Result.BuildOnOpenDelayMs := TAtlasOpenBuild.DefaultDelayMs;
  Result.BuildOnOpenExclude := '';
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
  Result.CodeLensMetrics := True;
  Result.Metrics := True;
  Result.CodeLensTests := True;
  Result.TestRun := True;
  Result.TestsAfterBuild := False;
  Result.TestsBuildFirst := True;
  Result.BuildZeroHints := False;
  Result.ReleaseGuard := True;
  Result.BuildGate := 'off';
  Result.ReleaseConfigs := TAtlasReleaseGuard.ReleaseConfiguration;
  Result.ReleaseChecks := TAtlasReleaseChecks.Defaults.ToText;
  Result.TestDebug := True;
  Result.TestBreakAtStart := True;
  Result.DebugHoverValues := True;
  Result.StartProfiles := True;
  Result.StartProfilesStatusField := True;
  Result.TodoList := True;
  Result.BaselineUpdate := True;
  Result.MetricsReport := True;
  Result.DfmPropertyRules := True;
  Result.TeamFile := True;
  Result.EditorKeysPriority := False;
  Result.SlashCommands := True;
  Result.GenerateMenu := True;
  Result.GenerateMenuKey := $802D; // Alt+Einfg
  Result.GenerateMenuGroups := 'generate,surround,templates';
  Result.GenerateMenuHidden := '';
  Result.GenerateMenuRecentFirst := True;
  Result.GenerateMenuShowCommandNames := True;
  Result.Snippets := True;
  Result.ImportIdeTemplates := True;
  // Wie die Vorgaben im Schema (atlas.schema.json, index).
  Result.IndexProjectGroup := True;
  Result.IndexSearchPaths := True;
  Result.IndexLibraryPaths := False;
  Result.IndexUsages := True;
  Result.MemoryBudgetMb := 768;
  Result.XmlDocExpand := 'last';
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
  Result.DiagnosticsProcesses := True;
  // Wie die Vorgaben im Schema (atlas.schema.json, architecture).
  Result.ArchitectureEnabled := True;
  Result.ArchitectureScope := 'projectGroup';
  Result.ArchitectureIncludeLibraryUnits := False;
  Result.ArchitectureCentralUnits := 15;
  Result.ArchitectureWindowPlaced := False;
  Result.SymbolPath := True;
  Result.ExperimentalEnabled := False;
  Result.SetupChecklist := True;
  Result.SetupChecklistSeen := False;
  Result.KeyOverview := True;
  Result.KeyStartupCheck := True;
  Result.ShortcutTips := True;
  Result.ShortcutTipsScope := 'all';
  Result.SafeAskAfterCrash := True;
  Result.SafeAutoAfterRepeatedCrash := True;
  Result.SafeStartupKey := 'shift';
  // Gemessen bis zur freien Nachrichtenschleife, mit Desktop, übrigen Packages und Projekt (#874).
  Result.SafeStartupTimeoutMs := 30000;
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
  Result.UnitSearchPreviewAutoCollapse := True;
  Result.UnitSearchMultiSelect := True;
  Result.UnitSearchActions := True;
  Result.UnitSearchActionsAddUses := True;
  Result.UnitSearchPathStyle := 'relative';
  Result.UnitSearchGroupBy := 'project';
  Result.UnitSearchDefaultScope := 'group';
  Result.UnitSearchKey := 0;
  Result.QuickOpen := True;
  Result.QuickOpenLibrary := False;
  Result.QuickOpenKey := $4050; // Strg+P
  Result.NavHistory := True;
  Result.NavBackKey := $8025; // Alt+Links
  Result.NavForwardKey := $8027; // Alt+Rechts
  Result.LastEditKey := $C051; // Strg+Alt+Q
  Result.Peek := True;
  Result.PeekHeightLines := 15;
  Result.PeekShowImplementation := True;
  Result.PeekDefinitionKey := $807B; // Alt+F12
  Result.PeekReferencesKey := $A07B; // Umschalt+Alt+F12
  Result.Outline := True;
  Result.OutlineAlphabetical := False;
  Result.OutlineFollowCursor := True;
  Result.OutlineConditions := True;
  Result.Breadcrumbs := True;
  Result.BreadcrumbsShowUnit := False;
  Result.BreadcrumbsIdeColors := True;
  Result.BreadcrumbsHideIdeToolbar := True;
  Result.EditorToolbar := True;
  Result.EditorToolbarPosition := 'belowBreadcrumbs';
  Result.EditorToolbarItems := TAtlasToolbarItems.DefaultText;
  Result.EditorToolbarReturnButton := True;
  Result.EditorToolbarLabels := False;
  Result.QuickBookmarks := True;
  Result.QuickBookmarksGutter := True;
  Result.QuickBookmarksGutterClick := True;
  Result.QuickBookmarksNumberedKeys := True;
  Result.QuickBookmarkKey := $604B; // Strg+Umschalt+K
  Result.QuickBookmarkKeyPriority := True;
  Result.QuickBookmarkChordWait := 800;
  Result.QuickBookmarkSetKey := $6031; // Strg+Umschalt+1
  Result.QuickBookmarkSetKeyPriority := True;
  Result.QuickBookmarkJumpKey := $4031; // Strg+1
  Result.QuickBookmarkJumpKeyPriority := True;
  Result.QuickBookmarksScope := 'project';
  Result.QuickBookmarksImportIde := True;
  Result.NextBookmarkKey := 0;
  Result.PreviousBookmarkKey := 0;
  Result.StickyScroll := False;
  Result.StickyScrollMaxLines := 3;
  Result.Minimap := False;
  Result.MinimapRender := 'blocks';
  Result.MinimapWidth := 120;
  Result.MinimapScale := 1;
  Result.MinimapMaxColumn := 120;
  Result.MinimapSide := 'right';
  Result.MinimapShowSlider := 'always';
  Result.MinimapSectionHeaders := True;
  Result.MinimapHighlightMethod := True;
  Result.MinimapMarkers := True;
  Result.MinimapClickJumps := True;
  Result.MinimapNoticeShown := False;
  Result.BreadcrumbsKey := $60BE; // Strg+Umschalt+.
  Result.GitGutter := True;
  Result.GitBlame := False;
  Result.GutterColumn := True;
  Result.GutterColumnProblems := True;
  Result.GutterColumnCodeActions := True;
  Result.GutterColumnOverrides := True;
  Result.SelectionMatches := True;
  Result.SelectionMatchesMinLength := 3;
  Result.SelectionMatchesCaseSensitive := False;
  Result.SelectionMatchesWholeWord := False;
  Result.SelectionMatchesNavigateF3 := True;
  Result.SelectionMatchesMaxMatches := 1000;
  Result.ToggleBlockComment := True;
  Result.ToggleBlockCommentKey := $A041; // Umschalt+Alt+A
  Result.ToggleBlockCommentStyle := 'braces';
  Result.ToggleBlockCommentFallback := 'lineComments';
  Result.ToggleBlockCommentOwnLines := False;
  Result.ToggleBlockCommentWithoutSelection := 'statement';
  Result.NewLineAround := True;
  Result.NewLineBelowKey := $200D; // Umschalt+Enter
  Result.NewLineAboveKey := $C00D; // Strg+Alt+Enter
  Result.NewLineAroundStatementAware := True;
  Result.Unwrap := True;
  Result.UnwrapKey := $602E; // Strg+Umschalt+Entf
  // Strg+Alt+↑/↓ springt in RAD Studio schon zwischen Methoden.
  Result.NextChangeKey := $C022; // Strg+Alt+Bild↓
  Result.PreviousChangeKey := $C021; // Strg+Alt+Bild↑
  Result.OverviewRuler := True;
  Result.OverviewRulerKinds := TAtlasOverviewKindNames.Text(TAtlasOverviewKindNames.All);
  Result.JumpToMatch := True;
  Result.JumpToMatchKey := $40BA; // Strg+Ü (VK_OEM_1 auf deutscher Tastatur)
  Result.JumpToMatchSelectKey := $60BA; // Strg+Umschalt+Ü
  Result.MoveLines := True;
  Result.MoveLinesUpKey := $8026; // Alt+↑
  Result.MoveLinesDownKey := $8028; // Alt+↓
  Result.DuplicateLinesUpKey := $A026; // Umschalt+Alt+↑
  Result.DuplicateLinesDownKey := $A028; // Umschalt+Alt+↓
  Result.ContinueComments := True;
  Result.ContinueCommentsLineComments := True;
  Result.ContinueCommentsLists := True;
  Result.ContinueCommentsBlockPrefix := '';
  Result.WrapSelection := True;
  Result.WrapSelectionChars := '([{''';
  Result.CompleteStatement := True;
  Result.CompleteStatementKey := $600D; // Strg+Umschalt+Enter
  Result.CompleteStatementBeginEnd := BeginEndMultiLine;
  Result.CompleteStatementTryKind := TryKindFinally;
  Result.CompleteStatementMethodBody := True;
  Result.FormatCode := True;
  // Strg+Umschalt+Alt+F hat die Suche in der Methode (#877).
  Result.FormatCodeKey := $E04C; // Strg+Umschalt+Alt+L
  Result.ContinuePattern := True;
  Result.ContinuePatternMinLines := 2;
  Result.MultiCursor := False;
  Result.LinkedEditing := False;
  Result.SmartPaste := 'off';
  Result.MultiCursorModifier := MultiCursorModifierAlt;
  Result.MultiCursorNextKey := $4044; // Strg+D
  Result.MultiCursorSkipKey := $4044; // Strg+K, Strg+D
  Result.MultiCursorLineEndsKey := $A049; // Alt+Umschalt+I
  Result.MultiCursorAboveKey := $C026; // Strg+Alt+↑
  Result.MultiCursorBelowKey := $C028; // Strg+Alt+↓
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
  Result.WelcomePageProjectSetup := True;
  Result.WelcomePageNewFromTemplate := True;
  Result.WelcomePageContinue := True;
  Result.WelcomePageContinueCount := 5;
  Result.WelcomePageTrends := True;
  Result.WelcomePageTrendsPoints := 30;
  Result.WelcomePageTrendsSeries := DefaultTrendSeries;
  Result.WelcomePageTests := True;
  Result.WelcomePageTestsMaxFailures := 5;
  Result.WelcomePageTestsCi := False;
  Result.WelcomePageTestsCiProvider := DefaultCiProvider;
  Result.WelcomePageTestsCiIntervalMinutes := 10;
  Result.WelcomePageTestsCiNotify := True;
  Result.CiLogin := True;
  Result.WelcomePageQuickActions := True;
  Result.WelcomePageQuickActionsItems := string.Join(',', QuickActionNames);
  Result.WelcomePageQuickActionsConsole := QuickActionsDefaultConsole;
  Result.WelcomePageQuickActionsBuildKey := $4042; // Strg+B
  Result.WelcomePageQuickActionsTestKey := $4054; // Strg+T
  Result.WelcomePageIssues := False;
  Result.WelcomePageIssuesTracker := '';
  Result.WelcomePageIssuesQuery := '';
  Result.WelcomePageIssuesStart := IssuesStartBranch;
  Result.WelcomePageIssuesBranchPattern := '';
  Result.WelcomePageIssuesBranchBase := '';
  Result.WelcomePageIssuesCommitPattern := DefaultIssuesCommitPattern;
  Result.TrackerLogin := True;
  Result.WelcomePageCustomLayout := True;
  Result.WelcomePageColumns := 2;
  Result.WelcomePageLayouts := '';
  Result.WelcomePageActiveLayout := DefaultWelcomeLayoutName;
  Result.WelcomePageContinueIncoming := True;
  Result.WelcomePageContinueFetch := False;
  Result.WelcomePageSaved := True;
  Result.Notifications := True;
  Result.NotificationsSources := '';
  Result.NotificationsMaxEntries := 200;
  Result.NotificationsKey := $E04E; // Strg+Umschalt+Alt+N
  Result.SettingsExportImport := True;
  Result.SettingsMarkModified := True;
  Result.SettingsBackupBeforeImport := True;
  Result.SettingsExportSecrets := 'omit';
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
  BuildOnOpenKind := TAtlasOpenBuild.KindName(TAtlasOpenBuild.KindOf(BuildOnOpenKind));
  CompletionListMode := Choice(CompletionListMode, CompletionListModeNames);
  CompletionListScope := Choice(CompletionListScope, CompletionListScopeNames);
  BuildOnOpenScope := TAtlasOpenBuild.ScopeNames[TAtlasOpenBuild.ScopeOf(BuildOnOpenScope)];
  BuildOnOpenDelayMs := EnsureRange(BuildOnOpenDelayMs, TAtlasOpenBuild.MinDelayMs, TAtlasOpenBuild.MaxDelayMs);
  BuildOnOpenExclude := TAtlasOpenBuild.NormalizedExclude(BuildOnOpenExclude);
  // Nach dem Speichern genau eins von beiden: Die Syntaxprüfung der IDE gewinnt.
  if CheckOnSave then
    CompileOnSave := False;
  XmlDocMaxLines := EnsureRange(XmlDocMaxLines, 0, MaxXmlDocLines);
  XmlDocExpand := Choice(XmlDocExpand, ['last', 'collapsed', 'expanded']);
  BlockEndLabelsMinLines := EnsureRange(BlockEndLabelsMinLines, MinBlockEndLines, MaxBlockEndLines);
  RecursionMarkersDepth := EnsureRange(RecursionMarkersDepth, MinRecursionDepth, MaxRecursionDepth);
  ContinuePatternMinLines := EnsureRange(ContinuePatternMinLines, MinPatternLines, MaxPatternLines);
  OpenDelayMs := EnsureRange(OpenDelayMs, 0, MaxOpenDelay);
  MemoryBudgetMb := EnsureRange(MemoryBudgetMb, 0, MaxMemoryBudgetMb);
  ArchitectureScope := Choice(ArchitectureScope, ['projectGroup', 'project']);
  ArchitectureCentralUnits := EnsureRange(ArchitectureCentralUnits, 5, 100);
  // TShortCut ist ein Word.
  PaletteKey := EnsureRange(PaletteKey, 0, $FFFF);
  WelcomePageSearchKey := EnsureRange(WelcomePageSearchKey, 0, $FFFF);
  WelcomePageMaxProjects := EnsureRange(WelcomePageMaxProjects, MinWelcomeProjects, MaxWelcomeProjects);
  WelcomePageUnsavedMinAgeHours := EnsureRange(WelcomePageUnsavedMinAgeHours, MinUnsavedHours, MaxUnsavedHours);
  WelcomePageUnsavedWarnHours := EnsureRange(WelcomePageUnsavedWarnHours, MinUnsavedHours, MaxUnsavedHours);
  // Rot nie vor gelb.
  WelcomePageUnsavedAlertHours := EnsureRange(WelcomePageUnsavedAlertHours, WelcomePageUnsavedWarnHours,
    MaxUnsavedHours);
  WelcomePageContinueCount := EnsureRange(WelcomePageContinueCount, MinContinueCount, MaxContinueCount);
  WelcomePageTrendsPoints := EnsureRange(WelcomePageTrendsPoints, MinTrendPoints, MaxTrendPoints);
  WelcomePageTrendsSeries := NormalizedTrendSeries(WelcomePageTrendsSeries);
  WelcomePageTestsMaxFailures := EnsureRange(WelcomePageTestsMaxFailures, MinTestFailures, MaxTestFailures);
  WelcomePageTestsCiIntervalMinutes := EnsureRange(WelcomePageTestsCiIntervalMinutes, MinCiIntervalMinutes,
    MaxCiIntervalMinutes);
  WelcomePageTestsCiProvider := NormalizedCiProvider(WelcomePageTestsCiProvider);
  WelcomePageQuickActionsItems := NormalizedQuickActionItems(WelcomePageQuickActionsItems);
  WelcomePageQuickActionsConsole := NormalizedQuickActionConsole(WelcomePageQuickActionsConsole);
  WelcomePageQuickActionsBuildKey := EnsureRange(WelcomePageQuickActionsBuildKey, 0, $FFFF);
  WelcomePageQuickActionsTestKey := EnsureRange(WelcomePageQuickActionsTestKey, 0, $FFFF);
  WelcomePageIssuesTracker := NormalizedIssuesTracker(WelcomePageIssuesTracker);
  WelcomePageIssuesQuery := NormalizedIssuesText(WelcomePageIssuesQuery, True);
  WelcomePageIssuesStart := NormalizedIssuesStart(WelcomePageIssuesStart);
  WelcomePageIssuesBranchPattern := NormalizedIssuesText(WelcomePageIssuesBranchPattern, True);
  WelcomePageIssuesBranchBase := NormalizedIssuesText(WelcomePageIssuesBranchBase, True);
  // Leerraum am Ende gehört zum Muster ("{kennung} ").
  WelcomePageIssuesCommitPattern := NormalizedIssuesText(WelcomePageIssuesCommitPattern, False);
  WelcomePageColumns := EnsureRange(WelcomePageColumns, MinWelcomeColumns, MaxWelcomeColumns);
  WelcomePageLayouts := Trim(WelcomePageLayouts);
  WelcomePageActiveLayout := Trim(WelcomePageActiveLayout);
  if WelcomePageActiveLayout = '' then
    WelcomePageActiveLayout := DefaultWelcomeLayoutName;
  BuildGate := TAtlasReleaseGuard.GateNames[TAtlasReleaseGuard.GateOf(BuildGate)];
  ReleaseConfigs := TAtlasReleaseGuard.NormalizedConfigurations(ReleaseConfigs);
  ReleaseChecks := TAtlasReleaseChecks.Normalized(ReleaseChecks);
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
  QuickOpenKey := EnsureRange(QuickOpenKey, 0, $FFFF);
  NavBackKey := EnsureRange(NavBackKey, 0, $FFFF);
  NavForwardKey := EnsureRange(NavForwardKey, 0, $FFFF);
  LastEditKey := EnsureRange(LastEditKey, 0, $FFFF);
  PeekHeightLines := EnsureRange(PeekHeightLines, MinPeekLines, MaxPeekLines);
  StickyScrollMaxLines := EnsureRange(StickyScrollMaxLines, MinStickyLines, MaxStickyLines);
  SelectionMatchesMinLength := EnsureRange(SelectionMatchesMinLength, MinSelectionMatchLength,
    MaxSelectionMatchLength);
  SelectionMatchesMaxMatches := EnsureRange(SelectionMatchesMaxMatches, MinSelectionMatches, MaxSelectionMatches);
  ToggleBlockCommentKey := EnsureRange(ToggleBlockCommentKey, 0, $FFFF);
  ToggleBlockCommentStyle := Choice(ToggleBlockCommentStyle, ['braces', 'parens']);
  ToggleBlockCommentFallback := Choice(ToggleBlockCommentFallback, ['lineComments', 'refuse']);
  ToggleBlockCommentWithoutSelection := Choice(ToggleBlockCommentWithoutSelection, ['statement', 'line']);
  NewLineBelowKey := EnsureRange(NewLineBelowKey, 0, $FFFF);
  NewLineAboveKey := EnsureRange(NewLineAboveKey, 0, $FFFF);
  UnwrapKey := EnsureRange(UnwrapKey, 0, $FFFF);
  MinimapRender := Choice(MinimapRender, ['blocks', 'characters']);
  MinimapWidth := EnsureRange(MinimapWidth, MinMinimapWidth, MaxMinimapWidth);
  MinimapScale := EnsureRange(MinimapScale, MinMinimapScale, MaxMinimapScale);
  MinimapMaxColumn := EnsureRange(MinimapMaxColumn, MinMinimapColumn, MaxMinimapColumn);
  MinimapSide := Choice(MinimapSide, ['right', 'left']);
  MinimapShowSlider := Choice(MinimapShowSlider, ['always', 'mouseover']);
  PeekDefinitionKey := EnsureRange(PeekDefinitionKey, 0, $FFFF);
  PeekReferencesKey := EnsureRange(PeekReferencesKey, 0, $FFFF);
  BreadcrumbsKey := EnsureRange(BreadcrumbsKey, 0, $FFFF);
  EditorToolbarPosition := Choice(EditorToolbarPosition, ['belowBreadcrumbs', 'aboveBreadcrumbs', 'inBreadcrumbs']);
  EditorToolbarItems := TAtlasToolbarItems.Normalize(EditorToolbarItems);
  QuickBookmarkKey := EnsureRange(QuickBookmarkKey, 0, $FFFF);
  QuickBookmarkChordWait := EnsureRange(QuickBookmarkChordWait, 0, MaxQuickChordWait);
  QuickBookmarkSetKey := EnsureRange(QuickBookmarkSetKey, 0, $FFFF);
  QuickBookmarkJumpKey := EnsureRange(QuickBookmarkJumpKey, 0, $FFFF);
  QuickBookmarksScope := Choice(QuickBookmarksScope, AtlasQuickBookmarkScopes);
  NextBookmarkKey := EnsureRange(NextBookmarkKey, 0, $FFFF);
  PreviousBookmarkKey := EnsureRange(PreviousBookmarkKey, 0, $FFFF);
  NextChangeKey := EnsureRange(NextChangeKey, 0, $FFFF);
  PreviousChangeKey := EnsureRange(PreviousChangeKey, 0, $FFFF);
  OverviewRulerKinds := TAtlasOverviewKindNames.Normalize(OverviewRulerKinds);
  JumpToMatchKey := EnsureRange(JumpToMatchKey, 0, $FFFF);
  JumpToMatchSelectKey := EnsureRange(JumpToMatchSelectKey, 0, $FFFF);
  MoveLinesUpKey := EnsureRange(MoveLinesUpKey, 0, $FFFF);
  MoveLinesDownKey := EnsureRange(MoveLinesDownKey, 0, $FFFF);
  DuplicateLinesUpKey := EnsureRange(DuplicateLinesUpKey, 0, $FFFF);
  DuplicateLinesDownKey := EnsureRange(DuplicateLinesDownKey, 0, $FFFF);
  ContinueCommentsBlockPrefix := NormalizedBlockPrefix(ContinueCommentsBlockPrefix);
  CompleteStatementKey := EnsureRange(CompleteStatementKey, 0, $FFFF);
  FormatCodeKey := EnsureRange(FormatCodeKey, 0, $FFFF);
  CompleteStatementBeginEnd := Choice(CompleteStatementBeginEnd, [BeginEndMultiLine, BeginEndAlways, BeginEndNever]);
  CompleteStatementTryKind := Choice(CompleteStatementTryKind, [TryKindFinally, TryKindExcept, TryKindAsk]);
  MultiCursorModifier := Choice(MultiCursorModifier, [MultiCursorModifierAlt, MultiCursorModifierCtrl]);
  SmartPaste := Choice(SmartPaste, ['off', 'uses', 'indent', 'both']);
  MultiCursorNextKey := EnsureRange(MultiCursorNextKey, 0, $FFFF);
  MultiCursorSkipKey := EnsureRange(MultiCursorSkipKey, 0, $FFFF);
  MultiCursorLineEndsKey := EnsureRange(MultiCursorLineEndsKey, 0, $FFFF);
  MultiCursorAboveKey := EnsureRange(MultiCursorAboveKey, 0, $FFFF);
  MultiCursorBelowKey := EnsureRange(MultiCursorBelowKey, 0, $FFFF);
  BookmarkKey := EnsureRange(BookmarkKey, 0, $FFFF);
  HideElementKey := EnsureRange(HideElementKey, 0, $FFFF);
  InlineDiagnostics := Choice(InlineDiagnostics, ['errors', 'off', 'errorsAndWarnings', 'all']);
  ProblemsWindowScope := Choice(ProblemsWindowScope, ['group', 'file', 'project']);
  ProblemsWindowGroupBy := Choice(ProblemsWindowGroupBy, ['file', 'none', 'rule', 'category']);
  ProblemsWindowClosedUnits := Choice(ProblemsWindowClosedUnits, ['dimmed', 'normal', 'hidden']);
  ProblemsCompilerMerge := Choice(ProblemsCompilerMerge, ['merge', 'both']);
  ProblemsWindowKey := EnsureRange(ProblemsWindowKey, 0, $FFFF);
  GotoInterfaceKey := EnsureRange(GotoInterfaceKey, 0, $FFFF);
  GotoImplementationKey := EnsureRange(GotoImplementationKey, 0, $FFFF);
  NextProblemKey := EnsureRange(NextProblemKey, 0, $FFFF);
  PreviousProblemKey := EnsureRange(PreviousProblemKey, 0, $FFFF);
  SearchKey := EnsureRange(SearchKey, 0, $FFFF);
  SearchNextKey := EnsureRange(SearchNextKey, 0, $FFFF);
  SearchPreviousKey := EnsureRange(SearchPreviousKey, 0, $FFFF);
  SearchMethodKey := EnsureRange(SearchMethodKey, 0, $FFFF);
  GenerateMenuKey := EnsureRange(GenerateMenuKey, 0, $FFFF);
  GenerateMenuGroups := TAtlasGenerateLists.NormalizeGroups(GenerateMenuGroups);
  GenerateMenuHidden := TAtlasGenerateLists.NormalizeHidden(GenerateMenuHidden);
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
  NotificationsSources := TAtlasNotificationSources.Normalize(NotificationsSources);
  NotificationsMaxEntries := EnsureRange(NotificationsMaxEntries, MinNotificationEntries, MaxNotificationEntries);
  NotificationsKey := EnsureRange(NotificationsKey, 0, $FFFF);
  SettingsExportSecrets := Choice(SettingsExportSecrets, ['omit', 'placeholder']);
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
  SelectionMarker := AStore.ReadInteger('SelectionMarker', BoolValue(Default.SelectionMarker)) <> 0;
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
  CompletionVariantBranch := AStore.ReadInteger('CompletionVariantBranch',
    BoolValue(Default.CompletionVariantBranch)) <> 0;
  CompletionListMode := AStore.ReadString('CompletionListMode', Default.CompletionListMode);
  CompletionListScope := AStore.ReadString('CompletionListScope', Default.CompletionListScope);
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
  InlayTypeHints := AStore.ReadInteger('InlayTypeHints', BoolValue(Default.InlayTypeHints)) <> 0;
  InlayDefineHints := AStore.ReadInteger('InlayDefineHints', BoolValue(Default.InlayDefineHints)) <> 0;
  InlayCharHints := AStore.ReadInteger('InlayCharHints', BoolValue(Default.InlayCharHints)) <> 0;
  BlockEndLabels := AStore.ReadInteger('BlockEndLabels', BoolValue(Default.BlockEndLabels)) <> 0;
  BlockEndLabelsMinLines := AStore.ReadInteger('BlockEndLabelsMinLines', Default.BlockEndLabelsMinLines);
  DimUnusedUses := AStore.ReadInteger('DimUnusedUses', BoolValue(Default.DimUnusedUses)) <> 0;
  RecursionMarkers := AStore.ReadInteger('RecursionMarkers', BoolValue(Default.RecursionMarkers)) <> 0;
  RecursionMarkersDepth := AStore.ReadInteger('RecursionMarkersDepth', Default.RecursionMarkersDepth);
  Notes := AStore.ReadInteger('Notes', BoolValue(Default.Notes)) <> 0;
  BookmarksNamed := AStore.ReadInteger('BookmarksNamed', BoolValue(Default.BookmarksNamed)) <> 0;
  BookmarksShared := AStore.ReadInteger('BookmarksShared', BoolValue(Default.BookmarksShared)) <> 0;
  BookmarkKey := AStore.ReadInteger('BookmarkKey', Default.BookmarkKey);
  HideElementKey := AStore.ReadInteger('HideElementKey', Default.HideElementKey);
  SearchReplaceIde := AStore.ReadInteger('SearchReplaceIde', BoolValue(Default.SearchReplaceIde)) <> 0;
  SearchResultsInMessages := AStore.ReadInteger('SearchResultsInMessages',
    BoolValue(Default.SearchResultsInMessages)) <> 0;
  SearchKey := AStore.ReadInteger('SearchKey', Default.SearchKey);
  SearchNextKey := AStore.ReadInteger('SearchNextKey', Default.SearchNextKey);
  SearchPreviousKey := AStore.ReadInteger('SearchPreviousKey', Default.SearchPreviousKey);
  SearchMethodKey := AStore.ReadInteger('SearchMethodKey', Default.SearchMethodKey);
  ServerPath := Trim(AStore.ReadString('ServerPath', Default.ServerPath));
  PairGuides := AStore.ReadInteger('PairGuides', BoolValue(Default.PairGuides)) <> 0;
  PairOwners := AStore.ReadInteger('PairOwners', BoolValue(Default.PairOwners)) <> 0;
  PairGuideWidth := AStore.ReadInteger('PairGuideWidth', Default.PairGuideWidth);
  PairGuideOpacity := AStore.ReadInteger('PairGuideOpacity', Default.PairGuideOpacity);
  PairColorsLight := AStore.ReadString('PairColorsLight', Default.PairColorsLight);
  PairColorsDark := AStore.ReadString('PairColorsDark', Default.PairColorsDark);
  Problems := AStore.ReadInteger('Problems', BoolValue(Default.Problems)) <> 0;
  ProblemsList := AStore.ReadInteger('ProblemsList', BoolValue(Default.ProblemsList)) <> 0;
  ProblemsWindow := AStore.ReadInteger('ProblemsWindow', BoolValue(Default.ProblemsWindow)) <> 0;
  ProblemsWindowScope := AStore.ReadString('ProblemsWindowScope', Default.ProblemsWindowScope);
  ProblemsWindowGroupBy := AStore.ReadString('ProblemsWindowGroupBy', Default.ProblemsWindowGroupBy);
  ProblemsWindowColumns := AStore.ReadString('ProblemsWindowColumns', Default.ProblemsWindowColumns);
  ProblemsWindowCompiler := AStore.ReadInteger('ProblemsWindowCompiler', BoolValue(Default.ProblemsWindowCompiler)) <> 0;
  ProblemsWindowFollowCursor := AStore.ReadInteger('ProblemsWindowFollowCursor',
    BoolValue(Default.ProblemsWindowFollowCursor)) <> 0;
  ProblemsWindowOpenFirst := AStore.ReadInteger('ProblemsWindowOpenFirst',
    BoolValue(Default.ProblemsWindowOpenFirst)) <> 0;
  ProblemsWindowClosedUnits := AStore.ReadString('ProblemsWindowClosedUnits', Default.ProblemsWindowClosedUnits);
  ProblemsWindowShowCleanActive := AStore.ReadInteger('ProblemsWindowShowCleanActive',
    BoolValue(Default.ProblemsWindowShowCleanActive)) <> 0;
  ProblemsCompilerMerge := AStore.ReadString('ProblemsCompilerMerge', Default.ProblemsCompilerMerge);
  ProblemsShowCompilerCode := AStore.ReadInteger('ProblemsShowCompilerCode',
    BoolValue(Default.ProblemsShowCompilerCode)) <> 0;
  ProblemsWindowKey := AStore.ReadInteger('ProblemsWindowKey', Default.ProblemsWindowKey);
  GotoInterfaceKey := AStore.ReadInteger('GotoInterfaceKey', Default.GotoInterfaceKey);
  GotoImplementationKey := AStore.ReadInteger('GotoImplementationKey', Default.GotoImplementationKey);
  ProblemsLive := AStore.ReadInteger('ProblemsLive', BoolValue(Default.ProblemsLive)) <> 0;
  HoverProblemActions := AStore.ReadInteger('HoverProblemActions', BoolValue(Default.HoverProblemActions)) <> 0;
  InlineDiagnostics := AStore.ReadString('InlineDiagnostics', Default.InlineDiagnostics);
  ProblemsStatusCounter := AStore.ReadInteger('ProblemsStatusCounter', BoolValue(Default.ProblemsStatusCounter)) <> 0;
  NextProblemKey := AStore.ReadInteger('NextProblemKey', Default.NextProblemKey);
  PreviousProblemKey := AStore.ReadInteger('PreviousProblemKey', Default.PreviousProblemKey);
  CheckOnSave := AStore.ReadInteger('CheckOnSave', BoolValue(Default.CheckOnSave)) <> 0;
  CheckOnSaveDelayMs := AStore.ReadInteger('CheckOnSaveDelayMs', Default.CheckOnSaveDelayMs);
  CheckOnSaveMaxMs := AStore.ReadInteger('CheckOnSaveMaxMs', Default.CheckOnSaveMaxMs);
  McpBuild := AStore.ReadInteger('McpBuild', BoolValue(Default.McpBuild)) <> 0;
  BuildOnOpen := AStore.ReadInteger('BuildOnOpen', BoolValue(Default.BuildOnOpen)) <> 0;
  BuildOnOpenKind := AStore.ReadString('BuildOnOpenKind', Default.BuildOnOpenKind);
  BuildOnOpenScope := AStore.ReadString('BuildOnOpenScope', Default.BuildOnOpenScope);
  BuildOnOpenDelayMs := AStore.ReadInteger('BuildOnOpenDelayMs', Default.BuildOnOpenDelayMs);
  BuildOnOpenExclude := AStore.ReadString('BuildOnOpenExclude', Default.BuildOnOpenExclude);
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
  CodeLensMetrics := AStore.ReadInteger('CodeLensMetrics', BoolValue(Default.CodeLensMetrics)) <> 0;
  Metrics := AStore.ReadInteger('Metrics', BoolValue(Default.Metrics)) <> 0;
  CodeLensTests := AStore.ReadInteger('CodeLensTests', BoolValue(Default.CodeLensTests)) <> 0;
  TestRun := AStore.ReadInteger('TestRun', BoolValue(Default.TestRun)) <> 0;
  TestsAfterBuild := AStore.ReadInteger('TestsAfterBuild', BoolValue(Default.TestsAfterBuild)) <> 0;
  TestsBuildFirst := AStore.ReadInteger('TestsBuildFirst', BoolValue(Default.TestsBuildFirst)) <> 0;
  BuildZeroHints := AStore.ReadInteger('BuildZeroHints', BoolValue(Default.BuildZeroHints)) <> 0;
  ReleaseGuard := AStore.ReadInteger('ReleaseGuard', BoolValue(Default.ReleaseGuard)) <> 0;
  BuildGate := AStore.ReadString('BuildGate', Default.BuildGate);
  ReleaseConfigs := AStore.ReadString('ReleaseConfigs', Default.ReleaseConfigs);
  ReleaseChecks := AStore.ReadString('ReleaseChecks', Default.ReleaseChecks);
  TestDebug := AStore.ReadInteger('TestDebug', BoolValue(Default.TestDebug)) <> 0;
  TestBreakAtStart := AStore.ReadInteger('TestBreakAtStart', BoolValue(Default.TestBreakAtStart)) <> 0;
  DebugHoverValues := AStore.ReadInteger('DebugHoverValues', BoolValue(Default.DebugHoverValues)) <> 0;
  StartProfiles := AStore.ReadInteger('StartProfiles', BoolValue(Default.StartProfiles)) <> 0;
  StartProfilesStatusField := AStore.ReadInteger('StartProfilesStatusField',
    BoolValue(Default.StartProfilesStatusField)) <> 0;
  TodoList := AStore.ReadInteger('TodoList', BoolValue(Default.TodoList)) <> 0;
  BaselineUpdate := AStore.ReadInteger('BaselineUpdate', BoolValue(Default.BaselineUpdate)) <> 0;
  MetricsReport := AStore.ReadInteger('MetricsReport', BoolValue(Default.MetricsReport)) <> 0;
  DfmPropertyRules := AStore.ReadInteger('DfmPropertyRules', BoolValue(Default.DfmPropertyRules)) <> 0;
  TeamFile := AStore.ReadInteger('TeamFile', BoolValue(Default.TeamFile)) <> 0;
  EditorKeysPriority := AStore.ReadInteger('EditorKeysPriority', BoolValue(Default.EditorKeysPriority)) <> 0;
  SlashCommands := AStore.ReadInteger('SlashCommands', BoolValue(Default.SlashCommands)) <> 0;
  GenerateMenu := AStore.ReadInteger('GenerateMenu', BoolValue(Default.GenerateMenu)) <> 0;
  GenerateMenuKey := AStore.ReadInteger('GenerateMenuKey', Default.GenerateMenuKey);
  GenerateMenuGroups := AStore.ReadString('GenerateMenuGroups', Default.GenerateMenuGroups);
  GenerateMenuHidden := AStore.ReadString('GenerateMenuHidden', Default.GenerateMenuHidden);
  GenerateMenuRecentFirst := AStore.ReadInteger('GenerateMenuRecentFirst',
    BoolValue(Default.GenerateMenuRecentFirst)) <> 0;
  GenerateMenuShowCommandNames := AStore.ReadInteger('GenerateMenuShowCommandNames',
    BoolValue(Default.GenerateMenuShowCommandNames)) <> 0;
  Snippets := AStore.ReadInteger('Snippets', BoolValue(Default.Snippets)) <> 0;
  ImportIdeTemplates := AStore.ReadInteger('ImportIdeTemplates', BoolValue(Default.ImportIdeTemplates)) <> 0;
  IndexProjectGroup := AStore.ReadInteger('IndexProjectGroup', BoolValue(Default.IndexProjectGroup)) <> 0;
  IndexSearchPaths := AStore.ReadInteger('IndexSearchPaths', BoolValue(Default.IndexSearchPaths)) <> 0;
  IndexLibraryPaths := AStore.ReadInteger('IndexLibraryPaths', BoolValue(Default.IndexLibraryPaths)) <> 0;
  IndexUsages := AStore.ReadInteger('IndexUsages', BoolValue(Default.IndexUsages)) <> 0;
  MemoryBudgetMb := AStore.ReadInteger('MemoryBudgetMb', Default.MemoryBudgetMb);
  XmlDocExpand := AStore.ReadString('XmlDocExpand', '');
  // Vor #770: XmlDocFull übernehmen.
  if XmlDocExpand = '' then
    case AStore.ReadInteger('XmlDocFull', -1) of
      0:
        XmlDocExpand := 'collapsed';
      1:
        XmlDocExpand := 'expanded';
    else
      XmlDocExpand := Default.XmlDocExpand;
    end;
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
  DiagnosticsProcesses :=
    AStore.ReadInteger('DiagnosticsProcesses', BoolValue(Default.DiagnosticsProcesses)) <> 0;
  ArchitectureEnabled := AStore.ReadInteger('ArchitectureEnabled', BoolValue(Default.ArchitectureEnabled)) <> 0;
  ArchitectureScope := AStore.ReadString('ArchitectureScope', Default.ArchitectureScope);
  ArchitectureIncludeLibraryUnits := AStore.ReadInteger('ArchitectureIncludeLibraryUnits',
    BoolValue(Default.ArchitectureIncludeLibraryUnits)) <> 0;
  ArchitectureCentralUnits := AStore.ReadInteger('ArchitectureCentralUnits', Default.ArchitectureCentralUnits);
  ArchitectureWindowPlaced := AStore.ReadInteger('ArchitectureWindowPlaced',
    BoolValue(Default.ArchitectureWindowPlaced)) <> 0;
  SymbolPath := AStore.ReadInteger('SymbolPath', BoolValue(Default.SymbolPath)) <> 0;
  ExperimentalEnabled := AStore.ReadInteger('ExperimentalEnabled', BoolValue(Default.ExperimentalEnabled)) <> 0;
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
  UnitSearchPreviewAutoCollapse := AStore.ReadInteger('UnitSearchPreviewAutoCollapse',
    BoolValue(Default.UnitSearchPreviewAutoCollapse)) <> 0;
  UnitSearchMultiSelect := AStore.ReadInteger('UnitSearchMultiSelect', BoolValue(Default.UnitSearchMultiSelect)) <> 0;
  UnitSearchActions := AStore.ReadInteger('UnitSearchActions', BoolValue(Default.UnitSearchActions)) <> 0;
  UnitSearchActionsAddUses := AStore.ReadInteger('UnitSearchActionsAddUses', BoolValue(Default.UnitSearchActionsAddUses)) <> 0;
  UnitSearchPathStyle := AStore.ReadString('UnitSearchPathStyle', Default.UnitSearchPathStyle);
  UnitSearchGroupBy := AStore.ReadString('UnitSearchGroupBy', Default.UnitSearchGroupBy);
  UnitSearchDefaultScope := AStore.ReadString('UnitSearchDefaultScope', Default.UnitSearchDefaultScope);
  UnitSearchKey := AStore.ReadInteger('UnitSearchKey', Default.UnitSearchKey);
  QuickOpen := AStore.ReadInteger('QuickOpen', BoolValue(Default.QuickOpen)) <> 0;
  QuickOpenLibrary := AStore.ReadInteger('QuickOpenLibrary', BoolValue(Default.QuickOpenLibrary)) <> 0;
  QuickOpenKey := AStore.ReadInteger('QuickOpenKey', Default.QuickOpenKey);
  NavHistory := AStore.ReadInteger('NavHistory', BoolValue(Default.NavHistory)) <> 0;
  NavBackKey := AStore.ReadInteger('NavBackKey', Default.NavBackKey);
  NavForwardKey := AStore.ReadInteger('NavForwardKey', Default.NavForwardKey);
  LastEditKey := AStore.ReadInteger('LastEditKey', Default.LastEditKey);
  Peek := AStore.ReadInteger('Peek', BoolValue(Default.Peek)) <> 0;
  PeekHeightLines := AStore.ReadInteger('PeekHeightLines', Default.PeekHeightLines);
  PeekShowImplementation := AStore.ReadInteger('PeekShowImplementation',
    BoolValue(Default.PeekShowImplementation)) <> 0;
  PeekDefinitionKey := AStore.ReadInteger('PeekDefinitionKey', Default.PeekDefinitionKey);
  PeekReferencesKey := AStore.ReadInteger('PeekReferencesKey', Default.PeekReferencesKey);
  Outline := AStore.ReadInteger('Outline', BoolValue(Default.Outline)) <> 0;
  OutlineAlphabetical := AStore.ReadInteger('OutlineAlphabetical', BoolValue(Default.OutlineAlphabetical)) <> 0;
  OutlineFollowCursor := AStore.ReadInteger('OutlineFollowCursor', BoolValue(Default.OutlineFollowCursor)) <> 0;
  OutlineConditions := AStore.ReadInteger('OutlineConditions', BoolValue(Default.OutlineConditions)) <> 0;
  Breadcrumbs := AStore.ReadInteger('Breadcrumbs', BoolValue(Default.Breadcrumbs)) <> 0;
  BreadcrumbsShowUnit := AStore.ReadInteger('BreadcrumbsShowUnit', BoolValue(Default.BreadcrumbsShowUnit)) <> 0;
  BreadcrumbsIdeColors := AStore.ReadInteger('BreadcrumbsIdeColors', BoolValue(Default.BreadcrumbsIdeColors)) <> 0;
  BreadcrumbsHideIdeToolbar := AStore.ReadInteger('BreadcrumbsHideIdeToolbar',
    BoolValue(Default.BreadcrumbsHideIdeToolbar)) <> 0;
  EditorToolbar := AStore.ReadInteger('EditorToolbar', BoolValue(Default.EditorToolbar)) <> 0;
  EditorToolbarPosition := AStore.ReadString('EditorToolbarPosition', Default.EditorToolbarPosition);
  EditorToolbarItems := AStore.ReadString('EditorToolbarItems', Default.EditorToolbarItems);
  EditorToolbarReturnButton := AStore.ReadInteger('EditorToolbarReturnButton',
    BoolValue(Default.EditorToolbarReturnButton)) <> 0;
  EditorToolbarLabels := AStore.ReadInteger('EditorToolbarLabels', BoolValue(Default.EditorToolbarLabels)) <> 0;
  QuickBookmarks := AStore.ReadInteger('QuickBookmarks', BoolValue(Default.QuickBookmarks)) <> 0;
  QuickBookmarksGutter := AStore.ReadInteger('QuickBookmarksGutter', BoolValue(Default.QuickBookmarksGutter)) <> 0;
  QuickBookmarksGutterClick := AStore.ReadInteger('QuickBookmarksGutterClick',
    BoolValue(Default.QuickBookmarksGutterClick)) <> 0;
  QuickBookmarksNumberedKeys := AStore.ReadInteger('QuickBookmarksNumberedKeys',
    BoolValue(Default.QuickBookmarksNumberedKeys)) <> 0;
  QuickBookmarkKey := AStore.ReadInteger('QuickBookmarkKey', Default.QuickBookmarkKey);
  QuickBookmarkKeyPriority := AStore.ReadInteger('QuickBookmarkKeyPriority',
    BoolValue(Default.QuickBookmarkKeyPriority)) <> 0;
  QuickBookmarkChordWait := AStore.ReadInteger('QuickBookmarkChordWait', Default.QuickBookmarkChordWait);
  QuickBookmarkSetKey := AStore.ReadInteger('QuickBookmarkSetKey', Default.QuickBookmarkSetKey);
  QuickBookmarkSetKeyPriority := AStore.ReadInteger('QuickBookmarkSetKeyPriority',
    BoolValue(Default.QuickBookmarkSetKeyPriority)) <> 0;
  QuickBookmarkJumpKey := AStore.ReadInteger('QuickBookmarkJumpKey', Default.QuickBookmarkJumpKey);
  QuickBookmarkJumpKeyPriority := AStore.ReadInteger('QuickBookmarkJumpKeyPriority',
    BoolValue(Default.QuickBookmarkJumpKeyPriority)) <> 0;
  QuickBookmarksScope := AStore.ReadString('QuickBookmarksScope', Default.QuickBookmarksScope);
  QuickBookmarksImportIde := AStore.ReadInteger('QuickBookmarksImportIde',
    BoolValue(Default.QuickBookmarksImportIde)) <> 0;
  NextBookmarkKey := AStore.ReadInteger('NextBookmarkKey', Default.NextBookmarkKey);
  PreviousBookmarkKey := AStore.ReadInteger('PreviousBookmarkKey', Default.PreviousBookmarkKey);
  StickyScroll := AStore.ReadInteger('StickyScroll', BoolValue(Default.StickyScroll)) <> 0;
  StickyScrollMaxLines := AStore.ReadInteger('StickyScrollMaxLines', Default.StickyScrollMaxLines);
  Minimap := AStore.ReadInteger('Minimap', BoolValue(Default.Minimap)) <> 0;
  MinimapRender := AStore.ReadString('MinimapRender', Default.MinimapRender);
  MinimapWidth := AStore.ReadInteger('MinimapWidth', Default.MinimapWidth);
  MinimapScale := AStore.ReadInteger('MinimapScale', Default.MinimapScale);
  MinimapMaxColumn := AStore.ReadInteger('MinimapMaxColumn', Default.MinimapMaxColumn);
  MinimapSide := AStore.ReadString('MinimapSide', Default.MinimapSide);
  MinimapShowSlider := AStore.ReadString('MinimapShowSlider', Default.MinimapShowSlider);
  MinimapSectionHeaders := AStore.ReadInteger('MinimapSectionHeaders', BoolValue(Default.MinimapSectionHeaders)) <> 0;
  MinimapHighlightMethod := AStore.ReadInteger('MinimapHighlightMethod',
    BoolValue(Default.MinimapHighlightMethod)) <> 0;
  MinimapMarkers := AStore.ReadInteger('MinimapMarkers', BoolValue(Default.MinimapMarkers)) <> 0;
  MinimapClickJumps := AStore.ReadInteger('MinimapClickJumps', BoolValue(Default.MinimapClickJumps)) <> 0;
  MinimapNoticeShown := AStore.ReadInteger('MinimapNoticeShown', BoolValue(Default.MinimapNoticeShown)) <> 0;
  BreadcrumbsKey := AStore.ReadInteger('BreadcrumbsKey', Default.BreadcrumbsKey);
  GitGutter := AStore.ReadInteger('GitGutter', BoolValue(Default.GitGutter)) <> 0;
  GitBlame := AStore.ReadInteger('GitBlame', BoolValue(Default.GitBlame)) <> 0;
  GutterColumn := AStore.ReadInteger('GutterColumn', BoolValue(Default.GutterColumn)) <> 0;
  GutterColumnProblems := AStore.ReadInteger('GutterColumnProblems', BoolValue(Default.GutterColumnProblems)) <> 0;
  GutterColumnCodeActions := AStore.ReadInteger('GutterColumnCodeActions',
    BoolValue(Default.GutterColumnCodeActions)) <> 0;
  GutterColumnOverrides := AStore.ReadInteger('GutterColumnOverrides', BoolValue(Default.GutterColumnOverrides)) <> 0;
  SelectionMatches := AStore.ReadInteger('SelectionMatches', BoolValue(Default.SelectionMatches)) <> 0;
  SelectionMatchesMinLength := AStore.ReadInteger('SelectionMatchesMinLength', Default.SelectionMatchesMinLength);
  SelectionMatchesCaseSensitive := AStore.ReadInteger('SelectionMatchesCaseSensitive',
    BoolValue(Default.SelectionMatchesCaseSensitive)) <> 0;
  SelectionMatchesWholeWord := AStore.ReadInteger('SelectionMatchesWholeWord',
    BoolValue(Default.SelectionMatchesWholeWord)) <> 0;
  SelectionMatchesNavigateF3 := AStore.ReadInteger('SelectionMatchesNavigateF3',
    BoolValue(Default.SelectionMatchesNavigateF3)) <> 0;
  SelectionMatchesMaxMatches := AStore.ReadInteger('SelectionMatchesMaxMatches', Default.SelectionMatchesMaxMatches);
  ToggleBlockComment := AStore.ReadInteger('ToggleBlockComment', BoolValue(Default.ToggleBlockComment)) <> 0;
  ToggleBlockCommentKey := AStore.ReadInteger('ToggleBlockCommentKey', Default.ToggleBlockCommentKey);
  ToggleBlockCommentStyle := AStore.ReadString('ToggleBlockCommentStyle', Default.ToggleBlockCommentStyle);
  ToggleBlockCommentFallback := AStore.ReadString('ToggleBlockCommentFallback', Default.ToggleBlockCommentFallback);
  ToggleBlockCommentOwnLines := AStore.ReadInteger('ToggleBlockCommentOwnLines',
    BoolValue(Default.ToggleBlockCommentOwnLines)) <> 0;
  ToggleBlockCommentWithoutSelection := AStore.ReadString('ToggleBlockCommentWithoutSelection',
    Default.ToggleBlockCommentWithoutSelection);
  NewLineAround := AStore.ReadInteger('NewLineAround', BoolValue(Default.NewLineAround)) <> 0;
  NewLineBelowKey := AStore.ReadInteger('NewLineBelowKey', Default.NewLineBelowKey);
  NewLineAboveKey := AStore.ReadInteger('NewLineAboveKey', Default.NewLineAboveKey);
  NewLineAroundStatementAware := AStore.ReadInteger('NewLineAroundStatementAware',
    BoolValue(Default.NewLineAroundStatementAware)) <> 0;
  Unwrap := AStore.ReadInteger('Unwrap', BoolValue(Default.Unwrap)) <> 0;
  UnwrapKey := AStore.ReadInteger('UnwrapKey', Default.UnwrapKey);
  NextChangeKey := AStore.ReadInteger('NextChangeKey', Default.NextChangeKey);
  PreviousChangeKey := AStore.ReadInteger('PreviousChangeKey', Default.PreviousChangeKey);
  OverviewRuler := AStore.ReadInteger('OverviewRuler', BoolValue(Default.OverviewRuler)) <> 0;
  OverviewRulerKinds := AStore.ReadString('OverviewRulerKinds', Default.OverviewRulerKinds);
  JumpToMatch := AStore.ReadInteger('JumpToMatch', BoolValue(Default.JumpToMatch)) <> 0;
  JumpToMatchKey := AStore.ReadInteger('JumpToMatchKey', Default.JumpToMatchKey);
  JumpToMatchSelectKey := AStore.ReadInteger('JumpToMatchSelectKey', Default.JumpToMatchSelectKey);
  MoveLines := AStore.ReadInteger('MoveLines', BoolValue(Default.MoveLines)) <> 0;
  MoveLinesUpKey := AStore.ReadInteger('MoveLinesUpKey', Default.MoveLinesUpKey);
  MoveLinesDownKey := AStore.ReadInteger('MoveLinesDownKey', Default.MoveLinesDownKey);
  DuplicateLinesUpKey := AStore.ReadInteger('DuplicateLinesUpKey', Default.DuplicateLinesUpKey);
  DuplicateLinesDownKey := AStore.ReadInteger('DuplicateLinesDownKey', Default.DuplicateLinesDownKey);
  ContinueComments := AStore.ReadInteger('ContinueComments', BoolValue(Default.ContinueComments)) <> 0;
  ContinueCommentsLineComments := AStore.ReadInteger('ContinueCommentsLineComments',
    BoolValue(Default.ContinueCommentsLineComments)) <> 0;
  ContinueCommentsLists := AStore.ReadInteger('ContinueCommentsLists',
    BoolValue(Default.ContinueCommentsLists)) <> 0;
  ContinueCommentsBlockPrefix := AStore.ReadString('ContinueCommentsBlockPrefix',
    Default.ContinueCommentsBlockPrefix);
  WrapSelection := AStore.ReadInteger('WrapSelection', BoolValue(Default.WrapSelection)) <> 0;
  WrapSelectionChars := AStore.ReadString('WrapSelectionChars', Default.WrapSelectionChars);
  CompleteStatement := AStore.ReadInteger('CompleteStatement', BoolValue(Default.CompleteStatement)) <> 0;
  CompleteStatementKey := AStore.ReadInteger('CompleteStatementKey', Default.CompleteStatementKey);
  CompleteStatementBeginEnd := AStore.ReadString('CompleteStatementBeginEnd', Default.CompleteStatementBeginEnd);
  CompleteStatementTryKind := AStore.ReadString('CompleteStatementTryKind', Default.CompleteStatementTryKind);
  CompleteStatementMethodBody := AStore.ReadInteger('CompleteStatementMethodBody',
    BoolValue(Default.CompleteStatementMethodBody)) <> 0;
  FormatCode := AStore.ReadInteger('FormatCode', BoolValue(Default.FormatCode)) <> 0;
  FormatCodeKey := AStore.ReadInteger('FormatCodeKey', Default.FormatCodeKey);
  ContinuePattern := AStore.ReadInteger('ContinuePattern', BoolValue(Default.ContinuePattern)) <> 0;
  ContinuePatternMinLines := AStore.ReadInteger('ContinuePatternMinLines', Default.ContinuePatternMinLines);
  MultiCursor := AStore.ReadInteger('MultiCursor', BoolValue(Default.MultiCursor)) <> 0;
  LinkedEditing := AStore.ReadInteger('LinkedEditing', BoolValue(Default.LinkedEditing)) <> 0;
  MultiCursorModifier := AStore.ReadString('MultiCursorModifier', Default.MultiCursorModifier);
  SmartPaste := AStore.ReadString('SmartPaste', Default.SmartPaste);
  MultiCursorNextKey := AStore.ReadInteger('MultiCursorNextKey', Default.MultiCursorNextKey);
  MultiCursorSkipKey := AStore.ReadInteger('MultiCursorSkipKey', Default.MultiCursorSkipKey);
  MultiCursorLineEndsKey := AStore.ReadInteger('MultiCursorLineEndsKey', Default.MultiCursorLineEndsKey);
  MultiCursorAboveKey := AStore.ReadInteger('MultiCursorAboveKey', Default.MultiCursorAboveKey);
  MultiCursorBelowKey := AStore.ReadInteger('MultiCursorBelowKey', Default.MultiCursorBelowKey);
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
  WelcomePageProjectSetup := AStore.ReadInteger('WelcomePageProjectSetup',
    BoolValue(Default.WelcomePageProjectSetup)) <> 0;
  WelcomePageNewFromTemplate := AStore.ReadInteger('WelcomePageNewFromTemplate',
    BoolValue(Default.WelcomePageNewFromTemplate)) <> 0;
  WelcomePageContinue := AStore.ReadInteger('WelcomePageContinue', BoolValue(Default.WelcomePageContinue)) <> 0;
  WelcomePageContinueCount := AStore.ReadInteger('WelcomePageContinueCount', Default.WelcomePageContinueCount);
  WelcomePageContinueIncoming := AStore.ReadInteger('WelcomePageContinueIncoming',
    BoolValue(Default.WelcomePageContinueIncoming)) <> 0;
  WelcomePageContinueFetch := AStore.ReadInteger('WelcomePageContinueFetch',
    BoolValue(Default.WelcomePageContinueFetch)) <> 0;
  WelcomePageSaved := AStore.ReadInteger('WelcomePageSaved', BoolValue(Default.WelcomePageSaved)) <> 0;
  WelcomePageTrends := AStore.ReadInteger('WelcomePageTrends', BoolValue(Default.WelcomePageTrends)) <> 0;
  WelcomePageTrendsPoints := AStore.ReadInteger('WelcomePageTrendsPoints', Default.WelcomePageTrendsPoints);
  WelcomePageTrendsSeries := AStore.ReadString('WelcomePageTrendsSeries', Default.WelcomePageTrendsSeries);
  WelcomePageTests := AStore.ReadInteger('WelcomePageTests', BoolValue(Default.WelcomePageTests)) <> 0;
  WelcomePageTestsMaxFailures := AStore.ReadInteger('WelcomePageTestsMaxFailures',
    Default.WelcomePageTestsMaxFailures);
  WelcomePageTestsCi := AStore.ReadInteger('WelcomePageTestsCi', BoolValue(Default.WelcomePageTestsCi)) <> 0;
  WelcomePageTestsCiProvider := AStore.ReadString('WelcomePageTestsCiProvider', Default.WelcomePageTestsCiProvider);
  WelcomePageTestsCiIntervalMinutes := AStore.ReadInteger('WelcomePageTestsCiIntervalMinutes',
    Default.WelcomePageTestsCiIntervalMinutes);
  WelcomePageTestsCiNotify := AStore.ReadInteger('WelcomePageTestsCiNotify',
    BoolValue(Default.WelcomePageTestsCiNotify)) <> 0;
  CiLogin := AStore.ReadInteger('CiLogin', BoolValue(Default.CiLogin)) <> 0;
  WelcomePageQuickActions := AStore.ReadInteger('WelcomePageQuickActions',
    BoolValue(Default.WelcomePageQuickActions)) <> 0;
  WelcomePageQuickActionsItems := AStore.ReadString('WelcomePageQuickActionsItems',
    Default.WelcomePageQuickActionsItems);
  WelcomePageQuickActionsConsole := AStore.ReadString('WelcomePageQuickActionsConsole',
    Default.WelcomePageQuickActionsConsole);
  WelcomePageQuickActionsBuildKey := AStore.ReadInteger('WelcomePageQuickActionsBuildKey',
    Default.WelcomePageQuickActionsBuildKey);
  WelcomePageQuickActionsTestKey := AStore.ReadInteger('WelcomePageQuickActionsTestKey',
    Default.WelcomePageQuickActionsTestKey);
  WelcomePageIssues := AStore.ReadInteger('WelcomePageIssues', BoolValue(Default.WelcomePageIssues)) <> 0;
  WelcomePageIssuesTracker := AStore.ReadString('WelcomePageIssuesTracker', Default.WelcomePageIssuesTracker);
  WelcomePageIssuesQuery := AStore.ReadString('WelcomePageIssuesQuery', Default.WelcomePageIssuesQuery);
  WelcomePageIssuesStart := AStore.ReadString('WelcomePageIssuesStart', Default.WelcomePageIssuesStart);
  WelcomePageIssuesBranchPattern := AStore.ReadString('WelcomePageIssuesBranchPattern',
    Default.WelcomePageIssuesBranchPattern);
  WelcomePageIssuesBranchBase := AStore.ReadString('WelcomePageIssuesBranchBase',
    Default.WelcomePageIssuesBranchBase);
  WelcomePageIssuesCommitPattern := AStore.ReadString('WelcomePageIssuesCommitPattern',
    Default.WelcomePageIssuesCommitPattern);
  TrackerLogin := AStore.ReadInteger('TrackerLogin', BoolValue(Default.TrackerLogin)) <> 0;
  WelcomePageCustomLayout := AStore.ReadInteger('WelcomePageCustomLayout',
    BoolValue(Default.WelcomePageCustomLayout)) <> 0;
  WelcomePageColumns := AStore.ReadInteger('WelcomePageColumns', Default.WelcomePageColumns);
  WelcomePageLayouts := AStore.ReadString('WelcomePageLayouts', Default.WelcomePageLayouts);
  WelcomePageActiveLayout := AStore.ReadString('WelcomePageActiveLayout', Default.WelcomePageActiveLayout);
  Notifications := AStore.ReadInteger('Notifications', BoolValue(Default.Notifications)) <> 0;
  NotificationsSources := AStore.ReadString('NotificationsSources', Default.NotificationsSources);
  NotificationsMaxEntries := AStore.ReadInteger('NotificationsMaxEntries', Default.NotificationsMaxEntries);
  NotificationsKey := AStore.ReadInteger('NotificationsKey', Default.NotificationsKey);
  SettingsExportImport := AStore.ReadInteger('SettingsExportImport', BoolValue(Default.SettingsExportImport)) <> 0;
  SettingsMarkModified := AStore.ReadInteger('SettingsMarkModified', BoolValue(Default.SettingsMarkModified)) <> 0;
  SettingsBackupBeforeImport := AStore.ReadInteger('SettingsBackupBeforeImport',
    BoolValue(Default.SettingsBackupBeforeImport)) <> 0;
  SettingsExportSecrets := AStore.ReadString('SettingsExportSecrets', Default.SettingsExportSecrets);
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
  AStore.WriteInteger('SelectionMarker', BoolValue(SelectionMarker));
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
  AStore.WriteInteger('CompletionVariantBranch', BoolValue(CompletionVariantBranch));
  AStore.WriteString('CompletionListMode', CompletionListMode);
  AStore.WriteString('CompletionListScope', CompletionListScope);
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
  AStore.WriteInteger('InlayTypeHints', BoolValue(InlayTypeHints));
  AStore.WriteInteger('InlayDefineHints', BoolValue(InlayDefineHints));
  AStore.WriteInteger('InlayCharHints', BoolValue(InlayCharHints));
  AStore.WriteInteger('BlockEndLabels', BoolValue(BlockEndLabels));
  AStore.WriteInteger('BlockEndLabelsMinLines', BlockEndLabelsMinLines);
  AStore.WriteInteger('DimUnusedUses', BoolValue(DimUnusedUses));
  AStore.WriteInteger('RecursionMarkers', BoolValue(RecursionMarkers));
  AStore.WriteInteger('RecursionMarkersDepth', RecursionMarkersDepth);
  AStore.WriteInteger('Notes', BoolValue(Notes));
  AStore.WriteInteger('BookmarksNamed', BoolValue(BookmarksNamed));
  AStore.WriteInteger('BookmarksShared', BoolValue(BookmarksShared));
  AStore.WriteInteger('BookmarkKey', BookmarkKey);
  AStore.WriteInteger('HideElementKey', HideElementKey);
  AStore.WriteInteger('SearchReplaceIde', BoolValue(SearchReplaceIde));
  AStore.WriteInteger('SearchResultsInMessages', BoolValue(SearchResultsInMessages));
  AStore.WriteInteger('SearchKey', SearchKey);
  AStore.WriteInteger('SearchNextKey', SearchNextKey);
  AStore.WriteInteger('SearchPreviousKey', SearchPreviousKey);
  AStore.WriteInteger('SearchMethodKey', SearchMethodKey);
  AStore.WriteString('ServerPath', Trim(ServerPath));
  AStore.WriteInteger('PairGuides', BoolValue(PairGuides));
  AStore.WriteInteger('PairOwners', BoolValue(PairOwners));
  AStore.WriteInteger('PairGuideWidth', PairGuideWidth);
  AStore.WriteInteger('PairGuideOpacity', PairGuideOpacity);
  AStore.WriteString('PairColorsLight', PairColorsLight);
  AStore.WriteString('PairColorsDark', PairColorsDark);
  AStore.WriteInteger('Problems', BoolValue(Problems));
  AStore.WriteInteger('ProblemsList', BoolValue(ProblemsList));
  AStore.WriteInteger('ProblemsWindow', BoolValue(ProblemsWindow));
  AStore.WriteString('ProblemsWindowScope', ProblemsWindowScope);
  AStore.WriteString('ProblemsWindowGroupBy', ProblemsWindowGroupBy);
  AStore.WriteString('ProblemsWindowColumns', ProblemsWindowColumns);
  AStore.WriteInteger('ProblemsWindowCompiler', BoolValue(ProblemsWindowCompiler));
  AStore.WriteInteger('ProblemsWindowFollowCursor', BoolValue(ProblemsWindowFollowCursor));
  AStore.WriteInteger('ProblemsWindowOpenFirst', BoolValue(ProblemsWindowOpenFirst));
  AStore.WriteString('ProblemsWindowClosedUnits', ProblemsWindowClosedUnits);
  AStore.WriteInteger('ProblemsWindowShowCleanActive', BoolValue(ProblemsWindowShowCleanActive));
  AStore.WriteString('ProblemsCompilerMerge', ProblemsCompilerMerge);
  AStore.WriteInteger('ProblemsShowCompilerCode', BoolValue(ProblemsShowCompilerCode));
  AStore.WriteInteger('ProblemsWindowKey', ProblemsWindowKey);
  AStore.WriteInteger('GotoInterfaceKey', GotoInterfaceKey);
  AStore.WriteInteger('GotoImplementationKey', GotoImplementationKey);
  AStore.WriteInteger('ProblemsLive', BoolValue(ProblemsLive));
  AStore.WriteInteger('HoverProblemActions', BoolValue(HoverProblemActions));
  AStore.WriteString('InlineDiagnostics', InlineDiagnostics);
  AStore.WriteInteger('ProblemsStatusCounter', BoolValue(ProblemsStatusCounter));
  AStore.WriteInteger('NextProblemKey', NextProblemKey);
  AStore.WriteInteger('PreviousProblemKey', PreviousProblemKey);
  AStore.WriteInteger('CheckOnSave', BoolValue(CheckOnSave));
  AStore.WriteInteger('CheckOnSaveDelayMs', CheckOnSaveDelayMs);
  AStore.WriteInteger('CheckOnSaveMaxMs', CheckOnSaveMaxMs);
  AStore.WriteInteger('McpBuild', BoolValue(McpBuild));
  AStore.WriteInteger('BuildOnOpen', BoolValue(BuildOnOpen));
  AStore.WriteString('BuildOnOpenKind', BuildOnOpenKind);
  AStore.WriteString('BuildOnOpenScope', BuildOnOpenScope);
  AStore.WriteInteger('BuildOnOpenDelayMs', BuildOnOpenDelayMs);
  AStore.WriteString('BuildOnOpenExclude', BuildOnOpenExclude);
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
  AStore.WriteInteger('CodeLensMetrics', BoolValue(CodeLensMetrics));
  AStore.WriteInteger('Metrics', BoolValue(Metrics));
  AStore.WriteInteger('CodeLensTests', BoolValue(CodeLensTests));
  AStore.WriteInteger('TestRun', BoolValue(TestRun));
  AStore.WriteInteger('TestsAfterBuild', BoolValue(TestsAfterBuild));
  AStore.WriteInteger('TestsBuildFirst', BoolValue(TestsBuildFirst));
  AStore.WriteInteger('BuildZeroHints', BoolValue(BuildZeroHints));
  AStore.WriteInteger('ReleaseGuard', BoolValue(ReleaseGuard));
  AStore.WriteString('BuildGate', BuildGate);
  AStore.WriteString('ReleaseConfigs', ReleaseConfigs);
  AStore.WriteString('ReleaseChecks', ReleaseChecks);
  AStore.WriteInteger('TestDebug', BoolValue(TestDebug));
  AStore.WriteInteger('TestBreakAtStart', BoolValue(TestBreakAtStart));
  AStore.WriteInteger('DebugHoverValues', BoolValue(DebugHoverValues));
  AStore.WriteInteger('StartProfiles', BoolValue(StartProfiles));
  AStore.WriteInteger('StartProfilesStatusField', BoolValue(StartProfilesStatusField));
  AStore.WriteInteger('TodoList', BoolValue(TodoList));
  AStore.WriteInteger('BaselineUpdate', BoolValue(BaselineUpdate));
  AStore.WriteInteger('MetricsReport', BoolValue(MetricsReport));
  AStore.WriteInteger('DfmPropertyRules', BoolValue(DfmPropertyRules));
  AStore.WriteInteger('TeamFile', BoolValue(TeamFile));
  AStore.WriteInteger('EditorKeysPriority', BoolValue(EditorKeysPriority));
  AStore.WriteInteger('SlashCommands', BoolValue(SlashCommands));
  AStore.WriteInteger('GenerateMenu', BoolValue(GenerateMenu));
  AStore.WriteInteger('GenerateMenuKey', GenerateMenuKey);
  AStore.WriteString('GenerateMenuGroups', GenerateMenuGroups);
  AStore.WriteString('GenerateMenuHidden', GenerateMenuHidden);
  AStore.WriteInteger('GenerateMenuRecentFirst', BoolValue(GenerateMenuRecentFirst));
  AStore.WriteInteger('GenerateMenuShowCommandNames', BoolValue(GenerateMenuShowCommandNames));
  AStore.WriteInteger('Snippets', BoolValue(Snippets));
  AStore.WriteInteger('ImportIdeTemplates', BoolValue(ImportIdeTemplates));
  AStore.WriteInteger('IndexProjectGroup', BoolValue(IndexProjectGroup));
  AStore.WriteInteger('IndexSearchPaths', BoolValue(IndexSearchPaths));
  AStore.WriteInteger('IndexLibraryPaths', BoolValue(IndexLibraryPaths));
  AStore.WriteInteger('IndexUsages', BoolValue(IndexUsages));
  AStore.WriteInteger('MemoryBudgetMb', MemoryBudgetMb);
  AStore.WriteString('XmlDocExpand', XmlDocExpand);
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
  AStore.WriteInteger('DiagnosticsProcesses', BoolValue(DiagnosticsProcesses));
  AStore.WriteInteger('ArchitectureEnabled', BoolValue(ArchitectureEnabled));
  AStore.WriteString('ArchitectureScope', ArchitectureScope);
  AStore.WriteInteger('ArchitectureIncludeLibraryUnits', BoolValue(ArchitectureIncludeLibraryUnits));
  AStore.WriteInteger('ArchitectureCentralUnits', ArchitectureCentralUnits);
  AStore.WriteInteger('ArchitectureWindowPlaced', BoolValue(ArchitectureWindowPlaced));
  AStore.WriteInteger('SymbolPath', BoolValue(SymbolPath));
  AStore.WriteInteger('ExperimentalEnabled', BoolValue(ExperimentalEnabled));
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
  AStore.WriteInteger('UnitSearchPreviewAutoCollapse', BoolValue(UnitSearchPreviewAutoCollapse));
  AStore.WriteInteger('UnitSearchMultiSelect', BoolValue(UnitSearchMultiSelect));
  AStore.WriteInteger('UnitSearchActions', BoolValue(UnitSearchActions));
  AStore.WriteInteger('UnitSearchActionsAddUses', BoolValue(UnitSearchActionsAddUses));
  AStore.WriteString('UnitSearchPathStyle', UnitSearchPathStyle);
  AStore.WriteString('UnitSearchGroupBy', UnitSearchGroupBy);
  AStore.WriteString('UnitSearchDefaultScope', UnitSearchDefaultScope);
  AStore.WriteInteger('UnitSearchKey', UnitSearchKey);
  AStore.WriteInteger('QuickOpen', BoolValue(QuickOpen));
  AStore.WriteInteger('QuickOpenLibrary', BoolValue(QuickOpenLibrary));
  AStore.WriteInteger('QuickOpenKey', QuickOpenKey);
  AStore.WriteInteger('NavHistory', BoolValue(NavHistory));
  AStore.WriteInteger('NavBackKey', NavBackKey);
  AStore.WriteInteger('NavForwardKey', NavForwardKey);
  AStore.WriteInteger('LastEditKey', LastEditKey);
  AStore.WriteInteger('Peek', BoolValue(Peek));
  AStore.WriteInteger('PeekHeightLines', PeekHeightLines);
  AStore.WriteInteger('PeekShowImplementation', BoolValue(PeekShowImplementation));
  AStore.WriteInteger('PeekDefinitionKey', PeekDefinitionKey);
  AStore.WriteInteger('PeekReferencesKey', PeekReferencesKey);
  AStore.WriteInteger('Outline', BoolValue(Outline));
  AStore.WriteInteger('OutlineAlphabetical', BoolValue(OutlineAlphabetical));
  AStore.WriteInteger('OutlineFollowCursor', BoolValue(OutlineFollowCursor));
  AStore.WriteInteger('OutlineConditions', BoolValue(OutlineConditions));
  AStore.WriteInteger('Breadcrumbs', BoolValue(Breadcrumbs));
  AStore.WriteInteger('BreadcrumbsShowUnit', BoolValue(BreadcrumbsShowUnit));
  AStore.WriteInteger('BreadcrumbsIdeColors', BoolValue(BreadcrumbsIdeColors));
  AStore.WriteInteger('BreadcrumbsHideIdeToolbar', BoolValue(BreadcrumbsHideIdeToolbar));
  AStore.WriteInteger('EditorToolbar', BoolValue(EditorToolbar));
  AStore.WriteString('EditorToolbarPosition', EditorToolbarPosition);
  AStore.WriteString('EditorToolbarItems', EditorToolbarItems);
  AStore.WriteInteger('EditorToolbarReturnButton', BoolValue(EditorToolbarReturnButton));
  AStore.WriteInteger('EditorToolbarLabels', BoolValue(EditorToolbarLabels));
  AStore.WriteInteger('QuickBookmarks', BoolValue(QuickBookmarks));
  AStore.WriteInteger('QuickBookmarksGutter', BoolValue(QuickBookmarksGutter));
  AStore.WriteInteger('QuickBookmarksGutterClick', BoolValue(QuickBookmarksGutterClick));
  AStore.WriteInteger('QuickBookmarksNumberedKeys', BoolValue(QuickBookmarksNumberedKeys));
  AStore.WriteInteger('QuickBookmarkKey', QuickBookmarkKey);
  AStore.WriteInteger('QuickBookmarkKeyPriority', BoolValue(QuickBookmarkKeyPriority));
  AStore.WriteInteger('QuickBookmarkChordWait', QuickBookmarkChordWait);
  AStore.WriteInteger('QuickBookmarkSetKey', QuickBookmarkSetKey);
  AStore.WriteInteger('QuickBookmarkSetKeyPriority', BoolValue(QuickBookmarkSetKeyPriority));
  AStore.WriteInteger('QuickBookmarkJumpKey', QuickBookmarkJumpKey);
  AStore.WriteInteger('QuickBookmarkJumpKeyPriority', BoolValue(QuickBookmarkJumpKeyPriority));
  AStore.WriteString('QuickBookmarksScope', QuickBookmarksScope);
  AStore.WriteInteger('QuickBookmarksImportIde', BoolValue(QuickBookmarksImportIde));
  AStore.WriteInteger('NextBookmarkKey', NextBookmarkKey);
  AStore.WriteInteger('PreviousBookmarkKey', PreviousBookmarkKey);
  AStore.WriteInteger('StickyScroll', BoolValue(StickyScroll));
  AStore.WriteInteger('StickyScrollMaxLines', StickyScrollMaxLines);
  AStore.WriteInteger('Minimap', BoolValue(Minimap));
  AStore.WriteString('MinimapRender', MinimapRender);
  AStore.WriteInteger('MinimapWidth', MinimapWidth);
  AStore.WriteInteger('MinimapScale', MinimapScale);
  AStore.WriteInteger('MinimapMaxColumn', MinimapMaxColumn);
  AStore.WriteString('MinimapSide', MinimapSide);
  AStore.WriteString('MinimapShowSlider', MinimapShowSlider);
  AStore.WriteInteger('MinimapSectionHeaders', BoolValue(MinimapSectionHeaders));
  AStore.WriteInteger('MinimapHighlightMethod', BoolValue(MinimapHighlightMethod));
  AStore.WriteInteger('MinimapMarkers', BoolValue(MinimapMarkers));
  AStore.WriteInteger('MinimapClickJumps', BoolValue(MinimapClickJumps));
  AStore.WriteInteger('MinimapNoticeShown', BoolValue(MinimapNoticeShown));
  AStore.WriteInteger('BreadcrumbsKey', BreadcrumbsKey);
  AStore.WriteInteger('GitGutter', BoolValue(GitGutter));
  AStore.WriteInteger('GitBlame', BoolValue(GitBlame));
  AStore.WriteInteger('GutterColumn', BoolValue(GutterColumn));
  AStore.WriteInteger('GutterColumnProblems', BoolValue(GutterColumnProblems));
  AStore.WriteInteger('GutterColumnCodeActions', BoolValue(GutterColumnCodeActions));
  AStore.WriteInteger('GutterColumnOverrides', BoolValue(GutterColumnOverrides));
  AStore.WriteInteger('SelectionMatches', BoolValue(SelectionMatches));
  AStore.WriteInteger('SelectionMatchesMinLength', SelectionMatchesMinLength);
  AStore.WriteInteger('SelectionMatchesCaseSensitive', BoolValue(SelectionMatchesCaseSensitive));
  AStore.WriteInteger('SelectionMatchesWholeWord', BoolValue(SelectionMatchesWholeWord));
  AStore.WriteInteger('SelectionMatchesNavigateF3', BoolValue(SelectionMatchesNavigateF3));
  AStore.WriteInteger('SelectionMatchesMaxMatches', SelectionMatchesMaxMatches);
  AStore.WriteInteger('ToggleBlockComment', BoolValue(ToggleBlockComment));
  AStore.WriteInteger('ToggleBlockCommentKey', ToggleBlockCommentKey);
  AStore.WriteString('ToggleBlockCommentStyle', ToggleBlockCommentStyle);
  AStore.WriteString('ToggleBlockCommentFallback', ToggleBlockCommentFallback);
  AStore.WriteInteger('ToggleBlockCommentOwnLines', BoolValue(ToggleBlockCommentOwnLines));
  AStore.WriteString('ToggleBlockCommentWithoutSelection', ToggleBlockCommentWithoutSelection);
  AStore.WriteInteger('NewLineAround', BoolValue(NewLineAround));
  AStore.WriteInteger('NewLineBelowKey', NewLineBelowKey);
  AStore.WriteInteger('NewLineAboveKey', NewLineAboveKey);
  AStore.WriteInteger('NewLineAroundStatementAware', BoolValue(NewLineAroundStatementAware));
  AStore.WriteInteger('Unwrap', BoolValue(Unwrap));
  AStore.WriteInteger('UnwrapKey', UnwrapKey);
  AStore.WriteInteger('NextChangeKey', NextChangeKey);
  AStore.WriteInteger('PreviousChangeKey', PreviousChangeKey);
  AStore.WriteInteger('OverviewRuler', BoolValue(OverviewRuler));
  AStore.WriteString('OverviewRulerKinds', OverviewRulerKinds);
  AStore.WriteInteger('JumpToMatch', BoolValue(JumpToMatch));
  AStore.WriteInteger('JumpToMatchKey', JumpToMatchKey);
  AStore.WriteInteger('JumpToMatchSelectKey', JumpToMatchSelectKey);
  AStore.WriteInteger('MoveLines', BoolValue(MoveLines));
  AStore.WriteInteger('MoveLinesUpKey', MoveLinesUpKey);
  AStore.WriteInteger('MoveLinesDownKey', MoveLinesDownKey);
  AStore.WriteInteger('DuplicateLinesUpKey', DuplicateLinesUpKey);
  AStore.WriteInteger('DuplicateLinesDownKey', DuplicateLinesDownKey);
  AStore.WriteInteger('ContinueComments', BoolValue(ContinueComments));
  AStore.WriteInteger('ContinueCommentsLineComments', BoolValue(ContinueCommentsLineComments));
  AStore.WriteInteger('ContinueCommentsLists', BoolValue(ContinueCommentsLists));
  AStore.WriteString('ContinueCommentsBlockPrefix', ContinueCommentsBlockPrefix);
  AStore.WriteInteger('WrapSelection', BoolValue(WrapSelection));
  AStore.WriteString('WrapSelectionChars', WrapSelectionChars);
  AStore.WriteInteger('CompleteStatement', BoolValue(CompleteStatement));
  AStore.WriteInteger('CompleteStatementKey', CompleteStatementKey);
  AStore.WriteString('CompleteStatementBeginEnd', CompleteStatementBeginEnd);
  AStore.WriteString('CompleteStatementTryKind', CompleteStatementTryKind);
  AStore.WriteInteger('CompleteStatementMethodBody', BoolValue(CompleteStatementMethodBody));
  AStore.WriteInteger('FormatCode', BoolValue(FormatCode));
  AStore.WriteInteger('FormatCodeKey', FormatCodeKey);
  AStore.WriteInteger('ContinuePattern', BoolValue(ContinuePattern));
  AStore.WriteInteger('ContinuePatternMinLines', ContinuePatternMinLines);
  AStore.WriteInteger('MultiCursor', BoolValue(MultiCursor));
  AStore.WriteInteger('LinkedEditing', BoolValue(LinkedEditing));
  AStore.WriteString('MultiCursorModifier', MultiCursorModifier);
  AStore.WriteString('SmartPaste', SmartPaste);
  AStore.WriteInteger('MultiCursorNextKey', MultiCursorNextKey);
  AStore.WriteInteger('MultiCursorSkipKey', MultiCursorSkipKey);
  AStore.WriteInteger('MultiCursorLineEndsKey', MultiCursorLineEndsKey);
  AStore.WriteInteger('MultiCursorAboveKey', MultiCursorAboveKey);
  AStore.WriteInteger('MultiCursorBelowKey', MultiCursorBelowKey);
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
  AStore.WriteInteger('WelcomePageProjectSetup', BoolValue(WelcomePageProjectSetup));
  AStore.WriteInteger('WelcomePageNewFromTemplate', BoolValue(WelcomePageNewFromTemplate));
  AStore.WriteInteger('WelcomePageContinue', BoolValue(WelcomePageContinue));
  AStore.WriteInteger('WelcomePageContinueCount', WelcomePageContinueCount);
  AStore.WriteInteger('WelcomePageContinueIncoming', BoolValue(WelcomePageContinueIncoming));
  AStore.WriteInteger('WelcomePageContinueFetch', BoolValue(WelcomePageContinueFetch));
  AStore.WriteInteger('WelcomePageSaved', BoolValue(WelcomePageSaved));
  AStore.WriteInteger('WelcomePageTrends', BoolValue(WelcomePageTrends));
  AStore.WriteInteger('WelcomePageTrendsPoints', WelcomePageTrendsPoints);
  AStore.WriteString('WelcomePageTrendsSeries', WelcomePageTrendsSeries);
  AStore.WriteInteger('WelcomePageTests', BoolValue(WelcomePageTests));
  AStore.WriteInteger('WelcomePageTestsMaxFailures', WelcomePageTestsMaxFailures);
  AStore.WriteInteger('WelcomePageTestsCi', BoolValue(WelcomePageTestsCi));
  AStore.WriteString('WelcomePageTestsCiProvider', WelcomePageTestsCiProvider);
  AStore.WriteInteger('WelcomePageTestsCiIntervalMinutes', WelcomePageTestsCiIntervalMinutes);
  AStore.WriteInteger('WelcomePageTestsCiNotify', BoolValue(WelcomePageTestsCiNotify));
  AStore.WriteInteger('CiLogin', BoolValue(CiLogin));
  AStore.WriteInteger('WelcomePageQuickActions', BoolValue(WelcomePageQuickActions));
  AStore.WriteString('WelcomePageQuickActionsItems', WelcomePageQuickActionsItems);
  AStore.WriteString('WelcomePageQuickActionsConsole', WelcomePageQuickActionsConsole);
  AStore.WriteInteger('WelcomePageQuickActionsBuildKey', WelcomePageQuickActionsBuildKey);
  AStore.WriteInteger('WelcomePageQuickActionsTestKey', WelcomePageQuickActionsTestKey);
  AStore.WriteInteger('WelcomePageIssues', BoolValue(WelcomePageIssues));
  AStore.WriteString('WelcomePageIssuesTracker', WelcomePageIssuesTracker);
  AStore.WriteString('WelcomePageIssuesQuery', WelcomePageIssuesQuery);
  AStore.WriteString('WelcomePageIssuesStart', WelcomePageIssuesStart);
  AStore.WriteString('WelcomePageIssuesBranchPattern', WelcomePageIssuesBranchPattern);
  AStore.WriteString('WelcomePageIssuesBranchBase', WelcomePageIssuesBranchBase);
  AStore.WriteString('WelcomePageIssuesCommitPattern', WelcomePageIssuesCommitPattern);
  AStore.WriteInteger('TrackerLogin', BoolValue(TrackerLogin));
  AStore.WriteInteger('WelcomePageCustomLayout', BoolValue(WelcomePageCustomLayout));
  AStore.WriteInteger('WelcomePageColumns', WelcomePageColumns);
  AStore.WriteString('WelcomePageLayouts', WelcomePageLayouts);
  AStore.WriteString('WelcomePageActiveLayout', WelcomePageActiveLayout);
  AStore.WriteInteger('Notifications', BoolValue(Notifications));
  AStore.WriteString('NotificationsSources', NotificationsSources);
  AStore.WriteInteger('NotificationsMaxEntries', NotificationsMaxEntries);
  AStore.WriteInteger('NotificationsKey', NotificationsKey);
  AStore.WriteInteger('SettingsExportImport', BoolValue(SettingsExportImport));
  AStore.WriteInteger('SettingsMarkModified', BoolValue(SettingsMarkModified));
  AStore.WriteInteger('SettingsBackupBeforeImport', BoolValue(SettingsBackupBeforeImport));
  AStore.WriteString('SettingsExportSecrets', SettingsExportSecrets);
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
