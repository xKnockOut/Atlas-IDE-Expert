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
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.ChangedFiles,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Hierarchies,
  Atlas.Common.Lsp.Impact;

type
{$SCOPEDENUMS ON}
  /// <summary>Was sich geändert hat: ein Symbol oder die Unit als Ganzes (uses, initialization).</summary>
  TAffectedChangeKind = (Symbol, WholeUnit);
  /// <summary>Ausgabe von --affected-tests und get_affected_tests.</summary>
  TAffectedFormat = (Text, Json, DUnitX);
{$SCOPEDENUMS OFF}

  TAffectedChange = record
    Kind: TAffectedChangeKind;
    /// <summary>Das geänderte Symbol; bei WholeUnit Name und UnitName = Unit, FileName = ihre Datei.</summary>
    Item: THierarchyItem;
    /// <summary>Geänderte Datei (bei .dfm und .inc diese, sonst die Unit).</summary>
    Source: string;
    /// <summary>Wo die Änderung liegt: interface, implementation, initialization, Formular, Include.</summary>
    Place: string;
    /// <summary>"TBaseline.Match" bzw. "Unit Atlas.Foo".</summary>
    function Text: string;
  end;

  /// <summary>Geänderte Datei, die keine Tests betrifft, mit Grund.</summary>
  TAffectedSkipped = record
    FileName: string;
    Reason: string;
  end;

  TAffectedReason = record
    /// <summary>Text der geänderten Stelle (TAffectedChange.Text).</summary>
    Change: string;
    /// <summary>Weg von der geänderten Stelle bis zum Test, beide eingeschlossen.</summary>
    Path: TArray<string>;
    /// <summary>Ein Schritt des Wegs ist erschlossen (#1119), nicht sicher.</summary>
    Inferred: Boolean;
    /// <summary>"TBaseline.Match → TFoo.Bar → TFooTests.Test" mit „(erschlossen)“.</summary>
    function Text: string;
  end;

  TAffectedTest = record
    /// <summary>Unit.Fixture.Methode, bei einer ganzen Fixture Unit.Fixture.</summary>
    Name: string;
    /// <summary>Namen für --run bzw. run_tests (bei [TestCase] je Fall).</summary>
    RunNames: TArray<string>;
    UnitName: string;
    Fixture: string;
    /// <summary>'' = die ganze Fixture.</summary>
    Method: string;
    FileName: string;
    /// <summary>0-basiert: Kopf der Testmethode bzw. Deklaration der Fixture.</summary>
    Line: Integer;
    Reasons: TArray<TAffectedReason>;
  end;

  /// <summary>Geänderte Datei mit ihren Zeilen; ohne Zeilen (HasLines = False) gilt sie als ganz geändert.</summary>
  TAffectedInput = record
    FileName: string;
    Lines: TChangedLines;
    HasLines: Boolean;
  end;

  TAffectedRequest = record
    /// <summary>Projektdateien aller Projekte (Referenzsuche).</summary>
    Files: TArray<string>;
    /// <summary>Hauptdateien der Testprogramme (.dpr); ihre Änderung betrifft alle Tests.</summary>
    TestPrograms: TArray<string>;
    /// <summary>Tiefe, Treffersicherheit, Testunits und Zeitlimit je Symbol.</summary>
    Options: TImpactOptions;
    /// <summary>Nur für die Ausgabe: Ref, Revision oder BASE.</summary>
    Base: string;
  end;

  TAffectedResult = record
    Base: string;
    Depth: Integer;
    /// <summary>Alle Tests sind nötig (AllReason sagt warum).</summary>
    All: Boolean;
    AllReason: string;
    Changes: TArray<TAffectedChange>;
    Skipped: TArray<TAffectedSkipped>;
    Tests: TArray<TAffectedTest>;
    Limits: TImpactLimits;
    /// <summary>Alle Namen für --run bzw. run_tests, ohne Doppelte, in Reihenfolge der Tests.</summary>
    function RunNames: TArray<string>;
  end;

  TAffectedTests = class
  public const
    Method = 'atlas/affectedTests';
    DefaultDepth = 3;
    /// <summary>Mehr als so viel Prozent der Tests einer Fixture betroffen: die ganze Fixture.</summary>
    FixturePercent = 80;
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
    class function TryParseFormat(const AText: string; out AFormat: TAffectedFormat): Boolean; static;
    class function Render(const AResult: TAffectedResult; AFormat: TAffectedFormat): string; static;
    /// <summary>Bericht für Menschen.</summary>
    class function ToText(const AResult: TAffectedResult): string; static;
    /// <summary>Antwort von atlas/affectedTests und get_affected_tests mit format json; der Aufrufer übernimmt das
    /// Objekt.</summary>
    class function ToJson(const AResult: TAffectedResult): TJSONObject; static;
    /// <summary>Argument --run:… für die Test-exe; '' bei allen Tests, ohne Tests oder wenn es zu lang wird
    /// (dann False).</summary>
    class function DUnitXArgument(const AResult: TAffectedResult; out AArgument: string): Boolean; static;
    /// <summary>Gelesenes Ergebnis von atlas/affectedTests (Plugin, Tests).</summary>
    class function FromJson(const AValue: TJSONValue): TAffectedResult; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.ReferenceConfidence,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX;

