unit Atlas.Core.Problems.Findings;

// Modell des Fensters „Atlas-Prüfung“ (#909), ohne VCL und Open Tools API.
// Die Befunde kommen aus demselben Speicher wie Wellenlinien und Hover
// (TAtlasProblemStore, #398); es gibt keine zweite Prüfung.
// - TAtlasFindings: Befunde aus dem Speicher (ohne inaktive Zweige, uses-
//   Hinweise und Testmeldungen), Art aus dem Schweregrad (error → Error,
//   warning → Warnung, information/hint → Info), Kategorie aus dem Katalog
//   bzw. „Compiler“ für dcc, Zeilentext ohne Einrückung, Spalten-Layout als
//   Text für problems.window.columns. Spalte „Compiler“ (#1024): Code der
//   Compilermeldung bzw. die Codes, denen die Regel entspricht, mit
//   „Atlas + dcc“, wenn der letzte Build den Befund bestätigt.
// - TAtlasFindingsCache (Atlas.Core.Problems.FindingsCache) baut darauf auf.
// - TAtlasFindingsView: Filter (Bereich, Arten, Kategorie, Text, Compiler),
//   Gruppierung (keine, Datei, Regel, Kategorie), Sortierung (Vorgabe Art,
//   Datei, Zeile; Klick auf eine Spalte sortiert nach ihr, zweiter Klick
//   kehrt um), Zeilen mit aufklappbaren Gruppen, Zähler je Art. Neue Befunde
//   werden kurz markiert (IsNew). Auswahl und Aufklappzustand hängen an
//   Schlüsseln, die nicht von der Zeile abhängen: Sie bleiben erhalten, wenn
//   die Zeilen beim Tippen mitwandern oder neue Ergebnisse kommen.
// - Offene Units zuerst (#1108, problems.window.openFirst): Die Stufe (aktive
//   Unit, geöffnete Units, nicht geöffnete Units) ist der erste
//   Sortierschlüssel, die Spaltensortierung gilt innerhalb der Stufe. Bei
//   Gruppierung nach Datei steht die Gruppe der aktiven Unit angepinnt oben,
//   darunter Trennzeilen „Geöffnet“ und „Nicht geöffnet“ mit den Gruppen
//   alphabetisch; ohne Gruppierung dieselben drei Abschnitte als Trennzeilen;
//   bei Regel oder Kategorie nur die Reihenfolge innerhalb jeder Gruppe.
//   Nicht geöffnete Units ausgegraut, normal oder ausgeblendet
//   (problems.window.closedUnits); die aktive Unit auf Wunsch auch ohne
//   Befunde (problems.window.showCleanActive). Trennzeilen sind weder Gruppen
//   noch Befunde: nicht klappbar, nicht wählbar, nicht in Visible, Step,
//   SelectAt und beim Kopieren. .pas und .dfm/.fmx einer Unit zählen als eine.
// - IAtlasBulkFixer: Vertrag der Sammelkorrektur (#1352) für das Modul
//   Prüfregeln (#1455).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store;

