unit Atlas.Core.Debug.Phases.Tests;

// Tests für die Phasen einer Debug-Sitzung (#517 und folgende): Prozess startet, hält, läuft weiter, endet,
// Thread wechselt; verzögert gemeldeter Halt, eigene Auswertungen, Filter, Zuhörer. Der Debugger der IDE ist
// durch TAtlasDebugTargetFake ersetzt.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.Phases,
  Atlas.Tests.DebugTargetFake;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugPhasesTests = class
  private
    FTarget: TAtlasDebugTargetFake;
    FTargetRef: IAtlasDebugTarget;
    FPhases: TAtlasDebugPhases;
    FLog: TAtlasDebugListenerLog;
    FLogRef: IAtlasDebugListener;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure StartedOnlyForFirstProcess;
    [Test]
    procedure EndedAfterLastProcess;
    [Test]
    procedure StopReportedOnTick;
    [Test]
    procedure StopKindFollowsState;
    [Test]
    procedure ResumedOnlyAfterStop;
    [Test]
    procedure StopDroppedWhenRunningBeforeTick;
    [Test]
    procedure NewerStopReportedOnce;
    [Test]
    procedure StopWithoutThreadDropped;
    [Test]
    procedure ThreadSwitchKeepsStop;
    [Test]
    procedure StopInOtherThreadCountsAgain;
    [Test]
    procedure InternalChangesIgnored;
    [Test]
    procedure FilterHandlesStop;
    [Test]
    procedure FilterDeclinesStop;
    [Test]
    procedure FailingListenerDoesNotStopOthers;
    [Test]
    procedure RemovedListenerNotCalled;
    [Test]
    procedure AttachTakesDebuggerState;
    [Test]
    procedure ResetForgetsListeners;
    [Test]
    procedure NewSessionRestartsStopCount;
  end;

implementation

uses
  System.SysUtils;

type
  /// <summary>Zuhörer, dessen DebugStopped scheitert.</summary>
  TFailingListener = class(TAtlasDebugListenerLog)
  public
    procedure DebugStopped(AStop: TAtlasDebugStop); override;
  end;

  /// <summary>Zuhörer, der beim Start einen anderen abmeldet.</summary>
  TRemovingListener = class(TAtlasDebugListenerLog)
  private
    FPhases: TAtlasDebugPhases;
    FOther: IAtlasDebugListener;
  public
    constructor Create(APhases: TAtlasDebugPhases; const AOther: IAtlasDebugListener);
    destructor Destroy; override;
    procedure DebugStarted; override;
  end;

{ TFailingListener }

procedure TFailingListener.DebugStopped(AStop: TAtlasDebugStop);
begin
  raise EConvertError.Create('Zuhörer scheitert');
end;

{ TRemovingListener }

constructor TRemovingListener.Create(APhases: TAtlasDebugPhases; const AOther: IAtlasDebugListener);
begin
  inherited Create;
  FPhases := APhases;
  FOther := AOther;
end;

destructor TRemovingListener.Destroy;
begin
  FOther := nil;
  inherited Destroy;
end;

procedure TRemovingListener.DebugStarted;
begin
  inherited DebugStarted;
  FPhases.RemoveListener(FOther);
end;

{ TAtlasDebugPhasesTests }

procedure TAtlasDebugPhasesTests.Setup;
begin
  FTarget := TAtlasDebugTargetFake.Create;
  FTargetRef := FTarget;
  FPhases := TAtlasDebugPhases.Create(FTargetRef);
  FTarget.Connect(FPhases);
  FLog := TAtlasDebugListenerLog.Create;
  FLogRef := FLog;
  FPhases.AddListener(FLogRef);
end;

procedure TAtlasDebugPhasesTests.TearDown;
begin
  FTarget.Connect(nil);
  FreeAndNil(FPhases);
  FLogRef := nil;
  FLog := nil;
  FTargetRef := nil;
  FTarget := nil;
end;

procedure TAtlasDebugPhasesTests.StartedOnlyForFirstProcess;
begin
  FTarget.Launch;
  FTarget.Launch;
  Assert.AreEqual('Started', FLog.Text);
  Assert.IsTrue(FPhases.Active);
end;

