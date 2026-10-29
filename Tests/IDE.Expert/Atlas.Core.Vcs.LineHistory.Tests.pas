unit Atlas.Core.Vcs.LineHistory.Tests;

// Herkunft von Zeilen über Commits (#1275) ohne git und svn: Unified-Diffs
// lesen, einen Bereich rückwärts durch SVN-Revisionen verfolgen, die
// Ausgaben von git log -L, git log --no-walk, svn log --xml und
// svn log --diff (aufgezeichnet mit git 2.43 und svn 1.14) und die Aufrufe
// der Umsetzungen mit einem Prozessläufer-Ersatz.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasVcsLineHistoryTests = class
  public
    [Test]
    procedure HunkHeaderAndHunks;
    /// <summary>Hinzufügen im Bereich und Löschen zwischen zwei Zeilen ändern ihn, Ränder nicht.</summary>
    [Test]
    procedure TouchesOnlyInsideTheRange;
    [Test]
    procedure MapBackFollowsInsertionsAndDeletions;
    /// <summary>Aufgezeichnete Ausgabe von svn log --diff, auch mit einer gelöschten Zeile aus 72 „-“ und einer
    /// leeren Nachricht.</summary>
    [Test]
    procedure SvnLogDiffParsesRevisionsAndPatches;
    [Test]
    procedure SvnTraceFindsRevisionsOfRange;
    [Test]
    procedure SvnLogXmlReadsMessages;
    [Test]
    procedure GitLineLogParsesCommitsWithPatch;
    [Test]
    procedure GitMessagesParse;
    [Test]
    procedure GitProviderRunsLineHistoryCommands;
    [Test]
    procedure SvnProviderRunsLineHistoryCommands;
    [Test]
    procedure NullProviderReportsOutcome;
    [Test]
    procedure ConsoleTextFallsBackToAnsi;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Internals.Text,
  Atlas.Core.Vcs.Internals.LineTrace,
  Atlas.Core.Vcs.Internals.GitParser,
  Atlas.Core.Vcs.Internals.SvnParser,
  Atlas.Core.Vcs.Providers.Git,
  Atlas.Core.Vcs.Providers.Svn,
  Atlas.Core.Vcs.Providers.Null;

