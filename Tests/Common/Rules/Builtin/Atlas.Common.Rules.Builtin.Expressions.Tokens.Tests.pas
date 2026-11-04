unit Atlas.Common.Rules.Builtin.Expressions.Tokens.Tests;

// Tests der Tokenhilfen der Ausdrucksregeln: Ende des rechten Operanden, einfacher Bezeichner,
// Form "not X op Y" und Länge eines Pascal-Literals.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Pascal.Contract;

type
  [TestFixture]
  TExpressionTokensTests = class
  private
    FTokens: TArray<TPascalToken>;
    function IndexOfText(const AText: string): Integer;
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure OperandEndStopsAtThenAndAnd;
    [Test]
    procedure OperandEndSpansBrackets;
    [Test]
    procedure OperandEndWithoutOperand;
    [Test]
    procedure PlainIdentifierExcludesChainsAndCalls;
    [Test]
    procedure NotComparisonFindsParts;
    [Test]
    procedure NotComparisonNeedsPlainIdentifier;
    [Test]
    procedure LiteralLengthCountsParts;
    [Test]
    procedure LiteralLengthRejectsOtherText;
  end;

implementation

uses
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Rules.Builtin.Expressions.Tokens;

function TExpressionTokensTests.IndexOfText(const AText: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  mIndex := 0;
  while (Result < 0) and (mIndex <= High(FTokens)) do
  begin
    if FTokens[mIndex].Text = AText then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

procedure TExpressionTokensTests.TearDown;
begin
  FTokens := nil;
end;

procedure TExpressionTokensTests.OperandEndStopsAtThenAndAnd;
begin
  FTokens := TPascalLexer.Tokenize('if not A = B + 1 then');
  Assert.AreEqual(IndexOfText('1'), OperandEnd(FTokens, IndexOfText('B')));
  FTokens := TPascalLexer.Tokenize('if not A = B and C then');
  Assert.AreEqual(IndexOfText('B'), OperandEnd(FTokens, IndexOfText('B')));
end;

procedure TExpressionTokensTests.OperandEndSpansBrackets;
begin
  FTokens := TPascalLexer.Tokenize('X := not A in [B, C];');
  Assert.AreEqual(IndexOfText(']'), OperandEnd(FTokens, IndexOfText('[')));
end;

procedure TExpressionTokensTests.OperandEndWithoutOperand;
begin
  FTokens := TPascalLexer.Tokenize('if not A = then');
  Assert.AreEqual(-1, OperandEnd(FTokens, IndexOfText('then')));
end;

procedure TExpressionTokensTests.PlainIdentifierExcludesChainsAndCalls;
begin
  FTokens := TPascalLexer.Tokenize('X := A + B.C + D(1);');
  Assert.IsTrue(IsPlainIdentifier(FTokens, IndexOfText('A')));
  Assert.IsFalse(IsPlainIdentifier(FTokens, IndexOfText('B')));
  Assert.IsFalse(IsPlainIdentifier(FTokens, IndexOfText('C')));
  Assert.IsFalse(IsPlainIdentifier(FTokens, IndexOfText('D')));
end;

procedure TExpressionTokensTests.NotComparisonFindsParts;
var
  mParts: TNotComparison;
begin
  FTokens := TPascalLexer.Tokenize('if not Wert in [1, 2] then');
  Assert.IsTrue(NotComparisonAt(FTokens, IndexOfText('not'), mParts));
  Assert.AreEqual(IndexOfText('Wert'), mParts.Operand);
  Assert.AreEqual(IndexOfText('in'), mParts.Op);
  Assert.AreEqual(IndexOfText('['), mParts.Right);
  Assert.AreEqual(IndexOfText(']'), mParts.Last);
end;

procedure TExpressionTokensTests.NotComparisonNeedsPlainIdentifier;
var
  mParts: TNotComparison;
begin
  FTokens := TPascalLexer.Tokenize('if not Liste.Wert = 1 then');
  Assert.IsFalse(NotComparisonAt(FTokens, IndexOfText('not'), mParts));
  FTokens := TPascalLexer.Tokenize('if not Fertig then');
  Assert.IsFalse(NotComparisonAt(FTokens, IndexOfText('not'), mParts));
end;

procedure TExpressionTokensTests.LiteralLengthCountsParts;
begin
  Assert.AreEqual(3, PascalLiteralLength('''abc'''));
  Assert.AreEqual(1, PascalLiteralLength(''''''''''));
  Assert.AreEqual(4, PascalLiteralLength('''ab''#13#10'));
  Assert.AreEqual(0, PascalLiteralLength(''''''));
end;

procedure TExpressionTokensTests.LiteralLengthRejectsOtherText;
begin
  Assert.AreEqual(-1, PascalLiteralLength('Name'));
  Assert.AreEqual(-1, PascalLiteralLength('''a''+''b'''));
end;

initialization
  TDUnitX.RegisterTestFixture(TExpressionTokensTests);

end.
