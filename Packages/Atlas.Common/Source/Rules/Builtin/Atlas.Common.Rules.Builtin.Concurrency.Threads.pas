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
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.RtlTypePatterns,
  Atlas.Common.Rules.Derived,
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
  mTarget: TSyntaxNode;
begin
  Result := '';
  if (AStatement.Kind <> TSyntaxKind.AssignStatement) or (AStatement.ChildCount <> 2) then
  begin
    Exit;
  end;
  mTarget := AStatement[0];
  if (mTarget.Kind = TSyntaxKind.MemberAccess) and SameText(mTarget.Name, 'FreeOnTerminate') and
    (mTarget.ChildCount = 1) and (mTarget[0].Kind = TSyntaxKind.Identifier) and IsTrueLiteral(AStatement[1]) then
  begin
    Result := mTarget[0].Name;
  end;
end;

/// <summary>Variable bei X.Free oder FreeAndNil(X), sonst ''.</summary>
function FreedVariable(AStatement: TSyntaxNode): string;
var
  mCall: TMethodCall;
begin
  Result := '';
  if not TryMethodCall(AStatement, mCall) then
  begin
    Exit;
  end;
  if SameText(mCall.Method, 'Free') and (mCall.Call = nil) then
  begin
    Result := VariableName(mCall.Receiver);
  end
  else if SameText(mCall.Method, 'FreeAndNil') and (mCall.Receiver = nil) and (mCall.Call.ChildCount = 2) then
  begin
    Result := VariableName(mCall.Call[1]);
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
    mIndex: Integer;
    mStatement: TSyntaxNode;
    mCall: TMethodCall;
    mName: string;
    mStarted: Boolean;
  begin
    mName := '';
    mStarted := False;
    for mIndex := 0 to AList.ChildCount - 1 do
    begin
      mStatement := AList[mIndex];
      if mStarted then
      begin
        if not Mentions(mStatement, mName) then
        begin
          Continue;
        end;
        // Neue Zuweisung beendet die Beobachtung; Free meldet thread-free-with-free-on-terminate.
        if not IsAssignmentTo(mStatement, mName) and not SameText(FreedVariable(mStatement), mName) then
        begin
          AReport.Add(NodeRange(mStatement), cTexts[TConcurrencyThreadsText.UsedAfterStart].Fmt([mName]),
            TRuleConfidence.High);
        end;
        mName := '';
        mStarted := False;
        Continue;
      end;
      if FreeOnTerminateTarget(mStatement) <> '' then
      begin
        mName := FreeOnTerminateTarget(mStatement);
      end
      else if (mName <> '') and TryMethodCall(mStatement, mCall) and
        (SameText(mCall.Method, 'Start') or SameText(mCall.Method, 'Resume')) and
        SameText(VariableName(mCall.Receiver), mName) then
      begin
        mStarted := True;
      end;
    end;
  end;

var
  mList: TSyntaxNode;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  for mList in StatementLists(AContext.Tree.Root) do
  begin
    CheckList(mList);
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
    mIndex: Integer;
    mStatement: TSyntaxNode;
    mName: string;
  begin
    mName := '';
    for mIndex := 0 to AList.ChildCount - 1 do
    begin
      mStatement := AList[mIndex];
      if FreeOnTerminateTarget(mStatement) <> '' then
      begin
        mName := FreeOnTerminateTarget(mStatement);
      end
      else if (mName <> '') and IsAssignmentTo(mStatement, mName) then
      begin
        mName := '';
      end
      else if (mName <> '') and SameText(FreedVariable(mStatement), mName) then
      begin
        AReport.Add(NodeRange(mStatement), cTexts[TConcurrencyThreadsText.DoubleFree].Fmt([mName]),
          TRuleConfidence.High,
          [TRuleFix.Create(cTexts[TConcurrencyThreadsText.RemoveFree].Text,
            [TRuleEdit.Create(StatementRemoval(AContext.Text, mStatement), '')])]);
        mName := '';
      end;
    end;
  end;