type
  {$SCOPEDENUMS ON}
  /// <summary>Spalte „Art“: Error (auch Bug), Warnung, Info (information und hint).</summary>
  TAtlasFindingKind = (Error, Warning, Info);
  TAtlasFindingCategory = (Bug, Vulnerability, CodeSmell, SecurityHotspot, Compiler, Other);
  TAtlasFindingColumn = (Icon, Kind, Category, Message, Line, Location, Rule, Compiler);
  TAtlasFindingScope = (CurrentFile, Project, Group);
  TAtlasFindingGrouping = (None, ByFile, ByRule, ByCategory);
  /// <summary>Stufe einer Datei (#1108): Datei des oberen Editors, in der IDE geöffnet, nicht geöffnet.</summary>
  TAtlasFindingTier = (Active, Open, Closed);
  /// <summary>Darstellung nicht geöffneter Units (problems.window.closedUnits).</summary>
  TAtlasClosedUnits = (Dimmed, Normal, Hidden);
  {$SCOPEDENUMS OFF}
  TAtlasFindingKinds = set of TAtlasFindingKind;

  TAtlasFinding = record
    FileName: string;
    Problem: TAtlasProblem;
    Kind: TAtlasFindingKind;
    Category: TAtlasFindingCategory;
    /// <summary>Betroffene Quelltextzeile ohne führenden und folgenden Leerraum; '' wenn unbekannt.</summary>
    LineText: string;
    /// <summary>Datei, Regel, Meldung und laufende Nummer: unabhängig von der Zeile.</summary>
    Key: string;
    /// <summary>Stufe der Datei (#1108); setzt TAtlasFindingsView aus den geöffneten Dateien.</summary>
    Tier: TAtlasFindingTier;
    /// <summary>"Unit1.pas:12:5" (1-basiert).</summary>
    function Location: string;
    /// <summary>Zeilentext, gekürzt auf AMax Zeichen mit „…“.</summary>
    function ShortLine(AMax: Integer): string;
    /// <summary>Regel-ID bzw. Meldungsnummer des Compilers.</summary>
    function Rule: string;
    /// <summary>Spalte „Compiler“ (#1024): "E2035", "E2034, E2035" oder "E2035 · Atlas + dcc" bei einem vom
    /// Build bestätigten Befund; '' ohne Code.</summary>
    function CompilerText: string;
    /// <summary>Meldung; ohne AShowCompilerCode (problems.showCompilerCode aus) ohne „(wie E2035)“.</summary>
    function MessageText(AShowCompilerCode: Boolean): string;
  end;

  /// <summary>Sammelkorrektur (#1352) im Kontextmenü von „Atlas-Prüfung“; ein Modul stellt sie bereit (#1455, Modul
  /// Prüfregeln), das Fenster fragt laufende Module. Ohne Modul fehlt der Eintrag.</summary>
  IAtlasBulkFixer = interface
    ['{3B7E2D91-5A4C-4F68-9E13-C82D6A0F7B54}']
    /// <summary>Eintrag sichtbar (fix.bulk an).</summary>
    function CanFixAll: Boolean;
    /// <summary>Alle sicheren Treffer von ARule in den Dateien von AFindings (den angezeigten Befunden) korrigieren:
    /// Vorschau, dann die gewählten Dateien. Nur im Hauptthread.</summary>
    procedure FixAll(const ARule: string; const AFindings: TArray<TAtlasFinding>);
  end;

  TAtlasFindingColumnState = record
    Column: TAtlasFindingColumn;
    /// <summary>Breite in Pixeln bei 96 dpi; 0 = Vorgabe.</summary>
    Width: Integer;
    Visible: Boolean;
    class function Create(AColumn: TAtlasFindingColumn; AWidth: Integer; AVisible: Boolean):
      TAtlasFindingColumnState; static;
  end;

  TAtlasFindingCounts = record
    Errors: Integer;
    Warnings: Integer;
    Infos: Integer;
    /// <summary>Dateien mit sichtbaren Befunden.</summary>
    Files: Integer;
    /// <summary>Offene Units zuerst (#1108): Units der aktiven und geöffneten Stufe mit sichtbaren Befunden und
    /// deren Befunde; sonst 0.</summary>
    OpenUnits: Integer;
    OpenFindings: Integer;
    /// <summary>Nicht geöffnete Units mit sichtbaren Befunden und deren Befunde; sonst 0.</summary>
    ClosedUnits: Integer;
    ClosedFindings: Integer;
    /// <summary>Nicht geöffnete Units, deren Befunde problems.window.closedUnits = hidden ausblendet.</summary>
    HiddenUnits: Integer;
    function Total: Integer;
    function OfKind(AKind: TAtlasFindingKind): Integer;
  end;

  TAtlasFindingFilter = record
    Scope: TAtlasFindingScope;
    Kinds: TAtlasFindingKinds;
    /// <summary>False = alle Kategorien.</summary>
    OneCategory: Boolean;
    Category: TAtlasFindingCategory;
    /// <summary>Teiltext in Meldung, Regel oder Datei (Groß-/Kleinschreibung egal); '' = alle.</summary>
    Text: string;
    /// <summary>Compilermeldungen zeigen (problems.window.compiler).</summary>
    Compiler: Boolean;
    /// <summary>Bereich „aktuelle Datei“.</summary>
    CurrentFile: string;
    /// <summary>Bereich „Projekt“ bzw. „Projektgruppe“: Dateien des Bereichs; nil = alle Dateien des Speichers.</summary>
    Files: TArray<string>;
    /// <summary>Alle Arten und Kategorien, Bereich Projektgruppe, ohne Compiler.</summary>
    class function Create: TAtlasFindingFilter; static;
    /// <summary>Alles außer den Arten: für die Zähler auf den Umschaltern.</summary>
    function MatchesExceptKind(const AFinding: TAtlasFinding): Boolean;
    function Matches(const AFinding: TAtlasFinding): Boolean;
  end;

  TAtlasFindingRow = record
    IsGroup: Boolean;
    /// <summary>Gruppe der Zeile bzw. des Befunds; '' ohne Gruppierung.</summary>
    GroupKey: string;
    /// <summary>Gruppenzeile: Datei (ohne Pfad), Regel oder Kategorie (Name der Kategorie); sonst ''.</summary>
    Caption: string;
    /// <summary>Gruppenzeile: Befunde der Gruppe.</summary>
    Count: Integer;
    /// <summary>Gruppenzeile: Kategorie bei Gruppierung nach Kategorie.</summary>
    Category: TAtlasFindingCategory;
    Expanded: Boolean;
    /// <summary>Befundzeile: Index in TAtlasFindingsView.Findings; -1 bei Gruppenzeilen.</summary>
    Finding: Integer;
    /// <summary>Befund kam mit der letzten Aktualisierung neu dazu.</summary>
    IsNew: Boolean;
    /// <summary>Trennzeile (#1108): „Geöffnet“, „Nicht geöffnet“, ohne Gruppierung auch die aktive Unit; weder
    /// Gruppe noch Befund. Caption = Datei der aktiven Unit, Count = Befunde, Units = Units des Abschnitts.</summary>
    IsSection: Boolean;
    Units: Integer;
    /// <summary>Stufe der Zeile; nur mit Offene-zuerst aussagekräftig.</summary>
    Tier: TAtlasFindingTier;
    /// <summary>Zeile der aktiven Unit: hinterlegt, Gruppe mit Nadel.</summary>
    Pinned: Boolean;
    /// <summary>Zeile einer nicht geöffneten Unit: ausgegraut (problems.window.closedUnits = dimmed).</summary>
    Dimmed: Boolean;
    /// <summary>Aktive Unit ohne Befunde (problems.window.showCleanActive): Trennzeile „Keine Befunde“ bzw. „wird
    /// geprüft …“ (Checking), solange der Server die Datei noch nicht geliefert hat.</summary>
    IsCleanActive: Boolean;
    Checking: Boolean;
  end;

  TAtlasFindings = class
  public const
    /// <summary>Zeilentext in der Spalte „Zeile“; länger mit „…“, der Tooltip zeigt die ganze Zeile.</summary>
    LineMax = 80;
    ColumnNames: array[TAtlasFindingColumn] of string = ('icon', 'kind', 'category', 'message', 'line',
      'location', 'rule', 'compiler');
    /// <summary>Marke eines vom Compiler bestätigten Befunds (#1024).</summary>
    ConfirmedMark = TAtlasProblem.ConfirmedSource;
    ScopeNames: array[TAtlasFindingScope] of string = ('file', 'project', 'group');
    GroupingNames: array[TAtlasFindingGrouping] of string = ('none', 'file', 'rule', 'category');
    ClosedUnitsNames: array[TAtlasClosedUnits] of string = ('dimmed', 'normal', 'hidden');
  public
    /// <summary>Vergleichsschlüssel einer Datei (#1108): Kleinbuchstaben, Formular (.dfm/.fmx) als seine .pas.
    /// </summary>
    class function UnitKey(const AFileName: string): string; static;
    class function TryParseClosedUnits(const AText: string; out AValue: TAtlasClosedUnits): Boolean; static;
    class function KindOf(ASeverity: TAtlasProblemSeverity): TAtlasFindingKind; static;
    /// <summary>dcc = Compiler; sonst nach data.category ("bug", "vulnerability", "code-smell",
    /// "security-hotspot"), ohne Kategorie Other.</summary>
    class function CategoryOf(const AProblem: TAtlasProblem): TAtlasFindingCategory; static;
    /// <summary>Gehört der Eintrag in das Fenster? Ohne inaktive Zweige, uses-Hinweise (#621) und Tests (#69).
    /// </summary>
    class function IsFinding(const AProblem: TAtlasProblem): Boolean; static;
    /// <summary>Befunde der Dateien AFiles (nil = alle Dateien des Speichers). Zeilentext aus dem bekannten Text
    /// des Speichers, sonst aus den Zeilen von AReadLines (je Datei höchstens ein Aufruf; nil = ohne).</summary>
    class function FromStore(AStore: TAtlasProblemStore; const AFiles: TArray<string>;
      const AReadLines: TFunc<string, TArray<string>>): TArray<TAtlasFinding>; static;
    /// <summary>Befunde einer Datei des Speichers, Zeilentext wie bei FromStore.</summary>
    class function FromStoreFile(AStore: TAtlasProblemStore; const AFileName: string;
      const AReadLines: TFunc<string, TArray<string>>): TArray<TAtlasFinding>; static;
    /// <summary>Hängt die Listen aneinander, mit einer einzigen Belegung.</summary>
    class function Concat(const AParts: TArray<TArray<TAtlasFinding>>): TArray<TAtlasFinding>; static;
    /// <summary>Aus einer Liste je Datei; vergibt die Schlüssel.</summary>
    class function FromProblems(const AFileName: string; const AProblems: TArray<TAtlasProblem>;
      const ALines: TArray<string>): TArray<TAtlasFinding>; static;
    /// <summary>Ohne führenden und folgenden Leerraum, gekürzt auf AMax Zeichen mit „…“.</summary>
    class function Shorten(const AText: string; AMax: Integer): string; static;
    /// <summary>Wie viele von AProjectFiles hat der Server schon geliefert (Statuszeile „214 von 214 Units
    /// geprüft“)?</summary>
    class function CheckedCount(AStore: TAtlasProblemStore; const AProjectFiles: TArray<string>): Integer; static;
    /// <summary>Spalten aus problems.window.columns: "kind:70,category,-rule,…" (Name, optional Breite, "-" =
    /// ausgeblendet). Unbekannte Namen fallen weg, fehlende Spalten kommen hinten dazu; Pflichtspalten sind immer
    /// sichtbar. '' = alle in der Vorgabe-Reihenfolge.</summary>
    class function ParseColumns(const AText: string): TArray<TAtlasFindingColumnState>; static;
    class function FormatColumns(const AColumns: TArray<TAtlasFindingColumnState>): string; static;
    /// <summary>Icon, Art, Kategorie, Zeile und Stelle lassen sich nicht ausblenden.</summary>
    class function IsMandatory(AColumn: TAtlasFindingColumn): Boolean; static;
    class function TryParseScope(const AText: string; out AScope: TAtlasFindingScope): Boolean; static;
    class function TryParseGrouping(const AText: string; out AGrouping: TAtlasFindingGrouping): Boolean; static;
    /// <summary>„Kopieren“: je Befund eine Zeile im Format des Compilers, "Unit.pas:12:5: warning [regel]
    /// Meldung", dahinter eingerückt der Zeilentext; Zeilenende CRLF.</summary>
    class function AsText(const AFindings: TArray<TAtlasFinding>): string; static;
  end;

  /// <summary>Befunde je Stufe in der angezeigten Reihenfolge (Indizes in die Befunde).</summary>
  TAtlasFindingTierMembers = array[TAtlasFindingTier] of TArray<Integer>;

  /// <summary>Befunde mit Filter und Stufen (offene Units zuerst, #1108); Grundlage von TAtlasFindingsView.
  /// </summary>
  TAtlasFindingsSource = class
  protected
    FFindings: TArray<TAtlasFinding>;
    FFilter: TAtlasFindingFilter;
    FKnown: TDictionary<string, Boolean>;
    FNew: TDictionary<string, Boolean>;
    FFilled: Boolean;
    FOpenFirst: Boolean;
    FClosedUnits: TAtlasClosedUnits;
    FShowCleanActive: Boolean;
    FActiveFile: string;
    FActiveKey: string;
    FActiveChecked: Boolean;
    FOpenKeys: TDictionary<string, Boolean>;
    /// <summary>Zeilen und Zähler nach einer Änderung neu aufbauen.</summary>
    procedure Rebuild; virtual; abstract;
    procedure SetFilter(const AValue: TAtlasFindingFilter);
    procedure SetOpenFirst(AValue: Boolean);
    procedure SetClosedUnits(AValue: TAtlasClosedUnits);
    procedure SetShowCleanActive(AValue: Boolean);
    function TierOf(const AFileName: string): TAtlasFindingTier;
    procedure AssignTiers;
    /// <summary>Wird AFinding wegen problems.window.closedUnits = hidden ausgeblendet?</summary>
    function HiddenByTier(const AFinding: TAtlasFinding): Boolean;
    function IsActiveInScope: Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neuer Stand aus dem Speicher. Befunde, deren Schlüssel vorher fehlte, sind neu (nicht beim ersten
    /// Füllen).</summary>
    procedure SetFindings(const AFindings: TArray<TAtlasFinding>);
    /// <summary>Offene Units zuerst (#1108): AActive = Datei des oberen Editors ('' = keine), AOpen = alle in der
    /// IDE geöffneten Dateien; AActiveChecked = der Server hat die aktive Datei schon geliefert (sonst zeigt die
    /// Zeile ohne Befunde „wird geprüft …“).</summary>
    procedure SetOpenFiles(const AActive: string; const AOpen: TArray<string>; AActiveChecked: Boolean);
    /// <summary>Wirkt die Stufe gerade? Offene-zuerst an und Bereich nicht „Aktuelle Datei“.</summary>
    function TiersActive: Boolean;
    /// <summary>Markierung „neu“ entfernen (nach dem kurzen Hervorheben).</summary>
    procedure ClearNew;
    function Finding(AIndex: Integer): TAtlasFinding;
    property Filter: TAtlasFindingFilter read FFilter write SetFilter;
    /// <summary>problems.window.openFirst; im Modell Vorgabe aus, die Einstellung hat Vorgabe an.</summary>
    property OpenFirst: Boolean read FOpenFirst write SetOpenFirst;
    /// <summary>problems.window.closedUnits (Vorgabe ausgegraut).</summary>
    property ClosedUnits: TAtlasClosedUnits read FClosedUnits write SetClosedUnits;
    /// <summary>problems.window.showCleanActive (Vorgabe an).</summary>
    property ShowCleanActive: Boolean read FShowCleanActive write SetShowCleanActive;
    property ActiveFile: string read FActiveFile;
  end;

  /// <summary>Gruppierung und Sortierung der Befunde.</summary>
  TAtlasFindingsSorted = class(TAtlasFindingsSource)
  protected
    FGrouping: TAtlasFindingGrouping;
    FSortColumn: TAtlasFindingColumn;
    FSortDescending: Boolean;
    FSortCustom: Boolean;
    procedure SetGrouping(AValue: TAtlasFindingGrouping);
    function GroupKeyOf(const AFinding: TAtlasFinding): string;
    function Compare(const A, B: TAtlasFinding): Integer;
    /// <summary>Reihenfolge zweier Gruppen nach ihrem ersten Befund; bei Gleichstand nach dem Schlüssel.</summary>
    function CompareGroups(const AFirstA, AFirstB: TAtlasFinding; const AKeyA, AKeyB: string): Integer;
    /// <summary>Indizes der Befunde unter Filter und Stufe, sortiert.</summary>
    function SortedMatches: TArray<Integer>;
    /// <summary>Trennzeilen der Stufen gelten nach Datei (bei Regel und Kategorie würden sie sich wiederholen).
    /// </summary>
    function TiersByFile: Boolean;
  public
    constructor Create;
    /// <summary>Klick auf den Spaltenkopf: nach AColumn sortieren, beim zweiten Klick absteigend.</summary>
    procedure SortBy(AColumn: TAtlasFindingColumn);
    /// <summary>Zurück zur Vorgabe: Art, Datei, Zeile.</summary>
    procedure ResetSort;
    property Grouping: TAtlasFindingGrouping read FGrouping write SetGrouping;
    property SortColumn: TAtlasFindingColumn read FSortColumn;
    property SortDescending: Boolean read FSortDescending;
    property SortCustom: Boolean read FSortCustom;
  end;

  TAtlasFindingsView = class(TAtlasFindingsSorted)
  private
    FCollapsed: TDictionary<string, Boolean>;
    FVisible: TArray<Integer>;
    FRows: TArray<TAtlasFindingRow>;
    FSelectedKey: string;
    // Counts bis zum nächsten Rebuild: Das Fenster fragt sie in jedem Takt für die Statuszeile.
    FCounts: TAtlasFindingCounts;
    FCountsValid: Boolean;
    // BeginUpdate/EndUpdate: ein Neuaufbau für mehrere Änderungen.
    FUpdateCount: Integer;
    FRebuildPending: Boolean;
    function GetSelectedRow: Integer;
    /// <summary>Zeile für AFinding mit Stufe, Nadel und Grau.</summary>
    function FindingRow(AIndex: Integer; const AGroupKey: string): TAtlasFindingRow;
    /// <summary>Trennzeile der Stufe ATier über die Befunde AMembers.</summary>
    function SectionRow(ATier: TAtlasFindingTier; const AMembers: TArray<Integer>): TAtlasFindingRow;
    /// <summary>Zeile „Keine Befunde“ der aktiven Unit, wenn sie gezeigt werden soll.</summary>
    function CleanActiveRow(out ARow: TAtlasFindingRow): Boolean;
    /// <summary>Kopfzeile der Gruppe AKey mit ihrem ersten Befund und Aufklappzustand.</summary>
    function GroupRow(const AKey: string; const AFirst: TAtlasFinding; ACount: Integer): TAtlasFindingRow;
    /// <summary>Ohne Gruppierung (#1108): die drei Stufen als Trennzeilen, die aktive Unit auch ohne Befunde.
    /// </summary>
    procedure RebuildFlat(const AOrder: TArray<Integer>; const AOfTier: TAtlasFindingTierMembers;
      ARows: TList<TAtlasFindingRow>);
    procedure RebuildGrouped(const AOrder: TArray<Integer>; const AOfTier: TAtlasFindingTierMembers;
      ARows: TList<TAtlasFindingRow>);
    /// <summary>Indizes der sichtbaren Befunde der Gruppe AGroupKey.</summary>
    function GroupMembers(const AGroupKey: string): TArray<Integer>;
  protected
    procedure Rebuild; override;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Änderungen sammeln (Filter, Befunde, offene Dateien): Zeilen und Zähler werden erst mit dem letzten
    /// EndUpdate einmal neu aufgebaut, nicht nach jeder einzelnen Änderung. Dazwischen nicht lesen.</summary>
    procedure BeginUpdate;
    procedure EndUpdate;
    function Rows: TArray<TAtlasFindingRow>;
    /// <summary>Befunde in der angezeigten Reihenfolge (gefiltert, unabhängig vom Aufklappen).</summary>
    function Visible: TArray<TAtlasFinding>;
    /// <summary>Zähler je Art unter dem Filter ohne die Arten; Files zählt die Dateien der sichtbaren Befunde.
    /// </summary>
    function Counts: TAtlasFindingCounts;
    /// <summary>Gruppe auf- bzw. zuklappen (bleibt über Aktualisierungen erhalten).</summary>
    procedure SetExpanded(const AGroupKey: string; AExpanded: Boolean);
    procedure Toggle(ARow: Integer);
    procedure Select(ARow: Integer);
    /// <summary>Markierung folgt dem Cursor: ersten Befund auf der Zeile (0-basiert) wählen; True, wenn einer
    /// gefunden wurde. Klappt seine Gruppe auf.</summary>
    function SelectAt(const AFileName: string; ALine: Integer): Boolean;
    /// <summary>Nächster bzw. vorheriger Befund der gefilterten Liste ab der Auswahl (am Ende wieder vorn); wählt
    /// ihn aus und klappt seine Gruppe auf.</summary>
    function Step(AForward: Boolean; out AFinding: TAtlasFinding): Boolean;
    /// <summary>Befunde der Zeilen ARows ohne Doppelte, zum Kopieren; eine Gruppenzeile steht für ihre Befunde.
    /// </summary>
    function FindingsOfRows(const ARows: TArray<Integer>): TArray<TAtlasFinding>;
    function SelectedFinding(out AFinding: TAtlasFinding): Boolean;
    property SelectedKey: string read FSelectedKey write FSelectedKey;
    /// <summary>-1 ohne Auswahl oder wenn der gewählte Befund nicht sichtbar ist.</summary>
    property SelectedRow: Integer read GetSelectedRow;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults;

const
  CategoryNames: array[TAtlasFindingCategory] of string = ('bug', 'vulnerability', 'code-smell',
    'security-hotspot', 'compiler', '');

{ TAtlasFinding }

function TAtlasFinding.Location: string;
begin
  Result := Format('%s:%d:%d', [ExtractFileName(FileName), Problem.StartLine + 1, Problem.StartCharacter + 1]);
end;

function TAtlasFinding.ShortLine(AMax: Integer): string;
begin
  Result := TAtlasFindings.Shorten(LineText, AMax);
end;

function TAtlasFinding.Rule: string;
begin
  Result := Problem.Code;
end;

function TAtlasFinding.CompilerText: string;
begin
  Result := Problem.CompilerCodeText;
  if Problem.Confirmed then
  begin
    Result := Result + ' ' + #$00B7 + ' ' + TAtlasFindings.ConfirmedMark;
  end;
end;

function TAtlasFinding.MessageText(AShowCompilerCode: Boolean): string;
begin
  Result := Problem.Message;
  if not AShowCompilerCode then
  begin
    Result := TAtlasProblem.WithoutCompilerCode(Result);
  end;
end;

{ TAtlasFindingColumnState }

class function TAtlasFindingColumnState.Create(AColumn: TAtlasFindingColumn; AWidth: Integer;
  AVisible: Boolean): TAtlasFindingColumnState;
begin
  Result.Column := AColumn;
  Result.Width := AWidth;
  Result.Visible := AVisible;
end;

{ TAtlasFindingCounts }

function TAtlasFindingCounts.Total: Integer;
begin
  Result := Errors + Warnings + Infos;
end;

function TAtlasFindingCounts.OfKind(AKind: TAtlasFindingKind): Integer;
begin
  case AKind of
    TAtlasFindingKind.Error:
      Result := Errors;
    TAtlasFindingKind.Warning:
      Result := Warnings;
  else
    Result := Infos;
  end;
end;

{ TAtlasFindingFilter }

class function TAtlasFindingFilter.Create: TAtlasFindingFilter;
begin
  Result := Default(TAtlasFindingFilter);
  Result.Scope := TAtlasFindingScope.Group;
  Result.Kinds := [TAtlasFindingKind.Error, TAtlasFindingKind.Warning, TAtlasFindingKind.Info];
end;

/// <summary>AFileName steht in AFiles (ohne Groß-/Kleinschreibung).</summary>
function InFiles(const AFiles: TArray<string>; const AFileName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in AFiles do
  begin
    if SameText(mName, AFileName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Meldung, Code oder Dateiname enthalten ANeedle (klein geschrieben).</summary>
function ContainsNeedle(const AFinding: TAtlasFinding; const ANeedle: string): Boolean;
begin
  Result := AFinding.Problem.Message.ToLower.Contains(ANeedle) or AFinding.Problem.Code.ToLower.Contains(ANeedle) or
    ExtractFileName(AFinding.FileName).ToLower.Contains(ANeedle);
end;

function TAtlasFindingFilter.MatchesExceptKind(const AFinding: TAtlasFinding): Boolean;
begin
  Result := Compiler or (AFinding.Category <> TAtlasFindingCategory.Compiler);
  Result := Result and (not OneCategory or (AFinding.Category = Category));
  if Scope = TAtlasFindingScope.CurrentFile then
  begin
    Result := Result and SameText(AFinding.FileName, CurrentFile);
  end
  else
  begin
    Result := Result and ((Files = nil) or InFiles(Files, AFinding.FileName));
  end;
  Result := Result and ((Text = '') or ContainsNeedle(AFinding, Text.ToLower));
end;

function TAtlasFindingFilter.Matches(const AFinding: TAtlasFinding): Boolean;
begin
  Result := (AFinding.Kind in Kinds) and MatchesExceptKind(AFinding);
end;

{ TAtlasFindings }

class function TAtlasFindings.KindOf(ASeverity: TAtlasProblemSeverity): TAtlasFindingKind;
begin
  case ASeverity of
    TAtlasProblemSeverity.Error:
      Result := TAtlasFindingKind.Error;
    TAtlasProblemSeverity.Warning:
      Result := TAtlasFindingKind.Warning;
  else
    Result := TAtlasFindingKind.Info;
  end;
end;

class function TAtlasFindings.CategoryOf(const AProblem: TAtlasProblem): TAtlasFindingCategory;
var
  Category: TAtlasFindingCategory;
begin
  if AProblem.IsCompiler then
  begin
    Exit(TAtlasFindingCategory.Compiler);
  end;
  for Category := Low(TAtlasFindingCategory) to Pred(TAtlasFindingCategory.Compiler) do
  begin
    if SameText(AProblem.Category, CategoryNames[Category]) then
    begin
      Exit(Category);
    end;
  end;
  Result := TAtlasFindingCategory.Other;
end;

class function TAtlasFindings.IsFinding(const AProblem: TAtlasProblem): Boolean;
begin
  Result := not AProblem.Unnecessary and not AProblem.IsUses and
    not SameText(AProblem.Source, TAtlasProblemStore.TestSource);
end;

class function TAtlasFindings.FromProblems(const AFileName: string; const AProblems: TArray<TAtlasProblem>;
  const ALines: TArray<string>): TArray<TAtlasFinding>;
var
  Problem: TAtlasProblem;
  Finding: TAtlasFinding;
  Seen: TDictionary<string, Integer>;
  Base: string;
  Number, Count: Integer;
begin
  SetLength(Result, Length(AProblems));
  Count := 0;
  Seen := TDictionary<string, Integer>.Create;
  try
    for Problem in AProblems do
    begin
      if not IsFinding(Problem) then
      begin
        Continue;
      end;
      Finding := Default(TAtlasFinding);
      Finding.FileName := AFileName;
      Finding.Problem := Problem;
      Finding.Kind := KindOf(Problem.Severity);
      Finding.Category := CategoryOf(Problem);
      if (Problem.StartLine >= 0) and (Problem.StartLine < Length(ALines)) then
      begin
        Finding.LineText := ALines[Problem.StartLine].Trim;
      end;
      Base := AnsiLowerCase(AFileName) + '|' + Problem.Source + '|' + Problem.Code + '|' + Problem.Message;
      if not Seen.TryGetValue(Base, Number) then
      begin
        Number := 0;
      end;
      Inc(Number);
      Seen.AddOrSetValue(Base, Number);
      Finding.Key := Base + '|' + IntToStr(Number);
      Result[Count] := Finding;
      Inc(Count);
    end;
  finally
    Seen.Free;
  end;
  SetLength(Result, Count);
end;

type
  /// <summary>Zeilen einer Datei von der Platte, höchstens einmal gelesen (Hänger mit vielen Befunden).</summary>
  TDiskLines = record
    FileName: string;
    ReadLines: TFunc<string, TArray<string>>;
    Lines: TArray<string>;
    Read: Boolean;
    function Line(AIndex: Integer): string;
  end;

function TDiskLines.Line(AIndex: Integer): string;
begin
  Result := '';
  if not Assigned(ReadLines) then
  begin
    Exit;
  end;
  if not Read then
  begin
    Lines := ReadLines(FileName);
    Read := True;
  end;
  if AIndex < Length(Lines) then
  begin
    Result := Lines[AIndex];
  end;
end;

function LastStartLine(const AProblems: TArray<TAtlasProblem>): Integer;
var
  mProblem: TAtlasProblem;
begin
  Result := -1;
  for mProblem in AProblems do
  begin
    Result := Max(Result, mProblem.StartLine);
  end;
end;

class function TAtlasFindings.FromStoreFile(AStore: TAtlasProblemStore; const AFileName: string;
  const AReadLines: TFunc<string, TArray<string>>): TArray<TAtlasFinding>;
var
  mText: string;
  mProblems: TArray<TAtlasProblem>;
  mLines: TArray<string>;
  mProblem: TAtlasProblem;
  mDisk: TDiskLines;
begin
  mProblems := AStore.ForFile(AFileName);
  Result := nil;
  if mProblems = nil then
  begin
    Exit;
  end;
  SetLength(mLines, LastStartLine(mProblems) + 1);
  // Die Platte höchstens einmal je Datei, nicht je Zeile.
  mDisk := Default(TDiskLines);
  mDisk.FileName := AFileName;
  mDisk.ReadLines := AReadLines;
  for mProblem in mProblems do
  begin
    if (mProblem.StartLine < 0) or (mLines[mProblem.StartLine] <> '') then
    begin
      Continue;
    end;
    if AStore.LineText(AFileName, mProblem.StartLine, mText) then
    begin
      mLines[mProblem.StartLine] := mText;
    end
    else
    begin
      mLines[mProblem.StartLine] := mDisk.Line(mProblem.StartLine);
    end;
  end;
  Result := FromProblems(AFileName, mProblems, mLines);
end;

class function TAtlasFindings.Concat(const AParts: TArray<TArray<TAtlasFinding>>): TArray<TAtlasFinding>;
var
  Part: TArray<TAtlasFinding>;
  Count, Index: Integer;
begin
  Count := 0;
  for Part in AParts do
  begin
    Inc(Count, Length(Part));
  end;
  SetLength(Result, Count);
  Count := 0;
  for Part in AParts do
  begin
    for Index := 0 to High(Part) do
    begin
      Result[Count] := Part[Index];
      Inc(Count);
    end;
  end;
end;

class function TAtlasFindings.FromStore(AStore: TAtlasProblemStore; const AFiles: TArray<string>;
  const AReadLines: TFunc<string, TArray<string>>): TArray<TAtlasFinding>;
var
  Files: TArray<string>;
  Parts: TArray<TArray<TAtlasFinding>>;
  Index: Integer;
begin
  Files := AFiles;
  if Files = nil then
  begin
    Files := AStore.Files;
  end;
  SetLength(Parts, Length(Files));
  for Index := 0 to High(Files) do
  begin
    Parts[Index] := FromStoreFile(AStore, Files[Index], AReadLines);
  end;
  Result := Concat(Parts);
end;

class function TAtlasFindings.Shorten(const AText: string; AMax: Integer): string;
begin
  Result := AText.Trim;
  if (AMax > 1) and (Length(Result) > AMax) then
  begin
    Result := Copy(Result, 1, AMax - 1).TrimRight + '…';
  end;
end;

class function TAtlasFindings.CheckedCount(AStore: TAtlasProblemStore; const AProjectFiles: TArray<string>): Integer;
var
  FileName: string;
begin
  Result := 0;
  for FileName in AProjectFiles do
  begin
    if AStore.Contains(FileName) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasFindings.IsMandatory(AColumn: TAtlasFindingColumn): Boolean;
begin
  Result := not (AColumn in [TAtlasFindingColumn.Message, TAtlasFindingColumn.Rule, TAtlasFindingColumn.Compiler]);
end;

/// <summary>Teil einer Spaltenliste („-rule:120“): Name, Breite (0 ohne) und ob ausgeblendet.</summary>
procedure SplitColumnPart(const APart: string; out AName: string; out AWidth: Integer; out AHidden: Boolean);
var
  mColon: Integer;
begin
  AName := APart.Trim;
  AHidden := AName.StartsWith('-');
  if AHidden then
  begin
    AName := AName.Substring(1).Trim;
  end;
  AWidth := 0;
  mColon := AName.IndexOf(':');
  if mColon >= 0 then
  begin
    AWidth := Max(0, StrToIntDef(AName.Substring(mColon + 1).Trim, 0));
    AName := AName.Substring(0, mColon).Trim;
  end;
end;

/// <summary>Spalte zum Namen; False bei unbekanntem Namen.</summary>
function ColumnByName(const AName: string; out AColumn: TAtlasFindingColumn): Boolean;
var
  mCandidate: TAtlasFindingColumn;
begin
  AColumn := TAtlasFindingColumn.Icon;
  for mCandidate := Low(TAtlasFindingColumn) to High(TAtlasFindingColumn) do
  begin
    if SameText(AName, TAtlasFindings.ColumnNames[mCandidate]) then
    begin
      AColumn := mCandidate;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasFindings.ParseColumns(const AText: string): TArray<TAtlasFindingColumnState>;
var
  mPart, mName: string;
  mColumn: TAtlasFindingColumn;
  mHidden: Boolean;
  mWidth: Integer;
  mTaken: set of TAtlasFindingColumn;
begin
  Result := nil;
  mTaken := [];
  for mPart in AText.Split([',']) do
  begin
    SplitColumnPart(mPart, mName, mWidth, mHidden);
    if ColumnByName(mName, mColumn) and not (mColumn in mTaken) then
    begin
      Include(mTaken, mColumn);
      Result := Result + [TAtlasFindingColumnState.Create(mColumn, mWidth, not mHidden or IsMandatory(mColumn))];
    end;
  end;
  for mColumn := Low(TAtlasFindingColumn) to High(TAtlasFindingColumn) do
  begin
    if not (mColumn in mTaken) then
    begin
      Result := Result + [TAtlasFindingColumnState.Create(mColumn, 0, True)];
    end;
  end;
end;

class function TAtlasFindings.FormatColumns(const AColumns: TArray<TAtlasFindingColumnState>): string;
var
  State: TAtlasFindingColumnState;
  Part: string;
begin
  Result := '';
  for State in AColumns do
  begin
    Part := ColumnNames[State.Column];
    if not State.Visible and not IsMandatory(State.Column) then
    begin
      Part := '-' + Part;
    end;
    if State.Width > 0 then
    begin
      Part := Part + ':' + IntToStr(State.Width);
    end;
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + Part;
  end;
end;

class function TAtlasFindings.TryParseScope(const AText: string; out AScope: TAtlasFindingScope): Boolean;
var
  Scope: TAtlasFindingScope;
begin
  for Scope := Low(TAtlasFindingScope) to High(TAtlasFindingScope) do
  begin
    if SameText(AText, ScopeNames[Scope]) then
    begin
      AScope := Scope;
      Exit(True);
    end;
  end;
  AScope := TAtlasFindingScope.Group;
  Result := False;
end;

class function TAtlasFindings.TryParseGrouping(const AText: string; out AGrouping: TAtlasFindingGrouping): Boolean;
var
  Grouping: TAtlasFindingGrouping;
begin
  for Grouping := Low(TAtlasFindingGrouping) to High(TAtlasFindingGrouping) do
  begin
    if SameText(AText, GroupingNames[Grouping]) then
    begin
      AGrouping := Grouping;
      Exit(True);
    end;
  end;
  AGrouping := TAtlasFindingGrouping.ByFile;
  Result := False;
end;

class function TAtlasFindings.UnitKey(const AFileName: string): string;
var
  Extension: string;
begin
  Result := AnsiLowerCase(AFileName);
  Extension := ExtractFileExt(Result);
  if (Extension = '.dfm') or (Extension = '.fmx') then
  begin
    Result := ChangeFileExt(Result, '.pas');
  end;
end;

class function TAtlasFindings.TryParseClosedUnits(const AText: string; out AValue: TAtlasClosedUnits): Boolean;
var
  Value: TAtlasClosedUnits;
begin
  for Value := Low(TAtlasClosedUnits) to High(TAtlasClosedUnits) do
  begin
    if SameText(AText, ClosedUnitsNames[Value]) then
    begin
      AValue := Value;
      Exit(True);
    end;
  end;
  AValue := TAtlasClosedUnits.Dimmed;
  Result := False;
end;

class function TAtlasFindings.AsText(const AFindings: TArray<TAtlasFinding>): string;
const
  KindWords: array[TAtlasFindingKind] of string = ('error', 'warning', 'info');
var
  Item: TAtlasFinding;
  Builder: TStringBuilder;
begin
  Builder := TStringBuilder.Create;
  try
    for Item in AFindings do
    begin
      Builder.Append(Item.Location).Append(': ').Append(KindWords[Item.Kind]);
      if Item.Rule <> '' then
      begin
        Builder.Append(' [').Append(Item.Rule).Append(']');
      end;
      Builder.Append(' ').Append(Item.Problem.Message).Append(#13#10);
      if Item.LineText <> '' then
      begin
        Builder.Append('    ').Append(Item.LineText).Append(#13#10);
      end;
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

{ TAtlasFindingsSource }

constructor TAtlasFindingsSource.Create;
begin
  inherited Create;
  FFilter := TAtlasFindingFilter.Create;
  FKnown := TDictionary<string, Boolean>.Create;
  FNew := TDictionary<string, Boolean>.Create;
  FOpenKeys := TDictionary<string, Boolean>.Create;
  // Aus, bis die IDE-Schicht die Einstellung setzt: so verhält sich das Modell ohne Stufen genau wie #909.
  FOpenFirst := False;
  FClosedUnits := TAtlasClosedUnits.Dimmed;
  FShowCleanActive := True;
end;

destructor TAtlasFindingsSource.Destroy;
begin
  FOpenKeys.Free;
  FNew.Free;
  FKnown.Free;
  inherited Destroy;
end;

procedure TAtlasFindingsSource.SetFindings(const AFindings: TArray<TAtlasFinding>);
var
  mFinding: TAtlasFinding;
begin
  FFindings := AFindings;
  FNew.Clear;
  if FFilled then
  begin
    for mFinding in AFindings do
    begin
      if not FKnown.ContainsKey(mFinding.Key) then
      begin
        FNew.AddOrSetValue(mFinding.Key, True);
      end;
    end;
  end;
  FKnown.Clear;
  for mFinding in AFindings do
  begin
    FKnown.AddOrSetValue(mFinding.Key, True);
  end;
  FFilled := True;
  AssignTiers;
  Rebuild;
end;

procedure TAtlasFindingsSource.SetOpenFiles(const AActive: string; const AOpen: TArray<string>;
  AActiveChecked: Boolean);
var
  mFileName: string;
begin
  FActiveFile := AActive;
  FActiveKey := '';
  if AActive <> '' then
  begin
    FActiveKey := TAtlasFindings.UnitKey(AActive);
  end;
  // Das Formular steht für seine Unit: Angezeigt wird die .pas.
  if FActiveKey <> AnsiLowerCase(AActive) then
  begin
    FActiveFile := ChangeFileExt(AActive, '.pas');
  end;
  FActiveChecked := AActiveChecked;
  FOpenKeys.Clear;
  for mFileName in AOpen do
  begin
    if mFileName <> '' then
    begin
      FOpenKeys.AddOrSetValue(TAtlasFindings.UnitKey(mFileName), True);
    end;
  end;
  AssignTiers;
  Rebuild;
end;

function TAtlasFindingsSource.TierOf(const AFileName: string): TAtlasFindingTier;
var
  mKey: string;
begin
  mKey := TAtlasFindings.UnitKey(AFileName);
  if (FActiveKey <> '') and (mKey = FActiveKey) then
  begin
    Result := TAtlasFindingTier.Active;
  end
  else if FOpenKeys.ContainsKey(mKey) then
  begin
    Result := TAtlasFindingTier.Open;
  end
  else
  begin
    Result := TAtlasFindingTier.Closed;
  end;
end;

procedure TAtlasFindingsSource.AssignTiers;
var
  mIndex: Integer;
  mLast: string;
  mTier: TAtlasFindingTier;
begin
  // Befunde einer Datei stehen hintereinander: die Stufe je Datei nur einmal bestimmen.
  mLast := '';
  mTier := TAtlasFindingTier.Closed;
  for mIndex := 0 to High(FFindings) do
  begin
    if (mIndex = 0) or (FFindings[mIndex].FileName <> mLast) then
    begin
      mLast := FFindings[mIndex].FileName;
      mTier := TierOf(mLast);
    end;
    FFindings[mIndex].Tier := mTier;
  end;
end;

function TAtlasFindingsSource.TiersActive: Boolean;
begin
  Result := FOpenFirst and (FFilter.Scope <> TAtlasFindingScope.CurrentFile);
end;

function TAtlasFindingsSource.HiddenByTier(const AFinding: TAtlasFinding): Boolean;
begin
  Result := TiersActive and (FClosedUnits = TAtlasClosedUnits.Hidden) and
    (AFinding.Tier = TAtlasFindingTier.Closed);
end;

procedure TAtlasFindingsSource.SetOpenFirst(AValue: Boolean);
begin
  FOpenFirst := AValue;
  Rebuild;
end;

procedure TAtlasFindingsSource.SetClosedUnits(AValue: TAtlasClosedUnits);
begin
  FClosedUnits := AValue;
  Rebuild;
end;

procedure TAtlasFindingsSource.SetShowCleanActive(AValue: Boolean);
begin
  FShowCleanActive := AValue;
  Rebuild;
end;

procedure TAtlasFindingsSource.ClearNew;
begin
  if FNew.Count = 0 then
  begin
    Exit;
  end;
  FNew.Clear;
  Rebuild;
end;

procedure TAtlasFindingsSource.SetFilter(const AValue: TAtlasFindingFilter);
begin
  FFilter := AValue;
  Rebuild;
end;

function TAtlasFindingsSource.IsActiveInScope: Boolean;
var
  mName: string;
begin
  if FActiveKey = '' then
  begin
    Exit(False);
  end;
  if (FFilter.Scope = TAtlasFindingScope.CurrentFile) or (FFilter.Files = nil) then
  begin
    Exit(True);
  end;
  for mName in FFilter.Files do
  begin
    if TAtlasFindings.UnitKey(mName) = FActiveKey then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasFindingsSource.Finding(AIndex: Integer): TAtlasFinding;
begin
  Result := FFindings[AIndex];
end;

{ TAtlasFindingsSorted }

constructor TAtlasFindingsSorted.Create;
begin
  inherited Create;
  FGrouping := TAtlasFindingGrouping.ByFile;
end;

procedure TAtlasFindingsSorted.SetGrouping(AValue: TAtlasFindingGrouping);
begin
  FGrouping := AValue;
  Rebuild;
end;

procedure TAtlasFindingsSorted.SortBy(AColumn: TAtlasFindingColumn);
begin
  if FSortCustom and (FSortColumn = AColumn) then
  begin
    FSortDescending := not FSortDescending;
  end
  else
  begin
    FSortCustom := True;
    FSortColumn := AColumn;
    FSortDescending := False;
  end;
  Rebuild;
end;

procedure TAtlasFindingsSorted.ResetSort;
begin
  FSortCustom := False;
  FSortDescending := False;
  Rebuild;
end;

function TAtlasFindingsSorted.GroupKeyOf(const AFinding: TAtlasFinding): string;
begin
  case FGrouping of
    TAtlasFindingGrouping.ByFile:
      Result := 'file:' + AnsiLowerCase(AFinding.FileName);
    TAtlasFindingGrouping.ByRule:
      Result := 'rule:' + AnsiLowerCase(AFinding.Problem.Code);
    TAtlasFindingGrouping.ByCategory:
      Result := 'category:' + IntToStr(Ord(AFinding.Category));
  else
    Result := '';
  end;
end;

function CompareDefault(const A, B: TAtlasFinding): Integer;
begin
  Result := Ord(A.Kind) - Ord(B.Kind);
  if Result = 0 then
  begin
    Result := CompareText(A.FileName, B.FileName);
  end;
  if Result = 0 then
  begin
    Result := A.Problem.StartLine - B.Problem.StartLine;
  end;
  if Result = 0 then
  begin
    Result := A.Problem.StartCharacter - B.Problem.StartCharacter;
  end;
  if Result = 0 then
  begin
    Result := CompareStr(A.Key, B.Key);
  end;
end;

function CompareLocation(const A, B: TAtlasFinding): Integer;
begin
  Result := CompareText(ExtractFileName(A.FileName), ExtractFileName(B.FileName));
  if Result = 0 then
  begin
    Result := A.Problem.StartLine - B.Problem.StartLine;
  end;
  if Result = 0 then
  begin
    Result := A.Problem.StartCharacter - B.Problem.StartCharacter;
  end;
end;

/// <summary>Vergleich nach der Spalte AColumn (aufsteigend).</summary>
function CompareColumn(AColumn: TAtlasFindingColumn; const A, B: TAtlasFinding): Integer;
begin
  case AColumn of
    TAtlasFindingColumn.Category:
      Result := Ord(A.Category) - Ord(B.Category);
    TAtlasFindingColumn.Message:
      Result := CompareText(A.Problem.Message, B.Problem.Message);
    TAtlasFindingColumn.Line:
      Result := CompareText(A.LineText, B.LineText);
    TAtlasFindingColumn.Location:
      Result := CompareLocation(A, B);
    TAtlasFindingColumn.Rule:
      Result := CompareText(A.Problem.Code, B.Problem.Code);
    TAtlasFindingColumn.Compiler:
      Result := CompareText(A.CompilerText, B.CompilerText);
  else
    // Symbol und Art.
    Result := Ord(A.Kind) - Ord(B.Kind);
  end;
end;

function TAtlasFindingsSorted.Compare(const A, B: TAtlasFinding): Integer;
begin
  // Offene Units zuerst (#1108): Die Stufe kommt vor jeder Spalte; ein Klick auf den Spaltenkopf sortiert nur
  // innerhalb der Stufe.
  Result := 0;
  if TiersActive then
  begin
    Result := Ord(A.Tier) - Ord(B.Tier);
  end;
  if (Result = 0) and FSortCustom then
  begin
    Result := CompareColumn(FSortColumn, A, B);
    if FSortDescending then
    begin
      Result := -Result;
    end;
  end;
  if Result = 0 then
  begin
    Result := CompareDefault(A, B);
  end;
end;

function TAtlasFindingsSorted.TiersByFile: Boolean;
begin
  Result := TiersActive and (FGrouping = TAtlasFindingGrouping.ByFile);
end;

function TAtlasFindingsSorted.CompareGroups(const AFirstA, AFirstB: TAtlasFinding;
  const AKeyA, AKeyB: string): Integer;
begin
  // Gruppen nach Datei, Regel bzw. Kategorie; innerhalb der Gruppe die gewählte Sortierung. Nach Datei mit
  // Offene-zuerst (#1108) kommt die Stufe vor dem Namen: aktive Unit, geöffnete und nicht geöffnete je
  // alphabetisch, damit beim Editorwechsel nur die angepinnte Gruppe springt.
  Result := 0;
  if TiersByFile then
  begin
    Result := Ord(AFirstA.Tier) - Ord(AFirstB.Tier);
  end;
  if Result = 0 then
  begin
    case FGrouping of
      TAtlasFindingGrouping.ByFile:
        Result := CompareText(ExtractFileName(AFirstA.FileName), ExtractFileName(AFirstB.FileName));
      TAtlasFindingGrouping.ByRule:
        Result := CompareText(AFirstA.Problem.Code, AFirstB.Problem.Code);
    else
      Result := Ord(AFirstA.Category) - Ord(AFirstB.Category);
    end;
  end;
  if Result = 0 then
  begin
    Result := CompareText(AKeyA, AKeyB);
  end;
end;

function TAtlasFindingsSorted.SortedMatches: TArray<Integer>;
var
  mIndex: Integer;
  mOrder: TList<Integer>;
begin
  mOrder := TList<Integer>.Create;
  try
    for mIndex := 0 to High(FFindings) do
    begin
      if FFilter.Matches(FFindings[mIndex]) and not HiddenByTier(FFindings[mIndex]) then
      begin
        mOrder.Add(mIndex);
      end;
    end;
    mOrder.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := Compare(FFindings[A], FFindings[B]);
      end));
    Result := mOrder.ToArray;
  finally
    mOrder.Free;
  end;
end;

/// <summary>AOrder je Stufe aufgeteilt, Reihenfolge bleibt.</summary>
function SplitByTier(const AFindings: TArray<TAtlasFinding>; const AOrder: TArray<Integer>):
  TAtlasFindingTierMembers;
var
  mCount: array[TAtlasFindingTier] of Integer;
  mTier: TAtlasFindingTier;
  mIndex: Integer;
begin
  for mTier := Low(TAtlasFindingTier) to High(TAtlasFindingTier) do
  begin
    mCount[mTier] := 0;
  end;
  for mIndex in AOrder do
  begin
    Inc(mCount[AFindings[mIndex].Tier]);
  end;
  for mTier := Low(TAtlasFindingTier) to High(TAtlasFindingTier) do
  begin
    SetLength(Result[mTier], mCount[mTier]);
    mCount[mTier] := 0;
  end;
  for mIndex in AOrder do
  begin
    mTier := AFindings[mIndex].Tier;
    Result[mTier][mCount[mTier]] := mIndex;
    Inc(mCount[mTier]);
  end;
end;

{ TAtlasFindingsView }

constructor TAtlasFindingsView.Create;
begin
  inherited Create;
  FCollapsed := TDictionary<string, Boolean>.Create;
end;

destructor TAtlasFindingsView.Destroy;
begin
  FCollapsed.Free;
  inherited Destroy;
end;

procedure TAtlasFindingsView.BeginUpdate;
begin
  Inc(FUpdateCount);
end;

procedure TAtlasFindingsView.EndUpdate;
begin
  if FUpdateCount = 0 then
  begin
    Exit;
  end;
  Dec(FUpdateCount);
  if (FUpdateCount = 0) and FRebuildPending then
  begin
    Rebuild;
  end;
end;

function TAtlasFindingsView.FindingRow(AIndex: Integer; const AGroupKey: string): TAtlasFindingRow;
begin
  Result := Default(TAtlasFindingRow);
  Result.GroupKey := AGroupKey;
  Result.Finding := AIndex;
  Result.IsNew := FNew.ContainsKey(FFindings[AIndex].Key);
  Result.Tier := FFindings[AIndex].Tier;
  if TiersActive then
  begin
    Result.Pinned := Result.Tier = TAtlasFindingTier.Active;
    Result.Dimmed := (Result.Tier = TAtlasFindingTier.Closed) and (FClosedUnits = TAtlasClosedUnits.Dimmed);
  end;
end;

function TAtlasFindingsView.SectionRow(ATier: TAtlasFindingTier; const AMembers: TArray<Integer>): TAtlasFindingRow;
var
  mIndex: Integer;
  mUnits: TDictionary<string, Boolean>;
begin
  Result := Default(TAtlasFindingRow);
  Result.IsSection := True;
  Result.Finding := -1;
  Result.Tier := ATier;
  Result.Pinned := ATier = TAtlasFindingTier.Active;
  Result.Dimmed := (ATier = TAtlasFindingTier.Closed) and (FClosedUnits = TAtlasClosedUnits.Dimmed);
  Result.Count := Length(AMembers);
  mUnits := TDictionary<string, Boolean>.Create;
  try
    for mIndex in AMembers do
    begin
      mUnits.AddOrSetValue(TAtlasFindings.UnitKey(FFindings[mIndex].FileName), True);
    end;
    Result.Units := mUnits.Count;
  finally
    mUnits.Free;
  end;
  if ATier = TAtlasFindingTier.Active then
  begin
    Result.Caption := ExtractFileName(FActiveFile);
  end;
end;

function TAtlasFindingsView.CleanActiveRow(out ARow: TAtlasFindingRow): Boolean;
begin
  ARow := Default(TAtlasFindingRow);
  Result := TiersActive and FShowCleanActive and IsActiveInScope;
  if not Result then
  begin
    Exit;
  end;
  ARow := SectionRow(TAtlasFindingTier.Active, nil);
  ARow.IsCleanActive := True;
  ARow.Checking := not FActiveChecked;
end;

function TAtlasFindingsView.GroupRow(const AKey: string; const AFirst: TAtlasFinding;
  ACount: Integer): TAtlasFindingRow;
var
  mCollapsed: Boolean;
begin
  Result := Default(TAtlasFindingRow);
  Result.IsGroup := True;
  Result.GroupKey := AKey;
  Result.Finding := -1;
  Result.Count := ACount;
  Result.Category := AFirst.Category;
  if TiersByFile then
  begin
    Result.Tier := AFirst.Tier;
    Result.Pinned := AFirst.Tier = TAtlasFindingTier.Active;
    Result.Dimmed := (AFirst.Tier = TAtlasFindingTier.Closed) and (FClosedUnits = TAtlasClosedUnits.Dimmed);
  end;
  case FGrouping of
    TAtlasFindingGrouping.ByFile:
      Result.Caption := ExtractFileName(AFirst.FileName);
    TAtlasFindingGrouping.ByRule:
      Result.Caption := AFirst.Problem.Code;
    TAtlasFindingGrouping.ByCategory:
      Result.Caption := CategoryNames[AFirst.Category];
    TAtlasFindingGrouping.None: ;
  end;
  if not FCollapsed.TryGetValue(AKey, mCollapsed) then
  begin
    mCollapsed := False;
  end;
  Result.Expanded := not mCollapsed;
end;

procedure TAtlasFindingsView.Rebuild;
var
  mOrder: TArray<Integer>;
  mOfTier: TAtlasFindingTierMembers;
  mRows: TList<TAtlasFindingRow>;
begin
  FCountsValid := False;
  if FUpdateCount > 0 then
  begin
    FRebuildPending := True;
    Exit;
  end;
  FRebuildPending := False;
  mOrder := SortedMatches;
  mOfTier := SplitByTier(FFindings, mOrder);
  // Zeilen über Listen statt Array + [x]: Mit zehntausenden Befunden wäre jeder Neuaufbau quadratisch.
  mRows := TList<TAtlasFindingRow>.Create;
  try
    if FGrouping = TAtlasFindingGrouping.None then
    begin
      RebuildFlat(mOrder, mOfTier, mRows);
    end
    else
    begin
      RebuildGrouped(mOrder, mOfTier, mRows);
    end;
    FRows := mRows.ToArray;
  finally
    mRows.Free;
  end;
  // Zugeklappte Gruppen, die gerade keine Befunde haben, bleiben gemerkt: Kommen ihre Befunde wieder, bleiben sie
  // zugeklappt.
end;

procedure TAtlasFindingsView.RebuildFlat(const AOrder: TArray<Integer>; const AOfTier: TAtlasFindingTierMembers;
  ARows: TList<TAtlasFindingRow>);
var
  mIndex: Integer;
  mTier: TAtlasFindingTier;
  mStarted: set of TAtlasFindingTier;
  mRow: TAtlasFindingRow;
  mTiers: Boolean;
begin
  FVisible := AOrder;
  mTiers := TiersActive;
  mStarted := [];
  if mTiers and (Length(AOfTier[TAtlasFindingTier.Active]) = 0) and CleanActiveRow(mRow) then
  begin
    ARows.Add(mRow);
  end;
  for mIndex in FVisible do
  begin
    mTier := FFindings[mIndex].Tier;
    if mTiers and not (mTier in mStarted) then
    begin
      Include(mStarted, mTier);
      ARows.Add(SectionRow(mTier, AOfTier[mTier]));
    end;
    ARows.Add(FindingRow(mIndex, ''));
  end;
end;

/// <summary>Gruppenschlüssel in der Reihenfolge des ersten Auftretens und ihre Befunde.</summary>
procedure CollectGroups(const AKeys: TArray<string>; const AOrder: TArray<Integer>; AGroups: TList<string>;
  AMembers: TObjectDictionary<string, TList<Integer>>);
var
  mIndex: Integer;
  mList: TList<Integer>;
begin
  for mIndex := 0 to High(AOrder) do
  begin
    if not AMembers.TryGetValue(AKeys[mIndex], mList) then
    begin
      AGroups.Add(AKeys[mIndex]);
      mList := TList<Integer>.Create;
      AMembers.Add(AKeys[mIndex], mList);
    end;
    mList.Add(AOrder[mIndex]);
  end;
end;

procedure TAtlasFindingsView.RebuildGrouped(const AOrder: TArray<Integer>; const AOfTier: TAtlasFindingTierMembers;
  ARows: TList<TAtlasFindingRow>);
var
  mKeys: TArray<string>;
  mIndex, mMember: Integer;
  mGroups: TList<string>;
  mMembers: TObjectDictionary<string, TList<Integer>>;
  mKey: string;
  mRow: TAtlasFindingRow;
  mFirst: TAtlasFinding;
  mStarted: set of TAtlasFindingTier;
  mVisible: TList<Integer>;
begin
  SetLength(mKeys, Length(AOrder));
  for mIndex := 0 to High(AOrder) do
  begin
    mKeys[mIndex] := GroupKeyOf(FFindings[AOrder[mIndex]]);
  end;
  mStarted := [];
  mVisible := TList<Integer>.Create;
  mGroups := TList<string>.Create;
  mMembers := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  try
    CollectGroups(mKeys, AOrder, mGroups, mMembers);
    mGroups.Sort(TComparer<string>.Construct(
      function(const A, B: string): Integer
      begin
        Result := CompareGroups(FFindings[mMembers[A][0]], FFindings[mMembers[B][0]], A, B);
      end));
    if TiersByFile and (Length(AOfTier[TAtlasFindingTier.Active]) = 0) and CleanActiveRow(mRow) then
    begin
      ARows.Add(mRow);
    end;
    for mKey in mGroups do
    begin
      mFirst := FFindings[mMembers[mKey][0]];
      // Trennzeilen „Geöffnet“ und „Nicht geöffnet“ nur nach Datei.
      if TiersByFile and (mFirst.Tier <> TAtlasFindingTier.Active) and not (mFirst.Tier in mStarted) then
      begin
        Include(mStarted, mFirst.Tier);
        ARows.Add(SectionRow(mFirst.Tier, AOfTier[mFirst.Tier]));
      end;
      mRow := GroupRow(mKey, mFirst, mMembers[mKey].Count);
      ARows.Add(mRow);
      for mMember in mMembers[mKey] do
      begin
        mVisible.Add(mMember);
        if mRow.Expanded then
        begin
          ARows.Add(FindingRow(mMember, mKey));
        end;
      end;
    end;
    FVisible := mVisible.ToArray;
  finally
    mMembers.Free;
    mGroups.Free;
    mVisible.Free;
  end;
end;

function TAtlasFindingsView.Rows: TArray<TAtlasFindingRow>;
begin
  Result := FRows;
end;

function TAtlasFindingsView.Visible: TArray<TAtlasFinding>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(FVisible));
  for mIndex := 0 to High(FVisible) do
  begin
    Result[mIndex] := FFindings[FVisible[mIndex]];
  end;
end;

type
  /// <summary>Units und Dateien, die Counts zählt.</summary>
  TCountUnits = record
    Files: TDictionary<string, Boolean>;
    Open: TDictionary<string, Boolean>;
    Closed: TDictionary<string, Boolean>;
    Hidden: TDictionary<string, Boolean>;
    procedure Init;
    procedure Done;
  end;

procedure TCountUnits.Init;
begin
  Files := TDictionary<string, Boolean>.Create;
  Open := TDictionary<string, Boolean>.Create;
  Closed := TDictionary<string, Boolean>.Create;
  Hidden := TDictionary<string, Boolean>.Create;
end;

procedure TCountUnits.Done;
begin
  Hidden.Free;
  Closed.Free;
  Open.Free;
  Files.Free;
end;

procedure CountKind(AKind: TAtlasFindingKind; var ACounts: TAtlasFindingCounts);
begin
  case AKind of
    TAtlasFindingKind.Error:
      Inc(ACounts.Errors);
    TAtlasFindingKind.Warning:
      Inc(ACounts.Warnings);
  else
    Inc(ACounts.Infos);
  end;
end;

/// <summary>Einen Befund unter dem Filter ohne die Arten zählen; AInKinds = seine Art ist im Filter.</summary>
procedure CountFinding(const AFinding: TAtlasFinding; AHidden, ATiers, AInKinds: Boolean;
  var ACounts: TAtlasFindingCounts; const AUnits: TCountUnits);
begin
  // Ausgegraut ist reine Darstellung und zählt mit; ausgeblendet zählt nicht (#1108).
  if AHidden then
  begin
    if AInKinds then
    begin
      AUnits.Hidden.AddOrSetValue(TAtlasFindings.UnitKey(AFinding.FileName), True);
    end;
    Exit;
  end;
  if ATiers and AInKinds and (AFinding.Tier = TAtlasFindingTier.Closed) then
  begin
    AUnits.Closed.AddOrSetValue(TAtlasFindings.UnitKey(AFinding.FileName), True);
    Inc(ACounts.ClosedFindings);
  end
  else if ATiers and AInKinds then
  begin
    AUnits.Open.AddOrSetValue(TAtlasFindings.UnitKey(AFinding.FileName), True);
    Inc(ACounts.OpenFindings);
  end;
  CountKind(AFinding.Kind, ACounts);
  if AInKinds then
  begin
    AUnits.Files.AddOrSetValue(AnsiLowerCase(AFinding.FileName), True);
  end;
end;

function TAtlasFindingsView.Counts: TAtlasFindingCounts;
var
  mFinding: TAtlasFinding;
  mUnits: TCountUnits;
  mTiers: Boolean;
begin
  if FCountsValid then
  begin
    Exit(FCounts);
  end;
  Result := Default(TAtlasFindingCounts);
  mTiers := TiersActive;
  mUnits.Init;
  try
    for mFinding in FFindings do
    begin
      if FFilter.MatchesExceptKind(mFinding) then
      begin
        CountFinding(mFinding, HiddenByTier(mFinding), mTiers, mFinding.Kind in FFilter.Kinds, Result, mUnits);
      end;
    end;
    Result.Files := mUnits.Files.Count;
    Result.OpenUnits := mUnits.Open.Count;
    Result.ClosedUnits := mUnits.Closed.Count;
    Result.HiddenUnits := mUnits.Hidden.Count;
    FCounts := Result;
    FCountsValid := True;
  finally
    mUnits.Done;
  end;
end;

procedure TAtlasFindingsView.SetExpanded(const AGroupKey: string; AExpanded: Boolean);
begin
  if AExpanded then
  begin
    FCollapsed.Remove(AGroupKey);
  end
  else
  begin
    FCollapsed.AddOrSetValue(AGroupKey, True);
  end;
  Rebuild;
end;

procedure TAtlasFindingsView.Toggle(ARow: Integer);
begin
  if (ARow < 0) or (ARow > High(FRows)) or not FRows[ARow].IsGroup then
  begin
    Exit;
  end;
  SetExpanded(FRows[ARow].GroupKey, not FRows[ARow].Expanded);
end;

procedure TAtlasFindingsView.Select(ARow: Integer);
begin
  if (ARow < 0) or (ARow > High(FRows)) then
  begin
    FSelectedKey := '';
  end
  else if FRows[ARow].IsSection then
  begin
    // Trennzeilen sind nicht wählbar: Die Auswahl bleibt, wo sie war.
    Exit;
  end
  else if FRows[ARow].IsGroup then
  begin
    FSelectedKey := 'group:' + FRows[ARow].GroupKey;
  end
  else
  begin
    FSelectedKey := FFindings[FRows[ARow].Finding].Key;
  end;
end;

function TAtlasFindingsView.GetSelectedRow: Integer;
var
  Index: Integer;
begin
  Result := -1;
  if FSelectedKey = '' then
  begin
    Exit;
  end;
  for Index := 0 to High(FRows) do
  begin
    if FRows[Index].IsSection then
    begin
      Continue;
    end
    else if FRows[Index].IsGroup then
    begin
      if FSelectedKey = 'group:' + FRows[Index].GroupKey then
      begin
        Exit(Index);
      end;
    end
    else if FFindings[FRows[Index].Finding].Key = FSelectedKey then
    begin
      Exit(Index);
    end;
  end;
end;

function TAtlasFindingsView.SelectedFinding(out AFinding: TAtlasFinding): Boolean;
var
  Row: Integer;
begin
  AFinding := Default(TAtlasFinding);
  Row := GetSelectedRow;
  Result := (Row >= 0) and not FRows[Row].IsGroup and not FRows[Row].IsSection;
  if Result then
  begin
    AFinding := FFindings[FRows[Row].Finding];
  end;
end;

function TAtlasFindingsView.SelectAt(const AFileName: string; ALine: Integer): Boolean;
var
  Index: Integer;
  Finding: TAtlasFinding;
  Key: string;
begin
  for Index in FVisible do
  begin
    Finding := FFindings[Index];
    if SameText(Finding.FileName, AFileName) and (ALine >= Finding.Problem.StartLine) and
      (ALine <= Max(Finding.Problem.StartLine, Finding.Problem.EndLine)) then
    begin
      FSelectedKey := Finding.Key;
      Key := GroupKeyOf(Finding);
      if (Key <> '') and FCollapsed.ContainsKey(Key) then
      begin
        SetExpanded(Key, True);
      end;
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasFindingsView.Step(AForward: Boolean; out AFinding: TAtlasFinding): Boolean;
var
  Current, Index, Target: Integer;
  Key: string;
begin
  AFinding := Default(TAtlasFinding);
  if Length(FVisible) = 0 then
  begin
    Exit(False);
  end;
  Current := -1;
  for Index := 0 to High(FVisible) do
  begin
    if FFindings[FVisible[Index]].Key = FSelectedKey then
    begin
      Current := Index;
    end;
  end;
  if Current < 0 then
  begin
    if AForward then
    begin
      Target := 0;
    end
    else
    begin
      Target := High(FVisible);
    end;
  end
  else if AForward then
  begin
    Target := (Current + 1) mod Length(FVisible);
  end
  else
  begin
    Target := (Current - 1 + Length(FVisible)) mod Length(FVisible);
  end;
  AFinding := FFindings[FVisible[Target]];
  FSelectedKey := AFinding.Key;
  Key := GroupKeyOf(AFinding);
  if (Key <> '') and FCollapsed.ContainsKey(Key) then
  begin
    SetExpanded(Key, True);
  end;
  Result := True;
end;

function TAtlasFindingsView.GroupMembers(const AGroupKey: string): TArray<Integer>;
var
  mIndex: Integer;
  mList: TList<Integer>;
begin
  mList := TList<Integer>.Create;
  try
    for mIndex in FVisible do
    begin
      if GroupKeyOf(FFindings[mIndex]) = AGroupKey then
      begin
        mList.Add(mIndex);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function TAtlasFindingsView.FindingsOfRows(const ARows: TArray<Integer>): TArray<TAtlasFinding>;
var
  mRow, mIndex: Integer;
  mMembers: TArray<Integer>;
  mDone: TDictionary<Integer, Boolean>;
  mList: TList<TAtlasFinding>;
begin
  mDone := TDictionary<Integer, Boolean>.Create;
  mList := TList<TAtlasFinding>.Create;
  try
    for mRow in ARows do
    begin
      if (mRow < 0) or (mRow > High(FRows)) or FRows[mRow].IsSection then
      begin
        Continue;
      end;
      if FRows[mRow].IsGroup then
      begin
        mMembers := GroupMembers(FRows[mRow].GroupKey);
      end
      else
      begin
        mMembers := TArray<Integer>.Create(FRows[mRow].Finding);
      end;
      for mIndex in mMembers do
      begin
        if not mDone.ContainsKey(mIndex) then
        begin
          mDone.Add(mIndex, True);
          mList.Add(FFindings[mIndex]);
        end;
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
    mDone.Free;
  end;
end;

end.
