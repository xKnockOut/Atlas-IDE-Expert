unit Atlas.Common.Architecture.Overview.Naming;

// Namen der Teilsysteme der Architekturübersicht (#1118, #1364), ausgelagert
// aus Atlas.Common.Architecture.Overview.
//
// - Ein Teilsystem heißt nach dem Namensraum-Abschnitt, der seine Units am
//   besten von den übrigen unterscheidet: Häufigkeit in der Gruppe mal
//   log(Gesamtzahl / Häufigkeit im Vergleichsumfang). Vergleichsumfang ist
//   das ganze Projekt bzw. bei Teilen eines nachgeteilten Teilsystems dessen
//   Units.
// - Abschnitte zählen ohne Groß-/Kleinschreibung, je Unit einmal; der Name
//   übernimmt die Schreibweise der ersten Unit der Gruppe.
// - Doppelte Namen werden in der Reihenfolge der Teilsysteme durchgezählt:
//   "Index", "Index 2".

interface

uses
  System.Generics.Collections;

type
  TSubsystemNaming = class
  public
    /// <summary>Je Namensraum-Abschnitt (klein) die Zahl der Units aus AMembers, die ihn tragen (je Unit
    /// einmal). AParts: Abschnitte je Unit. Der Aufrufer gibt das Ergebnis frei.</summary>
    class function PartCounts(const AParts: TArray<TArray<string>>; const AMembers: TArray<Integer>)
      : TDictionary<string, Integer>; static;
    /// <summary>Bester Abschnitt der Gruppe AMembers gegen AGlobal (ATotal Units); '' ohne Abschnitt mit
    /// Gewinn. AScore: sein Wert.</summary>
    class function BestPart(const AParts: TArray<TArray<string>>; const AMembers: TArray<Integer>;
      const AGlobal: TDictionary<string, Integer>; ATotal: Integer; out AScore: Double): string; static;
    /// <summary>Schreibweise des Abschnitts AKey, wie er in den Units der Gruppe steht.</summary>
    class function PartCaption(const AParts: TArray<TArray<string>>; const AMembers: TArray<Integer>;
      const AKey: string): string; static;
    /// <summary>Doppelte Namen eindeutig machen: "Index", "Index 2" (ohne Groß-/Kleinschreibung).</summary>
    class procedure MakeUnique(var ANames: TArray<string>); static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils;

class function TSubsystemNaming.PartCounts(const AParts: TArray<TArray<string>>; const AMembers: TArray<Integer>)
  : TDictionary<string, Integer>;
var
  mMember, mCount: Integer;
  mPart, mKey: string;
  mSeen: TArray<string>;
begin
  Result := TDictionary<string, Integer>.Create;
  for mMember in AMembers do
  begin
    mSeen := nil;
    for mPart in AParts[mMember] do
    begin
      mKey := LowerCase(mPart);
      if IndexStr(mKey, mSeen) >= 0 then
      begin
        Continue;
      end;
      mSeen := mSeen + [mKey];
      if not Result.TryGetValue(mKey, mCount) then
      begin
        mCount := 0;
      end;
      Result.AddOrSetValue(mKey, mCount + 1);
    end;
  end;
end;

class function TSubsystemNaming.BestPart(const AParts: TArray<TArray<string>>; const AMembers: TArray<Integer>;
  const AGlobal: TDictionary<string, Integer>; ATotal: Integer; out AScore: Double): string;
var
  mLocal: TDictionary<string, Integer>;
  mGlobal: Integer;
  mKey: string;
  mKeys: TArray<string>;
  mScore: Double;
begin
  Result := '';
  AScore := 0;
  mLocal := PartCounts(AParts, AMembers);
  try
    mKeys := mLocal.Keys.ToArray;
    TArray.Sort<string>(mKeys);
    for mKey in mKeys do
    begin
      if not AGlobal.TryGetValue(mKey, mGlobal) or (mGlobal <= 0) then
      begin
        Continue;
      end;
      mScore := mLocal[mKey] * Ln(ATotal / mGlobal);
      if mScore > AScore + 1E-9 then
      begin
        AScore := mScore;
        Result := mKey;
      end;
    end;
  finally
    mLocal.Free;
  end;
end;

class function TSubsystemNaming.PartCaption(const AParts: TArray<TArray<string>>; const AMembers: TArray<Integer>;
  const AKey: string): string;
var
  mMember: Integer;
  mPart: string;
begin
  for mMember in AMembers do
  begin
    for mPart in AParts[mMember] do
    begin
      if SameText(mPart, AKey) then
      begin
        Exit(mPart);
      end;
    end;
  end;
  Result := AKey;
end;

/// <summary>Ein Name aus ANames[0..ABefore-1] ist gleich AName.</summary>
function NameTaken(const ANames: TArray<string>; ABefore: Integer; const AName: string): Boolean;
var
  mOther: Integer;
begin
  for mOther := 0 to ABefore - 1 do
  begin
    if SameText(ANames[mOther], AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class procedure TSubsystemNaming.MakeUnique(var ANames: TArray<string>);
var
  mIndex, mSuffix: Integer;
  mName: string;
begin
  for mIndex := 1 to High(ANames) do
  begin
    mName := ANames[mIndex];
    mSuffix := 1;
    while NameTaken(ANames, mIndex, mName) do
    begin
      Inc(mSuffix);
      mName := ANames[mIndex] + ' ' + IntToStr(mSuffix);
    end;
    ANames[mIndex] := mName;
  end;
end;

end.
