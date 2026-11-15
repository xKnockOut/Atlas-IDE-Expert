unit Atlas.Core.Tracker.SprintLoad.Tests;

// Abfrage des Bereichs „Sprint“ (#1277, #1967) ohne IDE: gewähltes Board und Rückfall auf das erste, Arbeitstage,
// Vorsprints nur mit Vergleich, Stand der Kachel nach Antwort und Fehler, wann neu geladen wird.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasSprintLoadTests = class
  public
    /// <summary>Board gelöscht bzw. ohne Zugriff (NotFound): das erste des Projekts.</summary>
    [Test]
    procedure MissingBoardFallsBackToFirst;
    [Test]
    procedure WorkDaysAndPreviousWithCompare;
    [Test]
    procedure NoPreviousWithoutCompare;
    [Test]
    procedure FailureKeepsError;
    [Test]
    procedure StateTakesAndFails;
    [Test]
    procedure RestoreWithoutCacheIsEmpty;
    [Test]
    procedure DueAfterIntervalOrCompare;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.Sprint,
  Atlas.Core.Tracker.SprintLoad;

type
  /// <summary>Board mit einem aktuellen und zwei früheren Sprints; schreibt die Anfragen mit.</summary>
  TFakeSprintBoards = class(TInterfacedObject, IAtlasTrackerBoards, IAtlasTrackerWorkDays)
  private
    FCalls: string;
    FMissing: string;
    FFails: Boolean;
  public
    function LoadBoard(const ARequest: TAtlasBoardRequest; out ASnapshot: TAtlasBoardSnapshot;
      out AError: TAtlasCiFetchError): Boolean;
    function MoveCard(const AMove: TAtlasBoardMove; const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
    function WorkDays(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport; ATimeoutMs: Integer;
      out ADays: TArray<Integer>): Boolean;
    property Calls: string read FCalls;
  end;

function Sprint(const AId: string; AStart: TDateTime): TAtlasBoardSprint;
begin
  Result := Default(TAtlasBoardSprint);
  Result.Id := AId;
  Result.Name := AId;
  Result.Start := AStart;
  Result.Finish := IncDay(AStart, 14);
end;

function TFakeSprintBoards.LoadBoard(const ARequest: TAtlasBoardRequest; out ASnapshot: TAtlasBoardSnapshot;
  out AError: TAtlasCiFetchError): Boolean;
var
  mStart: TDateTime;
begin
  FCalls := FCalls + '[' + ARequest.BoardId + '/' + ARequest.SprintId + ']';
  ASnapshot := TAtlasBoardSnapshot.Empty;
  AError := TAtlasCiFetchError.None;
  if FFails then
  begin
    AError := TAtlasCiFetchError.Timeout;
    Exit(False);
  end;
  if (FMissing <> '') and (ARequest.BoardId = FMissing) then
  begin
    AError := TAtlasCiFetchError.NotFound;
    Exit(False);
  end;
  mStart := EncodeDate(2026, 11, 2);
  ASnapshot.Board := TAtlasBoardRef.Create('b1', 'Board');
  ASnapshot.Sprints := [Sprint('s1', IncDay(mStart, -28)), Sprint('s2', IncDay(mStart, -14)), Sprint('s3', mStart)];
  ASnapshot.Sprint := ASnapshot.Sprints[2];
  if ARequest.SprintId <> '' then
  begin
    ASnapshot.Sprint := Sprint(ARequest.SprintId, IncDay(mStart, -14));
  end;
  Result := True;
end;

function TFakeSprintBoards.MoveCard(const AMove: TAtlasBoardMove;
  const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
begin
  Result := TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 0, '');
end;

function TFakeSprintBoards.WorkDays(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  ATimeoutMs: Integer; out ADays: TArray<Integer>): Boolean;
begin
  FCalls := FCalls + '[Tage]';
  ADays := [1, 2, 3, 4];
  Result := True;
end;

function Job(const ABoards: TFakeSprintBoards; const ABoardId: string; ACompare: Boolean): TAtlasSprintJob;
begin
  Result := Default(TAtlasSprintJob);
  Result.Target := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cYouTrack, 'https://firma.youtrack.cloud', 'ATL',
    '');
  Result.Boards := ABoards;
  Result.WorkDays := ABoards;
  Result.BoardId := ABoardId;
  Result.Compare := ACompare;
  Result.Outcome := TAtlasSprintResult.Failed(TAtlasSprintCalendar.WorkWeek, TAtlasCiFetchError.Network);
end;

{ TAtlasSprintLoadTests }

procedure TAtlasSprintLoadTests.MissingBoardFallsBackToFirst;
var
  mFake: TFakeSprintBoards;
  mKeep: IAtlasTrackerBoards;
  mJob: TAtlasSprintJob;
begin
  mFake := TFakeSprintBoards.Create;
  mKeep := mFake;
  mFake.FMissing := 'weg';
  mJob := Job(mFake, 'weg', False);
  mJob.Execute;
  Assert.IsTrue(mJob.Outcome.Succeeded);
  Assert.AreEqual('[weg/][/][Tage]', mFake.Calls);
  Assert.AreEqual('b1', mJob.Outcome.Snapshot.Board.Id);
  Assert.IsNull(mJob.Transport);
end;

procedure TAtlasSprintLoadTests.WorkDaysAndPreviousWithCompare;
var
  mFake: TFakeSprintBoards;
  mKeep: IAtlasTrackerBoards;
  mJob: TAtlasSprintJob;
