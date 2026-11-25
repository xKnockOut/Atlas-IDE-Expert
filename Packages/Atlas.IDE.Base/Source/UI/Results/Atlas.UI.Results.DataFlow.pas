unit Atlas.UI.Results.DataFlow;

// Datenfluss (#690) im Ergebnisfenster: je Stelle „Art: Ausdruck · über X   Datei:Zeile: Quelltextzeile“,
// zusammengefasste Stellen mit ihren Fundorten darunter, dann die Quellen bzw. Ziele (← bzw. →), die beim Aufklappen
// über OnExpand die nächste Ebene holen, bis zur Tiefengrenze. Konstanten, Stellen außerhalb des Projekts und Zyklen
// bleiben Blätter. Oben die Filter „Nur Projektcode“ und „Tests ausblenden“ (OnFilter).
// OnExpand antwortet aus dem Hintergrund: Der Knoten zeigt „…“, bis die Ebene da ist.

interface

uses
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Atlas.Plugin.Lsp.DataFlow,
  Atlas.Core.Results.DataFlow,
  Atlas.UI.Results.View;

type
  /// <summary>Antwort auf TAtlasDataFlowExpand im Hauptthread; leer, wenn die Anfrage scheiterte.</summary>
  TAtlasDataFlowLoaded = reference to procedure(const AResult: TAtlasDataFlowResult);
  /// <summary>Nächste Ebene des Datenflusses (#690) unter ASource; APath: Schlüssel der Vorfahren samt ASource.
  /// ADone genau einmal, gleich oder später.</summary>
  TAtlasDataFlowExpand = reference to procedure(ADirection: TAtlasDataFlowDirection;
    const ASource: TAtlasDataFlowSymbol; const APath: TArray<string>; const ADone: TAtlasDataFlowLoaded);
  /// <summary>Filter des Datenflusses geändert: die erste Ebene neu holen.</summary>
  TAtlasDataFlowFilter = reference to procedure(AOnlyProject, AExcludeTests: Boolean);

  TAtlasResultsFlowPart = class(TAtlasResultsPart)
  private type
    TParts = record
      Bar: TFlowPanel;
      OnlyProject: TCheckBox;
      ExcludeTests: TCheckBox;
    end;
    THandlers = record
      OnExpand: TAtlasDataFlowExpand;
      OnFilter: TAtlasDataFlowFilter;
    end;
  private
    FParts: TParts;
    FHandlers: THandlers;
    FShows: Boolean;
    FDirection: TAtlasDataFlowDirection;
    FMaxDepth: Integer;
    FSettingFilter: Boolean;
    procedure AddNodes(AParent: TTreeNode; const ANodes: TArray<TAtlasDataFlowNode>; ALevel: Integer;
      const APath: TArray<string>);
    procedure AddChild(AParent: TTreeNode; const AChild: TAtlasDataFlowChild; ALevel: Integer;
      const APath: TArray<string>);
    procedure FilterClick(Sender: TObject);
    /// <summary>Ebene zum Knoten mit ALoadId ist da; ALevel und APath wie beim Aufklappen.</summary>
    procedure Loaded(ALoadId, ALevel: Integer; const APath: TArray<string>; const AFlow: TAtlasDataFlowResult);
  protected
    procedure Reset; override;
    function Expand(ANode: TTreeNode; const AData: TAtlasResultsNode; var AAllowExpansion: Boolean): Boolean;
      override;
  public
    constructor Create(AView: TAtlasResultsView);
    /// <summary>Erste Ebene; AMaxDepth = navigation.dataFlow.maxDepth, die Filter wie angefragt.</summary>
    procedure Show(const ATitle: string; ADirection: TAtlasDataFlowDirection; const AResult: TAtlasDataFlowResult;
      AMaxDepth: Integer; AOnlyProject, AExcludeTests: Boolean);
    /// <summary>Zeigt gerade einen Datenfluss.</summary>
    property Shows: Boolean read FShows;
    property OnlyProjectCheck: TCheckBox read FParts.OnlyProject;
    property ExcludeTestsCheck: TCheckBox read FParts.ExcludeTests;
    property OnExpand: TAtlasDataFlowExpand read FHandlers.OnExpand write FHandlers.OnExpand;
    property OnFilter: TAtlasDataFlowFilter read FHandlers.OnFilter write FHandlers.OnFilter;
  end;

implementation

uses
  Vcl.Controls,
  Atlas.UI.Results.Strings,
  Atlas.UI.Results.Texts;

const
  /// <summary>Breite der Filter-Häkchen in der Leiste bei 96 dpi.</summary>
  cFilterCheckWidth = 150;

{ TAtlasResultsFlowPart }

constructor TAtlasResultsFlowPart.Create(AView: TAtlasResultsView);
begin
  inherited Create(AView);
  // Filter; nur sichtbar, solange ein Datenfluss gezeigt wird.
  // Fließende Leiste: Reihenfolge = Erzeugungsreihenfolge, bei schmalem Fenster Umbruch.
  FParts.Bar := TAtlasResultsControls.Bar(AView.Host, AView);
  FParts.OnlyProject := TAtlasResultsControls.Check(AView.Host, FParts.Bar, alNone, cFilterCheckWidth,
    TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowOnlyProject), FilterClick);
  FParts.ExcludeTests := TAtlasResultsControls.Check(AView.Host, FParts.Bar, alNone, cFilterCheckWidth,
    TAtlasResultsStrings.Text(TAtlasResultsTextId.DataFlowExcludeTests), FilterClick);
end;

procedure TAtlasResultsFlowPart.Reset;
begin
  FShows := False;
  FParts.Bar.Visible := False;
end;

