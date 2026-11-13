unit Atlas.UI.Debug.BreakpointsFrame;

// Inhalt des Haltepunktfensters (#863): oben Suche, Gruppierung und „Zähler
// zurücksetzen“, darunter die Filterchips und die Zeile für Etiketten (mit
// Vervollständigung der schon benutzten), dann die Liste mit auf- und
// zuklappbaren Gruppen, unten die Zusammenfassung.
// Die Liste zeigt, was die IDE-Schicht mit SetRows liefert; Suche, Chips und
// Gruppierung wendet der Frame selbst an (Atlas.Core.Debug.BreakpointList).
// Befehle gehen mit den gewählten Zeilen an die IDE-Schicht (On…), die die
// Haltepunkte der IDE ändert und danach SetRows mit dem neuen Stand ruft.
// Tasten in der Liste: Enter Eigenschaften der IDE, Leertaste ein/aus, Entf
// löschen, Strg+Z rückgängig; Doppelklick springt zur Stelle.
// Spalten: ein- und ausblendbar (Kontextmenü „Spalten“), Breite und
// Reihenfolge (Kopf ziehen) liest Columns für die IDE-Schicht zurück.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.ComCtrls,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Core.Debug.BreakpointList;

type
  TAtlasBreakpointRowsEvent = reference to procedure(const ARows: TArray<TAtlasBreakpointRow>);
  TAtlasBreakpointToggleEvent = reference to procedure(const ARows: TArray<TAtlasBreakpointRow>; AEnable: Boolean);
  TAtlasBreakpointTagEvent = reference to procedure(const ARows: TArray<TAtlasBreakpointRow>; const ATag: string;
    AAdd: Boolean);

  /// <summary>Texte der Zellen und Gruppen, ohne Steuerelemente (testbar).</summary>
  TAtlasBreakpointTexts = class
  public
    class function Cell(const ARow: TAtlasBreakpointRow; AColumn: TAtlasBreakpointColumn; AHasRun: Boolean): string;
      static;
    class function ColumnCaption(AColumn: TAtlasBreakpointColumn): string; static;
    /// <summary>Überschrift einer Gruppe; leere Überschrift als „(ohne Etikett)“ bzw. „(ohne Gruppe)“.</summary>
    class function GroupCaption(const ACaption: string; AGrouping: TAtlasBreakpointGrouping; ACount: Integer): string;
      static;
    class function Summary(AShown, ATotal: Integer; AHasRun: Boolean): string; static;
  end;

  /// <summary>Befehle des Haltepunktfensters an die IDE-Schicht; die Ereignisse bekommen die gewählten
  /// Haltepunkte.</summary>
  TAtlasBreakpointsFrameEvents = class
  private
    FToggle: TAtlasBreakpointToggleEvent;
    FDelete: TAtlasBreakpointRowsEvent;
    FOpen: TAtlasBreakpointRowsEvent;
    FProperties: TAtlasBreakpointRowsEvent;
    FTag: TAtlasBreakpointTagEvent;
    FUndo: TProc;
    FResetHits: TProc;
  public
    property OnToggle: TAtlasBreakpointToggleEvent read FToggle write FToggle;
    property OnDelete: TAtlasBreakpointRowsEvent read FDelete write FDelete;
    property OnOpen: TAtlasBreakpointRowsEvent read FOpen write FOpen;
    property OnProperties: TAtlasBreakpointRowsEvent read FProperties write FProperties;
    property OnTag: TAtlasBreakpointTagEvent read FTag write FTag;
    property OnUndo: TProc read FUndo write FUndo;
    property OnResetHits: TProc read FResetHits write FResetHits;
  end;

  TAtlasDebugBreakpointsFrame = class(TFrame)
  private type
    TControls = record
      Search: TEdit;
      Grouping: TComboBox;
      ResetHits: TButton;
      Chips: array[TAtlasBreakpointFilter] of TCheckBox;
      Tag: TComboBox;
      AddTag: TButton;
      RemoveTag: TButton;
      List: TListView;
      Summary: TLabel;
      Menu: TPopupMenu;
      UndoItem: TMenuItem;
      ColumnItems: array[TAtlasBreakpointColumn] of TMenuItem;
    end;
    TState = record
      Rows: TArray<TAtlasBreakpointRow>;
      Columns: TAtlasBreakpointColumns;
      HasRun: Boolean;
      UndoCount: Integer;
      Filling: Boolean;
    end;
  private
    FControls: TControls;
    FEvents: TAtlasBreakpointsFrameEvents;
    FState: TState;
    procedure BuildColumns;
    procedure CaptureColumns;
    procedure Fill;
    procedure FillKeeping(ASelected: TStrings);
    procedure AddItems(const AEntry: TAtlasBreakpointGroupEntry; AGroupId: Integer; ASelected: TStrings);
    procedure UpdateCommands;
    function SelectedKeys: TStrings;
    function CurrentFilters: TAtlasBreakpointFilters;
    procedure FilterChanged(Sender: TObject);
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    function GetColumns: TAtlasBreakpointColumns;
    procedure SetColumns(const AValue: TAtlasBreakpointColumns);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Neuer Stand der Haltepunkte; AHasRun: Lief schon eine Sitzung (sonst bleibt „Treffer“ leer)?
    /// Die Auswahl bleibt erhalten, soweit die Haltepunkte noch da sind.</summary>
    procedure SetRows(const ARows: TArray<TAtlasBreakpointRow>; AHasRun: Boolean);
    /// <summary>Schon benutzte Etiketten für die Vervollständigung.</summary>
    procedure SetKnownTags(const ATags: TArray<string>);
    /// <summary>Zahl der gelöschten Haltepunkte, die „Rückgängig“ zurückholt; 0 = nichts.</summary>
    procedure SetUndoCount(ACount: Integer);
    /// <summary>Gewählte Zeilen (ohne Doppel, wenn eine Zeile in zwei Gruppen steht).</summary>
    function SelectedRows: TArray<TAtlasBreakpointRow>;
    /// <summary>Zeilen, die Suche und Chips gerade zeigen (in der Reihenfolge von SetRows).</summary>
    function ShownRows: TArray<Integer>;
    function CurrentGrouping: TAtlasBreakpointGrouping;
    procedure SetGrouping(AGrouping: TAtlasBreakpointGrouping);
    /// <summary>Etikett aus dem Feld an den gewählten Haltepunkten setzen (AAdd) bzw. entfernen.</summary>
    procedure TagSelected(AAdd: Boolean);
    /// <summary>Filterchip ein- oder ausschalten; die Liste folgt sofort.</summary>
    procedure SetChip(AFilter: TAtlasBreakpointFilter; AChecked: Boolean);
    property Search: TEdit read FControls.Search;
    property Grouping: TComboBox read FControls.Grouping;
    property TagBox: TComboBox read FControls.Tag;
    property List: TListView read FControls.List;
    property SummaryLabel: TLabel read FControls.Summary;
    /// <summary>Spalten mit Breite und Reihenfolge, wie sie gerade stehen.</summary>
    property Columns: TAtlasBreakpointColumns read GetColumns write SetColumns;
    property Events: TAtlasBreakpointsFrameEvents read FEvents;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.CommCtrl,
  Atlas.UI.Debug.Strings;

