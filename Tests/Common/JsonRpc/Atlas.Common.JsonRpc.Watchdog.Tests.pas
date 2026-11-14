unit Atlas.Common.JsonRpc.Watchdog.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcWatchdogTests = class
  public
    [Test]
    procedure CancelsRequestAfterTimeout;
    [Test]
    procedure UnwatchedRequestIsNotCancelled;
    [Test]
    procedure ZeroTimeoutDisablesWatching;
    [Test]
    procedure SetTimeoutAppliesToLaterRequests;
    /// <summary>Nebenläufige Anfrage wird beim Ablauf genau einmal beantwortet.</summary>
    [Test]
    procedure AnswersConcurrentRequestOnceAfterTimeout;
    [Test]
    procedure HandlerAnswerBeforeTimeoutWins;
    [Test]
    procedure WatchWithoutResponderOnlyCancels;
    /// <summary>Die Fehlerantwort des Watchdogs zählt als laufende Arbeit: WaitForWork meldet erst Ruhe, wenn sie
    /// geschrieben ist (sonst ging sie beim Beenden der Verbindung verloren).</summary>
    [Test]
    procedure TimeoutAnswerCountsAsWork;
    /// <summary>#1355: OnExpired bekommt id (als JSON-Text), Methode und Zeitlimit für den Absturzfall.</summary>
    [Test]
    procedure ExpiredEventGetsIdAndMethod;
    /// <summary>Hat der Client die Anfrage vor dem Zeitlimit abgebrochen ($/cancelRequest nach seiner kürzeren
    /// Frist), meldet OnExpired sie nicht (kein Absturzfall); OnTimeout und die Antwort bleiben.</summary>
    [Test]
    procedure ExpiredEventSkipsRequestCancelledByClient;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.PendingRequests,
  Atlas.Common.JsonRpc.Watchdog;

function WaitUntil(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal): Boolean;
var
  mDue: UInt64;
begin
  mDue := TThread.GetTickCount64 + ATimeoutMs;
  while not ACondition() do
  begin
    if TThread.GetTickCount64 > mDue then
    begin
      Exit(False);
    end;
    TThread.Sleep(5);
  end;
  Result := True;
end;

{ TJsonRpcWatchdogTests }

procedure TJsonRpcWatchdogTests.CancelsRequestAfterTimeout;
var
  mPending: IJsonRpcPendingRequests;
  mWatchdog: IJsonRpcWatchdog;
  mId: TJSONValue;
  mToken: IJsonRpcCancellationToken;
  mTimedOut: string;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mTimedOut := '';
  mWatchdog := TJsonRpcWatchdog.Create(mPending, 20,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      mTimedOut := AMethod;
    end);
  mId := TJSONNumber.Create(7);
  try
    mToken := mPending.Acquire(mId);
    mWatchdog.Watch(mId, 'test/slow');
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := mToken.IsCancellationRequested;
      end, 2000));
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := mTimedOut <> '';
      end, 2000));
    Assert.AreEqual('test/slow', mTimedOut);
    mPending.Release(mId, mToken);
  finally
    mId.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.UnwatchedRequestIsNotCancelled;
var
  mPending: IJsonRpcPendingRequests;
  mWatchdog: IJsonRpcWatchdog;
  mId: TJSONValue;
  mToken: IJsonRpcCancellationToken;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mWatchdog := TJsonRpcWatchdog.Create(mPending, 50, nil);
  mId := TJSONNumber.Create(8);
  try
    mToken := mPending.Acquire(mId);
    mWatchdog.Unwatch(mWatchdog.Watch(mId, 'test/fast'));
    TThread.Sleep(150);
    Assert.IsFalse(mToken.IsCancellationRequested);
    mPending.Release(mId, mToken);
  finally
    mId.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.ZeroTimeoutDisablesWatching;
var
  mWatchdog: IJsonRpcWatchdog;
  mId: TJSONValue;
begin
  mWatchdog := TJsonRpcWatchdog.Create(TJsonRpcPendingRequests.Create, 0, nil);
  mId := TJSONNumber.Create(9);
  try
    Assert.AreEqual(Int64(0), mWatchdog.Watch(mId, 'test/any'));
  finally
    mId.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.SetTimeoutAppliesToLaterRequests;
var
  mPending: IJsonRpcPendingRequests;
  mWatchdog: IJsonRpcWatchdog;
  mId: TJSONValue;
  mToken: IJsonRpcCancellationToken;
  mReported: Cardinal;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mReported := 0;
  mWatchdog := TJsonRpcWatchdog.Create(mPending, 60000,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      mReported := ATimeoutMs;
    end);
  mWatchdog.SetTimeout(20);
  mId := TJSONNumber.Create(10);
  try
    mToken := mPending.Acquire(mId);
    mWatchdog.Watch(mId, 'test/slow');
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := mReported <> 0;
      end, 2000));
    Assert.AreEqual(Cardinal(20), mReported);
    Assert.IsTrue(mToken.IsCancellationRequested);
    mPending.Release(mId, mToken);
  finally
    mId.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.AnswersConcurrentRequestOnceAfterTimeout;
