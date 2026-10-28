unit Atlas.Core.Vcs.BranchPlan.Tests;

// Plan für „Branch anlegen“ (#1288) ohne Prozesse: Inspect und InspectServer
// über eine Versionsverwaltung im Speicher, Basen und Vorgabe unter Git und
// SVN, die Schritte (genau die Befehlszeilen aus dem Dialog), Anzeige mit
// Anführungszeichen, Ausführung bis zum ersten Fehler mit Fortschritt und die
// Serverschritte, die danach stehen bleiben. Git-Optionen (#1289): Vorgaben
// aus den Einstellungen, Basis vom Server mit Abruf, stash, worktree-Ordner
// mit Platzhaltern, Push, Reihenfolge der Schritte, Rückfall nach
// gescheitertem Abruf und Push, der allein scheitert.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasVcsBranchPlanTests = class
  public
    /// <summary>Git: Hauptbranch = erster Kandidat, den es lokal oder auf origin gibt; unsichere übersprungen.
    /// </summary>
    [Test]
    procedure InspectGitFindsMainBranch;
    /// <summary>SVN: voller Pfad der Arbeitskopie, Revision, Externals; HEAD-Revision erst vom Server.</summary>
    [Test]
    procedure InspectSvnAndServer;
    [Test]
    procedure InspectWithoutVersionControl;
    /// <summary>Git: origin, lokal, aktuell; Vorgabe lokal vor origin, ohne Hauptbranch keine.</summary>
    [Test]
    procedure BasesAndDefaultGit;
    /// <summary>SVN: Hauptbranch @ HEAD und Arbeitskopie @ Revision; Vorgabe HEAD.</summary>
    [Test]
    procedure BasesAndDefaultSvn;
    /// <summary>Git: checkout -b von refs/heads, refs/remotes/origin oder HEAD; ungültige Eingaben ohne Schritte.
    /// </summary>
    [Test]
    procedure StepsGit;
    /// <summary>SVN: copy mit Nachricht (Vorgabe „Branch &lt;Name&gt;“) auf dem Server, dann switch.</summary>
    [Test]
    procedure StepsSvn;
    [Test]
    procedure StepTextQuotesArguments;
    /// <summary>Hört beim ersten Fehler auf; Fortschritt vor jedem Schritt; die Kopie bleibt als Serverschritt.
    /// </summary>
    [Test]
    procedure ExecuteStopsAtFirstFailure;
    /// <summary>#1289: Werte der Einstellungen; Unbekanntes gilt als Vorgabe des Schemas.</summary>
    [Test]
    procedure GitOptionsFromSettings;
    /// <summary>#1289: Remote des lokalen Hauptbranchs aus dem verfolgten Branch; dessen Stand statt origin.
    /// </summary>
    [Test]
    procedure InspectGitRemoteOfMainBranch;
    /// <summary>#1289: Vorgabe-Basis und Felder der Anfrage je Option.</summary>
    [Test]
    procedure DefaultRequestWithGitOptions;
    /// <summary>#1289: fetch, stash, checkout bzw. worktree add, push in dieser Reihenfolge.</summary>
    [Test]
    procedure StepsGitOptions;
    /// <summary>#1289: Platzhalter {repo}, {name}, {kennung}, relativ zur Wurzel; Projekt im neuen Ordner.
    /// </summary>
    [Test]
    procedure WorktreePathAndProject;
    /// <summary>#1289: Abruf gescheitert (nichts geändert, Rückfall auf den lokalen Stand); nur Push gescheitert.
    /// </summary>
    [Test]
    procedure FetchFallbackAndPushFailure;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.BranchPlan;

var
  /// <summary>Protokoll von RecordingProgress.</summary>
  ProgressLog: TArray<string>;

/// <summary>Fortschritt, der Index, Anzahl und Befehl festhält; in eigener Routine gebaut.</summary>
function RecordingProgress: TAtlasVcsBranchProgress;
begin
  Result :=
    procedure(AIndex, ACount: Integer; const AStep: TAtlasVcsBranchStep)
    begin
      ProgressLog := ProgressLog + [Format('%d/%d %s', [AIndex, ACount, AStep.Arguments[0]])];
    end;
end;

