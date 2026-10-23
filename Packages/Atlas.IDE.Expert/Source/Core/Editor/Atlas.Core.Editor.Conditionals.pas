unit Atlas.Core.Editor.Conditionals;

// Bedingte Übersetzung für die eigenen Lexer des Plugins (#775 und folgende):
// Welche Zweige von $IFDEF, $IFNDEF, $IF, $ELSEIF, $ELSE und $ENDIF/$IFEND
// aktiv sind, mit $DEFINE und $UNDEF in aktiven Zweigen. Ohne diese Auswertung
// sahen die Lexer alle Zweige zugleich; stehen dort alternative Rümpfe
// ({$IFDEF MSWINDOWS} begin … end; {$ELSE} begin … end; {$ENDIF}), geriet der
// Aufbau durcheinander und der Methodenwechsel fand ab dort keine Routine mehr.
// $IF versteht Defined(X), Declared(X), CompilerVersion, RTLVersion, Zahlen,
// Vergleiche, not, and, or und Klammern; Unbekanntes gilt als wahr, $IFOPT als
// falsch. Je Bedingung ist genau ein Zweig aktiv, wie beim Compiler.
// Reine Logik ohne VCL und OTA; die Symbole bringt der Aufrufer mit
// (TTextDefines.Predefined und die Defines des Projekts).

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TAtlasConditionals = class
  private type
    TFrame = record
      ParentActive: Boolean;
      Taken: Boolean;
      Active: Boolean;
    end;
  private
    FDefines: TDictionary<string, Boolean>;
    FFrames: TList<TFrame>;
    FCompilerVersion: Double;
    function Evaluate(const AExpression: string): Boolean;
  public
    /// <summary>ADefines: gesetzte Symbole (Groß-/Kleinschreibung egal); ACompilerVersion z. B. 37.0.</summary>
    constructor Create(const ADefines: TArray<string>; ACompilerVersion: Double);
    destructor Destroy; override;
    /// <summary>Direktive ohne Klammern und ohne "$", z. B. "IFDEF FPC"; True, wenn sie die bedingte Übersetzung
    /// betrifft (dann ist sie verarbeitet).</summary>
    function Handle(const ADirective: string): Boolean;
    /// <summary>Liegt die aktuelle Stelle in einem aktiven Zweig?</summary>
    function Active: Boolean;
    /// <summary>Ist ASymbol gesetzt?</summary>
    function Defined(const ASymbol: string): Boolean;
    property CompilerVersion: Double read FCompilerVersion;
  end;

implementation

uses
  System.Character;

type
  TExprTokenKind = (etIdent, etNumber, etSymbol, etEnd);

  TExprToken = record
    Kind: TExprTokenKind;
    Text: string;
  end;

  /// <summary>Ausdruck hinter $IF bzw. $ELSEIF; rekursiver Abstieg über or, and, not und Vergleiche.</summary>
  TExprParser = class
  private
    FOwner: TAtlasConditionals;
    FTokens: TArray<TExprToken>;
    FPos: Integer;
    procedure Scan(const AText: string);
    function Peek: TExprToken;
    function Take: TExprToken;
    function IsWord(const AWord: string): Boolean;
    function IsSymbol(const ASymbol: string): Boolean;
    function ParseOr: Double;
    function ParseAnd: Double;
    function ParseNot: Double;
    function ParseCompare: Double;
    function ParseValue: Double;
  public
    constructor Create(AOwner: TAtlasConditionals; const AText: string);
    function Run: Boolean;
  end;

const
  /// <summary>Wert für Unbekanntes: gilt als wahr bzw. als erfüllter Vergleich.</summary>
  UnknownValue = 1.0;

function Truth(ACondition: Boolean): Double;
begin
  if ACondition then
    Result := 1
  else
    Result := 0;
end;

{ TExprParser }

constructor TExprParser.Create(AOwner: TAtlasConditionals; const AText: string);
begin
  inherited Create;
  FOwner := AOwner;
  Scan(AText);
  FPos := 0;
end;

procedure TExprParser.Scan(const AText: string);
var
  Index, Start: Integer;
  Token: TExprToken;
