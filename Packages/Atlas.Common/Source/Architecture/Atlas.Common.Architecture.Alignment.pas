unit Atlas.Common.Architecture.Alignment;

// Farben und Namen der Teilsysteme über Läufe halten (#1367).
//
// Nach dem Gruppieren werden die Teilsysteme einem vorigen Stand zugeordnet
// (TSubsystemMatcher im Modus Mehrheit: mehr als die Hälfte der Units beider
// Seiten gemeinsam; dieselbe Routine wie der Vergleich #1121):
// - Zugeordnete behalten ihren alten Namen samt Zusatz („Index 2“) und ihre
//   alte Farbnummer (ColorSlot) mit Farbton (Shade). Die Teile eines
//   nachgeteilten Teilsystems (#1364) teilen weiter eine Farbe: Die Familie
//   nimmt die Farbe ihres größten zugeordneten Teils, das ursprüngliche
//   Teilsystem (Parent) dessen alten Namen.
// - Neue bekommen die kleinste freie Farbnummer und ihren Namen wie bisher;
//   gleicht er einem behaltenen, bekommt er einen Zusatz (Name 2, Name 3, …).
// - Fundament (#1365) und die Sammelgruppe ohne uses-Beziehung behalten ihre
//   festen Namen; das Fundament bleibt neutral (ColorSlot -1). Sie werden nur
//   ihresgleichen zugeordnet.
// - Die Reihenfolge der Teilsysteme bleibt (nach Größe und Name); nur Farbe
//   und Name werden angeglichen. Die Zuordnungen der Units (#1368) werden
//   danach neu sortiert, weil Gleichstände nach Namen gehen.
// Deterministisch: gleiche Übersicht und gleicher voriger Stand ergeben
// dasselbe Ergebnis.

interface

uses
  Atlas.Common.Architecture.Overview,
  Atlas.Common.Architecture.Snapshot;

type
  TArchitectureAlignment = class
  public
    /// <summary>Gleicht Farben und Namen der Teilsysteme von AOverview an APrevious an. Liefert die Zahl der
    /// Teilsysteme, die Name und Farbe behielten; nur dann setzt es AlignedSource (ASource), AlignedAt (AAt) und
    /// AlignedKept.</summary>
    class function Align(var AOverview: TArchitectureOverview; const APrevious: TArchitectureSnapshot;
      const ASource: string; AAt: TDateTime): Integer; static;
    /// <summary>ABase oder, wenn schon vergeben (ohne Groß-/Kleinschreibung), ABase ohne Zusatz mit " 2", " 3" …
    /// </summary>
    class function UniqueName(const ABase: string; const ATaken: TArray<string>): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Architecture.Matching;

/// <summary>Farbtöne einer Familie in der Reihenfolge der Vergabe: 0, +1, -1, +2, -2, …</summary>
function ShadeAt(ARank: Integer): Integer;
begin
  if ARank = 0 then
    Result := 0
  else if Odd(ARank) then
    Result := (ARank + 1) div 2
  else
    Result := -(ARank div 2);
end;

/// <summary>Name ohne den Zusatz " 2", " 3" …, den das Eindeutigmachen anhängt.</summary>
function WithoutSuffix(const AName: string): string;
var
  mPosition: Integer;
begin
  Result := AName;
  mPosition := Length(AName);
  while (mPosition > 0) and CharInSet(AName[mPosition], ['0'..'9']) do
    Dec(mPosition);
  if (mPosition > 1) and (mPosition < Length(AName)) and (AName[mPosition] = ' ') then
    Result := Copy(AName, 1, mPosition - 1);
end;

function Taken(const AName: string; const ATaken: TArray<string>): Boolean;
var
  mName: string;
begin
  for mName in ATaken do
    if SameText(mName, AName) then
      Exit(True);
  Result := False;
end;

class function TArchitectureAlignment.UniqueName(const ABase: string; const ATaken: TArray<string>): string;
var
  mBase: string;
  mSuffix: Integer;
begin
  Result := ABase;
  if not Taken(Result, ATaken) then
    Exit;
  mBase := WithoutSuffix(ABase);
  mSuffix := 2;
  Result := mBase + ' ' + IntToStr(mSuffix);
  while Taken(Result, ATaken) do
  begin
    Inc(mSuffix);
    Result := mBase + ' ' + IntToStr(mSuffix);
  end;
end;

/// <summary>Je Teilsystem von AOverview das zugeordnete aus APrevious (-1 = keins).</summary>
function MatchedOld(const AOverview: TArchitectureOverview; const APrevious: TArchitectureSnapshot)
  : TArray<Integer>;
var
  mMatches: TArray<TSubsystemMatch>;
  mMatch: TSubsystemMatch;
  mOldByName, mNewByName: TDictionary<string, Integer>;
  mIndex, mOld, mNew: Integer;
