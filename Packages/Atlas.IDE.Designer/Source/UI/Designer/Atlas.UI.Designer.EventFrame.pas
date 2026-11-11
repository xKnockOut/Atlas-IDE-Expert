unit Atlas.UI.Designer.EventFrame;

// Ereignis-Karte (#612), Inhalt des andockbaren Fensters, reine VCL:
//   [Filter          ] [Alle Ereignisse ▾] [☐ Nur Befunde] [Gruppe: Handler ▾]
//   ▾ btnOkClick (2)
//     btnOk   TButton   OnClick    btnOkClick   5
//     actOk   TAction   OnExecute  btnOkClick   5
//   ▾ FormDestroy
//     frmKunden TfrmKunden OnDestroy FormDestroy 3  leer
// - Gruppen als ListView-Gruppen (zuklappbar); Befunde in der Fehlerfarbe.
// - Doppelklick meldet OnJump (zum Handler), ein zweiter Doppelklick auf
//   dieselbe Zeile OnShow (Komponente im Designer); Kontextmenü: Im Designer
//   zeigen, Handler umbenennen, Leeren Handler entfernen.
// - Filter, Ereignis, „Nur Befunde“ und Gruppe melden OnOptions.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Menus,
  Atlas.Core.Designer.EventMap;

type
  TAtlasEventFrame = class(TFrame)
  private
    FTop: TPanel;
    FFilter: TEdit;
    FEvent: TComboBox;
    FOnlyFindings: TCheckBox;
    FGroup: TComboBox;
    FList: TListView;
    FMenu: TPopupMenu;
    FRemoveItem: TMenuItem;
    FRows: TArray<TAtlasEventRow>;
    FLastJump: Integer;
    FUpdating: Boolean;
    FErrorColor: TColor;
    FOnJump: TProc<TAtlasEventRow>;
    FOnShow: TProc<TAtlasEventRow>;
    FOnRename: TProc<TAtlasEventRow>;
    FOnRemove: TProc<TAtlasEventRow>;
    FOnOptions: TProc;
    function AddCombo(const AItems: array of string): TComboBox;
    function AddMenuItem(const ACaption: string; const AOnClick: TNotifyEvent): TMenuItem;
    function SelectedRow(out ARow: TAtlasEventRow): Boolean;
    procedure OptionsChanged(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure ShowClick(Sender: TObject);
    procedure RenameClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    function GroupId(const AHeader: string): Integer;
    procedure FillEvents(const AEvents: TArray<string>);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeilen in der Reihenfolge der Gruppe; AFinding: Text je Befund; AEvents: Auswahl im Ereignis-Feld.
    /// </summary>
    procedure ShowRows(const ARows: TArray<TAtlasEventRow>; const AEvents: TArray<string>;
      const AFinding: TFunc<TAtlasEventRow, string>);
    function FilterText: string;
    /// <summary>Gewähltes Ereignis; '' = alle.</summary>
    function EventFilter: string;
    function OnlyFindings: Boolean;
    function Group: TAtlasEventGroup;
    property ErrorColor: TColor read FErrorColor write FErrorColor;
    property OnJump: TProc<TAtlasEventRow> read FOnJump write FOnJump;
    property OnShow: TProc<TAtlasEventRow> read FOnShow write FOnShow;
    property OnRename: TProc<TAtlasEventRow> read FOnRename write FOnRename;
    property OnRemove: TProc<TAtlasEventRow> read FOnRemove write FOnRemove;
    property OnOptions: TProc read FOnOptions write FOnOptions;
  end;

implementation

uses
  Atlas.UI.Designer.ViewStrings;

const
  cBasePpi = 96;
  cColumnWidths: array[0..5] of Integer = (120, 100, 100, 150, 60, 180);
  cColumnTexts: array[0..5] of TAtlasDesignerViewTextId = (TAtlasDesignerViewTextId.EmColComponent,
    TAtlasDesignerViewTextId.EmColClass, TAtlasDesignerViewTextId.EmColEvent, TAtlasDesignerViewTextId.EmColHandler,
    TAtlasDesignerViewTextId.EmColLines, TAtlasDesignerViewTextId.EmColFinding);
  cComboWidth = 140;
  cCheckBoxBox = 24;
  cNoGroup = '–';

{ TAtlasEventFrame }

constructor TAtlasEventFrame.Create(AOwner: TComponent);
var
  mIndex: Integer;
  mColumn: TListColumn;
begin
  inherited Create(AOwner);
  FErrorColor := clRed;
  FLastJump := -1;
  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.BevelOuter := bvNone;
  FTop.AutoSize := True;
  FGroup := AddCombo([TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmGroupComponent),
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmGroupEvent),
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmGroupHandler)]);
  FOnlyFindings := TCheckBox.Create(Self);
  FOnlyFindings.Parent := FTop;
  FOnlyFindings.Align := alRight;
  FOnlyFindings.AlignWithMargins := True;
  FOnlyFindings.Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmOnlyFindings);
  FOnlyFindings.Width := Canvas.TextWidth(FOnlyFindings.Caption) + MulDiv(cCheckBoxBox, CurrentPPI, cBasePpi);
  FOnlyFindings.OnClick := OptionsChanged;
  FEvent := AddCombo([TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmAllEvents)]);
  FFilter := TEdit.Create(Self);
  FFilter.Parent := FTop;
  FFilter.Align := alClient;
  FFilter.AlignWithMargins := True;
  FFilter.TextHint := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.NvFilter);
  FFilter.OnChange := OptionsChanged;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  AddMenuItem(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmShow), ShowClick);
  AddMenuItem(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmRename), RenameClick);
  FRemoveItem := AddMenuItem(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmRemove), RemoveClick);
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.ReadOnly := True;
  FList.HideSelection := False;
  FList.GroupView := True;
  FList.PopupMenu := FMenu;
  for mIndex := 0 to High(cColumnWidths) do
  begin
    mColumn := FList.Columns.Add;
    mColumn.Caption := TAtlasDesignerViewStrings.Text(cColumnTexts[mIndex]);
    mColumn.Width := MulDiv(cColumnWidths[mIndex], CurrentPPI, cBasePpi);
  end;
  FList.Columns[4].Alignment := taRightJustify;
  FList.OnDblClick := ListDblClick;
  FList.OnCustomDrawItem := ListCustomDrawItem;
