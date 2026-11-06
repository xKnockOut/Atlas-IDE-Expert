unit Atlas.Common.Rules.Builtin.Inheritance.Ancestry.Tests;

// Tests der gemeinsamen Hilfen der Vererbungsregeln: Sichtbarkeit für Nachfahren, Dateiname für den Auflöser.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceAncestryTests = class
  public
    [Test]
    procedure VisibilityForDescendants;
    [Test]
    procedure FileNameForResolver;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Index.Contract;

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

procedure TInheritanceAncestryTests.FileNameForResolver;
var
  mContext: TRuleContext;
begin
  mContext := Default(TRuleContext);
  mContext.UnitName := 'Kunden';
  Assert.AreEqual('Kunden.pas', ResolverFileName(mContext));
  mContext.RelativePath := 'Src\Kunden.pas';
  Assert.AreEqual('Src\Kunden.pas', ResolverFileName(mContext));
  mContext.FileName := 'C:\Projekt\Src\Kunden.pas';
  Assert.AreEqual('C:\Projekt\Src\Kunden.pas', ResolverFileName(mContext));
  mContext := Default(TRuleContext);
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceAncestryTests);

end.
