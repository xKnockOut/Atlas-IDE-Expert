unit Atlas.Core.Settings.Plugin.Editor;

// Einstellungen des IDE-Plugins, Bereich Editor (editor.*, Navigation, Suche, Hinweise) (#227, ADR 0017):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

const
  cMaxXmlDocLines = 50;
  /// <summary>Grenze für hover.membersMaxLines (#1841).</summary>
  cMaxHoverMembersLines = 100;
  cMinPeekLines = 5;
  cMaxPeekLines = 60;
  /// <summary>Grenzen für navigation.impactDepth (#1120).</summary>
  cMinImpactDepth = 1;
  cMaxImpactDepth = 5;
  /// <summary>Grenzen für navigation.dataFlow.maxDepth (#690).</summary>
  cMinDataFlowDepth = 1;
  cMaxDataFlowDepth = 20;
  /// <summary>Grenzen für editor.stickyScrollMaxLines (#506).</summary>
  cMinStickyLines = 1;
  cMaxStickyLines = 10;
  /// <summary>Grenzen für editor.stickyScrollBlockMinLines (#1230).</summary>
  cMinStickyBlockLines = 5;
  cMaxStickyBlockLines = 1000;
  /// <summary>Grenzen für editor.minimap.width, .scale und .maxColumn (#873).</summary>
  cMinMinimapWidth = 40;
  cMaxMinimapWidth = 400;
  cMinMinimapScale = 1;
  cMaxMinimapScale = 3;
  cMinMinimapColumn = 20;
  cMaxMinimapColumn = 500;
  /// <summary>Grenzen für editor.blockEndLabels.minLines (#620).</summary>
  cMinBlockEndLines = 1;
  cMaxBlockEndLines = 1000;
  /// <summary>Grenzen für editor.recursionMarkers.depth (#623); wie TRecursionAnalysis im Server.</summary>
  cMinRecursionDepth = 1;
  cMaxRecursionDepth = 16;
  /// <summary>Muster fortsetzen (#671): Mindestzahl gleichförmiger Zeilen.</summary>
  cMinPatternLines = 2;
  cMaxPatternLines = 5;
  /// <summary>Grenzen für undo.multiFile.depth und undo.multiFile.maxSizeMb (#721).</summary>
  cMinUndoDepth = 1;
  cMaxUndoDepth = 200;
  cMinUndoMaxSizeMb = 1;
  cMaxUndoMaxSizeMb = 1024;
  /// <summary>search.history (#893): Vorgabe und Höchstwert.</summary>
  cDefaultSearchHistory = 20;
  cMaxSearchHistory = 100;
  /// <summary>Werte von editor.completeStatement.beginEnd und .tryKind (#697).</summary>
  cBeginEndAlways = 'always';
  cBeginEndMultiLine = 'multiLine';
  cBeginEndNever = 'never';
  cTryKindFinally = 'finally';
  cTryKindExcept = 'except';
  cTryKindAsk = 'ask';
  /// <summary>Werte von editor.multiCursorModifier (#589): Taste für den Klick mit neuer Marke.</summary>
  cMultiCursorModifierAlt = 'alt';
  cMultiCursorModifierCtrl = 'ctrl';
  /// <summary>Werte von editor.designerBar.searchStyle (#1442).</summary>
  cDesignerSearchWindow = 'window';
  cDesignerSearchPopup = 'popup';
  /// <summary>Werte von designer.selectSimilar.scope (#738).</summary>
  cDesignerScopeForm = 'form';
  cDesignerScopeParent = 'parent';
  /// <summary>Werte von designer.selectionSets.storage (#739).</summary>
  cDesignerSetsLocal = 'local';
  cDesignerSetsShared = 'shared';
  /// <summary>Quellen von designer.fitToText.sources (#730).</summary>
  cFitSourceCaption = 'caption';
  cFitSourceText = 'text';
  cFitSourceItems = 'items';
  cMaxFitMinWidth = 2000;
  cMaxFitPadding = 200;

