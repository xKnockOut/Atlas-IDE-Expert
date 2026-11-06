unit Atlas.Core.Settings.Plugin.Keys;

// Einstellungen des IDE-Plugins, Bereich Tastenkürzel (keys.*) (#227, ADR 0017):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

type
  /// <summary>Plugin-Einstellungen: Tastenkürzel der Editorbefehle.</summary>
  TAtlasPluginEditingKeysSettings = record
    /// <summary>Tastenkürzel der Befehlspalette und der Syntaxprüfung (TShortCut, 0 = keins, #494).</summary>
    PaletteKey: Integer;
    CheckKey: Integer;
    /// <summary>Eigene Tasten für Vervollständigung und Parameter-Hint (#494), 0 = die Taste der IDE
    /// (Strg+Leer bzw. Strg+Umschalt+Leer über Code Insight); sonst belegt Atlas sie zusätzlich.</summary>
    CompletionKey: Integer;
    SignatureKey: Integer;
    /// <summary>Taste für „Issue anlegen …“ (#1268, keys.createIssue); 0 = keine.</summary>
    CreateIssueKey: Integer;
    /// <summary>Tastenkürzel im Editor (#399, TShortCut, 0 = keins): Code-Aktionen, Auswahl erweitern und
    /// verkleinern, Gehe zu Implementierung und zu Typdefinition.</summary>
    ActionsKey: Integer;
    ExpandKey: Integer;
    ShrinkKey: Integer;
    /// <summary>Zwischen Unit und Testunit wechseln (#189, TShortCut, 0 = keins).</summary>
    TestUnitKey: Integer;
    /// <summary>Tastenkürzel des Erzeugen-Menüs (#719, keys.generateMenu.key; TShortCut, 0 = keins; Vorgabe Alt+Einfg).
    /// </summary>
    GenerateMenuKey: Integer;
    /// <summary>Tastenkürzel für das Fenster der Schnellschalter (#604, TShortCut, 0 = keins) und Vorrang wie
    /// bei den anderen Atlas-Tasten (#494).</summary>
    QuickToggleKey: Integer;
    /// <summary>Tastenkürzel, das den Diagnosemodus umschaltet (#479, TShortCut, 0 = keins); Vorgabe
    /// Strg+Alt+Umschalt+D, weil Strg+Alt+Umschalt+A den Schnellschaltern (#604) gehört. Vorrang wie bei den
    /// anderen Atlas-Tasten (#494).</summary>
    DiagnosticModeKey: Integer;
    /// <summary>Beim Start die Tasten von Atlas gegen alle Belegungen prüfen und jeden Konflikt einmal in der
    /// Meldungsansicht melden (#520).</summary>
    KeyStartupCheck: Boolean;
    /// <summary>Tastenkürzel „Letzte Atlas-Änderung zurücknehmen“ und „… wiederherstellen“ (#721, wie die
    /// Editor-Kürzel aus #399 änderbar, TShortCut, 0 = keins).</summary>
    UndoKey: Integer;
    RedoKey: Integer;
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
    /// <summary>Kürzel „Typ des Ausdrucks“ (#689, keys.expressionType); Vorgabe Strg+Umschalt+T.</summary>
    ExpressionTypeKey: Integer;
    /// <summary>Sicher löschen (#716, keys.safeDelete): Kürzel im Editor; aus = Kürzel frei, kein Menüeintrag
    /// (die Code-Aktion schaltet refactoring.safeDelete).</summary>
    SafeDelete: Boolean;
    /// <summary>Kürzel „Sicher löschen“ (#716); Vorgabe Alt+Entf.</summary>
    SafeDeleteKey: Integer;
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
    /// <summary>Kürzel „Anweisung vervollständigen“ (#697, keys.completeStatement); Vorgabe Strg+Umschalt+Enter.
    /// </summary>
    CompleteStatementKey: Integer;
    /// <summary>Kürzel „Formatieren“ (#43, keys.format); Vorgabe Strg+Umschalt+Alt+F, weil Strg+D die
    /// Mehrfachmarken haben und RAD Studio 13 keinen eigenen Formatierer mehr hat.</summary>
    FormatCodeKey: Integer;
    /// <summary>Kürzel der Mehrfachmarken (#589, keys.multiCursor.*): nächstes Vorkommen (Strg+D), Überspringen
    /// (zweite Taste nach Strg+K, Vorgabe Strg+D), Marken an den Zeilenenden (Alt+Umschalt+I), Marke darüber
    /// bzw. darunter (Strg+Alt+↑/↓).</summary>
    MultiCursorNextKey: Integer;
    MultiCursorSkipKey: Integer;
    MultiCursorLineEndsKey: Integer;
    MultiCursorAboveKey: Integer;
    MultiCursorBelowKey: Integer;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginEditingKeysSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

  /// <summary>Plugin-Einstellungen: Vorrang der Atlas-Tastenkürzel vor der IDE.</summary>
  TAtlasPluginKeyPrioritiesSettings = record
    /// <summary>Kürzel auch belegen, wenn die IDE oder eine andere Erweiterung es schon nutzt.</summary>
    PaletteKeyPriority: Boolean;
    CheckKeyPriority: Boolean;
    CompletionKeyPriority: Boolean;
    SignatureKeyPriority: Boolean;
    /// <summary>Die Editor-Kürzel auch belegen, wenn die IDE oder eine andere Erweiterung sie nutzt.</summary>
    EditorKeysPriority: Boolean;
    QuickToggleKeyPriority: Boolean;
    DiagnosticModeKeyPriority: Boolean;
    /// <summary>Vorrang für QuickBookmarkKey vor der Faltung der IDE (#1104, bookmarks.quick.keyPriority).</summary>
    QuickBookmarkKeyPriority: Boolean;
    /// <summary>Vorrang vor „Lesezeichen umschalten“ der IDE (#1104, bookmarks.quick.setKeyPriority).</summary>
    QuickBookmarkSetKeyPriority: Boolean;
    /// <summary>Vorrang vor „Zu Lesezeichen springen“ der IDE (#1104, bookmarks.quick.jumpKeyPriority).</summary>
    QuickBookmarkJumpKeyPriority: Boolean;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginKeyPrioritiesSettings; static;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

  /// <summary>Plugin-Einstellungen: Tastenkürzel für Navigation, Suche, Lesezeichen und Probleme.</summary>
  TAtlasPluginNavigationKeysSettings = record
    /// <summary>„Lesezeichen setzen…“ (#622, TShortCut, 0 = keins; Vorgabe Strg+Alt+K).</summary>
    BookmarkKey: Integer;
    /// <summary>„Element ausblenden …“ (#628, TShortCut, 0 = keins; Vorgabe Strg+.): Menü „Ausblenden“ für das von
    /// Atlas gezeichnete Element in der Cursorzeile; ohne Element geht die Taste an die IDE (IDE Insight).</summary>
    HideElementKey: Integer;
    /// <summary>Suchleiste mit Ersetzen-Zeile (#893, TShortCut, 0 = keine; Vorgabe Strg+H); nur mit
    /// search.replaceIdeSearch und search.replace.</summary>
    SearchReplaceKey: Integer;
    /// <summary>Taste für die Atlas-Suchleiste (#878, TShortCut, 0 = keine; Vorgabe Strg+F).</summary>
    SearchKey: Integer;
    /// <summary>Nächster Treffer der letzten Atlas-Suche (#878; Vorgabe F3).</summary>
    SearchNextKey: Integer;
    /// <summary>Voriger Treffer der letzten Atlas-Suche (#878; Vorgabe Umschalt+F3).</summary>
    SearchPreviousKey: Integer;
    /// <summary>„In Methode suchen“ (#877): Suchleiste mit Bereich Methode und dem Bezeichner am Cursor; gilt
    /// auch mit search.replaceIdeSearch aus (Vorgabe Strg+Umschalt+Alt+F).</summary>
    SearchMethodKey: Integer;
    /// <summary>Fenster öffnen (TShortCut, 0 = keins; Vorgabe Strg+Alt+P).</summary>
    ProblemsWindowKey: Integer;
    /// <summary>„Datei jetzt prüfen“ (#1744, keys.checkFile): offene Datei sofort prüfen, in jedem Modus von
    /// problems.update (TShortCut, 0 = keins; Vorgabe Strg+Umschalt+Alt+P).</summary>
    CheckFileKey: Integer;
    /// <summary>Kürzel „Zum interface-Teil“ (#1101, keys.gotoInterface); 0 = keins.</summary>
    GotoInterfaceKey: Integer;
    /// <summary>Kürzel „Zum implementation-Teil“ (#1101, keys.gotoImplementation); 0 = keins.</summary>
    GotoImplementationKey: Integer;
    /// <summary>Nächster bzw. vorheriger Befund in der Datei (#509, TShortCut, 0 = keins; Vorgabe Strg+Alt+F8
    /// und Strg+Alt+Umschalt+F8).</summary>
    NextProblemKey: Integer;
    PreviousProblemKey: Integer;
    ImplementationKey: Integer;
    TypeDefinitionKey: Integer;
    /// <summary>Tasten für den Wechsel (#775, TShortCut, 0 = keine): Strg+Umschalt+↑ und Strg+Umschalt+↓.</summary>
    MethodToggleUpKey: Integer;
    MethodToggleDownKey: Integer;
    /// <summary>Tastenkürzel-Übersicht (#520): Menüeintrag *Atlas › Tastenkürzel-Übersicht…* und Befehl der
    /// Palette; aus: beide ausgeblendet.</summary>
    KeyOverview: Boolean;
    /// <summary>Eigenes Kürzel für das Atlas-Fenster (#777, TShortCut, 0 = keins); Strg+F12 über replaceIdeDialog.</summary>
    UnitSearchKey: Integer;
    /// <summary>Kürzel für „Schnell öffnen“ (#503, keys.quickOpen, TShortCut, 0 = keins); Vorgabe Strg+P.</summary>
    QuickOpenKey: Integer;
    /// <summary>Kürzel „Zurück“ (#504, keys.navBack, TShortCut, 0 = keins); Vorgabe Alt+Links.</summary>
    NavBackKey: Integer;
    /// <summary>Kürzel „Vor“ (#504, keys.navForward); Vorgabe Alt+Rechts.</summary>
    NavForwardKey: Integer;
    /// <summary>Kürzel „Letzte Bearbeitungsstelle“ (#504, keys.lastEdit); Vorgabe Strg+Alt+Q.</summary>
    LastEditKey: Integer;
    /// <summary>Kürzel „Definition einblenden“ (#505, keys.peekDefinition); Vorgabe Alt+F12.</summary>
    PeekDefinitionKey: Integer;
    /// <summary>Kürzel „Referenzen einblenden“ (#505, keys.peekReferences); Vorgabe Umschalt+Alt+F12.</summary>
    PeekReferencesKey: Integer;
    /// <summary>Taste für „Lesezeichen 1 setzen“; 2–9 mit denselben Umschalttasten (#1104,
    /// bookmarks.quick.setKey); 0 = keine.</summary>
    QuickBookmarkSetKey: Integer;
    /// <summary>Taste für „Zu Lesezeichen 1 springen“; 2–9 mit denselben Umschalttasten (#1104,
    /// bookmarks.quick.jumpKey); 0 = keine.</summary>
    QuickBookmarkJumpKey: Integer;
    /// <summary>Taste „Nächstes Lesezeichen“ (#1104, keys.nextBookmark); 0 = keine.</summary>
    NextBookmarkKey: Integer;
    /// <summary>Taste „Voriges Lesezeichen“ (#1104, keys.previousBookmark); 0 = keine.</summary>
    PreviousBookmarkKey: Integer;
    /// <summary>Kürzel „Brotkrumenleiste“ (#590, keys.breadcrumbs); Vorgabe Strg+Umschalt+Punkt.</summary>
    BreadcrumbsKey: Integer;
    /// <summary>Kürzel „Nächste Änderung“ (#507, keys.nextChange); Vorgabe Strg+Alt+Bild↓.</summary>
    NextChangeKey: Integer;
    /// <summary>Kürzel „Vorherige Änderung“ (#507, keys.previousChange); Vorgabe Strg+Alt+Bild↑.</summary>
    PreviousChangeKey: Integer;
    /// <summary>Sprung zum Gegenstück (#635, keys.jumpToMatch).</summary>
    JumpToMatch: Boolean;
    /// <summary>Kürzel „Zum Gegenstück springen“ (#635, keys.jumpToMatchShortcut); Vorgabe Strg+Ü.</summary>
    JumpToMatchKey: Integer;
    /// <summary>Kürzel „Bis zum Gegenstück markieren“ (#635, keys.jumpToMatchSelect); Vorgabe Strg+Umschalt+Ü.</summary>
    JumpToMatchSelectKey: Integer;
    /// <summary>Taste für den Fokus ins Suchfeld, solange die Willkommensseite aktiv ist (TShortCut; 0 = keine).</summary>
    WelcomePageSearchKey: Integer;
    /// <summary>Taste für „Öffnen und bauen“ bzw. „Tests“ in der Zeile mit dem Fokus (#764, TShortCut; 0 = keine).
    /// </summary>
    WelcomePageQuickActionsBuildKey: Integer;
    WelcomePageQuickActionsTestKey: Integer;
    /// <summary>Tastenkürzel für die Liste der Benachrichtigungen (#601, TShortCut, 0 = keins); Vorrang wie die
    /// Editorbefehle (EditorKeysPriority, #399).</summary>
    NotificationsKey: Integer;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginNavigationKeysSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  System.Math;