{$R *.dfm}

const
  cEnabledMark = '✓';
  cDisabledMark = '–';
  cKeySeparator = '|';
  cTagSeparator = ', ';
  cBarHeight = 30;
  cButtonWidth = 120;
  cGroupingWidth = 140;
  cTagWidth = 160;
  cDefaultPpi = 96;
  // Trennlinie im Menü.
  cLine = '-';
  cColumnTexts: array[TAtlasBreakpointColumn] of TAtlasDebugTextId = (TAtlasDebugTextId.BreakpointsColumnEnabled,
    TAtlasDebugTextId.BreakpointsColumnLocation, TAtlasDebugTextId.BreakpointsColumnCondition,
    TAtlasDebugTextId.BreakpointsColumnPassCount, TAtlasDebugTextId.BreakpointsColumnHits,
    TAtlasDebugTextId.BreakpointsColumnTags, TAtlasDebugTextId.BreakpointsColumnGroup,
    TAtlasDebugTextId.BreakpointsColumnSet);
  cChipTexts: array[TAtlasBreakpointFilter] of TAtlasDebugTextId = (TAtlasDebugTextId.BreakpointsChipActive,
    TAtlasDebugTextId.BreakpointsChipCondition, TAtlasDebugTextId.BreakpointsChipNeverHit,
    TAtlasDebugTextId.BreakpointsChipNotEffective);
  cGroupingTexts: array[TAtlasBreakpointGrouping] of TAtlasDebugTextId = (TAtlasDebugTextId.BreakpointsGroupNone,
    TAtlasDebugTextId.BreakpointsGroupByTag, TAtlasDebugTextId.BreakpointsGroupByFile,
    TAtlasDebugTextId.BreakpointsGroupByGroup);

function RowKey(const ARow: TAtlasBreakpointRow): string;
begin
  Result := ARow.FileName.ToLower + cKeySeparator + IntToStr(ARow.Line);
