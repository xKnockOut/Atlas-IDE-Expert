unit Atlas.UI.Outline.Frame;

// Inhalt des Seitenfensters „Gliederung“ (#537), reine VCL: oben das
// Suchfeld (unscharf wie die Vervollständigung) und die Knöpfe
// „Sichtbarkeit“, „Art“ (Menüs zum Ankreuzen) und Sortierung
// (Quelltextreihenfolge oder alphabetisch), darunter die Gliederung als
// selbst gezeichnete Liste mit Einrückung und Pfeil zum Auf- und Zuklappen.
// Je Zeile: Zeichen der Sichtbarkeit (− # + ◆), Name, gedämpft die Art des
// Typs bzw. „class“, „override“, „virtual“, „abstract“, und in Warnfarbe
// „nicht implementiert“. Eltern, die nur als Rahmen eines Treffers stehen,
// sind gedämpft.
// Bedienung: Klick oder Enter springt zur Deklaration, Doppelklick oder
// Strg+Enter zur Implementierung (OnOpen); Klick auf den Pfeil, ← und →
// klappen. Im Suchfeld führt ↓ in die Liste, Enter springt zum ersten
// Treffer, Esc leert die Suche. Kontextmenü: Zur Deklaration, Zur
// Implementierung, Cursor folgen. HighlightAt wählt den Eintrag am Cursor,
// ohne zu springen. Mit Suchtext ist alles aufgeklappt.
// Die IDE-Schicht bettet den Frame in ein andockbares Fenster ein und ruft
// SetNodes bzw. SetMessage. Die DFM ist leer, weil TCustomFrame.Create für
// abgeleitete Frames eine Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Core.Outline.Model;

