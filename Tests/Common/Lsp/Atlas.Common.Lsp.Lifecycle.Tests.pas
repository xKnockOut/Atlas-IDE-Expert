unit Atlas.Common.Lsp.Lifecycle.Tests;

interface

uses
  System.JSON,
  DUnitX.TestFramework,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Lsp.Lifecycle;

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
  System.Generics.Collections,
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.JsonRpc.TestSupport;

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
      Result.AddPair('textDocumentSync', TJSONNumber.Create(TLspTextDocumentSyncKind.cIncremental));
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
  mMessage: TJSONObject;
begin
  mMessage := TJsonRpcTestSupport.Parse(AJson);
  try
    Result := FDispatcher.DispatchMessage(mMessage);
  finally
    mMessage.Free;
  end;
end;

procedure TLspLifecycleTests.InitializeServer;
begin
  Send('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"rootUri":"file:///C:/Projekt"}}').Free;
  Assert.IsNull(Send('{"jsonrpc":"2.0","method":"initialized","params":{}}'));
end;

procedure TLspLifecycleTests.InitializeReturnsCapabilitiesAndServerInfo;
var
  mResponse: TJSONObject;
begin
  mResponse := Send('{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"capabilities":{}}}');
  try
    Assert.AreEqual(1, mResponse.GetValue<Integer>('id'));
    Assert.AreEqual(TLspTextDocumentSyncKind.cIncremental,
      mResponse.GetValue<Integer>('result.capabilities.textDocumentSync'));
    Assert.AreEqual('TestServer', mResponse.GetValue<string>('result.serverInfo.name'));
    Assert.AreEqual('1.2.3', mResponse.GetValue<string>('result.serverInfo.version'));
    Assert.AreEqual<TLspServerState>(TLspServerState.Running, FLifecycle.State);
  finally
    mResponse.Free;
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
  mResponse: TJSONObject;
begin
  mResponse := Send('{"jsonrpc":"2.0","id":2,"method":"test/request"}');
  try
    Assert.AreEqual(TLspErrorCode.cServerNotInitialized, mResponse.GetValue<Integer>('error.code'));
  finally
    mResponse.Free;
  end;
end;

procedure TLspLifecycleTests.DropsNotificationBeforeInitialize;
begin
  Assert.IsNull(Send('{"jsonrpc":"2.0","method":"test/notification"}'));
  Assert.IsFalse(FNotificationReceived);
end;

procedure TLspLifecycleTests.AcceptsRequestsAfterInitialize;
var
  mResponse: TJSONObject;
begin
  InitializeServer;
  mResponse := Send('{"jsonrpc":"2.0","id":2,"method":"test/request"}');
  try
    Assert.IsTrue(mResponse.GetValue<Boolean>('result'));
  finally
    mResponse.Free;
  end;
  Send('{"jsonrpc":"2.0","method":"test/notification"}').Free;
  Assert.IsTrue(FNotificationReceived);
end;

procedure TLspLifecycleTests.RejectsSecondInitialize;
var
  mResponse: TJSONObject;
begin
  InitializeServer;
  mResponse := Send('{"jsonrpc":"2.0","id":2,"method":"initialize","params":{}}');
  try
    Assert.AreEqual(TJsonRpcErrorCode.cInvalidRequest, mResponse.GetValue<Integer>('error.code'));
  finally
    mResponse.Free;
  end;
end;

procedure TLspLifecycleTests.ShutdownReturnsNullAndRejectsFurtherRequests;
var
  mResponse: TJSONObject;
begin
  InitializeServer;
  mResponse := Send('{"jsonrpc":"2.0","id":2,"method":"shutdown"}');
  try
    Assert.IsTrue(mResponse.GetValue('result') is TJSONNull);
    Assert.AreEqual<TLspServerState>(TLspServerState.ShuttingDown, FLifecycle.State);
  finally
    mResponse.Free;
  end;

  mResponse := Send('{"jsonrpc":"2.0","id":3,"method":"test/request"}');
  try
    Assert.AreEqual(TJsonRpcErrorCode.cInvalidRequest, mResponse.GetValue<Integer>('error.code'));
  finally
    mResponse.Free;
  end;
end;

procedure TLspLifecycleTests.ExitAfterShutdownGivesExitCodeZero;
begin
  InitializeServer;
  Send('{"jsonrpc":"2.0","id":2,"method":"shutdown"}').Free;
  Assert.IsNull(Send('{"jsonrpc":"2.0","method":"exit"}'));
  Assert.IsTrue(FExitCalled);
  Assert.AreEqual<TLspServerState>(TLspServerState.Exited, FLifecycle.State);
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
