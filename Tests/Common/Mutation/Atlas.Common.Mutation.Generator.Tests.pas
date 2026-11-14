unit Atlas.Common.Mutation.Generator.Tests;

// Tests des Mutanten-Generators (#1460): je Operator ein Positiv- und ein
// Negativfall, die Ausnahmen (Assert, Protokoll, inaktive Zweige,
// atlas-ignore, case-Marken, Strings), Auswahl nach Routine und Zeilen,
// Apply und das Beispiel aus der Abnahme (AMenge >= 100).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Mutation.Contract;

type
  [TestFixture]
  TMutationGeneratorTests = class
  private
    FMutants: TArray<TMutant>;
    /// <summary>Mutanten des Rumpfs ABody in "function F(A, B: Integer): Integer"; nur AOperators.</summary>
    procedure Generate(const ABody: string; AOperators: TMutationOperators);
    /// <summary>Gibt es einen Mutanten mit Original AOriginal und Ersatz AReplacement?</summary>
    function Has(const AOriginal, AReplacement: string): Boolean;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BoundaryOperators;
    [Test]
    procedure EqualityOperators;
    [Test]
    procedure LogicalOperatorsKeepCase;
    [Test]
    procedure RemovesNot;
    [Test]
    procedure ArithmeticSkipsStrings;
    [Test]
    procedure RemovesIncrement;
    [Test]
    procedure BooleanLiterals;
    [Test]
    procedure NumberLiteralsOnlyZeroAndOne;
    [Test]
    procedure RemovesCallsAndAssignmentsButNotFlow;
    [Test]
    procedure ExitBecomesDefaultOfResultType;
    [Test]
    procedure ExitUntouchedInProcedureAndAnonymousMethod;
    [Test]
    procedure SkipsAssertAndLogging;
    [Test]
    procedure LoginIsNoLogging;
    [Test]
    procedure SkipsInactiveBranches;
    [Test]
    procedure IgnoreCommentOnLineAndAbove;
    [Test]
    procedure IgnoreCommentAboveRoutine;
    [Test]
    procedure SkipsCaseLabels;
    [Test]
    procedure OnlyRoutineBodies;
    [Test]
    procedure FiltersByRoutineAndLines;
    [Test]
    procedure LocalRoutinesQualified;
    [Test]
    procedure IdsInSourceOrder;
    [Test]
    procedure ApplyChangesOnlyTheRange;
    [Test]
    procedure AcceptanceExample;
    [Test]
    procedure ParsesOperatorIds;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Mutation.Generator;

const
  cLf = #10;

function UnitWith(const ABody: string): string;
begin
  Result := 'unit U;' + cLf + 'interface' + cLf + 'implementation' + cLf +
    'function F(A, B: Integer): Integer;' + cLf + 'begin' + cLf + ABody + cLf + 'end;' + cLf + 'end.';
end;

{ TMutationGeneratorTests }

procedure TMutationGeneratorTests.TearDown;
begin
  FMutants := nil;
end;

procedure TMutationGeneratorTests.Generate(const ABody: string; AOperators: TMutationOperators);
var
  mOptions: TMutationOptions;
begin
  mOptions := TMutationOptions.Default;
  mOptions.Operators := AOperators;
  FMutants := TMutationGenerator.ForText(UnitWith(ABody), mOptions);
end;

function TMutationGeneratorTests.Has(const AOriginal, AReplacement: string): Boolean;
var
  mMutant: TMutant;
begin
  for mMutant in FMutants do
  begin
    if (mMutant.Original = AOriginal) and (mMutant.Replacement = AReplacement) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TMutationGeneratorTests.BoundaryOperators;
begin
  Generate('  if (A < B) or (A > B) or (A <= 1) or (A >= 2) then Result := 0;', [TMutationOperator.Boundary]);
  Assert.AreEqual(4, Integer(Length(FMutants)));
  Assert.IsTrue(Has('<', '<='));
  Assert.IsTrue(Has('>', '>='));
  Assert.IsTrue(Has('<=', '<'));
  Assert.IsTrue(Has('>=', '>'));
  Generate('  if A = B then Result := 0;', [TMutationOperator.Boundary]);
  Assert.AreEqual(0, Integer(Length(FMutants)));
end;

procedure TMutationGeneratorTests.EqualityOperators;
begin
  Generate('  if (A = B) and (A <> 3) then Result := 0;', [TMutationOperator.Equality]);
  Assert.AreEqual(2, Integer(Length(FMutants)));
  Assert.IsTrue(Has('=', '<>'));
  Assert.IsTrue(Has('<>', '='));
  // := ist keine Gleichheit.
  Generate('  Result := A;', [TMutationOperator.Equality]);
  Assert.AreEqual(0, Integer(Length(FMutants)));
