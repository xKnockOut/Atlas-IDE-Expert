unit Atlas.Common.Architecture.Matching;

// Zuordnung der Teilsysteme zweier Architekturstände über ihre Units, eine
// Routine für den Vergleich (#1121) und die Angleichung (#1367):
// - Überschneidung (Vergleich): größte Überschneidung zuerst, bei Gleichstand
//   derselbe Name, dann nach Namen; je altes zu höchstens einem neuen. Übrige
//   ohne gemeinsame Units mit gleichem Namen danach.
// - Mehrheit (Angleichung): nur Paare, die mehr als die Hälfte der Units des
//   neuen und des alten Teilsystems teilen (strikte Mehrheit beider Seiten),
//   ohne Rückfall auf den Namen. Solche Paare sind von selbst eindeutig.
// Units vergleichen ohne Groß-/Kleinschreibung; Teilsysteme ohne Eintrag in
// Subsystems zählen über das Feld Subsystem ihrer Units mit.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Common.Architecture.Snapshot;

type
  TSubsystemMatchMode = (Overlap, Majority);

  /// <summary>Neues Teilsystem und das alte, dem es zugeordnet ist ('' = keinem).</summary>
  TSubsystemMatch = record
    NewName: string;
    OldName: string;
  end;

  TSubsystemMatcher = class
  public
    /// <summary>Je Teilsystem von ANew (nach Namen sortiert) das zugeordnete aus AOld.</summary>
    class function Match(const AOld, ANew: TArchitectureSnapshot; AMode: TSubsystemMatchMode)
      : TArray<TSubsystemMatch>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults;

type
  TMatchCandidate = record
    NewIndex: Integer;
    OldIndex: Integer;
    Overlap: Integer;
    SameName: Boolean;
  end;

function CompareNames(const ALeft, ARight: string): Integer;
begin
  Result := CompareText(ALeft, ARight);
  if Result = 0 then
  begin
    Result := CompareStr(ALeft, ARight);
  end;
end;

/// <summary>Teilsystemnamen eines Stands mit ihren Units (klein geschrieben).</summary>
function GroupsOf(const ASnapshot: TArchitectureSnapshot;
  out ANames: TArray<string>): TArray<TDictionary<string, Boolean>>;
var
  mIndex, mGroup: Integer;
  mItem: TSnapshotUnit;
  mLookup: TDictionary<string, Integer>;
  mKey: string;
begin
  ANames := nil;
  Result := nil;
  mLookup := TDictionary<string, Integer>.Create;
  try
    for mIndex := 0 to High(ASnapshot.Subsystems) do
    begin
      mKey := LowerCase(ASnapshot.Subsystems[mIndex].Name);
      if mLookup.ContainsKey(mKey) then
      begin
        Continue;
      end;
      mLookup.Add(mKey, Length(ANames));
      ANames := ANames + [ASnapshot.Subsystems[mIndex].Name];
      Result := Result + [TDictionary<string, Boolean>.Create];
    end;
    for mItem in ASnapshot.Units do
    begin
      mKey := LowerCase(mItem.Subsystem);
      if not mLookup.TryGetValue(mKey, mGroup) then
      begin
        mGroup := Length(ANames);
        mLookup.Add(mKey, mGroup);
        ANames := ANames + [mItem.Subsystem];
        Result := Result + [TDictionary<string, Boolean>.Create];
      end;
      Result[mGroup].AddOrSetValue(LowerCase(mItem.Name), True);
    end;
  finally
    mLookup.Free;
  end;
end;

procedure FreeGroups(const AGroups: TArray<TDictionary<string, Boolean>>);
var
  mGroup: TDictionary<string, Boolean>;
begin
  for mGroup in AGroups do
  begin
    mGroup.Free;
  end;
end;

/// <summary>Strikte Mehrheit beider Seiten: mehr als die Hälfte der Units des neuen und des alten.</summary>
function IsMajority(AOverlap, ANewCount, AOldCount: Integer): Boolean;
begin
  Result := (AOverlap * 2 > ANewCount) and (AOverlap * 2 > AOldCount);
end;

/// <summary>Anzahl der Units, die in beiden Gruppen stehen.</summary>
function OverlapOf(const ANew, AOld: TDictionary<string, Boolean>): Integer;
var
  mKey: string;
begin
  Result := 0;
  for mKey in ANew.Keys do
  begin
    if AOld.ContainsKey(mKey) then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Alle Paare mit gemeinsamen Units (bei Majority nur mit Mehrheit auf beiden Seiten).</summary>
procedure CollectCandidates(const AOldGroups, ANewGroups: TArray<TDictionary<string, Boolean>>;
  const AOldNames, ANewNames: TArray<string>; AMode: TSubsystemMatchMode; ACandidates: TList<TMatchCandidate>);
var
  mCandidate: TMatchCandidate;
  mNewIndex, mOldIndex, mOverlap: Integer;
begin
  for mNewIndex := 0 to High(ANewGroups) do
  begin
    for mOldIndex := 0 to High(AOldGroups) do
    begin
      mOverlap := OverlapOf(ANewGroups[mNewIndex], AOldGroups[mOldIndex]);
      if (mOverlap = 0) or (AMode = TSubsystemMatchMode.Majority) and
        not IsMajority(mOverlap, ANewGroups[mNewIndex].Count, AOldGroups[mOldIndex].Count) then
      begin
        Continue;
      end;
      mCandidate.NewIndex := mNewIndex;
      mCandidate.OldIndex := mOldIndex;
      mCandidate.Overlap := mOverlap;
      mCandidate.SameName := SameText(ANewNames[mNewIndex], AOldNames[mOldIndex]);
      ACandidates.Add(mCandidate);
    end;
  end;
