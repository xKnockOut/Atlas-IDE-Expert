unit Atlas.Common.Rules.Builtin.Expressions;

// Regeln für Ausdrücke, die anders gebunden werden als gemeint (#909):
//   operator-precedence   not bindet stärker als in und Vergleiche (#911):
//                         "not X in Menge" ist "(not X) in Menge", "not A = B"
//                         ist "(not A) = B", bei Ganzzahlen bitweise.
// Gemeldet wird nur, wenn der Typ des Operanden in der Datei deklariert und
// kein Boolean ist (Atlas.Common.Pascal.DeclaredTypes); unbekannte Typen und
// Variants bleiben stumm.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  OperatorPrecedenceRuleId = 'operator-precedence';

type
  TOperatorPrecedenceRule = class(TInterfacedObject, IRule)
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

procedure RegisterExpressionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOperatorPrecedenceRule.Create);
end;

end.
