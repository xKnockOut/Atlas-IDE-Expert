unit Atlas.Core.VersionControl.Internals.GitParser.Tests;

// Tests des git-Parsers mit aufgezeichneten Ausgaben (git 2.43): Status, Blame, Branches, Stashes, Log, eingehende
// Commits und Verlauf.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Lesen aufgezeichneter git-Ausgaben.</summary>
  [TestFixture]
  [Category('Atlas.IDE.VersionControl')]
  TAtlasVcsGitParserTests = class
  public
    [Test]
    procedure GitStatusReadsBranchCommitAndChanges;
    [Test]
    procedure GitStatusReadsUpstreamDetachedAndInitial;
    [Test]
    procedure GitStatusReadsConflictsAndRejectsUnknown;
    [Test]
    procedure GitBlameReadsCommitsAndUncommittedLines;
    [Test]
    procedure GitParsesBranchesStashesLogAndNameStatus;
    [Test]
    procedure GitParserRejectsBrokenLocalWork;
    [Test]
    procedure GitIncomingParsesCommitsWithFiles;
    [Test]
    procedure GitParsesHistoryRefsAndDistance;
    [Test]
    procedure GitHistoryRejectsBrokenOutput;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Internals.Text,
  Atlas.Core.VersionControl.Internals.GitParser,
  Atlas.Core.VersionControl.TestSupport;

procedure TAtlasVcsGitParserTests.GitStatusReadsBranchCommitAndChanges;
var
  mHead: TAtlasVcsHead;
  mChanges: TArray<TAtlasVcsChange>;
begin
  TAtlasGitParser.ParseStatus(GitStatusSample, Root, mHead, mChanges);
  Assert.AreEqual('main', mHead.Branch);
  Assert.AreEqual(cHash1, mHead.Revision);
  Assert.AreEqual('1979e3d', mHead.ShortRevision(TAtlasVcsKind.Git));
  Assert.IsFalse(mHead.Detached);
  Assert.AreEqual('', mHead.Upstream);
  Assert.AreEqual(-1, mHead.Ahead, 'ohne verfolgten Branch unbekannt');
  Assert.AreEqual(5, Integer(Length(mChanges)));
  Assert.AreEqual(Under('A.pas'), mChanges[0].Path);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Modified, mChanges[0].Kind);
  Assert.IsFalse(mChanges[0].Staged);
  Assert.IsTrue(mChanges[0].Unstaged);
  Assert.AreEqual(Under('C.pas'), mChanges[1].Path);
  Assert.AreEqual(Under('B.pas'), mChanges[1].OldPath, 'alter Name als eigener Eintrag');
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Renamed, mChanges[1].Kind);
  Assert.IsTrue(mChanges[1].Staged);
  Assert.IsFalse(mChanges[1].Unstaged);
  Assert.AreEqual(Under(#$00DC + ' m.pas'), mChanges[2].Path, 'Umlaut und Leerzeichen unverändert');
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Deleted, mChanges[2].Kind);
  Assert.AreEqual(Under('Neu.pas'), mChanges[3].Path);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Untracked, mChanges[3].Kind);
  Assert.AreEqual(Under('sub/Q.pas'), mChanges[4].Path);
end;
procedure TAtlasVcsGitParserTests.GitStatusReadsUpstreamDetachedAndInitial;
var
  mHead: TAtlasVcsHead;
  mChanges: TArray<TAtlasVcsChange>;
