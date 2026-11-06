unit Atlas.UI.Debug.ExceptionsFrame;

// Inhalt des Seitenfensters „Exception-Verlauf“ (#517), reine VCL: oben die
// Auswahl der Klasse („Alle Klassen“ oder eine aus dem Verlauf) und ein
// Textfilter (jedes Wort muss in Klasse, Meldung, Ort, Routine oder Thread
// vorkommen), darunter die Liste mit Uhrzeit (zuletzt gesehen), Klasse,
// Meldung, Anzahl, Ort und Thread, zuletzt gesehene zuerst. Still
// fortgesetzte Exceptions (Ignorier-Liste) stehen grau, Klassen auf der
// Ignorier-Liste mit „ignoriert“ hinter der Anzahl. Unten die Summe.
// Bedienung: Klick, Doppelklick oder Enter springt zur Stelle (OnOpen, nur mit
// Quelltext), Strg+C kopiert die Meldung (OnCopy). Kontextmenü: Springen,
// „Klasse künftig ignorieren“ bzw. „Wieder anhalten“ (OnIgnoreClass mit
// True/False), „Meldung kopieren“, „Verlauf leeren“ (OnClear). Die
// IDE-Schicht hält den Verlauf und ruft nach jeder Änderung SetHistory.
// Unten der Aufrufstapel des gewählten Eintrags (#578, Stack,
// TAtlasDebugExceptionStack). Die DFM ist leer, weil TCustomFrame.Create für
// abgeleitete Frames eine Ressource verlangt; aufgebaut wird im Code.

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
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.IgnoreList,
  Atlas.UI.Debug.ExceptionStack;

type
  TAtlasDebugExceptionsFrame = class(TFrame)
  private type
    /// <summary>Kontextmenü der Liste: Springen, Klasse ignorieren bzw. wieder anhalten, kopieren, leeren.</summary>
    TListMenu = class(TPopupMenu)
    private
      FFrame: TAtlasDebugExceptionsFrame;
      FOpenItem: TMenuItem;
      FIgnoreItem: TMenuItem;
      FStopItem: TMenuItem;
      FCopyItem: TMenuItem;
      FClearItem: TMenuItem;
      function AddItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
      procedure MenuPopup(Sender: TObject);
      procedure OpenClick(Sender: TObject);
      procedure IgnoreClick(Sender: TObject);
      procedure StopClick(Sender: TObject);
      procedure CopyClick(Sender: TObject);
      procedure ClearClick(Sender: TObject);
    public
      constructor CreateFor(AFrame: TAtlasDebugExceptionsFrame);
    end;
    /// <summary>Gezeigter Verlauf: Einträge (zuletzt gesehen zuerst), Klassen und Summe aller Exceptions.</summary>
    THistoryData = record
      Entries: TAtlasDebugExceptions;
      Classes: TArray<string>;
      Total: Integer;
    end;
    /// <summary>Ereignisse an die IDE-Schicht.</summary>
    TEvents = record
      Open: TProc<TAtlasDebugException>;
      Copy: TProc<TAtlasDebugException>;
      IgnoreClass: TProc<string, Boolean>;
      Clear: TProc;
    end;
  private
    FClassBox: TComboBox;
    FFilter: TEdit;
    FList: TListView;
    FStack: TAtlasDebugExceptionStack;
    FEmpty: TLabel;
    FSummary: TLabel;
    FMenu: TListMenu;
    FHistory: THistoryData;
    FIgnore: TAtlasDebugIgnoreList;
    /// <summary>Gezeigte Einträge in der Reihenfolge der Listenzeilen.</summary>
    FShown: TAtlasDebugExceptions;
    FEvents: TEvents;
    procedure FillClasses;
    procedure Refill;
    procedure FillList(const ASelected: string);
    procedure FillStack;
    procedure FilterChange(Sender: TObject);
    procedure FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer;
      State: TCustomDrawState; var DefaultDraw: Boolean);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Verlauf und Ignorier-Liste zeigen; Filter und Auswahl bleiben, soweit möglich.</summary>
    procedure SetHistory(const AHistory: TAtlasDebugExceptionHistory; const AIgnore: TAtlasDebugIgnoreList);
    /// <summary>Gewählter Eintrag; False ohne Auswahl.</summary>
    function TrySelected(out AException: TAtlasDebugException): Boolean;
    procedure OpenSelected;
    procedure CopySelected;
    /// <summary>Text der Spalten einer Zeile: Uhrzeit, Klasse, Meldung, Anzahl, Ort, Thread.</summary>
    class function Cells(const AException: TAtlasDebugException; AIgnoredClass: Boolean): TArray<string>; static;
    property ClassBox: TComboBox read FClassBox;
    property Filter: TEdit read FFilter;
    property List: TListView read FList;
    property EmptyLabel: TLabel read FEmpty;
    property SummaryLabel: TLabel read FSummary;
    property Shown: TAtlasDebugExceptions read FShown;
    /// <summary>Aufrufstapel des gewählten Eintrags (#578).</summary>
    property Stack: TAtlasDebugExceptionStack read FStack;
    property OnOpen: TProc<TAtlasDebugException> read FEvents.Open write FEvents.Open;
    property OnCopy: TProc<TAtlasDebugException> read FEvents.Copy write FEvents.Copy;
    /// <summary>Klasse und True = künftig ignorieren, False = wieder anhalten.</summary>
    property OnIgnoreClass: TProc<string, Boolean> read FEvents.IgnoreClass write FEvents.IgnoreClass;
    property OnClear: TProc read FEvents.Clear write FEvents.Clear;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Debug.Strings;

