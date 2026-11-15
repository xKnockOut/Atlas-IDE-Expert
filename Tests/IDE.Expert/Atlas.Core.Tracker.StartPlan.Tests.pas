unit Atlas.Core.Tracker.StartPlan.Tests;

// Tests der Entscheidungen von „Beginnen“ (#765, #1967) ohne IDE und Versionsverwaltung: Stand eines Laufs
// (Branch, Weiterarbeiten, verknüpfter Branch, lokale Änderungen, Dialog „Branch anlegen“), Sprint beim Beginnen,
// Git-Hook, Meldung bei Fehlschlag, Hinweis, Projekt, Öffnen und Arbeitsstand danach.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasIssueStartPlanTests = class
  public
    [Test]
    procedure BranchingNeedsValidBranchPlan;
    [Test]
    procedure ResumeAsksWhenBranchGone;
    [Test]
    procedure LocalChangesAskedOnce;
    [Test]
    procedure DialogWithConfirmOrSvnWithoutLayout;
    [Test]
    procedure LinkingOnlyForNewBranch;
    [Test]
    procedure SprintFollowsSetting;
    [Test]
    procedure SprintNeedsCachedRunningSprint;
    [Test]
    procedure HookAskedOncePerProject;
    [Test]
    procedure FailureNamesReason;
    [Test]
    procedure NoticeAndModeAfterStart;
    [Test]
    procedure OpenAndWorkAfterStart;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Tracker.CommitHook,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.MyIssues,
  Atlas.Core.Tracker.StartPlan,
  Atlas.Core.VersionControl.BranchPlan,
  Atlas.Core.VersionControl.Contract;

/// <summary>Gültiger Plan für einen neuen Branch, Stand gelesen, ohne Änderungen.</summary>
function BranchState: TAtlasIssueStartState;
begin
  Result := Default(TAtlasIssueStartState);
  Result.Plan.Mode := TAtlasIssueStart.Branch;
  Result.Plan.Valid := True;
  Result.Plan.Branch := 'feature/ATL-7';
  Result.Plan.Bases := TArray<string>.Create('main', 'master');
  Result.Facts := TAtlasVcsBranchFacts.Empty;
  Result.Facts.Outcome := TAtlasVcsOutcome.Ok;
  Result.Facts.Kind := TAtlasVcsKind.Git;
end;

function ResultOf(AOutcome: TAtlasIssueStartOutcome): TAtlasIssueStartResult;
begin
  Result := Default(TAtlasIssueStartResult);
  Result.Outcome := AOutcome;
end;

{ TAtlasIssueStartPlanTests }

procedure TAtlasIssueStartPlanTests.BranchingNeedsValidBranchPlan;
var
  mState: TAtlasIssueStartState;
begin
  mState := BranchState;
  Assert.IsTrue(mState.Branching);
  Assert.IsTrue(mState.ChoosesBranch);
  Assert.AreEqual('main', mState.LinkBase);
  mState.Facts.Outcome := TAtlasVcsOutcome.Failed;
  Assert.IsFalse(mState.ChoosesBranch, 'Branch gibt es schon bzw. Stand nicht gelesen');
  mState.Plan.Valid := False;
  Assert.IsFalse(mState.Branching, 'ungültiger Name');
  mState := BranchState;
  mState.Plan.Mode := TAtlasIssueStart.Remember;
  Assert.IsFalse(mState.Branching, 'nur merken');
  mState.Plan.Bases := nil;
  Assert.AreEqual('', mState.LinkBase);
end;

procedure TAtlasIssueStartPlanTests.ResumeAsksWhenBranchGone;
var
  mState: TAtlasIssueStartState;
begin
  mState := BranchState;
  Assert.IsFalse(mState.Resuming);
  Assert.IsFalse(mState.AsksRecreate);
  mState.ResumeBranch := 'feature/ATL-7';
  Assert.IsTrue(mState.Resuming);
  Assert.IsTrue(mState.AsksRecreate, 'gemerkter Branch fehlt');
  mState.Facts.Outcome := TAtlasVcsOutcome.Failed;
  Assert.IsFalse(mState.AsksRecreate);
