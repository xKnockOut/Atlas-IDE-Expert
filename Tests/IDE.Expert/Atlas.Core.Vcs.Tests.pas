unit Atlas.Core.Vcs.Tests;

// Versionsverwaltung über eine gemeinsame Schnittstelle (#571), ohne git und
// svn: Parser mit aufgezeichneten Ausgaben (git 2.43, svn 1.14), Umsetzungen
// mit einem Prozessläufer-Ersatz, Erkennen der Arbeitskopie, Auswahl nach
// vcs.provider, einmalige Meldung bei fehlendem Programm und Wechsel-
// erkennung; eingehende Commits mit Autor und Dateien und die Aufrufe
// dafür (#755). Die Tests mit echtem git bzw. svn stehen in
// Atlas.Core.Vcs.Integration.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
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
    procedure GitStatusReadsBranchCommitAndChanges;
    [Test]
    procedure GitStatusReadsUpstreamDetachedAndInitial;
    [Test]
    procedure GitStatusReadsConflictsAndRejectsUnknown;
    [Test]
    procedure GitBlameReadsCommitsAndUncommittedLines;
    [Test]
    procedure SvnInfoReadsRootPathAndRevision;
    [Test]
    procedure SvnBranchFromRepositoryPath;
    [Test]
    procedure SvnStatusReadsChanges;
    [Test]
    procedure SvnBlameReadsLines;
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
    procedure GitParsesBranchesStashesLogAndNameStatus;
    [Test]
    procedure GitParserRejectsBrokenLocalWork;
    [Test]
    procedure GitProviderRunsLocalWorkCommands;
    [Test]
    procedure SvnAndNullLocalWork;
    [Test]
    procedure GitIncomingParsesCommitsWithFiles;
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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Internals.Text,
  Atlas.Core.Vcs.Internals.GitParser,
  Atlas.Core.Vcs.Internals.SvnParser,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.Detection,
  Atlas.Core.Vcs.Switches,
  Atlas.Core.Vcs.Providers.Git,
  Atlas.Core.Vcs.Providers.Svn,
  Atlas.Core.Vcs.Providers.Null,
  Atlas.Core.Vcs.Composition,
  Atlas.Core.Vcs.BranchPlan,
  Atlas.Core.Vcs.Worker;

const
  Hash1 = '1979e3d795214220705682d5b0b63c8f3b7e66d7';
  Hash2 = '35b70b0b58543816b60892fa1b872449fdc3886b';

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

function Root: string;
begin
  if PathDelim = '\' then
    Result := 'C:\Projekte\Kunde'
  else
    Result := '/projekte/kunde';
end;

function Under(const ARelative: string): string;
begin
  Result := Root + PathDelim + StringReplace(ARelative, '/', PathDelim, [rfReplaceAll]);
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
      AfterC := False
    else if AArguments[Index] = '-c' then
      AfterC := True
    else if Copy(AArguments[Index], 1, 1) <> '-' then
    begin
      Command := AArguments[Index];
      Break;
    end;
  end;
  Result := TAtlasVcsRunResult.Make(Outcome, ExitCode, nil);
  Result.ErrorText := ErrorText;
  for Index := 0 to High(Commands) do
    if Commands[Index] = Command then
      Result.Output := Utf8Bytes(Answers[Index]);
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

function GitStatusSample: string;
begin
  // Aufgezeichnet mit git 2.43: "git status --porcelain=v2 --branch -z --untracked-files=all" nach
  // git mv B.pas C.pas, Änderung an A.pas, gelöschter Datei mit Umlaut und Leerzeichen und zwei neuen Dateien.
  Result :=
    '# branch.oid ' + Hash1 + #0 +
    '# branch.head main' + #0 +
    '1 .M N... 100644 100644 100644 ' + Hash2 + ' ' + Hash2 + ' A.pas' + #0 +
    '2 R. N... 100644 100644 100644 587be6b4c3f93f93c489c0111bba5596147a26cb ' +
    '587be6b4c3f93f93c489c0111bba5596147a26cb R100 C.pas' + #0 + 'B.pas' + #0 +
    '1 .D N... 100644 100644 000000 975fbec8256d3e8a3797e7a3611380f27c49f4ac ' +
    '975fbec8256d3e8a3797e7a3611380f27c49f4ac ' + #$00DC + ' m.pas' + #0 +
    '? Neu.pas' + #0 +
    '? sub/Q.pas' + #0;
end;

const
  SvnInfoSample =
    '<?xml version="1.0" encoding="UTF-8"?>'#10 +
    '<info>'#10 +
    '<entry'#10 +
    '   kind="dir"'#10 +
    '   path="."'#10 +
    '   revision="42">'#10 +
    '<url>https://svn.example.org/repo/projekt/branches/release-2</url>'#10 +
    '<relative-url>^/projekt/branches/release-2</relative-url>'#10 +
    '<repository>'#10 +
    '<root>https://svn.example.org/repo</root>'#10 +
    '<uuid>0c8d5a9e-3f1b-4e7a-9b2c-7d6e5f4a3b2c</uuid>'#10 +
    '</repository>'#10 +
    '<wc-info>'#10 +
    '<wcroot-abspath>C:/Projekte/Kunde</wcroot-abspath>'#10 +
    '<schedule>normal</schedule>'#10 +
    '<depth>infinity</depth>'#10 +
    '</wc-info>'#10 +
    '<commit'#10 +
    '   revision="40">'#10 +
    '<author>marco</author>'#10 +
    '<date>2026-10-01T08:00:00.000000Z</date>'#10 +
    '</commit>'#10 +
    '</entry>'#10 +
    '</info>'#10;

  SvnStatusSample =
    '<?xml version="1.0" encoding="UTF-8"?>'#10 +
    '<status>'#10 +
    '<target'#10 +
    '   path=".">'#10 +
    '<entry'#10 +
    '   path="src\Main.pas">'#10 +
    '<wc-status'#10 +
    '   props="none"'#10 +
    '   item="modified"'#10 +
    '   revision="42">'#10 +
    '<commit'#10 +
    '   revision="40">'#10 +
    '<author>marco</author>'#10 +
    '<date>2026-10-01T08:00:00.000000Z</date>'#10 +
    '</commit>'#10 +
    '</wc-status>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   path="src\Neu &amp; Alt.pas">'#10 +
    '<wc-status'#10 +
    '   props="none"'#10 +
    '   item="added"'#10 +
    '   revision="-1">'#10 +
    '</wc-status>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   path="notizen.txt">'#10 +
    '<wc-status'#10 +
    '   props="none"'#10 +
    '   item="unversioned">'#10 +
    '</wc-status>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   path="build">'#10 +
    '<wc-status'#10 +
    '   props="none"'#10 +
    '   item="ignored">'#10 +
    '</wc-status>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   path="res\Logo.png">'#10 +
    '<wc-status'#10 +
    '   props="modified"'#10 +
    '   item="normal"'#10 +
    '   revision="42">'#10 +
    '</wc-status>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   path="alt.pas">'#10 +
    '<wc-status'#10 +
    '   props="none"'#10 +
    '   item="deleted"'#10 +
    '   revision="42"/>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   path="weg.pas">'#10 +
    '<wc-status'#10 +
    '   props="none"'#10 +
    '   item="missing"'#10 +
    '   revision="42"/>'#10 +
    '</entry>'#10 +
    '</target>'#10 +
    '</status>'#10;

  SvnBlameSample =
    '<?xml version="1.0" encoding="UTF-8"?>'#10 +
    '<blame>'#10 +
    '<target'#10 +
    '   path="src\Main.pas">'#10 +
    '<entry'#10 +
    '   line-number="1">'#10 +
    '<commit'#10 +
    '   revision="12">'#10 +
    '<author>marco</author>'#10 +
    '<date>2026-09-01T10:00:00.250000Z</date>'#10 +
    '</commit>'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   line-number="2">'#10 +
    '</entry>'#10 +
    '<entry'#10 +
    '   line-number="3">'#10 +
    '<commit'#10 +
    '   revision="40">'#10 +
    '<author>j&#252;rgen</author>'#10 +
    '<date>2026-10-01T08:00:00.000000Z</date>'#10 +
    '</commit>'#10 +
    '</entry>'#10 +
    '</target>'#10 +
    '</blame>'#10;

{ TAtlasVcsTests }

procedure TAtlasVcsTests.ProviderSettingRoundTrip;
var
  Provider: TAtlasVcsProvider;
