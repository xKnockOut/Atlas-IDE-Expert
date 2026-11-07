unit Atlas.Common.Lsp.HoverValues;

// Zusatzangaben für den Hover (#38): Zahlen in mehreren Schreibweisen, Werte von Konstanten
// (Zahlen, Mengen, Texte auch aus mehreren Teilen wie bei Resourcestrings), Basistyp von
// Mengentypen und Hinweise auf veraltete, plattformspezifische oder experimentelle Symbole.

interface

uses
  System.SysUtils;

type
  THoverValues = record
  public
    /// <summary>Dezimal, $Hex, %Binär und &amp;Oktal, mit optionalem Vorzeichen.</summary>
    class function TryParseNumber(const AText: string; out AValue: Int64): Boolean; static;
    /// <summary>"15 · $0F · %1111"</summary>
    class function FormatNumber(AValue: Int64): string; static;
    /// <summary>Wert einer Konstantendeklaration "Name = Ausdruck;": Zahl als FormatNumber, Menge als
    /// SetValue, Text als StringValue; '' bei anderen Ausdrücken.</summary>
    class function ConstantValue(const ADeclaration: string): string; static;
    /// <summary>Ausdruck hinter "=" bis zum letzten ";", ohne angehängte Hinweis-Direktiven; '' ohne "=".
    /// </summary>
    class function ConstantExpression(const ADeclaration: string): string; static;
    /// <summary>"[fsBold, fsItalic] · 2 Elemente"; '' wenn AExpression keine Mengenkonstante ist.</summary>
    class function SetValue(const AExpression: string): string; static;
    /// <summary>Text aus Literalen, #13#10, #$41 und "+" als 'Text' (Zeilenumbruch als ⏎); '' bei anderen
    /// Ausdrücken.</summary>
    class function StringValue(const AExpression: string): string; static;
    /// <summary>Basistyp eines Mengentyps "TFoo = set of TBar;" bzw. "set of (A, B)"; False sonst.</summary>
    class function SetBaseType(const ADeclaration: string; out ABaseType: string): Boolean; static;
    /// <summary>Anzahl möglicher Elemente für den Basistyp, soweit ohne Index bekannt: Aufzählung in
    /// Klammern, Teilbereich aus Zahlen oder Zeichen, Byte, Boolean, AnsiChar …; -1 sonst.</summary>
    class function BaseTypeCount(const ABaseType: string): Integer; static;
    /// <summary>Hinweis zu deprecated/platform/experimental in der Deklaration; '' ohne Direktive.</summary>
    class function Deprecation(const ADeclaration: string): string; static;
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  THoverValuesText = (Empty, Elements, Deprecated, PlatformSpecific, Experimental);

const
  cTexts: array[THoverValuesText] of TAtlasText = (
    (De: '[] · leer'; En: '[] · empty'),
    (De: ' · %s Elemente'; En: ' · %s elements'),
    (De: '**Veraltet**'; En: '**Deprecated**'),
    (De: '**Plattformspezifisch**'; En: '**Platform specific**'),
    (De: '**Experimentell**'; En: '**Experimental**'));

{$SCOPEDENUMS OFF}

function DigitValue(AChar: Char): Integer;
begin
  case AChar of
    '0'..'9': Result := Ord(AChar) - Ord('0');
    'a'..'f': Result := Ord(AChar) - Ord('a') + 10;
    'A'..'F': Result := Ord(AChar) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

class function THoverValues.TryParseNumber(const AText: string; out AValue: Int64): Boolean;
var
  mText: string;
  mBase, mIndex, mDigit: Integer;
  mNegative: Boolean;
  mValue: UInt64;
