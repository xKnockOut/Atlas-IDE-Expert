unit Atlas.UI.Designer.FontsDialog;

// Dialoge „Schriften und Farben“ (#741), reine VCL.
// Übersicht mit zwei Seiten:
//   Schriften (3) | Farben (2)
//   Schrift            Selbst gesetzt  Geerbt  Hinweis
//   Segoe UI 9         1               2       Schrift des Formulars
//   Tahoma 8           14              0
//   MS Sans Serif 8    1               0       Ausreißer   (fett)
//                                              [Ersetzen …] [Schließen]
// Ein Klick auf eine Zeile meldet die Komponenten (Auswahl im Designer),
// „Ersetzen …“ schließt mit der Zeile. Ersetzen-Dialog: Ziel aus den anderen
// Einträgen oder „Andere …“ (Schrift- bzw. Farbwahl), Häkchen für Name,
// Größe, Stil und Farbe, „Nur markierte Komponenten“.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Designer.FontsColors,
  Atlas.UI.Designer.Dialog;

type
  TAtlasFontsAction = (Close, ReplaceFont, ReplaceColor);

  TAtlasFontsDialog = class(TAtlasDesignerDialog)
  public const
    cDialogWidth = 560;
    cListHeight = 300;
  private
    FFontRows: TArray<TAtlasFontRow>;
    FColorRows: TArray<TAtlasColorRow>;
    FPages: TPageControl;
    FFonts: TListView;
    FColors: TListView;
    FOnSelect: TProc<TArray<string>>;
    FAction: TAtlasFontsAction;
    function AddList(const ACaption: string; const AColumns: array of string): TListView;
    procedure AddButtons;
    procedure Fill;
    procedure ListClick(Sender: TObject);
    procedure ListDrawItem(Sender: TCustomListView; AItem: TListItem; AState: TCustomDrawState;
      var ADefaultDraw: Boolean);
    procedure ColorDrawSubItem(Sender: TCustomListView; AItem: TListItem; ASubItem: Integer;
      AState: TCustomDrawState; var ADefaultDraw: Boolean);
    procedure ReplaceClick(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent; const AForm: string; const AFontRows: TArray<TAtlasFontRow>;
      const AColorRows: TArray<TAtlasColorRow>; const AOnSelect: TProc<TArray<string>>);
    /// <summary>Namen der Stile in Bitreihenfolge (fett, kursiv, unterstrichen, durchgestrichen).</summary>
    class function StyleNames: TArray<string>; static;
    /// <summary>Schrift als Schlüssel: Name, Größe, Stil als Bitmaske, Farbe als Text.</summary>
    class function KeyOf(AFont: TFont): TAtlasFontKey; static;
    /// <summary>Modal zeigen; ATab: Seite beim Öffnen und danach, ARow: Zeile für „Ersetzen“.</summary>
    class function Execute(const AForm: string; const AFontRows: TArray<TAtlasFontRow>;
      const AColorRows: TArray<TAtlasColorRow>; const AOnSelect: TProc<TArray<string>>; var ATab: Integer;
      out ARow: Integer): TAtlasFontsAction; static;
    property Fonts: TListView read FFonts;
    property Colors: TListView read FColors;
  end;

  TAtlasFontReplace = record
    Font: TAtlasFontKey;
    Color: string;
    Parts: TAtlasFontParts;
    OnlySelected: Boolean;
  end;

  TAtlasFontReplaceDialog = class(TAtlasDesignerDialog)
  private
    FIsFont: Boolean;
    FFontTargets: TArray<TAtlasFontKey>;
    FColorTargets: TArray<string>;
    FTarget: TComboBox;
    FParts: array [TAtlasFontPart] of TCheckBox;
    FOnlySelected: TCheckBox;
    procedure AddTarget(const ATargets: TArray<string>);
    procedure AddOptions(AHasSelection: Boolean);
    procedure AddButtons;
    procedure OtherClick(Sender: TObject);
    function Choice: TAtlasFontReplace;
  public
    constructor CreateDialog(AOwner: TComponent; const ATitle: string; AIsFont, AHasSelection: Boolean;
      const ATargets: TArray<string>);
    class function ExecuteFont(const AFrom: TAtlasFontKey; const ATargets: TArray<TAtlasFontKey>;
      AHasSelection: Boolean; out AReplace: TAtlasFontReplace): Boolean; static;
    class function ExecuteColor(const AFrom: string; const ATargets: TArray<string>; AHasSelection: Boolean;
      out AReplace: TAtlasFontReplace): Boolean; static;
  end;

