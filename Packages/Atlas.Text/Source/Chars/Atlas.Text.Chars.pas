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
    class function IsIdentStart(AC: Char): Boolean; static;
    /// <summary>IsIdentStart oder 0–9.</summary>
    class function IsIdentChar(AC: Char): Boolean; static;
    /// <summary>Nur ASCII: A–Z, a–z, 0–9, _.</summary>
    class function IsAsciiIdentChar(AC: Char): Boolean; static;
  end;

implementation

class function TTextChars.IsIdentStart(AC: Char): Boolean;
begin
  Result := ((AC >= 'A') and (AC <= 'Z')) or ((AC >= 'a') and (AC <= 'z')) or (AC = '_') or (Ord(AC) >= 128);
end;

class function TTextChars.IsIdentChar(AC: Char): Boolean;
begin
  Result := IsIdentStart(AC) or ((AC >= '0') and (AC <= '9'));
end;

class function TTextChars.IsAsciiIdentChar(AC: Char): Boolean;
begin
  Result := ((AC >= 'A') and (AC <= 'Z')) or ((AC >= 'a') and (AC <= 'z')) or ((AC >= '0') and (AC <= '9')) or
    (AC = '_');
end;

end.
