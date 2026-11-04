unit Atlas.Common.Architecture.Overview.Foundations;

// Fundamente der Architekturübersicht (#1365), ausgelagert aus
// Atlas.Common.Architecture.Overview.
//
// - Kandidaten sind Units mit Rolle Fundament, die verwendet werden. Ihre
//   Verteilung zählt in einem Louvain-Lauf ohne sie, denn im ersten Lauf
//   ziehen sie ihre Abhängigen gerade zusammen.
// - Übergreifend ist ein Kandidat, dessen Abhängige (ohne Kandidaten und ohne
//   Units, die nur an Kandidaten hängen) in mindestens MinSpread
//   Teilsystemen liegen oder höchstens zu MaxOwnPercent im größten.
// - Ein zweiter Lauf rechnet ohne die übergreifenden Fundamente und ihre
//   Kanten. Units, deren einzige Kanten zu Fundamenten führen, folgen dem
//   Fundament mit dem größten Gewicht.
// - Separate: alle Fundamente und ihre Folger in eine eigene Gruppe.
//   Sonst (Attach) kommt jedes Fundament in die Gruppe, aus der die meisten
//   Abhängigen stammen; Fundamente ohne zugeordnete Abhängige folgen zuletzt
//   den Units, die sie verwenden, oder bilden je eine eigene Gruppe.
// - Kanten sind ungerichtet gespeichert mit A = verwendende Unit,
//   B = verwendete Unit.

interface

uses
  System.Generics.Collections,
  Atlas.Common.Architecture.Louvain;

type
  TFoundationSettings = record
    /// <summary>Auflösung γ der Louvain-Läufe.</summary>
    Resolution: Double;
    /// <summary>True: Fundamente in eine eigene Gruppe; False: an die Gruppe ihrer Abhängigen anhängen.</summary>
    Separate: Boolean;
    /// <summary>Übergreifend ab so vielen Gruppen der Abhängigen.</summary>
    MinSpread: Integer;
    /// <summary>Übergreifend, wenn höchstens so viel Prozent der Abhängigen in der größten Gruppe liegen.</summary>
    MaxOwnPercent: Integer;
  end;

  TFoundationSeparation = class
  private
    FEdges: TArray<TLouvainEdge>;
    FSettings: TFoundationSettings;
    FCount: Integer;
    FCandidate: TArray<Boolean>;
    FFoundation: TArray<Boolean>;
    FFollower: TArray<Boolean>;
    FAssigned: TArray<Boolean>;
    FDegree: TArray<Integer>;
    FReducedDegree: TArray<Integer>;
    FFollow: TArray<Integer>;
    FSecond: TArray<Integer>;
    FIncoming: TArray<TArray<Integer>>;
    FNext: Integer;
    /// <summary>Louvain ohne die Units AExcluded und ihre Kanten, fortlaufend nummeriert; FReducedDegree: Kanten
    /// je Unit im verbleibenden Graphen.</summary>
    function Without(const AExcluded: TArray<Boolean>): TArray<Integer>;
    /// <summary>Kandidaten aus ARoles (Rolle Fundament) mit mindestens einer eingehenden Kante.</summary>
    function FindCandidates(const ARoles: TArray<Boolean>): Boolean;
    /// <summary>Der Kandidat AUnit ist übergreifend (Verteilung seiner Abhängigen im Lauf AProbe).</summary>
    function IsSpread(AUnit: Integer; const AProbe: TArray<Integer>; ASpread: TDictionary<Integer, Integer>): Boolean;
    function FindFoundations(const AProbe: TArray<Integer>): Boolean;
    /// <summary>Zweiter Lauf ohne die übergreifenden Fundamente (sind es alle Kandidaten, ist es AProbe).</summary>
    function SecondRun(const AProbe: TArray<Integer>): TArray<Integer>;
    /// <summary>Fundament, dem AUnit folgt, weil alle ihre Kanten zu Fundamenten führen; -1 ohne.</summary>
    function FollowOf(AUnit: Integer): Integer;
    procedure FindFollowers;
    procedure SeparateAll(out AInFoundation: TArray<Boolean>);
    /// <summary>Gewichte der Gruppen, aus denen zugeordnete Units AUnit verwenden (APass 1: auch die, die AUnit
    /// verwendet).</summary>
    procedure WeighGroups(AUnit, APass: Integer; var AWeights: TArray<Double>);
    /// <summary>Ein Durchgang der Zuordnung; True, wenn ein Fundament dazukam.</summary>
    function AttachPass(APass: Integer; var AWeights: TArray<Double>): Boolean;
    procedure AttachAll;
  public
    constructor Create(ANodeCount: Integer; const AEdges: TArray<TLouvainEdge>;
      const ASettings: TFoundationSettings);
    /// <summary>Neue Gruppen in ACommunities, wenn ein Kandidat aus ARoles übergreifend ist; sonst bleibt
    /// ACommunities. AInFoundation: mit Separate je Unit, ob sie in die Gruppe der Fundamente kam, sonst nil.
    /// </summary>
    procedure Run(const ARoles: TArray<Boolean>; var ACommunities: TArray<Integer>;
      out AInFoundation: TArray<Boolean>);
    /// <summary>Gruppennummern fortlaufend ab 0 in der Reihenfolge des ersten Auftretens.</summary>
    class procedure Renumber(var AValues: TArray<Integer>); static;
  end;

