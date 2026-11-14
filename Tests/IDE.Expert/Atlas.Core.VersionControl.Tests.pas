unit Atlas.Core.VersionControl.Tests;

// Versionsverwaltung über eine gemeinsame Schnittstelle (#571), ohne git und
// svn: Parser mit aufgezeichneten Ausgaben (git 2.43, svn 1.14), Umsetzungen
// mit einem Prozessläufer-Ersatz, Erkennen der Arbeitskopie, Auswahl nach
// vcs.provider, einmalige Meldung bei fehlendem Programm und Wechsel-
// erkennung; eingehende Commits mit Autor und Dateien und die Aufrufe
// dafür (#755); Suche nach Commits mit einer Kennung, Branches samt
// entfernten, Abstand zur Basis und Dateiinhalt eines Commits (#1269). Die
// Tests mit echtem git bzw. svn stehen in Atlas.Core.VersionControl.Integration.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.VersionControl')]
  TAtlasVcsTests = class
  public
    [Test]
    procedure ProviderSettingRoundTrip;
    [Test]
    procedure RelativeAndFullPaths;
    [Test]
    procedure ParsesDatesAndXmlEntities;
    [Test]
    procedure XmlReaderReadsElementsAttributesAndText;
    [Test]
    procedure DetectionFindsNearestWorkingCopy;
    [Test]
    procedure DetectionHonoursProvider;
    [Test]
    procedure LocatesProgramInPathAndKnownDirs;
    [Test]
    procedure GitProviderRunsExpectedCommands;
    [Test]
    procedure SvnProviderRunsExpectedCommands;
    [Test]
    procedure ProvidersMapFailuresToOutcome;
    [Test]
    procedure WithoutWorkingCopyEverythingIsEmpty;
    [Test]
    procedure OpenSelectsByProviderAndReportsMissingToolOnce;
    [Test]
    procedure SwitchesCompareHeads;
    [Test]
    procedure WatchAsksOnlyWhenMarkerChanges;
    [Test]
    procedure GitChangeMarkerFollowsHeadAndBranch;
    [Test]
    procedure WorkerReportsWhetherItStarted;
    [Test]
    procedure GitProviderRunsLocalWorkCommands;
    [Test]
    procedure SvnAndNullLocalWork;
    [Test]
    procedure GitProviderRunsIncomingCommands;
    [Test]
    procedure ProvidersPullOnlyForward;
    [Test]
    procedure ProvidersCreateIssueBranches;
    /// <summary>#1290: SVN sucht und schaltet am Ort aus den Optionen ({projektwurzel} aus relative-url, fester Ort
    /// ohne Aufruf), ohne Layout Failed ohne Serveraufruf; switch mit langem Zeitlimit; svnversion neben svn nur
    /// unter SVN.</summary>
    [Test]
    procedure SvnBranchOptionsUseLocation;
    /// <summary>#1291: propget --xml -R, repos-root-url, --version und svnversion je Ordner ohne Server; RunStep
    /// schreibt die Eingabedatei (UTF-8 ohne BOM, LF) vor dem Aufruf.</summary>
    [Test]
    procedure SvnExternalsCommands;
    /// <summary>#1292: status --xml samt Externals, update mit und ohne Externals, log -q
    /// zählt nur Einträge nach der Revision und prüft Revision und Pfad vor dem Aufruf, propset aus Temp-Datei, die
    /// danach wieder weg ist; git submodule status --recursive.</summary>
    [Test]
    procedure WorkingCopyStateCommands;
    /// <summary>#1289: Git-Optionen über den Prozessläufer: fetch und push ohne Rückfrage, stash und checkout
    /// bzw. worktree add lokal, in dieser Reihenfolge; ohne Anmeldung endet es beim Abruf.</summary>
    [Test]
    procedure ProvidersRunGitBranchOptions;
    [Test]
    procedure SafeBranchNames;
    [Test]
    procedure ProvidersRunHistoryCommands;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Internals.Text,
  Atlas.Core.VersionControl.Internals.GitParser,
  Atlas.Core.VersionControl.Tools,
  Atlas.Core.VersionControl.Detection,
  Atlas.Core.VersionControl.Switches,
  Atlas.Core.VersionControl.Providers.Git,
  Atlas.Core.VersionControl.Providers.Svn,
  Atlas.Core.VersionControl.Providers.Null,
  Atlas.Core.VersionControl.Composition,
  Atlas.Core.VersionControl.BranchPlan,
  Atlas.Core.VersionControl.Worker,
  Atlas.Core.VersionControl.TestSupport;

type
  /// <summary>Antwortet je Unterbefehl (erstes Argument, das nicht mit "-" beginnt und nicht auf -c folgt).</summary>
  TFakeRunner = class(TInterfacedObject, IAtlasVcsRunner)
  public
    Calls: TArray<string>;
    WorkingDirs: TArray<string>;
    /// <summary>Programm und Zeitlimit je Aufruf (#1290).</summary>
    Executables: TArray<string>;
    Timeouts: TArray<Cardinal>;
    Commands: TArray<string>;
    Answers: TArray<string>;
    ExitCode: Integer;
    Outcome: TAtlasVcsOutcome;
    /// <summary>stderr jeder Antwort (#1287).</summary>
    ErrorText: string;
    procedure Answer(const ACommand, AText: string);
    function Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
      ATimeoutMs: Cardinal): TAtlasVcsRunResult;
  end;

  TFakeVcs = class(TInterfacedObject, IAtlasVersionControl)
  public
    Marker: string;
    Current: TAtlasVcsHead;
    HeadCalls: Integer;
    HeadOutcome: TAtlasVcsOutcome;
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
  end;

function Utf8Bytes(const AText: string): TBytes;
begin
  Result := TEncoding.UTF8.GetBytes(AText);
end;
{ TFakeRunner }

procedure TFakeRunner.Answer(const ACommand, AText: string);
begin
  Commands := Commands + [ACommand];
  Answers := Answers + [AText];
end;
function TFakeRunner.Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
  ATimeoutMs: Cardinal): TAtlasVcsRunResult;
var
  Index: Integer;
  Command: string;
  AfterC: Boolean;
begin
  Calls := Calls + [string.Join(' ', AArguments)];
  WorkingDirs := WorkingDirs + [AWorkingDir];
  Executables := Executables + [AExecutable];
  Timeouts := Timeouts + [ATimeoutMs];
  Command := '';
  AfterC := False;
  for Index := 0 to High(AArguments) do
  begin
    if AfterC then
    begin
      AfterC := False;
    end
    else if AArguments[Index] = '-c' then
    begin
      AfterC := True;
    end
    else if Copy(AArguments[Index], 1, 1) <> '-' then
    begin
      Command := AArguments[Index];
      Break;
    end;
  end;
  Result := TAtlasVcsRunResult.Make(Outcome, ExitCode, nil);
  Result.ErrorText := ErrorText;
  for Index := 0 to High(Commands) do
  begin
    if Commands[Index] = Command then
    begin
      Result.Output := Utf8Bytes(Answers[Index]);
    end;
  end;
end;
{ TFakeVcs }

function TFakeVcs.Kind: TAtlasVcsKind;
begin
  Result := TAtlasVcsKind.Git;
end;
function TFakeVcs.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result.Kind := TAtlasVcsKind.Git;
  Result.Root := Root;
end;
function TFakeVcs.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  Inc(HeadCalls);
  AHead := Current;
  Result := HeadOutcome;
end;
function TFakeVcs.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Ok;
end;
function TFakeVcs.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Ok;
end;
function TFakeVcs.Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Ok;
end;
function TFakeVcs.ChangeMarker: string;
begin
  Result := Marker;
end;
{ TAtlasVcsTests }

procedure TAtlasVcsTests.ProviderSettingRoundTrip;
var
  Provider: TAtlasVcsProvider;
begin
  for Provider := Low(TAtlasVcsProvider) to High(TAtlasVcsProvider) do
  begin
    Assert.AreEqual<TAtlasVcsProvider>(Provider,
      AtlasVcsProviderOf(AtlasVcsProviderText(Provider)), AtlasVcsProviderText(Provider));
  end;
  Assert.AreEqual<TAtlasVcsProvider>(TAtlasVcsProvider.Svn,
    AtlasVcsProviderOf(' SVN '), 'Groß- und Kleinschreibung egal');
  Assert.AreEqual<TAtlasVcsProvider>(TAtlasVcsProvider.Auto, AtlasVcsProviderOf(''), 'leer = auto');
  Assert.AreEqual<TAtlasVcsProvider>(TAtlasVcsProvider.Off, AtlasVcsProviderOf('"off"'), 'JSON-Text aus settings.json');
  Assert.AreEqual<TAtlasVcsProvider>(TAtlasVcsProvider.Auto, AtlasVcsProviderOf('cvs'), 'unbekannt = auto');
  Assert.AreEqual('Git', AtlasVcsKindName(TAtlasVcsKind.Git));
  Assert.AreEqual('SVN', AtlasVcsKindName(TAtlasVcsKind.Svn));
  Assert.AreEqual('', AtlasVcsKindName(TAtlasVcsKind.None));
  Assert.AreEqual('TimedOut', AtlasVcsOutcomeName(TAtlasVcsOutcome.TimedOut));
  Assert.AreEqual('MainThread', AtlasVcsOutcomeName(TAtlasVcsOutcome.MainThread));
  Assert.AreEqual('LoginNeeded', AtlasVcsOutcomeName(TAtlasVcsOutcome.LoginNeeded));
end;
procedure TAtlasVcsTests.RelativeAndFullPaths;
var
  Relative: string;
