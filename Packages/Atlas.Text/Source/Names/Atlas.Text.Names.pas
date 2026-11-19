unit Atlas.Text.Names;

// Namen in Delphi-Quelltext und Units zu Dateinamen (gemeinsam für Server und
// Plugin): letzter Teil eines qualifizierten Namens, Name mit Container,
// Unit-Name einer .pas-Datei, Quelltextdateien (.pas, .dpr, .dpk).

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
    Result := ChangeFileExt(ExtractFileName(AFileName), '');
  end;
end;

class function TTextNames.IsPascalFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.pas') or (mExtension = '.dpr') or (mExtension = '.dpk');
end;

end.
