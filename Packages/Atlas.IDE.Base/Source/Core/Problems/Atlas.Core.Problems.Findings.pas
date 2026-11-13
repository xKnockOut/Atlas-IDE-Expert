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
// - TAtlasFindingsView (Atlas.Core.Problems.FindingsView): Filter (Bereich, Arten, Kategorie, Text, Compiler),
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
// - Fehler der IDE (#1819, problems.ideErrors): Die Befunde kommen aus
//   WithIde des Speichers, abgeglichen mit Error Insight. Spalte „Quelle“
//   (Atlas, Atlas + IDE, IDE) und Filter Origin (alle, nur Atlas, nur IDE).
// - IAtlasBulkFixer: Vertrag der Sammelkorrektur (#1352) für das Modul
//   Prüfregeln (#1455).

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.IdeErrors,
  Atlas.Core.Problems.Store;

type
  {$SCOPEDENUMS ON}
  /// <summary>Spalte „Art“: Error (auch Bug), Warnung, Info (information und hint).</summary>
  TAtlasFindingKind = (Error, Warning, Info);
  TAtlasFindingCategory = (Bug, Vulnerability, CodeSmell, SecurityHotspot, Compiler, Other);
  TAtlasFindingColumn = (Icon, Kind, Category, Message, Line, Location, Rule, Compiler, Source);
  /// <summary>Filter „Quelle“ (#1819): Atlas und IDE (alle), nur Atlas, nur IDE.</summary>
  TAtlasFindingOrigin = (All, AtlasOnly, IdeOnly);
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
    /// <summary>Spalte „Quelle“ (#1819): "Atlas", "Atlas + IDE", "IDE" bzw. die Quelle (dcc, DUnitX, Aufgabe).
    /// </summary>
    function SourceText: string;
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
    /// <summary>Filter „Quelle“ (#1819); nur Atlas bzw. nur IDE ohne Compiler, Tests und Aufgaben.</summary>
    Origin: TAtlasFindingOrigin;
    /// <summary>Bereich „aktuelle Datei“.</summary>
    CurrentFile: string;
    /// <summary>Bereich „Projekt“ bzw. „Projektgruppe“: Dateien des Bereichs; nil = alle Dateien des
    /// Speichers.</summary>
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
    cLineMax = 80;
    cColumnNames: array[TAtlasFindingColumn] of string = ('icon', 'kind', 'category', 'message', 'line',
      'location', 'rule', 'compiler', 'source');
    /// <summary>Marke eines vom Compiler bestätigten Befunds (#1024).</summary>
    cConfirmedMark = TAtlasProblem.cConfirmedSource;
    cScopeNames: array[TAtlasFindingScope] of string = ('file', 'project', 'group');
    cGroupingNames: array[TAtlasFindingGrouping] of string = ('none', 'file', 'rule', 'category');
    cClosedUnitsNames: array[TAtlasClosedUnits] of string = ('dimmed', 'normal', 'hidden');
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
    /// <summary>Name der Kategorie wie im Katalog (bug, code-smell …); '' bei Other.</summary>
    class function CategoryName(ACategory: TAtlasFindingCategory): string; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults;

