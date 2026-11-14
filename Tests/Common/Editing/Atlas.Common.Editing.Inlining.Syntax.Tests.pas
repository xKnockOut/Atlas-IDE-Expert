unit Atlas.Common.Editing.Inlining.Syntax.Tests;

// Tests für die gemeinsamen Hilfen von „Einbetten“ (#103, Teil A): Rümpfe nach
// Namen in Quelltextreihenfolge, Aufruf an der Einfügemarke mit Empfänger und
// Argumenten, Verneinen von Bedingungen und Anweisungen untereinander.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInlineSyntaxTests = class
  public
    [Test]
    procedure FindRoutinesKeepsSourceOrder;
    [Test]
    procedure CallAtFindsReceiverAndArguments;
    [Test]
    procedure CallAtSkipsQualifierAndTarget;
    [Test]
    procedure NegatedAddsParenthesesOnlyWhenNeeded;
    [Test]
    procedure JoinStatementsIndentsLines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.Inlining.Types,
  Atlas.Common.Editing.Inlining.Syntax;

const
  cRoutines =
    'unit U;'#10 +
    'interface'#10 +
    'procedure Foo;'#10 +
    'implementation'#10 +
    'procedure TB.Foo;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Foo;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TA.Foo;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure Bar;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';
  cCall =
    'unit U;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'procedure P;'#10 +
    'begin'#10 +
    '  Obj.Run(1, X);'#10 +
    '  Obj.Value := 2;'#10 +
    'end;'#10 +
    'end.';

procedure TInlineSyntaxTests.FindRoutinesKeepsSourceOrder;
var
  mTree: TSyntaxTree;
  mRoutines: TArray<TSyntaxNode>;
begin
  mTree := TPascalParser.Parse(cRoutines);
  try
    mRoutines := TInlineSyntax.FindRoutines(mTree, 'Foo');
    Assert.AreEqual(3, Integer(Length(mRoutines)));
    Assert.AreEqual('TB.Foo', mRoutines[0].Name);
    Assert.AreEqual('Foo', mRoutines[1].Name);
    Assert.AreEqual('TA.Foo', mRoutines[2].Name);
    mRoutines := TInlineSyntax.FindRoutines(mTree, 'TA.Foo');
    Assert.AreEqual(1, Integer(Length(mRoutines)));
    Assert.AreEqual(0, Integer(Length(TInlineSyntax.FindRoutines(mTree, 'Baz'))));
  finally
    mTree.Free;
  end;
end;

procedure TInlineSyntaxTests.CallAtFindsReceiverAndArguments;
var
  mTree: TSyntaxTree;
  mCall: TInlineCall;
begin
  mTree := TPascalParser.Parse(cCall);
  try
    // Zeile 5 (ab 0), Spalte 7: das "u" in Run.
    Assert.IsTrue(TInlineSyntax.CallAt(mTree, cCall, TTextPosition.Create(5, 7), mCall));
    Assert.AreEqual('Run', mCall.Name);
    Assert.AreEqual(2, Integer(Length(mCall.Arguments)));
    Assert.IsNotNull(mCall.Receiver);
    Assert.AreEqual('Obj', mCall.Receiver.Name);
    Assert.IsNotNull(mCall.Statement);
    Assert.AreEqual(5, mCall.NamePos.Line);
    Assert.AreEqual(6, mCall.NamePos.Character);
  finally
    mTree.Free;
  end;
end;

procedure TInlineSyntaxTests.CallAtSkipsQualifierAndTarget;
var
  mTree: TSyntaxTree;
  mCall: TInlineCall;
begin
  mTree := TPascalParser.Parse(cCall);
  try
    // Obj vor .Run ist Qualifizierer, kein Aufruf.
    Assert.IsFalse(TInlineSyntax.CallAt(mTree, cCall, TTextPosition.Create(5, 3), mCall));
    // Außerhalb einer Routine.
    Assert.IsFalse(TInlineSyntax.CallAt(mTree, cCall, TTextPosition.Create(0, 1), mCall));
  finally
    mTree.Free;
  end;
end;

procedure TInlineSyntaxTests.NegatedAddsParenthesesOnlyWhenNeeded;
var
  mTree: TSyntaxTree;
  mCall: TInlineCall;
begin
  mTree := TPascalParser.Parse(cCall);
  try
    Assert.IsTrue(TInlineSyntax.CallAt(mTree, cCall, TTextPosition.Create(5, 7), mCall));
    // Aufruf und Name: ohne Klammern; Zahl als Literal ebenso.
    Assert.AreEqual('not Obj.Run(1, X)', TInlineSyntax.Negated('Obj.Run(1, X)', mCall.Node));
    Assert.AreEqual('not X', TInlineSyntax.Negated('X', mCall.Arguments[1]));
    Assert.AreEqual('not 1', TInlineSyntax.Negated('1', mCall.Arguments[0]));
  finally
    mTree.Free;
  end;
end;

procedure TInlineSyntaxTests.JoinStatementsIndentsLines;
begin
  Assert.AreEqual('  A := 1;'#10'  B := 2', TInlineSyntax.JoinStatements(TArray<string>.Create('A := 1',
    'B := 2'), '  ', #10, True));
  Assert.AreEqual('A := 1;'#10'  B := 2', TInlineSyntax.JoinStatements(TArray<string>.Create('A := 1',
    'B := 2'), '  ', #10, False));
end;

initialization
  TDUnitX.RegisterTestFixture(TInlineSyntaxTests);

end.