const
  cArrow = ' → ';

{ TAffectedChange }

function TAffectedChange.Text: string;
begin
  if Kind = TAffectedChangeKind.WholeUnit then
    Result := 'Unit ' + Item.Name
  else if Item.Container <> '' then
    Result := Item.Container + '.' + Item.Name
  else
    Result := Item.Name;
end;

{ TAffectedReason }

function TAffectedReason.Text: string;
begin
  Result := string.Join(cArrow, Path);
  if Result = '' then
    Result := Change;
  if Inferred then
    Result := Result + ' (erschlossen)';
end;

{ TAffectedResult }

function TAffectedResult.RunNames: TArray<string>;
var
  mTest: TAffectedTest;
  mName: string;
  mSeen: TDictionary<string, Boolean>;
begin
  Result := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mTest in Tests do
      for mName in mTest.RunNames do
        if not mSeen.ContainsKey(UpperCase(mName)) then
        begin
          mSeen.Add(UpperCase(mName), True);
          Result := Result + [mName];
        end;
  finally
    mSeen.Free;
  end;
end;

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

constructor TAffectedSource.Create(const AFileName, AText: string);
var
  mToken: TPascalToken;
  mLine, mCount: Integer;
begin
  inherited Create;
  FFileName := AFileName;
  mCount := Length(TTextLines.SplitLines(AText));
  SetLength(FCode, mCount);
  for mLine := 0 to mCount - 1 do
    FCode[mLine] := TTextPosition.Create(mLine, -1);
  FImplementationLine := MaxInt;
  FInitializationLine := MaxInt;
  for mToken in TPascalLexer.Tokenize(AText) do
  begin
    if mToken.Kind = TPascalTokenKind.Comment then
      Continue;
    // Zeilen, die ein mehrzeiliges Token (String) überspannt, zählen als Code ab Spalte 0.
    for mLine := mToken.StartPos.Line to mToken.EndPos.Line do
    begin
      if (mLine < 0) or (mLine >= mCount) or (FCode[mLine].Character >= 0) then
        Continue;
      if mLine = mToken.StartPos.Line then
        FCode[mLine] := mToken.StartPos
      else
        FCode[mLine] := TTextPosition.Create(mLine, 0);
    end;
    // initialization und finalization sind reservierte Wörter und stehen nur auf Unit-Ebene.
    if mToken.IsKeyword('implementation') and (FImplementationLine = MaxInt) then
      FImplementationLine := mToken.StartPos.Line
    else if (FInitializationLine = MaxInt) and
      (mToken.IsKeyword('initialization') or mToken.IsKeyword('finalization')) then
      FInitializationLine := mToken.StartPos.Line;
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
    Result := 'initialization'
  else if ALine >= FImplementationLine then
    Result := 'implementation'
  else
    Result := 'interface';
end;

function TAffectedSource.KeyOf(const AChange: TAffectedChange): string;
begin
  if AChange.Kind = TAffectedChangeKind.WholeUnit then
    Result := 'unit|' + UpperCase(AChange.Item.FileName)
  else
    Result := UpperCase(AChange.Item.FileName) + '|' + IntToStr(AChange.Item.SelectionRange.StartPos.Line) + ':' +
      IntToStr(AChange.Item.SelectionRange.StartPos.Character);
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
    Result.Item.Name := ChangeFileExt(ExtractFileName(FFileName), '');
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
    Result.Place := SectionOf(ALine);
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
    for mSymbol in FUnit.Symbols do
      // Symbole aus Include-Dateien tragen deren Zeilen.
      if (mSymbol.FileName = '') and RangeHas(mSymbol.Range, mPosition) and
        (not mFound or (SpanSize(mSymbol.Range) < SpanSize(mBest.Range))) then
      begin
        mBest := mSymbol;
        mFound := True;
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
    mAbove := Length(FCode) - 1;
  while (mAbove >= 0) and not HasCode(mAbove) do
    Dec(mAbove);
  mBelow := AGap;
  while (mBelow < Length(FCode)) and not HasCode(mBelow) do
    Inc(mBelow);
  // Am Anfang oder Ende der Datei: nichts, was die Zeilen umschloss.
  if (mAbove < 0) or (mBelow >= Length(FCode)) then
    Exit;
  mBefore := ChangeAt(mAbove, '');
  mAfter := ChangeAt(mBelow, '');
  if KeyOf(mBefore) = KeyOf(mAfter) then
    AChange := mBefore
  else
    // Zwischen zwei Symbolen entfernt (z. B. eine ganze Routine): Was fehlt, lässt sich nicht mehr verfolgen.
    AChange := UnitChange(SectionOf(mBelow));
  Result := True;
end;

procedure TAffectedSource.Add(var AChanges: TArray<TAffectedChange>; const AChange: TAffectedChange);
var
  mChange: TAffectedChange;
  mKey: string;