var
  mPending: IJsonRpcPendingRequests;
  mWatchdog: IJsonRpcWatchdog;
  mId: TJSONValue;
  mToken: IJsonRpcCancellationToken;
  mAnswers, mCode, mAnswerId: Integer;
  mTimeouts: Integer;
  mAnswered: Boolean;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mAnswers := 0;
  mCode := 0;
  mAnswerId := 0;
  mTimeouts := 0;
  mAnswered := False;
  mWatchdog := TJsonRpcWatchdog.Create(mPending, 20,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      mAnswered := AAnswered;
      TInterlocked.Increment(mTimeouts);
    end);
  mId := TJSONNumber.Create(1);
  try
    mToken := mPending.Acquire(mId);
    mWatchdog.Watch(mId, 'test/slow', mToken,
      procedure(const AResponse: TJSONObject)
      begin
        try
          mCode := AResponse.GetValue<Integer>('error.code');
          mAnswerId := AResponse.GetValue<Integer>('id');
          TInterlocked.Increment(mAnswers);
        finally
          AResponse.Free;
        end;
      end);
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := mTimeouts > 0;
      end, 2000));
    TThread.Sleep(50);
    Assert.AreEqual(1, mAnswers);
    Assert.AreEqual(TJsonRpcErrorCode.cRequestCancelled, mCode);
    Assert.AreEqual(1, mAnswerId);
    Assert.IsTrue(mAnswered);
    Assert.IsTrue(mToken.IsCancellationRequested);
    // Der Worker darf danach nicht mehr antworten.
    Assert.IsFalse(mPending.TryAnswer(mToken));
    mPending.Release(mId, mToken);
  finally
    mId.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.HandlerAnswerBeforeTimeoutWins;
var
  mPending: IJsonRpcPendingRequests;
  mWatchdog: IJsonRpcWatchdog;
  mId: TJSONValue;
  mToken: IJsonRpcCancellationToken;
  mAnswers, mTimeouts: Integer;
  mAnswered: Boolean;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mAnswers := 0;
  mTimeouts := 0;
  mAnswered := True;
  mWatchdog := TJsonRpcWatchdog.Create(mPending, 20,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      mAnswered := AAnswered;
      TInterlocked.Increment(mTimeouts);
    end);
  mId := TJSONNumber.Create(2);
  try
    mToken := mPending.Acquire(mId);
    // Der "Worker" hat schon geantwortet, aber Unwatch noch nicht erreicht.
    Assert.IsTrue(mPending.TryAnswer(mToken));
    mWatchdog.Watch(mId, 'test/slow', mToken,
      procedure(const AResponse: TJSONObject)
      begin
        TInterlocked.Increment(mAnswers);
        AResponse.Free;
      end);
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := mTimeouts > 0;
      end, 2000));
    Assert.AreEqual(0, mAnswers);
    Assert.IsFalse(mAnswered);
    mPending.Release(mId, mToken);
  finally
    mId.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.WatchWithoutResponderOnlyCancels;
var
  mPending: IJsonRpcPendingRequests;
  mWatchdog: IJsonRpcWatchdog;
  mId: TJSONValue;
  mToken: IJsonRpcCancellationToken;
  mTimeouts: Integer;
  mAnswered: Boolean;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mTimeouts := 0;
  mAnswered := True;
  mWatchdog := TJsonRpcWatchdog.Create(mPending, 20,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      mAnswered := AAnswered;
      TInterlocked.Increment(mTimeouts);
    end);
  mId := TJSONNumber.Create(3);
  try
    mToken := mPending.Acquire(mId);
    mWatchdog.Watch(mId, 'test/sync');
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := mTimeouts > 0;
      end, 2000));
    Assert.IsFalse(mAnswered);
    Assert.IsTrue(mToken.IsCancellationRequested);
    // Synchrone Anfragen antworten selbst.
    Assert.IsTrue(mPending.TryAnswer(mToken));
    mPending.Release(mId, mToken);
  finally
    mId.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.TimeoutAnswerCountsAsWork;
var
  mPending: IJsonRpcPendingRequests;
  mWatchdog: IJsonRpcWatchdog;
  mId: TJSONValue;
  mToken: IJsonRpcCancellationToken;
  mGate: TEvent;
  mWriting: Integer;
