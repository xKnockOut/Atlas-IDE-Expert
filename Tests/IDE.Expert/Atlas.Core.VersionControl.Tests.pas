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
  mIndex: Integer;
  mCommand: string;
  mAfterC: Boolean;
begin
  Calls := Calls + [string.Join(' ', AArguments)];
  WorkingDirs := WorkingDirs + [AWorkingDir];
  Executables := Executables + [AExecutable];
  Timeouts := Timeouts + [ATimeoutMs];
  mCommand := '';
  mAfterC := False;
  for mIndex := 0 to High(AArguments) do
  begin
    if mAfterC then
    begin
      mAfterC := False;
    end
    else if AArguments[mIndex] = '-c' then
    begin
      mAfterC := True;
    end
    else if Copy(AArguments[mIndex], 1, 1) <> '-' then
    begin
      mCommand := AArguments[mIndex];
      Break;
    end;
  end;
  Result := TAtlasVcsRunResult.Make(Outcome, ExitCode, nil);
  Result.ErrorText := ErrorText;
  for mIndex := 0 to High(Commands) do
  begin
    if Commands[mIndex] = mCommand then
    begin
      Result.Output := Utf8Bytes(Answers[mIndex]);
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
  mProvider: TAtlasVcsProvider;
begin
  for mProvider := Low(TAtlasVcsProvider) to High(TAtlasVcsProvider) do
  begin
    Assert.AreEqual<TAtlasVcsProvider>(mProvider,
      AtlasVcsProviderOf(AtlasVcsProviderText(mProvider)), AtlasVcsProviderText(mProvider));
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
  mRelative: string;
begin
  Assert.IsTrue(VcsRelativePath(Root, Under('src/Main.pas'), mRelative));
  Assert.AreEqual('src/Main.pas', mRelative);
  Assert.IsTrue(VcsRelativePath(Root + PathDelim, Under('A.pas'), mRelative), 'Wurzel mit Trenner');
  Assert.AreEqual('A.pas', mRelative);
  Assert.IsFalse(VcsRelativePath(Root, Root + 'X' + PathDelim + 'A.pas', mRelative), 'Nachbarordner mit gleichem Anfang');
  Assert.IsFalse(VcsRelativePath(Root, Root, mRelative), 'die Wurzel selbst ist keine Datei');
  // #1292: Ordner der Wurzel selbst ("." im Status, Ziel von svn:externals).
  Assert.IsTrue(VcsRelativeOrRoot(Root, Root + PathDelim, mRelative));
  Assert.AreEqual('', mRelative);
  Assert.IsTrue(VcsRelativeOrRoot(Root, Under('src/Main.pas'), mRelative));
  Assert.AreEqual('src/Main.pas', mRelative);
  Assert.IsFalse(VcsRelativeOrRoot(Root, Root + 'X', mRelative));
  Assert.IsFalse(VcsRelativeOrRoot('', '', mRelative));
  // Weiterleitung für den Host
  Assert.IsTrue(TAtlasVcsDetection.RelativePath(Root, Under('src/Main.pas'), mRelative));
  Assert.AreEqual('src/Main.pas', mRelative);
  Assert.IsFalse(TAtlasVcsDetection.RelativePath(Root, Root, mRelative));
  if PathDelim = '\' then
  begin
    Assert.IsTrue(VcsRelativePath('c:\projekte\kunde', Under('A.pas'), mRelative), 'Windows: ohne Groß/klein');
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
  mDate: TDateTime;
begin
  Assert.IsTrue(VcsParseIsoDate('2026-10-01T08:30:15.250000Z', mDate));
  Assert.AreEqual('2026-10-01 08:30:15.250', FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', mDate));
  Assert.IsTrue(VcsParseIsoDate('2026-10-01T08:30:15Z', mDate), 'ohne Bruchteile');
  Assert.AreEqual('2026-10-01 08:30:15.000', FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', mDate));
  Assert.IsFalse(VcsParseIsoDate('01.10.2026', mDate));
  Assert.IsFalse(VcsParseIsoDate('2026-13-01T08:30:15Z', mDate), 'Monat 13');
  Assert.AreEqual('2026-10-15 12:22:39', FormatDateTime('yyyy-mm-dd hh:nn:ss', VcsUnixToDate(1792066959)));
  Assert.AreEqual('a & b <c> "d" ''e'' ' + #$00FC + ' ' + #$00E4, VcsXmlDecode(
    'a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&apos; &#252; &#xE4;'));
  Assert.AreEqual('ohne', VcsXmlDecode('ohne'));
  Assert.AreEqual('&unbekannt; & offen', VcsXmlDecode('&unbekannt; & offen'));
end;
procedure TAtlasVcsTests.XmlReaderReadsElementsAttributesAndText;
var
  mReader: TAtlasVcsXmlReader;
  mTrace: string;
begin
  mReader := TAtlasVcsXmlReader.Create('<?xml version="1.0"?><!-- Kommentar --><a x="1" y=''z &amp; w''>' +
    'Text<b/><c k="v"></c></a>');
  try
    mTrace := '';
    while mReader.Next do
      case mReader.Node of
        TAtlasVcsXmlNode.StartTag:
          begin
            mTrace := mTrace + '<' + mReader.Name;
            if mReader.Name = 'a' then
            begin
              mTrace := mTrace + ' x=' + mReader.Attr('x') + ' y=' + mReader.Attr('y') + ' q=' + mReader.Attr('q');
            end;
            if mReader.EmptyElement then
            begin
              mTrace := mTrace + '/';
            end;
            mTrace := mTrace + '>';
          end;
        TAtlasVcsXmlNode.EndTag:
          mTrace := mTrace + '</' + mReader.Name + '>';
        TAtlasVcsXmlNode.Text:
          mTrace := mTrace + '[' + mReader.Value + ']';
      end;
  finally
    mReader.Free;
  end;
  Assert.AreEqual('<a x=1 y=z & w q=>[Text]<b/><c></c></a>', mTrace);
  mReader := TAtlasVcsXmlReader.Create('<a x=1>');
  try
    Assert.WillRaise(
      procedure
      begin
        mReader.Next;
      end, EAtlasVcsParse);
  finally
    mReader.Free;
  end;
end;
function FakeFileSystem(const ADirs, AFiles: TArray<string>; out ADirExists, AFileExists: TAtlasVcsPathExists): Boolean;
var
  mDirs, mFiles: TArray<string>;
begin
  mDirs := ADirs;
  mFiles := AFiles;
  ADirExists :=
    function(const APath: string): Boolean
    var
      Item: string;
    begin
      for Item in mDirs do
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
      for Item in mFiles do
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
  mDirExists, mFileExists_: TAtlasVcsPathExists;
  mFound: TAtlasVcsWorkingCopy;
begin
  // Git-Repository mit einer SVN-Arbeitskopie darin (Fremdcode) und einem Submodul (.git als Datei).
  FakeFileSystem([Under('.git'), Under('lib/fremd/.svn')], [Under('ext/sub/.git')], mDirExists, mFileExists_);
  mFound := TAtlasVcsDetection.Find(Under('src/app'), TAtlasVcsProvider.Auto, mDirExists, mFileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git, mFound.Kind);
  Assert.AreEqual(Root, mFound.Root);
  mFound := TAtlasVcsDetection.Find(Under('lib/fremd/src'), TAtlasVcsProvider.Auto, mDirExists, mFileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Svn, mFound.Kind, 'die nächstliegende gilt');
  Assert.AreEqual(Under('lib/fremd'), mFound.Root);
  mFound := TAtlasVcsDetection.Find(Under('ext/sub/src'), TAtlasVcsProvider.Auto, mDirExists, mFileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git, mFound.Kind, '.git als Datei (Submodul, Worktree)');
  Assert.AreEqual(Under('ext/sub'), mFound.Root);
  mFound := TAtlasVcsDetection.Find(Root + PathDelim, TAtlasVcsProvider.Auto, mDirExists, mFileExists_);
  Assert.AreEqual(Root, mFound.Root, 'Ordner mit Trenner am Ende');
  // Beide im selben Ordner: Git gewinnt.
  FakeFileSystem([Under('.git'), Under('.svn')], [], mDirExists, mFileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git,
    TAtlasVcsDetection.Find(Root, TAtlasVcsProvider.Auto, mDirExists, mFileExists_).Kind);
  FakeFileSystem([], [], mDirExists, mFileExists_);
  mFound := TAtlasVcsDetection.Find(Under('src'), TAtlasVcsProvider.Auto, mDirExists, mFileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, mFound.Kind, 'ohne Arbeitskopie');
  Assert.AreEqual('', mFound.Root);
end;
procedure TAtlasVcsTests.DetectionHonoursProvider;
var
  mDirExists, mFileExists_: TAtlasVcsPathExists;
  mFound: TAtlasVcsWorkingCopy;
begin
  FakeFileSystem([Under('.git'), Under('lib/fremd/.svn')], [], mDirExists, mFileExists_);
  mFound := TAtlasVcsDetection.Find(Under('lib/fremd/src'), TAtlasVcsProvider.Git, mDirExists, mFileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git, mFound.Kind, 'git: SVN wird übergangen');
  Assert.AreEqual(Root, mFound.Root);
  mFound := TAtlasVcsDetection.Find(Under('src'), TAtlasVcsProvider.Svn, mDirExists, mFileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, mFound.Kind, 'svn: Git zählt nicht');
  mFound := TAtlasVcsDetection.Find(Under('lib/fremd'), TAtlasVcsProvider.Off, mDirExists, mFileExists_);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, mFound.Kind, 'off sucht nicht');
