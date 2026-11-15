unit Atlas.Core.Debug.StopProgress.Tests;

// Tests für den Ablauf je Halt der Anzeigen im Editor (#508, #1878, #1967): Phase, Nachfragen am
// Ausführungspunkt, jüngste Antwort, derselbe Halt; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasStopProgressTests = class
  public
    [Test]
    procedure RestartReadsLocation;
    [Test]
    procedure LocateReadyOrGiveUp;
    [Test]
    procedure LocateRetriesUpToLimit;
    [Test]
    procedure OnlyNewestAnswerCounts;
    [Test]
    procedure StillAtSameStop;
  end;

implementation

uses
  Atlas.Core.Debug.StopProgress;

{ TAtlasStopProgressTests }

procedure TAtlasStopProgressTests.RestartReadsLocation;
var
  mProgress: TAtlasStopProgress;
begin
  mProgress := Default(TAtlasStopProgress);
  mProgress.Retries := 5;
  mProgress.Restart(3);
  Assert.AreEqual<TAtlasStopPhase>(TAtlasStopPhase.Location, mProgress.Phase);
  Assert.AreEqual(3, mProgress.Stop);
  Assert.AreEqual(0, mProgress.Retries);
end;

procedure TAtlasStopProgressTests.LocateReadyOrGiveUp;
var
  mProgress: TAtlasStopProgress;
begin
  mProgress := Default(TAtlasStopProgress);
  mProgress.Restart(1);
  Assert.AreEqual<TAtlasStopLocation>(TAtlasStopLocation.Ready, mProgress.Locate(False, False, True, 2));
  Assert.AreEqual<TAtlasStopPhase>(TAtlasStopPhase.Request, mProgress.Phase);
  mProgress.Restart(2);
  Assert.AreEqual<TAtlasStopLocation>(TAtlasStopLocation.GiveUp, mProgress.Locate(True, False, False, 2));
  Assert.AreEqual<TAtlasStopPhase>(TAtlasStopPhase.Idle, mProgress.Phase);
  // Ohne Quelltext hilft auch ein Editor nicht.
  mProgress.Restart(3);
  Assert.AreEqual<TAtlasStopLocation>(TAtlasStopLocation.GiveUp, mProgress.Locate(False, True, True, 2));
end;

procedure TAtlasStopProgressTests.LocateRetriesUpToLimit;
var
  mProgress: TAtlasStopProgress;
begin
  mProgress := Default(TAtlasStopProgress);
  mProgress.Restart(1);
  Assert.AreEqual<TAtlasStopLocation>(TAtlasStopLocation.Retry, mProgress.Locate(False, False, False, 2));
  Assert.AreEqual<TAtlasStopLocation>(TAtlasStopLocation.Retry, mProgress.Locate(False, False, False, 2));
  Assert.AreEqual<TAtlasStopPhase>(TAtlasStopPhase.Location, mProgress.Phase);
  Assert.AreEqual<TAtlasStopLocation>(TAtlasStopLocation.GiveUp, mProgress.Locate(False, False, False, 2));
  Assert.AreEqual<TAtlasStopPhase>(TAtlasStopPhase.Idle, mProgress.Phase);
end;

procedure TAtlasStopProgressTests.OnlyNewestAnswerCounts;
var
  mProgress: TAtlasStopProgress;
  mFirst, mSecond: Integer;
begin
  mProgress := Default(TAtlasStopProgress);
  mProgress.Phase := TAtlasStopPhase.Request;
  mFirst := mProgress.NextRequest;
  mSecond := mProgress.NextRequest;
  Assert.IsFalse(mProgress.Accepts(mFirst));
  Assert.IsTrue(mProgress.Accepts(mSecond));
  mProgress.Phase := TAtlasStopPhase.Evaluate;
  Assert.IsFalse(mProgress.Accepts(mSecond));
  Assert.IsTrue(mProgress.IsNewest(mSecond));
  // Verworfen (Fortsetzen): auch die jüngste zählt nicht mehr.
  mProgress.Discard;
  Assert.IsFalse(mProgress.IsNewest(mSecond));
  Assert.AreEqual<TAtlasStopPhase>(TAtlasStopPhase.Idle, mProgress.Phase);
end;

procedure TAtlasStopProgressTests.StillAtSameStop;
var
  mProgress: TAtlasStopProgress;
begin
  mProgress := Default(TAtlasStopProgress);
  mProgress.Restart(4);
  Assert.IsTrue(mProgress.StillAt(4, True));
  Assert.IsFalse(mProgress.StillAt(5, True));
  Assert.IsFalse(mProgress.StillAt(4, False));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStopProgressTests);

end.
