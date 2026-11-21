unit Atlas.Core.AiProviders.Anthropic.Tests;

// Tests für die KI-Anbieter (#1922): Anfrage an die Anthropic-API (Modell nur aus den Einstellungen, Köpfe,
// System- und Nutzertext), Auswertung der Antwort und der Fehler, kein Senden ohne Schlüssel, Fehler des
// Transports und der Katalog der Anbieter. Der Transport ist eine Fälschung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasAnthropicApiTests = class
  public
    [Test]
    procedure RequestBodyCarriesModelSystemAndTask;
    [Test]
    procedure RequestBodyOmitsEmptySystem;
    [Test]
    procedure HeadersCarryKeyAndVersion;
    [Test]
    procedure AnswerJoinsTextBlocks;
    [Test]
    procedure AnswerRefusalIsAnError;
    [Test]
    procedure AnswerUnauthorizedKeepsMessage;
    [Test]
    procedure AnswerNotFoundIsMissingModel;
    [Test]
    procedure AnswerOverloadedIsRateLimited;
    [Test]
    procedure AnswerNotJsonIsBadAnswer;
    [Test]
    procedure AnswerWithoutTextIsBadAnswer;
    [Test]
    procedure CompleteWithoutKeySendsNothing;
    [Test]
    procedure CompleteSendsToTheApiWithKey;
    [Test]
    procedure CompleteReportsTransportFailure;
    [Test]
    procedure CatalogBuildsProviders;
    [Test]
    procedure KeyTargetIsPerProvider;
    [Test]
    procedure ReadyNeedsProviderModelAndKey;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Core.AiProviders.Contract,
  Atlas.Core.AiProviders.Anthropic,
  Atlas.Core.AiProviders.Catalog,
  Atlas.Core.AiProviders.TestSupport;

function PromptOf(const AInstructions, ATask: string): TAtlasAiPrompt;
begin
  Result := Default(TAtlasAiPrompt);
  Result.Instructions := AInstructions;
  Result.Task := ATask;
  Result.MaxTokens := 100;
  Result.TimeoutMs := 5000;
end;

{ TAtlasAnthropicApiTests }

procedure TAtlasAnthropicApiTests.RequestBodyCarriesModelSystemAndTask;
var
  mValue: TJSONValue;
  mBody: TJSONObject;
  mMessage: TJSONObject;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasAnthropicApi.RequestBody('modell-a', PromptOf('Regeln', 'Aufgabe')));
  try
    Assert.IsTrue(mValue is TJSONObject, 'JSON-Objekt');
    mBody := TJSONObject(mValue);
    Assert.AreEqual('modell-a', mBody.GetValue<string>('model'));
    Assert.AreEqual(100, mBody.GetValue<Integer>('max_tokens'));
    Assert.AreEqual('Regeln', mBody.GetValue<string>('system'));
    mMessage := mBody.GetValue<TJSONArray>('messages').Items[0] as TJSONObject;
    Assert.AreEqual('user', mMessage.GetValue<string>('role'));
    Assert.AreEqual('Aufgabe', mMessage.GetValue<string>('content'));
  finally
    mValue.Free;
  end;
end;

procedure TAtlasAnthropicApiTests.RequestBodyOmitsEmptySystem;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasAnthropicApi.RequestBody('m', PromptOf('', 'x')));
  try
    Assert.IsNull(TJSONObject(mValue).GetValue('system'), 'ohne system');
  finally
    mValue.Free;
  end;
end;

procedure TAtlasAnthropicApiTests.HeadersCarryKeyAndVersion;
var
  mHeaders: TArray<TAtlasAiHeader>;
begin
  mHeaders := TAtlasAnthropicApi.Headers('geheim');
  Assert.AreEqual('geheim', AiHeaderValue(mHeaders, 'x-api-key'));
  Assert.AreEqual(TAtlasAnthropicApi.cVersion, AiHeaderValue(mHeaders, 'anthropic-version'));
  Assert.AreEqual('application/json', AiHeaderValue(mHeaders, 'content-type'));
end;

procedure TAtlasAnthropicApiTests.AnswerJoinsTextBlocks;
var
  mAnswer: TAtlasAiAnswer;
