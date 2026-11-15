unit Atlas.Core.Hover.Plan.Tests;

// Entscheidungen des Hover-Tooltips (Atlas.Core.Hover.Plan): Wort und Schlüssel unter der Maus, Inhalt,
// Aktionen, Tasten und Zeitgeber.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  THoverPlanTests = class
  public
    [Test]
    procedure WordAtFindsIdentifierBounds;
    [Test]
    procedure WordAtRejectsNumbersAndBlanks;
    [Test]
    procedure KeysDifferForWordAndProblem;
    [Test]
    procedure HasContentNeedsAnything;
    [Test]
    procedure ReassignedOnlyForChosenTargets;
    [Test]
    procedure TypeChainStartsWithDeclaredType;
    [Test]
    procedure VisualizeKeyChangesWithValueAndType;
    [Test]
    procedure ExplainsOnlyFailedWithoutNote;
    [Test]
    procedure SubjectIsSelectedRow;
    [Test]
    procedure SubjectOfPendingRowIsPending;
    [Test]
    procedure SubjectKeepsValueForMoreRowAndOutOfRange;
    [Test]
    procedure ExampleWithoutEntryNamesRule;
    [Test]
    procedure CopyPrefersSelectionThenMembers;
    [Test]
    procedure ProblemActionTags;
    [Test]
    procedure OpensOnlyWebAndMail;
  end;

  [TestFixture]
  THoverKeysTests = class
  public
    [Test]
    procedure NothingWhenHidden;
    [Test]
    procedure EscapeClosesWithoutShift;
    [Test]
    procedure BackOnlyPinnedWithHistory;
    [Test]
    procedure ActionKeysNeedPinOrMouse;
    [Test]
    procedure HelpOnlyWithDocWiki;
    [Test]
    procedure CopySelectionWithoutLocation;
    [Test]
    procedure ProblemActionKeys;
    [Test]
    procedure TreeKeysOnlyWhenExpandable;
    [Test]
    procedure ClosesAfterOtherKeyUnlessPinned;
    [Test]
    procedure TrackSteps;
    [Test]
    procedure HideSteps;
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.DebugValue,
  Atlas.Core.Hover.Plan,
  Atlas.Core.Hover.View,
  Atlas.Core.Problems.Explanation;

function ShownState(APinned: Boolean): TAtlasHoverKeyState;
begin
  Result := Default(TAtlasHoverKeyState);
  Result.Shown := True;
  Result.Pinned := APinned;
end;

function DebugValueWithRow(APending, ALazy, AMore: Boolean): TAtlasDebugValue;
begin
  Result := TAtlasDebugValue.Evaluated('List', '(Count: 2)');
  SetLength(Result.Rows, 1);
  Result.Rows[0].Expression := 'List[0]';
  Result.Rows[0].Text := '42';
  Result.Rows[0].OldText := '41';
  Result.Rows[0].Expandable := True;
  Result.Rows[0].Pending := APending;
  Result.Rows[0].Lazy := ALazy;
  Result.Rows[0].More := AMore;
end;

{ THoverPlanTests }

procedure THoverPlanTests.WordAtFindsIdentifierBounds;
var
  mStart, mStop: Integer;
begin
  // Maus mitten in „Caption“: ganzes Wort, Ende exklusiv.
  Assert.IsTrue(TAtlasHoverPlan.WordAt('  Form1.Caption := X;', 10, mStart, mStop));
  Assert.AreEqual(8, mStart);
  Assert.AreEqual(15, mStop);
end;

procedure THoverPlanTests.WordAtRejectsNumbersAndBlanks;
var
  mStart, mStop: Integer;
begin
  Assert.IsFalse(TAtlasHoverPlan.WordAt('X := 1E5;', 6, mStart, mStop), 'Zahl');
  Assert.IsFalse(TAtlasHoverPlan.WordAt('X := 1;', 1, mStart, mStop), 'Leerzeichen');
  Assert.IsFalse(TAtlasHoverPlan.WordAt('X', 1, mStart, mStop), 'hinter dem Zeilenende');
  Assert.AreEqual(0, mStart);
  Assert.AreEqual(0, mStop);
end;

procedure THoverPlanTests.KeysDifferForWordAndProblem;
begin
  Assert.AreEqual('a.pas|3|7', TAtlasHoverPlan.WordKey('a.pas', 3, 7));
  Assert.AreEqual('a.pas|3|p7', TAtlasHoverPlan.ProblemKey('a.pas', 3, 7));
end;