end;

{ TAtlasBreakpointTexts }

class function TAtlasBreakpointTexts.Cell(const ARow: TAtlasBreakpointRow; AColumn: TAtlasBreakpointColumn;
  AHasRun: Boolean): string;
begin
  case AColumn of
    TAtlasBreakpointColumn.Enabled:
      begin
        Result := cDisabledMark;
        if ARow.Enabled then
        begin
          Result := cEnabledMark;
        end;
      end;
    TAtlasBreakpointColumn.Location:
      Result := ARow.Location;
    TAtlasBreakpointColumn.Condition:
      Result := ARow.Condition;
    TAtlasBreakpointColumn.PassCount:
      begin
        Result := '';
        if ARow.PassCount > 0 then
        begin
          Result := IntToStr(ARow.PassCount);
        end;
      end;
    TAtlasBreakpointColumn.Hits:
      begin
        Result := '';
        if AHasRun then
        begin
          Result := IntToStr(ARow.Hits);
        end;
      end;
    TAtlasBreakpointColumn.Tags:
      Result := string.Join(cTagSeparator, ARow.Tags);
    TAtlasBreakpointColumn.Group:
      Result := ARow.Group;
  else
    Result := ARow.SetName;
  end;
end;

class function TAtlasBreakpointTexts.ColumnCaption(AColumn: TAtlasBreakpointColumn): string;
begin
  Result := TAtlasDebugStrings.Text(cColumnTexts[AColumn]);
end;

class function TAtlasBreakpointTexts.GroupCaption(const ACaption: string; AGrouping: TAtlasBreakpointGrouping;
  ACount: Integer): string;
begin
  Result := ACaption;
  if Result = '' then
  begin
    Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsWithoutGroup);
    if AGrouping = TAtlasBreakpointGrouping.ByTag then
    begin
      Result := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsWithoutTag);
    end;
  end;
  Result := Format('%s (%d)', [Result, ACount]);
end;

class function TAtlasBreakpointTexts.Summary(AShown, ATotal: Integer; AHasRun: Boolean): string;
begin
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointsSummary, [AShown, ATotal]);
  if not AHasRun then
  begin
    Result := Result + ' · ' + TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsHitsNoSession);
  end;
end;

type
  /// <summary>Knöpfe, Menü und Tasten der Liste; gehört dem Frame (Besitzer) und gibt Befehle an dessen
  /// Ereignisse weiter.</summary>
  TBreakpointsActions = class(TComponent)
  private
    FFrame: TAtlasDebugBreakpointsFrame;
    procedure SendRows(const AEvent: TAtlasBreakpointRowsEvent);
    procedure SendToggle(AEnable: Boolean);
  public
    constructor CreateFor(AFrame: TAtlasDebugBreakpointsFrame);
    procedure ResetHitsClick(Sender: TObject);
    procedure AddTagClick(Sender: TObject);
    procedure RemoveTagClick(Sender: TObject);
    procedure EnableClick(Sender: TObject);
    procedure DisableClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure PropertiesClick(Sender: TObject);
    procedure ColumnItemClick(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  end;

{ Aufbau }

function ScaleLogical(AFrame: TCustomFrame; AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, AFrame.CurrentPPI, cDefaultPpi);
end;

function AddBar(AFrame: TAtlasDebugBreakpointsFrame; ATop: Integer): TPanel;
begin
  Result := TPanel.Create(AFrame);
  Result.Top := ATop;
  Result.Height := ScaleLogical(AFrame, cBarHeight);
  Result.Align := alTop;
  Result.Parent := AFrame;
  Result.BevelOuter := bvNone;
  Result.ShowCaption := False;
  Result.ParentBackground := True;
end;

function AddButton(AFrame: TAtlasDebugBreakpointsFrame; AParent: TWinControl; AText: TAtlasDebugTextId;
  AClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AFrame);
  Result.Parent := AParent;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := ScaleLogical(AFrame, cButtonWidth);
  Result.Caption := TAtlasDebugStrings.Text(AText);
  Result.OnClick := AClick;
end;

function AddMenuItem(AFrame: TAtlasDebugBreakpointsFrame; AParent: TMenuItem; const ACaption: string;
  AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AFrame);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  AParent.Add(Result);
end;

procedure CreateTopBar(AFrame: TAtlasDebugBreakpointsFrame; AActions: TBreakpointsActions);
var
  mBar: TPanel;
begin
  mBar := AddBar(AFrame, 0);
  AFrame.FControls.ResetHits := AddButton(AFrame, mBar, TAtlasDebugTextId.BreakpointsResetHits,
    AActions.ResetHitsClick);
  AFrame.FControls.Grouping := TComboBox.Create(AFrame);
  AFrame.FControls.Grouping.Parent := mBar;
  AFrame.FControls.Grouping.Align := alRight;
  AFrame.FControls.Grouping.AlignWithMargins := True;
  AFrame.FControls.Grouping.Width := ScaleLogical(AFrame, cGroupingWidth);
  AFrame.FControls.Grouping.Style := csDropDownList;
  AFrame.FControls.Grouping.OnChange := AFrame.FilterChanged;
  AFrame.FControls.Search := TEdit.Create(AFrame);
  AFrame.FControls.Search.Parent := mBar;
  AFrame.FControls.Search.Align := alClient;
  AFrame.FControls.Search.AlignWithMargins := True;
  AFrame.FControls.Search.TextHint := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsSearchHint);
  AFrame.FControls.Search.OnChange := AFrame.FilterChanged;
  // Einträge erst mit Fenster (CreateWnd); bis dahin merkt Tag die Wahl.
  AFrame.FControls.Grouping.Tag := Ord(TAtlasBreakpointGrouping.None);
