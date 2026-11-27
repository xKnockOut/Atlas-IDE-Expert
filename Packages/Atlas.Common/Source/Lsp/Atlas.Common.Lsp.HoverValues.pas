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
    /// <summary>Deklaration nur für AName aus einer Namensliste mit Typ: "A, B: Integer;" ergibt für B
    /// "B: Integer;", "const C, D: string" für D "const D: string". ADeclaration ist genau der Text der
    /// Deklaration (Variablen, Felder, Parameter). False bei anderen Deklarationen (Routinen, Typen,
    /// Konstanten, Properties) und wenn AName nicht in der Liste steht.</summary>
    class function NameDeclaration(const ADeclaration, AName: string; out AResult: string): Boolean; static;
    /// <summary>Deklaration ab ALines[ALine], Zeichen ACharacter (ab 0), deren Klammern in der ersten Zeile offen
    /// bleiben (Aufzählung, Parameterliste oder Vorfahren über mehrere Zeilen), in einer Zeile ohne Kommentare:
    /// "TFarbe = (Rot, Gruen, Blau);". Sehr lange Listen enden nach dem letzten passenden Element mit "…".
    /// False, wenn die erste Zeile die Klammern schließt oder sie nicht bis zum Ende geschlossen werden.</summary>
    class function SpannedDeclaration(const ALines: TArray<string>; ALine, ACharacter: Integer;
      out AResult: string): Boolean; static;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.TokenCursor,
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

{ THoverValues }

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
  else if MatchText(mText, ['Byte', 'ShortInt', 'AnsiChar', 'Char', 'UInt8', 'Int8']) then
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

/// <summary>Steht an AIndex ein Wort vor den Namen (const, var, out, class var …), dem ein weiteres Wort folgt?
/// "out, B: Integer" beginnt dagegen mit dem Namen out.</summary>
function IsModifierAt(const ACursor: TTokenCursor; AIndex: Integer): Boolean;
begin
  Result := MatchText(ACursor.At(AIndex).Text, ['class', 'var', 'const', 'threadvar', 'out', 'constref']) and
    (ACursor.At(ACursor.NextCode(AIndex + 1)).Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]);
end;

/// <summary>Liest die Namensliste "A, B, C:" ab AIndex; AColon ist danach das Token ":". False, wenn dort keine
/// Namensliste mit Doppelpunkt steht oder AName nicht darin vorkommt.</summary>
function ReadNameList(const ACursor: TTokenCursor; AIndex: Integer; const AName: string;
  out AColon: Integer): Boolean;
var
  mFound: Boolean;
begin
  AColon := -1;
  mFound := False;
  while ACursor.At(AIndex).Kind = TPascalTokenKind.Identifier do
  begin
    mFound := mFound or SameText(TPascalLexer.PlainName(ACursor.At(AIndex).Text), TPascalLexer.PlainName(AName));
    AIndex := ACursor.NextCode(AIndex + 1);
    if ACursor.Is_(AIndex, ':') then
    begin
      AColon := AIndex;
      Break;
    end;
    if not ACursor.Is_(AIndex, ',') then
    begin
      Break;
    end;
    AIndex := ACursor.NextCode(AIndex + 1);
  end;
  Result := mFound and (AColon >= 0);
end;

class function THoverValues.NameDeclaration(const ADeclaration, AName: string; out AResult: string): Boolean;
var
  mCursor: TTokenCursor;
  mFirst, mColon: Integer;
begin
  AResult := '';
  mCursor := TTokenCursor.Create(TPascalLexer.Tokenize(ADeclaration));
  mFirst := mCursor.NextCode(0);
  while IsModifierAt(mCursor, mFirst) do
  begin
    mFirst := mCursor.NextCode(mFirst + 1);
  end;
  Result := ReadNameList(mCursor, mFirst, AName, mColon);
  if Result then
  begin
    // Wörter davor (const, var) bleiben, die Liste wird zum einen Namen.
    AResult := Copy(ADeclaration, 1, mCursor.At(mFirst).Offset) + AName +
      Copy(ADeclaration, mCursor.At(mColon).Offset + 1, MaxInt);
  end;
end;

const
  /// <summary>So viele Zeilen liest SpannedDeclaration höchstens.</summary>
  cSpannedMaxLines = 200;
  /// <summary>Ab dieser Länge kürzt SpannedDeclaration die Liste mit "…".</summary>
  cSpannedMaxLength = 400;

