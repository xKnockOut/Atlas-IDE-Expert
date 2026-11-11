unit Atlas.UI.Editor.ChangeSignature;

// Dialog „Signatur ändern“ (#100): Liste der Parameter mit Name, Typ,
// Modifizierer und Standardwert bzw. Wert für die bisherigen Aufrufer,
// Knöpfe zum Hinzufügen, Entfernen und Verschieben, Felder für die gewählte
// Zeile (bei vorhandenen Parametern nur der Name), die Wahl für neue Parameter
// (Überladung oder alle Aufrufer) und die Vorschau der neuen Signatur. Fehler
// zeigt die Zeile über den Knöpfen; „Vorschau …“ geht erst ohne Fehler.
// Reine VCL; das Modell ist TAtlasSignatureModel.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Atlas.Core.Editor.ChangeSignature;

type
  TAtlasChangeSignatureDialog = class(TForm)
  private
    FModel: TAtlasSignatureModel;
    FList: TListView;
    FName: TEdit;
    FType: TEdit;
    FModifier: TComboBox;
    FValue: TEdit;
    FAdd: TButton;
    FRemove: TButton;
    FUp: TButton;
    FDown: TButton;
    FOverload: TRadioButton;
    FCallers: TRadioButton;
    FVirtual: TCheckBox;
    FPreview: TLabel;
    FError: TLabel;
    FNotes: TLabel;
    FOk: TButton;
    FCancel: TButton;
    FUpdating: Boolean;
    /// <summary>Knöpfe unten, darüber Hinweise, Fehler und Vorschau.</summary>
    procedure CreateBottom;
    /// <summary>Wahl für neue Parameter (Überladung oder alle Aufrufer).</summary>
    procedure CreateOptions;
    /// <summary>Felder der gewählten Zeile.</summary>
    procedure CreateFields;
    /// <summary>Knöpfe rechts neben der Liste.</summary>
    procedure CreateSide;
    function Selected: Integer;
    procedure FillList(ASelect: Integer);
    procedure ShowRow;
    procedure Refresh;
    procedure AddClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure FieldChange(Sender: TObject);
    procedure ModeClick(Sender: TObject);
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure OkClick(Sender: TObject);
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; AModel: TAtlasSignatureModel);
    /// <summary>True, wenn der Benutzer „Vorschau …“ gewählt hat; das Modell enthält dann die neue Liste.</summary>
    class function Execute(AModel: TAtlasSignatureModel): Boolean; static;
  end;

implementation

uses
  Vcl.Graphics,
  Atlas.UI.Strings,
  Atlas.UI.Editor.Strings;

const
  // Breiten der Spalten Name, Typ, Modifizierer und Vorgabewert in der Parameterliste.
  cSigNameWidth = 130;
  cSigTypeWidth = 140;
  cSigModifierWidth = 80;
  cSigValueWidth = 140;

const
  cGap = 8;
  cDialogWidth = 640;
  cDialogHeight = 520;

/// <summary>Panel ohne Rahmen in AParent, an AAlign ausgerichtet; ASize ist Höhe bzw. Breite (schon skaliert).
/// </summary>
function AddPanel(AParent: TWinControl; AAlign: TAlign; ASize: Integer): TPanel;
begin
  Result := TPanel.Create(AParent);
  Result.Parent := AParent;
  Result.Align := AAlign;
  if AAlign in [alLeft, alRight] then
  begin
    Result.Width := ASize;
  end
  else
  begin
    Result.Height := ASize;
  end;
  Result.BevelOuter := bvNone;
end;

/// <summary>Mehrzeilige Beschriftung unten in AForm mit den Rändern Gap und oben ATopMargin.</summary>
function AddNoteLabel(AForm: TForm; ATopMargin: Integer): TLabel;
begin
  Result := TLabel.Create(AForm);
  Result.Parent := AForm;
  Result.Align := alBottom;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(cGap, ATopMargin, cGap, cGap div 2);
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
end;

