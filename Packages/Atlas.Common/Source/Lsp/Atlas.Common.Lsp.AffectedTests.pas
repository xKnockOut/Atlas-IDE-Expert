unit Atlas.Common.Lsp.AffectedTests;

// Betroffene Tests einer Änderung (#1353): aus dem Unterschied zur Basis
// (Git oder SVN, geänderte Zeilen aus Atlas.Common.Rules.ChangedFiles) die
// geänderten Symbole bestimmen, ihre Auswirkungen verfolgen (#1120) und die
// DUnitX-Testmethoden ausgeben, die dabei erreicht werden.
//
// Geänderte Zeilen → Symbole (Map):
// - Zählen nur Zeilen mit Code; Leerzeilen und reine Kommentare nicht. Eine
//   Stelle, an der nur Zeilen entfernt wurden (TChangedLines.Gaps), zählt für
//   das Symbol, das die Zeilen davor und danach umschließt; liegen sie in
//   verschiedenen Symbolen (z. B. eine ganze Routine entfernt), für die Unit.
// - In einer Routine mit Rumpf (auch im Kopf der Umsetzung): die Routine.
//   Sonst das innerste Symbol der Unit (Methodenkopf in der Klasse, Feld,
//   Typ, Konstante), auch im interface-Teil.
// - Außerhalb jedes Symbols (uses, initialization, finalization): die ganze
//   Unit. Sie wird über uses verfolgt: Testunits, die sie über bis zu
//   Tiefe Ebenen verwenden, mit allen ihren Tests.
// - .dfm/.fmx: die Formularklasse in der gleichnamigen Unit. .inc: die
//   Stelle des {$I} in den einbindenden Units. Geänderte Dateien des
//   Testprogramms (.dpr, .dproj): alle Tests. Andere Dateien (Doku,
//   Projektdateien anderer Projekte, Units außerhalb der Projekte) zählen
//   nicht und stehen unter Skipped.
// - Kann eine Datei nicht zugeordnet werden (Formularklasse fehlt), sind alle
//   Tests nötig: All mit Grund.
//
// Verfolgung: TImpactAnalysis.AnalyzeEach je geändertem Symbol bis zur Tiefe;
// Tests auf jeder Ebene zählen, geänderte Testmethoden selbst (Ebene 0) immer.
// Jeder Test trägt seine Gründe: die geänderte Stelle und den Weg bis zum
// Test, erschlossene Wege (#1119) gekennzeichnet.
//
// Ausgabe: Unit.Fixture.Methode, sortiert (ohne Groß-/Kleinschreibung, bei
// Gleichstand ordinal). Sind mehr als FixturePercent Prozent der Tests einer
// Fixture betroffen, steht die ganze Fixture (Unit.Fixture) da. Formate text,
// json (run passt in run_tests.tests) und dunitx (fertiges --run:… für die
// Test-exe).

interface

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.ChangedFiles,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.AffectedTests.Contract;

type
  TAffectedTests = class
  public const
    cMethod = 'atlas/affectedTests';
    cDefaultDepth = 3;
    /// <summary>Mehr als so viel Prozent der Tests einer Fixture betroffen: die ganze Fixture.</summary>
    cFixturePercent = 80;
  public
    /// <summary>Geänderte Stellen einer Pascal-Datei (Text AText, Unit AUnitName) zu den Zeilen ALines.</summary>
    class function MapPascal(const AFileName, AText: string; const ALines: TChangedLines): TArray<TAffectedChange>;
      overload; static;
    /// <summary>Wie oben für einzelne Zeilen AAt (0-basiert, z. B. die eines {$I}); APlace ersetzt die Angabe
    /// interface/implementation.</summary>
    class function MapPascal(const AFileName, AText: string; const AAt: TArray<Integer>;
      const APlace: string): TArray<TAffectedChange>; overload; static;
    /// <summary>Klasse des Formulars aus der ersten Zeile der .dfm/.fmx ("object Form1: TForm1"); '' ohne.</summary>
    class function FormClass(const AFormText: string): string; static;
    /// <summary>Zeilen einer Unit (0-basiert), in denen {$I}/{$INCLUDE} die Datei AIncludeFile einbindet.</summary>
    class function IncludeLines(const AText, AIncludeFile: string): TArray<Integer>; static;
    /// <summary>Ordnet die geänderten Dateien zu, verfolgt sie und liefert die betroffenen Tests.</summary>
    class function Determine(AResolver: TNameResolver; const AIndex: ISymbolIndex;
      const AInputs: TArray<TAffectedInput>; const ARequest: TAffectedRequest; const AReadText: TReferenceReadText;
      const ACancellation: IJsonRpcCancellationToken): TAffectedResult; static;
    /// <summary>Fasst Tests einer Fixture zusammen, wenn mehr als FixturePercent Prozent betroffen sind; ATotal
    /// liefert die Zahl der Tests einer Fixture (Datei, Fixture) und ihre Namen für --run.</summary>
    class function Collapse(const ATests: TArray<TAffectedTest>;
      const ATotal: TFunc<TAffectedTest, Integer>; const AFixtureRun: TFunc<TAffectedTest, TArray<string>>):
      TArray<TAffectedTest>; static;
    /// <summary>Tests nach Name (ohne Groß-/Kleinschreibung, bei Gleichstand ordinal), Gründe nach Text.</summary>
    class procedure Sort(var ATests: TArray<TAffectedTest>); static;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  System.Math,
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.ReferenceConfidence,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Lsp.Impact,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TAffectedTestsText = (TestProgramChanged, NotInTheProjects, NotReadable, OnlyBlankLinesOrComments,
    UnitNotInTheProjects, FormClassOfNotFound, NotUsedByAnyUnit, NoDelphiSource, TimeLimitOfTheAnalysis,
    ProjectFileOfAnotherProject, MoreThanAffectedPlaces, Form);

