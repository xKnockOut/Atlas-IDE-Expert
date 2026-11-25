unit Atlas.Common.Metrics.DuplicateBaseline;

// Baseline der wortgleichen Rümpfe (--check-duplicates): bekannte Gruppen mit ihren Fassungen ("Pfad:Routine").
// Compare trennt neue Fassungen (eine neue Gruppe oder eine weitere Kopie einer bekannten) von Einträgen, die es
// nicht mehr gibt. Beides lässt die Prüfung scheitern: Neue Kopien gehören zusammengelegt, und eine Baseline mit
// toten Einträgen ließe eine entfernte Kopie unbemerkt wiederkommen. Die Baseline kann so nur schrumpfen.
//
// Format: JSON mit einer Gruppe je Zeile, nach Fingerabdruck sortiert, damit parallele Änderungen selten an
// derselben Stelle zusammenstoßen. Zeilennummern stehen nicht darin; Verschieben einer Routine ändert nichts.

interface

uses
  System.SysUtils,
  Atlas.Common.Metrics.DuplicateBodies;

type
  /// <summary>Eine Gruppe der Baseline.</summary>
  TDuplicateBaselineGroup = record
    Hash: string;
    BodyLines: Integer;
    /// <summary>"Pfad:Routine", sortiert.</summary>
    Members: TArray<string>;
  end;

  /// <summary>Gefundene Gruppe mit Fassungen, die die Baseline nicht kennt.</summary>
  TDuplicateNewCopies = record
    Group: TDuplicateBodyGroup;
    /// <summary>Die Gruppe fehlt in der Baseline ganz.</summary>
    NewGroup: Boolean;
    /// <summary>Schlüssel der neuen Fassungen ("Pfad:Routine").</summary>
    NewMembers: TArray<string>;
  end;

  /// <summary>Ergebnis des Vergleichs mit der Baseline.</summary>
  TDuplicateComparison = record
    NewCopies: TArray<TDuplicateNewCopies>;
    /// <summary>Einträge der Baseline, die es nicht mehr gibt: Gruppe mit nur den toten Fassungen.</summary>
    Stale: TArray<TDuplicateBaselineGroup>;
    /// <summary>Gruppen, die ganz in der Baseline stehen.</summary>
    KnownGroups: Integer;
    function Clean: Boolean;
  end;

  TDuplicateBaseline = record
  public
    MinLines: Integer;
    Groups: TArray<TDuplicateBaselineGroup>;
    /// <summary>Baseline aus gefundenen Gruppen.</summary>
    class function FromGroups(const AGroups: TArray<TDuplicateBodyGroup>; AMinLines: Integer): TDuplicateBaseline;
      static;
    /// <summary>Liest AJson; EDuplicateBaseline bei falschem Aufbau.</summary>
    class function Parse(const AJson: string): TDuplicateBaseline; static;
    /// <summary>JSON mit einer Gruppe je Zeile, Zeilenende #10.</summary>
    function ToJson: string;
    /// <summary>Fassungen über alle Gruppen.</summary>
    function MemberCount: Integer;
    /// <summary>Vergleicht AGroups mit der Baseline.</summary>
    function Compare(const AGroups: TArray<TDuplicateBodyGroup>): TDuplicateComparison;
  end;

  EDuplicateBaseline = class(Exception);

implementation

uses
  System.JSON,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Json;

{ TDuplicateComparison }

function TDuplicateComparison.Clean: Boolean;
begin
  Result := (Length(NewCopies) = 0) and (Length(Stale) = 0);
end;

{ Hilfen }

function KeysOf(const AGroup: TDuplicateBodyGroup): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AGroup.Members));
  for mIndex := 0 to High(AGroup.Members) do
  begin
    Result[mIndex] := AGroup.Members[mIndex].Key;
  end;
end;

function Contains(const AKeys: TArray<string>; const AKey: string): Boolean;
var
  mKey: string;
begin
  for mKey in AKeys do
  begin
    if SameText(mKey, AKey) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Schlüssel aus ACandidates, die in AKnown fehlen.</summary>
function Missing(const ACandidates, AKnown: TArray<string>): TArray<string>;
var
  mKey: string;
begin
  Result := nil;
  for mKey in ACandidates do
  begin
    if not Contains(AKnown, mKey) then
    begin
      Result := Result + [mKey];
    end;
  end;
end;

{ TDuplicateBaseline }

class function TDuplicateBaseline.FromGroups(const AGroups: TArray<TDuplicateBodyGroup>;
  AMinLines: Integer): TDuplicateBaseline;
var
  mIndex: Integer;
begin
  Result := Default(TDuplicateBaseline);
  Result.MinLines := AMinLines;
  SetLength(Result.Groups, Length(AGroups));
  for mIndex := 0 to High(AGroups) do
  begin
    Result.Groups[mIndex].Hash := AGroups[mIndex].Hash;
    Result.Groups[mIndex].BodyLines := AGroups[mIndex].BodyLines;
    Result.Groups[mIndex].Members := TDuplicateBodies.SortedPaths(KeysOf(AGroups[mIndex]));
  end;
  TArray.Sort<TDuplicateBaselineGroup>(Result.Groups, TComparer<TDuplicateBaselineGroup>.Construct(
    function(const ALeft, ARight: TDuplicateBaselineGroup): Integer
    begin
      Result := CompareStr(ALeft.Hash, ARight.Hash);
    end));
end;

/// <summary>Eine Gruppe aus AValue; EDuplicateBaseline bei falschem Aufbau.</summary>
function GroupOf(AValue: TJSONValue): TDuplicateBaselineGroup;
var
  mObject: TJSONObject;
  mMembers: TJSONArray;
  mIndex: Integer;
