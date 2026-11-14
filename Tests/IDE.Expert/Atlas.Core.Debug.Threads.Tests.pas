unit Atlas.Core.Debug.Threads.Tests;

// Tests zu den Wartepunkten der Threads (#587, #837): Routinen erkennen, tiefste Warte-Routine über dem ersten
// eigenen Rahmen, Hauptthread und Sprungziel.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.Threads;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugThreadsTests = class
  public
    [Test]
    procedure MatchesAtDotBoundary;
    [Test]
    procedure KnowsWaitRoutines;
    [Test]
    procedure FindsHighLevelWaitAboveOwnCode;
    [Test]
    procedure IgnoresWaitsBelowOwnCode;
    [Test]
    procedure FindsWaitWithoutOwnCode;
    [Test]
    procedure RunningThreadDoesNotWait;
    [Test]
    procedure MessageLoopIsIdle;
    [Test]
    procedure MainThreadStartsInProjectFile;
    [Test]
    procedure MainThreadFallsBackToFirst;
    [Test]
    procedure JumpFramePrefersOwnCode;
    [Test]
    procedure DefaultRoutinesNameKinds;
  end;

  /// <summary>Stapel für Tests; Rahmen „Kopf|Datei|Zeile|own“, oberster zuerst.</summary>
  TAtlasDebugTestStacks = record
    class function Stack(AThreadId: Cardinal; const AName: string;
      const AFrames: array of string): TAtlasDebugThreadStack; static;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  Atlas.Core.Debug.CallStack;

{ TAtlasDebugTestStacks }

class function TAtlasDebugTestStacks.Stack(AThreadId: Cardinal; const AName: string;
  const AFrames: array of string): TAtlasDebugThreadStack;
var
  mFrames: TAtlasDebugFrames;
  mIndex: Integer;
  mParts: TArray<string>;
begin
  SetLength(mFrames, Length(AFrames));
  for mIndex := 0 to High(AFrames) do
  begin
    mParts := AFrames[mIndex].Split(['|']);
    mFrames[mIndex] := TAtlasDebugFrame.Create(mParts[0], '', 0);
    if Length(mParts) > 2 then
    begin
      mFrames[mIndex].FileName := mParts[1];
      mFrames[mIndex].Line := StrToInt(mParts[2]);
    end;
    mFrames[mIndex].Own := (Length(mParts) > 3) and (mParts[3] = 'own');
  end;
  Result := TAtlasDebugThreadStack.Create(AThreadId, AName, mFrames);
end;

function Stack(AThreadId: Cardinal; const AFrames: array of string): TAtlasDebugThreadStack;
begin
  Result := TAtlasDebugTestStacks.Stack(AThreadId, '', AFrames);
end;

{ TAtlasDebugThreadsTests }

procedure TAtlasDebugThreadsTests.MatchesAtDotBoundary;
begin
  Assert.IsTrue(TAtlasDebugWaits.Matches('System.TMonitor.Enter', 'TMonitor.Enter'));
  Assert.IsTrue(TAtlasDebugWaits.Matches('kernel32.sleep', 'Sleep'));
  Assert.IsTrue(TAtlasDebugWaits.Matches('Sleep', 'Sleep'));
  Assert.IsFalse(TAtlasDebugWaits.Matches('Unit1.DeepSleep', 'Sleep'));
  Assert.IsFalse(TAtlasDebugWaits.Matches('Sleep', 'TThread.Sleep'));
  Assert.IsFalse(TAtlasDebugWaits.Matches('Unit1.Run', ''));
end;

procedure TAtlasDebugThreadsTests.KnowsWaitRoutines;
begin
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.ThreadWaitFor,
    TAtlasDebugWaits.KindOf('System.Classes.TThread.WaitFor'));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.Synchronize,
    TAtlasDebugWaits.KindOf('System.Classes.TThread.Synchronize'));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.MonitorEnter,
    TAtlasDebugWaits.KindOf('System.TMonitor.Enter'));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.MonitorWait,
    TAtlasDebugWaits.KindOf('System.TMonitor.Wait'));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.CriticalSection,
    TAtlasDebugWaits.KindOf('System.SyncObjs.TCriticalSection.Enter'));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.CriticalSection,
    TAtlasDebugWaits.KindOf('ntdll.RtlEnterCriticalSection'));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.EventWait,
    TAtlasDebugWaits.KindOf('System.SyncObjs.THandleObject.WaitFor'));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.Handle,
    TAtlasDebugWaits.KindOf('KERNELBASE.WaitForSingleObjectEx'));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.Sleep, TAtlasDebugWaits.KindOf('KERNELBASE.SleepEx'));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.Idle, TAtlasDebugWaits.KindOf('user32.GetMessageW'));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.None, TAtlasDebugWaits.KindOf('Unit1.TForm1.Button1Click'));
end;

procedure TAtlasDebugThreadsTests.FindsHighLevelWaitAboveOwnCode;
var
  mWait: TAtlasDebugWait;
