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

function BuildGraph(ANodeCount: Integer; const AEdges: TArray<TLouvainEdge>): TLevelGraph;
var
  Maps: TArray<TDictionary<Integer, Double>>;
  Edge: TLouvainEdge;
  Node: Integer;
  Neighbor: TNeighbor;
  Keys: TArray<Integer>;
  Key: Integer;
  Weight: Double;
begin
  // Result kann auf den Graphen der vorigen Stufe zeigen (Rückgabe per Referenz): erst leeren.
  Result := Default(TLevelGraph);
  SetLength(Result.Neighbors, ANodeCount);
  SetLength(Result.SelfWeight, ANodeCount);
  SetLength(Result.Degree, ANodeCount);
  Result.Total := 0;
  SetLength(Maps, ANodeCount);
  for Node := 0 to ANodeCount - 1 do
    Maps[Node] := TDictionary<Integer, Double>.Create;
  try
    for Edge in AEdges do
    begin
      if (Edge.Weight <= 0) or (Edge.A < 0) or (Edge.B < 0) or (Edge.A >= ANodeCount) or (Edge.B >= ANodeCount) then
        Continue;
      if Edge.A = Edge.B then
      begin
        Result.SelfWeight[Edge.A] := Result.SelfWeight[Edge.A] + Edge.Weight;
        Continue;
      end;
      if not Maps[Edge.A].TryGetValue(Edge.B, Weight) then
        Weight := 0;
      Maps[Edge.A].AddOrSetValue(Edge.B, Weight + Edge.Weight);
      if not Maps[Edge.B].TryGetValue(Edge.A, Weight) then
        Weight := 0;
      Maps[Edge.B].AddOrSetValue(Edge.A, Weight + Edge.Weight);
    end;
    for Node := 0 to ANodeCount - 1 do
    begin
      // Nachbarn sortiert, damit die Reihenfolge nicht vom Hash abhängt.
      Keys := Maps[Node].Keys.ToArray;
      TArray.Sort<Integer>(Keys);
      for Key in Keys do
      begin
        Neighbor.Node := Key;
        Neighbor.Weight := Maps[Node][Key];
        Result.Neighbors[Node] := Result.Neighbors[Node] + [Neighbor];
        Result.Degree[Node] := Result.Degree[Node] + Neighbor.Weight;
      end;
      // Eine Schleife zählt im Grad doppelt (beide Enden).
      Result.Degree[Node] := Result.Degree[Node] + 2 * Result.SelfWeight[Node];
      Result.Total := Result.Total + Result.Degree[Node];
    end;
  finally
    for Node := 0 to ANodeCount - 1 do
      Maps[Node].Free;
  end;
end;

/// <summary>Stufe 1 auf AGraph mit Auflösung AResolution: Gruppe je Knoten; True, wenn sich etwas bewegt hat.
/// </summary>
function MoveNodes(const AGraph: TLevelGraph; AResolution: Double; var ACommunity: TArray<Integer>): Boolean;
var
  Count, Node, Best, Current, Candidate, Index: Integer;
  Tot: TArray<Double>;
  Links: TDictionary<Integer, Double>;
  Neighbor: TNeighbor;
  Weight, BestGain, Gain, Ki, TwoM: Double;
  Moved: Boolean;
  Candidates: TArray<Integer>;
begin
  Result := False;
  Count := Length(AGraph.Neighbors);
  TwoM := AGraph.Total;
  if TwoM <= 0 then
    Exit;
  SetLength(Tot, Count);
  for Node := 0 to Count - 1 do
    Tot[ACommunity[Node]] := Tot[ACommunity[Node]] + AGraph.Degree[Node];
  Links := TDictionary<Integer, Double>.Create;
  try
    repeat
      Moved := False;
      for Node := 0 to Count - 1 do
      begin
        Current := ACommunity[Node];
        Ki := AGraph.Degree[Node];
        Links.Clear;
        Candidates := nil;
        for Neighbor in AGraph.Neighbors[Node] do
        begin
          Candidate := ACommunity[Neighbor.Node];
          if not Links.TryGetValue(Candidate, Weight) then
          begin
            Weight := 0;
            Candidates := Candidates + [Candidate];
          end;
          Links.AddOrSetValue(Candidate, Weight + Neighbor.Weight);
        end;
        // Knoten herausnehmen, dann die beste Gruppe suchen (die eigene steht dabei mit ihrem Gewinn).
        Tot[Current] := Tot[Current] - Ki;
        if not Links.TryGetValue(Current, Weight) then
          Weight := 0;
        Best := Current;
        BestGain := Weight - AResolution * Tot[Current] * Ki / TwoM;
        TArray.Sort<Integer>(Candidates);
        for Index := 0 to High(Candidates) do
        begin
          Candidate := Candidates[Index];
          if Candidate = Current then
            Continue;
          Gain := Links[Candidate] - AResolution * Tot[Candidate] * Ki / TwoM;
          if Gain > BestGain + Epsilon then
          begin
            BestGain := Gain;
            Best := Candidate;
          end;
        end;
        Tot[Best] := Tot[Best] + Ki;
        if Best <> Current then
        begin
          ACommunity[Node] := Best;
          Moved := True;
          Result := True;
        end;
      end;
    until not Moved;
  finally
    Links.Free;
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
          Continue;
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
    Result[Node] := Node;
  Edges := AEdges;
  Count := ANodeCount;
  while Count > 0 do
  begin
    Graph := BuildGraph(Count, Edges);
    SetLength(Level, Count);
    for Node := 0 to Count - 1 do
      Level[Node] := Node;
    if not MoveNodes(Graph, AResolution, Level) then
      Break;
    Merged := Renumber(Level);
    // Zuordnung der ursprünglichen Knoten nachführen.
    for Node := 0 to ANodeCount - 1 do
      Result[Node] := Level[Result[Node]];
    // Keine Gruppe verschmolzen: weitere Stufen ändern nichts mehr.
    if Merged >= Count then
      Break;
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
    Exit;
  Count := 0;
  for Community in ACommunities do
    if Community + 1 > Count then
      Count := Community + 1;
  SetLength(Inside, Count);
  SetLength(Tot, Count);
  for Node := 0 to ANodeCount - 1 do
  begin
    Tot[ACommunities[Node]] := Tot[ACommunities[Node]] + Graph.Degree[Node];
    Inside[ACommunities[Node]] := Inside[ACommunities[Node]] + 2 * Graph.SelfWeight[Node];
    for Neighbor in Graph.Neighbors[Node] do
      if ACommunities[Neighbor.Node] = ACommunities[Node] then
        Inside[ACommunities[Node]] := Inside[ACommunities[Node]] + Neighbor.Weight;
  end;
  for Community := 0 to Count - 1 do
    Result := Result + Inside[Community] / Graph.Total - AResolution * Sqr(Tot[Community] / Graph.Total);
end;

end.