begin
  Assert.IsTrue(VcsRelativePath(Root, Under('src/Main.pas'), Relative));
  Assert.AreEqual('src/Main.pas', Relative);
  Assert.IsTrue(VcsRelativePath(Root + PathDelim, Under('A.pas'), Relative), 'Wurzel mit Trenner');
  Assert.AreEqual('A.pas', Relative);
  Assert.IsFalse(VcsRelativePath(Root, Root + 'X' + PathDelim + 'A.pas', Relative), 'Nachbarordner mit gleichem Anfang');
  Assert.IsFalse(VcsRelativePath(Root, Root, Relative), 'die Wurzel selbst ist keine Datei');
  // #1292: Ordner der Wurzel selbst ("." im Status, Ziel von svn:externals).
  Assert.IsTrue(VcsRelativeOrRoot(Root, Root + PathDelim, Relative));
  Assert.AreEqual('', Relative);
  Assert.IsTrue(VcsRelativeOrRoot(Root, Under('src/Main.pas'), Relative));
  Assert.AreEqual('src/Main.pas', Relative);
  Assert.IsFalse(VcsRelativeOrRoot(Root, Root + 'X', Relative));
  Assert.IsFalse(VcsRelativeOrRoot('', '', Relative));
  // Weiterleitung für den Host
  Assert.IsTrue(TAtlasVcsDetection.RelativePath(Root, Under('src/Main.pas'), Relative));
  Assert.AreEqual('src/Main.pas', Relative);
  Assert.IsFalse(TAtlasVcsDetection.RelativePath(Root, Root, Relative));
  if PathDelim = '\' then
  begin
    Assert.IsTrue(VcsRelativePath('c:\projekte\kunde', Under('A.pas'), Relative), 'Windows: ohne Groß/klein');
    Assert.AreEqual('C:\Projekte\Kunde', VcsNormalizeDir('C:/Projekte/Kunde/'));
    Assert.AreEqual('C:\', VcsNormalizeDir('C:\'), 'Laufwerkswurzel behält den Trenner');
  end;
  Assert.AreEqual(Under('src/Main.pas'), VcsFullPath(Root, 'src/Main.pas'));
  Assert.AreEqual(Under('src/Main.pas'), VcsFullPath(Root, 'src\Main.pas'));
  Assert.AreEqual(Under('A.pas'), VcsFullPath(Root, './A.pas'));
  Assert.AreEqual(Root, VcsFullPath(Root, '.'));
end;
procedure TAtlasVcsTests.ParsesDatesAndXmlEntities;
var
  Date: TDateTime;
begin
  Assert.IsTrue(VcsParseIsoDate('2026-10-01T08:30:15.250000Z', Date));
  Assert.AreEqual('2026-10-01 08:30:15.250', FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Date));
  Assert.IsTrue(VcsParseIsoDate('2026-10-01T08:30:15Z', Date), 'ohne Bruchteile');
  Assert.AreEqual('2026-10-01 08:30:15.000', FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Date));
  Assert.IsFalse(VcsParseIsoDate('01.10.2026', Date));
  Assert.IsFalse(VcsParseIsoDate('2026-13-01T08:30:15Z', Date), 'Monat 13');
  Assert.AreEqual('2026-10-15 12:22:39', FormatDateTime('yyyy-mm-dd hh:nn:ss', VcsUnixToDate(1792066959)));
  Assert.AreEqual('a & b <c> "d" ''e'' ' + #$00FC + ' ' + #$00E4, VcsXmlDecode(
    'a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&apos; &#252; &#xE4;'));
  Assert.AreEqual('ohne', VcsXmlDecode('ohne'));
  Assert.AreEqual('&unbekannt; & offen', VcsXmlDecode('&unbekannt; & offen'));
end;
procedure TAtlasVcsTests.XmlReaderReadsElementsAttributesAndText;
var
  Reader: TAtlasVcsXmlReader;
  Trace: string;
begin
  Reader := TAtlasVcsXmlReader.Create('<?xml version="1.0"?><!-- Kommentar --><a x="1" y=''z &amp; w''>' +
    'Text<b/><c k="v"></c></a>');
  try
    Trace := '';
    while Reader.Next do
      case Reader.Node of
        TAtlasVcsXmlNode.StartTag:
          begin
            Trace := Trace + '<' + Reader.Name;
            if Reader.Name = 'a' then
            begin
              Trace := Trace + ' x=' + Reader.Attr('x') + ' y=' + Reader.Attr('y') + ' q=' + Reader.Attr('q');
            end;
            if Reader.EmptyElement then
            begin
              Trace := Trace + '/';
            end;
            Trace := Trace + '>';
          end;
        TAtlasVcsXmlNode.EndTag:
          Trace := Trace + '</' + Reader.Name + '>';
        TAtlasVcsXmlNode.Text:
          Trace := Trace + '[' + Reader.Value + ']';
      end;
  finally
    Reader.Free;
  end;
  Assert.AreEqual('<a x=1 y=z & w q=>[Text]<b/><c></c></a>', Trace);
  Reader := TAtlasVcsXmlReader.Create('<a x=1>');
  try
    Assert.WillRaise(
      procedure
      begin
        Reader.Next;
      end, EAtlasVcsParse);
  finally
    Reader.Free;
  end;
end;
function FakeFileSystem(const ADirs, AFiles: TArray<string>; out ADirExists, AFileExists: TAtlasVcsPathExists): Boolean;
var
  Dirs, Files: TArray<string>;
begin
  Dirs := ADirs;
  Files := AFiles;
  ADirExists :=
    function(const APath: string): Boolean
    var
      Item: string;
    begin
      for Item in Dirs do
      begin
        if SameText(Item, APath) then
        begin
          Exit(True);
        end;
      end;
      Result := False;
    end;
  AFileExists :=
    function(const APath: string): Boolean
    var
      Item: string;
    begin
      for Item in Files do
      begin
        if SameText(Item, APath) then
        begin
          Exit(True);
        end;
      end;
      Result := False;
    end;
  Result := True;
end;
procedure TAtlasVcsTests.DetectionFindsNearestWorkingCopy;
var
  DirExists, FileExists_: TAtlasVcsPathExists;
  Found: TAtlasVcsWorkingCopy;
begin
  // Git-Repository mit einer SVN-Arbeitskopie darin (Fremdcode) und einem Submodul (.git als Datei).
  FakeFileSystem([Under('.git'), Under('lib/fremd/.svn')], [Under('ext/sub/.git')], DirExists, FileExists_);
  Found := TAtlasVcsDetection.Find(Under('src/app'), TAtlasVcsProvider.Auto, DirExists, FileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git, Found.Kind);
  Assert.AreEqual(Root, Found.Root);
  Found := TAtlasVcsDetection.Find(Under('lib/fremd/src'), TAtlasVcsProvider.Auto, DirExists, FileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Svn, Found.Kind, 'die nächstliegende gilt');
  Assert.AreEqual(Under('lib/fremd'), Found.Root);
  Found := TAtlasVcsDetection.Find(Under('ext/sub/src'), TAtlasVcsProvider.Auto, DirExists, FileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git, Found.Kind, '.git als Datei (Submodul, Worktree)');
  Assert.AreEqual(Under('ext/sub'), Found.Root);
  Found := TAtlasVcsDetection.Find(Root + PathDelim, TAtlasVcsProvider.Auto, DirExists, FileExists_);
  Assert.AreEqual(Root, Found.Root, 'Ordner mit Trenner am Ende');
  // Beide im selben Ordner: Git gewinnt.
  FakeFileSystem([Under('.git'), Under('.svn')], [], DirExists, FileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git,
    TAtlasVcsDetection.Find(Root, TAtlasVcsProvider.Auto, DirExists, FileExists_).Kind);
  FakeFileSystem([], [], DirExists, FileExists_);
  Found := TAtlasVcsDetection.Find(Under('src'), TAtlasVcsProvider.Auto, DirExists, FileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, Found.Kind, 'ohne Arbeitskopie');
  Assert.AreEqual('', Found.Root);
end;
procedure TAtlasVcsTests.DetectionHonoursProvider;
var
  DirExists, FileExists_: TAtlasVcsPathExists;
  Found: TAtlasVcsWorkingCopy;
begin
  FakeFileSystem([Under('.git'), Under('lib/fremd/.svn')], [], DirExists, FileExists_);
  Found := TAtlasVcsDetection.Find(Under('lib/fremd/src'), TAtlasVcsProvider.Git, DirExists, FileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git, Found.Kind, 'git: SVN wird übergangen');
  Assert.AreEqual(Root, Found.Root);
  Found := TAtlasVcsDetection.Find(Under('src'), TAtlasVcsProvider.Svn, DirExists, FileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, Found.Kind, 'svn: Git zählt nicht');
  Found := TAtlasVcsDetection.Find(Under('lib/fremd'), TAtlasVcsProvider.Off, DirExists, FileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, Found.Kind, 'off sucht nicht');
end;
procedure TAtlasVcsTests.LocatesProgramInPathAndKnownDirs;
var
  Exe, PathText: string;
  Dirs: TArray<string>;
begin
  Exe := 'svn';
  if PathDelim = '\' then
  begin
    Exe := 'svn.exe';
  end;
  PathText := Under('leer') + PathSep + '"' + Under('tools') + '"' + PathSep + PathSep;
  Assert.AreEqual(Under('tools/' + Exe), TAtlasVcsTools.Locate('svn', PathText, nil,
    function(const APath: string): Boolean
    begin
      Result := APath = Under('tools/' + Exe);
    end), 'PATH mit Anführungszeichen und leeren Einträgen');
  Dirs := TAtlasVcsTools.KnownDirs(TAtlasVcsKind.Svn, [Root, '']);
  Assert.AreEqual(Under('TortoiseSVN/bin'), Dirs[0], 'TortoiseSVN mit Kommandozeilenwerkzeugen');
  Assert.AreEqual(Under('TortoiseSVN/bin/' + Exe), TAtlasVcsTools.Locate('svn', '', Dirs,
    function(const APath: string): Boolean
    begin
      Result := APath = Under('TortoiseSVN/bin/' + Exe);
    end));
  Assert.AreEqual(Under('Git/cmd'), TAtlasVcsTools.KnownDirs(TAtlasVcsKind.Git, [Root])[0]);
  Assert.AreEqual('', TAtlasVcsTools.Locate('svn', PathText, Dirs,
    function(const APath: string): Boolean
    begin
      Result := False;
    end), 'nicht installiert');
  Assert.AreEqual(0, Integer(Length(TAtlasVcsTools.KnownDirs(TAtlasVcsKind.None, [Root]))));
  TAtlasVcsTools.Preset(TAtlasVcsKind.Svn, '');
  try
    Assert.AreEqual('', TAtlasVcsTools.Find(TAtlasVcsKind.Svn), 'Preset gilt für Find');
  finally
    TAtlasVcsTools.Forget;
  end;
