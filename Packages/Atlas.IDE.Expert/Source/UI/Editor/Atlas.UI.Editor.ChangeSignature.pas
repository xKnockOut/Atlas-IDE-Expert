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
    function AddButton(AParent: TWinControl; const ACaption: string; AClick: TNotifyEvent): TButton;
    function AddLabeled(AParent: TWinControl; const ACaption: string; ATop: Integer; AControl: TWinControl): Integer;
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
  Atlas.UI.Strings;

const
  Gap = 8;
  DialogWidth = 640;
  DialogHeight = 520;

{ TAtlasChangeSignatureDialog }

constructor TAtlasChangeSignatureDialog.CreateDialog(AOwner: TComponent; AModel: TAtlasSignatureModel);
var
  Bottom, Right, Fields, Options: TPanel;
  Column: TListColumn;
  mTop: Integer;
  Notes: string;
  Warning: string;
begin
  inherited CreateNew(AOwner);
  FModel := AModel;
  Caption := TAtlasStrings.Fmt(TAtlasTextId.SigTitle, [AModel.Name]);
  BorderStyle := bsSizeable;
  BorderIcons := [biSystemMenu];
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(DialogWidth);
  ClientHeight := ScaleValue(DialogHeight);

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := ScaleValue(44);
  Bottom.BevelOuter := bvNone;
  FCancel := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.SigCancel), nil);
  FCancel.Cancel := True;
  FCancel.ModalResult := mrCancel;
  FCancel.Left := Bottom.ClientWidth - FCancel.Width - ScaleValue(Gap);
  FOk := AddButton(Bottom, TAtlasStrings.Text(TAtlasTextId.SigPreviewButton), OkClick);
  FOk.Default := True;
  FOk.Left := FCancel.Left - FOk.Width - ScaleValue(Gap);

  // Hinweise, Fehler und Vorschau über den Knöpfen.
  FNotes := TLabel.Create(Self);
  FNotes.Parent := Self;
  FNotes.Align := alBottom;
  FNotes.AlignWithMargins := True;
  FNotes.Margins.SetBounds(Gap, 0, Gap, Gap div 2);
  FNotes.WordWrap := True;
  FNotes.ShowAccelChar := False;
  Notes := '';
  if AModel.EventFixed then
    Notes := TAtlasStrings.Fmt(TAtlasTextId.SigEventFixed, [AModel.BoundEvent]);
  for Warning in AModel.Warnings do
  begin
    if Notes <> '' then
      Notes := Notes + sLineBreak;
    Notes := Notes + TAtlasStrings.Fmt(TAtlasTextId.SigWarning, [Warning]);
  end;
  FNotes.Caption := Notes;
  FError := TLabel.Create(Self);
  FError.Parent := Self;
  FError.Align := alBottom;
  FError.AlignWithMargins := True;
  FError.Margins.SetBounds(Gap, 0, Gap, Gap div 2);
  FError.WordWrap := True;
  FError.ShowAccelChar := False;
  FError.Font.Color := clRed;
  FPreview := TLabel.Create(Self);
  FPreview.Parent := Self;
  FPreview.Align := alBottom;
  FPreview.AlignWithMargins := True;
  FPreview.Margins.SetBounds(Gap, Gap div 2, Gap, Gap div 2);
  FPreview.WordWrap := True;
  FPreview.ShowAccelChar := False;
  FPreview.Font.Name := 'Consolas';

  Options := TPanel.Create(Self);
  Options.Parent := Self;
  Options.Align := alBottom;
  Options.Height := ScaleValue(72);
  Options.BevelOuter := bvNone;
  FOverload := TRadioButton.Create(Self);
  FOverload.Parent := Options;
  FOverload.SetBounds(ScaleValue(Gap), ScaleValue(4), ScaleValue(DialogWidth - 2 * Gap), ScaleValue(20));
  FOverload.Caption := TAtlasStrings.Text(TAtlasTextId.SigModeOverload);
  FOverload.OnClick := ModeClick;
  FCallers := TRadioButton.Create(Self);
  FCallers.Parent := Options;
  FCallers.SetBounds(ScaleValue(Gap), ScaleValue(26), ScaleValue(DialogWidth - 2 * Gap), ScaleValue(20));
  FCallers.Caption := TAtlasStrings.Text(TAtlasTextId.SigModeCallers);
  FCallers.OnClick := ModeClick;
  FVirtual := TCheckBox.Create(Self);
  FVirtual.Parent := Options;
  FVirtual.SetBounds(ScaleValue(Gap + 16), ScaleValue(48), ScaleValue(DialogWidth - 2 * Gap - 16), ScaleValue(20));
  FVirtual.Caption := TAtlasStrings.Text(TAtlasTextId.SigVirtual);
  FVirtual.Checked := AModel.VirtualOverload;
  FVirtual.OnClick := ModeClick;
  if not AModel.OverloadPossible then
  begin
    FOverload.Enabled := False;
    FOverload.Caption := FOverload.Caption + ' – ' + TAtlasStrings.Text(TAtlasTextId.SigModeForced);
  end;
  FOverload.Checked := AModel.UseOverload;
  FCallers.Checked := not AModel.UseOverload;

  // Felder der gewählten Zeile.
  Fields := TPanel.Create(Self);
  Fields.Parent := Self;
  Fields.Align := alBottom;
  Fields.Height := ScaleValue(118);
  Fields.BevelOuter := bvNone;
  FName := TEdit.Create(Self);
  FType := TEdit.Create(Self);
  FModifier := TComboBox.Create(Self);
  FValue := TEdit.Create(Self);
  mTop := ScaleValue(4);
  mTop := AddLabeled(Fields, TAtlasStrings.Text(TAtlasTextId.SigFieldName), mTop, FName);
  mTop := AddLabeled(Fields, TAtlasStrings.Text(TAtlasTextId.SigFieldType), mTop, FType);
  mTop := AddLabeled(Fields, TAtlasStrings.Text(TAtlasTextId.SigFieldModifier), mTop, FModifier);
  AddLabeled(Fields, TAtlasStrings.Text(TAtlasTextId.SigFieldValue), mTop, FValue);
  FModifier.Style := csDropDownList;
  FName.OnChange := FieldChange;
  FType.OnChange := FieldChange;
  FModifier.OnChange := FieldChange;
  FValue.OnChange := FieldChange;

  // Knöpfe rechts neben der Liste.
  Right := TPanel.Create(Self);
  Right.Parent := Self;
  Right.Align := alRight;
  Right.Width := ScaleValue(120);
  Right.BevelOuter := bvNone;
  FAdd := AddButton(Right, TAtlasStrings.Text(TAtlasTextId.SigAdd), AddClick);
  FRemove := AddButton(Right, TAtlasStrings.Text(TAtlasTextId.SigRemove), RemoveClick);
  FUp := AddButton(Right, TAtlasStrings.Text(TAtlasTextId.SigUp), UpClick);
  FDown := AddButton(Right, TAtlasStrings.Text(TAtlasTextId.SigDown), DownClick);
  FAdd.Top := ScaleValue(Gap);
  FRemove.Top := FAdd.Top + FAdd.Height + ScaleValue(4);
  FUp.Top := FRemove.Top + FRemove.Height + ScaleValue(Gap * 2);
  FDown.Top := FUp.Top + FUp.Height + ScaleValue(4);
  for mTop := 0 to Right.ControlCount - 1 do
  begin
    Right.Controls[mTop].Left := ScaleValue(Gap);
    Right.Controls[mTop].Width := Right.Width - ScaleValue(2 * Gap);
    Right.Controls[mTop].Anchors := [akLeft, akTop];
  end;

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(Gap, Gap, 0, 0);
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.OnSelectItem := ListSelect;
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.SigColName);
  Column.Width := ScaleValue(130);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.SigColType);
  Column.Width := ScaleValue(140);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.SigColModifier);
  Column.Width := ScaleValue(80);
  Column := FList.Columns.Add;
  Column.Caption := TAtlasStrings.Text(TAtlasTextId.SigColValue);
  Column.Width := ScaleValue(140);
  ActiveControl := FList;
