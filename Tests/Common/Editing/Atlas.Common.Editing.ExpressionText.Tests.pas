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
  mIfNode: TSyntaxNode;
begin
  mIfNode := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if ANode.Kind = TSyntaxKind.IfStatement then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  Result := mIfNode[0];
end;

function Negated(const ACondition: string): string;
var
  mText: string;
  mTree: TSyntaxTree;
begin
  mText := Program_(ACondition);
  mTree := TPascalParser.Parse(mText);
  try
    Result := TExpressionText.Negate(mText, ConditionOf(mTree)).Text;
  finally
    mTree.Free;
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
  mRel, mAtom, mSum: TExpressionPart;
begin
  mRel := TExpressionPart.Create('X = 1', cPrecedenceRelational);
  mAtom := TExpressionPart.Create('Ready', cPrecedenceOperand);
  mSum := TExpressionPart.Create('A + B', cPrecedenceAdditive);
  Assert.AreEqual('(X = 1) and Ready', TExpressionText.Combine('and', mRel, mAtom).Text);
  Assert.AreEqual('Ready or (X = 1)', TExpressionText.Combine('or', mAtom, mRel).Text);
  Assert.AreEqual('A + B = Ready', TExpressionText.Combine('=', mSum, mAtom).Text);
  Assert.AreEqual('A + B - (A + B)', TExpressionText.Combine('-', mSum, mSum).Text);
  Assert.AreEqual(cPrecedenceMultiplicative, TExpressionText.Combine('and', mRel, mAtom).Precedence);
  Assert.AreEqual('(X = 1)', mRel.AtLeast(cPrecedenceAdditive));
  Assert.AreEqual('X = 1', mRel.AtLeast(cPrecedenceRelational));
end;

procedure TExpressionTextTests.SameIgnoresLayoutAndCase;
var
  mText: string;
  mTree: TSyntaxTree;
  mCondition: TSyntaxNode;
begin
  mText := Program_('(Edit1.Text = edit1 . text) and (A[1] = (a[ 1 ])) and (B = C)');
  mTree := TPascalParser.Parse(mText);
  try
    mCondition := ConditionOf(mTree);
    // (P1 and P2) and P3; je Klammer ein Vergleich mit zwei Seiten.
    Assert.IsTrue(TExpressionText.Same(mTree, mCondition[0][0][0][0], mCondition[0][0][0][1]));
    Assert.IsTrue(TExpressionText.Same(mTree, mCondition[0][1][0][0], mCondition[0][1][0][1]));
    Assert.IsFalse(TExpressionText.Same(mTree, mCondition[1][0][0], mCondition[1][0][1]));
  finally
    mTree.Free;
  end;
end;

procedure TExpressionTextTests.SideEffects;

  function Pure(const ACondition: string): Boolean;
  var
    mText: string;
    mTree: TSyntaxTree;
  begin
    mText := Program_(ACondition);
    mTree := TPascalParser.Parse(mText);
    try
      Result := TExpressionText.IsSideEffectFree(ConditionOf(mTree));
    finally
      mTree.Free;
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
  mText: string;
  mTree: TSyntaxTree;
  mCondition: TSyntaxNode;
begin
  mText := Program_('(A = B) and not C or F(X)');
  mTree := TPascalParser.Parse(mText);
  try
    // ((A = B) and not C) or F(X)
    mCondition := ConditionOf(mTree);
    Assert.AreEqual(cPrecedenceIfExpr, TExpressionText.ContextPrecedence(mCondition));
    Assert.AreEqual(cPrecedenceAdditive, TExpressionText.ContextPrecedence(mCondition[0]));
    Assert.AreEqual(cPrecedenceMultiplicative, TExpressionText.ContextPrecedence(mCondition[0][0]));
    Assert.AreEqual(cPrecedenceMultiplicative + 1, TExpressionText.ContextPrecedence(mCondition[0][1]));
    Assert.AreEqual(cPrecedenceUnary, TExpressionText.ContextPrecedence(mCondition[0][1][0]));
    // Empfänger eines Aufrufs braucht einen Operanden, ein Argument nichts.
    Assert.AreEqual(cPrecedenceOperand, TExpressionText.ContextPrecedence(mCondition[1][0]));
    Assert.AreEqual(cPrecedenceIfExpr, TExpressionText.ContextPrecedence(mCondition[1][1]));
  finally
    mTree.Free;
  end;
  // Bedingungsausdruck: Bedingung und Wert vor else brauchen Klammern, der Wert nach else nicht.
  mText := Program_('(if A then B else C)');
  mTree := TPascalParser.Parse(mText);
  try
    mCondition := ConditionOf(mTree);
    while mCondition.Kind <> TSyntaxKind.IfExpr do
    begin
      mCondition := mCondition[0];
    end;
    Assert.AreEqual(cPrecedenceIfExpr + 1, TExpressionText.ContextPrecedence(mCondition[0]));
    Assert.AreEqual(cPrecedenceIfExpr + 1, TExpressionText.ContextPrecedence(mCondition[1]));
    Assert.AreEqual(cPrecedenceIfExpr, TExpressionText.ContextPrecedence(mCondition[2]));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TExpressionTextTests);

end.
