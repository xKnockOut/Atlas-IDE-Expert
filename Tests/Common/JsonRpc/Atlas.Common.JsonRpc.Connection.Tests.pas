unit Atlas.Common.JsonRpc.Connection.Tests;

// Nachrichtenschleife über Streams im Speicher. Kein Test lässt einen Thread
// zurück: Run wartet auf seinen Lese-Thread, und nebenläufige
// Anfragen laufen in eigenen Threads (TJoinedWorkers), auf die der Test vor
// dem Ende wartet. Der Thread-Pool der RTL behielte seine Worker über den
// Test hinaus; ihn prüft der Dauerlauf in Atlas.Tests.LeakMonitor.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcConnectionTests = class
  public
    [Test]
    procedure AnswersRequestsUntilInputCloses;
    [Test]
    procedure StopsAfterStopAndLeavesRemainingInput;
    [Test]
    procedure AnswersInvalidJsonWithParseErrorAndContinues;
    [Test]
    procedure ReportsNotificationHandlerErrorAndContinues;
    [Test]
    procedure AnswersConcurrentRequestFromWorker;
    [Test]
    procedure CancelsRunningConcurrentRequest;
    [Test]
    procedure KeepsOrderOfNotificationsAndRequests;
    [Test]
    procedure RaisesTransportErrorOfBrokenStream;
    [Test]
    procedure PostedMessageRunsBeforeRemainingInput;
    [Test]
    procedure PostWithoutLoopFreesMessage;
    /// <summary>Arbeit aus fremden Threads läuft im Thread von Run.</summary>
    [Test]
    procedure QueuedWorkRunsInLoopBeforeRemainingInput;
    [Test]
    procedure QueueWithoutLoopReturnsFalse;
    [Test]
    procedure QueuedWorkErrorIsReported;
    /// <summary>Der Watchdog beantwortet eine hängende nebenläufige Anfrage, die späte
    /// Antwort des Handlers wird verworfen.</summary>
    [Test]
    procedure WatchdogAnswersHangingRequestOnce;
    [Test]
    procedure RunReportsUnfinishedWork;
    /// <summary>Nach Run hält kein Thread der Verbindung mehr etwas von ihr; der Transport ist mit
    /// der Verbindung frei.</summary>
    [Test]
    procedure RunReleasesReaderBeforeReturning;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  System.Diagnostics,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.JsonRpc.Connection,
  Atlas.Common.JsonRpc.StreamTransport,
  Atlas.Common.JsonRpc.Watchdog,
  Atlas.Common.JsonRpc.TestSupport;

type
  ETestFailure = class(Exception);

  /// <summary>Scheduler für nebenläufige Anfragen: jede in einem eigenen Thread, auf den JoinAll wartet.</summary>
  TJoinedWorkers = class
  private
    FLock: TObject;
    FThreads: TList<TThread>;
    procedure Start(const AWork: TProc);
  public
    constructor Create;
    /// <summary>Wartet wie JoinAll.</summary>
    destructor Destroy; override;
    function Scheduler: TJsonRpcScheduler;
    /// <summary>Wartet auf alle bisher gestarteten Threads und gibt sie frei.</summary>
    procedure JoinAll;
  end;

  /// <summary>Transport, der sein Freigeben meldet.</summary>
  TTrackedTransport = class(TJsonRpcStreamTransport)
  private
    FDestroyed: PBoolean;
  public
    constructor Create(AInput, AOutput: TStream; ADestroyed: PBoolean);
    destructor Destroy; override;
  end;

{ TJoinedWorkers }

constructor TJoinedWorkers.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FThreads := TList<TThread>.Create;
end;

destructor TJoinedWorkers.Destroy;
begin
  JoinAll;
  FThreads.Free;
  FLock.Free;
  inherited;
end;

procedure TJoinedWorkers.Start(const AWork: TProc);
var
  mThread: TThread;
