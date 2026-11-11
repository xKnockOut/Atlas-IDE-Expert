unit Atlas.UI.Designer.DuplicateDialog;

// Dialog „In Reihe duplizieren“ (#736), reine VCL:
//   Richtung:  [Nach unten  v]    Abstand (px): [8 ]    Anzahl: [3 ]
//   Namensliste, ergibt die Anzahl (z. B. Fax, Mobil, Privat):
//   [Fax, Mobil, Privat                         ]
//   [x] Ereignis-Handler teilen   [ ] DataField aus der Liste setzen
//   [ ] Nachfolgende Steuerelemente verschieben
//   Kopien: lblFax, edtFax; lblMobil, edtMobil …
//                                          [Anlegen] [Abbrechen]
// Jede Änderung meldet OnChange mit den aktuellen Optionen; der Aufrufer
// zeichnet damit die Vorschau im Designer und gibt die Zeile „Kopien: …“
// samt Überlauf über SetPreview zurück. Enter legt an, Esc verwirft.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Designer.DuplicateRow;

type
  TAtlasDuplicateOptions = record
    Direction: TAtlasDuplicateDirection;
    Gap: Integer;
    Count: Integer;
    List: string;
    ShareEvents: Boolean;
    DataFields: Boolean;
    Push: Boolean;
  end;

  TAtlasDuplicateDialog = class(TForm)
  public const
    cDialogWidth = 480;
    cMaxCount = 99;
  private
    FDirection: TComboBox;
    FGap: TEdit;
    FCount: TEdit;
    FList: TEdit;
    FShare: TCheckBox;
    FDataFields: TCheckBox;
    FPush: TCheckBox;
    FPreview: TLabel;
    FBad: TLabel;
    FOk: TButton;
    FCancel: TButton;
    FLoading: Boolean;
    FOnChange: TProc<TAtlasDuplicateOptions>;
    function AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
    function AddEdit(AParent: TWinControl; AWidth: Integer; ANumbers: Boolean): TEdit;
    function AddCheck(AParent: TWinControl; const ACaption: string): TCheckBox;
    function AddRow: TFlowPanel;
    procedure AddButtons;
    procedure Changed(Sender: TObject);
    procedure Load(const AOptions: TAtlasDuplicateOptions);
  public
    constructor CreateDialog(AOwner: TComponent; const AOptions: TAtlasDuplicateOptions);
    function Options: TAtlasDuplicateOptions;
    /// <summary>Zeile unter den Optionen; ABad zeigt den Hinweis auf rote Umrisse.</summary>
    procedure SetPreview(const AText: string; ABad: Boolean);
    /// <summary>Modal zeigen; True nach „Anlegen“ mit den gewählten Optionen.</summary>
    class function Execute(var AOptions: TAtlasDuplicateOptions;
      const AOnChange: TProc<TAtlasDuplicateOptions, TAtlasDuplicateDialog>): Boolean; static;
    property OnChange: TProc<TAtlasDuplicateOptions> read FOnChange write FOnChange;
    property DirectionBox: TComboBox read FDirection;
    property GapEdit: TEdit read FGap;
    property CountEdit: TEdit read FCount;
    property ListEdit: TEdit read FList;
    property ShareCheck: TCheckBox read FShare;
    property DataFieldCheck: TCheckBox read FDataFields;
    property PushCheck: TCheckBox read FPush;
    property PreviewLabel: TLabel read FPreview;
    property BadLabel: TLabel read FBad;
  end;

implementation

uses
  System.Math,
  Vcl.Graphics,
  Atlas.UI.Designer.Strings;

const
  cGap = 10;
  cNumberWidth = 48;

{ TAtlasDuplicateDialog }

constructor TAtlasDuplicateDialog.CreateDialog(AOwner: TComponent; const AOptions: TAtlasDuplicateOptions);
var
  mRow: TFlowPanel;
begin
  inherited CreateNew(AOwner);
  Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateTitle);
  BorderStyle := bsDialog;
  Position := poMainFormCenter;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  ClientWidth := ScaleValue(cDialogWidth);
  Canvas.Font := Font;

  mRow := AddRow;
  AddLabel(mRow, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateDirection));
  FDirection := TComboBox.Create(Self);
  FDirection.Parent := mRow;
  FDirection.Style := csDropDownList;
  FDirection.Width := ScaleValue(110);
  FDirection.AlignWithMargins := True;
  FDirection.Margins.SetBounds(0, 0, cGap * 2, 0);
  FDirection.Items.Add(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateDown));
  FDirection.Items.Add(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateRight));
  AddLabel(mRow, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateGap));
  FGap := AddEdit(mRow, cNumberWidth, True);
  FGap.Margins.Right := cGap * 2;
  AddLabel(mRow, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateCount));
  FCount := AddEdit(mRow, cNumberWidth, True);

  mRow := AddRow;
  AddLabel(mRow, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateList));
  mRow := AddRow;
  FList := AddEdit(mRow, cDialogWidth - cGap * 2, False);

  mRow := AddRow;
  FShare := AddCheck(mRow, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateShare));
  FDataFields := AddCheck(mRow, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateDataField));
  mRow := AddRow;
  FPush := AddCheck(mRow, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicatePush));

  mRow := AddRow;
  FPreview := AddLabel(mRow, '');
  mRow := AddRow;
  FBad := AddLabel(mRow, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateBad));
  FBad.Font.Color := clRed;
  FBad.Visible := False;

  AddButtons;
  Load(AOptions);
  ActiveControl := FList;
