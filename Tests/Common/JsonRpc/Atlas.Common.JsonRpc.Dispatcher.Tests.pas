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
    /// <summary>TJsonRpcCurrentRequest gilt für die Dauer jedes Handlers.</summary>
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
    /// <summary>#1355: RequestGuard sieht Methode und Parameter und weist die Anfrage mit seinem Code ab, ohne den
    /// Handler.</summary>
    [Test]
    procedure RequestGuardRejectsWithParams;
    /// <summary>#1355: Recent bekommt jede eingehende Nachricht, auch Benachrichtigungen.</summary>
    [Test]
    procedure RecentGetsEveryMessage;
    /// <summary>#1355: Ein Stapelüberlauf im Handler stellt die Schutzseite wieder her, bevor geantwortet
    /// wird.</summary>
    [Test]
    procedure OverflowInHandlerRestoresGuardPage;
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
  Atlas.Common.JsonRpc.RecentMessages,
  Atlas.Common.Diagnostics.StackGuard,
  Atlas.Common.JsonRpc.TestSupport;

type
  /// <summary>Gleichnamig zur veralteten RTL-Klasse (W1000): TStackGuard erkennt den Überlauf am Namen.</summary>
  EStackOverflow = class(Exception);

type
  ETestFailure = class(Exception);

function DispatchJson(ADispatcher: TJsonRpcDispatcher; const AJson: string): TJSONObject;
var
  mMessage: TJSONObject;
begin
  mMessage := TJsonRpcTestSupport.Parse(AJson);
  try
    Result := ADispatcher.DispatchMessage(mMessage);
  finally
    mMessage.Free;
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
  begin
    mWork();
  end;
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
  mResponse: TJSONObject;
begin
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":7,"method":"echo","params":{"a":1}}');
  try
    Assert.AreEqual('2.0', mResponse.GetValue<string>('jsonrpc'));
    Assert.AreEqual(7, mResponse.GetValue<Integer>('id'));
    Assert.AreEqual(1, mResponse.GetValue<Integer>('result.a'));
    Assert.IsNull(mResponse.GetValue('error'));
  finally
    mResponse.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.CopiesStringId;
var
  mResponse: TJSONObject;
begin
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":"abc","method":"echo","params":[]}');
  try
    Assert.AreEqual('abc', mResponse.GetValue<string>('id'));
  finally
    mResponse.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.SendsNilResultAsNull;
var
  mResponse: TJSONObject;
begin
  FDispatcher.RegisterRequest('nothing',
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := nil;
    end);
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":1,"method":"nothing"}');
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONNull);
  finally
    mResponse.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.AnswersUnknownRequestWithMethodNotFound;
var
  mResponse: TJSONObject;
begin
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":3,"method":"gibtsnicht"}');
  try
    Assert.AreEqual(3, mResponse.GetValue<Integer>('id'));
    Assert.AreEqual(TJsonRpcErrorCode.cMethodNotFound, mResponse.GetValue<Integer>('error.code'));
    Assert.IsNull(mResponse.GetValue('result'));
  finally
    mResponse.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.IgnoresUnknownNotification;
begin
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","method":"gibtsnicht"}'));
end;

procedure TJsonRpcDispatcherTests.CallsNotificationHandlerWithoutResponse;
var
  mReceived: string;
begin
  FDispatcher.RegisterNotification('note',
    procedure(const AParams: TJSONValue)
    begin
      mReceived := AParams.GetValue<string>('text');
    end);
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","method":"note","params":{"text":"hallo"}}'));
  Assert.AreEqual('hallo', mReceived);
end;

procedure TJsonRpcDispatcherTests.AnswersJsonRpcErrorWithItsCode;
var
  mResponse: TJSONObject;
begin
  FDispatcher.RegisterRequest('strict',
    function(const AParams: TJSONValue): TJSONValue
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, 'Parameter fehlen');
    end);
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":4,"method":"strict"}');
  try
    Assert.AreEqual(TJsonRpcErrorCode.cInvalidParams, mResponse.GetValue<Integer>('error.code'));
    Assert.AreEqual('Parameter fehlen', mResponse.GetValue<string>('error.message'));
  finally
    mResponse.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.AnswersOtherExceptionWithInternalError;
var
  mResponse: TJSONObject;
