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

/// <summary>Zeichen, neben dem kein Verweis beginnt bzw. endet: Bezeichner, &amp;, # und $ (z. B. &#312;, $1F).
/// </summary>
function JoinsLink(ACh: Char): Boolean;
begin
  Result := TTextChars.IsIdentChar(ACh) or CharInSet(ACh, ['&', '#', '$']);
end;

function WithoutLeadingZeros(const ADigits: string): string;
begin
  Result := ADigits;
  while (Length(Result) > 1) and (Result[1] = '0') do
  begin
    Delete(Result, 1, 1);
  end;
end;

/// <summary>Ein Verweis darf bei AIndex beginnen: am Anfang oder nach einem Zeichen, das nicht verbindet.</summary>
function MayStartAt(const AText: string; AIndex: Integer): Boolean;
begin
  Result := (AIndex = 1) or not JoinsLink(AText[AIndex - 1]);
end;

/// <summary>Ein Verweis darf vor AEnd enden: am Ende oder vor einem Zeichen, das nicht verbindet.</summary>
function MayEndBefore(const AText: string; AEnd: Integer): Boolean;
begin
  Result := (AEnd > Length(AText)) or not JoinsLink(AText[AEnd]);
end;

/// <summary>Erste Stelle ab AStart, die keine Ziffer ist.</summary>
function DigitsEnd(const AText: string; AStart: Integer): Integer;
begin
  Result := AStart;
  while (Result <= Length(AText)) and IsDigit(AText[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>URL ab AIndex bis zum Leerraum, ohne Satzzeichen am Ende; Ende hinter der URL, 0 ohne.</summary>
function ReadUrl(const AText, ALower: string; AIndex: Integer; var ALink: TRationaleLink): Integer;
begin
  Result := 0;
  if (StartsText('https://', Copy(ALower, AIndex, 8)) or StartsText('http://', Copy(ALower, AIndex, 7))) and
    MayStartAt(AText, AIndex) then
  begin
    Result := AIndex;
    while (Result <= Length(AText)) and (AText[Result] > ' ') do
    begin
      Inc(Result);
    end;
    while (Result > AIndex) and CharInSet(AText[Result - 1], ['.', ',', ';', ':', ')', '!', '?', '''', '"']) do
    begin
      Dec(Result);
    end;
    ALink.Kind := TRationaleLinkKind.Url;
    ALink.Key := Copy(AText, AIndex, Result - AIndex);
  end;
end;

/// <summary>ADR-0007, ADR 7 oder ADR7 ab AIndex; Ende hinter der Nummer, 0 ohne.</summary>
function ReadAdr(const AText, ALower: string; AIndex: Integer; var ALink: TRationaleLink): Integer;
var
  mDigits: Integer;
begin
  Result := 0;
  if (Copy(ALower, AIndex, 3) = 'adr') and MayStartAt(AText, AIndex) then
  begin
    mDigits := AIndex + 3;
    if (mDigits <= Length(AText)) and CharInSet(AText[mDigits], ['-', ' ']) then
    begin
      Inc(mDigits);
    end;
    Result := DigitsEnd(AText, mDigits);
    if (Result > mDigits) and MayEndBefore(AText, Result) then
    begin
      ALink.Kind := TRationaleLinkKind.Adr;
      ALink.Key := WithoutLeadingZeros(Copy(AText, mDigits, Result - mDigits));
    end
    else
    begin
      Result := 0;
    end;
  end;
end;

/// <summary>#312 ab AIndex, nicht #13#10 und nicht mitten in einem Wort; Ende hinter der Nummer, 0 ohne.</summary>
function ReadIssue(const AText: string; AIndex: Integer; var ALink: TRationaleLink): Integer;
begin
  Result := 0;
  if (AText[AIndex] = '#') and MayStartAt(AText, AIndex) then
  begin
    Result := DigitsEnd(AText, AIndex + 1);
    if (Result > AIndex + 1) and MayEndBefore(AText, Result) then
    begin
      ALink.Kind := TRationaleLinkKind.Issue;
      ALink.Key := WithoutLeadingZeros(Copy(AText, AIndex + 1, Result - AIndex - 1));
    end
    else
    begin
      Result := 0;
    end;
  end;
end;

/// <summary>Verweis ab AIndex (URL, ADR oder Issue); Ende hinter dem Verweis, 0 ohne.</summary>
function ReadLink(const AText, ALower: string; AIndex: Integer; out ALink: TRationaleLink): Integer;
begin
  ALink := Default(TRationaleLink);
  Result := ReadUrl(AText, ALower, AIndex, ALink);
  if Result = 0 then
  begin
    Result := ReadAdr(AText, ALower, AIndex, ALink);
  end;
  if Result = 0 then
  begin
    Result := ReadIssue(AText, AIndex, ALink);
  end;
end;

class function TRationaleReferences.Find(const AText: string): TArray<TRationaleLink>;
var
  mIndex, mEnd: Integer;
  mLink: TRationaleLink;
  mLower: string;
begin
  Result := nil;
  mLower := LowerCase(AText);
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    mEnd := ReadLink(AText, mLower, mIndex, mLink);
    if mEnd > mIndex then
    begin
      mLink.Start := mIndex - 1;
      mLink.Length := mEnd - mIndex;
      Result := Result + [mLink];
      mIndex := mEnd;
    end
    else
    begin
      Inc(mIndex);
    end;
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
  begin
    Exit;
  end;
  mNames := Copy(AFileNames);
  TArray.Sort<string>(mNames);
  for mFileName in mNames do
  begin
    mName := LowerCase(ExtractFileName(StringReplace(mFileName, '\', '/', [rfReplaceAll]).Replace('/', PathDelim)));
    if StartsStr('adr-', mName) or StartsStr('adr_', mName) then
    begin
      Delete(mName, 1, 4);
    end;
    mEnd := 1;
    while (mEnd <= Length(mName)) and IsDigit(mName[mEnd]) do
    begin
      Inc(mEnd);
    end;
    mDigits := Copy(mName, 1, mEnd - 1);
    if (mDigits <> '') and (WithoutLeadingZeros(mDigits) = AKey) and (mEnd <= Length(mName)) and
      CharInSet(mName[mEnd], ['-', '_', '.', ' ']) then
    begin
      Exit(mFileName);
    end;
  end;
end;

end.
