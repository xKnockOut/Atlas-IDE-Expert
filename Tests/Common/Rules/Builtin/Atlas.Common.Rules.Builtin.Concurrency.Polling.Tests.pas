unit Atlas.Common.Rules.Builtin.Concurrency.Polling.Tests;

// Tests für sleep-polling-loop.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSleepPollingLoopRuleTests = class
  public
    [Test]
    procedure IssueExampleReports;
    [Test]
    procedure WorkInBodyIsSilent;
    [Test]
    procedure RepeatAndAdvice;
    [Test]
    procedure CounterAndTimeCheck;
    [Test]
    procedure LocalStateIsSilent;
    [Test]
    procedure NoDuplicateWithOtherRules;
    [Test]
    procedure OffInConfiguration;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Concurrency.MainThread,
  Atlas.Common.Rules.Builtin.Concurrency.Threads,
  Atlas.Common.Rules.Builtin.Concurrency.Polling,
  Atlas.Tests.RuleAssert;

function InboxUnit(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TAtlasBuildInbox = class'#10'  private'#10 +
    '    FSignalled: Boolean;'#10'  public'#10'    procedure WaitForSignal;'#10'  end;'#10'implementation'#10 +
    'procedure TAtlasBuildInbox.WaitForSignal;'#10 + ABody + 'end;'#10'end.';
end;

function InboxMethod(const ABody: string): string;
begin
  Result := InboxUnit('begin'#10 + ABody);
end;

procedure TSleepPollingLoopRuleTests.IssueExampleReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TSleepPollingLoopRule.Create, InboxMethod('  while not FSignalled do'#10 +
    '    Sleep(25);'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('sleep-polling-loop', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Die Schleife wartet mit Sleep auf FSignalled. Auf ein Ereignis warten (TEvent.WaitFor bzw. ' +
    'TLightweightEvent.WaitFor mit Zeitgrenze) statt abzufragen.', mFindings[0].Message);
  Assert.AreEqual(12, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(7, mFindings[0].Range.EndPos.Character);
end;

procedure TSleepPollingLoopRuleTests.WorkInBodyIsSilent;
begin
  // Der Rumpf arbeitet: keine reine Warteschleife.
  TRuleAssert.Silent(TSleepPollingLoopRule.Create, InboxMethod('  while not FSignalled do'#10'  begin'#10 +
    '    ProcessNext;'#10'    Sleep(25);'#10'  end;'#10));
  // Warten auf ein Ereignis statt Sleep.
  TRuleAssert.Silent(TSleepPollingLoopRule.Create, InboxMethod('  while not FSignalled do'#10 +
    '    FEvent.WaitFor(25);'#10));
  // Sleep in einer anonymen Methode gehört nicht zur Schleife der Methode.
  TRuleAssert.Silent(TSleepPollingLoopRule.Create, InboxMethod('  while not FSignalled do'#10 +
    '    Run(procedure begin Sleep(25); end);'#10));
end;

procedure TSleepPollingLoopRuleTests.RepeatAndAdvice;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TSleepPollingLoopRule.Create, InboxMethod('  repeat'#10'    Sleep(10);'#10 +
    '  until FWorker.Finished;'#10'  while FTask.Status = TTaskStatus.Running do'#10'    SleepEx(10, False);'#10));
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('Die Schleife wartet mit Sleep auf FWorker.Finished. Mit TThread.WaitFor auf das Ende des Threads ' +
    'warten statt abzufragen.', mFindings[0].Message);
  Assert.AreEqual(12, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(8, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual('Die Schleife wartet mit Sleep auf FTask.Status. Mit ITask.Wait auf den Task warten statt ' +
    'abzufragen.', mFindings[1].Message);
  // Globale Variable in einer freien Routine.
  TRuleAssert.Reports(TSleepPollingLoopRule.Create, 'unit U;'#10'interface'#10'implementation'#10'var'#10 +
    '  GReady: Boolean;'#10'procedure Warten;'#10'begin'#10'  while not GReady do'#10'    Sleep(10);'#10'end;'#10 +
    'end.', 1);
end;

procedure TSleepPollingLoopRuleTests.CounterAndTimeCheck;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Zähler, Zeitmessung und Abbruch bei Zeitüberschreitung bleiben eine Warteschleife.
  mFindings := TRuleAssert.Findings(TSleepPollingLoopRule.Create, InboxUnit('var'#10'  mWaited: Integer;'#10 +
    '  mStart: UInt64;'#10'begin'#10'  mWaited := 0;'#10'  mStart := GetTickCount64;'#10 +
    '  while not FSignalled and (mWaited < 5000) do'#10'  begin'#10'    Sleep(50);'#10'    Inc(mWaited, 50);'#10 +
    '    if GetTickCount64 - mStart > 4000 then'#10'      raise ETimeout.Create(''Zeit'');'#10'  end;'#10 +
    '  repeat'#10'    Sleep(10);'#10'    mWaited := mWaited + 10;'#10'    if mWaited > 100 then'#10'    begin'#10 +
    '      mWaited := 0;'#10'      Break;'#10'    end;'#10'  until FSignalled;'#10));
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual(17, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(24, mFindings[1].Range.StartPos.Line);
end;

procedure TSleepPollingLoopRuleTests.LocalStateIsSilent;
begin
  // Die Bedingung liest nur lokale Variablen, Konstanten und Zeitfunktionen: eine Pause, kein Abfragen.
  TRuleAssert.Silent(TSleepPollingLoopRule.Create, InboxUnit('var'#10'  mCount: Integer;'#10'  mStart: UInt64;'#10 +
    'begin'#10'  mCount := 0;'#10'  while mCount < 10 do'#10'  begin'#10'    Sleep(10);'#10'    Inc(mCount);'#10 +
    '  end;'#10'  mStart := GetTickCount64;'#10'  repeat'#10'    Sleep(10);'#10 +
    '  until GetTickCount64 - mStart > 100;'#10'  while True do'#10'    Sleep(10);'#10));
  // Sleep(0) im Spinlock, Wiederholen einer Aktion und eine Zeitgrenze aus einem Feld.
  TRuleAssert.Silent(TSleepPollingLoopRule.Create, InboxUnit('var'#10'  mStart: UInt64;'#10'begin'#10 +
    '  while AtomicCmpExchange(GLock, 1, 0) <> 0 do'#10'    Sleep(0);'#10'  while not TryReplace(FSource) do'#10 +
    '    Sleep(100);'#10'  mStart := GetTickCount64;'#10'  while GetTickCount64 - mStart < FDelayMs do'#10 +
    '    Sleep(5);'#10));
  // Neben der Zeitgrenze bleibt der abgefragte Zustand gemeldet.
  TRuleAssert.Reports(TSleepPollingLoopRule.Create, InboxUnit('var'#10'  mWatch: TStopwatch;'#10'begin'#10 +
    '  mWatch := TStopwatch.StartNew;'#10'  while not FSignalled and (mWatch.ElapsedMilliseconds < FTimeoutMs) do'#10 +
    '    Sleep(10);'#10), 1);
end;

procedure TSleepPollingLoopRuleTests.NoDuplicateWithOtherRules;
var
  mForm, mThread, mThreadWithTerminated: string;
  mFindings: TArray<TRuleFinding>;
begin
  // Formular: meldet blocking-call-in-main-thread.
  mForm := 'unit U;'#10'interface'#10'type'#10'  TfrmHaupt = class(TForm)'#10'  private'#10 +
    '    FReady: Boolean;'#10'  end;'#10'implementation'#10'procedure TfrmHaupt.Laden;'#10'begin'#10 +
    '  while not FReady do'#10'    Sleep(10);'#10'end;'#10'end.';
  TRuleAssert.Silent(TSleepPollingLoopRule.Create, mForm);
  Assert.IsTrue(Length(TRuleAssert.Findings(TBlockingCallInMainThreadRule.Create, mForm)) > 0);
  // Thread ohne Terminated in der Schleife: meldet thread-loop-without-terminated.
  mThread := 'unit U;'#10'interface'#10'type'#10'  TPoller = class(TThread)'#10'  private'#10 +
    '    FReady: Boolean;'#10'  protected'#10'    procedure Execute; override;'#10'  end;'#10'implementation'#10 +
    'procedure TPoller.Execute;'#10'begin'#10'  while not FReady do'#10'    Sleep(10);'#10'end;'#10'end.';
  TRuleAssert.Silent(TSleepPollingLoopRule.Create, mThread);
  TRuleAssert.Reports(TThreadLoopWithoutTerminatedRule.Create, mThread, 1);
  // Mit Terminated meldet nur sleep-polling-loop das Abfragen von FReady.
  mThreadWithTerminated := StringReplace(mThread, 'while not FReady do', 'while not Terminated and not FReady do',
    []);
  TRuleAssert.Silent(TThreadLoopWithoutTerminatedRule.Create, mThreadWithTerminated);
  mFindings := TRuleAssert.Findings(TSleepPollingLoopRule.Create, mThreadWithTerminated);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.StartsWith('Die Schleife wartet mit Sleep auf FReady.', mFindings[0].Message);
  // Nur Terminated: der Thread wartet auf sein Ende, das meldet keine der Regeln.
  TRuleAssert.Silent(TSleepPollingLoopRule.Create, StringReplace(mThread, 'while not FReady do',
    'while not Terminated do', []));
end;

procedure TSleepPollingLoopRuleTests.OffInConfiguration;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSleepPollingLoopRule.Create,
    InboxMethod('  while not FSignalled do'#10'    Sleep(25);'#10), '{"rules": {"sleep-polling-loop": "off"}}'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TSleepPollingLoopRuleTests);

end.
