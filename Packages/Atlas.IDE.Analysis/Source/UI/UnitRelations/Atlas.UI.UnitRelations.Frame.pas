unit Atlas.UI.UnitRelations.Frame;

// Inhalt des Fensters „Unit-Beziehungen“ (#593), reine VCL, aufgebaut im Code
// wie das Ergebnisfenster (#400; die DFM ist leer):
// - Titelzeile mit Atlas-Symbol (#751) und Unit-Name, darunter eine Zeile mit
//   den Kosten („N Units neu übersetzen“), dem Zyklus der Unit und wie viele
//   interface-Einträge sich ins implementation-uses verschieben lassen
//   (#554).
// - Leiste mit Filterfeld und dem Umschalter „direkt“ / „alle Ebenen“
//   (OnDepthChanged; der Dienst fragt dann den Server neu).
// - Baum mit „Verwendet (n)“ und „Wird verwendet von (n)“; je Eintrag intf
//   bzw. impl, Zyklen rot mit „Zyklus“ (Rundweg im Hinweis unter der Maus),
//   ungenutzte Einträge und Bibliotheks-Units (RTL, VCL) abgeblendet, die
//   Bibliothek in einer eingeklappten Gruppe. Mit „alle Ebenen“ hängen die
//   weiteren Ebenen darunter; eine Unit, die weiter oben schon aufgeklappt
//   ist, trägt „siehe oben“. „Wird verwendet von“ teilt sich in „über
//   interface-uses“ und „über implementation-uses“ (#554, „Abhängigkeiten
//   dieser Unit“): Nur die ersten geben eine interface-Änderung weiter.
//   interface-Einträge, die nur im implementation-Teil gebraucht werden,
//   tragen „nur in implementation gebraucht“.
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
    TNodeKind = (Section, LibraryGroup, UsedByGroup, Entry);
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

    /// <summary>Steuerelemente des Frames.</summary>
    TParts = record
      Symbol: TAtlasSymbolImage;
      Title: TLabel;
      Info: TLabel;
      Filter: TEdit;
      Direct: TRadioButton;
      AllLevels: TRadioButton;
      Tree: TTreeView;
      Menu: TPopupMenu;
      MoveImplementationItem: TMenuItem;
      MoveInterfaceItem: TMenuItem;
      RemoveItem: TMenuItem;
      CopyPathItem: TMenuItem;
    end;

    /// <summary>Rückrufe an die IDE-Schicht.</summary>
    THandlers = record
      OnOpen: TAtlasUnitRelationsOpen;
      OnMove: TAtlasUnitRelationsMove;
      OnRemove: TAtlasUnitRelationsRemove;
      OnDepthChanged: TProc<Boolean>;
    end;

    /// <summary>Gezeigte Daten und Zustand des Baums.</summary>
    TState = record
      Relations: TAtlasUnitRelations;
      HasRelations: Boolean;
      RenderedFile: string;
      HintNode: TTreeNode;
      UpdatingDepth: Boolean;
    end;

    /// <summary>Ereignisse der Steuerelemente; gehört dem Frame.</summary>
    TEvents = class(TComponent)
    private
      FFrame: TAtlasUnitRelationsFrame;
    public
      constructor Create(AFrame: TAtlasUnitRelationsFrame); reintroduce;
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
    end;
  private
    FParts: TParts;
    FHandlers: THandlers;
    FState: TState;
    FData: TList<TNodeData>;
    procedure Render;
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
    /// <summary>Gruppe „über interface-uses“ bzw. „über implementation-uses“ unter „Wird verwendet von“.</summary>
    function IsUsedByGroup(ANode: TTreeNode): Boolean;
    property Relations: TAtlasUnitRelations read FState.Relations;
    property HasRelations: Boolean read FState.HasRelations;
    property AllLevels: Boolean read GetAllLevels write SetAllLevels;
    property Tree: TTreeView read FParts.Tree;
    property Filter: TEdit read FParts.Filter;
    property Title: TLabel read FParts.Title;
    property Info: TLabel read FParts.Info;
    property DirectButton: TRadioButton read FParts.Direct;
    property AllLevelsButton: TRadioButton read FParts.AllLevels;
    property MoveImplementationItem: TMenuItem read FParts.MoveImplementationItem;
    property MoveInterfaceItem: TMenuItem read FParts.MoveInterfaceItem;
    property RemoveItem: TMenuItem read FParts.RemoveItem;
    property CopyPathItem: TMenuItem read FParts.CopyPathItem;
    property OnOpen: TAtlasUnitRelationsOpen read FHandlers.OnOpen write FHandlers.OnOpen;
    property OnMove: TAtlasUnitRelationsMove read FHandlers.OnMove write FHandlers.OnMove;
    property OnRemove: TAtlasUnitRelationsRemove read FHandlers.OnRemove write FHandlers.OnRemove;
    /// <summary>Umschalter „direkt“ / „alle Ebenen“ betätigt; True = alle Ebenen.</summary>
    property OnDepthChanged: TProc<Boolean> read FHandlers.OnDepthChanged write FHandlers.OnDepthChanged;
  end;

