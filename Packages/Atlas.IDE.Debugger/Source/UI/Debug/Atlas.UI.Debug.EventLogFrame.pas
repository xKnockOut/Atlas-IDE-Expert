unit Atlas.UI.Debug.EventLogFrame;

// Inhalt des Seitenfensters „Ereignisprotokoll“ (#580), reine VCL: oben die
// Art („Alle Arten“ oder eine), der Filter (Wörter oder /Ausdruck/, gemerkte
// Filter des Projekts in der Auswahl) und „Filter merken“, darunter die
// virtuelle Liste mit Zeit (relativ zum Start), Art, Thread und Text, Farben
// nach debug.eventLogColors. Unten die Summe bzw. der Hinweis auf einen
// ungültigen Ausdruck. Neue Einträge rollen die Liste mit, solange keine
// Zeile gewählt ist.
// Bedienung: Doppelklick oder Enter springt zum Quelltext (OnOpen), Strg+C
// kopiert die Zeile. Kontextmenü: Springen, Kopieren, Als Textdatei speichern
// (OnSave), Gemerkten Filter entfernen (OnForgetFilter), Leeren (OnClear).
// Die IDE-Schicht hält das Protokoll und ruft nach Änderungen Refill. Die DFM
// ist leer, weil TCustomFrame.Create für abgeleitete Frames eine Ressource
// verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Core.Debug.EventLog;

type
  TAtlasDebugEventLogFrame = class(TFrame)
  private type
    /// <summary>Kontextmenü der Liste: Springen, Kopieren, Speichern, gemerkten Filter entfernen, Leeren.</summary>
    TListMenu = class(TPopupMenu)
    private
      FFrame: TAtlasDebugEventLogFrame;
      FOpenItem: TMenuItem;
      FCopyItem: TMenuItem;
      FSaveItem: TMenuItem;
      FForgetItem: TMenuItem;
      FClearItem: TMenuItem;
      function AddItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
      procedure MenuPopup(Sender: TObject);
      procedure OpenClick(Sender: TObject);
      procedure CopyClick(Sender: TObject);
      procedure SaveClick(Sender: TObject);
      procedure ForgetClick(Sender: TObject);
      procedure ClearClick(Sender: TObject);
    public
      constructor CreateFor(AFrame: TAtlasDebugEventLogFrame);
    end;
    /// <summary>Ereignisse an die IDE-Schicht.</summary>
    TEvents = record
      Open: TProc<TAtlasEventEntry>;
      Save: TProc;
      Clear: TProc;
      RememberFilter: TProc<string>;
      ForgetFilter: TProc<string>;
    end;
  private
    FKindBox: TComboBox;
    FFilter: TComboBox;
    FRemember: TButton;
    FList: TListView;
    FEmpty: TLabel;
    FSummary: TLabel;
    FMenu: TListMenu;
    FLog: TAtlasEventLog;
    FColors: TAtlasEventColors;
    FSavedFilters: TArray<string>;
    /// <summary>Indizes der gezeigten Einträge im Protokoll.</summary>
    FShown: TArray<Integer>;
    FEvents: TEvents;
    procedure CreateFilterBar;
    procedure CreateList;
    procedure FillKinds;
    procedure FillSavedFilters;
    function CurrentFilter: TAtlasEventFilter;
    procedure FilterChange(Sender: TObject);
    procedure RememberClick(Sender: TObject);
    function HasSavedFilter: Boolean;
    procedure ListData(Sender: TObject; Item: TListItem);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure RowColor(AItem: TListItem; AState: TCustomDrawState);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Protokoll (gehört der IDE-Schicht), Farben und gemerkte Filter des Projekts zeigen.</summary>
    procedure SetLog(ALog: TAtlasEventLog; const AColors: TAtlasEventColors; const ASavedFilters: TArray<string>);
    /// <summary>Liste neu filtern; Auswahl bleibt, ohne Auswahl rollt sie ans Ende.</summary>
    procedure Refill;
    /// <summary>Gewählter Eintrag; False ohne Auswahl.</summary>
    function TrySelected(out AEntry: TAtlasEventEntry): Boolean;
    procedure OpenSelected;
    procedure CopySelected;
    /// <summary>Name der Art für die Anzeige.</summary>
    class function KindCaption(AKind: TAtlasEventKind): string; static;
    /// <summary>Text der Spalten: Zeit, Art, Thread, Text.</summary>
    class function Cells(const AEntry: TAtlasEventEntry): TArray<string>; static;
    property OnOpen: TProc<TAtlasEventEntry> read FEvents.Open write FEvents.Open;
    property OnSave: TProc read FEvents.Save write FEvents.Save;
    property OnClear: TProc read FEvents.Clear write FEvents.Clear;
    property OnRememberFilter: TProc<string> read FEvents.RememberFilter write FEvents.RememberFilter;
    property OnForgetFilter: TProc<string> read FEvents.ForgetFilter write FEvents.ForgetFilter;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.CommCtrl,
  Vcl.Clipbrd,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.UI.Debug.Strings;