type
  /// <summary>Steuerelemente des Seitenfensters „Gliederung“; Grundlage von TAtlasOutlineFrame.</summary>
  TAtlasOutlineFrameParts = class(TFrame)
  private
    FTop: TPanel;
    FSearch: TEdit;
    FVisibilityButton: TButton;
    FKindButton: TButton;
    FSortButton: TButton;
    FList: TListBox;
    FMessage: TLabel;
    FVisibilityMenu: TPopupMenu;
    FKindMenu: TPopupMenu;
    FListMenu: TPopupMenu;
    FFollowItem: TMenuItem;
    function NewButton: TButton;
    function AddMenuItem(AMenu: TPopupMenu; const ACaption: string; ATag: Integer; AClick: TNotifyEvent): TMenuItem;
    function Scale(AValue: Integer): Integer;
    /// <summary>Die Liste hat ein Fenster oder kann eins bekommen (Formular darüber).</summary>
    function ListCanHaveHandle: Boolean;
  public
    property Search: TEdit read FSearch;
    property List: TListBox read FList;
    property MessageLabel: TLabel read FMessage;
    property VisibilityMenu: TPopupMenu read FVisibilityMenu;
    property KindMenu: TPopupMenu read FKindMenu;
    property ListMenu: TPopupMenu read FListMenu;
  end;

  /// <summary>Gliederung, Filter, Zugeklapptes und die gezeigten Zeilen.</summary>
  TAtlasOutlineFrameRows = class(TAtlasOutlineFrameParts)
  private
    FNodes: TAtlasOutlineNodes;
    /// <summary>Alle Zeilen nach Filter und Sortierung, ohne Rücksicht auf Zugeklapptes.</summary>
    FAllRows: TArray<TAtlasOutlineRow>;
    /// <summary>Gezeigte Zeilen (Zugeklapptes ausgelassen).</summary>
    FRows: TArray<TAtlasOutlineRow>;
    FFilter: TAtlasOutlineFilter;
    FAlphabetical: Boolean;
    FShowConditions: Boolean;
    /// <summary>Pfade zugeklappter Knoten ("interface/TForm1"); bleiben über SetNodes erhalten.</summary>
    FCollapsed: TStringList;
    FMessageText: string;
    function PathOf(ANode: Integer): string;
    function SelectedPath: string;
    function RowHasChildren(AIndex: Integer): Boolean;
    /// <summary>Ist die gezeigte Zeile AIndex zugeklappt?</summary>
    function IsCollapsed(AIndex: Integer): Boolean;
    function ExpanderRect(AIndex: Integer; const ARect: TRect): TRect;
    procedure Refill; overload;
    procedure Refill(const ASelectedPath: string); overload;
    procedure UpdateButtons;
    procedure UpdateMessage;
    procedure ListDrawItem(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
    procedure SetShowConditions(AValue: Boolean);
    procedure SetAlphabetical(AValue: Boolean);
  protected
    procedure CreateWnd; override;
  public
    destructor Destroy; override;
    /// <summary>Neue Gliederung; Filter, Zugeklapptes und Auswahl (nach Pfad) bleiben.</summary>
    procedure SetNodes(const ANodes: TAtlasOutlineNodes);
    /// <summary>Statt der Gliederung ein Hinweis (kein Editor, kein Server); leert die Knoten.</summary>
    procedure SetMessage(const AText: string);
    /// <summary>Eintrag an der Stelle (0-basiert) wählen, ohne zu springen; klappt Eltern auf. False, wenn
    /// dort kein gezeigter Eintrag steht.</summary>
    function HighlightAt(ALine, ACharacter: Integer): Boolean;
    /// <summary>Knoten der gewählten Zeile; -1 ohne Auswahl.</summary>
    function SelectedNode: Integer;
    /// <summary>Zeile wählen (Index in Rows).</summary>
    procedure SelectRow(AIndex: Integer);
    /// <summary>Zeile auf- oder zuklappen.</summary>
    procedure ToggleRow(AIndex: Integer);
    /// <summary>Sichtbarkeitsfilter setzen (leer = alle).</summary>
    procedure SetVisibilities(const AVisibilities: TAtlasOutlineVisibilities);
    /// <summary>Artfilter setzen (leer = alle).</summary>
    procedure SetCategories(const ACategories: TAtlasOutlineCategories);
    /// <summary>Text der Zeile, wie gezeichnet: Zeichen, Name und Marken (für Tests und Bildschirmleser).</summary>
    function RowText(AIndex: Integer): string;
    property Nodes: TAtlasOutlineNodes read FNodes;
    property Rows: TArray<TAtlasOutlineRow> read FRows;
    property Filter: TAtlasOutlineFilter read FFilter;
    /// <summary>Bedingung des aktiven {$IFDEF}-Zweigs hinter dem Eintrag zeigen (#845).</summary>
    property ShowConditions: Boolean read FShowConditions write SetShowConditions;
    property Alphabetical: Boolean read FAlphabetical write SetAlphabetical;
  end;

  TAtlasOutlineFrame = class(TAtlasOutlineFrameRows)
  private
    FFollowCursor: Boolean;
    /// <summary>Der letzte Mausklick traf den Pfeil, nicht den Namen.</summary>
    FExpanderClick: Boolean;
    /// <summary>Linksklick auf einen Namen: der folgende OnClick springt (Pfeiltasten melden auch OnClick).</summary>
    FMouseOpen: Boolean;
    FOnOpen: TProc<Integer, Boolean>;
    FOnSortChanged: TProc<Boolean>;
    FOnFollowChanged: TProc<Boolean>;
    procedure BuildBar;
    procedure BuildMenus;
    procedure BuildList;
    procedure SearchChange(Sender: TObject);
    procedure SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure SearchKeyPress(Sender: TObject; var Key: Char);
    procedure VisibilityClick(Sender: TObject);
    procedure KindClick(Sender: TObject);
    procedure SortClick(Sender: TObject);
    procedure VisibilityItemClick(Sender: TObject);
    procedure KindItemClick(Sender: TObject);
    procedure ListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ListClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    /// <summary>← in der Liste: Zeile AIndex zuklappen oder zum Elternknoten.</summary>
    procedure KeyLeft(AIndex: Integer);
    procedure ListMenuPopup(Sender: TObject);
    procedure DeclarationClick(Sender: TObject);
    procedure ImplementationClick(Sender: TObject);
    procedure FollowClick(Sender: TObject);
    procedure SetFollowCursor(AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>OnOpen für die gewählte Zeile: Deklaration oder Implementierung.</summary>
    procedure OpenSelected(AImplementation: Boolean);
    property FollowCursor: Boolean read FFollowCursor write SetFollowCursor;
    /// <summary>Knoten und ob zur Implementierung.</summary>
    property OnOpen: TProc<Integer, Boolean> read FOnOpen write FOnOpen;
    /// <summary>Sortierknopf gedrückt: neuer Wert von Alphabetical.</summary>
    property OnSortChanged: TProc<Boolean> read FOnSortChanged write FOnSortChanged;
    /// <summary>„Cursor folgen“ im Kontextmenü umgeschaltet.</summary>
    property OnFollowChanged: TProc<Boolean> read FOnFollowChanged write FOnFollowChanged;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Strings;

{$R *.dfm}

const
  cIndentPx = 14;
  cExpanderPx = 14;
  cRowPx = 20;
  /// <summary>Tag der Menüeinträge „Alle zeigen“.</summary>
  cTagAll = -1;
  cKindTexts: array[0..7] of TAtlasTextId = (TAtlasTextId.OutlineKindTypes, TAtlasTextId.OutlineKindFields,
    TAtlasTextId.OutlineKindMethods, TAtlasTextId.OutlineKindProperties, TAtlasTextId.OutlineKindConstants,
    TAtlasTextId.OutlineKindVariables, TAtlasTextId.OutlineKindRoutines, TAtlasTextId.OutlineKindEnumMembers);
  cKindCategories: array[0..7] of TAtlasOutlineCategory = (TAtlasOutlineCategory.TypeDecl,
    TAtlasOutlineCategory.Field, TAtlasOutlineCategory.Method, TAtlasOutlineCategory.PropertyDecl,
    TAtlasOutlineCategory.Constant, TAtlasOutlineCategory.Variable, TAtlasOutlineCategory.Routine,
    TAtlasOutlineCategory.EnumMember);
  cVisibilityTexts: array[0..3] of TAtlasTextId = (TAtlasTextId.OutlineVisPrivate, TAtlasTextId.OutlineVisProtected,
    TAtlasTextId.OutlineVisPublic, TAtlasTextId.OutlineVisPublished);

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function StyleColors: TAtlasColors;
begin
  Result := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices.GetSystemColor(clWindow))));
