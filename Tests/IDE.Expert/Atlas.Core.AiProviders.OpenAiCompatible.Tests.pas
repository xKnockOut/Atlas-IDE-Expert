unit Atlas.Core.AiProviders.OpenAiCompatible.Tests;

// Tests für den OpenAI-kompatiblen Anbieter (#2056): Adressen, Schlüssel nur über https oder an den eigenen Rechner,
// Aufbau der Anfrage, Auswertung von Antworten und Fehlern, Modellliste, Probe und die Einstellungen der Anbieter.
// Der Transport ist eine Fälschung; es geht nichts ins Netz.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasOpenAiCompatibleTests = class
  public
    [Test]
    procedure UrlOfJoinsWithoutDoubleSlash;
    [Test]
    procedure KeyOnlyOverHttpsOrLocalhost;
    [Test]
    procedure RequestBodyHasSystemUserAndNoStream;
    [Test]
    procedure HeadersWithoutKeyHaveNoAuthorization;
    [Test]
    procedure AnswerReadsFirstChoice;
    [Test]
    procedure AnswerContentFilterIsRefused;
    [Test]
    procedure AnswerErrorObjectKeepsMessage;
    [Test]
    procedure AnswerErrorTextKeepsMessage;
    [Test]
    procedure AnswerWithoutChoicesIsBadAnswer;
    [Test]
    procedure ModelsAreReadAndSorted;
    [Test]
    procedure ModelsWithoutListAreNil;
    [Test]
    procedure CompleteWithoutModelSendsNothing;
    [Test]
    procedure CompletePostsToChatCompletionsWithOwnTimeout;
    [Test]
    procedure CompleteSendsKeyOnlyToLocalhost;
    [Test]
    procedure ModelsGetsTheList;
    [Test]
    procedure ProbeMeasuresAndAnswers;
    [Test]
    procedure SettingsOfPicksTheProviderModel;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.AiProviders.Contract,
  Atlas.Core.AiProviders.OpenAiCompatible,
  Atlas.Core.AiProviders.Catalog,
  Atlas.Core.AiProviders.TestSupport;

function PromptOf(const AInstructions, ATask: string): TAtlasAiPrompt;
begin
  Result := Default(TAtlasAiPrompt);
  Result.Instructions := AInstructions;
  Result.Task := ATask;
  Result.MaxTokens := 50;
  // 0: Zeitlimit aus den Einstellungen des Anbieters.
  Result.TimeoutMs := 0;
end;

function KeyReader(const AKey: string): TAtlasAiKeyReader;
begin
  Result :=
    function(const AProviderId: string): string
    begin
      Result := AKey;
    end;
end;

{ TAtlasOpenAiCompatibleTests }

procedure TAtlasOpenAiCompatibleTests.UrlOfJoinsWithoutDoubleSlash;
begin
  Assert.AreEqual('http://localhost:1234/v1/models', TAtlasOpenAiApi.UrlOf(' http://localhost:1234/v1/ ', '/models'));
  Assert.AreEqual('http://h/v1/chat/completions', TAtlasOpenAiApi.UrlOf('http://h/v1', '/chat/completions'));
end;

procedure TAtlasOpenAiCompatibleTests.KeyOnlyOverHttpsOrLocalhost;
begin
  Assert.IsTrue(TAtlasOpenAiApi.MayAuthenticate('https://gateway.firma.de/v1'), 'https');
  Assert.IsTrue(TAtlasOpenAiApi.MayAuthenticate('http://localhost:1234/v1'), 'localhost');
  Assert.IsTrue(TAtlasOpenAiApi.MayAuthenticate('http://127.0.0.1:8080/v1'), '127.0.0.1');
  Assert.IsTrue(TAtlasOpenAiApi.MayAuthenticate('http://[::1]:11434/v1'), '::1');
  Assert.IsFalse(TAtlasOpenAiApi.MayAuthenticate('http://server.firma.de/v1'), 'http an fremden Rechner');
  Assert.IsFalse(TAtlasOpenAiApi.MayAuthenticate('http://localhost.boese.de/v1'), 'nur der Name localhost');
  Assert.IsFalse(TAtlasOpenAiApi.MayAuthenticate('ftp://localhost/v1'), 'kein http');
