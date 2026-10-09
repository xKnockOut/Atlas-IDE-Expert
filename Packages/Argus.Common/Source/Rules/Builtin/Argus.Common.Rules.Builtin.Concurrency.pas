unit Argus.Common.Rules.Builtin.Concurrency;

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
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Registry;

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

/// <summary>Klassen der Unit, die direkt oder über Klassen der Unit von TThread erben.</summary>
function ThreadClasses(ARoot: TSyntaxNode): TArray<string>;

procedure RegisterConcurrencyRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.JSON,
  Argus.Common.Configuration.Contract,
  Argus.Common.Documents.Contract;

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

/// <summary>True, wenn ANode oder ein Nachfahre den Bezeichner AName benutzt.</summary>
function Mentions(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName) then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if Mentions(ANode[Index], AName) then
      Exit(True);
  Result := False;
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

  procedure Collect(ANode: TSyntaxNode);
  var
    Index: Integer;
    ClassNode, Ancestor: TSyntaxNode;
  begin
    if ANode.Kind = TSyntaxKind.TypeDecl then
    begin
      ClassNode := ANode.FindChild(TSyntaxKind.ClassType);
      if ClassNode <> nil then
      begin
        Ancestor := ClassNode.FindChild(TSyntaxKind.TypeReference);
        if Ancestor <> nil then
        begin
          Names := Names + [ANode.Name];
          Parents := Parents + [Ancestor.Name];
        end;
      end;
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Collect(ANode[Index]);
  end;

var
  Index: Integer;
  Changed: Boolean;
begin
  Result := nil;
  Names := nil;
  Parents := nil;
  if ARoot = nil then
    Exit;
  Collect(ARoot);
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

procedure TThreadVclAccessRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Threads: TArray<string>;

  // Erster VCL-Zugriff in ANode außerhalb von Synchronize/Queue, sonst nil.
  function FindAccess(ANode: TSyntaxNode): TSyntaxNode;
  var
    Index: Integer;
    Call: TMethodCall;
  begin
    if TryMethodCall(ANode, Call) and (SameText(Call.Method, 'Synchronize') or SameText(Call.Method, 'Queue')) then
      Exit(nil);
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 0) and
      (SameText(ANode.Name, 'Synchronize') or SameText(ANode.Name, 'Queue')) then
      Exit(nil);
    if (ANode.Kind = TSyntaxKind.Identifier) and (InList(VclGlobals, ANode.Name) or InList(VclDialogs, ANode.Name)) then
      Exit(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Result := FindAccess(ANode[Index]);
      if Result <> nil then
        Exit;
    end;
    Result := nil;
  end;

  procedure CheckBody(ABody: TSyntaxNode);
  var
    Index: Integer;
    Statement, Access: TSyntaxNode;
    Code: string;
  begin
    for Index := 0 to ABody.ChildCount - 1 do
    begin
      Statement := ABody[Index];
      Access := FindAccess(Statement);
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

  // Anonyme Methoden als Argument von CreateAnonymousThread, TTask.Run/Create/Future.
  procedure VisitAnonymous(ANode: TSyntaxNode);
  var
    Index, Arg: Integer;
    Call: TSyntaxNode;
    Name: string;
    Body: TSyntaxNode;
  begin
    if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount > 1) then
    begin
      Call := ANode[0];
      Name := '';
      if (Call.Kind = TSyntaxKind.MemberAccess) and (Call.ChildCount = 1) then
        Name := LowerCase(VariableName(Call[0]) + '.' + Call.Name);
      if (Name = 'tthread.createanonymousthread') or (Name = 'ttask.run') or (Name = 'ttask.create') or
        (Name = 'ttask.future') then
        for Arg := 1 to ANode.ChildCount - 1 do
          if ANode[Arg].Kind = TSyntaxKind.AnonymousMethod then
          begin
            Body := ANode[Arg].FindChild(TSyntaxKind.Block);
            if Body <> nil then
              CheckBody(Body);
          end;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      VisitAnonymous(ANode[Index]);
  end;

  procedure VisitRoutines(ANode: TSyntaxNode);
  var
    Index: Integer;
    Body: TSyntaxNode;
  begin
    if ANode.Kind = TSyntaxKind.RoutineDecl then
    begin
      if SameText(MethodPart(ANode.Name), 'Execute') and InList(Threads, ClassPart(ANode.Name)) then
      begin
        Body := ANode.FindChild(TSyntaxKind.Block);
        if Body <> nil then
          CheckBody(Body);
      end;
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      VisitRoutines(ANode[Index]);
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Threads := ThreadClasses(AContext.Tree.Root);
  VisitRoutines(AContext.Tree.Root);
  VisitAnonymous(AContext.Tree.Root);
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

