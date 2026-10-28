unit Atlas.UI.Tracker.TimeDialog.Tests;

// Tests des Dialogs „… buchen?“ (#1267) und der Liste offener Buchungen:
// Frage und gerundete Dauer, Buchung aus den Feldern, ungültige Dauer,
// Fehler im Dialog ohne Wiederholung, Zeiterfassung aus, GitHub ohne
// Kommentar nur lokal, Verwerfen und die Zeilen der Liste.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerTimeDialogTests = class
  private
    FSaved: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure QuestionAndRoundedDuration;
    [Test]
    procedure ItemFromFields;
    [Test]
    procedure InvalidDurationBooksNothing;
    /// <summary>Fehler bleiben im Dialog, nichts wird wiederholt; Erfolg schließt mit „gebucht“.</summary>
    [Test]
    procedure BookShowsErrorThenSucceeds;
    [Test]
    procedure TrackingOffLocksBook;
    /// <summary>GitHub: ohne Häkchen nur lokal als gebucht, mit Häkchen als Kommentar gesendet.</summary>
    [Test]
    procedure CommentModeOnlyWithCheck;
    [Test]
    procedure DiscardAndLater;
    [Test]
    procedure ListRowText;
  end;

implementation

uses
  System.SysUtils,
  System.UITypes,
  System.DateUtils,
  Vcl.Controls,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.TimeLog,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.TimeDialog,
  Atlas.UI.Tracker.TimeList;

function Day: TDateTime;
begin
  Result := EncodeDate(2026, 10, 28);
end;

{ TAtlasTrackerTimeDialogTests }

procedure TAtlasTrackerTimeDialogTests.Setup;
begin
  FSaved := Ord(TAtlasStrings.Language);
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasTrackerTimeDialogTests.TearDown;
begin
  TAtlasStrings.Language := TAtlasLanguage(FSaved);
end;

procedure TAtlasTrackerTimeDialogTests.QuestionAndRoundedDuration;
var
  mDialog: TAtlasTrackerTimeDialog;
begin
  mDialog := TAtlasTrackerTimeDialog.CreateDialog(nil, 'ATL-123', 87 * 60, 5, Day, 'Parser repariert',
    TAtlasTimeBookMode.WorkItem);
  try
    Assert.AreEqual('1 h 25 min auf ATL-123 buchen?', mDialog.Question.Caption);
    Assert.AreEqual('1:25', mDialog.DurationEdit.Text, 'auf 5 Minuten gerundet');
    Assert.AreEqual('Parser repariert', mDialog.TextMemo.Text);
    Assert.AreEqual(Ord(TAtlasTimeDecision.Later), Ord(mDialog.Decision), 'ohne Klick: später');
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerTimeDialogTests.ItemFromFields;
var
  mDialog: TAtlasTrackerTimeDialog;
  mItem: TAtlasTrackerWorkItem;
begin
  mDialog := TAtlasTrackerTimeDialog.CreateDialog(nil, 'ATL-123', 60 * 60, 5, Day, '',
    TAtlasTimeBookMode.WorkItem);
  try
    mDialog.SetWorkTypes(TArray<string>.Create('Entwicklung', 'Test'));
    mDialog.DurationEdit.Text := '1 h 30 min';
    mDialog.WorkTypeBox.Value := ' Entwicklung ';
    mDialog.TextMemo.Text := 'Zeile 1'#13#10'Zeile 2';
    Assert.IsTrue(mDialog.Item(mItem));
    Assert.AreEqual(90, mItem.Minutes);
    Assert.AreEqual('Entwicklung', mItem.WorkType);
    Assert.AreEqual('Zeile 1'#10'Zeile 2', mItem.Text);
    Assert.IsTrue(SameDate(Day, mItem.Date));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerTimeDialogTests.InvalidDurationBooksNothing;
var
  mDialog: TAtlasTrackerTimeDialog;
  mCalls: Integer;
begin
  mCalls := 0;
  mDialog := TAtlasTrackerTimeDialog.CreateDialog(nil, 'ATL-123', 30 * 60, 5, Day, '',
    TAtlasTimeBookMode.WorkItem);
  try
    mDialog.OnBook :=
      procedure(const AItem: TAtlasTrackerWorkItem; const ADone: TAtlasTrackerSendDone)
      begin
        Inc(mCalls);
      end;
    mDialog.DurationEdit.Text := 'viel';
    mDialog.BookButton.Click;
    Assert.AreEqual(0, mCalls);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.TimeBookInvalid), mDialog.Note.Caption);
    Assert.AreEqual(Integer(mrNone), Integer(mDialog.ModalResult));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerTimeDialogTests.BookShowsErrorThenSucceeds;
