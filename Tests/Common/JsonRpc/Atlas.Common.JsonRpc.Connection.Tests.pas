unit Atlas.Common.JsonRpc.Connection.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcConnectionTests = class
  public
    [Test]
    // Worker- bzw. Pool-Threads legen Verwaltungsdaten an, die erst nach dem Test freigegeben werden.
    [IgnoreMemoryLeaks]
    procedure AnswersRequestsUntilInputCloses;
    [Test]
    procedure StopsAfterStopAndLeavesRemainingInput;
    [Test]
    procedure AnswersInvalidJsonWithParseErrorAndContinues;
    [Test]
    procedure ReportsNotificationHandlerErrorAndContinues;
    [Test]
    // Worker- bzw. Pool-Threads legen Verwaltungsdaten an, die erst nach dem Test freigegeben werden.
    [IgnoreMemoryLeaks]
    procedure AnswersConcurrentRequestFromWorker;
    [Test]
    // Worker- bzw. Pool-Threads legen Verwaltungsdaten an, die erst nach dem Test freigegeben werden.
    [IgnoreMemoryLeaks]
    procedure CancelsRunningConcurrentRequest;
    [Test]
    // Worker- bzw. Pool-Threads legen Verwaltungsdaten an, die erst nach dem Test freigegeben werden.
    [IgnoreMemoryLeaks]
    procedure KeepsOrderOfNotificationsAndRequests;
    [Test]
    procedure RaisesTransportErrorOfBrokenStream;
    [Test]
    procedure PostedMessageRunsBeforeRemainingInput;
    [Test]
    procedure PostWithoutLoopFreesMessage;
    /// <summary>Code-Review A-03: Arbeit aus fremden Threads läuft im Thread von Run.</summary>
    [Test]
    procedure QueuedWorkRunsInLoopBeforeRemainingInput;
    [Test]
    procedure QueueWithoutLoopReturnsFalse;
    [Test]
    procedure QueuedWorkErrorIsReported;
    /// <summary>Code-Review A-06: Der Watchdog beantwortet eine hängende nebenläufige Anfrage, die späte
    /// Antwort des Handlers wird verworfen.</summary>
    [Test]
    // Worker- bzw. Pool-Threads legen Verwaltungsdaten an, die erst nach dem Test freigegeben werden.
    [IgnoreMemoryLeaks]
    procedure WatchdogAnswersHangingRequestOnce;
    [Test]
    // Worker- bzw. Pool-Threads legen Verwaltungsdaten an, die erst nach dem Test freigegeben werden.
    [IgnoreMemoryLeaks]
    procedure RunReportsUnfinishedWork;
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

// Lässt eine Verbindung über die Eingabe laufen und liefert die Antworten.
// Gibt AInput frei.
function RunConnectionOn(AInput: TBytesStream; ADispatcher: TJsonRpcDispatcher;
  const AConfigure: TProc<TJsonRpcConnection>): TObjectList<TJSONObject>;
var
  Input: TBytesStream;
  Output: TBytesStream;
  Connection: TJsonRpcConnection;
begin
  Input := AInput;
  Output := TBytesStream.Create;
  try
    Connection := TJsonRpcConnection.Create(TJsonRpcStreamTransport.Create(Input, Output, False), ADispatcher);
    try
      if Assigned(AConfigure) then
        AConfigure(Connection);
      Connection.Run;
    finally
      Connection.Free;
    end;
    Result := TJsonRpcTestSupport.ReadMessages(Output);
  finally
    Output.Free;
    Input.Free;
  end;
end;

function RunConnection(const AInput: array of string; ADispatcher: TJsonRpcDispatcher;
  const AConfigure: TProc<TJsonRpcConnection>): TObjectList<TJSONObject>;
begin
  Result := RunConnectionOn(TJsonRpcTestSupport.InputOf(AInput), ADispatcher, AConfigure);
end;

function FindResponse(AResponses: TObjectList<TJSONObject>; AId: Integer): TJSONObject;
var
  Response: TJSONObject;
begin
  for Response in AResponses do
    if Response.GetValue<Integer>('id') = AId then
      Exit(Response);
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
  Dispatcher: TJsonRpcDispatcher;
  Responses: TObjectList<TJSONObject>;
