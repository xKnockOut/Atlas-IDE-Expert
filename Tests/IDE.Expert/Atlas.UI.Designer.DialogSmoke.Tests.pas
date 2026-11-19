unit Atlas.UI.Designer.DialogSmoke.Tests;

// Rauchtest der Dialoge von Atlas.IDE.Designer: Jeder Dialog entsteht mit kleinster Eingabe, bekommt Fenster für
// sich und alle Steuerelemente, durchläuft DoShow wie beim Zeigen und wird freigegeben (TAtlasDialogSmoke).
// Dialoge mit eigenen Tests stehen dort; Tools/Check-DialogTests.ps1 prüft, dass jeder Dialog gebaut wird.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Designer.FormPreview;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerDialogSmokeTests = class
  private
    function PreviewData: TAtlasFormPreviewData;
  public
    [Test]
    procedure Anchors;
    [Test]
    procedure Duplicate;
    [Test]
    procedure ExtractFrame;
    [Test]
    procedure FontReplace;
    [Test]
    procedure Fonts;
    [Test]
    procedure FormPreview;
    [Test]
    procedure Names;
    [Test]
    procedure PaintProperties;
    [Test]
    procedure PropertySearch;
    [Test]
    procedure ScalePreview;
    [Test]
    procedure Space;
    [Test]
    procedure Texts;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.Core.Designer.Layout,
  Atlas.Core.Designer.FontsColors,
  Atlas.Core.Designer.PropertyPainter,
  Atlas.Core.Designer.FormTexts,
  Atlas.UI.Designer.AnchorDialog,
  Atlas.UI.Designer.DuplicateDialog,
  Atlas.UI.Designer.ExtractDialog,
  Atlas.UI.Designer.FontsDialog,
  Atlas.UI.Designer.NameDialog,
  Atlas.UI.Designer.PaintDialog,
  Atlas.UI.Designer.PropertyDialog,
  Atlas.UI.Designer.ScalePreview,
  Atlas.UI.Designer.SpaceDialog,
  Atlas.UI.Designer.TextsDialog,
  Atlas.Tests.DialogSmoke;

{ TAtlasDesignerDialogSmokeTests }

function TAtlasDesignerDialogSmokeTests.PreviewData: TAtlasFormPreviewData;
begin
  Result := Default(TAtlasFormPreviewData);
  Result.FormName := 'Form1';
  Result.Nodes := TArray<TAtlasLayoutNode>.Create(TAtlasLayoutNode.Create('Button1', 'TButton', -1,
    TRect.Create(TPoint.Create(8, 8), 75, 25)));
  Result.Design := TSize.Create(320, 240);
end;

procedure TAtlasDesignerDialogSmokeTests.Anchors;
var
  mRow: TAtlasAnchorRow;
  mDialog: TAtlasAnchorDialog;
begin
  mRow := Default(TAtlasAnchorRow);
  mRow.Name := 'Button1';
  mRow.Anchors := '[akRight, akBottom]';
  mRow.Offered := True;
  mDialog := TAtlasAnchorDialog.CreateDialog(nil, TArray<TAtlasAnchorRow>.Create(mRow), nil);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual(1, Integer(Length(mDialog.Checked)));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDesignerDialogSmokeTests.Duplicate;
var
  mOptions: TAtlasDuplicateOptions;
  mDialog: TAtlasDuplicateDialog;
begin
  mOptions := Default(TAtlasDuplicateOptions);
  mOptions.Gap := 8;
  mOptions.Count := 2;
  mDialog := TAtlasDuplicateDialog.CreateDialog(nil, mOptions);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual(2, mDialog.Options.Count);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDesignerDialogSmokeTests.ExtractFrame;
var
  mInput: TAtlasExtractInput;
  mDialog: TAtlasExtractDialog;
begin
  mInput := Default(TAtlasExtractInput);
  mInput.FrameClass := 'TAdresseFrame';
  mInput.FrameUnit := 'AdresseFrame';
  mDialog := TAtlasExtractDialog.CreateDialog(nil, 'Form1', mInput, False, nil);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDesignerDialogSmokeTests.FontReplace;
var
  mDialog: TAtlasFontReplaceDialog;
begin
  mDialog := TAtlasFontReplaceDialog.CreateDialog(nil, 'Schrift ersetzen', True, False,
    TArray<string>.Create('Segoe UI, 9'));
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDesignerDialogSmokeTests.Fonts;
var
  mFont: TAtlasFontRow;
  mColor: TAtlasColorRow;
  mDialog: TAtlasFontsDialog;
