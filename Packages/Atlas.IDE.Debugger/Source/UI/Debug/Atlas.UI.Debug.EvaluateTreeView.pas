unit Atlas.UI.Debug.EvaluateTreeView;

// Baum der Ausdrücke in den Fenstern „Auswerten“ (#784) und „Variablen“
// (#853), reine VCL: hält den TTreeView, seinen Abgleich mit der Liste
// (TAtlasEvalTreeSync) und die Liste selbst. Aufklappen holt beim ersten Mal
// die Felder über OnExpand (der Knoten klappt erst auf, wenn sie da sind und
// der Frame neu abgleicht), Zuklappen merkt sich die Liste. Gezeichnet wird in
// den Farben des Stils des Baums: seit dem letzten Halt geänderte Werte in der
// Warnfarbe, Fehler und Platzhalter grau, fett, was TAtlasEvalTreeSync.Emphasis
// sagt. Tasten, Auswahl und Kontextmenü bleiben beim Frame.

interface

uses
  System.Classes,
  Vcl.Graphics,
  Vcl.ComCtrls,
  Atlas.Core.Debug.Evaluate,
  Atlas.UI.Debug.EvaluateTree;

type
  TAtlasEvalNodeProc = reference to procedure(ANode: TAtlasEvalNode);

  /// <summary>Gewählter Knoten des Baums; nil ohne Auswahl.</summary>
  TAtlasEvalNodeSource = function: TAtlasEvalNode of object;

  TAtlasEvalTreeView = class
  private
    FTree: TTreeView;
    // Schlüssel und Darstellung je Baumknoten: Knoten der Liste können zwischen zwei Abgleichen freigegeben sein.
    FSync: TAtlasEvalTreeSync;
    FList: TAtlasEvalList;
    FFilling: Boolean;
    FOnExpand: TAtlasEvalNodeProc;
    procedure TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
    procedure TreeCollapsing(Sender: TObject; Node: TTreeNode; var AllowCollapse: Boolean);
    procedure TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    /// <summary>Systemfarbe im Stil des Baums, nicht im globalen: Die IDE themt ihre Fenster je Formular.</summary>
    function TreeColor(AColor: TColor): TColor;
  public
    /// <summary>Hängt sich an die Ereignisse Aufklappen, Zuklappen und Zeichnen von ATree; ATree gehört dem Frame.
    /// </summary>
    constructor Create(ATree: TTreeView);
    /// <summary>Löst die Ereignisse vom Baum: Er vergeht erst mit dem Frame und darf beim Löschen seiner Knoten nicht
    /// mehr hierher fragen.</summary>
    destructor Destroy; override;
    /// <summary>Baum an die Liste angleichen und die Auswahl halten. Der Baum braucht ein Fenster.</summary>
    procedure Refresh;
    /// <summary>Knoten der Liste zum Baumknoten; nil bei Platzhaltern und Knoten, die es nicht mehr gibt.</summary>
    function NodeOf(AItem: TTreeNode): TAtlasEvalNode;
    /// <summary>Gewählter Knoten der Liste; nil ohne Auswahl, ohne Fenster oder bei einem Platzhalter.</summary>
    function SelectedNode: TAtlasEvalNode;
    /// <summary>Knoten mit AKey wählen. Der Baum braucht ein Fenster.</summary>
    procedure Select(const AKey: string);
    property Tree: TTreeView read FTree;
    property Sync: TAtlasEvalTreeSync read FSync;
    /// <summary>Liste, die der Baum zeigt; gehört der IDE-Schicht (nil: leer).</summary>
    property List: TAtlasEvalList read FList write FList;
    /// <summary>Refresh gleicht gerade ab: Auswahl- und Aufklappmeldungen des Baums kommen nicht vom Benutzer.
    /// </summary>
    property Filling: Boolean read FFilling;
    /// <summary>Erstes Aufklappen: Felder holen; Refresh erst später, nicht in der Benachrichtigung des Baums.
    /// </summary>
    property OnExpand: TAtlasEvalNodeProc read FOnExpand write FOnExpand;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette;

{ TAtlasEvalTreeView }

constructor TAtlasEvalTreeView.Create(ATree: TTreeView);
begin
  inherited Create;
  FTree := ATree;
  FSync := TAtlasEvalTreeSync.Create(ATree);
  FTree.OnExpanding := TreeExpanding;
  FTree.OnCollapsing := TreeCollapsing;
  FTree.OnCustomDrawItem := TreeCustomDrawItem;
