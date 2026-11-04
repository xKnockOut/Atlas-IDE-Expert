unit Atlas.Common.Architecture.Overview.Splitting;

// Nachteilung der Teilsysteme der Architekturübersicht (#1364), ausgelagert
// aus Atlas.Common.Architecture.Overview.
//
// - Eine Gruppe wird nachgeteilt, wenn die Entscheidung des Aufrufers (Größe
//   und Zusammenhalt) es verlangt. Der Zusammenhalt ist Kanten innen /
//   (innen + nach außen); Kanten zu Fundament-Units zählen nicht mit. Er wird
//   erst ab CohesionMinUnits Units gerechnet, darunter gilt 1.
// - Gruppen, die mit einer Fundament-Unit beginnen, bleiben ganz (#1365).
// - Geteilt wird mit Louvain über die Kanten innerhalb der Gruppe. Teile sind
//   fortlaufend in der Reihenfolge der Units nummeriert; Units ohne Kante im
//   Teilgraphen bleiben beim größten Teil.
// - Kanten sind gerichtet gespeichert (A = verwendende Unit, B = verwendete);
//   Schleifen (A = B) zählen nicht.

interface

uses
  Atlas.Common.Architecture.Louvain;

type
  /// <summary>Entscheidung, ob eine Gruppe mit ASize Units und Zusammenhalt ACohesion nachgeteilt wird.</summary>
  TSplitDecision = reference to function(ASize: Integer; ACohesion: Double): Boolean;

  TSplitSettings = record
    /// <summary>Auflösung γ des Louvain-Laufs.</summary>
    Resolution: Double;
    /// <summary>Zusammenhalt erst ab so vielen Units rechnen (MaxInt = nie).</summary>
    CohesionMinUnits: Integer;
    Decision: TSplitDecision;
  end;

  TSubsystemSplitter = class
  private
    FEdges: TArray<TLouvainEdge>;
    FInFoundation: TArray<Boolean>;
    FSettings: TSplitSettings;
    /// <summary>Je Unit die Nummern ihrer Kanten (beide Richtungen, ohne Schleifen).</summary>
    FIncident: TArray<TArray<Integer>>;
    /// <summary>Je Unit die Stelle in der gerade untersuchten Gruppe; -1 außerhalb.</summary>
    FLocal: TArray<Integer>;
    procedure BuildIncident(AUnitCount: Integer);
    function InFoundation(AUnit: Integer): Boolean;
    function OtherEnd(AEdge, AUnit: Integer): Integer;
    procedure MarkMembers(const AMembers: TArray<Integer>; AMark: Boolean);
    function Cohesion(const AMembers: TArray<Integer>): Double;
    function NeedsSplit(const AMembers: TArray<Integer>): Boolean;
    /// <summary>Kanten innerhalb der Gruppe, je Kante einmal, in Stellen der Gruppe; ADegree: Kanten je Stelle.
    /// </summary>
    function InnerEdges(const AMembers: TArray<Integer>; out ADegree: TArray<Integer>): TArray<TLouvainEdge>;
    function SplitMembers(const AMembers: TArray<Integer>; out AParts: TArray<TArray<Integer>>): Boolean;
  public
    constructor Create(AUnitCount: Integer; const AEdges: TArray<TLouvainEdge>; const AInFoundation: TArray<Boolean>;
      const ASettings: TSplitSettings);
    /// <summary>Teilt AMembers in AParts (mindestens zwei); False = bleibt, wie sie ist.</summary>
    function SplitGroup(const AMembers: TArray<Integer>; out AParts: TArray<TArray<Integer>>): Boolean;
    /// <summary>Gemeinschaften ALocal (je Stelle) fortlaufend nummerieren; Stellen ohne Kante (ADegree 0) werden
    /// -1. Ergebnis: Zahl der Teile.</summary>
    class function Renumber(var ALocal: TArray<Integer>; const ADegree: TArray<Integer>): Integer; static;
    /// <summary>Units nach Teilen; Stellen mit -1 kommen zum größten Teil.</summary>
    class function PartsOf(const AMembers, ALocal: TArray<Integer>; ACount: Integer): TArray<TArray<Integer>>;
      static;
  end;