begin
  FTokens := nil;
  Index := 1;
  while Index <= Length(AText) do
  begin
    if AText[Index].IsWhiteSpace then
    begin
      Inc(Index);
      Continue;
    end;
    Start := Index;
    if AText[Index].IsLetter or (AText[Index] = '_') then
    begin
      while (Index <= Length(AText)) and (AText[Index].IsLetterOrDigit or CharInSet(AText[Index], ['_', '.'])) do
        Inc(Index);
      Token.Kind := etIdent;
    end
    else if AText[Index].IsDigit then
    begin
      while (Index <= Length(AText)) and (AText[Index].IsDigit or (AText[Index] = '.')) do
        Inc(Index);
      Token.Kind := etNumber;
    end
    else
    begin
      Inc(Index);
      if (Index <= Length(AText)) and CharInSet(AText[Start], ['<', '>']) and CharInSet(AText[Index], ['=', '>'])
        then
        Inc(Index);
      Token.Kind := etSymbol;
    end;
    Token.Text := Copy(AText, Start, Index - Start);
    FTokens := FTokens + [Token];
  end;
end;

function TExprParser.Peek: TExprToken;
begin
  if FPos <= High(FTokens) then
    Result := FTokens[FPos]
  else
  begin
    Result.Kind := etEnd;
    Result.Text := '';
  end;
end;

function TExprParser.Take: TExprToken;
begin
  Result := Peek;
  if FPos <= High(FTokens) then
    Inc(FPos);
end;

function TExprParser.IsWord(const AWord: string): Boolean;
begin
  Result := (Peek.Kind = etIdent) and SameText(Peek.Text, AWord);
end;

function TExprParser.IsSymbol(const ASymbol: string): Boolean;
begin
  Result := (Peek.Kind = etSymbol) and (Peek.Text = ASymbol);
end;

function TExprParser.Run: Boolean;
begin
  Result := ParseOr <> 0;
end;

function TExprParser.ParseOr: Double;
var
  Right: Double;
begin
  Result := ParseAnd;
  while IsWord('or') do
  begin
    Take;
    Right := ParseAnd;
    Result := Truth((Result <> 0) or (Right <> 0));
  end;
end;

function TExprParser.ParseAnd: Double;
var
  Right: Double;
begin
  Result := ParseNot;
  while IsWord('and') do
  begin
    Take;
    Right := ParseNot;
    Result := Truth((Result <> 0) and (Right <> 0));
  end;
end;

function TExprParser.ParseNot: Double;
begin
  if IsWord('not') then
  begin
    Take;
    Result := Truth(ParseNot = 0);
    Exit;
  end;
  Result := ParseCompare;
end;

function TExprParser.ParseCompare: Double;
var
  Op: string;
  Right: Double;
begin
  Result := ParseValue;
  if not (IsSymbol('=') or IsSymbol('<>') or IsSymbol('<') or IsSymbol('>') or IsSymbol('<=') or
    IsSymbol('>=')) then
    Exit;
  Op := Take.Text;
  Right := ParseValue;
  if Op = '=' then
    Result := Truth(Result = Right)
  else if Op = '<>' then
    Result := Truth(Result <> Right)
  else if Op = '<' then
    Result := Truth(Result < Right)
  else if Op = '>' then
    Result := Truth(Result > Right)
  else if Op = '<=' then
    Result := Truth(Result <= Right)
  else
    Result := Truth(Result >= Right);
end;

function TExprParser.ParseValue: Double;
var
  Token: TExprToken;
  Name: string;
