unit Atlas.Common.JsonRpc.Dispatcher.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.JsonRpc.Dispatcher;

type
  [TestFixture]
  TJsonRpcDispatcherTests = class
  private
    FDispatcher: TJsonRpcDispatcher;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Code-Review A-06: TJsonRpcCurrentRequest gilt für die Dauer jedes Handlers.</summary>
    [Test]
    procedure CurrentRequestIsSetDuringHandler;
    [Test]
    procedure RoutesRequestAndCopiesNumericId;
    [Test]
    procedure CopiesStringId;
    [Test]
    procedure SendsNilResultAsNull;
    [Test]
    procedure AnswersUnknownRequestWithMethodNotFound;
    [Test]
    procedure IgnoresUnknownNotification;
    [Test]
    procedure CallsNotificationHandlerWithoutResponse;
    [Test]
    procedure AnswersJsonRpcErrorWithItsCode;
    [Test]
    procedure AnswersOtherExceptionWithInternalError;
    [Test]
    procedure PassesNotificationHandlerExceptionToCaller;
    [Test]
    procedure AnswersMissingMethodWithInvalidRequest;
    [Test]
    procedure IgnoresResponsesFromClient;
    [Test]
    procedure RoutesExpectedResponseOnce;
    [Test]
    procedure GuardRejectsRequestWithItsCode;
    [Test]
    procedure GuardDropsNotification;
    [Test]
    procedure RunsConcurrentRequestDirectlyWithoutScheduler;
    [Test]
    procedure SchedulesConcurrentRequestAndAnswersViaResponder;
    [Test]
    procedure AnswersCancelledConcurrentRequestWithRequestCancelled;
    [Test]
    procedure AnswersRequestCancelledWhileQueued;
    [Test]
    procedure WaitForWorkCoversScheduledRequests;
    [Test]
    procedure ReportsUnexpectedErrorsToOnRequestFailed;
    [Test]
    procedure DoesNotReportJsonRpcErrors;
    [Test]
    procedure RemembersLastMessage;
    [Test]
    procedure WatchdogCancelsLongRunningRequest;
    /// <summary>#874: Ein normaler Handler mit Bedingung läuft nebenläufig, wenn sie für die Parameter gilt.</summary>
    [Test]
    procedure RunsConditionalRequestConcurrentlyWhenConditionHolds;
    /// <summary>#874: Die Wartezeit im Posteingang erreicht den Beobachter, auch bei seriellen Anfragen.</summary>
    [Test]
    procedure ReportsQueueTimeToObserver;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.PendingRequests,
  Atlas.Common.JsonRpc.Watchdog,
  Atlas.Common.JsonRpc.CurrentRequest,
  Atlas.Common.JsonRpc.TestSupport;

type
  ETestFailure = class(Exception);

function DispatchJson(ADispatcher: TJsonRpcDispatcher; const AJson: string): TJSONObject;
var
  Message: TJSONObject;
begin
  Message := TJsonRpcTestSupport.Parse(AJson);
  try
    Result := ADispatcher.DispatchMessage(Message);
  finally
    Message.Free;
  end;
end;

type
  /// <summary>Merkt sich die Wartezeit der letzten Anfrage.</summary>
  TQueueObserver = class(TInterfacedObject, IJsonRpcRequestObserver)
  public
    QueueMs: Int64;
    procedure Started(const AMethod: string);
    procedure Finished(const AMethod: string; const AParams, AResult: TJSONValue; const AError: Exception;
      AQueueMs, AElapsedMs: Int64);
  end;

procedure TQueueObserver.Started(const AMethod: string);
begin
end;

procedure TQueueObserver.Finished(const AMethod: string; const AParams, AResult: TJSONValue;
  const AError: Exception; AQueueMs, AElapsedMs: Int64);
begin
  QueueMs := AQueueMs;
end;

type
  /// <summary>Sammelt Arbeit und Antworten, statt Threads zu starten.</summary>
  TManualScheduling = class
  private
    FWork: TList<TProc>;
    FResponses: TObjectList<TJSONObject>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AttachTo(ADispatcher: TJsonRpcDispatcher);
    procedure RunAll;
    property Work: TList<TProc> read FWork;
    property Responses: TObjectList<TJSONObject> read FResponses;
  end;

constructor TManualScheduling.Create;
begin
  inherited Create;
  FWork := TList<TProc>.Create;
  FResponses := TObjectList<TJSONObject>.Create(True);
end;

destructor TManualScheduling.Destroy;
begin
  FResponses.Free;
  FWork.Free;
  inherited;
end;

