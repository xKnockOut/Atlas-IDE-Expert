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
// Formatroutinen (#451): Die eigenen Formatroutinen der Projektdatei gehen unter
// "formatFunctions" mit ([{"name": "Log", "formatIndex": 0}]); der Server zeigt
// für sie die Platzhalter im Parameter-Hint.
// Aktives Projekt (#46): "active" markiert das aktive Projekt der Gruppe; der
// Server wählt es für Dateien, die zu mehreren Projekten gehören.

interface

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON;

type
  {$SCOPEDENUMS ON}
  /// <summary>Art einer Präfix-Vorgabe; Reihenfolge wie TAtlasNamingKind der Projektdatei.</summary>
  TAtlasProjectNamingKind = (Field, Parameter, Local, Constant);
  {$SCOPEDENUMS OFF}

  /// <summary>Eigene Formatroutine der Projektdatei (#451): Name und Stelle des Formatstrings (ab 0).</summary>
  TAtlasProjectFormatFunction = record
    Name: string;
    FormatIndex: Integer;
  end;

  TAtlasProjectContext = record
  public const
    /// <summary>IOTABuildConfiguration.GetValue mit geerbten Werten.</summary>
    cSourceConfiguration = 'Konfiguration';
    /// <summary>GetValue lieferte noch $(Name); die Elternkonfigurationen hat das Plugin selbst eingesetzt.</summary>
    cSourceResolved = 'Konfiguration, Erbe selbst aufgelöst';
    /// <summary>Ersatzweg ohne Konfigurationsschnittstelle: IOTAProjectOptions.Values.</summary>
    cSourceOptions = 'Projektoptionen';
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
    /// <summary>Eigene Formatroutinen der Projektdatei (#451).</summary>
    FormatFunctions: TArray<TAtlasProjectFormatFunction>;
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
  cNamingKeys: array[TAtlasProjectNamingKind] of string = ('field', 'parameter', 'local', 'constant');

function JsonList(const AItems: TArray<string>): TJSONArray;
var
  mItem: string;
begin
  Result := TJSONArray.Create;
  for mItem in AItems do
  begin
    Result.Add(mItem);
  end;
end;

class function TAtlasProjectContext.List(const AValue: string): TArray<string>;
var
  mItem: string;
begin
  Result := nil;
  for mItem in AValue.Split([';']) do
  begin
    if Trim(mItem) <> '' then
    begin
      Result := Result + [Trim(mItem)];
    end;
  end;
end;

class function TAtlasProjectContext.VersionOfRegistryKey(const AKey: string): string;
var
  mKey: string;
begin
  mKey := AKey;
  while mKey.EndsWith('\') do
  begin
    mKey := Copy(mKey, 1, Length(mKey) - 1);
  end;
  Result := Copy(mKey, LastDelimiter('\', mKey) + 1, MaxInt);
  // Nur eine Versionsnummer; ein eigenes Profil (-r) heißt anders.
  if (Result = '') or not CharInSet(Result[1], ['0'..'9']) then
  begin
    Result := '';
  end;
end;

class function TAtlasProjectContext.RefersToItself(const AValue, AName: string): Boolean;
begin
  Result := Pos(UpperCase('$(' + AName + ')'), UpperCase(AValue)) > 0;
end;

class function TAtlasProjectContext.Inherit(const AOwn, AName, AParent: string): string;
begin
  if not RefersToItself(AOwn, AName) then
  begin
    Exit(AOwn);
  end;
  Result := string.Join(';', List(StringReplace(AOwn, '$(' + AName + ')', AParent, [rfReplaceAll, rfIgnoreCase])));
end;

function TAtlasProjectContext.Describe: string;
var
  mOrigin: string;
begin
  mOrigin := Source;
  if mOrigin = '' then
  begin
    mOrigin := 'keine Optionen';
  end;
  Result := Format('%s %s/%s (%s, BDS %s): Defines %s; %d Suchpfade, %d Namespaces, %d Bibliothekspfade',
    [ExtractFileName(Project), Configuration, Platform, mOrigin, BdsVersion, string.Join(';', Defines),
    Length(SearchPaths), Length(Namespaces), Length(LibraryPaths)]);
  if Active then
  begin
    Result := Result + ', aktiv';
  end;
end;

function TAtlasProjectContext.Key: string;
var
  mKind: TAtlasProjectNamingKind;
  mItem: TAtlasProjectFormatFunction;
begin
  Result := AnsiUpperCase(Project) + '|' + Configuration + '|' + Platform + '|' + BdsVersion + '|' +
    string.Join(';', Defines) + '|' + string.Join(';', SearchPaths) + '|' + string.Join(';', Namespaces) + '|' +
    string.Join(';', LibraryPaths) + '|' + BoolToStr(Active, True);
  for mKind := Low(TAtlasProjectNamingKind) to High(TAtlasProjectNamingKind) do
  begin
    if HasNaming[mKind] then
    begin
      Result := Result + '|' + cNamingKeys[mKind] + '=' + Naming[mKind];
    end;
  end;
  for mItem in FormatFunctions do
  begin
    Result := Result + '|format=' + mItem.Name + ':' + IntToStr(mItem.FormatIndex);
  end;
end;

function TAtlasProjectContext.ToJson: TJSONObject;
var
  mKind: TAtlasProjectNamingKind;
  mPrefixes, mEntry: TJSONObject;
  mFunctions: TJSONArray;
  mItem: TAtlasProjectFormatFunction;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', Project);
  Result.AddPair('configuration', Configuration);
  Result.AddPair('platform', Platform);
  if BdsVersion <> '' then
  begin
    Result.AddPair('bdsVersion', BdsVersion);
  end;
  Result.AddPair('defines', JsonList(Defines));
  Result.AddPair('searchPaths', JsonList(SearchPaths));
  Result.AddPair('namespaces', JsonList(Namespaces));
  if Length(LibraryPaths) > 0 then
  begin
    Result.AddPair('libraryPaths', JsonList(LibraryPaths));
  end;
  Result.AddPair('active', TJSONBool.Create(Active));
  mPrefixes := nil;
  for mKind := Low(TAtlasProjectNamingKind) to High(TAtlasProjectNamingKind) do
  begin
    if HasNaming[mKind] then
    begin
      if mPrefixes = nil then
      begin
        mPrefixes := TJSONObject.Create;
        Result.AddPair('naming', mPrefixes);
      end;
      mPrefixes.AddPair(cNamingKeys[mKind], Naming[mKind]);
    end;
  end;
  if Length(FormatFunctions) > 0 then
  begin
    mFunctions := TJSONArray.Create;
    Result.AddPair('formatFunctions', mFunctions);
    for mItem in FormatFunctions do
    begin
      mEntry := TJSONObject.Create;
      mFunctions.AddElement(mEntry);
      mEntry.AddPair('name', mItem.Name);
      mEntry.AddPair('formatIndex', TJSONNumber.Create(mItem.FormatIndex));
    end;
  end;
end;

end.
