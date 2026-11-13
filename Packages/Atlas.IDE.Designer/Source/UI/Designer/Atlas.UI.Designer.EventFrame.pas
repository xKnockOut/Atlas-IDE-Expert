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
  Winapi.Windows, // vor Vcl.Graphics, sonst verdeckt es TBitmap
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
  private type
    /// <summary>Anfangseinträge einer Klappliste: Items braucht ein Fenster, gefüllt wird in CreateWnd.</summary>
    TComboFill = record
      Combo: TComboBox;
      Items: TArray<string>;
    end;

    /// <summary>Steuerelemente: Leiste mit Filter, Ereignis, „nur Befunde“, Gruppe; Liste mit Kontextmenü.</summary>
    TParts = record
      Top: TFlowPanel;
      Filter: TEdit;
      Event: TComboBox;
      OnlyFindings: TCheckBox;
      Group: TComboBox;
      List: TListView;
      Menu: TPopupMenu;
      RemoveItem: TMenuItem;
    end;
  private
    FComboFills: TArray<TComboFill>;
    FParts: TParts;
    FRows: TArray<TAtlasEventRow>;
    /// <summary>Je Listeneintrag der Index in FRows; -1 für eine Gruppenüberschrift.</summary>
    FItemRows: TArray<Integer>;
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
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
  protected
    procedure CreateWnd; override;
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
  Vcl.Themes,
  Atlas.Core.Style.Signal,
  Atlas.UI.Foundation.Theme,
  Atlas.UI.Designer.ViewStrings;

{$R *.dfm}

/// <summary>Breite von AText in AFont (ein TFrame hat kein eigenes Canvas).</summary>
function TextWidthIn(AFont: TFont; const AText: string): Integer;
var
  mBitmap: TBitmap;
begin
  mBitmap := TBitmap.Create;
  try
    mBitmap.Canvas.Font := AFont;
    Result := mBitmap.Canvas.TextWidth(AText);
  finally
    mBitmap.Free;
  end;
end;

const
  cBasePpi = 96;
  cColumnWidths: array[0..5] of Integer = (120, 100, 100, 150, 60, 180);
  cColumnTexts: array[0..5] of TAtlasDesignerViewTextId = (TAtlasDesignerViewTextId.EmColComponent,
    TAtlasDesignerViewTextId.EmColClass, TAtlasDesignerViewTextId.EmColEvent, TAtlasDesignerViewTextId.EmColHandler,
    TAtlasDesignerViewTextId.EmColLines, TAtlasDesignerViewTextId.EmColFinding);
  cComboWidth = 140;
  cCheckBoxBox = 24;
  /// <summary>Breite des Filterfelds, logische Pixel.</summary>
  cFilterWidth = 240;

  cNoGroup = '–';
  cLinesColumn = 4;

{ TAtlasEventFrame }