type
  /// <summary>Versionsverwaltung im Speicher für Inspect und Execute.</summary>
  TPlanVcs = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsBranching)
  public
    VcsKind: TAtlasVcsKind;
    HeadBranch: string;
    HeadRevision: string;
    LocalBranches: TArray<string>;
    RemoteBranches: TArray<string>;
    RepoPath: string;
    Externals: Boolean;
    ServerOutcome: TAtlasVcsOutcome;
    /// <summary>Schritt mit diesem Befehl scheitert.</summary>
    FailOn: string;
    Calls: TArray<string>;
    constructor Create(AKind: TAtlasVcsKind);
    class function Has(const AList: TArray<string>; const AName: string): Boolean; static;
    { IAtlasVersionControl }
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
    { IAtlasVcsBranching }
    function BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
    function RemoteBranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
    function ServerRevision(const APath: string; out ARevision: string): TAtlasVcsOutcome;
    function HasExternals(out AHas: Boolean): TAtlasVcsOutcome;
    function RepositoryPath(out APath: string): TAtlasVcsOutcome;
    function RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
    function SwitchBranch(const AName: string): TAtlasVcsOutcome;
    function HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
  end;

  /// <summary>Wie TPlanVcs mit verfolgten Branches (IAtlasVcsLocalWork) und Remote-Refs (IAtlasVcsIncoming).
  /// </summary>
  TRemotePlanVcs = class(TPlanVcs, IAtlasVcsLocalWork, IAtlasVcsIncoming)
  public
    /// <summary>Remote des verfolgten Branchs von main.</summary>
    MainRemote: string;
    /// <summary>Volle Refs, die Resolve kennt.</summary>
    Refs: TArray<string>;
    { IAtlasVcsLocalWork }
    function Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
    function Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
    function Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
    function Outgoing(const ABranch, AUpstream: string; AMax: Integer;
      out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
    function ChangesIn(const ARevision: string; out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function Push(const ABranch, ARemote, ARemoteRef: string; ASetUpstream: Boolean): TAtlasVcsOutcome;
    { IAtlasVcsIncoming }
    function Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
    function Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
      out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
    function Fetch(const ARemote: string): TAtlasVcsOutcome;
  end;

  /// <summary>Kennt nur IAtlasVersionControl, nicht IAtlasVcsBranching.</summary>
  TPlainVcs = class(TInterfacedObject, IAtlasVersionControl)
  public
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
  end;

{ TPlanVcs }

constructor TPlanVcs.Create(AKind: TAtlasVcsKind);
begin
  inherited Create;
  VcsKind := AKind;
  ServerOutcome := TAtlasVcsOutcome.Ok;
end;

class function TPlanVcs.Has(const AList: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in AList do
    if mName = AName then
      Exit(True);
end;

function TPlanVcs.Kind: TAtlasVcsKind;
begin
  Result := VcsKind;
end;

function TPlanVcs.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result := TAtlasVcsWorkingCopy.Empty;
  Result.Kind := VcsKind;
  Result.Root := 'C:\Repo';
end;

function TPlanVcs.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  AHead := TAtlasVcsHead.Empty;
  AHead.Branch := HeadBranch;
  AHead.Revision := HeadRevision;
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlanVcs.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlanVcs.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TPlanVcs.Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TPlanVcs.ChangeMarker: string;
begin
  Result := '';
end;

function TPlanVcs.BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  Calls := Calls + ['exists ' + AName];
  AExists := Has(LocalBranches, AName);
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlanVcs.RemoteBranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  Calls := Calls + ['remote ' + AName];
  AExists := Has(RemoteBranches, AName);
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlanVcs.ServerRevision(const APath: string; out ARevision: string): TAtlasVcsOutcome;
begin
  Calls := Calls + ['revision ' + APath];
  ARevision := '';
  Result := ServerOutcome;
  if Result = TAtlasVcsOutcome.Ok then
    ARevision := '48230';
end;

function TPlanVcs.HasExternals(out AHas: Boolean): TAtlasVcsOutcome;
begin
  AHas := Externals;
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlanVcs.RepositoryPath(out APath: string): TAtlasVcsOutcome;
begin
  APath := RepoPath;
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlanVcs.RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
begin
  Calls := Calls + ['run ' + string.Join(' ', AStep.Arguments)];
  Result := TAtlasVcsOutcome.Ok;
  if AStep.Arguments[0] = FailOn then
    Result := TAtlasVcsOutcome.LoginNeeded;
end;

function TPlanVcs.SwitchBranch(const AName: string): TAtlasVcsOutcome;
begin
  Calls := Calls + ['switch ' + AName];
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlanVcs.HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
begin
  AHooks := '';
  AGitDir := '';
  Result := TAtlasVcsOutcome.Ok;
end;

{ TRemotePlanVcs }

function TRemotePlanVcs.Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
var
  mBranch: TAtlasVcsBranch;
begin
  mBranch := Default(TAtlasVcsBranch);
  mBranch.Name := 'main';
  mBranch.Remote := MainRemote;
  if MainRemote <> '' then
    mBranch.Upstream := MainRemote + '/main';
  ABranches := TArray<TAtlasVcsBranch>.Create(mBranch);
  Result := TAtlasVcsOutcome.Ok;
end;

function TRemotePlanVcs.Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
begin
  AStashes := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TRemotePlanVcs.Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
begin
  ANames := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TRemotePlanVcs.Outgoing(const ABranch, AUpstream: string; AMax: Integer;
  out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
begin
  ACommits := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TRemotePlanVcs.ChangesIn(const ARevision: string; out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TRemotePlanVcs.Push(const ABranch, ARemote, ARemoteRef: string; ASetUpstream: Boolean): TAtlasVcsOutcome;
begin
  Result := TAtlasVcsOutcome.Failed;
end;

function TRemotePlanVcs.Resolve(const ARef: string; out ARevision: string): TAtlasVcsOutcome;
begin
  Calls := Calls + ['resolve ' + ARef];
  ARevision := '';
  Result := TAtlasVcsOutcome.Failed;
  if Has(Refs, ARef) then
  begin
    ARevision := 'abc123';
    Result := TAtlasVcsOutcome.Ok;
  end;
end;

function TRemotePlanVcs.Incoming(const AUpstream: string; const AExclude: TArray<string>; AMax: Integer;
  out ACommits: TArray<TAtlasVcsIncomingCommit>): TAtlasVcsOutcome;
begin
  ACommits := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TRemotePlanVcs.Fetch(const ARemote: string): TAtlasVcsOutcome;
begin
  Result := TAtlasVcsOutcome.Ok;
end;

{ TPlainVcs }

function TPlainVcs.Kind: TAtlasVcsKind;
begin
  Result := TAtlasVcsKind.Git;
end;

function TPlainVcs.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result := TAtlasVcsWorkingCopy.Empty;
end;

function TPlainVcs.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  AHead := TAtlasVcsHead.Empty;
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlainVcs.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlainVcs.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TPlainVcs.Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TPlainVcs.ChangeMarker: string;
begin
  Result := '';
end;

function GitFacts(ALocal, ARemote: Boolean; const ACurrent: string): TAtlasVcsBranchFacts;
begin
  Result := TAtlasVcsBranchFacts.Empty;
  Result.Kind := TAtlasVcsKind.Git;
  Result.Outcome := TAtlasVcsOutcome.Ok;
  Result.Current := ACurrent;
  if ALocal or ARemote then
    Result.MainBranch := 'main';
  Result.LocalMain := ALocal;
  Result.RemoteMain := ARemote;
end;

function SvnFacts(const AHeadRevision: string): TAtlasVcsBranchFacts;
begin
  Result := TAtlasVcsBranchFacts.Empty;
  Result.Kind := TAtlasVcsKind.Svn;
  Result.Outcome := TAtlasVcsOutcome.Ok;
  Result.Current := 'Kasse/trunk';
  Result.Revision := '48100';
  Result.MainBranch := 'trunk';
  Result.HeadRevision := AHeadRevision;
  Result.ServerChecked := True;
end;

function Base(AKind: TAtlasVcsBranchBaseKind; const AName, ARevision: string): TAtlasVcsBranchBase;
begin
  Result := TAtlasVcsBranchBase.Make(AKind, AName, ARevision);
end;

/// <summary>Wurzel einer Arbeitskopie „Kasse“ und ihr übergeordneter Ordner, je nach Betriebssystem.</summary>
function RepoRoot: string;
begin
  Result := ExpandFileName(PathDelim + 'Projekte' + PathDelim + 'Kasse');
end;

function RepoParent: string;
begin
  Result := ExtractFileDir(RepoRoot);
end;

function GitOptions(ABase: TAtlasVcsGitBaseOption; APushNow: Boolean; AUncommitted: TAtlasVcsGitUncommitted;
  AWorktree: Boolean): TAtlasVcsGitBranchOptions;
begin
  Result := TAtlasVcsGitBranchOptions.Classic;
  Result.Base := ABase;
  Result.PushNow := APushNow;
  Result.Uncommitted := AUncommitted;
  Result.Worktree := AWorktree;
end;

function Args(const AStep: TAtlasVcsBranchStep): string;
begin
  Result := string.Join(' ', AStep.Arguments);
end;

{ TAtlasVcsBranchPlanTests }

procedure TAtlasVcsBranchPlanTests.InspectGitFindsMainBranch;
var
  mFake: TPlanVcs;
  mVcs: IAtlasVersionControl;
  mFacts: TAtlasVcsBranchFacts;
begin
  mFake := TPlanVcs.Create(TAtlasVcsKind.Git);
  mVcs := mFake;
  mFake.HeadBranch := 'feature/12-x';
  mFake.LocalBranches := ['master'];
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('-x', 'main', 'master'));
  Assert.IsTrue(mFacts.Outcome = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(mFacts.Kind = TAtlasVcsKind.Git);
  Assert.AreEqual('feature/12-x', mFacts.Current);
  Assert.AreEqual('master', mFacts.MainBranch);
  Assert.IsTrue(mFacts.LocalMain);
  Assert.IsFalse(mFacts.RemoteMain);
  Assert.IsFalse(mFacts.NeedsServer, 'Git braucht den Server nicht');
  // "-x" ist keine Option für git: übersprungen, ohne nachzufragen.
  Assert.AreEqual(4, Integer(Length(mFake.Calls)));
  Assert.AreEqual('exists main', mFake.Calls[0]);
  Assert.AreEqual('remote master', mFake.Calls[3]);
  // Nur auf origin.
  mFake.LocalBranches := nil;
  mFake.RemoteBranches := ['main'];
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('main', 'master'));
  Assert.AreEqual('main', mFacts.MainBranch);
  Assert.IsFalse(mFacts.LocalMain);
  Assert.IsTrue(mFacts.RemoteMain);
  // Keiner vorhanden.
  mFake.RemoteBranches := nil;
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('main', 'master'));
  Assert.IsTrue(mFacts.Outcome = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('', mFacts.MainBranch);
  mFake.Calls := nil;
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasVcsBranchPlanTests.InspectSvnAndServer;
var
  mFake: TPlanVcs;
  mVcs: IAtlasVersionControl;
  mFacts: TAtlasVcsBranchFacts;
begin
  mFake := TPlanVcs.Create(TAtlasVcsKind.Svn);
  mVcs := mFake;
  mFake.HeadBranch := 'trunk';
  mFake.HeadRevision := '48100';
  mFake.RepoPath := 'Kasse/trunk';
  mFake.Externals := True;
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('trunk'));
  Assert.IsTrue(mFacts.Outcome = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('Kasse/trunk', mFacts.Current, 'voller Pfad, nicht der gekürzte aus Head');
  Assert.AreEqual('48100', mFacts.Revision);
  Assert.AreEqual('trunk', mFacts.MainBranch);
  Assert.IsTrue(mFacts.Externals);
  Assert.AreEqual('', mFacts.HeadRevision);
  Assert.IsTrue(mFacts.NeedsServer, 'HEAD-Revision fehlt noch');
  Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'Inspect fragt den Server nicht');
  TAtlasVcsBranchPlan.InspectServer(mVcs, mFacts);
  Assert.IsFalse(mFacts.NeedsServer);
  Assert.IsTrue(mFacts.ServerChecked);
  Assert.IsTrue(mFacts.ServerOutcome = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('48230', mFacts.HeadRevision);
  Assert.AreEqual('revision trunk', mFake.Calls[0]);
  // Ohne Anmeldung: Ergebnis festhalten, Revision bleibt unbekannt.
  mFake.RepoPath := '';
  mFake.ServerOutcome := TAtlasVcsOutcome.LoginNeeded;
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('trunk'));
  Assert.AreEqual('trunk', mFacts.Current, 'ohne Pfad der aus Head');
  TAtlasVcsBranchPlan.InspectServer(mVcs, mFacts);
  Assert.IsTrue(mFacts.ServerChecked);
  Assert.IsTrue(mFacts.ServerOutcome = TAtlasVcsOutcome.LoginNeeded);
  Assert.AreEqual('', mFacts.HeadRevision);
  mFake.Calls := nil;
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasVcsBranchPlanTests.InspectWithoutVersionControl;
var
  mFacts: TAtlasVcsBranchFacts;
  mBase: TAtlasVcsBranchBase;
  mPlain: IAtlasVersionControl;
begin
  mFacts := TAtlasVcsBranchPlan.Inspect(nil, TArray<string>.Create('main'));
  Assert.IsTrue(mFacts.Outcome = TAtlasVcsOutcome.NoWorkingCopy);
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Bases(mFacts))));
  Assert.IsFalse(TAtlasVcsBranchPlan.DefaultBase(mFacts, mBase));
  // Ohne IAtlasVcsBranching kein Anlegen.
  // In einer Variablen: ein Objekt direkt als const-Schnittstelle würde nie freigegeben.
  mPlain := TPlainVcs.Create;
  mFacts := TAtlasVcsBranchPlan.Inspect(mPlain, TArray<string>.Create('main'));
  Assert.IsTrue(mFacts.Outcome = TAtlasVcsOutcome.NoWorkingCopy);
  Assert.IsFalse(mFacts.NeedsServer);
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasVcsBranchPlanTests.BasesAndDefaultGit;
var
  mBases: TArray<TAtlasVcsBranchBase>;
  mBase: TAtlasVcsBranchBase;
  mRequest: TAtlasVcsBranchRequest;
