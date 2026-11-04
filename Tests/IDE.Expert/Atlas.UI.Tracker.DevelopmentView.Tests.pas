unit Atlas.UI.Tracker.DevelopmentView.Tests;

// Reiter „Entwicklung“ im Fenster „Atlas-Issue“ (#1269): Laden und Meldung,
// Branches mit Stand und „Wechseln“, Commits mit Klick (Diff, erst nach der
// Doppelklickzeit) und Doppelklick (Unit öffnen), Pull Requests mit Zustand
// und Ampel bzw. VCS-Änderungen aus YouTrack, Units im Baum nach Projekt und
// Zeilen für fehlende Arbeitskopie bzw. Fehler des Trackers.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings,  Atlas.UI.Tracker.Strings;

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
    procedure SwitchOnlyForOtherBranch;
    [Test]
    procedure MissingWorkingCopyAndTrackerError;
    [Test]
    procedure YouTrackChangesInsteadOfPulls;
  end;

implementation

uses
  System.SysUtils,
  Vcl.Forms,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Development,
  Atlas.Core.Vcs.Contract,
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

/// <summary>Lokaler Branch mit Stand gegenüber main und ein nur noch entfernter.</summary>
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

/// <summary>Units im Projekt Kasse (eine gelöscht) und eine Datei ohne Projekt.</summary>
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
  mEntry: TAtlasVcsLogEntry;
  mFile: TAtlasVcsLogFile;
  mPull: TAtlasTrackerPull;
begin
  Result := TAtlasIssueDevelopment.Empty;
  Result.Key := '#753';
  Result.VcsKind := TAtlasVcsKind.Git;
  Result.VcsOutcome := TAtlasVcsOutcome.Ok;
  Result.Branches := SampleBranches;
  mFile := Default(TAtlasVcsLogFile);
  mFile.Path := Under('app/Main.pas');
  mFile.RepositoryPath := 'app/Main.pas';
  mEntry := Default(TAtlasVcsLogEntry);
  mEntry.Revision := '28358feaf94440dbfe2fcc3aa2cb742e2d972f37';
  mEntry.Summary := '#753 Bereiche';
  mEntry.Author := 'Marco';
  mEntry.Files := [mFile];
  Result.Commits := [mEntry];
  mEntry.Revision := '7637c6cf53522335c876c98aef9a32861d4dc147';
  mEntry.Summary := '#753 Anfang';
  Result.Commits := Result.Commits + [mEntry];
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
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevLoading), mView.StatusText);
    Assert.IsFalse(mView.HasDevelopment);
    Assert.IsNull(mView.Commits);
    mView.ShowDevelopment(Sample, '');
    Assert.IsTrue(mView.HasDevelopment);
    Assert.AreEqual('', mView.StatusText);
    mView.ShowNote(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevNoProject));
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevNoProject), mView.StatusText);
    Assert.IsNull(mView.Branches, 'alter Inhalt weg');
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
    Assert.AreEqual(2, mView.Branches.Items.Count);
    Assert.AreEqual('feature/753-atlas-bereiche', mView.Branches.Items[0].Caption);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevLocalRemote),
      mView.Branches.Items[0].SubItems[0]);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevCurrent) + ', ' +
      TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevAheadBehind, [3, 1, 'main']),
        mView.Branches.Items[0].SubItems[1]);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevRemote), mView.Branches.Items[1].SubItems[0]);
    Assert.AreEqual('', mView.Branches.Items[1].SubItems[1], 'ohne Vergleich kein Stand');
    Assert.AreEqual(2, mView.Commits.Items.Count);
    Assert.AreEqual('28358fe', mView.Commits.Items[0].Caption);
    Assert.AreEqual('#753 Bereiche', mView.Commits.Items[0].SubItems[0]);
    Assert.AreEqual('Marco', mView.Commits.Items[0].SubItems[1]);
    Assert.AreEqual(1, mView.Pulls.Items.Count);
    Assert.AreEqual('#760', mView.Pulls.Items[0].Caption);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevPullMerged),
      mView.Pulls.Items[0].SubItems[1]);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevChecksSuccess),
      mView.Pulls.Items[0].SubItems[2]);
    Assert.IsNull(mView.Changes, 'GitHub ohne VCS-Änderungen');
    mLines := mView.UnitLines;
    Assert.AreEqual(5, Integer(Length(mLines)));
    Assert.AreEqual('Kasse (2)', mLines[0]);
    Assert.AreEqual('  ' + 'app' + PathDelim + 'Main.pas', mLines[1], 'relativ zum Projekt');
    Assert.AreEqual('  '
      + TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevDeleted, ['app' + PathDelim + 'Alt.pas']), mLines[2]);
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevOtherFiles) + ' (1)', mLines[3]);
    Assert.AreEqual('  ' + Under('README.md'), mLines[4], 'ohne Projekt vollständig');
  finally
    mHost.Free;
  end;
