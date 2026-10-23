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
//
// anonymous-capture-invalid (#1035, Gruppe „Compiler vorab“, wie E2555): Eine
// anonyme Methode greift auf einen var-, out- oder untypisierten Parameter
// oder auf Result einer umgebenden Routine bzw. anonymen Funktion zu. Der Name
// wird von innen nach außen aufgelöst (Parameter, var/const/type, lokale
// Routinen, Inline-Variablen, for var); with und asm machen die Regel still,
// Zweige bedingter Übersetzung, die sich mit der Stelle ausschließen, zählen
// nicht. Korrektur: Wert vor der Anweisung in eine lokale Variable kopieren,
// in der anonymen Methode nur diese verwenden und nach der Anweisung
// zurückschreiben, wenn sie geschrieben wird.

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

  TAnonymousCaptureInvalidRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

const
  AnonymousCaptureInvalidRuleId = 'anonymous-capture-invalid';

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
  Atlas.Common.Pascal.ConditionalBranches,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Rules.Derived,
  Atlas.Text.Lines;

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
var
  Suffix: string;
begin
  // Iterativ (Bericht M1): von rechts nach links an der Kette entlang.
  Suffix := '';
  while (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount > 0) do
  begin
    Suffix := '.' + ANode.Name + Suffix;
    ANode := ANode[0];
  end;
  case ANode.Kind of
    TSyntaxKind.Identifier, TSyntaxKind.MemberAccess:
      Result := ANode.Name + Suffix;
  else
    // Wie früher: Vor einem anderen Ausdruck (Aufruf, Index …) bleiben nur die Member, z. B. ".Queue".
    Result := Suffix;
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
  Methods: TArray<TSyntaxNode>;
begin
  // Iterativ (Bericht M1); var-Parameter lassen sich nicht in der anonymen Methode verwenden.
  Methods := AMethods;
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    begin
      Result := AVisited.Kind <> TSyntaxKind.RoutineDecl;
      if Result and (AVisited.Kind = TSyntaxKind.AnonymousMethod) then
        Methods := Methods + [AVisited];
    end);
  AMethods := Methods;
end;

/// <summary>Bezeichner im Rumpf der anonymen Methode (ohne verschachtelte anonyme Methoden).</summary>
procedure CollectIdentifiers(ANode: TSyntaxNode; AList: TList<TSyntaxNode>);
var
  List: TList<TSyntaxNode>;
begin
  List := AList;
  // Iterativ (Bericht M1).
  ANode.Walk(
    function(AVisited: TSyntaxNode): Boolean
    begin
      if AVisited.Kind = TSyntaxKind.Identifier then
        List.Add(AVisited);
      Result := True;
    end);
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

  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node, TypeNode: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ mit eigenem Stapel (Bericht M1), Reihenfolge wie die frühere Rekursion.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
          Continue;
        if Node.Kind = TSyntaxKind.InlineVar then
        begin
          TypeNode := Node.FindChild(TSyntaxKind.TypeReference);
          if TypeNode <> nil then
            AddNames(Node.Name, TypeNode.Name)
          else
            AddNames(Node.Name, '');
        end
        else if Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
          AddNames(Node.Name, '');
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
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
  LB := TTextLines.LineBreakOf(Text);
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

{ TAnonymousCaptureInvalidRule }

{$SCOPEDENUMS ON}
type
  /// <summary>Was ein Name in einem Bereich (Routine oder anonyme Methode) bezeichnet (#1035).</summary>
  TCaptureDeclKind = (None, Other, VarParam, OutParam, UntypedParam, FunctionResult);
{$SCOPEDENUMS OFF}

type
  /// <summary>Gefundene Deklaration eines Namens für anonymous-capture-invalid.</summary>
  TCaptureDecl = record
    Kind: TCaptureDeclKind;
    /// <summary>Routine oder anonyme Methode, die den Namen deklariert.</summary>
    Scope: TSyntaxNode;
    /// <summary>Parameter-Knoten bzw. nil bei Result.</summary>
    Node: TSyntaxNode;
    /// <summary>Name wie deklariert.</summary>
    Name: string;
    /// <summary>Typ als Text, '' bei untypisierten Parametern.</summary>
    TypeText: string;
  end;