begin
  Dispatcher := CreateEchoDispatcher;
  try
    Responses := RunConnection([
      '{"jsonrpc":"2.0","id":1,"method":"echo","params":"eins"}',
      '{"jsonrpc":"2.0","method":"note"}',
      '{"jsonrpc":"2.0","id":2,"method":"echo","params":"zwei"}'], Dispatcher, nil);
    try
      Assert.AreEqual<NativeInt>(2, Responses.Count);
      Assert.AreEqual('eins', Responses[0].GetValue<string>('result'));
      Assert.AreEqual(2, Responses[1].GetValue<Integer>('id'));
    finally
      Responses.Free;
    end;
  finally
    Dispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.StopsAfterStopAndLeavesRemainingInput;
var
  Dispatcher: TJsonRpcDispatcher;
  Responses: TObjectList<TJSONObject>;
  Connection: TJsonRpcConnection;
begin
  Dispatcher := CreateEchoDispatcher;
  try
    Connection := nil;
    Dispatcher.RegisterNotification('stop',
      procedure(const AParams: TJSONValue)
      begin
        Connection.Stop;
      end);
    Responses := RunConnection([
      '{"jsonrpc":"2.0","id":1,"method":"echo","params":1}',
      '{"jsonrpc":"2.0","method":"stop"}',
      '{"jsonrpc":"2.0","id":2,"method":"echo","params":2}'], Dispatcher,
      procedure(AConnection: TJsonRpcConnection)
      begin
        Connection := AConnection;
      end);
    try
      Assert.AreEqual<NativeInt>(1, Responses.Count);
      Assert.AreEqual(1, Responses[0].GetValue<Integer>('id'));
    finally
      Responses.Free;
    end;
  finally
    Dispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.AnswersInvalidJsonWithParseErrorAndContinues;
var
  Dispatcher: TJsonRpcDispatcher;
  Responses: TObjectList<TJSONObject>;
begin
  Dispatcher := CreateEchoDispatcher;
  try
    Responses := RunConnection([
      '{kein json',
      '{"jsonrpc":"2.0","id":2,"method":"echo","params":"weiter"}'], Dispatcher, nil);
    try
      Assert.AreEqual<NativeInt>(2, Responses.Count);
      Assert.AreEqual(TJsonRpcErrorCode.ParseError, Responses[0].GetValue<Integer>('error.code'));
      Assert.IsTrue(Responses[0].GetValue('id') is TJSONNull);
      Assert.AreEqual('weiter', Responses[1].GetValue<string>('result'));
    finally
      Responses.Free;
    end;
  finally
    Dispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.ReportsNotificationHandlerErrorAndContinues;
var
  Dispatcher: TJsonRpcDispatcher;
  Responses: TObjectList<TJSONObject>;
  Reported: string;
begin
  Dispatcher := CreateEchoDispatcher;
  try
    Dispatcher.RegisterNotification('broken',
      procedure(const AParams: TJSONValue)
      begin
        raise ETestFailure.Create('kaputt');
      end);
    Responses := RunConnection([
      '{"jsonrpc":"2.0","method":"broken"}',
      '{"jsonrpc":"2.0","id":2,"method":"echo","params":"weiter"}'], Dispatcher,
      procedure(AConnection: TJsonRpcConnection)
      begin
        AConnection.OnError :=
          procedure(const AError: Exception)
          begin
            Reported := AError.Message;
          end;
      end);
    try
      Assert.AreEqual('kaputt', Reported);
      Assert.AreEqual<NativeInt>(1, Responses.Count);
      Assert.AreEqual('weiter', Responses[0].GetValue<string>('result'));
    finally
      Responses.Free;
    end;
  finally
    Dispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.AnswersConcurrentRequestFromWorker;
var
  Dispatcher: TJsonRpcDispatcher;
  Responses: TObjectList<TJSONObject>;
begin
  Dispatcher := CreateEchoDispatcher;
  try
    Dispatcher.RegisterConcurrentRequest('parallel',
      function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
      begin
        Result := TJSONString.Create('aus dem Worker');
      end);
    RegisterAwait(Dispatcher);
    Responses := RunConnection([
      '{"jsonrpc":"2.0","id":1,"method":"parallel"}',
      '{"jsonrpc":"2.0","id":2,"method":"await"}'], Dispatcher, nil);
    try
      Assert.AreEqual<NativeInt>(2, Responses.Count);
      Assert.AreEqual('aus dem Worker', FindResponse(Responses, 1).GetValue<string>('result'));
      Assert.IsTrue(FindResponse(Responses, 2).GetValue<Boolean>('result'));
    finally
      Responses.Free;
    end;
  finally
    Dispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.CancelsRunningConcurrentRequest;
