unit Atlas.Common.Pascal.SyntaxTree.Tests;

// Tests für den Besucher TSyntaxNode.Walk (Review P-03).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSyntaxTreeTests = class
  public
    [Test]
    procedure WalkVisitsAllNodesInTreeOrder;
    [Test]
    procedure WalkSkipsChildrenWhenVisitReturnsFalse;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser;

const
  Source = 'unit A;'#10'interface'#10'implementation'#10 +
    'procedure P;'#10'var X: Integer;'#10'begin'#10'  X := 1;'#10'  if X > 0 then X := 2;'#10'end;'#10 +
    'procedure Q;'#10'begin'#10'end;'#10'end.';

procedure CollectRecursive(ANode: TSyntaxNode; AList: TList<TSyntaxNode>);
var
  Index: Integer;
begin
  AList.Add(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    CollectRecursive(ANode.Children[Index], AList);
end;

function CountKind(ANode: TSyntaxNode; AKind: TSyntaxKind): Integer;
var
  Index: Integer;
begin
  Result := 0;
  if ANode.Kind = AKind then
    Inc(Result);
  for Index := 0 to ANode.ChildCount - 1 do
    Inc(Result, CountKind(ANode.Children[Index], AKind));
end;

procedure TSyntaxTreeTests.WalkVisitsAllNodesInTreeOrder;
var
  Tree: TSyntaxTree;
  Expected, Visited: TList<TSyntaxNode>;
  Index: Integer;
begin
  Tree := TPascalParser.Parse(Source);
  Expected := TList<TSyntaxNode>.Create;
  Visited := TList<TSyntaxNode>.Create;
  try
    CollectRecursive(Tree.Root, Expected);
    Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Visited.Add(ANode);
        Result := True;
      end);
    Assert.IsTrue(Expected.Count > 10, 'Baum zu klein');
    Assert.AreEqual(Expected.Count, Visited.Count, 'Anzahl Knoten');
    Assert.IsTrue(Visited[0] = Tree.Root, 'erster Knoten ist die Wurzel');
    for Index := 0 to Expected.Count - 1 do
      Assert.IsTrue(Expected[Index] = Visited[Index], 'Reihenfolge an Stelle ' + IntToStr(Index));
  finally
    Visited.Free;
    Expected.Free;
    Tree.Free;
  end;
end;

procedure TSyntaxTreeTests.WalkSkipsChildrenWhenVisitReturnsFalse;
var
  Tree: TSyntaxTree;
  Routines, Blocks: Integer;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Assert.IsTrue(CountKind(Tree.Root, TSyntaxKind.Block) > 0, 'Blöcke vorhanden');
    Routines := 0;
    Blocks := 0;
    Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if ANode.Kind = TSyntaxKind.RoutineDecl then
          Inc(Routines);
        if ANode.Kind = TSyntaxKind.Block then
          Inc(Blocks);
        Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      end);
    Assert.AreEqual(2, Routines, 'Routinen besucht');
    Assert.AreEqual(0, Blocks, 'keine Blöcke unter übersprungenen Routinen');
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSyntaxTreeTests);

end.