end;
procedure TAtlasVcsTests.GitProviderRunsExpectedCommands;
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Head: TAtlasVcsHead;
  Changes: TArray<TAtlasVcsChange>;
  Content: TBytes;
  Lines: TArray<TAtlasVcsBlameLine>;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Runner.Answer('status', GitStatusSample);
  Runner.Answer('show', 'unit A;');
  Runner.Answer('blame', Hash1 + ' 1 1 1'#10'author Ada'#10'summary S'#10#9'x'#10);
  Vcs := TAtlasGitVersionControl.Create(Root + PathDelim, RunnerRef, 'git.exe', 5000);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git, Vcs.Kind);
  Assert.AreEqual(Root, Vcs.WorkingCopy.Root, 'ohne Trenner am Ende');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Vcs.Head(Head));
  Assert.AreEqual('main', Head.Branch);
  Assert.AreEqual('--no-optional-locks -c core.quotepath=off -c color.ui=false status --porcelain=v2 --branch -z ' +
    '--untracked-files=no', Runner.Calls[0]);
  Assert.AreEqual(Root, Runner.WorkingDirs[0], 'git läuft in der Wurzel');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Vcs.Changes(Changes));
  Assert.AreEqual(5, Integer(Length(Changes)));
  Assert.Contains(Runner.Calls[1], '--untracked-files=all');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Vcs.FileAt(Under('src/Main.pas'), '', Content));
  Assert.AreEqual('unit A;', TEncoding.UTF8.GetString(Content));
  Assert.IsTrue(Pos('show HEAD:src/Main.pas', Runner.Calls[2]) > 0, 'Revision leer = HEAD, Pfad mit /');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Vcs.FileAt(Under('A.pas'), Hash2, Content));
  Assert.Contains(Runner.Calls[3], 'show ' + Hash2 + ':A.pas');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Vcs.Blame(Under('src/Main.pas'), Lines));
  Assert.Contains(Runner.Calls[4], 'blame --porcelain -- src/Main.pas');
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.AreEqual('S', Lines[0].Summary);
  // Datei außerhalb der Arbeitskopie, Revision als Option: kein Aufruf.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Vcs.FileAt(Root + 'X' + PathDelim + 'A.pas', '', Content));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Vcs.FileAt(Under('A.pas'), '--output=x', Content));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Vcs.Blame(Root + 'X' + PathDelim + 'A.pas', Lines));
  Assert.AreEqual(5, Integer(Length(Runner.Calls)));
end;
procedure TAtlasVcsTests.SvnProviderRunsExpectedCommands;
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Head: TAtlasVcsHead;
  Changes: TArray<TAtlasVcsChange>;
  Content: TBytes;
  Lines: TArray<TAtlasVcsBlameLine>;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Runner.Answer('info', SvnInfoSample);
  Runner.Answer('status', SvnStatusSample);
  Runner.Answer('cat', 'unit Main;');
  Runner.Answer('blame', SvnBlameSample);
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, 'svn.exe');
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Svn, Vcs.Kind);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Vcs.Head(Head));
  Assert.AreEqual('branches/release-2', Head.Branch);
  Assert.AreEqual('42', Head.Revision);
  Assert.AreEqual('r42', Head.ShortRevision(TAtlasVcsKind.Svn));
  Assert.AreEqual(-1, Head.Ahead);
  Assert.AreEqual('info --xml . --non-interactive', Runner.Calls[0]);
  Assert.AreEqual(Root, Runner.WorkingDirs[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Vcs.Changes(Changes));
  Assert.AreEqual(6, Integer(Length(Changes)));
  Assert.AreEqual('status --xml . --non-interactive', Runner.Calls[1]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Vcs.FileAt(Under('src/Main.pas'), '', Content));
  Assert.AreEqual('cat -r BASE src/Main.pas@ --non-interactive', Runner.Calls[2], 'Revision leer = BASE');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Vcs.FileAt(Under('src/Main.pas'), '40', Content));
  Assert.AreEqual('cat -r 40 src/Main.pas@ --non-interactive', Runner.Calls[3]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Vcs.Blame(Under('src/Main.pas'), Lines));
  Assert.AreEqual('blame --xml src/Main.pas@ --non-interactive', Runner.Calls[4]);
  Assert.AreEqual(3, Integer(Length(Lines)));
end;
procedure TAtlasVcsTests.ProvidersMapFailuresToOutcome;
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Head: TAtlasVcsHead;
  Changes: TArray<TAtlasVcsChange>;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Runner.ExitCode := 128;
  Vcs := TAtlasGitVersionControl.Create(Root, RunnerRef, 'git.exe');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Vcs.Head(Head), 'Exit-Code ungleich 0');
  Assert.AreEqual('', Head.Branch);
  Runner.ExitCode := 0;
  Runner.Outcome := TAtlasVcsOutcome.TimedOut;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.TimedOut, Vcs.Changes(Changes), 'Zeitlimit kommt durch');
  Runner.Outcome := TAtlasVcsOutcome.MainThread;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.MainThread, Vcs.Head(Head), 'Hauptthread abgelehnt');
  Runner.Outcome := TAtlasVcsOutcome.Ok;
  Runner.Answer('status', 'Z kaputt'#0);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Vcs.Changes(Changes), 'unlesbare Ausgabe');
  Assert.AreEqual(0, Integer(Length(Changes)));
  Runner.Answer('info', '<info>');
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, 'svn.exe');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Vcs.Head(Head), 'svn info ohne Eintrag');
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, '');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.ToolMissing, Vcs.Head(Head), 'ohne Programm kein Aufruf');
end;
procedure TAtlasVcsTests.WithoutWorkingCopyEverythingIsEmpty;
var
  Vcs: IAtlasVersionControl;
  Head: TAtlasVcsHead;
  Changes: TArray<TAtlasVcsChange>;
  Content: TBytes;
  Lines: TArray<TAtlasVcsBlameLine>;
begin
  Vcs := TAtlasNullVersionControl.Create;
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, Vcs.Kind);
  Assert.AreEqual('', Vcs.WorkingCopy.Root);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.NoWorkingCopy, Vcs.Head(Head));
  Assert.AreEqual('', Head.Branch);
  Assert.AreEqual('', Head.ShortRevision(TAtlasVcsKind.None));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.NoWorkingCopy, Vcs.Changes(Changes));
  Assert.AreEqual(0, Integer(Length(Changes)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.NoWorkingCopy, Vcs.FileAt(Under('A.pas'), '', Content));
  Assert.AreEqual(0, Integer(Length(Content)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.NoWorkingCopy, Vcs.Blame(Under('A.pas'), Lines));
  Assert.AreEqual('', Vcs.ChangeMarker);
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Vcs.Head(Head));
end;
function TempFolder(const AName: string): string;
var
  Temp: string;
begin
  Temp := GetEnvironmentVariable('TEMP');
  if Temp = '' then
  begin
    Temp := GetEnvironmentVariable('TMPDIR');
  end;
  if Temp = '' then
  begin
    Temp := '/tmp';
  end;
  Result := IncludeTrailingPathDelimiter(Temp) + 'AtlasVcsTests-' + AName + '-' + FormatDateTime('hhnnsszzz', Now) +
    IntToStr(Random(1000));
  ForceDirectories(Result);
end;
procedure WriteText(const AFileName, AText: string);
var
  Stream: TFileStream;
  Bytes: TBytes;
begin
  Bytes := TEncoding.UTF8.GetBytes(AText);
  Stream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(Bytes) > 0 then
    begin
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
    end;
  finally
    Stream.Free;
  end;
end;
/// <summary>Werkzeugsuche: svn fehlt, git ist da.</summary>
function GitOnlyLocate: TAtlasVcsLocate;
begin
  Result :=
    function(AKind: TAtlasVcsKind): string
    begin
      // svn fehlt, git ist da.
      if AKind = TAtlasVcsKind.Git then
      begin
        Result := 'git.exe';
      end
      else
      begin
        Result := '';
      end;
    end;
end;
procedure TAtlasVcsTests.OpenSelectsByProviderAndReportsMissingToolOnce;
var
  Folder: string;
  Vcs: IAtlasVersionControl;
  Reported: TArray<TAtlasVcsKind>;
  RunnerRef: IAtlasVcsRunner;
  Head: TAtlasVcsHead;
  Locate: TAtlasVcsLocate;
begin
  RunnerRef := TFakeRunner.Create;
  Folder := TempFolder('open');
  ForceDirectories(Folder + PathDelim + '.svn');
  ForceDirectories(Folder + PathDelim + 'src');
  Locate := GitOnlyLocate();
  Reported := nil;
  TAtlasVcsNotices.Reset;
  TAtlasVcsNotices.OnToolMissing :=
    procedure(AKind: TAtlasVcsKind)
    begin
      Reported := Reported + [AKind];
    end;
  try
    Vcs := TAtlasVersionControl.Open(Folder + PathDelim + 'src', TAtlasVcsProvider.Auto, RunnerRef, Locate, 1000);
    Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, Vcs.Kind, 'ohne svn weiter ohne Versionsverwaltung');
    Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.ToolMissing, Vcs.Head(Head));
    Vcs := TAtlasVersionControl.Open(Folder, TAtlasVcsProvider.Auto, RunnerRef, Locate, 1000);
    Assert.AreEqual(1, Integer(Length(Reported)), 'nur einmal gemeldet');
    Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Svn, Reported[0]);
    Vcs := TAtlasVersionControl.Open(Folder, TAtlasVcsProvider.Off, RunnerRef, Locate, 1000);
    Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Vcs.Head(Head), 'off');
    Vcs := TAtlasVersionControl.Open(Folder, TAtlasVcsProvider.Git, RunnerRef, Locate, 1000);
    Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.NoWorkingCopy, Vcs.Head(Head), 'git gewählt, aber nur SVN da');
    ForceDirectories(Folder + PathDelim + '.git');
    Vcs := TAtlasVersionControl.Open(Folder + PathDelim + 'src', TAtlasVcsProvider.Auto, RunnerRef, Locate, 1000);
    Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git, Vcs.Kind);
    Assert.AreEqual(VcsNormalizeDir(Folder), Vcs.WorkingCopy.Root);
    Vcs := TAtlasVersionControl.Open(Folder, TAtlasVcsProvider.Svn, RunnerRef, Locate, 1000);
    Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, Vcs.Kind, 'svn gewählt, svn fehlt');
    Assert.AreEqual(1, Integer(Length(Reported)), 'auch dann nicht noch einmal');
    TAtlasVcsNotices.Reset;
    Vcs := TAtlasVersionControl.Open(Folder, TAtlasVcsProvider.Svn, RunnerRef, Locate, 1000);
    Assert.AreEqual(2, Integer(Length(Reported)), 'nach Reset wieder');
  finally
    TAtlasVcsNotices.OnToolMissing := nil;
    TAtlasVcsNotices.Reset;
    RemoveDir(Folder + PathDelim + '.git');
    RemoveDir(Folder + PathDelim + '.svn');
    RemoveDir(Folder + PathDelim + 'src');
    RemoveDir(Folder);
  end;
