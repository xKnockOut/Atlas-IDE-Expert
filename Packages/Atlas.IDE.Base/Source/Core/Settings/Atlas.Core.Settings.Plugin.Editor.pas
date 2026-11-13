unit Atlas.Core.Settings.Plugin.Editor;

// Einstellungen des IDE-Plugins, Bereich Editor (editor.*, Navigation, Suche, Hinweise) (#227):
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
  /// <summary>Vorgabe für designer.showInDesigner.key (#511): Umschalt+F12 (scShift + VK_F12).</summary>
  cDefaultShowInDesignerKey = $2000 + $7B;
  /// <summary>Vorgabe für designer.usages.key (#750): Umschalt+Alt+F7 (scShift + scAlt + VK_F7).</summary>
  cDefaultUsagesKey = $2000 + $8000 + $76;
  /// <summary>Werte von designer.usages.scope (#750).</summary>
  cDesignerUsagesUnit = 'unit';
  cDesignerUsagesProject = 'project';
  cDesignerUsagesGroup = 'projectGroup';
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
  /// <summary>Werte von designer.groups.memberClick (#744).</summary>
  cDesignerGroupsAltClick = 'altClick';
  cDesignerGroupsDoubleClick = 'doubleClick';
  /// <summary>Vorgabe von designer.inlineCaption.key: F2 (#748).</summary>
  cInlineCaptionKey = 113;
  /// <summary>Quellen von designer.fitToText.sources (#730).</summary>
  cFitSourceCaption = 'caption';
  cFitSourceText = 'text';
  cFitSourceItems = 'items';
  cMaxFitMinWidth = 2000;
  cMaxFitPadding = 200;
  /// <summary>Grenzen und Vorgabe von designer.undoSteps (#1887).</summary>
  cMinUndoSteps = 5;
  cMaxUndoSteps = 200;
  cDefaultUndoSteps = 50;
  /// <summary>Werte von designer.gapHandles.anchor (#734).</summary>
  cGapAnchorCenter = 'center';
  cGapAnchorFirst = 'first';
  cGapAnchorLast = 'last';
  /// <summary>Werte von designer.multiResize.mode (#737).</summary>
  cResizeModeDelta = 'delta';
  cResizeModeAlign = 'align';
  /// <summary>Werte von designer.selectionBar.mode (#735).</summary>
  cSelectionBarAuto = 'auto';
  cSelectionBarShortcut = 'shortcut';
  cMaxSelectionBarDelay = 5000;
  /// <summary>Werte von designer.buttonBar.position (#732).</summary>
  cButtonBarBottomRight = 'bottomRight';
  cButtonBarBottomLeft = 'bottomLeft';
  cButtonBarRightTop = 'rightTop';
  cButtonBarRightBottom = 'rightBottom';
  /// <summary>Werte von designer.labelPairs.newLabelPosition (#729).</summary>
  cLabelLeft = 'left';
  cLabelAbove = 'above';
  /// <summary>Werte von designer.arrangeForm.labelAlign (#731).</summary>
  cGridLabelLeft = 'left';
  cGridLabelRight = 'right';
  cGridLabelAbove = 'above';
  cMaxButtonBarSpace = 100;
  cMaxNearTolerance = 10;

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
    /// <summary>Compilermeldungen im Hover erklären (#54, hover.explainMessages): typische Ursache, Links
    /// „Erklären“ und „DocWiki“.</summary>
    HoverExplainMessages: Boolean;
    /// <summary>Link „Beispiel zeigen“ in der Aktionszeile des Befund-Hovers (#145, hover.ruleExamples): klappt
    /// Beschreibung und Beispiel falsch/richtig aus dem Regelkatalog auf.</summary>
    HoverRuleExamples: Boolean;
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
    /// <summary>Testabdeckung aus einem Bericht von DelphiCodeCoverage in der Rinne (#275, tests.coverage): je
    /// Zeile mit Code ein Balken, grün durchlaufen, rot nicht; dazu die Befehle „Testabdeckung laden …“ und
    /// „Testabdeckung ausblenden“.</summary>
    TestCoverage: Boolean;
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
    /// <summary>Zurück-/Vor-Taste der Maus blättern im Navigationsverlauf (#1889, navigation.mouseButtons).</summary>
    MouseNavButtons: Boolean;
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
    /// <summary>„Komponenten suchen“ auch unscharf: Zeichen in ihrer Reihenfolge (#539, designer.fuzzySearch).
    /// </summary>
    DesignerFuzzySearch: Boolean;
    /// <summary>Tab-Reihenfolge neu vergeben: Reihenfolge klicken, nach Lesereihenfolge sortieren (#603,
    /// editor.designerBar.tabOrderClick).</summary>
    DesignerTabOrderClick: Boolean;
    /// <summary>Tab-Reihenfolge beim ersten Zeigen eines Formulars einblenden (#603, designer.tabOrderOverlay).
    /// </summary>
    DesignerTabOrderOverlay: Boolean;
    /// <summary>Verschachtelte Tab-Reihenfolge als Pfad „2.1“ (#603, designer.tabOrderPaths).</summary>
    DesignerTabOrderPaths: Boolean;
    /// <summary>Tab-Reihenfolge je Container farbig mit Rahmen statt langer Pfade (designer.tabOrderColors).
    /// </summary>
    DesignerTabOrderColors: Boolean;
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
    /// <summary>Befehl „Im Designer zeigen“ im Code-Editor (#511, designer.showInDesigner).</summary>
    DesignerShowInDesigner: Boolean;
    /// <summary>Taste für „Im Designer zeigen“ als TShortCut, 0 = keine (#511, designer.showInDesigner.key).</summary>
    DesignerShowInDesignerKey: Integer;
    /// <summary>Eigenschaften in Formularen suchen (#524, designer.propertySearch).</summary>
    DesignerPropertySearch: Boolean;
    /// <summary>„Verwendungen im Code“ aus dem Designer (#750, designer.usages).</summary>
    DesignerUsages: Boolean;
    /// <summary>Zähler der Verwendungen im Atlas-Statusfeld (#750, designer.usages.statusCount).</summary>
    DesignerUsagesStatusCount: Boolean;
    /// <summary>Suchbereich: cDesignerUsagesUnit, …Project, …Group (#750, designer.usages.scope).</summary>
    DesignerUsagesScope: string;
    /// <summary>Taste im Designer als TShortCut, 0 = keine (#750, designer.usages.key).</summary>
    DesignerUsagesKey: Integer;
    /// <summary>Räumliche Navigation mit Alt+Pfeil (#745, designer.spatialNavigation).</summary>
    DesignerSpatialNavigation: Boolean;
    /// <summary>Am Rand in benachbarte Container weiter (#745, designer.spatialNavigation.crossContainers).
    /// </summary>
    DesignerSpatialCrossContainers: Boolean;
    /// <summary>Maßlinien beim Verschieben und bei Größenänderung (#605, designer.measureDistances).</summary>
    DesignerMeasureDistances: Boolean;
    /// <summary>Maße mit Alt zur Komponente unter der Maus (#605, designer.measureAltKey).</summary>
    DesignerMeasureAltKey: Boolean;
    /// <summary>Knopf „Größe ausprobieren“ (#606, designer.resizePreview).</summary>
    DesignerResizePreview: Boolean;
    /// <summary>Schnellwerte „1366x768, 1920x1080“ (#606, designer.resizePreviewSizes).</summary>
    DesignerResizePreviewSizes: string;
    /// <summary>Nadeln für Anchors, Flächen für Align (#606, designer.resizePreviewShowAnchors).</summary>
    DesignerResizePreviewShowAnchors: Boolean;
    /// <summary>Knopf „Skalierung und Texte“ (#607, designer.scalePreview).</summary>
    DesignerScalePreview: Boolean;
    /// <summary>Angebotene Skalierungen „100, 125, 150, 175, 200“ (#607, designer.scalePreviewLevels).</summary>
    DesignerScalePreviewLevels: string;
    /// <summary>Angebotene Bildschirme „1366x768, 1920x1080“ (#607, designer.scalePreviewScreens).</summary>
    DesignerScalePreviewScreens: string;
    /// <summary>Verlängerung bei „Lange Texte“ in Prozent (#607, designer.longTextFactor).</summary>
    DesignerLongTextFactor: Integer;
    /// <summary>Knopf „Sprechende Namen“ (#608, designer.nameSuggest).</summary>
    DesignerNameSuggest: Boolean;
    /// <summary>Quellen und Reihenfolge „caption, label, handler, dataField“ (#608, designer.nameSuggestSources).
    /// </summary>
    DesignerNameSuggestSources: string;
    /// <summary>Umlaute „replace“ oder „remove“ (#608, designer.nameSuggestUmlauts).</summary>
    DesignerNameSuggestUmlauts: string;
    /// <summary>Handler mit Standardnamen mit umbenennen (#608, designer.nameSuggestRenameHandlers).</summary>
    DesignerNameSuggestRenameHandlers: Boolean;
    /// <summary>Eigene Präfixe „TKlasse=präfix“ vor der eingebauten Tabelle (#608, designer.nameSuggestPrefixes).
    /// </summary>
    DesignerNameSuggestPrefixes: string;
    /// <summary>Knopf „Atlas-Struktur“ mit andockbarem Fenster (#609, designer.structure).</summary>
    DesignerStructure: Boolean;
    /// <summary>Symbole nichtvisueller Komponenten auf der Formularfläche ausblenden, solange das Fenster offen ist
    /// (#609, designer.structureHideOnForm).</summary>
    DesignerStructureHideOnForm: Boolean;
    /// <summary>Knopf „Datenbindung“ mit der Brotkrumenleiste unter dem Designer (#610, designer.dataBindings).
    /// </summary>
    DesignerDataBindings: Boolean;
    /// <summary>Knopf „In Frame auslagern“ (#611, designer.extractFrame).</summary>
    DesignerExtractFrame: Boolean;
    /// <summary>Knopf „Ereignis-Karte“ (#612, designer.eventMap).</summary>
    DesignerEventMap: Boolean;
    /// <summary>Befehl „Breite nach Text“ (#730, designer.fitToText).</summary>
    DesignerFitToText: Boolean;
    /// <summary>Mindestbreite bei 96 dpi (#730, designer.fitToText.minWidth).</summary>
    DesignerFitToTextMinWidth: Integer;
    /// <summary>Innenabstand links und rechts zusammen (#730, designer.fitToText.padding).</summary>
    DesignerFitToTextPadding: Integer;
    /// <summary>Textquellen caption, text, items durch Komma (#730, designer.fitToText.sources).</summary>
    DesignerFitToTextSources: string;
    /// <summary>Befehl „Knopfleiste anordnen“ (#732, designer.buttonBar).</summary>
    DesignerButtonBar: Boolean;
    /// <summary>Reihenfolge der Rollen (#732, designer.buttonBar.order).</summary>
    DesignerButtonBarOrder: string;
    /// <summary>Lage: cButtonBarBottomRight … (#732, designer.buttonBar.position).</summary>
    DesignerButtonBarPosition: string;
    /// <summary>Abstand zwischen den Knöpfen (#732, designer.buttonBar.gap).</summary>
    DesignerButtonBarGap: Integer;
    /// <summary>Abstand zum Rand (#732, designer.buttonBar.margin).</summary>
    DesignerButtonBarMargin: Integer;
    /// <summary>Default, Cancel und ModalResult setzen (#732, designer.buttonBar.setModalResult).</summary>
    DesignerButtonBarSetModalResult: Boolean;
    /// <summary>Eigene Begriffe „ok=Weiter|Los; cancel=Zurück“ (#732, designer.buttonBar.roles).</summary>
    DesignerButtonBarRoles: string;
    /// <summary>Befehl „In Reihe duplizieren“ (#736, designer.duplicateRow).</summary>
    DesignerDuplicateRow: Boolean;
    /// <summary>Ereignis-Handler der Kopien teilen (#736, designer.duplicateRow.shareEvents).</summary>
    DesignerDuplicateRowShareEvents: Boolean;
    /// <summary>Abstand ohne erkannten Nachbarn (#736, designer.duplicateRow.defaultGap).</summary>
    DesignerDuplicateRowDefaultGap: Integer;
    /// <summary>Befehle „Platz einfügen/entfernen“ (#740, designer.insertSpace).</summary>
    DesignerInsertSpace: Boolean;
    /// <summary>Parent und Formular mitwachsen lassen (#740, designer.insertSpace.growParent).</summary>
    DesignerInsertSpaceGrowParent: Boolean;
    /// <summary>Befehl „An Inhalt anpassen“ (#742, designer.fitContainer).</summary>
    DesignerFitContainer: Boolean;
    /// <summary>Innenrand rechts und unten (#742, designer.fitContainer.padding).</summary>
    DesignerFitContainerPadding: Integer;
    /// <summary>Kinder nach links oben rücken (#742, designer.fitContainer.alignTopLeft).</summary>
    DesignerFitContainerAlignTopLeft: Boolean;
    /// <summary>Fast bündige Kanten (#746, designer.nearAlignment).</summary>
    DesignerNearAlignment: Boolean;
    /// <summary>Höchster Versatz in Pixeln, der als fast bündig gilt (#746,
    /// designer.nearAlignment.tolerance).</summary>
    DesignerNearAlignmentTolerance: Integer;
    /// <summary>Auch Textgrundlinien vergleichen (#746, designer.nearAlignment.baseline).</summary>
    DesignerNearAlignmentBaseline: Boolean;
    /// <summary>Klassen, die nicht verglichen werden (#746, designer.nearAlignment.ignoreClasses).</summary>
    DesignerNearAlignmentIgnoreClasses: string;
    /// <summary>Standardgrößen je Klasse (#747, designer.defaultSizes).</summary>
    DesignerDefaultSizes: Boolean;
    /// <summary>Tabelle „Klasse=Breite,Höhe; …“ (#747, designer.defaultSizes.table).</summary>
    DesignerDefaultSizesTable: string;
    /// <summary>Beim Ablegen neuer Komponenten anwenden (#747, designer.defaultSizes.applyOnInsert).</summary>
    DesignerDefaultSizesApplyOnInsert: Boolean;
    /// <summary>Befehl „Abweichungen anzeigen“ (#747, designer.defaultSizes.markDeviations).</summary>
    DesignerDefaultSizesMarkDeviations: Boolean;
    /// <summary>Ebenen schrittweise ordnen (#749, designer.zOrder).</summary>
    DesignerZOrder: Boolean;
    /// <summary>Strg+Bild auf/ab im Designer (#749, designer.zOrder.shortcuts).</summary>
    DesignerZOrderShortcuts: Boolean;
    /// <summary>Container-Vorfahren im Stapel (#749, designer.zOrder.includeParents).</summary>
    DesignerZOrderIncludeParents: Boolean;
    /// <summary>Format-Pinsel (#726, designer.propertyPainter).</summary>
    DesignerPropertyPainter: Boolean;
    /// <summary>Vorausgewählte Gruppen (#726, designer.propertyPainter.defaultGroups).</summary>
    DesignerPropertyPainterDefaultGroups: string;
    /// <summary>Häkchen je Quellklasse merken (#726, designer.propertyPainter.rememberPerClass).</summary>
    DesignerPropertyPainterRememberPerClass: Boolean;
    /// <summary>Anchors vorschlagen (#727, designer.suggestAnchors).</summary>
    DesignerSuggestAnchors: Boolean;
    /// <summary>Abstand, bis zu dem eine Komponente am Rand liegt (#727,
    /// designer.suggestAnchors.edgeDistance).</summary>
    DesignerSuggestAnchorsEdgeDistance: Integer;
    /// <summary>Gesetzte Anchors nicht überschreiben (#727, designer.suggestAnchors.keepExisting).</summary>
    DesignerSuggestAnchorsKeepExisting: Boolean;
    /// <summary>Füllende Klassen mit allen vier Anchors (#727, designer.suggestAnchors.fillClasses).</summary>
    DesignerSuggestAnchorsFillClasses: string;
    /// <summary>Texte des Formulars als Tabelle (#728, designer.textTable).</summary>
    DesignerTextTable: Boolean;
    /// <summary>Aktive Hinweise der Texttabelle (#728, designer.textTable.checks).</summary>
    DesignerTextTableChecks: string;
    /// <summary>Eigene Synonymgruppen (#728, designer.textTable.synonyms).</summary>
    DesignerTextTableSynonyms: string;
    /// <summary>Nicht erfasste Eigenschaften (#728, designer.textTable.excludeProperties).</summary>
    DesignerTextTableExcludeProperties: string;
    /// <summary>Label und Eingabefeld als Paar (#729, designer.labelPairs).</summary>
    DesignerLabelPairs: Boolean;
    /// <summary>Label auf die Textgrundlinie des Felds rücken (#729, designer.labelPairs.baseline).</summary>
    DesignerLabelPairsBaseline: Boolean;
    /// <summary>Leeres FocusControl auf das Feld setzen (#729, designer.labelPairs.focusControl).</summary>
    DesignerLabelPairsFocusControl: Boolean;
    /// <summary>Label mit dem Feld verschieben (#729, designer.labelPairs.moveTogether).</summary>
    DesignerLabelPairsMoveTogether: Boolean;
    /// <summary>Größter Abstand für ein Paar (#729, designer.labelPairs.pairDistance).</summary>
    DesignerLabelPairsPairDistance: Integer;
    /// <summary>Lage neuer Labels: cLabelLeft oder cLabelAbove (#729, designer.labelPairs.newLabelPosition).</summary>
    DesignerLabelPairsNewLabelPosition: string;
    /// <summary>Abkürzungen in eigener Schreibweise (#729, designer.labelPairs.abbreviations).</summary>
    DesignerLabelPairsAbbreviations: string;
    /// <summary>Als Formularraster anordnen (#731, designer.arrangeForm).</summary>
    DesignerArrangeForm: Boolean;
    /// <summary>Abstand zwischen den Zeilen (#731, designer.arrangeForm.rowGap).</summary>
    DesignerArrangeFormRowGap: Integer;
    /// <summary>Abstand zwischen Label und Feld (#731, designer.arrangeForm.labelGap).</summary>
    DesignerArrangeFormLabelGap: Integer;
    /// <summary>Lage der Labels: cGridLabelLeft … (#731, designer.arrangeForm.labelAlign).</summary>
    DesignerArrangeFormLabelAlign: string;
    /// <summary>Einzelne Felder gleich breit (#731, designer.arrangeForm.equalFieldWidth).</summary>
    DesignerArrangeFormEqualFieldWidth: Boolean;
    /// <summary>Zwei Paare je Zeile (#731, designer.arrangeForm.twoPerRow).</summary>
    DesignerArrangeFormTwoPerRow: Boolean;
    /// <summary>TabOrder nach dem Anordnen setzen (#731, designer.arrangeForm.setTabOrder).</summary>
    DesignerArrangeFormSetTabOrder: Boolean;
    /// <summary>Einpacken in Container und Container auflösen (#733, designer.wrapInContainer).</summary>
    DesignerWrapInContainer: Boolean;
    /// <summary>Innenrand des neuen Containers (#733, designer.wrapInContainer.padding).</summary>
    DesignerWrapInContainerPadding: Integer;
    /// <summary>Vorgabeklasse im Menü (#733, designer.wrapInContainer.defaultClass).</summary>
    DesignerWrapInContainerDefaultClass: string;
    /// <summary>Eigene Containerklassen, Komma-Liste (#733, designer.wrapInContainer.classes).</summary>
    DesignerWrapInContainerClasses: string;
    /// <summary>Schriften und Farben vereinheitlichen (#741, designer.fontsColors).</summary>
    DesignerFontsColors: Boolean;
    /// <summary>Beim Ersetzen wieder ParentFont/ParentColor setzen (#741,
    /// designer.fontsColors.restoreParent).</summary>
    DesignerFontsColorsRestoreParent: Boolean;
    /// <summary>Nicht aufgeführte Farben, Komma-Liste (#741, designer.fontsColors.ignoreColors).</summary>
    DesignerFontsColorsIgnoreColors: string;
    /// <summary>Gruppen ohne Container (#744, designer.groups).</summary>
    DesignerGroups: Boolean;
    /// <summary>Einzelnes Mitglied: cDesignerGroupsAltClick oder ...DoubleClick (#744,
    /// designer.groups.memberClick).</summary>
    DesignerGroupsMemberClick: string;
    /// <summary>Ablage: cDesignerSetsLocal oder cDesignerSetsShared (#744, designer.groups.storage).</summary>
    DesignerGroupsStorage: string;
    /// <summary>Beschriftung direkt im Designer bearbeiten (#748, designer.inlineCaption).</summary>
    DesignerInlineCaption: Boolean;
    /// <summary>Langsamer Doppelklick öffnet die Bearbeitung (#748, designer.inlineCaption.slowDoubleClick).</summary>
    DesignerInlineCaptionSlowDoubleClick: Boolean;
    /// <summary>Breite nach dem Übernehmen anpassen (#748, designer.inlineCaption.autoWidth).</summary>
    DesignerInlineCaptionAutoWidth: Boolean;
    /// <summary>Taste als TShortCut, 0 = keine (#748, designer.inlineCaption.key).</summary>
    DesignerInlineCaptionKey: Integer;
    /// <summary>Eigene Zuordnung Klasse=Eigenschaft (#748, designer.inlineCaption.properties).</summary>
    DesignerInlineCaptionProperties: string;
    /// <summary>Abstandsgriffe bei Mehrfachauswahl (#734, designer.gapHandles).</summary>
    DesignerGapHandles: Boolean;
    /// <summary>Rastwerte beim Ziehen, durch Komma getrennt (#734, designer.gapHandles.snapValues).</summary>
    DesignerGapHandlesSnapValues: string;
    /// <summary>Fester Punkt: cGapAnchorCenter, cGapAnchorFirst oder cGapAnchorLast (#734,
    /// designer.gapHandles.anchor).</summary>
    DesignerGapHandlesAnchor: string;
    /// <summary>Gemeinsame Größengriffe bei Mehrfachauswahl (#737, designer.multiResize).</summary>
    DesignerMultiResize: Boolean;
    /// <summary>cResizeModeDelta oder cResizeModeAlign (#737, designer.multiResize.mode).</summary>
    DesignerMultiResizeMode: string;
    /// <summary>Eigene Griffe auch links und oben (#737, designer.multiResize.leftTopHandles).</summary>
    DesignerMultiResizeLeftTopHandles: Boolean;
    /// <summary>Schnellleiste über einer Mehrfachauswahl (#735, designer.selectionBar).</summary>
    DesignerSelectionBar: Boolean;
    /// <summary>cSelectionBarAuto oder cSelectionBarShortcut (#735, designer.selectionBar.mode).</summary>
    DesignerSelectionBarMode: string;
    /// <summary>Verzögerung bis zum Einblenden in ms (#735, designer.selectionBar.delayMs).</summary>
    DesignerSelectionBarDelayMs: Integer;
    /// <summary>Knöpfe und Reihenfolge (#735, designer.selectionBar.items).</summary>
    DesignerSelectionBarItems: string;
    /// <summary>Taste zum Einblenden im Modus shortcut (#735, designer.selectionBar.key).</summary>
    DesignerSelectionBarKey: Integer;
    /// <summary>Lupe für den Designer (#743, designer.magnifier).</summary>
    DesignerMagnifier: Boolean;
    /// <summary>Vergrößerung beim Öffnen: 2, 4 oder 8 (#743, designer.magnifier.zoom).</summary>
    DesignerMagnifierZoom: Integer;
    /// <summary>Pixelraster ab 4× (#743, designer.magnifier.grid).</summary>
    DesignerMagnifierGrid: Boolean;
    /// <summary>Kanten der Auswahl und Nachbarn einzeichnen (#743, designer.magnifier.edges).</summary>
    DesignerMagnifierEdges: Boolean;
    /// <summary>Taste zum Öffnen und Einfrieren (#743, designer.magnifier.key).</summary>
    DesignerMagnifierKey: Integer;
    /// <summary>Rückgängig im Designer über Formular-Stände (#1887, designer.undo, experimentell).</summary>
    DesignerUndo: Boolean;
    /// <summary>Höchstzahl der Schritte je Formular (#1887, designer.undoSteps).</summary>
    DesignerUndoSteps: Integer;
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
    /// <summary>Vorgaben der eigenen Knöpfe der Designer-Leiste (#605 ff.).</summary>
    procedure SetViewDefaults;
    /// <summary>Einstellungen der eigenen Knöpfe der Designer-Leiste lesen bzw. schreiben.</summary>
    procedure ExchangeViews(const AIo: TAtlasSettingsExchange);
    /// <summary>Vorgaben der Befehle im Menü „Anordnen“ der Designer-Leiste (#730 ff.).</summary>
    procedure SetArrangeDefaults;
    /// <summary>Raster (#731), Einpacken (#733), Schriften (#741), Gruppen (#744), Beschriftung (#748).</summary>
    procedure SetFormToolDefaults;
    /// <summary>Einstellungen der Befehle im Menü „Anordnen“ lesen bzw. schreiben.</summary>
    procedure ExchangeArrange(const AIo: TAtlasSettingsExchange);
    /// <summary>Einstellungen von Formularraster und Einpacken lesen bzw. schreiben.</summary>
    procedure ExchangeFormTools(const AIo: TAtlasSettingsExchange);
    /// <summary>Vorgaben der Werkzeuge mit eigenem Knopf in der Designer-Leiste (#734 ff.).</summary>
    procedure SetToolDefaults;
    /// <summary>Einstellungen der Werkzeuge mit eigenem Knopf lesen bzw. schreiben.</summary>
    procedure ExchangeTools(const AIo: TAtlasSettingsExchange);
    /// <summary>Abstände und Ränder der Designer-Werkzeuge (und die Schritte von designer.undoSteps) in ihre
    /// Grenzen bringen.</summary>
    procedure NormalizeSpacing;
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

