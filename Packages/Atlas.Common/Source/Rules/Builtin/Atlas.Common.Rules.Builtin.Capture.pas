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
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TCaptureText = (CopyPerIteration, CapturesVariable, LoopTitle, ParamTitle, UntypedParam, ResultCapture,
    CannotCapture, VarParam, OutParam, CopyValue);

const
  cTexts: array[TCaptureText] of TAtlasText = (
    (De: 'Variable "%s" je Durchlauf kopieren'; En: 'Copy variable "%s" per iteration'),
    (De: 'Die anonyme Methode erfasst "%s", nicht seinen Wert; bis sie läuft, hat "%s" womöglich schon einen anderen ' +
      'Wert';
     En: 'The anonymous method captures "%s", not its value; by the time it runs, "%s" may already have a different ' +
      'value'),
    (De: 'Anonyme Methode erfasst eine Variable, die sich vor dem verzögerten Aufruf noch ändert';
     En: 'Anonymous method captures a variable that still changes before the deferred call'),
    (De: 'Anonyme Methode erfasst einen var-, out- oder untypisierten Parameter oder Result';
     En: 'Anonymous method captures a var, out or untyped parameter or Result'),
    (De: 'untypisierte Parameter'; En: 'untyped parameter'),
    (De: 'Result der umgebenden Funktion kann nicht erfasst werden (wie E2555).';
     En: 'Result of the enclosing function cannot be captured (like E2555).'),
    (De: 'Der %s %s kann nicht erfasst werden (wie E2555).'; En: 'The %s %s cannot be captured (like E2555).'),
    (De: 'var-Parameter'; En: 'var parameter'),
    (De: 'out-Parameter'; En: 'out parameter'),
    (De: 'Wert in die lokale Variable %s kopieren'; En: 'Copy the value into the local variable %s'));

{$SCOPEDENUMS OFF}

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
  begin
    Result := Result + [TCapturedLoopVariableRule.DefaultDeferredApis[Index]];
  end;
  if AOptions = '' then
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    Items := TJSONObject(Value).GetValue('deferredApis');
    if Items is TJSONArray then
    begin
      for Item in TJSONArray(Items) do
      begin
        if Item is TJSONString then
        begin
          Result := Result + [Item.Value];
        end;
      end;
    end;
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
  begin
    if SameText(ACallee, Api) or EndsText('.' + Api, ACallee) then
    begin
      Exit(True);
    end;
  end;
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
  begin
    Exit;
  end;
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
      begin
        Methods := Methods + [AVisited];
      end;
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
      begin
        List.Add(AVisited);
      end;
      Result := True;
    end);
end;

function NextToken(const AContext: TRuleContext; AOffset: Integer; out AToken: TPascalToken): Boolean;
var
  mIndex: Integer;