procedure TAtlasDebugPhasesTests.EndedAfterLastProcess;
begin
  FTarget.Launch;
  FTarget.Launch;
  FTarget.Terminate;
  Assert.AreEqual('Started', FLog.Text);
  Assert.IsTrue(FPhases.Active);
  FTarget.Terminate;
  Assert.AreEqual('Started,Ended', FLog.Text);
  Assert.IsFalse(FPhases.Active);
end;

procedure TAtlasDebugPhasesTests.StopReportedOnTick;
begin
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 7);
  // Im Notifier selbst wird nichts gemeldet, erst beim Tick danach.
  Assert.AreEqual('Started', FLog.Text);
  Assert.AreEqual(1, FTarget.TickRequests);
  Assert.AreEqual(1, FPhases.StopCount);
  Assert.IsTrue(FPhases.Stopped);
  FTarget.Tick;
  Assert.AreEqual('Started,Stopped:Paused', FLog.Text);
end;

procedure TAtlasDebugPhasesTests.StopKindFollowsState;
begin
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Exception, 7);
  FTarget.Tick;
  FTarget.Resume;
  FTarget.Stop(TAtlasDebugProcessState.Fault, 7);
  FTarget.Tick;
  Assert.AreEqual('Started,Stopped:Exception,Resumed,Stopped:Fault', FLog.Text);
  Assert.AreEqual(2, FPhases.StopCount);
end;

procedure TAtlasDebugPhasesTests.ResumedOnlyAfterStop;
begin
  FTarget.Launch;
  FTarget.Resume;
  Assert.AreEqual('Started', FLog.Text);
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 7);
  FTarget.Tick;
  FTarget.Resume;
  FTarget.Resume;
  Assert.AreEqual('Started,Stopped:Paused,Resumed', FLog.Text);
  Assert.IsFalse(FPhases.Stopped);
end;

procedure TAtlasDebugPhasesTests.StopDroppedWhenRunningBeforeTick;
begin
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 7);
  FTarget.Resume;
  FTarget.Tick;
  // Der Halt ist beim Tick vorbei: kein Halt, nur das Weiterlaufen.
  Assert.AreEqual('Started,Resumed', FLog.Text);
end;

procedure TAtlasDebugPhasesTests.NewerStopReportedOnce;
begin
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 7);
  FTarget.Stop(TAtlasDebugProcessState.Exception, 7);
  Assert.AreEqual(2, FTarget.TickRequests);
  FTarget.Tick;
  FTarget.Tick;
  Assert.AreEqual('Started,Stopped:Exception', FLog.Text);
  Assert.AreEqual(2, FPhases.StopCount);
end;

procedure TAtlasDebugPhasesTests.StopWithoutThreadDropped;
begin
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 0);
  FTarget.Tick;
  Assert.AreEqual('Started', FLog.Text);
  Assert.IsTrue(FPhases.Stopped);
end;

procedure TAtlasDebugPhasesTests.ThreadSwitchKeepsStop;
begin
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 7);
  // Anderer Thread im selben Halt (Fenster Threads der IDE): derselbe Halt, keine neue Nummer.
  FTarget.SelectThread(9);
  FTarget.Tick;
  Assert.AreEqual('Started,Stopped:Paused', FLog.Text);
  Assert.AreEqual(1, FPhases.StopCount);
end;

procedure TAtlasDebugPhasesTests.StopInOtherThreadCountsAgain;
begin
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 7);
  FTarget.Tick;
  FTarget.Resume;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 9);
  FTarget.Tick;
  Assert.AreEqual('Started,Stopped:Paused,Resumed,Stopped:Paused', FLog.Text);
  Assert.AreEqual(2, FPhases.StopCount);
end;

procedure TAtlasDebugPhasesTests.InternalChangesIgnored;
begin
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 7);
  FTarget.Tick;
  // Eine Auswertung lässt den Prozess kurz laufen und hält wieder an.
  FPhases.BeginInternal;
  FTarget.Resume;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 7);
  FPhases.EndInternal;
  FTarget.Tick;
  Assert.AreEqual('Started,Stopped:Paused', FLog.Text);
  Assert.AreEqual(1, FPhases.StopCount);
  Assert.AreEqual(1, FTarget.TickRequests);
  // Ein EndInternal zu viel schadet nicht.
  FPhases.EndInternal;
  FTarget.Resume;
  Assert.AreEqual('Started,Stopped:Paused,Resumed', FLog.Text);
