unit Atlas.Core.Settings.DataBreakClasses;

// Liste der beobachteten Klassen für debug.dataBreaks.classes (#870):
// Vorgabe, Zerlegen und Normalisieren. Liegt bei den Einstellungen, damit
// der Parser ohne den Debug-Kern auskommt (wie
// Atlas.Core.Settings.EventBreakNames); welche Methoden und Ausdrücke zu einer
// Klasse gehören, weiß Atlas.Core.Debug.DataBreak.
// Ein Eintrag ist ein Klassenname (TFDQuery) oder ein Klassenname mit Art
// (TMeineAbfrage=sql, TMeinClient=http) für Klassen, die der Kern nicht kennt.
// Getrennt wird an Komma, Semikolon und Zeilenumbruch.

interface

uses
  System.SysUtils;

type
  TAtlasDataBreakClassEntry = record
    Name: string;
    /// <summary>sql, http oder '' (Art aus der Tabelle des Kerns).</summary>
    Kind: string;
  end;

  TAtlasDataBreakSettings = class
  public const
    cKindSql = 'sql';
    cKindHttp = 'http';
    cDefaultClasses = 'TFDQuery, TFDCommand, TFDConnection, TFDStoredProc, TSQLQuery, TSQLDataSet, ' +
      'TSQLConnection, TADOQuery, TADOCommand, TADOConnection, TADODataSet, TZQuery, TZReadOnlyQuery, ' +
      'TZConnection, THTTPClient, TNetHTTPClient, TRESTRequest, TIdHTTP';
  private
    class function EntryOf(const APart: string; out AEntry: TAtlasDataBreakClassEntry): Boolean; static;
  public
    /// <summary>Einträge aus AText: getrimmt, ohne Leere und Doppelte (Name ohne Rücksicht auf
    /// Groß-/Kleinschreibung, der erste gewinnt), Reihenfolge bleibt. Eine unbekannte Art fällt weg, der Name
    /// bleibt.</summary>
    class function Entries(const AText: string): TArray<TAtlasDataBreakClassEntry>; static;
    /// <summary>Aufgeräumt wie Entries, mit „, “ verbunden (TFDQuery, TMeineAbfrage=sql).</summary>
    class function NormalizeClasses(const AText: string): string; static;
  end;

implementation

{ TAtlasDataBreakSettings }

class function TAtlasDataBreakSettings.EntryOf(const APart: string; out AEntry: TAtlasDataBreakClassEntry): Boolean;
var
  mEqual: Integer;
begin
  AEntry := Default(TAtlasDataBreakClassEntry);
  mEqual := Pos('=', APart);
  if mEqual > 0 then
  begin
    AEntry.Name := Trim(Copy(APart, 1, mEqual - 1));
    AEntry.Kind := LowerCase(Trim(Copy(APart, mEqual + 1, MaxInt)));
    if (AEntry.Kind <> cKindSql) and (AEntry.Kind <> cKindHttp) then
    begin
      AEntry.Kind := '';
    end;
  end
  else
  begin
    AEntry.Name := Trim(APart);
  end;
  Result := AEntry.Name <> '';
end;

class function TAtlasDataBreakSettings.Entries(const AText: string): TArray<TAtlasDataBreakClassEntry>;
var
  mPart: string;
  mEntry, mExisting: TAtlasDataBreakClassEntry;
  mFound: Boolean;
begin
  Result := nil;
  for mPart in AText.Split([',', ';', #13, #10]) do
  begin
    if not EntryOf(mPart, mEntry) then
    begin
      Continue;
    end;
    mFound := False;
    for mExisting in Result do
    begin
      mFound := mFound or SameText(mExisting.Name, mEntry.Name);
    end;
    if not mFound then
    begin
      Result := Result + [mEntry];
    end;
  end;
end;

class function TAtlasDataBreakSettings.NormalizeClasses(const AText: string): string;
var
  mEntry: TAtlasDataBreakClassEntry;
  mParts: TArray<string>;
begin
  mParts := nil;
  for mEntry in Entries(AText) do
  begin
    if mEntry.Kind <> '' then
    begin
      mParts := mParts + [mEntry.Name + '=' + mEntry.Kind];
    end
    else
    begin
      mParts := mParts + [mEntry.Name];
    end;
  end;
  Result := string.Join(', ', mParts);
end;

end.