end;

function TAtlasChangeSignatureDialog.AddButton(AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Result.Width := ScaleValue(100);
  Result.Top := ScaleValue(Gap);
  Result.Height := ScaleValue(28);
  Result.Anchors := [akTop, akRight];
end;

function TAtlasChangeSignatureDialog.AddLabeled(AParent: TWinControl; const ACaption: string; ATop: Integer;
  AControl: TWinControl): Integer;
var
  mCaption: TLabel;
begin
  mCaption := TLabel.Create(Self);
  mCaption.Parent := AParent;
  mCaption.Caption := ACaption;
  mCaption.SetBounds(ScaleValue(Gap), ATop + ScaleValue(3), ScaleValue(190), ScaleValue(20));
  mCaption.FocusControl := AControl;
  AControl.Parent := AParent;
  AControl.SetBounds(ScaleValue(200), ATop, ScaleValue(DialogWidth - 200 - Gap), ScaleValue(23));
  AControl.Anchors := [akLeft, akTop, akRight];
  Result := ATop + ScaleValue(28);
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
    Result := -1
  else
    Result := FList.Selected.Index;
end;

procedure TAtlasChangeSignatureDialog.FillList(ASelect: Integer);
var
  Index: Integer;
  Item: TListItem;
  Row: TAtlasSignatureRow;
begin
  FUpdating := True;
  try
    FList.Items.BeginUpdate;
    try
      FList.Items.Clear;
      for Index := 0 to FModel.Count - 1 do
      begin
        Row := FModel[Index];
        Item := FList.Items.Add;
        Item.Caption := Row.Name;
        Item.SubItems.Add(Row.TypeName);
        Item.SubItems.Add(Row.Modifier);
        if Row.IsNew then
          Item.SubItems.Add(Row.Value)
        else if Row.DefaultValue <> '' then
          Item.SubItems.Add('= ' + Row.DefaultValue)
        else
          Item.SubItems.Add('');
      end;
    finally
      FList.Items.EndUpdate;
    end;
    if (ASelect >= 0) and (ASelect < FList.Items.Count) then
      FList.Items[ASelect].Selected := True;
  finally
    FUpdating := False;
  end;
  ShowRow;
  Refresh;
end;

procedure TAtlasChangeSignatureDialog.ShowRow;
var
  Index: Integer;
  Row: TAtlasSignatureRow;
  HasRow: Boolean;
begin
  Index := Selected;
  HasRow := Index >= 0;
  Row := Default(TAtlasSignatureRow);
  FUpdating := True;
  try
    if HasRow then
    begin
      Row := FModel[Index];
      FName.Text := Row.Name;
      FType.Text := Row.TypeName;
      FModifier.ItemIndex := FModifier.Items.IndexOf(Row.Modifier);
      FValue.Text := Row.Value;
      if not Row.IsNew then
        FValue.Text := Row.DefaultValue;
    end
    else
    begin
      FName.Text := '';
      FType.Text := '';
      FModifier.ItemIndex := -1;
      FValue.Text := '';
    end;
    // Vorhandene Parameter behalten Typ und Modifizierer; nur neue bekommen einen Wert für die Aufrufer.
    FName.Enabled := HasRow;
    FType.Enabled := HasRow and Row.IsNew;
    FModifier.Enabled := HasRow and Row.IsNew;
    FValue.Enabled := HasRow and Row.IsNew;
    FRemove.Enabled := HasRow;
    FUp.Enabled := HasRow and (Index > 0);
    FDown.Enabled := HasRow and (Index < FModel.Count - 1);
  finally
    FUpdating := False;
  end;
end;

/// <summary>Meldung zum Fehler der Liste in der Sprache der Oberfläche; '' ohne Fehler.</summary>
function ProblemText(AProblem: TAtlasSignatureProblem; const AName: string): string;
begin
  case AProblem of
    TAtlasSignatureProblem.BadName:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SigBadName, [AName]);
    TAtlasSignatureProblem.Duplicate:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SigDuplicate, [AName]);
    TAtlasSignatureProblem.MissingType:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SigMissingType, [AName]);
    TAtlasSignatureProblem.MissingValue:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SigMissingValue, [AName]);
    TAtlasSignatureProblem.AfterDefault:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SigAfterDefault, [AName]);
    TAtlasSignatureProblem.TypesFixed:
      Result := TAtlasStrings.Fmt(TAtlasTextId.SigTypesFixed, [AName]);
  else
    Result := '';
  end;
