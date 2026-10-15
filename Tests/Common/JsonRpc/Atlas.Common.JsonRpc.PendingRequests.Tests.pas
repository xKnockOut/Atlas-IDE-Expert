unit Atlas.Common.JsonRpc.PendingRequests.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcPendingRequestsTests = class
  public
    [Test]
    procedure CancelMarksAcquiredToken;
    [Test]
    procedure ObserveTracksRequestAndExecutesCancelRequest;
    [Test]
    procedure ObservePassesOtherMessagesOn;
    [Test]
    procedure IgnoresCancelForReleasedRequest;
    [Test]
    procedure DistinguishesNumberAndStringIds;
    [Test]
    procedure CancelAllCancelsEveryOpenRequest;
    [Test]
    procedure ThrowIfCancellationRequestedRaisesRequestCancelled;
    [Test]
    procedure WaitForWorkWaitsUntilWorkEnds;
    [Test]
    procedure ChangeOfDocumentRaisesContentModified;
    [Test]
    procedure ChangeOfOtherDocumentKeepsRequest;
    [Test]
    procedure ChangeWithoutRegisteredMethodKeepsRequest;
    /// <summary>Code-Review A-06: genau eine Antwort je Anfrage (Worker oder Watchdog).</summary>
    [Test]
    procedure ExpireClaimsAnswerOnce;
    [Test]
    procedure TryAnswerAcceptsForeignToken;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.PendingRequests,
  Atlas.Common.JsonRpc.TestSupport;

function Observe(const APending: IJsonRpcPendingRequests; const AJson: string): Boolean;
var
  Message: TJSONObject;
begin
  Message := TJsonRpcTestSupport.Parse(AJson);
  try
    Result := APending.Observe(Message);
  finally
    Message.Free;
  end;
end;

function AcquireJson(const APending: IJsonRpcPendingRequests; const AIdJson: string): IJsonRpcCancellationToken;
var
  Id: TJSONValue;
begin
  Id := TJSONValue.ParseJSONValue(AIdJson);
  try
    Result := APending.Acquire(Id);
  finally
    Id.Free;
  end;
end;

procedure CancelJson(const APending: IJsonRpcPendingRequests; const AIdJson: string);
var
  Id: TJSONValue;
begin
  Id := TJSONValue.ParseJSONValue(AIdJson);
  try
    APending.Cancel(Id);
  finally
    Id.Free;
  end;
end;

procedure ReleaseJson(const APending: IJsonRpcPendingRequests; const AIdJson: string;
  const AToken: IJsonRpcCancellationToken);
var
  Id: TJSONValue;
begin
  Id := TJSONValue.ParseJSONValue(AIdJson);
  try
    APending.Release(Id, AToken);
  finally
    Id.Free;
  end;
end;

type
  /// <summary>Token einer fremden Implementierung ohne Antwortsperre.</summary>
  TForeignToken = class(TInterfacedObject, IJsonRpcCancellationToken)
  public
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
  end;

function TForeignToken.IsCancellationRequested: Boolean;
begin
  Result := False;
end;

procedure TForeignToken.ThrowIfCancellationRequested;
begin
  // Nie abgebrochen.
end;

{ TJsonRpcPendingRequestsTests }

