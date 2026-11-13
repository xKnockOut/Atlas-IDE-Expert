unit Atlas.UI.Tracker.DevelopmentView.Tests;

// Reiter „Entwicklung“ im Fenster „Atlas-Issue“ (#1269): Laden und Meldung,
// Branches mit Stand und „Wechseln“, Commits mit Klick (Diff, erst nach der
// Doppelklickzeit) und Doppelklick (Unit öffnen), Pull Requests mit Zustand
// und Ampel bzw. VCS-Änderungen aus YouTrack, Units im Baum nach Projekt und
// Zeilen für fehlende Arbeitskopie bzw. Fehler des Trackers.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasIssueDevelopmentViewTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LoadingAndNote;
    [Test]
    procedure ShowsBranchesCommitsPullsAndUnits;
    [Test]
    procedure ClickShowsDiffDoubleClickOpens;
    [Test]
    procedure UnitAndPullOpen;
    [Test]
    procedure SwitchOnlyForOtherBranch;
    [Test]
    procedure MissingWorkingCopyAndTrackerError;
    [Test]
    procedure YouTrackChangesInsteadOfPulls;
  end;

implementation

uses
  Atlas.UI.Tracker.Development.Strings,
  System.SysUtils,
  Vcl.Forms,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Development,
  Atlas.Core.VersionControl.Contract,
  Atlas.UI.Tracker.DevelopmentView;

function Root: string;
begin
  if PathDelim = '\' then
  begin
    Result := 'C:\Projekte\Kasse';
  end
  else
  begin
    Result := '/projekte/kasse';
  end;
end;

function Under(const ARelative: string): string;
begin
  Result := Root + PathDelim + StringReplace(ARelative, '/', PathDelim, [rfReplaceAll]);
end;

function SampleBranches: TArray<TAtlasIssueBranch>;
var
  mBranch: TAtlasIssueBranch;
begin
  mBranch := Default(TAtlasIssueBranch);
  mBranch.Name := 'feature/753-atlas-bereiche';
  mBranch.Local := True;
  mBranch.Remote := True;
  mBranch.Current := True;
  mBranch.Base := 'main';
  mBranch.Ahead := 3;
  mBranch.Behind := 1;
  Result := [mBranch];
  mBranch := Default(TAtlasIssueBranch);
  mBranch.Name := 'bugfix/753-nur-entfernt';
  mBranch.Remote := True;
  mBranch.Ahead := -1;
  mBranch.Behind := -1;
  Result := Result + [mBranch];
end;

function SampleCommits: TArray<TAtlasVcsLogEntry>;
var
  mEntry: TAtlasVcsLogEntry;
  mFile: TAtlasVcsLogFile;
begin
  mFile := Default(TAtlasVcsLogFile);
  mFile.Path := Under('app/Main.pas');
  mFile.RepositoryPath := 'app/Main.pas';
  mEntry := Default(TAtlasVcsLogEntry);
  mEntry.Revision := '28358feaf94440dbfe2fcc3aa2cb742e2d972f37';
  mEntry.Summary := '#753 Bereiche';
  mEntry.Author := 'Marco';
  mEntry.Files := [mFile];
  Result := [mEntry];
  mEntry.Revision := '7637c6cf53522335c876c98aef9a32861d4dc147';
  mEntry.Summary := '#753 Anfang';
  Result := Result + [mEntry];
end;

function SampleUnits: TArray<TAtlasIssueUnitGroup>;
var
  mGroup: TAtlasIssueUnitGroup;
  mUnit: TAtlasIssueUnit;
begin
  mGroup := Default(TAtlasIssueUnitGroup);
  mGroup.Project := 'Kasse';
  mGroup.ProjectFile := Under('Kasse.dproj');
  mUnit := Default(TAtlasIssueUnit);
  mUnit.Path := Under('app/Main.pas');
  mUnit.Commits := 2;
  mGroup.Units := [mUnit];
  mUnit.Path := Under('app/Alt.pas');
  mUnit.Deleted := True;
  mGroup.Units := mGroup.Units + [mUnit];
  Result := [mGroup];
  mGroup := Default(TAtlasIssueUnitGroup);
  mUnit := Default(TAtlasIssueUnit);
  mUnit.Path := Under('README.md');
  mGroup.Units := [mUnit];
  Result := Result + [mGroup];
end;

function Sample: TAtlasIssueDevelopment;
var
  mPull: TAtlasTrackerPull;