end;
function MakeHead(const ABranch, ARevision: string; ADetached: Boolean): TAtlasVcsHead;
begin
  Result := TAtlasVcsHead.Empty;
  Result.Branch := ABranch;
  Result.Revision := ARevision;
  Result.Detached := ADetached;
end;
procedure TAtlasVcsTests.SwitchesCompareHeads;
begin
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None,
    TAtlasVcsSwitches.Compare(TAtlasVcsHead.Empty, MakeHead('main', Hash1, False)), 'ohne alten Stand');
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None,
    TAtlasVcsSwitches.Compare(MakeHead('main', Hash1, False), MakeHead('main', Hash1, False)));
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Branch,
    TAtlasVcsSwitches.Compare(MakeHead('main', Hash1, False), MakeHead('feature/x', Hash1, False)), 'git checkout ohne neuen Commit');
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Revision,
    TAtlasVcsSwitches.Compare(MakeHead('main', Hash1, False), MakeHead('main', Hash2, False)), 'Commit oder Pull');
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Branch,
    TAtlasVcsSwitches.Compare(MakeHead('main', Hash1, False), MakeHead('', Hash1, True)), 'losgelöster HEAD');
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Revision,
    TAtlasVcsSwitches.Compare(MakeHead('trunk', '41', False), MakeHead('trunk', '42', False)), 'svn update');
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Branch,
    TAtlasVcsSwitches.Compare(MakeHead('trunk', '42', False), MakeHead('branches/x', '42', False)), 'svn switch');
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Revision,
    TAtlasVcsSwitches.Compare(MakeHead('main', '', False), MakeHead('main', Hash1, False)), 'erster Commit');
end;
procedure TAtlasVcsTests.WatchAsksOnlyWhenMarkerChanges;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  Watch: TAtlasVcsWatch;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.Marker := 'm1';
  Fake.Current := MakeHead('main', Hash1, False);
  Watch := TAtlasVcsWatch.Create(Vcs);
  try
    Assert.IsFalse(Watch.Known);
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None, Watch.Check, 'erster Stand');
    Assert.IsTrue(Watch.Known);
    Assert.AreEqual('main', Watch.Head.Branch);
    Assert.AreEqual(1, Fake.HeadCalls);
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None, Watch.Check);
    Assert.AreEqual(1, Fake.HeadCalls, 'Marke unverändert: kein Prozess');
    Fake.Marker := 'm2';
    Fake.Current := MakeHead('feature/x', Hash1, False);
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Branch, Watch.Check);
    Assert.AreEqual(2, Fake.HeadCalls);
    Fake.Marker := 'm3';
    Fake.Current := MakeHead('feature/x', Hash2, False);
    Fake.HeadOutcome := TAtlasVcsOutcome.TimedOut;
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None, Watch.Check, 'keine Antwort: alter Stand bleibt');
    Assert.AreEqual('feature/x', Watch.Head.Branch);
    Fake.HeadOutcome := TAtlasVcsOutcome.Ok;
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Revision, Watch.Check, 'beim nächsten Mal erkannt');
    Fake.Marker := '';
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None, Watch.Check);
    Assert.AreEqual(5, Fake.HeadCalls, 'ohne Marke wird jedes Mal gefragt');
  finally
    Watch.Free;
  end;
end;
procedure TAtlasVcsTests.GitChangeMarkerFollowsHeadAndBranch;
var
  Folder, Before: string;
  Vcs: IAtlasVersionControl;
  RunnerRef: IAtlasVcsRunner;