end;

procedure CreateChipBar(AFrame: TAtlasDebugBreakpointsFrame);
var
  mBar: TPanel;
  mFilter: TAtlasBreakpointFilter;
  mChip: TCheckBox;
begin
  mBar := AddBar(AFrame, ScaleLogical(AFrame, cBarHeight));
  for mFilter := High(TAtlasBreakpointFilter) downto Low(TAtlasBreakpointFilter) do
  begin
    mChip := TCheckBox.Create(AFrame);
    mChip.Parent := mBar;
    mChip.Align := alLeft;
    mChip.AlignWithMargins := True;
    mChip.Caption := TAtlasDebugStrings.Text(cChipTexts[mFilter]);
    mChip.Width := ScaleLogical(AFrame, cButtonWidth);
    mChip.OnClick := AFrame.FilterChanged;
    AFrame.FControls.Chips[mFilter] := mChip;
  end;
end;

procedure CreateTagBar(AFrame: TAtlasDebugBreakpointsFrame; AActions: TBreakpointsActions);
var
  mBar: TPanel;
begin
  mBar := AddBar(AFrame, 2 * ScaleLogical(AFrame, cBarHeight));
  AFrame.FControls.RemoveTag := AddButton(AFrame, mBar, TAtlasDebugTextId.BreakpointsRemoveTag,
    AActions.RemoveTagClick);
  AFrame.FControls.AddTag := AddButton(AFrame, mBar, TAtlasDebugTextId.BreakpointsAddTag, AActions.AddTagClick);
  AFrame.FControls.Tag := TComboBox.Create(AFrame);
  AFrame.FControls.Tag.Parent := mBar;
  AFrame.FControls.Tag.Align := alRight;
  AFrame.FControls.Tag.AlignWithMargins := True;
  AFrame.FControls.Tag.Width := ScaleLogical(AFrame, cTagWidth);
  AFrame.FControls.Tag.Style := csDropDown;
  AFrame.FControls.Tag.AutoComplete := True;
  AFrame.FControls.Tag.TextHint := TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsTagHint);
end;

procedure CreateList(AFrame: TAtlasDebugBreakpointsFrame; AActions: TBreakpointsActions);
begin
  AFrame.FControls.Summary := TLabel.Create(AFrame);
  AFrame.FControls.Summary.Parent := AFrame;
  AFrame.FControls.Summary.Align := alBottom;
  AFrame.FControls.Summary.AlignWithMargins := True;
  AFrame.FControls.Summary.ShowAccelChar := False;
  AFrame.FControls.List := TListView.Create(AFrame);
  AFrame.FControls.List.Parent := AFrame;
  AFrame.FControls.List.Align := alClient;
  AFrame.FControls.List.AlignWithMargins := True;
  AFrame.FControls.List.ViewStyle := vsReport;
  AFrame.FControls.List.RowSelect := True;
  AFrame.FControls.List.MultiSelect := True;
  AFrame.FControls.List.ReadOnly := True;
  AFrame.FControls.List.HideSelection := False;
  AFrame.FControls.List.ColumnClick := False;
  // Spalten am Kopf verschieben (LVS_EX_HEADERDRAGDROP).
  AFrame.FControls.List.FullDrag := True;
  AFrame.FControls.List.OnKeyDown := AActions.ListKeyDown;
  AFrame.FControls.List.OnDblClick := AActions.OpenClick;
  AFrame.FControls.List.OnSelectItem := ListSelectItem;
