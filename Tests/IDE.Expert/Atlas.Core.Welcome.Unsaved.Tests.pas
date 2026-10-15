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
  Atlas.Core.Vcs.Providers.Null,
  Atlas.Core.Welcome.Unsaved;

const
  Root = 'C:\Repo';

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
  Result.Root := Root;
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
  Index: Integer;
begin
  Calls := Calls + ['outgoing ' + ABranch + ' ' + AUpstream];
  ACommits := nil;
  for Index := 0 to High(FOutgoingBranch) do
    if (FOutgoingBranch[Index] = ABranch) and (FOutgoingUpstream[Index] = AUpstream) then
    begin
      ACommits := Copy(FOutgoing[Index], 0, AMax);
      Break;
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
  Result.FChanges := [Change(Root + '\Demo\A.pas', TAtlasVcsChangeKind.Modified),
    Change(Root + '\Demo\B.pas', TAtlasVcsChangeKind.Modified),
    Change(Root + '\Demo\Neu.pas', TAtlasVcsChangeKind.Untracked),
    Change(Root + '\Demo\Weg.pas', TAtlasVcsChangeKind.Deleted)];
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
        AUtc := HoursAgo(48)
      else if SameText(ExtractFileName(AFileName), 'Weg.pas') then
        Result := False
      else
        AUtc := HoursAgo(3);
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
    Result.Since := HoursAgo(AHoursAgo);
end;

{ TAtlasWelcomeUnsavedTests }

procedure TAtlasWelcomeUnsavedTests.GitProjectShowsThreeRowsWithAge;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasUnsavedState;
  View: TAtlasUnsavedView;
  Value: Integer;
  AgeUnit: TAtlasUnsavedAgeUnit;
begin
  Fake := GitFixture;
  Vcs := Fake;
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(Vcs, Root + '\Demo', NowUtc, FileTimes(), nil, State));
  Assert.AreEqual('git', State.Kind);
  Assert.AreEqual(Root, State.Root);
  Assert.AreEqual('main', State.Branch, 'aktueller Branch aus der Branch-Liste');
  State := TAtlasWelcomeUnsaved.Merge(TAtlasUnsavedState.Empty, State, NowUtc);
  View := TAtlasWelcomeUnsaved.View([Project('C:\Repo\Demo\Demo.dproj', State)], NowUtc, Options);
  Assert.AreEqual(3, Integer(Length(View.Rows)), 'Änderungen, Commits, Stash');
  // Älteste zuerst: Änderungen (48 h), Commits (30 h), Stash (5 h).
  Assert.IsTrue(View.Rows[0].Item.Kind = TAtlasUnsavedKind.Changes);
  Assert.AreEqual(4, View.Rows[0].Item.Count);
  Assert.AreEqual(2, View.Rows[0].Item.Modified);
  Assert.AreEqual(1, View.Rows[0].Item.Added);
  Assert.AreEqual(1, View.Rows[0].Item.Deleted);
  TAtlasWelcomeUnsaved.Age(View.Rows[0].Item.Since, NowUtc, Value, AgeUnit);
  Assert.AreEqual(2, Value, 'seit 2 Tagen');
  Assert.IsTrue(AgeUnit = TAtlasUnsavedAgeUnit.Days);
  Assert.IsTrue(View.Rows[1].Item.Kind = TAtlasUnsavedKind.Commits);
  Assert.AreEqual(3, View.Rows[1].Item.Count);
  Assert.AreEqual('main', View.Rows[1].Item.Branches[0]);
  AssertNear(HoursAgo(30), View.Rows[1].Item.Since, 1E-6, 'ältester nicht gepushter Commit');
  Assert.IsTrue(View.Rows[1].Item.CanPush);
  Assert.IsTrue(View.Rows[2].Item.Kind = TAtlasUnsavedKind.Stashes);
  Assert.AreEqual('WIP Hover-Cache', View.Rows[2].Item.Name);
  Assert.AreEqual('s1', View.Rows[2].Item.Ref);
  Assert.IsFalse(View.Rows[2].Item.CanPush);
  Assert.AreEqual('Demo', View.Rows[0].Name);
  Assert.AreEqual('main', View.Rows[0].Branch);
  Assert.IsTrue(View.Rows[0].Level = TAtlasUnsavedLevel.Warning, '48 h: gelb');
  Assert.IsTrue(View.Rows[2].Level = TAtlasUnsavedLevel.Fresh, '5 h: grün');
  Assert.IsFalse(View.Clean);
