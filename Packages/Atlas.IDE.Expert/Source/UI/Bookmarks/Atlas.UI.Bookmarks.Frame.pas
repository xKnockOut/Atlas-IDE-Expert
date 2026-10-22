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
  AtlasQuickBookmarkDot = '•';

type
  TAtlasBookmarksFrame = class(TFrame)
  private
    FFilter: TEdit;
    FOnlyFile: TCheckBox;
    FCurrentFile: string;
    FList: TListView;
    FEmpty: TLabel;
    FPlace: TLabel;
    FMenu: TPopupMenu;
    FOpenItem: TMenuItem;
    FRenameItem: TMenuItem;
    FDeleteItem: TMenuItem;
    FBookmarks: TAtlasBookmarkList;
    /// <summary>Gezeigte Lesezeichen in der Reihenfolge der Listenzeilen.</summary>
    FShown: TArray<TAtlasBookmark>;
    FEditAllowed: Boolean;
    FDropped: Boolean;
    /// <summary>Der letzte Mausklick traf eine Zeile (nicht die freie Fläche).</summary>
    FClickedItem: Boolean;
    FOnOpen: TProc<string>;
    FOnRename: TProc<string, string>;
    FOnDelete: TProc<string>;
    FOnMove: TProc<string, string>;
    FOnNumber: TProc<string, Integer>;
    function AddColumn(const ACaption: string; AWidth: Integer): TListColumn;
    function AddMenuItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
    function IdAt(AIndex: Integer): string;
    procedure Refill(const ASelectId: string);
    procedure FilterChange(Sender: TObject);
    procedure OnlyFileClick(Sender: TObject);
    /// <summary>Spalte „Nr.“ vorn zeigen, sobald die Liste ein Fenster hat.</summary>
    procedure ApplyColumnOrder;
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
  protected
    procedure CreateWnd; override;
  public const
    /// <summary>Index der Spalte „Nr.“ (hinten angelegt, vorn angezeigt).</summary>
    NumberColumn = 4;
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
    property Filter: TEdit read FFilter;
    property OnlyFileCheck: TCheckBox read FOnlyFile;
    property List: TListView read FList;
    property EmptyLabel: TLabel read FEmpty;
    property PlaceLabel: TLabel read FPlace;
    property Menu: TPopupMenu read FMenu;
    property Shown: TArray<TAtlasBookmark> read FShown;
    property OnOpen: TProc<string> read FOnOpen write FOnOpen;
    /// <summary>Kennung und neuer Name (ohne Leerraum am Rand, nie leer).</summary>
    property OnRename: TProc<string, string> read FOnRename write FOnRename;
    property OnDelete: TProc<string> read FOnDelete write FOnDelete;
    /// <summary>Kennung und Kennung, vor die es soll ('' = ans Ende).</summary>
    property OnMove: TProc<string, string> read FOnMove write FOnMove;
    /// <summary>Kennung und Nummer 1–9 (#1104).</summary>
    property OnNumber: TProc<string, Integer> read FOnNumber write FOnNumber;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.CommCtrl,
  Atlas.UI.Strings;

{$R *.dfm}

{ TAtlasBookmarksFrame }

