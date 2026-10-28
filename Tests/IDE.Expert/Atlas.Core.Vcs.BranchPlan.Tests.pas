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
    /// <summary>#1290: Projektwurzel aus dem Pfad der Arbeitskopie, Hauptbranch darunter, höchste Revision einer
    /// gemischten Arbeitskopie aus svnversion; ohne svnversion die Revision aus Head.</summary>
    [Test]
    procedure InspectSvnLayoutAndMixedRevision;
    /// <summary>#1290: Ort, Danach (switch, checkout mit Ordner, none) und langes Zeitlimit; ohne Ort bzw. Ordner
    /// keine Schritte.</summary>
    [Test]
    procedure StepsSvnWithOptions;
    /// <summary>#1290: Vorgabe-Anfrage mit Quelle, Ort und Ordner aus den Optionen; ohne Layout False.</summary>
    [Test]
    procedure DefaultRequestSvnWithOptions;
    /// <summary>#1290: Gruppe an derselben Stelle im neuen Ordner; außerhalb der Arbeitskopie ''.</summary>
    [Test]
    procedure CheckoutTargetMapsGroup;
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
  TPlanVcs = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsBranching, IAtlasVcsSvnWorkingCopy)
  public
    /// <summary>Ausgabe von svnversion (#1290); Outcome ungleich Ok = nicht verfügbar.</summary>
    SvnVersion: string;
    SvnVersionOutcome: TAtlasVcsOutcome;
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
    { IAtlasVcsSvnWorkingCopy }
    function WorkingRevisions(out AText: string): TAtlasVcsOutcome;
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
  SvnVersionOutcome := TAtlasVcsOutcome.ToolMissing;
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

function TPlanVcs.BranchExists(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions;
  out AExists: Boolean): TAtlasVcsOutcome;
begin
  Result := BranchExists(AName, AExists);
end;

function TPlanVcs.SwitchBranch(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions): TAtlasVcsOutcome;
begin
  Result := SwitchBranch(AName);
end;

function TPlanVcs.WorkingRevisions(out AText: string): TAtlasVcsOutcome;
begin
  Calls := Calls + ['svnversion'];
  AText := SvnVersion;
  Result := SvnVersionOutcome;
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
  // #1290: "trunk" liegt unter der Projektwurzel ^/Kasse.
  Assert.AreEqual('Kasse/trunk', mFacts.MainBranch);
  Assert.IsTrue(mFacts.Externals);
  Assert.AreEqual('', mFacts.HeadRevision);
  Assert.IsTrue(mFacts.NeedsServer, 'HEAD-Revision fehlt noch');
  Assert.AreEqual(1, Integer(Length(mFake.Calls)), 'Inspect fragt den Server nicht');
  Assert.AreEqual('svnversion', mFake.Calls[0], 'ohne Server');
  TAtlasVcsBranchPlan.InspectServer(mVcs, mFacts);
  Assert.IsFalse(mFacts.NeedsServer);
  Assert.IsTrue(mFacts.ServerChecked);
  Assert.IsTrue(mFacts.ServerOutcome = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('48230', mFacts.HeadRevision);
  Assert.AreEqual('revision Kasse/trunk', mFake.Calls[1]);
  // Ohne Anmeldung: Ergebnis festhalten, Revision bleibt unbekannt.
  mFake.RepoPath := '';
  mFake.ServerOutcome := TAtlasVcsOutcome.LoginNeeded;
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('trunk'));
  Assert.AreEqual('trunk', mFacts.Current, 'ohne Pfad der aus Head');
  Assert.AreEqual('trunk', mFacts.MainBranch, 'ohne Pfad kein Layout');
  Assert.IsFalse(mFacts.LayoutKnown);
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

procedure TAtlasVcsBranchPlanTests.InspectSvnLayoutAndMixedRevision;
var
  mFake: TPlanVcs;
  mVcs: IAtlasVersionControl;
  mFacts: TAtlasVcsBranchFacts;
