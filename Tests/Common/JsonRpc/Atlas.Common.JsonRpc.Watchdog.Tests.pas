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
    /// <summary>Code-Review A-06: nebenläufige Anfrage wird beim Ablauf genau einmal beantwortet.</summary>
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
  Due: UInt64;
begin
  Due := TThread.GetTickCount64 + ATimeoutMs;
  while not ACondition() do
  begin
    if TThread.GetTickCount64 > Due then
      Exit(False);
    TThread.Sleep(5);
  end;
  Result := True;
end;

{ TJsonRpcWatchdogTests }

procedure TJsonRpcWatchdogTests.CancelsRequestAfterTimeout;
var
  Pending: IJsonRpcPendingRequests;
  Watchdog: IJsonRpcWatchdog;
  Id: TJSONValue;
  Token: IJsonRpcCancellationToken;
  TimedOut: string;
begin
  Pending := TJsonRpcPendingRequests.Create;
  TimedOut := '';
  Watchdog := TJsonRpcWatchdog.Create(Pending, 20,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      TimedOut := AMethod;
    end);
  Id := TJSONNumber.Create(7);
  try
    Token := Pending.Acquire(Id);
    Watchdog.Watch(Id, 'test/slow');
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := Token.IsCancellationRequested;
      end, 2000));
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := TimedOut <> '';
      end, 2000));
    Assert.AreEqual('test/slow', TimedOut);
    Pending.Release(Id, Token);
  finally
    Id.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.UnwatchedRequestIsNotCancelled;
var
  Pending: IJsonRpcPendingRequests;
  Watchdog: IJsonRpcWatchdog;
  Id: TJSONValue;
  Token: IJsonRpcCancellationToken;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Watchdog := TJsonRpcWatchdog.Create(Pending, 50, nil);
  Id := TJSONNumber.Create(8);
  try
    Token := Pending.Acquire(Id);
    Watchdog.Unwatch(Watchdog.Watch(Id, 'test/fast'));
    TThread.Sleep(150);
    Assert.IsFalse(Token.IsCancellationRequested);
    Pending.Release(Id, Token);
  finally
    Id.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.ZeroTimeoutDisablesWatching;
var
  Watchdog: IJsonRpcWatchdog;
  Id: TJSONValue;
begin
  Watchdog := TJsonRpcWatchdog.Create(TJsonRpcPendingRequests.Create, 0, nil);
  Id := TJSONNumber.Create(9);
  try
    Assert.AreEqual(Int64(0), Watchdog.Watch(Id, 'test/any'));
  finally
    Id.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.SetTimeoutAppliesToLaterRequests;
var
  Pending: IJsonRpcPendingRequests;
  Watchdog: IJsonRpcWatchdog;
  Id: TJSONValue;
  Token: IJsonRpcCancellationToken;
  Reported: Cardinal;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Reported := 0;
  Watchdog := TJsonRpcWatchdog.Create(Pending, 60000,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      Reported := ATimeoutMs;
    end);
  Watchdog.SetTimeout(20);
  Id := TJSONNumber.Create(10);
  try
    Token := Pending.Acquire(Id);
    Watchdog.Watch(Id, 'test/slow');
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := Reported <> 0;
      end, 2000));
    Assert.AreEqual(Cardinal(20), Reported);
    Assert.IsTrue(Token.IsCancellationRequested);
    Pending.Release(Id, Token);
  finally
    Id.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.AnswersConcurrentRequestOnceAfterTimeout;
var
  Pending: IJsonRpcPendingRequests;
  Watchdog: IJsonRpcWatchdog;
  Id: TJSONValue;
  Token: IJsonRpcCancellationToken;
  Answers, Code, AnswerId: Integer;
  Timeouts: Integer;
  Answered: Boolean;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Answers := 0;
  Code := 0;
  AnswerId := 0;
  Timeouts := 0;
  Answered := False;
  Watchdog := TJsonRpcWatchdog.Create(Pending, 20,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      Answered := AAnswered;
      TInterlocked.Increment(Timeouts);
    end);
  Id := TJSONNumber.Create(1);
  try
    Token := Pending.Acquire(Id);
    Watchdog.Watch(Id, 'test/slow', Token,
      procedure(const AResponse: TJSONObject)
      begin
        try
          Code := AResponse.GetValue<Integer>('error.code');
          AnswerId := AResponse.GetValue<Integer>('id');
          TInterlocked.Increment(Answers);
        finally
          AResponse.Free;
        end;
      end);
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := Timeouts > 0;
      end, 2000));
    TThread.Sleep(50);
    Assert.AreEqual(1, Answers);
    Assert.AreEqual(TJsonRpcErrorCode.RequestCancelled, Code);
    Assert.AreEqual(1, AnswerId);
    Assert.IsTrue(Answered);
    Assert.IsTrue(Token.IsCancellationRequested);
    // Der Worker darf danach nicht mehr antworten.
    Assert.IsFalse(Pending.TryAnswer(Token));
    Pending.Release(Id, Token);
  finally
    Id.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.HandlerAnswerBeforeTimeoutWins;
