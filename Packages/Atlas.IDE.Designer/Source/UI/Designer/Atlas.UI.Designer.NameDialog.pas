unit Atlas.UI.Designer.NameDialog;

// Dialog „Sprechende Namen“ (#608), reine VCL:
//   ☑ Button1   TButton   Beschriftung   btnSpeichern
//   ☑ Edit3     TEdit     Label          edtPlz
//   ☐ Button2   TButton                  –              kein Vorschlag
//   Vorschlag: [btnSpeichern      ]
//   [Letzte Umbenennung rückgängig]            [Übernehmen] [Abbrechen]
// - Haken vorbelegt bei jedem Vorschlag; der Vorschlag der markierten Zeile
//   lässt sich im Feld darunter ändern, ein ungültiger Bezeichner nimmt den
//   Haken weg und steht als Hinweis da.
// - Ergebnis: Übernehmen (mit den Zeilen), Rückgängig oder Abbrechen.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasNameRow = record
    OldName: string;
    ClassName: string;
    SourceText: string;
    NewName: string;
    Note: string;
    Checked: Boolean;
  end;

{$SCOPEDENUMS ON}
  TAtlasNameDialogResult = (Cancel, Apply, Undo);
{$SCOPEDENUMS OFF}

  TAtlasNameDialog = class(TAtlasDialog)
  private
    FRows: TArray<TAtlasNameRow>;
    FList: TListView;
    FEdit: TEdit;
    FUpdating: Boolean;
    procedure AddBottom(ACanUndo: Boolean);
    procedure AddEditBar;
    procedure AddList;
    function AddButton(AParent: TWinControl; const ACaption: string; AResult: TModalResult; AAlign: TAlign): TButton;
    procedure Fill;
    procedure ShowRow(AIndex: Integer);
    procedure ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListChecked(Sender: TObject; Item: TListItem);
    procedure EditChanged(Sender: TObject);
  public
    constructor CreateDialog(AOwner: TComponent; const AFormName: string; const ARows: TArray<TAtlasNameRow>;
      ACanUndo: Boolean);
    /// <summary>Zeigt den Dialog; ARows enthält danach die Haken und Vorschläge. APrepare (darf nil sein) bekommt
    /// das Fenster vor dem Zeigen (Farben der IDE).</summary>
    class function Execute(const AFormName: string; var ARows: TArray<TAtlasNameRow>; ACanUndo: Boolean;
      const APrepare: TProc<TForm>): TAtlasNameDialogResult; static;
  end;

implementation

uses
  System.UITypes,
  Winapi.Windows,
  Atlas.UI.Designer.ViewStrings;

const
  cBasePpi = 96;
  cWidth = 760;
  cHeight = 420;
  cColumnWidths: array[0..4] of Integer = (130, 110, 100, 170, 200);
  cEditWidth = 240;
  cComponentColumn = 0;
  cClassColumn = 1;
  cSourceColumn = 2;
  cProposalColumn = 3;
  cNoteColumn = 4;

/// <summary>Index in TListItem.SubItems zur Spalte AColumn (die erste Spalte ist Caption).</summary>
function SubItemOf(AColumn: Integer): Integer;
begin
  Result := AColumn - 1;
end;

{ TAtlasNameDialog }

constructor TAtlasNameDialog.CreateDialog(AOwner: TComponent; const AFormName: string;
  const ARows: TArray<TAtlasNameRow>; ACanUndo: Boolean);
begin
  inherited CreateDialog(AOwner, '', 0);
  FRows := Copy(ARows);
  Caption := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.NameTitle, [AFormName]);
  BorderStyle := bsSizeToolWin;
  Width := MulDiv(cWidth, CurrentPPI, cBasePpi);
  Height := MulDiv(cHeight, CurrentPPI, cBasePpi);
  AddBottom(ACanUndo);
  AddEditBar;
  AddList;
  Fill;
  FList.OnSelectItem := ListSelect;
  FList.OnItemChecked := ListChecked;
  if FList.Items.Count > 0 then
  begin
    FList.Items[0].Selected := True;
    ShowRow(0);
  end;
end;

/// <summary>Knöpfe unten: Rückgängig links, Übernehmen und Abbrechen rechts.</summary>
procedure TAtlasNameDialog.AddBottom(ACanUndo: Boolean);
var
  mBottom: TPanel;
  mUndo: TButton;
begin
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.BevelOuter := bvNone;
  mBottom.AutoSize := True;
  mUndo := AddButton(mBottom, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameUndo), mrRetry, alLeft);
  mUndo.Width := MulDiv(cEditWidth, CurrentPPI, cBasePpi);
  mUndo.Enabled := ACanUndo;
  AddButton(mBottom, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameCancel), mrCancel,
    alRight).Cancel := True;
  AddButton(mBottom, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameApply), mrOk, alRight).Default :=
    True;
end;

/// <summary>Feld für den Vorschlag der markierten Zeile.</summary>
procedure TAtlasNameDialog.AddEditBar;
var
  mEditBar: TPanel;
  mLabel: TLabel;
