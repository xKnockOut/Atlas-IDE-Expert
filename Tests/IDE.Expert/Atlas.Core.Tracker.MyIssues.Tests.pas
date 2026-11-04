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
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.BranchPlan,
  Atlas.Core.Vcs.Internals.SvnLayout,
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
  Name: string;
begin
  Result := False;
  for Name in AList do
  begin
    if Name = AName then
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
  Target: TAtlasTrackerTarget;
begin
  Target := TAtlasMyIssues.TargetFor('youtrack', 'https://yt.firma.de', 'ATL', '', 'for: me');
  Assert.AreEqual('youtrack', Target.Provider);
  Assert.AreEqual('for: me', Target.Query);
  Assert.IsTrue(Target.Configured);
  // Einstellung ersetzt den Anbieter aus .atlas.
  Target := TAtlasMyIssues.TargetFor('youtrack', 'https://github.com', 'beispiel/atlas', 'GitHub', '');
  Assert.AreEqual('github', Target.Provider);
  Assert.IsTrue(Target.Configured);
  // Unbekannter Anbieter: nicht eingerichtet.
  Assert.IsFalse(TAtlasMyIssues.TargetFor('jira', 'https://jira.firma.de', 'ATL', '', '').Configured);
  Assert.IsFalse(TAtlasMyIssues.TargetFor('', '', '', '', '').Configured);
end;

procedure TAtlasMyIssuesTests.DueEveryTenMinutes;
var
  State: TAtlasIssuesState;
begin
  State := TAtlasIssuesState.Empty;
  Assert.IsTrue(TAtlasMyIssues.Due(State, GitHub, Now0, False), 'noch nie');
  TAtlasMyIssues.Recorded(State, GitHub, Now0, True, [Issue('#1', 1, 'a')], TAtlasCiFetchError.None);
  Assert.IsFalse(TAtlasMyIssues.Due(State, GitHub, IncMinute(Now0, 9), False));
  Assert.IsTrue(TAtlasMyIssues.Due(State, GitHub, IncMinute(Now0, 10), False));
  Assert.IsTrue(TAtlasMyIssues.Due(State, GitHub, IncMinute(Now0, 1), True), '„Jetzt abfragen“');
  Assert.IsTrue(TAtlasMyIssues.Due(State, YouTrack, IncMinute(Now0, 1), False), 'anderes Ziel');
  Assert.IsTrue(TAtlasMyIssues.Due(State, GitHub, IncMinute(Now0, -5), False), 'Uhr zurückgestellt');
  Assert.IsFalse(TAtlasMyIssues.Due(State, TAtlasMyIssues.TargetFor('', '', '', '', ''), Now0, True),
    'ohne Tracker kein Netzzugriff');
end;

procedure TAtlasMyIssuesTests.FailedFetchKeepsLastState;
var
  State: TAtlasIssuesState;
begin
  State := TAtlasIssuesState.Empty;
  TAtlasMyIssues.Recorded(State, GitHub, Now0, True, [Issue('#1', 1, 'a'), Issue('#2', 2, 'b')],
    TAtlasCiFetchError.None);
  TAtlasMyIssues.Recorded(State, GitHub, IncMinute(Now0, 20), False, nil, TAtlasCiFetchError.Network);
  Assert.AreEqual(2, Integer(Length(State.Items)), 'letzter Stand bleibt');
  Assert.IsTrue(SameDateTime(Now0, State.At));
  Assert.IsTrue(State.Error = TAtlasCiFetchError.Network);
  Assert.IsTrue(SameDateTime(IncMinute(Now0, 20), State.Attempt));
  // Anderes Ziel ohne Erfolg: der alte Stand gehört nicht dazu.
  TAtlasMyIssues.Recorded(State, YouTrack, IncMinute(Now0, 21), False, nil, TAtlasCiFetchError.Timeout);
  Assert.AreEqual(0, Integer(Length(State.Items)));
  Assert.IsTrue(State.At = 0);
end;

procedure TAtlasMyIssuesTests.ViewStatus;
var
  State: TAtlasIssuesState;
  View: TAtlasIssuesView;
