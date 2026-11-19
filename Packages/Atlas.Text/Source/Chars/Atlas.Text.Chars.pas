unit Atlas.Text.Chars;

// Zeichenklassen für Bezeichner (gemeinsam für Server und Plugin).
// Delphi erlaubt Unicode-Bezeichner; IsIdentStart und IsIdentChar zählen
// darum jedes Zeichen ab #128 mit. IsAsciiIdentChar ist für Stellen, die
// bewusst nur ASCII-Namen kennen (Schlüssel, Kürzel).

interface

uses
  System.SysUtils;

type
  TTextChars = class
  public
    /// <summary>A–Z, a–z, _ und jedes Zeichen ab #128.</summary>
    class function IsIdentStart(AC: Char): Boolean; static;
    /// <summary>IsIdentStart oder 0–9.</summary>
    class function IsIdentChar(AC: Char): Boolean; static;
    /// <summary>Nur ASCII: A–Z, a–z, 0–9, _.</summary>
    class function IsAsciiIdentChar(AC: Char): Boolean; static;
    /// <summary>Zeichen an AIndex (ab 1); #0 außerhalb von AText.</summary>
    class function CharAt(const AText: string; AIndex: Integer): Char; static;
    /// <summary>Besteht AText nur aus 0–9 und ist nicht leer?</summary>
    class function IsDigits(const AText: string): Boolean; static;
    /// <summary>Position (ab 1) hinter dem ersten AChar ab AFrom; Length(AText) + 2, wenn keins folgt.</summary>
    class function PastNext(const AText: string; AFrom: Integer; AChar: Char): Integer; static;
    /// <summary>Position (ab 1) hinter der Folge von Zeichen aus AChars ab AIndex; AIndex, wenn dort keins
    /// steht.</summary>
    class function RunEnd(const AText: string; AIndex: Integer; const AChars: TSysCharSet): Integer; static;
    /// <summary>Position (ab 1) hinter den Bezeichnerzeichen (IsIdentChar) ab AIndex.</summary>
    class function IdentEnd(const AText: string; AIndex: Integer): Integer; static;
    /// <summary>Position (ab 1) hinter den ASCII-Bezeichnerzeichen (IsAsciiIdentChar) ab AIndex.</summary>
    class function AsciiIdentEnd(const AText: string; AIndex: Integer): Integer; static;
  end;

implementation

uses
  Atlas.Text.Encoding;

{ TTextChars }

class function TTextChars.IsIdentStart(AC: Char): Boolean;
begin
  Result := ((AC >= 'A') and (AC <= 'Z')) or ((AC >= 'a') and (AC <= 'z')) or (AC = '_') or
    (Ord(AC) >= TTextEncodingProbe.cFirstNonAscii);
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

class function TTextChars.CharAt(const AText: string; AIndex: Integer): Char;
begin
  Result := #0;
  if (AIndex >= 1) and (AIndex <= Length(AText)) then
  begin
    Result := AText[AIndex];
  end;
end;

class function TTextChars.IsDigits(const AText: string): Boolean;
var
  mChar: Char;
begin
  Result := AText <> '';
  for mChar in AText do
  begin
    if (mChar < '0') or (mChar > '9') then
    begin
      Exit(False);
    end;
  end;
end;

class function TTextChars.PastNext(const AText: string; AFrom: Integer; AChar: Char): Integer;
begin
  Result := AFrom;
  while (Result <= Length(AText)) and (AText[Result] <> AChar) do
  begin
    Inc(Result);
  end;
  Inc(Result);
end;

class function TTextChars.RunEnd(const AText: string; AIndex: Integer; const AChars: TSysCharSet): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and CharInSet(AText[Result], AChars) do
  begin
    Inc(Result);
  end;
end;

class function TTextChars.IdentEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and IsIdentChar(AText[Result]) do
  begin
    Inc(Result);
  end;
end;

class function TTextChars.AsciiIdentEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and IsAsciiIdentChar(AText[Result]) do
  begin
    Inc(Result);
  end;
end;

end.
