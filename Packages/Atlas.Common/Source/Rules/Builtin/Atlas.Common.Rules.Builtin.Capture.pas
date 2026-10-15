unit Atlas.Common.Rules.Builtin.Capture;

// captured-loop-variable (#116): Eine anonyme Methode, die verzögert läuft
// (TThread.Queue, TTask.Run …), erfasst eine Variable, die sich danach noch
// ändert. Delphi erfasst die Variable, nicht ihren Wert; beim Ausführen
// steht dort schon ein anderer.
//
// Gemeldet werden:
// - die Variable einer umgebenden for-in-Schleife und eines "for var",
// - lokale Variablen, die nach dem Erzeugen der anonymen Methode laut
//   Kontrollfluss (#143) noch zugewiesen werden (auch Inc/Dec), etwa im
//   nächsten Durchlauf einer while- oder repeat-Schleife.
// Eine klassische for-Zählvariable lässt sich nicht erfassen (E2555) und
// wird übergangen.
//
// Verzögert ist eine API aus der Liste (Option "deferredApis" ergänzt sie)
// mit Konfidenz hoch, oder die Zuweisung an eine Ereignis-Property (On…)
// mit Konfidenz mittel. TThread.Synchronize läuft synchron und zählt nicht.
//
// Korrektur "Variable je Durchlauf kopieren": Die anonyme Methode wandert in
// eine lokale Funktion, die den Wert als Parameter bekommt; so erfasst jede
// Instanz ihren eigenen Wert. Nur für parameterlose Prozeduren (TProc), deren
// Variable einen bekannten Typ hat und die sonst nichts Lokales erfassen.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TCapturedLoopVariableRule = class(TInterfacedObject, IRule)
  public const
    DefaultDeferredApis: array[0..6] of string = ('TThread.Queue', 'TThread.ForceQueue', 'TTask.Run',
      'TTask.Create', 'TTask.Future', 'TThread.CreateAnonymousThread', 'TParallel.For');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterCaptureRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Derived;

type
  /// <summary>Lokale Variable der Routine mit Typ ('' wenn unbekannt).</summary>
  TLocal = record
    Name: string;
    TypeName: string;
  end;

function DeferredApis(const AOptions: string): TArray<string>;
var
  Index: Integer;
  Value, Items, Item: TJSONValue;
begin
  Result := nil;
  for Index := Low(TCapturedLoopVariableRule.DefaultDeferredApis) to High(TCapturedLoopVariableRule.DefaultDeferredApis) do
    Result := Result + [TCapturedLoopVariableRule.DefaultDeferredApis[Index]];
  if AOptions = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
      Exit;
    Items := TJSONObject(Value).GetValue('deferredApis');
    if Items is TJSONArray then
      for Item in TJSONArray(Items) do
        if Item is TJSONString then
          Result := Result + [Item.Value];
  finally
    Value.Free;
  end;
end;

/// <summary>Text eines Aufrufziels: Bezeichner und Member-Zugriffe, z. B. "TThread.Queue".</summary>
function CalleeText(ANode: TSyntaxNode): string;
begin
  case ANode.Kind of
    TSyntaxKind.Identifier:
      Result := ANode.Name;
    TSyntaxKind.MemberAccess:
      if ANode.ChildCount > 0 then
        Result := CalleeText(ANode[0]) + '.' + ANode.Name
      else
        Result := ANode.Name;
  else
    Result := '';
  end;
end;

/// <summary>Passt das Aufrufziel auf einen Listeneintrag? "TThread.Queue" passt auf
/// "System.Classes.TThread.Queue", "Queue" nur auf den Namen.</summary>
function MatchesApi(const ACallee: string; const AApis: TArray<string>): Boolean;
var
  Api: string;
begin
  for Api in AApis do
    if SameText(ACallee, Api) or EndsText('.' + Api, ACallee) then
      Exit(True);
  Result := False;
end;

/// <summary>Läuft AMethod verzögert? AConfidence ist dann gesetzt.</summary>
function IsDeferred(AMethod: TSyntaxNode; const AApis: TArray<string>; out AConfidence: TRuleConfidence): Boolean;
var
  Parent: TSyntaxNode;