end;

procedure TAtlasWelcomeUnsavedTests.SvnProjectShowsOnlyChangedFiles;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasUnsavedState;
  View: TAtlasUnsavedView;
  Svn: TAtlasVcsHead;
begin
  // SVN: Branches, Stashes und Outgoing leer (wie TAtlasSvnVersionControl), Pfad aus Head.
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FKind := TAtlasVcsKind.Svn;
  Fake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  Fake.FChanges := [Change(Root + '\A.pas', TAtlasVcsChangeKind.Modified),
    Change(Root + '\B.pas', TAtlasVcsChangeKind.Modified)];
  Svn := TAtlasVcsHead.Empty;
  Svn.Branch := 'trunk';
  Svn.Revision := '42';
  Fake.FHead := Svn;
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(Vcs, Root, NowUtc, FileTimes(), nil, State));
  Assert.AreEqual('svn', State.Kind);
  Assert.AreEqual('trunk', State.Branch);
  State := TAtlasWelcomeUnsaved.Merge(TAtlasUnsavedState.Empty, State, NowUtc);
  View := TAtlasWelcomeUnsaved.View([Project('C:\Repo\Demo.dproj', State)], NowUtc, Options);
  Assert.AreEqual(1, Integer(Length(View.Rows)), 'keine Push- oder Stash-Zeile');
  Assert.IsTrue(View.Rows[0].Item.Kind = TAtlasUnsavedKind.Changes);
  Assert.AreEqual(2, View.Rows[0].Item.Count, '2 Dateien geändert');
  Assert.AreEqual(2, View.Rows[0].Item.Modified);
  Assert.AreEqual(0, View.Rows[0].Item.Added);
  Assert.AreEqual('svn', View.Rows[0].VcsKind);
end;

procedure TAtlasWelcomeUnsavedTests.ProjectWithoutVersionControlShowsNothing;
var
  Vcs: IAtlasVersionControl;
  State: TAtlasUnsavedState;
  View: TAtlasUnsavedView;
begin
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.NoWorkingCopy);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(Vcs, 'C:\Ohne', NowUtc, nil, nil, State), 'kein Fehler');
  Assert.AreEqual('none', State.Kind);
  Assert.IsFalse(State.InWorkingCopy);
  View := TAtlasWelcomeUnsaved.View([Project('C:\Ohne\Demo.dproj', State)], NowUtc, Options);
  Assert.AreEqual(0, Integer(Length(View.Rows)), 'erscheint nicht');
  Assert.IsTrue(View.Clean);
  Assert.IsTrue(View.Known);
  // Abgeschaltet (vcs.provider = off) wie ohne Arbeitskopie.
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(Vcs, 'C:\Ohne', NowUtc, nil, nil, State));
  Assert.AreEqual('none', State.Kind);
  Assert.IsFalse(TAtlasWelcomeUnsaved.Probe(nil, 'C:\Ohne', NowUtc, nil, nil, State), 'ohne Umsetzung');
end;

procedure TAtlasWelcomeUnsavedTests.ProbeFailureKeepsStoredState;
var
  Vcs: IAtlasVersionControl;
  State: TAtlasUnsavedState;
begin
  // git fehlt bzw. Zeitlimit: kein Ergebnis, der gespeicherte Stand bleibt.
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.ToolMissing);
  Assert.IsFalse(TAtlasWelcomeUnsaved.Probe(Vcs, Root, NowUtc, nil, nil, State));
  Assert.IsFalse(State.Known);
end;

