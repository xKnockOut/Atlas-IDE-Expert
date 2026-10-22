unit Atlas.Common.Semantics.OrdinalConstants;

// Werte ordinaler Konstantenausdrücke aus Token (#983): Ganzzahlen (dezimal,
// $hex, %binär, &oktal), Zeichen ('a', #13, #$0D), True und False, Klammern,
// die Operatoren + - * div mod and or xor not shl shr sowie Ord, Chr, Succ,
// Pred und Umwandlungen in ganzzahlige und Zeichentypen, dazu SizeOf, High und
// Low für Typen fester Größe (#992, #1083), MaxInt und MaxLongint. Namen (Konstanten, Aufzählungswerte) löst
// der Aufrufer über ALookup auf. Alles andere, auch Gleitkomma, Strings und
// Überläufe, gilt als nicht auswertbar. Check sagt zusätzlich, ob der Ausdruck
// sicher durch null teilt oder sicher überläuft (#992, wie E2098 und E2099):
// Überlauf heißt, das Ergebnis liegt auch außerhalb von UInt64, denn Delphi
// rechnet Konstanten bis High(UInt64).

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
  OrdinalCasts: array[0..15] of string = ('Byte', 'Word', 'Integer', 'Cardinal', 'Int64', 'UInt64', 'ShortInt',
    'SmallInt', 'LongInt', 'LongWord', 'NativeInt', 'NativeUInt', 'Char', 'AnsiChar', 'WideChar', 'Ord');
  // Tiefe der Klammern und Aufrufe, damit ein Ausdruck aus fremdem Quelltext den Stapel nicht sprengt.
  MaxDepth = 64;
  // Grenzen für den sicheren Überlauf als Gleitkommaschätzung: unter Low(Int64) bzw. deutlich über
  // High(UInt64); knapp daneben bleibt der Ausdruck nur unbekannt.
  OverflowBelow = -9.2233720368547758e18;
  OverflowAbove = 1.85e19;

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
    function CharValue(const AText: string; out AValue: Int64): Boolean;
    function StringValue(const AText: string; out AValue: Int64): Boolean;
    function Arguments: Int64;
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
    FLast := High(FTokens);
  FLookup := ALookup;
end;

