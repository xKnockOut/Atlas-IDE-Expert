unit Atlas.Core.Editor.PeekPlan.Tests;

// Definition und Referenzen einblenden (#505, #1967): Tasten und Platz des
// Fensters.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPeekPlanTests = class
  public
    [Test]
    procedure KeysWithoutShift;
    [Test]
    procedure ArrowsScrollWithOneTarget;
    [Test]
    procedure StaysExceptCloseAndOpen;
    [Test]
    procedure BelowWhenItFits;
    [Test]
    procedure AboveWhenMoreRoom;
    [Test]
    procedure ClippedToArea;
  end;

implementation

uses
  System.Classes,
  System.Types,
  Atlas.Core.Editor.PeekPlan;

{ TAtlasPeekPlanTests }

procedure TAtlasPeekPlanTests.KeysWithoutShift;
begin
  Assert.AreEqual<TAtlasPeekKey>(TAtlasPeekKey.Close, TAtlasPeekPlan.KeyOf(TAtlasPeekPlan.cKeyEscape, [], 2));
  Assert.AreEqual<TAtlasPeekKey>(TAtlasPeekKey.Open, TAtlasPeekPlan.KeyOf(TAtlasPeekPlan.cKeyReturn, [], 2));
  Assert.AreEqual<TAtlasPeekKey>(TAtlasPeekKey.PageUp, TAtlasPeekPlan.KeyOf(TAtlasPeekPlan.cKeyPrior, [], 2));
  Assert.AreEqual<TAtlasPeekKey>(TAtlasPeekKey.PageDown, TAtlasPeekPlan.KeyOf(TAtlasPeekPlan.cKeyNext, [], 2));
  Assert.AreEqual<TAtlasPeekKey>(TAtlasPeekKey.None, TAtlasPeekPlan.KeyOf(TAtlasPeekPlan.cKeyEscape, [ssShift], 2));
  Assert.AreEqual<TAtlasPeekKey>(TAtlasPeekKey.None, TAtlasPeekPlan.KeyOf(TAtlasPeekPlan.cKeyReturn, [ssCtrl], 2));
  Assert.AreEqual<TAtlasPeekKey>(TAtlasPeekKey.None, TAtlasPeekPlan.KeyOf(0, [], 2));
end;

procedure TAtlasPeekPlanTests.ArrowsScrollWithOneTarget;
begin
  Assert.AreEqual<TAtlasPeekKey>(TAtlasPeekKey.Previous, TAtlasPeekPlan.KeyOf(TAtlasPeekPlan.cKeyUp, [], 2));
  Assert.AreEqual<TAtlasPeekKey>(TAtlasPeekKey.Next, TAtlasPeekPlan.KeyOf(TAtlasPeekPlan.cKeyDown, [], 3));
  Assert.AreEqual<TAtlasPeekKey>(TAtlasPeekKey.ScrollUp, TAtlasPeekPlan.KeyOf(TAtlasPeekPlan.cKeyUp, [], 1));
  Assert.AreEqual<TAtlasPeekKey>(TAtlasPeekKey.ScrollDown, TAtlasPeekPlan.KeyOf(TAtlasPeekPlan.cKeyDown, [], 0));
end;

procedure TAtlasPeekPlanTests.StaysExceptCloseAndOpen;
begin
  Assert.IsFalse(TAtlasPeekPlan.Stays(TAtlasPeekKey.Close));
  Assert.IsFalse(TAtlasPeekPlan.Stays(TAtlasPeekKey.Open));
  Assert.IsFalse(TAtlasPeekPlan.Stays(TAtlasPeekKey.None));
  Assert.IsTrue(TAtlasPeekPlan.Stays(TAtlasPeekKey.Next));
  Assert.IsTrue(TAtlasPeekPlan.Stays(TAtlasPeekKey.PageDown));
end;

procedure TAtlasPeekPlanTests.BelowWhenItFits;
var
  mBounds: TRect;
begin
  mBounds := TAtlasPeekPlan.Bounds(TRect.Create(100, 200, 110, 216), TRect.Create(50, 0, 850, 1000),
    TRect.Create(0, 0, 1920, 1040), 300);
  Assert.AreEqual(50, mBounds.Left);
  Assert.AreEqual(217, mBounds.Top);
  Assert.AreEqual(850, mBounds.Right);
  Assert.AreEqual(517, mBounds.Bottom);
end;

procedure TAtlasPeekPlanTests.AboveWhenMoreRoom;
var
  mBounds: TRect;
begin
  mBounds := TAtlasPeekPlan.Bounds(TRect.Create(100, 900, 110, 916), TRect.Create(50, 0, 850, 1000),
    TRect.Create(0, 0, 1920, 1040), 300);
  Assert.AreEqual(599, mBounds.Top);
  Assert.AreEqual(899, mBounds.Bottom);
  // Unten weniger Platz, oben auch nicht mehr: darunter, gekürzt.
  mBounds := TAtlasPeekPlan.Bounds(TRect.Create(100, 100, 110, 116), TRect.Create(50, 0, 850, 1000),
    TRect.Create(0, 0, 1920, 300), 300);
  Assert.AreEqual(117, mBounds.Top);
  Assert.AreEqual(300, mBounds.Bottom);
end;

procedure TAtlasPeekPlanTests.ClippedToArea;
var
  mBounds: TRect;
begin
  mBounds := TAtlasPeekPlan.Bounds(TRect.Create(100, 900, 110, 916), TRect.Create(-20, 0, 2000, 1000),
    TRect.Create(0, 700, 1920, 1040), 300);
  Assert.AreEqual(0, mBounds.Left);
  Assert.AreEqual(1920, mBounds.Right);
  Assert.AreEqual(700, mBounds.Top);
  Assert.AreEqual(899, mBounds.Bottom);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPeekPlanTests);

end.