function AddButton(ADialog: TAtlasChangeSignatureDialog; AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(ADialog);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Result.Width := ADialog.ScaleValue(100);
  Result.Top := ADialog.ScaleValue(cGap);
  Result.Height := ADialog.ScaleValue(28);
  Result.Anchors := [akTop, akRight];
end;

/// <summary>Beschriftung ACaption und AControl in einer Zeile ab ATop; liefert den Beginn der nächsten Zeile.
/// </summary>
function AddLabeled(ADialog: TAtlasChangeSignatureDialog; AParent: TWinControl; const ACaption: string;
  ATop: Integer; AControl: TWinControl): Integer;
var
  mCaption: TLabel;
begin
  mCaption := TLabel.Create(ADialog);
  mCaption.Parent := AParent;
  mCaption.Caption := ACaption;
  mCaption.SetBounds(ADialog.ScaleValue(cGap), ATop + ADialog.ScaleValue(3), ADialog.ScaleValue(190),
    ADialog.ScaleValue(20));
  mCaption.FocusControl := AControl;
  AControl.Parent := AParent;
  AControl.SetBounds(ADialog.ScaleValue(200), ATop, ADialog.ScaleValue(cDialogWidth - 200 - cGap),
    ADialog.ScaleValue(23));
  AControl.Anchors := [akLeft, akTop, akRight];
  Result := ATop + ADialog.ScaleValue(28);
end;

/// <summary>Spalte ACaption mit der Breite AWidth (schon skaliert).</summary>
procedure AddColumn(AList: TListView; const ACaption: string; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := ACaption;
  mColumn.Width := AWidth;
end;

/// <summary>Hinweise zum Modell: festes Ereignis und Warnungen des Servers, je eine Zeile.</summary>
function NotesOf(AModel: TAtlasSignatureModel): string;
var
  mWarning: string;
begin
  Result := '';
  if AModel.EventFixed then
  begin
    Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.SigEventFixed, [AModel.BoundEvent]);
  end;
  for mWarning in AModel.Warnings do
  begin
    if Result <> '' then
    begin
      Result := Result + sLineBreak;
    end;
    Result := Result + TAtlasStrings.Fmt(TAtlasTextId.SigWarning, [mWarning]);
  end;
end;

{ TAtlasChangeSignatureDialog }

constructor TAtlasChangeSignatureDialog.CreateDialog(AOwner: TComponent; AModel: TAtlasSignatureModel);
begin
  inherited CreateNew(AOwner);
  FModel := AModel;
  Caption := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.SigTitle, [AModel.Name]);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);
  ClientHeight := ScaleValue(cDialogHeight);
  // Reihenfolge zählt: Was zuerst unten ausgerichtet wird, steht zuunterst.
  CreateBottom;
  CreateOptions;
  CreateFields;
  CreateSide;
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(cGap, cGap, 0, 0);
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnSelectItem := ListSelect;
  AddColumn(FList, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigColName), ScaleValue(cSigNameWidth));
  AddColumn(FList, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigColType), ScaleValue(cSigTypeWidth));
  AddColumn(FList, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigColModifier), ScaleValue(cSigModifierWidth));
  AddColumn(FList, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigColValue), ScaleValue(cSigValueWidth));
  ActiveControl := FList;
end;

procedure TAtlasChangeSignatureDialog.CreateBottom;
var
  mBottom: TPanel;
begin
  mBottom := AddPanel(Self, alBottom, ScaleValue(44));
  FCancel := AddButton(Self, mBottom, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigCancel), nil);
  FCancel.Cancel := True;
  FCancel.ModalResult := mrCancel;
  FCancel.Left := mBottom.ClientWidth - FCancel.Width - ScaleValue(cGap);
  FOk := AddButton(Self, mBottom, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigPreviewButton), OkClick);
  FOk.Default := True;
  FOk.Left := FCancel.Left - FOk.Width - ScaleValue(cGap);
  FNotes := AddNoteLabel(Self, 0);
  FNotes.Caption := NotesOf(FModel);
  FError := AddNoteLabel(Self, 0);
  FError.Font.Color := clRed;
  FPreview := AddNoteLabel(Self, cGap div 2);
  FPreview.Font.Name := 'Consolas';
