unit Atlas.Common.Rules.Builtin.Flow.HandleLeak;

// Regel handle-leak aus Atlas.Common.Rules.Builtin.Flow (#269): Ein Windows-Handle aus der Tabelle der Paare
// (CreateFile/CloseHandle, GetDC/ReleaseDC …) wird in einer lokalen Variablen geöffnet, und ein Weg erreicht das
// normale Ende der Routine, ohne es zu schließen oder weiterzugeben. Bei if über die Prüfung des Handles (auch über
// einen Merker, Result := H <> 0; if Result then …) folgt der Weg nur dem Zweig, in dem das Öffnen gelang.
// Korrektur: try … finally Schließen end um die folgenden Anweisungen.

interface

uses
  Atlas.Common.Rules.Contract;

type
  THandleLeakRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Paare "Öffnen|Ort|Schließen" aus der Tabelle und der Option pairs ("Öffnen&gt;Schließen" oder
    /// {"open", "close"}).</summary>
    class function Pairs(const AOptions: string): TArray<string>; static;
  end;

const
  HandleLeakRuleId = 'handle-leak';

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
  Atlas.Common.Rules.Builtin.Flow.Shared,
  Atlas.Common.Rules.Builtin.Flow.HandleLeak.Handles,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TFlowHandleLeakText = (AndWord, NeverClosed, NotAlwaysClosed, Add, WrapTry, Title, VerbOne, VerbMany);

const
  cTexts: array[TFlowHandleLeakText] of TAtlasText = (
    (De: ' und '; En: ' and '),
    (De: '%s %s nie mit %s geschlossen (Handle-Leck).'; En: '%s %s never closed with %s (handle leak).'),
    (De: '%s %s nicht auf jedem Weg mit %s geschlossen (Handle-Leck).';
     En: '%s %s not closed with %s on every path (handle leak).'),
    (De: '%s ergänzen'; En: 'Add %s'),
    (De: 'In try … finally %s einschließen'; En: 'Wrap in try … finally %s'),
    (De: 'Windows-Handle wird nicht geschlossen'; En: 'Windows handle is not closed'),
    (De: 'wird'; En: 'is'),
    (De: 'werden'; En: 'are'));

{$SCOPEDENUMS OFF}

/// <summary>Was ein Knoten selbst auswertet: einfache Anweisungen ganz, bei if, case und Schleifen die Bedingung
/// bzw. der Kopf, with ganz (with H do … gibt das Handle weiter).</summary>
function NodeParts(ANode: TFlowNode): TArray<TSyntaxNode>;
begin
  Result := nil;
  if ANode.Syntax = nil then
  begin
    Exit;
  end;
  if ANode.Syntax.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement,
    TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.WithStatement] then
  begin
    Result := [ANode.Syntax];
  end
  else if ANode.Kind = TFlowNodeKind.Condition then
  begin
    Result := OwnParts(ANode.Syntax);
  end;
end;

function InRange(AInner, AOuter: TSyntaxNode): Boolean;
begin
  Result := (AInner <> nil) and (AOuter <> nil) and (AInner.StartOffset >= AOuter.StartOffset) and
    (AInner.EndOffset <= AOuter.EndOffset);
end;

/// <summary>Bedingung (erster Ausdruck) und then-Zweig (erste Anweisung) einer if-Anweisung.</summary>
procedure SplitIf(AIf: TSyntaxNode; out ACondition, AThen: TSyntaxNode);
var
  Index: Integer;
begin
  ACondition := nil;
  AThen := nil;
  for Index := 0 to AIf.ChildCount - 1 do
  begin
    if not (AIf[Index].Kind in FlowStatementKinds) then
    begin
      if ACondition = nil then
      begin
        ACondition := AIf[Index];
      end;
    end
    else if AThen = nil then
    begin
      AThen := AIf[Index];
    end;
  end;
end;

/// <summary>ANode ist AName := ….</summary>
function IsAssignTo(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, AName);
end;

/// <summary>Zuweisungen AName := … unter ABody (ohne eingebettete Routinen), die zwischen AFrom und ATo stehen.
/// </summary>
function AssignmentsTo(ABody: TSyntaxNode; const AName: string; AFrom, ATo: Integer): TArray<TSyntaxNode>;
var
  Found: TArray<TSyntaxNode>;
  Body: TSyntaxNode;
  Name: string;
  From, Till: Integer;
