unit Atlas.Common.Semantics.OrdinalConstants;

// Werte ordinaler Konstantenausdrücke aus Token (#983): Ganzzahlen (dezimal,
// $hex, %binär, &oktal), Zeichen ('a', #13, #$0D), True und False, Klammern,
// die Operatoren + - * div mod and or xor not shl shr sowie Ord, Chr, Succ,
// Pred, Umwandlungen in ganzzahlige und Zeichentypen sowie Low und High der
// eingebauten ordinalen Typen fester Größe und MaxInt/MaxLongint (#1083).
// Namen (Konstanten, Aufzählungswerte) löst der Aufrufer über ALookup auf. Alles andere, auch
// Gleitkomma, Strings und Überläufe, gilt als nicht auswertbar.

interface

uses
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Wert der Namenskette ANames (A.B.C), deren erstes Token in den ausgewerteten Token an
  /// ATokenIndex steht; False, wenn der Name keinen bekannten ordinalen Wert hat.</summary>
  TOrdinalNameLookup = reference to function(const ANames: TArray<string>; ATokenIndex: Integer;
    out AValue: Int64): Boolean;

  TOrdinalConstants = record
  public
    /// <summary>Wert der Token AFirst..ALast (Kommentare und Direktiven zählen nicht); False, wenn der
    /// Ausdruck nicht vollständig auswertbar ist. ALookup darf nil sein.</summary>
    class function Evaluate(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
      const ALookup: TOrdinalNameLookup; out AValue: Int64): Boolean; overload; static;
    /// <summary>Wie oben über den ganzen Text AText (z. B. "5 + Max").</summary>
    class function Evaluate(const AText: string; const ALookup: TOrdinalNameLookup;
      out AValue: Int64): Boolean; overload; static;
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
  // Low und High eingebauter Typen fester Größe (NativeInt hängt von der Plattform ab und fehlt).
  RangeTypes: array[0..14] of string = ('Byte', 'ShortInt', 'Word', 'SmallInt', 'Integer', 'LongInt', 'FixedInt',
    'Cardinal', 'LongWord', 'FixedUInt', 'Int64', 'Char', 'WideChar', 'AnsiChar', 'Boolean');
  RangeLows: array[0..14] of Int64 = (0, -128, 0, -32768, -2147483648, -2147483648, -2147483648, 0, 0, 0,
    Low(Int64), 0, 0, 0, 0);
  RangeHighs: array[0..14] of Int64 = (255, 127, 65535, 32767, 2147483647, 2147483647, 2147483647, 4294967295,
    4294967295, 4294967295, High(Int64), 65535, 65535, 255, 1);
  // Tiefe der Klammern und Aufrufe, damit ein Ausdruck aus fremdem Quelltext den Stapel nicht sprengt.
  MaxDepth = 64;

type
  TEvaluator = class
  private
    FTokens: TArray<TPascalToken>;
    FIndex: Integer;
    FLast: Integer;
    FLookup: TOrdinalNameLookup;
    FFailed: Boolean;
    FDepth: Integer;
    procedure SkipTrivia;
    function AtEnd: Boolean;
    function Current: TPascalToken;
    procedure Advance;
    function IsSym(const ASymbol: string): Boolean;
    function IsWord(const AWord: string): Boolean;
    procedure Fail;
    function Expression: Int64;
    function Term: Int64;
    function Factor: Int64;
    function Primary: Int64;
    function CharValue(const AText: string; out AValue: Int64): Boolean;
    function StringValue(const AText: string; out AValue: Int64): Boolean;
    function Arguments: Int64;
    function Bound(AHigh: Boolean): Int64;
  public
    constructor Create(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
      const ALookup: TOrdinalNameLookup);
    function Run(out AValue: Int64): Boolean;
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

function TEvaluator.Run(out AValue: Int64): Boolean;
begin
  AValue := 0;
  if AtEnd then
    Exit(False);
  try
    AValue := Expression;
  except
    // Überlauf und Division durch null: nicht auswertbar.
    on EIntOverflow do
      FFailed := True;
    on EDivByZero do
      FFailed := True;
  end;
  Result := not FFailed and AtEnd;
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
      Result := Result + Right;
    end
    else if IsSym('-') then
    begin
      Advance;
      Right := Term;
      Result := Result - Right;
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
      Result := Result * Right
    else if (Operation = 'div') or (Operation = 'mod') then
    begin
      if Right = 0 then
      begin
        Fail;
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

function TEvaluator.Bound(AHigh: Boolean): Int64;
var
  Index: Integer;
begin
  // Low(Typ) bzw. High(Typ) für eingebaute Typen; alles andere (Variablen, Arrays) ist nicht auswertbar.
  Result := 0;
  Advance; // (
  Index := -1;
  if not AtEnd and (Current.Kind = TPascalTokenKind.Identifier) then
    Index := IndexText(Current.Text, RangeTypes);
  if Index < 0 then
  begin
    Fail;
    Exit;
  end;
  Advance;
  if not IsSym(')') then
  begin
    Fail;
    Exit;
  end;
  Advance;
  if AHigh then
    Result := RangeHighs[Index]
  else
    Result := RangeLows[Index];
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
  Name: string;
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
            // Ord, Chr, Succ, Pred und Typumwandlungen.
            if SameText(Name, 'High') or SameText(Name, 'Low') then
              Result := Bound(SameText(Name, 'High'))
            else if SameText(Name, 'Succ') then
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

class function TOrdinalConstants.Evaluate(const ATokens: TArray<TPascalToken>; AFirst, ALast: Integer;
  const ALookup: TOrdinalNameLookup; out AValue: Int64): Boolean;
var
  Evaluator: TEvaluator;
begin
  AValue := 0;
  if (AFirst < 0) or (AFirst > ALast) then
    Exit(False);
  Evaluator := TEvaluator.Create(ATokens, AFirst, ALast, ALookup);
  try
    Result := Evaluator.Run(AValue);
  finally
    Evaluator.Free;
  end;
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
