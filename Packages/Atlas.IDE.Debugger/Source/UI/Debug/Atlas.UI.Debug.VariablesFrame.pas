unit Atlas.UI.Debug.VariablesFrame;

// Inhalt des Fensters „Variablen“ (#853), reine VCL: oben die Reiter Autos,
// Lokal und Überwachung, darunter das Suchfeld mit „In Werten“ und
// „Unterelemente“, im Reiter Überwachung das Eingabefeld für neue Ausdrücke.
// In der Mitte der Baum der gewählten TAtlasEvalList wie im Fenster
// „Auswerten“ (TAtlasEvalTreeSync): seit dem letzten Schritt geänderte Werte
// in der Warnfarbe, bei einer Suche nur Treffer, ihre Pfade und ihre
// Unterelemente, Treffer fett. Kontextmenü und Tasten je Zeile: als
// Überwachung hinzufügen (Strg+W), Wert kopieren (Strg+C), Ausdruck kopieren
// (Strg+Umschalt+C), Wert ändern (F2, über „Werte ändern“ #868), Überwachung
// entfernen (Entf). Unten Anzahl bzw. Treffer
// und die Tastenhilfe. Die Suche startet kurz nach der letzten Eingabe.
// Die DFM ist leer, weil TCustomFrame.Create für abgeleitete Frames eine
// Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Buttons,
  Vcl.ComCtrls,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Core.Debug.Evaluate,
  Atlas.Core.Debug.Variables,
  Atlas.UI.Debug.EvaluateTree,
  Atlas.UI.Foundation.WrapLabel;