begin
  for Provider := Low(TAtlasVcsProvider) to High(TAtlasVcsProvider) do
    Assert.IsTrue(AtlasVcsProviderOf(AtlasVcsProviderText(Provider)) = Provider, AtlasVcsProviderText(Provider));
  Assert.IsTrue(AtlasVcsProviderOf(' SVN ') = TAtlasVcsProvider.Svn, 'Groß- und Kleinschreibung egal');
  Assert.IsTrue(AtlasVcsProviderOf('') = TAtlasVcsProvider.Auto, 'leer = auto');
  Assert.IsTrue(AtlasVcsProviderOf('"off"') = TAtlasVcsProvider.Off, 'JSON-Text aus settings.json');
  Assert.IsTrue(AtlasVcsProviderOf('cvs') = TAtlasVcsProvider.Auto, 'unbekannt = auto');
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
  // Weiterleitung für den Host (Code-Review A-12)
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
              Trace := Trace + ' x=' + Reader.Attr('x') + ' y=' + Reader.Attr('y') + ' q=' + Reader.Attr('q');
            if Reader.EmptyElement then
              Trace := Trace + '/';
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

procedure TAtlasVcsTests.GitStatusReadsBranchCommitAndChanges;
var
  Head: TAtlasVcsHead;
  Changes: TArray<TAtlasVcsChange>;
