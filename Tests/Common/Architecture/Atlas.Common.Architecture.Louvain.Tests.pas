unit Atlas.Common.Architecture.Louvain.Tests;

// Tests der Louvain-Gruppierung (#1118): getrennte Gruppen, Brücken,
// einzelne Knoten, Nummerierung, ungültige Kanten, Modularität.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLouvainTests = class
  public
    [Test]
    procedure SplitsTwoCliquesJoinedByBridge;
    [Test]
    procedure IsolatedNodesStayAlone;
    [Test]
    procedure NumbersFollowFirstNode;
    [Test]
    procedure IgnoresInvalidEdges;
    [Test]
    procedure ModularityPrefersFoundGroups;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Architecture.Louvain;

function Edge(A, B: Integer; AWeight: Double): TLouvainEdge;
begin
  Result.A := A;
  Result.B := B;
  Result.Weight := AWeight;
end;

/// <summary>Vollständige Vierergruppe ab AOffset.</summary>
function Clique(AOffset: Integer): TArray<TLouvainEdge>;
var
  A, B: Integer;
begin
  Result := nil;
  for A := 0 to 3 do
    for B := A + 1 to 3 do
      Result := Result + [Edge(AOffset + A, AOffset + B, 2)];
end;

/// <summary>Zwei vollständige Vierergruppen 0..3 und 4..7, verbunden durch 3–4.</summary>
function TwoCliques: TArray<TLouvainEdge>;
begin
  Result := Clique(0) + Clique(4);
  Result := Result + [Edge(3, 4, 1)];
end;

function Joined(const AValues: TArray<Integer>): string;
var
  Value: Integer;
begin
  Result := '';
  for Value in AValues do
    Result := Result + IntToStr(Value);
end;

{ TLouvainTests }

procedure TLouvainTests.SplitsTwoCliquesJoinedByBridge;
begin
  Assert.AreEqual('00001111', Joined(TLouvain.Communities(8, TwoCliques)));
end;

procedure TLouvainTests.IsolatedNodesStayAlone;
var
  Edges: TArray<TLouvainEdge>;
begin
  // Knoten 2 ohne Kanten, 0–1 und 3–4 je ein Paar.
  Edges := nil;
  Edges := Edges + [Edge(0, 1, 1), Edge(3, 4, 1)];
  Assert.AreEqual('00122', Joined(TLouvain.Communities(5, Edges)));
  Assert.AreEqual('012', Joined(TLouvain.Communities(3, nil)));
end;

procedure TLouvainTests.NumbersFollowFirstNode;
var
  Edges: TArray<TLouvainEdge>;
begin
  // Kanten der hinteren Gruppe zuerst: Die Gruppe von Knoten 0 bekommt trotzdem die 0.
  Edges := Clique(4) + Clique(0);
  Edges := Edges + [Edge(3, 4, 1)];
  Assert.AreEqual('00001111', Joined(TLouvain.Communities(8, Edges)));
end;

procedure TLouvainTests.IgnoresInvalidEdges;
var
  Edges: TArray<TLouvainEdge>;
begin
  Edges := nil;
  Edges := Edges + [Edge(0, 0, 5), Edge(1, 2, 0), Edge(-1, 1, 1), Edge(1, 9, 1)];
  Assert.AreEqual('012', Joined(TLouvain.Communities(3, Edges)));
end;

procedure TLouvainTests.ModularityPrefersFoundGroups;
var
  Found, Single: TArray<Integer>;
begin
  Found := TLouvain.Communities(8, TwoCliques);
  SetLength(Single, 8);
  Assert.IsTrue(TLouvain.Modularity(8, TwoCliques, Found) > 0.3, FloatToStr(TLouvain.Modularity(8, TwoCliques, Found)));
  Assert.AreEqual(Double(0), TLouvain.Modularity(8, TwoCliques, Single), 1E-9);
end;

initialization
  TDUnitX.RegisterTestFixture(TLouvainTests);

end.
