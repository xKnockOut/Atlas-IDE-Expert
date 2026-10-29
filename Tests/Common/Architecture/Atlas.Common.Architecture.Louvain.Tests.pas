unit Atlas.Common.Architecture.Louvain.Tests;

// Tests der Louvain-Gruppierung (#1118): getrennte Gruppen, Brücken,
// einzelne Knoten, Nummerierung, ungültige Kanten, Modularität; Auflösung γ
// (#1366) an einem Ring aus Cliquen.

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
    [Test]
    procedure ResolutionOneMatchesClassic;
    [Test]
    procedure RingOfCliquesAtResolutionOne;
    [Test]
    procedure SmallResolutionMergesCliques;
    [Test]
    procedure LargeResolutionKeepsCliques;
    [Test]
    procedure ModularityWithResolutionMatchesHandCalculation;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
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

/// <summary>Ring aus sechs vollständigen Fünfergruppen (Gewicht 1), je Gruppe eine Kante zur nächsten.</summary>
function RingOfCliques: TArray<TLouvainEdge>;
var
  mGroup, mA, mB: Integer;
begin
  Result := nil;
  for mGroup := 0 to 5 do
  begin
    for mA := 0 to 4 do
      for mB := mA + 1 to 4 do
        Result := Result + [Edge(mGroup * 5 + mA, mGroup * 5 + mB, 1)];
    Result := Result + [Edge(mGroup * 5 + 4, ((mGroup + 1) mod 6) * 5, 1)];
  end;
end;

function GroupCount(const AValues: TArray<Integer>): Integer;
var
  mValue: Integer;
begin
  Result := 0;
  for mValue in AValues do
    Result := Max(Result, mValue + 1);
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

procedure TLouvainTests.ResolutionOneMatchesClassic;
begin
  Assert.AreEqual(Joined(TLouvain.Communities(8, TwoCliques)), Joined(TLouvain.Communities(8, TwoCliques, 1)));
  Assert.AreEqual(Joined(TLouvain.Communities(30, RingOfCliques)), Joined(TLouvain.Communities(30, RingOfCliques, 1)));
  Assert.AreEqual(TLouvain.Modularity(8, TwoCliques, TLouvain.Communities(8, TwoCliques)),
    TLouvain.Modularity(8, TwoCliques, TLouvain.Communities(8, TwoCliques), 1), 1E-12);
end;

procedure TLouvainTests.RingOfCliquesAtResolutionOne;
begin
  Assert.AreEqual('000001111122222333334444455555', Joined(TLouvain.Communities(30, RingOfCliques, 1)));
end;

procedure TLouvainTests.SmallResolutionMergesCliques;
var
  mCount: Integer;
begin
  // Wechsel lohnt, sobald 1 > γ · 22 · 22 / 132, also γ < 0,27: Nachbargruppen verschmelzen.
  mCount := GroupCount(TLouvain.Communities(30, RingOfCliques, 0.2));
  Assert.IsTrue(mCount < 6, IntToStr(mCount));
  Assert.IsTrue(mCount >= 1, IntToStr(mCount));
end;

procedure TLouvainTests.LargeResolutionKeepsCliques;
var
  mCount: Integer;
begin
  mCount := GroupCount(TLouvain.Communities(30, RingOfCliques, 5));
  Assert.IsTrue(mCount >= 6, IntToStr(mCount));
  mCount := GroupCount(TLouvain.Communities(30, RingOfCliques, 2));
  Assert.IsTrue(mCount >= 6, IntToStr(mCount));
end;

procedure TLouvainTests.ModularityWithResolutionMatchesHandCalculation;
var
  mGroups: TArray<Integer>;
  mNode: Integer;
  mInner, mExpected: Double;
begin
  // Je Gruppe innen 10 Kanten (20 als Summe der Nachbargewichte), Grad 22, 2m = 132:
  // Q = 6 · (20/132 − γ · (22/132)²) = 10/11 − γ/6.
  SetLength(mGroups, 30);
  for mNode := 0 to 29 do
    mGroups[mNode] := mNode div 5;
  // Doubles statt konstanter Ausdrücke: FPC rechnet 0.5 / 6 sonst nur in Single.
  mInner := 10;
  mInner := mInner / 11;
  mExpected := mInner - 1 / 6;
  Assert.AreEqual(mExpected, TLouvain.Modularity(30, RingOfCliques, mGroups, 1), 1E-9);
  mExpected := mInner - 2 / 6;
  Assert.AreEqual(mExpected, TLouvain.Modularity(30, RingOfCliques, mGroups, 2), 1E-9);
  mExpected := 0.5;
  mExpected := mInner - mExpected / 6;
  Assert.AreEqual(mExpected, TLouvain.Modularity(30, RingOfCliques, mGroups, 0.5), 1E-9);
end;

initialization
  TDUnitX.RegisterTestFixture(TLouvainTests);

end.