end;

destructor TAtlasEvalTreeView.Destroy;
begin
  if FTree <> nil then
  begin
    FTree.OnExpanding := nil;
    FTree.OnCollapsing := nil;
    FTree.OnCustomDrawItem := nil;
  end;
  FreeAndNil(FSync);
  FList := nil;
  inherited Destroy;
end;

procedure TAtlasEvalTreeView.Refresh;
var
  mKeep: string;
begin
  mKeep := FSync.KeyOf(FTree.Selected);
  FFilling := True;
  try
    FSync.Sync(FList);
  finally
    FFilling := False;
  end;
  // Wurde der gewählte Knoten ersetzt (Teile eines neuen Werts), denselben Schlüssel wieder wählen.
  if (mKeep <> '') and (FSync.KeyOf(FTree.Selected) <> mKeep) then
  begin
    Select(mKeep);
  end;
end;

function TAtlasEvalTreeView.NodeOf(AItem: TTreeNode): TAtlasEvalNode;
var
  mKey: string;
begin
  // Über den Schlüssel: nil, wenn es den Knoten nicht mehr gibt.
  Result := nil;
  mKey := FSync.KeyOf(AItem);
  if (mKey <> '') and (FList <> nil) then
  begin
    Result := FList.Find(mKey);
  end;
end;

function TAtlasEvalTreeView.SelectedNode: TAtlasEvalNode;
begin
  Result := nil;
  if FTree.HandleAllocated then
  begin
    Result := NodeOf(FTree.Selected);
  end;
end;

procedure TAtlasEvalTreeView.Select(const AKey: string);
var
  mItem: TTreeNode;
begin
  mItem := FSync.ItemOf(AKey);
  if mItem <> nil then
  begin
    FTree.Selected := mItem;
  end;
end;

procedure TAtlasEvalTreeView.TreeExpanding(Sender: TObject; Node: TTreeNode; var AllowExpansion: Boolean);
var
  mNode: TAtlasEvalNode;
begin
  AllowExpansion := True;
  mNode := NodeOf(Node);
  if FFilling or (mNode = nil) then
  begin
    Exit;
  end;
  mNode.Expanded := True;
  if not mNode.ChildrenLoaded and Assigned(FOnExpand) then
  begin
    // Felder kommen später; der Frame gleicht dann mit aufgeklapptem Knoten neu ab. OnExpand darf das nicht sofort
    // tun: Der Baum steckt noch in der Benachrichtigung für diesen Knoten.
    AllowExpansion := False;
    FOnExpand(mNode);
  end;
end;

procedure TAtlasEvalTreeView.TreeCollapsing(Sender: TObject; Node: TTreeNode; var AllowCollapse: Boolean);
var
  mNode: TAtlasEvalNode;
begin
  AllowCollapse := True;
  mNode := NodeOf(Node);
  if not FFilling and (mNode <> nil) then
  begin
    mNode.Expanded := False;
  end;
end;

function TAtlasEvalTreeView.TreeColor(AColor: TColor): TColor;
begin
  Result := ColorToRGB(StyleServices(FTree).GetSystemColor(AColor));
end;

procedure TAtlasEvalTreeView.TreeCustomDrawItem(Sender: TCustomTreeView; Node: TTreeNode;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mInfo: TAtlasEvalItemInfo;
  mCanvas: TCanvas;
begin
  DefaultDraw := True;
  mCanvas := Sender.Canvas;
  // Darstellung steht am Baumknoten (FSync): Zeichnen sucht nicht in der Liste.
  mInfo := FSync.InfoOf(Node);
  mCanvas.Font.Style := [];
  if mInfo.Bold then
  begin
    mCanvas.Font.Style := [fsBold];
  end;
  if cdsSelected in State then
  begin
    mCanvas.Brush.Color := TreeColor(clHighlight);
    mCanvas.Font.Color := TreeColor(clHighlightText);
    Exit;
  end;
  mCanvas.Brush.Color := TreeColor(FTree.Color);
  case mInfo.Look of
    TAtlasEvalLook.Changed:
      mCanvas.Font.Color := ColorToRGB(TColor(TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(
        mCanvas.Brush.Color))).Warn));
    TAtlasEvalLook.Gray:
      mCanvas.Font.Color := TreeColor(clGrayText);
  else
    mCanvas.Font.Color := TreeColor(FTree.Font.Color);
  end;
end;

end.
