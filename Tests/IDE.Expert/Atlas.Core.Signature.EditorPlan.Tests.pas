unit Atlas.Core.Signature.EditorPlan.Tests;

// Entscheidungen des Parameter-Hints im Editor (Atlas.Core.Signature.EditorPlan): Tasten, Schritt nach einer
// Bewegung, Überladung aus dem Detailpanel, Wieder öffnen, Ruhe vor der Platzhalter-Anfrage, linke Kante, Scrollen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSignatureEditorPlanTests = class
  public
    [Test]
    procedure KeysOnlyWhileOpen;
    [Test]
    procedure OverloadKeysNeedSeveralSignatures;
    [Test]
    procedure StepByOpeningParenthesis;
    [Test]
    procedure AnswerFitsSameCallOnly;
    [Test]
    procedure PreferredOverloadByNameAndRange;
    [Test]
    procedure ReopenNotForDismissedCall;
    [Test]
    procedure RemovedParenOnSameLineWhileClosed;
    [Test]
    procedure FormatAsksAfterQuietTicks;
    [Test]
    procedure ParenRunOnlyOnCaretLine;
    [Test]
    procedure ScrollShiftByRows;
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Signature.CallScanner,
  Atlas.Core.Signature.EditorPlan;

function Site(AFound: Boolean; AOpenParen: Integer): TAtlasCallSite;
begin
  Result := Default(TAtlasCallSite);
  Result.Found := AFound;
  Result.OpenParen := AOpenParen;
end;

{ TSignatureEditorPlanTests }

procedure TSignatureEditorPlanTests.KeysOnlyWhileOpen;
begin
  Assert.AreEqual<TAtlasSignatureKey>(TAtlasSignatureKey.Dismiss,
    TAtlasSignatureEditorPlan.Key(TAtlasSignatureEditorPlan.cVkEscape, [], True, 1));
  Assert.AreEqual<TAtlasSignatureKey>(TAtlasSignatureKey.None,
    TAtlasSignatureEditorPlan.Key(TAtlasSignatureEditorPlan.cVkEscape, [], False, 1));
  Assert.AreEqual<TAtlasSignatureKey>(TAtlasSignatureKey.None,
    TAtlasSignatureEditorPlan.Key(TAtlasSignatureEditorPlan.cVkEscape, [ssShift], True, 1));
  Assert.AreEqual<TAtlasSignatureKey>(TAtlasSignatureKey.None, TAtlasSignatureEditorPlan.Key(Ord('A'), [], True, 3));
end;

procedure TSignatureEditorPlanTests.OverloadKeysNeedSeveralSignatures;
begin
  Assert.AreEqual<TAtlasSignatureKey>(TAtlasSignatureKey.PreviousOverload,
    TAtlasSignatureEditorPlan.Key(TAtlasSignatureEditorPlan.cVkUp, [ssAlt], True, 2));
  Assert.AreEqual<TAtlasSignatureKey>(TAtlasSignatureKey.NextOverload,
    TAtlasSignatureEditorPlan.Key(TAtlasSignatureEditorPlan.cVkDown, [ssAlt], True, 2));
  Assert.AreEqual<TAtlasSignatureKey>(TAtlasSignatureKey.None,
    TAtlasSignatureEditorPlan.Key(TAtlasSignatureEditorPlan.cVkDown, [ssAlt], True, 1));
  Assert.AreEqual<TAtlasSignatureKey>(TAtlasSignatureKey.None,
    TAtlasSignatureEditorPlan.Key(TAtlasSignatureEditorPlan.cVkDown, [], True, 2));
end;

procedure TSignatureEditorPlanTests.StepByOpeningParenthesis;
begin
  Assert.AreEqual<TAtlasSignatureStep>(TAtlasSignatureStep.Close, TAtlasSignatureEditorPlan.Step(Site(False, 0), 5));
  Assert.AreEqual<TAtlasSignatureStep>(TAtlasSignatureStep.Close, TAtlasSignatureEditorPlan.Step(Site(True, 9), 5));
  Assert.AreEqual<TAtlasSignatureStep>(TAtlasSignatureStep.ShowOuter,
    TAtlasSignatureEditorPlan.Step(Site(True, 2), 5));
  Assert.AreEqual<TAtlasSignatureStep>(TAtlasSignatureStep.Update, TAtlasSignatureEditorPlan.Step(Site(True, 5), 5));
end;

procedure TSignatureEditorPlanTests.AnswerFitsSameCallOnly;
begin
  Assert.IsTrue(TAtlasSignatureEditorPlan.StillAtCall(Site(True, 5), 5));
  Assert.IsFalse(TAtlasSignatureEditorPlan.StillAtCall(Site(True, 4), 5));
  Assert.IsFalse(TAtlasSignatureEditorPlan.StillAtCall(Site(False, 5), 5));
