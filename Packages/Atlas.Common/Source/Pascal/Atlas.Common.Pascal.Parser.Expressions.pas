unit Atlas.Common.Pascal.Parser.Expressions;

// Ausdrücke des Parsers (Pascal.Parser): Operatoren nach Vorrang, Faktoren,
// Literale, generische Argumente und lange Operatorketten (#1094, siehe
// Kopf von Pascal.Parser). Anonyme Methoden und Typverweise liefern die
// Klassen darüber.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser.Cursor;

type

  /// <summary>Rechter Operand einer Operatorkette mit seinen Token-Grenzen (EndIndex exklusiv).</summary>
  TChainOperand = record
    Node: TSyntaxNode;
    StartIndex: Integer;
    EndIndex: Integer;
  end;

  /// <summary>Folge desselben assoziativen Operators, die ParseSimpleExpression bzw. ParseTerm sammelt.</summary>
  TOperatorRun = record
    Operator: string;
    Operands: TArray<TChainOperand>;
    Count: Integer;
  end;
  /// <summary>Ausdrücke; anonyme Methoden und Typverweise liefern die Klassen darüber.</summary>
  TExpressionParser = class(TParserBase)
  protected
    function ParseExpression(AParent: TSyntaxNode): TSyntaxNode;
    /// <summary>Steht auf einem Vergleich: = &lt;&gt; &lt; &gt; &lt;= &gt;= in is, is not, not in.</summary>
    function AtRelationalOperator: Boolean;
    function ParseSimpleExpression: TSyntaxNode;
    function ParseTerm: TSyntaxNode;
    function ParseFactor: TSyntaxNode;
    function ParseFactorBody: TSyntaxNode;
    function ParsePrimary: TSyntaxNode;
    /// <summary>Operand ohne nachgestellte Teile; nil, wenn hier kein Ausdruck beginnt.</summary>
    function ParseOperand(AStart: Integer): TSyntaxNode;
    /// <summary>Operand ab Schlüsselwort oder Klammer (nil, inherited, anonyme Methode, (…), […]); sonst nil.
    /// </summary>
    function ParseKeywordOperand(AStart: Integer): TSyntaxNode;
    function ParseInherited(AStart: Integer): TSyntaxNode;
    /// <summary>(…) mit Record- und Array-Konstanten: (X: 1; Y: 2), (1, 2, 3).</summary>
    function ParseParenExpr(AStart: Integer): TSyntaxNode;
    /// <summary>[a, b..c]</summary>
    function ParseSetConstructor(AStart: Integer): TSyntaxNode;
    /// <summary>Nachgestellter Teil hinter AOperand (.Name, (…), […], ^, &lt;Typen&gt;); nil, wenn keiner folgt.
    /// </summary>
    function ParseSelector(AOperand: TSyntaxNode): TSyntaxNode;
    /// <summary>Aufruf (…) bzw. Index […] hinter AOperand.</summary>
    function ParseCallOrIndex(AOperand: TSyntaxNode): TSyntaxNode;
    /// <summary>Steht auf "&lt;": Folgen generische Argumente? Im Ausdruck darf danach kein Operand stehen.</summary>
    function LooksLikeGenericArgs: Boolean; overload;
    /// <summary>Wie oben; AInType: im Typverweis ist "&lt;" immer der Anfang von Typargumenten, danach darf auch
    /// ein Bezeichner folgen (property L: TList&lt;Integer&gt; read FL).</summary>
    function LooksLikeGenericArgs(AInType: Boolean): Boolean; overload;
    /// <summary>'a'#13'b'^M als ein Literal; Steuerzeichen ^M stehen im Namen als #13 (#862).</summary>
    function ParseStringLiteral: TSyntaxNode;
    procedure ParseGenericArgs(AParent: TSyntaxNode);
    procedure ParseArguments(AParent: TSyntaxNode; const ACloser: string);
    function Binary(const AOperator: string; ALeft, ARight: TSyntaxNode; AStartIndex: Integer): TSyntaxNode;
    /// <summary>Wie Binary, mit ausdrücklichem Ende (Token-Index exklusiv) statt der aktuellen Position.</summary>
    function BinaryUpTo(const AOperator: string; ALeft, ARight: TSyntaxNode; AStartIndex,
      AEndIndex: Integer): TSyntaxNode;
    /// <summary>Ausgeglichener Teilbaum aus den Operanden ALow..AHigh von ARun.</summary>
    function BalancedRun(const ARun: TOperatorRun; ALow, AHigh: Integer): TSyntaxNode;
    /// <summary>Hängt die gesammelte Folge an ALeft (Anfang AStartIndex) und leert sie.</summary>
    function FlushRun(ALeft: TSyntaxNode; AStartIndex: Integer; var ARun: TOperatorRun): TSyntaxNode;
    /// <summary>Nimmt den Operanden ARight hinter AOperator auf: in die laufende Folge eines assoziativen
    /// Operators oder sofort als BinaryExpr.</summary>
    function ChainOperand(ALeft: TSyntaxNode; const AOperator: string; ARight: TSyntaxNode;
      AStartIndex, AOperandStart: Integer; var ARun: TOperatorRun): TSyntaxNode;
    /// <summary>Anonyme Methode ab procedure bzw. function (Pascal.Parser).</summary>
    function ParseAnonymousMethod: TSyntaxNode; virtual; abstract;
    /// <summary>Typverweis wie TList&lt;Integer&gt; oder array of string (Pascal.Parser.Types).</summary>
    function ParseTypeReference(AParent: TSyntaxNode): TSyntaxNode; virtual; abstract;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TParserExpressionsText = (Expression);

