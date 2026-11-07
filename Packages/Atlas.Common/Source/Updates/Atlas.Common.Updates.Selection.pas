unit Atlas.Common.Updates.Selection;

// Platform-Feature "Updates" (#1519), Root: welche Packages ein Update
// installiert (Mockup 6).
// - Kern und Verträge immer; bisher eingetragene Module bleiben gewählt.
// - Neue Module (in der installierten Version nicht vorhanden) nach
//   updates.newModules: install wählt sie, skip nicht, ask fragt. Ein früher
//   abgelehntes neues Modul wird nicht erneut vorgeschlagen.
// - Vorhandene, aber nicht eingetragene Module (früher abgewählt) bleiben
//   abgewählt.
// - Abgelehnt ist ein neues Modul, das bei der Installation nicht gewählt
//   war; wählt der Benutzer es später, verschwindet es aus der Liste.

interface

uses
  System.SysUtils,
  Atlas.Text.UpdateRun;

type
  /// <summary>Was über die Packages einer Installation bekannt ist (Namen ohne Versionsendung).</summary>
  TUpdateSelectionInput = record
    /// <summary>Packages der neuen Version.</summary>
    Staged: TArray<string>;
    /// <summary>Im Profil aus dem Atlas-Ordner eingetragen.</summary>
    Registered: TArray<string>;
    /// <summary>Im Atlas-Ordner der Plattform vorhanden (installierte Version).</summary>
    Present: TArray<string>;
    Declined: TArray<string>;
    NewModules: TUpdateNewModules;
  end;

  TUpdateSelection = class
  public
    class function Candidates(const AInput: TUpdateSelectionInput): TArray<TUpdateCandidate>; static;
    /// <summary>Neue, nie abgelehnte Module und updates.newModules = ask.</summary>
    class function MustAsk(const ACandidates: TArray<TUpdateCandidate>; ANewModules: TUpdateNewModules): Boolean;
      static;
    /// <summary>Gewählte Namen aus AChosen (leer = Vorschlag) samt Pflicht-Packages; EUpdateError (selection) bei
    /// unbekannten Namen.</summary>
    class function Resolve(const ACandidates: TArray<TUpdateCandidate>; const AChosen: TArray<string>)
      : TArray<string>; static;
    /// <summary>Liste der abgelehnten Module nach der Installation von ASelected.</summary>
    class function Declined(const AOld: TArray<string>; const ACandidates: TArray<TUpdateCandidate>;
      const ASelected: TArray<string>): TArray<string>; static;
    class function Contains(const ANames: TArray<string>; const AName: string): Boolean; static;
    /// <summary>Eine Zeile je Name; leere Zeilen und Leerraum fallen weg.</summary>
    class function ParseLines(const AText: string): TArray<string>; static;
    class function JoinLines(const ANames: TArray<string>): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Updates,
  Atlas.Common.Updates.Contract;

{ TUpdateSelection }

class function TUpdateSelection.Contains(const ANames: TArray<string>; const AName: string): Boolean;
begin
  Result := IndexText(AName, ANames) >= 0;
end;

function Proposed(const ACandidate: TUpdateCandidate; ANewModules: TUpdateNewModules): Boolean;
begin
  if ACandidate.Required or ACandidate.Installed then
  begin
    Exit(True);
  end;
  Result := ACandidate.IsNew and not ACandidate.Declined and (ANewModules <> TUpdateNewModules.Skip);
end;

class function TUpdateSelection.Candidates(const AInput: TUpdateSelectionInput): TArray<TUpdateCandidate>;
var
  mIndex: Integer;
  mName: string;
begin
  SetLength(Result, Length(AInput.Staged));
  for mIndex := 0 to High(AInput.Staged) do
  begin
    mName := AInput.Staged[mIndex];
    Result[mIndex] := Default(TUpdateCandidate);
    Result[mIndex].Name := mName;
    Result[mIndex].Required := TUpdateVersions.IsRequiredPackage(mName);
    Result[mIndex].Installed := Contains(AInput.Registered, mName);
    Result[mIndex].IsNew := not Contains(AInput.Present, mName) and not Result[mIndex].Installed;
    Result[mIndex].Declined := Result[mIndex].IsNew and Contains(AInput.Declined, mName);
    Result[mIndex].Selected := Proposed(Result[mIndex], AInput.NewModules);
  end;
end;

class function TUpdateSelection.MustAsk(const ACandidates: TArray<TUpdateCandidate>;
  ANewModules: TUpdateNewModules): Boolean;
var
  mCandidate: TUpdateCandidate;
begin
  Result := False;
  if ANewModules <> TUpdateNewModules.Ask then
  begin
    Exit;
  end;
  for mCandidate in ACandidates do
  begin
    if mCandidate.IsNew and not mCandidate.Declined and not mCandidate.Required then
    begin
      Result := True;
    end;
  end;
end;

function CandidateNames(const ACandidates: TArray<TUpdateCandidate>): TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(ACandidates));
  for mIndex := 0 to High(ACandidates) do
  begin
    Result[mIndex] := ACandidates[mIndex].Name;
  end;
end;

procedure CheckKnown(const ACandidates: TArray<TUpdateCandidate>; const AChosen: TArray<string>);
var
  mNames: TArray<string>;
  mName: string;
begin
  mNames := CandidateNames(ACandidates);
  for mName in AChosen do
  begin
    if not TUpdateSelection.Contains(mNames, mName) then
    begin
      raise EUpdateError.CreateCode(TUpdateErrors.cSelection, mName);
    end;
  end;
end;

class function TUpdateSelection.Resolve(const ACandidates: TArray<TUpdateCandidate>;
  const AChosen: TArray<string>): TArray<string>;
var
  mCandidate: TUpdateCandidate;
  mList: TList<string>;
  mWanted: Boolean;
begin
  CheckKnown(ACandidates, AChosen);
  mList := TList<string>.Create;
  try
    for mCandidate in ACandidates do
    begin
      mWanted := mCandidate.Required;
      if not mWanted then
      begin
        mWanted := (Length(AChosen) = 0) and mCandidate.Selected;
      end;
      if not mWanted then
      begin
        mWanted := Contains(AChosen, mCandidate.Name);
      end;
      if mWanted then
      begin
        mList.Add(mCandidate.Name);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TUpdateSelection.Declined(const AOld: TArray<string>; const ACandidates: TArray<TUpdateCandidate>;
  const ASelected: TArray<string>): TArray<string>;
var
  mList: TList<string>;
  mName: string;
  mCandidate: TUpdateCandidate;
begin
  mList := TList<string>.Create;
  try
    for mName in AOld do
    begin
      if not Contains(ASelected, mName) then
      begin
        mList.Add(mName);
      end;
    end;
    for mCandidate in ACandidates do
    begin
      if mCandidate.IsNew and not Contains(ASelected, mCandidate.Name) and
        not Contains(mList.ToArray, mCandidate.Name) then
      begin
        mList.Add(mCandidate.Name);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TUpdateSelection.ParseLines(const AText: string): TArray<string>;
var
  mList: TList<string>;
  mLine: string;
begin
  mList := TList<string>.Create;
  try
    for mLine in AText.Replace(#13, '').Split([#10]) do
    begin
      if mLine.Trim <> '' then
      begin
        mList.Add(mLine.Trim);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TUpdateSelection.JoinLines(const ANames: TArray<string>): string;
var
  mName: string;
begin
  Result := '';
  for mName in ANames do
  begin
    Result := Result + mName + #13#10;
  end;
end;

end.