procedure TJsonRpcPendingRequestsTests.CancelMarksAcquiredToken;
var
  Pending: IJsonRpcPendingRequests;
  Token: IJsonRpcCancellationToken;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Token := AcquireJson(Pending, '1');
  Assert.IsFalse(Token.IsCancellationRequested);
  CancelJson(Pending, '1');
  Assert.IsTrue(Token.IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.ObserveTracksRequestAndExecutesCancelRequest;
var
  Pending: IJsonRpcPendingRequests;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Assert.IsFalse(Observe(Pending, '{"jsonrpc":"2.0","id":7,"method":"langsam"}'));
  Assert.IsTrue(Observe(Pending, '{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":7}}'));
  Assert.IsTrue(AcquireJson(Pending, '7').IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.ObservePassesOtherMessagesOn;
var
  Pending: IJsonRpcPendingRequests;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Assert.IsFalse(Observe(Pending, '{"jsonrpc":"2.0","method":"textDocument/didChange"}'));
  Assert.IsFalse(Observe(Pending, '{"jsonrpc":"2.0","id":1,"result":null}'));
  // Ein Abbruch ohne gültige Parameter ist trotzdem erledigt.
  Assert.IsTrue(Observe(Pending, '{"jsonrpc":"2.0","method":"$/cancelRequest"}'));
end;

procedure TJsonRpcPendingRequestsTests.IgnoresCancelForReleasedRequest;
var
  Pending: IJsonRpcPendingRequests;
  Token: IJsonRpcCancellationToken;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Token := AcquireJson(Pending, '3');
  ReleaseJson(Pending, '3', Token);
  CancelJson(Pending, '3');
  Assert.IsFalse(Token.IsCancellationRequested);
  Assert.IsFalse(AcquireJson(Pending, '3').IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.DistinguishesNumberAndStringIds;
var
  Pending: IJsonRpcPendingRequests;
  NumberToken: IJsonRpcCancellationToken;
  StringToken: IJsonRpcCancellationToken;
begin
  Pending := TJsonRpcPendingRequests.Create;
  NumberToken := AcquireJson(Pending, '1');
  StringToken := AcquireJson(Pending, '"1"');
  CancelJson(Pending, '"1"');
  Assert.IsFalse(NumberToken.IsCancellationRequested);
  Assert.IsTrue(StringToken.IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.CancelAllCancelsEveryOpenRequest;
var
  Pending: IJsonRpcPendingRequests;
  First: IJsonRpcCancellationToken;
  Second: IJsonRpcCancellationToken;
begin
  Pending := TJsonRpcPendingRequests.Create;
  First := AcquireJson(Pending, '1');
  Second := AcquireJson(Pending, '"zwei"');
  Pending.CancelAll;
  Assert.IsTrue(First.IsCancellationRequested);
  Assert.IsTrue(Second.IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.ThrowIfCancellationRequestedRaisesRequestCancelled;
var
  Pending: IJsonRpcPendingRequests;
  Token: IJsonRpcCancellationToken;
  Code: Integer;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Token := AcquireJson(Pending, '1');
  Token.ThrowIfCancellationRequested;
  CancelJson(Pending, '1');
  Code := 0;
  try
    Token.ThrowIfCancellationRequested;
  except
    on E: EJsonRpcRequestCancelled do
      Code := E.Code;
  end;
  Assert.AreEqual(TJsonRpcErrorCode.RequestCancelled, Code);
end;

procedure TJsonRpcPendingRequestsTests.WaitForWorkWaitsUntilWorkEnds;
var
  Pending: IJsonRpcPendingRequests;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Assert.IsTrue(Pending.WaitForWork(0));
  Pending.BeginWork;
  Pending.BeginWork;
  Assert.IsFalse(Pending.WaitForWork(0));
  Pending.EndWork;
  Assert.IsFalse(Pending.WaitForWork(0));
  Pending.EndWork;
  Assert.IsTrue(Pending.WaitForWork(0));
end;

procedure TJsonRpcPendingRequestsTests.ChangeOfDocumentRaisesContentModified;
var
  Pending: IJsonRpcPendingRequests;
  Token: IJsonRpcCancellationToken;
  Code: Integer;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Pending.AddContentChangeMethod('textDocument/didChange');
  Observe(Pending, '{"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///a.pas"}}}');
  Token := AcquireJson(Pending, '4');
  Assert.IsFalse(Observe(Pending,
    '{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///a.pas"}}}'));
  Assert.IsTrue(Token.IsCancellationRequested);
  Code := 0;
  try
    Token.ThrowIfCancellationRequested;
  except
    on E: EJsonRpcError do
      Code := E.Code;
  end;
  Assert.AreEqual(TJsonRpcErrorCode.ContentModified, Code);
end;

procedure TJsonRpcPendingRequestsTests.ChangeOfOtherDocumentKeepsRequest;
var
  Pending: IJsonRpcPendingRequests;
  Token: IJsonRpcCancellationToken;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Pending.AddContentChangeMethod('textDocument/didChange');
  Observe(Pending, '{"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///a.pas"}}}');
  Token := AcquireJson(Pending, '4');
  Observe(Pending, '{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///b.pas"}}}');
  Assert.IsFalse(Token.IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.ChangeWithoutRegisteredMethodKeepsRequest;
var
  Pending: IJsonRpcPendingRequests;
  Token: IJsonRpcCancellationToken;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Observe(Pending, '{"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///a.pas"}}}');
  Token := AcquireJson(Pending, '4');
  Observe(Pending, '{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///a.pas"}}}');
  Assert.IsFalse(Token.IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.ExpireClaimsAnswerOnce;
var
  Pending: IJsonRpcPendingRequests;
  Token: IJsonRpcCancellationToken;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Token := AcquireJson(Pending, '1');
  Assert.IsTrue(Pending.Expire(Token));
  Assert.IsTrue(Token.IsCancellationRequested);
  Assert.IsFalse(Pending.TryAnswer(Token));
  Assert.IsFalse(Pending.Expire(Token));
  ReleaseJson(Pending, '1', Token);
end;

procedure TJsonRpcPendingRequestsTests.TryAnswerAcceptsForeignToken;
var
  Pending: IJsonRpcPendingRequests;
  Token: IJsonRpcCancellationToken;
begin
  Pending := TJsonRpcPendingRequests.Create;
  Token := TForeignToken.Create;
  Assert.IsTrue(Pending.TryAnswer(Token));
  Assert.IsTrue(Pending.TryAnswer(Token));
  Assert.IsFalse(Pending.Expire(Token));
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcPendingRequestsTests);

end.
