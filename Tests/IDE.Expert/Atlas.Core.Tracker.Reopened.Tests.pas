unit Atlas.Core.Tracker.Reopened.Tests;

// Tests der wieder geöffneten Issues (#2127) ohne VCL: Erledigt sind
// Zielzustände und Prüfzustände (issues.reviewStates); eine Meldung mit
// Wechsel von erledigt nach offen setzt die Marke mit dem neuesten Kommentar;
// beim Laden der Liste wird ein erledigt gesehenes, beendetes Issue, das
// offen in der Liste steht, erkannt; Branch und Zeitpunkt des Beendens gehen
// in die Marke über; Kommentare vor dem Beenden sind kein Grund; Marken
// ersetzen sich, behalten den Grund und fallen nach cMaxEntries heraus;
// Speichern und Lesen im Abschnitt "issues"; „Beginnen“ nimmt die Marke weg.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerReopenedTests = class
  public
    [Test]
    procedure ReviewStatesCountAsDone;
    [Test]
    procedure NoticeFromDoneToOpenMarks;
    [Test]
    procedure NoticeWithoutReturnDoesNotMark;
    [Test]
    procedure ListSeesDoneThenOpen;
    [Test]
    procedure EndedMovesIntoMark;
    [Test]
    procedure MarkKeepsBranchAndReason;
    [Test]
    procedure ListsAreLimited;
    [Test]
    procedure LatestForeignComment;
    [Test]
    procedure ConcernsEndedOrListed;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure StartDismissesMark;
    [Test]
    procedure ResumeUsesRememberedBranch;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.DateUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.Notify,
  Atlas.Core.Tracker.Reopened;

function T0: TDateTime;
begin
  Result := EncodeDate(2026, 11, 12) + EncodeTime(9, 0, 0, 0);
end;

function YouTrack: TAtlasTrackerDoneStates;
begin
  Result := TAtlasTrackerDoneStates.Create('youtrack', TArray<string>.Create('Erledigt'),
    TArray<string>.Create('Zur Prüfung'));
end;

function Item(const AKey, AState: string): TAtlasTrackerIssue;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := AKey;
  Result.Title := 'Titel ' + AKey;
  Result.State := AState;
end;

function Ended(const AKey, ABranch: string; AAt: TDateTime; ADone: Boolean): TAtlasTrackerEnded;
begin
  Result := Default(TAtlasTrackerEnded);
  Result.Key := AKey;
  Result.Branch := ABranch;
  Result.At := AAt;
  Result.Done := ADone;
end;

function Comment(const AAuthor: string; ACreated: TDateTime; const AText: string): TAtlasTrackerComment;
begin
  Result.Author := AAuthor;
  Result.Created := ACreated;
  Result.Text := AText;
end;

{ TAtlasTrackerReopenedTests }

procedure TAtlasTrackerReopenedTests.ReviewStatesCountAsDone;
var
  mDone: TAtlasTrackerDoneStates;
begin
  mDone := YouTrack;
  Assert.IsTrue(mDone.IsDone('Erledigt'));
  Assert.IsTrue(mDone.IsDone('zur prüfung'), 'Prüfzustand ohne Groß-/Kleinschreibung');
  Assert.IsTrue(mDone.IsReview(' Zur Prüfung '));
  Assert.IsFalse(mDone.IsDone('In Bearbeitung'));
  Assert.IsFalse(mDone.IsDone(''));
  Assert.IsTrue(TAtlasTrackerReopened.IsReopen(mDone, 'Zur Prüfung', 'In Bearbeitung'));
  Assert.IsTrue(TAtlasTrackerReopened.IsReopen(mDone, 'Erledigt', 'Offen'));
  Assert.IsFalse(TAtlasTrackerReopened.IsReopen(mDone, 'Offen', 'In Bearbeitung'));
  Assert.IsFalse(TAtlasTrackerReopened.IsReopen(mDone, 'Zur Prüfung', 'Erledigt'), 'Prüfung bestanden');
  Assert.IsFalse(TAtlasTrackerReopened.IsReopen(mDone, 'Erledigt', ''));
  mDone := TAtlasTrackerDoneStates.Create('github', nil, nil);
  Assert.IsTrue(TAtlasTrackerReopened.IsReopen(mDone, 'closed', 'open'));
