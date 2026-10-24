unit Atlas.Common.Editing.StatementText.Tests;

// Tests für die Anweisungsbausteine der Umformungen (Kette L): Anweisungen
// eines Zweigs, Text mit Kommentaren, neu eingerückt, Zweige mit und ohne
// begin … end.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStatementTextTests = class
  public
    [Test]
    procedure StatementsOfBlockAndSingle;
    [Test]
    procedure TextKeepsCommentsAndReindents;
    [Test]
    procedure BranchWithOneAndManyStatements;
    [Test]
    procedure FinishPutsSuffixBeforeComment;
    [Test]
    procedure HasCommentFindsComments;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.StatementText;

function MainBlock(ATree: TSyntaxTree): TSyntaxNode;
begin
  Result := ATree.Root.FindChild(TSyntaxKind.Block);
end;

procedure TStatementTextTests.StatementsOfBlockAndSingle;
var
  Text: string;
  Tree: TSyntaxTree;
  Block: TSyntaxNode;
begin
  Text := 'program P;'#10'begin'#10'  A := 1;'#10'  ;'#10'  B;'#10'  if X then C;'#10'end.';
  Tree := TPascalParser.Parse(Text);
  try
    Block := MainBlock(Tree);
    Assert.AreEqual(3, Integer(Length(TStatementText.Statements(Block))));
    Assert.AreEqual(1, Integer(Length(TStatementText.Statements(Block[0]))));
    Assert.AreEqual(0, Integer(Length(TStatementText.Statements(nil))));
  finally
    Tree.Free;
  end;
end;

procedure TStatementTextTests.TextKeepsCommentsAndReindents;
var
  Text: string;
  Tree: TSyntaxTree;
  Statements: TArray<TSyntaxNode>;
begin
  Text := 'program P;'#10'begin'#10'  // vorher'#10'  A := 1; // dahinter'#10'  if X then'#10'  begin'#10 +
    '    B;'#10'  end;'#10'  { am Ende }'#10'end.';
  Tree := TPascalParser.Parse(Text);
  try
    Statements := TStatementText.Statements(MainBlock(Tree));
    Assert.AreEqual('      // vorher'#10'      A := 1'#0'// dahinter', TStatementText.Text(Text, Tree, Statements[0],
      False, '      ', #10));
    Assert.AreEqual('    if X then'#10'    begin'#10'      B;'#10'    end'#0#10'    { am Ende }',
      TStatementText.Text(Text, Tree, Statements[1], True, '    ', #13#10).Replace(#13#10, #10));
    Assert.AreEqual('  // vorher'#10'  A := 1; // dahinter'#10'  if X then'#10'  begin'#10'    B;'#10'  end;'#10 +
      '  { am Ende }', TStatementText.List(Text, Tree, Statements, '  ', #10));
  finally
    Tree.Free;
  end;
end;

procedure TStatementTextTests.BranchWithOneAndManyStatements;
var
  Text: string;
  Tree: TSyntaxTree;
  Statements: TArray<TSyntaxNode>;
  Layout: TStatementLayout;
begin
  Text := 'program P;'#10'begin'#10'  A := 1;'#10'  B;'#10'end.';
  Tree := TPascalParser.Parse(Text);
  try
    Statements := TStatementText.Statements(MainBlock(Tree));
    Layout := TStatementLayout.Create('  ', '  ', #10);
    Assert.AreEqual(#10'    A := 1', TStatementText.Branch(Text, Tree, [Statements[0]], Layout, False));
    Assert.AreEqual(#10'  begin'#10'    A := 1;'#10'    B;'#10'  end', TStatementText.Branch(Text, Tree, Statements,
      Layout, False));
    Assert.AreEqual('', TStatementText.Branch(Text, Tree, nil, Layout, False));
    Assert.AreEqual(#10'  begin'#10'  end', TStatementText.Branch(Text, Tree, nil, Layout, True));
    Assert.AreEqual('    ', Layout.Deeper.Indent);
  finally
    Tree.Free;
  end;
end;

procedure TStatementTextTests.FinishPutsSuffixBeforeComment;
begin
  Assert.AreEqual('A := 1;', TStatementText.Finish('A := 1', ';'));
  Assert.AreEqual('A := 1; // eins', TStatementText.Finish('A := 1'#0'// eins', ';'));
  Assert.AreEqual('A := 1;'#10'  { zwei }', TStatementText.Finish('A := 1'#0#10'  { zwei }', ';'));
end;

procedure TStatementTextTests.HasCommentFindsComments;
var
  Text: string;
  Tree: TSyntaxTree;
begin
  Text := 'program P;'#10'begin'#10'  A := {x} 1;'#10'end.';
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsTrue(TStatementText.HasComment(Tree, 0, Length(Text)));
    Assert.IsFalse(TStatementText.HasComment(Tree, 0, Pos('{', Text) - 1));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TStatementTextTests);

end.
