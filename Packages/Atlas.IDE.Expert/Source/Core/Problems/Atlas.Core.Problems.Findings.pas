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
    /// des Speichers, sonst über AReadLine (nil = ohne).</summary>
    class function FromStore(AStore: TAtlasProblemStore; const AFiles: TArray<string>;
      const AReadLine: TFunc<string, Integer, string>): TArray<TAtlasFinding>; static;
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

  TAtlasFindingsView = class
  private
    FFindings: TArray<TAtlasFinding>;
    FFilter: TAtlasFindingFilter;
    FGrouping: TAtlasFindingGrouping;
    FSortColumn: TAtlasFindingColumn;
    FSortDescending: Boolean;
    FSortCustom: Boolean;
    FCollapsed: TDictionary<string, Boolean>;
    FKnown: TDictionary<string, Boolean>;
    FNew: TDictionary<string, Boolean>;
    FFilled: Boolean;
    FVisible: TArray<Integer>;
    FRows: TArray<TAtlasFindingRow>;
    FSelectedKey: string;
    FOpenFirst: Boolean;
    FClosedUnits: TAtlasClosedUnits;
    FShowCleanActive: Boolean;
    FActiveFile: string;
    FActiveKey: string;
    FActiveChecked: Boolean;
    FOpenKeys: TDictionary<string, Boolean>;
    procedure Rebuild;
    procedure SetFilter(const AValue: TAtlasFindingFilter);
    procedure SetGrouping(AValue: TAtlasFindingGrouping);
    procedure SetOpenFirst(AValue: Boolean);
    procedure SetClosedUnits(AValue: TAtlasClosedUnits);
    procedure SetShowCleanActive(AValue: Boolean);
    function GroupKeyOf(const AFinding: TAtlasFinding): string;
    function Compare(const A, B: TAtlasFinding): Integer;
    function GetSelectedRow: Integer;
    function TierOf(const AFileName: string): TAtlasFindingTier;
    procedure AssignTiers;
    /// <summary>Wird AFinding wegen problems.window.closedUnits = hidden ausgeblendet?</summary>
    function HiddenByTier(const AFinding: TAtlasFinding): Boolean;
    /// <summary>Zeile für AFinding mit Stufe, Nadel und Grau.</summary>
    function FindingRow(AIndex: Integer; const AGroupKey: string): TAtlasFindingRow;
    /// <summary>Trennzeile der Stufe ATier über die Befunde AMembers.</summary>
    function SectionRow(ATier: TAtlasFindingTier; const AMembers: TArray<Integer>): TAtlasFindingRow;
    /// <summary>Zeile „Keine Befunde“ der aktiven Unit, wenn sie gezeigt werden soll.</summary>
    function CleanActiveRow(out ARow: TAtlasFindingRow): Boolean;
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
    /// <summary>Klick auf den Spaltenkopf: nach AColumn sortieren, beim zweiten Klick absteigend.</summary>
    procedure SortBy(AColumn: TAtlasFindingColumn);
    /// <summary>Zurück zur Vorgabe: Art, Datei, Zeile.</summary>
    procedure ResetSort;
    function Rows: TArray<TAtlasFindingRow>;
    function Finding(AIndex: Integer): TAtlasFinding;
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
    property Filter: TAtlasFindingFilter read FFilter write SetFilter;
    property Grouping: TAtlasFindingGrouping read FGrouping write SetGrouping;
    property SortColumn: TAtlasFindingColumn read FSortColumn;
    property SortDescending: Boolean read FSortDescending;
    property SortCustom: Boolean read FSortCustom;
    property SelectedKey: string read FSelectedKey write FSelectedKey;
    /// <summary>problems.window.openFirst; im Modell Vorgabe aus, die Einstellung hat Vorgabe an.</summary>
    property OpenFirst: Boolean read FOpenFirst write SetOpenFirst;
    /// <summary>problems.window.closedUnits (Vorgabe ausgegraut).</summary>
    property ClosedUnits: TAtlasClosedUnits read FClosedUnits write SetClosedUnits;
    /// <summary>problems.window.showCleanActive (Vorgabe an).</summary>
    property ShowCleanActive: Boolean read FShowCleanActive write SetShowCleanActive;
    property ActiveFile: string read FActiveFile;
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
    Result := Result + ' ' + #$00B7 + ' ' + TAtlasFindings.ConfirmedMark;
