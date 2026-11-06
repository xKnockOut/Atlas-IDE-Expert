unit Atlas.Common.Rules.Builtin.Flow.Uninitialized;

// Regel possibly-uninitialized aus Atlas.Common.Rules.Builtin.Flow (#269): lokale Variable wird möglicherweise vor
// der ersten Zuweisung gelesen (wie W1036). Geprüft werden nur Variablen, die Delphi nicht selbst vorbelegt:
// einfache Typen (Konfidenz hoch) und T…-Typen wie Klassen und Records (Konfidenz mittel). Ein Merker (Found :=
// True neben der Zuweisung) schützt einen Lesezugriff in if Found then … (#1109).

interface

uses
  Atlas.Common.Rules.Contract;

type
  TPossiblyUninitializedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFlowUninitializedText = (Title, MaybeRead);

const
  cTexts: array[TFlowUninitializedText] of TAtlasText = (
    (De: 'Variable wird möglicherweise vor der ersten Zuweisung gelesen';
     En: 'Variable may be read before the first assignment'),
    (De: '"%s" wird hier möglicherweise gelesen, bevor ein Wert zugewiesen wurde';
     En: '"%s" may be read here before a value was assigned'));

{$SCOPEDENUMS OFF}

type
  /// <summary>Merker in Bedingungen: positiv (F, Assigned(F), F &lt;&gt; nil) und negativ (not F, F = nil).
  /// </summary>
  TFlagExpressions = class
  public
    class function IsFalseValue(ANode: TSyntaxNode): Boolean; static;
    class function Compared(ANode: TSyntaxNode; out AFlag: string): Boolean; static;
    class function PositiveBinary(ANode: TSyntaxNode; out AFlag: string): Boolean; static;
    class function Positive(ANode: TSyntaxNode; out AFlag: string): Boolean; static;
    class function NegativeBinary(ANode: TSyntaxNode; out AFlag: string): Boolean; static;
    class function Negative(ANode: TSyntaxNode; out AFlag: string): Boolean; static;
  end;

  /// <summary>Prüfung einer Unit für possibly-uninitialized; hält die Routine, ihren Graphen und die geprüfte
  /// Variable.</summary>
  TUninitializedCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FGraph: TControlFlowGraph;
    FName: string;
    FConfidence: TRuleConfidence;
    FReported: Boolean;
    /// <summary>Record-Methoden je Typname (Großbuchstaben): RecordMethods durchsucht die Typdeklarationen der Unit;
    /// je Variable gerufen wuchs das mit großen Klassen quadratisch.</summary>
    FRecordMethods: TDictionary<string, TArray<string>>;
    function MethodsOfRecord(const ATypeName: string): TArray<string>;
    function FlowNodeOf(ANode: TSyntaxNode): TFlowNode;
    function IsFlagFor(ABlock: TSyntaxNode; const AFlag: string): Boolean;
    function ThenGuard(ABlock, AParent, AChild: TSyntaxNode): Boolean;
    function OperandGuard(ABlock, AParent, AChild: TSyntaxNode): Boolean;
    function ExitGuard(ABlock, AParent, AChild: TSyntaxNode): Boolean;
    function GuardedByFlag(ABlock, ANode: TSyntaxNode): Boolean;
    function IsRead(ANode: TSyntaxNode): Boolean;
    function ReadsUninitialized(ARoot, ANode: TSyntaxNode): Boolean;
    procedure Visit(ARoot: TSyntaxNode);
    procedure CheckDecl(ARoutine, ABlock, ADecl: TSyntaxNode);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

{ TFlagExpressions }

class function TFlagExpressions.IsFalseValue(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) and
    MatchText(ANode.Name, ['False', 'nil', '''''']);
end;

/// <summary>Vergleich eines Bezeichners mit False, nil oder '' (auf einer der beiden Seiten); liefert ihn.
/// </summary>
class function TFlagExpressions.Compared(ANode: TSyntaxNode; out AFlag: string): Boolean;
var
  Index: Integer;