end;
procedure TAtlasVcsTests.LocatesProgramInPathAndKnownDirs;
var
  mExe, mPathText: string;
  mDirs: TArray<string>;
begin
  mExe := 'svn';
  if PathDelim = '\' then
  begin
    mExe := 'svn.exe';
  end;
  mPathText := Under('leer') + PathSep + '"' + Under('tools') + '"' + PathSep + PathSep;
  Assert.AreEqual(Under('tools/' + mExe), TAtlasVcsTools.Locate('svn', mPathText, nil,
    function(const APath: string): Boolean
    begin
      Result := APath = Under('tools/' + mExe);
    end), 'PATH mit Anführungszeichen und leeren Einträgen');
  mDirs := TAtlasVcsTools.KnownDirs(TAtlasVcsKind.Svn, [Root, '']);
  Assert.AreEqual(Under('TortoiseSVN/bin'), mDirs[0], 'TortoiseSVN mit Kommandozeilenwerkzeugen');
  Assert.AreEqual(Under('TortoiseSVN/bin/' + mExe), TAtlasVcsTools.Locate('svn', '', mDirs,
    function(const APath: string): Boolean
    begin
      Result := APath = Under('TortoiseSVN/bin/' + mExe);
    end));
  Assert.AreEqual(Under('Git/cmd'), TAtlasVcsTools.KnownDirs(TAtlasVcsKind.Git, [Root])[0]);
  Assert.AreEqual('', TAtlasVcsTools.Locate('svn', mPathText, mDirs,
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
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mHead: TAtlasVcsHead;
  mChanges: TArray<TAtlasVcsChange>;
  mContent: TBytes;
  mLines: TArray<TAtlasVcsBlameLine>;
begin
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  mRunner.Answer('status', GitStatusSample);
  mRunner.Answer('show', 'unit A;');
  mRunner.Answer('blame', cHash1 + ' 1 1 1'#10'author Ada'#10'summary S'#10#9'x'#10);
  mVcs := TAtlasGitVersionControl.Create(Root + PathDelim, mRunnerRef, 'git.exe', 5000);
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git, mVcs.Kind);
  Assert.AreEqual(Root, mVcs.WorkingCopy.Root, 'ohne Trenner am Ende');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.Head(mHead));
  Assert.AreEqual('main', mHead.Branch);
  Assert.AreEqual('--no-optional-locks -c core.quotepath=off -c color.ui=false status --porcelain=v2 --branch -z ' +
    '--untracked-files=no', mRunner.Calls[0]);
  Assert.AreEqual(Root, mRunner.WorkingDirs[0], 'git läuft in der Wurzel');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.Changes(mChanges));
  Assert.AreEqual(5, Integer(Length(mChanges)));
  Assert.Contains(mRunner.Calls[1], '--untracked-files=all');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.FileAt(Under('src/Main.pas'), '', mContent));
  Assert.AreEqual('unit A;', TEncoding.UTF8.GetString(mContent));
  Assert.IsTrue(Pos('show HEAD:src/Main.pas', mRunner.Calls[2]) > 0, 'Revision leer = HEAD, Pfad mit /');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.FileAt(Under('A.pas'), cHash2, mContent));
  Assert.Contains(mRunner.Calls[3], 'show ' + cHash2 + ':A.pas');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.Blame(Under('src/Main.pas'), mLines));
  Assert.Contains(mRunner.Calls[4], 'blame --porcelain -- src/Main.pas');
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.AreEqual('S', mLines[0].Summary);
  // Datei außerhalb der Arbeitskopie, Revision als Option: kein Aufruf.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mVcs.FileAt(Root + 'X' + PathDelim + 'A.pas', '', mContent));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mVcs.FileAt(Under('A.pas'), '--output=x', mContent));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mVcs.Blame(Root + 'X' + PathDelim + 'A.pas', mLines));
  Assert.AreEqual(5, Integer(Length(mRunner.Calls)));
end;
procedure TAtlasVcsTests.SvnProviderRunsExpectedCommands;
var
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mHead: TAtlasVcsHead;
  mChanges: TArray<TAtlasVcsChange>;
  mContent: TBytes;
  mLines: TArray<TAtlasVcsBlameLine>;
begin
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  mRunner.Answer('info', cSvnInfoSample);
  mRunner.Answer('status', cSvnStatusSample);
  mRunner.Answer('cat', 'unit Main;');
  mRunner.Answer('blame', cSvnBlameSample);
  mVcs := TAtlasSvnVersionControl.Create(Root, mRunnerRef, 'svn.exe');
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Svn, mVcs.Kind);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.Head(mHead));
  Assert.AreEqual('branches/release-2', mHead.Branch);
  Assert.AreEqual('42', mHead.Revision);
  Assert.AreEqual('r42', mHead.ShortRevision(TAtlasVcsKind.Svn));
  Assert.AreEqual(-1, mHead.Ahead);
  Assert.AreEqual('info --xml . --non-interactive', mRunner.Calls[0]);
  Assert.AreEqual(Root, mRunner.WorkingDirs[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.Changes(mChanges));
  Assert.AreEqual(6, Integer(Length(mChanges)));
  Assert.AreEqual('status --xml . --non-interactive', mRunner.Calls[1]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.FileAt(Under('src/Main.pas'), '', mContent));
  Assert.AreEqual('cat -r BASE src/Main.pas@ --non-interactive', mRunner.Calls[2], 'Revision leer = BASE');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.FileAt(Under('src/Main.pas'), '40', mContent));
  Assert.AreEqual('cat -r 40 src/Main.pas@ --non-interactive', mRunner.Calls[3]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mVcs.Blame(Under('src/Main.pas'), mLines));
  Assert.AreEqual('blame --xml src/Main.pas@ --non-interactive', mRunner.Calls[4]);
  Assert.AreEqual(3, Integer(Length(mLines)));
end;
procedure TAtlasVcsTests.ProvidersMapFailuresToOutcome;
var
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mHead: TAtlasVcsHead;
  mChanges: TArray<TAtlasVcsChange>;
begin
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  mRunner.ExitCode := 128;
  mVcs := TAtlasGitVersionControl.Create(Root, mRunnerRef, 'git.exe');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mVcs.Head(mHead), 'Exit-Code ungleich 0');
  Assert.AreEqual('', mHead.Branch);
  mRunner.ExitCode := 0;
  mRunner.Outcome := TAtlasVcsOutcome.TimedOut;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.TimedOut, mVcs.Changes(mChanges), 'Zeitlimit kommt durch');
  mRunner.Outcome := TAtlasVcsOutcome.MainThread;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.MainThread, mVcs.Head(mHead), 'Hauptthread abgelehnt');
  mRunner.Outcome := TAtlasVcsOutcome.Ok;
  mRunner.Answer('status', 'Z kaputt'#0);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mVcs.Changes(mChanges), 'unlesbare Ausgabe');
  Assert.AreEqual(0, Integer(Length(mChanges)));
  mRunner.Answer('info', '<info>');
  mVcs := TAtlasSvnVersionControl.Create(Root, mRunnerRef, 'svn.exe');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mVcs.Head(mHead), 'svn info ohne Eintrag');
  mVcs := TAtlasSvnVersionControl.Create(Root, mRunnerRef, '');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.ToolMissing, mVcs.Head(mHead), 'ohne Programm kein Aufruf');
