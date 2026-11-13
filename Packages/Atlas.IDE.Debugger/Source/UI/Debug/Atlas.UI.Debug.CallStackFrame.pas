unit Atlas.UI.Debug.CallStackFrame;

// Inhalt des Seitenfensters „Atlas-Aufrufstapel“ (#843), reine VCL: oben Suche, „Mit letztem Halt vergleichen“,
// „Kopieren“ (Menü: als Text, als Markdown, nur eigener Code) und die Statuszeile; darunter die Liste der Rahmen
// (Routine mit Parametern, Unit:Zeile), rechts bei eingeschaltetem Vergleich der Stapel beim letzten Halt an
// derselben Stelle; unten die Tastenhinweise.
//   - Bibliotheksrahmen in Folge stehen grau als eine Zeile „▸ 7 Aufrufe in VCL“ mit erster und letzter Routine;
//     Enter oder Doppelklick klappt auf (OnExpand), auf einem Rahmen springt es (OnOpenFrame).
//   - Treffer der Suche stehen fett in der Akzentfarbe, zugeklappte Gruppen nennen ihre Treffer.
//   - Mit Vergleich sind neue Rahmen und Rahmen mit geänderten Parametern mit „≠“ und in der Warnfarbe markiert.
// Die Leiste oben ist ein eigenes Steuerelement (TAtlasCallStackBar). Die IDE-Schicht ruft nach jedem Halt SetStack
// und nach jeder Auswertung UpdateStack. Die DFM ist leer; aufgebaut wird im Code, gefüllt erst mit Fenster
// (CreateWnd).

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
  Atlas.Core.Debug.OwnCode,
  Atlas.Core.Debug.CallStackView,
  Atlas.UI.Debug.Strings;

