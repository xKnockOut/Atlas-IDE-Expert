unit Atlas.UI.Debug.BreakpointSets;

// Dialoge der Haltepunkt-Sätze (#586), nur VCL:
//   Speichern                              Wechseln/Hinzufügen/Löschen
//   Name des Satzes (vorhandener …):      ┌──────────────────────────────────┐
//   [Import                         ▾]    │ Import (12 Haltepunkte, Branch …)│
//   [x] An Branch feature/import koppeln  │ Speichern (3 Haltepunkte)        │
//              [Speichern] [Abbrechen]    └──────────────────────────────────┘
//                                                     [Wechseln] [Abbrechen]
// Liste und Auswahlfeld füllt erst DoShow (brauchen ein Fenster).

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Debug.BreakpointSets,
  Atlas.UI.Foundation.Dialog;

type
  {$SCOPEDENUMS ON}
  TAtlasBreakpointSetMode = (Save, Switch, Add, Delete);
  {$SCOPEDENUMS OFF}

  TAtlasBreakpointSetDialog = class(TAtlasDialog)
  private
    FMode: TAtlasBreakpointSetMode;
    FSets: TAtlasBreakpointSetList;
    FBranch: string;
    FSelected: string;
    FName: TComboBox;
    FCouple: TCheckBox;
    FList: TListBox;
    FOk: TButton;
    FFilled: Boolean;
    procedure CreateSaveRows;
    procedure CreateList;
    procedure CreateButtons;
    procedure ListDblClick(Sender: TObject);
    procedure OkClick(Sender: TObject);
    function TitleText: string;
    function OkText: string;
  protected
    procedure DoShow; override;
  public
    constructor CreateDialog(AOwner: TComponent; AMode: TAtlasBreakpointSetMode;
      const ASets: TAtlasBreakpointSetList; const ABranch, ASelected: string);
    /// <summary>Liste bzw. Auswahlfeld füllen; braucht ein Fenster (DoShow, Tests nach HandleNeeded). Einmal.
    /// </summary>
    procedure Fill;
    /// <summary>Gewählter bzw. eingegebener Name; '' ohne Wahl.</summary>
    function ChosenName: string;
    /// <summary>Speichern: Branch zum Koppeln ('' ohne).</summary>
    function ChosenBranch: string;
    /// <summary>Text eines Satzes in der Liste.</summary>
    class function ItemText(const ASet: TAtlasBreakpointSet): string; static;
    /// <summary>Zeigt den Dialog modal; False bei Abbrechen.</summary>
    class function Execute(AMode: TAtlasBreakpointSetMode; const ASets: TAtlasBreakpointSetList;
      const ABranch, ASelected: string; out AName, ABranchChosen: string): Boolean; static;
    property NameBox: TComboBox read FName;
    property CoupleCheck: TCheckBox read FCouple;
    property SetList: TListBox read FList;
    property OkButton: TButton read FOk;
  end;

implementation

uses
  Atlas.UI.Debug.Strings;

const
  cDialogWidth = 460;
  cRowHeight = 24;
  cListHeight = 180;

{ TAtlasBreakpointSetDialog }

constructor TAtlasBreakpointSetDialog.CreateDialog(AOwner: TComponent; AMode: TAtlasBreakpointSetMode;
  const ASets: TAtlasBreakpointSetList; const ABranch, ASelected: string);
begin
  // Titel hängt vom Modus ab: vor dem geerbten Konstruktor setzen.
  FMode := AMode;
  inherited CreateDialog(AOwner, TitleText, cDialogWidth);
  FSets := ASets;
  FBranch := ABranch;
  FSelected := ASelected;
  if FMode = TAtlasBreakpointSetMode.Save then
  begin
    CreateSaveRows;
  end
  else
  begin
    CreateList;
  end;
  CreateButtons;
  FitHeight;
  if FList <> nil then
  begin
    AllowResize(FList);
    ActiveControl := FList;
  end
  else
  begin
    ActiveControl := FName;
  end;
end;

function TAtlasBreakpointSetDialog.TitleText: string;
begin
  case FMode of
    TAtlasBreakpointSetMode.Save:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetSaveTitle);
    TAtlasBreakpointSetMode.Add:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetAddTitle);
    TAtlasBreakpointSetMode.Delete:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetDeleteTitle);
  else
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetSwitchTitle);
  end;
end;

function TAtlasBreakpointSetDialog.OkText: string;
begin
  case FMode of
    TAtlasBreakpointSetMode.Save:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetSave);
    TAtlasBreakpointSetMode.Add:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetAdd);
    TAtlasBreakpointSetMode.Delete:
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetDelete);
  else
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetSwitch);
  end;
end;

procedure TAtlasBreakpointSetDialog.CreateSaveRows;
var
  mRow: TPanel;
  mLabel: TLabel;
