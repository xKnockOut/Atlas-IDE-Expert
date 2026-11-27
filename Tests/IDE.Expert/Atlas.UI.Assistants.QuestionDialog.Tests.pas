unit Atlas.UI.Assistants.QuestionDialog.Tests;

// Fenster „KI-Assistent fragt“ (#2620): Optionen und eigene Antwort, „Antworten“ erst mit Auswahl, Antwort, Später
// und Abbrechen an den Eingang, neue Frage ersetzt den Inhalt; dazu die Kopfzeile, Zellen und Sperrgründe des
// Fensters „Atlas-KI-Protokoll“ (#2049).

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Assistants.QuestionDialog;

type
  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasQuestionDialogTests = class
  private
    FDialog: TAtlasQuestionDialog;
    FId: string;
    FAnswer: string;
    FLater: string;
    FCancelled: string;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsOptionsAndOwnAnswer;
    [Test]
    procedure AnswerNeedsAChoice;
    [Test]
    procedure TypingChoosesOwnAnswer;
    [Test]
    procedure WithoutOptionsOnlyText;
    [Test]
    procedure LaterAndCancelReachTheInbox;
    [Test]
    procedure NextQuestionReplacesContent;
  end;

  [TestFixture]
  [Category('Atlas.IDE.Assistants')]
  TAtlasAssistantsLogFrameTests = class
  public
    [Test]
    procedure CellsOfAnEdit;
    [Test]
    procedure CellsOfABuildAndAQuestion;
    [Test]
    procedure HeaderCountsTheSession;
    [Test]
    procedure BlockTextsSayWhy;
    [Test]
    procedure FrameShowsEntriesWithoutWindow;
    [Test]
    procedure FilterShowsOneAssistant;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Assistants.Log,
  Atlas.UI.Assistants.Strings,
  Atlas.UI.Assistants.LogFrame,
  Atlas.Core.Assistants.Questions,
  Atlas.Text.AssistantOrigin;

/// <summary>Assistent ohne Sitzung bzw. unbekannt mit ''.</summary>
function Who(const AClient: string): TAtlasAssistantOrigin;
begin
  Result := TAtlasAssistantOrigin.Make(AClient, '');
end;

function Sample(const AId: string; const AOptions: TArray<string>; AAllowText: Boolean): TAtlasQuestion;
begin
  Result := Default(TAtlasQuestion);
  Result.Id := AId;
  Result.Question := 'Welche Unit soll die Methode bekommen?';
  Result.Options := AOptions;
  Result.AllowText := AAllowText;
  Result.Client := 'Assistent A';
end;

{ TAtlasQuestionDialogTests }

procedure TAtlasQuestionDialogTests.SetUp;
begin
  FId := '';
  FAnswer := '';
  FLater := '';
  FCancelled := '';
  FDialog := TAtlasQuestionDialog.CreateQuestion(nil);
  FDialog.OnAnswer :=
    procedure(const AId, AAnswer: string)
    begin
      FId := AId;
      FAnswer := AAnswer;
    end;
  FDialog.OnLater :=
    procedure(const AId: string)
    begin
      FLater := AId;
    end;
  FDialog.OnCancel :=
    procedure(const AId: string)
    begin
      FCancelled := AId;
    end;
end;

procedure TAtlasQuestionDialogTests.TearDown;
begin
  FreeAndNil(FDialog);
  FId := '';
  FAnswer := '';
  FLater := '';
  FCancelled := '';
end;

procedure TAtlasQuestionDialogTests.ShowsOptionsAndOwnAnswer;
begin
  FDialog.ShowQuestion(Sample('q1', TArray<string>.Create('Atlas.IDE.Tests.Run', 'Atlas.Core.Tests.Run'), True), 2);
  Assert.AreEqual(TAtlasQuestionDialog.CaptionFor('Assistent A'), FDialog.Caption);
  Assert.Contains(FDialog.Caption, 'Assistent A');
  Assert.AreEqual('Welche Unit soll die Methode bekommen?', FDialog.TextLabel.Caption);
  Assert.AreEqual(2, Integer(Length(FDialog.Options)));
  Assert.AreEqual('Atlas.Core.Tests.Run', FDialog.Options[1].Caption);
  Assert.IsNotNull(FDialog.OwnAnswer, 'eigene Antwort erlaubt');
  Assert.IsNotNull(FDialog.AnswerEdit);
  Assert.Contains(FDialog.MoreLabel.Caption, '2');
