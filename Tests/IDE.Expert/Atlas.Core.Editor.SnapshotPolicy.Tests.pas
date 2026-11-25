unit Atlas.Core.Editor.SnapshotPolicy.Tests;

// Tests für die Entscheidung, wann der gemeinsame Pufferstand neu gelesen wird.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Editor.SnapshotPolicy;

type
  [TestFixture]
  TSnapshotPolicyTests = class
  private
    function Clean: TAtlasSnapshotState;
    function Quiet(ASafetyMs: Cardinal): TAtlasSnapshotState;
  public
    [Test]
    procedure UnknownMustRead;
    [Test]
    procedure DirtyMustRead;
    [Test]
    procedure CleanSameStateSkips;
    [Test]
    procedure LineCountChangedMustRead;
    [Test]
    procedure ModifiedFlagChangedMustRead;
    [Test]
    procedure SafetyIntervalMustRead;
    [Test]
    procedure TickWrapAroundMustRead;
    [Test]
    procedure FirstReadUsesShortInterval;
    [Test]
    procedure QuietSafetyReadDoubles;
    [Test]
    procedure QuietSafetyReadsStopAtMaximum;
    [Test]
    procedure LongIntervalSkipsBeforeExpiry;
    [Test]
    procedure TextChangedWithoutEventResets;
    [Test]
    procedure TextChangedAfterEventResets;
    [Test]
    procedure EventReadWithoutChangeKeepsInterval;
    [Test]
    procedure TickWrapAroundKeepsInterval;
    [Test]
    procedure ReadStoresState;
  end;

implementation

{ TSnapshotPolicyTests }

function TSnapshotPolicyTests.Clean: TAtlasSnapshotState;
begin
  Result := Default(TAtlasSnapshotState);
  Result.Known := True;
  Result.Dirty := False;
  Result.Lines := 120;
  Result.Modified := True;
  Result.ReadAt := 10000;
end;

function TSnapshotPolicyTests.Quiet(ASafetyMs: Cardinal): TAtlasSnapshotState;
begin
  Result := Clean;
  Result.SafetyMs := ASafetyMs;
end;

procedure TSnapshotPolicyTests.UnknownMustRead;
var
  mState: TAtlasSnapshotState;
begin
  mState := Clean;
  mState.Known := False;
  Assert.IsTrue(TAtlasSnapshotPolicy.MustRead(mState, 120, True, 10001));
end;

procedure TSnapshotPolicyTests.DirtyMustRead;
var
  mState: TAtlasSnapshotState;
begin
  mState := Clean;
  mState.Dirty := True;
  Assert.IsTrue(TAtlasSnapshotPolicy.MustRead(mState, 120, True, 10001));
end;

procedure TSnapshotPolicyTests.CleanSameStateSkips;
begin
  Assert.IsFalse(TAtlasSnapshotPolicy.MustRead(Clean, 120, True, 10000));
  Assert.IsFalse(TAtlasSnapshotPolicy.MustRead(Clean, 120, True, 10000 + TAtlasSnapshotPolicy.cSafetyMs - 1));
end;

procedure TSnapshotPolicyTests.LineCountChangedMustRead;
begin
  Assert.IsTrue(TAtlasSnapshotPolicy.MustRead(Clean, 121, True, 10001));
end;

procedure TSnapshotPolicyTests.ModifiedFlagChangedMustRead;
begin
  Assert.IsTrue(TAtlasSnapshotPolicy.MustRead(Clean, 120, False, 10001));
end;

procedure TSnapshotPolicyTests.SafetyIntervalMustRead;
begin
  Assert.IsTrue(TAtlasSnapshotPolicy.MustRead(Clean, 120, True, 10000 + TAtlasSnapshotPolicy.cSafetyMs));
end;

procedure TSnapshotPolicyTests.TickWrapAroundMustRead;
begin
  // Uhr zurückgesetzt: jetzt kleiner als beim Lesen.
  Assert.IsTrue(TAtlasSnapshotPolicy.MustRead(Clean, 120, True, 5));
end;

procedure TSnapshotPolicyTests.FirstReadUsesShortInterval;
var
  mState: TAtlasSnapshotState;
begin
  mState := Default(TAtlasSnapshotState);
  TAtlasSnapshotPolicy.Read(mState, 120, False, 500, True);
  Assert.AreEqual(Cardinal(TAtlasSnapshotPolicy.cSafetyMs), TAtlasSnapshotPolicy.SafetyMs(mState));
end;