procedure THoverPlanTests.HasContentNeedsAnything;
begin
  Assert.IsFalse(TAtlasHoverPlan.HasContent(False, 0, False));
  Assert.IsTrue(TAtlasHoverPlan.HasContent(True, 0, False));
  Assert.IsTrue(TAtlasHoverPlan.HasContent(False, 1, False));
  Assert.IsTrue(TAtlasHoverPlan.HasContent(False, 0, True));
end;

procedure THoverPlanTests.ReassignedOnlyForChosenTargets;
begin
  Assert.IsTrue(TAtlasHoverPlan.ShowsReassigned(True, 'locals,varParams', 'locals'));
  Assert.IsFalse(TAtlasHoverPlan.ShowsReassigned(True, 'varParams', 'locals'), 'nicht gewählt');
  Assert.IsFalse(TAtlasHoverPlan.ShowsReassigned(False, 'locals', 'locals'), 'abgeschaltet');
  Assert.IsFalse(TAtlasHoverPlan.ShowsReassigned(True, 'locals', ''), 'ohne Art');
end;

procedure THoverPlanTests.TypeChainStartsWithDeclaredType;
var
  mData: TAtlasHoverData;
  mChain: TArray<string>;
begin
  mData := Default(TAtlasHoverData);
  mData.Declaration := 'var Items: TStringList';
  SetLength(mData.Ancestors, 2);
  mData.Ancestors[0].Name := 'TStrings';
  mData.Ancestors[1].Name := 'TPersistent';
  mChain := TAtlasHoverPlan.TypeChain(mData);
  Assert.AreEqual(3, Integer(Length(mChain)));
  Assert.AreEqual('TStringList', mChain[0]);
  Assert.AreEqual('TStrings', mChain[1]);
  Assert.AreEqual('TPersistent', mChain[2]);
end;

procedure THoverPlanTests.VisualizeKeyChangesWithValueAndType;
var
  mValue: TAtlasDebugValue;
  mKey: string;
begin
  mValue := TAtlasDebugValue.Evaluated('Color', '255');
  mKey := TAtlasHoverPlan.VisualizeKey(mValue, 'var Color: TColor');
  Assert.AreEqual(mKey, TAtlasHoverPlan.VisualizeKey(mValue, 'var Color: TColor'));
  Assert.AreNotEqual(mKey, TAtlasHoverPlan.VisualizeKey(mValue, 'var Color: Integer'));
  mValue.Text := '0';
  Assert.AreNotEqual(mKey, TAtlasHoverPlan.VisualizeKey(mValue, 'var Color: TColor'));
end;

procedure THoverPlanTests.ExplainsOnlyFailedWithoutNote;
var
  mValue: TAtlasDebugValue;
begin
  mValue := TAtlasDebugValue.Failed('X', 'inaccessible');
  Assert.IsTrue(TAtlasHoverPlan.NeedsExplanation(mValue));
  mValue.Note.Caption := '‹kein Zugriff›';
  Assert.IsFalse(TAtlasHoverPlan.NeedsExplanation(mValue), 'schon erklärt');
  Assert.IsFalse(TAtlasHoverPlan.NeedsExplanation(TAtlasDebugValue.Evaluated('X', '1')), 'Wert');
end;

procedure THoverPlanTests.SubjectIsSelectedRow;
var
  mSubject: TAtlasDebugValue;
begin
  mSubject := TAtlasHoverPlan.Subject(DebugValueWithRow(False, False, False), 0);
  Assert.AreEqual('List[0]', mSubject.Expression);
  Assert.AreEqual('42', mSubject.Text);
  Assert.AreEqual('41', mSubject.OldText);
  Assert.IsTrue(mSubject.Expandable);
  Assert.AreEqual(0, Integer(Length(mSubject.Rows)));
  Assert.AreEqual<TAtlasDebugValueState>(TAtlasDebugValueState.Value, mSubject.State);
end;

procedure THoverPlanTests.SubjectOfPendingRowIsPending;
begin
  Assert.AreEqual<TAtlasDebugValueState>(TAtlasDebugValueState.Pending,
    TAtlasHoverPlan.Subject(DebugValueWithRow(True, False, False), 0).State, 'ausstehend');
  Assert.AreEqual<TAtlasDebugValueState>(TAtlasDebugValueState.Pending,
    TAtlasHoverPlan.Subject(DebugValueWithRow(False, True, False), 0).State, 'Getter');
end;