const
  /// <summary>Knöpfe der Schnellleiste im Designer ab Werk, in dieser Reihenfolge (Kennungen, kein Text).</summary>
  cSelectionBarItems = 'fontSmaller, fontSize, fontLarger, bold, italic, fontColor, enabled, visible, ' +
    'parentFont, parentColor, anchorLeft, anchorTop, anchorRight, anchorBottom, sameWidth, sameHeight, alignLeft, ' +
    'alignCenter, alignRight, transfer';
  /// <summary>Vorgabe von designer.selectionSets.saveKey: Strg+Umschalt+S (scShift + scCtrl + Ord('S')).</summary>
  cDefaultSelectionSetsSaveKey = $2000 + $4000 + Ord('S');
  /// <summary>Vorgabeabstand der Designer-Werkzeuge in Pixel (Zeilen, Beschriftungen, Innenrand).</summary>
  cDefaultDesignerGap = 8;
  /// <summary>Vorgabe für „nahe am Rand“ bzw. „nahe am Feld“ in Pixel (Anchors, Label und Feld).</summary>
  cDefaultDesignerNear = 16;
  cDefaultPainterGroups = 'font, colors, size, layout';
  cDefaultAnchorFillClasses = 'TMemo, TDBGrid, TStringGrid, TListView, TTreeView, TPageControl, TRichEdit';
  cDefaultTextChecks = 'accelerators, variants, truncated, whitespace';
  cDefaultTextExcludeProperties = 'SQL, CommandText';
  cDefaultLabelAbbreviations = 'PLZ, IBAN, BIC, USt, ID';
  cDefaultIgnoreColors = 'clWindow, clBtnFace, clWindowText, clDefault';
  cDefaultNameSources = 'caption, label, handler, dataField';

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
  Result.HoverExplainMessages := True;
  Result.HoverRuleExamples := True;
  Result.HoverMembersMaxLines := 15;
  Result.HoverSignatureParams := True;
  Result.ProblemsStatusCounter := True;
  Result.CodeLensTestUnit := True;
  Result.CodeLensMetrics := True;
  Result.Metrics := True;
  Result.CodeLensTests := True;
  Result.TestCoverage := True;
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
  AIo.Flag('HoverExplainMessages', HoverExplainMessages);
  AIo.Flag('HoverRuleExamples', HoverRuleExamples);
  AIo.Number('HoverMembersMaxLines', HoverMembersMaxLines);
  AIo.Flag('HoverSignatureParams', HoverSignatureParams);
  AIo.Flag('ProblemsStatusCounter', ProblemsStatusCounter);
  AIo.Flag('CodeLensTestUnit', CodeLensTestUnit);
  AIo.Flag('CodeLensMetrics', CodeLensMetrics);
  AIo.Flag('Metrics', Metrics);
  AIo.Flag('CodeLensTests', CodeLensTests);
  AIo.Flag('TestCoverage', TestCoverage);
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
  Result.MouseNavButtons := True;
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
  AIo.Flag('MouseNavButtons', MouseNavButtons);
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
  Result.DesignerFuzzySearch := True;
  Result.DesignerTabOrderClick := True;
  Result.DesignerTabOrderOverlay := False;
  Result.DesignerTabOrderPaths := False;
  Result.DesignerTabOrderColors := True;
  Result.DesignerAlign := False;
  Result.DesignerSelectSimilar := True;
  Result.DesignerSelectDescendants := True;
  Result.DesignerSelectScope := cDesignerScopeForm;
  Result.DesignerSelectionSets := True;
  Result.DesignerSelectionSetsShortcuts := True;
  Result.DesignerSelectionSetsStorage := cDesignerSetsLocal;
  // Strg+Umschalt+S.
  Result.DesignerSelectionSetsSaveKey := cDefaultSelectionSetsSaveKey;
  Result.DesignerShowInDesigner := True;
  // Umschalt+F12 (in der IDE „Formulare anzeigen“).
  Result.DesignerShowInDesignerKey := cDefaultShowInDesignerKey;
  Result.DesignerPropertySearch := True;
  Result.DesignerUsages := True;
  Result.DesignerUsagesStatusCount := True;
  Result.DesignerUsagesScope := cDesignerUsagesProject;
  Result.DesignerUsagesKey := cDefaultUsagesKey;
  Result.DesignerSpatialNavigation := True;
  Result.DesignerSpatialCrossContainers := True;
  Result.SetViewDefaults;
  Result.SetArrangeDefaults;
  Result.SetFormToolDefaults;
  Result.SetToolDefaults;
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

