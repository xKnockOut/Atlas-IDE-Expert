unit Atlas.Core.Commands.KeyConflicts;

// Verträglichkeit mit anderen Erweiterungen (#494), Teil ohne Open Tools API:
// - Tastenkürzel von Atlas gegen bekannte Belegungen prüfen (Aktionen der IDE
//   und anderer Erweiterungen, Editor-Belegungen der Standard-Tastaturbelegung).
//   Bei Konflikt belegt Atlas die Taste nur mit ausdrücklichem Vorrang; sonst
//   bleibt die fremde Belegung aktiv.
// - Erweiterungen mit eigener Vervollständigung an ihren Packages erkennen;
//   Atlas weist nur darauf hin und schaltet fremde Erweiterungen nie ab.
// - Seite „Tastenkonflikte“: je Atlas-Taste (Befehlspalette, Syntaxprüfung,
//   Vervollständigung, Parameter-Hint, Schnellschalter #604, Diagnosemodus #479) Taste, fremde Belegung und die Wahl
//   „Atlas verwenden“, „anderer Belegung überlassen“ oder „andere Taste für
//   Atlas“ (TAtlasKeyEntry).
// - Alle Atlas-Tasten für die Tastenkürzel-Übersicht (#520) und die Einrichtung
//   (#625): AllFromSettings ergänzt die Seite „Tastenkonflikte“ um die Tasten
//   der Editorbefehle (#399), des Änderungsprotokolls (#721), des Suchfelds
//   der Willkommensseite (#760), des Wechsels Deklaration ⇄ Implementierung
//   (#775), des Wechsels Unit ⇄ Testunit (#189), des Fensters „Units
//   suchen“ (#777, eigene Taste und Übernahme von Strg+F12) und von
//   „Lesezeichen setzen…“ (#622, Strg+Alt+K) und des Erzeugen-Menüs (#719,
//   Alt+Einfg) und von „Element ausblenden …“ (#628, Strg+.) und von Zeilen
//   verschieben und duplizieren (#634, Alt+↑/↓, Umschalt+Alt+↑/↓) und der Mehrfachmarken (#589, Strg+D,
//   Strg+K Strg+D, Alt+Umschalt+I, Strg+Alt+↑/↓) und der schnellen
//   Lesezeichen (#1104: Strg+Umschalt+K, Strg+Umschalt+1…9, Strg+1…9 auch auf
//   der Seite „Tastenkonflikte“, dazu nächstes/voriges Lesezeichen). Ist eine Funktion
//   abgeschaltet, steht ihr Eintrag mit Disabled in der Liste: Atlas belegt die
//   Taste dann nicht, also ist sie auch kein Konflikt.
// Kürzel sind TShortCut-Werte (Word) wie in Vcl.Menus.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin;