begin
  mKey := KeyOf(AChange);
  for mChange in AChanges do
    if KeyOf(mChange) = mKey then
      Exit;
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
        mLast := mSource.LineCount - 1;
      for mLine := mSpan.First to mLast do
        if mSource.HasCode(mLine) then
          mSource.Add(Result, mSource.ChangeAt(mLine, ''));
    end;
    for mGap in ALines.Gaps do
      if mSource.ChangeAtGap(mGap, mChange) then
        mSource.Add(Result, mChange);
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
      if mSource.HasCode(mLine) then
        mSource.Add(Result, mSource.ChangeAt(mLine, APlace));
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
      Continue;
    // object Form1: TForm1 | inherited Form2: TForm2 | inline Frame1: TFrame1 [n]
    if not (StartsText('object ', mRest) or StartsText('inherited ', mRest) or StartsText('inline ', mRest)) then
      Exit;
    mColon := Pos(':', mRest);
    if mColon = 0 then
      Exit;
    Result := Trim(Copy(mRest, mColon + 1, MaxInt));
    if Pos(' ', Result) > 0 then
      Result := Copy(Result, 1, Pos(' ', Result) - 1);
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
    for mName in TChangedFiles.IncludeNames(mLines[mIndex]) do
      if SameText(BaseNameOf(mName), BaseNameOf(AIncludeFile)) or
        ((Pos('.', BaseNameOf(mName)) = 0) and SameText(BaseNameOf(mName) + '.inc', BaseNameOf(AIncludeFile))) then
      begin
        Result := Result + [mIndex];
        Break;
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
    if SameFile(mFile, AFileName) then
      Exit(True);
  Result := False;
end;

function CompareTests(const A, B: TAffectedTest): Integer;
begin
  Result := CompareText(A.Name, B.Name);
  if Result = 0 then
    Result := CompareStr(A.Name, B.Name);
end;

function CompareReasons(const A, B: TAffectedReason): Integer;
begin
  Result := CompareText(A.Text, B.Text);
  if Result = 0 then
    Result := CompareStr(A.Text, B.Text);
end;

class procedure TAffectedTests.Sort(var ATests: TArray<TAffectedTest>);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATests) do
    TArray.Sort<TAffectedReason>(ATests[mIndex].Reasons, TComparer<TAffectedReason>.Construct(CompareReasons));
  TArray.Sort<TAffectedTest>(ATests, TComparer<TAffectedTest>.Construct(CompareTests));
end;

procedure AddReason(var ATest: TAffectedTest; const AReason: TAffectedReason);
var
  mReason: TAffectedReason;
begin
  for mReason in ATest.Reasons do
    if mReason.Text = AReason.Text then
      Exit;
  ATest.Reasons := ATest.Reasons + [AReason];
end;

class function TAffectedTests.Collapse(const ATests: TArray<TAffectedTest>;
  const ATotal: TFunc<TAffectedTest, Integer>; const AFixtureRun: TFunc<TAffectedTest, TArray<string>>):
  TArray<TAffectedTest>;
var
  mGroups: TDictionary<string, TList<Integer>>;
  mOrder: TList<string>;
  mKey: string;
  mIndex, mTotal: Integer;
  mMembers: TList<Integer>;
  mWhole: TAffectedTest;
  mReason: TAffectedReason;
begin
  Result := nil;
  mGroups := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  mOrder := TList<string>.Create;
  try
    for mIndex := 0 to High(ATests) do
    begin
      mKey := UpperCase(ATests[mIndex].FileName + '|' + ATests[mIndex].Fixture);
      if not mGroups.TryGetValue(mKey, mMembers) then
      begin
        mMembers := TList<Integer>.Create;
        mGroups.Add(mKey, mMembers);
        mOrder.Add(mKey);
      end;
      mMembers.Add(mIndex);
    end;
    for mKey in mOrder do
    begin
      mMembers := mGroups[mKey];
      mTotal := ATotal(ATests[mMembers[0]]);
      // Schon eine ganze Fixture (ganze Unit geändert) oder mehr als FixturePercent Prozent betroffen.
      if (ATests[mMembers[0]].Method = '') or
        ((mTotal > 0) and (mMembers.Count * 100 > mTotal * FixturePercent)) then
      begin
        mWhole := ATests[mMembers[0]];
        mWhole.Method := '';
        mWhole.Name := TDUnitXCommandLine.TestName(mWhole.UnitName, mWhole.Fixture, '');
        mWhole.RunNames := AFixtureRun(mWhole);
        if mWhole.RunNames = nil then
          mWhole.RunNames := [mWhole.Name];
        mWhole.Reasons := nil;
        for mIndex in mMembers do
          for mReason in ATests[mIndex].Reasons do
            AddReason(mWhole, mReason);
        Result := Result + [mWhole];
      end
      else
        for mIndex in mMembers do
          Result := Result + [ATests[mIndex]];
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
    procedure MapInput(const AInput: TAffectedInput);
    function ProjectFile(const AFileName: string; out AUnit: TUnitIndex): Boolean;
    procedure TraceSymbols(AResolver: TNameResolver; const ACancellation: IJsonRpcCancellationToken);
    procedure TraceUnits;
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
    Exit;
  Result := Default(TDUnitXUnit);
  if ReadText(AFileName, mText) then
    Result := TDUnitXSource.Scan(TTextLines.SplitLines(mText));
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
    Exit;
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

