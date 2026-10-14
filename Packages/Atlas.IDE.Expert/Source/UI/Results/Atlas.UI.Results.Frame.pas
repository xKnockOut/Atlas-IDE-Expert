unit Atlas.UI.Results.Frame;

// Inhalt des Ergebnisfensters (#400), reine VCL: oben eine Titelzeile, darunter
// ein Baum. Fundstellen (Referenzen, Implementierungen) stehen nach Unit
// gruppiert, je Zeile „Zeile: Text“; Hierarchien (Aufrufer, Aufrufe,
// Vorfahren, Nachfahren) laden ihre nächste Ebene erst beim Aufklappen über
// OnExpand. Doppelklick oder Enter springt über OnOpen zur Stelle. Die Liste
// „Atlas-Änderungen“ (#721) zeigt die Sätze des Änderungsprotokolls mit ihren
// Dateien; Doppelklick oder Enter zeigt den Unterschied (OnChangeDiff), das
// Kontextmenü nimmt einen Satz zurück oder stellt ihn wieder her. Die DFM
// ist leer, weil TCustomFrame.Create für abgeleitete Frames eine Ressource
// verlangt; aufgebaut wird im Code. Die IDE-Schicht bettet den Frame in ein
// andockbares Fenster ein. Vor dem Titel steht das Atlas-Symbol (#751).

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Atlas.Core.Results.Model,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol,
  Atlas.Core.Undo.Contract;

