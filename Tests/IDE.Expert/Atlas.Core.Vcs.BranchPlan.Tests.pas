unit Atlas.Core.Vcs.BranchPlan.Tests;

// Plan für „Branch anlegen“ (#1288) ohne Prozesse: Inspect und InspectServer
// über eine Versionsverwaltung im Speicher, Basen und Vorgabe unter Git und
// SVN, die Schritte (genau die Befehlszeilen aus dem Dialog), Anzeige mit
// Anführungszeichen, Ausführung bis zum ersten Fehler mit Fortschritt und die
// Serverschritte, die danach stehen bleiben. Externals (#1291): Inspect liest
// sie samt Zustand, Schritte in der Reihenfolge Packages, Projekt,
// Umschreiben, Umschalten; --pin-externals ab svn 1.9; Arbeitsordner.
// Git-Optionen (#1289): Vorgaben aus den Einstellungen, Basis vom Server mit
// Abruf, stash, worktree-Ordner mit Platzhaltern, Push, Reihenfolge der
// Schritte, Rückfall nach gescheitertem Abruf und Push, der allein scheitert.

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
    /// <summary>#1291: Externals mit Quelle, Revision und lokalen Änderungen der External-Arbeitskopie,
    /// Version von svn, Wurzel des Repositorys.</summary>
    [Test]
    procedure InspectReadsExternals;
    /// <summary>#1291: alle festschreiben mit --pin-externals (ab 1.9), sonst Umschreiben im Branch; mitverzweigen
    /// zuerst, Reihenfolge Packages, Projekt, Umschreiben, Umschalten; ungültige Wahl ohne Schritte.</summary>
    [Test]
    procedure StepsSvnWithExternals;
    /// <summary>#1291: Vorgaben je External, Ask ohne Dialog keine Anfrage, Orte der Packages, Index neu nach
    /// dem Umschalten, Arbeitsordner vor und nach dem Ausführen gelöscht.</summary>
    [Test]
    procedure ExternalsDefaultsAndExecute;
    /// <summary>#1291: vcs.externals.rules zwischen JSON, Text der Einstellungsseite und Regeln.</summary>
    [Test]
    procedure ExternalRulesRoundTrip;
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
  System.IOUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Internals.SvnExternals,
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
    /// <summary>#1291: Ausgabe von propget --xml (ExternalsOutcome ungleich Ok = keine), Wurzel des Repositorys,
    /// Version von svn und svnversion je Ordner ("Packages/Basis=48190M").</summary>
    ExternalsText: string;
    ExternalsOutcome: TAtlasVcsOutcome;
    RepositoryUrl: string;
    Version: string;
    FolderVersions: TArray<string>;
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
    function WorkingRevisions(out AText: string): TAtlasVcsOutcome; overload;
    function WorkingRevisions(const AFolder: string; out AText: string): TAtlasVcsOutcome; overload;
    function ExternalsXml(out AText: string): TAtlasVcsOutcome;
    function RepositoryRoot(out AUrl: string): TAtlasVcsOutcome;
    function ToolVersion(out AVersion: string): TAtlasVcsOutcome;
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
  SvnVersionOutcome := TAtlasVcsOutcome.ToolMissing;
  ExternalsOutcome := TAtlasVcsOutcome.Failed;
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

function TPlanVcs.WorkingRevisions(const AFolder: string; out AText: string): TAtlasVcsOutcome;
var
  mEntry: string;
begin
  Calls := Calls + ['svnversion ' + AFolder];
  AText := '';
  Result := TAtlasVcsOutcome.Failed;
  for mEntry in FolderVersions do
    if mEntry.StartsWith(AFolder + '=') then
    begin
      AText := Copy(mEntry, Length(AFolder) + 2, MaxInt);
      Result := TAtlasVcsOutcome.Ok;
    end;
end;

function TPlanVcs.ExternalsXml(out AText: string): TAtlasVcsOutcome;
begin
  AText := ExternalsText;
  Result := ExternalsOutcome;
end;