begin
  mFake := TFakeSprintBoards.Create;
  mKeep := mFake;
  mJob := Job(mFake, '', True);
  mJob.Execute;
  Assert.IsTrue(mJob.Outcome.Succeeded);
  Assert.IsTrue(mJob.Outcome.CalendarKnown);
  Assert.AreEqual('1,2,3,4', mJob.Outcome.Calendar.Text);
  Assert.IsTrue(mJob.Outcome.WithPrevious);
  // Ohne Zwischenspeicher (Ordner '') wird jeder Vorsprint gefragt, ältester zuerst.
  Assert.AreEqual('[/][Tage][b1/s1][b1/s2]', mFake.Calls);
  Assert.AreEqual(2, Integer(Length(mJob.Outcome.Previous)));
  Assert.AreEqual('s1', mJob.Outcome.Previous[0].Id);
end;

procedure TAtlasSprintLoadTests.NoPreviousWithoutCompare;
var
  mFake: TFakeSprintBoards;
  mKeep: IAtlasTrackerBoards;
  mJob: TAtlasSprintJob;
begin
  mFake := TFakeSprintBoards.Create;
  mKeep := mFake;
  mJob := Job(mFake, 'b1', False);
  mJob.Execute;
  Assert.AreEqual('[b1/][Tage]', mFake.Calls);
  Assert.IsFalse(mJob.Outcome.WithPrevious);
  Assert.AreEqual(0, Integer(Length(mJob.Outcome.Previous)));
end;

procedure TAtlasSprintLoadTests.FailureKeepsError;
var
  mFake: TFakeSprintBoards;
  mKeep: IAtlasTrackerBoards;
  mJob: TAtlasSprintJob;
begin
  mFake := TFakeSprintBoards.Create;
  mKeep := mFake;
  mFake.FFails := True;
  mJob := Job(mFake, 'b1', True);
  mJob.Execute;
  Assert.IsFalse(mJob.Outcome.Succeeded);
  Assert.AreEqual(Integer(Ord(TAtlasCiFetchError.Timeout)), Integer(Ord(mJob.Outcome.Error)));
  Assert.AreEqual('[b1/]', mFake.Calls, 'kein Rückfall bei Zeitgrenze, keine Arbeitstage');
end;

procedure TAtlasSprintLoadTests.StateTakesAndFails;
var
  mState: TAtlasSprintState;
  mResult: TAtlasSprintResult;
  mNow: TDateTime;
begin
  mNow := EncodeDateTime(2026, 11, 15, 10, 0, 0, 0);
  mState := Default(TAtlasSprintState);
  mState.Calendar := TAtlasSprintCalendar.WorkWeek;
  mResult := TAtlasSprintResult.Failed(TAtlasSprintCalendar.Create([1, 2]), TAtlasCiFetchError.None);
  mResult.Succeeded := True;
  mResult.Snapshot := TAtlasBoardSnapshot.Empty;
  mResult.Snapshot.Board := TAtlasBoardRef.Create('b1', 'Board');
  mResult.WithPrevious := True;
  mState.Take(mResult, mNow);
  Assert.IsTrue(mState.HasSnapshot);
  Assert.AreEqual(Double(mNow), Double(mState.Snapshot.Fetched), 1E-9);
  Assert.AreEqual(TAtlasSprintCalendar.WorkWeek.Text, mState.Calendar.Text, 'Arbeitstage unbekannt: Kalender bleibt');
  mResult.CalendarKnown := True;
  mState.Take(mResult, mNow);
  Assert.AreEqual('1,2', mState.Calendar.Text);
  mState.Fail(TAtlasCiFetchError.Timeout);
  Assert.IsTrue(mState.Stale);
  Assert.IsTrue(mState.HasSnapshot, 'letzter Stand bleibt');
  Assert.AreEqual(Integer(Ord(TAtlasCiFetchError.Timeout)), Integer(Ord(mState.Error)));
  mState.Take(mResult, mNow);
  Assert.IsFalse(mState.Stale);
  Assert.AreEqual(Integer(Ord(TAtlasCiFetchError.None)), Integer(Ord(mState.Error)));
end;

procedure TAtlasSprintLoadTests.RestoreWithoutCacheIsEmpty;
var
  mState: TAtlasSprintState;
begin
  mState := Default(TAtlasSprintState);
  mState.Stale := True;
  mState.WithPrevious := True;
  mState.Restore('', TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, '', 'owner/repo', ''), 'sprint',
    'workdays');
  Assert.IsFalse(mState.HasSnapshot);
  Assert.IsFalse(mState.Stale);
  Assert.IsFalse(mState.WithPrevious);
  Assert.AreEqual(TAtlasSprintCalendar.WorkWeek.Text, mState.Calendar.Text);
end;

procedure TAtlasSprintLoadTests.DueAfterIntervalOrCompare;
var
  mMinute: UInt64;
begin
  mMinute := TAtlasSprintLoad.cMsPerMinute;
  Assert.IsTrue(TAtlasSprintLoad.Due(0, 5, 10, False, False), 'noch nie geladen');
  Assert.IsFalse(TAtlasSprintLoad.Due(1000, 1000 + 9 * mMinute, 10, False, False));
  Assert.IsTrue(TAtlasSprintLoad.Due(1000, 1000 + 10 * mMinute, 10, False, False));
  Assert.IsTrue(TAtlasSprintLoad.Due(1000, 2000, 10, True, False), 'Vergleich eingeschaltet');
  Assert.IsFalse(TAtlasSprintLoad.Due(1000, 2000, 10, True, True));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSprintLoadTests);

end.