procedure TAffectedRun.MapInput(const AInput: TAffectedInput);
var
  mExt, mText, mClass, mUnitFile, mUnitText: string;
  mLines: TChangedLines;
  mWhole: TLineSpan;
  mUnit, mIncluding: TUnitIndex;
  mIndex: Integer;
  mChange, mIncluded: TAffectedChange;
  mFound, mMapped: Boolean;
  mProgram: string;
begin
  mExt := LowerCase(ExtractFileExt(AInput.FileName));
  mLines := AInput.Lines;
  if not AInput.HasLines then
  begin
    mWhole.First := 0;
    mWhole.Last := MaxInt;
    mLines.Spans := [mWhole];
    mLines.Gaps := nil;
  end;
  if MatchText(mExt, ['.dpr', '.dproj']) then
  begin
    for mProgram in FRequest.TestPrograms do
      if SameFile(ChangeFileExt(mProgram, mExt), AInput.FileName) then
      begin
        NeedAll(Format('Testprogramm %s geändert', [ExtractFileName(AInput.FileName)]));
        Exit;
      end;
    Skip(AInput.FileName, 'Projektdatei eines anderen Projekts');
  end
  else if MatchText(mExt, ['.pas']) then
  begin
    if not ProjectFile(AInput.FileName, mUnit) then
      Skip(AInput.FileName, 'nicht in den Projekten')
    else if not ReadText(AInput.FileName, mText) then
      NeedAll(Format('%s nicht lesbar', [ExtractFileName(AInput.FileName)]))
    else
    begin
      mFound := False;
      for mChange in TAffectedTests.MapPascal(AInput.FileName, mText, mLines) do
      begin
        FResult.Changes := FResult.Changes + [mChange];
        mFound := True;
      end;
      if not mFound then
        Skip(AInput.FileName, 'nur Leerzeilen oder Kommentare');
    end;
  end
  else if MatchText(mExt, ['.dfm', '.fmx']) then
  begin
    mUnitFile := ChangeFileExt(AInput.FileName, '.pas');
    if not ProjectFile(mUnitFile, mUnit) then
      Skip(AInput.FileName, 'Unit nicht in den Projekten')
    else if not ReadText(AInput.FileName, mText) or not ReadText(mUnitFile, mUnitText) then
      NeedAll(Format('%s nicht lesbar', [ExtractFileName(AInput.FileName)]))
    else
    begin
      mClass := TAffectedTests.FormClass(mText);
      mChange := Default(TAffectedChange);
      mFound := False;
      if mClass <> '' then
      begin
        if mUnit.UnitName = '' then
          mUnit := TIndexExtractor.ExtractText(mUnitText, mUnitFile, nil, nil);
        for mIndex in mUnit.SymbolsNamed(mClass) do
          if (mUnit.Symbols[mIndex].Kind = TIndexSymbolKind.ClassType) and (mUnit.Symbols[mIndex].Container = '') then
          begin
            mChange.Kind := TAffectedChangeKind.Symbol;
            mChange.Item := TLspHierarchies.ItemOf(mUnit.UnitName, mUnitFile, mUnit.Symbols[mIndex]);
            mChange.Source := AInput.FileName;
            mChange.Place := 'Formular';
            mFound := True;
            Break;
          end;
      end;
      if mFound then
        FResult.Changes := FResult.Changes + [mChange]
      else
        NeedAll(Format('Formularklasse von %s nicht gefunden', [ExtractFileName(AInput.FileName)]));
    end;
  end
  else if MatchText(mExt, ['.inc']) then
  begin
    mFound := False;
    for mIncluding in FIndex.Units do
    begin
      if mIncluding.Library_ or not ContainsFile(mIncluding.Includes, AInput.FileName) then
        Continue;
      mFound := True;
      if not ReadText(mIncluding.FileName, mText) then
      begin
        NeedAll(Format('%s nicht lesbar', [ExtractFileName(mIncluding.FileName)]));
        Break;
      end;
      // Die Stelle des {$I}; findet sie sich nicht (Name über einen Suchpfad), die ganze Unit.
      mMapped := False;
      for mChange in TAffectedTests.MapPascal(mIncluding.FileName, mText,
        TAffectedTests.IncludeLines(mText, AInput.FileName), 'Include') do
      begin
        mIncluded := mChange;
        mIncluded.Source := AInput.FileName;
        FResult.Changes := FResult.Changes + [mIncluded];
        mMapped := True;
      end;
      if not mMapped then
      begin
        mChange := Default(TAffectedChange);
        mChange.Kind := TAffectedChangeKind.WholeUnit;
        mChange.Item.Name := mIncluding.UnitName;
        mChange.Item.UnitName := mIncluding.UnitName;
        mChange.Item.FileName := mIncluding.FileName;
        mChange.Source := AInput.FileName;
        mChange.Place := 'Include';
        FResult.Changes := FResult.Changes + [mChange];
      end;
    end;
    if not mFound then
      Skip(AInput.FileName, 'von keiner Unit der Projekte eingebunden');
  end
  else
    Skip(AInput.FileName, 'keine Delphi-Quelle');
end;

