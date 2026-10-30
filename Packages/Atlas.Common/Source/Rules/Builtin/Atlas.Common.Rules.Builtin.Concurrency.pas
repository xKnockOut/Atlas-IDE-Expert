unit Atlas.Common.Rules.Builtin.Concurrency;

// Nebenläufigkeitsregeln (#148, mit der VCL-Thread-Regel aus #56):
//   thread-vcl-access                   VCL-Zugriff (Application, Screen, ShowMessage …) in
//                                       TThread.Execute, CreateAnonymousThread oder TTask
//                                       außerhalb von Synchronize/Queue; Korrektur: in Queue einschließen
//   lock-without-finally                Sperre ohne direkt folgendes try/finally mit Freigabe;
//                                       Korrektur, wenn die Freigabe später im selben Block steht
//   thread-use-after-free-on-terminate  Variable nach FreeOnTerminate := True und Start weiter benutzt
//   thread-free-with-free-on-terminate  Free auf einem Thread mit FreeOnTerminate (Doppelfreigabe)
//   synchronize-in-destructor           Synchronize im Destruktor eines TThread-Nachfahren
//   thread-resume-suspend               veraltetes Resume/Suspend; Korrektur Resume → Start
//   pair-without-finally                beliebige Paare wie DisableControls/EnableControls, BeginUpdate/
//                                       EndUpdate, FindFirst/FindClose, Reset/CloseFile, GetMem/FreeMem und
//                                       Screen.Cursor := … ohne try/finally (#930); die Sperrpaare bleiben
//                                       bei lock-without-finally. Erweiterbar über die Option "pairs".
//   processmessages-in-loop             Application.ProcessMessages in einer Schleife oder direkt in einem
//                                       Ereignis-Handler (Methode mit Parameter Sender) öffnet die Tür für
//                                       Wiedereintritt (#931); Ausnahmen über die Option "allowIn".
//   queue-nil-in-package                TThread.Queue(nil, …) bzw. ForceQueue(nil, …) in einer Unit eines
//                                       Packages (#943): der Eintrag gehört keinem Thread und kann nach dem
//                                       Entladen laufen. Korrektur auf den Wrapper aus "wrapper" (Vorgabe
//                                       TAtlasMainThread.Queue, für ForceQueue …ForceQueue); eine Zeile mit
//                                       dem Kommentar aus "okMarker" (Vorgabe mainthread-ok) bleibt still.
//   blocking-call-in-main-thread        Sleep, WaitFor, WaitForSingleObject, WaitForMultipleObjects und Wait
//                                       in Methoden von Formularen und Frames sowie in Ereignis-Handlern
//                                       (#959); kurzes Sleep unter "maxSleepMs" nur in Warteschleifen.
//   thread-loop-without-terminated      while/repeat ohne Terminated in Execute eines Threads und in Methoden,
//                                       die nur von dort kommen (#960); nur Endlos- und Warteschleifen.
//   anonymous-thread-not-started        TThread.CreateAnonymousThread(…) ohne Start, als Anweisung oder in
//                                       einer lokalen Variablen, die weder gestartet noch weitergegeben wird (#961).
//   task-exception-unobserved           TTask.Run(…) bzw. TTask.Create(…).Start, das nie abgefragt wird und
//                                       dessen anonymer Rumpf kein try … except hat (#962).
//
// Ein Thread mit Free ohne Terminate und WaitFor wird nicht gemeldet:
// TThread.Destroy ruft beides selbst auf.
//
// Typen kennt die Regel nicht. Thread-Klassen sind Klassen dieser Unit, die
// (auch über Zwischenklassen der Unit) von TThread erben; Sperren erkennt sie
// an den Methodenpaaren, erweiterbar über die Option
//   "rules": { "lock-without-finally": { "lockPairs": [["Lock", "Unlock"]] } }

interface

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TLockPair = record
    Lock: string;
    Release: string;
  end;

  TThreadVclAccessRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLockWithoutFinallyRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Eingebaute Paare und die aus "lockPairs" in AOptions.</summary>
    class function LockPairs(const AOptions: string): TArray<TLockPair>; static;
  end;

  TThreadUseAfterFreeOnTerminateRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TThreadFreeWithFreeOnTerminateRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSynchronizeInDestructorRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TThreadResumeSuspendRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Paar für pair-without-finally (#930). Open und Close sind Methoden- bzw. Routinennamen oder eine
  /// Zuweisung "Screen.Cursor :="; OpenArg/CloseArg wählen das Argument, das beide verbindet (-1 = Empfänger,
  /// ohne Empfänger das erste Argument).</summary>
  TStatePair = record
    Open: string;
    Close: string;
    OpenArg: Integer;
    CloseArg: Integer;
    /// <summary>Was bei einer Ausnahme hängen bleibt, für die Meldung.</summary>
    Consequence: string;
  end;

  TPairWithoutFinallyRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Eingebaute Paare und die aus "pairs" in AOptions.</summary>
    class function Pairs(const AOptions: string): TArray<TStatePair>; static;
  end;

  TProcessMessagesInLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TBlockingCallInMainThreadRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Position des Timeouts unter den Argumenten von ACall (ab 0); -1 ohne Timeout.</summary>
    class function TimeoutArgument(const ACall: string): Integer; static;
  end;

  TThreadLoopWithoutTerminatedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TAnonymousThreadNotStartedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TTaskExceptionUnobservedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TQueueNilInPackageRule = class(TInterfacedObject, IRule)
  public const
    DefaultWrapper = 'TAtlasMainThread.Queue';
    DefaultOkMarker = 'mainthread-ok';
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Aufruf, der AWrapper für AMethod (Queue oder ForceQueue) ersetzt: bei ForceQueue wird aus
    /// …Queue …ForceQueue. Enthält AWrapper eine Klammer, steht er so vor den übrigen Argumenten.</summary>
    class function WrapperCall(const AWrapper, AMethod: string): string; static;
  end;

/// <summary>Klassen der Unit, die direkt oder über Klassen der Unit von TThread erben.</summary>
function ThreadClasses(ARoot: TSyntaxNode): TArray<string>;

procedure RegisterConcurrencyRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.JSON,
  System.StrUtils,
  Atlas.Text.Lines,
  System.Generics.Collections,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Options;

type
  /// <summary>Aufruf X.M, X.M(…) oder M(…) als Anweisung.</summary>
  TMethodCall = record
    Method: string;
    /// <summary>Ausdruck vor dem Punkt, nil bei M(…).</summary>
    Receiver: TSyntaxNode;
    /// <summary>Knoten mit dem Methodennamen (MemberAccess oder Identifier).</summary>
    Member: TSyntaxNode;
    /// <summary>Aufruf mit Argumenten, sonst nil.</summary>
    Call: TSyntaxNode;
  end;

const
  BuiltinLockPairs: array[0..5, 0..1] of string = (('Enter', 'Leave'), ('Enter', 'Exit'), ('Acquire', 'Release'),
    ('BeginRead', 'EndRead'), ('BeginWrite', 'EndWrite'), ('EnterCriticalSection', 'LeaveCriticalSection'));
  VclGlobals: array[0..1] of string = ('Application', 'Screen');
  VclDialogs: array[0..4] of string = ('ShowMessage', 'ShowMessageFmt', 'ShowMessagePos', 'MessageDlg',
    'InputBox');

function InList(const AItems: array of string; const AText: string): Boolean;
var
  Item: string;
begin
  for Item in AItems do
    if SameText(Item, AText) then
      Exit(True);
  Result := False;
end;

function SourceText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := LowerCase(SourceText(AText, ANode));
end;

function TryMethodCall(AStatement: TSyntaxNode; out ACall: TMethodCall): Boolean;
var
  Target: TSyntaxNode;
begin
  Result := False;
  ACall := Default(TMethodCall);
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
    Exit;
  Target := AStatement[0];
  if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
  begin
    ACall.Call := Target;
    Target := Target[0];
  end;
  if (Target.Kind = TSyntaxKind.MemberAccess) and (Target.ChildCount > 0) then
    ACall.Receiver := Target[0]
  else if (Target.Kind <> TSyntaxKind.Identifier) or (ACall.Call = nil) then
    Exit;
  ACall.Method := Target.Name;
  ACall.Member := Target;
  Result := True;
end;

/// <summary>Bereich des Namens am Ende von ANode (MemberAccess oder Identifier).</summary>
function NameRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.EndPos.Line, ANode.EndPos.Character - Length(ANode.Name),
    ANode.EndPos.Line, ANode.EndPos.Character);
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

/// <summary>Bezeichner der Variablen in X oder Self.X, sonst ''.</summary>
function VariableName(ANode: TSyntaxNode): string;
begin
  if ANode = nil then
    Result := ''
  else if ANode.Kind = TSyntaxKind.Identifier then
    Result := ANode.Name
  else if (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount = 1) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Self') then
    Result := ANode.Name
  else
    Result := '';
end;

function IsStatementList(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.FinallyBlock,
    TSyntaxKind.ExceptBlock, TSyntaxKind.InitializationSection, TSyntaxKind.FinalizationSection];
end;

/// <summary>Anweisungslisten in ARoot in Baumreihenfolge. Iterativ gesammelt (Bericht M1), damit die Regeln sie
/// ohne eigene Rekursion prüfen.</summary>
function StatementLists(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  Found: TList<TSyntaxNode>;
begin
  Found := TList<TSyntaxNode>.Create;
  try
    ARoot.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        if IsStatementList(ANode) then
          Found.Add(ANode);
        Result := True;
      end);
    Result := Found.ToArray;
  finally
    Found.Free;
  end;
end;

/// <summary>True, wenn ANode oder ein Nachfahre den Bezeichner AName benutzt.</summary>
function Mentions(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if (AVisited.Kind = TSyntaxKind.Identifier) and SameText(AVisited.Name, Name) then
        Exit(TSyntaxSearchStep.Found);
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

/// <summary>Klassenteil eines Routinennamens: "TA" in "TA.Destroy", sonst ''.</summary>
function ClassPart(const ARoutineName: string): string;
var
  Dot: Integer;
begin
  Dot := LastDelimiter('.', ARoutineName);
  if Dot > 0 then
    Result := Copy(ARoutineName, 1, Dot - 1)
  else
    Result := '';
end;

function MethodPart(const ARoutineName: string): string;
begin
  Result := Copy(ARoutineName, LastDelimiter('.', ARoutineName) + 1, MaxInt);
end;

function ThreadClasses(ARoot: TSyntaxNode): TArray<string>;
var
  Names, Parents: TArray<string>;
  Index: Integer;
  Changed: Boolean;
begin
  Result := nil;
  Names := nil;
  Parents := nil;
  if ARoot = nil then
    Exit;
  // Iterativ (Bericht M1): Der Lauf geht auch durch lange Ausdrucksketten.
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      ClassNode, Ancestor: TSyntaxNode;
    begin
      Result := ANode.Kind <> TSyntaxKind.TypeDecl;
      if Result then
        Exit;
      ClassNode := ANode.FindChild(TSyntaxKind.ClassType);
      if ClassNode = nil then
        Exit;
      Ancestor := ClassNode.FindChild(TSyntaxKind.TypeReference);
      if Ancestor = nil then
        Exit;
      Names := Names + [ANode.Name];
      Parents := Parents + [Ancestor.Name];
    end);
  // Fixpunkt über Zwischenklassen der Unit.
  repeat
    Changed := False;
    for Index := 0 to High(Names) do
      if not InList(Result, Names[Index]) and
        (SameText(Parents[Index], 'TThread') or SameText(Parents[Index], 'System.Classes.TThread') or
        InList(Result, Parents[Index])) then
      begin
        Result := Result + [Names[Index]];
        Changed := True;
      end;
  until not Changed;
end;

