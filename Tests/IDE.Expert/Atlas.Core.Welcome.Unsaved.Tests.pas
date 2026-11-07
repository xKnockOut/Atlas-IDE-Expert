unit Atlas.Core.Welcome.Unsaved.Tests;

// Tests des Bereichs „Nicht gesichert“ ohne VCL (#762): Abfrage mit
// Ersatz-Umsetzungen für Git und SVN, Alter, Ampel, Sortierung, Ausblenden
// (Mindestalter, „Ignorieren bis morgen“), einmal je Arbeitskopie,
// Zusammenführen mit dem gespeicherten Stand, Abschnitt "unsaved" in der
// Projekt-Zusammenfassung und was „Push …“ pushen würde.
// Akzeptanzkriterien: Git mit 4 geänderten Dateien, 3 nicht gepushten Commits
// und einem Stash ergibt drei Zeilen mit Alter; SVN mit 2 geänderten Dateien
// eine Zeile ohne Push und Stash; ohne Versionsverwaltung keine Zeile und kein
// Fehler; älter als alertHours ist rot.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeUnsavedTests = class
  public
    [Test]
    procedure GitProjectShowsThreeRowsWithAge;
    [Test]
    procedure SvnProjectShowsOnlyChangedFiles;
    [Test]
    procedure ProjectWithoutVersionControlShowsNothing;
    [Test]
    procedure ProbeFailureKeepsStoredState;
    [Test]
    procedure ProbeCountsChangesBelowProjectFolderAndConflicts;
    /// <summary>#1292: Änderungen und Konflikte je Arbeitskopie (Wurzel und Externals aus svn status), nur
    /// eingeschaltet und bei mehr als einer Arbeitskopie; Text und Abschnitt "places".</summary>
    [Test]
    procedure ProbeSplitsChangesPerWorkingCopy;
    [Test]
    procedure ProbeSkipsBranchesWithoutLocalCommits;
    [Test]
    procedure ProbeStopsAtTimeLimit;
    [Test]
    procedure AgeUnits;
    [Test]
    procedure LevelFollowsWarnAndAlertHours;
    [Test]
    procedure OlderThanAlertIsRed;
    [Test]
    procedure SortsOldestFirst;
    [Test]
    procedure MinimumAgeAndIgnoreHideRows;
    [Test]
    procedure RepositoryWideRowsOncePerWorkingCopy;
    [Test]
    procedure MergeKeepsUnqueriedKindsAndFirstSeen;
    [Test]
    procedure MergeDropsExpiredIgnores;
    [Test]
    procedure TomorrowIsNextMidnight;
    [Test]
    procedure SectionRoundTripKeepsSummary;
    [Test]
    procedure PushPlansForCommitsAndBranchesWithoutUpstream;
    [Test]
    procedure PushPlansWithoutRemoteAreEmpty;
    [Test]
    procedure SettingsDefaultsAndLimits;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Internals.Text,
  Atlas.Core.Vcs.Providers.Null,
  Atlas.Core.Welcome.Unsaved;

const
  cRoot = 'C:\Repo';