end;
procedure TAtlasVcsTests.WithoutWorkingCopyEverythingIsEmpty;
var
  mVcs: IAtlasVersionControl;
  mHead: TAtlasVcsHead;
  mChanges: TArray<TAtlasVcsChange>;
  mContent: TBytes;
  mLines: TArray<TAtlasVcsBlameLine>;
begin
  mVcs := TAtlasNullVersionControl.Create;
  Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, mVcs.Kind);
  Assert.AreEqual('', mVcs.WorkingCopy.Root);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.NoWorkingCopy, mVcs.Head(mHead));
  Assert.AreEqual('', mHead.Branch);
  Assert.AreEqual('', mHead.ShortRevision(TAtlasVcsKind.None));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.NoWorkingCopy, mVcs.Changes(mChanges));
  Assert.AreEqual(0, Integer(Length(mChanges)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.NoWorkingCopy, mVcs.FileAt(Under('A.pas'), '', mContent));
  Assert.AreEqual(0, Integer(Length(mContent)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.NoWorkingCopy, mVcs.Blame(Under('A.pas'), mLines));
  Assert.AreEqual('', mVcs.ChangeMarker);
  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mVcs.Head(mHead));
end;
function TempFolder(const AName: string): string;
var
  mTemp: string;
begin
  mTemp := GetEnvironmentVariable('TEMP');
  if mTemp = '' then
  begin
    mTemp := GetEnvironmentVariable('TMPDIR');
  end;
  if mTemp = '' then
  begin
    mTemp := '/tmp';
  end;
  Result := IncludeTrailingPathDelimiter(mTemp) + 'AtlasVcsTests-' + AName + '-' + FormatDateTime('hhnnsszzz', Now) +
    IntToStr(Random(1000));
  ForceDirectories(Result);
end;
procedure WriteText(const AFileName, AText: string);
var
  mStream: TFileStream;
  mBytes: TBytes;
begin
  mBytes := TEncoding.UTF8.GetBytes(AText);
  mStream := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(mBytes) > 0 then
    begin
      mStream.WriteBuffer(mBytes[0], Length(mBytes));
    end;
  finally
    mStream.Free;
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
  mFolder: string;
  mVcs: IAtlasVersionControl;
  mReported: TArray<TAtlasVcsKind>;
  mRunnerRef: IAtlasVcsRunner;
  mHead: TAtlasVcsHead;
  mLocate: TAtlasVcsLocate;
begin
  mRunnerRef := TFakeRunner.Create;
  mFolder := TempFolder('open');
  ForceDirectories(mFolder + PathDelim + '.svn');
  ForceDirectories(mFolder + PathDelim + 'src');
  mLocate := GitOnlyLocate();
  mReported := nil;
  TAtlasVcsNotices.Reset;
  TAtlasVcsNotices.OnToolMissing :=
    procedure(AKind: TAtlasVcsKind)
    begin
      mReported := mReported + [AKind];
    end;
  try
    mVcs := TAtlasVersionControl.Open(mFolder + PathDelim + 'src', TAtlasVcsProvider.Auto, mRunnerRef, mLocate, 1000);
    Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, mVcs.Kind, 'ohne svn weiter ohne Versionsverwaltung');
    Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.ToolMissing, mVcs.Head(mHead));
    mVcs := TAtlasVersionControl.Open(mFolder, TAtlasVcsProvider.Auto, mRunnerRef, mLocate, 1000);
    Assert.AreEqual(1, Integer(Length(mReported)), 'nur einmal gemeldet');
    Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Svn, mReported[0]);
    mVcs := TAtlasVersionControl.Open(mFolder, TAtlasVcsProvider.Off, mRunnerRef, mLocate, 1000);
    Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mVcs.Head(mHead), 'off');
    mVcs := TAtlasVersionControl.Open(mFolder, TAtlasVcsProvider.Git, mRunnerRef, mLocate, 1000);
    Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.NoWorkingCopy, mVcs.Head(mHead), 'git gewählt, aber nur SVN da');
    ForceDirectories(mFolder + PathDelim + '.git');
    mVcs := TAtlasVersionControl.Open(mFolder + PathDelim + 'src', TAtlasVcsProvider.Auto, mRunnerRef, mLocate, 1000);
    Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.Git, mVcs.Kind);
    Assert.AreEqual(VcsNormalizeDir(mFolder), mVcs.WorkingCopy.Root);
    mVcs := TAtlasVersionControl.Open(mFolder, TAtlasVcsProvider.Svn, mRunnerRef, mLocate, 1000);
    Assert.AreEqual<TAtlasVcsKind>(TAtlasVcsKind.None, mVcs.Kind, 'svn gewählt, svn fehlt');
    Assert.AreEqual(1, Integer(Length(mReported)), 'auch dann nicht noch einmal');
    TAtlasVcsNotices.Reset;
    mVcs := TAtlasVersionControl.Open(mFolder, TAtlasVcsProvider.Svn, mRunnerRef, mLocate, 1000);
    Assert.AreEqual(2, Integer(Length(mReported)), 'nach Reset wieder');
  finally
    TAtlasVcsNotices.OnToolMissing := nil;
    TAtlasVcsNotices.Reset;
    RemoveDir(mFolder + PathDelim + '.git');
    RemoveDir(mFolder + PathDelim + '.svn');
    RemoveDir(mFolder + PathDelim + 'src');
    RemoveDir(mFolder);
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
    TAtlasVcsSwitches.Compare(TAtlasVcsHead.Empty, MakeHead('main', cHash1, False)), 'ohne alten Stand');
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None,
    TAtlasVcsSwitches.Compare(MakeHead('main', cHash1, False), MakeHead('main', cHash1, False)));
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Branch,
    TAtlasVcsSwitches.Compare(MakeHead('main', cHash1, False), MakeHead('feature/x', cHash1, False)), 'git checkout ohne neuen Commit');
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Revision,
    TAtlasVcsSwitches.Compare(MakeHead('main', cHash1, False), MakeHead('main', cHash2, False)), 'Commit oder Pull');
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Branch,
    TAtlasVcsSwitches.Compare(MakeHead('main', cHash1, False), MakeHead('', cHash1, True)), 'losgelöster HEAD');
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Revision,
    TAtlasVcsSwitches.Compare(MakeHead('trunk', '41', False), MakeHead('trunk', '42', False)), 'svn update');
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Branch,
    TAtlasVcsSwitches.Compare(MakeHead('trunk', '42', False), MakeHead('branches/x', '42', False)), 'svn switch');
  Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Revision,
    TAtlasVcsSwitches.Compare(MakeHead('main', '', False), MakeHead('main', cHash1, False)), 'erster Commit');
end;
procedure TAtlasVcsTests.WatchAsksOnlyWhenMarkerChanges;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mWatch: TAtlasVcsWatch;
begin
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.Marker := 'm1';
  mFake.Current := MakeHead('main', cHash1, False);
  mWatch := TAtlasVcsWatch.Create(mVcs);
  try
    Assert.IsFalse(mWatch.Known);
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None, mWatch.Check, 'erster Stand');
    Assert.IsTrue(mWatch.Known);
    Assert.AreEqual('main', mWatch.Head.Branch);
    Assert.AreEqual(1, mFake.HeadCalls);
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None, mWatch.Check);
    Assert.AreEqual(1, mFake.HeadCalls, 'Marke unverändert: kein Prozess');
    mFake.Marker := 'm2';
    mFake.Current := MakeHead('feature/x', cHash1, False);
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Branch, mWatch.Check);
    Assert.AreEqual(2, mFake.HeadCalls);
    mFake.Marker := 'm3';
    mFake.Current := MakeHead('feature/x', cHash2, False);
    mFake.HeadOutcome := TAtlasVcsOutcome.TimedOut;
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None, mWatch.Check, 'keine Antwort: alter Stand bleibt');
    Assert.AreEqual('feature/x', mWatch.Head.Branch);
    mFake.HeadOutcome := TAtlasVcsOutcome.Ok;
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.Revision, mWatch.Check, 'beim nächsten Mal erkannt');
    mFake.Marker := '';
    Assert.AreEqual<TAtlasVcsSwitch>(TAtlasVcsSwitch.None, mWatch.Check);
    Assert.AreEqual(5, mFake.HeadCalls, 'ohne Marke wird jedes Mal gefragt');
  finally
    mWatch.Free;
  end;
