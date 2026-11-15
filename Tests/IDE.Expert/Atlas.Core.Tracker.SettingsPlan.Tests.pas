unit Atlas.Core.Tracker.SettingsPlan.Tests;

// Tests des Abschnitts „Issue-Tracker“ ohne IDE (#1967): Stand einer Verbindung, Ziel für „Werte vom Tracker
// laden“, Name der Verbindung aus der .atlas und anonymes Protokoll.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerSettingsPlanTests = class
  public
    [Test]
    procedure StateNeedsTokenThenKnownResult;
    [Test]
    procedure ValuesTargetFromTeamFileOnSameServer;
    [Test]
    procedure TeamNameAndKeys;
    [Test]
    procedure LogIsAnonymous;
  end;

implementation

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.QueryTest,
  Atlas.Core.Tracker.SettingsPlan;

procedure TAtlasTrackerSettingsPlanTests.StateNeedsTokenThenKnownResult;
var
  mKnown: TAtlasTrackerTokenStatus;
begin
  mKnown := TAtlasTrackerTokenStatus.Create(TAtlasTrackerTokenState.Verified, 1, 200);
  Assert.AreEqual(Integer(Ord(TAtlasTrackerTokenState.Missing)),
    Integer(Ord(TAtlasTrackerSettingsPlan.StateOf(False, True, mKnown).State)), 'ohne Token');
  Assert.AreEqual(Integer(Ord(TAtlasTrackerTokenState.Verified)),
    Integer(Ord(TAtlasTrackerSettingsPlan.StateOf(True, True, mKnown).State)));
  Assert.AreEqual(Integer(Ord(TAtlasTrackerTokenState.Saved)),
    Integer(Ord(TAtlasTrackerSettingsPlan.StateOf(True, False, mKnown).State)), 'noch nicht geprüft');
end;

procedure TAtlasTrackerSettingsPlanTests.ValuesTargetFromTeamFileOnSameServer;
var
  mTarget, mTeam: TAtlasTrackerTarget;
begin
  mTarget := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, 'https://github.com', '', '');
  mTeam := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, 'https://GitHub.com', 'a/b', '');
  Assert.AreEqual('a/b', TAtlasTrackerSettingsPlan.ValuesTarget(mTarget, True, mTeam).Project);
  Assert.AreEqual('', TAtlasTrackerSettingsPlan.ValuesTarget(mTarget, False, mTeam).Project, 'ohne .atlas');
  mTeam := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cYouTrack, 'https://github.com', 'ATL', '');
  Assert.AreEqual('', TAtlasTrackerSettingsPlan.ValuesTarget(mTarget, True, mTeam).Project, 'anderer Anbieter');
  mTeam := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, 'https://git.firma.local', 'a/b', '');
  Assert.AreEqual('', TAtlasTrackerSettingsPlan.ValuesTarget(mTarget, True, mTeam).Project, 'anderer Server');
end;

procedure TAtlasTrackerSettingsPlanTests.TeamNameAndKeys;
var
  mTarget: TAtlasTrackerTarget;
begin
  Assert.AreEqual('App', TAtlasTrackerSettingsPlan.TeamName('C:\Src\App.dproj'));
  mTarget := TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, 'https://GitHub.com', 'a/b', '');
  Assert.AreEqual(TAtlasTrackerSettingsPlan.StateKey(mTarget), TAtlasTrackerSettingsPlan.StateKey(
    TAtlasTrackerTarget.Create(TAtlasTrackerTarget.cGitHub, 'https://github.com', 'a/b', '')), 'klein');
  Assert.AreEqual('verified', TAtlasTrackerSettingsPlan.TokenStateKey(TAtlasTrackerTokenState.Verified));
  Assert.AreEqual('unexpected', TAtlasTrackerSettingsPlan.TokenStateKey(TAtlasTrackerTokenState.Unexpected));
  Assert.AreEqual('queryRejected', TAtlasTrackerSettingsPlan.OutcomeKey(TAtlasTrackerQueryOutcome.QueryRejected));
  Assert.AreEqual('unreachable', TAtlasTrackerSettingsPlan.OutcomeKey(TAtlasTrackerQueryOutcome.Unreachable));
end;

procedure TAtlasTrackerSettingsPlanTests.LogIsAnonymous;
begin
  Assert.AreEqual('Issue-Tracker: Verbindung geprüft (rejected)',
    TAtlasTrackerSettingsPlan.CheckedLog(TAtlasTrackerTokenState.Rejected));
  Assert.AreEqual('Issue-Tracker: Abfrage getestet (GitHub, empty)',
    TAtlasTrackerSettingsPlan.QueryLog('GitHub', TAtlasTrackerQueryOutcome.Empty));
  Assert.AreEqual('Issue-Tracker: Werte geladen (' + TAtlasCiBuild.ErrorKey(TAtlasCiFetchError.None) +
    ', 3 Zustände)', TAtlasTrackerSettingsPlan.ValuesLog(TAtlasCiFetchError.None, 3));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerSettingsPlanTests);

end.