{ TAtlasPluginEditingKeysSettings }

class function TAtlasPluginEditingKeysSettings.Defaults: TAtlasPluginEditingKeysSettings;
begin
  Result.PaletteKey := $6050; // Strg+Umschalt+P
  Result.CheckKey := $C078; // Strg+Alt+F9
  Result.CompletionKey := 0;
  Result.SignatureKey := 0;
  Result.CreateIssueKey := 0;
  Result.ActionsKey := $800D; // Alt+Enter
  Result.ExpandKey := $4057; // Strg+W
  Result.ShrinkKey := $6057; // Strg+Umschalt+W
  Result.TestUnitKey := 0;
  Result.GenerateMenuKey := $802D; // Alt+Einfg
  Result.QuickToggleKey := $E041; // Strg+Umschalt+Alt+A
  Result.DiagnosticModeKey := $E044; // Strg+Umschalt+Alt+D
  Result.KeyStartupCheck := True;
  Result.UndoKey := $C05A; // Strg+Alt+Z
  Result.RedoKey := $E05A; // Strg+Alt+Umschalt+Z
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
  Result.ExpressionTypeKey := $6054; // Strg+Umschalt+T
  Result.SafeDelete := True;
  Result.SafeDeleteKey := $802E; // Alt+Entf
  Result.MoveLines := True;
  Result.MoveLinesUpKey := $8026; // Alt+↑
  Result.MoveLinesDownKey := $8028; // Alt+↓
  Result.DuplicateLinesUpKey := $A026; // Umschalt+Alt+↑
  Result.DuplicateLinesDownKey := $A028; // Umschalt+Alt+↓
  Result.CompleteStatementKey := $600D; // Strg+Umschalt+Enter
  // Strg+Umschalt+Alt+F hat die Suche in der Methode (#877).
  Result.FormatCodeKey := $E04C; // Strg+Umschalt+Alt+L
  Result.MultiCursorNextKey := $4044; // Strg+D
  Result.MultiCursorSkipKey := $4044; // Strg+K, Strg+D
  Result.MultiCursorLineEndsKey := $A049; // Alt+Umschalt+I
  Result.MultiCursorAboveKey := $C026; // Strg+Alt+↑
  Result.MultiCursorBelowKey := $C028; // Strg+Alt+↓