type
  /// <summary>Leiste über der Liste: Suche, „Mit letztem Halt vergleichen“, „Kopieren“ mit Menü und Statuszeile.
  /// OnChange nach Eingabe in der Suche und Klick auf den Vergleich, OnCopy nach der Wahl im Menü
  /// (Markdown?).</summary>
  TAtlasCallStackBar = class(TPanel)
  private
    FSearch: TEdit;
    FCompare: TCheckBox;
    FCopy: TButton;
    FCopyMenu: TPopupMenu;
    FOwnOnly: TMenuItem;
    FStatus: TLabel;
    FOnChange: TNotifyEvent;
    FOnCopy: TProc<Boolean>;
    procedure Changed(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure CopyTextClick(Sender: TObject);
    procedure CopyMarkdownClick(Sender: TObject);
    function MenuItem(ACaption: TAtlasDebugTextId; AClick: TNotifyEvent): TMenuItem;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Suchtext ohne Leerzeichen am Rand.</summary>
    function Query: string;
    function Comparing: Boolean;
    property SearchEdit: TEdit read FSearch;
    property CompareCheck: TCheckBox read FCompare;
    property OwnOnlyItem: TMenuItem read FOwnOnly;
    property StatusLabel: TLabel read FStatus;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnCopy: TProc<Boolean> read FOnCopy write FOnCopy;
  end;

  TAtlasDebugCallStackFrame = class(TFrame)
  private
    FBar: TAtlasCallStackBar;
    FList: TListView;
    FSplitter: TSplitter;
    FPrevious: TListView;
    FStack: TAtlasDebugStackView;
    FPrev: TAtlasDebugStackView;
    FHasPrevious: Boolean;
    FRows: TAtlasDebugStackRows;
    FExpanded: TArray<Integer>;
    FStatusText: string;
    FFilled: Boolean;
    FOnOpenFrame: TProc<Integer>;
    FOnExpand: TProc;
    FOnCopied: TProc<Integer>;
    procedure BuildLists;
    procedure Fill;
    procedure FillPrevious;
    function RowIndex(AItem: TListItem): Integer;
    procedure BarChange(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure PreviousCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure DrawRow(ACanvas: TCanvas; AItem: TListItem; AState: TCustomDrawState);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Neuer Halt: Stapel zeigen, Gruppen zu. APrevious: Stapel beim letzten Halt an derselben Stelle
    /// (AHasPrevious); beide schon verglichen.</summary>
    procedure SetStack(const AStack, APrevious: TAtlasDebugStackView; AHasPrevious: Boolean);
    /// <summary>Namen oder Werte sind nachgekommen: neu zeichnen, Auswahl und Gruppen bleiben.</summary>
    procedure UpdateStack(const AStack, APrevious: TAtlasDebugStackView);
    /// <summary>Nur eine Zeile (Programm läuft); die Liste ist leer.</summary>
    procedure ShowStatus(const AText: string);
    /// <summary>Zeile AIndex ausführen: Gruppe aufklappen (OnExpand) bzw. Rahmen melden (OnOpenFrame).</summary>
    procedure OpenRow(AIndex: Integer);
    /// <summary>Text zum Kopieren nach der Wahl im Menü (nur eigener Code).</summary>
    function CopyText(AMarkdown: Boolean): string;
    /// <summary>In die Zwischenablage; meldet die Zahl der Rahmen (OnCopied).</summary>
    procedure CopyToClipboard(AMarkdown: Boolean);
    property Bar: TAtlasCallStackBar read FBar;
    property List: TListView read FList;
    property PreviousList: TListView read FPrevious;
    property Rows: TAtlasDebugStackRows read FRows;
    property OnOpenFrame: TProc<Integer> read FOnOpenFrame write FOnOpenFrame;
    property OnExpand: TProc read FOnExpand write FOnExpand;
    property OnCopied: TProc<Integer> read FOnCopied write FOnCopied;
  end;

  /// <summary>Texte der Zeilen, ohne Fenster prüfbar.</summary>
  TAtlasCallStackTexts = class
  public const
    cChangedMark = '≠ ';
  public
    class function FrameText(const AEntry: TAtlasDebugStackEntry; AComparing: Boolean): string; static;
    class function GroupText(const AStack: TAtlasDebugStackView; const ARow: TAtlasDebugStackRow;
      const AQuery: string): string; static;
    class function StatusText(const AStack: TAtlasDebugStackView; const ARows: TAtlasDebugStackRows;
      const AQuery: string): string; static;
    /// <summary>Zellen einer Zeile: Rahmen bzw. Gruppe, dann Unit:Zeile bzw. erste und letzte Routine.</summary>
    class function RowCells(const AStack: TAtlasDebugStackView; const ARow: TAtlasDebugStackRow;
      const AQuery: string; AComparing: Boolean): TArray<string>; static;
  end;

implementation

uses
  System.Types,
  Winapi.Windows,
  Vcl.Clipbrd,
  Atlas.UI.Debug.ExceptionStack;

{$R *.dfm}

const
  cBarHeight = 28;
  cGap = 6;
  cEditTop = 3;
  cSearchWidth = 200;
  cCompareWidth = 190;
  cButtonWidth = 90;
  cFrameColumn = 420;
  cLocationColumn = 150;
  cPreviousWidth = 300;
  cPreviousColumn = 280;
  cBasePpi = 96;
  cChangedColor = TColor($0050A0E0);
  cHitColor = TColor($00D08020);

{ TAtlasCallStackTexts }

class function TAtlasCallStackTexts.FrameText(const AEntry: TAtlasDebugStackEntry; AComparing: Boolean): string;
begin
  Result := AEntry.Text;
  if AComparing and (AEntry.Changed or AEntry.ParamsChanged) then
  begin
    Result := cChangedMark + Result;
  end;
end;

class function TAtlasCallStackTexts.GroupText(const AStack: TAtlasDebugStackView; const ARow: TAtlasDebugStackRow;
  const AQuery: string): string;
var
  mArea: string;
  mHits: Integer;
begin
  mArea := AStack.Area(ARow);
  if mArea = '' then
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.CallStackGroupMixed, [ARow.Count]);
  end
  else
  begin
    Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.CallStackGroup, [ARow.Count, mArea]);
  end;
  mHits := AStack.Hits(ARow, AQuery);
  if mHits > 0 then
  begin
    Result := Result + TAtlasDebugStrings.Fmt(TAtlasDebugTextId.CallStackGroupHits, [mHits]);
  end;
