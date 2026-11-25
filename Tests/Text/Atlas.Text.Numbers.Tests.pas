unit Atlas.Text.Numbers.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextNumbersTests = class
  public
    [Test]
    procedure SignedShowsPlusOnlyAboveZero;
    [Test]
    procedure CountedPicksSingularOnlyForOne;
  end;

implementation

uses
  Atlas.Text.Numbers;

{ TTextNumbersTests }

procedure TTextNumbersTests.SignedShowsPlusOnlyAboveZero;
begin
  Assert.AreEqual('+3', TTextNumbers.Signed(3));
  Assert.AreEqual('0', TTextNumbers.Signed(0));
  Assert.AreEqual('-2', TTextNumbers.Signed(-2));
end;

procedure TTextNumbersTests.CountedPicksSingularOnlyForOne;
begin
  Assert.AreEqual('1 Wert', TTextNumbers.Counted(1, 'Wert', 'Werte'));
  Assert.AreEqual('0 Werte', TTextNumbers.Counted(0, 'Wert', 'Werte'));
  Assert.AreEqual('3 Werte', TTextNumbers.Counted(3, 'Wert', 'Werte'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextNumbersTests);

end.