begin
  TAtlasGitParser.ParseStatus('# branch.oid ' + cHash1 + #0'# branch.head feature/x'#0 +
    '# branch.upstream origin/feature/x'#0'# branch.ab +2 -3'#0, Root, mHead, mChanges);
  Assert.AreEqual('feature/x', mHead.Branch);
  Assert.AreEqual('origin/feature/x', mHead.Upstream);
  Assert.AreEqual(2, mHead.Ahead);
  Assert.AreEqual(3, mHead.Behind);
  Assert.AreEqual(0, Integer(Length(mChanges)));
  TAtlasGitParser.ParseStatus('# branch.oid ' + cHash1 + #0'# branch.head (detached)'#0, Root, mHead, mChanges);
  Assert.IsTrue(mHead.Detached);
  Assert.AreEqual('', mHead.Branch);
  Assert.AreEqual(cHash1, mHead.Revision);
  TAtlasGitParser.ParseStatus('# branch.oid (initial)'#0'# branch.head main'#0'? A.pas'#0, Root, mHead, mChanges);
  Assert.AreEqual('', mHead.Revision, 'vor dem ersten Commit');
  Assert.AreEqual('main', mHead.Branch);
  Assert.AreEqual(1, Integer(Length(mChanges)));
  // Ohne -z (Zeilen) wird ebenso gelesen.
  TAtlasGitParser.ParseStatus('# branch.oid ' + cHash1 + #10'# branch.head main'#10, Root, mHead, mChanges);
  Assert.AreEqual('main', mHead.Branch);
end;
procedure TAtlasVcsGitParserTests.GitStatusReadsConflictsAndRejectsUnknown;
var
  mHead: TAtlasVcsHead;
  mChanges: TArray<TAtlasVcsChange>;
begin
  TAtlasGitParser.ParseStatus('# branch.head main'#0 +
    'u UU N... 100644 100644 100644 100644 ' + cHash1 + ' ' + cHash2 + ' ' + cHash1 + ' src/Konflikt Datei.pas'#0 +
    '1 A. N... 000000 100644 100644 0000000000000000000000000000000000000000 ' + cHash2 + ' Neu.pas'#0 +
    '1 MM N... 100644 100644 100644 ' + cHash1 + ' ' + cHash2 + ' Beides.pas'#0 +
    '1 .T N... 100644 100644 120000 ' + cHash1 + ' ' + cHash1 + ' Link.pas'#0 +
    '! ignoriert.dcu'#0, Root, mHead, mChanges);
  Assert.AreEqual(4, Integer(Length(mChanges)), 'ignorierte Dateien entfallen');
  Assert.AreEqual(Under('src/Konflikt Datei.pas'), mChanges[0].Path);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Conflicted, mChanges[0].Kind);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Added, mChanges[1].Kind);
  Assert.IsTrue(mChanges[1].Staged);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Modified, mChanges[2].Kind);
  Assert.IsTrue(mChanges[2].Staged and mChanges[2].Unstaged);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.TypeChanged, mChanges[3].Kind);
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseStatus('X unbekannt'#0, Root, mHead, mChanges);
    end, EAtlasVcsParse);
end;
procedure TAtlasVcsGitParserTests.GitBlameReadsCommitsAndUncommittedLines;
var
  mLines: TArray<TAtlasVcsBlameLine>;
begin
  // Aufgezeichnet mit git 2.43: "git blame --porcelain -- A.pas" mit einer neuen, noch nicht übernommenen Zeile.
  mLines := TAtlasGitParser.ParseBlame(
    cHash1 + ' 1 1 2'#10 +
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
    cHash1 + ' 2 2'#10 +
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
    'previous ' + cHash1 + ' A.pas'#10 +
    'filename A.pas'#10 +
    #9'z'#10);
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.AreEqual(1, mLines[0].Line);
  Assert.AreEqual(cHash1, mLines[0].Revision);
  Assert.AreEqual('Ada', mLines[0].Author);
  Assert.AreEqual('Erster Stand', mLines[0].Summary);
  Assert.AreEqual('2026-10-15 12:22:39', FormatDateTime('yyyy-mm-dd hh:nn:ss', mLines[0].Date));
  Assert.AreEqual(2, mLines[1].Line);
  Assert.AreEqual('Ada', mLines[1].Author, 'Angaben des Commits nur beim ersten Auftreten');
  Assert.AreEqual('Erster Stand', mLines[1].Summary);
  Assert.AreEqual(3, mLines[2].Line);
  Assert.IsTrue(mLines[2].Uncommitted);
  Assert.AreEqual('', mLines[2].Author, 'nicht übernommen: kein Autor');
  Assert.IsFalse(mLines[0].Uncommitted);
  Assert.AreEqual(0, Integer(Length(TAtlasGitParser.ParseBlame(''))));
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseBlame('kein Kopf'#10);
    end, EAtlasVcsParse);
end;
/// <summary>#762: for-each-ref wie von git 2.43.</summary>
procedure AssertGitBranches;
var
  mBranches: TArray<TAtlasVcsBranch>;
begin
  // #762: Ausgaben wie von git 2.43 (for-each-ref mit %00, "%(HEAD)" ist "*" oder " ").
  mBranches := TAtlasGitParser.ParseBranches(
    'lokal'#0#0#0#0#0'1792071091'#0' '#10 +
    'main'#0'origin/main'#0'origin'#0'refs/heads/main'#0'ahead 2'#0'1792071092'#0'*'#10 +
    'dev'#0'origin/dev'#0'origin'#0'refs/heads/dev'#0'ahead 1, behind 4'#0'1792071000'#0' '#10 +
    'alt'#0'origin/alt'#0'origin'#0'refs/heads/alt'#0'gone'#0'1792070000'#0' '#10 +
    'sync'#0'origin/sync'#0'origin'#0'refs/heads/sync'#0#0'1792070000'#0' '#10);
  Assert.AreEqual(5, Integer(Length(mBranches)));
  Assert.AreEqual('lokal', mBranches[0].Name);
  Assert.AreEqual('', mBranches[0].Upstream);
  Assert.IsFalse(mBranches[0].Tracked);
  Assert.AreEqual(-1, mBranches[0].Ahead, 'ohne Upstream unbekannt');
  Assert.IsFalse(mBranches[0].Current);
  Assert.IsTrue(mBranches[0].TipDate > 0);
  Assert.AreEqual('origin/main', mBranches[1].Upstream);
  Assert.AreEqual('origin', mBranches[1].Remote);
  Assert.AreEqual('refs/heads/main', mBranches[1].RemoteRef);
  Assert.AreEqual(2, mBranches[1].Ahead);
  Assert.AreEqual(0, mBranches[1].Behind);
  Assert.IsTrue(mBranches[1].Current);
  Assert.IsTrue(mBranches[1].Tracked);
  Assert.AreEqual(1, mBranches[2].Ahead);
  Assert.AreEqual(4, mBranches[2].Behind);
  Assert.IsTrue(mBranches[3].Gone, 'Upstream auf dem Server gelöscht');
  Assert.IsFalse(mBranches[3].Tracked);
  Assert.AreEqual(0, mBranches[4].Ahead, 'gleichauf');
  Assert.AreEqual(0, mBranches[4].Behind);
  Assert.AreEqual(0, Integer(Length(TAtlasGitParser.ParseBranches(''))));
end;
/// <summary>stash list mit Branch und Nachricht ohne WIP-Vorspann.</summary>
procedure AssertGitStashes;
var
  mStashes: TArray<TAtlasVcsStash>;
begin
  mStashes := TAtlasGitParser.ParseStashes(
    cHash1 + #0'1792071092'#0'stash@{0}'#0'On main: Mein Name'#10 +
    cHash2 + #0'1792071000'#0'stash@{1}'#0'WIP on feature/x: 9805f75 Hover-Cache: erster Wurf'#10);
  Assert.AreEqual(2, Integer(Length(mStashes)));
  Assert.AreEqual(cHash1, mStashes[0].Hash);
  Assert.AreEqual('stash@{0}', mStashes[0].Ref);
  Assert.AreEqual('main', mStashes[0].Branch);
  Assert.AreEqual('Mein Name', mStashes[0].Message);
  Assert.AreEqual('feature/x', mStashes[1].Branch);
  Assert.AreEqual('Hover-Cache: erster Wurf', mStashes[1].Message, 'ohne "WIP on …:" und Hash');
  Assert.IsTrue(mStashes[1].Date < mStashes[0].Date);
end;
procedure TAtlasVcsGitParserTests.GitParsesBranchesStashesLogAndNameStatus;
var
  mCommits: TArray<TAtlasVcsCommit>;
  mChanges: TArray<TAtlasVcsChange>;
begin
  AssertGitBranches;

  AssertGitStashes;

  mCommits := TAtlasGitParser.ParseLog(cHash1 + #0'1792071091'#0'vier'#10 + cHash2 + #0'1792071000'#0#10);
  Assert.AreEqual(2, Integer(Length(mCommits)));
  Assert.AreEqual('vier', mCommits[0].Summary);
  Assert.AreEqual(Copy(cHash1, 1, 7), mCommits[0].ShortHash);
  Assert.AreEqual('', mCommits[1].Summary, 'leere Nachricht');
  Assert.IsTrue(mCommits[1].Date < mCommits[0].Date);

  mChanges := TAtlasGitParser.ParseNameStatus('M'#0'src/A.pas'#0'A'#0'Neu.pas'#0'D'#0'Weg.pas'#0 +
    'R100'#0'Alt.pas'#0'Umbenannt.pas'#0, Root);
  Assert.AreEqual(4, Integer(Length(mChanges)));
  Assert.AreEqual(Under('src/A.pas'), mChanges[0].Path);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Modified, mChanges[0].Kind);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Added, mChanges[1].Kind);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Deleted, mChanges[2].Kind);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Renamed, mChanges[3].Kind);
  Assert.AreEqual(Under('Umbenannt.pas'), mChanges[3].Path);
  Assert.AreEqual(Under('Alt.pas'), mChanges[3].OldPath);

  Assert.AreEqual(2, Integer(Length(TAtlasGitParser.ParseLines('origin'#10'upstream'#13#10#10))));
end;
procedure TAtlasVcsGitParserTests.GitParserRejectsBrokenLocalWork;
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
procedure TAtlasVcsGitParserTests.GitIncomingParsesCommitsWithFiles;
var
  mCommits: TArray<TAtlasVcsIncomingCommit>;
begin
  // git log --format=%x1e%H%x00%ct%x00%an%x00%s --name-only -z: Trenner, Kopf mit NUL, Zeilenende, Dateien mit NUL.
  mCommits := TAtlasGitParser.ParseIncoming(#$1E + cHash1 + #0'1792071092'#0'Eva Muster'#0'Kunde: Prüfung'#0#10 +
    'src/Kunde.pas'#0'Neu.pas'#0#10 + #$1E + cHash2 + #0'1792071000'#0'Max'#0'Merge branch x'#0#10, Root);
  Assert.AreEqual(2, Integer(Length(mCommits)));
  Assert.AreEqual(cHash1, mCommits[0].Hash);
  Assert.AreEqual(Copy(cHash1, 1, 7), mCommits[0].ShortHash);
  Assert.AreEqual('Eva Muster', mCommits[0].Author);
  Assert.AreEqual('Kunde: Prüfung', mCommits[0].Summary);
  Assert.AreEqual(2, Integer(Length(mCommits[0].Files)));
  Assert.AreEqual(Under('src/Kunde.pas'), mCommits[0].Files[0], 'vollständiger Pfad');
  Assert.AreEqual(Under('Neu.pas'), mCommits[0].Files[1]);
  Assert.IsTrue(mCommits[1].Date < mCommits[0].Date);
  Assert.AreEqual(0, Integer(Length(mCommits[1].Files)), 'Merge ohne Dateien');
  Assert.AreEqual(0, Integer(Length(TAtlasGitParser.ParseIncoming('', Root))), 'nichts Neues');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseIncoming(#$1E'kurz'#0'1'#0, Root);
    end, EAtlasVcsParse);
end;
procedure TAtlasVcsGitParserTests.GitParsesHistoryRefsAndDistance;
var
  mEntries: TArray<TAtlasVcsLogEntry>;
  mRefs: TArray<TAtlasVcsRef>;
  mAhead, mBehind: Integer;
begin
  mEntries := TAtlasGitParser.ParseHistory(cGitHistorySample, Root);
  Assert.AreEqual(2, Integer(Length(mEntries)));
  Assert.AreEqual('28358feaf94440dbfe2fcc3aa2cb742e2d972f37', mEntries[0].Revision);
  Assert.AreEqual('28358fe', mEntries[0].ShortRevision(TAtlasVcsKind.Git));
  Assert.AreEqual('Marco B', mEntries[0].Author);
  Assert.AreEqual('ATL-12: weiter', mEntries[0].Summary);
  Assert.AreEqual(Double(VcsUnixToDate(1761603600)), Double(mEntries[0].Date), 1 / 86400);
  Assert.AreEqual(3, Integer(Length(mEntries[0].Files)), 'Zeilenende vor der ersten Art zählt nicht');
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Modified, mEntries[0].Files[0].Kind);
  Assert.AreEqual('A.pas', mEntries[0].Files[0].RepositoryPath);
  Assert.AreEqual(Under('A.pas'), mEntries[0].Files[0].Path);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Added, mEntries[0].Files[1].Kind);
  Assert.AreEqual<TAtlasVcsChangeKind>(TAtlasVcsChangeKind.Deleted, mEntries[0].Files[2].Kind);
  Assert.AreEqual(Under('src/B.pas'), mEntries[0].Files[2].Path);
  // Mehrzeilige Nachricht: ganz in Message, erste Zeile als Betreff.
  Assert.AreEqual('ATL-12 Erster Stand', mEntries[1].Summary);
  Assert.AreEqual('ATL-12 Erster Stand'#10#10'Zweite Zeile', mEntries[1].Message);
  Assert.AreEqual(2, Integer(Length(mEntries[1].Files)));
  Assert.AreEqual(0, Integer(Length(TAtlasGitParser.ParseHistory('', Root))), 'nichts gefunden');

  mRefs := TAtlasGitParser.ParseRefs(
    'refs/heads/main'#0'1761600000'#0' '#10 +
    'refs/heads/feature/ATL-12-tracker'#0'1761603600'#0'*'#10 +
    'refs/remotes/origin/HEAD'#0'1761600000'#0' '#10 +
    'refs/remotes/origin/feature/ATL-12-tracker'#0'1761603000'#0' '#10 +
    'refs/tags/v1'#0'1761600000'#0' '#10);
  Assert.AreEqual(3, Integer(Length(mRefs)), 'origin/HEAD und Tags entfallen');
  Assert.AreEqual('main', mRefs[0].Name);
  Assert.IsFalse(mRefs[0].Current);
  Assert.IsFalse(mRefs[0].Remote);
  Assert.AreEqual('feature/ATL-12-tracker', mRefs[1].LocalName);
  Assert.IsTrue(mRefs[1].Current, 'HEAD zeigt dorthin');
  Assert.IsTrue(mRefs[2].Remote);
  Assert.AreEqual('origin/feature/ATL-12-tracker', mRefs[2].Name);
  Assert.AreEqual('feature/ATL-12-tracker', mRefs[2].LocalName, 'ohne Remote zum Wechseln');
  Assert.AreEqual(Double(VcsUnixToDate(1761603000)), Double(mRefs[2].TipDate), 1 / 86400);

  // Links der Rückstand, rechts der Vorsprung.
  TAtlasGitParser.ParseDistance('3'#9'5'#10, mAhead, mBehind);
  Assert.AreEqual(5, mAhead);
  Assert.AreEqual(3, mBehind);
end;
procedure TAtlasVcsGitParserTests.GitHistoryRejectsBrokenOutput;
var
  mAhead, mBehind: Integer;
begin
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseHistory(#$1E'abc'#0'1'#0'x'#0'm', Root);
    end, EAtlasVcsParse, 'Hash zu kurz');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseHistory(#$1E + cHash1 + #0'1'#0'x'#0'm'#10#0#10'M'#0, Root);
    end, EAtlasVcsParse, 'Pfad fehlt');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseHistory(#$1E + cHash1 + #0'1'#0'x'#0'm'#10#0#10'X'#0'A.pas'#0, Root);
    end, EAtlasVcsParse, 'Art unbekannt');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseRefs('refs/heads/main'#10);
    end, EAtlasVcsParse, 'Felder fehlen');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseDistance('fatal', mAhead, mBehind);
    end, EAtlasVcsParse);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsGitParserTests);

end.