procedure TAtlasWelcomeUnsavedTests.ProbeCountsChangesBelowProjectFolderAndConflicts;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasUnsavedState;
  Found: TAtlasUnsavedItem;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FKind := TAtlasVcsKind.Git;
  Fake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  Fake.FChanges := [Change(Root + '\Demo\A.pas', TAtlasVcsChangeKind.Modified),
    Change(Root + '\Anderes\B.pas', TAtlasVcsChangeKind.Modified),
    Change(Root + '\Demo\K.pas', TAtlasVcsChangeKind.Conflicted),
    Change(Root + '\Demo\Weg.pas', TAtlasVcsChangeKind.Deleted)];
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(Vcs, Root + '\demo', NowUtc, FileTimes(), nil, State));
  Assert.IsTrue(State.Find(TAtlasUnsavedKind.Changes, Found));
  Assert.AreEqual(2, Found.Count, 'nur im Projektordner, ohne Konflikt');
  Assert.AreEqual(1, Found.Deleted);
  AssertNear(HoursAgo(48), Found.Since, 1E-6, '');
  Assert.IsTrue(State.Find(TAtlasUnsavedKind.Conflicts, Found));
  Assert.AreEqual(1, Found.Count);
  Assert.IsTrue(TAtlasUnsavedKind.Changes in State.Queried);
  Assert.IsTrue(TAtlasUnsavedKind.Stashes in State.Queried);
  Assert.IsFalse(State.Find(TAtlasUnsavedKind.Stashes, Found), 'keine leeren Arten');
end;

procedure TAtlasWelcomeUnsavedTests.ProbeSkipsBranchesWithoutLocalCommits;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasUnsavedState;
  Found: TAtlasUnsavedItem;
  Gone: TAtlasVcsBranch;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FKind := TAtlasVcsKind.Git;
  Fake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  Gone := Branch('alt', 'origin/alt', 0, False);
  Gone.Gone := True;
  Fake.FBranches := [Branch('main', 'origin/main', 0, True), Branch('leer', '', 0, False),
    Branch('feature/x', '', 0, False), Gone];
  // "leer" liegt ganz auf einem Remote; "feature/x" hat zwei nur lokale Commits; "alt" (Upstream gelöscht) einen.
  Fake.AddOutgoing('feature/x', '', [Commit('b', 4), Commit('a', 50)]);
  Fake.AddOutgoing('alt', '', [Commit('z', 7)]);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(Vcs, Root, NowUtc, nil, nil, State));
  Assert.IsFalse(State.Find(TAtlasUnsavedKind.Commits, Found), 'main gleichauf');
  Assert.IsTrue(State.Find(TAtlasUnsavedKind.NoUpstream, Found));
  Assert.AreEqual(2, Found.Count, 'feature/x und alt');
  Assert.AreEqual(3, Found.Commits);
  Assert.AreEqual('feature/x', Found.Branches[0]);
  Assert.AreEqual('alt', Found.Branches[1]);
  AssertNear(HoursAgo(50), Found.Since, 1E-6, '');
end;

procedure TAtlasWelcomeUnsavedTests.ProbeStopsAtTimeLimit;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State, Old, Merged: TAtlasUnsavedState;
  Found: TAtlasUnsavedItem;
  Ticks: Integer;
begin
  Fake := GitFixture;
  Vcs := Fake;
  Ticks := 0;
  // Nach dem ersten Aufruf ist das Zeitlimit erreicht: nur noch Änderungen.
  Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(Vcs, Root, NowUtc, nil,
    function: Boolean
    begin
      Inc(Ticks);
      Result := True;
    end, State));
  Assert.AreEqual(1, Integer(Length(Fake.Calls)), 'kein weiterer Aufruf');
  Assert.IsTrue(Ticks > 0);
  Assert.IsTrue(State.Queried = [TAtlasUnsavedKind.Changes, TAtlasUnsavedKind.Conflicts]);
  // Was nicht abgefragt wurde, kommt aus dem gespeicherten Stand.
  Old := GitState(Root, [Item(TAtlasUnsavedKind.Stashes, 2, 100), Item(TAtlasUnsavedKind.Changes, 9, 100)]);
  Merged := TAtlasWelcomeUnsaved.Merge(Old, State, NowUtc);
  Assert.IsTrue(Merged.Find(TAtlasUnsavedKind.Stashes, Found));
  Assert.AreEqual(2, Found.Count);
  Assert.IsTrue(Merged.Find(TAtlasUnsavedKind.Changes, Found));
  Assert.AreEqual(4, Found.Count, 'Änderungen frisch');
end;

procedure TAtlasWelcomeUnsavedTests.AgeUnits;
var
  Value: Integer;
  AgeUnit: TAtlasUnsavedAgeUnit;
