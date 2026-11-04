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

  TParser = class
  private
    FTokens: TArray<TToken>;
    FCount: Integer;
    FPos: Integer;
    FEof: TToken;
    FPlaces: TArray<TAtlasMethodPlace>;
    FPlaceCount: Integer;
    FConditionals: TAtlasConditionals;
    procedure Lex(const AText: string);
    procedure AddToken(const AText: string; AKind: TTokenKind; ALine, ACharacter: Integer; AEscaped: Boolean);
    function Tok(AOffset: Integer): TToken;
    function Kw(AOffset: Integer; const AWord: string): Boolean;
    function Sym(AOffset: Integer; const ASymbol: string): Boolean;
    function IsRoutineWord(AOffset: Integer): Boolean;
    function IsRoutineStart: Boolean;
    function IsSectionEnd: Boolean;
    function IsDirective: Boolean;
    procedure SkipBrackets;
    procedure SkipAngles;
    procedure SkipToSemicolon;
    procedure SkipDeclarations;
    procedure SkipCompound;
    procedure SkipHelper;
    function ParseHeading(out AHeading: THeading): Boolean;
    procedure SkipDirectives(out AForward, AExternal: Boolean);
    function Signature(AFirst, ALast: Integer; out ACount: Integer): string;
    function ParseBlockBody: Integer;
    procedure ParseTypeSection(const AOwner: string; ACollect: Boolean);
    procedure ParseStruct(const AOwner: string; ACollect: Boolean);
    procedure ParseRoutine(const AOwner: string; AInInterface, ACollect: Boolean);
    procedure AddPlace(const AName: string; const AHeading: THeading; AFirst, ALast: Integer; AIsBody: Boolean);
  public
    function Run(const AText: string; const ADefines: TArray<string>): TArray<TAtlasMethodPlace>;
  end;

{ TParser }

procedure TParser.AddToken(const AText: string; AKind: TTokenKind; ALine, ACharacter: Integer; AEscaped: Boolean);
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

