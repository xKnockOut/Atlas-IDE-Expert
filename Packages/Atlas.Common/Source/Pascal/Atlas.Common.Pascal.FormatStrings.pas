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
  System.SysUtils,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TFormatStringsText = (ANumber, AString);

const
  cTexts: array[TFormatStringsText] of TAtlasText = (
    (De: 'eine Zahl'; En: 'a number'),
    (De: 'ein String'; En: 'a string'));

{$SCOPEDENUMS OFF}

const
  cTypeChars = ['d', 'u', 'e', 'f', 'g', 'n', 'm', 'p', 's', 'x'];

function LowerChar(AChar: Char): Char;
begin
  Result := AChar;
  if CharInSet(AChar, ['A'..'Z']) then
  begin
    Result := Char(Ord(AChar) + Ord('a') - Ord('A'));
  end;
end;

type
  /// <summary>Liest die Platzhalter eines Formatstrings nacheinander (TFormatString.Parse).</summary>
  TFormatParser = record
  private
    FText: string;
    FPos: Integer;
    /// <summary>Nächstes Argument ohne Index.</summary>
    FNext: Integer;
    /// <summary>Index "*" gelesen: Zuordnung ab hier unbekannt.</summary>
    FDynamic: Boolean;
    function AtEnd: Boolean;
    /// <summary>Steht AChar an der aktuellen Stelle?</summary>
    function At(AChar: Char): Boolean;
    /// <summary>Ziffern oder "*" ab FPos; AStar: "*" gelesen.</summary>
    function ReadNumber(out AValue: Integer; out AStar: Boolean): Boolean;
    /// <summary>Breite bzw. Genauigkeit aus der Argumentliste: verbraucht ein Argument.</summary>
    function TakeArgument: Integer;
    /// <summary>Index, "-" und Breite; liefert, ob die Breite "*" ist.</summary>
    function ReadIndexAndWidth(var ASpec: TFormatSpec): Boolean;
    procedure ReadPrecision(var ASpec: TFormatSpec);
    procedure ReadType(var ASpec: TFormatSpec);
    /// <summary>Platzhalter ab dem "%" an AStart; FPos steht dahinter.</summary>
    function ReadSpec(AStart: Integer): TFormatSpec;
  public
    procedure Init(const AText: string);
    /// <summary>Nächster Platzhalter; False am Ende des Texts.</summary>
    function Next(out ASpec: TFormatSpec): Boolean;
  end;

  /// <summary>Liest ein Pascal-Stringliteral aus Teilen in Hochkommas und Zeichencodes
  /// (TFormatString.LiteralOffsets).</summary>
  TLiteralReader = record
  private
    FText: string;
    FPos: Integer;
    procedure Add(AChar: Char; AOffset: Integer);
    /// <summary>Teil in Hochkommas ab FPos; False, wenn er nicht endet.</summary>
    function ReadQuoted: Boolean;
    /// <summary>Ziffern eines Zeichencodes ab FPos; False ohne Ziffern oder bei Codes über $FFFF.</summary>
    function ReadCodeDigits(AHex: Boolean; out ACode: Integer): Boolean;
    /// <summary>Zeichencode #13 bzw. #$0A ab FPos; False bei ungültigem Code.</summary>
    function ReadCode: Boolean;
  public
    Value: string;
    Offsets: TArray<Integer>;
    procedure Init(const AText: string);
    /// <summary>Liest den ganzen Text; False bei anderem Text als Literalteilen und Leerraum.</summary>
    function Read: Boolean;
  end;

{ TFormatParser }

procedure TFormatParser.Init(const AText: string);
begin
  FText := AText;
  FPos := 1;
  FNext := 0;
  FDynamic := False;
end;

function TFormatParser.AtEnd: Boolean;
begin
  Result := FPos > Length(FText);
end;

function TFormatParser.At(AChar: Char): Boolean;
begin
  Result := not AtEnd and (FText[FPos] = AChar);
end;

function TFormatParser.ReadNumber(out AValue: Integer; out AStar: Boolean): Boolean;
var
  mFrom: Integer;
begin
  AValue := 0;
  AStar := At('*');
  if AStar then
  begin
    Inc(FPos);
    Exit(True);
  end;
  mFrom := FPos;
  while not AtEnd and CharInSet(FText[FPos], ['0'..'9']) do
  begin
    if AValue < 100000 then
    begin
      AValue := AValue * 10 + Ord(FText[FPos]) - Ord('0');
    end;
    Inc(FPos);
  end;
  Result := FPos > mFrom;
end;

function TFormatParser.TakeArgument: Integer;
begin
  Result := FNext;
  Inc(FNext);
end;

function TFormatParser.ReadIndexAndWidth(var ASpec: TFormatSpec): Boolean;
var
  mValue: Integer;
  mStar, mHasNumber: Boolean;
