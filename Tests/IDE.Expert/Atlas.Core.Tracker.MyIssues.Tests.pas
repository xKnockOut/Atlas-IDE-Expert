unit Atlas.Core.Tracker.MyIssues.Tests;

// Tests des Bereichs „Meine Issues“ ohne IDE und Netz (#765): Ziel aus .atlas
// und Einstellungen, Abstand der Abfragen, letzter Stand ohne Netz, aktives
// Issue (gemerkt, Branch → Ticket, beendet), Plan für „Beginnen“ unter Git,
// SVN und ohne Versionsverwaltung, Commit-Präfix und der Abschnitt "issues"
// der Projekt-Zusammenfassung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasMyIssuesTests = class
  public
    [Test]
    procedure TargetFromTeamFileAndSettings;
    /// <summary>Abfrage höchstens alle 10 Minuten; anderes Ziel sofort; ohne Tracker nie.</summary>
    [Test]
    procedure DueEveryTenMinutes;
    /// <summary>Abnahme: ohne Netz der letzte Stand („Stand vom …“), kein Fehler.</summary>
    [Test]
    procedure FailedFetchKeepsLastState;
    [Test]
    procedure ViewStatus;
    [Test]
    procedure ActiveIssueFromStartAndBranch;
    [Test]
    procedure EndedIssueStaysOff;
    /// <summary>Abnahme: Git feature/753-atlas-bereiche-und von main (sonst master).</summary>
    [Test]
    procedure PlanStartGit;
    /// <summary>Abnahme: SVN ^/branches/ATL-123-… von trunk.</summary>
    [Test]
    procedure PlanStartSvnAndRemember;
    /// <summary>Abnahme: start=remember, die nächste Commit-Nachricht beginnt mit „ATL-123 “; leeres Muster aus.
    /// </summary>
    [Test]
    procedure CommitPrefixOfActiveIssue;
    [Test]
    procedure FieldsOfGitHubAndYouTrack;
    [Test]
    procedure SectionRoundTripKeepsOtherFields;
    /// <summary>„Beginnen“: anlegen von main, sonst master; vorhandenen Branch auschecken; Fehler.</summary>
    [Test]
    procedure ExecuteGit;
    /// <summary>Werte aus dem Dialog „Branch anlegen“ (#1288): Name und Basis genau so, Fortschritt je Schritt.
    /// </summary>
    [Test]
    procedure ExecuteWithDialogRequest;
    /// <summary>Git-Optionen (#1289): scheitert nur der Push, gilt der Branch als angelegt; belegter
    /// worktree-Ordner legt nichts an; im worktree Ordner und Wurzel im Ergebnis.</summary>
    [Test]
    procedure ExecuteWithGitOptions;
    /// <summary>SVN: copy und switch aus dem Plan; scheitert switch, steht die Kopie als Serverschritt da.</summary>
    [Test]
    procedure ExecuteSvnAndRemember;
    /// <summary>#1290: In ^/Kasse/trunk legt „Beginnen“ unter ^/Kasse/branches an (Hauptbranch Kasse/trunk,
    /// Nachricht aus dem Muster), findet den Branch danach dort und schaltet nur um; mit after = none bleibt die
    /// Arbeitskopie, mit checkout liefert das Ergebnis Ordner und Wurzel; ohne Layout scheitert es ohne
    /// Serverschritt.</summary>
    [Test]
    procedure ExecuteSvnUnderProjectRoot;
    /// <summary>Rückfrage nur bei Änderungen an versionierten Dateien.</summary>
    [Test]
    procedure VcsKindFromText;
    /// <summary>„Alle Tracker-Projekte“ (#1928): je Gruppe höchstens PerGroup Zeilen, Kopf mit Trefferzahl und
    /// Zustand; GroupOf findet die Gruppe einer Zeile auch hinter einer leeren Gruppe.</summary>
    [Test]
    procedure GroupsLimitRowsPerProject;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.BranchPlan,
  Atlas.Core.VersionControl.Internals.SvnLayout,
  Atlas.Core.Tracker.MyIssues;

var
  /// <summary>Aufrufe von CountingProgress.</summary>
  ProgressCalls: Integer;

/// <summary>Fortschritt, der nur zählt; in eigener Routine gebaut.</summary>
function CountingProgress: TAtlasVcsBranchProgress;
begin
  Result :=
    procedure(AIndex, ACount: Integer; const AStep: TAtlasVcsBranchStep)
    begin
      Inc(ProgressCalls);
    end;
end;

type
  /// <summary>Versionsverwaltung mit Branches im Speicher.</summary>
  TFakeBranchingVcs = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsBranching)
  public
    VcsKind: TAtlasVcsKind;
    Branches: TArray<string>;
    /// <summary>Lokale Branches, die als Basis taugen (main, master, trunk).</summary>
    Bases: TArray<string>;
    /// <summary>Git: Branches auf origin im lokalen Stand (#1288).</summary>
    RemoteBases: TArray<string>;
    Calls: TArray<string>;
    Current: string;
    ExistsOutcome: TAtlasVcsOutcome;
    /// <summary>Schritt mit diesem Befehl (z. B. "switch") scheitert (#1288).</summary>
    FailOn: string;
    /// <summary>SVN (#1290): Pfad der Arbeitskopie für RepositoryPath ('' = Current); die Überladungen mit Optionen
    /// suchen dann am aufgelösten Ort unter Branches, copy trägt das Ziel dort ein.</summary>
    SvnUrl: string;
    constructor Create(AKind: TAtlasVcsKind);
    function Has(const AList: TArray<string>; const AName: string): Boolean;
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
  end;

constructor TFakeBranchingVcs.Create(AKind: TAtlasVcsKind);
begin
  inherited Create;
  VcsKind := AKind;
  ExistsOutcome := TAtlasVcsOutcome.Ok;
end;