end;

procedure CreateMenu(AFrame: TAtlasDebugBreakpointsFrame; AActions: TBreakpointsActions);
var
  mColumn: TAtlasBreakpointColumn;
  mItems, mColumns: TMenuItem;
begin
  AFrame.FControls.Menu := TPopupMenu.Create(AFrame);
  AFrame.FControls.Menu.OnPopup := AActions.MenuPopup;
  mItems := AFrame.FControls.Menu.Items;
  AddMenuItem(AFrame, mItems, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsGoTo), AActions.OpenClick);
  AddMenuItem(AFrame, mItems, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsProperties),
    AActions.PropertiesClick);
  AddMenuItem(AFrame, mItems, cLine, nil);
  AddMenuItem(AFrame, mItems, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsEnable), AActions.EnableClick);
  AddMenuItem(AFrame, mItems, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsDisable), AActions.DisableClick);
  AddMenuItem(AFrame, mItems, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsDelete), AActions.DeleteClick);
  AFrame.FControls.UndoItem := AddMenuItem(AFrame, mItems, '', AActions.UndoClick);
  AddMenuItem(AFrame, mItems, cLine, nil);
  mColumns := AddMenuItem(AFrame, mItems, TAtlasDebugStrings.Text(TAtlasDebugTextId.BreakpointsColumns), nil);
  for mColumn := Low(TAtlasBreakpointColumn) to High(TAtlasBreakpointColumn) do
  begin
    AFrame.FControls.ColumnItems[mColumn] := AddMenuItem(AFrame, mColumns,
      TAtlasBreakpointTexts.ColumnCaption(mColumn), AActions.ColumnItemClick);
    AFrame.FControls.ColumnItems[mColumn].Tag := Ord(mColumn);
  end;
  AFrame.FControls.List.PopupMenu := AFrame.FControls.Menu;
end;

{ TBreakpointsActions }

constructor TBreakpointsActions.CreateFor(AFrame: TAtlasDebugBreakpointsFrame);
begin
  inherited Create(AFrame);
  FFrame := AFrame;
end;

procedure TBreakpointsActions.SendRows(const AEvent: TAtlasBreakpointRowsEvent);
var
  mRows: TArray<TAtlasBreakpointRow>;
begin
  mRows := FFrame.SelectedRows;
  if (Length(mRows) > 0) and Assigned(AEvent) then
  begin
    AEvent(mRows);
  end;
end;

procedure TBreakpointsActions.SendToggle(AEnable: Boolean);
var
  mRows: TArray<TAtlasBreakpointRow>;
  mEvent: TAtlasBreakpointToggleEvent;
begin
  mRows := FFrame.SelectedRows;
  mEvent := FFrame.Events.OnToggle;
  if (Length(mRows) > 0) and Assigned(mEvent) then
  begin
    mEvent(mRows, AEnable);
  end;
end;

procedure TBreakpointsActions.ResetHitsClick(Sender: TObject);
var
  mEvent: TProc;
begin
  mEvent := FFrame.Events.OnResetHits;
  if Assigned(mEvent) then
  begin
    mEvent();
  end;
end;

procedure TBreakpointsActions.AddTagClick(Sender: TObject);
begin
  FFrame.TagSelected(True);
end;

procedure TBreakpointsActions.RemoveTagClick(Sender: TObject);
begin
  FFrame.TagSelected(False);
end;

procedure TBreakpointsActions.EnableClick(Sender: TObject);
begin
  SendToggle(True);
end;

procedure TBreakpointsActions.DisableClick(Sender: TObject);
begin
  SendToggle(False);
end;

procedure TBreakpointsActions.DeleteClick(Sender: TObject);
begin
  SendRows(FFrame.Events.OnDelete);
end;

procedure TBreakpointsActions.UndoClick(Sender: TObject);
var
  mEvent: TProc;
begin
  mEvent := FFrame.Events.OnUndo;
  if (FFrame.FState.UndoCount > 0) and Assigned(mEvent) then
  begin
    mEvent();
  end;
end;

procedure TBreakpointsActions.OpenClick(Sender: TObject);
begin
  SendRows(FFrame.Events.OnOpen);
end;

procedure TBreakpointsActions.PropertiesClick(Sender: TObject);
begin
  SendRows(FFrame.Events.OnProperties);
end;

procedure TBreakpointsActions.ColumnItemClick(Sender: TObject);
var
  mColumn: TAtlasBreakpointColumn;
