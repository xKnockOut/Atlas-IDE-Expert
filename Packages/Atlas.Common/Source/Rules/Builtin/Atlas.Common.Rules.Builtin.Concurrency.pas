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
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Concurrency.Syntax,
  Atlas.Common.Rules.Builtin.Concurrency.Threads,
  Atlas.Common.Rules.Builtin.Concurrency.MainThread,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TConcurrencyText = (VclTitle, VclAccess, WrapQueue, LockTitle, WrapTryFinally, LockNoFinally, PairTitle, StateStuck,
    NotInFinally, SameFor, GridFrozen, DisplayLocked, SearchHandleOpen, FileOpen, MemoryAllocated, CursorStuck);

const
  cTexts: array[TConcurrencyText] of TAtlasText = (
    (De: 'VCL-Zugriff aus einem Thread ohne Synchronize oder Queue';
     En: 'VCL access from a thread without Synchronize or Queue'),
    (De: '%s aus einem Thread: VCL-Zugriffe nur über Synchronize oder Queue';
     En: '%s from a thread: VCL access only via Synchronize or Queue'),
    (De: 'In TThread.Queue einschließen'; En: 'Wrap in TThread.Queue'),
    (De: 'Sperre ohne try/finally mit passender Freigabe'; En: 'Lock without try/finally with matching release'),
    (De: 'In try/finally einschließen'; En: 'Wrap in try/finally'),
    (De: '%s ohne try/finally mit %s: eine Ausnahme lässt die Sperre gesetzt';
     En: '%s without try/finally with %s: an exception leaves the lock set'),
    (De: 'Paarige Aufrufe ohne try/finally'; En: 'Paired calls without try/finally'),
    (De: 'bleibt der Zustand hängen'; En: 'the state stays stuck'),
    (De: '%s steht nicht im finally; bei einer Exception %s.'; En: '%s is not in finally; on an exception %s.'),
    (De: ' Gleiches gilt für %s.'; En: ' The same applies to %s.'),
    (De: 'bleibt das Grid eingefroren'; En: 'the grid stays frozen'),
    (De: 'bleibt die Anzeige gesperrt'; En: 'the display stays locked'),
    (De: 'bleibt das Suchhandle offen'; En: 'the search handle stays open'),
    (De: 'bleibt die Datei offen'; En: 'the file stays open'),
    (De: 'bleibt der Speicher belegt'; En: 'the memory stays allocated'),
    (De: 'bleibt der Mauszeiger stehen'; En: 'the mouse cursor stays as it is'));

{$SCOPEDENUMS OFF}

{ TThreadVclAccessRule }

function TThreadVclAccessRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('thread-vcl-access', TRuleSeverity.Warning,
    cTexts[TConcurrencyText.VclTitle].Text);
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
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if (AVisited.Kind = TSyntaxKind.Call) and (AVisited.ChildCount > 0) and
        (SameText(AVisited.Name, 'Synchronize') or SameText(AVisited.Name, 'Queue')) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      if (AVisited.Kind = TSyntaxKind.Identifier) and (InList(VclGlobals, AVisited.Name) or
        InList(VclDialogs, AVisited.Name)) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
end;

/// <summary>Meldet VCL-Zugriffe in den Anweisungen von ABody; einfache Anweisungen mit Korrektur (in
/// TThread.Queue einschließen), verschachtelte (if, for, try …) ohne.</summary>
procedure CheckVclBody(const AContext: TRuleContext; ABody: TSyntaxNode; const AReport: IRuleReport);
var
  mIndex: Integer;
  mStatement, mAccess: TSyntaxNode;
  mMessage: string;
begin
  for mIndex := 0 to ABody.ChildCount - 1 do
  begin
    mStatement := ABody[mIndex];
    mAccess := FindVclAccess(mStatement);
    if mAccess = nil then
    begin
      Continue;
    end;
    mMessage := cTexts[TConcurrencyText.VclAccess].Fmt([mAccess.Name]);
    if mStatement.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement] then
    begin
      AReport.Add(NodeRange(mAccess), mMessage, TRuleConfidence.High,
        [TRuleFix.Create(cTexts[TConcurrencyText.WrapQueue].Text, [TRuleEdit.Create(NodeRange(mStatement),
        'TThread.Queue(nil, procedure begin ' + SourceText(AContext.Text, mStatement) + ' end)')])]);
    end
    else if IsStatementList(mStatement) or (mStatement.ChildCount > 0) then
    begin
      AReport.Add(NodeRange(mAccess), mMessage, TRuleConfidence.High);
    end;
  end;