end;

function TAtlasEventFrame.AddCombo(const AItems: array of string): TComboBox;
var
  mItem: string;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := FTop;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Style := csDropDownList;
  Result.Width := MulDiv(cComboWidth, CurrentPPI, cBasePpi);
  for mItem in AItems do
  begin
    Result.Items.Add(mItem);
  end;
  Result.ItemIndex := 0;
  Result.OnChange := OptionsChanged;
end;

function TAtlasEventFrame.AddMenuItem(const ACaption: string; const AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
  FMenu.Items.Add(Result);
end;

procedure TAtlasEventFrame.OptionsChanged(Sender: TObject);
begin
  if not FUpdating and Assigned(FOnOptions) then
  begin
    FOnOptions();
  end;
end;

function TAtlasEventFrame.FilterText: string;
begin
  Result := Trim(FFilter.Text);
end;

function TAtlasEventFrame.EventFilter: string;
begin
  Result := '';
  if FEvent.ItemIndex > 0 then
  begin
    Result := FEvent.Items[FEvent.ItemIndex];
  end;
end;

function TAtlasEventFrame.OnlyFindings: Boolean;
begin
  Result := FOnlyFindings.Checked;
end;

function TAtlasEventFrame.Group: TAtlasEventGroup;
begin
  case FGroup.ItemIndex of
    1:
      Result := TAtlasEventGroup.Event;
    2:
      Result := TAtlasEventGroup.Handler;
  else
    Result := TAtlasEventGroup.Component;
  end;
end;

function TAtlasEventFrame.GroupId(const AHeader: string): Integer;
var
  mIndex: Integer;
  mGroup: TListGroup;
begin
  for mIndex := 0 to FList.Groups.Count - 1 do
  begin
    if FList.Groups[mIndex].Header = AHeader then
    begin
      Exit(FList.Groups[mIndex].GroupID);
    end;
  end;
  mGroup := FList.Groups.Add;
  mGroup.Header := AHeader;
  mGroup.State := [lgsCollapsible];
  Result := mGroup.GroupID;
end;

procedure TAtlasEventFrame.FillEvents(const AEvents: TArray<string>);
var
  mCurrent, mEvent: string;
begin
  mCurrent := EventFilter;
  FEvent.Items.BeginUpdate;
  try
    while FEvent.Items.Count > 1 do
    begin
      FEvent.Items.Delete(1);
    end;
    for mEvent in AEvents do
    begin
      FEvent.Items.Add(mEvent);
    end;
    FEvent.ItemIndex := FEvent.Items.IndexOf(mCurrent);
    if FEvent.ItemIndex < 0 then
    begin
      FEvent.ItemIndex := 0;
    end;
  finally
    FEvent.Items.EndUpdate;
  end;
end;

procedure TAtlasEventFrame.ShowRows(const ARows: TArray<TAtlasEventRow>; const AEvents: TArray<string>;
  const AFinding: TFunc<TAtlasEventRow, string>);
var
  mRow: TAtlasEventRow;
  mItem: TListItem;
  mHeader: string;
  mGroup: TAtlasEventGroup;
begin
  FUpdating := True;
  FList.Items.BeginUpdate;
  try
    FillEvents(AEvents);
    FList.Items.Clear;
    FList.Groups.Clear;
    FRows := ARows;
    FLastJump := -1;
    mGroup := Group;
    for mRow in ARows do
    begin
      mItem := FList.Items.Add;
      mItem.Caption := mRow.Component;
      mItem.SubItems.Add(mRow.ClassName);
      mItem.SubItems.Add(mRow.Event);
      mItem.SubItems.Add(mRow.Handler);
      if mRow.Lines > 0 then
      begin
        mItem.SubItems.Add(IntToStr(mRow.Lines));
      end
      else
      begin
        mItem.SubItems.Add('');
      end;
      mItem.SubItems.Add(AFinding(mRow));
      mHeader := TAtlasEventMap.GroupKey(mRow, mGroup);
      if mHeader = '' then
      begin
        mHeader := cNoGroup;
      end
      else if (mGroup = TAtlasEventGroup.Handler) and (mRow.UseCount > 1) then
      begin
        mHeader := mHeader + ' (' + IntToStr(mRow.UseCount) + ')';
      end;
      mItem.GroupID := GroupId(mHeader);
    end;
  finally
    FList.Items.EndUpdate;
    FUpdating := False;
  end;
end;

function TAtlasEventFrame.SelectedRow(out ARow: TAtlasEventRow): Boolean;
begin
  Result := (FList.Selected <> nil) and (FList.Selected.Index <= High(FRows));
  if Result then
  begin
    ARow := FRows[FList.Selected.Index];
  end;
end;

procedure TAtlasEventFrame.ListDblClick(Sender: TObject);
var
  mRow: TAtlasEventRow;
begin
  if not SelectedRow(mRow) then
  begin
    Exit;
  end;
  // Zweiter Doppelklick auf dieselbe Zeile: vom Handler zur Komponente.
  if (FList.Selected.Index = FLastJump) and (mRow.Component <> '') and Assigned(FOnShow) then
  begin
    FLastJump := -1;
    FOnShow(mRow);
  end
  else if Assigned(FOnJump) then
  begin
    FLastJump := FList.Selected.Index;
    FOnJump(mRow);
  end;
end;

procedure TAtlasEventFrame.MenuPopup(Sender: TObject);
var
  mRow: TAtlasEventRow;
  mHas: Boolean;
  mItem: Integer;
begin
  mHas := SelectedRow(mRow);
  for mItem := 0 to FMenu.Items.Count - 1 do
  begin
    FMenu.Items[mItem].Enabled := mHas;
  end;
  FRemoveItem.Enabled := mHas and (mRow.Finding in [TAtlasEventFinding.Empty, TAtlasEventFinding.Unassigned]);
end;

procedure TAtlasEventFrame.ShowClick(Sender: TObject);
var
  mRow: TAtlasEventRow;
begin
  if SelectedRow(mRow) and Assigned(FOnShow) then
  begin
    FOnShow(mRow);
  end;
end;

procedure TAtlasEventFrame.RenameClick(Sender: TObject);
var
  mRow: TAtlasEventRow;
begin
  if SelectedRow(mRow) and Assigned(FOnRename) then
  begin
    FOnRename(mRow);
  end;
end;

procedure TAtlasEventFrame.RemoveClick(Sender: TObject);
var
  mRow: TAtlasEventRow;
begin
  if SelectedRow(mRow) and Assigned(FOnRemove) then
  begin
    FOnRemove(mRow);
  end;
end;

procedure TAtlasEventFrame.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
  var DefaultDraw: Boolean);
begin
  if (Item.Index <= High(FRows)) and (FRows[Item.Index].Finding <> TAtlasEventFinding.None) then
  begin
    Sender.Canvas.Font.Color := FErrorColor;
  end;
end;

end.
