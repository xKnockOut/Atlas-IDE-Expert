unit Atlas.Common.Pascal.Preprocessor;

// Präprozessor für Object Pascal: bedingte Kompilierung und Include-Dateien.
//
// - Arbeitet auf den Token des Lexers. Ergebnis sind die aktiven Token in
//   Reihenfolge; Token aus Include-Dateien behalten ihre Positionen in ihrer
//   eigenen Datei, FileIndexes sagt, aus welcher Datei jedes Token stammt.
// - Unterstützt $IFDEF, $IFNDEF, $IF, $ELSEIF, $ELSE, $ENDIF, $IFEND, $IFOPT,
//   $DEFINE, $UNDEF und $I/$INCLUDE. $I+ und $I- sind Schalter, keine Includes.
// - $IF-Ausdrücke: Defined, Declared, CompilerVersion, RTLVersion, Zahlen,
//   Konstanten aus den Optionen, Vergleiche, and/or/xor/not, Klammern.
// - Bricht nie ab; Fehler (fehlendes $ENDIF, unbekannte Include-Datei,
//   kaputter Ausdruck) landen in Issues.
// - Inaktive Bereiche werden für das Abblenden im Editor (#23) gesammelt.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Sucht eine Include-Datei; AFromFile ist die einbindende Datei ('' = Hauptdatei).</summary>
  TIncludeResolver = reference to function(const AName, AFromFile: string;
    out AFileName, AText: string): Boolean;

  /// <summary>Beantwortet Declared(X); ohne Callback gilt False.</summary>
  TDeclaredFunc = reference to function(const AName: string): Boolean;

  TPreprocessorOptions = record
    Defines: TArray<string>;
    CompilerVersion: Double;
    RTLVersion: Double;
    /// <summary>Weitere Konstanten für $IF als Name=Wert.</summary>
    Constants: TArray<TPair<string, Double>>;
    FileName: string;
    ResolveInclude: TIncludeResolver;
    Declared: TDeclaredFunc;
    MaxIncludeDepth: Integer;
    class function Default: TPreprocessorOptions; static;
  end;

  /// <summary>Art eines Präprozessor-Befunds; Include-Probleme werden in Diagnosen unterschieden (#264).</summary>
  TPreprocessorIssueKind = (General, IncludeMissing, IncludeCycle);

  TPreprocessorIssue = record
    Kind: TPreprocessorIssueKind;
    FileIndex: Integer;
    Range: TTextRange;
    /// <summary>Bereich der $I-Direktive in der Hauptdatei, über die der Befund erreicht wurde;
    /// bei FileIndex = 0 gleich Range.</summary>
    RootRange: TTextRange;
    Message: string;
  end;

  TInactiveRange = record
    FileIndex: Integer;
    Range: TTextRange;
  end;

  TPreprocessorResult = record
    /// <summary>Aktive Token ohne die verarbeiteten Direktiven.</summary>
    Tokens: TArray<TPascalToken>;
    /// <summary>Je Token der Index in Files.</summary>
    FileIndexes: TArray<Integer>;
    /// <summary>Files[0] ist die Hauptdatei, danach die Include-Dateien.</summary>
    Files: TArray<string>;
    InactiveRanges: TArray<TInactiveRange>;
    Issues: TArray<TPreprocessorIssue>;
    /// <summary>Symbole am Ende der Datei (nach $DEFINE/$UNDEF).</summary>
    Defines: TArray<string>;
  end;

  TPascalPreprocessor = record
  public
    class function Process(const AText: string; const AOptions: TPreprocessorOptions): TPreprocessorResult; static;
    /// <summary>Vordefinierte Symbole für Plattform und Compilerversion (z. B. Win64, 37.0).</summary>
    class function PredefinedSymbols(const APlatform: string; ACompilerVersion: Double): TArray<string>; static;
    /// <summary>Compilerversion zur BDS-Version der Registry: bis Delphi 12 (BDS 23.0) BDS + 13,
    /// z. B. 23.0 -> 36.0; ab Delphi 13 gleich (37.0). 0 für unbekannte Werte.</summary>
    class function CompilerVersionOfBds(ABdsVersion: Double): Double; static;
    /// <summary>Compilerversion aus einem Symbol VERnnn in ADefines (VER360 -> 36.0); 0 ohne.</summary>
    class function CompilerVersionFromDefines(const ADefines: TArray<string>): Double; static;
    /// <summary>Wertet einen $IF-Ausdruck aus; False und AError bei Fehlern.</summary>
    class function Evaluate(const AExpression: string; const AOptions: TPreprocessorOptions;
      const ADefines: TArray<string>; out AError: string): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Pascal.Lexer;