begin
  mBases := TAtlasVcsBranchPlan.Bases(GitFacts(True, True, 'feature/12-x'));
  Assert.AreEqual(3, Integer(Length(mBases)));
  Assert.IsTrue(mBases[0].Kind = TAtlasVcsBranchBaseKind.RemoteMain);
  Assert.IsTrue(mBases[1].Kind = TAtlasVcsBranchBaseKind.LocalMain);
  Assert.IsTrue(mBases[2].Kind = TAtlasVcsBranchBaseKind.Current);
  Assert.AreEqual('feature/12-x', mBases[2].Name);
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultBase(GitFacts(True, True, 'feature/12-x'), mBase));
  Assert.IsTrue(mBase.Kind = TAtlasVcsBranchBaseKind.LocalMain, 'lokal vor origin wie bei „Beginnen“');
  // Auf main: der aktuelle Branch steht schon als lokaler Hauptbranch da.
  mBases := TAtlasVcsBranchPlan.Bases(GitFacts(True, True, 'main'));
  Assert.AreEqual(2, Integer(Length(mBases)));
  // Nur origin: Vorgabe origin/main.
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultBase(GitFacts(False, True, 'main'), mBase));
  Assert.IsTrue(mBase.Kind = TAtlasVcsBranchBaseKind.RemoteMain);
  // Ohne Hauptbranch: nur der aktuelle Branch zur Wahl, aber keine Vorgabe.
  mBases := TAtlasVcsBranchPlan.Bases(GitFacts(False, False, ''));
  Assert.AreEqual(1, Integer(Length(mBases)));
  Assert.IsTrue(mBases[0].Kind = TAtlasVcsBranchBaseKind.Current);
  Assert.AreEqual('', mBases[0].Name, 'losgelöster HEAD');
  Assert.IsFalse(TAtlasVcsBranchPlan.DefaultBase(GitFacts(False, False, 'feature/12-x'), mBase));
  Assert.IsFalse(TAtlasVcsBranchPlan.DefaultRequest(GitFacts(False, False, 'feature/12-x'), 'feature/13-y', '',
    mRequest));
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(GitFacts(False, True, 'x'), 'feature/13-y', '', mRequest));
  Assert.AreEqual('feature/13-y', mRequest.Name);
  Assert.AreEqual('origin/main', TAtlasVcsBranchPlan.BaseName(TAtlasVcsKind.Git, mRequest.Base));
  mBases := nil;
