unit Atlas.UI.Results.View;

// Gemeinsame Ansicht des Ergebnisfensters (#400): Titelzeile, Baum, Kontextmenü und die Daten je Knoten. Jede
// Darstellung (Fundstellen, Hierarchie, Änderungen, Listen mit Kennungen, Weg, Auswirkung, Datenfluss, Issues) ist
// ein eigener Teil (TAtlasResultsPart), den die Ansicht kennt: Clear setzt alle Teile zurück; Aufklappen, Öffnen,
// Kontextmenü, Klick und Tasten gehen der Reihe nach an die Teile, bis einer sie übernimmt. Die Teile bauen ihre
// Steuerelemente selbst in Titelzeile (Header) bzw. Frame (Host); Besitzer ist der Frame.

interface

uses
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.DataFlow,
  Atlas.Core.Undo.Contract;

type
  TAtlasResultsOpen = reference to procedure(const AFileName: string; ALine, ACharacter: Integer);

{$SCOPEDENUMS ON}
  /// <summary>Art eines Knotens im Baum des Ergebnisfensters.</summary>
  TAtlasResultsNodeKind = (Group, Entry, Hierarchy, Placeholder, ChangeSet, ChangeFile, Item, Flow, FlowPlace,
    FlowSource, Issue, Commit);
{$SCOPEDENUMS OFF}

  /// <summary>Daten eines Knotens; Line und Character 0-basiert.</summary>
  TAtlasResultsNode = record
    Kind: TAtlasResultsNodeKind;
    FileName: string;
    Line: Integer;
    Character: Integer;
    Item: TAtlasHierarchyItem;
    Loaded: Boolean;
    /// <summary>Kennung des Satzes (#721) und sein Zustand; bei Issue und Commit (#1275) deren Id.</summary>
    SetId: Integer;
    State: TAtlasChangeSetState;
    /// <summary>Kennung des Eintrags einer Liste mit Kennungen (#545, #1455).</summary>
    ItemId: string;
    /// <summary>Hinweis unter der Maus: Erklärung eines erschlossenen Treffers (#1119).</summary>
    Hint: string;
    /// <summary>Datenfluss (#690): Quelle, Pfad bis einschließlich der Quelle und Ebene ihrer Stelle.</summary>
    FlowSource: TAtlasDataFlowSymbol;
    FlowPath: TArray<string>;
    FlowLevel: Integer;
    /// <summary>Knoten der Art AKind ohne weitere Angaben.</summary>
    class function Create(AKind: TAtlasResultsNodeKind): TAtlasResultsNode; static;
    /// <summary>Knoten der Art AKind, der zu AFileName springt.</summary>
    class function Place(AKind: TAtlasResultsNodeKind; const AFileName: string;
      ALine, ACharacter: Integer): TAtlasResultsNode; static;
  end;

  TAtlasResultsView = class;

  /// <summary>Eine Darstellung im Ergebnisfenster. Die Grundfassung übernimmt nichts.</summary>
  TAtlasResultsPart = class
  private
    FView: TAtlasResultsView;
  protected
    /// <summary>Neuer Baum mit Titel: Steuerelemente des Teils verbergen, Zustand vergessen.</summary>
    procedure Reset; virtual;
    /// <summary>ANode nachladen; True, wenn der Teil den Knoten kennt.</summary>
    function Expand(ANode: TTreeNode; const AData: TAtlasResultsNode; var AAllowExpansion: Boolean): Boolean;
      virtual;
    /// <summary>Gewählten Knoten öffnen; True, wenn der Teil ihn übernommen hat.</summary>
    function Open(const AData: TAtlasResultsNode): Boolean; virtual;
    /// <summary>Eigene Einträge im Kontextmenü zeigen bzw. verbergen.</summary>
    procedure Popup; virtual;
    /// <summary>Klick auf die schon gewählte Zeile ANode.</summary>
    procedure Click(ANode: TTreeNode); virtual;
    /// <summary>Taste übernehmen; True, wenn der Teil sie verarbeitet hat.</summary>
    function KeyDown(AKey: Word): Boolean; virtual;
  public
    constructor Create(AView: TAtlasResultsView);
    property View: TAtlasResultsView read FView;
  end;

  /// <summary>Titelzeile, Baum und Kontextmenü, die sich alle Teile teilen.</summary>
  TAtlasResultsView = class
  private type
    TControls = record
      Host: TWinControl;
      Header: TPanel;
      Title: TLabel;
      Tree: TTreeView;
      Menu: TPopupMenu;
    end;
  private
    FControls: TControls;
    FData: TList<TAtlasResultsNode>;
    FParts: TObjectList<TAtlasResultsPart>;
    FHintNode: TTreeNode;
    FOnOpen: TAtlasResultsOpen;
  public
    constructor Create(AHost: TWinControl; AHeader: TPanel; ATitle: TLabel; ATree: TTreeView; AMenu: TPopupMenu);
    destructor Destroy; override;
    /// <summary>Teil anmelden; die Ansicht gibt ihn frei.</summary>
    procedure Add(APart: TAtlasResultsPart);
    /// <summary>Alle Teile zurücksetzen, Baum leeren und den Titel setzen.</summary>
    procedure Clear(const ATitle: string);
    function AddNode(AParent: TTreeNode; const AText: string; const AData: TAtlasResultsNode): TTreeNode;
    /// <summary>Daten von ANode; ohne Knoten ein Platzhalter.</summary>
    function DataOf(ANode: TTreeNode): TAtlasResultsNode;
    /// <summary>Daten von ANode ersetzen (etwa Loaded nach dem Nachladen).</summary>
    procedure Store(ANode: TTreeNode; const AData: TAtlasResultsNode);
    /// <summary>ANode wählen; nil wählt den ersten Knoten, falls es einen gibt.</summary>
    procedure Select(ANode: TTreeNode);
    /// <summary>Zur Stelle von AData springen, falls sie eine hat.</summary>
    procedure Open(const AData: TAtlasResultsNode);
    /// <summary>Gewählten Knoten öffnen: zuerst die Teile fragen, sonst zur Stelle springen.</summary>
    procedure OpenSelected;
    /// <summary>Knoten aufklappen: Der erste Teil, der ihn kennt, lädt nach.</summary>
    procedure Expanding(ANode: TTreeNode; var AAllowExpansion: Boolean);
    /// <summary>Kontextmenü öffnet sich: Jeder Teil zeigt bzw. verbirgt seine Einträge.</summary>
    procedure Popup;
    /// <summary>Klick auf die Zeile von ANode.</summary>
    procedure Click(ANode: TTreeNode);
    /// <summary>Taste im Baum; AKey 0, wenn ein Teil sie übernommen hat.</summary>
    procedure KeyDown(var AKey: Word);
    /// <summary>Hinweis des Knotens unter der Maus zeigen.</summary>
    procedure HintAt(AX, AY: Integer);
    property Host: TWinControl read FControls.Host;
    property Header: TPanel read FControls.Header;
    property Title: TLabel read FControls.Title;
    property Tree: TTreeView read FControls.Tree;
    property Menu: TPopupMenu read FControls.Menu;
    property OnOpen: TAtlasResultsOpen read FOnOpen write FOnOpen;
  end;

  /// <summary>Steuerelemente der Teile, einheitlich angelegt (Besitzer AOwner, AlignWithMargins).</summary>
  TAtlasResultsControls = record
    class function Check(AOwner: TComponent; AParent: TWinControl; AAlign: TAlign; AWidth: Integer;
      const ACaption: string; AOnClick: TNotifyEvent): TCheckBox; static;
    class function Button(AOwner: TComponent; AParent: TWinControl; AAlign: TAlign; AWidth: Integer;
      const ACaption: string; AOnClick: TNotifyEvent): TButton; static;
    class function Radio(AOwner: TComponent; AParent: TWinControl; AWidth: Integer; const ACaption: string;
      AOnClick: TNotifyEvent): TRadioButton; static;
    /// <summary>Eintrag am Ende von AMenu.</summary>
    class function MenuItem(AMenu: TPopupMenu; const ACaption: string; AOnClick: TNotifyEvent): TMenuItem; static;
    /// <summary>Unsichtbare, fließende Leiste unter der Titelzeile; Reihenfolge = Erzeugungsreihenfolge.</summary>
    class function Bar(AOwner: TComponent; AView: TAtlasResultsView): TFlowPanel; static;
  end;