{$R *.dfm}

/// <summary>Spalte mit ACaption und AWidth (logische Pixel) an AList.</summary>
function AddColumn(AList: TListView; const ACaption: string; AWidth: Integer): TListColumn;
begin
  Result := AList.Columns.Add;
  Result.Caption := ACaption;
  Result.Width := MulDiv(AWidth, AList.CurrentPPI, 96);
end;

/// <summary>Gewählte Klasse aus ABox; '' für „Alle Klassen“ (Eintrag 0).</summary>
function ClassFilter(ABox: TComboBox; const AClasses: TArray<string>): string;
begin
  Result := '';
  if (ABox.ItemIndex > 0) and (ABox.ItemIndex <= Length(AClasses)) then
  begin
    Result := AClasses[ABox.ItemIndex - 1];
  end;
end;

/// <summary>Leiste oben in AFrame: Auswahl der Klasse und Textfilter.</summary>
procedure CreateFilterBar(AFrame: TAtlasDebugExceptionsFrame);
var
  mTop: TPanel;
begin
  mTop := TPanel.Create(AFrame);
  mTop.Parent := AFrame;
  mTop.Align := alTop;
  mTop.BevelOuter := bvNone;
  mTop.ShowCaption := False;
  mTop.ParentBackground := True;
  mTop.Height := MulDiv(30, AFrame.CurrentPPI, 96);

  AFrame.FClassBox := TComboBox.Create(AFrame);
  AFrame.FClassBox.Parent := mTop;
  AFrame.FClassBox.Align := alLeft;
  AFrame.FClassBox.AlignWithMargins := True;
  AFrame.FClassBox.Style := csDropDownList;
  AFrame.FClassBox.Width := MulDiv(170, AFrame.CurrentPPI, 96);
  AFrame.FClassBox.OnChange := AFrame.FilterChange;

  AFrame.FFilter := TEdit.Create(AFrame);
  AFrame.FFilter.Parent := mTop;
  AFrame.FFilter.Align := alClient;
  AFrame.FFilter.AlignWithMargins := True;
  AFrame.FFilter.TextHint := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsFilterHint);
  AFrame.FFilter.OnChange := AFrame.FilterChange;
  AFrame.FFilter.OnKeyDown := AFrame.FilterKeyDown;
end;

/// <summary>Graue Beschriftung in AFrame (Summe unten bzw. Hinweis ohne Exceptions).</summary>
function GrayLabel(AFrame: TAtlasDebugExceptionsFrame; AAlign: TAlign): TLabel;
begin
  Result := TLabel.Create(AFrame);
  Result.Parent := AFrame;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
  Result.Font.Color := clGrayText;
