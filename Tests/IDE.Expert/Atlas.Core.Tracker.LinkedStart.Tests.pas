unit Atlas.Core.Tracker.LinkedStart.Tests;

// „Beginnen“ mit verknüpftem Branch (#2138) gegen eine Fake-
// Versionsverwaltung und einen Fake-Tracker: Anlegen, Abruf und Auschecken,
// Rückfall auf den lokalen Weg (fremder Remote, vorhandener Branch, fehlende
// Rechte, Abruf gescheitert), dazu die Einstellung je Verbindung und die
// Kennzeichnung im Reiter „Entwicklung“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasLinkedStartTests = class
  public
    [Test]
    procedure CreatedBranchIsFetchedAndCheckedOut;
    [Test]
    procedure FoundBranchIsCheckedOutUnderItsName;
    [Test]
    procedure ForeignOriginGoesLocal;
    [Test]
    procedure RemoteBranchKnownGoesLocal;
    [Test]
    procedure DeniedGoesLocal;
    [Test]
    procedure FailedFetchGoesLocal;
    [Test]
    procedure SvnIsNotLinked;
    [Test]
    procedure ConnectionOverridesLinkBranch;
    [Test]
    procedure DevelopmentMarksLinkedBranches;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Development,
  Atlas.Core.Tracker.LinkedStart,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.VersionControl.Contract;

const
  cBranch = 'feature/7-statusfeld';
  cOrigin = 'git@github.com:beispiel/atlas.git';

type
  /// <summary>Git mit Remote-Branches im Speicher; merkt sich fetch und switch.</summary>
  TFakeLinkVcs = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsBranching, IAtlasVcsIncoming)
  public
    VcsKind: TAtlasVcsKind;
    RemoteBranches: TArray<string>;
    FetchOutcome: TAtlasVcsOutcome;
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
    { IAtlasVcsBranching }
    function BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome; overload;
    function BranchExists(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions;
      out AExists: Boolean): TAtlasVcsOutcome; overload;
    function RemoteBranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
    function ServerRevision(const APath: string; out ARevision: string): TAtlasVcsOutcome;
    function HasExternals(out AHas: Boolean): TAtlasVcsOutcome;
    function RepositoryPath(out APath: string): TAtlasVcsOutcome;
    function RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
    function SwitchBranch(const AName: string): TAtlasVcsOutcome; overload;
    function SwitchBranch(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions): TAtlasVcsOutcome;
      overload;
    function HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
    { IAtlasVcsIncoming }
    function Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
    function Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
      out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
    function Fetch(const ARemote: string): TAtlasVcsOutcome;
  end;

  /// <summary>Tracker mit festem Ergebnis; merkt sich, ob angelegt werden sollte.</summary>
  TFakeLinker = class(TInterfacedObject, IAtlasTrackerBranchLinker)
  public
    Answer: TAtlasTrackerBranchLink;
    Asked: Boolean;
    function SameRepository(const ATarget: TAtlasTrackerTarget; const AOriginUrl: string): Boolean;
    function LinkBranch(const ACall: TAtlasTrackerCall; const AKey, ABranch, ABase: string): TAtlasTrackerBranchLink;
  end;

constructor TFakeLinkVcs.Create(AKind: TAtlasVcsKind);
begin
  inherited Create;
  VcsKind := AKind;
  FetchOutcome := TAtlasVcsOutcome.Ok;
end;

function TFakeLinkVcs.Kind: TAtlasVcsKind;
begin
  Result := VcsKind;
end;

function TFakeLinkVcs.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result := TAtlasVcsWorkingCopy.Empty;
  Result.Kind := VcsKind;
  Result.Root := 'C:\Repo';
end;

function TFakeLinkVcs.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  AHead := TAtlasVcsHead.Empty;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeLinkVcs.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeLinkVcs.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeLinkVcs.Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeLinkVcs.ChangeMarker: string;
begin
  Result := '';
end;

function TFakeLinkVcs.BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  AExists := False;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeLinkVcs.BranchExists(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions;
  out AExists: Boolean): TAtlasVcsOutcome;
begin
  Result := BranchExists(AName, AExists);
end;

function TFakeLinkVcs.RemoteBranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
var
  mName: string;
begin
  AExists := False;
  for mName in RemoteBranches do
  begin
    AExists := AExists or (mName = AName);
  end;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeLinkVcs.ServerRevision(const APath: string; out ARevision: string): TAtlasVcsOutcome;