/// <summary>Schlüssel einer Sperre: Empfänger; bei TMonitor.Enter(X) und EnterCriticalSection(X) auch das Argument.</summary>
function LockKey(const AText: string; const ACall: TMethodCall): string;
begin
  if ACall.Receiver <> nil then
    Result := NodeText(AText, ACall.Receiver)
  else
    Result := '';
  if (ACall.Call <> nil) and (ACall.Call.ChildCount > 1) then
    Result := Result + '(' + NodeText(AText, ACall.Call[1]) + ')';
end;

function IsRelease(const AText: string; ANode: TSyntaxNode; const ARelease, AKey: string): Boolean;
var
  Call: TMethodCall;
begin
  Result := TryMethodCall(ANode, Call) and SameText(Call.Method, ARelease) and (LockKey(AText, Call) = AKey);
end;

/// <summary>True, wenn ein Finally-Block von ATry die Freigabe mit demselben Schlüssel enthält.</summary>
function ReleasesIn(const AText: string; ATry: TSyntaxNode; const ARelease, AKey: string): Boolean;

  function Search(ANode: TSyntaxNode): Boolean;
  var
    Index: Integer;
  begin
    if IsRelease(AText, ANode, ARelease, AKey) then
      Exit(True);
    for Index := 0 to ANode.ChildCount - 1 do
      if Search(ANode[Index]) then
        Exit(True);
    Result := False;
  end;

var
  Final: TSyntaxNode;