function TFakeBranchingVcs.Has(const AList: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in AList do
  begin
    if mName = AName then
    begin
      Exit(True);
    end;
  end;
end;

function TFakeBranchingVcs.Kind: TAtlasVcsKind;
begin
  Result := VcsKind;
end;

function TFakeBranchingVcs.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result := TAtlasVcsWorkingCopy.Empty;
  Result.Kind := VcsKind;
  Result.Root := 'C:\Repo';
end;

function TFakeBranchingVcs.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  AHead := TAtlasVcsHead.Empty;
  AHead.Branch := Current;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeBranchingVcs.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeBranchingVcs.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeBranchingVcs.Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeBranchingVcs.ChangeMarker: string;
begin
  Result := '';
end;

function TFakeBranchingVcs.BranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  Calls := Calls + ['exists ' + AName];
  AExists := Has(Branches, AName) or Has(Bases, AName);
  Result := ExistsOutcome;
end;

function TFakeBranchingVcs.BranchExists(const AName: string; const AOptions: TAtlasVcsSvnBranchOptions;
  out AExists: Boolean): TAtlasVcsOutcome;
var
  mPath: string;
begin
  if (VcsKind <> TAtlasVcsKind.Svn) or (SvnUrl = '') then
  begin
    Exit(BranchExists(AName, AExists));
  end;
  AExists := False;
  if not TAtlasSvnLayout.Resolve(AOptions, SvnUrl, AName, mPath) then
  begin
    Calls := Calls + ['exists ?'];
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Calls := Calls + ['exists ^/' + mPath];
  AExists := Has(Branches, mPath);
  Result := ExistsOutcome;
end;

function TFakeBranchingVcs.SwitchBranch(const AName: string;
  const AOptions: TAtlasVcsSvnBranchOptions): TAtlasVcsOutcome;
var
  mPath: string;
begin
  if (VcsKind <> TAtlasVcsKind.Svn) or (SvnUrl = '') then
  begin
    Exit(SwitchBranch(AName));
  end;
  if not TAtlasSvnLayout.Resolve(AOptions, SvnUrl, AName, mPath) then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  Calls := Calls + ['switch ^/' + mPath];
  Current := mPath;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeBranchingVcs.RemoteBranchExists(const AName: string; out AExists: Boolean): TAtlasVcsOutcome;
begin
  Calls := Calls + ['remote ' + AName];
  AExists := Has(RemoteBases, AName);
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeBranchingVcs.ServerRevision(const APath: string; out ARevision: string): TAtlasVcsOutcome;
begin
  ARevision := '48230';
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeBranchingVcs.HasExternals(out AHas: Boolean): TAtlasVcsOutcome;
begin
  AHas := False;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeBranchingVcs.RepositoryPath(out APath: string): TAtlasVcsOutcome;
begin
  APath := Current;
  if SvnUrl <> '' then
  begin
    APath := SvnUrl;
  end;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeBranchingVcs.RunStep(const AStep: TAtlasVcsBranchStep): TAtlasVcsOutcome;
var
  mArgs: TArray<string>;
  mName: string;
begin
  mArgs := AStep.Arguments;
  Calls := Calls + ['run ' + string.Join(' ', mArgs)];
  if mArgs[0] = FailOn then
  begin
    Exit(TAtlasVcsOutcome.Failed);
  end;
  // Git: checkout --quiet --no-track -b <Name> <Start> --; SVN checkout <Ort> <Ordner> (#1290) ändert hier nichts.
  if (mArgs[0] = 'checkout') and (SvnUrl = '') and (Length(mArgs) > 4) then
  begin
    mName := mArgs[4];
    Branches := Branches + [mName];
    Current := mName;
  end
  else if (mArgs[0] = 'switch') and (SvnUrl <> '') then
  begin
    // copy ^/<Ort>@: voller Ort ohne ^/ und @ (#1290).
    Current := Copy(mArgs[1], 3, Length(mArgs[1]) - 3);
  end
  else if mArgs[0] = 'switch' then
  begin
    mName := Copy(mArgs[1], Length('^/branches/') + 1, Length(mArgs[1]) - Length('^/branches/') - 1);
    Current := mName;
  end
  else if (mArgs[0] = 'copy') and (SvnUrl <> '') then
  begin
    Branches := Branches + [Copy(mArgs[2], 3, Length(mArgs[2]) - 3)];
  end;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeBranchingVcs.SwitchBranch(const AName: string): TAtlasVcsOutcome;
begin
  Calls := Calls + ['switch ' + AName];
  Current := AName;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeBranchingVcs.HookFolders(out AHooks, AGitDir: string): TAtlasVcsOutcome;
begin
  AHooks := '';
  AGitDir := '';
  if VcsKind <> TAtlasVcsKind.Git then
  begin
    Exit(TAtlasVcsOutcome.Ok);
  end;
  AHooks := 'C:\Repo\.git\hooks';
  AGitDir := 'C:\Repo\.git';
  Result := TAtlasVcsOutcome.Ok;
end;

function Now0: TDateTime;
begin
  Result := EncodeDateTime(2026, 10, 16, 9, 0, 0, 0);
end;

function Issue(const AKey: string; ANumber: Integer; const ATitle: string): TAtlasTrackerIssue;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := AKey;
  Result.Number := ANumber;
  Result.Title := ATitle;
end;

function GitHub: TAtlasTrackerTarget;
begin
  Result := TAtlasMyIssues.TargetFor('github', 'https://github.com', 'beispiel/atlas', '', '');
end;

function YouTrack: TAtlasTrackerTarget;
begin
  Result := TAtlasMyIssues.TargetFor('youtrack', 'https://beispiel.youtrack.cloud', 'ATL', '', '');
end;

{ TAtlasMyIssuesTests }

procedure TAtlasMyIssuesTests.TargetFromTeamFileAndSettings;
var
  mTarget: TAtlasTrackerTarget;
begin
  mTarget := TAtlasMyIssues.TargetFor('youtrack', 'https://yt.firma.de', 'ATL', '', 'for: me');
  Assert.AreEqual('youtrack', mTarget.Provider);
  Assert.AreEqual('for: me', mTarget.Query);
  Assert.IsTrue(mTarget.Configured);
  // Einstellung ersetzt den Anbieter aus .atlas.
  mTarget := TAtlasMyIssues.TargetFor('youtrack', 'https://github.com', 'beispiel/atlas', 'GitHub', '');
  Assert.AreEqual('github', mTarget.Provider);
  Assert.IsTrue(mTarget.Configured);
  // Unbekannter Anbieter: nicht eingerichtet.
  Assert.IsFalse(TAtlasMyIssues.TargetFor('jira', 'https://jira.firma.de', 'ATL', '', '').Configured);
  Assert.IsFalse(TAtlasMyIssues.TargetFor('', '', '', '', '').Configured);
end;

procedure TAtlasMyIssuesTests.DueEveryTenMinutes;
var
  mState: TAtlasIssuesState;
begin
  mState := TAtlasIssuesState.Empty;
  Assert.IsTrue(TAtlasMyIssues.Due(mState, GitHub, Now0, False), 'noch nie');
  TAtlasMyIssues.Recorded(mState, GitHub, Now0, True, [Issue('#1', 1, 'a')], TAtlasCiFetchError.None);
  Assert.IsFalse(TAtlasMyIssues.Due(mState, GitHub, IncMinute(Now0, 9), False));
  Assert.IsTrue(TAtlasMyIssues.Due(mState, GitHub, IncMinute(Now0, 10), False));
  Assert.IsTrue(TAtlasMyIssues.Due(mState, GitHub, IncMinute(Now0, 1), True), '„Jetzt abfragen“');
  Assert.IsTrue(TAtlasMyIssues.Due(mState, YouTrack, IncMinute(Now0, 1), False), 'anderes Ziel');
  Assert.IsTrue(TAtlasMyIssues.Due(mState, GitHub, IncMinute(Now0, -5), False), 'Uhr zurückgestellt');
  Assert.IsFalse(TAtlasMyIssues.Due(mState, TAtlasMyIssues.TargetFor('', '', '', '', ''), Now0, True),
    'ohne Tracker kein Netzzugriff');
end;

procedure TAtlasMyIssuesTests.FailedFetchKeepsLastState;
var
  mState: TAtlasIssuesState;
begin
  mState := TAtlasIssuesState.Empty;
  TAtlasMyIssues.Recorded(mState, GitHub, Now0, True, [Issue('#1', 1, 'a'), Issue('#2', 2, 'b')],
    TAtlasCiFetchError.None);
  TAtlasMyIssues.Recorded(mState, GitHub, IncMinute(Now0, 20), False, nil, TAtlasCiFetchError.Network);
  Assert.AreEqual(2, Integer(Length(mState.Items)), 'letzter Stand bleibt');
  Assert.IsTrue(SameDateTime(Now0, mState.At));
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.Network, mState.Error);
  Assert.IsTrue(SameDateTime(IncMinute(Now0, 20), mState.Attempt));
  // Anderes Ziel ohne Erfolg: der alte Stand gehört nicht dazu.
  TAtlasMyIssues.Recorded(mState, YouTrack, IncMinute(Now0, 21), False, nil, TAtlasCiFetchError.Timeout);
  Assert.AreEqual(0, Integer(Length(mState.Items)));
  Assert.AreEqual<TDateTime>(0, mState.At);
