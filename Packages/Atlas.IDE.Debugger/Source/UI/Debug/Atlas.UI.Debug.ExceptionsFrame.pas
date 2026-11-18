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
// True/False), „Nur bei Meldungen wie dieser anhalten …“ und „Meldungen wie
// diese ignorieren …“ (#2549, MessageRule, nur mit Meldung), „Regeln mit
// Meldung für X entfernen“ (RemoveMessageRules, nur wenn es welche gibt),
// „Meldung kopieren“, „Verlauf leeren“ (OnClear). Die
// IDE-Schicht hält den Verlauf und ruft nach jeder Änderung SetHistory.
// Unten der Aufrufstapel des gewählten Eintrags (#578, Stack,
// TAtlasDebugExceptionStack). Filterleiste und Meldungen an die IDE-Schicht
// stehen in Atlas.UI.Debug.ExceptionsParts. Die DFM ist leer, weil TCustomFrame.Create für
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
  Atlas.UI.Debug.ExceptionStack,
  Atlas.UI.Debug.ExceptionsParts;

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
      FStopOnlyItem: TMenuItem;
      FIgnoreMessageItem: TMenuItem;
      FRemoveRulesItem: TMenuItem;
      FCopyItem: TMenuItem;
      FClearItem: TMenuItem;
      function AddItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
      procedure MenuPopup(Sender: TObject);
      procedure OpenClick(Sender: TObject);
      procedure IgnoreClick(Sender: TObject);
      procedure StopClick(Sender: TObject);
      procedure StopOnlyClick(Sender: TObject);
      procedure IgnoreMessageClick(Sender: TObject);
      procedure RemoveRulesClick(Sender: TObject);
      procedure MessageRule(AIgnore: Boolean);
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
  private
    FFilterBar: TAtlasDebugExceptionsFilterBar;
    FList: TListView;
    FStack: TAtlasDebugExceptionStack;
    FEmpty: TLabel;
    FSummary: TLabel;
    FMenu: TListMenu;
    FHistory: THistoryData;
    FIgnore: TAtlasDebugIgnoreList;
    /// <summary>Gezeigte Einträge in der Reihenfolge der Listenzeilen.</summary>
    FShown: TAtlasDebugExceptions;
    FHooks: TAtlasDebugExceptionsHooks;
    procedure BuildList;
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
    destructor Destroy; override;
    /// <summary>Verlauf und Ignorier-Liste zeigen; Filter und Auswahl bleiben, soweit möglich.</summary>
    procedure SetHistory(const AHistory: TAtlasDebugExceptionHistory; const AIgnore: TAtlasDebugIgnoreList);
    /// <summary>Gewählter Eintrag; False ohne Auswahl.</summary>
    function TrySelected(out AException: TAtlasDebugException): Boolean;
    procedure OpenSelected;
    procedure CopySelected;
    /// <summary>Text der Spalten einer Zeile: Uhrzeit, Klasse, Meldung, Anzahl, Ort, Thread.</summary>
    class function Cells(const AException: TAtlasDebugException; AIgnoredClass: Boolean): TArray<string>; static;
    property FilterBar: TAtlasDebugExceptionsFilterBar read FFilterBar;
    property List: TListView read FList;
    property EmptyLabel: TLabel read FEmpty;
    property SummaryLabel: TLabel read FSummary;
    property Shown: TAtlasDebugExceptions read FShown;
    /// <summary>Aufrufstapel des gewählten Eintrags (#578).</summary>
    property Stack: TAtlasDebugExceptionStack read FStack;
    /// <summary>Meldungen an die IDE-Schicht: springen, kopieren, Klasse ignorieren, Verlauf leeren.</summary>
    property Hooks: TAtlasDebugExceptionsHooks read FHooks;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Debug.Exceptions.Strings;

{$R *.dfm}