begin
  mAnswer := TAtlasAnthropicApi.ReadAnswer(200, '{"model":"m1","stop_reason":"end_turn","content":[' +
    '{"type":"text","text":"Inc(A);"},{"type":"other"},{"type":"text","text":" Exit;"}]}');
  Assert.IsTrue(mAnswer.Ok, 'ohne Fehler');
  Assert.AreEqual('Inc(A); Exit;', mAnswer.Text);
  Assert.AreEqual('m1', mAnswer.Model);
  Assert.AreEqual(200, mAnswer.Status);
end;

procedure TAtlasAnthropicApiTests.AnswerRefusalIsAnError;
var
  mAnswer: TAtlasAiAnswer;
begin
  mAnswer := TAtlasAnthropicApi.ReadAnswer(200, '{"stop_reason":"refusal","content":[]}');
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.Refused, mAnswer.Error);
  Assert.AreEqual('', mAnswer.Text);
end;

procedure TAtlasAnthropicApiTests.AnswerUnauthorizedKeepsMessage;
var
  mAnswer: TAtlasAiAnswer;
begin
  mAnswer := TAtlasAnthropicApi.ReadAnswer(401,
    '{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}');
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.Unauthorized, mAnswer.Error);
  Assert.AreEqual('invalid x-api-key', mAnswer.Detail);
end;

procedure TAtlasAnthropicApiTests.AnswerNotFoundIsMissingModel;
var
  mAnswer: TAtlasAiAnswer;
begin
  mAnswer := TAtlasAnthropicApi.ReadAnswer(404, '{"type":"error","error":{"type":"not_found_error","message":"m"}}');
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.ModelMissing, mAnswer.Error);
end;

procedure TAtlasAnthropicApiTests.AnswerOverloadedIsRateLimited;
var
  mAnswer: TAtlasAiAnswer;
begin
  mAnswer := TAtlasAnthropicApi.ReadAnswer(529, '{"type":"error","error":{"type":"overloaded_error","message":"o"}}');
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.RateLimited, mAnswer.Error);
  mAnswer := TAtlasAnthropicApi.ReadAnswer(500, '{"type":"error","error":{"type":"api_error","message":"o"}}');
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.ServerError, mAnswer.Error);
end;

procedure TAtlasAnthropicApiTests.AnswerNotJsonIsBadAnswer;
var
  mAnswer: TAtlasAiAnswer;
begin
  mAnswer := TAtlasAnthropicApi.ReadAnswer(200, '<html>');
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.BadAnswer, mAnswer.Error);
  mAnswer := TAtlasAnthropicApi.ReadAnswer(502, '<html>');
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.ServerError, mAnswer.Error);
end;

procedure TAtlasAnthropicApiTests.AnswerWithoutTextIsBadAnswer;
var
  mAnswer: TAtlasAiAnswer;
begin
  mAnswer := TAtlasAnthropicApi.ReadAnswer(200, '{"stop_reason":"end_turn","content":[]}');
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.BadAnswer, mAnswer.Error);
end;

procedure TAtlasAnthropicApiTests.CompleteWithoutKeySendsNothing;
var
  mFake: TFakeAiHttp;
  mHttp: IAtlasAiHttp;
  mProvider: IAtlasAiProvider;
  mAnswer: TAtlasAiAnswer;
begin
  mFake := TFakeAiHttp.Create;
  mHttp := mFake;
  mProvider := TAtlasAnthropicProvider.Create(mHttp,
    function(const AProviderId: string): string
    begin
      Result := '';
    end, 'm');
  mAnswer := mProvider.Complete(PromptOf('', 'x'));
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.NoKey, mAnswer.Error);
  Assert.AreEqual(0, mFake.Calls, 'nichts gesendet');
end;

procedure TAtlasAnthropicApiTests.CompleteSendsToTheApiWithKey;
var
  mFake: TFakeAiHttp;
  mHttp: IAtlasAiHttp;
  mProvider: IAtlasAiProvider;
  mAnswer: TAtlasAiAnswer;
  mAsked: string;