const
  cTexts: array[TParserExpressionsText] of TAtlasText = (
    (De: 'Ausdruck'; En: 'expression'));

{$SCOPEDENUMS OFF}

const
  RelationalOperators: array[0..5] of string = ('=', '<>', '<', '>', '<=', '>=');
  AdditiveSymbols: array[0..1] of string = ('+', '-');
  MultiplicativeSymbols: array[0..1] of string = ('*', '/');

  /// <summary>Assoziative Operatoren, deren lange Folgen ausgeglichen gebaut werden.</summary>
  AssociativeOperators: array[0..3] of string = ('+', 'and', 'or', 'xor');
  /// <summary>Ab so vielen rechten Operanden desselben assoziativen Operators wird die Folge ausgeglichen
  /// statt linkslastig gebaut; kürzere Folgen bleiben linkslastig.</summary>
  BalancedRunFrom = 32;

{ TExpressionParser }

function TExpressionParser.Binary(const AOperator: string; ALeft, ARight: TSyntaxNode; AStartIndex: Integer): TSyntaxNode;
begin
  Result := StartNode(TSyntaxKind.BinaryExpr);
  Result.Name := AOperator;
  Result.Add(ALeft);
  Result.Add(ARight);
  FinishNode(Result, AStartIndex);
end;

function TExpressionParser.BinaryUpTo(const AOperator: string; ALeft, ARight: TSyntaxNode; AStartIndex,
  AEndIndex: Integer): TSyntaxNode;
var
  First, Last: TPascalToken;
begin
  Result := StartNode(TSyntaxKind.BinaryExpr);
  Result.Name := AOperator;
  Result.Add(ALeft);
  Result.Add(ARight);
  // Wie FinishNode an der Stelle, als der Parser hinter dem letzten Operanden stand.
  First := FTokens[AStartIndex];
  Last := FTokens[AEndIndex - 1];
  Result.SetRange(First.StartPos, Last.EndPos, First.Offset, Last.Offset + Length(Last.Text));
end;

function TExpressionParser.BalancedRun(const ARun: TOperatorRun; ALow, AHigh: Integer): TSyntaxNode;
var
  Middle: Integer;
begin
  if ALow = AHigh then
  begin
    Exit(ARun.Operands[ALow].Node);
  end;
  // Rekursionstiefe log2(Anzahl), auch bei Zehntausenden Operanden flach.
  Middle := (ALow + AHigh) div 2;
  Result := BinaryUpTo(ARun.Operator, BalancedRun(ARun, ALow, Middle), BalancedRun(ARun, Middle + 1, AHigh),
    ARun.Operands[ALow].StartIndex, ARun.Operands[AHigh].EndIndex);