end;

{ TAtlasOutlineFrame }

constructor TAtlasOutlineFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FFilter := TAtlasOutlineFilter.All;
  FFollowCursor := True;
  FShowConditions := True;
  FCollapsed := TStringList.Create;
  FCollapsed.Sorted := True;
  FCollapsed.Duplicates := dupIgnore;
  FCollapsed.CaseSensitive := False;
  BuildBar;
  BuildMenus;
  BuildList;
  FMessageText := TAtlasStrings.Text(TAtlasTextId.OutlineEmpty);
  UpdateButtons;
  UpdateMessage;
end;

/// <summary>Obere Leiste: Knöpfe Sortierung, Art, Sichtbarkeit (von rechts) und das Suchfeld.</summary>
procedure TAtlasOutlineFrame.BuildBar;
begin
  FTop := TPanel.Create(Self);
  FTop.Parent := Self;
  FTop.Align := alTop;
  FTop.BevelOuter := bvNone;
  FTop.ShowCaption := False;
  FTop.ParentBackground := True;
  FTop.Height := Scale(28);

  FSortButton := NewButton;
  FSortButton.OnClick := SortClick;
  FKindButton := NewButton;
  FKindButton.Caption := TAtlasStrings.Text(TAtlasTextId.OutlineKindButton) + ' ▾';
  FKindButton.OnClick := KindClick;
  FVisibilityButton := NewButton;
  FVisibilityButton.Caption := TAtlasStrings.Text(TAtlasTextId.OutlineVisibilityButton) + ' ▾';
  FVisibilityButton.OnClick := VisibilityClick;

  FSearch := TEdit.Create(Self);
  FSearch.Parent := FTop;
  FSearch.Align := alClient;
  FSearch.AlignWithMargins := True;
  FSearch.TextHint := TAtlasStrings.Text(TAtlasTextId.OutlineSearchHint);
  FSearch.OnChange := SearchChange;
  FSearch.OnKeyDown := SearchKeyDown;
  FSearch.OnKeyPress := SearchKeyPress;
end;

/// <summary>Menüs der Knöpfe Sichtbarkeit und Art und das Kontextmenü der Liste.</summary>
procedure TAtlasOutlineFrame.BuildMenus;
var
  mIndex: Integer;
begin
  FVisibilityMenu := TPopupMenu.Create(Self);
  AddMenuItem(FVisibilityMenu, TAtlasStrings.Text(TAtlasTextId.OutlineShowAll), cTagAll, VisibilityItemClick);
  FVisibilityMenu.Items.Add(NewLine);
  for mIndex := 0 to High(cVisibilityTexts) do
  begin
    AddMenuItem(FVisibilityMenu, TAtlasStrings.Text(cVisibilityTexts[mIndex]), mIndex, VisibilityItemClick).Checked :=
      True;
  end;

  FKindMenu := TPopupMenu.Create(Self);
  AddMenuItem(FKindMenu, TAtlasStrings.Text(TAtlasTextId.OutlineShowAll), cTagAll, KindItemClick);
  FKindMenu.Items.Add(NewLine);
  for mIndex := 0 to High(cKindTexts) do
  begin
    AddMenuItem(FKindMenu, TAtlasStrings.Text(cKindTexts[mIndex]), mIndex, KindItemClick).Checked := True;
  end;

  FListMenu := TPopupMenu.Create(Self);
  FListMenu.OnPopup := ListMenuPopup;
  AddMenuItem(FListMenu, TAtlasStrings.Text(TAtlasTextId.OutlineGoToDeclaration), 0, DeclarationClick).Default :=
    True;
  AddMenuItem(FListMenu, TAtlasStrings.Text(TAtlasTextId.OutlineGoToImplementation), 1, ImplementationClick);
  FListMenu.Items.Add(NewLine);
  FFollowItem := AddMenuItem(FListMenu, TAtlasStrings.Text(TAtlasTextId.OutlineFollowCursor), 2, FollowClick);
  FFollowItem.Checked := FFollowCursor;
end;