end;

function TAtlasFinding.MessageText(AShowCompilerCode: Boolean): string;
begin
  Result := Problem.Message;
  if not AShowCompilerCode then
    Result := TAtlasProblem.WithoutCompilerCode(Result);
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

function TAtlasFindingFilter.MatchesExceptKind(const AFinding: TAtlasFinding): Boolean;
var
  Needle: string;
  Found: Boolean;
  Name: string;
begin
  if (AFinding.Category = TAtlasFindingCategory.Compiler) and not Compiler then
    Exit(False);
  if OneCategory and (AFinding.Category <> Category) then
    Exit(False);
  case Scope of
    TAtlasFindingScope.CurrentFile:
      if not SameText(AFinding.FileName, CurrentFile) then
        Exit(False);
  else
    if Files <> nil then
    begin
      Found := False;
      for Name in Files do
        if SameText(Name, AFinding.FileName) then
        begin
          Found := True;
          Break;
        end;
      if not Found then
        Exit(False);
    end;
  end;
  if Text <> '' then
  begin
    Needle := Text.ToLower;
    if not AFinding.Problem.Message.ToLower.Contains(Needle) and not AFinding.Problem.Code.ToLower.Contains(Needle)
      and not ExtractFileName(AFinding.FileName).ToLower.Contains(Needle) then
      Exit(False);
  end;
  Result := True;
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
    Exit(TAtlasFindingCategory.Compiler);
  for Category := Low(TAtlasFindingCategory) to Pred(TAtlasFindingCategory.Compiler) do
    if SameText(AProblem.Category, CategoryNames[Category]) then
      Exit(Category);
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
  Number: Integer;
begin
  Result := nil;
  Seen := TDictionary<string, Integer>.Create;
  try
    for Problem in AProblems do
    begin
      if not IsFinding(Problem) then
        Continue;
      Finding := Default(TAtlasFinding);
      Finding.FileName := AFileName;
      Finding.Problem := Problem;
      Finding.Kind := KindOf(Problem.Severity);
      Finding.Category := CategoryOf(Problem);
      if (Problem.StartLine >= 0) and (Problem.StartLine < Length(ALines)) then
        Finding.LineText := ALines[Problem.StartLine].Trim;
      Base := AnsiLowerCase(AFileName) + '|' + Problem.Source + '|' + Problem.Code + '|' + Problem.Message;
      if not Seen.TryGetValue(Base, Number) then
        Number := 0;
      Inc(Number);
      Seen.AddOrSetValue(Base, Number);
      Finding.Key := Base + '|' + IntToStr(Number);
      Result := Result + [Finding];
    end;
  finally
    Seen.Free;
  end;
end;

class function TAtlasFindings.FromStore(AStore: TAtlasProblemStore; const AFiles: TArray<string>;
  const AReadLine: TFunc<string, Integer, string>): TArray<TAtlasFinding>;
var
  Files: TArray<string>;
  FileName, Text: string;
  Problems: TArray<TAtlasProblem>;
  Lines: TArray<string>;
  Problem: TAtlasProblem;
  Last: Integer;
begin
  Result := nil;
  Files := AFiles;
  if Files = nil then
    Files := AStore.Files;
  for FileName in Files do
  begin
    Problems := AStore.ForFile(FileName);
    if Problems = nil then
      Continue;
    Last := -1;
    for Problem in Problems do
      Last := Max(Last, Problem.StartLine);
    SetLength(Lines, Last + 1);
    for Problem in Problems do
      if (Problem.StartLine >= 0) and (Lines[Problem.StartLine] = '') then
      begin
        if AStore.LineText(FileName, Problem.StartLine, Text) then
          Lines[Problem.StartLine] := Text
        else if Assigned(AReadLine) then
          Lines[Problem.StartLine] := AReadLine(FileName, Problem.StartLine);
      end;
    Result := Result + FromProblems(FileName, Problems, Lines);
    Lines := nil;
  end;
end;

class function TAtlasFindings.Shorten(const AText: string; AMax: Integer): string;
begin
  Result := AText.Trim;
  if (AMax > 1) and (Length(Result) > AMax) then
    Result := Copy(Result, 1, AMax - 1).TrimRight + '…';