end;

function TExpressionParser.FlushRun(ALeft: TSyntaxNode; AStartIndex: Integer; var ARun: TOperatorRun): TSyntaxNode;
var
  Index: Integer;
begin
  Result := ALeft;
  if ARun.Count = 0 then
  begin
    Exit;
  end;
  if ARun.Count < BalancedRunFrom then
  begin
    // Kurze Folge: linkslastig wie bisher, mit denselben Bereichen wie Binary.
    for Index := 0 to ARun.Count - 1 do
    begin
      Result := BinaryUpTo(ARun.Operator, Result, ARun.Operands[Index].Node, AStartIndex,
        ARun.Operands[Index].EndIndex);
    end;
  end
  else
  begin
    // Lange Folge desselben assoziativen Operators, etwa 'a' + #10 + 'b' + … in erzeugten Units:
    // A + x1 + … + xn = A + (x1 + … + xn), der rechte Teil ausgeglichen. Linkslastig wäre der Baum so
    // tief wie die Kette lang, und rekursive Auswertungen (Prüfregeln, Index) sprengten den Stapel.
    Result := BinaryUpTo(ARun.Operator, Result, BalancedRun(ARun, 0, ARun.Count - 1), AStartIndex,
      ARun.Operands[ARun.Count - 1].EndIndex);
  end;
  ARun.Operator := '';
  ARun.Operands := nil;
  ARun.Count := 0;
end;

function TExpressionParser.ChainOperand(ALeft: TSyntaxNode; const AOperator: string; ARight: TSyntaxNode;
  AStartIndex, AOperandStart: Integer; var ARun: TOperatorRun): TSyntaxNode;
var
  Operand: TChainOperand;
begin
  Result := ALeft;
  if (ARun.Count > 0) and (ARun.Operator <> AOperator) then
  begin
    Result := FlushRun(Result, AStartIndex, ARun);
  end;
  // Nicht assoziativ (a - b - c) oder leerer Operand (fehlender Ausdruck): sofort anhängen wie bisher.
  if not InWords(AOperator, AssociativeOperators) or (FIndex <= AOperandStart) then
  begin
    Result := FlushRun(Result, AStartIndex, ARun);
    Exit(Binary(AOperator, Result, ARight, AStartIndex));
  end;
  Operand.Node := ARight;
  Operand.StartIndex := AOperandStart;
  Operand.EndIndex := FIndex;
  ARun.Operator := AOperator;
  if ARun.Count = Length(ARun.Operands) then
  begin
    SetLength(ARun.Operands, 2 * ARun.Count + 8);
  end;
  ARun.Operands[ARun.Count] := Operand;
  Inc(ARun.Count);
end;

function TExpressionParser.ParseExpression(AParent: TSyntaxNode): TSyntaxNode;
var
  Start: Integer;
  Op: string;
begin
  // Vergleich: = <> < > <= >= in is, ab Delphi 13 auch "is not" und "not in" (#109)
  Start := NodeStart;
  Result := ParseSimpleExpression;
  while AtRelationalOperator do
  begin
    Op := LowerCase(Current.Text);
    Advance;
    if (Op = 'is') and IsKw('not') then
    begin
      Op := 'is not';
      Advance;
    end
    else if Op = 'not' then
    begin
      Op := 'not in';
      Advance;
    end;
    Result := Binary(Op, Result, ParseSimpleExpression, Start);
  end;
  if AParent <> nil then
  begin
    AParent.Add(Result);
  end;
end;

function TExpressionParser.AtRelationalOperator: Boolean;
begin
  if IsKw(['in', 'is']) or (IsKw('not') and PeekIsKw(1, 'in')) then
  begin
    Exit(True);
  end;
  Result := not AtEnd and (Current.Kind = TPascalTokenKind.Symbol) and InWords(Current.Text, RelationalOperators);