end;

/// <summary>Liste der Exceptions in AFrame mit ihren Spalten und Ereignissen.</summary>
procedure CreateList(AFrame: TAtlasDebugExceptionsFrame);
var
  mList: TListView;
begin
  mList := TListView.Create(AFrame);
  AFrame.FList := mList;
  mList.Parent := AFrame;
  mList.Align := alClient;
  mList.AlignWithMargins := True;
  mList.ViewStyle := vsReport;
  mList.RowSelect := True;
  mList.HideSelection := False;
  mList.ReadOnly := True;
  mList.MultiSelect := False;
  mList.ColumnClick := False;
  mList.PopupMenu := AFrame.FMenu;
  AddColumn(mList, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsColumnTime), 70);
  AddColumn(mList, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsColumnClass), 130);
  AddColumn(mList, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsColumnMessage), 260);
  AddColumn(mList, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsColumnCount), 60).Alignment :=
    taRightJustify;
  AddColumn(mList, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsColumnLocation), 170);
  AddColumn(mList, TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsColumnThread), 110);
  mList.OnDblClick := AFrame.ListDblClick;
  mList.OnSelectItem := AFrame.ListSelectItem;
  mList.OnKeyDown := AFrame.ListKeyDown;
  mList.OnCustomDrawItem := AFrame.ListCustomDrawItem;
  mList.OnCustomDrawSubItem := AFrame.ListCustomDrawSubItem;
end;

/// <summary>Zeile AItem ist eine still fortgesetzte Exception aus AShown.</summary>
function ShownIgnored(const AShown: TAtlasDebugExceptions; AItem: TListItem): Boolean;
begin
  Result := (AItem <> nil) and (AItem.Index <= High(AShown)) and AShown[AItem.Index].Ignored;
end;

{ TAtlasDebugExceptionsFrame.TListMenu }

constructor TAtlasDebugExceptionsFrame.TListMenu.CreateFor(AFrame: TAtlasDebugExceptionsFrame);
begin
  inherited Create(AFrame);
  FFrame := AFrame;
  OnPopup := MenuPopup;
  FOpenItem := AddItem(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsGoTo), OpenClick);
  FOpenItem.Default := True;
  FIgnoreItem := AddItem(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsIgnoreClass), IgnoreClick);
  FStopItem := AddItem(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsStopAgain), StopClick);
  FCopyItem := AddItem(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsCopy), CopyClick);
  FClearItem := AddItem(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsClear), ClearClick);
end;

function TAtlasDebugExceptionsFrame.TListMenu.AddItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(Self);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  Items.Add(Result);
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.MenuPopup(Sender: TObject);
var
  mEntry: TAtlasDebugException;
  mHas, mIgnored: Boolean;
begin
  mHas := FFrame.TrySelected(mEntry);
  mIgnored := mHas and FFrame.FIgnore.IgnoresClass(mEntry.ExceptionClass);
  FOpenItem.Enabled := mHas and mEntry.HasSource;
  FIgnoreItem.Visible := not mIgnored;
  FIgnoreItem.Enabled := mHas;
  FStopItem.Visible := mIgnored;
  FCopyItem.Enabled := mHas;
  FClearItem.Enabled := FFrame.FHistory.Entries <> nil;
  if mHas then
  begin
    FIgnoreItem.Caption := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugExceptionsIgnoreClassNamed,
      [mEntry.ExceptionClass]);
    FStopItem.Caption := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugExceptionsStopAgainNamed,
      [mEntry.ExceptionClass]);
  end
  else
  begin
    FIgnoreItem.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsIgnoreClass);
    FStopItem.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsStopAgain);
  end;
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.OpenClick(Sender: TObject);
begin
  FFrame.OpenSelected;
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.IgnoreClick(Sender: TObject);
var
  mEntry: TAtlasDebugException;
begin
  if FFrame.TrySelected(mEntry) and Assigned(FFrame.FEvents.IgnoreClass) then
  begin
    FFrame.FEvents.IgnoreClass(mEntry.ExceptionClass, True);
  end;
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.StopClick(Sender: TObject);
var
  mEntry: TAtlasDebugException;
