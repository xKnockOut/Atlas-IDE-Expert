unit Atlas.UI.Debug.ProfileFrame;

// Inhalt des Fensters „Atlas: Profil“ (#2057): oben die Wahl des Laufs (die
// letzten fünf), „Nur eigener Code“, „Mit vorigem Lauf vergleichen“ und die
// Knöpfe „Profil starten/beenden“ und „Neu laden“; in der Mitte die Methoden
// als virtuelle Liste (Methode, Unit, Eigen, Gesamt, heißeste Zeile bzw. im
// Vergleich Methode, Vorher, Nachher, Änderung); unten eine Zeile zum Lauf.
// Doppelklick bzw. Enter meldet die Zeile über OnOpen. Die Läufe lädt und
// wertet die IDE-Schicht (Atlas.IDE.Debug.Profiler) aus; der Frame zeigt nur.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Atlas.Core.Debug.Profiler;

type
  TAtlasDebugProfileFrame = class(TFrame)
  private type
    TControls = record
      RunBox: TComboBox;
      OwnOnly: TCheckBox;
      Compare: TCheckBox;
      Toggle: TButton;
      Reload: TButton;
      List: TListView;
      Summary: TLabel;
    end;
    TEvents = record
      RunChange: TProc;
      OptionsChange: TProc;
      Toggle: TProc;
      Reload: TProc;
      Open: TProc<TAtlasProfileRow>;
    end;
    TShown = record
      Runs: TArray<string>;
      RunIndex: Integer;
      Rows: TArray<TAtlasProfileRow>;
      Compare: Boolean;
    end;
  private
    FControls: TControls;
    FEvents: TEvents;
    FShown: TShown;
    procedure CreateTopBar;
    procedure CreateList;
    procedure SetColumns(ACompare: Boolean);
    procedure FillRuns;
    procedure FillRows;
    procedure ListData(Sender: TObject; Item: TListItem);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure RunBoxChange(Sender: TObject);
    procedure OptionClick(Sender: TObject);
    procedure ToggleClick(Sender: TObject);
    procedure ReloadClick(Sender: TObject);
    procedure OpenSelected;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Titel der Läufe, neuester zuerst; AIndex der gezeigte (-1 = keiner).</summary>
    procedure SetRuns(const ATitles: TArray<string>; AIndex: Integer);
    /// <summary>Zeilen zeigen; ACompare wählt die Spalten des Vergleichs.</summary>
    procedure ShowRows(const ARows: TArray<TAtlasProfileRow>; ACompare: Boolean);
    procedure SetSummary(const AText: string);
    /// <summary>Beschriftung des Knopfs: „Profil beenden“ während eines Laufs, sonst „Profil starten“.</summary>
    procedure SetRunning(ARunning: Boolean);
    function RunIndex: Integer;
    function OwnOnly: Boolean;
    function CompareWanted: Boolean;
    /// <summary>Zeile AIndex der Liste; False außerhalb.</summary>
    function TryRow(AIndex: Integer; out ARow: TAtlasProfileRow): Boolean;
    function RowCount: Integer;
    property RunBox: TComboBox read FControls.RunBox;
    property OwnOnlyCheck: TCheckBox read FControls.OwnOnly;
    property CompareCheck: TCheckBox read FControls.Compare;
    property ToggleButton: TButton read FControls.Toggle;
    property ReloadButton: TButton read FControls.Reload;
    property List: TListView read FControls.List;
    property SummaryLabel: TLabel read FControls.Summary;
    property OnRunChange: TProc read FEvents.RunChange write FEvents.RunChange;
    property OnOptionsChange: TProc read FEvents.OptionsChange write FEvents.OptionsChange;
    property OnToggle: TProc read FEvents.Toggle write FEvents.Toggle;
    property OnReload: TProc read FEvents.Reload write FEvents.Reload;
    property OnOpen: TProc<TAtlasProfileRow> read FEvents.Open write FEvents.Open;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.CommCtrl,
  Atlas.UI.Debug.Profile.Strings;

{$R *.dfm}

const
  /// <summary>Höhe der Leiste oben und Breiten, logische Pixel.</summary>
  cBarHeight = 32;
  cRunWidth = 170;
  cCheckWidth = 190;
  cButtonWidth = 110;
  cNameWidth = 300;
  cUnitWidth = 160;
  cNumberWidth = 80;
  cLineWidth = 100;

function Px(AFrame: TAtlasDebugProfileFrame; AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, AFrame.CurrentPPI, 96);
end;

function AddButton(AFrame: TAtlasDebugProfileFrame; AParent: TWinControl; const ACaption: string;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AFrame);
  Result.Parent := AParent;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := Px(AFrame, cButtonWidth);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

function AddCheck(AFrame: TAtlasDebugProfileFrame; AParent: TWinControl; ALeft: Integer; const ACaption: string;
  AClick: TNotifyEvent): TCheckBox;