type
  /// <summary>Ersatz für Git bzw. SVN: festgelegte Ergebnisse ohne Prozess, zählt die Aufrufe.</summary>
  TFakeVcs = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsLocalWork)
  public
    FKind: TAtlasVcsKind;
    FChangesOutcome: TAtlasVcsOutcome;
    FChanges: TArray<TAtlasVcsChange>;
    FHead: TAtlasVcsHead;
    FBranches: TArray<TAtlasVcsBranch>;
    FStashes: TArray<TAtlasVcsStash>;
    FRemotes: TArray<string>;
    // Branch → Commits (neueste zuerst) für Outgoing.
    FOutgoingBranch: TArray<string>;
    FOutgoingUpstream: TArray<string>;
    FOutgoing: TArray<TArray<TAtlasVcsCommit>>;
    Calls: TArray<string>;
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
    function Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
    function Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
    function Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
    function Outgoing(const ABranch, AUpstream: string; AMax: Integer;
      out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
    function ChangesIn(const ARevision: string; out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function Push(const ABranch, ARemote, ARemoteRef: string; ASetUpstream: Boolean): TAtlasVcsOutcome;
    procedure AddOutgoing(const ABranch, AUpstream: string; const ACommits: TArray<TAtlasVcsCommit>);
  end;

function TFakeVcs.Kind: TAtlasVcsKind;
begin
  Result := FKind;
end;

function TFakeVcs.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result.Kind := FKind;
  Result.Root := cRoot;
end;

function TFakeVcs.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  Calls := Calls + ['head'];
  AHead := FHead;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeVcs.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  Calls := Calls + ['changes'];
  AChanges := FChanges;
  Result := FChangesOutcome;
end;

function TFakeVcs.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeVcs.Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeVcs.ChangeMarker: string;
begin
  Result := '';
end;

function TFakeVcs.Branches(out ABranches: TArray<TAtlasVcsBranch>): TAtlasVcsOutcome;
begin
  Calls := Calls + ['branches'];
  ABranches := FBranches;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeVcs.Stashes(out AStashes: TArray<TAtlasVcsStash>): TAtlasVcsOutcome;
begin
  Calls := Calls + ['stashes'];
  AStashes := FStashes;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeVcs.Remotes(out ANames: TArray<string>): TAtlasVcsOutcome;
begin
  Calls := Calls + ['remotes'];
  ANames := FRemotes;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeVcs.Outgoing(const ABranch, AUpstream: string; AMax: Integer;
  out ACommits: TArray<TAtlasVcsCommit>): TAtlasVcsOutcome;
var
  mIndex: Integer;
begin
  Calls := Calls + ['outgoing ' + ABranch + ' ' + AUpstream];
  ACommits := nil;
  for mIndex := 0 to High(FOutgoingBranch) do
  begin
    if (FOutgoingBranch[mIndex] = ABranch) and (FOutgoingUpstream[mIndex] = AUpstream) then
    begin
      ACommits := Copy(FOutgoing[mIndex], 0, AMax);
      Break;
    end;
  end;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeVcs.ChangesIn(const ARevision: string; out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeVcs.Push(const ABranch, ARemote, ARemoteRef: string; ASetUpstream: Boolean): TAtlasVcsOutcome;
begin
  Calls := Calls + ['push'];
  Result := TAtlasVcsOutcome.Failed;
end;

type
  /// <summary>SVN mit svn status --xml der Wurzel (#1292).</summary>
  TFakeSvnStatus = class(TFakeVcs, IAtlasVcsSvnExternals)
  public
    StatusText: string;
    function StatusXml(out AText: string): TAtlasVcsOutcome;
    function Update(AIgnoreExternals: Boolean): TAtlasVcsOutcome;
    function CommitsSince(const APath, ARevision: string; out ACount: Integer): TAtlasVcsOutcome;
    function SetExternals(const AOwner, AText: string): TAtlasVcsOutcome;
  end;

function TFakeSvnStatus.StatusXml(out AText: string): TAtlasVcsOutcome;
begin
  Calls := Calls + ['status'];
  AText := StatusText;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeSvnStatus.Update(AIgnoreExternals: Boolean): TAtlasVcsOutcome;
begin
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeSvnStatus.CommitsSince(const APath, ARevision: string; out ACount: Integer): TAtlasVcsOutcome;
begin
  ACount := 0;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeSvnStatus.SetExternals(const AOwner, AText: string): TAtlasVcsOutcome;
begin
  Result := TAtlasVcsOutcome.Failed;
end;

procedure TFakeVcs.AddOutgoing(const ABranch, AUpstream: string; const ACommits: TArray<TAtlasVcsCommit>);
begin
  FOutgoingBranch := FOutgoingBranch + [ABranch];
  FOutgoingUpstream := FOutgoingUpstream + [AUpstream];
  FOutgoing := FOutgoing + [ACommits];
end;

{ Testdaten }

/// <summary>Zeitpunkte und Stunden vergleichen (ohne die Gleitkomma-Überladungen von Assert.AreEqual).</summary>
procedure AssertNear(AExpected, AActual, ATolerance: Double; const AMessage: string);
begin
  Assert.IsTrue(Abs(AExpected - AActual) <= ATolerance, Format('erwartet %g, war %g %s', [AExpected, AActual,
    AMessage]));
end;

function NowUtc: TDateTime;
begin
  Result := EncodeDate(2026, 10, 15) + EncodeTime(12, 0, 0, 0);
end;

function HoursAgo(AHours: Double): TDateTime;
begin
  Result := NowUtc - AHours / 24;
end;

function Change(const APath: string; AKind: TAtlasVcsChangeKind): TAtlasVcsChange;
begin
  Result := Default(TAtlasVcsChange);
  Result.Path := APath;
  Result.Kind := AKind;
  Result.Unstaged := True;
end;

function Branch(const AName, AUpstream: string; AAhead: Integer; ACurrent: Boolean): TAtlasVcsBranch;
begin
  Result := Default(TAtlasVcsBranch);
  Result.Name := AName;
  Result.Upstream := AUpstream;
  if AUpstream <> '' then
  begin
    Result.Remote := 'origin';
    Result.RemoteRef := 'refs/heads/' + AName;
    Result.Ahead := AAhead;
    Result.Behind := 0;
  end
  else
  begin
    Result.Ahead := -1;
    Result.Behind := -1;
  end;
  Result.TipDate := HoursAgo(1);
  Result.Current := ACurrent;
end;

function Commit(const AHash: string; AHoursAgo: Double): TAtlasVcsCommit;
begin
  Result.Hash := AHash;
  Result.Date := HoursAgo(AHoursAgo);
  Result.Summary := 'Commit ' + AHash;
end;

function Stash(const AHash, AMessage: string; AHoursAgo: Double): TAtlasVcsStash;
begin
  Result := Default(TAtlasVcsStash);
  Result.Hash := AHash;
  Result.Ref := 'stash@{0}';
  Result.Branch := 'main';
  Result.Message := AMessage;
  Result.Date := HoursAgo(AHoursAgo);
end;

/// <summary>Git: 4 geänderte Dateien (älteste vor 2 Tagen), 3 nicht gepushte Commits (ältester vor 30 Stunden),
/// ein Stash (vor 5 Stunden).</summary>
function GitFixture: TFakeVcs;
begin
  Result := TFakeVcs.Create;
  Result.FKind := TAtlasVcsKind.Git;
  Result.FChangesOutcome := TAtlasVcsOutcome.Ok;
  Result.FChanges := [Change(cRoot + '\Demo\A.pas', TAtlasVcsChangeKind.Modified),
    Change(cRoot + '\Demo\B.pas', TAtlasVcsChangeKind.Modified),
    Change(cRoot + '\Demo\Neu.pas', TAtlasVcsChangeKind.Untracked),
    Change(cRoot + '\Demo\Weg.pas', TAtlasVcsChangeKind.Deleted)];
  Result.FBranches := [Branch('main', 'origin/main', 3, True)];
  Result.AddOutgoing('main', 'origin/main', [Commit('c3', 2), Commit('c2', 10), Commit('c1', 30)]);
  Result.FStashes := [Stash('s1', 'WIP Hover-Cache', 5)];
end;

function FileTimes: TAtlasUnsavedFileTime;
begin
  Result :=
    function(const AFileName: string; out AUtc: TDateTime): Boolean
    begin
      Result := True;
      if SameText(ExtractFileName(AFileName), 'A.pas') then
      begin
        AUtc := HoursAgo(48);
      end
      else if SameText(ExtractFileName(AFileName), 'Weg.pas') then
      begin
        Result := False;
      end
      else
      begin
        AUtc := HoursAgo(3);
      end;
    end;
end;

function Project(const AProject: string; const AState: TAtlasUnsavedState): TAtlasUnsavedProject;
begin
  Result := Default(TAtlasUnsavedProject);
  Result.Project := AProject;
  Result.State := AState;
  Result.Fresh := True;
end;

function Options: TAtlasUnsavedOptions;
begin
  Result := TAtlasUnsavedOptions.Create(0, 24, 72);
end;

function GitState(const ARoot: string; const AItems: TArray<TAtlasUnsavedItem>): TAtlasUnsavedState;
begin
  Result := TAtlasUnsavedState.Empty;
  Result.Known := True;
  Result.At := NowUtc;
  Result.Kind := 'git';
  Result.Root := ARoot;
  Result.Branch := 'main';
  Result.Items := AItems;
end;

function Item(AKind: TAtlasUnsavedKind; ACount: Integer; AHoursAgo: Double): TAtlasUnsavedItem;
begin
  Result := TAtlasUnsavedItem.Create(AKind, ACount);
  if AHoursAgo >= 0 then
  begin
    Result.Since := HoursAgo(AHoursAgo);
  end;
end;

{ TAtlasWelcomeUnsavedTests }

procedure TAtlasWelcomeUnsavedTests.GitProjectShowsThreeRowsWithAge;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mState: TAtlasUnsavedState;
  mView: TAtlasUnsavedView;
  mValue: Integer;
  mAgeUnit: TAtlasUnsavedAgeUnit;
begin
  mFake := GitFixture;
  mVcs := mFake;
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(mVcs, cRoot + '\Demo', NowUtc, FileTimes(), nil, mState));
  Assert.AreEqual('git', mState.Kind);
  Assert.AreEqual(cRoot, mState.Root);
  Assert.AreEqual('main', mState.Branch, 'aktueller Branch aus der Branch-Liste');
  mState := TAtlasWelcomeUnsaved.Merge(TAtlasUnsavedState.Empty, mState, NowUtc);
  mView := TAtlasWelcomeUnsaved.View([Project('C:\Repo\Demo\Demo.dproj', mState)], NowUtc, Options);
  Assert.AreEqual(3, Integer(Length(mView.Rows)), 'Änderungen, Commits, Stash');
  // Älteste zuerst: Änderungen (48 h), Commits (30 h), Stash (5 h).
  Assert.IsTrue(mView.Rows[0].Item.Kind = TAtlasUnsavedKind.Changes);
  Assert.AreEqual(4, Integer(mView.Rows[0].Item.Count));
  Assert.AreEqual(2, mView.Rows[0].Item.Modified);
  Assert.AreEqual(1, mView.Rows[0].Item.Added);
  Assert.AreEqual(1, mView.Rows[0].Item.Deleted);
  TAtlasWelcomeUnsaved.Age(mView.Rows[0].Item.Since, NowUtc, mValue, mAgeUnit);
  Assert.AreEqual(2, mValue, 'seit 2 Tagen');
  Assert.IsTrue(mAgeUnit = TAtlasUnsavedAgeUnit.Days);
  Assert.IsTrue(mView.Rows[1].Item.Kind = TAtlasUnsavedKind.Commits);
  Assert.AreEqual(3, Integer(mView.Rows[1].Item.Count));
  Assert.AreEqual('main', mView.Rows[1].Item.Branches[0]);
  AssertNear(HoursAgo(30), mView.Rows[1].Item.Since, 1E-6, 'ältester nicht gepushter Commit');
  Assert.IsTrue(mView.Rows[1].Item.CanPush);
  Assert.IsTrue(mView.Rows[2].Item.Kind = TAtlasUnsavedKind.Stashes);
  Assert.AreEqual('WIP Hover-Cache', mView.Rows[2].Item.Name);
  Assert.AreEqual('s1', mView.Rows[2].Item.Ref);
  Assert.IsFalse(mView.Rows[2].Item.CanPush);
  Assert.AreEqual('Demo', mView.Rows[0].Name);
  Assert.AreEqual('main', mView.Rows[0].Branch);
  Assert.IsTrue(mView.Rows[0].Level = TAtlasUnsavedLevel.Warning, '48 h: gelb');
  Assert.IsTrue(mView.Rows[2].Level = TAtlasUnsavedLevel.Fresh, '5 h: grün');
  Assert.IsFalse(mView.Clean);
end;

procedure TAtlasWelcomeUnsavedTests.SvnProjectShowsOnlyChangedFiles;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mState: TAtlasUnsavedState;
  mView: TAtlasUnsavedView;
  mSvn: TAtlasVcsHead;
begin
  // SVN: Branches, Stashes und Outgoing leer (wie TAtlasSvnVersionControl), Pfad aus Head.
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.FKind := TAtlasVcsKind.Svn;
  mFake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  mFake.FChanges := [Change(cRoot + '\A.pas', TAtlasVcsChangeKind.Modified),
    Change(cRoot + '\B.pas', TAtlasVcsChangeKind.Modified)];
  mSvn := TAtlasVcsHead.Empty;
  mSvn.Branch := 'trunk';
  mSvn.Revision := '42';
  mFake.FHead := mSvn;
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(mVcs, cRoot, NowUtc, FileTimes(), nil, mState));
  Assert.AreEqual('svn', mState.Kind);
  Assert.AreEqual('trunk', mState.Branch);
  mState := TAtlasWelcomeUnsaved.Merge(TAtlasUnsavedState.Empty, mState, NowUtc);
  mView := TAtlasWelcomeUnsaved.View([Project('C:\Repo\Demo.dproj', mState)], NowUtc, Options);
  Assert.AreEqual(1, Integer(Length(mView.Rows)), 'keine Push- oder Stash-Zeile');
  Assert.IsTrue(mView.Rows[0].Item.Kind = TAtlasUnsavedKind.Changes);
  Assert.AreEqual(2, Integer(mView.Rows[0].Item.Count), '2 Dateien geändert');
  Assert.AreEqual(2, mView.Rows[0].Item.Modified);
  Assert.AreEqual(0, mView.Rows[0].Item.Added);
  Assert.AreEqual('svn', mView.Rows[0].VcsKind);
end;

procedure TAtlasWelcomeUnsavedTests.ProjectWithoutVersionControlShowsNothing;
var
  mVcs: IAtlasVersionControl;
  mState: TAtlasUnsavedState;
  mView: TAtlasUnsavedView;
begin
  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.NoWorkingCopy);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(mVcs, 'C:\Ohne', NowUtc, nil, nil, mState), 'kein Fehler');
  Assert.AreEqual('none', mState.Kind);
  Assert.IsFalse(mState.InWorkingCopy);
  mView := TAtlasWelcomeUnsaved.View([Project('C:\Ohne\Demo.dproj', mState)], NowUtc, Options);
  Assert.AreEqual(0, Integer(Length(mView.Rows)), 'erscheint nicht');
  Assert.IsTrue(mView.Clean);
  Assert.IsTrue(mView.Known);
  // Abgeschaltet (vcs.provider = off) wie ohne Arbeitskopie.
  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(mVcs, 'C:\Ohne', NowUtc, nil, nil, mState));
  Assert.AreEqual('none', mState.Kind);
  Assert.IsFalse(TAtlasWelcomeUnsaved.Probe(nil, 'C:\Ohne', NowUtc, nil, nil, mState), 'ohne Umsetzung');