end;

procedure TAtlasPluginEditingKeysSettings.Normalize;
begin
  // TShortCut ist ein Word.
  PaletteKey := EnsureRange(PaletteKey, 0, $FFFF);
  CheckKey := EnsureRange(CheckKey, 0, $FFFF);
  CompletionKey := EnsureRange(CompletionKey, 0, $FFFF);
  SignatureKey := EnsureRange(SignatureKey, 0, $FFFF);
  QuickToggleKey := EnsureRange(QuickToggleKey, 0, $FFFF);
  DiagnosticModeKey := EnsureRange(DiagnosticModeKey, 0, $FFFF);
  UndoKey := EnsureRange(UndoKey, 0, $FFFF);
  RedoKey := EnsureRange(RedoKey, 0, $FFFF);
  ToggleBlockCommentKey := EnsureRange(ToggleBlockCommentKey, 0, $FFFF);
  ToggleBlockCommentStyle := Choice(ToggleBlockCommentStyle, ['braces', 'parens']);
  ToggleBlockCommentFallback := Choice(ToggleBlockCommentFallback, ['lineComments', 'refuse']);
  ToggleBlockCommentWithoutSelection := Choice(ToggleBlockCommentWithoutSelection, ['statement', 'line']);
  NewLineBelowKey := EnsureRange(NewLineBelowKey, 0, $FFFF);
  NewLineAboveKey := EnsureRange(NewLineAboveKey, 0, $FFFF);
  UnwrapKey := EnsureRange(UnwrapKey, 0, $FFFF);
  ExpressionTypeKey := EnsureRange(ExpressionTypeKey, 0, $FFFF);
  SafeDeleteKey := EnsureRange(SafeDeleteKey, 0, $FFFF);
  MoveLinesUpKey := EnsureRange(MoveLinesUpKey, 0, $FFFF);
  MoveLinesDownKey := EnsureRange(MoveLinesDownKey, 0, $FFFF);
  DuplicateLinesUpKey := EnsureRange(DuplicateLinesUpKey, 0, $FFFF);
  DuplicateLinesDownKey := EnsureRange(DuplicateLinesDownKey, 0, $FFFF);
  CompleteStatementKey := EnsureRange(CompleteStatementKey, 0, $FFFF);
  FormatCodeKey := EnsureRange(FormatCodeKey, 0, $FFFF);
  MultiCursorNextKey := EnsureRange(MultiCursorNextKey, 0, $FFFF);
  MultiCursorSkipKey := EnsureRange(MultiCursorSkipKey, 0, $FFFF);
  MultiCursorLineEndsKey := EnsureRange(MultiCursorLineEndsKey, 0, $FFFF);
  MultiCursorAboveKey := EnsureRange(MultiCursorAboveKey, 0, $FFFF);
  MultiCursorBelowKey := EnsureRange(MultiCursorBelowKey, 0, $FFFF);
  CreateIssueKey := EnsureRange(CreateIssueKey, 0, $FFFF);
  GenerateMenuKey := EnsureRange(GenerateMenuKey, 0, $FFFF);
