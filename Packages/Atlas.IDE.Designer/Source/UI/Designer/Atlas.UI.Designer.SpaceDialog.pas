unit Atlas.UI.Designer.SpaceDialog;

// Dialog „Platz einfügen“ bzw. „Platz entfernen“ (#740), reine VCL:
//   (o) Zeilen: an der Oberkante der Auswahl
//   ( ) Spalten: an der linken Kante der Auswahl
//   Betrag (px): [30 ]
//   [x] Am Raster des Designers einrasten
//                                       [OK] [Abbrechen]
// Enter bestätigt, Esc verwirft. Den Betrag begrenzt und rechnet
// TAtlasInsertSpace in der IDE-Schicht.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Designer.InsertSpace;

type
  TAtlasSpaceOptions = record
    Axis: TAtlasSpaceAxis;
    Amount: Integer;
    Snap: Boolean;
  end;

  TAtlasSpaceDialog = class(TForm)
  public const
    cDialogWidth = 360;
    cMaxAmount = 2000;
  private
    FRows: TRadioButton;
    FColumns: TRadioButton;
    FAmount: TEdit;
    FSnap: TCheckBox;
    function AddRow: TFlowPanel;
    function AddRadio(AParent: TWinControl; const ACaption: string; ATop: Integer): TRadioButton;
    procedure AddButtons;
  public
    /// <summary>ARemove: Titel „Platz entfernen“.</summary>
    constructor CreateDialog(AOwner: TComponent; ARemove: Boolean; const AOptions: TAtlasSpaceOptions);
    function Options: TAtlasSpaceOptions;
    /// <summary>Modal zeigen; True nach OK mit den gewählten Optionen.</summary>
    class function Execute(ARemove: Boolean; var AOptions: TAtlasSpaceOptions): Boolean; static;
    property RowsRadio: TRadioButton read FRows;
    property ColumnsRadio: TRadioButton read FColumns;
    property AmountEdit: TEdit read FAmount;
    property SnapCheck: TCheckBox read FSnap;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Designer.Strings;

const
  cGap = 10;
  cNumberWidth = 56;
  cRadioHeight = 22;

{ TAtlasSpaceDialog }

constructor TAtlasSpaceDialog.CreateDialog(AOwner: TComponent; ARemove: Boolean; const AOptions: TAtlasSpaceOptions);
var
  mRow: TFlowPanel;
  mGroup: TPanel;
  mLabel: TLabel;
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceInsertTitle);
  if ARemove then
  begin
    Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceRemoveTitle);
  end;
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);
  Canvas.Font := Font;

  // Beide Optionen in einem Container, damit sie sich gegenseitig ausschließen.
  mGroup := TPanel.Create(Self);
  mGroup.Parent := Self;
  mGroup.Align := alTop;
  mGroup.BevelOuter := bvNone;
  mGroup.AlignWithMargins := True;
  mGroup.Margins.SetBounds(cGap, cGap, cGap, 0);
  mGroup.Height := ScaleValue(cRadioHeight * 2);
  FRows := AddRadio(mGroup, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceRows), 0);
  FColumns := AddRadio(mGroup, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceColumns),
    ScaleValue(cRadioHeight));
  mRow := AddRow;
  mLabel := TLabel.Create(Self);
  mLabel.Parent := mRow;
  mLabel.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceAmount);
  mLabel.AlignWithMargins := True;
  mLabel.Margins.SetBounds(0, ScaleValue(3), cGap div 2, 0);
  FAmount := TEdit.Create(Self);
  FAmount.Parent := mRow;
  FAmount.Width := ScaleValue(cNumberWidth);
  FAmount.NumbersOnly := True;
  mRow := AddRow;
  FSnap := TCheckBox.Create(Self);
  FSnap.Parent := mRow;
  FSnap.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceSnap);
  FSnap.Width := Canvas.TextWidth(FSnap.Caption) + ScaleValue(24);
  AddButtons;

  FRows.Checked := AOptions.Axis = TAtlasSpaceAxis.Rows;
  FColumns.Checked := AOptions.Axis = TAtlasSpaceAxis.Columns;
  FAmount.Text := IntToStr(AOptions.Amount);
  FSnap.Checked := AOptions.Snap;
  ActiveControl := FAmount;
end;

function TAtlasSpaceDialog.AddRow: TFlowPanel;
begin
  Result := TFlowPanel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.AutoSize := True;
  Result.BevelOuter := bvNone;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(cGap, cGap div 2, cGap, 0);
  // Hinter alle bisherigen Zeilen (alTop ordnet nach Top).
  Result.Top := ScaleValue(2000) + ComponentCount;
end;

function TAtlasSpaceDialog.AddRadio(AParent: TWinControl; const ACaption: string; ATop: Integer): TRadioButton;
begin
  Result := TRadioButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.SetBounds(0, ATop, Canvas.TextWidth(ACaption) + ScaleValue(24), ScaleValue(cRadioHeight - 2));
end;

procedure TAtlasSpaceDialog.AddButtons;
var
  mButtons: TFlowPanel;
  mButton: TButton;
begin
  mButtons := AddRow;
  mButtons.Margins.SetBounds(cGap, cGap, cGap, cGap);
  mButton := TButton.Create(Self);
  mButton.Parent := mButtons;
  mButton.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceOk);
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

function TAtlasSpaceDialog.Options: TAtlasSpaceOptions;
begin
  Result.Axis := TAtlasSpaceAxis.Rows;
  if FColumns.Checked then
  begin
    Result.Axis := TAtlasSpaceAxis.Columns;
  end;
  Result.Amount := EnsureRange(StrToIntDef(FAmount.Text, 0), 0, cMaxAmount);
  Result.Snap := FSnap.Checked;
end;

class function TAtlasSpaceDialog.Execute(ARemove: Boolean; var AOptions: TAtlasSpaceOptions): Boolean;
var
  mDialog: TAtlasSpaceDialog;
begin
  mDialog := TAtlasSpaceDialog.CreateDialog(nil, ARemove, AOptions);
  try
    Result := mDialog.ShowModal = mrOk;
    AOptions := mDialog.Options;
  finally
    mDialog.Free;
  end;
end;

end.