{$R *.dfm}

const
  // Maße in logischen Pixeln (96 dpi).
  cBarHeight = 30;
  cKindBoxWidth = 120;
  cRememberWidth = 100;
  cTimeWidth = 80;
  cKindWidth = 80;
  cThreadWidth = 60;
  cTextWidth = 520;
  cKindTexts: array[TAtlasEventKind] of TAtlasDebugTextId = (TAtlasDebugTextId.DebugEventLogKindOutput,
    TAtlasDebugTextId.DebugEventLogKindBreakpoint, TAtlasDebugTextId.DebugEventLogKindModule,
    TAtlasDebugTextId.DebugEventLogKindThread, TAtlasDebugTextId.DebugEventLogKindProcess,
    TAtlasDebugTextId.DebugEventLogKindLogpoint, TAtlasDebugTextId.DebugEventLogKindOther);

/// <summary>Spalte mit ACaption und AWidth (logische Pixel) an AList.</summary>
procedure AddColumn(AList: TListView; const ACaption: string; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := ACaption;
  mColumn.Width := MulDiv(AWidth, AList.CurrentPPI, 96);
end;

constructor TAtlasDebugEventLogFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  CreateFilterBar;
  FSummary := TLabel.Create(Self);
  FSummary.Parent := Self;
  FSummary.Align := alBottom;
  FSummary.AlignWithMargins := True;
  FSummary.ShowAccelChar := False;
  FSummary.Font.Color := clGrayText;
  FSummary.Caption := '';
  FMenu := TListMenu.CreateFor(Self);
  CreateList;
  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := Self;
  FEmpty.Align := alClient;
  FEmpty.AlignWithMargins := True;
  FEmpty.ShowAccelChar := False;
  FEmpty.Font.Color := clGrayText;
  FEmpty.WordWrap := True;
  FEmpty.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogEmpty);
  FEmpty.Visible := False;
end;

procedure TAtlasDebugEventLogFrame.CreateFilterBar;
var
  mTop: TPanel;
begin
  mTop := TPanel.Create(Self);
  mTop.Top := 0;
  mTop.Height := MulDiv(cBarHeight, CurrentPPI, 96);
  mTop.Align := alTop;
  mTop.Parent := Self;
  mTop.BevelOuter := bvNone;
  mTop.ShowCaption := False;
  mTop.ParentBackground := True;

  FKindBox := TComboBox.Create(Self);
  FKindBox.Parent := mTop;
  FKindBox.Align := alLeft;
  FKindBox.AlignWithMargins := True;
  FKindBox.Style := csDropDownList;
  FKindBox.Width := MulDiv(cKindBoxWidth, CurrentPPI, 96);
  FKindBox.OnChange := FilterChange;

  FRemember := TButton.Create(Self);
  FRemember.Parent := mTop;
  FRemember.Align := alRight;
  FRemember.AlignWithMargins := True;
  FRemember.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogRememberFilter);
  FRemember.Width := MulDiv(cRememberWidth, CurrentPPI, 96);
  FRemember.OnClick := RememberClick;

  FFilter := TComboBox.Create(Self);
  FFilter.Parent := mTop;
  FFilter.Align := alClient;
  FFilter.AlignWithMargins := True;
  FFilter.Style := csDropDown;
  FFilter.TextHint := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogFilterHint);
  FFilter.OnChange := FilterChange;
