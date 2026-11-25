unit Atlas.Core.Assistants.Questions.Tests;

// Tests für Rückfragen von KI-Assistenten in der IDE (#2620): Auftrag lesen, Antwort schreiben, Reihenfolge der
// offenen Fragen mit „Später“, Ablauf der Frist und Abschalten.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Assistants.Questions;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasQuestionsTests = class
  private
    FQueue: TAtlasQuestionQueue;
    function Question(const AId: string; ADeadlineMs: UInt64): TAtlasQuestion;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ParseReadsQuestionOptionsAndDeadline;
    [Test]
    procedure ParseWithoutOptionsAllowsText;
    [Test]
    procedure ParseClampsTheTimeout;
    [Test]
    procedure ParseRejectsMissingQuestion;
    [Test]
    procedure AnswerTextNamesStatusAndAnswer;
    [Test]
    procedure CurrentSkipsPostponedQuestions;
    [Test]
    procedure TakeExpiredRemovesOnlyDueQuestions;
    [Test]
    procedure TakeAllEmptiesTheQueue;
    [Test]
    procedure ChosenAnswer;
  end;

implementation

uses
  System.SysUtils,
  System.JSON;

function Texts: TAtlasQuestionTexts;
begin
  Result.Unreadable := 'unlesbar';
  Result.NoQuestion := 'keine Frage';
end;

{ TAtlasQuestionsTests }

procedure TAtlasQuestionsTests.Setup;
begin
  FQueue := TAtlasQuestionQueue.Create;
end;

procedure TAtlasQuestionsTests.TearDown;
begin
  FreeAndNil(FQueue);
end;

function TAtlasQuestionsTests.Question(const AId: string; ADeadlineMs: UInt64): TAtlasQuestion;
begin
  Result := Default(TAtlasQuestion);
  Result.Id := AId;
  Result.Question := 'Frage ' + AId;
  Result.DeadlineMs := ADeadlineMs;
end;

procedure TAtlasQuestionsTests.ParseReadsQuestionOptionsAndDeadline;
var
  mQuestion: TAtlasQuestion;
  mReason: string;
begin
  Assert.IsTrue(TAtlasQuestionInbox.Parse('q1', '{"question":" Welche Unit? ","options":["A"," ","B"],' +
    '"allowText":false,"timeoutSeconds":60,"client":"Assistent A"}', 1000, Texts, mQuestion, mReason));
  Assert.AreEqual('q1', mQuestion.Id);
  Assert.AreEqual('Welche Unit?', mQuestion.Question);
  Assert.AreEqual(2, Integer(Length(mQuestion.Options)), 'leere Antworten fallen weg');
  Assert.AreEqual('B', mQuestion.Options[1]);
  Assert.IsFalse(mQuestion.AllowText);
  Assert.AreEqual('Assistent A', mQuestion.Client);
  Assert.AreEqual<UInt64>(61000, mQuestion.DeadlineMs);
end;

procedure TAtlasQuestionsTests.ParseWithoutOptionsAllowsText;
var
  mQuestion: TAtlasQuestion;
  mReason: string;
begin
  Assert.IsTrue(TAtlasQuestionInbox.Parse('q', '{"question":"Name?"}', 0, Texts, mQuestion, mReason));
  Assert.IsTrue(mQuestion.AllowText, 'ohne Optionen bleibt nur Text');
  Assert.AreEqual(TAtlasQuestionInbox.cDefaultTimeoutSeconds, mQuestion.TimeoutSeconds);
end;

procedure TAtlasQuestionsTests.ParseClampsTheTimeout;
var
  mQuestion: TAtlasQuestion;
  mReason: string;
begin
  Assert.IsTrue(TAtlasQuestionInbox.Parse('q', '{"question":"x","timeoutSeconds":1}', 0, Texts, mQuestion,
    mReason));
  Assert.AreEqual(TAtlasQuestionInbox.cMinTimeoutSeconds, mQuestion.TimeoutSeconds);
  Assert.IsTrue(TAtlasQuestionInbox.Parse('q', '{"question":"x","timeoutSeconds":99999}', 0, Texts, mQuestion,
    mReason));
  Assert.AreEqual(TAtlasQuestionInbox.cMaxTimeoutSeconds, mQuestion.TimeoutSeconds);
end;

procedure TAtlasQuestionsTests.ParseRejectsMissingQuestion;
var
  mQuestion: TAtlasQuestion;
  mReason: string;
begin
  Assert.IsFalse(TAtlasQuestionInbox.Parse('q', '{"question":"  "}', 0, Texts, mQuestion, mReason));
  Assert.AreEqual('keine Frage', mReason);
  Assert.IsFalse(TAtlasQuestionInbox.Parse('q', 'kein JSON', 0, Texts, mQuestion, mReason));
  Assert.AreEqual('unlesbar', mReason);