begin
  State := TAtlasIssuesState.Empty;
  View := TAtlasMyIssues.View(State, TAtlasMyIssues.TargetFor('', '', '', '', ''), '');
  Assert.IsTrue(View.Status = TAtlasIssuesStatus.NotConfigured);
  View := TAtlasMyIssues.View(State, GitHub, '');
  Assert.IsTrue(View.Status = TAtlasIssuesStatus.Waiting);
  TAtlasMyIssues.Recorded(State, GitHub, Now0, False, nil, TAtlasCiFetchError.Unauthorized);
  View := TAtlasMyIssues.View(State, GitHub, '');
  Assert.IsTrue(View.Status = TAtlasIssuesStatus.Failed);
  Assert.IsTrue(View.Error = TAtlasCiFetchError.Unauthorized);
  TAtlasMyIssues.Recorded(State, GitHub, Now0, True, [Issue('#1', 1, 'a')], TAtlasCiFetchError.None);
  View := TAtlasMyIssues.View(State, GitHub, '');
  Assert.IsTrue(View.Status = TAtlasIssuesStatus.Ready);
  Assert.AreEqual(1, Integer(Length(View.Items)));
  TAtlasMyIssues.Recorded(State, GitHub, IncHour(Now0, 1), False, nil, TAtlasCiFetchError.Network);
  View := TAtlasMyIssues.View(State, GitHub, '');
  Assert.IsTrue(View.Status = TAtlasIssuesStatus.Stale, '„Stand vom …“');
  Assert.IsTrue(SameDateTime(Now0, View.At));
  Assert.AreEqual(1, Integer(Length(View.Items)));
end;

procedure TAtlasMyIssuesTests.ActiveIssueFromStartAndBranch;
var
  State: TAtlasIssuesState;
  Active: TAtlasActiveIssue;
begin
  State := TAtlasIssuesState.Empty;
  TAtlasMyIssues.Recorded(State, GitHub, Now0, True, [Issue('#753', 753, 'Atlas-Bereiche')],
    TAtlasCiFetchError.None);
  // Branch → Ticket, Titel aus der Liste.
  Active := TAtlasMyIssues.Effective(State, 'github', 'beispiel/atlas', 'feature/753-atlas-bereiche-und');
  Assert.AreEqual('#753', Active.Key);
  Assert.AreEqual('Atlas-Bereiche', Active.Title);
  Assert.IsTrue(Active.FromBranch);
  Assert.IsFalse(TAtlasMyIssues.Effective(State, 'github', 'beispiel/atlas', 'main').Active);
  // Mit Branch begonnen: gilt nur auf diesem Branch.
  TAtlasMyIssues.Started(State, Issue('#612', 612, 'Parser'), TAtlasIssueStart.Branch, 'feature/612-parser',
    Now0);
  Assert.AreEqual('#612', TAtlasMyIssues.Effective(State, 'github', '', 'feature/612-parser').Key);
  Assert.AreEqual('#612', TAtlasMyIssues.Effective(State, 'github', '', '').Key, 'Branch unbekannt');
  Assert.IsFalse(TAtlasMyIssues.Effective(State, 'github', '', 'main').Active, 'anderer Branch');
  // Nur gemerkt: gilt auf jedem Branch.
  TAtlasMyIssues.Started(State, Issue('ATL-123', 123, 'Tracker'), TAtlasIssueStart.Remember, 'trunk', Now0);
  Active := TAtlasMyIssues.Effective(State, 'youtrack', 'ATL', 'trunk');
  Assert.AreEqual('ATL-123', Active.Key);
  Assert.AreEqual('', Active.Branch);
  Assert.IsFalse(Active.FromBranch);
end;

procedure TAtlasMyIssuesTests.EndedIssueStaysOff;
var
  State: TAtlasIssuesState;
begin
  State := TAtlasIssuesState.Empty;
  TAtlasMyIssues.Started(State, Issue('#753', 753, 'x'), TAtlasIssueStart.Branch, 'feature/753-x', Now0);
  TAtlasMyIssues.Ended(State, 'feature/753-x');
  Assert.IsFalse(TAtlasMyIssues.Effective(State, 'github', '', 'feature/753-x').Active,
    'der Branch aktiviert es nicht wieder');
  Assert.AreEqual('#9', TAtlasMyIssues.Effective(State, 'github', '', 'feature/9-y').Key);
  TAtlasMyIssues.Started(State, Issue('#753', 753, 'x'), TAtlasIssueStart.Branch, 'feature/753-x', Now0);
  Assert.AreEqual('', State.EndedBranch, 'erneutes Beginnen hebt es auf');
end;

procedure TAtlasMyIssuesTests.PlanStartGit;
var
  Plan: TAtlasIssueStartPlan;
  Options: TAtlasIssuesOptions;
