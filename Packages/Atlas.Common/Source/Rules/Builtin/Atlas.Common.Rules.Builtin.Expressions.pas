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

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  OperatorPrecedenceRuleId = 'operator-precedence';
  DuplicateConditionRuleId = 'duplicate-condition';

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

procedure RegisterExpressionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes;

type
  TTokens = TArray<TPascalToken>;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
    Inc(Result);
end;

function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
    Dec(Result);
end;

/// <summary>Quelltext der Token AFirst..ALast wie geschrieben.</summary>
function SourceText(const AText: string; const ATokens: TTokens; AFirst, ALast: Integer): string;
begin
  Result := Copy(AText, ATokens[AFirst].Offset + 1,
    ATokens[ALast].Offset + Length(ATokens[ALast].Text) - ATokens[AFirst].Offset);
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

function IsComparison(const AToken: TPascalToken): Boolean;
begin
  Result := (AToken.Kind = TPascalTokenKind.Symbol) and MatchStr(AToken.Text, ['=', '<>', '<', '>', '<=', '>=']);
end;

/// <summary>Boolescher Typ oder Variant: not wirkt dort wie gemeint bzw. ist nicht sicher zu beurteilen.</summary>
function IsLogical(const AType: string): Boolean;
begin
  Result := MatchText(AType, ['Boolean', 'ByteBool', 'WordBool', 'LongBool', 'Variant', 'OleVariant']);
end;

/// <summary>Einfacher Bezeichner: kein Teil einer Kette A.B und kein Aufruf.</summary>
function IsPlainIdentifier(const ATokens: TTokens; AIndex: Integer): Boolean;
var
  Prev, Next: Integer;
begin
  if (AIndex < 0) or (AIndex > High(ATokens)) or (ATokens[AIndex].Kind <> TPascalTokenKind.Identifier) then
    Exit(False);
  Prev := PreviousCode(ATokens, AIndex);
  Next := NextCode(ATokens, AIndex + 1);
  Result := not ((Prev >= 0) and (ATokens[Prev].IsSymbol('.') or ATokens[Prev].IsSymbol('@'))) and
    not ((Next <= High(ATokens)) and (ATokens[Next].IsSymbol('.') or ATokens[Next].IsSymbol('(') or
    ATokens[Next].IsSymbol('[') or ATokens[Next].IsSymbol('^')));
end;

/// <summary>Letztes Token des rechten Operanden ab AStart: bis vor das nächste Wort oder Zeichen, das den
/// Vergleich beendet (then, and, ;, schließende Klammer …), auf derselben Klammerebene; -1 ohne Operand.</summary>
function OperandEnd(const ATokens: TTokens; AStart: Integer): Integer;
var
  Index, Depth: Integer;
  Token: TPascalToken;
begin
  Result := -1;
  Depth := 0;
  Index := AStart;
  while Index <= High(ATokens) do
  begin
    Token := ATokens[Index];
    if not IsTrivia(Token) then
    begin
      if Token.IsSymbol('(') or Token.IsSymbol('[') then
        Inc(Depth)
      else if Token.IsSymbol(')') or Token.IsSymbol(']') then
      begin
        if Depth = 0 then
          Exit;
        Dec(Depth);
      end
      else if Depth = 0 then
      begin
        if ((Token.Kind = TPascalTokenKind.Keyword) and MatchText(Token.Text, ['then', 'do', 'of', 'else',
          'until', 'end', 'to', 'downto', 'and', 'or', 'xor', 'in', 'begin', 'except', 'finally'])) or
          Token.IsSymbol(';') or Token.IsSymbol(',') or Token.IsSymbol(':=') or Token.IsSymbol(':') or
          IsComparison(Token) then
          Exit;
      end;
      Result := Index;
    end;
    Inc(Index);
  end;
end;

