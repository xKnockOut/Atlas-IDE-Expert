unit Atlas.UI.Bookmarks.Frame;

// Inhalt des Seitenfensters „Lesezeichen“ (#622), reine VCL: oben ein
// Filterfeld (jedes Wort muss in Name, Datei, Methode oder Zeilenvorschau
// vorkommen, TAtlasBookmarkList.Filter) und der Schalter „nur diese Datei“
// (#1104), darunter die Liste mit den Spalten Nr., Name, Datei (mit Zeile),
// Methode und Zeilenvorschau in der Reihenfolge der Lesezeichen. „Nr.“ zeigt
// den Marker der schnellen Lesezeichen (#1104): die Ziffer, bei
// unnummerierten einen Punkt. Schnelle ohne Namen zeigen die Methode grau als
// Namen; nicht gefundene stehen grau mit „nicht gefunden“ vor der Vorschau.
// Unten der Speicherort (lokal bzw. für das Team).
// Bedienung: Klick, Doppelklick oder Enter springt hin (OnOpen), F2 benennt
// um (OnRename), Entf löscht (OnDelete), Ziehen mit der Maus oder
// Strg+↑/↓ sortiert um (OnMove: Kennung vor eine andere stellen, '' = ans
// Ende), Strg+Umschalt+1…9 vergibt die Nummer (OnNumber; dieselbe Nummer
// nochmals nimmt sie weg). Im Filterfeld führt ↓ in die Liste, Enter springt zum ersten
// Treffer. Kontextmenü: Springen, Umbenennen, Löschen. Die IDE-Schicht
// bettet den Frame in ein andockbares Fenster ein, hält die Lesezeichen und
// ruft nach jeder Änderung SetBookmarks. Die DFM ist leer, weil
// TCustomFrame.Create für abgeleitete Frames eine Ressource verlangt;
// aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Core.Bookmarks.Store;

const
  /// <summary>Marker unnummerierter schneller Lesezeichen in der Spalte „Nr.“.</summary>
  cAtlasQuickBookmarkDot = '•';

