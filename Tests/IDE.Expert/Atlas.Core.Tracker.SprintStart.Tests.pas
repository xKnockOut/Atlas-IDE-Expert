unit Atlas.Core.Tracker.SprintStart.Tests;

// Tests der Entscheidung „in den laufenden Sprint aufnehmen?“ beim Beginnen
// (#2128) und des Befehls für YouTrack.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasSprintStartTests = class
  public
    [Test]
    procedure IssueOutsideRunningSprintIsMissing;
    [Test]
    procedure IssueInSprintIsNotMissing;
    [Test]
    procedure OnlyRunningAgileSprintsCount;
    [Test]
    procedure FullSnapshotAsksNothing;
    [Test]
    procedure CommandAddsToSprint;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.SprintStart,
  Atlas.Core.Tracker.YouTrackApi;

function NowUtc: TDateTime;
begin
  Result := EncodeDateTime(2026, 11, 12, 9, 0, 0, 0);
end;

function Card(const AKey: string): TAtlasBoardCard;
begin
  Result := Default(TAtlasBoardCard);
  Result.Key := AKey;
end;

function Snapshot: TAtlasBoardSnapshot;
begin
  Result := TAtlasBoardSnapshot.Empty;
  Result.Kind := TAtlasBoardKind.Agile;
  Result.Board := TAtlasBoardRef.Create('108-4', 'Atlas-Board');
  Result.Sprint.Id := '109-47';
  Result.Sprint.Name := 'Sprint 47';
  Result.Sprint.Start := EncodeDate(2026, 11, 5);
  Result.Sprint.Finish := EncodeDate(2026, 11, 19);
  Result.Cards := [Card('ATL-2052'), Card('ATL-2060')];
end;

procedure TAtlasSprintStartTests.IssueOutsideRunningSprintIsMissing;
var
  mSprint: TAtlasTrackerSprintRef;
begin
  Assert.IsTrue(TAtlasSprintStart.Missing(Snapshot, 'ATL-2071', NowUtc, mSprint));
  Assert.AreEqual('Atlas-Board', mSprint.Board);
  Assert.AreEqual('Sprint 47', mSprint.Sprint);
  Assert.IsTrue(SameDate(EncodeDate(2026, 11, 19), mSprint.Finish));
  Assert.IsTrue(mSprint.IsSet);
end;

procedure TAtlasSprintStartTests.IssueInSprintIsNotMissing;
var
  mSprint: TAtlasTrackerSprintRef;
begin
  Assert.IsFalse(TAtlasSprintStart.Missing(Snapshot, 'atl-2052', NowUtc, mSprint), 'Kennung ohne Groß/klein');
  Assert.IsFalse(mSprint.IsSet);
  Assert.IsFalse(TAtlasSprintStart.Missing(Snapshot, ' ', NowUtc, mSprint), 'ohne Kennung');
end;

procedure TAtlasSprintStartTests.OnlyRunningAgileSprintsCount;
var
  mSnapshot: TAtlasBoardSnapshot;
  mSprint: TAtlasTrackerSprintRef;
begin
  mSnapshot := Snapshot;
  mSnapshot.Sprint.Finish := EncodeDate(2026, 11, 10);
  Assert.IsFalse(TAtlasSprintStart.Missing(mSnapshot, 'ATL-2071', NowUtc, mSprint), 'Sprint vorbei');
  mSnapshot := Snapshot;
  mSnapshot.Sprint.Start := EncodeDate(2026, 11, 20);
  mSnapshot.Sprint.Finish := 0;
  Assert.IsFalse(TAtlasSprintStart.Missing(mSnapshot, 'ATL-2071', NowUtc, mSprint), 'Sprint noch nicht begonnen');
  mSnapshot := Snapshot;
  mSnapshot.Sprint.Archived := True;
  Assert.IsFalse(TAtlasSprintStart.Missing(mSnapshot, 'ATL-2071', NowUtc, mSprint), 'archiviert');
  mSnapshot := Snapshot;
  mSnapshot.Sprint := Default(TAtlasBoardSprint);
  Assert.IsFalse(TAtlasSprintStart.Missing(mSnapshot, 'ATL-2071', NowUtc, mSprint), 'Board ohne Sprints');
  mSnapshot := Snapshot;
  mSnapshot.Kind := TAtlasBoardKind.Project;
  Assert.IsFalse(TAtlasSprintStart.Missing(mSnapshot, 'ATL-2071', NowUtc, mSprint), 'GitHub-Projekt');
  mSnapshot := Snapshot;
  mSnapshot.Sprint.Start := 0;
  mSnapshot.Sprint.Finish := 0;
  Assert.IsTrue(TAtlasSprintStart.Missing(mSnapshot, 'ATL-2071', NowUtc, mSprint), 'ohne Daten: offen');
end;

procedure TAtlasSprintStartTests.FullSnapshotAsksNothing;
var
  mSnapshot: TAtlasBoardSnapshot;
  mSprint: TAtlasTrackerSprintRef;
  mIndex: Integer;
begin
  mSnapshot := Snapshot;
  SetLength(mSnapshot.Cards, TAtlasBoardSnapshot.cMaxCards);
  for mIndex := 0 to High(mSnapshot.Cards) do
  begin
    mSnapshot.Cards[mIndex] := Card('ATL-' + IntToStr(mIndex + 1));
  end;
  Assert.IsFalse(TAtlasSprintStart.Missing(mSnapshot, 'ATL-2071', NowUtc, mSprint), 'Stand evtl. unvollständig');
end;

procedure TAtlasSprintStartTests.CommandAddsToSprint;
var
  mChange: TAtlasTrackerWrite;
begin
  Assert.AreEqual('Board Atlas-Board {Sprint 47}',
    TAtlasYouTrackBodies.SprintQuery(TAtlasTrackerSprintRef.Create('Atlas-Board', 'Sprint 47', 0)));
  Assert.AreEqual('', TAtlasYouTrackBodies.SprintQuery(TAtlasTrackerSprintRef.None));
  mChange := TAtlasTrackerWrite.Empty;
  mChange.State := 'In Arbeit';
  mChange.Assign := TAtlasTrackerAssign.Me;
  mChange.Sprint := TAtlasTrackerSprintRef.Create('Atlas', 'S47', 0);
  Assert.AreEqual('State {In Arbeit} Assignee me Board Atlas S47', TAtlasYouTrackBodies.CommandQuery(mChange));
  mChange := TAtlasTrackerWrite.Empty;
  Assert.IsFalse(mChange.HasWork);
  mChange.Sprint := TAtlasTrackerSprintRef.Create('Atlas', 'S47', 0);
  Assert.IsTrue(mChange.HasWork, 'nur der Sprint');
  Assert.AreEqual('Board Atlas S47', TAtlasYouTrackBodies.CommandQuery(mChange));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSprintStartTests);

end.