begin
  RunnerRef := TFakeRunner.Create;
  Folder := TempFolder('marker');
  ForceDirectories(Folder + PathDelim + '.git' + PathDelim + 'refs' + PathDelim + 'heads');
  WriteText(Folder + PathDelim + '.git' + PathDelim + 'HEAD', 'ref: refs/heads/main'#10);
  WriteText(Folder + PathDelim + '.git' + PathDelim + 'refs' + PathDelim + 'heads' + PathDelim + 'main', Hash1 + #10);
  try
    Vcs := TAtlasGitVersionControl.Create(Folder, RunnerRef, 'git.exe');
    Before := Vcs.ChangeMarker;
    Assert.Contains(Before, 'ref: refs/heads/main');
    Assert.IsTrue(Pos(Hash1, Before) > 0, 'Commit des Branchs');
    Assert.AreEqual(Before, Vcs.ChangeMarker, 'stabil ohne Änderung');
    WriteText(Folder + PathDelim + '.git' + PathDelim + 'refs' + PathDelim + 'heads' + PathDelim + 'main',
      Hash2 + #10);
    Assert.AreNotEqual(Before, Vcs.ChangeMarker, 'neuer Commit');
    // Worktree bzw. Submodul: .git ist eine Datei mit gitdir.
    Assert.AreEqual(Folder + PathDelim + '.git', TAtlasGitVersionControl.GitDir(Folder));
    Assert.AreEqual('', TAtlasGitVersionControl.GitDir(Folder + PathDelim + 'fehlt'));
  finally
    DeleteFile(Folder + PathDelim + '.git' + PathDelim + 'refs' + PathDelim + 'heads' + PathDelim + 'main');
    DeleteFile(Folder + PathDelim + '.git' + PathDelim + 'HEAD');
    RemoveDir(Folder + PathDelim + '.git' + PathDelim + 'refs' + PathDelim + 'heads');
    RemoveDir(Folder + PathDelim + '.git' + PathDelim + 'refs');
    RemoveDir(Folder + PathDelim + '.git');
    RemoveDir(Folder);
  end;
end;
procedure TAtlasVcsTests.WorkerReportsWhetherItStarted;
var
  Worker: TAtlasVcsWorker;
  Done: Boolean;
  Deadline: UInt64;
begin
  // #592: Ohne Start kommt kein Ergebnis; der Aufrufer muss das wissen, sonst bleibt „wird abgefragt …“.
  Done := False;
  Worker := TAtlasVcsWorker.Create;
  try
    Assert.IsTrue(Worker.Run(
      procedure
      begin
      end,
      procedure
      begin
        Done := True;
      end));
    Deadline := TThread.GetTickCount64 + 5000;
    while not Done and (TThread.GetTickCount64 < Deadline) do
    begin
      CheckSynchronize(10);
    end;
    Assert.IsTrue(Done);
    Worker.Stop(1000);
    Assert.IsFalse(Worker.Run(
      procedure
      begin
      end,
      procedure
      begin
      end));
  finally
    Worker.Free;
  end;
end;
procedure TAtlasVcsTests.GitProviderRunsLocalWorkCommands;
const
  Prefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Local: IAtlasVcsLocalWork;
  Branches: TArray<TAtlasVcsBranch>;
  Stashes: TArray<TAtlasVcsStash>;
  Commits: TArray<TAtlasVcsCommit>;
  Changes: TArray<TAtlasVcsChange>;
  Names: TArray<string>;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Runner.Answer('for-each-ref', 'main'#0'origin/main'#0'origin'#0'refs/heads/main'#0'ahead 1'#0'1792071092'#0'*'#10);
  Runner.Answer('stash', Hash1 + #0'1792071092'#0'stash@{0}'#0'On main: X'#10);
  Runner.Answer('remote', 'origin'#10);
  Runner.Answer('log', Hash2 + #0'1792071091'#0'eins'#10);
  Runner.Answer('diff', 'M'#0'A.pas'#0);
  Vcs := TAtlasGitVersionControl.Create(Root, RunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsLocalWork, Local), 'Git bietet IAtlasVcsLocalWork');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Local.Branches(Branches));
  Assert.AreEqual(1, Integer(Length(Branches)));
  Assert.AreEqual(Prefix + 'for-each-ref --format=' + TAtlasGitParser.cBranchFormat + ' refs/heads', Runner.Calls[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Local.Stashes(Stashes));
  Assert.AreEqual(Prefix + 'stash list --format=' + TAtlasGitParser.cStashFormat, Runner.Calls[1]);
  Assert.AreEqual('X', Stashes[0].Message);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Local.Remotes(Names));
  Assert.AreEqual('origin', Names[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Local.Outgoing('main', 'origin/main', 51, Commits));
  Assert.AreEqual(Prefix + 'log --format=' + TAtlasGitParser.cLogFormat + ' --max-count=51 refs/heads/main --not ' +
    'origin/main', Runner.Calls[3], 'kein fetch: nur das lokale Repository');
  Assert.AreEqual('eins', Commits[0].Summary);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Local.Outgoing('lokal', '', 0, Commits));
  Assert.AreEqual(Prefix + 'log --format=' + TAtlasGitParser.cLogFormat + ' --max-count=1 refs/heads/lokal --not ' +
    '--remotes', Runner.Calls[4], 'ohne Upstream: auf keinem Remote');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Local.ChangesIn(Hash1, Changes));
  Assert.AreEqual(Prefix + 'diff --name-status -z --no-renames ' + Hash1 + '^1 ' + Hash1, Runner.Calls[5]);
  Assert.AreEqual(Under('A.pas'), Changes[0].Path);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Local.Push('main', 'origin', 'refs/heads/main', False));
  Assert.AreEqual(Prefix + '-c credential.interactive=never -c core.askPass= push --porcelain origin ' +
    'refs/heads/main:refs/heads/main', Runner.Calls[6], 'ohne Rückfrage nach Zugangsdaten (#1287)');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Local.Push('neu', 'origin', 'refs/heads/neu', True));
  Assert.AreEqual(Prefix + '-c credential.interactive=never -c core.askPass= push --porcelain --set-upstream ' +
    'origin refs/heads/neu:refs/heads/neu', Runner.Calls[7]);
  // Namen, die als Option gelesen würden, starten keinen Prozess.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Local.Outgoing('-x', '', 5, Commits));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Local.Outgoing('main', '--all', 5, Commits));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Local.ChangesIn('--output=x', Changes));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Local.Push('main', '-f', 'refs/heads/main', False));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Local.Push('a b', 'origin', 'refs/heads/main', False));
  Assert.AreEqual(8, Integer(Length(Runner.Calls)));
  // Exit-Code ungleich 0 (z. B. Push abgelehnt) = Failed.
  Runner.ExitCode := 1;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Local.Push('main', 'origin', 'refs/heads/main', False));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Local.Branches(Branches));
  Assert.AreEqual(0, Integer(Length(Branches)));
end;
procedure TAtlasVcsTests.SvnAndNullLocalWork;
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Local: IAtlasVcsLocalWork;
  Branches: TArray<TAtlasVcsBranch>;
  Stashes: TArray<TAtlasVcsStash>;
  Commits: TArray<TAtlasVcsCommit>;
  Changes: TArray<TAtlasVcsChange>;
  Names: TArray<string>;
begin
  // SVN: keine lokalen Commits, Stashes oder Branches; kein Prozess.
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(Vcs, IAtlasVcsLocalWork, Local));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Local.Branches(Branches));
  Assert.AreEqual(0, Integer(Length(Branches)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Local.Stashes(Stashes));
  Assert.AreEqual(0, Integer(Length(Stashes)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Local.Remotes(Names));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Local.Outgoing('trunk', '', 10, Commits));
  Assert.AreEqual(0, Integer(Length(Commits)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Local.ChangesIn('42', Changes));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Local.Push('trunk', 'x', 'y', False));
  Assert.AreEqual(0, Integer(Length(Runner.Calls)), 'kein Prozess');
  // Leere Umsetzung: Outcome sagt, warum.
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsLocalWork, Local));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Local.Branches(Branches));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Local.Stashes(Stashes));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Local.Remotes(Names));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Local.Outgoing('main', '', 1, Commits));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Local.ChangesIn('x', Changes));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Local.Push('main', 'origin', 'refs/heads/main', False));
end;
procedure TAtlasVcsTests.GitProviderRunsIncomingCommands;
const
  Prefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Incoming: IAtlasVcsIncoming;
  Commits: TArray<TAtlasVcsIncomingCommit>;
  Revision: string;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Runner.Answer('rev-parse', Hash2 + #10);
  Runner.Answer('log', #$1E + Hash1 + #0'1792071092'#0'Eva'#0'eins'#0#10'A.pas'#0);
  Runner.Answer('fetch', '');
  Vcs := TAtlasGitVersionControl.Create(Root, RunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsIncoming, Incoming), 'Git bietet IAtlasVcsIncoming');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Incoming.Resolve('origin/main', Revision));
  Assert.AreEqual(Hash2, Revision);
  Assert.AreEqual(Prefix + 'rev-parse --verify --quiet origin/main^{commit}', Runner.Calls[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    Incoming.Incoming('origin/main', [Hash1, '', Hash2], 200, Commits));
  Assert.AreEqual(Prefix + 'log --format=' + TAtlasGitParser.cIncomingFormat + ' --name-only -z --no-renames ' +
    '--max-count=200 origin/main --not ' + Hash1 + ' ' + Hash2, Runner.Calls[1], 'nur lokale Remote-Branches');
  Assert.AreEqual(1, Integer(Length(Commits)));
  Assert.AreEqual(Under('A.pas'), Commits[0].Files[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Incoming.Fetch(''));
  Assert.AreEqual(Prefix + '-c credential.interactive=never -c core.askPass= fetch --quiet --no-tags',
    Runner.Calls[2], 'ohne Rückfrage nach Zugangsdaten');
  // Namen, die als Option gelesen würden, starten keinen Prozess.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Incoming.Resolve('--all', Revision));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Incoming.Incoming('--all', nil, 5, Commits));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Incoming.Incoming('origin/main', ['-p'], 5, Commits));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Incoming.Fetch('--upload-pack=x'));
  Assert.AreEqual(3, Integer(Length(Runner.Calls)));
  // SVN: kein lokaler Stand des Servers, kein Prozess; leere Umsetzung meldet ihren Grund.
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(Vcs, IAtlasVcsIncoming, Incoming));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Incoming.Incoming('trunk', nil, 5, Commits));
  Assert.AreEqual(0, Integer(Length(Commits)));
  Assert.AreEqual(3, Integer(Length(Runner.Calls)), 'SVN startet keinen Prozess');
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsIncoming, Incoming));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Incoming.Fetch(''));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Incoming.Incoming('origin/main', nil, 5, Commits));
end;
procedure TAtlasVcsTests.ProvidersPullOnlyForward;
const
  Prefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Update: IAtlasVcsUpdate;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Vcs := TAtlasGitVersionControl.Create(Root, RunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsUpdate, Update), 'Git bietet IAtlasVcsUpdate');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Update.Pull);
  Assert.AreEqual(Prefix + '-c credential.interactive=never -c core.askPass= pull --ff-only --no-rebase --quiet',
    Runner.Calls[0], 'nur vorwärts, ohne Rückfrage nach Zugangsdaten');
  Assert.AreEqual(Root, Runner.WorkingDirs[0], 'in der Wurzel der Arbeitskopie');
  // Abweichender Branch: git endet mit Fehler, nichts wird zusammengeführt.
  Runner.ExitCode := 128;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Update.Pull);
  // Fehlende Anmeldung (#1287): eigenes Ergebnis statt still „Failed“.
  Runner.ErrorText := 'fatal: Authentication failed for ''https://example.com/kasse.git/''';
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.LoginNeeded, Update.Pull);
  Runner.ErrorText := '';
  Runner.ExitCode := 0;
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(Vcs, IAtlasVcsUpdate, Update), 'SVN bietet IAtlasVcsUpdate');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Update.Pull);
  Assert.AreEqual('update . --non-interactive', Runner.Calls[3]);
  Runner.ExitCode := 1;
  Runner.ErrorText := 'svn: E170001: Authorization failed';
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.LoginNeeded, Update.Pull);
  Runner.ErrorText := '';
  Runner.ExitCode := 0;
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.ToolMissing);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsUpdate, Update));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.ToolMissing, Update.Pull);
  Assert.AreEqual(5, Integer(Length(Runner.Calls)), 'die leere Umsetzung startet keinen Prozess');
end;
/// <summary>Git: Branch prüfen, anlegen, wechseln, Hook-Ordner; unsichere Namen ohne Prozess.</summary>
procedure AssertGitBranching(ARunner: TFakeRunner; const ARunnerRef: IAtlasVcsRunner);
const
  Prefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
  RemotePrefix = Prefix + '-c credential.interactive=never -c core.askPass= ';
var
  Vcs: IAtlasVersionControl;
  Branching: IAtlasVcsBranching;
  Exists, mHas: Boolean;
  Hooks, GitDir, mRevision: string;
  mSteps: TArray<TAtlasVcsBranchStep>;
