unit Atlas.Core.Commands.KeyMap;

// Tastenkürzel-Übersicht mit Konflikterkennung (#520), Teil ohne VCL und Open
// Tools API. Die IDE-Schicht sammelt alle Belegungen als TAtlasKeyItem:
// Aktionen der IDE und anderer Erweiterungen (INTAServices.ActionList),
// Tastaturbelegungen des Editors (IOTAKeyboardServices, soweit auslesbar) und
// die Tasten von Atlas (TAtlasKeyEntry.AllFromSettings, #399, #494, #502).
// Hier entsteht daraus die Übersicht:
// - Konflikt: dieselbe Taste, sich überschneidender Kontext (global
//   überschneidet sich mit allem) und verschiedene Besitzer (Herkunft, bei
//   Atlas die Funktion, bei Erweiterungen der Package-Name). Doppelte
//   Belegungen innerhalb der IDE sind ihre eigene Sache und kein Konflikt.
// - Wer gewinnt, entscheidet der Kontext, in dem sich die Belegungen treffen:
//   auf der Willkommensseite das Suchfeld von Atlas; im Editor eine
//   Tastaturbelegung vor einem Menübefehl, unter mehreren die wirksame
//   (zuletzt angemeldete); Atlas mit Vorrang vor der fremden Belegung; ohne
//   Vorrang überlässt Atlas die Taste (#494); unter Aktionen die erste der
//   Aktionsliste.
// - Suche nach Taste („Strg+Umschalt+P“, auch englisch „Ctrl+Shift+P“, nur
//   Umschalttasten „Strg+Alt“) oder nach Text in Taste, Befehl, Kategorie und
//   Herkunft.
// - Export als druckbare HTML-Seite (Zeilen mit Konflikt rot).
// - AtlasConflicts liefert die Atlas-Tasten mit offenem Konflikt für die
//   Meldung beim Start und die Einrichtung (#625).
// - „Units suchen“ übernimmt Strg+F12 (#777): Die Taste bleibt bei der Aktion
//   der IDE; die Übersicht zeigt die Aktion als Atlas-Zeile (Quelle Action,
//   Kontext global), solange die Übernahme an ist.

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.KeyConflicts;