end;

procedure TAtlasChangeSignatureDialog.CreateOptions;
var
  mOptions: TPanel;
begin
  mOptions := AddPanel(Self, alBottom, ScaleValue(72));
  FOverload := TRadioButton.Create(Self);
  FOverload.Parent := mOptions;
  FOverload.SetBounds(ScaleValue(cGap), ScaleValue(4), ScaleValue(cDialogWidth - 2 * cGap), ScaleValue(20));
  FOverload.Caption := TAtlasEditorStrings.Text(TAtlasEditorTextId.SigModeOverload);
  FOverload.OnClick := ModeClick;
  FCallers := TRadioButton.Create(Self);
  FCallers.Parent := mOptions;
  FCallers.SetBounds(ScaleValue(cGap), ScaleValue(26), ScaleValue(cDialogWidth - 2 * cGap), ScaleValue(20));
  FCallers.Caption := TAtlasEditorStrings.Text(TAtlasEditorTextId.SigModeCallers);
  FCallers.OnClick := ModeClick;
  FVirtual := TCheckBox.Create(Self);
  FVirtual.Parent := mOptions;
  FVirtual.SetBounds(ScaleValue(cGap + 16), ScaleValue(48), ScaleValue(cDialogWidth - 2 * cGap - 16), ScaleValue(20));
  FVirtual.Caption := TAtlasEditorStrings.Text(TAtlasEditorTextId.SigVirtual);
  FVirtual.Checked := FModel.VirtualOverload;
  FVirtual.OnClick := ModeClick;
  if not FModel.OverloadPossible then
  begin
    FOverload.Enabled := False;
    FOverload.Caption := FOverload.Caption + ' – ' + TAtlasEditorStrings.Text(TAtlasEditorTextId.SigModeForced);
  end;
  FOverload.Checked := FModel.UseOverload;
  FCallers.Checked := not FModel.UseOverload;
end;

procedure TAtlasChangeSignatureDialog.CreateFields;
var
  mFields: TPanel;
  mTop: Integer;
begin
  mFields := AddPanel(Self, alBottom, ScaleValue(118));
  FName := TEdit.Create(Self);
  FType := TEdit.Create(Self);
  FModifier := TComboBox.Create(Self);
  FValue := TEdit.Create(Self);
  mTop := ScaleValue(4);
  mTop := AddLabeled(Self, mFields, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigFieldName), mTop, FName);
  mTop := AddLabeled(Self, mFields, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigFieldType), mTop, FType);
  mTop := AddLabeled(Self, mFields, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigFieldModifier), mTop, FModifier);
  AddLabeled(Self, mFields, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigFieldValue), mTop, FValue);
  FModifier.Style := csDropDownList;
  FName.OnChange := FieldChange;
  FType.OnChange := FieldChange;
  FModifier.OnChange := FieldChange;
  FValue.OnChange := FieldChange;
end;

procedure TAtlasChangeSignatureDialog.CreateSide;
var
  mRight: TPanel;
  mIndex: Integer;
begin
  mRight := AddPanel(Self, alRight, ScaleValue(120));
  FAdd := AddButton(Self, mRight, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigAdd), AddClick);
  FRemove := AddButton(Self, mRight, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigRemove), RemoveClick);
  FUp := AddButton(Self, mRight, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigUp), UpClick);
  FDown := AddButton(Self, mRight, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigDown), DownClick);
  FAdd.Top := ScaleValue(cGap);
  FRemove.Top := FAdd.Top + FAdd.Height + ScaleValue(4);
  FUp.Top := FRemove.Top + FRemove.Height + ScaleValue(cGap * 2);
  FDown.Top := FUp.Top + FUp.Height + ScaleValue(4);
  for mIndex := 0 to mRight.ControlCount - 1 do
  begin
    mRight.Controls[mIndex].Left := ScaleValue(cGap);
    mRight.Controls[mIndex].Width := mRight.Width - ScaleValue(2 * cGap);
    mRight.Controls[mIndex].Anchors := [akLeft, akTop];
  end;