/// <summary>Liste der Gliederung und der Hinweis an ihrer Stelle.</summary>
procedure TAtlasOutlineFrame.BuildList;
begin
  FList := TListBox.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  // Style := lbVirtualOwnerDraw erst in CreateWnd: SetStyle leert die Einträge per
  // LB_RESETCONTENT und braucht dafür das Fenster, das ohne Parent fehlt.
  FList.ItemHeight := Scale(cRowPx);
  FList.PopupMenu := FListMenu;
  FList.OnDrawItem := ListDrawItem;
  FList.OnMouseDown := ListMouseDown;
  FList.OnClick := ListClick;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;

  // Ohne Gliederung oder ohne Treffer: Hinweis statt leerer Liste.
  FMessage := TLabel.Create(Self);
  FMessage.Parent := Self;
  FMessage.Align := alClient;
  FMessage.AlignWithMargins := True;
  FMessage.WordWrap := True;
  FMessage.ShowAccelChar := False;
  FMessage.Font.Color := clGrayText;
  FMessage.Visible := False;
end;

procedure TAtlasOutlineFrameRows.CreateWnd;
begin
  inherited CreateWnd;
  FList.Style := lbVirtualOwnerDraw;
  FList.Count := Length(FRows);
end;

function TAtlasOutlineFrameParts.ListCanHaveHandle: Boolean;
begin
  Result := FList.HandleAllocated or (GetParentForm(FList) <> nil);
end;

destructor TAtlasOutlineFrameRows.Destroy;
begin
  FCollapsed.Free;
  inherited Destroy;
end;

function TAtlasOutlineFrameParts.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, 96);
end;

function TAtlasOutlineFrameParts.NewButton: TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FTop;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := Scale(92);
end;

