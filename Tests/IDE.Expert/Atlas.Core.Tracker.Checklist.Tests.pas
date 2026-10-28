unit Atlas.Core.Tracker.Checklist.Tests;

// Checklisten in Issue-Beschreibungen (#1273): Erkennung ("- [ ]", "* [x]",
// "+ [X]", nummeriert, eingerückt; nicht in Codeblöcken und Zitaten),
// Fortschritt, Umschalten ohne Änderung am übrigen Text (CRLF, LF, CR),
// Erkennen einer inzwischen geänderten Beschreibung und Anhängen eines Punkts.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerChecklistTests = class
  public
    [Test]
    procedure DetectsVariantsAndNesting;
    [Test]
    procedure IgnoresCodeBlocksAndQuotes;
    [Test]
    procedure CountsProgress;
    [Test]
    procedure FindsByIndex;
    [Test]
    procedure ToggleKeepsCrLf;
    [Test]
    procedure ToggleKeepsLfAndCr;
    [Test]
    procedure ToggleDetectsChangedDescription;
    [Test]
    procedure ToggleAllowsChangesElsewhere;
    [Test]
    procedure AppendBelowLastItem;
    [Test]
    procedure AppendNumberedAndNested;
    [Test]
    procedure AppendRejectsEmpty;
    [Test]
    procedure TaskTargetsRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tracker.Markdown,
  Atlas.Core.Tracker.Checklist;

function Lines(const AParts: TArray<string>; const ABreak: string): string;
begin
  Result := string.Join(ABreak, AParts);
end;

{ TAtlasTrackerChecklistTests }

procedure TAtlasTrackerChecklistTests.DetectsVariantsAndNesting;
var
  mItems: TArray<TAtlasChecklistItem>;