type
  TAtlasResultsOpen = reference to procedure(const AFileName: string; ALine, ACharacter: Integer);
  TAtlasHierarchyExpand = reference to function(ADirection: TAtlasHierarchyDirection;
    const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
  /// <summary>Satz (#721) zurücknehmen bzw. wiederherstellen.</summary>
  TAtlasChangeSetAction = reference to procedure(ASetId: Integer);
  /// <summary>Unterschied eines Satzes zeigen; AFileName = '' für alle Dateien.</summary>
  TAtlasChangeDiff = reference to procedure(ASetId: Integer; const AFileName: string);

  TAtlasResultsFrame = class(TFrame)
  private type
{$SCOPEDENUMS ON}
    TNodeKind = (Group, Entry, Hierarchy, Placeholder, ChangeSet, ChangeFile);
{$SCOPEDENUMS OFF}
    TNodeData = record
      Kind: TNodeKind;
      FileName: string;
      Line: Integer;
      Character: Integer;
      Item: TAtlasHierarchyItem;
      Loaded: Boolean;
      /// <summary>Kennung des Satzes (#721) und sein Zustand.</summary>
      SetId: Integer;
      State: TAtlasChangeSetState;
    end;
  private
    FTitle: TLabel;
    FSymbol: TAtlasSymbolImage;
    FTree: TTreeView;
    FData: TList<TNodeData>;
    FDirection: TAtlasHierarchyDirection;
    FOnOpen: TAtlasResultsOpen;
    FOnExpand: TAtlasHierarchyExpand;
    FMenu: TPopupMenu;
    FUndoItem: TMenuItem;
    FRedoItem: TMenuItem;
    FDiffItem: TMenuItem;
    FShowsChanges: Boolean;
    FOnChangeUndo: TAtlasChangeSetAction;
    FOnChangeRedo: TAtlasChangeSetAction;
    FOnChangeDiff: TAtlasChangeDiff;
    function AddNode(AParent: TTreeNode; const AText: string; const AData: TNodeData): TTreeNode;
    function DataOf(ANode: TTreeNode): TNodeData;
    procedure AddHierarchy(AParent: TTreeNode; const AItems: TArray<TAtlasHierarchyItem>);
    procedure Clear(const ATitle: string);
    procedure OpenSelected;
    procedure TreeDblClick(Sender: TObject);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
    function SelectedSet: TNodeData;
    procedure MenuPopup(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure DiffClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Fundstellen nach Unit gruppiert; alle Gruppen aufgeklappt.</summary>
    procedure ShowEntries(const ATitle: string; const AGroups: TArray<TAtlasResultGroup>);
    /// <summary>Wurzeln einer Hierarchie; die erste Ebene wird gleich geladen.</summary>
    procedure ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
      const ARoots: TArray<TAtlasHierarchyItem>);
    /// <summary>Liste „Atlas-Änderungen“ (#721): neueste Sätze zuerst, je Satz seine Dateien (zugeklappt).
    /// AKeepSelection: den bisher gewählten Satz wieder wählen (nach Zurücknehmen).</summary>
    procedure ShowChanges(const ATitle: string; const ASets: TArray<TAtlasChangeSet>; ANow: TDateTime;
      AKeepSelection: Boolean);
    /// <summary>Unterschied, Zurücknehmen und Wiederherstellen für den gewählten Satz
    /// bzw. die gewählte Datei.</summary>
    procedure ShowSelectedDiff;
    procedure UndoSelected;
    procedure RedoSelected;
    /// <summary>Text einer Fundstelle: "12: Kunde.Laden;" bzw. mit Vorschau "alt  →  neu".</summary>
    class function EntryText(const AEntry: TAtlasResultEntry): string; static;
    /// <summary>Text eines Hierarchie-Eintrags: "Laden · TKunde  (Kunden.pas:12)".</summary>
    class function HierarchyText(const AItem: TAtlasHierarchyItem): string; static;
    property Tree: TTreeView read FTree;
    property OnOpen: TAtlasResultsOpen read FOnOpen write FOnOpen;
    property OnExpand: TAtlasHierarchyExpand read FOnExpand write FOnExpand;
    property Menu: TPopupMenu read FMenu;
    property Symbol: TAtlasSymbolImage read FSymbol;
    /// <summary>Zeigt gerade die Liste „Atlas-Änderungen“.</summary>
    property ShowsChanges: Boolean read FShowsChanges;
    property OnChangeUndo: TAtlasChangeSetAction read FOnChangeUndo write FOnChangeUndo;
    property OnChangeRedo: TAtlasChangeSetAction read FOnChangeRedo write FOnChangeRedo;
    property OnChangeDiff: TAtlasChangeDiff read FOnChangeDiff write FOnChangeDiff;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.UI.Strings,
  Atlas.UI.Undo.Messages;

{$R *.dfm}

{ TAtlasResultsFrame }

constructor TAtlasResultsFrame.Create(AOwner: TComponent);
var
  Header: TPanel;
begin
  inherited Create(AOwner);
  FData := TList<TNodeData>.Create;
  // Titelzeile: Symbol (#751) und Titel.
  Header := TPanel.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.BevelOuter := bvNone;
  Header.ParentBackground := True;
  Header.Height := 22;
  FSymbol := TAtlasSymbolImage.Create(Self);
  FSymbol.Parent := Header;
  FSymbol.LogicalSize := TAtlasSymbol.MenuSize;
  FSymbol.Align := alLeft;
  FSymbol.AlignWithMargins := True;
  FTitle := TLabel.Create(Self);
  FTitle.Parent := Header;
  FTitle.Align := alClient;
  FTitle.Layout := tlCenter;
  FTitle.AlignWithMargins := True;
  FTitle.ShowAccelChar := False;
  FTitle.EllipsisPosition := epEndEllipsis;
  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.RowSelect := True;
  FTree.ShowLines := False;
  FTree.BorderStyle := bsNone;
  FTree.OnDblClick := TreeDblClick;
  FTree.OnKeyDown := TreeKeyDown;
  FTree.OnExpanding := TreeExpanding;
  // Kontextmenü der Liste „Atlas-Änderungen“ (#721); in anderen Listen ohne Einträge.
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FUndoItem := TMenuItem.Create(FMenu);
  FUndoItem.Caption := TAtlasStrings.Text(TAtlasTextId.UndoActionUndo);
  FUndoItem.OnClick := UndoClick;
  FMenu.Items.Add(FUndoItem);
  FRedoItem := TMenuItem.Create(FMenu);
  FRedoItem.Caption := TAtlasStrings.Text(TAtlasTextId.UndoActionRedo);
  FRedoItem.OnClick := RedoClick;
  FMenu.Items.Add(FRedoItem);
  FDiffItem := TMenuItem.Create(FMenu);
  FDiffItem.Caption := TAtlasStrings.Text(TAtlasTextId.UndoActionDiff);
  FDiffItem.OnClick := DiffClick;
  FMenu.Items.Add(FDiffItem);
  FTree.PopupMenu := FMenu;
end;

destructor TAtlasResultsFrame.Destroy;
begin
  FData.Free;
  inherited;
end;

class function TAtlasResultsFrame.EntryText(const AEntry: TAtlasResultEntry): string;
begin
  Result := Format('%d: %s', [AEntry.Line + 1, AEntry.Text]);
  if AEntry.Detail <> '' then
    Result := Result + '  →  ' + AEntry.Detail;
end;

class function TAtlasResultsFrame.HierarchyText(const AItem: TAtlasHierarchyItem): string;
begin
  Result := AItem.Name;
  if AItem.Detail <> '' then
    Result := Result + ' · ' + AItem.Detail;
  if AItem.FileName <> '' then
    Result := Result + Format('  (%s:%d)', [ExtractFileName(AItem.FileName), AItem.Line + 1]);
end;

function TAtlasResultsFrame.AddNode(AParent: TTreeNode; const AText: string; const AData: TNodeData): TTreeNode;
begin
  Result := FTree.Items.AddChild(AParent, AText);
  // Index in FData; 0 wäre nil, deshalb um eins verschoben.
  Result.Data := Pointer(NativeInt(FData.Add(AData) + 1));
end;

function TAtlasResultsFrame.DataOf(ANode: TTreeNode): TNodeData;
var
  Index: NativeInt;
begin
  Result := Default(TNodeData);
  Result.Kind := TNodeKind.Placeholder;
  if ANode = nil then
    Exit;
  Index := NativeInt(ANode.Data) - 1;
  if (Index >= 0) and (Index < FData.Count) then
    Result := FData[Integer(Index)];
end;

procedure TAtlasResultsFrame.Clear(const ATitle: string);
begin
  FShowsChanges := False;
  FTitle.Caption := ATitle;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
  finally
    FTree.Items.EndUpdate;
  end;
  FData.Clear;
end;

procedure TAtlasResultsFrame.ShowEntries(const ATitle: string; const AGroups: TArray<TAtlasResultGroup>);
var
  Group: TAtlasResultGroup;
  Entry: TAtlasResultEntry;
  Data: TNodeData;
  GroupNode: TTreeNode;
begin
  Clear(ATitle);
  FTree.Items.BeginUpdate;
  try
    for Group in AGroups do
    begin
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.Group;
      Data.FileName := Group.FileName;
      GroupNode := AddNode(nil, Group.Caption, Data);
      for Entry in Group.Entries do
      begin
        Data := Default(TNodeData);
        Data.Kind := TNodeKind.Entry;
        Data.FileName := Entry.FileName;
        Data.Line := Entry.Line;
        Data.Character := Entry.Character;
        AddNode(GroupNode, EntryText(Entry), Data);
      end;
      GroupNode.Expand(False);
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
    FTree.Selected := FTree.Items[0];
end;

procedure TAtlasResultsFrame.AddHierarchy(AParent: TTreeNode; const AItems: TArray<TAtlasHierarchyItem>);
var
  Item: TAtlasHierarchyItem;
  Data: TNodeData;
  Node: TTreeNode;
begin
  for Item in AItems do
  begin
    Data := Default(TNodeData);
    Data.Kind := TNodeKind.Hierarchy;
    Data.FileName := Item.FileName;
    Data.Line := Item.Line;
    Data.Character := Item.Character;
    Data.Item := Item;
    Node := AddNode(AParent, HierarchyText(Item), Data);
    // Platzhalter, damit sich der Knoten aufklappen lässt; geladen wird erst dann.
    Data := Default(TNodeData);
    Data.Kind := TNodeKind.Placeholder;
    AddNode(Node, '…', Data);
  end;
end;

procedure TAtlasResultsFrame.ShowHierarchy(const ATitle: string; ADirection: TAtlasHierarchyDirection;
  const ARoots: TArray<TAtlasHierarchyItem>);
begin
  Clear(ATitle);
  FDirection := ADirection;
  FTree.Items.BeginUpdate;
  try
    AddHierarchy(nil, ARoots);
  finally
    FTree.Items.EndUpdate;
  end;
  if FTree.Items.Count > 0 then
  begin
    FTree.Selected := FTree.Items[0];
    FTree.Items[0].Expand(False);
  end;
end;

procedure TAtlasResultsFrame.TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
var
  Index: NativeInt;
  Data: TNodeData;
  Children: TArray<TAtlasHierarchyItem>;
begin
  Data := DataOf(Node);
  if (Data.Kind <> TNodeKind.Hierarchy) or Data.Loaded then
    Exit;
  Index := NativeInt(Node.Data) - 1;
  Data.Loaded := True;
  FData[Integer(Index)] := Data;
  Children := nil;
  if Assigned(FOnExpand) then
  begin
    Screen.Cursor := crHourGlass;
    try
      Children := FOnExpand(FDirection, Data.Item);
    finally
      Screen.Cursor := crDefault;
    end;
  end;
  FTree.Items.BeginUpdate;
  try
    Node.DeleteChildren;
    AddHierarchy(Node, Children);
  finally
    FTree.Items.EndUpdate;
  end;
  AllowExpansion := Node.HasChildren;
end;

procedure TAtlasResultsFrame.ShowChanges(const ATitle: string; const ASets: TArray<TAtlasChangeSet>; ANow: TDateTime;
  AKeepSelection: Boolean);
var
  ChangeSet: TAtlasChangeSet;
  Change: TAtlasFileChange;
  Data: TNodeData;
  SetNode, Selected: TTreeNode;
  PreviousId: Integer;
begin
  PreviousId := 0;
  if AKeepSelection and FShowsChanges then
    PreviousId := SelectedSet.SetId;
  Clear(ATitle);
  FShowsChanges := True;
  Selected := nil;
  FTree.Items.BeginUpdate;
  try
    for ChangeSet in ASets do
    begin
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.ChangeSet;
      Data.SetId := ChangeSet.Id;
      Data.State := ChangeSet.State;
      SetNode := AddNode(nil, TAtlasUndoMessages.SetCaption(ChangeSet, ANow), Data);
      if ChangeSet.Id = PreviousId then
        Selected := SetNode;
      for Change in ChangeSet.Files do
      begin
        Data.Kind := TNodeKind.ChangeFile;
        Data.FileName := Change.FileName;
        AddNode(SetNode, TAtlasUndoMessages.FileCaption(Change), Data);
      end;
    end;
  finally
    FTree.Items.EndUpdate;
  end;
  if Selected <> nil then
    FTree.Selected := Selected
  else if FTree.Items.Count > 0 then
    FTree.Selected := FTree.Items[0];
end;

function TAtlasResultsFrame.SelectedSet: TNodeData;
begin
  Result := DataOf(FTree.Selected);
  if not (Result.Kind in [TNodeKind.ChangeSet, TNodeKind.ChangeFile]) then
    Result := Default(TNodeData);
end;

procedure TAtlasResultsFrame.MenuPopup(Sender: TObject);
var
  Data: TNodeData;
begin
  Data := SelectedSet;
  FUndoItem.Visible := FShowsChanges;
  FRedoItem.Visible := FShowsChanges;
  FDiffItem.Visible := FShowsChanges;
  FUndoItem.Enabled := (Data.SetId > 0) and (Data.State <> TAtlasChangeSetState.Undone);
  FRedoItem.Enabled := (Data.SetId > 0) and (Data.State <> TAtlasChangeSetState.Applied);
  FDiffItem.Enabled := Data.SetId > 0;
end;

procedure TAtlasResultsFrame.ShowSelectedDiff;
var
  Data: TNodeData;
begin
  Data := SelectedSet;
  if (Data.SetId > 0) and Assigned(FOnChangeDiff) then
    FOnChangeDiff(Data.SetId, Data.FileName);
end;

procedure TAtlasResultsFrame.UndoSelected;
var
  Data: TNodeData;
begin
  Data := SelectedSet;
  if (Data.SetId > 0) and Assigned(FOnChangeUndo) then
    FOnChangeUndo(Data.SetId);
end;

procedure TAtlasResultsFrame.RedoSelected;
var
  Data: TNodeData;
begin
  Data := SelectedSet;
  if (Data.SetId > 0) and Assigned(FOnChangeRedo) then
    FOnChangeRedo(Data.SetId);
end;

procedure TAtlasResultsFrame.UndoClick(Sender: TObject);
begin
  UndoSelected;
end;

procedure TAtlasResultsFrame.RedoClick(Sender: TObject);
begin
  RedoSelected;
end;

procedure TAtlasResultsFrame.DiffClick(Sender: TObject);
begin
  ShowSelectedDiff;
end;

procedure TAtlasResultsFrame.OpenSelected;
var
  Data: TNodeData;
begin
  Data := DataOf(FTree.Selected);
  // Atlas-Änderungen (#721): Doppelklick zeigt den Unterschied.
  if Data.Kind in [TNodeKind.ChangeSet, TNodeKind.ChangeFile] then
  begin
    ShowSelectedDiff;
    Exit;
  end;
  if (Data.Kind in [TNodeKind.Entry, TNodeKind.Hierarchy]) and (Data.FileName <> '') and Assigned(FOnOpen) then
    FOnOpen(Data.FileName, Data.Line, Data.Character);
end;

procedure TAtlasResultsFrame.TreeDblClick(Sender: TObject);
begin
  OpenSelected;
end;

procedure TAtlasResultsFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    OpenSelected;
    Key := 0;
  end;
end;

end.
