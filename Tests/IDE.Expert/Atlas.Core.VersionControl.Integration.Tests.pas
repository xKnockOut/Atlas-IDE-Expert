unit Atlas.Core.VersionControl.Integration.Tests;

// Versionsverwaltung mit echtem git und svn (#571): Die Tests legen eine
// Git- bzw. SVN-Arbeitskopie (mit svnadmin ein Repository unter file:///) in
// einem temporären Ordner an und prüfen Branch, Revision, geänderte Dateien,
// Inhalt in einer Revision, Zeilenherkunft und Wechselerkennung. Fehlt git
// bzw. svn (oder svnadmin), wird der Test übersprungen.
// Lokale Arbeit (#762): Branches mit Upstream und Vorsprung, Branch ohne
// Upstream, Stash mit Dateien, ungepushte Commits, Push auf ein lokales
// Bare-Repository und die Auswertung für „Nicht gesichert“.
// Eingehende Commits (#755): Ein zweiter Klon pusht Commits zu einer
// bearbeiteten und zu einer fremden Datei; erst nach fetch kennt die
// Arbeitskopie sie, und nur der Commit zur bearbeiteten Datei erscheint.
// Dazu der Prozessläufer selbst: Hauptthread abgelehnt, Zeitlimit, fehlendes
// Programm, Hintergrund über TAtlasVcsWorker.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.VersionControl')]
  TAtlasVcsIntegrationTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure GitWorkingCopyReportsBranchRevisionAndChanges;
    [Test]
    procedure SvnWorkingCopyReportsBranchRevisionAndChanges;
    [Test]
    procedure GitLocalWorkReportsUnsavedAndPushes;
    [Test]
    procedure GitIncomingCommitsOnEditedFiles;
    [Test]
    procedure RunnerRefusesMainThreadAndHonoursTimeout;
    [Test]
    procedure WorkerRunsInBackgroundAndDeliversInMainThread;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Tools,
  Atlas.Core.VersionControl.Switches,
  Atlas.Core.VersionControl.Worker,
  Atlas.Core.VersionControl.Composition,
  Atlas.Core.VersionControl.Adapters.ProcessRunner,
  Atlas.Core.Welcome.Unsaved,
  Atlas.Core.Welcome.Continue;

/// <summary>Führt ein Programm für den Aufbau der Fixture aus; Ausgabe als Text, Ausnahme bei Fehler.</summary>
function Exec(const ARunner: IAtlasVcsRunner; const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir: string): string;
var
  mAnswer: TAtlasVcsRunResult;
begin
  mAnswer := ARunner.Run(AExecutable, AArguments, AWorkingDir, 30000);
  if (mAnswer.Outcome <> TAtlasVcsOutcome.Ok) or (mAnswer.ExitCode <> 0) then
  begin
    raise Exception.CreateFmt('%s %s: Exit-Code %d, %s', [ExtractFileName(AExecutable),
      string.Join(' ', AArguments), mAnswer.ExitCode, mAnswer.ErrorText]);
  end;
  Result := Trim(TEncoding.UTF8.GetString(mAnswer.Output));
end;