begin
  Options := TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', '{kennung} ');
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, Options,
    Issue('#753', 753, 'Plugin: Atlas-Bereiche und Layouts der Willkommensseite'));
  Assert.IsTrue(Plan.Valid);
  Assert.IsTrue(Plan.Mode = TAtlasIssueStart.Branch);
  Assert.AreEqual('feature/753-atlas-bereiche-und', Plan.Branch);
  Assert.AreEqual(2, Integer(Length(Plan.Bases)));
  Assert.AreEqual('main', Plan.Bases[0]);
  Assert.AreEqual('master', Plan.Bases[1]);
  Assert.AreEqual('#753 ', Plan.Prefix);
  Options := TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, 'bugfix/{nummer}', 'develop', '');
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, Options, Issue('#9', 9, 'x'));
  Assert.AreEqual('bugfix/9', Plan.Branch);
  Assert.AreEqual(1, Integer(Length(Plan.Bases)));
  Assert.AreEqual('develop', Plan.Bases[0]);
  Assert.AreEqual('', Plan.Prefix);
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch,
    '///', '', ''), Issue('#9', 9, 'x'));
  Assert.IsFalse(Plan.Valid, 'kein gültiger Name');
  // #1286: Hauptbranch des Projekts statt raten; issues.branchBase bleibt vorrangig.
  Options := TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', '');
  Options.MainBranch := 'develop';
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, Options, Issue('#9', 9, 'x'));
  Assert.AreEqual(1, Integer(Length(Plan.Bases)));
  Assert.AreEqual('develop', Plan.Bases[0]);
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, Options, Issue('#9', 9, 'x'));
  Assert.AreEqual('develop', Plan.Bases[0], 'auch unter SVN (^/develop)');
  Options.BranchBase := 'release';
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, Options, Issue('#9', 9, 'x'));
  Assert.AreEqual('release', Plan.Bases[0]);
end;

procedure TAtlasMyIssuesTests.PlanStartSvnAndRemember;
var
  Plan: TAtlasIssueStartPlan;
begin
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '',
    '', '{kennung} '), Issue('ATL-123', 123, 'Tracker im Plugin anbinden'));
  Assert.AreEqual('ATL-123-tracker-im-plugin', Plan.Branch, 'unter ^/branches/');
  Assert.AreEqual('trunk', Plan.Bases[0]);
  // #1290: Nachricht aus vcs.branch.svn.message (Vorgabe „{kennung} Branch für {titel}“), Optionen mit Kennung.
  Assert.AreEqual('ATL-123 Branch für Tracker im Plugin anbinden', Plan.Message);
  Assert.AreEqual('ATL-123', Plan.Svn.Key);
  Assert.AreEqual('{projektwurzel}/branches/{name}', Plan.Svn.Location);
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, TAtlasIssuesOptions.Create(TAtlasIssueStart.Remember, '',
    '', '{kennung} '), Issue('ATL-123', 123, 'x'));
  Assert.IsTrue(Plan.Mode = TAtlasIssueStart.Remember);
  Assert.AreEqual('', Plan.Branch);
  Assert.AreEqual('ATL-123 ', Plan.Prefix);
  // Ohne Versionsverwaltung: nur merken.
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.None, TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '',
    '', ''), Issue('ATL-1', 1, 'x'));
  Assert.IsTrue(Plan.Mode = TAtlasIssueStart.Remember);
  Assert.IsTrue(Plan.Valid);
end;

procedure TAtlasMyIssuesTests.CommitPrefixOfActiveIssue;
var
  State: TAtlasIssuesState;
  Active: TAtlasActiveIssue;
begin
  State := TAtlasIssuesState.Empty;
  Assert.AreEqual('', TAtlasMyIssues.CommitPrefix(TAtlasMyIssues.Effective(State, 'youtrack', 'ATL',
    'trunk'), '{kennung} '), 'ohne aktives Issue');
  TAtlasMyIssues.Started(State, Issue('ATL-123', 123, 'Tracker'), TAtlasIssueStart.Remember, '', Now0);
  Active := TAtlasMyIssues.Effective(State, 'youtrack', 'ATL', 'trunk');
  Assert.AreEqual('ATL-123 ', TAtlasMyIssues.CommitPrefix(Active, '{kennung} '));
  Assert.AreEqual('', TAtlasMyIssues.CommitPrefix(Active, ''), 'leeres Muster: aus');
  Assert.AreEqual('[123] ', TAtlasMyIssues.CommitPrefix(Active, '[{nummer}] '));
  Assert.AreEqual(753, TAtlasMyIssues.NumberOfKey('#753'));
  Assert.AreEqual(123, TAtlasMyIssues.NumberOfKey('ATL-123'));
  Assert.AreEqual(0, TAtlasMyIssues.NumberOfKey('ATL'));
  Assert.AreEqual(0, TAtlasMyIssues.NumberOfKey('x5'));
end;

procedure TAtlasMyIssuesTests.FieldsOfGitHubAndYouTrack;
var
  Value: TAtlasTrackerIssue;
  Fields: TArray<string>;
