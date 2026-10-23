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
// IDE-Schicht hält den Verlauf und ruft nach jeder Änderung SetHistory. Die
// DFM ist leer, weil TCustomFrame.Create für abgeleitete Frames eine Ressource
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
  Atlas.Core.Debug.Exceptions,
  Atlas.Core.Debug.IgnoreList;

type
  TAtlasDebugExceptionsFrame = class(TFrame)
  private
    FTop: TPanel;
    FClassBox: TComboBox;
    FFilter: TEdit;
    FList: TListView;
    FEmpty: TLabel;
    FSummary: TLabel;
    FMenu: TPopupMenu;
    FOpenItem: TMenuItem;
    FIgnoreItem: TMenuItem;
    FStopItem: TMenuItem;
    FCopyItem: TMenuItem;
    FClearItem: TMenuItem;
    FHistory: TAtlasDebugExceptions;
    FIgnore: TAtlasDebugIgnoreList;
    FClasses: TArray<string>;
    /// <summary>Gezeigte Einträge in der Reihenfolge der Listenzeilen.</summary>
    FShown: TAtlasDebugExceptions;
    FTotal: Integer;
    FOnOpen: TProc<TAtlasDebugException>;
    FOnCopy: TProc<TAtlasDebugException>;
    FOnIgnoreClass: TProc<string, Boolean>;
    FOnClear: TProc;
    function AddColumn(const ACaption: string; AWidth: Integer): TListColumn;
    function AddMenuItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
    function ClassFilter: string;
    procedure FillClasses;
    procedure Refill;
    procedure FilterChange(Sender: TObject);
    procedure FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function ListColor(AColor: TColor): TColor;
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure RowColors(ACanvas: TCanvas; AState: TCustomDrawState; AGray: Boolean);
    procedure MenuPopup(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure IgnoreClick(Sender: TObject);
    procedure StopClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
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
    property Menu: TPopupMenu read FMenu;
    property Shown: TAtlasDebugExceptions read FShown;
    property OnOpen: TProc<TAtlasDebugException> read FOnOpen write FOnOpen;
    property OnCopy: TProc<TAtlasDebugException> read FOnCopy write FOnCopy;
    /// <summary>Klasse und True = künftig ignorieren, False = wieder anhalten.</summary>
    property OnIgnoreClass: TProc<string, Boolean> read FOnIgnoreClass write FOnIgnoreClass;
    property OnClear: TProc read FOnClear write FOnClear;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Themes,
  Atlas.UI.Strings;

{$R *.dfm}

{ TAtlasDebugExceptionsFrame }

constructor TAtlasDebugExceptionsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FIgnore := TAtlasDebugIgnoreList.Empty;

  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.BevelOuter := bvNone;
  FTop.ShowCaption := False;
  FTop.ParentBackground := True;
  FTop.Height := MulDiv(30, CurrentPPI, 96);

  FClassBox := TComboBox.Create(Self);
  FClassBox.Parent := FTop;
  FClassBox.Align := alLeft;
  FClassBox.AlignWithMargins := True;
  FClassBox.Style := csDropDownList;
  FClassBox.Width := MulDiv(170, CurrentPPI, 96);
  FClassBox.OnChange := FilterChange;

  FFilter := TEdit.Create(Self);
  FFilter.Parent := FTop;
  FFilter.Align := alClient;
  FFilter.AlignWithMargins := True;
  FFilter.TextHint := TAtlasStrings.Text(TAtlasTextId.DebugExceptionsFilterHint);
  FFilter.OnChange := FilterChange;
  FFilter.OnKeyDown := FilterKeyDown;

  FSummary := TLabel.Create(Self);
  FSummary.Parent := Self;
  FSummary.Align := alBottom;
  FSummary.AlignWithMargins := True;
  FSummary.ShowAccelChar := False;
  FSummary.Font.Color := clGrayText;
  FSummary.Caption := '';

  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FOpenItem := AddMenuItem(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsGoTo), OpenClick);
  FOpenItem.Default := True;
  FIgnoreItem := AddMenuItem(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsIgnoreClass), IgnoreClick);
  FStopItem := AddMenuItem(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsStopAgain), StopClick);
  FCopyItem := AddMenuItem(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsCopy), CopyClick);
  FClearItem := AddMenuItem(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsClear), ClearClick);

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := True;
  FList.MultiSelect := False;
  FList.ColumnClick := False;
  FList.PopupMenu := FMenu;
  AddColumn(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsColumnTime), 70);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsColumnClass), 130);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsColumnMessage), 260);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsColumnCount), 60).Alignment := taRightJustify;
  AddColumn(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsColumnLocation), 170);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsColumnThread), 110);
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  FList.OnCustomDrawSubItem := ListCustomDrawSubItem;

  // Ohne Exceptions: Hinweis statt leerer Liste.
  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := Self;
  FEmpty.Align := alClient;
  FEmpty.AlignWithMargins := True;
  FEmpty.WordWrap := True;
  FEmpty.ShowAccelChar := False;
  FEmpty.Font.Color := clGrayText;
  FEmpty.Caption := TAtlasStrings.Text(TAtlasTextId.DebugExceptionsEmpty);
  FEmpty.Visible := False;