implementation

uses
  System.Types,
  System.UITypes,
  Vcl.Dialogs,
  Atlas.UI.Designer.Strings;

const
  cColumnWidth = 110;
  cWideColumn = 180;
  cComboWidth = 260;
  /// <summary>Spalte der Farbe in der Liste der Farben; das Muster steht in der Spalte davor.</summary>
  cColorColumn = 1;
  /// <summary>Abstand des Farbmusters zum Rand der Zelle.</summary>
  cSwatchInsetX = 4;
  cSwatchInsetY = 3;
  /// <summary>Abstand zwischen Beschriftung und Auswahlliste darunter.</summary>
  cLabelGap = 4;
  /// <summary>Teile einer Schrift (Name, Größe, Stil, Farbe), je eine Spalte.</summary>
  cPartCount = Ord(High(TAtlasFontPart)) + 1;

function UiText(AId: TAtlasDesignerTextId): string;
begin
  Result := TAtlasDesignerStrings.Text(AId);
end;

class function TAtlasFontsDialog.KeyOf(AFont: TFont): TAtlasFontKey;
var
  mStyle: Integer;
  mFontStyle: TFontStyle;
begin
  // Ein Bit je Stil in der Reihenfolge von TFontStyle (fett, kursiv, unterstrichen, durchgestrichen).
  mStyle := 0;
  for mFontStyle in AFont.Style do
  begin
    mStyle := mStyle or (1 shl Ord(mFontStyle));
  end;
  Result := TAtlasFontKey.Create(AFont.Name, AFont.Size, mStyle, ColorToString(AFont.Color));
end;

function FontLine(const AFont: TAtlasFontKey): string;
begin
  Result := TAtlasFontsColors.FontText(AFont, TAtlasFontsDialog.StyleNames);
  if not SameText(AFont.Color, 'clWindowText') then
  begin
    Result := Result + ', ' + AFont.Color;
  end;
end;

{ TAtlasFontsDialog }

class function TAtlasFontsDialog.StyleNames: TArray<string>;
begin
  Result := UiText(TAtlasDesignerTextId.DesignerFontsStyles).Split([',']);
end;

constructor TAtlasFontsDialog.CreateDialog(AOwner: TComponent; const AForm: string;
  const AFontRows: TArray<TAtlasFontRow>; const AColorRows: TArray<TAtlasColorRow>;
  const AOnSelect: TProc<TArray<string>>);
begin
  inherited CreateNew(AOwner);
  FFontRows := AFontRows;
  FColorRows := AColorRows;
  FOnSelect := AOnSelect;
  InitDialog(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerFontsTitle, [AForm]), cDialogWidth, bsSizeToolWin);
  ClientHeight := ScaleValue(cListHeight);
  AddButtons;
  FPages := TPageControl.Create(Self);
  FPages.Parent := Self;
  FPages.Align := alClient;
  FPages.AlignWithMargins := True;
  FPages.Margins.SetBounds(cGap, cGap, cGap, 0);
  FFonts := AddList(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerFontsFontsTab, [Length(AFontRows)]),
    [UiText(TAtlasDesignerTextId.DesignerFontsFont), UiText(TAtlasDesignerTextId.DesignerFontsOwn),
    UiText(TAtlasDesignerTextId.DesignerFontsInherit), UiText(TAtlasDesignerTextId.DesignerFontsNote)]);
  FColors := AddList(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerFontsColorsTab, [Length(AColorRows)]),
    [UiText(TAtlasDesignerTextId.DesignerFontsSample), UiText(TAtlasDesignerTextId.DesignerFontsColor),
    UiText(TAtlasDesignerTextId.DesignerFontsCount), UiText(TAtlasDesignerTextId.DesignerFontsNote)]);
  FColors.OnCustomDrawSubItem := ColorDrawSubItem;
  Fill;
