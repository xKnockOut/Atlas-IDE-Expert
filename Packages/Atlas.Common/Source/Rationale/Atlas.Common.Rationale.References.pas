unit Atlas.Common.Rationale.References;

// Verweise im Text einer Begründung (#1123): ADR-0007, ADR 7 bzw. ADR7 auf
// eine Architekturentscheidung, #312 auf ein Issue, http(s)-Adressen. Ein
// Verweis beginnt und endet nicht mitten in einem Bezeichner und nicht neben
// &, # oder $ (&#312;, $1F). AdrFile sucht die Datei zur Nummer im ADR-Ordner.

interface

uses
  Atlas.Common.Rationale.Contract;

type
  TRationaleReferences = class
  public
    /// <summary>Verweise in AText, nach Anfang sortiert.</summary>
    class function Find(const AText: string): TArray<TRationaleLink>; static;
    /// <summary>Datei zur Entscheidung AKey ("7") aus AFileNames: Der Dateiname (ohne Ordner) beginnt mit der
    /// Nummer, auch mit führenden Nullen oder "ADR-" davor, gefolgt von "-", "_", "." oder Leerzeichen; bei
    /// mehreren die erste nach Name. '' ohne.</summary>
    class function AdrFile(const AKey: string; const AFileNames: TArray<string>): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Chars;

function IsDigit(ACh: Char): Boolean;
begin
  Result := CharInSet(ACh, ['0'..'9']);
end;

/// <summary>Zeichen, neben dem kein Verweis beginnt bzw. endet: Bezeichner, &, # und $ (z. B. &#312;, $1F).
/// </summary>
function JoinsLink(ACh: Char): Boolean;
begin
  Result := TTextChars.IsIdentChar(ACh) or CharInSet(ACh, ['&', '#', '$']);
end;

function WithoutLeadingZeros(const ADigits: string): string;
begin
  Result := ADigits;
  while (Length(Result) > 1) and (Result[1] = '0') do
    Delete(Result, 1, 1);
end;

class function TRationaleReferences.Find(const AText: string): TArray<TRationaleLink>;
var
  mIndex, mEnd, mDigits: Integer;
  mLink: TRationaleLink;
  mLower: string;
begin
  Result := nil;
  mLower := LowerCase(AText);
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mLink := Default(TRationaleLink);
    mEnd := 0;
    // URL bis zum Leerraum, ohne Satzzeichen am Ende.
    if (StartsText('https://', Copy(mLower, mIndex, 8)) or StartsText('http://', Copy(mLower, mIndex, 7))) and
      ((mIndex = 1) or not JoinsLink(AText[mIndex - 1])) then
    begin
      mEnd := mIndex;
      while (mEnd <= Length(AText)) and (AText[mEnd] > ' ') do
        Inc(mEnd);
      while (mEnd > mIndex) and CharInSet(AText[mEnd - 1], ['.', ',', ';', ':', ')', '!', '?', '''', '"']) do
        Dec(mEnd);
      mLink.Kind := TRationaleLinkKind.Url;
      mLink.Key := Copy(AText, mIndex, mEnd - mIndex);
    end
    // ADR-0007, ADR 7, ADR7.
    else if (Copy(mLower, mIndex, 3) = 'adr') and ((mIndex = 1) or not JoinsLink(AText[mIndex - 1])) then
    begin
      mDigits := mIndex + 3;
      if (mDigits <= Length(AText)) and CharInSet(AText[mDigits], ['-', ' ']) then
        Inc(mDigits);
      mEnd := mDigits;
      while (mEnd <= Length(AText)) and IsDigit(AText[mEnd]) do
        Inc(mEnd);
      if (mEnd > mDigits) and ((mEnd > Length(AText)) or not JoinsLink(AText[mEnd])) then
      begin
        mLink.Kind := TRationaleLinkKind.Adr;
        mLink.Key := WithoutLeadingZeros(Copy(AText, mDigits, mEnd - mDigits));
      end
      else
        mEnd := 0;
    end
    // #312, nicht #13#10 und nicht mitten in einem Wort.
    else if (AText[mIndex] = '#') and ((mIndex = 1) or not JoinsLink(AText[mIndex - 1])) then
    begin
      mEnd := mIndex + 1;
      while (mEnd <= Length(AText)) and IsDigit(AText[mEnd]) do
        Inc(mEnd);
      if (mEnd > mIndex + 1) and ((mEnd > Length(AText)) or not JoinsLink(AText[mEnd])) then
      begin
        mLink.Kind := TRationaleLinkKind.Issue;
        mLink.Key := WithoutLeadingZeros(Copy(AText, mIndex + 1, mEnd - mIndex - 1));
      end
      else
        mEnd := 0;
    end;
    if mEnd > mIndex then
    begin
      mLink.Start := mIndex - 1;
      mLink.Length := mEnd - mIndex;
      Result := Result + [mLink];
      mIndex := mEnd;
    end
    else
      Inc(mIndex);
  end;
end;

class function TRationaleReferences.AdrFile(const AKey: string; const AFileNames: TArray<string>): string;
var
  mNames: TArray<string>;
  mFileName, mName, mDigits: string;
  mEnd: Integer;
begin
  Result := '';
  if AKey = '' then
    Exit;
  mNames := Copy(AFileNames);
  TArray.Sort<string>(mNames);
  for mFileName in mNames do
  begin
    mName := LowerCase(ExtractFileName(StringReplace(mFileName, '\', '/', [rfReplaceAll]).Replace('/', PathDelim)));
    if StartsStr('adr-', mName) or StartsStr('adr_', mName) then
      Delete(mName, 1, 4);
    mEnd := 1;
    while (mEnd <= Length(mName)) and IsDigit(mName[mEnd]) do
      Inc(mEnd);
    mDigits := Copy(mName, 1, mEnd - 1);
    if (mDigits <> '') and (WithoutLeadingZeros(mDigits) = AKey) and (mEnd <= Length(mName)) and
      CharInSet(mName[mEnd], ['-', '_', '.', ' ']) then
      Exit(mFileName);
  end;
end;

end.