begin
  Value := Issue('#753', 753, 'x');
  Value.Labels := ['plugin', 'willkommensseite'];
  Value.State := 'open';
  Fields := TAtlasMyIssues.Fields(Value);
  Assert.AreEqual(2, Integer(Length(Fields)), 'GitHub: nur Labels');
  Assert.AreEqual('plugin', Fields[0]);
  Value := Issue('ATL-123', 123, 'x');
  Value.State := 'In Progress';
  Value.Priority := 'Major';
  Value.Sprint := 'Sprint 42';
  Fields := TAtlasMyIssues.Fields(Value);
  Assert.AreEqual(3, Integer(Length(Fields)));
  Assert.AreEqual('In Progress', Fields[0]);
  Assert.AreEqual('Major', Fields[1]);
  Assert.AreEqual('Sprint 42', Fields[2]);
end;

procedure TAtlasMyIssuesTests.SectionRoundTripKeepsOtherFields;
var
  Summary, Loaded: TAtlasProjectSummary;
  State, Back: TAtlasIssuesState;
  Item: TAtlasTrackerIssue;
  Json: string;
begin
  Summary := TAtlasProjectSummary.Create('C:\Projekte\Demo.dproj');
  Summary.LastOpened := Now0;
  State := TAtlasIssuesState.Empty;
  Item := Issue('#753', 753, 'Atlas-Bereiche');
  Item.Labels := ['plugin'];
  Item.PullRequest.Number := 760;
  Item.PullRequest.Checks := TAtlasTrackerChecks.Failure;
  Item.PullRequest.Draft := True;
  TAtlasMyIssues.Recorded(State, GitHub, Now0, True, [Item], TAtlasCiFetchError.None);
  TAtlasMyIssues.Recorded(State, GitHub, IncMinute(Now0, 30), False, nil, TAtlasCiFetchError.Timeout);
  TAtlasMyIssues.Started(State, Item, TAtlasIssueStart.Branch, 'feature/753-atlas-bereiche', Now0);
  State.Hook := TAtlasMyIssues.cHookYes;
  State.GitDir := 'C:\Repo\.git';
  TAtlasMyIssues.Write(Summary, State);
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Loaded));
  Assert.IsTrue(SameDateTime(Now0, Loaded.LastOpened), 'übrige Felder bleiben');
  Assert.IsTrue(TAtlasMyIssues.Read(Loaded, Back));
  Assert.AreEqual('github', Back.Provider);
  Assert.AreEqual('https://github.com', Back.Server);
  Assert.AreEqual('beispiel/atlas', Back.Project);
  Assert.IsTrue(Back.Error = TAtlasCiFetchError.Timeout);
  Assert.IsTrue(SameDateTime(Now0, Back.At));
  Assert.AreEqual(1, Integer(Length(Back.Items)));
  Assert.AreEqual('#753', Back.Items[0].Key);
  Assert.AreEqual(753, Back.Items[0].Number);
  Assert.AreEqual('plugin', Back.Items[0].Labels[0]);
  Assert.AreEqual(760, Back.Items[0].PullRequest.Number);
  Assert.IsTrue(Back.Items[0].PullRequest.Checks = TAtlasTrackerChecks.Failure);
  Assert.IsTrue(Back.Items[0].PullRequest.Draft);
  Assert.AreEqual('#753', Back.Active.Key);
  Assert.IsTrue(Back.Active.Mode = TAtlasIssueStart.Branch);
  Assert.AreEqual('feature/753-atlas-bereiche', Back.Active.Branch);
  Assert.AreEqual('yes', Back.Hook);
  Assert.AreEqual('C:\Repo\.git', Back.GitDir);
  Assert.IsTrue(Back.Matches(GitHub));
  // Ein zweites Schreiben ersetzt den Abschnitt.
  TAtlasMyIssues.Ended(Back, 'feature/753-atlas-bereiche');
  TAtlasMyIssues.Write(Loaded, Back);
  Assert.IsTrue(TAtlasMyIssues.Read(Loaded, State));
  Assert.IsFalse(State.Active.Active);
  Assert.AreEqual('feature/753-atlas-bereiche', State.EndedBranch);
  Assert.IsFalse(TAtlasMyIssues.Read(TAtlasProjectSummary.Create('x'), State), 'ohne Abschnitt');
  Assert.IsFalse(Pos('token', LowerCase(TAtlasMyIssues.ToJson(Back))) > 0, 'nie Zugangsdaten');
end;

const
  cExecuteGitcName = 'feature/753-atlas-bereiche-und';

