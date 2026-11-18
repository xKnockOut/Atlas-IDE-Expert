unit Atlas.Core.Tracker.CurrentIssuePlan.Tests;

// Tests von Aufbau und Ablage von atlas-current-issue.json (#2051) ohne VCL: Felder aus dem Stand der Vorschau,
// die letzten Kommentare, kein Token und keine Anhänge, Codeverweise in den üblichen Schreibweisen, <gitdir> auch
// bei Worktrees, Schreiben nur bei geändertem Inhalt, Löschen ohne Issue bzw. mit ausgeschalteter Einstellung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasCurrentIssuePlanTests = class
  private
    FDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BuildTakesDetailsAndChecklist;
    [Test]
    procedure BuildKeepsLastCommentsOnly;
    [Test]
    procedure BuildWithoutDetailsHasHeadOnly;
    [Test]
    procedure NoTokenNoSignedAddress;
    [Test]
    procedure CodeRefsInCommonForms;
    [Test]
    procedure CodeRefsIgnoreOtherText;
    [Test]
    procedure GitDirOfFolderAndParent;
    [Test]
    procedure GitDirOfWorktree;
    [Test]
    procedure SyncWritesOnlyChanges;
    [Test]
    procedure SyncRemovesWithoutIssueOrSharing;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Files,
  Atlas.Core.Tracker.Files.TestSupport,
  Atlas.Core.Tracker.CurrentIssue,
  Atlas.Core.Tracker.CurrentIssuePlan;

const
  cNow = 46000.5;

function Comment(const AAuthor, AText: string): TAtlasTrackerComment;
begin
  Result.Author := AAuthor;
  Result.Created := cNow;
  Result.Text := AText;
end;

function Source: TAtlasCurrentIssueSource;
begin
  Result := Default(TAtlasCurrentIssueSource);
  Result.Key := 'ATL-12';
  Result.Title := 'Titel aus der Liste';
  Result.Branch := 'feature/ATL-12-abc';
  Result.Started := cNow - 1;
  Result.Target := TAtlasTrackerTarget.Create('youtrack', 'https://firma.youtrack.cloud', 'ATL', '');
  Result.HasDetails := True;
  Result.Details := TAtlasTrackerDetails.Empty;
  Result.Details.Key := 'ATL-12';
  Result.Details.Title := 'Titel aus dem Tracker';
  Result.Details.State := 'In Arbeit';
  Result.Details.Sprint := 'Sprint 4';
  Result.Details.Page := 'https://firma.youtrack.cloud/issue/ATL-12';
  Result.Details.Description := 'Fehler in `Unit1.pas`, Zeile 12' + #10 + '- [x] Test' + #10 + '- [ ] Bau';
  Result.Details.Fetched := cNow;
end;

{ TAtlasCurrentIssuePlanTests }

procedure TAtlasCurrentIssuePlanTests.Setup;
begin
  TAtlasTrackerFiles.Install(TAtlasTrackerTestFiles.Create, nil);
  FDir := TPath.Combine(TPath.GetTempPath, 'atlas-current-' + IntToStr(Random(1000000)));
  ForceDirectories(FDir);
end;

procedure TAtlasCurrentIssuePlanTests.TearDown;
begin
  TAtlasTrackerFiles.Uninstall;
  if TDirectory.Exists(FDir) then
  begin
    TDirectory.Delete(FDir, True);
  end;
  FDir := '';
end;

procedure TAtlasCurrentIssuePlanTests.BuildTakesDetailsAndChecklist;
var
  mIssue: TAtlasCurrentIssue;
begin
  mIssue := TAtlasCurrentIssuePlan.Build(Source);
  Assert.AreEqual('ATL-12', mIssue.Key);
  Assert.AreEqual('Titel aus dem Tracker', mIssue.Title, 'frischer Titel vor dem der Liste');
  Assert.AreEqual('youtrack', mIssue.Tracker);
  Assert.AreEqual('ATL', mIssue.Project);
  Assert.AreEqual('In Arbeit', mIssue.State);
  Assert.AreEqual('Sprint 4', mIssue.Milestone);
  Assert.AreEqual('feature/ATL-12-abc', mIssue.Branch);
  Assert.AreEqual(2, Integer(Length(mIssue.Checklist)));
  Assert.IsTrue(mIssue.Checklist[0].Done);
  Assert.AreEqual('Bau', mIssue.Checklist[1].Text);
  Assert.AreEqual(1, Integer(Length(mIssue.CodeRefs)));
  Assert.AreEqual('Unit1.pas', mIssue.CodeRefs[0].FileName);
  Assert.AreEqual(-1, mIssue.CommentCount, 'Kommentare nicht abgefragt');
end;