end;

procedure TMutationGeneratorTests.LogicalOperatorsKeepCase;
begin
  Generate('  if (A > 0) AND (B > 0) or (A = B) then Result := 0;', [TMutationOperator.Logical]);
  Assert.AreEqual(2, Integer(Length(FMutants)));
  Assert.IsTrue(Has('AND', 'OR'));
  Assert.IsTrue(Has('or', 'and'));
  Generate('  if (A > 0) xor (B > 0) then Result := 0;', [TMutationOperator.Logical]);
  Assert.AreEqual(0, Integer(Length(FMutants)));
end;

procedure TMutationGeneratorTests.RemovesNot;
begin
  Generate('  if not Odd(A) then Result := 0;', [TMutationOperator.RemoveNot]);
  Assert.AreEqual(1, Integer(Length(FMutants)));
  Assert.IsTrue(Has('not Odd(A)', 'Odd(A)'));
  Generate('  if Odd(A) then Result := -A;', [TMutationOperator.RemoveNot]);
  Assert.AreEqual(0, Integer(Length(FMutants)));
end;

procedure TMutationGeneratorTests.ArithmeticSkipsStrings;
begin
  Generate('  Result := A + B - 2;', [TMutationOperator.Arithmetic]);
  Assert.AreEqual(2, Integer(Length(FMutants)));
  Assert.IsTrue(Has('+', '-'));
  Assert.IsTrue(Has('-', '+'));
  Generate('  S := ''a'' + S; S := S + #13;', [TMutationOperator.Arithmetic]);
  Assert.AreEqual(0, Integer(Length(FMutants)));
end;

procedure TMutationGeneratorTests.RemovesIncrement;
begin
  Generate('  Result := A + 1; B := B - 1; B := B + 2;', [TMutationOperator.RemoveIncrement]);
  Assert.AreEqual(2, Integer(Length(FMutants)));
  Assert.IsTrue(Has('A + 1', 'A'));
  Assert.IsTrue(Has('B - 1', 'B'));
end;

procedure TMutationGeneratorTests.BooleanLiterals;
begin
  Generate('  Flag := True; Other := false;', [TMutationOperator.BooleanLiteral]);
  Assert.AreEqual(2, Integer(Length(FMutants)));
  Assert.IsTrue(Has('True', 'False'));
  Assert.IsTrue(Has('false', 'true'));
  Generate('  Flag := TrueValue;', [TMutationOperator.BooleanLiteral]);
  Assert.AreEqual(0, Integer(Length(FMutants)));
end;

procedure TMutationGeneratorTests.NumberLiteralsOnlyZeroAndOne;
begin
  Generate('  Result := 0; B := 1; B := 2; B := 10;', [TMutationOperator.NumberLiteral]);
  Assert.AreEqual(2, Integer(Length(FMutants)));
  Assert.IsTrue(Has('0', '1'));
  Assert.IsTrue(Has('1', '0'));
end;

procedure TMutationGeneratorTests.RemovesCallsAndAssignmentsButNotFlow;
begin
  Generate('  Foo.Bar(A);' + cLf + '  Result := A;' + cLf + '  Exit;' + cLf + '  while True do Break;',
    [TMutationOperator.RemoveStatement]);
  Assert.AreEqual(2, Integer(Length(FMutants)));
  Assert.IsTrue(Has('Foo.Bar(A)', ''));
  Assert.IsTrue(Has('Result := A', ''));
end;

procedure TMutationGeneratorTests.ExitBecomesDefaultOfResultType;
begin
  Generate('  if A > 0 then Exit(A * 2);' + cLf + '  Exit(0);', [TMutationOperator.ExitDefault]);
  Assert.AreEqual(1, Integer(Length(FMutants)));
  Assert.IsTrue(Has('A * 2', 'Default(Integer)'));
end;

procedure TMutationGeneratorTests.ExitUntouchedInProcedureAndAnonymousMethod;
var
  mText: string;
begin
  mText := 'unit U;' + cLf + 'implementation' + cLf + 'procedure P;' + cLf + 'begin' + cLf + '  Exit;' + cLf +
    'end;' + cLf + 'function G: Integer;' + cLf + 'var F: TFunc<Integer>;' + cLf + 'begin' + cLf +
    '  F := function: Integer begin Exit(5); end;' + cLf + '  Result := F;' + cLf + 'end;' + cLf + 'end.';
  FMutants := TMutationGenerator.ForText(mText, TMutationOptions.Default);
  Assert.IsFalse(Has('5', 'Default(Integer)'));
end;