end;

function TAtlasFontsDialog.AddList(const ACaption: string; const AColumns: array of string): TListView;
var
  mSheet: TTabSheet;
  mIndex: Integer;
  mColumn: TListColumn;
begin
  mSheet := TTabSheet.Create(Self);
  mSheet.PageControl := FPages;
  mSheet.Caption := ACaption;
  Result := TListView.Create(Self);
  Result.Parent := mSheet;
  Result.Align := alClient;
  Result.ViewStyle := vsReport;
  Result.ReadOnly := True;
  Result.RowSelect := True;
  Result.HideSelection := False;
  for mIndex := 0 to High(AColumns) do
  begin
    mColumn := Result.Columns.Add;
    mColumn.Caption := AColumns[mIndex];
    mColumn.Width := ScaleValue(cColumnWidth);
    if mIndex = 0 then
    begin
      mColumn.Width := ScaleValue(cWideColumn);
    end;
  end;
  Result.OnClick := ListClick;
  Result.OnCustomDrawItem := ListDrawItem;
end;

procedure TAtlasFontsDialog.AddButtons;
var
  mButtons: TFlowPanel;
  mButton: TButton;
begin
  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alBottom;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.FlowStyle := fsRightLeftTopBottom;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mButton := TButton.Create(Self);
  mButton.Parent := mButtons;
  mButton.Caption := UiText(TAtlasDesignerTextId.DesignerFontsClose);
  mButton.Cancel := True;
  mButton.ModalResult := mrCancel;
  mButton := TButton.Create(Self);
  mButton.Parent := mButtons;
  mButton.Caption := UiText(TAtlasDesignerTextId.DesignerFontsReplace);
  mButton.AlignWithMargins := True;
  mButton.Margins.SetBounds(0, 0, cGap, 0);
  mButton.OnClick := ReplaceClick;
end;

procedure TAtlasFontsDialog.Fill;
var
  mRow: TAtlasFontRow;
  mColor: TAtlasColorRow;
  mItem: TListItem;
begin
  FFonts.Items.BeginUpdate;
  try
    for mRow in FFontRows do
    begin
      mItem := FFonts.Items.Add;
      mItem.Caption := FontLine(mRow.Font);
      mItem.SubItems.Add(IntToStr(Length(mRow.Own)));
      mItem.SubItems.Add(IntToStr(Length(mRow.Inherits)));
      if mRow.IsFormFont then
      begin
        mItem.SubItems.Add(UiText(TAtlasDesignerTextId.DesignerFontsFormFont));
      end
      else if mRow.Outlier then
      begin
        mItem.SubItems.Add(UiText(TAtlasDesignerTextId.DesignerFontsOutlier));
      end;
    end;
  finally
    FFonts.Items.EndUpdate;
  end;
  FColors.Items.BeginUpdate;
  try
    for mColor in FColorRows do
    begin
      mItem := FColors.Items.Add;
      mItem.Caption := '';
      mItem.SubItems.Add(mColor.Color);
      mItem.SubItems.Add(IntToStr(Length(mColor.Components)));
      if mColor.Outlier then
      begin
        mItem.SubItems.Add(UiText(TAtlasDesignerTextId.DesignerFontsOutlier));
      end;
    end;
  finally
    FColors.Items.EndUpdate;
  end;
end;

procedure TAtlasFontsDialog.ListClick(Sender: TObject);
var
  mList: TListView;
  mIndex: Integer;
begin
  mList := TListView(Sender);
  if (mList.Selected = nil) or not Assigned(FOnSelect) then
  begin
    Exit;
  end;
  mIndex := mList.Selected.Index;
  if (mList = FFonts) and (mIndex <= High(FFontRows)) then
  begin
    FOnSelect(FFontRows[mIndex].Own + FFontRows[mIndex].Inherits);
  end
  else if (mList = FColors) and (mIndex <= High(FColorRows)) then
  begin
    FOnSelect(FColorRows[mIndex].Components);
  end;