function NewFolder(const AName: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'AtlasVcs-' + AName + '-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(Result);
end;

procedure RemoveFolder(const AFolder: string);
var
  mFileName: string;
begin
  if not TDirectory.Exists(AFolder) then
  begin
    Exit;
  end;
  // git legt schreibgeschützte Objektdateien an.
  for mFileName in TDirectory.GetFiles(AFolder, '*', TSearchOption.soAllDirectories) do
  begin
    {$WARN SYMBOL_PLATFORM OFF}
    TFile.SetAttributes(mFileName, [TFileAttribute.faNormal]);
    {$WARN SYMBOL_PLATFORM ON}
  end;
  try
    TDirectory.Delete(AFolder, True);
  except
    on EInOutError do
      ;
    on EOSError do
      ;
  end;
end;

function Find(const AChanges: TArray<TAtlasVcsChange>; const APath: string; out AChange: TAtlasVcsChange): Boolean;
var
  mItem: TAtlasVcsChange;
begin
  for mItem in AChanges do
  begin
    if SameText(mItem.Path, APath) then
    begin
      AChange := mItem;
      Exit(True);
    end;
  end;
  AChange := Default(TAtlasVcsChange);
  Result := False;
end;

{ TAtlasVcsIntegrationTests }

procedure TAtlasVcsIntegrationTests.WarmUpFirstUse;
begin
  // Ohne git bzw. svn meldet der Test Assert.Pass; das gilt hier nicht als Fehler.
  try
    GitWorkingCopyReportsBranchRevisionAndChanges;
  except
    on Exception do
      ;
  end;
  try
    SvnWorkingCopyReportsBranchRevisionAndChanges;
  except
    on Exception do
      ;
  end;
end;

/// <summary>Legt in AFolder ein Git-Repository mit Branch main für „Atlas Test“ an (ohne CRLF-Umwandlung und
/// Signatur).</summary>
procedure InitGitRepository(const ARunner: IAtlasVcsRunner; const AGitExe, AFolder: string);
begin
  Exec(ARunner, AGitExe, ['init', '-q'], AFolder);
  Exec(ARunner, AGitExe, ['symbolic-ref', 'HEAD', 'refs/heads/main'], AFolder);
  Exec(ARunner, AGitExe, ['config', 'user.name', 'Atlas Test'], AFolder);
  Exec(ARunner, AGitExe, ['config', 'user.email', 'test@example.org'], AFolder);
  Exec(ARunner, AGitExe, ['config', 'core.autocrlf', 'false'], AFolder);
  Exec(ARunner, AGitExe, ['config', 'commit.gpgsign', 'false'], AFolder);
end;

/// <summary>Schreibt A.pas (zwei Zeilen) und B.pas nach AFolder.</summary>
procedure WriteUnitsAB(const AFolder: string);
begin
  TFile.WriteAllText(TPath.Combine(AFolder, 'A.pas'), 'unit A;'#10'end.'#10, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(AFolder, 'B.pas'), 'unit B;'#10, TEncoding.ASCII);
end;

/// <summary>Prüft den Stand von A.pas im Repository und dessen Blame (zwei übernommene Zeilen aus ARevision, eine
/// neue); AFirst ist die erste Zeile.</summary>
procedure AssertBaseAndBlame(const AVcs: IAtlasVersionControl; const AFolder, ARevision, AMessage: string;
  out AFirst: TAtlasVcsBlameLine);
var
  mContent: TBytes;
  mLines: TArray<TAtlasVcsBlameLine>;
begin
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, AVcs.FileAt(TPath.Combine(AFolder, 'A.pas'), '', mContent));
  Assert.AreEqual('unit A;'#10'end.'#10, TEncoding.UTF8.GetString(mContent), AMessage);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, AVcs.Blame(TPath.Combine(AFolder, 'A.pas'), mLines));
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.AreEqual(ARevision, mLines[0].Revision);
  Assert.IsTrue(mLines[2].Uncommitted);
  AFirst := mLines[0];
end;

/// <summary>Ändert A.pas, legt src\Neu Datei.pas an, löscht B.pas und prüft die drei Änderungen.</summary>
procedure AssertGitChanges(const AVcs: IAtlasVersionControl; const AFolder: string);
var
  mChanges: TArray<TAtlasVcsChange>;
  mChange: TAtlasVcsChange;
begin
  TFile.AppendAllText(TPath.Combine(AFolder, 'A.pas'), '// neu'#10, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(AFolder, 'src\Neu Datei.pas'), 'unit Neu;'#10, TEncoding.ASCII);
  TFile.Delete(TPath.Combine(AFolder, 'B.pas'));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, AVcs.Changes(mChanges));
  Assert.AreEqual(3, Integer(Length(mChanges)));
  Assert.IsTrue(Find(mChanges, TPath.Combine(AFolder, 'A.pas'), mChange));
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Modified, mChange.Kind);
  Assert.IsTrue(Find(mChanges, TPath.Combine(AFolder, 'src\Neu Datei.pas'), mChange), 'neue Datei im Unterordner');
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Untracked, mChange.Kind);
  Assert.IsTrue(Find(mChanges, TPath.Combine(AFolder, 'B.pas'), mChange));
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Deleted, mChange.Kind);
end;

/// <summary>Die Wache meldet git checkout -b als Branch- und einen Commit als Revisionswechsel.</summary>
procedure AssertGitWatch(const AVcs: IAtlasVersionControl; const ARunner: IAtlasVcsRunner; const AGitExe,
  AFolder: string);
var
  mWatch: TAtlasVcsWatch;
begin
  mWatch := TAtlasVcsWatch.Create(AVcs);
  try
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None, mWatch.Check);
    Exec(ARunner, AGitExe, ['checkout', '-q', '-b', 'feature/x'], AFolder);
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Branch, mWatch.Check, 'git checkout -b');
    Assert.AreEqual('feature/x', mWatch.Head.Branch);
    Exec(ARunner, AGitExe, ['commit', '-q', '-a', '-m', 'Zweiter Stand'], AFolder);
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Revision, mWatch.Check, 'Commit');
  finally
    mWatch.Free;
  end;
end;

procedure TAtlasVcsIntegrationTests.GitWorkingCopyReportsBranchRevisionAndChanges;
var
  mGitExe, mFolder, mCommit: string;
  mRunner: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mHead: TAtlasVcsHead;
  mChanges: TArray<TAtlasVcsChange>;
  mFirst: TAtlasVcsBlameLine;