begin
  // Index oder Breite.
  mHasNumber := ReadNumber(mValue, mStar);
  if mHasNumber and At(':') then
  begin
    Inc(FPos);
    ASpec.ExplicitIndex := True;
    if mStar then
    begin
      FDynamic := True;
    end
    else
    begin
      FNext := mValue;
    end;
    if At('-') then
    begin
      Inc(FPos);
    end;
    mHasNumber := ReadNumber(mValue, mStar);
  end
  else if not mHasNumber and At('-') then
  begin
    Inc(FPos);
    mHasNumber := ReadNumber(mValue, mStar);
  end;
  Result := mHasNumber and mStar;
end;

procedure TFormatParser.ReadPrecision(var ASpec: TFormatSpec);
var
  mValue: Integer;
  mStar: Boolean;
begin
  if not At('.') then
  begin
    Exit;
  end;
  Inc(FPos);
  if ReadNumber(mValue, mStar) and mStar then
  begin
    ASpec.PrecisionArgument := TakeArgument;
  end;
end;

procedure TFormatParser.ReadType(var ASpec: TFormatSpec);
begin
  if AtEnd then
  begin
    ASpec.Kind := TFormatSpecKind.Incomplete;
    Exit;
  end;
  if CharInSet(LowerChar(FText[FPos]), cTypeChars) then
  begin
    ASpec.TypeChar := LowerChar(FText[FPos]);
    ASpec.Argument := TakeArgument;
  end
  else if ASpec.ExplicitIndex and not CharInSet(FText[FPos], ['a'..'z', 'A'..'Z']) then
  begin
    ASpec.Kind := TFormatSpecKind.IndexWithoutType;
  end
  else
  begin
    ASpec.Kind := TFormatSpecKind.UnknownType;
  end;
  Inc(FPos);
end;

function TFormatParser.ReadSpec(AStart: Integer): TFormatSpec;
begin
  Result := Default(TFormatSpec);
  Result.Offset := AStart;
  Result.Argument := -1;
  Result.WidthArgument := -1;
  Result.PrecisionArgument := -1;
  if ReadIndexAndWidth(Result) then
  begin
    Result.WidthArgument := TakeArgument;
  end;
  ReadPrecision(Result);
  Result.Dynamic := FDynamic;
  ReadType(Result);
  Result.Text := Copy(FText, AStart, FPos - AStart);
  if FDynamic then
  begin
    Result.Argument := -1;
    Result.WidthArgument := -1;
    Result.PrecisionArgument := -1;
  end;
end;

function TFormatParser.Next(out ASpec: TFormatSpec): Boolean;
var
  mStart: Integer;
begin
  while not AtEnd do
  begin
    if FText[FPos] <> '%' then
    begin
      Inc(FPos);
      Continue;
    end;
    mStart := FPos;
    Inc(FPos);
    if At('%') then
    begin
      Inc(FPos);
      Continue;
    end;
    ASpec := ReadSpec(mStart);
    Exit(True);
  end;
  Result := False;
end;

{ TLiteralReader }

procedure TLiteralReader.Init(const AText: string);
begin
  FText := AText;
  FPos := 1;
  Value := '';
  Offsets := nil;
end;

procedure TLiteralReader.Add(AChar: Char; AOffset: Integer);
begin
  Value := Value + AChar;
  Offsets := Offsets + [AOffset];
end;