end;

procedure TAtlasPluginEditingKeysSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Number('PaletteKey', PaletteKey);
  AIo.Number('CheckKey', CheckKey);
  AIo.Number('CompletionKey', CompletionKey);
  AIo.Number('SignatureKey', SignatureKey);
  AIo.Number('CreateIssueKey', CreateIssueKey);
  AIo.Number('ActionsKey', ActionsKey);
  AIo.Number('ExpandKey', ExpandKey);
  AIo.Number('ShrinkKey', ShrinkKey);
  AIo.Number('TestUnitKey', TestUnitKey);
  AIo.Number('GenerateMenuKey', GenerateMenuKey);
  AIo.Number('QuickToggleKey', QuickToggleKey);
  AIo.Number('DiagnosticModeKey', DiagnosticModeKey);
  AIo.Flag('KeyStartupCheck', KeyStartupCheck);
  AIo.Number('UndoKey', UndoKey);
  AIo.Number('RedoKey', RedoKey);
  AIo.Flag('ToggleBlockComment', ToggleBlockComment);
  AIo.Number('ToggleBlockCommentKey', ToggleBlockCommentKey);
  AIo.Text('ToggleBlockCommentStyle', ToggleBlockCommentStyle);
  AIo.Text('ToggleBlockCommentFallback', ToggleBlockCommentFallback);
  AIo.Flag('ToggleBlockCommentOwnLines', ToggleBlockCommentOwnLines);
  AIo.Text('ToggleBlockCommentWithoutSelection', ToggleBlockCommentWithoutSelection);
  AIo.Flag('NewLineAround', NewLineAround);
  AIo.Number('NewLineBelowKey', NewLineBelowKey);
  AIo.Number('NewLineAboveKey', NewLineAboveKey);
  AIo.Flag('NewLineAroundStatementAware', NewLineAroundStatementAware);
  AIo.Flag('Unwrap', Unwrap);
  AIo.Number('UnwrapKey', UnwrapKey);
  AIo.Number('ExpressionTypeKey', ExpressionTypeKey);
  AIo.Flag('SafeDelete', SafeDelete);
  AIo.Number('SafeDeleteKey', SafeDeleteKey);
  AIo.Flag('MoveLines', MoveLines);
  AIo.Number('MoveLinesUpKey', MoveLinesUpKey);
  AIo.Number('MoveLinesDownKey', MoveLinesDownKey);
  AIo.Number('DuplicateLinesUpKey', DuplicateLinesUpKey);
  AIo.Number('DuplicateLinesDownKey', DuplicateLinesDownKey);
  AIo.Number('CompleteStatementKey', CompleteStatementKey);
  AIo.Number('FormatCodeKey', FormatCodeKey);
  AIo.Number('MultiCursorNextKey', MultiCursorNextKey);
  AIo.Number('MultiCursorSkipKey', MultiCursorSkipKey);
  AIo.Number('MultiCursorLineEndsKey', MultiCursorLineEndsKey);
  AIo.Number('MultiCursorAboveKey', MultiCursorAboveKey);
  AIo.Number('MultiCursorBelowKey', MultiCursorBelowKey);