end;

procedure TAtlasVcsBranchPlanTests.BasesAndDefaultSvn;
var
  mBases: TArray<TAtlasVcsBranchBase>;
  mBase: TAtlasVcsBranchBase;
  mFacts: TAtlasVcsBranchFacts;
begin
  mBases := TAtlasVcsBranchPlan.Bases(SvnFacts('48230'));
  Assert.AreEqual(2, Integer(Length(mBases)));
  Assert.IsTrue(mBases[0].Kind = TAtlasVcsBranchBaseKind.Head);
  Assert.AreEqual('trunk', mBases[0].Name);
  Assert.AreEqual('48230', mBases[0].Revision);
  Assert.IsTrue(mBases[1].Kind = TAtlasVcsBranchBaseKind.WorkingCopy);
  Assert.AreEqual('Kasse/trunk', mBases[1].Name);
  Assert.AreEqual('48100', mBases[1].Revision);
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultBase(SvnFacts(''), mBase));
  Assert.IsTrue(mBase.Kind = TAtlasVcsBranchBaseKind.Head);
  Assert.AreEqual('trunk', TAtlasVcsBranchPlan.BaseName(TAtlasVcsKind.Svn, mBase), 'HEAD beim Kopieren');
  Assert.AreEqual('trunk@48230', TAtlasVcsBranchPlan.BaseName(TAtlasVcsKind.Svn, mBases[0]));
  mFacts := SvnFacts('');
  mFacts.MainBranch := '';
  Assert.IsFalse(TAtlasVcsBranchPlan.DefaultBase(mFacts, mBase), 'SVN ohne Hauptbranch: keine Vorgabe');
  mFacts.Outcome := TAtlasVcsOutcome.TimedOut;
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Bases(mFacts))));
  mBases := nil;
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasVcsBranchPlanTests.StepsGit;
var
  mSteps: TArray<TAtlasVcsBranchStep>;
begin
  mSteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/13-y',
    Base(TAtlasVcsBranchBaseKind.LocalMain, 'main', ''), ''));
  Assert.AreEqual(1, Integer(Length(mSteps)));
  Assert.AreEqual('checkout --quiet --no-track -b feature/13-y refs/heads/main --',
    string.Join(' ', mSteps[0].Arguments));
  Assert.IsFalse(mSteps[0].Remote);
  Assert.IsFalse(mSteps[0].ChangesServer);
  mSteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/13-y',
    Base(TAtlasVcsBranchBaseKind.RemoteMain, 'main', ''), ''));
  Assert.AreEqual('refs/remotes/origin/main', mSteps[0].Arguments[5]);
  mSteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/13-y',
    Base(TAtlasVcsBranchBaseKind.Current, 'feature/12-x', ''), ''));
  Assert.AreEqual('refs/heads/feature/12-x', mSteps[0].Arguments[5]);
  mSteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/13-y',
    Base(TAtlasVcsBranchBaseKind.Current, '', ''), ''));
  Assert.AreEqual('HEAD', mSteps[0].Arguments[5], 'losgelöst');
  // Ungültig: Name wie eine Option, Name mit Leerzeichen, Basis wie eine Option, ohne Versionsverwaltung.
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git,
    '--force', Base(TAtlasVcsBranchBaseKind.LocalMain, 'main', ''), '')))));
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git,
    'a b', Base(TAtlasVcsBranchBaseKind.LocalMain, 'main', ''), '')))));
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git,
    'feature/13-y', Base(TAtlasVcsBranchBaseKind.Current, '-x', ''), '')))));
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.None,
    'feature/13-y', Base(TAtlasVcsBranchBaseKind.LocalMain, 'main', ''), '')))));
  mSteps := nil;
end;

procedure TAtlasVcsBranchPlanTests.StepsSvn;
var
  mSteps: TArray<TAtlasVcsBranchStep>;