var
  mList: TSyntaxNode;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  for mList in StatementLists(AContext.Tree.Root) do
  begin
    CheckList(mList);
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
  mThreads: TArray<string>;
  mRoutines: TArray<TSyntaxNode>;

  function FindMethod(const AClass, AMethod: string): TSyntaxNode;
  var
    mRoutine: TSyntaxNode;
  begin
    for mRoutine in mRoutines do
    begin
      if SameText(mRoutine.Name, AClass + '.' + AMethod) then
      begin
        Exit(mRoutine);
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
    mPending: TStack<TCallDepthEntry>;
    mEntry: TCallDepthEntry;
    mIndex: Integer;
    mNode, mBody: TSyntaxNode;
  begin
    // Iterativ mit eigenem Stapel (Bericht M1); die Kinder rückwärts darauf, damit die Reihenfolge der Treffer die
    // der früheren Rekursion bleibt.
    mPending := TStack<TCallDepthEntry>.Create;
    try
      mPending.Push(CallDepthEntry(ABody, 0));
      while mPending.Count > 0 do
      begin
        mEntry := mPending.Pop;
        mNode := mEntry.Node;
        if mNode.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        if IsSynchronizeName(mNode) then
        begin
          AReport.Add(NameRange(mNode), cTexts[TConcurrencyThreadsText.SyncDestructor].Text, TRuleConfidence.Medium);
          Continue;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(CallDepthEntry(mNode[mIndex], mEntry.Depth));
        end;
        // Eine Ebene tief in Methoden derselben Klasse, die der Destruktor aufruft; zuletzt auf den Stapel, damit
        // sie wie früher vor den Kindern des Aufrufs drankommen.
        mBody := nil;
        if mEntry.Depth = 0 then
        begin
          mBody := CalleeBody(mNode, AClass);
        end;
        if mBody <> nil then
        begin
          mPending.Push(CallDepthEntry(mBody, 1));
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

var
  mRoutine, mBody: TSyntaxNode;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mThreads := SharedThreadClasses(AContext);
  if mThreads = nil then
  begin
    Exit;
  end;
  mRoutines := nil;
  // Iterativ (Bericht M1); eingebettete Routinen zählen nicht als Methoden.
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if not Result then
      begin
        mRoutines := mRoutines + [ANode];
      end;
    end);
  for mRoutine in mRoutines do
  begin
    if (Pos('destructor', NodeText(AContext.Text, mRoutine)) = 1) and InList(mThreads, ClassPart(mRoutine.Name)) then
    begin
      mBody := mRoutine.FindChild(TSyntaxKind.Block);
      if mBody <> nil then
      begin
        Search(mBody, ClassPart(mRoutine.Name));
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
  mReport: IRuleReport;
  mTypes: TDeclaredTypes;
  mAncestry: TAncestry;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mReport := AReport;
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
          mReport.Add(Range, cTexts[TConcurrencyThreadsText.ResumeDeprecated].Text,
            TRuleConfidence.High, [TRuleFix.Create(cTexts[TConcurrencyThreadsText.ReplaceWithStart].Text,
              [TRuleEdit.Create(Range, 'Start')], True)]);
        end
        else
        begin
          mReport.Add(Range, cTexts[TConcurrencyThreadsText.SuspendDeprecated].Text, TRuleConfidence.High);
        end;
      end);
  finally
    mAncestry.Free;
    mTypes.Free;
  end;
end;

{ TThreadLoopWithoutTerminatedRule }