end;

class function TAtlasFindings.CheckedCount(AStore: TAtlasProblemStore; const AProjectFiles: TArray<string>): Integer;
var
  FileName: string;
begin
  Result := 0;
  for FileName in AProjectFiles do
    if AStore.Contains(FileName) then
      Inc(Result);
end;

class function TAtlasFindings.IsMandatory(AColumn: TAtlasFindingColumn): Boolean;
begin
  Result := not (AColumn in [TAtlasFindingColumn.Message, TAtlasFindingColumn.Rule, TAtlasFindingColumn.Compiler]);
end;

class function TAtlasFindings.ParseColumns(const AText: string): TArray<TAtlasFindingColumnState>;
var
  Part, Name: string;
  Column, Candidate: TAtlasFindingColumn;
  Known, Hidden: Boolean;
  Width, Colon: Integer;
  Taken: set of TAtlasFindingColumn;
begin
  Result := nil;
  Taken := [];
  for Part in AText.Split([',']) do
  begin
    Name := Part.Trim;
    Hidden := Name.StartsWith('-');
    if Hidden then
      Name := Name.Substring(1).Trim;
    Width := 0;
    Colon := Name.IndexOf(':');
    if Colon >= 0 then
    begin
      Width := Max(0, StrToIntDef(Name.Substring(Colon + 1).Trim, 0));
      Name := Name.Substring(0, Colon).Trim;
    end;
    Known := False;
    Column := TAtlasFindingColumn.Icon;
    for Candidate := Low(TAtlasFindingColumn) to High(TAtlasFindingColumn) do
      if SameText(Name, ColumnNames[Candidate]) then
      begin
        Column := Candidate;
        Known := True;
      end;
    if not Known or (Column in Taken) then
      Continue;
    Include(Taken, Column);
    Result := Result + [TAtlasFindingColumnState.Create(Column, Width, not Hidden or IsMandatory(Column))];
  end;
  for Column := Low(TAtlasFindingColumn) to High(TAtlasFindingColumn) do
    if not (Column in Taken) then
      Result := Result + [TAtlasFindingColumnState.Create(Column, 0, True)];
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
      Part := '-' + Part;
    if State.Width > 0 then
      Part := Part + ':' + IntToStr(State.Width);
    if Result <> '' then
      Result := Result + ',';
    Result := Result + Part;
  end;
end;

class function TAtlasFindings.TryParseScope(const AText: string; out AScope: TAtlasFindingScope): Boolean;
var
  Scope: TAtlasFindingScope;
begin
  for Scope := Low(TAtlasFindingScope) to High(TAtlasFindingScope) do
    if SameText(AText, ScopeNames[Scope]) then
    begin
      AScope := Scope;
      Exit(True);
    end;
  AScope := TAtlasFindingScope.Group;
  Result := False;
end;

class function TAtlasFindings.TryParseGrouping(const AText: string; out AGrouping: TAtlasFindingGrouping): Boolean;
var
  Grouping: TAtlasFindingGrouping;
begin
  for Grouping := Low(TAtlasFindingGrouping) to High(TAtlasFindingGrouping) do
    if SameText(AText, GroupingNames[Grouping]) then
    begin
      AGrouping := Grouping;
      Exit(True);
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
    Result := ChangeFileExt(Result, '.pas');
end;

class function TAtlasFindings.TryParseClosedUnits(const AText: string; out AValue: TAtlasClosedUnits): Boolean;
var
  Value: TAtlasClosedUnits;