procedure THoverPlanTests.SubjectKeepsValueForMoreRowAndOutOfRange;
begin
  Assert.AreEqual('List', TAtlasHoverPlan.Subject(DebugValueWithRow(False, False, True), 0).Expression, 'weitere');
  Assert.AreEqual('List', TAtlasHoverPlan.Subject(DebugValueWithRow(False, False, False), -1).Expression, 'Wert');
  Assert.AreEqual('List', TAtlasHoverPlan.Subject(DebugValueWithRow(False, False, False), 1).Expression, 'hinter');
end;

procedure THoverPlanTests.ExampleWithoutEntryNamesRule;
var
  mExplanation: TAtlasRuleExplanation;
begin
  mExplanation := Default(TAtlasRuleExplanation);
  Assert.AreEqual('empty-except', TAtlasHoverPlan.ExampleOf('empty-except', mExplanation).Id);
  mExplanation.Id := 'with-statement';
  Assert.AreEqual('with-statement', TAtlasHoverPlan.ExampleOf('empty-except', mExplanation).Id);
end;

procedure THoverPlanTests.CopyPrefersSelectionThenMembers;
begin
  Assert.AreEqual<TAtlasHoverCopySource>(TAtlasHoverCopySource.Selection, TAtlasHoverPlan.CopySource(True, 3));
  Assert.AreEqual<TAtlasHoverCopySource>(TAtlasHoverCopySource.Members, TAtlasHoverPlan.CopySource(False, 3));
  Assert.AreEqual<TAtlasHoverCopySource>(TAtlasHoverCopySource.Declaration, TAtlasHoverPlan.CopySource(False, 0));
end;

procedure THoverPlanTests.ProblemActionTags;
begin
  Assert.AreEqual('uses.remove', TAtlasHoverPlan.ProblemActionTag(TAtlasHoverProblemAction.RemoveUses, 0));
  Assert.AreEqual('rule.fix', TAtlasHoverPlan.ProblemActionTag(TAtlasHoverProblemAction.Fix, 0));
  Assert.AreEqual('related:2', TAtlasHoverPlan.ProblemActionTag(TAtlasHoverProblemAction.Related, 2));
  Assert.AreEqual('test.compare', TAtlasHoverPlan.ProblemActionTag(TAtlasHoverProblemAction.Compare, 0));
  Assert.AreEqual('', TAtlasHoverPlan.ProblemActionTag(TAtlasHoverProblemAction.Example, 0));
end;

procedure THoverPlanTests.OpensOnlyWebAndMail;
begin
  Assert.IsTrue(TAtlasHoverPlan.OpensUrl('https://docwiki.embarcadero.com'));
  Assert.IsTrue(TAtlasHoverPlan.OpensUrl('HTTP://example.org')); // lsp-ignore: security-insecure-http
  Assert.IsTrue(TAtlasHoverPlan.OpensUrl('mailto:a@b.c'));
  Assert.IsFalse(TAtlasHoverPlan.OpensUrl('file:///C:/Windows/notepad.exe'));
  Assert.IsFalse(TAtlasHoverPlan.OpensUrl('C:\Windows\notepad.exe'));
end;

{ THoverKeysTests }

procedure THoverKeysTests.NothingWhenHidden;
begin
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.None,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkEscape, [], Default(TAtlasHoverKeyState)));
end;

procedure THoverKeysTests.EscapeClosesWithoutShift;
begin
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.Close,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkEscape, [], ShownState(False)));
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.None,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkEscape, [ssShift], ShownState(False)));
end;

procedure THoverKeysTests.BackOnlyPinnedWithHistory;
var
  mState: TAtlasHoverKeyState;
begin
  mState := ShownState(True);
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.None,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkBack, [], mState), 'ohne Verlauf');
  mState.CanGoBack := True;
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.Back,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkBack, [], mState));
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.Back,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkLeft, [ssAlt], mState));
  mState.Pinned := False;
  mState.MouseOverTip := True;
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.None,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkBack, [], mState), 'nicht angeheftet');
end;

procedure THoverKeysTests.ActionKeysNeedPinOrMouse;
var
  mState: TAtlasHoverKeyState;
begin
  mState := ShownState(False);
  mState.HasLocation := True;
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.None,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkF12, [], mState), 'Tooltip nicht gemeint');
  mState.MouseOverTip := True;
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.Navigate,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkF12, [], mState));
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.Usages,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkF12, [ssShift], mState));
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.Copy,
    TAtlasHoverKeys.Command(Ord('C'), [ssCtrl], mState));
  mState.HasLocation := False;
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.None,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkF12, [], mState), 'ohne Fundort');
end;

procedure THoverKeysTests.HelpOnlyWithDocWiki;
var
  mState: TAtlasHoverKeyState;