begin
  mFont := Default(TAtlasFontRow);
  mFont.Font := TAtlasFontKey.Create('Tahoma', 8, 0, 'clWindowText');
  mFont.Own := TArray<string>.Create('Label1');
  mColor := Default(TAtlasColorRow);
  mColor.Color := 'clRed';
  mColor.Components := TArray<string>.Create('Panel1');
  mDialog := TAtlasFontsDialog.CreateDialog(nil, 'Form1', TArray<TAtlasFontRow>.Create(mFont),
    TArray<TAtlasColorRow>.Create(mColor), nil);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual(1, mDialog.Fonts.Items.Count);
    Assert.AreEqual(1, mDialog.Colors.Items.Count);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDesignerDialogSmokeTests.FormPreview;
var
  mDialog: TAtlasFormPreviewWindow;
begin
  mDialog := TAtlasFormPreviewWindow.CreatePreview(nil, PreviewData, TAtlasColors.Light);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.IsTrue(mDialog.Probe.cx >= TAtlasFormPreviewWindow.cMinProbe);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDesignerDialogSmokeTests.Names;
var
  mRow: TAtlasNameRow;
  mDialog: TAtlasNameDialog;
begin
  mRow := Default(TAtlasNameRow);
  mRow.OldName := 'Button1';
  mRow.ClassName := 'TButton';
  mRow.SourceText := 'Speichern';
  mRow.NewName := 'SaveButton';
  mRow.Checked := True;
  mDialog := TAtlasNameDialog.CreateDialog(nil, 'Form1', TArray<TAtlasNameRow>.Create(mRow), True);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDesignerDialogSmokeTests.PaintProperties;
var
  mHeader, mLeaf: TAtlasPaintRow;
  mDialog: TAtlasPaintDialog;
begin
  mHeader := Default(TAtlasPaintRow);
  mHeader.Kind := TAtlasPaintRowKind.Header;
  mHeader.Parent := -1;
  mLeaf := Default(TAtlasPaintRow);
  mLeaf.Kind := TAtlasPaintRowKind.Leaf;
  mLeaf.Path := 'Font.Size';
  mLeaf.Parent := -1;
  mDialog := TAtlasPaintDialog.CreateDialog(nil, 'Button1', TArray<TAtlasPaintRow>.Create(mHeader, mLeaf),
    TArray<Boolean>.Create(False, True));
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual(2, Integer(Length(mDialog.Checked)));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDesignerDialogSmokeTests.PropertySearch;
var
  mOptions: TAtlasPropertyOptions;
  mDialog: TAtlasPropertyDialog;
begin
  mOptions := Default(TAtlasPropertyOptions);
  mOptions.Query := 'Font.Size > 10';
  mOptions.History := TArray<string>.Create('Visible = False');
  mOptions.HasForm := True;
  mDialog := TAtlasPropertyDialog.CreateDialog(nil, mOptions);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDesignerDialogSmokeTests.ScalePreview;
var
  mData: TAtlasScalePreviewData;
  mDialog: TAtlasScalePreviewWindow;
begin
  mData := Default(TAtlasScalePreviewData);
  mData.Form := PreviewData;
  mData.DesignPpi := 96;
  mData.Scaled := True;
  mData.Levels := TArray<Integer>.Create(100, 150);
  mDialog := TAtlasScalePreviewWindow.CreateScale(nil, mData, TAtlasColors.Light);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDesignerDialogSmokeTests.Space;
var
  mOptions: TAtlasSpaceOptions;
  mDialog: TAtlasSpaceDialog;
begin
  mOptions := Default(TAtlasSpaceOptions);
  mOptions.Amount := 16;
  mDialog := TAtlasSpaceDialog.CreateDialog(nil, True, mOptions);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual(16, mDialog.Options.Amount);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasDesignerDialogSmokeTests.Texts;
var
  mDialog: TAtlasTextsDialog;
begin
  mDialog := TAtlasTextsDialog.CreateDialog(nil, 'Form1', TArray<TAtlasTextEntry>.Create(
    TAtlasTextEntry.Create('Button1', 'TButton', 'Caption', '&Speichern', 'Panel1')), nil, nil);
  try
    Assert.IsTrue(TAtlasDialogSmoke.Realize(mDialog) > 1);
    Assert.AreEqual(1, mDialog.List.Items.Count);
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDesignerDialogSmokeTests);

end.
