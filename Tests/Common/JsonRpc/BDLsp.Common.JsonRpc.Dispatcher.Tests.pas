unit BDLsp.Common.JsonRpc.Dispatcher.Tests;

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.JsonRpc.Dispatcher;

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
    procedure GuardRejectsRequestWithItsCode;
    [Test]
    procedure GuardDropsNotification;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.TestSupport;

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

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcDispatcherTests);

end.