implementation

uses
  System.UITypes,
  Winapi.Windows,
  Vcl.Clipbrd,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Analysis.Strings;

{$R *.dfm}

type
  TRelationsFrame = TAtlasUnitRelationsFrame;
  TNodeData = TAtlasUnitRelationsFrame.TNodeData;
  TNodeKind = TAtlasUnitRelationsFrame.TNodeKind;

function DataOf(AFrame: TRelationsFrame; ANode: TTreeNode): TNodeData;
var
  mIndex: Integer;
begin
  Result := Default(TNodeData);
  if ANode = nil then
  begin
    Exit;
  end;
  mIndex := Integer(NativeInt(ANode.Data));
  if (mIndex >= 0) and (mIndex < AFrame.FData.Count) then
  begin
    Result := AFrame.FData[mIndex];
  end;
end;

function AddNode(AFrame: TRelationsFrame; AParent: TTreeNode; const AText: string; const AData: TNodeData): TTreeNode;
begin
  Result := AFrame.FParts.Tree.Items.AddChildObject(AParent, AText, Pointer(NativeInt(AFrame.FData.Count)));
  AFrame.FData.Add(AData);
end;

function EntryText(const ARelation: TAtlasUnitRelation): string;
begin
  Result := ARelation.Name + '  ';
  if ARelation.InInterface then
  begin
    Result := Result + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsInterface);
  end
  else
  begin
    Result := Result + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsImplementation);
  end;
  if ARelation.Cycle then
  begin
    Result := Result + ' · ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsCycle);
  end;
  if ARelation.Unused then
  begin
    Result := Result + ' · ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsUnused);
  end
  else if ARelation.OnlyImplementation and ARelation.InInterface then
  begin
    Result := Result + ' · ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsOnlyImplementation);
  end;
  if ARelation.Repeated then
  begin
    Result := Result + ' · ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsRepeated);
  end;
end;

procedure AddEntries(AFrame: TRelationsFrame; AParent: TTreeNode; const AItems: TAtlasUnitRelationList;
  AUsesSide, ATopLevel: Boolean; const AKey: string);
var
  mItem: TAtlasUnitRelation;
  mData: TNodeData;
  mNode: TTreeNode;
begin
  for mItem in AItems do
  begin
    mData := Default(TNodeData);
    mData.Kind := TNodeKind.Entry;
    mData.Relation := mItem;
    mData.UsesSide := AUsesSide;
    mData.TopLevel := ATopLevel;
    mData.Key := AKey + '/' + LowerCase(mItem.Name);
    mNode := AddNode(AFrame, AParent, EntryText(mItem), mData);
    AddEntries(AFrame, mNode, mItem.Children, AUsesSide, False, mData.Key);
  end;
end;

/// <summary>Aufgeklappte Knoten und Auswahl merken (nach dem Schlüssel jedes Knotens).</summary>
procedure SaveState(AFrame: TRelationsFrame; AExpanded: TDictionary<string, Boolean>; out ASelected: string);
var
  mNode: TTreeNode;
