unit Atlas.UI.EditorToolbar.Customize;

// Atlas-Editorleiste (#1101): Dialog „Leiste anpassen“. Links die verfügbaren
// Befehle der Befehlspalette (#600) samt „— Trennstrich —“, rechts die Knöpfe
// der Leiste mit Symbol in ihrer Reihenfolge. Dazwischen →/← (hinzufügen,
// entfernen), daneben ↑/↓ (verschieben); Doppelklick fügt hinzu bzw. entfernt.
// Darunter „Text neben den Symbolen“, die Position und „Standard
// wiederherstellen“. Der Dialog arbeitet auf einer Kopie (TAtlasToolbarConfig);
// erst OK übernimmt sie. Die Listenschritte selbst stecken in
// TAtlasToolbarItems (ohne VCL getestet). Die Listen werden erst mit Fenster
// gefüllt (TListBox.Items braucht eins), Änderungen ohne Fenster nur gemerkt.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.UI.Foundation.Dialog;

type
  /// <summary>Ein Befehl, der in die Leiste kann (aus der Befehlspalette).</summary>
  TAtlasToolbarCommandInfo = record
    Id: string;
    Caption: string;
    class function Create(const AId, ACaption: string): TAtlasToolbarCommandInfo; static;
  end;

  /// <summary>Was der Dialog ändert.</summary>
  TAtlasToolbarConfig = record
    Items: TArray<string>;
    Labels: Boolean;
    /// <summary>belowBreadcrumbs, aboveBreadcrumbs oder inBreadcrumbs.</summary>
    Position: string;
  end;

  TAtlasToolbarCustomizeDialog = class(TAtlasDialog)
  private
    FCommands: TArray<TAtlasToolbarCommandInfo>;
    FConfig: TAtlasToolbarConfig;
    /// <summary>Kennungen der linken Liste in Anzeigereihenfolge (zuerst der Trennstrich).</summary>
    FAvailable: TArray<string>;
    FAvailableList: TListBox;
    FCurrentList: TListBox;
    FAddButton: TButton;
    FRemoveButton: TButton;
    FUpButton: TButton;
    FDownButton: TButton;
    FLabelsCheck: TCheckBox;
    FPositionCombo: TComboBox;
    FOk: TButton;
    FCancel: TButton;
    FFilled: Boolean;
    procedure BuildAvailable;
    procedure Fill(ACurrentIndex, AAvailableIndex: Integer);
    procedure UpdateButtons;
    /// <summary>Knopf mit Aktion im Tag (TAtlasToolbarCustomizeAction).</summary>
    procedure ActionClick(Sender: TObject);
    /// <summary>Doppelklick: links hinzufügen, rechts entfernen.</summary>
    procedure ListDblClick(Sender: TObject);
    procedure ListClick(Sender: TObject);
    procedure LabelsClick(Sender: TObject);
    procedure PositionChange(Sender: TObject);
    procedure CurrentDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; const ACommands: TArray<TAtlasToolbarCommandInfo>;
      const AConfig: TAtlasToolbarConfig);
    /// <summary>Beschriftung zur Kennung; '|' ist der Trennstrich, unbekannte Kennungen bleiben, wie sie
    /// sind.</summary>
    function CaptionOf(const AId: string): string;
    /// <summary>Linke Liste: Kennungen in Anzeigereihenfolge (Trennstrich zuerst, dann nach Beschriftung).</summary>
    function Available: TArray<string>;
    /// <summary>Eintrag AAvailableIndex der linken Liste vor AIndex einfügen; liefert den neuen Index oder
    /// -1.</summary>
    function AddItem(AAvailableIndex, AIndex: Integer): Integer;
    function RemoveItem(AIndex: Integer): Boolean;
    function MoveItem(AIndex, ADelta: Integer): Integer;
    procedure RestoreDefault;
    procedure SetLabels(AValue: Boolean);
    procedure SetPosition(const AValue: string);
    property Config: TAtlasToolbarConfig read FConfig;
    property AvailableList: TListBox read FAvailableList;
    property CurrentList: TListBox read FCurrentList;
    property OkButton: TButton read FOk;
    property CancelButton: TButton read FCancel;
    /// <summary>Zeigt den Dialog modal; True und die neue Belegung in AConfig bei OK.</summary>
    class function Execute(const ACommands: TArray<TAtlasToolbarCommandInfo>;
      var AConfig: TAtlasToolbarConfig): Boolean; static;
  end;