procedure TAtlasMyIssuesTests.ExecuteGit;
var
  Fake: TFakeBranchingVcs;
  Vcs: IAtlasVersionControl;
  Plan: TAtlasIssueStartPlan;
  Started: TAtlasIssueStartResult;
  Options: TAtlasIssuesOptions;
begin
  Options := TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', '{kennung} ');
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git, Options,
    Issue('#753', 753, 'Atlas-Bereiche und Layout'));
  // Ohne main: von master (Plan aus TAtlasVcsBranchPlan, #1288).
  Fake := TFakeBranchingVcs.Create(TAtlasVcsKind.Git);
  Vcs := Fake;
  Fake.Bases := ['master'];
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Started);
  Assert.IsTrue(Started.Succeeded);
  Assert.AreEqual(cExecuteGitcName, Started.Branch);
  Assert.AreEqual('master', Started.Base);
  Assert.AreEqual(cExecuteGitcName, Fake.Current);
  Assert.AreEqual('C:\Repo\.git', Started.GitDir);
  Assert.AreEqual('C:\Repo\.git\hooks', Started.Hooks);
  Assert.AreEqual(6, Integer(Length(Fake.Calls)));
  Assert.AreEqual('exists main', Fake.Calls[1]);
  Assert.AreEqual('remote master', Fake.Calls[4]);
  Assert.AreEqual('run checkout --quiet --no-track -b ' + cExecuteGitcName + ' refs/heads/master --', Fake.Calls[5]);
  Assert.AreEqual(1, Integer(Length(Started.Steps)));
  Assert.AreEqual(1, Started.Run.Done);
  // Gibt es den Branch schon: nur auschecken.
  Fake.Current := 'main';
  Fake.Calls := nil;
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Switched);
  Assert.AreEqual(2, Integer(Length(Fake.Calls)));
  Assert.AreEqual('switch ' + cExecuteGitcName, Fake.Calls[1]);
  // Nur auf origin: von origin/main.
  Fake.Branches := nil;
  Fake.Bases := nil;
  Fake.RemoteBases := ['main'];
  Fake.Calls := nil;
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Started);
  Assert.AreEqual('origin/main', Started.Base);
  Assert.AreEqual('run checkout --quiet --no-track -b ' + cExecuteGitcName + ' refs/remotes/origin/main --',
    Fake.Calls[High(Fake.Calls)]);
  // Keine Basis vorhanden: Fehler, nichts ausgecheckt (nie stillschweigend vom aktuellen Branch).
  Fake.Branches := nil;
  Fake.RemoteBases := nil;
  Fake.Current := 'main';
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Failed);
  Assert.IsFalse(Started.Succeeded);
  Assert.IsTrue(Started.Reason = TAtlasVcsOutcome.Failed);
  Assert.AreEqual('main', Fake.Current);
  // Zeitüberschreitung bei der Prüfung: kein Anlegen.
  Fake.ExistsOutcome := TAtlasVcsOutcome.TimedOut;
  Fake.Bases := ['main'];
  Fake.Calls := nil;
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Reason = TAtlasVcsOutcome.TimedOut);
  Assert.AreEqual(1, Integer(Length(Fake.Calls)));
  Fake.ExistsOutcome := TAtlasVcsOutcome.Ok;
  // Ungültiger Name aus dem Muster.
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git,
    TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '{kurztitel}', '', ''), Issue('#1', 1, '...'));
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.InvalidName);
  Fake.Calls := nil;
  Fake.Branches := nil;
  Fake.Bases := nil;
  Fake.RemoteBases := nil;
  Fake.Current := '';
  Started := Default(TAtlasIssueStartResult);
end;

procedure TAtlasMyIssuesTests.ExecuteWithDialogRequest;
var
  Fake: TFakeBranchingVcs;
  Vcs: IAtlasVersionControl;
  Plan: TAtlasIssueStartPlan;
  Started: TAtlasIssueStartResult;
  mRequest: TAtlasVcsBranchRequest;