end;

procedure TAtlasFontsDialog.ListDrawItem(Sender: TCustomListView; AItem: TListItem; AState: TCustomDrawState;
  var ADefaultDraw: Boolean);
var
  mOutlier: Boolean;
begin
  mOutlier := ((Sender = FFonts) and (AItem.Index <= High(FFontRows)) and FFontRows[AItem.Index].Outlier) or
    ((Sender = FColors) and (AItem.Index <= High(FColorRows)) and FColorRows[AItem.Index].Outlier);
  if mOutlier then
  begin
    Sender.Canvas.Font.Style := [fsBold];
  end;
  ADefaultDraw := True;
end;

procedure TAtlasFontsDialog.ColorDrawSubItem(Sender: TCustomListView; AItem: TListItem; ASubItem: Integer;
  AState: TCustomDrawState; var ADefaultDraw: Boolean);
var
  mRect: TRect;
  mColor: TColor;
begin
  ADefaultDraw := True;
  if (ASubItem <> cColorColumn) or (AItem.Index > High(FColorRows)) then
  begin
    Exit;
  end;
  // Muster in der ersten Spalte, neben dem Namen gezeichnet.
  mRect := AItem.DisplayRect(drBounds);
  mRect.Right := mRect.Left + Sender.Column[0].Width;
  mRect.Inflate(-cSwatchInsetX, -cSwatchInsetY);
  mColor := StringToColor(FColorRows[AItem.Index].Color);
  Sender.Canvas.Brush.Color := mColor;
  Sender.Canvas.Pen.Color := clGray;
  Sender.Canvas.Rectangle(mRect);
  Sender.Canvas.Brush.Style := bsClear;
end;

procedure TAtlasFontsDialog.ReplaceClick(Sender: TObject);
begin
  if (FPages.ActivePageIndex = 0) and (FFonts.Selected <> nil) then
  begin
    FAction := TAtlasFontsAction.ReplaceFont;
    ModalResult := mrOk;
  end
  else if (FPages.ActivePageIndex = 1) and (FColors.Selected <> nil) then
  begin
    FAction := TAtlasFontsAction.ReplaceColor;
    ModalResult := mrOk;
  end;
end;

class function TAtlasFontsDialog.Execute(const AForm: string; const AFontRows: TArray<TAtlasFontRow>;
  const AColorRows: TArray<TAtlasColorRow>; const AOnSelect: TProc<TArray<string>>; var ATab: Integer;
  out ARow: Integer): TAtlasFontsAction;
var
  mDialog: TAtlasFontsDialog;
begin
  ARow := -1;
  mDialog := TAtlasFontsDialog.CreateDialog(nil, AForm, AFontRows, AColorRows, AOnSelect);
  try
    mDialog.FPages.ActivePageIndex := ATab;
    Result := TAtlasFontsAction.Close;
    if mDialog.ShowModal = mrOk then
    begin
      Result := mDialog.FAction;
      ATab := mDialog.FPages.ActivePageIndex;
      ARow := mDialog.FFonts.ItemIndex;
      if Result = TAtlasFontsAction.ReplaceColor then
      begin
        ARow := mDialog.FColors.ItemIndex;
      end;
    end;
  finally
    mDialog.Free;
  end;
end;

{ TAtlasFontReplaceDialog }

constructor TAtlasFontReplaceDialog.CreateDialog(AOwner: TComponent; const ATitle: string; AIsFont,
  AHasSelection: Boolean; const ATargets: TArray<string>);
begin
  inherited CreateNew(AOwner);
  FIsFont := AIsFont;
  InitDialog(ATitle, cComboWidth, bsDialog);
  ClientWidth := ScaleValue(cComboWidth) + 2 * cGap;
  AddTarget(ATargets);
  AddOptions(AHasSelection);
  AddButtons;
  ActiveControl := FTarget;
end;