end;
procedure TAtlasVcsTests.GitChangeMarkerFollowsHeadAndBranch;
var
  mFolder, mBefore: string;
  mVcs: IAtlasVersionControl;
  mRunnerRef: IAtlasVcsRunner;
begin
  mRunnerRef := TFakeRunner.Create;
  mFolder := TempFolder('marker');
  ForceDirectories(mFolder + PathDelim + '.git' + PathDelim + 'refs' + PathDelim + 'heads');
  WriteText(mFolder + PathDelim + '.git' + PathDelim + 'HEAD', 'ref: refs/heads/main'#10);
  WriteText(mFolder + PathDelim + '.git' + PathDelim + 'refs' + PathDelim + 'heads' + PathDelim + 'main', cHash1 + #10);
  try
    mVcs := TAtlasGitVersionControl.Create(mFolder, mRunnerRef, 'git.exe');
    mBefore := mVcs.ChangeMarker;
    Assert.Contains(mBefore, 'ref: refs/heads/main');
    Assert.IsTrue(Pos(cHash1, mBefore) > 0, 'Commit des Branchs');
    Assert.AreEqual(mBefore, mVcs.ChangeMarker, 'stabil ohne Änderung');
    WriteText(mFolder + PathDelim + '.git' + PathDelim + 'refs' + PathDelim + 'heads' + PathDelim + 'main',
      cHash2 + #10);
    Assert.AreNotEqual(mBefore, mVcs.ChangeMarker, 'neuer Commit');
    // Worktree bzw. Submodul: .git ist eine Datei mit gitdir.
    Assert.AreEqual(mFolder + PathDelim + '.git', TAtlasGitVersionControl.GitDir(mFolder));
    Assert.AreEqual('', TAtlasGitVersionControl.GitDir(mFolder + PathDelim + 'fehlt'));
  finally
    DeleteFile(mFolder + PathDelim + '.git' + PathDelim + 'refs' + PathDelim + 'heads' + PathDelim + 'main');
    DeleteFile(mFolder + PathDelim + '.git' + PathDelim + 'HEAD');
    RemoveDir(mFolder + PathDelim + '.git' + PathDelim + 'refs' + PathDelim + 'heads');
    RemoveDir(mFolder + PathDelim + '.git' + PathDelim + 'refs');
    RemoveDir(mFolder + PathDelim + '.git');
    RemoveDir(mFolder);
  end;
end;
procedure TAtlasVcsTests.WorkerReportsWhetherItStarted;
var
  mWorker: TAtlasVcsWorker;
  mDone: Boolean;
  mDeadline: UInt64;
begin
  // #592: Ohne Start kommt kein Ergebnis; der Aufrufer muss das wissen, sonst bleibt „wird abgefragt …“.
  mDone := False;
  mWorker := TAtlasVcsWorker.Create;
  try
    Assert.IsTrue(mWorker.Run(
      procedure
      begin
      end,
      procedure
      begin
        mDone := True;
      end));
    mDeadline := TThread.GetTickCount64 + 5000;
    while not mDone and (TThread.GetTickCount64 < mDeadline) do
    begin
      CheckSynchronize(10);
    end;
    Assert.IsTrue(mDone);
    mWorker.Stop(1000);
    Assert.IsFalse(mWorker.Run(
      procedure
      begin
      end,
      procedure
      begin
      end));
  finally
    mWorker.Free;
  end;
end;
procedure TAtlasVcsTests.GitProviderRunsLocalWorkCommands;
const
  cPrefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
var
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mLocal: IAtlasVcsLocalWork;
  mBranches: TArray<TAtlasVcsBranch>;
  mStashes: TArray<TAtlasVcsStash>;
  mCommits: TArray<TAtlasVcsCommit>;
  mChanges: TArray<TAtlasVcsChange>;
  mNames: TArray<string>;
begin
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  mRunner.Answer('for-each-ref', 'main'#0'origin/main'#0'origin'#0'refs/heads/main'#0'ahead 1'#0'1792071092'#0'*'#10);
  mRunner.Answer('stash', cHash1 + #0'1792071092'#0'stash@{0}'#0'On main: X'#10);
  mRunner.Answer('remote', 'origin'#10);
  mRunner.Answer('log', cHash2 + #0'1792071091'#0'eins'#10);
  mRunner.Answer('diff', 'M'#0'A.pas'#0);
  mVcs := TAtlasGitVersionControl.Create(Root, mRunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsLocalWork, mLocal), 'Git bietet IAtlasVcsLocalWork');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.Branches(mBranches));
  Assert.AreEqual(1, Integer(Length(mBranches)));
  Assert.AreEqual(cPrefix + 'for-each-ref --format=' + TAtlasGitParser.cBranchFormat + ' refs/heads', mRunner.Calls[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.Stashes(mStashes));
  Assert.AreEqual(cPrefix + 'stash list --format=' + TAtlasGitParser.cStashFormat, mRunner.Calls[1]);
  Assert.AreEqual('X', mStashes[0].Message);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.Remotes(mNames));
  Assert.AreEqual('origin', mNames[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.Outgoing('main', 'origin/main', 51, mCommits));
  Assert.AreEqual(cPrefix + 'log --format=' + TAtlasGitParser.cLogFormat + ' --max-count=51 refs/heads/main --not ' +
    'origin/main', mRunner.Calls[3], 'kein fetch: nur das lokale Repository');
  Assert.AreEqual('eins', mCommits[0].Summary);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.Outgoing('lokal', '', 0, mCommits));
  Assert.AreEqual(cPrefix + 'log --format=' + TAtlasGitParser.cLogFormat + ' --max-count=1 refs/heads/lokal --not ' +
    '--remotes', mRunner.Calls[4], 'ohne Upstream: auf keinem Remote');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.ChangesIn(cHash1, mChanges));
  Assert.AreEqual(cPrefix + 'diff --name-status -z --no-renames ' + cHash1 + '^1 ' + cHash1, mRunner.Calls[5]);
  Assert.AreEqual(Under('A.pas'), mChanges[0].Path);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.Push('main', 'origin', 'refs/heads/main', False));
  Assert.AreEqual(cPrefix + '-c credential.interactive=never -c core.askPass= push --porcelain origin ' +
    'refs/heads/main:refs/heads/main', mRunner.Calls[6], 'ohne Rückfrage nach Zugangsdaten (#1287)');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.Push('neu', 'origin', 'refs/heads/neu', True));
  Assert.AreEqual(cPrefix + '-c credential.interactive=never -c core.askPass= push --porcelain --set-upstream ' +
    'origin refs/heads/neu:refs/heads/neu', mRunner.Calls[7]);
  // Namen, die als Option gelesen würden, starten keinen Prozess.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mLocal.Outgoing('-x', '', 5, mCommits));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mLocal.Outgoing('main', '--all', 5, mCommits));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mLocal.ChangesIn('--output=x', mChanges));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mLocal.Push('main', '-f', 'refs/heads/main', False));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mLocal.Push('a b', 'origin', 'refs/heads/main', False));
  Assert.AreEqual(8, Integer(Length(mRunner.Calls)));
  // Exit-Code ungleich 0 (z. B. Push abgelehnt) = Failed.
  mRunner.ExitCode := 1;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mLocal.Push('main', 'origin', 'refs/heads/main', False));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mLocal.Branches(mBranches));
  Assert.AreEqual(0, Integer(Length(mBranches)));
end;
procedure TAtlasVcsTests.SvnAndNullLocalWork;
var
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mLocal: IAtlasVcsLocalWork;
  mBranches: TArray<TAtlasVcsBranch>;
  mStashes: TArray<TAtlasVcsStash>;
  mCommits: TArray<TAtlasVcsCommit>;
  mChanges: TArray<TAtlasVcsChange>;
  mNames: TArray<string>;
begin
  // SVN: keine lokalen Commits, Stashes oder Branches; kein Prozess.
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  mVcs := TAtlasSvnVersionControl.Create(Root, mRunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(mVcs, IAtlasVcsLocalWork, mLocal));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.Branches(mBranches));
  Assert.AreEqual(0, Integer(Length(mBranches)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.Stashes(mStashes));
  Assert.AreEqual(0, Integer(Length(mStashes)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.Remotes(mNames));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mLocal.Outgoing('trunk', '', 10, mCommits));
  Assert.AreEqual(0, Integer(Length(mCommits)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mLocal.ChangesIn('42', mChanges));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mLocal.Push('trunk', 'x', 'y', False));
  Assert.AreEqual(0, Integer(Length(mRunner.Calls)), 'kein Prozess');
  // Leere Umsetzung: Outcome sagt, warum.
  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsLocalWork, mLocal));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mLocal.Branches(mBranches));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mLocal.Stashes(mStashes));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mLocal.Remotes(mNames));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mLocal.Outgoing('main', '', 1, mCommits));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mLocal.ChangesIn('x', mChanges));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mLocal.Push('main', 'origin', 'refs/heads/main', False));