function TAtlasOutlineFrameParts.AddMenuItem(AMenu: TPopupMenu; const ACaption: string; ATag: Integer;
  AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := AClick;
  AMenu.Items.Add(Result);
end;

function TAtlasOutlineFrameRows.PathOf(ANode: Integer): string;
begin
  Result := '';
  while ANode >= 0 do
  begin
    Result := FNodes[ANode].Name + '/' + Result;
    ANode := FNodes[ANode].Parent;
  end;
end;

function TAtlasOutlineFrameRows.SelectedPath: string;
begin
  Result := '';
  if SelectedNode >= 0 then
  begin
    Result := PathOf(SelectedNode);
  end;
end;

procedure TAtlasOutlineFrameRows.SetNodes(const ANodes: TAtlasOutlineNodes);
var
  mSelected: string;
begin
  // Pfad vor dem Wechsel: Die Indizes der alten Zeilen gelten für die neuen Knoten nicht.
  mSelected := SelectedPath;
  FRows := nil;
  FNodes := ANodes;
  FMessageText := TAtlasStrings.Text(TAtlasTextId.OutlineNoMatch);
  Refill(mSelected);
end;

procedure TAtlasOutlineFrameRows.SetMessage(const AText: string);
begin
  FRows := nil;
  FNodes := nil;
  FMessageText := AText;
  Refill('');
end;

procedure TAtlasOutlineFrameRows.Refill;
begin
  Refill(SelectedPath);
end;

procedure TAtlasOutlineFrameRows.Refill(const ASelectedPath: string);
var
  mIndex, mSkip: Integer;
  mRow: TAtlasOutlineRow;
  mSort: TAtlasOutlineSort;
begin
  mSort := TAtlasOutlineSort.Source;
  if FAlphabetical then
  begin
    mSort := TAtlasOutlineSort.Alphabetical;
  end;
  FAllRows := TAtlasOutline.Rows(FNodes, FFilter, mSort);
  FRows := nil;
  // Zugeklapptes auslassen; mit Suchtext ist alles offen.
  mSkip := -1;
  for mIndex := 0 to High(FAllRows) do
  begin
    mRow := FAllRows[mIndex];
    if (mSkip >= 0) and (mRow.Depth > mSkip) then
    begin
      Continue;
    end;
    mSkip := -1;
    FRows := FRows + [mRow];
    if (FFilter.Text = '') and (FCollapsed.IndexOf(PathOf(mRow.Node)) >= 0) then
    begin
      mSkip := mRow.Depth;
    end;
  end;
  // Count braucht das Fenster; ohne Formular setzt CreateWnd die Zahl nach.
  if ListCanHaveHandle then
  begin
    FList.HandleNeeded;
    FList.Count := Length(FRows);
  end;
  if ASelectedPath <> '' then
  begin
    for mIndex := 0 to High(FRows) do
    begin
      if SameText(PathOf(FRows[mIndex].Node), ASelectedPath) then
      begin
        SelectRow(mIndex);
        Break;
      end;
    end;
  end;
  FList.Invalidate;
  UpdateMessage;
end;

procedure TAtlasOutlineFrameRows.UpdateMessage;
begin
  FMessage.Caption := FMessageText;
  FMessage.Visible := Length(FRows) = 0;
  FList.Visible := not FMessage.Visible;
end;

procedure TAtlasOutlineFrameRows.UpdateButtons;
var
  mItem: TMenuItem;
begin
  if FAlphabetical then
  begin
    FSortButton.Caption := TAtlasStrings.Text(TAtlasTextId.OutlineSortAlphabetical);
  end
  else
  begin
    FSortButton.Caption := TAtlasStrings.Text(TAtlasTextId.OutlineSortSource);
  end;
  for mItem in FVisibilityMenu.Items do
  begin
    if mItem.Tag >= 0 then
    begin
      mItem.Checked := TAtlasOutline.FilterVisibilities[mItem.Tag] in FFilter.Visibilities;
    end;
  end;
  for mItem in FKindMenu.Items do
  begin
    if mItem.Tag >= 0 then
    begin
      mItem.Checked := cKindCategories[mItem.Tag] in FFilter.Categories;
    end;
  end;
  // Ein aktiver Filter ist am Knopf zu sehen.
  FVisibilityButton.Font.Style := [];
  if not FFilter.AllVisibilities then
  begin
    FVisibilityButton.Font.Style := [fsBold];
  end;
  FKindButton.Font.Style := [];
  if not FFilter.AllCategories then
  begin
    FKindButton.Font.Style := [fsBold];
  end;
end;

procedure TAtlasOutlineFrameRows.SetVisibilities(const AVisibilities: TAtlasOutlineVisibilities);
begin
  // strict private zählt zu private, strict protected zu protected (TAtlasOutline.Rows).
  if AVisibilities = [] then
  begin
    FFilter.Visibilities := TAtlasOutlineFilter.All.Visibilities;
  end
  else
  begin
    FFilter.Visibilities := AVisibilities;
  end;
  UpdateButtons;
  Refill;
end;

procedure TAtlasOutlineFrameRows.SetCategories(const ACategories: TAtlasOutlineCategories);
begin
  if ACategories = [] then
  begin
    FFilter.Categories := TAtlasOutlineFilter.All.Categories;
  end
  else
  begin
    FFilter.Categories := ACategories + [TAtlasOutlineCategory.Section];
  end;
  UpdateButtons;
  Refill;
end;

procedure TAtlasOutlineFrameRows.SetAlphabetical(AValue: Boolean);
begin
  if FAlphabetical = AValue then
  begin
    Exit;
  end;
  FAlphabetical := AValue;
  UpdateButtons;
  Refill;
end;

procedure TAtlasOutlineFrameRows.SetShowConditions(AValue: Boolean);
begin
  if FShowConditions = AValue then
  begin
    Exit;
  end;
  FShowConditions := AValue;
  if FList.HandleAllocated then
  begin
    FList.Invalidate;
  end;
end;

procedure TAtlasOutlineFrame.SetFollowCursor(AValue: Boolean);
begin
  FFollowCursor := AValue;
  FFollowItem.Checked := AValue;
end;

function TAtlasOutlineFrameRows.SelectedNode: Integer;
begin
  Result := -1;
  // ItemIndex fragt das Fenster ab; ohne Fenster gibt es keine Auswahl.
  if not FList.HandleAllocated then
  begin
    Exit;
  end;
  if (FList.ItemIndex >= 0) and (FList.ItemIndex <= High(FRows)) then
  begin
    Result := FRows[FList.ItemIndex].Node;
  end;
end;

procedure TAtlasOutlineFrameRows.SelectRow(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FRows)) then
  begin
    Exit;
  end;
  // ItemIndex braucht das Fenster der Liste und damit ein Formular darüber.
  if not ListCanHaveHandle then
  begin
    Exit;
  end;
  FList.ItemIndex := AIndex;
  if (AIndex < FList.TopIndex) or (AIndex >= FList.TopIndex + Max(1, FList.ClientHeight div FList.ItemHeight)) then
  begin
    FList.TopIndex := Max(0, AIndex - 2);
  end;
end;

function TAtlasOutlineFrameRows.RowHasChildren(AIndex: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to High(FAllRows) do
  begin
    if FAllRows[mIndex].Node = FRows[AIndex].Node then
    begin
      Exit((mIndex < High(FAllRows)) and (FAllRows[mIndex + 1].Depth > FAllRows[mIndex].Depth));
    end;
  end;
end;

procedure TAtlasOutlineFrameRows.ToggleRow(AIndex: Integer);
var
  mPath: string;
  mPosition: Integer;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) or not RowHasChildren(AIndex) then
  begin
    Exit;
  end;
  mPath := PathOf(FRows[AIndex].Node);
  mPosition := FCollapsed.IndexOf(mPath);
  if mPosition >= 0 then
  begin
    FCollapsed.Delete(mPosition);
  end
  else
  begin
    FCollapsed.Add(mPath);
  end;
  Refill;
end;

function TAtlasOutlineFrameRows.HighlightAt(ALine, ACharacter: Integer): Boolean;
var
  mNode, mParent, mIndex: Integer;
  mOpened: Boolean;
