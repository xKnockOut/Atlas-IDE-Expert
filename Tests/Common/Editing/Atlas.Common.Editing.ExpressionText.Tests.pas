unit Atlas.Common.Editing.ExpressionText.Tests;

// Tests für die Ausdrucksbausteine der Umformungen (Kette L): Vorrang,
// Klammern nach Vorrang, lesbares Verneinen, Vergleich zweier Ausdrücke und
// Seiteneffekte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TExpressionTextTests = class
  public
    [Test]
    procedure NegatesComparisons;
    [Test]
    procedure NegatesWithDeMorgan;
    [Test]
    procedure NegatesNotInAndLiterals;
    [Test]
    procedure CombineSetsParenthesesByPrecedence;
    [Test]
    procedure SameIgnoresLayoutAndCase;
    [Test]
    procedure SideEffects;
    [Test]
    procedure ContextPrecedenceFollowsParent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ExpressionText;

/// <summary>Programm, dessen einzige Anweisung "if ACondition then ;" ist.</summary>
function Program_(const ACondition: string): string;
begin
  Result := 'program P;'#10'begin'#10'  if ' + ACondition + ' then ;'#10'end.';
end;

function ConditionOf(ATree: TSyntaxTree): TSyntaxNode;
var
  IfNode: TSyntaxNode;
begin
  IfNode := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind = TSyntaxKind.IfStatement then
        Result := TSyntaxSearchStep.Found;
    end);
  Result := IfNode[0];
end;

function Negated(const ACondition: string): string;
var
  Text: string;
  Tree: TSyntaxTree;
begin
  Text := Program_(ACondition);
  Tree := TPascalParser.Parse(Text);
  try
    Result := TExpressionText.Negate(Text, ConditionOf(Tree)).Text;
  finally
    Tree.Free;
  end;
end;

procedure TExpressionTextTests.NegatesComparisons;
begin
  Assert.AreEqual('A <> B', Negated('A = B'));
  Assert.AreEqual('A = B', Negated('A <> B'));
  Assert.AreEqual('A >= B', Negated('A < B'));
  Assert.AreEqual('A < B', Negated('A >= B'));
  Assert.AreEqual('A <= B', Negated('A > B'));
  Assert.AreEqual('A > B', Negated('A <= B'));
  Assert.AreEqual('A + 1 <> B * 2', Negated('(A + 1 = B * 2)'));
  // Kein not A = B aus not (A = B).
  Assert.AreEqual('A = B', Negated('not not (A <> B)'));
end;

procedure TExpressionTextTests.NegatesWithDeMorgan;
begin
  Assert.AreEqual('not A or not B', Negated('A and B'));
  Assert.AreEqual('not A and not B', Negated('A or B'));
  Assert.AreEqual('(X <> 1) or (Y >= 2)', Negated('(X = 1) and (Y < 2)'));
  Assert.AreEqual('not A and ((X <> 1) or not Ready)', Negated('A or (X = 1) and Ready'));
  // Reihenfolge bleibt (Kurzschluss): Assigned vor dem Zugriff.
  Assert.AreEqual('not Assigned(P) or (P.Count = 0)', Negated('Assigned(P) and (P.Count <> 0)'));
end;

procedure TExpressionTextTests.NegatesNotInAndLiterals;
begin
  Assert.AreEqual('A', Negated('not A'));
  Assert.AreEqual('A and B', Negated('not (A and B)'));
  Assert.AreEqual('not (C in [1, 2])', Negated('C in [1, 2]'));
  Assert.AreEqual('not (O is TButton)', Negated('O is TButton'));
  Assert.AreEqual('False', Negated('True'));
  Assert.AreEqual('True', Negated('False'));
  Assert.AreEqual('not Ready', Negated('Ready'));
  Assert.AreEqual('not IsEmpty(S)', Negated('IsEmpty(S)'));
  Assert.AreEqual('not (A xor B)', Negated('A xor B'));
end;

procedure TExpressionTextTests.CombineSetsParenthesesByPrecedence;
var
  Rel, Atom, Sum: TExpressionPart;