procedure TMutationGeneratorTests.SkipsAssertAndLogging;
begin
  Generate('  Assert(A > 0);' + cLf + '  Log(A = 1);' + cLf + '  FLogger.Debug(''x'' + IntToStr(A + 1));' + cLf +
    '  TLog.Info(True);' + cLf + '  OutputDebugString(PChar(IntToStr(0)));', TMutation.AllOperators);
  Assert.AreEqual(0, Integer(Length(FMutants)));
end;

procedure TMutationGeneratorTests.LoginIsNoLogging;
begin
  Generate('  Login(A);', [TMutationOperator.RemoveStatement]);
  Assert.AreEqual(1, Integer(Length(FMutants)));
end;

procedure TMutationGeneratorTests.SkipsInactiveBranches;
var
  mOptions: TMutationOptions;
  mText: string;
begin
  mText := UnitWith('  {$IFDEF NIEMALS}' + cLf + '  Result := A + B;' + cLf + '  {$ELSE}' + cLf + '  Result := A - B;' +
    cLf + '  {$ENDIF}');
  mOptions := TMutationOptions.Default;
  mOptions.Operators := [TMutationOperator.Arithmetic];
  FMutants := TMutationGenerator.ForText(mText, mOptions);
  Assert.AreEqual(1, Integer(Length(FMutants)));
  Assert.IsTrue(Has('-', '+'));
  mOptions.Defines := ['NIEMALS'];
  FMutants := TMutationGenerator.ForText(mText, mOptions);
  Assert.AreEqual(1, Integer(Length(FMutants)));
  Assert.IsTrue(Has('+', '-'));
end;

procedure TMutationGeneratorTests.IgnoreCommentOnLineAndAbove;
begin
  Generate('  Result := A + B; // atlas-ignore: mutation' + cLf + '  // lsp-ignore: mutation' + cLf +
    '  Result := A + B;' + cLf + '  Result := A + B;', [TMutationOperator.Arithmetic]);
  Assert.AreEqual(1, Integer(Length(FMutants)));
  Assert.AreEqual(8, FMutants[0].Range.StartPos.Line);
end;

procedure TMutationGeneratorTests.IgnoreCommentAboveRoutine;
var
  mText: string;
begin
  mText := 'unit U;' + cLf + 'implementation' + cLf + '// atlas-ignore: mutation' + cLf + 'function F: Integer;' + cLf +
    'begin' + cLf + '  Result := 1 + 2;' + cLf + 'end;' + cLf + 'function G: Integer;' + cLf + 'begin' + cLf +
    '  Result := 1 + 2;' + cLf + 'end;' + cLf + 'end.';
  FMutants := TMutationGenerator.ForText(mText, TMutationOptions.Default);
  Assert.IsTrue(Length(FMutants) > 0);
  Assert.AreEqual('G', FMutants[0].Routine);
  Assert.AreEqual('G', FMutants[High(FMutants)].Routine);
end;

procedure TMutationGeneratorTests.SkipsCaseLabels;
begin
  Generate('  case A of' + cLf + '    0, 1: Result := 0;' + cLf + '  end;', [TMutationOperator.NumberLiteral]);
  Assert.AreEqual(1, Integer(Length(FMutants)));
  Assert.AreEqual(6, FMutants[0].Range.StartPos.Line);
  Assert.AreEqual(20, FMutants[0].Range.StartPos.Character);
end;

procedure TMutationGeneratorTests.OnlyRoutineBodies;
var
  mText: string;
begin
  mText := 'unit U;' + cLf + 'interface' + cLf + 'const C = 1 + 0;' + cLf + 'implementation' + cLf +
    'procedure P;' + cLf + 'asm' + cLf + '  ret' + cLf + 'end;' + cLf + 'initialization' + cLf + '  Foo(True);' + cLf +
    'end.';
  FMutants := TMutationGenerator.ForText(mText, TMutationOptions.Default);
  Assert.AreEqual(0, Integer(Length(FMutants)));
end;

procedure TMutationGeneratorTests.FiltersByRoutineAndLines;
var
  mText: string;
  mOptions: TMutationOptions;
begin
  mText := 'unit U;' + cLf + 'implementation' + cLf + 'function TFoo.F: Integer;' + cLf + 'begin' + cLf +
    '  Result := 1 + 2;' + cLf + 'end;' + cLf + 'function TBar.F: Integer;' + cLf + 'begin' + cLf +
    '  Result := 1 + 2;' + cLf + '  Result := 3 + 4;' + cLf + 'end;' + cLf + 'end.';
  mOptions := TMutationOptions.Default;
  mOptions.Operators := [TMutationOperator.Arithmetic];
  mOptions.Routine := 'tbar.f';
  FMutants := TMutationGenerator.ForText(mText, mOptions);
  Assert.AreEqual(2, Integer(Length(FMutants)));
  Assert.AreEqual('TBar.F', FMutants[0].Routine);
  mOptions.Routine := 'F';
  FMutants := TMutationGenerator.ForText(mText, mOptions);
  Assert.AreEqual(3, Integer(Length(FMutants)));
  mOptions.Routine := '';
  mOptions.FirstLine := 9;
  mOptions.LastLine := 9;
  FMutants := TMutationGenerator.ForText(mText, mOptions);
  Assert.AreEqual(1, Integer(Length(FMutants)));
  Assert.AreEqual('3 + 4', Copy(mText, FMutants[0].StartOffset - 1, 5));