end;

procedure TAtlasDebugPhasesTests.FilterHandlesStop;
var
  mTarget: TAtlasDebugTargetFake;
  mSeen: TAtlasDebugStop;
begin
  mTarget := FTarget;
  mSeen := TAtlasDebugStop.Fault;
  FPhases.SetStopFilter(
    function(AStop: TAtlasDebugStop): Boolean
    begin
      mSeen := AStop;
      mTarget.Resume;
      Result := True;
    end);
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 7);
  FTarget.Tick;
  // Erledigt: weder der Halt noch das Weiterlaufen erreichen die Zuhörer.
  Assert.AreEqual('Started', FLog.Text);
  Assert.AreEqual<TAtlasDebugStop>(TAtlasDebugStop.Paused, mSeen);
  Assert.IsFalse(FPhases.Stopped);
  FPhases.SetStopFilter(nil);
end;

procedure TAtlasDebugPhasesTests.FilterDeclinesStop;
begin
  FPhases.SetStopFilter(
    function(AStop: TAtlasDebugStop): Boolean
    begin
      Result := False;
    end);
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Exception, 7);
  FTarget.Tick;
  FTarget.Resume;
  Assert.AreEqual('Started,Stopped:Exception,Resumed', FLog.Text);
  FPhases.SetStopFilter(nil);
end;

procedure TAtlasDebugPhasesTests.FailingListenerDoesNotStopOthers;
var
  mFailing: IAtlasDebugListener;
  mLast: TAtlasDebugListenerLog;
  mLastRef: IAtlasDebugListener;
begin
  mFailing := TFailingListener.Create;
  mLast := TAtlasDebugListenerLog.Create;
  mLastRef := mLast;
  FPhases.RemoveListener(FLogRef);
  FPhases.AddListener(mFailing);
  FPhases.AddListener(mLastRef);
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 7);
  FTarget.Tick;
  Assert.AreEqual('Started,Stopped:Paused', mLast.Text);
  Assert.AreEqual(1, FTarget.Errors);
end;

procedure TAtlasDebugPhasesTests.RemovedListenerNotCalled;
var
  mRemoving: IAtlasDebugListener;
begin
  FPhases.RemoveListener(FLogRef);
  mRemoving := TRemovingListener.Create(FPhases, FLogRef);
  FPhases.AddListener(mRemoving);
  FPhases.AddListener(FLogRef);
  Assert.AreEqual(2, FPhases.ListenerCount);
  FTarget.Launch;
  Assert.AreEqual('', FLog.Text);
  Assert.AreEqual(1, FPhases.ListenerCount);
end;

procedure TAtlasDebugPhasesTests.AttachTakesDebuggerState;
begin
  // Notifier erst angemeldet, während schon ein Prozess angehalten ist.
  FTarget.Preset(1, TAtlasDebugProcessState.Stopped, 7);
  FPhases.Attach;
  Assert.IsTrue(FPhases.Active);
  Assert.IsTrue(FPhases.Stopped);
  FTarget.Resume;
  FTarget.Terminate;
  Assert.AreEqual('Resumed,Ended', FLog.Text);
end;

procedure TAtlasDebugPhasesTests.ResetForgetsListeners;
begin
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 7);
  FTarget.Tick;
  FPhases.Reset;
  Assert.AreEqual(0, FPhases.ListenerCount);
  Assert.IsFalse(FPhases.Active);
  Assert.IsFalse(FPhases.Stopped);
  Assert.AreEqual(1, FPhases.StopCount);
  FTarget.Resume;
  Assert.AreEqual('Started,Stopped:Paused', FLog.Text);
end;

procedure TAtlasDebugPhasesTests.NewSessionRestartsStopCount;
begin
  FTarget.Launch;
  FTarget.Stop(TAtlasDebugProcessState.Stopped, 7);
  FTarget.Tick;
  FTarget.Terminate;
  FTarget.Launch;
  Assert.AreEqual(0, FPhases.StopCount);
  Assert.IsFalse(FPhases.Stopped);
  Assert.AreEqual('Started,Stopped:Paused,Ended,Started', FLog.Text);
end;

end.
