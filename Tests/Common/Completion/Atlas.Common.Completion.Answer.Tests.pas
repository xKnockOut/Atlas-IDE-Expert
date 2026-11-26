unit Atlas.Common.Completion.Answer.Tests;

// Angemeldete Quellen der Vervollständigung: Reihenfolge der Anmeldung, Halt bei der ersten Antwort, leere Stellen,
// Antwort mit einem Eintrag allein.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompletionAnswerTests = class
  public
    [Test]
    procedure SourcesRunInOrderUntilAnswered;
    [Test]
    procedure EmptySlotGoesOn;
    [Test]
    procedure AnswerWithReplacesExclusive;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Completion.Contract,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Answer;

/// <summary>Quelle, die ihren Namen an ALog hängt und mit AOutcome endet.</summary>
function LoggingSource(const AName: string; AOutcome: TCompletionOutcome; ALog: TStringBuilder): TCompletionSource;
begin
  Result :=
    function(ARequest: TCompletionRequest; AAnswer: TCompletionAnswer): TCompletionOutcome
    begin
      ALog.Append(AName);
      Result := AOutcome;
    end;
end;

{ TCompletionAnswerTests }

procedure TCompletionAnswerTests.SourcesRunInOrderUntilAnswered;
var
  mSources: TCompletionSources;
  mRequest: TCompletionRequest;
  mAnswer: TCompletionAnswer;
  mLog: TStringBuilder;
begin
  mSources := nil;
  mRequest := nil;
  mAnswer := nil;
  mLog := nil;
  try
    mSources := TCompletionSources.Create;
    mRequest := TCompletionRequest.Create('', '', TTextPosition.Create(0, 0));
    mAnswer := TCompletionAnswer.Create;
    mLog := TStringBuilder.Create;
    mSources.Add(TCompletionSlot.CreateMethod, LoggingSource('a', TCompletionOutcome.Next, mLog));
    mSources.Add(TCompletionSlot.CreateMethod, LoggingSource('b', TCompletionOutcome.Answered, mLog));
    mSources.Add(TCompletionSlot.CreateMethod, LoggingSource('c', TCompletionOutcome.Next, mLog));
    Assert.AreEqual<TCompletionOutcome>(TCompletionOutcome.Answered,
      mSources.Run(TCompletionSlot.CreateMethod, mRequest, mAnswer));
    Assert.AreEqual('ab', mLog.ToString);
  finally
    mLog.Free;
    mAnswer.Free;
    mRequest.Free;
    mSources.Free;
  end;
end;

procedure TCompletionAnswerTests.EmptySlotGoesOn;
var
  mSources: TCompletionSources;
  mRequest: TCompletionRequest;
  mAnswer: TCompletionAnswer;
begin
  mSources := nil;
  mRequest := nil;
  mAnswer := nil;
  try
    mSources := TCompletionSources.Create;
    mRequest := TCompletionRequest.Create('', '', TTextPosition.Create(0, 0));
    mAnswer := TCompletionAnswer.Create;
    Assert.AreEqual<TCompletionOutcome>(TCompletionOutcome.Next,
      mSources.Run(TCompletionSlot.CreateMethod, mRequest, mAnswer));
  finally
    mAnswer.Free;
    mRequest.Free;
    mSources.Free;
  end;
end;

procedure TCompletionAnswerTests.AnswerWithReplacesExclusive;
var
  mAnswer: TCompletionAnswer;
  mItem: TCompletionItem;
begin
  mAnswer := TCompletionAnswer.Create;
  try
    mAnswer.Exclusive.Incomplete := True;
    mItem := Default(TCompletionItem);
    mItem.Name := 'Eins';
    Assert.AreEqual<TCompletionOutcome>(TCompletionOutcome.Answered, mAnswer.AnswerWith(mItem));
    Assert.AreEqual(1, Integer(Length(mAnswer.Exclusive.Items)));
    Assert.AreEqual('Eins', mAnswer.Exclusive.Items[0].Name);
    Assert.IsFalse(mAnswer.Exclusive.Incomplete);
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionAnswerTests);

end.
