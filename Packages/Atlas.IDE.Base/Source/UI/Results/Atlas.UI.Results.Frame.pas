unit Atlas.UI.Results.Frame;

// Inhalt des Ergebnisfensters (#400), reine VCL: oben eine Titelzeile mit dem Atlas-Symbol (#751), darunter ein
// Baum. Doppelklick oder Enter springt über OnOpen zur Stelle. Was der Baum zeigt, liefern die Teile, je einer pro
// Darstellung: Entries (Fundstellen, erschlossene Treffer #1119), Hierarchy (Hierarchien und Aufrufdiagramm #1122),
// Changes („Atlas-Änderungen“ #721), Items (Listen mit Kennungen #1455, etwa Notizen #545), Path (Weg zwischen
// Symbolen #1117), Impact (Auswirkungsanalyse #1120), Flow (Datenfluss #690) und Issues (#1275). Ereignisse des
// Baums gehen über TAtlasResultsView an die Teile. Die DFM ist leer, weil TCustomFrame.Create für abgeleitete Frames
// eine Ressource verlangt; aufgebaut wird im Code. Die IDE-Schicht bettet den Frame in ein andockbares Fenster ein.

interface

uses
  System.Classes,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Atlas.UI.Style.Symbol,
  Atlas.UI.Results.View,
  Atlas.UI.Results.Entries,
  Atlas.UI.Results.Hierarchy,
  Atlas.UI.Results.Changes,
  Atlas.UI.Results.Items,
  Atlas.UI.Results.SymbolPath,
  Atlas.UI.Results.Impact,
  Atlas.UI.Results.DataFlow,
  Atlas.UI.Results.Issues;