begin
  mSteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Svn, 'ATL-123-kasse',
    Base(TAtlasVcsBranchBaseKind.Head, 'trunk', '48230'), '  '));
  Assert.AreEqual(2, Integer(Length(mSteps)));
  Assert.AreEqual('copy ^/trunk@48230 ^/branches/ATL-123-kasse@ --parents -m Branch ATL-123-kasse',
    string.Join(' ', mSteps[0].Arguments));
  Assert.IsTrue(mSteps[0].Remote);
  Assert.IsTrue(mSteps[0].ChangesServer, 'svn copy ändert den Server');
  Assert.AreEqual('switch ^/branches/ATL-123-kasse@ .', string.Join(' ', mSteps[1].Arguments));
  Assert.IsTrue(mSteps[1].Remote);
  Assert.IsFalse(mSteps[1].ChangesServer);
  // Eigene Nachricht, Arbeitskopie als Basis, HEAD ohne Revision.
  mSteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Svn, 'ATL-123-kasse',
    Base(TAtlasVcsBranchBaseKind.WorkingCopy, 'Kasse/trunk', '48100'), 'ATL-123 Kasse'));
  Assert.AreEqual('^/Kasse/trunk@48100', mSteps[0].Arguments[1]);
  Assert.AreEqual('ATL-123 Kasse', mSteps[0].Arguments[5]);
  mSteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Svn, 'ATL-123-kasse',
    Base(TAtlasVcsBranchBaseKind.Head, 'trunk', ''), ''));
  Assert.AreEqual('^/trunk@', mSteps[0].Arguments[1], 'HEAD beim Kopieren');
  // Revision keine Zahl, Basis ohne Pfad: keine Schritte.
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Svn,
    'ATL-123-kasse', Base(TAtlasVcsBranchBaseKind.Head, 'trunk', 'HEAD'), '')))));
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Svn,
    'ATL-123-kasse', Base(TAtlasVcsBranchBaseKind.Head, '', ''), '')))));
  mSteps := nil;
end;

procedure TAtlasVcsBranchPlanTests.StepTextQuotesArguments;
var
  mStep: TAtlasVcsBranchStep;
begin
  mStep := TAtlasVcsBranchStep.Make(TArray<string>.Create('copy', '^/trunk@', '-m', 'Branch "neu" x'), True,
    True);
  Assert.AreEqual('svn copy ^/trunk@ -m "Branch \"neu\" x"', TAtlasVcsBranchPlan.StepText(TAtlasVcsKind.Svn,
    mStep));
  mStep := TAtlasVcsBranchStep.Make(TArray<string>.Create('checkout', '-b', 'x', ''), False, False);
  Assert.AreEqual('git checkout -b x ""', TAtlasVcsBranchPlan.StepText(TAtlasVcsKind.Git, mStep));
  mStep := TAtlasVcsBranchStep.Make(nil, False, False);
end;

procedure TAtlasVcsBranchPlanTests.ExecuteStopsAtFirstFailure;
var
  mFake: TPlanVcs;
  mBranching: IAtlasVcsBranching;
  mSteps, mServer: TArray<TAtlasVcsBranchStep>;
  mRun: TAtlasVcsBranchRun;
begin
  mFake := TPlanVcs.Create(TAtlasVcsKind.Svn);
  mBranching := mFake;
  mSteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Svn, 'ATL-1-a',
    Base(TAtlasVcsBranchBaseKind.Head, 'trunk', '48230'), ''));
  ProgressLog := nil;
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, mSteps, RecordingProgress());
  Assert.IsTrue(mRun.Succeeded);
  Assert.AreEqual(2, mRun.Done);
  Assert.AreEqual(-1, mRun.Failed);
  Assert.AreEqual(2, Integer(Length(ProgressLog)));
  Assert.AreEqual('0/2 copy', ProgressLog[0]);
  Assert.AreEqual('1/2 switch', ProgressLog[1]);
  // switch scheitert: copy ist auf dem Server geschehen und bleibt.
  mFake.FailOn := 'switch';
  mFake.Calls := nil;
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, mSteps);
  Assert.IsFalse(mRun.Succeeded);
  Assert.IsTrue(mRun.Outcome = TAtlasVcsOutcome.LoginNeeded);
  Assert.AreEqual(1, mRun.Done);
  Assert.AreEqual(1, mRun.Failed);
  mServer := TAtlasVcsBranchPlan.ServerStepsDone(mSteps, mRun.Done);
  Assert.AreEqual(1, Integer(Length(mServer)));
  Assert.AreEqual('copy', mServer[0].Arguments[0]);
  // copy scheitert: nichts weiter, nichts auf dem Server.
  mFake.FailOn := 'copy';
  mFake.Calls := nil;
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, mSteps);
  Assert.AreEqual(0, mRun.Failed);
  Assert.AreEqual(1, Integer(Length(mFake.Calls)));
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.ServerStepsDone(mSteps, mRun.Done))));
  // Ohne Schritte bzw. ohne Versionsverwaltung.
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, nil);
  Assert.IsTrue(mRun.Outcome = TAtlasVcsOutcome.Failed);
  mRun := TAtlasVcsBranchPlan.Execute(nil, mSteps);
  Assert.IsTrue(mRun.Outcome = TAtlasVcsOutcome.NoWorkingCopy);
  Assert.IsFalse(mRun.Succeeded);
  mFake.Calls := nil;
  mSteps := nil;
  mServer := nil;
  ProgressLog := nil;
end;

procedure TAtlasVcsBranchPlanTests.GitOptionsFromSettings;
var
  mOptions: TAtlasVcsGitBranchOptions;
begin
  mOptions := TAtlasVcsGitBranchOptions.FromSettings('remote', 'later', 'carry', False, '');
  Assert.IsTrue(mOptions.Base = TAtlasVcsGitBaseOption.Remote);
  Assert.IsFalse(mOptions.PushNow);
  Assert.IsTrue(mOptions.Uncommitted = TAtlasVcsGitUncommitted.Carry);
  Assert.IsFalse(mOptions.Worktree);
  Assert.AreEqual(TAtlasVcsGitBranchOptions.DefaultWorktreeFolder, mOptions.WorktreeFolder, 'leer = Vorgabe');
  mOptions := TAtlasVcsGitBranchOptions.FromSettings(' Local ', 'now', 'stash', True, ' ..\{name} ');
  Assert.IsTrue(mOptions.Base = TAtlasVcsGitBaseOption.Local);
  Assert.IsTrue(mOptions.PushNow);
  Assert.IsTrue(mOptions.Uncommitted = TAtlasVcsGitUncommitted.Stash);
  Assert.IsTrue(mOptions.Worktree);
  Assert.AreEqual('..\{name}', mOptions.WorktreeFolder);
  mOptions := TAtlasVcsGitBranchOptions.FromSettings('current', 'bald', 'ask', False, '');
  Assert.IsTrue(mOptions.Base = TAtlasVcsGitBaseOption.Current);
  Assert.IsFalse(mOptions.PushNow, 'unbekannt = later');
  Assert.IsTrue(mOptions.Uncommitted = TAtlasVcsGitUncommitted.Ask);
  mOptions := TAtlasVcsGitBranchOptions.FromSettings('irgendwo', '', 'weg', False, '');
  Assert.IsTrue(mOptions.Base = TAtlasVcsGitBaseOption.Remote, 'unbekannt = remote');
  Assert.IsTrue(mOptions.Uncommitted = TAtlasVcsGitUncommitted.Carry, 'unbekannt = carry');
  // Verhalten vor #1289.
  mOptions := TAtlasVcsGitBranchOptions.Classic;
  Assert.IsTrue(mOptions.Base = TAtlasVcsGitBaseOption.Local);
  Assert.IsFalse(mOptions.PushNow);
  Assert.IsTrue(mOptions.Uncommitted = TAtlasVcsGitUncommitted.Carry);
  Assert.IsFalse(mOptions.Worktree);
  mOptions.WorktreeFolder := '';