end;

procedure TAtlasOpenAiCompatibleTests.RequestBodyHasSystemUserAndNoStream;
var
  mValue: TJSONValue;
  mBody: TJSONObject;
  mMessages: TJSONArray;
begin
  mValue := TJSONObject.ParseJSONValue(TAtlasOpenAiApi.RequestBody('qwen', PromptOf('Regeln', 'Aufgabe')));
  try
    mBody := mValue as TJSONObject;
    Assert.AreEqual('qwen', mBody.GetValue<string>('model'));
    Assert.AreEqual(50, mBody.GetValue<Integer>('max_tokens'));
    Assert.IsFalse(mBody.GetValue<Boolean>('stream'), 'ohne Streaming');
    mMessages := mBody.GetValue<TJSONArray>('messages');
    Assert.AreEqual(2, Integer(mMessages.Count));
    Assert.AreEqual('system', (mMessages.Items[0] as TJSONObject).GetValue<string>('role'));
    Assert.AreEqual('Regeln', (mMessages.Items[0] as TJSONObject).GetValue<string>('content'));
    Assert.AreEqual('user', (mMessages.Items[1] as TJSONObject).GetValue<string>('role'));
    Assert.AreEqual('Aufgabe', (mMessages.Items[1] as TJSONObject).GetValue<string>('content'));
  finally
    mValue.Free;
  end;
end;

procedure TAtlasOpenAiCompatibleTests.HeadersWithoutKeyHaveNoAuthorization;
begin
  Assert.AreEqual('', AiHeaderValue(TAtlasOpenAiApi.Headers(''), 'Authorization'));
  Assert.AreEqual('Bearer k', AiHeaderValue(TAtlasOpenAiApi.Headers('k'), 'Authorization'));
end;

procedure TAtlasOpenAiCompatibleTests.AnswerReadsFirstChoice;
var
  mAnswer: TAtlasAiAnswer;
begin
  mAnswer := TAtlasOpenAiApi.ReadAnswer(200, '{"model":"qwen","choices":[{"index":0,"finish_reason":"stop",' +
    '"message":{"role":"assistant","content":"Exit;"}},{"message":{"content":"zweite"}}]}');
  Assert.IsTrue(mAnswer.Ok, 'ohne Fehler');
  Assert.AreEqual('Exit;', mAnswer.Text);
  Assert.AreEqual('qwen', mAnswer.Model);
end;

procedure TAtlasOpenAiCompatibleTests.AnswerContentFilterIsRefused;
begin
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.Refused, TAtlasOpenAiApi.ReadAnswer(200,
    '{"choices":[{"finish_reason":"content_filter","message":{"content":""}}]}').Error);
end;

procedure TAtlasOpenAiCompatibleTests.AnswerErrorObjectKeepsMessage;
var
  mAnswer: TAtlasAiAnswer;
begin
  mAnswer := TAtlasOpenAiApi.ReadAnswer(404,
    '{"error":{"message":"model \"x\" not found","type":"invalid_request_error","code":"model_not_found"}}');
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.ModelMissing, mAnswer.Error);
  Assert.AreEqual('model "x" not found', mAnswer.Detail);
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.Unauthorized, TAtlasOpenAiApi.ReadAnswer(401, '{}').Error);
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.ServerError, TAtlasOpenAiApi.ReadAnswer(503, 'down').Error);
end;

procedure TAtlasOpenAiCompatibleTests.AnswerErrorTextKeepsMessage;
var
  mAnswer: TAtlasAiAnswer;
begin
  mAnswer := TAtlasOpenAiApi.ReadAnswer(400, '{"error":"model is required"}');
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.BadAnswer, mAnswer.Error);
  Assert.AreEqual('model is required', mAnswer.Detail);
end;

