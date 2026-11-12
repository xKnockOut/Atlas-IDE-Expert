unit Atlas.UI.Foundation.Dialog.Tests;

// Basis der Atlas-Dialoge (#2062): Vorgaben von CreateDialog, Abo beim
// Themendienst bis zum Freigeben, Thema beim Zeigen und bei jedem Wechsel,
// Zeilen von oben nach unten, Knopfbreiten nach Text, Vorgabe und Abbrechen,
// Hinweiszeile in der Textfarbe der Palette.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDialogTests = class
  public
    [SetupFixture]
    procedure WarmUpFirstUse;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CreateDialogSetsDefaults;
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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Forms,
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

procedure TProbeDialog.ThemeChanged;
begin
  Inc(ThemeCount);
end;

procedure TAtlasDialogTests.WarmUpFirstUse;
var
  mDialog: TAtlasDialog;
begin
  // Erste Benutzung (VCL-Formular, Liste der Abonnenten des Themendienstes) nicht dem ersten Test anrechnen.
  mDialog := TAtlasDialog.CreateDialog(nil, 'Aufwärmen', 300);
  try
    mDialog.HandleNeeded;
  finally
    mDialog.Free;
  end;
end;

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
    Assert.IsTrue(mDialog.BorderStyle = bsDialog);
    Assert.IsTrue(mDialog.Position = poMainFormCenter);
    Assert.AreEqual(string(TAtlasUiTheme.cFontName), string(mDialog.Font.Name));
    Assert.AreEqual(mDialog.ScaleValue(400), mDialog.ClientWidth);
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
    Assert.IsTrue(mLabel.Parent = mFirst, 'Parent');
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
    Assert.IsTrue(mDialog.BorderStyle = bsSizeable);
    Assert.AreEqual(mDialog.Width, Integer(mDialog.Constraints.MinWidth));
    mMinHeight := mDialog.Constraints.MinHeight;
    Assert.AreEqual(mDialog.Height, mMinHeight);
    Assert.IsTrue(mTop.Align = alTop);
    Assert.IsTrue(mGrow.Align = alClient);
    Assert.IsTrue(mBottom.Align = alBottom);
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasDialogTests);

end.
