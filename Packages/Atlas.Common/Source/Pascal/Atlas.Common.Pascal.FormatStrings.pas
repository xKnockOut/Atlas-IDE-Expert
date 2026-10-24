unit Atlas.Common.Pascal.FormatStrings;

// Zerlegung von Formatstrings für System.SysUtils.Format (#56): Platzhalter
// "%" [Index ":"] ["-"] [Breite] ["." Genauigkeit] Typ mit Breite und
// Genauigkeit auch als "*" (aus der Argumentliste) und "%%" für ein
// Prozentzeichen. Wie FormatBuf der RTL zählt ein Index die folgenden
// Platzhalter ab dieser Stelle weiter. Typbuchstaben: d u e f g n m p s x,
// ohne Groß-/Kleinschreibung. Dazu der Wert eines Pascal-Stringliterals aus
// Teilen in Hochkommas und Zeichencodes (#13, #$0A). Gemeinsamer Baustein von
// format-args und format-without-settings.

interface

type
  /// <summary>Art eines Platzhalters: gültig, unbekannter Typbuchstabe (%q), unvollständig am Ende ('%5'), Index
  /// ohne Typ (%0: gefolgt von etwas anderem als einem Buchstaben).</summary>
  TFormatSpecKind = (Valid, UnknownType, Incomplete, IndexWithoutType);

  /// <summary>Ein Platzhalter. Argumente zählen ab 0; -1 = keins. Bei Index "*" ist die Zuordnung ab dort
  /// unbekannt (Dynamic).</summary>
  TFormatSpec = record
    Text: string;
    /// <summary>Position des "%" ab 1.</summary>
    Offset: Integer;
    Kind: TFormatSpecKind;
    /// <summary>Typbuchstabe klein; #0 bei ungültigen Platzhaltern.</summary>
    TypeChar: Char;
    Argument: Integer;
    WidthArgument: Integer;
    PrecisionArgument: Integer;
    ExplicitIndex: Boolean;
    Dynamic: Boolean;
  end;

  /// <summary>Art eines Arguments im Sinn von TVarRec (#56, #451).</summary>
  {$SCOPEDENUMS ON}
  TFormatArgumentClass = (Unknown, Integer_, Float, Text, Character, Bool, Variant_, Enum, Object_, Pointer_);
  {$SCOPEDENUMS OFF}

  TFormatString = record
    Specs: TArray<TFormatSpec>;
    /// <summary>Kein ungültiger Platzhalter?</summary>
    function Valid: Boolean;
    /// <summary>Höchstes verwendetes Argument + 1; -1, wenn die Zuordnung unbekannt ist (Index "*").</summary>
    function ArgumentCount: Integer;
    /// <summary>Hat ein Platzhalter einen Index (%0:s)?</summary>
    function HasExplicitIndex: Boolean;
    class function Parse(const AFormat: string): TFormatString; static;
    /// <summary>Hängt der Typbuchstabe vom Gebietsschema ab (e f g n m)?</summary>
    class function IsLocaleType(AType: Char): Boolean; static;
    /// <summary>Enthält AFormat einen gültigen Platzhalter, der vom Gebietsschema abhängt?</summary>
    class function HasLocaleSpecifier(const AFormat: string): Boolean; static;
    /// <summary>Wert eines Pascal-Stringliterals aus Teilen 'abc' und Zeichencodes #13 bzw. #$0A, auch
    /// gemischt ('a'#13#10'b'). False für anderen Text, mehrzeilige Literale (''') und Codes über $FFFF.
    /// </summary>
    class function LiteralValue(const AText: string; out AValue: string): Boolean; static;
    /// <summary>Wie LiteralValue; AOffsets nennt je Zeichen des Werts seine Stelle in AText (ab 0): das
    /// Zeichen selbst, bei '' das erste Hochkomma, bei #13 das #.</summary>
    class function LiteralOffsets(const AText: string; out AValue: string; out AOffsets: TArray<Integer>): Boolean;
      static;
    /// <summary>Wert eines Ausdrucks aus Literalen, die mit + verbunden sind ('a' + #13 + 'b').</summary>
    class function ExpressionValue(const AText: string; out AValue: string): Boolean; static;
    /// <summary>Wert einer Konstanten aus ihrer Signatur ("cFormat = 'Text'", "cFormat: string = 'Text'");
    /// False bei gekürzter Signatur oder anderem Wert.</summary>
    class function ConstantValue(const ASignature: string; out AValue: string): Boolean; static;
    /// <summary>Art eines einzelnen Literals (String, Zeichen, Zahl, auch negativ); Unknown für anderes.
    /// ATypeName: "ein String" bzw. "eine Zahl".</summary>
    class function LiteralClass(const AText: string; out ATypeName: string): TFormatArgumentClass; static;
    /// <summary>Passt die Art AClass zum Typbuchstaben AType ('*' für Breite bzw. Genauigkeit)? Unbekannte
    /// Arten und Variants passen immer.</summary>
    class function Fits(AType: Char; AClass: TFormatArgumentClass): Boolean; static;
  end;