/// <summary>ThreadClasses der geprüften Datei, je Lauf einmal berechnet (Review P-03).</summary>
function SharedThreadClasses(const AContext: TRuleContext): TArray<string>;
var
  Cache: IRuleDerivedCache;
  Root: TSyntaxNode;
begin
  Cache := TRuleDerived.Open(AContext);
  Root := AContext.Tree.Root;
  Result := TRuleDerived.Get<TRuleDerivedValue<TArray<string>>>(Cache, 'concurrency.threadClasses',
    function: TRuleDerivedValue<TArray<string>>
    begin
      Result := TRuleDerivedValue<TArray<string>>.Create(ThreadClasses(Root));
    end).Value;
end;

/// <summary>Bereich einer ganzen Anweisung samt Semikolon und Zeilenende, wenn sie allein in ihrer Zeile steht.</summary>
function StatementRemoval(const AText: string; AStatement: TSyntaxNode): TTextRange;
var
  Index: Integer;
  Alone: Boolean;
begin
  Alone := True;
  Index := AStatement.StartOffset;
  while (Index > 0) and (AText[Index] <> #10) do
  begin
    if not CharInSet(AText[Index], [' ', #9]) then
      Alone := False;
    Dec(Index);
  end;
  Index := AStatement.EndOffset + 1;
  if (Index <= Length(AText)) and (AText[Index] = ';') then
    Inc(Index);
  while (Index <= Length(AText)) and not CharInSet(AText[Index], [#10, #13]) do
  begin
    if not CharInSet(AText[Index], [' ', #9]) then
      Alone := False;
    Inc(Index);
  end;
  if Alone then
    Result := TTextRange.Create(AStatement.StartPos.Line, 0, AStatement.EndPos.Line + 1, 0)
  else
    Result := NodeRange(AStatement);
end;

{ TThreadVclAccessRule }

function TThreadVclAccessRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-vcl-access', TRuleSeverity.Warning,
    'VCL-Zugriff aus einem Thread ohne Synchronize oder Queue');
end;

/// <summary>Erster VCL-Zugriff in ANode außerhalb von Synchronize/Queue, sonst nil.</summary>
function FindVclAccess(ANode: TSyntaxNode): TSyntaxNode;
begin
  // Iterativ (Bericht M1).
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    var
      Call: TMethodCall;
    begin
      if TryMethodCall(AVisited, Call) and (SameText(Call.Method, 'Synchronize') or SameText(Call.Method, 'Queue')) then
        Exit(TSyntaxSearchStep.Skip);
      if (AVisited.Kind = TSyntaxKind.Call) and (AVisited.ChildCount > 0) and
        (SameText(AVisited.Name, 'Synchronize') or SameText(AVisited.Name, 'Queue')) then
        Exit(TSyntaxSearchStep.Skip);
      if (AVisited.Kind = TSyntaxKind.Identifier) and (InList(VclGlobals, AVisited.Name) or
        InList(VclDialogs, AVisited.Name)) then
        Exit(TSyntaxSearchStep.Found);
      Result := TSyntaxSearchStep.Descend;
    end);
end;

procedure TThreadVclAccessRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Threads: TArray<string>;
  Bodies: TList<TSyntaxNode>;
  Body: TSyntaxNode;

  procedure CheckBody(ABody: TSyntaxNode);
  var
    Index: Integer;
    Statement, Access: TSyntaxNode;
    Code: string;
  begin
    for Index := 0 to ABody.ChildCount - 1 do
    begin
      Statement := ABody[Index];
      Access := FindVclAccess(Statement);
      if Access = nil then
        Continue;
      if (Statement.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement]) then
      begin
        Code := SourceText(AContext.Text, Statement);
        AReport.Add(NodeRange(Access), Format('%s aus einem Thread: VCL-Zugriffe nur über Synchronize oder Queue',
          [Access.Name]), TRuleConfidence.High,
          [TRuleFix.Create('In TThread.Queue einschließen', [TRuleEdit.Create(NodeRange(Statement),
            'TThread.Queue(nil, procedure begin ' + Code + ' end)')])]);
      end
      else if IsStatementList(Statement) or (Statement.ChildCount > 0) then
        // Verschachtelte Anweisungen (if, for, try …) ohne Korrektur melden.
        AReport.Add(NodeRange(Access), Format('%s aus einem Thread: VCL-Zugriffe nur über Synchronize oder Queue',
          [Access.Name]), TRuleConfidence.High);
    end;
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Threads := SharedThreadClasses(AContext);
  // Iterativ (Bericht M1): erst die Rümpfe sammeln, dann prüfen.
  Bodies := TList<TSyntaxNode>.Create;
  try
    // Execute der Thread-Klassen; eingebettete Routinen darin zählen nicht.
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Found: TSyntaxNode;
      begin
        Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
        if Result or not SameText(MethodPart(ANode.Name), 'Execute') or
          not InList(Threads, ClassPart(ANode.Name)) then
          Exit;
        Found := ANode.FindChild(TSyntaxKind.Block);
        if Found <> nil then
          Bodies.Add(Found);
      end);
    // Anonyme Methoden als Argument von CreateAnonymousThread, TTask.Run/Create/Future.
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Arg: Integer;
        Call, Found: TSyntaxNode;
        Name: string;
      begin
        Result := True;
        if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount <= 1) then
          Exit;
        Call := ANode[0];
        Name := '';
        if (Call.Kind = TSyntaxKind.MemberAccess) and (Call.ChildCount = 1) then
          Name := LowerCase(VariableName(Call[0]) + '.' + Call.Name);
        if (Name = 'tthread.createanonymousthread') or (Name = 'ttask.run') or (Name = 'ttask.create') or
          (Name = 'ttask.future') then
          for Arg := 1 to ANode.ChildCount - 1 do
            if ANode[Arg].Kind = TSyntaxKind.AnonymousMethod then
            begin
              Found := ANode[Arg].FindChild(TSyntaxKind.Block);
              if Found <> nil then
                Bodies.Add(Found);
            end;
      end);
    for Body in Bodies do
      CheckBody(Body);
  finally
    Bodies.Free;
  end;
end;

{ TLockWithoutFinallyRule }

function TLockWithoutFinallyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('lock-without-finally', TRuleSeverity.Warning,
    'Sperre ohne try/finally mit passender Freigabe');
end;

class function TLockWithoutFinallyRule.LockPairs(const AOptions: string): TArray<TLockPair>;
var
  Index: Integer;
  Pair: TLockPair;
  Value, Pairs: TJSONValue;
  Item: TJSONValue;
begin
  Result := nil;
  for Index := Low(BuiltinLockPairs) to High(BuiltinLockPairs) do
  begin
    Pair.Lock := BuiltinLockPairs[Index, 0];
    Pair.Release := BuiltinLockPairs[Index, 1];
    Result := Result + [Pair];
  end;
  if AOptions = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
      Exit;
    Pairs := TJSONObject(Value).GetValue('lockPairs');
    if not (Pairs is TJSONArray) then
      Exit;
    for Item in TJSONArray(Pairs) do
      if (Item is TJSONArray) and (TJSONArray(Item).Count = 2) and (TJSONArray(Item).Items[0] is TJSONString) and
        (TJSONArray(Item).Items[1] is TJSONString) then
      begin
        Pair.Lock := TJSONArray(Item).Items[0].Value;
        Pair.Release := TJSONArray(Item).Items[1].Value;
        Result := Result + [Pair];
      end;
  finally
    Value.Free;
  end;
end;

function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

/// <summary>Schlüssel einer Sperre: Empfänger; bei TMonitor.Enter(X) und EnterCriticalSection(X) auch das Argument.</summary>
function LockKey(const AText: string; const ACall: TMethodCall): string;
begin
  if ACall.Receiver <> nil then
    Result := NodeText(AText, ACall.Receiver)
  else
    Result := '';
  // Nur bei TMonitor.Enter(X) und EnterCriticalSection(X) gehört das Argument zur Sperre; sonst ist es ein
  // Parameter der Freigabe (Guard.Leave(Clear, Keys), #1109).
  if (ACall.Call <> nil) and (ACall.Call.ChildCount > 1) and
    ((ACall.Receiver = nil) or SameText(ShortName(Result), 'TMonitor')) then
    Result := Result + '(' + NodeText(AText, ACall.Call[1]) + ')';
end;

/// <summary>Wie TryMethodCall für einen Aufruf in einem Ausdruck: if Guard.Leave(…) then (#1109).</summary>
function TryExpressionCall(ANode: TSyntaxNode; out ACall: TMethodCall): Boolean;
begin
  Result := False;
  ACall := Default(TMethodCall);
  if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount = 0) or (ANode.Parent = nil) or
    (ANode.Parent.Kind = TSyntaxKind.CallStatement) then
    Exit;
  ACall.Call := ANode;
  ACall.Member := ANode[0];
  if (ACall.Member.Kind = TSyntaxKind.MemberAccess) and (ACall.Member.ChildCount > 0) then
    ACall.Receiver := ACall.Member[0]
  else if ACall.Member.Kind <> TSyntaxKind.Identifier then
    Exit;
  ACall.Method := ACall.Member.Name;
  Result := True;
end;

function IsRelease(const AText: string; ANode: TSyntaxNode; const ARelease, AKey: string): Boolean;
var
  Call: TMethodCall;
begin
  Result := (TryMethodCall(ANode, Call) or TryExpressionCall(ANode, Call)) and SameText(Call.Method, ARelease) and (LockKey(AText, Call) = AKey);
end;

/// <summary>True, wenn ein Finally-Block von ATry die Freigabe mit demselben Schlüssel enthält.</summary>
function ReleasesIn(const AText: string; ATry: TSyntaxNode; const ARelease, AKey: string): Boolean;
var
  Final: TSyntaxNode;
  Text, Release, Key: string;
begin
  Final := ATry.FindChild(TSyntaxKind.FinallyBlock);
  if Final = nil then
    Exit(False);
  Text := AText;
  Release := ARelease;
  Key := AKey;
  // Iterativ (Bericht M1).
  Result := Final.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if IsRelease(Text, ANode, Release, Key) then
        Exit(TSyntaxSearchStep.Found);
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