procedure TAtlasPluginEditorViewSettings.SetArrangeDefaults;
begin
  DesignerFitToText := True;
  DesignerFitToTextMinWidth := 75;
  DesignerFitToTextPadding := 16;
  DesignerFitToTextSources := cFitSourceCaption;
  DesignerButtonBar := True;
  DesignerButtonBarOrder := 'ok,cancel,apply,help';
  DesignerButtonBarPosition := cButtonBarBottomRight;
  DesignerButtonBarGap := 8;
  DesignerButtonBarMargin := 8;
  DesignerButtonBarSetModalResult := True;
  DesignerButtonBarRoles := '';
  DesignerDuplicateRow := True;
  DesignerDuplicateRowShareEvents := True;
  DesignerDuplicateRowDefaultGap := 8;
  DesignerInsertSpace := True;
  DesignerInsertSpaceGrowParent := True;
  DesignerFitContainer := True;
  DesignerFitContainerPadding := 8;
  DesignerFitContainerAlignTopLeft := False;
  DesignerNearAlignment := True;
  DesignerNearAlignmentTolerance := 3;
  DesignerNearAlignmentBaseline := True;
  DesignerNearAlignmentIgnoreClasses := 'TBevel,TShape';
  DesignerDefaultSizes := True;
  DesignerDefaultSizesTable := '';
  DesignerDefaultSizesApplyOnInsert := True;
  DesignerDefaultSizesMarkDeviations := False;
  DesignerZOrder := True;
  DesignerZOrderShortcuts := True;
  DesignerZOrderIncludeParents := False;
  DesignerPropertyPainter := True;
  DesignerPropertyPainterDefaultGroups := cDefaultPainterGroups;
  DesignerPropertyPainterRememberPerClass := True;
  DesignerSuggestAnchors := True;
  DesignerSuggestAnchorsEdgeDistance := cDefaultDesignerNear;
  DesignerSuggestAnchorsKeepExisting := True;
  DesignerSuggestAnchorsFillClasses := cDefaultAnchorFillClasses;
  DesignerTextTable := True;
  DesignerTextTableChecks := cDefaultTextChecks;
  DesignerTextTableSynonyms := '';
  DesignerTextTableExcludeProperties := cDefaultTextExcludeProperties;
  DesignerLabelPairs := True;
  DesignerLabelPairsBaseline := True;
  DesignerLabelPairsFocusControl := True;
  DesignerLabelPairsMoveTogether := True;
  DesignerLabelPairsPairDistance := cDefaultDesignerNear;
  DesignerLabelPairsNewLabelPosition := cLabelLeft;
  DesignerLabelPairsAbbreviations := cDefaultLabelAbbreviations;
