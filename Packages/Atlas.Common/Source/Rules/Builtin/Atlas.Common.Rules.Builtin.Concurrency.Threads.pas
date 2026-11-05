unit Atlas.Common.Rules.Builtin.Concurrency.Threads;

// Nebenläufigkeitsregeln zur Lebensdauer von Threads und Tasks (Teil von Atlas.Common.Rules.Builtin.Concurrency,
// dort registriert): thread-use-after-free-on-terminate, thread-free-with-free-on-terminate,
// synchronize-in-destructor, thread-resume-suspend, thread-loop-without-terminated, anonymous-thread-not-started,
// task-exception-unobserved.

interface

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract;

type
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
  Atlas.Common.Rules.Options,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Builtin.Concurrency.Syntax,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TConcurrencyThreadsText = (UsedAfterStartTitle, UsedAfterStart, FreeTitle, DoubleFree, RemoveFree,
    SyncDestructorTitle, SyncDestructor, ResumeTitle, ResumeDeprecated, ReplaceWithStart, SuspendDeprecated,
    TerminatedTitle, AddTerminated, NoTerminated, AnonymousTitle, AddStart, AppendStart, TaskTitle, WrapTry, InTask,
    TaskLost, NeverStarted);

const
  cTexts: array[TConcurrencyThreadsText] of TAtlasText = (
    (De: 'Thread mit FreeOnTerminate wird nach dem Start weiter benutzt';
     En: 'Thread with FreeOnTerminate is used after the start'),
    (De: '"%s" gibt sich nach dem Start selbst frei (FreeOnTerminate); der Zugriff kann ein freigegebenes Objekt ' +
      'treffen';
     En: '"%s" frees itself after the start (FreeOnTerminate); the access can hit a freed object'),
    (De: 'Free auf einem Thread mit FreeOnTerminate'; En: 'Free on a thread with FreeOnTerminate'),
    (De: '"%s" gibt sich mit FreeOnTerminate selbst frei; Free führt zur Doppelfreigabe';
     En: '"%s" frees itself with FreeOnTerminate; Free leads to a double free'),
    (De: 'Free entfernen'; En: 'Remove Free'),
    (De: 'Synchronize im Destruktor eines Threads'; En: 'Synchronize in the destructor of a thread'),
    (De: 'Synchronize im Destruktor eines Threads: der Hauptthread wartet in WaitFor, der Thread auf Synchronize; ' +
      'beide verklemmen sich';
     En: 'Synchronize in the destructor of a thread: the main thread waits in WaitFor, the thread waits for ' +
      'Synchronize; both deadlock'),
    (De: 'Veraltetes TThread.Resume oder Suspend'; En: 'Deprecated TThread.Resume or Suspend'),
    (De: 'TThread.Resume ist veraltet; einen erzeugten Thread mit Start starten';
     En: 'TThread.Resume is deprecated; start a created thread with Start'),
    (De: 'Durch Start ersetzen'; En: 'Replace with Start'),
    (De: 'TThread.Suspend ist veraltet und kann den Thread mitten in einer Sperre anhalten; stattdessen mit einem ' +
      'Ereignis (TEvent) warten';
     En: 'TThread.Suspend is deprecated and can stop the thread in the middle of a lock; wait with an event (TEvent) ' +
      'instead'),
    (De: 'Thread-Schleife ohne Terminated'; En: 'Thread loop without Terminated'),
    (De: 'Terminated in die Schleifenbedingung aufnehmen'; En: 'Add Terminated to the loop condition'),
    (De: 'Die Schleife prüft Terminated nicht; der Thread lässt sich nicht beenden.';
     En: 'The loop does not check Terminated; the thread cannot be stopped.'),
    (De: 'Anonymer Thread nie gestartet'; En: 'Anonymous thread never started'),
    (De: '%s.Start ergänzen'; En: 'Add %s.Start'),
    (De: '.Start anhängen'; En: 'Append .Start'),
    (De: 'Exception in TTask geht verloren'; En: 'Exception in TTask is lost'),
    (De: 'Rumpf in try … except mit Meldung über TThread.Queue einschließen';
     En: 'Wrap the body in try … except with a message via TThread.Queue'),
    (De: 'im Task'; En: 'in the task'),
    (De: 'Der Task wird nie abgefragt und fängt keine Exceptions; Fehler %s gehen verloren.';
     En: 'The task is never queried and catches no exceptions; errors %s are lost.'),
    (De: 'Der anonyme Thread wird nie gestartet und nie freigegeben.';
     En: 'The anonymous thread is never started and never freed.'));