type
  TAtlasResultsFrame = class(TFrame)
  private type
    TParts = record
      Entries: TAtlasResultsEntriesPart;
      Hierarchy: TAtlasResultsHierarchyPart;
      Changes: TAtlasResultsChangesPart;
      Items: TAtlasResultsItemsPart;
      Path: TAtlasResultsPathPart;
      Impact: TAtlasResultsImpactPart;
      Flow: TAtlasResultsFlowPart;
      Issues: TAtlasResultsIssuesPart;
    end;
  private
    FSymbol: TAtlasSymbolImage;
    FView: TAtlasResultsView;
    FParts: TParts;
    function CreateHeader: TPanel;
    function CreateTree: TTreeView;
    procedure CreateParts;
    function GetTree: TTreeView;
    function GetMenu: TPopupMenu;
    function GetOnOpen: TAtlasResultsOpen;
    procedure SetOnOpen(const AValue: TAtlasResultsOpen);
    procedure TreeClick(Sender: TObject);
    procedure TreeDblClick(Sender: TObject);
    procedure TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
    procedure TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure MenuPopup(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    property Tree: TTreeView read GetTree;
    property Menu: TPopupMenu read GetMenu;
    property Symbol: TAtlasSymbolImage read FSymbol;
    property OnOpen: TAtlasResultsOpen read GetOnOpen write SetOnOpen;
    /// <summary>Fundstellen, auch nach Treffersicherheit (#1119).</summary>
    property Entries: TAtlasResultsEntriesPart read FParts.Entries;
    /// <summary>Hierarchien und Aufrufdiagramm (#1122).</summary>
    property Hierarchy: TAtlasResultsHierarchyPart read FParts.Hierarchy;
    /// <summary>Liste „Atlas-Änderungen“ (#721).</summary>
    property Changes: TAtlasResultsChangesPart read FParts.Changes;
    /// <summary>Listen mit Kennungen eines Moduls (#1455, etwa die Notizen #545).</summary>
    property Items: TAtlasResultsItemsPart read FParts.Items;
    /// <summary>Weg zwischen Symbolen (#1117).</summary>
    property Path: TAtlasResultsPathPart read FParts.Path;
    /// <summary>Auswirkungsanalyse (#1120).</summary>
    property Impact: TAtlasResultsImpactPart read FParts.Impact;
    /// <summary>Datenfluss (#690).</summary>
    property Flow: TAtlasResultsFlowPart read FParts.Flow;
    /// <summary>Issues zu einer Methode (#1275).</summary>
    property Issues: TAtlasResultsIssuesPart read FParts.Issues;
  end;

implementation

uses
  Winapi.Windows,
  Atlas.Core.Style.Symbol;

{$R *.dfm}

{ TAtlasResultsFrame }

constructor TAtlasResultsFrame.Create(AOwner: TComponent);
var
  mHeader: TPanel;
  mTitle: TLabel;
  mMenu: TPopupMenu;
begin
  inherited Create(AOwner);
  mHeader := CreateHeader;
  mTitle := TLabel.Create(Self);
  mTitle.Parent := mHeader;
  mTitle.Align := alClient;
  mTitle.Layout := tlCenter;
  mTitle.AlignWithMargins := True;
  mTitle.ShowAccelChar := False;
  mTitle.EllipsisPosition := epEndEllipsis;
  mMenu := TPopupMenu.Create(Self);
  mMenu.OnPopup := MenuPopup;
  FView := TAtlasResultsView.Create(Self, mHeader, mTitle, CreateTree, mMenu);
  FView.Tree.PopupMenu := mMenu;
  CreateParts;
end;

destructor TAtlasResultsFrame.Destroy;
begin
  FView.Free;
  inherited;
end;

function TAtlasResultsFrame.CreateHeader: TPanel;
begin
  // Titelzeile: Symbol (#751) links, Titel in der Mitte, Schalter der Teile rechts.
  Result := TPanel.Create(Self);
  Result.Parent := Self;
  Result.Align := alTop;
  Result.BevelOuter := bvNone;
  Result.ParentBackground := True;
  Result.Height := Result.ScaleValue(22);
  FSymbol := TAtlasSymbolImage.Create(Self);
  FSymbol.Parent := Result;
  FSymbol.LogicalSize := TAtlasSymbol.cMenuSize;
  FSymbol.Align := alLeft;
  FSymbol.AlignWithMargins := True;
end;

function TAtlasResultsFrame.CreateTree: TTreeView;
begin
  Result := TTreeView.Create(Self);
  Result.Parent := Self;
  Result.Align := alClient;
  Result.ReadOnly := True;
  Result.HideSelection := False;
  Result.RowSelect := True;
  Result.ShowLines := False;
  Result.BorderStyle := bsNone;
  Result.OnDblClick := TreeDblClick;
  Result.OnClick := TreeClick;
  Result.OnKeyDown := TreeKeyDown;
  Result.OnExpanding := TreeExpanding;
  Result.OnMouseMove := TreeMouseMove;
  Result.ShowHint := True;
end;

procedure TAtlasResultsFrame.CreateParts;
begin
  // Reihenfolge wie die Schalter rechts in der Titelzeile und die Einträge im Kontextmenü.
  FParts.Entries := TAtlasResultsEntriesPart.Create(FView);
  FView.Add(FParts.Entries);
  FParts.Hierarchy := TAtlasResultsHierarchyPart.Create(FView);
  FView.Add(FParts.Hierarchy);
  FParts.Impact := TAtlasResultsImpactPart.Create(FView);
  FView.Add(FParts.Impact);
  FParts.Flow := TAtlasResultsFlowPart.Create(FView);
  FView.Add(FParts.Flow);
  FParts.Changes := TAtlasResultsChangesPart.Create(FView);
  FView.Add(FParts.Changes);
  FParts.Items := TAtlasResultsItemsPart.Create(FView);
  FView.Add(FParts.Items);
  FParts.Path := TAtlasResultsPathPart.Create(FView);
  FView.Add(FParts.Path);
  FParts.Issues := TAtlasResultsIssuesPart.Create(FView);
  FView.Add(FParts.Issues);
end;

function TAtlasResultsFrame.GetTree: TTreeView;
begin
  Result := FView.Tree;
end;

function TAtlasResultsFrame.GetMenu: TPopupMenu;
begin
  Result := FView.Menu;
end;

function TAtlasResultsFrame.GetOnOpen: TAtlasResultsOpen;
begin
  Result := FView.OnOpen;
end;

procedure TAtlasResultsFrame.SetOnOpen(const AValue: TAtlasResultsOpen);
begin
  FView.OnOpen := AValue;
end;

procedure TAtlasResultsFrame.MenuPopup(Sender: TObject);
begin
  FView.Popup;
end;

procedure TAtlasResultsFrame.TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
begin
  FView.Expanding(Node, AllowExpansion);
end;

procedure TAtlasResultsFrame.TreeMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  FView.HintAt(X, Y);
end;

procedure TAtlasResultsFrame.TreeClick(Sender: TObject);
var
  mWhere: TPoint;
  mNode: TTreeNode;
begin
  // Nur ein Klick auf die schon gewählte Zeile, nicht auf das Aufklappzeichen (Issues #1275).
  if not Tree.HandleAllocated then
  begin
    Exit;
  end;
  mWhere := Tree.ScreenToClient(Mouse.CursorPos);
  if not (htOnItem in Tree.GetHitTestInfoAt(mWhere.X, mWhere.Y)) then
  begin
    Exit;
  end;
  mNode := Tree.GetNodeAt(mWhere.X, mWhere.Y);
  if (mNode <> nil) and (mNode = Tree.Selected) then
  begin
    FView.Click(mNode);
  end;
end;

procedure TAtlasResultsFrame.TreeDblClick(Sender: TObject);
begin
  // Ein Issue hat schon der Klick geöffnet; der Doppelklick klappt es nur auf.
  if FView.DataOf(Tree.Selected).Kind = TAtlasResultsNodeKind.Issue then
  begin
    Exit;
  end;
  FView.OpenSelected;
end;

procedure TAtlasResultsFrame.TreeKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    FView.OpenSelected;
    Key := 0;
  end
  else
  begin
    FView.KeyDown(Key);
  end;
end;

end.