type
  EPreprocessorExpression = class(Exception);

  TBranchState = record
    ParentActive: Boolean;
    Taken: Boolean;
    Active: Boolean;
    InElse: Boolean;
  end;

  /// <summary>Rekursiv absteigender Auswerter für $IF-Ausdrücke.</summary>
  TExpressionEvaluator = class
  private
    FTokens: TArray<TPascalToken>;
    FIndex: Integer;
    FOptions: TPreprocessorOptions;
    FDefines: TDictionary<string, Boolean>;
    function Peek: TPascalToken;
    function AtEnd: Boolean;
    function Next: TPascalToken;
    procedure Expect(const ASymbol: string);
    function IsWord(const AWord: string): Boolean;
    function ParseOr: Double;
    function ParseAnd: Double;
    function ParseComparison: Double;
    function ParseAdditive: Double;
    function ParseMultiplicative: Double;
    function ParseUnary: Double;
    function ParsePrimary: Double;
    function ReadName: string;
  public
    constructor Create(const AOptions: TPreprocessorOptions; ADefines: TDictionary<string, Boolean>);
    function Evaluate(const AExpression: string): Boolean;
  end;

  TPreprocessorRun = class
  private
    FOptions: TPreprocessorOptions;
    FDefines: TDictionary<string, Boolean>;
    FTokens: TList<TPascalToken>;
    FFileIndexes: TList<Integer>;
    FFiles: TList<string>;
    FInactive: TList<TInactiveRange>;
    FIssues: TList<TPreprocessorIssue>;
    FIncludeStack: TList<string>;
    // $I-Direktive der Hauptdatei, die gerade verarbeitet wird.
    FRootRange: TTextRange;
    procedure AddIssue(AFileIndex: Integer; const AToken: TPascalToken; const AMessage: string;
      AKind: TPreprocessorIssueKind = TPreprocessorIssueKind.General);
    procedure ProcessText(const AText: string; AFileIndex, ADepth: Integer);
    procedure Include(const AName: string; AFileIndex, ADepth: Integer; const AToken: TPascalToken);
    function EvaluateCondition(const AExpression: string; AFileIndex: Integer; const AToken: TPascalToken): Boolean;
  public
    constructor Create(const AOptions: TPreprocessorOptions);
    destructor Destroy; override;
    function Run(const AText: string): TPreprocessorResult;
  end;

const
  BooleanValue: array[Boolean] of Double = (0, 1);

function DirectiveBody(const AText: string): string;
begin
  // '{$IFDEF X}' bzw. '(*$IFDEF X*)' → 'IFDEF X'
  if (Length(AText) >= 2) and (AText[1] = '{') then
  begin
    Result := Copy(AText, 3, MaxInt);
    if (Result <> '') and (Result[Length(Result)] = '}') then
      Delete(Result, Length(Result), 1);
  end
  else
  begin
    Result := Copy(AText, 4, MaxInt);
    if (Length(Result) >= 2) and (Copy(Result, Length(Result) - 1, 2) = '*)') then
      Delete(Result, Length(Result) - 1, 2);
  end;
  Result := Trim(Result);
end;

