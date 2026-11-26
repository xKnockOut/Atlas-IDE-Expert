unit Mcp.IdeQuestions.Tests;

// Tests für Rückfragen an den Menschen in der IDE (#2620, MCP-Werkzeug ask_user): Prüfung der Argumente, Auftrag,
// Antwort des Plugins und Text für den Assistenten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpIdeQuestionsTests = class
  public
    [Test]
    procedure QuestionIsRequired;
    [Test]
    procedure TooManyOptionsAreRefused;
    [Test]
    procedure WithoutOptionsTextIsAllowed;
    [Test]
    procedure TimeoutIsClamped;
    [Test]
    procedure RequestCarriesAllFields;
    [Test]
    procedure AnswerMsAddsSlack;
    [Test]
    procedure ParsesTheAnswers;
    [Test]
    procedure ResultTextNamesTheAnswer;
    [Test]
    procedure InputSchemaIsJson;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Mcp.IdeQuestions;

function Arguments(const AJson: string): TJSONObject;
begin
  Result := TJSONObject.ParseJSONValue(AJson) as TJSONObject;
end;

function Ask(const AJson: string; out AQuestion: TMcpIdeQuestion; out AReason: string): Boolean;
var
  mArguments: TJSONObject;
begin
  mArguments := Arguments(AJson);
  try
    Result := TMcpIdeQuestions.FromArguments(mArguments, 'Client', AQuestion, AReason);
  finally
    mArguments.Free;
  end;
end;

{ TMcpIdeQuestionsTests }

procedure TMcpIdeQuestionsTests.QuestionIsRequired;
var
  mQuestion: TMcpIdeQuestion;
  mReason: string;
begin
  Assert.IsFalse(Ask('{"question":"  "}', mQuestion, mReason));
  Assert.IsNotEmpty(mReason);
  Assert.IsFalse(TMcpIdeQuestions.FromArguments(nil, '', mQuestion, mReason));
end;

procedure TMcpIdeQuestionsTests.TooManyOptionsAreRefused;
var
  mQuestion: TMcpIdeQuestion;
  mReason: string;
begin
  Assert.IsFalse(Ask('{"question":"Q","options":["1","2","3","4","5","6","7","8","9","10","11"]}', mQuestion,
    mReason));
  Assert.IsTrue(Ask('{"question":"Q","options":["1"," ","2"]}', mQuestion, mReason), mReason);
  Assert.AreEqual(2, Integer(Length(mQuestion.Options)), 'leere Antworten fallen weg');
  Assert.IsFalse(mQuestion.AllowText);
end;

procedure TMcpIdeQuestionsTests.WithoutOptionsTextIsAllowed;
var
  mQuestion: TMcpIdeQuestion;
  mReason: string;
begin
  Assert.IsTrue(Ask('{"question":"Wie soll die Klasse heißen?"}', mQuestion, mReason), mReason);
  Assert.IsTrue(mQuestion.AllowText);
  Assert.AreEqual('Client', mQuestion.Client);
end;

procedure TMcpIdeQuestionsTests.TimeoutIsClamped;
var
  mQuestion: TMcpIdeQuestion;
  mReason: string;
begin
  Ask('{"question":"Q","timeoutSeconds":1}', mQuestion, mReason);
  Assert.AreEqual(TMcpIdeQuestions.cMinTimeoutSeconds, mQuestion.TimeoutSeconds);
  Ask('{"question":"Q","timeoutSeconds":99999}', mQuestion, mReason);
  Assert.AreEqual(TMcpIdeQuestions.cMaxTimeoutSeconds, mQuestion.TimeoutSeconds);
  Ask('{"question":"Q"}', mQuestion, mReason);
  Assert.AreEqual(TMcpIdeQuestions.cDefaultTimeoutSeconds, mQuestion.TimeoutSeconds);
end;

procedure TMcpIdeQuestionsTests.RequestCarriesAllFields;
var
  mQuestion: TMcpIdeQuestion;
  mReason: string;
  mJson: TJSONValue;
begin
  Ask('{"question":"Welche?","options":["A","B"],"allowText":true,"timeoutSeconds":60}', mQuestion, mReason);
  mJson := TJSONObject.ParseJSONValue(TMcpIdeQuestions.RequestText(mQuestion));
  try
    Assert.AreEqual('Welche?', mJson.GetValue<string>('question'));
    Assert.AreEqual(2, TJSONArray(TJSONObject(mJson).GetValue('options')).Count);
    Assert.IsTrue(mJson.GetValue<Boolean>('allowText'));
    Assert.AreEqual(60, mJson.GetValue<Integer>('timeoutSeconds'));
    Assert.AreEqual('Client', mJson.GetValue<string>('client'));
  finally
    mJson.Free;
  end;
end;

procedure TMcpIdeQuestionsTests.AnswerMsAddsSlack;
var
  mQuestion: TMcpIdeQuestion;
begin
  mQuestion := Default(TMcpIdeQuestion);
  mQuestion.TimeoutSeconds := 60;
  Assert.AreEqual(Int64(60000 + TMcpIdeQuestions.cAnswerSlackMs), TMcpIdeQuestions.AnswerMs(mQuestion));
end;

procedure TMcpIdeQuestionsTests.ParsesTheAnswers;
var
  mAnswer: string;
begin
  Assert.AreEqual<TMcpQuestionOutcome>(TMcpQuestionOutcome.Answered,
    TMcpIdeQuestions.ParseAnswer('{"status":"answered","answer":"B"}', mAnswer));
  Assert.AreEqual('B', mAnswer);
  Assert.AreEqual<TMcpQuestionOutcome>(TMcpQuestionOutcome.Declined,
    TMcpIdeQuestions.ParseAnswer('{"status":"declined"}', mAnswer));
  Assert.AreEqual<TMcpQuestionOutcome>(TMcpQuestionOutcome.TimedOut,
    TMcpIdeQuestions.ParseAnswer('{"status":"timeout"}', mAnswer));
  Assert.AreEqual<TMcpQuestionOutcome>(TMcpQuestionOutcome.Unreadable,
    TMcpIdeQuestions.ParseAnswer('kaputt', mAnswer));
end;

procedure TMcpIdeQuestionsTests.ResultTextNamesTheAnswer;
var
  mQuestion: TMcpIdeQuestion;
begin
  mQuestion := Default(TMcpIdeQuestion);
  mQuestion.TimeoutSeconds := 30;
  Assert.Contains(TMcpIdeQuestions.ResultText(TMcpQuestionOutcome.Answered, 'Variante B', mQuestion), 'Variante B');
  Assert.Contains(TMcpIdeQuestions.ResultText(TMcpQuestionOutcome.TimedOut, '', mQuestion), '30');
  Assert.IsNotEmpty(TMcpIdeQuestions.ResultText(TMcpQuestionOutcome.NoIde, '', mQuestion));
  Assert.IsNotEmpty(TMcpIdeQuestions.ResultText(TMcpQuestionOutcome.NotTaken, '', mQuestion));
end;

procedure TMcpIdeQuestionsTests.InputSchemaIsJson;
var
  mJson: TJSONValue;
begin
  mJson := TJSONObject.ParseJSONValue(TMcpIdeQuestions.InputSchema);
  try
    Assert.IsTrue(mJson is TJSONObject);
    Assert.AreEqual('question', TJSONArray(TJSONObject(mJson).GetValue('required')).Items[0].Value);
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpIdeQuestionsTests);

end.
