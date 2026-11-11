unit Atlas.Common.Rules.Builtin.Statements.Tokens.Tests;

// Tests der gemeinsamen Hilfen der Anweisungsregeln: Code-Token vor und nach
// Kommentaren, Token ab einer Stelle, schließende Klammer, Suche auf
// Klammerebene 0, Basis vor einem Index, Vergleichstext und Dateiname des
// Kontexts.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStatementTokensTests = class
  public
    [Test]
    procedure CodeTokensSkipComments;
    [Test]
    procedure TokenFromFindsFirstAtOffset;
    [Test]
    procedure ClosingAndDepthZero;
    [Test]
    procedure BaseBeforeNeedsNoDot;
    [Test]
    procedure ContextFileNameFallsBack;
    [Test]
    procedure StringTypes;
  end;

implementation

uses
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Statements.Tokens;

{ TStatementTokensTests }

procedure TStatementTokensTests.CodeTokensSkipComments;
var
  mTokens: TTokens;
begin
  mTokens := TPascalLexer.Tokenize('A { x } := // y'#10'B;');
  Assert.IsTrue(IsTrivia(mTokens[1]));
  Assert.AreEqual(2, NextCode(mTokens, 1));
  Assert.AreEqual(0, PreviousCode(mTokens, 2));
  Assert.AreEqual(':=b;', CodeKey(mTokens, 2, High(mTokens)));
  Assert.AreEqual('A { x } :=', SourceText('A { x } := // y'#10'B;', mTokens, 0, 2));
end;

procedure TStatementTokensTests.TokenFromFindsFirstAtOffset;
var
  mTokens: TTokens;
begin
  mTokens := TPascalLexer.Tokenize('A := B;');
  Assert.AreEqual(0, TokenFrom(mTokens, 0));
  Assert.AreEqual(1, TokenFrom(mTokens, 1));
  Assert.AreEqual(Integer(Length(mTokens)), TokenFrom(mTokens, 100));
end;

procedure TStatementTokensTests.ClosingAndDepthZero;
var
  mTokens: TTokens;
begin
  // F ( A , ( B ) ) do: Token 0 bis 8
  mTokens := TPascalLexer.Tokenize('F(A, (B)) do');
  Assert.AreEqual(7, MatchingParen(mTokens, 1, Length(mTokens)));
  Assert.AreEqual(-1, MatchingParen(mTokens, 1, 7));
  Assert.AreEqual(8, DepthZero(mTokens, 0, Length(mTokens), 'do', True));
  Assert.AreEqual(-1, DepthZero(mTokens, 0, Length(mTokens), ',', False));
end;

procedure TStatementTokensTests.BaseBeforeNeedsNoDot;
var
  mTokens: TTokens;
begin
  // Kunden [ und Andere . Kunden [
  mTokens := TPascalLexer.Tokenize('Kunden[I]');
  Assert.IsTrue(BaseBefore(mTokens, 1, 'kunden', 1));
  mTokens := TPascalLexer.Tokenize('Andere.Kunden[I]');
  Assert.IsFalse(BaseBefore(mTokens, 3, 'kunden', 1));
  Assert.IsTrue(BaseBefore(mTokens, 3, 'andere.kunden', 3));
end;

procedure TStatementTokensTests.ContextFileNameFallsBack;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.UnitName := 'Daten';
  Assert.AreEqual('Daten.pas', ContextFileName(mContext));
  mContext.RelativePath := 'Src/Daten.pas';
  Assert.AreEqual('Src/Daten.pas', ContextFileName(mContext));
  mContext.FileName := 'C:\Src\Daten.pas';
  Assert.AreEqual('C:\Src\Daten.pas', ContextFileName(mContext));
end;

procedure TStatementTokensTests.StringTypes;
begin
  Assert.IsTrue(IsStringType('string'));
  Assert.IsTrue(IsStringType('AnsiString'));
  Assert.IsFalse(IsStringType('Integer'));
  Assert.IsFalse(IsStringType(''));
end;

initialization
  TDUnitX.RegisterTestFixture(TStatementTokensTests);

end.
