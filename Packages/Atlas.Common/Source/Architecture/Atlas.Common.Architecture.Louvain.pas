unit Atlas.Common.Architecture.Louvain;

// Gruppierung nach dem Louvain-Verfahren (#1118): Knoten eines ungerichteten,
// gewichteten Graphen in Gruppen mit vielen Kanten innen und wenigen außen
// (größte Modularität).
//
// - Stufe 1: Jeder Knoten wechselt in die Nachbargruppe mit dem größten
//   Gewinn, bis sich nichts mehr ändert. Stufe 2: Jede Gruppe wird zu einem
//   Knoten; dann wieder Stufe 1, bis keine Gruppe mehr verschmilzt.
// - Deterministisch: Die Knoten laufen in der Reihenfolge, in der der Aufrufer
//   sie übergibt (Architektur: nach Unit-Name). Bei gleichem Gewinn gewinnt
//   die Gruppe mit der kleineren Nummer; ein Wechsel braucht echten Gewinn.
// - Ergebnis: Gruppennummer je Knoten, fortlaufend ab 0 in der Reihenfolge
//   des ersten Knotens der Gruppe.
// - Auflösung γ (#1366): Der Gewinn eines Wechsels ist Kanten zur Zielgruppe
//   − γ · Grad der Zielgruppe · Grad des Knotens / 2m. γ > 1 ergibt mehr und
//   kleinere Gruppen, γ < 1 weniger und größere; 1 ist die klassische
//   Modularität.

interface

uses
  System.SysUtils;

type
  TLouvainEdge = record
    A: Integer;
    B: Integer;
    Weight: Double;
  end;

  TLouvain = class
  public
    /// <summary>Gruppe je Knoten 0..ANodeCount-1. Kanten mit A = B oder Gewicht &lt;= 0 zählen nicht; doppelte
    /// Kanten addieren sich.</summary>
    class function Communities(ANodeCount: Integer; const AEdges: TArray<TLouvainEdge>): TArray<Integer>;
      overload; static;
    /// <summary>Wie oben mit Auflösung AResolution (γ, größer 0; 1 = wie oben).</summary>
    class function Communities(ANodeCount: Integer; const AEdges: TArray<TLouvainEdge>;
      AResolution: Double): TArray<Integer>; overload; static;
    /// <summary>Modularität einer Einteilung (zum Prüfen und für Tests).</summary>
    class function Modularity(ANodeCount: Integer; const AEdges: TArray<TLouvainEdge>;
      const ACommunities: TArray<Integer>): Double; overload; static;
    /// <summary>Wie oben mit Auflösung AResolution: Summe je Gruppe Innen/2m − γ · (Grad/2m)².</summary>
    class function Modularity(ANodeCount: Integer; const AEdges: TArray<TLouvainEdge>;
      const ACommunities: TArray<Integer>; AResolution: Double): Double; overload; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Collections;

type
  TNeighbor = record
    Node: Integer;
    Weight: Double;
  end;

  /// <summary>Ungerichteter Graph als Nachbarlisten; Schleifen (Gewicht innerhalb eines verschmolzenen Knotens)
  /// getrennt in SelfWeight.</summary>
  TLevelGraph = record
    Neighbors: TArray<TArray<TNeighbor>>;
    SelfWeight: TArray<Double>;
    Degree: TArray<Double>;
    /// <summary>Summe aller Grade (= doppeltes Kantengewicht, 2m).</summary>
    Total: Double;
  end;

const
  Epsilon = 1E-12;

/// <summary>AWeight zum Gewicht des Nachbarn ATo in AMap addieren.</summary>
procedure AddWeight(AMap: TDictionary<Integer, Double>; ATo: Integer; AWeight: Double);
var
  mWeight: Double;
begin
  if not AMap.TryGetValue(ATo, mWeight) then
  begin
    mWeight := 0;
  end;
  AMap.AddOrSetValue(ATo, mWeight + AWeight);
end;

/// <summary>Kante liegt im Knotenbereich und hat ein positives Gewicht.</summary>
function IsValidEdge(const AEdge: TLouvainEdge; ANodeCount: Integer): Boolean;
begin
  Result := (AEdge.Weight > 0) and (Min(AEdge.A, AEdge.B) >= 0) and (Max(AEdge.A, AEdge.B) < ANodeCount);
end;

