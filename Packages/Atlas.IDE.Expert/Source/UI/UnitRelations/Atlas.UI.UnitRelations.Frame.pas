unit Atlas.UI.UnitRelations.Frame;

// Inhalt des Fensters „Unit-Beziehungen“ (#593), reine VCL, aufgebaut im Code
// wie das Ergebnisfenster (#400; die DFM ist leer):
// - Titelzeile mit Atlas-Symbol (#751) und Unit-Name, darunter eine Zeile mit
//   den Kosten („N Units neu übersetzen“) und dem Zyklus der Unit.
// - Leiste mit Filterfeld und dem Umschalter „direkt“ / „alle Ebenen“
//   (OnDepthChanged; der Dienst fragt dann den Server neu).
// - Baum mit „Verwendet (n)“ und „Wird verwendet von (n)“; je Eintrag intf
//   bzw. impl, Zyklen rot mit „Zyklus“ (Rundweg im Hinweis unter der Maus),
//   ungenutzte Einträge und Bibliotheks-Units (RTL, VCL) abgeblendet, die
//   Bibliothek in einer eingeklappten Gruppe. Mit „alle Ebenen“ hängen die
//   weiteren Ebenen darunter; eine Unit, die weiter oben schon aufgeklappt
//   ist, trägt „siehe oben“.
// - Doppelklick oder Enter öffnet die Unit, Strg+Doppelklick bzw. Strg+Enter
//   springt zum uses-Eintrag (bei „Verwendet“ in der Unit selbst, bei „Wird
//   verwendet von“ in der verwendenden Unit), beides über OnOpen.
// - Kontextmenü auf den direkten Einträgen von „Verwendet“: „In
//   implementation verschieben“ bzw. „In interface verschieben“ (OnMove),
//   „Eintrag entfernen“ nur bei ungenutzten (OnRemove); „Pfad kopieren“ bei
//   allen Einträgen mit Datei.
// - Neue Daten (SetRelations) behalten aufgeklappte Knoten und die Auswahl,
//   solange es dieselbe Unit ist: Der Dienst fragt im Hintergrund regelmäßig
//   nach.

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
  Atlas.Core.UnitRelations.Model,
  Atlas.UI.Style.Symbol;

