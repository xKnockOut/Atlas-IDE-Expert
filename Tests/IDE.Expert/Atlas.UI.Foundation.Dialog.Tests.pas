unit Atlas.UI.Foundation.Dialog.Tests;

// Basis der Atlas-Dialoge (#2062): Vorgaben von CreateDialog, Abo beim
// Themendienst bis zum Freigeben, Thema beim Zeigen und bei jedem Wechsel,
// Zeilen von oben nach unten, Knopfbreiten nach Text, Vorgabe und Abbrechen,
// Hinweiszeile in der Textfarbe der Palette. TAtlasPopupForm: ohne Rahmen
// in den übergebenen Farben, bei jedem Themenwechsel die Farben des Themas,
// das IDE-Thema an den Steuerelementen nur mit ThemedControls. Ohne Breite
// legt CreateDialog kein Fenster an, CreatePopup nie: Nachfahren sehen in
// CreateWnd und Resize ein fertiges Objekt. Mit PaintsAll löscht das Fenster
// seinen Hintergrund nie (kein Flackern), holt ein Kind ihn aber weiter.
// MainFormWorkArea: ohne Hauptfenster die Arbeitsfläche des Hauptmonitors.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDialogTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CreateDialogSetsDefaults;
    [Test]
    procedure CreateDialogWithoutWidthHasNoWindow;
    [Test]
    procedure SubscribedUntilFreed;
    [Test]
    procedure ThemeChangeAppliesAndNotifies;
    [Test]
    procedure RowsStackFromTop;
    [Test]
    procedure ButtonsFitTextAndRoles;
    [Test]
    procedure NoteUsesPaletteColors;
    [Test]
    procedure ResizeGrowsMiddleRow;
    [Test]
    procedure FitRightStretchesWithRow;
    [Test]
    procedure PopupFormSetsDefaults;
    [Test]
    procedure PopupFormFollowsTheme;
    [Test]
    procedure PopupFormHasNoWindow;
    [Test]
    procedure PopupFormThemesControlsOnRequest;
    [Test]
    procedure PopupFormPaintsAllKeepsBackground;
    [Test]
    procedure WorkAreaWithoutMainForm;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Types,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Signal,
  Atlas.UI.Foundation.Theme,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Zählt ThemeChanged.</summary>
  TProbeDialog = class(TAtlasDialog)
  protected
    procedure ThemeChanged; override;
  public
    ThemeCount: Integer;
  end;

  /// <summary>Zählt ColorsChanged und merkt sich die Fläche dabei.</summary>
  TProbePopup = class(TAtlasPopupForm)
  protected
    procedure ColorsChanged; override;
  public
    ColorsCount: Integer;
    SurfaceSeen: TAtlasColor;
  end;

{ TProbePopup }

procedure TProbePopup.ColorsChanged;
begin
  Inc(ColorsCount);
  SurfaceSeen := Colors.Surface;
end;

{ TProbeDialog }

procedure TProbeDialog.ThemeChanged;
begin
  Inc(ThemeCount);
end;

{ TAtlasDialogTests }

procedure TAtlasDialogTests.TearDown;
begin
  TAtlasUiTheme.Uninstall;
end;

procedure TAtlasDialogTests.CreateDialogSetsDefaults;
var
  mDialog: TAtlasDialog;
begin
  mDialog := TAtlasDialog.CreateDialog(nil, 'Titel', 400);
  try
    Assert.AreEqual('Titel', string(mDialog.Caption));
    Assert.AreEqual<TFormBorderStyle>(bsDialog, mDialog.BorderStyle);
    Assert.AreEqual<TPosition>(poMainFormCenter, mDialog.Position);
    Assert.AreEqual(string(TAtlasUiTheme.cFontName), string(mDialog.Font.Name));
    Assert.AreEqual(mDialog.ScaleValue(400), mDialog.ClientWidth);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDialogTests.CreateDialogWithoutWidthHasNoWindow;
var
  mDialog: TAtlasDialog;
begin
  // Breite 0: Der Dialog setzt sie selbst; ClientWidth würde das Fenster vor dem Konstruktor des Nachfahren anlegen.
  mDialog := TAtlasDialog.CreateDialog(nil, 'Titel', 0);
  try
    Assert.IsFalse(mDialog.HandleAllocated, 'Fenster nach CreateDialog');
    Assert.AreEqual<TFormBorderStyle>(bsDialog, mDialog.BorderStyle);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDialogTests.SubscribedUntilFreed;
var
  mDialog: TAtlasDialog;