type
  TAtlasBookmarksFrame = class(TFrame)
  private type
    /// <summary>Steuerelemente des Frames.</summary>
    TParts = record
      Filter: TEdit;
      OnlyFile: TCheckBox;
      List: TListView;
      Empty: TLabel;
      Place: TLabel;
      Menu: TPopupMenu;
      OpenItem: TMenuItem;
      RenameItem: TMenuItem;
      DeleteItem: TMenuItem;
    end;

    /// <summary>Rückrufe an die IDE-Schicht.</summary>
    THandlers = record
      OnOpen: TProc<string>;
      OnRename: TProc<string, string>;
      OnDelete: TProc<string>;
      OnMove: TProc<string, string>;
      OnNumber: TProc<string, Integer>;
    end;

    /// <summary>Zustand von Maus und Namensbearbeitung.</summary>
    TMouse = record
      EditAllowed: Boolean;
      Dropped: Boolean;
      /// <summary>Der letzte Mausklick traf eine Zeile (nicht die freie Fläche).</summary>
      ClickedItem: Boolean;
    end;

    /// <summary>Ereignisse der Steuerelemente; gehört dem Frame.</summary>
    TEvents = class(TComponent)
    private
      FFrame: TAtlasBookmarksFrame;
    public
      constructor Create(AFrame: TAtlasBookmarksFrame); reintroduce;
      procedure FilterChange(Sender: TObject);
      procedure OnlyFileClick(Sender: TObject);
      procedure FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
      procedure FilterKeyPress(Sender: TObject; var Key: Char);
      procedure ListClick(Sender: TObject);
      procedure ListDblClick(Sender: TObject);
      procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
      procedure ListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
      procedure ListEditing(Sender: TObject; Item: TListItem; var AllowEdit: Boolean);
      procedure ListEdited(Sender: TObject; Item: TListItem; var S: string);
      procedure ListDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState; var Accept: Boolean);
      procedure ListDragDrop(Sender, Source: TObject; X, Y: Integer);
      procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
        var DefaultDraw: Boolean);
      procedure ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer;
        State: TCustomDrawState; var DefaultDraw: Boolean);
      procedure MenuPopup(Sender: TObject);
      procedure OpenClick(Sender: TObject);
      procedure RenameClick(Sender: TObject);
      procedure DeleteClick(Sender: TObject);
    end;
  private
    FParts: TParts;
    FHandlers: THandlers;
    FMouse: TMouse;
    FCurrentFile: string;
    FBookmarks: TAtlasBookmarkList;
    /// <summary>Gezeigte Lesezeichen in der Reihenfolge der Listenzeilen.</summary>
    FShown: TArray<TAtlasBookmark>;
    function IdAt(AIndex: Integer): string;
    procedure Refill(const ASelectId: string);
    /// <summary>Spalte „Nr.“ vorn zeigen, sobald die Liste ein Fenster hat.</summary>
    procedure ApplyColumnOrder;
  protected
    procedure CreateWnd; override;
  public const
    /// <summary>Index der Spalte „Nr.“ (hinten angelegt, vorn angezeigt).</summary>
    cNumberColumn = 4;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Datei im oberen Editor für „nur diese Datei“ (#1104).</summary>
    procedure SetCurrentFile(const AFileName: string);
    /// <summary>Strg+Umschalt+ANumber in der Liste: Nummer für das gewählte Lesezeichen.</summary>
    procedure NumberSelected(ANumber: Integer);
    /// <summary>Lesezeichen zeigen (Filter bleibt); APlace ist der Speicherort für die Fußzeile. ASelectId
    /// wählt ein Lesezeichen, sonst bleibt die bisherige Auswahl.</summary>
    procedure SetBookmarks(const AList: TAtlasBookmarkList; const APlace, ASelectId: string);
    /// <summary>Kennung des gewählten Lesezeichens; '' ohne Auswahl.</summary>
    function SelectedId: string;
    procedure OpenSelected;
    /// <summary>F2: Namen in der Liste bearbeiten.</summary>
    procedure BeginRename;
    procedure DeleteSelected;
    /// <summary>Gewähltes Lesezeichen um eine Zeile nach oben (-1) bzw. unten (+1) in der Anzeige.</summary>
    procedure MoveSelected(ADelta: Integer);
    /// <summary>Ziehen: AId vor ABeforeId stellen ('' = ans Ende).</summary>
    procedure Drop(const AId, ABeforeId: string);
    /// <summary>Text der Spalten einer Zeile: Name (ohne Namen die Methode), Datei mit Zeile, Methode, Vorschau,
    /// Nr. (Ziffer, • bei unnummerierten schnellen, sonst leer).</summary>
    class function Cells(const ABookmark: TAtlasBookmark): TArray<string>; static;
    property Filter: TEdit read FParts.Filter;
    property OnlyFileCheck: TCheckBox read FParts.OnlyFile;
    property List: TListView read FParts.List;
    property EmptyLabel: TLabel read FParts.Empty;
    property PlaceLabel: TLabel read FParts.Place;
    property Menu: TPopupMenu read FParts.Menu;
    property Shown: TArray<TAtlasBookmark> read FShown;
    property OnOpen: TProc<string> read FHandlers.OnOpen write FHandlers.OnOpen;
    /// <summary>Kennung und neuer Name (ohne Leerraum am Rand, nie leer).</summary>
    property OnRename: TProc<string, string> read FHandlers.OnRename write FHandlers.OnRename;
    property OnDelete: TProc<string> read FHandlers.OnDelete write FHandlers.OnDelete;
    /// <summary>Kennung und Kennung, vor die es soll ('' = ans Ende).</summary>
    property OnMove: TProc<string, string> read FHandlers.OnMove write FHandlers.OnMove;
    /// <summary>Kennung und Nummer 1–9 (#1104).</summary>
    property OnNumber: TProc<string, Integer> read FHandlers.OnNumber write FHandlers.OnNumber;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.CommCtrl,
  Vcl.Themes,
  Atlas.UI.Bookmarks.Strings,
  Atlas.Core.Marks.Ids;

{$R *.dfm}

function AddColumn(AList: TListView; const ACaption: string; AWidth, APPI: Integer): TListColumn;
begin
  Result := AList.Columns.Add;
  Result.Caption := ACaption;
  Result.Width := MulDiv(AWidth, APPI, 96);
end;

function AddMenuItem(AMenu: TPopupMenu; const ACaption: string; AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  AMenu.Items.Add(Result);
end;

function ListColor(AList: TListView; AColor: TColor): TColor;
begin
  // Stil der Liste, nicht der globale: Die IDE themt ihre Fenster je Formular.
  Result := ColorToRGB(StyleServices(AList).GetSystemColor(AColor));
end;

procedure RowColors(AList: TListView; ACanvas: TCanvas; ASelected, AGray: Boolean);
begin
  // Farben ausdrücklich aus dem Stil der Liste: Nach einer geänderten Schriftfarbe zeichnet die Liste sonst mit den
  // Systemfarben, im dunklen Thema also weiße Zellen. ASelected aus Item.Selected: Mit cdsSelected war in der
  // Prüfliste jede Zeile blau, auch die nicht gewählten.
  if ASelected then
  begin
    ACanvas.Brush.Color := ListColor(AList, clHighlight);
    ACanvas.Font.Color := ListColor(AList, clHighlightText);
  end
  else
  begin
    ACanvas.Brush.Color := ListColor(AList, AList.Color);
    if AGray then
    begin
      ACanvas.Font.Color := ListColor(AList, clGrayText);
    end
    else
    begin
      ACanvas.Font.Color := ListColor(AList, AList.Font.Color);
    end;
  end;
end;

function BuildFilter(AFrame: TAtlasBookmarksFrame; AEvents: TAtlasBookmarksFrame.TEvents): TEdit;
begin
  Result := TEdit.Create(AFrame);
  Result.Parent := AFrame;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.TextHint := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksFilterHint);
  Result.OnChange := AEvents.FilterChange;
  Result.OnKeyDown := AEvents.FilterKeyDown;
  Result.OnKeyPress := AEvents.FilterKeyPress;
end;

function BuildOnlyFile(AFrame: TAtlasBookmarksFrame; AEvents: TAtlasBookmarksFrame.TEvents;
  AFilter: TEdit): TCheckBox;
begin
  Result := TCheckBox.Create(AFrame);
  Result.Parent := AFrame;
  Result.Align := alTop;
  Result.AlignWithMargins := True;
  Result.Top := AFilter.Top + AFilter.Height;
  Result.Caption := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksOnlyFile);
  Result.OnClick := AEvents.OnlyFileClick;