begin
  mWait := TAtlasDebugWaits.Find(Stack(1, [
    ':77A1F0CC ntdll.NtWaitForSingleObject + 0xc',
    ':7714C3E2 KERNELBASE.WaitForSingleObjectEx + 0x92',
    'System.Classes.TThread.WaitFor',
    'System.Classes.TThread.Destroy',
    'Unit1.TForm1.FormDestroy(Self=$02A3F2C0)|C:\P\Unit1.pas|42|own',
    'Project1.Project1|C:\P\Project1.dpr|19|own']));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.ThreadWaitFor, mWait.Kind);
  Assert.AreEqual(2, mWait.Frame);
  Assert.AreEqual('System.Classes.TThread.WaitFor', mWait.Routine);
  Assert.IsTrue(mWait.Blocked);
end;

procedure TAtlasDebugThreadsTests.IgnoresWaitsBelowOwnCode;
var
  mWait: TAtlasDebugWait;
begin
  // Der Thread rechnet in eigenem Code; das WaitFor weiter unten gehört zu einem Aufrufer, der schon weiter ist.
  mWait := TAtlasDebugWaits.Find(Stack(1, [
    'Unit2.Compute|C:\P\Unit2.pas|10|own',
    'System.Classes.TThread.WaitFor']));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.None, mWait.Kind);
  Assert.AreEqual(-1, mWait.Frame);
  Assert.IsFalse(mWait.Blocked);
end;

procedure TAtlasDebugThreadsTests.FindsWaitWithoutOwnCode;
var
  mWait: TAtlasDebugWait;
begin
  mWait := TAtlasDebugWaits.Find(Stack(1, [
    ':77A1F0CC ntdll.NtWaitForSingleObject + 0xc',
    'System.TMonitor.Wait',
    'System.Threading.TThreadPool.TQueueWorkerThread.Execute',
    'System.Classes.ThreadProc']));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.MonitorWait, mWait.Kind);
  Assert.AreEqual(1, mWait.Frame);
end;

procedure TAtlasDebugThreadsTests.RunningThreadDoesNotWait;
begin
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.None, TAtlasDebugWaits.Find(Stack(1, [
    'Unit2.TWorker.Execute|C:\P\Unit2.pas|30|own',
    'System.Classes.ThreadProc'])).Kind);
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.None, TAtlasDebugWaits.Find(Stack(1, [])).Kind);
end;

procedure TAtlasDebugThreadsTests.MessageLoopIsIdle;
var
  mWait: TAtlasDebugWait;
begin
  mWait := TAtlasDebugWaits.Find(Stack(1, [
    ':75F1A2B0 win32u.NtUserGetMessage + 0xc',
    ':76E2C1D0 user32.GetMessageW + 0x2a',
    'Vcl.Forms.TApplication.ProcessMessage',
    'Vcl.Forms.TApplication.HandleMessage',
    'Vcl.Forms.TApplication.Run',
    'Project1.Project1|C:\P\Project1.dpr|19|own']));
  Assert.AreEqual<TAtlasDebugWaitKind>(TAtlasDebugWaitKind.Idle, mWait.Kind);
  Assert.IsFalse(mWait.Blocked);
end;

procedure TAtlasDebugThreadsTests.MainThreadStartsInProjectFile;
var
  mStacks: TAtlasDebugThreadStacks;
begin
  mStacks := [Stack(7, ['System.Classes.ThreadProc']),
    Stack(5, ['Vcl.Forms.TApplication.Run', 'Project1.Project1|C:\P\Project1.dpr|19|own'])];
  Assert.AreEqual(1, TAtlasDebugWaits.MainIndex(mStacks));
end;

procedure TAtlasDebugThreadsTests.MainThreadFallsBackToFirst;
var
  mStacks: TAtlasDebugThreadStacks;
begin
  mStacks := [Stack(7, ['System.Classes.ThreadProc']), Stack(5, ['System.Classes.ThreadProc'])];
  Assert.AreEqual(0, TAtlasDebugWaits.MainIndex(mStacks));
  Assert.AreEqual(-1, TAtlasDebugWaits.MainIndex(nil));
end;

procedure TAtlasDebugThreadsTests.JumpFramePrefersOwnCode;
var
  mStack: TAtlasDebugThreadStack;
begin
  mStack := Stack(1, ['System.Classes.TThread.WaitFor|System.Classes.pas|100',
    'Unit1.TForm1.FormDestroy|C:\P\Unit1.pas|42|own']);
  Assert.AreEqual(1, mStack.FirstOwn);
  Assert.AreEqual(1, mStack.JumpFrame);
  mStack := Stack(1, ['System.Classes.TThread.WaitFor|System.Classes.pas|100', 'System.Classes.ThreadProc']);
  Assert.AreEqual(-1, mStack.FirstOwn);
  Assert.AreEqual(0, mStack.JumpFrame);
end;

procedure TAtlasDebugThreadsTests.DefaultRoutinesNameKinds;
var
  mEntry: string;
  mKind: string;
begin
  Assert.IsTrue(Length(TAtlasDebugWaits.DefaultRoutines) > 0);
  for mEntry in TAtlasDebugWaits.DefaultRoutines do
  begin
    mKind := Copy(mEntry, 1, Pos('=', mEntry) - 1);
    Assert.IsTrue(GetEnumValue(TypeInfo(TAtlasDebugWaitKind), mKind) > 0, mEntry);
  end;
end;

end.