implementation

uses
  Vcl.Forms;

{ TAtlasResultsNode }

class function TAtlasResultsNode.Create(AKind: TAtlasResultsNodeKind): TAtlasResultsNode;
begin
  Result := Default(TAtlasResultsNode);
  Result.Kind := AKind;
end;

class function TAtlasResultsNode.Place(AKind: TAtlasResultsNodeKind; const AFileName: string;
  ALine, ACharacter: Integer): TAtlasResultsNode;
begin
  Result := Create(AKind);
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Character := ACharacter;
end;

{ TAtlasResultsView }

constructor TAtlasResultsView.Create(AHost: TWinControl; AHeader: TPanel; ATitle: TLabel; ATree: TTreeView;
  AMenu: TPopupMenu);
begin
  inherited Create;
  FControls.Host := AHost;
  FControls.Header := AHeader;
  FControls.Title := ATitle;
  FControls.Tree := ATree;
  FControls.Menu := AMenu;
  FData := TList<TAtlasResultsNode>.Create;
  FParts := TObjectList<TAtlasResultsPart>.Create(True);
end;

destructor TAtlasResultsView.Destroy;
begin
  FParts.Free;
  FData.Free;
  inherited;
end;

procedure TAtlasResultsView.Add(APart: TAtlasResultsPart);
begin
  FParts.Add(APart);
