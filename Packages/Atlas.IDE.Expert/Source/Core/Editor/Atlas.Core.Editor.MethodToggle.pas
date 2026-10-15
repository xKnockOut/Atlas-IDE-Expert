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
    /// <summary>Alle Deklarationen und Implementierungen in AText, in Textreihenfolge.</summary>
    class function Places(const AText: string): TArray<TAtlasMethodPlace>; static;
    /// <summary>Stelle unter dem Cursor (Zeile, Zeichen); False außerhalb jedes Kopfs und Rumpfs.</summary>
    class function PlaceAt(const APlaces: TArray<TAtlasMethodPlace>; ALine, ACharacter: Integer;
      out APlace: TAtlasMethodPlace): Boolean; static;
    /// <summary>Gegenstück zu ASource unter APlaces; False, wenn es keins gibt.</summary>
    class function Match(const APlaces: TArray<TAtlasMethodPlace>; const ASource: TAtlasMethodPlace;
      out ATarget: TAtlasMethodPlace): Boolean; static;
    /// <summary>Gegenstück der Methode am Cursor: Deklaration ⇄ Implementierung.</summary>
    class function Counterpart(const AText: string; ALine, ACharacter: Integer;
      out ATarget: TAtlasMethodPlace): Boolean; static;
  end;

implementation

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
    function Run(const AText: string): TArray<TAtlasMethodPlace>;
  end;

function IsIdentStart(C: Char): Boolean;
begin
  Result := CharInSet(C, ['A'..'Z', 'a'..'z', '_']) or (Ord(C) > 127);
end;

function IsIdentChar(C: Char): Boolean;
begin
  Result := IsIdentStart(C) or CharInSet(C, ['0'..'9']);
end;

{ TParser }

procedure TParser.AddToken(const AText: string; AKind: TTokenKind; ALine, ACharacter: Integer; AEscaped: Boolean);
var
  Token: TToken;