begin
  AValue := 0;
  mText := Trim(AText);
  mNegative := StartsStr('-', mText);
  if mNegative or StartsStr('+', mText) then
  begin
    mText := Trim(Copy(mText, 2, MaxInt));
  end;
  mBase := 10;
  if StartsStr('$', mText) then
  begin
    mBase := 16;
  end
  else if StartsStr('%', mText) then
  begin
    mBase := 2;
  end
  else if StartsStr('&', mText) then
  begin
    mBase := 8;
  end;
  if mBase <> 10 then
  begin
    mText := Copy(mText, 2, MaxInt);
  end;
  // Ziffertrenner ab Delphi 11: 1_000
  mText := StringReplace(mText, '_', '', [rfReplaceAll]);
  if mText = '' then
  begin
    Exit(False);
  end;
  mValue := 0;
  for mIndex := 1 to Length(mText) do
  begin
    mDigit := DigitValue(mText[mIndex]);
    if (mDigit < 0) or (mDigit >= mBase) then
    begin
      Exit(False);
    end;
    if mValue > (High(UInt64) - UInt64(mDigit)) div UInt64(mBase) then
    begin
      Exit(False);
    end;
    mValue := mValue * UInt64(mBase) + UInt64(mDigit);
  end;
  if mNegative then
  begin
    AValue := -Int64(mValue);
  end
  else
  begin
    AValue := Int64(mValue);
  end;
  Result := True;
end;

class function THoverValues.FormatNumber(AValue: Int64): string;
var
  mHex, mBinary: string;
  mValue: UInt64;
begin
  mValue := UInt64(AValue);
  // Ohne Vorzeichen auf Byte, Word, Cardinal bzw. Int64 auffüllen.
  if (AValue >= 0) and (AValue <= High(Byte)) then
  begin
    mHex := IntToHex(AValue, 2);
  end
  else if (AValue >= 0) and (AValue <= High(Word)) then
  begin
    mHex := IntToHex(AValue, 4);
  end
  else if (AValue >= 0) and (AValue <= High(Cardinal)) then
  begin
    mHex := IntToHex(AValue, 8);
  end
  else
  begin
    mHex := IntToHex(AValue, 16);
  end;
  mBinary := '';
  repeat
    mBinary := Char(Ord('0') + Integer(mValue and 1)) + mBinary;
    mValue := mValue shr 1;
  until mValue = 0;
  Result := IntToStr(AValue) + ' · $' + mHex + ' · %' + mBinary;
end;

const
  cHintWords: array[0..3] of string = ('deprecated', 'platform', 'experimental', 'library');

/// <summary>Teile von AText auf oberster Ebene (außerhalb von Strings und Klammern), getrennt durch ADelimiter.
/// </summary>
function SplitTop(const AText: string; ADelimiter: Char): TArray<string>;
var
  mIndex, mDepth, mStart: Integer;
  mInString: Boolean;