begin
  mFake := TPlanVcs.Create(TAtlasVcsKind.Svn);
  mVcs := mFake;
  mFake.HeadBranch := 'trunk';
  mFake.HeadRevision := '48190';
  mFake.RepoPath := 'Kasse/trunk';
  mFake.SvnVersion := '48190:48213M';
  mFake.SvnVersionOutcome := TAtlasVcsOutcome.Ok;
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('trunk'));
  Assert.IsTrue(mFacts.LayoutKnown);
  Assert.AreEqual('Kasse', mFacts.ProjectRoot);
  Assert.AreEqual('Kasse/trunk', mFacts.MainBranch);
  Assert.AreEqual('48213', mFacts.Revision, 'die höchste');
  Assert.IsTrue(mFacts.MixedRevision);
  Assert.AreEqual('C:\Repo', mFacts.Root);
  // Ein Hauptbranch mit ^/ gilt wie angegeben.
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('^/Basis/trunk'));
  Assert.AreEqual('Basis/trunk', mFacts.MainBranch);
  // Einheitliche Revision.
  mFake.SvnVersion := '48213';
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('trunk'));
  Assert.AreEqual('48213', mFacts.Revision);
  Assert.IsFalse(mFacts.MixedRevision);
  // Ohne svnversion bzw. unlesbar: die Revision aus Head, keine Warnung.
  mFake.SvnVersionOutcome := TAtlasVcsOutcome.ToolMissing;
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('trunk'));
  Assert.AreEqual('48190', mFacts.Revision);
  Assert.IsFalse(mFacts.MixedRevision);
  mFake.SvnVersionOutcome := TAtlasVcsOutcome.Ok;
  mFake.SvnVersion := 'Unversioned directory';
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('trunk'));
  Assert.AreEqual('48190', mFacts.Revision);
  // Standardlayout: Projektwurzel ist die Wurzel des Repositorys.
  mFake.RepoPath := 'trunk';
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('trunk'));
  Assert.IsTrue(mFacts.LayoutKnown);
  Assert.AreEqual('', mFacts.ProjectRoot);
  Assert.AreEqual('trunk', mFacts.MainBranch);
  mFake.Calls := nil;
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasVcsBranchPlanTests.StepsSvnWithOptions;
var
  mFacts: TAtlasVcsBranchFacts;
  mOptions: TAtlasVcsSvnBranchOptions;
  mRequest: TAtlasVcsBranchRequest;
  mSteps: TArray<TAtlasVcsBranchStep>;
begin
  mFacts := SvnFacts('48230');
  mFacts.LayoutKnown := True;
  mFacts.ProjectRoot := 'Kasse';
  mFacts.MainBranch := 'Kasse/trunk';
  mFacts.Root := 'C:\Projekte\Kasse';
  mOptions := TAtlasVcsSvnBranchOptions.Default;
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Svn, 'KASSE-42-bon',
    Base(TAtlasVcsBranchBaseKind.Head, 'Kasse/trunk', '48230'), 'KASSE-42 Branch');
  Assert.AreEqual('branches/KASSE-42-bon', mRequest.Location, 'Make wie vor #1290');
  Assert.IsTrue(TAtlasVcsBranchPlan.ApplySvn(mRequest, mFacts, mOptions));
  Assert.AreEqual('Kasse/branches/KASSE-42-bon', mRequest.Location);
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  Assert.AreEqual(2, Integer(Length(mSteps)));
  Assert.AreEqual('copy ^/Kasse/trunk@48230 ^/Kasse/branches/KASSE-42-bon@ --parents -m KASSE-42 Branch',
    string.Join(' ', mSteps[0].Arguments));
  Assert.IsFalse(mSteps[0].Long);
  Assert.AreEqual('switch ^/Kasse/branches/KASSE-42-bon@ .', string.Join(' ', mSteps[1].Arguments));
  Assert.IsTrue(mSteps[1].Long, 'switch holt die ganze Arbeitskopie');
  // Frisch auschecken in den Ordner aus dem Muster.
  mOptions.After := TAtlasVcsSvnAfter.Checkout;
  mOptions.Key := 'KASSE-42';
  Assert.IsTrue(TAtlasVcsBranchPlan.ApplySvn(mRequest, mFacts, mOptions));
  Assert.AreEqual(ExpandFileName('C:\Projekte\Kasse\..\Kasse-KASSE-42'), mRequest.CheckoutFolder);
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  Assert.AreEqual(2, Integer(Length(mSteps)));
  Assert.AreEqual('checkout', mSteps[1].Arguments[0]);
  Assert.AreEqual('^/Kasse/branches/KASSE-42-bon@', mSteps[1].Arguments[1]);
  Assert.AreEqual(mRequest.CheckoutFolder, mSteps[1].Arguments[2]);
  Assert.IsTrue(mSteps[1].Remote);
  Assert.IsFalse(mSteps[1].ChangesServer);
  Assert.IsTrue(mSteps[1].Long);
  mRequest.CheckoutFolder := '';
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))), 'auschecken ohne Ordner');
  mRequest.CheckoutFolder := '-x';
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))), 'Ordner wie eine Option');
  // Nur anlegen.
  mOptions.After := TAtlasVcsSvnAfter.None;
  TAtlasVcsBranchPlan.ApplySvn(mRequest, mFacts, mOptions);
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  Assert.AreEqual(1, Integer(Length(mSteps)));
  Assert.AreEqual('copy', mSteps[0].Arguments[0]);
  // Ohne Layout: kein Ort, keine Schritte.
  mFacts.LayoutKnown := False;
  Assert.IsFalse(TAtlasVcsBranchPlan.ApplySvn(mRequest, mFacts, mOptions));
  Assert.AreEqual('', mRequest.Location);
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))));
  // Ort mit „..“: keine Schritte.
  mRequest.Location := 'Kasse/../trunk';
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))));
  // Git: ApplySvn ändert nichts.
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/1-x',
    Base(TAtlasVcsBranchBaseKind.LocalMain, 'main', ''), '');
  Assert.IsTrue(TAtlasVcsBranchPlan.ApplySvn(mRequest, mFacts, mOptions));
  Assert.IsTrue(mRequest.After = TAtlasVcsSvnAfter.Switch);
  mSteps := nil;
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasVcsBranchPlanTests.DefaultRequestSvnWithOptions;
var
  mFacts: TAtlasVcsBranchFacts;
  mOptions: TAtlasVcsSvnBranchOptions;
  mRequest: TAtlasVcsBranchRequest;
  mBase: TAtlasVcsBranchBase;