begin
  SetLength(Result, Length(AOverview.Subsystems));
  for mIndex := 0 to High(Result) do
    Result[mIndex] := -1;
  mMatches := TSubsystemMatcher.Match(APrevious, TArchitectureSnapshots.FromOverview(AOverview),
    TSubsystemMatchMode.Majority);
  mOldByName := TDictionary<string, Integer>.Create;
  mNewByName := TDictionary<string, Integer>.Create;
  try
    for mIndex := 0 to High(APrevious.Subsystems) do
      mOldByName.AddOrSetValue(LowerCase(APrevious.Subsystems[mIndex].Name), mIndex);
    for mIndex := 0 to High(AOverview.Subsystems) do
      mNewByName.AddOrSetValue(LowerCase(AOverview.Subsystems[mIndex].Name), mIndex);
    for mMatch in mMatches do
      if (mMatch.OldName <> '') and mNewByName.TryGetValue(LowerCase(mMatch.NewName), mNew) and
        mOldByName.TryGetValue(LowerCase(mMatch.OldName), mOld) and
        (AOverview.Subsystems[mNew].Foundation = APrevious.Subsystems[mOld].Foundation) and
        (AOverview.Subsystems[mNew].Isolated = APrevious.Subsystems[mOld].Isolated) then
        Result[mNew] := mOld;
  finally
    mNewByName.Free;
    mOldByName.Free;
  end;
end;

function ContainsShade(const AShades: TArray<Integer>; AShade: Integer): Boolean;
var
  mShade: Integer;
begin
  for mShade in AShades do
    if mShade = AShade then
      Exit(True);
  Result := False;
end;

/// <summary>Farben: je Familie (gleiche Farbnummer aus der Gruppierung) die alte Farbe ihres größten zugeordneten
/// Teils, sonst die kleinste freie; Farbtöne zugeordneter Teile bleiben, wenn frei.</summary>
procedure AlignColors(var AOverview: TArchitectureOverview; const APrevious: TArchitectureSnapshot;
  const AOld: TArray<Integer>);
var
  mFamily: TArray<Integer>;
  mSlotOf, mSourceOf: TDictionary<Integer, Integer>;
  mUsed: TDictionary<Integer, Boolean>;
  mShades: TDictionary<Integer, TArray<Integer>>;
  mIndex, mMember, mSlot, mSource, mRank, mShade: Integer;
  mUsedShades: TArray<Integer>;
  mKeep: TArray<Boolean>;

  function HasOldColor(ASubsystem: Integer): Boolean;
  begin
    Result := (AOld[ASubsystem] >= 0) and APrevious.Subsystems[AOld[ASubsystem]].HasColor and
      (APrevious.Subsystems[AOld[ASubsystem]].ColorSlot >= 0);
  end;