end;

procedure TAtlasIssueStartPlanTests.LocalChangesAskedOnce;
var
  mState: TAtlasIssueStartState;
  mOptions: TAtlasVcsGitBranchOptions;
begin
  mState := BranchState;
  Assert.IsFalse(mState.ChangesOpen(False), 'ohne Änderungen');
  mState.Changes := 3;
  Assert.IsTrue(mState.ChangesOpen(False));
  Assert.IsFalse(mState.ChangesOpen(True), 'schon gefragt');
  mState.Request := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, mState.Plan.Branch, Default(TAtlasVcsBranchBase),
    '');
  mState.OfferLocal := True;
  Assert.IsTrue(mState.InDialog);
  Assert.IsFalse(mState.ChangesOpen(False), 'im Dialog entschieden');
  mState.OfferLocal := False;
  mState.UseRequest := True;
  mState.Request.Stash := True;
  Assert.IsTrue(mState.Settled);
  Assert.IsFalse(mState.ChangesOpen(False), 'beiseitegelegt');
  mOptions := TAtlasVcsGitBranchOptions.Classic;
  mOptions.Uncommitted := TAtlasVcsGitUncommitted.Ask;
  mState.Request.Stash := False;
  Assert.IsTrue(mState.AsksUncommitted(mOptions));
  mState.Request.WorktreeFolder := '..\atlas-ATL-7';
  Assert.IsFalse(mState.AsksUncommitted(mOptions), 'worktree nimmt nichts mit');
  mOptions.Uncommitted := TAtlasVcsGitUncommitted.Carry;
  mState.Request.WorktreeFolder := '';
  Assert.IsFalse(mState.AsksUncommitted(mOptions));
end;

procedure TAtlasIssueStartPlanTests.DialogWithConfirmOrSvnWithoutLayout;
var
  mState: TAtlasIssueStartState;
begin
  mState := BranchState;
  Assert.IsTrue(mState.ShowsDialog(True));
  Assert.IsFalse(mState.ShowsDialog(False), 'Git mit Vorgaben');
  mState.Facts.Kind := TAtlasVcsKind.Svn;
  Assert.IsTrue(mState.ShowsDialog(False), 'SVN ohne Ort');
  mState.UseRequest := True;
  Assert.IsFalse(mState.ShowsDialog(False), 'SVN mit Ort aus den Vorgaben');
end;

procedure TAtlasIssueStartPlanTests.LinkingOnlyForNewBranch;
var
  mState: TAtlasIssueStartState;
begin
  mState := BranchState;
  Assert.IsFalse(mState.Linking, 'ausgeschaltet');
  mState.LinkActive := True;
  Assert.IsTrue(mState.Linking);
  mState.ResumeBranch := 'feature/ATL-7';
  Assert.IsFalse(mState.Linking, 'Weiterarbeiten');
  mState.ResumeBranch := '';
  mState.UseRequest := True;
  mState.Request.WorktreeFolder := '..\atlas-ATL-7';
  Assert.IsFalse(mState.Linking, 'worktree');
end;

