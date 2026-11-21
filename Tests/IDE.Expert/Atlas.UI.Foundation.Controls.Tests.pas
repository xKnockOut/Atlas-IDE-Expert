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
    /// <summary>NewHiddenSheet hängt die Seite ohne Fenster und ohne sichtbaren Reiter ein.</summary>
    [Test]
    procedure NewHiddenSheetJoinsPagesWithoutTab;
    /// <summary>KeyHandled gibt die Taste weiter und setzt Result nur, wenn sie behandelt wurde.</summary>
    [Test]
    procedure KeyHandledMarksOnlyHandledKeys;
    /// <summary>ReturnKey nimmt nur Enter und setzt die Taste dann auf 0.</summary>
    [Test]
    procedure ReturnKeyTakesOnlyEnter;
    /// <summary>OpenOrCopyKey: Enter öffnet, Strg+C kopiert, C allein bleibt.</summary>
    [Test]
    procedure OpenOrCopyKeyTakesEnterAndCtrlC;
    /// <summary>SelectedIndex liest Data des gewählten Knotens; ohne Auswahl -1.</summary>
    [Test]
    procedure SelectedIndexReadsNodeData;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.Classes,
  System.SysUtils,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
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

procedure TAtlasControlsTests.NewHiddenSheetJoinsPagesWithoutTab;
var
  mForm: TForm;
  mPages: TPageControl;
  mSheet: TTabSheet;
begin
  mForm := TForm.CreateNew(nil);
  try
    mPages := TPageControl.Create(mForm);
    mSheet := TAtlasControls.NewHiddenSheet(mForm, mPages, 'Reiter');
    Assert.IsTrue(mSheet.PageControl = mPages);
    Assert.IsFalse(mSheet.TabVisible);
    Assert.AreEqual('Reiter', mSheet.Caption);
    Assert.IsTrue(mSheet.Owner = mForm);
  finally
    mForm.Free;
  end;
end;

procedure TAtlasControlsTests.KeyHandledMarksOnlyHandledKeys;
var
  mMessage: TWMKeyDown;
  mSeen: Word;
begin
  mMessage := Default(TWMKeyDown);
  mMessage.CharCode := Ord('B');
  mSeen := 0;
  Assert.IsFalse(TAtlasControls.KeyHandled(mMessage,
    function(AKey: Word; AShift: TShiftState): Boolean
    begin
      mSeen := AKey;
      Result := False;
    end));
  Assert.AreEqual(Ord('B'), Integer(mSeen));
  Assert.AreEqual(0, Integer(mMessage.Result));
  Assert.IsTrue(TAtlasControls.KeyHandled(mMessage,
    function(AKey: Word; AShift: TShiftState): Boolean
    begin
      Result := True;
    end));
  Assert.AreEqual(1, Integer(mMessage.Result));
end;

procedure TAtlasControlsTests.ReturnKeyTakesOnlyEnter;
var
  mKey: Word;
  mOpened: Integer;
  mOpen: TProc;
begin
  mOpened := 0;
  mOpen :=
    procedure
    begin
      Inc(mOpened);
    end;
  mKey := VK_RETURN;
  Assert.IsTrue(TAtlasControls.ReturnKey(mKey, mOpen));
  Assert.AreEqual(0, Integer(mKey));
  Assert.AreEqual(1, mOpened);
  mKey := VK_ESCAPE;
  Assert.IsFalse(TAtlasControls.ReturnKey(mKey, mOpen));
  Assert.AreEqual(Integer(VK_ESCAPE), Integer(mKey));
  Assert.AreEqual(1, mOpened);
  mOpen := nil;
end;

procedure TAtlasControlsTests.OpenOrCopyKeyTakesEnterAndCtrlC;
var
  mKey: Word;
  mLog: string;
  mOpen, mCopy: TProc;
begin
  mLog := '';
  mOpen :=
    procedure
    begin
      mLog := mLog + 'o';
    end;
  mCopy :=
    procedure
    begin
      mLog := mLog + 'c';
    end;
  mKey := VK_RETURN;
  Assert.IsTrue(TAtlasControls.OpenOrCopyKey(mKey, [], mOpen, mCopy));
  mKey := Ord('C');
  Assert.IsTrue(TAtlasControls.OpenOrCopyKey(mKey, [ssCtrl], mOpen, mCopy));
  Assert.AreEqual(0, Integer(mKey));
  mKey := Ord('C');
  Assert.IsFalse(TAtlasControls.OpenOrCopyKey(mKey, [], mOpen, mCopy));
  Assert.AreEqual(Ord('C'), Integer(mKey));
  Assert.AreEqual('oc', mLog);
  mOpen := nil;
  mCopy := nil;
  mLog := '';
end;

procedure TAtlasControlsTests.SelectedIndexReadsNodeData;
var
  mForm: TForm;
  mTree: TTreeView;
  mNode: TTreeNode;
begin
  mForm := TForm.CreateNew(nil);
  try
    mTree := TTreeView.Create(mForm);
    mTree.Parent := mForm;
    Assert.AreEqual(-1, TAtlasControls.SelectedIndex(mTree));
    mNode := mTree.Items.Add(nil, 'Zeile');
    mNode.Data := Pointer(cSomeRow);
    mNode.Selected := True;
    Assert.AreEqual(cSomeRow, TAtlasControls.SelectedIndex(mTree));
  finally
    mForm.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasControlsTests);

end.