begin
  Result := False;
  for Index := 0 to 1 do
  begin
    if not Result and IsFalseValue(ANode[1 - Index]) and (ANode[Index].Kind = TSyntaxKind.Identifier) then
    begin
      AFlag := ANode[Index].Name;
      Result := True;
    end;
  end;
end;

/// <summary>F and …, … and F, F &lt;&gt; nil.</summary>
class function TFlagExpressions.PositiveBinary(ANode: TSyntaxNode; out AFlag: string): Boolean;
begin
  Result := False;
  if ANode.ChildCount <> 2 then
  begin
    Exit;
  end;
  if SameText(ANode.Name, 'and') then
  begin
    Result := Positive(ANode[0], AFlag) or Positive(ANode[1], AFlag);
  end
  else if ANode.Name = '<>' then
  begin
    Result := Compared(ANode, AFlag);
  end;
end;

/// <summary>Merker ANode: F, Assigned(F), F &lt;&gt; nil, F &lt;&gt; ''; liefert F.</summary>
class function TFlagExpressions.Positive(ANode: TSyntaxNode; out AFlag: string): Boolean;
begin
  Result := False;
  case ANode.Kind of
    TSyntaxKind.Identifier:
      begin
        Result := not MatchText(ANode.Name, ['True', 'False', 'nil']);
        AFlag := ANode.Name;
      end;
    TSyntaxKind.ParenExpr:
      Result := (ANode.ChildCount = 1) and Positive(ANode[0], AFlag);
    TSyntaxKind.Call:
      begin
        Result := (ANode.ChildCount = 2) and IsName(ANode[0], 'Assigned') and (ANode[1].Kind = TSyntaxKind.Identifier);
        if Result then
        begin
          AFlag := ANode[1].Name;
        end;
      end;
    TSyntaxKind.BinaryExpr:
      Result := PositiveBinary(ANode, AFlag);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>… or …, F = nil.</summary>
class function TFlagExpressions.NegativeBinary(ANode: TSyntaxNode; out AFlag: string): Boolean;
begin
  Result := False;
  if ANode.ChildCount <> 2 then
  begin
    Exit;
  end;
  if SameText(ANode.Name, 'or') then
  begin
    Result := Negative(ANode[0], AFlag) or Negative(ANode[1], AFlag);
  end
  else if ANode.Name = '=' then
  begin
    Result := Compared(ANode, AFlag);
  end;
end;

/// <summary>Gegenteil eines Merkers: not F, F = nil, F = '', … or …; liefert F.</summary>
class function TFlagExpressions.Negative(ANode: TSyntaxNode; out AFlag: string): Boolean;
begin
  Result := False;
  case ANode.Kind of
    TSyntaxKind.ParenExpr:
      Result := (ANode.ChildCount = 1) and Negative(ANode[0], AFlag);
    TSyntaxKind.UnaryExpr:
      Result := SameText(ANode.Name, 'not') and (ANode.ChildCount = 1) and Positive(ANode[0], AFlag);
    TSyntaxKind.BinaryExpr:
      Result := NegativeBinary(ANode, AFlag);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Aufruf von Exit, Break, Continue, Abort oder Halt als Anweisung.</summary>
function IsLeavingCall(AStatement: TSyntaxNode): Boolean;
var
  Callee: TSyntaxNode;
begin
  Result := False;
  if AStatement.ChildCount = 0 then
  begin
    Exit;
  end;
  Callee := AStatement[0];
  if (Callee.Kind = TSyntaxKind.Call) and (Callee.ChildCount > 0) then
  begin
    Callee := Callee[0];
  end;
  Result := (Callee.Kind = TSyntaxKind.Identifier) and MatchText(Callee.Name,
    ['Exit', 'Break', 'Continue', 'Abort', 'Halt']);
end;

/// <summary>Verlässt AStatement die Anweisungsliste immer (Exit, raise, Break, Continue, Abort)?</summary>
function Leaves(AStatement: TSyntaxNode): Boolean;
begin
  case AStatement.Kind of
    TSyntaxKind.RaiseStatement:
      Result := True;
    TSyntaxKind.CallStatement:
      Result := IsLeavingCall(AStatement);
    TSyntaxKind.Block:
      Result := (AStatement.ChildCount > 0) and Leaves(AStatement[AStatement.ChildCount - 1]);
  else
    Result := False;
  end;
