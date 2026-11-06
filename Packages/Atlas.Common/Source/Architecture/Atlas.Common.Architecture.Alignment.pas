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
  begin
    Result := 0;
  end
  else if Odd(ARank) then
  begin
    Result := (ARank + 1) div 2;
  end
  else
  begin
    Result := -(ARank div 2);
  end;
end;

/// <summary>Name ohne den Zusatz " 2", " 3" …, den das Eindeutigmachen anhängt.</summary>
function WithoutSuffix(const AName: string): string;
var
  mPosition: Integer;
begin
  Result := AName;
  mPosition := Length(AName);
  while (mPosition > 0) and CharInSet(AName[mPosition], ['0'..'9']) do
  begin
    Dec(mPosition);
  end;
  if (mPosition > 1) and (mPosition < Length(AName)) and (AName[mPosition] = ' ') then
  begin
    Result := Copy(AName, 1, mPosition - 1);
  end;
end;

function Taken(const AName: string; const ATaken: TArray<string>): Boolean;
var
  mName: string;
begin
  for mName in ATaken do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TArchitectureAlignment.UniqueName(const ABase: string; const ATaken: TArray<string>): string;
var
  mBase: string;
  mSuffix: Integer;
begin
  Result := ABase;
  if not Taken(Result, ATaken) then
  begin
    Exit;
  end;
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
  begin
    Result[mIndex] := -1;
  end;
  mMatches := TSubsystemMatcher.Match(APrevious, TArchitectureSnapshots.FromOverview(AOverview),
    TSubsystemMatchMode.Majority);
  mOldByName := TDictionary<string, Integer>.Create;
  mNewByName := TDictionary<string, Integer>.Create;
  try
    for mIndex := 0 to High(APrevious.Subsystems) do
    begin
      mOldByName.AddOrSetValue(LowerCase(APrevious.Subsystems[mIndex].Name), mIndex);
    end;
    for mIndex := 0 to High(AOverview.Subsystems) do
    begin
      mNewByName.AddOrSetValue(LowerCase(AOverview.Subsystems[mIndex].Name), mIndex);
    end;
    for mMatch in mMatches do
    begin
      if (mMatch.OldName <> '') and mNewByName.TryGetValue(LowerCase(mMatch.NewName), mNew) and
        mOldByName.TryGetValue(LowerCase(mMatch.OldName), mOld) and
        (AOverview.Subsystems[mNew].Foundation = APrevious.Subsystems[mOld].Foundation) and
        (AOverview.Subsystems[mNew].Isolated = APrevious.Subsystems[mOld].Isolated) then
      begin
        Result[mNew] := mOld;
      end;
    end;
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
  begin
    if mShade = AShade then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

type
  /// <summary>Farben: je Familie (gleiche Farbnummer aus der Gruppierung) die alte Farbe ihres größten zugeordneten
  /// Teils, sonst die kleinste freie; Farbtöne zugeordneter Teile bleiben, wenn frei.</summary>
  TColorAlignment = class
  private
    FPrevious: TArchitectureSnapshot;
    FOld: TArray<Integer>;
    FFamily: TArray<Integer>;
    FKeep: TArray<Boolean>;
    FSlotOf, FSourceOf: TDictionary<Integer, Integer>;
    FUsed: TDictionary<Integer, Boolean>;
    FShades: TDictionary<Integer, TArray<Integer>>;
    function HasOldColor(ASubsystem: Integer): Boolean;
    function UsedShades(ASlot: Integer): TArray<Integer>;
    procedure KeepOldSlot(AFamilyStart: Integer);
    procedure AssignSlots;
    procedure KeepOldShades(var AOverview: TArchitectureOverview);
    procedure AssignShades(var AOverview: TArchitectureOverview);
    procedure ApplySlots(var AOverview: TArchitectureOverview);
  public
    constructor Create(const AOverview: TArchitectureOverview; const APrevious: TArchitectureSnapshot;
      const AOld: TArray<Integer>);
    destructor Destroy; override;
    procedure Run(var AOverview: TArchitectureOverview);
  end;

constructor TColorAlignment.Create(const AOverview: TArchitectureOverview; const APrevious: TArchitectureSnapshot;
  const AOld: TArray<Integer>);