var
  Dispatcher: TJsonRpcDispatcher;
  Responses: TObjectList<TJSONObject>;
begin
  Dispatcher := CreateEchoDispatcher;
  try
    // Läuft, bis sie abgebrochen wird (höchstens 10 s).
    Dispatcher.RegisterConcurrentRequest('slow',
      function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
      var
        Watch: TStopwatch;
      begin
        Watch := TStopwatch.StartNew;
        while not ACancellation.IsCancellationRequested and (Watch.ElapsedMilliseconds < 10000) do
          TThread.Sleep(5);
        ACancellation.ThrowIfCancellationRequested;
        Result := TJSONString.Create('nicht abgebrochen');
      end);
    RegisterAwait(Dispatcher);
    // "await" läuft, bevor die Eingabe endet: Fertig wird "slow" nur durch $/cancelRequest.
    Responses := RunConnection([
      '{"jsonrpc":"2.0","id":1,"method":"slow"}',
      '{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":1}}',
      '{"jsonrpc":"2.0","id":2,"method":"await"}'], Dispatcher, nil);
    try
      Assert.AreEqual<NativeInt>(2, Responses.Count);
      Assert.AreEqual(TJsonRpcErrorCode.RequestCancelled, FindResponse(Responses, 1).GetValue<Integer>('error.code'));
      Assert.IsTrue(FindResponse(Responses, 2).GetValue<Boolean>('result'));
    finally
      Responses.Free;
    end;
  finally
    Dispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.KeepsOrderOfNotificationsAndRequests;
const
  ChangeCount = 50;
var
  Dispatcher: TJsonRpcDispatcher;
  Responses: TObjectList<TJSONObject>;
  Input: TArray<string>;
  Received: TStringBuilder;
  Expected: TStringBuilder;
  I: Integer;
begin
  Received := TStringBuilder.Create;
  Expected := TStringBuilder.Create;
  Dispatcher := CreateEchoDispatcher;
  try
    Dispatcher.RegisterNotification('change',
      procedure(const AParams: TJSONValue)
      begin
        Received.Append(AParams.Value).Append(',');
      end);
    Dispatcher.RegisterRequest('received',
      function(const AParams: TJSONValue): TJSONValue
      begin
        Result := TJSONString.Create(Received.ToString);
      end);
    for I := 1 to ChangeCount do
    begin
      Input := Input + [Format('{"jsonrpc":"2.0","method":"change","params":%d}', [I])];
      Expected.Append(I).Append(',');
    end;
    Input := Input + ['{"jsonrpc":"2.0","id":1,"method":"received"}'];

    Responses := RunConnection(Input, Dispatcher, nil);
    try
      Assert.AreEqual<NativeInt>(1, Responses.Count);
      Assert.AreEqual(Expected.ToString, Responses[0].GetValue<string>('result'));
    finally
      Responses.Free;
    end;
  finally
    Dispatcher.Free;
    Expected.Free;
    Received.Free;
  end;
end;

procedure TJsonRpcConnectionTests.RaisesTransportErrorOfBrokenStream;
var
  Dispatcher: TJsonRpcDispatcher;
