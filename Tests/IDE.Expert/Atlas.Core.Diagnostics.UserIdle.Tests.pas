unit Atlas.Core.Diagnostics.UserIdle.Tests;

// Zeit seit der letzten Eingabe: Differenz auf dem 32-Bit-Zähler über den Überlauf hinweg.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUserIdleTests = class
  public
    [Test]
    procedure ElapsedWithoutWrap;
    [Test]
    procedure ElapsedAcrossWrap;
    [Test]
    procedure IdleMsIsPlausible;
  end;

implementation

uses
  Atlas.Core.Diagnostics.UserIdle;

procedure TAtlasUserIdleTests.ElapsedWithoutWrap;
begin
  Assert.AreEqual(Cardinal(0), TAtlasUserIdle.Elapsed(500, 500));
  Assert.AreEqual(Cardinal(250), TAtlasUserIdle.Elapsed(750, 500));
end;

procedure TAtlasUserIdleTests.ElapsedAcrossWrap;
begin
  Assert.AreEqual(Cardinal(1), TAtlasUserIdle.Elapsed(0, High(Cardinal)));
  Assert.AreEqual(Cardinal(356), TAtlasUserIdle.Elapsed(100, $FFFFFF00));
end;

procedure TAtlasUserIdleTests.IdleMsIsPlausible;
var
  mMs: Cardinal;
begin
  // Ohne Sitzung (Dienst, CI) darf Windows den Stand verweigern; dann ist das Ergebnis 0.
  if not TAtlasUserIdle.IdleMs(mMs) then
  begin
    Assert.AreEqual(Cardinal(0), mMs);
  end
  else
  begin
    Assert.IsTrue(mMs < High(Cardinal));
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUserIdleTests);

end.