procedure TAtlasIssueStartPlanTests.SprintFollowsSetting;
begin
  Assert.AreEqual(Integer(Ord(TAtlasSprintOnStart.Ask)), Integer(Ord(TAtlasIssueStartFlow.SprintOnStart(
    TAtlasPluginSettings.cIssuesSprintAsk, True, True))));
  Assert.AreEqual(Integer(Ord(TAtlasSprintOnStart.Take)), Integer(Ord(TAtlasIssueStartFlow.SprintOnStart(
    TAtlasPluginSettings.cIssuesSprintAlways, True, True))));
  Assert.AreEqual(Integer(Ord(TAtlasSprintOnStart.Skip)), Integer(Ord(TAtlasIssueStartFlow.SprintOnStart(
    TAtlasPluginSettings.cIssuesSprintNever, True, True))));
  Assert.AreEqual(Integer(Ord(TAtlasSprintOnStart.Skip)), Integer(Ord(TAtlasIssueStartFlow.SprintOnStart(
    TAtlasPluginSettings.cIssuesSprintAlways, False, True))), 'ohne Nachführen');
  Assert.AreEqual(Integer(Ord(TAtlasSprintOnStart.Skip)), Integer(Ord(TAtlasIssueStartFlow.SprintOnStart(
    TAtlasPluginSettings.cIssuesSprintAsk, True, False))), 'kein laufender Sprint ohne das Issue');
  Assert.AreEqual(TAtlasPluginSettings.cIssuesSprintAlways, TAtlasIssueStartFlow.RememberedSprintMode(True));
  Assert.AreEqual(TAtlasPluginSettings.cIssuesSprintNever, TAtlasIssueStartFlow.RememberedSprintMode(False));
end;

procedure TAtlasIssueStartPlanTests.SprintNeedsCachedRunningSprint;
var
  mSprint: TAtlasTrackerSprintRef;
begin
  // Ohne angemeldeten Dateizugriff gibt es keinen gelesenen Stand: nichts aufnehmen.
  Assert.IsFalse(TAtlasIssueStartFlow.CachedSprint('C:\Atlas\issues', 'sprint', Default(TAtlasTrackerTarget),
    'ATL-7', 46000, mSprint));
  Assert.IsFalse(mSprint.IsSet);
end;

procedure TAtlasIssueStartPlanTests.HookAskedOncePerProject;
begin
  Assert.AreEqual(Integer(Ord(TAtlasHookStep.Skip)), Integer(Ord(TAtlasIssueStartFlow.HookStep('',
    '', TAtlasCommitHookState.Missing))), 'kein Hook-Ordner');
  Assert.AreEqual(Integer(Ord(TAtlasHookStep.Skip)), Integer(Ord(TAtlasIssueStartFlow.HookStep('C:\r\.git\hooks',
    TAtlasMyIssues.cHookNo, TAtlasCommitHookState.Missing))), 'schon entschieden');
  Assert.AreEqual(Integer(Ord(TAtlasHookStep.Own)), Integer(Ord(TAtlasIssueStartFlow.HookStep('C:\r\.git\hooks',
    '', TAtlasCommitHookState.Own))));
  Assert.AreEqual(Integer(Ord(TAtlasHookStep.Ask)), Integer(Ord(TAtlasIssueStartFlow.HookStep('C:\r\.git\hooks',
    '', TAtlasCommitHookState.Foreign))), 'fremder Hook: erst fragen, dann bleibt er');
end;

procedure TAtlasIssueStartPlanTests.FailureNamesReason;
var
  mResult: TAtlasIssueStartResult;
begin
  Assert.AreEqual(Integer(Ord(TAtlasStartFailure.None)), Integer(Ord(TAtlasIssueStartFlow.Failure(ResultOf(
    TAtlasIssueStartOutcome.Started)))));
  Assert.AreEqual(Integer(Ord(TAtlasStartFailure.InvalidName)), Integer(Ord(TAtlasIssueStartFlow.Failure(ResultOf(
    TAtlasIssueStartOutcome.InvalidName)))));
  mResult := ResultOf(TAtlasIssueStartOutcome.Failed);
  Assert.AreEqual(Integer(Ord(TAtlasStartFailure.Plain)), Integer(Ord(TAtlasIssueStartFlow.Failure(mResult))));
  SetLength(mResult.Steps, 1);
  Assert.AreEqual(Integer(Ord(TAtlasStartFailure.Steps)), Integer(Ord(TAtlasIssueStartFlow.Failure(mResult))));
  mResult.FolderTaken := True;
  Assert.AreEqual(Integer(Ord(TAtlasStartFailure.FolderTaken)), Integer(Ord(TAtlasIssueStartFlow.Failure(mResult))));