implementation

uses
  System.SysUtils;

const
  cTypeChars = ['d', 'u', 'e', 'f', 'g', 'n', 'm', 'p', 's', 'x'];

function LowerChar(AChar: Char): Char;
begin
  Result := AChar;
  if CharInSet(AChar, ['A'..'Z']) then
    Result := Char(Ord(AChar) + Ord('a') - Ord('A'));
end;

{ TFormatString }

function TFormatString.Valid: Boolean;
var
  mSpec: TFormatSpec;
begin
  for mSpec in Specs do
    if mSpec.Kind <> TFormatSpecKind.Valid then
      Exit(False);
  Result := True;
end;

function TFormatString.ArgumentCount: Integer;
var
  mSpec: TFormatSpec;
begin
  Result := 0;
  for mSpec in Specs do
  begin
    if mSpec.Dynamic then
      Exit(-1);
    if mSpec.WidthArgument >= Result then
      Result := mSpec.WidthArgument + 1;
    if mSpec.PrecisionArgument >= Result then
      Result := mSpec.PrecisionArgument + 1;
    if mSpec.Argument >= Result then
      Result := mSpec.Argument + 1;
  end;
end;

function TFormatString.HasExplicitIndex: Boolean;
var
  mSpec: TFormatSpec;
begin
  for mSpec in Specs do
    if mSpec.ExplicitIndex then
      Exit(True);
  Result := False;
end;

class function TFormatString.IsLocaleType(AType: Char): Boolean;
begin
  Result := CharInSet(AType, ['e', 'f', 'g', 'n', 'm']);
end;

class function TFormatString.HasLocaleSpecifier(const AFormat: string): Boolean;
var
  mSpec: TFormatSpec;
begin
  for mSpec in Parse(AFormat).Specs do
    if (mSpec.Kind = TFormatSpecKind.Valid) and IsLocaleType(mSpec.TypeChar) then
      Exit(True);
  Result := False;
end;

class function TFormatString.Parse(const AFormat: string): TFormatString;
var
  mPos, mStart, mNext: Integer;
  mDynamic: Boolean;
  mSpec: TFormatSpec;

  function AtEnd: Boolean;
  begin
    Result := mPos > Length(AFormat);
  end;

  /// <summary>Ziffern oder "*" ab mPos; AStar: "*" gelesen.</summary>
  function ReadNumber(out AValue: Integer; out AStar: Boolean): Boolean;
  var
    mFrom: Integer;
  begin
    AValue := 0;
    AStar := False;
    if not AtEnd and (AFormat[mPos] = '*') then
    begin
      AStar := True;
      Inc(mPos);
      Exit(True);
    end;
    mFrom := mPos;
    while not AtEnd and CharInSet(AFormat[mPos], ['0'..'9']) do
    begin
      if AValue < 100000 then
        AValue := AValue * 10 + Ord(AFormat[mPos]) - Ord('0');
      Inc(mPos);
    end;
    Result := mPos > mFrom;
  end;

  /// <summary>Breite bzw. Genauigkeit aus der Argumentliste: verbraucht ein Argument.</summary>
  function TakeArgument: Integer;
  begin
    Result := mNext;
    Inc(mNext);
  end;

var
  mValue: Integer;
  mStar, mHasNumber: Boolean;