begin
  mGitExe := TAtlasVcsTools.Find(TAtlasVcsKind.Git);
  if mGitExe = '' then
  begin
    Assert.Pass('git nicht installiert; Prüfung übersprungen');
  end;
  // Im Test erlaubt: Der Hauptthread des Testprogramms ist keine IDE.
  mRunner := TAtlasVcsProcessRunner.Create(True, nil);
  mFolder := NewFolder('git');
  try
    InitGitRepository(mRunner, mGitExe, mFolder);
    WriteUnitsAB(mFolder);
    Exec(mRunner, mGitExe, ['add', '.'], mFolder);
    Exec(mRunner, mGitExe, ['commit', '-q', '-m', 'Erster Stand'], mFolder);
    mCommit := Exec(mRunner, mGitExe, ['rev-parse', 'HEAD'], mFolder);
    TDirectory.CreateDirectory(TPath.Combine(mFolder, 'src'));

    mVcs := TAtlasVersionControl.Open(TPath.Combine(mFolder, 'src'), TAtlasVcsProvider.Auto, mRunner);
    Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git, mVcs.Kind);
    Assert.AreEqual(ExcludeTrailingPathDelimiter(mFolder), mVcs.WorkingCopy.Root);
    Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.Head(mHead));
    Assert.AreEqual('main', mHead.Branch);
    Assert.AreEqual(mCommit, mHead.Revision);
    Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.Changes(mChanges));
    Assert.AreEqual(0, Integer(Length(mChanges)), 'frisch übernommen');

    AssertGitChanges(mVcs, mFolder);
    AssertBaseAndBlame(mVcs, mFolder, mCommit, 'Stand im Repository', mFirst);
    Assert.AreEqual('Atlas Test', mFirst.Author);
    Assert.AreEqual('Erster Stand', mFirst.Summary);
    AssertGitWatch(mVcs, mRunner, mGitExe, mFolder);
  finally
    mVcs := nil;
    RemoveFolder(mFolder);
  end;
end;

/// <summary>svn und svnadmin; False, wenn eines fehlt.</summary>
function SvnTools(out ASvnExe, ASvnAdmin: string): Boolean;
begin
  ASvnExe := TAtlasVcsTools.Find(TAtlasVcsKind.Svn);
  ASvnAdmin := '';
  Result := ASvnExe <> '';
  if Result then
  begin
    ASvnAdmin := TPath.Combine(ExtractFilePath(ASvnExe), 'svnadmin.exe');
    Result := TFile.Exists(ASvnAdmin);
  end;
end;

/// <summary>Ablage unter AFolder mit trunk und branches, Arbeitskopie von trunk in AWorkingCopy mit A.pas und
/// B.pas als r2; liefert die URL der Ablage.</summary>
function CreateSvnCheckout(const ARunner: IAtlasVcsRunner; const ASvnExe, ASvnAdmin, AFolder,
  AWorkingCopy: string): string;
var
  mRepository: string;
begin
  mRepository := TPath.Combine(AFolder, 'repo');
  Exec(ARunner, ASvnAdmin, ['create', mRepository], AFolder);
  Result := 'file:///' + StringReplace(mRepository, '\', '/', [rfReplaceAll]);
  Exec(ARunner, ASvnExe, ['mkdir', '-q', '-m', 'Ablage', Result + '/trunk', Result + '/branches',
    '--non-interactive'], AFolder);
  Exec(ARunner, ASvnExe, ['checkout', '-q', Result + '/trunk', AWorkingCopy, '--non-interactive'], AFolder);
  WriteUnitsAB(AWorkingCopy);
  Exec(ARunner, ASvnExe, ['add', '-q', 'A.pas', 'B.pas'], AWorkingCopy);
  Exec(ARunner, ASvnExe, ['commit', '-q', '-m', 'Erster Stand', '--non-interactive'], AWorkingCopy);
  Exec(ARunner, ASvnExe, ['update', '-q', '--non-interactive'], AWorkingCopy);
end;

/// <summary>Ändert A.pas, legt Neu.pas an und prüft die zwei Änderungen.</summary>
procedure AssertSvnChanges(const AVcs: IAtlasVersionControl; const AWorkingCopy: string);
var
  mChanges: TArray<TAtlasVcsChange>;
  mChange: TAtlasVcsChange;
begin
  TFile.AppendAllText(TPath.Combine(AWorkingCopy, 'A.pas'), '// neu'#10, TEncoding.ASCII);
  TFile.WriteAllText(TPath.Combine(AWorkingCopy, 'Neu.pas'), 'unit Neu;'#10, TEncoding.ASCII);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, AVcs.Changes(mChanges));
  Assert.AreEqual(2, Integer(Length(mChanges)));
  Assert.IsTrue(Find(mChanges, TPath.Combine(AWorkingCopy, 'A.pas'), mChange));
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Modified, mChange.Kind);
  Assert.IsTrue(Find(mChanges, TPath.Combine(AWorkingCopy, 'Neu.pas'), mChange));
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Untracked, mChange.Kind);
end;

/// <summary>Die Wache meldet svn switch auf branches/x als Branchwechsel.</summary>
procedure AssertSvnSwitch(const AVcs: IAtlasVersionControl; const ARunner: IAtlasVcsRunner; const ASvnExe,
  AWorkingCopy, AUrl: string);
var
  mWatch: TAtlasVcsWatch;
begin
  mWatch := TAtlasVcsWatch.Create(AVcs);
  try
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None, mWatch.Check);
    Exec(ARunner, ASvnExe, ['revert', '-q', 'A.pas'], AWorkingCopy);
    Exec(ARunner, ASvnExe, ['copy', '-q', '-m', 'Branch', AUrl + '/trunk', AUrl + '/branches/x', '--non-interactive'],
      AWorkingCopy);
    Exec(ARunner, ASvnExe, ['switch', '-q', AUrl + '/branches/x', '--non-interactive'], AWorkingCopy);
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Branch, mWatch.Check, 'svn switch');
    Assert.AreEqual('branches/x', mWatch.Head.Branch);
  finally
    mWatch.Free;
  end;