procedure TManualScheduling.AttachTo(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.Scheduler :=
    procedure(const AWork: TProc)
    begin
      FWork.Add(AWork);
    end;
  ADispatcher.Responder :=
    procedure(const AResponse: TJSONObject)
    begin
      FResponses.Add(AResponse);
    end;
end;

procedure TManualScheduling.RunAll;
var
  mWork: TProc;
begin
  for mWork in FWork.ToArray do
    mWork();
  FWork.Clear;
end;

procedure RegisterConcurrentEcho(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest('parallel',
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      Result := TJSONValue(AParams.Clone);
    end);
end;

{ TJsonRpcDispatcherTests }

procedure TJsonRpcDispatcherTests.Setup;
begin
  FDispatcher := TJsonRpcDispatcher.Create;
  FDispatcher.RegisterRequest('echo',
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := TJSONValue(AParams.Clone);
    end);
end;

procedure TJsonRpcDispatcherTests.TearDown;
begin
  FreeAndNil(FDispatcher);
end;

procedure TJsonRpcDispatcherTests.RoutesRequestAndCopiesNumericId;
var
  Response: TJSONObject;
begin
  Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":7,"method":"echo","params":{"a":1}}');
  try
    Assert.AreEqual('2.0', Response.GetValue<string>('jsonrpc'));
    Assert.AreEqual(7, Response.GetValue<Integer>('id'));
    Assert.AreEqual(1, Response.GetValue<Integer>('result.a'));
    Assert.IsNull(Response.GetValue('error'));
  finally
    Response.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.CopiesStringId;
var
  Response: TJSONObject;
begin
  Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":"abc","method":"echo","params":[]}');
  try
    Assert.AreEqual('abc', Response.GetValue<string>('id'));
  finally
    Response.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.SendsNilResultAsNull;
var
  Response: TJSONObject;
begin
  FDispatcher.RegisterRequest('nothing',
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := nil;
    end);
  Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":1,"method":"nothing"}');
  try
    Assert.IsTrue(Response.GetValue('result') is TJSONNull);
  finally
    Response.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.AnswersUnknownRequestWithMethodNotFound;
var
  Response: TJSONObject;
begin
  Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":3,"method":"gibtsnicht"}');
  try
    Assert.AreEqual(3, Response.GetValue<Integer>('id'));
    Assert.AreEqual(TJsonRpcErrorCode.MethodNotFound, Response.GetValue<Integer>('error.code'));
    Assert.IsNull(Response.GetValue('result'));
  finally
    Response.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.IgnoresUnknownNotification;
begin
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","method":"gibtsnicht"}'));
end;

procedure TJsonRpcDispatcherTests.CallsNotificationHandlerWithoutResponse;
var
  Received: string;
begin
  FDispatcher.RegisterNotification('note',
    procedure(const AParams: TJSONValue)
    begin
      Received := AParams.GetValue<string>('text');
    end);
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","method":"note","params":{"text":"hallo"}}'));
  Assert.AreEqual('hallo', Received);
end;

procedure TJsonRpcDispatcherTests.AnswersJsonRpcErrorWithItsCode;
var
  Response: TJSONObject;
begin
  FDispatcher.RegisterRequest('strict',
    function(const AParams: TJSONValue): TJSONValue
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Parameter fehlen');
    end);
  Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":4,"method":"strict"}');
  try
    Assert.AreEqual(TJsonRpcErrorCode.InvalidParams, Response.GetValue<Integer>('error.code'));
    Assert.AreEqual('Parameter fehlen', Response.GetValue<string>('error.message'));
  finally
    Response.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.AnswersOtherExceptionWithInternalError;
var
  Response: TJSONObject;
begin
  FDispatcher.RegisterRequest('broken',
    function(const AParams: TJSONValue): TJSONValue
    begin
      raise ETestFailure.Create('kaputt');
    end);
  Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":5,"method":"broken"}');
  try
    Assert.AreEqual(TJsonRpcErrorCode.InternalError, Response.GetValue<Integer>('error.code'));
    Assert.Contains(Response.GetValue<string>('error.message'), 'kaputt');
  finally
    Response.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.PassesNotificationHandlerExceptionToCaller;
begin
  FDispatcher.RegisterNotification('broken',
    procedure(const AParams: TJSONValue)
    begin
      raise ETestFailure.Create('kaputt');
    end);
  Assert.WillRaise(
    procedure
    begin
      DispatchJson(FDispatcher, '{"jsonrpc":"2.0","method":"broken"}').Free;
    end, ETestFailure);
end;

procedure TJsonRpcDispatcherTests.AnswersMissingMethodWithInvalidRequest;
var
  Response: TJSONObject;
begin
  Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":6}');
  try
    Assert.AreEqual(TJsonRpcErrorCode.InvalidRequest, Response.GetValue<Integer>('error.code'));
  finally
    Response.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.IgnoresResponsesFromClient;
begin
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":1,"result":null}'));
end;

procedure TJsonRpcDispatcherTests.RoutesExpectedResponseOnce;
var
  Calls: Integer;
  Applied: Boolean;
begin
  // #397: Antwort des Clients auf workspace/applyEdit geht einmal an den angemeldeten Handler.
  Calls := 0;
  Applied := False;
  FDispatcher.ExpectResponse('atlas/applyEdit/1',
    procedure(const AResponse: TJSONObject)
    begin
      Inc(Calls);
      Applied := AResponse.GetValue<Boolean>('result.applied');
    end);
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":"atlas/applyEdit/1","result":{"applied":true}}'));
  Assert.AreEqual(1, Calls);
  Assert.IsTrue(Applied);
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":"atlas/applyEdit/1","result":{"applied":true}}'));
  Assert.AreEqual(1, Calls);
  // Zurückgegebene Anmeldung: kein Aufruf.
  FDispatcher.ExpectResponse('7',
    procedure(const AResponse: TJSONObject)
    begin
      Inc(Calls);
    end);
  FDispatcher.ForgetResponse('7');
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":7,"error":{"code":-1,"message":"x"}}'));
  Assert.AreEqual(1, Calls);
end;

procedure TJsonRpcDispatcherTests.GuardRejectsRequestWithItsCode;
var
  Response: TJSONObject;
begin
  FDispatcher.Guard :=
    procedure(const AMethod: string; AIsRequest: Boolean)
    begin
      raise EJsonRpcError.Create(-32002, 'nicht bereit');
    end;
  Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":8,"method":"echo","params":{}}');
  try
    Assert.AreEqual(-32002, Response.GetValue<Integer>('error.code'));
  finally
    Response.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.GuardDropsNotification;
var
  Called: Boolean;
begin
  Called := False;
  FDispatcher.RegisterNotification('note',
    procedure(const AParams: TJSONValue)
    begin
      Called := True;
    end);
  FDispatcher.Guard :=
    procedure(const AMethod: string; AIsRequest: Boolean)
    begin
      raise EJsonRpcError.Create(-32002, 'nicht bereit');
    end;
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","method":"note"}'));
  Assert.IsFalse(Called);
end;

procedure TJsonRpcDispatcherTests.RunsConcurrentRequestDirectlyWithoutScheduler;
var
  Response: TJSONObject;
begin
  RegisterConcurrentEcho(FDispatcher);
  Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":1,"method":"parallel","params":"direkt"}');
  try
    Assert.AreEqual('direkt', Response.GetValue<string>('result'));
  finally
    Response.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.SchedulesConcurrentRequestAndAnswersViaResponder;
var
  Scheduling: TManualScheduling;
begin
  RegisterConcurrentEcho(FDispatcher);
  Scheduling := TManualScheduling.Create;
  try
    Scheduling.AttachTo(FDispatcher);
    Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":5,"method":"parallel","params":"später"}'));
    Assert.AreEqual<NativeInt>(1, Scheduling.Work.Count);
    Assert.AreEqual<NativeInt>(0, Scheduling.Responses.Count);

    Scheduling.RunAll;
    Assert.AreEqual<NativeInt>(1, Scheduling.Responses.Count);
    Assert.AreEqual(5, Scheduling.Responses[0].GetValue<Integer>('id'));
    Assert.AreEqual('später', Scheduling.Responses[0].GetValue<string>('result'));
  finally
    Scheduling.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.AnswersCancelledConcurrentRequestWithRequestCancelled;
var
  Scheduling: TManualScheduling;
  HandlerCalled: Boolean;
begin
  HandlerCalled := False;
  FDispatcher.RegisterConcurrentRequest('parallel',
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      HandlerCalled := True;
      Result := nil;
    end);
  Scheduling := TManualScheduling.Create;
  try
    Scheduling.AttachTo(FDispatcher);
    Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":"a","method":"parallel"}'));
    Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":"a"}}'));

    Scheduling.RunAll;
    Assert.IsFalse(HandlerCalled);
    Assert.AreEqual<NativeInt>(1, Scheduling.Responses.Count);
    Assert.AreEqual('a', Scheduling.Responses[0].GetValue<string>('id'));
    Assert.AreEqual(TJsonRpcErrorCode.RequestCancelled, Scheduling.Responses[0].GetValue<Integer>('error.code'));
  finally
    Scheduling.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.AnswersRequestCancelledWhileQueued;
var
  Request: TJSONObject;
  Cancel: TJSONObject;
  Response: TJSONObject;
begin
  // So sieht es der Lese-Thread: Anfrage und Abbruch kommen an, bevor die
  // Nachrichtenschleife die Anfrage verarbeitet.
  Request := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","id":9,"method":"echo","params":1}');
  Cancel := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":9}}');
  try
    Assert.IsFalse(FDispatcher.PendingRequests.Observe(Request));
    Assert.IsTrue(FDispatcher.PendingRequests.Observe(Cancel));
    Response := FDispatcher.DispatchMessage(Request);
    try
      Assert.AreEqual(9, Response.GetValue<Integer>('id'));
      Assert.AreEqual(TJsonRpcErrorCode.RequestCancelled, Response.GetValue<Integer>('error.code'));
    finally
      Response.Free;
    end;

    // Dieselbe id später erneut: nicht mehr abgebrochen.
    Response := FDispatcher.DispatchMessage(Request);
    try
      Assert.AreEqual(1, Response.GetValue<Integer>('result'));
    finally
      Response.Free;
    end;
  finally
    Cancel.Free;
    Request.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.WaitForWorkCoversScheduledRequests;
var
  Scheduling: TManualScheduling;
begin
  RegisterConcurrentEcho(FDispatcher);
  Scheduling := TManualScheduling.Create;
  try
    Scheduling.AttachTo(FDispatcher);
    Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":1,"method":"parallel","params":1}'));
    Assert.IsFalse(FDispatcher.PendingRequests.WaitForWork(0));
    Scheduling.RunAll;
    Assert.IsTrue(FDispatcher.PendingRequests.WaitForWork(0));
  finally
    Scheduling.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.ReportsUnexpectedErrorsToOnRequestFailed;
var
  Reported: string;
  Response: TJSONObject;
begin
  Reported := '';
  FDispatcher.OnRequestFailed :=
    procedure(const AMethod: string; const AParams: TJSONValue; const AError: Exception)
    begin
      Reported := AMethod + '|' + AParams.ToJSON + '|' + AError.Message;
    end;
  FDispatcher.RegisterRequest('broken',
    function(const AParams: TJSONValue): TJSONValue
    begin
      raise ETestFailure.Create('kaputt');
    end);
  Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":5,"method":"broken","params":{"a":1}}');
  Response.Free;
  Assert.AreEqual('broken|{"a":1}|kaputt', Reported);
end;

procedure TJsonRpcDispatcherTests.DoesNotReportJsonRpcErrors;
var
  Reported: Boolean;
  Response: TJSONObject;
begin
  Reported := False;
  FDispatcher.OnRequestFailed :=
    procedure(const AMethod: string; const AParams: TJSONValue; const AError: Exception)
    begin
      Reported := True;
    end;
  FDispatcher.RegisterRequest('invalid',
    function(const AParams: TJSONValue): TJSONValue
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'falsch');
    end);
  Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":6,"method":"invalid"}');
  Response.Free;
  Assert.IsFalse(Reported);
end;

procedure TJsonRpcDispatcherTests.RemembersLastMessage;
var
  Response: TJSONObject;
begin
  Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":7,"method":"unbekannt"}');
  Response.Free;
  Assert.AreEqual('unbekannt (id 7)', FDispatcher.LastMessage);
  DispatchJson(FDispatcher, '{"jsonrpc":"2.0","method":"hinweis"}').Free;
  Assert.AreEqual('hinweis', FDispatcher.LastMessage);
end;

procedure TJsonRpcDispatcherTests.WatchdogCancelsLongRunningRequest;
var
  TimedOut: string;
  Response: TJSONObject;
begin
  TimedOut := '';
  FDispatcher.Watchdog := TJsonRpcWatchdog.Create(FDispatcher.PendingRequests, 50,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      TimedOut := AMethod;
    end);
  try
    // Läuft, bis das Abbruchsignal kommt (höchstens 5 s).
    FDispatcher.RegisterConcurrentRequest('slow',
      function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
      var
        Index: Integer;
      begin
        for Index := 1 to 500 do
        begin
          ACancellation.ThrowIfCancellationRequested;
          Sleep(10);
        end;
        Result := TJSONString.Create('fertig');
      end);
    Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":8,"method":"slow"}');
    try
      Assert.AreEqual(TJsonRpcErrorCode.RequestCancelled, Response.GetValue<Integer>('error.code'));
      Assert.AreEqual('slow', TimedOut);
    finally
      Response.Free;
    end;
  finally
    FDispatcher.Watchdog := nil;
  end;
end;

procedure TJsonRpcDispatcherTests.CurrentRequestIsSetDuringHandler;
var
  SyncSeen, ConcurrentSeen: Boolean;
begin
  SyncSeen := False;
  ConcurrentSeen := False;
  FDispatcher.RegisterRequest('sync',
    function(const AParams: TJSONValue): TJSONValue
    begin
      SyncSeen := TJsonRpcCurrentRequest.Token <> nil;
      Result := TJSONNull.Create;
    end);
  // Ohne Scheduler läuft auch die nebenläufige Anfrage in DispatchMessage.
  FDispatcher.RegisterConcurrentRequest('concurrent',
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      ConcurrentSeen := (TJsonRpcCurrentRequest.Token as IInterface) = (ACancellation as IInterface);
      Result := TJSONNull.Create;
    end);
  DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":1,"method":"sync"}').Free;
  DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":2,"method":"concurrent"}').Free;
  Assert.IsTrue(SyncSeen, 'synchroner Handler');
  Assert.IsTrue(ConcurrentSeen, 'nebenläufiger Handler');
  Assert.IsTrue(TJsonRpcCurrentRequest.Token = nil, 'nach dem Handler');
end;

procedure TJsonRpcDispatcherTests.RunsConditionalRequestConcurrentlyWhenConditionHolds;
var
  Scheduling: TManualScheduling;
  Response: TJSONObject;
  Handler: TJsonRpcRequestHandler;
  When: TJsonRpcConcurrentWhen;
begin
  Handler :=
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := TJSONValue(AParams.Clone);
    end;
  When :=
    function(const AParams: TJSONValue): Boolean
    begin
      Result := (AParams is TJSONObject) and (TJSONObject(AParams).GetValue('fast') is TJSONBool) and
        TJSONBool(TJSONObject(AParams).GetValue('fast')).AsBoolean;
    end;
  FDispatcher.RegisterConditionalRequest('command', Handler, When);
  Scheduling := TManualScheduling.Create;
  try
    Scheduling.AttachTo(FDispatcher);
    // Bedingung erfüllt: über den Scheduler, Antwort über den Responder.
    Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":1,"method":"command","params":{"fast":true}}'));
    Assert.AreEqual(1, Integer(Scheduling.Work.Count));
    Scheduling.RunAll;
    Assert.AreEqual(1, Integer(Scheduling.Responses.Count));
    Assert.IsTrue(Scheduling.Responses[0].GetValue<Boolean>('result.fast'));
    // Nicht erfüllt: in der Reihenfolge, Antwort direkt.
    Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":2,"method":"command","params":{"fast":false}}');
    try
      Assert.IsNotNull(Response);
      Assert.AreEqual(2, Response.GetValue<Integer>('id'));
      Assert.AreEqual(0, Integer(Scheduling.Work.Count));
    finally
      Response.Free;
    end;
    // RegisterRequest ohne Bedingung nimmt sie wieder weg.
    FDispatcher.RegisterRequest('command',
      function(const AParams: TJSONValue): TJSONValue
      begin
        Result := nil;
      end);
    Response := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":3,"method":"command","params":{"fast":true}}');
    try
      Assert.IsNotNull(Response, 'ohne Bedingung seriell');
    finally
      Response.Free;
    end;
  finally
    Scheduling.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.ReportsQueueTimeToObserver;
var
  Observer: TQueueObserver;
  Keep: IJsonRpcRequestObserver;
  Message, Response: TJSONObject;
  Scheduling: TManualScheduling;
begin
  Observer := TQueueObserver.Create;
  Keep := Observer;
  FDispatcher.Observer := Keep;
  Message := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","id":1,"method":"echo","params":1}');
  try
    Response := FDispatcher.DispatchMessage(Message, 250);
    Response.Free;
  finally
    Message.Free;
  end;
  Assert.AreEqual<Int64>(250, Observer.QueueMs, 'seriell: Wartezeit im Posteingang');
  RegisterConcurrentEcho(FDispatcher);
  Scheduling := TManualScheduling.Create;
  try
    Scheduling.AttachTo(FDispatcher);
    Message := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","id":2,"method":"parallel","params":2}');
    try
      Assert.IsNull(FDispatcher.DispatchMessage(Message, 400));
    finally
      Message.Free;
    end;
    Scheduling.RunAll;
    Assert.IsTrue(Observer.QueueMs >= 400, 'nebenläufig: Posteingang und Warteschlange');
  finally
    Scheduling.Free;
  end;
  FDispatcher.Observer := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcDispatcherTests);

end.
