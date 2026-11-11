unit Atlas.UI.Designer.AnchorDialog;

// Dialog „Anchors vorschlagen“ (#727), reine VCL: eine Zeile je Komponente
// mit Häkchen, Name, vorgeschlagenen Anchors („L T R B“) und Grund.
//   [x] btnOk      - - R B   unten rechts am Rand
//   [ ] pnlBottom  L T R -   durch Align geregelt
//                                       [Übernehmen] [Abbrechen]
// Nur Zeilen mit Änderung lassen sich abhaken; ein Klick auf eine Zeile meldet
// den Namen (Auswahl im Designer). Enter übernimmt, Esc verwirft.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls;

type
  TAtlasAnchorRow = record
    Name: string;
    Anchors: string;
    Reason: string;
    /// <summary>Angeboten (Änderung); sonst nur zur Anzeige.</summary>
    Offered: Boolean;
  end;

  TAtlasAnchorDialog = class(TForm)
  public const
    cDialogWidth = 480;
    cListHeight = 320;
  private
    FRows: TArray<TAtlasAnchorRow>;
    FList: TListView;
    FOnSelect: TProc<string>;
    procedure ListClick(Sender: TObject);
    procedure ListItemChecked(Sender: TObject; AItem: TListItem);
    procedure AddButtons;
  public
    constructor CreateDialog(AOwner: TComponent; const ARows: TArray<TAtlasAnchorRow>;
      const AOnSelect: TProc<string>);
    function Checked: TArray<Boolean>;
    /// <summary>Modal zeigen; True nach „Übernehmen“, AChecked dann mit den Häkchen.</summary>
    class function Execute(const ARows: TArray<TAtlasAnchorRow>; const AOnSelect: TProc<string>;
      out AChecked: TArray<Boolean>): Boolean; static;
    property List: TListView read FList;
  end;

implementation

uses
  Atlas.UI.Designer.Strings;

const
  cGap = 10;
  cNameWidth = 140;
  cAnchorsWidth = 80;

{ TAtlasAnchorDialog }

constructor TAtlasAnchorDialog.CreateDialog(AOwner: TComponent; const ARows: TArray<TAtlasAnchorRow>;
  const AOnSelect: TProc<string>);
var
  mRow: TAtlasAnchorRow;
  mItem: TListItem;
  mColumn: TListColumn;
begin
  inherited CreateNew(AOwner);
  FRows := ARows;
  FOnSelect := AOnSelect;
  Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAnchorsTitle);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alTop;
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(cGap, cGap, cGap, 0);
  FList.Height := ScaleValue(cListHeight);
  FList.ViewStyle := vsReport;
  FList.Checkboxes := True;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  mColumn := FList.Columns.Add;
  mColumn.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAnchorsName);
  mColumn.Width := ScaleValue(cNameWidth);
  mColumn := FList.Columns.Add;
  mColumn.Caption := 'Anchors';
  mColumn.Width := ScaleValue(cAnchorsWidth);
  mColumn := FList.Columns.Add;
  mColumn.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAnchorsReason);
  mColumn.AutoSize := True;
  for mRow in ARows do
  begin
    mItem := FList.Items.Add;
    mItem.Caption := mRow.Name;
    mItem.SubItems.Add(mRow.Anchors);
    mItem.SubItems.Add(mRow.Reason);
    mItem.Checked := mRow.Offered;
  end;
  FList.OnClick := ListClick;
  FList.OnItemChecked := ListItemChecked;
  AddButtons;
  ActiveControl := FList;
end;

procedure TAtlasAnchorDialog.ListClick(Sender: TObject);
begin
  if (FList.Selected <> nil) and Assigned(FOnSelect) then
  begin
    FOnSelect(FList.Selected.Caption);
  end;
end;

procedure TAtlasAnchorDialog.ListItemChecked(Sender: TObject; AItem: TListItem);
begin
  // Nur Änderungen lassen sich abhaken; Align und vorhandene Anchors bleiben ohne Häkchen.
  if (AItem.Index <= High(FRows)) and not FRows[AItem.Index].Offered and AItem.Checked then
  begin
    AItem.Checked := False;
  end;
end;

procedure TAtlasAnchorDialog.AddButtons;
var
  mButtons: TFlowPanel;
  mButton: TButton;
begin
  mButtons := TFlowPanel.Create(Self);
  mButtons.Parent := Self;
  mButtons.Align := alTop;
  mButtons.AutoSize := True;
  mButtons.BevelOuter := bvNone;
  mButtons.AlignWithMargins := True;
  mButtons.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mButtons.Top := FList.Top + FList.Height + 1;
  mButton := TButton.Create(Self);
  mButton.Parent := mButtons;
  mButton.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAnchorsApply);
  mButton.Default := True;
  mButton.ModalResult := mrOk;
  mButton.AlignWithMargins := True;
  mButton.Margins.SetBounds(0, 0, cGap, 0);
  mButton := TButton.Create(Self);
  mButton.Parent := mButtons;
  mButton.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateCancel);
  mButton.Cancel := True;
  mButton.ModalResult := mrCancel;
  ClientHeight := mButtons.Top + mButtons.Height + ScaleValue(cGap);
end;

function TAtlasAnchorDialog.Checked: TArray<Boolean>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, FList.Items.Count);
  for mIndex := 0 to FList.Items.Count - 1 do
  begin
    Result[mIndex] := FList.Items[mIndex].Checked and (mIndex <= High(FRows)) and FRows[mIndex].Offered;
  end;
end;

class function TAtlasAnchorDialog.Execute(const ARows: TArray<TAtlasAnchorRow>; const AOnSelect: TProc<string>;
  out AChecked: TArray<Boolean>): Boolean;
var
  mDialog: TAtlasAnchorDialog;
begin
  mDialog := TAtlasAnchorDialog.CreateDialog(nil, ARows, AOnSelect);
  try
    Result := mDialog.ShowModal = mrOk;
    AChecked := mDialog.Checked;
  finally
    mDialog.Free;
  end;
end;

end.
