unit Atlas.Core.Vcs.BranchPlan.Tests;

// Plan für „Branch anlegen“ (#1288) ohne Prozesse: Inspect und InspectServer
// über eine Versionsverwaltung im Speicher, Basen und Vorgabe unter Git und
// SVN, die Schritte (genau die Befehlszeilen aus dem Dialog), Anzeige mit
// Anführungszeichen, Ausführung bis zum ersten Fehler mit Fortschritt und die
// Serverschritte, die danach stehen bleiben.

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

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsBranchPlanTests);

end.
