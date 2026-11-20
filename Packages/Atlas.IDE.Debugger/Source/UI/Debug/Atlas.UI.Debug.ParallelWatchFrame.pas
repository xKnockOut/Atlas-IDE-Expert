unit Atlas.UI.Debug.ParallelWatchFrame;

// Inhalt des Fensters „Parallel auswerten“ (#866), reine VCL: oben Eingabefeld mit „Hinzufügen“, „Auswerten“ und
// „Threads ohne eigenen Code zeigen“, darunter die Tabelle (Zeilen = Threads, Spalten = Thread, Ort, Ausdrücke),
// unten die Zustandszeile. Klick auf einen Spaltenkopf sortiert (noch einmal: absteigend); das Kontextmenü wirkt auf
// die Spalte unter der Maus: Ausdruck ändern, entfernen, „Nur Zeilen mit …“, Filter aufheben. Doppelklick oder Enter
// meldet den Thread (OnOpen). Welche Zeilen in welcher Reihenfolge stehen, rechnet Atlas.Core.Debug.ParallelWatch.
// Die DFM ist leer; aufgebaut wird im Code, gefüllt erst mit Fenster (CreateWnd).

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
  Atlas.Core.Debug.ParallelWatch;

type
  /// <summary>Ausdruck AIndex (ab 0) mit neuem Text AExpression; bei OnRemove ist AExpression leer.</summary>
  TAtlasParallelColumnEvent = reference to procedure(AIndex: Integer; const AExpression: string);
  /// <summary>Thread der Zeile ARow (Index in die Zeilen von SetTable).</summary>
  TAtlasParallelRowEvent = reference to procedure(ARow: Integer);
  /// <summary>Text abfragen (Titel, Frage, Vorgabe); False bei Abbruch.</summary>
  TAtlasParallelQuery = reference to function(const ATitle, APrompt: string; var AText: string): Boolean;

  /// <summary>Rückrufe des Fensters an die IDE-Schicht.</summary>
  TAtlasParallelWatchEvents = record
    /// <summary>Neuer Ausdruck aus dem Eingabefeld.</summary>
    OnAdd: TProc<string>;
    /// <summary>Knopf „Auswerten“.</summary>
    OnEvaluate: TProc;
    OnOpen: TAtlasParallelRowEvent;
    OnRename: TAtlasParallelColumnEvent;
    OnRemove: TAtlasParallelColumnEvent;
    /// <summary>Ersatz für InputQuery (Tests); nil: InputQuery.</summary>
    Query: TAtlasParallelQuery;
  end;

  TAtlasDebugParallelWatchFrame = class(TFrame)
  private
    FInput: TEdit;
    FEvaluate: TButton;
    FShowAll: TCheckBox;
    FList: TListView;
    FStatus: TLabel;
    FMenu: TPopupMenu;
    FExpressions: TArray<string>;
    FRows: TAtlasParallelRows;
    FView: TArray<Integer>;
    FNote: string;
    FFilter: TAtlasParallelFilter;
    FOrder: TAtlasParallelOrder;
    /// <summary>Spalte unter der Maus beim Kontextmenü; -1 ohne.</summary>
    FColumn: Integer;
    FEvents: TAtlasParallelWatchEvents;
    procedure BuildBar;
    procedure BuildMenu;
    procedure BuildColumns;
    procedure Fill;
    procedure UpdateStatus;
    function ColumnAtX(AX: Integer): Integer;
    procedure AddClick(Sender: TObject);
    procedure EvaluateClick(Sender: TObject);
    procedure ShowAllClick(Sender: TObject);
    procedure InputKeyPress(Sender: TObject; var Key: Char);
    procedure ListColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MenuPopup(Sender: TObject);
    procedure RenameClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure FilterClick(Sender: TObject);
    procedure ClearFilterClick(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Ausdrücke und Zeilen zeigen; ANote ersetzt die Zustandszeile ('' = Zahl der Threads und Filter);
    /// AEvaluate: Knopf „Auswerten“ an (ab cAutoLimit Threads).</summary>
    procedure SetTable(const AExpressions: TArray<string>; const ARows: TAtlasParallelRows; const ANote: string;
      AEvaluate: Boolean);
    /// <summary>Index (in die Zeilen) der gewählten Zeile; -1 ohne.</summary>
    function SelectedRow: Integer;
    property Events: TAtlasParallelWatchEvents read FEvents write FEvents;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Dialogs,
  Atlas.Core.Debug.Threads,
  Atlas.UI.Debug.ThreadMarks,
  Atlas.UI.Debug.ParallelWatch.Strings;

{$R *.dfm}

const
  cBaseDpi = 96;
  cBarRows = 28;
  cButtonSize = 96;
  cCheckSize = 230;
  cThreadWidth = 170;
  cPlaceWidth = 230;
  cValueWidth = 140;
  // Einträge des Kontextmenüs.
  cMenuRename = 0;
  cMenuRemove = 1;
  cMenuFilter = 2;
  cMenuClearFilter = 3;

{ TAtlasDebugParallelWatchFrame }

constructor TAtlasDebugParallelWatchFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColumn := -1;
  FFilter := TAtlasParallelFilter.None;
  FOrder := TAtlasParallelOrder.None;
  BuildBar;
  FStatus := TLabel.Create(Self);
  FStatus.Align := alBottom;
  FStatus.Parent := Self;
  BuildMenu;
  FList := TListView.Create(Self);
  FList.Align := alClient;
  FList.ViewStyle := vsReport;
  FList.ReadOnly := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.PopupMenu := FMenu;
  FList.OnColumnClick := ListColumnClick;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  FList.OnMouseDown := ListMouseDown;
  FList.Parent := Self;
end;

/// <summary>Knopf rechts in ABar.</summary>
function RightButton(AOwner: TComponent; ABar: TWinControl; const ACaption: string; AWidth: Integer;
  AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Caption := ACaption;
  Result.Width := AWidth;
  Result.Align := alRight;
  Result.OnClick := AOnClick;
  Result.Parent := ABar;
end;

procedure TAtlasDebugParallelWatchFrame.BuildBar;
var
  mBar: TPanel;
begin
  mBar := TPanel.Create(Self);
  mBar.BevelOuter := bvNone;
  mBar.Top := 0;
  mBar.Height := MulDiv(cBarRows, CurrentPPI, cBaseDpi);
  mBar.Align := alTop;
  mBar.Parent := Self;
  FShowAll := TCheckBox.Create(Self);
  FShowAll.Caption := TAtlasParallelWatchStrings.Text(TAtlasParallelWatchTextId.ParallelWatchShowAll);
  FShowAll.Width := MulDiv(cCheckSize, CurrentPPI, cBaseDpi);
  FShowAll.Align := alRight;
  FShowAll.OnClick := ShowAllClick;
  FShowAll.Parent := mBar;
  FEvaluate := RightButton(Self, mBar,
    TAtlasParallelWatchStrings.Text(TAtlasParallelWatchTextId.ParallelWatchEvaluate),
    MulDiv(cButtonSize, CurrentPPI, cBaseDpi), EvaluateClick);
  FEvaluate.Enabled := False;
  RightButton(Self, mBar, TAtlasParallelWatchStrings.Text(TAtlasParallelWatchTextId.ParallelWatchAdd),
    MulDiv(cButtonSize, CurrentPPI, cBaseDpi), AddClick);
  FInput := TEdit.Create(Self);
  FInput.TextHint := TAtlasParallelWatchStrings.Text(TAtlasParallelWatchTextId.ParallelWatchAddHint);
  FInput.Align := alClient;
  FInput.OnKeyPress := InputKeyPress;
  FInput.Parent := mBar;
end;

procedure TAtlasDebugParallelWatchFrame.BuildMenu;
const
  cIds: array[cMenuRename..cMenuClearFilter] of TAtlasParallelWatchTextId = (
    TAtlasParallelWatchTextId.ParallelWatchRename, TAtlasParallelWatchTextId.ParallelWatchRemove,
    TAtlasParallelWatchTextId.ParallelWatchFilter, TAtlasParallelWatchTextId.ParallelWatchClearFilter);
var
  mClicks: array[cMenuRename..cMenuClearFilter] of TNotifyEvent;
  mIndex: Integer;
  mItem: TMenuItem;
begin
  mClicks[cMenuRename] := RenameClick;
  mClicks[cMenuRemove] := RemoveClick;
  mClicks[cMenuFilter] := FilterClick;
  mClicks[cMenuClearFilter] := ClearFilterClick;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  for mIndex := 0 to High(cIds) do
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := TAtlasParallelWatchStrings.Text(cIds[mIndex]);
    mItem.OnClick := mClicks[mIndex];
    FMenu.Items.Add(mItem);
  end;
end;

procedure TAtlasDebugParallelWatchFrame.CreateWnd;
begin
  inherited CreateWnd;
  // Liste und Spalten brauchen ein Fenster; Fill baut beides neu auf.
  Fill;
end;

/// <summary>Titel der Spalte AColumn (siehe Atlas.Core.Debug.ParallelWatch); Ausdrücke aus AExpressions.</summary>
function ColumnTitle(const AExpressions: TArray<string>; AColumn: Integer): string;
begin
  case AColumn of
    TAtlasParallelWatch.cThreadColumn:
      Result := TAtlasParallelWatchStrings.Text(TAtlasParallelWatchTextId.ParallelWatchColumnThread);
    TAtlasParallelWatch.cPlaceColumn:
      Result := TAtlasParallelWatchStrings.Text(TAtlasParallelWatchTextId.ParallelWatchColumnPlace);
  else
    Result := '';
    if (AColumn >= TAtlasParallelWatch.cFirstValue) and
      (AColumn - TAtlasParallelWatch.cFirstValue <= High(AExpressions)) then
    begin
      Result := AExpressions[AColumn - TAtlasParallelWatch.cFirstValue];
    end;
  end;
end;

procedure TAtlasDebugParallelWatchFrame.BuildColumns;
var
  mIndex: Integer;
  mColumn: TListColumn;
  mWidth: Integer;
begin
  if FList.Columns.Count = Length(FExpressions) + TAtlasParallelWatch.cFirstValue then
  begin
    for mIndex := 0 to FList.Columns.Count - 1 do
    begin
      FList.Columns[mIndex].Caption := ColumnTitle(FExpressions, mIndex);
    end;
    Exit;
  end;
  FList.Columns.Clear;
  for mIndex := 0 to Length(FExpressions) + TAtlasParallelWatch.cFirstValue - 1 do
  begin
    mColumn := FList.Columns.Add;
    mColumn.Caption := ColumnTitle(FExpressions, mIndex);
    case mIndex of
      TAtlasParallelWatch.cThreadColumn:
        mWidth := cThreadWidth;
      TAtlasParallelWatch.cPlaceColumn:
        mWidth := cPlaceWidth;
    else
      mWidth := cValueWidth;
    end;
    mColumn.Width := MulDiv(mWidth, CurrentPPI, cBaseDpi);
  end;
end;

/// <summary>Text der Spalte Thread: Kennung, Name, ⚑ für markierte Threads (#852).</summary>
function ThreadText(const ARow: TAtlasParallelRow): string;
begin
  Result := TAtlasThreadMarkTexts.ThreadLabel(TAtlasDebugThreadStack.Create(ARow.ThreadId, ARow.Name, nil),
    ARow.Flagged);
end;

procedure TAtlasDebugParallelWatchFrame.Fill;
var
  mItem: TListItem;
  mRow, mSelected, mColumn: Integer;
begin
  mSelected := SelectedRow;
  FList.HandleNeeded;
  BuildColumns;
  FView := TAtlasParallelWatch.View(FRows, FShowAll.Checked, FFilter, FOrder);
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mRow in FView do
    begin
      mItem := FList.Items.Add;
      mItem.Caption := ThreadText(FRows[mRow]);
      for mColumn := TAtlasParallelWatch.cPlaceColumn to Length(FExpressions) + TAtlasParallelWatch.cFirstValue - 1 do
      begin
        mItem.SubItems.Add(FRows[mRow].ColumnText(mColumn));
      end;
      mItem.Selected := mRow = mSelected;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  UpdateStatus;
end;

procedure TAtlasDebugParallelWatchFrame.UpdateStatus;
var
  mText: string;
begin
  mText := FNote;
  if (mText = '') and (FExpressions = nil) then
  begin
    mText := TAtlasParallelWatchStrings.Text(TAtlasParallelWatchTextId.ParallelWatchEmpty);
  end
  else if mText = '' then
  begin
    mText := TAtlasParallelWatchStrings.Fmt(TAtlasParallelWatchTextId.ParallelWatchStatus,
      [Length(FView), Length(FRows)]);
  end;
  if FFilter.Active then
  begin
    mText := mText + '  ·  ' + TAtlasParallelWatchStrings.Fmt(TAtlasParallelWatchTextId.ParallelWatchFilterActive,
      [ColumnTitle(FExpressions, FFilter.Column), FFilter.Text]);
  end;
  FStatus.Caption := mText;
end;

procedure TAtlasDebugParallelWatchFrame.SetTable(const AExpressions: TArray<string>;
  const ARows: TAtlasParallelRows; const ANote: string; AEvaluate: Boolean);
begin
  FEvaluate.Enabled := AEvaluate;
  FExpressions := Copy(AExpressions);
  FRows := Copy(ARows);
  FNote := ANote;
  if FFilter.Column >= Length(FExpressions) + TAtlasParallelWatch.cFirstValue then
  begin
    FFilter := TAtlasParallelFilter.None;
  end;
  if FOrder.Column >= Length(FExpressions) + TAtlasParallelWatch.cFirstValue then
  begin
    FOrder := TAtlasParallelOrder.None;
  end;
  if HandleAllocated then
  begin
    Fill;
  end;
end;

function TAtlasDebugParallelWatchFrame.SelectedRow: Integer;
begin
  Result := -1;
  if FList.HandleAllocated and (FList.Selected <> nil) and (FList.Selected.Index <= High(FView)) then
  begin
    Result := FView[FList.Selected.Index];
  end;
end;

function TAtlasDebugParallelWatchFrame.ColumnAtX(AX: Integer): Integer;
var
  mLeft, mIndex: Integer;
begin
  // Spalten lassen sich nicht verschieben: Breiten von links aufsummieren, waagerecht gescrollt eingerechnet.
  mLeft := -GetScrollPos(FList.Handle, SB_HORZ);
  for mIndex := 0 to FList.Columns.Count - 1 do
  begin
    mLeft := mLeft + FList.Columns[mIndex].Width;
    if AX < mLeft then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Text abfragen über AQuery, ohne AQuery über InputQuery.</summary>
function Ask(const AQuery: TAtlasParallelQuery; const ATitle, APrompt: string; var AText: string): Boolean;
begin
  if Assigned(AQuery) then
  begin
    Result := AQuery(ATitle, APrompt, AText);
  end
  else
  begin
    Result := InputQuery(ATitle, APrompt, AText);
  end;
end;

procedure TAtlasDebugParallelWatchFrame.AddClick(Sender: TObject);
var
  mText: string;
begin
  mText := Trim(FInput.Text);
  if (mText <> '') and Assigned(FEvents.OnAdd) then
  begin
    FInput.Text := '';
    FEvents.OnAdd(mText);
  end;
end;

procedure TAtlasDebugParallelWatchFrame.EvaluateClick(Sender: TObject);
begin
  if Assigned(FEvents.OnEvaluate) then
  begin
    FEvents.OnEvaluate();
  end;
end;

procedure TAtlasDebugParallelWatchFrame.ShowAllClick(Sender: TObject);
begin
  // Das Kästchen gibt es nur mit Fenster.
  Fill;
end;

procedure TAtlasDebugParallelWatchFrame.InputKeyPress(Sender: TObject; var Key: Char);
begin
  if Key = #13 then
  begin
    Key := #0;
    AddClick(Sender);
  end;
end;

procedure TAtlasDebugParallelWatchFrame.ListColumnClick(Sender: TObject; Column: TListColumn);
begin
  FOrder := FOrder.Toggled(Column.Index);
  Fill;
end;

procedure TAtlasDebugParallelWatchFrame.ListDblClick(Sender: TObject);
var
  mRow: Integer;
begin
  mRow := SelectedRow;
  if (mRow >= 0) and Assigned(FEvents.OnOpen) then
  begin
    FEvents.OnOpen(mRow);
  end;
end;

procedure TAtlasDebugParallelWatchFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    ListDblClick(Sender);
  end;
end;

procedure TAtlasDebugParallelWatchFrame.ListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  if Button = mbRight then
  begin
    FColumn := ColumnAtX(X);
  end;
end;

procedure TAtlasDebugParallelWatchFrame.MenuPopup(Sender: TObject);
var
  mValue: Boolean;
begin
  mValue := FColumn >= TAtlasParallelWatch.cFirstValue;
  FMenu.Items[cMenuRename].Visible := mValue;
  FMenu.Items[cMenuRemove].Visible := mValue;
  FMenu.Items[cMenuFilter].Visible := FColumn >= 0;
  FMenu.Items[cMenuClearFilter].Visible := FFilter.Active;
end;

procedure TAtlasDebugParallelWatchFrame.RenameClick(Sender: TObject);
var
  mText: string;
begin
  mText := ColumnTitle(FExpressions, FColumn);
  if (FColumn >= TAtlasParallelWatch.cFirstValue) and Assigned(FEvents.OnRename) and
    Ask(FEvents.Query, TAtlasParallelWatchStrings.Text(TAtlasParallelWatchTextId.ParallelWatchRenameTitle),
    TAtlasParallelWatchStrings.Text(TAtlasParallelWatchTextId.ParallelWatchRenamePrompt), mText) and
    (Trim(mText) <> '') then
  begin
    FEvents.OnRename(FColumn - TAtlasParallelWatch.cFirstValue, Trim(mText));
  end;
end;

procedure TAtlasDebugParallelWatchFrame.RemoveClick(Sender: TObject);
begin
  if (FColumn >= TAtlasParallelWatch.cFirstValue) and Assigned(FEvents.OnRemove) then
  begin
    FEvents.OnRemove(FColumn - TAtlasParallelWatch.cFirstValue, '');
  end;
end;

procedure TAtlasDebugParallelWatchFrame.FilterClick(Sender: TObject);
var
  mText: string;
begin
  mText := '';
  if FFilter.Column = FColumn then
  begin
    mText := FFilter.Text;
  end;
  if (FColumn >= 0) and Ask(FEvents.Query,
    TAtlasParallelWatchStrings.Text(TAtlasParallelWatchTextId.ParallelWatchFilterTitle),
    TAtlasParallelWatchStrings.Fmt(TAtlasParallelWatchTextId.ParallelWatchFilterPrompt,
    [ColumnTitle(FExpressions, FColumn)]), mText) then
  begin
    FFilter.Column := FColumn;
    FFilter.Text := mText;
    Fill;
  end;
end;

procedure TAtlasDebugParallelWatchFrame.ClearFilterClick(Sender: TObject);
begin
  FFilter := TAtlasParallelFilter.None;
  Fill;
end;

end.