type
  /// <summary>Datei öffnen; ALine = -1: nur die Unit, sonst die Stelle (0-basiert).</summary>
  TAtlasUnitRelationsOpen = reference to procedure(const AFileName: string; ALine, ACharacter: Integer);
  TAtlasUnitRelationsMove = reference to procedure(const AUnit: string; AToInterface: Boolean);
  TAtlasUnitRelationsRemove = reference to procedure(const AUnit: string);

  TAtlasUnitRelationsFrame = class(TFrame)
  private type
{$SCOPEDENUMS ON}
    TNodeKind = (Section, LibraryGroup, Entry);
{$SCOPEDENUMS OFF}
    TNodeData = record
      Kind: TNodeKind;
      Relation: TAtlasUnitRelation;
      /// <summary>Unter „Verwendet“ (sonst „Wird verwendet von“).</summary>
      UsesSide: Boolean;
      /// <summary>Direkter Eintrag der Unit (nicht in einer tieferen Ebene).</summary>
      TopLevel: Boolean;
      /// <summary>Weg von der Wurzel, um Aufklappen und Auswahl nach neuen Daten wiederzufinden.</summary>
      Key: string;
    end;
  private
    FSymbol: TAtlasSymbolImage;
    FTitle: TLabel;
    FInfo: TLabel;
    FFilter: TEdit;
    FDirect: TRadioButton;
    FAllLevels: TRadioButton;
    FTree: TTreeView;
    FData: TList<TNodeData>;
    FMenu: TPopupMenu;
    FMoveImplementationItem: TMenuItem;
    FMoveInterfaceItem: TMenuItem;
    FRemoveItem: TMenuItem;
    FCopyPathItem: TMenuItem;
    FRelations: TAtlasUnitRelations;
    FHasRelations: Boolean;
    FRenderedFile: string;
    FHintNode: TTreeNode;
    FUpdatingDepth: Boolean;
    FOnOpen: TAtlasUnitRelationsOpen;
    FOnMove: TAtlasUnitRelationsMove;
    FOnRemove: TAtlasUnitRelationsRemove;
    FOnDepthChanged: TProc<Boolean>;
    function DataOf(ANode: TTreeNode): TNodeData;
    function AddNode(AParent: TTreeNode; const AText: string; const AData: TNodeData): TTreeNode;
    procedure AddEntries(AParent: TTreeNode; const AItems: TAtlasUnitRelationList; AUsesSide, ATopLevel: Boolean;
      const AKey: string);
    function EntryText(const ARelation: TAtlasUnitRelation): string;
    procedure Render;
    procedure SaveState(AExpanded: TDictionary<string, Boolean>; out ASelected: string);
    procedure RestoreState(AExpanded: TDictionary<string, Boolean>; const ASelected: string);
    procedure FilterChange(Sender: TObject);
    procedure DepthClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure MenuPopup(Sender: TObject);
    procedure MoveImplementationClick(Sender: TObject);
    procedure MoveInterfaceClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure CopyPathClick(Sender: TObject);
    function GetAllLevels: Boolean;
    procedure SetAllLevels(AValue: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Neue Daten; bei derselben Unit bleiben Aufklappen und Auswahl.</summary>
    procedure SetRelations(const ARelations: TAtlasUnitRelations);
    /// <summary>Meldung statt Daten (keine Datei, kein Server, Fehler).</summary>
    procedure SetMessage(const AText: string);
    /// <summary>Wie Doppelklick (AToEntry = Strg gedrückt) auf ANode.</summary>
    procedure OpenNode(ANode: TTreeNode; AToEntry: Boolean);
    /// <summary>Kontextmenü für die Auswahl vorbereiten (OnPopup).</summary>
    procedure UpdateMenu;
    /// <summary>Eintrag hinter ANode; False bei Abschnitten und Gruppen.</summary>
    function EntryOf(ANode: TTreeNode; out ARelation: TAtlasUnitRelation): Boolean;
    /// <summary>Knoten des Eintrags AName unter „Verwendet“ (AUsesSide) bzw. „Wird verwendet von“; nil ohne.</summary>
    function FindEntry(const AName: string; AUsesSide: Boolean): TTreeNode;
    /// <summary>Hinweis unter der Maus für ANode: Rundweg bei Zyklen, sonst die Datei.</summary>
    function HintOf(ANode: TTreeNode): string;
    function IsLibraryGroup(ANode: TTreeNode): Boolean;
    property Relations: TAtlasUnitRelations read FRelations;
    property HasRelations: Boolean read FHasRelations;
    property AllLevels: Boolean read GetAllLevels write SetAllLevels;
    property Tree: TTreeView read FTree;
    property Filter: TEdit read FFilter;
    property Title: TLabel read FTitle;
    property Info: TLabel read FInfo;
    property DirectButton: TRadioButton read FDirect;
    property AllLevelsButton: TRadioButton read FAllLevels;
    property MoveImplementationItem: TMenuItem read FMoveImplementationItem;
    property MoveInterfaceItem: TMenuItem read FMoveInterfaceItem;
    property RemoveItem: TMenuItem read FRemoveItem;
    property CopyPathItem: TMenuItem read FCopyPathItem;
    property OnOpen: TAtlasUnitRelationsOpen read FOnOpen write FOnOpen;
    property OnMove: TAtlasUnitRelationsMove read FOnMove write FOnMove;
    property OnRemove: TAtlasUnitRelationsRemove read FOnRemove write FOnRemove;
    /// <summary>Umschalter „direkt“ / „alle Ebenen“ betätigt; True = alle Ebenen.</summary>
    property OnDepthChanged: TProc<Boolean> read FOnDepthChanged write FOnDepthChanged;
  end;

implementation

uses
  Winapi.Windows,
  Vcl.Clipbrd,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Strings;

{$R *.dfm}

{ TAtlasUnitRelationsFrame }

constructor TAtlasUnitRelationsFrame.Create(AOwner: TComponent);
var
  Header, Bar: TPanel;
begin
  inherited Create(AOwner);
  FData := TList<TNodeData>.Create;
  // Titelzeile: Symbol (#751) und Unit.
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
  FTitle.Font.Style := [fsBold];
  // Kosten und Zyklus der Unit.
  FInfo := TLabel.Create(Self);
  FInfo.Parent := Self;
  FInfo.Align := alTop;
  FInfo.Top := Header.Top + Header.Height;
  FInfo.AlignWithMargins := True;
  FInfo.ShowAccelChar := False;
  FInfo.EllipsisPosition := epEndEllipsis;
  FInfo.ShowHint := True;
  // Leiste: Filter und Tiefe.
  Bar := TPanel.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Top := FInfo.Top + FInfo.Height + 1;
  Bar.BevelOuter := bvNone;
  Bar.ParentBackground := True;
  Bar.Height := 26;
  FAllLevels := TRadioButton.Create(Self);
  FAllLevels.Parent := Bar;
  FAllLevels.Align := alRight;
  FAllLevels.AlignWithMargins := True;
  FAllLevels.Width := 90;
  FAllLevels.Caption := TAtlasStrings.Text(TAtlasTextId.UnitRelationsAllLevels);
  FAllLevels.OnClick := DepthClick;
  FDirect := TRadioButton.Create(Self);
  FDirect.Parent := Bar;
  FDirect.Align := alRight;
  FDirect.AlignWithMargins := True;
  FDirect.Width := 70;
  FDirect.Caption := TAtlasStrings.Text(TAtlasTextId.UnitRelationsDirect);
  FDirect.Checked := True;
  FDirect.OnClick := DepthClick;
  FFilter := TEdit.Create(Self);
  FFilter.Parent := Bar;
  FFilter.Align := alClient;
  FFilter.AlignWithMargins := True;
  FFilter.TextHint := TAtlasStrings.Text(TAtlasTextId.UnitRelationsFilterHint);
  FFilter.OnChange := FilterChange;
  FTree := TTreeView.Create(Self);
  FTree.Parent := Self;
  FTree.Align := alClient;
  FTree.ReadOnly := True;
  FTree.HideSelection := False;
  FTree.RowSelect := True;
  FTree.ShowLines := False;
  FTree.RightClickSelect := True;
  FTree.BorderStyle := bsNone;
  FTree.OnDblClick := TreeDblClick;
  FTree.OnKeyDown := TreeKeyDown;
  FTree.OnMouseMove := TreeMouseMove;
  FTree.OnCustomDrawItem := TreeCustomDrawItem;
  FTree.ShowHint := True;
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FMoveImplementationItem := TMenuItem.Create(FMenu);
  FMoveImplementationItem.Caption := TAtlasStrings.Text(TAtlasTextId.UnitRelationsMoveImplementation);
  FMoveImplementationItem.OnClick := MoveImplementationClick;
  FMenu.Items.Add(FMoveImplementationItem);
  FMoveInterfaceItem := TMenuItem.Create(FMenu);
  FMoveInterfaceItem.Caption := TAtlasStrings.Text(TAtlasTextId.UnitRelationsMoveInterface);
  FMoveInterfaceItem.OnClick := MoveInterfaceClick;
  FMenu.Items.Add(FMoveInterfaceItem);
  FRemoveItem := TMenuItem.Create(FMenu);
  FRemoveItem.Caption := TAtlasStrings.Text(TAtlasTextId.UnitRelationsRemove);
  FRemoveItem.OnClick := RemoveClick;
  FMenu.Items.Add(FRemoveItem);
  FCopyPathItem := TMenuItem.Create(FMenu);
  FCopyPathItem.Caption := TAtlasStrings.Text(TAtlasTextId.UnitRelationsCopyPath);
  FCopyPathItem.OnClick := CopyPathClick;
  FMenu.Items.Add(FCopyPathItem);
  FTree.PopupMenu := FMenu;
end;

destructor TAtlasUnitRelationsFrame.Destroy;
begin
  FData.Free;
  inherited Destroy;
end;

function TAtlasUnitRelationsFrame.GetAllLevels: Boolean;
begin
  Result := FAllLevels.Checked;
end;

procedure TAtlasUnitRelationsFrame.SetAllLevels(AValue: Boolean);
begin
  // Von außen gesetzt: kein OnDepthChanged.
  FUpdatingDepth := True;
  try
    FAllLevels.Checked := AValue;
    FDirect.Checked := not AValue;
  finally
    FUpdatingDepth := False;
  end;
end;

function TAtlasUnitRelationsFrame.DataOf(ANode: TTreeNode): TNodeData;
var
  Index: Integer;
begin
  Result := Default(TNodeData);
  if ANode = nil then
    Exit;
  Index := Integer(NativeInt(ANode.Data));
  if (Index >= 0) and (Index < FData.Count) then
    Result := FData[Index];
end;

function TAtlasUnitRelationsFrame.AddNode(AParent: TTreeNode; const AText: string;
  const AData: TNodeData): TTreeNode;
begin
  Result := FTree.Items.AddChildObject(AParent, AText, Pointer(NativeInt(FData.Count)));
  FData.Add(AData);
end;

function TAtlasUnitRelationsFrame.EntryText(const ARelation: TAtlasUnitRelation): string;
begin
  Result := ARelation.Name + '  ';
  if ARelation.InInterface then
    Result := Result + TAtlasStrings.Text(TAtlasTextId.UnitRelationsInterface)
  else
    Result := Result + TAtlasStrings.Text(TAtlasTextId.UnitRelationsImplementation);
  if ARelation.Cycle then
    Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.UnitRelationsCycle);
  if ARelation.Unused then
    Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.UnitRelationsUnused);
  if ARelation.Repeated then
    Result := Result + ' · ' + TAtlasStrings.Text(TAtlasTextId.UnitRelationsRepeated);