begin
  FDispatcher.RegisterRequest('broken',
    function(const AParams: TJSONValue): TJSONValue
    begin
      raise ETestFailure.Create('kaputt');
    end);
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":5,"method":"broken"}');
  try
    Assert.AreEqual(TJsonRpcErrorCode.cInternalError, mResponse.GetValue<Integer>('error.code'));
    Assert.Contains(mResponse.GetValue<string>('error.message'), 'kaputt');
  finally
    mResponse.Free;
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
  mResponse: TJSONObject;
begin
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":6}');
  try
    Assert.AreEqual(TJsonRpcErrorCode.cInvalidRequest, mResponse.GetValue<Integer>('error.code'));
  finally
    mResponse.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.IgnoresResponsesFromClient;
begin
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":1,"result":null}'));
end;

procedure TJsonRpcDispatcherTests.RoutesExpectedResponseOnce;
var
  mCalls: Integer;
  mApplied: Boolean;
begin
  // #397: Antwort des Clients auf workspace/applyEdit geht einmal an den angemeldeten Handler.
  mCalls := 0;
  mApplied := False;
  FDispatcher.ExpectResponse('atlas/applyEdit/1',
    procedure(const AResponse: TJSONObject)
    begin
      Inc(mCalls);
      mApplied := AResponse.GetValue<Boolean>('result.applied');
    end);
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":"atlas/applyEdit/1","result":{"applied":true}}'));
  Assert.AreEqual(1, mCalls);
  Assert.IsTrue(mApplied);
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":"atlas/applyEdit/1","result":{"applied":true}}'));
  Assert.AreEqual(1, mCalls);
  // Zurückgegebene Anmeldung: kein Aufruf.
  FDispatcher.ExpectResponse('7',
    procedure(const AResponse: TJSONObject)
    begin
      Inc(mCalls);
    end);
  FDispatcher.ForgetResponse('7');
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":7,"error":{"code":-1,"message":"x"}}'));
  Assert.AreEqual(1, mCalls);
end;

procedure TJsonRpcDispatcherTests.GuardRejectsRequestWithItsCode;
var
  mResponse: TJSONObject;
begin
  FDispatcher.Guard :=
    procedure(const AMethod: string; AIsRequest: Boolean)
    begin
      raise EJsonRpcError.Create(-32002, 'nicht bereit');
    end;
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":8,"method":"echo","params":{}}');
  try
    Assert.AreEqual(-32002, mResponse.GetValue<Integer>('error.code'));
  finally
    mResponse.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.GuardDropsNotification;
var
  mCalled: Boolean;
begin
  mCalled := False;
  FDispatcher.RegisterNotification('note',
    procedure(const AParams: TJSONValue)
    begin
      mCalled := True;
    end);
  FDispatcher.Guard :=
    procedure(const AMethod: string; AIsRequest: Boolean)
    begin
      raise EJsonRpcError.Create(-32002, 'nicht bereit');
    end;
  Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","method":"note"}'));
  Assert.IsFalse(mCalled);
end;

procedure TJsonRpcDispatcherTests.RunsConcurrentRequestDirectlyWithoutScheduler;
var
  mResponse: TJSONObject;
begin
  RegisterConcurrentEcho(FDispatcher);
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":1,"method":"parallel","params":"direkt"}');
  try
    Assert.AreEqual('direkt', mResponse.GetValue<string>('result'));
  finally
    mResponse.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.SchedulesConcurrentRequestAndAnswersViaResponder;
var
  mScheduling: TManualScheduling;
begin
  RegisterConcurrentEcho(FDispatcher);
  mScheduling := TManualScheduling.Create;
  try
    mScheduling.AttachTo(FDispatcher);
    Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":5,"method":"parallel","params":"später"}'));
    Assert.AreEqual<NativeInt>(1, mScheduling.Work.Count);
    Assert.AreEqual<NativeInt>(0, mScheduling.Responses.Count);

    mScheduling.RunAll;
    Assert.AreEqual<NativeInt>(1, mScheduling.Responses.Count);
    Assert.AreEqual(5, mScheduling.Responses[0].GetValue<Integer>('id'));
    Assert.AreEqual('später', mScheduling.Responses[0].GetValue<string>('result'));
  finally
    mScheduling.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.AnswersCancelledConcurrentRequestWithRequestCancelled;
var
  mScheduling: TManualScheduling;
  mHandlerCalled: Boolean;