end;

procedure TAtlasDebugExceptionsFrame.CreateWnd;
begin
  inherited CreateWnd;
  // Die Auswahl der Klasse braucht ein Fenster (TComboBox.Items).
  FillClasses;
  Refill;
end;

function TAtlasDebugExceptionsFrame.AddColumn(const ACaption: string; AWidth: Integer): TListColumn;
begin
  Result := FList.Columns.Add;
  Result.Caption := ACaption;
  Result.Width := MulDiv(AWidth, CurrentPPI, 96);
end;

function TAtlasDebugExceptionsFrame.AddMenuItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  FMenu.Items.Add(Result);
end;

class function TAtlasDebugExceptionsFrame.Cells(const AException: TAtlasDebugException;
  AIgnoredClass: Boolean): TArray<string>;
var
  Count: string;
begin
  Count := IntToStr(AException.Count);
  if AIgnoredClass then
    Count := Count + ' · ' + TAtlasStrings.Text(TAtlasTextId.DebugExceptionsIgnored);
  Result := TArray<string>.Create(FormatDateTime('hh:nn:ss', AException.LastTime), AException.ExceptionClass,
    AException.Message, Count, AException.LocationText,
    AException.ThreadText(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsThread)));
end;

function TAtlasDebugExceptionsFrame.ClassFilter: string;
begin
  // Eintrag 0 ist „Alle Klassen“.
  if (FClassBox.ItemIndex > 0) and (FClassBox.ItemIndex <= Length(FClasses)) then
    Result := FClasses[FClassBox.ItemIndex - 1]
  else
    Result := '';
end;

procedure TAtlasDebugExceptionsFrame.FillClasses;
var
  Keep, Name: string;
  Index: Integer;
begin
  // Erst mit Fenster (CreateWnd): TComboBox.Items braucht eins.
  if not HandleAllocated then
    Exit;
  Keep := ClassFilter;
  FClassBox.Items.BeginUpdate;
  try
    FClassBox.Items.Clear;
    FClassBox.Items.Add(TAtlasStrings.Text(TAtlasTextId.DebugExceptionsAllClasses));
    for Name in FClasses do
      FClassBox.Items.Add(Name);
  finally
    FClassBox.Items.EndUpdate;
  end;
  FClassBox.ItemIndex := 0;
  for Index := 0 to High(FClasses) do
    if SameText(FClasses[Index], Keep) then
      FClassBox.ItemIndex := Index + 1;
end;

procedure TAtlasDebugExceptionsFrame.SetHistory(const AHistory: TAtlasDebugExceptionHistory;
  const AIgnore: TAtlasDebugIgnoreList);
var
  Index: Integer;
  Filtered: TArray<Integer>;
begin
  FIgnore := AIgnore;
  FHistory := nil;
  FClasses := nil;
  FTotal := 0;
  if AHistory <> nil then
  begin
    // Reihenfolge des Verlaufs: zuletzt gesehen zuerst.
    Filtered := AHistory.Filter('', '');
    for Index in Filtered do
      FHistory := FHistory + [AHistory[Index]];
    FClasses := AHistory.Classes;
    FTotal := AHistory.Total;
  end;
  FillClasses;
  Refill;
end;

procedure TAtlasDebugExceptionsFrame.Refill;
var
  Entry: TAtlasDebugException;
  Item: TListItem;
  Texts: TArray<string>;
  Part: Integer;
  Words: TArray<string>;
  Selected, OnlyClass: string;
  Current: TAtlasDebugException;
begin
  Selected := '';
  if TrySelected(Current) then
    Selected := Current.Key;
  FShown := nil;
  Words := TAtlasDebugException.FilterWords(FFilter.Text);
  OnlyClass := ClassFilter;
  for Entry in FHistory do
    if Entry.Matches(OnlyClass, Words) then
      FShown := FShown + [Entry];
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for Entry in FShown do
    begin
      Texts := Cells(Entry, FIgnore.IgnoresClass(Entry.ExceptionClass));
      Item := FList.Items.Add;
      Item.Caption := Texts[0];
      for Part := 1 to High(Texts) do
        Item.SubItems.Add(Texts[Part]);
      if (Selected <> '') and (Entry.Key = Selected) then
        Item.Selected := True;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  FEmpty.Visible := FHistory = nil;
  FList.Visible := FHistory <> nil;
  FSummary.Caption := TAtlasStrings.Fmt(TAtlasTextId.DebugExceptionsSummary, [Length(FHistory), FTotal]);