begin
  Result := False;
  mNode := TAtlasOutline.NodeAt(FNodes, ALine, ACharacter);
  if mNode < 0 then
  begin
    Exit;
  end;
  // Eltern aufklappen, damit der Eintrag zu sehen ist.
  mOpened := False;
  mParent := FNodes[mNode].Parent;
  while mParent >= 0 do
  begin
    mIndex := FCollapsed.IndexOf(PathOf(mParent));
    if mIndex >= 0 then
    begin
      FCollapsed.Delete(mIndex);
      mOpened := True;
    end;
    mParent := FNodes[mParent].Parent;
  end;
  if mOpened then
  begin
    Refill;
  end;
  // Ausgefiltert: der nächste gezeigte Elternknoten.
  while mNode >= 0 do
  begin
    for mIndex := 0 to High(FRows) do
    begin
      if FRows[mIndex].Node = mNode then
      begin
        if FList.ItemIndex <> mIndex then
        begin
          SelectRow(mIndex);
        end;
        Exit(True);
      end;
    end;
    mNode := FNodes[mNode].Parent;
  end;
end;

procedure TAtlasOutlineFrame.OpenSelected(AImplementation: Boolean);
var
  mNode: Integer;
begin
  mNode := SelectedNode;
  if (mNode >= 0) and Assigned(FOnOpen) then
  begin
    FOnOpen(mNode, AImplementation);
  end;
end;

function TAtlasOutlineFrameRows.RowText(AIndex: Integer): string;
var
  mNode: TAtlasOutlineNode;
begin
  mNode := FNodes[FRows[AIndex].Node];
  Result := TAtlasOutline.VisibilityMark(mNode.Visibility);
  if Result <> '' then
  begin
    Result := Result + ' ';
  end;
  Result := Result + mNode.Name;
  if (mNode.Category = TAtlasOutlineCategory.TypeDecl) and (mNode.Detail <> '') then
  begin
    Result := Result + ' · ' + mNode.Detail;
  end;
  if mNode.ClassMember then
  begin
    Result := Result + ' · class';
  end;
  if mNode.IsOverride then
  begin
    Result := Result + ' · override';
  end;
  if mNode.IsVirtual and not mNode.IsOverride then
  begin
    Result := Result + ' · virtual';
  end;
  if mNode.IsAbstract then
  begin
    Result := Result + ' · abstract';
  end;
  if mNode.Unimplemented then
  begin
    Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.OutlineUnimplemented);
  end;
  if FShowConditions and (mNode.Condition <> '') then
  begin
    Result := Result + ' · ' + mNode.Condition;
  end;
end;

function TAtlasOutlineFrameRows.ExpanderRect(AIndex: Integer; const ARect: TRect): TRect;
begin
  Result := ARect;
  Result.Left := ARect.Left + Scale(4) + FRows[AIndex].Depth * Scale(cIndentPx);
  Result.Right := Result.Left + Scale(cExpanderPx);
end;

/// <summary>AText ab AX in der Zeile ARect, AX danach hinter dem Text; leer zeichnet nichts.</summary>
procedure PutText(ACanvas: TCanvas; var AX: Integer; const ARect: TRect; const AText: string; AColor: TAtlasColor;
  AStyle: TFontStyles);
begin
  if AText = '' then
  begin
    Exit;
  end;
  ACanvas.Font.Color := ToColor(AColor);
  ACanvas.Font.Style := AStyle;
  ACanvas.TextOut(AX, ARect.Top + (ARect.Height - ACanvas.TextHeight('Ag')) div 2, AText);
  Inc(AX, ACanvas.TextWidth(AText));
end;

/// <summary>Gedämpfte Marken hinter dem Namen: Art des Typs, class, override, virtual, abstract.</summary>
function ExtraText(const ANode: TAtlasOutlineNode): string;
begin
  Result := '';
  if (ANode.Category = TAtlasOutlineCategory.TypeDecl) and (ANode.Detail <> '') then
  begin
    Result := Result + '  ' + ANode.Detail;
  end;
  if ANode.ClassMember then
  begin
    Result := Result + '  class';
  end;
  if ANode.IsOverride then
  begin
    Result := Result + '  override';
  end;
  if ANode.IsVirtual and not ANode.IsOverride then
  begin
    Result := Result + '  virtual';
  end;
  if ANode.IsAbstract then
  begin
    Result := Result + '  abstract';
  end;
end;

/// <summary>Name des Knotens: Abschnitte fett, Treffer in Textfarbe, bloße Rahmen gedämpft.</summary>
procedure PutName(ACanvas: TCanvas; var AX: Integer; const ARect: TRect; const ANode: TAtlasOutlineNode;
  AMatched: Boolean; const AColors: TAtlasColors);
begin
  if ANode.Category = TAtlasOutlineCategory.Section then
  begin
    PutText(ACanvas, AX, ARect, ANode.Name, AColors.Keyword, [fsBold]);
  end
  else if AMatched then
  begin
    PutText(ACanvas, AX, ARect, ANode.Name, AColors.Text, []);
  end
  else
  begin
    PutText(ACanvas, AX, ARect, ANode.Name, AColors.Muted, []);
  end;
end;

