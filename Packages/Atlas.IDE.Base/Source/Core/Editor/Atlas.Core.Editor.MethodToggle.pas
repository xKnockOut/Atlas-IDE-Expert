unit Atlas.Core.Editor.MethodToggle;

// Zwischen Deklaration und Implementierung einer Methode wechseln (#775), ohne
// Open Tools API und ohne Server: Ein kleiner Lexer überspringt Strings,
// Kommentare und Direktiven; ein Parser sammelt
// - Deklarationen: Methodenköpfe in class, record, object und interface
//   (auch verschachtelte und generische Typen), Routinenköpfe im
//   interface-Teil und forward-Deklarationen,
// - Implementierungen: Routinen mit Rumpf auf oberster Ebene, vom Kopf bis zum
//   end des Rumpfs (lokale Routinen gehören zur umgebenden).
// Der Name ist voll qualifiziert ohne Generika-Parameter (TFoo<T>.Bar → TFoo.Bar).
// Gegenstück: gleicher Name auf der anderen Seite; bei Überladungen gewinnt die
// gleiche Parameterliste (Typen), dann die gleiche Anzahl, sonst die erste.
// Ein Implementierungskopf ohne Parameterliste passt zur einzigen Deklaration.
// Bedingte Übersetzung wie beim Compiler (Atlas.Core.Editor.Conditionals): Nur
// aktive Zweige werden zu Token; alternative Rümpfe in $IFDEF-Zweigen brachten
// den Aufbau sonst durcheinander, ab dort fand sich keine Routine mehr.
// Zeilen und Zeichen sind 0-basiert, #13 zählt nicht.

interface

uses
  System.SysUtils;

type
  /// <summary>Deklaration oder Implementierung einer Routine.</summary>
  TAtlasMethodPlace = record
    /// <summary>Voll qualifizierter Name ohne Generika-Parameter, z. B. TOuter.TInner.Run.</summary>
    Name: string;
    /// <summary>Position des (letzten) Namensteils.</summary>
    Line: Integer;
    Character: Integer;
    /// <summary>Bereich: Kopf samt Direktiven bzw. Kopf bis end des Rumpfs.</summary>
    FirstLine: Integer;
    FirstCharacter: Integer;
    LastLine: Integer;
    /// <summary>Parametertypen, klein, durch Komma getrennt; leer ohne Parameter.</summary>
    Signature: string;
    ParameterCount: Integer;
    /// <summary>False, wenn der Kopf keine Parameterliste hat (in der Implementierung erlaubt).</summary>
    HasParameters: Boolean;
    /// <summary>True: Implementierung mit Rumpf; False: Deklaration.</summary>
    IsBody: Boolean;
  end;

  TAtlasMethodToggle = class
  public
    /// <summary>Alle Deklarationen und Implementierungen in AText, in Textreihenfolge. ADefines: gesetzte Symbole
    /// der bedingten Übersetzung; nil = Delphi für Win32 (TTextDefines.Predefined).</summary>
    class function Places(const AText: string; const ADefines: TArray<string>): TArray<TAtlasMethodPlace>;
      overload; static;
    /// <summary>Wie oben für Delphi für Win32 (ADefines = nil).</summary>
    class function Places(const AText: string): TArray<TAtlasMethodPlace>; overload; static;
    /// <summary>Stelle unter dem Cursor (Zeile, Zeichen); False außerhalb jedes Kopfs und Rumpfs.</summary>
    class function PlaceAt(const APlaces: TArray<TAtlasMethodPlace>; ALine, ACharacter: Integer;
      out APlace: TAtlasMethodPlace): Boolean; static;
    /// <summary>Innerster Methodenrumpf um ALine (0-basiert); False außerhalb jeder Methode. Für Lesezeichen,
    /// „Weiterarbeiten“ und die Issues einer Methode (#1275); bis #1455 TAtlasBookmarks.MethodAt.</summary>
    class function BodyAt(const APlaces: TArray<TAtlasMethodPlace>; ALine: Integer;
      out APlace: TAtlasMethodPlace): Boolean; static;
    /// <summary>Name der Methode um ALine (ab 1) in AText; '' außerhalb jeder Methode. Für „Issue anlegen“ (#1268).
    /// </summary>
    class function MethodNameAt(const AText: string; ALine: Integer): string; static;
    /// <summary>Gegenstück zu ASource unter APlaces; False, wenn es keins gibt.</summary>
    class function Match(const APlaces: TArray<TAtlasMethodPlace>; const ASource: TAtlasMethodPlace;
      out ATarget: TAtlasMethodPlace): Boolean; static;
    /// <summary>Gegenstück der Methode am Cursor: Deklaration ⇄ Implementierung; ADefines wie bei Places.</summary>
    class function Counterpart(const AText: string; ALine, ACharacter: Integer; out ATarget: TAtlasMethodPlace;
      const ADefines: TArray<string>): Boolean; overload; static;
    /// <summary>Wie oben für Delphi für Win32 (ADefines = nil).</summary>
    class function Counterpart(const AText: string; ALine, ACharacter: Integer;
      out ATarget: TAtlasMethodPlace): Boolean; overload; static;
  end;

implementation

uses
  Atlas.Text.Chars,
  Atlas.Text.Defines,
  Atlas.Core.Editor.Conditionals;

