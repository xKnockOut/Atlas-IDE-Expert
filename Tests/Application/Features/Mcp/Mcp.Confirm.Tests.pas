unit Mcp.Confirm.Tests;

// Tests für Rückfragen schreibender Werkzeuge (#2620, Stufe 2): Wahl des Wegs (Client vor IDE), Anfrage
// elicitation/create und Lesen der Antwort des Clients.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpConfirmTests = class
  public
    [Test]
    procedure WithoutWayNothingIsAsked;
    [Test]
    procedure ClientComesBeforeIde;
    [Test]
    procedure IdeAnswersWithoutClient;
    [Test]
    procedure NotTakenCountsAsNotAsked;
    [Test]
    procedure DeclinedAndUnknownAnswersAreNoAnswer;
    [Test]
    procedure ElicitParamsOfferTheAnswers;
    [Test]
    procedure ParsesTheClientResponse;
    [Test]
    procedure AskClientMapsTheOutcome;
    [Test]
    procedure QuestionHasNoFreeText;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Outgoing,
  Mcp.IdeQuestions,
  Atlas.Text.AssistantOrigin,
  Mcp.Confirm;

type
  /// <summary>Antwortet auf jede Anfrage mit AOutcome und, bei Answered, mit AResponse.</summary>
  TFixedOutgoing = class(TInterfacedObject, IJsonRpcOutgoing)
  private
    FOutcome: TJsonRpcOutgoingOutcome;
    FResponse: string;
  public
    constructor Create(AOutcome: TJsonRpcOutgoingOutcome; const AResponse: string);
    function Observe(AMessage: TJSONObject): Boolean;
    function Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
      out AResponse: TJSONObject): TJsonRpcOutgoingOutcome;
    procedure CloseAll;
  end;

constructor TFixedOutgoing.Create(AOutcome: TJsonRpcOutgoingOutcome; const AResponse: string);
begin
  inherited Create;
  FOutcome := AOutcome;
  FResponse := AResponse;
end;

function TFixedOutgoing.Observe(AMessage: TJSONObject): Boolean;
begin
  Result := False;
end;

function TFixedOutgoing.Request(const AMethod: string; AParams: TJSONValue; ATimeoutMs: Cardinal;
  out AResponse: TJSONObject): TJsonRpcOutgoingOutcome;
begin
  AParams.Free;
  AResponse := nil;
  if FOutcome = TJsonRpcOutgoingOutcome.Answered then
  begin
    AResponse := TJSONObject.ParseJSONValue(FResponse) as TJSONObject;
  end;
  Result := FOutcome;
end;

procedure TFixedOutgoing.CloseAll;
begin
end;

/// <summary>Fragefunktion, die AOutcome mit AAnswer liefert und ACalls hochzählt.</summary>
function Fixed(AOutcome: TMcpQuestionOutcome; const AAnswer: string; ACalls: PInteger): TMcpAskFunc;
begin
  Result :=
    function(const AQuestion: TMcpIdeQuestion; out AText: string): TMcpQuestionOutcome
    begin
      Inc(ACalls^);
      AText := AAnswer;
      Result := AOutcome;
    end;
end;

function YesNo: TMcpIdeQuestion;
begin
  Result := TMcpConfirm.Question('Weiter?', TArray<string>.Create('Ja', 'Nein'),
    TAtlasAssistantOrigin.Make('Client', '3f2a'));
end;

function Parse(const AJson: string; out AAnswer: string): TMcpQuestionOutcome;
var
  mResponse: TJSONObject;
begin
  mResponse := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
  try
    Result := TMcpConfirm.ParseElicitResponse(mResponse, AAnswer);
  finally
    mResponse.Free;
  end;
end;

function AskVia(AOutcome: TJsonRpcOutgoingOutcome; const AResponse: string; out AAnswer: string): TMcpQuestionOutcome;
var
  mOutgoing: IJsonRpcOutgoing;
begin
  mOutgoing := TFixedOutgoing.Create(AOutcome, AResponse);
  Result := TMcpConfirm.AskClient(mOutgoing, YesNo, AAnswer);
end;

procedure AreOutcome(AExpected, AActual: TMcpQuestionOutcome);
begin
  Assert.AreEqual<TMcpQuestionOutcome>(AExpected, AActual);
end;

{ TMcpConfirmTests }

procedure TMcpConfirmTests.WithoutWayNothingIsAsked;
begin
  Assert.AreEqual(TMcpConfirm.cNotAsked, TMcpConfirm.Choose(nil, nil, YesNo));
end;

procedure TMcpConfirmTests.ClientComesBeforeIde;
var
  mClientCalls, mIdeCalls: Integer;
begin
  mClientCalls := 0;
  mIdeCalls := 0;
  Assert.AreEqual(1, TMcpConfirm.Choose(Fixed(TMcpQuestionOutcome.Answered, 'Nein', @mClientCalls),
    Fixed(TMcpQuestionOutcome.Answered, 'Ja', @mIdeCalls), YesNo));
  Assert.AreEqual(1, mClientCalls);
  Assert.AreEqual(0, mIdeCalls, 'die IDE wird nicht zusätzlich gefragt');