const
  /// <summary>Werte von editor.toolbar.position in der Reihenfolge der Auswahl.</summary>
  cAtlasToolbarPositions: array[0..2] of string = ('belowBreadcrumbs', 'aboveBreadcrumbs', 'inBreadcrumbs');

implementation

uses
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.EditorToolbar.Icons,
  System.Math,
  System.UITypes,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.UI.Strings,
  Atlas.UI.EditorToolbar.Strings,
  Atlas.UI.EditorToolbar.Glyphs;

const
  cGap = 8;
  cDialogWidth = 640;

type
{$SCOPEDENUMS ON}
  /// <summary>Aktion eines Knopfs (im Tag).</summary>
  TAtlasToolbarCustomizeAction = (None, Add, Remove, Up, Down, Default, Ok);
{$SCOPEDENUMS OFF}

  /// <summary>Baut die Steuerelemente des Dialogs: untere Knopfleiste, Optionen und die Listen.</summary>
  TAtlasToolbarCustomizeBuilder = record
    Dialog: TAtlasToolbarCustomizeDialog;
    function NewPanel(AParent: TWinControl; AAlign: TAlign; ASize: Integer): TPanel;
    function NewButton(AParent: TWinControl; const ACaption, AHint: string;
      AAction: TAtlasToolbarCustomizeAction): TButton;
    function NewList(AParent: TWinControl): TListBox;
    procedure BuildBottom;
    procedure BuildOptions;
    procedure BuildLists;
    procedure BuildHeading;
  end;

function TAtlasToolbarCustomizeBuilder.NewPanel(AParent: TWinControl; AAlign: TAlign; ASize: Integer): TPanel;
begin
  Result := TPanel.Create(Dialog);
  Result.Parent := AParent;
  Result.Align := AAlign;
  Result.BevelOuter := bvNone;
  if AAlign in [alLeft, alRight] then
  begin
    Result.Width := ASize;
  end
  else if AAlign in [alTop, alBottom] then
  begin
    Result.Height := ASize;
  end;
end;

function TAtlasToolbarCustomizeBuilder.NewButton(AParent: TWinControl; const ACaption, AHint: string;
  AAction: TAtlasToolbarCustomizeAction): TButton;
begin
  Result := TButton.Create(Dialog);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.Tag := Ord(AAction);
  if AAction <> TAtlasToolbarCustomizeAction.None then
  begin
    Result.OnClick := Dialog.ActionClick;
  end;
  Dialog.Canvas.Font := Dialog.Font;
  Result.Width := Max(Dialog.ScaleValue(90), Dialog.Canvas.TextWidth(ACaption) + Dialog.ScaleValue(32));
  Result.Top := Dialog.ScaleValue(cGap);
  Result.Height := Dialog.ScaleValue(28);
end;

function TAtlasToolbarCustomizeBuilder.NewList(AParent: TWinControl): TListBox;
begin
  Result := TListBox.Create(Dialog);
  Result.Parent := AParent;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(Dialog.ScaleValue(cGap), Dialog.ScaleValue(4), 0, Dialog.ScaleValue(cGap));
  Result.OnClick := Dialog.ListClick;
  Result.OnDblClick := Dialog.ListDblClick;
end;

procedure TAtlasToolbarCustomizeBuilder.BuildBottom;
var
  mBottom: TPanel;
  mDefault: TButton;
begin
  mBottom := NewPanel(Dialog, alBottom, Dialog.ScaleValue(44));
  Dialog.FCancel := NewButton(mBottom, TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.EditorToolbarCancel),
    '',
    TAtlasToolbarCustomizeAction.None);
  Dialog.FCancel.Cancel := True;
  Dialog.FCancel.ModalResult := mrCancel;
  Dialog.FCancel.Left := mBottom.ClientWidth - Dialog.FCancel.Width - Dialog.ScaleValue(cGap);
  Dialog.FCancel.Anchors := [akTop, akRight];
  Dialog.FOk := NewButton(mBottom, TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.EditorToolbarOk), '',
    TAtlasToolbarCustomizeAction.Ok);
  Dialog.FOk.Default := True;
  Dialog.FOk.Left := Dialog.FCancel.Left - Dialog.FOk.Width - Dialog.ScaleValue(cGap);
  Dialog.FOk.Anchors := [akTop, akRight];
  mDefault := NewButton(mBottom, TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.EditorToolbarRestoreDefault),
    '',
    TAtlasToolbarCustomizeAction.Default);
  mDefault.Left := Dialog.ScaleValue(cGap);