begin
  TAtlasWelcomeUnsaved.Age(NowUtc, NowUtc, Value, AgeUnit);
  Assert.AreEqual(1, Value, 'mindestens 1 Minute');
  Assert.IsTrue(AgeUnit = TAtlasUnsavedAgeUnit.Minutes);
  TAtlasWelcomeUnsaved.Age(HoursAgo(0.5), NowUtc, Value, AgeUnit);
  Assert.AreEqual(30, Value);
  TAtlasWelcomeUnsaved.Age(HoursAgo(1), NowUtc, Value, AgeUnit);
  Assert.AreEqual(1, Value);
  Assert.IsTrue(AgeUnit = TAtlasUnsavedAgeUnit.Hours);
  TAtlasWelcomeUnsaved.Age(HoursAgo(23.9), NowUtc, Value, AgeUnit);
  Assert.AreEqual(23, Value);
  TAtlasWelcomeUnsaved.Age(HoursAgo(24), NowUtc, Value, AgeUnit);
  Assert.AreEqual(1, Value);
  Assert.IsTrue(AgeUnit = TAtlasUnsavedAgeUnit.Days);
  TAtlasWelcomeUnsaved.Age(HoursAgo(24 * 9 + 5), NowUtc, Value, AgeUnit);
  Assert.AreEqual(9, Value);
  AssertNear(0.0, TAtlasWelcomeUnsaved.AgeHours(0, NowUtc), 1E-9, 'unbekannt');
  AssertNear(0.0, TAtlasWelcomeUnsaved.AgeHours(NowUtc + 1, NowUtc), 1E-9, 'Zukunft (Uhr verstellt)');
end;

procedure TAtlasWelcomeUnsavedTests.LevelFollowsWarnAndAlertHours;
var
  Settings: TAtlasUnsavedOptions;
begin
  Settings := TAtlasUnsavedOptions.Create(0, 24, 72);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Level(HoursAgo(23), NowUtc, Settings) = TAtlasUnsavedLevel.Fresh);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Level(HoursAgo(24), NowUtc, Settings) = TAtlasUnsavedLevel.Warning,
    'gelb ab warnHours');
  Assert.IsTrue(TAtlasWelcomeUnsaved.Level(HoursAgo(71), NowUtc, Settings) = TAtlasUnsavedLevel.Warning);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Level(HoursAgo(72), NowUtc, Settings) = TAtlasUnsavedLevel.Alert,
    'rot ab alertHours');
  Assert.IsTrue(TAtlasWelcomeUnsaved.Level(0, NowUtc, Settings) = TAtlasUnsavedLevel.Fresh, 'unbekannt');
  Settings := TAtlasUnsavedOptions.Create(0, 1, 2);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Level(HoursAgo(1.5), NowUtc, Settings) = TAtlasUnsavedLevel.Warning);
end;

procedure TAtlasWelcomeUnsavedTests.OlderThanAlertIsRed;
var
  View: TAtlasUnsavedView;
begin
  View := TAtlasWelcomeUnsaved.View([Project('C:\Repo\Demo.dproj',
    GitState(Root, [Item(TAtlasUnsavedKind.Changes, 1, 80)]))], NowUtc, Options);
  Assert.AreEqual(1, Integer(Length(View.Rows)));
  Assert.IsTrue(View.Rows[0].Level = TAtlasUnsavedLevel.Alert);
end;

procedure TAtlasWelcomeUnsavedTests.SortsOldestFirst;
var
  View: TAtlasUnsavedView;
begin
  View := TAtlasWelcomeUnsaved.View([
    Project('C:\A\Eins.dproj', GitState('C:\A', [Item(TAtlasUnsavedKind.Changes, 1, 2),
      Item(TAtlasUnsavedKind.Stashes, 1, 40), Item(TAtlasUnsavedKind.Commits, 2, -1)])),
    Project('C:\B\Zwei.dproj', GitState('C:\B', [Item(TAtlasUnsavedKind.Changes, 3, 10),
      Item(TAtlasUnsavedKind.Conflicts, 1, 10)]))], NowUtc, Options);
  Assert.AreEqual(5, Integer(Length(View.Rows)));
  Assert.IsTrue(View.Rows[0].Item.Kind = TAtlasUnsavedKind.Stashes, 'älteste zuerst');
  Assert.AreEqual('Zwei', View.Rows[1].Name);
  Assert.IsTrue(View.Rows[1].Item.Kind = TAtlasUnsavedKind.Changes, 'gleich alt: nach Art');
  Assert.IsTrue(View.Rows[2].Item.Kind = TAtlasUnsavedKind.Conflicts);
  Assert.AreEqual('Eins', View.Rows[3].Name);
  Assert.IsTrue(View.Rows[3].Item.Kind = TAtlasUnsavedKind.Changes);
  Assert.IsTrue(View.Rows[4].Item.Kind = TAtlasUnsavedKind.Commits, 'unbekanntes Alter zuletzt');