type
  {$SCOPEDENUMS ON}
  /// <summary>Die ersten sechs stehen auf der Seite „Tastenkonflikte“ (FromSettings); die übrigen nur in der
  /// Übersicht (#520, AllFromSettings): Editorbefehle mit gemeinsamem Vorrang EditorKeysPriority, das Suchfeld
  /// der Willkommensseite, Deklaration ⇄ Implementierung mit zwei Tasten (#775), Unit ⇄ Testunit (#189), die
  /// eigene Taste für „Units suchen“, die Übernahme von Strg+F12 durch „Units suchen“ (#777) und „Lesezeichen
  /// setzen…“ (#622), das Erzeugen-Menü (#719), die Benachrichtigungen (#601) und die Schnellaktionen der
  /// Willkommensseite „Öffnen und bauen“ und „Tests“ (#764), „Element ausblenden …“ (#628), nächster und voriger
  /// Befund (#509), „Schnell öffnen“ (#503), Zurück, Vor und letzte Bearbeitungsstelle (#504) sowie Definition und
  /// Referenzen einblenden (#505), das Fenster „Atlas-Prüfung“ (#909) und die Abschnittssprünge zum interface- und
  /// implementation-Teil (#1101). Schnelle Lesezeichen (#1104): QuickBookmark (Strg+Umschalt+K), QuickBookmarkSet
  /// und QuickBookmarkJump (je eine Zeile für die Tasten 1–9, Key ist die Taste für 1) stehen mit eigener Wahl auch
  /// auf der Seite „Tastenkonflikte“; NextBookmark und PreviousBookmark nur in der Übersicht. Gezielt
  /// hineinspringen (#836) nur in der Übersicht. „Datei jetzt prüfen“ (#1744). Neue Funktionen
  /// nur hinten anhängen: Die Ordnungszahl steckt in Kennungen der Übersicht. Sicher löschen (#716). Neue Zeile am Ende des Abschnitts (#1768).</summary>
  TAtlasKeyFunction = (Palette, Check, Completion, Signature, QuickToggle, DiagnosticMode, CodeActions,
    ExpandSelection, ShrinkSelection, GoToImplementation, TypeDefinition, UndoChange, RedoChange, WelcomeSearch,
    MethodToggleUp, MethodToggleDown, TestUnit, UnitSearch, UnitSearchIde, Bookmark, GenerateMenu,
    Notifications, WelcomeQuickBuild, WelcomeQuickTests, HideElement, NextProblem, PreviousProblem, QuickOpen,
    NavBack, NavForward, LastEdit, PeekDefinition, PeekReferences, Breadcrumbs, JumpToMatch,
    JumpToMatchSelect, NextChange, PreviousChange, MoveLinesUp, MoveLinesDown, DuplicateLinesUp,
    DuplicateLinesDown, CompleteStatement, MultiCursorNext, MultiCursorSkip, MultiCursorLineEnds,
    MultiCursorAbove, MultiCursorBelow, Search, SearchNext, SearchPrevious,
    SearchMethod, FormatCode, ToggleBlockComment, NewLineBelow, NewLineAbove, Unwrap, ProblemsWindow,
    SectionInterface, SectionImplementation, QuickBookmark, QuickBookmarkSet, QuickBookmarkJump, NextBookmark,
    PreviousBookmark, SearchReplace, StepIntoTarget, ExpressionType, SafeDelete, CreateIssue,
    DesignerSearch, CheckFile, SectionAppend, DesignerSelectionSetsSave, DesignerShowComponent,
    DesignerInlineCaption, DesignerSelectionBar, DesignerMagnifier, DesignerUsages);
  TAtlasKeyChoice = (UseAtlas, LeaveOther, OtherKey);
  /// <summary>NoKey: keine Taste; IdeKey: Taste der IDE über Code Insight, Atlas belegt nichts selbst;
  /// Free: Atlas belegt die freie Taste; AtlasWins: belegt, Atlas hat Vorrang; Left: belegt, Atlas
  /// überlässt sie der anderen Belegung.</summary>
  TAtlasKeyStatus = (NoKey, IdeKey, Free, AtlasWins, Left);
  {$SCOPEDENUMS OFF}

  /// <summary>Eine Taste von Atlas auf der Seite „Tastenkonflikte“ (#494).</summary>
  TAtlasKeyEntry = record
    Func: TAtlasKeyFunction;
    /// <summary>0 = keine Taste; bei Vervollständigung und Parameter-Hint die Taste der IDE.</summary>
    Key: Word;
    Priority: Boolean;
    /// <summary>Funktion abgeschaltet (etwa Deklaration ⇄ Implementierung aus, „Units suchen“ aus): Atlas belegt
    /// die Taste nicht, sie ist kein Konflikt (Status NoKey). Key behält den eingestellten Wert.</summary>
    Disabled: Boolean;
    class function Create(AFunc: TAtlasKeyFunction; AKey: Word; APriority: Boolean): TAtlasKeyEntry; overload; static;
    class function Create(AFunc: TAtlasKeyFunction; AKey: Word; APriority, AEnabled: Boolean): TAtlasKeyEntry;
      overload; static;
    /// <summary>Alle Atlas-Tasten aus den Einstellungen, in fester Reihenfolge.</summary>
    class function FromSettings(const ASettings: TAtlasPluginSettings): TArray<TAtlasKeyEntry>; static;
    /// <summary>Jede Taste von Atlas (#520): FromSettings, dann die Editorbefehle (Vorrang aus
    /// EditorKeysPriority), das Suchfeld der Willkommensseite (immer mit Vorrang: es nimmt die Taste nur dort,
    /// solange die Seite aktiv ist), Deklaration ⇄ Implementierung (#775), Unit ⇄ Testunit (#189), „Units
    /// suchen“ (#777, eigene Taste und Strg+F12) und „Lesezeichen setzen…“ (#622). Abgeschaltete Funktionen kommen
    /// mit Disabled.</summary>
    class function AllFromSettings(const ASettings: TAtlasPluginSettings): TArray<TAtlasKeyEntry>; static;
    /// <summary>Zweiter Teil von AllFromSettings ab dem Navigationsverlauf; AShared ist der gemeinsame Vorrang
    /// der Editorbefehle.</summary>
    class function MoreFromSettings(const ASettings: TAtlasPluginSettings;
      AShared: Boolean): TArray<TAtlasKeyEntry>; static;
    /// <summary>Tasten und Vorrang zurück in die Einstellungen; Disabled und die feste Taste Strg+F12 nicht (dafür
    /// gibt es eigene Schalter).</summary>
    class procedure ToSettings(const AEntries: TArray<TAtlasKeyEntry>; var ASettings: TAtlasPluginSettings); static;
    /// <summary>Taste der IDE, über die Code Insight Atlas aufruft (Strg+Leer, Strg+Umschalt+Leer); sonst 0.</summary>
    function IdeKey: Word;
    function Choice: TAtlasKeyChoice;
    /// <summary>Wahl übernehmen: Atlas verwenden = Vorrang; sonst ohne Vorrang. Atlas verwenden ohne eigene
    /// Taste bei Vervollständigung und Parameter-Hint: Atlas belegt die Taste der IDE selbst.</summary>
    procedure Choose(AChoice: TAtlasKeyChoice);
    /// <summary>Zustand bei fremder Belegung AOwner ('' = frei); abgeschaltet NoKey.</summary>
    function Status(const AOwner: string): TAtlasKeyStatus;
  end;

  TAtlasKeyOwner = record
    ShortCut: Word;
    Owner: string;
    class function Create(AShortCut: Word; const AOwner: string): TAtlasKeyOwner; static;
  end;

  TAtlasKeyConflicts = class
  public const
    cScShift = $2000;
    cScCtrl = $4000;
    cScAlt = $8000;
    cPaletteDefault = cScCtrl or cScShift or Ord('P');
    cCheckDefault = cScCtrl or cScAlt or $78; // VK_F9
    cIdeCompletionKey = cScCtrl or $20; // Strg+Leer
    cIdeSignatureKey = cScCtrl or cScShift or $20; // Strg+Umschalt+Leer
    cQuickToggleDefault = cScCtrl or cScShift or cScAlt or Ord('A');
    /// <summary>Diagnosemodus (#479): Strg+Alt+Umschalt+A gehört schon den Schnellschaltern (#604).</summary>
    cDiagnosticModeDefault = cScCtrl or cScShift or cScAlt or Ord('D');
    /// <summary>Strg+F12 der IDE-Aktion „Units“; „Units suchen“ übernimmt sie (#777, unitSearch.replaceIdeDialog).
    /// </summary>
    cIdeUnitsKey = cScCtrl or $7B; // VK_F12
  public
    /// <summary>Editor-Belegungen der Standard-Tastaturbelegung, die keine Aktionen sind.</summary>
    class function KnownIdeKeys: TArray<TAtlasKeyOwner>; static;
    /// <summary>Wer belegt AShortCut schon? '' wenn frei.</summary>
    class function OwnerOf(AShortCut: Word; const AKeys: TArray<TAtlasKeyOwner>): string; static;
    /// <summary>Soll Atlas die Taste belegen? Nur frei oder mit Vorrang; 0 heißt „keine Taste“.</summary>
    class function ShouldBind(AShortCut: Word; const AOwner: string; APriority: Boolean): Boolean; static;
    /// <summary>Namen von Erweiterungen mit eigener Vervollständigung unter den geladenen Modulen.</summary>
    class function CompletionExtensions(const AModules: TArray<string>): TArray<string>; static;
  end;

implementation