constructor TAtlasEventFrame.Create(AOwner: TComponent);
var
  mIndex: Integer;
  mColumn: TListColumn;
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FErrorColor := TAtlasUiTheme.TextColor(TAtlasSignalKind.Error);
  FLastJump := -1;
  // Fließende Leiste: Ist das Fenster schmal, brechen Häkchen und Auswahllisten in weitere Zeilen um, statt
  // den Filter auf null zu schrumpfen.
  FParts.Top := TFlowPanel.Create(Self);
  FParts.Top.Parent := Self;
  FParts.Top.Align := alTop;
  FParts.Top.BevelOuter := bvNone;
  FParts.Top.ShowCaption := False;
  FParts.Top.AutoWrap := True;
  FParts.Top.AutoSize := True;
  FParts.Filter := TEdit.Create(Self);
  FParts.Filter.Parent := FParts.Top;
  FParts.Filter.AlignWithMargins := True;
  FParts.Filter.Width := MulDiv(cFilterWidth, CurrentPPI, cBasePpi);
  FParts.Filter.TextHint := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StFilter);
  FParts.Filter.OnChange := OptionsChanged;
  FParts.OnlyFindings := TCheckBox.Create(Self);
  FParts.OnlyFindings.Parent := FParts.Top;
  FParts.OnlyFindings.AlignWithMargins := True;
  FParts.OnlyFindings.Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmOnlyFindings);
  FParts.OnlyFindings.Width := TextWidthIn(Font, FParts.OnlyFindings.Caption) +
    MulDiv(cCheckBoxBox, CurrentPPI, cBasePpi);
  FParts.OnlyFindings.Height := FParts.Filter.Height;
  FParts.OnlyFindings.OnClick := OptionsChanged;
  FParts.Group := AddCombo([TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmGroupComponent),
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmGroupEvent),
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmGroupHandler)]);
  FParts.Event := AddCombo([TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmAllEvents)]);
  FParts.Menu := TPopupMenu.Create(Self);
  FParts.Menu.OnPopup := MenuPopup;
  AddMenuItem(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmShow), ShowClick);
  AddMenuItem(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmRename), RenameClick);
  FParts.RemoveItem := AddMenuItem(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmRemove), RemoveClick);
  FParts.List := TListView.Create(Self);
  FParts.List.Parent := Self;
  FParts.List.Align := alClient;
  FParts.List.ViewStyle := vsReport;
  FParts.List.RowSelect := True;
  FParts.List.ReadOnly := True;
  FParts.List.HideSelection := False;
  // Keine Gruppen von Windows: Deren Köpfe folgen nicht dem IDE-Thema (dunkelblau auf dunkel). Überschriften
  // sind eigene Zeilen, gezeichnet in ListCustomDrawItem.
  FParts.List.PopupMenu := FParts.Menu;
  for mIndex := 0 to High(cColumnWidths) do
  begin
    mColumn := FParts.List.Columns.Add;
    mColumn.Caption := TAtlasDesignerViewStrings.Text(cColumnTexts[mIndex]);
    mColumn.Width := MulDiv(cColumnWidths[mIndex], CurrentPPI, cBasePpi);
  end;
  FParts.List.Columns[cLinesColumn].Alignment := taRightJustify;
  FParts.List.OnDblClick := ListDblClick;
  FParts.List.OnCustomDrawItem := ListCustomDrawItem;
  FParts.List.OnSelectItem := ListSelectItem;
end;

procedure TAtlasEventFrame.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
begin
  // Überschriften sind nicht wählbar: Windows malt die Auswahl ohne Fokus hell (weiß im dunklen Thema), und
  // eine gewählte Überschrift hat ohnehin keine Aktion.
  if Selected and (Item <> nil) and (Item.Index <= High(FItemRows)) and (FItemRows[Item.Index] < 0) then
  begin
    Item.Selected := False;
  end;
end;

function TAtlasEventFrame.AddCombo(const AItems: array of string): TComboBox;
var
  mItem: string;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := FParts.Top;
  Result.AlignWithMargins := True;
  Result.Style := csDropDownList;
  Result.Width := MulDiv(cComboWidth, CurrentPPI, cBasePpi);
  // Items braucht ein Fenster (ohne Parent: kein übergeordnetes Fenster): erst in CreateWnd füllen.
  SetLength(FComboFills, Length(FComboFills) + 1);
  FComboFills[High(FComboFills)].Combo := Result;
  FComboFills[High(FComboFills)].Items := nil;
  for mItem in AItems do
  begin
    FComboFills[High(FComboFills)].Items := FComboFills[High(FComboFills)].Items + [mItem];
  end;
  Result.OnChange := OptionsChanged;
end;

procedure TAtlasEventFrame.CreateWnd;
var
  mFill: TComboFill;
  mItem: string;
