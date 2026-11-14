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
  end;

implementation

function TSnapshotPolicyTests.Clean: TAtlasSnapshotState;
begin
  Result := Default(TAtlasSnapshotState);
  Result.Known := True;
  Result.Dirty := False;
  Result.Lines := 120;
  Result.Modified := True;
  Result.ReadAt := 10000;
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

initialization
  TDUnitX.RegisterTestFixture(TSnapshotPolicyTests);

end.
