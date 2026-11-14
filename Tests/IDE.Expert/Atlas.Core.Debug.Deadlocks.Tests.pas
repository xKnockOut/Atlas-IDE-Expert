unit Atlas.Core.Debug.Deadlocks.Tests;

// Tests zu „Was wartet worauf?“ (#587): Muster aus vorgegebenen Aufrufstapeln ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugDeadlocksTests = class
  public
    [Test]
    procedure DestructorWaitsForSynchronizingThread;
    [Test]
    procedure SynchronizeWhileMainHangsOnLock;
    [Test]
    procedure SynchronizeWhileMainIdleIsFine;
    [Test]
    procedure ThreadsWaitingAtSameLock;
    [Test]
    procedure DifferentLocksAreNotGrouped;
    [Test]
    procedure AllThreadsBlocked;
    [Test]
    procedure SleepingThreadIsNotBlocked;
    [Test]
    procedure UnreadableStacksAreSkipped;
  end;

implementation

uses
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.Threads.Tests,
  Atlas.Core.Debug.Deadlocks;

function Stack(AThreadId: Cardinal; const AFrames: array of string): TAtlasDebugThreadStack;
begin
  Result := TAtlasDebugTestStacks.Stack(AThreadId, '', AFrames);
end;

/// <summary>Hauptthread im Destruktor eines Threads, wartet in WaitFor.</summary>
function MainInDestructor: TAtlasDebugThreadStack;
begin
  Result := Stack(100, [
    ':77A1F0CC ntdll.NtWaitForSingleObject + 0xc',
    ':7714C3E2 KERNELBASE.WaitForSingleObjectEx + 0x92',
    'System.Classes.TThread.WaitFor',
    'System.Classes.TThread.Destroy',
    'Unit2.TWorker.Destroy|C:\P\Unit2.pas|50|own',
    'Unit1.TForm1.FormDestroy|C:\P\Unit1.pas|42|own',
    'Project1.Project1|C:\P\Project1.dpr|19|own']);
end;

function WorkerInSynchronize(AThreadId: Cardinal): TAtlasDebugThreadStack;
begin
  Result := Stack(AThreadId, [
    ':77A1F0CC ntdll.NtWaitForSingleObject + 0xc',
    'System.Classes.TThread.Synchronize',
    'System.Classes.TThread.Synchronize',
    'Unit2.TWorker.Execute|C:\P\Unit2.pas|30|own',
    'System.Classes.ThreadProc']);
end;

function MainOnLock: TAtlasDebugThreadStack;
begin
  Result := Stack(100, [
    ':77A1F0CC ntdll.NtWaitForSingleObject + 0xc',
    'System.TMonitor.Enter',
    'Unit1.TForm1.Timer1Timer|C:\P\Unit1.pas|60|own',
    'Project1.Project1|C:\P\Project1.dpr|19|own']);
end;

function MainIdle: TAtlasDebugThreadStack;
begin
  Result := Stack(100, [
    ':76E2C1D0 user32.GetMessageW + 0x2a',
    'Vcl.Forms.TApplication.Run',
    'Project1.Project1|C:\P\Project1.dpr|19|own']);
end;

function WorkerOnLock(AThreadId: Cardinal; const ARoutine: string): TAtlasDebugThreadStack;
begin
  Result := Stack(AThreadId, [
    'ntdll.RtlEnterCriticalSection',
    'System.SyncObjs.TCriticalSection.Enter',
    ARoutine + '|C:\P\Unit3.pas|12|own',
    'System.Classes.ThreadProc']);
end;

function WorkerSleeping(AThreadId: Cardinal): TAtlasDebugThreadStack;
begin
  Result := Stack(AThreadId, [
    'KERNELBASE.SleepEx',
    'Unit3.TPoller.Execute|C:\P\Unit3.pas|20|own']);
end;

{ TAtlasDebugDeadlocksTests }

procedure TAtlasDebugDeadlocksTests.DestructorWaitsForSynchronizingThread;
var
  mReport: TAtlasDebugWaitReport;
begin
  mReport := TAtlasDebugWaitReport.Analyze([WorkerInSynchronize(7), MainInDestructor]);
  Assert.AreEqual(1, mReport.Main);
  Assert.IsTrue(mReport.MainInThreadDestructor);
  Assert.AreEqual(2, Integer(Length(mReport.Patterns)));
  Assert.AreEqual<TAtlasDebugDeadlockKind>(TAtlasDebugDeadlockKind.MainWaitsForSynchronize, mReport.Patterns[0].Kind);
  Assert.AreEqual(2, Integer(Length(mReport.Patterns[0].Threads)));
  Assert.AreEqual(1, mReport.Patterns[0].Threads[0]);
  Assert.AreEqual(0, mReport.Patterns[0].Threads[1]);
  // Beide warten: auch „alle blockiert“.
  Assert.AreEqual<TAtlasDebugDeadlockKind>(TAtlasDebugDeadlockKind.AllBlocked, mReport.Patterns[1].Kind);
