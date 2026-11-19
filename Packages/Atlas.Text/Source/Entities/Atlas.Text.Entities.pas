unit Atlas.Text.Entities;

// XML-Entities entschlüsseln (gemeinsam für Server und Plugin):
// &lt; &gt; &amp; &quot; &apos; sowie numerische &#NN; und &#xNN;
// (auch über U+FFFF als Surrogatpaar). Unbekanntes bleibt stehen.

interface

type
  TTextEntities = class
  public
    class function Decode(const AText: string): string; static;
    /// <summary>Zeichen zum Codepunkt; '' für 0, Surrogate und Werte über U+10FFFF.</summary>
    class function CodePointText(ACode: Integer): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Encoding;

const
  // Benannte Entities und ihre Zeichen, gleich geordnet.
  cEntityNames: array[0..4] of string = ('lt', 'gt', 'amp', 'quot', 'apos');
  cEntityChars: array[0..4] of string = ('<', '>', '&', '"', '''');
  /// <summary>Vorsilbe einer hexadezimalen Zahlenangabe ("#x41").</summary>
  cHexPrefix = '#x';

{ TTextEntities }

class function TTextEntities.CodePointText(ACode: Integer): string;
begin
  if (ACode <= 0) or (ACode > TTextEncodingProbe.cMaxCodePoint) or
    ((ACode >= TTextEncodingProbe.cHighSurrogateFirst) and (ACode <= TTextEncodingProbe.cSurrogateLast)) then
  begin
    Exit('');
  end;
  if ACode < TTextEncodingProbe.cFirstSupplementary then
  begin
    Exit(Char(ACode));
  end;
  Dec(ACode, TTextEncodingProbe.cFirstSupplementary);
  Result := Char(TTextEncodingProbe.cHighSurrogateFirst + (ACode shr TTextEncodingProbe.cSurrogateBits)) +
    Char(TTextEncodingProbe.cLowSurrogateFirst + (ACode and TTextEncodingProbe.cSurrogateMask));
end;

// Zeichen zu einer Zahlenangabe ("#65", "#x41"); '' ohne gültige Zahl.
function NumericEntity(const AName: string): string;
var
  mCode: Integer;
  mDigits: string;
begin
  Result := '';
  if (Length(AName) > Length(cHexPrefix)) and AName.StartsWith(cHexPrefix, True) then
  begin
    mDigits := '$' + Copy(AName, Length(cHexPrefix) + 1, MaxInt);
  end
  else
  begin
    mDigits := Copy(AName, 2, MaxInt);
  end;
  if TryStrToInt(mDigits, mCode) then
  begin
    Result := TTextEntities.CodePointText(mCode);
  end;
end;

// Text zur Entity AName (ohne & und ;); '' bei unbekannten Namen.
function EntityText(const AName: string): string;
var
  mIndex: Integer;
begin
  if (Length(AName) > 1) and (AName[1] = '#') then
  begin
    Exit(NumericEntity(AName));
  end;
  for mIndex := Low(cEntityNames) to High(cEntityNames) do
  begin
    if cEntityNames[mIndex] = AName then
    begin
      Exit(cEntityChars[mIndex]);
    end;
  end;
  Result := '';
end;

// Ersetzung der Entity bei AIndex (AText[AIndex] = '&'); ANext ist dann die Stelle dahinter.
function EntityAt(const AText: string; AIndex: Integer; out ANext: Integer): string;
var
  mClose: Integer;
begin
  Result := '';
  ANext := AIndex + 1;
  mClose := Pos(';', AText, AIndex + 1);
  if (mClose > 0) and (mClose - AIndex <= 10) then
  begin
    Result := EntityText(Copy(AText, AIndex + 1, mClose - AIndex - 1));
    ANext := mClose + 1;
  end;
end;

class function TTextEntities.Decode(const AText: string): string;
var
  mIndex, mNext: Integer;
  mReplacement: string;
  mBuilder: TStringBuilder;
begin
  if Pos('&', AText) = 0 then
  begin
    Exit(AText);
  end;
  mBuilder := TStringBuilder.Create(Length(AText));
  try
    mIndex := 1;
    while mIndex <= Length(AText) do
    begin
      mReplacement := '';
      if AText[mIndex] = '&' then
      begin
        mReplacement := EntityAt(AText, mIndex, mNext);
      end;
      if mReplacement <> '' then
      begin
        mBuilder.Append(mReplacement);
        mIndex := mNext;
      end
      else
      begin
        mBuilder.Append(AText[mIndex]);
        Inc(mIndex);
      end;
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

end.
