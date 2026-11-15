unit Atlas.Core.Debug.BreakpointSetFlow;

// Entscheidungen der Haltepunkt-Sätze (#586) außerhalb von Speichern und Plan, ohne IDE prüfbar (#1967): Satz zum
// gewählten Namen, Branch beim Überschreiben, Einträge der anderen Sätze beim Wechseln und die Stellen der Sätze
// für das Haltepunktfenster (#863). Atlas.IDE.Debug.BreakpointSets fragt Debugger, Dateien und Dialog.

interface

uses
  System.Classes,
  Atlas.Core.Debug.BreakpointSets;

type
  TAtlasBreakpointSetFlow = class
  public
    /// <summary>Index des Satzes AName (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    class function IndexOfName(const ASets: TAtlasBreakpointSetList; const AName: string): Integer; static;
    /// <summary>Branch beim Speichern unter AName: ohne neue Kopplung (ABranch und ACurrentBranch leer) bleibt der
    /// Branch eines vorhandenen Satzes gleichen Namens.</summary>
    class function KeepBranch(const ASets: TAtlasBreakpointSetList; const AName, ABranch,
      ACurrentBranch: string): string; static;
    /// <summary>Einträge aller Sätze außer ASets[AIndex]; nil ohne AExclusive.</summary>
    class function OthersOf(const ASets: TAtlasBreakpointSetList; AIndex: Integer;
      AExclusive: Boolean): TAtlasBreakpointSetEntries; static;
    /// <summary>Schlüssel einer Stelle: Datei klein und Zeile (ab 0).</summary>
    class function PlaceKey(const AFileName: string; ALine: Integer): string; static;
    /// <summary>Stellen aller Sätze in APlaces (Name=Wert: Schlüssel, Namen mit Tab getrennt); nicht gefundene
    /// Einträge fehlen.</summary>
    class procedure FillPlaces(APlaces: TStrings; const ASets: TAtlasBreakpointSetList;
      const AText: TAtlasBreakpointTextFunc); static;
    /// <summary>Namen der Sätze an AFileName/ALine; nil ohne.</summary>
    class function NamesAt(APlaces: TStrings; const AFileName: string; ALine: Integer): TArray<string>; static;
    /// <summary>Stellen neu lesen: noch keine (AHave = False) oder älter als AMaxAgeMs.</summary>
    class function PlacesStale(AHave: Boolean; ANowMs, AReadAtMs: UInt64; AMaxAgeMs: Integer): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasBreakpointSetFlow }

class function TAtlasBreakpointSetFlow.IndexOfName(const ASets: TAtlasBreakpointSetList;
  const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ASets) do
  begin
    if SameText(ASets[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasBreakpointSetFlow.KeepBranch(const ASets: TAtlasBreakpointSetList; const AName, ABranch,
  ACurrentBranch: string): string;
var
  mIndex: Integer;
begin
  Result := ABranch;
  for mIndex := 0 to High(ASets) do
  begin
    if SameText(ASets[mIndex].Name, AName) and (Result = '') and (ACurrentBranch = '') then
    begin
      Result := ASets[mIndex].Branch;
    end;
  end;
end;

class function TAtlasBreakpointSetFlow.OthersOf(const ASets: TAtlasBreakpointSetList; AIndex: Integer;
  AExclusive: Boolean): TAtlasBreakpointSetEntries;
var
  mIndex: Integer;
begin
  Result := nil;
  if not AExclusive then
  begin
    Exit;
  end;
  for mIndex := 0 to High(ASets) do
  begin
    if mIndex <> AIndex then
    begin
      Result := Result + ASets[mIndex].Entries;
    end;
  end;
end;

class function TAtlasBreakpointSetFlow.PlaceKey(const AFileName: string; ALine: Integer): string;
begin
  Result := LowerCase(AFileName) + '|' + IntToStr(ALine);
end;

class procedure TAtlasBreakpointSetFlow.FillPlaces(APlaces: TStrings; const ASets: TAtlasBreakpointSetList;
  const AText: TAtlasBreakpointTextFunc);
var
  mSet: TAtlasBreakpointSet;
  mItem: TAtlasResolvedBreakpoint;
  mKey: string;
  mIndex: Integer;
begin
  APlaces.Clear;
  for mSet in ASets do
  begin
    for mItem in TAtlasBreakpointSets.Resolve(mSet.Entries, AText) do
    begin
      if not mItem.Found then
      begin
        Continue;
      end;
      mKey := PlaceKey(mItem.Entry.FileName, mItem.Line);
      mIndex := APlaces.IndexOfName(mKey);
      if mIndex < 0 then
      begin
        APlaces.Add(mKey + '=' + mSet.Name);
      end
      else
      begin
        APlaces.ValueFromIndex[mIndex] := APlaces.ValueFromIndex[mIndex] + #9 + mSet.Name;
      end;
    end;
  end;
end;

class function TAtlasBreakpointSetFlow.NamesAt(APlaces: TStrings; const AFileName: string;
  ALine: Integer): TArray<string>;
var
  mNames: string;
begin
  Result := nil;
  mNames := APlaces.Values[PlaceKey(AFileName, ALine)];
  if mNames <> '' then
  begin
    Result := mNames.Split([#9]);
  end;
end;

class function TAtlasBreakpointSetFlow.PlacesStale(AHave: Boolean; ANowMs, AReadAtMs: UInt64;
  AMaxAgeMs: Integer): Boolean;
begin
  Result := not AHave or (ANowMs - AReadAtMs >= UInt64(AMaxAgeMs));
end;

end.