end;

procedure TAtlasMyIssuesTests.ViewStatus;
var
  mState: TAtlasIssuesState;
  mView: TAtlasIssuesView;
begin
  mState := TAtlasIssuesState.Empty;
  mView := TAtlasMyIssues.View(mState, TAtlasMyIssues.TargetFor('', '', '', '', ''), '');
  Assert.AreEqual<TAtlasIssuesStatus>(TAtlasIssuesStatus.NotConfigured, mView.Status);
  mView := TAtlasMyIssues.View(mState, GitHub, '');
  Assert.AreEqual<TAtlasIssuesStatus>(TAtlasIssuesStatus.Waiting, mView.Status);
  TAtlasMyIssues.Recorded(mState, GitHub, Now0, False, nil, TAtlasCiFetchError.Unauthorized);
  mView := TAtlasMyIssues.View(mState, GitHub, '');
  Assert.AreEqual<TAtlasIssuesStatus>(TAtlasIssuesStatus.Failed, mView.Status);
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.Unauthorized, mView.Error);
  TAtlasMyIssues.Recorded(mState, GitHub, Now0, True, [Issue('#1', 1, 'a')], TAtlasCiFetchError.None);
  mView := TAtlasMyIssues.View(mState, GitHub, '');
  Assert.AreEqual<TAtlasIssuesStatus>(TAtlasIssuesStatus.Ready, mView.Status);
  Assert.AreEqual(1, Integer(Length(mView.Items)));
  TAtlasMyIssues.Recorded(mState, GitHub, IncHour(Now0, 1), False, nil, TAtlasCiFetchError.Network);
  mView := TAtlasMyIssues.View(mState, GitHub, '');
  Assert.AreEqual<TAtlasIssuesStatus>(TAtlasIssuesStatus.Stale, mView.Status, '„Stand vom …“');
  Assert.IsTrue(SameDateTime(Now0, mView.At));
  Assert.AreEqual(1, Integer(Length(mView.Items)));
end;

procedure TAtlasMyIssuesTests.ActiveIssueFromStartAndBranch;
var
  mState: TAtlasIssuesState;
  mActive: TAtlasActiveIssue;
begin
  mState := TAtlasIssuesState.Empty;
  TAtlasMyIssues.Recorded(mState, GitHub, Now0, True, [Issue('#753', 753, 'Atlas-Bereiche')],
    TAtlasCiFetchError.None);
  // Branch → Ticket, Titel aus der Liste.
  mActive := TAtlasMyIssues.Effective(mState, 'github', 'beispiel/atlas', 'feature/753-atlas-bereiche-und');
  Assert.AreEqual('#753', mActive.Key);
  Assert.AreEqual('Atlas-Bereiche', mActive.Title);
  Assert.IsTrue(mActive.FromBranch);
  Assert.IsFalse(TAtlasMyIssues.Effective(mState, 'github', 'beispiel/atlas', 'main').Active);
  // Mit Branch begonnen: gilt nur auf diesem Branch.
  TAtlasMyIssues.Started(mState, Issue('#612', 612, 'Parser'), TAtlasIssueStart.Branch, 'feature/612-parser',
    Now0);
  Assert.AreEqual('#612', TAtlasMyIssues.Effective(mState, 'github', '', 'feature/612-parser').Key);
  Assert.AreEqual('#612', TAtlasMyIssues.Effective(mState, 'github', '', '').Key, 'Branch unbekannt');
  Assert.IsFalse(TAtlasMyIssues.Effective(mState, 'github', '', 'main').Active, 'anderer Branch');
  // Nur gemerkt: gilt auf jedem Branch.
  TAtlasMyIssues.Started(mState, Issue('ATL-123', 123, 'Tracker'), TAtlasIssueStart.Remember, 'trunk', Now0);
  mActive := TAtlasMyIssues.Effective(mState, 'youtrack', 'ATL', 'trunk');
  Assert.AreEqual('ATL-123', mActive.Key);
  Assert.AreEqual('', mActive.Branch);
  Assert.IsFalse(mActive.FromBranch);
end;

procedure TAtlasMyIssuesTests.EndedIssueStaysOff;
var
  mState: TAtlasIssuesState;
begin
  mState := TAtlasIssuesState.Empty;
  TAtlasMyIssues.Started(mState, Issue('#753', 753, 'x'), TAtlasIssueStart.Branch, 'feature/753-x', Now0);
  TAtlasMyIssues.Ended(mState, 'feature/753-x');
  Assert.IsFalse(TAtlasMyIssues.Effective(mState, 'github', '', 'feature/753-x').Active,
    'der Branch aktiviert es nicht wieder');
  Assert.AreEqual('#9', TAtlasMyIssues.Effective(mState, 'github', '', 'feature/9-y').Key);
  TAtlasMyIssues.Started(mState, Issue('#753', 753, 'x'), TAtlasIssueStart.Branch, 'feature/753-x', Now0);
  Assert.AreEqual('', mState.EndedBranch, 'erneutes Beginnen hebt es auf');
end;

procedure TAtlasMyIssuesTests.PlanStartGit;
var
  mPlan: TAtlasIssueStartPlan;
  mOptions: TAtlasIssuesOptions;