end;

function TAtlasDebugExceptionsFrame.TrySelected(out AException: TAtlasDebugException): Boolean;
begin
  Result := (FList <> nil) and (FList.Selected <> nil) and (FList.Selected.Index <= High(FShown));
  if Result then
    AException := FShown[FList.Selected.Index]
  else
    AException := Default(TAtlasDebugException);
end;

procedure TAtlasDebugExceptionsFrame.OpenSelected;
var
  Entry: TAtlasDebugException;
begin
  if TrySelected(Entry) and Entry.HasSource and Assigned(FOnOpen) then
    FOnOpen(Entry);
end;

procedure TAtlasDebugExceptionsFrame.CopySelected;
var
  Entry: TAtlasDebugException;
begin
  if TrySelected(Entry) and Assigned(FOnCopy) then
    FOnCopy(Entry);
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
      FList.Items[0].Selected := True;
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

function TAtlasDebugExceptionsFrame.ListColor(AColor: TColor): TColor;
begin
  // Stil der Liste, nicht der globale: Die IDE themt ihre Fenster je Formular.
  Result := ColorToRGB(StyleServices(FList).GetSystemColor(AColor));
end;

procedure TAtlasDebugExceptionsFrame.RowColors(ACanvas: TCanvas; AState: TCustomDrawState; AGray: Boolean);
begin
  // Farben ausdrücklich aus dem Stil der Liste (wie die Lesezeichenliste), sonst im dunklen Thema weiße Zellen.
  if cdsSelected in AState then
  begin
    ACanvas.Brush.Color := ListColor(clHighlight);
    ACanvas.Font.Color := ListColor(clHighlightText);
  end
  else
  begin
    ACanvas.Brush.Color := ListColor(FList.Color);
    if AGray then
      ACanvas.Font.Color := ListColor(clGrayText)
    else
      ACanvas.Font.Color := ListColor(FList.Font.Color);
  end;
end;

procedure TAtlasDebugExceptionsFrame.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  // Still fortgesetzt: ganze Zeile grau.
  RowColors(Sender.Canvas, State, (Item <> nil) and (Item.Index <= High(FShown)) and FShown[Item.Index].Ignored);
end;

procedure TAtlasDebugExceptionsFrame.ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  RowColors(Sender.Canvas, State, (Item <> nil) and (Item.Index <= High(FShown)) and FShown[Item.Index].Ignored);
end;

procedure TAtlasDebugExceptionsFrame.MenuPopup(Sender: TObject);
var
  Entry: TAtlasDebugException;
  Has, Ignored: Boolean;
begin
  Has := TrySelected(Entry);
  Ignored := Has and FIgnore.IgnoresClass(Entry.ExceptionClass);
  FOpenItem.Enabled := Has and Entry.HasSource;
  FIgnoreItem.Visible := not Ignored;
  FIgnoreItem.Enabled := Has;
  FStopItem.Visible := Ignored;
  FCopyItem.Enabled := Has;
  FClearItem.Enabled := FHistory <> nil;
  if Has then
  begin
    FIgnoreItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.DebugExceptionsIgnoreClassNamed, [Entry.ExceptionClass]);
    FStopItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.DebugExceptionsStopAgainNamed, [Entry.ExceptionClass]);
  end
  else
  begin
    FIgnoreItem.Caption := TAtlasStrings.Text(TAtlasTextId.DebugExceptionsIgnoreClass);
    FStopItem.Caption := TAtlasStrings.Text(TAtlasTextId.DebugExceptionsStopAgain);
  end;
end;

procedure TAtlasDebugExceptionsFrame.OpenClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TAtlasDebugExceptionsFrame.IgnoreClick(Sender: TObject);
var
  Entry: TAtlasDebugException;
begin
  if TrySelected(Entry) and Assigned(FOnIgnoreClass) then
    FOnIgnoreClass(Entry.ExceptionClass, True);
end;

procedure TAtlasDebugExceptionsFrame.StopClick(Sender: TObject);
var
  Entry: TAtlasDebugException;
begin
  if TrySelected(Entry) and Assigned(FOnIgnoreClass) then
    FOnIgnoreClass(Entry.ExceptionClass, False);
end;

procedure TAtlasDebugExceptionsFrame.CopyClick(Sender: TObject);
begin
  CopySelected;
end;

procedure TAtlasDebugExceptionsFrame.ClearClick(Sender: TObject);
begin
  if Assigned(FOnClear) then
    FOnClear();
end;

end.
