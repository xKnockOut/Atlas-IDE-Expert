unit Atlas.Core.Tracker.EndPull.Tests;

// „Beenden“ mit Pull Request (#2136) gegen eine Fake-Versionsverwaltung und
// einen Fake-Tracker: Push mit Upstream und Anlegen, fremder Remote (Fork),
// ungesicherte Änderungen (unversionierte Dateien zählen nicht), gescheiterter
// Push, SVN, dazu der Schritt „Pull Request“ im Plan und der Platzhalter
// {closes} der Textvorlage.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasEndPullTests = class
  public
    [Test]
    procedure PushesWithUpstreamThenCreates;
    [Test]
    procedure ForeignOriginPushesNothing;
    [Test]
    procedure ModifiedFilesAreDirty;
    [Test]
    procedure UntrackedFilesAreNotDirty;
    [Test]
    procedure FailedPushCreatesNothing;
    [Test]
    procedure SvnIsNotConfigured;
    [Test]
    procedure EndStepWithoutPullIsSkipped;
    [Test]
    procedure FailedPullStopsEnd;
    [Test]
    procedure FillWritesClosesKeyword;
    [Test]
    procedure ConnectionOverridesPrBase;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.EndPull,
  Atlas.Core.Tracker.EndSteps,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.VersionControl.Contract;

const
  cBranch = 'feature/7-statusfeld';
  cOrigin = 'git@github.com:beispiel/atlas.git';

