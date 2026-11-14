unit Atlas.Core.Tracker.Review.Tests;

// Tests von „Prüfen“ (#2126) ohne VCL: angeboten nur in Prüfzuständen; Branch
// des Issues zuerst nach Muster, dann mit der Kennung, ohne doppelte Namen;
// alle Branches geordnet zur Auswahl; Schrittfolge (ohne Build ausgelassen,
// gescheiterter Build lässt die Tests aus, fehlgeschlagene Tests scheitern);
// Rückweg nur nach gelungenem Wechsel; Build-Ergebnis aus dem Bericht;
// Vorlage mit {build} und {tests}, Vorgabe folgt der Sprache.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerReviewTests = class
  public
    [Test]
    procedure OfferedOnlyInReviewStates;
    [Test]
    procedure CandidatesPatternFirstThenKey;
    [Test]
    procedure CandidatesWithoutPattern;
    [Test]
    procedure AllBranchesSortedAndUnique;
    [Test]
    procedure StepsWithoutBuildAreSkipped;
    [Test]
    procedure FailedBuildSkipsTests;
    [Test]
    procedure TestsFailOrPass;
    [Test]
    procedure ReturnOnlyAfterSwitch;
    [Test]
    procedure BuildCountsMessages;
    [Test]
    procedure CommentFillsPlaceholders;
    [Test]
    procedure DefaultCommentFollowsLanguage;
    [Test]
    procedure ReturnNameByKind;
    [Test]
    procedure RowReviewsInReviewState;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Build.Messages,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Build.Requests,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Development,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.Review;

function Ref(const AName, ALocalName: string; ARemote: Boolean): TAtlasVcsRef;
begin
  Result := Default(TAtlasVcsRef);
  Result.Name := AName;
  Result.LocalName := ALocalName;
  Result.Remote := ARemote;
end;

function Refs: TArray<TAtlasVcsRef>;
begin
  Result := TArray<TAtlasVcsRef>.Create(Ref('main', 'main', False), Ref('feature/ATL-2052-fix',
    'feature/ATL-2052-fix', False), Ref('origin/issue/ATL-2052', 'issue/ATL-2052', True),
    Ref('origin/feature/ATL-2052-fix', 'feature/ATL-2052-fix', True), Ref('issue/ATL-20520', 'issue/ATL-20520',
    False), Ref('issue/ATL-2060', 'issue/ATL-2060', False));
end;

function Request: TAtlasIssueDevelopmentRequest;
begin
  Result := TAtlasIssueDevelopmentRequest.Create(TAtlasTrackerTarget.cYouTrack, 'ATL', 'ATL-2052', nil, nil);
end;

function Message(ASeverity: TAtlasCompilerSeverity): TAtlasCompilerMessage;
begin
  Result := Default(TAtlasCompilerMessage);
  Result.Severity := ASeverity;
  Result.Text := 'x';
end;

procedure TAtlasTrackerReviewTests.OfferedOnlyInReviewStates;
var
  mStates: TArray<string>;
begin
  mStates := TArray<string>.Create('Zur Prüfung', ' In Review ');
  Assert.IsTrue(TAtlasTrackerReview.Offered('zur prüfung', mStates));
  Assert.IsTrue(TAtlasTrackerReview.Offered('In Review', mStates), 'Rand zählt nicht');
  Assert.IsFalse(TAtlasTrackerReview.Offered('In Bearbeitung', mStates));
  Assert.IsFalse(TAtlasTrackerReview.Offered('', mStates));
  Assert.IsFalse(TAtlasTrackerReview.Offered('Zur Prüfung', nil), 'leer = nur Kontextmenü');
end;

procedure TAtlasTrackerReviewTests.CandidatesPatternFirstThenKey;
var
  mFound: TArray<string>;
begin
  mFound := TAtlasTrackerReview.Candidates(Request, 'issue/ATL-2052', Refs);
  // Muster zuerst (nur entfernt vorhanden), dann der mit der Kennung; lokal und entfernt nur einmal.
  Assert.AreEqual(2, Integer(Length(mFound)), string.Join('|', mFound));
  Assert.AreEqual('issue/ATL-2052', mFound[0]);
  Assert.AreEqual('feature/ATL-2052-fix', mFound[1]);
end;

procedure TAtlasTrackerReviewTests.CandidatesWithoutPattern;
var
  mFound: TArray<string>;
begin
  // Das Muster gibt es nicht: nur die Branches mit der Kennung; ATL-20520 ist eine andere.
  mFound := TAtlasTrackerReview.Candidates(Request, 'review/ATL-2052', Refs);
  Assert.AreEqual(2, Integer(Length(mFound)), string.Join('|', mFound));
  Assert.IsFalse(string.Join('|', mFound).Contains('ATL-20520'));
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerReview.Candidates(Request, '', nil))));
end;

