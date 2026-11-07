unit Atlas.Core.Vcs.Internals.SvnParser.Tests;

// Tests des svn-Parsers mit aufgezeichneten Ausgaben (svn 1.14): Info, Status, Blame, Log und Liste.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Lesen aufgezeichneter svn-Ausgaben.</summary>
  [TestFixture]
  [Category('Atlas.IDE.Vcs')]
  TAtlasVcsSvnParserTests = class
  public
    [Test]
    procedure SvnInfoReadsRootPathAndRevision;
    [Test]
    procedure SvnBranchFromRepositoryPath;
    [Test]
    procedure SvnStatusReadsChanges;
    [Test]
    procedure SvnBlameReadsLines;
    [Test]
    procedure SvnParsesLogListAndLocalPaths;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Internals.Text,
  Atlas.Core.Vcs.Internals.SvnParser,
  Atlas.Core.Vcs.TestSupport;

procedure TAtlasVcsSvnParserTests.SvnInfoReadsRootPathAndRevision;
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
procedure TAtlasVcsSvnParserTests.SvnBranchFromRepositoryPath;
begin
  Assert.AreEqual('trunk', TAtlasSvnParser.BranchOf('trunk'));
  Assert.AreEqual('trunk', TAtlasSvnParser.BranchOf('projekt/trunk/src'));
  Assert.AreEqual('branches/x', TAtlasSvnParser.BranchOf('branches/x'));
  Assert.AreEqual('branches/release-2', TAtlasSvnParser.BranchOf('projekt/branches/release-2/src/sub'));
  Assert.AreEqual('tags/1.0', TAtlasSvnParser.BranchOf('tags/1.0'));
  Assert.AreEqual('eigenes/layout', TAtlasSvnParser.BranchOf('eigenes/layout'), 'ohne übliche Ablage der ganze Pfad');
  Assert.AreEqual('', TAtlasSvnParser.BranchOf(''));
end;
procedure TAtlasVcsSvnParserTests.SvnStatusReadsChanges;
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
procedure TAtlasVcsSvnParserTests.SvnBlameReadsLines;
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
procedure TAtlasVcsSvnParserTests.SvnParsesLogListAndLocalPaths;
var
  Entries: TArray<TAtlasVcsLogEntry>;
  Refs: TArray<TAtlasVcsRef>;
begin
  // Arbeitskopie von ^/projekt/trunk: Dateien anderer Branches desselben Projekts zählen mit ihrem Pfad darunter.
  Assert.AreEqual(Under('src/Main.pas'), TAtlasSvnParser.LocalPath(Root, 'projekt/trunk',
    '/projekt/branches/ATL-12-tracker/src/Main.pas'));
  Assert.AreEqual('', TAtlasSvnParser.LocalPath(Root, 'projekt/trunk', '/anderes/trunk/X.pas'), 'anderes Projekt');
  Assert.AreEqual('', TAtlasSvnParser.LocalPath(Root, 'projekt/trunk', '/projekt/liesmich.txt'), 'ohne Ablage');
  // Arbeitskopie eines Unterordners: nur darunter, relativ dazu.
  Assert.AreEqual(Under('Main.pas'), TAtlasSvnParser.LocalPath(Root, 'projekt/trunk/src',
    '/projekt/branches/x/src/Main.pas'));
  Assert.AreEqual('', TAtlasSvnParser.LocalPath(Root, 'projekt/trunk/src', '/projekt/trunk/doc/A.md'));

  Entries := TAtlasSvnParser.ParseLog(SvnLogSample, Root, 'projekt/trunk');
  Assert.AreEqual(2, Integer(Length(Entries)));
  Assert.AreEqual('57', Entries[0].Revision);
  Assert.AreEqual('r57', Entries[0].ShortRevision(TAtlasVcsKind.Svn));
  Assert.AreEqual('marco', Entries[0].Author);
  Assert.AreEqual('ATL-12 Tracker & Plugin', Entries[0].Summary);
  Assert.AreEqual('ATL-12 Tracker & Plugin'#10'Zweite Zeile', Entries[0].Message);
  Assert.AreEqual(Double(EncodeDate(2026, 10, 27) + EncodeTime(21, 20, 0, 0)), Double(Entries[0].Date), 1 / 86400);
  Assert.AreEqual(2, Integer(Length(Entries[0].Files)), 'Ordner zählen nicht');
  Assert.AreEqual('/projekt/branches/ATL-12-tracker/src/Main.pas', Entries[0].Files[0].RepositoryPath);
  Assert.AreEqual(Under('src/Main.pas'), Entries[0].Files[0].Path);
  Assert.IsTrue(Entries[0].Files[1].Kind = TAtlasVcsChangeKind.Deleted);
  Assert.AreEqual('', Entries[0].Files[1].Path, 'außerhalb der Arbeitskopie');
  Assert.IsTrue(Entries[1].Files[0].Kind = TAtlasVcsChangeKind.Added);

  Refs := TAtlasSvnParser.ParseList(SvnListSample, 'branches/release-2');
  Assert.AreEqual(2, Integer(Length(Refs)), 'nur Ordner');
  Assert.AreEqual('ATL-12-tracker', Refs[0].Name);
  Assert.AreEqual('ATL-12-tracker', Refs[0].LocalName);
  Assert.IsTrue(Refs[0].Remote, 'liegt auf dem Server');
  Assert.IsFalse(Refs[0].Current);
  Assert.IsTrue(Refs[1].Current, 'Arbeitskopie zeigt auf release-2');
  Assert.AreEqual(Double(EncodeDate(2026, 10, 1) + EncodeTime(8, 0, 0, 0)), Double(Refs[1].TipDate), 1 / 86400);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsSvnParserTests);

end.