begin
  mDialog := TAtlasDialog.CreateDialog(nil, 'Titel', 300);
  try
    Assert.IsTrue(TAtlasUiTheme.Subscribed(mDialog));
  finally
    mDialog.Free;
  end;
  Assert.IsFalse(TAtlasUiTheme.Subscribed(mDialog));
end;

procedure TAtlasDialogTests.ThemeChangeAppliesAndNotifies;
var
  mDialog: TProbeDialog;
  mApplied: Integer;
begin
  mApplied := 0;
  TAtlasUiTheme.Install(nil,
    procedure(AControl: TWinControl)
    begin
      Inc(mApplied);
    end, nil);
  mDialog := TProbeDialog.CreateDialog(nil, 'Titel', 300);
  try
    TAtlasUiTheme.Changed;
    Assert.AreEqual(1, mApplied);
    Assert.AreEqual(1, mDialog.ThemeCount);
  finally
    mDialog.Free;
  end;
  // Freigegeben: kein Rückruf mehr.
  TAtlasUiTheme.Changed;
  Assert.AreEqual(1, mApplied);
end;

procedure TAtlasDialogTests.RowsStackFromTop;
var
  mDialog: TAtlasDialog;
  mFirst, mSecond: TPanel;
  mLabel: TLabel;
begin
  mDialog := TAtlasDialog.CreateDialog(nil, 'Titel', 300);
  try
    mFirst := mDialog.AddRow(22);
    mLabel := mDialog.AddLabel(mFirst, 'Dauer');
    mSecond := mDialog.AddRow(26);
    // Ohne Fenster ordnet die VCL alTop-Zeilen nicht an.
    mDialog.HandleNeeded;
    Assert.AreEqual(mDialog.ScaleValue(22), mFirst.Height);
    Assert.IsTrue(mSecond.Top > mFirst.Top, Format('Top %d/%d', [mFirst.Top, mSecond.Top]));
    Assert.AreSame(mFirst, mLabel.Parent, 'Parent');
    mDialog.FitHeight;
    Assert.IsTrue(mDialog.ClientHeight >= mSecond.Top + mSecond.Height,
      Format('ClientHeight %d, Ende %d', [mDialog.ClientHeight, mSecond.Top + mSecond.Height]));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDialogTests.ButtonsFitTextAndRoles;
var
  mDialog: TAtlasDialog;
  mRow: TAtlasButtonRow;
  mShort, mLong, mCancel: TButton;
begin
  mDialog := TAtlasDialog.CreateDialog(nil, 'Titel', 400);
  try
    mRow := mDialog.AddButtonRow;
    mShort := mRow.AddButton('OK', TAtlasButtonKind.Default);
    mLong := mRow.AddButton('Später erinnern und Fenster schließen');
    mCancel := mRow.AddButton('Abbrechen', TAtlasButtonKind.Cancel);
    Assert.AreEqual(mRow.ScaleValue(TAtlasButtonRow.cButtonMinWidth), mShort.Width);
    Assert.IsTrue(mLong.Width > mShort.Width);
    Assert.IsTrue(mShort.Default);
    Assert.IsTrue(mCancel.Cancel);
    Assert.AreEqual(Integer(mrCancel), Integer(mCancel.ModalResult));
    Assert.IsFalse(mLong.Default or mLong.Cancel);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDialogTests.NoteUsesPaletteColors;
var
  mDialog: TAtlasDialog;
  mNote: TAtlasNoteLabel;
begin
  TAtlasUiTheme.Install(
    function: TAtlasColors
    begin
      Result := TAtlasColors.Dark;
    end, nil, nil);
  mDialog := TAtlasDialog.CreateDialog(nil, 'Titel', 300);
  try
    mNote := mDialog.AddNote(34);
    Assert.AreEqual('', string(mNote.Caption));
    mNote.ShowNote('Falsche Dauer', TAtlasSignalKind.Error);
    Assert.AreEqual('Falsche Dauer', string(mNote.Caption));
    Assert.AreEqual(Integer(TColor(TAtlasColors.Dark.Error)), Integer(mNote.Font.Color));
    // Mit seFont übergeht der Stil Font.Color; farbige Meldungen zeichnen ihre Schrift selbst.
    Assert.IsFalse(seFont in mNote.StyleElements);
    mNote.ShowNote('Nur lokal gespeichert', TAtlasSignalKind.Info);
    Assert.IsTrue(seFont in mNote.StyleElements);
    Assert.AreEqual(Integer(clWindowText), Integer(mNote.Font.Color));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDialogTests.ResizeGrowsMiddleRow;
var
  mDialog: TAtlasDialog;
  mTop, mGrow, mBottom: TPanel;
  mMinHeight: Integer;