end;

function BuildPlace(AFrame: TAtlasBookmarksFrame): TLabel;
begin
  Result := TLabel.Create(AFrame);
  Result.Parent := AFrame;
  Result.Align := alBottom;
  Result.AlignWithMargins := True;
  Result.ShowAccelChar := False;
  Result.EllipsisPosition := epEndEllipsis;
  Result.Font.Color := clGrayText;
  Result.Caption := '';
end;

procedure BuildMenu(AFrame: TAtlasBookmarksFrame; AEvents: TAtlasBookmarksFrame.TEvents;
  var AParts: TAtlasBookmarksFrame.TParts);
begin
  AParts.Menu := TPopupMenu.Create(AFrame);
  AParts.Menu.OnPopup := AEvents.MenuPopup;
  AParts.OpenItem := AddMenuItem(AParts.Menu, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksMenuGoTo),
    AEvents.OpenClick);
  AParts.OpenItem.Default := True;
  AParts.RenameItem := AddMenuItem(AParts.Menu, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksRename),
    AEvents.RenameClick);
  AParts.DeleteItem := AddMenuItem(AParts.Menu, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksDelete),
    AEvents.DeleteClick);
end;

procedure AddColumns(AList: TListView; APPI: Integer);
begin
  AddColumn(AList, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksColumnName), 160, APPI);
  AddColumn(AList, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksColumnFile), 120, APPI);
  AddColumn(AList, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksColumnMethod), 140, APPI);
  AddColumn(AList, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksColumnLine), 240, APPI);
  // „Nr.“ hinten angelegt, damit der Name die bearbeitbare erste Spalte bleibt; CreateWnd zeigt sie vorn.
  AddColumn(AList, TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksColumnNumber), 36, APPI).Alignment :=
    taCenter;
