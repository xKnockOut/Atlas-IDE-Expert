unit Atlas.Common.Rules.Builtin.Flow.UseAfterFree;

// Regel use-after-free aus Atlas.Common.Rules.Builtin.Flow (#269): Nach X.Free, X.Destroy, X.DisposeOf,
// FreeAndNil(X) oder Dispose(X) liest ein Weg des Kontrollflusses X wieder. Eine Zuweisung an X, die Übergabe als
// Argument und @X beenden den Weg; Assigned(X) und Vergleiche mit nil trennen ihn.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TUseAfterFreeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  UseAfterFreeRuleId = 'use-after-free';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared;

type
  /// <summary>Prüfung einer Unit für use-after-free; hält den Graphen der Routine, die Freigabe und den Stand des
  /// gerade untersuchten Knotens.</summary>
  TUseAfterFreeCheck = class
  strict private
    FReport: IRuleReport;
    FGraph: TControlFlowGraph;
    FReported: TArray<Integer>;
    FFree: TFlowNode;
    FPath: string;
    FToNil: Boolean;
    FUses: TArray<TSyntaxNode>;
    FStops: Boolean;
    FGuarded: Boolean;
    function AlreadyReported(AOffset: Integer): Boolean;
    function VisitAccess(ANode: TSyntaxNode): Integer;
    procedure VisitArgument(const ACallee: string; AArgument: TSyntaxNode);
    procedure VisitCall(ANode: TSyntaxNode);
    function VisitAddress(ANode: TSyntaxNode): Integer;
    procedure VisitBinary(ANode: TSyntaxNode);
    function FirstChildToVisit(ANode: TSyntaxNode): Integer;
    procedure Visit(ARoot: TSyntaxNode);
    procedure Inspect(ASyntax: TSyntaxNode);
    function StopsAt(ANode: TFlowNode): Boolean;
    procedure ReportAccess(ANode: TFlowNode; AAccess: TSyntaxNode);
    function WalksOn(ANode: TFlowNode): Boolean;
    procedure Follow(AFree: TFlowNode; const APath: string; AToNil: Boolean);
    procedure CheckGraph;
  public
    constructor Create(const AReport: IRuleReport);
    procedure Run(const AContext: TRuleContext);
  end;

{ TUseAfterFreeCheck }

constructor TUseAfterFreeCheck.Create(const AReport: IRuleReport);
begin
  inherited Create;
  FReport := AReport;
end;

function TUseAfterFreeCheck.AlreadyReported(AOffset: Integer): Boolean;
var
  Offset: Integer;
begin
  Result := False;
  for Offset in FReported do
  begin
    Result := Result or (Offset = AOffset);
  end;
end;

/// <summary>X.…, X[…], X^: ein Zugriff; danach nicht mehr in X selbst absteigen.</summary>
function TUseAfterFreeCheck.VisitAccess(ANode: TSyntaxNode): Integer;
begin
  Result := 0;
  if (ANode.ChildCount > 0) and SameText(FreedPath(ANode[0]), FPath) then
  begin
    // Nach FreeAndNil ist ein weiteres Free harmlos.
    if not (FToNil and (ANode.Kind = TSyntaxKind.MemberAccess) and SameText(ANode.Name, 'Free')) then
    begin
      FUses := FUses + [ANode[0]];
    end;
    Result := 1;
  end;
end;

procedure TUseAfterFreeCheck.VisitArgument(const ACallee: string; AArgument: TSyntaxNode);
begin
  if MatchText(ACallee, ['Assigned', 'FreeAndNil']) and not FToNil then
  begin
    // Nach Free: Assigned(X) ist immer True, FreeAndNil(X) gibt doppelt frei.
    FUses := FUses + [AArgument];
  end
  else if SameText(ACallee, 'Assigned') then
  begin
    FGuarded := True;
  end
  else
  begin
    // Übergabe: die Routine kann X neu setzen oder nur vergleichen (List.Remove(X)).
    FStops := True;
  end;
end;