end;
procedure TAtlasVcsTests.GitProviderRunsIncomingCommands;
const
  cPrefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
var
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mIncoming: IAtlasVcsIncoming;
  mCommits: TArray<TAtlasVcsIncomingCommit>;
  mRevision: string;
begin
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  mRunner.Answer('rev-parse', cHash2 + #10);
  mRunner.Answer('log', #$1E + cHash1 + #0'1792071092'#0'Eva'#0'eins'#0#10'A.pas'#0);
  mRunner.Answer('fetch', '');
  mVcs := TAtlasGitVersionControl.Create(Root, mRunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsIncoming, mIncoming), 'Git bietet IAtlasVcsIncoming');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mIncoming.Resolve('origin/main', mRevision));
  Assert.AreEqual(cHash2, mRevision);
  Assert.AreEqual(cPrefix + 'rev-parse --verify --quiet origin/main^{commit}', mRunner.Calls[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    mIncoming.Incoming('origin/main', [cHash1, '', cHash2], 200, mCommits));
  Assert.AreEqual(cPrefix + 'log --format=' + TAtlasGitParser.cIncomingFormat + ' --name-only -z --no-renames ' +
    '--max-count=200 origin/main --not ' + cHash1 + ' ' + cHash2, mRunner.Calls[1], 'nur lokale Remote-Branches');
  Assert.AreEqual(1, Integer(Length(mCommits)));
  Assert.AreEqual(Under('A.pas'), mCommits[0].Files[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mIncoming.Fetch(''));
  Assert.AreEqual(cPrefix + '-c credential.interactive=never -c core.askPass= fetch --quiet --no-tags',
    mRunner.Calls[2], 'ohne Rückfrage nach Zugangsdaten');
  // Namen, die als Option gelesen würden, starten keinen Prozess.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mIncoming.Resolve('--all', mRevision));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mIncoming.Incoming('--all', nil, 5, mCommits));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mIncoming.Incoming('origin/main', ['-p'], 5, mCommits));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mIncoming.Fetch('--upload-pack=x'));
  Assert.AreEqual(3, Integer(Length(mRunner.Calls)));
  // SVN: kein lokaler Stand des Servers, kein Prozess; leere Umsetzung meldet ihren Grund.
  mVcs := TAtlasSvnVersionControl.Create(Root, mRunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(mVcs, IAtlasVcsIncoming, mIncoming));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mIncoming.Incoming('trunk', nil, 5, mCommits));
  Assert.AreEqual(0, Integer(Length(mCommits)));
  Assert.AreEqual(3, Integer(Length(mRunner.Calls)), 'SVN startet keinen Prozess');
  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsIncoming, mIncoming));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mIncoming.Fetch(''));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mIncoming.Incoming('origin/main', nil, 5, mCommits));
end;
procedure TAtlasVcsTests.ProvidersPullOnlyForward;
const
  cPrefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
var
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mUpdate: IAtlasVcsUpdate;
begin
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  mVcs := TAtlasGitVersionControl.Create(Root, mRunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsUpdate, mUpdate), 'Git bietet IAtlasVcsUpdate');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mUpdate.Pull);
  Assert.AreEqual(cPrefix + '-c credential.interactive=never -c core.askPass= pull --ff-only --no-rebase --quiet',
    mRunner.Calls[0], 'nur vorwärts, ohne Rückfrage nach Zugangsdaten');
  Assert.AreEqual(Root, mRunner.WorkingDirs[0], 'in der Wurzel der Arbeitskopie');
  // Abweichender Branch: git endet mit Fehler, nichts wird zusammengeführt.
  mRunner.ExitCode := 128;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mUpdate.Pull);
  // Fehlende Anmeldung (#1287): eigenes Ergebnis statt still „Failed“.
  mRunner.ErrorText := 'fatal: Authentication failed for ''https://example.com/kasse.git/''';
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.LoginNeeded, mUpdate.Pull);
  mRunner.ErrorText := '';
  mRunner.ExitCode := 0;
  mVcs := TAtlasSvnVersionControl.Create(Root, mRunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(mVcs, IAtlasVcsUpdate, mUpdate), 'SVN bietet IAtlasVcsUpdate');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mUpdate.Pull);
  Assert.AreEqual('update . --non-interactive', mRunner.Calls[3]);
  mRunner.ExitCode := 1;
  mRunner.ErrorText := 'svn: E170001: Authorization failed';
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.LoginNeeded, mUpdate.Pull);
  mRunner.ErrorText := '';
  mRunner.ExitCode := 0;
  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.ToolMissing);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsUpdate, mUpdate));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.ToolMissing, mUpdate.Pull);
  Assert.AreEqual(5, Integer(Length(mRunner.Calls)), 'die leere Umsetzung startet keinen Prozess');
end;
/// <summary>Git: Branch prüfen, anlegen, wechseln, Hook-Ordner; unsichere Namen ohne Prozess.</summary>
procedure AssertGitBranching(ARunner: TFakeRunner; const ARunnerRef: IAtlasVcsRunner);
const
  cPrefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
  cRemotePrefix = cPrefix + '-c credential.interactive=never -c core.askPass= ';
var
  mVcs: IAtlasVersionControl;
  mBranching: IAtlasVcsBranching;
  mExists, mHas: Boolean;
  mHooks, mGitDir, mRevision: string;
  mSteps: TArray<TAtlasVcsBranchStep>;
begin
  ARunner.Answer('for-each-ref',
    'refs/heads/feature/753-atlas-bereiche-und' + #10 + 'refs/remotes/origin/develop' + #10);
  ARunner.Answer('rev-parse', '.git/hooks' + #10 + '.git' + #10);
  mVcs := TAtlasGitVersionControl.Create(Root, ARunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsBranching, mBranching), 'Git bietet IAtlasVcsBranching');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    mBranching.BranchExists('feature/753-atlas-bereiche-und', mExists));
  Assert.IsTrue(mExists, 'vorhandener Branch');
  Assert.AreEqual(cPrefix + 'for-each-ref --format=%(refname) refs/heads/feature/753-atlas-bereiche-und',
    ARunner.Calls[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.BranchExists('feature/1-neu', mExists));
  Assert.IsFalse(mExists, 'ein ähnlicher Ref zählt nicht');
  // Remote-Branch im lokalen Stand (#1288), ohne fetch.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.RemoteBranchExists('develop', mExists));
  Assert.IsTrue(mExists);
  Assert.AreEqual(cPrefix + 'for-each-ref --format=%(refname) refs/remotes/origin/develop', ARunner.Calls[2]);
  // Schritte aus dem Plan: lokal mit den festen Optionen, mit Remote zusätzlich ohne Rückfrage.
  mSteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/9-neu',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.RemoteMain, 'develop', ''), 'egal'));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.RunStep(mSteps[0]));
  Assert.AreEqual(cPrefix + 'checkout --quiet --no-track -b feature/9-neu refs/remotes/origin/develop --',
    ARunner.Calls[3]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    mBranching.RunStep(TAtlasVcsBranchStep.Make(TArray<string>.Create('push', '-u', 'origin',
    'feature/9-neu'), True, True)));
  Assert.AreEqual(cRemotePrefix + 'push -u origin feature/9-neu', ARunner.Calls[4]);
  // Git: keine Serverrevision, keine Externals, ohne Prozess.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.ServerRevision('main', mRevision));
  Assert.AreEqual('', mRevision);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.HasExternals(mHas));
  Assert.IsFalse(mHas);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.RepositoryPath(mRevision));
  Assert.AreEqual('', mRevision);
  Assert.AreEqual(5, Integer(Length(ARunner.Calls)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.SwitchBranch('feature/753-atlas-bereiche-und'));
  Assert.AreEqual(cPrefix + 'checkout --quiet feature/753-atlas-bereiche-und --', ARunner.Calls[5]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.HookFolders(mHooks, mGitDir));
  Assert.AreEqual(cPrefix + 'rev-parse --git-path hooks --git-dir', ARunner.Calls[6]);
  Assert.AreEqual(Under('.git/hooks'), mHooks, 'relativ zur Wurzel aufgelöst');
  Assert.AreEqual(Under('.git'), mGitDir);
  // Unsichere Namen und leere Schritte starten keinen Prozess.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mBranching.SwitchBranch('a..b'));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mBranching.RemoteBranchExists('-x', mExists));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mBranching.RunStep(Default(TAtlasVcsBranchStep)));
  Assert.AreEqual(7, Integer(Length(ARunner.Calls)));
  // Git endet mit Fehler (Branch gibt es schon, Konflikt beim Wechsel): Failed.
  ARunner.ExitCode := 128;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mBranching.SwitchBranch('feature/1-neu'));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mBranching.RunStep(mSteps[0]));
  ARunner.ExitCode := 0;
