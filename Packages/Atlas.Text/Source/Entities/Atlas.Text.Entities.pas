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
  System.StrUtils;

{ TTextEntities }

class function TTextEntities.CodePointText(ACode: Integer): string;
begin
  if (ACode <= 0) or (ACode > $10FFFF) or ((ACode >= $D800) and (ACode <= $DFFF)) then
  begin
    Exit('');
  end;
  if ACode <= $FFFF then
  begin
    Exit(Char(ACode));
  end;
  Dec(ACode, $10000);
  Result := Char($D800 + (ACode shr 10)) + Char($DC00 + (ACode and $3FF));
end;

// Zeichen zu einer Zahlenangabe ("#65", "#x41"); '' ohne gültige Zahl.
function NumericEntity(const AName: string): string;
var
  mCode: Integer;
  mDigits: string;
begin
  Result := '';
  if (Length(AName) > 2) and ((AName[2] = 'x') or (AName[2] = 'X')) then
  begin
    mDigits := '$' + Copy(AName, 3, MaxInt);
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
begin
  if (Length(AName) > 1) and (AName[1] = '#') then
  begin
    Exit(NumericEntity(AName));
  end;
  case IndexStr(AName, ['lt', 'gt', 'amp', 'quot', 'apos']) of
    0:
      Result := '<';
    1:
      Result := '>';
    2:
      Result := '&';
    3:
      Result := '"';
    4:
      Result := '''';
  else
    Result := '';
  end;
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
