unit Atlas.Core.Debug.BreakLocations;

// Haltestellen vorübergehender Haltepunkte, gemeinsam für „Beim nächsten
// Ereignis anhalten“ (#856) und „Anhalten bei Datenzugriff“ (#870): je Datei
// und Zeile ein Haltepunkt, dazu die Indizes der Einträge (Handler bzw.
// Aufrufstellen), die dort liegen.

interface

uses
  System.SysUtils;

type
  TAtlasBreakLocation = record
    FileName: string;
    /// <summary>Zeile (ab 0) des Haltepunkts.</summary>
    Line: Integer;
    /// <summary>Indizes der Einträge an dieser Stelle.</summary>
    Items: TArray<Integer>;
  end;

  TAtlasBreakLocations = class
  public
    /// <summary>Haltestelle an AFileName/ALine (Datei ohne Rücksicht auf Groß-/Kleinschreibung); -1 ohne.</summary>
    class function IndexOf(const ALocations: TArray<TAtlasBreakLocation>; const AFileName: string;
      ALine: Integer): Integer; static;
    /// <summary>Eintrag AItem an AFileName/ALine: an die bestehende Haltestelle oder als neue hinten an.</summary>
    class procedure Add(var ALocations: TArray<TAtlasBreakLocation>; const AFileName: string;
      ALine, AItem: Integer); static;
  end;

implementation

{ TAtlasBreakLocations }

class function TAtlasBreakLocations.IndexOf(const ALocations: TArray<TAtlasBreakLocation>; const AFileName: string;
  ALine: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ALocations) do
  begin
    if (ALocations[mIndex].Line = ALine) and SameText(ALocations[mIndex].FileName, AFileName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

class procedure TAtlasBreakLocations.Add(var ALocations: TArray<TAtlasBreakLocation>; const AFileName: string;
  ALine, AItem: Integer);
var
  mFound: Integer;
  mLocation: TAtlasBreakLocation;
begin
  mFound := IndexOf(ALocations, AFileName, ALine);
  if mFound >= 0 then
  begin
    ALocations[mFound].Items := ALocations[mFound].Items + [AItem];
    Exit;
  end;
  mLocation := Default(TAtlasBreakLocation);
  mLocation.FileName := AFileName;
  mLocation.Line := ALine;
  mLocation.Items := [AItem];
  ALocations := ALocations + [mLocation];
end;

end.