type
  /// <summary>Plugin-Einstellungen: Verhalten beim Tippen und Bearbeiten im Editor.</summary>
  TAtlasPluginEditorTypingSettings = record
    /// <summary>Eigener Hover-Tooltip (#442).</summary>
    HoverTooltip: Boolean;
    /// <summary>Extern geänderte Dateien ohne eigene Änderungen still neu laden (#536).</summary>
    ReloadExternal: Boolean;
    /// <summary>Änderungen des Servers an nicht geöffneten Dateien: im Editor öffnen (an) oder
    /// direkt auf die Platte schreiben (aus, #397).</summary>
    OpenForEdits: Boolean;
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
    /// <summary>Fehlertext am Zeilenende (#509): 'off', 'errors' (Vorgabe), 'errorsAndWarnings', 'all'; nur mit
    /// Problems.</summary>
    InlineDiagnostics: string;
    /// <summary>Marken folgen ihrer Zeile sofort bei Bearbeitungen (#1818, editor.trackLines).</summary>
    TrackLines: Boolean;
    /// <summary>Änderungsmarken in der Rinne (#507, editor.gitGutter).</summary>
    GitGutter: Boolean;
    /// <summary>Zeilenhistorie am Ende der Cursorzeile (#507, editor.gitBlame).</summary>
    GitBlame: Boolean;
    /// <summary>Reihenfolge der Methodenrümpfe (#660, editor.methodPlacement): grouped (Lebenszyklus, Get/Set-Paare,
    /// Überschreibungen, Rest; #1834), declaration oder alphabetical; off schaltet Verschieben und Befehl ab.
    /// </summary>
    MethodPlacement: string;
    /// <summary>Regionen beim Öffnen (#1814, editor.regionFolds): keep, collapse, expand oder off; off schaltet auch
    /// die Befehle „Alle Regionen zu-/aufklappen“ ab.</summary>
    RegionFolds: string;
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
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginEditorTypingSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

  /// <summary>Plugin-Einstellungen: Hinweise, Inlay-Hints, CodeLens, Probleme, Notizen und Rückgängig.</summary>
  TAtlasPluginEditorInsightSettings = record
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
    /// <summary>Marke „braucht kein Self“ hinter Methoden, die Self nicht brauchen (#686,
    /// refactoring.methodKindMarker).</summary>
    InlayMethodHints: Boolean;
    /// <summary>Persönliche Notizen an Codezeilen (#545): Symbol in der Rinne, Befehle und Liste; gespeichert in
    /// %LOCALAPPDATA%\Atlas\Notes\, nie im Quelltext.</summary>
    Notes: Boolean;
    /// <summary>Probleme im Editor unterstreichen und im Meldungsfenster auflisten (#398).</summary>
    Problems: Boolean;
    /// <summary>Aktionszeile im Befund-Hover (#909): Schnellkorrektur, für diese Zeile unterdrücken, Regel einstellen.
    /// </summary>
    HoverProblemActions: Boolean;
    /// <summary>Zeilen der published-Mitglieder im Hover ohne Scrollen (#1841, hover.membersMaxLines);
    /// 0 = bis zur Bildschirmhöhe.</summary>
    HoverMembersMaxLines: Integer;
    /// <summary>Parameter und Rückgabe im Hover immer offen, auch ohne XMLDoc (#1919, hover.signatureParams).
    /// </summary>
    HoverSignatureParams: Boolean;
    /// <summary>Zähler „Fehler/Warnungen/Hinweise“ in der Statusleiste (#509); Klick öffnet die Liste.</summary>
    ProblemsStatusCounter: Boolean;
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
    /// <summary>XMLDoc in Tooltip und Detailpanel beim Öffnen (#770, hints.xmlDocExpand in settings.json):
    /// collapsed, last (wie zuletzt), expanded. Ersetzt XmlDocFull (1 = expanded, 0 = collapsed).</summary>
    XmlDocExpand: string;
    /// <summary>Höchstens so viele Zeilen Doku ohne Scrollen, 0 = bis zur Bildschirmhöhe (#654).</summary>
    XmlDocMaxLines: Integer;
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
    /// <summary>Typ des markierten Ausdrucks (#689, hints.expressionType): Kürzel und Tooltip; aus = Kürzel frei,
    /// kein Menüeintrag.</summary>
    ExpressionType: Boolean;
    /// <summary>Implizite Umwandlungen im Tooltip nennen (#689).</summary>
    ExpressionTypeConversions: Boolean;
    /// <summary>Wert konstanter Ausdrücke im Tooltip zeigen (#689).</summary>
    ExpressionTypeConstValue: Boolean;
    /// <summary>Modul-Schalter designer.enabled (#1454): Designer-Werkzeuge; aus = die wirksamen Werte aller
    /// Einstellungen des Moduls sind
    /// „aus“ (TAtlasModuleSwitches), gespeichert bleiben sie.</summary>
    DesignerEnabled: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginEditorInsightSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

  /// <summary>Plugin-Einstellungen: Navigation, Suche, Gliederung, Peek und Referenzen.</summary>
  TAtlasPluginEditorNavigationSettings = record
    /// <summary>Atlas-Suche ersetzt die IDE-Suche (#878, search.replaceIdeSearch): Strg+F öffnet die Suchleiste
    /// unter dem Editor, F3/Umschalt+F3 springen in der zuletzt benutzten Atlas-Suche; aus = Suchen der IDE wie
    /// bisher. Vorgabe an.</summary>
    SearchReplaceIde: Boolean;
    /// <summary>Treffer der Atlas-Suche im Reiter „Atlas-Suche“ des Fensters Meldungen auflisten (#878,
    /// search.resultsInMessages; Enter bzw. „In Meldungen“ in der Suchleiste). Vorgabe an.</summary>
    SearchResultsInMessages: Boolean;
    /// <summary>Ersetzen-Zeile der Suchleiste und Strg+H (#893, search.replace); aus = keine Ersetzen-Zeile, Strg+H
    /// gehört der IDE. Vorgabe an.</summary>
    SearchReplace: Boolean;
    /// <summary>Option „.*“ (regulärer Ausdruck) und Vorschau in der Suchleiste (#893, search.regex). Vorgabe an.
    /// </summary>
    SearchRegex: Boolean;
    /// <summary>Länge des Such- und Ersetzen-Verlaufs (#893, search.history; 0 = kein Verlauf, Vorgabe 20).
    /// </summary>
    SearchHistory: Integer;
    /// <summary>Bereiche „Offene Dateien“, „Projekt“, „Projektgruppe“ in der Suchleiste (#893, search.multiFile).
    /// Vorgabe an.</summary>
    SearchMultiFile: Boolean;
    /// <summary>Beim Tippen zum ersten Treffer der Unit bzw. des Bereichs springen statt zum nächsten ab der
    /// Cursorposition (#1242, search.fromFirstHit). Vorgabe aus.</summary>
    SearchFromFirstHit: Boolean;
    /// <summary>Befehl „Weg zwischen Symbolen…“ mit Menü- und Kontextmenüeintrag (#1117, navigation.symbolPath in
    /// settings.json); Vorgabe an.</summary>
    SymbolPath: Boolean;
    /// <summary>Datei und Symbol schnell öffnen (#503, quickOpen.enabled): Fenster mit Präfixen @, #, :.</summary>
    QuickOpen: Boolean;
    /// <summary>Auch die Quellen von RTL/VCL ($(BDS)\source) auflisten (#503, quickOpen.librarySources).</summary>
    QuickOpenLibrary: Boolean;
    /// <summary>Navigationsverlauf über Dateien (#504, navHistory.enabled): Sprünge und Bearbeitungsstellen
    /// merken, Zurück/Vor, letzte Bearbeitungsstelle, Liste.</summary>
    NavHistory: Boolean;
    /// <summary>Definition und Referenzen einblenden (#505, peek.enabled).</summary>
    Peek: Boolean;
    /// <summary>Höhe des Peek-Fensters in Editorzeilen (#505, peek.heightLines), MinPeekLines bis
    /// MaxPeekLines.</summary>
    PeekHeightLines: Integer;
    /// <summary>Bei Routinen auch die Implementierung zeigen (#505, peek.showImplementation).</summary>
    PeekShowImplementation: Boolean;
    /// <summary>Erschlossene Verwendungen zeigen (#1119, references.inferred in settings.json).</summary>
    ReferencesInferred: Boolean;
    /// <summary>Namen in String-Literalen als erschlossene Verwendung (#1119, references.textMatches).</summary>
    ReferencesTextMatches: Boolean;
    /// <summary>Aufrufhierarchie auch als Diagramm (#1122, callHierarchy.diagram).</summary>
    CallHierarchyDiagram: Boolean;
    /// <summary>Befehl „Auswirkungen anzeigen“ mit Menüeinträgen (#1120, navigation.impact in settings.json).</summary>
    Impact: Boolean;
    /// <summary>Vorgabe der Tiefe der Auswirkungsanalyse (#1120, navigation.impactDepth), MinImpactDepth bis
    /// MaxImpactDepth.</summary>
    ImpactDepth: Integer;
    /// <summary>„Woher kommt der Wert?“ und „Wohin geht der Wert?“ im Ergebnisfenster (#690,
    /// navigation.dataFlow).</summary>
    DataFlow: Boolean;
    /// <summary>Größte Tiefe beim Aufklappen (#690, navigation.dataFlow.maxDepth), MinDataFlowDepth bis
    /// MaxDataFlowDepth.</summary>
    DataFlowMaxDepth: Integer;
    /// <summary>Filter „Tests ausblenden“ zu Beginn an (#690, navigation.dataFlow.excludeTests).</summary>
    DataFlowExcludeTests: Boolean;
    /// <summary>Fenster „Gliederung“ (#537, outline.enabled).</summary>
    Outline: Boolean;
    /// <summary>Gliederung alphabetisch sortieren (#537, outline.alphabetical).</summary>
    OutlineAlphabetical: Boolean;
    /// <summary>Eintrag am Cursor hervorheben (#537, outline.followCursor).</summary>
    OutlineFollowCursor: Boolean;
    /// <summary>Bedingung des aktiven {$IFDEF}-Zweigs hinter dem Eintrag (#845, outline.conditions).</summary>
    OutlineConditions: Boolean;
    /// <summary>Modul-Schalter search.enabled (#1454): Suche (Atlas-Suche, Unitsuche, Abfragen); aus = die wirksamen
    /// Werte aller Einstellungen des Moduls sind
    /// „aus“ (TAtlasModuleSwitches), gespeichert bleiben sie.</summary>
    SearchEnabled: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginEditorNavigationSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

  /// <summary>Plugin-Einstellungen: Units suchen (unitSearch.*).</summary>
  TAtlasPluginUnitSearchSettings = record
    /// <summary>Hauptschalter für das Fenster „Units suchen“ (#777, unitSearch.enabled); Vorgabe an.</summary>
    UnitSearchEnabled: Boolean;
    /// <summary>Strg+F12 und Ansicht › Units öffnen das Atlas-Fenster statt des IDE-Dialogs (#777,
    /// unitSearch.replaceIdeDialog); Vorgabe an.</summary>
    UnitSearchReplaceIdeDialog: Boolean;
    /// <summary>Alt+F11 und Datei › Unit verwenden öffnen das Atlas-Fenster im Modus „Unit verwenden“ (#786,
    /// unitSearch.replaceUseUnitDialog); Vorgabe an.</summary>
    UnitSearchReplaceUseUnitDialog: Boolean;
    /// <summary>Umschalt+F12 und Ansicht › Formulare öffnen das Atlas-Fenster mit Filter Formulare (#786,
    /// unitSearch.replaceFormsDialog); Vorgabe an.</summary>
    UnitSearchReplaceFormsDialog: Boolean;
    /// <summary>Eingeklappte Gruppen je Projektgruppe merken (#777, unitSearch.rememberCollapsed); Vorgabe
    /// an.</summary>
    UnitSearchRememberCollapsed: Boolean;
    /// <summary>Chipzeile mit Herkunft und Art (#777, unitSearch.filters); Vorgabe an.</summary>
    UnitSearchFilters: Boolean;
    /// <summary>Tippsyntax p:/t: im Suchfeld (#777, unitSearch.filterSyntax); Vorgabe an.</summary>
    UnitSearchFilterSyntax: Boolean;
    /// <summary>Formulare auch über ihre Caption finden (#1310, unitSearch.formCaptions); Vorgabe an.</summary>
    UnitSearchFormCaptions: Boolean;
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
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginUnitSearchSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

  /// <summary>Plugin-Einstellungen: Sticky Scroll und Brotkrumen.</summary>
  TAtlasPluginStickyScrollSettings = record
    /// <summary>Brotkrumenleiste über dem Editor (#590, editor.breadcrumbs).</summary>
    Breadcrumbs: Boolean;
    /// <summary>Unit-Namen als erstes Glied (#590, editor.breadcrumbsShowUnit).</summary>
    BreadcrumbsShowUnit: Boolean;
    /// <summary>Sichtbarkeitsabschnitt als Glied hinter dem Typ (#1759, editor.breadcrumbsVisibility).</summary>
    BreadcrumbsVisibility: Boolean;
    /// <summary>Unterblock (const, type, class var) als Glied (#1767, editor.breadcrumbsMemberBlocks).</summary>
    BreadcrumbsMemberBlocks: Boolean;
    /// <summary>Sichtbarkeitsmarke am Methodenglied im implementation-Teil (#1765,
    /// editor.breadcrumbsVisibilityMark).</summary>
    BreadcrumbsVisibilityMark: Boolean;
    /// <summary>Deklarationsblock der Unit als Glied (#1766, editor.breadcrumbsDeclarationBlocks).</summary>
    BreadcrumbsDeclarationBlocks: Boolean;
    /// <summary>Bedingungszweig ({$IFDEF …}) als Glied (#1763, editor.breadcrumbsConditionals).</summary>
    BreadcrumbsConditionals: Boolean;
    /// <summary>Region ({$REGION}) als Glied (#1764, editor.breadcrumbsRegions).</summary>
    BreadcrumbsRegions: Boolean;
    /// <summary>try/except/finally und case-Zweig als Glied (#1769, editor.breadcrumbsStatements).</summary>
    BreadcrumbsStatements: Boolean;
    /// <summary>Mitgliederzahl je Abschnitt im Menü des Sichtbarkeitsglieds (#1768,
    /// editor.breadcrumbsSectionCounts).</summary>
    BreadcrumbsSectionCounts: Boolean;
    /// <summary>Einträge „Neue Zeile am Ende von …“ im Menü des Sichtbarkeitsglieds (#1768,
    /// editor.breadcrumbsSectionAppend); auch Befehl und Taste keys.sectionAppend.</summary>
    BreadcrumbsSectionAppend: Boolean;
    /// <summary>Einträge „Abschnitt anlegen: …“ für fehlende Abschnitte (#1768,
    /// editor.breadcrumbsSectionCreate).</summary>
    BreadcrumbsSectionCreate: Boolean;
    /// <summary>Rechtsklick-Menü an den Gliedern der Leiste (#1786, editor.breadcrumbsContextMenu).</summary>
    BreadcrumbsContextMenu: Boolean;
    /// <summary>Zähler und Parameter bei Überladungen (#1784, editor.breadcrumbsOverloads).</summary>
    BreadcrumbsOverloads: Boolean;
    /// <summary>Interface-Marke an Methodengliedern (#1785, editor.breadcrumbsInterfaces).</summary>
    BreadcrumbsInterfaces: Boolean;
    /// <summary>Kennzahlen-Karte an Methoden- und Typgliedern (#1787, editor.breadcrumbsMetrics).</summary>
    BreadcrumbsMetrics: Boolean;
    /// <summary>Brotkrumenleiste in den Farben der IDE-Werkzeugleisten statt der Atlas-Palette
    /// (editor.breadcrumbsIdeColors).</summary>
    BreadcrumbsIdeColors: Boolean;
    /// <summary>Navigationsleiste der IDE („Typ suchen“/„Methode suchen“) ausblenden, solange die
    /// Brotkrumenleiste an ist (editor.breadcrumbsHideIdeToolbar).</summary>
    BreadcrumbsHideIdeToolbar: Boolean;
    /// <summary>Mitlaufender Kopf (#506, editor.stickyScroll, experimentell).</summary>
    StickyScroll: Boolean;
    /// <summary>Höchstzahl seiner Zeilen, MinStickyLines bis MaxStickyLines (#506,
    /// editor.stickyScrollMaxLines).</summary>
    StickyScrollMaxLines: Integer;
    /// <summary>Was der Kopf zeigt (editor.stickyScrollTypes, …Routines): Klassen/Records und Routinen der
    /// Gliederung.</summary>
    StickyScrollTypes: Boolean;
    StickyScrollRoutines: Boolean;
    /// <summary>Große if/else-Blöcke im Kopf (#1230, editor.stickyScrollBlocks).</summary>
    StickyScrollBlocks: Boolean;
    /// <summary>Weitere große Anweisungsblöcke im Kopf: for/while/repeat, try, case, with
    /// (editor.stickyScrollLoops, …Try, …Case, …With).</summary>
    StickyScrollLoops: Boolean;
    StickyScrollTry: Boolean;
    StickyScrollCase: Boolean;
    StickyScrollWith: Boolean;
    /// <summary>Mindestlänge solcher Blöcke in Zeilen, MinStickyBlockLines bis MaxStickyBlockLines (#1230,
    /// editor.stickyScrollBlockMinLines).</summary>
    StickyScrollBlockMinLines: Integer;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginStickyScrollSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

  /// <summary>Plugin-Einstellungen: Minimap, Werkzeugleisten, Statusleiste, Randspalte und Übersichtslineal.</summary>
  TAtlasPluginEditorViewSettings = record
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
    /// <summary>Atlas-Statusleiste unten am Editor (#1155, editor.statusBar); Hauptschalter. Mit dem Element status
    /// zieht das Atlas-Feld aus der Statuszeile der IDE in die Leiste.</summary>
    EditorStatusBar: Boolean;
    /// <summary>Sichtbare Elemente in Reihenfolge: status, findings, liveCheck, method, durch Komma getrennt (#1155,
    /// editor.statusBar.items); leer = keine.</summary>
    EditorStatusBarItems: string;
    /// <summary>Designer-Leiste im Formular-Designer statt Brotkrumen und Editorleiste (#1442,
    /// editor.designerBar): Komponenten suchen, Nichtvisuelle (Strg+H der IDE), Elternelement, Tab-Reihenfolge,
    /// Ausrichten.</summary>
    EditorDesignerBar: Boolean;
    /// <summary>Taste für „Komponenten suchen“ im Designer (TShortCut, editor.designerBar.searchKey); 0 = keine.
    /// </summary>
    DesignerSearchKey: Integer;
    /// <summary>Fenster „Komponenten suchen“: DesignerSearchWindow (groß mit Vorschau) oder DesignerSearchPopup
    /// (klein wie Strg+P), editor.designerBar.searchStyle.</summary>
    DesignerSearchStyle: string;
    /// <summary>Tab-Reihenfolge per Klick auf die Nummern neu vergeben (experimentell,
    /// editor.designerBar.tabOrderClick).</summary>
    DesignerTabOrderClick: Boolean;
    /// <summary>Knopf „Ausrichten“ mit Menü (experimentell, editor.designerBar.align).</summary>
    DesignerAlign: Boolean;
    /// <summary>Menü „Gleiche auswählen“ in der Designer-Leiste (#738, designer.selectSimilar).</summary>
    DesignerSelectSimilar: Boolean;
    /// <summary>Eintrag „Gleiche Klasse und Nachfahren“ (#738, designer.selectSimilar.includeDescendants).</summary>
    DesignerSelectDescendants: Boolean;
    /// <summary>Bereich: cDesignerScopeForm oder cDesignerScopeParent (#738, designer.selectSimilar.scope).
    /// </summary>
    DesignerSelectScope: string;
    /// <summary>Auswahlsätze im Designer (#739, designer.selectionSets).</summary>
    DesignerSelectionSets: Boolean;
    /// <summary>Strg+Umschalt+1…9 für die ersten neun Sätze (#739, designer.selectionSets.shortcuts).</summary>
    DesignerSelectionSetsShortcuts: Boolean;
    /// <summary>Ablage: cDesignerSetsLocal oder cDesignerSetsShared (#739, designer.selectionSets.storage).</summary>
    DesignerSelectionSetsStorage: string;
    /// <summary>Taste „Auswahl speichern …“ als TShortCut, 0 = keine (#739, designer.selectionSets.saveKey).</summary>
    DesignerSelectionSetsSaveKey: Integer;
    /// <summary>Räumliche Navigation mit Alt+Pfeil (#745, designer.spatialNavigation).</summary>
    DesignerSpatialNavigation: Boolean;
    /// <summary>Am Rand in benachbarte Container weiter (#745, designer.spatialNavigation.crossContainers).
    /// </summary>
    DesignerSpatialCrossContainers: Boolean;
    /// <summary>Befehl „Breite nach Text“ (#730, designer.fitToText).</summary>
    DesignerFitToText: Boolean;
    /// <summary>Mindestbreite bei 96 dpi (#730, designer.fitToText.minWidth).</summary>
    DesignerFitToTextMinWidth: Integer;
    /// <summary>Innenabstand links und rechts zusammen (#730, designer.fitToText.padding).</summary>
    DesignerFitToTextPadding: Integer;
    /// <summary>Textquellen caption, text, items durch Komma (#730, designer.fitToText.sources).</summary>
    DesignerFitToTextSources: string;
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
    /// <summary>Atlas-Spalte in der Zeilenleiste (#768, editor.gutterColumn).</summary>
    GutterColumn: Boolean;
    /// <summary>Problemsymbole in der Spalte (#768, editor.gutterColumn.problems).</summary>
    GutterColumnProblems: Boolean;
    /// <summary>Glühbirne für Code-Aktionen der Cursorzeile (#768, editor.gutterColumn.codeActions).</summary>
    GutterColumnCodeActions: Boolean;
    /// <summary>„überschreibt“/„wird überschrieben“ an Methoden (#768, editor.gutterColumn.overrides).</summary>
    GutterColumnOverrides: Boolean;
    /// <summary>Übersichtsleiste an der Scrollleiste (#519, editor.overviewRuler).</summary>
    OverviewRuler: Boolean;
    /// <summary>Arten der Übersichtsleiste, kommagetrennt (#519, editor.overviewRulerKinds); siehe
    /// TAtlasOverviewKindNames.</summary>
    OverviewRulerKinds: string;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginEditorViewSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  Atlas.Core.Settings.OverviewKinds,
  Atlas.Core.Settings.StatusBarItems,
  Atlas.Core.Settings.ToolbarItems;