procedure TLockWithoutFinallyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Pairs: TArray<TLockPair>;

  // Korrektur: Anweisungen zwischen Sperre und Freigabe in try/finally einschließen.
  function WrapFix(AList: TSyntaxNode; ALockIndex, AReleaseIndex: Integer): TArray<TRuleFix>;
  var
    Indent, Middle, NewText: string;
    First, Release: TSyntaxNode;
  begin
    Result := nil;
    if AReleaseIndex <= ALockIndex + 1 then
      Exit;
    First := AList[ALockIndex + 1];
    Release := AList[AReleaseIndex];
    Indent := StringOfChar(' ', AList[ALockIndex].StartPos.Character);
    Middle := TrimRight(Copy(AContext.Text, First.StartOffset + 1, Release.StartOffset - First.StartOffset));
    Middle := StringReplace(Middle, #10, #10'  ', [rfReplaceAll]);
    NewText := 'try' + sLineBreak + Indent + '  ' + Middle + sLineBreak + Indent + 'finally' + sLineBreak +
      Indent + '  ' + SourceText(AContext.Text, Release) + ';' + sLineBreak + Indent + 'end';
    Result := [TRuleFix.Create('In try/finally einschließen', [TRuleEdit.Create(
      TTextRange.Create(First.StartPos, Release.EndPos), NewText)])];
  end;

  // Namen der Routinen dieser Unit (Methoden, lokale Routinen) ohne Klassenpräfix.
  function UnitRoutines: TArray<string>;
  var
    Names: TArray<string>;
  begin
    Names := nil;
    AContext.Tree.Root.Search(
      function(ANode: TSyntaxNode): TSyntaxSearchStep
      begin
        if (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.Name <> '') then
          Names := Names + [ShortName(ANode.Name)];
        Result := TSyntaxSearchStep.Descend;
      end);
    Result := Names;
  end;

  // Name der Routine, in der ANode steht; '' außerhalb (initialization).
  function EnclosingRoutine(ANode: TSyntaxNode): string;
  begin
    Result := '';
    while ANode <> nil do
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
        Exit(ShortName(ANode.Name));
      ANode := ANode.Parent;
    end;
  end;

var
  Routines: TArray<string>;

  procedure CheckList(AList: TSyntaxNode);
  var
    Index, Later, ReleaseIndex: Integer;
    Call: TMethodCall;
    Pair: TLockPair;
    Key, Release: string;
    Released: Boolean;
  begin
    for Index := 0 to AList.ChildCount - 1 do
    begin
      if not TryMethodCall(AList[Index], Call) then
        Continue;
      // Enter(…) ohne Empfänger ruft eine Routine dieser Unit (lokale Routine, eigene Methode), keine Sperre;
      // eine gleichnamige Hülle (procedure TX.Enter; begin TMonitor.Enter(FLock); end) gibt die Sperre an den
      // Aufrufer weiter, der dort geprüft wird (#1109).
      if ((Call.Receiver = nil) and MatchText(Call.Method, Routines)) or
        SameText(EnclosingRoutine(AList), Call.Method) then
        Continue;
      Key := LockKey(AContext.Text, Call);
      Released := False;
      Release := '';
      ReleaseIndex := -1;
      for Pair in Pairs do
        if SameText(Pair.Lock, Call.Method) then
        begin
          if Release = '' then
            Release := Pair.Release;
          // Direkt folgendes try … finally Freigabe, oder Sperre als Anweisung im try selbst.
          if ((Index < AList.ChildCount - 1) and (AList[Index + 1].Kind = TSyntaxKind.TryStatement) and
            ReleasesIn(AContext.Text, AList[Index + 1], Pair.Release, Key)) or
            ((AList.Kind = TSyntaxKind.TryStatement) and ReleasesIn(AContext.Text, AList, Pair.Release, Key)) or
            // Freigabe direkt danach: dazwischen kann nichts werfen (Monitor vorab anlegen).
            ((Index < AList.ChildCount - 1) and IsRelease(AContext.Text, AList[Index + 1], Pair.Release, Key)) then
            Released := True;
          for Later := Index + 1 to AList.ChildCount - 1 do
            if (ReleaseIndex < 0) and IsRelease(AContext.Text, AList[Later], Pair.Release, Key) then
            begin
              ReleaseIndex := Later;
              Release := Pair.Release;
            end;
        end;
      if (Release = '') or Released then
        Continue;
      AReport.Add(NameRange(Call.Member),
        Format('%s ohne try/finally mit %s: eine Ausnahme lässt die Sperre gesetzt', [Call.Method, Release]),
        TRuleConfidence.High, WrapFix(AList, Index, ReleaseIndex));
    end;
  end;

var
  List: TSyntaxNode;
begin
  if AContext.Tree = nil then
    Exit;
  Pairs := LockPairs(AContext.Options);
  Routines := UnitRoutines;
  for List in StatementLists(AContext.Tree.Root) do
    CheckList(List);
end;

{ TPairWithoutFinallyRule }

const
  // Open, Close, OpenArg, CloseArg, Folge.
  BuiltinStatePairs: array[0..8, 0..4] of string = (
    ('DisableControls', 'EnableControls', '-1', '-1', 'bleibt das Grid eingefroren'),
    ('BeginUpdate', 'EndUpdate', '-1', '-1', 'bleibt die Anzeige gesperrt'),
    ('FindFirst', 'FindClose', '2', '0', 'bleibt das Suchhandle offen'),
    ('Reset', 'CloseFile', '0', '0', 'bleibt die Datei offen'),
    ('Rewrite', 'CloseFile', '0', '0', 'bleibt die Datei offen'),
    ('Append', 'CloseFile', '0', '0', 'bleibt die Datei offen'),
    ('GetMem', 'FreeMem', '0', '0', 'bleibt der Speicher belegt'),
    ('AllocMem', 'FreeMem', '-2', '0', 'bleibt der Speicher belegt'),
    ('Screen.Cursor :=', 'Screen.Cursor :=', '-1', '-1', 'bleibt der Mauszeiger stehen'));
  AssignSuffix = ':=';

function TPairWithoutFinallyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('pair-without-finally', TRuleSeverity.Warning,
    'Paarige Aufrufe ohne try/finally');
end;

class function TPairWithoutFinallyRule.Pairs(const AOptions: string): TArray<TStatePair>;
var
  Index: Integer;
  Pair: TStatePair;
  Value, List, Item: TJSONValue;
  Number: Integer;
begin
  Result := nil;
  for Index := Low(BuiltinStatePairs) to High(BuiltinStatePairs) do
  begin
    Pair.Open := BuiltinStatePairs[Index, 0];
    Pair.Close := BuiltinStatePairs[Index, 1];
    Pair.OpenArg := StrToInt(BuiltinStatePairs[Index, 2]);
    Pair.CloseArg := StrToInt(BuiltinStatePairs[Index, 3]);
    Pair.Consequence := BuiltinStatePairs[Index, 4];
    Result := Result + [Pair];
  end;
  if Trim(AOptions) = '' then
    Exit;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
      Exit;
    List := TJSONObject(Value).GetValue('pairs');
    if not (List is TJSONArray) then
      Exit;
    for Item in TJSONArray(List) do
      if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>('open', Pair.Open) and
        TJSONObject(Item).TryGetValue<string>('close', Pair.Close) and (Trim(Pair.Open) <> '') and
        (Trim(Pair.Close) <> '') then
      begin
        Pair.Open := Trim(Pair.Open);
        Pair.Close := Trim(Pair.Close);
        Pair.OpenArg := -1;
        Pair.CloseArg := -1;
        if TJSONObject(Item).TryGetValue<Integer>('openArg', Number) then
          Pair.OpenArg := Number;
        if TJSONObject(Item).TryGetValue<Integer>('closeArg', Number) then
          Pair.CloseArg := Number;
        Pair.Consequence := 'bleibt der Zustand hängen';
        Result := Result + [Pair];
      end;
  finally
    Value.Free;
  end;
end;

procedure TPairWithoutFinallyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
type
  TOpening = record
    Pair: Integer;
    Index: Integer;
    Key: string;
  end;
var
  StatePairs: TArray<TStatePair>;

  function IsAssignPair(const AName: string): Boolean;
  begin
    Result := EndsStr(AssignSuffix, AName);
  end;

  function AssignTarget(const AName: string): string;
  begin
    Result := LowerCase(Trim(Copy(AName, 1, Length(AName) - Length(AssignSuffix))));
  end;

  // Schlüssel eines Aufrufs: Empfänger bzw. das gewählte Argument (Call[1] ist das erste Argument).
  function CallKey(ACall: TSyntaxNode; AReceiver: TSyntaxNode; AArg: Integer): string;
  begin
    Result := '';
    if AArg = -2 then
      Exit('*');
    if (AArg < 0) and (AReceiver <> nil) then
      Exit(NodeText(AContext.Text, AReceiver));
    if AArg < 0 then
      AArg := 0;
    if (ACall <> nil) and (ACall.ChildCount > AArg + 1) then
      Result := NodeText(AContext.Text, ACall[AArg + 1]);
  end;

  // Aufruf von AName in ANode (Anweisung, rechte Seite einer Zuweisung); nil sonst.
  function FindCall(ANode: TSyntaxNode; const AName: string; out AReceiver: TSyntaxNode): TSyntaxNode;
  var
    Pending: TStack<TSyntaxNode>;
    Node, Callee: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1), Vorordnung wie die frühere Rekursion.
    AReceiver := nil;
    Result := nil;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.Call then
        begin
          Callee := Node[0];
          if ((Callee.Kind = TSyntaxKind.Identifier) or (Callee.Kind = TSyntaxKind.MemberAccess)) and
            SameText(Callee.Name, AName) then
          begin
            if (Callee.Kind = TSyntaxKind.MemberAccess) and (Callee.ChildCount > 0) then
              AReceiver := Callee[0];
            Exit(Node);
          end;
        end;
        if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.AnonymousMethod,
          TSyntaxKind.RoutineDecl] then
          Continue;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Ist AStatement das Öffnen bzw. Schließen von APair (AOpen) mit Schlüssel AKey?
  function Matches(AStatement: TSyntaxNode; const APair: TStatePair; AOpen: Boolean; out AKey: string): Boolean;
  var
    Name: string;
    Arg: Integer;
    Call: TMethodCall;
    Found, Receiver: TSyntaxNode;
  begin
    AKey := '';
    if AOpen then
    begin
      Name := APair.Open;
      Arg := APair.OpenArg;
    end
    else
    begin
      Name := APair.Close;
      Arg := APair.CloseArg;
    end;
    if IsAssignPair(Name) then
    begin
      Result := (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount = 2) and
        (NodeText(AContext.Text, AStatement[0]) = AssignTarget(Name));
      if Result then
        AKey := AssignTarget(Name);
      Exit;
    end;
    if (Arg <> -2) and TryMethodCall(AStatement, Call) and SameText(Call.Method, Name) then
    begin
      AKey := CallKey(Call.Call, Call.Receiver, Arg);
      Exit(True);
    end;
    // P := AllocMem(N) bzw. R := FindFirst(...): Aufruf auf der rechten Seite.
    Result := False;
    if AOpen and (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount = 2) then
    begin
      Found := FindCall(AStatement[1], Name, Receiver);
      if Found <> nil then
      begin
        AKey := CallKey(Found, Receiver, Arg);
        if AKey = '*' then
          AKey := NodeText(AContext.Text, AStatement[0]);
        Result := True;
      end;
    end;
  end;

  // Schließt ein finally eines try in AList ab AFrom das Paar mit AKey?
  function ClosedInFinally(AList: TSyntaxNode; AFrom, APair: Integer; const AKey: string): Boolean;

    function Search(ANode: TSyntaxNode): Boolean;
    var
      Pending: TStack<TSyntaxNode>;
      Node: TSyntaxNode;
      Index: Integer;
      Key: string;
    begin
      // Iterativ (Bericht M1).
      Result := False;
      Pending := TStack<TSyntaxNode>.Create;
      try
        Pending.Push(ANode);
        while Pending.Count > 0 do
        begin
          Node := Pending.Pop;
          if Matches(Node, StatePairs[APair], False, Key) and (Key = AKey) then
            Exit(True);
          for Index := Node.ChildCount - 1 downto 0 do
            Pending.Push(Node[Index]);
        end;
      finally
        Pending.Free;
      end;
    end;

  var
    Index: Integer;
    Final: TSyntaxNode;
  begin
    for Index := AFrom to AList.ChildCount - 1 do
      if AList[Index].Kind = TSyntaxKind.TryStatement then
      begin
        Final := AList[Index].FindChild(TSyntaxKind.FinallyBlock);
        if (Final <> nil) and Search(Final) then
          Exit(True);
      end;
    Result := False;
  end;

  function CloseIndex(AList: TSyntaxNode; AFrom, APair: Integer; const AKey: string): Integer;
  var
    Index: Integer;
    Key: string;
  begin
    for Index := AFrom to AList.ChildCount - 1 do
      if Matches(AList[Index], StatePairs[APair], False, Key) and (Key = AKey) then
        Exit(Index);
    Result := -1;
  end;

  function CloseName(APair: Integer): string;
  begin
    Result := StatePairs[APair].Close;
    if IsAssignPair(Result) then
      Result := Trim(Copy(Result, 1, Length(Result) - Length(AssignSuffix)));
  end;

  // try/finally um die Anweisungen ab AFirst bis vor die Schließen-Anweisungen AFirstClose..ALastClose.
  function WrapFix(AList: TSyntaxNode; AFirst, AFirstClose, ALastClose: Integer): TArray<TRuleFix>;
  var
    Indent, Middle, Closes, LineBreak: string;
    Index: Integer;
    First: TSyntaxNode;
  begin
    Result := nil;
    if AFirst >= AFirstClose then
      Exit;
    LineBreak := TTextLines.LineBreakOf(AContext.Text);
    First := AList[AFirst];
    Indent := StringOfChar(' ', First.StartPos.Character);
    Middle := TrimRight(Copy(AContext.Text, First.StartOffset + 1, AList[AFirstClose].StartOffset -
      First.StartOffset));
    Middle := StringReplace(Middle, #10, #10'  ', [rfReplaceAll]);
    Closes := '';
    for Index := AFirstClose to ALastClose do
      Closes := Closes + LineBreak + Indent + '  ' + Trim(SourceText(AContext.Text, AList[Index])) + ';';
    Result := [TRuleFix.Create('In try/finally einschließen', [TRuleEdit.Create(
      TTextRange.Create(First.StartPos, AList[ALastClose].EndPos), 'try' + LineBreak + Indent + '  ' + Middle +
      LineBreak + Indent + 'finally' + Closes + LineBreak + Indent + 'end')])];
  end;

  // Meldung für Paare, deren Bereiche sich überlappen; am ersten Schließen, die übrigen Paare nennt sie mit.
  procedure ReportGroup(AList: TSyntaxNode; const AGroup: TArray<TOpening>; const ACloses: TArray<Integer>);
  var
    Index, Other, FirstClose, LastClose, LastOpen, Inner: Integer;
    Message, Others: string;
    Contiguous: Boolean;
  begin
    FirstClose := ACloses[0];
    LastClose := ACloses[0];
    LastOpen := AGroup[0].Index;
    Inner := 0;
    for Index := 0 to High(AGroup) do
    begin
      if ACloses[Index] < FirstClose then
      begin
        FirstClose := ACloses[Index];
        Inner := Index;
      end;
      if ACloses[Index] > LastClose then
        LastClose := ACloses[Index];
      if AGroup[Index].Index > LastOpen then
        LastOpen := AGroup[Index].Index;
    end;
    Others := '';
    for Index := 0 to High(AGroup) do
      if Index <> Inner then
      begin
        if Others <> '' then
          Others := Others + ', ';
        Others := Others + CloseName(AGroup[Index].Pair);
      end;
    Message := Format('%s steht nicht im finally; bei einer Exception %s.',
      [CloseName(AGroup[Inner].Pair), StatePairs[AGroup[Inner].Pair].Consequence]);
    if Others <> '' then
      Message := Message + Format(' Gleiches gilt für %s.', [Others]);
    // Korrektur nur, wenn alle Öffnungen vor dem ersten Schließen stehen und die Schließen-Anweisungen
    // verschieden sind und direkt aufeinander folgen.
    Contiguous := (LastOpen < FirstClose) and (LastClose - FirstClose + 1 = Length(AGroup));
    for Index := 0 to High(AGroup) do
      for Other := Index + 1 to High(AGroup) do
        if ACloses[Index] = ACloses[Other] then
          Contiguous := False;
    if Contiguous then
      AReport.Add(TTextRange.Create(AList[FirstClose].StartPos, AList[FirstClose].EndPos), Message,
        TRuleConfidence.High, WrapFix(AList, LastOpen + 1, FirstClose, LastClose))
    else
      AReport.Add(TTextRange.Create(AList[FirstClose].StartPos, AList[FirstClose].EndPos), Message,
        TRuleConfidence.High);
  end;

  // AOutside: Öffnen außerhalb der Liste (if FindFirst(...) = 0 then), Index -1.
  procedure CheckList(AList: TSyntaxNode; const AOutside: TArray<TOpening>);
  var
    Openings, Group: TArray<TOpening>;
    Opening: TOpening;
    Index, PairIndex, Close, Reach: Integer;
    Key: string;
    Closes: TArray<Integer>;
  begin
    Openings := AOutside;
    for Index := 0 to AList.ChildCount - 1 do
      for PairIndex := 0 to High(StatePairs) do
        if Matches(AList[Index], StatePairs[PairIndex], True, Key) and (Key <> '') then
        begin
          Opening.Pair := PairIndex;
          Opening.Index := Index;
          Opening.Key := Key;
          Openings := Openings + [Opening];
          Break;
        end;
    // Offene Paare mit ungeschütztem Schließen in derselben Liste; überlappende Paare zusammen.
    Group := nil;
    Closes := nil;
    Reach := -1;
    for Opening in Openings do
    begin
      Close := CloseIndex(AList, Opening.Index + 1, Opening.Pair, Opening.Key);
      if (Close < 0) or (Close <= Opening.Index + 1) or
        ClosedInFinally(AList, Opening.Index + 1, Opening.Pair, Opening.Key) then
        Continue;
      if (Group <> nil) and (Opening.Index > Reach) then
      begin
        ReportGroup(AList, Group, Closes);
        Group := nil;
        Closes := nil;
      end;
      Group := Group + [Opening];
      Closes := Closes + [Close];
      if Close > Reach then
        Reach := Close;
    end;
    if Group <> nil then
      ReportGroup(AList, Group, Closes);
  end;

  // if FindFirst(...) = 0 then begin … FindClose(SR) end: das Öffnen steht in der Bedingung.
  function ConditionOpening(AIf: TSyntaxNode; out AOpening: TOpening): Boolean;
  var
    PairIndex: Integer;
    Found, Receiver: TSyntaxNode;
  begin
    Result := False;
    if (AIf.ChildCount < 2) or (AIf[1].Kind <> TSyntaxKind.Block) then
      Exit;
    for PairIndex := 0 to High(StatePairs) do
      if not IsAssignPair(StatePairs[PairIndex].Open) then
      begin
        Found := FindCall(AIf[0], StatePairs[PairIndex].Open, Receiver);
        if Found <> nil then
        begin
          AOpening.Pair := PairIndex;
          AOpening.Index := -1;
          AOpening.Key := CallKey(Found, Receiver, StatePairs[PairIndex].OpenArg);
          Exit(AOpening.Key <> '');
        end;
      end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
    Opening: TOpening;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.IfStatement) and ConditionOpening(Node, Opening) then
          CheckList(Node[1], [Opening])
        else if IsStatementList(Node) and not ((Node.Kind = TSyntaxKind.Block) and (Node.Parent <> nil) and
          (Node.Parent.Kind = TSyntaxKind.IfStatement) and (Node.Parent[1] = Node) and
          ConditionOpening(Node.Parent, Opening)) then
          CheckList(Node, nil);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  StatePairs := Pairs(AContext.Options);
  Visit(AContext.Tree.Root);