end;

procedure TAtlasWelcomeUnsavedTests.ProbeFailureKeepsStoredState;
var
  mVcs: IAtlasVersionControl;
  mState: TAtlasUnsavedState;
begin
  // git fehlt bzw. Zeitlimit: kein Ergebnis, der gespeicherte Stand bleibt.
  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.ToolMissing);
  Assert.IsFalse(TAtlasWelcomeUnsaved.Probe(mVcs, cRoot, NowUtc, nil, nil, mState));
  Assert.IsFalse(mState.Known);
end;

procedure TAtlasWelcomeUnsavedTests.ProbeCountsChangesBelowProjectFolderAndConflicts;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mState: TAtlasUnsavedState;
  mFound: TAtlasUnsavedItem;
begin
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.FKind := TAtlasVcsKind.Git;
  mFake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  mFake.FChanges := [Change(cRoot + '\Demo\A.pas', TAtlasVcsChangeKind.Modified),
    Change(cRoot + '\Anderes\B.pas', TAtlasVcsChangeKind.Modified),
    Change(cRoot + '\Demo\K.pas', TAtlasVcsChangeKind.Conflicted),
    Change(cRoot + '\Demo\Weg.pas', TAtlasVcsChangeKind.Deleted)];
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(mVcs, cRoot + '\demo', NowUtc, FileTimes(), nil, mState));
  Assert.IsTrue(mState.Find(TAtlasUnsavedKind.Changes, mFound));
  Assert.AreEqual(2, Integer(mFound.Count), 'nur im Projektordner, ohne Konflikt');
  Assert.AreEqual(1, mFound.Deleted);
  AssertNear(HoursAgo(48), mFound.Since, 1E-6, '');
  Assert.IsTrue(mState.Find(TAtlasUnsavedKind.Conflicts, mFound));
  Assert.AreEqual(1, Integer(mFound.Count));
  Assert.IsTrue(TAtlasUnsavedKind.Changes in mState.Queried);
  Assert.IsTrue(TAtlasUnsavedKind.Stashes in mState.Queried);
  Assert.IsFalse(mState.Find(TAtlasUnsavedKind.Stashes, mFound), 'keine leeren Arten');