begin
  inherited CreateWnd;
  for mFill in FComboFills do
  begin
    // Bei jedem neuen Fenster nur, solange die Liste noch leer ist (Einträge von Fill bleiben).
    if mFill.Combo.Items.Count = 0 then
    begin
      mFill.Combo.Items.BeginUpdate;
      try
        for mItem in mFill.Items do
        begin
          mFill.Combo.Items.Add(mItem);
        end;
      finally
        mFill.Combo.Items.EndUpdate;
      end;
      mFill.Combo.ItemIndex := 0;
    end;
  end;
end;

function TAtlasEventFrame.AddMenuItem(const ACaption: string; const AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FParts.Menu);
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
  FParts.Menu.Items.Add(Result);
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
  Result := Trim(FParts.Filter.Text);
end;

function TAtlasEventFrame.EventFilter: string;
begin
  Result := '';
  if FParts.Event.ItemIndex > 0 then
  begin
    Result := FParts.Event.Items[FParts.Event.ItemIndex];
  end;
end;

function TAtlasEventFrame.OnlyFindings: Boolean;
begin
  Result := FParts.OnlyFindings.Checked;
end;

function TAtlasEventFrame.Group: TAtlasEventGroup;
begin
  case FParts.Group.ItemIndex of
    1:
      Result := TAtlasEventGroup.Event;
    2:
      Result := TAtlasEventGroup.Handler;
  else
    Result := TAtlasEventGroup.Component;
  end;
end;

/// <summary>Überschrift der Gruppe von ARow.</summary>
function HeaderOf(const ARow: TAtlasEventRow; AGroup: TAtlasEventGroup): string;
begin
  Result := TAtlasEventMap.GroupKey(ARow, AGroup);
  if Result = '' then
  begin
    Result := cNoGroup;
  end
  else if (AGroup = TAtlasEventGroup.Handler) and (ARow.UseCount > 1) then
  begin
    Result := Result + ' (' + IntToStr(ARow.UseCount) + ')';
  end;
end;

procedure TAtlasEventFrame.FillEvents(const AEvents: TArray<string>);
var
  mCurrent, mEvent: string;
begin
  mCurrent := EventFilter;
  FParts.Event.Items.BeginUpdate;
  try
    while FParts.Event.Items.Count > 1 do
    begin
      FParts.Event.Items.Delete(1);
    end;
    for mEvent in AEvents do
    begin
      FParts.Event.Items.Add(mEvent);
    end;
    FParts.Event.ItemIndex := FParts.Event.Items.IndexOf(mCurrent);
    if FParts.Event.ItemIndex < 0 then
    begin
      FParts.Event.ItemIndex := 0;
    end;
  finally
    FParts.Event.Items.EndUpdate;
  end;
end;

/// <summary>Listeneintrag für ARow: Komponente, Klasse, Ereignis, Handler, Zeilen (leer ohne), Befund.</summary>
procedure AddRowItem(AItems: TListItems; const ARow: TAtlasEventRow; const AFinding: string);
var
  mItem: TListItem;
begin
  mItem := AItems.Add;
  mItem.Caption := ARow.Component;
  mItem.SubItems.Add(ARow.ClassName);
  mItem.SubItems.Add(ARow.Event);
  mItem.SubItems.Add(ARow.Handler);
  if ARow.Lines > 0 then
  begin
    mItem.SubItems.Add(IntToStr(ARow.Lines));
  end
  else
  begin
    mItem.SubItems.Add('');
  end;
  mItem.SubItems.Add(AFinding);
end;

procedure TAtlasEventFrame.ShowRows(const ARows: TArray<TAtlasEventRow>; const AEvents: TArray<string>;
  const AFinding: TFunc<TAtlasEventRow, string>);
var
  mRow: TAtlasEventRow;
  mItem: TListItem;
  mHeaders: TStringList;
  mGroup: TAtlasEventGroup;
  mHeader: Integer;
  mIndex: Integer;
