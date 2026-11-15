unit Atlas.Core.Tracker.BlamePlan.Tests;

// Entscheidungen der Issues in der Zeilenhistorie (#1275, #1967) ohne IDE: Stand je Kennung im Hover, Schlüssel,
// Menüeinträge und abgefangene Klicks.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasBlamePlanTests = class
  public
    [Test]
    procedure KeysIgnoreCaseOfIssue;
    [Test]
    procedure LookupStatePerAnswer;
    /// <summary>„Nicht gefunden“ geht vor; ohne Netz bleibt ein vorhandener Stand stehen.</summary>
    [Test]
    procedure ShownStatePrefersNotFoundThenCache;
    [Test]
    procedure MenuTagRoundTrip;
    /// <summary>Umschalt+Rechtsklick bleibt beim Kontextmenü der IDE.</summary>
    [Test]
    procedure CatchesCtrlClickAndRightClick;
  end;

implementation

uses
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Tracker.BlamePlan;

function Shown(AKnown: Boolean; AState: TAtlasBlameKeyState; ACached: Boolean): Integer;
begin
  Result := Ord(TAtlasBlamePlan.ShownState(AKnown, AState, ACached));
end;

{ TAtlasBlamePlanTests }

procedure TAtlasBlamePlanTests.KeysIgnoreCaseOfIssue;
begin
  Assert.AreEqual(TAtlasBlamePlan.StateKey('youtrack|ATL', 'ATL-97'), TAtlasBlamePlan.StateKey('youtrack|ATL', 'atl-97'));
  Assert.AreNotEqual(TAtlasBlamePlan.StateKey('a', 'ATL-97'), TAtlasBlamePlan.StateKey('b', 'ATL-97'));
  Assert.AreEqual('U.pas'#1'10'#1'20'#1'TA.Run'#1'abc'#1'p', TAtlasBlamePlan.CountKey('U.pas', 10, 20, 'TA.Run', 'abc',
    'p'));
end;

procedure TAtlasBlamePlanTests.LookupStatePerAnswer;
begin
  Assert.AreEqual(Integer(Ord(TAtlasBlameKeyState.Found)),
    Integer(Ord(TAtlasBlamePlan.LookupState(True, TAtlasCiFetchError.None))));
  Assert.AreEqual(Integer(Ord(TAtlasBlameKeyState.NotFound)),
    Integer(Ord(TAtlasBlamePlan.LookupState(False, TAtlasCiFetchError.NotFound))));
  Assert.AreEqual(Integer(Ord(TAtlasBlameKeyState.Failed)),
    Integer(Ord(TAtlasBlamePlan.LookupState(False, TAtlasCiFetchError.Timeout))));
end;

procedure TAtlasBlamePlanTests.ShownStatePrefersNotFoundThenCache;
begin
  Assert.AreEqual(Integer(Ord(TAtlasBlameKeyState.NotFound)), Shown(True, TAtlasBlameKeyState.NotFound, True));
  Assert.AreEqual(Integer(Ord(TAtlasBlameKeyState.Found)), Shown(True, TAtlasBlameKeyState.Failed, True));
  Assert.AreEqual(Integer(Ord(TAtlasBlameKeyState.Found)), Shown(False, TAtlasBlameKeyState.Loading, True));
  Assert.AreEqual(Integer(Ord(TAtlasBlameKeyState.Failed)), Shown(True, TAtlasBlameKeyState.Failed, False));
  Assert.AreEqual(Integer(Ord(TAtlasBlameKeyState.Loading)), Shown(True, TAtlasBlameKeyState.Loading, False));
  Assert.AreEqual(Integer(Ord(TAtlasBlameKeyState.Loading)), Shown(False, TAtlasBlameKeyState.Failed, False));
  Assert.AreEqual(Integer(Ord(TAtlasCiFetchError.Timeout)), Integer(Ord(TAtlasBlamePlan.ShownError(
    TAtlasBlameKeyState.Failed, TAtlasCiFetchError.Timeout))));
  Assert.AreEqual(Integer(Ord(TAtlasCiFetchError.None)), Integer(Ord(TAtlasBlamePlan.ShownError(
    TAtlasBlameKeyState.Found, TAtlasCiFetchError.Timeout))));
end;

procedure TAtlasBlamePlanTests.MenuTagRoundTrip;
var
  mTag: Integer;
begin
  mTag := TAtlasBlamePlan.MenuTag(3, TAtlasBlamePlan.cMenuCopy);
  Assert.AreEqual(3, TAtlasBlamePlan.MenuKey(mTag));
  Assert.AreEqual(Integer(TAtlasBlamePlan.cMenuCopy), TAtlasBlamePlan.MenuCommand(mTag));
  Assert.AreEqual(0, TAtlasBlamePlan.MenuKey(TAtlasBlamePlan.cMenuScope));
end;

procedure TAtlasBlamePlanTests.CatchesCtrlClickAndRightClick;
begin
  Assert.IsTrue(TAtlasBlamePlan.Catches(True, False, True, False));
  Assert.IsFalse(TAtlasBlamePlan.Catches(True, False, False, False), 'Linksklick ohne Strg');
  Assert.IsTrue(TAtlasBlamePlan.Catches(False, True, False, False));
  Assert.IsFalse(TAtlasBlamePlan.Catches(False, True, False, True), 'Umschalt+Rechtsklick');
  Assert.AreEqual(Integer(TAtlasBlamePlan.cMenuShow), TAtlasBlamePlan.ClickCommand(False));
  Assert.AreEqual(Integer(TAtlasBlamePlan.cMenuBrowse), TAtlasBlamePlan.ClickCommand(True));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBlamePlanTests);

end.
