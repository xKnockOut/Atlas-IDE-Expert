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

procedure RegisterExpressionRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Rules.Options;

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
    Name := Trim(Copy(Name, 1, Pos('[', Name) - 1));
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
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
        Inc(Depth)
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(Depth);
        if Depth = 0 then
          Exit;
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
      if Token(Position).IsSymbol('(') or Token(Position).IsSymbol('[') then
        Inc(Depth)
      else if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
        Dec(Depth)
      else if (Depth = 0) and Token(Position).IsSymbol(',') then
        Result := Result + [Position + 1];
  end;

  // Ist das Argument ab AFirst bis vor ANext sicher ein String? Deklarierter Typ, Literal oder .Text/.Caption.
  function IsStringArgument(AFirst, ANext: Integer): Boolean;
  var
    Last: Integer;
  begin
    Last := ANext - 1;
    if Last < AFirst then
      Exit(False);
    if (AFirst = Last) and (Token(AFirst).Kind = TPascalTokenKind.StringLiteral) then
      Exit(True);
    if (Token(Last).Kind = TPascalTokenKind.Identifier) and IsSym(Last - 1, '.') and
      MatchText(Token(Last).Text, ['Text', 'Caption']) then
      Exit(True);
    if IsName(AFirst, 'Self') and IsSym(AFirst + 1, '.') then
      Inc(AFirst, 2);
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
      Exit;
    Close := Closing(APosition + 1);
    if Close < 0 then
      Exit;
    Args := Arguments(APosition + 1, Close);
    Args := Args + [Close + 1];
    Name := Token(APosition).Text;
    if SameText(Name, 'Insert') then
      Index := 2
    else
      Index := 1;
    if Length(Args) < Index + 2 then
      Exit;
    // Das Argument muss genau "0" sein; der String steht bei Insert an zweiter, sonst an erster Stelle.
    if (Args[Index + 1] - Args[Index] <> 2) or (Token(Args[Index]).Text <> '0') or
      not IsStringArgument(Args[Index - 1], Args[Index] - 1) then
      Exit;
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

  // Vergleich hinter AClose: Operator, optional "-", Zahl. Liefert die Positionen und den Text.
  function Comparison(AAfter: Integer; out AOperator, ALast: Integer; out AText: string): Boolean;
  begin
    Result := False;
    if (AAfter > High(Code)) or not (Token(AAfter).IsSymbol('>') or Token(AAfter).IsSymbol('>=') or
      Token(AAfter).IsSymbol('<') or Token(AAfter).IsSymbol('<=') or Token(AAfter).IsSymbol('=') or
      Token(AAfter).IsSymbol('<>')) then
      Exit;
    AOperator := AAfter;
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
    end
    else
      Exit;
    // "Pos(…) > 1 + X" vergleicht mit einem anderen Wert.
    if IsSym(ALast + 1, '+') or IsSym(ALast + 1, '-') or IsSym(ALast + 1, '*') or
      ((ALast + 1 <= High(Code)) and (Token(ALast + 1).IsKeyword('div') or Token(ALast + 1).IsKeyword('mod'))) then
      Exit;
    Result := True;
  end;

  function TextOf(AFirst, ALast: Integer): string;
  begin
    Result := SourceText(AContext.Text, Tokens, Code[AFirst], Code[ALast]);
  end;

  // Steht vor APosition ein Rechenoperator ("X + Pos(…) > 0")? Dann gilt der Vergleich der Summe.
  function InArithmetic(APosition: Integer): Boolean;
  begin
    if IsSym(APosition - 1, '.') then
      Dec(APosition, 2);
    Result := IsSym(APosition - 1, '+') or IsSym(APosition - 1, '-') or IsSym(APosition - 1, '*') or
      ((APosition > 0) and (Token(APosition - 1).IsKeyword('div') or Token(APosition - 1).IsKeyword('mod')));
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
      Exit;
    Close := Closing(APosition + 1);
    // "Pos(…) > -1", aber nicht "Pos(…) - 1 > 0" oder "X.Pos".
    if (Close < 0) or not Comparison(Close + 1, Operator, Last, Compare) then
      Exit;
    Name := Token(APosition).Text;
    if (Compare = '>-1') or (Compare = '>=0') or (Compare = '<>-1') then
      ReportComparison(Operator, Last, Format('%s liefert 0 bei keinem Treffer; der Vergleich %s ist immer wahr.',
        [Name, TextOf(Operator, Last)]), '> 0', TRuleConfidence.High)
    else if (Compare = '=-1') or (Compare = '<0') or (Compare = '<=-1') then
      ReportComparison(Operator, Last, Format('%s liefert 0 bei keinem Treffer; der Vergleich %s ist nie wahr.',
        [Name, TextOf(Operator, Last)]), '= 0', TRuleConfidence.High);
  end;

  // S.IndexOf(…) > 0 bzw. >= 1 übersieht den Treffer am Anfang; < 1 bzw. <= 0 zählt ihn als "nicht gefunden".
  procedure CheckIndexOf(APosition: Integer);
  var
    Close, Operator, Last: Integer;
    Compare, Name: string;
  begin
    if not IsSym(APosition - 1, '.') or not IsSym(APosition + 1, '(') then
      Exit;
    Close := Closing(APosition + 1);
    if (Close < 0) or not Comparison(Close + 1, Operator, Last, Compare) then
      Exit;
    Name := Token(APosition).Text;
    if (Compare = '>0') or (Compare = '>=1') then
      ReportComparison(Operator, Last, Format('%s zählt ab 0 und liefert -1 bei keinem Treffer; der Vergleich %s ' +
        'übersieht den Treffer am Anfang.', [Name, TextOf(Operator, Last)]), '>= 0', TRuleConfidence.Medium)
    else if (Compare = '<1') or (Compare = '<=0') then
      ReportComparison(Operator, Last, Format('%s zählt ab 0 und liefert -1 bei keinem Treffer; der Vergleich %s ' +
        'zählt den Treffer am Anfang als nicht gefunden.', [Name, TextOf(Operator, Last)]), '< 0',
        TRuleConfidence.Medium);
  end;