implementation

uses
  System.Math;

/// <summary>Gruppe mit dem größten Gewicht in AWeights (Gleichstand: kleinere Nummer); -1 ohne.</summary>
function Heaviest(const AWeights: TArray<Double>): Integer;
var
  mCommunity: Integer;
begin
  Result := -1;
  for mCommunity := 0 to High(AWeights) do
  begin
    if (AWeights[mCommunity] > 0) and ((Result < 0) or (AWeights[mCommunity] > AWeights[Result])) then
    begin
      Result := mCommunity;
    end;
  end;
end;

class procedure TFoundationSeparation.Renumber(var AValues: TArray<Integer>);
var
  mMap: TDictionary<Integer, Integer>;
  mIndex, mNumber: Integer;
begin
  mMap := TDictionary<Integer, Integer>.Create;
  try
    for mIndex := 0 to High(AValues) do
    begin
      if not mMap.TryGetValue(AValues[mIndex], mNumber) then
      begin
        mNumber := mMap.Count;
        mMap.Add(AValues[mIndex], mNumber);
      end;
      AValues[mIndex] := mNumber;
    end;
  finally
    mMap.Free;
  end;
end;

constructor TFoundationSeparation.Create(ANodeCount: Integer; const AEdges: TArray<TLouvainEdge>;
  const ASettings: TFoundationSettings);
var
  mIndex: Integer;
begin
  inherited Create;
  FCount := ANodeCount;
  FEdges := AEdges;
  FSettings := ASettings;
  SetLength(FIncoming, FCount);
  SetLength(FDegree, FCount);
  for mIndex := 0 to High(FEdges) do
  begin
    FIncoming[FEdges[mIndex].B] := FIncoming[FEdges[mIndex].B] + [mIndex];
    Inc(FDegree[FEdges[mIndex].A]);
    Inc(FDegree[FEdges[mIndex].B]);
  end;
end;

function TFoundationSeparation.Without(const AExcluded: TArray<Boolean>): TArray<Integer>;
var
  mReduced: TList<TLouvainEdge>;
  mEdge: TLouvainEdge;
begin
  FReducedDegree := nil;
  SetLength(FReducedDegree, FCount);
  mReduced := TList<TLouvainEdge>.Create;
  try
    for mEdge in FEdges do
    begin
      if not AExcluded[mEdge.A] and not AExcluded[mEdge.B] then
      begin
        mReduced.Add(mEdge);
        Inc(FReducedDegree[mEdge.A]);
        Inc(FReducedDegree[mEdge.B]);
      end;
    end;
    Result := TLouvain.Communities(FCount, mReduced.ToArray, FSettings.Resolution);
  finally
    mReduced.Free;
  end;
  Renumber(Result);
end;

function TFoundationSeparation.FindCandidates(const ARoles: TArray<Boolean>): Boolean;
var
  mUnit: Integer;