/// <summary>Nachbarliste und Grad von ANode aus AMap (Nachbarn sortiert, damit die Reihenfolge nicht vom Hash
/// abhängt).</summary>
procedure FillNode(var AGraph: TLevelGraph; ANode: Integer; AMap: TDictionary<Integer, Double>);
var
  mKeys: TArray<Integer>;
  mKey: Integer;
  mNeighbor: TNeighbor;
begin
  mKeys := AMap.Keys.ToArray;
  TArray.Sort<Integer>(mKeys);
  for mKey in mKeys do
  begin
    mNeighbor.Node := mKey;
    mNeighbor.Weight := AMap[mKey];
    AGraph.Neighbors[ANode] := AGraph.Neighbors[ANode] + [mNeighbor];
    AGraph.Degree[ANode] := AGraph.Degree[ANode] + mNeighbor.Weight;
  end;
  // Eine Schleife zählt im Grad doppelt (beide Enden).
  AGraph.Degree[ANode] := AGraph.Degree[ANode] + 2 * AGraph.SelfWeight[ANode];
  AGraph.Total := AGraph.Total + AGraph.Degree[ANode];
end;

function BuildGraph(ANodeCount: Integer; const AEdges: TArray<TLouvainEdge>): TLevelGraph;
var
  mMaps: TArray<TDictionary<Integer, Double>>;
  mEdge: TLouvainEdge;
  mNode: Integer;
begin
  // Result kann auf den Graphen der vorigen Stufe zeigen (Rückgabe per Referenz): erst leeren.
  Result := Default(TLevelGraph);
  SetLength(Result.Neighbors, ANodeCount);
  SetLength(Result.SelfWeight, ANodeCount);
  SetLength(Result.Degree, ANodeCount);
  Result.Total := 0;
  SetLength(mMaps, ANodeCount);
  for mNode := 0 to ANodeCount - 1 do
  begin
    mMaps[mNode] := TDictionary<Integer, Double>.Create;
  end;
  try
    for mEdge in AEdges do
    begin
      if not IsValidEdge(mEdge, ANodeCount) then
      begin
        Continue;
      end;
      if mEdge.A = mEdge.B then
      begin
        Result.SelfWeight[mEdge.A] := Result.SelfWeight[mEdge.A] + mEdge.Weight;
        Continue;
      end;
      AddWeight(mMaps[mEdge.A], mEdge.B, mEdge.Weight);
      AddWeight(mMaps[mEdge.B], mEdge.A, mEdge.Weight);
    end;
    for mNode := 0 to ANodeCount - 1 do
    begin
      FillNode(Result, mNode, mMaps[mNode]);
    end;
  finally
    for mNode := 0 to ANodeCount - 1 do
    begin
      mMaps[mNode].Free;
    end;
  end;
end;

type
  /// <summary>Stufe 1 der Louvain-Methode: Knoten wandern in die Nachbargruppe mit dem größten Gewinn.</summary>
  TNodeMover = class
  private
    FGraph: TLevelGraph;
    FResolution: Double;
    FTot: TArray<Double>;
    FLinks: TDictionary<Integer, Double>;
    FCandidates: TArray<Integer>;
    /// <summary>Gewicht zu jeder Nachbargruppe von ANode in FLinks, die Gruppen sortiert in FCandidates.</summary>
    procedure CollectLinks(ANode: Integer; const ACommunity: TArray<Integer>);
    function LinkWeight(ACommunity: Integer): Double;
    /// <summary>Beste Gruppe für ANode, der aus ACurrent herausgenommen ist (die eigene mit ihrem Gewinn).</summary>
    function BestCommunity(ANode, ACurrent: Integer): Integer;
    /// <summary>ANode in die beste Gruppe verschieben; True, wenn er die Gruppe gewechselt hat.</summary>
    function MoveNode(ANode: Integer; var ACommunity: TArray<Integer>): Boolean;
  public
    constructor Create(const AGraph: TLevelGraph; AResolution: Double; const ACommunity: TArray<Integer>);
    destructor Destroy; override;
    function Run(var ACommunity: TArray<Integer>): Boolean;
  end;

constructor TNodeMover.Create(const AGraph: TLevelGraph; AResolution: Double; const ACommunity: TArray<Integer>);
var
  mNode: Integer;
begin
  inherited Create;
  FGraph := AGraph;
  FResolution := AResolution;
  SetLength(FTot, Length(AGraph.Neighbors));
  for mNode := 0 to High(AGraph.Neighbors) do
  begin
    FTot[ACommunity[mNode]] := FTot[ACommunity[mNode]] + AGraph.Degree[mNode];
  end;
  FLinks := TDictionary<Integer, Double>.Create;