begin
  Result := TAtlasIssueDevelopment.Empty;
  Result.Key := '#753';
  Result.VcsKind := TAtlasVcsKind.Git;
  Result.VcsOutcome := TAtlasVcsOutcome.Ok;
  Result.Branches := SampleBranches;
  Result.Commits := SampleCommits;
  Result.TrackerLoaded := True;
  mPull := Default(TAtlasTrackerPull);
  mPull.Number := 760;
  mPull.Title := 'Atlas-Bereiche';
  mPull.State := TAtlasTrackerPullState.Merged;
  mPull.Checks := TAtlasTrackerChecks.Success;
  mPull.Page := 'https://github.com/beispiel/kasse/pull/760';
  Result.Tracker.Pulls := [mPull];
  Result.Units := SampleUnits;
end;

{ TAtlasIssueDevelopmentViewTests }

procedure TAtlasIssueDevelopmentViewTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasIssueDevelopmentViewTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasIssueDevelopmentViewTests.LoadingAndNote;
var
  mHost: TForm;
  mView: TAtlasIssueDevelopmentView;
begin
  mHost := TForm.CreateNew(nil);
  try
    mView := TAtlasIssueDevelopmentView.Create(mHost);
    mView.Parent := mHost;
    mView.ShowLoading;
    Assert.AreEqual(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevLoading),
      TAtlasIssueDevelopmentProbe.StatusText(mView));
    Assert.IsFalse(mView.HasDevelopment);
    Assert.IsNull(mView.Parts.Commits);
    mView.ShowDevelopment(Sample, '');
    Assert.IsTrue(mView.HasDevelopment);
    Assert.AreEqual('', TAtlasIssueDevelopmentProbe.StatusText(mView));
    mView.ShowNote(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevNoProject));
    Assert.AreEqual(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevNoProject),
      TAtlasIssueDevelopmentProbe.StatusText(mView));
    Assert.IsNull(mView.Parts.Branches, 'alter Inhalt weg');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueDevelopmentViewTests.ShowsBranchesCommitsPullsAndUnits;
var
  mHost: TForm;
  mView: TAtlasIssueDevelopmentView;
  mLines: TArray<string>;
begin
  mHost := TForm.CreateNew(nil);
  try
    mHost.Width := 700;
    mHost.Height := 600;
    mView := TAtlasIssueDevelopmentView.Create(mHost);
    mView.Parent := mHost;
    mView.ShowDevelopment(Sample, '');
    Assert.AreEqual(2, mView.Parts.Branches.Items.Count);
    Assert.AreEqual('feature/753-atlas-bereiche', mView.Parts.Branches.Items[0].Caption);
    Assert.AreEqual(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevLocalRemote),
      mView.Parts.Branches.Items[0].SubItems[0]);
    Assert.AreEqual(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevCurrent) + ', ' +
      TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevAheadBehind, [3, 1, 'main']),
        mView.Parts.Branches.Items[0].SubItems[1]);
    Assert.AreEqual(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevRemote),
      mView.Parts.Branches.Items[1].SubItems[0]);
    Assert.AreEqual('', mView.Parts.Branches.Items[1].SubItems[1], 'ohne Vergleich kein Stand');
    Assert.AreEqual(2, mView.Parts.Commits.Items.Count);
    Assert.AreEqual('28358fe', mView.Parts.Commits.Items[0].Caption);
    Assert.AreEqual('#753 Bereiche', mView.Parts.Commits.Items[0].SubItems[0]);
    Assert.AreEqual('Marco', mView.Parts.Commits.Items[0].SubItems[1]);
    Assert.AreEqual(1, mView.Parts.Pulls.Items.Count);
    Assert.AreEqual('#760', mView.Parts.Pulls.Items[0].Caption);
    Assert.AreEqual(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevPullMerged),
      mView.Parts.Pulls.Items[0].SubItems[1]);
    Assert.AreEqual(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevChecksSuccess),
      mView.Parts.Pulls.Items[0].SubItems[2]);
    Assert.IsNull(mView.Parts.Changes, 'GitHub ohne VCS-Änderungen');
    mLines := TAtlasIssueDevelopmentProbe.UnitLines(mView);
    Assert.AreEqual(5, Integer(Length(mLines)));
    Assert.AreEqual('Kasse (2)', mLines[0]);
    Assert.AreEqual('  ' + 'app' + PathDelim + 'Main.pas', mLines[1], 'relativ zum Projekt');
    Assert.AreEqual('  '
      + TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevDeleted, ['app' + PathDelim + 'Alt.pas']), mLines[2]);
    Assert.AreEqual(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevOtherFiles) + ' (1)', mLines[3]);
    Assert.AreEqual('  ' + Under('README.md'), mLines[4], 'ohne Projekt vollständig');
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueDevelopmentViewTests.ClickShowsDiffDoubleClickOpens;
var
  mHost: TForm;
  mView: TAtlasIssueDevelopmentView;
  mEvents: TAtlasIssueDevelopmentEvents;
  mDiff, mOpened: string;