begin
  Fake := TFakeBranchingVcs.Create(TAtlasVcsKind.Git);
  Vcs := Fake;
  Fake.Bases := ['main'];
  Fake.Current := 'feature/700-alt';
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git,
    TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', ''), Issue('#753', 753, 'Atlas-Bereiche'));
  // Im Dialog umbenannt und vom aktuellen Branch: genau diese Werte, ohne eigene Prüfung der Basen.
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/753-anders',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Current, 'feature/700-alt', ''), '');
  ProgressCalls := 0;
  Started := TAtlasMyIssues.Execute(Vcs, Plan, mRequest, CountingProgress());
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Started);
  Assert.AreEqual('feature/753-anders', Started.Branch);
  Assert.AreEqual('feature/700-alt', Started.Base);
  Assert.AreEqual(2, Integer(Length(Fake.Calls)));
  Assert.AreEqual('exists feature/753-anders', Fake.Calls[0]);
  Assert.AreEqual('run checkout --quiet --no-track -b feature/753-anders refs/heads/feature/700-alt --',
    Fake.Calls[1]);
  Assert.AreEqual(1, ProgressCalls, 'Fortschritt je Schritt');
  // Ungültiger Name aus dem Dialog: nichts angelegt.
  mRequest.Name := 'mit leerzeichen';
  Fake.Calls := nil;
  Started := TAtlasMyIssues.Execute(Vcs, Plan, mRequest);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.InvalidName);
  Assert.AreEqual(0, Integer(Length(Fake.Calls)));
  Fake.Calls := nil;
  Fake.Branches := nil;
  Fake.Bases := nil;
  Fake.Current := '';
  Started := Default(TAtlasIssueStartResult);
  mRequest := Default(TAtlasVcsBranchRequest);
end;

procedure TAtlasMyIssuesTests.ExecuteWithGitOptions;
var
  Fake: TFakeBranchingVcs;
  Vcs: IAtlasVersionControl;
  Plan: TAtlasIssueStartPlan;
  Started: TAtlasIssueStartResult;
  mRequest: TAtlasVcsBranchRequest;
  mFolder: string;
begin
  Fake := TFakeBranchingVcs.Create(TAtlasVcsKind.Git);
  Vcs := Fake;
  Fake.Bases := ['main'];
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Git,
    TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', ''), Issue('#753', 753, 'Atlas-Bereiche'));
  // Push ohne Anmeldung: der lokale Branch bleibt, „Beginnen“ gilt als gelungen.
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/753-x',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.LocalMain, 'main', '', 'origin'), '');
  mRequest.PushNow := True;
  Fake.FailOn := 'push';
  Started := TAtlasMyIssues.Execute(Vcs, Plan, mRequest);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Started);
  Assert.IsTrue(Started.PushFailed);
  Assert.IsTrue(Started.Reason = TAtlasVcsOutcome.Failed, 'Grund des Push');
  Assert.AreEqual('feature/753-x', Fake.Current);
  Assert.AreEqual(2, Integer(Length(Started.Steps)));
  Assert.AreEqual('', Started.Folder);
  // Mit Push: nicht gescheitert.
  Fake.FailOn := '';
  Fake.Branches := nil;
  Started := TAtlasMyIssues.Execute(Vcs, Plan, mRequest);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Started);
  Assert.IsFalse(Started.PushFailed);
  // Den worktree-Ordner gibt es schon: nichts angelegt.
  Fake.Branches := nil;
  Fake.Calls := nil;
  mRequest.PushNow := False;
  mRequest.WorktreeFolder := ExcludeTrailingPathDelimiter(GetCurrentDir);
  Started := TAtlasMyIssues.Execute(Vcs, Plan, mRequest);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Failed);
  Assert.IsTrue(Started.FolderTaken);
  Assert.AreEqual(mRequest.WorktreeFolder, Started.Folder);
  Assert.AreEqual(1, Integer(Length(Fake.Calls)), 'nur die Abfrage, ob es den Branch gibt');
  // Neuer Ordner: worktree add, Ordner und Wurzel im Ergebnis.
  mFolder := IncludeTrailingPathDelimiter(GetCurrentDir) + 'gibt-es-nicht-1289';
  mRequest.WorktreeFolder := mFolder;
  Fake.Calls := nil;
  Started := TAtlasMyIssues.Execute(Vcs, Plan, mRequest);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Started);
  Assert.IsFalse(Started.FolderTaken);
  Assert.AreEqual(mFolder, Started.Folder);
  Assert.AreEqual('C:\Repo', Started.WorkingRoot);
  Assert.AreEqual('run worktree add --quiet --no-track -b feature/753-x ' + mFolder + ' refs/heads/main',
    Fake.Calls[High(Fake.Calls)]);
  Fake.Calls := nil;
  Fake.Branches := nil;
  Fake.Bases := nil;
  Fake.Current := '';
  Fake.FailOn := '';
  Started := Default(TAtlasIssueStartResult);
  mRequest := Default(TAtlasVcsBranchRequest);
end;

procedure TAtlasMyIssuesTests.ExecuteSvnAndRemember;
const
  cName = 'ATL-123-tracker-im-bereich';
var
  Fake: TFakeBranchingVcs;
  Vcs: IAtlasVersionControl;
  Plan: TAtlasIssueStartPlan;
  Started: TAtlasIssueStartResult;
  mDone: TArray<TAtlasVcsBranchStep>;