end;

function BuildList(AFrame: TAtlasBookmarksFrame; AEvents: TAtlasBookmarksFrame.TEvents;
  AMenu: TPopupMenu): TListView;
begin
  Result := TListView.Create(AFrame);
  Result.Parent := AFrame;
  Result.Align := alClient;
  Result.AlignWithMargins := True;
  Result.ViewStyle := vsReport;
  Result.RowSelect := True;
  Result.HideSelection := False;
  Result.ReadOnly := False;
  Result.MultiSelect := False;
  Result.ColumnClick := False;
  Result.DragMode := dmAutomatic;
  Result.PopupMenu := AMenu;
  AddColumns(Result, AFrame.CurrentPPI);
  Result.OnClick := AEvents.ListClick;
  Result.OnDblClick := AEvents.ListDblClick;
  Result.OnKeyDown := AEvents.ListKeyDown;
  Result.OnMouseDown := AEvents.ListMouseDown;
  Result.OnEditing := AEvents.ListEditing;
  Result.OnEdited := AEvents.ListEdited;
  Result.OnDragOver := AEvents.ListDragOver;
  Result.OnDragDrop := AEvents.ListDragDrop;
  Result.OnCustomDrawItem := AEvents.ListCustomDrawItem;
  Result.OnCustomDrawSubItem := AEvents.ListCustomDrawSubItem;
end;

function BuildEmpty(AFrame: TAtlasBookmarksFrame): TLabel;
begin
  // Ohne Lesezeichen: Hinweis statt leerer Liste.
  Result := TLabel.Create(AFrame);
  Result.Parent := AFrame;
  Result.Align := alClient;
  Result.AlignWithMargins := True;
  Result.WordWrap := True;
  Result.ShowAccelChar := False;
  Result.Font.Color := clGrayText;
  Result.Caption := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksEmpty);
  Result.Visible := False;
end;

{ TAtlasBookmarksFrame.TEvents }

constructor TAtlasBookmarksFrame.TEvents.Create(AFrame: TAtlasBookmarksFrame);
begin
  inherited Create(AFrame);
  FFrame := AFrame;
end;

procedure TAtlasBookmarksFrame.TEvents.FilterChange(Sender: TObject);
begin
  FFrame.Refill(FFrame.SelectedId);
end;

procedure TAtlasBookmarksFrame.TEvents.OnlyFileClick(Sender: TObject);
begin
  FFrame.Refill(FFrame.SelectedId);
end;

procedure TAtlasBookmarksFrame.TEvents.FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mList: TListView;
begin
  mList := FFrame.FParts.List;
  case Key of
    VK_DOWN:
      if mList.Visible and (mList.Items.Count > 0) then
      begin
        Key := 0;
        if mList.CanFocus and mList.Showing then
        begin
          mList.SetFocus;
        end;
      end;
    VK_RETURN:
      begin
        Key := 0;
        if mList.Items.Count > 0 then
        begin
          mList.Items[0].Selected := True;
          FFrame.OpenSelected;
        end;
      end;
  end;
end;

procedure TAtlasBookmarksFrame.TEvents.FilterKeyPress(Sender: TObject; var Key: Char);
begin
  // Enter springt; kein Signalton des Eingabefelds.
  if Key = #13 then
  begin
    Key := #0;
  end;
end;

procedure TAtlasBookmarksFrame.TEvents.ListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  FFrame.FMouse.Dropped := False;
  FFrame.FMouse.ClickedItem := FFrame.FParts.List.GetItemAt(X, Y) <> nil;
end;

procedure TAtlasBookmarksFrame.TEvents.ListClick(Sender: TObject);
begin
  // Nach dem Ziehen und auf der freien Fläche kein Sprung.
  if FFrame.FMouse.Dropped or not FFrame.FMouse.ClickedItem then
  begin
    FFrame.FMouse.Dropped := False;
    Exit;
  end;
  FFrame.OpenSelected;
end;

procedure TAtlasBookmarksFrame.TEvents.ListDblClick(Sender: TObject);
begin
  FFrame.OpenSelected;
end;