begin
  mFake := TFakeAiHttp.Create;
  mHttp := mFake;
  mFake.Reply.Status := 200;
  mFake.Reply.Body := '{"content":[{"type":"text","text":"ok"}]}';
  mProvider := TAtlasAnthropicProvider.Create(mHttp,
    function(const AProviderId: string): string
    begin
      mAsked := AProviderId;
      Result := 'k1';
    end, 'modell-b');
  mAnswer := mProvider.Complete(PromptOf('s', 't'));
  Assert.IsTrue(mAnswer.Ok, 'Antwort');
  Assert.AreEqual('ok', mAnswer.Text);
  Assert.AreEqual(TAtlasAnthropicApi.cId, mAsked, 'Schlüssel des Anbieters');
  Assert.AreEqual('POST', mFake.Method);
  Assert.AreEqual(TAtlasAnthropicApi.cUrl, mFake.Url);
  Assert.AreEqual('k1', AiHeaderValue(mFake.Headers, 'x-api-key'));
  Assert.AreEqual(5000, mFake.TimeoutMs);
  Assert.IsTrue(Pos('"modell-b"', mFake.Body) > 0, 'Modell aus den Einstellungen');
  Assert.IsFalse(Pos('k1', mFake.Body) > 0, 'Schlüssel nicht im Inhalt');
end;

procedure TAtlasAnthropicApiTests.CompleteReportsTransportFailure;
var
  mFake: TFakeAiHttp;
  mHttp: IAtlasAiHttp;
  mProvider: IAtlasAiProvider;
begin
  mFake := TFakeAiHttp.Create;
  mHttp := mFake;
  mFake.Reply.Failure := TAtlasAiError.Timeout;
  mProvider := TAtlasAnthropicProvider.Create(mHttp,
    function(const AProviderId: string): string
    begin
      Result := 'k';
    end, 'm');
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.Timeout, mProvider.Complete(PromptOf('', 'x')).Error);
end;

function SettingsOf(const AId: string): TAtlasAiProviderSettings;
begin
  Result := Default(TAtlasAiProviderSettings);
  Result.Id := AId;
  Result.Model := 'm';
  Result.Url := 'http://localhost:1234/v1';
  Result.TimeoutMs := 1000;
end;

procedure TAtlasAnthropicApiTests.CatalogBuildsProviders;
var
  mHttp: IAtlasAiHttp;
begin
  mHttp := TFakeAiHttp.Create;
  Assert.IsNull(TAtlasAiProviders.Create(SettingsOf(TAtlasAiProviders.cNone), mHttp, nil), 'keiner');
  Assert.IsNull(TAtlasAiProviders.Create(SettingsOf('unbekannt'), mHttp, nil), 'unbekannt');
  Assert.AreEqual(TAtlasAnthropicApi.cId, TAtlasAiProviders.Create(SettingsOf('Anthropic'), mHttp, nil).Id);
  Assert.AreEqual('openai-compatible', TAtlasAiProviders.Create(SettingsOf('openai-compatible'), mHttp, nil).Id);
  Assert.IsTrue(TAtlasAiProviders.NeedsKey('anthropic'), 'Schlüssel nötig');
  Assert.IsFalse(TAtlasAiProviders.NeedsKey('openai-compatible'), 'Schlüssel freiwillig');
  Assert.IsTrue(TAtlasAiProviders.TakesKey('openai-compatible'), 'Schlüssel möglich');
  Assert.IsFalse(TAtlasAiProviders.NeedsKey('none'), 'ohne Anbieter kein Schlüssel');
end;

procedure TAtlasAnthropicApiTests.KeyTargetIsPerProvider;
begin
  Assert.AreEqual('Atlas:ai:anthropic', TAtlasAiKeys.Target(' Anthropic '));
end;

procedure TAtlasAnthropicApiTests.ReadyNeedsProviderModelAndKey;
var
  mSettings: TAtlasAiProviderSettings;
begin
  Assert.IsFalse(TAtlasAiProviders.Ready(SettingsOf(TAtlasAiProviders.cNone), True), 'ohne Anbieter');
  Assert.IsFalse(TAtlasAiProviders.Ready(SettingsOf('unbekannt'), True), 'unbekannter Anbieter');
  Assert.IsTrue(TAtlasAiProviders.Ready(SettingsOf('anthropic'), True), 'Anthropic mit Schlüssel');
  Assert.IsFalse(TAtlasAiProviders.Ready(SettingsOf('anthropic'), False), 'Anthropic ohne Schlüssel');
  Assert.IsTrue(TAtlasAiProviders.Ready(SettingsOf('openai-compatible'), False), 'lokal ohne Schlüssel');
  mSettings := SettingsOf('openai-compatible');
  mSettings.Model := ' ';
  Assert.IsFalse(TAtlasAiProviders.Ready(mSettings, True), 'ohne Modell');
  mSettings := SettingsOf('openai-compatible');
  mSettings.Url := '';
  Assert.IsFalse(TAtlasAiProviders.Ready(mSettings, True), 'ohne Adresse');
end;

end.
