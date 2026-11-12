unit Atlas.UI.Tracker.SprintDialog.Tests;

// Tests der Rückfrage „in den laufenden Sprint aufnehmen?“ beim Beginnen
// (#2128): Text mit und ohne Ende des Sprints, Knöpfe und Antworten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerSprintDialogTests = class
  private
    FSaved: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure QuestionNamesBoardAndSprint;
    [Test]
    procedure ButtonsGiveAnswers;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.UITypes,
  Atlas.Core.Tracker.Contract,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.SprintDialog;

procedure TAtlasTrackerSprintDialogTests.Setup;
begin
  FSaved := Ord(TAtlasStrings.Language);
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasTrackerSprintDialogTests.TearDown;
begin
  TAtlasStrings.Language := TAtlasLanguage(FSaved);
end;

procedure TAtlasTrackerSprintDialogTests.QuestionNamesBoardAndSprint;
var
  mText: string;
begin
  // Mittag UTC: in jeder Zeitzone derselbe Tag.
  mText := TAtlasTrackerSprintDialog.QuestionText('ATL-2071', 'Absturz',
    TAtlasTrackerSprintRef.Create('Atlas-Board', 'Sprint 47', EncodeDateTime(2026, 11, 19, 12, 0, 0, 0)));
  Assert.AreEqual('ATL-2071 „Absturz“ ist in keinem Sprint von „Atlas-Board“.' + sLineBreak +
    'In den laufenden Sprint „Sprint 47“ (bis 19.11.) aufnehmen?', mText);
  mText := TAtlasTrackerSprintDialog.QuestionText('ATL-2071', 'Absturz',
    TAtlasTrackerSprintRef.Create('Atlas-Board', 'Sprint 47', 0));
  Assert.IsTrue(mText.EndsWith('In den laufenden Sprint „Sprint 47“ aufnehmen?'), 'ohne Ende kein „bis“');
end;

procedure TAtlasTrackerSprintDialogTests.ButtonsGiveAnswers;
var
  mDialog: TAtlasTrackerSprintDialog;
begin
  mDialog := TAtlasTrackerSprintDialog.CreateDialog(nil, 'ATL-2071', 'Absturz',
    TAtlasTrackerSprintRef.Create('Atlas-Board', 'Sprint 47', 0));
  try
    Assert.AreEqual('ATL-2071 beginnen', mDialog.Caption);
    Assert.IsTrue(mDialog.AddButton.Default, 'Eingabe nimmt auf');
    Assert.IsTrue(TAtlasTrackerSprintDialog.AnswerOf(mDialog.AddButton.ModalResult) = TAtlasSprintAnswer.Add);
    Assert.IsTrue(TAtlasTrackerSprintDialog.AnswerOf(mDialog.WithoutButton.ModalResult) =
      TAtlasSprintAnswer.Without);
    Assert.IsTrue(TAtlasTrackerSprintDialog.AnswerOf(mrCancel) = TAtlasSprintAnswer.Cancel);
    Assert.IsFalse(mDialog.DontAskCheck.Checked);
  finally
    mDialog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerSprintDialogTests);

end.
