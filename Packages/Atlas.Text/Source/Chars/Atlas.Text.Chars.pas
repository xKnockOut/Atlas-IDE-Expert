unit Atlas.Text.Chars;

// Zeichenklassen für Bezeichner (gemeinsam für Server und Plugin, ADR 0012).
// Delphi erlaubt Unicode-Bezeichner; IsIdentStart und IsIdentChar zählen
// darum jedes Zeichen ab #128 mit. IsAsciiIdentChar ist für Stellen, die
// bewusst nur ASCII-Namen kennen (Schlüssel, Kürzel).

interface

type
  TTextChars = class
  public
    /// <summary>A–Z, a–z, _ und jedes Zeichen ab #128.</summary>
    class function IsIdentStart(C: Char): Boolean; static;
    /// <summary>IsIdentStart oder 0–9.</summary>
    class function IsIdentChar(C: Char): Boolean; static;
    /// <summary>Nur ASCII: A–Z, a–z, 0–9, _.</summary>
    class function IsAsciiIdentChar(C: Char): Boolean; static;
  end;

implementation

class function TTextChars.IsIdentStart(C: Char): Boolean;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or (C = '_') or (Ord(C) >= 128);
end;

class function TTextChars.IsIdentChar(C: Char): Boolean;
begin
  Result := IsIdentStart(C) or ((C >= '0') and (C <= '9'));
end;

class function TTextChars.IsAsciiIdentChar(C: Char): Boolean;
begin
  Result := ((C >= 'A') and (C <= 'Z')) or ((C >= 'a') and (C <= 'z')) or ((C >= '0') and (C <= '9')) or (C = '_');
end;

end.