end;

procedure TAtlasPluginEditorViewSettings.SetFormToolDefaults;
begin
  DesignerArrangeForm := True;
  DesignerArrangeFormRowGap := cDefaultDesignerGap;
  DesignerArrangeFormLabelGap := cDefaultDesignerGap;
  DesignerArrangeFormLabelAlign := cGridLabelLeft;
  DesignerArrangeFormEqualFieldWidth := False;
  DesignerArrangeFormTwoPerRow := False;
  DesignerArrangeFormSetTabOrder := True;
  DesignerWrapInContainer := True;
  DesignerWrapInContainerPadding := cDefaultDesignerGap;
  DesignerWrapInContainerDefaultClass := 'TPanel';
  DesignerWrapInContainerClasses := '';
  DesignerFontsColors := True;
  DesignerFontsColorsRestoreParent := True;
  DesignerFontsColorsIgnoreColors := cDefaultIgnoreColors;
  DesignerGroups := True;
  DesignerGroupsMemberClick := cDesignerGroupsAltClick;
  DesignerGroupsStorage := cDesignerSetsLocal;
  DesignerInlineCaption := True;
  DesignerInlineCaptionSlowDoubleClick := True;
  DesignerInlineCaptionAutoWidth := False;
  DesignerInlineCaptionKey := cInlineCaptionKey;
  DesignerInlineCaptionProperties := '';