begin
  for Value := Low(TAtlasClosedUnits) to High(TAtlasClosedUnits) do
    if SameText(AText, ClosedUnitsNames[Value]) then
    begin
      AValue := Value;
      Exit(True);
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
        Builder.Append(' [').Append(Item.Rule).Append(']');
      Builder.Append(' ').Append(Item.Problem.Message).Append(#13#10);
      if Item.LineText <> '' then
        Builder.Append('    ').Append(Item.LineText).Append(#13#10);
    end;
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

{ TAtlasFindingsView }

constructor TAtlasFindingsView.Create;
begin
  inherited Create;
  FFilter := TAtlasFindingFilter.Create;
  FGrouping := TAtlasFindingGrouping.ByFile;
  FCollapsed := TDictionary<string, Boolean>.Create;
  FKnown := TDictionary<string, Boolean>.Create;
  FNew := TDictionary<string, Boolean>.Create;
  FOpenKeys := TDictionary<string, Boolean>.Create;
  // Aus, bis die IDE-Schicht die Einstellung setzt: so verhält sich das Modell ohne Stufen genau wie #909.
  FOpenFirst := False;
  FClosedUnits := TAtlasClosedUnits.Dimmed;
  FShowCleanActive := True;
end;

destructor TAtlasFindingsView.Destroy;
begin
  FOpenKeys.Free;
  FNew.Free;
  FKnown.Free;
  FCollapsed.Free;
  inherited;
end;

procedure TAtlasFindingsView.SetFindings(const AFindings: TArray<TAtlasFinding>);
var
  Finding: TAtlasFinding;
begin
  FFindings := AFindings;
  FNew.Clear;
  if FFilled then
    for Finding in AFindings do
      if not FKnown.ContainsKey(Finding.Key) then
        FNew.AddOrSetValue(Finding.Key, True);
  FKnown.Clear;
  for Finding in AFindings do
    FKnown.AddOrSetValue(Finding.Key, True);
  FFilled := True;
  AssignTiers;
  Rebuild;
end;

procedure TAtlasFindingsView.SetOpenFiles(const AActive: string; const AOpen: TArray<string>;
  AActiveChecked: Boolean);
var
  FileName: string;
begin
  FActiveFile := AActive;
  FActiveKey := '';
  if AActive <> '' then
    FActiveKey := TAtlasFindings.UnitKey(AActive);
  // Das Formular steht für seine Unit: Angezeigt wird die .pas.
  if FActiveKey <> AnsiLowerCase(AActive) then
    FActiveFile := ChangeFileExt(AActive, '.pas');
  FActiveChecked := AActiveChecked;
  FOpenKeys.Clear;
  for FileName in AOpen do
    if FileName <> '' then
      FOpenKeys.AddOrSetValue(TAtlasFindings.UnitKey(FileName), True);
  AssignTiers;
  Rebuild;
end;

function TAtlasFindingsView.TierOf(const AFileName: string): TAtlasFindingTier;
var
  Key: string;
begin
  Key := TAtlasFindings.UnitKey(AFileName);
  if (FActiveKey <> '') and (Key = FActiveKey) then
    Result := TAtlasFindingTier.Active
  else if FOpenKeys.ContainsKey(Key) then
    Result := TAtlasFindingTier.Open
  else
    Result := TAtlasFindingTier.Closed;
end;

procedure TAtlasFindingsView.AssignTiers;
var
  Index: Integer;
begin
  for Index := 0 to High(FFindings) do
    FFindings[Index].Tier := TierOf(FFindings[Index].FileName);
end;

function TAtlasFindingsView.TiersActive: Boolean;
begin
  Result := FOpenFirst and (FFilter.Scope <> TAtlasFindingScope.CurrentFile);
end;

function TAtlasFindingsView.HiddenByTier(const AFinding: TAtlasFinding): Boolean;
begin
  Result := TiersActive and (FClosedUnits = TAtlasClosedUnits.Hidden) and
    (AFinding.Tier = TAtlasFindingTier.Closed);
end;

procedure TAtlasFindingsView.SetOpenFirst(AValue: Boolean);
begin
  FOpenFirst := AValue;
  Rebuild;
end;

procedure TAtlasFindingsView.SetClosedUnits(AValue: TAtlasClosedUnits);
begin
  FClosedUnits := AValue;
  Rebuild;
end;

procedure TAtlasFindingsView.SetShowCleanActive(AValue: Boolean);
begin
  FShowCleanActive := AValue;
  Rebuild;
end;

procedure TAtlasFindingsView.ClearNew;
begin
  if FNew.Count = 0 then
    Exit;
  FNew.Clear;
  Rebuild;
end;

procedure TAtlasFindingsView.SetFilter(const AValue: TAtlasFindingFilter);
begin
  FFilter := AValue;
  Rebuild;
end;

procedure TAtlasFindingsView.SetGrouping(AValue: TAtlasFindingGrouping);
begin
  FGrouping := AValue;
  Rebuild;
end;

procedure TAtlasFindingsView.SortBy(AColumn: TAtlasFindingColumn);
begin
  if FSortCustom and (FSortColumn = AColumn) then
    FSortDescending := not FSortDescending
  else
  begin
    FSortCustom := True;
    FSortColumn := AColumn;
    FSortDescending := False;
  end;
  Rebuild;
end;

procedure TAtlasFindingsView.ResetSort;
begin
  FSortCustom := False;
  FSortDescending := False;
  Rebuild;
end;

function TAtlasFindingsView.GroupKeyOf(const AFinding: TAtlasFinding): string;
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
    Result := CompareText(A.FileName, B.FileName);
  if Result = 0 then
    Result := A.Problem.StartLine - B.Problem.StartLine;
  if Result = 0 then
    Result := A.Problem.StartCharacter - B.Problem.StartCharacter;
  if Result = 0 then
    Result := CompareStr(A.Key, B.Key);
end;

function TAtlasFindingsView.Compare(const A, B: TAtlasFinding): Integer;
begin
  // Offene Units zuerst (#1108): Die Stufe kommt vor jeder Spalte; ein Klick auf den Spaltenkopf sortiert nur
  // innerhalb der Stufe.
  if TiersActive then
  begin
    Result := Ord(A.Tier) - Ord(B.Tier);
    if Result <> 0 then
      Exit;
  end;
  Result := 0;
  if FSortCustom then
  begin
    case FSortColumn of
      TAtlasFindingColumn.Icon, TAtlasFindingColumn.Kind:
        Result := Ord(A.Kind) - Ord(B.Kind);
      TAtlasFindingColumn.Category:
        Result := Ord(A.Category) - Ord(B.Category);
      TAtlasFindingColumn.Message:
        Result := CompareText(A.Problem.Message, B.Problem.Message);
      TAtlasFindingColumn.Line:
        Result := CompareText(A.LineText, B.LineText);
      TAtlasFindingColumn.Location:
        begin
          Result := CompareText(ExtractFileName(A.FileName), ExtractFileName(B.FileName));
          if Result = 0 then
            Result := A.Problem.StartLine - B.Problem.StartLine;
          if Result = 0 then
            Result := A.Problem.StartCharacter - B.Problem.StartCharacter;
        end;
      TAtlasFindingColumn.Rule:
        Result := CompareText(A.Problem.Code, B.Problem.Code);
      TAtlasFindingColumn.Compiler:
        Result := CompareText(A.CompilerText, B.CompilerText);
    end;
    if FSortDescending then
      Result := -Result;
  end;
  if Result = 0 then
    Result := CompareDefault(A, B);
end;

function TAtlasFindingsView.IsActiveInScope: Boolean;
var
  Name: string;
begin
  if FActiveKey = '' then
    Exit(False);
  if (FFilter.Scope = TAtlasFindingScope.CurrentFile) or (FFilter.Files = nil) then
    Exit(True);
  for Name in FFilter.Files do
    if TAtlasFindings.UnitKey(Name) = FActiveKey then
      Exit(True);
  Result := False;
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
  Index: Integer;
  Units: TDictionary<string, Boolean>;
begin
  Result := Default(TAtlasFindingRow);
  Result.IsSection := True;
  Result.Finding := -1;
  Result.Tier := ATier;
  Result.Pinned := ATier = TAtlasFindingTier.Active;
  Result.Dimmed := (ATier = TAtlasFindingTier.Closed) and (FClosedUnits = TAtlasClosedUnits.Dimmed);
  Result.Count := Length(AMembers);
  Units := TDictionary<string, Boolean>.Create;
  try
    for Index in AMembers do
      Units.AddOrSetValue(TAtlasFindings.UnitKey(FFindings[Index].FileName), True);
    Result.Units := Units.Count;
  finally
    Units.Free;
  end;
  if ATier = TAtlasFindingTier.Active then
    Result.Caption := ExtractFileName(FActiveFile);
end;

function TAtlasFindingsView.CleanActiveRow(out ARow: TAtlasFindingRow): Boolean;
begin
  ARow := Default(TAtlasFindingRow);
  Result := TiersActive and FShowCleanActive and IsActiveInScope;
  if not Result then
    Exit;
  ARow := SectionRow(TAtlasFindingTier.Active, nil);
  ARow.IsCleanActive := True;
  ARow.Checking := not FActiveChecked;
end;

procedure TAtlasFindingsView.Rebuild;
var
  Index: Integer;
  Order: TList<Integer>;
  Groups: TList<string>;
  Members: TObjectDictionary<string, TList<Integer>>;
  Key: string;
  Row: TAtlasFindingRow;
  Collapsed, Tiers, HasActive: Boolean;
  Member: Integer;
  First: TAtlasFinding;
  Tier: TAtlasFindingTier;
  OfTier: array[TAtlasFindingTier] of TArray<Integer>;
  Started: array[TAtlasFindingTier] of Boolean;
begin
  Tiers := TiersActive;
  Order := TList<Integer>.Create;
  try
    for Index := 0 to High(FFindings) do
      if FFilter.Matches(FFindings[Index]) and not HiddenByTier(FFindings[Index]) then
        Order.Add(Index);
    Order.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := Compare(FFindings[A], FFindings[B]);
      end));
    FRows := nil;
    for Tier := Low(TAtlasFindingTier) to High(TAtlasFindingTier) do
    begin
      OfTier[Tier] := nil;
      Started[Tier] := False;
    end;
    HasActive := False;
    for Index in Order do
    begin
      Tier := FFindings[Index].Tier;
      OfTier[Tier] := OfTier[Tier] + [Index];
      if Tier = TAtlasFindingTier.Active then
        HasActive := True;
    end;
    if FGrouping = TAtlasFindingGrouping.None then
    begin
      FVisible := Order.ToArray;
      // Ohne Gruppierung (#1108): die drei Stufen als Trennzeilen, die aktive Unit auch ohne Befunde.
      if Tiers and not HasActive and CleanActiveRow(Row) then
        FRows := FRows + [Row];
      for Index in FVisible do
      begin
        Tier := FFindings[Index].Tier;
        if Tiers and not Started[Tier] then
        begin
          Started[Tier] := True;
          FRows := FRows + [SectionRow(Tier, OfTier[Tier])];
        end;
        FRows := FRows + [FindingRow(Index, '')];
      end;
      Exit;
    end;
    Groups := TList<string>.Create;
    Members := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
    try
      for Index in Order do
      begin
        Key := GroupKeyOf(FFindings[Index]);
        if not Members.ContainsKey(Key) then
        begin
          Groups.Add(Key);
          Members.Add(Key, TList<Integer>.Create);
        end;
        Members[Key].Add(Index);
      end;
      // Gruppen nach Datei, Regel bzw. Kategorie; innerhalb der Gruppe die gewählte Sortierung. Nach Datei mit
      // Offene-zuerst (#1108) kommt die Stufe vor dem Namen: aktive Unit, geöffnete und nicht geöffnete je
      // alphabetisch, damit beim Editorwechsel nur die angepinnte Gruppe springt.
      Groups.Sort(TComparer<string>.Construct(
        function(const A, B: string): Integer
        var
          FirstA, FirstB: TAtlasFinding;
        begin
          FirstA := FFindings[Members[A][0]];
          FirstB := FFindings[Members[B][0]];
          Result := 0;
          if Tiers and (FGrouping = TAtlasFindingGrouping.ByFile) then
            Result := Ord(FirstA.Tier) - Ord(FirstB.Tier);
          if Result = 0 then
            case FGrouping of
              TAtlasFindingGrouping.ByFile:
                Result := CompareText(ExtractFileName(FirstA.FileName), ExtractFileName(FirstB.FileName));
              TAtlasFindingGrouping.ByRule:
                Result := CompareText(FirstA.Problem.Code, FirstB.Problem.Code);
            else
              Result := Ord(FirstA.Category) - Ord(FirstB.Category);
            end;
          if Result = 0 then
            Result := CompareText(A, B);
        end));
      FVisible := nil;
      if Tiers and (FGrouping = TAtlasFindingGrouping.ByFile) and not HasActive and CleanActiveRow(Row) then
        FRows := FRows + [Row];
      for Key in Groups do
      begin
        First := FFindings[Members[Key][0]];
        // Trennzeilen „Geöffnet“ und „Nicht geöffnet“ nur nach Datei; bei Regel und Kategorie würden sie sich in
        // jeder Gruppe wiederholen.
        if Tiers and (FGrouping = TAtlasFindingGrouping.ByFile) and (First.Tier <> TAtlasFindingTier.Active) and
          not Started[First.Tier] then
        begin
          Started[First.Tier] := True;
          FRows := FRows + [SectionRow(First.Tier, OfTier[First.Tier])];
        end;
        Row := Default(TAtlasFindingRow);
        Row.IsGroup := True;
        Row.GroupKey := Key;
        Row.Finding := -1;
        Row.Count := Members[Key].Count;
        Row.Category := First.Category;
        if Tiers and (FGrouping = TAtlasFindingGrouping.ByFile) then
        begin
          Row.Tier := First.Tier;
          Row.Pinned := First.Tier = TAtlasFindingTier.Active;
          Row.Dimmed := (First.Tier = TAtlasFindingTier.Closed) and (FClosedUnits = TAtlasClosedUnits.Dimmed);
        end;
        case FGrouping of
          TAtlasFindingGrouping.ByFile:
            Row.Caption := ExtractFileName(First.FileName);
          TAtlasFindingGrouping.ByRule:
            Row.Caption := First.Problem.Code;
          TAtlasFindingGrouping.ByCategory:
            Row.Caption := CategoryNames[First.Category];
        end;
        if not FCollapsed.TryGetValue(Key, Collapsed) then
          Collapsed := False;
        Row.Expanded := not Collapsed;
        FRows := FRows + [Row];
        for Member in Members[Key] do
        begin
          FVisible := FVisible + [Member];
          if Collapsed then
            Continue;
          FRows := FRows + [FindingRow(Member, Key)];
        end;
      end;
    finally
      Members.Free;
      Groups.Free;
    end;
  finally
    Order.Free;
  end;
  // Zugeklappte Gruppen, die gerade keine Befunde haben, bleiben gemerkt: Kommen ihre Befunde wieder, bleiben sie
  // zugeklappt.
