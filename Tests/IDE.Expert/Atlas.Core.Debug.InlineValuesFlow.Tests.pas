unit Atlas.Core.Debug.InlineValuesFlow.Tests;

// Tests für die Entscheidungen der Werte im Editor (#508, #1967): Schritt nach einem Wert, Frist, Ende der
// Zeitscheibe, Spalte und Zeilenvergleich; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasInlineValuesFlowTests = class
  public
    [Test]
    procedure StepFollowsValueState;
    [Test]
    procedure DeferredAfterTimeout;
    [Test]
    procedure SliceDoneWithoutWork;
    [Test]
    procedure ColumnAndLineWithTabs;
  end;

implementation

uses
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.InlineValuesFlow;

{ TAtlasInlineValuesFlowTests }

procedure TAtlasInlineValuesFlowTests.StepFollowsValueState;
begin
  Assert.AreEqual<TAtlasInlineStep>(TAtlasInlineStep.Wait,
    TAtlasInlineValuesFlow.StepOf(TAtlasDebugValueState.Pending));
  Assert.AreEqual<TAtlasInlineStep>(TAtlasInlineStep.Next, TAtlasInlineValuesFlow.StepOf(TAtlasDebugValueState.Value));
  Assert.AreEqual<TAtlasInlineStep>(TAtlasInlineStep.Next,
    TAtlasInlineValuesFlow.StepOf(TAtlasDebugValueState.Failed));
  Assert.AreEqual<TAtlasInlineStep>(TAtlasInlineStep.Dropped,
    TAtlasInlineValuesFlow.StepOf(TAtlasDebugValueState.None));
end;

procedure TAtlasInlineValuesFlowTests.DeferredAfterTimeout;
begin
  Assert.IsFalse(TAtlasInlineValuesFlow.DeferredExpired(499, 500));
  Assert.IsTrue(TAtlasInlineValuesFlow.DeferredExpired(500, 500));
end;

procedure TAtlasInlineValuesFlowTests.SliceDoneWithoutWork;
begin
  Assert.IsTrue(TAtlasInlineValuesFlow.SliceDone('', False));
  Assert.IsFalse(TAtlasInlineValuesFlow.SliceDone('Count', False));
  Assert.IsFalse(TAtlasInlineValuesFlow.SliceDone('', True));
end;

procedure TAtlasInlineValuesFlowTests.ColumnAndLineWithTabs;
begin
  Assert.AreEqual('C:\P\Unit1.pas|TForm1.Click', TAtlasInlineValuesFlow.ContextOf('C:\P\Unit1.pas',
    'TForm1.Click'));
  Assert.AreEqual(1, TAtlasInlineValuesFlow.ColumnOf('abc', 0, 4));
  Assert.AreEqual(4, TAtlasInlineValuesFlow.ColumnOf('abc', 3, 4));
  // Tab auf Spalte 4 aufgelöst.
  Assert.AreEqual(6, TAtlasInlineValuesFlow.ColumnOf(#9'x', 2, 4));
  Assert.AreEqual(1, TAtlasInlineValuesFlow.ColumnOf('abc', -2, 4));
  Assert.IsTrue(TAtlasInlineValuesFlow.SameLine(#9'x := 1;  ', '    x := 1;', 4));
  Assert.IsFalse(TAtlasInlineValuesFlow.SameLine('x := 2;', 'x := 1;', 4));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasInlineValuesFlowTests);

end.
