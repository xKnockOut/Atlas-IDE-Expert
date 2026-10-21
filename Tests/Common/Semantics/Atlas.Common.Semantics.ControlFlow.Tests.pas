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
    [Test]
    procedure ExceptionPathThroughFinallyDoesNotEndNormally;
    [Test]
    procedure ReachingDefinitionsWithoutEntryPath;
    [Test]
    procedure MayReadBeforeWriteFindsEarlyRead;
    [Test]
    procedure MayReadBeforeWriteSilentAfterAssignment;
    [Test]
    procedure SyntaxErrorGivesUnknown;
    [Test]
    procedure UncertainChangeGivesUnknown;
    [Test]
    procedure KnownConstParameterKeepsAnswer;
    [Test]
    procedure KnownVarAndOutParameterGiveUnknown;
    [Test]
    procedure AssignmentAfterUncertainChangeGivesNo;
    [Test]
    procedure ValueArgumentIsRead;
    procedure MethodNamedExitIsOrdinaryCall;
    [Test]
    procedure ImplicitRaiseEdgesAreMarked;
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

function FindRoutine(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and SameText(ANode.Name, AName) then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindRoutine(ANode.Children[Index], AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

/// <summary>Wie Flow, mit weiteren Routinen der Unit vor F (für bekannte Signaturen, #143).</summary>
function FlowWith(const ADeclarations, ABody: string): TFlowFixture;
begin
  Result.Tree := TPascalParser.Parse(
    'unit A;'#13#10'interface'#13#10'implementation'#13#10 + ADeclarations + #13#10 +
    'function F(X: Integer): Integer;'#13#10'var I, Y: Integer;'#13#10 +
    'begin'#13#10 + ABody + #13#10'end;'#13#10'end.');
  Result.Graph := TControlFlowGraph.Build(FindRoutine(Result.Tree.Root, 'F'));
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
  Syntax: TSyntaxNode;
  Node: TFlowNode;
  OnExitPath: Boolean;
begin
  F := Flow('  try'#13#10'    Exit;'#13#10'  finally'#13#10'    Cleanup;'#13#10'  end;'#13#10'  Dead;');
  try
    // Seit #647 gibt es je Ausgang eine Kopie des finally-Blocks: Eine Kopie ist erreichbar, das Ende auch,
    // der Code hinter dem try nicht.
    Syntax := FindStatement(F.Tree.Root, 'Cleanup');
    OnExitPath := False;
    for Node in F.Graph.Nodes do
      if (Node.Syntax = Syntax) and (F.Graph.IsReachable(Node) = TFlowAnswer.Yes) then
        OnExitPath := True;
    Assert.IsTrue(OnExitPath, 'finally läuft');
    Assert.IsTrue(F.Graph.IsReachable(F.Graph.ExitNode) = TFlowAnswer.Yes, 'Routine endet');
    Assert.IsTrue(F.Graph.IsReachable(NodeNamed(F, 'Dead')) = TFlowAnswer.No, 'Exit springt');
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

procedure TControlFlowTests.ExceptionPathThroughFinallyDoesNotEndNormally;
var
  F: TFlowFixture;
begin
  // Eine Ausnahme vor "Result := 1" läuft durch finally und verlässt die Routine;
  // sie endet nicht normal ohne Result (#647).
  F := Flow('  try'#13#10'    Work;'#13#10'    Result := 1;'#13#10'  finally'#13#10'    Cleanup;'#13#10'  end;');
  try
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.No);
    Assert.IsTrue(F.Graph.IsReachable(F.Graph.RaiseExit) = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
  // Das finally steht je Ausgang einmal im Graphen, gilt aber nur einmal als erreichbar.
  F := Flow('  try'#13#10'    Exit;'#13#10'  finally'#13#10'    Cleanup;'#13#10'  end;'#13#10'  Dead;');
  try
    Assert.AreEqual(1, Integer(Length(F.Graph.UnreachableStatements)));
    Assert.IsTrue(F.Graph.UnreachableStatements[0] = NodeNamed(F, 'Dead'));
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ReachingDefinitionsWithoutEntryPath;
var
  F: TFlowFixture;
  Defs: TReachingDefinitions;
begin
  F := Flow('  Y := 1;'#13#10'  if X > 0 then Y := 2;'#13#10'  Use;');
  try
    Defs := F.Graph.ReachingDefinitions(NodeNamed(F, 'Use'), 'Y');
    Assert.AreEqual(2, Integer(Length(Defs.Definitions)));
    Assert.IsFalse(Defs.FromEntry);
    Assert.IsFalse(Defs.MaybeFromEntry);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.MayReadBeforeWriteFindsEarlyRead;
var
  F: TFlowFixture;
begin
  F := Flow('  if X > 0 then Y := 1;'#13#10'  Result := Y;');
  try
    Assert.IsTrue(F.Graph.MayReadBeforeWrite('Y') = TFlowAnswer.Yes);
    Assert.IsTrue(F.Graph.MayReadBeforeWrite(NodeNamed(F, 'Result'), 'Y') = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.MayReadBeforeWriteSilentAfterAssignment;
var
  F: TFlowFixture;
begin
  F := Flow('  Y := X;'#13#10'  if X > 0 then Y := 2;'#13#10'  Result := Y;');
  try
    Assert.IsTrue(F.Graph.MayReadBeforeWrite('Y') = TFlowAnswer.No);
    Assert.IsTrue(F.Graph.MayReadBeforeWrite(NodeNamed(F, 'Result'), 'Y') = TFlowAnswer.No);
    // X ist Parameter und hat keine Zuweisung: aus Sicht der Routine vom Anfang an gelesen.
    Assert.IsTrue(F.Graph.MayReadBeforeWrite('X') = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.SyntaxErrorGivesUnknown;
var
  F: TFlowFixture;
begin
  F := Flow('  if X > 0 then Result := 1;'#13#10'  Y := ) 2;');
  try
    Assert.IsFalse(F.Graph.Complete);
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.Unknown);
    Assert.IsTrue(F.Graph.MayReadBeforeWrite('Y') = TFlowAnswer.Unknown);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.UncertainChangeGivesUnknown;
const
  // var-/out-Argument mit unbekannter oder bekannter Signatur, Adresse, Teilzuweisung (#143).
  Statements: array[0..9] of string = ('Dict.TryGetValue(X, Result);', 'TryGetValue(X, Result);',
    'SetLength(Result, X);', 'FillChar(Result, SizeOf(Result), 0);', 'P := @Result;', 'P := Addr(Result);',
    'Result.Feld := 1;', 'Result[0] := 1;', 'Result.Init(X);', 'with Result do Feld := 1;');
var
  F: TFlowFixture;
  Defs: TReachingDefinitions;
  Statement: string;
begin
  for Statement in Statements do
  begin
    F := Flow('  ' + Statement);
    try
      Assert.IsTrue(F.Graph.Complete, Statement);
      Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.Unknown, Statement);
      Defs := F.Graph.ReachingDefinitions(F.Graph.ExitNode, 'Result');
      Assert.IsFalse(Defs.FromEntry, Statement);
      Assert.IsTrue(Defs.MaybeFromEntry, Statement);
      Assert.AreEqual(1, Integer(Length(Defs.Uncertain)), Statement);
    finally
      F.Free;
    end;
  end;
end;

procedure TControlFlowTests.KnownConstParameterKeepsAnswer;
var
  F: TFlowFixture;
begin
  F := FlowWith('procedure Show(const V: Integer; W: Integer);'#13#10'begin'#13#10'end;',
    '  Show(Result, Result);');
  try
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.Yes);
    Assert.IsTrue(F.Graph.MayReadBeforeWrite('Result') = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
  // Standardroutinen mit Wertparametern ebenso.
  F := Flow('  Writeln(IntToStr(Result));');
  try
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.KnownVarAndOutParameterGiveUnknown;
var
  F: TFlowFixture;
begin
  F := FlowWith('procedure Fill(var V: Integer);'#13#10'begin'#13#10'end;',
    '  Fill(Result);');
  try
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.Unknown);
    Assert.IsTrue(F.Graph.MayReadBeforeWrite('Result') = TFlowAnswer.Unknown);
  finally
    F.Free;
  end;
  F := FlowWith('procedure Take(out V: Integer);'#13#10'begin'#13#10'end;',
    '  Take(Result);');
  try
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.Unknown);
    // out liest nicht.
    Assert.IsTrue(F.Graph.MayReadBeforeWrite('Result') = TFlowAnswer.No);
  finally
    F.Free;
  end;
  // Überladungen mit unterschiedlicher Übergabe: unbekannt.
  F := FlowWith('procedure Show(const V: Integer); overload;'#13#10'begin'#13#10'end;'#13#10 +
    'procedure Show(var V: Integer); overload;'#13#10'begin'#13#10'end;', '  Show(Result);');
  try
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.Unknown);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.AssignmentAfterUncertainChangeGivesNo;
var
  F: TFlowFixture;
begin
  F := Flow('  SetLength(Result, X);'#13#10'  Result := 1;');
  try
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.No);
  finally
    F.Free;
  end;
  // Ein Weg ohne unsichere Änderung bleibt Yes.
  F := Flow('  if X > 0 then SetLength(Result, X);');
  try
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ValueArgumentIsRead;
var
  F: TFlowFixture;
  Node: TFlowNode;
begin
  F := Flow('  Use(Y + 1, Dict.Items[I]);');
  try
    Node := NodeNamed(F, 'Use');
    Assert.IsTrue(Node.ReadsName('Y'));
    Assert.IsTrue(Node.ReadsName('I'), 'Index in einer Kette wird gelesen');
    Assert.IsTrue(Node.TouchesName('Dict'), 'unbekannte Signatur');
    Assert.IsFalse(Node.TouchesName('Y'), 'Ausdruck kann nicht var-Argument sein');
  finally
    F.Free;
  end;
  // Eine anonyme Methode kann Y später ändern.
  F := Flow('  Y := 1;'#13#10'  Proc := procedure begin Y := 2; end;'#13#10'  Use(Y);');
  try
    Assert.IsTrue(NodeNamed(F, 'Proc').TouchesName('Y'));
    Assert.AreEqual(1, Integer(Length(F.Graph.ReachingDefinitions(NodeNamed(F, 'Use'), 'Y').Uncertain)));
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

procedure TControlFlowTests.MethodNamedExitIsOrdinaryCall;
var
  F: TFlowFixture;
begin
  // TMonitor.Exit(FLock) im finally ist kein Exit der Routine (#647).
  F := Flow('  try'#13#10'    Y := 1;'#13#10'  finally'#13#10'    TMonitor.Exit(Self);'#13#10'  end;'#13#10 +
    '  Result := Y;');
  try
    Assert.IsTrue(F.Graph.IsReachable(NodeNamed(F, 'Result')) = TFlowAnswer.Yes);
    Assert.AreEqual(0, Integer(Length(F.Graph.UnreachableStatements)));
    Assert.IsTrue(F.Graph.MayEndWithout('Result') = TFlowAnswer.No);
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ImplicitRaiseEdgesAreMarked;
var
  F: TFlowFixture;

  function ImplicitEdges(ANode: TFlowNode): Integer;
  var
    Next: TFlowNode;
  begin
    Result := 0;
    for Next in ANode.Successors do
      if ANode.IsImplicitRaiseEdge(Next) then
        Inc(Result);
  end;

begin
  // Ausnahmewege einer Anweisung im try sind markiert (#915); raise und der normale Weg nicht.
  F := Flow('  Vorher;'#13#10'  try'#13#10'    A;'#13#10'    Werfen;'#13#10'  except'#13#10'    C;'#13#10'  end;'#13#10 +
    '  try'#13#10'    D;'#13#10'  finally'#13#10'    E;'#13#10'  end;'#13#10'  Result := 1;');
  try
    Assert.IsFalse(NodeNamed(F, 'Vorher').MayRaise, 'außerhalb von try');
    Assert.AreEqual(0, ImplicitEdges(NodeNamed(F, 'Vorher')));
    Assert.IsTrue(NodeNamed(F, 'A').MayRaise);
    Assert.AreEqual(2, NodeNamed(F, 'A').Successors.Count);
    Assert.AreEqual(1, ImplicitEdges(NodeNamed(F, 'A')), 'A: Weg zum except');
    Assert.AreEqual(1, ImplicitEdges(NodeNamed(F, 'D')), 'D: Weg zur finally-Kopie für Ausnahmen');
    Assert.IsFalse(NodeNamed(F, 'E').MayRaise, 'finally liegt außerhalb des try-Teils');
    Assert.IsTrue(F.Graph.IsReachable(NodeNamed(F, 'Result')) = TFlowAnswer.Yes);
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TControlFlowTests);

end.
