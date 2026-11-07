unit Atlas.Core.Vcs.Internals.GitParser.Tests;

// Tests des git-Parsers mit aufgezeichneten Ausgaben (git 2.43): Status, Blame, Branches, Stashes, Log, eingehende Commits und Verlauf.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Lesen aufgezeichneter git-Ausgaben.</summary>
  [TestFixture]
  [Category('Atlas.IDE.Vcs')]
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
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Internals.Text,
  Atlas.Core.Vcs.Internals.GitParser,
  Atlas.Core.Vcs.TestSupport;

procedure TAtlasVcsGitParserTests.GitStatusReadsBranchCommitAndChanges;
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
procedure TAtlasVcsGitParserTests.GitStatusReadsUpstreamDetachedAndInitial;
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
procedure TAtlasVcsGitParserTests.GitStatusReadsConflictsAndRejectsUnknown;
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
procedure TAtlasVcsGitParserTests.GitBlameReadsCommitsAndUncommittedLines;
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
    Hash1 + #0'1792071092'#0'stash@{0}'#0'On main: Mein Name'#10 +
    Hash2 + #0'1792071000'#0'stash@{1}'#0'WIP on feature/x: 9805f75 Hover-Cache: erster Wurf'#10);
  Assert.AreEqual(2, Integer(Length(mStashes)));
  Assert.AreEqual(Hash1, mStashes[0].Hash);
  Assert.AreEqual('stash@{0}', mStashes[0].Ref);
  Assert.AreEqual('main', mStashes[0].Branch);
  Assert.AreEqual('Mein Name', mStashes[0].Message);
  Assert.AreEqual('feature/x', mStashes[1].Branch);
  Assert.AreEqual('Hover-Cache: erster Wurf', mStashes[1].Message, 'ohne "WIP on …:" und Hash');
  Assert.IsTrue(mStashes[1].Date < mStashes[0].Date);
end;
procedure TAtlasVcsGitParserTests.GitParsesBranchesStashesLogAndNameStatus;
var
  Commits: TArray<TAtlasVcsCommit>;
  Changes: TArray<TAtlasVcsChange>;
begin
  AssertGitBranches;

  AssertGitStashes;

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
procedure TAtlasVcsGitParserTests.GitParsesHistoryRefsAndDistance;
var
  Entries: TArray<TAtlasVcsLogEntry>;
  Refs: TArray<TAtlasVcsRef>;
  Ahead, Behind: Integer;
begin
  Entries := TAtlasGitParser.ParseHistory(GitHistorySample, Root);
  Assert.AreEqual(2, Integer(Length(Entries)));
  Assert.AreEqual('28358feaf94440dbfe2fcc3aa2cb742e2d972f37', Entries[0].Revision);
  Assert.AreEqual('28358fe', Entries[0].ShortRevision(TAtlasVcsKind.Git));
  Assert.AreEqual('Marco B', Entries[0].Author);
  Assert.AreEqual('ATL-12: weiter', Entries[0].Summary);
  Assert.AreEqual(Double(VcsUnixToDate(1761603600)), Double(Entries[0].Date), 1 / 86400);
  Assert.AreEqual(3, Integer(Length(Entries[0].Files)), 'Zeilenende vor der ersten Art zählt nicht');
  Assert.IsTrue(Entries[0].Files[0].Kind = TAtlasVcsChangeKind.Modified);
  Assert.AreEqual('A.pas', Entries[0].Files[0].RepositoryPath);
  Assert.AreEqual(Under('A.pas'), Entries[0].Files[0].Path);
  Assert.IsTrue(Entries[0].Files[1].Kind = TAtlasVcsChangeKind.Added);
  Assert.IsTrue(Entries[0].Files[2].Kind = TAtlasVcsChangeKind.Deleted);
  Assert.AreEqual(Under('src/B.pas'), Entries[0].Files[2].Path);
  // Mehrzeilige Nachricht: ganz in Message, erste Zeile als Betreff.
  Assert.AreEqual('ATL-12 Erster Stand', Entries[1].Summary);
  Assert.AreEqual('ATL-12 Erster Stand'#10#10'Zweite Zeile', Entries[1].Message);
  Assert.AreEqual(2, Integer(Length(Entries[1].Files)));
  Assert.AreEqual(0, Integer(Length(TAtlasGitParser.ParseHistory('', Root))), 'nichts gefunden');

  Refs := TAtlasGitParser.ParseRefs(
    'refs/heads/main'#0'1761600000'#0' '#10 +
    'refs/heads/feature/ATL-12-tracker'#0'1761603600'#0'*'#10 +
    'refs/remotes/origin/HEAD'#0'1761600000'#0' '#10 +
    'refs/remotes/origin/feature/ATL-12-tracker'#0'1761603000'#0' '#10 +
    'refs/tags/v1'#0'1761600000'#0' '#10);
  Assert.AreEqual(3, Integer(Length(Refs)), 'origin/HEAD und Tags entfallen');
  Assert.AreEqual('main', Refs[0].Name);
  Assert.IsFalse(Refs[0].Current);
  Assert.IsFalse(Refs[0].Remote);
  Assert.AreEqual('feature/ATL-12-tracker', Refs[1].LocalName);
  Assert.IsTrue(Refs[1].Current, 'HEAD zeigt dorthin');
  Assert.IsTrue(Refs[2].Remote);
  Assert.AreEqual('origin/feature/ATL-12-tracker', Refs[2].Name);
  Assert.AreEqual('feature/ATL-12-tracker', Refs[2].LocalName, 'ohne Remote zum Wechseln');
  Assert.AreEqual(Double(VcsUnixToDate(1761603000)), Double(Refs[2].TipDate), 1 / 86400);

  // Links der Rückstand, rechts der Vorsprung.
  TAtlasGitParser.ParseDistance('3'#9'5'#10, Ahead, Behind);
  Assert.AreEqual(5, Ahead);
  Assert.AreEqual(3, Behind);
end;
procedure TAtlasVcsGitParserTests.GitHistoryRejectsBrokenOutput;
var
  Ahead, Behind: Integer;
begin
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseHistory(#$1E'abc'#0'1'#0'x'#0'm', Root);
    end, EAtlasVcsParse, 'Hash zu kurz');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseHistory(#$1E + Hash1 + #0'1'#0'x'#0'm'#10#0#10'M'#0, Root);
    end, EAtlasVcsParse, 'Pfad fehlt');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseHistory(#$1E + Hash1 + #0'1'#0'x'#0'm'#10#0#10'X'#0'A.pas'#0, Root);
    end, EAtlasVcsParse, 'Art unbekannt');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseRefs('refs/heads/main'#10);
    end, EAtlasVcsParse, 'Felder fehlen');
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseDistance('fatal', Ahead, Behind);
    end, EAtlasVcsParse);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsGitParserTests);

end.