end;

/// <summary>Rümpfe von Execute der Thread-Klassen AThreads in ARoot; eingebettete Routinen darin zählen nicht.
/// </summary>
procedure CollectExecuteBodies(ARoot: TSyntaxNode; const AThreads: TArray<string>; ABodies: TList<TSyntaxNode>);
var
  mThreads: TArray<string>;
begin
  // const-Parameter dürfen anonyme Methoden nicht erfassen (E2555): lokale Kopie.
  mThreads := AThreads;
  // Iterativ (Bericht M1).
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mFound: TSyntaxNode;
    begin
      Result := ANode.Kind <> TSyntaxKind.RoutineDecl;
      if not Result and SameText(MethodPart(ANode.Name), 'Execute') and InList(mThreads, ClassPart(ANode.Name)) then
      begin
        mFound := ANode.FindChild(TSyntaxKind.Block);
        if mFound <> nil then
        begin
          ABodies.Add(mFound);
        end;
      end;
    end);
end;

/// <summary>Startet der Aufruf ACall (mit Argumenten) Code in einem anderen Thread: CreateAnonymousThread,
/// TTask.Run, TTask.Create, TTask.Future?</summary>
function StartsThreadCode(ACall: TSyntaxNode): Boolean;
var
  mTarget: TSyntaxNode;
begin
  Result := False;
  if (ACall.Kind <> TSyntaxKind.Call) or (ACall.ChildCount <= 1) then
  begin
    Exit;
  end;
  mTarget := ACall[0];
  if (mTarget.Kind = TSyntaxKind.MemberAccess) and (mTarget.ChildCount = 1) then
  begin
    Result := MatchText(VariableName(mTarget[0]) + '.' + mTarget.Name, ['TThread.CreateAnonymousThread',
      'TTask.Run', 'TTask.Create', 'TTask.Future']);
  end;
end;

/// <summary>Rümpfe der anonymen Methoden, die CreateAnonymousThread oder TTask.Run/Create/Future in ARoot
/// übergeben werden.</summary>
procedure CollectThreadArgumentBodies(ARoot: TSyntaxNode; ABodies: TList<TSyntaxNode>);
begin
  // Iterativ (Bericht M1).
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    var
      mArg: Integer;
      mFound: TSyntaxNode;
    begin
      Result := True;
      if not StartsThreadCode(ANode) then
      begin
        Exit;
      end;
      for mArg := 1 to ANode.ChildCount - 1 do
      begin
        mFound := nil;
        if ANode[mArg].Kind = TSyntaxKind.AnonymousMethod then
        begin
          mFound := ANode[mArg].FindChild(TSyntaxKind.Block);
        end;
        if mFound <> nil then
        begin
          ABodies.Add(mFound);
        end;
      end;
    end);
end;

procedure TThreadVclAccessRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mBodies: TList<TSyntaxNode>;
  mBody: TSyntaxNode;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  // Iterativ (Bericht M1): erst die Rümpfe sammeln, dann prüfen.
  mBodies := TList<TSyntaxNode>.Create;
  try
    CollectExecuteBodies(AContext.Tree.Root, SharedThreadClasses(AContext), mBodies);
    CollectThreadArgumentBodies(AContext.Tree.Root, mBodies);
    for mBody in mBodies do
    begin
      CheckVclBody(AContext, mBody, AReport);
    end;
  finally
    mBodies.Free;
  end;
end;

{ TLockWithoutFinallyRule }

function TLockWithoutFinallyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('lock-without-finally', TRuleSeverity.Warning,
    cTexts[TConcurrencyText.LockTitle].Text);
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
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    Pairs := TJSONObject(Value).GetValue('lockPairs');
    if not (Pairs is TJSONArray) then
    begin
      Exit;
    end;
    for Item in TJSONArray(Pairs) do
    begin
      if (Item is TJSONArray) and (TJSONArray(Item).Count = 2) and (TJSONArray(Item).Items[0] is TJSONString) and
        (TJSONArray(Item).Items[1] is TJSONString) then
      begin
        Pair.Lock := TJSONArray(Item).Items[0].Value;
        Pair.Release := TJSONArray(Item).Items[1].Value;
        Result := Result + [Pair];
      end;
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
  begin
    Result := NodeText(AText, ACall.Receiver);
  end
  else
  begin
    Result := '';
  end;
  // Nur bei TMonitor.Enter(X) und EnterCriticalSection(X) gehört das Argument zur Sperre; sonst ist es ein
  // Parameter der Freigabe (Guard.Leave(Clear, Keys), #1109).
  if (ACall.Call <> nil) and (ACall.Call.ChildCount > 1) and
    ((ACall.Receiver = nil) or SameText(ShortName(Result), 'TMonitor')) then
  begin
    Result := Result + '(' + NodeText(AText, ACall.Call[1]) + ')';
  end;