end;

procedure TAtlasQuestionDialogTests.AnswerNeedsAChoice;
begin
  FDialog.ShowQuestion(Sample('q1', TArray<string>.Create('A', 'B'), False), 0);
  Assert.IsFalse(FDialog.AnswerButton.Enabled, 'ohne Auswahl keine Antwort');
  Assert.IsNull(FDialog.OwnAnswer, 'keine eigene Antwort');
  FDialog.Options[1].Checked := True;
  Assert.IsTrue(FDialog.AnswerButton.Enabled);
  FDialog.AnswerButton.Click;
  Assert.AreEqual('q1', FId);
  Assert.AreEqual('B', FAnswer);
end;

procedure TAtlasQuestionDialogTests.TypingChoosesOwnAnswer;
begin
  FDialog.ShowQuestion(Sample('q2', TArray<string>.Create('A'), True), 0);
  FDialog.AnswerEdit.Text := 'Atlas.UI.Tests.Run';
  Assert.IsTrue(FDialog.OwnAnswer.Checked, 'Tippen wählt die eigene Antwort');
  FDialog.AnswerButton.Click;
  Assert.AreEqual('Atlas.UI.Tests.Run', FAnswer);
end;

procedure TAtlasQuestionDialogTests.WithoutOptionsOnlyText;
begin
  FDialog.ShowQuestion(Sample('q3', nil, True), 0);
  Assert.AreEqual(0, Integer(Length(FDialog.Options)));
  Assert.IsNull(FDialog.OwnAnswer);
  Assert.IsFalse(FDialog.AnswerButton.Enabled);
  FDialog.AnswerEdit.Text := 'TRunner';
  Assert.IsTrue(FDialog.AnswerButton.Enabled);
  FDialog.AnswerButton.Click;
  Assert.AreEqual('TRunner', FAnswer);
end;

procedure TAtlasQuestionDialogTests.LaterAndCancelReachTheInbox;
begin
  FDialog.ShowQuestion(Sample('q4', TArray<string>.Create('A'), False), 0);
  FDialog.LaterButton.Click;
  Assert.AreEqual('q4', FLater);
  FDialog.CancelButton.Click;
  Assert.AreEqual('q4', FCancelled);
  Assert.AreEqual('', FAnswer, 'nichts beantwortet');
end;

procedure TAtlasQuestionDialogTests.NextQuestionReplacesContent;
begin
  FDialog.ShowQuestion(Sample('q5', TArray<string>.Create('A', 'B', 'C'), True), 1);
  FDialog.ShowQuestion(Sample('q6', TArray<string>.Create('X'), False), 0);
  Assert.AreEqual('q6', FDialog.Question.Id);
  Assert.AreEqual(1, Integer(Length(FDialog.Options)));
  Assert.IsNull(FDialog.AnswerEdit);
  Assert.AreEqual('', FDialog.MoreLabel.Caption);
  FDialog.SetWaiting(3);
  Assert.Contains(FDialog.MoreLabel.Caption, '3');
end;

{ TAtlasAssistantsLogFrameTests }

