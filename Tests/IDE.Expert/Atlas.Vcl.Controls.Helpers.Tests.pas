unit Atlas.Vcl.Controls.Helpers.Tests;

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
    /// <summary>BelowLeft liegt unter der linken unteren Ecke; ShownCaption nur für sichtbare Beschriftungen.
    /// </summary>
    [Test]
    procedure BelowLeftAndShownCaption;
    /// <summary>CanFocusNow: ohne Fenster bzw. bei gesperrtem Formular False (CanFocus allein sagt dort True),
    /// gezeigt und freigegeben True.</summary>
    [Test]
    procedure CanFocusNowChecksTheForm;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.Classes,
  System.SysUtils,
  System.Types,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Atlas.Vcl.Controls.Helpers;

const
  cSomeRow = 3;
  cOldHeight = 10;
  cNewHeight = 25;
  cOffScreen = 10000;

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
    Assert.AreSame(mPages, mSheet.PageControl);
    Assert.IsFalse(mSheet.TabVisible);
    Assert.AreEqual('Reiter', mSheet.Caption);
    Assert.AreSame(mForm, mSheet.Owner);
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

procedure TAtlasControlsTests.BelowLeftAndShownCaption;
var
  mForm: TForm;
  mLabel: TLabel;
  mPoint: TPoint;
  mHeight: Integer;
begin
  mForm := TForm.CreateNew(nil);
  try
    mLabel := TLabel.Create(mForm);
    // Ohne das passt AutoSize die Höhe an die Schrift an, sobald die Beschriftung gesetzt ist.
    mLabel.AutoSize := False;
    mHeight := mForm.ScaleValue(cNewHeight);
    mLabel.Height := mHeight;
    mLabel.Parent := mForm;
    mLabel.Caption := 'Status';
    mPoint := TAtlasControls.BelowLeft(mLabel);
    Assert.AreEqual(mLabel.ClientToScreen(TPoint.Create(0, 0)).Y + mHeight, mPoint.Y);
    Assert.AreEqual(mLabel.ClientToScreen(TPoint.Create(0, 0)).X, mPoint.X);
    Assert.AreEqual('Status', TAtlasControls.ShownCaption(mLabel));
    mLabel.Visible := False;
    Assert.AreEqual('', TAtlasControls.ShownCaption(mLabel));
  finally
    mForm.Free;
  end;
end;

procedure TAtlasControlsTests.CanFocusNowChecksTheForm;
var
  mForm: TForm;
  mEdit: TEdit;
begin
  mForm := TForm.CreateNew(nil);
  try
    mForm.Position := poDesigned;
    mForm.SetBounds(-cOffScreen, -cOffScreen, cNewHeight * 10, cNewHeight * 4);
    mEdit := TEdit.Create(mForm);
    mEdit.Parent := mForm;
    Assert.IsFalse(TAtlasControls.CanFocusNow(nil));
    Assert.IsFalse(TAtlasControls.CanFocusNow(mEdit), 'Formular nicht gezeigt');
    mForm.Show;
    Assert.IsTrue(TAtlasControls.CanFocusNow(mEdit), 'gezeigt und freigegeben');
    mForm.Enabled := False;
    Assert.IsTrue(mEdit.CanFocus, 'CanFocus prüft das Formular nicht');
    Assert.IsFalse(TAtlasControls.CanFocusNow(mEdit), 'Formular gesperrt');
    mForm.Enabled := True;
    mForm.Hide;
  finally
    mForm.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasControlsTests);

end.