var
  Index, Position: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
    if not IsTrivia(Tokens[Index]) then
      Code := Code + [Index];
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Position := 0 to High(Code) do
    begin
      if Token(Position).Kind <> TPascalTokenKind.Identifier then
        Continue;
      if MatchText(Token(Position).Text, ['Copy', 'Delete', 'Insert']) then
        CheckStartIndex(Position)
      else if MatchText(Token(Position).Text, ['Pos', 'PosEx', 'AnsiPos']) then
        CheckPos(Position)
      // LastIndexOf(…) > 0 heißt meist bewusst "Trenner nicht am Anfang" (Name.LastIndexOf('.') > 0).
      else if MatchText(Token(Position).Text, ['IndexOf', 'IndexOfAny']) then
        CheckIndexOf(Position);
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

  // Erstes Token der Kette (A, A.B, A(…), A[…]), die bei ALast endet; -1 bei anderen Ausdrücken.
  function ChainStart(ALast: Integer): Integer;
  var
    Position, Depth: Integer;
  begin
    Result := -1;
    Position := ALast;
    while Position >= 0 do
    begin
      if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
      begin
        Depth := 0;
        repeat
          if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
            Inc(Depth)
          else if Token(Position).IsSymbol('(') or Token(Position).IsSymbol('[') then
            Dec(Depth);
          Dec(Position);
        until (Depth = 0) or (Position < 0);
        if Position < 0 then
          Exit;
      end;
      if not IsWord(Position) then
        Exit;
      if not IsSym(Position - 1, '.') then
        Exit(Position);
      Dec(Position, 2);
    end;
  end;

  // Letztes Token der Kette ab AFirst; -1, wenn dort keine beginnt.
  function ChainEnd(AFirst: Integer): Integer;
  var
    Position, Depth: Integer;
  begin
    Result := -1;
    Position := AFirst;
    while IsWord(Position) do
    begin
      Result := Position;
      Inc(Position);
      while IsSym(Position, '(') or IsSym(Position, '[') do
      begin
        Depth := 0;
        repeat
          if Token(Position).IsSymbol('(') or Token(Position).IsSymbol('[') then
            Inc(Depth)
          else if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
            Dec(Depth);
          Inc(Position);
        until (Depth = 0) or (Position > High(Code));
        if Depth <> 0 then
          Exit(-1);
        Result := Position - 1;
      end;
      if not IsSym(Position, '.') then
        Exit;
      Inc(Position);
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
      Exit;
    ABase := TextOf(AFirst, ALast - 2);
    // FieldByName('…'), FindField, Fields[…], ParamByName, Params[…] in der Kette.
    for Position := AFirst to ALast - 2 do
      if IsName(Position, 'FieldByName') or IsName(Position, 'FindField') or IsName(Position, 'ParamByName') or
        IsName(Position, 'FindParam') or ((IsName(Position, 'Fields') or IsName(Position, 'Params')) and
        IsSym(Position + 1, '[')) then
        Exit(True);
    // Feld mit deklariertem Typ TStringField, TIntegerField, TParam …
    Result := (ALast - 2 = AFirst) and IsDataType(Types.DeclaredType(Token(AFirst).Text, Token(AFirst).StartPos));
  end;

  procedure ReportAt(AFirst, ALast, AOperator, AExprFirst, AExprLast: Integer);
  var
    Base, Replacement, Message, Prefix: string;
  begin
    if Token(AOperator).IsSymbol('<>') then
      Prefix := 'not '
    else
      Prefix := '';
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
      AReport.Add(TTextRange.Create(Token(AFirst).StartPos, Token(ALast).EndPos), Message)
    else
      AReport.Add(TTextRange.Create(Token(AFirst).StartPos, Token(ALast).EndPos), Message,
        [TRuleFix.Create(Format('Durch "%s" ersetzen', [Replacement]),
        [TRuleEdit.Create(TTextRange.Create(Token(AFirst).StartPos, Token(ALast).EndPos), Replacement)])]);
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
        ReportAt(First, APosition, APosition - 1, First, APosition - 2);
    end
    // Null = X bzw. Null <> X
    else if (IsSym(APosition + 1, '=') or IsSym(APosition + 1, '<>')) and OpensExpression(APosition - 1) then
    begin
      Last := ChainEnd(APosition + 2);
      if (Last >= 0) and ClosesExpression(Last + 1) then
        ReportAt(APosition, Last, APosition + 1, APosition + 2, Last);
    end;
  end;