end;

procedure TMcpConfirmTests.IdeAnswersWithoutClient;
var
  mIdeCalls: Integer;
begin
  mIdeCalls := 0;
  Assert.AreEqual(0, TMcpConfirm.Choose(nil, Fixed(TMcpQuestionOutcome.Answered, 'Ja', @mIdeCalls), YesNo));
  Assert.AreEqual(1, mIdeCalls);
end;

procedure TMcpConfirmTests.NotTakenCountsAsNotAsked;
var
  mCalls: Integer;
begin
  mCalls := 0;
  Assert.AreEqual(TMcpConfirm.cNotAsked, TMcpConfirm.Choose(nil, Fixed(TMcpQuestionOutcome.NotTaken, '', @mCalls),
    YesNo));
  Assert.AreEqual(TMcpConfirm.cNotAsked, TMcpConfirm.Choose(nil, Fixed(TMcpQuestionOutcome.NoIde, '', @mCalls),
    YesNo));
end;

procedure TMcpConfirmTests.DeclinedAndUnknownAnswersAreNoAnswer;
var
  mCalls: Integer;
begin
  mCalls := 0;
  Assert.AreEqual(TMcpConfirm.cNoAnswer, TMcpConfirm.Choose(Fixed(TMcpQuestionOutcome.Declined, '', @mCalls), nil,
    YesNo));
  Assert.AreEqual(TMcpConfirm.cNoAnswer, TMcpConfirm.Choose(Fixed(TMcpQuestionOutcome.TimedOut, '', @mCalls), nil,
    YesNo));
  Assert.AreEqual(TMcpConfirm.cNoAnswer, TMcpConfirm.Choose(Fixed(TMcpQuestionOutcome.Answered, 'Vielleicht',
    @mCalls), nil, YesNo), 'Antwort, die nicht angeboten war');
end;

procedure TMcpConfirmTests.ElicitParamsOfferTheAnswers;
var
  mParams: TJSONObject;
  mEnum: TJSONArray;
begin
  mParams := TMcpConfirm.ElicitParams(YesNo);
  try
    Assert.AreEqual('Weiter?', mParams.GetValue<string>('message'));
    Assert.AreEqual('object', mParams.GetValue<string>('requestedSchema.type'));
    Assert.AreEqual('string', mParams.GetValue<string>('requestedSchema.properties.answer.type'));
    mEnum := mParams.GetValue<TJSONArray>('requestedSchema.properties.answer.enum');
    Assert.AreEqual(2, Integer(mEnum.Count));
    Assert.AreEqual('Nein', mEnum.Items[1].Value);
    Assert.AreEqual(TMcpConfirm.cField, mParams.GetValue<TJSONArray>('requestedSchema.required').Items[0].Value);
  finally
    mParams.Free;
  end;
end;

procedure TMcpConfirmTests.ParsesTheClientResponse;
var
  mAnswer: string;
begin
  AreOutcome(TMcpQuestionOutcome.Answered, Parse('{"result":{"action":"accept","content":{"answer":"Ja"}}}',
    mAnswer));
  Assert.AreEqual('Ja', mAnswer);
  AreOutcome(TMcpQuestionOutcome.Declined, Parse('{"result":{"action":"decline"}}', mAnswer));
  AreOutcome(TMcpQuestionOutcome.Declined, Parse('{"result":{"action":"cancel"}}', mAnswer));
  AreOutcome(TMcpQuestionOutcome.Unreadable, Parse('{"result":{"action":"accept"}}', mAnswer));
  AreOutcome(TMcpQuestionOutcome.Unreadable, Parse('{"error":{"code":-32601}}', mAnswer));
  AreOutcome(TMcpQuestionOutcome.Unreadable, TMcpConfirm.ParseElicitResponse(nil, mAnswer));
  Assert.AreEqual('', mAnswer);
end;

procedure TMcpConfirmTests.AskClientMapsTheOutcome;
var
  mAnswer: string;
begin
  AreOutcome(TMcpQuestionOutcome.Answered, AskVia(TJsonRpcOutgoingOutcome.Answered,
    '{"result":{"action":"accept","content":{"answer":"Nein"}}}', mAnswer));
  Assert.AreEqual('Nein', mAnswer);
  AreOutcome(TMcpQuestionOutcome.TimedOut, AskVia(TJsonRpcOutgoingOutcome.TimedOut, '', mAnswer));
  AreOutcome(TMcpQuestionOutcome.Declined, AskVia(TJsonRpcOutgoingOutcome.Closed, '', mAnswer));
end;

procedure TMcpConfirmTests.QuestionHasNoFreeText;
var
  mQuestion: TMcpIdeQuestion;
begin
  mQuestion := YesNo;
  Assert.IsFalse(mQuestion.AllowText);
  Assert.AreEqual('Client', mQuestion.Origin.Client);
  Assert.AreEqual('3f2a', mQuestion.Origin.Session);
  Assert.AreEqual(TMcpIdeQuestions.cDefaultTimeoutSeconds, mQuestion.TimeoutSeconds);
  Assert.AreEqual(2, Integer(Length(mQuestion.Options)));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpConfirmTests);

end.