begin
  ASelected := '';
  mNode := AFrame.FParts.Tree.Items.GetFirstNode;
  while mNode <> nil do
  begin
    if mNode.HasChildren then
    begin
      AExpanded.AddOrSetValue(DataOf(AFrame, mNode).Key, mNode.Expanded);
    end;
    mNode := mNode.GetNext;
  end;
  if AFrame.FParts.Tree.Selected <> nil then
  begin
    ASelected := DataOf(AFrame, AFrame.FParts.Tree.Selected).Key;
  end;
end;

procedure RestoreState(AFrame: TRelationsFrame; AExpanded: TDictionary<string, Boolean>; const ASelected: string);
var
  mNode: TTreeNode;
  mData: TNodeData;
  mExpanded: Boolean;
begin
  mNode := AFrame.FParts.Tree.Items.GetFirstNode;
  while mNode <> nil do
  begin
    mData := DataOf(AFrame, mNode);
    if mNode.HasChildren then
    begin
      // Unbekannte Knoten: Abschnitte und Verwender-Gruppen offen, Bibliothek und tiefere Ebenen zu; mit Filter
      // alles offen.
      if not AExpanded.TryGetValue(mData.Key, mExpanded) then
      begin
        mExpanded := (mData.Kind in [TNodeKind.Section, TNodeKind.UsedByGroup])
          or (Trim(AFrame.FParts.Filter.Text) <> '');
      end;
      mNode.Expanded := mExpanded;
    end;
    if (ASelected <> '') and (mData.Key = ASelected) then
    begin
      AFrame.FParts.Tree.Selected := mNode;
    end;
    mNode := mNode.GetNext;
  end;
end;

/// <summary>Zeile unter dem Titel: Kosten, verschiebbare Einträge, Zyklus.</summary>
function InfoLine(const ARelations: TAtlasUnitRelations): string;
var
  mMovable: Integer;
begin
  if not ARelations.Found then
  begin
    Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsNotInGraph);
  end
  else if ARelations.RecompileCount = 1 then
  begin
    Result := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsRecompileOne);
  end
  else
  begin
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsRecompile, [ARelations.RecompileCount]);
  end;
  mMovable := TAtlasUnitRelationsModel.Movable(ARelations.Uses_);
  if mMovable > 0 then
  begin
    Result := Result + ' · ' + TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsMovable, [mMovable]);
  end;
  if ARelations.InCycle then
  begin
    Result := Result + ' · ' + TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsCycle);
  end;
end;

procedure ShowInfo(AFrame: TRelationsFrame);
var
  mRelations: TAtlasUnitRelations;
begin
  mRelations := AFrame.FState.Relations;
  AFrame.FParts.Title.Caption := mRelations.UnitName;
  AFrame.FParts.Info.Caption := InfoLine(mRelations);
  AFrame.FParts.Info.Hint := mRelations.CyclePath;
  if mRelations.InCycle then
  begin
    AFrame.FParts.Info.Font.Color := TColor(TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(
      StyleServices(AFrame).GetSystemColor(clWindow)))).Error);
  end
  else
  begin
    AFrame.FParts.Info.ParentFont := True;
  end;
end;

function GroupData(AKind: TNodeKind; AUsesSide: Boolean; const AKey: string): TNodeData;
begin
  Result := Default(TNodeData);
  Result.Kind := AKind;
  Result.UsesSide := AUsesSide;
  Result.Key := AKey;
end;

/// <summary>Abschnitt „Verwendet“ mit der Bibliothek in einer eigenen Gruppe.</summary>
procedure AddUses(AFrame: TRelationsFrame);
var
  mUses, mProject, mLibrary: TAtlasUnitRelationList;
  mSection, mGroup: TTreeNode;
begin
  mUses := TAtlasUnitRelationsModel.Filter(AFrame.FState.Relations.Uses_, AFrame.FParts.Filter.Text);
  TAtlasUnitRelationsModel.SplitLibrary(mUses, mProject, mLibrary);
  mSection := AddNode(AFrame, nil, TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUses,
    [Length(mUses)]), GroupData(TNodeKind.Section, True, 'uses'));
  AddEntries(AFrame, mSection, mProject, True, True, 'uses');
  if mLibrary <> nil then
  begin
    mGroup := AddNode(AFrame, mSection, TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsLibrary,
      [Length(mLibrary)]), GroupData(TNodeKind.LibraryGroup, True, 'uses/#library'));
    AddEntries(AFrame, mGroup, mLibrary, True, True, 'uses/#library');
  end;