end;

type
  /// <summary>Hält fest, was die Ansicht zeigen oder öffnen will.</summary>
  TDevelopmentClickProbe = class
  public
    FDiff: string;
    FOpened: string;
    FUnit: string;
    FPull: string;
  end;

/// <summary>Diff, Commit, Unit und Pull Request der Ansicht an die Probe hängen.</summary>
procedure WireDevelopmentClicks(const ATarget: TAtlasIssueDevelopmentView; const AProbe: TDevelopmentClickProbe);
begin
  ATarget.OnShowDiff :=
    procedure(AEntry: TAtlasVcsLogEntry)
    begin
      AProbe.FDiff := AEntry.Revision;
    end;
  ATarget.OnOpenCommit :=
    procedure(AEntry: TAtlasVcsLogEntry)
    begin
      AProbe.FOpened := AEntry.Revision;
    end;
  ATarget.OnOpenUnit :=
    procedure(AUnit: TAtlasIssueUnit)
    begin
      AProbe.FUnit := AUnit.Path;
    end;
  ATarget.OnOpenPull :=
    procedure(APull: TAtlasTrackerPull)
    begin
      AProbe.FPull := APull.Page;
    end;
end;

procedure TAtlasIssueDevelopmentViewTests.ClickShowsDiffDoubleClickOpens;
var
  mHost: TForm;
  mView: TAtlasIssueDevelopmentView;
  mProbe: TDevelopmentClickProbe;
begin
  mProbe := TDevelopmentClickProbe.Create;
  mHost := TForm.CreateNew(nil);
  try
    mView := TAtlasIssueDevelopmentView.Create(mHost);
    mView.Parent := mHost;
    WireDevelopmentClicks(mView, mProbe);
    mView.ShowDevelopment(Sample, '');
    // Klick: der Diff erst nach der Doppelklickzeit.
    mView.Commits.Selected := mView.Commits.Items[1];
    mView.Commits.OnClick(mView.Commits);
    Assert.IsTrue(mView.CommitTimer.Enabled);
    Assert.AreEqual('', mProbe.FDiff);
    mView.FireCommitClick;
    Assert.AreEqual('7637c6cf53522335c876c98aef9a32861d4dc147', mProbe.FDiff);
    Assert.IsFalse(mView.CommitTimer.Enabled);
    // Doppelklick: öffnen statt Diff.
    mProbe.FDiff := '';
    mView.Commits.Selected := mView.Commits.Items[0];
    mView.Commits.OnClick(mView.Commits);
    mView.Commits.OnDblClick(mView.Commits);
    Assert.IsFalse(mView.CommitTimer.Enabled, 'Doppelklick hält den Diff an');
    mView.FireCommitClick;
    Assert.AreEqual('', mProbe.FDiff);
    Assert.AreEqual('28358feaf94440dbfe2fcc3aa2cb742e2d972f37', mProbe.FOpened);
    // Units: Gruppen und gelöschte öffnen nichts.
    mView.Units.Selected := mView.Units.Items[0];
    mView.Units.OnClick(mView.Units);
    Assert.AreEqual('', mProbe.FUnit);
    mView.Units.Selected := mView.Units.Items[2];
    mView.Units.OnClick(mView.Units);
    Assert.AreEqual('', mProbe.FUnit, 'gelöscht');
    mView.Units.Selected := mView.Units.Items[1];
    mView.Units.OnClick(mView.Units);
    Assert.AreEqual(Under('app/Main.pas'), mProbe.FUnit);
    mView.Pulls.Selected := mView.Pulls.Items[0];
    mView.Pulls.OnDblClick(mView.Pulls);
    Assert.AreEqual('https://github.com/beispiel/kasse/pull/760', mProbe.FPull);
  finally
    mHost.Free;
    mProbe.Free;
  end;