var
  mDialog: TAtlasTrackerTimeDialog;
  mCalls: Integer;
  mPending: TAtlasTrackerSendDone;
  mBooked: TAtlasTrackerWorkItem;
begin
  mCalls := 0;
  mPending := nil;
  mDialog := TAtlasTrackerTimeDialog.CreateDialog(nil, 'ATL-123', 85 * 60, 5, Day, 'Text',
    TAtlasTimeBookMode.WorkItem);
  try
    mDialog.OnBook :=
      procedure(const AItem: TAtlasTrackerWorkItem; const ADone: TAtlasTrackerSendDone)
      begin
        Inc(mCalls);
        mBooked := AItem;
        mPending := ADone;
      end;
    mDialog.BookButton.Click;
    Assert.AreEqual(1, mCalls);
    Assert.AreEqual(85, mBooked.Minutes);
    Assert.IsTrue(mDialog.Sending);
    Assert.IsFalse(mDialog.LaterButton.Enabled, 'während der Buchung nicht schließen');
    mDialog.BookButton.Click;
    Assert.AreEqual(1, mCalls, 'keine zweite Buchung');
    mPending(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Unauthorized, 403, ''));
    Assert.IsFalse(mDialog.Sending);
    Assert.AreEqual('Keine Schreibrechte für ATL-123 (403).', mDialog.Note.Caption);
    Assert.AreEqual(Integer(mrNone), Integer(mDialog.ModalResult), 'Dialog bleibt offen');
    Assert.AreEqual(1, mCalls, 'nichts wird wiederholt');
    mDialog.BookButton.Click;
    Assert.AreEqual(2, mCalls);
    mPending(TAtlasTrackerWriteResult.Ok);
    Assert.IsTrue(mDialog.Sent);
    Assert.AreEqual(Ord(TAtlasTimeDecision.Booked), Ord(mDialog.Decision));
    Assert.AreEqual(85, mDialog.BookedItem.Minutes);
    Assert.AreEqual(Integer(mrOk), Integer(mDialog.ModalResult));
  finally
    mDialog.Free;
  end;
  mPending := nil;
end;

procedure TAtlasTrackerTimeDialogTests.TrackingOffLocksBook;
var
  mDialog: TAtlasTrackerTimeDialog;
  mPending: TAtlasTrackerSendDone;
begin
  mPending := nil;
  mDialog := TAtlasTrackerTimeDialog.CreateDialog(nil, 'ATL-123', 30 * 60, 5, Day, '',
    TAtlasTimeBookMode.WorkItem);
  try
    mDialog.OnBook :=
      procedure(const AItem: TAtlasTrackerWorkItem; const ADone: TAtlasTrackerSendDone)
      begin
        mPending := ADone;
      end;
    mDialog.IsTrackingOff :=
      function(const AResult: TAtlasTrackerWriteResult): Boolean
      begin
        Result := AResult.Status = 400;
      end;
    mDialog.BookButton.Click;
    mPending(TAtlasTrackerWriteResult.Failed(TAtlasCiFetchError.Invalid, 400, 'Time tracking is disabled'));
    Assert.IsTrue(mDialog.TrackingOff);
    Assert.IsFalse(mDialog.BookButton.Enabled);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.TimeBookOff), mDialog.Note.Caption);
    Assert.IsTrue(mDialog.LaterButton.Enabled, 'Später bleibt');
    Assert.IsTrue(mDialog.DiscardButton.Enabled, 'Verwerfen bleibt');
  finally
    mDialog.Free;
  end;
  mPending := nil;