end;

/// <summary>Gruppe unter „Wird verwendet von“; leere Gruppen entfallen.</summary>
procedure AddUsedByGroup(AFrame: TRelationsFrame; ASection: TTreeNode; AText: TAtlasAnalysisTextId;
  const AItems: TAtlasUnitRelationList; const AKey: string);
var
  mGroup: TTreeNode;
begin
  if AItems = nil then
  begin
    Exit;
  end;
  mGroup := AddNode(AFrame, ASection, TAtlasAnalysisStrings.Fmt(AText, [Length(AItems)]),
    GroupData(TNodeKind.UsedByGroup, False, AKey));
  AddEntries(AFrame, mGroup, AItems, False, True, AKey);
end;

/// <summary>Abschnitt „Wird verwendet von“, geteilt nach dem Abschnitt in der verwendenden Unit (#554).</summary>
procedure AddUsedBy(AFrame: TRelationsFrame);
var
  mUsedBy, mByInterface, mByImplementation: TAtlasUnitRelationList;
  mSection: TTreeNode;
begin
  mUsedBy := TAtlasUnitRelationsModel.Filter(AFrame.FState.Relations.UsedBy, AFrame.FParts.Filter.Text);
  mSection := AddNode(AFrame, nil, TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsUsedBy,
    [Length(mUsedBy)]), GroupData(TNodeKind.Section, False, 'usedBy'));
  TAtlasUnitRelationsModel.SplitUsedBy(mUsedBy, mByInterface, mByImplementation);
  AddUsedByGroup(AFrame, mSection, TAtlasAnalysisTextId.UnitRelationsUsedByInterface, mByInterface,
    'usedBy/#interface');
  AddUsedByGroup(AFrame, mSection, TAtlasAnalysisTextId.UnitRelationsUsedByImplementation, mByImplementation,
    'usedBy/#implementation');
end;