function TPlanVcs.RepositoryRoot(out AUrl: string): TAtlasVcsOutcome;
begin
  AUrl := RepositoryUrl;
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlanVcs.ToolVersion(out AVersion: string): TAtlasVcsOutcome;
begin
  AVersion := Version;
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

const
  cRepository = 'https://svn.firma.local/repo';
  /// <summary>Drei Externals: ohne Revision, mit Revision, aus fremdem Repository.</summary>
  cExternals = '# Packages'#10'^/Packages/Basis/trunk Packages/Basis'#10 +
    '-r 4711 ^/Packages/Kunden/trunk Packages/Kunden'#10'https://svn.lieferant.de/k/trunk Lieferant'#10;

/// <summary>SVN-Fakten mit Layout ^/Kasse und den Externals aus cExternals samt Revisionen der Arbeitskopie.
/// </summary>
function ExternalFacts: TAtlasVcsBranchFacts;
begin
  Result := SvnFacts('48230');
  Result.LayoutKnown := True;
  Result.ProjectRoot := 'Kasse';
  Result.MainBranch := 'Kasse/trunk';
  Result.Root := 'C:\Projekte\Kasse';
  Result.RepositoryRoot := cRepository;
  Result.SvnVersion := '1.14.3';
  Result.SvnDefinitions := [TAtlasVcsSvnExternalDefinition.Make('', cExternals)];
  Result.SvnExternals := TAtlasSvnExternals.ParseAll(Result.SvnDefinitions, cRepository + '/Kasse/trunk',
    cRepository);
  Result.SvnExternals[0].WorkingRevision := '48190';
  Result.SvnExternals[1].WorkingRevision := '4711';
  Result.SvnExternals[2].WorkingRevision := '17';
  Result.Externals := True;
end;

function ExternalRequest(const AFacts: TAtlasVcsBranchFacts;
  const AActions: TArray<TAtlasVcsExternalAction>): TAtlasVcsBranchRequest;
var
  mOptions: TAtlasVcsSvnBranchOptions;
begin
  mOptions := TAtlasVcsSvnBranchOptions.Default;
  mOptions.Key := 'KASSE-42';
  Result := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Svn, 'KASSE-42-bon',
    Base(TAtlasVcsBranchBaseKind.Head, 'Kasse/trunk', '48230'), 'KASSE-42 Branch');
  TAtlasVcsBranchPlan.ApplySvn(Result, AFacts, mOptions);
  TAtlasVcsBranchPlan.ApplyExternals(Result, AFacts, mOptions, AActions);
end;

function Line(const ASteps: TArray<TAtlasVcsBranchStep>; AIndex: Integer): string;
begin
  Result := string.Join(' ', ASteps[AIndex].Arguments);
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

procedure TAtlasVcsBranchPlanTests.InspectReadsExternals;
var
  mFake: TPlanVcs;
  mVcs: IAtlasVersionControl;
  mFacts: TAtlasVcsBranchFacts;
