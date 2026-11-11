unit Atlas.Core.Diagnostics.Deadline.Tests;

// Fristen auf dem 64-Bit-Tickzähler (Code-Review F-101): Eine Frist, die kurz
// vor dem Überlauf des 32-Bit-Zählers gesetzt wird, muss danach erreicht werden.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDeadlineTests = class
  private
    FNow: UInt64;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DefaultAndPassedAreReached;
    [Test]
    procedure AfterIsReachedOnlyAfterItsTime;
    /// <summary>Frist knapp vor High(Cardinal) gesetzt: nach dem 32-Bit-Überlauf erreicht, vorher nicht.</summary>
    [Test]
    procedure SurvivesThe32BitWrap;
    [Test]
    procedure RemainingCountsDownToZero;
    [Test]
    procedure SinceNeverGoesNegative;
    [Test]
    procedure RealClockAdvances;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Deadline;

procedure TAtlasDeadlineTests.Setup;
begin
  FNow := 1000;
  TAtlasTicks.SetClock(
    function: UInt64
    begin
      Result := FNow;
    end);
end;

procedure TAtlasDeadlineTests.TearDown;
begin
  TAtlasTicks.SetClock(nil);
end;

procedure TAtlasDeadlineTests.DefaultAndPassedAreReached;
var
  mDeadline: TAtlasDeadline;
begin
  mDeadline := Default(TAtlasDeadline);
  Assert.IsTrue(mDeadline.Reached);
  Assert.IsTrue(TAtlasDeadline.Passed.Reached);
  Assert.AreEqual(UInt64(0), TAtlasDeadline.Passed.RemainingMs);
end;

procedure TAtlasDeadlineTests.AfterIsReachedOnlyAfterItsTime;
var
  mDeadline: TAtlasDeadline;
begin
  mDeadline := TAtlasDeadline.After(500);
  Assert.IsFalse(mDeadline.Reached);
  FNow := 1499;
  Assert.IsFalse(mDeadline.Reached);
  FNow := 1500;
  Assert.IsTrue(mDeadline.Reached);
end;

procedure TAtlasDeadlineTests.SurvivesThe32BitWrap;
var
  mDeadline: TAtlasDeadline;
begin
  FNow := UInt64(High(Cardinal)) - 1000;
  mDeadline := TAtlasDeadline.After(5000);
  FNow := UInt64(High(Cardinal));
  Assert.IsFalse(mDeadline.Reached);
  // Der 32-Bit-Zähler stünde hier wieder bei 3998 und die alte Frist (knapp unter High(Cardinal)) wäre
  // 49 Tage lang nicht erreicht.
  FNow := UInt64(High(Cardinal)) + 3999;
  Assert.IsFalse(mDeadline.Reached);
  FNow := UInt64(High(Cardinal)) + 4000;
  Assert.IsTrue(mDeadline.Reached);
end;

procedure TAtlasDeadlineTests.RemainingCountsDownToZero;
var
  mDeadline: TAtlasDeadline;
begin
  mDeadline := TAtlasDeadline.After(300);
  Assert.AreEqual(UInt64(300), mDeadline.RemainingMs);
  FNow := 1200;
  Assert.AreEqual(UInt64(100), mDeadline.RemainingMs);
  FNow := 5000;
  Assert.AreEqual(UInt64(0), mDeadline.RemainingMs);
end;

procedure TAtlasDeadlineTests.SinceNeverGoesNegative;
begin
  Assert.AreEqual(UInt64(400), TAtlasTicks.Since(600));
  Assert.AreEqual(UInt64(0), TAtlasTicks.Since(2000));
  Assert.AreEqual(Cardinal(400), TAtlasTicks.SinceMs(600));
  FNow := UInt64(High(Cardinal)) * 3;
  Assert.AreEqual(High(Cardinal), TAtlasTicks.SinceMs(0));
end;

procedure TAtlasDeadlineTests.RealClockAdvances;
var
  mStart: UInt64;
begin
  TAtlasTicks.SetClock(nil);
  mStart := TAtlasTicks.Now;
  Sleep(20);
  Assert.IsTrue(TAtlasTicks.Since(mStart) >= 10);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDeadlineTests);

end.
