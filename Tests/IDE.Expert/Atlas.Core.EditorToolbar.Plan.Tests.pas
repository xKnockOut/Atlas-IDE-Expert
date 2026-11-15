unit Atlas.Core.EditorToolbar.Plan.Tests;

// Atlas-Editorleiste (#1101, #1967): Takt, Platz neben den Brotkrumen,
// Abschnittsknöpfe, Hooks und Sprungziele.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasToolbarPlanTests = class
  public
    [Test]
    procedure TickClearsWithoutBarAndPoints;
    [Test]
    procedure TickWaitsWithoutEditor;
    [Test]
    procedure PlacementFollowsPosition;
    [Test]
    procedure InlineWidthHalfRowAtMost;
    [Test]
    procedure ReorderTopFixesWrongSide;
    [Test]
    procedure PlainCaptionDropsPrefix;
    [Test]
    procedure SectionTargetsById;
    [Test]
    procedure SectionPressedCountsFinalization;
    [Test]
    procedure SectionHintByTarget;
    [Test]
    procedure HookById;
    [Test]
    procedure TopRowUpperThird;
    [Test]
    procedure ReturnColumnAndShiftAnchor;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.Core.EditorToolbar.Sections,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.EditorToolbar.Plan;

{ TAtlasToolbarPlanTests }

procedure TAtlasToolbarPlanTests.TickClearsWithoutBarAndPoints;
var
  mIdle: Integer;
begin
  mIdle := 5;
  Assert.AreEqual<TAtlasToolbarTick>(TAtlasToolbarTick.Clear, TAtlasToolbarPlan.Tick(False, 0, True, mIdle));
  Assert.AreEqual(5, mIdle);
  Assert.AreEqual<TAtlasToolbarTick>(TAtlasToolbarTick.Run, TAtlasToolbarPlan.Tick(False, 1, True, mIdle));
  Assert.AreEqual(0, mIdle);
  Assert.AreEqual<TAtlasToolbarTick>(TAtlasToolbarTick.Run, TAtlasToolbarPlan.Tick(True, 0, True, mIdle));
end;

procedure TAtlasToolbarPlanTests.TickWaitsWithoutEditor;
var
  mIdle, mIndex: Integer;
begin
  mIdle := 0;
  for mIndex := 1 to TAtlasToolbarPlan.cSlowTicks - 1 do
  begin
    Assert.AreEqual<TAtlasToolbarTick>(TAtlasToolbarTick.Wait, TAtlasToolbarPlan.Tick(True, 0, False, mIdle));
  end;
  Assert.AreEqual<TAtlasToolbarTick>(TAtlasToolbarTick.Run, TAtlasToolbarPlan.Tick(True, 0, False, mIdle));
  Assert.AreEqual(0, mIdle);
end;

procedure TAtlasToolbarPlanTests.PlacementFollowsPosition;
begin
  Assert.AreEqual<TAtlasToolbarPlacement>(TAtlasToolbarPlacement.InBreadcrumbs,
    TAtlasToolbarPlan.PlacementOf(TAtlasToolbarPlan.cPositionInline, True));
  Assert.AreEqual<TAtlasToolbarPlacement>(TAtlasToolbarPlacement.Below,
    TAtlasToolbarPlan.PlacementOf(TAtlasToolbarPlan.cPositionInline, False));
  Assert.AreEqual<TAtlasToolbarPlacement>(TAtlasToolbarPlacement.Above,
    TAtlasToolbarPlan.PlacementOf('ABOVEBREADCRUMBS', True));
  Assert.AreEqual<TAtlasToolbarPlacement>(TAtlasToolbarPlacement.Below,
    TAtlasToolbarPlan.PlacementOf('belowBreadcrumbs', True));
  Assert.AreEqual<TAtlasToolbarPlacement>(TAtlasToolbarPlacement.Below, TAtlasToolbarPlan.PlacementOf('', False));
end;

procedure TAtlasToolbarPlanTests.InlineWidthHalfRowAtMost;
begin
  Assert.AreEqual(80, TAtlasToolbarPlan.InlineWidth(80, 120, 1000));
  Assert.AreEqual(500, TAtlasToolbarPlan.InlineWidth(900, 120, 1000));
  Assert.AreEqual(120, TAtlasToolbarPlan.InlineWidth(900, 120, 100));
end;

procedure TAtlasToolbarPlanTests.ReorderTopFixesWrongSide;
var
  mTop: Integer;
begin
  Assert.IsTrue(TAtlasToolbarPlan.ReorderTop(TAtlasToolbarPlacement.Above, 30, 0, 22, mTop));
  Assert.AreEqual(-1, mTop);
  Assert.IsFalse(TAtlasToolbarPlan.ReorderTop(TAtlasToolbarPlacement.Above, 0, 22, 22, mTop));
  Assert.AreEqual(0, mTop);
  Assert.IsTrue(TAtlasToolbarPlan.ReorderTop(TAtlasToolbarPlacement.Below, 0, 10, 22, mTop));
  Assert.AreEqual(32, mTop);
  Assert.IsFalse(TAtlasToolbarPlan.ReorderTop(TAtlasToolbarPlacement.Below, 22, 0, 22, mTop));
  Assert.AreEqual(22, mTop);
end;

procedure TAtlasToolbarPlanTests.PlainCaptionDropsPrefix;
begin
  Assert.AreEqual('Formatieren', TAtlasToolbarPlan.PlainCaption('Atlas: Formatieren'));
  Assert.AreEqual('Formatieren', TAtlasToolbarPlan.PlainCaption('Formatieren'));
  Assert.AreEqual('atlas: x', TAtlasToolbarPlan.PlainCaption('atlas: x'));
