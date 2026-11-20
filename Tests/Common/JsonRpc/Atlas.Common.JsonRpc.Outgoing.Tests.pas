unit Atlas.Common.JsonRpc.Outgoing.Tests;

// Tests für eigene Anfragen an die Gegenseite (#2620, elicitation/create): Senden mit eigener id, Antwort über
// Observe, Zeitablauf und Ende der Verbindung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcOutgoingTests = class
  public
    [Test]
    procedure RequestReturnsTheAnswer;
    [Test]
    procedure RequestSendsMethodParamsAndPrefixedId;
    [Test]
    procedure RequestTimesOutWithoutAnswer;
    [Test]
    procedure ClosedConnectionEndsRequests;
    [Test]
    procedure ObserveIgnoresOtherMessages;
    [Test]
    procedure ResponseIdReadsOnlyResponses;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Outgoing;

type
  /// <summary>Merkt sich die zuletzt geschriebene Nachricht; mit AAnswer beantwortet sie die Anfrage sofort, als
  /// käme die Antwort über den Lese-Thread.</summary>
  TAnsweringTransport = class(TInterfacedObject, IJsonRpcTransport)
  private
    FAnswer: string;
    FLast: string;
    /// <summary>Nicht gezählt, sonst hielten sich Transport und Outgoing gegenseitig.</summary>
    FOutgoing: TJsonRpcOutgoing;
  public
    constructor Create(const AAnswer: string);
    function ReadMessage: TJSONObject;
    procedure WriteMessage(const AMessage: TJSONObject);
    property Last: string read FLast;
    property Outgoing: TJsonRpcOutgoing read FOutgoing write FOutgoing;
  end;

constructor TAnsweringTransport.Create(const AAnswer: string);
begin
  inherited Create;
  FAnswer := AAnswer;
end;

function TAnsweringTransport.ReadMessage: TJSONObject;
begin
  raise EJsonRpcTransportClosed.Create('Ende');
end;

procedure TAnsweringTransport.WriteMessage(const AMessage: TJSONObject);
var
  mResponse: TJSONObject;
begin
  FLast := AMessage.ToJSON;
  if FAnswer = '' then
  begin
    Exit;
  end;
  mResponse := TJSONObject.ParseJSONValue(FAnswer) as TJSONObject;
  mResponse.AddPair('id', AMessage.GetValue('id').Value);
  if not FOutgoing.Observe(mResponse) then
  begin
    mResponse.Free;
  end;
end;

function NewOutgoing(const AAnswer: string; out ATransport: TAnsweringTransport): IJsonRpcOutgoing;
var
  mOutgoing: TJsonRpcOutgoing;
  mTransport: IJsonRpcTransport;
begin
  ATransport := TAnsweringTransport.Create(AAnswer);
  mTransport := ATransport;
  mOutgoing := TJsonRpcOutgoing.Create(mTransport, 'atlas/out/');
  ATransport.Outgoing := mOutgoing;
  Result := mOutgoing;
end;

function Params: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('message', 'Frage');
end;

procedure AreOutcome(AExpected, AActual: TJsonRpcOutgoingOutcome);
begin
  Assert.AreEqual<TJsonRpcOutgoingOutcome>(AExpected, AActual);
end;

{ TJsonRpcOutgoingTests }

procedure TJsonRpcOutgoingTests.RequestReturnsTheAnswer;
var
  mTransport: TAnsweringTransport;
  mOutgoing: IJsonRpcOutgoing;
  mResponse: TJSONObject;
begin
  mOutgoing := NewOutgoing('{"jsonrpc":"2.0","result":{"action":"accept"}}', mTransport);
  AreOutcome(TJsonRpcOutgoingOutcome.Answered, mOutgoing.Request('elicitation/create', Params, 1000,
    mResponse));
  try
    Assert.AreEqual('accept', mResponse.GetValue<string>('result.action'));
  finally
    mResponse.Free;
  end;
end;

