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
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
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
  Threads := SharedThreadClasses(AContext);
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
    Callee: TSyntaxNode;
    Index: Integer;
  begin
    AReceiver := nil;
    if ANode.Kind = TSyntaxKind.Call then
    begin
      Callee := ANode[0];
      if ((Callee.Kind = TSyntaxKind.Identifier) or (Callee.Kind = TSyntaxKind.MemberAccess)) and
        SameText(Callee.Name, AName) then
      begin
        if (Callee.Kind = TSyntaxKind.MemberAccess) and (Callee.ChildCount > 0) then
          AReceiver := Callee[0];
        Exit(ANode);
      end;
    end;
    if ANode.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.AnonymousMethod,
      TSyntaxKind.RoutineDecl] then
      Exit(nil);
    for Index := 0 to ANode.ChildCount - 1 do
    begin
      Result := FindCall(ANode[Index], AName, AReceiver);
      if Result <> nil then
        Exit;
    end;
    Result := nil;
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
      Index: Integer;
      Key: string;
    begin
      if Matches(ANode, StatePairs[APair], False, Key) and (Key = AKey) then
        Exit(True);
      for Index := 0 to ANode.ChildCount - 1 do
        if Search(ANode[Index]) then
          Exit(True);
      Result := False;
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
    Index: Integer;
    Opening: TOpening;
  begin
    if (ANode.Kind = TSyntaxKind.IfStatement) and ConditionOpening(ANode, Opening) then
      CheckList(ANode[1], [Opening])
    else if IsStatementList(ANode) and not ((ANode.Kind = TSyntaxKind.Block) and (ANode.Parent <> nil) and
      (ANode.Parent.Kind = TSyntaxKind.IfStatement) and (ANode.Parent[1] = ANode) and
      ConditionOpening(ANode.Parent, Opening)) then
      CheckList(ANode, nil);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index]);
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
  Threads := SharedThreadClasses(AContext);
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

  // Methode mit einem Parameter Sender: OnClick, OnTimer und Verwandte.
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

  function IsProcessMessages(ANode: TSyntaxNode): Boolean;
  var
    Call: TMethodCall;
  begin
    Result := TryMethodCall(ANode, Call) and SameText(Call.Method, 'ProcessMessages') and
      (Call.Receiver <> nil) and SameText(MethodPart(NodeText(AContext.Text, Call.Receiver)), 'application');
  end;

  procedure Visit(ANode: TSyntaxNode; ALoops: Integer; AHandler, AAllowed: Boolean);
  var
    Index: Integer;
    Loops: Integer;
  begin
    case ANode.Kind of
      TSyntaxKind.RoutineDecl:
        begin
          AHandler := IsEventHandler(ANode);
          AAllowed := Allowed(ANode.Name);
          ALoops := 0;
        end;
      // Anonyme Methoden laufen später oder in einem Thread (dort meldet thread-vcl-access).
      TSyntaxKind.AnonymousMethod:
        Exit;
      TSyntaxKind.CallStatement:
        if not AAllowed and IsProcessMessages(ANode) then
        begin
          if ALoops > 0 then
            AReport.Add(NodeRange(ANode), 'ProcessMessages in der Schleife erlaubt Wiedereintritt (zweiter Klick, ' +
              'Formular schließen).' + ProcessMessagesAdvice, TRuleConfidence.Medium)
          else if AHandler then
            AReport.Add(NodeRange(ANode), 'ProcessMessages im Ereignis-Handler erlaubt Wiedereintritt (zweiter ' +
              'Klick, Formular schließen).' + ProcessMessagesAdvice, TRuleConfidence.Medium);
          Exit;
        end;
    end;
    Loops := ALoops;
    if ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
      TSyntaxKind.RepeatStatement] then
      Inc(Loops);
    for Index := 0 to ANode.ChildCount - 1 do
      Visit(ANode[Index], Loops, AHandler, AAllowed);
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
end;

end.