end;

procedure TAtlasTrackerReopenedTests.NoticeFromDoneToOpenMarks;
var
  mNotice: TAtlasTrackerNotice;
  mReopen: TAtlasTrackerReopen;
begin
  mNotice := Default(TAtlasTrackerNotice);
  mNotice.Key := 'ATL-7';
  mNotice.Title := 'Arbeitsstand';
  mNotice.StateChanged := True;
  mNotice.Previous := 'Zur Prüfung';
  mNotice.State := 'In Bearbeitung';
  mNotice.LastComment := 'Lesezeichen' + sLineBreak + 'fehlen.';
  mNotice.LastCommentBy := 'Jana';
  mNotice.LastCommentAt := T0;
  mNotice.Time := T0;
  Assert.IsTrue(TAtlasTrackerReopened.FromNotice(YouTrack, mNotice, mReopen));
  Assert.AreEqual('ATL-7', mReopen.Key);
  Assert.AreEqual('Zur Prüfung', mReopen.Previous);
  Assert.AreEqual('In Bearbeitung', mReopen.State);
  Assert.AreEqual('Lesezeichen fehlen.', mReopen.Comment, 'Zeilenumbruch zu Leerzeichen');
  Assert.AreEqual('Jana', mReopen.CommentBy);
  Assert.AreEqual(T0, mReopen.CommentAt);
end;

procedure TAtlasTrackerReopenedTests.NoticeWithoutReturnDoesNotMark;
var
  mNotice: TAtlasTrackerNotice;
  mReopen: TAtlasTrackerReopen;
begin
  mNotice := Default(TAtlasTrackerNotice);
  mNotice.Key := 'ATL-7';
  mNotice.Comments := 1;
  mNotice.LastComment := 'Nur ein Kommentar';
  Assert.IsFalse(TAtlasTrackerReopened.FromNotice(YouTrack, mNotice, mReopen), 'ohne Zustandswechsel');
  mNotice.StateChanged := True;
  mNotice.Previous := 'Offen';
  mNotice.State := 'In Bearbeitung';
  Assert.IsFalse(TAtlasTrackerReopened.FromNotice(YouTrack, mNotice, mReopen), 'von offen nach offen');
  Assert.AreEqual('', mReopen.Key);
end;

procedure TAtlasTrackerReopenedTests.ListSeesDoneThenOpen;
var
  mEnded: TArray<TAtlasTrackerEnded>;
  mFound: TArray<TAtlasTrackerReopen>;
begin
  // Ohne Zustand beendet: erst in der Prüfung gesehen, dann offen.
  mEnded := TArray<TAtlasTrackerEnded>.Create(Ended('ATL-1', 'issue/ATL-1', T0, False),
    Ended('ATL-2', 'issue/ATL-2', T0, False));
  mFound := TAtlasTrackerReopened.FromList(YouTrack, mEnded,
    TArray<TAtlasTrackerIssue>.Create(Item('ATL-1', 'Zur Prüfung'), Item('ATL-2', 'In Bearbeitung')), T0);
  Assert.AreEqual(0, Integer(Length(mFound)), 'ATL-2 nie erledigt gesehen');
  Assert.IsTrue(mEnded[0].Done);
  Assert.IsFalse(mEnded[1].Done);
  mFound := TAtlasTrackerReopened.FromList(YouTrack, mEnded,
    TArray<TAtlasTrackerIssue>.Create(Item('ATL-1', 'In Bearbeitung')), T0 + 1);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('ATL-1', mFound[0].Key);
  Assert.AreEqual('issue/ATL-1', mFound[0].Branch);
  Assert.AreEqual(T0, mFound[0].EndedAt);
  Assert.AreEqual(T0 + 1, mFound[0].At);
  Assert.AreEqual(1, Integer(Length(mEnded)), 'Eintrag ging in die Marke über');
  Assert.AreEqual('ATL-2', mEnded[0].Key);
  // Dieselbe Rückkehr nicht zweimal.
  mFound := TAtlasTrackerReopened.FromList(YouTrack, mEnded,
    TArray<TAtlasTrackerIssue>.Create(Item('ATL-1', 'In Bearbeitung')), T0 + 2);
  Assert.AreEqual(0, Integer(Length(mFound)));
  mEnded := nil;