procedure TUseAfterFreeCheck.VisitCall(ANode: TSyntaxNode);
var
  Index: Integer;
  Callee: string;
begin
  Callee := '';
  if (ANode.ChildCount > 0) and (ANode[0].Kind = TSyntaxKind.Identifier) then
  begin
    Callee := ANode[0].Name;
  end;
  for Index := 1 to ANode.ChildCount - 1 do
  begin
    if SameText(FreedPath(ANode[Index]), FPath) then
    begin
      VisitArgument(Callee, ANode[Index]);
    end;
  end;
end;

/// <summary>@X beendet den Weg; die Kinder bleiben aus.</summary>
function TUseAfterFreeCheck.VisitAddress(ANode: TSyntaxNode): Integer;
begin
  Result := 0;
  if (ANode.ChildCount > 0) and SameText(FreedPath(ANode[0]), FPath) then
  begin
    FStops := True;
    Result := ANode.ChildCount;
  end;
end;

/// <summary>X = nil, X &lt;&gt; nil: eine Abfrage, die den Weg trennt.</summary>
procedure TUseAfterFreeCheck.VisitBinary(ANode: TSyntaxNode);
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    FGuarded := FGuarded or SameText(FreedPath(ANode[Index]), FPath);
  end;
end;

/// <summary>Wertet ANode aus; Ergebnis: ab diesem Kind weiter absteigen (ChildCount: gar nicht).</summary>
function TUseAfterFreeCheck.FirstChildToVisit(ANode: TSyntaxNode): Integer;
begin
  Result := 0;
  if ANode.Kind in [TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl] then
  begin
    Result := ANode.ChildCount;
  end
  else if ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Dereference] then
  begin
    Result := VisitAccess(ANode);
  end
  else if ANode.Kind = TSyntaxKind.Call then
  begin
    VisitCall(ANode);
  end
  else if ANode.Kind = TSyntaxKind.AddressOf then
  begin
    Result := VisitAddress(ANode);
  end
  else if ANode.Kind = TSyntaxKind.BinaryExpr then
  begin
    VisitBinary(ANode);
  end;
end;

procedure TUseAfterFreeCheck.Visit(ARoot: TSyntaxNode);
var
  Index, First: Integer;
  Node: TSyntaxNode;
  Pending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      First := FirstChildToVisit(Node);
      for Index := Node.ChildCount - 1 downto First do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Zugriffe auf FPath im eigenen Teil der Anweisung bzw. Bedingung ASyntax.</summary>
procedure TUseAfterFreeCheck.Inspect(ASyntax: TSyntaxNode);
var
  Index: Integer;
  Child: TSyntaxNode;
  AllChildren: Boolean;
begin
  AllChildren := ASyntax.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst];
  for Index := 0 to ASyntax.ChildCount - 1 do
  begin
    Child := ASyntax[Index];
    if not AllChildren and (Child.Kind in FlowStatementKinds) then
    begin
      Continue;
    end;
    if (Index = 0) and (ASyntax.Kind = TSyntaxKind.AssignStatement) and SameText(FreedPath(Child), FPath) then
    begin
      FStops := True;
    end
    else if (ASyntax.Kind = TSyntaxKind.WithStatement) and SameText(FreedPath(Child), FPath) then
    begin
      FUses := FUses + [Child];
    end
    else
    begin
      Visit(Child);
    end;
  end;
end;

