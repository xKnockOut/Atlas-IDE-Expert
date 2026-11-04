unit Atlas.Common.Rules.Builtin.Style.Tokens.Tests;

// Tests der gemeinsamen Tokenhilfen der Stilregeln: Kommentare und
// Compileranweisungen überspringen und den Bereich einer Tokenfolge bilden.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStyleTokensTests = class
  public
    [Test]
    procedure TriviaAreCommentsAndDirectives;
    [Test]
    procedure NextAndPreviousSkipTrivia;
    [Test]
    procedure NextAndPreviousAtTheEdges;
    [Test]
    procedure RangeSpansFirstToLast;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Rules.Builtin.Style.Tokens;

{ TStyleTokensTests }

procedure TStyleTokensTests.TriviaAreCommentsAndDirectives;
var
  mTokens: TTokens;
begin
  // A { x } {$IFDEF Y} B
  mTokens := TPascalLexer.Tokenize('A { x } {$IFDEF Y} B');
  Assert.IsFalse(IsTrivia(mTokens[0]));
  Assert.IsTrue(IsTrivia(mTokens[1]));
  Assert.IsTrue(IsTrivia(mTokens[2]));
  Assert.IsFalse(IsTrivia(mTokens[3]));
end;

procedure TStyleTokensTests.NextAndPreviousSkipTrivia;
var
  mTokens: TTokens;
begin
  mTokens := TPascalLexer.Tokenize('A { x } {$IFDEF Y} B');
  Assert.AreEqual(3, NextCode(mTokens, 1));
  Assert.AreEqual(0, NextCode(mTokens, 0));
  Assert.AreEqual(0, PreviousCode(mTokens, 3));
end;

procedure TStyleTokensTests.NextAndPreviousAtTheEdges;
var
  mTokens: TTokens;
begin
  mTokens := TPascalLexer.Tokenize('A { x }');
  Assert.AreEqual(Integer(Length(mTokens)), NextCode(mTokens, 1));
  Assert.AreEqual(-1, PreviousCode(mTokens, 0));
end;

procedure TStyleTokensTests.RangeSpansFirstToLast;
var
  mTokens: TTokens;
  mRange: TTextRange;
begin
  mTokens := TPascalLexer.Tokenize('A := B;');
  mRange := RangeOf(mTokens, 0, 2);
  Assert.IsTrue(mRange.StartPos = mTokens[0].StartPos);
  Assert.IsTrue(mRange.EndPos = mTokens[2].EndPos);
end;

initialization
  TDUnitX.RegisterTestFixture(TStyleTokensTests);

end.