procedure TAtlasBookmarksFrame.TEvents.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Während der Namensbearbeitung gehören die Tasten dem Eingabefeld.
  if FFrame.FParts.List.IsEditing then
  begin
    Exit;
  end;
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        FFrame.OpenSelected;
      end;
    VK_F2:
      begin
        Key := 0;
        FFrame.BeginRename;
      end;
    VK_DELETE:
      begin
        Key := 0;
        FFrame.DeleteSelected;
      end;
    Ord('1')..Ord('9'):
      // Strg+Umschalt+Zahl vergibt die Nummer (#1104).
      if (ssCtrl in Shift) and (ssShift in Shift) and not (ssAlt in Shift) then
      begin
        FFrame.NumberSelected(Key - Ord('0'));
        Key := 0;
      end;
    VK_UP, VK_DOWN:
      if ssCtrl in Shift then
      begin
        if Key = VK_UP then
        begin
          FFrame.MoveSelected(-1);
        end
        else
        begin
          FFrame.MoveSelected(1);
        end;
        Key := 0;
      end;
  end;
end;

procedure TAtlasBookmarksFrame.TEvents.ListEditing(Sender: TObject; Item: TListItem; var AllowEdit: Boolean);
begin
  // Nur über F2 bzw. „Umbenennen“, nicht durch einen zweiten Klick (der springt).
  AllowEdit := FFrame.FMouse.EditAllowed;
end;

procedure TAtlasBookmarksFrame.TEvents.ListEdited(Sender: TObject; Item: TListItem; var S: string);
var
  mId, mName: string;
begin
  mId := FFrame.IdAt(Item.Index);
  mName := Trim(S);
  // Leer bleibt beim alten Namen.
  if (mId = '') or (mName = '') then
  begin
    S := Item.Caption;
    Exit;
  end;
  S := mName;
  if Assigned(FFrame.FHandlers.OnRename) then
  begin
    FFrame.FHandlers.OnRename(mId, mName);
  end;
end;

procedure TAtlasBookmarksFrame.TEvents.ListDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState;
  var Accept: Boolean);
begin
  Accept := (Source = FFrame.FParts.List) and (FFrame.FParts.List.Selected <> nil);
end;

procedure TAtlasBookmarksFrame.TEvents.ListDragDrop(Sender, Source: TObject; X, Y: Integer);
var
  mList: TListView;
  mTarget: TListItem;
  mBefore: string;
begin
  mList := FFrame.FParts.List;
  if (Source <> mList) or (mList.Selected = nil) then
  begin
    Exit;
  end;
  FFrame.FMouse.Dropped := True;
  mTarget := mList.GetItemAt(X, Y);
  mBefore := '';
  if mTarget <> nil then
  begin
    // Nach unten gezogen: hinter das Ziel, nach oben: davor.
    if mTarget.Index > mList.Selected.Index then
    begin
      mBefore := FFrame.IdAt(mTarget.Index + 1);
    end
    else
    begin
      mBefore := FFrame.IdAt(mTarget.Index);
    end;
  end;
  FFrame.Drop(FFrame.SelectedId, mBefore);
end;

procedure TAtlasBookmarksFrame.TEvents.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mShown: TArray<TAtlasBookmark>;
begin
  DefaultDraw := True;
  mShown := FFrame.FShown;
  // Nicht gefunden: ganze Zeile grau; ohne Namen ist der abgeleitete Name grau (#1104).
  RowColors(FFrame.FParts.List, Sender.Canvas, (Item <> nil) and Item.Selected,
    (Item <> nil) and (Item.Index <= High(mShown)) and (mShown[Item.Index].Lost or mShown[Item.Index].Unnamed));
end;

procedure TAtlasBookmarksFrame.TEvents.ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem;
  SubItem: Integer; State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mShown: TArray<TAtlasBookmark>;
begin
  DefaultDraw := True;
  mShown := FFrame.FShown;
  RowColors(FFrame.FParts.List, Sender.Canvas, (Item <> nil) and Item.Selected,
    (Item <> nil) and (Item.Index <= High(mShown)) and mShown[Item.Index].Lost);
end;

procedure TAtlasBookmarksFrame.TEvents.MenuPopup(Sender: TObject);
var
  mHas: Boolean;