/// <summary>Weist ANode FPath neu zu? for und for … in tun das in jedem Durchlauf mit der Schleifenvariablen.
/// </summary>
function TUseAfterFreeCheck.StopsAt(ANode: TFlowNode): Boolean;
begin
  Result := SameText(ANode.Defines, FPath);
  if not Result and (ANode.Kind = TFlowNodeKind.Condition) then
  begin
    Result := (ANode.Syntax.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and
      SameText(ANode.Syntax.Name, FPath);
  end;
end;

procedure TUseAfterFreeCheck.ReportAccess(ANode: TFlowNode; AAccess: TSyntaxNode);
var
  Confidence: TRuleConfidence;
  FreeLine: Integer;
  Message: string;
begin
  if AlreadyReported(AAccess.StartOffset) then
  begin
    Exit;
  end;
  FReported := FReported + [AAccess.StartOffset];
  // Im selben Block nacheinander: der Zugriff folgt sicher auf die Freigabe.
  Confidence := TRuleConfidence.Medium;
  if (ANode.Syntax.Parent = FFree.Syntax.Parent) and (ANode.Syntax.StartOffset > FFree.Syntax.StartOffset) then
  begin
    Confidence := TRuleConfidence.High;
  end;
  FreeLine := FFree.Syntax.StartPos.Line + 1;
  if FToNil then
  begin
    Message := Format('%s wurde in Zeile %d mit FreeAndNil freigegeben und ist hier nil.', [FPath, FreeLine]);
  end
  else
  begin
    Message := Format('%s wurde in Zeile %d freigegeben und wird hier wieder gelesen.', [FPath, FreeLine]);
  end;
  FReport.Add(NodeRange(AAccess), Message, Confidence,
    [TRuleFix.Jump(Format('Zur Freigabe in Zeile %d springen', [FreeLine]), FFree.Syntax.StartPos)]);
end;

/// <summary>Meldet die Zugriffe in ANode; True, wenn der Weg hinter ANode weitergeht.</summary>
function TUseAfterFreeCheck.WalksOn(ANode: TFlowNode): Boolean;
var
  Access: TSyntaxNode;
begin
  FStops := StopsAt(ANode);
  FGuarded := False;
  FUses := nil;
  if (ANode.Syntax <> nil) and not FStops then
  begin
    Inspect(ANode.Syntax);
  end;
  Result := False;
  if not (FGuarded and FToNil) then
  begin
    for Access in FUses do
    begin
      ReportAccess(ANode, Access);
    end;
    Result := not (FStops or FGuarded);
  end;
end;

procedure TUseAfterFreeCheck.Follow(AFree: TFlowNode; const APath: string; AToNil: Boolean);
var
  Visited: TArray<Boolean>;
  Queue: TArray<TFlowNode>;
  Head: Integer;
  Current: TFlowNode;
begin
  FFree := AFree;
  FPath := APath;
  FToNil := AToNil;
  SetLength(Visited, FGraph.Nodes.Count);
  Queue := nil;
  QueueSuccessors(AFree, Visited, Queue);
  Head := 0;
  while Head < Length(Queue) do
  begin
    Current := Queue[Head];
    Inc(Head);
    if not Visited[Current.Index] then
    begin
      Visited[Current.Index] := True;
      if WalksOn(Current) then
      begin
        QueueSuccessors(Current, Visited, Queue);
      end;
    end;
  end;
  FUses := nil;
end;

procedure TUseAfterFreeCheck.CheckGraph;
var
  Node: TFlowNode;
  Path: string;
  ToNil: Boolean;
begin
  for Node in FGraph.Nodes do
  begin
    if (Node.Kind = TFlowNodeKind.Statement) and FreedBy(Node.Syntax, Path, ToNil) then
    begin
      Follow(Node, Path, ToNil);
    end;
  end;
end;

procedure TUseAfterFreeCheck.Run(const AContext: TRuleContext);
var
  Cache: IRuleDerivedCache;
  Routine: TSyntaxNode;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Cache := TRuleDerived.Open(AContext);
  for Routine in TRuleDerived.Routines(Cache, AContext) do
  begin
    FGraph := TRuleDerived.Graph(Cache, AContext, Routine);
    if FGraph.Complete then
    begin
      CheckGraph;
    end;
  end;
end;

{ TUseAfterFreeRule }

function TUseAfterFreeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(UseAfterFreeRuleId, TRuleSeverity.Error, 'Objekt nach Free weiter benutzt');
end;

procedure TUseAfterFreeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TUseAfterFreeCheck;
begin
  Check := TUseAfterFreeCheck.Create(AReport);
  try
    Check.Run(AContext);
  finally
    Check.Free;
  end;
end;

end.