const
  cCategoryNames: array[TAtlasFindingCategory] of string = ('bug', 'vulnerability', 'code-smell',
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
    Result := Result + ' ' + #$00B7 + ' ' + TAtlasFindings.cConfirmedMark;
  end;
end;

function TAtlasFinding.SourceText: string;
begin
  Result := TAtlasIdeErrors.OriginText(Problem);
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
  // Quelle (#1819): „Atlas und IDE“ lässt alle durch.
  if Origin = TAtlasFindingOrigin.AtlasOnly then
  begin
    Result := Result and (TAtlasIdeErrors.OriginOf(AFinding.Problem) = TAtlasProblemOrigin.Atlas);
  end
  else if Origin = TAtlasFindingOrigin.IdeOnly then
  begin
    Result := Result and (TAtlasIdeErrors.OriginOf(AFinding.Problem) = TAtlasProblemOrigin.Ide);
  end;
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
  mCategory: TAtlasFindingCategory;
begin
  if AProblem.IsCompiler then
  begin
    Exit(TAtlasFindingCategory.Compiler);
  end;
  for mCategory := Low(TAtlasFindingCategory) to Pred(TAtlasFindingCategory.Compiler) do
  begin
    if SameText(AProblem.Category, cCategoryNames[mCategory]) then
    begin
      Exit(mCategory);
    end;
  end;
  Result := TAtlasFindingCategory.Other;
end;

class function TAtlasFindings.IsFinding(const AProblem: TAtlasProblem): Boolean;
begin
  Result := not AProblem.Unnecessary and not AProblem.IsUses and
    not SameText(AProblem.Source, TAtlasProblemStore.cTestSource);
end;

class function TAtlasFindings.FromProblems(const AFileName: string; const AProblems: TArray<TAtlasProblem>;
  const ALines: TArray<string>): TArray<TAtlasFinding>;
var
  mProblem: TAtlasProblem;
  mFinding: TAtlasFinding;
  mSeen: TDictionary<string, Integer>;
  mBase: string;
  mNumber, mCount: Integer;
begin
  SetLength(Result, Length(AProblems));
  mCount := 0;
  mSeen := TDictionary<string, Integer>.Create;
  try
    for mProblem in AProblems do
    begin
      if not IsFinding(mProblem) then
      begin
        Continue;
      end;
      mFinding := Default(TAtlasFinding);
      mFinding.FileName := AFileName;
      mFinding.Problem := mProblem;
      mFinding.Kind := KindOf(mProblem.Severity);
      mFinding.Category := CategoryOf(mProblem);
      if (mProblem.StartLine >= 0) and (mProblem.StartLine < Length(ALines)) then
      begin
        mFinding.LineText := ALines[mProblem.StartLine].Trim;
      end;
      mBase := AnsiLowerCase(AFileName) + '|' + mProblem.Source + '|' + mProblem.Code + '|' + mProblem.Message;
      if not mSeen.TryGetValue(mBase, mNumber) then
      begin
        mNumber := 0;
      end;
      Inc(mNumber);
      mSeen.AddOrSetValue(mBase, mNumber);
      mFinding.Key := mBase + '|' + IntToStr(mNumber);
      Result[mCount] := mFinding;
      Inc(mCount);
    end;
  finally
    mSeen.Free;
  end;
  SetLength(Result, mCount);
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
  mProblems := AStore.WithIde(AFileName);
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
  mPart: TArray<TAtlasFinding>;
  mCount, mIndex: Integer;
begin
  mCount := 0;
  for mPart in AParts do
  begin
    Inc(mCount, Length(mPart));
  end;
  SetLength(Result, mCount);
  mCount := 0;
  for mPart in AParts do
  begin
    for mIndex := 0 to High(mPart) do
    begin
      Result[mCount] := mPart[mIndex];
      Inc(mCount);
    end;
  end;
end;

class function TAtlasFindings.FromStore(AStore: TAtlasProblemStore; const AFiles: TArray<string>;
  const AReadLines: TFunc<string, TArray<string>>): TArray<TAtlasFinding>;
var
  mFiles: TArray<string>;
  mParts: TArray<TArray<TAtlasFinding>>;
  mIndex: Integer;
begin
  mFiles := AFiles;
  if mFiles = nil then
  begin
    mFiles := AStore.Files;
  end;
  SetLength(mParts, Length(mFiles));
  for mIndex := 0 to High(mFiles) do
  begin
    mParts[mIndex] := FromStoreFile(AStore, mFiles[mIndex], AReadLines);
  end;
  Result := Concat(mParts);
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
  mFileName: string;
begin
  Result := 0;
  for mFileName in AProjectFiles do
  begin
    if AStore.Contains(mFileName) then
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasFindings.IsMandatory(AColumn: TAtlasFindingColumn): Boolean;
begin
  Result := not (AColumn in [TAtlasFindingColumn.Message, TAtlasFindingColumn.Rule, TAtlasFindingColumn.Compiler,
    TAtlasFindingColumn.Source]);
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
    if SameText(AName, TAtlasFindings.cColumnNames[mCandidate]) then
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
  mState: TAtlasFindingColumnState;
  mPart: string;
begin
  Result := '';
  for mState in AColumns do
  begin
    mPart := cColumnNames[mState.Column];
    if not mState.Visible and not IsMandatory(mState.Column) then
    begin
      mPart := '-' + mPart;
    end;
    if mState.Width > 0 then
    begin
      mPart := mPart + ':' + IntToStr(mState.Width);
    end;
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mPart;
  end;
end;

class function TAtlasFindings.TryParseScope(const AText: string; out AScope: TAtlasFindingScope): Boolean;
var
  mScope: TAtlasFindingScope;
begin
  for mScope := Low(TAtlasFindingScope) to High(TAtlasFindingScope) do
  begin
    if SameText(AText, cScopeNames[mScope]) then
    begin
      AScope := mScope;
      Exit(True);
    end;
  end;
  AScope := TAtlasFindingScope.Group;
  Result := False;
end;

class function TAtlasFindings.TryParseGrouping(const AText: string; out AGrouping: TAtlasFindingGrouping): Boolean;
var
  mGrouping: TAtlasFindingGrouping;
begin
  for mGrouping := Low(TAtlasFindingGrouping) to High(TAtlasFindingGrouping) do
  begin
    if SameText(AText, cGroupingNames[mGrouping]) then
    begin
      AGrouping := mGrouping;
      Exit(True);
    end;
  end;
  AGrouping := TAtlasFindingGrouping.ByFile;
  Result := False;
end;

class function TAtlasFindings.UnitKey(const AFileName: string): string;
var
  mExtension: string;
begin
  Result := AnsiLowerCase(AFileName);
  mExtension := ExtractFileExt(Result);
  if (mExtension = '.dfm') or (mExtension = '.fmx') then
  begin
    Result := ChangeFileExt(Result, '.pas');
  end;
end;

class function TAtlasFindings.TryParseClosedUnits(const AText: string; out AValue: TAtlasClosedUnits): Boolean;
var
  mValue: TAtlasClosedUnits;
begin
  for mValue := Low(TAtlasClosedUnits) to High(TAtlasClosedUnits) do
  begin
    if SameText(AText, cClosedUnitsNames[mValue]) then
    begin
      AValue := mValue;
      Exit(True);
    end;
  end;
  AValue := TAtlasClosedUnits.Dimmed;
  Result := False;
end;

class function TAtlasFindings.CategoryName(ACategory: TAtlasFindingCategory): string;
begin
  Result := cCategoryNames[ACategory];
end;

class function TAtlasFindings.AsText(const AFindings: TArray<TAtlasFinding>): string;
const
  cKindWords: array[TAtlasFindingKind] of string = ('error', 'warning', 'info');
var
  mItem: TAtlasFinding;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mItem in AFindings do
    begin
      mBuilder.Append(mItem.Location).Append(': ').Append(cKindWords[mItem.Kind]);
      if mItem.Rule <> '' then
      begin
        mBuilder.Append(' [').Append(mItem.Rule).Append(']');
      end;
      mBuilder.Append(' ').Append(mItem.Problem.Message).Append(#13#10);
      if mItem.LineText <> '' then
      begin
        mBuilder.Append('    ').Append(mItem.LineText).Append(#13#10);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