begin
  mState := ShownState(True);
  mState.HasLocation := True;
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.None,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkF1, [], mState));
  mState.HasHelp := True;
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.Help,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkF1, [], mState));
end;

procedure THoverKeysTests.CopySelectionWithoutLocation;
var
  mState: TAtlasHoverKeyState;
begin
  mState := ShownState(True);
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.None,
    TAtlasHoverKeys.Command(Ord('C'), [ssCtrl], mState));
  mState.HasSelection := True;
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.Copy,
    TAtlasHoverKeys.Command(Ord('C'), [ssCtrl], mState));
end;

procedure THoverKeysTests.ProblemActionKeys;
var
  mState: TAtlasHoverKeyState;
begin
  mState := ShownState(True);
  mState.HasFix := True;
  mState.HasProblemActions := True;
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.ApplyFix,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkReturn, [ssAlt], mState));
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.NextAction,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkTab, [], mState));
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.PreviousAction,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkTab, [ssShift], mState));
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.None,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkReturn, [], mState), 'nichts markiert');
  mState.ProblemActionMarked := True;
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.ActivateAction,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkReturn, [], mState));
end;

procedure THoverKeysTests.TreeKeysOnlyWhenExpandable;
var
  mState: TAtlasHoverKeyState;
begin
  mState := ShownState(False);
  mState.MouseOverTip := True;
  mState.CanGoBack := True;
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.None,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkUp, [], mState));
  mState.DebugExpandable := True;
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.DebugUp,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkUp, [], mState));
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.DebugDown,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkDown, [], mState));
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.DebugExpand,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkRight, [], mState));
  // Links ohne Umschalter klappt zu, auch wenn der Verlauf zurück könnte.
  Assert.AreEqual<TAtlasHoverKeyCommand>(TAtlasHoverKeyCommand.DebugCollapse,
    TAtlasHoverKeys.Command(TAtlasHoverKeys.cVkLeft, [], mState));
end;

procedure THoverKeysTests.ClosesAfterOtherKeyUnlessPinned;
begin
  Assert.IsTrue(TAtlasHoverKeys.ClosesAfter(Ord('A'), False, False));
  Assert.IsFalse(TAtlasHoverKeys.ClosesAfter(Ord('A'), True, False), 'genommen');
  Assert.IsFalse(TAtlasHoverKeys.ClosesAfter(Ord('A'), False, True), 'angeheftet');
  Assert.IsFalse(TAtlasHoverKeys.ClosesAfter(TAtlasHoverKeys.cVkControl, False, False), 'Strg allein');
  Assert.IsTrue(TAtlasHoverKeys.IsModifier(TAtlasHoverKeys.cVkMenu));
  Assert.IsFalse(TAtlasHoverKeys.IsModifier(TAtlasHoverKeys.cVkEscape));
end;

procedure THoverKeysTests.TrackSteps;
begin
  Assert.AreEqual<TAtlasHoverTrack>(TAtlasHoverTrack.Leave, TAtlasHoverKeys.Track('', 'a', 'a'));
  Assert.AreEqual<TAtlasHoverTrack>(TAtlasHoverTrack.Stay, TAtlasHoverKeys.Track('a', 'a', 'b'));
  Assert.AreEqual<TAtlasHoverTrack>(TAtlasHoverTrack.Restart, TAtlasHoverKeys.Track('b', 'a', 'a'));
  Assert.AreEqual<TAtlasHoverTrack>(TAtlasHoverTrack.Wait, TAtlasHoverKeys.Track('b', 'a', 'b'));
end;

procedure THoverKeysTests.HideSteps;
begin
  Assert.AreEqual<TAtlasHoverHideStep>(TAtlasHoverHideStep.Close, TAtlasHoverKeys.HideStep(True, False, False, True));
  Assert.AreEqual<TAtlasHoverHideStep>(TAtlasHoverHideStep.KeepPinned,
    TAtlasHoverKeys.HideStep(True, True, False, True));
  Assert.AreEqual<TAtlasHoverHideStep>(TAtlasHoverHideStep.Recheck, TAtlasHoverKeys.HideStep(True, False, True, True));
  Assert.AreEqual<TAtlasHoverHideStep>(TAtlasHoverHideStep.Close, TAtlasHoverKeys.HideStep(True, True, True, False),
    'IDE inaktiv');
  Assert.AreEqual<TAtlasHoverHideStep>(TAtlasHoverHideStep.Close, TAtlasHoverKeys.HideStep(False, True, True, True),
    'schon zu');
end;

initialization
  TDUnitX.RegisterTestFixture(THoverPlanTests);
  TDUnitX.RegisterTestFixture(THoverKeysTests);

end.