end;

procedure TAtlasQuestionsTests.AnswerTextNamesStatusAndAnswer;
var
  mJson: TJSONValue;
begin
  mJson := TJSONObject.ParseJSONValue(TAtlasQuestionInbox.AnswerText(TAtlasQuestionStatus.Answered, 'Ja'));
  try
    Assert.AreEqual('answered', TJSONObject(mJson).GetValue<string>('status'));
    Assert.AreEqual('Ja', TJSONObject(mJson).GetValue<string>('answer'));
  finally
    mJson.Free;
  end;
  mJson := TJSONObject.ParseJSONValue(TAtlasQuestionInbox.AnswerText(TAtlasQuestionStatus.Declined, 'Ja'));
  try
    Assert.AreEqual('declined', TJSONObject(mJson).GetValue<string>('status'));
    Assert.IsNull(TJSONObject(mJson).GetValue('answer'), 'ohne Antwort');
  finally
    mJson.Free;
  end;
  Assert.Contains(TAtlasQuestionInbox.AnswerText(TAtlasQuestionStatus.TimedOut, ''), '"timeout"');
end;

procedure TAtlasQuestionsTests.CurrentSkipsPostponedQuestions;
var
  mQuestion: TAtlasQuestion;
begin
  Assert.IsFalse(FQueue.TryCurrent(mQuestion), 'leer');
  FQueue.Add(Question('a', 100));
  FQueue.Add(Question('b', 100));
  Assert.IsTrue(FQueue.TryCurrent(mQuestion));
  Assert.AreEqual('a', mQuestion.Id, 'die älteste zuerst');
  FQueue.Postpone('a', True);
  Assert.IsTrue(FQueue.TryCurrent(mQuestion));
  Assert.AreEqual('b', mQuestion.Id, '„Später“ lässt die nächste vor');
  FQueue.Postpone('b', True);
  Assert.IsTrue(FQueue.TryCurrent(mQuestion));
  Assert.AreEqual('a', mQuestion.Id, 'alle zurückgestellt: wieder die älteste');
  FQueue.RecallAll;
  Assert.IsTrue(FQueue.TryGet('b', mQuestion));
  Assert.IsFalse(mQuestion.Postponed);
  Assert.IsTrue(FQueue.Remove('a'));
  Assert.IsFalse(FQueue.Remove('a'));
  Assert.AreEqual(1, Integer(FQueue.Count));
end;

procedure TAtlasQuestionsTests.TakeExpiredRemovesOnlyDueQuestions;
var
  mExpired: TArray<TAtlasQuestion>;
begin
  FQueue.Add(Question('a', 100));
  FQueue.Add(Question('b', 300));
  FQueue.Add(Question('c', 200));
  mExpired := FQueue.TakeExpired(200);
  Assert.AreEqual(2, Integer(Length(mExpired)));
  Assert.AreEqual('a', mExpired[0].Id);
  Assert.AreEqual('c', mExpired[1].Id);
  Assert.AreEqual(1, Integer(FQueue.Count));
end;

procedure TAtlasQuestionsTests.TakeAllEmptiesTheQueue;
begin
  FQueue.Add(Question('a', 100));
  FQueue.Add(Question('b', 100));
  Assert.AreEqual(2, Integer(Length(FQueue.TakeAll)));
  Assert.AreEqual(0, Integer(FQueue.Count));
end;

procedure TAtlasQuestionsTests.ChosenAnswer;
var
  mQuestion: TAtlasQuestion;
  mAnswer: string;
begin
  mQuestion := Default(TAtlasQuestion);
  mQuestion.Options := TArray<string>.Create('A', 'B');
  Assert.IsTrue(TAtlasQuestionInbox.Chosen(mQuestion, 1, '', mAnswer));
  Assert.AreEqual('B', mAnswer);
  Assert.IsFalse(TAtlasQuestionInbox.Chosen(mQuestion, -1, 'frei', mAnswer), 'eigene Antwort nicht erlaubt');
  Assert.IsFalse(TAtlasQuestionInbox.Chosen(mQuestion, 5, '', mAnswer), 'nichts gewählt');
  mQuestion.AllowText := True;
  Assert.IsTrue(TAtlasQuestionInbox.Chosen(mQuestion, -1, '  frei  ', mAnswer));
  Assert.AreEqual('frei', mAnswer);
  Assert.IsFalse(TAtlasQuestionInbox.Chosen(mQuestion, -1, '   ', mAnswer), 'leer');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuestionsTests);

end.