end;

procedure TAtlasChangeSignatureDialog.Refresh;
var
  Problem: TAtlasSignatureProblem;
  Subject: string;
begin
  FVirtual.Enabled := FOverload.Checked and FOverload.Enabled;
  FPreview.Caption := FModel.Preview;
  Problem := FModel.Validate(Subject);
  FError.Caption := ProblemText(Problem, Subject);
  FOk.Enabled := (Problem = TAtlasSignatureProblem.None) and FModel.Changed;
end;

procedure TAtlasChangeSignatureDialog.AddClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := FModel.Add(Selected, TAtlasStrings.Text(TAtlasTextId.SigNewName) + IntToStr(FModel.Count + 1), 'Integer',
    '', '0');
  FillList(Index);
  FName.SetFocus;
  FName.SelectAll;
end;

procedure TAtlasChangeSignatureDialog.RemoveClick(Sender: TObject);
var
  Index: Integer;
begin
  Index := Selected;
  FModel.Remove(Index);
  if Index >= FModel.Count then
    Index := FModel.Count - 1;
  FillList(Index);
end;

procedure TAtlasChangeSignatureDialog.UpClick(Sender: TObject);
begin
  if FModel.MoveRow(Selected, -1) then
    FillList(Selected - 1);
end;

procedure TAtlasChangeSignatureDialog.DownClick(Sender: TObject);
begin
  if FModel.MoveRow(Selected, 1) then
    FillList(Selected + 1);