function IsCaptureScope(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod];
end;

/// <summary>Nächster Bereich (Routine oder anonyme Methode) über ANode; nil außerhalb.</summary>
function ScopeOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not IsCaptureScope(Result) do
    Result := Result.Parent;
end;

function TypeChild(ANode: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind in TRoutineLocals.TypeKinds then
      Exit(ANode[Index]);
  Result := nil;
end;

function HasName(const ANames, AName: string): Boolean;
var
  Name: string;
begin
  for Name in SplitString(ANames, ',') do
    if SameText(Trim(Name), AName) then
      Exit(True);
  Result := False;
end;

/// <summary>Deklariert AScope den Namen AName, sichtbar an AOffset? Zweige, die sich mit APath ausschließen,
/// zählen nicht.</summary>
function FindCaptureDecl(const AText: string; AScope: TSyntaxNode; const AName: string; AOffset: Integer;
  const APaths: TArray<string>; const ATokens: TArray<TPascalToken>; const APath: string;
  out ADecl: TCaptureDecl): Boolean;
var
  Header, Parameters, Param, Section, Result_: TSyntaxNode;
  Index, Inner: Integer;
  Found: Boolean;

  function Active(ANode: TSyntaxNode): Boolean;
  begin
    Result := not TConditionalBranches.Exclusive(APath,
      TConditionalBranches.PathAt(APaths, TRoutineBody.TokenAt(ATokens, ANode.StartOffset)));
  end;

  procedure Take(AKind: TCaptureDeclKind; ANode: TSyntaxNode; const ATypeText: string);
  begin
    ADecl.Kind := AKind;
    ADecl.Scope := AScope;
    ADecl.Node := ANode;
    ADecl.Name := AName;
    ADecl.TypeText := ATypeText;
    Found := True;
  end;

  // Inline-Variablen und for var dieses Bereichs (nicht verschachtelter anonymer Methoden), die AOffset sehen.
  // Iterativ (Bericht M1).
  procedure VisitInline(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    I: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoot);
      while (Pending.Count > 0) and not Found do
      begin
        Node := Pending.Pop;
        if (Node <> AScope) and IsCaptureScope(Node) then
          Continue;
        if (Node.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst]) and HasName(Node.Name, AName) and
          (Node.StartOffset <= AOffset) and (Node.Parent <> nil) and (AOffset <= Node.Parent.EndOffset) and
          Active(Node) then
          Take(TCaptureDeclKind.Other, Node, '')
        else if (Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) and
          SameText(Node.Name, AName) and (Node.StartOffset <= AOffset) and (AOffset <= Node.EndOffset) and
          TRoutineLocals.IsInlineFor(ATokens, Node) and Active(Node) then
          Take(TCaptureDeclKind.Other, Node, '');
        for I := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[I]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  ADecl := Default(TCaptureDecl);
  Found := False;
  if AScope.Kind = TSyntaxKind.RoutineDecl then
    Header := AScope.FindChild(TSyntaxKind.RoutineHeader)
  else
    Header := AScope;
  Parameters := nil;
  if Header <> nil then
    Parameters := Header.FindChild(TSyntaxKind.Parameters);
  if Parameters <> nil then
    for Index := 0 to Parameters.ChildCount - 1 do
    begin
      Param := Parameters[Index];
      if (Param.Kind <> TSyntaxKind.Parameter) or not HasName(Param.Name, AName) or not Active(Param) then
        Continue;
      if TypeChild(Param) = nil then
        Take(TCaptureDeclKind.UntypedParam, Param, '')
      else if Param.Modifier = TParameterModifier.VarParam then
        Take(TCaptureDeclKind.VarParam, Param, TRoutineBody.TextOf(AText, TypeChild(Param)))
      else if Param.Modifier = TParameterModifier.OutParam then
        Take(TCaptureDeclKind.OutParam, Param, TRoutineBody.TextOf(AText, TypeChild(Param)))
      else
        Take(TCaptureDeclKind.Other, Param, '');
      Exit(True);
    end;
  for Index := 0 to AScope.ChildCount - 1 do
  begin
    Section := AScope[Index];
    case Section.Kind of
      TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection:
        for Inner := 0 to Section.ChildCount - 1 do
          if HasName(Section[Inner].Name, AName) and Active(Section[Inner]) then
          begin
            Take(TCaptureDeclKind.Other, Section[Inner], '');
            Exit(True);
          end;
      TSyntaxKind.RoutineDecl:
        if SameText(Section.Name, AName) and Active(Section) then
        begin
          Take(TCaptureDeclKind.Other, Section, '');
          Exit(True);
        end;
    else
      // Übrige Werte bewusst ohne Wirkung.
    end;
  end;
  VisitInline(AScope);
  if Found then
    Exit(True);
  // Result einer Funktion: Ergebnistyp am Kopf (Routine) bzw. "function" (anonyme Methode).
  if SameText(AName, 'Result') then
  begin
    Result_ := nil;
    if Header <> nil then
      for Index := 0 to Header.ChildCount - 1 do
        if Header[Index].Kind = TSyntaxKind.TypeReference then
          Result_ := Header[Index];
    if (Result_ <> nil) and ((AScope.Kind = TSyntaxKind.RoutineDecl) or (AScope.Name = 'function')) then
    begin
      Take(TCaptureDeclKind.FunctionResult, nil, TRoutineBody.TextOf(AText, Result_));
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Steht ANode als Feldname einer Record-Konstante (X: 1) oder hinter einem Punkt?</summary>
function IsRecordFieldName(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if (ANode.Parent = nil) or (ANode.Parent.Kind <> TSyntaxKind.ParenExpr) then
    Exit;
  Index := TRoutineBody.NextToken(ATokens, TRoutineBody.TokenAt(ATokens, ANode.StartOffset));
  Result := (Index >= 0) and (Index < Length(ATokens)) and ATokens[Index].IsSymbol(':');
end;

function TAnonymousCaptureInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AnonymousCaptureInvalidRuleId, TRuleSeverity.Error,
    'Anonyme Methode erfasst einen var-, out- oder untypisierten Parameter oder Result');