end;

procedure TAtlasIssueDevelopmentViewTests.SwitchOnlyForOtherBranch;
var
  mHost: TForm;
  mView: TAtlasIssueDevelopmentView;
  mSwitched: string;
begin
  mSwitched := '';
  mHost := TForm.CreateNew(nil);
  try
    mView := TAtlasIssueDevelopmentView.Create(mHost);
    mView.Parent := mHost;
    mView.OnSwitchBranch :=
      procedure(ABranch: TAtlasIssueBranch)
      begin
        mSwitched := ABranch.Name;
      end;
    mView.ShowDevelopment(Sample, '');
    Assert.IsFalse(mView.SwitchButton.Enabled, 'ohne Auswahl');
    // Die Auswahl meldet die Liste über OnSelectItem; ohne sichtbares Fenster hier direkt.
    mView.Branches.Selected := mView.Branches.Items[0];
    mView.Branches.OnSelectItem(mView.Branches, mView.Branches.Items[0], True);
    Assert.IsFalse(mView.SwitchButton.Enabled, 'schon aktuell');
    mView.Branches.Selected := mView.Branches.Items[1];
    mView.Branches.OnSelectItem(mView.Branches, mView.Branches.Items[1], True);
    Assert.IsTrue(mView.SwitchButton.Enabled);
    mView.SwitchButton.Click;
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
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevNoVcs), mView.StatusText);
    Assert.IsNull(mView.Branches);
    Assert.IsNull(mView.Commits);
    Assert.IsNull(mView.Units, 'ohne Arbeitskopie keine Units');
    Assert.IsNotNull(mView.Pulls, 'der Tracker bleibt');
    mDevelopment.VcsOutcome := TAtlasVcsOutcome.ToolMissing;
    mView.ShowDevelopment(mDevelopment, '');
    Assert.AreEqual(TAtlasTrackerStrings.Fmt(TAtlasTrackerTextId.IssueDevToolMissing, ['Git']), mView.StatusText);
    mDevelopment.VcsOutcome := TAtlasVcsOutcome.Ok;
    mView.ShowDevelopment(mDevelopment, 'kein Netz', TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevNoProject));
    Assert.AreEqual(TAtlasTrackerStrings.Text(TAtlasTrackerTextId.IssueDevNoProject), mView.StatusText, 'ohne Projekt');
    Assert.IsNull(mView.Commits);
    Assert.IsNull(mView.Pulls, 'Fehler des Trackers statt der Liste');
    // Leere Ergebnisse sagen, was fehlt.
    mDevelopment := TAtlasIssueDevelopment.Empty;
    mDevelopment.Key := '#9';
    mDevelopment.VcsOutcome := TAtlasVcsOutcome.Ok;
    mDevelopment.TrackerLoaded := True;
    mView.ShowDevelopment(mDevelopment, '');
    Assert.IsNull(mView.Branches);
    Assert.IsNull(mView.Commits);
    Assert.IsNull(mView.Pulls);
    Assert.AreEqual(0, Integer(Length(mView.UnitLines)));
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
    Assert.AreEqual(1, mView.Changes.Items.Count);
    Assert.AreEqual('4c1d2e3f4a', mView.Changes.Items[0].Caption, 'gekürzt');
    Assert.AreEqual('ATL-123 Tracker angebunden', mView.Changes.Items[0].SubItems[0]);
    Assert.IsNull(mView.Pulls, 'YouTrack ohne Pull Requests');
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueDevelopmentViewTests);

end.