end;

/// <summary>Größte Überschneidung zuerst, bei Gleichstand derselbe Name, dann nach Namen (eindeutig).</summary>
procedure SortCandidates(ACandidates: TList<TMatchCandidate>; const AOldNames, ANewNames: TArray<string>);
begin
  ACandidates.Sort(TComparer<TMatchCandidate>.Construct(
    function(const ALeft, ARight: TMatchCandidate): Integer
    begin
      Result := ARight.Overlap - ALeft.Overlap;
      if Result = 0 then
      begin
        Result := Ord(ARight.SameName) - Ord(ALeft.SameName);
      end;
      if Result = 0 then
      begin
        Result := CompareNames(ANewNames[ALeft.NewIndex], ANewNames[ARight.NewIndex]);
      end;
      if Result = 0 then
      begin
        Result := CompareNames(AOldNames[ALeft.OldIndex], AOldNames[ARight.OldIndex]);
      end;
    end));
end;

/// <summary>Je neuem Teilsystem der Index des alten (-1 = keins); jedes alte höchstens einmal.</summary>
function AssignCandidates(ACandidates: TList<TMatchCandidate>; ANewCount: Integer;
  var AOldTaken: TArray<Boolean>): TArray<Integer>;
var
  mCandidate: TMatchCandidate;
  mNewIndex: Integer;
begin
  SetLength(Result, ANewCount);
  for mNewIndex := 0 to High(Result) do
  begin
    Result[mNewIndex] := -1;
  end;
  for mCandidate in ACandidates do
  begin
    if (Result[mCandidate.NewIndex] < 0) and not AOldTaken[mCandidate.OldIndex] then
    begin
      Result[mCandidate.NewIndex] := mCandidate.OldIndex;
      AOldTaken[mCandidate.OldIndex] := True;
    end;
  end;
end;

/// <summary>Freies altes Teilsystem mit dem Namen ANewName, sonst -1.</summary>
function FreeOldByName(const AOldNames: TArray<string>; const AOldTaken: TArray<Boolean>;
  const ANewName: string): Integer;
var
  mOldIndex: Integer;
begin
  for mOldIndex := 0 to High(AOldNames) do
  begin
    if not AOldTaken[mOldIndex] and SameText(AOldNames[mOldIndex], ANewName) then
    begin
      Exit(mOldIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Vergleich: ohne gemeinsame Units derselbe Name, wenn das alte Teilsystem noch frei ist.</summary>
procedure AssignSameNames(const AOldNames, ANewNames: TArray<string>; var AAssigned: TArray<Integer>;
  var AOldTaken: TArray<Boolean>);
var
  mNewIndex: Integer;
begin
  for mNewIndex := 0 to High(AAssigned) do
  begin
    if AAssigned[mNewIndex] < 0 then
    begin
      AAssigned[mNewIndex] := FreeOldByName(AOldNames, AOldTaken, ANewNames[mNewIndex]);
      if AAssigned[mNewIndex] >= 0 then
      begin
        AOldTaken[AAssigned[mNewIndex]] := True;
      end;
    end;
  end;
end;

/// <summary>Zuordnung als Namenspaare, nach neuem Namen sortiert.</summary>
function MatchesOf(const AOldNames, ANewNames: TArray<string>; const AAssigned: TArray<Integer>)
  : TArray<TSubsystemMatch>;
var
  mNewIndex: Integer;
begin
  SetLength(Result, Length(ANewNames));
  for mNewIndex := 0 to High(ANewNames) do
  begin
    Result[mNewIndex].NewName := ANewNames[mNewIndex];
    if AAssigned[mNewIndex] >= 0 then
    begin
      Result[mNewIndex].OldName := AOldNames[AAssigned[mNewIndex]];
    end
    else
    begin
      Result[mNewIndex].OldName := '';
    end;
  end;
  TArray.Sort<TSubsystemMatch>(Result, TComparer<TSubsystemMatch>.Construct(
    function(const ALeft, ARight: TSubsystemMatch): Integer
    begin
      Result := CompareNames(ALeft.NewName, ARight.NewName);
    end));
end;

class function TSubsystemMatcher.Match(const AOld, ANew: TArchitectureSnapshot; AMode: TSubsystemMatchMode)
  : TArray<TSubsystemMatch>;
var
  mOldNames, mNewNames: TArray<string>;
  mOldGroups, mNewGroups: TArray<TDictionary<string, Boolean>>;
  mCandidates: TList<TMatchCandidate>;
  mOldTaken: TArray<Boolean>;
  mAssigned: TArray<Integer>;
begin
  mOldGroups := GroupsOf(AOld, mOldNames);
  mNewGroups := nil;
  mCandidates := nil;
  try
    mNewGroups := GroupsOf(ANew, mNewNames);
    mCandidates := TList<TMatchCandidate>.Create;
    CollectCandidates(mOldGroups, mNewGroups, mOldNames, mNewNames, AMode, mCandidates);
    SortCandidates(mCandidates, mOldNames, mNewNames);
    SetLength(mOldTaken, Length(mOldGroups));
    mAssigned := AssignCandidates(mCandidates, Length(mNewGroups), mOldTaken);
    if AMode = TSubsystemMatchMode.Overlap then
    begin
      AssignSameNames(mOldNames, mNewNames, mAssigned, mOldTaken);
    end;
    Result := MatchesOf(mOldNames, mNewNames, mAssigned);
  finally
    mCandidates.Free;
    FreeGroups(mOldGroups);
    FreeGroups(mNewGroups);
  end;
end;

end.