begin
  ARunner.Answer('for-each-ref',
    'refs/heads/feature/753-atlas-bereiche-und' + #10 + 'refs/remotes/origin/develop' + #10);
  ARunner.Answer('rev-parse', '.git/hooks' + #10 + '.git' + #10);
  Vcs := TAtlasGitVersionControl.Create(Root, ARunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsBranching, Branching), 'Git bietet IAtlasVcsBranching');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    Branching.BranchExists('feature/753-atlas-bereiche-und', Exists));
  Assert.IsTrue(Exists, 'vorhandener Branch');
  Assert.AreEqual(Prefix + 'for-each-ref --format=%(refname) refs/heads/feature/753-atlas-bereiche-und',
    ARunner.Calls[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.BranchExists('feature/1-neu', Exists));
  Assert.IsFalse(Exists, 'ein ähnlicher Ref zählt nicht');
  // Remote-Branch im lokalen Stand (#1288), ohne fetch.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.RemoteBranchExists('develop', Exists));
  Assert.IsTrue(Exists);
  Assert.AreEqual(Prefix + 'for-each-ref --format=%(refname) refs/remotes/origin/develop', ARunner.Calls[2]);
  // Schritte aus dem Plan: lokal mit den festen Optionen, mit Remote zusätzlich ohne Rückfrage.
  mSteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/9-neu',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.RemoteMain, 'develop', ''), 'egal'));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.RunStep(mSteps[0]));
  Assert.AreEqual(Prefix + 'checkout --quiet --no-track -b feature/9-neu refs/remotes/origin/develop --',
    ARunner.Calls[3]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    Branching.RunStep(TAtlasVcsBranchStep.Make(TArray<string>.Create('push', '-u', 'origin',
    'feature/9-neu'), True, True)));
  Assert.AreEqual(RemotePrefix + 'push -u origin feature/9-neu', ARunner.Calls[4]);
  // Git: keine Serverrevision, keine Externals, ohne Prozess.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.ServerRevision('main', mRevision));
  Assert.AreEqual('', mRevision);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.HasExternals(mHas));
  Assert.IsFalse(mHas);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.RepositoryPath(mRevision));
  Assert.AreEqual('', mRevision);
  Assert.AreEqual(5, Integer(Length(ARunner.Calls)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.SwitchBranch('feature/753-atlas-bereiche-und'));
  Assert.AreEqual(Prefix + 'checkout --quiet feature/753-atlas-bereiche-und --', ARunner.Calls[5]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.HookFolders(Hooks, GitDir));
  Assert.AreEqual(Prefix + 'rev-parse --git-path hooks --git-dir', ARunner.Calls[6]);
  Assert.AreEqual(Under('.git/hooks'), Hooks, 'relativ zur Wurzel aufgelöst');
  Assert.AreEqual(Under('.git'), GitDir);
  // Unsichere Namen und leere Schritte starten keinen Prozess.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Branching.SwitchBranch('a..b'));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Branching.RemoteBranchExists('-x', Exists));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Branching.RunStep(Default(TAtlasVcsBranchStep)));
  Assert.AreEqual(7, Integer(Length(ARunner.Calls)));
  // Git endet mit Fehler (Branch gibt es schon, Konflikt beim Wechsel): Failed.
  ARunner.ExitCode := 128;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Branching.SwitchBranch('feature/1-neu'));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Branching.RunStep(mSteps[0]));
  ARunner.ExitCode := 0;
end;
/// <summary>SVN: Kopie im Repository und switch, Serverrevision, Externals, Pfad im Repository.</summary>
procedure AssertSvnBranching(ARunner: TFakeRunner; const ARunnerRef: IAtlasVcsRunner;
  out ASteps: TArray<TAtlasVcsBranchStep>);
var
  Vcs: IAtlasVersionControl;
  Branching: IAtlasVcsBranching;
  Exists, mHas: Boolean;
  Hooks, GitDir, mRevision: string;
begin
  // SVN: Kopie im Repository und switch, beide mit dem Server und --non-interactive.
  Vcs := TAtlasSvnVersionControl.Create(Root, ARunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(Vcs, IAtlasVcsBranching, Branching), 'SVN bietet IAtlasVcsBranching');
  ARunner.Calls := nil;
  ASteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Svn, 'ATL-123-tracker-im-plugin',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Head, 'trunk', ''), 'ATL-123 Branch'));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.RunStep(ASteps[0]));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.RunStep(ASteps[1]));
  Assert.AreEqual('copy ^/trunk@ ^/branches/ATL-123-tracker-im-plugin@ --parents -m ATL-123 Branch --non-interactive',
    ARunner.Calls[0]);
  Assert.AreEqual('switch ^/branches/ATL-123-tracker-im-plugin@ . --non-interactive', ARunner.Calls[1]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.BranchExists('ATL-123-tracker-im-plugin', Exists));
  Assert.IsTrue(Exists);
  Assert.AreEqual('info ^/branches/ATL-123-tracker-im-plugin@ --non-interactive', ARunner.Calls[2]);
  // HEAD-Revision vom Server und Externals der Arbeitskopie (#1288).
  ARunner.Answer('info', '48230' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.ServerRevision('Kasse/trunk', mRevision));
  Assert.AreEqual('48230', mRevision);
  Assert.AreEqual('info --show-item revision --non-interactive ^/Kasse/trunk@', ARunner.Calls[3]);
  ARunner.Answer('propget', 'Libs - ^/Libs/Common/trunk Common' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.HasExternals(mHas));
  Assert.IsTrue(mHas);
  Assert.AreEqual('propget svn:externals -R . --non-interactive', ARunner.Calls[4]);
  ARunner.Answer('info', '^/Kasse/trunk' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.RepositoryPath(mRevision));
  Assert.AreEqual('Kasse/trunk', mRevision, 'voller Pfad ohne ^/');
  Assert.AreEqual('info --show-item relative-url . --non-interactive', ARunner.Calls[5]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.RemoteBranchExists('trunk', Exists));
  Assert.IsFalse(Exists, 'SVN kennt keine Remote-Branches');
  Assert.AreEqual(6, Integer(Length(ARunner.Calls)), 'ohne Prozess');
  // Fehlt der Branch, endet svn info mit Fehler: das ist die Antwort.
  ARunner.ExitCode := 1;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.BranchExists('ATL-9-neu', Exists));
  Assert.IsFalse(Exists);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, Branching.ServerRevision('trunk', mRevision));
  Assert.AreEqual('', mRevision);
  ARunner.ExitCode := 0;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.HookFolders(Hooks, GitDir));
  Assert.AreEqual('', Hooks);
  Assert.AreEqual(8, Integer(Length(ARunner.Calls)), 'Hooks ohne Prozess');
end;
procedure TAtlasVcsTests.ProvidersCreateIssueBranches;
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Branching: IAtlasVcsBranching;
  Exists: Boolean;
  mRevision: string;
  mSteps: TArray<TAtlasVcsBranchStep>;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  AssertGitBranching(Runner, RunnerRef);
  AssertSvnBranching(Runner, RunnerRef, mSteps);

  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsBranching, Branching));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Branching.RunStep(mSteps[0]));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Branching.BranchExists('feature/1-x', Exists));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, Branching.ServerRevision('trunk', mRevision));
  Assert.AreEqual(8, Integer(Length(Runner.Calls)), 'die leere Umsetzung startet keinen Prozess');
  mSteps := nil;
end;
/// <summary>Ohne erkennbares Layout kein Ort; fester Ort mit ^/; ungültiges Muster ohne Prozess.</summary>
procedure AssertSvnBranchLocations(ARunner: TFakeRunner; const ABranching: IAtlasVcsBranching;
  const AOptions: TAtlasVcsSvnBranchOptions);
var
  mOptions: TAtlasVcsSvnBranchOptions;
  mExists: Boolean;
begin
  mOptions := AOptions;
  // Ohne erkennbares Layout: kein Ort und kein Aufruf am Server.
  ARunner.Commands := nil;
  ARunner.Answers := nil;
  ARunner.Answer('info', '^/Sonstiges' + #10);
  ARunner.Calls := nil;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed,
    ABranching.BranchExists('KASSE-42-bon', mOptions, mExists));
  Assert.IsFalse(mExists);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, ABranching.SwitchBranch('KASSE-42-bon', mOptions));
  Assert.AreEqual(2, Integer(Length(ARunner.Calls)), 'nur relative-url');
  // Fester Ort mit ^/: ohne relative-url; {kennung} aus den Optionen.
  mOptions.Location := '^/Kasse/branches/{kennung}';
  mOptions.Key := 'KASSE-42';
  ARunner.Calls := nil;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, ABranching.BranchExists('KASSE-42-bon', mOptions, mExists));
  Assert.AreEqual(1, Integer(Length(ARunner.Calls)));
  Assert.AreEqual('info ^/Kasse/branches/KASSE-42@ --non-interactive', ARunner.Calls[0]);
  // Ungültiges Muster: Failed ohne Prozess.
  mOptions.Location := 'branches/{name}';
  ARunner.Calls := nil;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed,
    ABranching.BranchExists('KASSE-42-bon', mOptions, mExists));
  Assert.AreEqual(0, Integer(Length(ARunner.Calls)));
end;
procedure TAtlasVcsTests.SvnBranchOptionsUseLocation;
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Branching: IAtlasVcsBranching;
  mSvn: IAtlasVcsSvnWorkingCopy;
  mOptions: TAtlasVcsSvnBranchOptions;
  mExists: Boolean;
  mText: string;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, Under('bin/svn.exe'));
  Assert.IsTrue(Supports(Vcs, IAtlasVcsBranching, Branching));
  // Vorgabe {projektwurzel}/branches/{name}: in ^/Kasse/trunk sucht und schaltet Atlas unter ^/Kasse/branches.
  Runner.Answer('info', '^/Kasse/trunk' + #10);
  mOptions := TAtlasVcsSvnBranchOptions.Default;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.BranchExists('KASSE-42-bon', mOptions, mExists));
  Assert.IsTrue(mExists);
  Assert.AreEqual(2, Integer(Length(Runner.Calls)));
  Assert.AreEqual('info --show-item relative-url . --non-interactive', Runner.Calls[0]);
  Assert.AreEqual('info ^/Kasse/branches/KASSE-42-bon@ --non-interactive', Runner.Calls[1]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.SwitchBranch('KASSE-42-bon', mOptions));
  Assert.AreEqual(4, Integer(Length(Runner.Calls)));
  Assert.AreEqual('switch ^/Kasse/branches/KASSE-42-bon@ . --non-interactive', Runner.Calls[3]);
  Assert.AreEqual(Cardinal(TAtlasVcsBranchStep.cLongTimeoutMs), Runner.Timeouts[3], 'switch mit langem Zeitlimit');
  Assert.AreEqual(Cardinal(TAtlasVcsCommand.cDefaultTimeoutMs), Runner.Timeouts[1], 'info mit dem üblichen');
  AssertSvnBranchLocations(Runner, Branching, mOptions);
  // svnversion liegt neben svn und spricht nicht mit dem Server.
  Assert.IsTrue(Supports(Vcs, IAtlasVcsSvnWorkingCopy, mSvn));
  Runner.Answer('.', '48190:48213M' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mSvn.WorkingRevisions(mText));
  Assert.AreEqual('48190:48213M', mText);
  Assert.AreEqual(Under('bin/svnversion.exe'), Runner.Executables[High(Runner.Executables)]);
  Assert.AreEqual('.', Runner.Calls[High(Runner.Calls)]);
  // Git und die leere Umsetzung kennen keine SVN-Revisionen; die Optionen gelten dort nicht.
  Vcs := TAtlasGitVersionControl.Create(Root, RunnerRef, 'git.exe');
  Assert.IsFalse(Supports(Vcs, IAtlasVcsSvnWorkingCopy));
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsFalse(Supports(Vcs, IAtlasVcsSvnWorkingCopy));
  Assert.IsTrue(Supports(Vcs, IAtlasVcsBranching, Branching));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled,
    Branching.BranchExists('x', TAtlasVcsSvnBranchOptions.Default, mExists));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled,
    Branching.SwitchBranch('x', TAtlasVcsSvnBranchOptions.Default));
  Runner.Calls := nil;
  Runner.Executables := nil;
  Runner.Timeouts := nil;
  Runner.WorkingDirs := nil;
  Runner.Commands := nil;
  Runner.Answers := nil;