procedure TAtlasFontReplaceDialog.AddTarget(const ATargets: TArray<string>);
var
  mLabel: TLabel;
  mButton: TButton;
  mText: string;
begin
  mLabel := TLabel.Create(Self);
  mLabel.Parent := Self;
  mLabel.SetBounds(cGap, cGap, ScaleValue(cComboWidth), mLabel.Height);
  mLabel.Caption := UiText(TAtlasDesignerTextId.DesignerFontsTarget);
  FTarget := TComboBox.Create(Self);
  FTarget.Parent := Self;
  FTarget.Style := csDropDownList;
  FTarget.SetBounds(cGap, mLabel.Top + mLabel.Height + cLabelGap, ScaleValue(cComboWidth - cColumnWidth) - cGap,
    FTarget.Height);
  FTarget.Items.BeginUpdate;
  try
    for mText in ATargets do
    begin
      FTarget.Items.Add(mText);
    end;
  finally
    FTarget.Items.EndUpdate;
  end;
  FTarget.ItemIndex := 0;
  mButton := TButton.Create(Self);
  mButton.Parent := Self;
  mButton.Caption := UiText(TAtlasDesignerTextId.DesignerFontsOther);
  mButton.SetBounds(FTarget.Left + FTarget.Width + cGap, FTarget.Top, ScaleValue(cColumnWidth), FTarget.Height);
  mButton.OnClick := OtherClick;
end;

procedure TAtlasFontReplaceDialog.AddOptions(AHasSelection: Boolean);
const
  cIds: array [TAtlasFontPart] of TAtlasDesignerTextId = (TAtlasDesignerTextId.DesignerFontsPartName,
    TAtlasDesignerTextId.DesignerFontsPartSize, TAtlasDesignerTextId.DesignerFontsPartStyle,
    TAtlasDesignerTextId.DesignerFontsColor);
var
  mPart: TAtlasFontPart;
  mTop: Integer;
begin
  mTop := FTarget.Top + FTarget.Height + cGap;
  for mPart := Low(TAtlasFontPart) to High(TAtlasFontPart) do
  begin
    FParts[mPart] := TCheckBox.Create(Self);
    FParts[mPart].Parent := Self;
    FParts[mPart].Caption := UiText(cIds[mPart]);
    FParts[mPart].Checked := True;
    FParts[mPart].Visible := FIsFont;
    FParts[mPart].SetBounds(cGap + Ord(mPart) * ScaleValue(cComboWidth div cPartCount), mTop,
      ScaleValue(cComboWidth div cPartCount), FParts[mPart].Height);
  end;
  if FIsFont then
  begin
    mTop := mTop + FParts[TAtlasFontPart.Name].Height + cGap;
  end;
  FOnlySelected := TCheckBox.Create(Self);
  FOnlySelected.Parent := Self;
  FOnlySelected.Caption := UiText(TAtlasDesignerTextId.DesignerFontsOnlySelected);
  FOnlySelected.Enabled := AHasSelection;
  FOnlySelected.SetBounds(cGap, mTop, ScaleValue(cComboWidth), FOnlySelected.Height);
end;

procedure TAtlasFontReplaceDialog.AddButtons;
var
  mButton: TButton;
begin
  mButton := TButton.Create(Self);
  mButton.Parent := Self;
  mButton.Caption := 'OK';
  mButton.Default := True;
  mButton.ModalResult := mrOk;
  mButton.SetBounds(ClientWidth - cGap - 2 * ScaleValue(cColumnWidth div 2) - cGap,
    FOnlySelected.Top + FOnlySelected.Height + cGap, ScaleValue(cColumnWidth div 2), mButton.Height);
  ClientHeight := mButton.Top + mButton.Height + ScaleValue(cGap);
  mButton := TButton.Create(Self);
  mButton.Parent := Self;
  mButton.Caption := UiText(TAtlasDesignerTextId.DesignerDuplicateCancel);
  mButton.Cancel := True;
  mButton.ModalResult := mrCancel;
  mButton.SetBounds(ClientWidth - cGap - ScaleValue(cColumnWidth div 2), ClientHeight - cGap - mButton.Height,
    ScaleValue(cColumnWidth div 2), mButton.Height);
