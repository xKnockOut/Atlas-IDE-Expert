unit Argus.Common.Semantics.ControlFlow;

// Kontrollflussgraph je Routine als gemeinsamer Dienst für flussbasierte
// Prüfregeln (unerreichbarer Code, nicht gesetztes Result, nicht
// initialisierte Variablen, Speicherlecks, ungenutzte Variablen).
//
// Jede Anweisung ist ein Knoten. Bedingungen von if, case und Schleifen
// sind eigene Knoten der Art Condition. Berücksichtigt werden
// try/finally/except, Exit, Break, Continue, raise, Abort, Halt und goto.
// Innerhalb eines try kann jede Anweisung eine Ausnahme auslösen; außerhalb
// führen nur raise und Abort zum Knoten RaiseExit.
//
// Ein finally-Block wird einmal modelliert: Jeder Sprung, der ihn verlässt,
// führt hinein, und sein Ende führt zu allen so erreichten Zielen. Der Graph
// enthält damit eher zu viele Wege als zu wenige; Aussagen „auf jedem Weg“
// bleiben dadurch sicher.
//
// Zuweisungen: einfache Zuweisungen an einen Bezeichner, Schleifenvariablen,
// Inline-Variablen mit Startwert und Exit(Wert) für Result. Zuweisungen über
// var/out-Parameter sind nicht erfasst.
//
// Enthält die Routine asm oder Syntaxfehler, ist der Graph unvollständig;
// die Abfragen liefern dann Unknown statt einer Vermutung.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Argus.Common.Pascal.SyntaxTree;

type
  TFlowNodeKind = (Entry, Exit, RaiseExit, Statement, Condition, Join);

  TFlowAnswer = (No, Yes, Unknown);

  TFlowNode = class
  private
    FIndex: Integer;
    FKind: TFlowNodeKind;
    FSyntax: TSyntaxNode;
    FDefines: string;
    FSuccessors: TList<TFlowNode>;
    FPredecessors: TList<TFlowNode>;
  public
    constructor Create(AIndex: Integer; AKind: TFlowNodeKind; ASyntax: TSyntaxNode);
    destructor Destroy; override;
    property Index: Integer read FIndex;
    property Kind: TFlowNodeKind read FKind;
    /// <summary>Anweisung oder Bedingung; nil bei Entry, Exit, RaiseExit und Join.</summary>
    property Syntax: TSyntaxNode read FSyntax;
    /// <summary>Name der Variablen, der dieser Knoten einen Wert zuweist; sonst ''.</summary>
    property Defines: string read FDefines;
    property Successors: TList<TFlowNode> read FSuccessors;
    property Predecessors: TList<TFlowNode> read FPredecessors;
  end;

  TReachingDefinitions = record
    /// <summary>Zuweisungen, die den Knoten ohne erneute Zuweisung erreichen.</summary>
    Definitions: TArray<TFlowNode>;
    /// <summary>Ein Weg vom Anfang der Routine kommt ohne Zuweisung an.</summary>
    FromEntry: Boolean;
  end;

  TControlFlowGraph = class
  private
    FNodes: TObjectList<TFlowNode>;
    FEntry: TFlowNode;
    FExit: TFlowNode;
    FRaiseExit: TFlowNode;
    FComplete: Boolean;
    FDominators: TArray<TArray<Boolean>>;
    procedure ComputeDominators;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Baut den Graphen für eine Routine (RoutineDecl, AnonymousMethod)
    /// oder einen Anweisungsblock. Der Syntaxbaum muss länger leben als der Graph.</summary>
    class function Build(ARoutine: TSyntaxNode): TControlFlowGraph; static;
    function NodeOf(ASyntax: TSyntaxNode): TFlowNode;
    function IsReachable(ANode: TFlowNode): TFlowAnswer;
    /// <summary>Wird A auf jedem Weg vom Anfang zu B durchlaufen?</summary>
    function Dominates(A, B: TFlowNode): TFlowAnswer;
    /// <summary>Anweisungen, die vom Anfang aus nicht erreichbar sind.</summary>
    function UnreachableStatements: TArray<TFlowNode>;
    function ReachingDefinitions(ANode: TFlowNode; const AName: string): TReachingDefinitions;
    /// <summary>Kann die Routine normal enden, ohne dass AName (z. B. Result) gesetzt wurde?</summary>
    function MayEndWithout(const AName: string): TFlowAnswer;
    property Nodes: TObjectList<TFlowNode> read FNodes;
    property Entry: TFlowNode read FEntry;
    property ExitNode: TFlowNode read FExit;
    property RaiseExit: TFlowNode read FRaiseExit;
    /// <summary>False bei asm oder Syntaxfehlern in der Routine.</summary>
    property Complete: Boolean read FComplete;
  end;