{$SCOPEDENUMS OFF}

{ Gemeinsam für FreeOnTerminate }

/// <summary>Ist ANode der Bezeichner True?</summary>
function IsTrueLiteral(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, 'True');
end;

/// <summary>Variable X bei X.FreeOnTerminate := True, sonst ''.</summary>
function FreeOnTerminateTarget(AStatement: TSyntaxNode): string;
var
  Target: TSyntaxNode;
begin
  Result := '';
  if (AStatement.Kind <> TSyntaxKind.AssignStatement) or (AStatement.ChildCount <> 2) then
  begin
    Exit;
  end;
  Target := AStatement[0];
  if (Target.Kind = TSyntaxKind.MemberAccess) and SameText(Target.Name, 'FreeOnTerminate') and
    (Target.ChildCount = 1) and (Target[0].Kind = TSyntaxKind.Identifier) and IsTrueLiteral(AStatement[1]) then
  begin
    Result := Target[0].Name;
  end;
end;

/// <summary>Variable bei X.Free oder FreeAndNil(X), sonst ''.</summary>
function FreedVariable(AStatement: TSyntaxNode): string;
var
  Call: TMethodCall;
begin
  Result := '';
  if not TryMethodCall(AStatement, Call) then
  begin
    Exit;
  end;
  if SameText(Call.Method, 'Free') and (Call.Call = nil) then
  begin
    Result := VariableName(Call.Receiver);
  end
  else if SameText(Call.Method, 'FreeAndNil') and (Call.Receiver = nil) and (Call.Call.ChildCount = 2) then
  begin
    Result := VariableName(Call.Call[1]);
  end;
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
    cTexts[TConcurrencyThreadsText.UsedAfterStartTitle].Text);
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
        begin
          Continue;
        end;
        // Neue Zuweisung beendet die Beobachtung; Free meldet thread-free-with-free-on-terminate.
        if not IsAssignmentTo(Statement, Name) and not SameText(FreedVariable(Statement), Name) then
        begin
          AReport.Add(NodeRange(Statement), cTexts[TConcurrencyThreadsText.UsedAfterStart].Fmt([Name]),
            TRuleConfidence.High);
        end;
        Name := '';
        Started := False;
        Continue;
      end;
      if FreeOnTerminateTarget(Statement) <> '' then
      begin
        Name := FreeOnTerminateTarget(Statement);
      end
      else if (Name <> '') and TryMethodCall(Statement, Call) and
        (SameText(Call.Method, 'Start') or SameText(Call.Method, 'Resume')) and
        SameText(VariableName(Call.Receiver), Name) then
      begin
        Started := True;
      end;
    end;
  end;

var
  List: TSyntaxNode;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  for List in StatementLists(AContext.Tree.Root) do
  begin
    CheckList(List);
  end;
end;

{ TThreadFreeWithFreeOnTerminateRule }

function TThreadFreeWithFreeOnTerminateRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-free-with-free-on-terminate', TRuleSeverity.Error,
    cTexts[TConcurrencyThreadsText.FreeTitle].Text);
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
      begin
        Name := FreeOnTerminateTarget(Statement);
      end
      else if (Name <> '') and IsAssignmentTo(Statement, Name) then
      begin
        Name := '';
      end
      else if (Name <> '') and SameText(FreedVariable(Statement), Name) then
      begin
        AReport.Add(NodeRange(Statement), cTexts[TConcurrencyThreadsText.DoubleFree].Fmt([Name]), TRuleConfidence.High,
          [TRuleFix.Create(cTexts[TConcurrencyThreadsText.RemoveFree].Text,
            [TRuleEdit.Create(StatementRemoval(AContext.Text, Statement), '')])]);
        Name := '';
      end;
    end;
  end;

var
  List: TSyntaxNode;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  for List in StatementLists(AContext.Tree.Root) do
  begin
    CheckList(List);
  end;
end;

{ TSynchronizeInDestructorRule }

function TSynchronizeInDestructorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('synchronize-in-destructor', TRuleSeverity.Warning,
    cTexts[TConcurrencyThreadsText.SyncDestructorTitle].Text);
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

