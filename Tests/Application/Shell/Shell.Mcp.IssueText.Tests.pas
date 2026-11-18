unit Shell.Mcp.IssueText.Tests;

// Tests der Ausgabe von get_current_issue (#2051): Text wie im Mockup je Abschnitt, Namen der Abschnitte, JSON des
// Abschnitts, relative Zeiten auf Deutsch und Englisch.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpIssueTextTests = class
  public
    [Test]
    procedure SummaryTextLikeMockup;
    [Test]
    procedure BodyAndCommentsText;
    [Test]
    procedure WithoutTrackerDataSaysSo;
    [Test]
    procedure ParseSectionKnowsNames;
    [Test]
    procedure JsonOnlyWithSectionFields;
    [Test]
    procedure AgoInMinutesHoursDays;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Core.Tracker.CurrentIssue,
  Shell.Mcp.IssueText;

const
  cAt = 46100.25;

function Started: TAtlasCurrentIssue;
var
  mTask: TAtlasCurrentIssueTask;
  mRef: TAtlasCurrentIssueCodeRef;
  mComment: TAtlasCurrentIssueComment;
begin
  Result := TAtlasCurrentIssue.Empty;
  Result.Key := 'ATL-42';
  Result.Title := 'Leiste im Debugger';
  Result.Tracker := 'youtrack';
  Result.Project := 'ATL';
  Result.State := 'In Arbeit';
  Result.Milestone := 'Sprint 7';
  Result.Branch := 'ATL-42-leiste';
  Result.Started := cAt - 2 / HoursPerDay;
  Result.Fetched := cAt - 5 / MinsPerDay;
  Result.Description := 'Erste Zeile' + #10 + 'Zweite Zeile';
  mTask.Level := 1;
  mTask.Text := 'Entwurf';
  mTask.Done := True;
  Result.Checklist := [mTask];
  mTask.Text := 'Test';
  mTask.Done := False;
  Result.Checklist := Result.Checklist + [mTask];
  mRef.FileName := 'Unit1.pas';
  mRef.Line := 12;
  mRef.Symbol := 'TFoo.Bar';
  Result.CodeRefs := [mRef];
  mComment.Author := 'Bea';
  mComment.Created := cAt - 3 / HoursPerDay;
  mComment.Text := 'Passt so.';
  Result.Comments := [mComment];
  Result.CommentCount := 4;
end;

{ TMcpIssueTextTests }

procedure TMcpIssueTextTests.SummaryTextLikeMockup;
var
  mText: string;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  mText := TMcpCurrentIssueText.Text(Started, TAtlasCurrentIssueSection.Summary, cAt);
  Assert.IsTrue(mText.StartsWith('ATL-42 Leiste im Debugger' + #10 + 'YouTrack ATL · In Arbeit · Sprint 7' + #10 +
    'Branch ATL-42-leiste · begonnen vor 2 Std. · Stand vor 5 Min.'), mText);
  Assert.IsTrue(Pos('Checkliste 1/2' + #10 + '  [x] Entwurf' + #10 + '  [ ] Test', mText) > 0, mText);
  Assert.IsTrue(Pos('  Unit1.pas:12  TFoo.Bar', mText) > 0, mText);
  Assert.IsTrue(Pos('24 Zeichen (section "body")', mText) > 0, 'nur die Länge der Beschreibung');
  Assert.AreEqual(0, Pos('Passt so', mText), 'Kommentare nur mit comments oder all');
end;

procedure TMcpIssueTextTests.BodyAndCommentsText;
var
  mText: string;
begin
  TAtlasLocale.Use(TTextLanguage.English);
  try
    mText := TMcpCurrentIssueText.Text(Started, TAtlasCurrentIssueSection.Body, cAt);
    Assert.IsTrue(Pos('Description' + #10 + '  Erste Zeile' + #10 + '  Zweite Zeile', mText) > 0, mText);
    mText := TMcpCurrentIssueText.Text(Started, TAtlasCurrentIssueSection.Comments, cAt);
    Assert.IsTrue(Pos('Comments (the last 1 of 4)', mText) > 0, mText);
    Assert.IsTrue(Pos('Bea, 3 h ago:', mText) > 0, mText);
    Assert.IsTrue(Pos('Passt so.', mText) > 0, mText);
  finally
    TAtlasLocale.Use(TTextLanguage.German);
  end;
end;

procedure TMcpIssueTextTests.WithoutTrackerDataSaysSo;
var
  mIssue: TAtlasCurrentIssue;
  mText: string;
begin
  TAtlasLocale.Use(TTextLanguage.English);
  try
    mIssue := TAtlasCurrentIssue.Empty;
    mIssue.Key := 'ATL-7';
    mText := TMcpCurrentIssueText.Text(mIssue, TAtlasCurrentIssueSection.All, cAt);
    Assert.IsTrue(Pos('no data from the tracker yet', mText) > 0, mText);
    Assert.IsTrue(Pos('no comments loaded', mText) > 0, mText);
    Assert.AreEqual(0, Pos('Branch', mText), 'ohne Branch keine leere Angabe');
  finally
    TAtlasLocale.Use(TTextLanguage.German);
  end;
end;

procedure TMcpIssueTextTests.ParseSectionKnowsNames;
var
  mSection: TAtlasCurrentIssueSection;
begin
  Assert.IsTrue(TMcpCurrentIssueText.ParseSection('', mSection));
  Assert.AreEqual<TAtlasCurrentIssueSection>(TAtlasCurrentIssueSection.Summary, mSection);
  Assert.IsTrue(TMcpCurrentIssueText.ParseSection('Checklist', mSection));
  Assert.AreEqual<TAtlasCurrentIssueSection>(TAtlasCurrentIssueSection.Checklist, mSection);
  Assert.IsTrue(TMcpCurrentIssueText.ParseSection('all', mSection));
  Assert.AreEqual<TAtlasCurrentIssueSection>(TAtlasCurrentIssueSection.All, mSection);
  Assert.IsFalse(TMcpCurrentIssueText.ParseSection('alles', mSection));
end;

procedure TMcpIssueTextTests.JsonOnlyWithSectionFields;
var
  mJson: string;
begin
  mJson := TMcpCurrentIssueText.Json(Started, TAtlasCurrentIssueSection.Body);
  Assert.IsTrue(Pos('"description"', mJson) > 0, mJson);
  Assert.AreEqual(0, Pos('"checklist"', mJson), mJson);
  Assert.IsTrue(Pos(#10, mJson) > 0, 'eingerückt');
end;

procedure TMcpIssueTextTests.AgoInMinutesHoursDays;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('', TMcpCurrentIssueText.Ago(0, cAt));
  Assert.AreEqual('gerade eben', TMcpCurrentIssueText.Ago(cAt - 10 / SecsPerDay, cAt));
  Assert.AreEqual('vor 59 Min.', TMcpCurrentIssueText.Ago(cAt - 59 / MinsPerDay, cAt));
  Assert.AreEqual('vor 47 Std.', TMcpCurrentIssueText.Ago(cAt - 47 / HoursPerDay, cAt));
  Assert.AreEqual('vor 3 Tagen', TMcpCurrentIssueText.Ago(cAt - 3, cAt));
end;

end.