end;

procedure TAtlasUnitRelationsFrame.AddEntries(AParent: TTreeNode; const AItems: TAtlasUnitRelationList;
  AUsesSide, ATopLevel: Boolean; const AKey: string);
var
  Item: TAtlasUnitRelation;
  Data: TNodeData;
  Node: TTreeNode;
begin
  for Item in AItems do
  begin
    Data := Default(TNodeData);
    Data.Kind := TNodeKind.Entry;
    Data.Relation := Item;
    Data.UsesSide := AUsesSide;
    Data.TopLevel := ATopLevel;
    Data.Key := AKey + '/' + LowerCase(Item.Name);
    Node := AddNode(AParent, EntryText(Item), Data);
    AddEntries(Node, Item.Children, AUsesSide, False, Data.Key);
  end;
end;

procedure TAtlasUnitRelationsFrame.SaveState(AExpanded: TDictionary<string, Boolean>; out ASelected: string);
var
  Node: TTreeNode;
begin
  ASelected := '';
  Node := FTree.Items.GetFirstNode;
  while Node <> nil do
  begin
    if Node.HasChildren then
      AExpanded.AddOrSetValue(DataOf(Node).Key, Node.Expanded);
    Node := Node.GetNext;
  end;
  if FTree.Selected <> nil then
    ASelected := DataOf(FTree.Selected).Key;