begin
  Result := TCheckBox.Create(AFrame);
  Result.Left := ALeft;
  Result.Align := alLeft;
  Result.Parent := AParent;
  Result.AlignWithMargins := True;
  Result.Width := Px(AFrame, cCheckWidth);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
end;

procedure AddColumn(AList: TListView; const ACaption: string; AWidth: Integer; ARight: Boolean);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := ACaption;
  mColumn.Width := AWidth;
  if ARight then
  begin
    mColumn.Alignment := taRightJustify;
  end;
end;

{ TAtlasDebugProfileFrame }

constructor TAtlasDebugProfileFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FShown.RunIndex := -1;
  CreateTopBar;
  FControls.Summary := TLabel.Create(Self);
  FControls.Summary.Align := alBottom;
  FControls.Summary.Parent := Self;
  FControls.Summary.AlignWithMargins := True;
  FControls.Summary.ShowAccelChar := False;
  FControls.Summary.Caption := TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileEmpty);
  CreateList;
  SetRunning(False);
end;

procedure TAtlasDebugProfileFrame.CreateTopBar;
var
  mBar: TPanel;
  mLabel: TLabel;
begin
  mBar := TPanel.Create(Self);
  mBar.Height := Px(Self, cBarHeight);
  mBar.Align := alTop;
  mBar.Parent := Self;
  mBar.BevelOuter := bvNone;
  mBar.ShowCaption := False;
  mBar.ParentBackground := True;
  FControls.Reload := AddButton(Self, mBar, TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileReload),
    ReloadClick);
  FControls.Toggle := AddButton(Self, mBar, TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileStart),
    ToggleClick);
  mLabel := TLabel.Create(Self);
  mLabel.Align := alLeft;
  mLabel.Parent := mBar;
  mLabel.AlignWithMargins := True;
  mLabel.Layout := tlCenter;
  mLabel.Caption := TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileRunsLabel);
  FControls.RunBox := TComboBox.Create(Self);
  FControls.RunBox.Left := mLabel.Left + mLabel.Width + 1;
  FControls.RunBox.Align := alLeft;
  FControls.RunBox.Parent := mBar;
  FControls.RunBox.AlignWithMargins := True;
  FControls.RunBox.Style := csDropDownList;
  FControls.RunBox.Width := Px(Self, cRunWidth);
  FControls.RunBox.OnChange := RunBoxChange;
  FControls.OwnOnly := AddCheck(Self, mBar, FControls.RunBox.Left + FControls.RunBox.Width + 1,
    TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileOwnOnly), OptionClick);
  FControls.Compare := AddCheck(Self, mBar, FControls.OwnOnly.Left + FControls.OwnOnly.Width + 1,
    TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileCompare), OptionClick);
end;

procedure TAtlasDebugProfileFrame.CreateList;
begin
  FControls.List := TListView.Create(Self);
  FControls.List.Parent := Self;
  FControls.List.Align := alClient;
  FControls.List.AlignWithMargins := True;
  FControls.List.ViewStyle := vsReport;
  FControls.List.OwnerData := True;
  FControls.List.RowSelect := True;
  FControls.List.HideSelection := False;
  FControls.List.ReadOnly := True;
  FControls.List.MultiSelect := False;
  FControls.List.ColumnClick := False;
  FControls.List.OnData := ListData;
  FControls.List.OnDblClick := ListDblClick;
  FControls.List.OnKeyDown := ListKeyDown;
  SetColumns(False);
end;

procedure TAtlasDebugProfileFrame.SetColumns(ACompare: Boolean);
var
  mList: TListView;
begin
  mList := FControls.List;
  mList.Columns.BeginUpdate;
  try
    mList.Columns.Clear;
    AddColumn(mList, TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileColumnMethod), Px(Self, cNameWidth),
      False);
    if ACompare then
    begin
      AddColumn(mList, TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileColumnBefore),
        Px(Self, cNumberWidth), True);
      AddColumn(mList, TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileColumnAfter), Px(Self, cNumberWidth),
        True);
      AddColumn(mList, TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileColumnChange),
        Px(Self, cNumberWidth), True);
    end
    else
    begin
      AddColumn(mList, TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileColumnUnit), Px(Self, cUnitWidth),
        False);
      AddColumn(mList, TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileColumnSelf), Px(Self, cNumberWidth),
        True);
      AddColumn(mList, TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileColumnTotal), Px(Self, cNumberWidth),
        True);
      AddColumn(mList, TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileColumnLine), Px(Self, cLineWidth),
        True);
    end;
  finally
    mList.Columns.EndUpdate;
  end;
end;

procedure TAtlasDebugProfileFrame.CreateWnd;
begin
  inherited CreateWnd;
  // Auswahlliste und Items.Count der virtuellen Liste brauchen ein Fenster.
  FillRuns;
  FillRows;