end;

{ TAtlasPluginKeyPrioritiesSettings }

class function TAtlasPluginKeyPrioritiesSettings.Defaults: TAtlasPluginKeyPrioritiesSettings;
begin
  Result.PaletteKeyPriority := False;
  Result.CheckKeyPriority := False;
  Result.CompletionKeyPriority := False;
  Result.SignatureKeyPriority := False;
  Result.EditorKeysPriority := False;
  Result.QuickToggleKeyPriority := False;
  Result.DiagnosticModeKeyPriority := False;
  Result.QuickBookmarkKeyPriority := True;
  Result.QuickBookmarkSetKeyPriority := True;
  Result.QuickBookmarkJumpKeyPriority := True;
end;

procedure TAtlasPluginKeyPrioritiesSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('PaletteKeyPriority', PaletteKeyPriority);
  AIo.Flag('CheckKeyPriority', CheckKeyPriority);
  AIo.Flag('CompletionKeyPriority', CompletionKeyPriority);
  AIo.Flag('SignatureKeyPriority', SignatureKeyPriority);
  AIo.Flag('EditorKeysPriority', EditorKeysPriority);
  AIo.Flag('QuickToggleKeyPriority', QuickToggleKeyPriority);
  AIo.Flag('DiagnosticModeKeyPriority', DiagnosticModeKeyPriority);
  AIo.Flag('QuickBookmarkKeyPriority', QuickBookmarkKeyPriority);
  AIo.Flag('QuickBookmarkSetKeyPriority', QuickBookmarkSetKeyPriority);
  AIo.Flag('QuickBookmarkJumpKeyPriority', QuickBookmarkJumpKeyPriority);