end;

function TAtlasFindingsView.Rows: TArray<TAtlasFindingRow>;
begin
  Result := FRows;
end;

function TAtlasFindingsView.Finding(AIndex: Integer): TAtlasFinding;
begin
  Result := FFindings[AIndex];
end;

function TAtlasFindingsView.Visible: TArray<TAtlasFinding>;
var
  Index: Integer;
begin
  Result := nil;
  for Index in FVisible do
    Result := Result + [FFindings[Index]];
end;

function TAtlasFindingsView.Counts: TAtlasFindingCounts;
var
  Finding: TAtlasFinding;
  Files, OpenUnits, ClosedUnits, HiddenUnits: TDictionary<string, Boolean>;
  Tiers: Boolean;
begin
  Result := Default(TAtlasFindingCounts);
  Tiers := TiersActive;
  Files := TDictionary<string, Boolean>.Create;
  OpenUnits := TDictionary<string, Boolean>.Create;
  ClosedUnits := TDictionary<string, Boolean>.Create;
  HiddenUnits := TDictionary<string, Boolean>.Create;
  try
    for Finding in FFindings do
    begin
      if not FFilter.MatchesExceptKind(Finding) then
        Continue;
      // Ausgegraut ist reine Darstellung und zählt mit; ausgeblendet zählt nicht (#1108).
      if HiddenByTier(Finding) then
      begin
        if Finding.Kind in FFilter.Kinds then
          HiddenUnits.AddOrSetValue(TAtlasFindings.UnitKey(Finding.FileName), True);
        Continue;
      end;
      if Tiers and (Finding.Kind in FFilter.Kinds) then
      begin
        if Finding.Tier = TAtlasFindingTier.Closed then
        begin
          ClosedUnits.AddOrSetValue(TAtlasFindings.UnitKey(Finding.FileName), True);
          Inc(Result.ClosedFindings);
        end
        else
        begin
          OpenUnits.AddOrSetValue(TAtlasFindings.UnitKey(Finding.FileName), True);
          Inc(Result.OpenFindings);
        end;
      end;
      case Finding.Kind of
        TAtlasFindingKind.Error:
          Inc(Result.Errors);
        TAtlasFindingKind.Warning:
          Inc(Result.Warnings);
      else
        Inc(Result.Infos);
      end;
      if Finding.Kind in FFilter.Kinds then
        Files.AddOrSetValue(AnsiLowerCase(Finding.FileName), True);
    end;
    Result.Files := Files.Count;
    Result.OpenUnits := OpenUnits.Count;
    Result.ClosedUnits := ClosedUnits.Count;
    Result.HiddenUnits := HiddenUnits.Count;
  finally
    HiddenUnits.Free;
    ClosedUnits.Free;
    OpenUnits.Free;
    Files.Free;
  end;