begin
  mDialog := TAtlasDialog.CreateDialog(nil, 'Titel', 300);
  try
    mTop := mDialog.AddRow(22);
    mGrow := mDialog.AddRow(60);
    mBottom := mDialog.AddRow(26);
    mDialog.HandleNeeded;
    mDialog.FitHeight;
    mDialog.AllowResize(mGrow);
    Assert.AreEqual<TFormBorderStyle>(bsSizeable, mDialog.BorderStyle);
    Assert.AreEqual(mDialog.Width, Integer(mDialog.Constraints.MinWidth));
    mMinHeight := mDialog.Constraints.MinHeight;
    Assert.AreEqual(mDialog.Height, mMinHeight);
    Assert.AreEqual<TAlign>(alTop, mTop.Align);
    Assert.AreEqual<TAlign>(alClient, mGrow.Align);
    Assert.AreEqual<TAlign>(alBottom, mBottom.Align);
    mDialog.Height := mMinHeight + mDialog.ScaleValue(100);
    Assert.AreEqual(mDialog.ScaleValue(26), mBottom.Height, 'untere Zeile behält ihre Höhe');
    Assert.IsTrue(mGrow.Height >= mDialog.ScaleValue(60 + 100) - 2, Format('Höhe %d', [mGrow.Height]));
    Assert.IsTrue(mBottom.Top > mGrow.Top, 'Reihenfolge bleibt');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDialogTests.FitRightStretchesWithRow;
var
  mDialog: TAtlasDialog;
  mRow: TPanel;
  mEdit: TEdit;
  mWidth: Integer;
begin
  mDialog := TAtlasDialog.CreateDialog(nil, 'Titel', 300);
  try
    mRow := mDialog.AddRow(26);
    mEdit := TEdit.Create(mDialog);
    mEdit.Parent := mRow;
    mEdit.Left := mDialog.ScaleValue(100);
    mDialog.HandleNeeded;
    mDialog.FitHeight;
    mDialog.FitRight(mEdit);
    Assert.AreEqual(mRow.ClientWidth - mDialog.ScaleValue(TAtlasDialog.cRowGap), mEdit.Left + mEdit.Width);
    mDialog.AllowResize(nil);
    mWidth := mEdit.Width;
    mDialog.Width := mDialog.Width + mDialog.ScaleValue(50);
    Assert.AreEqual(mWidth + mDialog.ScaleValue(50), mEdit.Width);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDialogTests.PopupFormSetsDefaults;
var
  mPopup: TAtlasPopupForm;
begin
  mPopup := TAtlasPopupForm.CreatePopup(nil, TAtlasColors.Dark);
  try
    Assert.AreEqual<TFormBorderStyle>(bsNone, mPopup.BorderStyle);
    Assert.AreEqual<TPosition>(poDesigned, mPopup.Position);
    Assert.AreEqual(string(TAtlasUiTheme.cFontName), string(mPopup.Font.Name));
    Assert.AreEqual(Integer(TColor(TAtlasColors.Dark.Surface)), Integer(mPopup.Color));
    Assert.AreEqual(Cardinal(TAtlasColors.Dark.Surface), Cardinal(mPopup.Colors.Surface));
    Assert.IsTrue(TAtlasUiTheme.Subscribed(mPopup));
  finally
    mPopup.Free;
  end;
  Assert.IsFalse(TAtlasUiTheme.Subscribed(mPopup));
end;

procedure TAtlasDialogTests.PopupFormFollowsTheme;
var
  mPopup: TProbePopup;
begin
  TAtlasUiTheme.Install(
    function: TAtlasColors
    begin
      Result := TAtlasColors.Dark;
    end, nil, nil);
  mPopup := TProbePopup.CreatePopup(nil, TAtlasColors.Light);
  try
    Assert.AreEqual(0, mPopup.ColorsCount);
    TAtlasUiTheme.Changed;
    Assert.AreEqual(1, mPopup.ColorsCount);
    Assert.AreEqual(Cardinal(TAtlasColors.Dark.Surface), Cardinal(mPopup.SurfaceSeen), 'Farben vor ColorsChanged');
    Assert.AreEqual(Integer(TColor(TAtlasColors.Dark.Surface)), Integer(mPopup.Color));
  finally
    mPopup.Free;
  end;
end;

procedure TAtlasDialogTests.PopupFormHasNoWindow;
var
  mPopup: TAtlasPopupForm;