end;

function TAtlasDuplicateDialog.AddRow: TFlowPanel;
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

function TAtlasDuplicateDialog.AddLabel(AParent: TWinControl; const ACaption: string): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, ScaleValue(3), cGap div 2, 0);
end;

function TAtlasDuplicateDialog.AddEdit(AParent: TWinControl; AWidth: Integer; ANumbers: Boolean): TEdit;
begin
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.Width := ScaleValue(AWidth);
  Result.NumbersOnly := ANumbers;
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, 0, 0);
  Result.OnChange := Changed;
end;

function TAtlasDuplicateDialog.AddCheck(AParent: TWinControl; const ACaption: string): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(24);
  Result.AlignWithMargins := True;
  Result.Margins.SetBounds(0, 0, cGap * 2, 0);
  Result.OnClick := Changed;
end;

procedure TAtlasDuplicateDialog.AddButtons;
var
  mButtons: TFlowPanel;

  function AddButton(const ACaption: string): TButton;
  begin
    Result := TButton.Create(Self);
    Result.Parent := mButtons;
    Result.Caption := ACaption;
    Result.Width := Canvas.TextWidth(ACaption) + ScaleValue(32);
    Result.AlignWithMargins := True;
    Result.Margins.SetBounds(0, 0, cGap, 0);
  end;

begin
  mButtons := AddRow;
  mButtons.Margins.SetBounds(cGap, cGap, cGap, cGap);
  FOk := AddButton(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateOk));
  FOk.Default := True;
  FOk.ModalResult := mrOk;
  FCancel := AddButton(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateCancel));
  FCancel.Cancel := True;
  FCancel.ModalResult := mrCancel;
  ClientHeight := mButtons.Top + mButtons.Height + ScaleValue(cGap);
end;

procedure TAtlasDuplicateDialog.Load(const AOptions: TAtlasDuplicateOptions);
begin
  FLoading := True;
  try
    FDirection.ItemIndex := Ord(AOptions.Direction);
    FDirection.OnChange := Changed;
    FGap.Text := IntToStr(AOptions.Gap);
    FCount.Text := IntToStr(AOptions.Count);
    FList.Text := AOptions.List;
    FShare.Checked := AOptions.ShareEvents;
    FDataFields.Checked := AOptions.DataFields;
    FPush.Checked := AOptions.Push;
  finally
    FLoading := False;
  end;
end;

function TAtlasDuplicateDialog.Options: TAtlasDuplicateOptions;
begin
  Result.Direction := TAtlasDuplicateDirection.Down;
  if FDirection.ItemIndex = 1 then
  begin
    Result.Direction := TAtlasDuplicateDirection.Right;
  end;
  Result.Gap := EnsureRange(StrToIntDef(FGap.Text, 0), 0, 1000);
  Result.Count := EnsureRange(StrToIntDef(FCount.Text, 1), 1, cMaxCount);
  Result.List := Trim(FList.Text);
  Result.ShareEvents := FShare.Checked;
  Result.DataFields := FDataFields.Checked;
  Result.Push := FPush.Checked;
end;

procedure TAtlasDuplicateDialog.Changed(Sender: TObject);
begin
  if FLoading then
  begin
    Exit;
  end;
  // Mit Liste ergibt sie die Anzahl; DataField gibt es nur mit Liste.
  FCount.Enabled := Length(TAtlasDuplicateRow.ParseList(FList.Text)) = 0;
  FDataFields.Enabled := not FCount.Enabled;
  if Assigned(FOnChange) then
  begin
    FOnChange(Options);
  end;
end;

procedure TAtlasDuplicateDialog.SetPreview(const AText: string; ABad: Boolean);
begin
  FPreview.Caption := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerDuplicatePreview, [AText]);
  FBad.Visible := ABad;
end;

class function TAtlasDuplicateDialog.Execute(var AOptions: TAtlasDuplicateOptions;
  const AOnChange: TProc<TAtlasDuplicateOptions, TAtlasDuplicateDialog>): Boolean;
var
  mDialog: TAtlasDuplicateDialog;
begin
  mDialog := TAtlasDuplicateDialog.CreateDialog(nil, AOptions);
  try
    mDialog.OnChange :=
      procedure(AChanged: TAtlasDuplicateOptions)
      begin
        AOnChange(AChanged, mDialog);
      end;
    mDialog.Changed(nil);
    Result := mDialog.ShowModal = mrOk;
    AOptions := mDialog.Options;
  finally
    mDialog.Free;
  end;
end;

end.
