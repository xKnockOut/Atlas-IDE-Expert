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
    procedure ForWithLiteralBoundsRunsAtLeastOnce;
    [Test]
    procedure ForBoundsAndDirection;
    [Test]
    procedure ForWithConstantBoundRunsAtLeastOnce;
    [Test]
    procedure ExitWithValueSetsResult;
    [Test]
    procedure BreakLeavesLoop;
    [Test]
    procedure EndlessLoopEndsOnlyThroughExit;
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
    procedure ReachingDefinitionsSkipFailedAssignment;
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
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Semantics.ControlFlow.Statements;

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
  mIndex: Integer;
begin
  if ANode.Kind = AKind then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindKind(ANode.Children[mIndex], AKind);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

/// <summary>Anweisung mit dem Namen AName (Zuweisungsziel oder aufgerufene Routine).</summary>
function FindStatement(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  if (ANode.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement]) and SameText(ANode.Name, AName) then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindStatement(ANode.Children[mIndex], AName);
    if Result <> nil then
    begin
      Exit;
    end;
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
  mIndex: Integer;
begin
  if (ANode.Kind = TSyntaxKind.RoutineDecl) and SameText(ANode.Name, AName) then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindRoutine(ANode.Children[mIndex], AName);
    if Result <> nil then
    begin
      Exit;
    end;
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.IsReachable(NodeNamed(F, 'Dead')));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.IsReachable(NodeNamed(F, 'Alive')));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.MayEndWithout('Result'));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.MayEndWithout('Result'));
  finally
    F.Free;
  end;
end;

/// <summary>for mit Literalen als Grenzen und nicht leerem Bereich läuft sicher einmal; leerer Bereich, downto
/// und Variablen als Grenze lassen den Weg am Rumpf vorbei offen.</summary>
procedure TControlFlowTests.ForWithLiteralBoundsRunsAtLeastOnce;

  function MayEndWithoutResult(const ABody: string): Boolean;
  var
    mFixture: TFlowFixture;
  begin
    mFixture := Flow(ABody);
    try
      Result := mFixture.Graph.MayEndWithout('Result') = TFlowAnswer.Yes;
    finally
      mFixture.Free;
    end;
  end;