/// <summary>Ist ANode der Name Synchronize (Aufruf oder X.Synchronize)?</summary>
function IsSynchronizeName(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Identifier]) and
    SameText(ANode.Name, 'Synchronize');
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
    begin
      if SameText(Routine.Name, AClass + '.' + AMethod) then
      begin
        Exit(Routine);
      end;
    end;
    Result := nil;
  end;

  // Rumpf der Methode von AClass, die die Anweisung ANode ohne Empfänger oder über Self aufruft; nil sonst.
  function CalleeBody(ANode: TSyntaxNode; const AClass: string): TSyntaxNode;
  var
    mCall: TMethodCall;
    mCallee: TSyntaxNode;
  begin
    mCallee := nil;
    if TryMethodCall(ANode, mCall) and ((mCall.Receiver = nil) or SameText(VariableName(mCall.Receiver), 'Self')) then
    begin
      mCallee := FindMethod(AClass, mCall.Method);
    end
    else if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Identifier) then
    begin
      mCallee := FindMethod(AClass, ANode[0].Name);
    end;
    Result := nil;
    if mCallee <> nil then
    begin
      Result := mCallee.FindChild(TSyntaxKind.Block);
    end;
  end;

  procedure Search(ABody: TSyntaxNode; const AClass: string);
  var
    Pending: TStack<TCallDepthEntry>;
    Entry: TCallDepthEntry;
    Index: Integer;
    Node, Body: TSyntaxNode;
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
        begin
          Continue;
        end;
        if IsSynchronizeName(Node) then
        begin
          AReport.Add(NameRange(Node), cTexts[TConcurrencyThreadsText.SyncDestructor].Text, TRuleConfidence.Medium);
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(CallDepthEntry(Node[Index], Entry.Depth));
        end;
        // Eine Ebene tief in Methoden derselben Klasse, die der Destruktor aufruft; zuletzt auf den Stapel, damit
        // sie wie früher vor den Kindern des Aufrufs drankommen.
        Body := nil;
        if Entry.Depth = 0 then
        begin
          Body := CalleeBody(Node, AClass);
        end;
        if Body <> nil then
        begin
          Pending.Push(CallDepthEntry(Body, 1));
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Routine, Body: TSyntaxNode;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Threads := SharedThreadClasses(AContext);
  if Threads = nil then
  begin
    Exit;
  end;
  Routines := nil;
  // Iterativ (Bericht M1); eingebettete Routinen zählen nicht als Methoden.
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if not Result then
      begin
        Routines := Routines + [ANode];
      end;
    end);
  for Routine in Routines do
  begin
    if (Pos('destructor', NodeText(AContext.Text, Routine)) = 1) and InList(Threads, ClassPart(Routine.Name)) then
    begin
      Body := Routine.FindChild(TSyntaxKind.Block);
      if Body <> nil then
      begin
        Search(Body, ClassPart(Routine.Name));
      end;
    end;
  end;
end;

{ TThreadResumeSuspendRule }

function TThreadResumeSuspendRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-resume-suspend', TRuleSeverity.Warning,
    cTexts[TConcurrencyThreadsText.ResumeTitle].Text);
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
  begin
    Exit;
  end;
  mType := ATypes.DeclaredType(AReceiver.Name, AReceiver.StartPos);
  if (mType = '') or SameText(mType, 'TThread') or AAncestry.DescendsFrom(mType, 'TThread') then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
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
        begin
          Exit;
        end;
        // Typen erst beim ersten Kandidaten bestimmen: Resume und Suspend sind selten.
        if mTypes = nil then
        begin
          mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
          mAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext),
            AContext));
        end;
        if KnownNonThread(mTypes, mAncestry, Call.Receiver) then
        begin
          Exit;
        end;
        Range := NameRange(Call.Member);
        if SameText(Call.Method, 'Resume') then
        begin
          Report.Add(Range, cTexts[TConcurrencyThreadsText.ResumeDeprecated].Text,
            TRuleConfidence.High, [TRuleFix.Create(cTexts[TConcurrencyThreadsText.ReplaceWithStart].Text,
              [TRuleEdit.Create(Range, 'Start')], True)]);
        end
        else
        begin
          Report.Add(Range, cTexts[TConcurrencyThreadsText.SuspendDeprecated].Text, TRuleConfidence.High);
        end;
      end);
  finally
    mAncestry.Free;
    mTypes.Free;
  end;
end;

{ TThreadLoopWithoutTerminatedRule }

const
  ThreadWaitCalls: array[0..6] of string = ('Sleep', 'WaitFor', 'WaitForSingleObject', 'WaitForMultipleObjects',
    'MsgWaitForMultipleObjects', 'Wait', 'Yield');

function TThreadLoopWithoutTerminatedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-loop-without-terminated', TRuleSeverity.Warning,
    cTexts[TConcurrencyThreadsText.TerminatedTitle].Text);