end;

procedure TAtlasVcsIntegrationTests.SvnWorkingCopyReportsBranchRevisionAndChanges;
var
  mSvnExe, mSvnAdmin, mFolder, mUrl, mWorkingCopy: string;
  mRunner: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mHead: TAtlasVcsHead;
  mFirst: TAtlasVcsBlameLine;
begin
  // Ohne svn bzw. svnadmin übersprungen. Exit statt Assert.Pass: DUnitX behält die Meldung
  // im Ergebnis, und der Leckmonitor zählte sie als Leck.
  if not SvnTools(mSvnExe, mSvnAdmin) then
  begin
    Exit;
  end;
  mRunner := TAtlasVcsProcessRunner.Create(True, nil);
  mFolder := NewFolder('svn');
  try
    mWorkingCopy := TPath.Combine(mFolder, 'wc');
    mUrl := CreateSvnCheckout(mRunner, mSvnExe, mSvnAdmin, mFolder, mWorkingCopy);

    mVcs := TAtlasVersionControl.Open(mWorkingCopy, TAtlasVcsProvider.Auto, mRunner);
    Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Svn, mVcs.Kind);
    Assert.IsTrue(SameText(ExcludeTrailingPathDelimiter(mWorkingCopy), mVcs.WorkingCopy.Root));
    Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.Head(mHead));
    Assert.AreEqual('trunk', mHead.Branch);
    Assert.AreEqual('2', mHead.Revision, 'Ablage = r1, erster Stand = r2');

    AssertSvnChanges(mVcs, mWorkingCopy);
    AssertBaseAndBlame(mVcs, mWorkingCopy, '2', 'BASE', mFirst);
    AssertSvnSwitch(mVcs, mRunner, mSvnExe, mWorkingCopy, mUrl);
  finally
    mVcs := nil;
    RemoveFolder(mFolder);
  end;
end;

/// <summary>Ablage ARemote und Klon AFolder mit vier Units auf origin/main, dazu 3 ungepushte Commits, 1 Stash und
/// 4 geänderte Dateien (Abnahme).</summary>
procedure PrepareLocalWork(const ARunner: IAtlasVcsRunner; const AGitExe, AFolder, ARemote: string);
var
  mName: string;
