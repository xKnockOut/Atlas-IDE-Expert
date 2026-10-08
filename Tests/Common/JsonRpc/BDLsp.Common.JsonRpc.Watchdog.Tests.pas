unit BDLsp.Common.JsonRpc.Watchdog.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.PendingRequests,
  BDLsp.Common.JsonRpc.Watchdog;

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
    procedure(const AMethod: string; ATimeoutMs: Cardinal)
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
    procedure(const AMethod: string; ATimeoutMs: Cardinal)
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

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcWatchdogTests);

end.