end;

procedure TAtlasFontReplaceDialog.OtherClick(Sender: TObject);
var
  mFontDialog: TFontDialog;
  mColorDialog: TColorDialog;
begin
  if FIsFont then
  begin
    mFontDialog := TFontDialog.Create(nil);
    try
      if mFontDialog.Execute(Handle) then
      begin
        FFontTargets := FFontTargets + [TAtlasFontsDialog.KeyOf(mFontDialog.Font)];
        FTarget.ItemIndex := FTarget.Items.Add(FontLine(TAtlasFontsDialog.KeyOf(mFontDialog.Font)));
      end;
    finally
      mFontDialog.Free;
    end;
    Exit;
  end;
  mColorDialog := TColorDialog.Create(nil);
  try
    if mColorDialog.Execute(Handle) then
    begin
      FColorTargets := FColorTargets + [ColorToString(mColorDialog.Color)];
      FTarget.ItemIndex := FTarget.Items.Add(ColorToString(mColorDialog.Color));
    end;
  finally
    mColorDialog.Free;
  end;
end;

function TAtlasFontReplaceDialog.Choice: TAtlasFontReplace;
var
  mPart: TAtlasFontPart;
begin
  Result := Default(TAtlasFontReplace);
  Result.OnlySelected := FOnlySelected.Enabled and FOnlySelected.Checked;
  if FIsFont and (FTarget.ItemIndex >= 0) and (FTarget.ItemIndex <= High(FFontTargets)) then
  begin
    Result.Font := FFontTargets[FTarget.ItemIndex];
    for mPart := Low(TAtlasFontPart) to High(TAtlasFontPart) do
    begin
      if FParts[mPart].Checked then
      begin
        Include(Result.Parts, mPart);
      end;
    end;
  end
  else if not FIsFont and (FTarget.ItemIndex >= 0) and (FTarget.ItemIndex <= High(FColorTargets)) then
  begin
    Result.Color := FColorTargets[FTarget.ItemIndex];
  end;
end;

class function TAtlasFontReplaceDialog.ExecuteFont(const AFrom: TAtlasFontKey;
  const ATargets: TArray<TAtlasFontKey>; AHasSelection: Boolean; out AReplace: TAtlasFontReplace): Boolean;
var
  mDialog: TAtlasFontReplaceDialog;
  mTexts: TArray<string>;
  mFont: TAtlasFontKey;
begin
  mTexts := nil;
  for mFont in ATargets do
  begin
    mTexts := mTexts + [FontLine(mFont)];
  end;
  mDialog := TAtlasFontReplaceDialog.CreateDialog(nil, TAtlasDesignerStrings.Fmt(
    TAtlasDesignerTextId.DesignerFontsReplaceTitle, [FontLine(AFrom)]), True, AHasSelection, mTexts);
  try
    mDialog.FFontTargets := ATargets;
    Result := (mDialog.ShowModal = mrOk) and (mDialog.FTarget.ItemIndex >= 0);
    AReplace := mDialog.Choice;
    Result := Result and (AReplace.Parts <> []);
  finally
    mDialog.Free;
  end;
end;

class function TAtlasFontReplaceDialog.ExecuteColor(const AFrom: string; const ATargets: TArray<string>;
  AHasSelection: Boolean; out AReplace: TAtlasFontReplace): Boolean;
var
  mDialog: TAtlasFontReplaceDialog;
begin
  mDialog := TAtlasFontReplaceDialog.CreateDialog(nil, TAtlasDesignerStrings.Fmt(
    TAtlasDesignerTextId.DesignerFontsReplaceTitle, [AFrom]), False, AHasSelection, ATargets);
  try
    mDialog.FColorTargets := ATargets;
    Result := (mDialog.ShowModal = mrOk) and (mDialog.FTarget.ItemIndex >= 0);
    AReplace := mDialog.Choice;
    Result := Result and (AReplace.Color <> '');
  finally
    mDialog.Free;
  end;
end;

end.
