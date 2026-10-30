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
    Result := CompareStr(ALeft, ARight);
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
        Continue;
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
    mGroup.Free;
end;

/// <summary>Strikte Mehrheit beider Seiten: mehr als die Hälfte der Units des neuen und des alten.</summary>
function IsMajority(AOverlap, ANewCount, AOldCount: Integer): Boolean;
begin
  Result := (AOverlap * 2 > ANewCount) and (AOverlap * 2 > AOldCount);
end;

class function TSubsystemMatcher.Match(const AOld, ANew: TArchitectureSnapshot; AMode: TSubsystemMatchMode)
  : TArray<TSubsystemMatch>;
var
  mOldNames, mNewNames: TArray<string>;
  mOldGroups, mNewGroups: TArray<TDictionary<string, Boolean>>;
  mCandidates: TList<TMatchCandidate>;
  mCandidate: TMatchCandidate;
  mNewIndex, mOldIndex, mOverlap: Integer;
  mKey: string;
  mOldTaken: TArray<Boolean>;
  mAssigned: TArray<Integer>;
begin
  mOldGroups := GroupsOf(AOld, mOldNames);
  mNewGroups := nil;
  mCandidates := nil;
  try
    mNewGroups := GroupsOf(ANew, mNewNames);
    mCandidates := TList<TMatchCandidate>.Create;
    for mNewIndex := 0 to High(mNewGroups) do
      for mOldIndex := 0 to High(mOldGroups) do
      begin
        mOverlap := 0;
        for mKey in mNewGroups[mNewIndex].Keys do
          if mOldGroups[mOldIndex].ContainsKey(mKey) then
            Inc(mOverlap);
        if mOverlap = 0 then
          Continue;
        if (AMode = TSubsystemMatchMode.Majority) and
          not IsMajority(mOverlap, mNewGroups[mNewIndex].Count, mOldGroups[mOldIndex].Count) then
          Continue;
        mCandidate.NewIndex := mNewIndex;
        mCandidate.OldIndex := mOldIndex;
        mCandidate.Overlap := mOverlap;
        mCandidate.SameName := SameText(mNewNames[mNewIndex], mOldNames[mOldIndex]);
        mCandidates.Add(mCandidate);
      end;
    // Größte Überschneidung zuerst, bei Gleichstand derselbe Name, dann nach Namen (eindeutig).
    mCandidates.Sort(TComparer<TMatchCandidate>.Construct(
      function(const ALeft, ARight: TMatchCandidate): Integer
      begin
        Result := ARight.Overlap - ALeft.Overlap;
        if Result = 0 then
          Result := Ord(ARight.SameName) - Ord(ALeft.SameName);
        if Result = 0 then
          Result := CompareNames(mNewNames[ALeft.NewIndex], mNewNames[ARight.NewIndex]);
        if Result = 0 then
          Result := CompareNames(mOldNames[ALeft.OldIndex], mOldNames[ARight.OldIndex]);
      end));
    SetLength(mOldTaken, Length(mOldGroups));
    SetLength(mAssigned, Length(mNewGroups));
    for mNewIndex := 0 to High(mAssigned) do
      mAssigned[mNewIndex] := -1;
    for mCandidate in mCandidates do
      if (mAssigned[mCandidate.NewIndex] < 0) and not mOldTaken[mCandidate.OldIndex] then
      begin
        mAssigned[mCandidate.NewIndex] := mCandidate.OldIndex;
        mOldTaken[mCandidate.OldIndex] := True;
      end;
    // Vergleich: ohne gemeinsame Units derselbe Name, wenn das alte Teilsystem noch frei ist.
    if AMode = TSubsystemMatchMode.Overlap then
      for mNewIndex := 0 to High(mAssigned) do
        if mAssigned[mNewIndex] < 0 then
          for mOldIndex := 0 to High(mOldNames) do
            if not mOldTaken[mOldIndex] and SameText(mOldNames[mOldIndex], mNewNames[mNewIndex]) then
            begin
              mAssigned[mNewIndex] := mOldIndex;
              mOldTaken[mOldIndex] := True;
              Break;
            end;
    SetLength(Result, Length(mNewNames));
    for mNewIndex := 0 to High(mNewNames) do
    begin
      Result[mNewIndex].NewName := mNewNames[mNewIndex];
      if mAssigned[mNewIndex] >= 0 then
        Result[mNewIndex].OldName := mOldNames[mAssigned[mNewIndex]]
      else
        Result[mNewIndex].OldName := '';
    end;
    TArray.Sort<TSubsystemMatch>(Result, TComparer<TSubsystemMatch>.Construct(
      function(const ALeft, ARight: TSubsystemMatch): Integer
      begin
        Result := CompareNames(ALeft.NewName, ARight.NewName);
      end));
  finally
    mCandidates.Free;
    FreeGroups(mOldGroups);
    FreeGroups(mNewGroups);
  end;
end;

end.