end;

/// <summary>Stehen in ANode Anweisungen nebeneinander (begin … end, try, repeat, case-Zweig)?</summary>
function IsStatementList(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.RepeatStatement,
    TSyntaxKind.FinallyBlock, TSyntaxKind.ExceptBlock, TSyntaxKind.CaseItem, TSyntaxKind.CaseElse];
end;

/// <summary>Weist AStatement (als begin … end) AName zu und verlässt die Liste danach?</summary>
function AssignsAndLeaves(AStatement: TSyntaxNode; const AName: string): Boolean;
var
  Child: Integer;
begin
  Result := False;
  if (AStatement.Kind <> TSyntaxKind.Block) or not Leaves(AStatement) then
  begin
    Exit;
  end;
  for Child := 0 to AStatement.ChildCount - 1 do
  begin
    Result := Result or IsAssignTo(AStatement[Child], AName);
  end;
end;

/// <summary>AStatement ist "if AFlag then begin AName := …; Break; end".</summary>
function IsFlagCommit(AStatement: TSyntaxNode; const AFlag, AName: string): Boolean;
begin
  Result := (AStatement.Kind = TSyntaxKind.IfStatement) and (AStatement.ChildCount = 2) and
    IsName(AStatement[0], AFlag) and AssignsAndLeaves(AStatement[1], AName);
end;

/// <summary>In der Liste AList folgt hinter AChild ein IsFlagCommit.</summary>
function CommitsInList(AList, AChild: TSyntaxNode; const AFlag, AName: string): Boolean;
var
  Index: Integer;
  Seen: Boolean;
begin
  Result := False;
  Seen := False;
  for Index := 0 to AList.ChildCount - 1 do
  begin
    Result := Result or (Seen and IsFlagCommit(AList[Index], AFlag, AName));
    Seen := Seen or (AList[Index] = AChild);
  end;
end;

/// <summary>Folgt der Zuweisung ANode an AFlag in einer umgebenden Liste "if AFlag then begin AName := …; Break;
/// end" (genau AFlag als Bedingung, nicht AFlag and …)? Dann bleibt AFlag nur gesetzt, wenn AName einen Wert hat
/// (Found := …; if Found then begin Hidden := S; Break; end; #1109).</summary>
function CommittedAfter(ABlock, ANode: TSyntaxNode; const AFlag, AName: string): Boolean;
var
  Child, Parent: TSyntaxNode;
begin
  Result := False;
  Child := ANode;
  Parent := ANode.Parent;
  while not Result and (Parent <> nil) and (Child <> ABlock) do
  begin
    Result := IsStatementList(Parent) and CommitsInList(Parent, Child, AFlag, AName);
    Child := Parent;
    Parent := Parent.Parent;
  end;
end;

