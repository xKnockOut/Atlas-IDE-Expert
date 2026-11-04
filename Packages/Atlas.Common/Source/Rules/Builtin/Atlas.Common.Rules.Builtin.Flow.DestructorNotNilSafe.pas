unit Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe;

// Regel destructor-not-nil-safe aus Atlas.Common.Rules.Builtin.Flow (#269): Wirft der Konstruktor, ruft Delphi den
// Destruktor mit den Feldern auf, die bis dahin gesetzt sind. Ein Zugriff FFeld.X, FFeld[…] oder FFeld^ im
// Destruktor (oder in einer privaten Methode, die nur er aufruft) auf ein Feld, das dann noch nil sein kann,
// stürzt ab und verdeckt die eigentliche Exception. Assigned(FFeld) und FFeld &lt;&gt; nil davor schützen.
// Korrektur: die Anweisung in if Assigned(FFeld) then einschließen.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TDestructorNotNilSafeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  DestructorNotNilSafeRuleId = 'destructor-not-nil-safe';

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.Constructors;

/// <summary>Methoden in private- und strict-private-Abschnitten der Klassendeklaration.</summary>
function PrivateOf(AClass: TSyntaxNode): TArray<string>;
var
  Index: Integer;
  IsPrivate: Boolean;
begin
  Result := nil;
  if AClass = nil then
  begin
    Exit;
  end;
  IsPrivate := False;
  for Index := 0 to AClass.ChildCount - 1 do
  begin
    if AClass[Index].Kind = TSyntaxKind.Visibility then
    begin
      IsPrivate := MatchText(AClass[Index].Name, ['private', 'strict private']);
    end
    else if IsPrivate and (AClass[Index].Kind = TSyntaxKind.RoutineHeader) and (AClass[Index].Name <> '') then
    begin
      Result := Result + [AClass[Index].Name];
    end;
  end;
end;

/// <summary>Nächste Anweisung über ANode (ANode selbst eingeschlossen); sonst ARoot.</summary>
function EnclosingStatement(ANode, ARoot: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> ARoot) and (Result <> nil) and
    not (Result.Kind in FlowStatementKinds + [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement]) do
  begin
    Result := Result.Parent;
  end;
  if Result = nil then
  begin
    Result := ARoot;
  end;
end;

/// <summary>X.Free und X.DisposeOf greifen nicht zu: beide vertragen nil.</summary>
function IsReleaseCall(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.MemberAccess) and MatchText(ANode.Name, ['Free', 'DisposeOf']);
end;

type
  /// <summary>Prüfung einer Unit für destructor-not-nil-safe; hält die Klasse, die Ergebnisse ihrer Konstruktoren
  /// und die im geprüften Rumpf schon abgefragten Felder.</summary>
  TDestructorCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FRoutines: TArray<TSyntaxNode>;
    FScan: TConstructorScan;
    FPrivateMethods: TArray<string>;
    FQualifiedClass: string;
    FLineBreak: string;
    FChecked: TArray<string>;
    FReported: TArray<string>;
    function Text(ANode: TSyntaxNode): string;
    function OnlyCalledFromDestructor(ARoutine: TSyntaxNode): Boolean;
    function IsReleasing(ARoutine: TSyntaxNode): Boolean;
    function GuardFix(AStatement: TSyntaxNode; const AField: string): TArray<TRuleFix>;
    procedure AddChecked(const AName: string);
    procedure AddAllChecked(const ANames: TArray<string>);
    procedure CollectChecks(ARoot: TSyntaxNode);
    procedure CollectShortCircuit(ANode: TSyntaxNode);
    procedure NoteGuards(ANode: TSyntaxNode);
    procedure ReportAccess(AAccess, AStatement: TSyntaxNode; const AField: string; const AItem: TNilAtDestroy);
    procedure CheckAccess(AAccess, ABody: TSyntaxNode);
    function VisitStep(ANode, ABody: TSyntaxNode): TSyntaxSearchStep;
    procedure CheckBody(ARoutine: TSyntaxNode);
    procedure CheckClass;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

{ TDestructorCheck }

constructor TDestructorCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FLineBreak := LineBreakOf(AContext.Text);
end;

destructor TDestructorCheck.Destroy;
begin
  FScan.Free;
  inherited Destroy;
end;

function TDestructorCheck.Text(ANode: TSyntaxNode): string;
begin
  Result := SourceText(FContext.Text, ANode);
end;

/// <summary>Private Methode der Klasse, die nur aus dem Destruktor aufgerufen wird (FreeAll aus Destroy);
/// öffentliche Methoden rufen auch andere Units.</summary>
function TDestructorCheck.OnlyCalledFromDestructor(ARoutine: TSyntaxNode): Boolean;
var
  Other: TSyntaxNode;
  Callers: Integer;