end;

procedure TAtlasIssueStartPlanTests.NoticeAndModeAfterStart;
var
  mResult: TAtlasIssueStartResult;
begin
  mResult := ResultOf(TAtlasIssueStartOutcome.Started);
  Assert.AreEqual(Integer(Ord(TAtlasStartNotice.Created)), Integer(Ord(TAtlasIssueStartFlow.Notice(mResult, ''))));
  Assert.AreEqual('C:\p\Kasse.dproj', TAtlasIssueStartFlow.ProjectAfter('C:\p\Kasse.dproj', mResult));
  mResult.Folder := 'C:\p-ATL-7';
  Assert.AreEqual(Integer(Ord(TAtlasStartNotice.Worktree)), Integer(Ord(TAtlasIssueStartFlow.Notice(mResult, ''))));
  Assert.AreEqual(Integer(Ord(TAtlasStartNotice.Switched)), Integer(Ord(TAtlasIssueStartFlow.Notice(ResultOf(
    TAtlasIssueStartOutcome.Switched), 'ATL-7: '))));
  mResult := ResultOf(TAtlasIssueStartOutcome.Remembered);
  Assert.AreEqual(Integer(Ord(TAtlasStartNotice.RememberedPrefix)), Integer(Ord(TAtlasIssueStartFlow.Notice(mResult,
    'ATL-7: '))));
  Assert.AreEqual(Integer(Ord(TAtlasStartNotice.Remembered)), Integer(Ord(TAtlasIssueStartFlow.Notice(mResult, ''))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueStart.Remember)), Integer(Ord(TAtlasIssueStartFlow.ModeAfter(mResult))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueStart.Branch)), Integer(Ord(TAtlasIssueStartFlow.ModeAfter(ResultOf(
    TAtlasIssueStartOutcome.Switched)))));
  Assert.AreEqual(Integer(Ord(TAtlasIssueStart.Branch)), Integer(Ord(TAtlasIssueStartFlow.ResumeMode('feature/ATL-7',
    TAtlasIssueStart.Remember))), 'gemerkter Branch gilt immer als Branch');
  Assert.AreEqual(Integer(Ord(TAtlasIssueStart.Remember)), Integer(Ord(TAtlasIssueStartFlow.ResumeMode('',
    TAtlasIssueStart.Remember))));
end;

procedure TAtlasIssueStartPlanTests.OpenAndWorkAfterStart;
begin
  Assert.AreEqual(Integer(Ord(TAtlasStartOpen.Project)), Integer(Ord(TAtlasIssueStartFlow.OpenAfter(True, True, ''))));
  Assert.AreEqual(Integer(Ord(TAtlasStartOpen.Worktree)), Integer(Ord(TAtlasIssueStartFlow.OpenAfter(True, True,
    'C:\p-ATL-7'))));
  Assert.AreEqual(Integer(Ord(TAtlasStartOpen.None)), Integer(Ord(TAtlasIssueStartFlow.OpenAfter(False, True, ''))),
    'Ordner als Tracker-Projekt');
  Assert.AreEqual(Integer(Ord(TAtlasStartOpen.None)), Integer(Ord(TAtlasIssueStartFlow.OpenAfter(True, False, ''))));
  Assert.AreEqual(Integer(Ord(TAtlasStartWork.Offer)), Integer(Ord(TAtlasIssueStartFlow.WorkAfter('', False))));
  Assert.AreEqual(Integer(Ord(TAtlasStartWork.Restore)), Integer(Ord(TAtlasIssueStartFlow.WorkAfter('', True))));
  Assert.AreEqual(Integer(Ord(TAtlasStartWork.None)), Integer(Ord(TAtlasIssueStartFlow.WorkAfter('C:\p-ATL-7',
    True))));
end;

end.