end;

procedure TAtlasTrackerTimeDialogTests.CommentModeOnlyWithCheck;
var
  mDialog: TAtlasTrackerTimeDialog;
  mCalls: Integer;
begin
  mCalls := 0;
  mDialog := TAtlasTrackerTimeDialog.CreateDialog(nil, '#753', 45 * 60, 5, Day, '', TAtlasTimeBookMode.Comment);
  try
    mDialog.OnBook :=
      procedure(const AItem: TAtlasTrackerWorkItem; const ADone: TAtlasTrackerSendDone)
      begin
        Inc(mCalls);
        ADone(TAtlasTrackerWriteResult.Ok);
      end;
    Assert.IsFalse(mDialog.AsCommentCheck.Checked, 'Vorgabe aus');
    mDialog.BookButton.Click;
    Assert.AreEqual(0, mCalls, 'ohne Häkchen nichts gesendet');
    Assert.AreEqual(Ord(TAtlasTimeDecision.Booked), Ord(mDialog.Decision));
    Assert.IsFalse(mDialog.Sent, 'nur lokal vermerkt');
  finally
    mDialog.Free;
  end;
  mDialog := TAtlasTrackerTimeDialog.CreateDialog(nil, '#753', 45 * 60, 5, Day, '', TAtlasTimeBookMode.Comment);
  try
    mDialog.OnBook :=
      procedure(const AItem: TAtlasTrackerWorkItem; const ADone: TAtlasTrackerSendDone)
      begin
        Inc(mCalls);
        ADone(TAtlasTrackerWriteResult.Ok);
      end;
    mDialog.AsCommentCheck.Checked := True;
    mDialog.BookButton.Click;
    Assert.AreEqual(1, mCalls, 'mit Häkchen als Kommentar');
    Assert.IsTrue(mDialog.Sent);
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerTimeDialogTests.DiscardAndLater;
var
  mDialog: TAtlasTrackerTimeDialog;
begin
  mDialog := TAtlasTrackerTimeDialog.CreateDialog(nil, 'ATL-123', 30 * 60, 5, Day, '',
    TAtlasTimeBookMode.WorkItem);
  try
    Assert.AreEqual(Integer(mrCancel), Integer(mDialog.LaterButton.ModalResult));
    Assert.IsTrue(mDialog.LaterButton.Cancel, 'Esc = Später');
    mDialog.DiscardButton.Click;
    Assert.AreEqual(Ord(TAtlasTimeDecision.Discarded), Ord(mDialog.Decision));
    Assert.AreEqual(Integer(mrAbort), Integer(mDialog.ModalResult));
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasTrackerTimeDialogTests.ListRowText;
var
  mItem: TAtlasTimeOpen;
  mText: string;
begin
  mItem.Issue := TAtlasTimeIssue.Create('youtrack', 'https://yt.beispiel.de', 'ATL', 'ATL-123');
  mItem.Seconds := 85 * 60;
  mItem.FirstDay := Trunc(Day) - 1;
  mItem.LastDay := Trunc(Day);
  mText := TAtlasTrackerTimeListDialog.RowText(mItem);
  Assert.IsTrue(mText.StartsWith('ATL-123 · 1 h 25 min · '), mText);
  Assert.IsTrue(mText.Contains(DateToStr(Day - 1)) and mText.Contains(DateToStr(Day)), mText);
  mItem.FirstDay := mItem.LastDay;
  Assert.AreEqual('ATL-123 · 1 h 25 min · ' + DateToStr(Day), TAtlasTrackerTimeListDialog.RowText(mItem));
end;

end.