begin
  Result := MatchText(MethodOf(ARoutine), FPrivateMethods);
  Callers := 0;
  for Other in FRoutines do
  begin
    if Result and (Other <> ARoutine) and CallsMethod(Other, MethodOf(ARoutine)) then
    begin
      Result := SameText(ClassOf(Other), FQualifiedClass) and StartsWithWord(FContext.Text, Other, 'destructor');
      Inc(Callers);
    end;
  end;
  Result := Result and (Callers > 0);
end;

/// <summary>Destruktoren und Methoden, die nur sie aufrufen; BeforeDestruction läuft nach einer Exception im
/// Konstruktor nicht.</summary>
function TDestructorCheck.IsReleasing(ARoutine: TSyntaxNode): Boolean;
begin
  Result := SameText(ClassOf(ARoutine), FQualifiedClass);
  Result := Result and (StartsWithWord(FContext.Text, ARoutine, 'destructor') or
    (not StartsWithWord(FContext.Text, ARoutine, 'constructor') and OnlyCalledFromDestructor(ARoutine)));
end;

/// <summary>Korrektur: "if Assigned(FFeld) then" vor eine Anweisung, die allein in einer Anweisungsliste steht.
/// </summary>
function TDestructorCheck.GuardFix(AStatement: TSyntaxNode; const AField: string): TArray<TRuleFix>;
var
  Outer: string;
begin
  Result := nil;
  if (AStatement.Parent = nil) or (AStatement.Parent.Kind <> TSyntaxKind.Block) or
    (AStatement.StartPos.Line <> AStatement.EndPos.Line) or not LineIndent(FContext.Text, AStatement, Outer) then
  begin
    Exit;
  end;
  Result := [TRuleFix.Create(Format('In if Assigned(%s) then einschließen', [AField]),
    [TRuleEdit.Create(NodeRange(AStatement), Format('if Assigned(%s) then', [AField]) + FLineBreak + Outer +
    '  ' + Trim(Text(AStatement)))])];
end;

/// <summary>X gilt als geprüft, dazu jedes Feld, das jeder Konstruktor vor X setzt.</summary>
procedure TDestructorCheck.AddChecked(const AName: string);
var
  Item: TGuardImplication;
begin
  FChecked := FChecked + [AName];
  for Item in FScan.Implications do
  begin
    if SameText(Item.Guard, AName) then
    begin
      FChecked := FChecked + Item.Implied;
    end;
  end;
end;

procedure TDestructorCheck.AddAllChecked(const ANames: TArray<string>);
var
  Name: string;
begin
  for Name in ANames do
  begin
    AddChecked(Name);
  end;
end;

/// <summary>Assigned(X), X &lt;&gt; nil, X = nil unter ARoot sammeln: danach gilt X als geprüft.</summary>
procedure TDestructorCheck.CollectChecks(ARoot: TSyntaxNode);
begin
  // Iterativ (Bericht M1).
  ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      AddAllChecked(NilCheckedPaths(ANode));
      Result := TSyntaxSearchStep.Descend;
    end);
end;

/// <summary>Linker Teil von "… and …": Assigned(X) und X &lt;&gt; nil schützen den rechten Teil (Kurzschluss,
/// #1109).</summary>
procedure TDestructorCheck.CollectShortCircuit(ANode: TSyntaxNode);
begin
  if (ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1) then
  begin
    CollectShortCircuit(ANode[0]);
  end
  else if (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.ChildCount = 2) and SameText(ANode.Name, 'and') then
  begin
    CollectShortCircuit(ANode[0]);
    CollectShortCircuit(ANode[1]);
  end
  else if (ANode.Kind = TSyntaxKind.Call) or ((ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.Name = '<>')) then
  begin
    AddAllChecked(NilCheckedPaths(ANode));
  end;
end;

/// <summary>Abfragen und Zuweisungen in ANode, die die folgenden Zugriffe schützen.</summary>
procedure TDestructorCheck.NoteGuards(ANode: TSyntaxNode);
var
  Index: Integer;
begin
  // if Assigned(FFeld) then …, while FFeld <> nil do …: die Bedingung schützt alles danach.
  if ANode.Kind in [TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
    TSyntaxKind.CaseStatement] then
  begin
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      if not (ANode[Index].Kind in FlowStatementKinds) then
      begin
        CollectChecks(ANode[Index]);
      end;
    end;
  end;
  if (ANode.Kind = TSyntaxKind.BinaryExpr) and SameText(ANode.Name, 'and') and (ANode.ChildCount = 2) then
  begin
    CollectShortCircuit(ANode[0]);
  end;
  // Neu zugewiesen im Destruktor: der Wert stammt nicht mehr aus dem Konstruktor.
  if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and (FreedPath(ANode[0]) <> '') then
  begin
    FChecked := FChecked + [FreedPath(ANode[0])];
  end;
end;

procedure TDestructorCheck.ReportAccess(AAccess, AStatement: TSyntaxNode; const AField: string;
  const AItem: TNilAtDestroy);