begin
  Token := Take;
  Result := UnknownValue;
  case Token.Kind of
    etNumber:
      if not TryStrToFloat(Token.Text, Result, TFormatSettings.Invariant) then
        Result := UnknownValue;
    etIdent:
      if SameText(Token.Text, 'Defined') or SameText(Token.Text, 'Declared') then
      begin
        Name := '';
        if IsSymbol('(') then
        begin
          Take;
          while not ((Peek.Kind = etEnd) or IsSymbol(')')) do
            Name := Name + Take.Text;
          Take;
        end;
        // Declared kennt nur der Compiler: bleibt wahr.
        if SameText(Token.Text, 'Defined') then
          Result := Truth(FOwner.Defined(Name));
      end
      else if SameText(Token.Text, 'CompilerVersion') or SameText(Token.Text, 'RTLVersion') then
        Result := FOwner.CompilerVersion
      else if SameText(Token.Text, 'True') then
        Result := 1
      else if SameText(Token.Text, 'False') then
        Result := 0;
    etSymbol:
      if Token.Text = '(' then
      begin
        Result := ParseOr;
        if IsSymbol(')') then
          Take;
      end;
  else
    // Ende des Ausdrucks: bleibt unbekannt.
  end;
end;

{ TAtlasConditionals }

constructor TAtlasConditionals.Create(const ADefines: TArray<string>; ACompilerVersion: Double);
var
  Symbol: string;
begin
  inherited Create;
  FDefines := TDictionary<string, Boolean>.Create;
  FFrames := TList<TFrame>.Create;
  FCompilerVersion := ACompilerVersion;
  for Symbol in ADefines do
    if Trim(Symbol) <> '' then
      FDefines.AddOrSetValue(UpperCase(Trim(Symbol)), True);
end;

destructor TAtlasConditionals.Destroy;
begin
  FFrames.Free;
  FDefines.Free;
  inherited;
end;

function TAtlasConditionals.Defined(const ASymbol: string): Boolean;
begin
  Result := FDefines.ContainsKey(UpperCase(Trim(ASymbol)));
end;

function TAtlasConditionals.Active: Boolean;
begin
  Result := (FFrames.Count = 0) or FFrames.Last.Active;
end;

function TAtlasConditionals.Evaluate(const AExpression: string): Boolean;
var
  Parser: TExprParser;
begin
  Parser := TExprParser.Create(Self, AExpression);
  try
    Result := Parser.Run;
  finally
    Parser.Free;
  end;
end;

function TAtlasConditionals.Handle(const ADirective: string): Boolean;
var
  Text, Name, Argument: string;
  Split: Integer;
  Frame: TFrame;
  Condition: Boolean;
begin
  Text := Trim(ADirective);
  Split := 1;
  while (Split <= Length(Text)) and (Text[Split].IsLetterOrDigit or (Text[Split] = '_')) do
    Inc(Split);
  Name := UpperCase(Copy(Text, 1, Split - 1));
  Argument := Trim(Copy(Text, Split, MaxInt));
  Result := True;
  if (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IF') or (Name = 'IFOPT') then
  begin
    Frame.ParentActive := Active;
    Condition := False;
    if Frame.ParentActive then
      if Name = 'IFDEF' then
        Condition := Defined(Argument)
      else if Name = 'IFNDEF' then
        Condition := not Defined(Argument)
      else if Name = 'IF' then
        Condition := Evaluate(Argument);
    Frame.Active := Frame.ParentActive and Condition;
    Frame.Taken := Frame.Active;
    FFrames.Add(Frame);
  end
  else if (Name = 'ELSEIF') and (FFrames.Count > 0) then
  begin
    Frame := FFrames.Last;
    Frame.Active := Frame.ParentActive and not Frame.Taken and Evaluate(Argument);
    Frame.Taken := Frame.Taken or Frame.Active;
    FFrames[FFrames.Count - 1] := Frame;
  end
  else if (Name = 'ELSE') and (FFrames.Count > 0) then
  begin
    Frame := FFrames.Last;
    Frame.Active := Frame.ParentActive and not Frame.Taken;
    Frame.Taken := True;
    FFrames[FFrames.Count - 1] := Frame;
  end
  else if (Name = 'ENDIF') or (Name = 'IFEND') then
  begin
    if FFrames.Count > 0 then
      FFrames.Delete(FFrames.Count - 1);
  end
  else if Name = 'DEFINE' then
  begin
    if Active and (Argument <> '') then
      FDefines.AddOrSetValue(UpperCase(Argument), True);
  end
  else if Name = 'UNDEF' then
  begin
    if Active then
      FDefines.Remove(UpperCase(Argument));
  end
  else
    Result := False;
end;

end.
