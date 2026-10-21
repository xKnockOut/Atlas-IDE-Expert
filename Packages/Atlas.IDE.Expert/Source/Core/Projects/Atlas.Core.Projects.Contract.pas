unit Atlas.Core.Projects.Contract;

// Projektkontext für den Server (#396), ohne Open Tools API: was die IDE für
// ein Projekt gerade verwendet (Konfiguration, Plattform, bedingte Symbole,
// Suchpfade, Unit-Namespaces, Bibliothekspfade, Delphi-Version). Die
// IDE-Schicht füllt ihn; die Sitzung schickt ihn in initialize und danach bei
// jeder Änderung als atlas/projectContext. Die Werte bleiben roh, wie sie in
// den Projektoptionen stehen ($(Platform), $(BDS), relative Pfade): Der Server
// löst sie mit den Variablen der Installation auf.
// Contract des Features Projects (A-09, früher Atlas.Core.Projects.Context): Der LSP-Client
// importiert nur ihn, nicht die übrigen Projects-Units.
// Präfixe (#452): Gibt die Projektdatei .atlas (#486) unter "naming" Präfixe für
// Felder, Parameter oder lokale Variablen vor, gehen sie unter "naming" mit; sie
// gelten für die Namensvorschläge vor der Zählung im Projekt.
// Aktives Projekt (#46): "active" markiert das aktive Projekt der Gruppe; der
// Server wählt es für Dateien, die zu mehreren Projekten gehören.

interface

uses
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  /// <summary>Art einer Präfix-Vorgabe; Reihenfolge wie TAtlasNamingKind der Projektdatei.</summary>
  TAtlasProjectNamingKind = (Field, Parameter, Local);
  {$SCOPEDENUMS OFF}

  TAtlasProjectContext = record
  public const
    /// <summary>IOTABuildConfiguration.GetValue mit geerbten Werten.</summary>
    SourceConfiguration = 'Konfiguration';
    /// <summary>GetValue lieferte noch $(Name); die Elternkonfigurationen hat das Plugin selbst eingesetzt.</summary>
    SourceResolved = 'Konfiguration, Erbe selbst aufgelöst';
    /// <summary>Ersatzweg ohne Konfigurationsschnittstelle: IOTAProjectOptions.Values.</summary>
    SourceOptions = 'Projektoptionen';
  public
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
    /// <summary>Präfix-Vorgaben der Projektdatei (#452); nur mit HasNaming gesetzt, '' = ohne Präfix.</summary>
    Naming: array[TAtlasProjectNamingKind] of string;
    HasNaming: array[TAtlasProjectNamingKind] of Boolean;
    /// <summary>Aktives Projekt der Projektgruppe (#46).</summary>
    Active: Boolean;
    /// <summary>Woher Defines, Suchpfade und Namespaces kommen (nur fürs Protokoll, nicht für den
    /// Server): SourceConfiguration, SourceResolved, SourceOptions oder ''.</summary>
    Source: string;
    /// <summary>Durch ";" getrennte Liste aus den Projektoptionen, ohne leere Einträge.</summary>
    class function List(const AValue: string): TArray<string>; static;
    /// <summary>Version aus dem Registry-Schlüssel der IDE, z. B. "Software\Embarcadero\BDS\23.0" → "23.0".</summary>
    class function VersionOfRegistryKey(const AKey: string): string; static;
    /// <summary>
    /// Setzt in AOwn den Verweis $(AName) auf die geerbte Liste durch AParent ein, wie MSBuild es tut
    /// ("DEBUG;$(DCC_Define)"). Leere Einträge entfallen. Ohne Verweis bleibt AOwn.
    /// </summary>
    class function Inherit(const AOwn, AName, AParent: string): string; static;
    /// <summary>Hat AValue noch einen Verweis $(AName) auf sich selbst?</summary>
    class function RefersToItself(const AValue, AName: string): Boolean; static;
    /// <summary>Eine Zeile fürs Diagnoseprotokoll.</summary>
    function Describe: string;
    /// <summary>Gleich, wenn sich für den Server nichts ändert.</summary>
    function Key: string;
    /// <summary>Parameter für atlas/projectContext; gehört dem Aufrufer.</summary>
    function ToJson: TJSONObject;
  end;

implementation

const
  NamingKeys: array[TAtlasProjectNamingKind] of string = ('field', 'parameter', 'local');

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

class function TAtlasProjectContext.RefersToItself(const AValue, AName: string): Boolean;
begin
  Result := Pos(UpperCase('$(' + AName + ')'), UpperCase(AValue)) > 0;
end;

class function TAtlasProjectContext.Inherit(const AOwn, AName, AParent: string): string;
begin
  if not RefersToItself(AOwn, AName) then
    Exit(AOwn);
  Result := string.Join(';', List(StringReplace(AOwn, '$(' + AName + ')', AParent, [rfReplaceAll, rfIgnoreCase])));
end;

function TAtlasProjectContext.Describe: string;
var
  Origin: string;
begin
  Origin := Source;
  if Origin = '' then
    Origin := 'keine Optionen';
  Result := Format('%s %s/%s (%s, BDS %s): Defines %s; %d Suchpfade, %d Namespaces, %d Bibliothekspfade',
    [ExtractFileName(Project), Configuration, Platform, Origin, BdsVersion, string.Join(';', Defines),
    Length(SearchPaths), Length(Namespaces), Length(LibraryPaths)]);
  if Active then
    Result := Result + ', aktiv';
end;

function TAtlasProjectContext.Key: string;
var
  Kind: TAtlasProjectNamingKind;
begin
  Result := AnsiUpperCase(Project) + '|' + Configuration + '|' + Platform + '|' + BdsVersion + '|' +
    string.Join(';', Defines) + '|' + string.Join(';', SearchPaths) + '|' + string.Join(';', Namespaces) + '|' +
    string.Join(';', LibraryPaths) + '|' + BoolToStr(Active, True);
  for Kind := Low(TAtlasProjectNamingKind) to High(TAtlasProjectNamingKind) do
    if HasNaming[Kind] then
      Result := Result + '|' + NamingKeys[Kind] + '=' + Naming[Kind];
end;

function TAtlasProjectContext.ToJson: TJSONObject;
var
  Kind: TAtlasProjectNamingKind;
  Prefixes: TJSONObject;
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
  Result.AddPair('active', TJSONBool.Create(Active));
  Prefixes := nil;
  for Kind := Low(TAtlasProjectNamingKind) to High(TAtlasProjectNamingKind) do
    if HasNaming[Kind] then
    begin
      if Prefixes = nil then
      begin
        Prefixes := TJSONObject.Create;
        Result.AddPair('naming', Prefixes);
      end;
      Prefixes.AddPair(NamingKeys[Kind], Naming[Kind]);
    end;
end;

end.