function PlaceName(const AItem: THierarchyItem): string;
begin
  if AItem.Container <> '' then
    Result := AItem.Container + '.' + AItem.Name
  else
    Result := AItem.Name;
end;

procedure TAffectedRun.TraceSymbols(AResolver: TNameResolver; const ACancellation: IJsonRpcCancellationToken);
var
  mWholeFiles: TDictionary<string, Boolean>;
  mStarts: TArray<THierarchyItem>;
  mChanges: TArray<TAffectedChange>;
  mChange: TAffectedChange;
  mResults: TArray<TImpactResult>;
  mFound: TImpactResult;
  mIndex, mTestIndex, mPlace, mStep: Integer;
  mImpactTest: TImpactTest;
  mTest: TAffectedTest;
  mReason: TAffectedReason;
  mPath: TArray<string>;
  mInferred: Boolean;
begin
  // Symbole einer Unit, die ohnehin als Ganzes verfolgt wird, bringen keine weiteren Tests (jeder Weg über
  // Verweise führt auch über uses).
  mWholeFiles := TDictionary<string, Boolean>.Create;
  try
    for mChange in FResult.Changes do
      if mChange.Kind = TAffectedChangeKind.WholeUnit then
        mWholeFiles.AddOrSetValue(UpperCase(mChange.Item.FileName), True);
    mStarts := nil;
    mChanges := nil;
    for mChange in FResult.Changes do
      if (mChange.Kind = TAffectedChangeKind.Symbol) and not mWholeFiles.ContainsKey(UpperCase(mChange.Item.FileName))
      then
      begin
        mStarts := mStarts + [mChange.Item];
        mChanges := mChanges + [mChange];
      end;
  finally
    mWholeFiles.Free;
  end;
  if mStarts = nil then
    Exit;
  mResults := TImpactAnalysis.AnalyzeEach(AResolver, FIndex, mStarts, FRequest.Files, FReadText, FRequest.Options,
    ACancellation);
  for mIndex := 0 to High(mResults) do
  begin
    mFound := mResults[mIndex];
    FResult.Limits := FResult.Limits + mFound.Limits;
    for mTestIndex := 0 to High(mFound.Tests) do
    begin
      mImpactTest := mFound.Tests[mTestIndex];
      // Weg: von der Stelle des Tests über die Ursachen zurück zum geänderten Symbol.
      mPath := nil;
      mInferred := False;
      mPlace := -1;
      for mStep := 0 to High(mFound.Places) do
        if mFound.Places[mStep].Test = mTestIndex then
        begin
          mPlace := mStep;
          Break;
        end;
      mTest := Default(TAffectedTest);
      mTest.Name := mImpactTest.Name;
      mTest.RunNames := mImpactTest.RunNames;
      mTest.FileName := mImpactTest.FileName;
      mTest.Line := mImpactTest.Line;
      if mPlace >= 0 then
      begin
        mTest.Fixture := mFound.Places[mPlace].Item.Container;
        mTest.Method := mFound.Places[mPlace].Item.Name;
        mTest.UnitName := mFound.Places[mPlace].Item.UnitName;
        mStep := mPlace;
        while mStep >= 0 do
        begin
          mPath := TArray<string>.Create(PlaceName(mFound.Places[mStep].Item)) + mPath;
          if not mFound.Places[mStep].Confidence.IsSure then
            mInferred := True;
          mStep := mFound.Places[mStep].Cause;
        end;
      end
      else
      begin
        // Das geänderte Symbol ist selbst der Test (Ebene 0).
        mTest.Fixture := mStarts[mIndex].Container;
        mTest.Method := mStarts[mIndex].Name;
        mTest.UnitName := mStarts[mIndex].UnitName;
      end;
      if (mTest.UnitName = '') and EndsText('.' + mTest.Fixture + '.' + mTest.Method, mTest.Name) then
        mTest.UnitName := Copy(mTest.Name, 1, Length(mTest.Name) - Length(mTest.Fixture + mTest.Method) - 2);
      mPath := TArray<string>.Create(mChanges[mIndex].Text) + mPath;
      mReason.Change := mChanges[mIndex].Text;
      mReason.Path := mPath;
      mReason.Inferred := mInferred;
      AddTest(mTest, mReason);
    end;
  end;
end;

procedure TAffectedRun.TraceUnits;
var
  mUsers: TObjectDictionary<string, TList<string>>;
  mUnits: TDictionary<string, TUnitIndex>;
  mUnit, mFound: TUnitIndex;
  mUsed, mName, mNext: string;
  mList: TList<string>;
  mChange: TAffectedChange;
  mFrontier, mLevelNext: TList<string>;
  mPaths: TDictionary<string, TArray<string>>;
  mLevel, mFixture, mTestIndex: Integer;
  mSource: TDUnitXUnit;
  mTest: TAffectedTest;
  mReason: TAffectedReason;
  mPath: TArray<string>;