begin
  ARevision := '';
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeLinkVcs.HasExternals(out AHas: Boolean): TAtlasVcsOutcome;
begin
  AHas := False;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeLinkVcs.RepositoryPath(out APath: string): TAtlasVcsOutcome;
begin
  APath := '';
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeLinkVcs.RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
begin
  Calls := Calls + ['step'];
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeLinkVcs.SwitchBranch(const AName: string): TAtlasVcsOutcome;
begin
  Calls := Calls + ['switch ' + AName];
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeLinkVcs.SwitchBranch(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions): TAtlasVcsOutcome;
begin
  Result := SwitchBranch(AName);
end;

function TFakeLinkVcs.HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
begin
  AHooks := 'C:\Repo\.git\hooks';
  AGitDir := 'C:\Repo\.git';
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeLinkVcs.Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
begin
  ARevision := '';
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeLinkVcs.Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
  out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
begin
  ACommits := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeLinkVcs.Fetch(const ARemote: string): TAtlasVcsOutcome;
begin
  Calls := Calls + ['fetch ' + ARemote];
  Result := FetchOutcome;
end;

function TFakeLinker.SameRepository(const ATarget: TAtlasTrackerTarget; const AOriginUrl: string): Boolean;
begin
  Result := AOriginUrl = cOrigin;
end;

function TFakeLinker.LinkBranch(const ACall: TAtlasTrackerCall; const AKey, ABranch,
  ABase: string): TAtlasTrackerBranchLink;
begin
  Asked := True;
  Result := Answer;
end;

/// <summary>Anfrage für Issue #7 mit AVcs und ALinker.</summary>
function Request(const AVcs: IAtlasVersionControl; const ALinker: IAtlasTrackerBranchLinker;
  const AOrigin: string): TAtlasLinkedStartRequest;