begin
  mFake := TPlanVcs.Create(TAtlasVcsKind.Svn);
  mVcs := mFake;
  mFake.HeadBranch := 'trunk';
  mFake.HeadRevision := '48213';
  mFake.RepoPath := 'Kasse/trunk';
  mFake.RepositoryUrl := cRepository;
  mFake.Version := '1.14.3';
  mFake.ExternalsOutcome := TAtlasVcsOutcome.Ok;
  mFake.ExternalsText := '<?xml version="1.0"?><properties><target path="."><property name="svn:externals">' +
    StringReplace(cExternals, '&', '&amp;', [rfReplaceAll]) + '</property></target></properties>';
  mFake.FolderVersions := TArray<string>.Create('Packages/Basis=48190M', 'Packages/Kunden=4711');
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('trunk'));
  Assert.IsTrue(mFacts.Externals);
  Assert.AreEqual(cRepository, mFacts.RepositoryRoot);
  Assert.AreEqual('1.14.3', mFacts.SvnVersion);
  Assert.AreEqual(1, Integer(Length(mFacts.SvnDefinitions)));
  Assert.AreEqual(3, Integer(Length(mFacts.SvnExternals)));
  Assert.AreEqual('Packages/Basis/trunk', mFacts.SvnExternals[0].Source);
  Assert.AreEqual('48190', mFacts.SvnExternals[0].WorkingRevision);
  Assert.IsTrue(mFacts.SvnExternals[0].Modified, 'svnversion „M“');
  Assert.IsFalse(mFacts.SvnExternals[1].Modified);
  Assert.AreEqual('', mFacts.SvnExternals[2].WorkingRevision, 'svnversion scheitert: unbekannt');
  Assert.IsTrue(mFacts.SvnExternals[2].Foreign);
  Assert.IsFalse(mFacts.SvnExternals[0].IsFile, 'Ordner gibt es hier nicht: kein Datei-External');
  Assert.IsTrue(TPlanVcs.Has(mFake.Calls, 'svnversion Packages/Basis'));
  // Ohne lesbare Externals: wie vor #1291 der Hinweis aus HasExternals.
  mFake.ExternalsOutcome := TAtlasVcsOutcome.Failed;
  mFake.Externals := True;
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('trunk'));
  Assert.IsTrue(mFacts.Externals);
  Assert.AreEqual(0, Integer(Length(mFacts.SvnExternals)));
  mFake.ExternalsOutcome := TAtlasVcsOutcome.Ok;
  mFake.ExternalsText := '<properties><target';
  mFacts := TAtlasVcsBranchPlan.Inspect(mVcs, TArray<string>.Create('trunk'));
  Assert.IsTrue(mFacts.Outcome = TAtlasVcsOutcome.Ok, 'kaputtes XML hält das Anlegen nicht auf');
  mFake.Calls := nil;
  mFake.FolderVersions := nil;
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasVcsBranchPlanTests.StepsSvnWithExternals;
var
  mFacts: TAtlasVcsBranchFacts;
  mRequest: TAtlasVcsBranchRequest;
  mSteps: TArray<TAtlasVcsBranchStep>;
  mDir: string;