begin
  mPending := TJsonRpcPendingRequests.Create;
  Assert.IsTrue(mPending.WaitForWork(0), 'ohne Arbeit ruhig');
  mWriting := 0;
  mGate := TEvent.Create(nil, True, False, '');
  try
    mWatchdog := TJsonRpcWatchdog.Create(mPending, 20, nil);
    mId := TJSONNumber.Create(4);
    try
      mToken := mPending.Acquire(mId);
      // Die Antwort "schreibt" so lange, bis der Test das Tor öffnet.
      mWatchdog.Watch(mId, 'test/slow', mToken,
        procedure(const AResponse: TJSONObject)
        begin
          TInterlocked.Increment(mWriting);
          mGate.WaitFor(5000);
          AResponse.Free;
        end);
      Assert.IsTrue(WaitUntil(
        function: Boolean
        begin
          Result := mWriting > 0;
        end, 2000), 'Watchdog antwortet nicht');
      Assert.IsFalse(mPending.WaitForWork(50), 'Ruhe gemeldet, bevor die Antwort geschrieben ist');
      mGate.SetEvent;
      Assert.IsTrue(mPending.WaitForWork(2000), 'nach der Antwort ruhig');
      mPending.Release(mId, mToken);
    finally
      mId.Free;
    end;
    mWatchdog := nil;
  finally
    mGate.Free;
  end;
end;


procedure TJsonRpcWatchdogTests.ExpiredEventGetsIdAndMethod;
var
  mPending: IJsonRpcPendingRequests;
  mWatchdog: TJsonRpcWatchdog;
  mWatchdogRef: IJsonRpcWatchdog;
  mId: TJSONValue;
  mToken: IJsonRpcCancellationToken;
  mSeen: string;
  mLock: TObject;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mSeen := '';
  mLock := TObject.Create;
  try
    mWatchdog := TJsonRpcWatchdog.Create(mPending, 20, nil);
    mWatchdogRef := mWatchdog;
    mWatchdog.OnExpired :=
      procedure(const AId, AMethod: string; ATimeoutMs: Cardinal)
      begin
        System.TMonitor.Enter(mLock);
        try
          mSeen := Format('%s %s %d', [AId, AMethod, ATimeoutMs]);
        finally
          System.TMonitor.Exit(mLock);
        end;
      end;
    mId := TJSONString.Create('abc');
    try
      mToken := mPending.Acquire(mId);
      mWatchdog.Watch(mId, 'test/slow');
      Assert.IsTrue(WaitUntil(
        function: Boolean
        begin
          System.TMonitor.Enter(mLock);
          try
            Result := mSeen <> '';
          finally
            System.TMonitor.Exit(mLock);
          end;
        end, 2000));
      Assert.AreEqual('"abc" test/slow 20', mSeen);
      mPending.Release(mId, mToken);
    finally
      mId.Free;
    end;
    mWatchdogRef := nil;
  finally
    mLock.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.ExpiredEventSkipsRequestCancelledByClient;
var
  mPending: IJsonRpcPendingRequests;
  mWatchdog: TJsonRpcWatchdog;
  mWatchdogRef: IJsonRpcWatchdog;
  mId: TJSONValue;
  mToken: IJsonRpcCancellationToken;
  mExpired, mTimeouts, mAnswers: Integer;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mExpired := 0;
  mTimeouts := 0;
  mAnswers := 0;
  mWatchdog := TJsonRpcWatchdog.Create(mPending, 20,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      TInterlocked.Increment(mTimeouts);
    end);
  mWatchdogRef := mWatchdog;
  mWatchdog.OnExpired :=
    procedure(const AId, AMethod: string; ATimeoutMs: Cardinal)
    begin
      TInterlocked.Increment(mExpired);
    end;
  mId := TJSONNumber.Create(11);
  try
    mToken := mPending.Acquire(mId);
    // Der Client gibt auf, bevor das Zeitlimit des Servers abläuft; der Handler prüft sein Signal nicht.
    mPending.Cancel(mId);
    mWatchdog.Watch(mId, 'textDocument/codeAction', mToken,
      procedure(const AResponse: TJSONObject)
      begin
        TInterlocked.Increment(mAnswers);
        AResponse.Free;
      end);
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := TInterlocked.CompareExchange(mTimeouts, 0, 0) > 0;
      end, 2000));
    TThread.Sleep(20);
    Assert.AreEqual(0, TInterlocked.CompareExchange(mExpired, 0, 0), 'kein Absturzfall');
    Assert.AreEqual(1, TInterlocked.CompareExchange(mAnswers, 0, 0), 'genau eine Antwort');
    mPending.Release(mId, mToken);
  finally
    mId.Free;
  end;
  mWatchdogRef := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcWatchdogTests);

end.
