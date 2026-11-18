unit Atlas.Core.Tracker.CurrentIssue.Tests;

// Tests der Datei atlas-current-issue.json (#2051) ohne VCL: Hin und zurück über JSON, fremde Version und fehlende
// Kennung, Felder je Abschnitt. Die Textausgabe prüft Shell.Mcp.IssueText.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasCurrentIssueTests = class
  public
    [Test]
    procedure JsonRoundTripKeepsAllFields;
    [Test]
    procedure FromJsonRejectsBrokenOrForeign;
    [Test]
    procedure SectionsChooseJsonFields;
    [Test]
    procedure FileLiesInGitDir;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  Atlas.Core.Tracker.CurrentIssue;

const
  cNow = 46000.5;

function Task(const AText: string; ADone: Boolean): TAtlasCurrentIssueTask;
begin
  Result.Text := AText;
  Result.Done := ADone;
  Result.Level := 1;
end;

function Sample: TAtlasCurrentIssue;
var
  mRef: TAtlasCurrentIssueCodeRef;
  mComment: TAtlasCurrentIssueComment;
begin
  Result := TAtlasCurrentIssue.Empty;
  Result.Key := '#1926';
  Result.Title := 'Arbeitskopien je Tracker-Projekt hinterlegen';
  Result.Tracker := 'github';
  Result.Project := 'owner/repo';
  Result.State := 'open';
  Result.Milestone := 'v2.1.0';
  Result.Page := 'https://github.com/owner/repo/issues/1926';
  Result.Branch := 'feature/1926-arbeitskopien';
  Result.Started := cNow - 2 / HoursPerDay;
  Result.Fetched := cNow - 5 / MinsPerDay;
  Result.Description := 'Größere Änderung' + #10 + '- [x] Spalte' + #10 + '- [ ] Handtest';
  Result.Checklist := TArray<TAtlasCurrentIssueTask>.Create(Task('Spalte', True), Task('Handtest', False));
  mRef.FileName := 'Atlas.IDE.Tracker.IssueStart.pas';
  mRef.Line := 212;
  mRef.Symbol := 'TAtlasIdeIssueStart.Branch';
  Result.CodeRefs := [mRef];
  mComment.Author := 'Anna';
  mComment.Created := cNow - 3 / HoursPerDay;
  mComment.Text := 'Sieht gut aus.';
  Result.Comments := [mComment];
  Result.CommentCount := 7;
end;

{ TAtlasCurrentIssueTests }

procedure TAtlasCurrentIssueTests.JsonRoundTripKeepsAllFields;
var
  mIssue: TAtlasCurrentIssue;
  mText: string;
begin
  mText := Sample.ToJson;
  Assert.IsTrue(Pos('Größere', mText) > 0, 'Umlaute lesbar, nicht als \u');
  Assert.IsTrue(TAtlasCurrentIssue.FromJson(mText, mIssue));
  Assert.AreEqual('#1926', mIssue.Key);
  Assert.AreEqual('Arbeitskopien je Tracker-Projekt hinterlegen', mIssue.Title);
  Assert.AreEqual('github', mIssue.Tracker);
  Assert.AreEqual('owner/repo', mIssue.Project);
  Assert.AreEqual('open', mIssue.State);
  Assert.AreEqual('v2.1.0', mIssue.Milestone);
  Assert.AreEqual('feature/1926-arbeitskopien', mIssue.Branch);
  Assert.AreEqual(Sample.Description, mIssue.Description);
  Assert.AreEqual(2, Integer(Length(mIssue.Checklist)));
  Assert.IsTrue(mIssue.Checklist[0].Done);
  Assert.AreEqual('Handtest', mIssue.Checklist[1].Text);
  Assert.AreEqual(212, mIssue.CodeRefs[0].Line);
  Assert.AreEqual('TAtlasIdeIssueStart.Branch', mIssue.CodeRefs[0].Symbol);
  Assert.AreEqual('Anna', mIssue.Comments[0].Author);
  Assert.AreEqual(7, mIssue.CommentCount);
  Assert.AreEqual(Int64(0), SecondsBetween(Sample.Fetched, mIssue.Fetched), 'Stand bleibt auf die Sekunde');
  Assert.AreEqual(Int64(0), SecondsBetween(Sample.Started, mIssue.Started));
end;

procedure TAtlasCurrentIssueTests.FromJsonRejectsBrokenOrForeign;
var
  mIssue: TAtlasCurrentIssue;
begin
  Assert.IsFalse(TAtlasCurrentIssue.FromJson('', mIssue));
  Assert.IsFalse(TAtlasCurrentIssue.FromJson('{kaputt', mIssue));
  Assert.IsFalse(TAtlasCurrentIssue.FromJson('[]', mIssue));
  Assert.IsFalse(TAtlasCurrentIssue.FromJson('{"version":2,"key":"#1"}', mIssue), 'fremde Version');
  Assert.IsFalse(TAtlasCurrentIssue.FromJson('{"version":1,"key":" "}', mIssue), 'ohne Kennung');
  Assert.IsTrue(TAtlasCurrentIssue.FromJson('{"version":1,"key":"ATL-1"}', mIssue));
  Assert.AreEqual(-1, mIssue.CommentCount, 'Kommentare nicht abgefragt');
  Assert.AreEqual(Double(0), Double(mIssue.Fetched));
end;

procedure TAtlasCurrentIssueTests.SectionsChooseJsonFields;
var
  mObject: TJSONObject;
begin
  mObject := Sample.ToJsonObject(TAtlasCurrentIssueSection.Summary);
  try
    Assert.IsNotNull(mObject.GetValue('checklist'));
    Assert.IsNotNull(mObject.GetValue('codeRefs'));
    Assert.IsNull(mObject.GetValue('description'), 'summary nennt nur die Länge');
    Assert.AreEqual(Length(Sample.Description), mObject.GetValue<Integer>('descriptionLength'));
    Assert.IsNull(mObject.GetValue('comments'));
  finally
    mObject.Free;
  end;
  mObject := Sample.ToJsonObject(TAtlasCurrentIssueSection.Comments);
  try
    Assert.IsNotNull(mObject.GetValue('comments'));
    Assert.IsNull(mObject.GetValue('checklist'));
    Assert.AreEqual('#1926', mObject.GetValue<string>('key'), 'Kopf immer dabei');
  finally
    mObject.Free;
  end;
  Assert.IsTrue(Pos('"description"', Sample.ToJson) > 0, 'Datei mit allen Feldern');
end;

procedure TAtlasCurrentIssueTests.FileLiesInGitDir;
begin
  Assert.AreEqual(IncludeTrailingPathDelimiter('repo') + 'atlas-current-issue.json',
    TAtlasCurrentIssue.FileOf('repo'));
end;

end.