end;

procedure TAtlasWelcomeUnsavedTests.ProbeSplitsChangesPerWorkingCopy;
var
  mFake: TFakeSvnStatus;
  mVcs: IAtlasVersionControl;
  mState, mRead: TAtlasUnsavedState;
  mFound: TAtlasUnsavedItem;
  mSummary: TAtlasProjectSummary;
  mQuery: TAtlasUnsavedQuery;
begin
  mFake := TFakeSvnStatus.Create;
  mVcs := mFake;
  mFake.FKind := TAtlasVcsKind.Svn;
  mFake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  mFake.StatusText := '<?xml version="1.0"?><status><target path="."><entry path="Packages\Drucken">' +
    '<wc-status item="external" props="none"></wc-status></entry></target></status>';
  // Wie svn status der Wurzel: die Dateien des Externals stehen mit drin.
  mFake.FChanges := [Change(VcsFullPath(cRoot, 'Kasse.dpr'), TAtlasVcsChangeKind.Modified),
    Change(VcsFullPath(cRoot, 'Packages/Drucken/A.pas'), TAtlasVcsChangeKind.Modified),
    Change(VcsFullPath(cRoot, 'Packages/Drucken/B.pas'), TAtlasVcsChangeKind.Untracked),
    Change(VcsFullPath(cRoot, 'Packages/Drucken/K.pas'), TAtlasVcsChangeKind.Conflicted)];
  mQuery := TAtlasUnsavedQuery.Create('', NowUtc, nil, nil);
  mQuery.WorkingCopies := True;
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(mVcs, mQuery, mState));
  Assert.IsTrue(mState.Find(TAtlasUnsavedKind.Changes, mFound));
  Assert.AreEqual(3, Integer(mFound.Count), 'Summe aller Arbeitskopien');
  Assert.AreEqual(2, Integer(Length(mFound.Places)));
  Assert.AreEqual('', mFound.Places[0].Path);
  Assert.AreEqual(1, mFound.Places[0].Count);
  Assert.AreEqual('Packages/Drucken', mFound.Places[1].Path);
  Assert.AreEqual(2, mFound.Places[1].Count, 'auch unversionierte wie in der Summe');
  Assert.AreEqual('Kasse 1 · Packages\Drucken 2', TAtlasWelcomeUnsaved.PlacesText(mFound, 'Kasse'));
  Assert.IsTrue(mState.Find(TAtlasUnsavedKind.Conflicts, mFound));
  Assert.AreEqual(0, Integer(Length(mFound.Places)), 'nur eine Arbeitskopie betroffen');
  Assert.AreEqual('', TAtlasWelcomeUnsaved.PlacesText(mFound, 'Kasse'));
  // Abschnitt "places" übersteht Schreiben und Lesen.
  mSummary := TAtlasProjectSummary.Create('C:\Repo\Kasse.groupproj');
  TAtlasWelcomeUnsaved.Write(mSummary, mState);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Read(mSummary, mRead));
  Assert.IsTrue(mRead.Find(TAtlasUnsavedKind.Changes, mFound));
  Assert.AreEqual(2, Integer(Length(mFound.Places)));
  Assert.AreEqual('Packages/Drucken', mFound.Places[1].Path);
  Assert.AreEqual(2, mFound.Places[1].Count);
  // Abgeschaltet (vcs.externals.show aus): keine weitere Abfrage, keine Anteile.
  mFake.Calls := nil;
  mQuery.WorkingCopies := False;
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(mVcs, mQuery, mState));
  Assert.IsTrue(mState.Find(TAtlasUnsavedKind.Changes, mFound));
  Assert.AreEqual(0, Integer(Length(mFound.Places)));
  Assert.IsFalse(string.Join(',', mFake.Calls).Contains('status'));
  mFake.Calls := nil;
  mFake.FChanges := nil;
  mFake.StatusText := '';
end;

procedure TAtlasWelcomeUnsavedTests.ProbeSkipsBranchesWithoutLocalCommits;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mState: TAtlasUnsavedState;
  mFound: TAtlasUnsavedItem;
  mGone: TAtlasVcsBranch;