begin
  Found := nil;
  Body := ABody;
  Name := AName;
  From := AFrom;
  Till := ATo;
  // Iterativ (Bericht M1).
  ABody.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode <> Body) and IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if IsAssignTo(ANode, Name) and (ANode.StartOffset > From) and (ANode.EndOffset < Till) then
      begin
        Found := Found + [ANode];
      end;
    end);
  Result := Found;
end;

/// <summary>Merker als Bedingung (#1519): Result := H &lt;&gt; INVALID_HANDLE_VALUE; if Result then …. Die
/// Bedingung ist eine Variable (auch not X oder in Klammern), der ABody zwischen dem Öffnen und dem if genau
/// einmal einen Ausdruck zuweist; dann gilt dessen Bedeutung. Spätere Zuweisungen (im then-Zweig) zählen nicht.
/// 0 sonst.</summary>
function FlagSuccess(ABody, AIf, ACondition: TSyntaxNode; const AHandle: TOpenedHandle;
  AOpenCall: TSyntaxNode): Integer;
var
  Node: TSyntaxNode;
  Sign: Integer;
  Assignments: TArray<TSyntaxNode>;
begin
  Result := 0;
  Sign := 1;
  Node := ACondition;
  while (Node.ChildCount = 1) and ((Node.Kind = TSyntaxKind.ParenExpr) or
    ((Node.Kind = TSyntaxKind.UnaryExpr) and SameText(Node.Name, 'not'))) do
  begin
    if Node.Kind = TSyntaxKind.UnaryExpr then
    begin
      Sign := -Sign;
    end;
    Node := Node[0];
  end;
  if (ABody = nil) or (Node.Kind <> TSyntaxKind.Identifier) then
  begin
    Exit;
  end;
  Assignments := AssignmentsTo(ABody, Node.Name, AOpenCall.EndOffset, AIf.StartOffset);
  if Length(Assignments) = 1 then
  begin
    Result := Sign * OpenSuccess(Assignments[0][1], AHandle, AOpenCall);
  end;
end;

/// <summary>Variablen und Inline-Variablen der Routine (ohne Parameter und eingebettete Routinen).</summary>
function DeclaredLocals(ARoutine: TSyntaxNode): TArray<string>;
var
  Names: TArray<string>;
  Routine: TSyntaxNode;
begin
  Names := nil;
  Routine := ARoutine;
  // Iterativ (Bericht M1).
  ARoutine.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    var
      Name: string;
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ANode <> Routine) and IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar] then
      begin
        for Name in ANode.Name.Split([',']) do
        begin
          Names := Names + [Trim(Name)];
        end;
      end;
    end);
  Result := Names;
end;

/// <summary>Pfade der Handles, mit und verbunden.</summary>
function HandleNames(const AHandles: TArray<TOpenedHandle>): string;
var
  Handle: TOpenedHandle;
begin
  Result := '';
  for Handle in AHandles do
  begin
    if Result <> '' then
    begin
      Result := Result + cTexts[TFlowHandleLeakText.AndWord].Text;
    end;
    Result := Result + Handle.Path;
  end;
end;

function LeakMessage(const ALeaked: TArray<TOpenedHandle>; ANever: Boolean): string;
var
  Verb: string;
begin
  Verb := cTexts[TFlowHandleLeakText.VerbOne].Text;
  if Length(ALeaked) > 1 then
  begin
    Verb := cTexts[TFlowHandleLeakText.VerbMany].Text;
  end;
  if ANever then
  begin
    Result := cTexts[TFlowHandleLeakText.NeverClosed].Fmt([HandleNames(ALeaked), Verb,
      ALeaked[0].CloseName]);
  end
  else
  begin
    Result := cTexts[TFlowHandleLeakText.NotAlwaysClosed].Fmt([HandleNames(ALeaked), Verb,
      ALeaked[0].CloseName]);
  end;
end;

