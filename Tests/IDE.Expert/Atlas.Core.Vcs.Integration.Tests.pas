unit Atlas.Core.Vcs.Integration.Tests;

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
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.Switches,
  Atlas.Core.Vcs.Worker,
  Atlas.Core.Vcs.Composition,
  Atlas.Core.Vcs.Adapters.ProcessRunner,
  Atlas.Core.Welcome.Unsaved,
  Atlas.Core.Welcome.Continue;

/// <summary>Führt ein Programm für den Aufbau der Fixture aus; Ausgabe als Text, Ausnahme bei Fehler.</summary>
function Exec(const ARunner: IAtlasVcsRunner; const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir: string): string;
var
  Answer: TAtlasVcsRunResult;
begin
  Answer := ARunner.Run(AExecutable, AArguments, AWorkingDir, 30000);
  if (Answer.Outcome <> TAtlasVcsOutcome.Ok) or (Answer.ExitCode <> 0) then
    raise Exception.CreateFmt('%s %s: Exit-Code %d, %s', [ExtractFileName(AExecutable),
      string.Join(' ', AArguments), Answer.ExitCode, Answer.ErrorText]);
  Result := Trim(TEncoding.UTF8.GetString(Answer.Output));
end;

function NewFolder(const AName: string): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, 'AtlasVcs-' + AName + '-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(Result);
end;

procedure RemoveFolder(const AFolder: string);
var
  FileName: string;
begin
  if not TDirectory.Exists(AFolder) then
    Exit;
  // git legt schreibgeschützte Objektdateien an.
  for FileName in TDirectory.GetFiles(AFolder, '*', TSearchOption.soAllDirectories) do
  begin
    {$WARN SYMBOL_PLATFORM OFF}
    TFile.SetAttributes(FileName, [TFileAttribute.faNormal]);
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
  Item: TAtlasVcsChange;
begin
  for Item in AChanges do
    if SameText(Item.Path, APath) then
    begin
      AChange := Item;
      Exit(True);
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

procedure TAtlasVcsIntegrationTests.GitWorkingCopyReportsBranchRevisionAndChanges;
var
  GitExe, Folder, Commit: string;
  Runner: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Head: TAtlasVcsHead;
  Changes: TArray<TAtlasVcsChange>;
  Change: TAtlasVcsChange;
  Content: TBytes;
  Lines: TArray<TAtlasVcsBlameLine>;
  Watch: TAtlasVcsWatch;