begin
  mOptions := TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', '{kennung} ');
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, mOptions,
    Issue('#753', 753, 'Plugin: Atlas-Bereiche und Layouts der Willkommensseite'));
  Assert.IsTrue(mPlan.Valid);
  Assert.AreEqual<TAtlasIssueStart>(TAtlasIssueStart.Branch, mPlan.Mode);
  Assert.AreEqual('feature/753-atlas-bereiche-und', mPlan.Branch);
  Assert.AreEqual(2, Integer(Length(mPlan.Bases)));
  Assert.AreEqual('main', mPlan.Bases[0]);
  Assert.AreEqual('master', mPlan.Bases[1]);
  Assert.AreEqual('#753 ', mPlan.Prefix);
  mOptions := TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, 'bugfix/{nummer}', 'develop', '');
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, mOptions, Issue('#9', 9, 'x'));
  Assert.AreEqual('bugfix/9', mPlan.Branch);
  Assert.AreEqual(1, Integer(Length(mPlan.Bases)));
  Assert.AreEqual('develop', mPlan.Bases[0]);
  Assert.AreEqual('', mPlan.Prefix);
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch,
    '///', '', ''), Issue('#9', 9, 'x'));
  Assert.IsFalse(mPlan.Valid, 'kein gültiger Name');
  // #1286: Hauptbranch des Projekts statt raten; issues.branchBase bleibt vorrangig.
  mOptions := TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', '');
  mOptions.MainBranch := 'develop';
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, mOptions, Issue('#9', 9, 'x'));
  Assert.AreEqual(1, Integer(Length(mPlan.Bases)));
  Assert.AreEqual('develop', mPlan.Bases[0]);
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, mOptions, Issue('#9', 9, 'x'));
  Assert.AreEqual('develop', mPlan.Bases[0], 'auch unter SVN (^/develop)');
  mOptions.BranchBase := 'release';
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, mOptions, Issue('#9', 9, 'x'));
  Assert.AreEqual('release', mPlan.Bases[0]);
end;

procedure TAtlasMyIssuesTests.PlanStartSvnAndRemember;
var
  mPlan: TAtlasIssueStartPlan;
begin
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '',
    '', '{kennung} '), Issue('ATL-123', 123, 'Tracker im Plugin anbinden'));
  Assert.AreEqual('ATL-123-tracker-im-plugin', mPlan.Branch, 'unter ^/branches/');
  Assert.AreEqual('trunk', mPlan.Bases[0]);
  // #1290: Nachricht aus vcs.branch.svn.message (Vorgabe „{kennung} Branch für {titel}“), Optionen mit Kennung.
  Assert.AreEqual('ATL-123 Branch für Tracker im Plugin anbinden', mPlan.Message);
  Assert.AreEqual('ATL-123', mPlan.Svn.Key);
  Assert.AreEqual('{projektwurzel}/branches/{name}', mPlan.Svn.Location);
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, TAtlasIssuesOptions.Create(TAtlasIssueStart.Remember, '',
    '', '{kennung} '), Issue('ATL-123', 123, 'x'));
  Assert.AreEqual<TAtlasIssueStart>(TAtlasIssueStart.Remember, mPlan.Mode);
  Assert.AreEqual('', mPlan.Branch);
  Assert.AreEqual('ATL-123 ', mPlan.Prefix);
  // Ohne Versionsverwaltung: nur merken.
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.None, TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '',
    '', ''), Issue('ATL-1', 1, 'x'));
  Assert.AreEqual<TAtlasIssueStart>(TAtlasIssueStart.Remember, mPlan.Mode);
  Assert.IsTrue(mPlan.Valid);
end;

procedure TAtlasMyIssuesTests.CommitPrefixOfActiveIssue;
var
  mState: TAtlasIssuesState;
  mActive: TAtlasActiveIssue;
begin
  mState := TAtlasIssuesState.Empty;
  Assert.AreEqual('', TAtlasMyIssues.CommitPrefix(TAtlasMyIssues.Effective(mState, 'youtrack', 'ATL',
    'trunk'), '{kennung} '), 'ohne aktives Issue');
  TAtlasMyIssues.Started(mState, Issue('ATL-123', 123, 'Tracker'), TAtlasIssueStart.Remember, '', Now0);
  mActive := TAtlasMyIssues.Effective(mState, 'youtrack', 'ATL', 'trunk');
  Assert.AreEqual('ATL-123 ', TAtlasMyIssues.CommitPrefix(mActive, '{kennung} '));
  Assert.AreEqual('', TAtlasMyIssues.CommitPrefix(mActive, ''), 'leeres Muster: aus');
  Assert.AreEqual('[123] ', TAtlasMyIssues.CommitPrefix(mActive, '[{nummer}] '));
  Assert.AreEqual(753, TAtlasMyIssues.NumberOfKey('#753'));
  Assert.AreEqual(123, TAtlasMyIssues.NumberOfKey('ATL-123'));
  Assert.AreEqual(0, TAtlasMyIssues.NumberOfKey('ATL'));
  Assert.AreEqual(0, TAtlasMyIssues.NumberOfKey('x5'));
end;

procedure TAtlasMyIssuesTests.FieldsOfGitHubAndYouTrack;
var
  mValue: TAtlasTrackerIssue;
  mFields: TArray<string>;
begin
  mValue := Issue('#753', 753, 'x');
  mValue.Labels := ['plugin', 'willkommensseite'];
  mValue.State := 'open';
  mFields := TAtlasMyIssues.Fields(mValue);
  Assert.AreEqual(2, Integer(Length(mFields)), 'GitHub: nur Labels');
  Assert.AreEqual('plugin', mFields[0]);
  mValue := Issue('ATL-123', 123, 'x');
  mValue.State := 'In Progress';
  mValue.Priority := 'Major';
  mValue.Sprint := 'Sprint 42';
  mFields := TAtlasMyIssues.Fields(mValue);
  Assert.AreEqual(3, Integer(Length(mFields)));
  Assert.AreEqual('In Progress', mFields[0]);
  Assert.AreEqual('Major', mFields[1]);
  Assert.AreEqual('Sprint 42', mFields[2]);
end;

procedure TAtlasMyIssuesTests.SectionRoundTripKeepsOtherFields;
var
  mSummary, mLoaded: TAtlasProjectSummary;
  mState, mBack: TAtlasIssuesState;
  mItem: TAtlasTrackerIssue;
  mJson: string;