begin
  mHas := FFrame.SelectedId <> '';
  FFrame.FParts.OpenItem.Enabled := mHas;
  FFrame.FParts.RenameItem.Enabled := mHas;
  FFrame.FParts.DeleteItem.Enabled := mHas;
end;

procedure TAtlasBookmarksFrame.TEvents.OpenClick(Sender: TObject);
begin
  FFrame.OpenSelected;
end;

procedure TAtlasBookmarksFrame.TEvents.RenameClick(Sender: TObject);
begin
  FFrame.BeginRename;
end;

procedure TAtlasBookmarksFrame.TEvents.DeleteClick(Sender: TObject);
begin
  FFrame.DeleteSelected;
end;

{ TAtlasBookmarksFrame }

constructor TAtlasBookmarksFrame.Create(AOwner: TComponent);
var
  mEvents: TEvents;
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FBookmarks := TAtlasBookmarkList.Create('');
  mEvents := TEvents.Create(Self);
  FParts.Filter := BuildFilter(Self, mEvents);
  FParts.OnlyFile := BuildOnlyFile(Self, mEvents, FParts.Filter);
  FParts.Place := BuildPlace(Self);
  BuildMenu(Self, mEvents, FParts);
  FParts.List := BuildList(Self, mEvents, FParts.Menu);
  FParts.Empty := BuildEmpty(Self);
  Refill('');
end;

procedure TAtlasBookmarksFrame.CreateWnd;
begin
  inherited CreateWnd;
  ApplyColumnOrder;
end;

procedure TAtlasBookmarksFrame.ApplyColumnOrder;
var
  mOrder: array[0..cNumberColumn] of Integer;
  mIndex: Integer;
begin
  // Ohne Fenster gibt es keine Reihenfolge; Refill versucht es erneut.
  if (FParts.List = nil) or not FParts.List.HandleAllocated then
  begin
    Exit;
  end;
  mOrder[0] := cNumberColumn;
  for mIndex := 1 to cNumberColumn do
  begin
    mOrder[mIndex] := mIndex - 1;
  end;
  ListView_SetColumnOrderArray(FParts.List.Handle, Length(mOrder), @mOrder[0]);
end;

class function TAtlasBookmarksFrame.Cells(const ABookmark: TAtlasBookmark): TArray<string>;
var
  mPreview, mNumber: string;
begin
  mPreview := ABookmark.Preview;
  if ABookmark.Lost then
  begin
    mPreview := TAtlasBookmarksStrings.Text(TAtlasBookmarksTextId.BookmarksLost) + ' · ' + mPreview;
  end;
  mNumber := '';
  if ABookmark.Number > 0 then
  begin
    mNumber := IntToStr(ABookmark.Number);
  end
  else if ABookmark.Kind = TAtlasBookmarkKind.Quick then
  begin
    mNumber := cAtlasQuickBookmarkDot;
  end;
  Result := [ABookmark.DisplayName, ExtractFileName(ABookmark.FileName) + ':' + IntToStr(ABookmark.Line + 1),
    ABookmark.Method, mPreview, mNumber];
end;

procedure TAtlasBookmarksFrame.SetCurrentFile(const AFileName: string);
begin
  if SameText(FCurrentFile, AFileName) then
  begin
    Exit;
  end;
  FCurrentFile := AFileName;
  if FParts.OnlyFile.Checked then
  begin
    Refill(SelectedId);
  end;
end;

procedure TAtlasBookmarksFrame.NumberSelected(ANumber: Integer);
var
  mId: string;
begin
  mId := SelectedId;
  if (mId <> '') and (ANumber >= 1) and (ANumber <= 9) and Assigned(FHandlers.OnNumber) then
  begin
    FHandlers.OnNumber(mId, ANumber);
  end;
end;

procedure TAtlasBookmarksFrame.SetBookmarks(const AList: TAtlasBookmarkList; const APlace, ASelectId: string);
var
  mSelect: string;
begin
  mSelect := ASelectId;
  if mSelect = '' then
  begin
    mSelect := SelectedId;
  end;
  FBookmarks := AList;
  FParts.Place.Caption := APlace;
  Refill(mSelect);