type
  /// <summary>Git mit festen Änderungen und festem Ergebnis des Pushs; merkt sich die Aufrufe.</summary>
  TFakePushVcs = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsLocalWork)
  public
    VcsKind: TAtlasVcsKind;
    Files: TArray<TAtlasVcsChange>;
    PushOutcome: TAtlasVcsOutcome;
    Calls: TArray<string>;
    constructor Create(AKind: TAtlasVcsKind);
    { IAtlasVersionControl }
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
    { IAtlasVcsLocalWork }
    function Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
    function Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
    function Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
    function Outgoing(const ABranch, AUpstream: string; AMax: Integer;
      out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
    function ChangesIn(const ARevision: string; out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function Push(const ABranch, ARemote, ARemoteRef: string; ASetUpstream: Boolean): TAtlasVcsOutcome;
  end;

  /// <summary>Tracker mit festem Ergebnis; merkt sich, ob angelegt werden sollte.</summary>
  TFakePulls = class(TInterfacedObject, IAtlasTrackerPullRequests)
  public
    Answer: TAtlasTrackerPullResult;
    Asked: Boolean;
    AskedSpec: TAtlasTrackerPullSpec;
    function SameRepository(const ATarget: TAtlasTrackerTarget; const AOriginUrl: string): Boolean;
    function CreatePull(const ACall: TAtlasTrackerCall; const AKey: string;
      const ASpec: TAtlasTrackerPullSpec): TAtlasTrackerPullResult;
  end;

constructor TFakePushVcs.Create(AKind: TAtlasVcsKind);
begin
  inherited Create;
  VcsKind := AKind;
  PushOutcome := TAtlasVcsOutcome.Ok;
end;

function TFakePushVcs.Kind: TAtlasVcsKind;
begin
  Result := VcsKind;
end;

function TFakePushVcs.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result := TAtlasVcsWorkingCopy.Empty;
  Result.Kind := VcsKind;
  Result.Root := 'C:\Repo';
end;

function TFakePushVcs.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  AHead := TAtlasVcsHead.Empty;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakePushVcs.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := Files;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakePushVcs.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakePushVcs.Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakePushVcs.ChangeMarker: string;
begin
  Result := '';
end;

function TFakePushVcs.Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
begin
  ABranches := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakePushVcs.Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
begin
  AStashes := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakePushVcs.Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
begin
  ANames := ['origin'];
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakePushVcs.Outgoing(const ABranch, AUpstream: string; AMax: Integer;
  out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
begin
  ACommits := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakePushVcs.ChangesIn(const ARevision: string; out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakePushVcs.Push(const ABranch, ARemote, ARemoteRef: string; ASetUpstream: Boolean): TAtlasVcsOutcome;
begin
  Calls := Calls + [Format('push %s %s %s %s', [ABranch, ARemote, ARemoteRef, BoolToStr(ASetUpstream, True)])];
  Result := PushOutcome;
end;

function TFakePulls.SameRepository(const ATarget: TAtlasTrackerTarget; const AOriginUrl: string): Boolean;
begin
  Result := AOriginUrl = cOrigin;
end;

function TFakePulls.CreatePull(const ACall: TAtlasTrackerCall; const AKey: string;
  const ASpec: TAtlasTrackerPullSpec): TAtlasTrackerPullResult;
begin
  Asked := True;
  AskedSpec := ASpec;
  Result := Answer;
end;

function Change(AKind: TAtlasVcsChangeKind): TAtlasVcsChange;
begin
  Result := Default(TAtlasVcsChange);
  Result.Path := 'C:\Repo\Neu.pas';
  Result.Kind := AKind;
end;

function Created: TAtlasTrackerPullResult;
begin
  Result := TAtlasTrackerPullResult.Make(TAtlasTrackerPullOutcome.Created);
  Result.Number := 42;
  Result.Url := 'https://github.com/beispiel/atlas/pull/42';
end;

function PullSpec: TAtlasTrackerPullSpec;
begin
  Result := TAtlasTrackerPullSpec.None;
  Result.Wanted := True;
  Result.Head := cBranch;
  Result.Title := 'Statusfeld';
end;

function Request(const AVcs: IAtlasVersionControl; const APulls: IAtlasTrackerPullRequests;
  const AOrigin: string): TAtlasEndPullRequest;
begin
  Result := Default(TAtlasEndPullRequest);
  Result.Vcs := AVcs;
  Result.Pulls := APulls;
  Result.Call := TAtlasTrackerCall.Create(TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', ''), nil, 1000);
  Result.Key := '#7';
  Result.Spec := PullSpec;
  Result.Origin := AOrigin;
end;

{ TAtlasEndPullTests }

procedure TAtlasEndPullTests.PushesWithUpstreamThenCreates;
var
  mVcs: TFakePushVcs;
  mKeepVcs: IAtlasVersionControl;
  mPulls: TFakePulls;
  mKeepPulls: IAtlasTrackerPullRequests;
  mPull: TAtlasTrackerPullResult;
begin
  mVcs := TFakePushVcs.Create(TAtlasVcsKind.Git);
  mKeepVcs := mVcs;
  mPulls := TFakePulls.Create;
  mKeepPulls := mPulls;
  mPulls.Answer := Created;
  mPull := TAtlasEndPull.Run(Request(mKeepVcs, mKeepPulls, cOrigin));
  Assert.AreEqual<TAtlasTrackerPullOutcome>(TAtlasTrackerPullOutcome.Created, mPull.Outcome);
  Assert.AreEqual(42, mPull.Number);
  Assert.AreEqual(1, Integer(Length(mVcs.Calls)));
  Assert.AreEqual('push ' + cBranch + ' origin refs/heads/' + cBranch + ' True', mVcs.Calls[0]);
  Assert.IsTrue(mPulls.Asked);
  Assert.AreEqual('Statusfeld', mPulls.AskedSpec.Title);
end;

procedure TAtlasEndPullTests.ForeignOriginPushesNothing;
var
  mVcs: TFakePushVcs;
  mKeepVcs: IAtlasVersionControl;
  mPulls: TFakePulls;
  mKeepPulls: IAtlasTrackerPullRequests;
  mPull: TAtlasTrackerPullResult;
begin
  mVcs := TFakePushVcs.Create(TAtlasVcsKind.Git);
  mKeepVcs := mVcs;
  mPulls := TFakePulls.Create;
  mKeepPulls := mPulls;
  mPull := TAtlasEndPull.Run(Request(mKeepVcs, mKeepPulls, 'git@github.com:fork/atlas.git'));
  Assert.AreEqual<TAtlasTrackerPullOutcome>(TAtlasTrackerPullOutcome.Foreign, mPull.Outcome);
  Assert.AreEqual(0, Integer(Length(mVcs.Calls)));
  Assert.IsFalse(mPulls.Asked);
end;

procedure TAtlasEndPullTests.ModifiedFilesAreDirty;
var
  mVcs: TFakePushVcs;
  mKeepVcs: IAtlasVersionControl;
  mPulls: TFakePulls;
  mKeepPulls: IAtlasTrackerPullRequests;
  mPull: TAtlasTrackerPullResult;
begin
  mVcs := TFakePushVcs.Create(TAtlasVcsKind.Git);
  mKeepVcs := mVcs;
  mVcs.Files := [Change(TAtlasVcsChangeKind.Untracked), Change(TAtlasVcsChangeKind.Modified)];
  mPulls := TFakePulls.Create;
  mKeepPulls := mPulls;
  mPull := TAtlasEndPull.Run(Request(mKeepVcs, mKeepPulls, cOrigin));
  Assert.AreEqual<TAtlasTrackerPullOutcome>(TAtlasTrackerPullOutcome.Dirty, mPull.Outcome);
  Assert.AreEqual(0, Integer(Length(mVcs.Calls)));
  Assert.IsFalse(mPulls.Asked);
end;

procedure TAtlasEndPullTests.UntrackedFilesAreNotDirty;
begin
  Assert.IsFalse(TAtlasEndPull.Dirty([Change(TAtlasVcsChangeKind.Untracked)]));
  Assert.IsFalse(TAtlasEndPull.Dirty(nil));
  Assert.IsTrue(TAtlasEndPull.Dirty([Change(TAtlasVcsChangeKind.Added)]));
end;

procedure TAtlasEndPullTests.FailedPushCreatesNothing;
var
  mVcs: TFakePushVcs;
  mKeepVcs: IAtlasVersionControl;
  mPulls: TFakePulls;
  mKeepPulls: IAtlasTrackerPullRequests;
  mPull: TAtlasTrackerPullResult;
begin
  mVcs := TFakePushVcs.Create(TAtlasVcsKind.Git);
  mKeepVcs := mVcs;
  mVcs.PushOutcome := TAtlasVcsOutcome.Failed;
  mPulls := TFakePulls.Create;
  mKeepPulls := mPulls;
  mPull := TAtlasEndPull.Run(Request(mKeepVcs, mKeepPulls, cOrigin));
  Assert.AreEqual<TAtlasTrackerPullOutcome>(TAtlasTrackerPullOutcome.PushFailed, mPull.Outcome);
  Assert.AreEqual(AtlasVcsOutcomeName(TAtlasVcsOutcome.Failed), mPull.Message);
  Assert.IsFalse(mPulls.Asked);
end;

procedure TAtlasEndPullTests.SvnIsNotConfigured;
var
  mVcs: TFakePushVcs;
  mKeepVcs: IAtlasVersionControl;
  mPulls: TFakePulls;
  mKeepPulls: IAtlasTrackerPullRequests;
  mPull: TAtlasTrackerPullResult;
begin
  mVcs := TFakePushVcs.Create(TAtlasVcsKind.Svn);
  mKeepVcs := mVcs;
  mPulls := TFakePulls.Create;
  mKeepPulls := mPulls;
  mPull := TAtlasEndPull.Run(Request(mKeepVcs, mKeepPulls, cOrigin));
  Assert.AreEqual<TAtlasTrackerPullOutcome>(TAtlasTrackerPullOutcome.Failed, mPull.Outcome);
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.NotConfigured, mPull.Error);
  Assert.AreEqual(0, Integer(Length(mVcs.Calls)));
end;

procedure TAtlasEndPullTests.EndStepWithoutPullIsSkipped;
var
  mPlan: TAtlasTrackerEndPlan;
begin
  mPlan := Default(TAtlasTrackerEndPlan);
  Assert.IsFalse(mPlan.Has(TAtlasTrackerEndStep.PullRequest));
  mPlan.Pull := PullSpec;
  Assert.IsTrue(mPlan.Has(TAtlasTrackerEndStep.PullRequest));
end;

procedure TAtlasEndPullTests.FailedPullStopsEnd;
begin
  Assert.IsFalse(TAtlasTrackerPullResult.Make(TAtlasTrackerPullOutcome.Dirty).Stands);
  Assert.IsTrue(TAtlasTrackerPullResult.Make(TAtlasTrackerPullOutcome.Existing).Stands);
  Assert.AreEqual<TAtlasTrackerPullOutcome>(TAtlasTrackerPullOutcome.Failed,
    TAtlasTrackerPullResult.Failure(TAtlasCiFetchError.Server, 500, 'x').Outcome);
end;

procedure TAtlasEndPullTests.FillWritesClosesKeyword;
var
  mValues: TAtlasTrackerPlaceholders;
begin
  mValues := TAtlasTrackerPlaceholders.Create('#7', cBranch);
  Assert.AreEqual('Closes #7', TAtlasTrackerWorkflow.Fill('{closes}', mValues));
end;

procedure TAtlasEndPullTests.ConnectionOverridesPrBase;
var
  mConnections: TArray<TAtlasTrackerConnection>;
  mOptions: TAtlasTrackerSyncOptions;
  mTarget: TAtlasTrackerTarget;
begin
  mConnections := TAtlasTrackerConnections.Read('[{"name":"A","provider":"github","url":"https://git.firma.local",' +
    '"githubPrBase":" develop "},{"name":"B","provider":"github","url":"https://git.andere.local"}]');
  Assert.AreEqual(2, Integer(Length(mConnections)));
  Assert.AreEqual('develop', mConnections[0].GitHubPrBase);
  Assert.IsTrue(Pos('"githubPrBase": "develop"', TAtlasTrackerConnections.ToJson(mConnections)) > 0,
    TAtlasTrackerConnections.ToJson(mConnections));
  mOptions := TAtlasTrackerSyncOptions.Create(True, '', '').WithPullRequest(True, ' main ', '{closes}', True);
  Assert.AreEqual('main', mOptions.GitHub.PrBase);
  Assert.IsTrue(mOptions.GitHub.CreatePr and mOptions.GitHub.PrDraft);
  mTarget := TAtlasTrackerTarget.Create('github', 'https://git.firma.local', 'team/kasse', '');
  Assert.AreEqual('develop', TAtlasTrackerWorkflow.ForConnection(mOptions, mConnections, mTarget).GitHub.PrBase);
  mTarget := TAtlasTrackerTarget.Create('github', 'https://git.andere.local', 'team/kasse', '');
  Assert.AreEqual('main', TAtlasTrackerWorkflow.ForConnection(mOptions, mConnections, mTarget).GitHub.PrBase);
  mConnections := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEndPullTests);

end.