function EditEntry: TAtlasAssistantsLogEntry;
begin
  Result := TAtlasAssistantsLog.EditEntry(TAtlasAssistantsLogKind.Edited, 'C:\P\Atlas.UI.Tracker.Strings.pas', Who(''),
    'a'#10'b'#10'c'#10'd'#10'e'#10, 'a'#10'b'#10'C'#10'D'#10'X'#10'd'#10'e'#10);
  Result.Time := EncodeTime(10, 41, 12, 0);
  Result.Method := 'TStrings.Load';
end;

procedure TAtlasAssistantsLogFrameTests.CellsOfAnEdit;
var
  mCells: TArray<string>;
begin
  mCells := TAtlasAssistantsLogTexts.Cells(EditEntry);
  Assert.AreEqual(5, Integer(Length(mCells)));
  Assert.AreEqual('10:41:12', mCells[0]);
  Assert.AreEqual(TAtlasAssistantsLogTexts.KindCaption(TAtlasAssistantsLogKind.Edited), mCells[1]);
  Assert.AreEqual('', mCells[2], 'älterer Server: kein Assistent');
  Assert.AreEqual('Atlas.UI.Tracker.Strings.pas · ' + TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LogLines,
    [3, 5]) + ' · TStrings.Load', mCells[3]);
  Assert.AreEqual(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LogPlusMinus, [3, 1]), mCells[4]);
end;

procedure TAtlasAssistantsLogFrameTests.CellsOfABuildAndAQuestion;
var
  mEntry: TAtlasAssistantsLogEntry;
  mCells: TArray<string>;
begin
  mEntry := TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Build, 'C:\P\Atlas.IDE.Tracker.dproj',
    TAtlasAssistantOrigin.Make('Assistent A', '3f2a'), 'check: 0 Fehler, 2 Warnungen');
  mCells := TAtlasAssistantsLogTexts.Cells(mEntry);
  Assert.AreEqual('Assistent A · 3f2a', mCells[2]);
  Assert.AreEqual('Atlas.IDE.Tracker.dproj', mCells[3]);
  Assert.AreEqual('check: 0 Fehler, 2 Warnungen', mCells[4]);
  mEntry := TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Question, '', Who('Assistent A'), 'Welche? → B');
  mCells := TAtlasAssistantsLogTexts.Cells(mEntry);
  Assert.AreEqual('Assistent A', mCells[2]);
  Assert.AreEqual('', mCells[3]);
  Assert.AreEqual('Welche? → B', mCells[4]);
end;

procedure TAtlasAssistantsLogFrameTests.HeaderCountsTheSession;
var
  mCounts: TAtlasAssistantsLogCounts;
  mText: string;
begin
  Assert.AreEqual('', TAtlasAssistantsLogTexts.HeaderText(Default(TAtlasAssistantsLogCounts), 0));
  mCounts := Default(TAtlasAssistantsLogCounts);
  mCounts.Edits := 3;
  mCounts.Builds := 1;
  mCounts.Refused := 1;
  mText := TAtlasAssistantsLogTexts.HeaderText(mCounts, EncodeTime(10, 38, 0, 0));
  Assert.Contains(mText, '10:38');
  Assert.AreEqual(TAtlasAssistantsStrings.Fmt(TAtlasAssistantsTextId.LogHeader, ['10:38', 3, 1, 1]), mText);
end;

procedure TAtlasAssistantsLogFrameTests.BlockTextsSayWhy;
begin
  Assert.AreEqual('', TAtlasAssistantsLogTexts.BlockText(TAtlasLogRevertBlock.None));
  Assert.AreEqual(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.LogRevertChanged),
    TAtlasAssistantsLogTexts.BlockText(TAtlasLogRevertBlock.ChangedSince));
  Assert.IsNotEmpty(TAtlasAssistantsLogTexts.BlockText(TAtlasLogRevertBlock.TooLarge));
  Assert.IsNotEmpty(TAtlasAssistantsLogTexts.BlockText(TAtlasLogRevertBlock.AlreadyReverted));
end;

procedure TAtlasAssistantsLogFrameTests.FrameShowsEntriesWithoutWindow;
var
  mFrame: TAtlasAssistantsLogFrame;
  mCounts: TAtlasAssistantsLogCounts;