const
  cThreadWaitCalls: array[0..6] of string = ('Sleep', 'WaitFor', 'WaitForSingleObject', 'WaitForMultipleObjects',
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
  mRoutines: TArray<TSyntaxNode>;
  mNames: TArray<TArray<string>>;

  function IsConstant(ANode: TSyntaxNode; const AValue: string): Boolean;
  begin
    Result := (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) and SameText(ANode.Name, AValue);
  end;

  // Alle Bezeichner (auch hinter einem Punkt), ohne anonyme Methoden.
  procedure CollectNames(ANode: TSyntaxNode; var ANames: TArray<string>);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1), Reihenfolge wie die frühere Rekursion.
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        if (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and not InList(ANames, mNode.Name) then
        begin
          ANames := ANames + [mNode.Name];
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

  function MentionsAny(ANode: TSyntaxNode; const ACandidates: array of string): Boolean;
  var
    mFound: TArray<string>;
    mName: string;
  begin
    mFound := nil;
    CollectNames(ANode, mFound);
    for mName in ACandidates do
    begin
      if InList(mFound, mName) then
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
    mMethod := MethodPart(mRoutines[AIndex].Name);
    mAny := False;
    Result := True;
    for mOther := 0 to High(mRoutines) do
    begin
      if (mOther <> AIndex) and InList(mNames[mOther], mMethod) then
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
    for mIndex := 0 to High(mRoutines) do
    begin
      if SameText(mRoutines[mIndex].Name, AClass + '.Execute') then
      begin
        mReached := mReached + [mIndex];
      end;
    end;
    repeat
      mCount := Length(mReached);
      for mIndex := 0 to High(mRoutines) do
      begin
        if (mReached <> nil) and not ContainsIndex(mReached, mIndex) and
          SameText(ClassPart(mRoutines[mIndex].Name), AClass) and CalledOnlyFrom(mIndex, mReached) then
        begin
          mReached := mReached + [mIndex];
        end;
      end;
    until mCount = Length(mReached);
    for mIndex in mReached do
    begin
      Result := Result + [mRoutines[mIndex]];
    end;
  end;

  function Fix(ALoop: TSyntaxNode): TArray<TRuleFix>;
  var
    mCondition: TSyntaxNode;
    mText, mReplacement: string;
  begin
    if ALoop.Kind = TSyntaxKind.WhileStatement then
    begin
      mCondition := ALoop[0];
    end
    else
    begin
      mCondition := ALoop[ALoop.ChildCount - 1];
    end;
    mText := SourceText(AContext.Text, mCondition);
    if mCondition.Kind = TSyntaxKind.BinaryExpr then
    begin
      mText := '(' + mText + ')';
    end;
    if ALoop.Kind = TSyntaxKind.WhileStatement then
    begin
      if IsConstant(mCondition, 'True') then
      begin
        mReplacement := 'not Terminated';
      end
      else
      begin
        mReplacement := mText + ' and not Terminated';
      end;
    end
    else if IsConstant(mCondition, 'False') then
    begin
      mReplacement := 'Terminated';
    end
    else
    begin
      mReplacement := mText + ' or Terminated';
    end;
    Result := [TRuleFix.Create(cTexts[TConcurrencyThreadsText.AddTerminated].Text,
      [TRuleEdit.Create(NodeRange(mCondition), mReplacement)])];
  end;

  function HasMethod(const AName: string): Boolean;
  var
    mRoutine: TSyntaxNode;
  begin
    for mRoutine in mRoutines do
    begin
      if SameText(mRoutine.Name, AName) then
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
    if mInfinite or MentionsAny(ANode, cThreadWaitCalls) then
    begin
      AReport.Add(TTextRange.Create(ANode.StartPos, TTextPosition.Create(ANode.StartPos.Line,
        ANode.StartPos.Character + Length(mKeyword))), cTexts[TConcurrencyThreadsText.NoTerminated].Text,
          TRuleConfidence.High, Fix(ANode));
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Continue;
        end;
        if (mNode.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]) and (mNode.ChildCount >= 2) and
          not MentionsAny(mNode, ['Terminated', 'CheckTerminated']) then
        begin
          CheckLoop(mNode);
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

