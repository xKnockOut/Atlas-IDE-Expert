unit Atlas.Common.Pascal.Parser.Declarations;

// Deklarationen des Parsers (Pascal.Parser): Abschnitte type, const, var,
// label und exports, Attribute, generische Parameter, Routinenköpfe mit
// Parametern und Direktiven. Typen und Routinenrümpfe liefern die Klassen
// darüber.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser.Expressions;

type

  /// <summary>Deklarationen und Routinenköpfe; Typen und Rümpfe liefern die Klassen darüber.</summary>
  TDeclarationParser = class(TExpressionParser)
  protected
    FInImplementation: Boolean;
    procedure ParseDeclarations(AParent: TSyntaxNode);
    function ParseDeclaration(AParent: TSyntaxNode): Boolean;
    procedure ParseAttributes(AParent: TSyntaxNode);
    procedure ParseTypeSection(AParent: TSyntaxNode);
    procedure ParseTypeDecl(AParent: TSyntaxNode);
    function ParseGenericParams(AParent: TSyntaxNode): Boolean;
    /// <summary>Ein Schritt in &lt;…&gt; generischer Parameter; False, wenn die Liste hier abbricht. AGreaterEqual:
    /// Die Liste endet mit "&gt;=".</summary>
    function GenericParamStep(ANode: TSyntaxNode; var ADepth: Integer; var AInConstraints,
      AGreaterEqual: Boolean): Boolean;
    /// <summary>Bezeichner direkt hinter "&lt;", "," oder ";" der Parameterliste.</summary>
    function IsGenericParamName: Boolean;
    procedure ParseConstSection(AParent: TSyntaxNode);
    procedure ParseConstDecl(AParent: TSyntaxNode);
    /// <summary>Wert einer typisierten Konstante oder initialisierten Variable; () ist die leere Record- bzw.
    /// Array-Initialisierung, alle Felder null (#1138).</summary>
    procedure ParseInitializer(AParent: TSyntaxNode);
    function IsDeclStart: Boolean;
    /// <summary>Steht auf "["; folgt den Attributen ein Deklarationsname (#849)? Sonst gehören sie zur
    /// nächsten Methode oder Property und beenden den Abschnitt.</summary>
    function AttributesBeforeName: Boolean;
    function IsDirectiveStart: Boolean;
    procedure ParseVarSection(AParent: TSyntaxNode);
    procedure ParseVarDecl(AParent: TSyntaxNode);
    procedure ParseLabelSection(AParent: TSyntaxNode);
    procedure ParseExports(AParent: TSyntaxNode);
    procedure ParseRoutine(AParent: TSyntaxNode; AWithBody: Boolean);
    function ParseRoutineHeader(AParent: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
    /// <summary>Name hinter procedure, function … bis vor die Parameter, mit generischen Parametern und
    /// Qualifizierung (TFoo&lt;T&gt;.Bar).</summary>
    function ParseRoutineName(AHeader: TSyntaxNode): string;
    /// <summary>Methodenzuordnung ab "=": procedure IFoo.Bar = MyBar.</summary>
    procedure ParseResolution(AHeader: TSyntaxNode);
    procedure ParseParameters(AParent: TSyntaxNode);
    /// <summary>Ein Parameter: Attribute, Modifizierer, Namen, Typ und Vorgabewert.</summary>
    procedure ParseParameter(AParent: TSyntaxNode);
    /// <summary>const, var, out oder constref vor den Namen eines Parameters.</summary>
    procedure ParseParameterModifier(AParam: TSyntaxNode);
    procedure ParseDirectives(AParent: TSyntaxNode);
    procedure ParseHints;
    /// <summary>Typ einer Deklaration (Pascal.Parser.Types).</summary>
    function ParseType(AParent: TSyntaxNode): TSyntaxNode; virtual; abstract;
    /// <summary>Rumpf einer Routine mit lokalen Deklarationen (Pascal.Parser); AWithBody: im
    /// implementation-Teil, sonst nur Direktiven wie forward oder external.</summary>
    procedure ParseRoutineBody(AParent: TSyntaxNode; AWithBody: Boolean); virtual; abstract;
  end;

const

  cCallingConventions: array[0..6] of string = ('stdcall', 'cdecl', 'pascal', 'register', 'safecall', 'winapi',
    'varargs');
  cVisibilityWords: array[0..5] of string = ('private', 'protected', 'public', 'published', 'automated', 'strict');

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.Parser.Cursor;

const

  // Reservierte Wörter, die als Name hinter operator stehen dürfen (class operator In, #1140).
  cOperatorKeywords: array[0..8] of string = ('in', 'and', 'or', 'xor', 'not', 'div', 'mod', 'shl', 'shr');
  cHintWords: array[0..3] of string = ('deprecated', 'platform', 'library', 'experimental');

{ TDeclarationParser }

procedure TDeclarationParser.ParseDeclarations(AParent: TSyntaxNode);
begin
  while not IsSectionEnd do
  begin
    if not ParseDeclaration(AParent) then
    begin
      SkipError(AParent, TRecovery.Declarations);
    end;
  end;
end;

function TDeclarationParser.ParseDeclaration(AParent: TSyntaxNode): Boolean;
begin
  Result := True;
  if IsKw('type') then
  begin
    ParseTypeSection(AParent);
  end
  else if IsKw(['const', 'resourcestring']) then
  begin
    ParseConstSection(AParent);
  end
  else if IsKw(['var', 'threadvar']) then
  begin
    ParseVarSection(AParent);
  end
  else if IsKw('label') then
  begin
    ParseLabelSection(AParent);
  end
  else if IsKw('exports') then
  begin
    ParseExports(AParent);
  end
  else if IsSym('[') then
  begin
    ParseAttributes(AParent);
  end
  else if IsRoutineStart then
  begin
    ParseRoutine(AParent, FInImplementation);
  end
  else
  begin
    Result := False;
  end;
end;

procedure TDeclarationParser.ParseAttributes(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  // [Attr], [Attr(1, 'x')], [A, B]
  while IsSym('[') do
  begin
    mStart := NodeStart;
    mNode := StartNode(TSyntaxKind.Attribute);
    AParent.Add(mNode);
    Advance;
    if not IsSym(']') then
    begin
      ParseArguments(mNode, ']');
    end
    else
    begin
      Advance;
    end;
    if mNode.ChildCount > 0 then
    begin
      mNode.Name := mNode.Children[0].Name;
    end;
    FinishNode(mNode, mStart);
  end;
end;

procedure TDeclarationParser.ParseTypeSection(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.TypeSection);
  AParent.Add(mNode);
  Advance; // type
  while IsDeclStart do
  begin
    if IsSym('[') then
    begin
      ParseAttributes(mNode);
    end
    else
    begin
      ParseTypeDecl(mNode);
    end;
  end;
  FinishNode(mNode, mStart);
end;

procedure TDeclarationParser.ParseTypeDecl(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.TypeDecl);
  AParent.Add(mNode);
  mNode.Name := ExpectIdent;
  if not (IsSym('<') and ParseGenericParams(mNode)) then
  begin
    ExpectSym('=');
  end;
  AcceptKw('type'); // type TNeu = type Integer;
  ParseType(mNode);
  ParseHints;
  ExpectSym(';');
  FinishNode(mNode, mStart);
end;

function TDeclarationParser.ParseGenericParams(AParent: TSyntaxNode): Boolean;
var
  mStart: Integer;
  mNode: TSyntaxNode;
  mDepth: Integer;
  mInConstraints: Boolean;
begin
  // <T>, <K, V>, <T: class, constructor>, <T: IFoo, IBar; U>. Liefert True, wenn
  // der Lexer ">=" gelesen hat (TFoo<T>=class), das "=" also schon verbraucht ist.
  // Nach ":" folgen bis zum nächsten ";" Einschränkungen, keine Typparameter.
  Result := False;
  mInConstraints := False;
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.GenericParams);
  AParent.Add(mNode);
  Advance; // <
  mDepth := 1;
  while not AtEnd and (mDepth > 0) do
  begin
    if not GenericParamStep(mNode, mDepth, mInConstraints, Result) then
    begin
      Break;
    end;
  end;
  if mDepth > 0 then
  begin
    DiagnoseUnexpected('">"');
  end;
  FinishNode(mNode, mStart);
end;

function TDeclarationParser.GenericParamStep(ANode: TSyntaxNode; var ADepth: Integer; var AInConstraints,
  AGreaterEqual: Boolean): Boolean;
begin
  Result := True;
  if IsSym('<') then
  begin
    Inc(ADepth);
    Advance;
  end
  else if IsSym('>') or IsSym('>=') then
  begin
    Dec(ADepth);
    if ADepth = 0 then
    begin
      AGreaterEqual := IsSym('>=');
    end;
    Advance;
  end
  else if IsSym('=') or IsSym('(') or IsSym(')') or IsKw(['begin', 'end']) then
  begin
    Result := False;
  end
  else if ADepth > 1 then
  begin
    Advance;
  end
  else if IsSym(':') or IsSym(';') then
  begin
    AInConstraints := IsSym(':');
    Advance;
  end
  else if not AInConstraints and IsGenericParamName then
  begin
    ANode.Add(Leaf(TSyntaxKind.Identifier, Current.Text));
  end
  else
  begin
    Advance;
  end;
end;

function TDeclarationParser.IsGenericParamName: Boolean;
begin
  Result := IsIdent and (PeekIsSym(-1, '<') or PeekIsSym(-1, ',') or PeekIsSym(-1, ';'));
end;

function TDeclarationParser.AttributesBeforeName: Boolean;
var
  mDelta, mDepth: Integer;
  mToken: TPascalToken;
begin
  mDelta := 0;
  while PeekIsSym(mDelta, '[') do
  begin
    mDepth := 0;
    repeat
      if FIndex + mDelta >= Length(FTokens) then
      begin
        Exit(False);
      end;
      mToken := PeekToken(mDelta);
      if mToken.IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if mToken.IsSymbol(']') then
      begin
        Dec(mDepth);
      end;
      Inc(mDelta);
    until mDepth = 0;
  end;
  mToken := PeekToken(mDelta);
  Result := (mToken.Kind = TPascalTokenKind.Identifier) and not InWords(mToken.Text, cVisibilityWords);
end;

function TDeclarationParser.IsDeclStart: Boolean;
begin
  // Sichtbarkeit beendet einen var- oder const-Abschnitt in Klassen, ebenso ein Attribut vor einer Methode.
  Result := (IsSym('[') and AttributesBeforeName) or (IsIdent and not (InWords(Current.Text, cVisibilityWords) and
    not PeekIsSym(1, ':') and not PeekIsSym(1, ',') and not PeekIsSym(1, '=')));
end;

procedure TDeclarationParser.ParseConstSection(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.ConstSection);
  mNode.Name := LowerCase(Current.Text); // const oder resourcestring
  AParent.Add(mNode);
  Advance;
  while IsDeclStart do
  begin
    if IsSym('[') then
    begin
      ParseAttributes(mNode);
    end
    else
    begin
      ParseConstDecl(mNode);
    end;
  end;
  FinishNode(mNode, mStart);
end;

procedure TDeclarationParser.ParseConstDecl(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  // Name = Wert; Name: Typ = Wert;
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.ConstDecl);
  AParent.Add(mNode);
  mNode.Name := ExpectIdent;
  if AcceptSym(':') then
  begin
    ParseType(mNode);
    ExpectSym('=');
    ParseInitializer(mNode);
  end
  else
  begin
    ExpectSym('=');
    ParseExpression(mNode);
  end;
  ParseHints;
  ExpectSym(';');
  FinishNode(mNode, mStart);
end;

procedure TDeclarationParser.ParseInitializer(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  if IsSym('(') and PeekToken(1).IsSymbol(')') then
  begin
    mStart := NodeStart;
    mNode := StartNode(TSyntaxKind.ParenExpr);
    AParent.Add(mNode);
    Advance;
    Advance;
    FinishNode(mNode, mStart);
  end
  else
  begin
    ParseExpression(AParent);
  end;
end;

procedure TDeclarationParser.ParseVarSection(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.VarSection);
  mNode.Name := LowerCase(Current.Text); // var oder threadvar
  AParent.Add(mNode);
  Advance;
  while IsDeclStart do
  begin
    if IsSym('[') then
    begin
      ParseAttributes(mNode);
    end
    else
    begin
      ParseVarDecl(mNode);
    end;
  end;
  FinishNode(mNode, mStart);
end;

procedure TDeclarationParser.ParseVarDecl(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
  mNames: string;
begin
  // A, B: Typ; X: Typ = Wert; Y: Typ absolute Z;
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.VarDecl);
  AParent.Add(mNode);
  mNames := ExpectIdent;
  while AcceptSym(',') do
  begin
    mNames := mNames + ',' + ExpectIdent;
  end;
  mNode.Name := mNames;
  ExpectSym(':');
  ParseType(mNode);
  // X: Boolean platform = False (System.NoErrMsg): Das Hinweiswort darf vor dem Startwert stehen.
  ParseHints;
  if IsIdentText('absolute') then
  begin
    Advance;
    if IsIdent then
    begin
      ParseExpression(mNode);
    end
    else
    begin
      // absolute $40:$17: Adressen kennt Delphi nicht mehr, nur Variablen (wie E2088, #1382). Bis zum ';'
      // überspringen, sonst folgen Fehler zum ':'.
      DiagnoseUnexpected('E2088', 'Variable');
      while not AtEnd and not IsSym(';') do
      begin
        Advance;
      end;
    end;
  end
  else if AcceptSym('=') then
  begin
    ParseInitializer(mNode);
  end;
  ParseHints;
  ExpectSym(';');
  FinishNode(mNode, mStart);
end;

procedure TDeclarationParser.ParseLabelSection(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.LabelSection);
  AParent.Add(mNode);
  Advance; // label
  while not AtEnd and not IsSym(';') and not IsSectionEnd do
  begin
    Advance;
  end;
  ExpectSym(';');
  FinishNode(mNode, mStart);
end;

procedure TDeclarationParser.ParseExports(AParent: TSyntaxNode);
var
  mStart, mDepth: Integer;
  mNode: TSyntaxNode;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.ExportsClause);
  AParent.Add(mNode);
  Advance; // exports
  // Parameterlisten überladener Routinen, z. B. Setze(const A: string; var B: TBytes), enthalten ";" (#973).
  mDepth := 0;
  while not AtEnd and ((mDepth > 0) or (not IsSym(';') and not IsSectionEnd)) do
  begin
    if IsSym('(') then
    begin
      Inc(mDepth);
    end
    else if IsSym(')') and (mDepth > 0) then
    begin
      Dec(mDepth);
    end;
    Advance;
  end;
  ExpectSym(';');
  FinishNode(mNode, mStart);
end;

function TDeclarationParser.ParseRoutineHeader(AParent: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  mStart: Integer;
begin
  // [class] procedure|function|constructor|destructor|operator Name[<T>][.Name[<T>]] [(Params)] [: Typ];
  mStart := NodeStart;
  Result := StartNode(AKind);
  AParent.Add(Result);
  AcceptKw('class');
  Result.Name := ParseRoutineName(Result);
  if IsSym('(') then
  begin
    ParseParameters(Result);
  end;
  if AcceptSym(':') then
  begin
    ParseAttributes(Result);
    ParseTypeReference(Result);
  end;
  if IsSym('=') then
  begin
    ParseResolution(Result);
  end;
  // Aufrufkonvention oder Direktive ohne Semikolon davor: function F: Integer stdcall; (#849)
  if not IsDirectiveStart then
  begin
    if not IsSym(';') and not IsSym(')') and not IsSym(']') then
    begin
      DiagnoseMissingSemicolon;
    end
    else
    begin
      AcceptSym(';');
    end;
  end;
  ParseDirectives(Result);
  FinishNode(Result, mStart);
end;

function TDeclarationParser.ParseRoutineName(AHeader: TSyntaxNode): string;
var
  mIsOperator: Boolean;
begin
  mIsOperator := SameWord(Current.Text, 'operator');
  Advance; // procedure, function, constructor, destructor, operator
  // Operatornamen dürfen reservierte Wörter sein: class operator In, And, Or, Xor, Not, Div, Mod, Shl, Shr (#1140).
  if mIsOperator and (Current.Kind = TPascalTokenKind.Keyword) and InWords(Current.Text, cOperatorKeywords) then
  begin
    Result := Current.Text;
    Advance;
  end
  else
  begin
    Result := ExpectIdent;
  end;
  repeat
    if IsSym('<') then
    begin
      ParseGenericParams(AHeader);
    end;
    if not IsSym('.') or not (PeekToken(1).Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword]) then
    begin
      Break;
    end;
    Advance;
    Result := Result + '.' + Current.Text;
    Advance;
  until False;
end;

procedure TDeclarationParser.ParseResolution(AHeader: TSyntaxNode);
var
  mStart: Integer;
  mClause: TSyntaxNode;
begin
  // Methodenzuordnung: procedure IFoo.Bar = MyBar; als Direktive "resolution" mit dem Ziel (#849).
  mStart := NodeStart;
  mClause := StartNode(TSyntaxKind.Directive);
  mClause.Name := 'resolution';
  AHeader.Add(mClause);
  Advance;
  if IsIdent then
  begin
    mClause.Add(Leaf(TSyntaxKind.Identifier, Current.Text));
  end
  else
  begin
    ExpectIdent;
  end;
  FinishNode(mClause, mStart);
end;

procedure TDeclarationParser.ParseParameters(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
  mCloser: string;
begin
  mStart := NodeStart;
  mNode := StartNode(TSyntaxKind.Parameters);
  AParent.Add(mNode);
  if IsSym('[') then
  begin
    mCloser := ']';
  end
  else
  begin
    mCloser := ')';
  end;
  Advance; // ( oder [
  while not AtEnd and not IsSym(mCloser) do
  begin
    ParseParameter(mNode);
    if not AcceptSym(';') then
    begin
      Break;
    end;
  end;
  ExpectSym(mCloser);
  FinishNode(mNode, mStart);
end;

procedure TDeclarationParser.ParseParameter(AParent: TSyntaxNode);
var
  mStart: Integer;
  mParam: TSyntaxNode;
  mNames: string;
begin
  mStart := NodeStart;
  mParam := StartNode(TSyntaxKind.Parameter);
  AParent.Add(mParam);
  ParseAttributes(mParam);
  ParseParameterModifier(mParam);
  ParseAttributes(mParam);
  mNames := ExpectIdent;
  while AcceptSym(',') do
  begin
    mNames := mNames + ',' + ExpectIdent;
  end;
  mParam.Name := mNames;
  if AcceptSym(':') then
  begin
    if IsKw('array') then
    begin
      ParseType(mParam);
    end
    else
    begin
      ParseTypeReference(mParam);
    end;
  end;
  if AcceptSym('=') then
  begin
    ParseExpression(mParam);
  end;
  FinishNode(mParam, mStart);
end;

procedure TDeclarationParser.ParseParameterModifier(AParam: TSyntaxNode);
begin
  // const und var immer; out und constref nur vor einem Namen, sonst heißt der Parameter so.
  if IsKw('const') then
  begin
    AParam.Modifier := TParameterModifier.ConstParam;
  end
  else if IsKw('var') then
  begin
    AParam.Modifier := TParameterModifier.VarParam;
  end
  else if PeekToken(1).Kind <> TPascalTokenKind.Identifier then
  begin
    Exit;
  end
  else if IsIdentText('out') then
  begin
    AParam.Modifier := TParameterModifier.OutParam;
  end
  else if IsIdentText('constref') then
  begin
    AParam.Modifier := TParameterModifier.ConstRefParam;
  end
  else
  begin
    Exit;
  end;
  Advance;
end;

function TDeclarationParser.IsDirectiveStart: Boolean;
begin
  Result := IsIdent and TDirectiveNames.IsRoutineDirective(Current.Text) or IsKw(['inline', 'library']);
end;

procedure TDeclarationParser.ParseDirectives(AParent: TSyntaxNode);
var
  mStart: Integer;
  mNode: TSyntaxNode;
  mWord: string;
begin
  // overload; virtual; abstract; external 'dll' name 'x'; message WM_X; ...
  // Ein anderes Wort mit ';' dahinter kann an dieser Stelle nur eine Direktive sein, meist ein Tippfehler
  // (overide;): Es wird ein Directive-Knoten mit dem Wort, die Regel directive-typo meldet es (#1068).
  while IsDirectiveStart or (IsIdent and PeekIsSym(1, ';')) do
  begin
    mStart := NodeStart;
    mWord := LowerCase(Current.Text);
    mNode := StartNode(TSyntaxKind.Directive);
    mNode.Name := mWord;
    AParent.Add(mNode);
    Advance;
    // Argumente der Direktive bis zum Semikolon; "assembler asm" ohne Semikolon (#849).
    while not AtEnd and not IsSym(';') and not IsKw(['begin', 'asm', 'var', 'const', 'type', 'end', 'label']) and
      not IsRoutineStart and not IsDirectiveStart do
    begin
      Advance;
    end;
    FinishNode(mNode, mStart);
    AcceptSym(';');
  end;
end;

procedure TDeclarationParser.ParseHints;
begin
  // deprecated 'Grund', platform, library, experimental
  while (IsIdent and InWords(Current.Text, cHintWords)) or IsKw('library') do
  begin
    Advance;
    if Current.Kind = TPascalTokenKind.StringLiteral then
    begin
      Advance;
    end;
  end;
end;

procedure TDeclarationParser.ParseRoutine(AParent: TSyntaxNode; AWithBody: Boolean);
begin
  if not EnterNesting then
  begin
    AParent.Add(TooDeep);
    Exit;
  end;
  try
    ParseRoutineBody(AParent, AWithBody);
  finally
    Dec(FDepth);
  end;
end;

end.
