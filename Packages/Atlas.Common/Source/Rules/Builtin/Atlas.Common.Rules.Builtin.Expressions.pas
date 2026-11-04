unit Atlas.Common.Rules.Builtin.Expressions;

// Regeln für Ausdrücke, die anders gebunden werden als gemeint (#909):
//   operator-precedence   not bindet stärker als in und Vergleiche (#911):
//                         "not X in Menge" ist "(not X) in Menge", "not A = B"
//                         ist "(not A) = B", bei Ganzzahlen bitweise.
// Gemeldet wird nur, wenn der Typ des Operanden in der Datei deklariert und
// kein Boolean ist (Atlas.Common.Pascal.DeclaredTypes); unbekannte Typen und
// Variants bleiben stumm.
//   duplicate-condition   dieselbe Bedingung zweimal in einer if-else-if-Kette, gleiche then- und
//                         else-Zweige, A and A bzw. A or A, X = X (#928). Verglichen wird der
//                         Quelltext ohne Leerraum, Kommentare und Groß-/Kleinschreibung.
//   string-index-base     Copy(S, 0, N), Delete(S, 0, N), Insert(T, S, 0) auf Strings (deklarierter Typ,
//                         Literal, .Text/.Caption) und Pos(…) verglichen mit -1 bzw. >= 0 (#951); umgekehrt
//                         S.IndexOf(…) > 0 bzw. < 1 (nullbasiert, -1 bei keinem Treffer; LastIndexOf nicht,
//                         dort ist "> 0" meist bewusst).
//   null-compare          X = Null bzw. X <> Null (#953): Das Ergebnis hängt von NullEqualityRule ab (Vorgabe
//                         ncrLoose vergleicht wie erwartet, ncrStrict liefert nie wahr, ncrError eine Exception).
//                         Korrektur: Feld.IsNull bei X.Value auf FieldByName/FindField/Fields[…]/Params bzw.
//                         einem Feld vom Typ T…Field/T…Param, sonst VarIsNull(X); bei <> mit not.
//   pos-arguments-swapped Pos(Text, ';') statt Pos(';', Text), ebenso PosEx, StartsText, EndsText (…Str, Ansi…) und
//                         umgekehrt ContainsText(';', Text) (#1045): an der Stelle des Textes ein kurzes Literal
//                         (bis maxLiteralLength Zeichen, Vorgabe 3), an der Stelle des Teils sicher ein String
//                         (deklarierter Typ, .Text/.Caption, String-Funktion, Verkettung). Zeichen bleiben stumm:
//                         Pos(C, ';,') prüft bewusst, ob C einer der Trenner ist.
//   integer-division-to-float
//                         Schnitt := Summe div Anzahl mit Schnitt: Double (#1046): div schneidet ab, bevor zugewiesen
//                         wird; auch Teil div Gesamt * 100, Result und var X: Double := …. Gesucht wird durch Klammern
//                         und + - * / hindurch, nicht in Aufrufen (Round(A div B)). Ziel mit in der Datei deklariertem
//                         Gleitkommatyp; TDateTime bleibt stumm (ganze Tage sind dort meist gewollt), ebenso with
//                         und Trunc(A) div Trunc(B) (ausdrücklich gewandelt, also gewollt ganzzahlig).
//   conditional-expression-version
//                         Bedingungsausdruck X := if C then A else B in einem Projekt, das mit Delphi 12 oder älter
//                         übersetzen muss (#684, Gruppe Compiler, wie E2029): gemeldet wird der äußerste Ausdruck,
//                         nicht in Zweigen von {$IF}, die nach CompilerVersion, RTLVersion, VERnnn oder Declared
//                         fragen. Korrektur „In if-Anweisung umwandeln“ (TConditionalExpression), auch als
//                         Sammelkorrektur. Ohne bekannte Version still.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  OperatorPrecedenceRuleId = 'operator-precedence';
  DuplicateConditionRuleId = 'duplicate-condition';
  StringIndexBaseRuleId = 'string-index-base';
  NullCompareRuleId = 'null-compare';
  PosArgumentsSwappedRuleId = 'pos-arguments-swapped';
  IntegerDivisionToFloatRuleId = 'integer-division-to-float';
  ConditionalExpressionVersionRuleId = 'conditional-expression-version';

type
  TOperatorPrecedenceRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDuplicateConditionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TStringIndexBaseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist AType ein String-Typ (string, AnsiString, ShortString, String[n] …)?</summary>
    class function IsStringType(const AType: string): Boolean; static;
  end;

  TNullCompareRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist AType ein Datenbankfeld oder Parameter (TField, TStringField, TParam, TFDParam …)?</summary>
    class function IsDataType(const AType: string): Boolean; static;
  end;

  TPosArgumentsSwappedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Zeichenzahl eines Literals aus '…'- und #n-Teilen ('''' zählt als ein Zeichen); -1, wenn
    /// ALiteral kein solches Literal ist.</summary>
    class function LiteralLength(const ALiteral: string): Integer; static;
  end;

  TIntegerDivisionToFloatRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Gleitkommatyp mit Nachkommastellen (Double, Single, Extended, Real, Currency …), ohne TDateTime.</summary>
    class function IsFractional(const AType: string): Boolean; static;
  end;

  TConditionalExpressionVersionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Fragt die Direktive ADirective (Text samt Klammern) nach der Compilerversion?</summary>
    class function IsVersionDirective(const ADirective: string): Boolean; static;
  end;

procedure RegisterExpressionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Rules.Options,
  Atlas.Common.Pascal.PureRoutines,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Editing.StatementText,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.ConditionalExpression,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.Expressions.Tokens;

type
  TTokens = TArray<TPascalToken>;

{ TOperatorPrecedenceRule }

function TOperatorPrecedenceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OperatorPrecedenceRuleId, TRuleSeverity.Warning,
    'Vorrang von not vor in und Vergleichen übersehen');
end;

/// <summary>Meldung für "not X op Y" (AShown) mit dem Operator AOp und dem Typ ATypeName von X.</summary>
function PrecedenceMessage(const AOp: TPascalToken; const ATypeName, AName, AShown: string): string;
begin
  if AOp.IsKeyword('in') then
  begin
    Result := Format('„not“ gilt nur für %s, nicht für den in-Ausdruck. Gemeint ist vermutlich not (%s).',
      [AName, AShown]);
  end
  else if TDeclaredTypes.IsInt32(ATypeName) or TDeclaredTypes.IsInt64(ATypeName) then
  begin
    Result := Format('„not“ kehrt die Ganzzahl %s bitweise um, nicht den Vergleich. ' +
      'Gemeint ist vermutlich not (%s).', [AName, AShown]);
  end
  else
  begin
    Result := Format('„not“ gilt nur für %s, nicht für den Vergleich. Gemeint ist vermutlich not (%s).',
      [AName, AShown]);
  end;
end;

/// <summary>Meldet "not X op Y" (AParts) mit dem Typ ATypeName von X samt Korrektur not (X op Y).</summary>
procedure ReportPrecedence(const AContext: TRuleContext; const AReport: IRuleReport; const ATokens: TTokens;
  const AParts: TNotComparison; const ATypeName: string);
var
  mName, mShown: string;
begin
  mName := ATokens[AParts.Operand].Text;
  mShown := Trim(SourceText(AContext.Text, ATokens, AParts.Right, AParts.Last));
  if ATokens[AParts.Right].IsSymbol('[') then
  begin
    mShown := '[…]';
  end;
  mShown := mName + ' ' + ATokens[AParts.Op].Text + ' ' + mShown;
  AReport.Add(RangeOf(ATokens, AParts.NotToken, AParts.Last), PrecedenceMessage(ATokens[AParts.Op], ATypeName,
    mName, mShown), TRuleConfidence.High, [TRuleFix.Create(Format('Klammern setzen: not (%s)', [mShown]),
    [TRuleEdit.Create(RangeOf(ATokens, AParts.Operand, AParts.Last),
    '(' + SourceText(AContext.Text, ATokens, AParts.Operand, AParts.Last) + ')')])]);
