unit Atlas.Core.VersionControl.Internals.SvnParser.Tests;

// Tests des svn-Parsers mit aufgezeichneten Ausgaben (svn 1.14): Info, Status, Blame, Log und Liste.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Lesen aufgezeichneter svn-Ausgaben.</summary>
  [TestFixture]
  [Category('Atlas.IDE.VersionControl')]
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
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Internals.Text,
  Atlas.Core.VersionControl.Internals.SvnParser,
  Atlas.Core.VersionControl.TestSupport;

procedure TAtlasVcsSvnParserTests.SvnInfoReadsRootPathAndRevision;
var
  mInfo: TAtlasSvnInfo;
begin
  mInfo := TAtlasSvnParser.ParseInfo(cSvnInfoSample);
  Assert.AreEqual(VcsNormalizeDir('C:/Projekte/Kunde'), mInfo.Root);
  Assert.AreEqual('projekt/branches/release-2', mInfo.RelativeUrl);
  Assert.AreEqual('42', mInfo.Revision, 'Revision der Arbeitskopie, nicht des letzten Commits');
  // svn vor 1.8: ohne relative-url aus url und root.
  mInfo := TAtlasSvnParser.ParseInfo(StringReplace(cSvnInfoSample,
    '<relative-url>^/projekt/branches/release-2</relative-url>', '', []));
  Assert.AreEqual('projekt/branches/release-2', mInfo.RelativeUrl);
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
  mChanges: TArray<TAtlasVcsChange>;
begin
  mChanges := TAtlasSvnParser.ParseStatus(cSvnStatusSample, Root);
  Assert.AreEqual(6, Integer(Length(mChanges)), 'ignorierte entfallen');
  Assert.AreEqual(Under('src/Main.pas'), mChanges[0].Path);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Modified, mChanges[0].Kind);
  Assert.IsTrue(mChanges[0].Unstaged);
  Assert.IsFalse(mChanges[0].Staged);
  Assert.AreEqual(Under('src/Neu & Alt.pas'), mChanges[1].Path);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Added, mChanges[1].Kind);
  Assert.AreEqual(Under('notizen.txt'), mChanges[2].Path);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Untracked, mChanges[2].Kind);
  Assert.AreEqual(Under('res/Logo.png'), mChanges[3].Path, 'nur Eigenschaften geändert');
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Modified, mChanges[3].Kind);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Deleted, mChanges[4].Kind, 'leeres wc-status-Element');
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Missing, mChanges[5].Kind);
  Assert.AreEqual(0, Integer(Length(TAtlasSvnParser.ParseStatus('<status><target path="."></target></status>', Root))));
end;
procedure TAtlasVcsSvnParserTests.SvnBlameReadsLines;
var
  mLines: TArray<TAtlasVcsBlameLine>;
begin
  mLines := TAtlasSvnParser.ParseBlame(cSvnBlameSample);
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.AreEqual(1, mLines[0].Line);
  Assert.AreEqual('12', mLines[0].Revision);
  Assert.AreEqual('marco', mLines[0].Author);
  Assert.AreEqual('2026-09-01 10:00:00.250', FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', mLines[0].Date));
  Assert.AreEqual(2, mLines[1].Line);
  Assert.IsTrue(mLines[1].Uncommitted, 'lokal geändert: ohne commit');
  Assert.AreEqual('j' + #$00FC + 'rgen', mLines[2].Author);
  Assert.AreEqual('40', mLines[2].Revision);
end;
procedure TAtlasVcsSvnParserTests.SvnParsesLogListAndLocalPaths;
var
  mEntries: TArray<TAtlasVcsLogEntry>;
  mRefs: TArray<TAtlasVcsRef>;
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

  mEntries := TAtlasSvnParser.ParseLog(cSvnLogSample, Root, 'projekt/trunk');
  Assert.AreEqual(2, Integer(Length(mEntries)));
  Assert.AreEqual('57', mEntries[0].Revision);
  Assert.AreEqual('r57', mEntries[0].ShortRevision(TAtlasVcsKind.Svn));
  Assert.AreEqual('marco', mEntries[0].Author);
  Assert.AreEqual('ATL-12 Tracker & Plugin', mEntries[0].Summary);
  Assert.AreEqual('ATL-12 Tracker & Plugin'#10'Zweite Zeile', mEntries[0].Message);
  Assert.AreEqual(Double(EncodeDate(2026, 10, 27) + EncodeTime(21, 20, 0, 0)), Double(mEntries[0].Date), 1 / 86400);
  Assert.AreEqual(2, Integer(Length(mEntries[0].Files)), 'Ordner zählen nicht');
  Assert.AreEqual('/projekt/branches/ATL-12-tracker/src/Main.pas', mEntries[0].Files[0].RepositoryPath);
  Assert.AreEqual(Under('src/Main.pas'), mEntries[0].Files[0].Path);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Deleted, mEntries[0].Files[1].Kind);
  Assert.AreEqual('', mEntries[0].Files[1].Path, 'außerhalb der Arbeitskopie');
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Added, mEntries[1].Files[0].Kind);

  mRefs := TAtlasSvnParser.ParseList(cSvnListSample, 'branches/release-2');
  Assert.AreEqual(2, Integer(Length(mRefs)), 'nur Ordner');
  Assert.AreEqual('ATL-12-tracker', mRefs[0].Name);
  Assert.AreEqual('ATL-12-tracker', mRefs[0].LocalName);
  Assert.IsTrue(mRefs[0].Remote, 'liegt auf dem Server');
  Assert.IsFalse(mRefs[0].Current);
  Assert.IsTrue(mRefs[1].Current, 'Arbeitskopie zeigt auf release-2');
  Assert.AreEqual(Double(EncodeDate(2026, 10, 1) + EncodeTime(8, 0, 0, 0)), Double(mRefs[1].TipDate), 1 / 86400);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsSvnParserTests);

end.