end;

/// <summary>Wie TryMethodCall für einen Aufruf in einem Ausdruck: if Guard.Leave(…) then (#1109).</summary>
function TryExpressionCall(ANode: TSyntaxNode; out ACall: TMethodCall): Boolean;
begin
  Result := False;
  ACall := Default(TMethodCall);
  if (ANode.Kind <> TSyntaxKind.Call) or (ANode.ChildCount = 0) or (ANode.Parent = nil) or
    (ANode.Parent.Kind = TSyntaxKind.CallStatement) then
  begin
    Exit;
  end;
  ACall.Call := ANode;
  ACall.Member := ANode[0];
  if (ACall.Member.Kind = TSyntaxKind.MemberAccess) and (ACall.Member.ChildCount > 0) then
  begin
    ACall.Receiver := ACall.Member[0];
  end
  else if ACall.Member.Kind <> TSyntaxKind.Identifier then
  begin
    Exit;
  end;
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
  begin
    Exit(False);
  end;
  Text := AText;
  Release := ARelease;
  Key := AKey;
  // Iterativ (Bericht M1).
  Result := Final.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if IsRelease(Text, ANode, Release, Key) then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

/// <summary>Ist die Sperre an AIndex in AList sicher freigegeben: direkt folgendes try … finally mit der Freigabe
/// ARelease (Schlüssel AKey), Sperre als Anweisung im try selbst oder Freigabe direkt danach (dazwischen kann nichts
/// werfen)?</summary>
function ReleasedSafely(const AText: string; AList: TSyntaxNode; AIndex: Integer;
  const ARelease, AKey: string): Boolean;
var
  mNext: TSyntaxNode;
begin
  Result := (AList.Kind = TSyntaxKind.TryStatement) and ReleasesIn(AText, AList, ARelease, AKey);
  if not Result and (AIndex < AList.ChildCount - 1) then
  begin
    mNext := AList[AIndex + 1];
    Result := ((mNext.Kind = TSyntaxKind.TryStatement) and ReleasesIn(AText, mNext, ARelease, AKey)) or
      IsRelease(AText, mNext, ARelease, AKey);
  end;
end;

/// <summary>Index der ersten Freigabe ARelease (Schlüssel AKey) nach AIndex in AList; -1 ohne.</summary>
function ReleaseIndexOf(const AText: string; AList: TSyntaxNode; AIndex: Integer;
  const ARelease, AKey: string): Integer;
var
  mLater: Integer;