implementation

uses
  System.Generics.Collections;

constructor TSubsystemSplitter.Create(AUnitCount: Integer; const AEdges: TArray<TLouvainEdge>;
  const AInFoundation: TArray<Boolean>; const ASettings: TSplitSettings);
var
  mIndex: Integer;
begin
  inherited Create;
  FEdges := AEdges;
  FInFoundation := AInFoundation;
  FSettings := ASettings;
  BuildIncident(AUnitCount);
  SetLength(FLocal, AUnitCount);
  for mIndex := 0 to High(FLocal) do
  begin
    FLocal[mIndex] := -1;
  end;
end;

procedure TSubsystemSplitter.BuildIncident(AUnitCount: Integer);
var
  mSizes: TArray<Integer>;
  mIndex: Integer;
  mEdge: TLouvainEdge;
begin
  SetLength(mSizes, AUnitCount);
  for mEdge in FEdges do
  begin
    if mEdge.A <> mEdge.B then
    begin
      Inc(mSizes[mEdge.A]);
      Inc(mSizes[mEdge.B]);
    end;
  end;
  SetLength(FIncident, AUnitCount);
  for mIndex := 0 to AUnitCount - 1 do
  begin
    SetLength(FIncident[mIndex], mSizes[mIndex]);
    mSizes[mIndex] := 0;
  end;
  for mIndex := 0 to High(FEdges) do
  begin
    mEdge := FEdges[mIndex];
    if mEdge.A = mEdge.B then
    begin
      Continue;
    end;
    FIncident[mEdge.A][mSizes[mEdge.A]] := mIndex;
    Inc(mSizes[mEdge.A]);
    FIncident[mEdge.B][mSizes[mEdge.B]] := mIndex;
    Inc(mSizes[mEdge.B]);
  end;
end;

function TSubsystemSplitter.InFoundation(AUnit: Integer): Boolean;
begin
  Result := (AUnit >= 0) and (AUnit < Length(FInFoundation)) and FInFoundation[AUnit];
end;

function TSubsystemSplitter.OtherEnd(AEdge, AUnit: Integer): Integer;
begin
  if FEdges[AEdge].A = AUnit then
  begin
    Result := FEdges[AEdge].B;
  end
  else
  begin
    Result := FEdges[AEdge].A;
  end;
end;

procedure TSubsystemSplitter.MarkMembers(const AMembers: TArray<Integer>; AMark: Boolean);
var
  mPosition: Integer;
begin
  for mPosition := 0 to High(AMembers) do
  begin
    if AMark then
    begin
      FLocal[AMembers[mPosition]] := mPosition;
    end
    else
    begin
      FLocal[AMembers[mPosition]] := -1;
    end;
  end;
end;

function TSubsystemSplitter.Cohesion(const AMembers: TArray<Integer>): Double;
var
  mInner, mOuter, mMember, mEdge, mOther: Integer;
begin
  mInner := 0;
  mOuter := 0;
  MarkMembers(AMembers, True);
  for mMember in AMembers do
  begin
    for mEdge in FIncident[mMember] do
    begin
      mOther := OtherEnd(mEdge, mMember);
      if InFoundation(mOther) then
      begin
        Continue;
      end;
      if FLocal[mOther] >= 0 then
      begin
        Inc(mInner);
      end
      else
      begin
        Inc(mOuter);
      end;
    end;
  end;
  MarkMembers(AMembers, False);
  // Innere Kanten stehen bei beiden Enden.
  mInner := mInner div 2;
  Result := 1;
  if mInner + mOuter > 0 then
  begin
    Result := mInner / (mInner + mOuter);
  end;
end;

function TSubsystemSplitter.NeedsSplit(const AMembers: TArray<Integer>): Boolean;
var
  mCohesion: Double;
begin
  mCohesion := 1;
  if Length(AMembers) >= FSettings.CohesionMinUnits then
  begin
    mCohesion := Cohesion(AMembers);
  end;
  Result := FSettings.Decision(Length(AMembers), mCohesion);
end;