end;

procedure TAtlasFindingsView.SetExpanded(const AGroupKey: string; AExpanded: Boolean);
begin
  if AExpanded then
    FCollapsed.Remove(AGroupKey)
  else
    FCollapsed.AddOrSetValue(AGroupKey, True);
  Rebuild;
end;

procedure TAtlasFindingsView.Toggle(ARow: Integer);
begin
  if (ARow < 0) or (ARow > High(FRows)) or not FRows[ARow].IsGroup then
    Exit;
  SetExpanded(FRows[ARow].GroupKey, not FRows[ARow].Expanded);
end;

procedure TAtlasFindingsView.Select(ARow: Integer);
begin
  if (ARow < 0) or (ARow > High(FRows)) then
    FSelectedKey := ''
  else if FRows[ARow].IsSection then
    // Trennzeilen sind nicht wählbar: Die Auswahl bleibt, wo sie war.
    Exit
  else if FRows[ARow].IsGroup then
    FSelectedKey := 'group:' + FRows[ARow].GroupKey
  else
    FSelectedKey := FFindings[FRows[ARow].Finding].Key;
end;

function TAtlasFindingsView.GetSelectedRow: Integer;
var
  Index: Integer;
begin
  Result := -1;
  if FSelectedKey = '' then
    Exit;
  for Index := 0 to High(FRows) do
    if FRows[Index].IsSection then
      Continue
    else if FRows[Index].IsGroup then
    begin
      if FSelectedKey = 'group:' + FRows[Index].GroupKey then
        Exit(Index);
    end
    else if FFindings[FRows[Index].Finding].Key = FSelectedKey then
      Exit(Index);