procedure TEvaluator.SkipTrivia;
begin
  while (FIndex <= FLast) and (FTokens[FIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Inc(FIndex);
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
    Result := FTokens[FIndex]
  else
    Result := Default(TPascalToken);
end;

procedure TEvaluator.Advance;
begin
  SkipTrivia;
  if FIndex <= FLast then
    Inc(FIndex);
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
    FStatus := AStatus;
  FFailed := True;
end;

function TEvaluator.Arith(const AOperation: string; ALeft, ARight: Int64): Int64;
var
  Estimate: Double;
begin
  // Erst grob schätzen: Liegt das Ergebnis sicher außerhalb dessen, was Delphi rechnet, ist es ein Überlauf.
  Result := 0;
  if AOperation = '+' then
    Estimate := ALeft + Double(ARight)
  else if AOperation = '-' then
    Estimate := ALeft - Double(ARight)
  else
    Estimate := ALeft * Double(ARight);
  if (Estimate < OverflowBelow) or (Estimate > OverflowAbove) then
  begin
    FailWith(TOrdinalStatus.Overflow);
    Exit;
  end;
  // Unter Low(Int64) ist es sicher ein Überlauf. Exakt prüfen: Double hat dort zu wenig Stellen
  // (Low(Int64) - 10 ergäbe wieder Low(Int64)).
  if ((AOperation = '+') and (ARight < 0) and (ALeft < Low(Int64) - ARight)) or
    ((AOperation = '-') and (ARight > 0) and (ALeft < Low(Int64) + ARight)) then
  begin
    FailWith(TOrdinalStatus.Overflow);
    Exit;
  end;
  // Knapp an den Grenzen meldet die Überlaufprüfung EIntOverflow; Run macht daraus "unbekannt".
  if AOperation = '+' then
    Result := ALeft + ARight
  else if AOperation = '-' then
    Result := ALeft - ARight
  else
    Result := ALeft * ARight;
end;

function TEvaluator.Run(out AValue: Int64): TOrdinalStatus;
begin
  AValue := 0;
  FStatus := TOrdinalStatus.Unknown;
  if AtEnd then
    Exit(TOrdinalStatus.Unknown);
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
    Result := FStatus
  else if AtEnd then
    Result := TOrdinalStatus.Value
  else
    Result := TOrdinalStatus.Unknown;
  if Result <> TOrdinalStatus.Value then
    AValue := 0;
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
        Exit;
      Result := Arith('+', Result, Right);
    end
    else if IsSym('-') then
    begin
      Advance;
      Right := Term;
      if FFailed then
        Exit;
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

function TEvaluator.Term: Int64;
var
  Right: Int64;
  Operation: string;
begin
  Result := Factor;
  while not FFailed and (IsSym('*') or IsWord('div') or IsWord('mod') or IsWord('and') or IsWord('shl') or
    IsWord('shr')) do
  begin
    Operation := LowerCase(Current.Text);
    Advance;
    Right := Factor;
    if FFailed then
      Exit;
    if Operation = '*' then
      Result := Arith('*', Result, Right)
    else if (Operation = 'div') or (Operation = 'mod') then
    begin
      if Right = 0 then
      begin
        FailWith(TOrdinalStatus.DivisionByZero);
        Exit;
      end;
      if Operation = 'div' then
        Result := Result div Right
      else
        Result := Result mod Right;
    end
    else if Operation = 'and' then
      Result := Result and Right
    else if (Right < 0) or (Right > 63) then
      Fail
    else if Operation = 'shl' then
      Result := Result shl Right
    else
      Result := Result shr Right;
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
    Result := Primary;
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

function TEvaluator.TypeArgument(out AName: string): Boolean;
var
  Start: Integer;
begin
  // ( Typname ) ohne Punkt; danach steht der Zeiger hinter der Klammer.
  Result := False;
  AName := '';
  Start := FIndex;
  if not IsSym('(') then
    Exit;
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

function TEvaluator.CharValue(const AText: string; out AValue: Int64): Boolean;
var
  Digits: string;
begin
  // #13, #$0D
  Digits := Copy(AText, 2, MaxInt);
  Result := (Digits <> '') and TOrdinalConstants.TryNumber(Digits, AValue);
end;

function TEvaluator.StringValue(const AText: string; out AValue: Int64): Boolean;
var
  Inner: string;
begin
  // Genau ein Zeichen: 'a' bzw. '''' für das Hochkomma.
  Result := False;
  AValue := 0;
  if (Length(AText) < 3) or (AText[1] <> '''') or (AText[Length(AText)] <> '''') then
    Exit;
  Inner := StringReplace(Copy(AText, 2, Length(AText) - 2), '''''', '''', [rfReplaceAll]);
  if Length(Inner) <> 1 then
    Exit;
  AValue := Ord(Inner[1]);
  Result := True;
end;

function TEvaluator.Primary: Int64;
var
  Token: TPascalToken;
  Names: TArray<string>;
  Start: Integer;
  Name, TypeName: string;
  Lowest, Highest: Int64;
  HighKnown: Boolean;
  Size: Integer;
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
      Exit;
    end;
    Token := Current;
    case Token.Kind of
      TPascalTokenKind.Number:
        begin
          if not TOrdinalConstants.TryNumber(Token.Text, Result) then
            Fail;
          Advance;
        end;
      TPascalTokenKind.CharLiteral:
        begin
          if not CharValue(Token.Text, Result) then
            Fail;
          Advance;
          // 'a'#13 und #13#10 sind Strings, keine Zeichen.
          if not AtEnd and (Current.Kind in [TPascalTokenKind.CharLiteral, TPascalTokenKind.StringLiteral]) then
            Fail;
        end;
      TPascalTokenKind.StringLiteral:
        begin
          if not StringValue(Token.Text, Result) then
            Fail;
          Advance;
          if not AtEnd and (Current.Kind in [TPascalTokenKind.CharLiteral, TPascalTokenKind.StringLiteral]) then
            Fail;
        end;
      TPascalTokenKind.Symbol:
        if Token.IsSymbol('(') then
        begin
          Advance;
          Result := Expression;
          if not IsSym(')') then
            Fail
          else
            Advance;
        end
        else
          Fail;
      TPascalTokenKind.Identifier, TPascalTokenKind.Keyword:
        begin
          Start := FIndex;
          Name := Token.Text;
          Advance;
          if IsSym('(') then
          begin
            // SizeOf, High und Low eines Typs fester Größe.
            if (SameText(Name, 'SizeOf') or SameText(Name, 'High') or SameText(Name, 'Low')) and
              TypeArgument(TypeName) then
            begin
              if not TOrdinalConstants.FixedType(TypeName, Lowest, Highest, HighKnown, Size) or
                (SameText(Name, 'High') and not HighKnown) then
                Fail
              else if SameText(Name, 'SizeOf') then
                Result := Size
              else if SameText(Name, 'High') then
                Result := Highest
              else
                Result := Lowest;
              Exit;
            end;
            // Ord, Chr, Succ, Pred und Typumwandlungen.
            if SameText(Name, 'Succ') then
              Result := Arguments + 1
            else if SameText(Name, 'Pred') then
              Result := Arguments - 1
            else if SameText(Name, 'Chr') or (IndexText(Name, OrdinalCasts) >= 0) then
              Result := Arguments
            else
              Fail;
            Exit;
          end;
          Names := [Name];
          while IsSym('.') do
          begin
            Advance;
            if AtEnd or not (Current.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
            begin
              Fail;
              Exit;
            end;
            Names := Names + [Current.Text];
            Advance;
          end;
          if Assigned(FLookup) and FLookup(Names, Start, Result) then
            Exit;
          if (Length(Names) = 1) and SameText(Name, 'True') then
            Result := 1
          else if (Length(Names) = 1) and SameText(Name, 'False') then
            Result := 0
          // Konstanten aus System mit festem Wert auf allen Plattformen (#1083).
          else if (Length(Names) = 1) and (SameText(Name, 'MaxInt') or SameText(Name, 'MaxLongint')) then
            Result := 2147483647
          else
            Fail;
        end;
    else
      Fail;
    end;
  finally
    Dec(FDepth);
  end;
end;

{ TOrdinalConstants }

class function TOrdinalConstants.FixedType(const ATypeName: string; out ALow, AHigh: Int64;
  out AHighKnown: Boolean; out ASize: Integer): Boolean;

  procedure Put(ALowValue, AHighValue: Int64; ASizeValue: Integer);
  begin
    ALow := ALowValue;
    AHigh := AHighValue;
    ASize := ASizeValue;
  end;

var
  Name: string;
begin
  Result := True;
  AHighKnown := True;
  Name := LowerCase(ATypeName);
  if StartsText('system.', Name) then
    Name := Copy(Name, Length('system.') + 1, MaxInt);
  if (Name = 'byte') or (Name = 'uint8') or (Name = 'ansichar') then
    Put(0, 255, 1)
  else if (Name = 'shortint') or (Name = 'int8') then
    Put(-128, 127, 1)
  else if (Name = 'word') or (Name = 'uint16') or (Name = 'char') or (Name = 'widechar') then
    Put(0, 65535, 2)
  else if (Name = 'smallint') or (Name = 'int16') then
    Put(-32768, 32767, 2)
  else if (Name = 'integer') or (Name = 'int32') or (Name = 'fixedint') then
    Put(-2147483648, 2147483647, 4)
  else if (Name = 'cardinal') or (Name = 'uint32') or (Name = 'dword') or (Name = 'fixeduint') then
    Put(0, 4294967295, 4)
  else if Name = 'int64' then
    Put(Low(Int64), High(Int64), 8)
  else if Name = 'uint64' then
  begin
    Put(0, 0, 8);
    AHighKnown := False;
  end
  else if (Name = 'boolean') or (Name = 'bytebool') then
    Put(0, 1, 1)
  else if Name = 'single' then
    Put(0, 0, 4)
  else if (Name = 'double') or (Name = 'currency') or (Name = 'comp') then
    Put(0, 0, 8)
  else
  begin
    Put(0, 0, 0);
    AHighKnown := False;
    Result := False;
  end;
  // Gleitkomma hat nur eine Größe, keinen ordinalen Bereich.
  if (Name = 'single') or (Name = 'double') or (Name = 'currency') or (Name = 'comp') then
    AHighKnown := False;
end;

class function TOrdinalConstants.TryNumber(const AText: string; out AValue: Int64): Boolean;
var
  Base, Digit, Index: Integer;
  Text: string;
  Value: UInt64;
begin
  AValue := 0;
  Result := False;
  Text := StringReplace(AText, '_', '', [rfReplaceAll]);
  if Text = '' then
    Exit;
  Base := 10;
  case Text[1] of
    '$':
      Base := 16;
    '%':
      Base := 2;
    '&':
      Base := 8;
  end;
  if Base <> 10 then
    Text := Copy(Text, 2, MaxInt);
  if Text = '' then
    Exit;
  Value := 0;
  for Index := 1 to Length(Text) do
  begin
    case Text[Index] of
      '0'..'9':
        Digit := Ord(Text[Index]) - Ord('0');
      'a'..'f':
        Digit := Ord(Text[Index]) - Ord('a') + 10;
      'A'..'F':
        Digit := Ord(Text[Index]) - Ord('A') + 10;
    else
      Exit;
    end;
    if Digit >= Base then
      Exit;
    // Mehr als Int64 fasst: nicht auswertbar.
    if Value > (UInt64(High(Int64)) - UInt64(Digit)) div UInt64(Base) then
      Exit;
    Value := Value * UInt64(Base) + UInt64(Digit);
  end;
  AValue := Int64(Value);
  Result := True;
end;

class function TOrdinalConstants.Check(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  const ALookup: TOrdinalNameLookup; out AValue: Int64): TOrdinalStatus;
var
  Evaluator: TEvaluator;
begin
  AValue := 0;
  if (AFirst < 0) or (AFirst > ALast) then
    Exit(TOrdinalStatus.Unknown);
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