function NewMenuItem(AMenu: TPopupMenu; AText: TAtlasAnalysisTextId; const AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := TAtlasAnalysisStrings.Text(AText);
  Result.OnClick := AOnClick;
  AMenu.Items.Add(Result);
end;

function NewPanel(AFrame: TRelationsFrame; AHeight: Integer): TPanel;
begin
  Result := TPanel.Create(AFrame);
  Result.Parent := AFrame;
  Result.Align := alTop;
  Result.BevelOuter := bvNone;
  Result.ParentBackground := True;
  Result.Height := AHeight;
end;

/// <summary>Titelzeile mit Symbol (#751) und Unit, darunter Kosten und Zyklus der Unit.</summary>
procedure BuildHeader(AFrame: TRelationsFrame);
var
  mHeader: TPanel;
begin
  mHeader := NewPanel(AFrame, 22);
  AFrame.FParts.Symbol := TAtlasSymbolImage.Create(AFrame);
  AFrame.FParts.Symbol.Parent := mHeader;
  AFrame.FParts.Symbol.LogicalSize := TAtlasSymbol.cMenuSize;
  AFrame.FParts.Symbol.Align := alLeft;
  AFrame.FParts.Symbol.AlignWithMargins := True;
  AFrame.FParts.Title := TLabel.Create(AFrame);
  AFrame.FParts.Title.Parent := mHeader;
  AFrame.FParts.Title.Align := alClient;
  AFrame.FParts.Title.Layout := tlCenter;
  AFrame.FParts.Title.AlignWithMargins := True;
  AFrame.FParts.Title.ShowAccelChar := False;
  AFrame.FParts.Title.EllipsisPosition := epEndEllipsis;
  AFrame.FParts.Title.Font.Style := [fsBold];
  AFrame.FParts.Info := TLabel.Create(AFrame);
  AFrame.FParts.Info.Parent := AFrame;
  AFrame.FParts.Info.Align := alTop;
  AFrame.FParts.Info.Top := mHeader.Top + mHeader.Height;
  AFrame.FParts.Info.AlignWithMargins := True;
  AFrame.FParts.Info.ShowAccelChar := False;
  AFrame.FParts.Info.EllipsisPosition := epEndEllipsis;
  AFrame.FParts.Info.ShowHint := True;
end;

function NewRadio(ABar: TPanel; AWidth: Integer; AText: TAtlasAnalysisTextId;
  AEvents: TRelationsFrame.TEvents): TRadioButton;
begin
  Result := TRadioButton.Create(ABar.Owner);
  Result.Parent := ABar;
  Result.Align := alRight;
  Result.AlignWithMargins := True;
  Result.Width := AWidth;
  Result.Caption := TAtlasAnalysisStrings.Text(AText);
  Result.OnClick := AEvents.DepthClick;
end;

/// <summary>Leiste mit Filter und Tiefe.</summary>
procedure BuildBar(AFrame: TRelationsFrame; AEvents: TRelationsFrame.TEvents);
var
  mBar: TPanel;
begin
  mBar := NewPanel(AFrame, 26);
  mBar.Top := AFrame.FParts.Info.Top + AFrame.FParts.Info.Height + 1;
  AFrame.FParts.AllLevels := NewRadio(mBar, 90, TAtlasAnalysisTextId.UnitRelationsAllLevels, AEvents);
  AFrame.FParts.Direct := NewRadio(mBar, 70, TAtlasAnalysisTextId.UnitRelationsDirect, AEvents);
  AFrame.FParts.Direct.Checked := True;
  AFrame.FParts.Filter := TEdit.Create(AFrame);
  AFrame.FParts.Filter.Parent := mBar;
  AFrame.FParts.Filter.Align := alClient;
  AFrame.FParts.Filter.AlignWithMargins := True;
  AFrame.FParts.Filter.TextHint := TAtlasAnalysisStrings.Text(TAtlasAnalysisTextId.UnitRelationsFilterHint);
  AFrame.FParts.Filter.OnChange := AEvents.FilterChange;
end;

/// <summary>Baum und Kontextmenü.</summary>
procedure BuildTree(AFrame: TRelationsFrame; AEvents: TRelationsFrame.TEvents);
var
  mTree: TTreeView;
  mMenu: TPopupMenu;
begin
  mTree := TTreeView.Create(AFrame);
  mTree.Parent := AFrame;
  mTree.Align := alClient;
  mTree.ReadOnly := True;
  mTree.HideSelection := False;
  mTree.RowSelect := True;
  mTree.ShowLines := False;
  mTree.RightClickSelect := True;
  mTree.BorderStyle := bsNone;
  mTree.OnDblClick := AEvents.TreeDblClick;
  mTree.OnKeyDown := AEvents.TreeKeyDown;
  mTree.OnMouseMove := AEvents.TreeMouseMove;
  mTree.OnCustomDrawItem := AEvents.TreeCustomDrawItem;
  mTree.ShowHint := True;
  AFrame.FParts.Tree := mTree;
  mMenu := TPopupMenu.Create(AFrame);
  mMenu.OnPopup := AEvents.MenuPopup;
  AFrame.FParts.Menu := mMenu;
  AFrame.FParts.MoveImplementationItem := NewMenuItem(mMenu, TAtlasAnalysisTextId.UnitRelationsMoveImplementation,
    AEvents.MoveImplementationClick);
  AFrame.FParts.MoveInterfaceItem := NewMenuItem(mMenu, TAtlasAnalysisTextId.UnitRelationsMoveInterface,
    AEvents.MoveInterfaceClick);
  AFrame.FParts.RemoveItem := NewMenuItem(mMenu, TAtlasAnalysisTextId.UnitRelationsRemove, AEvents.RemoveClick);
  AFrame.FParts.CopyPathItem := NewMenuItem(mMenu, TAtlasAnalysisTextId.UnitRelationsCopyPath,
    AEvents.CopyPathClick);
  mTree.PopupMenu := mMenu;
end;

{ TAtlasUnitRelationsFrame.TEvents }

constructor TAtlasUnitRelationsFrame.TEvents.Create(AFrame: TAtlasUnitRelationsFrame);
begin
  inherited Create(AFrame);
  FFrame := AFrame;
end;

procedure TAtlasUnitRelationsFrame.TEvents.FilterChange(Sender: TObject);
begin
  if FFrame.FState.HasRelations then
  begin
    // Neuer Filter: aufgeklappt wird nach Vorgabe (mit Filter alles).
    FFrame.FState.RenderedFile := '';
    FFrame.Render;
  end;
end;

procedure TAtlasUnitRelationsFrame.TEvents.DepthClick(Sender: TObject);
begin
  if FFrame.FState.UpdatingDepth or not (Sender as TRadioButton).Checked then
  begin
    Exit;
  end;
  if Assigned(FFrame.FHandlers.OnDepthChanged) then
  begin
    FFrame.FHandlers.OnDepthChanged(FFrame.FParts.AllLevels.Checked);
  end;
end;

procedure TAtlasUnitRelationsFrame.TEvents.TreeDblClick(Sender: TObject);
begin
  FFrame.OpenNode(FFrame.FParts.Tree.Selected, GetKeyState(VK_CONTROL) < 0);
end;

procedure TAtlasUnitRelationsFrame.TEvents.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    FFrame.OpenNode(FFrame.FParts.Tree.Selected, ssCtrl in Shift);
    Key := 0;
  end;
end;

procedure TAtlasUnitRelationsFrame.TEvents.TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  mNode: TTreeNode;
begin
  mNode := FFrame.FParts.Tree.GetNodeAt(X, Y);
  if mNode = FFrame.FState.HintNode then
  begin
    Exit;
  end;
  FFrame.FState.HintNode := mNode;
  FFrame.FParts.Tree.Hint := FFrame.HintOf(mNode);
  Application.CancelHint;
end;

procedure TAtlasUnitRelationsFrame.TEvents.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mData: TNodeData;
  mColors: TAtlasColors;
begin
  DefaultDraw := True;
  mData := DataOf(FFrame, Node);
  // Wer hier Schrift ändert, zeichnet Hintergrund und Schrift selbst: Ohne Stilfarben wären sie clWindow und
  // clWindowText ohne Stil, also weiß bzw. schwarz im dunklen Thema. Gewählte Zeilen behalten die Farben der Auswahl.
  if not (cdsSelected in State) then
  begin
    Sender.Canvas.Brush.Color := StyleServices(FFrame).GetSystemColor(clWindow);
    Sender.Canvas.Font.Color := StyleServices(FFrame).GetSystemColor(clWindowText);
  end;
  if mData.Kind = TNodeKind.Section then
  begin
    Sender.Canvas.Font.Style := [fsBold];
    Exit;
  end;
  // Gewählte Zeile in den Farben der Auswahl lassen.
  if cdsSelected in State then
  begin
    Exit;
  end;
  mColors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(Sender.Canvas.Brush.Color)));
  if (mData.Kind = TNodeKind.Entry) and mData.Relation.Cycle then
  begin
    Sender.Canvas.Font.Color := TColor(mColors.Error);
  end
  else if (mData.Kind = TNodeKind.LibraryGroup) or mData.Relation.Library_ or mData.Relation.Unused then
  begin
    Sender.Canvas.Font.Color := TColor(mColors.Muted);
  end;
