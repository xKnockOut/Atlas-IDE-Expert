unit Atlas.Core.Commands.Contract;

// Contract des Plugin-Features Commands (#1443): Befehle und Zusatzquellen der Befehlspalette
// (#502, #1270), Funktionen mit Tastenkürzel (#520) und die Schnittstellen, über die Module
// Befehle anmelden, Paletten-Quellen und übernommene Aktionen bereitstellen und auf die
// Zählung der Befehle hören (#1455). Die Root-Units des Features führen die Typen als Alias
// weiter.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  TAtlasCommand = record
    /// <summary>Eindeutig, z. B. Name der Aktion oder "Atlas.Options".</summary>
    Id: string;
    Caption: string;
    /// <summary>Menüpfad bzw. Kategorie, gedimmt angezeigt ("Projekt › Erzeugen").</summary>
    Path: string;
    ShortCut: string;
    Description: string;
    IsAtlas: Boolean;
    /// <summary>Abzeichen rechts in der Zeile (Zustand eines Issues, #1270); '' ohne.</summary>
    Badge: string;
  end;

  /// <summary>Wie ein Eintrag einer Zusatzgruppe ausgeführt wird: Enter (Open), Strg+Enter (Start),
  /// Umschalt+Enter (Browse), Strg+C (Copy, die Palette bleibt offen), Alt+Enter (Toggle: Schnellschalter einer
  /// Einstellung umschalten, #1884).</summary>
  TAtlasPaletteAction = (Open, Start, Browse, Copy, Toggle);

  /// <summary>Gruppe einer Zusatzquelle unter den Befehlen (#1270).</summary>
  TAtlasPaletteGroup = record
    /// <summary>Überschrift ("Issues"); '' = keine Gruppe.</summary>
    Title: string;
    /// <summary>Zeile unter der Überschrift ("Suche im Tracker …", Fehler, Tastenhinweis); '' ohne.</summary>
    Status: string;
    /// <summary>Text, dessen Zeichen in den Einträgen hervorgehoben werden.</summary>
    Highlight: string;
    Items: TArray<TAtlasCommand>;
    class function None: TAtlasPaletteGroup; static;
    class function Create(const ATitle, AStatus, AHighlight: string;
      const AItems: TArray<TAtlasCommand>): TAtlasPaletteGroup; static;
    function Visible: Boolean;
  end;

  /// <summary>Zusatzquelle der Palette (#1270), z. B. Issues im Tracker. Alle Aufrufe im Hauptthread.</summary>
  IAtlasPaletteSource = interface
    ['{D1D5D951-0AD7-4D3E-80D8-5021BD5F0C41}']
    /// <summary>Palette geöffnet; AShow zeigt bzw. ersetzt die Gruppe, auch später (nach Closed wirkungslos).
    /// </summary>
    procedure Opened(const AShow: TProc<TAtlasPaletteGroup>);
    /// <summary>Eingabe geändert (auch auf leer).</summary>
    procedure Changed(const APattern: string);
    /// <summary>Eintrag der Gruppe ausgeführt; außer bei Copy ist die Palette danach geschlossen.</summary>
    procedure Execute(const AItem: TAtlasCommand; AAction: TAtlasPaletteAction);
    /// <summary>Palette geschlossen: laufende Anfragen abbrechen, AShow nicht mehr rufen.</summary>
    procedure Closed;
  end;

  /// <summary>Liefert beim Öffnen der Palette eine Zusatzquelle (#1270, #1455); ein Modul stellt es über seinen
  /// Scope bereit (etwa „Meine Issues“). nil = gerade keine Quelle. Hauptthread.</summary>
  IAtlasPaletteSourceProvider = interface
    ['{C737B249-C8ED-44D7-A33E-BEB867FED4B5}']
    function PaletteSource: IAtlasPaletteSource;
  end;

  /// <summary>Atlas-Befehle anmelden (Palette, #520); ohne VCL und Open Tools API. Features melden ihre Befehle
  /// darüber an, statt die Palette der IDE-Schicht zu importieren. Ohne Referenzzählung: Die Palette
  /// gehört der Composition; Empfänger speichern die Schnittstelle nicht.</summary>
  IAtlasCommandRegistry = interface
    ['{57AA1265-60F8-4655-BC7B-1AE31AC48481}']
    /// <summary>Atlas-Befehl für die Palette (Beschriftung mit „Atlas: “ davor).</summary>
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc); overload;
    /// <summary>Wie oben; der Befehl erscheint nur, solange AVisible True liefert (#520).</summary>
    procedure RegisterCommand(const AId, ACaption, ADescription: string; const AProc: TProc;
      const AVisible: TFunc<Boolean>); overload;
  end;

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
  /// nur hinten anhängen: Die Ordnungszahl steckt in Kennungen der Übersicht. Sicher löschen (#716). Neue Zeile am Ende
  /// des Abschnitts (#1768).</summary>
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
    DesignerInlineCaption, DesignerSelectionBar, DesignerMagnifier, DesignerUsages, TestsListRun, DebugReattach);

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

  /// <summary>Hörer der Zählung (#757, #1455), etwa die Karte „Atlas entdecken“ eines Moduls; ein Modul stellt ihn
  /// über seinen Scope bereit. Hauptthread.</summary>
  IAtlasCommandUsageListener = interface
    ['{F66EA46F-1AE5-4CD7-94C5-3BACEC4433D8}']
    /// <summary>„Zählung zurücksetzen“ (Einstellungen): Zähler sind leer.</summary>
    procedure UsageReset;
  end;

implementation

{ TAtlasPaletteGroup }

class function TAtlasPaletteGroup.None: TAtlasPaletteGroup;
begin
  Result.Title := '';
  Result.Status := '';
  Result.Highlight := '';
  Result.Items := nil;
end;

class function TAtlasPaletteGroup.Create(const ATitle, AStatus, AHighlight: string;
  const AItems: TArray<TAtlasCommand>): TAtlasPaletteGroup;
begin
  Result.Title := ATitle;
  Result.Status := AStatus;
  Result.Highlight := AHighlight;
  Result.Items := AItems;
end;

function TAtlasPaletteGroup.Visible: Boolean;
begin
  Result := Title <> '';
end;

end.