end;

procedure TAtlasTrackerReopenedTests.EndedMovesIntoMark;
var
  mEnded: TArray<TAtlasTrackerEnded>;
  mReopen: TAtlasTrackerReopen;
begin
  mEnded := TArray<TAtlasTrackerEnded>.Create(Ended('ATL-1', 'issue/ATL-1', T0, True));
  mEnded[0].State := 'Erledigt';
  mReopen := Default(TAtlasTrackerReopen);
  mReopen.Key := 'atl-1';
  // Kommentar vor dem Beenden ist nicht der Grund.
  mReopen.Comment := 'alt';
  mReopen.CommentAt := T0 - 1;
  TAtlasTrackerReopened.TakeEnded(mEnded, mReopen);
  Assert.AreEqual('issue/ATL-1', mReopen.Branch);
  Assert.AreEqual('Erledigt', mReopen.Previous, 'ohne Vorzustand der beim Beenden geschriebene');
  Assert.AreEqual('', mReopen.Comment);
  Assert.AreEqual(Double(0), Double(mReopen.CommentAt));
  Assert.AreEqual(0, Integer(Length(mEnded)));
end;

procedure TAtlasTrackerReopenedTests.MarkKeepsBranchAndReason;
var
  mMarks: TArray<TAtlasTrackerReopen>;
  mReopen, mFound: TAtlasTrackerReopen;
begin
  mReopen := Default(TAtlasTrackerReopen);
  mReopen.Key := 'ATL-1';
  mReopen.Branch := 'issue/ATL-1';
  mReopen.EndedAt := T0;
  mReopen.Comment := 'Grund';
  mReopen.CommentAt := T0 + 1;
  TAtlasTrackerReopened.Mark(mMarks, mReopen);
  mReopen := Default(TAtlasTrackerReopen);
  mReopen.Key := 'ATL-1';
  mReopen.State := 'Offen';
  TAtlasTrackerReopened.Mark(mMarks, mReopen);
  Assert.AreEqual(1, Integer(Length(mMarks)));
  Assert.IsTrue(TAtlasTrackerReopened.Find(mMarks, 'atl-1', mFound));
  Assert.AreEqual('issue/ATL-1', mFound.Branch);
  Assert.AreEqual('Grund', mFound.Comment);
  Assert.AreEqual('Offen', mFound.State);
  Assert.IsTrue(TAtlasTrackerReopened.Dismiss(mMarks, 'ATL-1'));
  Assert.IsFalse(TAtlasTrackerReopened.Dismiss(mMarks, 'ATL-1'));
  Assert.IsFalse(TAtlasTrackerReopened.Find(mMarks, 'ATL-1', mFound));
end;

procedure TAtlasTrackerReopenedTests.ListsAreLimited;
var
  mEnded: TArray<TAtlasTrackerEnded>;
  mMarks: TArray<TAtlasTrackerReopen>;
  mReopen: TAtlasTrackerReopen;
  mIndex: Integer;
begin
  for mIndex := 1 to TAtlasTrackerReopened.cMaxEntries + 3 do
  begin
    TAtlasTrackerReopened.AddEnded(mEnded, Ended('ATL-' + IntToStr(mIndex), '', T0, False));
    mReopen := Default(TAtlasTrackerReopen);
    mReopen.Key := 'ATL-' + IntToStr(mIndex);
    TAtlasTrackerReopened.Mark(mMarks, mReopen);
  end;
  Assert.AreEqual(TAtlasTrackerReopened.cMaxEntries, Integer(Length(mEnded)));
  Assert.AreEqual(TAtlasTrackerReopened.cMaxEntries, Integer(Length(mMarks)));
  Assert.AreEqual('ATL-4', mEnded[0].Key, 'die ältesten fallen heraus');
  Assert.AreEqual('ATL-4', mMarks[0].Key);
  // Erneut beendet: ersetzt und steht hinten.
  TAtlasTrackerReopened.AddEnded(mEnded, Ended('ATL-4', 'b', T0, True));
  Assert.AreEqual(TAtlasTrackerReopened.cMaxEntries, Integer(Length(mEnded)));
  Assert.AreEqual('ATL-4', mEnded[High(mEnded)].Key);
  Assert.AreEqual(-1, TAtlasTrackerReopened.IndexOfEnded(mEnded, 'ATL-1'));
  TAtlasTrackerReopened.AddEnded(mEnded, Ended(' ', '', T0, False));
  Assert.AreEqual(TAtlasTrackerReopened.cMaxEntries, Integer(Length(mEnded)), 'ohne Kennung nichts');
  mEnded := nil;
  mMarks := nil;
