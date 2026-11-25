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
  Assert.AreEqual<TAtlasGhostKey>(TAtlasGhostKey.AcceptAll, TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyTab, []));
  Assert.AreEqual<TAtlasGhostKey>(TAtlasGhostKey.None,
    TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyTab, [ssShift]), 'Umschalt+Tab');
end;

procedure TAtlasGhostKeysTests.CtrlRightAcceptsWord;
begin
  Assert.AreEqual<TAtlasGhostKey>(TAtlasGhostKey.AcceptWord,
    TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyRight, [ssCtrl]));
  Assert.AreEqual<TAtlasGhostKey>(TAtlasGhostKey.None,
    TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyRight, []), '→ allein');
  Assert.AreEqual<TAtlasGhostKey>(TAtlasGhostKey.None,
    TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyRight, [ssCtrl, ssShift]));
end;

procedure TAtlasGhostKeysTests.EscapeRejects;
begin
  Assert.AreEqual<TAtlasGhostKey>(TAtlasGhostKey.Reject, TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyEscape, []));
  Assert.AreEqual<TAtlasGhostKey>(TAtlasGhostKey.None, TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyEscape, [ssAlt]));
end;

procedure TAtlasGhostKeysTests.OtherKeysGoToTheEditor;
begin
  Assert.AreEqual<TAtlasGhostKey>(TAtlasGhostKey.None, TAtlasGhostKeys.KeyOf(Ord('A'), []));
  Assert.AreEqual<TAtlasGhostKey>(TAtlasGhostKey.None, TAtlasGhostKeys.KeyOf(TAtlasGhostKeys.cKeyTab, [ssCtrl]));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasGhostKeysTests);

end.
