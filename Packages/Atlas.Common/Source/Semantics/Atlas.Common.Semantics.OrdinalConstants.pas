unit Atlas.Common.Semantics.OrdinalConstants;

// Werte ordinaler Konstantenausdrücke aus Token (#983): Ganzzahlen (dezimal,
// $hex, %binär, &oktal), Zeichen ('a', #13, #$0D), True und False, Klammern,
// die Operatoren + - * div mod and or xor not shl shr sowie Ord, Chr, Succ,
// Pred und Umwandlungen in ganzzahlige und Zeichentypen (mit Abschneiden wie
// Delphi: Cardinal(-1) = 4294967295, Integer($80000000) = -2147483648, #1324;
// bei Typen, deren Größe von der Plattform abhängt, nur Werte, die überall
// passen), dazu SizeOf, High und
// Low für Typen fester Größe (#992, #1083), MaxInt und MaxLongint. Namen (Konstanten, Aufzählungswerte) löst
// der Aufrufer über ALookup auf. Alles andere, auch Gleitkomma, Strings und
// Überläufe, gilt als nicht auswertbar. Check sagt zusätzlich, ob der Ausdruck
// sicher durch null teilt oder sicher überläuft (#992, wie E2098 und E2099):
// Überlauf heißt, das Ergebnis liegt auch außerhalb von UInt64, denn mit einem
// UInt64-Operanden rechnet Delphi Konstanten bis High(UInt64). Sind alle
// Operanden sicher vorzeichenbehaftet (Literale bis High(Int64), High/Low von
// Typen mit Vorzeichen), rechnet dcc in Int64: High(Int64) + 1 ist dann schon
// ein Überlauf (#1372, im Testprojekt Compilermeldungen mit Delphi 13 belegt).
// Namen und Umwandlungen in vorzeichenlose 64-Bit-Typen machen den Typ des
// Ausdrucks unsicher; ein Überlauf nur über High(Int64) bleibt dann unbekannt.

interface

uses
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Wert der Namenskette ANames (A.B.C), deren erstes Token in den ausgewerteten Token an
  /// ATokenIndex steht; False, wenn der Name keinen bekannten ordinalen Wert hat.</summary>
  TOrdinalNameLookup = reference to function(const ANames: TArray<string>; ATokenIndex: Integer;
    out AValue: Int64): Boolean;

  /// <summary>Ergebnis von TOrdinalConstants.Check: Wert bekannt, nicht auswertbar, Division durch null bzw.
  /// Überlauf mit sicher bekannten Operanden.</summary>
  TOrdinalStatus = (Value, Unknown, DivisionByZero, Overflow);

  TOrdinalConstants = record
  public
    /// <summary>Wert der Token AFirst..ALast (Kommentare und Direktiven zählen nicht); False, wenn der
    /// Ausdruck nicht vollständig auswertbar ist. ALookup darf nil sein.</summary>
    class function Evaluate(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
      const ALookup: TOrdinalNameLookup; out AValue: Int64): Boolean; overload; static;
    /// <summary>Wie oben über den ganzen Text AText (z. B. "5 + Max").</summary>
    class function Evaluate(const AText: string; const ALookup: TOrdinalNameLookup;
      out AValue: Int64): Boolean; overload; static;
    /// <summary>Wie Evaluate, sagt aber auch, warum ein Ausdruck nicht auswertbar ist (#992).</summary>
    class function Check(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
      const ALookup: TOrdinalNameLookup; out AValue: Int64): TOrdinalStatus; overload; static;
    class function Check(const AText: string; const ALookup: TOrdinalNameLookup;
      out AValue: Int64): TOrdinalStatus; overload; static;
    /// <summary>Wertebereich und Größe des Typs ATypeName fester Größe (Byte, Integer, Char, Int64 …);
    /// False bei unbekannten und plattformabhängigen Typen (NativeInt, LongInt, Pointer). AHighKnown ist
    /// False bei UInt64, dessen Obergrenze nicht in Int64 passt.</summary>
    class function FixedType(const ATypeName: string; out ALow, AHigh: Int64; out AHighKnown: Boolean;
      out ASize: Integer): Boolean; static;
    /// <summary>Wert eines Zahl-Tokens (dezimal, $, %, &amp;); False bei Gleitkomma.</summary>
    class function TryNumber(const AText: string; out AValue: Int64): Boolean; static;
  end;