begin
  Exec(ARunner, AGitExe, ['init', '-q', '--bare', ARemote], ARemote);
  // Ohne init.defaultBranch = main zeigte HEAD der Ablage auf master: Der Klon bliebe leer.
  Exec(ARunner, AGitExe, ['symbolic-ref', 'HEAD', 'refs/heads/main'], ARemote);
  InitGitRepository(ARunner, AGitExe, AFolder);
  for mName in TArray<string>.Create('A', 'B', 'C', 'D') do
  begin
    TFile.WriteAllText(TPath.Combine(AFolder, mName + '.pas'), 'unit ' + mName + ';'#10, TEncoding.ASCII);
  end;
  Exec(ARunner, AGitExe, ['add', '.'], AFolder);
  Exec(ARunner, AGitExe, ['commit', '-q', '-m', 'Erster Stand'], AFolder);
  Exec(ARunner, AGitExe, ['remote', 'add', 'origin', ARemote], AFolder);
  Exec(ARunner, AGitExe, ['push', '-q', '-u', 'origin', 'main'], AFolder);
  for mName in TArray<string>.Create('Zwei', 'Drei', 'Vier') do
  begin
    Exec(ARunner, AGitExe, ['commit', '-q', '--allow-empty', '-m', mName], AFolder);
  end;
  TFile.AppendAllText(TPath.Combine(AFolder, 'A.pas'), '// Versuch'#10, TEncoding.ASCII);
  Exec(ARunner, AGitExe, ['stash', 'push', '-q', '-m', 'Versuch'], AFolder);
  TFile.AppendAllText(TPath.Combine(AFolder, 'A.pas'), '// neu'#10, TEncoding.ASCII);
  TFile.AppendAllText(TPath.Combine(AFolder, 'B.pas'), '// neu'#10, TEncoding.ASCII);
  TFile.Delete(TPath.Combine(AFolder, 'D.pas'));
  TFile.WriteAllText(TPath.Combine(AFolder, 'E.pas'), 'unit E;'#10, TEncoding.ASCII);
end;

/// <summary>Remotes, Branches und ungepushte Commits aus PrepareLocalWork.</summary>
procedure AssertBranchesAndOutgoing(const ALocal: IAtlasVcsLocalWork);
var
  mRemotes: TArray<string>;
  mBranches: TArray<TAtlasVcsBranch>;
  mCommits: TArray<TAtlasVcsCommit>;
begin
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, ALocal.Remotes(mRemotes));
  Assert.AreEqual(1, Integer(Length(mRemotes)));
  Assert.AreEqual('origin', mRemotes[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, ALocal.Branches(mBranches));
  Assert.AreEqual(1, Integer(Length(mBranches)));
  Assert.AreEqual('main', mBranches[0].Name);
  Assert.AreEqual('origin/main', mBranches[0].Upstream);
  Assert.AreEqual(3, mBranches[0].Ahead);
  Assert.AreEqual(0, mBranches[0].Behind);
  Assert.IsTrue(mBranches[0].Current);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, ALocal.Outgoing('main', 'origin/main', 10, mCommits));
  Assert.AreEqual(3, Integer(Length(mCommits)));
  Assert.AreEqual('Vier', mCommits[0].Summary, 'neuester zuerst');
end;

/// <summary>Der Stash aus PrepareLocalWork mit seiner einen Datei.</summary>
procedure AssertStash(const ALocal: IAtlasVcsLocalWork; const AFolder: string);
var
  mStashes: TArray<TAtlasVcsStash>;
  mChanges: TArray<TAtlasVcsChange>;
  mChange: TAtlasVcsChange;
begin
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, ALocal.Stashes(mStashes));
  Assert.AreEqual(1, Integer(Length(mStashes)));
  Assert.AreEqual('Versuch', mStashes[0].Message);
  Assert.AreEqual('main', mStashes[0].Branch);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, ALocal.ChangesIn(mStashes[0].Hash, mChanges));
  Assert.AreEqual(1, Integer(Length(mChanges)));
  Assert.IsTrue(Find(mChanges, TPath.Combine(AFolder, 'A.pas'), mChange), 'Datei im Stash');
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Modified, mChange.Kind);
end;

/// <summary>Was die Willkommensseite aus PrepareLocalWork als nicht gesichert zeigt.</summary>
procedure AssertUnsavedState(const AState: TAtlasUnsavedState; const AFolder: string; ANowUtc: TDateTime);
var
  mItem: TAtlasUnsavedItem;
  mProjects: TArray<TAtlasUnsavedProject>;
  mView: TAtlasUnsavedView;
begin
  Assert.IsTrue(AState.Find(TAtlasUnsavedKind.Changes, mItem));
  Assert.AreEqual(4, Integer(mItem.Count));
  Assert.AreEqual(2, mItem.Modified);
  Assert.AreEqual(1, mItem.Added);
  Assert.AreEqual(1, mItem.Deleted);
  Assert.IsTrue(AState.Find(TAtlasUnsavedKind.Commits, mItem));
  Assert.AreEqual(3, Integer(mItem.Count));
  Assert.IsTrue(mItem.Since > 0, 'Alter aus dem ältesten Commit');
  Assert.IsTrue(AState.Find(TAtlasUnsavedKind.Stashes, mItem));
  Assert.AreEqual(1, Integer(mItem.Count));
  Assert.IsFalse(AState.Find(TAtlasUnsavedKind.NoUpstream, mItem));
  SetLength(mProjects, 1);
  mProjects[0] := Default(TAtlasUnsavedProject);
  mProjects[0].Project := TPath.Combine(AFolder, 'Atlas.dproj');
  mProjects[0].State := AState;
  mProjects[0].Fresh := True;
  mView := TAtlasWelcomeUnsaved.View(mProjects, ANowUtc, TAtlasUnsavedOptions.Create(0, 24, 72));
  Assert.AreEqual(3, Integer(Length(mView.Rows)), 'Änderungen, Commits, Stash');
end;

/// <summary>Plant und pusht den Eintrag AKind aus AState: genau ein Plan auf ATarget, für einen Branch ohne
/// Upstream mit --set-upstream.</summary>
procedure PushPlanned(const ALocal: IAtlasVcsLocalWork; const AState: TAtlasUnsavedState;
  AKind: TAtlasUnsavedKind; const ATarget: string);
var
  mItem: TAtlasUnsavedItem;
  mPlans: TArray<TAtlasUnsavedPush>;
begin
  Assert.IsTrue(AState.Find(AKind, mItem));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, TAtlasWelcomeUnsaved.PushPlans(ALocal, mItem, mPlans));
  Assert.AreEqual(1, Integer(Length(mPlans)));
  Assert.AreEqual(ATarget, mPlans[0].Target);
  if AKind = TAtlasUnsavedKind.NoUpstream then
  begin
    Assert.IsTrue(mPlans[0].SetUpstream, 'neuer Branch mit --set-upstream');
  end;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    ALocal.Push(mPlans[0].Branch, mPlans[0].Remote, mPlans[0].RemoteRef, mPlans[0].SetUpstream));
end;

/// <summary>Nach beiden Pushes: beide Branches verfolgt, nichts mehr voraus.</summary>
procedure AssertAllPushed(const ALocal: IAtlasVcsLocalWork);
var
  mBranches: TArray<TAtlasVcsBranch>;
  mName: string;