begin
  if FResult.All then
    Exit;
  mUsers := nil;
  mUnits := TDictionary<string, TUnitIndex>.Create;
  try
    for mChange in FResult.Changes do
    begin
      if mChange.Kind <> TAffectedChangeKind.WholeUnit then
        Continue;
      if mUsers = nil then
      begin
        // Umgekehrte uses-Beziehung der Projekt-Units, einmal für alle ganzen Units.
        mUsers := TObjectDictionary<string, TList<string>>.Create([doOwnsValues]);
        for mUnit in FIndex.Units do
        begin
          if mUnit.Library_ or (mUnit.UnitName = '') then
            Continue;
          mUnits.AddOrSetValue(UpperCase(mUnit.UnitName), mUnit);
          for mUsed in mUnit.InterfaceUses + mUnit.ImplementationUses do
          begin
            if not mUsers.TryGetValue(UpperCase(mUsed), mList) then
            begin
              mList := TList<string>.Create;
              mUsers.Add(UpperCase(mUsed), mList);
            end;
            if not mList.Contains(mUnit.UnitName) then
              mList.Add(mUnit.UnitName);
          end;
        end;
      end;
      mFrontier := TList<string>.Create;
      mLevelNext := TList<string>.Create;
      mPaths := TDictionary<string, TArray<string>>.Create;
      try
        mFrontier.Add(mChange.Item.Name);
        mPaths.Add(UpperCase(mChange.Item.Name), TArray<string>.Create(mChange.Text));
        // Ebene 0 ist die Unit selbst (eine geänderte Testunit), dann je Ebene ihre Verwender.
        for mLevel := 0 to FRequest.Options.Depth do
        begin
          mLevelNext.Clear;
          for mName in mFrontier do
          begin
            if FRequest.Options.Tests.Contains(mName) and mUnits.TryGetValue(UpperCase(mName), mFound) then
            begin
              mSource := SourceOf(mFound.FileName);
              for mFixture := 0 to High(mSource.Fixtures) do
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
                  mTest.FileName := mFound.FileName;
                  mTest.Line := mSource.Fixtures[mFixture].Line;
                  mReason.Change := mChange.Text;
                  mReason.Path := mPaths[UpperCase(mName)];
                  mReason.Inferred := False;
                  AddTest(mTest, mReason);
                end;
            end;
            if (mLevel < FRequest.Options.Depth) and mUsers.TryGetValue(UpperCase(mName), mList) then
              for mNext in mList do
                if not mPaths.ContainsKey(UpperCase(mNext)) then
                begin
                  mPath := mPaths[UpperCase(mName)] + TArray<string>.Create('Unit ' + mNext);
                  mPaths.Add(UpperCase(mNext), mPath);
                  mLevelNext.Add(mNext);
                end;
          end;
          mFrontier.Clear;
          mFrontier.AddRange(mLevelNext.ToArray);
          if mFrontier.Count = 0 then
            Break;
        end;
      finally
        mPaths.Free;
        mLevelNext.Free;
        mFrontier.Free;
      end;
    end;
  finally
    mUnits.Free;
    mUsers.Free;
  end;
end;

function TAffectedRun.Run(AResolver: TNameResolver; const AInputs: TArray<TAffectedInput>;
  const ACancellation: IJsonRpcCancellationToken): TAffectedResult;
var
  mInput: TAffectedInput;
  mKey: string;
  mTests: TArray<TAffectedTest>;
begin
  FResult := Default(TAffectedResult);
  FResult.Base := FRequest.Base;
  FResult.Depth := FRequest.Options.Depth;
  for mInput in AInputs do
  begin
    if ACancellation <> nil then
      ACancellation.ThrowIfCancellationRequested;
    MapInput(mInput);
  end;
  if not FResult.All then
  begin
    TraceSymbols(AResolver, ACancellation);
    // Unvollständig verfolgt: Es können Tests fehlen. Die Tiefe dagegen ist gewollt.
    if TImpactLimit.Time in FResult.Limits then
      NeedAll('Zeitlimit der Analyse erreicht')
    else if TImpactLimit.Count in FResult.Limits then
      NeedAll(Format('mehr als %d betroffene Stellen', [TImpactAnalysis.MaxPlaces]));
  end;
  if not FResult.All then
  begin
    TraceUnits;
    mTests := nil;
    for mKey in FOrder do
      mTests := mTests + [FTests[mKey]];
    FResult.Tests := TAffectedTests.Collapse(mTests,
      function(ATest: TAffectedTest): Integer
      var
        mSource: TDUnitXUnit;
        mFixture, mTestIndex: Integer;
      begin
        mSource := SourceOf(ATest.FileName);
        if mSource.Find(ATest.Fixture, '', mFixture, mTestIndex) then
          Result := Length(mSource.Fixtures[mFixture].Tests)
        else
          Result := 0;
      end,
      function(ATest: TAffectedTest): TArray<string>
      var
        mSource: TDUnitXUnit;
        mFixture, mTestIndex: Integer;
      begin
        mSource := SourceOf(ATest.FileName);
        if mSource.Find(ATest.Fixture, '', mFixture, mTestIndex) then
          Result := TDUnitXCommandLine.RunNames(mSource, mFixture, -1, -1)
        else
          Result := nil;
      end);
    TAffectedTests.Sort(FResult.Tests);
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