end;

{ Gemeinsam für FreeOnTerminate }

/// <summary>Variable X bei X.FreeOnTerminate := True, sonst ''.</summary>
function FreeOnTerminateTarget(AStatement: TSyntaxNode): string;
var
  Target: TSyntaxNode;
begin
  Result := '';
  if (AStatement.Kind <> TSyntaxKind.AssignStatement) or (AStatement.ChildCount <> 2) then
    Exit;
  Target := AStatement[0];
  if (Target.Kind = TSyntaxKind.MemberAccess) and SameText(Target.Name, 'FreeOnTerminate') and
    (Target.ChildCount = 1) and (Target[0].Kind = TSyntaxKind.Identifier) and
    (AStatement[1].Kind = TSyntaxKind.Identifier) and SameText(AStatement[1].Name, 'True') then
    Result := Target[0].Name;
end;

/// <summary>Variable bei X.Free oder FreeAndNil(X), sonst ''.</summary>
function FreedVariable(AStatement: TSyntaxNode): string;
var
  Call: TMethodCall;
begin
  Result := '';
  if not TryMethodCall(AStatement, Call) then
    Exit;
  if SameText(Call.Method, 'Free') and (Call.Call = nil) then
    Result := VariableName(Call.Receiver)
  else if SameText(Call.Method, 'FreeAndNil') and (Call.Receiver = nil) and (Call.Call.ChildCount = 2) then
    Result := VariableName(Call.Call[1]);
end;

function IsAssignmentTo(AStatement: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (AStatement.Kind = TSyntaxKind.AssignStatement) and (AStatement.ChildCount > 0) and
    (AStatement[0].Kind = TSyntaxKind.Identifier) and SameText(AStatement[0].Name, AName);
end;

{ TThreadUseAfterFreeOnTerminateRule }

function TThreadUseAfterFreeOnTerminateRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-use-after-free-on-terminate', TRuleSeverity.Warning,
    'Thread mit FreeOnTerminate wird nach dem Start weiter benutzt');
end;

procedure TThreadUseAfterFreeOnTerminateRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);

  procedure CheckList(AList: TSyntaxNode);
  var
    Index: Integer;
    Statement: TSyntaxNode;
    Call: TMethodCall;
    Name: string;
    Started: Boolean;
  begin
    Name := '';
    Started := False;
    for Index := 0 to AList.ChildCount - 1 do
    begin
      Statement := AList[Index];
      if Started then
      begin
        if not Mentions(Statement, Name) then
          Continue;
        // Neue Zuweisung beendet die Beobachtung; Free meldet thread-free-with-free-on-terminate.
        if not IsAssignmentTo(Statement, Name) and not SameText(FreedVariable(Statement), Name) then
          AReport.Add(NodeRange(Statement), Format('"%s" gibt sich nach dem Start selbst frei (FreeOnTerminate); ' +
            'der Zugriff kann ein freigegebenes Objekt treffen', [Name]), TRuleConfidence.High);
        Name := '';
        Started := False;
        Continue;
      end;
      if FreeOnTerminateTarget(Statement) <> '' then
        Name := FreeOnTerminateTarget(Statement)
      else if (Name <> '') and TryMethodCall(Statement, Call) and
        (SameText(Call.Method, 'Start') or SameText(Call.Method, 'Resume')) and
        SameText(VariableName(Call.Receiver), Name) then
        Started := True;
    end;
  end;

var
  List: TSyntaxNode;
begin
  if AContext.Tree = nil then
    Exit;
  for List in StatementLists(AContext.Tree.Root) do
    CheckList(List);
end;

{ TThreadFreeWithFreeOnTerminateRule }

function TThreadFreeWithFreeOnTerminateRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-free-with-free-on-terminate', TRuleSeverity.Error,
    'Free auf einem Thread mit FreeOnTerminate');
end;

procedure TThreadFreeWithFreeOnTerminateRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);

  procedure CheckList(AList: TSyntaxNode);
  var
    Index: Integer;
    Statement: TSyntaxNode;
    Name: string;
  begin
    Name := '';
    for Index := 0 to AList.ChildCount - 1 do
    begin
      Statement := AList[Index];
      if FreeOnTerminateTarget(Statement) <> '' then
        Name := FreeOnTerminateTarget(Statement)
      else if (Name <> '') and IsAssignmentTo(Statement, Name) then
        Name := ''
      else if (Name <> '') and SameText(FreedVariable(Statement), Name) then
      begin
        AReport.Add(NodeRange(Statement), Format('"%s" gibt sich mit FreeOnTerminate selbst frei; Free führt zur ' +
          'Doppelfreigabe', [Name]), TRuleConfidence.High,
          [TRuleFix.Create('Free entfernen', [TRuleEdit.Create(StatementRemoval(AContext.Text, Statement), '')])]);
        Name := '';
      end;
    end;
  end;

var
  List: TSyntaxNode;
begin
  if AContext.Tree = nil then
    Exit;
  for List in StatementLists(AContext.Tree.Root) do
    CheckList(List);