/// <summary>Antwort für den Knoten mit ALoadId an APart.Loaded.</summary>
function LoadedFor(APart: TAtlasResultsFlowPart; ALoadId, ALevel: Integer;
  const APath: TArray<string>): TAtlasDataFlowLoaded;
var
  mPath: TArray<string>;
begin
  mPath := Copy(APath);
  Result :=
    procedure(const AFlow: TAtlasDataFlowResult)
    begin
      APart.Loaded(ALoadId, ALevel, mPath, AFlow);
    end;
end;

function TAtlasResultsFlowPart.Expand(ANode: TTreeNode; const AData: TAtlasResultsNode;
  var AAllowExpansion: Boolean): Boolean;
var
  mDone: TAtlasDataFlowLoaded;
begin
  Result := AData.Kind = TAtlasResultsNodeKind.FlowSource;
  if not Result then
  begin
    Exit;
  end;
  mDone := LoadedFor(Self, View.BeginLoad(ANode), AData.FlowLevel + 1, AData.FlowPath);
  // Der Platzhalter „…“ bleibt stehen, bis die Ebene da ist; kommt sie gleich, ersetzt Loaded ihn schon hier.
  if Assigned(FHandlers.OnExpand) then
  begin
    FHandlers.OnExpand(FDirection, AData.FlowSource, AData.FlowPath, mDone);
  end
  else
  begin
    mDone(Default(TAtlasDataFlowResult));
  end;
  AAllowExpansion := ANode.HasChildren;
end;

procedure TAtlasResultsFlowPart.Loaded(ALoadId, ALevel: Integer; const APath: TArray<string>;
  const AFlow: TAtlasDataFlowResult);
var
  mNode: TTreeNode;
begin
  mNode := View.NodeOfLoad(ALoadId);
  if mNode = nil then
  begin
    Exit;
  end;
  View.Tree.Items.BeginUpdate;
  try
    mNode.DeleteChildren;
    AddNodes(mNode, AFlow.Nodes, ALevel, APath);
  finally
    View.Tree.Items.EndUpdate;
  end;
end;

procedure TAtlasResultsFlowPart.AddNodes(AParent: TTreeNode; const ANodes: TArray<TAtlasDataFlowNode>;
  ALevel: Integer; const APath: TArray<string>);
var
  mNode: TAtlasDataFlowNode;
  mChild: TAtlasDataFlowChild;
  mPlace: TAtlasDataFlowPlace;
  mFlowNode: TTreeNode;
begin
  for mNode in ANodes do
  begin
    mPlace := TAtlasDataFlowTree.FirstPlace(mNode);
    mFlowNode := View.AddNode(AParent, TAtlasResultsTexts.FlowNodeText(mNode),
      TAtlasResultsNode.Place(TAtlasResultsNodeKind.Flow, mPlace.FileName, mPlace.Line, mPlace.Character));
    for mChild in TAtlasDataFlowTree.Children(mNode, ALevel, FMaxDepth) do
    begin
      AddChild(mFlowNode, mChild, ALevel, APath);
    end;
  end;
end;

procedure TAtlasResultsFlowPart.AddChild(AParent: TTreeNode; const AChild: TAtlasDataFlowChild; ALevel: Integer;
  const APath: TArray<string>);
var
  mData: TAtlasResultsNode;
  mSourceNode: TTreeNode;
begin
  if AChild.Kind = TAtlasDataFlowChildKind.Place then
  begin
    View.AddNode(AParent, TAtlasResultsTexts.FlowPlaceText(AChild.Place),
      TAtlasResultsNode.Place(TAtlasResultsNodeKind.FlowPlace, AChild.Place.FileName, AChild.Place.Line,
      AChild.Place.Character));
    Exit;
  end;
  mData := TAtlasResultsNode.Place(TAtlasResultsNodeKind.FlowSource, AChild.Source.FileName, AChild.Source.Line,
    AChild.Source.Character);
  mData.FlowSource := AChild.Source;
  mData.FlowPath := TAtlasDataFlowTree.ChildPath(APath, AChild.Source.Key);
  mData.FlowLevel := ALevel;
  mData.Loaded := not AChild.Expandable;
  mSourceNode := View.AddNode(AParent, TAtlasResultsTexts.FlowSourceText(AChild, FDirection), mData);
  if AChild.Expandable then
  begin
    // Platzhalter, damit sich die Quelle aufklappen lässt; geladen wird erst dann.
    View.AddNode(mSourceNode, '…', TAtlasResultsNode.Create(TAtlasResultsNodeKind.Placeholder));
  end;
end;

procedure TAtlasResultsFlowPart.FilterClick(Sender: TObject);
begin
  if FSettingFilter or not FShows or not Assigned(FHandlers.OnFilter) then
  begin
    Exit;
  end;
  FHandlers.OnFilter(FParts.OnlyProject.Checked, FParts.ExcludeTests.Checked);
end;

procedure TAtlasResultsFlowPart.Show(const ATitle: string; ADirection: TAtlasDataFlowDirection;
  const AResult: TAtlasDataFlowResult; AMaxDepth: Integer; AOnlyProject, AExcludeTests: Boolean);
begin
  View.Clear(ATitle);
  FShows := True;
  FDirection := ADirection;
  FMaxDepth := TAtlasDataFlowTree.ClampDepth(AMaxDepth);
  FSettingFilter := True;
  try
    FParts.OnlyProject.Checked := AOnlyProject;
    FParts.ExcludeTests.Checked := AExcludeTests;
  finally
    FSettingFilter := False;
  end;
  FParts.Bar.Visible := True;
  View.Tree.Items.BeginUpdate;
  try
    AddNodes(nil, AResult.Nodes, 1, TArray<string>.Create(AResult.Symbol.Key));
  finally
    View.Tree.Items.EndUpdate;
  end;
  View.Select(nil);
end;

end.