/// <summary>Spalte mit ACaption und AWidth (logische Pixel) an AList.</summary>
function AddColumn(AList: TListView; const ACaption: string; AWidth: Integer): TListColumn;
begin
  Result := AList.Columns.Add;
  Result.Caption := ACaption;
  Result.Width := MulDiv(AWidth, AList.CurrentPPI, 96);
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
  FOpenItem := AddItem(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsGoTo), OpenClick);
  FOpenItem.Default := True;
  FIgnoreItem := AddItem(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsIgnoreClass), IgnoreClick);
  FStopItem := AddItem(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsStopAgain), StopClick);
  FStopOnlyItem := AddItem(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsStopOnlyMessage),
    StopOnlyClick);
  FIgnoreMessageItem := AddItem(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsIgnoreMessage),
    IgnoreMessageClick);
  FRemoveRulesItem := AddItem('', RemoveRulesClick);
  FCopyItem := AddItem(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsCopy), CopyClick);
  FClearItem := AddItem(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsClear), ClearClick);
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
  FStopOnlyItem.Visible := mHas and FFrame.FHooks.MessageRulesOn and (Trim(mEntry.Message) <> '') and
    Assigned(FFrame.FHooks.MessageRule);
  FIgnoreMessageItem.Visible := FStopOnlyItem.Visible;
  FRemoveRulesItem.Visible := mHas and FFrame.FHooks.MessageRulesOn and Assigned(FFrame.FHooks.RemoveMessageRules) and
    FFrame.FIgnore.HasMessageRules(mEntry.ExceptionClass);
  FCopyItem.Enabled := mHas;
  FClearItem.Enabled := FFrame.FHistory.Entries <> nil;
  if mHas then
  begin
    FIgnoreItem.Caption := TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugExceptionsIgnoreClassNamed,
      [mEntry.ExceptionClass]);
    FStopItem.Caption := TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugExceptionsStopAgainNamed,
      [mEntry.ExceptionClass]);
    FRemoveRulesItem.Caption := TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugExceptionsRemoveMessageRules,
      [mEntry.ExceptionClass]);
  end
  else
  begin
    FIgnoreItem.Caption := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsIgnoreClass);
    FStopItem.Caption := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsStopAgain);
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
  if FFrame.TrySelected(mEntry) and Assigned(FFrame.FHooks.IgnoreClass) then
  begin
    FFrame.FHooks.IgnoreClass(mEntry.ExceptionClass, True);
  end;
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.StopClick(Sender: TObject);
var
  mEntry: TAtlasDebugException;
begin
  if FFrame.TrySelected(mEntry) and Assigned(FFrame.FHooks.IgnoreClass) then
  begin
    FFrame.FHooks.IgnoreClass(mEntry.ExceptionClass, False);
  end;
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.MessageRule(AIgnore: Boolean);
var
  mEntry: TAtlasDebugException;
begin
  if FFrame.TrySelected(mEntry) and Assigned(FFrame.FHooks.MessageRule) then
  begin
    FFrame.FHooks.MessageRule(mEntry, AIgnore);
  end;
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.StopOnlyClick(Sender: TObject);
begin
  MessageRule(False);
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.IgnoreMessageClick(Sender: TObject);
begin
  MessageRule(True);
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.RemoveRulesClick(Sender: TObject);
var
  mEntry: TAtlasDebugException;
begin
  if FFrame.TrySelected(mEntry) and Assigned(FFrame.FHooks.RemoveMessageRules) then
  begin
    FFrame.FHooks.RemoveMessageRules(mEntry.ExceptionClass);
  end;
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.CopyClick(Sender: TObject);
begin
  FFrame.CopySelected;
end;

procedure TAtlasDebugExceptionsFrame.TListMenu.ClearClick(Sender: TObject);
begin
  if Assigned(FFrame.FHooks.Clear) then
  begin
    FFrame.FHooks.Clear();
  end;
end;

{ TAtlasDebugExceptionsFrame }

constructor TAtlasDebugExceptionsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FIgnore := TAtlasDebugIgnoreList.Empty;
  FHooks := TAtlasDebugExceptionsHooks.Create;
  FFilterBar := TAtlasDebugExceptionsFilterBar.CreateIn(Self, FilterChange, FilterKeyDown);
  FSummary := GrayLabel(Self, alBottom);
  FSummary.Caption := '';
  // Aufrufstapel des gewählten Eintrags (#578) über der Summe.
  FStack := TAtlasDebugExceptionStack.CreateIn(Self);
  FMenu := TListMenu.CreateFor(Self);
  BuildList;
  // Ohne Exceptions: Hinweis statt leerer Liste.
  FEmpty := GrayLabel(Self, alClient);
  FEmpty.WordWrap := True; // window-ok: alClient, die Höhe kommt aus der Ausrichtung
  FEmpty.Caption := TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsEmpty);
  FEmpty.Visible := False;