begin
  if FFrame.TrySelected(mEntry) and Assigned(FFrame.FEvents.IgnoreClass) then
  begin
    FFrame.FEvents.IgnoreClass(mEntry.ExceptionClass, False);
  end;
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.CopyClick(Sender: TObject);
begin
  FFrame.CopySelected;
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.ClearClick(Sender: TObject);
begin
  if Assigned(FFrame.FEvents.Clear) then
  begin
    FFrame.FEvents.Clear();
  end;
end;

{ TAtlasDebugExceptionsFrame }

constructor TAtlasDebugExceptionsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FIgnore := TAtlasDebugIgnoreList.Empty;
  CreateFilterBar(Self);
  FSummary := GrayLabel(Self, alBottom);
  FSummary.Caption := '';
  // Aufrufstapel des gewählten Eintrags (#578) über der Summe.
  FStack := TAtlasDebugExceptionStack.CreateIn(Self);
  FMenu := TListMenu.CreateFor(Self);
  CreateList(Self);
  // Ohne Exceptions: Hinweis statt leerer Liste.
  FEmpty := GrayLabel(Self, alClient);
  FEmpty.WordWrap := True;
  FEmpty.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsEmpty);
  FEmpty.Visible := False;
end;

procedure TAtlasDebugExceptionsFrame.CreateWnd;
begin
  inherited CreateWnd;
  // Die Auswahl der Klasse braucht ein Fenster (TComboBox.Items).
  FillClasses;
  Refill;
end;

class function TAtlasDebugExceptionsFrame.Cells(const AException: TAtlasDebugException;
  AIgnoredClass: Boolean): TArray<string>;
var
  mCount: string;
begin
  mCount := IntToStr(AException.Count);
  if AIgnoredClass then
  begin
    mCount := mCount + ' · ' + TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsIgnored);
  end;
  // Uhrzeit für die Anzeige: im Format des Benutzers.
  Result := TArray<string>.Create(FormatDateTime('hh:nn:ss', AException.LastTime, FormatSettings),
    AException.ExceptionClass, AException.Message, mCount, AException.LocationText,
    AException.ThreadText(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsThread)));
end;

procedure TAtlasDebugExceptionsFrame.FillClasses;
var
  mKeep, mName: string;
  mIndex: Integer;
begin
  // Erst mit Fenster (CreateWnd): TComboBox.Items braucht eins.
  if not HandleAllocated then
  begin
    Exit;
  end;
  mKeep := ClassFilter(FClassBox, FHistory.Classes);
  FClassBox.Items.BeginUpdate;
  try
    FClassBox.Items.Clear;
    FClassBox.Items.Add(TAtlasDebugStrings.Text(TAtlasDebugTextId.DebugExceptionsAllClasses));
    for mName in FHistory.Classes do
    begin
      FClassBox.Items.Add(mName);
    end;
  finally
    FClassBox.Items.EndUpdate;
  end;
  FClassBox.ItemIndex := 0;
  for mIndex := 0 to High(FHistory.Classes) do
  begin
    if SameText(FHistory.Classes[mIndex], mKeep) then
    begin
      FClassBox.ItemIndex := mIndex + 1;
    end;
  end;
end;

procedure TAtlasDebugExceptionsFrame.SetHistory(const AHistory: TAtlasDebugExceptionHistory;
  const AIgnore: TAtlasDebugIgnoreList);
var
  mIndex: Integer;
begin
  FIgnore := AIgnore;
  FHistory := Default(THistoryData);
  if AHistory <> nil then
  begin
    // Reihenfolge des Verlaufs: zuletzt gesehen zuerst.
    for mIndex in AHistory.Filter('', '') do
    begin
      FHistory.Entries := FHistory.Entries + [AHistory[mIndex]];
    end;
    FHistory.Classes := AHistory.Classes;
    FHistory.Total := AHistory.Total;
  end;
  FillClasses;
  Refill;
end;

