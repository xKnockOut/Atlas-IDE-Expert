unit Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil;

// Regel field-free-without-nil aus Atlas.Common.Rules.Builtin.Flow (#269): Ein Feld wird mit X.Free freigegeben,
// und ein Weg erreicht das Ende der Methode, ohne das Feld neu zu setzen. Ausgenommen sind Destruktoren, Methoden
// aus ignoreMethods, DUnitX-Methoden mit [TearDown] und Methoden, die nur aus solchen aufgerufen werden.
// Korrektur: FreeAndNil(X).

interface

uses
  Atlas.Common.Rules.Contract;

type
  TFieldFreeWithoutNilRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Vorgabe der Option ignoreMethods.</summary>
    class function DefaultIgnoreMethods: TArray<string>; static;
  end;

const
  FieldFreeWithoutNilRuleId = 'field-free-without-nil';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFlowFieldFreeWithoutNilText = (StaysSet, Title);

const
  cTexts: array[TFlowFieldFreeWithoutNilText] of TAtlasText = (
    (De: '%s bleibt nach Free gesetzt; ein späterer Zugriff trifft freigegebenen Speicher.';
     En: '%s stays set after Free; a later access hits freed memory.'),
    (De: 'Feld freigegeben, Verweis bleibt stehen'; En: 'Field freed, reference remains'));

{$SCOPEDENUMS OFF}

/// <summary>Methoden der Klassendeklaration AClass mit [TearDown] oder [TearDownFixture] (DUnitX).</summary>
function TearDownMethods(AClass: TSyntaxNode): TArray<string>;

  procedure Visit(E: TSyntaxNode);
  var
    Index: Integer;
    Pending: Boolean;
  begin
    Pending := False;
    for Index := 0 to E.ChildCount - 1 do
    begin
      if E[Index].Kind = TSyntaxKind.Attribute then
      begin
        Pending := Pending or MatchText(E[Index].Name, ['TearDown', 'TearDownFixture']);
      end
      else
      begin
        if Pending and (E[Index].Name <> '') then
        begin
          Result := Result + [E[Index].Name];
        end;
        Pending := False;
        if E[Index].Kind = TSyntaxKind.Visibility then
        begin
          Visit(E[Index]);
        end;
      end;
    end;
  end;

begin
  Result := nil;
  if AClass <> nil then
  begin
    Visit(AClass);
  end;
end;

/// <summary>X.Free bzw. X.Free(); liefert X, sonst nil.</summary>
function FreeTarget(AStatement: TSyntaxNode): TSyntaxNode;
var
  Callee: TSyntaxNode;
begin
  Result := nil;
  if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
  begin
    Exit;
  end;
  Callee := AStatement[0];
  if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount = 1) then
  begin
    Callee := Callee[0];
  end;
  if (Callee.Kind = TSyntaxKind.MemberAccess) and (Callee.ChildCount = 1) and SameText(Callee.Name, 'Free') then
  begin
    Result := Callee[0];
  end;
end;

type
  /// <summary>Prüfung einer Unit für field-free-without-nil; hält die Routinen, die Klasse und den Graphen der
  /// geprüften Methode.</summary>
  TFieldFreeCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FRoutines: TArray<TSyntaxNode>;
    FGraph: TControlFlowGraph;
    FIgnore: TArray<string>;
    FFields: TArray<string>;
    FLocals: TArray<string>;
    FTearDowns: TArray<string>;
    FQualifiedClass: string;
    function Text(ANode: TSyntaxNode): string;
    function Releasing(ARoutine: TSyntaxNode): Boolean;
    function OnlyCalledWhileReleasing(ARoutine: TSyntaxNode): Boolean;
    function AssignerMethod(const AName, APath: string): Boolean;
    function IsAssignerCall(ACallee: TSyntaxNode; const APath: string): Boolean;
    function PartCallsAssigner(ARoot: TSyntaxNode; const APath: string): Boolean;
    function CallsAssigner(ANode: TFlowNode; const APath: string): Boolean;
    function ReachesEnd(AFree: TFlowNode; const APath: string): Boolean;
    procedure CheckStatement(ANode: TFlowNode);
    function PrepareRoutine(ARoutine: TSyntaxNode): Boolean;
    procedure CheckRoutine(const ACache: IRuleDerivedCache; ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TFieldFreeCheck }

