unit Atlas.Common.Rules.Builtin.Concurrency.Polling;

// Prüfregel sleep-polling-loop (Teil von Atlas.Common.Rules.Builtin.Concurrency, dort registriert): eine while- oder
// repeat-Schleife, deren Rumpf nur mit Sleep wartet (optional mit Zähler oder Zeitprüfung) und deren Bedingung einen
// Zustand außerhalb der Routine abfragt (Feld, Eigenschaft, globale Variable, Funktion). Warten auf ein Signal
// (TEvent.WaitFor, TThread.WaitFor, ITask.Wait) reagiert sofort, kostet keine Rechenzeit und hängt nicht still.
// Schleifen, die thread-loop-without-terminated (Thread-Klassen ohne Terminated in der Schleife) oder
// blocking-call-in-main-thread (Formulare, Frames, Ereignis-Handler) schon meldet, bleiben still.

interface

uses
  Atlas.Common.Rules.Contract;

type
  TSleepPollingLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Inheritance.Ancestry,
  Atlas.Common.Rules.Builtin.Concurrency.Syntax,
  Atlas.Common.Rules.Builtin.Concurrency.MainThread,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen.</summary>
  TPollingText = (Title, Polls, UseEvent, UseThreadWait, UseTaskWait);

const
  cTexts: array[TPollingText] of TAtlasText = (
    (De: 'Warteschleife mit Sleep statt Warten auf ein Ereignis'; En: 'Waiting loop with Sleep instead of an event'),
    (De: 'Die Schleife wartet mit Sleep auf %s. %s statt abzufragen.';
     En: 'The loop waits with Sleep for %s. %s instead of polling.'),
    (De: 'Auf ein Ereignis warten (TEvent.WaitFor bzw. TLightweightEvent.WaitFor mit Zeitgrenze)';
     En: 'Wait for an event (TEvent.WaitFor or TLightweightEvent.WaitFor with a timeout)'),
    (De: 'Mit TThread.WaitFor auf das Ende des Threads warten'; En: 'Wait for the end of the thread with TThread.WaitFor'),
    (De: 'Mit ITask.Wait auf den Task warten'; En: 'Wait for the task with ITask.Wait'));

{$SCOPEDENUMS OFF}

const
  // Wartende Aufrufe im Rumpf.
  cSleepCalls: array[0..1] of string = ('Sleep', 'SleepEx');
  // Namen in der Bedingung, die keinen fremden Zustand lesen: Konstanten und Zeitfunktionen. Terminated zählt nicht als
  // abgefragter Zustand: Die Schleife eines Threads muss es ohnehin prüfen.
  cNeutralNames: array[0..16] of string = ('True', 'False', 'nil', 'not', 'INFINITE', 'GetTickCount',
    'GetTickCount64', 'Now', 'Time', 'Date', 'MilliSecondsBetween', 'SecondsBetween', 'TThread', 'TStopwatch',
    'TimeGetTime', 'Terminated', 'CheckTerminated');
  // Zeitmessung in der Bedingung: Ein Vergleich damit ist die Zeitgrenze der Schleife, kein abgefragter Zustand.
  cTimeNames: array[0..8] of string = ('GetTickCount', 'GetTickCount64', 'Now', 'MilliSecondsBetween',
    'SecondsBetween', 'TimeGetTime', 'ElapsedMilliseconds', 'ElapsedTicks', 'Elapsed');
  // Vergleiche in der Bedingung.
  cComparisons: array[0..5] of string = ('<', '>', '<=', '>=', '=', '<>');
  // Zähler und Zeitprüfung im Rumpf.
  cCounterCalls: array[0..1] of string = ('Inc', 'Dec');
  // Abbruch im Rumpf einer Zeitprüfung.
  cLeaveCalls: array[0..1] of string = ('Exit', 'Break');