end;

destructor TAtlasDebugExceptionsFrame.Destroy;
begin
  FreeAndNil(FHooks);
  inherited Destroy;
end;

procedure TAtlasDebugExceptionsFrame.BuildList;
const
  // Spaltenbreiten bei 96 dpi.
  cTimeWidth = 70;
  cClassWidth = 130;
  cMessageWidth = 260;
  cCountWidth = 60;
  cLocationWidth = 170;
  cThreadWidth = 110;
var
  mList: TListView;
begin
  mList := TListView.Create(Self);
  FList := mList;
  mList.Parent := Self;
  mList.Align := alClient;
  mList.AlignWithMargins := True;
  mList.ViewStyle := vsReport;
  mList.RowSelect := True;
  mList.HideSelection := False;
  mList.ReadOnly := True;
  mList.MultiSelect := False;
  mList.ColumnClick := False;
  mList.PopupMenu := FMenu;
  AddColumn(mList, TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsColumnTime), cTimeWidth);
  AddColumn(mList, TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsColumnClass), cClassWidth);
  AddColumn(mList, TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsColumnMessage), cMessageWidth);
  AddColumn(mList, TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsColumnCount),
    cCountWidth).Alignment := taRightJustify;
  AddColumn(mList, TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsColumnLocation), cLocationWidth);
  AddColumn(mList, TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsColumnThread), cThreadWidth);
  mList.OnDblClick := ListDblClick;
  mList.OnSelectItem := ListSelectItem;
  mList.OnKeyDown := ListKeyDown;
  mList.OnCustomDrawItem := ListCustomDrawItem;
  mList.OnCustomDrawSubItem := ListCustomDrawSubItem;
end;

procedure TAtlasDebugExceptionsFrame.CreateWnd;
begin
  inherited CreateWnd;
  // Die Auswahl der Klasse braucht ein Fenster (TComboBox.Items).
  FillClasses;
  Refill;
end;

procedure TAtlasDebugExceptionsFrame.FillClasses;
begin
  // Erst mit Fenster (CreateWnd): TComboBox.Items braucht eins.
  if HandleAllocated then
  begin
    FFilterBar.FillClasses(FHistory.Classes);
  end;
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
  mWords := TAtlasDebugException.FilterWords(FFilterBar.Filter.Text);
  mOnlyClass := FFilterBar.SelectedClass;
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
  FSummary.Caption := TAtlasExceptionsStrings.Fmt(TAtlasExceptionsTextId.DebugExceptionsSummary,
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
  if TrySelected(mEntry) and mEntry.HasSource and Assigned(FHooks.Open) then
  begin
    FHooks.Open(mEntry);
  end;
end;

procedure TAtlasDebugExceptionsFrame.CopySelected;
var
  mEntry: TAtlasDebugException;
begin
  if TrySelected(mEntry) and Assigned(FHooks.Copy) then
  begin
    FHooks.Copy(mEntry);
  end;
end;

class function TAtlasDebugExceptionsFrame.Cells(const AException: TAtlasDebugException;
  AIgnoredClass: Boolean): TArray<string>;
var
  mCount: string;
begin
  mCount := IntToStr(AException.Count);
  if AIgnoredClass then
  begin
    mCount := mCount + ' · ' + TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsIgnored);
  end;
  // Uhrzeit für die Anzeige: im Format des Benutzers.
  Result := TArray<string>.Create(FormatDateTime('hh:nn:ss', AException.LastTime, FormatSettings),
    AException.ExceptionClass, AException.Message, mCount, AException.LocationText,
    AException.ThreadText(TAtlasExceptionsStrings.Text(TAtlasExceptionsTextId.DebugExceptionsThread)));
end;

end.
