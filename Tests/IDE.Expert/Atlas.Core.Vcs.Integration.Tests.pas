unit Atlas.Core.Vcs.Integration.Tests;

// Versionsverwaltung mit echtem git und svn (#571): Die Tests legen eine
// Git- bzw. SVN-Arbeitskopie (mit svnadmin ein Repository unter file:///) in
// einem temporären Ordner an und prüfen Branch, Revision, geänderte Dateien,
// Inhalt in einer Revision, Zeilenherkunft und Wechselerkennung. Fehlt git
// bzw. svn (oder svnadmin), wird der Test übersprungen.
// Dazu der Prozessläufer selbst: Hauptthread abgelehnt, Zeitlimit, fehlendes
// Programm, Hintergrund über TAtlasVcsWorker.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasVcsIntegrationTests = class
  public
    [Test]
    procedure GitWorkingCopyReportsBranchRevisionAndChanges;
    [Test]
    procedure SvnWorkingCopyReportsBranchRevisionAndChanges;
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
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.Switches,
  Atlas.Core.Vcs.Worker,
  Atlas.Core.Vcs.Composition,
  Atlas.Core.Vcs.Adapters.ProcessRunner;

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
    TFile.SetAttributes(FileName, [TFileAttribute.faNormal]);
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
  SvnExe := TAtlasVcsTools.Find(TAtlasVcsKind.Svn);
  if SvnExe = '' then
    Assert.Pass('svn nicht installiert; Prüfung übersprungen');
  SvnAdmin := TPath.Combine(ExtractFilePath(SvnExe), 'svnadmin.exe');
  if not TFile.Exists(SvnAdmin) then
    Assert.Pass('svnadmin fehlt neben svn; Prüfung übersprungen');
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
