unit Atlas.Common.Metrics.Calculator;

// Kennzahlen je Routine aus dem Syntaxbaum (#66); Zählweise siehe
// Atlas.Common.Metrics.Contract. Gemessen wird jede Routine mit Rumpf
// (begin … end), auch lokale Routinen; Routinen mit asm-Rumpf und forward-
// bzw. external-Deklarationen nicht. Anonyme Methoden gehören zur Routine, in
// der sie stehen (kognitiv eine Ebene tiefer).
//
// Einzelheiten:
//   - else erkennt der Calculator auch ohne then-Zweig (if A then else B)
//     am Schlüsselwort vor dem Zweig.
//   - and/or zählen nur in Bedingungen (if, while, until, Bedingungsausdruck):
//     dort sind sie logisch; anderswo können sie bitweise sein.
//   - Rekursion erhöht die kognitive Komplexität nicht (dafür bräuchte es
//     die Namensauflösung).
//   - Implementierungen ohne Parameterliste (procedure TFoo.Bar;) nehmen die
//     Parameter der Deklaration in derselben Datei.
// Der Baum wird iterativ durchlaufen: Lange Ausdrucksketten ergeben sehr
// tiefe Bäume. Structure liefert die Kennzahlen des Aufbaus (#939): Member je
// Klasse, Zeilen der Unit und Units im uses. Conditions liefert die
// Bedingungen mit ihren Operanden für metric-boolean-operands (#980).

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Metrics.Contract;