end;
procedure TAtlasVcsTests.SvnExternalsCommands;
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Branching: IAtlasVcsBranching;
  mSvn: IAtlasVcsSvnWorkingCopy;
  mText, mFile: string;
  mStep: TAtlasVcsBranchStep;
  mBytes: TBytes;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, Under('bin/svn.exe'));
  Assert.IsTrue(Supports(Vcs, IAtlasVcsSvnWorkingCopy, mSvn));
  Assert.IsTrue(Supports(Vcs, IAtlasVcsBranching, Branching));
  Runner.Answer('propget', '<properties/>');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mSvn.ExternalsXml(mText));
  Assert.AreEqual('<properties/>', mText);
  Assert.AreEqual('propget svn:externals --xml -R . --non-interactive', Runner.Calls[0]);
  Runner.Answer('info', 'https://svn.firma.local/repo' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mSvn.RepositoryRoot(mText));
  Assert.AreEqual('https://svn.firma.local/repo', mText);
  Assert.AreEqual('info --show-item repos-root-url . --non-interactive', Runner.Calls[1]);
  // Nur Schalter: Der Fake erkennt keinen Befehl ('').
  Runner.Answer('', '1.14.3' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mSvn.ToolVersion(mText));
  Assert.AreEqual('1.14.3', mText);
  Assert.AreEqual('--version --quiet', Runner.Calls[2]);
  Runner.Answer('Packages/Basis', '48190M' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mSvn.WorkingRevisions('Packages/Basis', mText));
  Assert.AreEqual('48190M', mText);
  Assert.AreEqual(Under('bin/svnversion.exe'), Runner.Executables[3]);
  // Eingabedatei für propset -F: vor dem Aufruf geschrieben, CRLF wird LF.
  mFile := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'Atlas-Vcs-Tests'), 'p0.txt');
  if TFile.Exists(mFile) then
  begin
    TFile.Delete(mFile);
  end;
  mStep := TAtlasVcsBranchStep.Make(TArray<string>.Create('propset', 'svn:externals', '-F', mFile, 'p0'), False,
    False);
  mStep.InputFile := mFile;
  mStep.InputText := '-r 1 ^/a Lib'#13#10'# ä'#13#10;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, Branching.RunStep(mStep));
  mBytes := TFile.ReadAllBytes(mFile);
  Assert.AreEqual('-r 1 ^/a Lib'#10'# ä'#10, TEncoding.UTF8.GetString(mBytes));
  Assert.IsFalse((Length(mBytes) >= 3) and (mBytes[0] = $EF), 'ohne BOM');
  Assert.AreEqual('propset svn:externals -F ' + mFile + ' p0 --non-interactive', Runner.Calls[High(Runner.Calls)]);
  TDirectory.Delete(ExtractFileDir(mFile), True);
  mStep := TAtlasVcsBranchStep.Make(nil, False, False);
  mBytes := nil;
  Runner.Calls := nil;
  Runner.Executables := nil;
  Runner.Timeouts := nil;
  Runner.WorkingDirs := nil;
  Runner.Commands := nil;
  Runner.Answers := nil;
end;
/// <summary>Git: Submodule statt Externals.</summary>
procedure AssertGitSubmodules(ARunner: TFakeRunner; const ARunnerRef: IAtlasVcsRunner);
var
  mVcs: IAtlasVersionControl;
  mSubmodules: IAtlasVcsSubmodules;
  mText: string;
begin
  mVcs := TAtlasGitVersionControl.Create(Root + PathDelim, ARunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsSubmodules, mSubmodules));
  Assert.IsFalse(Supports(mVcs, IAtlasVcsSvnExternals), 'Git kennt keine Externals');
  ARunner.Answer('submodule', ' 3f2a… Packages/Basis (heads/main)'#10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mSubmodules.SubmoduleStatus(mText));
  Assert.AreEqual(' 3f2a… Packages/Basis (heads/main)'#10, mText);
  Assert.IsTrue(ARunner.Calls[High(ARunner.Calls)].EndsWith('submodule status --recursive'),
    ARunner.Calls[High(ARunner.Calls)]);
end;
procedure TAtlasVcsTests.WorkingCopyStateCommands;
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  mExternals: IAtlasVcsSvnExternals;
  mText, mFile: string;
  mCount: Integer;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, Under('bin/svn.exe'));
  Assert.IsTrue(Supports(Vcs, IAtlasVcsSvnExternals, mExternals));
  Assert.IsFalse(Supports(Vcs, IAtlasVcsSubmodules), 'SVN kennt keine Submodule');
  Runner.Answer('status', '<status/>');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mExternals.StatusXml(mText));
  Assert.AreEqual('<status/>', mText);
  Assert.AreEqual('status --xml . --non-interactive', Runner.Calls[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mExternals.Update(False));
  Assert.AreEqual('update . --non-interactive', Runner.Calls[1]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mExternals.Update(True));
  Assert.AreEqual('update . --ignore-externals --non-interactive', Runner.Calls[2]);
  // HEAD:4711 enthält 4711 selbst, wenn sie den Pfad geändert hat.
  Runner.Answer('log', '<?xml version="1.0"?><log><logentry revision="4790"></logentry>' +
    '<logentry revision="4750"></logentry><logentry revision="4711"></logentry></log>');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    mExternals.CommitsSince('Packages/Kunden/trunk', '4711', mCount));
  Assert.AreEqual(2, mCount);
  Assert.AreEqual('log -q --xml -r HEAD:4711 ^/Packages/Kunden/trunk@HEAD --non-interactive', Runner.Calls[3]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed,
    mExternals.CommitsSince('Packages/Kunden/trunk', 'HEAD', mCount));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mExternals.CommitsSince('-r1', '4711', mCount));
  Assert.AreEqual(4, Integer(Length(Runner.Calls)), 'ungültig ohne Aufruf');
  Runner.Answer('log', '<log><logentry');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed,
    mExternals.CommitsSince('Packages/Kunden/trunk', '4711', mCount));
  Assert.AreEqual(0, mCount);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    mExternals.SetExternals('', '-r 4711 ^/Packages/Kunden/trunk Packages/Kunden'#10));
  mText := Runner.Calls[High(Runner.Calls)];
  Assert.IsTrue(mText.StartsWith('propset svn:externals -F '), mText);
  Assert.IsTrue(mText.EndsWith(' . --non-interactive'), mText);
  mFile := Copy(mText, Length('propset svn:externals -F ') + 1, Length(mText));
  mFile := Copy(mFile, 1, Length(mFile) - Length(' . --non-interactive'));
  Assert.IsFalse(TFile.Exists(mFile), 'Temp-Datei wieder entfernt');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mExternals.SetExternals('Packages', '^/x Lib'));
  Assert.IsTrue(Runner.Calls[High(Runner.Calls)].EndsWith(' Packages --non-interactive'));
  mExternals := nil;
  AssertGitSubmodules(Runner, RunnerRef);
  mText := '';
  mFile := '';
  Runner.Calls := nil;
  Runner.Executables := nil;
  Runner.Timeouts := nil;
  Runner.WorkingDirs := nil;
  Runner.Commands := nil;
  Runner.Answers := nil;
end;
/// <summary>worktree: eigener Ordner statt stash und checkout; Push an den Remote des Hauptbranchs.</summary>
procedure AssertGitWorktreeBranch(ARunner: TFakeRunner; const ABranching: IAtlasVcsBranching);
const
  Prefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
  RemotePrefix = Prefix + '-c credential.interactive=never -c core.askPass= ';
var
  mRequest: TAtlasVcsBranchRequest;
  mSteps: TArray<TAtlasVcsBranchStep>;
  mRun: TAtlasVcsBranchRun;
  mFolder: string;
begin
  // worktree: eigener Ordner statt stash und checkout; Push an den Remote des Hauptbranchs.
  ARunner.Calls := nil;
  mFolder := ExtractFileDir(Root) + PathDelim + 'kasse-ATL-9';
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'ATL-9-neu',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.LocalMain, 'main', '', 'upstream'), '');
  mRequest.Stash := True;
  mRequest.PushNow := True;
  mRequest.WorktreeFolder := mFolder;
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  mRun := TAtlasVcsBranchPlan.Execute(ABranching, mSteps);
  Assert.IsTrue(mRun.Succeeded);
  Assert.AreEqual(2, Integer(Length(ARunner.Calls)));
  Assert.AreEqual(Prefix + 'worktree add --quiet --no-track -b ATL-9-neu ' + mFolder + ' refs/heads/main',
    ARunner.Calls[0]);
  Assert.AreEqual(RemotePrefix + 'push --set-upstream upstream refs/heads/ATL-9-neu:refs/heads/ATL-9-neu',
    ARunner.Calls[1]);