constructor TFieldFreeCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

function TFieldFreeCheck.Text(ANode: TSyntaxNode): string;
begin
  Result := SourceText(FContext.Text, ANode);
end;

/// <summary>Destruktor, Methode aus ignoreMethods oder mit [TearDown].</summary>
function TFieldFreeCheck.Releasing(ARoutine: TSyntaxNode): Boolean;
begin
  Result := MatchText(MethodOf(ARoutine), FIgnore) or StartsText('destructor', Trim(Text(ARoutine))) or
    MatchText(MethodOf(ARoutine), FTearDowns);
end;

/// <summary>Wird die Methode nur aus freigebenden Methoden der Klasse aufgerufen (FreeFeatures aus Destroy)?
/// </summary>
function TFieldFreeCheck.OnlyCalledWhileReleasing(ARoutine: TSyntaxNode): Boolean;
var
  Other: TSyntaxNode;
  Callers: Integer;
begin
  Callers := 0;
  Result := True;
  for Other in FRoutines do
  begin
    if Result and (Other <> ARoutine) and CallsMethod(Other, MethodOf(ARoutine)) then
    begin
      Result := StartsText(FQualifiedClass + '.', Other.Name) and Releasing(Other);
      Inc(Callers);
    end;
  end;
  Result := Result and (Callers > 0);
end;

/// <summary>Methode derselben Klasse, die APath zuweist.</summary>
function TFieldFreeCheck.AssignerMethod(const AName, APath: string): Boolean;
var
  Other: TSyntaxNode;
begin
  Result := False;
  for Other in FRoutines do
  begin
    Result := Result or (SameText(Other.Name, FQualifiedClass + '.' + AName) and SubtreeAssigns(Other, APath));
  end;
end;

function TFieldFreeCheck.IsAssignerCall(ACallee: TSyntaxNode; const APath: string): Boolean;
var
  Name: string;
begin
  Name := FreedPath(ACallee);
  Result := (Name <> '') and AssignerMethod(Name, APath);
end;

function TFieldFreeCheck.PartCallsAssigner(ARoot: TSyntaxNode; const APath: string): Boolean;
var
  Path: string;
begin
  Path := APath;
  // Iterativ (Bericht M1).
  Result := ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) and IsAssignerCall(ANode[0], Path) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Ruft der Knoten eine Methode der Klasse auf, die APath neu setzt (Laden; Self.Laden; Laden(…))?
/// </summary>
function TFieldFreeCheck.CallsAssigner(ANode: TFlowNode; const APath: string): Boolean;
var
  Part: TSyntaxNode;
begin
  Result := False;
  if ANode.Syntax = nil then
  begin
    Exit;
  end;
  // Aufruf ohne Klammern: "Laden;" bzw. "Self.Laden;".
  if (ANode.Syntax.Kind = TSyntaxKind.CallStatement) and (ANode.Syntax.ChildCount > 0) then
  begin
    Result := IsAssignerCall(ANode.Syntax[0], APath);
  end;
  for Part in OwnParts(ANode.Syntax) do
  begin
    Result := Result or PartCallsAssigner(Part, APath);
  end;
end;

/// <summary>Erreicht ein Weg vom Free das normale Ende der Methode, ohne das Feld neu zu setzen?</summary>
function TFieldFreeCheck.ReachesEnd(AFree: TFlowNode; const APath: string): Boolean;
var
  Visited: TArray<Boolean>;
  Queue: TArray<TFlowNode>;
  Head: Integer;
  Current: TFlowNode;