end;

procedure TAtlasChangeSignatureDialog.DoShow;
begin
  inherited;
  // Liste und Auswahlfeld brauchen ein Fenster: erst hier füllen.
  if FModifier.Items.Count = 0 then
  begin
    FModifier.Items.Add('');
    FModifier.Items.Add('const');
    FModifier.Items.Add('var');
    FModifier.Items.Add('out');
    FModifier.Items.Add('constref');
  end;
  FillList(0);
end;

function TAtlasChangeSignatureDialog.Selected: Integer;
begin
  if FList.Selected = nil then
  begin
    Result := -1;
  end
  else
  begin
    Result := FList.Selected.Index;
  end;
end;

procedure TAtlasChangeSignatureDialog.FillList(ASelect: Integer);
var
  mIndex: Integer;
  mItem: TListItem;
  mRow: TAtlasSignatureRow;
begin
  FUpdating := True;
  try
    FList.Items.BeginUpdate;
    try
      FList.Items.Clear;
      for mIndex := 0 to FModel.Count - 1 do
      begin
        mRow := FModel[mIndex];
        mItem := FList.Items.Add;
        mItem.Caption := mRow.Name;
        mItem.SubItems.Add(mRow.TypeName);
        mItem.SubItems.Add(mRow.Modifier);
        if mRow.IsNew then
        begin
          mItem.SubItems.Add(mRow.Value);
        end
        else if mRow.DefaultValue <> '' then
        begin
          mItem.SubItems.Add('= ' + mRow.DefaultValue);
        end
        else
        begin
          mItem.SubItems.Add('');
        end;
      end;
    finally
      FList.Items.EndUpdate;
    end;
    if (ASelect >= 0) and (ASelect < FList.Items.Count) then
    begin
      FList.Items[ASelect].Selected := True;
    end;
  finally
    FUpdating := False;
  end;
  ShowRow;
  Refresh;
end;

procedure TAtlasChangeSignatureDialog.ShowRow;
var
  mIndex: Integer;
  mRow: TAtlasSignatureRow;
  mHasRow: Boolean;
begin
  mIndex := Selected;
  mHasRow := mIndex >= 0;
  mRow := Default(TAtlasSignatureRow);
  FUpdating := True;
  try
    if mHasRow then
    begin
      mRow := FModel[mIndex];
      FName.Text := mRow.Name;
      FType.Text := mRow.TypeName;
      FModifier.ItemIndex := FModifier.Items.IndexOf(mRow.Modifier);
      FValue.Text := mRow.Value;
      if not mRow.IsNew then
      begin
        FValue.Text := mRow.DefaultValue;
      end;
    end
    else
    begin
      FName.Text := '';
      FType.Text := '';
      FModifier.ItemIndex := -1;
      FValue.Text := '';
    end;
    // Vorhandene Parameter behalten Typ und Modifizierer; nur neue bekommen einen Wert für die Aufrufer.
    FName.Enabled := mHasRow;
    FType.Enabled := mHasRow and mRow.IsNew;
    FModifier.Enabled := mHasRow and mRow.IsNew;
    FValue.Enabled := mHasRow and mRow.IsNew;
    FRemove.Enabled := mHasRow;
    FUp.Enabled := mHasRow and (mIndex > 0);
    FDown.Enabled := mHasRow and (mIndex < FModel.Count - 1);
  finally
    FUpdating := False;
  end;
end;