type
  /// <summary>Zusammengezogene Deklaration aus SpannedDeclaration: Text und Stellen zum Kürzen.</summary>
  TSpannedText = record
    Text: string;
    /// <summary>Länge von Text hinter jedem Komma der äußersten Klammer.</summary>
    Commas: TArray<Integer>;
    /// <summary>Länge von Text vor der schließenden äußersten Klammer; -1 ohne.</summary>
    Closer: Integer;
    procedure Append(const AToken: TPascalToken; AGap: Boolean);
    function Shortened(AMaxLength: Integer): string;
  end;

procedure TSpannedText.Append(const AToken: TPascalToken; AGap: Boolean);
var
  mLast: Char;
begin
  mLast := TTextChars.CharAt(Text, Length(Text));
  if AGap and (Text <> '') and (mLast <> '(') and (mLast <> '[') and
    not MatchText(AToken.Text, [')', ']', ',', ';', '.)']) then
  begin
    Text := Text + ' ';
  end;
  Text := Text + AToken.Text;
end;

function TSpannedText.Shortened(AMaxLength: Integer): string;
var
  mIndex, mCut: Integer;
begin
  Result := Text;
  if (Length(Text) <= AMaxLength) or (Closer < 0) then
  begin
    Exit;
  end;
  mCut := -1;
  for mIndex := 0 to High(Commas) do
  begin
    if Commas[mIndex] + Length(Text) - Closer + 2 <= AMaxLength then
    begin
      mCut := Commas[mIndex];
    end;
  end;
  if mCut > 0 then
  begin
    Result := Copy(Text, 1, mCut) + ' …' + Copy(Text, Closer + 1, MaxInt);
  end;
end;

/// <summary>Zeilen ab ALine (die erste ab ACharacter), höchstens cSpannedMaxLines, mit #10 verbunden.</summary>
function SpannedSource(const ALines: TArray<string>; ALine, ACharacter: Integer): string;
var
  mLine: Integer;
  mBuilder: TStringBuilder;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.Append(Copy(ALines[ALine], ACharacter + 1, MaxInt));
    for mLine := ALine + 1 to Min(High(ALines), ALine + cSpannedMaxLines) do
    begin
      mBuilder.Append(#10).Append(ALines[mLine]);
    end;
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

/// <summary>Neue Klammertiefe nach AToken; merkt sich Kommas und schließende Klammer der äußersten Ebene.</summary>
function SpannedDepth(const AToken: TPascalToken; ADepth: Integer; var AText: TSpannedText): Integer;
begin
  Result := ADepth;
  if AToken.IsSymbol('(') or AToken.IsSymbol('[') then
  begin
    Inc(Result);
  end
  else if AToken.IsSymbol(')') or AToken.IsSymbol(']') then
  begin
    Dec(Result);
    if Result = 0 then
    begin
      AText.Closer := Length(AText.Text) - Length(AToken.Text);
    end;
  end
  else if (ADepth = 1) and AToken.IsSymbol(',') then
  begin
    AText.Commas := AText.Commas + [Length(AText.Text)];
  end;
end;

class function THoverValues.SpannedDeclaration(const ALines: TArray<string>; ALine, ACharacter: Integer;
  out AResult: string): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mText: TSpannedText;
  mIndex, mDepth, mEnd, mClosedLine: Integer;
begin
  AResult := '';
  Result := False;
  if (ALine < 0) or (ALine > High(ALines)) then
  begin
    Exit;
  end;
  mTokens := TPascalLexer.Tokenize(SpannedSource(ALines, ALine, ACharacter));
  mText := Default(TSpannedText);
  mText.Closer := -1;
  mDepth := 0;
  mEnd := 0;
  mClosedLine := -1;
  for mIndex := 0 to High(mTokens) do
  begin
    if (mClosedLine >= 0) and (mTokens[mIndex].StartPos.Line > mClosedLine) then
    begin
      Break;
    end;
    if mTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive] then
    begin
      Continue;
    end;
    if (mDepth = 0) and (mTokens[mIndex].StartPos.Line > 0) and (mClosedLine < 0) then
    begin
      // Die erste Zeile schließt ihre Klammern selbst: nichts zusammenzuziehen.
      Exit;
    end;
    mText.Append(mTokens[mIndex], mTokens[mIndex].Offset > mEnd);
    mEnd := mTokens[mIndex].Offset + Length(mTokens[mIndex].Text);
    mDepth := SpannedDepth(mTokens[mIndex], mDepth, mText);
    if (mDepth = 0) and (mClosedLine < 0) and (mTokens[mIndex].StartPos.Line > 0) then
    begin
      mClosedLine := mTokens[mIndex].StartPos.Line;
    end;
  end;
  Result := mClosedLine > 0;
  if Result then
  begin
    AResult := mText.Shortened(cSpannedMaxLength);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.HoverValues', cTexts);

end.