begin
  mHandlerCalled := False;
  FDispatcher.RegisterConcurrentRequest('parallel',
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      mHandlerCalled := True;
      Result := nil;
    end);
  mScheduling := TManualScheduling.Create;
  try
    mScheduling.AttachTo(FDispatcher);
    Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":"a","method":"parallel"}'));
    Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":"a"}}'));

    mScheduling.RunAll;
    Assert.IsFalse(mHandlerCalled);
    Assert.AreEqual<NativeInt>(1, mScheduling.Responses.Count);
    Assert.AreEqual('a', mScheduling.Responses[0].GetValue<string>('id'));
    Assert.AreEqual(TJsonRpcErrorCode.cRequestCancelled, mScheduling.Responses[0].GetValue<Integer>('error.code'));
  finally
    mScheduling.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.AnswersRequestCancelledWhileQueued;
var
  mRequest: TJSONObject;
  mCancel: TJSONObject;
  mResponse: TJSONObject;
begin
  // So sieht es der Lese-Thread: Anfrage und Abbruch kommen an, bevor die
  // Nachrichtenschleife die Anfrage verarbeitet.
  mRequest := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","id":9,"method":"echo","params":1}');
  mCancel := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":9}}');
  try
    Assert.IsFalse(FDispatcher.PendingRequests.Observe(mRequest));
    Assert.IsTrue(FDispatcher.PendingRequests.Observe(mCancel));
    mResponse := FDispatcher.DispatchMessage(mRequest);
    try
      Assert.AreEqual(9, mResponse.GetValue<Integer>('id'));
      Assert.AreEqual(TJsonRpcErrorCode.cRequestCancelled, mResponse.GetValue<Integer>('error.code'));
    finally
      mResponse.Free;
    end;

    // Dieselbe id später erneut: nicht mehr abgebrochen.
    mResponse := FDispatcher.DispatchMessage(mRequest);
    try
      Assert.AreEqual(1, mResponse.GetValue<Integer>('result'));
    finally
      mResponse.Free;
    end;
  finally
    mCancel.Free;
    mRequest.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.WaitForWorkCoversScheduledRequests;
var
  mScheduling: TManualScheduling;
begin
  RegisterConcurrentEcho(FDispatcher);
  mScheduling := TManualScheduling.Create;
  try
    mScheduling.AttachTo(FDispatcher);
    Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":1,"method":"parallel","params":1}'));
    Assert.IsFalse(FDispatcher.PendingRequests.WaitForWork(0));
    mScheduling.RunAll;
    Assert.IsTrue(FDispatcher.PendingRequests.WaitForWork(0));
  finally
    mScheduling.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.ReportsUnexpectedErrorsToOnRequestFailed;
var
  mReported: string;
  mResponse: TJSONObject;
begin
  mReported := '';
  FDispatcher.OnRequestFailed :=
    procedure(const AMethod: string; const AParams: TJSONValue; const AError: Exception)
    begin
      mReported := AMethod + '|' + AParams.ToJSON + '|' + AError.Message;
    end;
  FDispatcher.RegisterRequest('broken',
    function(const AParams: TJSONValue): TJSONValue
    begin
      raise ETestFailure.Create('kaputt');
    end);
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":5,"method":"broken","params":{"a":1}}');
  mResponse.Free;
  Assert.AreEqual('broken|{"a":1}|kaputt', mReported);
end;

procedure TJsonRpcDispatcherTests.DoesNotReportJsonRpcErrors;
var
  mReported: Boolean;
  mResponse: TJSONObject;
begin
  mReported := False;
  FDispatcher.OnRequestFailed :=
    procedure(const AMethod: string; const AParams: TJSONValue; const AError: Exception)
    begin
      mReported := True;
    end;
  FDispatcher.RegisterRequest('invalid',
    function(const AParams: TJSONValue): TJSONValue
    begin
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, 'falsch');
    end);
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":6,"method":"invalid"}');
  mResponse.Free;
  Assert.IsFalse(mReported);
end;

procedure TJsonRpcDispatcherTests.RemembersLastMessage;
var
  mResponse: TJSONObject;
begin
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":7,"method":"unbekannt"}');
  mResponse.Free;
  Assert.AreEqual('unbekannt (id 7)', FDispatcher.LastMessage);
  DispatchJson(FDispatcher, '{"jsonrpc":"2.0","method":"hinweis"}').Free;
  Assert.AreEqual('hinweis', FDispatcher.LastMessage);