type
  /// <summary>Ein Lauf von TSleepPollingLoopRule über eine Unit.</summary>
  TPollingScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FAncestry: TAncestry;
    FThreads: TArray<string>;
    FLocals: TArray<string>;
    function CalleeName(AStatement: TSyntaxNode; out AArguments: TSyntaxNode): string;
    function IsLocal(ANode: TSyntaxNode): Boolean;
    function IsLeave(AStatement: TSyntaxNode): Boolean;
    function IsWaitStep(AStatement: TSyntaxNode; var ASleeps: Integer): Boolean;
    function PolledState(ACondition: TSyntaxNode): string;
    function Advice(const AState: string): string;
    procedure CheckLoop(ALoop: TSyntaxNode);
    procedure CollectLocals(ARoutine: TSyntaxNode);
    function OuterMethod(ARoutine: TSyntaxNode): TSyntaxNode;
    function Skipped(ARoutine: TSyntaxNode): Boolean;
    procedure CheckRoutine(ARoutine: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

// Nennt ANode eine Zeitmessung (GetTickCount64, mUhr.ElapsedMilliseconds …)?
function MentionsTime(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Search(
    function(AChild: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (AChild.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and MatchText(AChild.Name, cTimeNames) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
end;

function DeclaredNames(ANode: TSyntaxNode): TArray<string>;
var
  mName: string;
begin
  Result := nil;
  for mName in SplitString(ANode.Name, ',') do
  begin
    if Trim(mName) <> '' then
    begin
      Result := Result + [Trim(mName)];
    end;
  end;
end;

{ TPollingScan }

constructor TPollingScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FAncestry := TAncestry.Create(FContext.Index, TRuleDerived.UnitIndex(TRuleDerived.Open(FContext), FContext));
end;

destructor TPollingScan.Destroy;
begin
  FAncestry.Free;
  FThreads := nil;
  FLocals := nil;
  inherited;
end;

// Name der aufgerufenen Routine einer Anweisung (M, M(…), X.M(…)); AArguments: der Aufruf mit Argumenten oder nil.
function TPollingScan.CalleeName(AStatement: TSyntaxNode; out AArguments: TSyntaxNode): string;
var
  mTarget: TSyntaxNode;
begin
  Result := '';
  AArguments := nil;
  if (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount = 0) then
  begin
    Exit;
  end;
  mTarget := AStatement[0];
  if (mTarget.Kind = TSyntaxKind.Call) and (mTarget.ChildCount > 0) then
  begin
    AArguments := mTarget;
    mTarget := mTarget[0];
  end;
  if mTarget.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess] then
  begin
    Result := mTarget.Name;
  end;
end;

function TPollingScan.IsLocal(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Identifier) and InList(FLocals, ANode.Name);
end;

// Exit, Break oder raise (auch in begin … end): der Abbruch einer Zeitprüfung.
function TPollingScan.IsLeave(AStatement: TSyntaxNode): Boolean;
var
  mArguments: TSyntaxNode;
  mIndex: Integer;
begin
  case AStatement.Kind of
    TSyntaxKind.RaiseStatement, TSyntaxKind.EmptyStatement:
      Result := True;
    TSyntaxKind.Block:
      begin
        Result := True;
        for mIndex := 0 to AStatement.ChildCount - 1 do
        begin
          Result := Result and (IsLeave(AStatement[mIndex]) or ((AStatement[mIndex].Kind = TSyntaxKind.AssignStatement) and
            IsLocal(AStatement[mIndex][0])));
        end;
      end;
  else
    Result := MatchText(CalleeName(AStatement, mArguments), cLeaveCalls);
  end;
end;

// Gehört AStatement zu einer reinen Warteschleife: Sleep, Zähler (Inc/Dec einer lokalen Variablen), Zuweisung an eine
// lokale Variable (Zeitmessung) oder eine Zeitprüfung "if … then Exit/Break/raise"?
function TPollingScan.IsWaitStep(AStatement: TSyntaxNode; var ASleeps: Integer): Boolean;
var
  mName: string;
  mArguments: TSyntaxNode;
  mIndex: Integer;
begin
  case AStatement.Kind of
    TSyntaxKind.EmptyStatement:
      Result := True;
    TSyntaxKind.Block:
      begin
        Result := True;
        for mIndex := 0 to AStatement.ChildCount - 1 do
        begin
          Result := Result and IsWaitStep(AStatement[mIndex], ASleeps);
        end;
      end;
    TSyntaxKind.AssignStatement:
      Result := (AStatement.ChildCount = 2) and IsLocal(AStatement[0]);
    TSyntaxKind.IfStatement:
      begin
        Result := AStatement.ChildCount >= 2;
        for mIndex := 1 to AStatement.ChildCount - 1 do
        begin
          Result := Result and IsLeave(AStatement[mIndex]);
        end;
      end;
    TSyntaxKind.CallStatement:
      begin
        mName := CalleeName(AStatement, mArguments);
        if MatchText(mName, cSleepCalls) then
        begin
          // Sleep(0) gibt nur die Zeitscheibe ab (Spinlock), es wartet nicht.
          Inc(ASleeps);
          Result := not ((mArguments <> nil) and (mArguments.ChildCount > 1) and
            (mArguments[1].Kind = TSyntaxKind.Literal) and (mArguments[1].Name = '0'));
        end
        else
        begin
          Result := MatchText(mName, cCounterCalls) and (mArguments <> nil) and (mArguments.ChildCount > 1) and
            IsLocal(mArguments[1]);
        end;
      end;
  else
    Result := False;
  end;
end;

// Der abgefragte fremde Zustand in der Bedingung (Feld, Eigenschaft, globale Variable, Funktion); '' wenn sie nur
// lokale Variablen, Konstanten und Zeitfunktionen liest.
function TPollingScan.PolledState(ACondition: TSyntaxNode): string;
var
  mFound: string;
begin
  mFound := '';
  ACondition.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      case ANode.Kind of
        // Ein Aufruf mit Argumenten tut etwas (TryReplace(…), AtomicCmpExchange(…)): ein Wiederholen, kein Abfragen.
        // Ein Vergleich mit einer Zeitmessung ist die Zeitgrenze.
        TSyntaxKind.Call:
          if ANode.ChildCount > 1 then
          begin
            Result := TSyntaxSearchStep.Skip;
          end;
        TSyntaxKind.BinaryExpr:
          if MatchText(ANode.Name, cComparisons) and MentionsTime(ANode) then
          begin
            Result := TSyntaxSearchStep.Skip;
          end;
        TSyntaxKind.MemberAccess:
          begin
            // X.Eigenschaft bzw. X.Methode: ein Zustand des Objekts, außer an lokalen Records (TStopwatch) und
            // Zeitfunktionen von TThread.
            if not ((ANode.ChildCount > 0) and (IsLocal(ANode[0]) or MatchText(ANode[0].Name, cNeutralNames))) then
            begin
              mFound := SourceText(FContext.Text, ANode);
              Result := TSyntaxSearchStep.Found;
            end
            else
            begin
              Result := TSyntaxSearchStep.Skip;
            end;
          end;
        TSyntaxKind.Identifier:
          if not IsLocal(ANode) and not MatchText(ANode.Name, cNeutralNames) then
          begin
            mFound := ANode.Name;
            Result := TSyntaxSearchStep.Found;
          end;
      end;
    end);
  Result := mFound;
end;

function TPollingScan.Advice(const AState: string): string;
begin
  if EndsText('Finished', AState) then
  begin
    Result := cTexts[TPollingText.UseThreadWait].Text;
  end
  else if EndsText('Status', AState) then
  begin
    Result := cTexts[TPollingText.UseTaskWait].Text;
  end
  else
  begin
    Result := cTexts[TPollingText.UseEvent].Text;
  end;
end;

procedure TPollingScan.CheckLoop(ALoop: TSyntaxNode);
var
  mCondition: TSyntaxNode;
  mIndex, mFirst, mLast, mSleeps: Integer;
  mPure: Boolean;
  mState, mKeyword: string;
begin
  if ALoop.Kind = TSyntaxKind.WhileStatement then
  begin
    mCondition := ALoop[0];
    mFirst := 1;
    mLast := ALoop.ChildCount - 1;
    mKeyword := 'while';
  end
  else
  begin
    mCondition := ALoop[ALoop.ChildCount - 1];
    mFirst := 0;
    mLast := ALoop.ChildCount - 2;
    mKeyword := 'repeat';
  end;
  mSleeps := 0;
  mPure := True;
  for mIndex := mFirst to mLast do
  begin
    mPure := mPure and IsWaitStep(ALoop[mIndex], mSleeps);
  end;
  if not mPure or (mSleeps = 0) then
  begin
    Exit;
  end;
  mState := PolledState(mCondition);
  if mState = '' then
  begin
    Exit;
  end;
  FReport.Add(TTextRange.Create(ALoop.StartPos, TTextPosition.Create(ALoop.StartPos.Line,
    ALoop.StartPos.Character + Length(mKeyword))), cTexts[TPollingText.Polls].Fmt([mState, Advice(mState)]),
    TRuleConfidence.Medium);
end;

// Lokale Variablen und Parameter der Routine samt der umgebenden Routinen (eingebettete Routinen sehen sie).
procedure TPollingScan.CollectLocals(ARoutine: TSyntaxNode);
var
  mRoutine: TSyntaxNode;
begin
  FLocals := nil;
  mRoutine := ARoutine;
  while mRoutine <> nil do
  begin
    if mRoutine.Kind = TSyntaxKind.RoutineDecl then
    begin
      mRoutine.Search(
        function(ANode: TSyntaxNode): TSyntaxSearchStep
        begin
          if (ANode <> mRoutine) and (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
          begin
            Exit(TSyntaxSearchStep.Skip);
          end;
          if ANode.Kind in [TSyntaxKind.VarDecl, TSyntaxKind.InlineVar, TSyntaxKind.Parameter, TSyntaxKind.ConstDecl]
          then
          begin
            FLocals := FLocals + DeclaredNames(ANode);
          end;
          Result := TSyntaxSearchStep.Descend;
        end);
    end;
    mRoutine := mRoutine.Parent;
  end;
end;

// Die Methode, zu der ARoutine gehört (eingebettete Routinen gehören zur äußeren); nil bei freien Routinen.
function TPollingScan.OuterMethod(ARoutine: TSyntaxNode): TSyntaxNode;
begin
  Result := ARoutine;
  while (Result <> nil) and ((Result.Kind <> TSyntaxKind.RoutineDecl) or (Pos('.', Result.Name) = 0)) do
  begin
    Result := Result.Parent;
  end;
end;

// Meldet schon eine andere Regel die Schleifen der Routine? Methoden von Thread-Klassen gehören zu
// thread-loop-without-terminated, Formulare, Frames und Ereignis-Handler zu blocking-call-in-main-thread.
function TPollingScan.Skipped(ARoutine: TSyntaxNode): Boolean;
var
  mMethod: TSyntaxNode;
  mOwner: string;
begin
  mMethod := OuterMethod(ARoutine);
  if mMethod = nil then
  begin
    Exit(False);
  end;
  mOwner := ClassPart(mMethod.Name);
  Result := InList(FThreads, mOwner) or FAncestry.DescendsFrom(mOwner, 'TThread') or
    RunsInMainThread(FAncestry, FThreads, mMethod);
end;

procedure TPollingScan.CheckRoutine(ARoutine: TSyntaxNode);
var
  mThreadMethod: Boolean;
begin
  mThreadMethod := Skipped(ARoutine);
  CollectLocals(ARoutine);
  ARoutine.FindChild(TSyntaxKind.Block).Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      // In Thread-Klassen nur Schleifen, die Terminated prüfen (die übrigen meldet thread-loop-without-terminated);
      // im Hauptthread keine.
      if (ANode.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]) and (ANode.ChildCount >= 2) and
        (not mThreadMethod or (FAncestry.DescendsFrom(ClassPart(OuterMethod(ARoutine).Name), 'TThread') and
        (Mentions(ANode, 'Terminated') or Mentions(ANode, 'CheckTerminated')))) then
      begin
        CheckLoop(ANode);
      end;
      Result := TSyntaxSearchStep.Descend;
    end);
end;

procedure TPollingScan.Run;
var
  mRoutine: TSyntaxNode;
begin
  FThreads := SharedThreadClasses(FContext);
  for mRoutine in TRuleDerived.Routines(TRuleDerived.Open(FContext), FContext) do
  begin
    CheckRoutine(mRoutine);
  end;
end;

{ TSleepPollingLoopRule }

function TSleepPollingLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('sleep-polling-loop', TRuleSeverity.Hint, cTexts[TPollingText.Title].Text);
end;

procedure TSleepPollingLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TPollingScan;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Sleep') then
  begin
    Exit;
  end;
  mScan := TPollingScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Concurrency.Polling', cTexts);

end.
