unit Atlas.Common.Editing.Completion.CreateMethod.Tests;

// Quelle „Methode aus Aufruf anlegen“ (#472) der Vervollständigung: nach "(" allein oder leer, mit Strg+Leer oben
// in der Liste; ohne Aufruf am Cursor kein Eintrag.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TEditingCreateMethodCompletionTests = class
  public
    /// <summary>Nach "(": nur der Eintrag, Text an der Aufrufstelle bleibt.</summary>
    [Test]
    procedure ParenAnswersAlone;
    /// <summary>Nach "(" ohne Angebot: leere Antwort statt der allgemeinen Liste.</summary>
    [Test]
    procedure ParenWithoutOfferIsEmpty;
    /// <summary>Mit Strg+Leer auf dem Namen: oben in der Liste, die Liste geht weiter.</summary>
    [Test]
    procedure NameGoesToHints;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Completion.Contract,
  Atlas.Common.Completion.Request,
  Atlas.Common.Completion.Answer,
  Atlas.Common.Editing.Completion.CreateMethod;

const
  cText =
    'unit U;'#10 +
    'implementation'#10 +
    'procedure Haupt;'#10 +
    'begin'#10 +
    '  Rechne(1);'#10 +
    'end;'#10 +
    'end.';

/// <summary>Angebot mit festem Titel, wenn AOffer.</summary>
function Creator(AOffer: Boolean): TEditingCreateMethodFunc;
begin
  Result :=
    function(ARequest: TCompletionRequest; out ATitle, ADetail: string; out AEdits: TArray<TTextEdit>): Boolean
    begin
      ATitle := 'Methode Rechne anlegen';
      ADetail := 'procedure Rechne(Value: Integer)';
      AEdits := nil;
      Result := AOffer;
    end;
end;

/// <summary>Lässt die Quelle an APosition mit ATrigger laufen.</summary>
function Run(AOffer: Boolean; const APosition: TTextPosition; const ATrigger: string; AAnswer: TCompletionAnswer):
  TCompletionOutcome;
var
  mTree: TSyntaxTree;
  mRequest: TCompletionRequest;
  mSource: TCompletionSource;
begin
  mSource := TEditingCreateMethodCompletion.Source(Creator(AOffer));
  mTree := nil;
  mRequest := nil;
  try
    mTree := TPascalParser.Parse(cText);
    mRequest := TCompletionRequest.Create(cText, 'C:\P\U.pas', APosition);
    mRequest.Tree := mTree;
    mRequest.Trigger := ATrigger;
    Result := mSource(mRequest, AAnswer);
  finally
    mRequest.Free;
    mTree.Free;
  end;
end;

{ TEditingCreateMethodCompletionTests }

procedure TEditingCreateMethodCompletionTests.ParenAnswersAlone;
var
  mAnswer: TCompletionAnswer;
begin
  mAnswer := TCompletionAnswer.Create;
  try
    Assert.AreEqual<TCompletionOutcome>(TCompletionOutcome.Answered,
      Run(True, TTextPosition.Create(4, 9), '(', mAnswer));
    Assert.AreEqual(1, Integer(Length(mAnswer.Exclusive.Items)));
    Assert.AreEqual('Methode Rechne anlegen', mAnswer.Exclusive.Items[0].Name);
    Assert.AreEqual('create', mAnswer.Exclusive.Items[0].Action);
    Assert.AreEqual(cKindMethod, mAnswer.Exclusive.Items[0].Kind);
    Assert.AreEqual('', mAnswer.Exclusive.Items[0].TextEdit.NewText);
  finally
    mAnswer.Free;
  end;
end;

procedure TEditingCreateMethodCompletionTests.ParenWithoutOfferIsEmpty;
var
  mAnswer: TCompletionAnswer;
begin
  mAnswer := TCompletionAnswer.Create;
  try
    Assert.AreEqual<TCompletionOutcome>(TCompletionOutcome.Answered,
      Run(False, TTextPosition.Create(4, 9), '(', mAnswer));
    Assert.AreEqual(0, Integer(Length(mAnswer.Exclusive.Items)));
  finally
    mAnswer.Free;
  end;
end;

procedure TEditingCreateMethodCompletionTests.NameGoesToHints;
var
  mAnswer: TCompletionAnswer;
begin
  mAnswer := TCompletionAnswer.Create;
  try
    Assert.AreEqual<TCompletionOutcome>(TCompletionOutcome.Next, Run(True, TTextPosition.Create(4, 5), '', mAnswer));
    Assert.AreEqual(1, Integer(Length(mAnswer.Hints)));
    Assert.AreEqual('Rechne', mAnswer.Hints[0].TextEdit.NewText);
    Assert.AreEqual(0, Integer(Length(mAnswer.Exclusive.Items)));
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TEditingCreateMethodCompletionTests);

end.