/// <summary>Meldung zum Fehler der Liste in der Sprache der Oberfläche; '' ohne Fehler.</summary>
function ProblemText(AProblem: TAtlasSignatureProblem; const AName: string): string;
begin
  case AProblem of
    TAtlasSignatureProblem.BadName:
      Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.SigBadName, [AName]);
    TAtlasSignatureProblem.Duplicate:
      Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.SigDuplicate, [AName]);
    TAtlasSignatureProblem.MissingType:
      Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.SigMissingType, [AName]);
    TAtlasSignatureProblem.MissingValue:
      Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.SigMissingValue, [AName]);
    TAtlasSignatureProblem.AfterDefault:
      Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.SigAfterDefault, [AName]);
    TAtlasSignatureProblem.TypesFixed:
      Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.SigTypesFixed, [AName]);
  else
    Result := '';
  end;
end;

procedure TAtlasChangeSignatureDialog.Refresh;
var
  mProblem: TAtlasSignatureProblem;
  mSubject: string;
begin
  FVirtual.Enabled := FOverload.Checked and FOverload.Enabled;
  FPreview.Caption := FModel.Preview;
  mProblem := FModel.Validate(mSubject);
  FError.Caption := ProblemText(mProblem, mSubject);
  FOk.Enabled := (mProblem = TAtlasSignatureProblem.None) and FModel.Changed;
end;

procedure TAtlasChangeSignatureDialog.AddClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := FModel.Add(Selected, TAtlasEditorStrings.Text(TAtlasEditorTextId.SigNewName) + IntToStr(FModel.Count + 1),
    'Integer',
    '', '0');
  FillList(mIndex);
  FName.SetFocus;
  FName.SelectAll;
end;

procedure TAtlasChangeSignatureDialog.RemoveClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := Selected;
  FModel.Remove(mIndex);
  if mIndex >= FModel.Count then
  begin
    mIndex := FModel.Count - 1;
  end;
  FillList(mIndex);
end;

procedure TAtlasChangeSignatureDialog.UpClick(Sender: TObject);
begin
  if FModel.MoveRow(Selected, -1) then
  begin
    FillList(Selected - 1);
  end;
end;

procedure TAtlasChangeSignatureDialog.DownClick(Sender: TObject);
begin
  if FModel.MoveRow(Selected, 1) then
  begin
    FillList(Selected + 1);
  end;
end;

procedure TAtlasChangeSignatureDialog.FieldChange(Sender: TObject);
var
  mIndex: Integer;
  mItem: TListItem;
  mRow: TAtlasSignatureRow;
begin
  if FUpdating then
  begin
    Exit;
  end;
  mIndex := Selected;
  if mIndex < 0 then
  begin
    Exit;
  end;
  FModel.Rename(mIndex, FName.Text);
  FModel.Change(mIndex, FType.Text, FModifier.Text, FValue.Text);
  // Nur die Zeile auffrischen, damit der Fokus im Feld bleibt.
  mRow := FModel[mIndex];
  mItem := FList.Items[mIndex];
  mItem.Caption := mRow.Name;
  mItem.SubItems[0] := mRow.TypeName;
  mItem.SubItems[1] := mRow.Modifier;
  if mRow.IsNew then
  begin
    mItem.SubItems[2] := mRow.Value;
  end;
  Refresh;
end;

procedure TAtlasChangeSignatureDialog.ModeClick(Sender: TObject);
begin
  FModel.UseOverload := FOverload.Checked;
  FModel.VirtualOverload := FVirtual.Checked;
  Refresh;
end;

procedure TAtlasChangeSignatureDialog.ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not FUpdating then
  begin
    ShowRow;
  end;
end;

procedure TAtlasChangeSignatureDialog.OkClick(Sender: TObject);
begin
  if FModel.Validate = TAtlasSignatureProblem.None then
  begin
    ModalResult := mrOk;
  end;
end;

class function TAtlasChangeSignatureDialog.Execute(AModel: TAtlasSignatureModel): Boolean;
var
  mDialog: TAtlasChangeSignatureDialog;
begin
  mDialog := TAtlasChangeSignatureDialog.CreateDialog(nil, AModel);
  try
    Result := mDialog.ShowModal = mrOk;
  finally
    mDialog.Free;
  end;
end;

end.