end;
/// <summary>SVN: Kopie im Repository und switch, Serverrevision, Externals, Pfad im Repository.</summary>
procedure AssertSvnBranching(ARunner: TFakeRunner; const ARunnerRef: IAtlasVcsRunner;
  out ASteps: TArray<TAtlasVcsBranchStep>);
var
  mVcs: IAtlasVersionControl;
  mBranching: IAtlasVcsBranching;
  mExists, mHas: Boolean;
  mHooks, mGitDir, mRevision: string;
begin
  // SVN: Kopie im Repository und switch, beide mit dem Server und --non-interactive.
  mVcs := TAtlasSvnVersionControl.Create(Root, ARunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(mVcs, IAtlasVcsBranching, mBranching), 'SVN bietet IAtlasVcsBranching');
  ARunner.Calls := nil;
  ASteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Svn, 'ATL-123-tracker-im-plugin',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Head, 'trunk', ''), 'ATL-123 Branch'));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.RunStep(ASteps[0]));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.RunStep(ASteps[1]));
  Assert.AreEqual('copy ^/trunk@ ^/branches/ATL-123-tracker-im-plugin@ --parents -m ATL-123 Branch --non-interactive',
    ARunner.Calls[0]);
  Assert.AreEqual('switch ^/branches/ATL-123-tracker-im-plugin@ . --non-interactive', ARunner.Calls[1]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.BranchExists('ATL-123-tracker-im-plugin', mExists));
  Assert.IsTrue(mExists);
  Assert.AreEqual('info ^/branches/ATL-123-tracker-im-plugin@ --non-interactive', ARunner.Calls[2]);
  // HEAD-Revision vom Server und Externals der Arbeitskopie (#1288).
  ARunner.Answer('info', '48230' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.ServerRevision('Kasse/trunk', mRevision));
  Assert.AreEqual('48230', mRevision);
  Assert.AreEqual('info --show-item revision --non-interactive ^/Kasse/trunk@', ARunner.Calls[3]);
  ARunner.Answer('propget', 'Libs - ^/Libs/Common/trunk Common' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.HasExternals(mHas));
  Assert.IsTrue(mHas);
  Assert.AreEqual('propget svn:externals -R . --non-interactive', ARunner.Calls[4]);
  ARunner.Answer('info', '^/Kasse/trunk' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.RepositoryPath(mRevision));
  Assert.AreEqual('Kasse/trunk', mRevision, 'voller Pfad ohne ^/');
  Assert.AreEqual('info --show-item relative-url . --non-interactive', ARunner.Calls[5]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.RemoteBranchExists('trunk', mExists));
  Assert.IsFalse(mExists, 'SVN kennt keine Remote-Branches');
  Assert.AreEqual(6, Integer(Length(ARunner.Calls)), 'ohne Prozess');
  // Fehlt der Branch, endet svn info mit Fehler: das ist die Antwort.
  ARunner.ExitCode := 1;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.BranchExists('ATL-9-neu', mExists));
  Assert.IsFalse(mExists);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mBranching.ServerRevision('trunk', mRevision));
  Assert.AreEqual('', mRevision);
  ARunner.ExitCode := 0;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.HookFolders(mHooks, mGitDir));
  Assert.AreEqual('', mHooks);
  Assert.AreEqual(8, Integer(Length(ARunner.Calls)), 'Hooks ohne Prozess');
end;
procedure TAtlasVcsTests.ProvidersCreateIssueBranches;
var
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mBranching: IAtlasVcsBranching;
  mExists: Boolean;
  mRevision: string;
  mSteps: TArray<TAtlasVcsBranchStep>;
begin
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  AssertGitBranching(mRunner, mRunnerRef);
  AssertSvnBranching(mRunner, mRunnerRef, mSteps);

  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsBranching, mBranching));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mBranching.RunStep(mSteps[0]));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mBranching.BranchExists('feature/1-x', mExists));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mBranching.ServerRevision('trunk', mRevision));
  Assert.AreEqual(8, Integer(Length(mRunner.Calls)), 'die leere Umsetzung startet keinen Prozess');
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
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mBranching: IAtlasVcsBranching;
  mSvn: IAtlasVcsSvnWorkingCopy;
  mOptions: TAtlasVcsSvnBranchOptions;
  mExists: Boolean;
  mText: string;
begin
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  mVcs := TAtlasSvnVersionControl.Create(Root, mRunnerRef, Under('bin/svn.exe'));
  Assert.IsTrue(Supports(mVcs, IAtlasVcsBranching, mBranching));
  // Vorgabe {projektwurzel}/branches/{name}: in ^/Kasse/trunk sucht und schaltet Atlas unter ^/Kasse/branches.
  mRunner.Answer('info', '^/Kasse/trunk' + #10);
  mOptions := TAtlasVcsSvnBranchOptions.Default;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.BranchExists('KASSE-42-bon', mOptions, mExists));
  Assert.IsTrue(mExists);
  Assert.AreEqual(2, Integer(Length(mRunner.Calls)));
  Assert.AreEqual('info --show-item relative-url . --non-interactive', mRunner.Calls[0]);
  Assert.AreEqual('info ^/Kasse/branches/KASSE-42-bon@ --non-interactive', mRunner.Calls[1]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.SwitchBranch('KASSE-42-bon', mOptions));
  Assert.AreEqual(4, Integer(Length(mRunner.Calls)));
  Assert.AreEqual('switch ^/Kasse/branches/KASSE-42-bon@ . --non-interactive', mRunner.Calls[3]);
  Assert.AreEqual(Cardinal(TAtlasVcsBranchStep.cLongTimeoutMs), mRunner.Timeouts[3], 'switch mit langem Zeitlimit');
  Assert.AreEqual(Cardinal(TAtlasVcsCommand.cDefaultTimeoutMs), mRunner.Timeouts[1], 'info mit dem üblichen');
  AssertSvnBranchLocations(mRunner, mBranching, mOptions);
  // svnversion liegt neben svn und spricht nicht mit dem Server.
  Assert.IsTrue(Supports(mVcs, IAtlasVcsSvnWorkingCopy, mSvn));
  mRunner.Answer('.', '48190:48213M' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mSvn.WorkingRevisions(mText));
  Assert.AreEqual('48190:48213M', mText);
  Assert.AreEqual(Under('bin/svnversion.exe'), mRunner.Executables[High(mRunner.Executables)]);
  Assert.AreEqual('.', mRunner.Calls[High(mRunner.Calls)]);
  // Git und die leere Umsetzung kennen keine SVN-Revisionen; die Optionen gelten dort nicht.
  mVcs := TAtlasGitVersionControl.Create(Root, mRunnerRef, 'git.exe');
  Assert.IsFalse(Supports(mVcs, IAtlasVcsSvnWorkingCopy));
  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsFalse(Supports(mVcs, IAtlasVcsSvnWorkingCopy));
  Assert.IsTrue(Supports(mVcs, IAtlasVcsBranching, mBranching));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled,
    mBranching.BranchExists('x', TAtlasVcsSvnBranchOptions.Default, mExists));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled,
    mBranching.SwitchBranch('x', TAtlasVcsSvnBranchOptions.Default));
  mRunner.Calls := nil;
  mRunner.Executables := nil;
  mRunner.Timeouts := nil;
  mRunner.WorkingDirs := nil;
  mRunner.Commands := nil;
  mRunner.Answers := nil;