end;

procedure TAtlasDebugEventLogFrame.CreateList;
begin
  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.OwnerData := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := True;
  FList.MultiSelect := False;
  FList.ColumnClick := False;
  FList.PopupMenu := FMenu;
  AddColumn(FList, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogColumnTime), cTimeWidth);
  AddColumn(FList, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogColumnKind), cKindWidth);
  AddColumn(FList, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogColumnThread), cThreadWidth);
  AddColumn(FList, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogColumnText), cTextWidth);
  FList.OnData := ListData;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  FList.OnCustomDrawSubItem := ListCustomDrawSubItem;
end;

{ TAtlasDebugEventLogFrame.TListMenu }

constructor TAtlasDebugEventLogFrame.TListMenu.CreateFor(AFrame: TAtlasDebugEventLogFrame);
begin
  inherited Create(AFrame);
  FFrame := AFrame;
  OnPopup := MenuPopup;
  FOpenItem := AddItem(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogGoTo), OpenClick);
  FOpenItem.Default := True;
  FCopyItem := AddItem(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogCopy), CopyClick);
  FSaveItem := AddItem(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogSave), SaveClick);
  FForgetItem := AddItem(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogForgetFilter), ForgetClick);
  FClearItem := AddItem(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogClear), ClearClick);
end;

function TAtlasDebugEventLogFrame.TListMenu.AddItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(Self);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Items.Add(Result);
end;

procedure TAtlasDebugEventLogFrame.TListMenu.MenuPopup(Sender: TObject);
var
  mEntry: TAtlasEventEntry;
  mHas, mAny: Boolean;
begin
  mHas := FFrame.TrySelected(mEntry);
  mAny := (FFrame.FLog <> nil) and (FFrame.FLog.Count > 0);
  FOpenItem.Enabled := mHas and (TAtlasEventJump.Find(mEntry.Text).Kind <> TAtlasEventJumpKind.None);
  FCopyItem.Enabled := mHas;
  FSaveItem.Enabled := mAny;
  FForgetItem.Visible := FFrame.HasSavedFilter;
  FClearItem.Enabled := mAny;
end;

procedure TAtlasDebugEventLogFrame.TListMenu.OpenClick(Sender: TObject);
begin
  FFrame.OpenSelected;
end;

procedure TAtlasDebugEventLogFrame.TListMenu.CopyClick(Sender: TObject);
begin
  FFrame.CopySelected;
end;

procedure TAtlasDebugEventLogFrame.TListMenu.SaveClick(Sender: TObject);
begin
  if Assigned(FFrame.FEvents.Save) then
  begin
    FFrame.FEvents.Save();
  end;
end;

procedure TAtlasDebugEventLogFrame.TListMenu.ForgetClick(Sender: TObject);
begin
  if Assigned(FFrame.FEvents.ForgetFilter) then
  begin
    FFrame.FEvents.ForgetFilter(Trim(FFrame.FFilter.Text));
  end;
end;

procedure TAtlasDebugEventLogFrame.TListMenu.ClearClick(Sender: TObject);
begin
  if Assigned(FFrame.FEvents.Clear) then
  begin
    FFrame.FEvents.Clear();
  end;
end;

{ TAtlasDebugEventLogFrame }

