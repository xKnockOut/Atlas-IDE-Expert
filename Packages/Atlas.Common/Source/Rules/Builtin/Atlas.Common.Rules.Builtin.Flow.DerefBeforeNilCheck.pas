unit Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck;

// Regel deref-before-nil-check aus Atlas.Common.Rules.Builtin.Flow (#269): X.… oder X^ steht vor der ersten
// Abfrage X = nil, X &lt;&gt; nil, Assigned(X) oder X is T auf demselben Weg, ohne dass X dazwischen geändert wird.
// Die Korrektur zieht eine direkt folgende if-Abfrage vor den Zugriff.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TDerefBeforeNilCheckRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  DerefBeforeNilCheckRuleId = 'deref-before-nil-check';

implementation

uses
  System.SysUtils,
  Atlas.Text.Lines,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared;

function IsNilLiteral(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and SameText(ANode.Name, 'nil');
end;

/// <summary>Assigned(APath)?</summary>
function IsAssignedCall(ANode: TSyntaxNode; const APath: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and IsName(ANode[0], 'Assigned') and
    SameText(FreedPath(ANode[1]), APath);
end;

/// <summary>APath = nil oder APath &lt;&gt; nil (auch nil links)?</summary>
function IsNilComparison(ANode: TSyntaxNode; const APath: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.BinaryExpr) and MatchText(ANode.Name, ['=', '<>']) and (ANode.ChildCount = 2);
  Result := Result and ((SameText(FreedPath(ANode[0]), APath) and IsNilLiteral(ANode[1])) or
    (SameText(FreedPath(ANode[1]), APath) and IsNilLiteral(ANode[0])));
end;

/// <summary>Enthält ARoot Assigned(APath), APath = nil oder APath &lt;&gt; nil?</summary>
function ContainsNilCheck(ARoot: TSyntaxNode; const APath: string): Boolean;
var
  Path: string;
begin
  Path := APath;
  // Iterativ (Bericht M1).
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if IsAssignedCall(ANode, Path) or IsNilComparison(ANode, Path) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Enthält ARoot APath is TKlasse? Das ist für nil False und schützt wie Assigned (#1371).</summary>
function ContainsIsCheck(ARoot: TSyntaxNode; const APath: string): Boolean;
var
  Path: string;
begin
  Path := APath;
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind = TSyntaxKind.BinaryExpr) and SameText(ANode.Name, 'is') and (ANode.ChildCount = 2) and
        SameText(FreedPath(ANode[0]), Path) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

function NodeHasNilCheck(ANode: TFlowNode; const APath: string): Boolean;
var
  Part: TSyntaxNode;
begin
  Result := False;
  for Part in OwnParts(ANode.Syntax) do
  begin
    Result := Result or ContainsNilCheck(Part, APath) or ContainsIsCheck(Part, APath);
  end;
end;

/// <summary>Wurzeln der Zugriffe X.… und X^ in ARoot, in Textreihenfolge. X[…] zählt nicht: bei dynamischen
/// Arrays ist X &lt;&gt; nil die übliche Abfrage auf leer.</summary>
procedure CollectDerefs(ARoot: TSyntaxNode; var AList: TArray<TSyntaxNode>);
var
  Found: TArray<TSyntaxNode>;
begin
  Found := nil;
  // Iterativ (Bericht M1).
  ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Dereference]) and (ANode.ChildCount > 0) and
        (FreedPath(ANode[0]) <> '') then
      begin
        Found := Found + [ANode[0]];
      end;
    end);
  AList := AList + Found;
end;