begin
  // Binär zum ersten Token ab AOffset statt ab Dateianfang (#1323).
  mIndex := AContext.Tree.FirstTokenFrom(AOffset);
  while mIndex <= High(AContext.Tree.Tokens) do
  begin
    if not (AContext.Tree.Tokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      AToken := AContext.Tree.Tokens[mIndex];
      Exit(True);
    end;
    Inc(mIndex);
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
    begin
      Exit;
    end;
    if Result.Kind = TSyntaxKind.RoutineDecl then
    begin
      Exit(nil);
    end;
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
    begin
      if Trim(Name) <> '' then
      begin
        Local.Name := Trim(Name);
        Local.TypeName := ATypeName;
        Result := Result + [Local];
      end;
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
        begin
          Continue;
        end;
        if Node.Kind = TSyntaxKind.InlineVar then
        begin
          TypeNode := Node.FindChild(TSyntaxKind.TypeReference);
          if TypeNode <> nil then
          begin
            AddNames(Node.Name, TypeNode.Name);
          end
          else
          begin
            AddNames(Node.Name, '');
          end;
        end
        else if Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
        begin
          AddNames(Node.Name, '');
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
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
    begin
      Continue;
    end;
    for Inner := 0 to Section.ChildCount - 1 do
    begin
      if Section[Inner].Kind = TSyntaxKind.VarDecl then
      begin
        TypeNode := Section[Inner].FindChild(TSyntaxKind.TypeReference);
        if (TypeNode <> nil) and (TypeNode.ChildCount = 0) then
        begin
          AddNames(Section[Inner].Name, TypeNode.Name);
        end
        else
        begin
          AddNames(Section[Inner].Name, '');
        end;
      end;
    end;
  end;
  Visit(ABlock);
end;

function FindLocal(const ALocals: TArray<TLocal>; const AName: string; out ALocal: TLocal): Boolean;
var
  Local: TLocal;
begin
  for Local in ALocals do
  begin
    if SameText(Local.Name, AName) then
    begin
      ALocal := Local;
      Exit(True);
    end;
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
  begin
    Exit(True);
  end;
  Syntax := ANode.Syntax;
  Result := False;
  if (Syntax = nil) or (Syntax.Kind <> TSyntaxKind.CallStatement) or (Syntax.ChildCount = 0) then
  begin
    Exit;
  end;
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
    begin
      if not Seen[Next.Index] then
      begin
        Seen[Next.Index] := True;
        Stack.Push(Next);
      end;
    end;
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      if Writes(Node, AName) then
      begin
        Exit(True);
      end;
      for Next in Node.Successors do
      begin
        if not Seen[Next.Index] then
        begin
          Seen[Next.Index] := True;
          Stack.Push(Next);
        end;
      end;
    end;
  finally
    Stack.Free;
  end;
end;

/// <summary>Ist ACall Inc(AName) bzw. Dec(AName)?</summary>
function IsIncDecOf(ACall: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (ACall.Kind = TSyntaxKind.Call) and (ACall.ChildCount > 1) and (ACall[0].Kind = TSyntaxKind.Identifier) and
    MatchText(ACall[0].Name, ['Inc', 'Dec']);
  Result := Result and (ACall[1].Kind = TSyntaxKind.Identifier) and SameText(ACall[1].Name, AName);
end;

/// <summary>Schreibt die Anweisung ANode AName (Zuweisung, Inc/Dec)?</summary>
function WritesName(ANode: TSyntaxNode; const AName: string): Boolean;
begin
  if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount > 0) then
  begin
    Result := (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, AName);
  end
  else
  begin
    Result := (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount > 0) and IsIncDecOf(ANode[0], AName);
  end;
end;

/// <summary>Schreibt die anonyme Methode AMethod selbst AName (Zuweisung, Inc/Dec)? Dann ist die Variable
/// gemeinsamer Zustand (ein Ereignis sammelt dort, was es sieht), kein Wert, den sie beim Erzeugen festhalten
/// soll.</summary>
function WrittenInside(AMethod: TSyntaxNode; const AName: string): Boolean;
var
  mStack: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  mStack := TStack<TSyntaxNode>.Create;
  try
    mStack.Push(AMethod);
    while not Result and (mStack.Count > 0) do
    begin
      mNode := mStack.Pop;
      Result := WritesName(mNode, AName);
      for mIndex := 0 to mNode.ChildCount - 1 do
      begin
        mStack.Push(mNode[mIndex]);
      end;
    end;
  finally
    mStack.Free;
  end;
end;

type
  /// <summary>Prüfung von captured-loop-variable für eine Datei; Routine, lokale Variablen und Graph der
  /// gerade geprüften Routine.</summary>
  TLoopCaptureCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FApis: TArray<string>;
    FRoutine: TSyntaxNode;
    FVariables: TArray<TLocal>;
    // Graph der Routine, erst bei Bedarf; gehört dem Cache.
    FGraph: TControlFlowGraph;
    /// <summary>Ändert sich ALocal, bevor AMethod verzögert läuft?</summary>
    function ChangesLater(AMethod: TSyntaxNode; const ALocal: TLocal): Boolean;
    /// <summary>Nutzt AMethod außer ALocal weitere lokale Variablen? Die würden in der Hilfsfunktion fehlen.
    /// </summary>
    function UsesOtherLocals(AIdentifiers: TList<TSyntaxNode>; const ALocal: TLocal): Boolean;
    /// <summary>Rumpf von AMethod mit AValue statt ALocal, von hinten ersetzt.</summary>
    function BodyWithValue(AMethod: TSyntaxNode; AIdentifiers: TList<TSyntaxNode>; const ALocal: TLocal): string;
    /// <summary>Text vor ARoutine in ihrer Zeile, wenn er nur aus Leerraum besteht; False sonst.</summary>
    function RoutineIndent(out AIndent: string): Boolean;
    /// <summary>Korrektur "Variable je Durchlauf kopieren"; False, wenn sie nicht sicher möglich ist.</summary>
    function CopyPerIterationFix(AMethod: TSyntaxNode; const ALocal: TLocal; out AFix: TRuleFix): Boolean;
    procedure ReportCapture(AIdentifier, AMethod: TSyntaxNode; const ALocal: TLocal; AConfidence: TRuleConfidence);
    procedure CheckMethod(AMethod: TSyntaxNode; AConfidence: TRuleConfidence);
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

constructor TLoopCaptureCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FApis := DeferredApis(AContext.Options);
  // Routinen, Signaturen und Graphen teilt der Lauf mit den anderen Regeln (Review P-03).
  FCache := TRuleDerived.Open(AContext);
end;

function TLoopCaptureCheck.UsesOtherLocals(AIdentifiers: TList<TSyntaxNode>; const ALocal: TLocal): Boolean;
var
  mIdentifier: TSyntaxNode;
  mOther: TLocal;
begin
  Result := False;
  for mIdentifier in AIdentifiers do
  begin
    Result := Result or not SameText(mIdentifier.Name, ALocal.Name) and
      FindLocal(FVariables, mIdentifier.Name, mOther);
  end;
end;

function TLoopCaptureCheck.BodyWithValue(AMethod: TSyntaxNode; AIdentifiers: TList<TSyntaxNode>;
  const ALocal: TLocal): string;
var
  mIndex, mPosition: Integer;
  mIdentifier: TSyntaxNode;
begin
  Result := Copy(FContext.Text, AMethod.StartOffset + 1, AMethod.EndOffset - AMethod.StartOffset);
  for mIndex := AIdentifiers.Count - 1 downto 0 do
  begin
    mIdentifier := AIdentifiers[mIndex];
    if SameText(mIdentifier.Name, ALocal.Name) then
    begin
      mPosition := mIdentifier.StartOffset - AMethod.StartOffset;
      Result := Copy(Result, 1, mPosition) + 'AValue' + Copy(Result, mPosition + Length(ALocal.Name) + 1, MaxInt);
    end;
  end;
end;

function TLoopCaptureCheck.RoutineIndent(out AIndent: string): Boolean;
var
  mLineStart: Integer;
begin
  mLineStart := FRoutine.StartOffset;
  while (mLineStart > 0) and (FContext.Text[mLineStart] <> #10) do
  begin
    Dec(mLineStart);
  end;
  AIndent := Copy(FContext.Text, mLineStart + 1, FRoutine.StartOffset - mLineStart);
  Result := Trim(AIndent) = '';
end;

function TLoopCaptureCheck.CopyPerIterationFix(AMethod: TSyntaxNode; const ALocal: TLocal;
  out AFix: TRuleFix): Boolean;
var
  mIdentifiers: TList<TSyntaxNode>;
  mBlock: TSyntaxNode;
  mBody, mLineBreak, mIndent, mFunctionName: string;
  mInsert: TTextPosition;
begin
  Result := False;
  AFix := Default(TRuleFix);
  mBlock := FRoutine.FindChild(TSyntaxKind.Block);
  // Nur procedure ohne Parameter (TProc) und mit bekanntem Typ.
  if (ALocal.TypeName = '') or (FRoutine.FindChild(TSyntaxKind.RoutineHeader) = nil) or (mBlock = nil) or
    not SameText(AMethod.Name, 'procedure') or (AMethod.FindChild(TSyntaxKind.Parameters) <> nil) then
  begin
    Exit;
  end;
  mIdentifiers := TList<TSyntaxNode>.Create;
  try
    CollectIdentifiers(AMethod, mIdentifiers);
    if UsesOtherLocals(mIdentifiers, ALocal) then
    begin
      Exit;
    end;
    mBody := BodyWithValue(AMethod, mIdentifiers, ALocal);
  finally
    mIdentifiers.Free;
  end;
  // Einrückung der Routine; die lokale Funktion steht direkt vor ihrem begin.
  mInsert := TRuleDerived.PositionAt(FCache, FContext, mBlock.StartOffset);
  if not RoutineIndent(mIndent) or (mInsert.Character <> Length(mIndent)) then
  begin
    Exit;
  end;
  mLineBreak := TTextLines.LineBreakOf(FContext.Text);
  mFunctionName := 'Capture' + ALocal.Name;
  AFix := TRuleFix.Create(cTexts[TCaptureText.CopyPerIteration].Fmt([ALocal.Name]), [
    TRuleEdit.Create(TTextRange.Create(TTextPosition.Create(mInsert.Line, 0), TTextPosition.Create(mInsert.Line, 0)),
      mIndent + '  function ' + mFunctionName + '(const AValue: ' + ALocal.TypeName + '): TProc;' + mLineBreak +
      mIndent + '  begin' + mLineBreak +
      mIndent + '    Result := ' + mBody + ';' + mLineBreak +
      mIndent + '  end;' + mLineBreak + mLineBreak),
    TRuleEdit.Create(TRuleDerived.OffsetRange(FCache, FContext, AMethod.StartOffset, AMethod.EndOffset),
      mFunctionName + '(' + ALocal.Name + ')')]);
  Result := True;
end;

function TLoopCaptureCheck.ChangesLater(AMethod: TSyntaxNode; const ALocal: TLocal): Boolean;
var
  mLoop: TSyntaxNode;
  mStart: TFlowNode;
begin
  mLoop := EnclosingLoop(AMethod, ALocal.Name);
  if mLoop <> nil then
  begin
    // for I := … mit äußerer Variable lässt sich nicht erfassen (E2555).
    Result := (mLoop.Kind <> TSyntaxKind.ForStatement) or IsInlineLoop(FContext, mLoop);
  end
  else if WrittenInside(AMethod, ALocal.Name) then
  begin
    // Ereignis, das in die Variable schreibt (Log := Log + …, Inc(Zähler)): gewollt geteilt.
    Result := False;
  end
  else
  begin
    if FGraph = nil then
    begin
      FGraph := TRuleDerived.Graph(FCache, FContext, FRoutine);
    end;
    mStart := FlowNodeOf(FGraph, AMethod);
    Result := FGraph.Complete and (mStart <> nil) and WrittenAfter(FGraph, mStart, ALocal.Name);
  end;
end;

procedure TLoopCaptureCheck.ReportCapture(AIdentifier, AMethod: TSyntaxNode; const ALocal: TLocal;
  AConfidence: TRuleConfidence);
var
  mMessage: string;
  mFix: TRuleFix;
begin
  mMessage := cTexts[TCaptureText.CapturesVariable].Fmt([ALocal.Name, ALocal.Name]);
  if CopyPerIterationFix(AMethod, ALocal, mFix) then
  begin
    FReport.Add(TTextRange.Create(AIdentifier.StartPos, AIdentifier.EndPos), mMessage, AConfidence, [mFix]);
  end
  else
  begin
    FReport.Add(TTextRange.Create(AIdentifier.StartPos, AIdentifier.EndPos), mMessage, AConfidence);
  end;
end;

procedure TLoopCaptureCheck.CheckMethod(AMethod: TSyntaxNode; AConfidence: TRuleConfidence);
var
  mIdentifiers: TList<TSyntaxNode>;
  mReported: TList<string>;
  mIdentifier: TSyntaxNode;
  mLocal: TLocal;
begin
  mIdentifiers := TList<TSyntaxNode>.Create;
  mReported := TList<string>.Create;
  try
    CollectIdentifiers(AMethod, mIdentifiers);
    for mIdentifier in mIdentifiers do
    begin
      if FindLocal(FVariables, mIdentifier.Name, mLocal) and not mReported.Contains(LowerCase(mLocal.Name)) and
        ChangesLater(AMethod, mLocal) then
      begin
        mReported.Add(LowerCase(mLocal.Name));
        ReportCapture(mIdentifier, AMethod, mLocal, AConfidence);
      end;
    end;
  finally
    mReported.Free;
    mIdentifiers.Free;
  end;
end;

procedure TLoopCaptureCheck.CheckRoutine(ARoutine: TSyntaxNode);
var
  mBlock, mMethod: TSyntaxNode;
  mMethods: TArray<TSyntaxNode>;
  mConfidence: TRuleConfidence;
begin
  mBlock := ARoutine.FindChild(TSyntaxKind.Block);
  mMethods := nil;
  CollectAnonymous(mBlock, mMethods);
  if mMethods = nil then
  begin
    Exit;
  end;
  FRoutine := ARoutine;
  FVariables := Locals(ARoutine, mBlock);
  FGraph := nil;
  for mMethod in mMethods do
  begin
    if IsDeferred(mMethod, FApis, mConfidence) then
    begin
      CheckMethod(mMethod, mConfidence);
    end;
  end;
end;

procedure TLoopCaptureCheck.Run;
var
  mRoutine: TSyntaxNode;
begin
  for mRoutine in TRuleDerived.Routines(FCache, FContext) do
  begin
    CheckRoutine(mRoutine);
  end;
end;

{ TCapturedLoopVariableRule }

function TCapturedLoopVariableRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('captured-loop-variable', TRuleSeverity.Warning,
    cTexts[TCaptureText.LoopTitle].Text);
end;

procedure TCapturedLoopVariableRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TLoopCaptureCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mCheck := TLoopCaptureCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
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
  begin
    Result := Result.Parent;
  end;
end;

function TypeChild(ANode: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[Index].Kind in TRoutineLocals.TypeKinds then
    begin
      Exit(ANode[Index]);
    end;
  end;
  Result := nil;
end;

function HasName(const ANames, AName: string): Boolean;
var
  Name: string;
begin
  for Name in SplitString(ANames, ',') do
  begin
    if SameText(Trim(Name), AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function MakeCaptureDecl(AKind: TCaptureDeclKind; AScope, ANode: TSyntaxNode; const AName,
  ATypeText: string): TCaptureDecl;
begin
  Result.Kind := AKind;
  Result.Scope := AScope;
  Result.Node := ANode;
  Result.Name := AName;
  Result.TypeText := ATypeText;
end;

type
  /// <summary>Sucht für anonymous-capture-invalid, was ein Name in einem Bereich deklariert; hält Text, Token
  /// und Übersetzungspfade der Datei.</summary>
  TCaptureLookup = class
  private
    FText: string;
    FPaths: TArray<string>;
    FTokens: TArray<TPascalToken>;
    /// <summary>Pfad des gesuchten Bezeichners; Zweige, die sich damit ausschließen, zählen nicht.</summary>
    FPath: string;
    function Active(ANode: TSyntaxNode): Boolean;
    function ParameterDecl(AScope, AParam: TSyntaxNode; const AName: string): TCaptureDecl;
    function FindParameter(AScope: TSyntaxNode; const AName: string; out ADecl: TCaptureDecl): Boolean;
    function FindInSection(AScope, ASection: TSyntaxNode; const AName: string; out ADecl: TCaptureDecl): Boolean;
    function FindSection(AScope: TSyntaxNode; const AName: string; out ADecl: TCaptureDecl): Boolean;
    /// <summary>Deklariert ANode (Inline-Variable oder for var) AName, sichtbar an AOffset?</summary>
    function DeclaresInline(ANode: TSyntaxNode; const AName: string; AOffset: Integer): Boolean;
    /// <summary>Inline-Variablen und for var dieses Bereichs (nicht verschachtelter anonymer Methoden), die
    /// AOffset sehen. Iterativ (Bericht M1).</summary>
    function FindInline(AScope: TSyntaxNode; const AName: string; AOffset: Integer;
      out ADecl: TCaptureDecl): Boolean;
    /// <summary>Result einer Funktion: Ergebnistyp am Kopf (Routine) bzw. "function" (anonyme Methode).
    /// </summary>
    function FindResult(AScope: TSyntaxNode; const AName: string; out ADecl: TCaptureDecl): Boolean;
  public
    constructor Create(const AText: string; const ATokens: TArray<TPascalToken>; const APaths: TArray<string>);
    /// <summary>Deklariert AScope den Namen AName, sichtbar an AOffset? APath ist der Pfad des Bezeichners.
    /// </summary>
    function Find(AScope: TSyntaxNode; const AName: string; AOffset: Integer; const APath: string;
      out ADecl: TCaptureDecl): Boolean;
  end;

/// <summary>Kopf des Bereichs: bei Routinen der Kopfknoten, bei anonymen Methoden der Bereich selbst.</summary>
function ScopeHeader(AScope: TSyntaxNode): TSyntaxNode;
begin
  if AScope.Kind = TSyntaxKind.RoutineDecl then
  begin
    Result := AScope.FindChild(TSyntaxKind.RoutineHeader);
  end
  else
  begin
    Result := AScope;
  end;
end;

constructor TCaptureLookup.Create(const AText: string; const ATokens: TArray<TPascalToken>;
  const APaths: TArray<string>);
begin
  inherited Create;
  FText := AText;
  FTokens := ATokens;
  FPaths := APaths;
end;

function TCaptureLookup.Active(ANode: TSyntaxNode): Boolean;
begin
  Result := not TConditionalBranches.Exclusive(FPath,
    TConditionalBranches.PathAt(FPaths, TRoutineBody.TokenAt(FTokens, ANode.StartOffset)));
end;

function TCaptureLookup.ParameterDecl(AScope, AParam: TSyntaxNode; const AName: string): TCaptureDecl;
begin
  if TypeChild(AParam) = nil then
  begin
    Result := MakeCaptureDecl(TCaptureDeclKind.UntypedParam, AScope, AParam, AName, '');
  end
  else if AParam.Modifier = TParameterModifier.VarParam then
  begin
    Result := MakeCaptureDecl(TCaptureDeclKind.VarParam, AScope, AParam, AName,
      TRoutineBody.TextOf(FText, TypeChild(AParam)));
  end
  else if AParam.Modifier = TParameterModifier.OutParam then
  begin
    Result := MakeCaptureDecl(TCaptureDeclKind.OutParam, AScope, AParam, AName,
      TRoutineBody.TextOf(FText, TypeChild(AParam)));
  end
  else
  begin
    Result := MakeCaptureDecl(TCaptureDeclKind.Other, AScope, AParam, AName, '');
  end;
end;

function TCaptureLookup.FindParameter(AScope: TSyntaxNode; const AName: string; out ADecl: TCaptureDecl): Boolean;
var
  mHeader, mParameters, mParam: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  ADecl := Default(TCaptureDecl);
  mHeader := ScopeHeader(AScope);
  mParameters := nil;
  if mHeader <> nil then
  begin
    mParameters := mHeader.FindChild(TSyntaxKind.Parameters);
  end;
  if mParameters = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParameters.ChildCount - 1 do
  begin
    mParam := mParameters[mIndex];
    if (mParam.Kind = TSyntaxKind.Parameter) and HasName(mParam.Name, AName) and Active(mParam) then
    begin
      ADecl := ParameterDecl(AScope, mParam, AName);
      Exit(True);
    end;
  end;
end;

function TCaptureLookup.FindInSection(AScope, ASection: TSyntaxNode; const AName: string;
  out ADecl: TCaptureDecl): Boolean;
var
  mInner: Integer;
begin
  Result := False;
  ADecl := Default(TCaptureDecl);
  for mInner := 0 to ASection.ChildCount - 1 do
  begin
    if HasName(ASection[mInner].Name, AName) and Active(ASection[mInner]) then
    begin
      ADecl := MakeCaptureDecl(TCaptureDeclKind.Other, AScope, ASection[mInner], AName, '');
      Exit(True);
    end;
  end;
end;

function TCaptureLookup.FindSection(AScope: TSyntaxNode; const AName: string; out ADecl: TCaptureDecl): Boolean;
var
  mIndex: Integer;
  mSection: TSyntaxNode;
begin
  Result := False;
  ADecl := Default(TCaptureDecl);
  mIndex := 0;
  while not Result and (mIndex < AScope.ChildCount) do
  begin
    mSection := AScope[mIndex];
    if mSection.Kind in [TSyntaxKind.VarSection, TSyntaxKind.ConstSection, TSyntaxKind.TypeSection] then
    begin
      Result := FindInSection(AScope, mSection, AName, ADecl);
    end
    else if (mSection.Kind = TSyntaxKind.RoutineDecl) and SameText(mSection.Name, AName) and Active(mSection) then
    begin
      ADecl := MakeCaptureDecl(TCaptureDeclKind.Other, AScope, mSection, AName, '');
      Result := True;
    end;
    Inc(mIndex);
  end;
end;

function TCaptureLookup.DeclaresInline(ANode: TSyntaxNode; const AName: string; AOffset: Integer): Boolean;
begin
  if ANode.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
  begin
    Result := HasName(ANode.Name, AName) and (ANode.StartOffset <= AOffset) and (ANode.Parent <> nil) and
      (AOffset <= ANode.Parent.EndOffset);
  end
  else if ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
  begin
    Result := SameText(ANode.Name, AName) and (ANode.StartOffset <= AOffset) and (AOffset <= ANode.EndOffset) and
      TRoutineLocals.IsInlineFor(FTokens, ANode);
  end
  else
  begin
    Result := False;
  end;
  Result := Result and Active(ANode);
end;

function TCaptureLookup.FindInline(AScope: TSyntaxNode; const AName: string; AOffset: Integer;
  out ADecl: TCaptureDecl): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := False;
  ADecl := Default(TCaptureDecl);
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(AScope);
    while (mPending.Count > 0) and not Result do
    begin
      mNode := mPending.Pop;
      if (mNode <> AScope) and IsCaptureScope(mNode) then
      begin
        Continue;
      end;
      Result := DeclaresInline(mNode, AName, AOffset);
      if Result then
      begin
        ADecl := MakeCaptureDecl(TCaptureDeclKind.Other, AScope, mNode, AName, '');
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function TCaptureLookup.FindResult(AScope: TSyntaxNode; const AName: string; out ADecl: TCaptureDecl): Boolean;
var
  mHeader, mResultType: TSyntaxNode;
  mIndex: Integer;
begin
  ADecl := Default(TCaptureDecl);
  mHeader := ScopeHeader(AScope);
  mResultType := nil;
  if SameText(AName, 'Result') and (mHeader <> nil) then
  begin
    for mIndex := 0 to mHeader.ChildCount - 1 do
    begin
      if mHeader[mIndex].Kind = TSyntaxKind.TypeReference then
      begin
        mResultType := mHeader[mIndex];
      end;
    end;
  end;
  Result := (mResultType <> nil) and ((AScope.Kind = TSyntaxKind.RoutineDecl) or (AScope.Name = 'function'));
  if Result then
  begin
    ADecl := MakeCaptureDecl(TCaptureDeclKind.FunctionResult, AScope, nil, AName,
      TRoutineBody.TextOf(FText, mResultType));
  end;
end;

function TCaptureLookup.Find(AScope: TSyntaxNode; const AName: string; AOffset: Integer; const APath: string;
  out ADecl: TCaptureDecl): Boolean;
begin
  FPath := APath;
  Result := FindParameter(AScope, AName, ADecl) or FindSection(AScope, AName, ADecl) or
    FindInline(AScope, AName, AOffset, ADecl) or FindResult(AScope, AName, ADecl);
end;

/// <summary>Steht ANode als Feldname einer Record-Konstante (X: 1) oder hinter einem Punkt?</summary>
function IsRecordFieldName(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Result := False;
  if (ANode.Parent = nil) or (ANode.Parent.Kind <> TSyntaxKind.ParenExpr) then
  begin
    Exit;
  end;
  Index := TRoutineBody.NextToken(ATokens, TRoutineBody.TokenAt(ATokens, ANode.StartOffset));
  Result := (Index >= 0) and (Index < Length(ATokens)) and ATokens[Index].IsSymbol(':');
end;

function TAnonymousCaptureInvalidRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(AnonymousCaptureInvalidRuleId, TRuleSeverity.Error,
    cTexts[TCaptureText.ParamTitle].Text);
end;

procedure TAnonymousCaptureInvalidRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Paths: TArray<string>;
  Lines: TArray<string>;
  LineBreak: string;
  Reported: TList<string>;
  Lookup: TCaptureLookup;

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
      begin
        Exit(False);
      end;
      if Node.Parent.Kind = TSyntaxKind.AsmBlock then
      begin
        Exit(False);
      end;
      Node := Node.Parent;
      if not IsCaptureScope(Node) then
      begin
        Continue;
      end;
      Scope := Node;
      if Lookup.Find(Scope, AIdent.Name, AIdent.StartOffset, Path, ADecl) then
      begin
        Exit(AOuter <> nil);
      end;
      if Scope.Kind = TSyntaxKind.AnonymousMethod then
      begin
        AOuter := Scope;
      end;
    end;
  end;

  function KindText(AKind: TCaptureDeclKind): string;
  begin
    case AKind of
      TCaptureDeclKind.VarParam:
        Result := cTexts[TCaptureText.VarParam].Text;
      TCaptureDeclKind.OutParam:
        Result := cTexts[TCaptureText.OutParam].Text;
    else
      Result := cTexts[TCaptureText.UntypedParam].Text;
    end;
  end;

  function Indent(ALine: Integer): string;
  var
    Text: string;
    Index: Integer;
  begin
    Result := '';
    if (ALine < 0) or (ALine > High(Lines)) then
    begin
      Exit;
    end;
    Text := Lines[ALine];
    Index := 1;
    while (Index <= Length(Text)) and CharInSet(Text[Index], [' ', #9]) do
    begin
      Inc(Index);
    end;
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
    begin
      Exit;
    end;
    Rest := Trim(Copy(Lines[APosition.Line], APosition.Character + 1, MaxInt));
    if StartsStr(';', Rest) then
    begin
      Rest := Trim(Copy(Rest, 2, MaxInt));
    end;
    Result := (Rest = '') or StartsStr('//', Rest);
  end;

  /// <summary>Anweisung, die die anonyme Methode AMethod enthält, direkt in einem Block der Routine AScope und
  /// allein auf ihren Zeilen; nil sonst.</summary>
  function FixStatement(AScope, AMethod: TSyntaxNode): TSyntaxNode;
  begin
    Result := AMethod;
    while (Result.Parent <> nil) and (Result.Parent.Kind <> TSyntaxKind.Block) do
    begin
      Result := Result.Parent;
    end;
    if (Result.Parent = nil) or (ScopeOf(Result) <> AScope) or not LineStartsAt(Result.StartPos) or
      not LineEndsAt(Result.EndPos) then
    begin
      Result := nil;
    end;
  end;

  /// <summary>Bezeichner in AMethod, die die Deklaration ADecl meinen; AReads/AWrites: ob sie gelesen bzw.
  /// geschrieben wird.</summary>
  function CapturedUses(const ADecl: TCaptureDecl; AMethod: TSyntaxNode; out AReads,
    AWrites: Boolean): TArray<TSyntaxNode>;
  var
    mFound: TList<TSyntaxNode>;
    mIdent, mOuter: TSyntaxNode;
    mDecl: TCaptureDecl;
    mAccess: TLocalAccess;
  begin
    Result := nil;
    AReads := False;
    AWrites := False;
    mFound := TList<TSyntaxNode>.Create;
    try
      AMethod.Walk(
        function(ANode: TSyntaxNode): Boolean
        begin
          if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, ADecl.Name) then
          begin
            mFound.Add(ANode);
          end;
          Result := True;
        end);
      for mIdent in mFound do
      begin
        if Resolve(mIdent, mDecl, mOuter) and (mDecl.Scope = ADecl.Scope) then
        begin
          Result := Result + [mIdent];
          mAccess := TRoutineLocals.AccessOf(mIdent, nil);
          AReads := AReads or (mAccess <> TLocalAccess.Write);
          AWrites := AWrites or (mAccess <> TLocalAccess.Read);
        end;
      end;
    finally
      mFound.Free;
    end;
  end;

  /// <summary>Neue lokale Variable ACopy mit dem Typ von ADecl: an den letzten var-Abschnitt der Routine
  /// ARoutine bzw. als eigener Abschnitt vor ihrem Block.</summary>
  function DeclarationEdit(const ADecl: TCaptureDecl; ARoutine: TSyntaxNode; const ACopy: string): TRuleEdit;
  var
    mSection, mBlock: TSyntaxNode;
    mIndex: Integer;
    mIndent: string;
  begin
    mSection := nil;
    for mIndex := 0 to ARoutine.ChildCount - 1 do
    begin
      if ARoutine[mIndex].Kind = TSyntaxKind.VarSection then
      begin
        mSection := ARoutine[mIndex];
      end;
    end;
    mIndent := Indent(ARoutine.StartPos.Line);
    if mSection <> nil then
    begin
      Result := TRuleEdit.Create(TTextRange.Create(mSection.EndPos.Line + 1, 0, mSection.EndPos.Line + 1, 0),
        mIndent + '  ' + ACopy + ': ' + ADecl.TypeText + ';' + LineBreak);
    end
    else
    begin
      mBlock := ARoutine.FindChild(TSyntaxKind.Block);
      Result := TRuleEdit.Create(TTextRange.Create(mBlock.StartPos.Line, 0, mBlock.StartPos.Line, 0),
        mIndent + 'var' + LineBreak + mIndent + '  ' + ACopy + ': ' + ADecl.TypeText + ';' + LineBreak);
    end;
  end;

  /// <summary>Name der Kopie: Ergebnis für Result, sonst NameKopie; eindeutig in der Datei.</summary>
  function CopyName(const ADecl: TCaptureDecl): string;
  begin
    if ADecl.Kind = TCaptureDeclKind.FunctionResult then
    begin
      Result := TRoutineBody.UniqueName(Tokens, AContext.NewNames.Local('Ergebnis'));
    end
    else
    begin
      Result := TRoutineBody.UniqueName(Tokens, AContext.NewNames.Local(ADecl.Name + 'Kopie'));
    end;
  end;

  /// <summary>Korrektur: Wert vor der Anweisung in eine lokale Variable kopieren, in AMethod nur diese
  /// verwenden und nach der Anweisung zurückschreiben, wenn AMethod schreibt.</summary>
  function CopyFix(const ADecl: TCaptureDecl; AMethod: TSyntaxNode; out AFix: TRuleFix): Boolean;
  var
    Statement, Ident: TSyntaxNode;
    Uses_: TArray<TSyntaxNode>;
    Reads, Writes: Boolean;
    Copy_, StatementIndent: string;
    Edits: TArray<TRuleEdit>;
  begin
    Result := False;
    AFix := Default(TRuleFix);
    if (ADecl.Scope.Kind <> TSyntaxKind.RoutineDecl) or (ADecl.TypeText = '') or
      (ADecl.Scope.FindChild(TSyntaxKind.Block) = nil) then
    begin
      Exit;
    end;
    Statement := FixStatement(ADecl.Scope, AMethod);
    if Statement = nil then
    begin
      Exit;
    end;
    Uses_ := CapturedUses(ADecl, AMethod, Reads, Writes);
    Copy_ := CopyName(ADecl);
    StatementIndent := Indent(Statement.StartPos.Line);
    Edits := [DeclarationEdit(ADecl, ADecl.Scope, Copy_)];
    // out-Parameter und Result haben vorher keinen Wert, der kopiert werden müsste.
    if Reads and (ADecl.Kind in [TCaptureDeclKind.VarParam, TCaptureDeclKind.FunctionResult]) then
    begin
      Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Statement.StartPos.Line, 0, Statement.StartPos.Line, 0),
        StatementIndent + Copy_ + ' := ' + ADecl.Name + ';' + LineBreak)];
    end;
    for Ident in Uses_ do
    begin
      Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Ident.StartPos, Ident.EndPos), Copy_)];
    end;
    if Writes then
    begin
      Edits := Edits + [TRuleEdit.Create(TTextRange.Create(Statement.EndPos.Line + 1, 0, Statement.EndPos.Line + 1,
        0), StatementIndent + ADecl.Name + ' := ' + Copy_ + ';' + LineBreak)];
    end;
    AFix := TRuleFix.Create(cTexts[TCaptureText.CopyValue].Fmt([Copy_]), Edits);
    Result := True;
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
    begin
      Exit;
    end;
    // Je anonymer Methode und Deklaration eine Meldung.
    Key := IntToStr(Outer.StartOffset) + ':' + IntToStr(Decl.Scope.StartOffset) + ':' + LowerCase(Decl.Name);
    if Reported.Contains(Key) then
    begin
      Exit;
    end;
    Reported.Add(Key);
    if Decl.Kind = TCaptureDeclKind.FunctionResult then
    begin
      Message := cTexts[TCaptureText.ResultCapture].Text;
    end
    else
    begin
      Message := cTexts[TCaptureText.CannotCapture].Fmt([KindText(Decl.Kind), Decl.Name]);
    end;
    if CopyFix(Decl, Outer, Fix) then
    begin
      AReport.Add(TTextRange.Create(AIdent.StartPos, AIdent.EndPos), Message, TRuleConfidence.High, [Fix]);
    end
    else
    begin
      AReport.Add(TTextRange.Create(AIdent.StartPos, AIdent.EndPos), Message, TRuleConfidence.High);
    end;
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
        begin
          CheckIdentifier(Node);
        end;
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
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Paths := TConditionalBranches.Paths(Tokens);
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Reported := TList<string>.Create;
  Lookup := TCaptureLookup.Create(AContext.Text, Tokens, Paths);
  try
    Visit(AContext.Tree.Root);
  finally
    Lookup.Free;
    Reported.Free;
  end;
end;

procedure RegisterCaptureRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TCapturedLoopVariableRule.Create);
  ARegistry.Register(TAnonymousCaptureInvalidRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Capture', cTexts);

end.