implementation

// Überläufe melden sich als EIntOverflow und machen den Ausdruck unauswertbar.
{$OVERFLOWCHECKS ON}

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Lexer;

const
  OrdinalCasts: array[0..23] of string = ('Byte', 'Word', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'ShortInt',
    'SmallInt', 'LongInt', 'LongWord', 'NativeInt', 'NativeUInt', 'Char', 'AnsiChar', 'WideChar', 'Ord', 'Int8',
    'UInt8', 'Int16', 'UInt16', 'Int32', 'UInt32', 'FixedInt', 'FixedUInt');
  // Tiefe der Klammern und Aufrufe, damit ein Ausdruck aus fremdem Quelltext den Stapel nicht sprengt.
  MaxDepth = 64;
  // Grenzen für den sicheren Überlauf als Gleitkommaschätzung: unter Low(Int64) bzw. deutlich über
  // High(UInt64); knapp daneben bleibt der Ausdruck nur unbekannt.
  OverflowBelow = -9.2233720368547758e18;
  OverflowAbove = 1.85e19;

/// <summary>Vorzeichenloser Typ, der auf einer Plattform 64 Bit breit ist (UInt64, NativeUInt, LongWord).</summary>
function UnsignedWide(const ATypeName: string): Boolean;
begin
  Result := MatchText(ATypeName, ['UInt64', 'NativeUInt', 'LongWord', 'System.UInt64', 'System.NativeUInt',
    'System.LongWord']);
end;

type
  TEvaluator = class
  private
    FTokens: TArray<TPascalToken>;
    FIndex: Integer;
    FLast: Integer;
    FLookup: TOrdinalNameLookup;
    FFailed: Boolean;
    FStatus: TOrdinalStatus;
    FDepth: Integer;
    // Ein Operand könnte UInt64 sein (Name, Umwandlung, Low/High eines vorzeichenlosen 64-Bit-Typs): Dann rechnet
    // Delphi bis High(UInt64), ein Überlauf über High(Int64) ist kein sicherer Fehler (#1372).
    FMaybeUnsigned: Boolean;
    procedure SkipTrivia;
    function AtEnd: Boolean;
    function Current: TPascalToken;
    procedure Advance;
    function IsSym(const ASymbol: string): Boolean;
    function IsWord(const AWord: string): Boolean;
    procedure Fail;
    procedure FailWith(AStatus: TOrdinalStatus);
    function Arith(const AOperation: string; ALeft, ARight: Int64): Int64;
    function TypeArgument(out AName: string): Boolean;
    function Expression: Int64;
    function Term: Int64;
    function Factor: Int64;
    function Primary: Int64;
    /// <summary>Wert des Tokens AToken am Anfang eines Operanden.</summary>
    function TokenValue(const AToken: TPascalToken): Int64;
    /// <summary>Nach einem Zeichen: AKnown sonst Fehler; 'a'#13 und #13#10 sind Strings, keine Zeichen.</summary>
    procedure EndCharacter(AKnown: Boolean);
    function Parenthesized: Int64;
    /// <summary>Name, Namenskette oder Funktionsaufruf ab dem Token an AStart.</summary>
    function NamedValue(AStart: Integer; const AName: string): Int64;
    /// <summary>SizeOf, High und Low eines Typs fester Größe; False, wenn es keins davon ist.</summary>
    function TypeQuery(const AName: string; out AValue: Int64): Boolean;
    /// <summary>Ord, Chr, Succ, Pred und Typumwandlungen.</summary>
    function FunctionValue(const AName: string): Int64;
    /// <summary>Kette A.B.C ab AName über FLookup, sonst True, False, MaxInt und MaxLongint.</summary>
    function ChainValue(AStart: Integer; const AName: string): Int64;
    function AtTermOperator: Boolean;
    function ApplyTerm(const AOperation: string; ALeft, ARight: Int64): Int64;
    function Arguments: Int64;
    function Cast(const ATypeName: string; AValue: Int64): Int64;
    /// <summary>Umwandlung in NativeInt, LongInt, NativeUInt, LongWord: 32 oder 64 Bit je Plattform.</summary>
    procedure CheckPlatformCast(const ATypeName: string; AValue: Int64);
  public
    constructor Create(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
      const ALookup: TOrdinalNameLookup);
    function Run(out AValue: Int64): TOrdinalStatus;
  end;

