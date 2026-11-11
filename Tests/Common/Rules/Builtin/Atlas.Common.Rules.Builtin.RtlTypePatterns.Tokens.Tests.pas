unit Atlas.Common.Rules.Builtin.RtlTypePatterns.Tokens.Tests;

// Tests der gemeinsamen Tokenhilfen der Regeln für RTL-Muster: schließende
// Klammer finden, Argumente zählen, einfache Bezeichner und Routinenrümpfe
// erkennen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRtlTypePatternTokensTests = class
  public
    [Test]
    procedure ClosingFindsMatchingBracket;
    [Test]
    procedure ClosingWithoutMatchIsMinusOne;
    [Test]
    procedure ArgumentCountCountsTopLevelCommas;
    [Test]
    procedure PlainIdentifierIsNoChainOrCall;
    [Test]
    procedure InStatementsOnlyInsideRoutineBody;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Tokens;

{ TRtlTypePatternTokensTests }

procedure TRtlTypePatternTokensTests.ClosingFindsMatchingBracket;
var
  mTokens: TTokens;
begin
  // F ( A [ 1 ] , ( B ) )
  mTokens := TPascalLexer.Tokenize('F(A[1], (B))');
  Assert.AreEqual(5, MatchingParen(mTokens, 3));
  Assert.AreEqual(10, MatchingParen(mTokens, 1));
end;

procedure TRtlTypePatternTokensTests.ClosingWithoutMatchIsMinusOne;
var
  mTokens: TTokens;
begin
  mTokens := TPascalLexer.Tokenize('F(A');
  Assert.AreEqual(-1, MatchingParen(mTokens, 1));
end;

procedure TRtlTypePatternTokensTests.ArgumentCountCountsTopLevelCommas;
var
  mTokens: TTokens;
begin
  mTokens := TPascalLexer.Tokenize('F(A, G(B, C), D[1, 2])');
  Assert.AreEqual(3, ArgumentCount(mTokens, 1, MatchingParen(mTokens, 1)));
  mTokens := TPascalLexer.Tokenize('F( { leer } )');
  Assert.AreEqual(0, ArgumentCount(mTokens, 1, MatchingParen(mTokens, 1)));
end;

procedure TRtlTypePatternTokensTests.PlainIdentifierIsNoChainOrCall;
var
  mTokens: TTokens;
begin
  // A := B.C + D(1) + E;
  mTokens := TPascalLexer.Tokenize('A := B.C + D(1) + E;');
  Assert.IsTrue(IsPlainIdentifier(mTokens, 0));
  Assert.IsFalse(IsPlainIdentifier(mTokens, 2));
  Assert.IsFalse(IsPlainIdentifier(mTokens, 4));
  Assert.IsFalse(IsPlainIdentifier(mTokens, 6));
  Assert.IsTrue(IsPlainIdentifier(mTokens, 11));
  Assert.IsFalse(IsPlainIdentifier(mTokens, 1));
  Assert.IsFalse(IsPlainIdentifier(mTokens, -1));
end;

procedure TRtlTypePatternTokensTests.InStatementsOnlyInsideRoutineBody;
const
  cSource = 'unit U;'#13#10'interface'#13#10'implementation'#13#10'procedure P;'#13#10'var'#13#10'  X: Integer;'#13#10 +
    'begin'#13#10'  X := 1;'#13#10'end;'#13#10'end.';
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.IsTrue(InStatements(mTree, TTextPosition.Create(7, 2)));
    Assert.IsFalse(InStatements(mTree, TTextPosition.Create(5, 2)));
    Assert.IsFalse(InStatements(mTree, TTextPosition.Create(0, 0)));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TRtlTypePatternTokensTests);

end.