begin
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, ALocal.Branches(mBranches));
  Assert.AreEqual(2, Integer(Length(mBranches)));
  for mName in TArray<string>.Create('feature/lokal', 'main') do
  begin
    Assert.IsTrue((mBranches[0].Name = mName) or (mBranches[1].Name = mName), mName);
  end;
  Assert.IsTrue(mBranches[0].Tracked and mBranches[1].Tracked, 'beide verfolgt');
  Assert.AreEqual(0, mBranches[0].Ahead + mBranches[1].Ahead, 'alles gepusht');
end;

procedure TAtlasVcsIntegrationTests.GitLocalWorkReportsUnsavedAndPushes;
var
  mGitExe, mFolder, mRemote: string;
  mRunner: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mLocal: IAtlasVcsLocalWork;
  mCommits: TArray<TAtlasVcsCommit>;
  mState: TAtlasUnsavedState;
  mItem: TAtlasUnsavedItem;
  mNowUtc: TDateTime;
begin
  mGitExe := TAtlasVcsTools.Find(TAtlasVcsKind.Git);
  if mGitExe = '' then
  begin
    Assert.Pass('git nicht installiert; Prüfung übersprungen');
  end;
  mRunner := TAtlasVcsProcessRunner.Create(True, nil);
  mRemote := NewFolder('git-remote');
  mFolder := NewFolder('git-local');
  try
    PrepareLocalWork(mRunner, mGitExe, mFolder, mRemote);
    mVcs := TAtlasVersionControl.Open(mFolder, TAtlasVcsProvider.Auto, mRunner);
    Assert.IsTrue(Supports(mVcs, IAtlasVcsLocalWork, mLocal), 'Git kann lokale Arbeit');
    AssertBranchesAndOutgoing(mLocal);
    AssertStash(mLocal, mFolder);
    mNowUtc := TTimeZone.Local.ToUniversalTime(Now);
    Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(mVcs, mFolder, mNowUtc, nil, nil, mState));
    AssertUnsavedState(mState, mFolder, mNowUtc);

    // Branch ohne Upstream mit einem Commit, der auf keinem Remote liegt.
    Exec(mRunner, mGitExe, ['checkout', '-q', '-b', 'feature/lokal'], mFolder);
    Exec(mRunner, mGitExe, ['commit', '-q', '--allow-empty', '-m', 'Nur lokal'], mFolder);
    Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.Outgoing('feature/lokal', '', 10, mCommits));
    Assert.AreEqual(4, Integer(Length(mCommits)), 'drei von main und einer eigener, keiner auf origin');
    Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(mVcs, mFolder, mNowUtc, nil, nil, mState));
    Assert.IsTrue(mState.Find(TAtlasUnsavedKind.NoUpstream, mItem));
    Assert.AreEqual(1, Integer(mItem.Count));
    Assert.AreEqual('feature/lokal', mItem.Branches[0]);

    // Push erst nach Plan: main auf seinen Upstream, der neue Branch mit --set-upstream.
    PushPlanned(mLocal, mState, TAtlasUnsavedKind.Commits, 'origin/main');
    PushPlanned(mLocal, mState, TAtlasUnsavedKind.NoUpstream, 'origin/feature/lokal');
    AssertAllPushed(mLocal);
    Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mLocal.Push('-x', 'origin', 'refs/heads/main', False),
      'keine Optionen als Branch');
  finally
    mVcs := nil;
    mLocal := nil;
    RemoveFolder(mFolder);
    RemoveFolder(mRemote);
  end;
end;

/// <summary>Ablage und Arbeitskopie mit Kunde.pas und Fremd.pas, erster Stand gepusht.</summary>
procedure InitGitWithCustomerUnits(const ARunner: IAtlasVcsRunner; const AGitExe, ARemote, AFolder: string);
var
  mName: string;
  mNames: TArray<string>;