begin
  FUpdating := True;
  FParts.List.Items.BeginUpdate;
  mHeaders := TStringList.Create;
  try
    FillEvents(AEvents);
    FParts.List.Items.Clear;
    FRows := ARows;
    FItemRows := nil;
    FLastJump := -1;
    mGroup := Group;
    // Überschriften in der Reihenfolge ihres ersten Auftretens, darunter ihre Zeilen.
    for mRow in ARows do
    begin
      if mHeaders.IndexOf(HeaderOf(mRow, mGroup)) < 0 then
      begin
        mHeaders.Add(HeaderOf(mRow, mGroup));
      end;
    end;
    for mHeader := 0 to mHeaders.Count - 1 do
    begin
      mItem := FParts.List.Items.Add;
      mItem.Caption := mHeaders[mHeader];
      FItemRows := FItemRows + [-1];
      for mIndex := 0 to High(ARows) do
      begin
        mRow := ARows[mIndex];
        if HeaderOf(mRow, mGroup) <> mHeaders[mHeader] then
        begin
          Continue;
        end;
        AddRowItem(FParts.List.Items, mRow, AFinding(mRow));
        FItemRows := FItemRows + [mIndex];
      end;
    end;
  finally
    mHeaders.Free;
    FParts.List.Items.EndUpdate;
    FUpdating := False;
  end;
end;

function TAtlasEventFrame.SelectedRow(out ARow: TAtlasEventRow): Boolean;
begin
  // Überschriften (FItemRows = -1) sind keine Zeile.
  Result := (FParts.List.Selected <> nil) and (FParts.List.Selected.Index <= High(FItemRows)) and
    (FItemRows[FParts.List.Selected.Index] >= 0);
  if Result then
  begin
    ARow := FRows[FItemRows[FParts.List.Selected.Index]];
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
  if (FParts.List.Selected.Index = FLastJump) and (mRow.Component <> '') and Assigned(FOnShow) then
  begin
    FLastJump := -1;
    FOnShow(mRow);
  end
  else if Assigned(FOnJump) then
  begin
    FLastJump := FParts.List.Selected.Index;
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
  for mItem := 0 to FParts.Menu.Items.Count - 1 do
  begin
    FParts.Menu.Items[mItem].Enabled := mHas;
  end;
  FParts.RemoveItem.Enabled := mHas and (mRow.Finding in [TAtlasEventFinding.Empty, TAtlasEventFinding.Unassigned]);
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
var
  mRow: Integer;
begin
  // Aufgebaut wie die Liste der Atlas-Prüfung (TAtlasProblemsFrameList.ListCustomDrawItem).
  DefaultDraw := True;
  if (Item = nil) or (Item.Index > High(FItemRows)) then
  begin
    Exit;
  end;
  mRow := FItemRows[Item.Index];
  if mRow < 0 then
  begin
    Sender.Canvas.Font.Style := [fsBold];
  end
  else
  begin
    Sender.Canvas.Font.Style := [];
  end;
  // Farben immer ausdrücklich aus dem Stil der Liste: Nach geänderter Schrift (fett) zeichnet die Liste sonst mit
  // Systemfarben, im dunklen Thema also weiße Zellen. Ausgewählt laut Item.Selected: cdsSelected ist in der IDE
  // bei jeder Zeile gesetzt.
  if Item.Selected then
  begin
    Sender.Canvas.Brush.Color := ColorToRGB(StyleServices(FParts.List).GetSystemColor(clHighlight));
    Sender.Canvas.Font.Color := ColorToRGB(StyleServices(FParts.List).GetSystemColor(clHighlightText));
  end
  else
  begin
    Sender.Canvas.Brush.Color := ColorToRGB(StyleServices(FParts.List).GetSystemColor(clWindow));
    Sender.Canvas.Font.Color := ColorToRGB(StyleServices(FParts.List).GetSystemColor(clWindowText));
    if (mRow >= 0) and (FRows[mRow].Finding <> TAtlasEventFinding.None) then
    begin
      Sender.Canvas.Font.Color := FErrorColor;
    end;
  end;
end;

end.
