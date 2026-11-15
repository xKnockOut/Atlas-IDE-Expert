unit Atlas.Core.Debug.LaunchProcesses.Tests;

// Tests für die gestarteten Programme eines Startverbunds (#867, #1967): Zustand, Statusfeld, Prozess zum Halt,
// nächster Prozess, Wartebedingung mit Prüfer und Frist nach dem Lauf; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasLaunchProcessesTests = class
  public
    [Test]
    procedure StateFollowsAliveAndPaused;
    [Test]
    procedure StatusTextJoinsPrograms;
    [Test]
    procedure AnyRunningIgnoresEnded;
    [Test]
    procedure FindsDebuggedProcessOnly;
    [Test]
    procedure NextIndexCyclesAfterCurrent;
    [Test]
    procedure ProbeForPortAndWindow;
    [Test]
    procedure DoneAfterDelay;
  end;

implementation

uses
  Atlas.Core.Debug.LaunchGroups,
  Atlas.Core.Debug.LaunchProcesses;

function Started(const ACaption: string; APid: Cardinal; ADebug: Boolean): TAtlasLaunchStarted;
begin
  Result := Default(TAtlasLaunchStarted);
  Result.Caption := ACaption;
  Result.Pid := APid;
  Result.Debug := ADebug;
end;

function WaitItem(AWait: TAtlasLaunchWaitKind; AValue: Integer): TAtlasLaunchItem;
begin
  Result := Default(TAtlasLaunchItem);
  Result.Wait := AWait;
  Result.Value := AValue;
end;

{ TAtlasLaunchProcessesTests }

procedure TAtlasLaunchProcessesTests.StateFollowsAliveAndPaused;
begin
  Assert.AreEqual<TAtlasLaunchProcessState>(TAtlasLaunchProcessState.Running,
    TAtlasLaunchProcesses.StateOf(True, False));
  Assert.AreEqual<TAtlasLaunchProcessState>(TAtlasLaunchProcessState.Paused,
    TAtlasLaunchProcesses.StateOf(True, True));
  Assert.AreEqual<TAtlasLaunchProcessState>(TAtlasLaunchProcessState.Ended,
    TAtlasLaunchProcesses.StateOf(False, True));
end;

procedure TAtlasLaunchProcessesTests.StatusTextJoinsPrograms;
var
  mTexts: TAtlasLaunchStateTexts;
begin
  mTexts.Running := 'läuft';
  mTexts.Paused := 'angehalten';
  mTexts.Ended := 'beendet';
  Assert.AreEqual('Server läuft · Client angehalten · Dienst beendet', TAtlasLaunchProcesses.StatusText(
    [Started('Server', 1, False), Started('Client', 2, True), Started('Dienst', 3, False)],
    [TAtlasLaunchProcessState.Running, TAtlasLaunchProcessState.Paused, TAtlasLaunchProcessState.Ended], mTexts));
  Assert.AreEqual('', TAtlasLaunchProcesses.StatusText(nil, nil, mTexts));
end;

procedure TAtlasLaunchProcessesTests.AnyRunningIgnoresEnded;
begin
  Assert.IsFalse(TAtlasLaunchProcesses.AnyRunning(nil));
  Assert.IsFalse(TAtlasLaunchProcesses.AnyRunning([TAtlasLaunchProcessState.Ended]));
  Assert.IsTrue(TAtlasLaunchProcesses.AnyRunning([TAtlasLaunchProcessState.Ended,
    TAtlasLaunchProcessState.Paused]));
end;

procedure TAtlasLaunchProcessesTests.FindsDebuggedProcessOnly;
var
  mFound: TAtlasLaunchStarted;
begin
  Assert.IsTrue(TAtlasLaunchProcesses.FindDebugged([Started('Ohne', 7, False), Started('Mit', 7, True)], 7,
    mFound));
  Assert.AreEqual('Mit', mFound.Caption);
  Assert.IsFalse(TAtlasLaunchProcesses.FindDebugged([Started('Ohne', 7, False)], 7, mFound));
  Assert.AreEqual('', mFound.Caption);
end;

procedure TAtlasLaunchProcessesTests.NextIndexCyclesAfterCurrent;
begin
  Assert.AreEqual(1, TAtlasLaunchProcesses.NextIndex([10, 20, 30], 10));
  Assert.AreEqual(0, TAtlasLaunchProcesses.NextIndex([10, 20, 30], 30));
  // Kein aktueller bzw. fremder Prozess: der erste.
  Assert.AreEqual(0, TAtlasLaunchProcesses.NextIndex([10, 20], 0));
  Assert.AreEqual(0, TAtlasLaunchProcesses.NextIndex([10, 20], 99));
  Assert.AreEqual(-1, TAtlasLaunchProcesses.NextIndex(nil, 10));
end;

procedure TAtlasLaunchProcessesTests.ProbeForPortAndWindow;
var
  mPort: Integer;
begin
  Assert.IsTrue(TAtlasLaunchProcesses.NeedsProbe(WaitItem(TAtlasLaunchWaitKind.Port, 8080), mPort));
  Assert.AreEqual(8080, mPort);
  Assert.IsTrue(TAtlasLaunchProcesses.NeedsProbe(WaitItem(TAtlasLaunchWaitKind.Window, 5), mPort));
  Assert.AreEqual(0, mPort);
  Assert.IsFalse(TAtlasLaunchProcesses.NeedsProbe(WaitItem(TAtlasLaunchWaitKind.Seconds, 5), mPort));
  Assert.IsFalse(TAtlasLaunchProcesses.NeedsProbe(WaitItem(TAtlasLaunchWaitKind.None, 0), mPort));
end;

procedure TAtlasLaunchProcessesTests.DoneAfterDelay;
var
  mDoneAt: UInt64;
begin
  mDoneAt := 0;
  Assert.IsFalse(TAtlasLaunchProcesses.DoneLongEnough(mDoneAt, 1000, 3000));
  Assert.AreEqual<UInt64>(1000, mDoneAt);
  Assert.IsFalse(TAtlasLaunchProcesses.DoneLongEnough(mDoneAt, 3999, 3000));
  Assert.IsTrue(TAtlasLaunchProcesses.DoneLongEnough(mDoneAt, 4000, 3000));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLaunchProcessesTests);

end.