begin
  FFrame.CaptureColumns;
  mColumn := TAtlasBreakpointColumn(TMenuItem(Sender).Tag);
  FFrame.FState.Columns.SetVisible(mColumn, not FFrame.FState.Columns.IsVisible(mColumn));
  FFrame.BuildColumns;
  FFrame.Fill;
end;

procedure TBreakpointsActions.MenuPopup(Sender: TObject);
var
  mColumn: TAtlasBreakpointColumn;
begin
  for mColumn := Low(TAtlasBreakpointColumn) to High(TAtlasBreakpointColumn) do
  begin
    FFrame.FControls.ColumnItems[mColumn].Checked := FFrame.FState.Columns.IsVisible(mColumn);
  end;
end;

procedure TBreakpointsActions.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mRows: TArray<TAtlasBreakpointRow>;
begin
  case Key of
    VK_RETURN:
      PropertiesClick(Sender);
    VK_DELETE:
      DeleteClick(Sender);
    VK_SPACE:
      begin
        mRows := FFrame.SelectedRows;
        if Length(mRows) > 0 then
        begin
          SendToggle(not mRows[0].Enabled);
        end;
      end;
    Ord('Z'):
      begin
        if ssCtrl in Shift then
        begin
          UndoClick(Sender);
        end;
        Exit;
      end;
  else
    Exit;
  end;
  Key := 0;
end;

{ TAtlasDebugBreakpointsFrame }

constructor TAtlasDebugBreakpointsFrame.Create(AOwner: TComponent);
var
  mActions: TBreakpointsActions;
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FState.Columns := TAtlasBreakpointColumns.Default;
  FEvents := TAtlasBreakpointsFrameEvents.Create;
  mActions := TBreakpointsActions.CreateFor(Self);
  // Von oben nach unten (alTop ordnet nach Top); die Liste füllt den Rest.
  CreateTopBar(Self, mActions);
  CreateChipBar(Self);
  CreateTagBar(Self, mActions);
  CreateList(Self, mActions);
  CreateMenu(Self, mActions);
  SetUndoCount(0);
end;

destructor TAtlasDebugBreakpointsFrame.Destroy;
begin
  FreeAndNil(FEvents);
  inherited Destroy;
end;

procedure TAtlasDebugBreakpointsFrame.CreateWnd;
var
  mGrouping: TAtlasBreakpointGrouping;
begin
  inherited CreateWnd;
  // Combobox und Liste brauchen ein Fenster.
  if FControls.Grouping.Items.Count = 0 then
  begin
    FControls.Grouping.Items.BeginUpdate;
    try
      for mGrouping := Low(TAtlasBreakpointGrouping) to High(TAtlasBreakpointGrouping) do
      begin
        FControls.Grouping.Items.Add(TAtlasDebugStrings.Text(cGroupingTexts[mGrouping]));
      end;
    finally
      FControls.Grouping.Items.EndUpdate;
    end;
    FControls.Grouping.ItemIndex := FControls.Grouping.Tag;
  end;
  BuildColumns;
  Fill;
end;

function TAtlasDebugBreakpointsFrame.CurrentFilters: TAtlasBreakpointFilters;
var
  mFilter: TAtlasBreakpointFilter;
begin
  Result := [];
  for mFilter := Low(TAtlasBreakpointFilter) to High(TAtlasBreakpointFilter) do
  begin
    if FControls.Chips[mFilter].Checked then
    begin
      Include(Result, mFilter);
    end;
  end;
end;

function TAtlasDebugBreakpointsFrame.CurrentGrouping: TAtlasBreakpointGrouping;
var
  mIndex: Integer;
begin
  mIndex := FControls.Grouping.ItemIndex;
  if mIndex < 0 then
  begin
    mIndex := FControls.Grouping.Tag;
  end;
  Result := TAtlasBreakpointGrouping(mIndex);
end;

function TAtlasDebugBreakpointsFrame.ShownRows: TArray<Integer>;
begin
  Result := TAtlasBreakpointView.Filter(FState.Rows, FControls.Search.Text, CurrentFilters);
end;

procedure TAtlasDebugBreakpointsFrame.BuildColumns;
var
  mInfo: TAtlasBreakpointColumnInfo;
  mColumn: TListColumn;
begin
  if not FControls.List.HandleAllocated then
  begin
    Exit;
  end;
  FControls.List.Columns.BeginUpdate;
  try
    FControls.List.Columns.Clear;
    for mInfo in FState.Columns.Items do
    begin
      if mInfo.Visible then
      begin
        mColumn := FControls.List.Columns.Add;
        mColumn.Caption := TAtlasBreakpointTexts.ColumnCaption(mInfo.Column);
        mColumn.Width := ScaleLogical(Self, mInfo.Width);
        mColumn.Tag := Ord(mInfo.Column);
      end;
    end;
  finally
    FControls.List.Columns.EndUpdate;
  end;
