unit Atlas.Core.Editor.GhostKeys.Tests;

// Tasten beim Schattenvorschlag (#1890): Tab, Strg+→, Esc; alles andere geht an den Editor.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasGhostKeysTests = class
  public
    [Test]
    procedure TabAcceptsAll;
    [Test]
    procedure CtrlRightAcceptsWord;
    [Test]
    procedure EscapeRejects;
    [Test]
    procedure OtherKeysGoToTheEditor;
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Editor.GhostKeys;

{ TAtlasGhostKeysTests }

procedure TAtlasGhostKeysTests.TabAcceptsAll;
begin
  Assert.IsTrue(TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyTab, []) = TAtlasGhostKey.AcceptAll);
  Assert.IsTrue(TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyTab, [ssShift]) = TAtlasGhostKey.None, 'Umschalt+Tab');
end;

procedure TAtlasGhostKeysTests.CtrlRightAcceptsWord;
begin
  Assert.IsTrue(TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyRight, [ssCtrl]) = TAtlasGhostKey.AcceptWord);
  Assert.IsTrue(TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyRight, []) = TAtlasGhostKey.None, '→ allein');
  Assert.IsTrue(TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyRight, [ssCtrl, ssShift]) = TAtlasGhostKey.None);
end;

procedure TAtlasGhostKeysTests.EscapeRejects;
begin
  Assert.IsTrue(TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyEscape, []) = TAtlasGhostKey.Reject);
  Assert.IsTrue(TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyEscape, [ssAlt]) = TAtlasGhostKey.None);
end;

procedure TAtlasGhostKeysTests.OtherKeysGoToTheEditor;
begin
  Assert.IsTrue(TAtlasGhostKeys.KeyOf(Ord('A'), []) = TAtlasGhostKey.None);
  Assert.IsTrue(TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyTab, [ssCtrl]) = TAtlasGhostKey.None);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGhostKeysTests);

end.