procedure TAtlasOpenAiCompatibleTests.AnswerWithoutChoicesIsBadAnswer;
begin
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.BadAnswer, TAtlasOpenAiApi.ReadAnswer(200, '{"choices":[]}').Error);
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.BadAnswer, TAtlasOpenAiApi.ReadAnswer(200, 'kein JSON').Error);
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.BadAnswer, TAtlasOpenAiApi.ReadAnswer(200,
    '{"choices":[{"message":{"content":null}}]}').Error);
end;

procedure TAtlasOpenAiCompatibleTests.ModelsAreReadAndSorted;
var
  mModels: TArray<string>;
begin
  mModels := TAtlasOpenAiApi.ReadModels('{"object":"list","data":[{"id":"qwen2.5-coder"},{"id":" "},' +
    '{"id":"llama3"},{"object":"model"}]}');
  Assert.AreEqual(2, Integer(Length(mModels)));
  Assert.AreEqual('llama3', mModels[0]);
  Assert.AreEqual('qwen2.5-coder', mModels[1]);
end;

procedure TAtlasOpenAiCompatibleTests.ModelsWithoutListAreNil;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasOpenAiApi.ReadModels('{"models":[]}'))));
  Assert.AreEqual(0, Integer(Length(TAtlasOpenAiApi.ReadModels('<html>'))));
end;

procedure TAtlasOpenAiCompatibleTests.CompleteWithoutModelSendsNothing;
var
  mFake: TFakeAiHttp;
  mHttp: IAtlasAiHttp;
  mProvider: IAtlasAiProvider;
begin
  mFake := TFakeAiHttp.Create;
  mHttp := mFake;
  mProvider := TAtlasOpenAiProvider.Create(mHttp, nil, 'http://localhost:1234/v1', ' ', 3000);
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.ModelMissing, mProvider.Complete(PromptOf('', 'x')).Error);
  Assert.AreEqual(0, mFake.Calls, 'nichts gesendet');
end;

procedure TAtlasOpenAiCompatibleTests.CompletePostsToChatCompletionsWithOwnTimeout;
var
  mPrompt: TAtlasAiPrompt;
  mFake: TFakeAiHttp;
  mHttp: IAtlasAiHttp;
  mProvider: IAtlasAiProvider;
  mAnswer: TAtlasAiAnswer;
begin
  mFake := TFakeAiHttp.Create;
  mHttp := mFake;
  mFake.Reply.Status := 200;
  mFake.Reply.Body := '{"choices":[{"message":{"content":"ok"}}]}';
  mProvider := TAtlasOpenAiProvider.Create(mHttp, nil, 'http://localhost:1234/v1/', 'qwen', 2500);
  mAnswer := mProvider.Complete(PromptOf('', 'x'));
  Assert.IsTrue(mAnswer.Ok, 'Antwort');
  Assert.AreEqual('POST', mFake.Method);
  Assert.AreEqual('http://localhost:1234/v1/chat/completions', mFake.Url);
  Assert.AreEqual(2500, mFake.TimeoutMs, 'Zeitlimit aus assistants.openaiCompatible.timeoutMs');
  Assert.AreEqual('', AiHeaderValue(mFake.Headers, 'Authorization'), 'ohne Schlüsselleser keine Anmeldung');
  mPrompt := PromptOf('', 'x');
  mPrompt.TimeoutMs := 30000;
  mAnswer := mProvider.Complete(mPrompt);
  Assert.IsTrue(mAnswer.Ok, 'zweite Antwort');
  Assert.AreEqual(30000, mFake.TimeoutMs, 'Zeitlimit des Prompts (Probe, Zusammenfassung) geht vor');
end;

procedure TAtlasOpenAiCompatibleTests.CompleteSendsKeyOnlyToLocalhost;
var
  mFake: TFakeAiHttp;
  mHttp: IAtlasAiHttp;
  mProvider: IAtlasAiProvider;