procedure TAtlasDebugExceptionsFrame.Refill;
var
  mEntry, mCurrent: TAtlasDebugException;
  mWords: TArray<string>;
  mSelected, mOnlyClass: string;
begin
  mSelected := '';
  if TrySelected(mCurrent) then
  begin
    mSelected := mCurrent.Key;
  end;
  FShown := nil;
  mWords := TAtlasDebugException.FilterWords(FFilter.Text);
  mOnlyClass := ClassFilter(FClassBox, FHistory.Classes);
  for mEntry in FHistory.Entries do
  begin
    if mEntry.Matches(mOnlyClass, mWords) then
    begin
      FShown := FShown + [mEntry];
    end;
  end;
  FillList(mSelected);
  FEmpty.Visible := FHistory.Entries = nil;
  FList.Visible := FHistory.Entries <> nil;
  FStack.SetShown(FHistory.Entries <> nil);
  FillStack;
  FSummary.Caption := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.DebugExceptionsSummary,
    [Length(FHistory.Entries), FHistory.Total]);
end;

procedure TAtlasDebugExceptionsFrame.FillList(const ASelected: string);
var
  mEntry: TAtlasDebugException;
  mItem: TListItem;
  mTexts: TArray<string>;
  mPart: Integer;
begin
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mEntry in FShown do
    begin
      mTexts := Cells(mEntry, FIgnore.IgnoresClass(mEntry.ExceptionClass));
      mItem := FList.Items.Add;
      mItem.Caption := mTexts[0];
      for mPart := 1 to High(mTexts) do
      begin
        mItem.SubItems.Add(mTexts[mPart]);
      end;
      if (ASelected <> '') and (mEntry.Key = ASelected) then
      begin
        mItem.Selected := True;
      end;
    end;
  finally
    FList.Items.EndUpdate;
  end;
end;

procedure TAtlasDebugExceptionsFrame.FillStack;
var
  mEntry: TAtlasDebugException;
begin
  if TrySelected(mEntry) then
  begin
    FStack.ShowFor(mEntry.Key, mEntry.Frames);
  end
  else
  begin
    FStack.ShowFor('', nil);
  end;
end;

function TAtlasDebugExceptionsFrame.TrySelected(out AException: TAtlasDebugException): Boolean;
begin
  Result := (FList <> nil) and (FList.Selected <> nil) and (FList.Selected.Index <= High(FShown));
  if Result then
  begin
    AException := FShown[FList.Selected.Index];
  end
  else
  begin
    AException := Default(TAtlasDebugException);
  end;
end;

procedure TAtlasDebugExceptionsFrame.OpenSelected;
var
  mEntry: TAtlasDebugException;
begin
  if TrySelected(mEntry) and mEntry.HasSource and Assigned(FEvents.Open) then
  begin
    FEvents.Open(mEntry);
  end;
end;

procedure TAtlasDebugExceptionsFrame.CopySelected;
var
  mEntry: TAtlasDebugException;
begin
  if TrySelected(mEntry) and Assigned(FEvents.Copy) then
  begin
    FEvents.Copy(mEntry);
  end;
end;

procedure TAtlasDebugExceptionsFrame.FilterChange(Sender: TObject);
begin
  Refill;
end;

procedure TAtlasDebugExceptionsFrame.FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // ↓ führt in die Liste.
  if (Key = VK_DOWN) and (FList.Items.Count > 0) then
  begin
    FList.SetFocus;
    if FList.Selected = nil then
    begin
      FList.Items[0].Selected := True;
    end;
    Key := 0;
  end;
end;

procedure TAtlasDebugExceptionsFrame.ListDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TAtlasDebugExceptionsFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
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

procedure TAtlasDebugExceptionsFrame.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  FillStack;
end;

procedure TAtlasDebugExceptionsFrame.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  // Still fortgesetzt: ganze Zeile grau.
  TAtlasDebugExceptionStack.RowColors(Sender.Canvas, FList, State, ShownIgnored(FShown, Item));
end;

procedure TAtlasDebugExceptionsFrame.ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  TAtlasDebugExceptionStack.RowColors(Sender.Canvas, FList, State, ShownIgnored(FShown, Item));
end;

end.