begin
  Result := nil;
  mDepth := 0;
  mInString := False;
  mStart := 1;
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mInString := not mInString;
    end
    else if mInString then
    begin
      Continue;
    end
    else if CharInSet(AText[mIndex], ['(', '[']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(AText[mIndex], [')', ']']) then
    begin
      Dec(mDepth);
    end
    else if (AText[mIndex] = ADelimiter) and (mDepth = 0) then
    begin
      Result := Result + [Trim(Copy(AText, mStart, mIndex - mStart))];
      mStart := mIndex + 1;
    end;
  end;
  Result := Result + [Trim(Copy(AText, mStart, MaxInt))];
end;

/// <summary>Position des ersten AChar auf oberster Ebene; 0 ohne.</summary>
function PosTop(AChar: Char; const AText: string): Integer;
var
  mIndex, mDepth: Integer;
  mInString: Boolean;
begin
  mDepth := 0;
  mInString := False;
  for mIndex := 1 to Length(AText) do
  begin
    if AText[mIndex] = '''' then
    begin
      mInString := not mInString;
    end
    else if mInString then
    begin
      Continue;
    end
    else if (AText[mIndex] = AChar) and (mDepth = 0) then
    begin
      Exit(mIndex);
    end
    else if CharInSet(AText[mIndex], ['(', '[']) then
    begin
      Inc(mDepth);
    end
    else if CharInSet(AText[mIndex], [')', ']']) then
    begin
      Dec(mDepth);
    end;
  end;
  Result := 0;
end;

/// <summary>ATail ohne angehängtes "deprecated 'Grund'"; sonst unverändert.</summary>
function WithoutDeprecatedMessage(const ATail: string): string;
var
  mIndex: Integer;
begin
  Result := ATail;
  if not EndsStr('''', ATail) then
  begin
    Exit;
  end;
  mIndex := Length(ATail) - 1;
  while (mIndex > 0) and (ATail[mIndex] <> '''') do
  begin
    Dec(mIndex);
  end;
  if (mIndex > 1) and EndsText('deprecated', TrimRight(Copy(ATail, 1, mIndex - 1))) then
  begin
    Result := TrimRight(Copy(ATail, 1, mIndex - 1));
  end;
end;

/// <summary>Entfernt ein angehängtes Hinweiswort (deprecated, platform …) von AText; False ohne.</summary>
function StripHintWord(var AText: string): Boolean;
var
  mTail, mWord: string;
begin
  mTail := WithoutDeprecatedMessage(AText);
  for mWord in cHintWords do
  begin
    if EndsText(' ' + mWord, mTail) then
    begin
      AText := TrimRight(Copy(mTail, 1, Length(mTail) - Length(mWord)));
      Exit(True);
    end;
  end;
  Result := False;
end;

class function THoverValues.ConstantExpression(const ADeclaration: string): string;
var
  mEquals: Integer;
  mParts: TArray<string>;
begin
  Result := '';
  mEquals := PosTop('=', ADeclaration);
  if mEquals = 0 then
  begin
    Exit;
  end;
  // Bis zum ersten ";" auf oberster Ebene; die Hinweise stehen davor oder dahinter.
  mParts := SplitTop(Copy(ADeclaration, mEquals + 1, MaxInt), ';');
  Result := mParts[0];
  // Angehängte Direktiven wie "deprecated 'Grund'" gehören nicht zum Wert.
  repeat
  until not StripHintWord(Result);
end;

class function THoverValues.ConstantValue(const ADeclaration: string): string;
var
  mExpression: string;
  mValue: Int64;
begin
  mExpression := ConstantExpression(ADeclaration);
  Result := '';
  if mExpression = '' then
  begin
    Exit;
  end;
  if TryParseNumber(mExpression, mValue) then
  begin
    Exit(FormatNumber(mValue));
  end;
  Result := SetValue(mExpression);
  if Result = '' then
  begin
    Result := StringValue(mExpression);
  end;
end;

/// <summary>Ordinalwert eines Zahlen- oder Zeichenliterals ('a', #65, 10); False sonst.</summary>
function TryOrdinal(const AText: string; out AValue: Int64): Boolean;
var
  mText: string;
begin
  mText := Trim(AText);
  if (Length(mText) = 3) and (mText[1] = '''') and (mText[3] = '''') then
  begin
    AValue := Ord(mText[2]);
    Exit(True);
  end;
  if StartsStr('#', mText) then
  begin
    Exit(THoverValues.TryParseNumber(Copy(mText, 2, MaxInt), AValue));
  end;
  Result := THoverValues.TryParseNumber(mText, AValue);
end;

class function THoverValues.SetValue(const AExpression: string): string;
var
  mText, mElement, mLow_, mHigh_: string;
  mElements: TArray<string>;
  mCount, mRange: Integer;
  mFirst, mLast: Int64;
  mCountable: Boolean;
begin
  Result := '';
  mText := Trim(AExpression);
  if (Length(mText) < 2) or (mText[1] <> '[') or (mText[Length(mText)] <> ']') or
    (PosTop(']', Copy(mText, 2, Length(mText) - 2)) > 0) then
  begin
    Exit;
  end;
  mText := Trim(Copy(mText, 2, Length(mText) - 2));
  if mText = '' then
  begin
    Exit(cTexts[THoverValuesText.Empty].Text);
  end;
  mElements := SplitTop(mText, ',');
  mCount := 0;
  mCountable := True;
  for mElement in mElements do
  begin
    mRange := Pos('..', mElement);
    if mRange = 0 then
    begin
      Inc(mCount);
      Continue;
    end;
    mLow_ := Trim(Copy(mElement, 1, mRange - 1));
    mHigh_ := Trim(Copy(mElement, mRange + 2, MaxInt));
    if TryOrdinal(mLow_, mFirst) and TryOrdinal(mHigh_, mLast) and (mLast >= mFirst) then
    begin
      Inc(mCount, Integer(mLast - mFirst + 1));
    end
    else
    begin
      mCountable := False;
    end;
  end;
  Result := '[' + string.Join(', ', mElements) + ']';
  if not mCountable then
  begin
    Exit;
  end;
  if mCount = 1 then
  begin
    Result := Result + ' · 1 Element';
  end
  else
  begin
    Result := Result + cTexts[THoverValuesText.Elements].Fmt([IntToStr(mCount)]);
  end;
end;

/// <summary>Liest das Literal ab AText[AIndex] = '''' in ABuilder; AIndex steht danach hinter dem Literal.
/// False ohne schließendes Hochkomma.</summary>
function ReadQuoted(const AText: string; var AIndex: Integer; ABuilder: TStringBuilder): Boolean;
var
  mClose: Integer;
begin
  mClose := AIndex + 1;
  while mClose <= Length(AText) do
  begin
    if AText[mClose] = '''' then
    begin
      if (mClose < Length(AText)) and (AText[mClose + 1] = '''') then
      begin
        ABuilder.Append('''');
        Inc(mClose, 2);
        Continue;
      end;
      AIndex := mClose + 1;
      Exit(True);
    end;
    ABuilder.Append(AText[mClose]);
    Inc(mClose);
  end;
  Result := False;
end;

/// <summary>Liest den Zeichencode ab AText[AIndex] = '#' in ABuilder; False bei ungültigem Code.</summary>
function ReadCharCode(const AText: string; var AIndex: Integer; ABuilder: TStringBuilder): Boolean;
var
  mClose: Integer;
  mCode: Int64;
begin
  mClose := AIndex + 1;
  while (mClose <= Length(AText)) and CharInSet(AText[mClose], ['$', '0'..'9', 'a'..'f', 'A'..'F']) do
  begin
    Inc(mClose);
  end;
  Result := THoverValues.TryParseNumber(Copy(AText, AIndex + 1, mClose - AIndex - 1), mCode) and (mCode >= 0) and
    (mCode <= $FFFF);
  if Result then
  begin
    ABuilder.Append(Char(mCode));
    AIndex := mClose;
  end;
end;

/// <summary>Eine Folge aus 'Literal' und #Code ohne Leerraum dazwischen in ABuilder; False bei anderem
/// Text.</summary>
function ReadStringPart(const APart: string; ABuilder: TStringBuilder): Boolean;
var
  mIndex: Integer;
begin
  Result := APart <> '';
  mIndex := 1;
  while Result and (mIndex <= Length(APart)) do
  begin
    case APart[mIndex] of
      '''': Result := ReadQuoted(APart, mIndex, ABuilder);
      '#': Result := ReadCharCode(APart, mIndex, ABuilder);
    else
      Result := False;
    end;
  end;
end;

class function THoverValues.StringValue(const AExpression: string): string;
var
  mPart, mText: string;
  mBuilder: TStringBuilder;
begin
  Result := '';
  mBuilder := TStringBuilder.Create;
  try
    for mPart in SplitTop(AExpression, '+') do
    begin
      if not ReadStringPart(mPart, mBuilder) then
      begin
        Exit;
      end;
    end;
    mText := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  mText := StringReplace(mText, #13#10, '⏎', [rfReplaceAll]);
  mText := StringReplace(mText, #10, '⏎', [rfReplaceAll]);
  mText := StringReplace(mText, #13, '⏎', [rfReplaceAll]);
  Result := '''' + mText + '''';
end;

class function THoverValues.SetBaseType(const ADeclaration: string; out ABaseType: string): Boolean;
var
  mExpression, mLower: string;
begin
  ABaseType := '';
  mExpression := ConstantExpression(ADeclaration);
  mLower := LowerCase(mExpression);
  Result := StartsStr('set of ', mLower) or StartsStr('packed set of ', mLower);
  if Result then
  begin
    ABaseType := Trim(Copy(mExpression, Pos(' of ', mLower) + 4, MaxInt));
  end;
end;

class function THoverValues.BaseTypeCount(const ABaseType: string): Integer;
var
  mText: string;
  mRange: Integer;
  mFirst, mLast: Int64;
begin
  Result := -1;
  mText := Trim(ABaseType);
  if StartsStr('(', mText) and EndsStr(')', mText) then
  begin
    Exit(Length(SplitTop(Copy(mText, 2, Length(mText) - 2), ',')));
  end;
  mRange := Pos('..', mText);
  if mRange > 0 then
  begin
    if TryOrdinal(Copy(mText, 1, mRange - 1), mFirst) and TryOrdinal(Copy(mText, mRange + 2, MaxInt), mLast) and
      (mLast >= mFirst) then
    begin
      Result := Integer(mLast - mFirst + 1);
    end;
    Exit;
  end;
  if SameText(mText, 'Boolean') or SameText(mText, 'ByteBool') then
  begin
    Result := 2;
  end
  else if SameText(mText, 'Byte') or SameText(mText, 'ShortInt') or SameText(mText, 'AnsiChar') or
    SameText(mText, 'Char') or SameText(mText, 'UInt8') or SameText(mText, 'Int8') then
  begin
    // set of Char gilt als set of AnsiChar (Warnung W1050).
    Result := 256;
  end;
end;

/// <summary>Beginnt bei AIndex ein Wort (nicht mitten in einem Namen oder nach ".")?</summary>
function IsWordStart(const AText: string; AIndex: Integer): Boolean;
begin
  Result := CharInSet(AText[AIndex], ['a'..'z', 'A'..'Z', '_']);
  if Result and (AIndex > 1) then
  begin
    Result := not CharInSet(AText[AIndex - 1], ['a'..'z', 'A'..'Z', '0'..'9', '_', '.']);
  end;
end;

/// <summary>Erste Stelle ab AIndex, die kein Leerzeichen ist.</summary>
function SkipSpaces(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= Length(AText)) and (AText[Result] = ' ') do
  begin
    Inc(Result);
  end;
end;

/// <summary>"**Veraltet**: Grund" für deprecated 'Grund'; AIndex steht hinter dem Wort.</summary>
function DeprecatedText(const ADeclaration: string; AIndex: Integer): string;
var
  mStart, mClose: Integer;
begin
  Result := cTexts[THoverValuesText.Deprecated].Text;
  mStart := SkipSpaces(ADeclaration, AIndex);
  if (mStart > Length(ADeclaration)) or (ADeclaration[mStart] <> '''') then
  begin
    Exit;
  end;
  mClose := PosEx('''', ADeclaration, mStart + 1);
  if mClose > mStart + 1 then
  begin
    Result := Result + ': ' + Copy(ADeclaration, mStart + 1, mClose - mStart - 1);
  end;
end;

/// <summary>Hinweis zum Direktivenwort AWord (klein), das vor AIndex endet; '' bei anderen Wörtern.</summary>
function DirectiveHint(const ADeclaration, AWord: string; AIndex: Integer): string;
begin
  Result := '';
  if AWord = 'deprecated' then
  begin
    Result := DeprecatedText(ADeclaration, AIndex);
  end
  else if AWord = 'platform' then
  begin
    Result := cTexts[THoverValuesText.PlatformSpecific].Text;
  end
  else if AWord = 'experimental' then
  begin
    Result := cTexts[THoverValuesText.Experimental].Text;
  end;
end;

class function THoverValues.Deprecation(const ADeclaration: string): string;
var
  mIndex, mStart, mClose: Integer;
  mInString: Boolean;
begin
  Result := '';
  mInString := False;
  mIndex := 1;
  while (Result = '') and (mIndex <= Length(ADeclaration)) do
  begin
    if ADeclaration[mIndex] = '''' then
    begin
      mInString := not mInString;
    end;
    if mInString or not IsWordStart(ADeclaration, mIndex) then
    begin
      Inc(mIndex);
      Continue;
    end;
    mStart := mIndex;
    while (mIndex <= Length(ADeclaration)) and CharInSet(ADeclaration[mIndex], ['a'..'z', 'A'..'Z', '0'..'9', '_']) do
    begin
      Inc(mIndex);
    end;
    // Direktiven stehen vor ";", einem String oder am Ende; Namen wie "Platform: string" nicht.
    mClose := SkipSpaces(ADeclaration, mIndex);
    if (mClose > Length(ADeclaration)) or CharInSet(ADeclaration[mClose], [';', '''']) then
    begin
      Result := DirectiveHint(ADeclaration, LowerCase(Copy(ADeclaration, mStart, mIndex - mStart)), mIndex);
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.HoverValues', cTexts);

end.