end;

procedure TAtlasVcsBranchPlanTests.InspectGitRemoteOfMainBranch;
var
  mFake: TRemotePlanVcs;
  mVcs: IAtlasVersionControl;
  mFacts: TAtlasVcsBranchFacts;
  mBases: TArray<TAtlasVcsBranchBase>;
begin
  mFake := TRemotePlanVcs.Create(TAtlasVcsKind.Git);
  mVcs := mFake;
  mFake.HeadBranch := 'feature/12-x';
  mFake.LocalBranches := ['main'];
  // main verfolgt upstream/main; origin hat ihn nicht, upstream schon.
  mFake.MainRemote := 'upstream';
  mFake.Refs := ['refs/remotes/upstream/main'];
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('main'));
  Assert.AreEqual('C:\Repo', mFacts.Root, 'Wurzel der Arbeitskopie');
  Assert.AreEqual('upstream', mFacts.Remote);
  Assert.IsTrue(mFacts.RemoteMain, 'Stand von upstream/main');
  Assert.AreEqual('resolve refs/remotes/upstream/main', mFake.Calls[High(mFake.Calls)]);
  mBases := TAtlasVcsBranchPlan.Bases(mFacts);
  Assert.AreEqual('upstream', mBases[0].Remote);
  Assert.AreEqual('upstream/main', TAtlasVcsBranchPlan.BaseName(TAtlasVcsKind.Git, mBases[0]));
  Assert.AreEqual('refs/remotes/upstream/main', TAtlasVcsBranchPlan.BaseRef(TAtlasVcsKind.Git, mBases[0]));
  Assert.AreEqual('upstream', mBases[1].Remote, 'auch die lokale Basis pusht nach upstream');
  // Ohne verfolgten Branch: origin, ohne weitere Abfrage.
  mFake.MainRemote := '';
  mFake.Calls := nil;
  mFake.RemoteBranches := ['main'];
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('main'));
  Assert.AreEqual('origin', mFacts.Remote);
  Assert.IsTrue(mFacts.RemoteMain);
  Assert.AreEqual(2, Integer(Length(mFake.Calls)), 'kein resolve für origin');
  // Remote mit unsicherem Namen (z. B. "." für einen lokalen Upstream): origin.
  mFake.MainRemote := '.';
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('main'));
  Assert.AreEqual('origin', mFacts.Remote);
  // SVN kennt kein Remote.
  Assert.AreEqual('', SvnFacts('').Remote);
  mFake.Calls := nil;
  mFake.Refs := nil;
  mBases := nil;
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasVcsBranchPlanTests.DefaultRequestWithGitOptions;
var
  mFacts: TAtlasVcsBranchFacts;
  mRequest: TAtlasVcsBranchRequest;
  mBase: TAtlasVcsBranchBase;
begin
  mFacts := GitFacts(True, True, 'feature/12-x');
  mFacts.Remote := 'origin';
  mFacts.Root := RepoRoot;
  // remote: origin/main mit Abruf.
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'feature/13-y', '', 'ATL-13',
    GitOptions(TAtlasVcsGitBaseOption.Remote, False, TAtlasVcsGitUncommitted.Carry, False), mRequest));
  Assert.IsTrue(mRequest.Base.Kind = TAtlasVcsBranchBaseKind.RemoteMain);
  Assert.IsTrue(mRequest.Fetch);
  Assert.IsFalse(mRequest.PushNow);
  Assert.IsFalse(mRequest.Stash);
  Assert.AreEqual('', mRequest.WorktreeFolder);
  // remote ohne origin/main: lokaler Hauptbranch, ohne Abruf.
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(GitFacts(True, False, 'x'), 'feature/13-y', '', '',
    GitOptions(TAtlasVcsGitBaseOption.Remote, False, TAtlasVcsGitUncommitted.Carry, False), mRequest));
  Assert.IsTrue(mRequest.Base.Kind = TAtlasVcsBranchBaseKind.LocalMain);
  Assert.IsFalse(mRequest.Fetch);
  // local: wie vor #1289, mit push und stash.
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'feature/13-y', '', '',
    GitOptions(TAtlasVcsGitBaseOption.Local, True, TAtlasVcsGitUncommitted.Stash, False), mRequest));
  Assert.IsTrue(mRequest.Base.Kind = TAtlasVcsBranchBaseKind.LocalMain);
  Assert.IsFalse(mRequest.Fetch);
  Assert.IsTrue(mRequest.PushNow);
  Assert.IsTrue(mRequest.Stash);
  // ask entscheidet der Aufrufer: kein stash.
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'feature/13-y', '', '',
    GitOptions(TAtlasVcsGitBaseOption.Local, False, TAtlasVcsGitUncommitted.Ask, False), mRequest));
  Assert.IsFalse(mRequest.Stash);
  // current: der aktuelle Branch; auf main der lokale Hauptbranch.
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'feature/13-y', '', '',
    GitOptions(TAtlasVcsGitBaseOption.Current, False, TAtlasVcsGitUncommitted.Carry, False), mRequest));
  Assert.IsTrue(mRequest.Base.Kind = TAtlasVcsBranchBaseKind.Current);
  Assert.AreEqual('feature/12-x', mRequest.Base.Name);
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultBase(GitFacts(True, True, 'main'),
    GitOptions(TAtlasVcsGitBaseOption.Current, False, TAtlasVcsGitUncommitted.Carry, False), mBase));
  Assert.IsTrue(mBase.Kind = TAtlasVcsBranchBaseKind.LocalMain);
  // current geht auch ohne Hauptbranch (ausdrücklich gewählt); local und remote nicht.
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultBase(GitFacts(False, False, 'feature/12-x'),
    GitOptions(TAtlasVcsGitBaseOption.Current, False, TAtlasVcsGitUncommitted.Carry, False), mBase));
  Assert.IsFalse(TAtlasVcsBranchPlan.DefaultBase(GitFacts(False, False, 'feature/12-x'),
    GitOptions(TAtlasVcsGitBaseOption.Remote, False, TAtlasVcsGitUncommitted.Carry, False), mBase));
  // worktree: Ordner neben der Arbeitskopie, kein stash (die Arbeitskopie bleibt unberührt).
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'feature/13-y', '', 'ATL-13',
    GitOptions(TAtlasVcsGitBaseOption.Local, False, TAtlasVcsGitUncommitted.Stash, True), mRequest));
  Assert.AreEqual(RepoParent + PathDelim + 'Kasse-ATL-13', mRequest.WorktreeFolder);
  Assert.IsFalse(mRequest.Stash);
  // SVN: Git-Optionen ohne Wirkung.
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(SvnFacts('48230'), 'ATL-1-a', '', 'ATL-1',
    GitOptions(TAtlasVcsGitBaseOption.Remote, True, TAtlasVcsGitUncommitted.Stash, True), mRequest));
  Assert.IsTrue(mRequest.Base.Kind = TAtlasVcsBranchBaseKind.Head);
  Assert.IsFalse(mRequest.Fetch);
  Assert.IsFalse(mRequest.PushNow);
  Assert.AreEqual('', mRequest.WorktreeFolder);
  mFacts := TAtlasVcsBranchFacts.Empty;
  mRequest := Default(TAtlasVcsBranchRequest);
  mBase := Default(TAtlasVcsBranchBase);
