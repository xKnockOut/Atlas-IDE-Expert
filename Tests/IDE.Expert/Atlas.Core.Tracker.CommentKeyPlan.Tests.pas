unit Atlas.Core.Tracker.CommentKeyPlan.Tests;

// Tasten im Kommentarfeld (#1278): Senden auch im einfachen Feld, Liste nur
// mit offenen Vorschlägen, Kürzel nur mit Ergänzung, welches Zeichen nicht ins
// Feld kommt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasCommentKeyPlanTests = class
  public
    [Test]
    procedure CtrlReturnSendsAlways;
    [Test]
    procedure ListKeysOnlyWithList;
    [Test]
    procedure ShortcutsOnlyEnhanced;
    [Test]
    procedure LeavingWordClosesList;
    [Test]
    procedure SwallowsAllButLeaveWord;
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Tracker.CommentKeyPlan;

{ TAtlasCommentKeyPlanTests }

procedure TAtlasCommentKeyPlanTests.CtrlReturnSendsAlways;
begin
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.Send,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyReturn, [ssCtrl], True, True), 'mit Liste');
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.Send,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyReturn, [ssCtrl], False, False), 'einfaches Feld');
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.None,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyReturn, [], False, False), 'Zeilenumbruch');
end;

procedure TAtlasCommentKeyPlanTests.ListKeysOnlyWithList;
begin
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.Up,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyUp, [], True, True));
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.PageDown,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyNext, [], True, True));
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.Accept,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyTab, [], True, True));
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.Accept,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyReturn, [], True, True));
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.None,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyReturn, [ssShift], True, True), 'Umschalt+Enter');
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.CloseList,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyEscape, [], True, True));
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.None,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyUp, [], True, False), 'ohne Liste');
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.Cancel,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyEscape, [], True, False), 'Esc ohne Liste');
end;

procedure TAtlasCommentKeyPlanTests.ShortcutsOnlyEnhanced;
begin
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.Snippets,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeySpace, [ssCtrl], True, False));
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.Bold, TAtlasCommentKeyPlan.Action(Ord('B'), [ssCtrl], True, False));
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.Italic,
    TAtlasCommentKeyPlan.Action(Ord('I'), [ssCtrl], True, True));
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.Code,
    TAtlasCommentKeyPlan.Action(Ord('K'), [ssCtrl, ssShift], True, False));
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.None,
    TAtlasCommentKeyPlan.Action(Ord('K'), [ssCtrl], True, False), 'Strg+K allein');
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.None,
    TAtlasCommentKeyPlan.Action(Ord('B'), [ssCtrl], False, False), 'einfaches Feld');
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.None,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyEscape, [], False, False), 'Esc im einfachen Feld');
end;

procedure TAtlasCommentKeyPlanTests.LeavingWordClosesList;
begin
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.LeaveWord,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyLeft, [], True, True));
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.LeaveWord,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyEnd, [ssShift], True, True));
  Assert.AreEqual<TAtlasCommentKey>(TAtlasCommentKey.None,
    TAtlasCommentKeyPlan.Action(TAtlasCommentKeyPlan.cKeyHome, [], True, False), 'ohne Liste');
end;

procedure TAtlasCommentKeyPlanTests.SwallowsAllButLeaveWord;
begin
  Assert.IsFalse(TAtlasCommentKeyPlan.Swallows(TAtlasCommentKey.None));
  Assert.IsFalse(TAtlasCommentKeyPlan.Swallows(TAtlasCommentKey.LeaveWord));
  Assert.IsTrue(TAtlasCommentKeyPlan.Swallows(TAtlasCommentKey.Italic));
  Assert.IsTrue(TAtlasCommentKeyPlan.Swallows(TAtlasCommentKey.Send));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCommentKeyPlanTests);

end.