end;

procedure TAtlasWelcomeUnsavedTests.MinimumAgeAndIgnoreHideRows;
var
  State: TAtlasUnsavedState;
  View: TAtlasUnsavedView;
begin
  State := GitState(Root, [Item(TAtlasUnsavedKind.Changes, 1, 2), Item(TAtlasUnsavedKind.Stashes, 1, 30),
    Item(TAtlasUnsavedKind.Commits, 1, 50)]);
  View := TAtlasWelcomeUnsaved.View([Project('C:\Repo\Demo.dproj', State)], NowUtc,
    TAtlasUnsavedOptions.Create(4, 24, 72));
  Assert.AreEqual(2, Integer(Length(View.Rows)), 'jünger als minAgeHours entfällt');
  Assert.AreEqual(1, View.Hidden);
  TAtlasWelcomeUnsaved.Ignore(State, TAtlasUnsavedKind.Stashes, NowUtc + 0.5);
  TAtlasWelcomeUnsaved.Ignore(State, TAtlasUnsavedKind.Commits, NowUtc - 0.1);
  View := TAtlasWelcomeUnsaved.View([Project('C:\Repo\Demo.dproj', State)], NowUtc,
    TAtlasUnsavedOptions.Create(4, 24, 72));
  Assert.AreEqual(1, Integer(Length(View.Rows)), 'Stash bis morgen ignoriert, Commits wieder da');
  Assert.IsTrue(View.Rows[0].Item.Kind = TAtlasUnsavedKind.Commits);
  Assert.AreEqual(2, View.Hidden);
  // Alles ausgeblendet: nichts zu zeigen, aber nicht „alles gesichert“ im Sinne von keinen Einträgen.
  TAtlasWelcomeUnsaved.Ignore(State, TAtlasUnsavedKind.Commits, NowUtc + 0.5);
  View := TAtlasWelcomeUnsaved.View([Project('C:\Repo\Demo.dproj', State)], NowUtc,
    TAtlasUnsavedOptions.Create(4, 24, 72));
  Assert.IsTrue(View.Clean);
  Assert.AreEqual(3, View.Hidden);
end;

procedure TAtlasWelcomeUnsavedTests.RepositoryWideRowsOncePerWorkingCopy;
var
  View: TAtlasUnsavedView;
begin
  // Projektgruppe und Projekt in derselben Arbeitskopie: Commits und Stash einmal, Änderungen je Projekt.
  View := TAtlasWelcomeUnsaved.View([
    Project('C:\Repo\Gruppe.groupproj', GitState('C:\Repo', [Item(TAtlasUnsavedKind.Changes, 2, 5),
      Item(TAtlasUnsavedKind.Commits, 3, 6), Item(TAtlasUnsavedKind.Stashes, 1, 7)])),
    Project('C:\Repo\Tests\Tests.dproj', GitState('c:\repo', [Item(TAtlasUnsavedKind.Changes, 1, 5),
      Item(TAtlasUnsavedKind.Commits, 3, 6), Item(TAtlasUnsavedKind.Stashes, 1, 7)]))], NowUtc, Options);
  Assert.AreEqual(4, Integer(Length(View.Rows)));
  Assert.AreEqual('Gruppe', View.Rows[0].Name, 'Stash beim zuerst genannten Projekt');
  Assert.IsTrue(View.Rows[0].Item.Kind = TAtlasUnsavedKind.Stashes);
  Assert.AreEqual('Gruppe', View.Rows[1].Name);
  Assert.IsTrue(View.Rows[1].Item.Kind = TAtlasUnsavedKind.Commits);
  Assert.AreEqual('Gruppe', View.Rows[2].Name);
  Assert.AreEqual('Tests', View.Rows[3].Name);
end;

procedure TAtlasWelcomeUnsavedTests.MergeKeepsUnqueriedKindsAndFirstSeen;
var
  Old, New_, Merged: TAtlasUnsavedState;
  Found: TAtlasUnsavedItem;