end;

procedure TAnonymousCaptureInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  Lines: TArray<string>;
  LineBreak: string;
  Reported: TList<string>;

  /// <summary>Deklaration von AIdent; AOuter: äußerste anonyme Methode zwischen Bezeichner und Bereich.</summary>
  function Resolve(AIdent: TSyntaxNode; out ADecl: TCaptureDecl; out AOuter: TSyntaxNode): Boolean;
  var
    Node, Scope: TSyntaxNode;
    Path: string;
  begin
    Result := False;
    AOuter := nil;
    Path := TConditionalBranches.PathAt(Paths, TRoutineBody.TokenAt(Tokens, AIdent.StartOffset));
    Node := AIdent;
    while Node.Parent <> nil do
    begin
      // with kann den Namen auf ein Feld umlenken: keine Aussage.
      if (Node.Parent.Kind = TSyntaxKind.WithStatement) and (Node <> Node.Parent[0]) then
        Exit(False);
      if Node.Parent.Kind = TSyntaxKind.AsmBlock then
        Exit(False);
      Node := Node.Parent;
      if not IsCaptureScope(Node) then
        Continue;
      Scope := Node;
      if FindCaptureDecl(AContext.Text, Scope, AIdent.Name, AIdent.StartOffset, Paths, Tokens, Path, ADecl) then
        Exit(AOuter <> nil);
      if Scope.Kind = TSyntaxKind.AnonymousMethod then
        AOuter := Scope;
    end;
  end;

  function KindText(AKind: TCaptureDeclKind): string;
  begin
    case AKind of
      TCaptureDeclKind.VarParam:
        Result := 'var-Parameter';
      TCaptureDeclKind.OutParam:
        Result := 'out-Parameter';
    else
      Result := 'untypisierte Parameter';
    end;
  end;

  function Indent(ALine: Integer): string;
  var
    Text: string;
    Index: Integer;
  begin
    Result := '';
    if (ALine < 0) or (ALine > High(Lines)) then
      Exit;
    Text := Lines[ALine];
    Index := 1;
    while (Index <= Length(Text)) and CharInSet(Text[Index], [' ', #9]) do
      Inc(Index);
    Result := Copy(Text, 1, Index - 1);
  end;

  /// <summary>Steht vor APosition in der Zeile nur Leerraum?</summary>
  function LineStartsAt(const APosition: TTextPosition): Boolean;
  begin
    Result := (APosition.Line <= High(Lines)) and (Trim(Copy(Lines[APosition.Line], 1, APosition.Character)) = '');
  end;

  /// <summary>Folgt hinter APosition in der Zeile nur ein Semikolon, Leerraum oder ein //-Kommentar?</summary>
  function LineEndsAt(const APosition: TTextPosition): Boolean;
  var
    Rest: string;
  begin
    Result := False;
    if APosition.Line > High(Lines) then
      Exit;
    Rest := Trim(Copy(Lines[APosition.Line], APosition.Character + 1, MaxInt));
    if StartsStr(';', Rest) then
      Rest := Trim(Copy(Rest, 2, MaxInt));
    Result := (Rest = '') or StartsStr('//', Rest);
  end;

  /// <summary>Korrektur: Wert vor der Anweisung in eine lokale Variable kopieren, in AMethod nur diese
  /// verwenden und nach der Anweisung zurückschreiben, wenn AMethod schreibt.</summary>
  function CopyFix(const ADecl: TCaptureDecl; AMethod: TSyntaxNode; out AFix: TRuleFix): Boolean;
  var
    Statement, Routine, Section, Block: TSyntaxNode;
    Uses_: TList<TSyntaxNode>;
    Ident: TSyntaxNode;
    Decl: TCaptureDecl;
    Outer: TSyntaxNode;
    Reads, Writes: Boolean;
    Access: TLocalAccess;
    Copy_, StatementIndent, RoutineIndent: string;
    Edits: TArray<TRuleEdit>;
    Index: Integer;
  begin
    Result := False;
    AFix := Default(TRuleFix);
    Routine := ADecl.Scope;
    if (Routine.Kind <> TSyntaxKind.RoutineDecl) or (ADecl.TypeText = '') then
      Exit;
    Block := Routine.FindChild(TSyntaxKind.Block);
    if Block = nil then
      Exit;
    // Anweisung, die die anonyme Methode enthält, direkt in einem Block der Routine.
    Statement := AMethod;
    while (Statement.Parent <> nil) and (Statement.Parent.Kind <> TSyntaxKind.Block) do
      Statement := Statement.Parent;
    if (Statement.Parent = nil) or (ScopeOf(Statement) <> Routine) or not LineStartsAt(Statement.StartPos) or
      not LineEndsAt(Statement.EndPos) then
      Exit;
    Uses_ := TList<TSyntaxNode>.Create;
    try
      AMethod.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, ADecl.Name) then
            Uses_.Add(ANode);
          Result := True;
        end);
      Reads := False;
      Writes := False;
      for Ident in Uses_ do
      begin
        if not Resolve(Ident, Decl, Outer) or (Decl.Scope <> ADecl.Scope) then
          Continue;
        Access := TRoutineLocals.AccessOf(Ident, nil);
        Reads := Reads or (Access <> TLocalAccess.Write);
        Writes := Writes or (Access <> TLocalAccess.Read);
      end;
      if ADecl.Kind = TCaptureDeclKind.FunctionResult then
        Copy_ := TRoutineBody.UniqueName(Tokens, 'Ergebnis')
      else
        Copy_ := TRoutineBody.UniqueName(Tokens, ADecl.Name + 'Kopie');
      RoutineIndent := Indent(Routine.StartPos.Line);
      StatementIndent := Indent(Statement.StartPos.Line);
      Section := nil;
      for Index := 0 to Routine.ChildCount - 1 do
        if Routine[Index].Kind = TSyntaxKind.VarSection then
          Section := Routine[Index];
      if Section <> nil then
        Edits := [TRuleEdit.Create(TTextRange.Create(Section.EndPos.Line + 1, 0, Section.EndPos.Line + 1, 0),
          RoutineIndent + '  ' + Copy_ + ': ' + ADecl.TypeText + ';' + LineBreak)]
      else
        Edits := [TRuleEdit.Create(TTextRange.Create(Block.StartPos.Line, 0, Block.StartPos.Line, 0),
          RoutineIndent + 'var' + LineBreak + RoutineIndent + '  ' + Copy_ + ': ' + ADecl.TypeText + ';' + LineBreak)];
      // out-Parameter und Result haben vorher keinen Wert, der kopiert werden müsste.
      if Reads and (ADecl.Kind in [TCaptureDeclKind.VarParam, TCaptureDeclKind.FunctionResult]) then
        Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Statement.StartPos.Line, 0, Statement.StartPos.Line, 0),
          StatementIndent + Copy_ + ' := ' + ADecl.Name + ';' + LineBreak)];
      for Ident in Uses_ do
        if Resolve(Ident, Decl, Outer) and (Decl.Scope = ADecl.Scope) then
          Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Ident.StartPos, Ident.EndPos), Copy_)];
      if Writes then
        Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Statement.EndPos.Line + 1, 0, Statement.EndPos.Line + 1,
          0), StatementIndent + ADecl.Name + ' := ' + Copy_ + ';' + LineBreak)];
      AFix := TRuleFix.Create('Wert in die lokale Variable ' + Copy_ + ' kopieren', Edits);
      Result := True;
    finally
      Uses_.Free;
    end;
  end;

  procedure CheckIdentifier(AIdent: TSyntaxNode);
  var
    Decl: TCaptureDecl;
    Outer: TSyntaxNode;
    Key, Message: string;
    Fix: TRuleFix;
  begin
    if IsRecordFieldName(Tokens, AIdent) or not Resolve(AIdent, Decl, Outer) or
      (Decl.Kind in [TCaptureDeclKind.None, TCaptureDeclKind.Other]) then
      Exit;
    // Je anonymer Methode und Deklaration eine Meldung.
    Key := IntToStr(Outer.StartOffset) + ':' + IntToStr(Decl.Scope.StartOffset) + ':' + LowerCase(Decl.Name);
    if Reported.Contains(Key) then
      Exit;
    Reported.Add(Key);
    if Decl.Kind = TCaptureDeclKind.FunctionResult then
      Message := 'Result der umgebenden Funktion kann nicht erfasst werden (wie E2555).'
    else
      Message := Format('Der %s %s kann nicht erfasst werden (wie E2555).', [KindText(Decl.Kind), Decl.Name]);
    if CopyFix(Decl, Outer, Fix) then
      AReport.Add(TTextRange.Create(AIdent.StartPos, AIdent.EndPos), Message, TRuleConfidence.High, [Fix])
    else
      AReport.Add(TTextRange.Create(AIdent.StartPos, AIdent.EndPos), Message, TRuleConfidence.High);
  end;

  // Iterativ (Bericht M1).
  procedure Visit(ARoot: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    PendingInAnonymous: TStack<Boolean>;
    Node: TSyntaxNode;
    InAnonymous: Boolean;
    Index: Integer;
  begin
    Pending := TStack<TSyntaxNode>.Create;
    PendingInAnonymous := TStack<Boolean>.Create;
    try
      Pending.Push(ARoot);
      PendingInAnonymous.Push(False);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        InAnonymous := PendingInAnonymous.Pop;
        if InAnonymous and (Node.Kind = TSyntaxKind.Identifier) then
          CheckIdentifier(Node);
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          PendingInAnonymous.Push(InAnonymous or (Node.Kind = TSyntaxKind.AnonymousMethod));
        end;
      end;
    finally
      PendingInAnonymous.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Reported := TList<string>.Create;
  try
    Visit(AContext.Tree.Root);
  finally
    Reported.Free;
  end;
end;

procedure RegisterCaptureRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TCapturedLoopVariableRule.Create);
  ARegistry.Register(TAnonymousCaptureInvalidRule.Create);
end;

end.
