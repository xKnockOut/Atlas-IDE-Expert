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

initialization
  TDUnitX.RegisterTestFixture(TTextNumbersTests);

end.
