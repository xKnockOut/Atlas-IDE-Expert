unit Atlas.Common.Rules.Builtin.Inheritance.Ancestry.Tests;

// Tests der gemeinsamen Hilfen der Vererbungsregeln: Sichtbarkeit für Nachfahren.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceAncestryTests = class
  public
    [Test]
    procedure VisibilityForDescendants;
  end;

implementation

uses
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Index.Contract;

{ TInheritanceAncestryTests }

procedure TInheritanceAncestryTests.VisibilityForDescendants;
var
  mLocation: TSymbolLocation;
  mSymbol: TIndexSymbol;
begin
  mLocation := Default(TSymbolLocation);
  mSymbol := Default(TIndexSymbol);
  mSymbol.Visibility := TIndexVisibility.StrictPrivate;
  Assert.IsTrue(InvisibleToDescendant(mLocation, mSymbol));
  mSymbol.Visibility := TIndexVisibility.Private;
  Assert.IsFalse(InvisibleToDescendant(mLocation, mSymbol));
  mLocation.FileName := 'Andere.pas';
  Assert.IsTrue(InvisibleToDescendant(mLocation, mSymbol));
  mSymbol.Visibility := TIndexVisibility.Protected;
  Assert.IsFalse(InvisibleToDescendant(mLocation, mSymbol));
  mLocation := Default(TSymbolLocation);
  mSymbol := Default(TIndexSymbol);
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceAncestryTests);

end.