procedure TAtlasDebugEventLogFrame.CreateWnd;
begin
  inherited CreateWnd;
  // Auswahllisten und Items.Count der virtuellen Liste brauchen ein Fenster.
  FillKinds;
  FillSavedFilters;
  Refill;
end;

procedure TAtlasDebugEventLogFrame.FillKinds;
var
  mKind: TAtlasEventKind;
  mKeep: Integer;
begin
  if not HandleAllocated then
  begin
    Exit;
  end;
  mKeep := FKindBox.ItemIndex;
  FKindBox.Items.BeginUpdate;
  try
    FKindBox.Items.Clear;
    FKindBox.Items.Add(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogKindAll));
    for mKind := Low(TAtlasEventKind) to High(TAtlasEventKind) do
    begin
      FKindBox.Items.Add(KindCaption(mKind));
    end;
  finally
    FKindBox.Items.EndUpdate;
  end;
  if mKeep < 0 then
  begin
    mKeep := 0;
  end;
  FKindBox.ItemIndex := mKeep;
end;

procedure TAtlasDebugEventLogFrame.FillSavedFilters;
var
  mText: string;
  mFilter: string;
begin
  if not HandleAllocated then
  begin
    Exit;
  end;
  mText := FFilter.Text;
  FFilter.Items.BeginUpdate;
  try
    FFilter.Items.Clear;
    for mFilter in FSavedFilters do
    begin
      FFilter.Items.Add(mFilter);
    end;
  finally
    FFilter.Items.EndUpdate;
  end;
  FFilter.Text := mText;
end;

class function TAtlasDebugEventLogFrame.KindCaption(AKind: TAtlasEventKind): string;
begin
  Result := TAtlasDebugStrings.Text(cKindTexts[AKind]);
end;

class function TAtlasDebugEventLogFrame.Cells(const AEntry: TAtlasEventEntry): TArray<string>;
begin
  Result := TArray<string>.Create(AEntry.TimeText, KindCaption(AEntry.Kind), AEntry.Thread, AEntry.Text);
end;

procedure TAtlasDebugEventLogFrame.SetLog(ALog: TAtlasEventLog; const AColors: TAtlasEventColors;
  const ASavedFilters: TArray<string>);
begin
  FLog := ALog;
  FColors := AColors;
  FSavedFilters := ASavedFilters;
  FillSavedFilters;
  Refill;
end;

function TAtlasDebugEventLogFrame.CurrentFilter: TAtlasEventFilter;
var
  mKinds: TAtlasEventKinds;
begin
  mKinds := TAtlasEventLog.cAllKinds;
  if FKindBox.ItemIndex > 0 then
  begin
    mKinds := [TAtlasEventKind(FKindBox.ItemIndex - 1)];
  end;
  Result := TAtlasEventFilter.Create(FFilter.Text, mKinds);
end;

procedure TAtlasDebugEventLogFrame.Refill;
var
  mFilter: TAtlasEventFilter;
  mSelected, mIndex, mTotal: Integer;
begin
  // Items.Count der virtuellen Liste braucht ein Fenster (CreateWnd ruft erneut).
  if not FList.HandleAllocated then
  begin
    Exit;
  end;
  mSelected := -1;
  if (FList.Selected <> nil) and (FList.Selected.Index <= High(FShown)) then
  begin
    mSelected := FShown[FList.Selected.Index];
  end;
  mFilter := CurrentFilter;
  FShown := nil;
  mTotal := 0;
  if FLog <> nil then
  begin
    FShown := FLog.Filter(mFilter);
    mTotal := FLog.Count;
  end;
  FList.Items.Count := Length(FShown);
  ListView_SetItemState(FList.Handle, -1, 0, LVIS_SELECTED);
  for mIndex := 0 to High(FShown) do
  begin
    if FShown[mIndex] = mSelected then
    begin
      FList.Items[mIndex].Selected := True;
      FList.Items[mIndex].MakeVisible(False);
    end;
  end;
  if (mSelected < 0) and (Length(FShown) > 0) then
  begin
    // Ohne Auswahl rollt die Liste mit.
    FList.Items[High(FShown)].MakeVisible(False);
  end;
  FList.Invalidate;
  FEmpty.Visible := mTotal = 0;
  FList.Visible := mTotal > 0;
  if not mFilter.Valid then
  begin
    FSummary.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugEventLogInvalidRegex);
  end
  else
  begin
    FSummary.Caption := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugEventLogSummary, [Length(FShown), mTotal]);
  end;