/// <summary>Wird APath dem Aufruf ANode als Argument übergeben?</summary>
function PassesPath(ANode: TSyntaxNode; const APath: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 1 to ANode.ChildCount - 1 do
  begin
    Result := Result or SameText(FreedPath(ANode[Index]), APath);
  end;
end;

/// <summary>Kann der Ausdruck ANode selbst APath ändern? Ein Aufruf mit APath als Argument (bei Feldern und
/// globalen Variablen jeder Aufruf außer Assigned) oder @APath.</summary>
function ExpressionChangesPath(ANode: TSyntaxNode; const APath: string; ALocal: Boolean): Boolean;
begin
  if ANode.Kind = TSyntaxKind.Call then
  begin
    Result := (ANode.ChildCount > 0) and not IsName(ANode[0], 'Assigned');
    Result := Result and (not ALocal or PassesPath(ANode, APath));
  end
  else
  begin
    Result := (ANode.Kind = TSyntaxKind.AddressOf) and (ANode.ChildCount > 0) and
      SameText(FreedPath(ANode[0]), APath);
  end;
end;

function PartChangesPath(ARoot: TSyntaxNode; const APath: string; ALocal: Boolean): Boolean;
var
  Path: string;
  Local: Boolean;
begin
  Path := APath;
  Local := ALocal;
  // Iterativ (Bericht M1).
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if ExpressionChangesPath(ANode, Path, Local) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Kann der Knoten APath ändern? Zuweisung, Schleifenvariable, Übergabe als Argument, @X; bei
/// Feldern und globalen Variablen (ALocal = False) jeder Aufruf.</summary>
function ChangesPath(ANode: TFlowNode; const APath: string; ALocal: Boolean): Boolean;
var
  Part: TSyntaxNode;
begin
  Result := AssignsPath(ANode, APath);
  if Result or (ANode.Syntax = nil) then
  begin
    Exit;
  end;
  // X.Methode ohne Klammern ist ein Aufruf.
  Result := not ALocal and (ANode.Syntax.Kind = TSyntaxKind.CallStatement);
  for Part in OwnParts(ANode.Syntax) do
  begin
    Result := Result or PartChangesPath(Part, APath, ALocal);
  end;
end;

procedure AddNames(var ANames: TArray<string>; const AAdded: TArray<string>);
var
  Name: string;
begin
  for Name in AAdded do
  begin
    if not MatchText(Name, ANames) then
    begin
      ANames := ANames + [Name];
    end;
  end;
end;

/// <summary>Pfade, die die Routine irgendwo auf nil prüft; nur diese lohnen die Suche.</summary>
function CheckedNames(ARoutine: TSyntaxNode): TArray<string>;
var
  Names: TArray<string>;
begin
  Names := nil;
  // Iterativ (Bericht M1).
  ARoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      AddNames(Names, NilCheckedPaths(ANode));
      Result := TSyntaxSearchStep.Descend;
    end);
  Result := Names;
end;

