unit Atlas.UI.Debug.InstanceBreakpoint;

// Haltepunkt nur für ein Objekt (#857), Fensterteil (nur VCL): ein Dialog mit
// Satz, Liste und Knöpfen für beide Fragen.
//   Haltepunkt nur wenn …
//   Bedingung für Kunde.pas:42 aus einem Feld von Self (aktueller Wert):
//   ┌──────────────────────────────┐
//   │ FNr = 4711                   │
//   │ FName = 'Meier'              │
//   └──────────────────────────────┘
//                      [Übernehmen] [Abbrechen]
// bzw. vor dem Start zu Adressbedingungen der letzten Sitzung:
//   [Adressbedingung entfernen] [Durch Feldbedingung ersetzen …] [Behalten]
// Ergebnis ist der Index des gedrückten Knopfs (-1 bei Schließen) und der
// gewählte Eintrag. Doppelklick bzw. Eingabe in der Liste drückt den ersten
// Knopf.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.UI.Foundation.Dialog;

type
  TAtlasInstanceBreakpointDialog = class(TAtlasDialog)
  private
    FItems: TArray<string>;
    FSummary: TLabel;
    FList: TListBox;
    FButtons: TArray<TButton>;
    FPressed: Integer;
    procedure CreateList;
    procedure CreateButtons(const ACaptions: TArray<string>; ACancel: Integer);
    procedure ButtonClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyPress(Sender: TObject; var Key: Char);
  protected
    procedure DoShow; override;
  public
    /// <summary>ACaptions: Knöpfe von links; der erste ist die Vorgabe, ACancel (-1 ohne) schließt wie Esc.
    /// </summary>
    constructor CreateQuestion(AOwner: TComponent; const ATitle, ASummary: string; const AItems,
      ACaptions: TArray<string>; ACancel: Integer);
    /// <summary>Liste füllen; braucht ein Fenster (DoShow, Tests nach HandleNeeded). Einmal.</summary>
    procedure Fill;
    /// <summary>Knopf AIndex drücken (wie ein Klick).</summary>
    procedure Press(AIndex: Integer);
    /// <summary>Modal fragen: Index des Knopfs (-1 bei Schließen), AItem der gewählte Eintrag (-1 ohne).
    /// </summary>
    class function Ask(const ATitle, ASummary: string; const AItems, ACaptions: TArray<string>; ACancel: Integer;
      out AItem: Integer): Integer; static;
    property Pressed: Integer read FPressed;
    property SummaryLabel: TLabel read FSummary;
    property ItemList: TListBox read FList;
    property Buttons: TArray<TButton> read FButtons;
  end;

implementation

const
  cDialogWidth = 520;
  cSummaryHeight = 22;
  cListHeight = 180;

{ TAtlasInstanceBreakpointDialog }

constructor TAtlasInstanceBreakpointDialog.CreateQuestion(AOwner: TComponent; const ATitle, ASummary: string;
  const AItems, ACaptions: TArray<string>; ACancel: Integer);
begin
  inherited CreateDialog(AOwner, ATitle, cDialogWidth);
  FItems := AItems;
  FPressed := -1;
  FSummary := AddLabel(AddRow(cSummaryHeight), ASummary);
  FSummary.ShowAccelChar := False;
  CreateList;
  CreateButtons(ACaptions, ACancel);
  FitHeight;
  AllowResize(FList);
  ActiveControl := FList;
end;

procedure TAtlasInstanceBreakpointDialog.CreateList;
begin
  FList := TListBox.Create(Self);
  // Lage vor Align und Parent wie bei AddRow.
  FList.Top := NextTop;
  FList.Height := ScaleValue(cListHeight);
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(ScaleValue(cRowGap), 0, ScaleValue(cRowGap), 0);
  FList.Align := alTop;
  FList.Parent := Self;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyPress := ListKeyPress;
end;

procedure TAtlasInstanceBreakpointDialog.CreateButtons(const ACaptions: TArray<string>; ACancel: Integer);
var
  mRow: TAtlasButtonRow;
  mIndex: Integer;
  mKind: TAtlasButtonKind;
  mButton: TButton;
begin
  mRow := AddButtonRow;
  SetLength(FButtons, Length(ACaptions));
  for mIndex := 0 to High(ACaptions) do
  begin
    mKind := TAtlasButtonKind.Plain;
    if mIndex = 0 then
    begin
      mKind := TAtlasButtonKind.Default;
    end
    else if mIndex = ACancel then
    begin
      mKind := TAtlasButtonKind.Cancel;
    end;
    mButton := mRow.AddButton(ACaptions[mIndex], mKind);
    mButton.Tag := mIndex;
    mButton.OnClick := ButtonClick;
    FButtons[mIndex] := mButton;
  end;
end;

procedure TAtlasInstanceBreakpointDialog.Fill;
var
  mItem: string;
begin
  if FList.Items.Count > 0 then
  begin
    Exit;
  end;
  FList.Items.BeginUpdate;
  try
    for mItem in FItems do
    begin
      FList.Items.Add(mItem);
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FList.Items.Count > 0 then
  begin
    FList.ItemIndex := 0;
  end;
end;

procedure TAtlasInstanceBreakpointDialog.DoShow;
begin
  inherited;
  // Die Liste braucht ein Fenster: erst hier füllen.
  Fill;
end;

procedure TAtlasInstanceBreakpointDialog.Press(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FButtons)) then
  begin
    Exit;
  end;
  FPressed := AIndex;
  ModalResult := mrOk;
end;

procedure TAtlasInstanceBreakpointDialog.ButtonClick(Sender: TObject);
begin
  Press((Sender as TButton).Tag);
end;

procedure TAtlasInstanceBreakpointDialog.ListDblClick(Sender: TObject);
begin
  Press(0);
end;

procedure TAtlasInstanceBreakpointDialog.ListKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    Press(0);
  end;
end;

class function TAtlasInstanceBreakpointDialog.Ask(const ATitle, ASummary: string; const AItems,
  ACaptions: TArray<string>; ACancel: Integer; out AItem: Integer): Integer;
var
  mDialog: TAtlasInstanceBreakpointDialog;
begin
  mDialog := TAtlasInstanceBreakpointDialog.CreateQuestion(nil, ATitle, ASummary, AItems, ACaptions, ACancel);
  try
    mDialog.ShowModal;
    Result := mDialog.Pressed;
    AItem := mDialog.ItemList.ItemIndex;
    if Result = ACancel then
    begin
      Result := -1;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