end;

procedure TOperatorPrecedenceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mTypes: TDeclaredTypes;
  mIndex: Integer;
  mParts: TNotComparison;
  mTypeName: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mIndex := 0 to High(mTokens) do
    begin
      if not NotComparisonAt(mTokens, mIndex, mParts) or not InStatements(AContext.Tree, mTokens[mIndex].StartPos) then
      begin
        Continue;
      end;
      mTypeName := mTypes.DeclaredType(mTokens[mParts.Operand].Text, mTokens[mParts.Operand].StartPos);
      if (mTypeName <> '') and not IsLogical(mTypeName) then
      begin
        ReportPrecedence(AContext, AReport, mTokens, mParts, mTypeName);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TDuplicateConditionRule }

const
  // Aufrufe, die bei jedem Aufruf etwas anderes liefern können: dann ist die Wiederholung gewollt.
  ImpureCalls: array[0..11] of string = ('Read', 'Readln', 'Next', 'MoveNext', 'Pop', 'Dequeue', 'Extract',
    'Random', 'Execute', 'ExecSQL', 'GetTickCount', 'Now');
  FloatTypes: array[0..4] of string = ('Double', 'Single', 'Extended', 'Real', 'TDateTime');

function TDuplicateConditionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DuplicateConditionRuleId, TRuleSeverity.Warning,
    'Doppelte Bedingung oder gleiche Zweige');
end;

procedure TDuplicateConditionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;

  // Erstes Token ab AOffset (binäre Suche); Length(Tokens) ohne.
  function FirstToken(AOffset: Integer): Integer;
  var
    Lo, Hi, Middle: Integer;
  begin
    Lo := 0;
    Hi := Length(Tokens);
    while Lo < Hi do
    begin
      Middle := (Lo + Hi) div 2;
      if Tokens[Middle].Offset < AOffset then
      begin
        Lo := Middle + 1;
      end
      else
      begin
        Hi := Middle;
      end;
    end;
    Result := Lo;
  end;

  function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
    begin
      Result := Result[0];
    end;
  end;

  // Vergleichsschlüssel: Token ohne Kommentare, Bezeichner und Schlüsselwörter klein.
  function Key(ANode: TSyntaxNode): string;
  var
    Index: Integer;
    Node: TSyntaxNode;
  begin
    Node := Unwrapped(ANode);
    Result := '';
    Index := FirstToken(Node.StartOffset);
    while (Index <= High(Tokens)) and (Tokens[Index].Offset < Node.EndOffset) do
    begin
      if not IsTrivia(Tokens[Index]) then
      begin
        if Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
        begin
          Result := Result + LowerCase(Tokens[Index].Text) + ' ';
        end
        else
        begin
          Result := Result + Tokens[Index].Text + ' ';
        end;
      end;
      Inc(Index);
    end;
  end;

  function Display(ANode: TSyntaxNode): string;
  var
    Node: TSyntaxNode;
  begin
    Node := Unwrapped(ANode);
    Result := Trim(Copy(AContext.Text, Node.StartOffset + 1, Node.EndOffset - Node.StartOffset));
  end;

  // Iterativ (Bericht M1).
  function Impure(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.Call, TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          MatchText(Node.Name, ImpureCalls) then
        begin
          Exit(True);
        end;
        if (Node.Kind = TSyntaxKind.Call) and not TPureRoutines.IsPure(Node.Name) then
        begin
          Exit(True);
        end;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // if … else if …: spätere Bedingung gleich einer früheren.
  procedure CheckChain(AIf: TSyntaxNode);
  var
    Conditions: TArray<TSyntaxNode>;
    Current: TSyntaxNode;
    Index, Earlier: Integer;
  begin
    Conditions := nil;
    Current := AIf;
    while (Current <> nil) and (Current.Kind = TSyntaxKind.IfStatement) and (Current.ChildCount > 0) do
    begin
      Conditions := Conditions + [Current[0]];
      if (Current.ChildCount = 3) and (Current[2].Kind = TSyntaxKind.IfStatement) then
      begin
        Current := Current[2];
      end
      else
      begin
        Current := nil;
      end;
    end;
    // Ein Aufruf in der Kette kann den Zustand ändern, den eine spätere Bedingung liest.
    for Index := 0 to High(Conditions) do
    begin
      if Impure(Conditions[Index]) then
      begin
        Exit;
      end;
    end;
    for Index := 1 to High(Conditions) do
    begin
      for Earlier := 0 to Index - 1 do
      begin
          if Key(Conditions[Earlier]) = Key(Conditions[Index]) then
          begin
            AReport.Add(TTextRange.Create(Conditions[Index].StartPos, Conditions[Index].EndPos),
              Format('Gleiche Bedingung wie in Zeile %d; dieser Zweig wird nie erreicht.',
              [Conditions[Earlier].StartPos.Line + 1]), TRuleConfidence.High,
              [TRuleFix.Jump('Zum ersten Vorkommen springen', Conditions[Earlier].StartPos)]);
            Break;
          end;
      end;
    end;
  end;

  procedure CheckBranches(AIf: TSyntaxNode);
  begin
    if (AIf.ChildCount <> 3) or (AIf[2].Kind = TSyntaxKind.IfStatement) or (Key(AIf[1]) = '') or
      (Key(AIf[1]) <> Key(AIf[2])) then
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(AIf[0].StartPos, AIf[0].EndPos), 'then- und else-Zweig sind gleich; ' +
      'die Bedingung hat keine Wirkung.', TRuleConfidence.High,
      [TRuleFix.Jump('Zum then-Zweig springen', AIf[1].StartPos)]);
  end;

  // Operanden einer Kette aus demselben Operator: A and B and A. Iterativ (Bericht M1): rechter Operand
  // zuerst auf den Stapel, damit die Operanden von links nach rechts in AList landen.
  procedure Operands(ANode: TSyntaxNode; const AOperator: string; var AList: TArray<TSyntaxNode>);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Unwrapped(Pending.Pop);
        if (Node.Kind = TSyntaxKind.BinaryExpr) and SameText(Node.Name, AOperator) and (Node.ChildCount = 2) then
        begin
          Pending.Push(Node[1]);
          Pending.Push(Node[0]);
        end
        else
        begin
          AList := AList + [Node];
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure CheckLogical(ANode: TSyntaxNode);
  var
    List: TArray<TSyntaxNode>;
    Index, Earlier: Integer;
    Op: string;
    Parent: TSyntaxNode;
  begin
    // Nur am Anfang der Kette prüfen, auch durch Klammern hindurch.
    Parent := ANode.Parent;
    while (Parent <> nil) and (Parent.Kind = TSyntaxKind.ParenExpr) do
    begin
      Parent := Parent.Parent;
    end;
    if (Parent <> nil) and (Parent.Kind = TSyntaxKind.BinaryExpr) and SameText(Parent.Name, ANode.Name) then
    begin
      Exit;
    end;
    Op := LowerCase(ANode.Name);
    List := nil;
    Operands(ANode, Op, List);
    for Index := 0 to High(List) do
    begin
      if Impure(List[Index]) then
      begin
        Exit;
      end;
    end;
    for Index := 1 to High(List) do
    begin
      for Earlier := 0 to Index - 1 do
      begin
          if Key(List[Earlier]) = Key(List[Index]) then
          begin
            AReport.Add(TTextRange.Create(List[Index].StartPos, List[Index].EndPos),
              Format('%s steht zweimal in derselben %s-Verknüpfung; vermutlich ein Kopierfehler.',
              [Display(List[Index]), Op]), TRuleConfidence.High,
              [TRuleFix.Jump('Zum ersten Vorkommen springen', List[Earlier].StartPos)]);
            Break;
          end;
      end;
    end;
  end;

  function IsFloat(ANode: TSyntaxNode): Boolean;
  var
    Node: TSyntaxNode;
  begin
    Node := Unwrapped(ANode);
    Result := (Node.Kind = TSyntaxKind.Identifier) and MatchText(Types.DeclaredType(Node.Name, Node.StartPos),
      FloatTypes);
  end;

  // TKlasse.Instanz: Mitglied eines Bezeichners in der Form TName?
  function IsClassMember(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount > 0) and
      (ANode[0].Kind = TSyntaxKind.Identifier);
    Result := Result and (Length(ANode[0].Name) > 1) and (ANode[0].Name[1] = 'T') and
      CharInSet(ANode[0].Name[2], ['A'..'Z']);
  end;

  // TKlasse.Instanz = TKlasse.Instanz prüft bewusst die Identität eines Singletons.
  // Iterativ (Bericht M1).
  function OnClass(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if IsClassMember(Node) then
        begin
          Exit(True);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  procedure CheckComparison(ANode: TSyntaxNode);
  var
    Outcome: string;
  begin
    if (ANode.ChildCount <> 2) or (Key(ANode[0]) <> Key(ANode[1])) or Impure(ANode) or OnClass(ANode) then
    begin
      Exit;
    end;
    // X <> X ist bei Gleitkommazahlen die Prüfung auf NaN.
    if IsFloat(ANode[0]) then
    begin
      Exit;
    end;
    if MatchStr(ANode.Name, ['=', '<=', '>=']) then
    begin
      Outcome := 'True';
    end
    else
    begin
      Outcome := 'False';
    end;
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('%s wird mit sich selbst verglichen; ' +
      'das Ergebnis ist immer %s.', [Display(ANode[0]), Outcome]), TRuleConfidence.High);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.IfStatement then
        begin
          // Kette nur vom ersten if aus.
          if not ((Node.Parent <> nil) and (Node.Parent.Kind = TSyntaxKind.IfStatement) and
            (Node.Parent.ChildCount = 3) and (Node.Parent[2] = Node)) then
          begin
            CheckChain(Node);
          end;
          CheckBranches(Node);
        end
        else if Node.Kind = TSyntaxKind.BinaryExpr then
        begin
          if MatchText(Node.Name, ['and', 'or', 'xor']) then
          begin
            CheckLogical(Node);
          end
          else if MatchStr(Node.Name, ['=', '<>', '<', '>', '<=', '>=']) then
          begin
            CheckComparison(Node);
          end;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    Types.Free;
  end;