end;

procedure TAtlasDebugBreakpointsFrame.CaptureColumns;
var
  mOrder: array of Integer;
  mIndex: Integer;
  mColumn: TListColumn;
  mKind: TAtlasBreakpointColumn;
begin
  if not FControls.List.HandleAllocated or (FControls.List.Columns.Count = 0) then
  begin
    Exit;
  end;
  SetLength(mOrder, FControls.List.Columns.Count);
  if not ListView_GetColumnOrderArray(FControls.List.Handle, Length(mOrder), @mOrder[0]) then
  begin
    Exit;
  end;
  // Sichtbare Spalten in der Reihenfolge am Kopf nach vorn, mit ihrer Breite (logische Pixel).
  for mIndex := 0 to High(mOrder) do
  begin
    mColumn := FControls.List.Columns[mOrder[mIndex]];
    mKind := TAtlasBreakpointColumn(mColumn.Tag);
    FState.Columns.SetWidth(mKind, MulDiv(mColumn.Width, cDefaultPpi, CurrentPPI));
    FState.Columns.MoveTo(mKind, mIndex);
  end;
end;

function TAtlasDebugBreakpointsFrame.GetColumns: TAtlasBreakpointColumns;
begin
  CaptureColumns;
  Result := FState.Columns;
end;

procedure TAtlasDebugBreakpointsFrame.SetColumns(const AValue: TAtlasBreakpointColumns);
begin
  FState.Columns := TAtlasBreakpointColumns.Parse(AValue.ToText);
  BuildColumns;
  Fill;
end;

function TAtlasDebugBreakpointsFrame.SelectedKeys: TStrings;
var
  mItem: TListItem;
begin
  Result := TStringList.Create;
  TStringList(Result).Sorted := True;
  TStringList(Result).Duplicates := dupIgnore;
  if not FControls.List.HandleAllocated then
  begin
    Exit;
  end;
  mItem := FControls.List.Selected;
  while mItem <> nil do
  begin
    Result.Add(RowKey(FState.Rows[Integer(NativeInt(mItem.Data))]));
    mItem := FControls.List.GetNextItem(mItem, sdAll, [isSelected]);
  end;
end;

procedure TAtlasDebugBreakpointsFrame.AddItems(const AEntry: TAtlasBreakpointGroupEntry; AGroupId: Integer;
  ASelected: TStrings);
var
  mRow, mIndex: Integer;
  mItem: TListItem;
  mColumn: TListColumn;
  mText: string;
begin
  for mRow in AEntry.Rows do
  begin
    mItem := FControls.List.Items.Add;
    mItem.Data := Pointer(NativeInt(mRow));
    mItem.GroupID := AGroupId;
    for mIndex := 0 to FControls.List.Columns.Count - 1 do
    begin
      mColumn := FControls.List.Columns[mIndex];
      mText := TAtlasBreakpointTexts.Cell(FState.Rows[mRow], TAtlasBreakpointColumn(mColumn.Tag), FState.HasRun);
      if mIndex = 0 then
      begin
        mItem.Caption := mText;
      end
      else
      begin
        mItem.SubItems.Add(mText);
      end;
    end;
    mItem.Selected := ASelected.IndexOf(RowKey(FState.Rows[mRow])) >= 0;
  end;
end;

procedure TAtlasDebugBreakpointsFrame.Fill;
begin
  FillKeeping(SelectedKeys);
end;

/// <summary>Liste neu aufbauen; ASelected (Schlüssel der gewählten Haltepunkte) gibt sie danach frei.</summary>
procedure TAtlasDebugBreakpointsFrame.FillKeeping(ASelected: TStrings);
var
  mGroups: TArray<TAtlasBreakpointGroupEntry>;
  mGrouping: TAtlasBreakpointGrouping;
  mShown: TArray<Integer>;
  mIndex: Integer;
  mGroup: TListGroup;