end;

{ TAtlasPluginNavigationKeysSettings }

class function TAtlasPluginNavigationKeysSettings.Defaults: TAtlasPluginNavigationKeysSettings;
begin
  Result.BookmarkKey := $C04B; // Strg+Alt+K
  Result.HideElementKey := $40BE; // Strg+.
  Result.SearchReplaceKey := $4048; // Strg+H
  Result.SearchKey := $4046; // Strg+F
  Result.SearchNextKey := $72; // F3
  Result.SearchPreviousKey := $2072; // Umschalt+F3
  Result.SearchMethodKey := $E046; // Strg+Umschalt+Alt+F
  Result.ProblemsWindowKey := $C050; // Strg+Alt+P
  Result.CheckFileKey := $E050; // Strg+Umschalt+Alt+P
  Result.GotoInterfaceKey := 0;
  Result.GotoImplementationKey := 0;
  Result.NextProblemKey := $C077; // Strg+Alt+F8
  Result.PreviousProblemKey := $E077; // Strg+Alt+Umschalt+F8
  Result.ImplementationKey := $C049; // Strg+Alt+I
  Result.TypeDefinitionKey := 0;
  Result.MethodToggleUpKey := $6026; // Strg+Umschalt+↑
  Result.MethodToggleDownKey := $6028; // Strg+Umschalt+↓
  Result.KeyOverview := True;
  Result.UnitSearchKey := 0;
  Result.QuickOpenKey := $4050; // Strg+P
  Result.NavBackKey := $8025; // Alt+Links
  Result.NavForwardKey := $8027; // Alt+Rechts
  Result.LastEditKey := $C051; // Strg+Alt+Q
  Result.PeekDefinitionKey := $807B; // Alt+F12
  Result.PeekReferencesKey := $A07B; // Umschalt+Alt+F12
  Result.QuickBookmarkSetKey := $6031; // Strg+Umschalt+1
  Result.QuickBookmarkJumpKey := $4031; // Strg+1
  Result.NextBookmarkKey := 0;
  Result.PreviousBookmarkKey := 0;
  Result.BreadcrumbsKey := $60BE; // Strg+Umschalt+.
  // Strg+Alt+↑/↓ springt in RAD Studio schon zwischen Methoden.
  Result.NextChangeKey := $C022; // Strg+Alt+Bild↓
  Result.PreviousChangeKey := $C021; // Strg+Alt+Bild↑
  Result.JumpToMatch := True;
  Result.JumpToMatchKey := $40BA; // Strg+Ü (VK_OEM_1 auf deutscher Tastatur)
  Result.JumpToMatchSelectKey := $60BA; // Strg+Umschalt+Ü
  Result.WelcomePageSearchKey := $4045; // Strg+E
  Result.WelcomePageQuickActionsBuildKey := $4042; // Strg+B
  Result.WelcomePageQuickActionsTestKey := $4054; // Strg+T
  Result.NotificationsKey := $E04E; // Strg+Umschalt+Alt+N
