unit Argus.Common.Lsp.Lifecycle.Tests;

interface

uses
  System.JSON,
  DUnitX.TestFramework,
  Argus.Common.JsonRpc.Dispatcher,
  Argus.Common.Lsp.Lifecycle;

type
  [TestFixture]
  TLspLifecycleTests = class
  private
    FDispatcher: TJsonRpcDispatcher;
    FLifecycle: TLspLifecycle;
    FExitCalled: Boolean;
    FNotificationReceived: Boolean;
    function Send(const AJson: string): TJSONObject;
    procedure InitializeServer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure InitializeReturnsCapabilitiesAndServerInfo;
    [Test]
    procedure InitializeKeepsClientParams;
    [Test]
    procedure RejectsRequestBeforeInitialize;
    [Test]
    procedure DropsNotificationBeforeInitialize;
    [Test]
    procedure AcceptsRequestsAfterInitialize;
    [Test]
    procedure RejectsSecondInitialize;
    [Test]
    procedure ShutdownReturnsNullAndRejectsFurtherRequests;
    [Test]
    procedure ExitAfterShutdownGivesExitCodeZero;
    [Test]
    procedure ExitWithoutShutdownGivesExitCodeOne;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.JsonRpc.Contract,
  Argus.Common.Lsp.Contract,
  Argus.Common.JsonRpc.TestSupport;

{ TLspLifecycleTests }

procedure TLspLifecycleTests.Setup;
begin
  FExitCalled := False;
  FNotificationReceived := False;
  FDispatcher := TJsonRpcDispatcher.Create;
  FLifecycle := TLspLifecycle.Create('TestServer', '1.2.3',
    function: TJSONObject
    begin
      Result := TJSONObject.Create;
      Result.AddPair('textDocumentSync', TJSONNumber.Create(TLspTextDocumentSyncKind.Incremental));
    end);
  FLifecycle.OnExit :=
    procedure
    begin
      FExitCalled := True;
    end;
  FLifecycle.Attach(FDispatcher);
  FDispatcher.RegisterRequest('test/request',
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := TJSONTrue.Create;
    end);
  FDispatcher.RegisterNotification('test/notification',
    procedure(const AParams: TJSONValue)
    begin
      FNotificationReceived := True;
    end);
end;

procedure TLspLifecycleTests.TearDown;
begin
  FreeAndNil(FLifecycle);
  FreeAndNil(FDispatcher);
end;

function TLspLifecycleTests.Send(const AJson: string): TJSONObject;
var
  Message: TJSONObject;
begin
  Message := TJsonRpcTestSupport.Parse(AJson);
  try
    Result := FDispatcher.DispatchMessage(Message);
  finally
    Message.Free;
  end;
end;

procedure TLspLifecycleTests.InitializeServer;
begin
  Send('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"rootUri":"file:///C:/Projekt"}}').Free;
  Assert.IsNull(Send('{"jsonrpc":"2.0","method":"initialized","params":{}}'));
end;

procedure TLspLifecycleTests.InitializeReturnsCapabilitiesAndServerInfo;
var
  Response: TJSONObject;
begin
  Response := Send('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}');
  try
    Assert.AreEqual(1, Response.GetValue<Integer>('id'));
    Assert.AreEqual(TLspTextDocumentSyncKind.Incremental,
      Response.GetValue<Integer>('result.capabilities.textDocumentSync'));
    Assert.AreEqual('TestServer', Response.GetValue<string>('result.serverInfo.name'));
    Assert.AreEqual('1.2.3', Response.GetValue<string>('result.serverInfo.version'));
    Assert.IsTrue(FLifecycle.State = TLspServerState.Running);
  finally
    Response.Free;
  end;
end;

procedure TLspLifecycleTests.InitializeKeepsClientParams;
begin
  Assert.IsNull(FLifecycle.InitializeParams);
  InitializeServer;
  Assert.AreEqual('file:///C:/Projekt', FLifecycle.InitializeParams.GetValue<string>('rootUri'));
end;

procedure TLspLifecycleTests.RejectsRequestBeforeInitialize;
var
  Response: TJSONObject;
begin
  Response := Send('{"jsonrpc":"2.0","id":2,"method":"test/request"}');
  try
    Assert.AreEqual(TLspErrorCode.ServerNotInitialized, Response.GetValue<Integer>('error.code'));
  finally
    Response.Free;
  end;
end;

procedure TLspLifecycleTests.DropsNotificationBeforeInitialize;
begin
  Assert.IsNull(Send('{"jsonrpc":"2.0","method":"test/notification"}'));
  Assert.IsFalse(FNotificationReceived);
end;

procedure TLspLifecycleTests.AcceptsRequestsAfterInitialize;
var
  Response: TJSONObject;
begin
  InitializeServer;
  Response := Send('{"jsonrpc":"2.0","id":2,"method":"test/request"}');
  try
    Assert.IsTrue(Response.GetValue<Boolean>('result'));
  finally
    Response.Free;
  end;
  Send('{"jsonrpc":"2.0","method":"test/notification"}').Free;
  Assert.IsTrue(FNotificationReceived);
end;

procedure TLspLifecycleTests.RejectsSecondInitialize;
var
  Response: TJSONObject;
begin
  InitializeServer;
  Response := Send('{"jsonrpc":"2.0","id":2,"method":"initialize","params":{}}');
  try
    Assert.AreEqual(TJsonRpcErrorCode.InvalidRequest, Response.GetValue<Integer>('error.code'));
  finally
    Response.Free;
  end;
end;

procedure TLspLifecycleTests.ShutdownReturnsNullAndRejectsFurtherRequests;
var
  Response: TJSONObject;
begin
  InitializeServer;
  Response := Send('{"jsonrpc":"2.0","id":2,"method":"shutdown"}');
  try
    Assert.IsTrue(Response.GetValue('result') is TJSONNull);
    Assert.IsTrue(FLifecycle.State = TLspServerState.ShuttingDown);
  finally
    Response.Free;
  end;

  Response := Send('{"jsonrpc":"2.0","id":3,"method":"test/request"}');
  try
    Assert.AreEqual(TJsonRpcErrorCode.InvalidRequest, Response.GetValue<Integer>('error.code'));
  finally
    Response.Free;
  end;
end;

procedure TLspLifecycleTests.ExitAfterShutdownGivesExitCodeZero;
begin
  InitializeServer;
  Send('{"jsonrpc":"2.0","id":2,"method":"shutdown"}').Free;
  Assert.IsNull(Send('{"jsonrpc":"2.0","method":"exit"}'));
  Assert.IsTrue(FExitCalled);
  Assert.IsTrue(FLifecycle.State = TLspServerState.Exited);
  Assert.AreEqual(0, FLifecycle.ExitCode);
end;

procedure TLspLifecycleTests.ExitWithoutShutdownGivesExitCodeOne;
begin
  InitializeServer;
  Assert.IsNull(Send('{"jsonrpc":"2.0","method":"exit"}'));
  Assert.IsTrue(FExitCalled);
  Assert.AreEqual(1, FLifecycle.ExitCode);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspLifecycleTests);

end.