const
  cSep = '------------------------------------------------------------------------';
  // svn log --diff -l 10 f.pas@ (svn 1.14.3): r5 löscht eine Zeile aus 72 „-“ und hat eine leere Nachricht.
  cSvnLogDiff =
    cSep + #10 +
    'r5 | root | 2026-10-28 15:57:27 +0000 (Wed, 28 Oct 2026) | 1 line' + #10 + #10 + #10 + #10 +
    'Index: f.pas' + #10 +
    '===================================================================' + #10 +
    '--- f.pas'#9'(revision 4)' + #10 +
    '+++ f.pas'#9'(revision 5)' + #10 +
    '@@ -1,5 +1,6 @@' + #10 + ' a' + #10 + ' B' + #10 + ' c' + #10 + cSep + #10 + '+X' + #10 + ' e' + #10 +
    '+f' + #10 + #10 +
    cSep + #10 +
    'r4 | root | 2026-10-28 15:57:27 +0000 (Wed, 28 Oct 2026) | 1 line' + #10 + #10 + 'Strich' + #10 + #10 +
    'Index: f.pas' + #10 +
    '===================================================================' + #10 +
    '--- f.pas'#9'(revision 3)' + #10 +
    '+++ f.pas'#9'(revision 4)' + #10 +
    '@@ -1,5 +1,5 @@' + #10 + ' a' + #10 + ' B' + #10 + ' c' + #10 + '-d' + #10 +
    '+-----------------------------------------------------------------------' + #10 + ' e' + #10 + #10 +
    cSep + #10 +
    'r3 | root | 2026-10-28 15:57:27 +0000 (Wed, 28 Oct 2026) | 2 Zeilen' + #10 + #10 + 'ATL-2 b groß' + #10 +
    'Siehe auch ATL-3' + #10 + #10 +
    'Index: f.pas' + #10 +
    '===================================================================' + #10 +
    '--- f.pas'#9'(revision 2)' + #10 +
    '+++ f.pas'#9'(revision 3)' + #10 +
    '@@ -1,5 +1,5 @@' + #10 + ' a' + #10 + '-b' + #10 + '+B' + #10 + ' c' + #10 + ' d' + #10 + ' e' + #10 + #10 +
    cSep + #10 +
    'r2 | root | 2026-10-28 15:57:23 +0000 (Wed, 28 Oct 2026) | 1 line' + #10 + #10 + 'ATL-1 Anfang' + #10 + #10 +
    'Index: f.pas' + #10 +
    '===================================================================' + #10 +
    '--- f.pas'#9'(nonexistent)' + #10 +
    '+++ f.pas'#9'(revision 2)' + #10 +
    '@@ -0,0 +1,5 @@' + #10 + '+a' + #10 + '+b' + #10 + '+c' + #10 + '+d' + #10 + '+e' + #10 + #10 +
    cSep + #10;
  // svn log --xml -c 3,2 f.pas@
  cSvnLogXml =
    '<?xml version="1.0" encoding="UTF-8"?>' + #10 + '<log>' + #10 + '<logentry' + #10 + '   revision="3">' + #10 +
    '<author>root</author>' + #10 + '<date>2026-10-28T15:57:27.568487Z</date>' + #10 +
    '<msg>ATL-2 b groß' + #10 + 'Siehe auch ATL-3</msg>' + #10 + '</logentry>' + #10 + '<logentry' + #10 +
    '   revision="2">' + #10 + '<author>root</author>' + #10 + '<date>2026-10-28T15:57:23.231934Z</date>' + #10 +
    '<msg>ATL-1 Anfang</msg>' + #10 + '</logentry>' + #10 + '</log>' + #10;
  cHashA = '2e17e3b0f83577f8a4a215a8ed44a1fc66f22d59';
  cHashB = '23321769fdfee7b20ebb1de4065b1ad1d60eb6ab';
  // git log --format=<LineLogFormat> --max-count=5 --no-ext-diff -L1,3:f.pas (git 2.43)
  cGitLineLog =
    #$1E + cHashA + #$1F'anna'#$1F'1793203000'#$1F'ATL-2 b groß' + #10 + #10 + 'Siehe auch ATL-3' + #10 +
    #$1F + #10 + #10 + 'diff --git a/f.pas b/f.pas' + #10 + '--- a/f.pas' + #10 + '+++ b/f.pas' + #10 +
    '@@ -1,3 +1,3 @@' + #10 + ' a' + #10 + '-b' + #10 + '+B' + #10 + ' c' + #10 +
    #$1E + cHashB + #$1F'anna'#$1F'1793203000'#$1F'ATL-1 Anfang' + #10 + #$1F + #10 + #10 +
    'diff --git a/f.pas b/f.pas' + #10 + '--- /dev/null' + #10 + '+++ b/f.pas' + #10 + '@@ -0,0 +1,3 @@' + #10 +
    '+a' + #10 + '+b' + #10 + '+c' + #10;
  // git log --no-walk=unsorted --format=<MessageFormat> <A> <B> --
  cGitMessages =
    #$1E + cHashA + #$1F'ATL-2 b groß' + #10 + #10 + 'Siehe auch ATL-3' + #10 + #10 +
    #$1E + cHashB + #$1F'ATL-1 Anfang' + #10 + #10;

type
  /// <summary>Antwortet nach einem Teil der Befehlszeile (erster passender Eintrag).</summary>
  TLineRunner = class(TInterfacedObject, IAtlasVcsRunner)
  public
    Calls: TArray<string>;
    Parts: TArray<string>;
    Answers: TArray<TBytes>;
    procedure Answer(const APart, AText: string); overload;
    procedure Answer(const APart: string; const ABytes: TBytes); overload;
    function Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
      ATimeoutMs: Cardinal): TAtlasVcsRunResult;
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