begin
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.FKind := TAtlasVcsKind.Git;
  mFake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  mGone := Branch('alt', 'origin/alt', 0, False);
  mGone.Gone := True;
  mFake.FBranches := [Branch('main', 'origin/main', 0, True), Branch('leer', '', 0, False),
    Branch('feature/x', '', 0, False), mGone];
  // "leer" liegt ganz auf einem Remote; "feature/x" hat zwei nur lokale Commits; "alt" (Upstream gelöscht) einen.
  mFake.AddOutgoing('feature/x', '', [Commit('b', 4), Commit('a', 50)]);
  mFake.AddOutgoing('alt', '', [Commit('z', 7)]);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(mVcs, cRoot, NowUtc, nil, nil, mState));
  Assert.IsFalse(mState.Find(TAtlasUnsavedKind.Commits, mFound), 'main gleichauf');
  Assert.IsTrue(mState.Find(TAtlasUnsavedKind.NoUpstream, mFound));
  Assert.AreEqual(2, Integer(mFound.Count), 'feature/x und alt');
  Assert.AreEqual(3, mFound.Commits);
  Assert.AreEqual('feature/x', mFound.Branches[0]);
  Assert.AreEqual('alt', mFound.Branches[1]);
  AssertNear(HoursAgo(50), mFound.Since, 1E-6, '');
end;

procedure TAtlasWelcomeUnsavedTests.ProbeStopsAtTimeLimit;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mState, mOld, mMerged: TAtlasUnsavedState;
  mFound: TAtlasUnsavedItem;
  mTicks: Integer;
begin
  mFake := GitFixture;
  mVcs := mFake;
  mTicks := 0;
  // Nach dem ersten Aufruf ist das Zeitlimit erreicht: nur noch Änderungen.
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(mVcs, cRoot, NowUtc, nil,
    function: Boolean
    begin
      Inc(mTicks);
      Result := True;
    end, mState));
  Assert.AreEqual(1, Integer(Length(mFake.Calls)), 'kein weiterer Aufruf');
  Assert.IsTrue(mTicks > 0);
  Assert.IsTrue(mState.Queried = [TAtlasUnsavedKind.Changes, TAtlasUnsavedKind.Conflicts]);
  // Was nicht abgefragt wurde, kommt aus dem gespeicherten Stand.
  mOld := GitState(cRoot, [Item(TAtlasUnsavedKind.Stashes, 2, 100), Item(TAtlasUnsavedKind.Changes, 9, 100)]);
  mMerged := TAtlasWelcomeUnsaved.Merge(mOld, mState, NowUtc);
  Assert.IsTrue(mMerged.Find(TAtlasUnsavedKind.Stashes, mFound));
  Assert.AreEqual(2, Integer(mFound.Count));
  Assert.IsTrue(mMerged.Find(TAtlasUnsavedKind.Changes, mFound));
  Assert.AreEqual(4, Integer(mFound.Count), 'Änderungen frisch');
end;

procedure TAtlasWelcomeUnsavedTests.AgeUnits;
var
  mValue: Integer;
  mAgeUnit: TAtlasUnsavedAgeUnit;
begin
  TAtlasWelcomeUnsaved.Age(NowUtc, NowUtc, mValue, mAgeUnit);
  Assert.AreEqual(1, mValue, 'mindestens 1 Minute');
  Assert.IsTrue(mAgeUnit = TAtlasUnsavedAgeUnit.Minutes);
  TAtlasWelcomeUnsaved.Age(HoursAgo(0.5), NowUtc, mValue, mAgeUnit);
  Assert.AreEqual(30, mValue);
  TAtlasWelcomeUnsaved.Age(HoursAgo(1), NowUtc, mValue, mAgeUnit);
  Assert.AreEqual(1, mValue);
  Assert.IsTrue(mAgeUnit = TAtlasUnsavedAgeUnit.Hours);
  TAtlasWelcomeUnsaved.Age(HoursAgo(23.9), NowUtc, mValue, mAgeUnit);
  Assert.AreEqual(23, mValue);
  TAtlasWelcomeUnsaved.Age(HoursAgo(24), NowUtc, mValue, mAgeUnit);
  Assert.AreEqual(1, mValue);
  Assert.IsTrue(mAgeUnit = TAtlasUnsavedAgeUnit.Days);
  TAtlasWelcomeUnsaved.Age(HoursAgo(24 * 9 + 5), NowUtc, mValue, mAgeUnit);
  Assert.AreEqual(9, mValue);
  AssertNear(0.0, TAtlasWelcomeUnsaved.AgeHours(0, NowUtc), 1E-9, 'unbekannt');
  AssertNear(0.0, TAtlasWelcomeUnsaved.AgeHours(NowUtc + 1, NowUtc), 1E-9, 'Zukunft (Uhr verstellt)');
end;

procedure TAtlasWelcomeUnsavedTests.LevelFollowsWarnAndAlertHours;
var
  mSettings: TAtlasUnsavedOptions;
begin
  mSettings := TAtlasUnsavedOptions.Create(0, 24, 72);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Level(HoursAgo(23), NowUtc, mSettings) = TAtlasUnsavedLevel.Fresh);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Level(HoursAgo(24), NowUtc, mSettings) = TAtlasUnsavedLevel.Warning,
    'gelb ab warnHours');
  Assert.IsTrue(TAtlasWelcomeUnsaved.Level(HoursAgo(71), NowUtc, mSettings) = TAtlasUnsavedLevel.Warning);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Level(HoursAgo(72), NowUtc, mSettings) = TAtlasUnsavedLevel.Alert,
    'rot ab alertHours');
  Assert.IsTrue(TAtlasWelcomeUnsaved.Level(0, NowUtc, mSettings) = TAtlasUnsavedLevel.Fresh, 'unbekannt');
  mSettings := TAtlasUnsavedOptions.Create(0, 1, 2);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Level(HoursAgo(1.5), NowUtc, mSettings) = TAtlasUnsavedLevel.Warning);
end;

procedure TAtlasWelcomeUnsavedTests.OlderThanAlertIsRed;
var
  mView: TAtlasUnsavedView;
begin
  mView := TAtlasWelcomeUnsaved.View([Project('C:\Repo\Demo.dproj',
    GitState(cRoot, [Item(TAtlasUnsavedKind.Changes, 1, 80)]))], NowUtc, Options);
  Assert.AreEqual(1, Integer(Length(mView.Rows)));
  Assert.IsTrue(mView.Rows[0].Level = TAtlasUnsavedLevel.Alert);
end;

procedure TAtlasWelcomeUnsavedTests.SortsOldestFirst;
var
  mView: TAtlasUnsavedView;
