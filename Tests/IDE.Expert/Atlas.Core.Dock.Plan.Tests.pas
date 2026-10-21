unit Atlas.Core.Dock.Plan.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDockPlanTests = class
  public
    [Test]
    procedure CreatesWhenNoForm;
    [Test]
    procedure CreatesWhenFormGoneButFrameLeft;
    [Test]
    procedure RecreatesFormWithoutFrame;
    [Test]
    procedure RevealsLivingWindow;
    [Test]
    procedure UnavailableWithoutServices;
    [Test]
    procedure RevealsWithoutServicesWhenAlive;
    [Test]
    procedure FrameNotUsableWithoutForm;
    [Test]
    procedure ShownNeedsAllHosts;
  end;

implementation

uses
  Atlas.Core.Dock.Plan;

{ TAtlasDockPlanTests }

procedure TAtlasDockPlanTests.CreatesWhenNoForm;
begin
  Assert.IsTrue(TAtlasDockPlan.ShowStep(True, False, False) = TAtlasDockStep.CreateForm);
end;

procedure TAtlasDockPlanTests.CreatesWhenFormGoneButFrameLeft;
begin
  // Die IDE hat die Form freigegeben, der Frame-Zeiger ist veraltet: neu anlegen statt toten Frame benutzen.
  Assert.IsTrue(TAtlasDockPlan.ShowStep(True, False, True) = TAtlasDockStep.CreateForm);
end;

procedure TAtlasDockPlanTests.RecreatesFormWithoutFrame;
begin
  Assert.IsTrue(TAtlasDockPlan.ShowStep(True, True, False) = TAtlasDockStep.RecreateForm);
end;

procedure TAtlasDockPlanTests.RevealsLivingWindow;
begin
  // Nach dem Schließen über das X lebt die Form noch (versteckt): nur wieder sichtbar machen.
  Assert.IsTrue(TAtlasDockPlan.ShowStep(True, True, True) = TAtlasDockStep.RevealForm);
end;

procedure TAtlasDockPlanTests.UnavailableWithoutServices;
begin
  Assert.IsTrue(TAtlasDockPlan.ShowStep(False, False, False) = TAtlasDockStep.Unavailable);
  Assert.IsTrue(TAtlasDockPlan.ShowStep(False, True, False) = TAtlasDockStep.Unavailable);
end;

procedure TAtlasDockPlanTests.RevealsWithoutServicesWhenAlive;
begin
  Assert.IsTrue(TAtlasDockPlan.ShowStep(False, True, True) = TAtlasDockStep.RevealForm);
end;

procedure TAtlasDockPlanTests.FrameNotUsableWithoutForm;
begin
  Assert.IsFalse(TAtlasDockPlan.FrameUsable(False, True));
  Assert.IsFalse(TAtlasDockPlan.FrameUsable(True, False));
  Assert.IsTrue(TAtlasDockPlan.FrameUsable(True, True));
end;

procedure TAtlasDockPlanTests.ShownNeedsAllHosts;
begin
  Assert.IsTrue(TAtlasDockPlan.Shown(True, []));
  Assert.IsTrue(TAtlasDockPlan.Shown(True, [True, True]));
  // Angedockt in einem versteckten Dock-Fenster: Form.Visible allein täuscht.
  Assert.IsFalse(TAtlasDockPlan.Shown(True, [True, False]));
  Assert.IsFalse(TAtlasDockPlan.Shown(False, [True]));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDockPlanTests);

end.
