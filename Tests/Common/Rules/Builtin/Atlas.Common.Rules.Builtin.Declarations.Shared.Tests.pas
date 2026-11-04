unit Atlas.Common.Rules.Builtin.Declarations.Shared.Tests;

// Tests der gemeinsamen Hilfen der Deklarationsregeln: Token zu einem Offset, Leerraum vor und hinter einer
// Stelle, Aufzählung und Name ohne Vorsatz.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationSharedTests = class
  public
    [Test]
    procedure TokenAtOffsetFindsFirstTokenFromOffset;
    [Test]
    procedure BlankBeforeAndAfter;
    [Test]
    procedure JoinedListUsesUnd;
    [Test]
    procedure BareNameDropsPrefixAndArguments;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Rules.Builtin.Declarations.Shared;

procedure TDeclarationSharedTests.TokenAtOffsetFindsFirstTokenFromOffset;
var
  mTokens: TArray<TPascalToken>;
begin
  mTokens := TPascalLexer.Tokenize('A := B;');
  Assert.AreEqual(0, TokenAtOffset(mTokens, 0));
  Assert.AreEqual(1, TokenAtOffset(mTokens, 1));
  Assert.AreEqual('B', mTokens[TokenAtOffset(mTokens, 3)].Text);
  Assert.AreEqual(Integer(Length(mTokens)), TokenAtOffset(mTokens, 100));
end;

procedure TDeclarationSharedTests.BlankBeforeAndAfter;
var
  mLines: TArray<string>;
begin
  mLines := TArray<string>.Create('  X: Integer; // Zahl', 'Y');
  Assert.IsTrue(BlankBefore(mLines, TTextPosition.Create(0, 2)));
  Assert.IsFalse(BlankBefore(mLines, TTextPosition.Create(0, 5)));
  Assert.IsTrue(BlankAfter(mLines, TTextPosition.Create(0, 13)));
  Assert.IsFalse(BlankAfter(mLines, TTextPosition.Create(0, 4)));
  Assert.IsFalse(BlankBefore(mLines, TTextPosition.Create(5, 0)));
  Assert.IsFalse(BlankAfter(mLines, TTextPosition.Create(5, 0)));
end;

procedure TDeclarationSharedTests.JoinedListUsesUnd;
begin
  Assert.AreEqual('', JoinedList(nil));
  Assert.AreEqual('A', JoinedList(TArray<string>.Create('A')));
  Assert.AreEqual('A und B', JoinedList(TArray<string>.Create('A', 'B')));
  Assert.AreEqual('A, B und C', JoinedList(TArray<string>.Create('A', 'B', 'C')));
end;

procedure TDeclarationSharedTests.BareNameDropsPrefixAndArguments;
begin
  Assert.AreEqual('TListe', BareName(' Einheit.TListe<T> '));
  Assert.AreEqual('IFoo', BareName('IFoo'));
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationSharedTests);

end.