type
  {$SCOPEDENUMS ON}
  /// <summary>Wem die Belegung gehört.</summary>
  TAtlasKeyOrigin = (Ide, Atlas, Plugin);
  /// <summary>Wo die Taste wirkt; Global überschneidet sich mit jedem anderen Kontext.</summary>
  TAtlasKeyContext = (Global, Editor, Designer, WelcomePage);
  /// <summary>Action: Aktion mit Tastenkürzel (Menü, wirkt im ganzen Hauptfenster); Binding: Tastaturbelegung des
  /// Editors (IOTAKeyboardBinding); Window: Kürzel eines eigenen Fensters (Suchfeld der Willkommensseite).</summary>
  TAtlasKeySource = (Action, Binding, Window);
  /// <summary>Warum der Gewinner eines Konflikts gewinnt.</summary>
  TAtlasKeyReason = (None, AtlasPriority, AtlasYields, EditorBinding, LastBinding, FirstAction, OwnWindow,
    NoneActive);
  {$SCOPEDENUMS OFF}

  /// <summary>Aktion der IDE, die ein Modul übernommen hat, etwa Strg+F12 „Units“ für „Units suchen“ (#777).
  /// </summary>
  TAtlasTakenAction = record
    /// <summary>Atlas-Funktion, die an Stelle der Aktion läuft.</summary>
    Func: TAtlasKeyFunction;
    /// <summary>Name der Aktion in der Aktionsliste der IDE.</summary>
    ActionName: string;
  end;

  /// <summary>Übernommene Aktionen eines Moduls für die Tastenkürzel-Übersicht (#520, #1455); Hauptthread.
  /// </summary>
  IAtlasTakenActions = interface
    ['{CA511338-4188-48A9-B7C7-E5B6CC0FFD28}']
    function TakenActions: TArray<TAtlasTakenAction>;
  end;

  /// <summary>Wem eine Belegung gehört und woher sie stammt (für TAtlasKeyItem.Create).</summary>
  TAtlasKeyProvenance = record
    Origin: TAtlasKeyOrigin;
    /// <summary>„IDE“, „Atlas“ oder der Package-Name der Erweiterung (ohne Pfad).</summary>
    OriginName: string;
    Context: TAtlasKeyContext;
    Source: TAtlasKeySource;
    /// <summary>Eindeutig je Quelle: Name der Aktion, Atlas-Funktion, Taste der Tastaturbelegung.</summary>
    Id: string;
    /// <summary>Reihenfolge in der Quelle (Aktionsliste, Anmeldung).</summary>
    Order: Integer;
    class function Create(AOrigin: TAtlasKeyOrigin; const AOriginName: string; AContext: TAtlasKeyContext;
      ASource: TAtlasKeySource; const AId: string; AOrder: Integer): TAtlasKeyProvenance; static;
  end;

  /// <summary>Eine Belegung einer Taste.</summary>
  TAtlasKeyItem = record
    ShortCut: Word;
    /// <summary>Taste als Text, wie die IDE sie zeigt (ShortCutToText).</summary>
    KeyText: string;
    Command: string;
    /// <summary>Kategorie bzw. Menüpfad; '' ohne.</summary>
    Category: string;
    Origin: TAtlasKeyOrigin;
    /// <summary>„IDE“, „Atlas“ oder der Package-Name der Erweiterung (ohne Pfad).</summary>
    OriginName: string;
    Context: TAtlasKeyContext;
    Source: TAtlasKeySource;
    /// <summary>Eindeutig je Quelle: Name der Aktion, Atlas-Funktion, Taste der Tastaturbelegung.</summary>
    Id: string;
    /// <summary>Reihenfolge in der Quelle (Aktionsliste, Anmeldung).</summary>
    Order: Integer;
    /// <summary>Hält die Taste: Atlas nur, wenn frei oder mit Vorrang belegt (#494); sonst immer True.</summary>
    Active: Boolean;
    /// <summary>Atlas: Vorrang gewählt („Atlas verwenden“).</summary>
    Priority: Boolean;
    /// <summary>Wirksame Tastaturbelegung des Editors für diese Taste (Abfrage der IDE).</summary>
    Effective: Boolean;
    /// <summary>Nur bei Herkunft Atlas: die Funktion.</summary>
    Func: TAtlasKeyFunction;
    /// <summary>Ergebnis von Analyze: mindestens eine andere Belegung kollidiert.</summary>
    Conflict: Boolean;
    /// <summary>Ergebnis von Analyze: Index der Belegung, die im gemeinsamen Kontext gewinnt; -1 = keine.</summary>
    Winner: Integer;
    Wins: Boolean;
    Reason: TAtlasKeyReason;
    /// <summary>Aufrufe des Befehls per Maus bzw. über das Kürzel (#600, Spalte „Selten per Tastatur“); 0 ohne
    /// Zählung.</summary>
    MouseUses: Integer;
    KeyUses: Integer;
    class function Create(AShortCut: Word; const AKeyText, ACommand: string;
      const AOwner: TAtlasKeyProvenance): TAtlasKeyItem; static;
    /// <summary>„Befehl (Herkunft)“ für Meldungen.</summary>
    function Holder: string;
    /// <summary>Selten per Tastatur genutzt (TAtlasCommandUsage.IsRarelyByKeyboard).</summary>
    function RarelyByKeyboard: Boolean;
  end;

  /// <summary>Suche in der Übersicht.</summary>
  TAtlasKeyQuery = record
    /// <summary>Kleingeschrieben und ohne Leerraum am Rand.</summary>
    Text: string;
    /// <summary>Erkannte Taste; 0 = keine.</summary>
    ShortCut: Word;
    /// <summary>Nur Umschalttasten erkannt („Strg+Umschalt“); 0 = keine.</summary>
    Modifiers: Word;
    class function Parse(const AText: string): TAtlasKeyQuery; static;
    function IsEmpty: Boolean;
    function Matches(const AItem: TAtlasKeyItem): Boolean;
  end;

  /// <summary>Zeile der HTML-Übersicht: Zellen als Klartext.</summary>
  TAtlasKeyHtmlRow = record
    Cells: TArray<string>;
    Conflict: Boolean;
    class function Create(const ACells: TArray<string>; AConflict: Boolean): TAtlasKeyHtmlRow; static;
  end;

  TAtlasKeyMap = class
  public const
    IdeName = 'IDE';
    AtlasName = 'Atlas';
    scShift = TAtlasKeyConflicts.scShift;
    scCtrl = TAtlasKeyConflicts.scCtrl;
    scAlt = TAtlasKeyConflicts.scAlt;
    ModifierMask = scShift or scCtrl or scAlt;
  public
    /// <summary>Kontext einer Atlas-Taste: das Suchfeld auf der Willkommensseite, Strg+F12 für „Units suchen“
    /// global (Aktion der IDE), alle übrigen im Editor (Tastaturbelegungen wirken nur dort).</summary>
    class function ContextOf(AFunc: TAtlasKeyFunction): TAtlasKeyContext; static;
    /// <summary>Window für das Suchfeld, Action für Strg+F12 (#777), sonst Binding.</summary>
    class function SourceOf(AFunc: TAtlasKeyFunction): TAtlasKeySource; static;
    /// <summary>Befehl der Befehlspalette (#502) zu einer Atlas-Taste; '' ohne. Mehrere Tasten können denselben
    /// Befehl haben (beide Tasten von Deklaration ⇄ Implementierung, eigene Taste und Strg+F12 für „Units
    /// suchen“).</summary>
    class function CommandIdOf(AFunc: TAtlasKeyFunction): string; static;
    /// <summary>Kontext einer Aktion nach ihrer Kategorie: „Designer“/„Formular“ = Designer, „Editor“ = Editor,
    /// sonst global (Menübefehle wirken im ganzen Hauptfenster).</summary>
    class function ContextOfCategory(const ACategory: string): TAtlasKeyContext; static;
    /// <summary>Herkunft nach dem Modul, das die Belegung umsetzt: Atlas-Package, Ordner der IDE (bds.exe) oder
    /// eine andere Erweiterung; AName ist dann der Package-Name ohne Pfad und Endung.</summary>
    class function OriginOfModule(const AModule, AIdeFolder, AAtlasModule: string;
      out AName: string): TAtlasKeyOrigin; static;
    class function Overlaps(A, B: TAtlasKeyContext): Boolean; static;
    /// <summary>A und B belegen dieselbe Taste in sich überschneidendem Kontext und gehören verschiedenen
    /// Besitzern.</summary>
    class function Collide(const A, B: TAtlasKeyItem): Boolean; static;
    /// <summary>Konflikte, Gewinner und Grund für jede Belegung setzen.</summary>
    class procedure Analyze(var AItems: TArray<TAtlasKeyItem>); static;
    /// <summary>Belegungen mit Konflikt.</summary>
    class function ConflictCount(const AItems: TArray<TAtlasKeyItem>): Integer; static;
    /// <summary>Andere Belegung im Konflikt mit AItems[AIndex]: der Gewinner, wenn es nicht sie selbst ist,
    /// sonst die erste kollidierende; -1 ohne Konflikt.</summary>
    class function PartnerOf(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer): Integer; static;
    /// <summary>Atlas-Tasten mit offenem Konflikt: kollidiert und nicht mit Vorrang gewonnen (#520, #625).</summary>
    class function AtlasConflicts(const AItems: TArray<TAtlasKeyItem>): TArray<Integer>; static;
    /// <summary>Indizes der Belegungen zur Suche, sortiert nach Taste und Befehl.</summary>
    class function Filter(const AItems: TArray<TAtlasKeyItem>; const AQuery: string;
      AOnlyConflicts: Boolean): TArray<Integer>; static;
    /// <summary>Taste aus Text: Umschalttasten deutsch oder englisch, dann eine Taste; 0, wenn nicht erkannt.
    /// AModifiers bekommt die Umschalttasten auch ohne Taste.</summary>
    class function ParseShortCut(const AText: string; out AModifiers: Word): Word; static;
    /// <summary>Druckbare HTML-Seite: Titel, Unterzeile, Knopf „Drucken“, Tabelle; Zeilen mit Konflikt rot.</summary>
    class function Html(const ALanguage, ATitle, ASubtitle, APrint: string; const AHeaders: TArray<string>;
      const ARows: TArray<TAtlasKeyHtmlRow>): string; static;
    class function HtmlEscape(const AText: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Commands.Usage;

{ TAtlasKeyProvenance }

class function TAtlasKeyProvenance.Create(AOrigin: TAtlasKeyOrigin; const AOriginName: string;
  AContext: TAtlasKeyContext; ASource: TAtlasKeySource; const AId: string; AOrder: Integer): TAtlasKeyProvenance;
begin
  Result.Origin := AOrigin;
  Result.OriginName := AOriginName;
  Result.Context := AContext;
  Result.Source := ASource;
  Result.Id := AId;
  Result.Order := AOrder;
end;

{ TAtlasKeyItem }

class function TAtlasKeyItem.Create(AShortCut: Word; const AKeyText, ACommand: string;
  const AOwner: TAtlasKeyProvenance): TAtlasKeyItem;
begin
  Result := Default(TAtlasKeyItem);
  Result.ShortCut := AShortCut;
  Result.KeyText := AKeyText;
  Result.Command := ACommand;
  Result.Origin := AOwner.Origin;
  Result.OriginName := AOwner.OriginName;
  Result.Context := AOwner.Context;
  Result.Source := AOwner.Source;
  Result.Id := AOwner.Id;
  Result.Order := AOwner.Order;
  Result.Active := True;
  Result.Winner := -1;
end;

function TAtlasKeyItem.RarelyByKeyboard: Boolean;
begin
  Result := TAtlasCommandUsage.IsRarelyByKeyboard(MouseUses, KeyUses);
end;

function TAtlasKeyItem.Holder: string;
begin
  if OriginName = '' then
  begin
    Result := Command;
  end
  else
  begin
    Result := Command + ' (' + OriginName + ')';
  end;
end;

{ TAtlasKeyQuery }

class function TAtlasKeyQuery.Parse(const AText: string): TAtlasKeyQuery;
begin
  Result := Default(TAtlasKeyQuery);
  Result.Text := LowerCase(Trim(AText));
  Result.ShortCut := TAtlasKeyMap.ParseShortCut(AText, Result.Modifiers);
end;

function TAtlasKeyQuery.IsEmpty: Boolean;
begin
  Result := Text = '';
end;

function TAtlasKeyQuery.Matches(const AItem: TAtlasKeyItem): Boolean;
begin
  if Text = '' then
  begin
    Exit(True);
  end;
  if ShortCut <> 0 then
  begin
    Exit(AItem.ShortCut = ShortCut);
  end;
  if Modifiers <> 0 then
  begin
    Exit((AItem.ShortCut <> 0) and ((AItem.ShortCut and Modifiers) = Modifiers));
  end;
  Result := (Pos(Text, LowerCase(AItem.KeyText)) > 0) or (Pos(Text, LowerCase(AItem.Command)) > 0) or
    (Pos(Text, LowerCase(AItem.Category)) > 0) or (Pos(Text, LowerCase(AItem.OriginName)) > 0);
end;

{ TAtlasKeyHtmlRow }

class function TAtlasKeyHtmlRow.Create(const ACells: TArray<string>; AConflict: Boolean): TAtlasKeyHtmlRow;
begin
  Result.Cells := ACells;
  Result.Conflict := AConflict;
end;

{ TAtlasKeyMap }

class function TAtlasKeyMap.ContextOf(AFunc: TAtlasKeyFunction): TAtlasKeyContext;
begin
  case AFunc of
    TAtlasKeyFunction.WelcomeSearch, TAtlasKeyFunction.WelcomeQuickBuild, TAtlasKeyFunction.WelcomeQuickTests:
      Result := TAtlasKeyContext.WelcomePage;
    TAtlasKeyFunction.UnitSearchIde:
      Result := TAtlasKeyContext.Global;
  else
    Result := TAtlasKeyContext.Editor;
  end;
end;

class function TAtlasKeyMap.SourceOf(AFunc: TAtlasKeyFunction): TAtlasKeySource;
begin
  case AFunc of
    TAtlasKeyFunction.WelcomeSearch, TAtlasKeyFunction.WelcomeQuickBuild, TAtlasKeyFunction.WelcomeQuickTests:
      Result := TAtlasKeySource.Window;
    TAtlasKeyFunction.UnitSearchIde:
      Result := TAtlasKeySource.Action;
    // Überspringen (#589): nur nach Strg+K, solange mehrere Einfügemarken aktiv sind; keine Bindung der IDE.
    TAtlasKeyFunction.MultiCursorSkip:
      Result := TAtlasKeySource.Window;
  else
    Result := TAtlasKeySource.Binding;
  end;
end;

const
  /// <summary>Befehl der Befehlspalette je Atlas-Taste (CommandIdOf); '' ohne.</summary>
  CommandIds: array[TAtlasKeyFunction] of string = (
    '', // Palette
    'Atlas.CheckNow', // Check
    '', // Completion
    '', // Signature
    'Atlas.QuickToggles', // QuickToggle
    '', // DiagnosticMode
    'Atlas.CodeActions', // CodeActions
    'Atlas.ExpandSelection', // ExpandSelection
    'Atlas.ShrinkSelection', // ShrinkSelection
    'Atlas.Implementations', // GoToImplementation
    'Atlas.TypeDefinition', // TypeDefinition
    'Atlas.UndoChange', // UndoChange
    'Atlas.RedoChange', // RedoChange
    '', // WelcomeSearch
    'Atlas.ToggleMethod', // MethodToggleUp
    'Atlas.ToggleMethod', // MethodToggleDown
    'Atlas.SwitchTestUnit', // TestUnit
    'Atlas.UnitSearch', // UnitSearch
    'Atlas.UnitSearch', // UnitSearchIde
    'Atlas.BookmarkAdd', // Bookmark
    'Atlas.GenerateMenu', // GenerateMenu
    'Atlas.Notifications', // Notifications
    '', // WelcomeQuickBuild
    '', // WelcomeQuickTests
    'Atlas.HideElement', // HideElement
    'Atlas.NextProblem', // NextProblem
    'Atlas.PreviousProblem', // PreviousProblem
    'Atlas.QuickOpen', // QuickOpen
    'Atlas.NavBack', // NavBack
    'Atlas.NavForward', // NavForward
    'Atlas.LastEdit', // LastEdit
    'Atlas.PeekDefinition', // PeekDefinition
    'Atlas.PeekReferences', // PeekReferences
    'Atlas.Breadcrumbs', // Breadcrumbs
    'Atlas.JumpToMatch', // JumpToMatch
    'Atlas.JumpToMatchSelect', // JumpToMatchSelect
    'Atlas.NextChange', // NextChange
    'Atlas.PreviousChange', // PreviousChange
    'Atlas.MoveLinesUp', // MoveLinesUp
    'Atlas.MoveLinesDown', // MoveLinesDown
    'Atlas.DuplicateLinesUp', // DuplicateLinesUp
    'Atlas.DuplicateLinesDown', // DuplicateLinesDown
    'Atlas.CompleteStatement', // CompleteStatement
    'Atlas.MultiCursorNext', // MultiCursorNext
    '', // MultiCursorSkip
    'Atlas.MultiCursorLineEnds', // MultiCursorLineEnds
    'Atlas.MultiCursorAbove', // MultiCursorAbove
    'Atlas.MultiCursorBelow', // MultiCursorBelow
    'Atlas.Search', // Search
    'Atlas.SearchNext', // SearchNext
    'Atlas.SearchPrevious', // SearchPrevious
    'Atlas.SearchInMethod', // SearchMethod
    'Atlas.FormatCode', // FormatCode
    'Atlas.ToggleBlockComment', // ToggleBlockComment
    'Atlas.NewLineBelow', // NewLineBelow
    'Atlas.NewLineAbove', // NewLineAbove
    'Atlas.Unwrap', // Unwrap
    'Atlas.ProblemsWindow', // ProblemsWindow
    'Atlas.GotoInterface', // SectionInterface
    'Atlas.GotoImplementation', // SectionImplementation
    'Atlas.QuickBookmarkToggle', // QuickBookmark
    '', // QuickBookmarkSet
    '', // QuickBookmarkJump
    'Atlas.NextBookmark', // NextBookmark
    'Atlas.PreviousBookmark', // PreviousBookmark
    'Atlas.SearchReplace', // SearchReplace
    'Atlas.StepIntoTarget', // StepIntoTarget
    'Atlas.ExpressionType', // ExpressionType
    'Atlas.SafeDelete', // SafeDelete
    'Atlas.CreateIssue', // CreateIssue
    '', // DesignerSearch
    'Atlas.CheckFile' // CheckFile
  );

class function TAtlasKeyMap.CommandIdOf(AFunc: TAtlasKeyFunction): string;
begin
  Result := CommandIds[AFunc];
end;

class function TAtlasKeyMap.ContextOfCategory(const ACategory: string): TAtlasKeyContext;
var
  Lower: string;
begin
  Lower := LowerCase(ACategory);
  if (Pos('designer', Lower) > 0) or (Pos('formular', Lower) > 0) then
  begin
    Result := TAtlasKeyContext.Designer;
  end
  else if Pos('editor', Lower) > 0 then
  begin
    Result := TAtlasKeyContext.Editor;
  end
  else
  begin
    Result := TAtlasKeyContext.Global;
  end;
end;

class function TAtlasKeyMap.OriginOfModule(const AModule, AIdeFolder, AAtlasModule: string;
  out AName: string): TAtlasKeyOrigin;
var
  Folder, Name: string;
begin
  // Kein Pfad nach außen: nur der Package-Name einer Erweiterung.
  Name := ExtractFileName(AModule.Replace('/', '\'));
  if (AAtlasModule <> '') and SameText(AModule, AAtlasModule) then
  begin
    AName := AtlasName;
    Exit(TAtlasKeyOrigin.Atlas);
  end;
  Folder := IncludeTrailingPathDelimiter(AIdeFolder.Replace('/', '\'));
  if (AModule = '') or ((AIdeFolder <> '') and AModule.Replace('/', '\').StartsWith(Folder, True)) then
  begin
    AName := IdeName;
    Exit(TAtlasKeyOrigin.Ide);
  end;
  AName := ChangeFileExt(Name, '');
  Result := TAtlasKeyOrigin.Plugin;
end;

class function TAtlasKeyMap.Overlaps(A, B: TAtlasKeyContext): Boolean;
begin
  Result := (A = B) or (A = TAtlasKeyContext.Global) or (B = TAtlasKeyContext.Global);
end;

class function TAtlasKeyMap.Collide(const A, B: TAtlasKeyItem): Boolean;
begin
  Result := False;
  if (A.ShortCut = 0) or (A.ShortCut <> B.ShortCut) or not Overlaps(A.Context, B.Context) then
  begin
    Exit;
  end;
  if A.Origin <> B.Origin then
  begin
    Exit(True);
  end;
  case A.Origin of
    // Zwei Atlas-Funktionen auf derselben Taste: doppelt belegt.
    TAtlasKeyOrigin.Atlas:
      Result := A.Id <> B.Id;
    TAtlasKeyOrigin.Plugin:
      Result := not SameText(A.OriginName, B.OriginName);
  else
    // Belegungen innerhalb der IDE sind ihre eigene Sache.
    Result := False;
  end;
end;

/// <summary>Kontext, in dem sich AItems[AIndex] mit den Partnern trifft: der eigene, bei globalen Belegungen der
/// engste der Partner (Editor vor Designer vor Willkommensseite).</summary>
function ClashContext(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer;
  const APartners: TArray<Integer>): TAtlasKeyContext;
var
  Partner: Integer;
  Found: Boolean;
  Context: TAtlasKeyContext;
begin
  Result := AItems[AIndex].Context;
  if Result <> TAtlasKeyContext.Global then
  begin
    Exit;
  end;
  for Context in [TAtlasKeyContext.Editor, TAtlasKeyContext.Designer, TAtlasKeyContext.WelcomePage] do
  begin
    Found := False;
    for Partner in APartners do
    begin
      if AItems[Partner].Context = Context then
      begin
        Found := True;
      end;
    end;
    if Found then
    begin
      Exit(Context);
    end;
  end;
end;

/// <summary>Willkommensseite: Das Suchfeld von Atlas nimmt die Taste, solange die Seite aktiv ist; -1 ohne.
/// </summary>
function WindowWinner(const AItems: TArray<TAtlasKeyItem>; const ACandidates: TArray<Integer>): Integer;
var
  Candidate: Integer;
begin
  Result := -1;
  for Candidate in ACandidates do
  begin
    if (AItems[Candidate].Source = TAtlasKeySource.Window) and AItems[Candidate].Active then
    begin
      Exit(Candidate);
    end;
  end;
end;

function IsActiveBinding(const AItem: TAtlasKeyItem): Boolean;
begin
  Result := (AItem.Source = TAtlasKeySource.Binding) and AItem.Active;
end;

/// <summary>Erste aktive Tastaturbelegung, die die IDE als wirksam meldet oder (AtlasFirst) von Atlas mit Vorrang;
/// -1 ohne.</summary>
function FirstBinding(const AItems: TArray<TAtlasKeyItem>; const ACandidates: TArray<Integer>;
  AAtlasFirst: Boolean): Integer;
var
  Candidate: Integer;
  Item: TAtlasKeyItem;
begin
  Result := -1;
  for Candidate in ACandidates do
  begin
    Item := AItems[Candidate];
    if not IsActiveBinding(Item) then
    begin
      Continue;
    end;
    if (not AAtlasFirst and Item.Effective) or
      (AAtlasFirst and (Item.Origin = TAtlasKeyOrigin.Atlas) and Item.Priority) then
    begin
      Exit(Candidate);
    end;
  end;
end;

/// <summary>Löst ACandidate den bisherigen Gewinner AWinner ab? Eine spätere Tastaturbelegung schlägt eine, die
/// weder wirksam ist noch Vorrang hat.</summary>
function Replaces(const AItems: TArray<TAtlasKeyItem>; ACandidate, AWinner: Integer): Boolean;
begin
  Result := (AWinner < 0) or ((AItems[AWinner].Source = TAtlasKeySource.Binding) and
    not AItems[AWinner].Effective and not AItems[AWinner].Priority and
    (AItems[ACandidate].Order > AItems[AWinner].Order));
end;

/// <summary>Editor: Tastaturbelegungen vor Menübefehlen; unter ihnen die wirksame (zuletzt angemeldete).</summary>
function EditorWinner(const AItems: TArray<TAtlasKeyItem>; const ACandidates: TArray<Integer>): Integer;
var
  Candidate: Integer;
begin
  Result := FirstBinding(AItems, ACandidates, False);
  if Result < 0 then
  begin
    Result := FirstBinding(AItems, ACandidates, True);
  end;
  for Candidate in ACandidates do
  begin
    if IsActiveBinding(AItems[Candidate]) and Replaces(AItems, Candidate, Result) then
    begin
      Result := Candidate;
    end;
  end;
end;

/// <summary>Die erste aktive Aktion der Aktionsliste; -1 ohne.</summary>
function ActionWinner(const AItems: TArray<TAtlasKeyItem>; const ACandidates: TArray<Integer>): Integer;
var
  Candidate: Integer;
begin
  Result := -1;
  for Candidate in ACandidates do
  begin
    if (AItems[Candidate].Source = TAtlasKeySource.Action) and AItems[Candidate].Active and
      ((Result < 0) or (AItems[Candidate].Order < AItems[Result].Order)) then
    begin
      Result := Candidate;
    end;
  end;
end;

/// <summary>Gewinnt AWinner nur, weil alle anderen Atlas-Tasten sind, die die Taste überlassen?</summary>
function OnlyAtlasLeft(const AItems: TArray<TAtlasKeyItem>; const ACandidates: TArray<Integer>;
  AWinner: Integer): Boolean;
var
  Candidate: Integer;
begin
  Result := AItems[AWinner].Origin <> TAtlasKeyOrigin.Atlas;
  for Candidate in ACandidates do
  begin
    if (Candidate <> AWinner) and ((AItems[Candidate].Origin <> TAtlasKeyOrigin.Atlas) or AItems[Candidate].Active)
      then
    begin
      Exit(False);
    end;
  end;
end;

/// <summary>Verliert eine Aktion gegen AWinner?</summary>
function ActionLoses(const AItems: TArray<TAtlasKeyItem>; const ACandidates: TArray<Integer>;
  AWinner: Integer): Boolean;
var
  Candidate: Integer;
begin
  Result := False;
  for Candidate in ACandidates do
  begin
    if (Candidate <> AWinner) and (AItems[Candidate].Source = TAtlasKeySource.Action) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Warum AWinner unter ACandidates gewinnt.</summary>
function ReasonOf(const AItems: TArray<TAtlasKeyItem>; const ACandidates: TArray<Integer>;
  AWinner: Integer): TAtlasKeyReason;
var
  Winner: TAtlasKeyItem;
begin
  Winner := AItems[AWinner];
  if OnlyAtlasLeft(AItems, ACandidates, AWinner) then
  begin
    Result := TAtlasKeyReason.AtlasYields;
  end
  else if Winner.Source <> TAtlasKeySource.Binding then
  begin
    Result := TAtlasKeyReason.FirstAction;
  end
  else if (Winner.Origin = TAtlasKeyOrigin.Atlas) and Winner.Priority then
  begin
    Result := TAtlasKeyReason.AtlasPriority;
  end
  else if ActionLoses(AItems, ACandidates, AWinner) then
  begin
    Result := TAtlasKeyReason.EditorBinding;
  end
  else
  begin
    Result := TAtlasKeyReason.LastBinding;
  end;
end;

/// <summary>Gewinner unter ACandidates im Kontext AClash; -1, wenn keine die Taste hält.</summary>
procedure Decide(const AItems: TArray<TAtlasKeyItem>; const ACandidates: TArray<Integer>;
  AClash: TAtlasKeyContext; out AWinner: Integer; out AReason: TAtlasKeyReason);
begin
  AWinner := -1;
  AReason := TAtlasKeyReason.NoneActive;
  if AClash = TAtlasKeyContext.WelcomePage then
  begin
    AWinner := WindowWinner(AItems, ACandidates);
  end;
  if AWinner >= 0 then
  begin
    AReason := TAtlasKeyReason.OwnWindow;
    Exit;
  end;
  if AClash = TAtlasKeyContext.Editor then
  begin
    AWinner := EditorWinner(AItems, ACandidates);
  end;
  // Sonst die erste Aktion der Aktionsliste.
  if AWinner < 0 then
  begin
    AWinner := ActionWinner(AItems, ACandidates);
  end;
  if AWinner >= 0 then
  begin
    AReason := ReasonOf(AItems, ACandidates, AWinner);
  end;
end;

/// <summary>Belegungen, die mit AItems[AIndex] kollidieren.</summary>
function PartnersOf(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer): TArray<Integer>;
var
  Other: Integer;
begin
  Result := nil;
  for Other := 0 to High(AItems) do
  begin
    if (Other <> AIndex) and TAtlasKeyMap.Collide(AItems[AIndex], AItems[Other]) then
    begin
      Result := Result + [Other];
    end;
  end;
end;

/// <summary>AIndex und die Partner, die sich mit dem Kontext AClash überschneiden.</summary>
function CandidatesOf(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer; const APartners: TArray<Integer>;
  AClash: TAtlasKeyContext): TArray<Integer>;
var
  Other: Integer;
begin
  Result := [AIndex];
  for Other in APartners do
  begin
    if TAtlasKeyMap.Overlaps(AItems[Other].Context, AClash) then
    begin
      Result := Result + [Other];
    end;
  end;
end;

class procedure TAtlasKeyMap.Analyze(var AItems: TArray<TAtlasKeyItem>);
var
  Index, Winner: Integer;
  Partners: TArray<Integer>;
  Clash: TAtlasKeyContext;
  Reason: TAtlasKeyReason;
begin
  for Index := 0 to High(AItems) do
  begin
    AItems[Index].Conflict := False;
    AItems[Index].Winner := -1;
    AItems[Index].Wins := False;
    AItems[Index].Reason := TAtlasKeyReason.None;
  end;
  for Index := 0 to High(AItems) do
  begin
    if AItems[Index].ShortCut = 0 then
    begin
      Continue;
    end;
    Partners := PartnersOf(AItems, Index);
    if Length(Partners) = 0 then
    begin
      AItems[Index].Winner := Index;
      AItems[Index].Wins := AItems[Index].Active;
      Continue;
    end;
    AItems[Index].Conflict := True;
    Clash := ClashContext(AItems, Index, Partners);
    Decide(AItems, CandidatesOf(AItems, Index, Partners, Clash), Clash, Winner, Reason);
    AItems[Index].Winner := Winner;
    AItems[Index].Reason := Reason;
    AItems[Index].Wins := Winner = Index;
  end;
end;

class function TAtlasKeyMap.ConflictCount(const AItems: TArray<TAtlasKeyItem>): Integer;
var
  Item: TAtlasKeyItem;
begin
  Result := 0;
  for Item in AItems do
  begin
    if Item.Conflict then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasKeyMap.PartnerOf(const AItems: TArray<TAtlasKeyItem>; AIndex: Integer): Integer;
var
  Other: Integer;
begin
  Result := -1;
  if (AIndex < 0) or (AIndex > High(AItems)) or not AItems[AIndex].Conflict then
  begin
    Exit;
  end;
  if (AItems[AIndex].Winner >= 0) and (AItems[AIndex].Winner <> AIndex) then
  begin
    Exit(AItems[AIndex].Winner);
  end;
  for Other := 0 to High(AItems) do
  begin
    if (Other <> AIndex) and Collide(AItems[AIndex], AItems[Other]) then
    begin
      Exit(Other);
    end;
  end;
end;

class function TAtlasKeyMap.AtlasConflicts(const AItems: TArray<TAtlasKeyItem>): TArray<Integer>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to High(AItems) do
  begin
    if (AItems[Index].Origin = TAtlasKeyOrigin.Atlas) and AItems[Index].Conflict and
      not (AItems[Index].Wins and AItems[Index].Priority) then
    begin
      Result := Result + [Index];
    end;
  end;
end;

class function TAtlasKeyMap.Filter(const AItems: TArray<TAtlasKeyItem>; const AQuery: string;
  AOnlyConflicts: Boolean): TArray<Integer>;
var
  Query: TAtlasKeyQuery;
  Found: TList<Integer>;
  Index: Integer;
  Items: TArray<TAtlasKeyItem>;
begin
  Items := AItems;
  Query := TAtlasKeyQuery.Parse(AQuery);
  Found := TList<Integer>.Create;
  try
    for Index := 0 to High(Items) do
    begin
      if (not AOnlyConflicts or Items[Index].Conflict) and Query.Matches(Items[Index]) then
      begin
        Found.Add(Index);
      end;
    end;
    Found.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := CompareText(Items[A].KeyText, Items[B].KeyText);
        if Result = 0 then
        begin
          Result := Integer(Items[A].ShortCut) - Integer(Items[B].ShortCut);
        end;
        if Result = 0 then
        begin
          Result := CompareText(Items[A].Command, Items[B].Command);
        end;
        if Result = 0 then
        begin
          Result := A - B;
        end;
      end));
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

/// <summary>Umschalttaste zum Namen (deutsch oder englisch); 0, wenn es keine ist.</summary>
function ModifierOf(const AName: string): Word;
begin
  if (AName = 'strg') or (AName = 'ctrl') or (AName = 'control') or (AName = 'ctl') then
  begin
    Result := TAtlasKeyMap.scCtrl;
  end
  else if (AName = 'umschalt') or (AName = 'umsch') or (AName = 'shift') or (AName = 'shft') then
  begin
    Result := TAtlasKeyMap.scShift;
  end
  else if (AName = 'alt') or (AName = 'menu') then
  begin
    Result := TAtlasKeyMap.scAlt;
  end
  else
  begin
    Result := 0;
  end;
end;

type
  /// <summary>Benannte Taste: Namen zwischen „|“ (deutsch und englisch, klein) und ihr virtueller Tastencode.
  /// </summary>
  TNamedKey = record
    Names: string;
    Key: Word;
  end;

const
  NamedKeys: array[0..14] of TNamedKey = (
    (Names: '|leer|leertaste|space|'; Key: $20),
    (Names: '|eingabe|enter|return|'; Key: $0D),
    (Names: '|esc|escape|'; Key: $1B),
    (Names: '|tab|tabulator|'; Key: $09),
    (Names: '|entf|del|delete|'; Key: $2E),
    (Names: '|einfg|ins|insert|'; Key: $2D),
    (Names: '|pos1|home|'; Key: $24),
    (Names: '|ende|end|'; Key: $23),
    (Names: '|bild auf|bildauf|pgup|page up|pageup|'; Key: $21),
    (Names: '|bild ab|bildab|pgdn|page down|pagedown|'; Key: $22),
    (Names: '|rück|rücktaste|backspace|bksp|'; Key: $08), // german-ok: Eingabealias
    (Names: '|links|left|'; Key: $25),
    (Names: '|oben|auf|up|'; Key: $26),
    (Names: '|rechts|right|'; Key: $27),
    (Names: '|unten|ab|down|'; Key: $28));

/// <summary>Taste eines einzelnen Zeichens: Buchstabe, Ziffer, Punkt, Komma, Minus; 0 sonst.</summary>
function CharKey(ACh: Char): Word;
begin
  case ACh of
    'a'..'z':
      Result := Ord(UpCase(ACh));
    '0'..'9':
      Result := Ord(ACh);
    '.':
      Result := $BE;
    ',':
      Result := $BC;
    '-':
      Result := $BD;
  else
    Result := 0;
  end;
end;

/// <summary>Taste aus der Tabelle der benannten Tasten; 0, wenn unbekannt.</summary>
function NamedKey(const AName: string): Word;
var
  Named: TNamedKey;
begin
  Result := 0;
  // „|“ trennt die Namen in der Tabelle und ist selbst keiner.
  if Pos('|', AName) > 0 then
  begin
    Exit;
  end;
  for Named in NamedKeys do
  begin
    if Pos('|' + AName + '|', Named.Names) > 0 then
    begin
      Exit(Named.Key);
    end;
  end;
end;

/// <summary>Virtueller Tastencode zum Namen (deutsch oder englisch); 0, wenn unbekannt. AFunctionKey bei F1–F24.
/// </summary>
function KeyOf(const AName: string; out AFunctionKey: Boolean): Word;
var
  Number: Integer;
begin
  AFunctionKey := False;
  if Length(AName) <= 1 then
  begin
    Result := 0;
    if AName <> '' then
    begin
      Result := CharKey(AName[1]);
    end;
  end
  else if (AName[1] = 'f') and TryStrToInt(Copy(AName, 2, MaxInt), Number) and (Number >= 1) and (Number <= 24) then
  begin
    AFunctionKey := True;
    Result := $70 + Number - 1;
  end
  else
  begin
    Result := NamedKey(AName);
  end;
end;

class function TAtlasKeyMap.ParseShortCut(const AText: string; out AModifiers: Word): Word;
var
  Parts: TArray<string>;
  Index: Integer;
  Part: string;
  Modifier, Key: Word;
  FunctionKey: Boolean;
begin
  Result := 0;
  AModifiers := 0;
  Parts := LowerCase(Trim(AText)).Split(['+']);
  if Length(Parts) = 0 then
  begin
    Exit;
  end;
  for Index := 0 to High(Parts) do
  begin
    Part := Trim(Parts[Index]);
    if (Part = '') and (Index = High(Parts)) and (Index > 0) then
    begin
      // „Strg+“: nur Umschalttasten.
      Exit;
    end;
    Modifier := ModifierOf(Part);
    if Modifier <> 0 then
    begin
      AModifiers := AModifiers or Modifier;
      Continue;
    end;
    // Eine Taste nur am Ende.
    Key := KeyOf(Part, FunctionKey);
    if (Key = 0) or (Index <> High(Parts)) then
    begin
      AModifiers := 0;
      Exit;
    end;
    // Ein einzelnes Zeichen ohne Umschalttaste ist eine Textsuche, eine Funktionstaste nicht.
    if (Length(Parts) = 1) and not FunctionKey then
    begin
      Exit;
    end;
    Result := Key or AModifiers;
  end;
end;

class function TAtlasKeyMap.HtmlEscape(const AText: string): string;
var
  Builder: TStringBuilder;
  Ch: Char;
begin
  Builder := TStringBuilder.Create;
  try
    for Ch in AText do
      case Ch of
        '&':
          Builder.Append('&amp;');
        '<':
          Builder.Append('&lt;');
        '>':
          Builder.Append('&gt;');
        '"':
          Builder.Append('&quot;');
        '''':
          Builder.Append('&#39;');
      else
        Builder.Append(Ch);
      end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

const
  /// <summary>Kopf der Seite ab der Formatvorlage bis zum Beginn von body.</summary>
  HtmlStyle = '<style>'#13#10 +
    'body{font:13px "Segoe UI",Arial,sans-serif;color:#1f2328;margin:24px}'#13#10 +
    'h1{font-size:20px;margin:0 0 4px}'#13#10 +
    'p.sub{color:#59636e;margin:0 0 12px}'#13#10 +
    'button.print{margin:0 0 12px;padding:4px 12px}'#13#10 +
    'table{border-collapse:collapse;width:100%}'#13#10 +
    'th,td{text-align:left;padding:4px 8px;border-bottom:1px solid #d1d9e0;vertical-align:top}'#13#10 +
    'th{background:#f6f8fa}'#13#10 +
    'td.key{font-family:Consolas,"Courier New",monospace;white-space:nowrap}'#13#10 +
    'tr.conflict td{color:#cf222e}'#13#10 +
    'tr.conflict td.key{font-weight:600}'#13#10 +
    '@media print{body{margin:0}button.print{display:none}thead{display:table-header-group}' +
    'tr{page-break-inside:avoid}tr.conflict td{color:#cf222e;-webkit-print-color-adjust:exact;' +
    'print-color-adjust:exact}}'#13#10 +
    '</style>'#13#10'</head>'#13#10'<body>'#13#10;

/// <summary>Tabellenzeile ARow; die erste Zelle ist die Taste, Zeilen mit Konflikt sind markiert.</summary>
procedure AppendRow(ABuilder: TStringBuilder; const ARow: TAtlasKeyHtmlRow);
var
  Index: Integer;
begin
  if ARow.Conflict then
  begin
    ABuilder.Append('<tr class="conflict">');
  end
  else
  begin
    ABuilder.Append('<tr>');
  end;
  for Index := 0 to High(ARow.Cells) do
  begin
    if Index = 0 then
    begin
      ABuilder.Append('<td class="key">');
    end
    else
    begin
      ABuilder.Append('<td>');
    end;
    ABuilder.Append(TAtlasKeyMap.HtmlEscape(ARow.Cells[Index])).Append('</td>');
  end;
  ABuilder.Append('</tr>'#13#10);
end;

class function TAtlasKeyMap.Html(const ALanguage, ATitle, ASubtitle, APrint: string;
  const AHeaders: TArray<string>; const ARows: TArray<TAtlasKeyHtmlRow>): string;
var
  Builder: TStringBuilder;
  Header: string;
  Row: TAtlasKeyHtmlRow;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('<!DOCTYPE html>'#13#10'<html lang="').Append(HtmlEscape(ALanguage)).Append('">'#13#10);
    Builder.Append('<head>'#13#10'<meta charset="utf-8">'#13#10);
    Builder.Append('<title>').Append(HtmlEscape(ATitle)).Append('</title>'#13#10);
    Builder.Append(HtmlStyle);
    Builder.Append('<h1>').Append(HtmlEscape(ATitle)).Append('</h1>'#13#10);
    if ASubtitle <> '' then
    begin
      Builder.Append('<p class="sub">').Append(HtmlEscape(ASubtitle)).Append('</p>'#13#10);
    end;
    if APrint <> '' then
    begin
      Builder.Append('<button class="print" onclick="window.print()">').Append(HtmlEscape(APrint))
        .Append('</button>'#13#10);
    end;
    Builder.Append('<table>'#13#10'<thead><tr>');
    for Header in AHeaders do
    begin
      Builder.Append('<th>').Append(HtmlEscape(Header)).Append('</th>');
    end;
    Builder.Append('</tr></thead>'#13#10'<tbody>'#13#10);
    for Row in ARows do
    begin
      AppendRow(Builder, Row);
    end;
    Builder.Append('</tbody>'#13#10'</table>'#13#10'</body>'#13#10'</html>'#13#10);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

end.