begin
  Assert.IsFalse(MayEndWithoutResult('  for I := 0 to 64 do'#13#10'    Result := I;'));
  Assert.IsFalse(MayEndWithoutResult('  for I := 3 downto 1 do'#13#10'    Result := I;'));
  Assert.IsFalse(MayEndWithoutResult('  for var J: Integer := 1 to 1 do'#13#10'    Result := J;'));
  Assert.IsTrue(MayEndWithoutResult('  for I := 64 to 0 do'#13#10'    Result := I;'));
  Assert.IsTrue(MayEndWithoutResult('  for I := 0 downto 64 do'#13#10'    Result := I;'));
  Assert.IsTrue(MayEndWithoutResult('  for I := 0 to X do'#13#10'    Result := I;'));
  Assert.IsTrue(MayEndWithoutResult('  for I := 0 to 64 do'#13#10'    if I > X then'#13#10'      Result := I;'));
end;

/// <summary>Eine echte Konstante der Unit als Grenze gilt wie ihr Wert (WithRetries
/// im Update-Netzadapter, cAttempts = 3); typisierte, doppelt deklarierte oder verdeckte Namen
/// nicht.</summary>
procedure TControlFlowTests.ForWithConstantBoundRunsAtLeastOnce;

  function MayEndWithoutResult(const ADeclarations, ABody: string): Boolean;
  var
    mFixture: TFlowFixture;
  begin
    mFixture := FlowWith(ADeclarations, ABody);
    try
      Result := mFixture.Graph.MayEndWithout('Result') = TFlowAnswer.Yes;
    finally
      mFixture.Free;
    end;
  end;

const
  cLoop = '  for I := 1 to cAttempts do'#13#10'    Result := I;';
begin
  Assert.IsFalse(MayEndWithoutResult('const cAttempts = 3;', cLoop));
  Assert.IsFalse(MayEndWithoutResult('const cAttempts = $10;', '  for I := cAttempts downto 2 do'#13#10 +
    '    Result := I;'));
  Assert.IsTrue(MayEndWithoutResult('const cAttempts = 0;', cLoop));
  Assert.IsTrue(MayEndWithoutResult('const cAttempts: Integer = 3;', cLoop));
  Assert.IsTrue(MayEndWithoutResult('', cLoop));
  Assert.IsTrue(MayEndWithoutResult('{$IF Defined(A)}const cAttempts = 3;{$ELSE}const cAttempts = 0;{$IFEND}',
    cLoop));
  Assert.IsTrue(MayEndWithoutResult('const cAttempts = 3;'#13#10 +
    'procedure G(cAttempts: Integer);'#13#10'begin'#13#10'end;', cLoop));
end;

/// <summary>Grenzen aus Zahlenliteralen (auch $hex, nach dem Typ einer Inline-Variablen) und downto aus dem
/// Parser; ohne for-Schleife keine Aussage.</summary>
procedure TControlFlowTests.ForBoundsAndDirection;
var
  mFixture: TFlowFixture;
  mFor: TSyntaxNode;
  mFrom, mTo: Int64;
begin
  mFixture := Flow('  for var J: Integer := $10 downto 2 do'#13#10'    Y := J;');
  try
    mFor := FindKind(mFixture.Tree.Root, TSyntaxKind.ForStatement);
    Assert.IsTrue(TFlowStatements.LiteralBounds(mFor, mFrom, mTo));
    Assert.AreEqual(Int64(16), mFrom);
    Assert.AreEqual(Int64(2), mTo);
    Assert.IsTrue(mFor.Descending);
    Assert.IsTrue(TFlowStatements.RunsAtLeastOnce(mFor));
    Assert.IsFalse(TFlowStatements.RunsAtLeastOnce(FindKind(mFixture.Tree.Root, TSyntaxKind.RoutineDecl)));
    Assert.IsTrue(TFlowStatements.IsStatement(TSyntaxKind.ForStatement));
    Assert.IsFalse(TFlowStatements.IsStatement(TSyntaxKind.Literal));
  finally
    mFixture.Free;
  end;
end;

procedure TControlFlowTests.ExitWithValueSetsResult;
var
  F: TFlowFixture;
begin
  F := Flow('  if X > 0 then Exit(1);'#13#10'  Result := 2;');
  try
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.MayEndWithout('Result'));
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.EndlessLoopEndsOnlyThroughExit;
var
  F: TFlowFixture;
  mBody: string;
begin
  // while True und repeat … until False laufen nur über Exit, Break oder raise hinaus (#1109).
  for mBody in TArray<string>.Create('  while True do'#13#10'    if X > 0 then Exit(1);',
    '  repeat'#13#10'    if X > 0 then Exit(1);'#13#10'  until False;',
    '  while (True) do'#13#10'    if X > 0 then Exit(1);') do
  begin
    F := Flow(mBody);
    try
      Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.MayEndWithout('Result'), mBody);
    finally
      F.Free;
    end;
  end;
  // Break verlässt die Schleife ohne Result.
  F := Flow('  while True do'#13#10'    if X > 0 then Break else Exit(1);');
  try
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.MayEndWithout('Result'));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.IsReachable(NodeNamed(F, 'Dead')));
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.IsReachable(NodeNamed(F, 'After')));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.IsReachable(NodeNamed(F, 'Dead')));
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.FinallyRunsOnExit;
var
  F: TFlowFixture;
  mSyntax: TSyntaxNode;
  mNode: TFlowNode;
  mOnExitPath: Boolean;
begin
  F := Flow('  try'#13#10'    Exit;'#13#10'  finally'#13#10'    Cleanup;'#13#10'  end;'#13#10'  Dead;');
  try
    // Seit #647 gibt es je Ausgang eine Kopie des finally-Blocks: Eine Kopie ist erreichbar, das Ende auch,
    // der Code hinter dem try nicht.
    mSyntax := FindStatement(F.Tree.Root, 'Cleanup');
    mOnExitPath := False;
    for mNode in F.Graph.Nodes do
    begin
      if (mNode.Syntax = mSyntax) and (F.Graph.IsReachable(mNode) = TFlowAnswer.Yes) then
      begin
        mOnExitPath := True;
      end;
    end;
    Assert.IsTrue(mOnExitPath, 'finally läuft');
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.IsReachable(F.Graph.ExitNode), 'Routine endet');
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.IsReachable(NodeNamed(F, 'Dead')), 'Exit springt');
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.IsReachable(NodeNamed(F, 'Dead')));
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.IsReachable(F.Graph.RaiseExit));
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.IsReachable(F.Graph.ExitNode));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.IsReachable(NodeNamed(F, 'Handle')));
    // Nicht behandelte Ausnahmen verlassen die Routine.
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.IsReachable(F.Graph.RaiseExit));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.IsReachable(NodeNamed(F, 'Dead')));
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.IsReachable(NodeNamed(F, 'Target')));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.Dominates(NodeNamed(F, 'Y'), NodeNamed(F, 'Use')));
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.Dominates(NodeNamed(F, 'Z'), NodeNamed(F, 'Use')));
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ReachingDefinitionsInLoop;
var
  F: TFlowFixture;
  mDefs: TReachingDefinitions;
begin
  F := Flow('  while X > 0 do'#13#10'  begin'#13#10'    Use;'#13#10'    Y := 1;'#13#10'  end;');
  try
    mDefs := F.Graph.ReachingDefinitions(NodeNamed(F, 'Use'), 'Y');
    Assert.AreEqual(1, Integer(Length(mDefs.Definitions)));
    Assert.IsTrue(mDefs.FromEntry);
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.MayEndWithout('Result'));
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.IsReachable(F.Graph.RaiseExit));
  finally
    F.Free;
  end;
  // Das finally steht je Ausgang einmal im Graphen, gilt aber nur einmal als erreichbar.
  F := Flow('  try'#13#10'    Exit;'#13#10'  finally'#13#10'    Cleanup;'#13#10'  end;'#13#10'  Dead;');
  try
    Assert.AreEqual(1, Integer(Length(F.Graph.UnreachableStatements)));
    Assert.AreSame(NodeNamed(F, 'Dead'), F.Graph.UnreachableStatements[0]);
  finally
    F.Free;
  end;
end;

// Wirft Load, wird Y nie gesetzt: Im except und dahinter gilt noch Y := nil (#1109).
procedure TControlFlowTests.ReachingDefinitionsSkipFailedAssignment;
var
  F: TFlowFixture;
  mDefs: TReachingDefinitions;
begin
  F := Flow('  Y := nil;'#13#10'  try'#13#10'    Y := Load;'#13#10'  except'#13#10'    Report;'#13#10'  end;'#13#10'  Use;');
  try
    mDefs := F.Graph.ReachingDefinitions(NodeNamed(F, 'Use'), 'Y');
    Assert.AreEqual(2, Integer(Length(mDefs.Definitions)));
    mDefs := F.Graph.ReachingDefinitions(NodeNamed(F, 'Report'), 'Y');
    Assert.AreEqual(1, Integer(Length(mDefs.Definitions)));
    Assert.AreSame(NodeNamed(F, 'Y'), mDefs.Definitions[0], 'im except gilt nur Y := nil');
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ReachingDefinitionsWithoutEntryPath;
var
  F: TFlowFixture;
  mDefs: TReachingDefinitions;
begin
  F := Flow('  Y := 1;'#13#10'  if X > 0 then Y := 2;'#13#10'  Use;');
  try
    mDefs := F.Graph.ReachingDefinitions(NodeNamed(F, 'Use'), 'Y');
    Assert.AreEqual(2, Integer(Length(mDefs.Definitions)));
    Assert.IsFalse(mDefs.FromEntry);
    Assert.IsFalse(mDefs.MaybeFromEntry);
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.MayReadBeforeWrite('Y'));
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.MayReadBeforeWrite(NodeNamed(F, 'Result'), 'Y'));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.MayReadBeforeWrite('Y'));
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.MayReadBeforeWrite(NodeNamed(F, 'Result'), 'Y'));
    // X ist Parameter und hat keine Zuweisung: aus Sicht der Routine vom Anfang an gelesen.
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.MayReadBeforeWrite('X'));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Unknown, F.Graph.MayEndWithout('Result'));
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Unknown, F.Graph.MayReadBeforeWrite('Y'));
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.UncertainChangeGivesUnknown;
const
  // var-/out-Argument mit unbekannter oder bekannter Signatur, Adresse, Teilzuweisung (#143).
  cStatements: array[0..9] of string = ('Dict.TryGetValue(X, Result);', 'TryGetValue(X, Result);',
    'SetLength(Result, X);', 'FillChar(Result, SizeOf(Result), 0);', 'P := @Result;', 'P := Addr(Result);',
    'Result.Feld := 1;', 'Result[0] := 1;', 'Result.Init(X);', 'with Result do Feld := 1;');