begin
  Exec(ARunner, AGitExe, ['init', '-q', '--bare', ARemote], ARemote);
  // Ohne init.defaultBranch = main zeigte HEAD der Ablage auf master: Der Klon bliebe leer.
  Exec(ARunner, AGitExe, ['symbolic-ref', 'HEAD', 'refs/heads/main'], ARemote);
  Exec(ARunner, AGitExe, ['init', '-q'], AFolder);
  Exec(ARunner, AGitExe, ['symbolic-ref', 'HEAD', 'refs/heads/main'], AFolder);
  Exec(ARunner, AGitExe, ['config', 'user.name', 'Atlas Test'], AFolder);
  Exec(ARunner, AGitExe, ['config', 'user.email', 'test@example.org'], AFolder);
  Exec(ARunner, AGitExe, ['config', 'core.autocrlf', 'false'], AFolder);
  Exec(ARunner, AGitExe, ['config', 'commit.gpgsign', 'false'], AFolder);
  mNames := ['Kunde', 'Fremd'];
  for mName in mNames do
  begin
    TFile.WriteAllText(TPath.Combine(AFolder, mName + '.pas'), 'unit ' + mName + ';'#10, TEncoding.ASCII);
  end;
  Exec(ARunner, AGitExe, ['add', '.'], AFolder);
  Exec(ARunner, AGitExe, ['commit', '-q', '-m', 'Erster Stand'], AFolder);
  Exec(ARunner, AGitExe, ['remote', 'add', 'origin', ARemote], AFolder);
  Exec(ARunner, AGitExe, ['push', '-q', '-u', 'origin', 'main'], AFolder);
end;

/// <summary>Ein Kollege pusht je einen Commit zu Kunde.pas und zu Fremd.pas.</summary>
procedure PushColleagueCommits(const ARunner: IAtlasVcsRunner; const AGitExe, ARemote, AOther: string);
begin
  Exec(ARunner, AGitExe, ['clone', '-q', ARemote, AOther], AOther);
  Exec(ARunner, AGitExe, ['config', 'user.name', 'Eva Kollegin'], AOther);
  Exec(ARunner, AGitExe, ['config', 'user.email', 'eva@example.org'], AOther);
  Exec(ARunner, AGitExe, ['config', 'core.autocrlf', 'false'], AOther);
  Exec(ARunner, AGitExe, ['config', 'commit.gpgsign', 'false'], AOther);
  TFile.AppendAllText(TPath.Combine(AOther, 'Kunde.pas'), '// Prüfung'#10, TEncoding.UTF8);
  Exec(ARunner, AGitExe, ['commit', '-q', '-am', 'Kunde: Prüfung'], AOther);
  TFile.AppendAllText(TPath.Combine(AOther, 'Fremd.pas'), '// anders'#10, TEncoding.ASCII);
  Exec(ARunner, AGitExe, ['commit', '-q', '-am', 'Fremd geändert'], AOther);
  Exec(ARunner, AGitExe, ['push', '-q', 'origin', 'main'], AOther);
end;

procedure TAtlasVcsIntegrationTests.GitIncomingCommitsOnEditedFiles;
var
  mGitExe, mRemote, mFolder, mOther: string;
  mRunner: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mState: TAtlasWorkState;
  mFound: TAtlasContinueIncoming;
  mNowUtc: TDateTime;
begin
  mGitExe := TAtlasVcsTools.Find(TAtlasVcsKind.Git);
  if mGitExe = '' then
  begin
    Assert.Pass('git nicht installiert; Prüfung übersprungen');
  end;
  mRunner := TAtlasVcsProcessRunner.Create(True, nil);
  mRemote := NewFolder('git-in-remote');
  mFolder := NewFolder('git-in-local');
  mOther := NewFolder('git-in-other');
  try
    InitGitWithCustomerUnits(mRunner, mGitExe, mRemote, mFolder);
    mVcs := TAtlasVersionControl.Open(mFolder, TAtlasVcsProvider.Auto, mRunner);
    // Beim Schließen: Kunde.pas offen, HEAD und origin/main gemerkt.
    mState := TAtlasWorkState.Empty;
    mState.Tabs := [TAtlasWorkTab.Create(TPath.Combine(mFolder, 'Kunde.pas'), 1, 1)];
    Assert.IsTrue(TAtlasWelcomeContinue.ProbeHead(mVcs, mState));
    Assert.AreEqual('git', mState.VcsKind);
    Assert.AreEqual('origin/main', mState.Upstream);
    Assert.AreEqual(40, Integer(Length(mState.Head)));
    Assert.AreEqual(mState.Head, mState.UpstreamRevision);
    // Ein Kollege pusht je einen Commit zu Kunde.pas und zu Fremd.pas.
    PushColleagueCommits(mRunner, mGitExe, mRemote, mOther);
    mNowUtc := TTimeZone.Local.ToUniversalTime(Now);
    // Ohne fetch: Grundlage ist der lokale Stand der Remote-Branches, dort ist noch nichts Neues.
    Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, nil, TPath.Combine(mFolder, 'Atlas.dproj'), mState, mNowUtc,
      mFound));
    Assert.IsTrue(mFound.Available);
    Assert.AreEqual(0, Integer(Length(mFound.Commits)));
    // Mit fetch: nur der Commit zur offenen Datei.
    Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(mVcs, mVcs, TPath.Combine(mFolder, 'Atlas.dproj'), mState, mNowUtc,
      mFound));
    Assert.IsFalse(mFound.FetchFailed);
    Assert.AreEqual('origin/main', mFound.Upstream);
    Assert.AreEqual(1, Integer(Length(mFound.Commits)), 'Commit zu einer anderen Datei erscheint nicht');
    Assert.AreEqual('Kunde: Prüfung', mFound.Commits[0].Commit.Summary);
    Assert.AreEqual('Eva Kollegin', mFound.Commits[0].Commit.Author);
    Assert.AreEqual(TPath.Combine(mFolder, 'Kunde.pas'), mFound.Commits[0].Files[0]);
    Assert.AreEqual(7, Integer(Length(mFound.Commits[0].Commit.ShortHash)));
  finally
    mVcs := nil;
    RemoveFolder(mFolder);
    RemoveFolder(mOther);
    RemoveFolder(mRemote);
  end;
end;

procedure TAtlasVcsIntegrationTests.RunnerRefusesMainThreadAndHonoursTimeout;
var
  mRunner: IAtlasVcsRunner;
  mPing: string;
  mAnswer: TAtlasVcsRunResult;
  mStarted: UInt64;