/// <summary>Liegt APosition im Rumpf (begin … end) einer Routine?</summary>
function InStatements(ATree: TSyntaxTree; const APosition: TTextPosition): Boolean;

  function Search(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
    Child: TSyntaxNode;
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Child := ANode[Index];
      if (Child.Kind = TSyntaxKind.Block) and
        ((Child.StartPos.Line < APosition.Line) or ((Child.StartPos.Line = APosition.Line) and
        (Child.StartPos.Character <= APosition.Character))) and
        ((Child.EndPos.Line > APosition.Line) or ((Child.EndPos.Line = APosition.Line) and
        (Child.EndPos.Character > APosition.Character))) then
        Exit(True);
      if Search(Child) then
        Exit(True);
    end;
    Result := False;
  end;

begin
  Result := (ATree.Root <> nil) and Search(ATree.Root);
end;

{ TOperatorPrecedenceRule }

function TOperatorPrecedenceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(OperatorPrecedenceRuleId, TRuleSeverity.Warning,
    'Vorrang von not vor in und Vergleichen übersehen');
end;

procedure TOperatorPrecedenceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Index, Operand, Op, Right, Last: Integer;
  TypeName, Name, RightText, Shown, Message: string;
  IsSet: Boolean;
begin
  if AContext.Tree = nil then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Index := 0 to High(Tokens) do
    begin
      if not Tokens[Index].IsKeyword('not') then
        Continue;
      Operand := NextCode(Tokens, Index + 1);
      if not IsPlainIdentifier(Tokens, Operand) then
        Continue;
      Op := NextCode(Tokens, Operand + 1);
      if (Op > High(Tokens)) or not (Tokens[Op].IsKeyword('in') or IsComparison(Tokens[Op])) then
        Continue;
      Right := NextCode(Tokens, Op + 1);
      Last := OperandEnd(Tokens, Right);
      if (Last < Right) or not InStatements(AContext.Tree, Tokens[Index].StartPos) then
        Continue;
      TypeName := Types.DeclaredType(Tokens[Operand].Text, Tokens[Operand].StartPos);
      if (TypeName = '') or IsLogical(TypeName) then
        Continue;
      Name := Tokens[Operand].Text;
      RightText := Trim(SourceText(AContext.Text, Tokens, Right, Last));
      IsSet := Tokens[Right].IsSymbol('[');
      if IsSet then
        Shown := '[…]'
      else
        Shown := RightText;
      Shown := Name + ' ' + Tokens[Op].Text + ' ' + Shown;
      if Tokens[Op].IsKeyword('in') then
        Message := Format('„not“ gilt nur für %s, nicht für den in-Ausdruck. Gemeint ist vermutlich not (%s).',
          [Name, Shown])
      else if TDeclaredTypes.IsInt32(TypeName) or TDeclaredTypes.IsInt64(TypeName) then
        Message := Format('„not“ kehrt die Ganzzahl %s bitweise um, nicht den Vergleich. ' +
          'Gemeint ist vermutlich not (%s).', [Name, Shown])
      else
        Message := Format('„not“ gilt nur für %s, nicht für den Vergleich. Gemeint ist vermutlich not (%s).',
          [Name, Shown]);
      AReport.Add(RangeOf(Tokens, Index, Last), Message, TRuleConfidence.High,
        [TRuleFix.Create(Format('Klammern setzen: not (%s)', [Shown]),
        [TRuleEdit.Create(RangeOf(Tokens, Operand, Last),
        '(' + SourceText(AContext.Text, Tokens, Operand, Last) + ')')])]);
    end;
  finally
    Types.Free;
  end;
end;

{ TDuplicateConditionRule }

const
  // Aufrufe, die bei jedem Aufruf etwas anderes liefern können: dann ist die Wiederholung gewollt.
  ImpureCalls: array[0..11] of string = ('Read', 'Readln', 'Next', 'MoveNext', 'Pop', 'Dequeue', 'Extract',
    'Random', 'Execute', 'ExecSQL', 'GetTickCount', 'Now');
  FloatTypes: array[0..4] of string = ('Double', 'Single', 'Extended', 'Real', 'TDateTime');
  // Aufrufe ohne Seiteneffekt; jeder andere Aufruf kann über var-Parameter oder Zustand etwas ändern.
  PureCalls: array[0..17] of string = ('SameText', 'SameStr', 'Assigned', 'Length', 'Pos', 'ContainsText',
    'ContainsStr', 'StartsText', 'StartsStr', 'EndsText', 'EndsStr', 'MatchText', 'MatchStr', 'Odd', 'Abs', 'Ord',
    'UpperCase', 'LowerCase');

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
        Lo := Middle + 1
      else
        Hi := Middle;
    end;
    Result := Lo;
  end;

  function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
      Result := Result[0];
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
        if Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
          Result := Result + LowerCase(Tokens[Index].Text) + ' '
        else
          Result := Result + Tokens[Index].Text + ' ';
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

  function Impure(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    if (ANode.Kind in [TSyntaxKind.Call, TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
      MatchText(ANode.Name, ImpureCalls) then
      Exit(True);
    if (ANode.Kind = TSyntaxKind.Call) and not MatchText(ANode.Name, PureCalls) then
      Exit(True);
    if ANode.Kind = TSyntaxKind.AnonymousMethod then
      Exit(True);
    for Index := 0 to ANode.ChildCount - 1 do
      if Impure(ANode[Index]) then
        Exit(True);
    Result := False;
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
        Current := Current[2]
      else
        Current := nil;
    end;
    // Ein Aufruf in der Kette kann den Zustand ändern, den eine spätere Bedingung liest.
    for Index := 0 to High(Conditions) do
      if Impure(Conditions[Index]) then
        Exit;
    for Index := 1 to High(Conditions) do
      for Earlier := 0 to Index - 1 do
          if Key(Conditions[Earlier]) = Key(Conditions[Index]) then
          begin
            AReport.Add(TTextRange.Create(Conditions[Index].StartPos, Conditions[Index].EndPos),
              Format('Gleiche Bedingung wie in Zeile %d; dieser Zweig wird nie erreicht.',
              [Conditions[Earlier].StartPos.Line + 1]), TRuleConfidence.High,
              [TRuleFix.Jump('Zum ersten Vorkommen springen', Conditions[Earlier].StartPos)]);
            Break;
          end;
  end;

  procedure CheckBranches(AIf: TSyntaxNode);
  begin
    if (AIf.ChildCount <> 3) or (AIf[2].Kind = TSyntaxKind.IfStatement) or (Key(AIf[1]) = '') or
      (Key(AIf[1]) <> Key(AIf[2])) then
      Exit;
    AReport.Add(TTextRange.Create(AIf[0].StartPos, AIf[0].EndPos), 'then- und else-Zweig sind gleich; ' +
      'die Bedingung hat keine Wirkung.', TRuleConfidence.High,
      [TRuleFix.Jump('Zum then-Zweig springen', AIf[1].StartPos)]);
  end;

  // Operanden einer Kette aus demselben Operator: A and B and A.
  procedure Operands(ANode: TSyntaxNode; const AOperator: string; var AList: TArray<TSyntaxNode>);
  var
    Node: TSyntaxNode;
  begin
    Node := Unwrapped(ANode);
    if (Node.Kind = TSyntaxKind.BinaryExpr) and SameText(Node.Name, AOperator) and (Node.ChildCount = 2) then
    begin
      Operands(Node[0], AOperator, AList);
      Operands(Node[1], AOperator, AList);
    end
    else
      AList := AList + [Node];
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
      Parent := Parent.Parent;
    if (Parent <> nil) and (Parent.Kind = TSyntaxKind.BinaryExpr) and SameText(Parent.Name, ANode.Name) then
      Exit;
    Op := LowerCase(ANode.Name);
    List := nil;
    Operands(ANode, Op, List);
    for Index := 0 to High(List) do
      if Impure(List[Index]) then
        Exit;
    for Index := 1 to High(List) do
      for Earlier := 0 to Index - 1 do
          if Key(List[Earlier]) = Key(List[Index]) then
          begin
            AReport.Add(TTextRange.Create(List[Index].StartPos, List[Index].EndPos),
              Format('%s steht zweimal in derselben %s-Verknüpfung; vermutlich ein Kopierfehler.',
              [Display(List[Index]), Op]), TRuleConfidence.High,
              [TRuleFix.Jump('Zum ersten Vorkommen springen', List[Earlier].StartPos)]);
            Break;
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

  // TKlasse.Instanz = TKlasse.Instanz prüft bewusst die Identität eines Singletons.
  function OnClass(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount > 0) and
      (ANode[0].Kind = TSyntaxKind.Identifier) and (Length(ANode[0].Name) > 1) and (ANode[0].Name[1] = 'T') and
      CharInSet(ANode[0].Name[2], ['A'..'Z']) then
      Exit(True);
    for Index := 0 to ANode.ChildCount - 1 do
      if OnClass(ANode[Index]) then
        Exit(True);
    Result := False;
  end;

  procedure CheckComparison(ANode: TSyntaxNode);
  var
    Outcome: string;
  begin
    if (ANode.ChildCount <> 2) or (Key(ANode[0]) <> Key(ANode[1])) or Impure(ANode) or OnClass(ANode) then
      Exit;
    // X <> X ist bei Gleitkommazahlen die Prüfung auf NaN.
    if IsFloat(ANode[0]) then
      Exit;
    if MatchStr(ANode.Name, ['=', '<=', '>=']) then
      Outcome := 'True'
    else
      Outcome := 'False';
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos), Format('%s wird mit sich selbst verglichen; ' +
      'das Ergebnis ist immer %s.', [Display(ANode[0]), Outcome]), TRuleConfidence.High);
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.IfStatement then
    begin
      // Kette nur vom ersten if aus.
      if not ((ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.IfStatement) and
        (ANode.Parent.ChildCount = 3) and (ANode.Parent[2] = ANode)) then
        CheckChain(ANode);
      CheckBranches(ANode);
    end
    else if ANode.Kind = TSyntaxKind.BinaryExpr then
    begin
      if MatchText(ANode.Name, ['and', 'or', 'xor']) then
        CheckLogical(ANode)
      else if MatchStr(ANode.Name, ['=', '<>', '<', '>', '<=', '>=']) then
        CheckComparison(ANode);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    Types.Free;
  end;
end;

procedure RegisterExpressionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOperatorPrecedenceRule.Create);
  ARegistry.Register(TDuplicateConditionRule.Create);
end;

end.