/// <summary>Folgt ANext im selben Block direkt auf AStatement?</summary>
function FollowsDirectly(AStatement, ANext: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
  Position: Integer;
begin
  Parent := AStatement.Parent;
  Result := (Parent <> nil) and (Parent = ANext.Parent);
  if Result then
  begin
    Position := PositionIn(Parent, AStatement);
    Result := (Position >= 0) and (Position + 1 < Parent.ChildCount) and (Parent[Position + 1] = ANext);
  end;
end;

/// <summary>Teilt "if Bedingung then Rumpf" ohne else; False bei else oder fehlenden Teilen.</summary>
function SplitIf(AIf: TSyntaxNode; out ACondition, ABody: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  ACondition := nil;
  ABody := nil;
  Result := True;
  for Index := 0 to AIf.ChildCount - 1 do
  begin
    if AIf[Index].Kind in FlowStatementKinds then
    begin
      Result := Result and (ABody = nil);
      ABody := AIf[Index];
    end
    else if ACondition = nil then
    begin
      ACondition := AIf[Index];
    end;
  end;
  Result := Result and (ACondition <> nil) and (ABody <> nil);
end;

type
  /// <summary>Prüfung einer Unit für deref-before-nil-check; hält Text, Graph und die Pfade der Routine.
  /// </summary>
  TDerefCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FGraph: TControlFlowGraph;
    FChecked: TArray<string>;
    FLocals: TArray<string>;
    FDone: TArray<string>;
    FLineBreak: string;
    function CheckedBefore(ANode: TFlowNode; const APath: string): Boolean;
    function CheckAfter(ANode: TFlowNode; const APath: string; ALocal: Boolean): TFlowNode;
    function FreesToNil(ANode: TFlowNode; const APath: string): Boolean;
    function AssignedOnWay(AFrom, ATo: TFlowNode; const APath: string): Boolean;
    function GuardsLater(ANode, ACheck: TFlowNode; const APath: string): Boolean;
    function Source(ANode: TSyntaxNode): string;
    function Reindented(const AText, AIndent: string): string;
    function BodyText(ABody: TSyntaxNode; const AInner: string): string;
    function MoveCheckFix(AAccess, ACheck: TFlowNode; out AFix: TRuleFix): Boolean;
    procedure ReportDeref(ANode, ACheck: TFlowNode; ADeref: TSyntaxNode; const APath: string);
    procedure CheckDeref(ANode: TFlowNode; ADeref: TSyntaxNode);
    procedure CheckNode(ANode: TFlowNode);
    procedure CheckRoutine(const ACache: IRuleDerivedCache; ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TDerefCheck }

constructor TDerefCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
end;

/// <summary>Wird APath auf einem Weg zu ANode schon geprüft (ohne Zuweisung dazwischen)? Rückwärts beenden nur
/// sichere Zuweisungen den Weg: lieber eine Prüfung zu viel finden.</summary>
function TDerefCheck.CheckedBefore(ANode: TFlowNode; const APath: string): Boolean;
var
  Visited: TArray<Boolean>;
  Queue: TArray<TFlowNode>;
  Head: Integer;
  Current: TFlowNode;
begin
  Result := False;
  SetLength(Visited, FGraph.Nodes.Count);
  Queue := ANode.Predecessors.ToArray;
  Head := 0;
  while not Result and (Head < Length(Queue)) do
  begin
    Current := Queue[Head];
    Inc(Head);
    if not Visited[Current.Index] then
    begin
      Visited[Current.Index] := True;
      Result := (Current.Syntax <> nil) and NodeHasNilCheck(Current, APath);
      if not Result and not AssignsPath(Current, APath) then
      begin
        QueuePredecessors(Current, Visited, Queue);
      end;
    end;
  end;
end;

/// <summary>Erste Prüfung von APath nach ANode ohne Änderung dazwischen; nil ohne.</summary>
function TDerefCheck.CheckAfter(ANode: TFlowNode; const APath: string; ALocal: Boolean): TFlowNode;
var
  Visited: TArray<Boolean>;
  Queue: TArray<TFlowNode>;
  Head: Integer;
  Current: TFlowNode;
begin
  Result := nil;
  SetLength(Visited, FGraph.Nodes.Count);
  Queue := nil;
  QueueSuccessors(ANode, Visited, Queue);
  Head := 0;
  while (Result = nil) and (Head < Length(Queue)) do
  begin
    Current := Queue[Head];
    Inc(Head);
    if Visited[Current.Index] or (Current = ANode) then
    begin
      Continue;
    end;
    Visited[Current.Index] := True;
    if (Current.Syntax <> nil) and NodeHasNilCheck(Current, APath) then
    begin
      Result := Current;
    end
    else if not ChangesPath(Current, APath, ALocal) then
    begin
      QueueSuccessors(Current, Visited, Queue);
    end;
  end;
end;

/// <summary>FreeAndNil(APath) in ANode?</summary>
function TDerefCheck.FreesToNil(ANode: TFlowNode; const APath: string): Boolean;
var
  Freed: string;
  ToNil: Boolean;
begin
  Result := FreedBy(ANode.Syntax, Freed, ToNil) and ToNil and SameText(Freed, APath);
end;

/// <summary>Weist ein Weg von AFrom nach ATo APath neu zu? Dann gilt die Prüfung in ATo auch dem neuen Wert
/// (X := List[I]; if X.Kind = … then X := X.FindChild(…); if X = nil then; #1109). FreeAndNil(X) setzt X ebenso
/// neu (etwa im except-Zweig nach einem gescheiterten Laden): die spätere Prüfung gilt diesem Weg.</summary>
function TDerefCheck.AssignedOnWay(AFrom, ATo: TFlowNode; const APath: string): Boolean;
var
  Visited: TArray<Boolean>;
  Queue: TArray<TFlowNode>;
  Head: Integer;
  Current: TFlowNode;
begin
  Result := False;
  SetLength(Visited, FGraph.Nodes.Count);
  Queue := ATo.Predecessors.ToArray;
  Head := 0;
  while not Result and (Head < Length(Queue)) do
  begin
    Current := Queue[Head];
    Inc(Head);
    if not Visited[Current.Index] and (Current <> AFrom) then
    begin
      Visited[Current.Index] := True;
      Result := AssignsPath(Current, APath) or FreesToNil(Current, APath);
      QueuePredecessors(Current, Visited, Queue);
    end;
  end;
end;

/// <summary>Gilt die spätere Prüfung ACheck dem Zugriff in ANode?</summary>
function TDerefCheck.GuardsLater(ANode, ACheck: TFlowNode; const APath: string): Boolean;
begin
  // Eine Prüfung weiter oben, die erst der nächste Schleifendurchlauf erreicht, schützt den Zugriff.
  Result := (ACheck <> nil) and (ACheck.Syntax.StartOffset >= ANode.Syntax.StartOffset);
  // Nur wenn jeder Weg zur Prüfung durch den Zugriff führt; sonst gilt sie den anderen Wegen
  // (X := TX.Create; X.Init; … if X <> nil nach einem Zweig ohne Create).
  Result := Result and (FGraph.Dominates(ANode, ACheck) = TFlowAnswer.Yes) and
    not AssignedOnWay(ANode, ACheck, APath);
  // while X <> nil do … X := X.Parent: die Bedingung gilt den späteren Durchläufen.
  Result := Result and not ((ACheck.Syntax.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]) and
    SubtreeAssigns(ACheck.Syntax, APath));
end;

function TDerefCheck.Source(ANode: TSyntaxNode): string;
begin
  Result := SourceText(FContext.Text, ANode);
end;

/// <summary>Zeilen von AText mit AIndent davor; führende und folgende Leerzeilen fallen weg.</summary>
function TDerefCheck.Reindented(const AText, AIndent: string): string;
var
  Line: string;
begin
  Result := '';
  for Line in AText.Replace(#13#10, #10).Replace(#13, #10).Split([#10]) do
  begin
    if Trim(Line) <> '' then
    begin
      Result := Result + AIndent + Line + FLineBreak;
    end;
  end;
end;

/// <summary>Rumpf der Abfrage als Zeilen; bei begin … end behalten sie ihre Einrückung.</summary>
function TDerefCheck.BodyText(ABody: TSyntaxNode; const AInner: string): string;
begin
  if ABody.Kind = TSyntaxKind.Block then
  begin
    Result := Source(ABody);
    Result := Reindented(Copy(Result, 6, Length(Result) - 8), '');
  end
  else
  begin
    Result := AInner + Trim(Source(ABody)) + ';' + FLineBreak;
  end;
end;

/// <summary>Prüfung als if ohne else direkt nach dem Zugriff im selben Block: if … then begin Zugriff; Rumpf end.
/// </summary>
function TDerefCheck.MoveCheckFix(AAccess, ACheck: TFlowNode; out AFix: TRuleFix): Boolean;
var
  Access, IfNode, Body, Condition: TSyntaxNode;
  Outer, Inner, Text: string;
begin
  Access := AAccess.Syntax;
  IfNode := ACheck.Syntax;
  Result := (AAccess.Kind = TFlowNodeKind.Statement) and (ACheck.Kind = TFlowNodeKind.Condition) and
    (IfNode.Kind = TSyntaxKind.IfStatement);
  Result := Result and FollowsDirectly(Access, IfNode) and SplitIf(IfNode, Condition, Body) and
    LineIndent(FContext.Text, Access, Outer);
  if not Result then
  begin
    Exit;
  end;
  Inner := Outer + '  ';
  Text := 'if ' + Trim(Source(Condition)) + ' then' + FLineBreak + Outer + 'begin' + FLineBreak +
    Inner + Trim(Source(Access)) + ';' + FLineBreak + BodyText(Body, Inner) + Outer + 'end';
  AFix := TRuleFix.Create('Prüfung vor den Zugriff ziehen',
    [TRuleEdit.Create(TTextRange.Create(Access.StartPos, IfNode.EndPos), Text)]);
end;

procedure TDerefCheck.ReportDeref(ANode, ACheck: TFlowNode; ADeref: TSyntaxNode; const APath: string);
var
  Fix: TRuleFix;
  Fixes: TArray<TRuleFix>;
begin
  Fixes := nil;
  if MoveCheckFix(ANode, ACheck, Fix) then
  begin
    Fixes := [Fix];
  end;
  FReport.Add(NodeRange(ADeref), Format('%s wird hier benutzt, aber erst in Zeile %d auf nil geprüft.',
    [APath, ACheck.Syntax.StartPos.Line + 1]), TRuleConfidence.Medium, Fixes);
end;

procedure TDerefCheck.CheckDeref(ANode: TFlowNode; ADeref: TSyntaxNode);
var
  Path, Key: string;
  Check: TFlowNode;
begin
  Path := FreedPath(ADeref);
  // X := X.Next: die spätere Prüfung gilt dem neuen Wert. Ebenso Supports(Y, IX, X) and X.Foo: die Übergabe im
  // selben Ausdruck setzt X erst.
  if not MatchText(Path, FChecked) or NodeHasNilCheck(ANode, Path) or ChangesPath(ANode, Path, True) then
  begin
    Exit;
  end;
  Check := CheckAfter(ANode, Path, MatchText(Path, FLocals));
  if not GuardsLater(ANode, Check, Path) then
  begin
    Exit;
  end;
  Key := LowerCase(Path) + '@' + IntToStr(Check.Index);
  if MatchText(Key, FDone) or CheckedBefore(ANode, Path) then
  begin
    Exit;
  end;
  FDone := FDone + [Key];
  ReportDeref(ANode, Check, ADeref, Path);
end;

procedure TDerefCheck.CheckNode(ANode: TFlowNode);
var
  Derefs: TArray<TSyntaxNode>;
  Deref, Part: TSyntaxNode;
begin
  if (ANode.Syntax = nil) or not (ANode.Kind in [TFlowNodeKind.Statement, TFlowNodeKind.Condition]) then
  begin
    Exit;
  end;
  Derefs := nil;
  for Part in OwnParts(ANode.Syntax) do
  begin
    CollectDerefs(Part, Derefs);
  end;
  for Deref in Derefs do
  begin
    CheckDeref(ANode, Deref);
  end;
end;

procedure TDerefCheck.CheckRoutine(const ACache: IRuleDerivedCache; ARoutine: TSyntaxNode);
var
  Node: TFlowNode;
begin
  FChecked := CheckedNames(ARoutine);
  if FChecked = nil then
  begin
    Exit;
  end;
  FGraph := TRuleDerived.Graph(ACache, FContext, ARoutine);
  if not FGraph.Complete then
  begin
    Exit;
  end;
  FLocals := LocalNames(ARoutine);
  FDone := nil;
  for Node in FGraph.Nodes do
  begin
    CheckNode(Node);
  end;
end;

procedure TDerefCheck.Run;
var
  Cache: IRuleDerivedCache;
  Routine: TSyntaxNode;
begin
  if FContext.Tree = nil then
  begin
    Exit;
  end;
  Cache := TRuleDerived.Open(FContext);
  for Routine in TRuleDerived.Routines(Cache, FContext) do
  begin
    CheckRoutine(Cache, Routine);
  end;
end;

{ TDerefBeforeNilCheckRule }

function TDerefBeforeNilCheckRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DerefBeforeNilCheckRuleId, TRuleSeverity.Warning,
    'Erst benutzt, dann auf nil geprüft');
end;

procedure TDerefBeforeNilCheckRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TDerefCheck;
begin
  Check := TDerefCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

end.