end;

{ TSynchronizeInDestructorRule }

function TSynchronizeInDestructorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('synchronize-in-destructor', TRuleSeverity.Warning,
    'Synchronize im Destruktor eines Threads');
end;

type
  /// <summary>Eintrag der Suche in TSynchronizeInDestructorRule: Knoten und Tiefe der Aufrufe.</summary>
  TCallDepthEntry = record
    Node: TSyntaxNode;
    Depth: Integer;
  end;

function CallDepthEntry(ANode: TSyntaxNode; ADepth: Integer): TCallDepthEntry;
begin
  Result.Node := ANode;
  Result.Depth := ADepth;
end;

procedure TSynchronizeInDestructorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Threads: TArray<string>;
  Routines: TArray<TSyntaxNode>;

  function FindMethod(const AClass, AMethod: string): TSyntaxNode;
  var
    Routine: TSyntaxNode;
  begin
    for Routine in Routines do
      if SameText(Routine.Name, AClass + '.' + AMethod) then
        Exit(Routine);
    Result := nil;
  end;

  procedure Search(ABody: TSyntaxNode; const AClass: string);
  var
    Pending: TStack<TCallDepthEntry>;
    Entry: TCallDepthEntry;
    Index: Integer;
    Call: TMethodCall;
    Node, Callee, Body: TSyntaxNode;
  begin
    // Iterativ mit eigenem Stapel (Bericht M1); die Kinder rückwärts darauf, damit die Reihenfolge der Treffer die
    // der früheren Rekursion bleibt.
    Pending := TStack<TCallDepthEntry>.Create;
    try
      Pending.Push(CallDepthEntry(ABody, 0));
      while Pending.Count > 0 do
      begin
        Entry := Pending.Pop;
        Node := Entry.Node;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
          Continue;
        if ((Node.Kind = TSyntaxKind.MemberAccess) or (Node.Kind = TSyntaxKind.Identifier)) and
          SameText(Node.Name, 'Synchronize') then
        begin
          AReport.Add(NameRange(Node), 'Synchronize im Destruktor eines Threads: der Hauptthread wartet in WaitFor, ' +
            'der Thread auf Synchronize; beide verklemmen sich', TRuleConfidence.Medium);
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(CallDepthEntry(Node[Index], Entry.Depth));
        if Entry.Depth > 0 then
          Continue;
        // Eine Ebene tief in Methoden derselben Klasse, die der Destruktor aufruft; zuletzt auf den Stapel, damit
        // sie wie früher vor den Kindern des Aufrufs drankommen.
        Callee := nil;
        if TryMethodCall(Node, Call) and ((Call.Receiver = nil) or SameText(VariableName(Call.Receiver), 'Self')) then
          Callee := FindMethod(AClass, Call.Method)
        else if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount = 1) and
          (Node[0].Kind = TSyntaxKind.Identifier) then
          Callee := FindMethod(AClass, Node[0].Name);
        if Callee = nil then
          Continue;
        Body := Callee.FindChild(TSyntaxKind.Block);
        if Body <> nil then
          Pending.Push(CallDepthEntry(Body, 1));
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Routine, Body: TSyntaxNode;
begin
  if AContext.Tree = nil then
    Exit;
  Threads := SharedThreadClasses(AContext);
  if Threads = nil then
    Exit;
  Routines := nil;
  // Iterativ (Bericht M1); eingebettete Routinen zählen nicht als Methoden.
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if not Result then
        Routines := Routines + [ANode];
    end);
  for Routine in Routines do
    if (Pos('destructor', NodeText(AContext.Text, Routine)) = 1) and InList(Threads, ClassPart(Routine.Name)) then
    begin
      Body := Routine.FindChild(TSyntaxKind.Block);
      if Body <> nil then
        Search(Body, ClassPart(Routine.Name));
    end;
end;

{ TThreadResumeSuspendRule }

function TThreadResumeSuspendRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-resume-suspend', TRuleSeverity.Warning,
    'Veraltetes TThread.Resume oder Suspend');
end;

/// <summary>Ist AReceiver ein Bezeichner, dessen deklarierter Typ sicher kein Thread ist: Typ in der Datei
/// deklariert, Vorfahrenkette (Datei oder Index) vollständig bis TObject und ohne TThread (eigene Klassen mit
/// Pause/Resume wie TAtlasTimeClock)?</summary>
function KnownNonThread(ATypes: TDeclaredTypes; AAncestry: TAncestry; AReceiver: TSyntaxNode): Boolean;
var
  mType: string;
  mComplete, mObjectMissing: Boolean;
begin
  Result := False;
  if AReceiver.Kind <> TSyntaxKind.Identifier then
    Exit;
  mType := ATypes.DeclaredType(AReceiver.Name, AReceiver.StartPos);
  if (mType = '') or SameText(mType, 'TThread') or AAncestry.DescendsFrom(mType, 'TThread') then
    Exit;
  AAncestry.Ancestors(mType, mComplete, mObjectMissing);
  Result := mComplete;
end;

procedure TThreadResumeSuspendRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Report: IRuleReport;
  mTypes: TDeclaredTypes;
  mAncestry: TAncestry;
begin
  if AContext.Tree = nil then
    Exit;
  Report := AReport;
  mTypes := nil;
  mAncestry := nil;
  try
    // Iterativ (Bericht M1).
    AContext.Tree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      var
        Call: TMethodCall;
        Range: TTextRange;
      begin
        Result := True;
        // Nur X.Resume/X.Suspend ohne Argumente: Resume(…) gehört zu anderen Klassen.
        if not TryMethodCall(ANode, Call) or (Call.Call <> nil) or (Call.Receiver = nil) or
          not MatchText(Call.Method, ['Resume', 'Suspend']) then
          Exit;
        // Typen erst beim ersten Kandidaten bestimmen: Resume und Suspend sind selten.
        if mTypes = nil then
        begin
          mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
          mAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext),
            AContext));
        end;
        if KnownNonThread(mTypes, mAncestry, Call.Receiver) then
          Exit;
        Range := NameRange(Call.Member);
        if SameText(Call.Method, 'Resume') then
          Report.Add(Range, 'TThread.Resume ist veraltet; einen erzeugten Thread mit Start starten',
            TRuleConfidence.High, [TRuleFix.Create('Durch Start ersetzen', [TRuleEdit.Create(Range, 'Start')], True)])
        else
          Report.Add(Range, 'TThread.Suspend ist veraltet und kann den Thread mitten in einer Sperre anhalten; ' +
            'stattdessen mit einem Ereignis (TEvent) warten', TRuleConfidence.High);
      end);
  finally
    mAncestry.Free;
    mTypes.Free;
  end;
end;

/// <summary>Methode mit einem Parameter Sender: OnClick, OnTimer und Verwandte.</summary>
function IsEventHandler(ARoutine: TSyntaxNode): Boolean;
var
  Header, Params: TSyntaxNode;
  Index: Integer;
  Name: string;
begin
  Result := False;
  if Pos('.', ARoutine.Name) = 0 then
    Exit;
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
    Exit;
  Params := Header.FindChild(TSyntaxKind.Parameters);
  if Params = nil then
    Exit;
  for Index := 0 to Params.ChildCount - 1 do
    if Params[Index].Kind = TSyntaxKind.Parameter then
      for Name in SplitString(Params[Index].Name, ',') do
        if SameText(Trim(Name), 'Sender') then
          Exit(True);
end;

{ TProcessMessagesInLoopRule }

const
  ProcessMessagesAdvice = ' Besser die Arbeit in einen Thread oder TTask auslagern oder den Auslöser bis zum ' +
    'Ende sperren.';

function TProcessMessagesInLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('processmessages-in-loop', TRuleSeverity.Hint,
    'Application.ProcessMessages in Schleifen');
end;

procedure TProcessMessagesInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  AllowIn: TArray<string>;

  function Allowed(const ARoutineName: string): Boolean;
  var
    Name: string;
  begin
    for Name in AllowIn do
      if SameText(Name, ARoutineName) or SameText(Name, MethodPart(ARoutineName)) then
        Exit(True);
    Result := False;
  end;

  function IsProcessMessages(ANode: TSyntaxNode): Boolean;
  var
    Call: TMethodCall;
  begin
    Result := TryMethodCall(ANode, Call) and SameText(Call.Method, 'ProcessMessages') and
      (Call.Receiver <> nil) and SameText(MethodPart(NodeText(AContext.Text, Call.Receiver)), 'application');
  end;

  procedure Visit(ANode: TSyntaxNode; ALoops: Integer; AHandler, AAllowed: Boolean);
  var
    Pending: TStack<TSyntaxNode>;
    LoopStack: TStack<Integer>;
    Handlers, Alloweds: TStack<Boolean>;
    Node: TSyntaxNode;
    Index, Loops: Integer;
    Handler, IsAllowed: Boolean;
  begin
    // Iterativ (Bericht M1); parallele Stapel führen ALoops, AHandler und AAllowed je Knoten mit.
    Pending := TStack<TSyntaxNode>.Create;
    LoopStack := TStack<Integer>.Create;
    Handlers := TStack<Boolean>.Create;
    Alloweds := TStack<Boolean>.Create;
    try
      Pending.Push(ANode);
      LoopStack.Push(ALoops);
      Handlers.Push(AHandler);
      Alloweds.Push(AAllowed);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Loops := LoopStack.Pop;
        Handler := Handlers.Pop;
        IsAllowed := Alloweds.Pop;
        case Node.Kind of
          TSyntaxKind.RoutineDecl:
            begin
              Handler := IsEventHandler(Node);
              IsAllowed := Allowed(Node.Name);
              Loops := 0;
            end;
          // Anonyme Methoden laufen später oder in einem Thread (dort meldet thread-vcl-access).
          TSyntaxKind.AnonymousMethod:
            Continue;
          TSyntaxKind.CallStatement:
            if not IsAllowed and IsProcessMessages(Node) then
            begin
              if Loops > 0 then
                AReport.Add(NodeRange(Node), 'ProcessMessages in der Schleife erlaubt Wiedereintritt (zweiter ' +
                  'Klick, Formular schließen).' + ProcessMessagesAdvice, TRuleConfidence.Medium)
              else if Handler then
                AReport.Add(NodeRange(Node), 'ProcessMessages im Ereignis-Handler erlaubt Wiedereintritt (zweiter ' +
                  'Klick, Formular schließen).' + ProcessMessagesAdvice, TRuleConfidence.Medium);
              Continue;
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        if Node.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
          TSyntaxKind.RepeatStatement] then
          Inc(Loops);
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          LoopStack.Push(Loops);
          Handlers.Push(Handler);
          Alloweds.Push(IsAllowed);
        end;
      end;
    finally
      Alloweds.Free;
      Handlers.Free;
      LoopStack.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  AllowIn := TRuleOptions.Strings(AContext.Options, 'allowIn', nil);
  Visit(AContext.Tree.Root, 0, False, False);
end;

{ TQueueNilInPackageRule }

function TQueueNilInPackageRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('queue-nil-in-package', TRuleSeverity.Warning,
    'TThread.Queue(nil, …) in einem Package');
end;

class function TQueueNilInPackageRule.WrapperCall(const AWrapper, AMethod: string): string;
var
  Name, Rest: string;
  Paren: Integer;
begin
  Paren := Pos('(', AWrapper);
  if Paren > 0 then
  begin
    Name := TrimRight(Copy(AWrapper, 1, Paren - 1));
    Rest := Copy(AWrapper, Paren, MaxInt);
  end
  else
  begin
    Name := AWrapper;
    Rest := '(';
  end;
  if SameText(AMethod, 'ForceQueue') and EndsText('Queue', Name) and not EndsText('ForceQueue', Name) then
    Name := Copy(Name, 1, Length(Name) - Length('Queue')) + 'ForceQueue';
  Result := Name + Rest;