procedure TJsonRpcOutgoingTests.RequestSendsMethodParamsAndPrefixedId;
var
  mTransport: TAnsweringTransport;
  mOutgoing: IJsonRpcOutgoing;
  mResponse: TJSONObject;
  mSent: TJSONObject;
begin
  mOutgoing := NewOutgoing('{"result":{}}', mTransport);
  mOutgoing.Request('elicitation/create', Params, 1000, mResponse);
  mResponse.Free;
  mSent := TJSONObject.ParseJSONValue(mTransport.Last) as TJSONObject;
  try
    Assert.AreEqual('elicitation/create', mSent.GetValue<string>('method'));
    Assert.AreEqual('Frage', mSent.GetValue<string>('params.message'));
    Assert.AreEqual('atlas/out/1', mSent.GetValue<string>('id'));
  finally
    mSent.Free;
  end;
end;

procedure TJsonRpcOutgoingTests.RequestTimesOutWithoutAnswer;
var
  mTransport: TAnsweringTransport;
  mOutgoing: IJsonRpcOutgoing;
  mResponse, mLate: TJSONObject;
begin
  mOutgoing := NewOutgoing('', mTransport);
  AreOutcome(TJsonRpcOutgoingOutcome.TimedOut, mOutgoing.Request('elicitation/create', Params, 10,
    mResponse));
  Assert.IsNull(mResponse);
  mLate := TJSONObject.ParseJSONValue('{"id":"atlas/out/1","result":{}}') as TJSONObject;
  try
    Assert.IsFalse(mOutgoing.Observe(mLate), 'späte Antwort gehört niemandem mehr');
  finally
    mLate.Free;
  end;
end;

procedure TJsonRpcOutgoingTests.ClosedConnectionEndsRequests;
var
  mTransport: TAnsweringTransport;
  mOutgoing: IJsonRpcOutgoing;
  mResponse: TJSONObject;
begin
  mOutgoing := NewOutgoing('{"result":{}}', mTransport);
  mOutgoing.CloseAll;
  AreOutcome(TJsonRpcOutgoingOutcome.Closed, mOutgoing.Request('elicitation/create', Params, 1000,
    mResponse));
  Assert.IsNull(mResponse);
  Assert.IsEmpty(mTransport.Last, 'nach dem Ende wird nichts mehr gesendet');
end;

procedure TJsonRpcOutgoingTests.ObserveIgnoresOtherMessages;
var
  mTransport: TAnsweringTransport;
  mOutgoing: IJsonRpcOutgoing;
  mRequest, mForeign: TJSONObject;
begin
  mOutgoing := NewOutgoing('', mTransport);
  mRequest := TJSONObject.ParseJSONValue('{"id":"atlas/out/1","method":"tools/call"}') as TJSONObject;
  mForeign := TJSONObject.ParseJSONValue('{"id":7,"result":{}}') as TJSONObject;
  try
    Assert.IsFalse(mOutgoing.Observe(mRequest), 'Anfrage der Gegenseite');
    Assert.IsFalse(mOutgoing.Observe(mForeign), 'Antwort ohne wartende Anfrage');
    Assert.IsFalse(mOutgoing.Observe(nil));
  finally
    mForeign.Free;
    mRequest.Free;
  end;
end;

procedure TJsonRpcOutgoingTests.ResponseIdReadsOnlyResponses;
var
  mNumber, mText, mRequest: TJSONObject;
begin
  mNumber := TJSONObject.ParseJSONValue('{"id":3,"result":{}}') as TJSONObject;
  mText := TJSONObject.ParseJSONValue('{"id":"x","error":{}}') as TJSONObject;
  mRequest := TJSONObject.ParseJSONValue('{"id":4,"method":"ping"}') as TJSONObject;
  try
    Assert.AreEqual('3', TJsonRpcOutgoing.ResponseId(mNumber));
    Assert.AreEqual('x', TJsonRpcOutgoing.ResponseId(mText));
    Assert.AreEqual('', TJsonRpcOutgoing.ResponseId(mRequest));
  finally
    mRequest.Free;
    mText.Free;
    mNumber.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TJsonRpcOutgoingTests);

end.