class function TAffectedTests.TryParseFormat(const AText: string; out AFormat: TAffectedFormat): Boolean;
begin
  Result := True;
  if (AText = '') or SameText(AText, 'text') then
    AFormat := TAffectedFormat.Text
  else if SameText(AText, 'json') then
    AFormat := TAffectedFormat.Json
  else if SameText(AText, 'dunitx') then
    AFormat := TAffectedFormat.DUnitX
  else
  begin
    AFormat := TAffectedFormat.Text;
    Result := False;
  end;
end;

class function TAffectedTests.Render(const AResult: TAffectedResult; AFormat: TAffectedFormat): string;
var
  mJson: TJSONObject;
begin
  case AFormat of
    TAffectedFormat.Json:
      begin
        mJson := ToJson(AResult);
        try
          Result := mJson.ToJSON([]);
        finally
          mJson.Free;
        end;
      end;
    TAffectedFormat.DUnitX:
      if not DUnitXArgument(AResult, Result) then
        Result := '';
  else
    Result := ToText(AResult);
  end;
end;

class function TAffectedTests.DUnitXArgument(const AResult: TAffectedResult; out AArgument: string): Boolean;
var
  mRun: string;
begin
  AArgument := '';
  Result := True;
  if AResult.All or (Length(AResult.Tests) = 0) then
    Exit;
  mRun := string.Join(',', AResult.RunNames);
  if Length(mRun) > TDUnitXCommandLine.MaxRunLength then
    Exit(False);
  AArgument := '--run:' + mRun;
end;

class function TAffectedTests.ToText(const AResult: TAffectedResult): string;
var
  mLines: TArray<string>;
  mTest: TAffectedTest;
  mReason: TAffectedReason;
  mChange: TAffectedChange;
  mFixtures: Integer;
  mLimit: TImpactLimit;
  mLimitNames: TArray<string>;
begin
  mLines := nil;
  if AResult.All then
    mLines := mLines + [Format('Alle Tests nötig: %s.', [AResult.AllReason])]
  else if Length(AResult.Tests) = 0 then
    mLines := mLines + [Format('Keine betroffenen Tests gegenüber %s (Tiefe %d).', [AResult.Base, AResult.Depth])]
  else
  begin
    mFixtures := 0;
    for mTest in AResult.Tests do
      if mTest.Method = '' then
        Inc(mFixtures);
    mLines := mLines + [Format('%d betroffene Tests gegenüber %s (Tiefe %d), davon %d ganze Fixtures:',
      [Length(AResult.Tests), AResult.Base, AResult.Depth, mFixtures])];
    for mTest in AResult.Tests do
    begin
      mLines := mLines + ['  ' + mTest.Name];
      for mReason in mTest.Reasons do
        mLines := mLines + ['    ← ' + mReason.Text];
    end;
  end;
  if Length(AResult.Changes) > 0 then
  begin
    mLines := mLines + ['', Format('Geändert (%d):', [Length(AResult.Changes)])];
    for mChange in AResult.Changes do
      mLines := mLines + [Format('  %s (%s, %s)', [mChange.Text, mChange.Place, ExtractFileName(mChange.Source)])];
  end;
  if Length(AResult.Skipped) > 0 then
    mLines := mLines + ['', Format('Ohne Einfluss auf Tests: %d Dateien.', [Length(AResult.Skipped)])];
  mLimitNames := nil;
  for mLimit := Low(TImpactLimit) to High(TImpactLimit) do
    if mLimit in AResult.Limits then
      mLimitNames := mLimitNames + [TImpactAnalysis.LimitName(mLimit)];
  if mLimitNames <> nil then
    mLines := mLines + ['', 'Grenzen erreicht: ' + string.Join(', ', mLimitNames) +
      '; mit größerer Tiefe oder allen Tests prüfen.'];
  if not AResult.All and (Length(AResult.Tests) > 0) then
    mLines := mLines + ['', 'run_tests tests: ' + string.Join(', ', AResult.RunNames)];
  Result := string.Join(sLineBreak, mLines) + sLineBreak;
end;

class function TAffectedTests.ToJson(const AResult: TAffectedResult): TJSONObject;
var
  mTests, mRun, mReasons, mPath, mChanges, mSkipped: TJSONArray;
  mEntry, mReasonEntry, mLimits: TJSONObject;
  mTest: TAffectedTest;
  mReason: TAffectedReason;
  mChange: TAffectedChange;
  mSkip: TAffectedSkipped;
  mName, mStep: string;
  mLimit: TImpactLimit;