end;

procedure TAtlasPluginEditorViewSettings.ExchangeArrange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('DesignerFitToText', DesignerFitToText);
  AIo.Number('DesignerFitToTextMinWidth', DesignerFitToTextMinWidth);
  AIo.Number('DesignerFitToTextPadding', DesignerFitToTextPadding);
  AIo.Text('DesignerFitToTextSources', DesignerFitToTextSources);
  AIo.Flag('DesignerButtonBar', DesignerButtonBar);
  AIo.Text('DesignerButtonBarOrder', DesignerButtonBarOrder);
  AIo.Text('DesignerButtonBarPosition', DesignerButtonBarPosition);
  AIo.Number('DesignerButtonBarGap', DesignerButtonBarGap);
  AIo.Number('DesignerButtonBarMargin', DesignerButtonBarMargin);
  AIo.Flag('DesignerButtonBarSetModalResult', DesignerButtonBarSetModalResult);
  AIo.Text('DesignerButtonBarRoles', DesignerButtonBarRoles);
  AIo.Flag('DesignerDuplicateRow', DesignerDuplicateRow);
  AIo.Flag('DesignerDuplicateRowShareEvents', DesignerDuplicateRowShareEvents);
  AIo.Number('DesignerDuplicateRowDefaultGap', DesignerDuplicateRowDefaultGap);
  AIo.Flag('DesignerInsertSpace', DesignerInsertSpace);
  AIo.Flag('DesignerInsertSpaceGrowParent', DesignerInsertSpaceGrowParent);
  AIo.Flag('DesignerFitContainer', DesignerFitContainer);
  AIo.Number('DesignerFitContainerPadding', DesignerFitContainerPadding);
  AIo.Flag('DesignerFitContainerAlignTopLeft', DesignerFitContainerAlignTopLeft);
  AIo.Flag('DesignerNearAlignment', DesignerNearAlignment);
  AIo.Number('DesignerNearAlignmentTolerance', DesignerNearAlignmentTolerance);
  AIo.Flag('DesignerNearAlignmentBaseline', DesignerNearAlignmentBaseline);
  AIo.Text('DesignerNearAlignmentIgnoreClasses', DesignerNearAlignmentIgnoreClasses);
  AIo.Flag('DesignerDefaultSizes', DesignerDefaultSizes);
  AIo.Text('DesignerDefaultSizesTable', DesignerDefaultSizesTable);
  AIo.Flag('DesignerDefaultSizesApplyOnInsert', DesignerDefaultSizesApplyOnInsert);
  AIo.Flag('DesignerDefaultSizesMarkDeviations', DesignerDefaultSizesMarkDeviations);
  AIo.Flag('DesignerZOrder', DesignerZOrder);
  AIo.Flag('DesignerZOrderShortcuts', DesignerZOrderShortcuts);
  AIo.Flag('DesignerZOrderIncludeParents', DesignerZOrderIncludeParents);
  AIo.Flag('DesignerPropertyPainter', DesignerPropertyPainter);
  AIo.Text('DesignerPropertyPainterDefaultGroups', DesignerPropertyPainterDefaultGroups);
  AIo.Flag('DesignerPropertyPainterRememberPerClass', DesignerPropertyPainterRememberPerClass);
  AIo.Flag('DesignerSuggestAnchors', DesignerSuggestAnchors);
  AIo.Number('DesignerSuggestAnchorsEdgeDistance', DesignerSuggestAnchorsEdgeDistance);
  AIo.Flag('DesignerSuggestAnchorsKeepExisting', DesignerSuggestAnchorsKeepExisting);
  AIo.Text('DesignerSuggestAnchorsFillClasses', DesignerSuggestAnchorsFillClasses);
  AIo.Flag('DesignerTextTable', DesignerTextTable);
  AIo.Text('DesignerTextTableChecks', DesignerTextTableChecks);
  AIo.Text('DesignerTextTableSynonyms', DesignerTextTableSynonyms);
  AIo.Text('DesignerTextTableExcludeProperties', DesignerTextTableExcludeProperties);
  AIo.Flag('DesignerLabelPairs', DesignerLabelPairs);
  AIo.Flag('DesignerLabelPairsBaseline', DesignerLabelPairsBaseline);
  AIo.Flag('DesignerLabelPairsFocusControl', DesignerLabelPairsFocusControl);
  AIo.Flag('DesignerLabelPairsMoveTogether', DesignerLabelPairsMoveTogether);
  AIo.Number('DesignerLabelPairsPairDistance', DesignerLabelPairsPairDistance);
  AIo.Text('DesignerLabelPairsNewLabelPosition', DesignerLabelPairsNewLabelPosition);
  AIo.Text('DesignerLabelPairsAbbreviations', DesignerLabelPairsAbbreviations);
