unit Rules.Builtin.Texts.Shared;

// Gemeinsame Hilfen der Regeln für Texte in String-Literalen: Format-Platzhalter erkennen und entscheiden, ob ein
// Literal nach Text für Menschen aussieht (hardcoded-string, text-concat-without-space #3042).

interface

type
  /// <summary>Einschätzungen über den Klartext eines String-Literals.</summary>
  TLiteralTexts = class
  public
    /// <summary>Länge des Format-Platzhalters ab AIndex (%s, %d, %0:s, %-8.2f, %*d, %%), sonst 0.</summary>
    class function FormatSpecifierLength(const AValue: string; AIndex: Integer): Integer; static;
    /// <summary>Endet AValue mit einem Format-Platzhalter (…%s, …%0:d, …%.2f)?</summary>
    class function EndsWithFormatSpecifier(const AValue: string): Boolean; static;
    /// <summary>Sieht der Literalinhalt nach Text für Menschen aus: mindestens drei Buchstaben und ein Leerzeichen?
    /// Format-Platzhalter (%s, %d …) zählen nicht als Buchstaben: '%s → %s (%s)' ist eine Vorlage ohne Text.</summary>
    class function LooksLikeText(const AValue: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.Character;

class function TLiteralTexts.FormatSpecifierLength(const AValue: string; AIndex: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  if (AIndex < 1) or (AIndex >= Length(AValue)) or (AValue[AIndex] <> '%') then
  begin
    Exit;
  end;
  mIndex := AIndex + 1;
  if AValue[mIndex] = '%' then
  begin
    Exit(2);
  end;
  while (mIndex <= Length(AValue)) and CharInSet(AValue[mIndex], ['0'..'9', '*', ':', '-', '.']) do
  begin
    Inc(mIndex);
  end;
  if (mIndex <= Length(AValue)) and CharInSet(AValue[mIndex], ['d', 'u', 'e', 'f', 'g', 'n', 'm', 'p', 's', 'x',
    'D', 'U', 'E', 'F', 'G', 'N', 'M', 'P', 'S', 'X']) then
  begin
    Result := mIndex - AIndex + 1;
  end;
end;

class function TLiteralTexts.EndsWithFormatSpecifier(const AValue: string): Boolean;
var
  mIndex, mLength: Integer;
begin
  // Von hinten das letzte % suchen; der Platzhalter ab dort muss genau bis zum Ende reichen. %% davor zählt als
  // Prozentzeichen, nicht als Platzhalter.
  mIndex := LastDelimiter('%', AValue);
  if mIndex = 0 then
  begin
    Exit(False);
  end;
  if (mIndex > 1) and (AValue[mIndex - 1] = '%') then
  begin
    Exit(False);
  end;
  mLength := FormatSpecifierLength(AValue, mIndex);
  Result := (mLength > 0) and (mIndex + mLength - 1 = Length(AValue));
end;

class function TLiteralTexts.LooksLikeText(const AValue: string): Boolean;
var
  mIndex, mLetters, mSpecifier: Integer;
begin
  mLetters := 0;
  mIndex := 1;
  while mIndex <= Length(AValue) do
  begin
    mSpecifier := FormatSpecifierLength(AValue, mIndex);
    if mSpecifier > 0 then
    begin
      Inc(mIndex, mSpecifier);
      Continue;
    end;
    if AValue[mIndex].IsLetter then
    begin
      Inc(mLetters);
    end;
    Inc(mIndex);
  end;
  Result := (mLetters >= 3) and (Pos(' ', Trim(AValue)) > 0);
end;

end.