type
  TAtlasVariablesNodeProc = reference to procedure(ANode: TAtlasEvalNode);
  TAtlasVariablesSearchProc = reference to procedure(const AText: string; AMode: TAtlasVariableSearchMode;
    ADeep: Boolean);

  /// <summary>Was der Frame an die IDE-Schicht meldet; nicht gesetzte Einträge bleiben still.</summary>
  TAtlasVariablesFrameHooks = record
    /// <summary>Anderer Reiter; danach SetList mit dessen Liste.</summary>
    Tab: TProc<TAtlasVariablesTab>;
    /// <summary>Suchtext oder Schalter geändert (leerer Text: Suche aus).</summary>
    Search: TAtlasVariablesSearchProc;
    /// <summary>Erstes Aufklappen: Felder holen, danach Refresh.</summary>
    Expand: TAtlasVariablesNodeProc;
    AddWatch: TProc<string>;
    RemoveWatch: TAtlasVariablesNodeProc;
    /// <summary>Wert der Zeile ändern (#868).</summary>
    EditValue: TAtlasVariablesNodeProc;
    /// <summary>Lässt sich gerade ein Wert ändern (debug.editValues an, Programm angehalten)?</summary>
    CanEditValue: TFunc<Boolean>;
  end;

  /// <summary>Steuerelemente des Frames; alle gehören dem Frame.</summary>
  TAtlasVariablesFrameParts = record
    Tabs: TPanel;
    TabButtons: array[TAtlasVariablesTab] of TSpeedButton;
    SearchBar: TPanel;
    SearchEdit: TEdit;
    ValuesCheck: TCheckBox;
    DeepCheck: TCheckBox;
    WatchBar: TPanel;
    WatchEdit: TEdit;
    Tree: TTreeView;
    Menu: TPopupMenu;
    Status: TAtlasWrapLabel;
    Keys: TAtlasWrapLabel;
    SearchTimer: TTimer;
  end;

  TAtlasDebugVariablesFrame = class(TFrame)
  public const
    /// <summary>So lange nach der letzten Eingabe startet die Suche.</summary>
    cSearchDelayMs = 300;
  private
    FParts: TAtlasVariablesFrameParts;
    FList: TAtlasEvalList;
    FSearch: TAtlasVariableSearch;
    FSync: TAtlasEvalTreeSync;
    FTab: TAtlasVariablesTab;
    FFilling: Boolean;
    FHooks: TAtlasVariablesFrameHooks;
    procedure TabClick(Sender: TObject);
    procedure SearchChange(Sender: TObject);
    procedure SearchTimer(Sender: TObject);
    procedure SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure WatchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
    procedure TreeCollapsing(Sender: TObject; Node: TTreeNode; var AllowCollapse: Boolean);
    procedure TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure MenuPopup(Sender: TObject);
    procedure MenuClick(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Liste des Reiters und Suche, die der Baum zeigt; beide gehören der IDE-Schicht (nil: leer).
    /// </summary>
    procedure SetList(AList: TAtlasEvalList; ASearch: TAtlasVariableSearch);
    /// <summary>Nach jeder Änderung der Liste oder der Suche.</summary>
    procedure Refresh;
    /// <summary>Text unten (Anzahl, Treffer, Hinweis).</summary>
    procedure SetStatus(const AText: string);
    procedure SetTab(ATab: TAtlasVariablesTab);
    procedure FocusSearch;
    /// <summary>Gewählter Knoten; nil ohne Auswahl.</summary>
    function Selected: TAtlasEvalNode;
    procedure Select(const AKey: string);
    /// <summary>Text für „Wert kopieren“: der ganze Wert, ohne Wert leer.</summary>
    class function ValueText(ANode: TAtlasEvalNode): string; static;
    property Parts: TAtlasVariablesFrameParts read FParts;
    property Tab: TAtlasVariablesTab read FTab;
    /// <summary>Anderer Reiter; danach SetList mit dessen Liste.</summary>
    property OnTab: TProc<TAtlasVariablesTab> read FHooks.Tab write FHooks.Tab;
    /// <summary>Suchtext oder Schalter geändert (leerer Text: Suche aus).</summary>
    property OnSearch: TAtlasVariablesSearchProc read FHooks.Search write FHooks.Search;
    /// <summary>Erstes Aufklappen: Felder holen, danach Refresh.</summary>
    property OnExpand: TAtlasVariablesNodeProc read FHooks.Expand write FHooks.Expand;
    property OnAddWatch: TProc<string> read FHooks.AddWatch write FHooks.AddWatch;
    property OnRemoveWatch: TAtlasVariablesNodeProc read FHooks.RemoveWatch write FHooks.RemoveWatch;
    property OnEditValue: TAtlasVariablesNodeProc read FHooks.EditValue write FHooks.EditValue;
    property OnCanEditValue: TFunc<Boolean> read FHooks.CanEditValue write FHooks.CanEditValue;
  end;

implementation

uses
  System.UITypes,
  Winapi.Windows,
  Vcl.Clipbrd,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Debug.Strings;

{$R *.dfm}

const
  cButtonHeight = 24;
  cBarHeight = 30;
  cTabWidth = 96;
  cCheckWidth = 110;
  /// <summary>Abstand der Lage vor dem Ausrichten: Sie bestimmt die Reihenfolge gleich ausgerichteter Teile.
  /// </summary>
  cOrderStep = 1000;
  cTabTexts: array[TAtlasVariablesTab] of TAtlasDebugTextId = (TAtlasDebugTextId.VariablesTabAutos,
    TAtlasDebugTextId.VariablesTabLocals, TAtlasDebugTextId.VariablesTabWatch);

type
  {$SCOPEDENUMS ON}
  /// <summary>Einträge des Kontextmenüs, als Tag der Menüeinträge.</summary>
  TRowAction = (None, AddWatch, CopyValue, CopyExpression, EditValue, RemoveWatch);
  {$SCOPEDENUMS OFF}

{ Aufbau }

function Px(ASelf: TAtlasDebugVariablesFrame; AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, ASelf.CurrentPPI, 96);
end;

function AddBar(ASelf: TAtlasDebugVariablesFrame; AOrder: Integer): TPanel;
begin
  Result := TPanel.Create(ASelf);
  // Erst Lage und Höhe, dann ausrichten: Sonst kann die VCL die Reihenfolge der Leisten vertauschen.
  Result.Top := AOrder * cOrderStep;
  Result.Height := Px(ASelf, cBarHeight);
  Result.Align := alTop;
  Result.BevelOuter := bvNone;
  Result.ShowCaption := False;
  Result.ParentBackground := True;
  Result.Parent := ASelf;
end;

function AddCheck(ASelf: TAtlasDebugVariablesFrame; AParent: TWinControl; AText: TAtlasDebugTextId;
  AOrder: Integer): TCheckBox;
begin
  Result := TCheckBox.Create(ASelf);
  // Lage vor dem Ausrichten: Sie bestimmt die Reihenfolge am rechten Rand.
  Result.Left := AOrder * cOrderStep;
  Result.Parent := AParent;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := Px(ASelf, cCheckWidth);
  Result.Caption := TAtlasDebugStrings.Text(AText);
  Result.OnClick := ASelf.SearchChange;
end;

procedure BuildTabs(ASelf: TAtlasDebugVariablesFrame);
var
  mTab: TAtlasVariablesTab;
  mButton: TSpeedButton;
begin
  ASelf.FParts.Tabs := AddBar(ASelf, 0);
  for mTab := Low(TAtlasVariablesTab) to High(TAtlasVariablesTab) do
  begin
    mButton := TSpeedButton.Create(ASelf);
    // Lage vor dem Ausrichten: Sie bestimmt die Reihenfolge am linken Rand.
    mButton.Left := cOrderStep * Ord(mTab);
    mButton.Parent := ASelf.FParts.Tabs;
    mButton.Align := alLeft;
    mButton.AlignWithMargins := True;
    mButton.Width := Px(ASelf, cTabWidth);
    mButton.Height := Px(ASelf, cButtonHeight);
    mButton.GroupIndex := 1;
    mButton.AllowAllUp := False;
    mButton.Caption := TAtlasDebugStrings.Text(cTabTexts[mTab]);
    mButton.Tag := Ord(mTab);
    mButton.Down := mTab = ASelf.FTab;
    mButton.OnClick := ASelf.TabClick;
    ASelf.FParts.TabButtons[mTab] := mButton;
  end;
end;

procedure BuildSearch(ASelf: TAtlasDebugVariablesFrame);
begin
  ASelf.FParts.SearchBar := AddBar(ASelf, 1);
  ASelf.FParts.ValuesCheck := AddCheck(ASelf, ASelf.FParts.SearchBar, TAtlasDebugTextId.VariablesSearchValues, 1);
  ASelf.FParts.DeepCheck := AddCheck(ASelf, ASelf.FParts.SearchBar, TAtlasDebugTextId.VariablesSearchDeep, 2);
  ASelf.FParts.SearchEdit := TEdit.Create(ASelf);
  ASelf.FParts.SearchEdit.Parent := ASelf.FParts.SearchBar;
  ASelf.FParts.SearchEdit.Align := alClient;
  ASelf.FParts.SearchEdit.AlignWithMargins := True;
  ASelf.FParts.SearchEdit.TextHint := TAtlasDebugStrings.Text(TAtlasDebugTextId.VariablesSearchHint);
  ASelf.FParts.SearchEdit.OnChange := ASelf.SearchChange;
  ASelf.FParts.SearchEdit.OnKeyDown := ASelf.SearchKeyDown;
  ASelf.FParts.SearchTimer := TTimer.Create(ASelf);
  ASelf.FParts.SearchTimer.Enabled := False;
  ASelf.FParts.SearchTimer.Interval := TAtlasDebugVariablesFrame.cSearchDelayMs;
  ASelf.FParts.SearchTimer.OnTimer := ASelf.SearchTimer;
end;

procedure BuildWatch(ASelf: TAtlasDebugVariablesFrame);
begin
  ASelf.FParts.WatchBar := AddBar(ASelf, 2);
  ASelf.FParts.WatchBar.Visible := False;
  ASelf.FParts.WatchEdit := TEdit.Create(ASelf);
  ASelf.FParts.WatchEdit.Parent := ASelf.FParts.WatchBar;
  ASelf.FParts.WatchEdit.Align := alClient;
  ASelf.FParts.WatchEdit.AlignWithMargins := True;
  ASelf.FParts.WatchEdit.TextHint := TAtlasDebugStrings.Text(TAtlasDebugTextId.VariablesWatchHint);
  ASelf.FParts.WatchEdit.OnKeyDown := ASelf.WatchKeyDown;
end;

function AddFooter(ASelf: TAtlasDebugVariablesFrame; AOrder: Integer; const AText: string): TAtlasWrapLabel;
begin
  Result := TAtlasWrapLabel.Create(ASelf);
  // Unten ausgerichtet: Die größere Lage steht weiter unten.
  Result.Top := AOrder * cOrderStep;
  Result.Align := alBottom;
  Result.AlignWithMargins := True;
  Result.Font.Color := clGrayText;
  Result.Caption := AText;
  Result.Parent := ASelf;
end;

procedure AddMenuItem(ASelf: TAtlasDebugVariablesFrame; AText: TAtlasDebugTextId; AAction: TRowAction;
  AShortCut: TShortCut);
var
  mItem: TMenuItem;
begin
  mItem := TMenuItem.Create(ASelf.FParts.Menu);
  mItem.Caption := TAtlasDebugStrings.Text(AText);
  mItem.Tag := Ord(AAction);
  mItem.ShortCut := AShortCut;
  mItem.OnClick := ASelf.MenuClick;
  ASelf.FParts.Menu.Items.Add(mItem);
end;

procedure BuildTree(ASelf: TAtlasDebugVariablesFrame);
begin
  ASelf.FParts.Menu := TPopupMenu.Create(ASelf);
  ASelf.FParts.Menu.OnPopup := ASelf.MenuPopup;
  AddMenuItem(ASelf, TAtlasDebugTextId.VariablesAddWatch, TRowAction.AddWatch, ShortCut(Ord('W'), [ssCtrl]));
  AddMenuItem(ASelf, TAtlasDebugTextId.VariablesCopyValue, TRowAction.CopyValue, ShortCut(Ord('C'), [ssCtrl]));
  AddMenuItem(ASelf, TAtlasDebugTextId.VariablesCopyExpression, TRowAction.CopyExpression,
    ShortCut(Ord('C'), [ssCtrl, ssShift]));
  AddMenuItem(ASelf, TAtlasDebugTextId.EditValueAction, TRowAction.EditValue, ShortCut(VK_F2, []));
  AddMenuItem(ASelf, TAtlasDebugTextId.VariablesRemoveWatch, TRowAction.RemoveWatch, ShortCut(VK_DELETE, []));

  ASelf.FParts.Tree := TTreeView.Create(ASelf);
  ASelf.FParts.Tree.Parent := ASelf;
  ASelf.FParts.Tree.Align := alClient;
  ASelf.FParts.Tree.AlignWithMargins := True;
  ASelf.FParts.Tree.ReadOnly := True;
  ASelf.FParts.Tree.HideSelection := False;
  ASelf.FParts.Tree.PopupMenu := ASelf.FParts.Menu;
  ASelf.FParts.Tree.OnKeyDown := ASelf.TreeKeyDown;
  ASelf.FParts.Tree.OnExpanding := ASelf.TreeExpanding;
  ASelf.FParts.Tree.OnCollapsing := ASelf.TreeCollapsing;
  ASelf.FParts.Tree.OnCustomDrawItem := ASelf.TreeCustomDrawItem;
end;

/// <summary>Sichtbar und Treffer kommen aus der Suche der IDE-Schicht, solange der Frame sie kennt.</summary>
procedure WireSync(ASelf: TAtlasDebugVariablesFrame);
begin
  ASelf.FSync.Visible :=
    function(ANode: TAtlasEvalNode): Boolean
    begin
      Result := (ASelf.FSearch = nil) or ASelf.FSearch.IsShown(ANode);
    end;
  ASelf.FSync.Emphasis :=
    function(ANode: TAtlasEvalNode): Boolean
    begin
      Result := (ASelf.FSearch <> nil) and ASelf.FSearch.IsHit(ANode);
    end;
end;

{ Zeilen }

function NodeOf(ASelf: TAtlasDebugVariablesFrame; AItem: TTreeNode): TAtlasEvalNode;
var
  mKey: string;
begin
  Result := nil;
  mKey := ASelf.FSync.KeyOf(AItem);
  if (mKey <> '') and (ASelf.FList <> nil) then
  begin
    Result := ASelf.FList.Find(mKey);
  end;
end;

function RowEnabled(ASelf: TAtlasDebugVariablesFrame; ANode: TAtlasEvalNode; AAction: TRowAction): Boolean;
begin
  Result := False;
  if ANode = nil then
  begin
    Exit;
  end;
  case AAction of
    TRowAction.AddWatch, TRowAction.CopyExpression:
      Result := ANode.Expression <> '';
    TRowAction.CopyValue:
      Result := ANode.State = TAtlasEvalState.Value;
    TRowAction.EditValue:
      Result := (ANode.State = TAtlasEvalState.Value) and Assigned(ASelf.FHooks.EditValue) and
        Assigned(ASelf.FHooks.CanEditValue) and ASelf.FHooks.CanEditValue();
    TRowAction.RemoveWatch:
      Result := (ASelf.FTab = TAtlasVariablesTab.Watch) and (ANode.Parent = nil);
    TRowAction.None: ;
  end;
end;

procedure RunRow(ASelf: TAtlasDebugVariablesFrame; ANode: TAtlasEvalNode; AAction: TRowAction);
begin
  if not RowEnabled(ASelf, ANode, AAction) then
  begin
    Exit;
  end;
  case AAction of
    TRowAction.AddWatch:
      if Assigned(ASelf.FHooks.AddWatch) then
      begin
        ASelf.FHooks.AddWatch(ANode.Expression);
      end;
    TRowAction.CopyValue:
      Clipboard.AsText := TAtlasDebugVariablesFrame.ValueText(ANode);
    TRowAction.CopyExpression:
      Clipboard.AsText := ANode.Expression;
    TRowAction.EditValue:
      ASelf.FHooks.EditValue(ANode);
    TRowAction.RemoveWatch:
      if Assigned(ASelf.FHooks.RemoveWatch) then
      begin
        ASelf.FHooks.RemoveWatch(ANode);
      end;
    TRowAction.None: ;
  end;
end;

function KeyAction(AKey: Word; AShift: TShiftState): TRowAction;
begin
  Result := TRowAction.None;
  if (AKey = Ord('W')) and (AShift = [ssCtrl]) then
  begin
    Result := TRowAction.AddWatch;
  end
  else if (AKey = Ord('C')) and (AShift = [ssCtrl]) then
  begin
    Result := TRowAction.CopyValue;
  end
  else if (AKey = Ord('C')) and (AShift = [ssCtrl, ssShift]) then
  begin
    Result := TRowAction.CopyExpression;
  end
  else if (AKey = VK_F2) and (AShift = []) then
  begin
    Result := TRowAction.EditValue;
  end
  else if (AKey = VK_DELETE) and (AShift = []) then
  begin
    Result := TRowAction.RemoveWatch;
  end;
end;

function TreeColor(ASelf: TAtlasDebugVariablesFrame; AColor: TColor): TColor;
begin
  Result := ColorToRGB(StyleServices(ASelf.FParts.Tree).GetSystemColor(AColor));
end;

{ TAtlasDebugVariablesFrame }

constructor TAtlasDebugVariablesFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Name := '';
  FTab := TAtlasVariablesTab.Autos;
  BuildTabs(Self);
  BuildSearch(Self);
  BuildWatch(Self);
  FParts.Keys := AddFooter(Self, 2, TAtlasDebugStrings.Text(TAtlasDebugTextId.VariablesKeys));
  FParts.Status := AddFooter(Self, 1, '');
  BuildTree(Self);
  FSync := TAtlasEvalTreeSync.Create(FParts.Tree);
  WireSync(Self);
end;

destructor TAtlasDebugVariablesFrame.Destroy;
begin
  if FParts.Tree <> nil then
  begin
    FParts.Tree.OnExpanding := nil;
    FParts.Tree.OnCollapsing := nil;
    FParts.Tree.OnCustomDrawItem := nil;
  end;
  if FParts.SearchTimer <> nil then
  begin
    FParts.SearchTimer.Enabled := False;
  end;
  FreeAndNil(FSync);
  FList := nil;
  FSearch := nil;
  inherited Destroy;
end;

procedure TAtlasDebugVariablesFrame.CreateWnd;
begin
  inherited CreateWnd;
  // TTreeView.Items braucht ein Fenster.
  Refresh;
end;

procedure TAtlasDebugVariablesFrame.SetList(AList: TAtlasEvalList; ASearch: TAtlasVariableSearch);
begin
  FList := AList;
  FSearch := ASearch;
  Refresh;
end;

procedure TAtlasDebugVariablesFrame.Refresh;
var
  mKeep: string;
begin
  if not HandleAllocated then
  begin
    Exit;
  end;
  mKeep := FSync.KeyOf(FParts.Tree.Selected);
  FFilling := True;
  try
    FSync.Sync(FList);
  finally
    FFilling := False;
  end;
  if (mKeep <> '') and (FSync.KeyOf(FParts.Tree.Selected) <> mKeep) then
  begin
    Select(mKeep);
  end;
end;

procedure TAtlasDebugVariablesFrame.SetStatus(const AText: string);
begin
  if FParts.Status.Caption <> AText then
  begin
    FParts.Status.Caption := AText;
  end;
end;

procedure TAtlasDebugVariablesFrame.SetTab(ATab: TAtlasVariablesTab);
begin
  FTab := ATab;
  FParts.TabButtons[ATab].Down := True;
  FParts.WatchBar.Visible := ATab = TAtlasVariablesTab.Watch;
end;

procedure TAtlasDebugVariablesFrame.FocusSearch;
begin
  if FParts.SearchEdit.CanFocus and FParts.SearchEdit.Showing then
  begin
    FParts.SearchEdit.SetFocus;
    FParts.SearchEdit.SelectAll;
  end;
end;

function TAtlasDebugVariablesFrame.Selected: TAtlasEvalNode;
begin
  Result := nil;
  if HandleAllocated then
  begin
    Result := NodeOf(Self, FParts.Tree.Selected);
  end;
end;

procedure TAtlasDebugVariablesFrame.Select(const AKey: string);
var
  mItem: TTreeNode;
begin
  if not HandleAllocated then
  begin
    Exit;
  end;
  mItem := FSync.ItemOf(AKey);
  if mItem <> nil then
  begin
    FParts.Tree.Selected := mItem;
  end;
end;

class function TAtlasDebugVariablesFrame.ValueText(ANode: TAtlasEvalNode): string;
begin
  Result := '';
  if (ANode <> nil) and (ANode.State = TAtlasEvalState.Value) then
  begin
    Result := ANode.Value;
  end;
end;

procedure TAtlasDebugVariablesFrame.TabClick(Sender: TObject);
begin
  if not (Sender is TSpeedButton) then
  begin
    Exit;
  end;
  SetTab(TAtlasVariablesTab(TSpeedButton(Sender).Tag));
  if Assigned(FHooks.Tab) then
  begin
    FHooks.Tab(FTab);
  end;
end;

procedure TAtlasDebugVariablesFrame.SearchChange(Sender: TObject);
begin
  // Neu anstoßen: Die Suche startet erst, wenn eine Weile nichts mehr kommt.
  FParts.SearchTimer.Enabled := False;
  FParts.SearchTimer.Enabled := True;
end;

procedure TAtlasDebugVariablesFrame.SearchTimer(Sender: TObject);
var
  mMode: TAtlasVariableSearchMode;
begin
  FParts.SearchTimer.Enabled := False;
  mMode := TAtlasVariableSearchMode.Name;
  if FParts.ValuesCheck.Checked then
  begin
    mMode := TAtlasVariableSearchMode.Value;
  end;
  if Assigned(FHooks.Search) then
  begin
    FHooks.Search(Trim(FParts.SearchEdit.Text), mMode, FParts.DeepCheck.Checked);
  end;
end;

procedure TAtlasDebugVariablesFrame.SearchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_RETURN) and (Shift = []) then
  begin
    Key := 0;
    SearchTimer(Sender);
  end
  else if (Key = VK_ESCAPE) and (Shift = []) and (FParts.SearchEdit.Text <> '') then
  begin
    Key := 0;
    FParts.SearchEdit.Text := '';
  end;