begin
  mItems := TAtlasTrackerChecklist.Items(Lines(TArray<string>.Create('- [ ] eins', '* [x] zwei', '+ [X] drei',
    '1. [ ] vier', '2) [x] fünf', '  - [ ] sechs', '-[ ] kein Punkt', '- [] kein Kästchen', '- [y] kein Kästchen',
    'Text [ ] mitten'), #10));
  Assert.AreEqual(Integer(6), Integer(Length(mItems)));
  Assert.AreEqual('eins', mItems[0].Text);
  Assert.IsFalse(mItems[0].Checked);
  Assert.IsTrue(mItems[1].Checked);
  Assert.IsTrue(mItems[2].Checked, 'großes X');
  Assert.AreEqual('vier', mItems[3].Text);
  Assert.IsFalse(mItems[3].Checked);
  Assert.IsTrue(mItems[4].Checked, 'nummeriert mit Klammer');
  Assert.AreEqual('sechs', mItems[5].Text);
  Assert.AreEqual(Integer(2), mItems[5].Level, 'eingerückt');
  Assert.AreEqual(Integer(5), mItems[5].Line);
  Assert.AreEqual('  - [ ] sechs', mItems[5].LineText);
  Assert.AreEqual(Integer(5), mItems[5].Index);
end;

procedure TAtlasTrackerChecklistTests.IgnoresCodeBlocksAndQuotes;
var
  mItems: TArray<TAtlasChecklistItem>;
begin
  mItems := TAtlasTrackerChecklist.Items(Lines(TArray<string>.Create('```', '- [ ] im Code', '```', '',
    '> - [ ] im Zitat', '', '- [x] echt', '  weiter'), #13#10));
  Assert.AreEqual(Integer(1), Integer(Length(mItems)));
  Assert.AreEqual(Integer(6), mItems[0].Line);
  Assert.AreEqual(Integer(7), mItems[0].LastLine, 'Fortsetzungszeile gehört zum Punkt');
  Assert.AreEqual('echt'#10'weiter', mItems[0].Text);
end;

procedure TAtlasTrackerChecklistTests.CountsProgress;
var
  mProgress: TAtlasChecklistProgress;
begin
  mProgress := TAtlasTrackerChecklist.Progress(Lines(TArray<string>.Create('- [x] a', '- [ ] b', '- [x] c',
    '- [ ] d', '- [x] e', '- kein Kästchen'), #10));
  Assert.AreEqual(Integer(3), mProgress.Done);
  Assert.AreEqual(Integer(5), mProgress.Total);
  Assert.AreEqual('3/5', mProgress.Text);
  Assert.IsTrue(mProgress.Any);
  mProgress := TAtlasTrackerChecklist.Progress('Nur Text');
  Assert.IsFalse(mProgress.Any);
  Assert.AreEqual('', mProgress.Text);
end;

procedure TAtlasTrackerChecklistTests.FindsByIndex;
var
  mItem: TAtlasChecklistItem;
begin
  Assert.IsTrue(TAtlasTrackerChecklist.Find('- [ ] a'#10'- [x] b', 1, mItem));
  Assert.AreEqual('b', mItem.Text);
  Assert.IsFalse(TAtlasTrackerChecklist.Find('- [ ] a', 1, mItem));
  Assert.IsFalse(TAtlasTrackerChecklist.Find('- [ ] a', -1, mItem));
end;

procedure TAtlasTrackerChecklistTests.ToggleKeepsCrLf;
var
  mText, mResult: string;
  mItem: TAtlasChecklistItem;
begin
  mText := 'Titel'#13#10'- [ ] a'#13#10'- [x] b'#13#10;
  Assert.IsTrue(TAtlasTrackerChecklist.Find(mText, 0, mItem));
  Assert.IsTrue(TAtlasTrackerChecklist.Toggle(mText, mItem, mResult));
  Assert.AreEqual('Titel'#13#10'- [x] a'#13#10'- [x] b'#13#10, mResult);
  Assert.IsTrue(TAtlasTrackerChecklist.Find(mText, 1, mItem));
  Assert.IsTrue(TAtlasTrackerChecklist.Toggle(mText, mItem, mResult));
  Assert.AreEqual('Titel'#13#10'- [ ] a'#13#10'- [ ] b'#13#10, mResult);
end;

procedure TAtlasTrackerChecklistTests.ToggleKeepsLfAndCr;
var
  mText, mResult: string;
  mItem: TAtlasChecklistItem;
begin
  mText := 'a'#10#10'1. [X] Groß'#13'  - [ ] tief'#10;
  Assert.IsTrue(TAtlasTrackerChecklist.Find(mText, 0, mItem));
  Assert.IsTrue(TAtlasTrackerChecklist.Toggle(mText, mItem, mResult));
  Assert.AreEqual('a'#10#10'1. [ ] Groß'#13'  - [ ] tief'#10, mResult);
  Assert.IsTrue(TAtlasTrackerChecklist.Find(mText, 1, mItem));
  Assert.IsTrue(TAtlasTrackerChecklist.Toggle(mText, mItem, mResult));
  Assert.AreEqual('a'#10#10'1. [X] Groß'#13'  - [x] tief'#10, mResult);
end;

procedure TAtlasTrackerChecklistTests.ToggleDetectsChangedDescription;
var
  mOld, mResult: string;
  mItem: TAtlasChecklistItem;
begin
  mOld := '- [ ] a'#10'- [ ] b';
  Assert.IsTrue(TAtlasTrackerChecklist.Find(mOld, 1, mItem));
  // Eine Zeile darüber eingefügt: Der Punkt steht nicht mehr an seiner Stelle.
  Assert.IsFalse(TAtlasTrackerChecklist.Toggle('neu'#10'- [ ] a'#10'- [ ] b', mItem, mResult));
  Assert.AreEqual('neu'#10'- [ ] a'#10'- [ ] b', mResult, 'unverändert');
  // Wortlaut geändert.
  Assert.IsFalse(TAtlasTrackerChecklist.Toggle('- [ ] a'#10'- [ ] bb', mItem, mResult));
  // Inzwischen von jemand anderem abgehakt.
  Assert.IsFalse(TAtlasTrackerChecklist.Toggle('- [ ] a'#10'- [x] b', mItem, mResult));
  // Kein Punkt mehr (in einen Codeblock gerutscht).
  Assert.IsFalse(TAtlasTrackerChecklist.Toggle('```'#10'- [ ] b'#10'```', mItem, mResult));
end;

procedure TAtlasTrackerChecklistTests.ToggleAllowsChangesElsewhere;
var
  mResult: string;
  mItem: TAtlasChecklistItem;
begin
  Assert.IsTrue(TAtlasTrackerChecklist.Find('- [ ] a'#10'- [ ] b', 0, mItem));
  Assert.IsTrue(TAtlasTrackerChecklist.Toggle('- [ ] a'#10'- [x] b'#10'Neu', mItem, mResult));
  Assert.AreEqual('- [x] a'#10'- [x] b'#10'Neu', mResult);
end;

procedure TAtlasTrackerChecklistTests.AppendBelowLastItem;
var
  mResult: string;
begin
  Assert.IsTrue(TAtlasTrackerChecklist.Append('- [ ] a'#13#10'- [x] b'#13#10#13#10'Ende', 'c', mResult));
  Assert.AreEqual('- [ ] a'#13#10'- [x] b'#13#10'- [ ] c'#13#10#13#10'Ende', mResult);
  Assert.IsTrue(TAtlasTrackerChecklist.Append('* [ ] a'#10'  weiter'#10#10'Ende', ' x'#13#10'y ', mResult));
  Assert.AreEqual('* [ ] a'#10'  weiter'#10'* [ ] x  y'#10#10'Ende', mResult, 'hinter der Fortsetzung, ohne Umbruch');
end;

procedure TAtlasTrackerChecklistTests.AppendNumberedAndNested;
var
  mResult: string;
begin
  Assert.IsTrue(TAtlasTrackerChecklist.Append('1. [ ] a'#10'2. [x] b'#10, 'c', mResult));
  Assert.AreEqual('1. [ ] a'#10'2. [x] b'#10'3. [ ] c'#10, mResult);
  Assert.IsTrue(TAtlasTrackerChecklist.Append('- [ ] a'#10'  9) [ ] b'#10, 'c', mResult));
  Assert.AreEqual('- [ ] a'#10'  9) [ ] b'#10'  10) [ ] c'#10, mResult);
end;

procedure TAtlasTrackerChecklistTests.AppendRejectsEmpty;
var
  mResult: string;
begin
  Assert.IsFalse(TAtlasTrackerChecklist.Append('- [ ] a'#10, '  ', mResult));
  Assert.AreEqual('- [ ] a'#10, mResult);
  Assert.IsFalse(TAtlasTrackerChecklist.Append('Kein Punkt'#10, 'c', mResult), 'ohne Checkliste');
  Assert.IsTrue(TAtlasTrackerChecklist.Append('- [ ] a'#10, StringOfChar('z', 600), mResult));
  Assert.AreEqual(Integer(Length('- [ ] a'#10'- [ ] ' + #10) + TAtlasTrackerChecklist.MaxItemText),
    Integer(Length(mResult)), 'gekürzt');
end;

procedure TAtlasTrackerChecklistTests.TaskTargetsRoundTrip;
var
  mIndex: Integer;
begin
  Assert.IsTrue(TAtlasTrackerMarkdown.TaskIndexOf(TAtlasTrackerMarkdown.TaskTarget(7), mIndex));
  Assert.AreEqual(Integer(7), mIndex);
  Assert.IsFalse(TAtlasTrackerMarkdown.TaskIndexOf('https://x.de', mIndex));
  Assert.IsFalse(TAtlasTrackerMarkdown.TaskIndexOf('atlas-task:-1', mIndex));
  Assert.IsFalse(TAtlasTrackerMarkdown.TaskIndexOf('atlas-task:', mIndex));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerChecklistTests);

end.
