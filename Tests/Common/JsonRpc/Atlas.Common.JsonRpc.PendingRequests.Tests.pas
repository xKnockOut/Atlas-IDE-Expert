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
    procedure ObserveExecutesMcpCancelled;
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
    /// <summary>Genau eine Antwort je Anfrage (Worker oder Watchdog).</summary>
    [Test]
    procedure ExpireClaimsAnswerOnce;
    [Test]
    procedure TryAnswerAcceptsForeignToken;
    /// <summary>#1761: Nur das Zeitlimit lässt eine Arbeit zu Ende laufen; Abbruch und geändertes Dokument
    /// wiegen schwerer.</summary>
    [Test]
    procedure ExpireIsOnlyExpiredUntilCancelOrChange;
    /// <summary>TJsonRpcPastTimeout übergeht das bloße Zeitlimit, nicht den Abbruch.</summary>
    [Test]
    procedure PastTimeoutIgnoresOnlyExpiry;
    /// <summary>Abandoned: abgebrochen oder Dokument geändert, nicht das bloße Zeitlimit; unbekannte id nicht.
    /// </summary>
    [Test]
    procedure AbandonedOnlyAfterCancelOrChange;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.PendingRequests,
  Atlas.Common.JsonRpc.TestSupport;

function Observe(const APending: IJsonRpcPendingRequests; const AJson: string): Boolean;
var
  mMessage: TJSONObject;
begin
  mMessage := TJsonRpcTestSupport.Parse(AJson);
  try
    Result := APending.Observe(mMessage);
  finally
    mMessage.Free;
  end;
end;

function AcquireJson(const APending: IJsonRpcPendingRequests; const AIdJson: string): IJsonRpcCancellationToken;
var
  mId: TJSONValue;
begin
  mId := TJSONValue.ParseJSONValue(AIdJson);
  try
    Result := APending.Acquire(mId);
  finally
    mId.Free;
  end;
end;

procedure CancelJson(const APending: IJsonRpcPendingRequests; const AIdJson: string);
var
  mId: TJSONValue;
begin
  mId := TJSONValue.ParseJSONValue(AIdJson);
  try
    APending.Cancel(mId);
  finally
    mId.Free;
  end;
end;

procedure ReleaseJson(const APending: IJsonRpcPendingRequests; const AIdJson: string;
  const AToken: IJsonRpcCancellationToken);
var
  mId: TJSONValue;