end;

{ TStringIndexBaseRule }

function TStringIndexBaseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(StringIndexBaseRuleId, TRuleSeverity.Warning,
    'String-Index ab 0 oder Pos-Ergebnis mit -1 verglichen');
end;

class function TStringIndexBaseRule.IsStringType(const AType: string): Boolean;
var
  Name: string;
begin
  Name := LowerCase(Trim(AType));
  if Pos('[', Name) > 0 then
  begin
    Name := Trim(Copy(Name, 1, Pos('[', Name) - 1));
  end;
  Result := MatchText(Name, ['string', 'unicodestring', 'ansistring', 'widestring', 'rawbytestring', 'utf8string',
    'shortstring', 'tcaption', 'system.string']);
end;

procedure TStringIndexBaseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Types: TDeclaredTypes;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier) and SameText(Token(APosition).Text, AName);
  end;

  function Closing(AOpen: Integer): Integer;
  var
    Depth: Integer;
  begin
    Depth := 0;
    for Result := AOpen to High(Code) do
    begin
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
      begin
        Inc(Depth);
      end
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Exit;
        end;
      end;
    end;
    Result := -1;
  end;

  // Positionen der Argumente (erstes Token) zwischen AOpen und AClose.
  function Arguments(AOpen, AClose: Integer): TArray<Integer>;
  var
    Position, Depth: Integer;
  begin
    Result := [AOpen + 1];
    Depth := 0;
    for Position := AOpen + 1 to AClose - 1 do
    begin
      if Token(Position).IsSymbol('(') or Token(Position).IsSymbol('[') then
      begin
        Inc(Depth);
      end
      else if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
      begin
        Dec(Depth);
      end
      else if (Depth = 0) and Token(Position).IsSymbol(',') then
      begin
        Result := Result + [Position + 1];
      end;
    end;
  end;

  // Ist das Argument ab AFirst bis vor ANext sicher ein String? Deklarierter Typ, Literal oder .Text/.Caption.
  function IsStringArgument(AFirst, ANext: Integer): Boolean;
  var
    Last: Integer;
  begin
    Last := ANext - 1;
    if Last < AFirst then
    begin
      Exit(False);
    end;
    if (AFirst = Last) and (Token(AFirst).Kind = TPascalTokenKind.StringLiteral) then
    begin
      Exit(True);
    end;
    if (Token(Last).Kind = TPascalTokenKind.Identifier) and IsSym(Last - 1, '.') and
      MatchText(Token(Last).Text, ['Text', 'Caption']) then
    begin
      Exit(True);
    end;
    if IsName(AFirst, 'Self') and IsSym(AFirst + 1, '.') then
    begin
      Inc(AFirst, 2);
    end;
    Result := (AFirst = Last) and (Token(AFirst).Kind = TPascalTokenKind.Identifier) and
      IsStringType(Types.DeclaredType(Token(AFirst).Text, Token(AFirst).StartPos));
  end;

  // Ist ARoutine der Aufruf der RTL-Routine (ohne Punkt davor bzw. mit System./StrUtils.)?
  function IsRtlCall(APosition: Integer): Boolean;
  begin
    Result := not IsSym(APosition - 1, '.') or IsName(APosition - 2, 'System') or IsName(APosition - 2, 'StrUtils');
  end;

  // Copy(S, 0, N), Delete(S, 0, N), Insert(T, S, 0).
  procedure CheckStartIndex(APosition: Integer);
  var
    Close, Index: Integer;
    Args: TArray<Integer>;
    Name, Message: string;
    Confidence: TRuleConfidence;
    Literal: TPascalToken;
  begin
    if not IsSym(APosition + 1, '(') or not IsRtlCall(APosition) then
    begin
      Exit;
    end;
    Close := Closing(APosition + 1);
    if Close < 0 then
    begin
      Exit;
    end;
    Args := Arguments(APosition + 1, Close);
    Args := Args + [Close + 1];
    Name := Token(APosition).Text;
    if SameText(Name, 'Insert') then
    begin
      Index := 2;
    end
    else
    begin
      Index := 1;
    end;
    if Length(Args) < Index + 2 then
    begin
      Exit;
    end;
    // Das Argument muss genau "0" sein; der String steht bei Insert an zweiter, sonst an erster Stelle.
    if (Args[Index + 1] - Args[Index] <> 2) or (Token(Args[Index]).Text <> '0') or
      not IsStringArgument(Args[Index - 1], Args[Index] - 1) then
    begin
      Exit;
    end;
    Literal := Token(Args[Index]);
    if SameText(Name, 'Delete') then
    begin
      Message := 'Delete zählt Zeichen ab 1; mit dem Startwert 0 löscht es nichts.';
      Confidence := TRuleConfidence.High;
    end
    else
    begin
      Message := Format('%s zählt Zeichen ab 1; der Startwert 0 wirkt nur zufällig wie 1.', [Name]);
      Confidence := TRuleConfidence.Medium;
    end;
    AReport.Add(TTextRange.Create(Literal.StartPos, Literal.EndPos), Message, Confidence,
      [TRuleFix.Create('Startwert 1', [TRuleEdit.Create(TTextRange.Create(Literal.StartPos, Literal.EndPos), '1')])]);
  end;

  // Rechenoperator (+, -, *, div, mod) beim Code-Token APosition?
  function IsArithmeticAt(APosition: Integer): Boolean;
  begin
    Result := IsSym(APosition, '+') or IsSym(APosition, '-') or IsSym(APosition, '*');
    Result := Result or ((APosition >= 0) and (APosition <= High(Code)) and (Token(APosition).IsKeyword('div') or
      Token(APosition).IsKeyword('mod')));
  end;

  // Vergleich hinter AClose: Operator, optional "-", Zahl. Liefert die Positionen und den Text.
  function Comparison(AAfter: Integer; out AOperator, ALast: Integer; out AText: string): Boolean;
  begin
    AOperator := AAfter;
    ALast := -1;
    AText := '';
    Result := (AAfter <= High(Code)) and IsComparison(Token(AAfter));
    if not Result then
    begin
      Exit;
    end;
    if IsSym(AAfter + 1, '-') and (AAfter + 2 <= High(Code)) and
      (Token(AAfter + 2).Kind = TPascalTokenKind.Number) then
    begin
      ALast := AAfter + 2;
      AText := Token(AAfter).Text + '-' + Token(AAfter + 2).Text;
    end
    else if (AAfter + 1 <= High(Code)) and (Token(AAfter + 1).Kind = TPascalTokenKind.Number) then
    begin
      ALast := AAfter + 1;
      AText := Token(AAfter).Text + Token(AAfter + 1).Text;
    end;
    // "Pos(…) > 1 + X" vergleicht mit einem anderen Wert.
    Result := (ALast >= 0) and not IsArithmeticAt(ALast + 1);
  end;

  function TextOf(AFirst, ALast: Integer): string;
  begin
    Result := SourceText(AContext.Text, Tokens, Code[AFirst], Code[ALast]);
  end;

  // Steht vor APosition ein Rechenoperator ("X + Pos(…) > 0")? Dann gilt der Vergleich der Summe.
  function InArithmetic(APosition: Integer): Boolean;
  begin
    if IsSym(APosition - 1, '.') then
    begin
      Dec(APosition, 2);
    end;
    Result := IsArithmeticAt(APosition - 1);
  end;

  procedure ReportComparison(AOperator, ALast: Integer; const AMessage, AReplacement: string;
    AConfidence: TRuleConfidence);
  var
    Range: TTextRange;
  begin
    Range := TTextRange.Create(Token(AOperator).StartPos, Token(ALast).EndPos);
    AReport.Add(Range, AMessage, AConfidence, [TRuleFix.Create(Format('Vergleich auf "%s" korrigieren',
      [AReplacement]), [TRuleEdit.Create(Range, AReplacement)])]);
  end;

  // Pos(…) > -1, >= 0, <> -1 (immer wahr), = -1, < 0 (nie wahr).
  procedure CheckPos(APosition: Integer);
  var
    Close, Operator, Last: Integer;
    Compare, Name: string;
  begin
    if not IsSym(APosition + 1, '(') or not IsRtlCall(APosition) or InArithmetic(APosition) then
    begin
      Exit;
    end;
    Close := Closing(APosition + 1);
    // "Pos(…) > -1", aber nicht "Pos(…) - 1 > 0" oder "X.Pos".
    if (Close < 0) or not Comparison(Close + 1, Operator, Last, Compare) then
    begin
      Exit;
    end;
    Name := Token(APosition).Text;
    if (Compare = '>-1') or (Compare = '>=0') or (Compare = '<>-1') then
    begin
      ReportComparison(Operator, Last, Format('%s liefert 0 bei keinem Treffer; der Vergleich %s ist immer wahr.',
        [Name, TextOf(Operator, Last)]), '> 0', TRuleConfidence.High);
    end
    else if (Compare = '=-1') or (Compare = '<0') or (Compare = '<=-1') then
    begin
      ReportComparison(Operator, Last, Format('%s liefert 0 bei keinem Treffer; der Vergleich %s ist nie wahr.',
        [Name, TextOf(Operator, Last)]), '= 0', TRuleConfidence.High);
    end;
  end;

  // S.IndexOf(…) > 0 bzw. >= 1 übersieht den Treffer am Anfang; < 1 bzw. <= 0 zählt ihn als "nicht gefunden".
  procedure CheckIndexOf(APosition: Integer);
  var
    Close, Operator, Last: Integer;
    Compare, Name: string;
  begin
    if not IsSym(APosition - 1, '.') or not IsSym(APosition + 1, '(') then
    begin
      Exit;
    end;
    Close := Closing(APosition + 1);
    if (Close < 0) or not Comparison(Close + 1, Operator, Last, Compare) then
    begin
      Exit;
    end;
    Name := Token(APosition).Text;
    if (Compare = '>0') or (Compare = '>=1') then
    begin
      ReportComparison(Operator, Last, Format('%s zählt ab 0 und liefert -1 bei keinem Treffer; der Vergleich %s ' +
        'übersieht den Treffer am Anfang.', [Name, TextOf(Operator, Last)]), '>= 0', TRuleConfidence.Medium);
    end
    else if (Compare = '<1') or (Compare = '<=0') then
    begin
      ReportComparison(Operator, Last, Format('%s zählt ab 0 und liefert -1 bei keinem Treffer; der Vergleich %s ' +
        'zählt den Treffer am Anfang als nicht gefunden.', [Name, TextOf(Operator, Last)]), '< 0',
        TRuleConfidence.Medium);
    end;
  end;

