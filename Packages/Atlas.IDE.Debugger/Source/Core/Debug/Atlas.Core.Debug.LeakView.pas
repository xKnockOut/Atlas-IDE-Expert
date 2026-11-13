unit Atlas.Core.Debug.LeakView;

// Inhalt des Fensters „Atlas-Lecks“ (#1875), ohne VCL: Zeilen je gemeldetem
// Namen mit Vergleich zum letzten Lauf, darunter je Klasse die Stellen.
//   - Ohne Aufrufstapel: Kandidaten des Servers (atlas.server.leakCandidates),
//     gelesen aus seiner Antwort, nach seiner Bewertung sortiert.
//   - Mit Aufrufstapeln (FullDebugMode): die Gruppen des Berichts mit ihrer
//     Erzeugungsstelle; Kandidaten braucht es dann nicht.
//   - Strings und unbekannte Blöcke folgen meist aus geleakten Objekten: ein
//     Hinweis darunter, wenn auch Objekte geleakt sind.
//   - „Bekannte ausblenden“ lässt bekannte Namen samt Stellen weg.

interface

uses
  Atlas.Text.LeakReport,
  Atlas.Core.Debug.LeakCapture;

type
  /// <summary>Kandidat des Servers; Zeile und Zeichen 0-basiert.</summary>
  TAtlasLeakPlace = record
    ClassName: string;
    FileName: string;
    Line: Integer;
    Character: Integer;
    /// <summary>Bewertung wie der Server sie nennt (neverFreed, returned …).</summary>
    Rating: string;
    Target: string;
    Routine: string;
  end;

{$SCOPEDENUMS ON}
  TAtlasLeakRowKind = (Name, Place, Group, Hint);
{$SCOPEDENUMS OFF}

  TAtlasLeakRow = record
    Kind: TAtlasLeakRowKind;
    /// <summary>Zeile des Namens (Kind = Name) bzw. der Name, zu dem die Stelle gehört.</summary>
    Entry: TAtlasLeakEntry;
    /// <summary>Stellen unter dem Namen (Kind = Name): Kandidaten oder Gruppen.</summary>
    PlaceCount: Integer;
    Place: TAtlasLeakPlace;
    Group: TLeakGroup;
  end;

  TAtlasLeakViews = class
  public const
    cCandidatesCommand = 'atlas.server.leakCandidates';
  public
    /// <summary>Argumente für atlas.server.leakCandidates: [uri des Projekts, {report}].</summary>
    class function CandidateArgumentsJson(const AProjectFile, AReportText: string): string; static;
    /// <summary>Kandidaten aus der Antwort des Servers; leer bei unlesbarer Antwort.</summary>
    class function PlacesFromJson(const AJson: string): TArray<TAtlasLeakPlace>; static;
    /// <summary>Zeilen des Fensters in der Reihenfolge der Einträge.</summary>
    class function Rows(const AEntries: TArray<TAtlasLeakEntry>; const APlaces: TArray<TAtlasLeakPlace>;
      const AGroups: TArray<TLeakGroup>; AHideKnown: Boolean): TArray<TAtlasLeakRow>; static;
    /// <summary>Gibt es eine Stelle zum Springen (Kandidat oder Gruppe mit Datei und Zeile)?</summary>
    class function CanOpen(const ARow: TAtlasLeakRow): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.Json,
  Atlas.Core.Lsp.Uris;

class function TAtlasLeakViews.CandidateArgumentsJson(const AProjectFile, AReportText: string): string;
var
  mArguments: TJSONArray;
  mOptions: TJSONObject;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(TLspUris.FromPath(AProjectFile));
    mOptions := TJSONObject.Create;
    mOptions.AddPair('report', AReportText);
    mArguments.AddElement(mOptions);
    Result := mArguments.ToJSON([]);
  finally
    mArguments.Free;
  end;
end;

function PlaceOf(AItem: TJSONObject): TAtlasLeakPlace;
begin
  Result := Default(TAtlasLeakPlace);
  Result.ClassName := TJsonRead.Text(AItem, 'className');
  Result.FileName := TLspUris.ToPath(TJsonRead.Text(AItem, 'uri'));
  Result.Line := TJsonRead.Int(AItem, 'line');
  Result.Character := TJsonRead.Int(AItem, 'character');
  Result.Rating := TJsonRead.Text(AItem, 'rating');
  Result.Target := TJsonRead.Text(AItem, 'target');
  Result.Routine := TJsonRead.Text(AItem, 'routine');