end;

class function TAtlasCallStackTexts.StatusText(const AStack: TAtlasDebugStackView; const ARows: TAtlasDebugStackRows;
  const AQuery: string): string;
var
  mOwn, mHits, mIndex: Integer;
  mRow: TAtlasDebugStackRow;
begin
  mOwn := 0;
  for mIndex := 0 to AStack.Count - 1 do
  begin
    if AStack.Entries[mIndex].Frame.Own then
    begin
      Inc(mOwn);
    end;
  end;
  Result := TAtlasDebugStrings.Fmt(TAtlasDebugTextId.CallStackStatus, [AStack.Count, mOwn]);
  if Trim(AQuery) = '' then
  begin
    Exit;
  end;
  mHits := 0;
  for mRow in ARows do
  begin
    Inc(mHits, AStack.Hits(mRow, AQuery));
  end;
  Result := Result + ' · ' + TAtlasDebugStrings.Fmt(TAtlasDebugTextId.CallStackHits, [mHits]);
end;

class function TAtlasCallStackTexts.RowCells(const AStack: TAtlasDebugStackView; const ARow: TAtlasDebugStackRow;
  const AQuery: string; AComparing: Boolean): TArray<string>;
begin
  if ARow.Kind = TAtlasDebugStackRowKind.LibraryGroup then
  begin
    Result := [GroupText(AStack, ARow, AQuery), AStack.Hint(ARow)];
  end
  else
  begin
    Result := [FrameText(AStack.Entries[ARow.First], AComparing), AStack.Entries[ARow.First].Location];
  end;
end;

{ TAtlasCallStackBar }

constructor TAtlasCallStackBar.Create(AOwner: TComponent);
var
  mLeft: Integer;
begin
  inherited Create(AOwner);
  BevelOuter := bvNone;
  mLeft := MulDiv(cGap, CurrentPPI, cBasePpi);
  FSearch := TEdit.Create(Self);
  FSearch.TextHint := TAtlasDebugStrings.Text(TAtlasDebugTextId.CallStackSearchHint);
  FSearch.SetBounds(mLeft, MulDiv(cEditTop, CurrentPPI, cBasePpi), MulDiv(cSearchWidth, CurrentPPI, cBasePpi),
    MulDiv(cBarHeight - cGap, CurrentPPI, cBasePpi));
  FSearch.OnChange := Changed;
  FSearch.Parent := Self;
  FCompare := TCheckBox.Create(Self);
  FCompare.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.CallStackCompare);
  FCompare.SetBounds(FSearch.Left + FSearch.Width + mLeft, FSearch.Top, MulDiv(cCompareWidth, CurrentPPI, cBasePpi),
    FSearch.Height);
  FCompare.OnClick := Changed;
  FCompare.Parent := Self;
  FCopyMenu := TPopupMenu.Create(Self);
  FCopyMenu.Items.Add(MenuItem(TAtlasDebugTextId.CallStackCopyText, CopyTextClick));
  FCopyMenu.Items.Add(MenuItem(TAtlasDebugTextId.CallStackCopyMarkdown, CopyMarkdownClick));
  FCopyMenu.Items.Add(NewLine);
  FOwnOnly := MenuItem(TAtlasDebugTextId.CallStackCopyOwnOnly, nil);
  FOwnOnly.AutoCheck := True;
  FCopyMenu.Items.Add(FOwnOnly);
  FCopy := TButton.Create(Self);
  FCopy.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.CallStackCopy) + ' ▾';
  FCopy.SetBounds(FCompare.Left + FCompare.Width + mLeft, FSearch.Top, MulDiv(cButtonWidth, CurrentPPI, cBasePpi),
    FSearch.Height);
  FCopy.OnClick := CopyClick;
  FCopy.Parent := Self;
  FStatus := TLabel.Create(Self);
  FStatus.Left := FCopy.Left + FCopy.Width + mLeft;
  FStatus.Top := FSearch.Top + MulDiv(cGap, CurrentPPI, cBasePpi) div 2;
  FStatus.Parent := Self;