begin
  GitExe := TAtlasVcsTools.Find(TAtlasVcsKind.Git);
  if GitExe = '' then
    Assert.Pass('git nicht installiert; Prüfung übersprungen');
  // Im Test erlaubt: Der Hauptthread des Testprogramms ist keine IDE.
  Runner := TAtlasVcsProcessRunner.Create(True, nil);
  Folder := NewFolder('git');
  try
    Exec(Runner, GitExe, ['init', '-q'], Folder);
    Exec(Runner, GitExe, ['symbolic-ref', 'HEAD', 'refs/heads/main'], Folder);
    Exec(Runner, GitExe, ['config', 'user.name', 'Atlas Test'], Folder);
    Exec(Runner, GitExe, ['config', 'user.email', 'test@example.org'], Folder);
    Exec(Runner, GitExe, ['config', 'core.autocrlf', 'false'], Folder);
    Exec(Runner, GitExe, ['config', 'commit.gpgsign', 'false'], Folder);
    TFile.WriteAllText(TPath.Combine(Folder, 'A.pas'), 'unit A;'#10'end.'#10, TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(Folder, 'B.pas'), 'unit B;'#10, TEncoding.ASCII);
    Exec(Runner, GitExe, ['add', '.'], Folder);
    Exec(Runner, GitExe, ['commit', '-q', '-m', 'Erster Stand'], Folder);
    Commit := Exec(Runner, GitExe, ['rev-parse', 'HEAD'], Folder);
    TDirectory.CreateDirectory(TPath.Combine(Folder, 'src'));

    Vcs := TAtlasVersionControl.Open(TPath.Combine(Folder, 'src'), TAtlasVcsProvider.Auto, Runner);
    Assert.IsTrue(Vcs.Kind = TAtlasVcsKind.Git);
    Assert.AreEqual(ExcludeTrailingPathDelimiter(Folder), Vcs.WorkingCopy.Root);
    Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual('main', Head.Branch);
    Assert.AreEqual(Commit, Head.Revision);
    Assert.IsTrue(Vcs.Changes(Changes) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(0, Integer(Length(Changes)), 'frisch übernommen');

    TFile.AppendAllText(TPath.Combine(Folder, 'A.pas'), '// neu'#10, TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(Folder, 'src\Neu Datei.pas'), 'unit Neu;'#10, TEncoding.ASCII);
    TFile.Delete(TPath.Combine(Folder, 'B.pas'));
    Assert.IsTrue(Vcs.Changes(Changes) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(3, Integer(Length(Changes)));
    Assert.IsTrue(Find(Changes, TPath.Combine(Folder, 'A.pas'), Change));
    Assert.IsTrue(Change.Kind = TAtlasVcsChangeKind.Modified);
    Assert.IsTrue(Find(Changes, TPath.Combine(Folder, 'src\Neu Datei.pas'), Change), 'neue Datei im Unterordner');
    Assert.IsTrue(Change.Kind = TAtlasVcsChangeKind.Untracked);
    Assert.IsTrue(Find(Changes, TPath.Combine(Folder, 'B.pas'), Change));
    Assert.IsTrue(Change.Kind = TAtlasVcsChangeKind.Deleted);

    Assert.IsTrue(Vcs.FileAt(TPath.Combine(Folder, 'A.pas'), '', Content) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual('unit A;'#10'end.'#10, TEncoding.UTF8.GetString(Content), 'Stand im Repository');
    Assert.IsTrue(Vcs.Blame(TPath.Combine(Folder, 'A.pas'), Lines) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(3, Integer(Length(Lines)));
    Assert.AreEqual(Commit, Lines[0].Revision);
    Assert.AreEqual('Atlas Test', Lines[0].Author);
    Assert.AreEqual('Erster Stand', Lines[0].Summary);
    Assert.IsTrue(Lines[2].Uncommitted);

    Watch := TAtlasVcsWatch.Create(Vcs);
    try
      Assert.IsTrue(Watch.Check = TAtlasVcsSwitch.None);
      Exec(Runner, GitExe, ['checkout', '-q', '-b', 'feature/x'], Folder);
      Assert.IsTrue(Watch.Check = TAtlasVcsSwitch.Branch, 'git checkout -b');
      Assert.AreEqual('feature/x', Watch.Head.Branch);
      Exec(Runner, GitExe, ['commit', '-q', '-a', '-m', 'Zweiter Stand'], Folder);
      Assert.IsTrue(Watch.Check = TAtlasVcsSwitch.Revision, 'Commit');
    finally
      Watch.Free;
    end;
  finally
    Vcs := nil;
    RemoveFolder(Folder);
  end;
end;

procedure TAtlasVcsIntegrationTests.SvnWorkingCopyReportsBranchRevisionAndChanges;
var
  SvnExe, SvnAdmin, Folder, Repository, Url, WorkingCopy: string;
  Runner: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Head: TAtlasVcsHead;
  Changes: TArray<TAtlasVcsChange>;
  Change: TAtlasVcsChange;
  Content: TBytes;
  Lines: TArray<TAtlasVcsBlameLine>;
  Watch: TAtlasVcsWatch;
begin
  // Ohne svn bzw. svnadmin übersprungen. Exit statt Assert.Pass: DUnitX behält die Meldung
  // im Ergebnis, und der Leckmonitor zählte sie als Leck.
  SvnExe := TAtlasVcsTools.Find(TAtlasVcsKind.Svn);
  if SvnExe = '' then
    Exit;
  SvnAdmin := TPath.Combine(ExtractFilePath(SvnExe), 'svnadmin.exe');
  if not TFile.Exists(SvnAdmin) then
    Exit;
  Runner := TAtlasVcsProcessRunner.Create(True, nil);
  Folder := NewFolder('svn');
  try
    Repository := TPath.Combine(Folder, 'repo');
    WorkingCopy := TPath.Combine(Folder, 'wc');
    Exec(Runner, SvnAdmin, ['create', Repository], Folder);
    Url := 'file:///' + StringReplace(Repository, '\', '/', [rfReplaceAll]);
    Exec(Runner, SvnExe, ['mkdir', '-q', '-m', 'Ablage', Url + '/trunk', Url + '/branches', '--non-interactive'],
      Folder);
    Exec(Runner, SvnExe, ['checkout', '-q', Url + '/trunk', WorkingCopy, '--non-interactive'], Folder);
    TFile.WriteAllText(TPath.Combine(WorkingCopy, 'A.pas'), 'unit A;'#10'end.'#10, TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(WorkingCopy, 'B.pas'), 'unit B;'#10, TEncoding.ASCII);
    Exec(Runner, SvnExe, ['add', '-q', 'A.pas', 'B.pas'], WorkingCopy);
    Exec(Runner, SvnExe, ['commit', '-q', '-m', 'Erster Stand', '--non-interactive'], WorkingCopy);
    Exec(Runner, SvnExe, ['update', '-q', '--non-interactive'], WorkingCopy);

    Vcs := TAtlasVersionControl.Open(WorkingCopy, TAtlasVcsProvider.Auto, Runner);
    Assert.IsTrue(Vcs.Kind = TAtlasVcsKind.Svn);
    Assert.IsTrue(SameText(ExcludeTrailingPathDelimiter(WorkingCopy), Vcs.WorkingCopy.Root));
    Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual('trunk', Head.Branch);
    Assert.AreEqual('2', Head.Revision, 'Ablage = r1, erster Stand = r2');

    TFile.AppendAllText(TPath.Combine(WorkingCopy, 'A.pas'), '// neu'#10, TEncoding.ASCII);
    TFile.WriteAllText(TPath.Combine(WorkingCopy, 'Neu.pas'), 'unit Neu;'#10, TEncoding.ASCII);
    Assert.IsTrue(Vcs.Changes(Changes) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(2, Integer(Length(Changes)));
    Assert.IsTrue(Find(Changes, TPath.Combine(WorkingCopy, 'A.pas'), Change));
    Assert.IsTrue(Change.Kind = TAtlasVcsChangeKind.Modified);
    Assert.IsTrue(Find(Changes, TPath.Combine(WorkingCopy, 'Neu.pas'), Change));
    Assert.IsTrue(Change.Kind = TAtlasVcsChangeKind.Untracked);

    Assert.IsTrue(Vcs.FileAt(TPath.Combine(WorkingCopy, 'A.pas'), '', Content) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual('unit A;'#10'end.'#10, TEncoding.UTF8.GetString(Content), 'BASE');
    Assert.IsTrue(Vcs.Blame(TPath.Combine(WorkingCopy, 'A.pas'), Lines) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(3, Integer(Length(Lines)));
    Assert.AreEqual('2', Lines[0].Revision);
    Assert.IsTrue(Lines[2].Uncommitted);

    Watch := TAtlasVcsWatch.Create(Vcs);
    try
      Assert.IsTrue(Watch.Check = TAtlasVcsSwitch.None);
      Exec(Runner, SvnExe, ['revert', '-q', 'A.pas'], WorkingCopy);
      Exec(Runner, SvnExe, ['copy', '-q', '-m', 'Branch', Url + '/trunk', Url + '/branches/x', '--non-interactive'],
        WorkingCopy);
      Exec(Runner, SvnExe, ['switch', '-q', Url + '/branches/x', '--non-interactive'], WorkingCopy);
      Assert.IsTrue(Watch.Check = TAtlasVcsSwitch.Branch, 'svn switch');
      Assert.AreEqual('branches/x', Watch.Head.Branch);
    finally
      Watch.Free;
    end;
  finally
    Vcs := nil;
    RemoveFolder(Folder);
  end;
end;

procedure TAtlasVcsIntegrationTests.GitLocalWorkReportsUnsavedAndPushes;
var
  GitExe, Folder, Remote: string;
  Runner: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Local: IAtlasVcsLocalWork;
  Branches: TArray<TAtlasVcsBranch>;
  Stashes: TArray<TAtlasVcsStash>;
  Commits: TArray<TAtlasVcsCommit>;
  Changes: TArray<TAtlasVcsChange>;
  Change: TAtlasVcsChange;
  Remotes: TArray<string>;
  State: TAtlasUnsavedState;
  Item: TAtlasUnsavedItem;
  Projects: TArray<TAtlasUnsavedProject>;
  View: TAtlasUnsavedView;
  Plans: TArray<TAtlasUnsavedPush>;
  NowUtc: TDateTime;
  Name: string;
  Names: TArray<string>;
begin
  GitExe := TAtlasVcsTools.Find(TAtlasVcsKind.Git);
  if GitExe = '' then
    Assert.Pass('git nicht installiert; Prüfung übersprungen');
  Runner := TAtlasVcsProcessRunner.Create(True, nil);
  Remote := NewFolder('git-remote');
  Folder := NewFolder('git-local');
  try
    Exec(Runner, GitExe, ['init', '-q', '--bare', Remote], Remote);
    // Ohne init.defaultBranch = main zeigte HEAD der Ablage auf master: Der Klon bliebe leer.
    Exec(Runner, GitExe, ['symbolic-ref', 'HEAD', 'refs/heads/main'], Remote);
    Exec(Runner, GitExe, ['init', '-q'], Folder);
    Exec(Runner, GitExe, ['symbolic-ref', 'HEAD', 'refs/heads/main'], Folder);
    Exec(Runner, GitExe, ['config', 'user.name', 'Atlas Test'], Folder);
    Exec(Runner, GitExe, ['config', 'user.email', 'test@example.org'], Folder);
    Exec(Runner, GitExe, ['config', 'core.autocrlf', 'false'], Folder);
    Exec(Runner, GitExe, ['config', 'commit.gpgsign', 'false'], Folder);
    Names := ['A', 'B', 'C', 'D'];
    for Name in Names do
      TFile.WriteAllText(TPath.Combine(Folder, Name + '.pas'), 'unit ' + Name + ';'#10, TEncoding.ASCII);
    Exec(Runner, GitExe, ['add', '.'], Folder);
    Exec(Runner, GitExe, ['commit', '-q', '-m', 'Erster Stand'], Folder);
    Exec(Runner, GitExe, ['remote', 'add', 'origin', Remote], Folder);
    Exec(Runner, GitExe, ['push', '-q', '-u', 'origin', 'main'], Folder);
    // Abnahme: 3 ungepushte Commits, 1 Stash, 4 geänderte Dateien.
    Names := ['Zwei', 'Drei', 'Vier'];
    for Name in Names do
      Exec(Runner, GitExe, ['commit', '-q', '--allow-empty', '-m', Name], Folder);
    TFile.AppendAllText(TPath.Combine(Folder, 'A.pas'), '// Versuch'#10, TEncoding.ASCII);
    Exec(Runner, GitExe, ['stash', 'push', '-q', '-m', 'Versuch'], Folder);
    TFile.AppendAllText(TPath.Combine(Folder, 'A.pas'), '// neu'#10, TEncoding.ASCII);
    TFile.AppendAllText(TPath.Combine(Folder, 'B.pas'), '// neu'#10, TEncoding.ASCII);
    TFile.Delete(TPath.Combine(Folder, 'D.pas'));
    TFile.WriteAllText(TPath.Combine(Folder, 'E.pas'), 'unit E;'#10, TEncoding.ASCII);

    Vcs := TAtlasVersionControl.Open(Folder, TAtlasVcsProvider.Auto, Runner);
    Assert.IsTrue(Supports(Vcs, IAtlasVcsLocalWork, Local), 'Git kann lokale Arbeit');
    Assert.IsTrue(Local.Remotes(Remotes) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(1, Integer(Length(Remotes)));
    Assert.AreEqual('origin', Remotes[0]);
    Assert.IsTrue(Local.Branches(Branches) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(1, Integer(Length(Branches)));
    Assert.AreEqual('main', Branches[0].Name);
    Assert.AreEqual('origin/main', Branches[0].Upstream);
    Assert.AreEqual(3, Branches[0].Ahead);
    Assert.AreEqual(0, Branches[0].Behind);
    Assert.IsTrue(Branches[0].Current);
    Assert.IsTrue(Local.Outgoing('main', 'origin/main', 10, Commits) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(3, Integer(Length(Commits)));
    Assert.AreEqual('Vier', Commits[0].Summary, 'neuester zuerst');
    Assert.IsTrue(Local.Stashes(Stashes) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(1, Integer(Length(Stashes)));
    Assert.AreEqual('Versuch', Stashes[0].Message);
    Assert.AreEqual('main', Stashes[0].Branch);
    Assert.IsTrue(Local.ChangesIn(Stashes[0].Hash, Changes) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(1, Integer(Length(Changes)));
    Assert.IsTrue(Find(Changes, TPath.Combine(Folder, 'A.pas'), Change), 'Datei im Stash');
    Assert.IsTrue(Change.Kind = TAtlasVcsChangeKind.Modified);

    NowUtc := TTimeZone.Local.ToUniversalTime(Now);
    Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(Vcs, Folder, NowUtc, nil, nil, State));
    Assert.IsTrue(State.Find(TAtlasUnsavedKind.Changes, Item));
    Assert.AreEqual(4, Integer(Item.Count));
    Assert.AreEqual(2, Item.Modified);
    Assert.AreEqual(1, Item.Added);
    Assert.AreEqual(1, Item.Deleted);
    Assert.IsTrue(State.Find(TAtlasUnsavedKind.Commits, Item));
    Assert.AreEqual(3, Integer(Item.Count));
    Assert.IsTrue(Item.Since > 0, 'Alter aus dem ältesten Commit');
    Assert.IsTrue(State.Find(TAtlasUnsavedKind.Stashes, Item));
    Assert.AreEqual(1, Integer(Item.Count));
    Assert.IsFalse(State.Find(TAtlasUnsavedKind.NoUpstream, Item));
    SetLength(Projects, 1);
    Projects[0] := Default(TAtlasUnsavedProject);
    Projects[0].Project := TPath.Combine(Folder, 'Atlas.dproj');
    Projects[0].State := State;
    Projects[0].Fresh := True;
    View := TAtlasWelcomeUnsaved.View(Projects, NowUtc, TAtlasUnsavedOptions.Create(0, 24, 72));
    Assert.AreEqual(3, Integer(Length(View.Rows)), 'Änderungen, Commits, Stash');

    // Branch ohne Upstream mit einem Commit, der auf keinem Remote liegt.
    Exec(Runner, GitExe, ['checkout', '-q', '-b', 'feature/lokal'], Folder);
    Exec(Runner, GitExe, ['commit', '-q', '--allow-empty', '-m', 'Nur lokal'], Folder);
    Assert.IsTrue(Local.Outgoing('feature/lokal', '', 10, Commits) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(4, Integer(Length(Commits)), 'drei von main und einer eigener, keiner auf origin');
    Assert.IsTrue(TAtlasWelcomeUnsaved.Probe(Vcs, Folder, NowUtc, nil, nil, State));
    Assert.IsTrue(State.Find(TAtlasUnsavedKind.NoUpstream, Item));
    Assert.AreEqual(1, Integer(Item.Count));
    Assert.AreEqual('feature/lokal', Item.Branches[0]);

    // Push erst nach Plan: main auf seinen Upstream, der neue Branch mit --set-upstream.
    Assert.IsTrue(State.Find(TAtlasUnsavedKind.Commits, Item));
    Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(Local, Item, Plans) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(1, Integer(Length(Plans)));
    Assert.AreEqual('origin/main', Plans[0].Target);
    Assert.IsTrue(Local.Push(Plans[0].Branch, Plans[0].Remote, Plans[0].RemoteRef, Plans[0].SetUpstream) =
      TAtlasVcsOutcome.Ok);
    Assert.IsTrue(State.Find(TAtlasUnsavedKind.NoUpstream, Item));
    Assert.IsTrue(TAtlasWelcomeUnsaved.PushPlans(Local, Item, Plans) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(1, Integer(Length(Plans)));
    Assert.IsTrue(Plans[0].SetUpstream);
    Assert.AreEqual('origin/feature/lokal', Plans[0].Target);
    Assert.IsTrue(Local.Push(Plans[0].Branch, Plans[0].Remote, Plans[0].RemoteRef, Plans[0].SetUpstream) =
      TAtlasVcsOutcome.Ok);
    Assert.IsTrue(Local.Branches(Branches) = TAtlasVcsOutcome.Ok);
    Assert.AreEqual(2, Integer(Length(Branches)));
    Names := ['feature/lokal', 'main'];
    for Name in Names do
      Assert.IsTrue((Branches[0].Name = Name) or (Branches[1].Name = Name), Name);
    Assert.IsTrue(Branches[0].Tracked and Branches[1].Tracked, 'beide verfolgt');
    Assert.AreEqual(0, Branches[0].Ahead + Branches[1].Ahead, 'alles gepusht');
    Assert.IsTrue(Local.Push('-x', 'origin', 'refs/heads/main', False) = TAtlasVcsOutcome.Failed,
      'keine Optionen als Branch');
  finally
    Vcs := nil;
    Local := nil;
    RemoveFolder(Folder);
    RemoveFolder(Remote);
  end;
end;

procedure TAtlasVcsIntegrationTests.GitIncomingCommitsOnEditedFiles;
var
  GitExe, Remote, Folder, Other: string;
  Runner: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  State: TAtlasWorkState;
  Found: TAtlasContinueIncoming;
  NowUtc: TDateTime;
  Name: string;
  Names: TArray<string>;
begin
  GitExe := TAtlasVcsTools.Find(TAtlasVcsKind.Git);
  if GitExe = '' then
    Assert.Pass('git nicht installiert; Prüfung übersprungen');
  Runner := TAtlasVcsProcessRunner.Create(True, nil);
  Remote := NewFolder('git-in-remote');
  Folder := NewFolder('git-in-local');
  Other := NewFolder('git-in-other');
  try
    Exec(Runner, GitExe, ['init', '-q', '--bare', Remote], Remote);
    // Ohne init.defaultBranch = main zeigte HEAD der Ablage auf master: Der Klon bliebe leer.
    Exec(Runner, GitExe, ['symbolic-ref', 'HEAD', 'refs/heads/main'], Remote);
    Exec(Runner, GitExe, ['init', '-q'], Folder);
    Exec(Runner, GitExe, ['symbolic-ref', 'HEAD', 'refs/heads/main'], Folder);
    Exec(Runner, GitExe, ['config', 'user.name', 'Atlas Test'], Folder);
    Exec(Runner, GitExe, ['config', 'user.email', 'test@example.org'], Folder);
    Exec(Runner, GitExe, ['config', 'core.autocrlf', 'false'], Folder);
    Exec(Runner, GitExe, ['config', 'commit.gpgsign', 'false'], Folder);
    Names := ['Kunde', 'Fremd'];
    for Name in Names do
      TFile.WriteAllText(TPath.Combine(Folder, Name + '.pas'), 'unit ' + Name + ';'#10, TEncoding.ASCII);
    Exec(Runner, GitExe, ['add', '.'], Folder);
    Exec(Runner, GitExe, ['commit', '-q', '-m', 'Erster Stand'], Folder);
    Exec(Runner, GitExe, ['remote', 'add', 'origin', Remote], Folder);
    Exec(Runner, GitExe, ['push', '-q', '-u', 'origin', 'main'], Folder);
    Vcs := TAtlasVersionControl.Open(Folder, TAtlasVcsProvider.Auto, Runner);
    // Beim Schließen: Kunde.pas offen, HEAD und origin/main gemerkt.
    State := TAtlasWorkState.Empty;
    State.Tabs := [TAtlasWorkTab.Create(TPath.Combine(Folder, 'Kunde.pas'), 1, 1)];
    Assert.IsTrue(TAtlasWelcomeContinue.ProbeHead(Vcs, State));
    Assert.AreEqual('git', State.VcsKind);
    Assert.AreEqual('origin/main', State.Upstream);
    Assert.AreEqual(40, Integer(Length(State.Head)));
    Assert.AreEqual(State.Head, State.UpstreamRevision);
    // Ein Kollege pusht je einen Commit zu Kunde.pas und zu Fremd.pas.
    Exec(Runner, GitExe, ['clone', '-q', Remote, Other], Other);
    Exec(Runner, GitExe, ['config', 'user.name', 'Eva Kollegin'], Other);
    Exec(Runner, GitExe, ['config', 'user.email', 'eva@example.org'], Other);
    Exec(Runner, GitExe, ['config', 'core.autocrlf', 'false'], Other);
    Exec(Runner, GitExe, ['config', 'commit.gpgsign', 'false'], Other);
    TFile.AppendAllText(TPath.Combine(Other, 'Kunde.pas'), '// Prüfung'#10, TEncoding.UTF8);
    Exec(Runner, GitExe, ['commit', '-q', '-am', 'Kunde: Prüfung'], Other);
    TFile.AppendAllText(TPath.Combine(Other, 'Fremd.pas'), '// anders'#10, TEncoding.ASCII);
    Exec(Runner, GitExe, ['commit', '-q', '-am', 'Fremd geändert'], Other);
    Exec(Runner, GitExe, ['push', '-q', 'origin', 'main'], Other);
    NowUtc := TTimeZone.Local.ToUniversalTime(Now);
    // Ohne fetch: Grundlage ist der lokale Stand der Remote-Branches, dort ist noch nichts Neues.
    Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(Vcs, nil, TPath.Combine(Folder, 'Atlas.dproj'), State, NowUtc,
      Found));
    Assert.IsTrue(Found.Available);
    Assert.AreEqual(0, Integer(Length(Found.Commits)));
    // Mit fetch: nur der Commit zur offenen Datei.
    Assert.IsTrue(TAtlasWelcomeContinue.ProbeIncoming(Vcs, Vcs, TPath.Combine(Folder, 'Atlas.dproj'), State, NowUtc,
      Found));
    Assert.IsFalse(Found.FetchFailed);
    Assert.AreEqual('origin/main', Found.Upstream);
    Assert.AreEqual(1, Integer(Length(Found.Commits)), 'Commit zu einer anderen Datei erscheint nicht');
    Assert.AreEqual('Kunde: Prüfung', Found.Commits[0].Commit.Summary);
    Assert.AreEqual('Eva Kollegin', Found.Commits[0].Commit.Author);
    Assert.AreEqual(TPath.Combine(Folder, 'Kunde.pas'), Found.Commits[0].Files[0]);
    Assert.AreEqual(7, Integer(Length(Found.Commits[0].Commit.ShortHash)));
  finally
    Vcs := nil;
    RemoveFolder(Folder);
    RemoveFolder(Other);
    RemoveFolder(Remote);
  end;
end;

procedure TAtlasVcsIntegrationTests.RunnerRefusesMainThreadAndHonoursTimeout;
var
  Runner: IAtlasVcsRunner;
  Ping: string;
  Answer: TAtlasVcsRunResult;
  Started: UInt64;
begin
  Ping := TPath.Combine(GetEnvironmentVariable('SystemRoot'), 'System32\PING.EXE');
  Runner := TAtlasVcsProcessRunner.Create;
  Answer := Runner.Run(Ping, ['-n', '1', '127.0.0.1'], '', 5000);
  Assert.IsTrue(Answer.Outcome = TAtlasVcsOutcome.MainThread, 'Hauptthread abgelehnt');
  Runner := TAtlasVcsProcessRunner.Create(True, nil);
  Answer := Runner.Run(TPath.Combine(TPath.GetTempPath, 'gibt-es-nicht.exe'), [], '', 5000);
  Assert.IsTrue(Answer.Outcome = TAtlasVcsOutcome.ToolMissing);
  Started := TThread.GetTickCount64;
  Answer := Runner.Run(Ping, ['-n', '30', '127.0.0.1'], '', 300);
  Assert.IsTrue(Answer.Outcome = TAtlasVcsOutcome.TimedOut, 'Zeitlimit');
  Assert.IsTrue(TThread.GetTickCount64 - Started < 5000, 'Prozess beendet, nicht abgewartet');
  Answer := Runner.Run(Ping, ['-n', '1', '127.0.0.1'], '', 10000);
  Assert.IsTrue(Answer.Outcome = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(Length(Answer.Output) > 0, 'stdout gelesen');
  Assert.AreEqual('"a b"', TAtlasVcsProcessRunner.QuoteArgument('a b'));
  Assert.AreEqual('"x\"y"', TAtlasVcsProcessRunner.QuoteArgument('x"y'));
  Assert.AreEqual('"C:\a b\\"', TAtlasVcsProcessRunner.QuoteArgument('C:\a b\'));
  Assert.AreEqual('""', TAtlasVcsProcessRunner.QuoteArgument(''));
end;

procedure TAtlasVcsIntegrationTests.WorkerRunsInBackgroundAndDeliversInMainThread;
var
  Worker: TAtlasVcsWorker;
  Runner: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Outcome: TAtlasVcsOutcome;
  Head: TAtlasVcsHead;
  Done, InMain: Boolean;
  Deadline: UInt64;
  GitExe: string;
begin
  GitExe := TAtlasVcsTools.Find(TAtlasVcsKind.Git);
  if GitExe = '' then
    Assert.Pass('git nicht installiert; Prüfung übersprungen');
  // Der Läufer der IDE: lehnt den Hauptthread ab, im Worker läuft er.
  Runner := TAtlasVcsProcessRunner.Create;
  Vcs := TAtlasVersionControl.ForWorkingCopy(Default(TAtlasVcsWorkingCopy), Runner, GitExe, 5000);
  Assert.IsTrue(Vcs.Kind = TAtlasVcsKind.None, 'ohne Arbeitskopie die leere Umsetzung');
  // Arbeitskopie des Repositorys, in dem die Tests laufen; ohne: irgendein Ordner (dann NoWorkingCopy).
  Vcs := TAtlasVersionControl.Open(ExtractFilePath(ParamStr(0)), TAtlasVcsProvider.Auto, Runner);
  Done := False;
  InMain := False;
  Outcome := TAtlasVcsOutcome.Failed;
  Worker := TAtlasVcsWorker.Create;
  try
    Assert.IsTrue(Worker.Run(
      procedure
      begin
        Outcome := Vcs.Head(Head);
      end,
      procedure
      begin
        InMain := TThread.CurrentThread.ThreadID = MainThreadID;
        Done := True;
      end), 'gestartet');
    Deadline := TThread.GetTickCount64 + 20000;
    while not Done and (TThread.GetTickCount64 < Deadline) do
    begin
      CheckSynchronize(10);
    end;
    Assert.IsTrue(Done, 'Ergebnis zugestellt');
    Assert.IsTrue(InMain, 'im Hauptthread');
    Assert.IsTrue(Outcome <> TAtlasVcsOutcome.MainThread, 'im Hintergrund gelaufen');
    if Vcs.Kind = TAtlasVcsKind.Git then
    begin
      Assert.IsTrue(Outcome = TAtlasVcsOutcome.Ok);
      Assert.IsTrue(Head.Revision <> '', 'Commit des Repositorys');
    end;
    Assert.AreEqual(0, Worker.Pending);
    // Nach Stop kommt nichts mehr an.
    Done := False;
    Worker.Stop(1000);
    Assert.IsFalse(Worker.Run(
      procedure
      begin
      end,
      procedure
      begin
        Done := True;
      end), 'nach Stop nicht gestartet');
    CheckSynchronize(50);
    Assert.IsFalse(Done);
  finally
    Worker.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsIntegrationTests);

end.