end;

procedure TAtlasDebugProfileFrame.SetRuns(const ATitles: TArray<string>; AIndex: Integer);
begin
  FShown.Runs := ATitles;
  FShown.RunIndex := AIndex;
  FillRuns;
end;

procedure TAtlasDebugProfileFrame.FillRuns;
var
  mTitle: string;
begin
  if not FControls.RunBox.HandleAllocated then
  begin
    if not HandleAllocated then
    begin
      Exit;
    end;
    FControls.RunBox.HandleNeeded;
  end;
  FControls.RunBox.Items.BeginUpdate;
  try
    FControls.RunBox.Items.Clear;
    for mTitle in FShown.Runs do
    begin
      FControls.RunBox.Items.Add(mTitle);
    end;
  finally
    FControls.RunBox.Items.EndUpdate;
  end;
  FControls.RunBox.ItemIndex := FShown.RunIndex;
end;

procedure TAtlasDebugProfileFrame.ShowRows(const ARows: TArray<TAtlasProfileRow>; ACompare: Boolean);
begin
  if ACompare <> FShown.Compare then
  begin
    SetColumns(ACompare);
  end;
  FShown.Compare := ACompare;
  FShown.Rows := ARows;
  FillRows;
end;

procedure TAtlasDebugProfileFrame.FillRows;
begin
  if not FControls.List.HandleAllocated then
  begin
    if not HandleAllocated then
    begin
      Exit;
    end;
    FControls.List.HandleNeeded;
  end;
  FControls.List.Items.Count := Length(FShown.Rows);
  ListView_SetItemState(FControls.List.Handle, -1, 0, LVIS_SELECTED);
  FControls.List.Invalidate;
end;

procedure TAtlasDebugProfileFrame.SetSummary(const AText: string);
begin
  FControls.Summary.Caption := AText;
end;

procedure TAtlasDebugProfileFrame.SetRunning(ARunning: Boolean);
begin
  if ARunning then
  begin
    FControls.Toggle.Caption := TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileStop);
  end
  else
  begin
    FControls.Toggle.Caption := TAtlasProfileStrings.Text(TAtlasProfileTextId.ProfileStart);
  end;
end;

function TAtlasDebugProfileFrame.RunIndex: Integer;
begin
  Result := FShown.RunIndex;
end;

function TAtlasDebugProfileFrame.OwnOnly: Boolean;
begin
  Result := FControls.OwnOnly.Checked;
end;

function TAtlasDebugProfileFrame.CompareWanted: Boolean;
begin
  Result := FControls.Compare.Checked;
end;

function TAtlasDebugProfileFrame.RowCount: Integer;
begin
  Result := Length(FShown.Rows);
end;

function TAtlasDebugProfileFrame.TryRow(AIndex: Integer; out ARow: TAtlasProfileRow): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FShown.Rows));
  if Result then
  begin
    ARow := FShown.Rows[AIndex];
  end
  else
  begin
    ARow := Default(TAtlasProfileRow);
  end;
end;

procedure TAtlasDebugProfileFrame.ListData(Sender: TObject; Item: TListItem);
var
  mRow: TAtlasProfileRow;
  mIndex: Integer;
begin
  if not TryRow(Item.Index, mRow) or (Length(mRow.Cells) = 0) then
  begin
    Exit;
  end;
  Item.Caption := mRow.Cells[0];
  for mIndex := 1 to High(mRow.Cells) do
  begin
    Item.SubItems.Add(mRow.Cells[mIndex]);
  end;
end;

procedure TAtlasDebugProfileFrame.OpenSelected;
var
  mRow: TAtlasProfileRow;
begin
  if (FControls.List.Selected = nil) or not TryRow(FControls.List.Selected.Index, mRow) then
  begin
    Exit;
  end;
  if Assigned(FEvents.Open) then
  begin
    FEvents.Open(mRow);
  end;
end;

procedure TAtlasDebugProfileFrame.ListDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TAtlasDebugProfileFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    OpenSelected;
  end;
end;

procedure TAtlasDebugProfileFrame.RunBoxChange(Sender: TObject);
begin
  FShown.RunIndex := FControls.RunBox.ItemIndex;
  if Assigned(FEvents.RunChange) then
  begin
    FEvents.RunChange();
  end;
end;

procedure TAtlasDebugProfileFrame.OptionClick(Sender: TObject);
begin
  if Assigned(FEvents.OptionsChange) then
  begin
    FEvents.OptionsChange();
  end;
end;

procedure TAtlasDebugProfileFrame.ToggleClick(Sender: TObject);
begin
  if Assigned(FEvents.Toggle) then
  begin
    FEvents.Toggle();
  end;
end;

procedure TAtlasDebugProfileFrame.ReloadClick(Sender: TObject);
begin
  if Assigned(FEvents.Reload) then
  begin
    FEvents.Reload();
  end;
end;

end.