end;

function TExpressionParser.ParseSimpleExpression: TSyntaxNode;
var
  Start, OperandStart: Integer;
  Op: string;
  Run: TOperatorRun;
begin
  // + - or xor
  Start := NodeStart;
  Result := ParseTerm;
  Run := Default(TOperatorRun);
  while (not AtEnd and (Current.Kind = TPascalTokenKind.Symbol) and InWords(Current.Text, AdditiveSymbols)) or
    IsKw(['or', 'xor']) do
  begin
    Op := LowerCase(Current.Text);
    Advance;
    OperandStart := NodeStart;
    Result := ChainOperand(Result, Op, ParseTerm, Start, OperandStart, Run);
  end;
  Result := FlushRun(Result, Start, Run);
end;

function TExpressionParser.ParseTerm: TSyntaxNode;
var
  Start, OperandStart: Integer;
  Op: string;
  Run: TOperatorRun;
begin
  // * / div mod and shl shr as
  Start := NodeStart;
  Result := ParseFactor;
  Run := Default(TOperatorRun);
  while (not AtEnd and (Current.Kind = TPascalTokenKind.Symbol) and InWords(Current.Text, MultiplicativeSymbols)) or
    IsKw(['div', 'mod', 'and', 'shl', 'shr', 'as']) do
  begin
    Op := LowerCase(Current.Text);
    Advance;
    OperandStart := NodeStart;
    Result := ChainOperand(Result, Op, ParseFactor, Start, OperandStart, Run);
  end;
  Result := FlushRun(Result, Start, Run);
end;

function TExpressionParser.ParseFactor: TSyntaxNode;
begin
  if not EnterNesting then
  begin
    Exit(TooDeep);
  end;
  try
    Result := ParseFactorBody;
  finally
    Dec(FDepth);
  end;
end;

function TExpressionParser.ParseFactorBody: TSyntaxNode;
var
  Start: Integer;
begin
  Start := NodeStart;
  if IsKw('not') or IsSym('-') or IsSym('+') then
  begin
    Result := StartNode(TSyntaxKind.UnaryExpr);
    Result.Name := LowerCase(Current.Text);
    Advance;
    Result.Add(ParseFactor);
    FinishNode(Result, Start);
  end
  else if IsSym('@') then
  begin
    Result := StartNode(TSyntaxKind.AddressOf);
    Advance;
    Result.Add(ParseFactor);
    FinishNode(Result, Start);
  end
  else if IsKw('if') then
  begin
    // Bedingter Ausdruck: if Bedingung then A else B
    Result := StartNode(TSyntaxKind.IfExpr);
    Advance;
    ParseExpression(Result);
    ExpectKw('then');
    ParseExpression(Result);
    ExpectKw('else');
    ParseExpression(Result);
    FinishNode(Result, Start);
  end
  else
  begin
    Result := ParsePrimary;
  end;
end;

function TExpressionParser.ParseStringLiteral: TSyntaxNode;
var
  Start: Integer;
  Text: string;
begin
  Start := NodeStart;
  Text := '';
  while not AtEnd do
  begin
    if Current.Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral] then
    begin
      Text := Text + Current.Text;
      Advance;
    end
    else if IsControlChar then
    begin
      Text := Text + '#' + IntToStr(Ord(UpCase(PeekToken(1).Text[1])) xor $40);
      Advance;
      Advance;
    end
    else
    begin
      Break;
    end;
  end;
  Result := StartNode(TSyntaxKind.Literal);
  Result.Name := Text;
  FinishNode(Result, Start);
end;

function TExpressionParser.LooksLikeGenericArgs: Boolean;
begin
  Result := LooksLikeGenericArgs(False);
end;

function TExpressionParser.LooksLikeGenericArgs(AInType: Boolean): Boolean;
var
  Delta: Integer;
  Depth: Integer;
  Token: TPascalToken;