begin
  Result.Specs := nil;
  mPos := 1;
  mNext := 0;
  mDynamic := False;
  while mPos <= Length(AFormat) do
  begin
    if AFormat[mPos] <> '%' then
    begin
      Inc(mPos);
      Continue;
    end;
    mStart := mPos;
    Inc(mPos);
    if not AtEnd and (AFormat[mPos] = '%') then
    begin
      Inc(mPos);
      Continue;
    end;
    mSpec := Default(TFormatSpec);
    mSpec.Offset := mStart;
    mSpec.Argument := -1;
    mSpec.WidthArgument := -1;
    mSpec.PrecisionArgument := -1;
    // Index oder Breite.
    mHasNumber := ReadNumber(mValue, mStar);
    if mHasNumber and not AtEnd and (AFormat[mPos] = ':') then
    begin
      Inc(mPos);
      mSpec.ExplicitIndex := True;
      if mStar then
        mDynamic := True
      else
        mNext := mValue;
      if not AtEnd and (AFormat[mPos] = '-') then
        Inc(mPos);
      mHasNumber := ReadNumber(mValue, mStar);
    end
    else if not mHasNumber and not AtEnd and (AFormat[mPos] = '-') then
    begin
      Inc(mPos);
      mHasNumber := ReadNumber(mValue, mStar);
    end;
    if mHasNumber and mStar then
      mSpec.WidthArgument := TakeArgument;
    if not AtEnd and (AFormat[mPos] = '.') then
    begin
      Inc(mPos);
      if ReadNumber(mValue, mStar) and mStar then
        mSpec.PrecisionArgument := TakeArgument;
    end;
    mSpec.Dynamic := mDynamic;
    if AtEnd then
      mSpec.Kind := TFormatSpecKind.Incomplete
    else if CharInSet(LowerChar(AFormat[mPos]), cTypeChars) then
    begin
      mSpec.TypeChar := LowerChar(AFormat[mPos]);
      mSpec.Argument := TakeArgument;
      Inc(mPos);
    end
    else
    begin
      if mSpec.ExplicitIndex and not CharInSet(AFormat[mPos], ['a'..'z', 'A'..'Z']) then
        mSpec.Kind := TFormatSpecKind.IndexWithoutType
      else
        mSpec.Kind := TFormatSpecKind.UnknownType;
      Inc(mPos);
    end;
    mSpec.Text := Copy(AFormat, mStart, mPos - mStart);
    if mDynamic then
    begin
      mSpec.Argument := -1;
      mSpec.WidthArgument := -1;
      mSpec.PrecisionArgument := -1;
    end;
    Result.Specs := Result.Specs + [mSpec];
  end;
end;

class function TFormatString.LiteralValue(const AText: string; out AValue: string): Boolean;
var
  mOffsets: TArray<Integer>;
begin
  Result := LiteralOffsets(AText, AValue, mOffsets);
end;

class function TFormatString.LiteralOffsets(const AText: string; out AValue: string;
  out AOffsets: TArray<Integer>): Boolean;
var
  mPos, mCode, mDigits, mStart: Integer;
  mHex: Boolean;

  procedure Add(AChar: Char; AOffset: Integer);
  begin
    AValue := AValue + AChar;
    AOffsets := AOffsets + [AOffset];
  end;