begin
  mSummary := TAtlasProjectSummary.Create('C:\Projekte\Demo.dproj');
  mSummary.LastOpened := Now0;
  mState := TAtlasIssuesState.Empty;
  mItem := Issue('#753', 753, 'Atlas-Bereiche');
  mItem.Labels := ['plugin'];
  mItem.PullRequest.Number := 760;
  mItem.PullRequest.Checks := TAtlasTrackerChecks.Failure;
  mItem.PullRequest.Draft := True;
  TAtlasMyIssues.Recorded(mState, GitHub, Now0, True, [mItem], TAtlasCiFetchError.None);
  TAtlasMyIssues.Recorded(mState, GitHub, IncMinute(Now0, 30), False, nil, TAtlasCiFetchError.Timeout);
  TAtlasMyIssues.Started(mState, mItem, TAtlasIssueStart.Branch, 'feature/753-atlas-bereiche', Now0);
  mState.Hook := TAtlasMyIssues.cHookYes;
  mState.GitDir := 'C:\Repo\.git';
  TAtlasMyIssues.Write(mSummary, mState);
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mLoaded));
  Assert.IsTrue(SameDateTime(Now0, mLoaded.LastOpened), 'übrige Felder bleiben');
  Assert.IsTrue(TAtlasMyIssues.Read(mLoaded, mBack));
  Assert.AreEqual('github', mBack.Provider);
  Assert.AreEqual('https://github.com', mBack.Server);
  Assert.AreEqual('beispiel/atlas', mBack.Project);
  Assert.AreEqual<TAtlasCiFetchError>(TAtlasCiFetchError.Timeout, mBack.Error);
  Assert.IsTrue(SameDateTime(Now0, mBack.At));
  Assert.AreEqual(1, Integer(Length(mBack.Items)));
  Assert.AreEqual('#753', mBack.Items[0].Key);
  Assert.AreEqual(753, mBack.Items[0].Number);
  Assert.AreEqual('plugin', mBack.Items[0].Labels[0]);
  Assert.AreEqual(760, mBack.Items[0].PullRequest.Number);
  Assert.AreEqual<TAtlasTrackerChecks>(TAtlasTrackerChecks.Failure, mBack.Items[0].PullRequest.Checks);
  Assert.IsTrue(mBack.Items[0].PullRequest.Draft);
  Assert.AreEqual('#753', mBack.Active.Key);
  Assert.AreEqual<TAtlasIssueStart>(TAtlasIssueStart.Branch, mBack.Active.Mode);
  Assert.AreEqual('feature/753-atlas-bereiche', mBack.Active.Branch);
  Assert.AreEqual('yes', mBack.Hook);
  Assert.AreEqual('C:\Repo\.git', mBack.GitDir);
  Assert.IsTrue(mBack.Matches(GitHub));
  // Ein zweites Schreiben ersetzt den Abschnitt.
  TAtlasMyIssues.Ended(mBack, 'feature/753-atlas-bereiche');
  TAtlasMyIssues.Write(mLoaded, mBack);
  Assert.IsTrue(TAtlasMyIssues.Read(mLoaded, mState));
  Assert.IsFalse(mState.Active.Active);
  Assert.AreEqual('feature/753-atlas-bereiche', mState.EndedBranch);
  Assert.IsFalse(TAtlasMyIssues.Read(TAtlasProjectSummary.Create('x'), mState), 'ohne Abschnitt');
  Assert.IsFalse(Pos('token', LowerCase(TAtlasMyIssues.ToJson(mBack))) > 0, 'nie Zugangsdaten');
end;

const
  cExecuteGitcName = 'feature/753-atlas-bereiche-und';

/// <summary>Nur auf origin, keine Basis, Zeitüberschreitung bei der Prüfung.</summary>
procedure AssertGitBaseFromOrigin(const AFake: TFakeBranchingVcs; const AVcs: IAtlasVersionControl;
  const APlan: TAtlasIssueStartPlan);
var
  mStarted: TAtlasIssueStartResult;
begin
  // Nur auf origin: von origin/main.
  AFake.Branches := nil;
  AFake.Bases := nil;
  AFake.RemoteBases := ['main'];
  AFake.Calls := nil;
  mStarted := TAtlasMyIssues.Execute(AVcs, APlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Started, mStarted.Outcome);
  Assert.AreEqual('origin/main', mStarted.Base);
  Assert.AreEqual('run checkout --quiet --no-track -b ' + cExecuteGitcName + ' refs/remotes/origin/main --',
    AFake.Calls[High(AFake.Calls)]);
  // Keine Basis vorhanden: Fehler, nichts ausgecheckt (nie stillschweigend vom aktuellen Branch).
  AFake.Branches := nil;
  AFake.RemoteBases := nil;
  AFake.Current := 'main';
  mStarted := TAtlasMyIssues.Execute(AVcs, APlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Failed, mStarted.Outcome);
  Assert.IsFalse(mStarted.Succeeded);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mStarted.Reason);
  Assert.AreEqual('main', AFake.Current);
  // Zeitüberschreitung bei der Prüfung: kein Anlegen.
  AFake.ExistsOutcome := TAtlasVcsOutcome.TimedOut;
  AFake.Bases := ['main'];
  AFake.Calls := nil;
  mStarted := TAtlasMyIssues.Execute(AVcs, APlan);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.TimedOut, mStarted.Reason);
  Assert.AreEqual(1, Integer(Length(AFake.Calls)));
  AFake.ExistsOutcome := TAtlasVcsOutcome.Ok;
end;

/// <summary>Ungültiger Name aus dem Muster; danach den Fake leeren.</summary>
procedure AssertGitInvalidName(const AFake: TFakeBranchingVcs; const AVcs: IAtlasVersionControl);
var
  mPlan: TAtlasIssueStartPlan;
  mStarted: TAtlasIssueStartResult;
begin
  // Ungültiger Name aus dem Muster.
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git,
    TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '{kurztitel}', '', ''), Issue('#1', 1, '...'));
  mStarted := TAtlasMyIssues.Execute(AVcs, mPlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.InvalidName, mStarted.Outcome);
  AFake.Calls := nil;
  AFake.Branches := nil;
  AFake.Bases := nil;
  AFake.RemoteBases := nil;
  AFake.Current := '';
  mStarted := Default(TAtlasIssueStartResult);
end;

procedure TAtlasMyIssuesTests.ExecuteGit;
var
  mFake: TFakeBranchingVcs;
  mVcs: IAtlasVersionControl;
  mPlan: TAtlasIssueStartPlan;
  mStarted: TAtlasIssueStartResult;
  mOptions: TAtlasIssuesOptions;
begin
  mOptions := TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', '{kennung} ');
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, mOptions,
    Issue('#753', 753, 'Atlas-Bereiche und Layout'));
  // Ohne main: von master (Plan aus TAtlasVcsBranchPlan, #1288).
  mFake := TFakeBranchingVcs.Create(TAtlasVcsKind.Git);
  mVcs := mFake;
  mFake.Bases := ['master'];
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Started, mStarted.Outcome);
  Assert.IsTrue(mStarted.Succeeded);
  Assert.AreEqual(cExecuteGitcName, mStarted.Branch);
  Assert.AreEqual('master', mStarted.Base);
  Assert.AreEqual(cExecuteGitcName, mFake.Current);
  Assert.AreEqual('C:\Repo\.git', mStarted.GitDir);
  Assert.AreEqual('C:\Repo\.git\hooks', mStarted.Hooks);
  Assert.AreEqual(6, Integer(Length(mFake.Calls)));
  Assert.AreEqual('exists main', mFake.Calls[1]);
  Assert.AreEqual('remote master', mFake.Calls[4]);
  Assert.AreEqual('run checkout --quiet --no-track -b ' + cExecuteGitcName + ' refs/heads/master --', mFake.Calls[5]);
  Assert.AreEqual(1, Integer(Length(mStarted.Steps)));
  Assert.AreEqual(1, mStarted.Run.Done);
  // Gibt es den Branch schon: nur auschecken.
  mFake.Current := 'main';
  mFake.Calls := nil;
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Switched, mStarted.Outcome);
  Assert.AreEqual(2, Integer(Length(mFake.Calls)));
  Assert.AreEqual('switch ' + cExecuteGitcName, mFake.Calls[1]);
  AssertGitBaseFromOrigin(mFake, mVcs, mPlan);
  AssertGitInvalidName(mFake, mVcs);