end;

procedure TQueueNilInPackageRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TArray<TPascalToken>;
  Code: TArray<Integer>;
  Wrapper, OkMarker, Where: string;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := Tokens[Code[APosition]];
  end;

  // Steht in der Zeile ALine ein Kommentar mit der Ausnahme?
  function MarkedOk(ALine: Integer): Boolean;
  var
    Item: TPascalToken;
  begin
    for Item in Tokens do
      if (Item.Kind = TPascalTokenKind.Comment) and (Item.StartPos.Line <= ALine) and (Item.EndPos.Line >= ALine) and
        ContainsText(Item.Text, OkMarker) then
        Exit(True);
    Result := False;
  end;

  // Anzahl der Argumente ab der öffnenden Klammer AOpen; -1 ohne schließende Klammer.
  function ArgumentCount(AOpen: Integer): Integer;
  var
    Position, Depth: Integer;
  begin
    Result := 1;
    Depth := 0;
    for Position := AOpen to High(Code) do
    begin
      if Token(Position).IsSymbol('(') or Token(Position).IsSymbol('[') then
        Inc(Depth)
      else if Token(Position).IsSymbol(')') or Token(Position).IsSymbol(']') then
      begin
        Dec(Depth);
        if Depth = 0 then
          Exit;
      end
      // Kommas in anonymen Methoden stehen in eigenen Klammern; begin … end zählt nicht.
      else if (Depth = 1) and Token(Position).IsSymbol(',') then
        Inc(Result);
    end;
    Result := -1;
  end;

  procedure CheckAt(AStart: Integer);
  var
    Method: string;
    Comma: Integer;
    Range, Replace: TTextRange;
    Fixes: TArray<TRuleFix>;
  begin
    // TThread . Queue|ForceQueue ( nil ,
    if (AStart + 5 > High(Code)) or not SameText(Token(AStart).Text, 'TThread') or
      not Token(AStart + 1).IsSymbol('.') or not Token(AStart + 3).IsSymbol('(') or
      not Token(AStart + 4).IsKeyword('nil') or not Token(AStart + 5).IsSymbol(',') then
      Exit;
    Method := Token(AStart + 2).Text;
    if not (SameText(Method, 'Queue') or SameText(Method, 'ForceQueue')) then
      Exit;
    if MarkedOk(Token(AStart).StartPos.Line) then
      Exit;
    Comma := AStart + 5;
    Range := TTextRange.Create(Token(AStart).StartPos, Token(AStart + 4).EndPos);
    Fixes := nil;
    // Nur mit genau zwei Argumenten: die Verzögerung von ForceQueue kennt der Wrapper nicht.
    if ArgumentCount(AStart + 3) = 2 then
    begin
      Replace := TTextRange.Create(Token(AStart).StartPos, Token(Comma).EndPos);
      // Steht das nächste Argument in derselben Zeile, fällt der Leerraum davor mit weg.
      if (Comma < High(Code)) and (Token(Comma + 1).StartPos.Line = Token(Comma).EndPos.Line) then
        Replace.EndPos := Token(Comma + 1).StartPos;
      Fixes := [TRuleFix.Create('Durch ' + WrapperCall(Wrapper, Method) + '…) ersetzen',
        [TTextEdit.Create(Replace, WrapperCall(Wrapper, Method))])];
    end;
    AReport.Add(Range, Format('%s(nil, …) in %s: der Eintrag kann nach dem Entladen des Packages laufen.',
      [Method, Where]), Fixes);
  end;

var
  Kind: TRuleApplicationKind;
  Index: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Text = '') then
    Exit;
  Kind := AContext.Application;
  // Ohne Projekt: die .dpk selbst.
  if Kind = TRuleApplicationKind.Unknown then
    Kind := TWritelnInGuiAppRule.ApplicationKind('', AContext.Text);
  if Kind <> TRuleApplicationKind.Package then
    Exit;
  Where := 'diesem Package';
  if AContext.ProjectName <> '' then
    Where := AContext.ProjectName + '.bpl';
  Wrapper := TRuleOptions.Text(AContext.Options, 'wrapper', DefaultWrapper);
  OkMarker := TRuleOptions.Text(AContext.Options, 'okMarker', DefaultOkMarker);
  Tokens := AContext.Tree.Tokens;
  Code := nil;
  for Index := 0 to High(Tokens) do
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      Code := Code + [Index];
  for Index := 0 to High(Code) do
    if Tokens[Code[Index]].Kind = TPascalTokenKind.Identifier then
      CheckAt(Index);
end;

{ TBlockingCallInMainThreadRule }

const
  FormBaseClasses: array[0..3] of string = ('TCustomForm', 'TForm', 'TCustomFrame', 'TFrame');
  WindowsWaitCalls: array[0..2] of string = ('Sleep', 'WaitForSingleObject', 'WaitForMultipleObjects');
  BlockingCallAdvice = ' Besser die Arbeit mit TTask.Run auslagern und das Ergebnis über TThread.Queue melden.';

function TBlockingCallInMainThreadRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('blocking-call-in-main-thread', TRuleSeverity.Warning,
    'Blockierender Aufruf im Hauptthread');
end;

class function TBlockingCallInMainThreadRule.TimeoutArgument(const ACall: string): Integer;
begin
  // Position des Timeouts in den Argumenten (ab 0); -1: Aufruf ohne Timeout, blockiert immer.
  if SameText(ACall, 'Sleep') or SameText(ACall, 'WaitFor') or SameText(ACall, 'Wait') then
    Result := 0
  else if SameText(ACall, 'WaitForSingleObject') then
    Result := 1
  else if SameText(ACall, 'WaitForMultipleObjects') then
    Result := 3
  else
    Result := -1;
end;

procedure TBlockingCallInMainThreadRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Calls: TArray<string>;
  MaxSleep: Integer;
  Ancestry: TAncestry;
  Threads: TArray<string>;

  // Methode eines Formulars oder Frames bzw. Ereignis-Handler außerhalb eines Threads.
  function InMainThread(ARoutine: TSyntaxNode): Boolean;
  var
    Owner, Base: string;
  begin
    Owner := ClassPart(ARoutine.Name);
    if (Owner = '') or InList(Threads, Owner) or Ancestry.DescendsFrom(Owner, 'TThread') then
      Exit(False);
    for Base in FormBaseClasses do
      if Ancestry.DescendsFrom(Owner, Base) then
        Exit(True);
    Result := IsEventHandler(ARoutine);
  end;

  // Timeout in Millisekunden: Zahl, INFINITE = MaxInt; -1 = unbekannt.
  function Milliseconds(ANode: TSyntaxNode): Integer;
  begin
    if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'INFINITE') then
      Exit(MaxInt);
    if (ANode.Kind <> TSyntaxKind.Literal) or not TryStrToInt(ANode.Name, Result) then
      Result := -1;
  end;

  function MentionsProcessMessages(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          SameText(Node.Name, 'ProcessMessages') then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  function Where(ARoutine: TSyntaxNode): string;
  var
    Method: string;
  begin
    Method := MethodPart(ARoutine.Name);
    if EndsText('Click', Method) then
      Result := 'im Click-Handler'
    else if IsEventHandler(ARoutine) then
      Result := 'im Ereignis-Handler ' + Method
    else
      Result := 'in ' + Method;
  end;

  // ACallee: Identifier oder MemberAccess mit dem Namen; AArgs: Aufruf mit Argumenten oder nil.
  procedure CheckCall(ACallee, AArgs: TSyntaxNode; ARoutine, ALoop: TSyntaxNode);
  var
    Name, Text, Receiver: string;
    Position, Timeout: Integer;
  begin
    Name := ACallee.Name;
    if not InList(Calls, Name) then
      Exit;
    // Sleep und die Wait-Funktionen der Windows-API ohne Empfänger (oder Winapi.Windows.…), WaitFor und Wait
    // mit Empfänger.
    if InList(WindowsWaitCalls, Name) then
    begin
      if (ACallee.Kind = TSyntaxKind.MemberAccess) and not MatchText(SourceText(AContext.Text, ACallee[0]),
        ['Windows', 'Winapi.Windows']) then
        Exit;
    end
    else if MatchText(Name, ['WaitFor', 'Wait']) and (ACallee.Kind <> TSyntaxKind.MemberAccess) then
      Exit;
    Position := TimeoutArgument(Name);
    Timeout := MaxInt;
    if (Position >= 0) and (AArgs <> nil) and (AArgs.ChildCount > Position + 1) then
      Timeout := Milliseconds(AArgs[Position + 1])
    else if SameText(Name, 'Sleep') then
      Exit;
    if AArgs <> nil then
      Text := SourceText(AContext.Text, AArgs)
    else
      Text := SourceText(AContext.Text, ACallee);
    if (Timeout >= 0) and (Timeout < MaxSleep) then
    begin
      // Kurzes Sleep nur in einer Warteschleife ohne ProcessMessages.
      if not SameText(Name, 'Sleep') or (ALoop = nil) or MentionsProcessMessages(ALoop) then
        Exit;
      AReport.Add(NameRange(ACallee), Format('Warteschleife mit Sleep %s blockiert den Hauptthread; die ' +
        'Oberfläche friert ein.', [Where(ARoutine)]) + BlockingCallAdvice, TRuleConfidence.Medium);
      Exit;
    end;
    Receiver := '';
    if ACallee.Kind = TSyntaxKind.MemberAccess then
      Receiver := VariableName(ACallee[0]);
    if SameText(Name, 'WaitFor') and ((AArgs = nil) or (AArgs.ChildCount = 1)) and (Receiver <> '') then
      AReport.Add(NameRange(ACallee), Format('WaitFor %s blockiert den Hauptthread; ruft %s Synchronize auf, ' +
        'hängt das Programm.', [Where(ARoutine), Receiver]) + BlockingCallAdvice, TRuleConfidence.Medium)
    else
      AReport.Add(NameRange(ACallee), Format('%s %s blockiert den Hauptthread; die Oberfläche friert ein.',
        [Text, Where(ARoutine)]) + BlockingCallAdvice, TRuleConfidence.Medium);
  end;

  procedure Visit(ANode: TSyntaxNode; ARoutine, ALoop: TSyntaxNode);
  var
    Pending, RoutineStack, LoopStack: TStack<TSyntaxNode>;
    Node, Routine, Loop: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1); parallele Stapel führen ARoutine und ALoop je Knoten mit.
    Pending := TStack<TSyntaxNode>.Create;
    RoutineStack := TStack<TSyntaxNode>.Create;
    LoopStack := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      RoutineStack.Push(ARoutine);
      LoopStack.Push(ALoop);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Routine := RoutineStack.Pop;
        Loop := LoopStack.Pop;
        case Node.Kind of
          TSyntaxKind.RoutineDecl:
            // Eingebettete Routinen gehören zur äußeren Methode.
            if Pos('.', Node.Name) > 0 then
            begin
              Routine := nil;
              if InMainThread(Node) then
                Routine := Node;
              Loop := nil;
            end;
          // Anonyme Methoden laufen oft in einem Thread oder später.
          TSyntaxKind.AnonymousMethod:
            Continue;
          TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.ForStatement,
          TSyntaxKind.ForInStatement:
            Loop := Node;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
        if Routine <> nil then
          if (Node.Kind = TSyntaxKind.Call) and (Node.ChildCount > 0) and
            (Node[0].Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
            CheckCall(Node[0], Node, Routine, Loop)
          else if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount > 0) and
            (Node[0].Kind = TSyntaxKind.MemberAccess) then
            CheckCall(Node[0], nil, Routine, Loop);
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          RoutineStack.Push(Routine);
          LoopStack.Push(Loop);
        end;
      end;
    finally
      LoopStack.Free;
      RoutineStack.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
    Exit;
  Calls := TRuleOptions.Strings(AContext.Options, 'calls', ['Sleep', 'WaitFor', 'WaitForSingleObject',
    'WaitForMultipleObjects', 'Wait']);
  MaxSleep := TRuleOptions.Int(AContext.Options, 'maxSleepMs', 50);
  Threads := ThreadClasses(AContext.Tree.Root);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    Visit(AContext.Tree.Root, nil, nil);
  finally
    Ancestry.Free;
  end;