procedure TParser.Lex(const AText: string);
var
  I, Len, Line, LineStart, Start, StartLine, StartChar: Integer;
  C: Char;
  Escaped: Boolean;

  procedure NewLine;
  begin
    Inc(Line);
    LineStart := I + 1;
  end;

  function RestOfLineBlank(AFrom: Integer): Boolean;
  var
    K: Integer;
  begin
    Result := True;
    K := AFrom;
    while (K <= Len) and (AText[K] <> #10) do
    begin
      if not CharInSet(AText[K], [' ', #9, #13]) then
      begin
        Exit(False);
      end;
      Inc(K);
    end;
  end;

begin
  FTokens := nil;
  FCount := 0;
  Len := Length(AText);
  Line := 0;
  LineStart := 1;
  I := 1;
  while I <= Len do
  begin
    C := AText[I];
    if C = #10 then
    begin
      NewLine;
      Inc(I);
    end
    else if CharInSet(C, [' ', #9, #13, #12]) then
    begin
      Inc(I);
    end
    else if (C = '/') and (I < Len) and (AText[I + 1] = '/') then
    begin
      while (I <= Len) and (AText[I] <> #10) do
      begin
        Inc(I);
      end;
    end
    else if C = '{' then
    begin
      Start := I;
      while (I <= Len) and (AText[I] <> '}') do
      begin
        if AText[I] = #10 then
        begin
          NewLine;
        end;
        Inc(I);
      end;
      if (Start < Len) and (AText[Start + 1] = '$') then
      begin
        FConditionals.Handle(Copy(AText, Start + 2, I - Start - 2));
      end;
      Inc(I);
    end
    else if (C = '(') and (I < Len) and (AText[I + 1] = '*') then
    begin
      Start := I;
      Inc(I, 2);
      while (I <= Len) and not ((AText[I] = '*') and (I < Len) and (AText[I + 1] = ')')) do
      begin
        if AText[I] = #10 then
        begin
          NewLine;
        end;
        Inc(I);
      end;
      if (Start + 2 <= Len) and (AText[Start + 2] = '$') then
      begin
        FConditionals.Handle(Copy(AText, Start + 3, I - Start - 3));
      end;
      Inc(I, 2);
    end
    else if C = '''' then
    begin
      StartLine := Line;
      StartChar := I - LineStart;
      Start := I;
      if (I + 2 <= Len) and (AText[I + 1] = '''') and (AText[I + 2] = '''') and RestOfLineBlank(I + 3) then
      begin
        // Mehrzeiliger String (Delphi 12): bis zur nächsten Zeile mit '''.
        Inc(I, 3);
        while (I <= Len) and not ((AText[I] = '''') and (I + 2 <= Len) and (AText[I + 1] = '''') and
          (AText[I + 2] = '''')) do
        begin
          if AText[I] = #10 then
          begin
            NewLine;
          end;
          Inc(I);
        end;
        Inc(I, 3);
        while (I <= Len) and (AText[I] = '''') do
        begin
          Inc(I);
        end;
      end
      else
      begin
        Inc(I);
        while (I <= Len) and (AText[I] <> #10) do
        begin
          if AText[I] = '''' then
          begin
            if (I < Len) and (AText[I + 1] = '''') then
            begin
              Inc(I, 2);
            end
            else
            begin
              Inc(I);
              Break;
            end;
          end
          else
          begin
            Inc(I);
          end;
        end;
      end;
      AddToken(Copy(AText, Start, I - Start), tkString, StartLine, StartChar, False);
    end
    else if C = '#' then
    begin
      Start := I;
      Inc(I);
      while (I <= Len) and (TTextChars.IsIdentChar(AText[I]) or (AText[I] = '$')) do
      begin
        Inc(I);
      end;
      AddToken(Copy(AText, Start, I - Start), tkString, Line, Start - LineStart, False);
    end
    else if TTextChars.IsIdentStart(C) or ((C = '&') and (I < Len) and TTextChars.IsIdentStart(AText[I + 1])) then
    begin
      // &begin und Sprungmarken wie @@End (#861) sind keine Schlüsselwörter.
      Escaped := (C = '&') or (I > 1) and (AText[I - 1] = '@');
      if C = '&' then
      begin
        Inc(I);
      end;
      Start := I;
      while (I <= Len) and TTextChars.IsIdentChar(AText[I]) do
      begin
        Inc(I);
      end;
      AddToken(Copy(AText, Start, I - Start), tkIdent, Line, Start - LineStart, Escaped);
    end
    else if CharInSet(C, ['0'..'9', '$', '%']) then
    begin
      Start := I;
      Inc(I);
      while (I <= Len) and (TTextChars.IsIdentChar(AText[I]) or
        ((AText[I] = '.') and (I < Len) and CharInSet(AText[I + 1], ['0'..'9']))) do
      begin
        Inc(I);
      end;
      AddToken(Copy(AText, Start, I - Start), tkNumber, Line, Start - LineStart, False);
    end
    else
    begin
      Start := I;
      if (I < Len) and (((C = ':') and (AText[I + 1] = '=')) or ((C = '.') and (AText[I + 1] = '.')) or
        ((C = '<') and CharInSet(AText[I + 1], ['=', '>'])) or ((C = '>') and (AText[I + 1] = '='))) then
      begin
        Inc(I, 2);
      end
      else
      begin
        Inc(I);
      end;
      AddToken(Copy(AText, Start, I - Start), tkSymbol, Line, Start - LineStart, False);
    end;
  end;
end;

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

function TParser.IsRoutineWord(AOffset: Integer): Boolean;
begin
  Result := Kw(AOffset, 'procedure') or Kw(AOffset, 'function') or Kw(AOffset, 'constructor') or
    Kw(AOffset, 'destructor') or Kw(AOffset, 'operator');
end;

function TParser.IsRoutineStart: Boolean;
begin
  Result := IsRoutineWord(0) or (Kw(0, 'class') and IsRoutineWord(1));
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

procedure TParser.SkipToSemicolon;
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
    end
    else if Depth <= 0 then
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
  Index, Depth, Names: Integer;
  Token: TToken;
  TypeText: string;
  InType, InDefault, Typed: Boolean;

  procedure Flush;
  var
    K: Integer;
  begin
    if Names = 0 then
    begin
      Exit;
    end;
    if not Typed then
    begin
      TypeText := '';
    end;
    for K := 1 to Names do
    begin
      if Result <> '' then
      begin
        Result := Result + ',';
      end;
      Result := Result + TypeText;
      Inc(ACount);
    end;
  end;

begin
  Result := '';
  ACount := 0;
  Depth := 0;
  Names := 0;
  TypeText := '';
  InType := False;
  InDefault := False;
  Typed := False;
  Index := AFirst;
  while Index <= ALast do
  begin
    Token := FTokens[Index];
    if (Token.Kind = tkSymbol) and ((Token.Text = '(') or (Token.Text = '[') or (Token.Text = '<')) then
    begin
      Inc(Depth);
      if InType and not InDefault then
      begin
        TypeText := TypeText + Token.Lower;
      end;
    end
    else if (Token.Kind = tkSymbol) and ((Token.Text = ')') or (Token.Text = ']') or (Token.Text = '>')) then
    begin
      Dec(Depth);
      if InType and not InDefault then
      begin
        TypeText := TypeText + Token.Lower;
      end;
    end
    else if (Depth = 0) and (Token.Kind = tkSymbol) and (Token.Text = ';') then
    begin
      Flush;
      Names := 0;
      TypeText := '';
      InType := False;
      InDefault := False;
      Typed := False;
    end
    else if (Depth = 0) and (Token.Kind = tkSymbol) and (Token.Text = ':') and not InType then
    begin
      InType := True;
      Typed := True;
    end
    else if (Depth = 0) and (Token.Kind = tkSymbol) and (Token.Text = '=') and InType then
    begin
      InDefault := True;
    end
    else if InType then
    begin
      if not InDefault then
      begin
        TypeText := TypeText + Token.Lower;
      end;
    end
    else if (Depth = 0) and (Token.Kind = tkIdent) and not ((Names = 0) and not Token.Escaped and
      ((Token.Lower = 'const') or (Token.Lower = 'var') or (Token.Lower = 'out') or (Token.Lower = 'constref'))) then
    begin
      Inc(Names);
    end;
    Inc(Index);
  end;
  Flush;
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

procedure TParser.ParseTypeSection(const AOwner: string; ACollect: Boolean);
var
  Path: string;
  Before: Integer;
begin
  while Tok(0).Kind <> tkEof do
  begin
    Before := FPos;
    if Sym(0, '[') then
    begin
      SkipBrackets;
      Continue;
    end;
    if (Tok(0).Kind <> tkIdent) or not (Sym(1, '=') or Sym(1, '<')) then
    begin
      Exit;
    end;
    Path := Tok(0).Text;
    if AOwner <> '' then
    begin
      Path := AOwner + '.' + Path;
    end;
    Inc(FPos);
    if Sym(0, '<') then
    begin
      SkipAngles;
    end;
    if not Sym(0, '=') then
    begin
      Exit;
    end;
    Inc(FPos);
    if Kw(0, 'type') then
    begin
      Inc(FPos);
    end;
    if Kw(0, 'packed') then
    begin
      Inc(FPos);
    end;
    if Kw(0, 'class') then
    begin
      Inc(FPos);
      if Kw(0, 'of') or Sym(0, ';') then
      begin
        SkipToSemicolon;
      end
      else
      begin
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
          ParseStruct(Path, ACollect);
          SkipToSemicolon;
        end;
      end;
    end
    else if Kw(0, 'record') or Kw(0, 'object') then
    begin
      Inc(FPos);
      if Kw(0, 'helper') then
      begin
        SkipHelper;
      end;
      if Sym(0, '(') then
      begin
        SkipBrackets;
      end;
      ParseStruct(Path, ACollect);
      SkipToSemicolon;
    end
    else if Kw(0, 'interface') or Kw(0, 'dispinterface') then
    begin
      Inc(FPos);
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
        if Sym(0, '[') then
        begin
          SkipBrackets;
        end;
        ParseStruct(Path, ACollect);
        SkipToSemicolon;
      end;
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

procedure TParser.ParseStruct(const AOwner: string; ACollect: Boolean);
var
  Before: Integer;
begin
  while Tok(0).Kind <> tkEof do
  begin
    Before := FPos;
    if Kw(0, 'end') then
    begin
      Inc(FPos);
      Exit;
    end
    else if Sym(0, '[') then
    begin
      SkipBrackets;
    end
    else if Kw(0, 'private') or Kw(0, 'protected') or Kw(0, 'public') or Kw(0, 'published') or
      Kw(0, 'automated') or Kw(0, 'strict') then
    begin
      Inc(FPos);
    end
    else if IsRoutineStart then
    begin
      ParseRoutine(AOwner, True, ACollect);
    end
    else if Kw(0, 'class') or Kw(0, 'var') or Kw(0, 'const') or Kw(0, 'threadvar') then
    begin
      Inc(FPos);
    end
    else if Kw(0, 'property') then
    begin
      SkipToSemicolon;
      if Kw(0, 'default') and Sym(1, ';') then
      begin
        Inc(FPos, 2);
      end;
    end
    else if Kw(0, 'type') then
    begin
      Inc(FPos);
      ParseTypeSection(AOwner, ACollect);
    end
    else if Kw(0, 'case') then
    begin
      while (Tok(0).Kind <> tkEof) and not Kw(0, 'of') do
      begin
        Inc(FPos);
      end;
      Inc(FPos);
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

function TParser.Run(const AText: string; const ADefines: TArray<string>): TArray<TAtlasMethodPlace>;
var
  InInterface: Boolean;
  Before: Integer;
  Defines: TArray<string>;
begin
  FEof.Kind := tkEof;
  FEof.Line := MaxInt;
  FPlaces := nil;
  FPlaceCount := 0;
  Defines := ADefines;
  if Defines = nil then
  begin
    Defines := TTextDefines.Predefined('Win32', CompilerVersion);
  end;
  FConditionals := TAtlasConditionals.Create(Defines, CompilerVersion);
  try
    Lex(AText);
  finally
    FreeAndNil(FConditionals);
  end;
  FPos := 0;
  // Programme und Bibliotheken haben keinen interface-Teil.
  InInterface := False;
  while Tok(0).Kind <> tkEof do
  begin
    Before := FPos;
    if Kw(0, 'unit') or Kw(0, 'program') or Kw(0, 'library') or Kw(0, 'package') or Kw(0, 'uses') or
      Kw(0, 'contains') or Kw(0, 'requires') or Kw(0, 'exports') then
    begin
      SkipToSemicolon;
    end
    else if Kw(0, 'interface') then
    begin
      InInterface := True;
      Inc(FPos);
    end
    else if Kw(0, 'implementation') then
    begin
      InInterface := False;
      Inc(FPos);
    end
    else if Kw(0, 'type') then
    begin
      Inc(FPos);
      ParseTypeSection('', True);
    end
    else if Kw(0, 'var') or Kw(0, 'const') or Kw(0, 'threadvar') or Kw(0, 'resourcestring') or Kw(0, 'label') then
    begin
      Inc(FPos);
      SkipDeclarations;
    end
    else if IsRoutineStart then
    begin
      ParseRoutine('', InInterface, True);
    end
    else if Kw(0, 'initialization') or Kw(0, 'finalization') or Kw(0, 'begin') or Kw(0, 'end') then
    begin
      Break;
    end
    else if Sym(0, '[') then
    begin
      SkipBrackets;
    end
    else
    begin
      Inc(FPos);
    end;
    if FPos = Before then
    begin
      Inc(FPos);
    end;
  end;
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