begin
  Fake := TFakeBranchingVcs.Create(TAtlasVcsKind.Svn);
  Vcs := Fake;
  // Standardlayout ^/trunk: {projektwurzel} ist die Wurzel, der Branch liegt unter ^/branches wie vor #1290.
  Fake.Current := 'trunk';
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn,
    TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', ''), Issue('ATL-123', 123, 'Tracker im Bereich'));
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Started);
  Assert.AreEqual(cName, Started.Branch);
  Assert.AreEqual('trunk', Started.Base);
  Assert.AreEqual('', Started.GitDir);
  Assert.AreEqual('', Started.CheckoutFolder);
  Assert.AreEqual(3, Integer(Length(Fake.Calls)));
  Assert.AreEqual('run copy ^/trunk@ ^/branches/' + cName + '@ --parents -m ATL-123 Branch für Tracker im Bereich',
    Fake.Calls[1]);
  Assert.AreEqual('run switch ^/branches/' + cName + '@ .', Fake.Calls[2]);
  Assert.AreEqual(cName, Fake.Current);
  // Scheitert switch nach der Kopie: Fehler mit dem schon ausgeführten Serverschritt.
  Fake.Branches := nil;
  Fake.Calls := nil;
  Fake.Current := 'trunk';
  Fake.FailOn := 'switch';
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Failed);
  Assert.AreEqual(1, Started.Run.Failed);
  Assert.AreEqual(1, Started.Run.Done);
  mDone := TAtlasVcsBranchPlan.ServerStepsDone(Started.Steps, Started.Run.Done);
  Assert.AreEqual(1, Integer(Length(mDone)));
  Assert.AreEqual('copy', mDone[0].Arguments[0]);
  Assert.AreEqual('trunk', Fake.Current, 'Arbeitskopie unverändert');
  Fake.FailOn := '';
  // Nur merken: keine Änderung an der Arbeitskopie.
  Fake.Calls := nil;
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn,
    TAtlasIssuesOptions.Create(TAtlasIssueStart.Remember, '', '', ''), Issue('ATL-123', 123, 'Tracker'));
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Remembered);
  Assert.AreEqual(0, Integer(Length(Fake.Calls)));
  // Ohne Versionsverwaltung: gemerkt.
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.None,
    TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', ''), Issue('ATL-123', 123, 'Tracker'));
  Started := TAtlasMyIssues.Execute(nil, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Remembered);
  Fake.Branches := nil;
  Fake.Calls := nil;
  Fake.Current := '';
  Started := Default(TAtlasIssueStartResult);
  mDone := nil;
end;

const
  cExecuteSvncName = 'KASSE-42-bon-drucken-langsam';

procedure TAtlasMyIssuesTests.ExecuteSvnUnderProjectRoot;
var
  Fake: TFakeBranchingVcs;
  Vcs: IAtlasVersionControl;
  Options: TAtlasIssuesOptions;
  Plan: TAtlasIssueStartPlan;
  Started: TAtlasIssueStartResult;
  mFacts: TAtlasVcsBranchFacts;
  mRequest: TAtlasVcsBranchRequest;