end;

procedure TAtlasMyIssuesTests.ExecuteWithDialogRequest;
var
  mFake: TFakeBranchingVcs;
  mVcs: IAtlasVersionControl;
  mPlan: TAtlasIssueStartPlan;
  mStarted: TAtlasIssueStartResult;
  mRequest: TAtlasVcsBranchRequest;
begin
  mFake := TFakeBranchingVcs.Create(TAtlasVcsKind.Git);
  mVcs := mFake;
  mFake.Bases := ['main'];
  mFake.Current := 'feature/700-alt';
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git,
    TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', ''), Issue('#753', 753, 'Atlas-Bereiche'));
  // Im Dialog umbenannt und vom aktuellen Branch: genau diese Werte, ohne eigene Prüfung der Basen.
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/753-anders',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Current, 'feature/700-alt', ''), '');
  ProgressCalls := 0;
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan, mRequest, CountingProgress());
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Started, mStarted.Outcome);
  Assert.AreEqual('feature/753-anders', mStarted.Branch);
  Assert.AreEqual('feature/700-alt', mStarted.Base);
  Assert.AreEqual(2, Integer(Length(mFake.Calls)));
  Assert.AreEqual('exists feature/753-anders', mFake.Calls[0]);
  Assert.AreEqual('run checkout --quiet --no-track -b feature/753-anders refs/heads/feature/700-alt --',
    mFake.Calls[1]);
  Assert.AreEqual(1, ProgressCalls, 'Fortschritt je Schritt');
  // Ungültiger Name aus dem Dialog: nichts angelegt.
  mRequest.Name := 'mit leerzeichen';
  mFake.Calls := nil;
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan, mRequest);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.InvalidName, mStarted.Outcome);
  Assert.AreEqual(0, Integer(Length(mFake.Calls)));
  mFake.Calls := nil;
  mFake.Branches := nil;
  mFake.Bases := nil;
  mFake.Current := '';
  mStarted := Default(TAtlasIssueStartResult);
  mRequest := Default(TAtlasVcsBranchRequest);
end;

procedure TAtlasMyIssuesTests.ExecuteWithGitOptions;
var
  mFake: TFakeBranchingVcs;
  mVcs: IAtlasVersionControl;
  mPlan: TAtlasIssueStartPlan;
  mStarted: TAtlasIssueStartResult;
  mRequest: TAtlasVcsBranchRequest;
  mFolder: string;
begin
  mFake := TFakeBranchingVcs.Create(TAtlasVcsKind.Git);
  mVcs := mFake;
  mFake.Bases := ['main'];
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git,
    TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', ''), Issue('#753', 753, 'Atlas-Bereiche'));
  // Push ohne Anmeldung: der lokale Branch bleibt, „Beginnen“ gilt als gelungen.
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/753-x',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.LocalMain, 'main', '', 'origin'), '');
  mRequest.PushNow := True;
  mFake.FailOn := 'push';
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan, mRequest);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Started, mStarted.Outcome);
  Assert.IsTrue(mStarted.PushFailed);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mStarted.Reason, 'Grund des Push');
  Assert.AreEqual('feature/753-x', mFake.Current);
  Assert.AreEqual(2, Integer(Length(mStarted.Steps)));
  Assert.AreEqual('', mStarted.Folder);
  // Mit Push: nicht gescheitert.
  mFake.FailOn := '';
  mFake.Branches := nil;
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan, mRequest);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Started, mStarted.Outcome);
  Assert.IsFalse(mStarted.PushFailed);
  // Den worktree-Ordner gibt es schon: nichts angelegt.
  mFake.Branches := nil;
  mFake.Calls := nil;
  mRequest.PushNow := False;
  mRequest.WorktreeFolder := ExcludeTrailingPathDelimiter(GetCurrentDir);
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan, mRequest);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Failed, mStarted.Outcome);
  Assert.IsTrue(mStarted.FolderTaken);
  Assert.AreEqual(mRequest.WorktreeFolder, mStarted.Folder);
  Assert.AreEqual(1, Integer(Length(mFake.Calls)), 'nur die Abfrage, ob es den Branch gibt');
  // Neuer Ordner: worktree add, Ordner und Wurzel im Ergebnis.
  mFolder := IncludeTrailingPathDelimiter(GetCurrentDir) + 'gibt-es-nicht-1289';
  mRequest.WorktreeFolder := mFolder;
  mFake.Calls := nil;
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan, mRequest);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Started, mStarted.Outcome);
  Assert.IsFalse(mStarted.FolderTaken);
  Assert.AreEqual(mFolder, mStarted.Folder);
  Assert.AreEqual('C:\Repo', mStarted.WorkingRoot);
  Assert.AreEqual('run worktree add --quiet --no-track -b feature/753-x ' + mFolder + ' refs/heads/main',
    mFake.Calls[High(mFake.Calls)]);
  mFake.Calls := nil;
  mFake.Branches := nil;
  mFake.Bases := nil;
  mFake.Current := '';
  mFake.FailOn := '';
  mStarted := Default(TAtlasIssueStartResult);
  mRequest := Default(TAtlasVcsBranchRequest);
end;

procedure TAtlasMyIssuesTests.ExecuteSvnAndRemember;
const
  cName = 'ATL-123-tracker-im-bereich';
var
  mFake: TFakeBranchingVcs;
  mVcs: IAtlasVersionControl;
  mPlan: TAtlasIssueStartPlan;
  mStarted: TAtlasIssueStartResult;
  mDone: TArray<TAtlasVcsBranchStep>;