end;

procedure TAtlasUnitRelationsFrame.RestoreState(AExpanded: TDictionary<string, Boolean>; const ASelected: string);
var
  Node: TTreeNode;
  Data: TNodeData;
  Expanded: Boolean;
begin
  Node := FTree.Items.GetFirstNode;
  while Node <> nil do
  begin
    Data := DataOf(Node);
    if Node.HasChildren then
    begin
      // Unbekannte Knoten: Abschnitte offen, Bibliothek und tiefere Ebenen zu; mit Filter alles offen.
      if not AExpanded.TryGetValue(Data.Key, Expanded) then
        Expanded := (Data.Kind = TNodeKind.Section) or (Trim(FFilter.Text) <> '');
      Node.Expanded := Expanded;
    end;
    if (ASelected <> '') and (Data.Key = ASelected) then
      FTree.Selected := Node;
    Node := Node.GetNext;
  end;
end;

procedure TAtlasUnitRelationsFrame.Render;
var
  Expanded: TDictionary<string, Boolean>;
  Selected, Line: string;
  Data: TNodeData;
  Section, Group: TTreeNode;
  Uses_, Project, Library_, UsedBy: TAtlasUnitRelationList;
begin
  Expanded := TDictionary<string, Boolean>.Create;
  try
    Selected := '';
    // Andere Unit oder neuer Filter: Vorgaben statt des alten Zustands.
    if SameText(FRenderedFile, FRelations.FileName) then
      SaveState(Expanded, Selected);
    FRenderedFile := FRelations.FileName;
    FHintNode := nil;
    FTree.Items.BeginUpdate;
    try
      FTree.Items.Clear;
      FData.Clear;
      FTitle.Caption := FRelations.UnitName;
      if not FRelations.Found then
        Line := TAtlasStrings.Text(TAtlasTextId.UnitRelationsNotInGraph)
      else if FRelations.RecompileCount = 1 then
        Line := TAtlasStrings.Text(TAtlasTextId.UnitRelationsRecompileOne)
      else
        Line := TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsRecompile, [FRelations.RecompileCount]);
      if FRelations.InCycle then
        Line := Line + ' · ' + TAtlasStrings.Text(TAtlasTextId.UnitRelationsCycle);
      FInfo.Caption := Line;
      FInfo.Hint := FRelations.CyclePath;
      if FRelations.InCycle then
        FInfo.Font.Color := TColor(TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(
          StyleServices(Self).GetSystemColor(clWindow)))).Error)
      else
        FInfo.ParentFont := True;
      Uses_ := TAtlasUnitRelationsModel.Filter(FRelations.Uses_, FFilter.Text);
      TAtlasUnitRelationsModel.SplitLibrary(Uses_, Project, Library_);
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.Section;
      Data.UsesSide := True;
      Data.Key := 'uses';
      Section := AddNode(nil, TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsUses, [Length(Uses_)]), Data);
      AddEntries(Section, Project, True, True, Data.Key);
      if Library_ <> nil then
      begin
        Data.Kind := TNodeKind.LibraryGroup;
        Data.Key := 'uses/#library';
        Group := AddNode(Section, TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsLibrary, [Length(Library_)]), Data);
        AddEntries(Group, Library_, True, True, Data.Key);
      end;
      UsedBy := TAtlasUnitRelationsModel.Filter(FRelations.UsedBy, FFilter.Text);
      Data := Default(TNodeData);
      Data.Kind := TNodeKind.Section;
      Data.Key := 'usedBy';
      Section := AddNode(nil, TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsUsedBy, [Length(UsedBy)]), Data);
      AddEntries(Section, UsedBy, False, True, Data.Key);
      RestoreState(Expanded, Selected);
    finally
      FTree.Items.EndUpdate;
    end;
  finally
    Expanded.Free;
  end;