begin
  Token.Text := AText;
  Token.Lower := LowerCase(AText);
  Token.Kind := AKind;
  Token.Line := ALine;
  Token.Character := ACharacter;
  Token.Escaped := AEscaped;
  Token.AfterDot := (FCount > 0) and (FTokens[FCount - 1].Kind = tkSymbol) and (FTokens[FCount - 1].Text = '.');
  if FCount = Length(FTokens) then
    SetLength(FTokens, 2 * FCount + 64);
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
        Exit(False);
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
      Inc(I)
    else if (C = '/') and (I < Len) and (AText[I + 1] = '/') then
    begin
      while (I <= Len) and (AText[I] <> #10) do
        Inc(I);
    end
    else if C = '{' then
    begin
      while (I <= Len) and (AText[I] <> '}') do
      begin
        if AText[I] = #10 then
          NewLine;
        Inc(I);
      end;
      Inc(I);
    end
    else if (C = '(') and (I < Len) and (AText[I + 1] = '*') then
    begin
      Inc(I, 2);
      while (I <= Len) and not ((AText[I] = '*') and (I < Len) and (AText[I + 1] = ')')) do
      begin
        if AText[I] = #10 then
          NewLine;
        Inc(I);
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
            NewLine;
          Inc(I);
        end;
        Inc(I, 3);
        while (I <= Len) and (AText[I] = '''') do
          Inc(I);
      end
      else
      begin
        Inc(I);
        while (I <= Len) and (AText[I] <> #10) do
        begin
          if AText[I] = '''' then
          begin
            if (I < Len) and (AText[I + 1] = '''') then
              Inc(I, 2)
            else
            begin
              Inc(I);
              Break;
            end;
          end
          else
            Inc(I);
        end;
      end;
      AddToken(Copy(AText, Start, I - Start), tkString, StartLine, StartChar, False);
    end
    else if C = '#' then
    begin
      Start := I;
      Inc(I);
      while (I <= Len) and (IsIdentChar(AText[I]) or (AText[I] = '$')) do
        Inc(I);
      AddToken(Copy(AText, Start, I - Start), tkString, Line, Start - LineStart, False);
    end
    else if IsIdentStart(C) or ((C = '&') and (I < Len) and IsIdentStart(AText[I + 1])) then
    begin
      Escaped := C = '&';
      if Escaped then
        Inc(I);
      Start := I;
      while (I <= Len) and IsIdentChar(AText[I]) do
        Inc(I);
      AddToken(Copy(AText, Start, I - Start), tkIdent, Line, Start - LineStart, Escaped);
    end
    else if CharInSet(C, ['0'..'9', '$', '%']) then
    begin
      Start := I;
      Inc(I);
      while (I <= Len) and (IsIdentChar(AText[I]) or
        ((AText[I] = '.') and (I < Len) and CharInSet(AText[I + 1], ['0'..'9']))) do
        Inc(I);
      AddToken(Copy(AText, Start, I - Start), tkNumber, Line, Start - LineStart, False);
    end
    else
    begin
      Start := I;
      if (I < Len) and (((C = ':') and (AText[I + 1] = '=')) or ((C = '.') and (AText[I + 1] = '.')) or
        ((C = '<') and CharInSet(AText[I + 1], ['=', '>'])) or ((C = '>') and (AText[I + 1] = '='))) then
        Inc(I, 2)
      else
        Inc(I);
      AddToken(Copy(AText, Start, I - Start), tkSymbol, Line, Start - LineStart, False);
    end;
  end;
end;

function TParser.Tok(AOffset: Integer): TToken;
begin
  if (FPos + AOffset >= 0) and (FPos + AOffset < FCount) then
    Result := FTokens[FPos + AOffset]
  else
    Result := FEof;
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
    for Word in Words do
      if Kw(0, Word) then
        Exit(True);
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
    Exit;
  // Ein Feld gleichen Namens (Message: string;) ist keine Direktive.
  if Sym(1, ':') or Sym(1, ',') or Sym(1, '=') then
    Exit;
  for Word in Words do
    if Token.Lower = Word then
      Exit(True);
end;

procedure TParser.SkipBrackets;
var
  Depth: Integer;
begin
  Depth := 0;
  while Tok(0).Kind <> tkEof do
  begin
    if Sym(0, '(') or Sym(0, '[') then
      Inc(Depth)
    else if Sym(0, ')') or Sym(0, ']') then
      Dec(Depth);
    Inc(FPos);
    if Depth <= 0 then
      Exit;
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
      Inc(Depth)
    else if Sym(0, '>') then
      Dec(Depth);
    Inc(FPos);
    if Depth <= 0 then
      Exit;
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
      Inc(Depth)
    else if Sym(0, ')') or Sym(0, ']') then
      Dec(Depth)
    else if Depth <= 0 then
    begin
      if Sym(0, ';') then
      begin
        Inc(FPos);
        Exit;
      end;
      // Letztes Feld vor end ohne Semikolon.
      if Kw(0, 'end') then
        Exit;
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
      SkipBrackets
    else
      SkipToSemicolon;
    if FPos = Before then
      Inc(FPos);
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
      Inc(Depth)
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
    SkipBrackets;
  if Kw(0, 'for') then
  begin
    Inc(FPos);
    if Tok(0).Kind = tkIdent then
      Inc(FPos);
    while Sym(0, '.') and (Tok(1).Kind = tkIdent) do
      Inc(FPos, 2);
    if Sym(0, '<') then
      SkipAngles;
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
      Exit;
    if not Typed then
      TypeText := '';
    for K := 1 to Names do
    begin
      if Result <> '' then
        Result := Result + ',';
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
        TypeText := TypeText + Token.Lower;
    end
    else if (Token.Kind = tkSymbol) and ((Token.Text = ')') or (Token.Text = ']') or (Token.Text = '>')) then
    begin
      Dec(Depth);
      if InType and not InDefault then
        TypeText := TypeText + Token.Lower;
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
      InDefault := True
    else if InType then
    begin
      if not InDefault then
        TypeText := TypeText + Token.Lower;
    end
    else if (Depth = 0) and (Token.Kind = tkIdent) and not ((Names = 0) and not Token.Escaped and
      ((Token.Lower = 'const') or (Token.Lower = 'var') or (Token.Lower = 'out') or (Token.Lower = 'constref'))) then
      Inc(Names);
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
    SkipAngles;
  while Sym(0, '.') and (Tok(1).Kind = tkIdent) do
  begin
    AHeading.Name := AHeading.Name + '.' + Tok(1).Text;
    AHeading.NameToken := FPos + 1;
    Inc(FPos, 2);
    if Sym(0, '<') then
      SkipAngles;
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
      AForward := True
    else if Kw(0, 'external') then
      AExternal := True;
    Before := FPos;
    SkipToSemicolon;
    if FPos = Before then
      Exit;
  end;
end;

procedure TParser.AddPlace(const AName: string; const AHeading: THeading; AFirst, ALast: Integer; AIsBody: Boolean);
var
  Place: TAtlasMethodPlace;
begin
  if (AHeading.NameToken < 0) or (AFirst < 0) or (AFirst >= FCount) then
    Exit;
  if ALast >= FCount then
    ALast := FCount - 1;
  if ALast < AFirst then
    ALast := AFirst;
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
    SetLength(FPlaces, 2 * FPlaceCount + 16);
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
      Exit
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
      // Lokale Routine: gehört zum Rumpf der umgebenden.
      ParseRoutine('', False, False)
    else
      Inc(FPos);
    if FPos = Before then
      Inc(FPos);
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
    Inc(FPos);
  if not ParseHeading(Heading) then
    Exit;
  SkipDirectives(IsForward, IsExternal);
  Name := Heading.Name;
  if AOwner <> '' then
    Name := AOwner + '.' + Name;
  if AInInterface or IsForward then
  begin
    if ACollect then
      AddPlace(Name, Heading, First, FPos - 1, False);
    Exit;
  end;
  if IsExternal then
    Exit;
  Last := ParseBlockBody;
  if ACollect then
    AddPlace(Name, Heading, First, Last, True);
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
      Exit;
    Path := Tok(0).Text;
    if AOwner <> '' then
      Path := AOwner + '.' + Path;
    Inc(FPos);
    if Sym(0, '<') then
      SkipAngles;
    if not Sym(0, '=') then
      Exit;
    Inc(FPos);
    if Kw(0, 'type') then
      Inc(FPos);
    if Kw(0, 'packed') then
      Inc(FPos);
    if Kw(0, 'class') then
    begin
      Inc(FPos);
      if Kw(0, 'of') or Sym(0, ';') then
        SkipToSemicolon
      else
      begin
        if Kw(0, 'helper') then
          SkipHelper;
        while Kw(0, 'abstract') or Kw(0, 'sealed') do
          Inc(FPos);
        if Sym(0, '(') then
          SkipBrackets;
        if Sym(0, ';') then
          Inc(FPos)
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
        SkipHelper;
      if Sym(0, '(') then
        SkipBrackets;
      ParseStruct(Path, ACollect);
      SkipToSemicolon;
    end
    else if Kw(0, 'interface') or Kw(0, 'dispinterface') then
    begin
      Inc(FPos);
      if Sym(0, '(') then
        SkipBrackets;
      if Sym(0, ';') then
        Inc(FPos)
      else
      begin
        if Sym(0, '[') then
          SkipBrackets;
        ParseStruct(Path, ACollect);
        SkipToSemicolon;
      end;
    end
    else
      SkipToSemicolon;
    if FPos = Before then
      Inc(FPos);
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
      SkipBrackets
    else if Kw(0, 'private') or Kw(0, 'protected') or Kw(0, 'public') or Kw(0, 'published') or
      Kw(0, 'automated') or Kw(0, 'strict') then
      Inc(FPos)
    else if IsRoutineStart then
      ParseRoutine(AOwner, True, ACollect)
    else if Kw(0, 'class') or Kw(0, 'var') or Kw(0, 'const') or Kw(0, 'threadvar') then
      Inc(FPos)
    else if Kw(0, 'property') then
    begin
      SkipToSemicolon;
      if Kw(0, 'default') and Sym(1, ';') then
        Inc(FPos, 2);
    end
    else if Kw(0, 'type') then
    begin
      Inc(FPos);
      ParseTypeSection(AOwner, ACollect);
    end
    else if Kw(0, 'case') then
    begin
      while (Tok(0).Kind <> tkEof) and not Kw(0, 'of') do
        Inc(FPos);
      Inc(FPos);
    end
    else
      SkipToSemicolon;
    if FPos = Before then
      Inc(FPos);
  end;
end;

function TParser.Run(const AText: string): TArray<TAtlasMethodPlace>;
var
  InInterface: Boolean;
  Before: Integer;
begin
  FEof.Kind := tkEof;
  FEof.Line := MaxInt;
  FPlaces := nil;
  FPlaceCount := 0;
  Lex(AText);
  FPos := 0;
  // Programme und Bibliotheken haben keinen interface-Teil.
  InInterface := False;
  while Tok(0).Kind <> tkEof do
  begin
    Before := FPos;
    if Kw(0, 'unit') or Kw(0, 'program') or Kw(0, 'library') or Kw(0, 'package') or Kw(0, 'uses') or
      Kw(0, 'contains') or Kw(0, 'requires') or Kw(0, 'exports') then
      SkipToSemicolon
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
      ParseRoutine('', InInterface, True)
    else if Kw(0, 'initialization') or Kw(0, 'finalization') or Kw(0, 'begin') or Kw(0, 'end') then
      Break
    else if Sym(0, '[') then
      SkipBrackets
    else
      Inc(FPos);
    if FPos = Before then
      Inc(FPos);
  end;
  SetLength(FPlaces, FPlaceCount);
  Result := FPlaces;
end;

{ TAtlasMethodToggle }

class function TAtlasMethodToggle.Places(const AText: string): TArray<TAtlasMethodPlace>;
var
  Parser: TParser;
begin
  Parser := TParser.Create;
  try
    Result := Parser.Run(AText);
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
      Continue;
    // Mehrere Köpfe in einer Zeile: der letzte, der vor dem Cursor beginnt.
    if Result and ((Place.FirstLine > ALine) or
      ((Place.FirstLine = ALine) and (Place.FirstCharacter > ACharacter))) then
      Continue;
    APlace := Place;
    Result := True;
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
    if (Place.IsBody <> ASource.IsBody) and SameText(Place.Name, ASource.Name) then
      Candidates := Candidates + [Place];
  if Length(Candidates) = 0 then
    Exit;
  Result := True;
  ATarget := Candidates[0];
  if Length(Candidates) = 1 then
    Exit;
  // Überladungen: auch die ohne Parameter (Show; neben Show(P)) zählt als eigene Liste.
  for Place in Candidates do
    if (Place.ParameterCount = ASource.ParameterCount) and (Place.Signature = ASource.Signature) then
    begin
      ATarget := Place;
      Exit;
    end;
  for Place in Candidates do
    if Place.ParameterCount = ASource.ParameterCount then
    begin
      ATarget := Place;
      Exit;
    end;
end;

class function TAtlasMethodToggle.Counterpart(const AText: string; ALine, ACharacter: Integer;
  out ATarget: TAtlasMethodPlace): Boolean;
var
  All: TArray<TAtlasMethodPlace>;
  Source: TAtlasMethodPlace;
begin
  ATarget := Default(TAtlasMethodPlace);
  All := Places(AText);
  Result := PlaceAt(All, ALine, ACharacter, Source) and Match(All, Source, ATarget);
end;

end.