end;

procedure TMutationGeneratorTests.LocalRoutinesQualified;
var
  mText: string;
begin
  mText := 'unit U;' + cLf + 'implementation' + cLf + 'procedure TFoo.P;' + cLf + '  procedure Inner;' + cLf +
    '  begin' + cLf + '    Bar;' + cLf + '  end;' + cLf + 'begin' + cLf + '  Inner;' + cLf + 'end;' + cLf + 'end.';
  FMutants := TMutationGenerator.ForText(mText, TMutationOptions.Default);
  Assert.AreEqual(2, Integer(Length(FMutants)));
  Assert.AreEqual('TFoo.P.Inner', FMutants[0].Routine);
  Assert.AreEqual('TFoo.P', FMutants[1].Routine);
end;

procedure TMutationGeneratorTests.IdsInSourceOrder;
var
  mIndex: Integer;
begin
  Generate('  if A >= 0 then Result := A + 1;', TMutation.AllOperators);
  Assert.IsTrue(Length(FMutants) > 3);
  for mIndex := 0 to High(FMutants) do
  begin
    Assert.AreEqual(mIndex + 1, FMutants[mIndex].Id);
    if mIndex > 0 then
    begin
      Assert.IsTrue(FMutants[mIndex].StartOffset >= FMutants[mIndex - 1].StartOffset);
    end;
  end;
end;

procedure TMutationGeneratorTests.ApplyChangesOnlyTheRange;
var
  mText: string;
begin
  mText := UnitWith('  if A >= 100 then Result := 1;');
  FMutants := TMutationGenerator.ForText(mText, TMutationOptions.Default);
  Assert.IsTrue(Has('>=', '>'));
  Assert.AreEqual(StringReplace(mText, '>=', '>', []), TMutation.Apply(mText, FMutants[0]));
  // Zeile 5 (ab 0): '  if A >= 100 …', der Operator beginnt bei Spalte 7.
  Assert.AreEqual(5, FMutants[0].Range.StartPos.Line);
  Assert.AreEqual(7, FMutants[0].Range.StartPos.Character);
  Assert.AreEqual(9, FMutants[0].Range.EndPos.Character);
end;

procedure TMutationGeneratorTests.AcceptanceExample;
var
  mText: string;
  mOptions: TMutationOptions;
begin
  mText := 'unit Preise;' + cLf + 'interface' + cLf + 'function Satz(AMenge: Integer): Integer;' + cLf +
    'implementation' + cLf + 'function Satz(AMenge: Integer): Integer;' + cLf + 'begin' + cLf +
    '  if AMenge >= 100 then' + cLf + '    Result := 5' + cLf + '  else' + cLf + '    Result := 0;' + cLf + 'end;' +
    cLf + 'end.';
  mOptions := TMutationOptions.Default;
  mOptions.Routine := 'Satz';
  FMutants := TMutationGenerator.ForText(mText, mOptions);
  Assert.IsTrue(Has('>=', '>'));
  Assert.AreEqual('Satz', FMutants[0].Routine);
  Assert.AreEqual(6, FMutants[0].Range.StartPos.Line);
end;

procedure TMutationGeneratorTests.ParsesOperatorIds;
var
  mUnknown: TArray<string>;
  mOperators: TMutationOperators;
  mOperator, mParsed: TMutationOperator;
begin
  for mOperator := Low(TMutationOperator) to High(TMutationOperator) do
  begin
    Assert.IsTrue(TMutation.TryParseOperator(TMutation.OperatorId(mOperator), mParsed));
    Assert.AreEqual<TMutationOperator>(mOperator, mParsed);
  end;
  mOperators := TMutation.ParseOperators(['Boundary', ' not ', 'gibtsnicht', ''], mUnknown);
  Assert.AreEqual<TMutationOperators>([TMutationOperator.Boundary, TMutationOperator.RemoveNot], mOperators);
  Assert.AreEqual(1, Integer(Length(mUnknown)));
  Assert.AreEqual('gibtsnicht', mUnknown[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TMutationGeneratorTests);

end.