end;

procedure TAtlasUnitRelationsFrame.SetRelations(const ARelations: TAtlasUnitRelations);
begin
  if not SameText(ARelations.FileName, FRelations.FileName) then
    FRenderedFile := '';
  FRelations := ARelations;
  FHasRelations := True;
  SetAllLevels(ARelations.Depth <> 1);
  Render;
end;

procedure TAtlasUnitRelationsFrame.SetMessage(const AText: string);
begin
  FHasRelations := False;
  FRelations := Default(TAtlasUnitRelations);
  FRenderedFile := '';
  FHintNode := nil;
  FTitle.Caption := '';
  FInfo.Caption := AText;
  FInfo.Hint := '';
  FInfo.ParentFont := True;
  FTree.Items.BeginUpdate;
  try
    FTree.Items.Clear;
    FData.Clear;
  finally
    FTree.Items.EndUpdate;
  end;
end;

function TAtlasUnitRelationsFrame.EntryOf(ANode: TTreeNode; out ARelation: TAtlasUnitRelation): Boolean;
var
  Data: TNodeData;
begin
  Data := DataOf(ANode);
  ARelation := Data.Relation;
  Result := (ANode <> nil) and (Data.Kind = TNodeKind.Entry);
end;

function TAtlasUnitRelationsFrame.IsLibraryGroup(ANode: TTreeNode): Boolean;
begin
  Result := (ANode <> nil) and (DataOf(ANode).Kind = TNodeKind.LibraryGroup);
end;

function TAtlasUnitRelationsFrame.FindEntry(const AName: string; AUsesSide: Boolean): TTreeNode;
var
  Node: TTreeNode;
  Data: TNodeData;
begin
  Node := FTree.Items.GetFirstNode;
  while Node <> nil do
  begin
    Data := DataOf(Node);
    if (Data.Kind = TNodeKind.Entry) and Data.TopLevel and (Data.UsesSide = AUsesSide) and
      SameText(Data.Relation.Name, AName) then
      Exit(Node);
    Node := Node.GetNext;
  end;
  Result := nil;
end;

function TAtlasUnitRelationsFrame.HintOf(ANode: TTreeNode): string;
var
  Relation: TAtlasUnitRelation;
begin
  Result := '';
  if not EntryOf(ANode, Relation) then
    Exit;
  if Relation.Cycle and (Relation.CyclePath <> '') then
    Result := TAtlasStrings.Fmt(TAtlasTextId.UnitRelationsCyclePath, [Relation.CyclePath])
  else
    Result := Relation.FileName;
end;

procedure TAtlasUnitRelationsFrame.OpenNode(ANode: TTreeNode; AToEntry: Boolean);
var
  Relation: TAtlasUnitRelation;
begin
  if not EntryOf(ANode, Relation) or not Assigned(FOnOpen) then
    Exit;
  if AToEntry and (Relation.LocationFile <> '') and (Relation.Line >= 0) then
    FOnOpen(Relation.LocationFile, Relation.Line, Relation.Character)
  else if Relation.FileName <> '' then
    FOnOpen(Relation.FileName, -1, -1)
  else if (Relation.LocationFile <> '') and (Relation.Line >= 0) then
    // Unit ohne Quelltext (RTL ohne Pfad): wenigstens der Eintrag.
    FOnOpen(Relation.LocationFile, Relation.Line, Relation.Character);