end;

procedure TAtlasToolbarCustomizeBuilder.BuildOptions;
var
  mOptions: TPanel;
  mCaption: TLabel;
begin
  mOptions := NewPanel(Dialog, alBottom, Dialog.ScaleValue(36));
  Dialog.FLabelsCheck := TCheckBox.Create(Dialog);
  Dialog.FLabelsCheck.Parent := mOptions;
  Dialog.FLabelsCheck.Caption := TAtlasStrings.Text(TAtlasTextId.EditorToolbarLabels);
  Dialog.FLabelsCheck.SetBounds(Dialog.ScaleValue(cGap), Dialog.ScaleValue(cGap), Dialog.ScaleValue(220),
    Dialog.ScaleValue(20));
  Dialog.FLabelsCheck.Checked := Dialog.FConfig.Labels;
  Dialog.FLabelsCheck.OnClick := Dialog.LabelsClick;
  mCaption := TLabel.Create(Dialog);
  mCaption.Parent := mOptions;
  mCaption.Caption := TAtlasStrings.Text(TAtlasTextId.EditorToolbarPosition);
  mCaption.SetBounds(Dialog.ScaleValue(250), Dialog.ScaleValue(cGap + 2), Dialog.ScaleValue(70), Dialog.ScaleValue(20));
  Dialog.FPositionCombo := TComboBox.Create(Dialog);
  Dialog.FPositionCombo.Parent := mOptions;
  Dialog.FPositionCombo.Style := csDropDownList;
  Dialog.FPositionCombo.SetBounds(Dialog.ScaleValue(330), Dialog.ScaleValue(cGap - 2), Dialog.ScaleValue(240),
    Dialog.ScaleValue(24));
  Dialog.FPositionCombo.OnChange := Dialog.PositionChange;
  mCaption.FocusControl := Dialog.FPositionCombo;
end;

procedure TAtlasToolbarCustomizeBuilder.BuildLists;
var
  mLists, mMiddle, mSide: TPanel;
begin
  mLists := NewPanel(Dialog, alClient, 0);
  // Links verfügbar, Mitte → ←, rechts die Leiste, ganz rechts ↑ ↓.
  mSide := NewPanel(mLists, alRight, Dialog.ScaleValue(48));
  Dialog.FUpButton := NewButton(mSide, '↑',
    TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.EditorToolbarUpHint),
    TAtlasToolbarCustomizeAction.Up);
  Dialog.FUpButton.SetBounds(Dialog.ScaleValue(cGap), Dialog.ScaleValue(80), Dialog.ScaleValue(32),
    Dialog.ScaleValue(28));
  Dialog.FDownButton := NewButton(mSide, '↓',
    TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.EditorToolbarDownHint),
    TAtlasToolbarCustomizeAction.Down);
  Dialog.FDownButton.SetBounds(Dialog.ScaleValue(cGap), Dialog.ScaleValue(116), Dialog.ScaleValue(32),
    Dialog.ScaleValue(28));
  Dialog.FCurrentList := NewList(mLists);
  Dialog.FCurrentList.Align := alRight;
  Dialog.FCurrentList.Width := Dialog.ScaleValue(260);
  Dialog.FCurrentList.Style := lbOwnerDrawFixed;
  Dialog.FCurrentList.ItemHeight := Dialog.ScaleValue(24);
  Dialog.FCurrentList.OnDrawItem := Dialog.CurrentDrawItem;
  mMiddle := NewPanel(mLists, alRight, Dialog.ScaleValue(56));
  Dialog.FAddButton := NewButton(mMiddle, '→',
    TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.EditorToolbarAddHint),
    TAtlasToolbarCustomizeAction.Add);
  Dialog.FAddButton.SetBounds(Dialog.ScaleValue(12), Dialog.ScaleValue(80), Dialog.ScaleValue(32),
    Dialog.ScaleValue(28));
  Dialog.FRemoveButton := NewButton(mMiddle, '←',
    TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.EditorToolbarRemoveHint),
    TAtlasToolbarCustomizeAction.Remove);
  Dialog.FRemoveButton.SetBounds(Dialog.ScaleValue(12), Dialog.ScaleValue(116), Dialog.ScaleValue(32),
    Dialog.ScaleValue(28));
  Dialog.FAvailableList := NewList(mLists);
  Dialog.FAvailableList.Align := alClient;
end;