end;

destructor TNodeMover.Destroy;
begin
  FLinks.Free;
  inherited;
end;

procedure TNodeMover.CollectLinks(ANode: Integer; const ACommunity: TArray<Integer>);
var
  mNeighbor: TNeighbor;
  mCandidate: Integer;
begin
  FLinks.Clear;
  FCandidates := nil;
  for mNeighbor in FGraph.Neighbors[ANode] do
  begin
    mCandidate := ACommunity[mNeighbor.Node];
    if not FLinks.ContainsKey(mCandidate) then
    begin
      FCandidates := FCandidates + [mCandidate];
    end;
    FLinks.AddOrSetValue(mCandidate, LinkWeight(mCandidate) + mNeighbor.Weight);
  end;
  TArray.Sort<Integer>(FCandidates);
end;

function TNodeMover.LinkWeight(ACommunity: Integer): Double;
begin
  if not FLinks.TryGetValue(ACommunity, Result) then
  begin
    Result := 0;
  end;
end;

function TNodeMover.BestCommunity(ANode, ACurrent: Integer): Integer;
var
  mCandidate: Integer;
  mKi, mBestGain, mGain: Double;
begin
  mKi := FGraph.Degree[ANode];
  Result := ACurrent;
  mBestGain := LinkWeight(ACurrent) - FResolution * FTot[ACurrent] * mKi / FGraph.Total;
  for mCandidate in FCandidates do
  begin
    if mCandidate = ACurrent then
    begin
      Continue;
    end;
    mGain := FLinks[mCandidate] - FResolution * FTot[mCandidate] * mKi / FGraph.Total;
    if mGain > mBestGain + Epsilon then
    begin
      mBestGain := mGain;
      Result := mCandidate;
    end;
  end;
end;

function TNodeMover.MoveNode(ANode: Integer; var ACommunity: TArray<Integer>): Boolean;
var
  mCurrent, mBest: Integer;
begin
  mCurrent := ACommunity[ANode];
  CollectLinks(ANode, ACommunity);
  // Knoten herausnehmen, dann die beste Gruppe suchen.
  FTot[mCurrent] := FTot[mCurrent] - FGraph.Degree[ANode];
  mBest := BestCommunity(ANode, mCurrent);
  FTot[mBest] := FTot[mBest] + FGraph.Degree[ANode];
  Result := mBest <> mCurrent;
  if Result then
  begin
    ACommunity[ANode] := mBest;
  end;
end;

function TNodeMover.Run(var ACommunity: TArray<Integer>): Boolean;
var
  mNode: Integer;
  mMoved: Boolean;
begin
  Result := False;
  repeat
    mMoved := False;
    for mNode := 0 to High(FGraph.Neighbors) do
    begin
      if MoveNode(mNode, ACommunity) then
      begin
        mMoved := True;
        Result := True;
      end;
    end;
  until not mMoved;
end;

/// <summary>Stufe 1 auf AGraph mit Auflösung AResolution: Gruppe je Knoten; True, wenn sich etwas bewegt hat.
/// </summary>
function MoveNodes(const AGraph: TLevelGraph; AResolution: Double; var ACommunity: TArray<Integer>): Boolean;
var
  mMover: TNodeMover;
begin
  if AGraph.Total <= 0 then
  begin
    Exit(False);
  end;
  mMover := TNodeMover.Create(AGraph, AResolution, ACommunity);
  try
    Result := mMover.Run(ACommunity);
  finally
    mMover.Free;
  end;
end;

/// <summary>Nummeriert die Gruppen fortlaufend in der Reihenfolge des ersten Knotens; liefert die Anzahl.</summary>
function Renumber(var ACommunity: TArray<Integer>): Integer;
var
  Map: TDictionary<Integer, Integer>;
  Node, Number: Integer;
begin
  Map := TDictionary<Integer, Integer>.Create;
  try
    for Node := 0 to High(ACommunity) do
    begin
      if not Map.TryGetValue(ACommunity[Node], Number) then
      begin
        Number := Map.Count;
        Map.Add(ACommunity[Node], Number);
      end;
      ACommunity[Node] := Number;
    end;
    Result := Map.Count;
  finally
    Map.Free;
  end;
end;

/// <summary>Stufe 2: jede Gruppe ein Knoten, Kanten summiert, Kanten innerhalb als Schleife.</summary>
function Aggregate(const AGraph: TLevelGraph; const ACommunity: TArray<Integer>): TArray<TLouvainEdge>;
var
  Node: Integer;
  Neighbor: TNeighbor;
  Edge: TLouvainEdge;
  Edges: TList<TLouvainEdge>;