begin
  mPopup := TAtlasPopupForm.CreatePopup(nil, TAtlasColors.Light);
  try
    Assert.IsFalse(mPopup.HandleAllocated, 'Fenster nach CreatePopup');
    Assert.AreEqual<TFormBorderStyle>(bsNone, mPopup.BorderStyle);
  finally
    mPopup.Free;
  end;
end;

procedure TAtlasDialogTests.PopupFormThemesControlsOnRequest;
var
  mPopup: TProbePopup;
  mApplied: Integer;
begin
  mApplied := 0;
  TAtlasUiTheme.Install(nil,
    procedure(AControl: TWinControl)
    begin
      Inc(mApplied);
    end, nil);
  mPopup := TProbePopup.CreatePopup(nil, TAtlasColors.Light);
  try
    // Ohne ThemedControls zeichnet das Fenster alles selbst: kein VCL-Stil.
    TAtlasUiTheme.Changed;
    Assert.AreEqual(0, mApplied, 'ohne ThemedControls');
    Assert.AreEqual(1, mPopup.ColorsCount);
    mPopup.ThemedControls := True;
    TAtlasUiTheme.Changed;
    Assert.AreEqual(1, mApplied, 'mit ThemedControls');
    Assert.AreEqual(2, mPopup.ColorsCount);
  finally
    mPopup.Free;
  end;
end;

function EraseProbe(APopup: TAtlasPopupForm; AFromChild: Boolean): TColor;
var
  mBitmap: TBitmap;
  mDC: HDC;
  mFrom: LPARAM;
begin
  // Rot vorbelegen und löschen lassen: Rot bleibt nur, wenn das Fenster nichts füllt.
  mBitmap := TBitmap.Create;
  try
    mBitmap.PixelFormat := pf24bit;
    mBitmap.SetSize(4, 4);
    mBitmap.Canvas.Brush.Color := clRed;
    mBitmap.Canvas.FillRect(Rect(0, 0, 4, 4));
    mDC := mBitmap.Canvas.Handle;
    mFrom := 0;
    if AFromChild then
    begin
      mFrom := LPARAM(mDC);
    end;
    APopup.Perform(WM_ERASEBKGND, WPARAM(mDC), mFrom);
    Result := mBitmap.Canvas.Pixels[0, 0];
  finally
    mBitmap.Free;
  end;
end;

procedure TAtlasDialogTests.PopupFormPaintsAllKeepsBackground;
var
  mPopup: TAtlasPopupForm;
begin
  mPopup := TAtlasPopupForm.CreatePopup(nil, TAtlasColors.Dark);
  try
    // Ohne Doppelpuffer füllt die VCL beim Löschen wie der Stil der IDE.
    mPopup.DoubleBuffered := False;
    mPopup.SetBounds(0, 0, 40, 40);
    mPopup.HandleNeeded;
    Assert.IsFalse(mPopup.PaintsAll, 'Vorgabe');
    Assert.IsFalse(csOpaque in mPopup.ControlStyle, 'Vorgabe csOpaque');
    Assert.AreNotEqual(Integer(clRed), Integer(EraseProbe(mPopup, False)), 'ohne PaintsAll gelöscht');
    mPopup.PaintsAll := True;
    Assert.IsTrue(csOpaque in mPopup.ControlStyle, 'Invalidate ohne Löschen');
    Assert.AreEqual(Integer(clRed), Integer(EraseProbe(mPopup, False)), 'mit PaintsAll nie gelöscht');
    Assert.AreNotEqual(Integer(clRed), Integer(EraseProbe(mPopup, True)), 'Hintergrund für ein Kind');
    mPopup.PaintsAll := False;
    Assert.IsFalse(csOpaque in mPopup.ControlStyle, 'wieder aus');
  finally
    mPopup.Free;
  end;
end;

procedure TAtlasDialogTests.WorkAreaWithoutMainForm;
var
  mArea, mScreen: TRect;
begin
  // Der Testlauf hat kein Hauptfenster: Dann begrenzt der Hauptmonitor die Dialoge.
  Assert.IsNull(Application.MainForm, 'Testlauf ohne Hauptfenster');
  mArea := TAtlasDialog.MainFormWorkArea;
  mScreen := Screen.WorkAreaRect;
  Assert.AreEqual(mScreen.Left, mArea.Left);
  Assert.AreEqual(mScreen.Top, mArea.Top);
  Assert.AreEqual(mScreen.Right, mArea.Right);
  Assert.AreEqual(mScreen.Bottom, mArea.Bottom);
  Assert.IsTrue(mArea.Width > 0, 'Breite');
  Assert.IsTrue(mArea.Height > 0, 'Höhe');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDialogTests);

end.