var
  F: TFlowFixture;
  mDefs: TReachingDefinitions;
  mStatement: string;
begin
  for mStatement in cStatements do
  begin
    F := Flow('  ' + mStatement);
    try
      Assert.IsTrue(F.Graph.Complete, mStatement);
      Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Unknown, F.Graph.MayEndWithout('Result'), mStatement);
      mDefs := F.Graph.ReachingDefinitions(F.Graph.ExitNode, 'Result');
      Assert.IsFalse(mDefs.FromEntry, mStatement);
      Assert.IsTrue(mDefs.MaybeFromEntry, mStatement);
      Assert.AreEqual(1, Integer(Length(mDefs.Uncertain)), mStatement);
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.MayEndWithout('Result'));
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.MayReadBeforeWrite('Result'));
  finally
    F.Free;
  end;
  // Standardroutinen mit Wertparametern ebenso.
  F := Flow('  Writeln(IntToStr(Result));');
  try
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.MayEndWithout('Result'));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Unknown, F.Graph.MayEndWithout('Result'));
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Unknown, F.Graph.MayReadBeforeWrite('Result'));
  finally
    F.Free;
  end;
  F := FlowWith('procedure Take(out V: Integer);'#13#10'begin'#13#10'end;',
    '  Take(Result);');
  try
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Unknown, F.Graph.MayEndWithout('Result'));
    // out liest nicht.
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.MayReadBeforeWrite('Result'));
  finally
    F.Free;
  end;
  // Überladungen mit unterschiedlicher Übergabe: unbekannt.
  F := FlowWith('procedure Show(const V: Integer); overload;'#13#10'begin'#13#10'end;'#13#10 +
    'procedure Show(var V: Integer); overload;'#13#10'begin'#13#10'end;', '  Show(Result);');
  try
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Unknown, F.Graph.MayEndWithout('Result'));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.MayEndWithout('Result'));
  finally
    F.Free;
  end;
  // Ein Weg ohne unsichere Änderung bleibt Yes.
  F := Flow('  if X > 0 then SetLength(Result, X);');
  try
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.MayEndWithout('Result'));
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ValueArgumentIsRead;
var
  F: TFlowFixture;
  mNode: TFlowNode;