end;

procedure TAtlasUnitRelationsFrame.FilterChange(Sender: TObject);
begin
  if FHasRelations then
  begin
    // Neuer Filter: aufgeklappt wird nach Vorgabe (mit Filter alles).
    FRenderedFile := '';
    Render;
  end;
end;

procedure TAtlasUnitRelationsFrame.DepthClick(Sender: TObject);
begin
  if FUpdatingDepth or not (Sender as TRadioButton).Checked then
    Exit;
  if Assigned(FOnDepthChanged) then
    FOnDepthChanged(FAllLevels.Checked);
end;

procedure TAtlasUnitRelationsFrame.TreeDblClick(Sender: TObject);
begin
  OpenNode(FTree.Selected, GetKeyState(VK_CONTROL) < 0);
end;

procedure TAtlasUnitRelationsFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    OpenNode(FTree.Selected, ssCtrl in Shift);
    Key := 0;
  end;
end;

procedure TAtlasUnitRelationsFrame.TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  Node: TTreeNode;
begin
  Node := FTree.GetNodeAt(X, Y);
  if Node = FHintNode then
    Exit;
  FHintNode := Node;
  FTree.Hint := HintOf(Node);
  Application.CancelHint;
end;

procedure TAtlasUnitRelationsFrame.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  Data: TNodeData;
  Colors: TAtlasColors;
begin
  DefaultDraw := True;
  Data := DataOf(Node);
  if Data.Kind = TNodeKind.Section then
  begin
    Sender.Canvas.Font.Style := [fsBold];
    Exit;
  end;
  // Gewählte Zeile in den Farben der Auswahl lassen.
  if cdsSelected in State then
    Exit;
  Colors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices(Self).GetSystemColor(clWindow))));
  if (Data.Kind = TNodeKind.Entry) and Data.Relation.Cycle then
    Sender.Canvas.Font.Color := TColor(Colors.Error)
  else if (Data.Kind = TNodeKind.LibraryGroup) or Data.Relation.Library_ or Data.Relation.Unused then
    Sender.Canvas.Font.Color := TColor(Colors.Muted);
end;

procedure TAtlasUnitRelationsFrame.UpdateMenu;
var
  Data: TNodeData;
  IsEntry, Direct: Boolean;
begin
  Data := DataOf(FTree.Selected);
  IsEntry := (FTree.Selected <> nil) and (Data.Kind = TNodeKind.Entry);
  // Ändern lassen sich nur die eigenen uses: direkte Einträge unter „Verwendet“.
  Direct := IsEntry and Data.UsesSide and Data.TopLevel and Assigned(FOnMove);
  FMoveImplementationItem.Visible := Direct and Data.Relation.InInterface;
  FMoveInterfaceItem.Visible := Direct and not Data.Relation.InInterface;
  FRemoveItem.Visible := IsEntry and Data.UsesSide and Data.TopLevel and Data.Relation.Unused and
    Assigned(FOnRemove);
  FCopyPathItem.Visible := IsEntry and (Data.Relation.FileName <> '');
end;

procedure TAtlasUnitRelationsFrame.MenuPopup(Sender: TObject);
begin
  UpdateMenu;
end;

procedure TAtlasUnitRelationsFrame.MoveImplementationClick(Sender: TObject);
var
  Relation: TAtlasUnitRelation;
begin
  if EntryOf(FTree.Selected, Relation) and Assigned(FOnMove) then
    FOnMove(Relation.Name, False);
end;

procedure TAtlasUnitRelationsFrame.MoveInterfaceClick(Sender: TObject);
var
  Relation: TAtlasUnitRelation;
begin
  if EntryOf(FTree.Selected, Relation) and Assigned(FOnMove) then
    FOnMove(Relation.Name, True);
end;

procedure TAtlasUnitRelationsFrame.RemoveClick(Sender: TObject);
var
  Relation: TAtlasUnitRelation;
begin
  if EntryOf(FTree.Selected, Relation) and Relation.Unused and Assigned(FOnRemove) then
    FOnRemove(Relation.Name);
end;

procedure TAtlasUnitRelationsFrame.CopyPathClick(Sender: TObject);
var
  Relation: TAtlasUnitRelation;
begin
  if EntryOf(FTree.Selected, Relation) and (Relation.FileName <> '') then
    Clipboard.AsText := Relation.FileName;
end;

end.