end;

/// <summary>Kommt AIndex in AItems vor?</summary>
function ContainsIndex(const AItems: TArray<Integer>; AIndex: Integer): Boolean;
var
  mItem: Integer;
begin
  Result := False;
  for mItem in AItems do
  begin
    Result := Result or (mItem = AIndex);
  end;
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
        begin
          Continue;
        end;
        if (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and not InList(ANames, Node.Name) then
        begin
          ANames := ANames + [Node.Name];
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

  function MentionsAny(ANode: TSyntaxNode; const ACandidates: array of string): Boolean;
  var
    Found: TArray<string>;
    Name: string;
  begin
    Found := nil;
    CollectNames(ANode, Found);
    for Name in ACandidates do
    begin
      if InList(Found, Name) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Ruft eine andere Routine die Methode der Routine AIndex auf, und kommen alle diese Aufrufer in AReached vor?
  function CalledOnlyFrom(AIndex: Integer; const AReached: TArray<Integer>): Boolean;
  var
    mOther: Integer;
    mMethod: string;
    mAny: Boolean;
  begin
    mMethod := MethodPart(Routines[AIndex].Name);
    mAny := False;
    Result := True;
    for mOther := 0 to High(Routines) do
    begin
      if (mOther <> AIndex) and InList(Names[mOther], mMethod) then
      begin
        mAny := True;
        Result := Result and ContainsIndex(AReached, mOther);
      end;
    end;
    Result := Result and mAny;
  end;

  // Execute und die Methoden der Klasse, die nur aus Execute heraus (auch über andere solche Methoden) kommen.
  function ThreadRoutines(const AClass: string): TArray<TSyntaxNode>;
  var
    mReached: TArray<Integer>;
    mIndex, mCount: Integer;
  begin
    Result := nil;
    mReached := nil;
    for mIndex := 0 to High(Routines) do
    begin
      if SameText(Routines[mIndex].Name, AClass + '.Execute') then
      begin
        mReached := mReached + [mIndex];
      end;
    end;
    repeat
      mCount := Length(mReached);
      for mIndex := 0 to High(Routines) do
      begin
        if (mReached <> nil) and not ContainsIndex(mReached, mIndex) and
          SameText(ClassPart(Routines[mIndex].Name), AClass) and CalledOnlyFrom(mIndex, mReached) then
        begin
          mReached := mReached + [mIndex];
        end;
      end;
    until mCount = Length(mReached);
    for mIndex in mReached do
    begin
      Result := Result + [Routines[mIndex]];
    end;
  end;

  function Fix(ALoop: TSyntaxNode): TArray<TRuleFix>;
  var
    Condition: TSyntaxNode;
    Text, Replacement: string;
  begin
    if ALoop.Kind = TSyntaxKind.WhileStatement then
    begin
      Condition := ALoop[0];
    end
    else
    begin
      Condition := ALoop[ALoop.ChildCount - 1];
    end;
    Text := SourceText(AContext.Text, Condition);
    if Condition.Kind = TSyntaxKind.BinaryExpr then
    begin
      Text := '(' + Text + ')';
    end;
    if ALoop.Kind = TSyntaxKind.WhileStatement then
    begin
      if IsConstant(Condition, 'True') then
      begin
        Replacement := 'not Terminated';
      end
      else
      begin
        Replacement := Text + ' and not Terminated';
      end;
    end
    else if IsConstant(Condition, 'False') then
    begin
      Replacement := 'Terminated';
    end
    else
    begin
      Replacement := Text + ' or Terminated';
    end;
    Result := [TRuleFix.Create(cTexts[TConcurrencyThreadsText.AddTerminated].Text,
      [TRuleEdit.Create(NodeRange(Condition), Replacement)])];
  end;

  function HasMethod(const AName: string): Boolean;
  var
    Routine: TSyntaxNode;
  begin
    for Routine in Routines do
    begin
      if SameText(Routine.Name, AName) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Meldet die Schleife ANode, wenn sie Terminated nicht prüft und endlos oder eine Warteschleife ist.
  procedure CheckLoop(ANode: TSyntaxNode);
  var
    mInfinite: Boolean;
    mKeyword: string;
  begin
    if ANode.Kind = TSyntaxKind.WhileStatement then
    begin
      mInfinite := IsConstant(ANode[0], 'True');
      mKeyword := 'while';
    end
    else
    begin
      mInfinite := IsConstant(ANode[ANode.ChildCount - 1], 'False');
      mKeyword := 'repeat';
    end;
    // Endlosschleife oder Warteschleife: beide laufen weiter, bis jemand Terminated prüft.
    if mInfinite or MentionsAny(ANode, ThreadWaitCalls) then
    begin
      AReport.Add(TTextRange.Create(ANode.StartPos, TTextPosition.Create(ANode.StartPos.Line,
        ANode.StartPos.Character + Length(mKeyword))), cTexts[TConcurrencyThreadsText.NoTerminated].Text,
          TRuleConfidence.High, Fix(ANode));
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        if (Node.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]) and (Node.ChildCount >= 2) and
          not MentionsAny(Node, ['Terminated', 'CheckTerminated']) then
        begin
          CheckLoop(Node);
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
  Ancestry: TAncestry;
  Classes: TArray<string>;
  Index: Integer;
  Owner: string;
  Routine: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Execute') then
  begin
    Exit;
  end;
  Routines := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        Routines := Routines + [ANode];
      end;
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
      begin
        Classes := Classes + [Owner];
      end;
    end;
  finally
    Ancestry.Free;
  end;
  for Owner in Classes do
  begin
    // Mit TerminatedSet beendet die Klasse ihre Schleifen auf eigenem Weg (Ereignis, Flag).
    if not HasMethod(Owner + '.TerminatedSet') then
    begin
      for Routine in ThreadRoutines(Owner) do
      begin
        Visit(Routine);
      end;
    end;
  end;