/// <summary>Neben der Zuweisung ANode steht in derselben Anweisungsliste eine Zuweisung an AName.</summary>
function PairedInList(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Child: Integer;
  Sibling: TSyntaxNode;
begin
  Result := False;
  if (ANode.Parent = nil) or not IsStatementList(ANode.Parent) then
  begin
    Exit;
  end;
  for Child := 0 to ANode.Parent.ChildCount - 1 do
  begin
    Sibling := ANode.Parent[Child];
    Result := Result or ((Sibling <> ANode) and IsAssignTo(Sibling, AName));
  end;
end;

/// <summary>Nennt ANode irgendwo den Bezeichner AName?</summary>
function MentionsName(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsName(AVisited, Name) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Lokale Routinen und anonyme Methoden der Routine, die AName nennen: Sie können ihn setzen, wann immer
/// sie laufen (Finish; setzt AfterName); der Fluss der Routine sieht das nicht (#1109).</summary>
function UsedInNested(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  Child: Integer;
  Name: string;
begin
  Name := AName;
  Result := False;
  for Child := 0 to ARoutine.ChildCount - 1 do
  begin
    Result := Result or (ARoutine[Child].Search(
      function(AVisited: TSyntaxNode): TSyntaxSearchStep
      begin
        Result := TSyntaxSearchStep.Descend;
        if AVisited.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
        begin
          Result := TSyntaxSearchStep.Skip;
          if MentionsName(AVisited, Name) then
          begin
            Result := TSyntaxSearchStep.Found;
          end;
        end;
      end) <> nil);
  end;
end;

/// <summary>Namen der Methoden im Record-Rumpf ABody.</summary>
function RecordHeaderNames(ABody: TSyntaxNode): TArray<string>;
var
  Child: Integer;
begin
  Result := nil;
  for Child := 0 to ABody.ChildCount - 1 do
  begin
    if (ABody[Child].Kind = TSyntaxKind.RoutineHeader) and (ABody[Child].Name <> '') then
    begin
      Result := Result + [ABody[Child].Name];
    end;
  end;
end;

/// <summary>Methoden eines Record-Typs ATypeName aus dieser Unit; nil für andere Typen.</summary>
function RecordMethods(ARoot: TSyntaxNode; const ATypeName: string): TArray<string>;
var
  TypeName: string;
  Decl, Body: TSyntaxNode;
begin
  Result := nil;
  TypeName := ATypeName;
  Decl := ARoot.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if AVisited.Kind = TSyntaxKind.RoutineDecl then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (AVisited.Kind = TSyntaxKind.TypeDecl) and SameText(AVisited.Name, TypeName) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  if Decl = nil then
  begin
    Exit;
  end;
  Body := Decl.FindChild(TSyntaxKind.RecordType);
  if Body <> nil then
  begin
    Result := RecordHeaderNames(Body);
  end;
end;

/// <summary>Ruft der Rumpf eine Methode des Records auf der Variablen AName auf (Scanner.Init(…))? Die Methode
/// bekommt den Record als var-Self und legt ihn an.</summary>
function CallsRecordMethod(ABlock: TSyntaxNode; const AName: string; const AMethods: TArray<string>): Boolean;
var
  Name: string;
  Methods: TArray<string>;
begin
  if AMethods = nil then
  begin
    Exit(False);
  end;
  Name := AName;
  Methods := AMethods;
  Result := ABlock.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (AVisited.Kind = TSyntaxKind.MemberAccess) and (AVisited.ChildCount = 1) and IsName(AVisited[0], Name) and
        MatchText(AVisited.Name, Methods) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

/// <summary>Konfidenz für die Deklaration ADecl: einfache Typen hoch, T…-Typen mittel; False für verwaltete
/// Typen, vorbelegte (var X: Integer = 0) und generische.</summary>
function DeclConfidence(ADecl: TSyntaxNode; out ATypeName: string; out AConfidence: TRuleConfidence): Boolean;
var
  TypeNode: TSyntaxNode;
begin
  ATypeName := '';
  AConfidence := TRuleConfidence.Medium;
  TypeNode := ADecl.FindChild(TSyntaxKind.TypeReference);
  Result := (ADecl.Kind = TSyntaxKind.VarDecl) and (TypeNode <> nil) and (ADecl.ChildCount = 1);
  Result := Result and (TypeNode.FindChild(TSyntaxKind.GenericArgs) = nil);
  if not Result then
  begin
    Exit;
  end;
  ATypeName := TypeNode.Name;
  if MatchText(ATypeName, SimpleTypes) then
  begin
    AConfidence := TRuleConfidence.High;
  end
  else
  begin
    Result := StartsText('T', ATypeName) and (Length(ATypeName) > 1) and not MatchText(ATypeName, ManagedTypes);
  end;
end;

{ TPossiblyUninitializedRule }

function TPossiblyUninitializedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('possibly-uninitialized', TRuleSeverity.Warning,
    cTexts[TFlowUninitializedText.Title].Text);
end;

procedure TPossiblyUninitializedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: TUninitializedCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Check := TUninitializedCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

{ TUninitializedCheck }

constructor TUninitializedCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  FCache := TRuleDerived.Open(AContext);
  FRecordMethods := TDictionary<string, TArray<string>>.Create;
end;

destructor TUninitializedCheck.Destroy;
begin
  FRecordMethods.Free;
  inherited;
end;

function TUninitializedCheck.MethodsOfRecord(const ATypeName: string): TArray<string>;
var
  mKey: string;
begin
  mKey := UpperCase(ATypeName);
  if not FRecordMethods.TryGetValue(mKey, Result) then
  begin
    Result := RecordMethods(FContext.Tree.Root, ATypeName);
    FRecordMethods.Add(mKey, Result);
  end;
end;

function TUninitializedCheck.FlowNodeOf(ANode: TSyntaxNode): TFlowNode;
begin
  Result := nil;
  while (ANode <> nil) and (Result = nil) do
  begin
    Result := FGraph.NodeOf(ANode);
    ANode := ANode.Parent;
  end;
end;

/// <summary>Ist AFlag ein Merker für die Variable: Jede Zuweisung an AFlag setzt den Startwert (False, nil, '')
/// oder steht in derselben Anweisungsliste wie eine Zuweisung an die Variable (Feld := Symbol; Gefunden := True)?
/// Dann heißt ein gesetzter Merker, dass sie einen Wert hat (#1109).</summary>
function TUninitializedCheck.IsFlagFor(ABlock: TSyntaxNode; const AFlag: string): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Any: Boolean;
begin
  if SameText(AFlag, FName) or HasOpaqueUse(ABlock, AFlag) then
  begin
    Exit(False);
  end;
  Result := True;
  Any := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ABlock);
    while Result and (Pending.Count > 0) do
    begin
      Node := Pending.Pop;
      if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        Continue;
      end;
      if IsAssignTo(Node, AFlag) and not TFlagExpressions.IsFalseValue(Node[1]) then
      begin
        Result := PairedInList(Node, FName) or CommittedAfter(ABlock, Node, AFlag, FName);
        Any := True;
      end;
      PushChildren(Pending, Node);
    end;
  finally
    Pending.Free;
  end;
  Result := Result and Any;
end;

/// <summary>AChild ist der then-Zweig von "if F then" mit Merker F.</summary>
function TUninitializedCheck.ThenGuard(ABlock, AParent, AChild: TSyntaxNode): Boolean;
var
  Flag: string;
begin
  Result := (AParent.Kind = TSyntaxKind.IfStatement) and (AParent.ChildCount >= 2) and (AParent[1] = AChild) and
    TFlagExpressions.Positive(AParent[0], Flag) and IsFlagFor(ABlock, Flag);
end;

/// <summary>AChild steht rechts von "F and …" bzw. "not F or …" mit Merker F.</summary>
function TUninitializedCheck.OperandGuard(ABlock, AParent, AChild: TSyntaxNode): Boolean;
var
  Flag: string;
begin
  Result := (AParent.Kind = TSyntaxKind.BinaryExpr) and (AParent.ChildCount = 2) and (AParent[1] = AChild);
  Result := Result and ((SameText(AParent.Name, 'and') and TFlagExpressions.Positive(AParent[0], Flag)) or
    (SameText(AParent.Name, 'or') and TFlagExpressions.Negative(AParent[0], Flag)));
  Result := Result and IsFlagFor(ABlock, Flag);
end;

/// <summary>Vor AChild steht in der Anweisungsliste AParent "if not F then Exit" mit Merker F.</summary>
function TUninitializedCheck.ExitGuard(ABlock, AParent, AChild: TSyntaxNode): Boolean;
var
  Index: Integer;
  Statement: TSyntaxNode;
  Flag: string;
begin
  Result := False;
  if not IsStatementList(AParent) then
  begin
    Exit;
  end;
  Index := 0;
  while not Result and (Index < AParent.ChildCount) and (AParent[Index] <> AChild) do
  begin
    Statement := AParent[Index];
    Result := (Statement.Kind = TSyntaxKind.IfStatement) and (Statement.ChildCount = 2) and
      TFlagExpressions.Negative(Statement[0], Flag) and Leaves(Statement[1]) and IsFlagFor(ABlock, Flag);
    Inc(Index);
  end;
end;

/// <summary>Liest ANode die Variable nur, wenn ein Merker gesetzt ist: im then-Zweig von if F, rechts von F and …
/// bzw. not F or …, oder nach if not F then Exit in einer umgebenden Anweisungsliste?</summary>
function TUninitializedCheck.GuardedByFlag(ABlock, ANode: TSyntaxNode): Boolean;
var
  Child, Parent: TSyntaxNode;
begin
  Result := False;
  Child := ANode;
  Parent := ANode.Parent;
  while not Result and (Parent <> nil) and (Child <> ABlock) do
  begin
    Result := ThenGuard(ABlock, Parent, Child) or OperandGuard(ABlock, Parent, Child) or
      ExitGuard(ABlock, Parent, Child);
    Child := Parent;
    Parent := Parent.Parent;
  end;
end;

/// <summary>ANode liest die Variable (nicht links einer Zuweisung).</summary>
function TUninitializedCheck.IsRead(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Parent := ANode.Parent;
  Result := IsName(ANode, FName) and not ((Parent <> nil) and (Parent.Kind = TSyntaxKind.AssignStatement) and
    (Parent.ChildCount > 0) and (Parent[0] = ANode));
end;

/// <summary>Der Lesezugriff ANode ist erreichbar, ohne dass vorher ein Wert zugewiesen wurde.</summary>
function TUninitializedCheck.ReadsUninitialized(ARoot, ANode: TSyntaxNode): Boolean;
var
  Flow: TFlowNode;
begin
  Flow := FlowNodeOf(ANode);
  Result := (Flow <> nil) and (FGraph.IsReachable(Flow) = TFlowAnswer.Yes);
  Result := Result and FGraph.ReachingDefinitions(Flow, FName).FromEntry and not GuardedByFlag(ARoot, ANode);
end;

/// <summary>Erster Lesezugriff auf die Variable, der ohne vorherige Zuweisung erreichbar ist.</summary>
procedure TUninitializedCheck.Visit(ARoot: TSyntaxNode);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  // Iterativ mit eigenem Stapel (Bericht M1); die Kinder rückwärts darauf, damit der erste Treffer derselbe bleibt.
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoot);
    while not FReported and (Pending.Count > 0) do
    begin
      Node := Pending.Pop;
      if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        Continue;
      end;
      if IsRead(Node) and ReadsUninitialized(ARoot, Node) then
      begin
        FReport.Add(NodeRange(Node),
          cTexts[TFlowUninitializedText.MaybeRead].Fmt([FName]), FConfidence);
        FReported := True;
      end
      else
      begin
        PushChildren(Pending, Node);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TUninitializedCheck.CheckDecl(ARoutine, ABlock, ADecl: TSyntaxNode);
var
  TypeName, Name: string;
begin
  if not DeclConfidence(ADecl, TypeName, FConfidence) then
  begin
    Exit;
  end;
  for Name in ADecl.Name.Split([',']) do
  begin
    FName := Name;
    if HasOpaqueUse(ABlock, Name.Trim) or UsedInNested(ARoutine, Name) or
      CallsRecordMethod(ABlock, Name, MethodsOfRecord(TypeName)) then
    begin
      Continue;
    end;
    if FGraph = nil then
    begin
      FGraph := TRuleDerived.Graph(FCache, FContext, ARoutine);
    end;
    if not FGraph.Complete then
    begin
      Break;
    end;
    FReported := False;
    Visit(ABlock);
  end;
end;

procedure TUninitializedCheck.CheckRoutine(ARoutine: TSyntaxNode);
var
  Block, Section: TSyntaxNode;
  Index, Inner: Integer;
begin
  Block := ARoutine.FindChild(TSyntaxKind.Block);
  FGraph := nil;
  for Index := 0 to ARoutine.ChildCount - 1 do
  begin
    Section := ARoutine[Index];
    if Section.Kind <> TSyntaxKind.VarSection then
    begin
      Continue;
    end;
    for Inner := 0 to Section.ChildCount - 1 do
    begin
      CheckDecl(ARoutine, Block, Section[Inner]);
    end;
  end;
end;

procedure TUninitializedCheck.Run;
var
  Routine: TSyntaxNode;
begin
  for Routine in TRuleDerived.Routines(FCache, FContext) do
  begin
    CheckRoutine(Routine);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Flow.Uninitialized', cTexts);

end.
