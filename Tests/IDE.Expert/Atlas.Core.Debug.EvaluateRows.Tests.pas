unit Atlas.Core.Debug.EvaluateRows.Tests;

// Tests für die Entscheidungen des Fensters „Auswerten“ über die Zeilen (#784, #1967): Ergebnis an den Knoten,
// „kein Zugriff“ (#840), neu auswerten, Felder aus dem Index sammeln, Antwort der Feldanfrage, festgeheftete
// Zeilen beim Projektwechsel; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasEvalRowsTests = class
  public
    [Test]
    procedure ErrorTextMarksUnavailable;
    [Test]
    procedure PutValueSetsValueErrorOrUnavailable;
    [Test]
    procedure MarkPendingDropsPartsAndKeepsFields;
    [Test]
    procedure IndexFieldKeysClearsLoadedIndexFields;
    [Test]
    procedure CoversRowAndItsFields;
    [Test]
    procedure AcceptFieldsPrefersFieldsThenParts;
    [Test]
    procedure AcceptFieldsIgnoresLoadedIndexFields;
    [Test]
    procedure ReplacePinnedKeepsOtherRows;
  end;

implementation

uses
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.EvaluateRows;

function Value(AState: TAtlasDebugValueState; const AText: string): TAtlasDebugValue;
begin
  Result := Default(TAtlasDebugValue);
  Result.State := AState;
  Result.Text := AText;
end;

function NoMark: TAtlasEvalUnavailable;
begin
  Result := TAtlasEvalUnavailable.Create('', nil);
end;

{ TAtlasEvalRowsTests }

procedure TAtlasEvalRowsTests.ErrorTextMarksUnavailable;
var
  mMark: TAtlasEvalUnavailable;
begin
  mMark := TAtlasEvalUnavailable.Create('<kein Zugriff>', ['eigener Text']);
  Assert.AreEqual('<kein Zugriff> optimized out', TAtlasEvalRows.ErrorText('optimized out', mMark));
  Assert.AreEqual('<kein Zugriff> eigener Text', TAtlasEvalRows.ErrorText('eigener Text', mMark));
  Assert.AreEqual('E2003 Undeklariert', TAtlasEvalRows.ErrorText('E2003 Undeklariert', mMark));
  // Abgeschaltet: ohne Beschriftung bleibt der Text, wie er ist.
  Assert.AreEqual('optimized out', TAtlasEvalRows.ErrorText('optimized out', NoMark));
end;

procedure TAtlasEvalRowsTests.PutValueSetsValueErrorOrUnavailable;
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
begin
  mList := TAtlasEvalList.Create;
  try
    mNode := mList.Add('X');
    TAtlasEvalRows.PutValue(mList, mNode, Value(TAtlasDebugValueState.Value, '42'), NoMark);
    Assert.AreEqual<TAtlasEvalState>(TAtlasEvalState.Value, mNode.State);
    Assert.AreEqual('42', mNode.Value);
    TAtlasEvalRows.PutValue(mList, mNode, Value(TAtlasDebugValueState.Failed, 'optimized out'),
      TAtlasEvalUnavailable.Create('<kein Zugriff>', nil));
    Assert.AreEqual<TAtlasEvalState>(TAtlasEvalState.Error, mNode.State);
    Assert.AreEqual('<kein Zugriff> optimized out', mNode.Value);
    TAtlasEvalRows.PutValue(mList, mNode, Value(TAtlasDebugValueState.None, ''), NoMark);
    Assert.AreEqual<TAtlasEvalState>(TAtlasEvalState.Unavailable, mNode.State);
  finally
    mList.Free;
  end;
end;

procedure TAtlasEvalRowsTests.MarkPendingDropsPartsAndKeepsFields;
var
  mList: TAtlasEvalList;
  mParts, mFields: TAtlasEvalNode;
begin
  mList := TAtlasEvalList.Create;
  try
    mParts := mList.Add('P');
    mList.SetResult(mParts, True, '(A: 1; B: 2)');
    Assert.IsTrue(mList.SetParts(mParts));
    mFields := mList.Add('F');
    mList.SetResult(mFields, True, '(A: 1)');
    mList.SetFields(mFields, ['A']);
    mFields.Children[0].State := TAtlasEvalState.Value;
    TAtlasEvalRows.MarkPending(mParts);
    TAtlasEvalRows.MarkPending(mFields);
    Assert.AreEqual<TAtlasEvalState>(TAtlasEvalState.Pending, mParts.State);
    Assert.AreEqual(0, mParts.ChildCount);
    Assert.AreEqual<TAtlasEvalState>(TAtlasEvalState.Pending, mFields.State);
    Assert.AreEqual(1, mFields.ChildCount);
    Assert.AreEqual<TAtlasEvalState>(TAtlasEvalState.Pending, mFields.Children[0].State);
  finally
    mList.Free;
  end;
