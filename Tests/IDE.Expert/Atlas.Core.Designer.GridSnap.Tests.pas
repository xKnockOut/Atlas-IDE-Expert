unit Atlas.Core.Designer.GridSnap.Tests;

// Tests für das Einrasten am Raster des Designers.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasGridSnapTests = class
  public
    [Test]
    procedure RoundsToNearestMultiple;
    [Test]
    procedure WithoutGridUnchanged;
  end;

implementation

uses
  Atlas.Core.Designer.GridSnap;

{ TAtlasGridSnapTests }

procedure TAtlasGridSnapTests.RoundsToNearestMultiple;
begin
  Assert.AreEqual(32, TAtlasGridSnap.Snap(30, 8));
  Assert.AreEqual(24, TAtlasGridSnap.Snap(26, 8));
  Assert.AreEqual(-8, TAtlasGridSnap.Snap(-7, 8), 'negativ');
end;

procedure TAtlasGridSnapTests.WithoutGridUnchanged;
begin
  Assert.AreEqual(30, TAtlasGridSnap.Snap(30, 1));
  Assert.AreEqual(30, TAtlasGridSnap.Snap(30, 0));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGridSnapTests);

end.