procedure TSnapshotPolicyTests.QuietSafetyReadDoubles;
var
  mState: TAtlasSnapshotState;
begin
  mState := Clean;
  TAtlasSnapshotPolicy.Read(mState, 120, True, 12000, False);
  Assert.AreEqual(Cardinal(4000), TAtlasSnapshotPolicy.SafetyMs(mState));
  TAtlasSnapshotPolicy.Read(mState, 120, True, 16000, False);
  Assert.AreEqual(Cardinal(8000), TAtlasSnapshotPolicy.SafetyMs(mState));
end;

procedure TSnapshotPolicyTests.QuietSafetyReadsStopAtMaximum;
var
  mState: TAtlasSnapshotState;
  mNow: UInt64;
  mRound: Integer;
begin
  mState := Clean;
  mNow := mState.ReadAt;
  for mRound := 1 to 10 do
  begin
    mNow := mNow + TAtlasSnapshotPolicy.SafetyMs(mState);
    Assert.IsTrue(TAtlasSnapshotPolicy.MustRead(mState, 120, True, mNow));
    TAtlasSnapshotPolicy.Read(mState, 120, True, mNow, False);
  end;
  Assert.AreEqual(Cardinal(TAtlasSnapshotPolicy.cSafetyMaxMs), TAtlasSnapshotPolicy.SafetyMs(mState));
end;

procedure TSnapshotPolicyTests.LongIntervalSkipsBeforeExpiry;
begin
  Assert.IsFalse(TAtlasSnapshotPolicy.MustRead(Quiet(16000), 120, True, 10000 + 16000 - 1));
  Assert.IsTrue(TAtlasSnapshotPolicy.MustRead(Quiet(16000), 120, True, 10000 + 16000));
end;

procedure TSnapshotPolicyTests.TextChangedWithoutEventResets;
var
  mState: TAtlasSnapshotState;
begin
  mState := Quiet(TAtlasSnapshotPolicy.cSafetyMaxMs);
  TAtlasSnapshotPolicy.Read(mState, 120, True, 10000 + TAtlasSnapshotPolicy.cSafetyMaxMs, True);
  Assert.AreEqual(Cardinal(TAtlasSnapshotPolicy.cSafetyMs), TAtlasSnapshotPolicy.SafetyMs(mState));
end;

procedure TSnapshotPolicyTests.TextChangedAfterEventResets;
var
  mState: TAtlasSnapshotState;
begin
  mState := Quiet(16000);
  mState.Dirty := True;
  TAtlasSnapshotPolicy.Read(mState, 121, True, 10500, True);
  Assert.AreEqual(Cardinal(TAtlasSnapshotPolicy.cSafetyMs), TAtlasSnapshotPolicy.SafetyMs(mState));
end;

procedure TSnapshotPolicyTests.EventReadWithoutChangeKeepsInterval;
var
  mState: TAtlasSnapshotState;
begin
  mState := Quiet(8000);
  mState.Dirty := True;
  TAtlasSnapshotPolicy.Read(mState, 120, True, 20000, False);
  Assert.AreEqual(Cardinal(8000), TAtlasSnapshotPolicy.SafetyMs(mState));
  mState := Quiet(8000);
  TAtlasSnapshotPolicy.Read(mState, 120, False, 20000, False);
  Assert.AreEqual(Cardinal(8000), TAtlasSnapshotPolicy.SafetyMs(mState));
end;

procedure TSnapshotPolicyTests.TickWrapAroundKeepsInterval;
var
  mState: TAtlasSnapshotState;
begin
  mState := Quiet(8000);
  TAtlasSnapshotPolicy.Read(mState, 120, True, 5, False);
  Assert.AreEqual(Cardinal(8000), TAtlasSnapshotPolicy.SafetyMs(mState));
end;

procedure TSnapshotPolicyTests.ReadStoresState;
var
  mState: TAtlasSnapshotState;
begin
  mState := Clean;
  mState.Dirty := True;
  TAtlasSnapshotPolicy.Read(mState, 140, False, 30000, True);
  Assert.IsTrue(mState.Known);
  Assert.IsFalse(mState.Dirty);
  Assert.AreEqual(140, mState.Lines);
  Assert.IsFalse(mState.Modified);
  Assert.AreEqual<UInt64>(UInt64(30000), mState.ReadAt);
  Assert.IsFalse(TAtlasSnapshotPolicy.MustRead(mState, 140, False, 30001));
end;

initialization
  TDUnitX.RegisterTestFixture(TSnapshotPolicyTests);

end.