end;

procedure TSignatureEditorPlanTests.PreferredOverloadByNameAndRange;
begin
  Assert.IsTrue(TAtlasSignatureEditorPlan.TakesOverload('Create', 'create', 1, 3));
  Assert.IsFalse(TAtlasSignatureEditorPlan.TakesOverload('Create', 'Free', 1, 3));
  Assert.IsFalse(TAtlasSignatureEditorPlan.TakesOverload('', '', 1, 3));
  // Die erste Überladung ist ohnehin gewählt; außerhalb der Liste nichts.
  Assert.IsFalse(TAtlasSignatureEditorPlan.TakesOverload('Create', 'Create', 0, 3));
  Assert.IsFalse(TAtlasSignatureEditorPlan.TakesOverload('Create', 'Create', 3, 3));
end;

procedure TSignatureEditorPlanTests.ReopenNotForDismissedCall;
var
  mDismissed: TAtlasSignatureDismissed;
begin
  mDismissed.FileName := 'C:\Src\A.pas';
  mDismissed.OpenParen := 7;
  Assert.IsFalse(TAtlasSignatureEditorPlan.Reopens(Site(True, 7), mDismissed, 'c:\src\a.pas'));
  Assert.IsTrue(TAtlasSignatureEditorPlan.Reopens(Site(True, 8), mDismissed, 'C:\Src\A.pas'));
  Assert.IsTrue(TAtlasSignatureEditorPlan.Reopens(Site(True, 7), mDismissed, 'C:\Src\B.pas'));
  Assert.IsFalse(TAtlasSignatureEditorPlan.Reopens(Site(False, 3), mDismissed, 'C:\Src\B.pas'));
end;

procedure TSignatureEditorPlanTests.RemovedParenOnSameLineWhileClosed;
var
  mLast: TAtlasSignatureLastLine;
begin
  mLast.FileName := 'A.pas';
  mLast.Line := 3;
  mLast.Text := '  Foo(1)';
  Assert.IsTrue(TAtlasSignatureEditorPlan.RemovedParen(mLast, 'a.pas', 3, '  Foo(1', False));
  Assert.IsFalse(TAtlasSignatureEditorPlan.RemovedParen(mLast, 'a.pas', 3, '  Foo(1', True), 'Hint offen');
  Assert.IsFalse(TAtlasSignatureEditorPlan.RemovedParen(mLast, 'a.pas', 4, '  Foo(1', False), 'andere Zeile');
  Assert.IsFalse(TAtlasSignatureEditorPlan.RemovedParen(mLast, 'B.pas', 3, '  Foo(1', False), 'andere Datei');
  Assert.IsFalse(TAtlasSignatureEditorPlan.RemovedParen(mLast, 'a.pas', 3, '  Foo(12)', False), 'getippt');
end;

procedure TSignatureEditorPlanTests.FormatAsksAfterQuietTicks;
var
  mState: TAtlasSignatureFormatState;
  mTick: Integer;
begin
  mState.Text := 'Format(';
  mState.Caret := 7;
  mState.Due := 0;
  // Unverändert und keine Anfrage fällig: nichts.
  Assert.IsFalse(TAtlasSignatureEditorPlan.FormatDue(mState, 'Format(', 7));
  // Geändert: Ruhe beginnt.
  Assert.IsFalse(TAtlasSignatureEditorPlan.FormatDue(mState, 'Format(''%d', 10));
  Assert.AreEqual(TAtlasSignatureEditorPlan.cFormatQuietTicks, mState.Due);
  for mTick := 1 to TAtlasSignatureEditorPlan.cFormatQuietTicks - 1 do
  begin
    Assert.IsFalse(TAtlasSignatureEditorPlan.FormatDue(mState, 'Format(''%d', 10));
  end;
  Assert.IsTrue(TAtlasSignatureEditorPlan.FormatDue(mState, 'Format(''%d', 10));
  // Danach nicht wieder, bis sich etwas ändert.
  Assert.IsFalse(TAtlasSignatureEditorPlan.FormatDue(mState, 'Format(''%d', 10));
  mState.Text := '';
end;

procedure TSignatureEditorPlanTests.ParenRunOnlyOnCaretLine;
begin
  Assert.AreEqual('(a, ', TAtlasSignatureEditorPlan.ParenRun('  Foo(a, ', 9, 5, 9));
  Assert.AreEqual('', TAtlasSignatureEditorPlan.ParenRun('Foo('#13#10'  a, ', 10, 3, 4));
end;

procedure TSignatureEditorPlanTests.ScrollShiftByRows;
begin
  Assert.AreEqual(-32, TAtlasSignatureEditorPlan.ScrollShift(10, 12, 16));
  Assert.AreEqual(16, TAtlasSignatureEditorPlan.ScrollShift(10, 9, 16));
end;

end.