procedure SplitDirective(const ABody: string; out AName, AArgument: string);
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(ABody)) and CharInSet(ABody[I], ['A'..'Z', 'a'..'z', '0'..'9', '_']) do
    Inc(I);
  AName := UpperCase(Copy(ABody, 1, I - 1));
  AArgument := Trim(Copy(ABody, I, MaxInt));
end;

function FirstWord(const AArgument: string): string;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(AArgument)) and CharInSet(AArgument[I], ['A'..'Z', 'a'..'z', '0'..'9', '_', '.']) do
    Inc(I);
  Result := Copy(AArgument, 1, I - 1);
end;

function IncludeName(const AArgument: string): string;
var
  Stop: Integer;
begin
  Result := Trim(AArgument);
  if (Result <> '') and (Result[1] = '''') then
  begin
    Stop := Pos('''', Copy(Result, 2, MaxInt));
    if Stop > 0 then
      Result := Copy(Result, 2, Stop - 1)
    else
      Result := Copy(Result, 2, MaxInt);
  end
  else
  begin
    Stop := Pos(' ', Result);
    if Stop > 0 then
      Result := Copy(Result, 1, Stop - 1);
  end;
end;

function IsSwitch(const AArgument: string): Boolean;
begin
  // {$I+} / {$I-}: E/A-Prüfung, kein Include.
  Result := (AArgument = '+') or (AArgument = '-') or
    ((Length(AArgument) >= 1) and CharInSet(AArgument[1], ['+', '-']) and
     ((Length(AArgument) = 1) or (AArgument[2] = ',') or (AArgument[2] = ' ')));
end;

{ TPreprocessorOptions }

class function TPreprocessorOptions.Default: TPreprocessorOptions;
begin
  Result.Defines := nil;
  Result.CompilerVersion := 0;
  Result.RTLVersion := 0;
  Result.Constants := nil;
  Result.FileName := '';
  Result.ResolveInclude := nil;
  Result.Declared := nil;
  Result.MaxIncludeDepth := 16;
end;

{ TExpressionEvaluator }

constructor TExpressionEvaluator.Create(const AOptions: TPreprocessorOptions; ADefines: TDictionary<string, Boolean>);
begin
  inherited Create;
  FOptions := AOptions;
  FDefines := ADefines;
end;

function TExpressionEvaluator.AtEnd: Boolean;
begin
  Result := FIndex >= Length(FTokens);
end;

function TExpressionEvaluator.Peek: TPascalToken;
begin
  if AtEnd then
  begin
    Result := Default(TPascalToken);
    Result.Kind := TPascalTokenKind.Unknown;
  end
  else
    Result := FTokens[FIndex];
end;

function TExpressionEvaluator.Next: TPascalToken;
begin
  if AtEnd then
    raise EPreprocessorExpression.Create('Ausdruck endet unerwartet');
  Result := FTokens[FIndex];
  Inc(FIndex);
end;

procedure TExpressionEvaluator.Expect(const ASymbol: string);
begin
  if AtEnd or not Peek.IsSymbol(ASymbol) then
    raise EPreprocessorExpression.CreateFmt('"%s" erwartet', [ASymbol]);
  Inc(FIndex);
end;

function TExpressionEvaluator.IsWord(const AWord: string): Boolean;
begin
  Result := not AtEnd and (Peek.Kind in [TPascalTokenKind.Keyword, TPascalTokenKind.Identifier]) and
    SameText(Peek.Text, AWord);
end;

function TExpressionEvaluator.ReadName: string;
begin
  if AtEnd or not (Peek.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
    raise EPreprocessorExpression.Create('Name erwartet');
  Result := Next.Text;
  // Qualifizierte Namen wie System.SysUtils
  while not AtEnd and Peek.IsSymbol('.') do
  begin
    Inc(FIndex);
    if AtEnd or not (Peek.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
      raise EPreprocessorExpression.Create('Name erwartet');
    Result := Result + '.' + Next.Text;
  end;
end;

function TExpressionEvaluator.Evaluate(const AExpression: string): Boolean;
var
  Significant: TList<TPascalToken>;
  Token: TPascalToken;
begin
  Significant := TList<TPascalToken>.Create;
  try
    for Token in TPascalLexer.Tokenize(AExpression) do
      if Token.Kind <> TPascalTokenKind.Comment then
        Significant.Add(Token);
    FTokens := Significant.ToArray;
  finally
    Significant.Free;
  end;
  FIndex := 0;
  if AtEnd then
    raise EPreprocessorExpression.Create('Ausdruck fehlt');
  Result := ParseOr <> 0;
  if not AtEnd then
    raise EPreprocessorExpression.CreateFmt('Unerwartet: "%s"', [Peek.Text]);
end;

function TExpressionEvaluator.ParseOr: Double;
var
  Right: Double;
begin
  Result := ParseAnd;
  while IsWord('or') or IsWord('xor') do
  begin
    if IsWord('or') then
    begin
      Inc(FIndex);
      Right := ParseAnd;
      Result := BooleanValue[(Result <> 0) or (Right <> 0)];
    end
    else
    begin
      Inc(FIndex);
      Right := ParseAnd;
      Result := BooleanValue[(Result <> 0) xor (Right <> 0)];
    end;
  end;
end;

function TExpressionEvaluator.ParseAnd: Double;
var
  Right: Double;
begin
  Result := ParseComparison;
  while IsWord('and') do
  begin
    Inc(FIndex);
    Right := ParseComparison;
    Result := BooleanValue[(Result <> 0) and (Right <> 0)];
  end;
end;

function TExpressionEvaluator.ParseComparison: Double;
var
  Op: string;
  Right: Double;
begin
  Result := ParseAdditive;
  if not AtEnd and (Peek.Kind = TPascalTokenKind.Symbol) then
  begin
    Op := Peek.Text;
    if (Op = '=') or (Op = '<>') or (Op = '<') or (Op = '>') or (Op = '<=') or (Op = '>=') then
    begin
      Inc(FIndex);
      Right := ParseAdditive;
      if Op = '=' then
        Result := BooleanValue[Result = Right]
      else if Op = '<>' then
        Result := BooleanValue[Result <> Right]
      else if Op = '<' then
        Result := BooleanValue[Result < Right]
      else if Op = '>' then
        Result := BooleanValue[Result > Right]
      else if Op = '<=' then
        Result := BooleanValue[Result <= Right]
      else
        Result := BooleanValue[Result >= Right];
    end;
  end;
end;

function TExpressionEvaluator.ParseAdditive: Double;
begin
  Result := ParseMultiplicative;
  while not AtEnd and (Peek.IsSymbol('+') or Peek.IsSymbol('-')) do
    if Next.Text = '+' then
      Result := Result + ParseMultiplicative
    else
      Result := Result - ParseMultiplicative;
end;

function TExpressionEvaluator.ParseMultiplicative: Double;
var
  Right: Double;
begin
  Result := ParseUnary;
  while not AtEnd and (Peek.IsSymbol('*') or IsWord('div')) do
    if Next.Text = '*' then
      Result := Result * ParseUnary
    else
    begin
      Right := ParseUnary;
      if Right = 0 then
        raise EPreprocessorExpression.Create('Division durch null');
      Result := Trunc(Result) div Trunc(Right);
    end;
end;

function TExpressionEvaluator.ParseUnary: Double;
begin
  if IsWord('not') then
  begin
    Inc(FIndex);
    Result := BooleanValue[ParseUnary = 0];
  end
  else if not AtEnd and Peek.IsSymbol('-') then
  begin
    Inc(FIndex);
    Result := -ParseUnary;
  end
  else
    Result := ParsePrimary;
end;

function TExpressionEvaluator.ParsePrimary: Double;
var
  Token: TPascalToken;
  Name: string;
  Pair: TPair<string, Double>;
begin
  Token := Peek;
  if Token.IsSymbol('(') then
  begin
    Inc(FIndex);
    Result := ParseOr;
    Expect(')');
    Exit;
  end;
  if Token.Kind = TPascalTokenKind.Number then
  begin
    Inc(FIndex);
    if not TryStrToFloat(Token.Text, Result, TFormatSettings.Invariant) then
      Result := StrToIntDef(Token.Text, 0);
    Exit;
  end;
  if IsWord('True') then
  begin
    Inc(FIndex);
    Exit(1);
  end;
  if IsWord('False') then
  begin
    Inc(FIndex);
    Exit(0);
  end;
  Name := ReadName;
  if SameText(Name, 'Defined') then
  begin
    Expect('(');
    Name := ReadName;
    Expect(')');
    Exit(BooleanValue[FDefines.ContainsKey(UpperCase(Name))]);
  end;
  if SameText(Name, 'Declared') then
  begin
    Expect('(');
    Name := ReadName;
    Expect(')');
    Exit(BooleanValue[Assigned(FOptions.Declared) and FOptions.Declared(Name)]);
  end;
  if SameText(Name, 'CompilerVersion') then
    Exit(FOptions.CompilerVersion);
  if SameText(Name, 'RTLVersion') then
    Exit(FOptions.RTLVersion);
  for Pair in FOptions.Constants do
    if SameText(Pair.Key, Name) then
      Exit(Pair.Value);
  raise EPreprocessorExpression.CreateFmt('Unbekannter Bezeichner "%s"', [Name]);
end;

{ TPreprocessorRun }

constructor TPreprocessorRun.Create(const AOptions: TPreprocessorOptions);
var
  Define: string;
begin
  inherited Create;
  FOptions := AOptions;
  // Ohne ausdrückliche Angabe folgen CompilerVersion und RTLVersion dem VERnnn der Defines,
  // damit {$IF CompilerVersion >= 36} zu den Projektsymbolen passt.
  if FOptions.CompilerVersion = 0 then
    FOptions.CompilerVersion := TPascalPreprocessor.CompilerVersionFromDefines(AOptions.Defines);
  if FOptions.RTLVersion = 0 then
    FOptions.RTLVersion := FOptions.CompilerVersion;
  FDefines := TDictionary<string, Boolean>.Create;
  for Define in AOptions.Defines do
    if Trim(Define) <> '' then
      FDefines.AddOrSetValue(UpperCase(Trim(Define)), True);
  FTokens := TList<TPascalToken>.Create;
  FFileIndexes := TList<Integer>.Create;
  FFiles := TList<string>.Create;
  FInactive := TList<TInactiveRange>.Create;
  FIssues := TList<TPreprocessorIssue>.Create;
  FIncludeStack := TList<string>.Create;
end;

destructor TPreprocessorRun.Destroy;
begin
  FIncludeStack.Free;
  FIssues.Free;
  FInactive.Free;
  FFiles.Free;
  FFileIndexes.Free;
  FTokens.Free;
  FDefines.Free;
  inherited;
end;

procedure TPreprocessorRun.AddIssue(AFileIndex: Integer; const AToken: TPascalToken; const AMessage: string;
  AKind: TPreprocessorIssueKind);
var
  Issue: TPreprocessorIssue;
begin
  Issue.Kind := AKind;
  Issue.FileIndex := AFileIndex;
  Issue.Range := TTextRange.Create(AToken.StartPos, AToken.EndPos);
  if AFileIndex = 0 then
    Issue.RootRange := Issue.Range
  else
    Issue.RootRange := FRootRange;
  Issue.Message := AMessage;
  FIssues.Add(Issue);
end;

function TPreprocessorRun.EvaluateCondition(const AExpression: string; AFileIndex: Integer;
  const AToken: TPascalToken): Boolean;
var
  Evaluator: TExpressionEvaluator;
begin
  Evaluator := TExpressionEvaluator.Create(FOptions, FDefines);
  try
    try
      Result := Evaluator.Evaluate(AExpression);
    except
      on E: EPreprocessorExpression do
      begin
        AddIssue(AFileIndex, AToken, 'Ungültiger $IF-Ausdruck: ' + E.Message);
        Result := False;
      end;
    end;
  finally
    Evaluator.Free;
  end;
end;

procedure TPreprocessorRun.Include(const AName: string; AFileIndex, ADepth: Integer; const AToken: TPascalToken);
var
  FileName, Text, Existing: string;
  Index: Integer;
begin
  if AFileIndex = 0 then
    FRootRange := TTextRange.Create(AToken.StartPos, AToken.EndPos);
  if AName = '' then
  begin
    AddIssue(AFileIndex, AToken, 'Include-Datei fehlt');
    Exit;
  end;
  if not Assigned(FOptions.ResolveInclude) or
    not FOptions.ResolveInclude(AName, FFiles[AFileIndex], FileName, Text) then
  begin
    AddIssue(AFileIndex, AToken, Format('Include-Datei "%s" nicht gefunden', [AName]),
      TPreprocessorIssueKind.IncludeMissing);
    Exit;
  end;
  if ADepth >= FOptions.MaxIncludeDepth then
  begin
    AddIssue(AFileIndex, AToken, 'Include-Dateien zu tief verschachtelt', TPreprocessorIssueKind.IncludeCycle);
    Exit;
  end;
  for Existing in FIncludeStack do
    if SameText(Existing, FileName) then
    begin
      AddIssue(AFileIndex, AToken, Format('Include-Datei "%s" bindet sich selbst ein', [AName]),
        TPreprocessorIssueKind.IncludeCycle);
      Exit;
    end;
  Index := FFiles.Add(FileName);
  FIncludeStack.Add(FileName);
  try
    ProcessText(Text, Index, ADepth + 1);
  finally
    FIncludeStack.Delete(FIncludeStack.Count - 1);
  end;
end;

procedure TPreprocessorRun.ProcessText(const AText: string; AFileIndex, ADepth: Integer);
var
  Stack: TStack<TBranchState>;
  Opening: TStack<TPascalToken>;
  Token: TPascalToken;
  Name, Argument: string;
  State: TBranchState;
  Active, WasActive, Condition: Boolean;
  InactiveStart, LastEnd: TTextPosition;
  Range: TInactiveRange;
begin
  Stack := TStack<TBranchState>.Create;
  Opening := TStack<TPascalToken>.Create;
  try
    Active := True;
    InactiveStart := TTextPosition.Create(0, 0);
    LastEnd := InactiveStart;
    for Token in TPascalLexer.Tokenize(AText) do
    begin
      LastEnd := Token.EndPos;
      if Token.Kind <> TPascalTokenKind.Directive then
      begin
        if Active then
        begin
          FTokens.Add(Token);
          FFileIndexes.Add(AFileIndex);
        end;
        Continue;
      end;

      SplitDirective(DirectiveBody(Token.Text), Name, Argument);
      WasActive := Active;

      if (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IF') or (Name = 'IFOPT') then
      begin
        State.ParentActive := Active;
        State.InElse := False;
        if not Active then
          Condition := False
        else if Name = 'IFDEF' then
          Condition := FDefines.ContainsKey(UpperCase(FirstWord(Argument)))
        else if Name = 'IFNDEF' then
          Condition := not FDefines.ContainsKey(UpperCase(FirstWord(Argument)))
        else if Name = 'IF' then
          Condition := EvaluateCondition(Argument, AFileIndex, Token)
        else
          Condition := False; // Schalterstände sind unbekannt.
        State.Active := Active and Condition;
        State.Taken := State.Active;
        Stack.Push(State);
        Opening.Push(Token);
        Active := State.Active;
      end
      else if (Name = 'ELSEIF') or (Name = 'ELSE') then
      begin
        if Stack.Count = 0 then
        begin
          AddIssue(AFileIndex, Token, Format('$%s ohne $IF', [Name]));
          Continue;
        end;
        State := Stack.Pop;
        if State.InElse then
          AddIssue(AFileIndex, Token, Format('$%s nach $ELSE', [Name]));
        if Name = 'ELSE' then
        begin
          State.Active := State.ParentActive and not State.Taken;
          State.InElse := True;
        end
        else if State.ParentActive and not State.Taken then
          State.Active := EvaluateCondition(Argument, AFileIndex, Token)
        else
          State.Active := False;
        State.Taken := State.Taken or State.Active;
        Stack.Push(State);
        Active := State.Active;
      end
      else if (Name = 'ENDIF') or (Name = 'IFEND') then
      begin
        if Stack.Count = 0 then
        begin
          AddIssue(AFileIndex, Token, Format('$%s ohne $IF', [Name]));
          Continue;
        end;
        Active := Stack.Pop.ParentActive;
        Opening.Pop;
      end
      else if not Active then
        Continue
      else if Name = 'DEFINE' then
        FDefines.AddOrSetValue(UpperCase(FirstWord(Argument)), True)
      else if Name = 'UNDEF' then
        FDefines.Remove(UpperCase(FirstWord(Argument)))
      else if ((Name = 'I') and not IsSwitch(Argument)) or (Name = 'INCLUDE') then
        Include(IncludeName(Argument), AFileIndex, ADepth, Token)
      else
      begin
        // Andere Direktiven bleiben für spätere Auswertungen erhalten.
        FTokens.Add(Token);
        FFileIndexes.Add(AFileIndex);
      end;

      if WasActive and not Active then
        InactiveStart := Token.EndPos
      else if not WasActive and Active then
      begin
        Range.FileIndex := AFileIndex;
        Range.Range := TTextRange.Create(InactiveStart, Token.StartPos);
        FInactive.Add(Range);
      end;
    end;

    while Opening.Count > 0 do
      AddIssue(AFileIndex, Opening.Pop, '$ENDIF fehlt');
    if not Active then
    begin
      Range.FileIndex := AFileIndex;
      Range.Range := TTextRange.Create(InactiveStart, LastEnd);
      FInactive.Add(Range);
    end;
  finally
    Opening.Free;
    Stack.Free;
  end;
end;

function TPreprocessorRun.Run(const AText: string): TPreprocessorResult;
var
  Defines: TList<string>;
  Key: string;
begin
  FFiles.Add(FOptions.FileName);
  FIncludeStack.Add(FOptions.FileName);
  ProcessText(AText, 0, 0);
  Result.Tokens := FTokens.ToArray;
  Result.FileIndexes := FFileIndexes.ToArray;
  Result.Files := FFiles.ToArray;
  Result.InactiveRanges := FInactive.ToArray;
  Result.Issues := FIssues.ToArray;
  Defines := TList<string>.Create;
  try
    for Key in FDefines.Keys do
      Defines.Add(Key);
    Defines.Sort;
    Result.Defines := Defines.ToArray;
  finally
    Defines.Free;
  end;
end;

{ TPascalPreprocessor }

class function TPascalPreprocessor.Process(const AText: string; const AOptions: TPreprocessorOptions): TPreprocessorResult;
var
  Run: TPreprocessorRun;
begin
  Run := TPreprocessorRun.Create(AOptions);
  try
    Result := Run.Run(AText);
  finally
    Run.Free;
  end;
end;

class function TPascalPreprocessor.Evaluate(const AExpression: string; const AOptions: TPreprocessorOptions;
  const ADefines: TArray<string>; out AError: string): Boolean;
var
  Defines: TDictionary<string, Boolean>;
  Evaluator: TExpressionEvaluator;
  Define: string;
begin
  AError := '';
  Defines := TDictionary<string, Boolean>.Create;
  try
    for Define in ADefines do
      Defines.AddOrSetValue(UpperCase(Define), True);
    Evaluator := TExpressionEvaluator.Create(AOptions, Defines);
    try
      try
        Result := Evaluator.Evaluate(AExpression);
      except
        on E: EPreprocessorExpression do
        begin
          AError := E.Message;
          Result := False;
        end;
      end;
    finally
      Evaluator.Free;
    end;
  finally
    Defines.Free;
  end;
end;

class function TPascalPreprocessor.CompilerVersionOfBds(ABdsVersion: Double): Double;
begin
  if ABdsVersion >= 37 then
    Result := ABdsVersion
  else if ABdsVersion >= 8 then
    Result := ABdsVersion + 13
  else
    Result := 0;
end;

class function TPascalPreprocessor.CompilerVersionFromDefines(const ADefines: TArray<string>): Double;
var
  Define, Digits: string;
  Number: Integer;
begin
  for Define in ADefines do
  begin
    Digits := Trim(Define);
    if (Length(Digits) > 3) and SameText(Copy(Digits, 1, 3), 'VER') and
      TryStrToInt(Copy(Digits, 4, MaxInt), Number) and (Number > 0) then
      Exit(Number / 10);
  end;
  Result := 0;
end;

class function TPascalPreprocessor.PredefinedSymbols(const APlatform: string; ACompilerVersion: Double): TArray<string>;
var
  Symbols: TList<string>;
  Platform: string;
begin
  Symbols := TList<string>.Create;
  try
    Symbols.AddRange(['CONDITIONALEXPRESSIONS', 'UNICODE', 'NATIVECODE', 'ASSEMBLER']);
    if ACompilerVersion > 0 then
      Symbols.Add(Format('VER%d', [Round(ACompilerVersion * 10)]));
    Platform := UpperCase(APlatform);
    if (Platform = 'WIN32') or (Platform = '') then
      Symbols.AddRange(['MSWINDOWS', 'WIN32', 'CPUX86', 'CPU386', 'CPU32BITS'])
    else if Platform = 'WIN64' then
      Symbols.AddRange(['MSWINDOWS', 'WIN64', 'CPUX64', 'CPU64BITS'])
    else if Platform = 'WIN64X' then
      Symbols.AddRange(['MSWINDOWS', 'WIN64', 'CPUX64', 'CPU64BITS', 'LLVM'])
    else if Platform = 'LINUX64' then
      Symbols.AddRange(['LINUX', 'LINUX64', 'POSIX', 'POSIX64', 'CPUX64', 'CPU64BITS'])
    else if (Platform = 'OSX64') or (Platform = 'OSXARM64') then
    begin
      Symbols.AddRange(['MACOS', 'MACOS64', 'POSIX', 'POSIX64', 'CPU64BITS']);
      if Platform = 'OSX64' then
        Symbols.Add('CPUX64')
      else
        Symbols.Add('CPUARM64');
    end
    else if Platform = 'ANDROID' then
      Symbols.AddRange(['ANDROID', 'ANDROID32', 'LINUX', 'POSIX', 'POSIX32', 'CPUARM', 'CPUARM32', 'CPU32BITS'])
    else if Platform = 'ANDROID64' then
      Symbols.AddRange(['ANDROID', 'ANDROID64', 'LINUX', 'POSIX', 'POSIX64', 'CPUARM', 'CPUARM64', 'CPU64BITS'])
    else if Platform = 'IOSDEVICE64' then
      Symbols.AddRange(['IOS', 'IOS64', 'MACOS', 'POSIX', 'POSIX64', 'CPUARM', 'CPUARM64', 'CPU64BITS'])
    else if Platform = 'IOSSIMARM64' then
      Symbols.AddRange(['IOS', 'IOS64', 'IOSSIMULATOR', 'MACOS', 'POSIX', 'POSIX64', 'CPUARM', 'CPUARM64', 'CPU64BITS']);
    Result := Symbols.ToArray;
  finally
    Symbols.Free;
  end;
end;

end.