begin
  mEvents := Default(TAtlasIssueDevelopmentEvents);
  mDiff := '';
  mOpened := '';
  mHost := TForm.CreateNew(nil);
  try
    mView := TAtlasIssueDevelopmentView.Create(mHost);
    mView.Parent := mHost;
    mEvents.ShowDiff :=
      procedure(AEntry: TAtlasVcsLogEntry)
      begin
        mDiff := AEntry.Revision;
      end;
    mEvents.OpenCommit :=
      procedure(AEntry: TAtlasVcsLogEntry)
      begin
        mOpened := AEntry.Revision;
      end;
    mView.Events := mEvents;
    mView.ShowDevelopment(Sample, '');
    // Klick: der Diff erst nach der Doppelklickzeit.
    mView.Parts.Commits.Selected := mView.Parts.Commits.Items[1];
    mView.Parts.Commits.OnClick(mView.Parts.Commits);
    Assert.IsTrue(mView.Parts.CommitTimer.Enabled);
    Assert.AreEqual('', mDiff);
    mView.FireCommitClick;
    Assert.AreEqual('7637c6cf53522335c876c98aef9a32861d4dc147', mDiff);
    Assert.IsFalse(mView.Parts.CommitTimer.Enabled);
    // Doppelklick: öffnen statt Diff.
    mDiff := '';
    mView.Parts.Commits.Selected := mView.Parts.Commits.Items[0];
    mView.Parts.Commits.OnClick(mView.Parts.Commits);
    mView.Parts.Commits.OnDblClick(mView.Parts.Commits);
    Assert.IsFalse(mView.Parts.CommitTimer.Enabled, 'Doppelklick hält den Diff an');
    mView.FireCommitClick;
    Assert.AreEqual('', mDiff);
    Assert.AreEqual('28358feaf94440dbfe2fcc3aa2cb742e2d972f37', mOpened);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueDevelopmentViewTests.UnitAndPullOpen;
var
  mHost: TForm;
  mView: TAtlasIssueDevelopmentView;
  mEvents: TAtlasIssueDevelopmentEvents;
  mUnit, mPull: string;
begin
  mEvents := Default(TAtlasIssueDevelopmentEvents);
  mUnit := '';
  mPull := '';
  mHost := TForm.CreateNew(nil);
  try
    mView := TAtlasIssueDevelopmentView.Create(mHost);
    mView.Parent := mHost;
    mEvents.OpenUnit :=
      procedure(AUnit: TAtlasIssueUnit)
      begin
        mUnit := AUnit.Path;
      end;
    mEvents.OpenPull :=
      procedure(APull: TAtlasTrackerPull)
      begin
        mPull := APull.Page;
      end;
    mView.Events := mEvents;
    mView.ShowDevelopment(Sample, '');
    // Units: Gruppen und gelöschte öffnen nichts.
    mView.Parts.Units.Selected := mView.Parts.Units.Items[0];
    mView.Parts.Units.OnClick(mView.Parts.Units);
    Assert.AreEqual('', mUnit);
    mView.Parts.Units.Selected := mView.Parts.Units.Items[2];
    mView.Parts.Units.OnClick(mView.Parts.Units);
    Assert.AreEqual('', mUnit, 'gelöscht');
    mView.Parts.Units.Selected := mView.Parts.Units.Items[1];
    mView.Parts.Units.OnClick(mView.Parts.Units);
    Assert.AreEqual(Under('app/Main.pas'), mUnit);
    mView.Parts.Pulls.Selected := mView.Parts.Pulls.Items[0];
    mView.Parts.Pulls.OnDblClick(mView.Parts.Pulls);
    Assert.AreEqual('https://github.com/beispiel/kasse/pull/760', mPull);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueDevelopmentViewTests.SwitchOnlyForOtherBranch;
var
  mHost: TForm;
  mView: TAtlasIssueDevelopmentView;
  mEvents: TAtlasIssueDevelopmentEvents;
  mSwitched: string;
begin
  mEvents := Default(TAtlasIssueDevelopmentEvents);
  mSwitched := '';
  mHost := TForm.CreateNew(nil);
  try
    mView := TAtlasIssueDevelopmentView.Create(mHost);
    mView.Parent := mHost;
    mEvents.SwitchBranch :=
      procedure(ABranch: TAtlasIssueBranch)
      begin
        mSwitched := ABranch.Name;
      end;
    mView.Events := mEvents;
    mView.ShowDevelopment(Sample, '');
    Assert.IsFalse(mView.Parts.Switch.Enabled, 'ohne Auswahl');
    // Die Auswahl meldet die Liste über OnSelectItem; ohne sichtbares Fenster hier direkt.
    mView.Parts.Branches.Selected := mView.Parts.Branches.Items[0];
    mView.Parts.Branches.OnSelectItem(mView.Parts.Branches, mView.Parts.Branches.Items[0], True);
    Assert.IsFalse(mView.Parts.Switch.Enabled, 'schon aktuell');
    mView.Parts.Branches.Selected := mView.Parts.Branches.Items[1];
    mView.Parts.Branches.OnSelectItem(mView.Parts.Branches, mView.Parts.Branches.Items[1], True);
    Assert.IsTrue(mView.Parts.Switch.Enabled);
    mView.Parts.Switch.Click;
    Assert.AreEqual('bugfix/753-nur-entfernt', mSwitched);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueDevelopmentViewTests.MissingWorkingCopyAndTrackerError;