function TAtlasOutlineFrameRows.IsCollapsed(AIndex: Integer): Boolean;
begin
  Result := FCollapsed.IndexOf(PathOf(FRows[AIndex].Node)) >= 0;
end;

procedure TAtlasOutlineFrameRows.ListDrawItem(Control: TWinControl; Index: Integer; Rect: TRect;
  State: TOwnerDrawState);
var
  mColors: TAtlasColors;
  mCanvas: TCanvas;
  mNode: TAtlasOutlineNode;
  mBox: TRect;
  X: Integer;
  mMark: string;
begin
  if (Index < 0) or (Index > High(FRows)) then
  begin
    Exit;
  end;
  mColors := StyleColors;
  mCanvas := FList.Canvas;
  mNode := FNodes[FRows[Index].Node];
  mCanvas.Brush.Style := bsSolid;
  mCanvas.Brush.Color := ToColor(mColors.Surface);
  if odSelected in State then
  begin
    mCanvas.Brush.Color := ToColor(mColors.Selection);
  end;
  mCanvas.FillRect(Rect);
  mCanvas.Brush.Style := bsClear;
  mCanvas.Font.Assign(FList.Font);
  mBox := ExpanderRect(Index, Rect);
  X := mBox.Left;
  if RowHasChildren(Index) and (FFilter.Text = '') and IsCollapsed(Index) then
  begin
    PutText(mCanvas, X, Rect, '▸', mColors.Muted, []);
  end
  else if RowHasChildren(Index) then
  begin
    PutText(mCanvas, X, Rect, '▾', mColors.Muted, []);
  end;
  X := mBox.Right + Scale(2);
  mMark := TAtlasOutline.VisibilityMark(mNode.Visibility);
  if mMark <> '' then
  begin
    PutText(mCanvas, X, Rect, mMark + ' ', mColors.Accent, []);
  end;
  PutName(mCanvas, X, Rect, mNode, FRows[Index].Matched, mColors);
  PutText(mCanvas, X, Rect, ExtraText(mNode), mColors.Muted, []);
  if mNode.Unimplemented then
  begin
    PutText(mCanvas, X, Rect, '  ' + TAtlasStrings.Text(TAtlasTextId.OutlineUnimplemented), mColors.Warn, [fsItalic]);
  end;
  // Aktiver Zweig der bedingten Kompilierung (#845), wie die Marke im Mockup.
  if FShowConditions and (mNode.Condition <> '') then
  begin
    PutText(mCanvas, X, Rect, '  ' + mNode.Condition, mColors.Accent, []);
  end;
  if odFocused in State then
  begin
    mCanvas.DrawFocusRect(Rect);
  end;
end;

procedure TAtlasOutlineFrame.ListMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
var
  mIndex: Integer;
begin
  FExpanderClick := False;
  FMouseOpen := False;
  mIndex := FList.ItemAtPos(Point(X, Y), True);
  if (mIndex < 0) or (Button <> mbLeft) then
  begin
    Exit;
  end;
  if RowHasChildren(mIndex) and (X < ExpanderRect(mIndex, FList.ItemRect(mIndex)).Right) then
  begin
    FExpanderClick := True;
    ToggleRow(mIndex);
    Exit;
  end;
  FMouseOpen := True;
end;

procedure TAtlasOutlineFrame.ListClick(Sender: TObject);
begin
  // Auch Pfeiltasten melden OnClick; springen nur nach einem Mausklick auf einen Namen.
  if not FMouseOpen then
  begin
    Exit;
  end;
  FMouseOpen := False;
  OpenSelected(False);
end;

procedure TAtlasOutlineFrame.ListDblClick(Sender: TObject);
begin
  if FExpanderClick then
  begin
    Exit;
  end;
  OpenSelected(True);
end;

procedure TAtlasOutlineFrame.KeyLeft(AIndex: Integer);
var
  mIndex: Integer;
begin
  if AIndex < 0 then
  begin
    Exit;
  end;
  if RowHasChildren(AIndex) and not IsCollapsed(AIndex) then
  begin
    ToggleRow(AIndex);
    Exit;
  end;
  if FNodes[FRows[AIndex].Node].Parent < 0 then
  begin
    Exit;
  end;
  for mIndex := AIndex - 1 downto 0 do
  begin
    if FRows[mIndex].Depth < FRows[AIndex].Depth then
    begin
      SelectRow(mIndex);
      Exit;
    end;
  end;
end;

procedure TAtlasOutlineFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mIndex: Integer;
begin
  mIndex := FList.ItemIndex;
  case Key of
    VK_RETURN:
      begin
        OpenSelected(ssCtrl in Shift);
        Key := 0;
      end;
    VK_LEFT:
      begin
        KeyLeft(mIndex);
        Key := 0;
      end;
    VK_RIGHT:
      begin
        if (mIndex >= 0) and IsCollapsed(mIndex) then
        begin
          ToggleRow(mIndex);
        end;
        Key := 0;
      end;
  end;