end;

procedure TAtlasUnitRelationsFrame.TEvents.MenuPopup(Sender: TObject);
begin
  FFrame.UpdateMenu;
end;

procedure TAtlasUnitRelationsFrame.TEvents.MoveImplementationClick(Sender: TObject);
var
  mRelation: TAtlasUnitRelation;
begin
  if FFrame.EntryOf(FFrame.FParts.Tree.Selected, mRelation) and Assigned(FFrame.FHandlers.OnMove) then
  begin
    FFrame.FHandlers.OnMove(mRelation.Name, False);
  end;
end;

procedure TAtlasUnitRelationsFrame.TEvents.MoveInterfaceClick(Sender: TObject);
var
  mRelation: TAtlasUnitRelation;
begin
  if FFrame.EntryOf(FFrame.FParts.Tree.Selected, mRelation) and Assigned(FFrame.FHandlers.OnMove) then
  begin
    FFrame.FHandlers.OnMove(mRelation.Name, True);
  end;
end;

procedure TAtlasUnitRelationsFrame.TEvents.RemoveClick(Sender: TObject);
var
  mRelation: TAtlasUnitRelation;
begin
  if FFrame.EntryOf(FFrame.FParts.Tree.Selected, mRelation) and mRelation.Unused
    and Assigned(FFrame.FHandlers.OnRemove) then
  begin
    FFrame.FHandlers.OnRemove(mRelation.Name);
  end;