begin
  Result := -1;
  for mLater := AIndex + 1 to AList.ChildCount - 1 do
  begin
    if (Result < 0) and IsRelease(AText, AList[mLater], ARelease, AKey) then
    begin
      Result := mLater;
    end;
  end;
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
    begin
      Exit;
    end;
    First := AList[ALockIndex + 1];
    Release := AList[AReleaseIndex];
    Indent := StringOfChar(' ', AList[ALockIndex].StartPos.Character);
    Middle := TrimRight(Copy(AContext.Text, First.StartOffset + 1, Release.StartOffset - First.StartOffset));
    Middle := StringReplace(Middle, #10, #10'  ', [rfReplaceAll]);
    NewText := 'try' + sLineBreak + Indent + '  ' + Middle + sLineBreak + Indent + 'finally' + sLineBreak +
      Indent + '  ' + SourceText(AContext.Text, Release) + ';' + sLineBreak + Indent + 'end';
    Result := [TRuleFix.Create(cTexts[TConcurrencyText.WrapTryFinally].Text, [TRuleEdit.Create(
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
        begin
          Names := Names + [ShortName(ANode.Name)];
        end;
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
      begin
        Exit(ShortName(ANode.Name));
      end;
      ANode := ANode.Parent;
    end;
  end;

var
  Routines: TArray<string>;

  // Enter(…) ohne Empfänger ruft eine Routine dieser Unit (lokale Routine, eigene Methode), keine Sperre; eine
  // gleichnamige Hülle (procedure TX.Enter; begin TMonitor.Enter(FLock); end) gibt die Sperre an den Aufrufer
  // weiter, der dort geprüft wird (#1109).
  function IsOwnRoutine(AList: TSyntaxNode; const ACall: TMethodCall): Boolean;
  begin
    Result := ((ACall.Receiver = nil) and MatchText(ACall.Method, Routines)) or
      SameText(EnclosingRoutine(AList), ACall.Method);
  end;

  // Paare zur Sperre ACall an AIndex: AReleased, wenn sicher freigegeben; ARelease die Freigabe ('' ohne Paar),
  // AReleaseIndex die erste spätere Freigabe (-1 ohne).
  function PairOf(AList: TSyntaxNode; AIndex: Integer; const ACall: TMethodCall; out ARelease: string;
    out AReleaseIndex: Integer): Boolean;
  var
    mPair: TLockPair;
    mKey: string;
    mLater: Integer;
  begin
    Result := False;
    ARelease := '';
    AReleaseIndex := -1;
    mKey := LockKey(AContext.Text, ACall);
    for mPair in Pairs do
    begin
      if not SameText(mPair.Lock, ACall.Method) then
      begin
        Continue;
      end;
      if ARelease = '' then
      begin
        ARelease := mPair.Release;
      end;
      Result := Result or ReleasedSafely(AContext.Text, AList, AIndex, mPair.Release, mKey);
      mLater := ReleaseIndexOf(AContext.Text, AList, AIndex, mPair.Release, mKey);
      if (AReleaseIndex < 0) and (mLater >= 0) then
      begin
        AReleaseIndex := mLater;
        ARelease := mPair.Release;
      end;
    end;
  end;

  procedure CheckList(AList: TSyntaxNode);
  var
    Index, ReleaseIndex: Integer;
    Call: TMethodCall;
    Release: string;
  begin
    for Index := 0 to AList.ChildCount - 1 do
    begin
      if not TryMethodCall(AList[Index], Call) then
      begin
        Continue;
      end;
      if IsOwnRoutine(AList, Call) or PairOf(AList, Index, Call, Release, ReleaseIndex) or (Release = '') then
      begin
        Continue;
      end;
      AReport.Add(NameRange(Call.Member),
        cTexts[TConcurrencyText.LockNoFinally].Fmt([Call.Method, Release]),
        TRuleConfidence.High, WrapFix(AList, Index, ReleaseIndex));
    end;
  end;

var
  List: TSyntaxNode;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Pairs := LockPairs(AContext.Options);
  Routines := UnitRoutines;
  for List in StatementLists(AContext.Tree.Root) do
  begin
    CheckList(List);
  end;
end;

{ TPairWithoutFinallyRule }

const
  // Open, Close, OpenArg, CloseArg; die Folge steht in BuiltinStateConsequences.
  BuiltinStatePairs: array[0..8, 0..3] of string = (
    ('DisableControls', 'EnableControls', '-1', '-1'),
    ('BeginUpdate', 'EndUpdate', '-1', '-1'),
    ('FindFirst', 'FindClose', '2', '0'),
    ('Reset', 'CloseFile', '0', '0'),
    ('Rewrite', 'CloseFile', '0', '0'),
    ('Append', 'CloseFile', '0', '0'),
    ('GetMem', 'FreeMem', '0', '0'),
    ('AllocMem', 'FreeMem', '-2', '0'),
    ('Screen.Cursor :=', 'Screen.Cursor :=', '-1', '-1'));
  BuiltinStateConsequences: array[0..8] of TConcurrencyText = (TConcurrencyText.GridFrozen,
    TConcurrencyText.DisplayLocked, TConcurrencyText.SearchHandleOpen, TConcurrencyText.FileOpen,
    TConcurrencyText.FileOpen, TConcurrencyText.FileOpen, TConcurrencyText.MemoryAllocated,
    TConcurrencyText.MemoryAllocated, TConcurrencyText.CursorStuck);
  AssignSuffix = ':=';

function TPairWithoutFinallyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('pair-without-finally', TRuleSeverity.Warning,
    cTexts[TConcurrencyText.PairTitle].Text);
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
    Pair.Consequence := cTexts[BuiltinStateConsequences[Index]].Text;
    Result := Result + [Pair];
  end;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  Value := TJSONObject.ParseJSONValue(AOptions);
  try
    if not (Value is TJSONObject) then
    begin
      Exit;
    end;
    List := TJSONObject(Value).GetValue('pairs');
    if not (List is TJSONArray) then
    begin
      Exit;
    end;
    for Item in TJSONArray(List) do
    begin
      if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>('open', Pair.Open) and
        TJSONObject(Item).TryGetValue<string>('close', Pair.Close) and (Trim(Pair.Open) <> '') and
        (Trim(Pair.Close) <> '') then
      begin
        Pair.Open := Trim(Pair.Open);
        Pair.Close := Trim(Pair.Close);
        Pair.OpenArg := -1;
        Pair.CloseArg := -1;
        if TJSONObject(Item).TryGetValue<Integer>('openArg', Number) then
        begin
          Pair.OpenArg := Number;
        end;
        if TJSONObject(Item).TryGetValue<Integer>('closeArg', Number) then
        begin
          Pair.CloseArg := Number;
        end;
        Pair.Consequence := cTexts[TConcurrencyText.StateStuck].Text;
        Result := Result + [Pair];
      end;
    end;
  finally
    Value.Free;
  end;
end;

type
  /// <summary>Öffnen eines Paars: Index des Paars, der Anweisung in der Liste (-1 außerhalb) und Schlüssel.
  /// </summary>
  TOpening = record
    Pair: Integer;
    Index: Integer;
    Key: string;
  end;

/// <summary>Ist ANode ein Aufruf von AName (AReceiver: Empfänger bei X.AName, sonst nil)?</summary>
function IsCallOf(ANode: TSyntaxNode; const AName: string; out AReceiver: TSyntaxNode): Boolean;
var
  mCallee: TSyntaxNode;
begin
  AReceiver := nil;
  Result := False;
  if ANode.Kind <> TSyntaxKind.Call then
  begin
    Exit;
  end;
  mCallee := ANode[0];
  Result := (mCallee.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and SameText(mCallee.Name, AName);
  if Result and (mCallee.Kind = TSyntaxKind.MemberAccess) and (mCallee.ChildCount > 0) then
  begin
    AReceiver := mCallee[0];
  end;
end;

/// <summary>Aufruf von AName in ANode (Anweisung, rechte Seite einer Zuweisung); nil sonst.</summary>
function FindCall(ANode: TSyntaxNode; const AName: string; out AReceiver: TSyntaxNode): TSyntaxNode;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ (Bericht M1), Vorordnung wie die frühere Rekursion.
  AReceiver := nil;
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while (Result = nil) and (mPending.Count > 0) do
    begin
      mNode := mPending.Pop;
      if IsCallOf(mNode, AName, AReceiver) then
      begin
        Result := mNode;
      end
      else if not (mNode.Kind in [TSyntaxKind.Block, TSyntaxKind.TryStatement, TSyntaxKind.AnonymousMethod,
        TSyntaxKind.RoutineDecl]) then
      begin
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Grenzen einer Gruppe überlappender Paare: erstes und letztes Schließen, letztes Öffnen und der Index
/// des Paars mit dem ersten Schließen (AInner).</summary>
procedure GroupBounds(const AGroup: TArray<TOpening>; const ACloses: TArray<Integer>; out AFirstClose, ALastClose,
  ALastOpen, AInner: Integer);
var
  mIndex: Integer;
begin
  AFirstClose := ACloses[0];
  ALastClose := ACloses[0];
  ALastOpen := AGroup[0].Index;
  AInner := 0;
  for mIndex := 0 to High(AGroup) do
  begin
    if ACloses[mIndex] < AFirstClose then
    begin
      AFirstClose := ACloses[mIndex];
      AInner := mIndex;
    end;
    if ACloses[mIndex] > ALastClose then
    begin
      ALastClose := ACloses[mIndex];
    end;
    if AGroup[mIndex].Index > ALastOpen then
    begin
      ALastOpen := AGroup[mIndex].Index;
    end;
  end;
end;

/// <summary>Sind alle Schließen-Indizes in ACloses verschieden?</summary>
function DistinctCloses(const ACloses: TArray<Integer>): Boolean;
var
  mIndex, mOther: Integer;
begin
  Result := True;
  for mIndex := 0 to High(ACloses) do
  begin
    for mOther := mIndex + 1 to High(ACloses) do
    begin
      Result := Result and (ACloses[mIndex] <> ACloses[mOther]);
    end;
  end;
end;

procedure TPairWithoutFinallyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
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
    begin
      Exit('*');
    end;
    if (AArg < 0) and (AReceiver <> nil) then
    begin
      Exit(NodeText(AContext.Text, AReceiver));
    end;
    if AArg < 0 then
    begin
      AArg := 0;
    end;
    if (ACall <> nil) and (ACall.ChildCount > AArg + 1) then
    begin
      Result := NodeText(AContext.Text, ACall[AArg + 1]);
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
      begin
        AKey := AssignTarget(Name);
      end;
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
        begin
          AKey := NodeText(AContext.Text, AStatement[0]);
        end;
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

  var
    Index: Integer;
    Final: TSyntaxNode;
  begin
    for Index := AFrom to AList.ChildCount - 1 do
    begin
      if AList[Index].Kind = TSyntaxKind.TryStatement then
      begin
        Final := AList[Index].FindChild(TSyntaxKind.FinallyBlock);
        if (Final <> nil) and Search(Final) then
        begin
          Exit(True);
        end;
      end;
    end;
    Result := False;
  end;

  function CloseIndex(AList: TSyntaxNode; AFrom, APair: Integer; const AKey: string): Integer;
  var
    Index: Integer;
    Key: string;
  begin
    for Index := AFrom to AList.ChildCount - 1 do
    begin
      if Matches(AList[Index], StatePairs[APair], False, Key) and (Key = AKey) then
      begin
        Exit(Index);
      end;
    end;
    Result := -1;
  end;

  function CloseName(APair: Integer): string;
  begin
    Result := StatePairs[APair].Close;
    if IsAssignPair(Result) then
    begin
      Result := Trim(Copy(Result, 1, Length(Result) - Length(AssignSuffix)));
    end;
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
    begin
      Exit;
    end;
    LineBreak := TTextLines.LineBreakOf(AContext.Text);
    First := AList[AFirst];
    Indent := StringOfChar(' ', First.StartPos.Character);
    Middle := TrimRight(Copy(AContext.Text, First.StartOffset + 1, AList[AFirstClose].StartOffset -
      First.StartOffset));
    Middle := StringReplace(Middle, #10, #10'  ', [rfReplaceAll]);
    Closes := '';
    for Index := AFirstClose to ALastClose do
    begin
      Closes := Closes + LineBreak + Indent + '  ' + Trim(SourceText(AContext.Text, AList[Index])) + ';';
    end;
    Result := [TRuleFix.Create(cTexts[TConcurrencyText.WrapTryFinally].Text, [TRuleEdit.Create(
      TTextRange.Create(First.StartPos, AList[ALastClose].EndPos), 'try' + LineBreak + Indent + '  ' + Middle +
      LineBreak + Indent + 'finally' + Closes + LineBreak + Indent + 'end')])];
  end;

  // Meldung für Paare, deren Bereiche sich überlappen; am ersten Schließen, die übrigen Paare nennt sie mit.
  // Schließen-Namen der Paare in AGroup außer dem an AInner, mit Komma getrennt.
  function OtherCloses(const AGroup: TArray<TOpening>; AInner: Integer): string;
  var
    mIndex: Integer;
  begin
    Result := '';
    for mIndex := 0 to High(AGroup) do
    begin
      if (mIndex <> AInner) and (Result <> '') then
      begin
        Result := Result + ', ';
      end;
      if mIndex <> AInner then
      begin
        Result := Result + CloseName(AGroup[mIndex].Pair);
      end;
    end;
  end;

  procedure ReportGroup(AList: TSyntaxNode; const AGroup: TArray<TOpening>; const ACloses: TArray<Integer>);
  var
    FirstClose, LastClose, LastOpen, Inner: Integer;
    Message, Others: string;
  begin
    GroupBounds(AGroup, ACloses, FirstClose, LastClose, LastOpen, Inner);
    Others := OtherCloses(AGroup, Inner);
    Message := cTexts[TConcurrencyText.NotInFinally].Fmt(
      [CloseName(AGroup[Inner].Pair), StatePairs[AGroup[Inner].Pair].Consequence]);
    if Others <> '' then
    begin
      Message := Message + cTexts[TConcurrencyText.SameFor].Fmt([Others]);
    end;
    // Korrektur nur, wenn alle Öffnungen vor dem ersten Schließen stehen und die Schließen-Anweisungen
    // verschieden sind und direkt aufeinander folgen.
    if (LastOpen < FirstClose) and (LastClose - FirstClose + 1 = Length(AGroup)) and DistinctCloses(ACloses) then
    begin
      AReport.Add(TTextRange.Create(AList[FirstClose].StartPos, AList[FirstClose].EndPos), Message,
        TRuleConfidence.High, WrapFix(AList, LastOpen + 1, FirstClose, LastClose));
    end
    else
    begin
      AReport.Add(TTextRange.Create(AList[FirstClose].StartPos, AList[FirstClose].EndPos), Message,
        TRuleConfidence.High);
    end;
  end;

  // AOutside: Öffnen außerhalb der Liste (if FindFirst(...) = 0 then), Index -1.
  // AOutside und die Öffnungen in AList, je Anweisung das erste passende Paar.
  function OpeningsOf(AList: TSyntaxNode; const AOutside: TArray<TOpening>): TArray<TOpening>;
  var
    mOpening: TOpening;
    mIndex, mPair: Integer;
    mKey: string;
  begin
    Result := AOutside;
    for mIndex := 0 to AList.ChildCount - 1 do
    begin
      mPair := 0;
      while mPair <= High(StatePairs) do
      begin
        if Matches(AList[mIndex], StatePairs[mPair], True, mKey) and (mKey <> '') then
        begin
          mOpening.Pair := mPair;
          mOpening.Index := mIndex;
          mOpening.Key := mKey;
          Result := Result + [mOpening];
          mPair := High(StatePairs);
        end;
        Inc(mPair);
      end;
    end;
  end;

  procedure CheckList(AList: TSyntaxNode; const AOutside: TArray<TOpening>);
  var
    Openings, Group: TArray<TOpening>;
    Opening: TOpening;
    Close, Reach: Integer;
    Closes: TArray<Integer>;
  begin
    Openings := OpeningsOf(AList, AOutside);
    // Offene Paare mit ungeschütztem Schließen in derselben Liste; überlappende Paare zusammen.
    Group := nil;
    Closes := nil;
    Reach := -1;
    for Opening in Openings do
    begin
      Close := CloseIndex(AList, Opening.Index + 1, Opening.Pair, Opening.Key);
      if (Close < 0) or (Close <= Opening.Index + 1) or
        ClosedInFinally(AList, Opening.Index + 1, Opening.Pair, Opening.Key) then
      begin
        Continue;
      end;
      if (Group <> nil) and (Opening.Index > Reach) then
      begin
        ReportGroup(AList, Group, Closes);
        Group := nil;
        Closes := nil;
      end;
      Group := Group + [Opening];
      Closes := Closes + [Close];
      if Close > Reach then
      begin
        Reach := Close;
      end;
    end;
    if Group <> nil then
    begin
      ReportGroup(AList, Group, Closes);
    end;
  end;

  // if FindFirst(...) = 0 then begin … FindClose(SR) end: das Öffnen steht in der Bedingung.
  function ConditionOpening(AIf: TSyntaxNode; out AOpening: TOpening): Boolean;
  var
    PairIndex: Integer;
    Found, Receiver: TSyntaxNode;
  begin
    Result := False;
    if (AIf.ChildCount < 2) or (AIf[1].Kind <> TSyntaxKind.Block) then
    begin
      Exit;
    end;
    for PairIndex := 0 to High(StatePairs) do
    begin
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
  end;

  // Then-Block eines if, in dessen Bedingung ein Paar öffnet (CheckList prüft ihn mit dieser Öffnung)?
  function IsConditionBlock(ANode: TSyntaxNode): Boolean;
  var
    mOpening: TOpening;
  begin
    Result := (ANode.Kind = TSyntaxKind.Block) and (ANode.Parent <> nil) and
      (ANode.Parent.Kind = TSyntaxKind.IfStatement) and (ANode.Parent[1] = ANode) and
      ConditionOpening(ANode.Parent, mOpening);
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
        begin
          CheckList(Node[1], [Opening]);
        end
        else if IsStatementList(Node) and not IsConditionBlock(Node) then
        begin
          CheckList(Node, nil);
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

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  StatePairs := Pairs(AContext.Options);
  Visit(AContext.Tree.Root);
end;

function ThreadClasses(ARoot: TSyntaxNode): TArray<string>;
begin
  Result := Atlas.Common.Rules.Builtin.Concurrency.Syntax.ThreadClasses(ARoot);
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Concurrency', cTexts);

end.
