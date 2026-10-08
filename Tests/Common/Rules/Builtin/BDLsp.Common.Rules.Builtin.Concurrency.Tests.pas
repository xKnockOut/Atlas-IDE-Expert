unit BDLsp.Common.Rules.Builtin.Concurrency.Tests;

// Tests für die Nebenläufigkeitsregeln (#148).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConcurrencyRulesTests = class
  public
    [Test]
    procedure LockWithoutFinallyReports;
    [Test]
    procedure LockFollowedByTryFinallyIsSilent;
    [Test]
    procedure LockInsideTryWithFinallyIsSilent;
    [Test]
    procedure MonitorNeedsSameObject;
    [Test]
    procedure ReleaseOfKnowsPairs;
    [Test]
    procedure ThreadUsedAfterStartReports;
    [Test]
    procedure ThreadWithoutFreeOnTerminateIsSilent;
    [Test]
    procedure ReassignedThreadIsSilent;
    [Test]
    procedure SynchronizeInDestructorReports;
    [Test]
    procedure SynchronizeElsewhereIsSilent;
    [Test]
    procedure ResumeReportsWithFix;
    [Test]
    procedure SuspendReportsAndResumeWithArgumentsIsSilent;
    [Test]
    procedure ThreadFreeWithoutWaitForReports;
    [Test]
    procedure ThreadFreeAfterWaitForIsSilent;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Builtin.Concurrency,
  BDLsp.Tests.RuleAssert;

function Routine(const ABody: string; const AHeader: string = 'procedure TA.Run;'): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10 + AHeader + #10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TConcurrencyRulesTests.LockWithoutFinallyReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TLockWithoutFinallyRule.Create,
    Routine('  FLock.Enter;'#10'  DoWork;'#10'  FLock.Leave;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(8, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(13, Findings[0].Range.EndPos.Character);
  Assert.Contains(Findings[0].Message, 'Leave');
end;

procedure TConcurrencyRulesTests.LockFollowedByTryFinallyIsSilent;
begin
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create,
    Routine('  FLock.BeginWrite;'#10'  try'#10'    DoWork;'#10'  finally'#10'    FLock.EndWrite;'#10'  end;'));
  // Freigabe eines anderen Objekts zählt nicht.
  TRuleAssert.Reports(TLockWithoutFinallyRule.Create,
    Routine('  FLock.Enter;'#10'  try'#10'    DoWork;'#10'  finally'#10'    FOther.Leave;'#10'  end;'));
end;

procedure TConcurrencyRulesTests.LockInsideTryWithFinallyIsSilent;
begin
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create,
    Routine('  try'#10'    FSection.Acquire;'#10'    DoWork;'#10'  finally'#10'    FSection.Release;'#10'  end;'));
end;

procedure TConcurrencyRulesTests.MonitorNeedsSameObject;
begin
  TRuleAssert.Silent(TLockWithoutFinallyRule.Create,
    Routine('  TMonitor.Enter(FList);'#10'  try'#10'    DoWork;'#10'  finally'#10'    TMonitor.Exit(FList);'#10'  end;'));
  TRuleAssert.Reports(TLockWithoutFinallyRule.Create,
    Routine('  TMonitor.Enter(FList);'#10'  try'#10'    DoWork;'#10'  finally'#10'    TMonitor.Exit(FOther);'#10'  end;'));
end;

procedure TConcurrencyRulesTests.ReleaseOfKnowsPairs;
begin
  Assert.AreEqual('Leave', TLockWithoutFinallyRule.ReleaseOf('enter'));
  Assert.AreEqual('UnlockList', TLockWithoutFinallyRule.ReleaseOf('LockList'));
  Assert.AreEqual('', TLockWithoutFinallyRule.ReleaseOf('Leave'));
end;

procedure TConcurrencyRulesTests.ThreadUsedAfterStartReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TThreadUsedAfterStartRule.Create,
    Routine('  T := TWorker.Create(True);'#10'  T.FreeOnTerminate := True;'#10'  T.Start;'#10 +
      '  Log(T.ThreadID);'#10'  T.WaitFor;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
end;

procedure TConcurrencyRulesTests.ThreadWithoutFreeOnTerminateIsSilent;
begin
  TRuleAssert.Silent(TThreadUsedAfterStartRule.Create,
    Routine('  T := TWorker.Create(True);'#10'  T.Start;'#10'  T.WaitFor;'#10'  T.Free;'));
end;

procedure TConcurrencyRulesTests.ReassignedThreadIsSilent;
begin
  TRuleAssert.Silent(TThreadUsedAfterStartRule.Create,
    Routine('  T.FreeOnTerminate := True;'#10'  T.Start;'#10'  T := TWorker.Create(True);'#10'  T.Start;'));
end;

procedure TConcurrencyRulesTests.SynchronizeInDestructorReports;
begin
  TRuleAssert.Reports(TSynchronizeInDestructorRule.Create,
    Routine('  TThread.Synchronize(nil, Notify);'#10'  inherited;', 'destructor TA.Destroy;'));
  TRuleAssert.Reports(TSynchronizeInDestructorRule.Create,
    Routine('  Synchronize(Notify);', 'destructor TWorker.Destroy;'));
end;

procedure TConcurrencyRulesTests.SynchronizeElsewhereIsSilent;
begin
  TRuleAssert.Silent(TSynchronizeInDestructorRule.Create, Routine('  Synchronize(Notify);', 'procedure TWorker.Execute;'));
end;

procedure TConcurrencyRulesTests.ResumeReportsWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDeprecatedSuspendResumeRule.Create, Routine('  FWorker.Resume;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Start', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(10, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(16, Findings[0].Fixes[0].Edits[0].Range.EndPos.Character);
end;

procedure TConcurrencyRulesTests.SuspendReportsAndResumeWithArgumentsIsSilent;
begin
  TRuleAssert.Reports(TDeprecatedSuspendResumeRule.Create, Routine('  FWorker.Suspend;'));
  TRuleAssert.Silent(TDeprecatedSuspendResumeRule.Create, Routine('  FPlayer.Resume(Position);'));
end;

procedure TConcurrencyRulesTests.ThreadFreeWithoutWaitForReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TThreadFreeWithoutWaitForRule.Create,
    Routine('  FWorkerThread.Free;'#10'  FreeAndNil(FPollThread);'#10'  FList.Free;'),
    '{ "rules": { "thread-free-without-waitfor": "hint" }, "minConfidence": "low" }');
  Assert.AreEqual(2, Integer(Length(Findings)));
end;

procedure TConcurrencyRulesTests.ThreadFreeAfterWaitForIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TThreadFreeWithoutWaitForRule.Create,
    Routine('  FThread.Terminate;'#10'  FThread.WaitFor;'#10'  FThread.Free;'),
    '{ "rules": { "thread-free-without-waitfor": "hint" }, "minConfidence": "low" }'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TConcurrencyRulesTests);

end.