begin
  mRow := AddRow(cRowHeight);
  mLabel := AddLabel(mRow, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetName));
  mLabel.ShowAccelChar := False;
  mRow := AddRow(cRowHeight);
  FName := TComboBox.Create(Self);
  FName.Style := csDropDown;
  FName.Align := alClient;
  FName.Parent := mRow;
  if FBranch <> '' then
  begin
    mRow := AddRow(cRowHeight);
    FCouple := TCheckBox.Create(Self);
    FCouple.Caption := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetBranch, [FBranch]);
    FCouple.Align := alClient;
    FCouple.Parent := mRow;
  end;
end;

procedure TAtlasBreakpointSetDialog.CreateList;
begin
  FList := TListBox.Create(Self);
  // Lage vor Align und Parent wie bei AddRow.
  FList.Top := NextTop;
  FList.Height := ScaleValue(cListHeight);
  FList.AlignWithMargins := True;
  FList.Margins.SetBounds(ScaleValue(cRowGap), ScaleValue(cRowGap), ScaleValue(cRowGap), 0);
  FList.Align := alTop;
  FList.Parent := Self;
  FList.OnDblClick := ListDblClick;
end;

procedure TAtlasBreakpointSetDialog.CreateButtons;
var
  mButtons: TAtlasButtonRow;
  mCancel: TButton;
begin
  mButtons := AddButtonRow;
  FOk := mButtons.AddButton(OkText, TAtlasButtonKind.Default);
  FOk.OnClick := OkClick;
  mCancel := mButtons.AddButton(TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointSetCancel),
    TAtlasButtonKind.Cancel);
  mCancel.ModalResult := mrCancel;
end;

class function TAtlasBreakpointSetDialog.ItemText(const ASet: TAtlasBreakpointSet): string;
begin
  if ASet.Branch <> '' then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetItemBranch,
      [ASet.Name, Length(ASet.Entries), ASet.Branch]);
  end
  else
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointSetItem, [ASet.Name, Length(ASet.Entries)]);
  end;
end;

procedure TAtlasBreakpointSetDialog.Fill;
var
  mSet: TAtlasBreakpointSet;
  mIndex: Integer;
begin
  if FFilled then
  begin
    Exit;
  end;
  FFilled := True;
  if FName <> nil then
  begin
    FName.Items.BeginUpdate;
    try
      for mSet in FSets do
      begin
        FName.Items.Add(mSet.Name);
      end;
    finally
      FName.Items.EndUpdate;
    end;
    FName.Text := FSelected;
    if (FCouple <> nil) and (TAtlasBreakpointSets.ForBranch(FSets, FBranch) >= 0) then
    begin
      FCouple.Checked := SameText(FSets[TAtlasBreakpointSets.ForBranch(FSets, FBranch)].Name, FSelected);
    end;
    Exit;
  end;
  FList.Items.BeginUpdate;
  try
    for mIndex := 0 to High(FSets) do
    begin
      FList.Items.Add(ItemText(FSets[mIndex]));
    end;
  finally
    FList.Items.EndUpdate;
  end;
  for mIndex := 0 to High(FSets) do
  begin
    if SameText(FSets[mIndex].Name, FSelected) then
    begin
      FList.ItemIndex := mIndex;
    end;
  end;
  if (FList.ItemIndex < 0) and (FList.Items.Count > 0) then
  begin
    FList.ItemIndex := 0;
  end;
end;

procedure TAtlasBreakpointSetDialog.DoShow;
begin
  inherited;
  Fill;
end;

function TAtlasBreakpointSetDialog.ChosenName: string;
begin
  Result := '';
  if FName <> nil then
  begin
    Result := Trim(FName.Text);
  end
  else if (FList <> nil) and (FList.ItemIndex >= 0) and (FList.ItemIndex <= High(FSets)) then
  begin
    Result := FSets[FList.ItemIndex].Name;
  end;
end;

function TAtlasBreakpointSetDialog.ChosenBranch: string;
begin
  Result := '';
  if (FCouple <> nil) and FCouple.Checked then
  begin
    Result := FBranch;
  end;
end;

procedure TAtlasBreakpointSetDialog.ListDblClick(Sender: TObject);
begin
  OkClick(Sender);
end;

procedure TAtlasBreakpointSetDialog.OkClick(Sender: TObject);
begin
  if ChosenName <> '' then
  begin
    ModalResult := mrOk;
  end;
end;

class function TAtlasBreakpointSetDialog.Execute(AMode: TAtlasBreakpointSetMode;
  const ASets: TAtlasBreakpointSetList; const ABranch, ASelected: string; out AName, ABranchChosen: string): Boolean;
var
  mDialog: TAtlasBreakpointSetDialog;
begin
  AName := '';
  ABranchChosen := '';
  mDialog := TAtlasBreakpointSetDialog.CreateDialog(nil, AMode, ASets, ABranch, ASelected);
  try
    Result := mDialog.ShowModal = mrOk;
    if Result then
    begin
      AName := mDialog.ChosenName;
      ABranchChosen := mDialog.ChosenBranch;
    end;
  finally
    mDialog.Free;
  end;
end;

end.