begin
  mObject := TJsonRead.AsObject(AValue);
  if mObject = nil then
  begin
    raise EDuplicateBaseline.Create('group is not an object');
  end;
  Result := Default(TDuplicateBaselineGroup);
  Result.Hash := TJsonRead.Text(mObject, 'hash');
  Result.BodyLines := TJsonRead.IntOr(mObject, 'lines', 0);
  mMembers := TJsonRead.Items(mObject, 'members');
  if (Result.Hash = '') or (mMembers = nil) then
  begin
    raise EDuplicateBaseline.Create('group without hash or members');
  end;
  SetLength(Result.Members, mMembers.Count);
  for mIndex := 0 to mMembers.Count - 1 do
  begin
    Result.Members[mIndex] := mMembers.Items[mIndex].Value;
  end;
end;

class function TDuplicateBaseline.Parse(const AJson: string): TDuplicateBaseline;
var
  mRoot: TJSONObject;
  mGroups: TJSONArray;
  mIndex: Integer;
begin
  Result := Default(TDuplicateBaseline);
  mRoot := TJsonRead.ParseObject(AJson);
  if mRoot = nil then
  begin
    raise EDuplicateBaseline.Create('not a JSON object');
  end;
  try
    Result.MinLines := TJsonRead.IntOr(mRoot, 'minLines', TDuplicateBodies.cMinBodyLines);
    mGroups := TJsonRead.Items(mRoot, 'groups');
    if mGroups = nil then
    begin
      raise EDuplicateBaseline.Create('"groups" missing');
    end;
    SetLength(Result.Groups, mGroups.Count);
    for mIndex := 0 to mGroups.Count - 1 do
    begin
      Result.Groups[mIndex] := GroupOf(mGroups.Items[mIndex]);
    end;
  finally
    mRoot.Free;
  end;
end;

function TDuplicateBaseline.ToJson: string;
var
  mBuilder: TStringBuilder;
  mIndex, mMember: Integer;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append('{'#10'  "minLines": ').Append(MinLines).Append(','#10'  "groups": [');
    for mIndex := 0 to High(Groups) do
    begin
      if mIndex > 0 then
      begin
        mBuilder.Append(',');
      end;
      mBuilder.Append(#10'    {"hash": ').Append(TJsonText.Quote(Groups[mIndex].Hash)).Append(', "lines": ')
        .Append(Groups[mIndex].BodyLines).Append(', "members": [');
      for mMember := 0 to High(Groups[mIndex].Members) do
      begin
        if mMember > 0 then
        begin
          mBuilder.Append(', ');
        end;
        mBuilder.Append(TJsonText.Quote(Groups[mIndex].Members[mMember]));
      end;
      mBuilder.Append(']}');
    end;
    if Length(Groups) > 0 then
    begin
      mBuilder.Append(#10'  ');
    end;
    mBuilder.Append(']'#10'}'#10);
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

function TDuplicateBaseline.MemberCount: Integer;
var
  mGroup: TDuplicateBaselineGroup;
begin
  Result := 0;
  for mGroup in Groups do
  begin
    Inc(Result, Length(mGroup.Members));
  end;
end;

/// <summary>Einträge aus AGroups, deren Fassungen in AFound (Fingerabdruck → gefundene Schlüssel) fehlen, je
/// Gruppe nur mit den toten Fassungen.</summary>
function StaleEntries(const AGroups: TArray<TDuplicateBaselineGroup>;
  AFound: TDictionary<string, TArray<string>>): TArray<TDuplicateBaselineGroup>;
var
  mEntry, mDead: TDuplicateBaselineGroup;
  mKeys: TArray<string>;
begin
  Result := nil;
  for mEntry in AGroups do
  begin
    if not AFound.TryGetValue(mEntry.Hash, mKeys) then
    begin
      mKeys := nil;
    end;
    mDead := mEntry;
    mDead.Members := Missing(mEntry.Members, mKeys);
    if Length(mDead.Members) > 0 then
    begin
      Result := Result + [mDead];
    end;
  end;
end;

function TDuplicateBaseline.Compare(const AGroups: TArray<TDuplicateBodyGroup>): TDuplicateComparison;
var
  mKnown: TDictionary<string, Integer>;
  mFound: TDictionary<string, TArray<string>>;
  mGroup: TDuplicateBodyGroup;
  mCopies: TDuplicateNewCopies;
  mAt: Integer;
  mKeys: TArray<string>;
begin
  Result := Default(TDuplicateComparison);
  mKnown := TDictionary<string, Integer>.Create;
  mFound := TDictionary<string, TArray<string>>.Create;
  try
    for mAt := 0 to High(Groups) do
    begin
      mKnown.AddOrSetValue(Groups[mAt].Hash, mAt);
    end;
    for mGroup in AGroups do
    begin
      mKeys := KeysOf(mGroup);
      mFound.AddOrSetValue(mGroup.Hash, mKeys);
      mCopies := Default(TDuplicateNewCopies);
      mCopies.Group := mGroup;
      if mKnown.TryGetValue(mGroup.Hash, mAt) then
      begin
        mCopies.NewMembers := Missing(mKeys, Groups[mAt].Members);
      end
      else
      begin
        mCopies.NewGroup := True;
        mCopies.NewMembers := mKeys;
      end;
      if Length(mCopies.NewMembers) > 0 then
      begin
        Result.NewCopies := Result.NewCopies + [mCopies];
      end
      else
      begin
        Inc(Result.KnownGroups);
      end;
    end;
    Result.Stale := StaleEntries(Groups, mFound);
  finally
    mFound.Free;
    mKnown.Free;
  end;
end;

end.