begin
  mThread := TThread.CreateAnonymousThread(AWork);
  mThread.FreeOnTerminate := False;
  TMonitor.Enter(FLock);
  try
    FThreads.Add(mThread);
  finally
    TMonitor.Exit(FLock);
  end;
  mThread.Start;
end;

function TJoinedWorkers.Scheduler: TJsonRpcScheduler;
begin
  Result := Start;
end;

procedure TJoinedWorkers.JoinAll;
var
  mThreads: TArray<TThread>;
  mThread: TThread;
begin
  TMonitor.Enter(FLock);
  try
    mThreads := FThreads.ToArray;
    FThreads.Clear;
  finally
    TMonitor.Exit(FLock);
  end;
  for mThread in mThreads do
  begin
    mThread.WaitFor;
    mThread.Free;
  end;
end;

{ TTrackedTransport }

constructor TTrackedTransport.Create(AInput, AOutput: TStream; ADestroyed: PBoolean);
begin
  inherited Create(AInput, AOutput, False);
  FDestroyed := ADestroyed;
end;

destructor TTrackedTransport.Destroy;
begin
  FDestroyed^ := True;
  inherited;
end;

// Lässt eine Verbindung über die Eingabe laufen und liefert die Antworten.
// Gibt AInput frei.
function RunConnectionOn(AInput: TBytesStream; ADispatcher: TJsonRpcDispatcher;
  const AConfigure: TProc<TJsonRpcConnection>): TObjectList<TJSONObject>;
var
  mInput: TBytesStream;
  mOutput: TBytesStream;
  mConnection: TJsonRpcConnection;
begin
  mInput := AInput;
  mOutput := TBytesStream.Create;
  try
    mConnection := TJsonRpcConnection.Create(TJsonRpcStreamTransport.Create(mInput, mOutput, False), ADispatcher);
    try
      if Assigned(AConfigure) then
      begin
        AConfigure(mConnection);
      end;
      mConnection.Run;
    finally
      mConnection.Free;
    end;
    Result := TJsonRpcTestSupport.ReadMessages(mOutput);
  finally
    mOutput.Free;
    mInput.Free;
  end;
end;

function RunConnection(const AInput: array of string; ADispatcher: TJsonRpcDispatcher;
  const AConfigure: TProc<TJsonRpcConnection>): TObjectList<TJSONObject>;
begin
  Result := RunConnectionOn(TJsonRpcTestSupport.InputOf(AInput), ADispatcher, AConfigure);
end;

function FindResponse(AResponses: TObjectList<TJSONObject>; AId: Integer): TJSONObject;
var
  mResponse: TJSONObject;
begin
  for mResponse in AResponses do
  begin
    if mResponse.GetValue<Integer>('id') = AId then
    begin
      Exit(mResponse);
    end;
  end;
  Result := nil;
end;