begin
  Edges := TList<TLouvainEdge>.Create;
  try
    for Node := 0 to High(AGraph.Neighbors) do
    begin
      if AGraph.SelfWeight[Node] > 0 then
      begin
        Edge.A := ACommunity[Node];
        Edge.B := ACommunity[Node];
        Edge.Weight := AGraph.SelfWeight[Node];
        Edges.Add(Edge);
      end;
      for Neighbor in AGraph.Neighbors[Node] do
      begin
        // Jede ungerichtete Kante steht zweimal in den Listen; nur einmal übernehmen.
        if Neighbor.Node < Node then
        begin
          Continue;
        end;
        Edge.A := ACommunity[Node];
        Edge.B := ACommunity[Neighbor.Node];
        Edge.Weight := Neighbor.Weight;
        Edges.Add(Edge);
      end;
    end;
    Result := Edges.ToArray;
  finally
    Edges.Free;
  end;
end;

{ TLouvain }

class function TLouvain.Communities(ANodeCount: Integer; const AEdges: TArray<TLouvainEdge>): TArray<Integer>;
begin
  Result := Communities(ANodeCount, AEdges, 1);
end;

class function TLouvain.Communities(ANodeCount: Integer; const AEdges: TArray<TLouvainEdge>;
  AResolution: Double): TArray<Integer>;
var
  Graph: TLevelGraph;
  Level: TArray<Integer>;
  Node, Count, Merged: Integer;
  Edges: TArray<TLouvainEdge>;
begin
  SetLength(Result, ANodeCount);
  for Node := 0 to ANodeCount - 1 do
  begin
    Result[Node] := Node;
  end;
  Edges := AEdges;
  Count := ANodeCount;
  while Count > 0 do
  begin
    Graph := BuildGraph(Count, Edges);
    SetLength(Level, Count);
    for Node := 0 to Count - 1 do
    begin
      Level[Node] := Node;
    end;
    if not MoveNodes(Graph, AResolution, Level) then
    begin
      Break;
    end;
    Merged := Renumber(Level);
    // Zuordnung der ursprünglichen Knoten nachführen.
    for Node := 0 to ANodeCount - 1 do
    begin
      Result[Node] := Level[Result[Node]];
    end;
    // Keine Gruppe verschmolzen: weitere Stufen ändern nichts mehr.
    if Merged >= Count then
    begin
      Break;
    end;
    Edges := Aggregate(Graph, Level);
    Count := Merged;
  end;
  Renumber(Result);
end;

class function TLouvain.Modularity(ANodeCount: Integer; const AEdges: TArray<TLouvainEdge>;
  const ACommunities: TArray<Integer>): Double;
begin
  Result := Modularity(ANodeCount, AEdges, ACommunities, 1);
end;

class function TLouvain.Modularity(ANodeCount: Integer; const AEdges: TArray<TLouvainEdge>;
  const ACommunities: TArray<Integer>; AResolution: Double): Double;
var
  Graph: TLevelGraph;
  Node, Count: Integer;
  Neighbor: TNeighbor;
  Inside, Tot: TArray<Double>;
  Community: Integer;
begin
  Result := 0;
  Graph := BuildGraph(ANodeCount, AEdges);
  if Graph.Total <= 0 then
  begin
    Exit;
  end;
  Count := 0;
  for Community in ACommunities do
  begin
    if Community + 1 > Count then
    begin
      Count := Community + 1;
    end;
  end;
  SetLength(Inside, Count);
  SetLength(Tot, Count);
  for Node := 0 to ANodeCount - 1 do
  begin
    Tot[ACommunities[Node]] := Tot[ACommunities[Node]] + Graph.Degree[Node];
    Inside[ACommunities[Node]] := Inside[ACommunities[Node]] + 2 * Graph.SelfWeight[Node];
    for Neighbor in Graph.Neighbors[Node] do
    begin
      if ACommunities[Neighbor.Node] = ACommunities[Node] then
      begin
        Inside[ACommunities[Node]] := Inside[ACommunities[Node]] + Neighbor.Weight;
      end;
    end;
  end;
  for Community := 0 to Count - 1 do
  begin
    Result := Result + Inside[Community] / Graph.Total - AResolution * Sqr(Tot[Community] / Graph.Total);
  end;
end;

end.