end;
procedure TAtlasVcsTests.SvnExternalsCommands;
var
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mBranching: IAtlasVcsBranching;
  mSvn: IAtlasVcsSvnWorkingCopy;
  mText, mFile: string;
  mStep: TAtlasVcsBranchStep;
  mBytes: TBytes;
begin
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  mVcs := TAtlasSvnVersionControl.Create(Root, mRunnerRef, Under('bin/svn.exe'));
  Assert.IsTrue(Supports(mVcs, IAtlasVcsSvnWorkingCopy, mSvn));
  Assert.IsTrue(Supports(mVcs, IAtlasVcsBranching, mBranching));
  mRunner.Answer('propget', '<properties/>');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mSvn.ExternalsXml(mText));
  Assert.AreEqual('<properties/>', mText);
  Assert.AreEqual('propget svn:externals --xml -R . --non-interactive', mRunner.Calls[0]);
  mRunner.Answer('info', 'https://svn.firma.local/repo' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mSvn.RepositoryRoot(mText));
  Assert.AreEqual('https://svn.firma.local/repo', mText);
  Assert.AreEqual('info --show-item repos-root-url . --non-interactive', mRunner.Calls[1]);
  // Nur Schalter: Der Fake erkennt keinen Befehl ('').
  mRunner.Answer('', '1.14.3' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mSvn.ToolVersion(mText));
  Assert.AreEqual('1.14.3', mText);
  Assert.AreEqual('--version --quiet', mRunner.Calls[2]);
  mRunner.Answer('Packages/Basis', '48190M' + #10);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mSvn.WorkingRevisions('Packages/Basis', mText));
  Assert.AreEqual('48190M', mText);
  Assert.AreEqual(Under('bin/svnversion.exe'), mRunner.Executables[3]);
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
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mBranching.RunStep(mStep));
  mBytes := TFile.ReadAllBytes(mFile);
  Assert.AreEqual('-r 1 ^/a Lib'#10'# ä'#10, TEncoding.UTF8.GetString(mBytes));
  Assert.IsFalse((Length(mBytes) >= 3) and (mBytes[0] = $EF), 'ohne BOM');
  Assert.AreEqual('propset svn:externals -F ' + mFile + ' p0 --non-interactive', mRunner.Calls[High(mRunner.Calls)]);
  TDirectory.Delete(ExtractFileDir(mFile), True);
  mStep := TAtlasVcsBranchStep.Make(nil, False, False);
  mBytes := nil;
  mRunner.Calls := nil;
  mRunner.Executables := nil;
  mRunner.Timeouts := nil;
  mRunner.WorkingDirs := nil;
  mRunner.Commands := nil;
  mRunner.Answers := nil;
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
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mExternals: IAtlasVcsSvnExternals;
  mText, mFile: string;
  mCount: Integer;
begin
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  mVcs := TAtlasSvnVersionControl.Create(Root, mRunnerRef, Under('bin/svn.exe'));
  Assert.IsTrue(Supports(mVcs, IAtlasVcsSvnExternals, mExternals));
  Assert.IsFalse(Supports(mVcs, IAtlasVcsSubmodules), 'SVN kennt keine Submodule');
  mRunner.Answer('status', '<status/>');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mExternals.StatusXml(mText));
  Assert.AreEqual('<status/>', mText);
  Assert.AreEqual('status --xml . --non-interactive', mRunner.Calls[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mExternals.Update(False));
  Assert.AreEqual('update . --non-interactive', mRunner.Calls[1]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mExternals.Update(True));
  Assert.AreEqual('update . --ignore-externals --non-interactive', mRunner.Calls[2]);
  // HEAD:4711 enthält 4711 selbst, wenn sie den Pfad geändert hat.
  mRunner.Answer('log', '<?xml version="1.0"?><log><logentry revision="4790"></logentry>' +
    '<logentry revision="4750"></logentry><logentry revision="4711"></logentry></log>');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    mExternals.CommitsSince('Packages/Kunden/trunk', '4711', mCount));
  Assert.AreEqual(2, mCount);
  Assert.AreEqual('log -q --xml -r HEAD:4711 ^/Packages/Kunden/trunk@HEAD --non-interactive', mRunner.Calls[3]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed,
    mExternals.CommitsSince('Packages/Kunden/trunk', 'HEAD', mCount));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mExternals.CommitsSince('-r1', '4711', mCount));
  Assert.AreEqual(4, Integer(Length(mRunner.Calls)), 'ungültig ohne Aufruf');
  mRunner.Answer('log', '<log><logentry');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed,
    mExternals.CommitsSince('Packages/Kunden/trunk', '4711', mCount));
  Assert.AreEqual(0, mCount);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    mExternals.SetExternals('', '-r 4711 ^/Packages/Kunden/trunk Packages/Kunden'#10));
  mText := mRunner.Calls[High(mRunner.Calls)];
  Assert.IsTrue(mText.StartsWith('propset svn:externals -F '), mText);
  Assert.IsTrue(mText.EndsWith(' . --non-interactive'), mText);
  mFile := Copy(mText, Length('propset svn:externals -F ') + 1, Length(mText));
  mFile := Copy(mFile, 1, Length(mFile) - Length(' . --non-interactive'));
  Assert.IsFalse(TFile.Exists(mFile), 'Temp-Datei wieder entfernt');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mExternals.SetExternals('Packages', '^/x Lib'));
  Assert.IsTrue(mRunner.Calls[High(mRunner.Calls)].EndsWith(' Packages --non-interactive'));
  mExternals := nil;
  AssertGitSubmodules(mRunner, mRunnerRef);
  mText := '';
  mFile := '';
  mRunner.Calls := nil;
  mRunner.Executables := nil;
  mRunner.Timeouts := nil;
  mRunner.WorkingDirs := nil;
  mRunner.Commands := nil;
  mRunner.Answers := nil;
end;
/// <summary>worktree: eigener Ordner statt stash und checkout; Push an den Remote des Hauptbranchs.</summary>
procedure AssertGitWorktreeBranch(ARunner: TFakeRunner; const ABranching: IAtlasVcsBranching);
const
  cPrefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
  cRemotePrefix = cPrefix + '-c credential.interactive=never -c core.askPass= ';
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
  Assert.AreEqual(cPrefix + 'worktree add --quiet --no-track -b ATL-9-neu ' + mFolder + ' refs/heads/main',
    ARunner.Calls[0]);
  Assert.AreEqual(cRemotePrefix + 'push --set-upstream upstream refs/heads/ATL-9-neu:refs/heads/ATL-9-neu',
    ARunner.Calls[1]);
end;
procedure TAtlasVcsTests.ProvidersRunGitBranchOptions;
const
  cPrefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
  cRemotePrefix = cPrefix + '-c credential.interactive=never -c core.askPass= ';
var
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mBranching: IAtlasVcsBranching;
  mRequest: TAtlasVcsBranchRequest;
  mSteps: TArray<TAtlasVcsBranchStep>;
  mRun: TAtlasVcsBranchRun;