begin
  Result := TJSONObject.Create;
  Result.AddPair('base', AResult.Base);
  Result.AddPair('depth', TJSONNumber.Create(AResult.Depth));
  Result.AddPair('all', TJSONBool.Create(AResult.All));
  Result.AddPair('reason', AResult.AllReason);
  mRun := TJSONArray.Create;
  Result.AddPair('run', mRun);
  if not AResult.All then
    for mName in AResult.RunNames do
      mRun.Add(mName);
  mTests := TJSONArray.Create;
  Result.AddPair('tests', mTests);
  for mTest in AResult.Tests do
  begin
    mEntry := TJSONObject.Create;
    mTests.AddElement(mEntry);
    mEntry.AddPair('name', mTest.Name);
    mEntry.AddPair('unit', mTest.UnitName);
    mEntry.AddPair('fixture', mTest.Fixture);
    mEntry.AddPair('method', mTest.Method);
    mRun := TJSONArray.Create;
    mEntry.AddPair('run', mRun);
    for mName in mTest.RunNames do
      mRun.Add(mName);
    mEntry.AddPair('uri', TDocumentUris.FromPath(mTest.FileName));
    mEntry.AddPair('line', TJSONNumber.Create(mTest.Line));
    mReasons := TJSONArray.Create;
    mEntry.AddPair('reasons', mReasons);
    for mReason in mTest.Reasons do
    begin
      mReasonEntry := TJSONObject.Create;
      mReasons.AddElement(mReasonEntry);
      mReasonEntry.AddPair('change', mReason.Change);
      mPath := TJSONArray.Create;
      mReasonEntry.AddPair('path', mPath);
      for mStep in mReason.Path do
        mPath.Add(mStep);
      mReasonEntry.AddPair('inferred', TJSONBool.Create(mReason.Inferred));
    end;
  end;
  mChanges := TJSONArray.Create;
  Result.AddPair('changes', mChanges);
  for mChange in AResult.Changes do
  begin
    mEntry := TJSONObject.Create;
    mChanges.AddElement(mEntry);
    if mChange.Kind = TAffectedChangeKind.WholeUnit then
      mEntry.AddPair('kind', 'unit')
    else
      mEntry.AddPair('kind', 'symbol');
    mEntry.AddPair('name', mChange.Text);
    mEntry.AddPair('place', mChange.Place);
    mEntry.AddPair('uri', TDocumentUris.FromPath(mChange.Source));
  end;
  mSkipped := TJSONArray.Create;
  Result.AddPair('skipped', mSkipped);
  for mSkip in AResult.Skipped do
  begin
    mEntry := TJSONObject.Create;
    mSkipped.AddElement(mEntry);
    mEntry.AddPair('uri', TDocumentUris.FromPath(mSkip.FileName));
    mEntry.AddPair('reason', mSkip.Reason);
  end;
  mLimits := TJSONObject.Create;
  Result.AddPair('limits', mLimits);
  for mLimit := Low(TImpactLimit) to High(TImpactLimit) do
    mLimits.AddPair(TImpactAnalysis.LimitName(mLimit), TJSONBool.Create(mLimit in AResult.Limits));
end;

class function TAffectedTests.FromJson(const AValue: TJSONValue): TAffectedResult;
var
  mRoot, mEntry, mReasonEntry, mLimits: TJSONObject;
  mArray, mInner, mSteps: TJSONArray;
  mItem, mReasonItem, mStep: TJSONValue;
  mTest: TAffectedTest;
  mReason: TAffectedReason;
  mLimit: TImpactLimit;
  mFlag: Boolean;
  mUri: string;
begin
  Result := Default(TAffectedResult);
  if not (AValue is TJSONObject) then
    Exit;
  mRoot := TJSONObject(AValue);
  mRoot.TryGetValue<string>('base', Result.Base);
  mRoot.TryGetValue<Integer>('depth', Result.Depth);
  mRoot.TryGetValue<Boolean>('all', Result.All);
  mRoot.TryGetValue<string>('reason', Result.AllReason);
  if mRoot.TryGetValue<TJSONArray>('tests', mArray) then
    for mItem in mArray do
    begin
      if not (mItem is TJSONObject) then
        Continue;
      mEntry := TJSONObject(mItem);
      mTest := Default(TAffectedTest);
      mEntry.TryGetValue<string>('name', mTest.Name);
      mEntry.TryGetValue<string>('unit', mTest.UnitName);
      mEntry.TryGetValue<string>('fixture', mTest.Fixture);
      mEntry.TryGetValue<string>('method', mTest.Method);
      mEntry.TryGetValue<Integer>('line', mTest.Line);
      if mEntry.TryGetValue<string>('uri', mUri) then
        mTest.FileName := TDocumentUris.ToPath(mUri);
      if mEntry.TryGetValue<TJSONArray>('run', mInner) then
        for mStep in mInner do
          mTest.RunNames := mTest.RunNames + [mStep.Value];
      if mEntry.TryGetValue<TJSONArray>('reasons', mInner) then
        for mReasonItem in mInner do
        begin
          if not (mReasonItem is TJSONObject) then
            Continue;
          mReasonEntry := TJSONObject(mReasonItem);
          mReason := Default(TAffectedReason);
          mReasonEntry.TryGetValue<string>('change', mReason.Change);
          mReasonEntry.TryGetValue<Boolean>('inferred', mReason.Inferred);
          if mReasonEntry.TryGetValue<TJSONArray>('path', mSteps) then
            for mStep in mSteps do
              mReason.Path := mReason.Path + [mStep.Value];
          mTest.Reasons := mTest.Reasons + [mReason];
        end;
      Result.Tests := Result.Tests + [mTest];
    end;
  if mRoot.TryGetValue<TJSONObject>('limits', mLimits) then
    for mLimit := Low(TImpactLimit) to High(TImpactLimit) do
      if mLimits.TryGetValue<Boolean>(TImpactAnalysis.LimitName(mLimit), mFlag) and mFlag then
        Include(Result.Limits, mLimit);
end;

end.