procedure TAtlasCurrentIssuePlanTests.BuildKeepsLastCommentsOnly;
var
  mSource: TAtlasCurrentIssueSource;
  mIssue: TAtlasCurrentIssue;
  mIndex: Integer;
begin
  mSource := Source;
  mSource.Details.CommentsLoaded := True;
  for mIndex := 1 to 7 do
  begin
    mSource.Details.Comments := mSource.Details.Comments + [Comment('Anna', 'K' + IntToStr(mIndex))];
  end;
  mIssue := TAtlasCurrentIssuePlan.Build(mSource);
  Assert.AreEqual(7, mIssue.CommentCount);
  Assert.AreEqual(TAtlasCurrentIssue.cMaxComments, Integer(Length(mIssue.Comments)));
  Assert.AreEqual('K3', mIssue.Comments[0].Text, 'die letzten, älteste zuerst');
  Assert.AreEqual('K7', mIssue.Comments[High(mIssue.Comments)].Text);
end;

procedure TAtlasCurrentIssuePlanTests.BuildWithoutDetailsHasHeadOnly;
var
  mSource: TAtlasCurrentIssueSource;
  mIssue: TAtlasCurrentIssue;
begin
  mSource := Source;
  mSource.HasDetails := False;
  mIssue := TAtlasCurrentIssuePlan.Build(mSource);
  Assert.AreEqual('Titel aus der Liste', mIssue.Title);
  Assert.AreEqual('', mIssue.Description);
  Assert.AreEqual(Double(0), Double(mIssue.Fetched));
end;

procedure TAtlasCurrentIssuePlanTests.NoTokenNoSignedAddress;
var
  mSource: TAtlasCurrentIssueSource;
  mAttachment: TAtlasTrackerAttachment;
  mText: string;
begin
  mSource := Source;
  mSource.Target.Url := 'https://firma.youtrack.cloud';
  mAttachment := Default(TAtlasTrackerAttachment);
  mAttachment.Name := 'log.txt';
  mAttachment.Url := 'https://firma.youtrack.cloud/api/files/1?sign=GEHEIM';
  mSource.Details.Attachments := [mAttachment];
  mText := TAtlasCurrentIssuePlan.Build(mSource).ToJson;
  Assert.AreEqual(0, Pos('sign=', mText), 'keine signierten Adressen');
  Assert.AreEqual(0, Pos('GEHEIM', mText));
  Assert.AreEqual(0, Pos('log.txt', mText), 'keine Anhänge');
  Assert.AreEqual(0, Pos('token', LowerCase(mText)));
end;

procedure TAtlasCurrentIssuePlanTests.CodeRefsInCommonForms;
var
  mRefs: TArray<TAtlasCurrentIssueCodeRef>;
begin
  mRefs := TAtlasCurrentIssuePlan.CodeRefs(
    'Siehe Atlas.IDE.Tracker.IssueStart.pas:212  TAtlasIdeIssueStart.Branch' + #13#10 +
    '- [ ] `Atlas.Core.Tracker.Projects.pas:88`' + #10 +
    'Befund in Src/Unit2.pas:7:5 (unused-variable)' + #10 +
    'Fundstelle: `Unit1.pas`, Zeile 12' + #10 +
    'Methode: `TForm1.Button1Click`' + #10 +
    'Und nochmal Atlas.Core.Tracker.Projects.pas:88');
  Assert.AreEqual(4, Integer(Length(mRefs)), 'doppelte nur einmal');
  Assert.AreEqual('Atlas.IDE.Tracker.IssueStart.pas', mRefs[0].FileName);
  Assert.AreEqual(212, mRefs[0].Line);
  Assert.AreEqual('TAtlasIdeIssueStart.Branch', mRefs[0].Symbol);
  Assert.AreEqual(88, mRefs[1].Line);
  Assert.AreEqual('', mRefs[1].Symbol);
  Assert.AreEqual('Src/Unit2.pas', mRefs[2].FileName);
  Assert.AreEqual(7, mRefs[2].Line, 'Spalte zählt nicht');
  Assert.AreEqual('', mRefs[2].Symbol, 'Klammer ist kein Symbol');
  Assert.AreEqual('Unit1.pas', mRefs[3].FileName);
  Assert.AreEqual(12, mRefs[3].Line);
  Assert.AreEqual('TForm1.Button1Click', mRefs[3].Symbol, 'Methode aus der Zeile darunter');
end;

procedure TAtlasCurrentIssuePlanTests.CodeRefsIgnoreOtherText;
var
  mRefs: TArray<TAtlasCurrentIssueCodeRef>;
begin
  mRefs := TAtlasCurrentIssuePlan.CodeRefs('Die Datei .pas allein, README.md:4, x.pascal:3, Version 1.2.3');
  Assert.AreEqual(0, Integer(Length(mRefs)));
  mRefs := TAtlasCurrentIssuePlan.CodeRefs('Projekt.dpr und Paket.dpk');
  Assert.AreEqual(2, Integer(Length(mRefs)), 'ohne Zeile');
  Assert.AreEqual(0, mRefs[0].Line);