begin
  mId := TJSONValue.ParseJSONValue(AIdJson);
  try
    APending.Release(mId, AToken);
  finally
    mId.Free;
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
  mPending: IJsonRpcPendingRequests;
  mToken: IJsonRpcCancellationToken;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mToken := AcquireJson(mPending, '1');
  Assert.IsFalse(mToken.IsCancellationRequested);
  CancelJson(mPending, '1');
  Assert.IsTrue(mToken.IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.ObserveTracksRequestAndExecutesCancelRequest;
var
  mPending: IJsonRpcPendingRequests;
begin
  mPending := TJsonRpcPendingRequests.Create;
  Assert.IsFalse(Observe(mPending, '{"jsonrpc":"2.0","id":7,"method":"langsam"}'));
  Assert.IsTrue(Observe(mPending, '{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":7}}'));
  Assert.IsTrue(AcquireJson(mPending, '7').IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.ObserveExecutesMcpCancelled;
var
  mPending: IJsonRpcPendingRequests;
begin
  // MCP bricht mit notifications/cancelled und params.requestId ab (#1117).
  mPending := TJsonRpcPendingRequests.Create;
  Assert.IsFalse(Observe(mPending, '{"jsonrpc":"2.0","id":"a1","method":"tools/call"}'));
  Assert.IsTrue(Observe(mPending, '{"jsonrpc":"2.0","method":"notifications/cancelled",' +
    '"params":{"requestId":"a1","reason":"Nutzer"}}'));
  Assert.IsTrue(AcquireJson(mPending, '"a1"').IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.ObservePassesOtherMessagesOn;
var
  mPending: IJsonRpcPendingRequests;
begin
  mPending := TJsonRpcPendingRequests.Create;
  Assert.IsFalse(Observe(mPending, '{"jsonrpc":"2.0","method":"textDocument/didChange"}'));
  Assert.IsFalse(Observe(mPending, '{"jsonrpc":"2.0","id":1,"result":null}'));
  // Ein Abbruch ohne gültige Parameter ist trotzdem erledigt.
  Assert.IsTrue(Observe(mPending, '{"jsonrpc":"2.0","method":"$/cancelRequest"}'));
end;

procedure TJsonRpcPendingRequestsTests.IgnoresCancelForReleasedRequest;
var
  mPending: IJsonRpcPendingRequests;
  mToken: IJsonRpcCancellationToken;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mToken := AcquireJson(mPending, '3');
  ReleaseJson(mPending, '3', mToken);
  CancelJson(mPending, '3');
  Assert.IsFalse(mToken.IsCancellationRequested);
  Assert.IsFalse(AcquireJson(mPending, '3').IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.DistinguishesNumberAndStringIds;
var
  mPending: IJsonRpcPendingRequests;
  mNumberToken: IJsonRpcCancellationToken;
  mStringToken: IJsonRpcCancellationToken;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mNumberToken := AcquireJson(mPending, '1');
  mStringToken := AcquireJson(mPending, '"1"');
  CancelJson(mPending, '"1"');
  Assert.IsFalse(mNumberToken.IsCancellationRequested);
  Assert.IsTrue(mStringToken.IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.CancelAllCancelsEveryOpenRequest;
var
  mPending: IJsonRpcPendingRequests;
  mFirst: IJsonRpcCancellationToken;
  mSecond: IJsonRpcCancellationToken;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mFirst := AcquireJson(mPending, '1');
  mSecond := AcquireJson(mPending, '"zwei"');
  mPending.CancelAll;
  Assert.IsTrue(mFirst.IsCancellationRequested);
  Assert.IsTrue(mSecond.IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.ThrowIfCancellationRequestedRaisesRequestCancelled;
var
  mPending: IJsonRpcPendingRequests;
  mToken: IJsonRpcCancellationToken;
  mCode: Integer;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mToken := AcquireJson(mPending, '1');
  mToken.ThrowIfCancellationRequested;
  CancelJson(mPending, '1');
  mCode := 0;
  try
    mToken.ThrowIfCancellationRequested;
  except
    on E: EJsonRpcRequestCancelled do
      mCode := E.Code;
  end;
  Assert.AreEqual(TJsonRpcErrorCode.cRequestCancelled, mCode);
end;

procedure TJsonRpcPendingRequestsTests.WaitForWorkWaitsUntilWorkEnds;
var
  mPending: IJsonRpcPendingRequests;
begin
  mPending := TJsonRpcPendingRequests.Create;
  Assert.IsTrue(mPending.WaitForWork(0));
  mPending.BeginWork;
  mPending.BeginWork;
  Assert.IsFalse(mPending.WaitForWork(0));
  mPending.EndWork;
  Assert.IsFalse(mPending.WaitForWork(0));
  mPending.EndWork;
  Assert.IsTrue(mPending.WaitForWork(0));
end;

procedure TJsonRpcPendingRequestsTests.ChangeOfDocumentRaisesContentModified;
var
  mPending: IJsonRpcPendingRequests;
  mToken: IJsonRpcCancellationToken;
  mCode: Integer;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mPending.AddContentChangeMethod('textDocument/didChange');
  Observe(mPending, '{"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///a.pas"}}}');
  mToken := AcquireJson(mPending, '4');
  Assert.IsFalse(Observe(mPending,
    '{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///a.pas"}}}'));
  Assert.IsTrue(mToken.IsCancellationRequested);
  mCode := 0;
  try
    mToken.ThrowIfCancellationRequested;
  except
    on E: EJsonRpcError do
      mCode := E.Code;
  end;
  Assert.AreEqual(TJsonRpcErrorCode.cContentModified, mCode);
end;

procedure TJsonRpcPendingRequestsTests.ChangeOfOtherDocumentKeepsRequest;
var
  mPending: IJsonRpcPendingRequests;
  mToken: IJsonRpcCancellationToken;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mPending.AddContentChangeMethod('textDocument/didChange');
  Observe(mPending, '{"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///a.pas"}}}');
  mToken := AcquireJson(mPending, '4');
  Observe(mPending, '{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///b.pas"}}}');
  Assert.IsFalse(mToken.IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.ChangeWithoutRegisteredMethodKeepsRequest;
var
  mPending: IJsonRpcPendingRequests;
  mToken: IJsonRpcCancellationToken;
begin
  mPending := TJsonRpcPendingRequests.Create;
  Observe(mPending, '{"jsonrpc":"2.0","id":4,"method":"textDocument/hover","params":{"textDocument":{"uri":"file:///a.pas"}}}');
  mToken := AcquireJson(mPending, '4');
  Observe(mPending, '{"jsonrpc":"2.0","method":"textDocument/didChange","params":{"textDocument":{"uri":"file:///a.pas"}}}');
  Assert.IsFalse(mToken.IsCancellationRequested);
end;

procedure TJsonRpcPendingRequestsTests.ExpireClaimsAnswerOnce;
var
  mPending: IJsonRpcPendingRequests;
  mToken: IJsonRpcCancellationToken;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mToken := AcquireJson(mPending, '1');
  Assert.IsTrue(mPending.Expire(mToken));
  Assert.IsTrue(mToken.IsCancellationRequested);
  Assert.IsFalse(mPending.TryAnswer(mToken));
  Assert.IsFalse(mPending.Expire(mToken));
  ReleaseJson(mPending, '1', mToken);
end;

procedure TJsonRpcPendingRequestsTests.TryAnswerAcceptsForeignToken;
var
  mPending: IJsonRpcPendingRequests;
  mToken: IJsonRpcCancellationToken;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mToken := TForeignToken.Create;
  Assert.IsTrue(mPending.TryAnswer(mToken));
  Assert.IsTrue(mPending.TryAnswer(mToken));
  Assert.IsFalse(mPending.Expire(mToken));
end;

procedure TJsonRpcPendingRequestsTests.ExpireIsOnlyExpiredUntilCancelOrChange;
var
  mExpired, mCancelled, mChanged: IJsonRpcCancellationSource;
  mCode: Integer;
begin
  mExpired := TJsonRpcCancellation.Create;
  Assert.IsFalse(mExpired.OnlyExpired);
  mExpired.Expire;
  Assert.IsTrue(mExpired.IsCancellationRequested);
  Assert.IsTrue(mExpired.OnlyExpired);
  Assert.WillRaise(
    procedure
    begin
      mExpired.ThrowIfCancellationRequested;
    end, EJsonRpcRequestCancelled);
  mCancelled := TJsonRpcCancellation.Create;
  mCancelled.Expire;
  mCancelled.Cancel;
  Assert.IsFalse(mCancelled.OnlyExpired, 'Abbruch nach dem Zeitlimit');
  mChanged := TJsonRpcCancellation.Create;
  mChanged.Expire;
  mChanged.CancelModified;
  Assert.IsFalse(mChanged.OnlyExpired, 'Dokument nach dem Zeitlimit geändert');
  mCode := 0;
  try
    mChanged.ThrowIfCancellationRequested;
  except
    on E: EJsonRpcContentModified do
      mCode := E.Code;
  end;
  Assert.AreEqual(TJsonRpcErrorCode.cContentModified, mCode);
end;

procedure TJsonRpcPendingRequestsTests.PastTimeoutIgnoresOnlyExpiry;
var
  mSource: IJsonRpcCancellationSource;
  mToken: IJsonRpcCancellationToken;
begin
  mSource := TJsonRpcCancellation.Create;
  mToken := TJsonRpcPastTimeout.Create(mSource);
  mSource.Expire;
  Assert.IsFalse(mToken.IsCancellationRequested, 'nur das Zeitlimit');
  mToken.ThrowIfCancellationRequested;
  mSource.Cancel;
  Assert.IsTrue(mToken.IsCancellationRequested, 'ausdrücklicher Abbruch');
  Assert.WillRaise(
    procedure
    begin
      mToken.ThrowIfCancellationRequested;
    end, EJsonRpcRequestCancelled);
  Assert.IsFalse((TJsonRpcPastTimeout.Create(nil) as IJsonRpcCancellationToken).IsCancellationRequested, 'ohne Anfrage');
end;

procedure TJsonRpcPendingRequestsTests.AbandonedOnlyAfterCancelOrChange;
var
  mPending: IJsonRpcPendingRequests;
  mId: TJSONValue;
  mToken: IJsonRpcCancellationToken;
begin
  mPending := TJsonRpcPendingRequests.Create;
  mId := TJSONNumber.Create(5);
  try
    Assert.IsFalse(mPending.Abandoned(mId), 'unbekannt');
    mToken := mPending.Acquire(mId);
    Assert.IsFalse(mPending.Abandoned(mId), 'offen');
    mPending.Expire(mToken);
    Assert.IsFalse(mPending.Abandoned(mId), 'nur Zeitlimit');
    mPending.Cancel(mId);
    Assert.IsTrue(mPending.Abandoned(mId), 'abgebrochen');
    mPending.Release(mId, mToken);
    Assert.IsFalse(mPending.Abandoned(mId), 'beantwortet');
  finally
    mId.Free;
  end;
  mPending := TJsonRpcPendingRequests.Create;
  mPending.AddContentChangeMethod('textDocument/didChange');
  Assert.IsFalse(Observe(mPending, '{"jsonrpc":"2.0","id":6,"method":"textDocument/codeAction",' +
    '"params":{"textDocument":{"uri":"file:///a.pas"}}}'));
  mPending.CancelForUri('file:///a.pas');
  mId := TJSONNumber.Create(6);
  try
    Assert.IsTrue(mPending.Abandoned(mId), 'Dokument geändert');
  finally
    mId.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcPendingRequestsTests);

end.
