unit Atlas.Core.Debug.ExceptionDialogFlow.Tests;

// Tests für die Entscheidungen beim Exception-Dialog der IDE außerhalb des Erkennens (#517, #1967): durchsuchte
// Formulare, Ausblenden, Ablauf des Wartens, Knöpfe; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasExceptionDialogFlowTests = class
  public
    [Test]
    procedure OpenFormsModalOnlyWhenArmed;
    [Test]
    procedure HiddenFormsBeforeShow;
    [Test]
    procedure HideOnlyOnceWhenArmed;
    [Test]
    procedure TimeoutOnlyWhileWatching;
    [Test]
    procedure ClickNeedsFoundButton;
  end;

implementation

uses
  Atlas.Core.Debug.ExceptionDialogFlow;

{ TAtlasExceptionDialogFlowTests }

procedure TAtlasExceptionDialogFlowTests.OpenFormsModalOnlyWhenArmed;
begin
  Assert.IsTrue(TAtlasExceptionDialogFlow.ScansOpen(True, False, False, False));
  Assert.IsFalse(TAtlasExceptionDialogFlow.ScansOpen(True, False, True, False));
  Assert.IsTrue(TAtlasExceptionDialogFlow.ScansOpen(True, False, True, True));
  Assert.IsFalse(TAtlasExceptionDialogFlow.ScansOpen(False, False, False, True));
  Assert.IsFalse(TAtlasExceptionDialogFlow.ScansOpen(True, True, False, True));
end;

procedure TAtlasExceptionDialogFlowTests.HiddenFormsBeforeShow;
begin
  Assert.IsTrue(TAtlasExceptionDialogFlow.ScansHidden(False, False, False));
  Assert.IsFalse(TAtlasExceptionDialogFlow.ScansHidden(True, False, False));
  Assert.IsFalse(TAtlasExceptionDialogFlow.ScansHidden(False, True, False));
  Assert.IsFalse(TAtlasExceptionDialogFlow.ScansHidden(False, False, True));
end;

procedure TAtlasExceptionDialogFlowTests.HideOnlyOnceWhenArmed;
begin
  Assert.IsTrue(TAtlasExceptionDialogFlow.MayHide(True, False));
  Assert.IsFalse(TAtlasExceptionDialogFlow.MayHide(False, False));
  Assert.IsFalse(TAtlasExceptionDialogFlow.MayHide(True, True));
end;

procedure TAtlasExceptionDialogFlowTests.TimeoutOnlyWhileWatching;
begin
  Assert.IsFalse(TAtlasExceptionDialogFlow.TimedOut(False, 1999, 0, 2000));
  Assert.IsTrue(TAtlasExceptionDialogFlow.TimedOut(False, 2000, 0, 2000));
  Assert.IsFalse(TAtlasExceptionDialogFlow.TimedOut(True, 9000, 0, 2000));
end;

procedure TAtlasExceptionDialogFlowTests.ClickNeedsFoundButton;
begin
  Assert.IsTrue(TAtlasExceptionDialogFlow.CanClick(True, 1, 2));
  Assert.IsFalse(TAtlasExceptionDialogFlow.CanClick(True, 2, 2));
  Assert.IsFalse(TAtlasExceptionDialogFlow.CanClick(True, -1, 2));
  Assert.IsFalse(TAtlasExceptionDialogFlow.CanClick(False, 0, 2));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExceptionDialogFlowTests);

end.