function Lines(const AText: string): TArray<string>;
begin
  Result := AText.Split([#10]);
end;

{ TLineRunner }

procedure TLineRunner.Answer(const APart, AText: string);
begin
  Answer(APart, TEncoding.UTF8.GetBytes(AText));
end;

procedure TLineRunner.Answer(const APart: string; const ABytes: TBytes);
begin
  Parts := Parts + [APart];
  SetLength(Answers, Length(Answers) + 1);
  Answers[High(Answers)] := ABytes;
end;

function TLineRunner.Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
  ATimeoutMs: Cardinal): TAtlasVcsRunResult;
var
  mIndex: Integer;
  mLine: string;
begin
  mLine := string.Join(' ', AArguments);
  Calls := Calls + [mLine];
  Result := TAtlasVcsRunResult.Make(TAtlasVcsOutcome.Ok, 0, nil);
  for mIndex := 0 to High(Parts) do
    if Pos(Parts[mIndex], mLine) > 0 then
    begin
      Result.Output := Answers[mIndex];
      Break;
    end;
end;

{ TAtlasVcsLineHistoryTests }

procedure TAtlasVcsLineHistoryTests.HunkHeaderAndHunks;
var
  mHunk: TAtlasVcsHunk;
  mHunks: TArray<TAtlasVcsHunk>;
begin
  Assert.IsTrue(TAtlasVcsLineTrace.ParseHunkHeader('@@ -10,7 +12,8 @@ procedure TKunde.Laden;', mHunk));
  Assert.AreEqual(10, mHunk.OldStart);
  Assert.AreEqual(7, mHunk.OldCount);
  Assert.AreEqual(12, mHunk.NewStart);
  Assert.AreEqual(8, mHunk.NewCount);
  Assert.IsTrue(TAtlasVcsLineTrace.ParseHunkHeader('@@ -3 +3 @@', mHunk), 'ohne Anzahl');
  Assert.AreEqual(1, mHunk.OldCount);
  Assert.AreEqual(1, mHunk.NewCount);
  Assert.IsFalse(TAtlasVcsLineTrace.ParseHunkHeader('## -0,0 +1 ##', mHunk), 'Eigenschaft, kein Block');
  Assert.IsFalse(TAtlasVcsLineTrace.ParseHunkHeader('@@ -a,1 +1 @@', mHunk));
  mHunks := TAtlasVcsLineTrace.ParseHunks(TArray<string>.Create('Index: a.pas', '--- a.pas', '+++ a.pas',
    '@@ -1,2 +1,2 @@', ' x', '-y', '+Y', '\ No newline at end of file', '@@ -9,0 +10,1 @@', '+neu',
    'Property changes on: a.pas'));
  Assert.AreEqual(2, Integer(Length(mHunks)));
  Assert.AreEqual(3, Integer(Length(mHunks[0].Lines)), '„\ No newline“ entfällt');
  Assert.AreEqual('+Y', mHunks[0].Lines[2]);
  Assert.AreEqual(1, Integer(Length(mHunks[1].Lines)), 'Block endet nach seinen Größen');
end;

procedure TAtlasVcsLineHistoryTests.TouchesOnlyInsideTheRange;
var
  mHunks: TArray<TAtlasVcsHunk>;
begin
  // Alt: 1 a, 2 b, 3 c, 4 d, 5 e. Neu: 1 a, 2 b, 3 X, 4 c, 5 e (X eingefügt, d gelöscht).
  mHunks := TAtlasVcsLineTrace.ParseHunks(TArray<string>.Create('@@ -1,5 +1,5 @@', ' a', ' b', '+X', ' c', '-d',
    ' e'));
  Assert.IsTrue(TAtlasVcsLineTrace.Touches(mHunks, 3, 3), 'eingefügte Zeile');
  Assert.IsTrue(TAtlasVcsLineTrace.Touches(mHunks, 1, 5), 'ganzer Bereich');
  Assert.IsTrue(TAtlasVcsLineTrace.Touches(mHunks, 4, 5), 'gelöscht zwischen c und e');
  Assert.IsFalse(TAtlasVcsLineTrace.Touches(mHunks, 1, 2), 'davor unverändert');
  Assert.IsFalse(TAtlasVcsLineTrace.Touches(mHunks, 5, 5), 'gelöscht direkt vor dem Bereich zählt nicht');
  Assert.IsFalse(TAtlasVcsLineTrace.Touches(mHunks, 4, 4), 'gelöscht direkt dahinter zählt nicht');
end;

procedure TAtlasVcsLineHistoryTests.MapBackFollowsInsertionsAndDeletions;
var
  mHunks: TArray<TAtlasVcsHunk>;
  mFirst, mLast: Integer;
begin
  // Alt: 1..10; neu: zwei Zeilen nach 2 eingefügt, Zeile 7 gelöscht.
  mHunks := TAtlasVcsLineTrace.ParseHunks(TArray<string>.Create('@@ -2,0 +3,2 @@', '+n1', '+n2', '@@ -7,1 +8,0 @@',
    '-sieben'));
  mFirst := 5;
  mLast := 9;
  Assert.IsTrue(TAtlasVcsLineTrace.MapBack(mHunks, mFirst, mLast));
  Assert.AreEqual(3, mFirst);
  Assert.AreEqual(8, mLast, 'nach der Löschung um eins zurück');
  mFirst := 3;
  mLast := 4;
  Assert.IsFalse(TAtlasVcsLineTrace.MapBack(mHunks, mFirst, mLast), 'ganz eingefügt: davor gab es ihn nicht');
  mFirst := 2;
  mLast := 4;
  Assert.IsTrue(TAtlasVcsLineTrace.MapBack(mHunks, mFirst, mLast));
  Assert.AreEqual(2, mFirst);
  Assert.AreEqual(2, mLast, 'eingefügte Zeilen am Ende fallen weg');
  mFirst := 20;
  mLast := 21;
  Assert.IsTrue(TAtlasVcsLineTrace.MapBack(mHunks, mFirst, mLast));
  Assert.AreEqual(19, mFirst, 'hinter allen Blöcken: +2 -1');
end;

procedure TAtlasVcsLineHistoryTests.SvnLogDiffParsesRevisionsAndPatches;
var
  mDiffs: TArray<TAtlasSvnLogDiff>;
begin
  mDiffs := TAtlasSvnParser.ParseLogDiff(cSvnLogDiff);
  Assert.AreEqual(4, Integer(Length(mDiffs)), 'die gelöschte Zeile aus „-“ beendet r5 nicht');
  Assert.AreEqual('5', mDiffs[0].Revision);
  Assert.AreEqual('Index: f.pas', mDiffs[0].Patch[0], 'leere Nachricht übersprungen');
  Assert.AreEqual(cSep, mDiffs[0].Patch[8]);
  Assert.AreEqual('+f', mDiffs[0].Patch[High(mDiffs[0].Patch)]);
  Assert.AreEqual('4', mDiffs[1].Revision);
  Assert.AreEqual('3', mDiffs[2].Revision);
  Assert.AreEqual('Index: f.pas', mDiffs[2].Patch[0], 'zwei Nachrichtenzeilen, Wort übersetzt');
  Assert.AreEqual('2', mDiffs[3].Revision);
  Assert.AreEqual(0, Integer(Length(TAtlasSvnParser.ParseLogDiff(''))));
  Assert.WillRaise(
    procedure
    begin
      TAtlasSvnParser.ParseLogDiff(cSep + #10 + 'kein Kopf' + #10);
    end, EAtlasVcsParse);
end;

procedure TAtlasVcsLineHistoryTests.SvnTraceFindsRevisionsOfRange;
var
  mDiffs: TArray<TAtlasSvnLogDiff>;
  mPatches: TArray<TArray<string>>;
  mIndex: Integer;
  mFound: TArray<Integer>;
begin
  mDiffs := TAtlasSvnParser.ParseLogDiff(cSvnLogDiff);
  SetLength(mPatches, Length(mDiffs));
  for mIndex := 0 to High(mDiffs) do
    mPatches[mIndex] := mDiffs[mIndex].Patch;
  // Zeilen 1–3 (a, B, c): r3 ändert b, r2 legt sie an; r5 und r4 ändern nur dahinter.
  mFound := TAtlasVcsLineTrace.Trace(mPatches, 1, 3);
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(2, mFound[0]);
  Assert.AreEqual(3, mFound[1]);
  // Zeile 4 (X): in r5 entstanden, ältere Revisionen zählen nicht.
  mFound := TAtlasVcsLineTrace.Trace(mPatches, 4, 4);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(0, mFound[0]);
  // Zeile 5 (e): nur r2.
  mFound := TAtlasVcsLineTrace.Trace(mPatches, 5, 5);
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(3, mFound[0]);
end;

procedure TAtlasVcsLineHistoryTests.SvnLogXmlReadsMessages;
var
  mLog: TArray<TAtlasVcsLineCommit>;
begin
  mLog := TAtlasSvnParser.ParseLog(cSvnLogXml);
  Assert.AreEqual(2, Integer(Length(mLog)));
  Assert.AreEqual('3', mLog[0].Revision);
  Assert.AreEqual('root', mLog[0].Author);
  Assert.AreEqual('ATL-2 b groß' + #10 + 'Siehe auch ATL-3', mLog[0].Message);
  Assert.AreEqual(2026, Integer(StrToInt(FormatDateTime('yyyy', mLog[0].Date))));
  Assert.AreEqual('ATL-1 Anfang', mLog[1].Message);
end;

procedure TAtlasVcsLineHistoryTests.GitLineLogParsesCommitsWithPatch;
var
  mCommits: TArray<TAtlasVcsLineCommit>;
begin
  mCommits := TAtlasGitParser.ParseLineLog(cGitLineLog);
  Assert.AreEqual(2, Integer(Length(mCommits)));
  Assert.AreEqual(cHashA, mCommits[0].Revision);
  Assert.AreEqual('anna', mCommits[0].Author);
  Assert.AreEqual('ATL-2 b groß' + #10 + #10 + 'Siehe auch ATL-3', mCommits[0].Message);
  Assert.IsTrue(mCommits[0].Date > 0);
  Assert.AreEqual('diff --git a/f.pas b/f.pas', mCommits[0].Patch[0], 'Leerzeilen vorn entfallen');
  Assert.AreEqual(' c', mCommits[0].Patch[High(mCommits[0].Patch)]);
  Assert.AreEqual('+c', mCommits[1].Patch[High(mCommits[1].Patch)], 'Leerzeilen hinten entfallen');
  Assert.AreEqual(0, Integer(Length(TAtlasGitParser.ParseLineLog(''))));
  Assert.WillRaise(
    procedure
    begin
      TAtlasGitParser.ParseLineLog(#$1E'abc'#$1F'x');
    end, EAtlasVcsParse);
end;

procedure TAtlasVcsLineHistoryTests.GitMessagesParse;
var
  mMessages: TArray<TAtlasVcsRevisionMessage>;
begin
  mMessages := TAtlasGitParser.ParseMessages(cGitMessages);
  Assert.AreEqual(2, Integer(Length(mMessages)));
  Assert.AreEqual(cHashA, mMessages[0].Revision);
  Assert.AreEqual('ATL-2 b groß' + #10 + #10 + 'Siehe auch ATL-3', mMessages[0].Message);
  Assert.AreEqual('ATL-1 Anfang', mMessages[1].Message);
end;

procedure TAtlasVcsLineHistoryTests.GitProviderRunsLineHistoryCommands;
const
  cPrefix = '--no-optional-locks -c core.quotepath=off -c color.ui=false ';
var
  mRunner: TLineRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mHistory: IAtlasVcsLineHistory;
  mCommits: TArray<TAtlasVcsLineCommit>;
  mMessages: TArray<TAtlasVcsRevisionMessage>;
  mRevisions: TArray<string>;
  mIndex: Integer;
begin
  mRunner := TLineRunner.Create;
  mRunnerRef := mRunner;
  mRunner.Answer('-L', cGitLineLog);
  mRunner.Answer('--no-walk', cGitMessages);
  mVcs := TAtlasGitVersionControl.Create(Root, mRunnerRef, 'git.exe', 5000);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsLineHistory, mHistory), 'Git bietet IAtlasVcsLineHistory');
  Assert.IsTrue(mHistory.LineHistory(Under('src/f.pas'), 1, 3, 200, mCommits) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(cPrefix + 'log --format=' + TAtlasGitParser.LineLogFormat + ' --max-count=200 --no-ext-diff ' +
    '-L1,3:src/f.pas', mRunner.Calls[0]);
  Assert.AreEqual(2, Integer(Length(mCommits)));
  Assert.IsTrue(mHistory.Messages(Under('src/f.pas'), TArray<string>.Create(cHashA, cHashB), mMessages) =
    TAtlasVcsOutcome.Ok);
  Assert.AreEqual(cPrefix + 'log --no-walk=unsorted --format=' + TAtlasGitParser.MessageFormat + ' ' + cHashA + ' ' +
    cHashB + ' --', mRunner.Calls[1]);
  Assert.AreEqual(2, Integer(Length(mMessages)));
  // Viele Commits: je MessageBatch ein Aufruf.
  SetLength(mRevisions, TAtlasGitVersionControl.MessageBatch + 1);
  for mIndex := 0 to High(mRevisions) do
    mRevisions[mIndex] := cHashA;
  Assert.IsTrue(mHistory.Messages(Under('src/f.pas'), mRevisions, mMessages) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(4, Integer(Length(mRunner.Calls)));
  // Ohne Commits kein Prozess; Optionen und ungültige Bereiche starten keinen.
  Assert.IsTrue(mHistory.Messages(Under('src/f.pas'), nil, mMessages) = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(mHistory.Messages(Under('src/f.pas'), TArray<string>.Create('--all'), mMessages) =
    TAtlasVcsOutcome.Failed);
  Assert.IsTrue(mHistory.LineHistory(Under('src/f.pas'), 5, 4, 200, mCommits) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(mHistory.LineHistory(Under('src/f.pas'), 0, 4, 200, mCommits) = TAtlasVcsOutcome.Failed);
  Assert.IsTrue(mHistory.LineHistory('/anderswo/f.pas', 1, 4, 200, mCommits) = TAtlasVcsOutcome.Failed);
  Assert.AreEqual(4, Integer(Length(mRunner.Calls)));
end;

procedure TAtlasVcsLineHistoryTests.SvnProviderRunsLineHistoryCommands;
var
  mRunner: TLineRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mHistory: IAtlasVcsLineHistory;
  mCommits: TArray<TAtlasVcsLineCommit>;
  mMessages: TArray<TAtlasVcsRevisionMessage>;
begin
  mRunner := TLineRunner.Create;
  mRunnerRef := mRunner;
  mRunner.Answer('--diff', cSvnLogDiff);
  mRunner.Answer('--xml', cSvnLogXml);
  mVcs := TAtlasSvnVersionControl.Create(Root, mRunnerRef, 'svn.exe', 5000);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsLineHistory, mHistory), 'SVN bietet IAtlasVcsLineHistory');
  Assert.IsTrue(mHistory.LineHistory(Under('f.pas'), 1, 3, 200, mCommits) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('log --xml -l 200 f.pas@ --non-interactive', mRunner.Calls[0]);
  Assert.AreEqual('log --diff -l 200 f.pas@ --non-interactive', mRunner.Calls[1]);
  Assert.AreEqual(2, Integer(Length(mCommits)), 'r3 und r2 ändern die Zeilen 1–3');
  Assert.AreEqual('3', mCommits[0].Revision);
  Assert.AreEqual('ATL-2 b groß' + #10 + 'Siehe auch ATL-3', mCommits[0].Message);
  Assert.AreEqual('Index: f.pas', mCommits[0].Patch[0]);
  Assert.AreEqual('2', mCommits[1].Revision);
  Assert.IsTrue(mHistory.Messages(Under('f.pas'), TArray<string>.Create('3', '2'), mMessages) =
    TAtlasVcsOutcome.Ok);
  Assert.AreEqual('log --xml -c 3,2 f.pas@ --non-interactive', mRunner.Calls[2]);
  Assert.AreEqual(2, Integer(Length(mMessages)));
  Assert.AreEqual('ATL-1 Anfang', mMessages[1].Message);
  Assert.IsTrue(mHistory.Messages(Under('f.pas'), TArray<string>.Create('-r'), mMessages) =
    TAtlasVcsOutcome.Failed);
  Assert.AreEqual(3, Integer(Length(mRunner.Calls)));
end;

procedure TAtlasVcsLineHistoryTests.NullProviderReportsOutcome;
var
  mVcs: IAtlasVersionControl;
  mHistory: IAtlasVcsLineHistory;
  mCommits: TArray<TAtlasVcsLineCommit>;
  mMessages: TArray<TAtlasVcsRevisionMessage>;
begin
  mVcs := TAtlasNullVersionControl.Create(TAtlasVcsOutcome.ToolMissing);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsLineHistory, mHistory));
  Assert.IsTrue(mHistory.LineHistory(Under('f.pas'), 1, 3, 200, mCommits) = TAtlasVcsOutcome.ToolMissing);
  Assert.AreEqual(0, Integer(Length(mCommits)));
  Assert.IsTrue(mHistory.Messages(Under('f.pas'), TArray<string>.Create('3'), mMessages) =
    TAtlasVcsOutcome.ToolMissing);
end;

procedure TAtlasVcsLineHistoryTests.ConsoleTextFallsBackToAnsi;
var
  mBytes: TBytes;
begin
  Assert.AreEqual('groß', VcsConsoleText(TEncoding.UTF8.GetBytes('groß')));
  Assert.IsTrue(VcsIsUtf8(TEncoding.UTF8.GetBytes('ATL-1 Prüfung €')));
  mBytes := TBytes.Create(Ord('g'), $F6, Ord('x'));
  Assert.IsFalse(VcsIsUtf8(mBytes), 'einzelnes Byte über $7F');
  Assert.AreEqual(3, Integer(Length(VcsConsoleText(mBytes))), 'ANSI: ein Zeichen je Byte');
  Assert.IsFalse(VcsIsUtf8(TBytes.Create($E0, $80, $80)), 'überlang');
  Assert.IsFalse(VcsIsUtf8(TBytes.Create($C3)), 'abgeschnitten');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsLineHistoryTests);

end.