type
  TTokenKind = (tkIdent, tkNumber, tkString, tkSymbol, tkEof);

  TToken = record
    Text: string;
    Lower: string;
    Kind: TTokenKind;
    Line: Integer;
    Character: Integer;
    /// <summary>&amp;begin: Bezeichner, kein Schlüsselwort.</summary>
    Escaped: Boolean;
    /// <summary>Steht hinter "." (Mitglied, kein Schlüsselwort).</summary>
    AfterDot: Boolean;
  end;

  THeading = record
    Name: string;
    NameToken: Integer;
    Signature: string;
    ParameterCount: Integer;
    HasParameters: Boolean;
  end;

  /// <summary>Zerlegt den Text in Token; nur aktive Zweige der bedingten Übersetzung.</summary>
  TLexer = class
  private
    FTokens: TArray<TToken>;
    FCount: Integer;
    FConditionals: TAtlasConditionals;
    FText: string;
    FLen: Integer;
    FI: Integer;
    FLine: Integer;
    FLineStart: Integer;
    procedure AddToken(const AText: string; AKind: TTokenKind; ALine, ACharacter: Integer; AEscaped: Boolean);
    function CharAt(AIndex: Integer): Char;
    procedure LexNewLine;
    procedure SkipChar;
    function RestOfLineBlank(AFrom: Integer): Boolean;
    function AtTripleQuote(AIndex: Integer): Boolean;
    function LexBlank: Boolean;
    function LexComment: Boolean;
    procedure SkipMultilineString;
    procedure SkipQuotedString;
    function LexString: Boolean;
    function LexCharCode: Boolean;
    function LexIdent: Boolean;
    function LexNumber: Boolean;
    function IsTwoCharSymbol: Boolean;
    procedure LexSymbol;
    function LexSkipped: Boolean;
    function LexLiteral: Boolean;
    procedure Lex(const AText: string);
  public
    function Run(const AText: string; const ADefines: TArray<string>): TArray<TToken>;
  end;

  /// <summary>Liest die Parametertypen einer Parameterliste Token für Token.</summary>
  TSignatureReader = record
  private
    FDepth: Integer;
    FNames: Integer;
    FTypeText: string;
    FInType: Boolean;
    FInDefault: Boolean;
    FTyped: Boolean;
    class function IsSymbolIn(const AToken: TToken; const ASymbols: string): Boolean; static;
    class function IsModifier(const AToken: TToken): Boolean; static;
    procedure AppendType(const AToken: TToken);
    procedure Flush;
    procedure EndGroup;
    procedure FeedTopLevel(const AToken: TToken);
  public
    /// <summary>Typen, klein, durch Komma getrennt.</summary>
    Text: string;
    Count: Integer;
    procedure Init;
    procedure Feed(const AToken: TToken);
    procedure Finish;
  end;

  TParser = class
  private
    FTokens: TArray<TToken>;
    FCount: Integer;
    FPos: Integer;
    FEof: TToken;
    FPlaces: TArray<TAtlasMethodPlace>;
    FPlaceCount: Integer;
    function Tok(AOffset: Integer): TToken;
    function Kw(AOffset: Integer; const AWord: string): Boolean;
    function KwIn(AOffset: Integer; const AWords: array of string): Boolean;
    function Sym(AOffset: Integer; const ASymbol: string): Boolean;
    function BracketDelta: Integer;
    function IsRoutineStart: Boolean;
    function IsSectionEnd: Boolean;
    function IsDirective: Boolean;
    procedure SkipBrackets;
    procedure SkipAngles;
    procedure SkipToSemicolon;
    procedure SkipDeclarations;
    procedure SkipCompound;
    procedure SkipHelper;
    procedure SkipProperty;
    procedure SkipVariantCase;
    function ParseHeading(out AHeading: THeading): Boolean;
    procedure SkipDirectives(out AForward, AExternal: Boolean);
    function Signature(AFirst, ALast: Integer; out ACount: Integer): string;
    function ParseBlockBody: Integer;
    function ReadTypeName(const AOwner: string; out APath: string): Boolean;
    procedure ParseStructBody(const APath: string; ACollect: Boolean);
    procedure ParseClassType(const APath: string; ACollect: Boolean);
    procedure ParseRecordType(const APath: string; ACollect: Boolean);
    procedure ParseInterfaceType(const APath: string; ACollect: Boolean);
    procedure ParseTypeValue(const APath: string; ACollect: Boolean);
    procedure ParseTypeSection(const AOwner: string; ACollect: Boolean);
    procedure ParseStructItem(const AOwner: string; ACollect: Boolean);
    procedure ParseStruct(const AOwner: string; ACollect: Boolean);
    procedure ParseRoutine(const AOwner: string; AInInterface, ACollect: Boolean);
    procedure ParseTopLevelItem(var AInInterface: Boolean);
    procedure ParseTopLevel;
    procedure AddPlace(const AName: string; const AHeading: THeading; AFirst, ALast: Integer; AIsBody: Boolean);
  public
    function Run(const AText: string; const ADefines: TArray<string>): TArray<TAtlasMethodPlace>;
  end;

{ TLexer }

procedure TLexer.AddToken(const AText: string; AKind: TTokenKind; ALine, ACharacter: Integer; AEscaped: Boolean);
var
  Token: TToken;
begin
  // Inaktiver Zweig der bedingten Übersetzung: kein Token.
  if not FConditionals.Active then
  begin
    Exit;
  end;
  Token.Text := AText;
  Token.Lower := LowerCase(AText);
  Token.Kind := AKind;
  Token.Line := ALine;
  Token.Character := ACharacter;
  Token.Escaped := AEscaped;
  Token.AfterDot := (FCount > 0) and (FTokens[FCount - 1].Kind = tkSymbol) and (FTokens[FCount - 1].Text = '.');
  if FCount = Length(FTokens) then
  begin
    SetLength(FTokens, 2 * FCount + 64);
  end;
  FTokens[FCount] := Token;
  Inc(FCount);
end;

function TLexer.CharAt(AIndex: Integer): Char;
begin
  Result := #0;
  if (AIndex >= 1) and (AIndex <= FLen) then
  begin
    Result := FText[AIndex];
  end;
