unit Atlas.Core.Projects.Context;

// Projektkontext für den Server (#396), ohne Open Tools API: was die IDE für
// ein Projekt gerade verwendet (Konfiguration, Plattform, bedingte Symbole,
// Suchpfade, Unit-Namespaces, Bibliothekspfade, Delphi-Version). Die
// IDE-Schicht füllt ihn; die Sitzung schickt ihn in initialize und danach bei
// jeder Änderung als atlas/projectContext. Die Werte bleiben roh, wie sie in
// den Projektoptionen stehen ($(Platform), $(BDS), relative Pfade): Der Server
// löst sie mit den Variablen der Installation auf.

interface

uses
  System.SysUtils,
  System.JSON;

type
  TAtlasProjectContext = record
    /// <summary>Absoluter Pfad der .dproj.</summary>
    Project: string;
    Configuration: string;
    Platform: string;
    /// <summary>Version der laufenden IDE, z. B. "23.0".</summary>
    BdsVersion: string;
    Defines: TArray<string>;
    SearchPaths: TArray<string>;
    Namespaces: TArray<string>;
    LibraryPaths: TArray<string>;
    /// <summary>Durch ";" getrennte Liste aus den Projektoptionen, ohne leere Einträge.</summary>
    class function List(const AValue: string): TArray<string>; static;
    /// <summary>Version aus dem Registry-Schlüssel der IDE, z. B. "Software\Embarcadero\BDS\23.0" → "23.0".</summary>
    class function VersionOfRegistryKey(const AKey: string): string; static;
    /// <summary>Gleich, wenn sich für den Server nichts ändert.</summary>
    function Key: string;
    /// <summary>Parameter für atlas/projectContext; gehört dem Aufrufer.</summary>
    function ToJson: TJSONObject;
  end;

implementation

function JsonList(const AItems: TArray<string>): TJSONArray;
var
  Item: string;
begin
  Result := TJSONArray.Create;
  for Item in AItems do
    Result.Add(Item);
end;

class function TAtlasProjectContext.List(const AValue: string): TArray<string>;
var
  Item: string;
begin
  Result := nil;
  for Item in AValue.Split([';']) do
    if Trim(Item) <> '' then
      Result := Result + [Trim(Item)];
end;

class function TAtlasProjectContext.VersionOfRegistryKey(const AKey: string): string;
var
  Key: string;
begin
  Key := AKey;
  while Key.EndsWith('\') do
    Key := Copy(Key, 1, Length(Key) - 1);
  Result := Copy(Key, LastDelimiter('\', Key) + 1, MaxInt);
  // Nur eine Versionsnummer; ein eigenes Profil (-r) heißt anders.
  if (Result = '') or not CharInSet(Result[1], ['0'..'9']) then
    Result := '';
end;

function TAtlasProjectContext.Key: string;
begin
  Result := AnsiUpperCase(Project) + '|' + Configuration + '|' + Platform + '|' + BdsVersion + '|' +
    string.Join(';', Defines) + '|' + string.Join(';', SearchPaths) + '|' + string.Join(';', Namespaces) + '|' +
    string.Join(';', LibraryPaths);
end;

function TAtlasProjectContext.ToJson: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', Project);
  Result.AddPair('configuration', Configuration);
  Result.AddPair('platform', Platform);
  if BdsVersion <> '' then
    Result.AddPair('bdsVersion', BdsVersion);
  Result.AddPair('defines', JsonList(Defines));
  Result.AddPair('searchPaths', JsonList(SearchPaths));
  Result.AddPair('namespaces', JsonList(Namespaces));
  if Length(LibraryPaths) > 0 then
    Result.AddPair('libraryPaths', JsonList(LibraryPaths));
end;

end.
