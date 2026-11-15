unit Atlas.Core.Status.FieldPlan.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStatusFieldPlanTests = class
  public
    [Test]
    procedure BadgeTextCapsAtNinetyNine;
    [Test]
    procedure TooltipAddsBadgeHintOnOwnLine;
    [Test]
    procedure PanelShownUnlessRelocated;
    [Test]
    procedure ExtraPanelsMoveWithRelocation;
    [Test]
    procedure ClickOnBadgeWindowOrExtra;
    [Test]
    procedure TogglesFollowGestureSetting;
    [Test]
    procedure TogglesNeedTargetPanelAndMouse;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Status.FieldPlan;

{ TAtlasStatusFieldPlanTests }

procedure TAtlasStatusFieldPlanTests.BadgeTextCapsAtNinetyNine;
begin
  Assert.AreEqual('0', TAtlasStatusFieldPlan.BadgeText(0));
  Assert.AreEqual('99', TAtlasStatusFieldPlan.BadgeText(99));
  Assert.AreEqual('99+', TAtlasStatusFieldPlan.BadgeText(100));
end;

procedure TAtlasStatusFieldPlanTests.TooltipAddsBadgeHintOnOwnLine;
begin
  Assert.AreEqual('Index 45 %' + sLineBreak + '3 neue', TAtlasStatusFieldPlan.Tooltip('Index 45 %', 3, '3 neue'));
  Assert.AreEqual('3 neue', TAtlasStatusFieldPlan.Tooltip('', 3, '3 neue'));
  Assert.AreEqual('Index 45 %', TAtlasStatusFieldPlan.Tooltip('Index 45 %', 0, '3 neue'));
  Assert.AreEqual('Index 45 %', TAtlasStatusFieldPlan.Tooltip('Index 45 %', 3, ''));
end;

procedure TAtlasStatusFieldPlanTests.PanelShownUnlessRelocated;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.StatusField := True;
  Assert.IsTrue(TAtlasStatusFieldPlan.PanelShown(mSettings, False));
  Assert.IsFalse(TAtlasStatusFieldPlan.PanelShown(mSettings, True));
  mSettings.StatusField := False;
  Assert.IsFalse(TAtlasStatusFieldPlan.PanelShown(mSettings, False));
end;

procedure TAtlasStatusFieldPlanTests.ExtraPanelsMoveWithRelocation;
begin
  Assert.AreEqual(2, TAtlasStatusFieldPlan.ExtraPanels(2, False));
  Assert.AreEqual(0, TAtlasStatusFieldPlan.ExtraPanels(2, True));
end;

procedure TAtlasStatusFieldPlanTests.ClickOnBadgeWindowOrExtra;
begin
  // Plakette rechts im Feld ab Pixel 80.
  Assert.AreEqual<TAtlasStatusFieldClick>(TAtlasStatusFieldClick.Badge,
    TAtlasStatusFieldPlan.Click(0, 1, 3, True, 85, 80));
  Assert.AreEqual<TAtlasStatusFieldClick>(TAtlasStatusFieldClick.Window,
    TAtlasStatusFieldPlan.Click(0, 1, 3, True, 79, 80));
  Assert.AreEqual<TAtlasStatusFieldClick>(TAtlasStatusFieldClick.Window,
    TAtlasStatusFieldPlan.Click(0, 1, 0, True, 85, 80));
  Assert.AreEqual<TAtlasStatusFieldClick>(TAtlasStatusFieldClick.Window,
    TAtlasStatusFieldPlan.Click(0, 1, 3, False, 85, 80));
  Assert.AreEqual<TAtlasStatusFieldClick>(TAtlasStatusFieldClick.Extra,
    TAtlasStatusFieldPlan.Click(1, 1, 3, True, 85, 80));
  Assert.AreEqual<TAtlasStatusFieldClick>(TAtlasStatusFieldClick.None,
    TAtlasStatusFieldPlan.Click(2, 1, 3, True, 85, 80));
  Assert.AreEqual<TAtlasStatusFieldClick>(TAtlasStatusFieldClick.None,
    TAtlasStatusFieldPlan.Click(-1, 1, 3, True, 85, 80));
end;

procedure TAtlasStatusFieldPlanTests.TogglesFollowGestureSetting;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  if not (mSettings.StatusTogglesOnRightClick and mSettings.StatusTogglesOnDoubleClick) then
  begin
    Assert.Pass('Vorgabe öffnet nicht mit beiden Gesten');
  end;
  Assert.IsTrue(TAtlasStatusFieldPlan.OpensToggles(TAtlasStatusFieldGesture.RightButton, mSettings, True, True,
    False));
  Assert.IsTrue(TAtlasStatusFieldPlan.OpensToggles(TAtlasStatusFieldGesture.DoubleClick, mSettings, True, True,
    False));
  Assert.IsTrue(TAtlasStatusFieldPlan.OpensToggles(TAtlasStatusFieldGesture.ContextMenu, mSettings, True, True,
    False));
  // Umschalt+F10 bleibt bei der IDE.
  Assert.IsFalse(TAtlasStatusFieldPlan.OpensToggles(TAtlasStatusFieldGesture.ContextMenu, mSettings, True, True,
    True));
end;

procedure TAtlasStatusFieldPlanTests.TogglesNeedTargetPanelAndMouse;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(TAtlasStatusFieldPlan.OpensToggles(TAtlasStatusFieldGesture.RightButton, mSettings, False, True,
    False));
  Assert.IsFalse(TAtlasStatusFieldPlan.OpensToggles(TAtlasStatusFieldGesture.DoubleClick, mSettings, True, False,
    False));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatusFieldPlanTests);

end.