end;

procedure TAtlasChangeSignatureDialog.FieldChange(Sender: TObject);
var
  Index: Integer;
  Item: TListItem;
  Row: TAtlasSignatureRow;
begin
  if FUpdating then
    Exit;
  Index := Selected;
  if Index < 0 then
    Exit;
  FModel.Rename(Index, FName.Text);
  FModel.Change(Index, FType.Text, FModifier.Text, FValue.Text);
  // Nur die Zeile auffrischen, damit der Fokus im Feld bleibt.
  Row := FModel[Index];
  Item := FList.Items[Index];
  Item.Caption := Row.Name;
  Item.SubItems[0] := Row.TypeName;
  Item.SubItems[1] := Row.Modifier;
  if Row.IsNew then
    Item.SubItems[2] := Row.Value;
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
    ShowRow;
end;

procedure TAtlasChangeSignatureDialog.OkClick(Sender: TObject);
begin
  if FModel.Validate = TAtlasSignatureProblem.None then
    ModalResult := mrOk;
end;

class function TAtlasChangeSignatureDialog.Execute(AModel: TAtlasSignatureModel): Boolean;
var
  Dialog: TAtlasChangeSignatureDialog;
begin
  Dialog := TAtlasChangeSignatureDialog.CreateDialog(nil, AModel);
  try
    Result := Dialog.ShowModal = mrOk;
  finally
    Dialog.Free;
  end;
end;

end.