begin
  mFacts := SvnFacts('48230');
  mFacts.LayoutKnown := True;
  mFacts.ProjectRoot := 'Kasse';
  mFacts.MainBranch := 'Kasse/trunk';
  mOptions := TAtlasVcsSvnBranchOptions.Default;
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'KASSE-42-bon', 'm', mOptions, mRequest));
  Assert.IsTrue(mRequest.Base.Kind = TAtlasVcsBranchBaseKind.Head);
  Assert.AreEqual('Kasse/branches/KASSE-42-bon', mRequest.Location);
  Assert.IsTrue(mRequest.After = TAtlasVcsSvnAfter.Switch);
  // Quelle Arbeitskopie: genau der Stand, den man gerade übersetzt.
  mOptions.Source := TAtlasVcsSvnSource.WorkingCopy;
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'KASSE-42-bon', 'm', mOptions, mRequest));
  Assert.IsTrue(mRequest.Base.Kind = TAtlasVcsBranchBaseKind.WorkingCopy);
  Assert.AreEqual('Kasse/trunk@48100', TAtlasVcsBranchPlan.BaseName(TAtlasVcsKind.Svn, mRequest.Base));
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultBase(mFacts, TAtlasVcsSvnSource.WorkingCopy, mBase));
  Assert.IsTrue(mBase.Kind = TAtlasVcsBranchBaseKind.WorkingCopy);
  // Git ignoriert die SVN-Quelle.
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultBase(GitFacts(True, True, 'x'), TAtlasVcsSvnSource.WorkingCopy, mBase));
  Assert.IsTrue(mBase.Kind = TAtlasVcsBranchBaseKind.LocalMain);
  // Ohne Layout: keine Vorgabe-Anfrage (Beginnen ohne Dialog scheitert, statt an der Wurzel anzulegen).
  mFacts.LayoutKnown := False;
  Assert.IsFalse(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'KASSE-42-bon', 'm', mOptions, mRequest));
  // Mit festem Ort wie vor #1290 geht es auch ohne Layout.
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'KASSE-42-bon', 'm', TAtlasVcsSvnBranchOptions.Legacy,
    mRequest));
  Assert.AreEqual('branches/KASSE-42-bon', mRequest.Location);
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasVcsBranchPlanTests.CheckoutTargetMapsGroup;
var
  mRoot: string;
begin
  if PathDelim = '\' then
    mRoot := 'C:\Projekte\Kasse'
  else
    mRoot := '/projekte/kasse';
  Assert.AreEqual(ExtractFilePath(mRoot) + 'Kasse-KASSE-42' + PathDelim + 'Gruppe' + PathDelim + 'Kasse.groupproj',
    TAtlasVcsBranchPlan.CheckoutTarget(mRoot, ExtractFilePath(mRoot) + 'Kasse-KASSE-42',
    mRoot + PathDelim + 'Gruppe' + PathDelim + 'Kasse.groupproj'));
  Assert.AreEqual('', TAtlasVcsBranchPlan.CheckoutTarget(mRoot, ExtractFilePath(mRoot) + 'x',
    ExtractFilePath(mRoot) + 'Anderes' + PathDelim + 'a.groupproj'), 'außerhalb der Arbeitskopie');
  Assert.AreEqual('', TAtlasVcsBranchPlan.CheckoutTarget(mRoot, '', mRoot + PathDelim + 'a.groupproj'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsBranchPlanTests);

end.
