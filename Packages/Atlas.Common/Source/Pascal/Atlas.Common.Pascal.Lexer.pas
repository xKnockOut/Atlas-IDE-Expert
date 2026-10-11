unit Atlas.Common.Pascal.Lexer;

// Lexer für Object Pascal. Zerlegt Quelltext in Token; Leerraum und
// Zeilenumbrüche erzeugen keine Token.
//
// Der Lexer bricht nie ab: Unvollständige Strings, Kommentare und Direktiven
// werden als Token mit Terminated = False geliefert, unbekannte Zeichen als
// Unknown. So bleibt er im Editor auch bei halb getipptem Code brauchbar.

interface

uses
  Atlas.Common.Pascal.Contract;

type
  TPascalLexer = record
  public
    /// <summary>Alle Token des Textes in Reihenfolge.</summary>
    class function Tokenize(const AText: string): TArray<TPascalToken>; static;
    /// <summary>True für reservierte Wörter (ohne Groß-/Kleinschreibung).</summary>
    class function IsReservedWord(const AWord: string): Boolean; static;
    /// <summary>Alle reservierten Wörter in Kleinbuchstaben (#187).</summary>
    class function ReservedWordList: TArray<string>; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract;

const
  // Reservierte Wörter von Delphi. Direktiven wie override, virtual oder out
  // sind kontextabhängig und bleiben Bezeichner.
  ReservedWords: array[0..63] of string = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except',
    'exports', 'file', 'finalization', 'finally', 'for', 'function', 'goto', 'if',
    'implementation', 'in', 'inherited', 'initialization', 'inline', 'interface',
    'is', 'label', 'library', 'mod', 'nil', 'not', 'object', 'of', 'or', 'packed',
    'procedure', 'program', 'property', 'raise', 'record', 'repeat',
    'resourcestring', 'set', 'shl', 'shr', 'string', 'then', 'threadvar', 'to',
    'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'with', 'xor');

  TwoCharSymbols: array[0..6] of string = (':=', '..', '<=', '>=', '<>', '(.', '.)');
  OneCharSymbols = '+-*/=<>[].,():;^@';

var
  ReservedWordSet: TDictionary<string, Boolean>;

type
  TScanner = record
  private
    FText: string;
    FLength: Integer;
    FPos: Integer;
    function Peek(ADelta: Integer = 0): Char; inline;
    function AtLineBreak: Boolean; inline;
    procedure SkipToLineEnd;
    function ScanUntil(const ACloser: string): Boolean;
    function ScanString: Boolean;
    function TryScanMultilineString(out ATerminated: Boolean): Boolean;
    procedure ScanDigits(const AAllowed: TSysCharSet);
    procedure ScanDecimal;
    procedure ScanIdentifier;
    function ScanSymbol: Boolean;
  public
    procedure Init(const AText: string);
    /// <summary>Liest das nächste Token ohne Positionen; False am Ende.</summary>
    function Next(out AToken: TPascalToken; out AEndOffset: Integer): Boolean;
  end;

function IsIdentifierStart(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']) or (Ord(C) >= 128);
end;

function IsIdentifierPart(C: Char): Boolean; inline;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(C) >= 128);
end;

{ TScanner }

procedure TScanner.Init(const AText: string);
begin
  FText := AText;
  FLength := Length(AText);
  FPos := 0;
end;

function TScanner.Peek(ADelta: Integer): Char;
begin
  // FPos zählt ab 0, der string ab 1.
  if FPos + ADelta < FLength then
    Result := FText[FPos + ADelta + 1]
  else
    Result := #0;
end;