procedure TAtlasTrackerReviewTests.AllBranchesSortedAndUnique;
var
  mAll: TArray<string>;
begin
  mAll := TAtlasTrackerReview.AllBranches(Refs);
  Assert.AreEqual('feature/ATL-2052-fix|issue/ATL-2052|issue/ATL-20520|issue/ATL-2060|main',
    string.Join('|', mAll));
end;

procedure TAtlasTrackerReviewTests.StepsWithoutBuildAreSkipped;
var
  mState: TAtlasReviewState;
begin
  mState := TAtlasReviewState.Create('ATL-2052', False);
  Assert.AreEqual('ATL-2052', mState.Key);
  Assert.AreEqual<TAtlasReviewMark>(TAtlasReviewMark.Skipped, mState.Marks[TAtlasReviewStep.Build]);
  Assert.AreEqual<TAtlasReviewMark>(TAtlasReviewMark.Skipped, mState.Marks[TAtlasReviewStep.Tests]);
  Assert.IsTrue(mState.Busy, 'Stand und Wechsel warten');
  mState.Marks[TAtlasReviewStep.Saved] := TAtlasReviewMark.Done;
  mState.Marks[TAtlasReviewStep.Switched] := TAtlasReviewMark.Done;
  Assert.IsFalse(mState.Busy);
  mState := TAtlasReviewState.Create('ATL-2052', True);
  Assert.AreEqual<TAtlasReviewMark>(TAtlasReviewMark.Waiting, mState.Marks[TAtlasReviewStep.Build]);
end;

procedure TAtlasTrackerReviewTests.FailedBuildSkipsTests;
var
  mState: TAtlasReviewState;
  mBuild: TAtlasReviewBuild;
begin
  mState := TAtlasReviewState.Create('ATL-2052', True);
  mBuild := Default(TAtlasReviewBuild);
  mBuild.Errors := 2;
  mState.Built(mBuild);
  Assert.AreEqual<TAtlasReviewMark>(TAtlasReviewMark.Failed, mState.Marks[TAtlasReviewStep.Build]);
  Assert.AreEqual<TAtlasReviewMark>(TAtlasReviewMark.Skipped, mState.Marks[TAtlasReviewStep.Tests]);
  Assert.AreEqual(2, mState.Build.Errors);
  mState := TAtlasReviewState.Create('ATL-2052', True);
  mBuild.Errors := 0;
  mBuild.Succeeded := True;
  mState.Built(mBuild);
  Assert.AreEqual<TAtlasReviewMark>(TAtlasReviewMark.Done, mState.Marks[TAtlasReviewStep.Build]);
  Assert.AreEqual<TAtlasReviewMark>(TAtlasReviewMark.Waiting, mState.Marks[TAtlasReviewStep.Tests]);
end;

procedure TAtlasTrackerReviewTests.TestsFailOrPass;
var
  mState: TAtlasReviewState;
begin
  mState := TAtlasReviewState.Create('ATL-2052', True);
  mState.Tested(14, 0);
  Assert.AreEqual<TAtlasReviewMark>(TAtlasReviewMark.Done, mState.Marks[TAtlasReviewStep.Tests]);
  Assert.AreEqual(14, mState.TestsPassed);
  mState.Tested(12, 2);
  Assert.AreEqual<TAtlasReviewMark>(TAtlasReviewMark.Failed, mState.Marks[TAtlasReviewStep.Tests]);
  Assert.AreEqual(2, mState.TestsFailed);
end;

procedure TAtlasTrackerReviewTests.ReturnOnlyAfterSwitch;
var
  mState: TAtlasReviewState;
begin
  mState := TAtlasReviewState.Create('ATL-2052', False);
  mState.OwnBranch := 'issue/ATL-2060';
  mState.Branch := 'issue/ATL-2052';
  Assert.IsFalse(mState.CanReturn, 'noch nicht gewechselt');
  mState.Marks[TAtlasReviewStep.Switched] := TAtlasReviewMark.Done;
  Assert.IsTrue(mState.CanReturn);
  mState.Branch := 'ISSUE/atl-2060';
  Assert.IsFalse(mState.CanReturn, 'schon auf dem eigenen Branch');
  mState.Branch := 'issue/ATL-2052';
  mState.OwnBranch := '';
  Assert.IsFalse(mState.CanReturn, 'eigener Branch unbekannt');
end;

procedure TAtlasTrackerReviewTests.BuildCountsMessages;
var
  mReport: TAtlasBuildReport;
  mBuild: TAtlasReviewBuild;