begin
  mFacts := ExternalFacts;
  // Alle ohne Revision festschreiben, svn 1.14: --pin-externals, kein Umschreiben.
  mRequest := ExternalRequest(mFacts, [TAtlasVcsExternalAction.Pin, TAtlasVcsExternalAction.Keep,
    TAtlasVcsExternalAction.Pin]);
  Assert.IsTrue(TAtlasVcsBranchPlan.UsesPinExternals(mRequest));
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  Assert.AreEqual(2, Integer(Length(mSteps)));
  Assert.AreEqual('copy ^/Kasse/trunk@48230 ^/Kasse/branches/KASSE-42-bon@ --parents -m KASSE-42 Branch ' +
    '--pin-externals', Line(mSteps, 0));
  Assert.AreEqual('switch', mSteps[1].Arguments[0]);
  // svn 1.8: Atlas schreibt im Branch selbst fest, mit der Revision der External-Arbeitskopie.
  mFacts.SvnVersion := '1.8.19';
  mRequest := ExternalRequest(mFacts, [TAtlasVcsExternalAction.Pin, TAtlasVcsExternalAction.Keep,
    TAtlasVcsExternalAction.Pin]);
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  Assert.AreEqual(5, Integer(Length(mSteps)));
  Assert.AreEqual('copy ^/Kasse/trunk@48230 ^/Kasse/branches/KASSE-42-bon@ --parents -m KASSE-42 Branch',
    Line(mSteps, 0));
  mDir := TPath.Combine(mRequest.WorkFolder, 'p0');
  Assert.AreEqual('checkout ^/Kasse/branches/KASSE-42-bon@ ' + mDir + ' --depth empty', Line(mSteps, 1));
  Assert.IsTrue(mSteps[1].Remote);
  Assert.IsFalse(mSteps[1].ChangesServer);
  Assert.AreEqual('propset svn:externals -F ' + mDir + '.txt ' + mDir, Line(mSteps, 2));
  Assert.AreEqual(mDir + '.txt', mSteps[2].InputFile);
  Assert.AreEqual('# Packages'#10'-r 48190 ^/Packages/Basis/trunk Packages/Basis'#10 +
    '-r 4711 ^/Packages/Kunden/trunk Packages/Kunden'#10'-r 17 https://svn.lieferant.de/k/trunk Lieferant'#10,
    mSteps[2].InputText, 'nur die festzuschreibenden Zeilen geändert');
  Assert.AreEqual('svn:externals: Packages/Basis -r 48190, Lieferant -r 17', mSteps[2].Note);
  Assert.IsFalse(mSteps[2].Remote);
  Assert.AreEqual('commit ' + mDir + ' -m KASSE-42 Branch', Line(mSteps, 3));
  Assert.IsTrue(mSteps[3].ChangesServer);
  Assert.AreEqual('switch', mSteps[4].Arguments[0]);
  Assert.Contains(TAtlasVcsBranchPlan.StepText(TAtlasVcsKind.Svn, mSteps[2]), '(svn:externals: Packages/Basis');
  // Mitverzweigen: Package zuerst, dann Projekt, dann Umschreiben, dann umschalten.
  mFacts.SvnVersion := '1.14.3';
  mRequest := ExternalRequest(mFacts, [TAtlasVcsExternalAction.Branch, TAtlasVcsExternalAction.Keep,
    TAtlasVcsExternalAction.Pin]);
  Assert.IsFalse(TAtlasVcsBranchPlan.UsesPinExternals(mRequest), 'Umschreiben nötig: selbst festschreiben');
  Assert.AreEqual('Packages/Basis/branches/KASSE-42-bon', mRequest.ExternalLocations[0]);
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  Assert.AreEqual(6, Integer(Length(mSteps)));
  Assert.AreEqual('copy ^/Packages/Basis/trunk@48190 ^/Packages/Basis/branches/KASSE-42-bon@ --parents -m ' +
    'KASSE-42 Branch', Line(mSteps, 0));
  Assert.IsTrue(mSteps[0].ChangesServer);
  Assert.AreEqual('^/Kasse/trunk@48230', mSteps[1].Arguments[1]);
  Assert.AreEqual('checkout', mSteps[2].Arguments[0]);
  Assert.AreEqual('# Packages'#10'^/Packages/Basis/branches/KASSE-42-bon Packages/Basis'#10 +
    '-r 4711 ^/Packages/Kunden/trunk Packages/Kunden'#10'-r 17 https://svn.lieferant.de/k/trunk Lieferant'#10,
    mSteps[3].InputText);
  Assert.AreEqual('svn:externals: Packages/Basis → ^/Packages/Basis/branches/KASSE-42-bon, Lieferant -r 17',
    mSteps[3].Note);
  Assert.AreEqual('commit', mSteps[4].Arguments[0]);
  Assert.AreEqual('switch', mSteps[5].Arguments[0]);
  Assert.AreEqual(3, Integer(Length(TAtlasVcsBranchPlan.ServerStepsDone(mSteps, 6))),
    'zwei Kopien und der Commit bleiben nach einem Fehler');
  // Nur lassen: wie vor #1291.
  mRequest := ExternalRequest(mFacts, [TAtlasVcsExternalAction.Keep, TAtlasVcsExternalAction.Keep,
    TAtlasVcsExternalAction.Keep]);
  Assert.AreEqual(2, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))));
  Assert.AreEqual(6, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest)[0].Arguments)), 'ohne --pin-externals');
  // Ungültige Wahl: keine Schritte.
  mRequest := ExternalRequest(mFacts, [TAtlasVcsExternalAction.Ask, TAtlasVcsExternalAction.Keep,
    TAtlasVcsExternalAction.Keep]);
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))), 'noch nicht gewählt');
  mRequest := ExternalRequest(mFacts, [TAtlasVcsExternalAction.Keep, TAtlasVcsExternalAction.Keep,
    TAtlasVcsExternalAction.Branch]);
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))), 'fremdes Repository mitverzweigen');
  mRequest := ExternalRequest(mFacts, [TAtlasVcsExternalAction.Keep, TAtlasVcsExternalAction.Pin,
    TAtlasVcsExternalAction.Keep]);
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))), 'feste Revision festschreiben');
  mFacts.SvnVersion := '1.8.0';
  mRequest := ExternalRequest(mFacts, [TAtlasVcsExternalAction.Pin, TAtlasVcsExternalAction.Keep,
    TAtlasVcsExternalAction.Keep]);
  mRequest.WorkFolder := '';
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.Steps(mRequest))), 'Umschreiben ohne Arbeitsordner');
  mRequest := Default(TAtlasVcsBranchRequest);
  mSteps := nil;
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasVcsBranchPlanTests.ExternalsDefaultsAndExecute;
var
  mFacts: TAtlasVcsBranchFacts;
  mOptions: TAtlasVcsSvnBranchOptions;
  mRequest: TAtlasVcsBranchRequest;
  mActions: TArray<TAtlasVcsExternalAction>;
  mFake: TPlanVcs;
  mBranching: IAtlasVcsBranching;
  mRun: TAtlasVcsBranchRun;
  mPath: string;