begin
  Result := Default(TAtlasLinkedStartRequest);
  Result.Vcs := AVcs;
  Result.Linker := ALinker;
  Result.Call := TAtlasTrackerCall.Create(TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', ''), nil, 1000);
  Result.Key := '#7';
  Result.Branch := cBranch;
  Result.Base := 'main';
  Result.Origin := AOrigin;
end;

function Created: TAtlasTrackerBranchLink;
begin
  Result := TAtlasTrackerBranchLink.Make(TAtlasTrackerBranchLinkOutcome.Created, cBranch);
  Result.Base := 'main';
end;

{ TAtlasLinkedStartTests }

procedure TAtlasLinkedStartTests.CreatedBranchIsFetchedAndCheckedOut;
var
  mVcs: TFakeLinkVcs;
  mKeepVcs: IAtlasVersionControl;
  mLinker: TFakeLinker;
  mKeepLinker: IAtlasTrackerBranchLinker;
  mResult: TAtlasLinkedStartResult;
begin
  mVcs := TFakeLinkVcs.Create(TAtlasVcsKind.Git);
  mKeepVcs := mVcs;
  mLinker := TFakeLinker.Create;
  mKeepLinker := mLinker;
  mLinker.Answer := Created;
  mResult := TAtlasLinkedStart.Run(Request(mKeepVcs, mKeepLinker, cOrigin));
  Assert.IsTrue(mResult.CheckedOut);
  Assert.AreEqual('fetch origin|switch ' + cBranch, string.Join('|', mVcs.Calls));
  Assert.AreEqual<TAtlasTrackerBranchLinkOutcome>(TAtlasTrackerBranchLinkOutcome.Created, mResult.Link.Outcome);
  Assert.AreEqual(cBranch, mResult.Link.Branch);
  Assert.AreEqual('main', mResult.Link.Base);
  Assert.AreEqual('C:\Repo\.git\hooks', mResult.Hooks);
end;

procedure TAtlasLinkedStartTests.FoundBranchIsCheckedOutUnderItsName;
var
  mVcs: TFakeLinkVcs;
  mKeepVcs: IAtlasVersionControl;
  mLinker: TFakeLinker;
  mKeepLinker: IAtlasTrackerBranchLinker;
begin
  mVcs := TFakeLinkVcs.Create(TAtlasVcsKind.Git);
  mKeepVcs := mVcs;
  mLinker := TFakeLinker.Create;
  mKeepLinker := mLinker;
  mLinker.Answer := TAtlasTrackerBranchLink.Make(TAtlasTrackerBranchLinkOutcome.Found, '7-anderer-name');
  Assert.IsTrue(TAtlasLinkedStart.Run(Request(mKeepVcs, mKeepLinker, cOrigin)).CheckedOut);
  Assert.AreEqual('fetch origin|switch 7-anderer-name', string.Join('|', mVcs.Calls));
end;

procedure TAtlasLinkedStartTests.ForeignOriginGoesLocal;
var
  mVcs: TFakeLinkVcs;
  mKeepVcs: IAtlasVersionControl;
  mLinker: TFakeLinker;
  mKeepLinker: IAtlasTrackerBranchLinker;
  mResult: TAtlasLinkedStartResult;
begin
  mVcs := TFakeLinkVcs.Create(TAtlasVcsKind.Git);
  mKeepVcs := mVcs;
  mLinker := TFakeLinker.Create;
  mKeepLinker := mLinker;
  mLinker.Answer := Created;
  mResult := TAtlasLinkedStart.Run(Request(mKeepVcs, mKeepLinker, 'https://github.com/fork/atlas.git'));
  Assert.AreEqual<TAtlasTrackerBranchLinkOutcome>(TAtlasTrackerBranchLinkOutcome.Foreign, mResult.Link.Outcome);
  Assert.IsFalse(mResult.CheckedOut);
  Assert.IsFalse(mLinker.Asked, 'nichts auf dem Server angelegt');
  Assert.AreEqual(0, Integer(Length(mVcs.Calls)));
end;

procedure TAtlasLinkedStartTests.RemoteBranchKnownGoesLocal;
var
  mVcs: TFakeLinkVcs;
  mKeepVcs: IAtlasVersionControl;
  mLinker: TFakeLinker;
  mKeepLinker: IAtlasTrackerBranchLinker;
  mResult: TAtlasLinkedStartResult;
begin
  mVcs := TFakeLinkVcs.Create(TAtlasVcsKind.Git);
  mKeepVcs := mVcs;
  mVcs.RemoteBranches := [cBranch];
  mLinker := TFakeLinker.Create;
  mKeepLinker := mLinker;
  mLinker.Answer := Created;
  mResult := TAtlasLinkedStart.Run(Request(mKeepVcs, mKeepLinker, cOrigin));
  Assert.AreEqual<TAtlasTrackerBranchLinkOutcome>(TAtlasTrackerBranchLinkOutcome.Exists, mResult.Link.Outcome);
  Assert.AreEqual(cBranch, mResult.Link.Branch);
  Assert.IsFalse(mLinker.Asked);
end;

procedure TAtlasLinkedStartTests.DeniedGoesLocal;
var
  mVcs: TFakeLinkVcs;
  mKeepVcs: IAtlasVersionControl;
  mLinker: TFakeLinker;
  mKeepLinker: IAtlasTrackerBranchLinker;
  mResult: TAtlasLinkedStartResult;
begin
  mVcs := TFakeLinkVcs.Create(TAtlasVcsKind.Git);
  mKeepVcs := mVcs;
  mLinker := TFakeLinker.Create;
  mKeepLinker := mLinker;
  mLinker.Answer := TAtlasTrackerBranchLink.Failure(TAtlasCiFetchError.Unauthorized, 'nein');
  mResult := TAtlasLinkedStart.Run(Request(mKeepVcs, mKeepLinker, cOrigin));
  Assert.AreEqual<TAtlasTrackerBranchLinkOutcome>(TAtlasTrackerBranchLinkOutcome.Denied, mResult.Link.Outcome);
  Assert.IsFalse(mResult.CheckedOut);
  Assert.AreEqual(0, Integer(Length(mVcs.Calls)), 'kein Abruf');
end;

procedure TAtlasLinkedStartTests.FailedFetchGoesLocal;
var
  mVcs: TFakeLinkVcs;
  mKeepVcs: IAtlasVersionControl;
  mLinker: TFakeLinker;
  mKeepLinker: IAtlasTrackerBranchLinker;
  mResult: TAtlasLinkedStartResult;
begin
  mVcs := TFakeLinkVcs.Create(TAtlasVcsKind.Git);
  mKeepVcs := mVcs;
  mVcs.FetchOutcome := TAtlasVcsOutcome.Failed;
  mLinker := TFakeLinker.Create;
  mKeepLinker := mLinker;
  mLinker.Answer := Created;
  mResult := TAtlasLinkedStart.Run(Request(mKeepVcs, mKeepLinker, cOrigin));
  Assert.AreEqual<TAtlasTrackerBranchLinkOutcome>(TAtlasTrackerBranchLinkOutcome.Created, mResult.Link.Outcome);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mResult.Fetch);
  Assert.IsFalse(mResult.CheckedOut);
  Assert.AreEqual('fetch origin', string.Join('|', mVcs.Calls), 'nicht ausgecheckt');