var
  Access, Message: string;
begin
  Access := Trim(Text(AAccess));
  if AItem.Conditional then
  begin
    Message := Format('%s wird im Konstruktor nur bedingt angelegt und kann beim Destruktor nil sein; ' +
      '%s stürzt dann ab.', [AField, Access]);
  end
  else
  begin
    Message := Format('Wirft %s, ist %s beim Destruktor noch nil; %s stürzt ab und verdeckt die ' +
      'eigentliche Exception.', [AItem.Raiser, AField, Access]);
  end;
  FReport.Add(NodeRange(AAccess), Message, TRuleConfidence.High, GuardFix(AStatement, AField));
end;

/// <summary>Zugriff FFeld.X (außer Free und DisposeOf), FFeld[…] oder FFeld^; je Anweisung und Feld ein Befund,
/// damit jede Korrektur ihre Anweisung schützt.</summary>
procedure TDestructorCheck.CheckAccess(AAccess, ABody: TSyntaxNode);
var
  Field, Key: string;
  Item: TNilAtDestroy;
  Statement: TSyntaxNode;
begin
  Field := FreedPath(AAccess[0]);
  if (Field = '') or IsReleaseCall(AAccess) or MatchText(Field, FChecked) or not FScan.RiskOf(Field, Item) then
  begin
    Exit;
  end;
  Statement := EnclosingStatement(AAccess, ABody);
  Key := Field + '@' + IntToStr(Statement.StartOffset);
  if not MatchText(Key, FReported) then
  begin
    FReported := FReported + [Key];
    ReportAccess(AAccess, Statement, Field, Item);
  end;
end;

function TDestructorCheck.VisitStep(ANode, ABody: TSyntaxNode): TSyntaxSearchStep;
begin
  Result := TSyntaxSearchStep.Descend;
  if IsRoutineBody(ANode) then
  begin
    Result := TSyntaxSearchStep.Skip;
    Exit;
  end;
  NoteGuards(ANode);
  if (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess, TSyntaxKind.Dereference]) and
    (ANode.ChildCount > 0) then
  begin
    CheckAccess(ANode, ABody);
  end;
end;

procedure TDestructorCheck.CheckBody(ARoutine: TSyntaxNode);
var
  Body: TSyntaxNode;
begin
  Body := ARoutine.FindChild(TSyntaxKind.Block);
  if Body = nil then
  begin
    Exit;
  end;
  FChecked := nil;
  FReported := nil;
  // Iterativ (Bericht M1): Vorordnung wie die Rekursion, FChecked wächst in derselben Reihenfolge.
  Body.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := VisitStep(ANode, Body);
    end);
end;

procedure TDestructorCheck.CheckClass;
var
  ClassType, Other: TSyntaxNode;
  Fields: TArray<string>;
begin
  ClassType := FindClassType(FContext.Tree.Root, DeclaredClassName(FQualifiedClass));
  Fields := ClassFields(ClassType);
  if Fields = nil then
  begin
    Exit;
  end;
  FPrivateMethods := PrivateOf(ClassType);
  FScan.Start(Fields);
  for Other in FRoutines do
  begin
    if SameText(ClassOf(Other), FQualifiedClass) and StartsWithWord(FContext.Text, Other, 'constructor') then
    begin
      FScan.Scan(Other);
    end;
  end;
  if FScan.Risky = nil then
  begin
    Exit;
  end;
  for Other in FRoutines do
  begin
    if IsReleasing(Other) then
    begin
      CheckBody(Other);
    end;
  end;
end;

procedure TDestructorCheck.Run;
var
  Routine: TSyntaxNode;
  Classes: TArray<string>;
begin
  if (FContext.Tree = nil) or not ContainsText(FContext.Text, 'destructor') then
  begin
    Exit;
  end;
  FRoutines := TRuleDerived.Routines(TRuleDerived.Open(FContext), FContext);
  FScan := TConstructorScan.Create(FContext.Text, FContext.Tree.Root, FRoutines,
    TRuleOptions.Bool(FContext.Options, 'onlyAfterRaisingCode', True));
  Classes := nil;
  for Routine in FRoutines do
  begin
    FQualifiedClass := ClassOf(Routine);
    if (FQualifiedClass <> '') and not MatchText(FQualifiedClass, Classes) and
      StartsWithWord(FContext.Text, Routine, 'destructor') then
    begin
      Classes := Classes + [FQualifiedClass];
      CheckClass;
    end;
  end;
end;

{ TDestructorNotNilSafeRule }

function TDestructorNotNilSafeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(DestructorNotNilSafeRuleId, TRuleSeverity.Warning,
    'Destruktor benutzt ein Feld, das nach einer Exception im Konstruktor nil ist');
end;

procedure TDestructorNotNilSafeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TDestructorCheck;
begin
  Check := TDestructorCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

end.