begin
  mView := TAtlasWelcomeUnsaved.View([
    Project('C:\A\Eins.dproj', GitState('C:\A', [Item(TAtlasUnsavedKind.Changes, 1, 2),
      Item(TAtlasUnsavedKind.Stashes, 1, 40), Item(TAtlasUnsavedKind.Commits, 2, -1)])),
    Project('C:\B\Zwei.dproj', GitState('C:\B', [Item(TAtlasUnsavedKind.Changes, 3, 10),
      Item(TAtlasUnsavedKind.Conflicts, 1, 10)]))], NowUtc, Options);
  Assert.AreEqual(5, Integer(Length(mView.Rows)));
  Assert.IsTrue(mView.Rows[0].Item.Kind = TAtlasUnsavedKind.Stashes, 'älteste zuerst');
  Assert.AreEqual('Zwei', mView.Rows[1].Name);
  Assert.IsTrue(mView.Rows[1].Item.Kind = TAtlasUnsavedKind.Changes, 'gleich alt: nach Art');
  Assert.IsTrue(mView.Rows[2].Item.Kind = TAtlasUnsavedKind.Conflicts);
  Assert.AreEqual('Eins', mView.Rows[3].Name);
  Assert.IsTrue(mView.Rows[3].Item.Kind = TAtlasUnsavedKind.Changes);
  Assert.IsTrue(mView.Rows[4].Item.Kind = TAtlasUnsavedKind.Commits, 'unbekanntes Alter zuletzt');
end;

procedure TAtlasWelcomeUnsavedTests.MinimumAgeAndIgnoreHideRows;
var
  mState: TAtlasUnsavedState;
  mView: TAtlasUnsavedView;
begin
  mState := GitState(cRoot, [Item(TAtlasUnsavedKind.Changes, 1, 2), Item(TAtlasUnsavedKind.Stashes, 1, 30),
    Item(TAtlasUnsavedKind.Commits, 1, 50)]);
  mView := TAtlasWelcomeUnsaved.View([Project('C:\Repo\Demo.dproj', mState)], NowUtc,
    TAtlasUnsavedOptions.Create(4, 24, 72));
  Assert.AreEqual(2, Integer(Length(mView.Rows)), 'jünger als minAgeHours entfällt');
  Assert.AreEqual(1, mView.Hidden);
  TAtlasWelcomeUnsaved.Ignore(mState, TAtlasUnsavedKind.Stashes, NowUtc + 0.5);
  TAtlasWelcomeUnsaved.Ignore(mState, TAtlasUnsavedKind.Commits, NowUtc - 0.1);
  mView := TAtlasWelcomeUnsaved.View([Project('C:\Repo\Demo.dproj', mState)], NowUtc,
    TAtlasUnsavedOptions.Create(4, 24, 72));
  Assert.AreEqual(1, Integer(Length(mView.Rows)), 'Stash bis morgen ignoriert, Commits wieder da');
  Assert.IsTrue(mView.Rows[0].Item.Kind = TAtlasUnsavedKind.Commits);
  Assert.AreEqual(2, mView.Hidden);
  // Alles ausgeblendet: nichts zu zeigen, aber nicht „alles gesichert“ im Sinne von keinen Einträgen.
  TAtlasWelcomeUnsaved.Ignore(mState, TAtlasUnsavedKind.Commits, NowUtc + 0.5);
  mView := TAtlasWelcomeUnsaved.View([Project('C:\Repo\Demo.dproj', mState)], NowUtc,
    TAtlasUnsavedOptions.Create(4, 24, 72));
  Assert.IsTrue(mView.Clean);
  Assert.AreEqual(3, mView.Hidden);
end;

procedure TAtlasWelcomeUnsavedTests.RepositoryWideRowsOncePerWorkingCopy;
var
  mView: TAtlasUnsavedView;
begin
  // Projektgruppe und Projekt in derselben Arbeitskopie: Commits und Stash einmal, Änderungen je Projekt.
  mView := TAtlasWelcomeUnsaved.View([
    Project('C:\Repo\Gruppe.groupproj', GitState('C:\Repo', [Item(TAtlasUnsavedKind.Changes, 2, 5),
      Item(TAtlasUnsavedKind.Commits, 3, 6), Item(TAtlasUnsavedKind.Stashes, 1, 7)])),
    Project('C:\Repo\Tests\Tests.dproj', GitState('c:\repo', [Item(TAtlasUnsavedKind.Changes, 1, 5),
      Item(TAtlasUnsavedKind.Commits, 3, 6), Item(TAtlasUnsavedKind.Stashes, 1, 7)]))], NowUtc, Options);
  Assert.AreEqual(4, Integer(Length(mView.Rows)));
  Assert.AreEqual('Gruppe', mView.Rows[0].Name, 'Stash beim zuerst genannten Projekt');
  Assert.IsTrue(mView.Rows[0].Item.Kind = TAtlasUnsavedKind.Stashes);
  Assert.AreEqual('Gruppe', mView.Rows[1].Name);
  Assert.IsTrue(mView.Rows[1].Item.Kind = TAtlasUnsavedKind.Commits);
  Assert.AreEqual('Gruppe', mView.Rows[2].Name);
  Assert.AreEqual('Tests', mView.Rows[3].Name);
end;

procedure TAtlasWelcomeUnsavedTests.MergeKeepsUnqueriedKindsAndFirstSeen;
var
  mOld, mNew_, mMerged: TAtlasUnsavedState;
  mFound: TAtlasUnsavedItem;
begin
  mOld := GitState(cRoot, [Item(TAtlasUnsavedKind.Changes, 2, 20)]);
  // Nur gelöschte Dateien: Alter unbekannt; gilt seit der ersten Sicht.
  mNew_ := GitState(cRoot, [Item(TAtlasUnsavedKind.Changes, 3, -1), Item(TAtlasUnsavedKind.Conflicts, 1, -1)]);
  mNew_.Queried := [TAtlasUnsavedKind.Changes, TAtlasUnsavedKind.Conflicts];
  mMerged := TAtlasWelcomeUnsaved.Merge(mOld, mNew_, NowUtc);
  Assert.IsTrue(mMerged.Find(TAtlasUnsavedKind.Changes, mFound));
  Assert.AreEqual(3, Integer(mFound.Count));
  AssertNear(HoursAgo(20), mFound.Since, 1E-6, 'seit der ersten Sicht');
  Assert.IsTrue(mMerged.Find(TAtlasUnsavedKind.Conflicts, mFound));
  AssertNear(NowUtc, mFound.Since, 1E-6, 'neu: jetzt');
  // Andere Arbeitskopie: nichts übernehmen.
  mOld.Root := 'C:\Anders';
  mMerged := TAtlasWelcomeUnsaved.Merge(mOld, mNew_, NowUtc);
  Assert.IsTrue(mMerged.Find(TAtlasUnsavedKind.Changes, mFound));
  AssertNear(NowUtc, mFound.Since, 1E-6, '');
