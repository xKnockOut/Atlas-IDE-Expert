unit Atlas.Common.Semantics.ControlFlow.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TControlFlowTests = class
  public
    [Test]
    procedure FindsCodeAfterExitUnreachable;
    [Test]
    procedure IfWithoutElseFallsThrough;
    [Test]
    procedure ResultSetOnAllPaths;
    [Test]
    procedure ResultMissingOnOnePath;
    [Test]
    procedure ExitWithValueSetsResult;
    [Test]
    procedure BreakLeavesLoop;
    [Test]
    procedure ContinueSkipsRestOfBody;
    [Test]
    procedure FinallyRunsOnExit;
    [Test]
    procedure RaiseSkipsFollowingCode;
    [Test]
    procedure ExceptHandlerReachableFromTryBody;
    [Test]
    procedure GotoJumpsToLabel;
    [Test]
    procedure DominanceOfAssignment;
    [Test]
    procedure ReachingDefinitionsInLoop;
    [Test]
    procedure AsmGivesUnknown;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.ControlFlow;

type
  TFlowFixture = record
    Tree: TSyntaxTree;
    Graph: TControlFlowGraph;
    procedure Free;
  end;

procedure TFlowFixture.Free;
begin
  Graph.Free;
  Tree.Free;
end;

function FindKind(ANode: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  Index: Integer;
begin
  if ANode.Kind = AKind then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindKind(ANode.Children[Index], AKind);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

/// <summary>Anweisung mit dem Namen AName (Zuweisungsziel oder aufgerufene Routine).</summary>
function FindStatement(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement]) and SameText(ANode.Name, AName) then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindStatement(ANode.Children[Index], AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

function Flow(const ABody: string): TFlowFixture;
begin
  Result.Tree := TPascalParser.Parse(
    'unit A;'#13#10'interface'#13#10'implementation'#13#10 +
    'function F(X: Integer): Integer;'#13#10'label L1;'#13#10'var I, Y: Integer;'#13#10 +
    'begin'#13#10 + ABody + #13#10'end;'#13#10'end.');
  Result.Graph := TControlFlowGraph.Build(FindKind(Result.Tree.Root, TSyntaxKind.RoutineDecl));
end;

function NodeNamed(const AFixture: TFlowFixture; const AName: string): TFlowNode;
begin
  Result := AFixture.Graph.NodeOf(FindStatement(AFixture.Tree.Root, AName));
end;

{ TControlFlowTests }

procedure TControlFlowTests.FindsCodeAfterExitUnreachable;
var
  F: TFlowFixture;
begin
  F := Flow('  Result := 1;'#13#10'  Exit;'#13#10'  Dead;');
  try
    Assert.IsTrue(F.Graph.Complete);
    Assert.AreEqual(1, Integer(Length(F.Graph.UnreachableStatements)));
    Assert.IsTrue(F.Graph.IsReachable(NodeNamed(F, 'Dead')) = TFlowAnswer.No);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.IfWithoutElseFallsThrough;
var
  F: TFlowFixture;
begin
  F := Flow('  if X > 0 then Exit;'#13#10'  Alive;');
  try
    Assert.IsTrue(F.Graph.IsReachable(NodeNamed(F, 'Alive')) = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ResultSetOnAllPaths;
var
  F: TFlowFixture;
begin
  F := Flow('  if X > 0 then Result := 1 else Result := 2;');
  try
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.No);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ResultMissingOnOnePath;
var
  F: TFlowFixture;
begin
  F := Flow('  if X > 0 then Result := 1;');
  try
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ExitWithValueSetsResult;
var
  F: TFlowFixture;
begin
  F := Flow('  if X > 0 then Exit(1);'#13#10'  Result := 2;');
  try
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.No);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.BreakLeavesLoop;
var
  F: TFlowFixture;
begin
  F := Flow('  while True do'#13#10'  begin'#13#10'    Break;'#13#10'    Dead;'#13#10'  end;'#13#10'  After;');
  try
    Assert.IsTrue(F.Graph.IsReachable(NodeNamed(F, 'Dead')) = TFlowAnswer.No);
    Assert.IsTrue(F.Graph.IsReachable(NodeNamed(F, 'After')) = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ContinueSkipsRestOfBody;
var
  F: TFlowFixture;
begin
  F := Flow('  for I := 0 to 3 do'#13#10'  begin'#13#10'    Continue;'#13#10'    Dead;'#13#10'  end;');
  try
    Assert.IsTrue(F.Graph.IsReachable(NodeNamed(F, 'Dead')) = TFlowAnswer.No);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.FinallyRunsOnExit;
var
  F: TFlowFixture;
  Cleanup: TFlowNode;
begin
  F := Flow('  try'#13#10'    Exit;'#13#10'  finally'#13#10'    Cleanup;'#13#10'  end;'#13#10'  Dead;');
  try
    Cleanup := NodeNamed(F, 'Cleanup');
    Assert.IsTrue(F.Graph.Dominates(Cleanup, F.Graph.ExitNode) = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.RaiseSkipsFollowingCode;
var
  F: TFlowFixture;
begin
  F := Flow('  raise Exception.Create(''x'');'#13#10'  Dead;');
  try
    Assert.IsTrue(F.Graph.IsReachable(NodeNamed(F, 'Dead')) = TFlowAnswer.No);
    Assert.IsTrue(F.Graph.IsReachable(F.Graph.RaiseExit) = TFlowAnswer.Yes);
    Assert.IsTrue(F.Graph.IsReachable(F.Graph.ExitNode) = TFlowAnswer.No);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ExceptHandlerReachableFromTryBody;
var
  F: TFlowFixture;
begin
  F := Flow('  try'#13#10'    Work;'#13#10'  except'#13#10'    on E: Exception do Handle;'#13#10'  end;');
  try
    Assert.IsTrue(F.Graph.IsReachable(NodeNamed(F, 'Handle')) = TFlowAnswer.Yes);
    // Nicht behandelte Ausnahmen verlassen die Routine.
    Assert.IsTrue(F.Graph.IsReachable(F.Graph.RaiseExit) = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.GotoJumpsToLabel;
var
  F: TFlowFixture;
begin
  F := Flow('  goto L1;'#13#10'  Dead;'#13#10'L1:'#13#10'  Target;');
  try
    Assert.IsTrue(F.Graph.IsReachable(NodeNamed(F, 'Dead')) = TFlowAnswer.No);
    Assert.IsTrue(F.Graph.IsReachable(NodeNamed(F, 'Target')) = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.DominanceOfAssignment;
var
  F: TFlowFixture;
begin
  F := Flow('  Y := 1;'#13#10'  if X > 0 then Z := 2;'#13#10'  Use;');
  try
    Assert.IsTrue(F.Graph.Dominates(NodeNamed(F, 'Y'), NodeNamed(F, 'Use')) = TFlowAnswer.Yes);
    Assert.IsTrue(F.Graph.Dominates(NodeNamed(F, 'Z'), NodeNamed(F, 'Use')) = TFlowAnswer.No);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ReachingDefinitionsInLoop;
var
  F: TFlowFixture;
  Defs: TReachingDefinitions;
begin
  F := Flow('  while X > 0 do'#13#10'  begin'#13#10'    Use;'#13#10'    Y := 1;'#13#10'  end;');
  try
    Defs := F.Graph.ReachingDefinitions(NodeNamed(F, 'Use'), 'Y');
    Assert.AreEqual(1, Integer(Length(Defs.Definitions)));
    Assert.IsTrue(Defs.FromEntry);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.AsmGivesUnknown;
var
  F: TFlowFixture;
begin
  F := Flow('  asm'#13#10'    nop'#13#10'  end;');
  try
    Assert.IsFalse(F.Graph.Complete);
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.Unknown);
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TControlFlowTests);

end.