end;

function TAtlasFindingsView.SelectedFinding(out AFinding: TAtlasFinding): Boolean;
var
  Row: Integer;
begin
  AFinding := Default(TAtlasFinding);
  Row := GetSelectedRow;
  Result := (Row >= 0) and not FRows[Row].IsGroup and not FRows[Row].IsSection;
  if Result then
    AFinding := FFindings[FRows[Row].Finding];
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
        SetExpanded(Key, True);
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
    Exit(False);
  Current := -1;
  for Index := 0 to High(FVisible) do
    if FFindings[FVisible[Index]].Key = FSelectedKey then
      Current := Index;
  if Current < 0 then
  begin
    if AForward then
      Target := 0
    else
      Target := High(FVisible);
  end
  else if AForward then
    Target := (Current + 1) mod Length(FVisible)
  else
    Target := (Current - 1 + Length(FVisible)) mod Length(FVisible);
  AFinding := FFindings[FVisible[Target]];
  FSelectedKey := AFinding.Key;
  Key := GroupKeyOf(AFinding);
  if (Key <> '') and FCollapsed.ContainsKey(Key) then
    SetExpanded(Key, True);
  Result := True;
end;

function TAtlasFindingsView.FindingsOfRows(const ARows: TArray<Integer>): TArray<TAtlasFinding>;
var
  Row, Index: Integer;
  Done: TDictionary<Integer, Boolean>;

  procedure Add(AIndex: Integer);
  begin
    if Done.ContainsKey(AIndex) then
      Exit;
    Done.Add(AIndex, True);
    Result := Result + [FFindings[AIndex]];
  end;

begin
  Result := nil;
  Done := TDictionary<Integer, Boolean>.Create;
  try
    for Row in ARows do
    begin
      if (Row < 0) or (Row > High(FRows)) or FRows[Row].IsSection then
        Continue;
      if not FRows[Row].IsGroup then
        Add(FRows[Row].Finding)
      else
        for Index in FVisible do
          if GroupKeyOf(FFindings[Index]) = FRows[Row].GroupKey then
            Add(Index);
    end;
  finally
    Done.Free;
  end;
end;

end.