begin
  mFacts := ExternalFacts;
  mOptions := TAtlasVcsSvnBranchOptions.Default;
  mActions := TAtlasVcsBranchPlan.DefaultActions(mFacts, mOptions);
  Assert.AreEqual(3, Integer(Length(mActions)));
  Assert.IsTrue(mActions[0] = TAtlasVcsExternalAction.Pin);
  Assert.IsTrue(mActions[1] = TAtlasVcsExternalAction.Keep, 'mit Revision');
  Assert.IsTrue(mActions[2] = TAtlasVcsExternalAction.Pin);
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'KASSE-42-bon', 'm', mOptions, mRequest));
  Assert.AreEqual(3, Integer(Length(mRequest.ExternalActions)));
  Assert.IsTrue(TAtlasVcsBranchPlan.ChangesExternals(mRequest), 'festschreiben und umschalten');
  // ask: ohne Dialog keine Vorgabe-Anfrage.
  mOptions.ExternalsOnBranch := TAtlasVcsExternalAction.Ask;
  Assert.IsFalse(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'KASSE-42-bon', 'm', mOptions, mRequest));
  // Wie vor #1291: nichts zu ändern, kein neuer Index.
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'KASSE-42-bon', 'm', TAtlasVcsSvnBranchOptions.Legacy,
    mRequest));
  Assert.IsFalse(TAtlasVcsBranchPlan.ChangesExternals(mRequest));
  // Ort eines Packages: unter dessen Projektwurzel, auch bei festem Ort des Projekts.
  Assert.IsTrue(TAtlasVcsBranchPlan.ExternalLocation(mFacts.SvnExternals[0], TAtlasVcsSvnBranchOptions.Legacy,
    'KASSE-42-bon', mPath));
  Assert.AreEqual('Packages/Basis/branches/KASSE-42-bon', mPath);
  Assert.IsFalse(TAtlasVcsBranchPlan.ExternalLocation(mFacts.SvnExternals[2], mOptions, 'x', mPath), 'fremd');
  Assert.AreEqual('r4711', 'r' + TAtlasVcsBranchPlan.ExternalRevision(mFacts.SvnExternals[1]));
  Assert.AreEqual('48190', TAtlasVcsBranchPlan.ExternalRevision(mFacts.SvnExternals[0]));
  // Ausführen: Arbeitsordner (Rest eines abgebrochenen Laufs) vorher und nachher weg.
  mFacts.SvnVersion := '1.8.0';
  mRequest := ExternalRequest(mFacts, [TAtlasVcsExternalAction.Pin, TAtlasVcsExternalAction.Keep,
    TAtlasVcsExternalAction.Keep]);
  TDirectory.CreateDirectory(TPath.Combine(mRequest.WorkFolder, 'p0'));
  mFake := TPlanVcs.Create(TAtlasVcsKind.Svn);
  mBranching := mFake;
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, mRequest, TAtlasVcsBranchPlan.Steps(mRequest), nil);
  Assert.IsTrue(mRun.Succeeded);
  Assert.AreEqual(5, Integer(Length(mFake.Calls)));
  Assert.IsFalse(TDirectory.Exists(mRequest.WorkFolder));
  Assert.Contains(mRequest.WorkFolder, 'Atlas-Branch-KASSE-42-bon');
  mFake.Calls := nil;
  mActions := nil;
  mRequest := Default(TAtlasVcsBranchRequest);
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasVcsBranchPlanTests.ExternalRulesRoundTrip;
var
  mRules: TArray<TAtlasVcsExternalRule>;
  mInvalid: string;