var
  Index, Position: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Null') then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
    if not IsTrivia(Tokens[Index]) then
      Code := Code + [Index];
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Position := 0 to High(Code) do
      // Null als Wert: nicht Teil einer Kette (X.Null) und kein Aufruf.
      if IsName(Position, 'Null') and not IsSym(Position - 1, '.') and not IsSym(Position + 1, '.') and
        not IsSym(Position + 1, '(') then
        CheckAt(Position);
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
var
  Index, Value: Integer;
  Digits: string;
begin
  Result := 0;
  Index := 1;
  while Index <= Length(ALiteral) do
    if ALiteral[Index] = '''' then
    begin
      Inc(Index);
      while Index <= Length(ALiteral) do
      begin
        if ALiteral[Index] = '''' then
        begin
          // '' im Literal ist ein Apostroph, sonst endet der Abschnitt.
          if (Index < Length(ALiteral)) and (ALiteral[Index + 1] = '''') then
            Inc(Index)
          else
            Break;
        end;
        Inc(Result);
        Inc(Index);
      end;
      Inc(Index);
    end
    else if ALiteral[Index] = '#' then
    begin
      Inc(Index);
      Digits := '';
      while (Index <= Length(ALiteral)) and CharInSet(ALiteral[Index], ['$', '0'..'9', 'A'..'F', 'a'..'f', '_']) do
      begin
        if ALiteral[Index] <> '_' then
          Digits := Digits + ALiteral[Index];
        Inc(Index);
      end;
      if not TryStrToInt(Digits, Value) then
        Exit(-1);
      Inc(Result);
    end
    else
      Exit(-1);
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
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
        Inc(Depth)
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(Depth);
        if Depth = 0 then
          Exit;
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
      if Token(Position).IsSymbol('(') or Token(Position).IsSymbol('[') then
        Inc(Depth)
      else if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
        Dec(Depth)
      else if (Depth = 0) and Token(Position).IsSymbol(',') then
        Result := Result + [Position + 1];
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
      Exit(-1);
    Text := '';
    for Position := AFirst to ALast do
    begin
      if not (Token(Position).Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]) or
        (Pos(#10, Token(Position).Text) > 0) then
        Exit(-1);
      Text := Text + Token(Position).Text;
    end;
    Result := LiteralLength(Text);
  end;

  // Ist das Argument AFirst..ALast sicher ein String und kein Zeichen? Deklarierter String-Typ, .Text/.Caption,
  // Aufruf einer String-Funktion der RTL oder Verkettung mit einem String-Teil.
  function IsStringArgument(AFirst, ALast: Integer): Boolean;
  var
    Position, Depth: Integer;
  begin
    if ALast < AFirst then
      Exit(False);
    Depth := 0;
    for Position := AFirst to ALast do
      if Token(Position).IsSymbol('(') or Token(Position).IsSymbol('[') then
        Inc(Depth)
      else if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
        Dec(Depth)
      else if (Depth = 0) and Token(Position).IsSymbol('+') then
        // Zeichen + Zeichen ist schon ein String, Zahl + Zahl nicht: ein Teil muss sicher String sein.
        Exit(IsStringArgument(AFirst, Position - 1) or IsStringArgument(Position + 1, ALast) or
          (Literal(AFirst, Position - 1) >= 2) or (Literal(Position + 1, ALast) >= 2));
    if (Token(ALast).Kind = TPascalTokenKind.Identifier) and IsSym(ALast - 1, '.') and
      MatchText(Token(ALast).Text, ['Text', 'Caption']) then
      Exit(True);
    if (Token(AFirst).Kind = TPascalTokenKind.Identifier) and IsSym(AFirst + 1, '(') and
      not IsSym(AFirst - 1, '.') and MatchText(Token(AFirst).Text, ['Trim', 'TrimLeft', 'TrimRight', 'UpperCase',
      'LowerCase', 'AnsiUpperCase', 'AnsiLowerCase', 'IntToStr', 'Format', 'QuotedStr', 'StringReplace',
      'ExtractFileName', 'ExtractFilePath', 'ExtractFileExt', 'ChangeFileExt', 'IncludeTrailingPathDelimiter',
      'ExcludeTrailingPathDelimiter', 'LeftStr', 'RightStr', 'MidStr', 'ReverseString', 'DupeString']) then
      Exit(Closing(AFirst + 1) = ALast);
    if IsName(AFirst, 'Self') and IsSym(AFirst + 1, '.') then
      Inc(AFirst, 2);
    Result := (AFirst = ALast) and (Token(AFirst).Kind = TPascalTokenKind.Identifier) and
      TStringIndexBaseRule.IsStringType(Types.DeclaredType(Token(AFirst).Text, Token(AFirst).StartPos));
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
    if not IsSym(APosition + 1, '(') then
      Exit;
    // Nur die RTL-Routine: ohne Punkt davor oder mit System. bzw. StrUtils. (auch System.StrUtils.).
    if IsSym(APosition - 1, '.') and not IsName(APosition - 2, 'System') and
      not IsName(APosition - 2, 'StrUtils') then
      Exit;
    Close := Closing(APosition + 1);
    if Close < 0 then
      Exit;
    Args := Arguments(APosition + 1, Close);
    if Length(Args) < 3 then
      Exit;
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
      Exit;
    Name := Token(APosition).Text;
    if ATextFirst then
      Message := '%s(Text, Teil): vermutlich vertauscht, gesucht wird %s in %s.'
    else
      Message := '%s(Teil, Text): vermutlich vertauscht, gesucht wird %s in %s.';
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
    Exit;
  MaxLength := TRuleOptions.Int(AContext.Options, 'maxLiteralLength', 3);
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
    if not IsTrivia(Tokens[Index]) then
      Code := Code + [Index];
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for Position := 0 to High(Code) do
    begin
      if Token(Position).Kind <> TPascalTokenKind.Identifier then
        Continue;
      if MatchText(Token(Position).Text, ['Pos', 'PosEx', 'AnsiPos', 'StartsText', 'StartsStr', 'EndsText',
        'EndsStr', 'AnsiStartsText', 'AnsiStartsStr', 'AnsiEndsText', 'AnsiEndsStr']) then
        CheckCall(Position, False)
      else if MatchText(Token(Position).Text, ['ContainsText', 'ContainsStr', 'AnsiContainsText',
        'AnsiContainsStr']) then
        CheckCall(Position, True);
    end;
  finally
    Types.Free;
  end;
end;

procedure RegisterExpressionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOperatorPrecedenceRule.Create);
  ARegistry.Register(TDuplicateConditionRule.Create);
  ARegistry.Register(TStringIndexBaseRule.Create);
  ARegistry.Register(TNullCompareRule.Create);
  ARegistry.Register(TPosArgumentsSwappedRule.Create);
end;

end.