var
  Index, Position: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
  begin
    if not IsTrivia(Tokens[Index]) then
    begin
      Code := Code + [Index];
    end;
  end;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Position := 0 to High(Code) do
    begin
      if Token(Position).Kind <> TPascalTokenKind.Identifier then
      begin
        Continue;
      end;
      if MatchText(Token(Position).Text, ['Copy', 'Delete', 'Insert']) then
      begin
        CheckStartIndex(Position);
      end
      else if MatchText(Token(Position).Text, ['Pos', 'PosEx', 'AnsiPos']) then
      begin
        CheckPos(Position);
      end
      // LastIndexOf(…) > 0 heißt meist bewusst "Trenner nicht am Anfang" (Name.LastIndexOf('.') > 0).
      else if MatchText(Token(Position).Text, ['IndexOf', 'IndexOfAny']) then
      begin
        CheckIndexOf(Position);
      end;
    end;
  finally
    Types.Free;
  end;
end;

{ TNullCompareRule }

function TNullCompareRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(NullCompareRuleId, TRuleSeverity.Warning,
    'Vergleich mit Null statt VarIsNull oder IsNull');
end;

class function TNullCompareRule.IsDataType(const AType: string): Boolean;
var
  Name: string;
begin
  Name := Copy(Trim(AType), LastDelimiter('.', Trim(AType)) + 1, MaxInt);
  Result := (Length(Name) > 1) and (Name[1] = 'T') and (EndsText('Field', Name) or EndsText('Param', Name));
end;