begin
  mRules := TAtlasVcsBranchPlan.RulesOf('[{"source": "^/Packages/Basis", "onBranch": "keep"}, ' +
    '{"source": "", "onBranch": "pin"}, {"source": "^/Libs", "onBranch": "ask"}, ' +
    '{"source": "^/packages/basis", "onBranch": "branch"}, {"source": "https://svn.x/Libs", "onBranch": "BRANCH"}]');
  Assert.AreEqual(2, Integer(Length(mRules)), 'ohne Quelle, ask und doppelte Quelle fallen weg');
  Assert.AreEqual('^/Packages/Basis', mRules[0].Source);
  Assert.IsTrue(mRules[0].Action = TAtlasVcsExternalAction.Keep);
  Assert.IsTrue(mRules[1].Action = TAtlasVcsExternalAction.Branch);
  Assert.AreEqual('[{"source": "^/Packages/Basis", "onBranch": "keep"}, ' +
    '{"source": "https://svn.x/Libs", "onBranch": "branch"}]', TAtlasVcsBranchPlan.RulesJson(mRules));
  Assert.AreEqual('^/Packages/Basis = keep' + sLineBreak + 'https://svn.x/Libs = branch',
    TAtlasVcsBranchPlan.RulesText(mRules));
  Assert.AreEqual(0, Integer(Length(TAtlasVcsBranchPlan.RulesOf('kaputt'))));
  Assert.AreEqual('[]', TAtlasVcsBranchPlan.RulesJson(nil));
  Assert.IsTrue(TAtlasVcsBranchPlan.RulesOfText('# Kommentar'#13#10'^/Packages/Basis = keep'#13#10#13#10 +
    '  ^/Libs=pin '#10'^/packages/basis = branch', mRules, mInvalid));
  Assert.AreEqual(2, Integer(Length(mRules)));
  Assert.IsTrue(mRules[0].Action = TAtlasVcsExternalAction.Branch, 'letzte Zeile gewinnt');
  Assert.AreEqual('^/Libs', mRules[1].Source);
  Assert.IsTrue(mRules[1].Action = TAtlasVcsExternalAction.Pin);
  Assert.AreEqual('', mInvalid);
  Assert.IsFalse(TAtlasVcsBranchPlan.RulesOfText('^/a = keep'#13#10'^/b = fragen', mRules, mInvalid));
  Assert.AreEqual('^/b = fragen', mInvalid);
  Assert.AreEqual(0, Integer(Length(mRules)));
  Assert.IsFalse(TAtlasVcsBranchPlan.RulesOfText('= keep', mRules, mInvalid));
  Assert.IsFalse(TAtlasVcsBranchPlan.RulesOfText('^/a keep', mRules, mInvalid));
  Assert.IsTrue(TAtlasVcsBranchPlan.RulesOfText('', mRules, mInvalid));
  Assert.AreEqual(0, Integer(Length(mRules)));
  mRules := nil;
  mInvalid := '';
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
  // SVN: Git-Optionen ohne Wirkung (Layout bekannt, sonst fehlt das Ziel der Vorgabe {root}/branches/…).
  mFacts := SvnFacts('48230');
  mFacts.LayoutKnown := True;
  mFacts.ProjectRoot := 'Kasse';
  Assert.IsTrue(TAtlasVcsBranchPlan.DefaultRequest(mFacts, 'ATL-1-a', '', 'ATL-1',
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