begin
  mFake := TFakeBranchingVcs.Create(TAtlasVcsKind.Svn);
  mVcs := mFake;
  // Standardlayout ^/trunk: {projektwurzel} ist die Wurzel, der Branch liegt unter ^/branches wie vor #1290.
  mFake.Current := 'trunk';
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn,
    TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', ''), Issue('ATL-123', 123, 'Tracker im Bereich'));
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Started, mStarted.Outcome);
  Assert.AreEqual(cName, mStarted.Branch);
  Assert.AreEqual('trunk', mStarted.Base);
  Assert.AreEqual('', mStarted.GitDir);
  Assert.AreEqual('', mStarted.CheckoutFolder);
  Assert.AreEqual(3, Integer(Length(mFake.Calls)));
  Assert.AreEqual('run copy ^/trunk@ ^/branches/' + cName + '@ --parents -m ATL-123 Branch für Tracker im Bereich',
    mFake.Calls[1]);
  Assert.AreEqual('run switch ^/branches/' + cName + '@ .', mFake.Calls[2]);
  Assert.AreEqual(cName, mFake.Current);
  // Scheitert switch nach der Kopie: Fehler mit dem schon ausgeführten Serverschritt.
  mFake.Branches := nil;
  mFake.Calls := nil;
  mFake.Current := 'trunk';
  mFake.FailOn := 'switch';
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Failed, mStarted.Outcome);
  Assert.AreEqual(1, mStarted.Run.Failed);
  Assert.AreEqual(1, mStarted.Run.Done);
  mDone := TAtlasVcsBranchPlan.ServerStepsDone(mStarted.Steps, mStarted.Run.Done);
  Assert.AreEqual(1, Integer(Length(mDone)));
  Assert.AreEqual('copy', mDone[0].Arguments[0]);
  Assert.AreEqual('trunk', mFake.Current, 'Arbeitskopie unverändert');
  mFake.FailOn := '';
  // Nur merken: keine Änderung an der Arbeitskopie.
  mFake.Calls := nil;
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn,
    TAtlasIssuesOptions.Create(TAtlasIssueStart.Remember, '', '', ''), Issue('ATL-123', 123, 'Tracker'));
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Remembered, mStarted.Outcome);
  Assert.AreEqual(0, Integer(Length(mFake.Calls)));
  // Ohne Versionsverwaltung: gemerkt.
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.None,
    TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', ''), Issue('ATL-123', 123, 'Tracker'));
  mStarted := TAtlasMyIssues.Execute(nil, mPlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Remembered, mStarted.Outcome);
  mFake.Branches := nil;
  mFake.Calls := nil;
  mFake.Current := '';
  mStarted := Default(TAtlasIssueStartResult);
  mDone := nil;
end;

const
  cExecuteSvncName = 'KASSE-42-bon-drucken-langsam';

/// <summary>after = none, after = checkout und ohne erkennbares Layout.</summary>
procedure AssertSvnAfterNoneCheckoutLayout(const AFake: TFakeBranchingVcs; const AVcs: IAtlasVersionControl;
  var AOptions: TAtlasIssuesOptions);
var
  mPlan: TAtlasIssueStartPlan;
  mStarted: TAtlasIssueStartResult;
begin
  // after = none: nur anlegen, die Arbeitskopie bleibt.
  AFake.Branches := nil;
  AFake.Calls := nil;
  AFake.Current := 'Kasse/trunk';
  AOptions.Svn.After := TAtlasVcsSvnAfter.None;
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, AOptions, Issue('KASSE-42', 42, 'Bon drucken langsam'));
  mStarted := TAtlasMyIssues.Execute(AVcs, mPlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Started, mStarted.Outcome);
  Assert.AreEqual(2, Integer(Length(AFake.Calls)), 'kein switch');
  Assert.AreEqual('Kasse/trunk', AFake.Current);
  // after = checkout: das Ergebnis nennt Ordner und alte Wurzel für das Angebot, die Gruppe dort zu öffnen.
  AFake.Branches := nil;
  AFake.Calls := nil;
  AOptions.Svn.After := TAtlasVcsSvnAfter.Checkout;
  AOptions.Svn.Project := 'Kassengruppe';
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, AOptions, Issue('KASSE-42', 42, 'Bon drucken langsam'));
  mStarted := TAtlasMyIssues.Execute(AVcs, mPlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Started, mStarted.Outcome);
  Assert.AreEqual(3, Integer(Length(AFake.Calls)));
  Assert.IsTrue(AFake.Calls[2].StartsWith('run checkout ^/Kasse/branches/' + cExecuteSvncName + '@ '), AFake.Calls[2]);
  Assert.AreEqual(AFake.WorkingCopy.Root, mStarted.WorkingRoot);
  Assert.AreEqual(ExpandFileName(IncludeTrailingPathDelimiter(AFake.WorkingCopy.Root) + '..' + PathDelim +
    'Kassengruppe-KASSE-42'), mStarted.CheckoutFolder);
  // Ohne erkennbares Layout: kein Ort, kein Serverschritt.
  AFake.Branches := nil;
  AFake.Calls := nil;
  AFake.SvnUrl := 'Kasse/Quellen';
  mStarted := TAtlasMyIssues.Execute(AVcs, mPlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Failed, mStarted.Outcome);
  Assert.AreEqual(1, Integer(Length(AFake.Calls)));
  Assert.AreEqual('exists ?', AFake.Calls[0]);
end;

/// <summary>#1291: festgeschriebenes External mit und ohne Umschalten.</summary>
procedure AssertSvnPinnedExternals(const AFake: TFakeBranchingVcs; const AVcs: IAtlasVersionControl;
  const AOptions: TAtlasIssuesOptions);
var
  mOptions: TAtlasIssuesOptions;
  mPlan: TAtlasIssueStartPlan;
  mStarted: TAtlasIssueStartResult;
  mFacts: TAtlasVcsBranchFacts;
  mRequest: TAtlasVcsBranchRequest;
begin
  mOptions := AOptions;
  // #1291: Anfrage mit festgeschriebenem External und Umschalten: --pin-externals, danach Index neu.
  AFake.Branches := nil;
  AFake.Calls := nil;
  AFake.SvnUrl := 'Kasse/trunk';
  AFake.Current := 'Kasse/trunk';
  mOptions.Svn.After := TAtlasVcsSvnAfter.Switch;
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, mOptions, Issue('KASSE-42', 42, 'Bon drucken langsam'));
  mFacts := TAtlasVcsBranchFacts.Empty;
  mFacts.Kind := TAtlasVcsKind.Svn;
  mFacts.ProjectRoot := 'Kasse';
  mFacts.LayoutKnown := True;
  mFacts.RepositoryRoot := 'https://svn.firma.local/repo';
  mFacts.SvnVersion := '1.14.3';
  mFacts.SvnDefinitions := [TAtlasVcsSvnExternalDefinition.Make('', '^/Packages/Basis/trunk Packages/Basis'#10)];
  SetLength(mFacts.SvnExternals, 1);
  mFacts.SvnExternals[0] := Default(TAtlasVcsSvnExternal);
  mFacts.SvnExternals[0].Folder := 'Packages/Basis';
  mFacts.SvnExternals[0].Url := '^/Packages/Basis/trunk';
  mFacts.SvnExternals[0].Source := 'Packages/Basis/trunk';
  mFacts.SvnExternals[0].WorkingRevision := '48190';
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Svn, cExecuteSvncName, TAtlasVcsBranchBase.Make(
    TAtlasVcsBranchBaseKind.Head, 'Kasse/trunk', '48230'), 'KASSE-42 Branch');
  Assert.IsTrue(TAtlasVcsBranchPlan.ApplySvn(mRequest, mFacts, mOptions.Svn));
  TAtlasVcsBranchPlan.ApplyExternals(mRequest, mFacts, mOptions.Svn,
    TArray<TAtlasVcsExternalAction>.Create(TAtlasVcsExternalAction.Pin));
  mStarted := TAtlasMyIssues.Execute(AVcs, mPlan, mRequest);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Started, mStarted.Outcome);
  Assert.IsTrue(AFake.Calls[1].EndsWith('--pin-externals'), AFake.Calls[1]);
  Assert.IsTrue(mStarted.IndexRebuild);
  // Nur anlegen: Die Arbeitskopie bleibt, der Index auch.
  AFake.Branches := nil;
  AFake.Calls := nil;
  mRequest.After := TAtlasVcsSvnAfter.None;
  mStarted := TAtlasMyIssues.Execute(AVcs, mPlan, mRequest);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Started, mStarted.Outcome);
  Assert.IsFalse(mStarted.IndexRebuild);
  AFake.Branches := nil;
  AFake.Calls := nil;
  mStarted := Default(TAtlasIssueStartResult);
  mRequest := Default(TAtlasVcsBranchRequest);
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasMyIssuesTests.ExecuteSvnUnderProjectRoot;
var
  mFake: TFakeBranchingVcs;
  mVcs: IAtlasVersionControl;
  mOptions: TAtlasIssuesOptions;
  mPlan: TAtlasIssueStartPlan;
  mStarted: TAtlasIssueStartResult;
