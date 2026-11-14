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
  mText: string;
  mTree: TSyntaxTree;
  mBlock: TSyntaxNode;
begin
  mText := 'program P;'#10'begin'#10'  A := 1;'#10'  ;'#10'  B;'#10'  if X then C;'#10'end.';
  mTree := TPascalParser.Parse(mText);
  try
    mBlock := MainBlock(mTree);
    Assert.AreEqual(3, Integer(Length(TStatementText.Statements(mBlock))));
    Assert.AreEqual(1, Integer(Length(TStatementText.Statements(mBlock[0]))));
    Assert.AreEqual(0, Integer(Length(TStatementText.Statements(nil))));
  finally
    mTree.Free;
  end;
end;

procedure TStatementTextTests.TextKeepsCommentsAndReindents;
var
  mText: string;
  mTree: TSyntaxTree;
  mStatements: TArray<TSyntaxNode>;
begin
  mText := 'program P;'#10'begin'#10'  // vorher'#10'  A := 1; // dahinter'#10'  if X then'#10'  begin'#10 +
    '    B;'#10'  end;'#10'  { am Ende }'#10'end.';
  mTree := TPascalParser.Parse(mText);
  try
    mStatements := TStatementText.Statements(MainBlock(mTree));
    Assert.AreEqual('      // vorher'#10'      A := 1'#0'// dahinter', TStatementText.Text(mText, mTree, mStatements[0],
      False, '      ', #10));
    Assert.AreEqual('    if X then'#10'    begin'#10'      B;'#10'    end'#0#10'    { am Ende }',
      TStatementText.Text(mText, mTree, mStatements[1], True, '    ', #13#10).Replace(#13#10, #10));
    Assert.AreEqual('  // vorher'#10'  A := 1; // dahinter'#10'  if X then'#10'  begin'#10'    B;'#10'  end;'#10 +
      '  { am Ende }', TStatementText.List(mText, mTree, mStatements, '  ', #10));
  finally
    mTree.Free;
  end;
end;

procedure TStatementTextTests.BranchWithOneAndManyStatements;
var
  mText: string;
  mTree: TSyntaxTree;
  mStatements: TArray<TSyntaxNode>;
  mLayout: TStatementLayout;
begin
  mText := 'program P;'#10'begin'#10'  A := 1;'#10'  B;'#10'end.';
  mTree := TPascalParser.Parse(mText);
  try
    mStatements := TStatementText.Statements(MainBlock(mTree));
    mLayout := TStatementLayout.Create('  ', '  ', #10);
    Assert.AreEqual(#10'    A := 1', TStatementText.Branch(mText, mTree, [mStatements[0]], mLayout, False));
    Assert.AreEqual(#10'  begin'#10'    A := 1;'#10'    B;'#10'  end', TStatementText.Branch(mText, mTree, mStatements,
      mLayout, False));
    Assert.AreEqual('', TStatementText.Branch(mText, mTree, nil, mLayout, False));
    Assert.AreEqual(#10'  begin'#10'  end', TStatementText.Branch(mText, mTree, nil, mLayout, True));
    Assert.AreEqual('    ', mLayout.Deeper.Indent);
  finally
    mTree.Free;
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
  mText: string;
  mTree: TSyntaxTree;
begin
  mText := 'program P;'#10'begin'#10'  A := {x} 1;'#10'end.';
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsTrue(TStatementText.HasComment(mTree, 0, Length(mText)));
    Assert.IsFalse(TStatementText.HasComment(mTree, 0, Pos('{', mText) - 1));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TStatementTextTests);

end.