procedure TAtlasToolbarCustomizeBuilder.BuildHeading;
var
  mCaption: TLabel;
begin
  // Überschriften über den Listen.
  mCaption := TLabel.Create(Dialog);
  mCaption.Parent := Dialog;
  mCaption.Align := alTop;
  mCaption.AlignWithMargins := True;
  mCaption.Margins.SetBounds(Dialog.ScaleValue(cGap), Dialog.ScaleValue(cGap), Dialog.ScaleValue(cGap), 0);
  mCaption.ShowAccelChar := False;
  mCaption.Caption := TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.EditorToolbarAvailable) + '  ›  ' +
    TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.EditorToolbarCurrent);
end;

{ TAtlasToolbarCommandInfo }

class function TAtlasToolbarCommandInfo.Create(const AId, ACaption: string): TAtlasToolbarCommandInfo;
begin
  Result.Id := AId;
  Result.Caption := ACaption;
end;

{ TAtlasToolbarCustomizeDialog }

constructor TAtlasToolbarCustomizeDialog.CreateDialog(AOwner: TComponent;
  const ACommands: TArray<TAtlasToolbarCommandInfo>; const AConfig: TAtlasToolbarConfig);
var
  mBuilder: TAtlasToolbarCustomizeBuilder;
  mPosition: string;
begin
  inherited CreateDialog(AOwner, '', cDialogWidth);
  FCommands := ACommands;
  FConfig := AConfig;
  FConfig.Items := TAtlasToolbarItems.Clean(AConfig.Items);
  Caption := TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.EditorToolbarCustomizeTitle);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  ClientHeight := ScaleValue(440);
  Constraints.MinWidth := ScaleValue(480);
  Constraints.MinHeight := ScaleValue(320);
  mBuilder.Dialog := Self;
  mBuilder.BuildBottom;
  mBuilder.BuildOptions;
  mBuilder.BuildLists;
  mBuilder.BuildHeading;
  ShowHint := True;
  BuildAvailable;
  for mPosition in cAtlasToolbarPositions do
  begin
    if SameText(mPosition, FConfig.Position) then
    begin
      FConfig.Position := mPosition;
    end;
  end;
  if FConfig.Position = '' then
  begin
    FConfig.Position := cAtlasToolbarPositions[0];
  end;
end;

function TAtlasToolbarCustomizeDialog.CaptionOf(const AId: string): string;
var
  mCommand: TAtlasToolbarCommandInfo;
begin
  if TAtlasToolbarItems.IsSeparator(AId) then
  begin
    Exit(TAtlasEditorToolbarStrings.Text(TAtlasEditorToolbarTextId.EditorToolbarSeparator));
  end;
  for mCommand in FCommands do
  begin
    if SameText(mCommand.Id, AId) then
    begin
      Exit(mCommand.Caption);
    end;
  end;
  Result := AId;
end;

procedure TAtlasToolbarCustomizeDialog.BuildAvailable;
var
  mCommand: TAtlasToolbarCommandInfo;
  mItem: string;
  mUsed: Boolean;
  mRest: TList<TAtlasToolbarCommandInfo>;
begin
  mRest := TList<TAtlasToolbarCommandInfo>.Create;
  try
    for mCommand in FCommands do
    begin
      mUsed := False;
      for mItem in FConfig.Items do
      begin
        if SameText(mItem, mCommand.Id) then
        begin
          mUsed := True;
        end;
      end;
      if not mUsed then
      begin
        mRest.Add(mCommand);
      end;
    end;
    mRest.Sort(TComparer<TAtlasToolbarCommandInfo>.Construct(
      function(const A, B: TAtlasToolbarCommandInfo): Integer
      begin
        Result := CompareText(A.Caption, B.Caption);
      end));
    FAvailable := [TAtlasToolbarItems.cSeparator];
    for mCommand in mRest do
    begin
      FAvailable := FAvailable + [mCommand.Id];
    end;
  finally
    mRest.Free;
  end;
end;

function TAtlasToolbarCustomizeDialog.Available: TArray<string>;
begin
  Result := FAvailable;
end;

function TAtlasToolbarCustomizeDialog.AddItem(AAvailableIndex, AIndex: Integer): Integer;
var
  mNext: Integer;