begin
  Final := ATry.FindChild(TSyntaxKind.FinallyBlock);
  Result := (Final <> nil) and Search(Final);
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
            ((AList.Kind = TSyntaxKind.TryStatement) and ReleasesIn(AContext.Text, AList, Pair.Release, Key)) then
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

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if IsStatementList(ANode) then
      CheckList(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if AContext.Tree = nil then
    Exit;
  Pairs := LockPairs(AContext.Options);
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

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if IsStatementList(ANode) then
      CheckList(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if AContext.Tree <> nil then
    Visit(AContext.Tree.Root);
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

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if IsStatementList(ANode) then
      CheckList(ANode);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if AContext.Tree <> nil then
    Visit(AContext.Tree.Root);
end;

{ TSynchronizeInDestructorRule }

function TSynchronizeInDestructorRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('synchronize-in-destructor', TRuleSeverity.Warning,
    'Synchronize im Destruktor eines Threads');
end;

procedure TSynchronizeInDestructorRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Threads: TArray<string>;
  Routines: TArray<TSyntaxNode>;

  procedure CollectRoutines(ANode: TSyntaxNode);
  var
    Index: Integer;
  begin
    if ANode.Kind = TSyntaxKind.RoutineDecl then
    begin
      Routines := Routines + [ANode];
      Exit;
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      CollectRoutines(ANode[Index]);
  end;

  function FindMethod(const AClass, AMethod: string): TSyntaxNode;
  var
    Routine: TSyntaxNode;
  begin
    for Routine in Routines do
      if SameText(Routine.Name, AClass + '.' + AMethod) then
        Exit(Routine);
    Result := nil;
  end;

  procedure Search(ANode: TSyntaxNode; const AClass: string; ADepth: Integer);
  var
    Index: Integer;
    Call: TMethodCall;
    Callee, Body: TSyntaxNode;
  begin
    if ANode.Kind = TSyntaxKind.AnonymousMethod then
      Exit;
    if ((ANode.Kind = TSyntaxKind.MemberAccess) or (ANode.Kind = TSyntaxKind.Identifier)) and
      SameText(ANode.Name, 'Synchronize') then
    begin
      AReport.Add(NameRange(ANode), 'Synchronize im Destruktor eines Threads: der Hauptthread wartet in WaitFor, ' +
        'der Thread auf Synchronize; beide verklemmen sich', TRuleConfidence.Medium);
      Exit;
    end;
    // Eine Ebene tief in Methoden derselben Klasse, die der Destruktor aufruft.
    if (ADepth = 0) and TryMethodCall(ANode, Call) and
      ((Call.Receiver = nil) or SameText(VariableName(Call.Receiver), 'Self')) then
    begin
      Callee := FindMethod(AClass, Call.Method);
      if Callee <> nil then
      begin
        Body := Callee.FindChild(TSyntaxKind.Block);
        if Body <> nil then
          Search(Body, AClass, 1);
      end;
    end
    else if (ADepth = 0) and (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and
      (ANode[0].Kind = TSyntaxKind.Identifier) then
    begin
      Callee := FindMethod(AClass, ANode[0].Name);
      if (Callee <> nil) and (Callee.FindChild(TSyntaxKind.Block) <> nil) then
        Search(Callee.FindChild(TSyntaxKind.Block), AClass, 1);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Search(ANode[Index], AClass, ADepth);
  end;

var
  Routine, Body: TSyntaxNode;
begin
  if AContext.Tree = nil then
    Exit;
  Threads := ThreadClasses(AContext.Tree.Root);
  if Threads = nil then
    Exit;
  Routines := nil;
  CollectRoutines(AContext.Tree.Root);
  for Routine in Routines do
    if (Pos('destructor', NodeText(AContext.Text, Routine)) = 1) and InList(Threads, ClassPart(Routine.Name)) then
    begin
      Body := Routine.FindChild(TSyntaxKind.Block);
      if Body <> nil then
        Search(Body, ClassPart(Routine.Name), 0);
    end;
end;

{ TThreadResumeSuspendRule }

function TThreadResumeSuspendRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-resume-suspend', TRuleSeverity.Warning,
    'Veraltetes TThread.Resume oder Suspend');
end;

procedure TThreadResumeSuspendRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);

  procedure Visit(ANode: TSyntaxNode);
  var
    Index: Integer;
    Call: TMethodCall;
    Range: TTextRange;
  begin
    // Nur X.Resume/X.Suspend ohne Argumente: Resume(…) gehört zu anderen Klassen.
    if TryMethodCall(ANode, Call) and (Call.Call = nil) and (Call.Receiver <> nil) then
    begin
      Range := NameRange(Call.Member);
      if SameText(Call.Method, 'Resume') then
        AReport.Add(Range, 'TThread.Resume ist veraltet; einen erzeugten Thread mit Start starten',
          TRuleConfidence.High, [TRuleFix.Create('Durch Start ersetzen', [TRuleEdit.Create(Range, 'Start')], True)])
      else if SameText(Call.Method, 'Suspend') then
        AReport.Add(Range, 'TThread.Suspend ist veraltet und kann den Thread mitten in einer Sperre anhalten; ' +
          'stattdessen mit einem Ereignis (TEvent) warten', TRuleConfidence.High);
    end;
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
  end;

begin
  if AContext.Tree <> nil then
    Visit(AContext.Tree.Root);
end;

procedure RegisterConcurrencyRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TThreadVclAccessRule.Create);
  ARegistry.Register(TLockWithoutFinallyRule.Create);
  ARegistry.Register(TThreadUseAfterFreeOnTerminateRule.Create);
  ARegistry.Register(TThreadFreeWithFreeOnTerminateRule.Create);
  ARegistry.Register(TSynchronizeInDestructorRule.Create);
  ARegistry.Register(TThreadResumeSuspendRule.Create);
end;

end.