end;

/// <summary>Nennt die Deklaration ANode ("A, B: T") den Namen AName?</summary>
function DeclaresName(ANode: TSyntaxNode; const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in SplitString(ANode.Name, ',') do
  begin
    Result := Result or SameText(Trim(mName), AName);
  end;
end;

/// <summary>Deklariert die Routine AName als lokale Variable (var-Abschnitt oder Inline-Variable)?</summary>
function DeclaresLocalVariable(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mPending: TStack<TSyntaxNode>;
  mNode, mChild: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (Bericht M1); mPending hält die Knoten, deren Kinder noch zu prüfen sind.
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoutine);
    while not Result and (mPending.Count > 0) do
    begin
      mNode := mPending.Pop;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mChild := mNode[mIndex];
        Result := Result or ((mChild.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar]) and
          DeclaresName(mChild, AName));
        if mChild.Kind <> TSyntaxKind.RoutineDecl then
        begin
          mPending.Push(mChild);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Ist ANode ein Aufruf X.AMethod(…)?</summary>
function IsMemberCall(ANode: TSyntaxNode; const AMethod: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) and
    (ANode[0].Kind = TSyntaxKind.MemberAccess) and SameText(ANode[0].Name, AMethod) and (ANode[0].ChildCount > 0);
end;

/// <summary>Ist AParent.Ziel einer Zuweisung (AGrand: AParent := …)?</summary>
function IsAssignTarget(AGrand, AParent: TSyntaxNode): Boolean;
begin
  Result := (AGrand <> nil) and (AGrand.Kind = TSyntaxKind.AssignStatement) and (AGrand[0] = AParent);
end;

/// <summary>Ordnet eine Erwähnung ANode der Thread-Variablen ein (AParent, AGrand: Eltern- und Großelternknoten):
/// .Start/.Resume startet, Zuweisen einer Eigenschaft ist harmlos, alles andere gibt die Variable weiter.</summary>
procedure ClassifyUse(ANode, AParent, AGrand: TSyntaxNode; var AStarted, AEscapes: Boolean);
begin
  if (AParent = nil) or (AParent.Kind <> TSyntaxKind.MemberAccess) or (AParent[0] <> ANode) then
  begin
    AEscapes := True;
  end
  else if MatchText(AParent.Name, ['Start', 'Resume']) then
  begin
    AStarted := True;
  end
  else if not IsAssignTarget(AGrand, AParent) then
  begin
    AEscapes := True;
  end;
end;

{ TAnonymousThreadNotStartedRule }


function TAnonymousThreadNotStartedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('anonymous-thread-not-started', TRuleSeverity.Warning,
    cTexts[TConcurrencyThreadsText.AnonymousTitle].Text);
end;

procedure TAnonymousThreadNotStartedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  LineBreak: string;

  // TThread.CreateAnonymousThread(…) bzw. System.Classes.TThread.CreateAnonymousThread(…)?
  function IsCreation(ANode: TSyntaxNode): Boolean;
  begin
    Result := IsMemberCall(ANode, 'CreateAnonymousThread') and
      SameText(MethodPart(SourceText(AContext.Text, ANode[0][0])), 'TThread');
  end;

  // Wie benutzt die Routine die Variable sonst? Gestartet, nur Eigenschaften gesetzt oder weitergegeben.
  procedure Usage(ARoutine, ATarget: TSyntaxNode; const AName: string; out AStarted, AEscapes: Boolean);
  var
    Pending, Parents, Grands: TStack<TSyntaxNode>;
    Node, Parent, Grand: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1); parallele Stapel führen Eltern- und Großelternknoten mit.
    AStarted := False;
    AEscapes := False;
    Pending := TStack<TSyntaxNode>.Create;
    Parents := TStack<TSyntaxNode>.Create;
    Grands := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ARoutine);
      Parents.Push(nil);
      Grands.Push(nil);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Parent := Parents.Pop;
        Grand := Grands.Pop;
        if (Node <> ATarget) and (Node.Kind = TSyntaxKind.Identifier) and SameText(Node.Name, AName) then
        begin
          ClassifyUse(Node, Parent, Grand, AStarted, AEscapes);
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
    begin
      Exit;
    end;
    Last := AAssign;
    Position := -1;
    for Index := 0 to List.ChildCount - 1 do
    begin
      if List[Index] = AAssign then
      begin
        Position := Index;
      end
      else if (Position >= 0) and Mentions(List[Index], AName) then
      begin
        Last := List[Index];
      end;
    end;
    Rest := Trim(Copy(Lines[Last.EndPos.Line], Last.EndPos.Character + 1, MaxInt));
    if ((Rest <> '') and (Rest <> ';')) or (Last.EndPos.Line >= High(Lines)) then
    begin
      Exit;
    end;
    Result := [TRuleFix.Create(cTexts[TConcurrencyThreadsText.AddStart].Fmt([AName]), [TRuleEdit.Create(
      TTextRange.Create(Last.EndPos.Line + 1, 0, Last.EndPos.Line + 1, 0),
      TTextLines.IndentOf(Lines[AAssign.StartPos.Line]) + AName + '.Start;' + LineBreak)])];
  end;

  // T := TThread.CreateAnonymousThread(…); bzw. var T := …; mit lokaler Variable: der Aufruf (ATarget: T bei der
  // Zuweisung, AName: der Name); nil sonst.
  function LocalCreation(ANode, ARoutine: TSyntaxNode; out ATarget: TSyntaxNode; out AName: string): TSyntaxNode;
  begin
    Result := nil;
    ATarget := nil;
    AName := '';
    if ARoutine = nil then
    begin
      Exit;
    end;
    if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
      (ANode[0].Kind = TSyntaxKind.Identifier) and IsCreation(ANode[1]) and
      DeclaresLocalVariable(ARoutine, ANode[0].Name) then
    begin
      Result := ANode[1];
      ATarget := ANode[0];
      AName := ATarget.Name;
    end
    else if (ANode.Kind = TSyntaxKind.InlineVar) and (ANode.ChildCount > 0) and (Pos(',', ANode.Name) = 0) and
      IsCreation(ANode[ANode.ChildCount - 1]) then
    begin
      Result := ANode[ANode.ChildCount - 1];
      AName := ANode.Name;
    end;
  end;

  // Meldet ANode, wenn es einen anonymen Thread anlegt, der nie gestartet wird.
  procedure CheckNode(ANode, ARoutine: TSyntaxNode);
  var
    mStarted, mEscapes: Boolean;
    mCreation, mTarget: TSyntaxNode;
    mName: string;
  begin
    // TThread.CreateAnonymousThread(…); als eigene Anweisung.
    if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount > 0) and IsCreation(ANode[0]) then
    begin
      AReport.Add(NameRange(ANode[0][0]), cTexts[TConcurrencyThreadsText.NeverStarted].Text, TRuleConfidence.High,
        [TRuleFix.Create(cTexts[TConcurrencyThreadsText.AppendStart].Text,
          [TRuleEdit.Create(TTextRange.Create(ANode[0].EndPos, ANode[0].EndPos),
        '.Start')])]);
    end;
    // Lokale Variable, die nie gestartet und nicht weitergegeben wird.
    mCreation := LocalCreation(ANode, ARoutine, mTarget, mName);
    if mCreation = nil then
    begin
      Exit;
    end;
    Usage(ARoutine, mTarget, mName, mStarted, mEscapes);
    if not mStarted and not mEscapes then
    begin
      AReport.Add(NameRange(mCreation[0]), cTexts[TConcurrencyThreadsText.NeverStarted].Text, TRuleConfidence.High,
        StartFix(ANode, mName));
    end;
  end;

  procedure Visit(ANode, ARoutine: TSyntaxNode);
  var
    Pending, RoutineStack: TStack<TSyntaxNode>;
    Node, Routine: TSyntaxNode;
    Index: Integer;
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
        begin
          Routine := Node;
        end;
        CheckNode(Node, Routine);
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
  begin
    Exit;
  end;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Visit(AContext.Tree.Root, nil);
