unit Atlas.Core.Debug.EditValueFlow.Tests;

// Tests für die Entscheidungen beim Ändern von Werten außerhalb von Prüfung und Ablage (#868, #1967): Aktionen,
// Antworten, gesetzter Text, Rückgängig und gemerkte Änderung; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasEditValueFlowTests = class
  public
    [Test]
    procedure OwnActionsOnly;
    [Test]
    procedure OnlyNewestAnswerWhileStopped;
    [Test]
    procedure DirectValueTakesCheckedText;
    [Test]
    procedure UndoSetsOldValue;
    [Test]
    procedure ChangePrefersDebuggerOutcome;
  end;

implementation

uses
  Atlas.Core.Debug.EditValue,
  Atlas.Core.Debug.EditValueFlow;

const
  /// <summary>Aktion „Anheften“ (#526), gehört nicht hierher.</summary>
  cPinAction = 526;

function Place: TAtlasEditPlace;
begin
  Result := Default(TAtlasEditPlace);
  Result.FileName := 'Kunden.pas';
  Result.Line := 12;
  Result.Expression := 'K.Betrag';
  Result.Value := '125';
end;

function Check(AProblem: TAtlasEditProblem; const AValue: string): TAtlasEditCheck;
begin
  Result := Default(TAtlasEditCheck);
  Result.Problem := AProblem;
  Result.Value := AValue;
end;

{ TAtlasEditValueFlowTests }

procedure TAtlasEditValueFlowTests.OwnActionsOnly;
begin
  Assert.IsTrue(TAtlasEditValueFlow.OwnAction(TAtlasEditValueFlow.cEditAction));
  Assert.IsTrue(TAtlasEditValueFlow.OwnAction(TAtlasEditValueFlow.cToggleAction));
  Assert.IsTrue(TAtlasEditValueFlow.OwnAction(TAtlasEditValueFlow.cUndoAction));
  Assert.IsFalse(TAtlasEditValueFlow.OwnAction(cPinAction));
end;

procedure TAtlasEditValueFlowTests.OnlyNewestAnswerWhileStopped;
begin
  Assert.IsTrue(TAtlasEditValueFlow.Current(3, 3, True));
  Assert.IsFalse(TAtlasEditValueFlow.Current(2, 3, True));
  Assert.IsFalse(TAtlasEditValueFlow.Current(3, 3, False));
end;

procedure TAtlasEditValueFlowTests.DirectValueTakesCheckedText;
begin
  Assert.AreEqual('''x''', TAtlasEditValueFlow.Final('x', 'x', Check(TAtlasEditProblem.None, '''x''')));
  // Prüfung misslingt: unverändert.
  Assert.AreEqual('x', TAtlasEditValueFlow.Final('x', 'x', Check(TAtlasEditProblem.NotInteger, '')));
  // Aus dem Dialog: schon umgesetzt.
  Assert.AreEqual('150', TAtlasEditValueFlow.Final('', '150', Check(TAtlasEditProblem.None, '$96')));
end;

procedure TAtlasEditValueFlowTests.UndoSetsOldValue;
var
  mPlace: TAtlasEditPlace;
  mChange: TAtlasEditChange;
begin
  mChange := Default(TAtlasEditChange);
  mChange.Line := 14;
  mChange.OldValue := '125';
  mChange.NewValue := '150';
  mPlace := Place;
  TAtlasEditValueFlow.ApplyUndo(mPlace, mChange);
  Assert.AreEqual(14, mPlace.Line);
  Assert.AreEqual('150', mPlace.Value);
  Assert.AreEqual('125', mPlace.Direct);
  Assert.IsTrue(mPlace.Undoing);
end;

procedure TAtlasEditValueFlowTests.ChangePrefersDebuggerOutcome;
var
  mChange: TAtlasEditChange;
begin
  mChange := TAtlasEditValueFlow.ChangeOf(Place, '150', '');
  Assert.AreEqual('Kunden.pas', mChange.FileName);
  Assert.AreEqual(12, mChange.Line);
  Assert.AreEqual('K.Betrag', mChange.Expression);
  Assert.AreEqual('125', mChange.OldValue);
  Assert.AreEqual('150', mChange.NewValue);
  Assert.AreEqual('150.0', TAtlasEditValueFlow.ChangeOf(Place, '150', '150.0').NewValue);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditValueFlowTests);

end.