end;

procedure TAtlasPluginNavigationKeysSettings.Normalize;
begin
  WelcomePageSearchKey := EnsureRange(WelcomePageSearchKey, 0, $FFFF);
  WelcomePageQuickActionsBuildKey := EnsureRange(WelcomePageQuickActionsBuildKey, 0, $FFFF);
  WelcomePageQuickActionsTestKey := EnsureRange(WelcomePageQuickActionsTestKey, 0, $FFFF);
  MethodToggleUpKey := EnsureRange(MethodToggleUpKey, 0, $FFFF);
  MethodToggleDownKey := EnsureRange(MethodToggleDownKey, 0, $FFFF);
  UnitSearchKey := EnsureRange(UnitSearchKey, 0, $FFFF);
  QuickOpenKey := EnsureRange(QuickOpenKey, 0, $FFFF);
  NavBackKey := EnsureRange(NavBackKey, 0, $FFFF);
  NavForwardKey := EnsureRange(NavForwardKey, 0, $FFFF);
  LastEditKey := EnsureRange(LastEditKey, 0, $FFFF);
  PeekDefinitionKey := EnsureRange(PeekDefinitionKey, 0, $FFFF);
  PeekReferencesKey := EnsureRange(PeekReferencesKey, 0, $FFFF);
  BreadcrumbsKey := EnsureRange(BreadcrumbsKey, 0, $FFFF);
  QuickBookmarkSetKey := EnsureRange(QuickBookmarkSetKey, 0, $FFFF);
  QuickBookmarkJumpKey := EnsureRange(QuickBookmarkJumpKey, 0, $FFFF);
  NextBookmarkKey := EnsureRange(NextBookmarkKey, 0, $FFFF);
  PreviousBookmarkKey := EnsureRange(PreviousBookmarkKey, 0, $FFFF);
  NextChangeKey := EnsureRange(NextChangeKey, 0, $FFFF);
  PreviousChangeKey := EnsureRange(PreviousChangeKey, 0, $FFFF);
  JumpToMatchKey := EnsureRange(JumpToMatchKey, 0, $FFFF);
  JumpToMatchSelectKey := EnsureRange(JumpToMatchSelectKey, 0, $FFFF);
  BookmarkKey := EnsureRange(BookmarkKey, 0, $FFFF);
  HideElementKey := EnsureRange(HideElementKey, 0, $FFFF);
  ProblemsWindowKey := EnsureRange(ProblemsWindowKey, 0, $FFFF);
  CheckFileKey := EnsureRange(CheckFileKey, 0, $FFFF);
  GotoInterfaceKey := EnsureRange(GotoInterfaceKey, 0, $FFFF);
  GotoImplementationKey := EnsureRange(GotoImplementationKey, 0, $FFFF);
  NextProblemKey := EnsureRange(NextProblemKey, 0, $FFFF);
  PreviousProblemKey := EnsureRange(PreviousProblemKey, 0, $FFFF);
  SearchKey := EnsureRange(SearchKey, 0, $FFFF);
  SearchReplaceKey := EnsureRange(SearchReplaceKey, 0, $FFFF);
  SearchNextKey := EnsureRange(SearchNextKey, 0, $FFFF);
  SearchPreviousKey := EnsureRange(SearchPreviousKey, 0, $FFFF);
  SearchMethodKey := EnsureRange(SearchMethodKey, 0, $FFFF);
  NotificationsKey := EnsureRange(NotificationsKey, 0, $FFFF);