end;

procedure TAtlasResultsView.Clear(const ATitle: string);
var
  mPart: TAtlasResultsPart;
begin
  for mPart in FParts do
  begin
    mPart.Reset;
  end;
  FHintNode := nil;
  Tree.Hint := '';
  Title.Caption := ATitle;
  Tree.Items.BeginUpdate;
  try
    Tree.Items.Clear;
  finally
    Tree.Items.EndUpdate;
  end;
  FData.Clear;
end;

function TAtlasResultsView.AddNode(AParent: TTreeNode; const AText: string;
  const AData: TAtlasResultsNode): TTreeNode;
begin
  Result := Tree.Items.AddChild(AParent, AText);
  // Index in FData; 0 wäre nil, deshalb um eins verschoben.
  Result.Data := Pointer(NativeInt(FData.Add(AData) + 1));
end;

function TAtlasResultsView.DataOf(ANode: TTreeNode): TAtlasResultsNode;
var
  mIndex: NativeInt;
begin
  Result := TAtlasResultsNode.Create(TAtlasResultsNodeKind.Placeholder);
  if ANode = nil then
  begin
    Exit;
  end;
  mIndex := NativeInt(ANode.Data) - 1;
  if (mIndex >= 0) and (mIndex < FData.Count) then
  begin
    Result := FData[Integer(mIndex)];
  end;
end;

procedure TAtlasResultsView.Store(ANode: TTreeNode; const AData: TAtlasResultsNode);
var
  mIndex: NativeInt;
begin
  mIndex := NativeInt(ANode.Data) - 1;
  if (mIndex >= 0) and (mIndex < FData.Count) then
  begin
    FData[Integer(mIndex)] := AData;
  end;
end;

procedure TAtlasResultsView.Select(ANode: TTreeNode);
begin
  if ANode <> nil then
  begin
    Tree.Selected := ANode;
  end
  else if Tree.Items.Count > 0 then
  begin
    Tree.Selected := Tree.Items[0];
  end;
end;

procedure TAtlasResultsView.Open(const AData: TAtlasResultsNode);
begin
  // Einträge mit Kennung (Notizen #545) springen zu ihrer Zeile, verwaiste Notizen zur zuletzt bekannten.
  if (AData.Kind in [TAtlasResultsNodeKind.Entry, TAtlasResultsNodeKind.Hierarchy, TAtlasResultsNodeKind.Item,
    TAtlasResultsNodeKind.Flow, TAtlasResultsNodeKind.FlowPlace, TAtlasResultsNodeKind.FlowSource]) and
    (AData.FileName <> '') and Assigned(FOnOpen) then
  begin
    FOnOpen(AData.FileName, AData.Line, AData.Character);
  end;
end;

procedure TAtlasResultsView.OpenSelected;
var
  mData: TAtlasResultsNode;
  mPart: TAtlasResultsPart;
begin
  mData := DataOf(Tree.Selected);
  for mPart in FParts do
  begin
    if mPart.Open(mData) then
    begin
      Exit;
    end;
  end;
  Open(mData);
end;

procedure TAtlasResultsView.Expanding(ANode: TTreeNode; var AAllowExpansion: Boolean);
var
  mData: TAtlasResultsNode;
  mPart: TAtlasResultsPart;