end;

procedure TAtlasDebugDeadlocksTests.SynchronizeWhileMainHangsOnLock;
var
  mReport: TAtlasDebugWaitReport;
begin
  mReport := TAtlasDebugWaitReport.Analyze([MainOnLock, WorkerInSynchronize(7), WorkerSleeping(8)]);
  Assert.AreEqual(1, Integer(Length(mReport.Patterns)));
  Assert.AreEqual<TAtlasDebugDeadlockKind>(TAtlasDebugDeadlockKind.SynchronizeBlocked, mReport.Patterns[0].Kind);
  Assert.IsFalse(mReport.MainInThreadDestructor);
end;

procedure TAtlasDebugDeadlocksTests.SynchronizeWhileMainIdleIsFine;
var
  mReport: TAtlasDebugWaitReport;
begin
  mReport := TAtlasDebugWaitReport.Analyze([MainIdle, WorkerInSynchronize(7)]);
  Assert.AreEqual(0, Integer(Length(mReport.Patterns)));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.Synchronize, mReport.Waits[1].Kind);
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.Idle, mReport.Waits[0].Kind);
end;

procedure TAtlasDebugDeadlocksTests.ThreadsWaitingAtSameLock;
var
  mReport: TAtlasDebugWaitReport;
begin
  mReport := TAtlasDebugWaitReport.Analyze([MainIdle, WorkerOnLock(7, 'Unit3.TCache.Add'),
    WorkerSleeping(8), WorkerOnLock(9, 'Unit3.TCache.Add')]);
  Assert.AreEqual(1, Integer(Length(mReport.Patterns)));
  Assert.AreEqual<TAtlasDebugDeadlockKind>(TAtlasDebugDeadlockKind.SameLock, mReport.Patterns[0].Kind);
  Assert.AreEqual('Unit3.TCache.Add', mReport.Patterns[0].Place);
  Assert.AreEqual(2, Integer(Length(mReport.Patterns[0].Threads)));
  Assert.AreEqual(1, mReport.Patterns[0].Threads[0]);
  Assert.AreEqual(3, mReport.Patterns[0].Threads[1]);
end;

procedure TAtlasDebugDeadlocksTests.DifferentLocksAreNotGrouped;
var
  mReport: TAtlasDebugWaitReport;
begin
  mReport := TAtlasDebugWaitReport.Analyze([MainIdle, WorkerOnLock(7, 'Unit3.TCache.Add'),
    WorkerOnLock(9, 'Unit3.TCache.Remove')]);
  Assert.AreEqual(0, Integer(Length(mReport.Patterns)));
end;

procedure TAtlasDebugDeadlocksTests.AllThreadsBlocked;
var
  mReport: TAtlasDebugWaitReport;
begin
  mReport := TAtlasDebugWaitReport.Analyze([MainOnLock, WorkerOnLock(7, 'Unit3.TCache.Add')]);
  Assert.AreEqual(1, Integer(Length(mReport.Patterns)));
  Assert.AreEqual<TAtlasDebugDeadlockKind>(TAtlasDebugDeadlockKind.AllBlocked, mReport.Patterns[0].Kind);
  Assert.AreEqual(2, Integer(Length(mReport.Patterns[0].Threads)));
end;

procedure TAtlasDebugDeadlocksTests.SleepingThreadIsNotBlocked;
var
  mReport: TAtlasDebugWaitReport;
begin
  mReport := TAtlasDebugWaitReport.Analyze([MainOnLock, WorkerSleeping(8)]);
  Assert.AreEqual(0, Integer(Length(mReport.Patterns)));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.Sleep, mReport.Waits[1].Kind);
end;

procedure TAtlasDebugDeadlocksTests.UnreadableStacksAreSkipped;
var
  mUnreadable: TAtlasDebugThreadStack;
  mReport: TAtlasDebugWaitReport;
begin
  mUnreadable := Stack(9, []);
  mUnreadable.Readable := False;
  mReport := TAtlasDebugWaitReport.Analyze([MainOnLock, WorkerOnLock(7, 'Unit3.TCache.Add'), mUnreadable]);
  Assert.AreEqual(1, Integer(Length(mReport.Patterns)));
  Assert.AreEqual<TAtlasDebugDeadlockKind>(TAtlasDebugDeadlockKind.AllBlocked, mReport.Patterns[0].Kind);
end;

end.