// Normale Anfrage "await": wartet in der Nachrichtenschleife, bis keine
// nebenläufige Anfrage mehr läuft, und liefert, ob das rechtzeitig geschah.
procedure RegisterAwait(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterRequest('await',
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := TJSONBool.Create(ADispatcher.PendingRequests.WaitForWork(5000));
    end);
end;

function CreateEchoDispatcher: TJsonRpcDispatcher;
begin
  Result := TJsonRpcDispatcher.Create;
  Result.RegisterRequest('echo',
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := TJSONValue(AParams.Clone);
    end);
end;

{ TJsonRpcConnectionTests }

procedure TJsonRpcConnectionTests.AnswersRequestsUntilInputCloses;
var
  mDispatcher: TJsonRpcDispatcher;
  mResponses: TObjectList<TJSONObject>;
begin
  mDispatcher := CreateEchoDispatcher;
  try
    mResponses := RunConnection([
      '{"jsonrpc":"2.0","id":1,"method":"echo","params":"eins"}',
      '{"jsonrpc":"2.0","method":"note"}',
      '{"jsonrpc":"2.0","id":2,"method":"echo","params":"zwei"}'], mDispatcher, nil);
    try
      Assert.AreEqual<NativeInt>(2, mResponses.Count);
      Assert.AreEqual('eins', mResponses[0].GetValue<string>('result'));
      Assert.AreEqual(2, mResponses[1].GetValue<Integer>('id'));
    finally
      mResponses.Free;
    end;
  finally
    mDispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.StopsAfterStopAndLeavesRemainingInput;
var
  mDispatcher: TJsonRpcDispatcher;
  mResponses: TObjectList<TJSONObject>;
  mConnection: TJsonRpcConnection;
begin
  mDispatcher := CreateEchoDispatcher;
  try
    mConnection := nil;
    mDispatcher.RegisterNotification('stop',
      procedure(const AParams: TJSONValue)
      begin
        mConnection.Stop;
      end);
    mResponses := RunConnection([
      '{"jsonrpc":"2.0","id":1,"method":"echo","params":1}',
      '{"jsonrpc":"2.0","method":"stop"}',
      '{"jsonrpc":"2.0","id":2,"method":"echo","params":2}'], mDispatcher,
      procedure(AConnection: TJsonRpcConnection)
      begin
        mConnection := AConnection;
      end);
    try
      Assert.AreEqual<NativeInt>(1, mResponses.Count);
      Assert.AreEqual(1, mResponses[0].GetValue<Integer>('id'));
    finally
      mResponses.Free;
    end;
  finally
    mDispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.AnswersInvalidJsonWithParseErrorAndContinues;
var
  mDispatcher: TJsonRpcDispatcher;
  mResponses: TObjectList<TJSONObject>;
begin
  mDispatcher := CreateEchoDispatcher;
  try
    mResponses := RunConnection([
      '{kein json',
      '{"jsonrpc":"2.0","id":2,"method":"echo","params":"weiter"}'], mDispatcher, nil);
    try
      Assert.AreEqual<NativeInt>(2, mResponses.Count);
      Assert.AreEqual(TJsonRpcErrorCode.cParseError, mResponses[0].GetValue<Integer>('error.code'));
      Assert.IsTrue(mResponses[0].GetValue('id') is TJSONNull);
      Assert.AreEqual('weiter', mResponses[1].GetValue<string>('result'));
    finally
      mResponses.Free;
    end;
  finally
    mDispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.ReportsNotificationHandlerErrorAndContinues;
var
  mDispatcher: TJsonRpcDispatcher;
  mResponses: TObjectList<TJSONObject>;
  mReported: string;
begin
  mDispatcher := CreateEchoDispatcher;
  try
    mDispatcher.RegisterNotification('broken',
      procedure(const AParams: TJSONValue)
      begin
        raise ETestFailure.Create('kaputt');
      end);
    mResponses := RunConnection([
      '{"jsonrpc":"2.0","method":"broken"}',
      '{"jsonrpc":"2.0","id":2,"method":"echo","params":"weiter"}'], mDispatcher,
      procedure(AConnection: TJsonRpcConnection)
      begin
        AConnection.OnError :=
          procedure(const AError: Exception)
          begin
            mReported := AError.Message;
          end;
      end);
    try
      Assert.AreEqual('kaputt', mReported);
      Assert.AreEqual<NativeInt>(1, mResponses.Count);
      Assert.AreEqual('weiter', mResponses[0].GetValue<string>('result'));
    finally
      mResponses.Free;
    end;
  finally
    mDispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.AnswersConcurrentRequestFromWorker;
var
  mDispatcher: TJsonRpcDispatcher;
  mResponses: TObjectList<TJSONObject>;
  mWorkers: TJoinedWorkers;
begin
  mWorkers := TJoinedWorkers.Create;
  mDispatcher := CreateEchoDispatcher;
  try
    mDispatcher.Scheduler := mWorkers.Scheduler();
    mDispatcher.RegisterConcurrentRequest('parallel',
      function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
      begin
        Result := TJSONString.Create('aus dem Worker');
      end);
    RegisterAwait(mDispatcher);
    mResponses := RunConnection([
      '{"jsonrpc":"2.0","id":1,"method":"parallel"}',
      '{"jsonrpc":"2.0","id":2,"method":"await"}'], mDispatcher, nil);
    mWorkers.JoinAll;
    try
      Assert.AreEqual<NativeInt>(2, mResponses.Count);
      Assert.AreEqual('aus dem Worker', FindResponse(mResponses, 1).GetValue<string>('result'));
      Assert.IsTrue(FindResponse(mResponses, 2).GetValue<Boolean>('result'));
    finally
      mResponses.Free;
    end;
  finally
    mDispatcher.Free;
    mWorkers.Free;
  end;
end;

procedure TJsonRpcConnectionTests.CancelsRunningConcurrentRequest;
var
  mDispatcher: TJsonRpcDispatcher;
  mResponses: TObjectList<TJSONObject>;
  mWorkers: TJoinedWorkers;
begin
  mWorkers := TJoinedWorkers.Create;
  mDispatcher := CreateEchoDispatcher;
  try
    mDispatcher.Scheduler := mWorkers.Scheduler();
    // Läuft, bis sie abgebrochen wird (höchstens 10 s).
    mDispatcher.RegisterConcurrentRequest('slow',
      function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
      var
        Watch: TStopwatch;
      begin
        Watch := TStopwatch.StartNew;
        while not ACancellation.IsCancellationRequested and (Watch.ElapsedMilliseconds < 10000) do
        begin
          TThread.Sleep(5);
        end;
        ACancellation.ThrowIfCancellationRequested;
        Result := TJSONString.Create('nicht abgebrochen');
      end);
    RegisterAwait(mDispatcher);
    // "await" läuft, bevor die Eingabe endet: Fertig wird "slow" nur durch $/cancelRequest.
    mResponses := RunConnection([
      '{"jsonrpc":"2.0","id":1,"method":"slow"}',
      '{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":1}}',
      '{"jsonrpc":"2.0","id":2,"method":"await"}'], mDispatcher, nil);
    mWorkers.JoinAll;
    try
      Assert.AreEqual<NativeInt>(2, mResponses.Count);
      Assert.AreEqual(TJsonRpcErrorCode.cRequestCancelled, FindResponse(mResponses, 1).GetValue<Integer>('error.code'));
      Assert.IsTrue(FindResponse(mResponses, 2).GetValue<Boolean>('result'));
    finally
      mResponses.Free;
    end;
  finally
    mDispatcher.Free;
    mWorkers.Free;
  end;
end;

procedure TJsonRpcConnectionTests.KeepsOrderOfNotificationsAndRequests;
const
  cChangeCount = 50;
var
  mDispatcher: TJsonRpcDispatcher;
  mResponses: TObjectList<TJSONObject>;
  mInput: TArray<string>;
  mReceived: TStringBuilder;
  mExpected: TStringBuilder;
  I: Integer;
begin
  mReceived := TStringBuilder.Create;
  mExpected := TStringBuilder.Create;
  mDispatcher := CreateEchoDispatcher;
  try
    mDispatcher.RegisterNotification('change',
      procedure(const AParams: TJSONValue)
      begin
        mReceived.Append(AParams.Value).Append(',');
      end);
    mDispatcher.RegisterRequest('received',
      function(const AParams: TJSONValue): TJSONValue
      begin
        Result := TJSONString.Create(mReceived.ToString);
      end);
    for I := 1 to cChangeCount do
    begin
      mInput := mInput + [Format('{"jsonrpc":"2.0","method":"change","params":%d}', [I])];
      mExpected.Append(I).Append(',');
    end;
    mInput := mInput + ['{"jsonrpc":"2.0","id":1,"method":"received"}'];

    mResponses := RunConnection(mInput, mDispatcher, nil);
    try
      Assert.AreEqual<NativeInt>(1, mResponses.Count);
      Assert.AreEqual(mExpected.ToString, mResponses[0].GetValue<string>('result'));
    finally
      mResponses.Free;
    end;
  finally
    mDispatcher.Free;
    mExpected.Free;
    mReceived.Free;
  end;
end;

procedure TJsonRpcConnectionTests.RaisesTransportErrorOfBrokenStream;
var
  mDispatcher: TJsonRpcDispatcher;
begin
  mDispatcher := CreateEchoDispatcher;
  try
    Assert.WillRaise(
      procedure
      begin
        RunConnectionOn(TJsonRpcTestSupport.RawInput('Content-Length: abc'#13#10#13#10'{}'), mDispatcher, nil).Free;
      end,
      EJsonRpcTransportError);
  finally
    mDispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.PostedMessageRunsBeforeRemainingInput;
var
  mDispatcher: TJsonRpcDispatcher;
  mResponses: TObjectList<TJSONObject>;
  mConnection: TJsonRpcConnection;
  mOrder: string;
begin
  // Eigene Nachrichten (#227, Dateibeobachter) laufen in der Schleife vor dem Rest der Eingabe.
  mOrder := '';
  mDispatcher := CreateEchoDispatcher;
  try
    mConnection := nil;
    mDispatcher.RegisterNotification('first',
      procedure(const AParams: TJSONValue)
      begin
        mOrder := mOrder + 'first ';
        Assert.IsTrue(mConnection.Post(TJSONObject.ParseJSONValue(
          '{"jsonrpc":"2.0","method":"posted","params":{"n":1}}') as TJSONObject));
        Assert.IsTrue(mConnection.Post(TJSONObject.ParseJSONValue(
          '{"jsonrpc":"2.0","method":"posted","params":{"n":2}}') as TJSONObject));
      end);
    mDispatcher.RegisterNotification('posted',
      procedure(const AParams: TJSONValue)
      begin
        mOrder := mOrder + 'posted' + IntToStr(AParams.GetValue<Integer>('n')) + ' ';
      end);
    mDispatcher.RegisterNotification('last',
      procedure(const AParams: TJSONValue)
      begin
        mOrder := mOrder + 'last';
      end);
    mResponses := RunConnection([
      '{"jsonrpc":"2.0","method":"first"}',
      '{"jsonrpc":"2.0","method":"last"}'], mDispatcher,
      procedure(AConnection: TJsonRpcConnection)
      begin
        mConnection := AConnection;
      end);
    mResponses.Free;
  finally
    mDispatcher.Free;
  end;
  Assert.AreEqual('first posted1 posted2 last', mOrder);
end;

procedure TJsonRpcConnectionTests.PostWithoutLoopFreesMessage;
var
  mDispatcher: TJsonRpcDispatcher;
  mConnection: TJsonRpcConnection;
begin
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mConnection := TJsonRpcConnection.Create(nil, mDispatcher);
    try
      // Ohne Run: verworfen und freigegeben (der Leck-Monitor prüft das).
      Assert.IsFalse(mConnection.Post(TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","method":"x"}') as TJSONObject));
    finally
      mConnection.Free;
    end;
  finally
    mDispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.QueuedWorkRunsInLoopBeforeRemainingInput;
var
  mDispatcher: TJsonRpcDispatcher;
  mResponses: TObjectList<TJSONObject>;
  mConnection: TJsonRpcConnection;
  mOrder: string;
  mLoopThread, mWorkThread: TThreadID;
begin
  mOrder := '';
  mLoopThread := 0;
  mWorkThread := 0;
  mDispatcher := CreateEchoDispatcher;
  try
    mConnection := nil;
    mDispatcher.RegisterNotification('first',
      procedure(const AParams: TJSONValue)
      begin
        mOrder := mOrder + 'first ';
        mLoopThread := TThread.Current.ThreadID;
        Assert.IsTrue(mConnection.Queue(
          procedure
          begin
            mOrder := mOrder + 'work ';
            mWorkThread := TThread.Current.ThreadID;
          end));
      end);
    mDispatcher.RegisterNotification('last',
      procedure(const AParams: TJSONValue)
      begin
        mOrder := mOrder + 'last';
      end);
    mResponses := RunConnection([
      '{"jsonrpc":"2.0","method":"first"}',
      '{"jsonrpc":"2.0","method":"last"}'], mDispatcher,
      procedure(AConnection: TJsonRpcConnection)
      begin
        mConnection := AConnection;
      end);
    mResponses.Free;
  finally
    mDispatcher.Free;
  end;
  Assert.AreEqual('first work last', mOrder);
  Assert.AreEqual<TThreadID>(mLoopThread, mWorkThread, 'Arbeit lief nicht im Thread der Schleife');
end;

procedure TJsonRpcConnectionTests.QueueWithoutLoopReturnsFalse;
var
  mDispatcher: TJsonRpcDispatcher;
  mConnection: TJsonRpcConnection;
  mRan: Boolean;
begin
  mRan := False;
  mDispatcher := TJsonRpcDispatcher.Create;
  try
    mConnection := TJsonRpcConnection.Create(nil, mDispatcher);
    try
      Assert.IsFalse(mConnection.Queue(
        procedure
        begin
          mRan := True;
        end));
    finally
      mConnection.Free;
    end;
  finally
    mDispatcher.Free;
  end;
  Assert.IsFalse(mRan);
end;

procedure TJsonRpcConnectionTests.QueuedWorkErrorIsReported;
var
  mDispatcher: TJsonRpcDispatcher;
  mResponses: TObjectList<TJSONObject>;
  mConnection: TJsonRpcConnection;
  mReported: Integer;
begin
  mReported := 0;
  mDispatcher := CreateEchoDispatcher;
  try
    mConnection := nil;
    mDispatcher.RegisterNotification('first',
      procedure(const AParams: TJSONValue)
      begin
        mConnection.Queue(
          procedure
          begin
            raise ETestFailure.Create('kaputt');
          end);
      end);
    mResponses := RunConnection([
      '{"jsonrpc":"2.0","method":"first"}',
      '{"jsonrpc":"2.0","id":2,"method":"echo","params":"weiter"}'], mDispatcher,
      procedure(AConnection: TJsonRpcConnection)
      begin
        mConnection := AConnection;
        AConnection.OnError :=
          procedure(const AError: Exception)
          begin
            if AError.Message = 'kaputt' then
            begin
              Inc(mReported);
            end;
          end;
      end);
    try
      Assert.AreEqual(1, mReported);
      Assert.AreEqual<NativeInt>(1, mResponses.Count);
      Assert.AreEqual('weiter', mResponses[0].GetValue<string>('result'));
    finally
      mResponses.Free;
    end;
  finally
    mDispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.WatchdogAnswersHangingRequestOnce;
var
  mDispatcher: TJsonRpcDispatcher;
  mResponses: TObjectList<TJSONObject>;
  mResponse: TJSONObject;
  mForFirst: Integer;
  mWorkers: TJoinedWorkers;
begin
  mWorkers := TJoinedWorkers.Create;
  mDispatcher := CreateEchoDispatcher;
  try
    mDispatcher.Scheduler := mWorkers.Scheduler();
    mDispatcher.Watchdog := TJsonRpcWatchdog.Create(mDispatcher.PendingRequests, 100, nil);
    // Prüft das Abbruchsignal nicht: antwortet erst nach dem Zeitlimit.
    mDispatcher.RegisterConcurrentRequest('slow',
      function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
      begin
        TThread.Sleep(300);
        Result := TJSONString.Create('late');
      end);
    RegisterAwait(mDispatcher);
    mResponses := RunConnection([
      '{"jsonrpc":"2.0","id":1,"method":"slow"}',
      '{"jsonrpc":"2.0","id":2,"method":"await"}'], mDispatcher, nil);
    mWorkers.JoinAll;
    try
      mForFirst := 0;
      for mResponse in mResponses do
      begin
        if mResponse.GetValue<Integer>('id') = 1 then
        begin
          Inc(mForFirst);
        end;
      end;
      Assert.AreEqual(1, mForFirst, 'genau eine Antwort auf id 1');
      Assert.AreEqual(TJsonRpcErrorCode.cRequestCancelled, FindResponse(mResponses, 1).GetValue<Integer>('error.code'));
      Assert.IsNull(FindResponse(mResponses, 1).GetValue('result'), 'späte Antwort verworfen');
      Assert.IsTrue(FindResponse(mResponses, 2).GetValue<Boolean>('result'));
    finally
      mResponses.Free;
    end;
  finally
    mDispatcher.Watchdog := nil;
    mDispatcher.Free;
    mWorkers.Free;
  end;
end;

procedure TJsonRpcConnectionTests.RunReportsUnfinishedWork;
var
  mDispatcher: TJsonRpcDispatcher;
  mInput, mOutput: TBytesStream;
  mConnection: TJsonRpcConnection;
  mUnfinished: Boolean;
  mStarted: Boolean;
  mWorkers: TJoinedWorkers;
begin
  mStarted := False;
  mWorkers := TJoinedWorkers.Create;
  mDispatcher := CreateEchoDispatcher;
  try
    mDispatcher.Scheduler := mWorkers.Scheduler();
    mDispatcher.RegisterConcurrentRequest('slow',
      function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
      begin
        mStarted := True;
        TThread.Sleep(300);
        Result := TJSONString.Create('late');
      end);
    // Hält die Schleife an, bis der Handler läuft: Sonst bräche das Beenden ihn vor dem Start ab.
    mDispatcher.RegisterRequest('started',
      function(const AParams: TJSONValue): TJSONValue
      var
        Watch: TStopwatch;
      begin
        Watch := TStopwatch.StartNew;
        while not mStarted and (Watch.ElapsedMilliseconds < 2000) do
        begin
          TThread.Sleep(5);
        end;
        Result := TJSONBool.Create(mStarted);
      end);
    mInput := TJsonRpcTestSupport.InputOf(['{"jsonrpc":"2.0","id":1,"method":"slow"}',
      '{"jsonrpc":"2.0","id":2,"method":"started"}']);
    mOutput := TBytesStream.Create;
    try
      mConnection := TJsonRpcConnection.Create(TJsonRpcStreamTransport.Create(mInput, mOutput, False), mDispatcher);
      try
        mConnection.WorkTimeout := 50;
        mConnection.Run;
        mUnfinished := mConnection.UnfinishedWork;
      finally
        mConnection.Free;
      end;
      // Erst nach dem Worker freigeben: Er schreibt seine Antwort noch in Output.
      Assert.IsTrue(mDispatcher.PendingRequests.WaitForWork(2000));
      mWorkers.JoinAll;
    finally
      mOutput.Free;
      mInput.Free;
    end;
    Assert.IsTrue(mUnfinished);
  finally
    mDispatcher.Free;
    mWorkers.Free;
  end;
end;

procedure TJsonRpcConnectionTests.RunReleasesReaderBeforeReturning;
var
  mDispatcher: TJsonRpcDispatcher;
  mInput, mOutput: TBytesStream;
  mConnection: TJsonRpcConnection;
  mDestroyed: Boolean;
begin
  mDestroyed := False;
  mDispatcher := CreateEchoDispatcher;
  try
    mInput := TJsonRpcTestSupport.InputOf(['{"jsonrpc":"2.0","id":1,"method":"echo","params":1}']);
    mOutput := TBytesStream.Create;
    try
      mConnection := TJsonRpcConnection.Create(TTrackedTransport.Create(mInput, mOutput, @mDestroyed), mDispatcher);
      try
        mConnection.Run;
      finally
        mConnection.Free;
      end;
      // Der Lese-Thread hält den Transport. Gab er sich erst nach Run selbst frei, lebte der hier noch.
      Assert.IsTrue(mDestroyed, 'Transport nach Run und Free noch gehalten');
    finally
      mOutput.Free;
      mInput.Free;
    end;
  finally
    mDispatcher.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcConnectionTests);

end.