end;

procedure TAtlasCurrentIssuePlanTests.GitDirOfFolderAndParent;
var
  mSub: string;
begin
  ForceDirectories(TPath.Combine(FDir, '.git'));
  mSub := TPath.Combine(TPath.Combine(FDir, 'Src'), 'Tief');
  ForceDirectories(mSub);
  Assert.AreEqual(TPath.Combine(FDir, '.git'), TAtlasCurrentIssuePlan.GitDirOf(FDir));
  Assert.AreEqual(TPath.Combine(FDir, '.git'), TAtlasCurrentIssuePlan.GitDirOf(mSub), 'aus einem Unterordner');
  Assert.AreEqual('', TAtlasCurrentIssuePlan.GitDirOf(''));
end;

procedure TAtlasCurrentIssuePlanTests.GitDirOfWorktree;
var
  mTree, mGitDir: string;
begin
  mTree := TPath.Combine(FDir, 'wt');
  mGitDir := TPath.Combine(TPath.Combine(TPath.Combine(FDir, 'main'), '.git'), 'worktrees');
  mGitDir := TPath.Combine(mGitDir, 'wt');
  ForceDirectories(mTree);
  ForceDirectories(mGitDir);
  // Relativ zum Worktree: WorktreeGitDir rechnet in Windows-Pfaden, so geht der Test auch unter FPC/Linux.
  TFile.WriteAllText(TPath.Combine(mTree, '.git'), 'gitdir: ../main/.git/worktrees/wt' + #10);
  Assert.AreEqual(mGitDir.Replace('\', '/'), TAtlasCurrentIssuePlan.GitDirOf(mTree).Replace('\', '/'),
    'eigener Ordner des Worktrees');
end;

procedure TAtlasCurrentIssuePlanTests.SyncWritesOnlyChanges;
var
  mIssue, mRead: TAtlasCurrentIssue;
  mText: string;
begin
  mIssue := TAtlasCurrentIssuePlan.Build(Source);
  Assert.AreEqual<TAtlasCurrentIssueSync>(TAtlasCurrentIssueSync.Written,
    TAtlasCurrentIssuePlan.Sync(FDir, True, True, mIssue));
  Assert.IsTrue(TAtlasTrackerFiles.Files.ReadText(TAtlasCurrentIssue.FileOf(FDir), mText));
  Assert.IsTrue(TAtlasCurrentIssue.FromJson(mText, mRead));
  Assert.AreEqual('ATL-12', mRead.Key);
  Assert.AreEqual<TAtlasCurrentIssueSync>(TAtlasCurrentIssueSync.Unchanged,
    TAtlasCurrentIssuePlan.Sync(FDir, True, True, mIssue), 'gleicher Inhalt: nichts schreiben');
  mIssue.Checklist[1].Done := True;
  Assert.AreEqual<TAtlasCurrentIssueSync>(TAtlasCurrentIssueSync.Written,
    TAtlasCurrentIssuePlan.Sync(FDir, True, True, mIssue), 'im Tracker abgehakt');
  Assert.AreEqual<TAtlasCurrentIssueSync>(TAtlasCurrentIssueSync.Unchanged,
    TAtlasCurrentIssuePlan.Sync('', True, True, mIssue), 'ohne Git-Ordner nichts');
end;

procedure TAtlasCurrentIssuePlanTests.SyncRemovesWithoutIssueOrSharing;
var
  mIssue: TAtlasCurrentIssue;
begin
  mIssue := TAtlasCurrentIssuePlan.Build(Source);
  TAtlasCurrentIssuePlan.Sync(FDir, True, True, mIssue);
  Assert.AreEqual<TAtlasCurrentIssueSync>(TAtlasCurrentIssueSync.Removed,
    TAtlasCurrentIssuePlan.Sync(FDir, False, True, mIssue), 'Einstellung aus');
  Assert.IsFalse(FileExists(TAtlasCurrentIssue.FileOf(FDir)));
  Assert.AreEqual<TAtlasCurrentIssueSync>(TAtlasCurrentIssueSync.Unchanged,
    TAtlasCurrentIssuePlan.Sync(FDir, False, True, mIssue), 'schon weg');
  TAtlasCurrentIssuePlan.Sync(FDir, True, True, mIssue);
  Assert.AreEqual<TAtlasCurrentIssueSync>(TAtlasCurrentIssueSync.Removed,
    TAtlasCurrentIssuePlan.Sync(FDir, True, False, mIssue), 'beendet');
  Assert.IsFalse(FileExists(TAtlasCurrentIssue.FileOf(FDir)));
end;

end.