var
  mAncestry: TAncestry;
  mClasses: TArray<string>;
  mIndex: Integer;
  mOwner: string;
  mRoutine: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Execute') then
  begin
    Exit;
  end;
  mRoutines := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if ANode.Kind = TSyntaxKind.RoutineDecl then
      begin
        mRoutines := mRoutines + [ANode];
      end;
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
    end);
  SetLength(mNames, Length(mRoutines));
  for mIndex := 0 to High(mRoutines) do
  begin
    mNames[mIndex] := nil;
    CollectNames(mRoutines[mIndex], mNames[mIndex]);
  end;
  mClasses := SharedThreadClasses(AContext);
  mAncestry := TAncestry.Create(AContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(AContext), AContext));
  try
    for mRoutine in mRoutines do
    begin
      mOwner := ClassPart(mRoutine.Name);
      if (mOwner <> '') and not InList(mClasses, mOwner) and mAncestry.DescendsFrom(mOwner, 'TThread') then
      begin
        mClasses := mClasses + [mOwner];
      end;
    end;
  finally
    mAncestry.Free;
  end;
  for mOwner in mClasses do
  begin
    // Mit TerminatedSet beendet die Klasse ihre Schleifen auf eigenem Weg (Ereignis, Flag).
    if not HasMethod(mOwner + '.TerminatedSet') then
    begin
      for mRoutine in ThreadRoutines(mOwner) do
      begin
        Visit(mRoutine);
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
  mLines: TArray<string>;
  mLineBreak: string;

  // TThread.CreateAnonymousThread(…) bzw. System.Classes.TThread.CreateAnonymousThread(…)?
  function IsCreation(ANode: TSyntaxNode): Boolean;
  begin
    Result := IsMemberCall(ANode, 'CreateAnonymousThread') and
      SameText(MethodPart(SourceText(AContext.Text, ANode[0][0])), 'TThread');
  end;

  // Wie benutzt die Routine die Variable sonst? Gestartet, nur Eigenschaften gesetzt oder weitergegeben.
  procedure Usage(ARoutine, ATarget: TSyntaxNode; const AName: string; out AStarted, AEscapes: Boolean);
  var
    mPending, mParents, mGrands: TStack<TSyntaxNode>;
    mNode, mParent, mGrand: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1); parallele Stapel führen Eltern- und Großelternknoten mit.
    AStarted := False;
    AEscapes := False;
    mPending := TStack<TSyntaxNode>.Create;
    mParents := TStack<TSyntaxNode>.Create;
    mGrands := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoutine);
      mParents.Push(nil);
      mGrands.Push(nil);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mParent := mParents.Pop;
        mGrand := mGrands.Pop;
        if (mNode <> ATarget) and (mNode.Kind = TSyntaxKind.Identifier) and SameText(mNode.Name, AName) then
        begin
          ClassifyUse(mNode, mParent, mGrand, AStarted, AEscapes);
          Continue;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
          mParents.Push(mNode);
          mGrands.Push(mParent);
        end;
      end;
    finally
      mGrands.Free;
      mParents.Free;
      mPending.Free;
    end;
  end;

  // T.Start; nach der letzten Anweisung derselben Liste, die T erwähnt.
  function StartFix(AAssign: TSyntaxNode; const AName: string): TArray<TRuleFix>;
  var
    mList, mLast: TSyntaxNode;
    mIndex, mPosition: Integer;
    mRest: string;
  begin
    Result := nil;
    mList := AAssign.Parent;
    if (mList = nil) or not IsStatementList(mList) then
    begin
      Exit;
    end;
    mLast := AAssign;
    mPosition := -1;
    for mIndex := 0 to mList.ChildCount - 1 do
    begin
      if mList[mIndex] = AAssign then
      begin
        mPosition := mIndex;
      end
      else if (mPosition >= 0) and Mentions(mList[mIndex], AName) then
      begin
        mLast := mList[mIndex];
      end;
    end;
    mRest := Trim(Copy(mLines[mLast.EndPos.Line], mLast.EndPos.Character + 1, MaxInt));
    if ((mRest <> '') and (mRest <> ';')) or (mLast.EndPos.Line >= High(mLines)) then
    begin
      Exit;
    end;
    Result := [TRuleFix.Create(cTexts[TConcurrencyThreadsText.AddStart].Fmt([AName]), [TRuleEdit.Create(
      TTextRange.Create(mLast.EndPos.Line + 1, 0, mLast.EndPos.Line + 1, 0),
      TTextLines.IndentOf(mLines[AAssign.StartPos.Line]) + AName + '.Start;' + mLineBreak)])];
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
    mPending, mRoutineStack: TStack<TSyntaxNode>;
    mNode, mRoutine: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1); RoutineStack führt ARoutine je Knoten mit.
    mPending := TStack<TSyntaxNode>.Create;
    mRoutineStack := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      mRoutineStack.Push(ARoutine);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mRoutine := mRoutineStack.Pop;
        if mNode.Kind = TSyntaxKind.RoutineDecl then
        begin
          mRoutine := mNode;
        end;
        CheckNode(mNode, mRoutine);
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
          mRoutineStack.Push(mRoutine);
        end;
      end;
    finally
      mRoutineStack.Free;
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text,
    'CreateAnonymousThread') then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
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
  mLines: TArray<string>;
  mLineBreak: string;

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
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1).
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.TryStatement) and (mNode.FindChild(TSyntaxKind.ExceptBlock) <> nil) then
        begin
          Exit(True);
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

  // Erster Aufruf im Rumpf für die Meldung.
  function FirstCall(ANode: TSyntaxNode): string;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
    mCall: TMethodCall;
  begin
    // Iterativ (Bericht M1), Vorordnung wie die frühere Rekursion; ein Aufruf ohne Namen lässt seine Kinder aus.
    Result := '';
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if TryMethodCall(mNode, mCall) then
        begin
          if mCall.Method <> '' then
          begin
            Exit(mCall.Method);
          end;
          Continue;
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

  // Steht das Wort an APosition am Zeilenanfang und folgen höchstens Klammern, Komma und Semikolon?
  function OnOwnLine(const APosition: TTextPosition; ALength: Integer): Boolean;
  var
    mRest: string;
    mCharacter: Char;
  begin
    Result := Trim(Copy(mLines[APosition.Line], 1, APosition.Character)) = '';
    mRest := Copy(mLines[APosition.Line], APosition.Character + ALength + 1, MaxInt);
    for mCharacter in mRest do
    begin
      if not CharInSet(mCharacter, [' ', #9, ')', ',', ';']) then
      begin
        Result := False;
      end;
    end;
  end;

  // except-Teil der Korrektur: Meldung über TThread.Queue im Hauptthread (AIndent: Einrückung von begin, AStep:
  // eine Stufe).
  function ExceptPart(const AIndent, AStep: string): string;
  begin
    Result := AIndent + AStep + 'except' + mLineBreak +
      AIndent + AStep + AStep + 'on E: Exception do' + mLineBreak +
      AIndent + AStep + AStep + 'begin' + mLineBreak +
      AIndent + AStep + AStep + AStep + 'var Fehler := E.Message;' + mLineBreak +
      AIndent + AStep + AStep + AStep + 'TThread.Queue(nil,' + mLineBreak + // mainthread-ok
      AIndent + AStep + AStep + AStep + AStep + 'procedure' + mLineBreak +
      AIndent + AStep + AStep + AStep + AStep + 'begin' + mLineBreak +
      AIndent + AStep + AStep + AStep + AStep + AStep + 'ShowMessage(Fehler);' + mLineBreak +
      AIndent + AStep + AStep + AStep + AStep + 'end);' + mLineBreak +
      AIndent + AStep + AStep + 'end;' + mLineBreak +
      AIndent + AStep + 'end;' + mLineBreak;
  end;

  // Korrektur: Rumpf in try … except, Meldung über TThread.Queue im Hauptthread.
  function WrapFix(ABody: TSyntaxNode): TArray<TRuleFix>;
  var
    mEdits: TArray<TRuleEdit>;
    mIndent, mStep, mDialogs, mText: string;
    mLine: Integer;
    mUsed: TArray<string>;
    mUsesEdit: TRuleEdit;
    mUsedUnit: string;
  begin
    Result := nil;
    if (ABody.EndPos.Line - ABody.StartPos.Line < 2) or not OnOwnLine(ABody.StartPos, Length('begin')) or
      not OnOwnLine(TTextPosition.Create(ABody.EndPos.Line, ABody.EndPos.Character - Length('end')),
      Length('end')) then
    begin
      Exit;
    end;
    mIndent := TTextLines.IndentOf(mLines[ABody.StartPos.Line]);
    mStep := TRoutineBody.IndentUnit(AContext.Formatting);
    // Ein Edit für alle Zeilen zwischen begin und end: try, eingerückter Rumpf, except-Teil.
    mText := mIndent + mStep + 'try' + mLineBreak;
    for mLine := ABody.StartPos.Line + 1 to ABody.EndPos.Line - 1 do
    begin
      if Trim(mLines[mLine]) = '' then
      begin
        mText := mText + mLines[mLine] + mLineBreak;
      end
      else
      begin
        mText := mText + mStep + mLines[mLine] + mLineBreak;
      end;
    end;
    mEdits := [TRuleEdit.Create(TTextRange.Create(ABody.StartPos.Line + 1, 0, ABody.EndPos.Line, 0), mText +
      ExceptPart(mIndent, mStep))];
    // ShowMessage aus Vcl.Dialogs bzw. FMX.Dialogs, Exception aus System.SysUtils.
    mUsed := TUsesClauses.UsedUnits(AContext.Tree.Tokens);
    mDialogs := 'Vcl.Dialogs';
    for mUsedUnit in mUsed do
    begin
      if StartsText('FMX.', mUsedUnit) then
      begin
        mDialogs := 'FMX.Dialogs';
      end;
    end;
    if not TUsesClauses.IsUsed(mUsed, mDialogs, AContext.Namespaces) and
      TUsesClauses.AddUnit(AContext.Tree.Tokens, ABody.StartOffset, mDialogs, mLineBreak, mUsesEdit) then
    begin
      mEdits := [mUsesEdit] + mEdits;
    end;
    if not TUsesClauses.IsUsed(mUsed, 'System.SysUtils', AContext.Namespaces) and
      TUsesClauses.AddUnit(AContext.Tree.Tokens, ABody.StartOffset, 'System.SysUtils', mLineBreak, mUsesEdit) then
    begin
      mEdits := [mUsesEdit] + mEdits;
    end;
    Result := [TRuleFix.Create(cTexts[TConcurrencyThreadsText.WrapTry].Text, mEdits)];
  end;

  procedure Report(ACall: TSyntaxNode);
  var
    mMethod, mBody: TSyntaxNode;
    mName: string;
  begin
    mMethod := ACall[1];
    if mMethod.Kind <> TSyntaxKind.AnonymousMethod then
    begin
      Exit;
    end;
    mBody := mMethod.FindChild(TSyntaxKind.Block);
    if (mBody = nil) or Catches(mBody) then
    begin
      Exit;
    end;
    mName := FirstCall(mBody);
    if mName = '' then
    begin
      mName := cTexts[TConcurrencyThreadsText.InTask].Text;
    end
    else
    begin
      mName := 'in ' + mName;
    end;
    AReport.Add(NameRange(ACall[0]), cTexts[TConcurrencyThreadsText.TaskLost].Fmt([mName]), TRuleConfidence.Medium,
      WrapFix(mBody));
  end;

  // Wie oft erwähnt die Routine die Variable außer an ATarget: als V.Start und sonst?
  procedure CountUses(ANode, AParent, ATarget: TSyntaxNode; const AName: string; var AStarts, AOthers: Integer);
  var
    mPending, mParents: TStack<TSyntaxNode>;
    mNode, mParent: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1); Parents führt den Elternknoten mit.
    mPending := TStack<TSyntaxNode>.Create;
    mParents := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      mParents.Push(AParent);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mParent := mParents.Pop;
        if (mNode <> ATarget) and (mNode.Kind = TSyntaxKind.Identifier) and SameText(mNode.Name, AName) then
        begin
          if (mParent <> nil) and (mParent.Kind = TSyntaxKind.MemberAccess) and SameText(mParent.Name, 'Start') then
          begin
            Inc(AStarts);
          end
          else
          begin
            Inc(AOthers);
          end;
          Continue;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
          mParents.Push(mNode);
        end;
      end;
    finally
      mParents.Free;
      mPending.Free;
    end;
  end;

  // Run ohne jede weitere Erwähnung; Create nur mit V.Start.
  procedure CheckVariable(ARoutine, ATarget, AValue: TSyntaxNode; const AName: string);
  var
    mStarts, mOthers: Integer;
  begin
    mStarts := 0;
    mOthers := 0;
    CountUses(ARoutine, nil, ATarget, AName, mStarts, mOthers);
    if mOthers > 0 then
    begin
      Exit;
    end;
    if (IsTaskCall(AValue, 'Run') and (mStarts = 0)) or (IsTaskCall(AValue, 'Create') and (mStarts > 0)) then
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
    mPending, mRoutineStack: TStack<TSyntaxNode>;
    mNode, mRoutine: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1); RoutineStack führt ARoutine je Knoten mit.
    mPending := TStack<TSyntaxNode>.Create;
    mRoutineStack := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      mRoutineStack.Push(ARoutine);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mRoutine := mRoutineStack.Pop;
        if mNode.Kind = TSyntaxKind.RoutineDecl then
        begin
          mRoutine := mNode;
        end;
        if (mNode.Kind = TSyntaxKind.CallStatement) and (mNode.ChildCount > 0) then
        begin
          CheckTaskStatement(mNode);
        end
        // Lokale Variable, die nie wieder vorkommt (bei Create nur in V.Start).
        else if IsLocalAssign(mNode, mRoutine) then
        begin
          CheckVariable(mRoutine, mNode[0], mNode[1], mNode[0].Name);
        end
        else if (mRoutine <> nil) and (mNode.Kind = TSyntaxKind.InlineVar) and (mNode.ChildCount > 0) and
          (Pos(',', mNode.Name) = 0) then
        begin
          CheckVariable(mRoutine, nil, mNode[mNode.ChildCount - 1], mNode.Name);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
          mRoutineStack.Push(mRoutine);
        end;
      end;
    finally
      mRoutineStack.Free;
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'TTask') then
  begin
    Exit;
  end;
  mLines := TTextLines.SplitLines(AContext.Text, mLineBreak);
  Visit(AContext.Tree.Root, nil);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Concurrency.Threads', cTexts);

end.