constructor TAtlasBookmarksFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FBookmarks := TAtlasBookmarkList.Create('');

  FFilter := TEdit.Create(Self);
  FFilter.Parent := Self;
  FFilter.Align := alTop;
  FFilter.AlignWithMargins := True;
  FFilter.TextHint := TAtlasStrings.Text(TAtlasTextId.BookmarksFilterHint);
  FFilter.OnChange := FilterChange;
  FFilter.OnKeyDown := FilterKeyDown;
  FFilter.OnKeyPress := FilterKeyPress;

  FOnlyFile := TCheckBox.Create(Self);
  FOnlyFile.Parent := Self;
  FOnlyFile.Align := alTop;
  FOnlyFile.AlignWithMargins := True;
  FOnlyFile.Top := FFilter.Top + FFilter.Height;
  FOnlyFile.Caption := TAtlasStrings.Text(TAtlasTextId.BookmarksOnlyFile);
  FOnlyFile.OnClick := OnlyFileClick;

  FPlace := TLabel.Create(Self);
  FPlace.Parent := Self;
  FPlace.Align := alBottom;
  FPlace.AlignWithMargins := True;
  FPlace.ShowAccelChar := False;
  FPlace.EllipsisPosition := epEndEllipsis;
  FPlace.Font.Color := clGrayText;
  FPlace.Caption := '';

  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FOpenItem := AddMenuItem(TAtlasStrings.Text(TAtlasTextId.BookmarksMenuGoTo), OpenClick);
  FOpenItem.Default := True;
  FRenameItem := AddMenuItem(TAtlasStrings.Text(TAtlasTextId.BookmarksRename), RenameClick);
  FDeleteItem := AddMenuItem(TAtlasStrings.Text(TAtlasTextId.BookmarksDelete), DeleteClick);

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := False;
  FList.MultiSelect := False;
  FList.ColumnClick := False;
  FList.DragMode := dmAutomatic;
  FList.PopupMenu := FMenu;
  AddColumn(TAtlasStrings.Text(TAtlasTextId.BookmarksColumnName), 160);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.BookmarksColumnFile), 120);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.BookmarksColumnMethod), 140);
  AddColumn(TAtlasStrings.Text(TAtlasTextId.BookmarksColumnLine), 240);
  // „Nr.“ hinten angelegt, damit der Name die bearbeitbare erste Spalte bleibt; CreateWnd zeigt sie vorn.
  AddColumn(TAtlasStrings.Text(TAtlasTextId.BookmarksColumnNumber), 36).Alignment := taCenter;
  FList.OnClick := ListClick;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  FList.OnMouseDown := ListMouseDown;
  FList.OnEditing := ListEditing;
  FList.OnEdited := ListEdited;
  FList.OnDragOver := ListDragOver;
  FList.OnDragDrop := ListDragDrop;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  FList.OnCustomDrawSubItem := ListCustomDrawSubItem;

  // Ohne Lesezeichen: Hinweis statt leerer Liste.
  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := Self;
  FEmpty.Align := alClient;
  FEmpty.AlignWithMargins := True;
  FEmpty.WordWrap := True;
  FEmpty.ShowAccelChar := False;
  FEmpty.Font.Color := clGrayText;
  FEmpty.Caption := TAtlasStrings.Text(TAtlasTextId.BookmarksEmpty);
  FEmpty.Visible := False;
  Refill('');
end;

procedure TAtlasBookmarksFrame.CreateWnd;
begin
  inherited CreateWnd;
  ApplyColumnOrder;
end;

procedure TAtlasBookmarksFrame.ApplyColumnOrder;
var
  Order: array[0..NumberColumn] of Integer;
  Index: Integer;
begin
  // Ohne Fenster gibt es keine Reihenfolge; Refill versucht es erneut.
  if (FList = nil) or not FList.HandleAllocated then
    Exit;
  Order[0] := NumberColumn;
  for Index := 1 to NumberColumn do
    Order[Index] := Index - 1;
  ListView_SetColumnOrderArray(FList.Handle, Length(Order), @Order[0]);
end;

function TAtlasBookmarksFrame.AddColumn(const ACaption: string; AWidth: Integer): TListColumn;
begin
  Result := FList.Columns.Add;
  Result.Caption := ACaption;
  Result.Width := MulDiv(AWidth, CurrentPPI, 96);
end;