end;

procedure TAtlasWelcomeUnsavedTests.MergeDropsExpiredIgnores;
var
  mOld, mNew_, mMerged: TAtlasUnsavedState;
begin
  mOld := GitState(cRoot, nil);
  TAtlasWelcomeUnsaved.Ignore(mOld, TAtlasUnsavedKind.Changes, NowUtc + 0.2);
  TAtlasWelcomeUnsaved.Ignore(mOld, TAtlasUnsavedKind.Stashes, NowUtc - 0.2);
  mNew_ := GitState(cRoot, nil);
  mMerged := TAtlasWelcomeUnsaved.Merge(mOld, mNew_, NowUtc);
  Assert.AreEqual(1, Integer(Length(mMerged.Ignored)));
  Assert.IsTrue(mMerged.IgnoredUntil(TAtlasUnsavedKind.Changes) > NowUtc);
  AssertNear(0.0, Double(mMerged.IgnoredUntil(TAtlasUnsavedKind.Stashes)), 1E-9, '');
end;

procedure TAtlasWelcomeUnsavedTests.TomorrowIsNextMidnight;
begin
  AssertNear(EncodeDate(2026, 10, 16), TAtlasWelcomeUnsaved.Tomorrow(EncodeDate(2026, 10, 15) +
    EncodeTime(23, 59, 0, 0)), 1E-9, '');
  AssertNear(EncodeDate(2026, 10, 16), TAtlasWelcomeUnsaved.Tomorrow(EncodeDate(2026, 10, 15)), 1E-9, '');
end;

/// <summary>Der gelesene Abschnitt trägt alle Einträge.</summary>
procedure AssertUnsavedRead(const AParsed: TAtlasProjectSummary);
var
  mRead: TAtlasUnsavedState;
  mFound: TAtlasUnsavedItem;
begin
  Assert.IsTrue(TAtlasWelcomeUnsaved.Read(AParsed, mRead));
  Assert.IsTrue(mRead.Known);
  Assert.AreEqual('git', mRead.Kind);
  Assert.AreEqual(cRoot, mRead.Root);
  Assert.AreEqual('main', mRead.Branch);
  AssertNear(NowUtc, mRead.At, 1E-6, '');
  Assert.AreEqual(3, Integer(Length(mRead.Items)));
  Assert.IsTrue(mRead.Find(TAtlasUnsavedKind.Changes, mFound));
  Assert.AreEqual(4, Integer(mFound.Count));
  Assert.AreEqual(2, mFound.Modified);
  Assert.AreEqual(1, mFound.Added);
  Assert.AreEqual(1, mFound.Deleted);
  AssertNear(HoursAgo(48), mFound.Since, 1 / (24 * 3600), '');
  Assert.IsTrue(mRead.Find(TAtlasUnsavedKind.NoUpstream, mFound));
  Assert.AreEqual(2, mFound.Commits);
  Assert.AreEqual('feature/x', mFound.Branches[0]);
  Assert.IsTrue(mRead.Find(TAtlasUnsavedKind.Stashes, mFound));
  Assert.AreEqual('WIP „Hover“', mFound.Name);
  Assert.AreEqual('abc', mFound.Ref);
  Assert.IsTrue(mRead.IgnoredUntil(TAtlasUnsavedKind.Stashes) > NowUtc);
end;

/// <summary>Zweimal schreiben, neue Zusammenfassung und unbekannte Arten.</summary>
procedure AssertUnsavedRewrite(const AParsed: TAtlasProjectSummary; const AState: TAtlasUnsavedState);
var
  mSummary: TAtlasProjectSummary;
  mParsed: TAtlasProjectSummary;
  mState: TAtlasUnsavedState;
  mRead: TAtlasUnsavedState;
begin
  mParsed := AParsed;
  mState := AState;
  // Zweimal schreiben ersetzt den Abschnitt.
  mState.Items := nil;
  TAtlasWelcomeUnsaved.Write(mParsed, mState);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Read(mParsed, mRead));
  Assert.AreEqual(0, Integer(Length(mRead.Items)));
  // Neue Zusammenfassung ohne Datei.
  mSummary := TAtlasProjectSummary.Create('C:\Neu\Neu.dproj');
  Assert.IsFalse(TAtlasWelcomeUnsaved.Read(mSummary, mRead));
  TAtlasWelcomeUnsaved.Write(mSummary, GitState(cRoot, nil));
  Assert.IsTrue(TAtlasProjectSummaries.Parse(TAtlasProjectSummaries.ToJson(mSummary), mParsed));
  Assert.AreEqual('C:\Neu\Neu.dproj', mParsed.Project);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Read(mParsed, mRead));
  // Unbekannte Arten einer späteren Fassung werden übergangen.
  Assert.IsTrue(TAtlasWelcomeUnsaved.FromJson('{"kind":"git","items":[{"kind":"neu","count":1},' +
    '{"kind":"stashes","count":2}]}', mRead));
  Assert.AreEqual(1, Integer(Length(mRead.Items)));
  Assert.IsFalse(TAtlasWelcomeUnsaved.FromJson('kein json', mRead));
end;

procedure TAtlasWelcomeUnsavedTests.SectionRoundTripKeepsSummary;
var
  mSummary, mParsed: TAtlasProjectSummary;
  mState: TAtlasUnsavedState;
  mLonely: TAtlasUnsavedItem;
  mChanges: TAtlasUnsavedItem;
  mJson: string;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"format":1,"project":"C:\\Repo\\Demo.dproj","hidden":true,' +
    '"vcs":{"kind":"git","branch":"main","changed":2},"history":{"x":1}}', mSummary));
  mChanges := Item(TAtlasUnsavedKind.Changes, 4, 48);
  mChanges.Modified := 2;
  mChanges.Added := 1;
  mChanges.Deleted := 1;
  mLonely := Item(TAtlasUnsavedKind.NoUpstream, 1, 50);
  mLonely.Commits := 2;
  mLonely.Branches := ['feature/x'];
  mState := GitState(cRoot, [mChanges, mLonely, Item(TAtlasUnsavedKind.Stashes, 1, 5)]);
  mState.Items[2].Name := 'WIP „Hover“';
  mState.Items[2].Ref := 'abc';
  TAtlasWelcomeUnsaved.Ignore(mState, TAtlasUnsavedKind.Stashes, NowUtc + 0.5);
  TAtlasWelcomeUnsaved.Write(mSummary, mState);
  mJson := TAtlasProjectSummaries.ToJson(mSummary);
  Assert.Contains(mJson, '"history"', 'fremde Abschnitte bleiben');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(mJson, mParsed));
  Assert.IsTrue(mParsed.Hidden, 'bekannte Felder bleiben');
  Assert.AreEqual('main', mParsed.Vcs.Branch);
  AssertUnsavedRead(mParsed);
  AssertUnsavedRewrite(mParsed, mState);