function TSubsystemSplitter.SplitGroup(const AMembers: TArray<Integer>; out AParts: TArray<TArray<Integer>>): Boolean;
begin
  AParts := nil;
  Result := (Length(AMembers) > 0) and not InFoundation(AMembers[0]) and NeedsSplit(AMembers) and
    SplitMembers(AMembers, AParts);
end;

function TSubsystemSplitter.InnerEdges(const AMembers: TArray<Integer>; out ADegree: TArray<Integer>)
  : TArray<TLouvainEdge>;
var
  mEdges: TList<TLouvainEdge>;
  mItem: TLouvainEdge;
  mPosition, mEdge: Integer;
begin
  SetLength(ADegree, Length(AMembers));
  MarkMembers(AMembers, True);
  mEdges := TList<TLouvainEdge>.Create;
  try
    for mPosition := 0 to High(AMembers) do
    begin
      for mEdge in FIncident[AMembers[mPosition]] do
      begin
        // Jede Kante einmal, bei ihrer Quelle; nur Kanten innerhalb der Gruppe.
        if (FEdges[mEdge].A <> AMembers[mPosition]) or (FLocal[FEdges[mEdge].B] < 0) then
        begin
          Continue;
        end;
        mItem.A := mPosition;
        mItem.B := FLocal[FEdges[mEdge].B];
        mItem.Weight := FEdges[mEdge].Weight;
        mEdges.Add(mItem);
        Inc(ADegree[mItem.A]);
        Inc(ADegree[mItem.B]);
      end;
    end;
    Result := mEdges.ToArray;
  finally
    mEdges.Free;
    MarkMembers(AMembers, False);
  end;
end;

function TSubsystemSplitter.SplitMembers(const AMembers: TArray<Integer>; out AParts: TArray<TArray<Integer>>)
  : Boolean;
var
  mDegree, mLocal: TArray<Integer>;
  mCount: Integer;
begin
  AParts := nil;
  mLocal := TLouvain.Communities(Length(AMembers), InnerEdges(AMembers, mDegree), FSettings.Resolution);
  mCount := Renumber(mLocal, mDegree);
  Result := mCount > 1;
  if Result then
  begin
    AParts := PartsOf(AMembers, mLocal, mCount);
  end;
end;

class function TSubsystemSplitter.Renumber(var ALocal: TArray<Integer>; const ADegree: TArray<Integer>): Integer;
var
  mNumbers: TDictionary<Integer, Integer>;
  mPosition, mNumber: Integer;
begin
  mNumbers := TDictionary<Integer, Integer>.Create;
  try
    for mPosition := 0 to High(ALocal) do
    begin
      if ADegree[mPosition] = 0 then
      begin
        ALocal[mPosition] := -1;
        Continue;
      end;
      if not mNumbers.TryGetValue(ALocal[mPosition], mNumber) then
      begin
        mNumber := mNumbers.Count;
        mNumbers.Add(ALocal[mPosition], mNumber);
      end;
      ALocal[mPosition] := mNumber;
    end;
    Result := mNumbers.Count;
  finally
    mNumbers.Free;
  end;
end;

/// <summary>Nummer des größten Teils (bei Gleichstand der erste).</summary>
function LargestPart(const ALocal: TArray<Integer>; ACount: Integer): Integer;
var
  mSizes: TArray<Integer>;
  mNumber: Integer;
begin
  SetLength(mSizes, ACount);
  for mNumber in ALocal do
  begin
    if mNumber >= 0 then
    begin
      Inc(mSizes[mNumber]);
    end;
  end;
  Result := 0;
  for mNumber := 1 to ACount - 1 do
  begin
    if mSizes[mNumber] > mSizes[Result] then
    begin
      Result := mNumber;
    end;
  end;
end;

class function TSubsystemSplitter.PartsOf(const AMembers, ALocal: TArray<Integer>; ACount: Integer)
  : TArray<TArray<Integer>>;
var
  mLargest, mPosition, mPart: Integer;
begin
  mLargest := LargestPart(ALocal, ACount);
  SetLength(Result, ACount);
  for mPosition := 0 to High(ALocal) do
  begin
    mPart := ALocal[mPosition];
    if mPart < 0 then
    begin
      mPart := mLargest;
    end;
    Result[mPart] := Result[mPart] + [AMembers[mPosition]];
  end;
end;

end.