function TLiteralReader.ReadQuoted: Boolean;
begin
  Inc(FPos);
  while FPos <= Length(FText) do
  begin
    if FText[FPos] <> '''' then
    begin
      Add(FText[FPos], FPos - 1);
      Inc(FPos);
    end
    else if (FPos < Length(FText)) and (FText[FPos + 1] = '''') then
    begin
      Add('''', FPos - 1);
      Inc(FPos, 2);
    end
    else
    begin
      Inc(FPos);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TLiteralReader.ReadCodeDigits(AHex: Boolean; out ACode: Integer): Boolean;
var
  mDigits: Integer;
begin
  ACode := 0;
  mDigits := 0;
  while (FPos <= Length(FText)) and (CharInSet(FText[FPos], ['0'..'9']) or AHex and
    CharInSet(FText[FPos], ['a'..'f', 'A'..'F'])) do
  begin
    if AHex then
    begin
      ACode := ACode * 16 + StrToInt('$' + FText[FPos]);
    end
    else
    begin
      ACode := ACode * 10 + Ord(FText[FPos]) - Ord('0');
    end;
    if ACode > $FFFF then
    begin
      Exit(False);
    end;
    Inc(mDigits);
    Inc(FPos);
  end;
  Result := mDigits > 0;
end;

function TLiteralReader.ReadCode: Boolean;
var
  mStart, mCode: Integer;
  mHex: Boolean;
begin
  mStart := FPos;
  Inc(FPos);
  mHex := (FPos <= Length(FText)) and (FText[FPos] = '$');
  if mHex then
  begin
    Inc(FPos);
  end;
  Result := ReadCodeDigits(mHex, mCode);
  if Result then
  begin
    Add(Char(mCode), mStart - 1);
  end;
end;

function TLiteralReader.Read: Boolean;
begin
  Result := True;
  while Result and (FPos <= Length(FText)) do
  begin
    case FText[FPos] of
      '''':
        Result := ReadQuoted;
      '#':
        Result := ReadCode;
      ' ', #9, #10, #13:
        Inc(FPos);
    else
      Result := False;
    end;
  end;
end;

{ TFormatString }

function TFormatString.Valid: Boolean;
var
  mSpec: TFormatSpec;
begin
  for mSpec in Specs do
  begin
    if mSpec.Kind <> TFormatSpecKind.Valid then
    begin
      Exit(False);
    end;
  end;
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
    begin
      Exit(-1);
    end;
    if mSpec.WidthArgument >= Result then
    begin
      Result := mSpec.WidthArgument + 1;
    end;
    if mSpec.PrecisionArgument >= Result then
    begin
      Result := mSpec.PrecisionArgument + 1;
    end;
    if mSpec.Argument >= Result then
    begin
      Result := mSpec.Argument + 1;
    end;
  end;
end;

function TFormatString.HasExplicitIndex: Boolean;
var
  mSpec: TFormatSpec;
begin
  for mSpec in Specs do
  begin
    if mSpec.ExplicitIndex then
    begin
      Exit(True);
    end;
  end;
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
  begin
    if (mSpec.Kind = TFormatSpecKind.Valid) and IsLocaleType(mSpec.TypeChar) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TFormatString.Parse(const AFormat: string): TFormatString;
var
  mParser: TFormatParser;
  mSpec: TFormatSpec;
begin
  Result.Specs := nil;
  mParser.Init(AFormat);
  while mParser.Next(mSpec) do
  begin
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
  mReader: TLiteralReader;
begin
  AValue := '';
  AOffsets := nil;
  // Mehrzeiliges Literal: ''' und ein Zeilenende (Delphi 12).
  if (AText = '') or AText.StartsWith('''''''') and (Length(AText) > 3) and CharInSet(AText[4], [#10, #13]) then
  begin
    Exit(False);
  end;
  mReader.Init(AText);
  Result := mReader.Read;
  if Result then
  begin
    AValue := mReader.Value;
    AOffsets := mReader.Offsets;
  end;
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
    begin
      mQuoted := not mQuoted;
    end;
    if (mPos > Length(AText)) or not mQuoted and (AText[mPos] = '+') then
    begin
      if not LiteralValue(Trim(Copy(AText, mStart, mPos - mStart)), mPart) then
      begin
        Exit(False);
      end;
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
  begin
    Exit(False);
  end;
  Result := ExpressionValue(Trim(Copy(ASignature, mEqual + 1, MaxInt)), AValue);
end;

/// <summary>Art einer Zahl ohne Vorzeichen: Float mit "." oder Exponent (nicht bei $-Zahlen), sonst Integer_.</summary>
function NumberClass(const AText: string): TFormatArgumentClass;
begin
  Result := TFormatArgumentClass.Integer_;
  if (AText[1] <> '$') and ((Pos('.', AText) > 0) or (Pos('e', LowerCase(AText)) > 0)) then
  begin
    Result := TFormatArgumentClass.Float;
  end;
end;

class function TFormatString.LiteralClass(const AText: string; out ATypeName: string): TFormatArgumentClass;
var
  mText, mValue: string;
begin
  ATypeName := '';
  Result := TFormatArgumentClass.Unknown;
  mText := Trim(AText);
  if (mText <> '') and (mText[1] = '-') then
  begin
    mText := Trim(Copy(mText, 2, MaxInt));
  end;
  if mText = '' then
  begin
    Exit;
  end;
  if CharInSet(mText[1], ['''', '#']) and LiteralValue(mText, mValue) then
  begin
    ATypeName := cTexts[TFormatStringsText.AString].Text;
    Result := TFormatArgumentClass.Text;
    if Length(mValue) = 1 then
    begin
      Result := TFormatArgumentClass.Character;
    end;
  end
  else if CharInSet(mText[1], ['0'..'9', '$']) then
  begin
    ATypeName := cTexts[TFormatStringsText.ANumber].Text;
    Result := NumberClass(mText);
  end;
end;

class function TFormatString.Fits(AType: Char; AClass: TFormatArgumentClass): Boolean;
begin
  if AClass in [TFormatArgumentClass.Unknown, TFormatArgumentClass.Variant_] then
  begin
    Exit(True);
  end;
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Pascal.FormatStrings', cTexts);

end.