end;

function TAtlasDebugEventLogFrame.TrySelected(out AEntry: TAtlasEventEntry): Boolean;
begin
  Result := (FLog <> nil) and (FList.Selected <> nil) and (FList.Selected.Index <= High(FShown)) and
    (FShown[FList.Selected.Index] < FLog.Count);
  if Result then
  begin
    AEntry := FLog[FShown[FList.Selected.Index]];
  end
  else
  begin
    AEntry := Default(TAtlasEventEntry);
  end;
end;

procedure TAtlasDebugEventLogFrame.OpenSelected;
var
  mEntry: TAtlasEventEntry;
begin
  if TrySelected(mEntry) and Assigned(FEvents.Open) then
  begin
    FEvents.Open(mEntry);
  end;
end;

procedure TAtlasDebugEventLogFrame.CopySelected;
var
  mEntry: TAtlasEventEntry;
begin
  if TrySelected(mEntry) then
  begin
    Clipboard.AsText := mEntry.Text;
  end;
end;

procedure TAtlasDebugEventLogFrame.FilterChange(Sender: TObject);
begin
  Refill;
end;

procedure TAtlasDebugEventLogFrame.RememberClick(Sender: TObject);
begin
  if (Trim(FFilter.Text) <> '') and Assigned(FEvents.RememberFilter) then
  begin
    FEvents.RememberFilter(Trim(FFilter.Text));
  end;
end;

function TAtlasDebugEventLogFrame.HasSavedFilter: Boolean;
var
  mFilter: string;
begin
  Result := False;
  for mFilter in FSavedFilters do
  begin
    Result := Result or SameText(mFilter, Trim(FFilter.Text));
  end;
end;

procedure TAtlasDebugEventLogFrame.ListData(Sender: TObject; Item: TListItem);
var
  mTexts: TArray<string>;
  mPart: Integer;
begin
  if (FLog = nil) or (Item.Index > High(FShown)) or (FShown[Item.Index] >= FLog.Count) then
  begin
    Exit;
  end;
  mTexts := Cells(FLog[FShown[Item.Index]]);
  Item.Caption := mTexts[0];
  for mPart := 1 to High(mTexts) do
  begin
    Item.SubItems.Add(mTexts[mPart]);
  end;
end;

procedure TAtlasDebugEventLogFrame.ListDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TAtlasDebugEventLogFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    OpenSelected;
    Key := 0;
  end
  else if (Key = Ord('C')) and (ssCtrl in Shift) then
  begin
    CopySelected;
    Key := 0;
  end;
end;

procedure TAtlasDebugEventLogFrame.RowColor(AItem: TListItem; AState: TCustomDrawState);
var
  mColor: TAtlasColor;
begin
  if (cdsSelected in AState) or (FLog = nil) or (AItem = nil) or (AItem.Index > High(FShown)) or
    (FShown[AItem.Index] >= FLog.Count) then
  begin
    Exit;
  end;
  if FColors.TryColorOf(FLog[FShown[AItem.Index]].Text, mColor) then
  begin
    FList.Canvas.Font.Color := TColor(mColor);
  end
  else
  begin
    FList.Canvas.Font.Color := StyleServices(FList).GetSystemColor(clWindowText);
  end;
end;

procedure TAtlasDebugEventLogFrame.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  RowColor(Item, State);
end;

procedure TAtlasDebugEventLogFrame.ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  RowColor(Item, State);
end;

end.