begin
  // Steht auf "<". Generische Argumente bestehen nur aus Bezeichnern, Punkten,
  // Kommas, string und verschachtelten <>; danach folgt kein Operand.
  Delta := 0;
  Depth := 0;
  repeat
    Token := PeekToken(Delta);
    if Token.IsSymbol('<') then
    begin
      Inc(Depth);
    end
    else if Token.IsSymbol('>') then
    begin
      Dec(Depth);
    end
    else if AInType and (Depth = 1) and Token.IsSymbol('>=') then
    begin
      // Baz: IBaz<string>=nil: das = gehört zum Vorgabewert (#1142).
      Exit(True);
    end
    else if not ((Token.Kind = TPascalTokenKind.Identifier) or Token.IsSymbol('.') or Token.IsSymbol(',') or
      Token.IsKeyword('string')) then
    begin
      Exit(False);
    end;
    Inc(Delta);
  until (Depth = 0) or (FIndex + Delta >= Length(FTokens));
  if Depth <> 0 then
  begin
    Exit(False);
  end;
  Token := PeekToken(Delta);
  Result := AInType and (Token.Kind = TPascalTokenKind.Identifier);
  Result := Result or not (Token.Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Number,
    TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]);
end;

procedure TExpressionParser.ParseGenericArgs(AParent: TSyntaxNode);
var
  Start: Integer;
  Node: TSyntaxNode;
begin
  Start := NodeStart;
  Node := StartNode(TSyntaxKind.GenericArgs);
  AParent.Add(Node);
  Advance; // <
  while not AtEnd and not IsSym('>') do
  begin
    ParseTypeReference(Node);
    if not AcceptSym(',') then
    begin
      Break;
    end;
  end;
  if IsSym('>=') then
  begin
    SplitGreaterEqual;
  end;
  ExpectSym('>');
  FinishNode(Node, Start);
end;

procedure TExpressionParser.ParseArguments(AParent: TSyntaxNode; const ACloser: string);
begin
  // Steht hinter ( oder [. Write(X:10:2) erlaubt Formatangaben.
  while not AtEnd and not IsSym(ACloser) do
  begin
    // Benanntes Argument der OLE-Automation: Open(FileName := 'a.docx') (#849); der Name gehört zur
    // Schnittstelle des Servers und wird nicht aufgelöst. Auch ein reserviertes Wort: Foo(Type := 1) (#1167).
    if (IsIdent or (Current.Kind = TPascalTokenKind.Keyword)) and PeekIsSym(1, ':=') then
    begin
      Advance;
      Advance;
    end;
    ParseExpression(AParent);
    while AcceptSym(':') do
    begin
      ParseExpression(AParent);
    end;
    if not AcceptSym(',') then
    begin
      Break;
    end;
  end;
  ExpectSym(ACloser);
end;

function TExpressionParser.ParsePrimary: TSyntaxNode;
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  Result := ParseOperand(mStart);
  if Result = nil then
  begin
    DiagnoseUnexpected(cTexts[TParserExpressionsText.Expression].Text);
    Result := StartNode(TSyntaxKind.Error);
    FinishNode(Result, mStart);
    Exit;
  end;
  // Nachgestellte Teile: .Name, (Argumente), [Index], ^, <Typen>
  mNode := ParseSelector(Result);
  while mNode <> nil do
  begin
    FinishNode(mNode, mStart);
    Result := mNode;
    mNode := ParseSelector(Result);
  end;
end;

function TExpressionParser.ParseOperand(AStart: Integer): TSyntaxNode;
begin
  case Current.Kind of
    TPascalTokenKind.Identifier:
      Result := Leaf(TSyntaxKind.Identifier, Current.Text);
    TPascalTokenKind.Number:
      Result := Leaf(TSyntaxKind.Literal, Current.Text);
    // {$I datei.inc} als Wert (#849): Literal mit dem Text der Direktive.
    TPascalTokenKind.Directive:
      Result := Leaf(TSyntaxKind.Literal, Current.Text);
    TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral:
      Result := ParseStringLiteral;
  else
    Result := ParseKeywordOperand(AStart);
  end;
end;