function TAtlasBookmarksFrame.AddMenuItem(const ACaption: string; AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  FMenu.Items.Add(Result);
end;

class function TAtlasBookmarksFrame.Cells(const ABookmark: TAtlasBookmark): TArray<string>;
var
  Preview, Number: string;
begin
  Preview := ABookmark.Preview;
  if ABookmark.Lost then
    Preview := TAtlasStrings.Text(TAtlasTextId.BookmarksLost) + ' · ' + Preview;
  Number := '';
  if ABookmark.Number > 0 then
    Number := IntToStr(ABookmark.Number)
  else if ABookmark.Kind = TAtlasBookmarkKind.Quick then
    Number := AtlasQuickBookmarkDot;
  Result := [ABookmark.DisplayName, ExtractFileName(ABookmark.FileName) + ':' + IntToStr(ABookmark.Line + 1),
    ABookmark.Method, Preview, Number];
end;

procedure TAtlasBookmarksFrame.SetCurrentFile(const AFileName: string);
begin
  if SameText(FCurrentFile, AFileName) then
    Exit;
  FCurrentFile := AFileName;
  if FOnlyFile.Checked then
    Refill(SelectedId);
end;

procedure TAtlasBookmarksFrame.NumberSelected(ANumber: Integer);
var
  Id: string;
begin
  Id := SelectedId;
  if (Id <> '') and (ANumber >= 1) and (ANumber <= 9) and Assigned(FOnNumber) then
    FOnNumber(Id, ANumber);
end;

procedure TAtlasBookmarksFrame.OnlyFileClick(Sender: TObject);
begin
  Refill(SelectedId);
end;

procedure TAtlasBookmarksFrame.SetBookmarks(const AList: TAtlasBookmarkList; const APlace, ASelectId: string);
var
  Select: string;
begin
  Select := ASelectId;
  if Select = '' then
    Select := SelectedId;
  FBookmarks := AList;
  FPlace.Caption := APlace;
  Refill(Select);
end;

procedure TAtlasBookmarksFrame.Refill(const ASelectId: string);
var
  Index: Integer;
  Item: TListItem;
  Texts: TArray<string>;
  Part: Integer;
begin
  FShown := nil;
  for Index in FBookmarks.Filter(FFilter.Text) do
    // „nur diese Datei“ (#1104): ohne bekannte Datei alle.
    if not FOnlyFile.Checked or (FCurrentFile = '') or
      TAtlasBookmarks.SameFile(FBookmarks.Bookmarks[Index].FileName, FCurrentFile) then
      FShown := FShown + [FBookmarks.Bookmarks[Index]];
  FList.Items.BeginUpdate;
  try
    FList.Items.Clear;
    for Index := 0 to High(FShown) do
    begin
      Texts := Cells(FShown[Index]);
      Item := FList.Items.Add;
      Item.Caption := Texts[0];
      for Part := 1 to High(Texts) do
        Item.SubItems.Add(Texts[Part]);
      if SameText(FShown[Index].Id, ASelectId) then
      begin
        Item.Selected := True;
        Item.Focused := True;
      end;
    end;
  finally
    FList.Items.EndUpdate;
  end;
  if (FList.Selected = nil) and (FList.Items.Count > 0) then
  begin
    FList.Items[0].Selected := True;
    FList.Items[0].Focused := True;
  end;
  if FList.Selected <> nil then
    FList.Selected.MakeVisible(False);
  ApplyColumnOrder;
  // Hinweis nur ohne jedes Lesezeichen; ein Filter ohne Treffer zeigt die leere Liste.
  FEmpty.Visible := FBookmarks.Count = 0;
  FList.Visible := not FEmpty.Visible;
end;

function TAtlasBookmarksFrame.IdAt(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(FShown)) then
    Result := FShown[AIndex].Id;
end;

function TAtlasBookmarksFrame.SelectedId: string;
begin
  Result := '';
  if FList.Selected <> nil then
    Result := IdAt(FList.Selected.Index);
end;

procedure TAtlasBookmarksFrame.OpenSelected;
var
  Id: string;
begin
  Id := SelectedId;
  if (Id <> '') and Assigned(FOnOpen) then
    FOnOpen(Id);
end;

procedure TAtlasBookmarksFrame.BeginRename;
begin
  if FList.Selected = nil then
    Exit;
  FEditAllowed := True;
  try
    FList.Selected.EditCaption;
  finally
    FEditAllowed := False;
  end;
end;

procedure TAtlasBookmarksFrame.DeleteSelected;
var
  Id: string;
begin
  Id := SelectedId;
  if (Id <> '') and Assigned(FOnDelete) then
    FOnDelete(Id);
end;

procedure TAtlasBookmarksFrame.MoveSelected(ADelta: Integer);
var
  Index: Integer;
  Before: string;
begin
  if FList.Selected = nil then
    Exit;
  Index := FList.Selected.Index;
  if ADelta < 0 then
  begin
    if Index <= 0 then
      Exit;
    Before := IdAt(Index - 1);
  end
  else
  begin
    if Index >= High(FShown) then
      Exit;
    // Hinter den nächsten: vor den übernächsten bzw. ans Ende.
    Before := IdAt(Index + 2);
  end;
  Drop(IdAt(Index), Before);
end;

procedure TAtlasBookmarksFrame.Drop(const AId, ABeforeId: string);
begin
  if (AId = '') or SameText(AId, ABeforeId) or not Assigned(FOnMove) then
    Exit;
  FOnMove(AId, ABeforeId);
end;

procedure TAtlasBookmarksFrame.FilterChange(Sender: TObject);
begin
  Refill(SelectedId);
end;

procedure TAtlasBookmarksFrame.FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_DOWN:
      if FList.Visible and (FList.Items.Count > 0) then
      begin
        Key := 0;
        if FList.CanFocus then
          FList.SetFocus;
      end;
    VK_RETURN:
      begin
        Key := 0;
        if FList.Items.Count > 0 then
        begin
          FList.Items[0].Selected := True;
          OpenSelected;
        end;
      end;
  end;
end;

procedure TAtlasBookmarksFrame.FilterKeyPress(Sender: TObject; var Key: Char);
begin
  // Enter springt; kein Signalton des Eingabefelds.
  if Key = #13 then
    Key := #0;
end;

procedure TAtlasBookmarksFrame.ListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  FDropped := False;
  FClickedItem := FList.GetItemAt(X, Y) <> nil;
end;

procedure TAtlasBookmarksFrame.ListClick(Sender: TObject);
begin
  // Nach dem Ziehen und auf der freien Fläche kein Sprung.
  if FDropped or not FClickedItem then
  begin
    FDropped := False;
    Exit;
  end;
  OpenSelected;
end;

procedure TAtlasBookmarksFrame.ListDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TAtlasBookmarksFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  // Während der Namensbearbeitung gehören die Tasten dem Eingabefeld.
  if FList.IsEditing then
    Exit;
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        OpenSelected;
      end;
    VK_F2:
      begin
        Key := 0;
        BeginRename;
      end;
    VK_DELETE:
      begin
        Key := 0;
        DeleteSelected;
      end;
    Ord('1')..Ord('9'):
      // Strg+Umschalt+Zahl vergibt die Nummer (#1104).
      if (ssCtrl in Shift) and (ssShift in Shift) and not (ssAlt in Shift) then
      begin
        NumberSelected(Key - Ord('0'));
        Key := 0;
      end;
    VK_UP, VK_DOWN:
      if ssCtrl in Shift then
      begin
        if Key = VK_UP then
          MoveSelected(-1)
        else
          MoveSelected(1);
        Key := 0;
      end;
  end;
end;

procedure TAtlasBookmarksFrame.ListEditing(Sender: TObject; Item: TListItem; var AllowEdit: Boolean);
begin
  // Nur über F2 bzw. „Umbenennen“, nicht durch einen zweiten Klick (der springt).
  AllowEdit := FEditAllowed;
end;

procedure TAtlasBookmarksFrame.ListEdited(Sender: TObject; Item: TListItem; var S: string);
var
  Id, Name: string;
begin
  Id := IdAt(Item.Index);
  Name := Trim(S);
  // Leer bleibt beim alten Namen.
  if (Id = '') or (Name = '') then
  begin
    S := Item.Caption;
    Exit;
  end;
  S := Name;
  if Assigned(FOnRename) then
    FOnRename(Id, Name);
end;

procedure TAtlasBookmarksFrame.ListDragOver(Sender, Source: TObject; X, Y: Integer; State: TDragState;
  var Accept: Boolean);
begin
  Accept := (Source = FList) and (FList.Selected <> nil);
end;

procedure TAtlasBookmarksFrame.ListDragDrop(Sender, Source: TObject; X, Y: Integer);
var
  Target: TListItem;
  Before: string;
begin
  if (Source <> FList) or (FList.Selected = nil) then
    Exit;
  FDropped := True;
  Target := FList.GetItemAt(X, Y);
  Before := '';
  if Target <> nil then
  begin
    // Nach unten gezogen: hinter das Ziel, nach oben: davor.
    if Target.Index > FList.Selected.Index then
      Before := IdAt(Target.Index + 1)
    else
      Before := IdAt(Target.Index);
  end;
  Drop(SelectedId, Before);
end;

procedure TAtlasBookmarksFrame.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  // Nicht gefunden: ganze Zeile grau; ohne Namen ist der abgeleitete Name grau (#1104).
  if (Item <> nil) and (Item.Index <= High(FShown)) and (FShown[Item.Index].Lost or FShown[Item.Index].Unnamed) then
    Sender.Canvas.Font.Color := clGrayText;
end;

procedure TAtlasBookmarksFrame.ListCustomDrawSubItem(Sender: TCustomListView; Item: TListItem; SubItem: Integer;
  State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  DefaultDraw := True;
  if (Item = nil) or (Item.Index > High(FShown)) then
    Exit;
  if FShown[Item.Index].Lost then
    Sender.Canvas.Font.Color := clGrayText
  else
    Sender.Canvas.Font.Color := FList.Font.Color;
end;

procedure TAtlasBookmarksFrame.MenuPopup(Sender: TObject);
var
  Has: Boolean;
begin
  Has := SelectedId <> '';
  FOpenItem.Enabled := Has;
  FRenameItem.Enabled := Has;
  FDeleteItem.Enabled := Has;
end;

procedure TAtlasBookmarksFrame.OpenClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TAtlasBookmarksFrame.RenameClick(Sender: TObject);
begin
  BeginRename;
end;

procedure TAtlasBookmarksFrame.DeleteClick(Sender: TObject);
begin
  DeleteSelected;
end;

end.
