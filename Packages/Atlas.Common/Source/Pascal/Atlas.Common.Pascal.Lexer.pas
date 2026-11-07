unit Atlas.Common.Pascal.Lexer;

// Lexer für Object Pascal. Zerlegt Quelltext in Token; Leerraum und
// Zeilenumbrüche erzeugen keine Token.
//
// Der Lexer bricht nie ab: Unvollständige Strings, Kommentare und Direktiven
// werden als Token mit Terminated = False geliefert, ebenso eine Zahl mit
// leerem Exponenten wie 1.5e (E2053, #1382), unbekannte Zeichen als
// Unknown. So bleibt er im Editor auch bei halb getipptem Code brauchbar.

interface

uses
  System.SysUtils,
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
    /// <summary>Name einer Direktive in Großbuchstaben, z. B. IFDEF für {$ifdef X}; '' ohne Direktive.</summary>
    class function DirectiveName(const AText: string): string; static;
    /// <summary>Name ohne das Escape-Zeichen, je Teil eines qualifizierten Namens: &amp;begin → begin,
    /// &amp;&amp;op_Equality → &amp;op_Equality, TFoo.&amp;Type → TFoo.Type (#1137).</summary>
    class function PlainName(const AName: string): string; static;
    /// <summary>Gegenstück zu PlainName: der Name, wie er im Quelltext stehen muss. Reservierte Wörter und
    /// Namen, die mit &amp; beginnen, bekommen ein &amp; davor (begin → &amp;begin, &amp;op_Equality →
    /// &amp;&amp;op_Equality).</summary>
    class function SourceName(const AName: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract;

const
  // Reservierte Wörter von Delphi. Direktiven wie override, virtual oder out
  // sind kontextabhängig und bleiben Bezeichner.
  cReservedWords: array[0..63] of string = (
    'and', 'array', 'as', 'asm', 'begin', 'case', 'class', 'const', 'constructor',
    'destructor', 'dispinterface', 'div', 'do', 'downto', 'else', 'end', 'except',
    'exports', 'file', 'finalization', 'finally', 'for', 'function', 'goto', 'if',
    'implementation', 'in', 'inherited', 'initialization', 'inline', 'interface',
    'is', 'label', 'library', 'mod', 'nil', 'not', 'object', 'of', 'or', 'packed',
    'procedure', 'program', 'property', 'raise', 'record', 'repeat',
    'resourcestring', 'set', 'shl', 'shr', 'string', 'then', 'threadvar', 'to',
    'try', 'type', 'unit', 'until', 'uses', 'var', 'while', 'with', 'xor');

  cTwoCharSymbols: array[0..6] of string = (':=', '..', '<=', '>=', '<>', '(.', '.)');
  cOneCharSymbols = '+-*/=<>[].,():;^@';

var
  ReservedWordSet: TDictionary<string, Boolean>;

type
  TScanner = record
  private
    FText: string;
    FLength: Integer;
    FPos: Integer;
    function Peek(ADelta: Integer): Char; overload; inline;
    // Wie oben mit ADelta = 0.
    function Peek: Char; overload; inline;
    function AtLineBreak: Boolean; inline;
    procedure SkipToLineEnd;
    function ScanUntil(const ACloser: string): Boolean;
    function ScanString: Boolean;
    function TryScanMultilineString(out ATerminated: Boolean): Boolean;
    /// <summary>Anzahl Hochkommas ab Peek(ADelta).</summary>
    function QuoteRun(ADelta: Integer): Integer;
    /// <summary>Anzahl Leerzeichen und Tabs ab Peek(ADelta).</summary>
    function BlankRun(ADelta: Integer): Integer;
    /// <summary>Kommentar oder Direktive ab FPos; False bei anderem Zeichen.</summary>
    function ScanComment(out AKind: TPascalTokenKind; out ATerminated: Boolean): Boolean;
    /// <summary>String, Zeichencode oder Zahl ab FPos; False bei anderem Zeichen.</summary>
    function ScanLiteral(out AKind: TPascalTokenKind; out ATerminated: Boolean): Boolean;
    /// <summary>&amp;begin, &amp;&amp;op_Equality und Oktalzahlen &amp;17; False bei anderem Zeichen.</summary>
    function ScanAmpersand(out AKind: TPascalTokenKind): Boolean;
    /// <summary>Bezeichner oder reserviertes Wort ab AStart (FPos = AStart).</summary>
    function ScanWord(AStart: Integer): TPascalTokenKind;
    /// <summary>Bezeichner, Symbol oder unbekanntes Zeichen ab AStart (FPos = AStart).</summary>
    function ScanOther(AStart: Integer): TPascalTokenKind;
    procedure ScanDigits(const AAllowed: TSysCharSet);
    /// <summary>False bei einem Exponenten ohne Ziffern (1.5e;): Delphi meldet E2053.</summary>
    function ScanDecimal: Boolean;
    procedure ScanIdentifier;
    function ScanSymbol: Boolean;
  public
    procedure Init(const AText: string);
    /// <summary>Liest das nächste Token ohne Positionen; False am Ende.</summary>
    function Next(out AToken: TPascalToken; out AEndOffset: Integer): Boolean;
  end;

function IsIdentifierStart(AC: Char): Boolean; inline;
begin
  Result := CharInSet(AC, ['A'..'Z', 'a'..'z', '_']) or (Ord(AC) >= 128);
end;

function IsIdentifierPart(AC: Char): Boolean; inline;
begin
  Result := CharInSet(AC, ['A'..'Z', 'a'..'z', '0'..'9', '_']) or (Ord(AC) >= 128);
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
  begin
    Result := FText[FPos + ADelta + 1];
  end
  else
  begin
    Result := #0;
  end;
end;

function TScanner.Peek: Char;
begin
  Result := Peek(0);
end;

function TScanner.AtLineBreak: Boolean;
begin
  Result := CharInSet(Peek, [#13, #10]);
end;

procedure TScanner.SkipToLineEnd;
begin
  while (FPos < FLength) and not AtLineBreak do
  begin
    Inc(FPos);
  end;
end;

function TScanner.ScanUntil(const ACloser: string): Boolean;
var
  mFound: Integer;
begin
  // Pos arbeitet ab 1; FPos + 1 ist das aktuelle Zeichen.
  mFound := Pos(ACloser, FText, FPos + 1);
  Result := mFound > 0;
  if Result then
  begin
    FPos := mFound - 1 + Length(ACloser);
  end
  else
  begin
    FPos := FLength;
  end;
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
      begin
        Inc(FPos, 2);
      end
      else
      begin
        Inc(FPos);
        Exit(True);
      end;
    end
    else if AtLineBreak then
    begin
      Exit(False);
    end
    else
    begin
      Inc(FPos);
    end;
  end;
  Result := False;
end;

function TScanner.QuoteRun(ADelta: Integer): Integer;
begin
  Result := 0;
  while Peek(ADelta + Result) = '''' do
  begin
    Inc(Result);
  end;
end;

function TScanner.BlankRun(ADelta: Integer): Integer;
begin
  Result := 0;
  while CharInSet(Peek(ADelta + Result), [' ', #9]) do
  begin
    Inc(Result);
  end;
end;

function TScanner.TryScanMultilineString(out ATerminated: Boolean): Boolean;
var
  mQuoteCount: Integer;
  mScan: Integer;
  mLineScan: Integer;
begin
  // Mehrzeiliger String (Delphi 12): eine ungerade Zahl (>= 3) Hochkommas,
  // danach nur Leerraum bis zum Zeilenende. Er endet an der ersten Zeile, die
  // nach Leerraum mit genauso vielen Hochkommas beginnt.
  ATerminated := False;
  mQuoteCount := QuoteRun(0);
  if (mQuoteCount < 3) or not Odd(mQuoteCount) then
  begin
    Exit(False);
  end;
  mScan := mQuoteCount + BlankRun(mQuoteCount);
  if not CharInSet(Peek(mScan), [#13, #10]) then
  begin
    Exit(False);
  end;

  Result := True;
  Inc(FPos, mScan);
  while not ATerminated and (FPos < FLength) do
  begin
    // Zeilenumbruch überspringen, dann Leerraum am Zeilenanfang.
    if Peek = #13 then
    begin
      Inc(FPos);
    end;
    if Peek = #10 then
    begin
      Inc(FPos);
    end;
    mLineScan := BlankRun(0);
    ATerminated := QuoteRun(mLineScan) = mQuoteCount;
    if ATerminated then
    begin
      Inc(FPos, mLineScan + mQuoteCount);
    end
    else
    begin
      SkipToLineEnd;
    end;
  end;
end;

procedure TScanner.ScanDigits(const AAllowed: TSysCharSet);
begin
  while CharInSet(Peek, AAllowed) do
  begin
    Inc(FPos);
  end;
end;

function TScanner.ScanDecimal: Boolean;
begin
  Result := True;
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
  end
  else if CharInSet(Peek, ['e', 'E']) and not IsIdentifierPart(Peek(1)) and not CharInSet(Peek(1), ['+', '-']) then
  begin
    // 1.5e: Delphi liest das e als Teil der Zahl. Mit Buchstaben dahinter (1Eh im asm-Block) bleibt es beim
    // Bezeichner.
    Inc(FPos);
    Result := False;
  end;
end;

procedure TScanner.ScanIdentifier;
begin
  while IsIdentifierPart(Peek) do
  begin
    Inc(FPos);
  end;
end;

function TScanner.ScanSymbol: Boolean;
var
  mPair: string;
  mSymbol: string;
begin
  mPair := Peek + Peek(1);
  for mSymbol in cTwoCharSymbols do
  begin
    if mPair = mSymbol then
    begin
      Inc(FPos, 2);
      Exit(True);
    end;
  end;
  Result := Pos(Peek, cOneCharSymbols) > 0;
  if Result then
  begin
    Inc(FPos);
  end;
end;

function TScanner.ScanComment(out AKind: TPascalTokenKind; out ATerminated: Boolean): Boolean;
begin
  Result := True;
  ATerminated := True;
  AKind := TPascalTokenKind.Comment;
  if (Peek = '/') and (Peek(1) = '/') then
  begin
    SkipToLineEnd;
  end
  else if Peek = '{' then
  begin
    if Peek(1) = '$' then
    begin
      AKind := TPascalTokenKind.Directive;
    end;
    ATerminated := ScanUntil('}');
  end
  else if (Peek = '(') and (Peek(1) = '*') then
  begin
    if Peek(2) = '$' then
    begin
      AKind := TPascalTokenKind.Directive;
    end;
    Inc(FPos, 2);
    ATerminated := ScanUntil('*)');
  end
  else
  begin
    Result := False;
  end;
end;

function TScanner.ScanLiteral(out AKind: TPascalTokenKind; out ATerminated: Boolean): Boolean;
var
  C: Char;
begin
  Result := True;
  ATerminated := True;
  AKind := TPascalTokenKind.Number;
  C := Peek;
  if C = '''' then
  begin
    AKind := TPascalTokenKind.StringLiteral;
    if not TryScanMultilineString(ATerminated) then
    begin
      ATerminated := ScanString;
    end;
  end
  else if C = '#' then
  begin
    AKind := TPascalTokenKind.CharLiteral;
    Inc(FPos);
    if Peek = '$' then
    begin
      Inc(FPos);
      ScanDigits(['0'..'9', 'A'..'F', 'a'..'f', '_']);
    end
    else
    begin
      ScanDigits(['0'..'9', '_']);
    end;
  end
  else if C = '$' then
  begin
    Inc(FPos);
    ScanDigits(['0'..'9', 'A'..'F', 'a'..'f', '_']);
  end
  else if (C = '%') and CharInSet(Peek(1), ['0', '1', '_']) then
  begin
    Inc(FPos);
    ScanDigits(['0', '1', '_']);
  end
  else if CharInSet(C, ['0'..'9']) then
  begin
    ATerminated := ScanDecimal;
  end
  else
  begin
    Result := False;
  end;
end;

function TScanner.ScanAmpersand(out AKind: TPascalTokenKind): Boolean;
begin
  Result := Peek = '&';
  AKind := TPascalTokenKind.Identifier;
  if not Result then
  begin
    Exit;
  end;
  if IsIdentifierStart(Peek(1)) then
  begin
    // &begin: reserviertes Wort als Bezeichner.
    Inc(FPos);
    ScanIdentifier;
  end
  else if (Peek(1) = '&') and IsIdentifierStart(Peek(2)) then
  begin
    // &&op_Equality: Bezeichner &op_Equality, so schreibt Spring4D die
    // Operator-Methoden nach dem .NET-Namensschema (#1137).
    Inc(FPos, 2);
    ScanIdentifier;
  end
  else if CharInSet(Peek(1), ['0'..'7']) then
  begin
    // &17: Oktalzahl.
    AKind := TPascalTokenKind.Number;
    Inc(FPos);
    ScanDigits(['0'..'7', '_']);
  end
  else
  begin
    Result := False;
  end;
end;

function TScanner.ScanWord(AStart: Integer): TPascalTokenKind;
begin
  ScanIdentifier;
  // Direkt hinter @ ist ein reserviertes Wort ein Bezeichner: Sprungmarken
  // wie @@End im asm-Block beenden den Block nicht (#861).
  if ((AStart = 0) or (FText[AStart] <> '@')) and
    TPascalLexer.IsReservedWord(Copy(FText, AStart + 1, FPos - AStart)) then
  begin
    Result := TPascalTokenKind.Keyword;
  end
  else
  begin
    Result := TPascalTokenKind.Identifier;
  end;
end;

function TScanner.ScanOther(AStart: Integer): TPascalTokenKind;
begin
  if IsIdentifierStart(Peek) then
  begin
    Result := ScanWord(AStart);
  end
  else if ScanSymbol then
  begin
    Result := TPascalTokenKind.Symbol;
  end
  else
  begin
    Result := TPascalTokenKind.Unknown;
    Inc(FPos);
  end;
end;

function TScanner.Next(out AToken: TPascalToken; out AEndOffset: Integer): Boolean;
var
  mStart: Integer;
  mTerminated: Boolean;
  mKind: TPascalTokenKind;
begin
  while (FPos < FLength) and (Peek <= ' ') do
  begin
    Inc(FPos);
  end;
  if FPos >= FLength then
  begin
    Exit(False);
  end;

  mStart := FPos;
  mTerminated := True;
  if not (ScanComment(mKind, mTerminated) or ScanLiteral(mKind, mTerminated) or ScanAmpersand(mKind)) then
  begin
    mKind := ScanOther(mStart);
  end;

  AToken := Default(TPascalToken);
  AToken.Kind := mKind;
  AToken.Text := Copy(FText, mStart + 1, FPos - mStart);
  AToken.Offset := mStart;
  AToken.Terminated := mTerminated;
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
      begin
        Inc(FLine);
      end;
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

class function TPascalLexer.DirectiveName(const AText: string): string;
var
  mStart, mStop: Integer;
begin
  if Copy(AText, 1, 2) = '{$' then
  begin
    mStart := 3;
  end
  else if Copy(AText, 1, 3) = '(*$' then
  begin
    mStart := 4;
  end
  else
  begin
    Exit('');
  end;
  mStop := mStart;
  while (mStop <= Length(AText)) and CharInSet(AText[mStop], ['A'..'Z', 'a'..'z']) do
  begin
    Inc(mStop);
  end;
  Result := UpperCase(Copy(AText, mStart, mStop - mStart));
end;

class function TPascalLexer.PlainName(const AName: string): string;
var
  mIndex: Integer;
  mAtStart: Boolean;
begin
  Result := '';
  mAtStart := True;
  for mIndex := 1 to Length(AName) do
  begin
    // Nur das erste & eines Teils ist Escape; ein zweites gehört zum Namen.
    if mAtStart and (AName[mIndex] = '&') then
    begin
      mAtStart := False;
      Continue;
    end;
    mAtStart := AName[mIndex] = '.';
    Result := Result + AName[mIndex];
  end;
end;

class function TPascalLexer.SourceName(const AName: string): string;
begin
  if (AName <> '') and ((AName[1] = '&') or IsReservedWord(AName)) then
  begin
    Result := '&' + AName;
  end
  else
  begin
    Result := AName;
  end;
end;

class function TPascalLexer.ReservedWordList: TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cReservedWords));
  for mIndex := 0 to High(cReservedWords) do
  begin
    Result[mIndex] := cReservedWords[mIndex];
  end;
end;

class function TPascalLexer.Tokenize(const AText: string): TArray<TPascalToken>;
var
  mScanner: TScanner;
  mTracker: TPositionTracker;
  mTokens: TList<TPascalToken>;
  mToken: TPascalToken;
  mEndOffset: Integer;
begin
  mScanner.Init(AText);
  mTracker.Init(AText);
  mTokens := TList<TPascalToken>.Create;
  try
    while mScanner.Next(mToken, mEndOffset) do
    begin
      mToken.StartPos := mTracker.PositionAt(mToken.Offset);
      mToken.EndPos := mTracker.PositionAt(mEndOffset);
      mTokens.Add(mToken);
    end;
    Result := mTokens.ToArray;
  finally
    mTokens.Free;
  end;
end;

procedure InitReservedWords;
var
  mWord: string;
begin
  ReservedWordSet := TDictionary<string, Boolean>.Create;
  for mWord in cReservedWords do
  begin
    ReservedWordSet.Add(mWord, True);
  end;
end;

initialization
  InitReservedWords;

finalization
  ReservedWordSet.Free;

end.