type
  TMetricsCalculator = class
  public
    /// <summary>Kennzahlen aller Routinen mit Rumpf in ATree, nach Position im Quelltext.</summary>
    class function Routines(ATree: TSyntaxTree): TArray<TRoutineMetrics>; static;
    /// <summary>Parst AText und liefert die Kennzahlen seiner Routinen.</summary>
    class function ForText(const AText: string): TArray<TRoutineMetrics>; static;
    /// <summary>Codezeilen von ARoutine (RoutineDecl) ohne Leerzeilen, Kommentare, Direktiven und lokale
    /// Routinen.</summary>
    class function CodeLines(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer; static;
    /// <summary>Verschachtelungstiefe von ARoutine (RoutineDecl); 0 ohne Kontrollstruktur.</summary>
    class function NestingDepth(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer; static;
    /// <summary>Zyklomatische Komplexität von ARoutine (RoutineDecl); mindestens 1.</summary>
    class function Cyclomatic(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer; static;
    /// <summary>Kognitive Komplexität von ARoutine (RoutineDecl).</summary>
    class function Cognitive(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer; static;
    /// <summary>Parameternamen in der Liste von AHeader (RoutineHeader); 0 ohne Liste.</summary>
    class function ParameterCount(AHeader: TSyntaxNode): Integer; static;
    /// <summary>Kennzahlen des Aufbaus (#939): je Klasse die Member, dazu Zeilen und uses-Anzahl der Unit;
    /// nach Position im Quelltext, die Unit zuerst.</summary>
    class function Structure(ATree: TSyntaxTree): TArray<TStructureMetrics>; static;
    /// <summary>Parst AText und liefert die Kennzahlen seines Aufbaus.</summary>
    class function StructureForText(const AText: string): TArray<TStructureMetrics>; static;
    /// <summary>Member einer Klasse (ClassType, ObjectType), Zählweise siehe Metrics.Contract.</summary>
    class function MemberCount(AClass: TSyntaxNode): Integer; static;
    /// <summary>Bedingungen in den Rümpfen aller Routinen mit ihren Operanden (#980), nach Position.</summary>
    class function Conditions(ATree: TSyntaxTree): TArray<TConditionMetrics>; static;
    /// <summary>Glieder der and/or/xor-Kette in AExpression, durch Klammern und not hindurch; mindestens 1.
    /// </summary>
    class function Operands(AExpression: TSyntaxNode): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.RoutineLocals;

const
  ExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.AddressOf, TSyntaxKind.GenericArgs,
    TSyntaxKind.SetConstructor, TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr,
    TSyntaxKind.InheritedExpr, TSyntaxKind.RangeExpr, TSyntaxKind.IfExpr];
  LoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
  TypeBodyKinds = [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
    TSyntaxKind.InterfaceType, TSyntaxKind.HelperType];

type
  /// <summary>Ein Knoten auf dem Stapel des Durchlaufs.</summary>
  TVisit = record
    Node: TSyntaxNode;
    /// <summary>Zahl der umgebenden Kontrollstrukturen (Verschachtelungstiefe).</summary>
    Depth: Integer;
    /// <summary>Schachtelungsebene der kognitiven Komplexität.</summary>
    Level: Integer;
    /// <summary>Der Knoten steht in einer Bedingung.</summary>
    Condition: Boolean;
    /// <summary>Der Knoten ist der else-Zweig eines if und selbst ein if (else if).</summary>
    ElseIf: Boolean;
    /// <summary>Der Knoten steht in einer anonymen Methode: Exit, raise und Variablen gehören zu ihr (#980).
    /// </summary>
    Anonymous: Boolean;
  end;

  /// <summary>Ergebnis eines Durchlaufs über den Rumpf einer Routine.</summary>
  TFlow = record
    Depth: Integer;
    Cyclomatic: Integer;
    Cognitive: Integer;
    /// <summary>Operanden der größten Bedingung, Inline- und for-Variablen, Exit und raise (#980).</summary>
    Operands: Integer;
    InlineLocals: Integer;
    Exits: Integer;
  end;

function Visit(ANode: TSyntaxNode; ADepth, ALevel: Integer; ACondition, AElseIf: Boolean): TVisit;
begin
  Result.Node := ANode;
  Result.Depth := ADepth;
  Result.Level := ALevel;
  Result.Condition := ACondition;
  Result.ElseIf := AElseIf;
  Result.Anonymous := False;
end;

/// <summary>Index des ersten Tokens mit Offset ab AOffset.</summary>
function FirstTokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Left, Right, Middle: Integer;
begin
  Left := 0;
  Right := Length(ATokens);
  while Left < Right do
  begin
    Middle := (Left + Right) div 2;
    if ATokens[Middle].Offset < AOffset then
    begin
      Left := Middle + 1;
    end
    else
    begin
      Right := Middle;
    end;
  end;
  Result := Left;
end;

/// <summary>Steht vor ANode (ohne Kommentare und Direktiven) das Schlüsselwort else?</summary>
function AfterElse(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := FirstTokenAt(ATokens, ANode.StartOffset) - 1;
  while (Index >= 0) and ((ATokens[Index].Kind = TPascalTokenKind.Comment) or
    (ATokens[Index].Kind = TPascalTokenKind.Directive)) do
  begin
    Dec(Index);
  end;
  Result := (Index >= 0) and ATokens[Index].IsKeyword('else');
end;

/// <summary>else-Zweig eines if; nil ohne.</summary>
function ElseBranch(const ATokens: TArray<TPascalToken>; AIf: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if AIf.ChildCount >= 3 then
  begin
    Result := AIf[2];
  end
  else if (AIf.ChildCount = 2) and AfterElse(ATokens, AIf[1]) then
  begin
    Result := AIf[1];
  end;
end;

function IsLogical(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.BinaryExpr) and (SameText(ANode.Name, 'and') or SameText(ANode.Name, 'or'));
end;

/// <summary>Setzt ANode (and/or) eine Folge desselben Operators fort? Klammern zählen nicht.</summary>
function ContinuesSequence(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Parent := ANode.Parent;
  while (Parent <> nil) and (Parent.Kind = TSyntaxKind.ParenExpr) do
  begin
    Parent := Parent.Parent;
  end;
  Result := (Parent <> nil) and (Parent.Kind = TSyntaxKind.BinaryExpr) and SameText(Parent.Name, ANode.Name);
end;

function NameCount(const ANames: string): Integer;
var
  Position: Integer;
begin
  Result := 0;
  if Trim(ANames) = '' then
  begin
    Exit;
  end;
  Result := 1;
  for Position := 1 to Length(ANames) do
  begin
    if ANames[Position] = ',' then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Exit bzw. Exit(Wert) als Anweisung.</summary>
function IsExitCall(ANode: TSyntaxNode): Boolean;
var
  Target: TSyntaxNode;
begin
  Result := False;
  if (ANode.Kind <> TSyntaxKind.CallStatement) or (ANode.ChildCount = 0) then
  begin
    Exit;
  end;
  Target := ANode[0];
  if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
  begin
    Target := Target[0];
  end;
  Result := (Target.Kind = TSyntaxKind.Identifier) and SameText(Target.Name, 'Exit');
end;

function BodyOf(ARoutine: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  Result := nil;
  if ARoutine = nil then
  begin
    Exit;
  end;
  for Index := ARoutine.ChildCount - 1 downto 0 do
  begin
    if ARoutine[Index].Kind = TSyntaxKind.Block then
    begin
      Exit(ARoutine[Index]);
    end;
  end;
end;

type
  /// <summary>Ein Durchlauf über den Rumpf einer Routine (AnalyzeWith).</summary>
  TFlowAnalyzer = class
  private
    FTokens: TArray<TPascalToken>;
    FStack: TStack<TVisit>;
    FConditions: TList<TSyntaxNode>;
    FFlow: TFlow;
    /// <summary>Der gerade besuchte Knoten steht in einer anonymen Methode.</summary>
    FAnonymous: Boolean;
    procedure PushVisit(AVisit: TVisit);
    procedure Push(AChild: TSyntaxNode; ADepth, ALevel: Integer; ACondition: Boolean);
    /// <summary>Wurzel einer Bedingung (if, while, until, Bedingungsausdruck).</summary>
    procedure PushCondition(AChild: TSyntaxNode; ADepth, ALevel: Integer);
    procedure Reach(ADepth: Integer);
    procedure PushIfChild(const AItem: TVisit; AChild, ABranch: TSyntaxNode);
    procedure VisitIf(const AItem: TVisit);
    procedure VisitIfExpr(const AItem: TVisit);
    procedure VisitCase(const AItem: TVisit);
    procedure VisitTry(const AItem: TVisit);
    procedure VisitExcept(const AItem: TVisit);
    procedure VisitHandler(const AItem: TVisit);
    procedure VisitAnonymous(const AItem: TVisit);
    procedure VisitLoop(const AItem: TVisit);
    /// <summary>Zählt Knoten ohne eigene Ebene (Exit, raise, Inline-Variablen, case-Zweige, goto, and/or).
    /// </summary>
    procedure CountSimple(const AItem: TVisit);
    /// <summary>Reicht Tiefe und Ebene an die Kinder weiter; die Bedingung nur innerhalb von Ausdrücken.
    /// </summary>
    procedure VisitOther(const AItem: TVisit);
    procedure VisitNode(const AItem: TVisit);
  public
    constructor Create(ATree: TSyntaxTree; AConditions: TList<TSyntaxNode>);
    destructor Destroy; override;
    function Run(ABody: TSyntaxNode): TFlow;
  end;

constructor TFlowAnalyzer.Create(ATree: TSyntaxTree; AConditions: TList<TSyntaxNode>);
begin
  inherited Create;
  FTokens := ATree.Tokens;
  FConditions := AConditions;
  FStack := TStack<TVisit>.Create;
end;

destructor TFlowAnalyzer.Destroy;
begin
  FStack.Free;
  inherited;
end;

procedure TFlowAnalyzer.PushVisit(AVisit: TVisit);
begin
  AVisit.Anonymous := FAnonymous;
  FStack.Push(AVisit);
end;

procedure TFlowAnalyzer.Push(AChild: TSyntaxNode; ADepth, ALevel: Integer; ACondition: Boolean);
begin
  PushVisit(Visit(AChild, ADepth, ALevel, ACondition, False));
end;

procedure TFlowAnalyzer.PushCondition(AChild: TSyntaxNode; ADepth, ALevel: Integer);
var
  mCount: Integer;
begin
  if AChild.Kind in ExpressionKinds then
  begin
    mCount := TMetricsCalculator.Operands(AChild);
    if mCount > FFlow.Operands then
    begin
      FFlow.Operands := mCount;
    end;
    if FConditions <> nil then
    begin
      FConditions.Add(AChild);
    end;
  end;
  Push(AChild, ADepth, ALevel, True);
end;

procedure TFlowAnalyzer.Reach(ADepth: Integer);
begin
  if ADepth > FFlow.Depth then
  begin
    FFlow.Depth := ADepth;
  end;
end;

procedure TFlowAnalyzer.PushIfChild(const AItem: TVisit; AChild, ABranch: TSyntaxNode);
begin
  if AChild <> ABranch then
  begin
    Push(AChild, AItem.Depth + 1, AItem.Level + 1, False);
  end
  else if ABranch.Kind = TSyntaxKind.IfStatement then
  begin
    // else if: gleiche Ebene wie das if, +1 beim inneren if.
    PushVisit(Visit(ABranch, AItem.Depth, AItem.Level, False, True));
  end
  else
  begin
    Inc(FFlow.Cognitive);
    Push(ABranch, AItem.Depth + 1, AItem.Level + 1, False);
  end;
end;

procedure TFlowAnalyzer.VisitIf(const AItem: TVisit);
var
  mIndex: Integer;
  mBranch: TSyntaxNode;
begin
  Inc(FFlow.Cyclomatic);
  Reach(AItem.Depth + 1);
  if AItem.ElseIf then
  begin
    Inc(FFlow.Cognitive);
  end
  else
  begin
    Inc(FFlow.Cognitive, 1 + AItem.Level);
  end;
  mBranch := ElseBranch(FTokens, AItem.Node);
  for mIndex := 0 to AItem.Node.ChildCount - 1 do
  begin
    if mIndex = 0 then
    begin
      PushCondition(AItem.Node[mIndex], AItem.Depth, AItem.Level);
    end
    else
    begin
      PushIfChild(AItem, AItem.Node[mIndex], mBranch);
    end;
  end;
end;

procedure TFlowAnalyzer.VisitIfExpr(const AItem: TVisit);
var
  mIndex: Integer;
begin
  Inc(FFlow.Cyclomatic);
  Inc(FFlow.Cognitive, 1 + AItem.Level);
  for mIndex := 0 to AItem.Node.ChildCount - 1 do
  begin
    if mIndex = 0 then
    begin
      PushCondition(AItem.Node[mIndex], AItem.Depth, AItem.Level);
    end
    else
    begin
      Push(AItem.Node[mIndex], AItem.Depth, AItem.Level + 1, False);
    end;
  end;
end;

procedure TFlowAnalyzer.VisitCase(const AItem: TVisit);
var
  mIndex: Integer;
begin
  Reach(AItem.Depth + 1);
  Inc(FFlow.Cognitive, 1 + AItem.Level);
  for mIndex := 0 to AItem.Node.ChildCount - 1 do
  begin
    if mIndex = 0 then
    begin
      Push(AItem.Node[mIndex], AItem.Depth, AItem.Level, False);
    end
    else
    begin
      Push(AItem.Node[mIndex], AItem.Depth + 1, AItem.Level + 1, False);
    end;
  end;
end;

procedure TFlowAnalyzer.VisitTry(const AItem: TVisit);
var
  mIndex: Integer;
begin
  // Nur die Tiefe; kognitiv zählt erst der except-Teil.
  Reach(AItem.Depth + 1);
  for mIndex := 0 to AItem.Node.ChildCount - 1 do
  begin
    Push(AItem.Node[mIndex], AItem.Depth + 1, AItem.Level, False);
  end;
end;

procedure TFlowAnalyzer.VisitExcept(const AItem: TVisit);
var
  mIndex, mHandlers: Integer;
begin
  mHandlers := 0;
  for mIndex := 0 to AItem.Node.ChildCount - 1 do
  begin
    if AItem.Node[mIndex].Kind = TSyntaxKind.ExceptionHandler then
    begin
      Inc(mHandlers);
      Push(AItem.Node[mIndex], AItem.Depth, AItem.Level, False);
    end
    else
    begin
      Push(AItem.Node[mIndex], AItem.Depth, AItem.Level + 1, False);
    end;
  end;
  if mHandlers = 0 then
  begin
    Inc(FFlow.Cyclomatic);
    Inc(FFlow.Cognitive, 1 + AItem.Level);
  end;
end;

procedure TFlowAnalyzer.VisitHandler(const AItem: TVisit);
var
  mIndex: Integer;
begin
  Inc(FFlow.Cyclomatic);
  Inc(FFlow.Cognitive, 1 + AItem.Level);
  for mIndex := 0 to AItem.Node.ChildCount - 1 do
  begin
    Push(AItem.Node[mIndex], AItem.Depth, AItem.Level + 1, False);
  end;
end;

procedure TFlowAnalyzer.VisitAnonymous(const AItem: TVisit);
var
  mIndex: Integer;
begin
  FAnonymous := True;
  for mIndex := 0 to AItem.Node.ChildCount - 1 do
  begin
    Push(AItem.Node[mIndex], AItem.Depth, AItem.Level + 1, False);
  end;
end;

/// <summary>Kind AIndex der Schleife ANode ist ihre Bedingung (while am Anfang, until am Ende).</summary>
function IsLoopCondition(ANode: TSyntaxNode; AIndex: Integer): Boolean;
begin
  Result := ((ANode.Kind = TSyntaxKind.WhileStatement) and (AIndex = 0)) or
    ((ANode.Kind = TSyntaxKind.RepeatStatement) and (AIndex = ANode.ChildCount - 1) and
    (ANode[AIndex].Kind in ExpressionKinds));
end;

procedure TFlowAnalyzer.VisitLoop(const AItem: TVisit);
var
  mIndex: Integer;
begin
  if not FAnonymous and (AItem.Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and
    TRoutineLocals.IsInlineFor(FTokens, AItem.Node) then
  begin
    Inc(FFlow.InlineLocals);
  end;
  Inc(FFlow.Cyclomatic);
  Reach(AItem.Depth + 1);
  Inc(FFlow.Cognitive, 1 + AItem.Level);
  for mIndex := 0 to AItem.Node.ChildCount - 1 do
  begin
    if IsLoopCondition(AItem.Node, mIndex) then
    begin
      PushCondition(AItem.Node[mIndex], AItem.Depth, AItem.Level);
    end
    else
    begin
      Push(AItem.Node[mIndex], AItem.Depth + 1, AItem.Level + 1, False);
    end;
  end;
end;

procedure TFlowAnalyzer.CountSimple(const AItem: TVisit);
begin
  case AItem.Node.Kind of
    TSyntaxKind.CallStatement:
      if not FAnonymous and IsExitCall(AItem.Node) then
      begin
        Inc(FFlow.Exits);
      end;
    TSyntaxKind.RaiseStatement:
      if not FAnonymous then
      begin
        Inc(FFlow.Exits);
      end;
    TSyntaxKind.InlineVar:
      if not FAnonymous then
      begin
        Inc(FFlow.InlineLocals, NameCount(AItem.Node.Name));
      end;
    TSyntaxKind.CaseItem:
      Inc(FFlow.Cyclomatic);
    TSyntaxKind.GotoStatement:
      Inc(FFlow.Cognitive);
    TSyntaxKind.BinaryExpr:
      if AItem.Condition and IsLogical(AItem.Node) then
      begin
        Inc(FFlow.Cyclomatic);
        if not ContinuesSequence(AItem.Node) then
        begin
          Inc(FFlow.Cognitive);
        end;
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TFlowAnalyzer.VisitOther(const AItem: TVisit);
var
  mIndex: Integer;
  mInner: Boolean;
begin
  CountSimple(AItem);
  mInner := AItem.Condition and (AItem.Node.Kind in ExpressionKinds);
  for mIndex := 0 to AItem.Node.ChildCount - 1 do
  begin
    Push(AItem.Node[mIndex], AItem.Depth, AItem.Level, mInner);
  end;
end;

procedure TFlowAnalyzer.VisitNode(const AItem: TVisit);
begin
  case AItem.Node.Kind of
    TSyntaxKind.RoutineDecl:
      ; // Lokale Routinen zählen für sich.
    TSyntaxKind.IfStatement:
      VisitIf(AItem);
    TSyntaxKind.IfExpr:
      VisitIfExpr(AItem);
    TSyntaxKind.CaseStatement:
      VisitCase(AItem);
    TSyntaxKind.TryStatement:
      VisitTry(AItem);
    TSyntaxKind.ExceptBlock:
      VisitExcept(AItem);
    TSyntaxKind.ExceptionHandler:
      VisitHandler(AItem);
    TSyntaxKind.AnonymousMethod:
      VisitAnonymous(AItem);
  else
    if AItem.Node.Kind in LoopKinds then
    begin
      VisitLoop(AItem);
    end
    else
    begin
      VisitOther(AItem);
    end;
  end;
end;

function TFlowAnalyzer.Run(ABody: TSyntaxNode): TFlow;
var
  mItem: TVisit;
begin
  FFlow := Default(TFlow);
  FFlow.Cyclomatic := 1;
  FAnonymous := False;
  if ABody <> nil then
  begin
    Push(ABody, 0, 0, False);
  end;
  while FStack.Count > 0 do
  begin
    mItem := FStack.Pop;
    FAnonymous := mItem.Anonymous;
    VisitNode(mItem);
  end;
  Result := FFlow;
end;

/// <summary>Ein Durchlauf über den Rumpf: Tiefe, zyklomatische und kognitive Komplexität, Operanden, Inline-
/// Variablen und Ausstiege; AConditions (oder nil) sammelt die Bedingungen.</summary>
function AnalyzeWith(ATree: TSyntaxTree; ARoutine: TSyntaxNode; AConditions: TList<TSyntaxNode>): TFlow;
var
  mAnalyzer: TFlowAnalyzer;
begin
  mAnalyzer := TFlowAnalyzer.Create(ATree, AConditions);
  try
    Result := mAnalyzer.Run(BodyOf(ARoutine));
  finally
    mAnalyzer.Free;
  end;
end;

function Analyze(ATree: TSyntaxTree; ARoutine: TSyntaxNode): TFlow;
begin
  Result := AnalyzeWith(ATree, ARoutine, nil);
end;

/// <summary>Namen im var-Abschnitt von ARoutine (nicht in lokalen Routinen).</summary>
function DeclaredLocals(ARoutine: TSyntaxNode): Integer;
var
  Index, Inner: Integer;
  Section: TSyntaxNode;
begin
  Result := 0;
  for Index := 0 to ARoutine.ChildCount - 1 do
  begin
    Section := ARoutine[Index];
    if Section.Kind = TSyntaxKind.VarSection then
    begin
      for Inner := 0 to Section.ChildCount - 1 do
      begin
        if Section[Inner].Kind = TSyntaxKind.VarDecl then
        begin
          Inc(Result, NameCount(Section[Inner].Name));
        end;
      end;
    end;
  end;
end;

/// <summary>Legt die lokalen Routinen von ARoutine auf AStack, die erste zuoberst.</summary>
procedure PushLocalRoutines(AStack: TStack<TSyntaxNode>; ARoutine: TSyntaxNode);
var
  mIndex: Integer;
begin
  for mIndex := ARoutine.ChildCount - 1 downto 0 do
  begin
    if ARoutine[mIndex].Kind = TSyntaxKind.RoutineDecl then
    begin
      AStack.Push(ARoutine[mIndex]);
    end;
  end;
end;

/// <summary>Routinen mit Rumpf in ATree, auch lokale, in der Reihenfolge des Durchlaufs.</summary>
function FindRoutines(ATree: TSyntaxTree): TArray<TSyntaxNode>;
var
  mStack: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mStack := TStack<TSyntaxNode>.Create;
  try
    mStack.Push(ATree.Root);
    while mStack.Count > 0 do
    begin
      mNode := mStack.Pop;
      if (mNode.Kind = TSyntaxKind.RoutineDecl) and (BodyOf(mNode) <> nil) then
      begin
        Result := Result + [mNode];
      end;
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        // Lokale Routinen stehen als Kinder darin.
        PushLocalRoutines(mStack, mNode);
      end
      else if not (mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] + ExpressionKinds) then
      begin
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mStack.Push(mNode[mIndex]);
        end;
      end;
    end;
  finally
    mStack.Free;
  end;
end;

/// <summary>Qualifizierter Name der Typen um ANode, z. B. "TFoo.TInner"; '' außerhalb von Typen.</summary>
function OwnerName(ANode: TSyntaxNode): string;
var
  Parent: TSyntaxNode;
begin
  Result := '';
  Parent := ANode.Parent;
  while Parent <> nil do
  begin
    if (Parent.Kind = TSyntaxKind.TypeDecl) and (Result = '') then
    begin
      Result := Parent.Name;
    end
    else if Parent.Kind = TSyntaxKind.TypeDecl then
    begin
      Result := Parent.Name + '.' + Result;
    end;
    Parent := Parent.Parent;
  end;
end;

/// <summary>Parameterzahl der Deklarationen in Typen: Großbuchstaben-Name → Zahl, -1 bei Überladungen.</summary>
function Declarations(ATree: TSyntaxTree): TDictionary<string, Integer>;
var
  Stack: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index, Count: Integer;
  Key: string;
begin
  Result := TDictionary<string, Integer>.Create;
  Stack := TStack<TSyntaxNode>.Create;
  try
    Stack.Push(ATree.Root);
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      if (Node.Kind = TSyntaxKind.RoutineHeader) and (Node.Parent <> nil) and (Node.Parent.Kind in TypeBodyKinds) then
      begin
        Key := UpperCase(OwnerName(Node) + '.' + Node.Name);
        Count := TMetricsCalculator.ParameterCount(Node);
        if Result.ContainsKey(Key) then
        begin
          Result[Key] := -1;
        end
        else
        begin
          Result.Add(Key, Count);
        end;
        Continue;
      end;
      // Rümpfe enthalten keine Typdeklarationen mit Methoden, die hier fehlen würden.
      if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] then
      begin
        Continue;
      end;
      for Index := 0 to Node.ChildCount - 1 do
      begin
        Stack.Push(Node[Index]);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

/// <summary>Index hinter den generischen Parametern "&lt;…&gt;", die an AIndex beginnen.</summary>
function SkipGenericArgs(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
var
  mDepth: Integer;
begin
  Result := AIndex;
  mDepth := 0;
  while Result < Length(ATokens) do
  begin
    if ATokens[Result].IsSymbol('<') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol('>') then
    begin
      Dec(mDepth);
    end
    else if ATokens[Result].IsSymbol('>>') then
    begin
      Dec(mDepth, 2);
    end;
    if (mDepth <= 0) and (ATokens[Result].IsSymbol('>') or ATokens[Result].IsSymbol('>>')) then
    begin
      Break;
    end;
    Inc(Result);
  end;
  Inc(Result);
end;

/// <summary>Erster Bezeichner im Kopf AHeader; -1 ohne.</summary>
function FirstIdentifier(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): Integer;
begin
  Result := FirstTokenAt(ATokens, AHeader.StartOffset);
  while (Result < Length(ATokens)) and (ATokens[Result].Offset < AHeader.EndOffset) and
    (ATokens[Result].Kind <> TPascalTokenKind.Identifier) do
  begin
    Inc(Result);
  end;
  if (Result >= Length(ATokens)) or (ATokens[Result].Offset >= AHeader.EndOffset) then
  begin
    Result := -1;
  end;
end;

/// <summary>Bereich des Namens im Kopf: Bezeichner mit Punkten, generische Parameter übersprungen.</summary>
function NameRangeOf(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TTextRange;
var
  mIndex, mFirst, mLast: Integer;
  mDone: Boolean;
begin
  mFirst := FirstIdentifier(ATokens, AHeader);
  if mFirst < 0 then
  begin
    Exit(TTextRange.Create(AHeader.StartPos, AHeader.StartPos));
  end;
  mLast := mFirst;
  mIndex := mFirst + 1;
  mDone := False;
  while not mDone and (mIndex < Length(ATokens)) do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Comment) or (ATokens[mIndex].Kind = TPascalTokenKind.Directive) then
    begin
      Inc(mIndex);
    end
    else if ATokens[mIndex].IsSymbol('<') then
    begin
      // TFoo<T>.Bar: bis zur passenden spitzen Klammer.
      mIndex := SkipGenericArgs(ATokens, mIndex);
    end
    else if ATokens[mIndex].IsSymbol('.') and (mIndex + 1 < Length(ATokens)) and
      (ATokens[mIndex + 1].Kind = TPascalTokenKind.Identifier) then
    begin
      mLast := mIndex + 1;
      Inc(mIndex, 2);
    end
    else
    begin
      mDone := True;
    end;
  end;
  Result := TTextRange.Create(ATokens[mFirst].StartPos, ATokens[mLast].EndPos);
end;

{ TMetricsCalculator }

class function TMetricsCalculator.ParameterCount(AHeader: TSyntaxNode): Integer;
var
  Parameters, Parameter: TSyntaxNode;
  Index, Position: Integer;
  Names: string;
begin
  Result := 0;
  if AHeader = nil then
  begin
    Exit;
  end;
  Parameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if Parameters = nil then
  begin
    Exit;
  end;
  for Index := 0 to Parameters.ChildCount - 1 do
  begin
    Parameter := Parameters[Index];
    if Parameter.Kind <> TSyntaxKind.Parameter then
    begin
      Continue;
    end;
    Names := Trim(Parameter.Name);
    if Names = '' then
    begin
      Continue;
    end;
    Inc(Result);
    for Position := 1 to Length(Names) do
    begin
      if Names[Position] = ',' then
      begin
        Inc(Result);
      end;
    end;
  end;
end;

/// <summary>Lokale Routinen von ARoutine.</summary>
function LocalRoutinesOf(ARoutine: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if ARoutine[mIndex].Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := Result + [ARoutine[mIndex]];
    end;
  end;
end;

/// <summary>AToken zählt als Code der Routine: kein Kommentar, keine Direktive, nicht in einer der ASkips.
/// </summary>
function IsOwnCode(const AToken: TPascalToken; const ASkips: TArray<TSyntaxNode>): Boolean;
var
  mSkip: TSyntaxNode;
begin
  Result := (AToken.Kind <> TPascalTokenKind.Comment) and (AToken.Kind <> TPascalTokenKind.Directive);
  for mSkip in ASkips do
  begin
    if (AToken.Offset >= mSkip.StartOffset) and (AToken.Offset < mSkip.EndOffset) then
    begin
      Result := False;
    end;
  end;
end;

class function TMetricsCalculator.CodeLines(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer;
var
  mTokens: TArray<TPascalToken>;
  mLines: TDictionary<Integer, Boolean>;
  mSkips: TArray<TSyntaxNode>;
  mIndex, mLine: Integer;
begin
  Result := 0;
  if ARoutine = nil then
  begin
    Exit;
  end;
  mTokens := ATree.Tokens;
  mSkips := LocalRoutinesOf(ARoutine);
  mLines := TDictionary<Integer, Boolean>.Create;
  try
    mIndex := FirstTokenAt(mTokens, ARoutine.StartOffset);
    while (mIndex < Length(mTokens)) and (mTokens[mIndex].Offset < ARoutine.EndOffset) do
    begin
      if IsOwnCode(mTokens[mIndex], mSkips) then
      begin
        for mLine := mTokens[mIndex].StartPos.Line to mTokens[mIndex].EndPos.Line do
        begin
          mLines.AddOrSetValue(mLine, True);
        end;
      end;
      Inc(mIndex);
    end;
    Result := mLines.Count;
  finally
    mLines.Free;
  end;
end;

class function TMetricsCalculator.NestingDepth(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer;
begin
  Result := Analyze(ATree, ARoutine).Depth;
end;

class function TMetricsCalculator.Cyclomatic(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer;
begin
  Result := Analyze(ATree, ARoutine).Cyclomatic;
end;

class function TMetricsCalculator.Cognitive(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer;
begin
  Result := Analyze(ATree, ARoutine).Cognitive;
end;

/// <summary>Name von ARoutine mit den Namen der umgebenden Routinen davor ("Außen.Innen").</summary>
function QualifiedRoutineName(ARoutine: TSyntaxNode): string;
var
  mParent: TSyntaxNode;
begin
  Result := ARoutine.Name;
  mParent := ARoutine.Parent;
  while mParent <> nil do
  begin
    if mParent.Kind = TSyntaxKind.RoutineDecl then
    begin
      Result := mParent.Name + '.' + Result;
    end;
    mParent := mParent.Parent;
  end;
end;

/// <summary>Parameterzahl von ARoutine; ohne Liste (procedure TFoo.Bar;) die der Deklaration. AKnown wird bei
/// Bedarf einmal angelegt.</summary>
function RoutineParameters(ATree: TSyntaxTree; ARoutine, AHeader: TSyntaxNode;
  var AKnown: TDictionary<string, Integer>): Integer;
var
  mDeclared: Integer;
begin
  Result := TMetricsCalculator.ParameterCount(AHeader);
  if (AHeader = nil) or (AHeader.FindChild(TSyntaxKind.Parameters) <> nil) or (Pos('.', ARoutine.Name) = 0) then
  begin
    Exit;
  end;
  if AKnown = nil then
  begin
    AKnown := Declarations(ATree);
  end;
  if AKnown.TryGetValue(UpperCase(ARoutine.Name), mDeclared) and (mDeclared > 0) then
  begin
    Result := mDeclared;
  end;
end;

/// <summary>Kennzahlen von ARoutine ohne die Parameterzahl.</summary>
function RoutineMetrics(ATree: TSyntaxTree; ARoutine, AHeader: TSyntaxNode): TRoutineMetrics;
var
  mFlow: TFlow;
begin
  Result := Default(TRoutineMetrics);
  Result.Name := QualifiedRoutineName(ARoutine);
  Result.Range := TTextRange.Create(ARoutine.StartPos, ARoutine.EndPos);
  Result.NameRange := TTextRange.Create(ARoutine.StartPos, ARoutine.StartPos);
  if AHeader <> nil then
  begin
    Result.NameRange := NameRangeOf(ATree.Tokens, AHeader);
  end;
  Result.Values[TMetricKind.MethodLength] := TMetricsCalculator.CodeLines(ATree, ARoutine);
  mFlow := Analyze(ATree, ARoutine);
  Result.Values[TMetricKind.NestingDepth] := mFlow.Depth;
  Result.Values[TMetricKind.Cyclomatic] := mFlow.Cyclomatic;
  Result.Values[TMetricKind.Cognitive] := mFlow.Cognitive;
  Result.Values[TMetricKind.BooleanOperands] := mFlow.Operands;
  Result.Values[TMetricKind.LocalCount] := DeclaredLocals(ARoutine) + mFlow.InlineLocals;
  Result.Values[TMetricKind.ExitPoints] := mFlow.Exits;
end;

class function TMetricsCalculator.Routines(ATree: TSyntaxTree): TArray<TRoutineMetrics>;
var
  mNode, mHeader: TSyntaxNode;
  mKnown: TDictionary<string, Integer>;
  mMetrics: TRoutineMetrics;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mKnown := nil;
  try
    for mNode in FindRoutines(ATree) do
    begin
      mHeader := mNode.FindChild(TSyntaxKind.RoutineHeader);
      mMetrics := RoutineMetrics(ATree, mNode, mHeader);
      mMetrics.Values[TMetricKind.ParameterCount] := RoutineParameters(ATree, mNode, mHeader, mKnown);
      Result := Result + [mMetrics];
    end;
  finally
    mKnown.Free;
  end;
end;

class function TMetricsCalculator.Operands(AExpression: TSyntaxNode): Integer;
var
  Stack: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  // Iterativ: lange Ketten ergeben tiefe Bäume.
  Result := 0;
  Stack := TStack<TSyntaxNode>.Create;
  try
    Stack.Push(AExpression);
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      if (Node.Kind = TSyntaxKind.BinaryExpr) and (Node.ChildCount = 2) and (SameText(Node.Name, 'and') or
        SameText(Node.Name, 'or') or SameText(Node.Name, 'xor')) then
      begin
        Stack.Push(Node[1]);
        Stack.Push(Node[0]);
      end
      else if ((Node.Kind = TSyntaxKind.ParenExpr) or ((Node.Kind = TSyntaxKind.UnaryExpr) and
        SameText(Node.Name, 'not'))) and (Node.ChildCount = 1) then
      begin
        Stack.Push(Node[0]);
      end
      else
      begin
        Inc(Result);
      end;
    end;
  finally
    Stack.Free;
  end;
end;

class function TMetricsCalculator.Conditions(ATree: TSyntaxTree): TArray<TConditionMetrics>;
var
  Routine, Node: TSyntaxNode;
  Found: TList<TSyntaxNode>;
  Item: TConditionMetrics;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  Found := TList<TSyntaxNode>.Create;
  try
    for Routine in FindRoutines(ATree) do
    begin
      AnalyzeWith(ATree, Routine, Found);
    end;
    Found.Sort(TComparer<TSyntaxNode>.Construct(
      function(const A, B: TSyntaxNode): Integer
      begin
        Result := A.StartOffset - B.StartOffset;
      end));
    for Node in Found do
    begin
      Item.Range := TTextRange.Create(Node.StartPos, Node.EndPos);
      Item.StartOffset := Node.StartOffset;
      Item.EndOffset := Node.EndOffset;
      Item.Operands := Operands(Node);
      Result := Result + [Item];
    end;
  finally
    Found.Free;
  end;
end;

class function TMetricsCalculator.MemberCount(AClass: TSyntaxNode): Integer;
var
  Index, Inner: Integer;
  Child: TSyntaxNode;
begin
  Result := 0;
  for Index := 0 to AClass.ChildCount - 1 do
  begin
    Child := AClass[Index];
    case Child.Kind of
      TSyntaxKind.Field:
        Inc(Result, NameCount(Child.Name));
      TSyntaxKind.RoutineHeader:
        Inc(Result);
      // property Align; hebt nur die Sichtbarkeit an und ist kein neues Member.
      TSyntaxKind.PropertyDecl:
        if Child.FindChild(TSyntaxKind.TypeReference) <> nil then
        begin
          Inc(Result);
        end;
      TSyntaxKind.VarSection:
        for Inner := 0 to Child.ChildCount - 1 do
        begin
          if Child[Inner].Kind in [TSyntaxKind.VarDecl, TSyntaxKind.Field] then
          begin
            Inc(Result, NameCount(Child[Inner].Name));
          end;
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
end;

/// <summary>Bezeichner ANode.Name (ohne generische Parameter) ab dem Anfang von ANode.</summary>
function TypeNameRange(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): TTextRange;
var
  mPosition: Integer;
  mName: string;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.StartPos);
  mName := ANode.Name;
  if Pos('<', mName) > 0 then
  begin
    mName := Copy(mName, 1, Pos('<', mName) - 1);
  end;
  mPosition := FirstTokenAt(ATokens, ANode.StartOffset);
  while (mPosition < Length(ATokens)) and (ATokens[mPosition].Offset < ANode.EndOffset) do
  begin
    if (ATokens[mPosition].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[mPosition].Text, mName) then
    begin
      Exit(TTextRange.Create(ATokens[mPosition].StartPos, ATokens[mPosition].EndPos));
    end;
    Inc(mPosition);
  end;
end;

/// <summary>Units in der uses-Klausel AUses.</summary>
function UsedUnitCount(AUses: TSyntaxNode): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  for mIndex := 0 to AUses.ChildCount - 1 do
  begin
    if AUses[mIndex].Kind = TSyntaxKind.UsedUnit then
    begin
      Inc(Result);
    end;
  end;
end;

/// <summary>Klassengröße zur Typdeklaration ATypeDecl; False, wenn sie keine Klasse (class, object) ist.</summary>
function ClassSizeOf(const ATokens: TArray<TPascalToken>; ATypeDecl: TSyntaxNode;
  out AItem: TStructureMetrics): Boolean;
var
  mBody: TSyntaxNode;
begin
  AItem := Default(TStructureMetrics);
  mBody := ATypeDecl.FindChild(TSyntaxKind.ClassType);
  if mBody = nil then
  begin
    mBody := ATypeDecl.FindChild(TSyntaxKind.ObjectType);
  end;
  Result := mBody <> nil;
  if Result then
  begin
    AItem.Kind := TStructureKind.ClassSize;
    AItem.Name := ATypeDecl.Name;
    AItem.NameRange := TypeNameRange(ATokens, ATypeDecl);
    AItem.Value := TMetricsCalculator.MemberCount(mBody);
  end;
end;

type
  /// <summary>Was Structure im Baum sammelt: Klassen, erste uses-Klausel und Units in allen uses-Klauseln.
  /// </summary>
  TStructureScan = record
    Classes: TArray<TStructureMetrics>;
    UsesNode: TSyntaxNode;
    UsesTotal: Integer;
  end;

function ScanStructure(ATree: TSyntaxTree): TStructureScan;
var
  mStack: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
  mItem: TStructureMetrics;
begin
  Result := Default(TStructureScan);
  mStack := TStack<TSyntaxNode>.Create;
  try
    mStack.Push(ATree.Root);
    while mStack.Count > 0 do
    begin
      mNode := mStack.Pop;
      if mNode.Kind = TSyntaxKind.UsesClause then
      begin
        if Result.UsesNode = nil then
        begin
          Result.UsesNode := mNode;
        end;
        Inc(Result.UsesTotal, UsedUnitCount(mNode));
      end
      else if not (mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] + ExpressionKinds) then
      begin
        if (mNode.Kind = TSyntaxKind.TypeDecl) and ClassSizeOf(ATree.Tokens, mNode, mItem) then
        begin
          Result.Classes := Result.Classes + [mItem];
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mStack.Push(mNode[mIndex]);
        end;
      end;
    end;
  finally
    mStack.Free;
  end;
end;

/// <summary>Länge der Unit und Zahl ihrer Units im uses.</summary>
function UnitStructure(ATree: TSyntaxTree; const AScan: TStructureScan): TArray<TStructureMetrics>;
var
  mTokens: TArray<TPascalToken>;
  mItem: TStructureMetrics;
  mIndex: Integer;
begin
  mTokens := ATree.Tokens;
  mItem := Default(TStructureMetrics);
  mItem.Kind := TStructureKind.UnitLength;
  mItem.Name := ATree.Root.Name;
  mItem.NameRange := NameRangeOf(mTokens, ATree.Root);
  mItem.Value := 1;
  if mTokens <> nil then
  begin
    mItem.Value := mTokens[High(mTokens)].EndPos.Line + 1;
  end;
  Result := [mItem];
  if AScan.UsesNode <> nil then
  begin
    mItem.Kind := TStructureKind.UsesCount;
    mIndex := FirstTokenAt(mTokens, AScan.UsesNode.StartOffset);
    if mIndex < Length(mTokens) then
    begin
      mItem.NameRange := TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos);
    end;
    mItem.Value := AScan.UsesTotal;
    Result := Result + [mItem];
  end;
end;

class function TMetricsCalculator.Structure(ATree: TSyntaxTree): TArray<TStructureMetrics>;
var
  mScan: TStructureScan;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
  mScan := ScanStructure(ATree);
  if ATree.Root.Kind = TSyntaxKind.UnitFile then
  begin
    Result := UnitStructure(ATree, mScan);
  end;
  Result := Result + mScan.Classes;
end;

class function TMetricsCalculator.StructureForText(const AText: string): TArray<TStructureMetrics>;
var
  Tree: TSyntaxTree;
begin
  Tree := TSyntaxTreeCache.Parse(AText);
  try
    Result := Structure(Tree);
  finally
    Tree.Free;
  end;
end;

class function TMetricsCalculator.ForText(const AText: string): TArray<TRoutineMetrics>;
var
  Tree: TSyntaxTree;
begin
  // Über den Cache: TSyntaxTreeCacheTests.NoParserCallsOutsideCache verlangt das für alle Parser-Aufrufe.
  Tree := TSyntaxTreeCache.Parse(AText);
  try
    Result := Routines(Tree);
  finally
    Tree.Free;
  end;
end;

end.