begin
  Dispatcher := CreateEchoDispatcher;
  try
    Assert.WillRaise(
      procedure
      begin
        RunConnectionOn(TJsonRpcTestSupport.RawInput('Content-Length: abc'#13#10#13#10'{}'), Dispatcher, nil).Free;
      end,
      EJsonRpcTransportError);
  finally
    Dispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.PostedMessageRunsBeforeRemainingInput;
var
  Dispatcher: TJsonRpcDispatcher;
  Responses: TObjectList<TJSONObject>;
  Connection: TJsonRpcConnection;
  Order: string;
begin
  // Eigene Nachrichten (#227, Dateibeobachter) laufen in der Schleife vor dem Rest der Eingabe.
  Order := '';
  Dispatcher := CreateEchoDispatcher;
  try
    Connection := nil;
    Dispatcher.RegisterNotification('first',
      procedure(const AParams: TJSONValue)
      begin
        Order := Order + 'first ';
        Assert.IsTrue(Connection.Post(TJSONObject.ParseJSONValue(
          '{"jsonrpc":"2.0","method":"posted","params":{"n":1}}') as TJSONObject));
        Assert.IsTrue(Connection.Post(TJSONObject.ParseJSONValue(
          '{"jsonrpc":"2.0","method":"posted","params":{"n":2}}') as TJSONObject));
      end);
    Dispatcher.RegisterNotification('posted',
      procedure(const AParams: TJSONValue)
      begin
        Order := Order + 'posted' + IntToStr(AParams.GetValue<Integer>('n')) + ' ';
      end);
    Dispatcher.RegisterNotification('last',
      procedure(const AParams: TJSONValue)
      begin
        Order := Order + 'last';
      end);
    Responses := RunConnection([
      '{"jsonrpc":"2.0","method":"first"}',
      '{"jsonrpc":"2.0","method":"last"}'], Dispatcher,
      procedure(AConnection: TJsonRpcConnection)
      begin
        Connection := AConnection;
      end);
    Responses.Free;
  finally
    Dispatcher.Free;
  end;
  Assert.AreEqual('first posted1 posted2 last', Order);
end;

procedure TJsonRpcConnectionTests.PostWithoutLoopFreesMessage;
var
  Dispatcher: TJsonRpcDispatcher;
  Connection: TJsonRpcConnection;
begin
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Connection := TJsonRpcConnection.Create(nil, Dispatcher);
    try
      // Ohne Run: verworfen und freigegeben (der Leck-Monitor prüft das).
      Assert.IsFalse(Connection.Post(TJSONObject.ParseJSONValue('{"jsonrpc":"2.0","method":"x"}') as TJSONObject));
    finally
      Connection.Free;
    end;
  finally
    Dispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.QueuedWorkRunsInLoopBeforeRemainingInput;
var
  Dispatcher: TJsonRpcDispatcher;
  Responses: TObjectList<TJSONObject>;
  Connection: TJsonRpcConnection;
  Order: string;
  LoopThread, WorkThread: TThreadID;
begin
  Order := '';
  LoopThread := 0;
  WorkThread := 0;
  Dispatcher := CreateEchoDispatcher;
  try
    Connection := nil;
    Dispatcher.RegisterNotification('first',
      procedure(const AParams: TJSONValue)
      begin
        Order := Order + 'first ';
        LoopThread := TThread.Current.ThreadID;
        Assert.IsTrue(Connection.Queue(
          procedure
          begin
            Order := Order + 'work ';
            WorkThread := TThread.Current.ThreadID;
          end));
      end);
    Dispatcher.RegisterNotification('last',
      procedure(const AParams: TJSONValue)
      begin
        Order := Order + 'last';
      end);
    Responses := RunConnection([
      '{"jsonrpc":"2.0","method":"first"}',
      '{"jsonrpc":"2.0","method":"last"}'], Dispatcher,
      procedure(AConnection: TJsonRpcConnection)
      begin
        Connection := AConnection;
      end);
    Responses.Free;
  finally
    Dispatcher.Free;
  end;
  Assert.AreEqual('first work last', Order);
  Assert.IsTrue(LoopThread = WorkThread, 'Arbeit lief nicht im Thread der Schleife');
end;

procedure TJsonRpcConnectionTests.QueueWithoutLoopReturnsFalse;
var
  Dispatcher: TJsonRpcDispatcher;
  Connection: TJsonRpcConnection;
  Ran: Boolean;
begin
  Ran := False;
  Dispatcher := TJsonRpcDispatcher.Create;
  try
    Connection := TJsonRpcConnection.Create(nil, Dispatcher);
    try
      Assert.IsFalse(Connection.Queue(
        procedure
        begin
          Ran := True;
        end));
    finally
      Connection.Free;
    end;
  finally
    Dispatcher.Free;
  end;
  Assert.IsFalse(Ran);
end;

procedure TJsonRpcConnectionTests.QueuedWorkErrorIsReported;
var
  Dispatcher: TJsonRpcDispatcher;
  Responses: TObjectList<TJSONObject>;
  Connection: TJsonRpcConnection;
  Reported: Integer;
begin
  Reported := 0;
  Dispatcher := CreateEchoDispatcher;
  try
    Connection := nil;
    Dispatcher.RegisterNotification('first',
      procedure(const AParams: TJSONValue)
      begin
        Connection.Queue(
          procedure
          begin
            raise ETestFailure.Create('kaputt');
          end);
      end);
    Responses := RunConnection([
      '{"jsonrpc":"2.0","method":"first"}',
      '{"jsonrpc":"2.0","id":2,"method":"echo","params":"weiter"}'], Dispatcher,
      procedure(AConnection: TJsonRpcConnection)
      begin
        Connection := AConnection;
        AConnection.OnError :=
          procedure(const AError: Exception)
          begin
            if AError.Message = 'kaputt' then
              Inc(Reported);
          end;
      end);
    try
      Assert.AreEqual(1, Reported);
      Assert.AreEqual<NativeInt>(1, Responses.Count);
      Assert.AreEqual('weiter', Responses[0].GetValue<string>('result'));
    finally
      Responses.Free;
    end;
  finally
    Dispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.WatchdogAnswersHangingRequestOnce;
var
  Dispatcher: TJsonRpcDispatcher;
  Responses: TObjectList<TJSONObject>;
  Response: TJSONObject;
  ForFirst: Integer;
begin
  Dispatcher := CreateEchoDispatcher;
  try
    Dispatcher.Watchdog := TJsonRpcWatchdog.Create(Dispatcher.PendingRequests, 100, nil);
    // Prüft das Abbruchsignal nicht: antwortet erst nach dem Zeitlimit.
    Dispatcher.RegisterConcurrentRequest('slow',
      function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
      begin
        TThread.Sleep(300);
        Result := TJSONString.Create('late');
      end);
    RegisterAwait(Dispatcher);
    Responses := RunConnection([
      '{"jsonrpc":"2.0","id":1,"method":"slow"}',
      '{"jsonrpc":"2.0","id":2,"method":"await"}'], Dispatcher, nil);
    try
      ForFirst := 0;
      for Response in Responses do
        if Response.GetValue<Integer>('id') = 1 then
          Inc(ForFirst);
      Assert.AreEqual(1, ForFirst, 'genau eine Antwort auf id 1');
      Assert.AreEqual(TJsonRpcErrorCode.RequestCancelled, FindResponse(Responses, 1).GetValue<Integer>('error.code'));
      Assert.IsTrue(FindResponse(Responses, 1).GetValue('result') = nil, 'späte Antwort verworfen');
      Assert.IsTrue(FindResponse(Responses, 2).GetValue<Boolean>('result'));
    finally
      Responses.Free;
    end;
  finally
    Dispatcher.Watchdog := nil;
    Dispatcher.Free;
  end;
end;

procedure TJsonRpcConnectionTests.RunReportsUnfinishedWork;
var
  Dispatcher: TJsonRpcDispatcher;
  Input, Output: TBytesStream;
  Connection: TJsonRpcConnection;
  Unfinished: Boolean;
  Started: Boolean;
begin
  Started := False;
  Dispatcher := CreateEchoDispatcher;
  try
    Dispatcher.RegisterConcurrentRequest('slow',
      function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
      begin
        Started := True;
        TThread.Sleep(300);
        Result := TJSONString.Create('late');
      end);
    // Hält die Schleife an, bis der Handler läuft: Sonst bräche das Beenden ihn vor dem Start ab.
    Dispatcher.RegisterRequest('started',
      function(const AParams: TJSONValue): TJSONValue
      var
        Watch: TStopwatch;
      begin
        Watch := TStopwatch.StartNew;
        while not Started and (Watch.ElapsedMilliseconds < 2000) do
          TThread.Sleep(5);
        Result := TJSONBool.Create(Started);
      end);
    Input := TJsonRpcTestSupport.InputOf(['{"jsonrpc":"2.0","id":1,"method":"slow"}',
      '{"jsonrpc":"2.0","id":2,"method":"started"}']);
    Output := TBytesStream.Create;
    try
      Connection := TJsonRpcConnection.Create(TJsonRpcStreamTransport.Create(Input, Output, False), Dispatcher);
      try
        Connection.WorkTimeout := 50;
        Connection.Run;
        Unfinished := Connection.UnfinishedWork;
      finally
        Connection.Free;
      end;
      // Erst nach dem Worker freigeben: Er schreibt seine Antwort noch in Output.
      Assert.IsTrue(Dispatcher.PendingRequests.WaitForWork(2000));
    finally
      Output.Free;
      Input.Free;
    end;
    Assert.IsTrue(Unfinished);
  finally
    Dispatcher.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcConnectionTests);

end.