end;

{ TThreadLoopWithoutTerminatedRule }

const
  ThreadWaitCalls: array[0..6] of string = ('Sleep', 'WaitFor', 'WaitForSingleObject', 'WaitForMultipleObjects',
    'MsgWaitForMultipleObjects', 'Wait', 'Yield');

function TThreadLoopWithoutTerminatedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-loop-without-terminated', TRuleSeverity.Warning,
    'Thread-Schleife ohne Terminated');
end;

procedure TThreadLoopWithoutTerminatedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Routines: TArray<TSyntaxNode>;
  Names: TArray<TArray<string>>;

  function IsConstant(ANode: TSyntaxNode; const AValue: string): Boolean;
  begin
    Result := (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) and SameText(ANode.Name, AValue);
  end;

  // Alle Bezeichner (auch hinter einem Punkt), ohne anonyme Methoden.
  procedure CollectNames(ANode: TSyntaxNode; var ANames: TArray<string>);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
          Continue;
        if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and not InList(ANames, Node.Name) then
          ANames := ANames + [Node.Name];
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  function MentionsAny(ANode: TSyntaxNode; const ACandidates: array of string): Boolean;
  var
    Found: TArray<string>;
    Name: string;
  begin
    Found := nil;
    CollectNames(ANode, Found);
    for Name in ACandidates do
      if InList(Found, Name) then
        Exit(True);
    Result := False;
  end;

  // Execute und die Methoden der Klasse, die nur aus Execute heraus (auch über andere solche Methoden) kommen.
  function ThreadRoutines(const AClass: string): TArray<TSyntaxNode>;
  var
    Reached: TArray<Integer>;
    Index, Other, Count: Integer;
    Method: string;
    Only: Boolean;

    function IsReached(AIndex: Integer): Boolean;
    var
      Item: Integer;
    begin
      for Item in Reached do
        if Item = AIndex then
          Exit(True);
      Result := False;
    end;

  begin
    Result := nil;
    Reached := nil;
    for Index := 0 to High(Routines) do
      if SameText(Routines[Index].Name, AClass + '.Execute') then
        Reached := Reached + [Index];
    if Reached = nil then
      Exit;
    repeat
      Count := Length(Reached);
      for Index := 0 to High(Routines) do
      begin
        if IsReached(Index) or not SameText(ClassPart(Routines[Index].Name), AClass) then
          Continue;
        Method := MethodPart(Routines[Index].Name);
        Only := False;
        for Other := 0 to High(Routines) do
          if (Other <> Index) and InList(Names[Other], Method) then
          begin
            Only := IsReached(Other);
            if not Only then
              Break;
          end;
        if Only then
          Reached := Reached + [Index];
      end;
    until Count = Length(Reached);
    for Index in Reached do
      Result := Result + [Routines[Index]];
  end;

  function Fix(ALoop: TSyntaxNode): TArray<TRuleFix>;
  var
    Condition: TSyntaxNode;
    Text, Replacement: string;
  begin
    if ALoop.Kind = TSyntaxKind.WhileStatement then
      Condition := ALoop[0]
    else
      Condition := ALoop[ALoop.ChildCount - 1];
    Text := SourceText(AContext.Text, Condition);
    if Condition.Kind = TSyntaxKind.BinaryExpr then
      Text := '(' + Text + ')';
    if ALoop.Kind = TSyntaxKind.WhileStatement then
    begin
      if IsConstant(Condition, 'True') then
        Replacement := 'not Terminated'
      else
        Replacement := Text + ' and not Terminated';
    end
    else if IsConstant(Condition, 'False') then
      Replacement := 'Terminated'
    else
      Replacement := Text + ' or Terminated';
    Result := [TRuleFix.Create('Terminated in die Schleifenbedingung aufnehmen',
      [TRuleEdit.Create(NodeRange(Condition), Replacement)])];
  end;

  function HasMethod(const AName: string): Boolean;
  var
    Routine: TSyntaxNode;
  begin
    for Routine in Routines do
      if SameText(Routine.Name, AName) then
        Exit(True);
    Result := False;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
    Infinite: Boolean;
    Keyword: string;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
          Continue;
        if (Node.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]) and (Node.ChildCount >= 2) and
          not MentionsAny(Node, ['Terminated', 'CheckTerminated']) then
        begin
          if Node.Kind = TSyntaxKind.WhileStatement then
          begin
            Infinite := IsConstant(Node[0], 'True');
            Keyword := 'while';
          end
          else
          begin
            Infinite := IsConstant(Node[Node.ChildCount - 1], 'False');
            Keyword := 'repeat';
          end;
          // Endlosschleife oder Warteschleife: beide laufen weiter, bis jemand Terminated prüft.
          if Infinite or MentionsAny(Node, ThreadWaitCalls) then
            AReport.Add(TTextRange.Create(Node.StartPos, TTextPosition.Create(Node.StartPos.Line,
              Node.StartPos.Character + Length(Keyword))), 'Die Schleife prüft Terminated nicht; der Thread ' +
              'lässt sich nicht beenden.', TRuleConfidence.High, Fix(Node));
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Ancestry: TAncestry;
  Classes: TArray<string>;
  Index: Integer;
  Owner: string;
  Routine: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Execute') then
    Exit;
  Routines := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
        Routines := Routines + [ANode];
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
    end);
  SetLength(Names, Length(Routines));
  for Index := 0 to High(Routines) do
  begin
    Names[Index] := nil;
    CollectNames(Routines[Index], Names[Index]);
  end;
  Classes := SharedThreadClasses(AContext);
  Ancestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    for Routine in Routines do
    begin
      Owner := ClassPart(Routine.Name);
      if (Owner <> '') and not InList(Classes, Owner) and Ancestry.DescendsFrom(Owner, 'TThread') then
        Classes := Classes + [Owner];
    end;
  finally
    Ancestry.Free;
  end;
  for Owner in Classes do
    // Mit TerminatedSet beendet die Klasse ihre Schleifen auf eigenem Weg (Ereignis, Flag).
    if not HasMethod(Owner + '.TerminatedSet') then
      for Routine in ThreadRoutines(Owner) do
        Visit(Routine);
end;

/// <summary>Deklariert die Routine AName als lokale Variable (var-Abschnitt oder Inline-Variable)?</summary>
function DeclaresLocalVariable(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Node, Child: TSyntaxNode;
  Index: Integer;
  Name: string;
begin
  // Iterativ (Bericht M1); Pending hält die Knoten, deren Kinder noch zu prüfen sind.
  Result := False;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ARoutine);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      for Index := Node.ChildCount - 1 downto 0 do
      begin
        Child := Node[Index];
        if Child.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar] then
          for Name in SplitString(Child.Name, ',') do
            if SameText(Trim(Name), AName) then
              Exit(True);
        if Child.Kind <> TSyntaxKind.RoutineDecl then
          Pending.Push(Child);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

{ TAnonymousThreadNotStartedRule }

const
  AnonymousThreadMessage = 'Der anonyme Thread wird nie gestartet und nie freigegeben.';

function TAnonymousThreadNotStartedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('anonymous-thread-not-started', TRuleSeverity.Warning,
    'Anonymer Thread nie gestartet');
end;

procedure TAnonymousThreadNotStartedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  LineBreak: string;

  // TThread.CreateAnonymousThread(…) bzw. System.Classes.TThread.CreateAnonymousThread(…)?
  function IsCreation(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) and SameText(ANode[0].Name, 'CreateAnonymousThread') and
      (ANode[0].ChildCount > 0) and SameText(MethodPart(SourceText(AContext.Text, ANode[0][0])), 'TThread');
  end;

  // Wie benutzt die Routine die Variable sonst? Gestartet, nur Eigenschaften gesetzt oder weitergegeben.
  procedure Usage(ANode, AParent, AGrand, ATarget: TSyntaxNode; const AName: string; var AStarted,
    AEscapes: Boolean);
  var
    Pending, Parents, Grands: TStack<TSyntaxNode>;
    Node, Parent, Grand: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1); parallele Stapel führen Eltern- und Großelternknoten mit.
    Pending := TStack<TSyntaxNode>.Create;
    Parents := TStack<TSyntaxNode>.Create;
    Grands := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      Parents.Push(AParent);
      Grands.Push(AGrand);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Parent := Parents.Pop;
        Grand := Grands.Pop;
        if (Node <> ATarget) and (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, AName) then
        begin
          if (Parent <> nil) and (Parent.Kind = TSyntaxKind.MemberAccess) and (Parent[0] = Node) then
          begin
            if MatchText(Parent.Name, ['Start', 'Resume']) then
              AStarted := True
            else if not ((Grand <> nil) and (Grand.Kind = TSyntaxKind.AssignStatement) and (Grand[0] = Parent)) then
              AEscapes := True;
          end
          else
            AEscapes := True;
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          Parents.Push(Node);
          Grands.Push(Parent);
        end;
      end;
    finally
      Grands.Free;
      Parents.Free;
      Pending.Free;
    end;
  end;

  // T.Start; nach der letzten Anweisung derselben Liste, die T erwähnt.
  function StartFix(AAssign: TSyntaxNode; const AName: string): TArray<TRuleFix>;
  var
    List, Last: TSyntaxNode;
    Index, Position: Integer;
    Rest: string;
  begin
    Result := nil;
    List := AAssign.Parent;
    if (List = nil) or not IsStatementList(List) then
      Exit;
    Last := AAssign;
    Position := -1;
    for Index := 0 to List.ChildCount - 1 do
      if List[Index] = AAssign then
        Position := Index
      else if (Position >= 0) and Mentions(List[Index], AName) then
        Last := List[Index];
    Rest := Trim(Copy(Lines[Last.EndPos.Line], Last.EndPos.Character + 1, MaxInt));
    if ((Rest <> '') and (Rest <> ';')) or (Last.EndPos.Line >= High(Lines)) then
      Exit;
    Result := [TRuleFix.Create(Format('%s.Start ergänzen', [AName]), [TRuleEdit.Create(
      TTextRange.Create(Last.EndPos.Line + 1, 0, Last.EndPos.Line + 1, 0),
      TTextLines.IndentOf(Lines[AAssign.StartPos.Line]) + AName + '.Start;' + LineBreak)])];
  end;

  procedure Visit(ANode, ARoutine: TSyntaxNode);
  var
    Pending, RoutineStack: TStack<TSyntaxNode>;
    Node, Routine: TSyntaxNode;
    Index: Integer;
    Started, Escapes: Boolean;
    Creation, Target: TSyntaxNode;
    Name: string;
  begin
    // Iterativ (Bericht M1); RoutineStack führt ARoutine je Knoten mit.
    Pending := TStack<TSyntaxNode>.Create;
    RoutineStack := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      RoutineStack.Push(ARoutine);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Routine := RoutineStack.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
          Routine := Node;
        // TThread.CreateAnonymousThread(…); als eigene Anweisung.
        if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount > 0) and IsCreation(Node[0]) then
          AReport.Add(NameRange(Node[0][0]), AnonymousThreadMessage, TRuleConfidence.High,
            [TRuleFix.Create('.Start anhängen', [TRuleEdit.Create(TTextRange.Create(Node[0].EndPos, Node[0].EndPos),
            '.Start')])]);
        // T := TThread.CreateAnonymousThread(…); bzw. var T := …; mit lokaler Variable, die nie gestartet und
        // nicht weitergegeben wird.
        Creation := nil;
        Target := nil;
        Name := '';
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and (Routine <> nil) and
          (Node[0].Kind = TSyntaxKind.Identifier) and IsCreation(Node[1]) and
          DeclaresLocalVariable(Routine, Node[0].Name) then
        begin
          Creation := Node[1];
          Target := Node[0];
          Name := Target.Name;
        end
        else if (Node.Kind = TSyntaxKind.InlineVar) and (Node.ChildCount > 0) and (Pos(',', Node.Name) = 0) and
          (Routine <> nil) and IsCreation(Node[Node.ChildCount - 1]) then
        begin
          Creation := Node[Node.ChildCount - 1];
          Name := Node.Name;
        end;
        if Creation <> nil then
        begin
          Started := False;
          Escapes := False;
          Usage(Routine, nil, nil, Target, Name, Started, Escapes);
          if not Started and not Escapes then
            AReport.Add(NameRange(Creation[0]), AnonymousThreadMessage, TRuleConfidence.High,
              StartFix(Node, Name));
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          RoutineStack.Push(Routine);
        end;
      end;
    finally
      RoutineStack.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text,
    'CreateAnonymousThread') then
    Exit;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Visit(AContext.Tree.Root, nil);