begin
  AValue := '';
  AOffsets := nil;
  Result := False;
  // Mehrzeiliges Literal: ''' und ein Zeilenende (Delphi 12).
  if (AText = '') or AText.StartsWith('''''''') and (Length(AText) > 3) and CharInSet(AText[4], [#10, #13]) then
    Exit;
  mPos := 1;
  while mPos <= Length(AText) do
    case AText[mPos] of
      '''':
        begin
          Inc(mPos);
          repeat
            if mPos > Length(AText) then
              Exit;
            if AText[mPos] = '''' then
            begin
              if (mPos < Length(AText)) and (AText[mPos + 1] = '''') then
              begin
                Add('''', mPos - 1);
                Inc(mPos, 2);
                Continue;
              end;
              Inc(mPos);
              Break;
            end;
            Add(AText[mPos], mPos - 1);
            Inc(mPos);
          until False;
        end;
      '#':
        begin
          mStart := mPos;
          Inc(mPos);
          mHex := (mPos <= Length(AText)) and (AText[mPos] = '$');
          if mHex then
            Inc(mPos);
          mCode := 0;
          mDigits := 0;
          while (mPos <= Length(AText)) and (CharInSet(AText[mPos], ['0'..'9']) or mHex and
            CharInSet(AText[mPos], ['a'..'f', 'A'..'F'])) do
          begin
            if mHex then
              mCode := mCode * 16 + StrToInt('$' + AText[mPos])
            else
              mCode := mCode * 10 + Ord(AText[mPos]) - Ord('0');
            if mCode > $FFFF then
              Exit;
            Inc(mDigits);
            Inc(mPos);
          end;
          if mDigits = 0 then
            Exit;
          Add(Char(mCode), mStart - 1);
        end;
      ' ', #9, #10, #13:
        Inc(mPos);
    else
      Exit;
    end;
  Result := True;
end;

class function TFormatString.ExpressionValue(const AText: string; out AValue: string): Boolean;
var
  mPos, mStart: Integer;
  mQuoted: Boolean;
  mPart: string;
begin
  AValue := '';
  mQuoted := False;
  mStart := 1;
  for mPos := 1 to Length(AText) + 1 do
  begin
    if (mPos <= Length(AText)) and (AText[mPos] = '''') then
      mQuoted := not mQuoted;
    if (mPos > Length(AText)) or not mQuoted and (AText[mPos] = '+') then
    begin
      if not LiteralValue(Trim(Copy(AText, mStart, mPos - mStart)), mPart) then
        Exit(False);
      AValue := AValue + mPart;
      mStart := mPos + 1;
    end;
  end;
  Result := True;
end;

class function TFormatString.ConstantValue(const ASignature: string; out AValue: string): Boolean;
var
  mEqual, mQuote: Integer;
begin
  AValue := '';
  mEqual := Pos('=', ASignature);
  mQuote := Pos('''', ASignature);
  // Gekürzte Signatur bzw. "=" erst im Literal.
  if (mEqual = 0) or (Copy(ASignature, Length(ASignature), 1) = #$2026) or ((mQuote > 0) and (mQuote < mEqual)) then
    Exit(False);
  Result := ExpressionValue(Trim(Copy(ASignature, mEqual + 1, MaxInt)), AValue);
end;

class function TFormatString.LiteralClass(const AText: string; out ATypeName: string): TFormatArgumentClass;
var
  mText, mValue: string;
begin
  ATypeName := '';
  Result := TFormatArgumentClass.Unknown;
  mText := Trim(AText);
  if (mText <> '') and (mText[1] = '-') then
    mText := Trim(Copy(mText, 2, MaxInt));
  if mText = '' then
    Exit;
  if CharInSet(mText[1], ['''', '#']) and LiteralValue(mText, mValue) then
  begin
    ATypeName := 'ein String';
    if Length(mValue) = 1 then
      Exit(TFormatArgumentClass.Character);
    Exit(TFormatArgumentClass.Text);
  end;
  if CharInSet(mText[1], ['0'..'9', '$']) then
  begin
    ATypeName := 'eine Zahl';
    if (mText[1] <> '$') and ((Pos('.', mText) > 0) or (Pos('e', LowerCase(mText)) > 0)) then
      Exit(TFormatArgumentClass.Float);
    Exit(TFormatArgumentClass.Integer_);
  end;
end;

class function TFormatString.Fits(AType: Char; AClass: TFormatArgumentClass): Boolean;
begin
  if AClass in [TFormatArgumentClass.Unknown, TFormatArgumentClass.Variant_] then
    Exit(True);
  case AType of
    'd', 'u', 'x', '*':
      Result := AClass = TFormatArgumentClass.Integer_;
    'e', 'f', 'g', 'n', 'm':
      Result := AClass = TFormatArgumentClass.Float;
    's':
      Result := AClass in [TFormatArgumentClass.Text, TFormatArgumentClass.Character];
    'p':
      Result := AClass in [TFormatArgumentClass.Pointer_, TFormatArgumentClass.Object_];
  else
    Result := True;
  end;
end;

end.