{ TEvaluator }

constructor TEvaluator.Create(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  const ALookup: TOrdinalNameLookup);
begin
  inherited Create;
  FTokens := ATokens;
  FIndex := AFirst;
  FLast := ALast;
  if FLast > High(FTokens) then
  begin
    FLast := High(FTokens);
  end;
  FLookup := ALookup;
end;

procedure TEvaluator.SkipTrivia;
begin
  while (FIndex <= FLast) and (FTokens[FIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
  begin
    Inc(FIndex);
  end;
end;

function TEvaluator.AtEnd: Boolean;
begin
  SkipTrivia;
  Result := FIndex > FLast;
end;

function TEvaluator.Current: TPascalToken;
begin
  SkipTrivia;
  if FIndex <= FLast then
  begin
    Result := FTokens[FIndex];
  end
  else
  begin
    Result := Default(TPascalToken);
  end;
end;

procedure TEvaluator.Advance;
begin
  SkipTrivia;
  if FIndex <= FLast then
  begin
    Inc(FIndex);
  end;
end;

function TEvaluator.IsSym(const ASymbol: string): Boolean;
begin
  Result := not AtEnd and Current.IsSymbol(ASymbol);
end;

function TEvaluator.IsWord(const AWord: string): Boolean;
begin
  Result := not AtEnd and (Current.Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier]) and
    SameText(Current.Text, AWord);
end;

procedure TEvaluator.Fail;
begin
  FFailed := True;
end;

procedure TEvaluator.FailWith(AStatus: TOrdinalStatus);
begin
  // Der erste Grund zählt.
  if not FFailed then
  begin
    FStatus := AStatus;
  end;
  FFailed := True;
end;

/// <summary>Grobe Schätzung des Ergebnisses als Gleitkommazahl.</summary>
function Estimate(const AOperation: string; ALeft, ARight: Int64): Double;
begin
  if AOperation = '+' then
  begin
    Result := ALeft + Double(ARight);
  end
  else if AOperation = '-' then
  begin
    Result := ALeft - Double(ARight);
  end
  else
  begin
    Result := ALeft * Double(ARight);
  end;
end;

/// <summary>Ergebnis sicher unter Low(Int64)? Exakt geprüft: Double hat dort zu wenig Stellen
/// (Low(Int64) - 10 ergäbe wieder Low(Int64)).</summary>
function BelowLowest(const AOperation: string; ALeft, ARight: Int64): Boolean;
begin
  if AOperation = '+' then
  begin
    Result := (ARight < 0) and (ALeft < Low(Int64) - ARight);
  end
  else if AOperation = '-' then
  begin
    Result := (ARight > 0) and (ALeft < Low(Int64) + ARight);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Exaktes Ergebnis; knapp an den Grenzen meldet die Überlaufprüfung EIntOverflow.</summary>
function Exact(const AOperation: string; ALeft, ARight: Int64): Int64;
begin
  if AOperation = '+' then
  begin
    Result := ALeft + ARight;
  end
  else if AOperation = '-' then
  begin
    Result := ALeft - ARight;
  end
  else
  begin
    Result := ALeft * ARight;
  end;
end;

function TEvaluator.Arith(const AOperation: string; ALeft, ARight: Int64): Int64;
var
  mEstimate: Double;
begin
  // Erst grob schätzen: Liegt das Ergebnis sicher außerhalb dessen, was Delphi rechnet, ist es ein Überlauf.
  Result := 0;
  mEstimate := Estimate(AOperation, ALeft, ARight);
  if (mEstimate < OverflowBelow) or (mEstimate > OverflowAbove) or BelowLowest(AOperation, ALeft, ARight) then
  begin
    FailWith(TOrdinalStatus.Overflow);
    Exit;
  end;
  // Mit lauter vorzeichenbehafteten Operanden rechnet dcc in Int64 und meldet E2099 (#1372); mit einem möglichen
  // UInt64-Operanden bleibt es unbekannt.
  try
    Result := Exact(AOperation, ALeft, ARight);
  except
    on EIntOverflow do
    begin
      Result := 0;
      if FMaybeUnsigned then
      begin
        Fail;
      end
      else
      begin
        FailWith(TOrdinalStatus.Overflow);
      end;
    end;
  end;
end;

function TEvaluator.Run(out AValue: Int64): TOrdinalStatus;
begin
  AValue := 0;
  FStatus := TOrdinalStatus.Unknown;
  if AtEnd then
  begin
    Exit(TOrdinalStatus.Unknown);
  end;
  try
    AValue := Expression;
  except
    // Überlauf knapp an den Grenzen und Division durch null ohne Prüfung: nicht auswertbar.
    on EIntOverflow do
      Fail;
    on EDivByZero do
      Fail;
  end;
  if FFailed then
  begin
    Result := FStatus;
  end
  else if AtEnd then
  begin
    Result := TOrdinalStatus.Value;
  end
  else
  begin
    Result := TOrdinalStatus.Unknown;
  end;
  if Result <> TOrdinalStatus.Value then
  begin
    AValue := 0;
  end;
end;

function TEvaluator.Expression: Int64;
var
  Right: Int64;
begin
  Result := Term;
  while not FFailed and (IsSym('+') or IsSym('-') or IsWord('or') or IsWord('xor')) do
  begin
    if IsSym('+') then
    begin
      Advance;
      Right := Term;
      if FFailed then
      begin
        Exit;
      end;
      Result := Arith('+', Result, Right);
    end
    else if IsSym('-') then
    begin
      Advance;
      Right := Term;
      if FFailed then
      begin
        Exit;
      end;
      Result := Arith('-', Result, Right);
    end
    else if IsWord('or') then
    begin
      Advance;
      Right := Term;
      Result := Result or Right;
    end
    else
    begin
      Advance;
      Right := Term;
      Result := Result xor Right;
    end;
  end;
end;

const
  // Operatoren der Stufe von *, als Wörter.
  cTermWords: array[0..4] of string = ('div', 'mod', 'and', 'shl', 'shr');

function TEvaluator.AtTermOperator: Boolean;
var
  mWord: string;
begin
  if IsSym('*') then
  begin
    Exit(True);
  end;
  for mWord in cTermWords do
  begin
    if IsWord(mWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TEvaluator.ApplyTerm(const AOperation: string; ALeft, ARight: Int64): Int64;
begin
  Result := ALeft;
  if AOperation = '*' then
  begin
    Result := Arith('*', ALeft, ARight);
  end
  else if ((AOperation = 'div') or (AOperation = 'mod')) and (ARight = 0) then
  begin
    FailWith(TOrdinalStatus.DivisionByZero);
  end
  else if AOperation = 'div' then
  begin
    Result := ALeft div ARight;
  end
  else if AOperation = 'mod' then
  begin
    Result := ALeft mod ARight;
  end
  else if AOperation = 'and' then
  begin
    Result := ALeft and ARight;
  end
  else if (ARight < 0) or (ARight > 63) then
  begin
    Fail;
  end
  else if AOperation = 'shl' then
  begin
    Result := ALeft shl ARight;
  end
  else
  begin
    Result := ALeft shr ARight;
  end;
end;

function TEvaluator.Term: Int64;
var
  mRight: Int64;
  mOperation: string;
begin
  Result := Factor;
  while not FFailed and AtTermOperator do
  begin
    mOperation := LowerCase(Current.Text);
    Advance;
    mRight := Factor;
    if FFailed then
    begin
      Exit;
    end;
    Result := ApplyTerm(mOperation, Result, mRight);
  end;
end;

function TEvaluator.Factor: Int64;
begin
  if IsSym('-') then
  begin
    Advance;
    Result := -Factor;
  end
  else if IsSym('+') then
  begin
    Advance;
    Result := Factor;
  end
  else if IsWord('not') then
  begin
    Advance;
    Result := not Factor;
  end
  else
  begin
    Result := Primary;
  end;
end;

function TEvaluator.Arguments: Int64;
begin
  // ( Ausdruck ) nach einem Funktionsnamen.
  Result := 0;
  if not IsSym('(') then
  begin
    Fail;
    Exit;
  end;
  Advance;
  Result := Expression;
  if not IsSym(')') then
  begin
    Fail;
    Exit;
  end;
  Advance;
end;

procedure TEvaluator.CheckPlatformCast(const ATypeName: string; AValue: Int64);
var
  mLow, mHigh: Int64;
begin
  // Werte, die in 32 Bit passen, bleiben überall gleich; sonst hängt das Ergebnis von der Plattform ab.
  if MatchText(ATypeName, ['NativeInt', 'LongInt']) then
  begin
    mLow := -2147483648;
    mHigh := 2147483647;
  end
  else
  begin
    mLow := 0;
    mHigh := 4294967295;
  end;
  if (AValue < mLow) or (AValue > mHigh) then
  begin
    Fail;
  end;
end;

/// <summary>AValue auf den Bereich ALow..AHigh eines Typs unter 8 Byte abgeschnitten.</summary>
function Truncated(AValue, ALow, AHigh: Int64): Int64;
var
  mBits: UInt64;
begin
  mBits := UInt64(AValue) and (UInt64(AHigh - ALow));
  if (ALow < 0) and (mBits > UInt64(AHigh)) then
  begin
    Result := Int64(mBits) + ALow * 2;
  end
  else
  begin
    Result := Int64(mBits);
  end;
end;

function TEvaluator.Cast(const ATypeName: string; AValue: Int64): Int64;
var
  mLow, mHigh: Int64;
  mHighKnown: Boolean;
  mSize: Integer;
begin
  // Umwandlung eines konstanten Werts (#1324): Delphi schneidet auf die Größe des Zieltyps ab.
  Result := AValue;
  if SameText(ATypeName, 'Ord') then
  begin
    Exit;
  end;
  if UnsignedWide(ATypeName) then
  begin
    FMaybeUnsigned := True;
  end;
  if not TOrdinalConstants.FixedType(ATypeName, mLow, mHigh, mHighKnown, mSize) then
  begin
    CheckPlatformCast(ATypeName, AValue);
  end
  // UInt64(-1) liegt über High(Int64) und lässt sich als Int64 nicht darstellen.
  else if mSize >= 8 then
  begin
    if not mHighKnown and (AValue < 0) then
    begin
      Fail;
    end;
  end
  else
  begin
    Result := Truncated(AValue, mLow, mHigh);
  end;
end;

function TEvaluator.TypeArgument(out AName: string): Boolean;
var
  Start: Integer;
begin
  // ( Typname ) ohne Punkt; danach steht der Zeiger hinter der Klammer.
  Result := False;
  AName := '';
  Start := FIndex;
  if not IsSym('(') then
  begin
    Exit;
  end;
  Advance;
  if AtEnd or not (Current.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
  begin
    FIndex := Start;
    Exit;
  end;
  AName := Current.Text;
  Advance;
  if not IsSym(')') then
  begin
    FIndex := Start;
    Exit;
  end;
  Advance;
  Result := True;
end;

/// <summary>Wert eines Zeichens #13, #$0D.</summary>
function CharValue(const AText: string; out AValue: Int64): Boolean;
var
  mDigits: string;
begin
  mDigits := Copy(AText, 2, MaxInt);
  AValue := 0;
  Result := (mDigits <> '') and TOrdinalConstants.TryNumber(mDigits, AValue);
end;

/// <summary>Wert eines Strings aus genau einem Zeichen: 'a' bzw. '''' für das Hochkomma.</summary>
function StringValue(const AText: string; out AValue: Int64): Boolean;
var
  mInner: string;
begin
  AValue := 0;
  mInner := '';
  if (Length(AText) >= 3) and (AText[1] = '''') and (AText[Length(AText)] = '''') then
  begin
    mInner := StringReplace(Copy(AText, 2, Length(AText) - 2), '''''', '''', [rfReplaceAll]);
  end;
  Result := Length(mInner) = 1;
  if Result then
  begin
    AValue := Ord(mInner[1]);
  end;
end;

procedure TEvaluator.EndCharacter(AKnown: Boolean);
begin
  if not AKnown then
  begin
    Fail;
  end;
  Advance;
  if not AtEnd and (Current.Kind in [TPascalTokenKind.CharLiteral, TPascalTokenKind.StringLiteral]) then
  begin
    Fail;
  end;
end;

function TEvaluator.Parenthesized: Int64;
begin
  Advance;
  Result := Expression;
  if not IsSym(')') then
  begin
    Fail;
  end
  else
  begin
    Advance;
  end;
end;

function TEvaluator.TypeQuery(const AName: string; out AValue: Int64): Boolean;
var
  mTypeName: string;
  mLowest, mHighest: Int64;
  mHighKnown: Boolean;
  mSize: Integer;
begin
  AValue := 0;
  Result := MatchText(AName, ['SizeOf', 'High', 'Low']) and TypeArgument(mTypeName);
  if not Result then
  begin
    Exit;
  end;
  if not SameText(AName, 'SizeOf') and UnsignedWide(mTypeName) then
  begin
    FMaybeUnsigned := True;
  end;
  if not TOrdinalConstants.FixedType(mTypeName, mLowest, mHighest, mHighKnown, mSize) or
    (SameText(AName, 'High') and not mHighKnown) then
  begin
    Fail;
  end
  else if SameText(AName, 'SizeOf') then
  begin
    AValue := mSize;
  end
  else if SameText(AName, 'High') then
  begin
    AValue := mHighest;
  end
  else
  begin
    AValue := mLowest;
  end;
end;

function TEvaluator.FunctionValue(const AName: string): Int64;
begin
  Result := 0;
  if SameText(AName, 'Succ') then
  begin
    Result := Arguments + 1;
  end
  else if SameText(AName, 'Pred') then
  begin
    Result := Arguments - 1;
  end
  else if SameText(AName, 'Chr') then
  begin
    Result := Arguments;
  end
  else if IndexText(AName, OrdinalCasts) >= 0 then
  begin
    Result := Cast(AName, Arguments);
  end
  else
  begin
    Fail;
  end;
end;

/// <summary>Wert der eingebauten Namen True und False und der Konstanten aus System mit festem Wert auf allen
/// Plattformen (#1083); False bei anderen Namen.</summary>
function BuiltinValue(const AName: string; out AValue: Int64): Boolean;
begin
  Result := True;
  AValue := 0;
  if SameText(AName, 'True') then
  begin
    AValue := 1;
  end
  else if MatchText(AName, ['MaxInt', 'MaxLongint']) then
  begin
    AValue := 2147483647;
  end
  else
  begin
    Result := SameText(AName, 'False');
  end;
end;

function TEvaluator.ChainValue(AStart: Integer; const AName: string): Int64;
var
  mNames: TArray<string>;
begin
  Result := 0;
  mNames := TArray<string>.Create(AName);
  while IsSym('.') do
  begin
    Advance;
    if AtEnd or not (Current.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
    begin
      Fail;
      Exit;
    end;
    mNames := mNames + [Current.Text];
    Advance;
  end;
  if Assigned(FLookup) and FLookup(mNames, AStart, Result) then
  begin
    // Der Typ einer Konstanten ist unbekannt; sie könnte UInt64 sein.
    FMaybeUnsigned := True;
  end
  else if (Length(mNames) <> 1) or not BuiltinValue(AName, Result) then
  begin
    Result := 0;
    Fail;
  end;
end;

function TEvaluator.NamedValue(AStart: Integer; const AName: string): Int64;
begin
  Advance;
  if not IsSym('(') then
  begin
    Result := ChainValue(AStart, AName);
  end
  else if not TypeQuery(AName, Result) then
  begin
    Result := FunctionValue(AName);
  end;
end;

function TEvaluator.TokenValue(const AToken: TPascalToken): Int64;
begin
  Result := 0;
  case AToken.Kind of
    TPascalTokenKind.Number:
      begin
        if not TOrdinalConstants.TryNumber(AToken.Text, Result) then
        begin
          Fail;
        end;
        Advance;
      end;
    TPascalTokenKind.CharLiteral:
      EndCharacter(CharValue(AToken.Text, Result));
    TPascalTokenKind.StringLiteral:
      EndCharacter(StringValue(AToken.Text, Result));
    TPascalTokenKind.Symbol:
      if AToken.IsSymbol('(') then
      begin
        Result := Parenthesized;
      end
      else
      begin
        Fail;
      end;
    TPascalTokenKind.Identifier, TPascalTokenKind.Keyword:
      Result := NamedValue(FIndex, AToken.Text);
  else
    Fail;
  end;
end;

function TEvaluator.Primary: Int64;
begin
  Result := 0;
  if AtEnd or FFailed then
  begin
    Fail;
    Exit;
  end;
  Inc(FDepth);
  try
    if FDepth > MaxDepth then
    begin
      Fail;
    end
    else
    begin
      Result := TokenValue(Current);
    end;
  finally
    Dec(FDepth);
  end;
end;

{ TOrdinalConstants }

type
  TFixedTypeInfo = record
    Name: string;
    LowValue: Int64;
    HighValue: Int64;
    Size: Integer;
    HighKnown: Boolean;
  end;

const
  // Gleitkomma hat nur eine Größe, keinen ordinalen Bereich; die Obergrenze von UInt64 passt nicht in Int64.
  // Der letzte Eintrag ohne Namen steht für unbekannte Typen.
  cFixedTypes: array[0..26] of TFixedTypeInfo = (
    (Name: 'byte'; LowValue: 0; HighValue: 255; Size: 1; HighKnown: True),
    (Name: 'uint8'; LowValue: 0; HighValue: 255; Size: 1; HighKnown: True),
    (Name: 'ansichar'; LowValue: 0; HighValue: 255; Size: 1; HighKnown: True),
    (Name: 'shortint'; LowValue: -128; HighValue: 127; Size: 1; HighKnown: True),
    (Name: 'int8'; LowValue: -128; HighValue: 127; Size: 1; HighKnown: True),
    (Name: 'word'; LowValue: 0; HighValue: 65535; Size: 2; HighKnown: True),
    (Name: 'uint16'; LowValue: 0; HighValue: 65535; Size: 2; HighKnown: True),
    (Name: 'char'; LowValue: 0; HighValue: 65535; Size: 2; HighKnown: True),
    (Name: 'widechar'; LowValue: 0; HighValue: 65535; Size: 2; HighKnown: True),
    (Name: 'smallint'; LowValue: -32768; HighValue: 32767; Size: 2; HighKnown: True),
    (Name: 'int16'; LowValue: -32768; HighValue: 32767; Size: 2; HighKnown: True),
    (Name: 'integer'; LowValue: -2147483648; HighValue: 2147483647; Size: 4; HighKnown: True),
    (Name: 'int32'; LowValue: -2147483648; HighValue: 2147483647; Size: 4; HighKnown: True),
    (Name: 'fixedint'; LowValue: -2147483648; HighValue: 2147483647; Size: 4; HighKnown: True),
    (Name: 'cardinal'; LowValue: 0; HighValue: 4294967295; Size: 4; HighKnown: True),
    (Name: 'uint32'; LowValue: 0; HighValue: 4294967295; Size: 4; HighKnown: True),
    (Name: 'dword'; LowValue: 0; HighValue: 4294967295; Size: 4; HighKnown: True),
    (Name: 'fixeduint'; LowValue: 0; HighValue: 4294967295; Size: 4; HighKnown: True),
    (Name: 'int64'; LowValue: Low(Int64); HighValue: High(Int64); Size: 8; HighKnown: True),
    (Name: 'uint64'; LowValue: 0; HighValue: 0; Size: 8; HighKnown: False),
    (Name: 'boolean'; LowValue: 0; HighValue: 1; Size: 1; HighKnown: True),
    (Name: 'bytebool'; LowValue: 0; HighValue: 1; Size: 1; HighKnown: True),
    (Name: 'single'; LowValue: 0; HighValue: 0; Size: 4; HighKnown: False),
    (Name: 'double'; LowValue: 0; HighValue: 0; Size: 8; HighKnown: False),
    (Name: 'currency'; LowValue: 0; HighValue: 0; Size: 8; HighKnown: False),
    (Name: 'comp'; LowValue: 0; HighValue: 0; Size: 8; HighKnown: False),
    (Name: ''; LowValue: 0; HighValue: 0; Size: 0; HighKnown: False));

class function TOrdinalConstants.FixedType(const ATypeName: string; out ALow, AHigh: Int64;
  out AHighKnown: Boolean; out ASize: Integer): Boolean;
var
  mName: string;
  mIndex: Integer;
begin
  mName := LowerCase(ATypeName);
  if StartsText('system.', mName) then
  begin
    mName := Copy(mName, Length('system.') + 1, MaxInt);
  end;
  mIndex := 0;
  while (mIndex < High(cFixedTypes)) and (cFixedTypes[mIndex].Name <> mName) do
  begin
    Inc(mIndex);
  end;
  ALow := cFixedTypes[mIndex].LowValue;
  AHigh := cFixedTypes[mIndex].HighValue;
  ASize := cFixedTypes[mIndex].Size;
  AHighKnown := cFixedTypes[mIndex].HighKnown;
  Result := mIndex < High(cFixedTypes);
end;

/// <summary>Basis nach dem Präfix von AText ($, %, &amp;), das dabei entfernt wird; sonst 10.</summary>
function NumberBase(var AText: string): Integer;
begin
  Result := 10;
  if AText = '' then
  begin
    Exit;
  end;
  case AText[1] of
    '$':
      Result := 16;
    '%':
      Result := 2;
    '&':
      Result := 8;
  end;
  if Result <> 10 then
  begin
    AText := Copy(AText, 2, MaxInt);
  end;
end;

/// <summary>Wert der Ziffer AChar; -1 bei anderen Zeichen.</summary>
function DigitOf(AChar: Char): Integer;
begin
  case AChar of
    '0'..'9':
      Result := Ord(AChar) - Ord('0');
    'a'..'f':
      Result := Ord(AChar) - Ord('a') + 10;
    'A'..'F':
      Result := Ord(AChar) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

/// <summary>Ziffern ADigits zur Basis ABase; False bei fremden Zeichen und mehr, als Int64 fasst.</summary>
function DigitsValue(const ADigits: string; ABase: Integer; out AValue: UInt64): Boolean;
var
  mIndex, mDigit: Integer;
begin
  AValue := 0;
  for mIndex := 1 to Length(ADigits) do
  begin
    mDigit := DigitOf(ADigits[mIndex]);
    if (mDigit < 0) or (mDigit >= ABase) or
      (AValue > (UInt64(High(Int64)) - UInt64(mDigit)) div UInt64(ABase)) then
    begin
      Exit(False);
    end;
    AValue := AValue * UInt64(ABase) + UInt64(mDigit);
  end;
  Result := ADigits <> '';
end;

class function TOrdinalConstants.TryNumber(const AText: string; out AValue: Int64): Boolean;
var
  mText: string;
  mBase: Integer;
  mValue: UInt64;
begin
  AValue := 0;
  mText := StringReplace(AText, '_', '', [rfReplaceAll]);
  mBase := NumberBase(mText);
  Result := DigitsValue(mText, mBase, mValue);
  if Result then
  begin
    AValue := Int64(mValue);
  end;
end;

class function TOrdinalConstants.Check(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  const ALookup: TOrdinalNameLookup; out AValue: Int64): TOrdinalStatus;
var
  Evaluator: TEvaluator;
begin
  AValue := 0;
  if (AFirst < 0) or (AFirst > ALast) then
  begin
    Exit(TOrdinalStatus.Unknown);
  end;
  Evaluator := TEvaluator.Create(ATokens, AFirst, ALast, ALookup);
  try
    Result := Evaluator.Run(AValue);
  finally
    Evaluator.Free;
  end;
end;

class function TOrdinalConstants.Check(const AText: string; const ALookup: TOrdinalNameLookup;
  out AValue: Int64): TOrdinalStatus;
var
  Tokens: TArray<TPascalToken>;
begin
  Tokens := TPascalLexer.Tokenize(AText);
  Result := Check(Tokens, 0, High(Tokens), ALookup, AValue);
end;

class function TOrdinalConstants.Evaluate(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  const ALookup: TOrdinalNameLookup; out AValue: Int64): Boolean;
begin
  Result := Check(ATokens, AFirst, ALast, ALookup, AValue) = TOrdinalStatus.Value;
end;

class function TOrdinalConstants.Evaluate(const AText: string; const ALookup: TOrdinalNameLookup;
  out AValue: Int64): Boolean;
var
  Tokens: TArray<TPascalToken>;
begin
  Tokens := TPascalLexer.Tokenize(AText);
  Result := Evaluate(Tokens, 0, High(Tokens), ALookup, AValue);
end;

end.