begin
  mFake := TFakeBranchingVcs.Create(TAtlasVcsKind.Svn);
  mVcs := mFake;
  mFake.SvnUrl := 'Kasse/trunk';
  mFake.Current := 'trunk';
  mOptions := TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', '');
  mPlan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, mOptions, Issue('KASSE-42', 42, 'Bon drucken langsam'));
  Assert.AreEqual(cExecuteSvncName, mPlan.Branch);
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Started, mStarted.Outcome);
  Assert.AreEqual('Kasse/trunk', mStarted.Base, 'Hauptbranch unter der Projektwurzel');
  Assert.AreEqual(3, Integer(Length(mFake.Calls)));
  Assert.AreEqual('exists ^/Kasse/branches/' + cExecuteSvncName, mFake.Calls[0]);
  Assert.AreEqual('run copy ^/Kasse/trunk@ ^/Kasse/branches/' + cExecuteSvncName +
    '@ --parents -m KASSE-42 Branch für Bon drucken langsam', mFake.Calls[1]);
  Assert.AreEqual('run switch ^/Kasse/branches/' + cExecuteSvncName + '@ .', mFake.Calls[2]);
  Assert.IsFalse(mStarted.IndexRebuild, 'ohne Externals kein neuer Index');
  // Zweites „Beginnen“ auf demselben Issue: findet ihn am selben Ort und schaltet nur um.
  mFake.Calls := nil;
  mFake.Current := 'Kasse/trunk';
  mStarted := TAtlasMyIssues.Execute(mVcs, mPlan);
  Assert.AreEqual<TAtlasIssueStartOutcome>(TAtlasIssueStartOutcome.Switched, mStarted.Outcome);
  Assert.AreEqual(2, Integer(Length(mFake.Calls)));
  Assert.AreEqual('switch ^/Kasse/branches/' + cExecuteSvncName, mFake.Calls[1]);
  Assert.AreEqual('Kasse/branches/' + cExecuteSvncName, mFake.Current);
  AssertSvnAfterNoneCheckoutLayout(mFake, mVcs, mOptions);
  AssertSvnPinnedExternals(mFake, mVcs, mOptions);
end;

procedure TAtlasMyIssuesTests.VcsKindFromText;
begin
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git, TAtlasMyIssues.VcsKindOf('git'));
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Svn, TAtlasMyIssues.VcsKindOf('SVN'));
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, TAtlasMyIssues.VcsKindOf('none'));
end;

procedure TAtlasMyIssuesTests.GroupsLimitRowsPerProject;
var
  mView, mKasse, mBasis, mAtlas: TAtlasIssuesView;
begin
  mView := Default(TAtlasIssuesView);
  mKasse := Default(TAtlasIssuesView);
  mKasse.Status := TAtlasIssuesStatus.Ready;
  mKasse.Items := [Issue('KASSE-1', 1, 'Eins'), Issue('KASSE-2', 2, 'Zwei'), Issue('KASSE-3', 3, 'Drei')];
  mBasis := Default(TAtlasIssuesView);
  mBasis.Status := TAtlasIssuesStatus.Failed;
  mBasis.Error := TAtlasCiFetchError.NoCredentials;
  mAtlas := Default(TAtlasIssuesView);
  mAtlas.Status := TAtlasIssuesStatus.Ready;
  mAtlas.Items := [Issue('#7', 7, 'Sieben')];
  TAtlasMyIssues.AddGroup(mView, 'Firma · KASSE', 'C:\Kasse', mKasse, 2);
  TAtlasMyIssues.AddGroup(mView, 'Firma · BASIS', 'C:\Basis', mBasis, 2);
  TAtlasMyIssues.AddGroup(mView, 'GitHub · owner/repo', 'C:\Atlas', mAtlas, 2);
  Assert.AreEqual(3, Integer(Length(mView.Items)));
  Assert.AreEqual(3, Integer(Length(mView.Groups)));
  Assert.AreEqual(2, mView.Groups[0].Shown);
  Assert.AreEqual(3, mView.Groups[0].Total);
  Assert.AreEqual(1, mView.Groups[0].More);
  Assert.AreEqual(2, mView.Groups[1].First);
  Assert.AreEqual(0, mView.Groups[1].Shown);
  Assert.AreEqual(Ord(TAtlasCiFetchError.NoCredentials), Ord(mView.Groups[1].Error));
  Assert.AreEqual(2, mView.Groups[2].First);
  Assert.AreEqual(0, TAtlasMyIssues.GroupOf(mView, 1));
  // Hinter der leeren Gruppe BASIS: die Zeile gehört zu owner/repo.
  Assert.AreEqual(2, TAtlasMyIssues.GroupOf(mView, 2));
  Assert.AreEqual('C:\Atlas', mView.Groups[TAtlasMyIssues.GroupOf(mView, 2)].Project);
  // Mindestens eine Zeile je Gruppe.
  mView := Default(TAtlasIssuesView);
  TAtlasMyIssues.AddGroup(mView, 'Firma · KASSE', 'C:\Kasse', mKasse, 0);
  Assert.AreEqual(1, Integer(Length(mView.Items)));
  Assert.AreEqual(-1, TAtlasMyIssues.GroupOf(Default(TAtlasIssuesView), 0));
  mView := Default(TAtlasIssuesView);
  mKasse := Default(TAtlasIssuesView);
  mBasis := Default(TAtlasIssuesView);
  mAtlas := Default(TAtlasIssuesView);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMyIssuesTests);

end.