end;

{ TTaskExceptionUnobservedRule }

function TTaskExceptionUnobservedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('task-exception-unobserved', TRuleSeverity.Hint,
    cTexts[TConcurrencyThreadsText.TaskTitle].Text);
end;

procedure TTaskExceptionUnobservedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Lines: TArray<string>;
  LineBreak: string;

  function IsTaskCall(ANode: TSyntaxNode; const AMethod: string): Boolean;
  begin
    Result := (ANode <> nil) and (ANode.ChildCount > 1) and IsMemberCall(ANode, AMethod) and
      SameText(MethodPart(SourceText(AContext.Text, ANode[0][0])), 'TTask');
  end;

  // TTask.Create(…).Start bzw. .Start(): der Create-Aufruf, sonst nil.
  function StartedCreate(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := nil;
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 1) then
    begin
      ANode := ANode[0];
    end;
    if (ANode.Kind = TSyntaxKind.MemberAccess) and SameText(ANode.Name, 'Start') and (ANode.ChildCount > 0) and
      IsTaskCall(ANode[0], 'Create') then
    begin
      Result := ANode[0];
    end;
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
        begin
          Exit(True);
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
          begin
            Exit(Call.Method);
          end;
          Continue;
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

  // Steht das Wort an APosition am Zeilenanfang und folgen höchstens Klammern, Komma und Semikolon?
  function OnOwnLine(const APosition: TTextPosition; ALength: Integer): Boolean;
  var
    Rest: string;
    Character: Char;
  begin
    Result := Trim(Copy(Lines[APosition.Line], 1, APosition.Character)) = '';
    Rest := Copy(Lines[APosition.Line], APosition.Character + ALength + 1, MaxInt);
    for Character in Rest do
    begin
      if not CharInSet(Character, [' ', #9, ')', ',', ';']) then
      begin
        Result := False;
      end;
    end;
  end;

  // except-Teil der Korrektur: Meldung über TThread.Queue im Hauptthread (AIndent: Einrückung von begin, AStep:
  // eine Stufe).
  function ExceptPart(const AIndent, AStep: string): string;
  begin
    Result := AIndent + AStep + 'except' + LineBreak +
      AIndent + AStep + AStep + 'on E: Exception do' + LineBreak +
      AIndent + AStep + AStep + 'begin' + LineBreak +
      AIndent + AStep + AStep + AStep + 'var Fehler := E.Message;' + LineBreak +
      AIndent + AStep + AStep + AStep + 'TThread.Queue(nil,' + LineBreak + // mainthread-ok
      AIndent + AStep + AStep + AStep + AStep + 'procedure' + LineBreak +
      AIndent + AStep + AStep + AStep + AStep + 'begin' + LineBreak +
      AIndent + AStep + AStep + AStep + AStep + AStep + 'ShowMessage(Fehler);' + LineBreak +
      AIndent + AStep + AStep + AStep + AStep + 'end);' + LineBreak +
      AIndent + AStep + AStep + 'end;' + LineBreak +
      AIndent + AStep + 'end;' + LineBreak;
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
    begin
      Exit;
    end;
    Indent := TTextLines.IndentOf(Lines[ABody.StartPos.Line]);
    Step := TRoutineBody.IndentUnit(AContext.Formatting);
    // Ein Edit für alle Zeilen zwischen begin und end: try, eingerückter Rumpf, except-Teil.
    Text := Indent + Step + 'try' + LineBreak;
    for Line := ABody.StartPos.Line + 1 to ABody.EndPos.Line - 1 do
    begin
      if Trim(Lines[Line]) = '' then
      begin
        Text := Text + Lines[Line] + LineBreak;
      end
      else
      begin
        Text := Text + Step + Lines[Line] + LineBreak;
      end;
    end;
    Edits := [TRuleEdit.Create(TTextRange.Create(ABody.StartPos.Line + 1, 0, ABody.EndPos.Line, 0), Text +
      ExceptPart(Indent, Step))];
    // ShowMessage aus Vcl.Dialogs bzw. FMX.Dialogs, Exception aus System.SysUtils.
    Used := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
    Dialogs := 'Vcl.Dialogs';
    for UsedUnit in Used do
    begin
      if StartsText('FMX.', UsedUnit) then
      begin
        Dialogs := 'FMX.Dialogs';
      end;
    end;
    if not TUsesClauses.IsUsed(Used, Dialogs, AContext.Namespaces) and
      TUsesClauses.AddUnit(AContext.Tree.Tokens, ABody.StartOffset, Dialogs, LineBreak, UsesEdit) then
    begin
      Edits := [UsesEdit] + Edits;
    end;
    if not TUsesClauses.IsUsed(Used, 'System.SysUtils', AContext.Namespaces) and
      TUsesClauses.AddUnit(AContext.Tree.Tokens, ABody.StartOffset, 'System.SysUtils', LineBreak, UsesEdit) then
    begin
      Edits := [UsesEdit] + Edits;
    end;
    Result := [TRuleFix.Create(cTexts[TConcurrencyThreadsText.WrapTry].Text, Edits)];
  end;

  procedure Report(ACall: TSyntaxNode);
  var
    Method, Body: TSyntaxNode;
    Name: string;
  begin
    Method := ACall[1];
    if Method.Kind <> TSyntaxKind.AnonymousMethod then
    begin
      Exit;
    end;
    Body := Method.FindChild(TSyntaxKind.Block);
    if (Body = nil) or Catches(Body) then
    begin
      Exit;
    end;
    Name := FirstCall(Body);
    if Name = '' then
    begin
      Name := cTexts[TConcurrencyThreadsText.InTask].Text;
    end
    else
    begin
      Name := 'in ' + Name;
    end;
    AReport.Add(NameRange(ACall[0]), cTexts[TConcurrencyThreadsText.TaskLost].Fmt([Name]), TRuleConfidence.Medium,
      WrapFix(Body));
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
          begin
            Inc(AStarts);
          end
          else
          begin
            Inc(AOthers);
          end;
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
    begin
      Exit;
    end;
    if (IsTaskCall(AValue, 'Run') and (Starts = 0)) or (IsTaskCall(AValue, 'Create') and (Starts > 0)) then
    begin
      Report(AValue);
    end;
  end;

  // TTask.Run(…); bzw. TTask.Create(…).Start; als Anweisung ANode.
  procedure CheckTaskStatement(ANode: TSyntaxNode);
  var
    mCreated: TSyntaxNode;
  begin
    mCreated := StartedCreate(ANode[0]);
    if IsTaskCall(ANode[0], 'Run') then
    begin
      Report(ANode[0]);
    end
    else if mCreated <> nil then
    begin
      Report(mCreated);
    end;
  end;

  // Zuweisung an eine lokale Variable der Routine ARoutine (nicht Result, kein Feld)?
  function IsLocalAssign(ANode, ARoutine: TSyntaxNode): Boolean;
  begin
    Result := (ARoutine <> nil) and (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount = 2) and
      (ANode[0].Kind = TSyntaxKind.Identifier);
    Result := Result and not SameText(ANode[0].Name, 'Result') and (Pos('.', ANode[0].Name) = 0) and
      DeclaresLocalVariable(ARoutine, ANode[0].Name);
  end;

  procedure Visit(ANode, ARoutine: TSyntaxNode);
  var
    Pending, RoutineStack: TStack<TSyntaxNode>;
    Node, Routine: TSyntaxNode;
    Index: Integer;
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
        begin
          Routine := Node;
        end;
        if (Node.Kind = TSyntaxKind.CallStatement) and (Node.ChildCount > 0) then
        begin
          CheckTaskStatement(Node);
        end
        // Lokale Variable, die nie wieder vorkommt (bei Create nur in V.Start).
        else if IsLocalAssign(Node, Routine) then
        begin
          CheckVariable(Routine, Node[0], Node[1], Node[0].Name);
        end
        else if (Routine <> nil) and (Node.Kind = TSyntaxKind.InlineVar) and (Node.ChildCount > 0) and
          (Pos(',', Node.Name) = 0) then
        begin
          CheckVariable(Routine, nil, Node[Node.ChildCount - 1], Node.Name);
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
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'TTask') then
  begin
    Exit;
  end;
  Lines := TTextLines.SplitLines(AContext.Text, LineBreak);
  Visit(AContext.Tree.Root, nil);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Concurrency.Threads', cTexts);

end.