begin
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  mVcs := TAtlasGitVersionControl.Create(Root, mRunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsBranching, mBranching));
  // Basis vom Server, vorher beiseitelegen, sofort pushen.
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/9-neu',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.RemoteMain, 'main', '', 'origin'), '');
  mRequest.Fetch := True;
  mRequest.Stash := True;
  mRequest.PushNow := True;
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, mSteps);
  Assert.IsTrue(mRun.Succeeded);
  Assert.AreEqual(4, Integer(Length(mRunner.Calls)));
  Assert.AreEqual(cRemotePrefix + 'fetch --quiet --no-tags origin main', mRunner.Calls[0]);
  Assert.AreEqual(cPrefix + 'stash push --include-untracked --quiet -m Atlas: vor feature/9-neu', mRunner.Calls[1]);
  Assert.AreEqual(cPrefix + 'checkout --quiet --no-track -b feature/9-neu refs/remotes/origin/main --',
    mRunner.Calls[2]);
  Assert.AreEqual(cRemotePrefix + 'push --set-upstream origin refs/heads/feature/9-neu:refs/heads/feature/9-neu',
    mRunner.Calls[3]);
  Assert.AreEqual(Root, mRunner.WorkingDirs[3], 'alles in der Wurzel der Arbeitskopie');
  // Ohne Anmeldung: LoginNeeded beim Abruf, danach nichts.
  mRunner.Calls := nil;
  mRunner.ExitCode := 128;
  mRunner.ErrorText := 'fatal: Authentication failed for ''https://example.com/kasse.git/''';
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, mSteps);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.LoginNeeded, mRun.Outcome);
  Assert.IsTrue(TAtlasVcsBranchPlan.FetchFailed(mSteps, mRun));
  Assert.AreEqual(1, Integer(Length(mRunner.Calls)));
  mRunner.ErrorText := '';
  mRunner.ExitCode := 0;
  AssertGitWorktreeBranch(mRunner, mBranching);
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
  mVcs: IAtlasVersionControl;
  mHistory: IAtlasVcsHistory;
  mEntries: TArray<TAtlasVcsLogEntry>;
  mRefs: TArray<TAtlasVcsRef>;
  mContent: TBytes;
  mFileOf: TAtlasVcsLogFile;
  mAhead, mBehind: Integer;
begin
  // SVN: erst info (Pfad der Arbeitskopie), dann das ganze Repository.
  ARunner.Calls := nil;
  ARunner.Commands := nil;
  ARunner.Answers := nil;
  ARunner.Answer('info', StringReplace(cSvnInfoSample, 'projekt/branches/release-2', 'projekt/trunk',
    [rfReplaceAll]));
  ARunner.Answer('log', cSvnLogSample);
  ARunner.Answer('list', cSvnListSample);
  ARunner.Answer('cat', 'alt');
  mVcs := TAtlasSvnVersionControl.Create(Root, ARunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(mVcs, IAtlasVcsHistory, mHistory), 'SVN bietet IAtlasVcsHistory');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mHistory.SearchLog('ATL-12', 50, mEntries));
  Assert.AreEqual('info --xml . --non-interactive', ARunner.Calls[0]);
  Assert.AreEqual('log --xml -v --search ATL-12 -l 50 ^/ --non-interactive', ARunner.Calls[1]);
  Assert.AreEqual(Under('src/Main.pas'), mEntries[0].Files[0].Path);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mHistory.AllBranches(mRefs));
  Assert.AreEqual('list --xml ^/branches --non-interactive', ARunner.Calls[3]);
  Assert.AreEqual(2, Integer(Length(mRefs)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mHistory.Distance('ATL-12-tracker', 'trunk', mAhead, mBehind));
  Assert.AreEqual(-1, mAhead, 'SVN kennt keinen Vorsprung');
  Assert.AreEqual(4, Integer(Length(ARunner.Calls)), 'ohne Prozess');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mHistory.ContentOf('57', mEntries[0].Files[0], True, mContent));
  Assert.AreEqual('cat ^/projekt/branches/ATL-12-tracker/src/Main.pas@56 --non-interactive', ARunner.Calls[4]);
  Assert.AreEqual('alt', TEncoding.UTF8.GetString(mContent));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mHistory.ContentOf('57', mEntries[0].Files[1], False, mContent),
    'gelöscht: danach leer');
  Assert.AreEqual(5, Integer(Length(ARunner.Calls)));
  // Vorher merken: Das gescheiterte SearchLog leert Entries (out).
  mFileOf := mEntries[0].Files[0];
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mHistory.SearchLog('ATL-*', 50, mEntries), 'Glob-Zeichen');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mHistory.ContentOf('x', mFileOf, True, mContent));
  Assert.AreEqual(5, Integer(Length(ARunner.Calls)));
end;
procedure TAtlasVcsTests.ProvidersRunHistoryCommands;
const
  cPrefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
var
  mRunner: TFakeRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mHistory: IAtlasVcsHistory;
  mEntries: TArray<TAtlasVcsLogEntry>;
  mRefs: TArray<TAtlasVcsRef>;
  mContent: TBytes;
  mFileOf: TAtlasVcsLogFile;
  mAhead, mBehind: Integer;
begin
  mRunner := TFakeRunner.Create;
  mRunnerRef := mRunner;
  mRunner.Answer('log', cGitHistorySample);
  mRunner.Answer('for-each-ref', 'refs/heads/main'#0'1761600000'#0'*'#10);
  mRunner.Answer('rev-list', '0'#9'2'#10);
  mRunner.Answer('show', 'Inhalt');
  mVcs := TAtlasGitVersionControl.Create(Root, mRunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsHistory, mHistory), 'Git bietet IAtlasVcsHistory');
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mHistory.SearchLog('ATL-12', 200, mEntries));
  Assert.AreEqual(2, Integer(Length(mEntries)));
  Assert.AreEqual(cPrefix + 'log --all --fixed-strings --regexp-ignore-case --grep=ATL-12 ' +
    '--format=%x1e%H%x00%ct%x00%an%x00%B --name-status -z --no-renames --max-count=200', mRunner.Calls[0]);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok, mHistory.AllBranches(mRefs));
  Assert.AreEqual(cPrefix + 'for-each-ref --format=%(refname)%00%(committerdate:unix)%00%(HEAD) refs/heads refs/remotes',
    mRunner.Calls[1]);
  Assert.AreEqual(1, Integer(Length(mRefs)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    mHistory.Distance('feature/ATL-12-x', 'origin/main', mAhead, mBehind));
  Assert.AreEqual(cPrefix + 'rev-list --left-right --count origin/main...feature/ATL-12-x --', mRunner.Calls[2]);
  Assert.AreEqual(2, mAhead);
  Assert.AreEqual(0, mBehind);
  mFileOf := mEntries[0].Files[0];
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    mHistory.ContentOf(mEntries[0].Revision, mFileOf, True, mContent));
  Assert.AreEqual(cPrefix + 'show 28358feaf94440dbfe2fcc3aa2cb742e2d972f37^1:A.pas', mRunner.Calls[3]);
  Assert.AreEqual('Inhalt', TEncoding.UTF8.GetString(mContent));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    mHistory.ContentOf(mEntries[0].Revision, mFileOf, False, mContent));
  Assert.AreEqual(cPrefix + 'show 28358feaf94440dbfe2fcc3aa2cb742e2d972f37:A.pas', mRunner.Calls[4]);
  // Neue Datei davor, gelöschte danach: leer ohne Prozess.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    mHistory.ContentOf(mEntries[0].Revision, mEntries[0].Files[1], True, mContent));
  Assert.AreEqual(0, Integer(Length(mContent)));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Ok,
    mHistory.ContentOf(mEntries[0].Revision, mEntries[0].Files[2], False, mContent));
  Assert.AreEqual(5, Integer(Length(mRunner.Calls)));
  // Unsichere Eingaben starten keinen Prozess.
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mHistory.SearchLog('', 10, mEntries));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mHistory.SearchLog('a'#10'b', 10, mEntries));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mHistory.Distance('--all', 'main', mAhead, mBehind));
  Assert.AreEqual(-1, mAhead);
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mHistory.ContentOf('-x', mFileOf, False, mContent));
  Assert.AreEqual(5, Integer(Length(mRunner.Calls)));
  // Unlesbare Ausgabe: Failed statt Ausnahme.
  mRunner.Answers[0] := #$1E'kurz'#0;
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Failed, mHistory.SearchLog('ATL-12', 10, mEntries));
  Assert.AreEqual(0, Integer(Length(mEntries)));

  AssertSvnHistory(mRunner, mRunnerRef);

  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsHistory, mHistory));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mHistory.SearchLog('ATL-12', 50, mEntries));
  Assert.AreEqual<TAtlasVcsOutcome>(TAtlasVcsOutcome.Disabled, mHistory.AllBranches(mRefs));
  Assert.AreEqual(5, Integer(Length(mRunner.Calls)), 'die leere Umsetzung startet keinen Prozess');
end;
initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsTests);

end.