end;

procedure TAtlasToolbarPlanTests.SectionTargetsById;
var
  mTarget: TAtlasSectionTarget;
begin
  Assert.IsTrue(TAtlasToolbarPlan.SectionTargetOf(TAtlasToolbarItems.cGotoInterface, mTarget));
  Assert.AreEqual<TAtlasSectionTarget>(TAtlasSectionTarget.InterfacePart, mTarget);
  Assert.IsTrue(TAtlasToolbarPlan.SectionTargetOf(UpperCase(TAtlasToolbarItems.cGotoImplementation), mTarget));
  Assert.AreEqual<TAtlasSectionTarget>(TAtlasSectionTarget.ImplementationPart, mTarget);
  Assert.IsTrue(TAtlasToolbarPlan.SectionTargetOf(TAtlasToolbarItems.cGotoUses, mTarget));
  Assert.AreEqual<TAtlasSectionTarget>(TAtlasSectionTarget.UsesClause, mTarget);
  Assert.IsTrue(TAtlasToolbarPlan.SectionTargetOf(TAtlasToolbarItems.cGotoInitialization, mTarget));
  Assert.AreEqual<TAtlasSectionTarget>(TAtlasSectionTarget.Initialization_, mTarget);
  Assert.IsFalse(TAtlasToolbarPlan.SectionTargetOf(TAtlasToolbarItems.cCommandPalette, mTarget));
end;

procedure TAtlasToolbarPlanTests.SectionPressedCountsFinalization;
begin
  Assert.IsTrue(TAtlasToolbarPlan.SectionPressed(TAtlasSectionTarget.InterfacePart,
    TAtlasCodeSection.InterfacePart));
  Assert.IsFalse(TAtlasToolbarPlan.SectionPressed(TAtlasSectionTarget.InterfacePart,
    TAtlasCodeSection.ImplementationPart));
  Assert.IsTrue(TAtlasToolbarPlan.SectionPressed(TAtlasSectionTarget.UsesClause, TAtlasCodeSection.UsesClause));
  Assert.IsTrue(TAtlasToolbarPlan.SectionPressed(TAtlasSectionTarget.Initialization_,
    TAtlasCodeSection.Finalization_));
  Assert.IsFalse(TAtlasToolbarPlan.SectionPressed(TAtlasSectionTarget.Initialization_, TAtlasCodeSection.None));
end;

procedure TAtlasToolbarPlanTests.SectionHintByTarget;
begin
  Assert.AreEqual<TAtlasToolbarSectionHint>(TAtlasToolbarSectionHint.NoParts,
    TAtlasToolbarPlan.SectionHint(TAtlasSectionTarget.InterfacePart));
  Assert.AreEqual<TAtlasToolbarSectionHint>(TAtlasToolbarSectionHint.NoParts,
    TAtlasToolbarPlan.SectionHint(TAtlasSectionTarget.ImplementationPart));
  Assert.AreEqual<TAtlasToolbarSectionHint>(TAtlasToolbarSectionHint.NoSection,
    TAtlasToolbarPlan.SectionHint(TAtlasSectionTarget.UsesClause));
  Assert.AreEqual<TAtlasToolbarSectionHint>(TAtlasToolbarSectionHint.NoSection,
    TAtlasToolbarPlan.SectionHint(TAtlasSectionTarget.Initialization_));
end;

procedure TAtlasToolbarPlanTests.HookById;
begin
  Assert.AreEqual<TAtlasToolbarHook>(TAtlasToolbarHook.Findings,
    TAtlasToolbarPlan.HookOf(TAtlasToolbarPlan.cProblemsId));
  Assert.AreEqual<TAtlasToolbarHook>(TAtlasToolbarHook.Back, TAtlasToolbarPlan.HookOf('atlas.navback'));
  Assert.AreEqual<TAtlasToolbarHook>(TAtlasToolbarHook.Forward, TAtlasToolbarPlan.HookOf(TAtlasToolbarPlan.cForwardId));
  Assert.AreEqual<TAtlasToolbarHook>(TAtlasToolbarHook.None,
    TAtlasToolbarPlan.HookOf(TAtlasToolbarItems.cCommandPalette));
  Assert.AreEqual<TAtlasToolbarHook>(TAtlasToolbarHook.None, TAtlasToolbarPlan.HookOf(''));
end;

procedure TAtlasToolbarPlanTests.TopRowUpperThird;
begin
  Assert.AreEqual(91, TAtlasToolbarPlan.TopRow(100, 30));
  Assert.AreEqual(1, TAtlasToolbarPlan.TopRow(3, 30));
  Assert.AreEqual(101, TAtlasToolbarPlan.TopRow(100, 0));
end;

procedure TAtlasToolbarPlanTests.ReturnColumnAndShiftAnchor;
begin
  Assert.AreEqual(4, TAtlasToolbarPlan.ReturnColumn('    Foo;'));
  Assert.AreEqual(0, TAtlasToolbarPlan.ReturnColumn(''));
  Assert.AreEqual(5, TAtlasToolbarPlan.ShiftAnchor(10, True, 5));
  Assert.AreEqual(10, TAtlasToolbarPlan.ShiftAnchor(10, True, 12));
  Assert.AreEqual(10, TAtlasToolbarPlan.ShiftAnchor(10, False, 5));
  Assert.AreEqual(10, TAtlasToolbarPlan.ShiftAnchor(10, True, -1));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasToolbarPlanTests);

end.