end;

function TAtlasCallStackBar.MenuItem(ACaption: TAtlasDebugTextId; AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FCopyMenu);
  Result.Caption := TAtlasDebugStrings.Text(ACaption);
  Result.OnClick := AClick;
end;

function TAtlasCallStackBar.Query: string;
begin
  Result := Trim(FSearch.Text);
end;

function TAtlasCallStackBar.Comparing: Boolean;
begin
  Result := FCompare.Checked;
end;

procedure TAtlasCallStackBar.Changed(Sender: TObject);
begin
  if Assigned(FOnChange) then
  begin
    FOnChange(Self);
  end;
end;

procedure TAtlasCallStackBar.CopyClick(Sender: TObject);
var
  mPoint: TPoint;
begin
  mPoint := FCopy.ClientToScreen(TPoint.Create(0, FCopy.Height));
  FCopyMenu.Popup(mPoint.X, mPoint.Y);
end;

procedure TAtlasCallStackBar.CopyTextClick(Sender: TObject);
begin
  if Assigned(FOnCopy) then
  begin
    FOnCopy(False);
  end;
end;

procedure TAtlasCallStackBar.CopyMarkdownClick(Sender: TObject);
begin
  if Assigned(FOnCopy) then
  begin
    FOnCopy(True);
  end;
end;

{ TAtlasDebugCallStackFrame }

constructor TAtlasDebugCallStackFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FBar := TAtlasCallStackBar.Create(Self);
  FBar.Top := 0;
  FBar.Height := MulDiv(cBarHeight, CurrentPPI, cBasePpi);
  FBar.Align := alTop;
  FBar.Parent := Self;
  FBar.OnChange := BarChange;
  FBar.OnCopy :=
    procedure(AMarkdown: Boolean)
    begin
      CopyToClipboard(AMarkdown);
    end;
  BuildLists;
end;

/// <summary>Spalte mit ACaption und AWidth (logische Pixel) an AList.</summary>
procedure AddColumn(AList: TListView; const ACaption: string; AWidth: Integer);
var
  mColumn: TListColumn;
begin
  mColumn := AList.Columns.Add;
  mColumn.Caption := ACaption;
  mColumn.Width := MulDiv(AWidth, AList.CurrentPPI, cBasePpi);
end;

/// <summary>Liste für Rahmen: Bericht, ganze Zeile, nur lesen.</summary>
function NewList(AOwner: TComponent; AParent: TWinControl): TListView;
begin
  Result := TListView.Create(AOwner);
  Result.ViewStyle := vsReport;
  Result.RowSelect := True;
  Result.HideSelection := False;
  Result.ReadOnly := True;
  Result.MultiSelect := False;
  Result.ColumnClick := False;
  Result.Parent := AParent;
end;

procedure TAtlasDebugCallStackFrame.BuildLists;
var
  mFooter: TLabel;
begin
  mFooter := TLabel.Create(Self);
  mFooter.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.CallStackFooter);
  mFooter.Align := alBottom;
  mFooter.Parent := Self;
  FPrevious := NewList(Self, Self);
  FPrevious.Width := MulDiv(cPreviousWidth, CurrentPPI, cBasePpi);
  FPrevious.Align := alRight;
  FPrevious.Visible := False;
  AddColumn(FPrevious, TAtlasDebugStrings.Text(TAtlasDebugTextId.CallStackPrevious), cPreviousColumn);
  FPrevious.OnCustomDrawItem := PreviousCustomDrawItem;
  FSplitter := TSplitter.Create(Self);
  FSplitter.Align := alRight;
  FSplitter.Visible := False;
  FSplitter.Parent := Self;
  FList := NewList(Self, Self);
  FList.Align := alClient;
  AddColumn(FList, TAtlasDebugStrings.Text(TAtlasDebugTextId.CallStackColumnFrame), cFrameColumn);
  AddColumn(FList, TAtlasDebugStrings.Text(TAtlasDebugTextId.CallStackColumnLocation), cLocationColumn);
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  FList.OnCustomDrawSubItem := ListCustomDrawSubItem;
end;