function TExpressionParser.ParseKeywordOperand(AStart: Integer): TSyntaxNode;
begin
  Result := nil;
  if IsKw('nil') then
  begin
    Result := Leaf(TSyntaxKind.Literal, 'nil');
  end
  else if IsKw('inherited') then
  begin
    Result := ParseInherited(AStart);
  end
  // string und file als Typname im Ausdruck: string(P), SizeOf(string), Default(File) (#1084).
  else if IsKw(['string', 'file']) then
  begin
    Result := Leaf(TSyntaxKind.Identifier, Current.Text);
  end
  else if IsKw(['procedure', 'function']) then
  begin
    Result := ParseAnonymousMethod;
  end
  else if IsSym('(') then
  begin
    Result := ParseParenExpr(AStart);
  end
  else if IsControlChar then
  begin
    Result := ParseStringLiteral;
  end
  else if IsSym('[') then
  begin
    Result := ParseSetConstructor(AStart);
  end;
end;

function TExpressionParser.ParseInherited(AStart: Integer): TSyntaxNode;
begin
  Result := StartNode(TSyntaxKind.InheritedExpr);
  Advance;
  if IsIdent then
  begin
    Result.Name := Current.Text;
    Advance;
  end;
  FinishNode(Result, AStart);
end;

function TExpressionParser.ParseParenExpr(AStart: Integer): TSyntaxNode;
begin
  Result := StartNode(TSyntaxKind.ParenExpr);
  Advance;
  ParseExpression(Result);
  // Record-Konstanten: (X: 1; Y: 2) und Array-Konstanten: (1, 2, 3)
  while AcceptSym(',') or AcceptSym(';') or AcceptSym(':') do
  begin
    if not IsSym(')') then
    begin
      ParseExpression(Result);
    end;
  end;
  ExpectSym(')');
  FinishNode(Result, AStart);
end;

function TExpressionParser.ParseSetConstructor(AStart: Integer): TSyntaxNode;
var
  mElementStart: Integer;
  mNode: TSyntaxNode;
begin
  Result := StartNode(TSyntaxKind.SetConstructor);
  Advance;
  while not AtEnd and not IsSym(']') do
  begin
    mElementStart := NodeStart;
    mNode := ParseExpression(Result);
    if AcceptSym('..') then
    begin
      // Bereich a..b
      Result.Extract(mNode);
      mNode := Binary('..', mNode, ParseExpression(nil), mElementStart);
      mNode.Kind := TSyntaxKind.RangeExpr;
      Result.Add(mNode);
    end;
    if not AcceptSym(',') then
    begin
      Break;
    end;
  end;
  ExpectSym(']');
  FinishNode(Result, AStart);
end;

function TExpressionParser.ParseSelector(AOperand: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if IsSym('.') and (PeekToken(1).Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
  begin
    Result := StartNode(TSyntaxKind.MemberAccess);
    Result.Add(AOperand);
    Advance;
    Result.Name := Current.Text;
    Advance;
  end
  else if IsSym('(') or IsSym('[') then
  begin
    Result := ParseCallOrIndex(AOperand);
  end
  else if IsSym('^') then
  begin
    Result := StartNode(TSyntaxKind.Dereference);
    Result.Add(AOperand);
    Advance;
  end
  else if IsSym('<') and (AOperand.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
    LooksLikeGenericArgs then
  begin
    Result := StartNode(TSyntaxKind.MemberAccess);
    Result.Name := AOperand.Name;
    Result.Add(AOperand);
    ParseGenericArgs(Result);
  end;
end;

function TExpressionParser.ParseCallOrIndex(AOperand: TSyntaxNode): TSyntaxNode;
begin
  if IsSym('(') then
  begin
    Result := StartNode(TSyntaxKind.Call);
  end
  else
  begin
    Result := StartNode(TSyntaxKind.IndexAccess);
  end;
  Result.Name := AOperand.Name;
  Result.Add(AOperand);
  Advance;
  if Result.Kind = TSyntaxKind.Call then
  begin
    ParseArguments(Result, ')');
  end
  else
  begin
    ParseArguments(Result, ']');
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Pascal.Parser.Expressions', cTexts);

end.
