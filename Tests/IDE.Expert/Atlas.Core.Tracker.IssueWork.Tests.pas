unit Atlas.Core.Tracker.IssueWork.Tests;

// Tests des Zustands eines Issues für den Arbeitsstand je Issue (#2052) ohne
// VCL: GitHub „closed …“ ist behoben, YouTrack Zielzustände aus
// issues.endStates und übliche englische Namen; frischer Stand der Vorschau vor
// der Liste „Meine Issues“, ohne beides unbekannt, Nachfragen ohne frischen
// Stand.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerIssueWorkTests = class
  public
    [Test]
    procedure GitHubClosedIsResolved;
    [Test]
    procedure YouTrackUsesEndStatesAndCommonNames;
    [Test]
    procedure FreshPreviewWinsOverList;
    [Test]
    procedure ListMeansOpenWithoutFreshPreview;
    [Test]
    procedure OldPreviewOutsideListCounts;
    [Test]
    procedure NothingKnownIsUnknown;
    [Test]
    procedure LookupOnlyWithoutFreshPreview;
  end;

implementation

uses
  Atlas.Core.Tracker.IssueWork;

function Facts(const AProvider: string; AInList, ACached, AFresh: Boolean;
  const AState: string): TAtlasTrackerIssueFacts;
begin
  Result := TAtlasTrackerIssueFacts.Empty;
  Result.Provider := AProvider;
  Result.InList := AInList;
  Result.Cached := ACached;
  Result.Fresh := AFresh;
  Result.State := AState;
end;

{ TAtlasTrackerIssueWorkTests }

procedure TAtlasTrackerIssueWorkTests.GitHubClosedIsResolved;
begin
  Assert.IsTrue(TAtlasTrackerIssueStates.IsResolvedState('github', 'closed', nil));
  Assert.IsTrue(TAtlasTrackerIssueStates.IsResolvedState('GitHub', 'closed (not planned)', nil));
  Assert.IsFalse(TAtlasTrackerIssueStates.IsResolvedState('github', 'open', nil));
  Assert.IsFalse(TAtlasTrackerIssueStates.IsResolvedState('github', 'Done', nil), 'GitHub kennt nur open/closed');
  Assert.IsFalse(TAtlasTrackerIssueStates.IsResolvedState('github', '', nil));
end;

procedure TAtlasTrackerIssueWorkTests.YouTrackUsesEndStatesAndCommonNames;
begin
  Assert.IsTrue(TAtlasTrackerIssueStates.IsResolvedState('youtrack', 'Erledigt', ['Zur Prüfung', ' erledigt ']),
    'Zielzustand aus issues.endStates');
  Assert.IsTrue(TAtlasTrackerIssueStates.IsResolvedState('youtrack', 'Fixed', nil));
  Assert.IsTrue(TAtlasTrackerIssueStates.IsResolvedState('youtrack', 'won''t fix', nil));
  Assert.IsTrue(TAtlasTrackerIssueStates.IsResolvedState('youtrack', ' Verified ', nil));
  Assert.IsFalse(TAtlasTrackerIssueStates.IsResolvedState('youtrack', 'In Progress', ['Erledigt']));
  Assert.IsFalse(TAtlasTrackerIssueStates.IsResolvedState('youtrack', 'Submitted', nil));
end;

procedure TAtlasTrackerIssueWorkTests.FreshPreviewWinsOverList;
begin
  Assert.AreEqual<TAtlasTrackerResolution>(TAtlasTrackerResolution.Resolved,
    TAtlasTrackerIssueStates.StatusOf(Facts('github', True, True, True, 'closed')), 'frisch geschlossen, auch wenn noch in der Liste');
  Assert.AreEqual<TAtlasTrackerResolution>(TAtlasTrackerResolution.Open,
    TAtlasTrackerIssueStates.StatusOf(Facts('github', False, True, True, 'open')));
end;

procedure TAtlasTrackerIssueWorkTests.ListMeansOpenWithoutFreshPreview;
begin
  Assert.AreEqual<TAtlasTrackerResolution>(TAtlasTrackerResolution.Open,
    TAtlasTrackerIssueStates.StatusOf(Facts('github', True, False, False, '')));
  Assert.AreEqual<TAtlasTrackerResolution>(TAtlasTrackerResolution.Open,
    TAtlasTrackerIssueStates.StatusOf(Facts('github', True, True, False, 'closed')), 'alter Stand zählt nicht gegen die Liste');
end;

procedure TAtlasTrackerIssueWorkTests.OldPreviewOutsideListCounts;
begin
  Assert.AreEqual<TAtlasTrackerResolution>(TAtlasTrackerResolution.Resolved,
    TAtlasTrackerIssueStates.StatusOf(Facts('youtrack', False, True, False, 'Fixed')));
end;

procedure TAtlasTrackerIssueWorkTests.NothingKnownIsUnknown;
begin
  Assert.AreEqual<TAtlasTrackerResolution>(TAtlasTrackerResolution.Unknown,
    TAtlasTrackerIssueStates.StatusOf(TAtlasTrackerIssueFacts.Empty),
    'ohne Netz und Liste: unbekannt');
end;

procedure TAtlasTrackerIssueWorkTests.LookupOnlyWithoutFreshPreview;
begin
  Assert.IsTrue(TAtlasTrackerIssueStates.NeedsLookup(TAtlasTrackerIssueFacts.Empty));
  Assert.IsTrue(TAtlasTrackerIssueStates.NeedsLookup(Facts('github', True, True, False, 'open')));
  Assert.IsFalse(TAtlasTrackerIssueStates.NeedsLookup(Facts('github', True, True, True, 'open')));
end;

end.