end;

procedure TLexer.LexNewLine;
begin
  Inc(FLine);
  FLineStart := FI + 1;
end;

procedure TLexer.SkipChar;
begin
  if CharAt(FI) = #10 then
  begin
    LexNewLine;
  end;
  Inc(FI);
end;

function TLexer.RestOfLineBlank(AFrom: Integer): Boolean;
var
  mIndex: Integer;
begin
  Result := True;
  mIndex := AFrom;
  while Result and (mIndex <= FLen) and (FText[mIndex] <> #10) do
  begin
    Result := CharInSet(FText[mIndex], [' ', #9, #13]);
    Inc(mIndex);
  end;
end;

function TLexer.LexBlank: Boolean;
var
  mChar: Char;
begin
  mChar := CharAt(FI);
  Result := True;
  if CharInSet(mChar, [#10, ' ', #9, #13, #12]) then
  begin
    SkipChar;
  end
  else if (mChar = '/') and (CharAt(FI + 1) = '/') then
  begin
    while (FI <= FLen) and (FText[FI] <> #10) do
    begin
      Inc(FI);
    end;
  end
  else
  begin
    Result := False;
  end;
end;

function TLexer.LexComment: Boolean;
var
  mStart: Integer;
begin
  mStart := FI;
  Result := True;
  if CharAt(FI) = '{' then
  begin
    while (FI <= FLen) and (FText[FI] <> '}') do
    begin
      SkipChar;
    end;
    if CharAt(mStart + 1) = '$' then
    begin
      FConditionals.Handle(Copy(FText, mStart + 2, FI - mStart - 2));
    end;
    Inc(FI);
  end
  else if (CharAt(FI) = '(') and (CharAt(FI + 1) = '*') then
  begin
    Inc(FI, 2);
    while (FI <= FLen) and not ((FText[FI] = '*') and (CharAt(FI + 1) = ')')) do
    begin
      SkipChar;
    end;
    if CharAt(mStart + 2) = '$' then
    begin
      FConditionals.Handle(Copy(FText, mStart + 3, FI - mStart - 3));
    end;
    Inc(FI, 2);
  end
  else
  begin
    Result := False;
  end;
end;

function TLexer.AtTripleQuote(AIndex: Integer): Boolean;
begin
  Result := (CharAt(AIndex) = '''') and (CharAt(AIndex + 1) = '''') and (CharAt(AIndex + 2) = '''');
end;

procedure TLexer.SkipMultilineString;
begin
  // Mehrzeiliger String (Delphi 12): bis zur nächsten Zeile mit '''.
  Inc(FI, 3);
  while (FI <= FLen) and not AtTripleQuote(FI) do
  begin
    SkipChar;
  end;
  Inc(FI, 3);
  while CharAt(FI) = '''' do
  begin
    Inc(FI);
  end;
end;

procedure TLexer.SkipQuotedString;
var
  mDone: Boolean;
begin
  Inc(FI);
  mDone := False;
  while not mDone and (FI <= FLen) and (FText[FI] <> #10) do
  begin
    if (FText[FI] = '''') and (CharAt(FI + 1) = '''') then
    begin
      Inc(FI, 2);
    end
    else
    begin
      mDone := FText[FI] = '''';
      Inc(FI);
    end;
  end;
end;

function TLexer.LexString: Boolean;
var
  mStart, mStartLine, mStartChar: Integer;
begin
  Result := CharAt(FI) = '''';
  if not Result then
  begin
    Exit;
  end;
  mStartLine := FLine;
  mStartChar := FI - FLineStart;
  mStart := FI;
  if AtTripleQuote(FI) and RestOfLineBlank(FI + 3) then
  begin
    SkipMultilineString;
  end
  else
  begin
    SkipQuotedString;
  end;
  AddToken(Copy(FText, mStart, FI - mStart), tkString, mStartLine, mStartChar, False);
end;

function TLexer.LexCharCode: Boolean;
var
  mStart: Integer;
begin
  Result := CharAt(FI) = '#';
  if not Result then
  begin
    Exit;
  end;
  mStart := FI;
  Inc(FI);
  while (FI <= FLen) and (TTextChars.IsIdentChar(FText[FI]) or (FText[FI] = '$')) do
  begin
    Inc(FI);
  end;
  AddToken(Copy(FText, mStart, FI - mStart), tkString, FLine, mStart - FLineStart, False);
end;

function TLexer.LexIdent: Boolean;
var
  mStart: Integer;
  mChar: Char;
  mEscaped: Boolean;
begin
  mChar := CharAt(FI);
  Result := TTextChars.IsIdentStart(mChar) or ((mChar = '&') and TTextChars.IsIdentStart(CharAt(FI + 1)));
  if not Result then
  begin
    Exit;
  end;
  // &begin und Sprungmarken wie @@End (#861) sind keine Schlüsselwörter.
  mEscaped := (mChar = '&') or (CharAt(FI - 1) = '@');
  if mChar = '&' then
  begin
    Inc(FI);
  end;
  mStart := FI;
  while (FI <= FLen) and TTextChars.IsIdentChar(FText[FI]) do
  begin
    Inc(FI);
  end;
  AddToken(Copy(FText, mStart, FI - mStart), tkIdent, FLine, mStart - FLineStart, mEscaped);
end;

function TLexer.LexNumber: Boolean;
var
  mStart: Integer;
begin
  Result := CharInSet(CharAt(FI), ['0'..'9', '$', '%']);
  if not Result then
  begin
    Exit;
  end;
  mStart := FI;
  Inc(FI);
  while (FI <= FLen) and (TTextChars.IsIdentChar(FText[FI]) or
    ((FText[FI] = '.') and CharInSet(CharAt(FI + 1), ['0'..'9']))) do
  begin
    Inc(FI);
  end;
  AddToken(Copy(FText, mStart, FI - mStart), tkNumber, FLine, mStart - FLineStart, False);
end;

function TLexer.IsTwoCharSymbol: Boolean;
var
  mPair: string;
begin
  mPair := FText[FI] + CharAt(FI + 1);
  Result := (mPair = ':=') or (mPair = '..') or (mPair = '<=') or (mPair = '<>') or (mPair = '>=');
end;

procedure TLexer.LexSymbol;
var
  mStart: Integer;
begin
  mStart := FI;
  if IsTwoCharSymbol then
  begin
    Inc(FI, 2);
  end
  else
  begin
    Inc(FI);
  end;
  AddToken(Copy(FText, mStart, FI - mStart), tkSymbol, FLine, mStart - FLineStart, False);
end;

function TLexer.LexSkipped: Boolean;
begin
  Result := LexBlank or LexComment;
end;

function TLexer.LexLiteral: Boolean;
begin
  Result := LexString or LexCharCode or LexIdent or LexNumber;
end;

procedure TLexer.Lex(const AText: string);
begin
  FTokens := nil;
  FCount := 0;
  FText := AText;
  FLen := Length(AText);
  FLine := 0;
  FLineStart := 1;
  FI := 1;
  while FI <= FLen do
  begin
    if not (LexSkipped or LexLiteral) then
    begin
      LexSymbol;
    end;
  end;
  FText := '';
end;

function TLexer.Run(const AText: string; const ADefines: TArray<string>): TArray<TToken>;
var
  mDefines: TArray<string>;
begin
  mDefines := ADefines;
  if mDefines = nil then
  begin
    mDefines := TTextDefines.Predefined('Win32', CompilerVersion);
  end;
  FConditionals := TAtlasConditionals.Create(mDefines, CompilerVersion);
  try
    Lex(AText);
  finally
    FreeAndNil(FConditionals);
  end;
  SetLength(FTokens, FCount);
  Result := FTokens;
end;

{ TSignatureReader }

procedure TSignatureReader.Init;
begin
  Self := Default(TSignatureReader);
end;

class function TSignatureReader.IsSymbolIn(const AToken: TToken; const ASymbols: string): Boolean;
begin
  Result := (AToken.Kind = tkSymbol) and (Length(AToken.Text) = 1) and (Pos(AToken.Text, ASymbols) > 0);
end;

class function TSignatureReader.IsModifier(const AToken: TToken): Boolean;
begin
  Result := not AToken.Escaped and ((AToken.Lower = 'const') or (AToken.Lower = 'var') or (AToken.Lower = 'out') or
    (AToken.Lower = 'constref'));
end;

procedure TSignatureReader.AppendType(const AToken: TToken);
begin
  if FInType and not FInDefault then
  begin
    FTypeText := FTypeText + AToken.Lower;
  end;
end;

procedure TSignatureReader.Flush;
var
  mIndex: Integer;
  mType: string;
begin
  mType := '';
  if FTyped then
  begin
    mType := FTypeText;
  end;
  for mIndex := 1 to FNames do
  begin
    if Text <> '' then
    begin
      Text := Text + ',';
    end;
    Text := Text + mType;
    Inc(Count);
  end;
end;

procedure TSignatureReader.EndGroup;
begin
  Flush;
  FNames := 0;
  FTypeText := '';
  FInType := False;
  FInDefault := False;
  FTyped := False;
end;

procedure TSignatureReader.FeedTopLevel(const AToken: TToken);
begin
  if IsSymbolIn(AToken, ';') then
  begin
    EndGroup;
  end
  else if IsSymbolIn(AToken, ':') and not FInType then
  begin
    FInType := True;
    FTyped := True;
  end
  else if IsSymbolIn(AToken, '=') and FInType then
  begin
    FInDefault := True;
  end
  else if FInType then
  begin
    AppendType(AToken);
  end
  else if (AToken.Kind = tkIdent) and not ((FNames = 0) and IsModifier(AToken)) then
  begin
    Inc(FNames);
  end;
end;

procedure TSignatureReader.Feed(const AToken: TToken);
begin
  if IsSymbolIn(AToken, '([<') then
  begin
    Inc(FDepth);
    AppendType(AToken);
  end
  else if IsSymbolIn(AToken, ')]>') then
  begin
    Dec(FDepth);
    AppendType(AToken);
  end
  else if FDepth = 0 then
  begin
    FeedTopLevel(AToken);
  end
  else
  begin
    AppendType(AToken);
  end;
end;

procedure TSignatureReader.Finish;
begin
  Flush;
end;

{ TParser }

function TParser.Tok(AOffset: Integer): TToken;
begin
  if (FPos + AOffset >= 0) and (FPos + AOffset < FCount) then
  begin
    Result := FTokens[FPos + AOffset];
  end
  else
  begin
    Result := FEof;
  end;
end;

function TParser.Kw(AOffset: Integer; const AWord: string): Boolean;
var
  Token: TToken;
begin
  Token := Tok(AOffset);
  Result := (Token.Kind = tkIdent) and not Token.Escaped and not Token.AfterDot and (Token.Lower = AWord);
end;

function TParser.Sym(AOffset: Integer; const ASymbol: string): Boolean;
var
  Token: TToken;
begin
  Token := Tok(AOffset);
  Result := (Token.Kind = tkSymbol) and (Token.Text = ASymbol);
end;

function TParser.IsRoutineStart: Boolean;
const
  cRoutineWords: array[0..4] of string = ('procedure', 'function', 'constructor', 'destructor', 'operator');
begin
  Result := KwIn(0, cRoutineWords) or (Kw(0, 'class') and KwIn(1, cRoutineWords));
end;

function TParser.IsSectionEnd: Boolean;
const
  Words: array[0..25] of string = ('begin', 'asm', 'var', 'const', 'type', 'label', 'resourcestring', 'threadvar',
    'procedure', 'function', 'constructor', 'destructor', 'operator', 'class', 'initialization', 'finalization',
    'implementation', 'interface', 'end', 'exports', 'property', 'private', 'protected', 'public', 'published',
    'strict');
var
  Word: string;
begin
  Result := Tok(0).Kind = tkEof;
  if not Result then
  begin
    for Word in Words do
    begin
      if Kw(0, Word) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

function TParser.IsDirective: Boolean;
const
  Words: array[0..28] of string = ('abstract', 'assembler', 'cdecl', 'deprecated', 'dispid', 'dynamic',
    'experimental', 'export', 'external', 'far', 'final', 'forward', 'inline', 'library', 'local', 'message', 'near',
    'overload', 'override', 'pascal', 'platform', 'register', 'reintroduce', 'safecall', 'static', 'stdcall',
    'varargs', 'virtual', 'winapi');
var
  Token: TToken;
  Word: string;
begin
  Result := False;
  Token := Tok(0);
  if (Token.Kind <> tkIdent) or Token.Escaped then
  begin
    Exit;
  end;
  // Ein Feld gleichen Namens (Message: string;) ist keine Direktive.
  if Sym(1, ':') or Sym(1, ',') or Sym(1, '=') then
  begin
    Exit;
  end;
  for Word in Words do
  begin
    if Token.Lower = Word then
    begin
      Exit(True);
    end;
  end;
end;

procedure TParser.SkipBrackets;
var
  Depth: Integer;
begin
  Depth := 0;
  while Tok(0).Kind <> tkEof do
  begin
    if Sym(0, '(') or Sym(0, '[') then
    begin
      Inc(Depth);
    end
    else if Sym(0, ')') or Sym(0, ']') then
    begin
      Dec(Depth);
    end;
    Inc(FPos);
    if Depth <= 0 then
    begin
      Exit;
    end;
  end;
end;

procedure TParser.SkipAngles;
var
  Depth: Integer;
begin
  Depth := 0;
  while Tok(0).Kind <> tkEof do
  begin
    if Sym(0, '<') then
    begin
      Inc(Depth);
    end
    else if Sym(0, '>') then
    begin
      Dec(Depth);
    end;
    Inc(FPos);
    if Depth <= 0 then
    begin
      Exit;
    end;
  end;
end;

function TParser.KwIn(AOffset: Integer; const AWords: array of string): Boolean;
var
  mWord: string;
begin
  Result := False;
  for mWord in AWords do
  begin
    Result := Result or Kw(AOffset, mWord);
  end;
end;

function TParser.BracketDelta: Integer;
begin
  Result := 0;
  if Sym(0, '(') or Sym(0, '[') then
  begin
    Result := 1;
  end
  else if Sym(0, ')') or Sym(0, ']') then
  begin
    Result := -1;
  end;
end;

procedure TParser.SkipToSemicolon;
var
  mDepth: Integer;
begin
  mDepth := 0;
  while Tok(0).Kind <> tkEof do
  begin
    if (mDepth <= 0) and (BracketDelta = 0) then
    begin
      if Sym(0, ';') then
      begin
        Inc(FPos);
        Exit;
      end;
      // Letztes Feld vor end ohne Semikolon.
      if Kw(0, 'end') then
      begin
        Exit;
      end;
      if Kw(0, 'record') then
      begin
        Inc(FPos);
        ParseStruct('', False);
        Continue;
      end;
    end;
    Inc(mDepth, BracketDelta);
    Inc(FPos);
  end;
end;

procedure TParser.SkipDeclarations;
var
  Before: Integer;
begin
  while not IsSectionEnd do
  begin
    Before := FPos;
    if Sym(0, '[') then
    begin
      SkipBrackets;
    end
    else
    begin
      SkipToSemicolon;
    end;
    if FPos = Before then
    begin
      Inc(FPos);
    end;
  end;
end;

procedure TParser.SkipCompound;
var
  Depth: Integer;
begin
  Depth := 0;
  while Tok(0).Kind <> tkEof do
  begin
    if Kw(0, 'begin') or Kw(0, 'asm') or Kw(0, 'try') or Kw(0, 'case') then
    begin
      Inc(Depth);
    end
    else if Kw(0, 'end') then
    begin
      Dec(Depth);
      if Depth <= 0 then
      begin
        Inc(FPos);
        Exit;
      end;
    end;
    Inc(FPos);
  end;
end;

procedure TParser.SkipHelper;
begin
  // helper[(Vorfahr)] for Typ
  Inc(FPos);
  if Sym(0, '(') then
  begin
    SkipBrackets;
  end;
  if Kw(0, 'for') then
  begin
    Inc(FPos);
    if Tok(0).Kind = tkIdent then
    begin
      Inc(FPos);
    end;
    while Sym(0, '.') and (Tok(1).Kind = tkIdent) do
    begin
      Inc(FPos, 2);
    end;
    if Sym(0, '<') then
    begin
      SkipAngles;
    end;
  end;
end;

function TParser.Signature(AFirst, ALast: Integer; out ACount: Integer): string;
var
  mIndex: Integer;
  mReader: TSignatureReader;
begin
  mReader.Init;
  for mIndex := AFirst to ALast do
  begin
    mReader.Feed(FTokens[mIndex]);
  end;
  mReader.Finish;
  ACount := mReader.Count;
  Result := mReader.Text;
end;

function TParser.ParseHeading(out AHeading: THeading): Boolean;
var
  Open: Integer;
begin
  AHeading.Name := '';
  AHeading.NameToken := -1;
  AHeading.Signature := '';
  AHeading.ParameterCount := 0;
  AHeading.HasParameters := False;
  Result := False;
  // Schlüsselwort procedure/function/…
  Inc(FPos);
  if Tok(0).Kind <> tkIdent then
  begin
    SkipToSemicolon;
    Exit;
  end;
  AHeading.Name := Tok(0).Text;
  AHeading.NameToken := FPos;
  Inc(FPos);
  if Sym(0, '<') then
  begin
    SkipAngles;
  end;
  while Sym(0, '.') and (Tok(1).Kind = tkIdent) do
  begin
    AHeading.Name := AHeading.Name + '.' + Tok(1).Text;
    AHeading.NameToken := FPos + 1;
    Inc(FPos, 2);
    if Sym(0, '<') then
    begin
      SkipAngles;
    end;
  end;
  // Methodenauflösungsklausel (procedure IFoo.Bar = MeinBar;): keine Deklaration.
  if Sym(0, '=') then
  begin
    SkipToSemicolon;
    Exit;
  end;
  if Sym(0, '(') then
  begin
    Open := FPos;
    SkipBrackets;
    AHeading.HasParameters := True;
    AHeading.Signature := Signature(Open + 1, FPos - 2, AHeading.ParameterCount);
  end;
  SkipToSemicolon;
  Result := True;
end;

procedure TParser.SkipDirectives(out AForward, AExternal: Boolean);
var
  Before: Integer;
begin
  AForward := False;
  AExternal := False;
  while IsDirective do
  begin
    if Kw(0, 'forward') then
    begin
      AForward := True;
    end
    else if Kw(0, 'external') then
    begin
      AExternal := True;
    end;
    Before := FPos;
    SkipToSemicolon;
    if FPos = Before then
    begin
      Exit;
    end;
  end;
end;

procedure TParser.AddPlace(const AName: string; const AHeading: THeading; AFirst, ALast: Integer; AIsBody: Boolean);
var
  Place: TAtlasMethodPlace;
begin
  if (AHeading.NameToken < 0) or (AFirst < 0) or (AFirst >= FCount) then
  begin
    Exit;
  end;
  if ALast >= FCount then
  begin
    ALast := FCount - 1;
  end;
  if ALast < AFirst then
  begin
    ALast := AFirst;
  end;
  Place.Name := AName;
  Place.Line := FTokens[AHeading.NameToken].Line;
  Place.Character := FTokens[AHeading.NameToken].Character;
  Place.FirstLine := FTokens[AFirst].Line;
  Place.FirstCharacter := FTokens[AFirst].Character;
  Place.LastLine := FTokens[ALast].Line;
  Place.Signature := AHeading.Signature;
  Place.ParameterCount := AHeading.ParameterCount;
  Place.HasParameters := AHeading.HasParameters;
  Place.IsBody := AIsBody;
  if FPlaceCount = Length(FPlaces) then
  begin
    SetLength(FPlaces, 2 * FPlaceCount + 16);
  end;
  FPlaces[FPlaceCount] := Place;
  Inc(FPlaceCount);
end;

function TParser.ParseBlockBody: Integer;
var
  Before: Integer;
begin
  Result := FPos - 1;
  while Tok(0).Kind <> tkEof do
  begin
    Before := FPos;
    if Kw(0, 'begin') or Kw(0, 'asm') then
    begin
      SkipCompound;
      Exit(FPos - 1);
    end
    else if Kw(0, 'initialization') or Kw(0, 'finalization') or Kw(0, 'implementation') then
    begin
      Exit;
    end
    else if Kw(0, 'var') or Kw(0, 'const') or Kw(0, 'threadvar') or Kw(0, 'resourcestring') or Kw(0, 'label') then
    begin
      Inc(FPos);
      SkipDeclarations;
    end
    else if Kw(0, 'type') then
    begin
      Inc(FPos);
      ParseTypeSection('', False);
    end
    else if IsRoutineStart then
    begin
      // Lokale Routine: gehört zum Rumpf der umgebenden.
      ParseRoutine('', False, False);
    end
    else
    begin
      Inc(FPos);
    end;
    if FPos = Before then
    begin
      Inc(FPos);
    end;
    Result := FPos - 1;
  end;
end;

procedure TParser.ParseRoutine(const AOwner: string; AInInterface, ACollect: Boolean);
var
  First, Last: Integer;
  Heading: THeading;
  IsForward, IsExternal: Boolean;
  Name: string;
begin
  First := FPos;
  if Kw(0, 'class') then
  begin
    Inc(FPos);
  end;
  if not ParseHeading(Heading) then
  begin
    Exit;
  end;
  SkipDirectives(IsForward, IsExternal);
  Name := Heading.Name;
  if AOwner <> '' then
  begin
    Name := AOwner + '.' + Name;
  end;
  if AInInterface or IsForward then
  begin
    if ACollect then
    begin
      AddPlace(Name, Heading, First, FPos - 1, False);
    end;
    Exit;
  end;
  if IsExternal then
  begin
    Exit;
  end;
  Last := ParseBlockBody;
  if ACollect then
  begin
    AddPlace(Name, Heading, First, Last, True);
  end;
end;

function TParser.ReadTypeName(const AOwner: string; out APath: string): Boolean;
begin
  APath := '';
  Result := (Tok(0).Kind = tkIdent) and (Sym(1, '=') or Sym(1, '<'));
  if not Result then
  begin
    Exit;
  end;
  APath := Tok(0).Text;
  if AOwner <> '' then
  begin
    APath := AOwner + '.' + APath;
  end;
  Inc(FPos);
  if Sym(0, '<') then
  begin
    SkipAngles;
  end;
  Result := Sym(0, '=');
  if Result then
  begin
    Inc(FPos);
    if Kw(0, 'type') then
    begin
      Inc(FPos);
    end;
    if Kw(0, 'packed') then
    begin
      Inc(FPos);
    end;
  end;
end;

procedure TParser.ParseStructBody(const APath: string; ACollect: Boolean);
begin
  ParseStruct(APath, ACollect);
  SkipToSemicolon;
end;

procedure TParser.ParseClassType(const APath: string; ACollect: Boolean);
begin
  if Kw(0, 'of') or Sym(0, ';') then
  begin
    SkipToSemicolon;
    Exit;
  end;
  if Kw(0, 'helper') then
  begin
    SkipHelper;
  end;
  while Kw(0, 'abstract') or Kw(0, 'sealed') do
  begin
    Inc(FPos);
  end;
  if Sym(0, '(') then
  begin
    SkipBrackets;
  end;
  if Sym(0, ';') then
  begin
    Inc(FPos);
  end
  else
  begin
    ParseStructBody(APath, ACollect);
  end;
end;

procedure TParser.ParseRecordType(const APath: string; ACollect: Boolean);
begin
  if Kw(0, 'helper') then
  begin
    SkipHelper;
  end;
  if Sym(0, '(') then
  begin
    SkipBrackets;
  end;
  ParseStructBody(APath, ACollect);
end;

procedure TParser.ParseInterfaceType(const APath: string; ACollect: Boolean);
begin
  if Sym(0, '(') then
  begin
    SkipBrackets;
  end;
  if Sym(0, ';') then
  begin
    Inc(FPos);
    Exit;
  end;
  if Sym(0, '[') then
  begin
    SkipBrackets;
  end;
  ParseStructBody(APath, ACollect);
end;

procedure TParser.ParseTypeValue(const APath: string; ACollect: Boolean);
begin
  if Kw(0, 'class') then
  begin
    Inc(FPos);
    ParseClassType(APath, ACollect);
  end
  else if KwIn(0, ['record', 'object']) then
  begin
    Inc(FPos);
    ParseRecordType(APath, ACollect);
  end
  else if KwIn(0, ['interface', 'dispinterface']) then
  begin
    Inc(FPos);
    ParseInterfaceType(APath, ACollect);
  end
  else
  begin
    SkipToSemicolon;
  end;
end;

procedure TParser.ParseTypeSection(const AOwner: string; ACollect: Boolean);
var
  mPath: string;
  mBefore: Integer;
begin
  while Tok(0).Kind <> tkEof do
  begin
    mBefore := FPos;
    if Sym(0, '[') then
    begin
      SkipBrackets;
      Continue;
    end;
    if not ReadTypeName(AOwner, mPath) then
    begin
      Exit;
    end;
    ParseTypeValue(mPath, ACollect);
    if FPos = mBefore then
    begin
      Inc(FPos);
    end;
  end;
end;

procedure TParser.SkipProperty;
begin
  SkipToSemicolon;
  if Kw(0, 'default') and Sym(1, ';') then
  begin
    Inc(FPos, 2);
  end;
end;

procedure TParser.SkipVariantCase;
begin
  while (Tok(0).Kind <> tkEof) and not Kw(0, 'of') do
  begin
    Inc(FPos);
  end;
  Inc(FPos);
end;

procedure TParser.ParseStructItem(const AOwner: string; ACollect: Boolean);
begin
  if Sym(0, '[') then
  begin
    SkipBrackets;
  end
  else if KwIn(0, ['private', 'protected', 'public', 'published', 'automated', 'strict']) then
  begin
    Inc(FPos);
  end
  else if IsRoutineStart then
  begin
    ParseRoutine(AOwner, True, ACollect);
  end
  else if KwIn(0, ['class', 'var', 'const', 'threadvar']) then
  begin
    Inc(FPos);
  end
  else if Kw(0, 'property') then
  begin
    SkipProperty;
  end
  else if Kw(0, 'type') then
  begin
    Inc(FPos);
    ParseTypeSection(AOwner, ACollect);
  end
  else if Kw(0, 'case') then
  begin
    SkipVariantCase;
  end
  else
  begin
    SkipToSemicolon;
  end;
end;

procedure TParser.ParseStruct(const AOwner: string; ACollect: Boolean);
var
  mBefore: Integer;
begin
  while Tok(0).Kind <> tkEof do
  begin
    mBefore := FPos;
    if Kw(0, 'end') then
    begin
      Inc(FPos);
      Exit;
    end;
    ParseStructItem(AOwner, ACollect);
    if FPos = mBefore then
    begin
      Inc(FPos);
    end;
  end;
end;

procedure TParser.ParseTopLevelItem(var AInInterface: Boolean);
begin
  if KwIn(0, ['unit', 'program', 'library', 'package', 'uses', 'contains', 'requires', 'exports']) then
  begin
    SkipToSemicolon;
  end
  else if KwIn(0, ['interface', 'implementation']) then
  begin
    AInInterface := Kw(0, 'interface');
    Inc(FPos);
  end
  else if Kw(0, 'type') then
  begin
    Inc(FPos);
    ParseTypeSection('', True);
  end
  else if KwIn(0, ['var', 'const', 'threadvar', 'resourcestring', 'label']) then
  begin
    Inc(FPos);
    SkipDeclarations;
  end
  else if IsRoutineStart then
  begin
    ParseRoutine('', AInInterface, True);
  end
  else if Sym(0, '[') then
  begin
    SkipBrackets;
  end
  else
  begin
    Inc(FPos);
  end;
end;

procedure TParser.ParseTopLevel;
var
  mInInterface: Boolean;
  mBefore: Integer;
begin
  // Programme und Bibliotheken haben keinen interface-Teil.
  mInInterface := False;
  while (Tok(0).Kind <> tkEof) and not KwIn(0, ['initialization', 'finalization', 'begin', 'end']) do
  begin
    mBefore := FPos;
    ParseTopLevelItem(mInInterface);
    if FPos = mBefore then
    begin
      Inc(FPos);
    end;
  end;
end;

function TParser.Run(const AText: string; const ADefines: TArray<string>): TArray<TAtlasMethodPlace>;
var
  mLexer: TLexer;
begin
  FEof.Kind := tkEof;
  FEof.Line := MaxInt;
  FPlaces := nil;
  FPlaceCount := 0;
  mLexer := TLexer.Create;
  try
    FTokens := mLexer.Run(AText, ADefines);
  finally
    mLexer.Free;
  end;
  FCount := Length(FTokens);
  FPos := 0;
  ParseTopLevel;
  SetLength(FPlaces, FPlaceCount);
  Result := FPlaces;
end;

{ TAtlasMethodToggle }

class function TAtlasMethodToggle.Places(const AText: string): TArray<TAtlasMethodPlace>;
begin
  Result := Places(AText, nil);
end;

class function TAtlasMethodToggle.Places(const AText: string;
  const ADefines: TArray<string>): TArray<TAtlasMethodPlace>;
var
  Parser: TParser;
begin
  Parser := TParser.Create;
  try
    Result := Parser.Run(AText, ADefines);
  finally
    Parser.Free;
  end;
end;

class function TAtlasMethodToggle.PlaceAt(const APlaces: TArray<TAtlasMethodPlace>; ALine, ACharacter: Integer;
  out APlace: TAtlasMethodPlace): Boolean;
var
  Place: TAtlasMethodPlace;
begin
  Result := False;
  APlace := Default(TAtlasMethodPlace);
  for Place in APlaces do
  begin
    if (ALine < Place.FirstLine) or (ALine > Place.LastLine) then
    begin
      Continue;
    end;
    // Mehrere Köpfe in einer Zeile: der letzte, der vor dem Cursor beginnt.
    if Result and ((Place.FirstLine > ALine) or
      ((Place.FirstLine = ALine) and (Place.FirstCharacter > ACharacter))) then
    begin
      Continue;
    end;
    APlace := Place;
    Result := True;
  end;
end;

class function TAtlasMethodToggle.MethodNameAt(const AText: string; ALine: Integer): string;
var
  mPlace: TAtlasMethodPlace;
begin
  Result := '';
  if (AText <> '') and (ALine >= 1) and BodyAt(Places(AText), ALine - 1, mPlace) then
  begin
    Result := mPlace.Name;
  end;
end;

class function TAtlasMethodToggle.BodyAt(const APlaces: TArray<TAtlasMethodPlace>; ALine: Integer;
  out APlace: TAtlasMethodPlace): Boolean;
var
  mPlace: TAtlasMethodPlace;
begin
  Result := False;
  APlace := Default(TAtlasMethodPlace);
  for mPlace in APlaces do
  begin
    if mPlace.IsBody and (ALine >= mPlace.FirstLine) and (ALine <= mPlace.LastLine) and
      (not Result or (mPlace.LastLine - mPlace.FirstLine < APlace.LastLine - APlace.FirstLine)) then
    begin
      APlace := mPlace;
      Result := True;
    end;
  end;
end;

class function TAtlasMethodToggle.Match(const APlaces: TArray<TAtlasMethodPlace>; const ASource: TAtlasMethodPlace;
  out ATarget: TAtlasMethodPlace): Boolean;
var
  Candidates: TArray<TAtlasMethodPlace>;
  Place: TAtlasMethodPlace;
begin
  Result := False;
  ATarget := Default(TAtlasMethodPlace);
  Candidates := nil;
  for Place in APlaces do
  begin
    if (Place.IsBody <> ASource.IsBody) and SameText(Place.Name, ASource.Name) then
    begin
      Candidates := Candidates + [Place];
    end;
  end;
  if Length(Candidates) = 0 then
  begin
    Exit;
  end;
  Result := True;
  ATarget := Candidates[0];
  if Length(Candidates) = 1 then
  begin
    Exit;
  end;
  // Überladungen: auch die ohne Parameter (Show; neben Show(P)) zählt als eigene Liste.
  for Place in Candidates do
  begin
    if (Place.ParameterCount = ASource.ParameterCount) and (Place.Signature = ASource.Signature) then
    begin
      ATarget := Place;
      Exit;
    end;
  end;
  for Place in Candidates do
  begin
    if Place.ParameterCount = ASource.ParameterCount then
    begin
      ATarget := Place;
      Exit;
    end;
  end;
end;

class function TAtlasMethodToggle.Counterpart(const AText: string; ALine, ACharacter: Integer;
  out ATarget: TAtlasMethodPlace): Boolean;
begin
  Result := Counterpart(AText, ALine, ACharacter, ATarget, nil);
end;

class function TAtlasMethodToggle.Counterpart(const AText: string; ALine, ACharacter: Integer;
  out ATarget: TAtlasMethodPlace; const ADefines: TArray<string>): Boolean;
var
  All: TArray<TAtlasMethodPlace>;
  Source: TAtlasMethodPlace;
begin
  ATarget := Default(TAtlasMethodPlace);
  All := Places(AText, ADefines);
  Result := PlaceAt(All, ALine, ACharacter, Source) and Match(All, Source, ATarget);
end;

end.