begin
  if (AAvailableIndex < 0) or (AAvailableIndex > High(FAvailable)) then
  begin
    Exit(-1);
  end;
  Result := TAtlasToolbarItems.Add(FConfig.Items, FAvailable[AAvailableIndex], AIndex);
  if Result < 0 then
  begin
    Exit;
  end;
  BuildAvailable;
  // Links bleibt die Auswahl an derselben Stelle (der Trennstrich bleibt stehen).
  mNext := Min(AAvailableIndex, High(FAvailable));
  Fill(Result, mNext);
end;

function TAtlasToolbarCustomizeDialog.RemoveItem(AIndex: Integer): Boolean;
begin
  Result := TAtlasToolbarItems.Remove(FConfig.Items, AIndex);
  if not Result then
  begin
    Exit;
  end;
  BuildAvailable;
  Fill(Min(AIndex, High(FConfig.Items)), -1);
end;

function TAtlasToolbarCustomizeDialog.MoveItem(AIndex, ADelta: Integer): Integer;
begin
  Result := TAtlasToolbarItems.Move(FConfig.Items, AIndex, ADelta);
  Fill(Result, -1);
end;

procedure TAtlasToolbarCustomizeDialog.RestoreDefault;
begin
  FConfig.Items := TAtlasToolbarItems.Default;
  FConfig.Labels := False;
  FConfig.Position := cAtlasToolbarPositions[0];
  BuildAvailable;
  Fill(-1, -1);
end;

procedure TAtlasToolbarCustomizeDialog.SetLabels(AValue: Boolean);
begin
  FConfig.Labels := AValue;
  if FFilled and (FLabelsCheck.Checked <> AValue) then
  begin
    FLabelsCheck.Checked := AValue;
  end;
end;

procedure TAtlasToolbarCustomizeDialog.SetPosition(const AValue: string);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(cAtlasToolbarPositions) do
  begin
    if SameText(cAtlasToolbarPositions[mIndex], AValue) then
    begin
      FConfig.Position := cAtlasToolbarPositions[mIndex];
      if FFilled then
      begin
        FPositionCombo.ItemIndex := mIndex;
      end;
    end;
  end;
end;

procedure TAtlasToolbarCustomizeDialog.DoShow;
begin
  inherited DoShow;
  Fill(-1, -1);
end;

procedure TAtlasToolbarCustomizeDialog.Fill(ACurrentIndex, AAvailableIndex: Integer);
var
  mItem: string;
  mIndex: Integer;
begin
  // Ohne Fenster bleibt es bei FConfig; DoShow füllt dann.
  if not HandleAllocated then
  begin
    Exit;
  end;
  FFilled := True;
  FAvailableList.Items.BeginUpdate;
  try
    FAvailableList.Items.Clear;
    for mItem in FAvailable do
    begin
      FAvailableList.Items.Add(CaptionOf(mItem));
    end;
  finally
    FAvailableList.Items.EndUpdate;
  end;
  FCurrentList.Items.BeginUpdate;
  try
    FCurrentList.Items.Clear;
    for mItem in FConfig.Items do
    begin
      FCurrentList.Items.Add(CaptionOf(mItem));
    end;
  finally
    FCurrentList.Items.EndUpdate;
  end;
  FCurrentList.ItemIndex := ACurrentIndex;
  FAvailableList.ItemIndex := AAvailableIndex;
  FLabelsCheck.Checked := FConfig.Labels;
  if FPositionCombo.Items.Count = 0 then
  begin
    FPositionCombo.Items.Add(TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionBelow));
    FPositionCombo.Items.Add(TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionAbove));
    FPositionCombo.Items.Add(TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionInline));
  end;
  FPositionCombo.ItemIndex := 0;
  for mIndex := 0 to High(cAtlasToolbarPositions) do
  begin
    if cAtlasToolbarPositions[mIndex] = FConfig.Position then
    begin
      FPositionCombo.ItemIndex := mIndex;
    end;
  end;
  UpdateButtons;
end;

procedure TAtlasToolbarCustomizeDialog.UpdateButtons;
var
  mCurrent: Integer;
begin
  mCurrent := FCurrentList.ItemIndex;
  FAddButton.Enabled := FAvailableList.ItemIndex >= 0;
  FRemoveButton.Enabled := mCurrent >= 0;
  FUpButton.Enabled := mCurrent > 0;
  FDownButton.Enabled := (mCurrent >= 0) and (mCurrent < High(FConfig.Items));
end;

procedure TAtlasToolbarCustomizeDialog.ListClick(Sender: TObject);
begin
  UpdateButtons;
end;

procedure TAtlasToolbarCustomizeDialog.ActionClick(Sender: TObject);
var
  mTarget: Integer;