end;

procedure TAtlasDebugVariablesFrame.WatchKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mText: string;
begin
  if (Key <> VK_RETURN) or (Shift <> []) then
  begin
    Exit;
  end;
  Key := 0;
  mText := Trim(FParts.WatchEdit.Text);
  if (mText <> '') and Assigned(FHooks.AddWatch) then
  begin
    FParts.WatchEdit.Text := '';
    FHooks.AddWatch(mText);
  end;
end;

procedure TAtlasDebugVariablesFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  mAction: TRowAction;
begin
  if (Key = Ord('F')) and (Shift = [ssCtrl]) then
  begin
    Key := 0;
    FocusSearch;
    Exit;
  end;
  mAction := KeyAction(Key, Shift);
  if mAction <> TRowAction.None then
  begin
    Key := 0;
    RunRow(Self, Selected, mAction);
  end;
end;

procedure TAtlasDebugVariablesFrame.TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
var
  mNode: TAtlasEvalNode;
begin
  AllowExpansion := True;
  mNode := NodeOf(Self, Node);
  if FFilling or (mNode = nil) then
  begin
    Exit;
  end;
  mNode.Expanded := True;
  if not mNode.ChildrenLoaded and Assigned(FHooks.Expand) then
  begin
    // Felder kommen später; Hooks.Expand darf Refresh nicht sofort rufen (Benachrichtigung des Baums).
    AllowExpansion := False;
    FHooks.Expand(mNode);
  end;