end;

procedure TAtlasBookmarksFrame.Refill(const ASelectId: string);
var
  mIndex: Integer;
  mItem: TListItem;
  mTexts: TArray<string>;
  mPart: Integer;
  mList: TListView;
begin
  mList := FParts.List;
  FShown := nil;
  for mIndex in FBookmarks.Filter(FParts.Filter.Text) do
  begin
    // „nur diese Datei“ (#1104): ohne bekannte Datei alle.
    if not FParts.OnlyFile.Checked or (FCurrentFile = '') or
      TAtlasMarkIds.SameFile(FBookmarks.Bookmarks[mIndex].FileName, FCurrentFile) then
    begin
      FShown := FShown + [FBookmarks.Bookmarks[mIndex]];
    end;
  end;
  mList.Items.BeginUpdate;
  try
    mList.Items.Clear;
    for mIndex := 0 to High(FShown) do
    begin
      mTexts := Cells(FShown[mIndex]);
      mItem := mList.Items.Add;
      mItem.Caption := mTexts[0];
      for mPart := 1 to High(mTexts) do
      begin
        mItem.SubItems.Add(mTexts[mPart]);
      end;
      if SameText(FShown[mIndex].Id, ASelectId) then
      begin
        mItem.Selected := True;
        mItem.Focused := True;
      end;
    end;
  finally
    mList.Items.EndUpdate;
  end;
  if (mList.Selected = nil) and (mList.Items.Count > 0) then
  begin
    mList.Items[0].Selected := True;
    mList.Items[0].Focused := True;
  end;
  if mList.Selected <> nil then
  begin
    mList.Selected.MakeVisible(False);
  end;
  ApplyColumnOrder;
  // Hinweis nur ohne jedes Lesezeichen; ein Filter ohne Treffer zeigt die leere Liste.
  FParts.Empty.Visible := FBookmarks.Count = 0;
  mList.Visible := not FParts.Empty.Visible;
end;

function TAtlasBookmarksFrame.IdAt(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(FShown)) then
  begin
    Result := FShown[AIndex].Id;
  end;
end;

function TAtlasBookmarksFrame.SelectedId: string;
begin
  Result := '';
  if FParts.List.Selected <> nil then
  begin
    Result := IdAt(FParts.List.Selected.Index);
  end;
end;

procedure TAtlasBookmarksFrame.OpenSelected;
var
  mId: string;
begin
  mId := SelectedId;
  if (mId <> '') and Assigned(FHandlers.OnOpen) then
  begin
    FHandlers.OnOpen(mId);
  end;
end;

procedure TAtlasBookmarksFrame.BeginRename;
begin
  if FParts.List.Selected = nil then
  begin
    Exit;
  end;
  FMouse.EditAllowed := True;
  try
    FParts.List.Selected.EditCaption;
  finally
    FMouse.EditAllowed := False;
  end;
end;

procedure TAtlasBookmarksFrame.DeleteSelected;
var
  mId: string;
begin
  mId := SelectedId;
  if (mId <> '') and Assigned(FHandlers.OnDelete) then
  begin
    FHandlers.OnDelete(mId);
  end;
end;

procedure TAtlasBookmarksFrame.MoveSelected(ADelta: Integer);
var
  mIndex: Integer;
  mBefore: string;
begin
  if FParts.List.Selected = nil then
  begin
    Exit;
  end;
  mIndex := FParts.List.Selected.Index;
  if ADelta < 0 then
  begin
    if mIndex <= 0 then
    begin
      Exit;
    end;
    mBefore := IdAt(mIndex - 1);
  end
  else
  begin
    if mIndex >= High(FShown) then
    begin
      Exit;
    end;
    // Hinter den nächsten: vor den übernächsten bzw. ans Ende.
    mBefore := IdAt(mIndex + 2);
  end;
  Drop(IdAt(mIndex), mBefore);
end;

procedure TAtlasBookmarksFrame.Drop(const AId, ABeforeId: string);
begin
  if (AId = '') or SameText(AId, ABeforeId) or not Assigned(FHandlers.OnMove) then
  begin
    Exit;
  end;
  FHandlers.OnMove(AId, ABeforeId);
end;

end.