procedure TAtlasDebugCallStackFrame.CreateWnd;
begin
  inherited CreateWnd;
  if not FFilled then
  begin
    Fill;
  end;
end;

procedure TAtlasDebugCallStackFrame.SetStack(const AStack, APrevious: TAtlasDebugStackView; AHasPrevious: Boolean);
begin
  FStack := AStack;
  FPrev := APrevious;
  FHasPrevious := AHasPrevious;
  FExpanded := nil;
  FStatusText := '';
  FFilled := False;
  if HandleAllocated then
  begin
    Fill;
  end;
end;

procedure TAtlasDebugCallStackFrame.UpdateStack(const AStack, APrevious: TAtlasDebugStackView);
var
  mSelected: Integer;
begin
  FStack := AStack;
  FPrev := APrevious;
  if not HandleAllocated then
  begin
    FFilled := False;
    Exit;
  end;
  mSelected := -1;
  if FList.Selected <> nil then
  begin
    mSelected := FList.Selected.Index;
  end;
  Fill;
  if (mSelected >= 0) and (mSelected < FList.Items.Count) then
  begin
    FList.Items[mSelected].Selected := True;
  end;
end;

procedure TAtlasDebugCallStackFrame.ShowStatus(const AText: string);
begin
  SetStack(Default(TAtlasDebugStackView), Default(TAtlasDebugStackView), False);
  FStatusText := AText;
  FBar.StatusLabel.Caption := AText;
end;

procedure TAtlasDebugCallStackFrame.Fill;
var
  mRow: TAtlasDebugStackRow;
  mCells: TArray<string>;
  mItem: TListItem;
begin
  FFilled := True;
  FRows := FStack.Rows(FExpanded);
  FList.HandleNeeded;
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for mRow in FRows do
    begin
      mCells := TAtlasCallStackTexts.RowCells(FStack, mRow, FBar.Query, FBar.Comparing);
      mItem := FList.Items.Add;
      mItem.Caption := mCells[0];
      mItem.SubItems.Add(mCells[1]);
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if FStatusText = '' then
  begin
    FBar.StatusLabel.Caption := TAtlasCallStackTexts.StatusText(FStack, FRows, FBar.Query);
  end;
  FillPrevious;
end;

procedure TAtlasDebugCallStackFrame.FillPrevious;
var
  mEntry: TAtlasDebugStackEntry;
  mItem: TListItem;
begin
  FPrevious.Visible := FBar.Comparing;
  FSplitter.Visible := FBar.Comparing;
  if FSplitter.Visible then
  begin
    FSplitter.Left := FPrevious.Left - 1;
  end;
  if not FBar.Comparing then
  begin
    Exit;
  end;
  FPrevious.HandleNeeded;
  FPrevious.Items.BeginUpdate;
  try
    FPrevious.Items.Clear;
    if not FHasPrevious then
    begin
      FPrevious.Items.Add.Caption := TAtlasDebugStrings.Text(TAtlasDebugTextId.CallStackNoPrevious);
      Exit;
    end;
    for mEntry in FPrev.Entries do
    begin
      mItem := FPrevious.Items.Add;
      mItem.Caption := TAtlasCallStackTexts.FrameText(mEntry, True);
    end;
  finally
    FPrevious.Items.EndUpdate;
  end;
end;

function TAtlasDebugCallStackFrame.RowIndex(AItem: TListItem): Integer;
begin
  Result := -1;
  if (AItem <> nil) and (AItem.Index <= High(FRows)) then
  begin
    Result := AItem.Index;
  end;
end;