begin
  F := Flow('  Use(Y + 1, Dict.Items[I]);');
  try
    mNode := NodeNamed(F, 'Use');
    Assert.IsTrue(mNode.ReadsName('Y'));
    Assert.IsTrue(mNode.ReadsName('I'), 'Index in einer Kette wird gelesen');
    Assert.IsTrue(mNode.TouchesName('Dict'), 'unbekannte Signatur');
    Assert.IsFalse(mNode.TouchesName('Y'), 'Ausdruck kann nicht var-Argument sein');
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Unknown, F.Graph.MayEndWithout('Result'));
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
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.IsReachable(NodeNamed(F, 'Result')));
    Assert.AreEqual(0, Integer(Length(F.Graph.UnreachableStatements)));
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.No, F.Graph.MayEndWithout('Result'));
  finally
    F.Free;
  end;
end;

procedure TControlFlowTests.ImplicitRaiseEdgesAreMarked;
var
  F: TFlowFixture;

  function ImplicitEdges(ANode: TFlowNode): Integer;
  var
    mNext: TFlowNode;
  begin
    Result := 0;
    for mNext in ANode.Successors do
    begin
      if ANode.IsImplicitRaiseEdge(mNext) then
      begin
        Inc(Result);
      end;
    end;
  end;

begin
  // Ausnahmewege einer Anweisung im try sind markiert (#915); raise und der normale Weg nicht.
  F := Flow('  Vorher;'#13#10'  try'#13#10'    A;'#13#10'    Werfen;'#13#10'  except'#13#10'    C;'#13#10'  end;'#13#10 +
    '  try'#13#10'    D;'#13#10'  finally'#13#10'    E;'#13#10'  end;'#13#10'  Result := 1;');
  try
    Assert.IsFalse(NodeNamed(F, 'Vorher').MayRaise, 'außerhalb von try');
    Assert.AreEqual(0, ImplicitEdges(NodeNamed(F, 'Vorher')));
    Assert.IsTrue(NodeNamed(F, 'A').MayRaise);
    Assert.AreEqual(2, Integer(NodeNamed(F, 'A').Successors.Count));
    Assert.AreEqual(1, ImplicitEdges(NodeNamed(F, 'A')), 'A: Weg zum except');
    Assert.AreEqual(1, ImplicitEdges(NodeNamed(F, 'D')), 'D: Weg zur finally-Kopie für Ausnahmen');
    Assert.IsFalse(NodeNamed(F, 'E').MayRaise, 'finally liegt außerhalb des try-Teils');
    Assert.AreEqual<TFlowAnswer>(TFlowAnswer.Yes, F.Graph.IsReachable(NodeNamed(F, 'Result')));
  finally
    F.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TControlFlowTests);

end.