const
  cTexts: array[TAffectedTestsText] of TAtlasText = (
    (De: 'Testprogramm %s geändert'; En: 'Test program %s changed'),
    (De: 'nicht in den Projekten'; En: 'not in the projects'),
    (De: '%s nicht lesbar'; En: '%s not readable'),
    (De: 'nur Leerzeilen oder Kommentare'; En: 'only blank lines or comments'),
    (De: 'Unit nicht in den Projekten'; En: 'Unit not in the projects'),
    (De: 'Formularklasse von %s nicht gefunden'; En: 'Form class of %s not found'),
    (De: 'von keiner Unit der Projekte eingebunden'; En: 'not used by any unit of the projects'),
    (De: 'keine Delphi-Quelle'; En: 'no Delphi source'),
    (De: 'Zeitlimit der Analyse erreicht'; En: 'Time limit of the analysis reached'),
    (De: 'Projektdatei eines anderen Projekts'; En: 'project file of another project'),
    (De: 'mehr als %d betroffene Stellen'; En: 'more than %d affected places'),
    (De: 'Formular'; En: 'form'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Eine Pascal-Datei für die Zuordnung geänderter Zeilen: Baum, Symbole, Zeilen mit Code, Abschnitte.
  /// </summary>
  TAffectedSource = class
  private
    FFileName: string;
    FTree: TSyntaxTree;
    FUnit: TUnitIndex;
    /// <summary>Je Zeile die erste Position mit Code; Character = -1 ohne Code.</summary>
    FCode: TArray<TTextPosition>;
    FImplementationLine: Integer;
    FInitializationLine: Integer;
    function SectionOf(ALine: Integer): string;
    function KeyOf(const AChange: TAffectedChange): string;
    function UnitChange(const APlace: string): TAffectedChange;
    function GetLineCount: Integer;
    /// <summary>Zeilen des Tokens als Zeilen mit Code.</summary>
    procedure MarkCode(const AToken: TPascalToken);
    /// <summary>Merkt sich die Zeile von implementation und initialization/finalization.</summary>
    procedure NoteSection(const AToken: TPascalToken);
  public
    constructor Create(const AFileName, AText: string);
    destructor Destroy; override;
    /// <summary>Geänderte Stelle an der Zeile ALine (mit Code); APlace '' = Abschnitt der Zeile.</summary>
    function ChangeAt(ALine: Integer; const APlace: string): TAffectedChange;
    /// <summary>Stelle, an der nur Zeilen entfernt wurden; False, wenn davor oder danach kein Code steht.</summary>
    function ChangeAtGap(AGap: Integer; out AChange: TAffectedChange): Boolean;
    procedure Add(var AChanges: TArray<TAffectedChange>; const AChange: TAffectedChange);
    function HasCode(ALine: Integer): Boolean;
    property LineCount: Integer read GetLineCount;
  end;

procedure TAffectedSource.MarkCode(const AToken: TPascalToken);
var
  mLine: Integer;
begin
  // Zeilen, die ein mehrzeiliges Token (String) überspannt, zählen als Code ab Spalte 0.
  for mLine := Max(AToken.StartPos.Line, 0) to Min(AToken.EndPos.Line, High(FCode)) do
  begin
    if FCode[mLine].Character >= 0 then
    begin
      Continue;
    end;
    if mLine = AToken.StartPos.Line then
    begin
      FCode[mLine] := AToken.StartPos;
    end
    else
    begin
      FCode[mLine] := TTextPosition.Create(mLine, 0);
    end;
  end;
end;

procedure TAffectedSource.NoteSection(const AToken: TPascalToken);
begin
  // initialization und finalization sind reservierte Wörter und stehen nur auf Unit-Ebene.
  if AToken.IsKeyword('implementation') and (FImplementationLine = MaxInt) then
  begin
    FImplementationLine := AToken.StartPos.Line;
  end
  else if (FInitializationLine = MaxInt) and
    (AToken.IsKeyword('initialization') or AToken.IsKeyword('finalization')) then
  begin
    FInitializationLine := AToken.StartPos.Line;
  end;
end;

constructor TAffectedSource.Create(const AFileName, AText: string);
var
  mToken: TPascalToken;
  mLine: Integer;
begin
  inherited Create;
  FFileName := AFileName;
  SetLength(FCode, Length(TTextLines.SplitLines(AText)));
  for mLine := 0 to High(FCode) do
  begin
    FCode[mLine] := TTextPosition.Create(mLine, -1);
  end;
  FImplementationLine := MaxInt;
  FInitializationLine := MaxInt;
  for mToken in TPascalLexer.Tokenize(AText) do
  begin
    if mToken.Kind <> TPascalTokenKind.Comment then
    begin
      MarkCode(mToken);
      NoteSection(mToken);
    end;
  end;
  FTree := TSyntaxTreeCache.Parse(AText);
  FUnit := TIndexExtractor.Extract(FTree, AFileName);
end;

destructor TAffectedSource.Destroy;
begin
  FTree.Free;
  inherited;
end;

function TAffectedSource.GetLineCount: Integer;
begin
  Result := Length(FCode);
end;

function TAffectedSource.HasCode(ALine: Integer): Boolean;
begin
  Result := (ALine >= 0) and (ALine < Length(FCode)) and (FCode[ALine].Character >= 0);
end;

function TAffectedSource.SectionOf(ALine: Integer): string;
begin
  if ALine >= FInitializationLine then
  begin
    Result := 'initialization';
  end
  else if ALine >= FImplementationLine then
  begin
    Result := 'implementation';
  end
  else
  begin
    Result := 'interface';
  end;
end;

function TAffectedSource.KeyOf(const AChange: TAffectedChange): string;
begin
  if AChange.Kind = TAffectedChangeKind.WholeUnit then
  begin
    Result := 'unit|' + UpperCase(AChange.Item.FileName);
  end
  else
  begin
    Result := UpperCase(AChange.Item.FileName) + '|' + IntToStr(AChange.Item.SelectionRange.StartPos.Line) + ':' +
      IntToStr(AChange.Item.SelectionRange.StartPos.Character);
  end;
end;

function SpanSize(const ARange: TTextRange): Int64;
begin
  Result := Int64(ARange.EndPos.Line - ARange.StartPos.Line) * 100000 + ARange.EndPos.Character -
    ARange.StartPos.Character;
end;

function RangeHas(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := ((ARange.StartPos.Line < APosition.Line) or
    ((ARange.StartPos.Line = APosition.Line) and (ARange.StartPos.Character <= APosition.Character))) and
    ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

function TAffectedSource.UnitChange(const APlace: string): TAffectedChange;
begin
  Result := Default(TAffectedChange);
  Result.Kind := TAffectedChangeKind.WholeUnit;
  Result.Source := FFileName;
  Result.Place := APlace;
  Result.Item := Default(THierarchyItem);
  Result.Item.Name := FUnit.UnitName;
  if Result.Item.Name = '' then
  begin
    Result.Item.Name := ChangeFileExt(ExtractFileName(FFileName), '');
  end;
  Result.Item.UnitName := Result.Item.Name;
  Result.Item.FileName := FFileName;
  Result.Item.SymbolKind := TIndexSymbolKind.Variable;
end;

function TAffectedSource.ChangeAt(ALine: Integer; const APlace: string): TAffectedChange;
var
  mPosition: TTextPosition;
  mSymbol, mBest: TIndexSymbol;
  mFound: Boolean;
begin
  Result := Default(TAffectedChange);
  Result.Source := FFileName;
  Result.Place := APlace;
  if Result.Place = '' then
  begin
    Result.Place := SectionOf(ALine);
  end;
  mPosition := FCode[ALine];
  // Rumpf und Kopf einer Routine: die Routine (bei lokalen Routinen die innerste).
  if TLspHierarchies.RoutineAt(FTree, FFileName, mPosition, Result.Item) then
  begin
    Result.Kind := TAffectedChangeKind.Symbol;
    Result.Item.UnitName := FUnit.UnitName;
    Exit;
  end;
  mFound := False;
  mBest := Default(TIndexSymbol);
  if ALine < FInitializationLine then
  begin
    for mSymbol in FUnit.Symbols do
    begin
      // Symbole aus Include-Dateien tragen deren Zeilen.
      if (mSymbol.FileName = '') and RangeHas(mSymbol.Range, mPosition) and
        (not mFound or (SpanSize(mSymbol.Range) < SpanSize(mBest.Range))) then
      begin
        mBest := mSymbol;
        mFound := True;
      end;
    end;
  end;
  if mFound then
  begin
    Result.Kind := TAffectedChangeKind.Symbol;
    Result.Item := TLspHierarchies.ItemOf(FUnit.UnitName, FFileName, mBest);
    Exit;
  end;
  // uses, initialization, finalization, Rumpf eines Programms: die Unit.
  Result := UnitChange(Result.Place);
end;

function TAffectedSource.ChangeAtGap(AGap: Integer; out AChange: TAffectedChange): Boolean;
var
  mAbove, mBelow: Integer;
  mBefore, mAfter: TAffectedChange;
begin
  Result := False;
  mAbove := AGap - 1;
  if mAbove >= Length(FCode) then
  begin
    mAbove := Length(FCode) - 1;
  end;
  while (mAbove >= 0) and not HasCode(mAbove) do
  begin
    Dec(mAbove);
  end;
  mBelow := AGap;
  while (mBelow < Length(FCode)) and not HasCode(mBelow) do
  begin
    Inc(mBelow);
  end;
  // Am Anfang oder Ende der Datei: nichts, was die Zeilen umschloss.
  if (mAbove < 0) or (mBelow >= Length(FCode)) then
  begin
    Exit;
  end;
  mBefore := ChangeAt(mAbove, '');
  mAfter := ChangeAt(mBelow, '');
  if KeyOf(mBefore) = KeyOf(mAfter) then
  begin
    AChange := mBefore;
  end
  else
  begin
    // Zwischen zwei Symbolen entfernt (z. B. eine ganze Routine): Was fehlt, lässt sich nicht mehr verfolgen.
    AChange := UnitChange(SectionOf(mBelow));
  end;
  Result := True;
end;

procedure TAffectedSource.Add(var AChanges: TArray<TAffectedChange>; const AChange: TAffectedChange);
var
  mChange: TAffectedChange;
  mKey: string;
begin
  mKey := KeyOf(AChange);
  for mChange in AChanges do
  begin
    if KeyOf(mChange) = mKey then
    begin
      Exit;
    end;
  end;
  AChanges := AChanges + [AChange];
end;

{ TAffectedTests }

class function TAffectedTests.MapPascal(const AFileName, AText: string;
  const ALines: TChangedLines): TArray<TAffectedChange>;
var
  mSource: TAffectedSource;
  mSpan: TLineSpan;
  mLine, mLast, mGap: Integer;
  mChange: TAffectedChange;
begin
  Result := nil;
  mSource := TAffectedSource.Create(AFileName, AText);
  try
    for mSpan in ALines.Spans do
    begin
      mLast := mSpan.Last;
      if mLast >= mSource.LineCount then
      begin
        mLast := mSource.LineCount - 1;
      end;
      for mLine := mSpan.First to mLast do
      begin
        if mSource.HasCode(mLine) then
        begin
          mSource.Add(Result, mSource.ChangeAt(mLine, ''));
        end;
      end;
    end;
    for mGap in ALines.Gaps do
    begin
      if mSource.ChangeAtGap(mGap, mChange) then
      begin
        mSource.Add(Result, mChange);
      end;
    end;
  finally
    mSource.Free;
  end;
end;

class function TAffectedTests.MapPascal(const AFileName, AText: string; const AAt: TArray<Integer>;
  const APlace: string): TArray<TAffectedChange>;
var
  mSource: TAffectedSource;
  mLine: Integer;
begin
  Result := nil;
  mSource := TAffectedSource.Create(AFileName, AText);
  try
    for mLine in AAt do
    begin
      if mSource.HasCode(mLine) then
      begin
        mSource.Add(Result, mSource.ChangeAt(mLine, APlace));
      end;
    end;
  finally
    mSource.Free;
  end;
end;

class function TAffectedTests.FormClass(const AFormText: string): string;
var
  mLine, mRest: string;
  mColon: Integer;
begin
  Result := '';
  for mLine in TTextLines.SplitLines(AFormText) do
  begin
    mRest := Trim(mLine);
    if mRest = '' then
    begin
      Continue;
    end;
    // object Form1: TForm1 | inherited Form2: TForm2 | inline Frame1: TFrame1 [n]
    if not (StartsText('object ', mRest) or StartsText('inherited ', mRest) or StartsText('inline ', mRest)) then
    begin
      Exit;
    end;
    mColon := Pos(':', mRest);
    if mColon = 0 then
    begin
      Exit;
    end;
    Result := Trim(Copy(mRest, mColon + 1, MaxInt));
    if Pos(' ', Result) > 0 then
    begin
      Result := Copy(Result, 1, Pos(' ', Result) - 1);
    end;
    Exit;
  end;
end;

function BaseNameOf(const APath: string): string;
var
  mPath: string;
begin
  mPath := StringReplace(APath, '\', '/', [rfReplaceAll]);
  Result := Copy(mPath, LastDelimiter('/', mPath) + 1, MaxInt);
end;

class function TAffectedTests.IncludeLines(const AText, AIncludeFile: string): TArray<Integer>;
var
  mLines: TArray<string>;
  mIndex: Integer;
  mName: string;
begin
  // Abgleich über den Dateinamen wie TChangedFiles.Select; ohne Endung gilt .inc.
  Result := nil;
  mLines := TTextLines.SplitLines(AText);
  for mIndex := 0 to High(mLines) do
  begin
    for mName in TChangedFiles.IncludeNames(mLines[mIndex]) do
    begin
      if SameText(BaseNameOf(mName), BaseNameOf(AIncludeFile)) or
        ((Pos('.', BaseNameOf(mName)) = 0) and SameText(BaseNameOf(mName) + '.inc', BaseNameOf(AIncludeFile))) then
      begin
        Result := Result + [mIndex];
        Break;
      end;
    end;
  end;
end;

function SameFile(const A, B: string): Boolean;
begin
  Result := SameText(StringReplace(A, '/', '\', [rfReplaceAll]), StringReplace(B, '/', '\', [rfReplaceAll]));
end;

function ContainsFile(const AFiles: TArray<string>; const AFileName: string): Boolean;
var
  mFile: string;
begin
  for mFile in AFiles do
  begin
    if SameFile(mFile, AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function CompareTests(const A, B: TAffectedTest): Integer;
begin
  Result := CompareText(A.Name, B.Name);
  if Result = 0 then
  begin
    Result := CompareStr(A.Name, B.Name);
  end;
end;

function CompareReasons(const A, B: TAffectedReason): Integer;
begin
  Result := CompareText(A.Text, B.Text);
  if Result = 0 then
  begin
    Result := CompareStr(A.Text, B.Text);
  end;
end;

class procedure TAffectedTests.Sort(var ATests: TArray<TAffectedTest>);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATests) do
  begin
    TArray.Sort<TAffectedReason>(ATests[mIndex].Reasons, TComparer<TAffectedReason>.Construct(CompareReasons));
  end;
  TArray.Sort<TAffectedTest>(ATests, TComparer<TAffectedTest>.Construct(CompareTests));
end;

procedure AddReason(var ATest: TAffectedTest; const AReason: TAffectedReason);
var
  mReason: TAffectedReason;
begin
  for mReason in ATest.Reasons do
  begin
    if mReason.Text = AReason.Text then
    begin
      Exit;
    end;
  end;
  ATest.Reasons := ATest.Reasons + [AReason];
end;

/// <summary>Tests nach Datei und Fixture; AOrder in der Reihenfolge des ersten Auftretens.</summary>
procedure GroupByFixture(const ATests: TArray<TAffectedTest>; AGroups: TObjectDictionary<string, TList<Integer>>;
  AOrder: TList<string>);
var
  mKey: string;
  mIndex: Integer;
  mMembers: TList<Integer>;
begin
  for mIndex := 0 to High(ATests) do
  begin
    mKey := UpperCase(ATests[mIndex].FileName + '|' + ATests[mIndex].Fixture);
    if not AGroups.TryGetValue(mKey, mMembers) then
    begin
      mMembers := TList<Integer>.Create;
      AGroups.Add(mKey, mMembers);
      AOrder.Add(mKey);
    end;
    mMembers.Add(mIndex);
  end;
end;

/// <summary>Die ganze Fixture der Tests AMembers mit allen ihren Gründen.</summary>
function WholeFixture(const ATests: TArray<TAffectedTest>; AMembers: TList<Integer>;
  const AFixtureRun: TFunc<TAffectedTest, TArray<string>>): TAffectedTest;
var
  mIndex: Integer;
  mReason: TAffectedReason;
begin
  Result := ATests[AMembers[0]];
  Result.Method := '';
  Result.Name := TDUnitXCommandLine.TestName(Result.UnitName, Result.Fixture, '');
  Result.RunNames := AFixtureRun(Result);
  if Result.RunNames = nil then
  begin
    Result.RunNames := [Result.Name];
  end;
  Result.Reasons := nil;
  for mIndex in AMembers do
  begin
    for mReason in ATests[mIndex].Reasons do
    begin
      AddReason(Result, mReason);
    end;
  end;
end;

class function TAffectedTests.Collapse(const ATests: TArray<TAffectedTest>;
  const ATotal: TFunc<TAffectedTest, Integer>; const AFixtureRun: TFunc<TAffectedTest, TArray<string>>):
  TArray<TAffectedTest>;
var
  mGroups: TObjectDictionary<string, TList<Integer>>;
  mOrder: TList<string>;
  mKey: string;
  mIndex, mTotal: Integer;
  mMembers: TList<Integer>;
begin
  Result := nil;
  mGroups := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  mOrder := TList<string>.Create;
  try
    GroupByFixture(ATests, mGroups, mOrder);
    for mKey in mOrder do
    begin
      mMembers := mGroups[mKey];
      mTotal := ATotal(ATests[mMembers[0]]);
      // Schon eine ganze Fixture (ganze Unit geändert) oder mehr als FixturePercent Prozent betroffen. Eine Fixture
      // mit nur einem Test bleibt beim Methodennamen: zusammengefasst wäre es derselbe Test, nur ungenauer benannt.
      if (ATests[mMembers[0]].Method = '') or
        ((mTotal > 1) and (mMembers.Count * 100 > mTotal * cFixturePercent)) then
      begin
        Result := Result + [WholeFixture(ATests, mMembers, AFixtureRun)];
        Continue;
      end;
      for mIndex in mMembers do
      begin
        Result := Result + [ATests[mIndex]];
      end;
    end;
  finally
    mOrder.Free;
    mGroups.Free;
  end;
end;

type
  /// <summary>Zustand von Determine: gelesene Testunits, gesammelte Tests.</summary>
  TAffectedRun = class
  private
    FIndex: ISymbolIndex;
    FReadText: TReferenceReadText;
    FRequest: TAffectedRequest;
    FResult: TAffectedResult;
    FTests: TDictionary<string, TAffectedTest>;
    FOrder: TList<string>;
    FSources: TDictionary<string, TDUnitXUnit>;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function SourceOf(const AFileName: string): TDUnitXUnit;
    procedure Skip(const AFileName, AReason: string);
    procedure NeedAll(const AReason: string);
    procedure AddTest(const ATest: TAffectedTest; const AReason: TAffectedReason);
    procedure MapProject(const AInput: TAffectedInput; const AExt: string);
    procedure MapUnit(const AInput: TAffectedInput);
    procedure MapForm(const AInput: TAffectedInput);
    /// <summary>Änderungen in AIncluding über das Include AIncludeFile; False, wenn die Unit nicht lesbar ist.
    /// </summary>
    function MapIncluding(const AIncluding: TUnitIndex; const AIncludeFile: string): Boolean;
    procedure MapInclude(const AInput: TAffectedInput);
    procedure MapInput(const AInput: TAffectedInput);
    function ProjectFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    /// <summary>Geänderte Symbole, die verfolgt werden, und ihre Änderungen (AChanges, gleiche Reihenfolge).
    /// </summary>
    function SymbolStarts(out AChanges: TArray<TAffectedChange>): TArray<THierarchyItem>;
    procedure AddImpactTests(const AFound: TImpactResult; const AStart: THierarchyItem;
      const AChange: TAffectedChange);
    procedure TraceSymbols(AResolver: TNameResolver; const ACancellation: IJsonRpcCancellationToken);
    /// <summary>Umgekehrte uses-Beziehung (AUsers) und Units (AUnits) der Projekt-Units.</summary>
    procedure ReadUses(AUsers: TObjectDictionary<string, TList<string>>; AUnits: TDictionary<string, TUnitIndex>);
    /// <summary>Alle Tests der Testunit AFound.</summary>
    procedure AddUnitTests(const AFound: TUnitIndex; const AReason: TAffectedReason);
    /// <summary>Verfolgt die ganz geänderte Unit AChange über ihre Verwender bis zur Tiefe.</summary>
    procedure TraceUnit(const AChange: TAffectedChange; AUsers: TObjectDictionary<string, TList<string>>;
      AUnits: TDictionary<string, TUnitIndex>);
    procedure TraceUnits;
    function FixtureTestCount(const ATest: TAffectedTest): Integer;
    function FixtureRunNames(const ATest: TAffectedTest): TArray<string>;
    /// <summary>Alle Tests nötig, wenn die Analyse an eine Grenze (Zeit, Stellen) kam.</summary>
    procedure CheckLimits;
    /// <summary>Gesammelte Tests, zusammengefasst und sortiert.</summary>
    function CollectedTests: TArray<TAffectedTest>;
  public
    constructor Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const ARequest: TAffectedRequest);
    destructor Destroy; override;
    function Run(AResolver: TNameResolver; const AInputs: TArray<TAffectedInput>;
      const ACancellation: IJsonRpcCancellationToken): TAffectedResult;
  end;

constructor TAffectedRun.Create(const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
  const ARequest: TAffectedRequest);
begin
  inherited Create;
  FIndex := AIndex;
  FReadText := AReadText;
  FRequest := ARequest;
  FTests := TDictionary<string, TAffectedTest>.Create;
  FOrder := TList<string>.Create;
  FSources := TDictionary<string, TDUnitXUnit>.Create;
end;

destructor TAffectedRun.Destroy;
begin
  FSources.Free;
  FOrder.Free;
  FTests.Free;
  inherited;
end;

function TAffectedRun.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := Assigned(FReadText) and FReadText(AFileName, AText);
end;

function TAffectedRun.SourceOf(const AFileName: string): TDUnitXUnit;
var
  mText: string;
begin
  if FSources.TryGetValue(UpperCase(AFileName), Result) then
  begin
    Exit;
  end;
  Result := Default(TDUnitXUnit);
  if ReadText(AFileName, mText) then
  begin
    Result := TDUnitXSource.Scan(TTextLines.SplitLines(mText));
  end;
  FSources.Add(UpperCase(AFileName), Result);
end;

procedure TAffectedRun.Skip(const AFileName, AReason: string);
var
  mSkipped: TAffectedSkipped;
begin
  mSkipped.FileName := AFileName;
  mSkipped.Reason := AReason;
  FResult.Skipped := FResult.Skipped + [mSkipped];
end;

procedure TAffectedRun.NeedAll(const AReason: string);
begin
  // Der erste Grund zählt; weitere ändern am Ergebnis nichts.
  if FResult.All then
  begin
    Exit;
  end;
  FResult.All := True;
  FResult.AllReason := AReason;
end;

procedure TAffectedRun.AddTest(const ATest: TAffectedTest; const AReason: TAffectedReason);
var
  mKey: string;
  mTest: TAffectedTest;
begin
  mKey := UpperCase(ATest.Name);
  if not FTests.TryGetValue(mKey, mTest) then
  begin
    mTest := ATest;
    mTest.Reasons := nil;
    FOrder.Add(mKey);
  end;
  AddReason(mTest, AReason);
  FTests.AddOrSetValue(mKey, mTest);
end;

function TAffectedRun.ProjectFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
begin
  Result := FIndex.FindFile(AFileName, AUnit) and not AUnit.Library_;
  if not Result then
  begin
    AUnit := Default(TUnitIndex);
    Result := ContainsFile(FRequest.Files, AFileName);
  end;
end;

procedure TAffectedRun.MapProject(const AInput: TAffectedInput; const AExt: string);
var
  mProgram: string;
begin
  for mProgram in FRequest.TestPrograms do
  begin
    if SameFile(ChangeFileExt(mProgram, AExt), AInput.FileName) then
    begin
      NeedAll(cTexts[TAffectedTestsText.TestProgramChanged].Fmt([ExtractFileName(AInput.FileName)]));
      Exit;
    end;
  end;
  Skip(AInput.FileName, cTexts[TAffectedTestsText.ProjectFileOfAnotherProject].Text);
end;

procedure TAffectedRun.MapUnit(const AInput: TAffectedInput);
var
  mLines: TChangedLines;
  mWhole: TLineSpan;
  mUnit: TUnitIndex;
  mText: string;
  mChanges: TArray<TAffectedChange>;
begin
  mLines := AInput.Lines;
  if not AInput.HasLines then
  begin
    mWhole.First := 0;
    mWhole.Last := MaxInt;
    mLines.Spans := [mWhole];
    mLines.Gaps := nil;
  end;
  if not ProjectFile(AInput.FileName, mUnit) then
  begin
    Skip(AInput.FileName, cTexts[TAffectedTestsText.NotInTheProjects].Text);
  end
  else if not ReadText(AInput.FileName, mText) then
  begin
    NeedAll(cTexts[TAffectedTestsText.NotReadable].Fmt([ExtractFileName(AInput.FileName)]));
  end
  else
  begin
    mChanges := TAffectedTests.MapPascal(AInput.FileName, mText, mLines);
    FResult.Changes := FResult.Changes + mChanges;
    if mChanges = nil then
    begin
      Skip(AInput.FileName, cTexts[TAffectedTestsText.OnlyBlankLinesOrComments].Text);
    end;
  end;
end;

/// <summary>Änderung an der Klasse AClass des Formulars AFormFile, deklariert in AUnit; False ohne Klasse.
/// </summary>
function FormChange(const AUnit: TUnitIndex; const AUnitFile, AFormFile, AClass: string;
  out AChange: TAffectedChange): Boolean;
var
  mIndex: Integer;
begin
  AChange := Default(TAffectedChange);
  for mIndex in AUnit.SymbolsNamed(AClass) do
  begin
    if (AUnit.Symbols[mIndex].Kind = TIndexSymbolKind.ClassType) and (AUnit.Symbols[mIndex].Container = '') then
    begin
      AChange.Kind := TAffectedChangeKind.Symbol;
      AChange.Item := TLspHierarchies.ItemOf(AUnit.UnitName, AUnitFile, AUnit.Symbols[mIndex]);
      AChange.Source := AFormFile;
      AChange.Place := cTexts[TAffectedTestsText.Form].Text;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAffectedRun.MapForm(const AInput: TAffectedInput);
var
  mText, mClass, mUnitFile, mUnitText: string;
  mUnit: TUnitIndex;
  mChange: TAffectedChange;
begin
  mUnitFile := ChangeFileExt(AInput.FileName, '.pas');
  if not ProjectFile(mUnitFile, mUnit) then
  begin
    Skip(AInput.FileName, cTexts[TAffectedTestsText.UnitNotInTheProjects].Text);
    Exit;
  end;
  if not ReadText(AInput.FileName, mText) or not ReadText(mUnitFile, mUnitText) then
  begin
    NeedAll(cTexts[TAffectedTestsText.NotReadable].Fmt([ExtractFileName(AInput.FileName)]));
    Exit;
  end;
  mClass := TAffectedTests.FormClass(mText);
  if (mClass <> '') and (mUnit.UnitName = '') then
  begin
    mUnit := TIndexExtractor.ExtractText(mUnitText, mUnitFile, nil, nil);
  end;
  if (mClass <> '') and FormChange(mUnit, mUnitFile, AInput.FileName, mClass, mChange) then
  begin
    FResult.Changes := FResult.Changes + [mChange];
  end
  else
  begin
    NeedAll(cTexts[TAffectedTestsText.FormClassOfNotFound].Fmt([ExtractFileName(AInput.FileName)]));
  end;
end;

/// <summary>Die Unit AIncluding als Ganzes, geändert über das Include AIncludeFile.</summary>
function IncludingUnitChange(const AIncluding: TUnitIndex; const AIncludeFile: string): TAffectedChange;
begin
  Result := Default(TAffectedChange);
  Result.Kind := TAffectedChangeKind.WholeUnit;
  Result.Item.Name := AIncluding.UnitName;
  Result.Item.UnitName := AIncluding.UnitName;
  Result.Item.FileName := AIncluding.FileName;
  Result.Source := AIncludeFile;
  Result.Place := 'Include';
end;

function TAffectedRun.MapIncluding(const AIncluding: TUnitIndex; const AIncludeFile: string): Boolean;
var
  mText: string;
  mChange, mIncluded: TAffectedChange;
  mMapped: Boolean;
begin
  Result := ReadText(AIncluding.FileName, mText);
  if not Result then
  begin
    NeedAll(cTexts[TAffectedTestsText.NotReadable].Fmt([ExtractFileName(AIncluding.FileName)]));
    Exit;
  end;
  // Die Stelle des {$I}; findet sie sich nicht (Name über einen Suchpfad), die ganze Unit.
  mMapped := False;
  for mChange in TAffectedTests.MapPascal(AIncluding.FileName, mText,
    TAffectedTests.IncludeLines(mText, AIncludeFile), 'Include') do
  begin
    mIncluded := mChange;
    mIncluded.Source := AIncludeFile;
    FResult.Changes := FResult.Changes + [mIncluded];
    mMapped := True;
  end;
  if not mMapped then
  begin
    FResult.Changes := FResult.Changes + [IncludingUnitChange(AIncluding, AIncludeFile)];
  end;
end;

procedure TAffectedRun.MapInclude(const AInput: TAffectedInput);
var
  mIncluding: TUnitIndex;
  mFound: Boolean;
begin
  mFound := False;
  for mIncluding in FIndex.Units do
  begin
    if mIncluding.Library_ or not ContainsFile(mIncluding.Includes, AInput.FileName) then
    begin
      Continue;
    end;
    mFound := True;
    if not MapIncluding(mIncluding, AInput.FileName) then
    begin
      Break;
    end;
  end;
  if not mFound then
  begin
    Skip(AInput.FileName, cTexts[TAffectedTestsText.NotUsedByAnyUnit].Text);
  end;
end;

procedure TAffectedRun.MapInput(const AInput: TAffectedInput);
var
  mExt: string;
begin
  mExt := LowerCase(ExtractFileExt(AInput.FileName));
  if MatchText(mExt, ['.dpr', '.dproj']) then
  begin
    MapProject(AInput, mExt);
  end
  else if MatchText(mExt, ['.pas']) then
  begin
    MapUnit(AInput);
  end
  else if MatchText(mExt, ['.dfm', '.fmx']) then
  begin
    MapForm(AInput);
  end
  else if MatchText(mExt, ['.inc']) then
  begin
    MapInclude(AInput);
  end
  else
  begin
    Skip(AInput.FileName, cTexts[TAffectedTestsText.NoDelphiSource].Text);
  end;
end;

function PlaceName(const AItem: THierarchyItem): string;
begin
  if AItem.Container <> '' then
  begin
    Result := AItem.Container + '.' + AItem.Name;
  end
  else
  begin
    Result := AItem.Name;
  end;
end;

function TAffectedRun.SymbolStarts(out AChanges: TArray<TAffectedChange>): TArray<THierarchyItem>;
var
  mWholeFiles: TDictionary<string, Boolean>;
  mChange: TAffectedChange;
begin
  Result := nil;
  AChanges := nil;
  // Symbole einer Unit, die ohnehin als Ganzes verfolgt wird, bringen keine weiteren Tests (jeder Weg über
  // Verweise führt auch über uses).
  mWholeFiles := TDictionary<string, Boolean>.Create;
  try
    for mChange in FResult.Changes do
    begin
      if mChange.Kind = TAffectedChangeKind.WholeUnit then
      begin
        mWholeFiles.AddOrSetValue(UpperCase(mChange.Item.FileName), True);
      end;
    end;
    for mChange in FResult.Changes do
    begin
      if (mChange.Kind = TAffectedChangeKind.Symbol) and
        not mWholeFiles.ContainsKey(UpperCase(mChange.Item.FileName)) then
      begin
        Result := Result + [mChange.Item];
        AChanges := AChanges + [mChange];
      end;
    end;
  finally
    mWholeFiles.Free;
  end;
end;

/// <summary>Stelle des Tests ATestIndex in AFound.Places; -1, wenn das geänderte Symbol selbst der Test ist.
/// </summary>
function PlaceOfTest(const AFound: TImpactResult; ATestIndex: Integer): Integer;
var
  mStep: Integer;
begin
  for mStep := 0 to High(AFound.Places) do
  begin
    if AFound.Places[mStep].Test = ATestIndex then
    begin
      Exit(mStep);
    end;
  end;
  Result := -1;
end;

/// <summary>Weg von der Stelle APlace über die Ursachen zurück zum geänderten Symbol, das Symbol zuerst.
/// AInferred: ein Schritt ist nicht sicher.</summary>
function ImpactPath(const AFound: TImpactResult; APlace: Integer; out AInferred: Boolean): TArray<string>;
var
  mStep: Integer;
begin
  Result := nil;
  AInferred := False;
  mStep := APlace;
  while mStep >= 0 do
  begin
    Result := TArray<string>.Create(PlaceName(AFound.Places[mStep].Item)) + Result;
    AInferred := AInferred or not AFound.Places[mStep].Confidence.IsSure;
    mStep := AFound.Places[mStep].Cause;
  end;
end;

/// <summary>Test ATestIndex aus AFound; AStart ist das geänderte Symbol.</summary>
function ImpactTest(const AFound: TImpactResult; ATestIndex, APlace: Integer;
  const AStart: THierarchyItem): TAffectedTest;
var
  mItem: THierarchyItem;
begin
  Result := Default(TAffectedTest);
  Result.Name := AFound.Tests[ATestIndex].Name;
  Result.RunNames := AFound.Tests[ATestIndex].RunNames;
  Result.FileName := AFound.Tests[ATestIndex].FileName;
  Result.Line := AFound.Tests[ATestIndex].Line;
  // Ohne Stelle ist das geänderte Symbol selbst der Test (Ebene 0).
  mItem := AStart;
  if APlace >= 0 then
  begin
    mItem := AFound.Places[APlace].Item;
  end;
  Result.Fixture := mItem.Container;
  Result.Method := mItem.Name;
  Result.UnitName := mItem.UnitName;
  if (Result.UnitName = '') and EndsText('.' + Result.Fixture + '.' + Result.Method, Result.Name) then
  begin
    Result.UnitName := Copy(Result.Name, 1, Length(Result.Name) - Length(Result.Fixture + Result.Method) - 2);
  end;
end;

procedure TAffectedRun.AddImpactTests(const AFound: TImpactResult; const AStart: THierarchyItem;
  const AChange: TAffectedChange);
var
  mTestIndex, mPlace: Integer;
  mReason: TAffectedReason;
begin
  for mTestIndex := 0 to High(AFound.Tests) do
  begin
    mPlace := PlaceOfTest(AFound, mTestIndex);
    mReason.Change := AChange.Text;
    mReason.Path := TArray<string>.Create(AChange.Text) + ImpactPath(AFound, mPlace, mReason.Inferred);
    AddTest(ImpactTest(AFound, mTestIndex, mPlace, AStart), mReason);
  end;
end;

procedure TAffectedRun.TraceSymbols(AResolver: TNameResolver; const ACancellation: IJsonRpcCancellationToken);
var
  mStarts: TArray<THierarchyItem>;
  mChanges: TArray<TAffectedChange>;
  mResults: TArray<TImpactResult>;
  mIndex: Integer;
begin
  mStarts := SymbolStarts(mChanges);
  if mStarts = nil then
  begin
    Exit;
  end;
  mResults := TImpactAnalysis.AnalyzeEach(AResolver, FIndex, mStarts, TImpactSources.Create(FRequest.Files,
    FReadText), FRequest.Options, ACancellation);
  for mIndex := 0 to High(mResults) do
  begin
    FResult.Limits := FResult.Limits + mResults[mIndex].Limits;
    AddImpactTests(mResults[mIndex], mStarts[mIndex], mChanges[mIndex]);
  end;
end;

procedure TAffectedRun.ReadUses(AUsers: TObjectDictionary<string, TList<string>>;
  AUnits: TDictionary<string, TUnitIndex>);
var
  mUnit: TUnitIndex;
  mUsed: string;
  mList: TList<string>;
begin
  for mUnit in FIndex.Units do
  begin
    if mUnit.Library_ or (mUnit.UnitName = '') then
    begin
      Continue;
    end;
    AUnits.AddOrSetValue(UpperCase(mUnit.UnitName), mUnit);
    for mUsed in mUnit.InterfaceUses + mUnit.ImplementationUses do
    begin
      if not AUsers.TryGetValue(UpperCase(mUsed), mList) then
      begin
        mList := TList<string>.Create;
        AUsers.Add(UpperCase(mUsed), mList);
      end;
      if not mList.Contains(mUnit.UnitName) then
      begin
        mList.Add(mUnit.UnitName);
      end;
    end;
  end;
end;

procedure TAffectedRun.AddUnitTests(const AFound: TUnitIndex; const AReason: TAffectedReason);
var
  mSource: TDUnitXUnit;
  mFixture, mTestIndex: Integer;
  mTest: TAffectedTest;
begin
  mSource := SourceOf(AFound.FileName);
  for mFixture := 0 to High(mSource.Fixtures) do
  begin
    for mTestIndex := 0 to High(mSource.Fixtures[mFixture].Tests) do
    begin
      mTest := Default(TAffectedTest);
      mTest.UnitName := mSource.UnitName;
      mTest.Fixture := mSource.Fixtures[mFixture].Name;
      // Alle Tests der Unit: Collapse fasst sie zur Fixture zusammen.
      mTest.Method := '';
      mTest.Name := TDUnitXCommandLine.TestName(mTest.UnitName, mTest.Fixture,
        mSource.Fixtures[mFixture].Tests[mTestIndex].Method);
      mTest.RunNames := TDUnitXCommandLine.RunNames(mSource, mFixture, mTestIndex, -1);
      mTest.FileName := AFound.FileName;
      mTest.Line := mSource.Fixtures[mFixture].Line;
      AddTest(mTest, AReason);
    end;
  end;
end;

/// <summary>Verwender von AName, die noch keinen Weg haben, mit Weg in APaths und in ANext.</summary>
procedure AddUsers(const AName: string; AUsers: TObjectDictionary<string, TList<string>>;
  APaths: TDictionary<string, TArray<string>>; ANext: TList<string>);
var
  mList: TList<string>;
  mUser: string;
begin
  if not AUsers.TryGetValue(UpperCase(AName), mList) then
  begin
    Exit;
  end;
  for mUser in mList do
  begin
    if not APaths.ContainsKey(UpperCase(mUser)) then
    begin
      APaths.Add(UpperCase(mUser), APaths[UpperCase(AName)] + TArray<string>.Create('Unit ' + mUser));
      ANext.Add(mUser);
    end;
  end;
end;

procedure TAffectedRun.TraceUnit(const AChange: TAffectedChange; AUsers: TObjectDictionary<string, TList<string>>;
  AUnits: TDictionary<string, TUnitIndex>);
var
  mFrontier, mLevelNext: TList<string>;
  mPaths: TDictionary<string, TArray<string>>;
  mLevel: Integer;
  mName: string;
  mFound: TUnitIndex;
  mReason: TAffectedReason;
begin
  mFrontier := TList<string>.Create;
  mLevelNext := TList<string>.Create;
  mPaths := TDictionary<string, TArray<string>>.Create;
  try
    mFrontier.Add(AChange.Item.Name);
    mPaths.Add(UpperCase(AChange.Item.Name), TArray<string>.Create(AChange.Text));
    mReason.Change := AChange.Text;
    mReason.Inferred := False;
    // Ebene 0 ist die Unit selbst (eine geänderte Testunit), dann je Ebene ihre Verwender.
    mLevel := 0;
    while (mLevel <= FRequest.Options.Depth) and (mFrontier.Count > 0) do
    begin
      mLevelNext.Clear;
      for mName in mFrontier do
      begin
        if FRequest.Options.Tests.Contains(mName) and AUnits.TryGetValue(UpperCase(mName), mFound) then
        begin
          mReason.Path := mPaths[UpperCase(mName)];
          AddUnitTests(mFound, mReason);
        end;
        if mLevel < FRequest.Options.Depth then
        begin
          AddUsers(mName, AUsers, mPaths, mLevelNext);
        end;
      end;
      mFrontier.Clear;
      mFrontier.AddRange(mLevelNext.ToArray);
      Inc(mLevel);
    end;
  finally
    mPaths.Free;
    mLevelNext.Free;
    mFrontier.Free;
  end;
end;

procedure TAffectedRun.TraceUnits;
var
  mUsers: TObjectDictionary<string, TList<string>>;
  mUnits: TDictionary<string, TUnitIndex>;
  mChange: TAffectedChange;
begin
  if FResult.All then
  begin
    Exit;
  end;
  mUsers := nil;
  mUnits := TDictionary<string, TUnitIndex>.Create;
  try
    for mChange in FResult.Changes do
    begin
      if mChange.Kind <> TAffectedChangeKind.WholeUnit then
      begin
        Continue;
      end;
      if mUsers = nil then
      begin
        // Umgekehrte uses-Beziehung der Projekt-Units, einmal für alle ganzen Units.
        mUsers := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
        ReadUses(mUsers, mUnits);
      end;
      TraceUnit(mChange, mUsers, mUnits);
    end;
  finally
    mUnits.Free;
    mUsers.Free;
  end;
end;

function TAffectedRun.FixtureTestCount(const ATest: TAffectedTest): Integer;
var
  mSource: TDUnitXUnit;
  mFixture, mTestIndex: Integer;
begin
  mSource := SourceOf(ATest.FileName);
  Result := 0;
  if mSource.Find(ATest.Fixture, '', mFixture, mTestIndex) then
  begin
    Result := Length(mSource.Fixtures[mFixture].Tests);
  end;
end;

function TAffectedRun.FixtureRunNames(const ATest: TAffectedTest): TArray<string>;
var
  mSource: TDUnitXUnit;
  mFixture, mTestIndex: Integer;
begin
  mSource := SourceOf(ATest.FileName);
  Result := nil;
  if mSource.Find(ATest.Fixture, '', mFixture, mTestIndex) then
  begin
    Result := TDUnitXCommandLine.RunNames(mSource, mFixture, -1, -1);
  end;
end;

procedure TAffectedRun.CheckLimits;
begin
  // Unvollständig verfolgt: Es können Tests fehlen. Die Tiefe dagegen ist gewollt.
  if TImpactLimit.Time in FResult.Limits then
  begin
    NeedAll(cTexts[TAffectedTestsText.TimeLimitOfTheAnalysis].Text);
  end
  else if TImpactLimit.Count in FResult.Limits then
  begin
    NeedAll(cTexts[TAffectedTestsText.MoreThanAffectedPlaces].Fmt([TImpactAnalysis.cMaxPlaces]));
  end;
end;

function TAffectedRun.CollectedTests: TArray<TAffectedTest>;
var
  mKey: string;
  mTests: TArray<TAffectedTest>;
begin
  mTests := nil;
  for mKey in FOrder do
  begin
    mTests := mTests + [FTests[mKey]];
  end;
  Result := TAffectedTests.Collapse(mTests,
    function(ATest: TAffectedTest): Integer
    begin
      Result := FixtureTestCount(ATest);
    end,
    function(ATest: TAffectedTest): TArray<string>
    begin
      Result := FixtureRunNames(ATest);
    end);
  TAffectedTests.Sort(Result);
end;

function TAffectedRun.Run(AResolver: TNameResolver; const AInputs: TArray<TAffectedInput>;
  const ACancellation: IJsonRpcCancellationToken): TAffectedResult;
var
  mInput: TAffectedInput;
begin
  FResult := Default(TAffectedResult);
  FResult.Base := FRequest.Base;
  FResult.Depth := FRequest.Options.Depth;
  for mInput in AInputs do
  begin
    if ACancellation <> nil then
    begin
      ACancellation.ThrowIfCancellationRequested;
    end;
    MapInput(mInput);
  end;
  if not FResult.All then
  begin
    TraceSymbols(AResolver, ACancellation);
    CheckLimits;
  end;
  if not FResult.All then
  begin
    TraceUnits;
    FResult.Tests := CollectedTests;
  end;
  Result := FResult;
end;

class function TAffectedTests.Determine(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AInputs: TArray<TAffectedInput>; const ARequest: TAffectedRequest; const AReadText: TReferenceReadText;
  const ACancellation: IJsonRpcCancellationToken): TAffectedResult;
var
  mRun: TAffectedRun;
begin
  mRun := TAffectedRun.Create(AIndex, AReadText, ARequest);
  try
    Result := mRun.Run(AResolver, AInputs, ACancellation);
  finally
    mRun.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.AffectedTests', cTexts);

end.