end;

procedure TAtlasOutlineFrame.SearchChange(Sender: TObject);
begin
  FFilter.Text := Trim(FSearch.Text);
  Refill;
end;

procedure TAtlasOutlineFrame.SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mIndex: Integer;
begin
  case Key of
    VK_DOWN:
      if Length(FRows) > 0 then
      begin
        FList.SetFocus;
        if FList.ItemIndex < 0 then
        begin
          SelectRow(0);
        end;
        Key := 0;
      end;
    VK_RETURN:
      begin
        // Erster Treffer, nicht der erste Rahmen.
        for mIndex := 0 to High(FRows) do
        begin
          if FRows[mIndex].Matched then
          begin
            SelectRow(mIndex);
            OpenSelected(ssCtrl in Shift);
            Break;
          end;
        end;
        Key := 0;
      end;
    VK_ESCAPE:
      begin
        FSearch.Text := '';
        Key := 0;
      end;
  end;
end;

procedure TAtlasOutlineFrame.SearchKeyPress(Sender: TObject; var Key: Char);
begin
  // Kein Signalton bei Enter und Esc.
  if (Key = #13) or (Key = #27) then
  begin
    Key := #0;
  end;
end;

procedure TAtlasOutlineFrame.VisibilityClick(Sender: TObject);
var
  mOrigin: TPoint;
begin
  mOrigin := FVisibilityButton.ClientToScreen(Point(0, FVisibilityButton.Height));
  FVisibilityMenu.Popup(mOrigin.X, mOrigin.Y);
end;

procedure TAtlasOutlineFrame.KindClick(Sender: TObject);
var
  mOrigin: TPoint;
begin
  mOrigin := FKindButton.ClientToScreen(Point(0, FKindButton.Height));
  FKindMenu.Popup(mOrigin.X, mOrigin.Y);
end;

procedure TAtlasOutlineFrame.SortClick(Sender: TObject);
begin
  Alphabetical := not FAlphabetical;
  if Assigned(FOnSortChanged) then
  begin
    FOnSortChanged(FAlphabetical);
  end;
end;

procedure TAtlasOutlineFrame.VisibilityItemClick(Sender: TObject);
var
  mItem: TMenuItem;
  mVisibility: TAtlasOutlineVisibility;
  mNext: TAtlasOutlineVisibilities;
begin
  mItem := TMenuItem(Sender);
  if mItem.Tag = cTagAll then
  begin
    SetVisibilities([]);
    Exit;
  end;
  mVisibility := TAtlasOutline.FilterVisibilities[mItem.Tag];
  // Aus „alle“ heraus wählt ein Klick genau diese Sichtbarkeit, sonst schaltet er sie um.
  if FFilter.AllVisibilities then
  begin
    mNext := [mVisibility];
  end
  else
  begin
    mNext := FFilter.Visibilities * [TAtlasOutlineVisibility.Private, TAtlasOutlineVisibility.Protected,
      TAtlasOutlineVisibility.Public, TAtlasOutlineVisibility.Published];
    if mVisibility in mNext then
    begin
      Exclude(mNext, mVisibility);
    end
    else
    begin
      Include(mNext, mVisibility);
    end;
  end;
  SetVisibilities(mNext);
end;

procedure TAtlasOutlineFrame.KindItemClick(Sender: TObject);
var
  mItem: TMenuItem;
  mCategory: TAtlasOutlineCategory;
  mNext: TAtlasOutlineCategories;
begin
  mItem := TMenuItem(Sender);
  if mItem.Tag = cTagAll then
  begin
    SetCategories([]);
    Exit;
  end;
  mCategory := cKindCategories[mItem.Tag];
  if FFilter.AllCategories then
  begin
    mNext := [mCategory];
  end
  else
  begin
    mNext := FFilter.Categories - [TAtlasOutlineCategory.Section];
    if mCategory in mNext then
    begin
      Exclude(mNext, mCategory);
    end
    else
    begin
      Include(mNext, mCategory);
    end;
  end;
  SetCategories(mNext);
end;

procedure TAtlasOutlineFrame.ListMenuPopup(Sender: TObject);
var
  mNode: Integer;
begin
  mNode := SelectedNode;
  FListMenu.Items[0].Enabled := mNode >= 0;
  FListMenu.Items[1].Enabled := (mNode >= 0) and (FNodes[mNode].Body >= 0);
  FFollowItem.Checked := FFollowCursor;
end;

procedure TAtlasOutlineFrame.DeclarationClick(Sender: TObject);
begin
  OpenSelected(False);
end;

procedure TAtlasOutlineFrame.ImplementationClick(Sender: TObject);
begin
  OpenSelected(True);
end;

procedure TAtlasOutlineFrame.FollowClick(Sender: TObject);
begin
  FollowCursor := not FFollowCursor;
  if Assigned(FOnFollowChanged) then
  begin
    FOnFollowChanged(FFollowCursor);
  end;
end;

end.