begin
  mFake := TFakeAiHttp.Create;
  mHttp := mFake;
  mFake.Reply.Status := 200;
  mFake.Reply.Body := '{"choices":[{"message":{"content":"ok"}}]}';
  mProvider := TAtlasOpenAiProvider.Create(mHttp, KeyReader('geheim'), 'http://127.0.0.1:8080/v1', 'm', 1000);
  mProvider.Complete(PromptOf('', 'x'));
  Assert.AreEqual('Bearer geheim', AiHeaderValue(mFake.Headers, 'Authorization'), 'eigener Rechner');
  mProvider := TAtlasOpenAiProvider.Create(mHttp, KeyReader('geheim'), 'http://server.firma.de/v1', 'm', 1000);
  mProvider.Complete(PromptOf('', 'x'));
  Assert.AreEqual('', AiHeaderValue(mFake.Headers, 'Authorization'), 'nicht im Klartext an fremden Rechner');
end;

procedure TAtlasOpenAiCompatibleTests.ModelsGetsTheList;
var
  mFake: TFakeAiHttp;
  mHttp: IAtlasAiHttp;
  mModels: IAtlasAiModels;
  mList: TArray<string>;
begin
  mFake := TFakeAiHttp.Create;
  mHttp := mFake;
  mFake.Reply.Status := 200;
  mFake.Reply.Body := '{"data":[{"id":"b"},{"id":"a"}]}';
  mModels := TAtlasOpenAiProvider.Create(mHttp, nil, 'http://localhost:1234/v1', '', 1000);
  Assert.IsTrue(mModels.Models(mList).Ok, 'Liste');
  Assert.AreEqual('GET', mFake.Method);
  Assert.AreEqual('http://localhost:1234/v1/models', mFake.Url);
  Assert.AreEqual(2, Integer(Length(mList)));
  Assert.AreEqual('a', mList[0]);
  mFake.Reply.Status := 401;
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.Unauthorized, mModels.Models(mList).Error);
  Assert.AreEqual(0, Integer(Length(mList)));
  mFake.Reply.Failure := TAtlasAiError.Unreachable;
  Assert.AreEqual<TAtlasAiError>(TAtlasAiError.Unreachable, mModels.Models(mList).Error);
end;

procedure TAtlasOpenAiCompatibleTests.ProbeMeasuresAndAnswers;
var
  mFake: TFakeAiHttp;
  mHttp: IAtlasAiHttp;
  mProvider: IAtlasAiProvider;
  mResult: TAtlasAiProbeResult;
begin
  mFake := TFakeAiHttp.Create;
  mHttp := mFake;
  mFake.Reply.Status := 200;
  mFake.Reply.Body := '{"model":"qwen","choices":[{"message":{"content":"OK"}}]}';
  // Erst in eine Interface-Variable: TObjekt.Create direkt am const-Interface-Parameter wird nie freigegeben.
  mProvider := TAtlasOpenAiProvider.Create(mHttp, nil, 'http://localhost/v1', 'qwen', 1000);
  mResult := TAtlasAiProviders.Probe(mProvider);
  Assert.IsTrue(mResult.Answer.Ok, 'Antwort');
  Assert.AreEqual('qwen', mResult.Answer.Model);
  Assert.IsTrue(mResult.Ms >= 0, 'Dauer');
  Assert.AreEqual(1, mFake.Calls, 'eine Anfrage');
end;

procedure TAtlasOpenAiCompatibleTests.SettingsOfPicksTheProviderModel;
var
  mSettings: TAtlasPluginSettings;
  mProvider: TAtlasAiProviderSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.AssistantsProvider := 'anthropic';
  mSettings.AssistantsModel := 'klein';
  mSettings.AssistantsOpenAiModel := 'lokal';
  mProvider := TAtlasAiProviders.SettingsOf(mSettings);
  Assert.AreEqual('klein', mProvider.Model);
  Assert.AreEqual('', mProvider.Url);
  mSettings.AssistantsProvider := 'openai-compatible';
  mProvider := TAtlasAiProviders.SettingsOf(mSettings);
  Assert.AreEqual('lokal', mProvider.Model);
  Assert.AreEqual('http://localhost:1234/v1', mProvider.Url);
  Assert.AreEqual(3000, mProvider.TimeoutMs);
end;

end.