end;

class function TAtlasLeakViews.PlacesFromJson(const AJson: string): TArray<TAtlasLeakPlace>;
var
  mAnswer: TJSONObject;
  mItems: TJSONArray;
  mItem: TJSONValue;
  mCount: Integer;
begin
  Result := nil;
  mAnswer := TJsonRead.ParseObject(AJson);
  try
    mItems := TJsonRead.Items(mAnswer, 'candidates');
    if mItems = nil then
    begin
      Exit;
    end;
    SetLength(Result, mItems.Count);
    mCount := 0;
    for mItem in mItems do
    begin
      if mItem is TJSONObject then
      begin
        Result[mCount] := PlaceOf(TJSONObject(mItem));
        Inc(mCount);
      end;
    end;
    SetLength(Result, mCount);
  finally
    mAnswer.Free;
  end;
end;

function HasInstances(const AEntries: TArray<TAtlasLeakEntry>): Boolean;
var
  mEntry: TAtlasLeakEntry;
begin
  for mEntry in AEntries do
  begin
    if mEntry.Kind = TLeakKind.Instance then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Zeilen der Stellen zu AEntry: Gruppen mit Stapeln, sonst Kandidaten.</summary>
function PlaceRows(const AEntry: TAtlasLeakEntry; const APlaces: TArray<TAtlasLeakPlace>;
  const AGroups: TArray<TLeakGroup>): TArray<TAtlasLeakRow>;
var
  mRow: TAtlasLeakRow;
  mPlace: TAtlasLeakPlace;
  mGroup: TLeakGroup;
begin
  Result := nil;
  for mGroup in AGroups do
  begin
    if SameText(mGroup.Name, AEntry.Name) then
    begin
      mRow := Default(TAtlasLeakRow);
      mRow.Kind := TAtlasLeakRowKind.Group;
      mRow.Entry := AEntry;
      mRow.Group := mGroup;
      Result := Result + [mRow];
    end;
  end;
  if Length(AGroups) > 0 then
  begin
    Exit;
  end;
  for mPlace in APlaces do
  begin
    if SameText(mPlace.ClassName, AEntry.Name) then
    begin
      mRow := Default(TAtlasLeakRow);
      mRow.Kind := TAtlasLeakRowKind.Place;
      mRow.Entry := AEntry;
      mRow.Place := mPlace;
      Result := Result + [mRow];
    end;
  end;
end;

class function TAtlasLeakViews.Rows(const AEntries: TArray<TAtlasLeakEntry>; const APlaces: TArray<TAtlasLeakPlace>;
  const AGroups: TArray<TLeakGroup>; AHideKnown: Boolean): TArray<TAtlasLeakRow>;
var
  mEntry: TAtlasLeakEntry;
  mRow: TAtlasLeakRow;
  mPlaces: TArray<TAtlasLeakRow>;
  mInstances: Boolean;
begin
  Result := nil;
  mInstances := HasInstances(AEntries);
  for mEntry in AEntries do
  begin
    if AHideKnown and mEntry.Known then
    begin
      Continue;
    end;
    mPlaces := PlaceRows(mEntry, APlaces, AGroups);
    mRow := Default(TAtlasLeakRow);
    mRow.Kind := TAtlasLeakRowKind.Name;
    mRow.Entry := mEntry;
    mRow.PlaceCount := Length(mPlaces);
    Result := Result + [mRow] + mPlaces;
    if (mEntry.Kind <> TLeakKind.Instance) and mInstances then
    begin
      mRow.Kind := TAtlasLeakRowKind.Hint;
      mRow.PlaceCount := 0;
      Result := Result + [mRow];
    end;
  end;
end;

class function TAtlasLeakViews.CanOpen(const ARow: TAtlasLeakRow): Boolean;
begin
  case ARow.Kind of
    TAtlasLeakRowKind.Place:
      Result := ARow.Place.FileName <> '';
    TAtlasLeakRowKind.Group:
      Result := (ARow.Group.Site >= 0) and (ARow.Group.Frames[ARow.Group.Site].FileName <> '') and
        (ARow.Group.Frames[ARow.Group.Site].Line > 0);
  else
    Result := False;
  end;
end;

end.