begin
  if not FControls.List.HandleAllocated then
  begin
    ASelected.Free;
    Exit;
  end;
  mGrouping := CurrentGrouping;
  mShown := ShownRows;
  mGroups := TAtlasBreakpointView.Group(FState.Rows, mShown, mGrouping);
  FState.Filling := True;
  FControls.List.Items.BeginUpdate;
  try
    FControls.List.Items.Clear;
    FControls.List.Groups.Clear;
    FControls.List.GroupView := mGrouping <> TAtlasBreakpointGrouping.None;
    for mIndex := 0 to High(mGroups) do
    begin
      if FControls.List.GroupView then
      begin
        mGroup := FControls.List.Groups.Add;
        mGroup.GroupID := mIndex;
        mGroup.Header := TAtlasBreakpointTexts.GroupCaption(mGroups[mIndex].Caption, mGrouping,
          Length(mGroups[mIndex].Rows));
        mGroup.State := [lgsNormal, lgsCollapsible];
      end;
      AddItems(mGroups[mIndex], mIndex, ASelected);
    end;
  finally
    FControls.List.Items.EndUpdate;
    FState.Filling := False;
    ASelected.Free;
  end;
  FControls.Summary.Caption := TAtlasBreakpointTexts.Summary(Length(mShown), Length(FState.Rows), FState.HasRun);
  UpdateCommands;
end;

procedure TAtlasDebugBreakpointsFrame.SetRows(const ARows: TArray<TAtlasBreakpointRow>; AHasRun: Boolean);
var
  mSelected: TStrings;
begin
  // Auswahl vor dem Tausch merken: Die Einträge zeigen noch auf die alten Zeilen.
  mSelected := SelectedKeys;
  FState.Rows := Copy(ARows);
  FState.HasRun := AHasRun;
  FillKeeping(mSelected);
end;

procedure TAtlasDebugBreakpointsFrame.SetKnownTags(const ATags: TArray<string>);
var
  mText: string;
  mTag: string;
begin
  mText := FControls.Tag.Text;
  FControls.Tag.Items.BeginUpdate;
  try
    FControls.Tag.Items.Clear;
    for mTag in ATags do
    begin
      FControls.Tag.Items.Add(mTag);
    end;
  finally
    FControls.Tag.Items.EndUpdate;
  end;
  FControls.Tag.Text := mText;
end;

procedure TAtlasDebugBreakpointsFrame.SetUndoCount(ACount: Integer);
begin
  FState.UndoCount := ACount;
  FControls.UndoItem.Caption := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.BreakpointsUndo, [ACount]);
  FControls.UndoItem.Enabled := ACount > 0;
end;

function TAtlasDebugBreakpointsFrame.SelectedRows: TArray<TAtlasBreakpointRow>;
var
  mKeys: TStrings;
  mRow: TAtlasBreakpointRow;
begin
  Result := nil;
  mKeys := SelectedKeys;
  try
    for mRow in FState.Rows do
    begin
      if mKeys.IndexOf(RowKey(mRow)) >= 0 then
      begin
        Result := Result + [mRow];
      end;
    end;
  finally
    mKeys.Free;
  end;
end;

procedure TAtlasDebugBreakpointsFrame.UpdateCommands;
var
  mAny: Boolean;
begin
  mAny := FControls.List.HandleAllocated and (FControls.List.SelCount > 0);
  FControls.AddTag.Enabled := mAny;
  FControls.RemoveTag.Enabled := mAny;
end;

procedure TAtlasDebugBreakpointsFrame.FilterChanged(Sender: TObject);
begin
  if Sender = FControls.Grouping then
  begin
    FControls.Grouping.Tag := FControls.Grouping.ItemIndex;
  end;
  Fill;
end;

procedure TAtlasDebugBreakpointsFrame.TagSelected(AAdd: Boolean);
var
  mRows: TArray<TAtlasBreakpointRow>;
  mTag: string;
  mEvent: TAtlasBreakpointTagEvent;
begin
  mTag := Trim(FControls.Tag.Text);
  mRows := SelectedRows;
  mEvent := FEvents.OnTag;
  if (mTag = '') or (Length(mRows) = 0) or not Assigned(mEvent) then
  begin
    Exit;
  end;
  mEvent(mRows, mTag, AAdd);
end;

procedure TAtlasDebugBreakpointsFrame.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  if not FState.Filling then
  begin
    UpdateCommands;
  end;
end;

procedure TAtlasDebugBreakpointsFrame.SetGrouping(AGrouping: TAtlasBreakpointGrouping);
begin
  FControls.Grouping.Tag := Ord(AGrouping);
  if FControls.Grouping.Items.Count > Ord(AGrouping) then
  begin
    FControls.Grouping.ItemIndex := Ord(AGrouping);
  end;
  Fill;
end;

procedure TAtlasDebugBreakpointsFrame.SetChip(AFilter: TAtlasBreakpointFilter; AChecked: Boolean);
begin
  FControls.Chips[AFilter].Checked := AChecked;
end;

end.