begin
  Old := GitState(Root, [Item(TAtlasUnsavedKind.Changes, 2, 20)]);
  // Nur gelöschte Dateien: Alter unbekannt; gilt seit der ersten Sicht.
  New_ := GitState(Root, [Item(TAtlasUnsavedKind.Changes, 3, -1), Item(TAtlasUnsavedKind.Conflicts, 1, -1)]);
  New_.Queried := [TAtlasUnsavedKind.Changes, TAtlasUnsavedKind.Conflicts];
  Merged := TAtlasWelcomeUnsaved.Merge(Old, New_, NowUtc);
  Assert.IsTrue(Merged.Find(TAtlasUnsavedKind.Changes, Found));
  Assert.AreEqual(3, Found.Count);
  AssertNear(HoursAgo(20), Found.Since, 1E-6, 'seit der ersten Sicht');
  Assert.IsTrue(Merged.Find(TAtlasUnsavedKind.Conflicts, Found));
  AssertNear(NowUtc, Found.Since, 1E-6, 'neu: jetzt');
  // Andere Arbeitskopie: nichts übernehmen.
  Old.Root := 'C:\Anders';
  Merged := TAtlasWelcomeUnsaved.Merge(Old, New_, NowUtc);
  Assert.IsTrue(Merged.Find(TAtlasUnsavedKind.Changes, Found));
  AssertNear(NowUtc, Found.Since, 1E-6, '');
end;

procedure TAtlasWelcomeUnsavedTests.MergeDropsExpiredIgnores;
var
  Old, New_, Merged: TAtlasUnsavedState;
begin
  Old := GitState(Root, nil);
  TAtlasWelcomeUnsaved.Ignore(Old, TAtlasUnsavedKind.Changes, NowUtc + 0.2);
  TAtlasWelcomeUnsaved.Ignore(Old, TAtlasUnsavedKind.Stashes, NowUtc - 0.2);
  New_ := GitState(Root, nil);
  Merged := TAtlasWelcomeUnsaved.Merge(Old, New_, NowUtc);
  Assert.AreEqual(1, Integer(Length(Merged.Ignored)));
  Assert.IsTrue(Merged.IgnoredUntil(TAtlasUnsavedKind.Changes) > NowUtc);
  AssertNear(0.0, Double(Merged.IgnoredUntil(TAtlasUnsavedKind.Stashes)), 1E-9, '');
end;

procedure TAtlasWelcomeUnsavedTests.TomorrowIsNextMidnight;
begin
  AssertNear(EncodeDate(2026, 10, 16), TAtlasWelcomeUnsaved.Tomorrow(EncodeDate(2026, 10, 15) +
    EncodeTime(23, 59, 0, 0)), 1E-9, '');
  AssertNear(EncodeDate(2026, 10, 16), TAtlasWelcomeUnsaved.Tomorrow(EncodeDate(2026, 10, 15)), 1E-9, '');
end;

procedure TAtlasWelcomeUnsavedTests.SectionRoundTripKeepsSummary;
var
  Summary, Parsed: TAtlasProjectSummary;
  State, Read_: TAtlasUnsavedState;
  Lonely: TAtlasUnsavedItem;
  Changes: TAtlasUnsavedItem;
  Found: TAtlasUnsavedItem;
  Json: string;