end;

procedure TAtlasPluginEditorViewSettings.ExchangeFormTools(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('DesignerArrangeForm', DesignerArrangeForm);
  AIo.Number('DesignerArrangeFormRowGap', DesignerArrangeFormRowGap);
  AIo.Number('DesignerArrangeFormLabelGap', DesignerArrangeFormLabelGap);
  AIo.Text('DesignerArrangeFormLabelAlign', DesignerArrangeFormLabelAlign);
  AIo.Flag('DesignerArrangeFormEqualFieldWidth', DesignerArrangeFormEqualFieldWidth);
  AIo.Flag('DesignerArrangeFormTwoPerRow', DesignerArrangeFormTwoPerRow);
  AIo.Flag('DesignerArrangeFormSetTabOrder', DesignerArrangeFormSetTabOrder);
  AIo.Flag('DesignerWrapInContainer', DesignerWrapInContainer);
  AIo.Number('DesignerWrapInContainerPadding', DesignerWrapInContainerPadding);
  AIo.Text('DesignerWrapInContainerDefaultClass', DesignerWrapInContainerDefaultClass);
  AIo.Text('DesignerWrapInContainerClasses', DesignerWrapInContainerClasses);
  AIo.Flag('DesignerFontsColors', DesignerFontsColors);
  AIo.Flag('DesignerFontsColorsRestoreParent', DesignerFontsColorsRestoreParent);
  AIo.Text('DesignerFontsColorsIgnoreColors', DesignerFontsColorsIgnoreColors);
  AIo.Flag('DesignerGroups', DesignerGroups);
  AIo.Text('DesignerGroupsMemberClick', DesignerGroupsMemberClick);
  AIo.Text('DesignerGroupsStorage', DesignerGroupsStorage);
  AIo.Flag('DesignerInlineCaption', DesignerInlineCaption);
  AIo.Flag('DesignerInlineCaptionSlowDoubleClick', DesignerInlineCaptionSlowDoubleClick);
  AIo.Flag('DesignerInlineCaptionAutoWidth', DesignerInlineCaptionAutoWidth);
  AIo.Number('DesignerInlineCaptionKey', DesignerInlineCaptionKey);
  AIo.Text('DesignerInlineCaptionProperties', DesignerInlineCaptionProperties);
end;

procedure TAtlasPluginEditorViewSettings.SetToolDefaults;
begin
  DesignerGapHandles := True;
  DesignerGapHandlesSnapValues := '4, 8, 12, 16';
  DesignerGapHandlesAnchor := cGapAnchorCenter;
  DesignerMultiResize := True;
  DesignerMultiResizeMode := cResizeModeDelta;
  DesignerMultiResizeLeftTopHandles := False;
  DesignerSelectionBar := True;
  DesignerSelectionBarMode := cSelectionBarAuto;
  DesignerSelectionBarDelayMs := 400;
  DesignerSelectionBarItems := cSelectionBarItems;
  // Strg+Umschalt+Leer.
  DesignerSelectionBarKey := 24608;
  DesignerMagnifier := True;
  DesignerMagnifierZoom := 4;
  DesignerMagnifierGrid := True;
  DesignerMagnifierEdges := False;
  // Strg+Alt+L.
  DesignerMagnifierKey := 49228;
  DesignerUndo := False;
  DesignerUndoSteps := cDefaultUndoSteps;
end;

procedure TAtlasPluginEditorViewSettings.ExchangeTools(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('DesignerGapHandles', DesignerGapHandles);
  AIo.Text('DesignerGapHandlesSnapValues', DesignerGapHandlesSnapValues);
  AIo.Text('DesignerGapHandlesAnchor', DesignerGapHandlesAnchor);
  AIo.Flag('DesignerMultiResize', DesignerMultiResize);
  AIo.Text('DesignerMultiResizeMode', DesignerMultiResizeMode);
  AIo.Flag('DesignerMultiResizeLeftTopHandles', DesignerMultiResizeLeftTopHandles);
  AIo.Flag('DesignerSelectionBar', DesignerSelectionBar);
  AIo.Text('DesignerSelectionBarMode', DesignerSelectionBarMode);
  AIo.Number('DesignerSelectionBarDelayMs', DesignerSelectionBarDelayMs);
  AIo.Text('DesignerSelectionBarItems', DesignerSelectionBarItems);
  AIo.Number('DesignerSelectionBarKey', DesignerSelectionBarKey);
  AIo.Flag('DesignerMagnifier', DesignerMagnifier);
  AIo.Number('DesignerMagnifierZoom', DesignerMagnifierZoom);
  AIo.Flag('DesignerMagnifierGrid', DesignerMagnifierGrid);
  AIo.Flag('DesignerMagnifierEdges', DesignerMagnifierEdges);
  AIo.Number('DesignerMagnifierKey', DesignerMagnifierKey);
  AIo.Flag('DesignerUndo', DesignerUndo);
  AIo.Number('DesignerUndoSteps', DesignerUndoSteps);
end;

procedure TAtlasPluginEditorViewSettings.NormalizeSpacing;
begin
  DesignerButtonBarGap := EnsureRange(DesignerButtonBarGap, 0, cMaxButtonBarSpace);
  DesignerButtonBarMargin := EnsureRange(DesignerButtonBarMargin, 0, cMaxButtonBarSpace);
  DesignerDuplicateRowDefaultGap := EnsureRange(DesignerDuplicateRowDefaultGap, 0, cMaxButtonBarSpace);
  DesignerFitContainerPadding := EnsureRange(DesignerFitContainerPadding, 0, cMaxButtonBarSpace);
  DesignerSuggestAnchorsEdgeDistance := EnsureRange(DesignerSuggestAnchorsEdgeDistance, 0, cMaxButtonBarSpace);
  DesignerLabelPairsPairDistance := EnsureRange(DesignerLabelPairsPairDistance, 0, cMaxButtonBarSpace);
  DesignerArrangeFormRowGap := EnsureRange(DesignerArrangeFormRowGap, 0, cMaxButtonBarSpace);
  DesignerArrangeFormLabelGap := EnsureRange(DesignerArrangeFormLabelGap, 0, cMaxButtonBarSpace);
  DesignerWrapInContainerPadding := EnsureRange(DesignerWrapInContainerPadding, 0, cMaxButtonBarSpace);
  DesignerUndoSteps := EnsureRange(DesignerUndoSteps, cMinUndoSteps, cMaxUndoSteps);
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
  DesignerGroupsStorage := Choice(DesignerGroupsStorage, [cDesignerSetsLocal, cDesignerSetsShared]);
  DesignerGroupsMemberClick := Choice(DesignerGroupsMemberClick, [cDesignerGroupsAltClick, cDesignerGroupsDoubleClick]);
  DesignerInlineCaptionKey := EnsureRange(DesignerInlineCaptionKey, 0, $FFFF);
  DesignerSelectionSetsSaveKey := EnsureRange(DesignerSelectionSetsSaveKey, 0, $FFFF);
  DesignerShowInDesignerKey := EnsureRange(DesignerShowInDesignerKey, 0, $FFFF);
  DesignerUsagesScope := Choice(DesignerUsagesScope, [cDesignerUsagesProject, cDesignerUsagesUnit,
    cDesignerUsagesGroup]);
  DesignerUsagesKey := EnsureRange(DesignerUsagesKey, 0, $FFFF);
  DesignerFitToTextMinWidth := EnsureRange(DesignerFitToTextMinWidth, 0, cMaxFitMinWidth);
  DesignerFitToTextPadding := EnsureRange(DesignerFitToTextPadding, 0, cMaxFitPadding);
  DesignerButtonBarPosition := Choice(DesignerButtonBarPosition, [cButtonBarBottomRight, cButtonBarBottomLeft,
    cButtonBarRightTop, cButtonBarRightBottom]);
  NormalizeSpacing;
  DesignerLabelPairsNewLabelPosition := Choice(DesignerLabelPairsNewLabelPosition, [cLabelLeft, cLabelAbove]);
  DesignerArrangeFormLabelAlign := Choice(DesignerArrangeFormLabelAlign, [cGridLabelLeft, cGridLabelRight,
    cGridLabelAbove]);
  if Trim(DesignerWrapInContainerDefaultClass) = '' then
  begin
    DesignerWrapInContainerDefaultClass := 'TPanel';
  end;
  DesignerNearAlignmentTolerance := EnsureRange(DesignerNearAlignmentTolerance, 1, cMaxNearTolerance);
  DesignerGapHandlesAnchor := Choice(DesignerGapHandlesAnchor, [cGapAnchorCenter, cGapAnchorFirst, cGapAnchorLast]);
  DesignerMultiResizeMode := Choice(DesignerMultiResizeMode, [cResizeModeDelta, cResizeModeAlign]);
  DesignerSelectionBarMode := Choice(DesignerSelectionBarMode, [cSelectionBarAuto, cSelectionBarShortcut]);
  DesignerSelectionBarDelayMs := EnsureRange(DesignerSelectionBarDelayMs, 0, cMaxSelectionBarDelay);
  DesignerSelectionBarKey := EnsureRange(DesignerSelectionBarKey, 0, $FFFF);
  // Stufen 2, 4, 8 (TAtlasMagnifier.NormalizeZoom im Designer-Modul).
  if DesignerMagnifierZoom <= 2 then
  begin
    DesignerMagnifierZoom := 2;
  end
  else if DesignerMagnifierZoom < 6 then
  begin
    DesignerMagnifierZoom := 4;
  end
  else
  begin
    DesignerMagnifierZoom := 8;
  end;
  DesignerMagnifierKey := EnsureRange(DesignerMagnifierKey, 0, $FFFF);
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
  AIo.Flag('DesignerFuzzySearch', DesignerFuzzySearch);
  AIo.Flag('DesignerTabOrderClick', DesignerTabOrderClick);
  AIo.Flag('DesignerTabOrderOverlay', DesignerTabOrderOverlay);
  AIo.Flag('DesignerTabOrderPaths', DesignerTabOrderPaths);
  AIo.Flag('DesignerTabOrderColors', DesignerTabOrderColors);
  AIo.Flag('DesignerAlign', DesignerAlign);
  AIo.Flag('DesignerSelectSimilar', DesignerSelectSimilar);
  AIo.Flag('DesignerSelectDescendants', DesignerSelectDescendants);
  AIo.Text('DesignerSelectScope', DesignerSelectScope);
  AIo.Flag('DesignerSelectionSets', DesignerSelectionSets);
  AIo.Flag('DesignerSelectionSetsShortcuts', DesignerSelectionSetsShortcuts);
  AIo.Text('DesignerSelectionSetsStorage', DesignerSelectionSetsStorage);
  AIo.Number('DesignerSelectionSetsSaveKey', DesignerSelectionSetsSaveKey);
  AIo.Flag('DesignerShowInDesigner', DesignerShowInDesigner);
  AIo.Number('DesignerShowInDesignerKey', DesignerShowInDesignerKey);
  AIo.Flag('DesignerPropertySearch', DesignerPropertySearch);
  AIo.Flag('DesignerUsages', DesignerUsages);
  AIo.Flag('DesignerUsagesStatusCount', DesignerUsagesStatusCount);
  AIo.Text('DesignerUsagesScope', DesignerUsagesScope);
  AIo.Number('DesignerUsagesKey', DesignerUsagesKey);
  AIo.Flag('DesignerSpatialNavigation', DesignerSpatialNavigation);
  AIo.Flag('DesignerSpatialCrossContainers', DesignerSpatialCrossContainers);
  ExchangeViews(AIo);
  ExchangeArrange(AIo);
  ExchangeFormTools(AIo);
  ExchangeTools(AIo);
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

const
  /// <summary>Vorgabe für designer.longTextFactor in Prozent.</summary>
  cLongTextFactor = 30;

procedure TAtlasPluginEditorViewSettings.SetViewDefaults;
begin
  DesignerMeasureDistances := True;
  DesignerMeasureAltKey := True;
  DesignerResizePreview := True;
  DesignerResizePreviewSizes := '1366x768, 1920x1080';
  DesignerResizePreviewShowAnchors := True;
  DesignerScalePreview := True;
  DesignerScalePreviewLevels := '100, 125, 150, 175, 200';
  DesignerScalePreviewScreens := '1366x768, 1920x1080';
  DesignerLongTextFactor := cLongTextFactor;
  DesignerNameSuggest := True;
  DesignerNameSuggestSources := cDefaultNameSources;
  DesignerNameSuggestUmlauts := 'replace';
  DesignerNameSuggestRenameHandlers := True;
  DesignerNameSuggestPrefixes := '';
  DesignerStructure := False;
  DesignerStructureHideOnForm := True;
  DesignerDataBindings := False;
  DesignerExtractFrame := True;
  DesignerEventMap := True;
end;

procedure TAtlasPluginEditorViewSettings.ExchangeViews(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('DesignerMeasureDistances', DesignerMeasureDistances);
  AIo.Flag('DesignerMeasureAltKey', DesignerMeasureAltKey);
  AIo.Flag('DesignerResizePreview', DesignerResizePreview);
  AIo.Text('DesignerResizePreviewSizes', DesignerResizePreviewSizes);
  AIo.Flag('DesignerResizePreviewShowAnchors', DesignerResizePreviewShowAnchors);
  AIo.Flag('DesignerScalePreview', DesignerScalePreview);
  AIo.Text('DesignerScalePreviewLevels', DesignerScalePreviewLevels);
  AIo.Text('DesignerScalePreviewScreens', DesignerScalePreviewScreens);
  AIo.Number('DesignerLongTextFactor', DesignerLongTextFactor);
  AIo.Flag('DesignerNameSuggest', DesignerNameSuggest);
  AIo.Text('DesignerNameSuggestSources', DesignerNameSuggestSources);
  AIo.Text('DesignerNameSuggestUmlauts', DesignerNameSuggestUmlauts);
  AIo.Flag('DesignerNameSuggestRenameHandlers', DesignerNameSuggestRenameHandlers);
  AIo.Text('DesignerNameSuggestPrefixes', DesignerNameSuggestPrefixes);
  AIo.Flag('DesignerStructure', DesignerStructure);
  AIo.Flag('DesignerStructureHideOnForm', DesignerStructureHideOnForm);
  AIo.Flag('DesignerDataBindings', DesignerDataBindings);
  AIo.Flag('DesignerExtractFrame', DesignerExtractFrame);
  AIo.Flag('DesignerEventMap', DesignerEventMap);
end;

end.