var
  mIndex: Integer;
begin
  inherited Create;
  FPrevious := APrevious;
  FOld := AOld;
  SetLength(FFamily, Length(AOverview.Subsystems));
  for mIndex := 0 to High(FFamily) do
  begin
    FFamily[mIndex] := AOverview.Subsystems[mIndex].ColorSlot;
  end;
  SetLength(FKeep, Length(FFamily));
  FSlotOf := TDictionary<Integer, Integer>.Create;
  FSourceOf := TDictionary<Integer, Integer>.Create;
  FUsed := TDictionary<Integer, Boolean>.Create;
  FShades := TDictionary<Integer, TArray<Integer>>.Create;
end;

destructor TColorAlignment.Destroy;
begin
  FShades.Free;
  FUsed.Free;
  FSourceOf.Free;
  FSlotOf.Free;
  inherited;
end;

function TColorAlignment.HasOldColor(ASubsystem: Integer): Boolean;
begin
  Result := (FOld[ASubsystem] >= 0) and FPrevious.Subsystems[FOld[ASubsystem]].HasColor and
    (FPrevious.Subsystems[FOld[ASubsystem]].ColorSlot >= 0);
end;

function TColorAlignment.UsedShades(ASlot: Integer): TArray<Integer>;
begin
  if not FShades.TryGetValue(ASlot, Result) then
  begin
    Result := nil;
  end;
end;

/// <summary>Alte Farbe für die Familie, die bei AFamilyStart beginnt: die des ersten (größten) zugeordneten Teils,
/// dessen Farbe noch frei ist.</summary>
procedure TColorAlignment.KeepOldSlot(AFamilyStart: Integer);
var
  mMember, mSlot: Integer;
begin
  for mMember := AFamilyStart to High(FFamily) do
  begin
    if (FFamily[mMember] = FFamily[AFamilyStart]) and HasOldColor(mMember) and
      not FUsed.ContainsKey(FPrevious.Subsystems[FOld[mMember]].ColorSlot) then
    begin
      mSlot := FPrevious.Subsystems[FOld[mMember]].ColorSlot;
      FSlotOf.Add(FFamily[AFamilyStart], mSlot);
      FSourceOf.Add(FFamily[AFamilyStart], mMember);
      FUsed.Add(mSlot, True);
      Exit;
    end;
  end;
end;

procedure TColorAlignment.AssignSlots;
var
  mIndex, mSlot: Integer;
begin
  // Erst die Familien mit alter Farbe (die Teile stehen nach Größe, der erste zugeordnete ist der größte).
  for mIndex := 0 to High(FFamily) do
  begin
    if (FFamily[mIndex] >= 0) and not FSlotOf.ContainsKey(FFamily[mIndex]) then
    begin
      KeepOldSlot(mIndex);
    end;
  end;
  // Dann die übrigen mit der kleinsten freien.
  for mIndex := 0 to High(FFamily) do
  begin
    if (FFamily[mIndex] < 0) or FSlotOf.ContainsKey(FFamily[mIndex]) then
    begin
      Continue;
    end;
    mSlot := 0;
    while FUsed.ContainsKey(mSlot) do
    begin
      Inc(mSlot);
    end;
    FSlotOf.Add(FFamily[mIndex], mSlot);
    FUsed.Add(mSlot, True);
  end;
end;

/// <summary>Zugeordnete Teile mit derselben alten Farbe behalten ihren Farbton.</summary>
procedure TColorAlignment.KeepOldShades(var AOverview: TArchitectureOverview);
var
  mIndex, mSlot: Integer;
  mUsedShades: TArray<Integer>;
begin
  for mIndex := 0 to High(FFamily) do
  begin
    if FFamily[mIndex] < 0 then
    begin
      Continue;
    end;
    mSlot := FSlotOf[FFamily[mIndex]];
    mUsedShades := UsedShades(mSlot);
    if HasOldColor(mIndex) and (FPrevious.Subsystems[FOld[mIndex]].ColorSlot = mSlot) and
      not ContainsShade(mUsedShades, FPrevious.Subsystems[FOld[mIndex]].Shade) then
    begin
      FKeep[mIndex] := True;
      AOverview.Subsystems[mIndex].Shade := FPrevious.Subsystems[FOld[mIndex]].Shade;
      FShades.AddOrSetValue(mSlot, mUsedShades + [AOverview.Subsystems[mIndex].Shade]);
    end;
  end;