begin
  Rel := TExpressionPart.Create('X = 1', PrecedenceRelational);
  Atom := TExpressionPart.Create('Ready', PrecedenceOperand);
  Sum := TExpressionPart.Create('A + B', PrecedenceAdditive);
  Assert.AreEqual('(X = 1) and Ready', TExpressionText.Combine('and', Rel, Atom).Text);
  Assert.AreEqual('Ready or (X = 1)', TExpressionText.Combine('or', Atom, Rel).Text);
  Assert.AreEqual('A + B = Ready', TExpressionText.Combine('=', Sum, Atom).Text);
  Assert.AreEqual('A + B - (A + B)', TExpressionText.Combine('-', Sum, Sum).Text);
  Assert.AreEqual(PrecedenceMultiplicative, TExpressionText.Combine('and', Rel, Atom).Precedence);
  Assert.AreEqual('(X = 1)', Rel.AtLeast(PrecedenceAdditive));
  Assert.AreEqual('X = 1', Rel.AtLeast(PrecedenceRelational));
end;

procedure TExpressionTextTests.SameIgnoresLayoutAndCase;
var
  Text: string;
  Tree: TSyntaxTree;
  Condition: TSyntaxNode;
begin
  Text := Program_('(Edit1.Text = edit1 . text) and (A[1] = (a[ 1 ])) and (B = C)');
  Tree := TPascalParser.Parse(Text);
  try
    Condition := ConditionOf(Tree);
    // (P1 and P2) and P3; je Klammer ein Vergleich mit zwei Seiten.
    Assert.IsTrue(TExpressionText.Same(Tree, Condition[0][0][0][0], Condition[0][0][0][1]));
    Assert.IsTrue(TExpressionText.Same(Tree, Condition[0][1][0][0], Condition[0][1][0][1]));
    Assert.IsFalse(TExpressionText.Same(Tree, Condition[1][0][0], Condition[1][0][1]));
  finally
    Tree.Free;
  end;
end;

procedure TExpressionTextTests.SideEffects;

  function Pure(const ACondition: string): Boolean;
  var
    Text: string;
    Tree: TSyntaxTree;
  begin
    Text := Program_(ACondition);
    Tree := TPascalParser.Parse(Text);
    try
      Result := TExpressionText.IsSideEffectFree(ConditionOf(Tree));
    finally
      Tree.Free;
    end;
  end;

begin
  Assert.IsTrue(Pure('A.B[I] = 1'));
  Assert.IsTrue(Pure('Length(S) > Ord(C)'));
  Assert.IsFalse(Pure('Next() = 1'));
  Assert.IsFalse(Pure('List.Count(X) = 1'));
end;

procedure TExpressionTextTests.ContextPrecedenceFollowsParent;
var
  Text: string;
  Tree: TSyntaxTree;
  Condition: TSyntaxNode;
begin
  Text := Program_('(A = B) and not C or F(X)');
  Tree := TPascalParser.Parse(Text);
  try
    // ((A = B) and not C) or F(X)
    Condition := ConditionOf(Tree);
    Assert.AreEqual(PrecedenceIfExpr, TExpressionText.ContextPrecedence(Condition));
    Assert.AreEqual(PrecedenceAdditive, TExpressionText.ContextPrecedence(Condition[0]));
    Assert.AreEqual(PrecedenceMultiplicative, TExpressionText.ContextPrecedence(Condition[0][0]));
    Assert.AreEqual(PrecedenceMultiplicative + 1, TExpressionText.ContextPrecedence(Condition[0][1]));
    Assert.AreEqual(PrecedenceUnary, TExpressionText.ContextPrecedence(Condition[0][1][0]));
    // Empfänger eines Aufrufs braucht einen Operanden, ein Argument nichts.
    Assert.AreEqual(PrecedenceOperand, TExpressionText.ContextPrecedence(Condition[1][0]));
    Assert.AreEqual(PrecedenceIfExpr, TExpressionText.ContextPrecedence(Condition[1][1]));
  finally
    Tree.Free;
  end;
  // Bedingungsausdruck: Bedingung und Wert vor else brauchen Klammern, der Wert nach else nicht.
  Text := Program_('(if A then B else C)');
  Tree := TPascalParser.Parse(Text);
  try
    Condition := ConditionOf(Tree);
    while Condition.Kind <> TSyntaxKind.IfExpr do
      Condition := Condition[0];
    Assert.AreEqual(PrecedenceIfExpr + 1, TExpressionText.ContextPrecedence(Condition[0]));
    Assert.AreEqual(PrecedenceIfExpr + 1, TExpressionText.ContextPrecedence(Condition[1]));
    Assert.AreEqual(PrecedenceIfExpr, TExpressionText.ContextPrecedence(Condition[2]));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TExpressionTextTests);

end.