begin
  case TAtlasToolbarCustomizeAction(TComponent(Sender).Tag) of
    TAtlasToolbarCustomizeAction.Add:
      begin
        // Hinter dem ausgewählten Knopf der Leiste einfügen, sonst hinten.
        mTarget := Length(FConfig.Items);
        if FCurrentList.ItemIndex >= 0 then
        begin
          mTarget := FCurrentList.ItemIndex + 1;
        end;
        AddItem(FAvailableList.ItemIndex, mTarget);
      end;
    TAtlasToolbarCustomizeAction.Remove:
      RemoveItem(FCurrentList.ItemIndex);
    TAtlasToolbarCustomizeAction.Up:
      MoveItem(FCurrentList.ItemIndex, -1);
    TAtlasToolbarCustomizeAction.Down:
      MoveItem(FCurrentList.ItemIndex, 1);
    TAtlasToolbarCustomizeAction.Default:
      RestoreDefault;
    TAtlasToolbarCustomizeAction.Ok:
      begin
        // Trennstriche am Rand oder doppelt fallen beim Übernehmen weg.
        FConfig.Items := TAtlasToolbarItems.Clean(FConfig.Items);
        ModalResult := mrOk;
      end;
  else
    // None: Abbrechen schließt über ModalResult.
  end;
end;

procedure TAtlasToolbarCustomizeDialog.ListDblClick(Sender: TObject);
begin
  if Sender = FAvailableList then
  begin
    ActionClick(FAddButton);
  end
  else
  begin
    ActionClick(FRemoveButton);
  end;
end;

procedure TAtlasToolbarCustomizeDialog.LabelsClick(Sender: TObject);
begin
  FConfig.Labels := FLabelsCheck.Checked;
end;

procedure TAtlasToolbarCustomizeDialog.PositionChange(Sender: TObject);
begin
  if (FPositionCombo.ItemIndex >= 0) and (FPositionCombo.ItemIndex <= High(cAtlasToolbarPositions)) then
  begin
    FConfig.Position := cAtlasToolbarPositions[FPositionCombo.ItemIndex];
  end;
end;

procedure TAtlasToolbarCustomizeDialog.CurrentDrawItem(Control: TWinControl; Index: Integer; Rect: TRect;
  State: TOwnerDrawState);
var
  mList: TListBox;
  mId: string;
  mIcon, mText: TRect;
  mCaption_: string;
  mSize, mMiddle: Integer;
begin
  mList := TListBox(Control);
  mList.Canvas.FillRect(Rect);
  if (Index < 0) or (Index > High(FConfig.Items)) then
  begin
    Exit;
  end;
  mId := FConfig.Items[Index];
  mCaption_ := CaptionOf(mId);
  mSize := ScaleValue(16);
  mIcon := System.Types.Rect(Rect.Left + ScaleValue(4), Rect.Top + (Rect.Height - mSize) div 2,
    Rect.Left + ScaleValue(4) + mSize, Rect.Top + (Rect.Height - mSize) div 2 + mSize);
  if TAtlasToolbarItems.IsSeparator(mId) then
  begin
    mMiddle := (Rect.Top + Rect.Bottom) div 2;
    mList.Canvas.Pen.Color := mList.Canvas.Font.Color;
    mList.Canvas.MoveTo(mIcon.Left, mMiddle);
    mList.Canvas.LineTo(mIcon.Right, mMiddle);
  end
  else
  begin
    TAtlasGlyphPainter.Draw(mList.Canvas, TAtlasToolbarIcons.IconOf(mId), mIcon, mList.Canvas.Font.Color,
      mList.Canvas.Brush.Color, mCaption_);
  end;
  mText := System.Types.Rect(mIcon.Right + ScaleValue(6), Rect.Top, Rect.Right - ScaleValue(2), Rect.Bottom);
  mList.Canvas.Brush.Style := bsClear;
  DrawText(mList.Canvas.Handle, PChar(mCaption_), -1, mText, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  mList.Canvas.Brush.Style := bsSolid;
end;

class function TAtlasToolbarCustomizeDialog.Execute(const ACommands: TArray<TAtlasToolbarCommandInfo>;
  var AConfig: TAtlasToolbarConfig): Boolean;
var
  mDialog: TAtlasToolbarCustomizeDialog;
begin
  mDialog := TAtlasToolbarCustomizeDialog.CreateDialog(nil, ACommands, AConfig);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AConfig := mDialog.Config;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