end;

procedure TAtlasVcsBranchPlanTests.StepsGitOptions;
var
  mRequest: TAtlasVcsBranchRequest;
  mSteps: TArray<TAtlasVcsBranchStep>;
  mFolder: string;
begin
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/13-y',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.RemoteMain, 'main', '', 'origin'), '');
  mRequest.Fetch := True;
  mRequest.Stash := True;
  mRequest.PushNow := True;
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  Assert.AreEqual(4, Integer(Length(mSteps)));
  Assert.AreEqual('fetch --quiet --no-tags origin main', Args(mSteps[0]));
  Assert.IsTrue(mSteps[0].Remote, 'Abruf ohne Rückfrage');
  Assert.IsFalse(mSteps[0].ChangesServer);
  Assert.AreEqual('stash push --include-untracked --quiet -m Atlas: vor feature/13-y', Args(mSteps[1]));
  Assert.IsFalse(mSteps[1].Remote);
  Assert.AreEqual('checkout --quiet --no-track -b feature/13-y refs/remotes/origin/main --', Args(mSteps[2]));
  Assert.AreEqual('push --set-upstream origin refs/heads/feature/13-y:refs/heads/feature/13-y', Args(mSteps[3]));
  Assert.IsTrue(mSteps[3].Remote);
  Assert.IsTrue(mSteps[3].ChangesServer, 'push ändert den Server');
  Assert.AreEqual('git stash push --include-untracked --quiet -m "Atlas: vor feature/13-y"',
    TAtlasVcsBranchPlan.StepText(TAtlasVcsKind.Git, mSteps[1]));
  // Abruf nur mit Basis vom Server.
  mRequest.Base := TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.LocalMain, 'main', '', 'origin');
  mRequest.Stash := False;
  mRequest.PushNow := False;
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  Assert.AreEqual(1, Integer(Length(mSteps)));
  Assert.AreEqual('checkout', mSteps[0].Arguments[0]);
  // worktree: eigener Ordner statt checkout, kein stash; Push an den Remote der Basis.
  mFolder := RepoParent + PathDelim + 'Kasse ATL-13';
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/13-y',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.RemoteMain, 'main', '', 'upstream'), '');
  mRequest.Fetch := True;
  mRequest.Stash := True;
  mRequest.PushNow := True;
  mRequest.WorktreeFolder := mFolder;
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  Assert.AreEqual(3, Integer(Length(mSteps)));
  Assert.AreEqual('fetch --quiet --no-tags upstream main', Args(mSteps[0]));
  Assert.AreEqual('worktree add --quiet --no-track -b feature/13-y ' + mFolder + ' refs/remotes/upstream/main',
    Args(mSteps[1]));
  Assert.AreEqual(mFolder, mSteps[1].Arguments[6], 'Ordner mit Leerzeichen als ein Argument');
  Assert.AreEqual('push --set-upstream upstream refs/heads/feature/13-y:refs/heads/feature/13-y', Args(mSteps[2]));
  // Ordner nicht vollständig, mit „-“ oder Steuerzeichen: keine Schritte.
  mRequest.WorktreeFolder := '..' + PathDelim + 'Kasse-13';
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))));
  mRequest.WorktreeFolder := '-f';
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))));
  mRequest.WorktreeFolder := mFolder + #10;
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))));
  // Remote wie eine Option: keine Schritte.
  mRequest.WorktreeFolder := '';
  mRequest.Base.Remote := '--upload-pack=x';
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))));
  mRequest := Default(TAtlasVcsBranchRequest);
  mSteps := nil;
end;

procedure TAtlasVcsBranchPlanTests.WorktreePathAndProject;
var
  mRoot, mParent: string;