end;

procedure TAtlasUnitRelationsFrame.TEvents.CopyPathClick(Sender: TObject);
var
  mRelation: TAtlasUnitRelation;
begin
  if FFrame.EntryOf(FFrame.FParts.Tree.Selected, mRelation) and (mRelation.FileName <> '') then
  begin
    Clipboard.AsText := mRelation.FileName;
  end;
end;

{ TAtlasUnitRelationsFrame }

constructor TAtlasUnitRelationsFrame.Create(AOwner: TComponent);
var
  mEvents: TEvents;
begin
  inherited Create(AOwner);
  FData := TList<TNodeData>.Create;
  mEvents := TEvents.Create(Self);
  BuildHeader(Self);
  BuildBar(Self, mEvents);
  BuildTree(Self, mEvents);
end;

destructor TAtlasUnitRelationsFrame.Destroy;
begin
  FData.Free;
  inherited Destroy;
end;

function TAtlasUnitRelationsFrame.GetAllLevels: Boolean;
begin
  Result := FParts.AllLevels.Checked;
end;

procedure TAtlasUnitRelationsFrame.SetAllLevels(AValue: Boolean);
begin
  // Von außen gesetzt: kein OnDepthChanged.
  FState.UpdatingDepth := True;
  try
    FParts.AllLevels.Checked := AValue;
    FParts.Direct.Checked := not AValue;
  finally
    FState.UpdatingDepth := False;
  end;
end;

procedure TAtlasUnitRelationsFrame.Render;
var
  mExpanded: TDictionary<string, Boolean>;
  mSelected: string;
begin
  mExpanded := TDictionary<string, Boolean>.Create;
  try
    mSelected := '';
    // Andere Unit oder neuer Filter: Vorgaben statt des alten Zustands.
    if SameText(FState.RenderedFile, FState.Relations.FileName) then
    begin
      SaveState(Self, mExpanded, mSelected);
    end;
    FState.RenderedFile := FState.Relations.FileName;
    FState.HintNode := nil;
    FParts.Tree.Items.BeginUpdate;
    try
      FParts.Tree.Items.Clear;
      FData.Clear;
      ShowInfo(Self);
      AddUses(Self);
      AddUsedBy(Self);
      RestoreState(Self, mExpanded, mSelected);
    finally
      FParts.Tree.Items.EndUpdate;
    end;
  finally
    mExpanded.Free;
  end;
end;

procedure TAtlasUnitRelationsFrame.SetRelations(const ARelations: TAtlasUnitRelations);
begin
  if not SameText(ARelations.FileName, FState.Relations.FileName) then
  begin
    FState.RenderedFile := '';
  end;
  FState.Relations := ARelations;
  FState.HasRelations := True;
  SetAllLevels(ARelations.Depth <> 1);
  Render;
end;

procedure TAtlasUnitRelationsFrame.SetMessage(const AText: string);
begin
  FState.HasRelations := False;
  FState.Relations := Default(TAtlasUnitRelations);
  FState.RenderedFile := '';
  FState.HintNode := nil;
  FParts.Title.Caption := '';
  FParts.Info.Caption := AText;
  FParts.Info.Hint := '';
  FParts.Info.ParentFont := True;
  FParts.Tree.Items.BeginUpdate;
  try
    FParts.Tree.Items.Clear;
    FData.Clear;
  finally
    FParts.Tree.Items.EndUpdate;
  end;
end;

function TAtlasUnitRelationsFrame.EntryOf(ANode: TTreeNode; out ARelation: TAtlasUnitRelation): Boolean;
var
  mData: TNodeData;