begin
  mData := DataOf(ANode);
  if mData.Loaded then
  begin
    Exit;
  end;
  for mPart in FParts do
  begin
    if mPart.Expand(ANode, mData, AAllowExpansion) then
    begin
      Exit;
    end;
  end;
end;

procedure TAtlasResultsView.Popup;
var
  mPart: TAtlasResultsPart;
begin
  for mPart in FParts do
  begin
    mPart.Popup;
  end;
end;

procedure TAtlasResultsView.Click(ANode: TTreeNode);
var
  mPart: TAtlasResultsPart;
begin
  for mPart in FParts do
  begin
    mPart.Click(ANode);
  end;
end;

procedure TAtlasResultsView.KeyDown(var AKey: Word);
var
  mPart: TAtlasResultsPart;
begin
  for mPart in FParts do
  begin
    if mPart.KeyDown(AKey) then
    begin
      AKey := 0;
      Exit;
    end;
  end;
end;

procedure TAtlasResultsView.HintAt(AX, AY: Integer);
var
  mNode: TTreeNode;
begin
  mNode := Tree.GetNodeAt(AX, AY);
  if mNode = FHintNode then
  begin
    Exit;
  end;
  FHintNode := mNode;
  Tree.Hint := DataOf(mNode).Hint;
  Application.CancelHint;
end;

{ TAtlasResultsPart }

constructor TAtlasResultsPart.Create(AView: TAtlasResultsView);
begin
  inherited Create;
  FView := AView;
end;

procedure TAtlasResultsPart.Reset;
begin
end;

function TAtlasResultsPart.Expand(ANode: TTreeNode; const AData: TAtlasResultsNode;
  var AAllowExpansion: Boolean): Boolean;
begin
  Result := False;
end;

function TAtlasResultsPart.Open(const AData: TAtlasResultsNode): Boolean;
begin
  Result := False;
end;

procedure TAtlasResultsPart.Popup;
begin
end;

procedure TAtlasResultsPart.Click(ANode: TTreeNode);
begin
end;

function TAtlasResultsPart.KeyDown(AKey: Word): Boolean;
begin
  Result := False;
end;

{ TAtlasResultsControls }

class function TAtlasResultsControls.Check(AOwner: TComponent; AParent: TWinControl; AAlign: TAlign;
  AWidth: Integer; const ACaption: string; AOnClick: TNotifyEvent): TCheckBox;
begin
  Result := TCheckBox.Create(AOwner);
  Result.Parent := AParent;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
  Result.Width := AWidth;
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
end;

class function TAtlasResultsControls.Button(AOwner: TComponent; AParent: TWinControl; AAlign: TAlign;
  AWidth: Integer; const ACaption: string; AOnClick: TNotifyEvent): TButton;
begin
  Result := TButton.Create(AOwner);
  Result.Parent := AParent;
  Result.Align := AAlign;
  Result.AlignWithMargins := True;
  Result.Width := AWidth;
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
end;

class function TAtlasResultsControls.Radio(AOwner: TComponent; AParent: TWinControl; AWidth: Integer;
  const ACaption: string; AOnClick: TNotifyEvent): TRadioButton;
begin
  // Ohne Align: die Leisten sind fließend (TFlowPanel) und ordnen nach Erzeugungsreihenfolge.
  Result := TRadioButton.Create(AOwner);
  Result.Parent := AParent;
  Result.AlignWithMargins := True;
  Result.Width := AWidth;
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
end;

class function TAtlasResultsControls.MenuItem(AMenu: TPopupMenu; const ACaption: string;
  AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(AMenu);
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
  AMenu.Items.Add(Result);
end;

class function TAtlasResultsControls.Bar(AOwner: TComponent; AView: TAtlasResultsView): TFlowPanel;
begin
  // Fließende Leiste: bei schmalem Fenster brechen die Bedienelemente in weitere Zeilen um.
  Result := TFlowPanel.Create(AOwner);
  Result.Visible := False;
  Result.Top := AView.Header.Top + AView.Header.Height;
  Result.Align := alTop;
  Result.Parent := AView.Host;
  Result.BevelOuter := bvNone;
  Result.ShowCaption := False;
  Result.ParentBackground := True;
  Result.AutoWrap := True;
  Result.AutoSize := True;
end;

end.