begin
  Assert.IsTrue(TAtlasProjectSummaries.Parse('{"format":1,"project":"C:\\Repo\\Demo.dproj","hidden":true,' +
    '"vcs":{"kind":"git","branch":"main","changed":2},"history":{"x":1}}', Summary));
  Changes := Item(TAtlasUnsavedKind.Changes, 4, 48);
  Changes.Modified := 2;
  Changes.Added := 1;
  Changes.Deleted := 1;
  Lonely := Item(TAtlasUnsavedKind.NoUpstream, 1, 50);
  Lonely.Commits := 2;
  Lonely.Branches := ['feature/x'];
  State := GitState(Root, [Changes, Lonely, Item(TAtlasUnsavedKind.Stashes, 1, 5)]);
  State.Items[2].Name := 'WIP „Hover“';
  State.Items[2].Ref := 'abc';
  TAtlasWelcomeUnsaved.Ignore(State, TAtlasUnsavedKind.Stashes, NowUtc + 0.5);
  TAtlasWelcomeUnsaved.Write(Summary, State);
  Json := TAtlasProjectSummaries.ToJson(Summary);
  Assert.Contains(Json, '"history"', 'fremde Abschnitte bleiben');
  Assert.IsTrue(TAtlasProjectSummaries.Parse(Json, Parsed));
  Assert.IsTrue(Parsed.Hidden, 'bekannte Felder bleiben');
  Assert.AreEqual('main', Parsed.Vcs.Branch);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Read(Parsed, Read_));
  Assert.IsTrue(Read_.Known);
  Assert.AreEqual('git', Read_.Kind);
  Assert.AreEqual(Root, Read_.Root);
  Assert.AreEqual('main', Read_.Branch);
  AssertNear(NowUtc, Read_.At, 1E-6, '');
  Assert.AreEqual(3, Integer(Length(Read_.Items)));
  Assert.IsTrue(Read_.Find(TAtlasUnsavedKind.Changes, Found));
  Assert.AreEqual(4, Found.Count);
  Assert.AreEqual(2, Found.Modified);
  Assert.AreEqual(1, Found.Added);
  Assert.AreEqual(1, Found.Deleted);
  AssertNear(HoursAgo(48), Found.Since, 1 / (24 * 3600), '');
  Assert.IsTrue(Read_.Find(TAtlasUnsavedKind.NoUpstream, Found));
  Assert.AreEqual(2, Found.Commits);
  Assert.AreEqual('feature/x', Found.Branches[0]);
  Assert.IsTrue(Read_.Find(TAtlasUnsavedKind.Stashes, Found));
  Assert.AreEqual('WIP „Hover“', Found.Name);
  Assert.AreEqual('abc', Found.Ref);
  Assert.IsTrue(Read_.IgnoredUntil(TAtlasUnsavedKind.Stashes) > NowUtc);
  // Zweimal schreiben ersetzt den Abschnitt.
  State.Items := nil;
  TAtlasWelcomeUnsaved.Write(Parsed, State);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Read(Parsed, Read_));
  Assert.AreEqual(0, Integer(Length(Read_.Items)));
  // Neue Zusammenfassung ohne Datei.
  Summary := TAtlasProjectSummary.Create('C:\Neu\Neu.dproj');
  Assert.IsFalse(TAtlasWelcomeUnsaved.Read(Summary, Read_));
  TAtlasWelcomeUnsaved.Write(Summary, GitState(Root, nil));
  Assert.IsTrue(TAtlasProjectSummaries.Parse(TAtlasProjectSummaries.ToJson(Summary), Parsed));
  Assert.AreEqual('C:\Neu\Neu.dproj', Parsed.Project);
  Assert.IsTrue(TAtlasWelcomeUnsaved.Read(Parsed, Read_));
  // Unbekannte Arten einer späteren Fassung werden übergangen.
  Assert.IsTrue(TAtlasWelcomeUnsaved.FromJson('{"kind":"git","items":[{"kind":"neu","count":1},' +
    '{"kind":"stashes","count":2}]}', Read_));
  Assert.AreEqual(1, Integer(Length(Read_.Items)));
  Assert.IsFalse(TAtlasWelcomeUnsaved.FromJson('kein json', Read_));
end;

procedure TAtlasWelcomeUnsavedTests.PushPlansForCommitsAndBranchesWithoutUpstream;
var
  Fake: TFakeVcs;
  Local: IAtlasVcsLocalWork;
  Plans: TArray<TAtlasUnsavedPush>;
  Pending, Lonely: TAtlasUnsavedItem;
  Many: TArray<TAtlasVcsCommit>;
  Index: Integer;
