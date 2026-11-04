unit Atlas.Common.Architecture.Overview.Splitting.Tests;

// Tests der Nachteilung der Teilsysteme (#1364): Teilen nach Entscheidung,
// Fundament bleibt ganz, Zusammenhalt ohne Fundament-Kanten, Nummerierung
// und Units ohne Kante beim größten Teil.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSubsystemSplitterTests = class
  public
    [Test]
    procedure SplitsTwoCliquesWhenDecided;
    [Test]
    procedure KeepsGroupWhenNotDecided;
    [Test]
    procedure FoundationGroupStaysWhole;
    [Test]
    procedure CohesionIgnoresFoundationEdges;
    [Test]
    procedure RenumberDropsUnitsWithoutEdges;
    [Test]
    procedure PartsOfPutsLooseUnitsIntoLargestPart;
  end;

implementation

uses
  Atlas.Common.Architecture.Louvain,
  Atlas.Common.Architecture.Overview.Splitting;

function Edge(AFrom, ATo: Integer): TLouvainEdge;
begin
  Result.A := AFrom;
  Result.B := ATo;
  Result.Weight := 1;
end;

/// <summary>Zwei vollständige Vierergruppen 0..3 und 4..7, verbunden durch 3–4; Unit 8 hängt an 0.</summary>
function TwoCliques: TArray<TLouvainEdge>;
var
  mGroup, mA, mB: Integer;
begin
  Result := nil;
  for mGroup := 0 to 1 do
  begin
    for mA := 0 to 3 do
    begin
      for mB := mA + 1 to 3 do
      begin
        Result := Result + [Edge(mGroup * 4 + mA, mGroup * 4 + mB)];
      end;
    end;
  end;
  Result := Result + [Edge(3, 4), Edge(0, 8)];
end;

function Decide(AValue: Boolean): TSplitDecision;
begin
  Result :=
    function(ASize: Integer; ACohesion: Double): Boolean
    begin
      Result := AValue;
    end;
end;

function Settings(const ADecision: TSplitDecision): TSplitSettings;
begin
  Result.Resolution := 1;
  Result.CohesionMinUnits := MaxInt;
  Result.Decision := ADecision;
end;

function SplitWith(const AInFoundation: TArray<Boolean>; const ASettings: TSplitSettings;
  const AMembers: TArray<Integer>; out AParts: TArray<TArray<Integer>>): Boolean;
var
  mSplitter: TSubsystemSplitter;
begin
  mSplitter := TSubsystemSplitter.Create(9, TwoCliques, AInFoundation, ASettings);
  try
    Result := mSplitter.SplitGroup(AMembers, AParts);
  finally
    mSplitter.Free;
  end;
end;

procedure TSubsystemSplitterTests.SplitsTwoCliquesWhenDecided;
var
  mParts: TArray<TArray<Integer>>;
begin
  Assert.IsTrue(SplitWith(nil, Settings(Decide(True)), TArray<Integer>.Create(0, 1, 2, 3, 4, 5, 6, 7), mParts));
  Assert.AreEqual(2, Integer(Length(mParts)));
  Assert.AreEqual(4, Integer(Length(mParts[0])));
  Assert.AreEqual(0, mParts[0][0]);
  Assert.AreEqual(4, mParts[1][0]);
end;

procedure TSubsystemSplitterTests.KeepsGroupWhenNotDecided;
var
  mParts: TArray<TArray<Integer>>;
begin
  Assert.IsFalse(SplitWith(nil, Settings(Decide(False)), TArray<Integer>.Create(0, 1, 2, 3, 4, 5, 6, 7), mParts));
  Assert.AreEqual(0, Integer(Length(mParts)));
end;

procedure TSubsystemSplitterTests.FoundationGroupStaysWhole;
var
  mParts: TArray<TArray<Integer>>;
  mInFoundation: TArray<Boolean>;
begin
  SetLength(mInFoundation, 9);
  mInFoundation[0] := True;
  Assert.IsFalse(SplitWith(mInFoundation, Settings(Decide(True)), TArray<Integer>.Create(0, 1, 2, 3, 4, 5, 6, 7),
    mParts));
end;

procedure TSubsystemSplitterTests.CohesionIgnoresFoundationEdges;
var
  mParts: TArray<TArray<Integer>>;
  mInFoundation: TArray<Boolean>;
  mSettings: TSplitSettings;
  mCohesion: Double;
begin
  SetLength(mInFoundation, 9);
  mInFoundation[8] := True;
  mCohesion := -1;
  mSettings := Settings(
    function(ASize: Integer; ACohesion: Double): Boolean
    begin
      mCohesion := ACohesion;
      Result := False;
    end);
  mSettings.CohesionMinUnits := 1;
  // Gruppe 0..3: 6 Kanten innen, 3–4 nach außen, 0–8 ins Fundament zählt nicht.
  SplitWith(mInFoundation, mSettings, TArray<Integer>.Create(0, 1, 2, 3), mParts);
  Assert.AreEqual(6 / 7, mCohesion, 1E-9);
end;

procedure TSubsystemSplitterTests.RenumberDropsUnitsWithoutEdges;
var
  mLocal: TArray<Integer>;
begin
  mLocal := TArray<Integer>.Create(5, 2, 5, 9);
  Assert.AreEqual(2, TSubsystemSplitter.Renumber(mLocal, TArray<Integer>.Create(1, 1, 1, 0)));
  Assert.AreEqual(0, mLocal[0]);
  Assert.AreEqual(1, mLocal[1]);
  Assert.AreEqual(0, mLocal[2]);
  Assert.AreEqual(-1, mLocal[3]);
end;

procedure TSubsystemSplitterTests.PartsOfPutsLooseUnitsIntoLargestPart;
var
  mParts: TArray<TArray<Integer>>;
begin
  mParts := TSubsystemSplitter.PartsOf(TArray<Integer>.Create(10, 11, 12, 13), TArray<Integer>.Create(0, 1, 1, -1), 2);
  Assert.AreEqual(2, Integer(Length(mParts)));
  Assert.AreEqual(1, Integer(Length(mParts[0])));
  Assert.AreEqual(3, Integer(Length(mParts[1])));
  Assert.AreEqual(13, mParts[1][2]);
end;

end.