begin
  mFrame := TAtlasAssistantsLogFrame.Create(nil);
  try
    mCounts := Default(TAtlasAssistantsLogCounts);
    mCounts.Edits := 1;
    mFrame.SetEntries(TArray<TAtlasAssistantsLogEntry>.Create(EditEntry), mCounts, EncodeTime(10, 38, 0, 0));
    Assert.Contains(mFrame.Header.Caption, '10:38');
    Assert.IsTrue(mFrame.Buttons[TAtlasLogButton.Session].Enabled, 'eine Änderung: Unterschied der Sitzung möglich');
    Assert.IsFalse(mFrame.Buttons[TAtlasLogButton.Revert].Enabled, 'ohne Auswahl nichts zurückzunehmen');
    mFrame.SetRevertState(TAtlasLogRevertBlock.ChangedSince);
    Assert.IsFalse(mFrame.Buttons[TAtlasLogButton.Revert].Enabled);
    Assert.AreEqual(TAtlasAssistantsLogTexts.BlockText(TAtlasLogRevertBlock.ChangedSince), mFrame.Note.Caption);
    mFrame.SetEntries(nil, Default(TAtlasAssistantsLogCounts), 0);
    Assert.IsFalse(mFrame.Buttons[TAtlasLogButton.Clear].Enabled);
  finally
    mFrame.Free;
  end;
end;

/// <summary>Erster Eintrag; Default ohne.</summary>
function First(const AEntries: TArray<TAtlasAssistantsLogEntry>): TAtlasAssistantsLogEntry;
begin
  Result := Default(TAtlasAssistantsLogEntry);
  if AEntries <> nil then
  begin
    Result := AEntries[0];
  end;
end;

procedure TAtlasAssistantsLogFrameTests.FilterShowsOneAssistant;
var
  mFrame: TAtlasAssistantsLogFrame;
  mA, mB: TAtlasAssistantOrigin;
  mEntries: TArray<TAtlasAssistantsLogEntry>;
begin
  mA := TAtlasAssistantOrigin.Make('Assistent A', '3f2a');
  mB := TAtlasAssistantOrigin.Make('Assistent A', '77c0');
  mEntries := TArray<TAtlasAssistantsLogEntry>.Create(
    TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Build, 'A.dproj', mA, 'ok'),
    TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Build, 'B.dproj', mB, 'ok'),
    TAtlasAssistantsLog.PlainEntry(TAtlasAssistantsLogKind.Refused, 'C.pas', mA, 'nein'));
  mFrame := TAtlasAssistantsLogFrame.Create(nil);
  try
    mFrame.SetEntries(mEntries, Default(TAtlasAssistantsLogCounts), EncodeTime(10, 38, 0, 0));
    Assert.AreEqual(3, Integer(Length(mFrame.AssistantBox.Shown)));
    // Zwei Sitzungen desselben Clients sind zwei Assistenten.
    mFrame.AssistantBox.ShowAssistant(mB, True);
    Assert.AreEqual(1, Integer(Length(mFrame.AssistantBox.Shown)));
    Assert.AreEqual('B.dproj', First(mFrame.AssistantBox.Shown).FileName);
    mFrame.AssistantBox.ShowAssistant(mA, True);
    Assert.AreEqual(2, Integer(Length(mFrame.AssistantBox.Shown)));
    // Neue Einträge folgen dem Filter; ohne Einträge des Assistenten wieder alle.
    mFrame.SetEntries(Copy(mEntries, 1, 1), Default(TAtlasAssistantsLogCounts), EncodeTime(10, 38, 0, 0));
    Assert.AreEqual(1, Integer(Length(mFrame.AssistantBox.Shown)));
    Assert.AreEqual('B.dproj', First(mFrame.AssistantBox.Shown).FileName);
    mFrame.AssistantBox.ShowAssistant(mA, False);
    Assert.AreEqual(1, Integer(Length(mFrame.AssistantBox.Shown)));
  finally
    mFrame.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasQuestionDialogTests);
  TDUnitX.RegisterTestFixture(TAtlasAssistantsLogFrameTests);

end.