type
  /// <summary>Prüfung einer Unit für handle-leak; hält die Tabelle, die Routine, ihren Graphen und ihre lokalen
  /// Variablen.</summary>
  THandleCheck = class
  strict private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTable: TArray<THandlePair>;
    FRoutine: TSyntaxNode;
    FGraph: TControlFlowGraph;
    FLocals: TArray<string>;
    FLineBreak: string;
    function PairOf(const AName: string; out APair: THandlePair): Boolean;
    function NewHandle(const APair: THandlePair; ACall: TSyntaxNode; const ARoot, APath: string): TOpenedHandle;
    procedure AddArgumentHandles(const APair: THandlePair; ACall: TSyntaxNode; AIndex: Integer;
      const AFields: TArray<string>; var AHandles: TArray<TOpenedHandle>);
    function ArgumentHandles(const APair: THandlePair; ACall: TSyntaxNode): TArray<TOpenedHandle>;
    function Opened(ACall: TSyntaxNode; const ATarget: string; out AHandles: TArray<TOpenedHandle>): Boolean;
    function IfVerdict(ANode: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode;
      out AThen: TSyntaxNode): Integer;
    function Followed(ANode: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): TArray<TFlowNode>;
    function StopsHandle(ANode: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Boolean;
    function LeaksFrom(AOpen: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Boolean;
    function ClosedAnywhere(const AHandle: TOpenedHandle): Boolean;
    function PositionAt(AOffset: Integer): TTextPosition;
    function ClosingLines(const AHandles: TArray<TOpenedHandle>; const AOuter: string): string;
    function AppendFix(AStatement: TSyntaxNode; const AHandles: TArray<TOpenedHandle>;
      const AOuter: string): TArray<TRuleFix>;
    function IndentedBody(ALineStart: Integer; ALast: TSyntaxNode): string;
    function WrapFix(AStatement: TSyntaxNode; const AHandles: TArray<TOpenedHandle>): TArray<TRuleFix>;
    procedure CollectOpens(ARoot: TSyntaxNode; var ACalls: TArray<TSyntaxNode>; var ATargets: TArray<string>);
    procedure NoteTargets(APart: TSyntaxNode; AFirst: Integer; const ACalls: TArray<TSyntaxNode>;
      var ATargets: TArray<string>);
    function LeakedHandles(ANode: TFlowNode; ACall: TSyntaxNode; const AHandles: TArray<TOpenedHandle>;
      out ANever: Boolean): TArray<TOpenedHandle>;
    procedure CheckOpen(ANode: TFlowNode; ACall: TSyntaxNode; const ATarget: string);
    procedure CheckNode(ANode: TFlowNode);
    procedure CheckRoutine(const ACache: IRuleDerivedCache; ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ THandleCheck }

constructor THandleCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FLineBreak := TTextLines.LineBreakOf(AContext.Text);
end;

function THandleCheck.PairOf(const AName: string; out APair: THandlePair): Boolean;
var
  Pair: THandlePair;
begin
  Result := False;
  for Pair in FTable do
  begin
    if not Result and SameRoutine(AName, Pair.Open) then
    begin
      APair := Pair;
      Result := True;
    end;
  end;
end;

function THandleCheck.NewHandle(const APair: THandlePair; ACall: TSyntaxNode; const ARoot,
  APath: string): TOpenedHandle;
begin
  Result.Path := APath;
  Result.Root := ARoot;
  Result.CloseName := Copy(APair.Close, 1, Pos('(', APair.Close) - 1);
  Result.CloseText := StringReplace(APair.Close, '%h', APath, [rfReplaceAll]);
  if (Pos('%0', Result.CloseText) > 0) and (ACall.ChildCount > 1) then
  begin
    Result.CloseText := StringReplace(Result.CloseText, '%0', Trim(SourceText(FContext.Text, ACall[1])),
      [rfReplaceAll]);
  end;
end;

/// <summary>Handle im out-Argument AIndex (Zählung ab 1 unter den Kindern des Aufrufs); bei Feldern (CreateProcess)
/// je Feld eins.</summary>
procedure THandleCheck.AddArgumentHandles(const APair: THandlePair; ACall: TSyntaxNode; AIndex: Integer;
  const AFields: TArray<string>; var AHandles: TArray<TOpenedHandle>);
var
  Arg, Field: string;
begin
  if (AIndex < 1) or (AIndex >= ACall.ChildCount) then
  begin
    Exit;
  end;
  Arg := HandlePath(ACall[AIndex]);
  if (Arg = '') or (Pos('.', Arg) > 0) or not MatchText(Arg, FLocals) then
  begin
    Exit;
  end;
  if AFields = nil then
  begin
    AHandles := AHandles + [NewHandle(APair, ACall, Arg, Arg)];
  end;
  for Field in AFields do
  begin
    AHandles := AHandles + [NewHandle(APair, ACall, Arg, Arg + '.' + Field)];
  end;
end;

/// <summary>Handles in out-Argumenten: Ort wie '4', '0,1' oder '9:hProcess,hThread'.</summary>
function THandleCheck.ArgumentHandles(const APair: THandlePair; ACall: TSyntaxNode): TArray<TOpenedHandle>;
var
  Where, Part: string;
  Fields: TArray<string>;
begin
  Result := nil;
  Fields := nil;
  Where := APair.Where;
  if Pos(':', Where) > 0 then
  begin
    Fields := Copy(Where, Pos(':', Where) + 1, MaxInt).Split([',']);
    Where := Copy(Where, 1, Pos(':', Where) - 1);
  end;
  for Part in Where.Split([',']) do
  begin
    AddArgumentHandles(APair, ACall, StrToIntDef(Part, -1) + 1, Fields, Result);
  end;
end;

/// <summary>Handles, die ACall öffnet; ATarget ist das Ziel einer Zuweisung ('' ohne).</summary>
function THandleCheck.Opened(ACall: TSyntaxNode; const ATarget: string; out AHandles: TArray<TOpenedHandle>): Boolean;
var
  Pair: THandlePair;
begin
  AHandles := nil;
  if not PairOf(CallName(FContext.Text, ACall), Pair) then
  begin
    Exit(False);
  end;
  if Pair.Where <> 'r' then
  begin
    AHandles := ArgumentHandles(Pair, ACall);
  end
  else if (ATarget <> '') and MatchText(ATarget, FLocals) then
  begin
    AHandles := AHandles + [NewHandle(Pair, ACall, ATarget, ATarget)];
  end;
  Result := AHandles <> nil;
end;

/// <summary>Bedeutet die Bedingung des if ANode, dass das Öffnen gelang (1) oder misslang (-1)? 0 sonst.
/// </summary>
function THandleCheck.IfVerdict(ANode: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode;
  out AThen: TSyntaxNode): Integer;
var
  Condition: TSyntaxNode;
begin
  Result := 0;
  AThen := nil;
  if (ANode.Kind <> TFlowNodeKind.Condition) or (ANode.Syntax.Kind <> TSyntaxKind.IfStatement) then
  begin
    Exit;
  end;
  SplitIf(ANode.Syntax, Condition, AThen);
  if Condition <> nil then
  begin
    Result := OpenSuccess(Condition, AHandle, AOpenCall);
  end;
  if (Result = 0) and (Condition <> nil) then
  begin
    Result := FlagSuccess(FRoutine.FindChild(TSyntaxKind.Block), ANode.Syntax, Condition, AHandle, AOpenCall);
  end;
end;

/// <summary>Nachfolger, denen der Weg mit offenem Handle folgt: bei if über die Prüfung des Handles nur der
/// Zweig, in dem das Öffnen gelang.</summary>
function THandleCheck.Followed(ANode: TFlowNode; const AHandle: TOpenedHandle;
  AOpenCall: TSyntaxNode): TArray<TFlowNode>;
var
  Next: TFlowNode;
  ThenPart: TSyntaxNode;
  Verdict: Integer;
  Follows: Boolean;
begin
  Result := nil;
  Verdict := IfVerdict(ANode, AHandle, AOpenCall, ThenPart);
  for Next in ANode.Successors do
  begin
    Follows := not ANode.IsImplicitRaiseEdge(Next) and (Next <> FGraph.RaiseExit);
    if Follows and (Verdict <> 0) then
    begin
      Follows := InRange(Next.Syntax, ThenPart) = (Verdict > 0);
    end;
    if Follows then
    begin
      Result := Result + [Next];
    end;
  end;
end;

/// <summary>Schließt ANode das Handle, gibt es weiter oder weist ihm neu zu (dann wird das alte hier nicht weiter
/// verfolgt)?</summary>
function THandleCheck.StopsHandle(ANode: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Boolean;
var
  Part, Syntax: TSyntaxNode;
begin
  Result := False;
  for Part in NodeParts(ANode) do
  begin
    Result := Result or ClosesHandle(FContext.Text, Part, AHandle) or
      PassesOn(FContext.Text, Part, AHandle, AOpenCall, FLocals);
  end;
  Syntax := ANode.Syntax;
  Result := Result or ((Syntax <> nil) and (Syntax.Kind = TSyntaxKind.AssignStatement) and
    (Syntax.ChildCount = 2) and SameText(HandlePath(Syntax[0]), AHandle.Path));
end;

/// <summary>Erreicht ein Weg vom Öffnen das normale Ende, ohne das Handle zu schließen oder weiterzugeben?
/// </summary>
function THandleCheck.LeaksFrom(AOpen: TFlowNode; const AHandle: TOpenedHandle; AOpenCall: TSyntaxNode): Boolean;
var
  Visited: TArray<Boolean>;
  Queue: TArray<TFlowNode>;
  Head: Integer;
  Current: TFlowNode;
begin
  Result := False;
  SetLength(Visited, FGraph.Nodes.Count);
  Queue := Followed(AOpen, AHandle, AOpenCall);
  Head := 0;
  while not Result and (Head < Length(Queue)) do
  begin
    Current := Queue[Head];
    Inc(Head);
    if Visited[Current.Index] or (Current = AOpen) then
    begin
      Continue;
    end;
    Visited[Current.Index] := True;
    Result := Current = FGraph.ExitNode;
    if not Result and not StopsHandle(Current, AHandle, AOpenCall) then
    begin
      Queue := Queue + Followed(Current, AHandle, AOpenCall);
    end;
  end;
end;

/// <summary>Schließt die Routine das Handle irgendwo (im Rumpf, ohne eingebettete Routinen)?</summary>
function THandleCheck.ClosedAnywhere(const AHandle: TOpenedHandle): Boolean;
var
  Body: TSyntaxNode;
begin
  Body := FRoutine.FindChild(TSyntaxKind.Block);
  Result := (Body <> nil) and ClosesHandle(FContext.Text, Body, AHandle);
end;

function THandleCheck.PositionAt(AOffset: Integer): TTextPosition;
var
  Index, Line, LineStart: Integer;
begin
  Line := 0;
  LineStart := 0;
  for Index := 1 to AOffset do
  begin
    if FContext.Text[Index] = #10 then
    begin
      Inc(Line);
      LineStart := Index;
    end;
  end;
  Result := TTextPosition.Create(Line, AOffset - LineStart);
end;

/// <summary>Schließen in umgekehrter Reihenfolge: zuletzt geöffnet, zuerst geschlossen (PI.hThread vor
/// PI.hProcess).</summary>
function THandleCheck.ClosingLines(const AHandles: TArray<TOpenedHandle>; const AOuter: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := High(AHandles) downto 0 do
  begin
    Result := Result + AOuter + '  ' + AHandles[Index].CloseText + ';' + FLineBreak;
  end;
end;

/// <summary>Nichts nach dem Öffnen: nur das Schließen anhängen.</summary>
function THandleCheck.AppendFix(AStatement: TSyntaxNode; const AHandles: TArray<TOpenedHandle>;
  const AOuter: string): TArray<TRuleFix>;
var
  Index: Integer;
  Body: string;
begin
  Body := '';
  for Index := High(AHandles) downto 0 do
  begin
    Body := Body + ';' + FLineBreak + AOuter + AHandles[Index].CloseText;
  end;
  Result := [TRuleFix.Create(cTexts[TFlowHandleLeakText.Add].Fmt([AHandles[0].CloseName]),
    [TRuleEdit.Create(TTextRange.Create(AStatement.EndPos, AStatement.EndPos), Body)])];
end;

/// <summary>Zeilen ab ALineStart bis zum Ende von ALast, zwei Stellen weiter eingerückt.</summary>
function THandleCheck.IndentedBody(ALineStart: Integer; ALast: TSyntaxNode): string;
var
  Line: string;
begin
  Result := '';
  for Line in Copy(FContext.Text, ALineStart + 1, ALast.EndOffset - ALineStart).Replace(#13#10, #10).Split([#10]) do
  begin
    if Trim(Line) = '' then
    begin
      Result := Result + FLineBreak;
    end
    else
    begin
      Result := Result + '  ' + Line + FLineBreak;
    end;
  end;
  // Die letzte Anweisung endet vor ihrem Semikolon; das alte Semikolon steht danach hinter end.
  if not Result.TrimRight.EndsWith(';') then
  begin
    Result := Result.TrimRight + ';' + FLineBreak;
  end;
end;

/// <summary>Korrektur: die Anweisungen nach dem Öffnen bis zum Ende ihres Blocks in try … finally Schließen end.
/// </summary>
function THandleCheck.WrapFix(AStatement: TSyntaxNode; const AHandles: TArray<TOpenedHandle>): TArray<TRuleFix>;
var
  Block, First, Last: TSyntaxNode;
  Position, LineStart: Integer;
  Outer, Inner: string;
begin
  Result := nil;
  Block := AStatement.Parent;
  if (Block = nil) or (Block.Kind <> TSyntaxKind.Block) then
  begin
    Exit;
  end;
  Position := PositionIn(Block, AStatement);
  if (Position < 0) or not LineIndent(FContext.Text, AStatement, Outer) then
  begin
    Exit;
  end;
  if Position = Block.ChildCount - 1 then
  begin
    Result := AppendFix(AStatement, AHandles, Outer);
    Exit;
  end;
  First := Block[Position + 1];
  Last := Block[Block.ChildCount - 1];
  if (First.Kind = TSyntaxKind.EmptyStatement) or not LineIndent(FContext.Text, First, Inner) then
  begin
    Exit;
  end;
  LineStart := First.StartOffset - Length(Inner);
  Result := [TRuleFix.Create(cTexts[TFlowHandleLeakText.WrapTry].Fmt([AHandles[0].CloseName]),
    [TRuleEdit.Create(TTextRange.Create(PositionAt(LineStart), Last.EndPos),
    Outer + 'try' + FLineBreak + IndentedBody(LineStart, Last) + Outer + 'finally' + FLineBreak +
    ClosingLines(AHandles, Outer) + Outer + 'end')])];
end;

/// <summary>Aufrufe unter ARoot, die Handles öffnen; ihr Ziel ist zunächst ''.</summary>
procedure THandleCheck.CollectOpens(ARoot: TSyntaxNode; var ACalls: TArray<TSyntaxNode>;
  var ATargets: TArray<string>);
var
  Calls: TArray<TSyntaxNode>;
  Call: TSyntaxNode;
begin
  Calls := nil;
  // Iterativ (Bericht M1).
  ARoot.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    var
      Pair: THandlePair;
    begin
      Result := TSyntaxSearchStep.Descend;
      if IsRoutineBody(ANode) then
      begin
        Result := TSyntaxSearchStep.Skip;
      end
      else if (ANode.Kind = TSyntaxKind.Call) and PairOf(CallName(FContext.Text, ANode), Pair) then
      begin
        Calls := Calls + [ANode];
      end;
    end);
  for Call in Calls do
  begin
    ACalls := ACalls + [Call];
    ATargets := ATargets + [''];
  end;
end;

/// <summary>H := CreateFile(…) bzw. var H := CreateFile(…): das Ziel nimmt das Handle auf.</summary>
procedure THandleCheck.NoteTargets(APart: TSyntaxNode; AFirst: Integer; const ACalls: TArray<TSyntaxNode>;
  var ATargets: TArray<string>);
var
  Index: Integer;
  IsAssign: Boolean;
begin
  IsAssign := (APart.Kind = TSyntaxKind.AssignStatement) and (APart.ChildCount = 2) and
    (APart[0].Kind = TSyntaxKind.Identifier);
  for Index := AFirst to High(ACalls) do
  begin
    if IsAssign and (ACalls[Index] = APart[1]) then
    begin
      ATargets[Index] := APart[0].Name;
    end
    else if (APart.Kind = TSyntaxKind.InlineVar) and (ACalls[Index].Parent = APart) then
    begin
      ATargets[Index] := Trim(APart.Name);
    end;
  end;
end;

/// <summary>Handles aus AHandles, die ein Weg vom Öffnen offen lässt; ANever: keins davon wird in der Routine je
/// geschlossen.</summary>
function THandleCheck.LeakedHandles(ANode: TFlowNode; ACall: TSyntaxNode; const AHandles: TArray<TOpenedHandle>;
  out ANever: Boolean): TArray<TOpenedHandle>;
var
  Handle: TOpenedHandle;
begin
  Result := nil;
  ANever := True;
  for Handle in AHandles do
  begin
    if LeaksFrom(ANode, Handle, ACall) then
    begin
      Result := Result + [Handle];
      ANever := ANever and not ClosedAnywhere(Handle);
    end;
  end;
end;

procedure THandleCheck.CheckOpen(ANode: TFlowNode; ACall: TSyntaxNode; const ATarget: string);
var
  Handles, Leaked: TArray<TOpenedHandle>;
  Never: Boolean;
  Fixes: TArray<TRuleFix>;
  Statement: TSyntaxNode;
begin
  if not Opened(ACall, ATarget, Handles) then
  begin
    Exit;
  end;
  Leaked := LeakedHandles(ANode, ACall, Handles, Never);
  if Leaked = nil then
  begin
    Exit;
  end;
  Fixes := nil;
  Statement := ANode.Syntax;
  if Never and (ANode.Kind = TFlowNodeKind.Statement) and (Statement.StartPos.Line = Statement.EndPos.Line) then
  begin
    Fixes := WrapFix(Statement, Leaked);
  end;
  FReport.Add(NodeRange(ACall), LeakMessage(Leaked, Never), TRuleConfidence.Medium, Fixes);
end;

procedure THandleCheck.CheckNode(ANode: TFlowNode);
var
  Calls: TArray<TSyntaxNode>;
  Targets: TArray<string>;
  Part: TSyntaxNode;
  Index, First: Integer;
begin
  // with: die Anweisungen darin sind eigene Knoten.
  if (ANode.Syntax = nil) or not (ANode.Kind in [TFlowNodeKind.Statement, TFlowNodeKind.Condition]) or
    (ANode.Syntax.Kind = TSyntaxKind.WithStatement) then
  begin
    Exit;
  end;
  Calls := nil;
  Targets := nil;
  for Part in NodeParts(ANode) do
  begin
    First := Length(Calls);
    CollectOpens(Part, Calls, Targets);
    NoteTargets(Part, First, Calls, Targets);
  end;
  for Index := 0 to High(Calls) do
  begin
    CheckOpen(ANode, Calls[Index], Targets[Index]);
  end;
end;

procedure THandleCheck.CheckRoutine(const ACache: IRuleDerivedCache; ARoutine: TSyntaxNode);
var
  Node: TFlowNode;
begin
  FRoutine := ARoutine;
  FLocals := DeclaredLocals(ARoutine);
  if FLocals = nil then
  begin
    Exit;
  end;
  FGraph := TRuleDerived.Graph(ACache, FContext, ARoutine);
  if not FGraph.Complete then
  begin
    Exit;
  end;
  for Node in FGraph.Nodes do
  begin
    CheckNode(Node);
  end;
end;

procedure THandleCheck.Run;
var
  Cache: IRuleDerivedCache;
  Routine: TSyntaxNode;
begin
  if FContext.Tree = nil then
  begin
    Exit;
  end;
  FTable := HandleTable(HandlePairs(FContext.Options));
  Cache := TRuleDerived.Open(FContext);
  for Routine in TRuleDerived.Routines(Cache, FContext) do
  begin
    CheckRoutine(Cache, Routine);
  end;
end;

{ THandleLeakRule }

function THandleLeakRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(HandleLeakRuleId, TRuleSeverity.Warning, cTexts[TFlowHandleLeakText.Title].Text);
end;

class function THandleLeakRule.Pairs(const AOptions: string): TArray<string>;
begin
  Result := HandlePairs(AOptions);
end;

procedure THandleLeakRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Check: THandleCheck;
begin
  Check := THandleCheck.Create(AContext, AReport);
  try
    Check.Run;
  finally
    Check.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Flow.HandleLeak', cTexts);

end.