function TScanner.AtLineBreak: Boolean;
begin
  Result := CharInSet(Peek, [#13, #10]);
end;

procedure TScanner.SkipToLineEnd;
begin
  while (FPos < FLength) and not AtLineBreak do
    Inc(FPos);
end;

function TScanner.ScanUntil(const ACloser: string): Boolean;
var
  Found: Integer;
begin
  // Pos arbeitet ab 1; FPos + 1 ist das aktuelle Zeichen.
  Found := Pos(ACloser, FText, FPos + 1);
  Result := Found > 0;
  if Result then
    FPos := Found - 1 + Length(ACloser)
  else
    FPos := FLength;
end;

function TScanner.ScanString: Boolean;
begin
  // Steht auf dem öffnenden Hochkomma. '' im String ist ein Hochkomma.
  Inc(FPos);
  while FPos < FLength do
  begin
    if Peek = '''' then
    begin
      if Peek(1) = '''' then
        Inc(FPos, 2)
      else
      begin
        Inc(FPos);
        Exit(True);
      end;
    end
    else if AtLineBreak then
      Exit(False)
    else
      Inc(FPos);
  end;
  Result := False;
end;

function TScanner.TryScanMultilineString(out ATerminated: Boolean): Boolean;
var
  QuoteCount: Integer;
  Scan: Integer;
  LineScan: Integer;
  Count: Integer;
begin
  // Mehrzeiliger String (Delphi 12): eine ungerade Zahl (>= 3) Hochkommas,
  // danach nur Leerraum bis zum Zeilenende. Er endet an der ersten Zeile, die
  // nach Leerraum mit genauso vielen Hochkommas beginnt.
  ATerminated := False;
  QuoteCount := 0;
  while Peek(QuoteCount) = '''' do
    Inc(QuoteCount);
  if (QuoteCount < 3) or not Odd(QuoteCount) then
    Exit(False);
  Scan := QuoteCount;
  while CharInSet(Peek(Scan), [' ', #9]) do
    Inc(Scan);
  if not CharInSet(Peek(Scan), [#13, #10]) then
    Exit(False);

  Result := True;
  Inc(FPos, Scan);
  while FPos < FLength do
  begin
    // Zeilenumbruch überspringen, dann Leerraum am Zeilenanfang.
    if Peek = #13 then
      Inc(FPos);
    if Peek = #10 then
      Inc(FPos);
    LineScan := 0;
    while CharInSet(Peek(LineScan), [' ', #9]) do
      Inc(LineScan);
    Count := 0;
    while Peek(LineScan + Count) = '''' do
      Inc(Count);
    if Count = QuoteCount then
    begin
      Inc(FPos, LineScan + Count);
      ATerminated := True;
      Exit;
    end;
    SkipToLineEnd;
  end;
end;

procedure TScanner.ScanDigits(const AAllowed: TSysCharSet);
begin
  while CharInSet(Peek, AAllowed) do
    Inc(FPos);
end;

procedure TScanner.ScanDecimal;
begin
  ScanDigits(['0'..'9', '_']);
  // Nachkommastellen, aber nicht bei 1..2 (Bereich).
  if (Peek = '.') and CharInSet(Peek(1), ['0'..'9']) then
  begin
    Inc(FPos);
    ScanDigits(['0'..'9', '_']);
  end;
  if CharInSet(Peek, ['e', 'E']) and
    (CharInSet(Peek(1), ['0'..'9']) or (CharInSet(Peek(1), ['+', '-']) and CharInSet(Peek(2), ['0'..'9']))) then
  begin
    Inc(FPos, 2);
    ScanDigits(['0'..'9']);
  end;
end;

procedure TScanner.ScanIdentifier;
begin
  while IsIdentifierPart(Peek) do
    Inc(FPos);
end;

function TScanner.ScanSymbol: Boolean;
var
  Pair: string;
  Symbol: string;
begin
  Pair := Peek + Peek(1);
  for Symbol in TwoCharSymbols do
    if Pair = Symbol then
    begin
      Inc(FPos, 2);
      Exit(True);
    end;
  Result := Pos(Peek, OneCharSymbols) > 0;
  if Result then
    Inc(FPos);
end;

function TScanner.Next(out AToken: TPascalToken; out AEndOffset: Integer): Boolean;
var
  Start: Integer;
  C: Char;
  Terminated: Boolean;
  Kind: TPascalTokenKind;
begin
  while (FPos < FLength) and (Peek <= ' ') do
    Inc(FPos);
  if FPos >= FLength then
    Exit(False);

  Start := FPos;
  C := Peek;
  Terminated := True;
  Kind := TPascalTokenKind.Unknown;

  if (C = '/') and (Peek(1) = '/') then
  begin
    Kind := TPascalTokenKind.Comment;
    SkipToLineEnd;
  end
  else if C = '{' then
  begin
    if Peek(1) = '$' then
      Kind := TPascalTokenKind.Directive
    else
      Kind := TPascalTokenKind.Comment;
    Terminated := ScanUntil('}');
  end
  else if (C = '(') and (Peek(1) = '*') then
  begin
    if Peek(2) = '$' then
      Kind := TPascalTokenKind.Directive
    else
      Kind := TPascalTokenKind.Comment;
    Inc(FPos, 2);
    Terminated := ScanUntil('*)');
  end
  else if C = '''' then
  begin
    Kind := TPascalTokenKind.StringLiteral;
    if not TryScanMultilineString(Terminated) then
      Terminated := ScanString;
  end
  else if C = '#' then
  begin
    Kind := TPascalTokenKind.CharLiteral;
    Inc(FPos);
    if Peek = '$' then
    begin
      Inc(FPos);
      ScanDigits(['0'..'9', 'A'..'F', 'a'..'f', '_']);
    end
    else
      ScanDigits(['0'..'9', '_']);
  end
  else if C = '$' then
  begin
    Kind := TPascalTokenKind.Number;
    Inc(FPos);
    ScanDigits(['0'..'9', 'A'..'F', 'a'..'f', '_']);
  end
  else if (C = '%') and CharInSet(Peek(1), ['0', '1']) then
  begin
    Kind := TPascalTokenKind.Number;
    Inc(FPos);
    ScanDigits(['0', '1', '_']);
  end
  else if CharInSet(C, ['0'..'9']) then
  begin
    Kind := TPascalTokenKind.Number;
    ScanDecimal;
  end
  else if (C = '&') and IsIdentifierStart(Peek(1)) then
  begin
    // &begin: reserviertes Wort als Bezeichner.
    Kind := TPascalTokenKind.Identifier;
    Inc(FPos);
    ScanIdentifier;
  end
  else if (C = '&') and CharInSet(Peek(1), ['0'..'7']) then
  begin
    // &17: Oktalzahl.
    Kind := TPascalTokenKind.Number;
    Inc(FPos);
    ScanDigits(['0'..'7', '_']);
  end
  else if IsIdentifierStart(C) then
  begin
    ScanIdentifier;
    if TPascalLexer.IsReservedWord(Copy(FText, Start + 1, FPos - Start)) then
      Kind := TPascalTokenKind.Keyword
    else
      Kind := TPascalTokenKind.Identifier;
  end
  else if ScanSymbol then
    Kind := TPascalTokenKind.Symbol
  else
    Inc(FPos);

  AToken := Default(TPascalToken);
  AToken.Kind := Kind;
  AToken.Text := Copy(FText, Start + 1, FPos - Start);
  AToken.Offset := Start;
  AToken.Terminated := Terminated;
  AEndOffset := FPos;
  Result := True;
end;

// Rechnet Offsets in Positionen um. Die Offsets müssen aufsteigend kommen.
type
  TPositionTracker = record
  private
    FText: string;
    FOffset: Integer;
    FLine: Integer;
    FLineStart: Integer;
  public
    procedure Init(const AText: string);
    function PositionAt(AOffset: Integer): TTextPosition;
  end;

procedure TPositionTracker.Init(const AText: string);
begin
  FText := AText;
  FOffset := 0;
  FLine := 0;
  FLineStart := 0;
end;

function TPositionTracker.PositionAt(AOffset: Integer): TTextPosition;
var
  C: Char;
begin
  while FOffset < AOffset do
  begin
    C := FText[FOffset + 1];
    if C = #13 then
    begin
      Inc(FLine);
      FLineStart := FOffset + 1;
    end
    else if C = #10 then
    begin
      // LF nach CR gehört zum selben Zeilenumbruch.
      if not ((FOffset > 0) and (FText[FOffset] = #13)) then
        Inc(FLine);
      FLineStart := FOffset + 1;
    end;
    Inc(FOffset);
  end;
  Result := TTextPosition.Create(FLine, AOffset - FLineStart);
end;

{ TPascalLexer }

class function TPascalLexer.IsReservedWord(const AWord: string): Boolean;
begin
  Result := ReservedWordSet.ContainsKey(LowerCase(AWord));
end;

class function TPascalLexer.ReservedWordList: TArray<string>;
var
  Index: Integer;
begin
  SetLength(Result, Length(ReservedWords));
  for Index := 0 to High(ReservedWords) do
    Result[Index] := ReservedWords[Index];
end;

class function TPascalLexer.Tokenize(const AText: string): TArray<TPascalToken>;
var
  Scanner: TScanner;
  Tracker: TPositionTracker;
  Tokens: TList<TPascalToken>;
  Token: TPascalToken;
  EndOffset: Integer;
begin
  Scanner.Init(AText);
  Tracker.Init(AText);
  Tokens := TList<TPascalToken>.Create;
  try
    while Scanner.Next(Token, EndOffset) do
    begin
      Token.StartPos := Tracker.PositionAt(Token.Offset);
      Token.EndPos := Tracker.PositionAt(EndOffset);
      Tokens.Add(Token);
    end;
    Result := Tokens.ToArray;
  finally
    Tokens.Free;
  end;
end;

procedure InitReservedWords;
var
  Word: string;
begin
  ReservedWordSet := TDictionary<string, Boolean>.Create;
  for Word in ReservedWords do
    ReservedWordSet.Add(Word, True);
end;

initialization
  InitReservedWords;

finalization
  ReservedWordSet.Free;

end.