begin
  Result := False;
  Parent := AMethod.Parent;
  if Parent = nil then
    Exit;
  if (Parent.Kind = TSyntaxKind.Call) and (Parent.ChildCount > 0) and (Parent[0] <> AMethod) and
    MatchesApi(CalleeText(Parent[0]), AApis) then
  begin
    AConfidence := TRuleConfidence.High;
    Exit(True);
  end;
  // Ereignis- oder Callback-Property: X.OnDone := procedure …
  if (Parent.Kind = TSyntaxKind.AssignStatement) and (Parent.ChildCount > 1) and (Parent[1] = AMethod) and
    (Parent[0].Kind = TSyntaxKind.MemberAccess) and StartsText('On', Parent[0].Name) then
  begin
    AConfidence := TRuleConfidence.Medium;
    Exit(True);
  end;
end;


/// <summary>Anonyme Methoden im Rumpf, ohne lokale Routinen.</summary>
procedure CollectAnonymous(ANode: TSyntaxNode; var AMethods: TArray<TSyntaxNode>);
var
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.RoutineDecl then
    Exit;
  if ANode.Kind = TSyntaxKind.AnonymousMethod then
    AMethods := AMethods + [ANode];
  for Index := 0 to ANode.ChildCount - 1 do
    CollectAnonymous(ANode[Index], AMethods);
end;