end;

procedure TAtlasTrackerReopenedTests.LatestForeignComment;
var
  mComments: TArray<TAtlasTrackerComment>;
  mComment: TAtlasTrackerComment;
  mReopen: TAtlasTrackerReopen;
begin
  mComments := TArray<TAtlasTrackerComment>.Create(Comment('Jana', T0 - 1, 'vor dem Beenden'),
    Comment('Jana', T0 + 1, 'Lesezeichen fehlen'), Comment('ich', T0 + 2, 'mein eigener'));
  Assert.IsTrue(TAtlasTrackerReopened.LatestComment(mComments, T0, 'ICH', mComment));
  Assert.AreEqual('Lesezeichen fehlen', mComment.Text);
  Assert.IsTrue(TAtlasTrackerReopened.LatestComment(mComments, T0, '', mComment));
  Assert.AreEqual('mein eigener', mComment.Text, 'ohne bekannten Namen zählt jeder');
  Assert.IsFalse(TAtlasTrackerReopened.LatestComment(mComments, T0 + 3, '', mComment));
  mReopen := Default(TAtlasTrackerReopen);
  mReopen.CommentAt := T0 + 5;
  mReopen.Comment := 'neuer';
  TAtlasTrackerReopened.TakeComment(mReopen, Comment('Jana', T0 + 1, 'älter'));
  Assert.AreEqual('neuer', mReopen.Comment, 'ein älterer ersetzt nicht');
  TAtlasTrackerReopened.TakeComment(mReopen, Comment('Jana', T0 + 6, StringOfChar('x', 300)));
  Assert.AreEqual(TAtlasTrackerReopened.cMaxComment, Length(mReopen.Comment));
  Assert.AreEqual('Jana', mReopen.CommentBy);
  mComments := nil;
end;

procedure TAtlasTrackerReopenedTests.ConcernsEndedOrListed;
var
  mEnded: TArray<TAtlasTrackerEnded>;
begin
  mEnded := TArray<TAtlasTrackerEnded>.Create(Ended('ATL-1', '', T0, True));
  Assert.IsTrue(TAtlasTrackerReopened.Concerns(mEnded, nil, 'atl-1'));
  Assert.IsTrue(TAtlasTrackerReopened.Concerns(nil, TArray<TAtlasTrackerIssue>.Create(Item('ATL-2', 'Offen')),
    'ATL-2'));
  Assert.IsFalse(TAtlasTrackerReopened.Concerns(mEnded, nil, 'ATL-3'));
  mEnded := nil;
end;

procedure TAtlasTrackerReopenedTests.JsonRoundTrip;
var
  mSection: TJSONObject;
  mEnded, mReadEnded: TArray<TAtlasTrackerEnded>;
  mMarks, mReadMarks: TArray<TAtlasTrackerReopen>;
  mReopen: TAtlasTrackerReopen;
