unit Atlas.Common.Lsp.ServerActivity.Tests;

// Tests für die Aktivität des Servers (#1901): laufende Anfragen mit Dauer, Fehler, Zeitüberschreitungen,
// Fortschritt und Zustand, ausführlicher Status über SetDetails und der Beobachter am Verteiler.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.ServerActivity;

type
  [TestFixture]
  TServerActivityTests = class
  private
    FActivity: TServerActivity;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DescribesProcess;
    [Test]
    procedure TracksLongestRunningRequest;
    [Test]
    procedure CountsErrorsAndTimeouts;
    [Test]
    procedure ProgressMeansWorking;
    [Test]
    procedure DetailsFallBackToTarget;
    [Test]
    procedure DetailsComeFromFunction;
    [Test]
    procedure ObserverForwardsToNext;
    [Test]
    procedure SharedIsEnabledByDefault;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.StatusFile;

type
  /// <summary>Zählt die Meldungen, die der Beobachter weiterreicht.</summary>
  TCountingObserver = class(TInterfacedObject, IJsonRpcRequestObserver)
  public
    StartedCount: Integer;
    FinishedCount: Integer;
    procedure Started(const AMethod: string);
    procedure Finished(const AMethod: string; const AParams, AResult: TJSONValue; const AError: Exception;
      AQueueMs, AElapsedMs: Int64);
  end;

procedure TCountingObserver.Started(const AMethod: string);
begin
  Inc(StartedCount);
end;

procedure TCountingObserver.Finished(const AMethod: string; const AParams, AResult: TJSONValue;
  const AError: Exception; AQueueMs, AElapsedMs: Int64);
begin
  Inc(FinishedCount);
end;

procedure TServerActivityTests.Setup;
begin
  FActivity := TServerActivity.Create;
end;

procedure TServerActivityTests.TearDown;
begin
  FreeAndNil(FActivity);
end;

procedure TServerActivityTests.DescribesProcess;
var
  mEntry: TServerStatusEntry;
begin
  FActivity.Describe(TServerStatusEntry.cKindCli, 'check', 'App.dproj');
  FActivity.SetLogFile('server.log');
  mEntry := FActivity.Snapshot(1000);
  Assert.AreEqual('cli', mEntry.Kind);
  Assert.AreEqual('check', mEntry.Command);
  Assert.AreEqual('App.dproj', mEntry.Target);
  Assert.AreEqual('server.log', mEntry.LogFile);
  Assert.IsTrue(mEntry.Started > 0);
  Assert.AreEqual('ready', mEntry.State);
  Assert.AreEqual(0, mEntry.Running);
end;

procedure TServerActivityTests.TracksLongestRunningRequest;
var
  mEntry: TServerStatusEntry;
  mThread: TThread;
  mActivity: TServerActivity;
begin
  mActivity := FActivity;
  FActivity.RequestStarted('textDocument/hover', 1000);
  // Eine zweite Anfrage in einem anderen Thread, früher begonnen.
  mThread := TThread.CreateAnonymousThread(
    procedure
    begin
      mActivity.RequestStarted('workspace/symbol', 400);
    end);
  mThread.FreeOnTerminate := False;
  try
    mThread.Start;
    mThread.WaitFor;
  finally
    mThread.Free;
  end;
  mEntry := FActivity.Snapshot(1500);
  Assert.AreEqual(2, mEntry.Running);
  Assert.AreEqual('workspace/symbol', mEntry.RunningMethod);
  Assert.AreEqual<Int64>(1100, mEntry.RunningMs);
  Assert.AreEqual('working', mEntry.State);
  FActivity.RequestFinished(False);
  mEntry := FActivity.Snapshot(1500);
  Assert.AreEqual(1, mEntry.Running, 'nur die Anfrage dieses Threads ist fertig');
  Assert.AreEqual(0, mEntry.Errors);
end;

procedure TServerActivityTests.CountsErrorsAndTimeouts;
var
  mEntry: TServerStatusEntry;