begin
  Result := False;
  SetLength(Visited, FGraph.Nodes.Count);
  Queue := nil;
  QueueSuccessors(AFree, Visited, Queue);
  Head := 0;
  while not Result and (Head < Length(Queue)) do
  begin
    Current := Queue[Head];
    Inc(Head);
    if Visited[Current.Index] or (Current = AFree) then
    begin
      Continue;
    end;
    Visited[Current.Index] := True;
    Result := Current = FGraph.ExitNode;
    if not Result and not AssignsPath(Current, APath) and not CallsAssigner(Current, APath) then
    begin
      QueueSuccessors(Current, Visited, Queue);
    end;
  end;
end;

procedure TFieldFreeCheck.CheckStatement(ANode: TFlowNode);
var
  Target: TSyntaxNode;
  Path, Replacement: string;
begin
  Target := FreeTarget(ANode.Syntax);
  Path := FreedPath(Target);
  if (Path = '') or MatchText(Path, FLocals) or not MatchText(Path, FFields) or not ReachesEnd(ANode, Path) then
  begin
    Exit;
  end;
  Replacement := Format('FreeAndNil(%s)', [Text(Target)]);
  FReport.Add(NodeRange(ANode.Syntax), cTexts[TFlowFieldFreeWithoutNilText.StaysSet].Fmt([Path]),
    TRuleConfidence.Medium,
    [TRuleFix.Create(Replacement, [TRuleEdit.Create(NodeRange(ANode.Syntax), Replacement)])]);
end;

/// <summary>Stellt Klasse, Felder und TearDown-Methoden der Methode ARoutine bereit; False, wenn sie nicht zu
/// prüfen ist.</summary>
function TFieldFreeCheck.PrepareRoutine(ARoutine: TSyntaxNode): Boolean;
var
  Dot: Integer;
  ClassType: TSyntaxNode;
begin
  Dot := LastDelimiter('.', ARoutine.Name);
  Result := Dot > 0;
  if not Result then
  begin
    Exit;
  end;
  FQualifiedClass := Copy(ARoutine.Name, 1, Dot - 1);
  ClassType := FindClassType(FContext.Tree.Root, DeclaredClassName(FQualifiedClass));
  FFields := ClassFields(ClassType);
  Result := FFields <> nil;
  if Result then
  begin
    FTearDowns := TearDownMethods(ClassType);
    Result := not Releasing(ARoutine) and not OnlyCalledWhileReleasing(ARoutine);
  end;
end;

procedure TFieldFreeCheck.CheckRoutine(const ACache: IRuleDerivedCache; ARoutine: TSyntaxNode);
var
  Node: TFlowNode;
begin
  if not PrepareRoutine(ARoutine) then
  begin
    Exit;
  end;
  FLocals := LocalNames(ARoutine);
  FGraph := TRuleDerived.Graph(ACache, FContext, ARoutine);
  if not FGraph.Complete then
  begin
    Exit;
  end;
  for Node in FGraph.Nodes do
  begin
    if Node.Kind = TFlowNodeKind.Statement then
    begin
      CheckStatement(Node);
    end;
  end;
end;

procedure TFieldFreeCheck.Run;
var
  Cache: IRuleDerivedCache;
  Routine: TSyntaxNode;
begin
  if FContext.Tree = nil then
  begin
    Exit;
  end;
  FIgnore := TRuleOptions.Strings(FContext.Options, 'ignoreMethods', TFieldFreeWithoutNilRule.DefaultIgnoreMethods);
  Cache := TRuleDerived.Open(FContext);
  FRoutines := TRuleDerived.Routines(Cache, FContext);
  for Routine in FRoutines do
  begin
    CheckRoutine(Cache, Routine);
  end;
end;

{ TFieldFreeWithoutNilRule }

function TFieldFreeWithoutNilRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FieldFreeWithoutNilRuleId, TRuleSeverity.Warning,
    cTexts[TFlowFieldFreeWithoutNilText.Title].Text);
end;

class function TFieldFreeWithoutNilRule.DefaultIgnoreMethods: TArray<string>;
begin
  Result := ['Destroy', 'BeforeDestruction'];
end;

procedure TFieldFreeWithoutNilRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TFieldFreeCheck;
begin
  Check := TFieldFreeCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Flow.FieldFreeWithoutNil', cTexts);

end.