procedure TAtlasDebugCallStackFrame.OpenRow(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FRows)) then
  begin
    Exit;
  end;
  if FRows[AIndex].Kind = TAtlasDebugStackRowKind.LibraryGroup then
  begin
    FExpanded := FExpanded + [FRows[AIndex].First];
    Fill;
    if AIndex < FList.Items.Count then
    begin
      FList.Items[AIndex].Selected := True;
    end;
    if Assigned(FOnExpand) then
    begin
      FOnExpand();
    end;
    Exit;
  end;
  if Assigned(FOnOpenFrame) then
  begin
    FOnOpenFrame(FRows[AIndex].First);
  end;
end;

function TAtlasDebugCallStackFrame.CopyText(AMarkdown: Boolean): string;
begin
  Result := FStack.CopyText(AMarkdown, FBar.OwnOnlyItem.Checked);
end;

procedure TAtlasDebugCallStackFrame.CopyToClipboard(AMarkdown: Boolean);
var
  mText: string;
begin
  mText := CopyText(AMarkdown);
  if mText = '' then
  begin
    Exit;
  end;
  Clipboard.AsText := mText;
  if Assigned(FOnCopied) then
  begin
    FOnCopied(Length(mText.Split([sLineBreak])));
  end;
end;

procedure TAtlasDebugCallStackFrame.BarChange(Sender: TObject);
begin
  if HandleAllocated then
  begin
    Fill;
  end;
end;

procedure TAtlasDebugCallStackFrame.ListDblClick(Sender: TObject);
begin
  OpenRow(RowIndex(FList.Selected));
end;

procedure TAtlasDebugCallStackFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    Key := 0;
    OpenRow(RowIndex(FList.Selected));
  end
  else if (ssCtrl in Shift) and (Key = Ord('C')) then
  begin
    Key := 0;
    CopyToClipboard(False);
  end
  else if (ssCtrl in Shift) and (Key = Ord('F')) then
  begin
    Key := 0;
    if FBar.SearchEdit.CanFocus and Showing then
    begin
      FBar.SearchEdit.SetFocus;
    end;
  end;
end;

procedure TAtlasDebugCallStackFrame.DrawRow(ACanvas: TCanvas; AItem: TListItem; AState: TCustomDrawState);
var
  mIndex: Integer;
  mRow: TAtlasDebugStackRow;
  mEntry: TAtlasDebugStackEntry;
begin
  mIndex := RowIndex(AItem);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mRow := FRows[mIndex];
  TAtlasDebugExceptionStack.RowColors(ACanvas, FList, AState, mRow.Faded);
  if FStack.Hits(mRow, FBar.Query) > 0 then
  begin
    ACanvas.Font.Style := [fsBold];
    if not (cdsSelected in AState) then
    begin
      ACanvas.Font.Color := cHitColor;
    end;
    Exit;
  end;
  if mRow.Kind <> TAtlasDebugStackRowKind.Frame then
  begin
    Exit;
  end;
  mEntry := FStack.Entries[mRow.First];
  if FBar.Comparing and (mEntry.Changed or mEntry.ParamsChanged) and not (cdsSelected in AState) then
  begin
    ACanvas.Font.Color := cChangedColor;
  end;
end;

procedure TAtlasDebugCallStackFrame.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  DrawRow(Sender.Canvas, Item, State);
end;

procedure TAtlasDebugCallStackFrame.ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  DrawRow(Sender.Canvas, Item, State);
end;

procedure TAtlasDebugCallStackFrame.PreviousCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mChanged: Boolean;
begin
  DefaultDraw := True;
  mChanged := FHasPrevious and (Item.Index <= High(FPrev.Entries)) and
    (FPrev.Entries[Item.Index].Changed or FPrev.Entries[Item.Index].ParamsChanged);
  TAtlasDebugExceptionStack.RowColors(Sender.Canvas, FPrevious, State, not FHasPrevious);
  if mChanged and not (cdsSelected in State) then
  begin
    Sender.Canvas.Font.Color := cChangedColor;
  end;
end;

end.