begin
  SetLength(mFamily, Length(AOverview.Subsystems));
  for mIndex := 0 to High(mFamily) do
    mFamily[mIndex] := AOverview.Subsystems[mIndex].ColorSlot;
  SetLength(mKeep, Length(mFamily));
  mSlotOf := TDictionary<Integer, Integer>.Create;
  mSourceOf := TDictionary<Integer, Integer>.Create;
  mUsed := TDictionary<Integer, Boolean>.Create;
  mShades := TDictionary<Integer, TArray<Integer>>.Create;
  try
    // Erst die Familien mit alter Farbe (die Teile stehen nach Größe, der erste zugeordnete ist der größte).
    for mIndex := 0 to High(mFamily) do
    begin
      if (mFamily[mIndex] < 0) or mSlotOf.ContainsKey(mFamily[mIndex]) then
        Continue;
      for mMember := mIndex to High(mFamily) do
        if (mFamily[mMember] = mFamily[mIndex]) and HasOldColor(mMember) and
          not mUsed.ContainsKey(APrevious.Subsystems[AOld[mMember]].ColorSlot) then
        begin
          mSlot := APrevious.Subsystems[AOld[mMember]].ColorSlot;
          mSlotOf.Add(mFamily[mIndex], mSlot);
          mSourceOf.Add(mFamily[mIndex], mMember);
          mUsed.Add(mSlot, True);
          Break;
        end;
    end;
    // Dann die übrigen mit der kleinsten freien.
    for mIndex := 0 to High(mFamily) do
    begin
      if (mFamily[mIndex] < 0) or mSlotOf.ContainsKey(mFamily[mIndex]) then
        Continue;
      mSlot := 0;
      while mUsed.ContainsKey(mSlot) do
        Inc(mSlot);
      mSlotOf.Add(mFamily[mIndex], mSlot);
      mUsed.Add(mSlot, True);
    end;
    // Farbtöne: zugeordnete Teile mit derselben alten Farbe behalten ihren, die übrigen der Reihe nach.
    for mIndex := 0 to High(mFamily) do
    begin
      if mFamily[mIndex] < 0 then
        Continue;
      mSlot := mSlotOf[mFamily[mIndex]];
      if not mShades.TryGetValue(mSlot, mUsedShades) then
        mUsedShades := nil;
      if HasOldColor(mIndex) and (APrevious.Subsystems[AOld[mIndex]].ColorSlot = mSlot) and
        not ContainsShade(mUsedShades, APrevious.Subsystems[AOld[mIndex]].Shade) then
      begin
        mKeep[mIndex] := True;
        AOverview.Subsystems[mIndex].Shade := APrevious.Subsystems[AOld[mIndex]].Shade;
        mShades.AddOrSetValue(mSlot, mUsedShades + [AOverview.Subsystems[mIndex].Shade]);
      end;
    end;
    for mIndex := 0 to High(mFamily) do
    begin
      if (mFamily[mIndex] < 0) or mKeep[mIndex] then
        Continue;
      mSlot := mSlotOf[mFamily[mIndex]];
      if not mShades.TryGetValue(mSlot, mUsedShades) then
        mUsedShades := nil;
      mRank := 0;
      mShade := ShadeAt(mRank);
      while ContainsShade(mUsedShades, mShade) do
      begin
        Inc(mRank);
        mShade := ShadeAt(mRank);
      end;
      AOverview.Subsystems[mIndex].Shade := mShade;
      mShades.AddOrSetValue(mSlot, mUsedShades + [mShade]);
    end;
    for mIndex := 0 to High(mFamily) do
      if mFamily[mIndex] >= 0 then
      begin
        AOverview.Subsystems[mIndex].ColorSlot := mSlotOf[mFamily[mIndex]];
        // Das ursprüngliche Teilsystem einer Familie heißt wie das des Teils, dessen Farbe sie übernimmt.
        if mSourceOf.TryGetValue(mFamily[mIndex], mSource) and (AOverview.Subsystems[mIndex].Parent <> '') and
          (APrevious.Subsystems[AOld[mSource]].Parent <> '') then
          AOverview.Subsystems[mIndex].Parent := APrevious.Subsystems[AOld[mSource]].Parent;
      end;
  finally
    mShades.Free;
    mUsed.Free;
    mSourceOf.Free;
    mSlotOf.Free;
  end;
end;

/// <summary>Namen: zugeordnete behalten den alten, Fundament und Sammelgruppe ihren festen; die übrigen werden
/// gegen alle diese eindeutig gemacht.</summary>
procedure AlignNames(var AOverview: TArchitectureOverview; const APrevious: TArchitectureSnapshot;
  const AOld: TArray<Integer>);
var
  mTaken: TArray<string>;
  mIndex: Integer;
  mFixed: TArray<Boolean>;
begin
  mTaken := nil;
  SetLength(mFixed, Length(AOverview.Subsystems));
  for mIndex := 0 to High(AOverview.Subsystems) do
  begin
    mFixed[mIndex] := AOverview.Subsystems[mIndex].Foundation or AOverview.Subsystems[mIndex].Isolated;
    if not mFixed[mIndex] and (AOld[mIndex] >= 0) then
    begin
      AOverview.Subsystems[mIndex].Name := APrevious.Subsystems[AOld[mIndex]].Name;
      mFixed[mIndex] := True;
    end;
    if mFixed[mIndex] then
      mTaken := mTaken + [AOverview.Subsystems[mIndex].Name];
  end;
  for mIndex := 0 to High(AOverview.Subsystems) do
    if not mFixed[mIndex] then
    begin
      AOverview.Subsystems[mIndex].Name := TArchitectureAlignment.UniqueName(AOverview.Subsystems[mIndex].Name,
        mTaken);
      mTaken := mTaken + [AOverview.Subsystems[mIndex].Name];
    end;
end;

class function TArchitectureAlignment.Align(var AOverview: TArchitectureOverview;
  const APrevious: TArchitectureSnapshot; const ASource: string; AAt: TDateTime): Integer;
var
  mOld: TArray<Integer>;
  mIndex: Integer;
begin
  Result := 0;
  if (Length(AOverview.Subsystems) = 0) or (Length(APrevious.Subsystems) = 0) then
    Exit;
  mOld := MatchedOld(AOverview, APrevious);
  for mIndex := 0 to High(mOld) do
    if (mOld[mIndex] >= 0) and not AOverview.Subsystems[mIndex].Foundation then
      Inc(Result);
  if Result = 0 then
    Exit;
  AlignColors(AOverview, APrevious, mOld);
  AlignNames(AOverview, APrevious, mOld);
  // Gleichstände der Zuordnung gehen nach dem Namen des Teilsystems (#1368).
  if Length(AOverview.Assignments) > 0 then
    AOverview.Assignments := TArchitectureAnalyzer.Assignments(AOverview);
  AOverview.AlignedSource := ASource;
  AOverview.AlignedAt := AAt;
  AOverview.AlignedKept := Result;
end;

end.