begin
  TAtlasGitParser.ParseStatus(GitStatusSample, Root, Head, Changes);
  Assert.AreEqual('main', Head.Branch);
  Assert.AreEqual(Hash1, Head.Revision);
  Assert.AreEqual('1979e3d', Head.ShortRevision(TAtlasVcsKind.Git));
  Assert.IsFalse(Head.Detached);
  Assert.AreEqual('', Head.Upstream);
  Assert.AreEqual(-1, Head.Ahead, 'ohne verfolgten Branch unbekannt');
  Assert.AreEqual(5, Integer(Length(Changes)));
  Assert.AreEqual(Under('A.pas'), Changes[0].Path);
  Assert.IsTrue(Changes[0].Kind = TAtlasVcsChangeKind.Modified);
  Assert.IsFalse(Changes[0].Staged);
  Assert.IsTrue(Changes[0].Unstaged);
  Assert.AreEqual(Under('C.pas'), Changes[1].Path);
  Assert.AreEqual(Under('B.pas'), Changes[1].OldPath, 'alter Name als eigener Eintrag');
  Assert.IsTrue(Changes[1].Kind = TAtlasVcsChangeKind.Renamed);
  Assert.IsTrue(Changes[1].Staged);
  Assert.IsFalse(Changes[1].Unstaged);
  Assert.AreEqual(Under(#$00DC + ' m.pas'), Changes[2].Path, 'Umlaut und Leerzeichen unverändert');
  Assert.IsTrue(Changes[2].Kind = TAtlasVcsChangeKind.Deleted);
  Assert.AreEqual(Under('Neu.pas'), Changes[3].Path);
  Assert.IsTrue(Changes[3].Kind = TAtlasVcsChangeKind.Untracked);
  Assert.AreEqual(Under('sub/Q.pas'), Changes[4].Path);
end;

procedure TAtlasVcsTests.GitStatusReadsUpstreamDetachedAndInitial;
var
  Head: TAtlasVcsHead;
  Changes: TArray<TAtlasVcsChange>;
begin
  TAtlasGitParser.ParseStatus('# branch.oid ' + Hash1 + #0'# branch.head feature/x'#0 +
    '# branch.upstream origin/feature/x'#0'# branch.ab +2 -3'#0, Root, Head, Changes);
  Assert.AreEqual('feature/x', Head.Branch);
  Assert.AreEqual('origin/feature/x', Head.Upstream);
  Assert.AreEqual(2, Head.Ahead);
  Assert.AreEqual(3, Head.Behind);
  Assert.AreEqual(0, Integer(Length(Changes)));
  TAtlasGitParser.ParseStatus('# branch.oid ' + Hash1 + #0'# branch.head (detached)'#0, Root, Head, Changes);
  Assert.IsTrue(Head.Detached);
  Assert.AreEqual('', Head.Branch);
  Assert.AreEqual(Hash1, Head.Revision);
  TAtlasGitParser.ParseStatus('# branch.oid (initial)'#0'# branch.head main'#0'? A.pas'#0, Root, Head, Changes);
  Assert.AreEqual('', Head.Revision, 'vor dem ersten Commit');
  Assert.AreEqual('main', Head.Branch);
  Assert.AreEqual(1, Integer(Length(Changes)));
  // Ohne -z (Zeilen) wird ebenso gelesen.
  TAtlasGitParser.ParseStatus('# branch.oid ' + Hash1 + #10'# branch.head main'#10, Root, Head, Changes);
  Assert.AreEqual('main', Head.Branch);
end;

procedure TAtlasVcsTests.GitStatusReadsConflictsAndRejectsUnknown;
var
  Head: TAtlasVcsHead;
  Changes: TArray<TAtlasVcsChange>;
begin
  TAtlasGitParser.ParseStatus('# branch.head main'#0 +
    'u UU N... 100644 100644 100644 100644 ' + Hash1 + ' ' + Hash2 + ' ' + Hash1 + ' src/Konflikt Datei.pas'#0 +
    '1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 ' + Hash2 + ' Neu.pas'#0 +
    '1 MM N... 100644 100644 100644 ' + Hash1 + ' ' + Hash2 + ' Beides.pas'#0 +
    '1 .T N... 100644 100644 120000 ' + Hash1 + ' ' + Hash1 + ' Link.pas'#0 +
    '! ignoriert.dcu'#0, Root, Head, Changes);
  Assert.AreEqual(4, Integer(Length(Changes)), 'ignorierte Dateien entfallen');
  Assert.AreEqual(Under('src/Konflikt Datei.pas'), Changes[0].Path);
  Assert.IsTrue(Changes[0].Kind = TAtlasVcsChangeKind.Conflicted);
  Assert.IsTrue(Changes[1].Kind = TAtlasVcsChangeKind.Added);
  Assert.IsTrue(Changes[1].Staged);
  Assert.IsTrue(Changes[2].Kind = TAtlasVcsChangeKind.Modified);
  Assert.IsTrue(Changes[2].Staged and Changes[2].Unstaged);
  Assert.IsTrue(Changes[3].Kind = TAtlasVcsChangeKind.TypeChanged);
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseStatus('X unbekannt'#0, Root, Head, Changes);
    end, EAtlasVcsParse);
end;

procedure TAtlasVcsTests.GitBlameReadsCommitsAndUncommittedLines;
var
  Lines: TArray<TAtlasVcsBlameLine>;
begin
  // Aufgezeichnet mit git 2.43: "git blame --porcelain -- A.pas" mit einer neuen, noch nicht übernommenen Zeile.
  Lines := TAtlasGitParser.ParseBlame(
    Hash1 + ' 1 1 2'#10 +
    'author Ada'#10 +
    'author-mail <a@x>'#10 +
    'author-time 1792066959'#10 +
    'author-tz +0000'#10 +
    'committer Ada'#10 +
    'committer-mail <a@x>'#10 +
    'committer-time 1792066959'#10 +
    'committer-tz +0000'#10 +
    'summary Erster Stand'#10 +
    'boundary'#10 +
    'filename A.pas'#10 +
    #9'unit A;'#10 +
    Hash1 + ' 2 2'#10 +
    #9'end.'#10 +
    '0000000000000000000000000000000000000000 3 3 1'#10 +
    'author Not Committed Yet'#10 +
    'author-mail <not.committed.yet>'#10 +
    'author-time 1792066959'#10 +
    'author-tz +0000'#10 +
    'committer Not Committed Yet'#10 +
    'committer-mail <not.committed.yet>'#10 +
    'committer-time 1792066959'#10 +
    'committer-tz +0000'#10 +
    'summary Version of A.pas from A.pas'#10 +
    'previous ' + Hash1 + ' A.pas'#10 +
    'filename A.pas'#10 +
    #9'z'#10);
  Assert.AreEqual(3, Integer(Length(Lines)));
  Assert.AreEqual(1, Lines[0].Line);
  Assert.AreEqual(Hash1, Lines[0].Revision);
  Assert.AreEqual('Ada', Lines[0].Author);
  Assert.AreEqual('Erster Stand', Lines[0].Summary);
  Assert.AreEqual('2026-10-15 12:22:39', FormatDateTime('yyyy-mm-dd hh:nn:ss', Lines[0].Date));
  Assert.AreEqual(2, Lines[1].Line);
  Assert.AreEqual('Ada', Lines[1].Author, 'Angaben des Commits nur beim ersten Auftreten');
  Assert.AreEqual('Erster Stand', Lines[1].Summary);
  Assert.AreEqual(3, Lines[2].Line);
  Assert.IsTrue(Lines[2].Uncommitted);
  Assert.AreEqual('', Lines[2].Author, 'nicht übernommen: kein Autor');
  Assert.IsFalse(Lines[0].Uncommitted);
  Assert.AreEqual(0, Integer(Length(TAtlasGitParser.ParseBlame(''))));
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseBlame('kein Kopf'#10);
    end, EAtlasVcsParse);
end;

procedure TAtlasVcsTests.SvnInfoReadsRootPathAndRevision;
var
  Info: TAtlasSvnInfo;
begin
  Info := TAtlasSvnParser.ParseInfo(SvnInfoSample);
  Assert.AreEqual(VcsNormalizeDir('C:/Projekte/Kunde'), Info.Root);
  Assert.AreEqual('projekt/branches/release-2', Info.RelativeUrl);
  Assert.AreEqual('42', Info.Revision, 'Revision der Arbeitskopie, nicht des letzten Commits');
  // svn vor 1.8: ohne relative-url aus url und root.
  Info := TAtlasSvnParser.ParseInfo(StringReplace(SvnInfoSample,
    '<relative-url>^/projekt/branches/release-2</relative-url>', '', []));
  Assert.AreEqual('projekt/branches/release-2', Info.RelativeUrl);
  Assert.WillRaise(
    procedure
    begin
      TAtlasSvnParser.ParseInfo('<info></info>');
    end, EAtlasVcsParse);
end;

procedure TAtlasVcsTests.SvnBranchFromRepositoryPath;
begin
  Assert.AreEqual('trunk', TAtlasSvnParser.BranchOf('trunk'));
  Assert.AreEqual('trunk', TAtlasSvnParser.BranchOf('projekt/trunk/src'));
  Assert.AreEqual('branches/x', TAtlasSvnParser.BranchOf('branches/x'));
  Assert.AreEqual('branches/release-2', TAtlasSvnParser.BranchOf('projekt/branches/release-2/src/sub'));
  Assert.AreEqual('tags/1.0', TAtlasSvnParser.BranchOf('tags/1.0'));
  Assert.AreEqual('eigenes/layout', TAtlasSvnParser.BranchOf('eigenes/layout'), 'ohne übliche Ablage der ganze Pfad');
  Assert.AreEqual('', TAtlasSvnParser.BranchOf(''));
end;

procedure TAtlasVcsTests.SvnStatusReadsChanges;
var
  Changes: TArray<TAtlasVcsChange>;
begin
  Changes := TAtlasSvnParser.ParseStatus(SvnStatusSample, Root);
  Assert.AreEqual(6, Integer(Length(Changes)), 'ignorierte entfallen');
  Assert.AreEqual(Under('src/Main.pas'), Changes[0].Path);
  Assert.IsTrue(Changes[0].Kind = TAtlasVcsChangeKind.Modified);
  Assert.IsTrue(Changes[0].Unstaged);
  Assert.IsFalse(Changes[0].Staged);
  Assert.AreEqual(Under('src/Neu & Alt.pas'), Changes[1].Path);
  Assert.IsTrue(Changes[1].Kind = TAtlasVcsChangeKind.Added);
  Assert.AreEqual(Under('notizen.txt'), Changes[2].Path);
  Assert.IsTrue(Changes[2].Kind = TAtlasVcsChangeKind.Untracked);
  Assert.AreEqual(Under('res/Logo.png'), Changes[3].Path, 'nur Eigenschaften geändert');
  Assert.IsTrue(Changes[3].Kind = TAtlasVcsChangeKind.Modified);
  Assert.IsTrue(Changes[4].Kind = TAtlasVcsChangeKind.Deleted, 'leeres wc-status-Element');
  Assert.IsTrue(Changes[5].Kind = TAtlasVcsChangeKind.Missing);
  Assert.AreEqual(0, Integer(Length(TAtlasSvnParser.ParseStatus('<status><target path="."></target></status>', Root))));
end;

procedure TAtlasVcsTests.SvnBlameReadsLines;
var
  Lines: TArray<TAtlasVcsBlameLine>;
begin
  Lines := TAtlasSvnParser.ParseBlame(SvnBlameSample);
  Assert.AreEqual(3, Integer(Length(Lines)));
  Assert.AreEqual(1, Lines[0].Line);
  Assert.AreEqual('12', Lines[0].Revision);
  Assert.AreEqual('marco', Lines[0].Author);
  Assert.AreEqual('2026-09-01 10:00:00.250', FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Lines[0].Date));
  Assert.AreEqual(2, Lines[1].Line);
  Assert.IsTrue(Lines[1].Uncommitted, 'lokal geändert: ohne commit');
  Assert.AreEqual('j' + #$00FC + 'rgen', Lines[2].Author);
  Assert.AreEqual('40', Lines[2].Revision);
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
        if SameText(Item, APath) then
          Exit(True);
      Result := False;
    end;
  AFileExists :=
    function(const APath: string): Boolean
    var
      Item: string;
    begin
      for Item in Files do
        if SameText(Item, APath) then
          Exit(True);
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
  Assert.IsTrue(Found.Kind = TAtlasVcsKind.Git);
  Assert.AreEqual(Root, Found.Root);
  Found := TAtlasVcsDetection.Find(Under('lib/fremd/src'), TAtlasVcsProvider.Auto, DirExists, FileExists_);
  Assert.IsTrue(Found.Kind = TAtlasVcsKind.Svn, 'die nächstliegende gilt');
  Assert.AreEqual(Under('lib/fremd'), Found.Root);
  Found := TAtlasVcsDetection.Find(Under('ext/sub/src'), TAtlasVcsProvider.Auto, DirExists, FileExists_);
  Assert.IsTrue(Found.Kind = TAtlasVcsKind.Git, '.git als Datei (Submodul, Worktree)');
  Assert.AreEqual(Under('ext/sub'), Found.Root);
  Found := TAtlasVcsDetection.Find(Root + PathDelim, TAtlasVcsProvider.Auto, DirExists, FileExists_);
  Assert.AreEqual(Root, Found.Root, 'Ordner mit Trenner am Ende');
  // Beide im selben Ordner: Git gewinnt.
  FakeFileSystem([Under('.git'), Under('.svn')], [], DirExists, FileExists_);
  Assert.IsTrue(TAtlasVcsDetection.Find(Root, TAtlasVcsProvider.Auto, DirExists, FileExists_).Kind =
    TAtlasVcsKind.Git);
  FakeFileSystem([], [], DirExists, FileExists_);
  Found := TAtlasVcsDetection.Find(Under('src'), TAtlasVcsProvider.Auto, DirExists, FileExists_);
  Assert.IsTrue(Found.Kind = TAtlasVcsKind.None, 'ohne Arbeitskopie');
  Assert.AreEqual('', Found.Root);
end;

procedure TAtlasVcsTests.DetectionHonoursProvider;
var
  DirExists, FileExists_: TAtlasVcsPathExists;
  Found: TAtlasVcsWorkingCopy;
begin
  FakeFileSystem([Under('.git'), Under('lib/fremd/.svn')], [], DirExists, FileExists_);
  Found := TAtlasVcsDetection.Find(Under('lib/fremd/src'), TAtlasVcsProvider.Git, DirExists, FileExists_);
  Assert.IsTrue(Found.Kind = TAtlasVcsKind.Git, 'git: SVN wird übergangen');
  Assert.AreEqual(Root, Found.Root);
  Found := TAtlasVcsDetection.Find(Under('src'), TAtlasVcsProvider.Svn, DirExists, FileExists_);
  Assert.IsTrue(Found.Kind = TAtlasVcsKind.None, 'svn: Git zählt nicht');
  Found := TAtlasVcsDetection.Find(Under('lib/fremd'), TAtlasVcsProvider.Off, DirExists, FileExists_);
  Assert.IsTrue(Found.Kind = TAtlasVcsKind.None, 'off sucht nicht');
end;

procedure TAtlasVcsTests.LocatesProgramInPathAndKnownDirs;
var
  Exe, PathText: string;
  Dirs: TArray<string>;
begin
  Exe := 'svn';
  if PathDelim = '\' then
    Exe := 'svn.exe';
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
  Assert.IsTrue(Vcs.Kind = TAtlasVcsKind.Git);
  Assert.AreEqual(Root, Vcs.WorkingCopy.Root, 'ohne Trenner am Ende');
  Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('main', Head.Branch);
  Assert.AreEqual('--no-optional-locks -c core.quotepath=off -c color.ui=false status --porcelain=v2 --branch -z ' +
    '--untracked-files=no', Runner.Calls[0]);
  Assert.AreEqual(Root, Runner.WorkingDirs[0], 'git läuft in der Wurzel');
  Assert.IsTrue(Vcs.Changes(Changes) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(5, Integer(Length(Changes)));
  Assert.Contains(Runner.Calls[1], '--untracked-files=all');
  Assert.IsTrue(Vcs.FileAt(Under('src/Main.pas'), '', Content) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('unit A;', TEncoding.UTF8.GetString(Content));
  Assert.IsTrue(Pos('show HEAD:src/Main.pas', Runner.Calls[2]) > 0, 'Revision leer = HEAD, Pfad mit /');
  Assert.IsTrue(Vcs.FileAt(Under('A.pas'), Hash2, Content) = TAtlasVcsOutcome.Ok);
  Assert.Contains(Runner.Calls[3], 'show ' + Hash2 + ':A.pas');
  Assert.IsTrue(Vcs.Blame(Under('src/Main.pas'), Lines) = TAtlasVcsOutcome.Ok);
  Assert.Contains(Runner.Calls[4], 'blame --porcelain -- src/Main.pas');
  Assert.AreEqual(1, Integer(Length(Lines)));
  Assert.AreEqual('S', Lines[0].Summary);
  // Datei außerhalb der Arbeitskopie, Revision als Option: kein Aufruf.
  Assert.IsTrue(Vcs.FileAt(Root + 'X' + PathDelim + 'A.pas', '', Content) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Vcs.FileAt(Under('A.pas'), '--output=x', Content) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Vcs.Blame(Root + 'X' + PathDelim + 'A.pas', Lines) = TAtlasVcsOutcome.Failed);
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
  Assert.IsTrue(Vcs.Kind = TAtlasVcsKind.Svn);
  Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('branches/release-2', Head.Branch);
  Assert.AreEqual('42', Head.Revision);
  Assert.AreEqual('r42', Head.ShortRevision(TAtlasVcsKind.Svn));
  Assert.AreEqual(-1, Head.Ahead);
  Assert.AreEqual('info --xml . --non-interactive', Runner.Calls[0]);
  Assert.AreEqual(Root, Runner.WorkingDirs[0]);
  Assert.IsTrue(Vcs.Changes(Changes) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(6, Integer(Length(Changes)));
  Assert.AreEqual('status --xml . --non-interactive', Runner.Calls[1]);
  Assert.IsTrue(Vcs.FileAt(Under('src/Main.pas'), '', Content) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('cat -r BASE src/Main.pas@ --non-interactive', Runner.Calls[2], 'Revision leer = BASE');
  Assert.IsTrue(Vcs.FileAt(Under('src/Main.pas'), '40', Content) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('cat -r 40 src/Main.pas@ --non-interactive', Runner.Calls[3]);
  Assert.IsTrue(Vcs.Blame(Under('src/Main.pas'), Lines) = TAtlasVcsOutcome.Ok);
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
  Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.Failed, 'Exit-Code ungleich 0');
  Assert.AreEqual('', Head.Branch);
  Runner.ExitCode := 0;
  Runner.Outcome := TAtlasVcsOutcome.TimedOut;
  Assert.IsTrue(Vcs.Changes(Changes) = TAtlasVcsOutcome.TimedOut, 'Zeitlimit kommt durch');
  Runner.Outcome := TAtlasVcsOutcome.MainThread;
  Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.MainThread, 'Hauptthread abgelehnt');
  Runner.Outcome := TAtlasVcsOutcome.Ok;
  Runner.Answer('status', 'Z kaputt'#0);
  Assert.IsTrue(Vcs.Changes(Changes) = TAtlasVcsOutcome.Failed, 'unlesbare Ausgabe');
  Assert.AreEqual(0, Integer(Length(Changes)));
  Runner.Answer('info', '<info>');
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, 'svn.exe');
  Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.Failed, 'svn info ohne Eintrag');
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, '');
  Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.ToolMissing, 'ohne Programm kein Aufruf');
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
  Assert.IsTrue(Vcs.Kind = TAtlasVcsKind.None);
  Assert.AreEqual('', Vcs.WorkingCopy.Root);
  Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.NoWorkingCopy);
  Assert.AreEqual('', Head.Branch);
  Assert.AreEqual('', Head.ShortRevision(TAtlasVcsKind.None));
  Assert.IsTrue(Vcs.Changes(Changes) = TAtlasVcsOutcome.NoWorkingCopy);
  Assert.AreEqual(0, Integer(Length(Changes)));
  Assert.IsTrue(Vcs.FileAt(Under('A.pas'), '', Content) = TAtlasVcsOutcome.NoWorkingCopy);
  Assert.AreEqual(0, Integer(Length(Content)));
  Assert.IsTrue(Vcs.Blame(Under('A.pas'), Lines) = TAtlasVcsOutcome.NoWorkingCopy);
  Assert.AreEqual('', Vcs.ChangeMarker);
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.Disabled);
end;

function TempFolder(const AName: string): string;
var
  Temp: string;
begin
  Temp := GetEnvironmentVariable('TEMP');
  if Temp = '' then
    Temp := GetEnvironmentVariable('TMPDIR');
  if Temp = '' then
    Temp := '/tmp';
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
      Stream.WriteBuffer(Bytes[0], Length(Bytes));
  finally
    Stream.Free;
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
  Locate :=
    function(AKind: TAtlasVcsKind): string
    begin
      // svn fehlt, git ist da.
      if AKind = TAtlasVcsKind.Git then
        Result := 'git.exe'
      else
        Result := '';
    end;
  Reported := nil;
  TAtlasVcsNotices.Reset;
  TAtlasVcsNotices.OnToolMissing :=
    procedure(AKind: TAtlasVcsKind)
    begin
      Reported := Reported + [AKind];
    end;
  try
    Vcs := TAtlasVersionControl.Open(Folder + PathDelim + 'src', TAtlasVcsProvider.Auto, RunnerRef, Locate, 1000);
    Assert.IsTrue(Vcs.Kind = TAtlasVcsKind.None, 'ohne svn weiter ohne Versionsverwaltung');
    Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.ToolMissing);
    Vcs := TAtlasVersionControl.Open(Folder, TAtlasVcsProvider.Auto, RunnerRef, Locate, 1000);
    Assert.AreEqual(1, Integer(Length(Reported)), 'nur einmal gemeldet');
    Assert.IsTrue(Reported[0] = TAtlasVcsKind.Svn);
    Vcs := TAtlasVersionControl.Open(Folder, TAtlasVcsProvider.Off, RunnerRef, Locate, 1000);
    Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.Disabled, 'off');
    Vcs := TAtlasVersionControl.Open(Folder, TAtlasVcsProvider.Git, RunnerRef, Locate, 1000);
    Assert.IsTrue(Vcs.Head(Head) = TAtlasVcsOutcome.NoWorkingCopy, 'git gewählt, aber nur SVN da');
    ForceDirectories(Folder + PathDelim + '.git');
    Vcs := TAtlasVersionControl.Open(Folder + PathDelim + 'src', TAtlasVcsProvider.Auto, RunnerRef, Locate, 1000);
    Assert.IsTrue(Vcs.Kind = TAtlasVcsKind.Git);
    Assert.AreEqual(VcsNormalizeDir(Folder), Vcs.WorkingCopy.Root);
    Vcs := TAtlasVersionControl.Open(Folder, TAtlasVcsProvider.Svn, RunnerRef, Locate, 1000);
    Assert.IsTrue(Vcs.Kind = TAtlasVcsKind.None, 'svn gewählt, svn fehlt');
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
  Assert.IsTrue(TAtlasVcsSwitches.Compare(TAtlasVcsHead.Empty, MakeHead('main', Hash1, False)) =
    TAtlasVcsSwitch.None, 'ohne alten Stand');
  Assert.IsTrue(TAtlasVcsSwitches.Compare(MakeHead('main', Hash1, False), MakeHead('main', Hash1, False)) =
    TAtlasVcsSwitch.None);
  Assert.IsTrue(TAtlasVcsSwitches.Compare(MakeHead('main', Hash1, False), MakeHead('feature/x', Hash1, False)) =
    TAtlasVcsSwitch.Branch, 'git checkout ohne neuen Commit');
  Assert.IsTrue(TAtlasVcsSwitches.Compare(MakeHead('main', Hash1, False), MakeHead('main', Hash2, False)) =
    TAtlasVcsSwitch.Revision, 'Commit oder Pull');
  Assert.IsTrue(TAtlasVcsSwitches.Compare(MakeHead('main', Hash1, False), MakeHead('', Hash1, True)) =
    TAtlasVcsSwitch.Branch, 'losgelöster HEAD');
  Assert.IsTrue(TAtlasVcsSwitches.Compare(MakeHead('trunk', '41', False), MakeHead('trunk', '42', False)) =
    TAtlasVcsSwitch.Revision, 'svn update');
  Assert.IsTrue(TAtlasVcsSwitches.Compare(MakeHead('trunk', '42', False), MakeHead('branches/x', '42', False)) =
    TAtlasVcsSwitch.Branch, 'svn switch');
  Assert.IsTrue(TAtlasVcsSwitches.Compare(MakeHead('main', '', False), MakeHead('main', Hash1, False)) =
    TAtlasVcsSwitch.Revision, 'erster Commit');
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
    Assert.IsTrue(Watch.Check = TAtlasVcsSwitch.None, 'erster Stand');
    Assert.IsTrue(Watch.Known);
    Assert.AreEqual('main', Watch.Head.Branch);
    Assert.AreEqual(1, Fake.HeadCalls);
    Assert.IsTrue(Watch.Check = TAtlasVcsSwitch.None);
    Assert.AreEqual(1, Fake.HeadCalls, 'Marke unverändert: kein Prozess');
    Fake.Marker := 'm2';
    Fake.Current := MakeHead('feature/x', Hash1, False);
    Assert.IsTrue(Watch.Check = TAtlasVcsSwitch.Branch);
    Assert.AreEqual(2, Fake.HeadCalls);
    Fake.Marker := 'm3';
    Fake.Current := MakeHead('feature/x', Hash2, False);
    Fake.HeadOutcome := TAtlasVcsOutcome.TimedOut;
    Assert.IsTrue(Watch.Check = TAtlasVcsSwitch.None, 'keine Antwort: alter Stand bleibt');
    Assert.AreEqual('feature/x', Watch.Head.Branch);
    Fake.HeadOutcome := TAtlasVcsOutcome.Ok;
    Assert.IsTrue(Watch.Check = TAtlasVcsSwitch.Revision, 'beim nächsten Mal erkannt');
    Fake.Marker := '';
    Assert.IsTrue(Watch.Check = TAtlasVcsSwitch.None);
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
      CheckSynchronize(10);
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

procedure TAtlasVcsTests.GitParsesBranchesStashesLogAndNameStatus;
var
  Branches: TArray<TAtlasVcsBranch>;
  Stashes: TArray<TAtlasVcsStash>;
  Commits: TArray<TAtlasVcsCommit>;
  Changes: TArray<TAtlasVcsChange>;
begin
  // #762: Ausgaben wie von git 2.43 (for-each-ref mit %00, "%(HEAD)" ist "*" oder " ").
  Branches := TAtlasGitParser.ParseBranches(
    'lokal'#0#0#0#0#0'1792071091'#0' '#10 +
    'main'#0'origin/main'#0'origin'#0'refs/heads/main'#0'ahead 2'#0'1792071092'#0'*'#10 +
    'dev'#0'origin/dev'#0'origin'#0'refs/heads/dev'#0'ahead 1, behind 4'#0'1792071000'#0' '#10 +
    'alt'#0'origin/alt'#0'origin'#0'refs/heads/alt'#0'gone'#0'1792070000'#0' '#10 +
    'sync'#0'origin/sync'#0'origin'#0'refs/heads/sync'#0#0'1792070000'#0' '#10);
  Assert.AreEqual(5, Integer(Length(Branches)));
  Assert.AreEqual('lokal', Branches[0].Name);
  Assert.AreEqual('', Branches[0].Upstream);
  Assert.IsFalse(Branches[0].Tracked);
  Assert.AreEqual(-1, Branches[0].Ahead, 'ohne Upstream unbekannt');
  Assert.IsFalse(Branches[0].Current);
  Assert.IsTrue(Branches[0].TipDate > 0);
  Assert.AreEqual('origin/main', Branches[1].Upstream);
  Assert.AreEqual('origin', Branches[1].Remote);
  Assert.AreEqual('refs/heads/main', Branches[1].RemoteRef);
  Assert.AreEqual(2, Branches[1].Ahead);
  Assert.AreEqual(0, Branches[1].Behind);
  Assert.IsTrue(Branches[1].Current);
  Assert.IsTrue(Branches[1].Tracked);
  Assert.AreEqual(1, Branches[2].Ahead);
  Assert.AreEqual(4, Branches[2].Behind);
  Assert.IsTrue(Branches[3].Gone, 'Upstream auf dem Server gelöscht');
  Assert.IsFalse(Branches[3].Tracked);
  Assert.AreEqual(0, Branches[4].Ahead, 'gleichauf');
  Assert.AreEqual(0, Branches[4].Behind);
  Assert.AreEqual(0, Integer(Length(TAtlasGitParser.ParseBranches(''))));

  Stashes := TAtlasGitParser.ParseStashes(
    Hash1 + #0'1792071092'#0'stash@{0}'#0'On main: Mein Name'#10 +
    Hash2 + #0'1792071000'#0'stash@{1}'#0'WIP on feature/x: 9805f75 Hover-Cache: erster Wurf'#10);
  Assert.AreEqual(2, Integer(Length(Stashes)));
  Assert.AreEqual(Hash1, Stashes[0].Hash);
  Assert.AreEqual('stash@{0}', Stashes[0].Ref);
  Assert.AreEqual('main', Stashes[0].Branch);
  Assert.AreEqual('Mein Name', Stashes[0].Message);
  Assert.AreEqual('feature/x', Stashes[1].Branch);
  Assert.AreEqual('Hover-Cache: erster Wurf', Stashes[1].Message, 'ohne "WIP on …:" und Hash');
  Assert.IsTrue(Stashes[1].Date < Stashes[0].Date);

  Commits := TAtlasGitParser.ParseLog(Hash1 + #0'1792071091'#0'vier'#10 + Hash2 + #0'1792071000'#0#10);
  Assert.AreEqual(2, Integer(Length(Commits)));
  Assert.AreEqual('vier', Commits[0].Summary);
  Assert.AreEqual(Copy(Hash1, 1, 7), Commits[0].ShortHash);
  Assert.AreEqual('', Commits[1].Summary, 'leere Nachricht');
  Assert.IsTrue(Commits[1].Date < Commits[0].Date);

  Changes := TAtlasGitParser.ParseNameStatus('M'#0'src/A.pas'#0'A'#0'Neu.pas'#0'D'#0'Weg.pas'#0 +
    'R100'#0'Alt.pas'#0'Umbenannt.pas'#0, Root);
  Assert.AreEqual(4, Integer(Length(Changes)));
  Assert.AreEqual(Under('src/A.pas'), Changes[0].Path);
  Assert.IsTrue(Changes[0].Kind = TAtlasVcsChangeKind.Modified);
  Assert.IsTrue(Changes[1].Kind = TAtlasVcsChangeKind.Added);
  Assert.IsTrue(Changes[2].Kind = TAtlasVcsChangeKind.Deleted);
  Assert.IsTrue(Changes[3].Kind = TAtlasVcsChangeKind.Renamed);
  Assert.AreEqual(Under('Umbenannt.pas'), Changes[3].Path);
  Assert.AreEqual(Under('Alt.pas'), Changes[3].OldPath);

  Assert.AreEqual(2, Integer(Length(TAtlasGitParser.ParseLines('origin'#10'upstream'#13#10#10))));
end;

procedure TAtlasVcsTests.GitParserRejectsBrokenLocalWork;
begin
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseBranches('main'#0'origin/main'#10);
    end, EAtlasVcsParse, 'zu wenige Felder');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseBranches('main'#0'origin/main'#0'origin'#0'refs/heads/main'#0'vorne 2'#0'1'#0'*');
    end, EAtlasVcsParse, 'Abstand unbekannt');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseStashes('nur eins');
    end, EAtlasVcsParse);
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseLog('kurz');
    end, EAtlasVcsParse);
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseNameStatus('X'#0'a'#0, Root);
    end, EAtlasVcsParse, 'Art unbekannt');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseNameStatus('M'#0, Root);
    end, EAtlasVcsParse, 'Pfad fehlt');
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
  Assert.IsTrue(Local.Branches(Branches) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(1, Integer(Length(Branches)));
  Assert.AreEqual(Prefix + 'for-each-ref --format=' + TAtlasGitParser.BranchFormat + ' refs/heads', Runner.Calls[0]);
  Assert.IsTrue(Local.Stashes(Stashes) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Prefix + 'stash list --format=' + TAtlasGitParser.StashFormat, Runner.Calls[1]);
  Assert.AreEqual('X', Stashes[0].Message);
  Assert.IsTrue(Local.Remotes(Names) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('origin', Names[0]);
  Assert.IsTrue(Local.Outgoing('main', 'origin/main', 51, Commits) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Prefix + 'log --format=' + TAtlasGitParser.LogFormat + ' --max-count=51 refs/heads/main --not ' +
    'origin/main', Runner.Calls[3], 'kein fetch: nur das lokale Repository');
  Assert.AreEqual('eins', Commits[0].Summary);
  Assert.IsTrue(Local.Outgoing('lokal', '', 0, Commits) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Prefix + 'log --format=' + TAtlasGitParser.LogFormat + ' --max-count=1 refs/heads/lokal --not ' +
    '--remotes', Runner.Calls[4], 'ohne Upstream: auf keinem Remote');
  Assert.IsTrue(Local.ChangesIn(Hash1, Changes) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Prefix + 'diff --name-status -z --no-renames ' + Hash1 + '^1 ' + Hash1, Runner.Calls[5]);
  Assert.AreEqual(Under('A.pas'), Changes[0].Path);
  Assert.IsTrue(Local.Push('main', 'origin', 'refs/heads/main', False) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Prefix + '-c credential.interactive=never -c core.askPass= push --porcelain origin ' +
    'refs/heads/main:refs/heads/main', Runner.Calls[6], 'ohne Rückfrage nach Zugangsdaten (#1287)');
  Assert.IsTrue(Local.Push('neu', 'origin', 'refs/heads/neu', True) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Prefix + '-c credential.interactive=never -c core.askPass= push --porcelain --set-upstream ' +
    'origin refs/heads/neu:refs/heads/neu', Runner.Calls[7]);
  // Namen, die als Option gelesen würden, starten keinen Prozess.
  Assert.IsTrue(Local.Outgoing('-x', '', 5, Commits) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Local.Outgoing('main', '--all', 5, Commits) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Local.ChangesIn('--output=x', Changes) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Local.Push('main', '-f', 'refs/heads/main', False) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Local.Push('a b', 'origin', 'refs/heads/main', False) = TAtlasVcsOutcome.Failed);
  Assert.AreEqual(8, Integer(Length(Runner.Calls)));
  // Exit-Code ungleich 0 (z. B. Push abgelehnt) = Failed.
  Runner.ExitCode := 1;
  Assert.IsTrue(Local.Push('main', 'origin', 'refs/heads/main', False) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Local.Branches(Branches) = TAtlasVcsOutcome.Failed);
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
  Assert.IsTrue(Local.Branches(Branches) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(0, Integer(Length(Branches)));
  Assert.IsTrue(Local.Stashes(Stashes) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(0, Integer(Length(Stashes)));
  Assert.IsTrue(Local.Remotes(Names) = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(Local.Outgoing('trunk', '', 10, Commits) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(0, Integer(Length(Commits)));
  Assert.IsTrue(Local.ChangesIn('42', Changes) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Local.Push('trunk', 'x', 'y', False) = TAtlasVcsOutcome.Failed);
  Assert.AreEqual(0, Integer(Length(Runner.Calls)), 'kein Prozess');
  // Leere Umsetzung: Outcome sagt, warum.
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsLocalWork, Local));
  Assert.IsTrue(Local.Branches(Branches) = TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Local.Stashes(Stashes) = TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Local.Remotes(Names) = TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Local.Outgoing('main', '', 1, Commits) = TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Local.ChangesIn('x', Changes) = TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Local.Push('main', 'origin', 'refs/heads/main', False) = TAtlasVcsOutcome.Disabled);
end;

procedure TAtlasVcsTests.GitIncomingParsesCommitsWithFiles;
var
  Commits: TArray<TAtlasVcsIncomingCommit>;
begin
  // git log --format=%x1e%H%x00%ct%x00%an%x00%s --name-only -z: Trenner, Kopf mit NUL, Zeilenende, Dateien mit NUL.
  Commits := TAtlasGitParser.ParseIncoming(#$1E + Hash1 + #0'1792071092'#0'Eva Muster'#0'Kunde: Prüfung'#0#10 +
    'src/Kunde.pas'#0'Neu.pas'#0#10 + #$1E + Hash2 + #0'1792071000'#0'Max'#0'Merge branch x'#0#10, Root);
  Assert.AreEqual(2, Integer(Length(Commits)));
  Assert.AreEqual(Hash1, Commits[0].Hash);
  Assert.AreEqual(Copy(Hash1, 1, 7), Commits[0].ShortHash);
  Assert.AreEqual('Eva Muster', Commits[0].Author);
  Assert.AreEqual('Kunde: Prüfung', Commits[0].Summary);
  Assert.AreEqual(2, Integer(Length(Commits[0].Files)));
  Assert.AreEqual(Under('src/Kunde.pas'), Commits[0].Files[0], 'vollständiger Pfad');
  Assert.AreEqual(Under('Neu.pas'), Commits[0].Files[1]);
  Assert.IsTrue(Commits[1].Date < Commits[0].Date);
  Assert.AreEqual(0, Integer(Length(Commits[1].Files)), 'Merge ohne Dateien');
  Assert.AreEqual(0, Integer(Length(TAtlasGitParser.ParseIncoming('', Root))), 'nichts Neues');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseIncoming(#$1E'kurz'#0'1'#0, Root);
    end, EAtlasVcsParse);
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
  Assert.IsTrue(Incoming.Resolve('origin/main', Revision) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Hash2, Revision);
  Assert.AreEqual(Prefix + 'rev-parse --verify --quiet origin/main^{commit}', Runner.Calls[0]);
  Assert.IsTrue(Incoming.Incoming('origin/main', [Hash1, '', Hash2], 200, Commits) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Prefix + 'log --format=' + TAtlasGitParser.IncomingFormat + ' --name-only -z --no-renames ' +
    '--max-count=200 origin/main --not ' + Hash1 + ' ' + Hash2, Runner.Calls[1], 'nur lokale Remote-Branches');
  Assert.AreEqual(1, Integer(Length(Commits)));
  Assert.AreEqual(Under('A.pas'), Commits[0].Files[0]);
  Assert.IsTrue(Incoming.Fetch('') = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Prefix + '-c credential.interactive=never -c core.askPass= fetch --quiet --no-tags',
    Runner.Calls[2], 'ohne Rückfrage nach Zugangsdaten');
  // Namen, die als Option gelesen würden, starten keinen Prozess.
  Assert.IsTrue(Incoming.Resolve('--all', Revision) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Incoming.Incoming('--all', nil, 5, Commits) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Incoming.Incoming('origin/main', ['-p'], 5, Commits) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Incoming.Fetch('--upload-pack=x') = TAtlasVcsOutcome.Failed);
  Assert.AreEqual(3, Integer(Length(Runner.Calls)));
  // SVN: kein lokaler Stand des Servers, kein Prozess; leere Umsetzung meldet ihren Grund.
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(Vcs, IAtlasVcsIncoming, Incoming));
  Assert.IsTrue(Incoming.Incoming('trunk', nil, 5, Commits) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(0, Integer(Length(Commits)));
  Assert.AreEqual(3, Integer(Length(Runner.Calls)), 'SVN startet keinen Prozess');
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsIncoming, Incoming));
  Assert.IsTrue(Incoming.Fetch('') = TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Incoming.Incoming('origin/main', nil, 5, Commits) = TAtlasVcsOutcome.Disabled);
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
  Assert.IsTrue(Update.Pull = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Prefix + '-c credential.interactive=never -c core.askPass= pull --ff-only --no-rebase --quiet',
    Runner.Calls[0], 'nur vorwärts, ohne Rückfrage nach Zugangsdaten');
  Assert.AreEqual(Root, Runner.WorkingDirs[0], 'in der Wurzel der Arbeitskopie');
  // Abweichender Branch: git endet mit Fehler, nichts wird zusammengeführt.
  Runner.ExitCode := 128;
  Assert.IsTrue(Update.Pull = TAtlasVcsOutcome.Failed);
  // Fehlende Anmeldung (#1287): eigenes Ergebnis statt still „Failed“.
  Runner.ErrorText := 'fatal: Authentication failed for ''https://example.com/kasse.git/''';
  Assert.IsTrue(Update.Pull = TAtlasVcsOutcome.LoginNeeded);
  Runner.ErrorText := '';
  Runner.ExitCode := 0;
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(Vcs, IAtlasVcsUpdate, Update), 'SVN bietet IAtlasVcsUpdate');
  Assert.IsTrue(Update.Pull = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('update . --non-interactive', Runner.Calls[3]);
  Runner.ExitCode := 1;
  Runner.ErrorText := 'svn: E170001: Authorization failed';
  Assert.IsTrue(Update.Pull = TAtlasVcsOutcome.LoginNeeded);
  Runner.ErrorText := '';
  Runner.ExitCode := 0;
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.ToolMissing);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsUpdate, Update));
  Assert.IsTrue(Update.Pull = TAtlasVcsOutcome.ToolMissing);
  Assert.AreEqual(5, Integer(Length(Runner.Calls)), 'die leere Umsetzung startet keinen Prozess');
end;

procedure TAtlasVcsTests.ProvidersCreateIssueBranches;
const
  Prefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
  RemotePrefix = Prefix + '-c credential.interactive=never -c core.askPass= ';
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  Branching: IAtlasVcsBranching;
  Exists, mHas: Boolean;
  Hooks, GitDir, mRevision: string;
  mSteps: TArray<TAtlasVcsBranchStep>;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Runner.Answer('for-each-ref', 'refs/heads/feature/753-atlas-bereiche-und' + #10 + 'refs/remotes/origin/develop' + #10);
  Runner.Answer('rev-parse', '.git/hooks' + #10 + '.git' + #10);
  Vcs := TAtlasGitVersionControl.Create(Root, RunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsBranching, Branching), 'Git bietet IAtlasVcsBranching');
  Assert.IsTrue(Branching.BranchExists('feature/753-atlas-bereiche-und', Exists) = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(Exists, 'vorhandener Branch');
  Assert.AreEqual(Prefix + 'for-each-ref --format=%(refname) refs/heads/feature/753-atlas-bereiche-und',
    Runner.Calls[0]);
  Assert.IsTrue(Branching.BranchExists('feature/1-neu', Exists) = TAtlasVcsOutcome.Ok);
  Assert.IsFalse(Exists, 'ein ähnlicher Ref zählt nicht');
  // Remote-Branch im lokalen Stand (#1288), ohne fetch.
  Assert.IsTrue(Branching.RemoteBranchExists('develop', Exists) = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(Exists);
  Assert.AreEqual(Prefix + 'for-each-ref --format=%(refname) refs/remotes/origin/develop', Runner.Calls[2]);
  // Schritte aus dem Plan: lokal mit den festen Optionen, mit Remote zusätzlich ohne Rückfrage.
  mSteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'feature/9-neu',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.RemoteMain, 'develop', ''), 'egal'));
  Assert.IsTrue(Branching.RunStep(mSteps[0]) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Prefix + 'checkout --quiet --no-track -b feature/9-neu refs/remotes/origin/develop --',
    Runner.Calls[3]);
  Assert.IsTrue(Branching.RunStep(TAtlasVcsBranchStep.Make(TArray<string>.Create('push', '-u', 'origin',
    'feature/9-neu'), True, True)) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(RemotePrefix + 'push -u origin feature/9-neu', Runner.Calls[4]);
  // Git: keine Serverrevision, keine Externals, ohne Prozess.
  Assert.IsTrue(Branching.ServerRevision('main', mRevision) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('', mRevision);
  Assert.IsTrue(Branching.HasExternals(mHas) = TAtlasVcsOutcome.Ok);
  Assert.IsFalse(mHas);
  Assert.IsTrue(Branching.RepositoryPath(mRevision) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('', mRevision);
  Assert.AreEqual(5, Integer(Length(Runner.Calls)));
  Assert.IsTrue(Branching.SwitchBranch('feature/753-atlas-bereiche-und') = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Prefix + 'checkout --quiet feature/753-atlas-bereiche-und --', Runner.Calls[5]);
  Assert.IsTrue(Branching.HookFolders(Hooks, GitDir) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(Prefix + 'rev-parse --git-path hooks --git-dir', Runner.Calls[6]);
  Assert.AreEqual(Under('.git/hooks'), Hooks, 'relativ zur Wurzel aufgelöst');
  Assert.AreEqual(Under('.git'), GitDir);
  // Unsichere Namen und leere Schritte starten keinen Prozess.
  Assert.IsTrue(Branching.SwitchBranch('a..b') = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Branching.RemoteBranchExists('-x', Exists) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Branching.RunStep(Default(TAtlasVcsBranchStep)) = TAtlasVcsOutcome.Failed);
  Assert.AreEqual(7, Integer(Length(Runner.Calls)));
  // Git endet mit Fehler (Branch gibt es schon, Konflikt beim Wechsel): Failed.
  Runner.ExitCode := 128;
  Assert.IsTrue(Branching.SwitchBranch('feature/1-neu') = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(Branching.RunStep(mSteps[0]) = TAtlasVcsOutcome.Failed);
  Runner.ExitCode := 0;

  // SVN: Kopie im Repository und switch, beide mit dem Server und --non-interactive.
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, 'svn.exe');
  Assert.IsTrue(Supports(Vcs, IAtlasVcsBranching, Branching), 'SVN bietet IAtlasVcsBranching');
  Runner.Calls := nil;
  mSteps := TAtlasVcsBranchPlan.Steps(TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Svn, 'ATL-123-tracker-im-plugin',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.Head, 'trunk', ''), 'ATL-123 Branch'));
  Assert.IsTrue(Branching.RunStep(mSteps[0]) = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(Branching.RunStep(mSteps[1]) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('copy ^/trunk@ ^/branches/ATL-123-tracker-im-plugin@ --parents -m ATL-123 Branch --non-interactive',
    Runner.Calls[0]);
  Assert.AreEqual('switch ^/branches/ATL-123-tracker-im-plugin@ . --non-interactive', Runner.Calls[1]);
  Assert.IsTrue(Branching.BranchExists('ATL-123-tracker-im-plugin', Exists) = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(Exists);
  Assert.AreEqual('info ^/branches/ATL-123-tracker-im-plugin@ --non-interactive', Runner.Calls[2]);
  // HEAD-Revision vom Server und Externals der Arbeitskopie (#1288).
  Runner.Answer('info', '48230' + #10);
  Assert.IsTrue(Branching.ServerRevision('Kasse/trunk', mRevision) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('48230', mRevision);
  Assert.AreEqual('info --show-item revision --non-interactive ^/Kasse/trunk@', Runner.Calls[3]);
  Runner.Answer('propget', 'Libs - ^/Libs/Common/trunk Common' + #10);
  Assert.IsTrue(Branching.HasExternals(mHas) = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(mHas);
  Assert.AreEqual('propget svn:externals -R . --non-interactive', Runner.Calls[4]);
  Runner.Answer('info', '^/Kasse/trunk' + #10);
  Assert.IsTrue(Branching.RepositoryPath(mRevision) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('Kasse/trunk', mRevision, 'voller Pfad ohne ^/');
  Assert.AreEqual('info --show-item relative-url . --non-interactive', Runner.Calls[5]);
  Assert.IsTrue(Branching.RemoteBranchExists('trunk', Exists) = TAtlasVcsOutcome.Ok);
  Assert.IsFalse(Exists, 'SVN kennt keine Remote-Branches');
  Assert.AreEqual(6, Integer(Length(Runner.Calls)), 'ohne Prozess');
  // Fehlt der Branch, endet svn info mit Fehler: das ist die Antwort.
  Runner.ExitCode := 1;
  Assert.IsTrue(Branching.BranchExists('ATL-9-neu', Exists) = TAtlasVcsOutcome.Ok);
  Assert.IsFalse(Exists);
  Assert.IsTrue(Branching.ServerRevision('trunk', mRevision) = TAtlasVcsOutcome.Failed);
  Assert.AreEqual('', mRevision);
  Runner.ExitCode := 0;
  Assert.IsTrue(Branching.HookFolders(Hooks, GitDir) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('', Hooks);
  Assert.AreEqual(8, Integer(Length(Runner.Calls)), 'Hooks ohne Prozess');

  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsBranching, Branching));
  Assert.IsTrue(Branching.RunStep(mSteps[0]) = TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Branching.BranchExists('feature/1-x', Exists) = TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Branching.ServerRevision('trunk', mRevision) = TAtlasVcsOutcome.Disabled);
  Assert.AreEqual(8, Integer(Length(Runner.Calls)), 'die leere Umsetzung startet keinen Prozess');
  mSteps := nil;
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
  Assert.IsTrue(Branching.BranchExists('KASSE-42-bon', mOptions, mExists) = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(mExists);
  Assert.AreEqual(2, Integer(Length(Runner.Calls)));
  Assert.AreEqual('info --show-item relative-url . --non-interactive', Runner.Calls[0]);
  Assert.AreEqual('info ^/Kasse/branches/KASSE-42-bon@ --non-interactive', Runner.Calls[1]);
  Assert.IsTrue(Branching.SwitchBranch('KASSE-42-bon', mOptions) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(4, Integer(Length(Runner.Calls)));
  Assert.AreEqual('switch ^/Kasse/branches/KASSE-42-bon@ . --non-interactive', Runner.Calls[3]);
  Assert.AreEqual(Cardinal(TAtlasVcsBranchStep.LongTimeoutMs), Runner.Timeouts[3], 'switch mit langem Zeitlimit');
  Assert.AreEqual(Cardinal(TAtlasVcsCommand.DefaultTimeoutMs), Runner.Timeouts[1], 'info mit dem üblichen');
  // Ohne erkennbares Layout: kein Ort und kein Aufruf am Server.
  Runner.Commands := nil;
  Runner.Answers := nil;
  Runner.Answer('info', '^/Sonstiges' + #10);
  Runner.Calls := nil;
  Assert.IsTrue(Branching.BranchExists('KASSE-42-bon', mOptions, mExists) = TAtlasVcsOutcome.Failed);
  Assert.IsFalse(mExists);
  Assert.IsTrue(Branching.SwitchBranch('KASSE-42-bon', mOptions) = TAtlasVcsOutcome.Failed);
  Assert.AreEqual(2, Integer(Length(Runner.Calls)), 'nur relative-url');
  // Fester Ort mit ^/: ohne relative-url; {kennung} aus den Optionen.
  mOptions.Location := '^/Kasse/branches/{kennung}';
  mOptions.Key := 'KASSE-42';
  Runner.Calls := nil;
  Assert.IsTrue(Branching.BranchExists('KASSE-42-bon', mOptions, mExists) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(1, Integer(Length(Runner.Calls)));
  Assert.AreEqual('info ^/Kasse/branches/KASSE-42@ --non-interactive', Runner.Calls[0]);
  // Ungültiges Muster: Failed ohne Prozess.
  mOptions.Location := 'branches/{name}';
  Runner.Calls := nil;
  Assert.IsTrue(Branching.BranchExists('KASSE-42-bon', mOptions, mExists) = TAtlasVcsOutcome.Failed);
  Assert.AreEqual(0, Integer(Length(Runner.Calls)));
  // svnversion liegt neben svn und spricht nicht mit dem Server.
  Assert.IsTrue(Supports(Vcs, IAtlasVcsSvnWorkingCopy, mSvn));
  Runner.Answer('.', '48190:48213M' + #10);
  Assert.IsTrue(mSvn.WorkingRevisions(mText) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('48190:48213M', mText);
  Assert.AreEqual(Under('bin/svnversion.exe'), Runner.Executables[High(Runner.Executables)]);
  Assert.AreEqual('.', Runner.Calls[High(Runner.Calls)]);
  // Git und die leere Umsetzung kennen keine SVN-Revisionen; die Optionen gelten dort nicht.
  Vcs := TAtlasGitVersionControl.Create(Root, RunnerRef, 'git.exe');
  Assert.IsFalse(Supports(Vcs, IAtlasVcsSvnWorkingCopy));
  Vcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.Disabled);
  Assert.IsFalse(Supports(Vcs, IAtlasVcsSvnWorkingCopy));
  Assert.IsTrue(Supports(Vcs, IAtlasVcsBranching, Branching));
  Assert.IsTrue(Branching.BranchExists('x', TAtlasVcsSvnBranchOptions.Default, mExists) = TAtlasVcsOutcome.Disabled);
  Assert.IsTrue(Branching.SwitchBranch('x', TAtlasVcsSvnBranchOptions.Default) = TAtlasVcsOutcome.Disabled);
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
  Assert.IsTrue(mSvn.ExternalsXml(mText) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('<properties/>', mText);
  Assert.AreEqual('propget svn:externals --xml -R . --non-interactive', Runner.Calls[0]);
  Runner.Answer('info', 'https://svn.firma.local/repo' + #10);
  Assert.IsTrue(mSvn.RepositoryRoot(mText) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('https://svn.firma.local/repo', mText);
  Assert.AreEqual('info --show-item repos-root-url . --non-interactive', Runner.Calls[1]);
  // Nur Schalter: Der Fake erkennt keinen Befehl ('').
  Runner.Answer('', '1.14.3' + #10);
  Assert.IsTrue(mSvn.ToolVersion(mText) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('1.14.3', mText);
  Assert.AreEqual('--version --quiet', Runner.Calls[2]);
  Runner.Answer('Packages/Basis', '48190M' + #10);
  Assert.IsTrue(mSvn.WorkingRevisions('Packages/Basis', mText) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('48190M', mText);
  Assert.AreEqual(Under('bin/svnversion.exe'), Runner.Executables[3]);
  // Eingabedatei für propset -F: vor dem Aufruf geschrieben, CRLF wird LF.
  mFile := TPath.Combine(TPath.Combine(TPath.GetTempPath, 'Atlas-Vcs-Tests'), 'p0.txt');
  if TFile.Exists(mFile) then
    TFile.Delete(mFile);
  mStep := TAtlasVcsBranchStep.Make(TArray<string>.Create('propset', 'svn:externals', '-F', mFile, 'p0'), False,
    False);
  mStep.InputFile := mFile;
  mStep.InputText := '-r 1 ^/a Lib'#13#10'# ä'#13#10;
  Assert.IsTrue(Branching.RunStep(mStep) = TAtlasVcsOutcome.Ok);
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

procedure TAtlasVcsTests.WorkingCopyStateCommands;
var
  Runner: TFakeRunner;
  RunnerRef: IAtlasVcsRunner;
  Vcs: IAtlasVersionControl;
  mExternals: IAtlasVcsSvnExternals;
  mSubmodules: IAtlasVcsSubmodules;
  mText, mFile: string;
  mCount: Integer;
begin
  Runner := TFakeRunner.Create;
  RunnerRef := Runner;
  Vcs := TAtlasSvnVersionControl.Create(Root, RunnerRef, Under('bin/svn.exe'));
  Assert.IsTrue(Supports(Vcs, IAtlasVcsSvnExternals, mExternals));
  Assert.IsFalse(Supports(Vcs, IAtlasVcsSubmodules), 'SVN kennt keine Submodule');
  Runner.Answer('status', '<status/>');
  Assert.IsTrue(mExternals.StatusXml(mText) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('<status/>', mText);
  Assert.AreEqual('status --xml . --non-interactive', Runner.Calls[0]);
  Assert.IsTrue(mExternals.Update(False) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('update . --non-interactive', Runner.Calls[1]);
  Assert.IsTrue(mExternals.Update(True) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('update . --ignore-externals --non-interactive', Runner.Calls[2]);
  // HEAD:4711 enthält 4711 selbst, wenn sie den Pfad geändert hat.
  Runner.Answer('log', '<?xml version="1.0"?><log><logentry revision="4790"></logentry>' +
    '<logentry revision="4750"></logentry><logentry revision="4711"></logentry></log>');
  Assert.IsTrue(mExternals.CommitsSince('Packages/Kunden/trunk', '4711', mCount) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(2, mCount);
  Assert.AreEqual('log -q --xml -r HEAD:4711 ^/Packages/Kunden/trunk@HEAD --non-interactive', Runner.Calls[3]);
  Assert.IsTrue(mExternals.CommitsSince('Packages/Kunden/trunk', 'HEAD', mCount) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(mExternals.CommitsSince('-r1', '4711', mCount) = TAtlasVcsOutcome.Failed);
  Assert.AreEqual(4, Integer(Length(Runner.Calls)), 'ungültig ohne Aufruf');
  Runner.Answer('log', '<log><logentry');
  Assert.IsTrue(mExternals.CommitsSince('Packages/Kunden/trunk', '4711', mCount) = TAtlasVcsOutcome.Failed);
  Assert.AreEqual(0, mCount);
  Assert.IsTrue(mExternals.SetExternals('', '-r 4711 ^/Packages/Kunden/trunk Packages/Kunden'#10) =
    TAtlasVcsOutcome.Ok);
  mText := Runner.Calls[High(Runner.Calls)];
  Assert.IsTrue(mText.StartsWith('propset svn:externals -F '), mText);
  Assert.IsTrue(mText.EndsWith(' . --non-interactive'), mText);
  mFile := Copy(mText, Length('propset svn:externals -F ') + 1, Length(mText));
  mFile := Copy(mFile, 1, Length(mFile) - Length(' . --non-interactive'));
  Assert.IsFalse(TFile.Exists(mFile), 'Temp-Datei wieder entfernt');
  Assert.IsTrue(mExternals.SetExternals('Packages', '^/x Lib') = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(Runner.Calls[High(Runner.Calls)].EndsWith(' Packages --non-interactive'));
  mExternals := nil;
  Vcs := TAtlasGitVersionControl.Create(Root + PathDelim, RunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(Vcs, IAtlasVcsSubmodules, mSubmodules));
  Assert.IsFalse(Supports(Vcs, IAtlasVcsSvnExternals), 'Git kennt keine Externals');
  Runner.Answer('submodule', ' 3f2a… Packages/Basis (heads/main)'#10);
  Assert.IsTrue(mSubmodules.SubmoduleStatus(mText) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(' 3f2a… Packages/Basis (heads/main)'#10, mText);
  Assert.IsTrue(Runner.Calls[High(Runner.Calls)].EndsWith('submodule status --recursive'),
    Runner.Calls[High(Runner.Calls)]);
  mText := '';
  mFile := '';
  Runner.Calls := nil;
  Runner.Executables := nil;
  Runner.Timeouts := nil;
  Runner.WorkingDirs := nil;
  Runner.Commands := nil;
  Runner.Answers := nil;
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
  mFolder: string;
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
  Assert.IsTrue(mRun.Outcome = TAtlasVcsOutcome.LoginNeeded);
  Assert.IsTrue(TAtlasVcsBranchPlan.FetchFailed(mSteps, mRun));
  Assert.AreEqual(1, Integer(Length(Runner.Calls)));
  Runner.ErrorText := '';
  Runner.ExitCode := 0;
  // worktree: eigener Ordner statt stash und checkout; Push an den Remote des Hauptbranchs.
  Runner.Calls := nil;
  mFolder := ExtractFileDir(Root) + PathDelim + 'kasse-ATL-9';
  mRequest := TAtlasVcsBranchRequest.Make(TAtlasVcsKind.Git, 'ATL-9-neu',
    TAtlasVcsBranchBase.Make(TAtlasVcsBranchBaseKind.LocalMain, 'main', '', 'upstream'), '');
  mRequest.Stash := True;
  mRequest.PushNow := True;
  mRequest.WorktreeFolder := mFolder;
  mSteps := TAtlasVcsBranchPlan.Steps(mRequest);
  mRun := TAtlasVcsBranchPlan.Execute(mBranching, mSteps);
  Assert.IsTrue(mRun.Succeeded);
  Assert.AreEqual(2, Integer(Length(Runner.Calls)));
  Assert.AreEqual(Prefix + 'worktree add --quiet --no-track -b ATL-9-neu ' + mFolder + ' refs/heads/main',
    Runner.Calls[0]);
  Assert.AreEqual(RemotePrefix + 'push --set-upstream upstream refs/heads/ATL-9-neu:refs/heads/ATL-9-neu',
    Runner.Calls[1]);
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsTests);

end.