begin
  Result := False;
  SetLength(FCandidate, FCount);
  for mUnit := 0 to FCount - 1 do
  begin
    FCandidate[mUnit] := ARoles[mUnit] and (Length(FIncoming[mUnit]) > 0);
    Result := Result or FCandidate[mUnit];
  end;
end;

function TFoundationSeparation.IsSpread(AUnit: Integer; const AProbe: TArray<Integer>;
  ASpread: TDictionary<Integer, Integer>): Boolean;
var
  mIndex, mOther, mTotal, mNumber, mLargest: Integer;
begin
  ASpread.Clear;
  mTotal := 0;
  for mIndex in FIncoming[AUnit] do
  begin
    mOther := FEdges[mIndex].A;
    if FCandidate[mOther] or (FReducedDegree[mOther] = 0) then
    begin
      Continue;
    end;
    Inc(mTotal);
    if not ASpread.TryGetValue(AProbe[mOther], mNumber) then
    begin
      mNumber := 0;
    end;
    ASpread.AddOrSetValue(AProbe[mOther], mNumber + 1);
  end;
  if mTotal = 0 then
  begin
    Exit(False);
  end;
  mLargest := 0;
  for mNumber in ASpread.Values do
  begin
    mLargest := Max(mLargest, mNumber);
  end;
  Result := (ASpread.Count >= FSettings.MinSpread) or (mLargest * 100 <= FSettings.MaxOwnPercent * mTotal);
end;

function TFoundationSeparation.FindFoundations(const AProbe: TArray<Integer>): Boolean;
var
  mUnit: Integer;
  mSpread: TDictionary<Integer, Integer>;
begin
  Result := False;
  SetLength(FFoundation, FCount);
  mSpread := TDictionary<Integer, Integer>.Create;
  try
    for mUnit := 0 to FCount - 1 do
    begin
      if FCandidate[mUnit] then
      begin
        FFoundation[mUnit] := IsSpread(mUnit, AProbe, mSpread);
        Result := Result or FFoundation[mUnit];
      end;
    end;
  finally
    mSpread.Free;
  end;
end;

function TFoundationSeparation.SecondRun(const AProbe: TArray<Integer>): TArray<Integer>;
var
  mUnit: Integer;
  mSame: Boolean;
begin
  mSame := True;
  for mUnit := 0 to FCount - 1 do
  begin
    mSame := mSame and (FCandidate[mUnit] = FFoundation[mUnit]);
  end;
  if mSame then
  begin
    Result := AProbe;
  end
  else
  begin
    Result := Without(FFoundation);
  end;
end;

function TFoundationSeparation.FollowOf(AUnit: Integer): Integer;
var
  mWeights: TArray<Double>;
  mEdge: TLouvainEdge;
  mOther: Integer;
begin
  SetLength(mWeights, FCount);
  for mEdge in FEdges do
  begin
    if mEdge.A = AUnit then
    begin
      mWeights[mEdge.B] := mWeights[mEdge.B] + mEdge.Weight;
    end
    else if mEdge.B = AUnit then
    begin
      mWeights[mEdge.A] := mWeights[mEdge.A] + mEdge.Weight;
    end;
  end;
  Result := -1;
  for mOther := 0 to FCount - 1 do
  begin
    if FFoundation[mOther] and (mWeights[mOther] > 0) and ((Result < 0) or (mWeights[mOther] > mWeights[Result])) then
    begin
      Result := mOther;
    end;
  end;
end;

procedure TFoundationSeparation.FindFollowers;
var
  mUnit: Integer;
begin
  SetLength(FFollower, FCount);
  SetLength(FFollow, FCount);
  for mUnit := 0 to FCount - 1 do
  begin
    FFollow[mUnit] := -1;
    if not FFoundation[mUnit] and (FDegree[mUnit] > 0) and (FReducedDegree[mUnit] = 0) then
    begin
      FFollow[mUnit] := FollowOf(mUnit);
      FFollower[mUnit] := FFollow[mUnit] >= 0;
    end;
  end;
end;

procedure TFoundationSeparation.SeparateAll(out AInFoundation: TArray<Boolean>);
var
  mUnit: Integer;
