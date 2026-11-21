unit Atlas.Text.Names;

// Namen in Delphi-Quelltext und Units zu Dateinamen (gemeinsam für Server und
// Plugin): letzter Teil eines qualifizierten Namens, Name mit Container,
// Unit-Name einer .pas-Datei, Quelltextdateien (.pas, .dpr, .dpk), Kennungen
// ohne führendes "#".

interface

type
  TTextNames = class
  public
    /// <summary>Teil hinter dem letzten Punkt ("Unit.TKlasse.Methode" → "Methode"); ohne Punkt AName.</summary>
    class function LastPart(const AName: string): string; static;
    /// <summary>"AContainer.AName"; ohne Container nur AName.</summary>
    class function Qualified(const AContainer, AName: string): string; static;
    /// <summary>Unit-Name einer .pas-Datei (Dateiname ohne Endung); '' für andere Dateien.</summary>
    class function UnitNameOf(const AFileName: string): string; static;
    /// <summary>Endet AFileName auf .pas, .dpr oder .dpk (ohne Rücksicht auf Groß-/Kleinschreibung)?</summary>
    class function IsPascalFile(const AFileName: string): Boolean; static;
    /// <summary>Kennung ohne Leerraum außen und ohne führende "#" ("#753" → "753"); "ATL-123" bleibt.</summary>
    class function KeyWithoutHash(const AKey: string): string; static;
  end;

implementation

uses
  System.SysUtils;

{ TTextNames }

class function TTextNames.LastPart(const AName: string): string;
var
  mDot: Integer;
begin
  Result := AName;
  mDot := LastDelimiter('.', Result);
  if mDot > 0 then
  begin
    Result := Copy(Result, mDot + 1, MaxInt);
  end;
end;

class function TTextNames.Qualified(const AContainer, AName: string): string;
begin
  if AContainer = '' then
  begin
    Result := AName;
  end
  else
  begin
    Result := AContainer + '.' + AName;
  end;
end;

class function TTextNames.UnitNameOf(const AFileName: string): string;
begin
  Result := '';
  if SameText(ExtractFileExt(AFileName), '.pas') then
  begin
    // ExtractFileName trennt unter Windows nur an '\': Pfade mit '/' vorher angleichen.
    Result := ChangeFileExt(ExtractFileName(AFileName.Replace('/', PathDelim)), '');
  end;
end;

class function TTextNames.IsPascalFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk');
end;

class function TTextNames.KeyWithoutHash(const AKey: string): string;
begin
  Result := Trim(AKey);
  while (Result <> '') and (Result[1] = '#') do
  begin
    Delete(Result, 1, 1);
  end;
end;

end.