/// <summary>XmlDocExpand lesen; fehlt der Wert, gilt XmlDocFull von vor #770, sonst ADefault.</summary>
function ReadXmlDocExpand(const AStore: IAtlasSettingsStore; const ADefault: string): string;
begin
  Result := AStore.ReadString('XmlDocExpand', '');
  // Vor #770: XmlDocFull übernehmen.
  if Result = '' then
  begin
    case AStore.ReadInteger('XmlDocFull', -1) of
      0:
        Result := 'collapsed';
      1:
        Result := 'expanded';
    else
      Result := ADefault;
    end;
  end;
end;

/// <summary>Präfix für Blockkommentare (#696): Steuerzeichen werden Leerzeichen, höchstens acht Zeichen; Leerraum
/// am Rand bleibt (' * ').</summary>
function NormalizedBlockPrefix(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := Copy(AText, 1, 8);
  for mIndex := 1 to Length(Result) do
  begin
    if Ord(Result[mIndex]) < 32 then
    begin
      Result[mIndex] := ' ';
    end;
  end;
  // Nur Leerraum ist kein Präfix.
  if Trim(Result) = '' then
  begin
    Result := '';
  end;
end;

{ TAtlasPluginEditorTypingSettings }

class function TAtlasPluginEditorTypingSettings.Defaults: TAtlasPluginEditorTypingSettings;
begin
  Result.HoverTooltip := True;
  Result.ReloadExternal := True;
  Result.OpenForEdits := True;
  Result.BlockEndLabels := True;
  Result.BlockEndLabelsMinLines := 25;
  Result.DimUnusedUses := True;
  Result.RecursionMarkers := True;
  Result.RecursionMarkersDepth := 4;
  Result.InlineDiagnostics := 'errors';
  Result.TrackLines := True;
  Result.GitGutter := True;
  Result.GitBlame := False;
  Result.MethodPlacement := 'grouped';
  Result.RegionFolds := 'keep';
  Result.ContinueComments := True;
  Result.ContinueCommentsLineComments := True;
  Result.ContinueCommentsLists := True;
  Result.ContinueCommentsBlockPrefix := '';
  Result.WrapSelection := True;
  Result.WrapSelectionChars := '([{''';
  Result.CompleteStatement := True;
  Result.CompleteStatementBeginEnd := cBeginEndMultiLine;
  Result.CompleteStatementTryKind := cTryKindFinally;
  Result.CompleteStatementMethodBody := True;
  Result.FormatCode := True;
  Result.ContinuePattern := True;
  Result.ContinuePatternMinLines := 2;
  Result.MultiCursor := False;
  Result.LinkedEditing := False;
  Result.SmartPaste := 'off';
  Result.MultiCursorModifier := cMultiCursorModifierAlt;
end;

procedure TAtlasPluginEditorTypingSettings.Normalize;
begin
  BlockEndLabelsMinLines := EnsureRange(BlockEndLabelsMinLines, cMinBlockEndLines, cMaxBlockEndLines);
  RecursionMarkersDepth := EnsureRange(RecursionMarkersDepth, cMinRecursionDepth, cMaxRecursionDepth);
  ContinuePatternMinLines := EnsureRange(ContinuePatternMinLines, cMinPatternLines, cMaxPatternLines);
  MethodPlacement := Choice(MethodPlacement, cAtlasMethodPlacements);
  RegionFolds := Choice(RegionFolds, cAtlasRegionFoldModes);
  ContinueCommentsBlockPrefix := NormalizedBlockPrefix(ContinueCommentsBlockPrefix);
  CompleteStatementBeginEnd := Choice(CompleteStatementBeginEnd, [cBeginEndMultiLine, cBeginEndAlways, cBeginEndNever]);
  CompleteStatementTryKind := Choice(CompleteStatementTryKind, [cTryKindFinally, cTryKindExcept, cTryKindAsk]);
  MultiCursorModifier := Choice(MultiCursorModifier, [cMultiCursorModifierAlt, cMultiCursorModifierCtrl]);
  SmartPaste := Choice(SmartPaste, ['off', 'uses', 'indent', 'both']);
  InlineDiagnostics := Choice(InlineDiagnostics, ['errors', 'off', 'errorsAndWarnings', 'all']);
end;

procedure TAtlasPluginEditorTypingSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('HoverTooltip', HoverTooltip);
  AIo.Flag('ReloadExternal', ReloadExternal);
  AIo.Flag('OpenForEdits', OpenForEdits);
  AIo.Flag('BlockEndLabels', BlockEndLabels);
  AIo.Number('BlockEndLabelsMinLines', BlockEndLabelsMinLines);
  AIo.Flag('DimUnusedUses', DimUnusedUses);
  AIo.Flag('RecursionMarkers', RecursionMarkers);
  AIo.Number('RecursionMarkersDepth', RecursionMarkersDepth);
  AIo.Text('InlineDiagnostics', InlineDiagnostics);
  AIo.Flag('TrackLines', TrackLines);
  AIo.Flag('GitGutter', GitGutter);
  AIo.Flag('GitBlame', GitBlame);
  AIo.Text('MethodPlacement', MethodPlacement);
  AIo.Text('RegionFolds', RegionFolds);
  AIo.Flag('ContinueComments', ContinueComments);
  AIo.Flag('ContinueCommentsLineComments', ContinueCommentsLineComments);
  AIo.Flag('ContinueCommentsLists', ContinueCommentsLists);
  AIo.Text('ContinueCommentsBlockPrefix', ContinueCommentsBlockPrefix);
  AIo.Flag('WrapSelection', WrapSelection);
  AIo.Text('WrapSelectionChars', WrapSelectionChars);
  AIo.Flag('CompleteStatement', CompleteStatement);
  AIo.Text('CompleteStatementBeginEnd', CompleteStatementBeginEnd);
  AIo.Text('CompleteStatementTryKind', CompleteStatementTryKind);
  AIo.Flag('CompleteStatementMethodBody', CompleteStatementMethodBody);
  AIo.Flag('FormatCode', FormatCode);
  AIo.Flag('ContinuePattern', ContinuePattern);
  AIo.Number('ContinuePatternMinLines', ContinuePatternMinLines);
  AIo.Flag('MultiCursor', MultiCursor);
  AIo.Flag('LinkedEditing', LinkedEditing);
  AIo.Text('SmartPaste', SmartPaste);
  AIo.Text('MultiCursorModifier', MultiCursorModifier);
end;

{ TAtlasPluginEditorInsightSettings }

class function TAtlasPluginEditorInsightSettings.Defaults: TAtlasPluginEditorInsightSettings;
begin
  Result.InlayHints := False;
  Result.InlayTypeHints := True;
  Result.InlayDefineHints := True;
  Result.InlayCharHints := True;
  Result.InlayMethodHints := True;
  Result.Notes := True;
  Result.Problems := True;
  Result.HoverProblemActions := True;
  Result.HoverMembersMaxLines := 15;
  Result.HoverSignatureParams := True;
  Result.ProblemsStatusCounter := True;
  Result.CodeLensTestUnit := True;
  Result.CodeLensMetrics := True;
  Result.Metrics := True;
  Result.CodeLensTests := True;
  Result.TodoList := True;
  Result.BaselineUpdate := True;
  Result.MetricsReport := True;
  Result.DfmPropertyRules := True;
  Result.XmlDocExpand := 'last';
  Result.XmlDocMaxLines := 0;
  Result.UndoMultiFile := True;
  Result.UndoMultiFileDepth := 20;
  Result.UndoMultiFilePersist := True;
  Result.UndoMultiFileMaxSizeMb := 50;
  Result.UndoMultiFileOnConflict := 'partial';
  Result.UndoMultiFileNewFiles := 'recycleBin';
  Result.ExpressionType := True;
  Result.ExpressionTypeConversions := True;
  Result.ExpressionTypeConstValue := True;
  Result.DesignerEnabled := True;
end;

procedure TAtlasPluginEditorInsightSettings.Normalize;
begin
  XmlDocMaxLines := EnsureRange(XmlDocMaxLines, 0, cMaxXmlDocLines);
  HoverMembersMaxLines := EnsureRange(HoverMembersMaxLines, 0, cMaxHoverMembersLines);
  XmlDocExpand := Choice(XmlDocExpand, ['last', 'collapsed', 'expanded']);
  UndoMultiFileDepth := EnsureRange(UndoMultiFileDepth, cMinUndoDepth, cMaxUndoDepth);
  UndoMultiFileMaxSizeMb := EnsureRange(UndoMultiFileMaxSizeMb, cMinUndoMaxSizeMb, cMaxUndoMaxSizeMb);
  if SameText(Trim(UndoMultiFileOnConflict), 'abort') then
  begin
    UndoMultiFileOnConflict := 'abort';
  end
  else
  begin
    UndoMultiFileOnConflict := 'partial';
  end;
  if SameText(Trim(UndoMultiFileNewFiles), 'delete') then
  begin
    UndoMultiFileNewFiles := 'delete';
  end
  else if SameText(Trim(UndoMultiFileNewFiles), 'keep') then
  begin
    UndoMultiFileNewFiles := 'keep';
  end
  else
  begin
    UndoMultiFileNewFiles := 'recycleBin';
  end;
end;

procedure TAtlasPluginEditorInsightSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('InlayHints', InlayHints);
  AIo.Flag('InlayTypeHints', InlayTypeHints);
  AIo.Flag('InlayDefineHints', InlayDefineHints);
  AIo.Flag('InlayCharHints', InlayCharHints);
  AIo.Flag('InlayMethodHints', InlayMethodHints);
  AIo.Flag('Notes', Notes);
  AIo.Flag('Problems', Problems);
  AIo.Flag('HoverProblemActions', HoverProblemActions);
  AIo.Number('HoverMembersMaxLines', HoverMembersMaxLines);
  AIo.Flag('HoverSignatureParams', HoverSignatureParams);
  AIo.Flag('ProblemsStatusCounter', ProblemsStatusCounter);
  AIo.Flag('CodeLensTestUnit', CodeLensTestUnit);
  AIo.Flag('CodeLensMetrics', CodeLensMetrics);
  AIo.Flag('Metrics', Metrics);
  AIo.Flag('CodeLensTests', CodeLensTests);
  AIo.Flag('TodoList', TodoList);
  AIo.Flag('BaselineUpdate', BaselineUpdate);
  AIo.Flag('MetricsReport', MetricsReport);
  AIo.Flag('DfmPropertyRules', DfmPropertyRules);
  if AIo.Writing then
  begin
    AIo.Text('XmlDocExpand', XmlDocExpand);
  end
  else
  begin
    XmlDocExpand := ReadXmlDocExpand(AIo.Store, XmlDocExpand);
  end;
  AIo.Number('XmlDocMaxLines', XmlDocMaxLines);
  AIo.Flag('UndoMultiFile', UndoMultiFile);
  AIo.Number('UndoMultiFileDepth', UndoMultiFileDepth);
  AIo.Flag('UndoMultiFilePersist', UndoMultiFilePersist);
  AIo.Number('UndoMultiFileMaxSizeMb', UndoMultiFileMaxSizeMb);
  AIo.Text('UndoMultiFileOnConflict', UndoMultiFileOnConflict);
  AIo.Text('UndoMultiFileNewFiles', UndoMultiFileNewFiles);
  AIo.Flag('ExpressionType', ExpressionType);
  AIo.Flag('ExpressionTypeConversions', ExpressionTypeConversions);
  AIo.Flag('ExpressionTypeConstValue', ExpressionTypeConstValue);
  AIo.Flag('DesignerEnabled', DesignerEnabled);
end;

{ TAtlasPluginEditorNavigationSettings }

class function TAtlasPluginEditorNavigationSettings.Defaults: TAtlasPluginEditorNavigationSettings;
begin
  Result.SearchReplaceIde := True;
  Result.SearchResultsInMessages := True;
  Result.SearchReplace := True;
  Result.SearchRegex := True;
  Result.SearchHistory := cDefaultSearchHistory;
  Result.SearchMultiFile := True;
  Result.SearchFromFirstHit := False;
  Result.SymbolPath := True;
  Result.QuickOpen := True;
  Result.QuickOpenLibrary := False;
  Result.NavHistory := True;
  Result.Peek := True;
  Result.PeekHeightLines := 15;
  Result.PeekShowImplementation := True;
  Result.ReferencesInferred := True;
  Result.ReferencesTextMatches := False;
  Result.CallHierarchyDiagram := True;
  Result.Impact := True;
  Result.ImpactDepth := 2;
  Result.DataFlow := True;
  Result.DataFlowMaxDepth := 6;
  Result.DataFlowExcludeTests := False;
  Result.Outline := True;
  Result.OutlineAlphabetical := False;
  Result.OutlineFollowCursor := True;
  Result.OutlineConditions := True;
  Result.SearchEnabled := True;
end;

procedure TAtlasPluginEditorNavigationSettings.Normalize;
begin
  PeekHeightLines := EnsureRange(PeekHeightLines, cMinPeekLines, cMaxPeekLines);
  ImpactDepth := EnsureRange(ImpactDepth, cMinImpactDepth, cMaxImpactDepth);
  DataFlowMaxDepth := EnsureRange(DataFlowMaxDepth, cMinDataFlowDepth, cMaxDataFlowDepth);
  SearchHistory := EnsureRange(SearchHistory, 0, cMaxSearchHistory);
end;

procedure TAtlasPluginEditorNavigationSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('SearchReplaceIde', SearchReplaceIde);
  AIo.Flag('SearchResultsInMessages', SearchResultsInMessages);
  AIo.Flag('SearchReplace', SearchReplace);
  AIo.Flag('SearchRegex', SearchRegex);
  AIo.Number('SearchHistory', SearchHistory);
  AIo.Flag('SearchMultiFile', SearchMultiFile);
  AIo.Flag('SearchFromFirstHit', SearchFromFirstHit);
  AIo.Flag('SymbolPath', SymbolPath);
  AIo.Flag('QuickOpen', QuickOpen);
  AIo.Flag('QuickOpenLibrary', QuickOpenLibrary);
  AIo.Flag('NavHistory', NavHistory);
  AIo.Flag('Peek', Peek);
  AIo.Number('PeekHeightLines', PeekHeightLines);
  AIo.Flag('PeekShowImplementation', PeekShowImplementation);
  AIo.Flag('ReferencesInferred', ReferencesInferred);
  AIo.Flag('ReferencesTextMatches', ReferencesTextMatches);
  AIo.Flag('CallHierarchyDiagram', CallHierarchyDiagram);
  AIo.Flag('Impact', Impact);
  AIo.Number('ImpactDepth', ImpactDepth);
  AIo.Flag('DataFlow', DataFlow);
  AIo.Number('DataFlowMaxDepth', DataFlowMaxDepth);
  AIo.Flag('DataFlowExcludeTests', DataFlowExcludeTests);
  AIo.Flag('Outline', Outline);
  AIo.Flag('OutlineAlphabetical', OutlineAlphabetical);
  AIo.Flag('OutlineFollowCursor', OutlineFollowCursor);
  AIo.Flag('OutlineConditions', OutlineConditions);
  AIo.Flag('SearchEnabled', SearchEnabled);
end;

{ TAtlasPluginUnitSearchSettings }

class function TAtlasPluginUnitSearchSettings.Defaults: TAtlasPluginUnitSearchSettings;
begin
  Result.UnitSearchEnabled := True;
  Result.UnitSearchReplaceIdeDialog := True;
  Result.UnitSearchReplaceUseUnitDialog := True;
  Result.UnitSearchReplaceFormsDialog := True;
  Result.UnitSearchRememberCollapsed := True;
  Result.UnitSearchFilters := True;
  Result.UnitSearchFilterSyntax := True;
  Result.UnitSearchFormCaptions := True;
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
end;

procedure TAtlasPluginUnitSearchSettings.Normalize;
begin
  UnitSearchPathStyle := Choice(UnitSearchPathStyle, ['relative', 'compact', 'absolute']);
  UnitSearchGroupBy := Choice(UnitSearchGroupBy, ['project', 'folder', 'none']);
  UnitSearchDefaultScope := Choice(UnitSearchDefaultScope, ['group', 'project', 'searchPath', 'library']);
end;

procedure TAtlasPluginUnitSearchSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('UnitSearchEnabled', UnitSearchEnabled);
  AIo.Flag('UnitSearchReplaceIdeDialog', UnitSearchReplaceIdeDialog);
  AIo.Flag('UnitSearchReplaceUseUnitDialog', UnitSearchReplaceUseUnitDialog);
  AIo.Flag('UnitSearchReplaceFormsDialog', UnitSearchReplaceFormsDialog);
  AIo.Flag('UnitSearchRememberCollapsed', UnitSearchRememberCollapsed);
  AIo.Flag('UnitSearchFilters', UnitSearchFilters);
  AIo.Flag('UnitSearchFilterSyntax', UnitSearchFilterSyntax);
  AIo.Flag('UnitSearchFormCaptions', UnitSearchFormCaptions);
  AIo.Flag('UnitSearchPreview', UnitSearchPreview);
  AIo.Flag('UnitSearchPreviewForm', UnitSearchPreviewForm);
  AIo.Flag('UnitSearchPreviewUsedBy', UnitSearchPreviewUsedBy);
  AIo.Flag('UnitSearchPreviewAutoCollapse', UnitSearchPreviewAutoCollapse);
  AIo.Flag('UnitSearchMultiSelect', UnitSearchMultiSelect);
  AIo.Flag('UnitSearchActions', UnitSearchActions);
  AIo.Flag('UnitSearchActionsAddUses', UnitSearchActionsAddUses);
  AIo.Text('UnitSearchPathStyle', UnitSearchPathStyle);
  AIo.Text('UnitSearchGroupBy', UnitSearchGroupBy);
  AIo.Text('UnitSearchDefaultScope', UnitSearchDefaultScope);
end;

{ TAtlasPluginStickyScrollSettings }

class function TAtlasPluginStickyScrollSettings.Defaults: TAtlasPluginStickyScrollSettings;
begin
  Result.Breadcrumbs := True;
  Result.BreadcrumbsShowUnit := False;
  Result.BreadcrumbsVisibility := True;
  Result.BreadcrumbsMemberBlocks := True;
  Result.BreadcrumbsVisibilityMark := True;
  Result.BreadcrumbsDeclarationBlocks := True;
  Result.BreadcrumbsConditionals := True;
  Result.BreadcrumbsRegions := True;
  Result.BreadcrumbsStatements := False;
  Result.BreadcrumbsSectionCounts := True;
  Result.BreadcrumbsSectionAppend := True;
  Result.BreadcrumbsSectionCreate := True;
  Result.BreadcrumbsContextMenu := True;
  Result.BreadcrumbsOverloads := True;
  Result.BreadcrumbsInterfaces := True;
  Result.BreadcrumbsMetrics := True;
  Result.BreadcrumbsIdeColors := True;
  Result.BreadcrumbsHideIdeToolbar := True;
  Result.StickyScroll := True;
  Result.StickyScrollMaxLines := 3;
  Result.StickyScrollTypes := True;
  Result.StickyScrollRoutines := True;
  Result.StickyScrollBlocks := True;
  Result.StickyScrollLoops := False;
  Result.StickyScrollTry := False;
  Result.StickyScrollCase := False;
  Result.StickyScrollWith := False;
  Result.StickyScrollBlockMinLines := 25;
end;

procedure TAtlasPluginStickyScrollSettings.Normalize;
begin
  StickyScrollMaxLines := EnsureRange(StickyScrollMaxLines, cMinStickyLines, cMaxStickyLines);
  StickyScrollBlockMinLines := EnsureRange(StickyScrollBlockMinLines, cMinStickyBlockLines, cMaxStickyBlockLines);
end;

procedure TAtlasPluginStickyScrollSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('Breadcrumbs', Breadcrumbs);
  AIo.Flag('BreadcrumbsShowUnit', BreadcrumbsShowUnit);
  AIo.Flag('BreadcrumbsVisibility', BreadcrumbsVisibility);
  AIo.Flag('BreadcrumbsMemberBlocks', BreadcrumbsMemberBlocks);
  AIo.Flag('BreadcrumbsVisibilityMark', BreadcrumbsVisibilityMark);
  AIo.Flag('BreadcrumbsDeclarationBlocks', BreadcrumbsDeclarationBlocks);
  AIo.Flag('BreadcrumbsConditionals', BreadcrumbsConditionals);
  AIo.Flag('BreadcrumbsRegions', BreadcrumbsRegions);
  AIo.Flag('BreadcrumbsStatements', BreadcrumbsStatements);
  AIo.Flag('BreadcrumbsSectionCounts', BreadcrumbsSectionCounts);
  AIo.Flag('BreadcrumbsSectionAppend', BreadcrumbsSectionAppend);
  AIo.Flag('BreadcrumbsSectionCreate', BreadcrumbsSectionCreate);
  AIo.Flag('BreadcrumbsContextMenu', BreadcrumbsContextMenu);
  AIo.Flag('BreadcrumbsOverloads', BreadcrumbsOverloads);
  AIo.Flag('BreadcrumbsInterfaces', BreadcrumbsInterfaces);
  AIo.Flag('BreadcrumbsMetrics', BreadcrumbsMetrics);
  AIo.Flag('BreadcrumbsIdeColors', BreadcrumbsIdeColors);
  AIo.Flag('BreadcrumbsHideIdeToolbar', BreadcrumbsHideIdeToolbar);
  AIo.Flag('StickyScroll', StickyScroll);
  AIo.Number('StickyScrollMaxLines', StickyScrollMaxLines);
  AIo.Flag('StickyScrollTypes', StickyScrollTypes);
  AIo.Flag('StickyScrollRoutines', StickyScrollRoutines);
  AIo.Flag('StickyScrollBlocks', StickyScrollBlocks);
  AIo.Flag('StickyScrollLoops', StickyScrollLoops);
  AIo.Flag('StickyScrollTry', StickyScrollTry);
  AIo.Flag('StickyScrollCase', StickyScrollCase);
  AIo.Flag('StickyScrollWith', StickyScrollWith);
  AIo.Number('StickyScrollBlockMinLines', StickyScrollBlockMinLines);
end;

{ TAtlasPluginEditorViewSettings }

class function TAtlasPluginEditorViewSettings.Defaults: TAtlasPluginEditorViewSettings;
begin
  Result.EditorToolbar := True;
  Result.EditorToolbarPosition := 'belowBreadcrumbs';
  Result.EditorToolbarItems := TAtlasToolbarItems.DefaultText;
  Result.EditorToolbarReturnButton := True;
  Result.EditorToolbarLabels := False;
  Result.EditorStatusBar := True;
  Result.EditorStatusBarItems := TAtlasStatusBarItems.DefaultText;
  Result.EditorDesignerBar := True;
  // Alt+^ (VK_OEM_5 mit Alt).
  Result.DesignerSearchKey := 32988;
  Result.DesignerSearchStyle := cDesignerSearchWindow;
  Result.DesignerTabOrderClick := False;
  Result.DesignerAlign := False;
  Result.DesignerSelectSimilar := True;
  Result.DesignerSelectDescendants := True;
  Result.DesignerSelectScope := cDesignerScopeForm;
  Result.DesignerSelectionSets := True;
  Result.DesignerSelectionSetsShortcuts := True;
  Result.DesignerSelectionSetsStorage := cDesignerSetsLocal;
  // Strg+Umschalt+S.
  Result.DesignerSelectionSetsSaveKey := 24659;
  Result.DesignerSpatialNavigation := True;
  Result.DesignerSpatialCrossContainers := True;
  Result.DesignerFitToText := True;
  Result.DesignerFitToTextMinWidth := 75;
  Result.DesignerFitToTextPadding := 16;
  Result.DesignerFitToTextSources := cFitSourceCaption;
  Result.Minimap := False;
  Result.MinimapRender := 'characters';
  Result.MinimapWidth := 120;
  // 2: 4 Pixel je Zeile, Zeichen lesbar wie in VS Code (bei 1 kaum erkennbar).
  Result.MinimapScale := 2;
  Result.MinimapMaxColumn := 120;
  Result.MinimapSide := 'right';
  Result.MinimapShowSlider := 'always';
  Result.MinimapSectionHeaders := True;
  Result.MinimapHighlightMethod := True;
  Result.MinimapMarkers := True;
  Result.MinimapClickJumps := True;
  Result.MinimapNoticeShown := False;
  Result.GutterColumn := True;
  Result.GutterColumnProblems := True;
  Result.GutterColumnCodeActions := True;
  Result.GutterColumnOverrides := True;
  Result.OverviewRuler := True;
  Result.OverviewRulerKinds := TAtlasOverviewKindNames.Text(TAtlasOverviewKindNames.cAll);
end;

procedure TAtlasPluginEditorViewSettings.Normalize;
begin
  MinimapRender := Choice(MinimapRender, ['characters', 'blocks']);
  MinimapWidth := EnsureRange(MinimapWidth, cMinMinimapWidth, cMaxMinimapWidth);
  MinimapScale := EnsureRange(MinimapScale, cMinMinimapScale, cMaxMinimapScale);
  MinimapMaxColumn := EnsureRange(MinimapMaxColumn, cMinMinimapColumn, cMaxMinimapColumn);
  MinimapSide := Choice(MinimapSide, ['right', 'left']);
  MinimapShowSlider := Choice(MinimapShowSlider, ['always', 'mouseover']);
  EditorToolbarPosition := Choice(EditorToolbarPosition, ['belowBreadcrumbs', 'aboveBreadcrumbs', 'inBreadcrumbs']);
  EditorToolbarItems := TAtlasToolbarItems.Normalize(EditorToolbarItems);
  EditorStatusBarItems := TAtlasStatusBarItems.Normalize(EditorStatusBarItems);
  OverviewRulerKinds := TAtlasOverviewKindNames.Normalize(OverviewRulerKinds);
  DesignerSearchKey := EnsureRange(DesignerSearchKey, 0, $FFFF);
  DesignerSearchStyle := Choice(DesignerSearchStyle, [cDesignerSearchWindow, cDesignerSearchPopup]);
  DesignerSelectScope := Choice(DesignerSelectScope, [cDesignerScopeForm, cDesignerScopeParent]);
  DesignerSelectionSetsStorage := Choice(DesignerSelectionSetsStorage, [cDesignerSetsLocal, cDesignerSetsShared]);
  DesignerSelectionSetsSaveKey := EnsureRange(DesignerSelectionSetsSaveKey, 0, $FFFF);
  DesignerFitToTextMinWidth := EnsureRange(DesignerFitToTextMinWidth, 0, cMaxFitMinWidth);
  DesignerFitToTextPadding := EnsureRange(DesignerFitToTextPadding, 0, cMaxFitPadding);
end;

procedure TAtlasPluginEditorViewSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('EditorToolbar', EditorToolbar);
  AIo.Text('EditorToolbarPosition', EditorToolbarPosition);
  AIo.Text('EditorToolbarItems', EditorToolbarItems);
  AIo.Flag('EditorToolbarReturnButton', EditorToolbarReturnButton);
  AIo.Flag('EditorToolbarLabels', EditorToolbarLabels);
  AIo.Flag('EditorStatusBar', EditorStatusBar);
  AIo.Text('EditorStatusBarItems', EditorStatusBarItems);
  AIo.Flag('EditorDesignerBar', EditorDesignerBar);
  AIo.Number('DesignerSearchKey', DesignerSearchKey);
  AIo.Text('DesignerSearchStyle', DesignerSearchStyle);
  AIo.Flag('DesignerTabOrderClick', DesignerTabOrderClick);
  AIo.Flag('DesignerAlign', DesignerAlign);
  AIo.Flag('DesignerSelectSimilar', DesignerSelectSimilar);
  AIo.Flag('DesignerSelectDescendants', DesignerSelectDescendants);
  AIo.Text('DesignerSelectScope', DesignerSelectScope);
  AIo.Flag('DesignerSelectionSets', DesignerSelectionSets);
  AIo.Flag('DesignerSelectionSetsShortcuts', DesignerSelectionSetsShortcuts);
  AIo.Text('DesignerSelectionSetsStorage', DesignerSelectionSetsStorage);
  AIo.Number('DesignerSelectionSetsSaveKey', DesignerSelectionSetsSaveKey);
  AIo.Flag('DesignerSpatialNavigation', DesignerSpatialNavigation);
  AIo.Flag('DesignerSpatialCrossContainers', DesignerSpatialCrossContainers);
  AIo.Flag('DesignerFitToText', DesignerFitToText);
  AIo.Number('DesignerFitToTextMinWidth', DesignerFitToTextMinWidth);
  AIo.Number('DesignerFitToTextPadding', DesignerFitToTextPadding);
  AIo.Text('DesignerFitToTextSources', DesignerFitToTextSources);
  AIo.Flag('Minimap', Minimap);
  AIo.Text('MinimapRender', MinimapRender);
  AIo.Number('MinimapWidth', MinimapWidth);
  AIo.Number('MinimapScale', MinimapScale);
  AIo.Number('MinimapMaxColumn', MinimapMaxColumn);
  AIo.Text('MinimapSide', MinimapSide);
  AIo.Text('MinimapShowSlider', MinimapShowSlider);
  AIo.Flag('MinimapSectionHeaders', MinimapSectionHeaders);
  AIo.Flag('MinimapHighlightMethod', MinimapHighlightMethod);
  AIo.Flag('MinimapMarkers', MinimapMarkers);
  AIo.Flag('MinimapClickJumps', MinimapClickJumps);
  AIo.Flag('MinimapNoticeShown', MinimapNoticeShown);
  AIo.Flag('GutterColumn', GutterColumn);
  AIo.Flag('GutterColumnProblems', GutterColumnProblems);
  AIo.Flag('GutterColumnCodeActions', GutterColumnCodeActions);
  AIo.Flag('GutterColumnOverrides', GutterColumnOverrides);
  AIo.Flag('OverviewRuler', OverviewRuler);
  AIo.Text('OverviewRulerKinds', OverviewRulerKinds);
end;

end.