begin
  mReport := Default(TAtlasBuildReport);
  mReport.Project.Platform := 'Win64';
  mReport.Project.Configuration := 'Debug';
  mReport.Succeeded := True;
  mReport.Messages := TArray<TAtlasCompilerMessage>.Create(Message(TAtlasCompilerSeverity.Warning),
    Message(TAtlasCompilerSeverity.Hint), Message(TAtlasCompilerSeverity.Hint), Message(TAtlasCompilerSeverity.Info));
  mBuild := TAtlasTrackerReview.BuildOf(mReport);
  Assert.AreEqual('Win64', mBuild.Platform);
  Assert.AreEqual('Debug', mBuild.Configuration);
  Assert.IsTrue(mBuild.Succeeded);
  Assert.AreEqual(0, mBuild.Errors);
  Assert.AreEqual(1, mBuild.Warnings);
  Assert.AreEqual(2, mBuild.Hints);
  // Ein fataler Fehler zählt als Fehler, auch wenn der Bericht gelungen meldet.
  mReport.Messages := mReport.Messages + [Message(TAtlasCompilerSeverity.Fatal)];
  mBuild := TAtlasTrackerReview.BuildOf(mReport);
  Assert.AreEqual(1, mBuild.Errors);
  Assert.IsFalse(mBuild.Succeeded);
  mReport.Messages := nil;
  mReport.Succeeded := False;
  Assert.IsFalse(TAtlasTrackerReview.BuildOf(mReport).Succeeded);
end;

procedure TAtlasTrackerReviewTests.CommentFillsPlaceholders;
begin
  Assert.AreEqual('Geprüft: Build Win64 Debug 0/0/0, 14 Tests bestanden.',
    TAtlasTrackerReview.Comment(TAtlasTrackerReview.cDefaultComment, 'ATL-2052', 'issue/ATL-2052',
    'Build Win64 Debug 0/0/0', '14 Tests bestanden'));
  Assert.AreEqual('ATL-2052 auf issue/ATL-2052:'#10'ok',
    TAtlasTrackerReview.Comment('{kennung} auf {branch}:\n{BUILD}{tests}', 'ATL-2052', 'issue/ATL-2052', 'ok', ''));
end;

procedure TAtlasTrackerReviewTests.DefaultCommentFollowsLanguage;
begin
  Assert.AreEqual(TAtlasPluginSettings.cDefaultIssuesReviewComment, TAtlasTrackerReview.cDefaultComment);
  Assert.AreEqual(TAtlasTrackerReview.cDefaultCommentEn,
    TAtlasTrackerReview.CommentFor(TAtlasTrackerReview.cDefaultComment, True));
  Assert.AreEqual(TAtlasTrackerReview.cDefaultComment,
    TAtlasTrackerReview.CommentFor(TAtlasTrackerReview.cDefaultCommentEn, False));
  Assert.AreEqual('Eigener Text', TAtlasTrackerReview.CommentFor('Eigener Text', True));
end;

procedure TAtlasTrackerReviewTests.ReturnNameByKind;
var
  mHead: TAtlasVcsHead;
begin
  mHead := TAtlasVcsHead.Empty;
  mHead.Branch := 'issue/ATL-2060';
  Assert.AreEqual('issue/ATL-2060', TAtlasTrackerReview.ReturnName(TAtlasVcsKind.Git, mHead));
  mHead.Detached := True;
  Assert.AreEqual('', TAtlasTrackerReview.ReturnName(TAtlasVcsKind.Git, mHead), 'losgelöst');
  mHead := TAtlasVcsHead.Empty;
  mHead.Branch := 'branches/ATL-2060';
  Assert.AreEqual('ATL-2060', TAtlasTrackerReview.ReturnName(TAtlasVcsKind.Svn, mHead));
  mHead.Branch := 'trunk';
  Assert.AreEqual('', TAtlasTrackerReview.ReturnName(TAtlasVcsKind.Svn, mHead), 'trunk ohne Rückweg');
  Assert.AreEqual('', TAtlasTrackerReview.ReturnName(TAtlasVcsKind.None, mHead));
end;

procedure TAtlasTrackerReviewTests.RowReviewsInReviewState;
var
  mView: TAtlasIssuesView;
  mIssue: TAtlasTrackerIssue;
begin
  mView := Default(TAtlasIssuesView);
  mView.VcsKind := TAtlasVcsKind.Git;
  mView.ReviewStates := TArray<string>.Create('In Review');
  mIssue := TAtlasTrackerIssue.Empty;
  mIssue.Key := 'ATL-2052';
  mIssue.State := 'in review';
  Assert.IsTrue(TAtlasTrackerReview.Reviews(mView, mIssue));
  mView.Active.Key := 'atl-2052';
  Assert.IsFalse(TAtlasTrackerReview.Reviews(mView, mIssue), 'nicht am aktuellen Issue');
  mView.Active.Key := '';
  mView.VcsKind := TAtlasVcsKind.None;
  Assert.IsFalse(TAtlasTrackerReview.Reviews(mView, mIssue), 'ohne Git oder SVN');
  mView.VcsKind := TAtlasVcsKind.Svn;
  mIssue.State := 'Offen';
  Assert.IsFalse(TAtlasTrackerReview.Reviews(mView, mIssue));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerReviewTests);

end.