end;

{ TTaskExceptionUnobservedRule }

function TTaskExceptionUnobservedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('task-exception-unobserved', TRuleSeverity.Hint,
    'Exception in TTask geht verloren');
end;

procedure TTaskExceptionUnobservedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  LineBreak: string;

  function IsTaskCall(ANode: TSyntaxNode; const AMethod: string): Boolean;
  begin
    Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 1) and
      (ANode[0].Kind = TSyntaxKind.MemberAccess) and SameText(ANode[0].Name, AMethod) and (ANode[0].ChildCount > 0) and
      SameText(MethodPart(SourceText(AContext.Text, ANode[0][0])), 'TTask');
  end;

  // TTask.Create(…).Start bzw. .Start(): der Create-Aufruf, sonst nil.
  function StartedCreate(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := nil;
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 1) then
      ANode := ANode[0];
    if (ANode.Kind = TSyntaxKind.MemberAccess) and SameText(ANode.Name, 'Start') and (ANode.ChildCount > 0) and
      IsTaskCall(ANode[0], 'Create') then
      Result := ANode[0];
  end;

  function Catches(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.TryStatement) and (Node.FindChild(TSyntaxKind.ExceptBlock) <> nil) then
          Exit(True);
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Erster Aufruf im Rumpf für die Meldung.
  function FirstCall(ANode: TSyntaxNode): string;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
    Call: TMethodCall;
  begin
    // Iterativ (Bericht M1), Vorordnung wie die frühere Rekursion; ein Aufruf ohne Namen lässt seine Kinder aus.
    Result := '';
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if TryMethodCall(Node, Call) then
        begin
          if Call.Method <> '' then
            Exit(Call.Method);
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Steht das Wort an APosition am Zeilenanfang und folgen höchstens Klammern, Komma und Semikolon?
  function OnOwnLine(const APosition: TTextPosition; ALength: Integer): Boolean;
  var
    Rest: string;
    Character: Char;
  begin
    Result := Trim(Copy(Lines[APosition.Line], 1, APosition.Character)) = '';
    Rest := Copy(Lines[APosition.Line], APosition.Character + ALength + 1, MaxInt);
    for Character in Rest do
      if not CharInSet(Character, [' ', #9, ')', ',', ';']) then
        Result := False;
  end;

  // Korrektur: Rumpf in try … except, Meldung über TThread.Queue im Hauptthread.
  function WrapFix(ABody: TSyntaxNode): TArray<TRuleFix>;
  var
    Edits: TArray<TRuleEdit>;
    Indent, Step, Dialogs, Text: string;
    Line: Integer;
    Used: TArray<string>;
    UsesEdit: TRuleEdit;
    UsedUnit: string;
  begin
    Result := nil;
    if (ABody.EndPos.Line - ABody.StartPos.Line < 2) or not OnOwnLine(ABody.StartPos, Length('begin')) or
      not OnOwnLine(TTextPosition.Create(ABody.EndPos.Line, ABody.EndPos.Character - Length('end')),
      Length('end')) then
      Exit;
    Indent := TTextLines.IndentOf(Lines[ABody.StartPos.Line]);
    Step := TRoutineBody.IndentUnit(AContext.Formatting);
    // Ein Edit für alle Zeilen zwischen begin und end: try, eingerückter Rumpf, except-Teil.
    Text := Indent + Step + 'try' + LineBreak;
    for Line := ABody.StartPos.Line + 1 to ABody.EndPos.Line - 1 do
      if Trim(Lines[Line]) = '' then
        Text := Text + Lines[Line] + LineBreak
      else
        Text := Text + Step + Lines[Line] + LineBreak;
    Edits := [TRuleEdit.Create(TTextRange.Create(ABody.StartPos.Line + 1, 0, ABody.EndPos.Line, 0), Text +
      Indent + Step + 'except' + LineBreak +
      Indent + Step + Step + 'on E: Exception do' + LineBreak +
      Indent + Step + Step + 'begin' + LineBreak +
      Indent + Step + Step + Step + 'var Fehler := E.Message;' + LineBreak +
      Indent + Step + Step + Step + 'TThread.Queue(nil,' + LineBreak + // mainthread-ok
      Indent + Step + Step + Step + Step + 'procedure' + LineBreak +
      Indent + Step + Step + Step + Step + 'begin' + LineBreak +
      Indent + Step + Step + Step + Step + Step + 'ShowMessage(Fehler);' + LineBreak +
      Indent + Step + Step + Step + Step + 'end);' + LineBreak +
      Indent + Step + Step + 'end;' + LineBreak +
      Indent + Step + 'end;' + LineBreak)];
    // ShowMessage aus Vcl.Dialogs bzw. FMX.Dialogs, Exception aus System.SysUtils.
    Used := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
    Dialogs := 'Vcl.Dialogs';
    for UsedUnit in Used do
      if StartsText('FMX.', UsedUnit) then
        Dialogs := 'FMX.Dialogs';
    if not TUsesClauses.IsUsed(Used, Dialogs, AContext.Namespaces) and
      TUsesClauses.AddUnit(AContext.Tree.Tokens, ABody.StartOffset, Dialogs, LineBreak, UsesEdit) then
      Edits := [UsesEdit] + Edits;
    if not TUsesClauses.IsUsed(Used, 'System.SysUtils', AContext.Namespaces) and
      TUsesClauses.AddUnit(AContext.Tree.Tokens, ABody.StartOffset, 'System.SysUtils', LineBreak, UsesEdit) then
      Edits := [UsesEdit] + Edits;
    Result := [TRuleFix.Create('Rumpf in try … except mit Meldung über TThread.Queue einschließen', Edits)];
  end;

  procedure Report(ACall: TSyntaxNode);
  var
    Method, Body: TSyntaxNode;
    Name: string;
  begin
    Method := ACall[1];
    if Method.Kind <> TSyntaxKind.AnonymousMethod then
      Exit;
    Body := Method.FindChild(TSyntaxKind.Block);
    if (Body = nil) or Catches(Body) then
      Exit;
    Name := FirstCall(Body);
    if Name = '' then
      Name := 'im Task'
    else
      Name := 'in ' + Name;
    AReport.Add(NameRange(ACall[0]), Format('Der Task wird nie abgefragt und fängt keine Exceptions; Fehler %s ' +
      'gehen verloren.', [Name]), TRuleConfidence.Medium, WrapFix(Body));
  end;

  // Wie oft erwähnt die Routine die Variable außer an ATarget: als V.Start und sonst?
  procedure CountUses(ANode, AParent, ATarget: TSyntaxNode; const AName: string; var AStarts, AOthers: Integer);
  var
    Pending, Parents: TStack<TSyntaxNode>;
    Node, Parent: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1); Parents führt den Elternknoten mit.
    Pending := TStack<TSyntaxNode>.Create;
    Parents := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      Parents.Push(AParent);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Parent := Parents.Pop;
        if (Node <> ATarget) and (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, AName) then
        begin
          if (Parent <> nil) and (Parent.Kind = TSyntaxKind.MemberAccess) and SameText(Parent.Name, 'Start') then
            Inc(AStarts)
          else
            Inc(AOthers);
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          Parents.Push(Node);
        end;
      end;
    finally
      Parents.Free;
      Pending.Free;
    end;
  end;

  // Run ohne jede weitere Erwähnung; Create nur mit V.Start.
  procedure CheckVariable(ARoutine, ATarget, AValue: TSyntaxNode; const AName: string);
  var
    Starts, Others: Integer;
  begin
    Starts := 0;
    Others := 0;
    CountUses(ARoutine, nil, ATarget, AName, Starts, Others);
    if Others > 0 then
      Exit;
    if (IsTaskCall(AValue, 'Run') and (Starts = 0)) or (IsTaskCall(AValue, 'Create') and (Starts > 0)) then
      Report(AValue);
  end;

  procedure Visit(ANode, ARoutine: TSyntaxNode);
  var
    Pending, RoutineStack: TStack<TSyntaxNode>;
    Node, Routine: TSyntaxNode;
    Index: Integer;
    Created: TSyntaxNode;
  begin
    // Iterativ (Bericht M1); RoutineStack führt ARoutine je Knoten mit.
    Pending := TStack<TSyntaxNode>.Create;
    RoutineStack := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      RoutineStack.Push(ARoutine);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Routine := RoutineStack.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
          Routine := Node;
        if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount > 0) then
        begin
          Created := StartedCreate(Node[0]);
          if IsTaskCall(Node[0], 'Run') then
            Report(Node[0])
          else if Created <> nil then
            Report(Created);
        end
        // Lokale Variable, die nie wieder vorkommt (bei Create nur in V.Start).
        else if (Routine <> nil) and (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
          (Node[0].Kind = TSyntaxKind.Identifier) and not SameText(Node[0].Name, 'Result') and
          (Pos('.', Node[0].Name) = 0) and DeclaresLocalVariable(Routine, Node[0].Name) then
          CheckVariable(Routine, Node[0], Node[1], Node[0].Name)
        else if (Routine <> nil) and (Node.Kind = TSyntaxKind.InlineVar) and (Node.ChildCount > 0) and
          (Pos(',', Node.Name) = 0) then
          CheckVariable(Routine, nil, Node[Node.ChildCount - 1], Node.Name);
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          RoutineStack.Push(Routine);
        end;
      end;
    finally
      RoutineStack.Free;
      Pending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'TTask') then
    Exit;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Visit(AContext.Tree.Root, nil);
end;

procedure RegisterConcurrencyRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TThreadVclAccessRule.Create);
  ARegistry.Register(TLockWithoutFinallyRule.Create);
  ARegistry.Register(TThreadUseAfterFreeOnTerminateRule.Create);
  ARegistry.Register(TThreadFreeWithFreeOnTerminateRule.Create);
  ARegistry.Register(TSynchronizeInDestructorRule.Create);
  ARegistry.Register(TThreadResumeSuspendRule.Create);
  ARegistry.Register(TPairWithoutFinallyRule.Create);
  ARegistry.Register(TProcessMessagesInLoopRule.Create);
  ARegistry.Register(TQueueNilInPackageRule.Create);
  ARegistry.Register(TBlockingCallInMainThreadRule.Create);
  ARegistry.Register(TThreadLoopWithoutTerminatedRule.Create);
  ARegistry.Register(TAnonymousThreadNotStartedRule.Create);
  ARegistry.Register(TTaskExceptionUnobservedRule.Create);
end;

end.