begin
  mData := DataOf(Self, ANode);
  ARelation := mData.Relation;
  Result := (ANode <> nil) and (mData.Kind = TNodeKind.Entry);
end;

function TAtlasUnitRelationsFrame.IsLibraryGroup(ANode: TTreeNode): Boolean;
begin
  Result := (ANode <> nil) and (DataOf(Self, ANode).Kind = TNodeKind.LibraryGroup);
end;

function TAtlasUnitRelationsFrame.IsUsedByGroup(ANode: TTreeNode): Boolean;
begin
  Result := (ANode <> nil) and (DataOf(Self, ANode).Kind = TNodeKind.UsedByGroup);
end;

function TAtlasUnitRelationsFrame.FindEntry(const AName: string; AUsesSide: Boolean): TTreeNode;
var
  mNode: TTreeNode;
  mData: TNodeData;
begin
  mNode := FParts.Tree.Items.GetFirstNode;
  while mNode <> nil do
  begin
    mData := DataOf(Self, mNode);
    if (mData.Kind = TNodeKind.Entry) and mData.TopLevel and (mData.UsesSide = AUsesSide) and
      SameText(mData.Relation.Name, AName) then
    begin
      Exit(mNode);
    end;
    mNode := mNode.GetNext;
  end;
  Result := nil;
end;

function TAtlasUnitRelationsFrame.HintOf(ANode: TTreeNode): string;
var
  mRelation: TAtlasUnitRelation;
begin
  Result := '';
  if not EntryOf(ANode, mRelation) then
  begin
    Exit;
  end;
  if mRelation.Cycle and (mRelation.CyclePath <> '') then
  begin
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsCyclePath, [mRelation.CyclePath]);
  end
  else if mRelation.OnlyImplementation and mRelation.InInterface and not mRelation.Unused then
  begin
    Result := TAtlasAnalysisStrings.Fmt(TAtlasAnalysisTextId.UnitRelationsOnlyImplementationHint, [mRelation.Name]);
  end
  else
  begin
    Result := mRelation.FileName;
  end;
end;

procedure TAtlasUnitRelationsFrame.OpenNode(ANode: TTreeNode; AToEntry: Boolean);
var
  mRelation: TAtlasUnitRelation;
  mOpen: TAtlasUnitRelationsOpen;
begin
  mOpen := FHandlers.OnOpen;
  if not EntryOf(ANode, mRelation) or not Assigned(mOpen) then
  begin
    Exit;
  end;
  if AToEntry and (mRelation.LocationFile <> '') and (mRelation.Line >= 0) then
  begin
    mOpen(mRelation.LocationFile, mRelation.Line, mRelation.Character);
  end
  else if mRelation.FileName <> '' then
  begin
    mOpen(mRelation.FileName, -1, -1);
  end
  else if (mRelation.LocationFile <> '') and (mRelation.Line >= 0) then
  begin
    // Unit ohne Quelltext (RTL ohne Pfad): wenigstens der Eintrag.
    mOpen(mRelation.LocationFile, mRelation.Line, mRelation.Character);
  end;
end;

procedure TAtlasUnitRelationsFrame.UpdateMenu;
var
  mData: TNodeData;
  mIsEntry, mDirect: Boolean;
begin
  mData := DataOf(Self, FParts.Tree.Selected);
  mIsEntry := (FParts.Tree.Selected <> nil) and (mData.Kind = TNodeKind.Entry);
  // Ändern lassen sich nur die eigenen uses: direkte Einträge unter „Verwendet“.
  mDirect := mIsEntry and mData.UsesSide and mData.TopLevel and Assigned(FHandlers.OnMove);
  FParts.MoveImplementationItem.Visible := mDirect and mData.Relation.InInterface;
  FParts.MoveInterfaceItem.Visible := mDirect and not mData.Relation.InInterface;
  FParts.RemoveItem.Visible := mIsEntry and mData.UsesSide and mData.TopLevel and mData.Relation.Unused and
    Assigned(FHandlers.OnRemove);
  FParts.CopyPathItem.Visible := mIsEntry and (mData.Relation.FileName <> '');
end;

end.