procedure TNullCompareRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Code: TArray<Integer>;
  Types: TDeclaredTypes;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsKey(APosition: Integer; const AKeyword: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsKeyword(AKeyword);
  end;

  function IsWord(APosition: Integer): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := IsWord(APosition) and SameText(Token(APosition).Text, AName);
  end;

  function TextOf(AFirst, ALast: Integer): string;
  begin
    Result := Copy(AContext.Text, Token(AFirst).Offset + 1,
      Token(ALast).Offset + Length(Token(ALast).Text) - Token(AFirst).Offset);
  end;

  // Position vor der öffnenden Klammer zur schließenden bei APosition; -1, wenn keine passt.
  function BeforeBrackets(APosition: Integer): Integer;
  var
    mDepth: Integer;
  begin
    Result := APosition;
    mDepth := 0;
    repeat
      if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Inc(mDepth);
      end
      else if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
      begin
        Dec(mDepth);
      end;
      Dec(Result);
    until (mDepth = 0) or (Result < 0);
  end;

  // Position hinter der schließenden Klammer zur öffnenden bei APosition; -1, wenn keine passt.
  function AfterBrackets(APosition: Integer): Integer;
  var
    mDepth: Integer;
  begin
    Result := APosition;
    mDepth := 0;
    repeat
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(mDepth);
      end;
      Inc(Result);
    until (mDepth = 0) or (Result > High(Code));
    if mDepth <> 0 then
    begin
      Result := -1;
    end;
  end;

  // Erstes Token der Kette (A, A.B, A(…), A[…]), die bei ALast endet; -1 bei anderen Ausdrücken.
  function ChainStart(ALast: Integer): Integer;
  var
    mPosition: Integer;
  begin
    Result := -1;
    mPosition := ALast;
    while mPosition >= 0 do
    begin
      if Token(mPosition).IsSymbol(')') or Token(mPosition).IsSymbol(']') then
      begin
        mPosition := BeforeBrackets(mPosition);
      end;
      if (mPosition < 0) or not IsWord(mPosition) then
      begin
        Exit;
      end;
      if not IsSym(mPosition - 1, '.') then
      begin
        Exit(mPosition);
      end;
      Dec(mPosition, 2);
    end;
  end;

  // Letztes Token der Kette ab AFirst; -1, wenn dort keine beginnt.
  function ChainEnd(AFirst: Integer): Integer;
  var
    mPosition: Integer;
  begin
    Result := -1;
    mPosition := AFirst;
    while IsWord(mPosition) do
    begin
      Result := mPosition;
      Inc(mPosition);
      while IsSym(mPosition, '(') or IsSym(mPosition, '[') do
      begin
        mPosition := AfterBrackets(mPosition);
        if mPosition < 0 then
        begin
          Exit(-1);
        end;
        Result := mPosition - 1;
      end;
      if not IsSym(mPosition, '.') then
      begin
        Exit;
      end;
      Inc(mPosition);
    end;
    Result := -1;
  end;

  // Vor dem Vergleich: Anfang einer Bedingung oder eines Arguments (sonst bindet ein Operator anders).
  function OpensExpression(APosition: Integer): Boolean;
  begin
    Result := IsSym(APosition, '(') or IsSym(APosition, ',') or IsSym(APosition, ':=') or IsKey(APosition, 'if') or
      IsKey(APosition, 'while') or IsKey(APosition, 'until') or IsKey(APosition, 'not');
  end;

  // Nach dem Vergleich: Ende der Bedingung oder des Arguments.
  function ClosesExpression(APosition: Integer): Boolean;
  begin
    Result := (APosition > High(Code)) or IsSym(APosition, ')') or IsSym(APosition, ',') or
      IsSym(APosition, ';') or IsKey(APosition, 'then') or IsKey(APosition, 'do') or IsKey(APosition, 'else') or
      IsKey(APosition, 'end');
  end;

  // Ist die Kette AFirst..ALast "X.Value" auf einem Feld oder Parameter? ABase liefert X.
  function DataValue(AFirst, ALast: Integer; out ABase: string): Boolean;
  var
    Position: Integer;
  begin
    Result := False;
    if (ALast - AFirst < 2) or not IsName(ALast, 'Value') or not IsSym(ALast - 1, '.') then
    begin
      Exit;
    end;
    ABase := TextOf(AFirst, ALast - 2);
    // FieldByName('…'), FindField, Fields[…], ParamByName, Params[…] in der Kette.
    for Position := AFirst to ALast - 2 do
    begin
      if IsWord(Position) and (MatchText(Token(Position).Text, ['FieldByName', 'FindField', 'ParamByName',
        'FindParam']) or (MatchText(Token(Position).Text, ['Fields', 'Params']) and IsSym(Position + 1, '['))) then
      begin
        Exit(True);
      end;
    end;
    // Feld mit deklariertem Typ TStringField, TIntegerField, TParam …
    Result := (ALast - 2 = AFirst) and IsDataType(Types.DeclaredType(Token(AFirst).Text, Token(AFirst).StartPos));
  end;

  procedure ReportAt(AFirst, ALast, AOperator, AExprFirst, AExprLast: Integer);
  var
    Base, Replacement, Message, Prefix: string;
  begin
    if Token(AOperator).IsSymbol('<>') then
    begin
      Prefix := 'not ';
    end
    else
    begin
      Prefix := '';
    end;
    if DataValue(AExprFirst, AExprLast, Base) then
    begin
      Replacement := Prefix + Base + '.IsNull';
      Message := 'Der Vergleich mit Null hängt von NullEqualityRule ab (ncrStrict: nie wahr, ncrError: ' +
        'Exception); IsNull prüft das Feld unabhängig davon.';
    end
    else
    begin
      Replacement := Prefix + 'VarIsNull(' + TextOf(AExprFirst, AExprLast) + ')';
      Message := 'Der Vergleich mit Null hängt von NullEqualityRule ab (ncrStrict: nie wahr, ncrError: ' +
        'Exception); VarIsNull prüft den Wert unabhängig davon.';
    end;
    // "not X = Null" bindet als "(not X) = Null": dann keine Korrektur, die Bedeutung ist unklar.
    if IsKey(AFirst - 1, 'not') then
    begin
      AReport.Add(TTextRange.Create(Token(AFirst).StartPos, Token(ALast).EndPos), Message);
    end
    else
    begin
      AReport.Add(TTextRange.Create(Token(AFirst).StartPos, Token(ALast).EndPos), Message,
        [TRuleFix.Create(Format('Durch "%s" ersetzen', [Replacement]),
        [TRuleEdit.Create(TTextRange.Create(Token(AFirst).StartPos, Token(ALast).EndPos), Replacement)])]);
    end;
  end;

  procedure CheckAt(APosition: Integer);
  var
    First, Last: Integer;
  begin
    // X = Null bzw. X <> Null
    if IsSym(APosition - 1, '=') or IsSym(APosition - 1, '<>') then
    begin
      First := ChainStart(APosition - 2);
      if (First >= 0) and OpensExpression(First - 1) and ClosesExpression(APosition + 1) then
      begin
        ReportAt(First, APosition, APosition - 1, First, APosition - 2);
      end;
    end
    // Null = X bzw. Null <> X
    else if (IsSym(APosition + 1, '=') or IsSym(APosition + 1, '<>')) and OpensExpression(APosition - 1) then
    begin
      Last := ChainEnd(APosition + 2);
      if (Last >= 0) and ClosesExpression(Last + 1) then
      begin
        ReportAt(APosition, Last, APosition + 1, APosition + 2, Last);
      end;
    end;
  end;

var
  Index, Position: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Null') then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
  begin
    if not IsTrivia(Tokens[Index]) then
    begin
      Code := Code + [Index];
    end;
  end;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Position := 0 to High(Code) do
    begin
      // Null als Wert: nicht Teil einer Kette (X.Null) und kein Aufruf.
      if IsName(Position, 'Null') and not IsSym(Position - 1, '.') and not IsSym(Position + 1, '.') and
        not IsSym(Position + 1, '(') then
      begin
        CheckAt(Position);
      end;
    end;
  finally
    Types.Free;
  end;
end;

{ TPosArgumentsSwappedRule }

function TPosArgumentsSwappedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(PosArgumentsSwappedRuleId, TRuleSeverity.Warning,
    'Argumente von Pos, StartsText oder ContainsText vertauscht');
end;

class function TPosArgumentsSwappedRule.LiteralLength(const ALiteral: string): Integer;
begin
  Result := PascalLiteralLength(ALiteral);
end;

procedure TPosArgumentsSwappedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Types: TDeclaredTypes;
  MaxLength: Integer;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(Code)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier) and SameText(Token(APosition).Text, AName);
  end;

  function Closing(AOpen: Integer): Integer;
  var
    Depth: Integer;
  begin
    Depth := 0;
    for Result := AOpen to High(Code) do
    begin
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
      begin
        Inc(Depth);
      end
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(Depth);
        if Depth = 0 then
        begin
          Exit;
        end;
      end;
    end;
    Result := -1;
  end;

  // Erstes Token jedes Arguments zwischen AOpen und AClose, dazu AClose + 1 als Ende des letzten.
  function Arguments(AOpen, AClose: Integer): TArray<Integer>;
  var
    Position, Depth: Integer;
  begin
    Result := [AOpen + 1];
    Depth := 0;
    for Position := AOpen + 1 to AClose - 1 do
    begin
      if Token(Position).IsSymbol('(') or Token(Position).IsSymbol('[') then
      begin
        Inc(Depth);
      end
      else if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
      begin
        Dec(Depth);
      end
      else if (Depth = 0) and Token(Position).IsSymbol(',') then
      begin
        Result := Result + [Position + 1];
      end;
    end;
    Result := Result + [AClose + 1];
  end;

  function TextOf(AFirst, ALast: Integer): string;
  begin
    Result := SourceText(AContext.Text, Tokens, Code[AFirst], Code[ALast]);
  end;

  // Zeichenzahl des Literals AFirst..ALast (nur String- und Zeichenliterale, keine mehrzeiligen); -1 sonst.
  function Literal(AFirst, ALast: Integer): Integer;
  var
    Position: Integer;
    Text: string;
  begin
    if ALast < AFirst then
    begin
      Exit(-1);
    end;
    Text := '';
    for Position := AFirst to ALast do
    begin
      if not (Token(Position).Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]) or
        (Pos(#10, Token(Position).Text) > 0) then
      begin
        Exit(-1);
      end;
      Text := Text + Token(Position).Text;
    end;
    Result := LiteralLength(Text);
  end;

  // Teil AFirst..ALast ohne + auf oberster Ebene: deklarierter String-Typ, .Text/.Caption oder Aufruf einer
  // String-Funktion der RTL.
  function IsStringPart(AFirst, ALast: Integer): Boolean;
  begin
    if ALast < AFirst then
    begin
      Exit(False);
    end;
    if (Token(ALast).Kind = TPascalTokenKind.Identifier) and IsSym(ALast - 1, '.') and
      MatchText(Token(ALast).Text, ['Text', 'Caption']) then
    begin
      Exit(True);
    end;
    if (Token(AFirst).Kind = TPascalTokenKind.Identifier) and IsSym(AFirst + 1, '(') and
      not IsSym(AFirst - 1, '.') and MatchText(Token(AFirst).Text, ['Trim', 'TrimLeft', 'TrimRight', 'UpperCase',
      'LowerCase', 'AnsiUpperCase', 'AnsiLowerCase', 'IntToStr', 'Format', 'QuotedStr', 'StringReplace',
      'ExtractFileName', 'ExtractFilePath', 'ExtractFileExt', 'ChangeFileExt', 'IncludeTrailingPathDelimiter',
      'ExcludeTrailingPathDelimiter', 'LeftStr', 'RightStr', 'MidStr', 'ReverseString', 'DupeString']) then
    begin
      Exit(Closing(AFirst + 1) = ALast);
    end;
    if IsName(AFirst, 'Self') and IsSym(AFirst + 1, '.') then
    begin
      Inc(AFirst, 2);
    end;
    Result := (AFirst = ALast) and (Token(AFirst).Kind = TPascalTokenKind.Identifier) and
      TStringIndexBaseRule.IsStringType(Types.DeclaredType(Token(AFirst).Text, Token(AFirst).StartPos));
  end;

  // Erstes + auf oberster Klammerebene in AFirst..ALast; -1 ohne.
  function TopLevelPlus(AFirst, ALast: Integer): Integer;
  var
    mPosition, mDepth: Integer;
  begin
    Result := -1;
    mDepth := 0;
    mPosition := AFirst;
    while (Result < 0) and (mPosition <= ALast) do
    begin
      if Token(mPosition).IsSymbol('(') or Token(mPosition).IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if Token(mPosition).IsSymbol(')') or Token(mPosition).IsSymbol(']') then
      begin
        Dec(mDepth);
      end
      else if (mDepth = 0) and Token(mPosition).IsSymbol('+') then
      begin
        Result := mPosition;
      end;
      Inc(mPosition);
    end;
  end;

  // Ist das Argument AFirst..ALast sicher ein String und kein Zeichen? Deklarierter String-Typ, .Text/.Caption,
  // Aufruf einer String-Funktion der RTL oder Verkettung mit einem String-Teil. Iterativ (Bericht M1): die
  // Teile einer langen Verkettung nacheinander statt einer Rekursionsebene je +.
  function IsStringArgument(AFirst, ALast: Integer): Boolean;
  var
    mStart, mPlus: Integer;
  begin
    Result := False;
    mStart := AFirst;
    while mStart <= ALast do
    begin
      mPlus := TopLevelPlus(mStart, ALast);
      if mPlus < 0 then
      begin
        Exit(IsStringPart(mStart, ALast));
      end;
      // Zeichen + Zeichen ist schon ein String, Zahl + Zahl nicht: ein Teil muss sicher String sein.
      if IsStringPart(mStart, mPlus - 1) or (Literal(mStart, mPlus - 1) >= 2) or (Literal(mPlus + 1, ALast) >= 2) then
      begin
        Exit(True);
      end;
      mStart := mPlus + 1;
    end;
  end;

  // ATextFirst: ContainsText(Text, Teil), sonst Pos(Teil, Text). Vertauscht steht an der Stelle des Textes ein
  // kurzes Literal und an der Stelle des Teils ein String.
  procedure CheckCall(APosition: Integer; ATextFirst: Boolean);
  var
    Close, TextArg, PartArg, Size: Integer;
    Args: TArray<Integer>;
    Name, Message, Between: string;
    Range: TTextRange;
  begin
    // Nur die RTL-Routine: ohne Punkt davor oder mit System. bzw. StrUtils. (auch System.StrUtils.).
    if not IsSym(APosition + 1, '(') or (IsSym(APosition - 1, '.') and not IsName(APosition - 2, 'System') and
      not IsName(APosition - 2, 'StrUtils')) then
    begin
      Exit;
    end;
    Close := Closing(APosition + 1);
    if Close < 0 then
    begin
      Exit;
    end;
    Args := Arguments(APosition + 1, Close);
    if Length(Args) < 3 then
    begin
      Exit;
    end;
    if ATextFirst then
    begin
      TextArg := 0;
      PartArg := 1;
    end
    else
    begin
      TextArg := 1;
      PartArg := 0;
    end;
    Size := Literal(Args[TextArg], Args[TextArg + 1] - 2);
    if (Size < 1) or (Size > MaxLength) or (Literal(Args[PartArg], Args[PartArg + 1] - 2) >= 0) or
      not IsStringArgument(Args[PartArg], Args[PartArg + 1] - 2) then
    begin
      Exit;
    end;
    Name := Token(APosition).Text;
    if ATextFirst then
    begin
      Message := '%s(Text, Teil): vermutlich vertauscht, gesucht wird %s in %s.';
    end
    else
    begin
      Message := '%s(Teil, Text): vermutlich vertauscht, gesucht wird %s in %s.';
    end;
    Message := Format(Message, [Name, TextOf(Args[TextArg], Args[TextArg + 1] - 2),
      TextOf(Args[PartArg], Args[PartArg + 1] - 2)]);
    // Eine Änderung über beide Argumente (ein Undo-Schritt); Komma, Leerraum und Kommentare dazwischen bleiben.
    Between := Copy(AContext.Text, Tokens[Code[Args[1] - 2]].Offset + Length(Tokens[Code[Args[1] - 2]].Text) + 1,
      Tokens[Code[Args[1]]].Offset - Tokens[Code[Args[1] - 2]].Offset - Length(Tokens[Code[Args[1] - 2]].Text));
    Range := TTextRange.Create(Token(Args[0]).StartPos, Token(Args[2] - 2).EndPos);
    AReport.Add(Range, Message, TRuleConfidence.Medium, [TRuleFix.Create('Argumente tauschen',
      [TRuleEdit.Create(Range, TextOf(Args[1], Args[2] - 2) + Between + TextOf(Args[0], Args[1] - 2))])]);
  end;

var
  Index, Position: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  MaxLength := TRuleOptions.Int(AContext.Options, 'maxLiteralLength', 3);
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
  begin
    if not IsTrivia(Tokens[Index]) then
    begin
      Code := Code + [Index];
    end;
  end;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Position := 0 to High(Code) do
    begin
      if Token(Position).Kind <> TPascalTokenKind.Identifier then
      begin
        Continue;
      end;
      if MatchText(Token(Position).Text, ['Pos', 'PosEx', 'AnsiPos', 'StartsText', 'StartsStr', 'EndsText',
        'EndsStr', 'AnsiStartsText', 'AnsiStartsStr', 'AnsiEndsText', 'AnsiEndsStr']) then
      begin
        CheckCall(Position, False);
      end
      else if MatchText(Token(Position).Text, ['ContainsText', 'ContainsStr', 'AnsiContainsText',
        'AnsiContainsStr']) then
      begin
        CheckCall(Position, True);
      end;
    end;
  finally
    Types.Free;
  end;
end;

{ TIntegerDivisionToFloatRule }

function TIntegerDivisionToFloatRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(IntegerDivisionToFloatRuleId, TRuleSeverity.Warning,
    'Ganzzahldivision an Gleitkommazahl');
end;

class function TIntegerDivisionToFloatRule.IsFractional(const AType: string): Boolean;
begin
  // TDateTime, TDate und TTime nicht: A div B als ganze Tage ist dort meist gewollt; Comp ist ganzzahlig.
  Result := MatchText(Trim(AType), ['Single', 'Double', 'Extended', 'Real', 'Real48', 'Float32', 'Float64',
    'Currency', 'System.Single', 'System.Double', 'System.Extended', 'System.Currency']);
end;

procedure TIntegerDivisionToFloatRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Types: TDeclaredTypes;

  // Typ des Funktionsergebnisses der Routine um ANode; '' ohne Funktion.
  function ResultType(ANode: TSyntaxNode): string;
  var
    Header, Reference: TSyntaxNode;
  begin
    Result := '';
    while (ANode <> nil) and not (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
    begin
      ANode := ANode.Parent;
    end;
    if (ANode = nil) or (ANode.Kind <> TSyntaxKind.RoutineDecl) then
    begin
      Exit;
    end;
    Header := ANode.FindChild(TSyntaxKind.RoutineHeader);
    if Header = nil then
    begin
      Exit;
    end;
    Reference := Header.FindChild(TSyntaxKind.TypeReference);
    if Reference <> nil then
    begin
      Result := Trim(Copy(AContext.Text, Reference.StartOffset + 1, Reference.EndOffset - Reference.StartOffset));
    end;
  end;

  // Steht ANode in einem with-Block? Dann kann der Name ein Feld des with-Objekts sein.
  function InWith(ANode: TSyntaxNode): Boolean;
  begin
    while ANode <> nil do
    begin
      if ANode.Kind = TSyntaxKind.WithStatement then
      begin
        Exit(True);
      end;
      ANode := ANode.Parent;
    end;
    Result := False;
  end;

  // Das Schlüsselwort div zwischen den Operanden von ADivision.
  function DivToken(ADivision: TSyntaxNode; out AToken: TPascalToken): Boolean;
  var
    Index: Integer;
  begin
    for Index := TSyntaxTree.FirstTokenOf(Tokens, ADivision[0].EndOffset) to High(Tokens) do
    begin
      if (Tokens[Index].Offset >= ADivision[0].EndOffset) and (Tokens[Index].Offset < ADivision[1].StartOffset) and
        Tokens[Index].IsKeyword('div') then
      begin
        AToken := Tokens[Index];
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Trunc(X), Round(X), Floor(X), Ceil(X): Wer Gleitkommazahlen ausdrücklich in Ganzzahlen wandelt und dann
  // mit div teilt, will die ganzzahlige Division (Trunc(A) div Trunc(B) im Präprozessor).
  function IsExplicitInteger(AOperand: TSyntaxNode): Boolean;
  begin
    while (AOperand.Kind = TSyntaxKind.ParenExpr) and (AOperand.ChildCount = 1) do
    begin
      AOperand := AOperand[0];
    end;
    Result := (AOperand.Kind = TSyntaxKind.Call) and (AOperand.ChildCount > 0) and
      (AOperand[0].Kind = TSyntaxKind.Identifier) and MatchText(AOperand[0].Name, ['Trunc', 'Round', 'Floor', 'Ceil']);
  end;

  // Meldet die Division ANode, wenn keiner der Operanden ausdrücklich ganzzahlig gewandelt ist.
  procedure CheckDiv(ANode: TSyntaxNode; const ATarget, AType: string);
  var
    mToken: TPascalToken;
  begin
    if IsExplicitInteger(ANode[0]) or IsExplicitInteger(ANode[1]) or not DivToken(ANode, mToken) then
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
      Format('div rechnet ganzzahlig; %s ist %s und verliert die Nachkommastellen.', [ATarget, AType]),
      TRuleConfidence.High, [TRuleFix.Create('div durch / ersetzen',
      [TRuleEdit.Create(TTextRange.Create(mToken.StartPos, mToken.EndPos), '/')])]);
  end;

  // Führt das Ergebnis von ANode ungekürzt weiter: Klammern, Vorzeichen und + - * /?
  function PassesThrough(ANode: TSyntaxNode): Boolean;
  begin
    case ANode.Kind of
      TSyntaxKind.ParenExpr:
        Result := True;
      TSyntaxKind.UnaryExpr:
        Result := (ANode.Name = '-') or (ANode.Name = '+');
      TSyntaxKind.BinaryExpr:
        Result := MatchStr(ANode.Name, ['+', '-', '*', '/']);
    else
      Result := False;
    end;
  end;

  // div in AExpression, deren Ergebnis ungekürzt in die Gleitkommazahl fließt: durch Klammern, Vorzeichen und
  // + - * / hindurch, nicht in Aufrufe, Indizes, mod oder Vergleiche.
  // Iterativ (Bericht M1).
  procedure Search(AExpression: TSyntaxNode; const ATarget, AType: string);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AExpression);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.BinaryExpr) and SameText(mNode.Name, 'div') and (mNode.ChildCount = 2) then
        begin
          CheckDiv(mNode, ATarget, AType);
        end
        else if PassesThrough(mNode) then
        begin
          for mIndex := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  procedure CheckAssignment(ANode: TSyntaxNode);
  var
    Target: TSyntaxNode;
    Name, TypeName: string;
  begin
    if (ANode.ChildCount <> 2) or InWith(ANode) then
    begin
      Exit;
    end;
    Target := ANode[0];
    // Self.X wie X.
    if (Target.Kind = TSyntaxKind.MemberAccess) and (Target.ChildCount = 1) and
      (Target[0].Kind = TSyntaxKind.Identifier) and SameText(Target[0].Name, 'Self') then
    begin
      Name := Target.Name;
    end
    else if Target.Kind = TSyntaxKind.Identifier then
    begin
      Name := Target.Name;
    end
    else
    begin
      Exit;
    end;
    if SameText(Name, 'Result') then
    begin
      TypeName := Types.DeclaredType(Name, Target.StartPos);
      if TypeName = '' then
      begin
        TypeName := ResultType(ANode);
      end;
    end
    else
    begin
      TypeName := Types.DeclaredType(Name, Target.StartPos);
    end;
    if IsFractional(TypeName) then
    begin
      Search(ANode[1], Name, TypeName);
    end;
  end;

  // var Schnitt: Double := Summe div Anzahl;
  procedure CheckInlineVar(ANode: TSyntaxNode);
  var
    Index: Integer;
    TypeName: string;
  begin
    if (ANode.ChildCount <> 2) or (Pos(',', ANode.Name) > 0) or (ANode[0].Kind <> TSyntaxKind.TypeReference) then
    begin
      Exit;
    end;
    TypeName := Trim(Copy(AContext.Text, ANode[0].StartOffset + 1, ANode[0].EndOffset - ANode[0].StartOffset));
    if IsFractional(TypeName) then
    begin
      for Index := 1 to ANode.ChildCount - 1 do
      begin
        Search(ANode[Index], Trim(ANode.Name), TypeName);
      end;
    end;
  end;

  // Iterativ (Bericht M1).
  procedure Walk(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AssignStatement then
        begin
          CheckAssignment(Node);
        end
        else if Node.Kind = TSyntaxKind.InlineVar then
        begin
          CheckInlineVar(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Walk(AContext.Tree.Root);
  finally
    Types.Free;
  end;
end;

{ TConditionalExpressionVersionRule }

type
  TOffsetRange = record
    Start: Integer;
    Stop: Integer;
  end;

  TVersionBlock = record
    Start: Integer;
    Version: Boolean;
  end;

function TConditionalExpressionVersionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(ConditionalExpressionVersionRuleId, TRuleSeverity.Error,
    'Bedingungsausdruck vor Delphi 13');
end;

class function TConditionalExpressionVersionRule.IsVersionDirective(const ADirective: string): Boolean;
var
  Text: string;
  Index: Integer;
begin
  Text := UpperCase(ADirective);
  Result := ContainsStr(Text, 'COMPILERVERSION') or ContainsStr(Text, 'RTLVERSION') or
    ContainsStr(Text, 'DECLARED');
  // VER370, VER360 …
  Index := Pos('VER', Text);
  while not Result and (Index > 0) do
  begin
    Result := (Index + 3 <= Length(Text)) and CharInSet(Text[Index + 3], ['0'..'9']) and
      ((Index = 1) or not CharInSet(Text[Index - 1], ['A'..'Z', '0'..'9', '_']));
    Index := PosEx('VER', Text, Index + 3);
  end;
end;

/// <summary>Offsetbereiche der {$IF…}-Blöcke (alle Zweige), die nach der Compilerversion fragen.</summary>
function VersionBlocks(const ATokens: TArray<TPascalToken>): TArray<TOffsetRange>;
var
  Stack: TArray<TVersionBlock>;
  Block: TVersionBlock;
  Range: TOffsetRange;
  Token: TPascalToken;
  Name: string;
begin
  Result := nil;
  Stack := nil;
  for Token in ATokens do
  begin
    if Token.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    Name := TPascalLexer.DirectiveName(Token.Text);
    if (Name = 'IF') or (Name = 'IFDEF') or (Name = 'IFNDEF') or (Name = 'IFOPT') then
    begin
      Block.Start := Token.Offset;
      Block.Version := TConditionalExpressionVersionRule.IsVersionDirective(Token.Text);
      Stack := Stack + [Block];
    end
    else if (Name = 'ELSEIF') and (Stack <> nil) and not Stack[High(Stack)].Version and
      TConditionalExpressionVersionRule.IsVersionDirective(Token.Text) then
    begin
      Stack[High(Stack)].Version := True;
      Stack[High(Stack)].Start := Token.Offset;
    end
    else if ((Name = 'ENDIF') or (Name = 'IFEND')) and (Stack <> nil) then
    begin
      if Stack[High(Stack)].Version then
      begin
        Range.Start := Stack[High(Stack)].Start;
        Range.Stop := Token.Offset + Length(Token.Text);
        Result := Result + [Range];
      end;
      SetLength(Stack, Length(Stack) - 1);
    end;
  end;
end;

procedure TConditionalExpressionVersionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Blocks: TArray<TOffsetRange>;
  Found: TArray<TSyntaxNode>;
  Node: TSyntaxNode;
  Layout: TStatementLayout;
  Rewrite: TStatementRewrite;
  Fixes: TArray<TRuleFix>;
  Message: string;

  function Guarded(AOffset: Integer): Boolean;
  var
    Range: TOffsetRange;
  begin
    Result := False;
    for Range in Blocks do
    begin
      if (AOffset >= Range.Start) and (AOffset < Range.Stop) then
      begin
        Exit(True);
      end;
    end;
  end;

begin
  // Ohne bekannte Version (IsAvailable liefert dann True) oder ab Delphi 13 still.
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    TLanguageFeatures.IsAvailable(TLanguageFeature.IfExpression, AContext.DelphiVersion) then
  begin
    Exit;
  end;
  Found := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if (ANode.Kind = TSyntaxKind.IfExpr) and (TConditionalExpression.Outermost(ANode) = ANode) then
      begin
        Found := Found + [ANode];
      end;
    end);
  if Found = nil then
  begin
    Exit;
  end;
  Blocks := VersionBlocks(AContext.Tree.Tokens);
  Layout := TStatementLayout.Create('', TRoutineBody.IndentUnit(AContext.Formatting),
    TTextLines.LineBreakOf(AContext.Text));
  Message := Format('Bedingungsausdrücke gibt es erst ab %s (eingestellt: %s)',
    [TLanguageFeatures.ProductName(TLanguageFeatures.MinimumVersion(TLanguageFeature.IfExpression)),
    TLanguageFeatures.ProductName(AContext.DelphiVersion)]);
  for Node in Found do
  begin
    if Guarded(Node.StartOffset) then
    begin
      Continue;
    end;
    Fixes := nil;
    if TConditionalExpression.ToStatement(AContext.Text, AContext.Tree, Node, Layout, Rewrite) then
    begin
      Fixes := [TRuleFix.Create(Rewrite.Title, [TRuleEdit.Create(Rewrite.Edit.Range, Rewrite.Edit.NewText)])];
    end;
    AReport.Add(TTextRange.Create(Node.StartPos, Node.EndPos), Message, TRuleConfidence.High, Fixes);
  end;
end;

procedure RegisterExpressionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOperatorPrecedenceRule.Create);
  ARegistry.Register(TDuplicateConditionRule.Create);
  ARegistry.Register(TStringIndexBaseRule.Create);
  ARegistry.Register(TNullCompareRule.Create);
  ARegistry.Register(TPosArgumentsSwappedRule.Create);
  ARegistry.Register(TIntegerDivisionToFloatRule.Create);
  ARegistry.Register(TConditionalExpressionVersionRule.Create);
end;

end.
