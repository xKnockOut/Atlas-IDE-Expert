unit Atlas.UI.Foundation.Controls.Tests;

// Bausteine selbst gebauter Steuerelemente (TAtlasControls): Fenster oder nachholen, Hervorhebung löschen,
// Enter/Esc ohne Signalton, Inhaltshöhe neu rechnen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasControlsTests = class
  public
    /// <summary>Ohne Fenster und ohne Formular darüber: False und nachholen; unter einem Formular: True.</summary>
    [Test]
    procedure WindowOrPendingFollowsParents;
    [Test]
    procedure ClearHotResetsIndex;
    [Test]
    procedure SuppressBeepOnlyForEnterAndEscape;
    /// <summary>Remeasure meldet nur eine echte Änderung.</summary>
    [Test]
    procedure RemeasureReportsOnlyChanges;
  end;

implementation

uses
  Vcl.Forms,
  Vcl.ExtCtrls,
  Atlas.UI.Foundation.Controls;

const
  cSomeRow = 3;
  cOldHeight = 10;
  cNewHeight = 25;

{ TAtlasControlsTests }

procedure TAtlasControlsTests.WindowOrPendingFollowsParents;
var
  mForm: TForm;
  mPanel: TPanel;
  mPending: Boolean;
begin
  mPanel := TPanel.Create(nil);
  try
    mPending := False;
    Assert.IsFalse(TAtlasControls.WindowOrPending(mPanel, mPending));
    Assert.IsTrue(mPending);
    mForm := TForm.Create(nil);
    try
      mPanel.Parent := mForm;
      mPending := False;
      Assert.IsTrue(TAtlasControls.WindowOrPending(mPanel, mPending));
      Assert.IsFalse(mPending);
      mPanel.Parent := nil;
    finally
      mForm.Free;
    end;
  finally
    mPanel.Free;
  end;
end;

procedure TAtlasControlsTests.ClearHotResetsIndex;
var
  mPanel: TPanel;
  mHot: Integer;
begin
  mPanel := TPanel.Create(nil);
  try
    mHot := cSomeRow;
    TAtlasControls.ClearHot(mPanel, mHot);
    Assert.AreEqual(TAtlasControls.cNoHot, mHot);
    TAtlasControls.ClearHot(mPanel, mHot);
    Assert.AreEqual(TAtlasControls.cNoHot, mHot);
  finally
    mPanel.Free;
  end;
end;

procedure TAtlasControlsTests.SuppressBeepOnlyForEnterAndEscape;
var
  mKey: Char;
begin
  mKey := #13;
  TAtlasControls.SuppressBeep(mKey);
  Assert.AreEqual<Char>(#0, mKey);
  mKey := #27;
  TAtlasControls.SuppressBeep(mKey);
  Assert.AreEqual<Char>(#0, mKey);
  mKey := 'a';
  TAtlasControls.SuppressBeep(mKey);
  Assert.AreEqual<Char>('a', mKey);
end;

procedure TAtlasControlsTests.RemeasureReportsOnlyChanges;
var
  mHeight, mCalls: Integer;
begin
  mHeight := cOldHeight;
  mCalls := 0;
  TAtlasControls.Remeasure(mHeight, cOldHeight,
    procedure
    begin
      Inc(mCalls);
    end);
  Assert.AreEqual(0, mCalls);
  TAtlasControls.Remeasure(mHeight, cNewHeight,
    procedure
    begin
      Inc(mCalls);
    end);
  Assert.AreEqual(1, mCalls);
  Assert.AreEqual(cNewHeight, mHeight);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasControlsTests);

end.
