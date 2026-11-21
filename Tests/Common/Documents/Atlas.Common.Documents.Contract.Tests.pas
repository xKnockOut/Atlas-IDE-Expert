unit Atlas.Common.Documents.Contract.Tests;

// Tests der Bereichsabfragen von TTextRange (Atlas.Common.Documents.Contract): Encloses schließt das Ende ein,
// Contains nicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextRangeTests = class
  public
    [Test]
    procedure EnclosesIncludesEnd;
    [Test]
    procedure AnyEnclosesChecksAllRanges;
  end;

implementation

uses
  Atlas.Common.Documents.Contract;

{ TTextRangeTests }

procedure TTextRangeTests.EnclosesIncludesEnd;
var
  mRange: TTextRange;
begin
  mRange := TTextRange.Create(TTextPosition.Create(1, 4), TTextPosition.Create(2, 3));
  Assert.IsTrue(mRange.Encloses(TTextPosition.Create(1, 4)));
  Assert.IsTrue(mRange.Encloses(TTextPosition.Create(1, 99)));
  Assert.IsTrue(mRange.Encloses(TTextPosition.Create(2, 3)), 'Ende zählt mit');
  Assert.IsFalse(mRange.Contains(TTextPosition.Create(2, 3)), 'Contains schließt das Ende aus');
  Assert.IsFalse(mRange.Encloses(TTextPosition.Create(1, 3)));
  Assert.IsFalse(mRange.Encloses(TTextPosition.Create(2, 4)));
end;

procedure TTextRangeTests.AnyEnclosesChecksAllRanges;
var
  mRanges: TArray<TTextRange>;
begin
  Assert.IsFalse(TTextRange.AnyEncloses(nil, TTextPosition.Create(0, 0)));
  mRanges := [TTextRange.Create(TTextPosition.Create(0, 0), TTextPosition.Create(0, 2)),
    TTextRange.Create(TTextPosition.Create(5, 0), TTextPosition.Create(6, 0))];
  Assert.IsTrue(TTextRange.AnyEncloses(mRanges, TTextPosition.Create(6, 0)));
  Assert.IsFalse(TTextRange.AnyEncloses(mRanges, TTextPosition.Create(3, 0)));
  mRanges := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TTextRangeTests);

end.