begin
  mRoot := RepoRoot;
  mParent := RepoParent;
  Assert.AreEqual(mParent + PathDelim + 'Kasse-ATL-13', TAtlasVcsBranchPlan.WorktreePath(mRoot, '', 'feature/13',
    'ATL-13'), 'Vorgabe ..\{repo}-{kennung}');
  Assert.AreEqual(mParent + PathDelim + 'Kasse-ATL-13', TAtlasVcsBranchPlan.WorktreePath(mRoot + PathDelim,
    '..\{repo}-{kennung}', 'x', 'ATL-13'), 'Trenner am Ende der Wurzel');
  // {name}: Trenner werden „-“, damit kein Unterordner entsteht; ohne Issue steht der Name für {kennung}.
  Assert.AreEqual(mParent + PathDelim + 'wt' + PathDelim + 'feature-13-y', TAtlasVcsBranchPlan.WorktreePath(mRoot,
    '../wt/{name}', 'feature/13-y', ''));
  Assert.AreEqual(mParent + PathDelim + 'Kasse-feature-13-y', TAtlasVcsBranchPlan.WorktreePath(mRoot, '',
    'feature/13-y', ''));
  // Unter Windows verbotene Zeichen der Kennung.
  Assert.AreEqual(mParent + PathDelim + 'Kasse-#753', TAtlasVcsBranchPlan.WorktreePath(mRoot, '', 'x', '#753'));
  Assert.AreEqual(mParent + PathDelim + 'Kasse-A-B', TAtlasVcsBranchPlan.WorktreePath(mRoot, '', 'x', 'A:B'));
  // Unterordner der Arbeitskopie und vollständiger Ordner.
  Assert.AreEqual(mRoot + PathDelim + 'wt', TAtlasVcsBranchPlan.WorktreePath(mRoot, 'wt', 'x', ''));
  Assert.AreEqual(mParent + PathDelim + 'Fest', TAtlasVcsBranchPlan.WorktreePath(mRoot, mParent + PathDelim + 'Fest',
    'x', ''));
  Assert.AreEqual('', TAtlasVcsBranchPlan.WorktreePath('', '', 'x', 'ATL-1'), 'ohne Wurzel');
  Assert.IsTrue(TAtlasVcsBranchPlan.SafeFolder(mParent + PathDelim + 'Kasse-ATL-13'));
  Assert.IsFalse(TAtlasVcsBranchPlan.SafeFolder(''));
  Assert.IsFalse(TAtlasVcsBranchPlan.SafeFolder('Kasse-ATL-13'), 'relativ');
  Assert.IsFalse(TAtlasVcsBranchPlan.SafeFolder(' ' + mParent), 'Leerraum am Rand');
  // Projekt bzw. Gruppe im neuen Ordner; außerhalb der Wurzel keins.
  Assert.AreEqual(mParent + PathDelim + 'Kasse-ATL-13' + PathDelim + 'src' + PathDelim + 'Kasse.dproj',
    TAtlasVcsBranchPlan.ProjectInFolder(mRoot + PathDelim + 'src' + PathDelim + 'Kasse.dproj', mRoot,
    mParent + PathDelim + 'Kasse-ATL-13'));
  Assert.AreEqual('', TAtlasVcsBranchPlan.ProjectInFolder(mParent + PathDelim + 'Libs' + PathDelim + 'L.dproj',
    mRoot, mParent + PathDelim + 'Kasse-ATL-13'));
  Assert.AreEqual('', TAtlasVcsBranchPlan.ProjectInFolder(mParent + PathDelim + 'Kasse2' + PathDelim + 'K.dproj',
    mRoot, mParent + PathDelim + 'Kasse-ATL-13'), 'nur echte Unterordner');
  Assert.AreEqual('Atlas: vor feature/13-y', TAtlasVcsBranchPlan.StashMessage('feature/13-y'));
end;

procedure TAtlasVcsBranchPlanTests.FetchFallbackAndPushFailure;
var
  mFake: TPlanVcs;
  mBranching: IAtlasVcsBranching;
  mFacts: TAtlasVcsBranchFacts;
  mRequest, mFallback: TAtlasVcsBranchRequest;
  mSteps: TArray<TAtlasVcsBranchStep>;
  mRun: TAtlasVcsBranchRun;
begin
  mFake := TPlanVcs.Create(TAtlasVcsKind.Git);
  mBranching := mFake;
  mFacts := GitFacts(True, True, 'feature/12-x');
  mFacts.Remote := 'origin';
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'feature/13-y', '', '',
    GitOptions(TAtlasVcsGitBaseOption.Remote, True, TAtlasVcsGitUncommitted.Stash, False), mRequest));
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  Assert.AreEqual(4, Integer(Length(mSteps)));
  // Abruf ohne Anmeldung: nichts weiter, nichts geändert.
  mFake.FailOn := 'fetch';
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, mSteps);
  Assert.IsTrue(mRun.Outcome = TAtlasVcsOutcome.LoginNeeded);
  Assert.AreEqual(0, mRun.Failed);
  Assert.AreEqual(1, Integer(Length(mFake.Calls)));
  Assert.IsTrue(TAtlasVcsBranchPlan.FetchFailed(mSteps, mRun));
  Assert.IsFalse(TAtlasVcsBranchPlan.OnlyPushFailed(mSteps, mRun));
  // Rückfall: lokaler Hauptbranch ohne Abruf, die übrigen Optionen bleiben.
  mFallback := TAtlasVcsBranchPlan.LocalFallback(mFacts, mRequest);
  Assert.IsFalse(mFallback.Fetch);
  Assert.IsTrue(mFallback.Base.Kind = TAtlasVcsBranchBaseKind.LocalMain);
  Assert.IsTrue(mFallback.PushNow);
  Assert.IsTrue(mFallback.Stash);
  Assert.AreEqual('stash', TAtlasVcsBranchPlan.Steps(mFallback)[0].Arguments[0]);
  // Ohne lokalen Hauptbranch: der zuletzt abgerufene Stand.
  mFallback := TAtlasVcsBranchPlan.LocalFallback(GitFacts(False, True, 'x'), mRequest);
  Assert.IsTrue(mFallback.Base.Kind = TAtlasVcsBranchBaseKind.RemoteMain);
  Assert.IsFalse(mFallback.Fetch);
  // Nur der Push scheitert: der Branch ist angelegt.
  mFake.FailOn := 'push';
  mFake.Calls := nil;
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, mSteps);
  Assert.IsFalse(mRun.Succeeded);
  Assert.AreEqual(3, mRun.Done);
  Assert.IsTrue(TAtlasVcsBranchPlan.OnlyPushFailed(mSteps, mRun));
  Assert.IsFalse(TAtlasVcsBranchPlan.FetchFailed(mSteps, mRun));
  // checkout scheitert: weder das eine noch das andere.
  mFake.FailOn := 'checkout';
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, mSteps);
  Assert.IsFalse(TAtlasVcsBranchPlan.OnlyPushFailed(mSteps, mRun));
  Assert.IsFalse(TAtlasVcsBranchPlan.FetchFailed(mSteps, mRun));
  mFake.Calls := nil;
  mSteps := nil;
  mFacts := TAtlasVcsBranchFacts.Empty;
  mRequest := Default(TAtlasVcsBranchRequest);
  mFallback := Default(TAtlasVcsBranchRequest);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsBranchPlanTests);

end.