end;
procedure TAtlasVcsTests.ProvidersRunGitBranchOptions;
const
  Prefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
  RemotePrefix = Prefix + '-c credential.interactive=never -c core.askPass= ';
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  mBranching: IAtlasVcsBranching;
  mRequest: TAtlasVcsBranchRequest;
  mSteps: TArray<TAtlasVcsBranchStep>;
  mRun: TAtlasVcsBranchRun;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Vcs := TAtlasGitVersionControl.Create(Root, RunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsBranching, mBranching));
  // Basis vom Server, vorher beiseitelegen, sofort pushen.
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/9-neu',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.RemoteMain, 'main', '', 'origin'), '');
  mRequest.Fetch := True;
  mRequest.Stash := True;
  mRequest.PushNow := True;
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, mSteps);
  Assert.IsTrue(mRun.Succeeded);
  Assert.AreEqual(4, Integer(Length(Runner.Calls)));
  Assert.AreEqual(RemotePrefix + 'fetch --quiet --no-tags origin main', Runner.Calls[0]);
  Assert.AreEqual(Prefix + 'stash push --include-untracked --quiet -m Atlas: vor feature/9-neu', Runner.Calls[1]);
  Assert.AreEqual(Prefix + 'checkout --quiet --no-track -b feature/9-neu refs/remotes/origin/main --',
    Runner.Calls[2]);
  Assert.AreEqual(RemotePrefix + 'push --set-upstream origin refs/heads/feature/9-neu:refs/heads/feature/9-neu',
    Runner.Calls[3]);
  Assert.AreEqual(Root, Runner.WorkingDirs[3], 'alles in der Wurzel der Arbeitskopie');
  // Ohne Anmeldung: LoginNeeded beim Abruf, danach nichts.
  Runner.Calls := nil;
  Runner.ExitCode := 128;
  Runner.ErrorText := 'fatal: Authentication failed for ''https://example.com/kasse.git/''';
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, mSteps);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.LoginNeeded, mRun.Outcome);
  Assert.IsTrue(TAtlasVcsBranchPlan.FetchFailed(mSteps, mRun));
  Assert.AreEqual(1, Integer(Length(Runner.Calls)));
  Runner.ErrorText := '';
  Runner.ExitCode := 0;
  AssertGitWorktreeBranch(Runner, mBranching);
  mSteps := nil;
  mRequest := Default(TAtlasVcsBranchRequest);
end;
procedure TAtlasVcsTests.SafeBranchNames;
begin
  Assert.IsTrue(VcsSafeBranchName('feature/753-atlas-bereiche-und'));
  Assert.IsTrue(VcsSafeBranchName('ATL-123-tracker'));
  Assert.IsTrue(VcsSafeBranchName('branches/release-1.2'));
  Assert.IsFalse(VcsSafeBranchName(''));
  Assert.IsFalse(VcsSafeBranchName('-f'));
  Assert.IsFalse(VcsSafeBranchName('/abs'));
  Assert.IsFalse(VcsSafeBranchName('a b'));
  Assert.IsFalse(VcsSafeBranchName('a..b'));
  Assert.IsFalse(VcsSafeBranchName('a~1'));
  Assert.IsFalse(VcsSafeBranchName('a^'));
  Assert.IsFalse(VcsSafeBranchName('a:b'));
  Assert.IsFalse(VcsSafeBranchName('a\b'));
  Assert.IsFalse(VcsSafeBranchName('a@{1}'));
  Assert.IsFalse(VcsSafeBranchName('a/'));
  Assert.IsFalse(VcsSafeBranchName('a.'));
  Assert.IsFalse(VcsSafeBranchName('a//b'));
end;
/// <summary>SVN: erst info (Pfad der Arbeitskopie), dann das ganze Repository.</summary>
procedure AssertSvnHistory(ARunner: TFakeRunner; const ARunnerRef: IAtlasVcsRunner);
var
  Vcs: IAtlasVersionControl;
  History: IAtlasVcsHistory;
  Entries: TArray<TAtlasVcsLogEntry>;
  Refs: TArray<TAtlasVcsRef>;
  Content: TBytes;
  FileOf: TAtlasVcsLogFile;
  Ahead, Behind: Integer;
begin
  // SVN: erst info (Pfad der Arbeitskopie), dann das ganze Repository.
  ARunner.Calls := nil;
  ARunner.Commands := nil;
  ARunner.Answers := nil;
  ARunner.Answer('info', StringReplace(SvnInfoSample, 'projekt/branches/release-2', 'projekt/trunk',
    [rfReplaceAll]));
  ARunner.Answer('log', SvnLogSample);
  ARunner.Answer('list', SvnListSample);
  ARunner.Answer('cat', 'alt');
  Vcs := TAtlasSvnVersionControl.Create(Root, ARunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(Vcs, IAtlasVcsHistory, History), 'SVN bietet IAtlasVcsHistory');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, History.SearchLog('ATL-12', 50, Entries));
  Assert.AreEqual('info --xml . --non-interactive', ARunner.Calls[0]);
  Assert.AreEqual('log --xml -v --search ATL-12 -l 50 ^/ --non-interactive', ARunner.Calls[1]);
  Assert.AreEqual(Under('src/Main.pas'), Entries[0].Files[0].Path);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, History.AllBranches(Refs));
  Assert.AreEqual('list --xml ^/branches --non-interactive', ARunner.Calls[3]);
  Assert.AreEqual(2, Integer(Length(Refs)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, History.Distance('ATL-12-tracker', 'trunk', Ahead, Behind));
  Assert.AreEqual(-1, Ahead, 'SVN kennt keinen Vorsprung');
  Assert.AreEqual(4, Integer(Length(ARunner.Calls)), 'ohne Prozess');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, History.ContentOf('57', Entries[0].Files[0], True, Content));
  Assert.AreEqual('cat ^/projekt/branches/ATL-12-tracker/src/Main.pas@56 --non-interactive', ARunner.Calls[4]);
  Assert.AreEqual('alt', TEncoding.UTF8.GetString(Content));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, History.ContentOf('57', Entries[0].Files[1], False, Content),
    'gelöscht: danach leer');
  Assert.AreEqual(5, Integer(Length(ARunner.Calls)));
  // Vorher merken: Das gescheiterte SearchLog leert Entries (out).
  FileOf := Entries[0].Files[0];
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, History.SearchLog('ATL-*', 50, Entries), 'Glob-Zeichen');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, History.ContentOf('x', FileOf, True, Content));
  Assert.AreEqual(5, Integer(Length(ARunner.Calls)));
end;
procedure TAtlasVcsTests.ProvidersRunHistoryCommands;
const
  Prefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  History: IAtlasVcsHistory;
  Entries: TArray<TAtlasVcsLogEntry>;
  Refs: TArray<TAtlasVcsRef>;
  Content: TBytes;
  FileOf: TAtlasVcsLogFile;
  Ahead, Behind: Integer;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Runner.Answer('log', GitHistorySample);
  Runner.Answer('for-each-ref', 'refs/heads/main'#0'1761600000'#0'*'#10);
  Runner.Answer('rev-list', '0'#9'2'#10);
  Runner.Answer('show', 'Inhalt');
  Vcs := TAtlasGitVersionControl.Create(Root, RunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsHistory, History), 'Git bietet IAtlasVcsHistory');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, History.SearchLog('ATL-12', 200, Entries));
  Assert.AreEqual(2, Integer(Length(Entries)));
  Assert.AreEqual(Prefix + 'log --all --fixed-strings --regexp-ignore-case --grep=ATL-12 ' +
    '--format=%x1e%H%x00%ct%x00%an%x00%B --name-status -z --no-renames --max-count=200', Runner.Calls[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, History.AllBranches(Refs));
  Assert.AreEqual(Prefix + 'for-each-ref --format=%(refname)%00%(committerdate:unix)%00%(HEAD) refs/heads refs/remotes',
    Runner.Calls[1]);
  Assert.AreEqual(1, Integer(Length(Refs)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    History.Distance('feature/ATL-12-x', 'origin/main', Ahead, Behind));
  Assert.AreEqual(Prefix + 'rev-list --left-right --count origin/main...feature/ATL-12-x --', Runner.Calls[2]);
  Assert.AreEqual(2, Ahead);
  Assert.AreEqual(0, Behind);
  FileOf := Entries[0].Files[0];
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, History.ContentOf(Entries[0].Revision, FileOf, True, Content));
  Assert.AreEqual(Prefix + 'show 28358feaf94440dbfe2fcc3aa2cb742e2d972f37^1:A.pas', Runner.Calls[3]);
  Assert.AreEqual('Inhalt', TEncoding.UTF8.GetString(Content));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    History.ContentOf(Entries[0].Revision, FileOf, False, Content));
  Assert.AreEqual(Prefix + 'show 28358feaf94440dbfe2fcc3aa2cb742e2d972f37:A.pas', Runner.Calls[4]);
  // Neue Datei davor, gelöschte danach: leer ohne Prozess.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    History.ContentOf(Entries[0].Revision, Entries[0].Files[1], True, Content));
  Assert.AreEqual(0, Integer(Length(Content)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    History.ContentOf(Entries[0].Revision, Entries[0].Files[2], False, Content));
  Assert.AreEqual(5, Integer(Length(Runner.Calls)));
  // Unsichere Eingaben starten keinen Prozess.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, History.SearchLog('', 10, Entries));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, History.SearchLog('a'#10'b', 10, Entries));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, History.Distance('--all', 'main', Ahead, Behind));
  Assert.AreEqual(-1, Ahead);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, History.ContentOf('-x', FileOf, False, Content));
  Assert.AreEqual(5, Integer(Length(Runner.Calls)));
  // Unlesbare Ausgabe: Failed statt Ausnahme.
  Runner.Answers[0] := #$1E'kurz'#0;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, History.SearchLog('ATL-12', 10, Entries));
  Assert.AreEqual(0, Integer(Length(Entries)));

  AssertSvnHistory(Runner, RunnerRef);

  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsHistory, History));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, History.SearchLog('ATL-12', 50, Entries));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, History.AllBranches(Refs));
  Assert.AreEqual(5, Integer(Length(Runner.Calls)), 'die leere Umsetzung startet keinen Prozess');
end;
initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsTests);

end.
