unit Atlas.Common.Architecture.Overview.Foundations.Tests;

// Tests der Fundamente der Architekturübersicht (#1365): Nummerierung,
// übergreifendes Fundament getrennt oder angehängt, Kandidat ohne Verteilung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFoundationSeparationTests = class
  public
    [Test]
    procedure RenumberFollowsFirstOccurrence;
    [Test]
    procedure SpreadFoundationGetsOwnGroup;
    [Test]
    procedure SpreadFoundationAttachesToGroup;
    [Test]
    procedure LocalCandidateStaysInGroup;
  end;

implementation

uses
  Atlas.Common.Architecture.Louvain,
  Atlas.Common.Architecture.Overview.Foundations;

function Edge(AFrom, ATo: Integer): TLouvainEdge;
begin
  Result.A := AFrom;
  Result.B := ATo;
  Result.Weight := 1;
end;

/// <summary>Drei vollständige Vierergruppen 0..3, 4..7, 8..11; Unit 12 wird aus jeder Gruppe verwendet
/// (AShared) oder nur aus der ersten.</summary>
function Graph(AShared: Boolean): TArray<TLouvainEdge>;
var
  mGroup, mA, mB: Integer;
begin
  Result := nil;
  for mGroup := 0 to 2 do
  begin
    for mA := 0 to 3 do
    begin
      for mB := mA + 1 to 3 do
      begin
        Result := Result + [Edge(mGroup * 4 + mA, mGroup * 4 + mB)];
      end;
    end;
  end;
  Result := Result + [Edge(0, 12), Edge(1, 12)];
  if AShared then
  begin
    Result := Result + [Edge(4, 12), Edge(5, 12), Edge(8, 12), Edge(9, 12)];
  end;
end;

function Settings(ASeparate: Boolean): TFoundationSettings;
begin
  Result.Resolution := 1;
  Result.Separate := ASeparate;
  Result.MinSpread := 3;
  Result.MaxOwnPercent := 60;
end;

/// <summary>Louvain und Fundamente über Graph(AShared) mit Unit 12 als Kandidat.</summary>
procedure RunOn(AShared, ASeparate: Boolean; out ACommunities: TArray<Integer>; out AInFoundation: TArray<Boolean>);
var
  mEdges: TArray<TLouvainEdge>;
  mRoles: TArray<Boolean>;
  mSeparation: TFoundationSeparation;
begin
  mEdges := Graph(AShared);
  SetLength(mRoles, 13);
  mRoles[12] := True;
  ACommunities := TLouvain.Communities(13, mEdges, 1);
  mSeparation := TFoundationSeparation.Create(13, mEdges, Settings(ASeparate));
  try
    mSeparation.Run(mRoles, ACommunities, AInFoundation);
  finally
    mSeparation.Free;
  end;
end;

procedure TFoundationSeparationTests.RenumberFollowsFirstOccurrence;
var
  mValues: TArray<Integer>;
begin
  mValues := TArray<Integer>.Create(7, 3, 7, 9, 3);
  TFoundationSeparation.Renumber(mValues);
  Assert.AreEqual(0, mValues[0]);
  Assert.AreEqual(1, mValues[1]);
  Assert.AreEqual(0, mValues[2]);
  Assert.AreEqual(2, mValues[3]);
  Assert.AreEqual(1, mValues[4]);
end;

procedure TFoundationSeparationTests.SpreadFoundationGetsOwnGroup;
var
  mCommunities: TArray<Integer>;
  mInFoundation: TArray<Boolean>;
  mUnit: Integer;
begin
  RunOn(True, True, mCommunities, mInFoundation);
  Assert.AreEqual(13, Integer(Length(mInFoundation)));
  Assert.IsTrue(mInFoundation[12]);
  for mUnit := 0 to 11 do
  begin
    Assert.IsFalse(mInFoundation[mUnit]);
    Assert.AreNotEqual(mCommunities[12], mCommunities[mUnit]);
  end;
  Assert.AreNotEqual(mCommunities[0], mCommunities[4]);
  Assert.AreNotEqual(mCommunities[4], mCommunities[8]);
end;

procedure TFoundationSeparationTests.SpreadFoundationAttachesToGroup;
var
  mCommunities: TArray<Integer>;
  mInFoundation: TArray<Boolean>;
begin
  RunOn(True, False, mCommunities, mInFoundation);
  Assert.AreEqual(0, Integer(Length(mInFoundation)));
  Assert.IsTrue((mCommunities[12] = mCommunities[0]) or (mCommunities[12] = mCommunities[4]) or
    (mCommunities[12] = mCommunities[8]));
  Assert.AreNotEqual(mCommunities[0], mCommunities[4]);
end;

procedure TFoundationSeparationTests.LocalCandidateStaysInGroup;
var
  mCommunities: TArray<Integer>;
  mInFoundation: TArray<Boolean>;
  mUnit: Integer;
begin
  RunOn(False, True, mCommunities, mInFoundation);
  for mUnit := 0 to High(mInFoundation) do
  begin
    Assert.IsFalse(mInFoundation[mUnit]);
  end;
  Assert.AreEqual(mCommunities[0], mCommunities[12]);
end;

end.