/// <summary>Bezeichner im Rumpf der anonymen Methode (ohne verschachtelte anonyme Methoden).</summary>
procedure CollectIdentifiers(ANode: TSyntaxNode; AList: TList<TSyntaxNode>);
var
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.Identifier then
    AList.Add(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    CollectIdentifiers(ANode[Index], AList);
end;

function NextToken(const AContext: TRuleContext; AOffset: Integer; out AToken: TPascalToken): Boolean;
var
  Token: TPascalToken;
begin
  for Token in AContext.Tree.Tokens do
    if (Token.Offset >= AOffset) and not (Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      AToken := Token;
      Exit(True);
    end;
  Result := False;
end;

/// <summary>Ist ALoop ein "for var …" (Variable mit der Schleife deklariert)?</summary>
function IsInlineLoop(const AContext: TRuleContext; ALoop: TSyntaxNode): Boolean;
var
  ForToken, Token: TPascalToken;
begin
  // Hinter "for" steht "var".
  Result := NextToken(AContext, ALoop.StartOffset, ForToken) and
    NextToken(AContext, ForToken.Offset + Length(ForToken.Text), Token) and Token.IsKeyword('var');
end;

/// <summary>Umgebende Schleife, deren Variable AName ist; nil sonst.</summary>
function EnclosingLoop(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
begin
  Result := ANode.Parent;
  while Result <> nil do
  begin
    if (Result.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and SameText(Result.Name, AName) then
      Exit;
    if Result.Kind = TSyntaxKind.RoutineDecl then
      Exit(nil);
    Result := Result.Parent;
  end;
end;

function Locals(ARoutine, ABlock: TSyntaxNode): TArray<TLocal>;

  procedure AddNames(const ANames, ATypeName: string);
  var
    Name: string;
    Local: TLocal;
  begin
    for Name in SplitString(ANames, ',') do
      if Trim(Name) <> '' then
      begin
        Local.Name := Trim(Name);
        Local.TypeName := ATypeName;
        Result := Result + [Local];
      end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    TypeNode: TSyntaxNode;
  begin
    if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      Exit;
    if ANode.Kind = TSyntaxKind.InlineVar then
    begin
      TypeNode := ANode.FindChild(TSyntaxKind.TypeReference);
      if TypeNode <> nil then
        AddNames(ANode.Name, TypeNode.Name)
      else
        AddNames(ANode.Name, '');
    end
    else if ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
      AddNames(ANode.Name, '');
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

var
  Index, Inner: Integer;
  Section, TypeNode: TSyntaxNode;
begin
  Result := nil;
  for Index := 0 to ARoutine.ChildCount - 1 do
  begin
    Section := ARoutine[Index];
    if Section.Kind <> TSyntaxKind.VarSection then
      Continue;
    for Inner := 0 to Section.ChildCount - 1 do
      if Section[Inner].Kind = TSyntaxKind.VarDecl then
      begin
        TypeNode := Section[Inner].FindChild(TSyntaxKind.TypeReference);
        if (TypeNode <> nil) and (TypeNode.ChildCount = 0) then
          AddNames(Section[Inner].Name, TypeNode.Name)
        else
          AddNames(Section[Inner].Name, '');
      end;
  end;
  Visit(ABlock);
end;

function FindLocal(const ALocals: TArray<TLocal>; const AName: string; out ALocal: TLocal): Boolean;
var
  Local: TLocal;
begin
  for Local in ALocals do
    if SameText(Local.Name, AName) then
    begin
      ALocal := Local;
      Exit(True);
    end;
  Result := False;
end;

/// <summary>Flussknoten der Anweisung um ANode.</summary>
function FlowNodeOf(AGraph: TControlFlowGraph; ANode: TSyntaxNode): TFlowNode;
begin
  Result := nil;
  while (ANode <> nil) and (Result = nil) do
  begin
    Result := AGraph.NodeOf(ANode);
    ANode := ANode.Parent;
  end;
end;

/// <summary>Schreibt der Knoten AName (Zuweisung, Schleife, Inc/Dec)?</summary>
function Writes(ANode: TFlowNode; const AName: string): Boolean;
var
  Syntax, Call: TSyntaxNode;
begin
  if SameText(ANode.Defines, AName) then
    Exit(True);
  Syntax := ANode.Syntax;
  Result := False;
  if (Syntax = nil) or (Syntax.Kind <> TSyntaxKind.CallStatement) or (Syntax.ChildCount = 0) then
    Exit;
  Call := Syntax[0];
  Result := (Call.Kind = TSyntaxKind.Call) and (Call.ChildCount > 1) and (Call[0].Kind = TSyntaxKind.Identifier) and
    MatchText(Call[0].Name, ['Inc', 'Dec']) and (Call[1].Kind = TSyntaxKind.Identifier) and
    SameText(Call[1].Name, AName);
end;

/// <summary>Wird AName auf einem Weg ab AStart (ohne AStart selbst, außer über eine Schleife) geschrieben?</summary>
function WrittenAfter(AGraph: TControlFlowGraph; AStart: TFlowNode; const AName: string): Boolean;
var
  Seen: TArray<Boolean>;
  Stack: TStack<TFlowNode>;
  Node, Next: TFlowNode;
begin
  Result := False;
  SetLength(Seen, AGraph.Nodes.Count);
  Stack := TStack<TFlowNode>.Create;
  try
    for Next in AStart.Successors do
      if not Seen[Next.Index] then
      begin
        Seen[Next.Index] := True;
        Stack.Push(Next);
      end;
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      if Writes(Node, AName) then
        Exit(True);
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
end;


function LineBreakOf(const AText: string): string;
begin
  if Pos(#13#10, AText) > 0 then
    Result := #13#10
  else
    Result := #10;
end;

/// <summary>Korrektur "Variable je Durchlauf kopieren"; False, wenn sie nicht sicher möglich ist.</summary>
function CopyPerIterationFix(const ACache: IRuleDerivedCache; const AContext: TRuleContext;
  ARoutine, AMethod: TSyntaxNode; const ALocal: TLocal; const ALocals: TArray<TLocal>; out AFix: TRuleFix): Boolean;
var
  Identifiers: TList<TSyntaxNode>;
  Identifier, Header, Block: TSyntaxNode;
  Other: TLocal;
  Text, Body, LB, Indent, FunctionName: string;
  Position, Index, LineStart: Integer;
  Insert: TTextPosition;
begin
  Result := False;
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  Block := ARoutine.FindChild(TSyntaxKind.Block);
  // Nur procedure ohne Parameter (TProc) und mit bekanntem Typ.
  if (ALocal.TypeName = '') or (Header = nil) or (Block = nil) or not SameText(AMethod.Name, 'procedure') or
    (AMethod.FindChild(TSyntaxKind.Parameters) <> nil) then
    Exit;
  Identifiers := TList<TSyntaxNode>.Create;
  try
    CollectIdentifiers(AMethod, Identifiers);
    // Weitere lokale Variablen würden in der Hilfsfunktion fehlen.
    for Identifier in Identifiers do
      if not SameText(Identifier.Name, ALocal.Name) and FindLocal(ALocals, Identifier.Name, Other) then
        Exit;
    Text := AContext.Text;
    // Rumpf der anonymen Methode mit AValue statt der Variable, von hinten ersetzt.
    Body := Copy(Text, AMethod.StartOffset + 1, AMethod.EndOffset - AMethod.StartOffset);
    for Index := Identifiers.Count - 1 downto 0 do
    begin
      Identifier := Identifiers[Index];
      if not SameText(Identifier.Name, ALocal.Name) then
        Continue;
      Position := Identifier.StartOffset - AMethod.StartOffset;
      Body := Copy(Body, 1, Position) + 'AValue' + Copy(Body, Position + Length(ALocal.Name) + 1, MaxInt);
    end;
  finally
    Identifiers.Free;
  end;
  LB := LineBreakOf(Text);
  // Einrückung der Routine; die lokale Funktion steht direkt vor ihrem begin.
  LineStart := ARoutine.StartOffset;
  while (LineStart > 0) and (Text[LineStart] <> #10) do
    Dec(LineStart);
  Indent := Copy(Text, LineStart + 1, ARoutine.StartOffset - LineStart);
  if Trim(Indent) <> '' then
    Exit;
  FunctionName := 'Capture' + ALocal.Name;
  Insert := TRuleDerived.PositionAt(ACache, AContext, Block.StartOffset);
  if Insert.Character <> Length(Indent) then
    Exit;
  AFix := TRuleFix.Create(Format('Variable "%s" je Durchlauf kopieren', [ALocal.Name]), [
    TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(Insert.Line, 0), TTextPosition.Create(Insert.Line, 0)),
      Indent + '  function ' + FunctionName + '(const AValue: ' + ALocal.TypeName + '): TProc;' + LB +
      Indent + '  begin' + LB +
      Indent + '    Result := ' + Body + ';' + LB +
      Indent + '  end;' + LB + LB),
    TRuleEdit.Create(TRuleDerived.OffsetRange(ACache, AContext, AMethod.StartOffset, AMethod.EndOffset),
      FunctionName + '(' + ALocal.Name + ')')]);
  Result := True;
end;

{ TCapturedLoopVariableRule }

function TCapturedLoopVariableRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('captured-loop-variable', TRuleSeverity.Warning,
    'Anonyme Methode erfasst eine Variable, die sich vor dem verzögerten Aufruf noch ändert');
end;

procedure TCapturedLoopVariableRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Apis: TArray<string>;
  Routines, Methods: TArray<TSyntaxNode>;
  Routine, Block, Method, Identifier, Loop: TSyntaxNode;
  Variables: TArray<TLocal>;
  Local: TLocal;
  Identifiers: TList<TSyntaxNode>;
  Reported: TList<string>;
  Graph: TControlFlowGraph;
  Start: TFlowNode;
  Confidence: TRuleConfidence;
  Changes: Boolean;
  Fix: TRuleFix;
  Message: string;
  Cache: IRuleDerivedCache;
begin
  if AContext.Tree = nil then
    Exit;
  Apis := DeferredApis(AContext.Options);
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  Cache := TRuleDerived.Open(AContext);
  Routines := TRuleDerived.Routines(Cache, AContext);
  Identifiers := TList<TSyntaxNode>.Create;
  Reported := TList<string>.Create;
  try
    for Routine in Routines do
    begin
      Block := Routine.FindChild(TSyntaxKind.Block);
      Methods := nil;
      CollectAnonymous(Block, Methods);
      if Methods = nil then
        Continue;
      Variables := Locals(Routine, Block);
      Graph := nil;
      for Method in Methods do
      begin
        if not IsDeferred(Method, Apis, Confidence) then
          Continue;
        Identifiers.Clear;
        Reported.Clear;
        CollectIdentifiers(Method, Identifiers);
        for Identifier in Identifiers do
        begin
          if not FindLocal(Variables, Identifier.Name, Local) or Reported.Contains(LowerCase(Local.Name)) then
            Continue;
          Loop := EnclosingLoop(Method, Local.Name);
          if Loop <> nil then
          begin
            // for I := … mit äußerer Variable lässt sich nicht erfassen (E2555).
            if (Loop.Kind = TSyntaxKind.ForStatement) and not IsInlineLoop(AContext, Loop) then
              Continue;
            Changes := True;
          end
          else
          begin
            if Graph = nil then
              Graph := TRuleDerived.Graph(Cache, AContext, Routine);
            Start := FlowNodeOf(Graph, Method);
            Changes := Graph.Complete and (Start <> nil) and WrittenAfter(Graph, Start, Local.Name);
          end;
          if not Changes then
            Continue;
          Reported.Add(LowerCase(Local.Name));
          Message := Format('Die anonyme Methode erfasst "%s", nicht seinen Wert; bis sie läuft, hat "%s" ' +
            'womöglich schon einen anderen Wert', [Local.Name, Local.Name]);
          if CopyPerIterationFix(Cache, AContext, Routine, Method, Local, Variables, Fix) then
            AReport.Add(TTextRange.Create(Identifier.StartPos, Identifier.EndPos), Message, Confidence, [Fix])
          else
            AReport.Add(TTextRange.Create(Identifier.StartPos, Identifier.EndPos), Message, Confidence);
        end;
      end;
    end;
  finally
    Reported.Free;
    Identifiers.Free;
  end;
end;

procedure RegisterCaptureRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TCapturedLoopVariableRule.Create);
end;

end.