begin
  mEditBar := TPanel.Create(Self);
  mEditBar.Parent := Self;
  mEditBar.Align := alBottom;
  mEditBar.BevelOuter := bvNone;
  mEditBar.AutoSize := True;
  mLabel := TLabel.Create(Self);
  mLabel.Parent := mEditBar;
  mLabel.Align := alLeft;
  mLabel.Layout := tlCenter;
  mLabel.AlignWithMargins := True;
  mLabel.Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameEdit);
  FEdit := TEdit.Create(Self);
  FEdit.Parent := mEditBar;
  FEdit.Align := alLeft;
  FEdit.AlignWithMargins := True;
  FEdit.Width := MulDiv(cEditWidth, CurrentPPI, cBasePpi);
  FEdit.OnChange := EditChanged;
end;

procedure TAtlasNameDialog.AddList;
var
  mIndex: Integer;
begin
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.Checkboxes := True;
  FList.RowSelect := True;
  FList.ReadOnly := True;
  FList.HideSelection := False;
  for mIndex := 0 to High(cColumnWidths) do
  begin
    FList.Columns.Add.Width := MulDiv(cColumnWidths[mIndex], CurrentPPI, cBasePpi);
  end;
  FList.Columns[cComponentColumn].Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameColComponent);
  FList.Columns[cClassColumn].Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameColClass);
  FList.Columns[cSourceColumn].Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameColSource);
  FList.Columns[cProposalColumn].Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameColProposal);
  FList.Columns[cNoteColumn].Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameColNote);
end;

function TAtlasNameDialog.AddButton(AParent: TWinControl; const ACaption: string; AResult: TModalResult;
  AAlign: TAlign): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.ModalResult := AResult;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
end;

procedure TAtlasNameDialog.Fill;
var
  mRow: TAtlasNameRow;
  mItem: TListItem;
begin
  FUpdating := True;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mRow in FRows do
    begin
      mItem := FList.Items.Add;
      mItem.Caption := mRow.OldName;
      mItem.SubItems.Add(mRow.ClassName);
      mItem.SubItems.Add(mRow.SourceText);
      mItem.SubItems.Add(mRow.NewName);
      mItem.SubItems.Add(mRow.Note);
      mItem.Checked := mRow.Checked;
    end;
  finally
    FList.Items.EndUpdate;
    FUpdating := False;
  end;
end;

procedure TAtlasNameDialog.ShowRow(AIndex: Integer);
begin
  FUpdating := True;
  try
    FEdit.Enabled := (AIndex >= 0) and (AIndex <= High(FRows));
    if FEdit.Enabled then
    begin
      FEdit.Text := FRows[AIndex].NewName;
    end
    else
    begin
      FEdit.Text := '';
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasNameDialog.ListSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if Selected and (Item <> nil) then
  begin
    ShowRow(Item.Index);
  end;
end;

procedure TAtlasNameDialog.ListChecked(Sender: TObject; Item: TListItem);
begin
  if FUpdating or (Item = nil) or (Item.Index > High(FRows)) then
  begin
    Exit;
  end;
  // Ohne gültigen Namen bleibt der Haken aus.
  FRows[Item.Index].Checked := Item.Checked and IsValidIdent(FRows[Item.Index].NewName);
  if Item.Checked <> FRows[Item.Index].Checked then
  begin
    FUpdating := True;
    try
      Item.Checked := FRows[Item.Index].Checked;
    finally
      FUpdating := False;
    end;
  end;
end;

procedure TAtlasNameDialog.EditChanged(Sender: TObject);
var
  mItem: TListItem;
  mRow: Integer;
begin
  mItem := FList.Selected;
  if FUpdating or (mItem = nil) or (mItem.Index > High(FRows)) then
  begin
    Exit;
  end;
  mRow := mItem.Index;
  FRows[mRow].NewName := Trim(FEdit.Text);
  FRows[mRow].Checked := IsValidIdent(FRows[mRow].NewName);
  if not FRows[mRow].Checked then
  begin
    FRows[mRow].Note := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameInvalid);
  end
  else if FRows[mRow].Note = TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NameInvalid) then
  begin
    FRows[mRow].Note := '';
  end;
  FUpdating := True;
  try
    mItem.SubItems[SubItemOf(cProposalColumn)] := FRows[mRow].NewName;
    mItem.SubItems[SubItemOf(cNoteColumn)] := FRows[mRow].Note;
    mItem.Checked := FRows[mRow].Checked;
  finally
    FUpdating := False;
  end;
end;

class function TAtlasNameDialog.Execute(const AFormName: string; var ARows: TArray<TAtlasNameRow>; ACanUndo: Boolean;
  const APrepare: TProc<TForm>): TAtlasNameDialogResult;
var
  mDialog: TAtlasNameDialog;
begin
  Result := TAtlasNameDialogResult.Cancel;
  mDialog := TAtlasNameDialog.CreateDialog(nil, AFormName, ARows, ACanUndo);
  try
    if Assigned(APrepare) then
    begin
      APrepare(mDialog);
    end;
    case mDialog.ShowModal of
      mrOk:
        begin
          ARows := mDialog.FRows;
          Result := TAtlasNameDialogResult.Apply;
        end;
      mrRetry:
        Result := TAtlasNameDialogResult.Undo;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