begin
  mPing := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\PING.EXE');
  mRunner := TAtlasVcsProcessRunner.Create;
  mAnswer := mRunner.Run(mPing, ['-n', '1', '127.0.0.1'], '', 5000);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.MainThread, mAnswer.Outcome, 'Hauptthread abgelehnt');
  mRunner := TAtlasVcsProcessRunner.Create(True, nil);
  mAnswer := mRunner.Run(TPath.Combine(TPath.GetTempPath, 'gibt-es-nicht.exe'), [], '', 5000);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.ToolMissing, mAnswer.Outcome);
  mStarted := TThread.GetTickCount64;
  mAnswer := mRunner.Run(mPing, ['-n', '30', '127.0.0.1'], '', 300);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.TimedOut, mAnswer.Outcome, 'Zeitlimit');
  Assert.IsTrue(TThread.GetTickCount64 - mStarted < 5000, 'Prozess beendet, nicht abgewartet');
  mAnswer := mRunner.Run(mPing, ['-n', '1', '127.0.0.1'], '', 10000);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mAnswer.Outcome);
  Assert.IsTrue(Length(mAnswer.Output) > 0, 'stdout gelesen');
  Assert.AreEqual('"a b"', TAtlasVcsProcessRunner.QuoteArgument('a b'));
  Assert.AreEqual('"x\"y"', TAtlasVcsProcessRunner.QuoteArgument('x"y'));
  Assert.AreEqual('"C:\a b\\"', TAtlasVcsProcessRunner.QuoteArgument('C:\a b\'));
  Assert.AreEqual('""', TAtlasVcsProcessRunner.QuoteArgument(''));
end;

/// <summary>Arbeitskopie des Repositorys, in dem die Tests laufen, mit dem Läufer der IDE.</summary>
function RepositoryVcs(const AGitExe: string): IAtlasVersionControl;
var
  mRunner: IAtlasVcsRunner;
begin
  // Der Läufer der IDE: lehnt den Hauptthread ab, im Worker läuft er.
  mRunner := TAtlasVcsProcessRunner.Create;
  Result := TAtlasVersionControl.ForWorkingCopy(Default(TAtlasVcsWorkingCopy), mRunner, AGitExe, 5000);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, Result.Kind, 'ohne Arbeitskopie die leere Umsetzung');
  // Arbeitskopie des Repositorys, in dem die Tests laufen; ohne: irgendein Ordner (dann NoWorkingCopy).
  Result := TAtlasVersionControl.Open(ExtractFilePath(ParamStr(0)), TAtlasVcsProvider.Auto, mRunner);
end;

/// <summary>In einer Git-Arbeitskopie liefert Head den Commit.</summary>
procedure AssertRepositoryHead(const AVcs: IAtlasVersionControl; AOutcome: TAtlasVcsOutcome;
  const AHead: TAtlasVcsHead);
begin
  if AVcs.Kind = TAtlasVcsKind.Git then
  begin
    Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, AOutcome);
    Assert.AreNotEqual('', AHead.Revision, 'Commit des Repositorys');
  end;
end;

procedure TAtlasVcsIntegrationTests.WorkerRunsInBackgroundAndDeliversInMainThread;
var
  mWorker: TAtlasVcsWorker;
  mVcs: IAtlasVersionControl;
  mOutcome: TAtlasVcsOutcome;
  mHead: TAtlasVcsHead;
  mDone, mInMain: Boolean;
  mDeadline: UInt64;
  mGitExe: string;
begin
  mGitExe := TAtlasVcsTools.Find(TAtlasVcsKind.Git);
  if mGitExe = '' then
  begin
    Assert.Pass('git nicht installiert; Prüfung übersprungen');
  end;
  mVcs := RepositoryVcs(mGitExe);
  mDone := False;
  mInMain := False;
  mOutcome := TAtlasVcsOutcome.Failed;
  mWorker := TAtlasVcsWorker.Create;
  try
    Assert.IsTrue(mWorker.Run(
      procedure
      begin
        mOutcome := mVcs.Head(mHead);
      end,
      procedure
      begin
        mInMain := TThread.CurrentThread.ThreadID = MainThreadID;
        mDone := True;
      end), 'gestartet');
    mDeadline := TThread.GetTickCount64 + 20000;
    while not mDone and (TThread.GetTickCount64 < mDeadline) do
    begin
      CheckSynchronize(10);
    end;
    Assert.IsTrue(mDone, 'Ergebnis zugestellt');
    Assert.IsTrue(mInMain, 'im Hauptthread');
    Assert.AreNotEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.MainThread, mOutcome, 'im Hintergrund gelaufen');
    AssertRepositoryHead(mVcs, mOutcome, mHead);
    Assert.AreEqual(0, mWorker.Pending);
    // Nach Stop kommt nichts mehr an.
    mDone := False;
    mWorker.Stop(1000);
    Assert.IsFalse(mWorker.Run(
      procedure
      begin
      end,
      procedure
      begin
        mDone := True;
      end), 'nach Stop nicht gestartet');
    CheckSynchronize(50);
    Assert.IsFalse(mDone);
  finally
    mWorker.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsIntegrationTests);

end.
