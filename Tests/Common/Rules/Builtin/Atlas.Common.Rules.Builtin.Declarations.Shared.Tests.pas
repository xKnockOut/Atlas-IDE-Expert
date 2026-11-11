unit Atlas.Common.Rules.Builtin.Declarations.Shared.Tests;

// Tests der gemeinsamen Hilfen der Deklarationsregeln: Leerraum vor und hinter einer Stelle,
// Aufzählung und Name ohne Vorsatz.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationSharedTests = class
  public
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
  Atlas.Common.Rules.Builtin.Declarations.Shared;

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