implementation

type
  /// <summary>Sprungziel, dessen Knoten erst später feststeht.</summary>
  TJumpTarget = class
  public
    Depth: Integer;
    Sources: TList<TFlowNode>;
    constructor Create(ADepth: Integer);
    destructor Destroy; override;
  end;

  TFinallyContext = class
  public
    Entry: TJumpTarget;
    Onward: TList<TJumpTarget>;
    constructor Create(ADepth: Integer);
    destructor Destroy; override;
  end;

  TLoopContext = record
    BreakTarget: TJumpTarget;
    ContinueTarget: TJumpTarget;
  end;

  TFlowBuilder = class
  private
    FGraph: TControlFlowGraph;
    FTargets: TObjectList<TJumpTarget>;
    FFinallies: TObjectList<TFinallyContext>;
    FLoops: TList<TLoopContext>;
    FRaiseTargets: TList<TJumpTarget>;
    FExitTarget: TJumpTarget;
    FRaiseTarget: TJumpTarget;
    FLabels: TDictionary<string, TFlowNode>;
    FTryDepth: Integer;
    function NewNode(AKind: TFlowNodeKind; ASyntax: TSyntaxNode): TFlowNode;
    function NewTarget: TJumpTarget;
    procedure Link(AFrom, ATo: TFlowNode);
    procedure LinkAll(const AFrom: TArray<TFlowNode>; ATo: TFlowNode);
    procedure Resolve(ATarget: TJumpTarget; ATo: TFlowNode);
    procedure Jump(AFrom: TFlowNode; ATarget: TJumpTarget);
    function LabelNode(const AName: string): TFlowNode;
    function Simple(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TFlowNode;
    function Sequence(AParent: TSyntaxNode; AFirst: Integer; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function Statement(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildIf(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildCase(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildLoop(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildRepeat(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildTry(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildCall(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
  public
    constructor Create(AGraph: TControlFlowGraph);
    destructor Destroy; override;
    procedure Run(ARoutine: TSyntaxNode);
  end;

function IsStatement(AKind: TSyntaxKind): Boolean;
begin
  case AKind of
    TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement,
    TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
    TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.RaiseStatement,
    TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement, TSyntaxKind.Error:
      Result := True;
  else
    Result := False;
  end;
end;

function Concat(const A, B: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Node: TFlowNode;
begin
  Result := A;
  for Node in B do
    Result := Result + [Node];
end;

{ TFlowNode }

constructor TFlowNode.Create(AIndex: Integer; AKind: TFlowNodeKind; ASyntax: TSyntaxNode);
begin
  inherited Create;
  FIndex := AIndex;
  FKind := AKind;
  FSyntax := ASyntax;
  FSuccessors := TList<TFlowNode>.Create;
  FPredecessors := TList<TFlowNode>.Create;
end;

destructor TFlowNode.Destroy;
begin
  FSuccessors.Free;
  FPredecessors.Free;
  inherited;
end;

{ TJumpTarget }

constructor TJumpTarget.Create(ADepth: Integer);
begin
  inherited Create;
  Depth := ADepth;
  Sources := TList<TFlowNode>.Create;
end;

destructor TJumpTarget.Destroy;
begin
  Sources.Free;
  inherited;
end;

{ TFinallyContext }

constructor TFinallyContext.Create(ADepth: Integer);
begin
  inherited Create;
  Entry := TJumpTarget.Create(ADepth);
  Onward := TList<TJumpTarget>.Create;
end;

destructor TFinallyContext.Destroy;
begin
  Entry.Free;
  Onward.Free;
  inherited;
end;

{ TFlowBuilder }

constructor TFlowBuilder.Create(AGraph: TControlFlowGraph);
begin
  inherited Create;
  FGraph := AGraph;
  FTargets := TObjectList<TJumpTarget>.Create;
  FFinallies := TObjectList<TFinallyContext>.Create(False);
  FLoops := TList<TLoopContext>.Create;
  FRaiseTargets := TList<TJumpTarget>.Create;
  FLabels := TDictionary<string, TFlowNode>.Create;
end;

destructor TFlowBuilder.Destroy;
begin
  FLabels.Free;
  FRaiseTargets.Free;
  FLoops.Free;
  FFinallies.Free;
  FTargets.Free;
  inherited;
end;

function TFlowBuilder.NewNode(AKind: TFlowNodeKind; ASyntax: TSyntaxNode): TFlowNode;
begin
  Result := TFlowNode.Create(FGraph.FNodes.Count, AKind, ASyntax);
  FGraph.FNodes.Add(Result);
end;

function TFlowBuilder.NewTarget: TJumpTarget;
begin
  Result := TJumpTarget.Create(FFinallies.Count);
  FTargets.Add(Result);
end;

procedure TFlowBuilder.Link(AFrom, ATo: TFlowNode);
begin
  if AFrom.FSuccessors.Contains(ATo) then
    Exit;
  AFrom.FSuccessors.Add(ATo);
  ATo.FPredecessors.Add(AFrom);
end;

procedure TFlowBuilder.LinkAll(const AFrom: TArray<TFlowNode>; ATo: TFlowNode);
var
  Node: TFlowNode;
begin
  for Node in AFrom do
    Link(Node, ATo);
end;

procedure TFlowBuilder.Resolve(ATarget: TJumpTarget; ATo: TFlowNode);
begin
  LinkAll(ATarget.Sources.ToArray, ATo);
end;

procedure TFlowBuilder.Jump(AFrom: TFlowNode; ATarget: TJumpTarget);
var
  Context: TFinallyContext;
begin
  // Verlässt der Sprung einen finally-Bereich, läuft er zuerst durch dessen finally.
  if FFinallies.Count > ATarget.Depth then
  begin
    Context := FFinallies[FFinallies.Count - 1];
    Context.Entry.Sources.Add(AFrom);
    if not Context.Onward.Contains(ATarget) then
      Context.Onward.Add(ATarget);
  end
  else
    ATarget.Sources.Add(AFrom);
end;

function TFlowBuilder.LabelNode(const AName: string): TFlowNode;
var
  Key: string;
begin
  Key := LowerCase(AName);
  if not FLabels.TryGetValue(Key, Result) then
  begin
    Result := NewNode(TFlowNodeKind.Join, nil);
    FLabels.Add(Key, Result);
  end;
end;

function TFlowBuilder.Simple(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TFlowNode;
begin
  Result := NewNode(TFlowNodeKind.Statement, AStatement);
  LinkAll(APreds, Result);
  // Innerhalb eines try kann jede Anweisung eine Ausnahme auslösen.
  if FTryDepth > 0 then
    Jump(Result, FRaiseTargets.Last);
end;

function TFlowBuilder.Sequence(AParent: TSyntaxNode; AFirst: Integer;
  const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Index: Integer;
begin
  Result := APreds;
  for Index := AFirst to AParent.ChildCount - 1 do
    if IsStatement(AParent.Children[Index].Kind) then
      Result := Statement(AParent.Children[Index], Result);
end;

function TFlowBuilder.Statement(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Node: TFlowNode;
  Index: Integer;
begin
  case S.Kind of
    TSyntaxKind.Block:
      Result := Sequence(S, 0, APreds);
    TSyntaxKind.IfStatement:
      Result := BuildIf(S, APreds);
    TSyntaxKind.CaseStatement:
      Result := BuildCase(S, APreds);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement:
      Result := BuildLoop(S, APreds);
    TSyntaxKind.RepeatStatement:
      Result := BuildRepeat(S, APreds);
    TSyntaxKind.WithStatement:
      begin
        Node := Simple(S, APreds);
        Result := Sequence(S, 0, [Node]);
      end;
    TSyntaxKind.TryStatement:
      Result := BuildTry(S, APreds);
    TSyntaxKind.CallStatement:
      Result := BuildCall(S, APreds);
    TSyntaxKind.RaiseStatement:
      begin
        Node := Simple(S, APreds);
        Jump(Node, FRaiseTargets.Last);
        Result := nil;
      end;
    TSyntaxKind.GotoStatement:
      begin
        Node := Simple(S, APreds);
        Link(Node, LabelNode(S.Name));
        Result := nil;
      end;
    TSyntaxKind.LabeledStatement:
      begin
        Node := LabelNode(S.Name);
        LinkAll(APreds, Node);
        Result := Sequence(S, 0, [Node]);
      end;
    TSyntaxKind.AssignStatement:
      begin
        Node := Simple(S, APreds);
        if (S.ChildCount > 0) and (S.Children[0].Kind = TSyntaxKind.Identifier) then
          Node.FDefines := S.Children[0].Name;
        Result := [Node];
      end;
    TSyntaxKind.InlineVar, TSyntaxKind.InlineConst:
      begin
        Node := Simple(S, APreds);
        for Index := 0 to S.ChildCount - 1 do
          if S.Children[Index].Kind <> TSyntaxKind.TypeReference then
            Node.FDefines := S.Name;
        Result := [Node];
      end;
    TSyntaxKind.AsmBlock, TSyntaxKind.Error:
      begin
        FGraph.FComplete := False;
        Result := [Simple(S, APreds)];
      end;
  else
    Result := [Simple(S, APreds)];
  end;
end;

function TFlowBuilder.BuildIf(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Condition: TFlowNode;
  Index, Branches: Integer;
begin
  Condition := NewNode(TFlowNodeKind.Condition, S);
  LinkAll(APreds, Condition);
  Result := nil;
  Branches := 0;
  for Index := 0 to S.ChildCount - 1 do
    if IsStatement(S.Children[Index].Kind) then
    begin
      Result := Concat(Result, Statement(S.Children[Index], [Condition]));
      Inc(Branches);
    end;
  if Branches < 2 then
    Result := Concat(Result, [Condition]);
end;

function TFlowBuilder.BuildCase(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Condition: TFlowNode;
  Index: Integer;
  HasElse: Boolean;
begin
  Condition := NewNode(TFlowNodeKind.Condition, S);
  LinkAll(APreds, Condition);
  Result := nil;
  HasElse := False;
  for Index := 0 to S.ChildCount - 1 do
    if S.Children[Index].Kind in [TSyntaxKind.CaseItem, TSyntaxKind.CaseElse] then
    begin
      HasElse := HasElse or (S.Children[Index].Kind = TSyntaxKind.CaseElse);
      Result := Concat(Result, Sequence(S.Children[Index], 0, [Condition]));
    end;
  if not HasElse then
    Result := Concat(Result, [Condition]);
end;

function TFlowBuilder.BuildLoop(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Init, Condition: TFlowNode;
  Loop: TLoopContext;
  Body: TArray<TFlowNode>;
begin
  Body := APreds;
  // for und for-in weisen der Schleifenvariablen vor dem ersten Durchlauf zu.
  if S.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
  begin
    Init := Simple(S, APreds);
    Init.FDefines := S.Name;
    Body := [Init];
  end;
  Condition := NewNode(TFlowNodeKind.Condition, S);
  LinkAll(Body, Condition);
  Loop.BreakTarget := NewTarget;
  Loop.ContinueTarget := NewTarget;
  FLoops.Add(Loop);
  Body := Sequence(S, 0, [Condition]);
  FLoops.Delete(FLoops.Count - 1);
  LinkAll(Body, Condition);
  Resolve(Loop.ContinueTarget, Condition);
  Result := Concat([Condition], Loop.BreakTarget.Sources.ToArray);
end;

function TFlowBuilder.BuildRepeat(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Head, Condition: TFlowNode;
  Loop: TLoopContext;
  Body: TArray<TFlowNode>;
begin
  Head := NewNode(TFlowNodeKind.Join, nil);
  LinkAll(APreds, Head);
  Loop.BreakTarget := NewTarget;
  Loop.ContinueTarget := NewTarget;
  FLoops.Add(Loop);
  Body := Sequence(S, 0, [Head]);
  FLoops.Delete(FLoops.Count - 1);
  Condition := NewNode(TFlowNodeKind.Condition, S);
  LinkAll(Body, Condition);
  Resolve(Loop.ContinueTarget, Condition);
  Link(Condition, Head);
  Result := Concat([Condition], Loop.BreakTarget.Sources.ToArray);
end;

function TFlowBuilder.BuildTry(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  ExceptPart, FinallyPart, Child: TSyntaxNode;
  Handlers: TJumpTarget;
  Context: TFinallyContext;
  Handler, FinallyEntry, Node: TFlowNode;
  Body, Ends: TArray<TFlowNode>;
  Index: Integer;
  HasHandlers, HasElse: Boolean;
  Onward: TJumpTarget;
begin
  ExceptPart := S.FindChild(TSyntaxKind.ExceptBlock);
  FinallyPart := S.FindChild(TSyntaxKind.FinallyBlock);
  if FinallyPart <> nil then
  begin
    Context := TFinallyContext.Create(FFinallies.Count);
    FFinallies.Add(Context);
    try
      // Ausnahmen im try-Teil verlassen den Bereich nach außen, also durch finally.
      Inc(FTryDepth);
      Body := Sequence(S, 0, APreds);
      Dec(FTryDepth);
      FFinallies.Delete(FFinallies.Count - 1);
      FinallyEntry := NewNode(TFlowNodeKind.Join, nil);
      LinkAll(Body, FinallyEntry);
      Resolve(Context.Entry, FinallyEntry);
      Ends := Sequence(FinallyPart, 0, [FinallyEntry]);
      for Onward in Context.Onward do
        for Node in Ends do
          Jump(Node, Onward);
      Result := Ends;
    finally
      Context.Free;
    end;
    Exit;
  end;

  if ExceptPart = nil then
    Exit(Sequence(S, 0, APreds));

  Handlers := NewTarget;
  FRaiseTargets.Add(Handlers);
  Inc(FTryDepth);
  Body := Sequence(S, 0, APreds);
  Dec(FTryDepth);
  FRaiseTargets.Delete(FRaiseTargets.Count - 1);
  Handler := NewNode(TFlowNodeKind.Join, nil);
  Resolve(Handlers, Handler);
  Result := Body;
  HasHandlers := False;
  HasElse := False;
  for Index := 0 to ExceptPart.ChildCount - 1 do
  begin
    Child := ExceptPart.Children[Index];
    if Child.Kind = TSyntaxKind.ExceptionHandler then
    begin
      HasHandlers := True;
      Ends := Sequence(Child, 0, [Handler]);
      Result := Concat(Result, Ends);
    end
    else if IsStatement(Child.Kind) then
      HasElse := True;
  end;
  if HasElse or not HasHandlers then
    Result := Concat(Result, Sequence(ExceptPart, 0, [Handler]))
  else
    // Nicht behandelte Ausnahmen laufen weiter nach außen.
    Jump(Handler, FRaiseTargets.Last);
end;

function TFlowBuilder.BuildCall(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Node: TFlowNode;
  Name: string;
begin
  Node := Simple(S, APreds);
  Name := LowerCase(S.Name);
  if Name = 'exit' then
  begin
    // Exit(Wert) setzt Result.
    if (S.ChildCount > 0) and (S.Children[0].Kind = TSyntaxKind.Call) and (S.Children[0].ChildCount > 1) then
      Node.FDefines := 'Result';
    Jump(Node, FExitTarget);
    Result := nil;
  end
  else if (Name = 'break') and (FLoops.Count > 0) then
  begin
    Jump(Node, FLoops.Last.BreakTarget);
    Result := nil;
  end
  else if (Name = 'continue') and (FLoops.Count > 0) then
  begin
    Jump(Node, FLoops.Last.ContinueTarget);
    Result := nil;
  end
  else if Name = 'abort' then
  begin
    Jump(Node, FRaiseTargets.Last);
    Result := nil;
  end
  else if Name = 'halt' then
  begin
    // Halt beendet das Programm; finally-Blöcke laufen nicht.
    Link(Node, FGraph.FExit);
    Result := nil;
  end
  else
    Result := [Node];
end;

procedure TFlowBuilder.Run(ARoutine: TSyntaxNode);
var
  Body: TSyntaxNode;
  Index: Integer;
  Ends: TArray<TFlowNode>;
begin
  FGraph.FEntry := NewNode(TFlowNodeKind.Entry, nil);
  FGraph.FExit := NewNode(TFlowNodeKind.Exit, nil);
  FGraph.FRaiseExit := NewNode(TFlowNodeKind.RaiseExit, nil);
  FExitTarget := NewTarget;
  FRaiseTarget := NewTarget;
  FRaiseTargets.Add(FRaiseTarget);
  Body := nil;
  if ARoutine.Kind = TSyntaxKind.Block then
    Body := ARoutine
  else
    for Index := ARoutine.ChildCount - 1 downto 0 do
      if ARoutine.Children[Index].Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] then
      begin
        Body := ARoutine.Children[Index];
        Break;
      end;
  if Body = nil then
  begin
    FGraph.FComplete := False;
    Link(FGraph.FEntry, FGraph.FExit);
    Exit;
  end;
  Ends := Statement(Body, [FGraph.FEntry]);
  LinkAll(Ends, FGraph.FExit);
  Resolve(FExitTarget, FGraph.FExit);
  Resolve(FRaiseTarget, FGraph.FRaiseExit);
end;

{ TControlFlowGraph }

constructor TControlFlowGraph.Create;
begin
  inherited Create;
  FNodes := TObjectList<TFlowNode>.Create;
  FComplete := True;
end;

destructor TControlFlowGraph.Destroy;
begin
  FNodes.Free;
  inherited;
end;

class function TControlFlowGraph.Build(ARoutine: TSyntaxNode): TControlFlowGraph;
var
  Builder: TFlowBuilder;
begin
  Result := TControlFlowGraph.Create;
  Builder := TFlowBuilder.Create(Result);
  try
    Builder.Run(ARoutine);
  finally
    Builder.Free;
  end;
end;

function TControlFlowGraph.NodeOf(ASyntax: TSyntaxNode): TFlowNode;
var
  Node: TFlowNode;
begin
  // Bei Schleifen gibt es Start- und Bedingungsknoten; der erste zählt.
  for Node in FNodes do
    if Node.Syntax = ASyntax then
      Exit(Node);
  Result := nil;
end;

function TControlFlowGraph.IsReachable(ANode: TFlowNode): TFlowAnswer;
var
  Seen: TArray<Boolean>;
  Stack: TStack<TFlowNode>;
  Node, Next: TFlowNode;
begin
  SetLength(Seen, FNodes.Count);
  Stack := TStack<TFlowNode>.Create;
  try
    Stack.Push(FEntry);
    Seen[FEntry.Index] := True;
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      if Node = ANode then
        Exit(TFlowAnswer.Yes);
      for Next in Node.Successors do
        if not Seen[Next.Index] then
        begin
          Seen[Next.Index] := True;
          Stack.Push(Next);
        end;
    end;
  finally
    Stack.Free;
  end;
  if FComplete then
    Result := TFlowAnswer.No
  else
    Result := TFlowAnswer.Unknown;
end;

procedure TControlFlowGraph.ComputeDominators;
var
  Count, I, J: Integer;
  Changed, Value: Boolean;
  Node, Pred: TFlowNode;
  First: Boolean;
begin
  if FDominators <> nil then
    Exit;
  Count := FNodes.Count;
  SetLength(FDominators, Count);
  for I := 0 to Count - 1 do
  begin
    SetLength(FDominators[I], Count);
    for J := 0 to Count - 1 do
      FDominators[I][J] := I <> FEntry.Index;
  end;
  FDominators[FEntry.Index][FEntry.Index] := True;
  repeat
    Changed := False;
    for Node in FNodes do
    begin
      if Node = FEntry then
        Continue;
      for J := 0 to Count - 1 do
      begin
        // Schnitt über alle Vorgänger, dazu der Knoten selbst.
        if J = Node.Index then
          Value := True
        else
        begin
          Value := False;
          First := True;
          for Pred in Node.Predecessors do
          begin
            if First then
              Value := FDominators[Pred.Index][J]
            else
              Value := Value and FDominators[Pred.Index][J];
            First := False;
          end;
        end;
        if Value <> FDominators[Node.Index][J] then
        begin
          FDominators[Node.Index][J] := Value;
          Changed := True;
        end;
      end;
    end;
  until not Changed;
end;

function TControlFlowGraph.Dominates(A, B: TFlowNode): TFlowAnswer;
begin
  if not FComplete then
    Exit(TFlowAnswer.Unknown);
  if IsReachable(B) <> TFlowAnswer.Yes then
    Exit(TFlowAnswer.Unknown);
  ComputeDominators;
  if FDominators[B.Index][A.Index] then
    Result := TFlowAnswer.Yes
  else
    Result := TFlowAnswer.No;
end;

function TControlFlowGraph.UnreachableStatements: TArray<TFlowNode>;
var
  Node: TFlowNode;
begin
  Result := nil;
  if not FComplete then
    Exit;
  for Node in FNodes do
    if (Node.Kind in [TFlowNodeKind.Statement, TFlowNodeKind.Condition]) and
      (IsReachable(Node) = TFlowAnswer.No) then
      Result := Result + [Node];
end;

function TControlFlowGraph.ReachingDefinitions(ANode: TFlowNode; const AName: string): TReachingDefinitions;
var
  Seen: TArray<Boolean>;
  Stack: TStack<TFlowNode>;
  Node, Pred: TFlowNode;
begin
  Result.Definitions := nil;
  Result.FromEntry := False;
  SetLength(Seen, FNodes.Count);
  Stack := TStack<TFlowNode>.Create;
  try
    for Pred in ANode.Predecessors do
      if not Seen[Pred.Index] then
      begin
        Seen[Pred.Index] := True;
        Stack.Push(Pred);
      end;
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      if SameText(Node.Defines, AName) then
      begin
        Result.Definitions := Result.Definitions + [Node];
        Continue;
      end;
      if Node = FEntry then
        Result.FromEntry := True;
      for Pred in Node.Predecessors do
        if not Seen[Pred.Index] then
        begin
          Seen[Pred.Index] := True;
          Stack.Push(Pred);
        end;
    end;
  finally
    Stack.Free;
  end;
end;

function TControlFlowGraph.MayEndWithout(const AName: string): TFlowAnswer;
begin
  if not FComplete then
    Exit(TFlowAnswer.Unknown);
  if ReachingDefinitions(FExit, AName).FromEntry then
    Result := TFlowAnswer.Yes
  else
    Result := TFlowAnswer.No;
end;

end.