end;

procedure TAtlasPluginNavigationKeysSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Number('BookmarkKey', BookmarkKey);
  AIo.Number('HideElementKey', HideElementKey);
  AIo.Number('SearchReplaceKey', SearchReplaceKey);
  AIo.Number('SearchKey', SearchKey);
  AIo.Number('SearchNextKey', SearchNextKey);
  AIo.Number('SearchPreviousKey', SearchPreviousKey);
  AIo.Number('SearchMethodKey', SearchMethodKey);
  AIo.Number('ProblemsWindowKey', ProblemsWindowKey);
  AIo.Number('CheckFileKey', CheckFileKey);
  AIo.Number('GotoInterfaceKey', GotoInterfaceKey);
  AIo.Number('GotoImplementationKey', GotoImplementationKey);
  AIo.Number('NextProblemKey', NextProblemKey);
  AIo.Number('PreviousProblemKey', PreviousProblemKey);
  AIo.Number('ImplementationKey', ImplementationKey);
  AIo.Number('TypeDefinitionKey', TypeDefinitionKey);
  AIo.Number('MethodToggleUpKey', MethodToggleUpKey);
  AIo.Number('MethodToggleDownKey', MethodToggleDownKey);
  AIo.Flag('KeyOverview', KeyOverview);
  AIo.Number('UnitSearchKey', UnitSearchKey);
  AIo.Number('QuickOpenKey', QuickOpenKey);
  AIo.Number('NavBackKey', NavBackKey);
  AIo.Number('NavForwardKey', NavForwardKey);
  AIo.Number('LastEditKey', LastEditKey);
  AIo.Number('PeekDefinitionKey', PeekDefinitionKey);
  AIo.Number('PeekReferencesKey', PeekReferencesKey);
  AIo.Number('QuickBookmarkSetKey', QuickBookmarkSetKey);
  AIo.Number('QuickBookmarkJumpKey', QuickBookmarkJumpKey);
  AIo.Number('NextBookmarkKey', NextBookmarkKey);
  AIo.Number('PreviousBookmarkKey', PreviousBookmarkKey);
  AIo.Number('BreadcrumbsKey', BreadcrumbsKey);
  AIo.Number('NextChangeKey', NextChangeKey);
  AIo.Number('PreviousChangeKey', PreviousChangeKey);
  AIo.Flag('JumpToMatch', JumpToMatch);
  AIo.Number('JumpToMatchKey', JumpToMatchKey);
  AIo.Number('JumpToMatchSelectKey', JumpToMatchSelectKey);
  AIo.Number('WelcomePageSearchKey', WelcomePageSearchKey);
  AIo.Number('WelcomePageQuickActionsBuildKey', WelcomePageQuickActionsBuildKey);
  AIo.Number('WelcomePageQuickActionsTestKey', WelcomePageQuickActionsTestKey);
  AIo.Number('NotificationsKey', NotificationsKey);
end;

end.