var
  Pending: IJsonRpcPendingRequests;
  Watchdog: IJsonRpcWatchdog;
  Id: TJSONValue;
  Token: IJsonRpcCancellationToken;
  Answers, Timeouts: Integer;
  Answered: Boolean;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Answers := 0;
  Timeouts := 0;
  Answered := True;
  Watchdog := TJsonRpcWatchdog.Create(Pending, 20,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      Answered := AAnswered;
      TInterlocked.Increment(Timeouts);
    end);
  Id := TJSONNumber.Create(2);
  try
    Token := Pending.Acquire(Id);
    // Der "Worker" hat schon geantwortet, aber Unwatch noch nicht erreicht.
    Assert.IsTrue(Pending.TryAnswer(Token));
    Watchdog.Watch(Id, 'test/slow', Token,
      procedure(const AResponse: TJSONObject)
      begin
        TInterlocked.Increment(Answers);
        AResponse.Free;
      end);
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := Timeouts > 0;
      end, 2000));
    Assert.AreEqual(0, Answers);
    Assert.IsFalse(Answered);
    Pending.Release(Id, Token);
  finally
    Id.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.WatchWithoutResponderOnlyCancels;
var
  Pending: IJsonRpcPendingRequests;
  Watchdog: IJsonRpcWatchdog;
  Id: TJSONValue;
  Token: IJsonRpcCancellationToken;
  Timeouts: Integer;
  Answered: Boolean;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Timeouts := 0;
  Answered := True;
  Watchdog := TJsonRpcWatchdog.Create(Pending, 20,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      Answered := AAnswered;
      TInterlocked.Increment(Timeouts);
    end);
  Id := TJSONNumber.Create(3);
  try
    Token := Pending.Acquire(Id);
    Watchdog.Watch(Id, 'test/sync');
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := Timeouts > 0;
      end, 2000));
    Assert.IsFalse(Answered);
    Assert.IsTrue(Token.IsCancellationRequested);
    // Synchrone Anfragen antworten selbst.
    Assert.IsTrue(Pending.TryAnswer(Token));
    Pending.Release(Id, Token);
  finally
    Id.Free;
  end;
end;

procedure TJsonRpcWatchdogTests.TimeoutAnswerCountsAsWork;
var
  Pending: IJsonRpcPendingRequests;
  Watchdog: IJsonRpcWatchdog;
  Id: TJSONValue;
  Token: IJsonRpcCancellationToken;
  Gate: TEvent;
  Writing: Integer;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Assert.IsTrue(Pending.WaitForWork(0), 'ohne Arbeit ruhig');
  Writing := 0;
  Gate := TEvent.Create(nil, True, False, '');
  try
    Watchdog := TJsonRpcWatchdog.Create(Pending, 20, nil);
    Id := TJSONNumber.Create(4);
    try
      Token := Pending.Acquire(Id);
      // Die Antwort "schreibt" so lange, bis der Test das Tor öffnet.
      Watchdog.Watch(Id, 'test/slow', Token,
        procedure(const AResponse: TJSONObject)
        begin
          TInterlocked.Increment(Writing);
          Gate.WaitFor(5000);
          AResponse.Free;
        end);
      Assert.IsTrue(WaitUntil(
        function: Boolean
        begin
          Result := Writing > 0;
        end, 2000), 'Watchdog antwortet nicht');
      Assert.IsFalse(Pending.WaitForWork(50), 'Ruhe gemeldet, bevor die Antwort geschrieben ist');
      Gate.SetEvent;
      Assert.IsTrue(Pending.WaitForWork(2000), 'nach der Antwort ruhig');
      Pending.Release(Id, Token);
    finally
      Id.Free;
    end;
    Watchdog := nil;
  finally
    Gate.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcWatchdogTests);

end.
