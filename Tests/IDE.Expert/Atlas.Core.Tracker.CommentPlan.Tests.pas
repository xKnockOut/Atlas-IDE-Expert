unit Atlas.Core.Tracker.CommentPlan.Tests;

// Entscheidungen des Kommentar-Editors in der IDE (#1278, #1967) ohne IDE: Hilfe je Feld, Merker der Benutzerliste,
// zuletzt geöffnete Issues und welche Fehler ins Protokoll kommen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasCommentPlanTests = class
  public
    [Test]
    procedure AssistsOnlyWithKey;
    [Test]
    procedure UsersKeyIgnoresCase;
    [Test]
    procedure UsersFreshFiveMinutes;
    [Test]
    procedure RecentAtMostMax;
    [Test]
    procedure LogsOnlyRealErrors;
  end;

implementation

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CommentPlan;

function Issue(const AKey: string): TAtlasTrackerIssue;
begin
  Result := Default(TAtlasTrackerIssue);
  Result.Key := AKey;
end;

{ TAtlasCommentPlanTests }

procedure TAtlasCommentPlanTests.AssistsOnlyWithKey;
begin
  Assert.IsTrue(TAtlasCommentPlan.Assists(True, True, 'ATL-1'));
  Assert.IsFalse(TAtlasCommentPlan.Assists(True, True, ''), 'ohne Issue');
  Assert.IsFalse(TAtlasCommentPlan.Assists(True, False, 'ATL-1'), 'issues.commentEditor aus');
  Assert.IsFalse(TAtlasCommentPlan.Assists(False, True, 'ATL-1'), 'beendet');
end;

procedure TAtlasCommentPlanTests.UsersKeyIgnoresCase;
begin
  Assert.AreEqual('youtrack|https://firma.youtrack.cloud|mar',
    TAtlasCommentPlan.UsersKey('youtrack|https://firma.youtrack.cloud', 'MaR'));
  Assert.AreEqual(TAtlasCommentPlan.UsersKey('k', 'ANNA'), TAtlasCommentPlan.UsersKey('k', 'anna'));
end;

procedure TAtlasCommentPlanTests.UsersFreshFiveMinutes;
begin
  Assert.IsTrue(TAtlasCommentPlan.UsersFresh(1000, 1000 + TAtlasCommentPlan.cCacheMs - 1));
  Assert.IsFalse(TAtlasCommentPlan.UsersFresh(1000, 1000 + TAtlasCommentPlan.cCacheMs));
end;

procedure TAtlasCommentPlanTests.RecentAtMostMax;
var
  mIssues: TArray<TAtlasTrackerIssue>;
begin
  mIssues := [Issue('ATL-1'), Issue('ATL-2'), Issue('ATL-3')];
  Assert.AreEqual(2, Integer(Length(TAtlasCommentPlan.Recent(mIssues, 2))));
  Assert.AreEqual('ATL-1', TAtlasCommentPlan.Recent(mIssues, 2)[0].Key);
  Assert.AreEqual(3, Integer(Length(TAtlasCommentPlan.Recent(mIssues, 10))));
  Assert.AreEqual(0, Integer(Length(TAtlasCommentPlan.Recent(nil, 10))));
end;

procedure TAtlasCommentPlanTests.LogsOnlyRealErrors;
begin
  Assert.IsTrue(TAtlasCommentPlan.LogsUsersError(TAtlasCiFetchError.Network));
  Assert.IsTrue(TAtlasCommentPlan.LogsUsersError(TAtlasCiFetchError.NotFound));
  Assert.IsFalse(TAtlasCommentPlan.LogsUsersError(TAtlasCiFetchError.Cancelled));
  Assert.IsTrue(TAtlasCommentPlan.LogsIssuesError(TAtlasCiFetchError.Timeout));
  Assert.IsFalse(TAtlasCommentPlan.LogsIssuesError(TAtlasCiFetchError.NotFound), 'Kennung gibt es nicht');
  Assert.IsFalse(TAtlasCommentPlan.LogsIssuesError(TAtlasCiFetchError.Cancelled));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCommentPlanTests);

end.