end;

procedure TAtlasWelcomeUnsavedTests.PushPlansForCommitsAndBranchesWithoutUpstream;
var
  mFake: TFakeVcs;
  mLocal: IAtlasVcsLocalWork;
  mPlans: TArray<TAtlasUnsavedPush>;
  mPending, mLonely: TAtlasUnsavedItem;
  mMany: TArray<TAtlasVcsCommit>;
  mIndex: Integer;
begin
  mFake := TFakeVcs.Create;
  mLocal := mFake;
  mFake.FKind := TAtlasVcsKind.Git;
  mFake.FBranches := [Branch('main', 'origin/main', 3, True), Branch('dev', 'origin/dev', 0, False),
    Branch('feature/x', '', 0, False)];
  mFake.FRemotes := ['origin'];
  mFake.AddOutgoing('main', 'origin/main', [Commit('c3', 1), Commit('c2', 2), Commit('c1', 3)]);
  mMany := nil;
  for mIndex := 1 to TAtlasWelcomeUnsaved.cPushListMax + 5 do
  begin
    mMany := mMany + [Commit('x' + IntToStr(mIndex), mIndex)];
  end;
  mFake.AddOutgoing('feature/x', '', mMany);
  mPending := Item(TAtlasUnsavedKind.Commits, 3, 3);
  mPending.Branches := ['main', 'dev'];
  Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(mLocal, mPending, mPlans) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(1, Integer(Length(mPlans)), 'dev ist gleichauf');
  Assert.AreEqual('main', mPlans[0].Branch);
  Assert.AreEqual('origin', mPlans[0].Remote);
  Assert.AreEqual('refs/heads/main', mPlans[0].RemoteRef);
  Assert.AreEqual('origin/main', mPlans[0].Target);
  Assert.IsFalse(mPlans[0].SetUpstream);
  Assert.AreEqual(3, Integer(Length(mPlans[0].Commits)));
  Assert.AreEqual('c3', mPlans[0].Commits[0].Hash, 'neueste zuerst');
  Assert.IsFalse(mPlans[0].More);
  Assert.IsFalse(mFake.Calls[High(mFake.Calls)] = 'push', 'nur geplant, nicht gepusht');
  mLonely := Item(TAtlasUnsavedKind.NoUpstream, 1, 3);
  mLonely.Branches := ['feature/x'];
  Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(mLocal, mLonely, mPlans) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(1, Integer(Length(mPlans)));
  Assert.AreEqual('origin', mPlans[0].Remote, 'einziges Remote');
  Assert.AreEqual('origin/feature/x', mPlans[0].Target);
  Assert.IsTrue(mPlans[0].SetUpstream);
  Assert.AreEqual(TAtlasWelcomeUnsaved.cPushListMax, Integer(Length(mPlans[0].Commits)));
  Assert.IsTrue(mPlans[0].More);
  Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(mLocal, Item(TAtlasUnsavedKind.Stashes, 1, 1), mPlans) =
    TAtlasVcsOutcome.Failed, 'Stash wird nicht gepusht');
end;

procedure TAtlasWelcomeUnsavedTests.PushPlansWithoutRemoteAreEmpty;
var
  mFake: TFakeVcs;
  mLocal: IAtlasVcsLocalWork;
  mPlans: TArray<TAtlasUnsavedPush>;
  mLonely: TAtlasUnsavedItem;
begin
  mFake := TFakeVcs.Create;
  mLocal := mFake;
  mFake.FKind := TAtlasVcsKind.Git;
  mFake.FBranches := [Branch('feature/x', '', 0, True)];
  mFake.AddOutgoing('feature/x', '', [Commit('a', 1)]);
  mLonely := Item(TAtlasUnsavedKind.NoUpstream, 1, 1);
  mLonely.Branches := ['feature/x'];
  // Kein Remote: kein Ziel.
  Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(mLocal, mLonely, mPlans) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(0, Integer(Length(mPlans)));
  // Mehrere Remotes ohne "origin": kein eindeutiges Ziel.
  mFake.FRemotes := ['a', 'b'];
  Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(mLocal, mLonely, mPlans) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(0, Integer(Length(mPlans)));
  mFake.FRemotes := ['upstream', 'origin'];
  Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(mLocal, mLonely, mPlans) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(1, Integer(Length(mPlans)));
  Assert.AreEqual('origin', mPlans[0].Remote);
end;

procedure TAtlasWelcomeUnsavedTests.SettingsDefaultsAndLimits;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.WelcomePageUnsaved, 'welcomePage.unsaved an');
  Assert.AreEqual(0, mSettings.WelcomePageUnsavedMinAgeHours);
  Assert.AreEqual(24, mSettings.WelcomePageUnsavedWarnHours);
  Assert.AreEqual(72, mSettings.WelcomePageUnsavedAlertHours);
  Assert.IsFalse(mSettings.WelcomePageUnsavedHideWhenClean);
  mSettings.WelcomePageUnsavedMinAgeHours := -5;
  mSettings.WelcomePageUnsavedWarnHours := 100000;
  mSettings.WelcomePageUnsavedAlertHours := 10;
  mSettings.Normalize;
  Assert.AreEqual(0, mSettings.WelcomePageUnsavedMinAgeHours);
  Assert.AreEqual(TAtlasWelcomeUnsaved.cMaxHours, mSettings.WelcomePageUnsavedWarnHours);
  Assert.AreEqual(TAtlasWelcomeUnsaved.cMaxHours, mSettings.WelcomePageUnsavedAlertHours, 'rot nie vor gelb');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeUnsavedTests);

end.