var
  mHost: TForm;
  mView: TAtlasIssueDevelopmentView;
  mDevelopment: TAtlasIssueDevelopment;
begin
  mHost := TForm.CreateNew(nil);
  try
    mView := TAtlasIssueDevelopmentView.Create(mHost);
    mView.Parent := mHost;
    mDevelopment := Sample;
    mDevelopment.VcsOutcome := TAtlasVcsOutcome.NoWorkingCopy;
    mView.ShowDevelopment(mDevelopment, '');
    Assert.AreEqual(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevNoVcs),
      TAtlasIssueDevelopmentProbe.StatusText(mView));
    Assert.IsNull(mView.Parts.Branches);
    Assert.IsNull(mView.Parts.Commits);
    Assert.IsNull(mView.Parts.Units, 'ohne Arbeitskopie keine Units');
    Assert.IsNotNull(mView.Parts.Pulls, 'der Tracker bleibt');
    mDevelopment.VcsOutcome := TAtlasVcsOutcome.ToolMissing;
    mView.ShowDevelopment(mDevelopment, '');
    Assert.AreEqual(TAtlasIssueDevStrings.Fmt(TAtlasIssueDevTextId.IssueDevToolMissing, ['Git']),
      TAtlasIssueDevelopmentProbe.StatusText(mView));
    mDevelopment.VcsOutcome := TAtlasVcsOutcome.Ok;
    mView.ShowDevelopment(mDevelopment, 'kein Netz',
      TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevNoProject));
    Assert.AreEqual(TAtlasIssueDevStrings.Text(TAtlasIssueDevTextId.IssueDevNoProject),
      TAtlasIssueDevelopmentProbe.StatusText(mView), 'ohne Projekt');
    Assert.IsNull(mView.Parts.Commits);
    Assert.IsNull(mView.Parts.Pulls, 'Fehler des Trackers statt der Liste');
    // Leere Ergebnisse sagen, was fehlt.
    mDevelopment := TAtlasIssueDevelopment.Empty;
    mDevelopment.Key := '#9';
    mDevelopment.VcsOutcome := TAtlasVcsOutcome.Ok;
    mDevelopment.TrackerLoaded := True;
    mView.ShowDevelopment(mDevelopment, '');
    Assert.IsNull(mView.Parts.Branches);
    Assert.IsNull(mView.Parts.Commits);
    Assert.IsNull(mView.Parts.Pulls);
    Assert.AreEqual(0, Integer(Length(TAtlasIssueDevelopmentProbe.UnitLines(mView))));
  finally
    mHost.Free;
  end;
end;

procedure TAtlasIssueDevelopmentViewTests.YouTrackChangesInsteadOfPulls;
var
  mHost: TForm;
  mView: TAtlasIssueDevelopmentView;
  mDevelopment: TAtlasIssueDevelopment;
  mChange: TAtlasTrackerVcsChange;
begin
  mHost := TForm.CreateNew(nil);
  try
    mView := TAtlasIssueDevelopmentView.Create(mHost);
    mView.Parent := mHost;
    mDevelopment := Sample;
    mDevelopment.Tracker := TAtlasTrackerDevelopment.Empty;
    mChange := Default(TAtlasTrackerVcsChange);
    mChange.Version := '4c1d2e3f4a5b6c7d8e9f';
    mChange.Text := 'ATL-123 Tracker angebunden';
    mChange.Author := 'Marco B.';
    mDevelopment.Tracker.Changes := [mChange];
    mView.ShowDevelopment(mDevelopment, '');
    Assert.AreEqual(1, mView.Parts.Changes.Items.Count);
    Assert.AreEqual('4c1d2e3f4a', mView.Parts.Changes.Items[0].Caption, 'gekürzt');
    Assert.AreEqual('ATL-123 Tracker angebunden', mView.Parts.Changes.Items[0].SubItems[0]);
    Assert.IsNull(mView.Parts.Pulls, 'YouTrack ohne Pull Requests');
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueDevelopmentViewTests);

end.