begin
  AInFoundation := nil;
  SetLength(AInFoundation, FCount);
  for mUnit := 0 to FCount - 1 do
  begin
    if FFoundation[mUnit] or FFollower[mUnit] then
    begin
      FSecond[mUnit] := FNext;
      AInFoundation[mUnit] := True;
    end;
  end;
end;

procedure TFoundationSeparation.WeighGroups(AUnit, APass: Integer; var AWeights: TArray<Double>);
var
  mIndex: Integer;
  mEdge: TLouvainEdge;
begin
  for mIndex := 0 to High(AWeights) do
  begin
    AWeights[mIndex] := 0;
  end;
  for mIndex in FIncoming[AUnit] do
  begin
    if FAssigned[FEdges[mIndex].A] then
    begin
      AWeights[FSecond[FEdges[mIndex].A]] := AWeights[FSecond[FEdges[mIndex].A]] + FEdges[mIndex].Weight;
    end;
  end;
  if APass <> 1 then
  begin
    Exit;
  end;
  for mEdge in FEdges do
  begin
    if (mEdge.A = AUnit) and FAssigned[mEdge.B] then
    begin
      AWeights[FSecond[mEdge.B]] := AWeights[FSecond[mEdge.B]] + mEdge.Weight;
    end;
  end;
end;

function TFoundationSeparation.AttachPass(APass: Integer; var AWeights: TArray<Double>): Boolean;
var
  mUnit, mBest: Integer;
begin
  Result := False;
  for mUnit := 0 to FCount - 1 do
  begin
    if not FFoundation[mUnit] or FAssigned[mUnit] then
    begin
      Continue;
    end;
    WeighGroups(mUnit, APass, AWeights);
    mBest := Heaviest(AWeights);
    if mBest >= 0 then
    begin
      FSecond[mUnit] := mBest;
      FAssigned[mUnit] := True;
      Result := True;
    end;
  end;
end;

procedure TFoundationSeparation.AttachAll;
var
  mUnit, mPass: Integer;
  mWeights: TArray<Double>;
begin
  // Anhängen: in das Teilsystem, aus dem die meisten Abhängigen stammen (gewichtet, Gleichstand: kleinere
  // Nummer). Fundamente, die nur Fundamente verwenden, folgen ihren Abhängigen, sobald diese zugeordnet sind;
  // solche ohne zugeordnete Abhängige zuletzt den Units, die sie verwenden.
  SetLength(FAssigned, FCount);
  for mUnit := 0 to FCount - 1 do
  begin
    FAssigned[mUnit] := not FFoundation[mUnit] and not FFollower[mUnit];
  end;
  SetLength(mWeights, FNext);
  for mPass := 0 to 1 do
  begin
    // Wiederholen, bis kein Fundament mehr dazukommt.
    repeat
    until not AttachPass(mPass, mWeights);
  end;
  // Ohne jede Zuordnung (nur Kanten unter solchen Fundamenten): je ein eigenes Teilsystem.
  for mUnit := 0 to FCount - 1 do
  begin
    if FFoundation[mUnit] and not FAssigned[mUnit] then
    begin
      FSecond[mUnit] := FNext;
      Inc(FNext);
    end;
  end;
  for mUnit := 0 to FCount - 1 do
  begin
    if FFollower[mUnit] then
    begin
      FSecond[mUnit] := FSecond[FFollow[mUnit]];
    end;
  end;
end;

procedure TFoundationSeparation.Run(const ARoles: TArray<Boolean>; var ACommunities: TArray<Integer>;
  out AInFoundation: TArray<Boolean>);
var
  mProbe: TArray<Integer>;
  mIndex: Integer;
begin
  AInFoundation := nil;
  if not FindCandidates(ARoles) then
  begin
    Exit;
  end;
  mProbe := Without(FCandidate);
  if not FindFoundations(mProbe) then
  begin
    Exit;
  end;
  FSecond := SecondRun(mProbe);
  FNext := 0;
  for mIndex in FSecond do
  begin
    FNext := Max(FNext, mIndex + 1);
  end;
  FindFollowers;
  if FSettings.Separate then
  begin
    SeparateAll(AInFoundation);
  end
  else
  begin
    AttachAll;
  end;
  ACommunities := FSecond;
end;

end.