end;

procedure TAtlasEvalRowsTests.IndexFieldKeysClearsLoadedIndexFields;
var
  mList: TAtlasEvalList;
  mOpen, mClosed, mParts: TAtlasEvalNode;
  mKeys: TArray<string>;
begin
  mList := TAtlasEvalList.Create;
  try
    mOpen := mList.Add('Offen');
    mOpen.Expanded := True;
    mList.SetFields(mOpen, ['A', 'B']);
    mClosed := mList.Add('Zu');
    mList.SetFields(mClosed, ['A']);
    mParts := mList.Add('Teile');
    mList.SetResult(mParts, True, '(A: 1)');
    mParts.Expanded := True;
    mList.SetParts(mParts);
    mKeys := TAtlasEvalRows.IndexFieldKeys(mList);
    Assert.AreEqual(1, Integer(Length(mKeys)));
    Assert.AreEqual(mOpen.Key, mKeys[0]);
    Assert.AreEqual(0, mOpen.ChildCount);
    Assert.AreEqual(1, mClosed.ChildCount);
    Assert.AreEqual(1, mParts.ChildCount);
  finally
    mList.Free;
  end;
end;

procedure TAtlasEvalRowsTests.CoversRowAndItsFields;
begin
  Assert.IsTrue(TAtlasEvalRows.Covers('A', 'A'));
  Assert.IsTrue(TAtlasEvalRows.Covers('A', 'A'#1'Feld'));
  Assert.IsFalse(TAtlasEvalRows.Covers('A', 'AB'));
  Assert.IsFalse(TAtlasEvalRows.Covers('A', ''));
end;

procedure TAtlasEvalRowsTests.AcceptFieldsPrefersFieldsThenParts;
var
  mList: TAtlasEvalList;
  mNode, mEmpty: TAtlasEvalNode;
begin
  mList := TAtlasEvalList.Create;
  try
    mNode := mList.Add('R');
    mList.SetResult(mNode, True, '(A: 1; B: 2)');
    Assert.IsTrue(TAtlasEvalRows.AcceptFields(mList, mNode, nil));
    Assert.IsTrue(mNode.FromParts);
    Assert.AreEqual(2, mNode.ChildCount);
    // Felder des Index ersetzen die Teile.
    Assert.IsTrue(TAtlasEvalRows.AcceptFields(mList, mNode, ['X']));
    Assert.AreEqual(1, mNode.ChildCount);
    Assert.AreEqual('R.X', mNode.Children[0].Expression);
    mEmpty := mList.Add('S');
    mList.SetResult(mEmpty, True, '7');
    Assert.IsTrue(TAtlasEvalRows.AcceptFields(mList, mEmpty, nil));
    Assert.IsTrue(mEmpty.ChildrenLoaded);
    Assert.AreEqual(0, mEmpty.ChildCount);
  finally
    mList.Free;
  end;
end;

procedure TAtlasEvalRowsTests.AcceptFieldsIgnoresLoadedIndexFields;
var
  mList: TAtlasEvalList;
  mNode: TAtlasEvalNode;
begin
  mList := TAtlasEvalList.Create;
  try
    mNode := mList.Add('R');
    mList.SetFields(mNode, ['A']);
    Assert.IsFalse(TAtlasEvalRows.AcceptFields(mList, mNode, ['A', 'B']));
    Assert.AreEqual(1, mNode.ChildCount);
    Assert.IsFalse(TAtlasEvalRows.AcceptFields(mList, nil, ['A']));
  finally
    mList.Free;
  end;
end;

procedure TAtlasEvalRowsTests.ReplacePinnedKeepsOtherRows;
var
  mList: TAtlasEvalList;
begin
  mList := TAtlasEvalList.Create;
  try
    mList.Add('Alt').Pinned := True;
    mList.Add('Frei');
    // Gespeichert jüngste zuerst: angefügt wird die älteste zuerst.
    TAtlasEvalRows.ReplacePinned(mList, ['Neu2', 'Neu1', ' '], False);
    Assert.AreEqual(3, mList.Count);
    Assert.AreEqual('Frei', mList.Roots[0].Expression);
    Assert.AreEqual('Neu1', mList.Roots[1].Expression);
    Assert.AreEqual('Neu2', mList.Roots[2].Expression);
    Assert.IsTrue(mList.Roots[1].Pinned);
    Assert.AreEqual<TAtlasEvalState>(TAtlasEvalState.Unavailable, mList.Roots[1].State);
    TAtlasEvalRows.ReplacePinned(mList, ['Neu3'], True);
    Assert.AreEqual(2, mList.Count);
    Assert.AreEqual<TAtlasEvalState>(TAtlasEvalState.Pending, mList.Roots[1].State);
  finally
    mList.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEvalRowsTests);

end.