begin
  mEnded := TArray<TAtlasTrackerEnded>.Create(Ended('ATL-1', 'issue/ATL-1', T0, True));
  mEnded[0].State := 'Erledigt';
  mReopen := Default(TAtlasTrackerReopen);
  mReopen.Key := 'ATL-2';
  mReopen.Title := 'Titel';
  mReopen.State := 'Offen';
  mReopen.Previous := 'Zur Prüfung';
  mReopen.At := T0 + 1;
  mReopen.EndedAt := T0;
  mReopen.Branch := 'issue/ATL-2';
  mReopen.CommentBy := 'Jana';
  mReopen.CommentAt := T0 + 0.5;
  mReopen.Comment := 'Grund';
  mMarks := TArray<TAtlasTrackerReopen>.Create(mReopen);
  mSection := TJSONObject.Create;
  try
    TAtlasTrackerReopened.WriteJson(mSection, mEnded, mMarks);
    TAtlasTrackerReopened.ReadJson(mSection, mReadEnded, mReadMarks);
  finally
    mSection.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mReadEnded)));
  Assert.AreEqual('issue/ATL-1', mReadEnded[0].Branch);
  Assert.AreEqual('Erledigt', mReadEnded[0].State);
  Assert.IsTrue(mReadEnded[0].Done);
  Assert.IsTrue(SameDateTime(T0, mReadEnded[0].At));
  Assert.AreEqual(1, Integer(Length(mReadMarks)));
  Assert.AreEqual('Zur Prüfung', mReadMarks[0].Previous);
  Assert.AreEqual('issue/ATL-2', mReadMarks[0].Branch);
  Assert.AreEqual('Grund', mReadMarks[0].Comment);
  Assert.AreEqual('Jana', mReadMarks[0].CommentBy);
  Assert.IsTrue(SameDateTime(T0 + 0.5, mReadMarks[0].CommentAt));
  Assert.IsTrue(SameDateTime(T0, mReadMarks[0].EndedAt));
  // Leere Listen entfallen.
  mSection := TJSONObject.Create;
  try
    TAtlasTrackerReopened.WriteJson(mSection, nil, nil);
    Assert.AreEqual(0, mSection.Count);
  finally
    mSection.Free;
  end;
  mEnded := nil;
  mReadEnded := nil;
  mMarks := nil;
  mReadMarks := nil;
end;

procedure TAtlasTrackerReopenedTests.StartDismissesMark;
var
  mState, mRead: TAtlasIssuesState;
  mReopen: TAtlasTrackerReopen;
  mView: TAtlasIssuesView;
  mTarget: TAtlasTrackerTarget;
begin
  mState := TAtlasIssuesState.Empty;
  TAtlasTrackerReopened.AddEnded(mState.Ended, Ended('ATL-1', 'issue/ATL-1', T0, True));
  mReopen := Default(TAtlasTrackerReopen);
  mReopen.Key := 'ATL-1';
  TAtlasTrackerReopened.Mark(mState.Reopened, mReopen);
  // Gespeichert im Abschnitt "issues" und wieder gelesen.
  Assert.IsTrue(TAtlasMyIssues.FromJson(TAtlasMyIssues.ToJson(mState), mRead));
  Assert.AreEqual(1, Integer(Length(mRead.Reopened)));
  Assert.AreEqual(1, Integer(Length(mRead.Ended)));
  mTarget := TAtlasMyIssues.TargetFor('youtrack', 'https://yt.example', 'ATL', '', '');
  mView := TAtlasMyIssues.View(mRead, mTarget, '');
  Assert.AreEqual(0, Integer(Length(mView.Reopened)), 'die Marken setzt die IDE-Schicht');
  TAtlasMyIssues.Started(mRead, Item('ATL-1', 'Offen'), TAtlasIssueStart.Branch, 'issue/ATL-1', T0);
  Assert.AreEqual(0, Integer(Length(mRead.Reopened)), '„Beginnen“ bzw. „Weiterarbeiten“ nimmt die Marke');
  Assert.AreEqual(0, Integer(Length(mRead.Ended)));
  mState := TAtlasIssuesState.Empty;
  mRead := TAtlasIssuesState.Empty;
end;

procedure TAtlasTrackerReopenedTests.ResumeUsesRememberedBranch;
var
  mPlan: TAtlasIssueStartPlan;
  mOptions: TAtlasIssuesOptions;
begin
  mOptions := TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, 'feature/{kennung}', '', '');
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, mOptions, Item('ATL-1', 'Offen'));
  Assert.AreEqual('feature/ATL-1', mPlan.Branch);
  TAtlasMyIssues.ResumeOn(mPlan, ' issue/ATL-1 ');
  Assert.AreEqual('issue/ATL-1', mPlan.Branch);
  TAtlasMyIssues.ResumeOn(mPlan, '');
  Assert.AreEqual('issue/ATL-1', mPlan.Branch, 'ohne gemerkten Branch unverändert');
  // Nur merken: kein Branch.
  mOptions := TAtlasIssuesOptions.Create(TAtlasIssueStart.Remember, '', '', '');
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, mOptions, Item('ATL-1', 'Offen'));
  TAtlasMyIssues.ResumeOn(mPlan, 'issue/ATL-1');
  Assert.AreEqual('', mPlan.Branch);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerReopenedTests);

end.