begin
  Fake := TFakeVcs.Create;
  Local := Fake;
  Fake.FKind := TAtlasVcsKind.Git;
  Fake.FBranches := [Branch('main', 'origin/main', 3, True), Branch('dev', 'origin/dev', 0, False),
    Branch('feature/x', '', 0, False)];
  Fake.FRemotes := ['origin'];
  Fake.AddOutgoing('main', 'origin/main', [Commit('c3', 1), Commit('c2', 2), Commit('c1', 3)]);
  Many := nil;
  for Index := 1 to TAtlasWelcomeUnsaved.PushListMax + 5 do
    Many := Many + [Commit('x' + IntToStr(Index), Index)];
  Fake.AddOutgoing('feature/x', '', Many);
  Pending := Item(TAtlasUnsavedKind.Commits, 3, 3);
  Pending.Branches := ['main', 'dev'];
  Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(Local, Pending, Plans) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(1, Integer(Length(Plans)), 'dev ist gleichauf');
  Assert.AreEqual('main', Plans[0].Branch);
  Assert.AreEqual('origin', Plans[0].Remote);
  Assert.AreEqual('refs/heads/main', Plans[0].RemoteRef);
  Assert.AreEqual('origin/main', Plans[0].Target);
  Assert.IsFalse(Plans[0].SetUpstream);
  Assert.AreEqual(3, Integer(Length(Plans[0].Commits)));
  Assert.AreEqual('c3', Plans[0].Commits[0].Hash, 'neueste zuerst');
  Assert.IsFalse(Plans[0].More);
  Assert.IsFalse(Fake.Calls[High(Fake.Calls)] = 'push', 'nur geplant, nicht gepusht');
  Lonely := Item(TAtlasUnsavedKind.NoUpstream, 1, 3);
  Lonely.Branches := ['feature/x'];
  Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(Local, Lonely, Plans) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(1, Integer(Length(Plans)));
  Assert.AreEqual('origin', Plans[0].Remote, 'einziges Remote');
  Assert.AreEqual('origin/feature/x', Plans[0].Target);
  Assert.IsTrue(Plans[0].SetUpstream);
  Assert.AreEqual(TAtlasWelcomeUnsaved.PushListMax, Integer(Length(Plans[0].Commits)));
  Assert.IsTrue(Plans[0].More);
  Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(Local, Item(TAtlasUnsavedKind.Stashes, 1, 1), Plans) =
    TAtlasVcsOutcome.Failed, 'Stash wird nicht gepusht');
end;

procedure TAtlasWelcomeUnsavedTests.PushPlansWithoutRemoteAreEmpty;
var
  Fake: TFakeVcs;
  Local: IAtlasVcsLocalWork;
  Plans: TArray<TAtlasUnsavedPush>;
  Lonely: TAtlasUnsavedItem;
begin
  Fake := TFakeVcs.Create;
  Local := Fake;
  Fake.FKind := TAtlasVcsKind.Git;
  Fake.FBranches := [Branch('feature/x', '', 0, True)];
  Fake.AddOutgoing('feature/x', '', [Commit('a', 1)]);
  Lonely := Item(TAtlasUnsavedKind.NoUpstream, 1, 1);
  Lonely.Branches := ['feature/x'];
  // Kein Remote: kein Ziel.
  Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(Local, Lonely, Plans) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(0, Integer(Length(Plans)));
  // Mehrere Remotes ohne "origin": kein eindeutiges Ziel.
  Fake.FRemotes := ['a', 'b'];
  Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(Local, Lonely, Plans) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(0, Integer(Length(Plans)));
  Fake.FRemotes := ['upstream', 'origin'];
  Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(Local, Lonely, Plans) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(1, Integer(Length(Plans)));
  Assert.AreEqual('origin', Plans[0].Remote);
end;

procedure TAtlasWelcomeUnsavedTests.SettingsDefaultsAndLimits;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.WelcomePageUnsaved, 'welcomePage.unsaved an');
  Assert.AreEqual(0, Settings.WelcomePageUnsavedMinAgeHours);
  Assert.AreEqual(24, Settings.WelcomePageUnsavedWarnHours);
  Assert.AreEqual(72, Settings.WelcomePageUnsavedAlertHours);
  Assert.IsFalse(Settings.WelcomePageUnsavedHideWhenClean);
  Settings.WelcomePageUnsavedMinAgeHours := -5;
  Settings.WelcomePageUnsavedWarnHours := 100000;
  Settings.WelcomePageUnsavedAlertHours := 10;
  Settings.Normalize;
  Assert.AreEqual(0, Settings.WelcomePageUnsavedMinAgeHours);
  Assert.AreEqual(TAtlasWelcomeUnsaved.MaxHours, Settings.WelcomePageUnsavedWarnHours);
  Assert.AreEqual(TAtlasWelcomeUnsaved.MaxHours, Settings.WelcomePageUnsavedAlertHours, 'rot nie vor gelb');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeUnsavedTests);

end.