end;

procedure TAtlasLinkedStartTests.SvnIsNotLinked;
var
  mVcs: TFakeLinkVcs;
  mKeepVcs: IAtlasVersionControl;
  mLinker: TFakeLinker;
  mKeepLinker: IAtlasTrackerBranchLinker;
  mResult: TAtlasLinkedStartResult;
begin
  mVcs := TFakeLinkVcs.Create(TAtlasVcsKind.Svn);
  mKeepVcs := mVcs;
  mLinker := TFakeLinker.Create;
  mKeepLinker := mLinker;
  mLinker.Answer := Created;
  mResult := TAtlasLinkedStart.Run(Request(mKeepVcs, mKeepLinker, cOrigin));
  Assert.AreEqual<TAtlasTrackerBranchLinkOutcome>(TAtlasTrackerBranchLinkOutcome.None, mResult.Link.Outcome);
  Assert.IsFalse(mLinker.Asked);
end;

procedure TAtlasLinkedStartTests.ConnectionOverridesLinkBranch;
var
  mConnections: TArray<TAtlasTrackerConnection>;
  mTarget: TAtlasTrackerTarget;
  mOptions: TAtlasTrackerSyncOptions;
begin
  mConnections := TAtlasTrackerConnections.Read('[{"name":"A","provider":"github","url":"https://github.com",' +
    '"githubLinkBranch":true},{"name":"B","provider":"github","url":"https://git.firma.local",' +
    '"githubLinkBranch":false},{"name":"C","provider":"github","url":"https://git.andere.local"}]');
  Assert.AreEqual(3, Integer(Length(mConnections)));
  Assert.AreEqual(TAtlasTrackerConnection.cOn, mConnections[0].GitHubLinkBranch);
  Assert.AreEqual(TAtlasTrackerConnection.cOff, mConnections[1].GitHubLinkBranch);
  Assert.AreEqual('', mConnections[2].GitHubLinkBranch);
  Assert.IsTrue(Pos('"githubLinkBranch": true', TAtlasTrackerConnections.ToJson(mConnections)) > 0,
    TAtlasTrackerConnections.ToJson(mConnections));
  mOptions := TAtlasTrackerSyncOptions.Create(True, '', '').WithLinkBranch(False);
  mTarget := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
  Assert.IsTrue(TAtlasTrackerWorkflow.ForConnection(mOptions, mConnections, mTarget).GitHub.LinkBranch);
  mOptions := mOptions.WithLinkBranch(True);
  mTarget := TAtlasTrackerTarget.Create('github', 'https://git.firma.local', 'team/kasse', '');
  Assert.IsFalse(TAtlasTrackerWorkflow.ForConnection(mOptions, mConnections, mTarget).GitHub.LinkBranch);
  mTarget := TAtlasTrackerTarget.Create('github', 'https://git.andere.local', 'team/kasse', '');
  Assert.IsTrue(TAtlasTrackerWorkflow.ForConnection(mOptions, mConnections, mTarget).GitHub.LinkBranch);
end;

/// <summary>Remote-Ref AName auf origin.</summary>
function RemoteRef(const AName: string): TAtlasVcsRef;
begin
  Result := Default(TAtlasVcsRef);
  Result.LocalName := AName;
  Result.Name := 'origin/' + AName;
  Result.Remote := True;
end;

procedure TAtlasLinkedStartTests.DevelopmentMarksLinkedBranches;
var
  mRequest: TAtlasIssueDevelopmentRequest;
  mBranches: TArray<TAtlasIssueBranch>;
begin
  mRequest := TAtlasIssueDevelopmentRequest.Create('github', 'beispiel/atlas', '#7', nil, nil);
  mRequest.Linked := ['statusfeld-schritt'];
  mBranches := TAtlasIssueDevelopmentQuery.BranchesOf(mRequest, [RemoteRef('feature/7-statusfeld'),
    RemoteRef('statusfeld-schritt'), RemoteRef('anderes')]);
  Assert.AreEqual(2, Integer(Length(mBranches)));
  Assert.AreEqual('feature/7-statusfeld', mBranches[0].Name);
  Assert.IsFalse(mBranches[0].Linked, 'nur über den Namen gefunden');
  Assert.AreEqual('statusfeld-schritt', mBranches[1].Name);
  Assert.IsTrue(mBranches[1].Linked, 'Name folgt nicht dem Muster, ist aber verknüpft');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLinkedStartTests);

end.