begin
  FActivity.RequestStarted('textDocument/hover', 10);
  FActivity.RequestFinished(True);
  FActivity.CountTimeout;
  FActivity.CountTimeout;
  mEntry := FActivity.Snapshot(20);
  Assert.AreEqual(1, mEntry.Errors);
  Assert.AreEqual(2, mEntry.Timeouts);
  Assert.AreEqual(0, mEntry.Running);
end;

procedure TServerActivityTests.ProgressMeansWorking;
var
  mEntry: TServerStatusEntry;
begin
  FActivity.SetProgress(3, 10);
  mEntry := FActivity.Snapshot(0);
  Assert.AreEqual(3, mEntry.Done);
  Assert.AreEqual(10, mEntry.Total);
  Assert.AreEqual('working', mEntry.State);
  FActivity.SetProgress(10, 10);
  Assert.AreEqual('ready', FActivity.Snapshot(0).State);
end;

procedure TServerActivityTests.DetailsFallBackToTarget;
var
  mDetails: TServerDetails;
begin
  Assert.AreEqual(0, Integer(Length(FActivity.Details.Roots)), 'ohne Ziel keine Wurzel');
  FActivity.Describe(TServerStatusEntry.cKindMcp, '', 'C:\Projekte\App');
  mDetails := FActivity.Details;
  Assert.IsNull(mDetails.Status);
  Assert.AreEqual(1, Integer(Length(mDetails.Roots)));
  Assert.AreEqual('C:\Projekte\App', mDetails.Roots[0]);
  mDetails := Default(TServerDetails);
end;

procedure TServerActivityTests.DetailsComeFromFunction;
var
  mDetails: TServerDetails;
begin
  FActivity.SetDetails(
    function: TServerDetails
    begin
      Result := Default(TServerDetails);
      Result.Roots := TArray<string>.Create('C:\A', 'C:\B');
      Result.State := 'loading';
      Result.Status := TJSONObject.Create;
    end);
  mDetails := FActivity.Details;
  try
    Assert.AreEqual(2, Integer(Length(mDetails.Roots)));
    Assert.AreEqual('loading', mDetails.State);
    Assert.IsNotNull(mDetails.Status);
  finally
    mDetails.Status.Free;
  end;
  // Abgemeldet: wieder ohne Status.
  FActivity.SetDetails(nil);
  Assert.IsNull(FActivity.Details.Status);
  mDetails := Default(TServerDetails);
end;

procedure TServerActivityTests.ObserverForwardsToNext;
var
  mCounter: TCountingObserver;
  mNext, mObserver: IJsonRpcRequestObserver;
  mError: Exception;
begin
  mCounter := TCountingObserver.Create;
  mNext := mCounter;
  mObserver := TServerActivityObserver.Create(FActivity, mNext);
  mObserver.Started('initialize');
  Assert.AreEqual(1, FActivity.Snapshot(TThread.GetTickCount64).Running);
  mError := Exception.Create('kaputt');
  try
    mObserver.Finished('initialize', nil, nil, mError, 0, 5);
  finally
    mError.Free;
  end;
  Assert.AreEqual(1, mCounter.StartedCount);
  Assert.AreEqual(1, mCounter.FinishedCount);
  Assert.AreEqual(0, FActivity.Snapshot(TThread.GetTickCount64).Running);
  Assert.AreEqual(1, FActivity.Snapshot(TThread.GetTickCount64).Errors);
  // Ohne Nachfolger nur die Aktivität.
  mObserver := TServerActivityObserver.Create(FActivity, nil);
  mObserver.Started('shutdown');
  mObserver.Finished('shutdown', nil, nil, nil, 0, 1);
  Assert.AreEqual(1, FActivity.Snapshot(TThread.GetTickCount64).Errors);
end;

procedure TServerActivityTests.SharedIsEnabledByDefault;
begin
  Assert.IsNotNull(TServerActivity.Shared);
  Assert.IsTrue(TServerActivity.Shared.Enabled);
  FActivity.Enabled := False;
  Assert.IsFalse(FActivity.Enabled);
end;

initialization
  TDUnitX.RegisterTestFixture(TServerActivityTests);

end.