begin
  Fake := TFakeBranchingVcs.Create(TAtlasVcsKind.Svn);
  Vcs := Fake;
  Fake.SvnUrl := 'Kasse/trunk';
  Fake.Current := 'trunk';
  Options := TAtlasIssuesOptions.Create(TAtlasIssueStart.Branch, '', '', '');
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, Options, Issue('KASSE-42', 42, 'Bon drucken langsam'));
  Assert.AreEqual(cExecuteSvncName, Plan.Branch);
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Started);
  Assert.AreEqual('Kasse/trunk', Started.Base, 'Hauptbranch unter der Projektwurzel');
  Assert.AreEqual(3, Integer(Length(Fake.Calls)));
  Assert.AreEqual('exists ^/Kasse/branches/' + cExecuteSvncName, Fake.Calls[0]);
  Assert.AreEqual('run copy ^/Kasse/trunk@ ^/Kasse/branches/' + cExecuteSvncName +
    '@ --parents -m KASSE-42 Branch für Bon drucken langsam', Fake.Calls[1]);
  Assert.AreEqual('run switch ^/Kasse/branches/' + cExecuteSvncName + '@ .', Fake.Calls[2]);
  Assert.IsFalse(Started.IndexRebuild, 'ohne Externals kein neuer Index');
  // Zweites „Beginnen“ auf demselben Issue: findet ihn am selben Ort und schaltet nur um.
  Fake.Calls := nil;
  Fake.Current := 'Kasse/trunk';
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Switched);
  Assert.AreEqual(2, Integer(Length(Fake.Calls)));
  Assert.AreEqual('switch ^/Kasse/branches/' + cExecuteSvncName, Fake.Calls[1]);
  Assert.AreEqual('Kasse/branches/' + cExecuteSvncName, Fake.Current);
  // after = none: nur anlegen, die Arbeitskopie bleibt.
  Fake.Branches := nil;
  Fake.Calls := nil;
  Fake.Current := 'Kasse/trunk';
  Options.Svn.After := TAtlasVcsSvnAfter.None;
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, Options, Issue('KASSE-42', 42, 'Bon drucken langsam'));
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Started);
  Assert.AreEqual(2, Integer(Length(Fake.Calls)), 'kein switch');
  Assert.AreEqual('Kasse/trunk', Fake.Current);
  // after = checkout: das Ergebnis nennt Ordner und alte Wurzel für das Angebot, die Gruppe dort zu öffnen.
  Fake.Branches := nil;
  Fake.Calls := nil;
  Options.Svn.After := TAtlasVcsSvnAfter.Checkout;
  Options.Svn.Project := 'Kassengruppe';
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, Options, Issue('KASSE-42', 42, 'Bon drucken langsam'));
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Started);
  Assert.AreEqual(3, Integer(Length(Fake.Calls)));
  Assert.IsTrue(Fake.Calls[2].StartsWith('run checkout ^/Kasse/branches/' + cExecuteSvncName + '@ '), Fake.Calls[2]);
  Assert.AreEqual(Fake.WorkingCopy.Root, Started.WorkingRoot);
  Assert.AreEqual(ExpandFileName(IncludeTrailingPathDelimiter(Fake.WorkingCopy.Root) + '..' + PathDelim +
    'Kassengruppe-KASSE-42'), Started.CheckoutFolder);
  // Ohne erkennbares Layout: kein Ort, kein Serverschritt.
  Fake.Branches := nil;
  Fake.Calls := nil;
  Fake.SvnUrl := 'Kasse/Quellen';
  Started := TAtlasMyIssues.Execute(Vcs, Plan);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Failed);
  Assert.AreEqual(1, Integer(Length(Fake.Calls)));
  Assert.AreEqual('exists ?', Fake.Calls[0]);
  // #1291: Anfrage mit festgeschriebenem External und Umschalten: --pin-externals, danach Index neu.
  Fake.Branches := nil;
  Fake.Calls := nil;
  Fake.SvnUrl := 'Kasse/trunk';
  Fake.Current := 'Kasse/trunk';
  Options.Svn.After := TAtlasVcsSvnAfter.Switch;
  Plan := TAtlasMyIssues.PlanStart(TAtlasVcsKind.Svn, Options, Issue('KASSE-42', 42, 'Bon drucken langsam'));
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
  Assert.IsTrue(TAtlasVcsBranchPlan.ApplySvn(mRequest, mFacts, Options.Svn));
  TAtlasVcsBranchPlan.ApplyExternals(mRequest, mFacts, Options.Svn,
    TArray<TAtlasVcsExternalAction>.Create(TAtlasVcsExternalAction.Pin));
  Started := TAtlasMyIssues.Execute(Vcs, Plan, mRequest);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Started);
  Assert.IsTrue(Fake.Calls[1].EndsWith('--pin-externals'), Fake.Calls[1]);
  Assert.IsTrue(Started.IndexRebuild);
  // Nur anlegen: Die Arbeitskopie bleibt, der Index auch.
  Fake.Branches := nil;
  Fake.Calls := nil;
  mRequest.After := TAtlasVcsSvnAfter.None;
  Started := TAtlasMyIssues.Execute(Vcs, Plan, mRequest);
  Assert.IsTrue(Started.Outcome = TAtlasIssueStartOutcome.Started);
  Assert.IsFalse(Started.IndexRebuild);
  Fake.Branches := nil;
  Fake.Calls := nil;
  Started := Default(TAtlasIssueStartResult);
  mRequest := Default(TAtlasVcsBranchRequest);
  mFacts := TAtlasVcsBranchFacts.Empty;
end;

procedure TAtlasMyIssuesTests.VcsKindFromText;
begin
  Assert.IsTrue(TAtlasMyIssues.VcsKindOf('git') = TAtlasVcsKind.Git);
  Assert.IsTrue(TAtlasMyIssues.VcsKindOf('SVN') = TAtlasVcsKind.Svn);
  Assert.IsTrue(TAtlasMyIssues.VcsKindOf('none') = TAtlasVcsKind.None);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMyIssuesTests);

end.