end;

/// <summary>Die übrigen Teile bekommen der Reihe nach den ersten freien Farbton ihrer Farbe.</summary>
procedure TColorAlignment.AssignShades(var AOverview: TArchitectureOverview);
var
  mIndex, mSlot, mRank, mShade: Integer;
  mUsedShades: TArray<Integer>;
begin
  for mIndex := 0 to High(FFamily) do
  begin
    if (FFamily[mIndex] < 0) or FKeep[mIndex] then
    begin
      Continue;
    end;
    mSlot := FSlotOf[FFamily[mIndex]];
    mUsedShades := UsedShades(mSlot);
    mRank := 0;
    mShade := ShadeAt(mRank);
    while ContainsShade(mUsedShades, mShade) do
    begin
      Inc(mRank);
      mShade := ShadeAt(mRank);
    end;
    AOverview.Subsystems[mIndex].Shade := mShade;
    FShades.AddOrSetValue(mSlot, mUsedShades + [mShade]);
  end;
end;

procedure TColorAlignment.ApplySlots(var AOverview: TArchitectureOverview);
var
  mIndex, mSource: Integer;
begin
  for mIndex := 0 to High(FFamily) do
  begin
    if FFamily[mIndex] < 0 then
    begin
      Continue;
    end;
    AOverview.Subsystems[mIndex].ColorSlot := FSlotOf[FFamily[mIndex]];
    // Das ursprüngliche Teilsystem einer Familie heißt wie das des Teils, dessen Farbe sie übernimmt.
    if FSourceOf.TryGetValue(FFamily[mIndex], mSource) and (AOverview.Subsystems[mIndex].Parent <> '') and
      (FPrevious.Subsystems[FOld[mSource]].Parent <> '') then
    begin
      AOverview.Subsystems[mIndex].Parent := FPrevious.Subsystems[FOld[mSource]].Parent;
    end;
  end;
end;

procedure TColorAlignment.Run(var AOverview: TArchitectureOverview);
begin
  AssignSlots;
  KeepOldShades(AOverview);
  AssignShades(AOverview);
  ApplySlots(AOverview);
end;

procedure AlignColors(var AOverview: TArchitectureOverview; const APrevious: TArchitectureSnapshot;
  const AOld: TArray<Integer>);
var
  mAlignment: TColorAlignment;
begin
  mAlignment := TColorAlignment.Create(AOverview, APrevious, AOld);
  try
    mAlignment.Run(AOverview);
  finally
    mAlignment.Free;
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
    begin
      mTaken := mTaken + [AOverview.Subsystems[mIndex].Name];
    end;
  end;
  for mIndex := 0 to High(AOverview.Subsystems) do
  begin
    if not mFixed[mIndex] then
    begin
      AOverview.Subsystems[mIndex].Name := TArchitectureAlignment.UniqueName(AOverview.Subsystems[mIndex].Name,
        mTaken);
      mTaken := mTaken + [AOverview.Subsystems[mIndex].Name];
    end;
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
  begin
    Exit;
  end;
  mOld := MatchedOld(AOverview, APrevious);
  for mIndex := 0 to High(mOld) do
  begin
    if (mOld[mIndex] >= 0) and not AOverview.Subsystems[mIndex].Foundation then
    begin
      Inc(Result);
    end;
  end;
  if Result = 0 then
  begin
    Exit;
  end;
  AlignColors(AOverview, APrevious, mOld);
  AlignNames(AOverview, APrevious, mOld);
  // Gleichstände der Zuordnung gehen nach dem Namen des Teilsystems (#1368).
  if Length(AOverview.Assignments) > 0 then
  begin
    AOverview.Assignments := TArchitectureAnalyzer.Assignments(AOverview);
  end;
  AOverview.AlignedSource := ASource;
  AOverview.AlignedAt := AAt;
  AOverview.AlignedKept := Result;
end;

end.