uses
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TKeyConflictsText = (IDEPlayKeyboardMacro, IDERecordKeyboardMacro, IDECodeBrowsingFindDeclaration,
    IDESelectColumnBlockUp, IDESelectColumnBlockDown, IDEFindReferences, IDEAddToDoItem, IDEFoldingCtrlShiftK,
    IDEToggleBookmark, IDEGoToBookmark);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TKeyConflictsText] of string = (
    ('IDE: Tastaturmakro abspielen',
     'IDE: Tastaturmakro aufzeichnen',
     'IDE: Code-Browsing (Deklaration suchen)',
     'IDE: Spaltenblock nach oben markieren',
     'IDE: Spaltenblock nach unten markieren',
     'IDE: Referenzen suchen',
     'IDE: To-Do-Eintrag hinzufügen',
     'IDE: Faltung (Strg+Umschalt+K, dann U, E, A, T, O …)',
     'IDE: Lesezeichen %d umschalten',
     'IDE: Zu Lesezeichen %d springen'),
    ('IDE: Play keyboard macro',
     'IDE: Record keyboard macro',
     'IDE: Code browsing (find declaration)',
     'IDE: Select column block up',
     'IDE: Select column block down',
     'IDE: Find references',
     'IDE: Add To-Do item',
     'IDE: Folding (Ctrl+Shift+K, then U, E, A, T, O …)',
     'IDE: Toggle bookmark %d',
     'IDE: Go to bookmark %d'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TKeyConflictsText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;
{ TAtlasKeyEntry }

class function TAtlasKeyEntry.Create(AFunc: TAtlasKeyFunction; AKey: Word; APriority: Boolean): TAtlasKeyEntry;
begin
  Result := Create(AFunc, AKey, APriority, True);
end;

class function TAtlasKeyEntry.Create(AFunc: TAtlasKeyFunction; AKey: Word; APriority,
  AEnabled: Boolean): TAtlasKeyEntry;
begin
  Result.Func := AFunc;
  Result.Key := AKey;
  Result.Priority := APriority;
  Result.Disabled := not AEnabled;
end;

class function TAtlasKeyEntry.FromSettings(const ASettings: TAtlasPluginSettings): TArray<TAtlasKeyEntry>;
begin
  Result := [Create(TAtlasKeyFunction.Palette, Word(ASettings.PaletteKey), ASettings.PaletteKeyPriority),
    Create(TAtlasKeyFunction.Check, Word(ASettings.CheckKey), ASettings.CheckKeyPriority),
    Create(TAtlasKeyFunction.Completion, Word(ASettings.CompletionKey), ASettings.CompletionKeyPriority),
    Create(TAtlasKeyFunction.Signature, Word(ASettings.SignatureKey), ASettings.SignatureKeyPriority),
    Create(TAtlasKeyFunction.QuickToggle, Word(ASettings.QuickToggleKey), ASettings.QuickToggleKeyPriority),
    Create(TAtlasKeyFunction.DiagnosticMode, Word(ASettings.DiagnosticModeKey), ASettings.DiagnosticModeKeyPriority),
    // Schnelle Lesezeichen (#1104): Die Tasten gehören in der IDE den Lesezeichen bzw. der Faltung; Atlas nimmt sie
    // mit Vorrang, „anderer Belegung überlassen“ gibt sie zurück. Wartezeit 0 = Strg+Umschalt+K bleibt bei der IDE.
    Create(TAtlasKeyFunction.QuickBookmark, Word(ASettings.QuickBookmarkKey), ASettings.QuickBookmarkKeyPriority,
      ASettings.QuickBookmarks and (ASettings.QuickBookmarkChordWait > 0)),
    Create(TAtlasKeyFunction.QuickBookmarkSet, Word(ASettings.QuickBookmarkSetKey),
      ASettings.QuickBookmarkSetKeyPriority, ASettings.QuickBookmarks and ASettings.QuickBookmarksNumberedKeys),
    Create(TAtlasKeyFunction.QuickBookmarkJump, Word(ASettings.QuickBookmarkJumpKey),
      ASettings.QuickBookmarkJumpKeyPriority, ASettings.QuickBookmarks and ASettings.QuickBookmarksNumberedKeys)];
end;

class function TAtlasKeyEntry.AllFromSettings(const ASettings: TAtlasPluginSettings): TArray<TAtlasKeyEntry>;
var
  mShared, mSecondToggle: Boolean;
begin
  mShared := ASettings.EditorKeysPriority;
  // Beide Tasten des Wechsels gleich: Atlas belegt die Taste nur einmal (AddAttemptKey), also auch nur ein Eintrag.
  mSecondToggle := ASettings.MethodToggle and (ASettings.MethodToggleDownKey <> ASettings.MethodToggleUpKey);
  Result := FromSettings(ASettings) + [Create(TAtlasKeyFunction.CodeActions, Word(ASettings.ActionsKey), mShared),
    Create(TAtlasKeyFunction.ExpandSelection, Word(ASettings.ExpandKey), mShared),
    Create(TAtlasKeyFunction.ShrinkSelection, Word(ASettings.ShrinkKey), mShared),
    Create(TAtlasKeyFunction.GoToImplementation, Word(ASettings.ImplementationKey), mShared),
    Create(TAtlasKeyFunction.TypeDefinition, Word(ASettings.TypeDefinitionKey), mShared),
    Create(TAtlasKeyFunction.UndoChange, Word(ASettings.UndoKey), mShared),
    Create(TAtlasKeyFunction.RedoChange, Word(ASettings.RedoKey), mShared),
    Create(TAtlasKeyFunction.WelcomeSearch, Word(ASettings.WelcomePageSearchKey), True,
      ASettings.WelcomePage and ASettings.WelcomePageSearch),
    // Deklaration ⇄ Implementierung (#775): aus = die Klassennavigation der IDE behält die Tasten.
    Create(TAtlasKeyFunction.MethodToggleUp, Word(ASettings.MethodToggleUpKey), mShared, ASettings.MethodToggle),
    Create(TAtlasKeyFunction.MethodToggleDown, Word(ASettings.MethodToggleDownKey), mShared, mSecondToggle),
    Create(TAtlasKeyFunction.TestUnit, Word(ASettings.TestUnitKey), mShared),
    // Units suchen (#777): eigene Taste als Editorbefehl; Strg+F12 bleibt die Aktion der IDE, Atlas hängt sich nur
    // an ihre Ausführung (bewusst übernommen, daher mit Vorrang).
    Create(TAtlasKeyFunction.UnitSearch, Word(ASettings.UnitSearchKey), mShared, ASettings.UnitSearchEnabled),
    Create(TAtlasKeyFunction.UnitSearchIde, TAtlasKeyConflicts.cIdeUnitsKey, True,
      ASettings.UnitSearchEnabled and ASettings.UnitSearchReplaceIdeDialog),
    // Benannte Lesezeichen (#622): aus = Atlas belegt Strg+Alt+K nicht.
    Create(TAtlasKeyFunction.Bookmark, Word(ASettings.BookmarkKey), mShared, ASettings.BookmarksNamed),
    // Erzeugen-Menü (#719): aus = Alt+Einfg bleibt frei.
    Create(TAtlasKeyFunction.GenerateMenu, Word(ASettings.GenerateMenuKey), mShared, ASettings.GenerateMenu),
    // Benachrichtigungszentrale (#601): aus = Strg+Umschalt+Alt+N bleibt frei.
    Create(TAtlasKeyFunction.Notifications, Word(ASettings.NotificationsKey), mShared, ASettings.Notifications),
    // Schnellaktionen der Willkommensseite (#764): nur in der Zeile von „Projekte“ bzw. „Weiterarbeiten“ mit dem
    // Fokus, dort immer mit Vorrang (wie das Suchfeld); aus = Strg+B und Strg+T bleiben dort der IDE.
    Create(TAtlasKeyFunction.WelcomeQuickBuild, Word(ASettings.WelcomePageQuickActionsBuildKey), True,
      ASettings.WelcomePage and ASettings.WelcomePageQuickActions),
    Create(TAtlasKeyFunction.WelcomeQuickTests, Word(ASettings.WelcomePageQuickActionsTestKey), True,
      ASettings.WelcomePage and ASettings.WelcomePageQuickActions),
    // Ausblenden am Element (#628): nimmt die Taste nur auf einer Zeile mit Atlas-Element, sonst geht sie an die
    // IDE weiter (Strg+. = IDE Insight); darum immer mit Vorrang, ohne fremde Belegung abzuschalten.
    Create(TAtlasKeyFunction.HideElement, Word(ASettings.HideElementKey), True),
    // Nächster/vorheriger Befund (#509): nur mit Problemen im Editor.
    Create(TAtlasKeyFunction.NextProblem, Word(ASettings.NextProblemKey), mShared, ASettings.Problems),
    Create(TAtlasKeyFunction.PreviousProblem, Word(ASettings.PreviousProblemKey), mShared, ASettings.Problems),
    // Schnell öffnen (#503): aus = Strg+P bleibt der IDE.
    Create(TAtlasKeyFunction.QuickOpen, Word(ASettings.QuickOpenKey), mShared, ASettings.QuickOpen)];
  Result := Result + MoreFromSettings(ASettings, mShared);
end;

class function TAtlasKeyEntry.MoreFromSettings(const ASettings: TAtlasPluginSettings;
  AShared: Boolean): TArray<TAtlasKeyEntry>;
begin
  Result := [
    // Navigationsverlauf (#504): Alt+Links/Rechts sind in der IDE „Zurück/Vor“ ihrer eigenen Navigation; der Atlas-
    // Verlauf führt deren Sprünge mit, darum mit Vorrang. Aus = die IDE behält die Tasten.
    Create(TAtlasKeyFunction.NavBack, Word(ASettings.NavBackKey), True, ASettings.NavHistory),
    Create(TAtlasKeyFunction.NavForward, Word(ASettings.NavForwardKey), True, ASettings.NavHistory),
    Create(TAtlasKeyFunction.LastEdit, Word(ASettings.LastEditKey), AShared, ASettings.NavHistory),
    // Definition und Referenzen einblenden (#505).
    Create(TAtlasKeyFunction.PeekDefinition, Word(ASettings.PeekDefinitionKey), AShared, ASettings.Peek),
    Create(TAtlasKeyFunction.PeekReferences, Word(ASettings.PeekReferencesKey), AShared, ASettings.Peek),
    // Brotkrumenleiste (#590).
    Create(TAtlasKeyFunction.Breadcrumbs, Word(ASettings.BreadcrumbsKey), AShared, ASettings.Breadcrumbs),
    // Sprung zum Gegenstück (#635).
    Create(TAtlasKeyFunction.JumpToMatch, Word(ASettings.JumpToMatchKey), AShared, ASettings.JumpToMatch),
    Create(TAtlasKeyFunction.JumpToMatchSelect, Word(ASettings.JumpToMatchSelectKey), AShared, ASettings.JumpToMatch),
    // Nächste/vorherige Änderung (#507).
    Create(TAtlasKeyFunction.NextChange, Word(ASettings.NextChangeKey), AShared, ASettings.GitGutter),
    Create(TAtlasKeyFunction.PreviousChange, Word(ASettings.PreviousChangeKey), AShared, ASettings.GitGutter),
    // Zeilen verschieben und duplizieren (#634): Alt+↑ ist in der IDE Code-Browsing, Umschalt+Alt+↑/↓ markiert
    // Spaltenblöcke; bewusst übernommen, darum mit Vorrang. Aus = die IDE behält die Tasten.
    Create(TAtlasKeyFunction.MoveLinesUp, Word(ASettings.MoveLinesUpKey), True, ASettings.MoveLines),
    Create(TAtlasKeyFunction.MoveLinesDown, Word(ASettings.MoveLinesDownKey), True, ASettings.MoveLines),
    Create(TAtlasKeyFunction.DuplicateLinesUp, Word(ASettings.DuplicateLinesUpKey), True, ASettings.MoveLines),
    Create(TAtlasKeyFunction.DuplicateLinesDown, Word(ASettings.DuplicateLinesDownKey), True, ASettings.MoveLines),
    // Anweisung vervollständigen (#697): Strg+Umschalt+Enter sucht in der IDE Referenzen; bewusst übernommen.
    Create(TAtlasKeyFunction.CompleteStatement, Word(ASettings.CompleteStatementKey), True,
      ASettings.CompleteStatement),
    // Mehrfachmarken (#589, experimentell): bewusst eingeschaltet, darum mit Vorrang (Strg+D formatiert in der IDE
    // den Quelltext; ohne Wort am Cursor geht die Taste dorthin weiter). Überspringen wirkt nur nach Strg+K,
    // solange mehrere Marken aktiv sind. Aus = die IDE behält die Tasten.
    Create(TAtlasKeyFunction.MultiCursorNext, Word(ASettings.MultiCursorNextKey), True, ASettings.MultiCursor),
    Create(TAtlasKeyFunction.MultiCursorSkip, Word(ASettings.MultiCursorSkipKey), True, ASettings.MultiCursor),
    Create(TAtlasKeyFunction.MultiCursorLineEnds, Word(ASettings.MultiCursorLineEndsKey), True,
      ASettings.MultiCursor),
    Create(TAtlasKeyFunction.MultiCursorAbove, Word(ASettings.MultiCursorAboveKey), True, ASettings.MultiCursor),
    Create(TAtlasKeyFunction.MultiCursorBelow, Word(ASettings.MultiCursorBelowKey), True, ASettings.MultiCursor),
    // Atlas-Suche (#878): Strg+F, F3 und Umschalt+F3 bewusst übernommen (Vorrang), nur mit search.replaceIdeSearch;
    // aus = die IDE behält ihre Suche. „In Methode suchen“ (#877) ist ein eigener Editorbefehl.
    Create(TAtlasKeyFunction.Search, Word(ASettings.SearchKey), True, ASettings.SearchReplaceIde),
    Create(TAtlasKeyFunction.SearchNext, Word(ASettings.SearchNextKey), True, ASettings.SearchReplaceIde),
    Create(TAtlasKeyFunction.SearchPrevious, Word(ASettings.SearchPreviousKey), True, ASettings.SearchReplaceIde),
    Create(TAtlasKeyFunction.SearchMethod, Word(ASettings.SearchMethodKey), AShared),
    // Suchen und ersetzen (#893): Strg+H wie Strg+F bewusst übernommen; mit search.replace aus gehört sie der IDE.
    Create(TAtlasKeyFunction.SearchReplace, Word(ASettings.SearchReplaceKey), True,
      ASettings.SearchReplaceIde and ASettings.SearchReplace),
    // Formatieren (#43): aus = keine Taste.
    Create(TAtlasKeyFunction.FormatCode, Word(ASettings.FormatCodeKey), AShared, ASettings.FormatCode),
    // Blockkommentar umschalten (#703): aus = Kürzel frei.
    Create(TAtlasKeyFunction.ToggleBlockComment, Word(ASettings.ToggleBlockCommentKey), AShared,
      ASettings.ToggleBlockComment),
    // Neue Zeile ober- oder unterhalb (#700): aus = Tasten frei.
    Create(TAtlasKeyFunction.NewLineBelow, Word(ASettings.NewLineBelowKey), AShared, ASettings.NewLineAround),
    Create(TAtlasKeyFunction.NewLineAbove, Word(ASettings.NewLineAboveKey), AShared, ASettings.NewLineAround),
    // Umschließung entfernen (#657): aus = Kürzel frei.
    Create(TAtlasKeyFunction.Unwrap, Word(ASettings.UnwrapKey), AShared, ASettings.Unwrap),
    // Fenster „Atlas-Prüfung“ (#909): aus = Kürzel frei.
    Create(TAtlasKeyFunction.ProblemsWindow, Word(ASettings.ProblemsWindowKey), AShared,
      ASettings.Problems and ASettings.ProblemsWindow),
    // Abschnittssprünge (#1101): wirken auch ohne Editorleiste; ohne Taste nichts belegt.
    Create(TAtlasKeyFunction.SectionInterface, Word(ASettings.GotoInterfaceKey), AShared),
    Create(TAtlasKeyFunction.SectionImplementation, Word(ASettings.GotoImplementationKey), AShared),
    // Nächstes/voriges Lesezeichen (#1104): Vorgabe ohne Taste.
    Create(TAtlasKeyFunction.NextBookmark, Word(ASettings.NextBookmarkKey), AShared, ASettings.QuickBookmarks),
    Create(TAtlasKeyFunction.PreviousBookmark, Word(ASettings.PreviousBookmarkKey), AShared, ASettings.QuickBookmarks),
    // Gezielt hineinspringen (#836): nur im angehaltenen Zustand, sonst geht die Taste an die IDE; aus = Kürzel frei.
    Create(TAtlasKeyFunction.StepIntoTarget, Word(ASettings.DebugStepIntoTargetKey), AShared,
      ASettings.DebugStepIntoTarget),
    // Typ des markierten Ausdrucks (#689): Strg+Umschalt+T ist in der IDE „To-Do-Eintrag hinzufügen“; bewusst
    // übernommen, darum mit Vorrang. Aus = die IDE behält die Taste.
    Create(TAtlasKeyFunction.ExpressionType, Word(ASettings.ExpressionTypeKey), True, ASettings.ExpressionType),
    // Sicher löschen (#716): aus = Kürzel frei.
    Create(TAtlasKeyFunction.SafeDelete, Word(ASettings.SafeDeleteKey), AShared, ASettings.SafeDelete),
    // Issue anlegen (#1268): frei belegbar, ohne Vorgabe.
    Create(TAtlasKeyFunction.CreateIssue, Word(ASettings.CreateIssueKey), AShared,
      ASettings.WelcomePage and ASettings.IssuesCreate),
    // Komponenten suchen (#1442): nur solange ein Designer gezeigt wird, dort mit Vorrang (wie das Suchfeld der
    // Willkommensseite).
    Create(TAtlasKeyFunction.DesignerSearch, Word(ASettings.DesignerSearchKey), True, ASettings.EditorDesignerBar),
    // Datei jetzt prüfen (#1744): in jedem Modus von problems.update; ohne Prüfregeln ist das Kürzel frei.
    Create(TAtlasKeyFunction.CheckFile, Word(ASettings.CheckFileKey), AShared, ASettings.Problems),
    // Neue Zeile am Ende des Abschnitts (#1768): frei belegbar, ohne Vorgabe.
    Create(TAtlasKeyFunction.SectionAppend, Word(ASettings.SectionAppendKey), AShared,
      ASettings.Breadcrumbs and ASettings.BreadcrumbsSectionAppend),
    // Auswahl speichern (#739): nur solange der Formular-Designer den Fokus hat, dort mit Vorrang (wie DesignerSearch).
    Create(TAtlasKeyFunction.DesignerSelectionSetsSave, Word(ASettings.DesignerSelectionSetsSaveKey), True,
      ASettings.EditorDesignerBar and ASettings.DesignerSelectionSets),
    // Im Designer zeigen (#511): Editorbefehl; Umschalt+F12 ist in der IDE „Formulare anzeigen“.
    Create(TAtlasKeyFunction.DesignerShowComponent, Word(ASettings.DesignerShowInDesignerKey), AShared,
      ASettings.DesignerShowInDesigner),
    // Text im Designer bearbeiten (#748): nur solange der Formular-Designer den Fokus hat, dort mit Vorrang.
    Create(TAtlasKeyFunction.DesignerInlineCaption, Word(ASettings.DesignerInlineCaptionKey), True,
      ASettings.EditorDesignerBar and ASettings.DesignerInlineCaption),
    // Auswahlleiste und Lupe im Designer: nur solange der Formular-Designer den Fokus hat, dort mit Vorrang.
    Create(TAtlasKeyFunction.DesignerSelectionBar, Word(ASettings.DesignerSelectionBarKey), True,
      ASettings.EditorDesignerBar and ASettings.DesignerSelectionBar),
    Create(TAtlasKeyFunction.DesignerMagnifier, Word(ASettings.DesignerMagnifierKey), True,
      ASettings.EditorDesignerBar and ASettings.DesignerMagnifier),
    // Verwendungen im Code (#750): nur solange der Formular-Designer den Fokus hat, dort mit Vorrang.
    Create(TAtlasKeyFunction.DesignerUsages, Word(ASettings.DesignerUsagesKey), True,
      ASettings.EditorDesignerBar and ASettings.DesignerUsages)];
end;

/// <summary>Teil 1 von ToSettings: Taste (und Vorrang) von AEntry in ASettings, wenn die Funktion hierher
/// gehört.</summary>
procedure StoreKeys1(const AEntry: TAtlasKeyEntry; var ASettings: TAtlasPluginSettings);
begin
  case AEntry.Func of
    TAtlasKeyFunction.Palette:
      begin
        ASettings.PaletteKey := AEntry.Key;
        ASettings.PaletteKeyPriority := AEntry.Priority;
      end;
    TAtlasKeyFunction.Check:
      begin
        ASettings.CheckKey := AEntry.Key;
        ASettings.CheckKeyPriority := AEntry.Priority;
      end;
    TAtlasKeyFunction.Completion:
      begin
        ASettings.CompletionKey := AEntry.Key;
        ASettings.CompletionKeyPriority := AEntry.Priority;
      end;
    TAtlasKeyFunction.Signature:
      begin
        ASettings.SignatureKey := AEntry.Key;
        ASettings.SignatureKeyPriority := AEntry.Priority;
      end;
    TAtlasKeyFunction.QuickToggle:
      begin
        ASettings.QuickToggleKey := AEntry.Key;
        ASettings.QuickToggleKeyPriority := AEntry.Priority;
      end;
    TAtlasKeyFunction.DiagnosticMode:
      begin
        ASettings.DiagnosticModeKey := AEntry.Key;
        ASettings.DiagnosticModeKeyPriority := AEntry.Priority;
      end;
    // Editorbefehle (#399, #721): eine gemeinsame Wahl für alle.
    TAtlasKeyFunction.CodeActions:
      begin
        ASettings.ActionsKey := AEntry.Key;
        ASettings.EditorKeysPriority := AEntry.Priority;
      end;
    TAtlasKeyFunction.ExpandSelection:
      ASettings.ExpandKey := AEntry.Key;
    TAtlasKeyFunction.ShrinkSelection:
      ASettings.ShrinkKey := AEntry.Key;
    TAtlasKeyFunction.GoToImplementation:
      ASettings.ImplementationKey := AEntry.Key;
    TAtlasKeyFunction.TypeDefinition:
      ASettings.TypeDefinitionKey := AEntry.Key;
    TAtlasKeyFunction.UndoChange:
      ASettings.UndoKey := AEntry.Key;
    TAtlasKeyFunction.RedoChange:
      ASettings.RedoKey := AEntry.Key;
  else
    // Gehört zu einem anderen Teil.
  end;
end;

/// <summary>Teil 2 von ToSettings: Taste (und Vorrang) von AEntry in ASettings, wenn die Funktion hierher
/// gehört.</summary>
procedure StoreKeys2(const AEntry: TAtlasKeyEntry; var ASettings: TAtlasPluginSettings);
begin
  case AEntry.Func of
    TAtlasKeyFunction.WelcomeSearch:
      ASettings.WelcomePageSearchKey := AEntry.Key;
    TAtlasKeyFunction.MethodToggleUp:
      ASettings.MethodToggleUpKey := AEntry.Key;
    TAtlasKeyFunction.MethodToggleDown:
      ASettings.MethodToggleDownKey := AEntry.Key;
    TAtlasKeyFunction.TestUnit:
      ASettings.TestUnitKey := AEntry.Key;
    TAtlasKeyFunction.UnitSearch:
      ASettings.UnitSearchKey := AEntry.Key;
    TAtlasKeyFunction.Bookmark:
      ASettings.BookmarkKey := AEntry.Key;
    TAtlasKeyFunction.GenerateMenu:
      ASettings.GenerateMenuKey := AEntry.Key;
    TAtlasKeyFunction.Notifications:
      ASettings.NotificationsKey := AEntry.Key;
    TAtlasKeyFunction.WelcomeQuickBuild:
      ASettings.WelcomePageQuickActionsBuildKey := AEntry.Key;
    TAtlasKeyFunction.WelcomeQuickTests:
      ASettings.WelcomePageQuickActionsTestKey := AEntry.Key;
    TAtlasKeyFunction.HideElement:
      ASettings.HideElementKey := AEntry.Key;
    TAtlasKeyFunction.NextProblem:
      ASettings.NextProblemKey := AEntry.Key;
    TAtlasKeyFunction.PreviousProblem:
      ASettings.PreviousProblemKey := AEntry.Key;
  else
    // Gehört zu einem anderen Teil.
  end;
end;

/// <summary>Teil 3 von ToSettings: Taste (und Vorrang) von AEntry in ASettings, wenn die Funktion hierher
/// gehört.</summary>
procedure StoreKeys3(const AEntry: TAtlasKeyEntry; var ASettings: TAtlasPluginSettings);
begin
  case AEntry.Func of
    TAtlasKeyFunction.QuickOpen:
      ASettings.QuickOpenKey := AEntry.Key;
    TAtlasKeyFunction.NavBack:
      ASettings.NavBackKey := AEntry.Key;
    TAtlasKeyFunction.NavForward:
      ASettings.NavForwardKey := AEntry.Key;
    TAtlasKeyFunction.LastEdit:
      ASettings.LastEditKey := AEntry.Key;
    TAtlasKeyFunction.PeekDefinition:
      ASettings.PeekDefinitionKey := AEntry.Key;
    TAtlasKeyFunction.PeekReferences:
      ASettings.PeekReferencesKey := AEntry.Key;
    TAtlasKeyFunction.Breadcrumbs:
      ASettings.BreadcrumbsKey := AEntry.Key;
    TAtlasKeyFunction.JumpToMatch:
      ASettings.JumpToMatchKey := AEntry.Key;
    TAtlasKeyFunction.JumpToMatchSelect:
      ASettings.JumpToMatchSelectKey := AEntry.Key;
    TAtlasKeyFunction.NextChange:
      ASettings.NextChangeKey := AEntry.Key;
    TAtlasKeyFunction.PreviousChange:
      ASettings.PreviousChangeKey := AEntry.Key;
    TAtlasKeyFunction.MoveLinesUp:
      ASettings.MoveLinesUpKey := AEntry.Key;
    TAtlasKeyFunction.MoveLinesDown:
      ASettings.MoveLinesDownKey := AEntry.Key;
  else
    // Gehört zu einem anderen Teil.
  end;
end;

/// <summary>Teil 4 von ToSettings: Taste (und Vorrang) von AEntry in ASettings, wenn die Funktion hierher
/// gehört.</summary>
procedure StoreKeys4(const AEntry: TAtlasKeyEntry; var ASettings: TAtlasPluginSettings);
begin
  case AEntry.Func of
    TAtlasKeyFunction.DuplicateLinesUp:
      ASettings.DuplicateLinesUpKey := AEntry.Key;
    TAtlasKeyFunction.DuplicateLinesDown:
      ASettings.DuplicateLinesDownKey := AEntry.Key;
    TAtlasKeyFunction.CompleteStatement:
      ASettings.CompleteStatementKey := AEntry.Key;
    TAtlasKeyFunction.MultiCursorNext:
      ASettings.MultiCursorNextKey := AEntry.Key;
    TAtlasKeyFunction.MultiCursorSkip:
      ASettings.MultiCursorSkipKey := AEntry.Key;
    TAtlasKeyFunction.MultiCursorLineEnds:
      ASettings.MultiCursorLineEndsKey := AEntry.Key;
    TAtlasKeyFunction.MultiCursorAbove:
      ASettings.MultiCursorAboveKey := AEntry.Key;
    TAtlasKeyFunction.MultiCursorBelow:
      ASettings.MultiCursorBelowKey := AEntry.Key;
    TAtlasKeyFunction.Search:
      ASettings.SearchKey := AEntry.Key;
    TAtlasKeyFunction.SearchNext:
      ASettings.SearchNextKey := AEntry.Key;
    TAtlasKeyFunction.SearchPrevious:
      ASettings.SearchPreviousKey := AEntry.Key;
    TAtlasKeyFunction.SearchMethod:
      ASettings.SearchMethodKey := AEntry.Key;
    TAtlasKeyFunction.SearchReplace:
      ASettings.SearchReplaceKey := AEntry.Key;
  else
    // Gehört zu einem anderen Teil.
  end;
end;

/// <summary>Teil 5 von ToSettings: Taste (und Vorrang) von AEntry in ASettings, wenn die Funktion hierher
/// gehört.</summary>
procedure StoreKeys5(const AEntry: TAtlasKeyEntry; var ASettings: TAtlasPluginSettings);
begin
  case AEntry.Func of
    TAtlasKeyFunction.FormatCode:
      ASettings.FormatCodeKey := AEntry.Key;
    TAtlasKeyFunction.ToggleBlockComment:
      ASettings.ToggleBlockCommentKey := AEntry.Key;
    TAtlasKeyFunction.NewLineBelow:
      ASettings.NewLineBelowKey := AEntry.Key;
    TAtlasKeyFunction.NewLineAbove:
      ASettings.NewLineAboveKey := AEntry.Key;
    TAtlasKeyFunction.Unwrap:
      ASettings.UnwrapKey := AEntry.Key;
    TAtlasKeyFunction.ProblemsWindow:
      ASettings.ProblemsWindowKey := AEntry.Key;
    TAtlasKeyFunction.SectionInterface:
      ASettings.GotoInterfaceKey := AEntry.Key;
    TAtlasKeyFunction.SectionImplementation:
      ASettings.GotoImplementationKey := AEntry.Key;
    TAtlasKeyFunction.QuickBookmark:
      begin
        ASettings.QuickBookmarkKey := AEntry.Key;
        ASettings.QuickBookmarkKeyPriority := AEntry.Priority;
      end;
    TAtlasKeyFunction.QuickBookmarkSet:
      begin
        ASettings.QuickBookmarkSetKey := AEntry.Key;
        ASettings.QuickBookmarkSetKeyPriority := AEntry.Priority;
      end;
    TAtlasKeyFunction.QuickBookmarkJump:
      begin
        ASettings.QuickBookmarkJumpKey := AEntry.Key;
        ASettings.QuickBookmarkJumpKeyPriority := AEntry.Priority;
      end;
    TAtlasKeyFunction.NextBookmark:
      ASettings.NextBookmarkKey := AEntry.Key;
    TAtlasKeyFunction.PreviousBookmark:
      ASettings.PreviousBookmarkKey := AEntry.Key;
  else
    // Gehört zu einem anderen Teil.
  end;
end;

/// <summary>Teil 6 von ToSettings: Taste (und Vorrang) von AEntry in ASettings, wenn die Funktion hierher
/// gehört.</summary>
procedure StoreKeys6(const AEntry: TAtlasKeyEntry; var ASettings: TAtlasPluginSettings);
begin
  case AEntry.Func of
    TAtlasKeyFunction.StepIntoTarget:
      ASettings.DebugStepIntoTargetKey := AEntry.Key;
    TAtlasKeyFunction.ExpressionType:
      ASettings.ExpressionTypeKey := AEntry.Key;
    TAtlasKeyFunction.SafeDelete:
      ASettings.SafeDeleteKey := AEntry.Key;
    TAtlasKeyFunction.CreateIssue:
      ASettings.CreateIssueKey := AEntry.Key;
    TAtlasKeyFunction.DesignerSearch:
      ASettings.DesignerSearchKey := AEntry.Key;
    TAtlasKeyFunction.CheckFile:
      ASettings.CheckFileKey := AEntry.Key;
    TAtlasKeyFunction.SectionAppend:
      ASettings.SectionAppendKey := AEntry.Key;
    TAtlasKeyFunction.DesignerSelectionSetsSave:
      ASettings.DesignerSelectionSetsSaveKey := AEntry.Key;
    TAtlasKeyFunction.DesignerShowComponent:
      ASettings.DesignerShowInDesignerKey := AEntry.Key;
    TAtlasKeyFunction.DesignerInlineCaption:
      ASettings.DesignerInlineCaptionKey := AEntry.Key;
    TAtlasKeyFunction.DesignerSelectionBar:
      ASettings.DesignerSelectionBarKey := AEntry.Key;
    TAtlasKeyFunction.DesignerMagnifier:
      ASettings.DesignerMagnifierKey := AEntry.Key;
    TAtlasKeyFunction.DesignerUsages:
      ASettings.DesignerUsagesKey := AEntry.Key;
  else
    // Gehört zu einem anderen Teil.
  end;
end;

class procedure TAtlasKeyEntry.ToSettings(const AEntries: TArray<TAtlasKeyEntry>;
  var ASettings: TAtlasPluginSettings);
var
  mEntry: TAtlasKeyEntry;
begin
  // Strg+F12 (UnitSearchIde) ist fest; ein- und ausgeschaltet wird über unitSearch.replaceIdeDialog.
  for mEntry in AEntries do
  begin
    StoreKeys1(mEntry, ASettings);
    StoreKeys2(mEntry, ASettings);
    StoreKeys3(mEntry, ASettings);
    StoreKeys4(mEntry, ASettings);
    StoreKeys5(mEntry, ASettings);
    StoreKeys6(mEntry, ASettings);
  end;
end;

function TAtlasKeyEntry.IdeKey: Word;
begin
  case Func of
    TAtlasKeyFunction.Completion:
      Result := TAtlasKeyConflicts.cIdeCompletionKey;
    TAtlasKeyFunction.Signature:
      Result := TAtlasKeyConflicts.cIdeSignatureKey;
  else
    Result := 0;
  end;
end;

function TAtlasKeyEntry.Choice: TAtlasKeyChoice;
begin
  if Priority then
  begin
    Result := TAtlasKeyChoice.UseAtlas;
  end
  else
  begin
    Result := TAtlasKeyChoice.LeaveOther;
  end;
end;

procedure TAtlasKeyEntry.Choose(AChoice: TAtlasKeyChoice);
begin
  Priority := AChoice = TAtlasKeyChoice.UseAtlas;
  if Priority and (Key = 0) then
  begin
    Key := IdeKey;
  end;
end;

function TAtlasKeyEntry.Status(const AOwner: string): TAtlasKeyStatus;
begin
  if Disabled then
  begin
    Result := TAtlasKeyStatus.NoKey;
  end
  else if Key = 0 then
  begin
    if IdeKey <> 0 then
    begin
      Result := TAtlasKeyStatus.IdeKey;
    end
    else
    begin
      Result := TAtlasKeyStatus.NoKey;
    end;
  end
  else if AOwner = '' then
  begin
    Result := TAtlasKeyStatus.Free;
  end
  else if Priority then
  begin
    Result := TAtlasKeyStatus.AtlasWins;
  end
  else
  begin
    Result := TAtlasKeyStatus.Left;
  end;
end;

{ TAtlasKeyOwner }

class function TAtlasKeyOwner.Create(AShortCut: Word; const AOwner: string): TAtlasKeyOwner;
begin
  Result.ShortCut := AShortCut;
  Result.Owner := AOwner;
end;

{ TAtlasKeyConflicts }

class function TAtlasKeyConflicts.KnownIdeKeys: TArray<TAtlasKeyOwner>;
var
  mDigit: Integer;
begin
  Result := [TAtlasKeyOwner.Create(cScCtrl or cScShift or Ord('P'), UiText(TKeyConflictsText.IDEPlayKeyboardMacro)),
    TAtlasKeyOwner.Create(cScCtrl or cScShift or Ord('R'), UiText(TKeyConflictsText.IDERecordKeyboardMacro)),
    // Zeilen verschieben und duplizieren (#634) nimmt diese Tasten mit Vorrang.
    TAtlasKeyOwner.Create(cScAlt or $26, UiText(TKeyConflictsText.IDECodeBrowsingFindDeclaration)), // VK_UP
    TAtlasKeyOwner.Create(cScShift or cScAlt or $26, UiText(TKeyConflictsText.IDESelectColumnBlockUp)),
    TAtlasKeyOwner.Create(cScShift or cScAlt or $28, UiText(TKeyConflictsText.IDESelectColumnBlockDown)), // VK_DOWN
    // Anweisung vervollständigen (#697) nimmt Strg+Umschalt+Enter mit Vorrang.
    TAtlasKeyOwner.Create(cScCtrl or cScShift or $0D, UiText(TKeyConflictsText.IDEFindReferences)), // VK_RETURN
    // Typ des markierten Ausdrucks (#689) nimmt Strg+Umschalt+T mit Vorrang.
    TAtlasKeyOwner.Create(cScCtrl or cScShift or Ord('T'), UiText(TKeyConflictsText.IDEAddToDoItem)),
    // Schnelle Lesezeichen (#1104): erster Teil der Faltungsakkorde.
    TAtlasKeyOwner.Create(cScCtrl or cScShift or Ord('K'), UiText(TKeyConflictsText.IDEFoldingCtrlShiftK))];
  // Lesezeichen 0–9 der IDE; 0 bleibt immer bei ihr.
  for mDigit := 0 to 9 do
  begin
    Result := Result + [TAtlasKeyOwner.Create(cScCtrl or cScShift or (Ord('0') + mDigit),
      Format(UiText(TKeyConflictsText.IDEToggleBookmark), [mDigit])),
        TAtlasKeyOwner.Create(cScCtrl or (Ord('0') + mDigit),
      Format(UiText(TKeyConflictsText.IDEGoToBookmark), [mDigit]))];
  end;
end;

class function TAtlasKeyConflicts.OwnerOf(AShortCut: Word; const AKeys: TArray<TAtlasKeyOwner>): string;
var
  mKey: TAtlasKeyOwner;
begin
  Result := '';
  if AShortCut = 0 then
  begin
    Exit;
  end;
  for mKey in AKeys do
  begin
    if mKey.ShortCut = AShortCut then
    begin
      Exit(mKey.Owner);
    end;
  end;
end;

class function TAtlasKeyConflicts.ShouldBind(AShortCut: Word; const AOwner: string; APriority: Boolean): Boolean;
begin
  Result := (AShortCut <> 0) and ((AOwner = '') or APriority);
end;

class function TAtlasKeyConflicts.CompletionExtensions(const AModules: TArray<string>): TArray<string>;
type
  TKnown = record
    Prefix: string;
    mName: string;
  end;
const
  // Package-Namen (ohne Version) und Anzeigename; nur Erweiterungen mit eigener Vervollständigung.
  cKnown: array[0..2] of TKnown = (
    (Prefix: 'CnWizards'; mName: 'CnPack (Input Helper)'),
    (Prefix: 'Castalia'; mName: 'Castalia'),
    (Prefix: 'CodeInsightPlus'; mName: 'Code Insight Plus'));
var
  mModule, mName: string;
  mIndex: Integer;
  mFound: Boolean;
begin
  Result := nil;
  for mIndex := Low(cKnown) to High(cKnown) do
  begin
    mFound := False;
    for mModule in AModules do
    begin
      mName := ExtractFileName(mModule);
      if mName.StartsWith(cKnown[mIndex].Prefix, True) then
      begin
        mFound := True;
      end;
    end;
    if mFound then
    begin
      Result := Result + [cKnown[mIndex].mName];
    end;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Commands.KeyConflicts', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
