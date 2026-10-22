unit Atlas.Common.Pascal.ConditionalBranches.Tests;

// Tests der Zweige bedingter Übersetzung (#983, #986): Pfade je Token mit
// {$IFDEF}, {$ELSEIF}, {$ELSE} und Verschachtelung, Ausschluss und Einschluss.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConditionalBranchesTests = class
  public
    [Test]
    procedure PathsPerToken;
    [Test]
    procedure WithoutConditionsEmpty;
    [Test]
    procedure ExclusiveAndImplies;
  end;

implementation

uses
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.ConditionalBranches;

function PathOf(const ATokens: TArray<TPascalToken>; const APaths: TArray<string>; const AText: string): string;
var
  Index: Integer;
begin
  Result := '?';
  for Index := 0 to High(ATokens) do
    if ATokens[Index].Text = AText then
      Exit(TConditionalBranches.PathAt(APaths, Index));
end;

procedure TConditionalBranchesTests.PathsPerToken;
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
begin
  Tokens := TPascalLexer.Tokenize('A {$IFDEF X} B {$IFNDEF Y} C {$ENDIF} {$ELSEIF Defined(Z)} D {$ELSE} E {$ENDIF} F ' +
    '{$IF A} G {$IFEND}');
  Paths := TConditionalBranches.Paths(Tokens);
  Assert.AreEqual(Integer(Length(Tokens)), Integer(Length(Paths)));
  Assert.AreEqual('', PathOf(Tokens, Paths, 'A'));
  Assert.AreEqual('0.0', PathOf(Tokens, Paths, 'B'));
  Assert.AreEqual('0.0/1.0', PathOf(Tokens, Paths, 'C'));
  Assert.AreEqual('0.1', PathOf(Tokens, Paths, 'D'));
  Assert.AreEqual('0.2', PathOf(Tokens, Paths, 'E'));
  Assert.AreEqual('', PathOf(Tokens, Paths, 'F'));
  Assert.AreEqual('2.0', PathOf(Tokens, Paths, 'G'));
end;

procedure TConditionalBranchesTests.WithoutConditionsEmpty;
begin
  Assert.AreEqual(0, Integer(Length(TConditionalBranches.Paths(TPascalLexer.Tokenize('A {$R+} B')))));
  Assert.AreEqual('', TConditionalBranches.PathAt(nil, 3));
end;

procedure TConditionalBranchesTests.ExclusiveAndImplies;
begin
  Assert.IsTrue(TConditionalBranches.Exclusive('0.0', '0.1'));
  Assert.IsTrue(TConditionalBranches.Exclusive('0.0/1.0', '0.2'));
  Assert.IsFalse(TConditionalBranches.Exclusive('0.0', '0.0/1.0'));
  Assert.IsFalse(TConditionalBranches.Exclusive('0.0', '2.0'));
  Assert.IsFalse(TConditionalBranches.Exclusive('', '0.1'));
  Assert.IsTrue(TConditionalBranches.Implies('0.0/1.0', '0.0'));
  Assert.IsTrue(TConditionalBranches.Implies('0.0', ''));
  Assert.IsTrue(TConditionalBranches.Implies('0.0', '0.0'));
  Assert.IsFalse(TConditionalBranches.Implies('0.0', '0.0/1.0'));
  Assert.IsFalse(TConditionalBranches.Implies('', '0.0'));
  Assert.IsFalse(TConditionalBranches.Implies('10.0', '1.0'));
end;

initialization
  TDUnitX.RegisterTestFixture(TConditionalBranchesTests);

end.