end;

procedure TJsonRpcDispatcherTests.WatchdogCancelsLongRunningRequest;
var
  mTimedOut: string;
  mResponse: TJSONObject;
begin
  mTimedOut := '';
  FDispatcher.Watchdog := TJsonRpcWatchdog.Create(FDispatcher.PendingRequests, 50,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      mTimedOut := AMethod;
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
    mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":8,"method":"slow"}');
    try
      Assert.AreEqual(TJsonRpcErrorCode.cRequestCancelled, mResponse.GetValue<Integer>('error.code'));
      Assert.AreEqual('slow', mTimedOut);
    finally
      mResponse.Free;
    end;
  finally
    FDispatcher.Watchdog := nil;
  end;
end;

procedure TJsonRpcDispatcherTests.CurrentRequestIsSetDuringHandler;
var
  mSyncSeen, mConcurrentSeen: Boolean;
begin
  mSyncSeen := False;
  mConcurrentSeen := False;
  FDispatcher.RegisterRequest('sync',
    function(const AParams: TJSONValue): TJSONValue
    begin
      mSyncSeen := TJsonRpcCurrentRequest.Token <> nil;
      Result := TJSONNull.Create;
    end);
  // Ohne Scheduler läuft auch die nebenläufige Anfrage in DispatchMessage.
  FDispatcher.RegisterConcurrentRequest('concurrent',
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      mConcurrentSeen := (TJsonRpcCurrentRequest.Token as IInterface) = (ACancellation as IInterface);
      Result := TJSONNull.Create;
    end);
  DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":1,"method":"sync"}').Free;
  DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":2,"method":"concurrent"}').Free;
  Assert.IsTrue(mSyncSeen, 'synchroner Handler');
  Assert.IsTrue(mConcurrentSeen, 'nebenläufiger Handler');
  Assert.IsNull(TJsonRpcCurrentRequest.Token, 'nach dem Handler');
end;

procedure TJsonRpcDispatcherTests.RunsConditionalRequestConcurrentlyWhenConditionHolds;
var
  mScheduling: TManualScheduling;
  mResponse: TJSONObject;
  mHandler: TJsonRpcRequestHandler;
  mWhen: TJsonRpcConcurrentWhen;
begin
  mHandler :=
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := TJSONValue(AParams.Clone);
    end;
  mWhen :=
    function(const AParams: TJSONValue): Boolean
    begin
      Result := (AParams is TJSONObject) and (TJSONObject(AParams).GetValue('fast') is TJSONBool) and
        TJSONBool(TJSONObject(AParams).GetValue('fast')).AsBoolean;
    end;
  FDispatcher.RegisterConditionalRequest('command', mHandler, mWhen);
  mScheduling := TManualScheduling.Create;
  try
    mScheduling.AttachTo(FDispatcher);
    // Bedingung erfüllt: über den Scheduler, Antwort über den Responder.
    Assert.IsNull(DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":1,"method":"command","params":{"fast":true}}'));
    Assert.AreEqual(1, Integer(mScheduling.Work.Count));
    mScheduling.RunAll;
    Assert.AreEqual(1, Integer(mScheduling.Responses.Count));
    Assert.IsTrue(mScheduling.Responses[0].GetValue<Boolean>('result.fast'));
    // Nicht erfüllt: in der Reihenfolge, Antwort direkt.
    mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":2,"method":"command","params":{"fast":false}}');
    try
      Assert.IsNotNull(mResponse);
      Assert.AreEqual(2, mResponse.GetValue<Integer>('id'));
      Assert.AreEqual(0, Integer(mScheduling.Work.Count));
    finally
      mResponse.Free;
    end;
    // RegisterRequest ohne Bedingung nimmt sie wieder weg.
    FDispatcher.RegisterRequest('command',
      function(const AParams: TJSONValue): TJSONValue
      begin
        Result := nil;
      end);
    mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":3,"method":"command","params":{"fast":true}}');
    try
      Assert.IsNotNull(mResponse, 'ohne Bedingung seriell');
    finally
      mResponse.Free;
    end;
  finally
    mScheduling.Free;
  end;
end;

procedure TJsonRpcDispatcherTests.ReportsQueueTimeToObserver;
var
  mObserver: TQueueObserver;
  mKeep: IJsonRpcRequestObserver;
  mMessage, mResponse: TJSONObject;
  mScheduling: TManualScheduling;
begin
  mObserver := TQueueObserver.Create;
  mKeep := mObserver;
  FDispatcher.Observer := mKeep;
  mMessage := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","id":1,"method":"echo","params":1}');
  try
    mResponse := FDispatcher.DispatchMessage(mMessage, 250);
    mResponse.Free;
  finally
    mMessage.Free;
  end;
  Assert.AreEqual<Int64>(250, mObserver.QueueMs, 'seriell: Wartezeit im Posteingang');
  RegisterConcurrentEcho(FDispatcher);
  mScheduling := TManualScheduling.Create;
  try
    mScheduling.AttachTo(FDispatcher);
    mMessage := TJsonRpcTestSupport.Parse('{"jsonrpc":"2.0","id":2,"method":"parallel","params":2}');
    try
      Assert.IsNull(FDispatcher.DispatchMessage(mMessage, 400));
    finally
      mMessage.Free;
    end;
    mScheduling.RunAll;
    Assert.IsTrue(mObserver.QueueMs >= 400, 'nebenläufig: Posteingang und Warteschlange');
  finally
    mScheduling.Free;
  end;
  FDispatcher.Observer := nil;
end;

procedure TJsonRpcDispatcherTests.RequestGuardRejectsWithParams;
var
  mResponse: TJSONObject;
  mCalled: Boolean;
  mSeen: string;
  mCode: Integer;
begin
  mCalled := False;
  mSeen := '';
  FDispatcher.RegisterRequest('probe',
    function(const AParams: TJSONValue): TJSONValue
    begin
      mCalled := True;
      Result := TJSONNull.Create;
    end);
  FDispatcher.RequestGuard :=
    procedure(const AMethod: string; const AParams: TJSONValue)
    begin
      mSeen := AMethod + ' ' + AParams.ToJSON;
      raise EJsonRpcError.Create(TJsonRpcErrorCode.cRequestFailed, 'übersprungen');
    end;
  mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":3,"method":"probe","params":{"a":1}}');
  try
    mCode := mResponse.GetValue<Integer>('error.code');
    Assert.AreEqual(TJsonRpcErrorCode.cRequestFailed, mCode);
    Assert.IsFalse(mCalled);
    Assert.AreEqual('probe {"a":1}', mSeen);
  finally
    mResponse.Free;
  end;
  FDispatcher.RequestGuard := nil;
end;

procedure TJsonRpcDispatcherTests.RecentGetsEveryMessage;
var
  mRecent: IJsonRpcRecentMessages;
  mLast: TArray<string>;
  mMethod, mParams: string;
begin
  mRecent := TJsonRpcRecentMessages.Create;
  FDispatcher.Recent := mRecent;
  DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":4,"method":"echo","params":{"x":2}}').Free;
  DispatchJson(FDispatcher, '{"jsonrpc":"2.0","method":"unknown/note"}').Free;
  mLast := mRecent.Last(5);
  Assert.AreEqual(2, Integer(Length(mLast)));
  Assert.IsTrue(mLast[0].Contains('"echo"'));
  Assert.IsTrue(mLast[1].Contains('unknown/note'));
  Assert.IsTrue(mRecent.FindRequest('4', mMethod, mParams));
  Assert.AreEqual('echo', mMethod);
  Assert.AreEqual('{"x":2}', mParams);
  FDispatcher.Recent := nil;
end;

procedure TJsonRpcDispatcherTests.OverflowInHandlerRestoresGuardPage;
var
  mRestored, mCode: Integer;
  mResponse: TJSONObject;
begin
  mRestored := 0;
  TStackGuard.Restore :=
    procedure
    begin
      Inc(mRestored);
    end;
  try
    FDispatcher.RegisterRequest('deep',
      function(const AParams: TJSONValue): TJSONValue
      begin
        raise EStackOverflow.Create('Stapel');
      end);
    mResponse := DispatchJson(FDispatcher, '{"jsonrpc":"2.0","id":5,"method":"deep"}');
    try
      mCode := mResponse.GetValue<Integer>('error.code');
      Assert.AreEqual(TJsonRpcErrorCode.cInternalError, mCode);
    finally
      mResponse.Free;
    end;
    Assert.AreEqual(1, mRestored);
  finally
    TStackGuard.Restore := nil;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcDispatcherTests);

end.