end;

procedure TAtlasDebugVariablesFrame.TreeCollapsing(Sender: TObject; Node: TTreeNode; var AllowCollapse: Boolean);
var
  mNode: TAtlasEvalNode;
begin
  AllowCollapse := True;
  mNode := NodeOf(Self, Node);
  if not FFilling and (mNode <> nil) then
  begin
    mNode.Expanded := False;
  end;
end;

procedure TAtlasDebugVariablesFrame.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mInfo: TAtlasEvalItemInfo;
  mCanvas: TCanvas;
begin
  DefaultDraw := True;
  mCanvas := Sender.Canvas;
  mInfo := FSync.InfoOf(Node);
  mCanvas.Font.Style := [];
  if mInfo.Bold then
  begin
    mCanvas.Font.Style := [fsBold];
  end;
  if cdsSelected in State then
  begin
    mCanvas.Brush.Color := TreeColor(Self, clHighlight);
    mCanvas.Font.Color := TreeColor(Self, clHighlightText);
    Exit;
  end;
  mCanvas.Brush.Color := TreeColor(Self, FParts.Tree.Color);
  case mInfo.Look of
    TAtlasEvalLook.Changed:
      mCanvas.Font.Color := ColorToRGB(TColor(TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(
        mCanvas.Brush.Color))).Warn));
    TAtlasEvalLook.Gray:
      mCanvas.Font.Color := TreeColor(Self, clGrayText);
  else
    mCanvas.Font.Color := TreeColor(Self, FParts.Tree.Font.Color);
  end;
end;

procedure TAtlasDebugVariablesFrame.MenuPopup(Sender: TObject);
var
  mNode: TAtlasEvalNode;
  mIndex: Integer;
  mItem: TMenuItem;
begin
  mNode := Selected;
  for mIndex := 0 to FParts.Menu.Items.Count - 1 do
  begin
    mItem := FParts.Menu.Items[mIndex];
    mItem.Enabled := RowEnabled(Self, mNode, TRowAction(mItem.Tag));
  end;
end;

procedure TAtlasDebugVariablesFrame.MenuClick(Sender: TObject);
begin
  if Sender is TMenuItem then
  begin
    RunRow(Self, Selected, TRowAction(TMenuItem(Sender).Tag));
  end;
end;

end.
