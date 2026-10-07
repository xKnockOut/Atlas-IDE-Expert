unit BDLsp.Common.JsonRpc.Connection.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher,
  BDLsp.Common.JsonRpc.Connection,
  BDLsp.Common.JsonRpc.StreamTransport,
  BDLsp.Common.JsonRpc.TestSupport;

type
  ETestFailure = class(Exception);

// Lässt eine Verbindung über die gegebenen Nachrichten laufen und liefert die Antworten.
function RunConnection(const AInput: array of string; ADispatcher: TJsonRpcDispatcher;
  const AConfigure: TProc<TJsonRpcConnection>): TObjectList<TJSONObject>;
var
  Input: TBytesStream;
  Output: TBytesStream;
  Connection: TJsonRpcConnection;
begin
  Input := TJsonRpcTestSupport.InputOf(AInput);
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

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcConnectionTests);

end.
