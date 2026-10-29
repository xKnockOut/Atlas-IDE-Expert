unit Atlas.Core.Tracker.BlameLinks.Tests;

// Tests der Issues in der Zeilenhistorie (#1275) ohne Editor, Netz, git und
// svn: Kennungen aus Commit-Nachrichten, Anhang für die Randanzeige,
// Gruppieren nach Kennung, Bereich der Methode am Cursor, Zuordnung des
// Puffers zum Stand im Repository und ein Benchmark über 200 SVN-Revisionen
// (Zerlegen, Rückverfolgen, Gruppieren).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBlameLinksTests = class
  public
    /// <summary>Abnahme: „ATL-123 …“ in einer Commit-Nachricht, auch mehrere je Nachricht.</summary>
    [Test]
    procedure KeysFromCommitMessages;
    [Test]
    procedure CaptionSuffixListsKeys;
    /// <summary>Abnahme: drei Issues an einer Methode, je mit Anzahl der Commits.</summary>
    [Test]
    procedure GroupCountsCommitsPerIssue;
    [Test]
    procedure GroupOrdersByNewestCommitThenKey;
    [Test]
    procedure ScopeIsInnermostMethodOrUnit;
    [Test]
    procedure RepositoryRangeSkipsUnsavedLines;
    /// <summary>History liest HEAD, ordnet den Pufferbereich zu und fragt git log -L mit den Zeilen im Repository;
    /// eine nicht übernommene Datei meldet NotCommitted.</summary>
    [Test]
    procedure HistoryUsesRepositoryLines;
    [Test]
    procedure BlameRevisionsAreDistinctAndCommitted;
    [Test]
    procedure ShortRevisionAndSubject;
    /// <summary>Abnahme: 200 Revisionen (maxRevisions) zerlegen, verfolgen und gruppieren, weit unter 5 s.</summary>
    [Test]
    [Category('Benchmark')]
    procedure SvnHistoryOf200RevisionsIsFast;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Diagnostics,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Providers.Svn,
  Atlas.Core.Vcs.Providers.Git,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.CodeLinks,
  Atlas.Core.Tracker.BlameLinks;

function YouTrack: TAtlasIssueKeyPattern;
begin
  Result := TAtlasIssueKeyPattern.ForTarget(TAtlasTrackerTarget.Create(TAtlasTrackerTarget.YouTrack,
    'https://firma.youtrack.cloud', 'ATL', ''));
end;

function Commit(const ARevision, AMessage: string; ADay: Integer): TAtlasVcsLineCommit;
begin
  Result := Default(TAtlasVcsLineCommit);
  Result.Revision := ARevision;
  Result.Author := 'anna';
  Result.Message := AMessage;
  Result.Date := EncodeDateTime(2026, 10, ADay, 12, 0, 0, 0);
end;

function KeyList(const AMatches: TArray<TAtlasIssueKeyMatch>): string;
var
  mMatch: TAtlasIssueKeyMatch;
begin
  Result := '';
  for mMatch in AMatches do
  begin
    if Result <> '' then
      Result := Result + '|';
    Result := Result + mMatch.Key;
  end;
end;

type
  /// <summary>Antwortet auf svn log --xml und svn log --diff.</summary>
  TBenchRunner = class(TInterfacedObject, IAtlasVcsRunner)
  public
    Xml: TBytes;
    Diff: TBytes;
    function Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
      ATimeoutMs: Cardinal): TAtlasVcsRunResult;
  end;

function TBenchRunner.Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
  ATimeoutMs: Cardinal): TAtlasVcsRunResult;
begin
  Result := TAtlasVcsRunResult.Make(TAtlasVcsOutcome.Ok, 0, nil);
  if AArguments[1] = '--diff' then
    Result.Output := Diff
  else
    Result.Output := Xml;
end;

type
  /// <summary>Git für History: show liefert den Stand im Repository (ohne: Exit-Code 128), log -L die Commits.
  /// </summary>
  THistoryRunner = class(TInterfacedObject, IAtlasVcsRunner)
  public
    Head: string;
    Committed: Boolean;
    Log: string;
    Calls: TArray<string>;
    function Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
      ATimeoutMs: Cardinal): TAtlasVcsRunResult;
  end;

function THistoryRunner.Run(const AExecutable: string; const AArguments: TArray<string>; const AWorkingDir: string;
  ATimeoutMs: Cardinal): TAtlasVcsRunResult;
var
  mLine: string;
begin
  mLine := string.Join(' ', AArguments);
  Calls := Calls + [mLine];
  Result := TAtlasVcsRunResult.Make(TAtlasVcsOutcome.Ok, 0, nil);
  if Pos(' show ', mLine) > 0 then
  begin
    if Committed then
      Result.Output := TEncoding.UTF8.GetBytes(Head)
    else
      Result.ExitCode := 128;
  end
  else if Pos(' -L', mLine) > 0 then
    Result.Output := TEncoding.UTF8.GetBytes(Log);
end;

{ TAtlasBlameLinksTests }

procedure TAtlasBlameLinksTests.KeysFromCommitMessages;
begin
  Assert.AreEqual('ATL-123', KeyList(TAtlasBlameLinks.Keys(YouTrack, 'ATL-123 Rabatt runden')));
  Assert.AreEqual('ATL-97|ATL-98', KeyList(TAtlasBlameLinks.Keys(YouTrack,
    'Zusammenführen: ATL-97 und atl-98' + #10 + #10 + 'Siehe auch ATL-97.')), 'alle, ohne Doppelte');
  Assert.AreEqual('', KeyList(TAtlasBlameLinks.Keys(YouTrack, 'UTF-8 statt ANSI')));
  Assert.AreEqual('', KeyList(TAtlasBlameLinks.Keys(TAtlasIssueKeyPattern.Empty, 'ATL-1')), 'ohne Tracker nichts');
end;

procedure TAtlasBlameLinksTests.CaptionSuffixListsKeys;
begin
  Assert.AreEqual(' · ATL-97', TAtlasBlameLinks.CaptionSuffix(TAtlasBlameLinks.Keys(YouTrack, 'ATL-97 x')));
  Assert.AreEqual(' · ATL-97, ATL-98', TAtlasBlameLinks.CaptionSuffix(TAtlasBlameLinks.Keys(YouTrack,
    'ATL-97 ATL-98')));
  Assert.AreEqual('', TAtlasBlameLinks.CaptionSuffix(nil));
end;

procedure TAtlasBlameLinksTests.GroupCountsCommitsPerIssue;
var
  mList: TAtlasBlameIssueList;
begin
  mList := TAtlasBlameLinks.Group(YouTrack, TArray<TAtlasVcsLineCommit>.Create(
    Commit('7', 'ATL-3 Nachtrag', 20),
    Commit('6', 'Aufräumen', 19),
    Commit('5', 'ATL-2 Rundung', 18),
    Commit('4', 'ATL-1 und ATL-3', 12),
    Commit('3', 'ATL-1 Anfang', 10)));
  Assert.AreEqual(3, Integer(Length(mList.Issues)));
  Assert.AreEqual(1, mList.Unlinked);
  Assert.AreEqual(5, Integer(Length(mList.Commits)));
  Assert.AreEqual('ATL-3', mList.Issues[0].Match.Key);
  Assert.AreEqual(2, Integer(Length(mList.Issues[0].Commits)));
  Assert.AreEqual(0, mList.Issues[0].Commits[0], 'neuester Commit zuerst');
  Assert.AreEqual(3, mList.Issues[0].Commits[1]);
  Assert.AreEqual('ATL-2', mList.Issues[1].Match.Key);
  Assert.AreEqual(1, Integer(Length(mList.Issues[1].Commits)));
  Assert.AreEqual('ATL-1', mList.Issues[2].Match.Key);
  Assert.AreEqual(2, Integer(Length(mList.Issues[2].Commits)));
  Assert.IsTrue(SameDateTime(EncodeDateTime(2026, 10, 12, 12, 0, 0, 0), mList.Issues[2].LastDate));
end;

procedure TAtlasBlameLinksTests.GroupOrdersByNewestCommitThenKey;
var
  mList: TAtlasBlameIssueList;
begin
  // Gleiche Zeit: nach Kennung, eindeutig.
  mList := TAtlasBlameLinks.Group(YouTrack, TArray<TAtlasVcsLineCommit>.Create(
    Commit('2', 'ATL-20 b', 5),
    Commit('1', 'ATL-10 a', 5)));
  Assert.AreEqual('ATL-10', mList.Issues[0].Match.Key);
  Assert.AreEqual('ATL-20', mList.Issues[1].Match.Key);
  mList := TAtlasBlameLinks.Group(YouTrack, nil);
  Assert.AreEqual(0, Integer(Length(mList.Issues)));
  Assert.AreEqual(0, mList.Unlinked);
end;

procedure TAtlasBlameLinksTests.ScopeIsInnermostMethodOrUnit;
const
  cText =
    'unit Kunde;' + #10 +                       // 0
    'interface' + #10 +                         // 1
    'type TKunde = class procedure Laden; end;' + #10 + // 2
    'implementation' + #10 +                    // 3
    'procedure TKunde.Laden;' + #10 +           // 4
    'begin' + #10 +                             // 5
    '  Rechne;' + #10 +                         // 6
    'end;' + #10 +                              // 7
    '' + #10 +                                  // 8
    'end.' + #10;                               // 9
var
  mFirst, mLast: Integer;
  mName: string;
begin
  Assert.IsTrue(TAtlasBlameLinks.Scope(cText, 6, mFirst, mLast, mName));
  Assert.AreEqual(4, mFirst);
  Assert.AreEqual(7, mLast);
  Assert.AreEqual('TKunde.Laden', mName);
  Assert.IsFalse(TAtlasBlameLinks.Scope(cText, 8, mFirst, mLast, mName), 'außerhalb: die Unit');
  Assert.AreEqual(0, mFirst);
  Assert.AreEqual(9, mLast, 'Zeilenende am Schluss beginnt keine Zeile');
  Assert.AreEqual('', mName);
end;

procedure TAtlasBlameLinksTests.RepositoryRangeSkipsUnsavedLines;
var
  mFirst, mLast: Integer;
begin
  // Im Puffer zwei neue Zeilen oben und eine neue am Ende der Methode (Zeilen 2..6 im Puffer).
  Assert.IsTrue(TAtlasBlameLinks.RepositoryRange(
    TArray<string>.Create('unit A;', 'procedure X;', 'begin', 'end;'),
    TArray<string>.Create('unit A;', '// neu', 'procedure X;', 'begin', '  neu;', 'end;', '// neu am Ende'),
    2, 6, mFirst, mLast));
  Assert.AreEqual(2, mFirst, '1-basiert im Repository');
  Assert.AreEqual(4, mLast);
  Assert.IsFalse(TAtlasBlameLinks.RepositoryRange(TArray<string>.Create('unit A;'),
    TArray<string>.Create('unit A;', 'neu'), 1, 1, mFirst, mLast), 'nur neue Zeilen');
end;

procedure TAtlasBlameLinksTests.HistoryUsesRepositoryLines;
const
  cHash = '2e17e3b0f83577f8a4a215a8ed44a1fc66f22d59';
var
  mRunner: THistoryRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mRoot, mFile: string;
  mBuffer: TArray<string>;
  mHistory: TAtlasBlameHistory;
begin
  if PathDelim = '\' then
    mRoot := 'C:\Projekte\Kunde'
  else
    mRoot := '/projekte/kunde';
  mFile := mRoot + PathDelim + 'a.pas';
  mRunner := THistoryRunner.Create;
  mRunnerRef := mRunner;
  mRunner.Committed := True;
  mRunner.Head := 'unit A;' + #10 + 'procedure X;' + #10 + 'begin' + #10 + 'end;' + #10;
  mRunner.Log := #$1E + cHash + #$1F'anna'#$1F'1793203000'#$1F'ATL-7 X' + #10 + #$1F + #10 + #10 +
    '@@ -0,0 +2,3 @@' + #10 + '+procedure X;' + #10 + '+begin' + #10 + '+end;' + #10;
  mVcs := TAtlasGitVersionControl.Create(mRoot, mRunnerRef, 'git.exe', 5000);
  // Eine ungespeicherte Zeile vorn verschiebt den Bereich im Puffer um eins.
  mBuffer := TArray<string>.Create('// neu', 'unit A;', 'procedure X;', 'begin', 'end;');
  mHistory := TAtlasBlameLinks.History(mVcs, mFile, mBuffer, 2, 4, 50);
  Assert.IsTrue(mHistory.Outcome = TAtlasBlameHistoryOutcome.Ok);
  Assert.AreEqual(1, Integer(Length(mHistory.Commits)));
  Assert.AreEqual('ATL-7 X', mHistory.Commits[0].Message);
  Assert.AreEqual(2, Integer(Length(mRunner.Calls)));
  Assert.IsTrue(Pos('show HEAD:a.pas', mRunner.Calls[0]) > 0, mRunner.Calls[0]);
  Assert.IsTrue(Pos('--max-count=50', mRunner.Calls[1]) > 0, mRunner.Calls[1]);
  Assert.IsTrue(Pos('-L2,4:a.pas', mRunner.Calls[1]) > 0, mRunner.Calls[1]);
  // Nur die neue Zeile: keine Historie, kein Aufruf von log.
  mRunner.Calls := nil;
  mHistory := TAtlasBlameLinks.History(mVcs, mFile, mBuffer, 0, 0, 50);
  Assert.IsTrue(mHistory.Outcome = TAtlasBlameHistoryOutcome.Ok);
  Assert.AreEqual(0, Integer(Length(mHistory.Commits)));
  Assert.AreEqual(1, Integer(Length(mRunner.Calls)));
  // Nicht übernommen: show scheitert.
  mRunner.Committed := False;
  mHistory := TAtlasBlameLinks.History(mVcs, mFile, mBuffer, 2, 4, 50);
  Assert.IsTrue(mHistory.Outcome = TAtlasBlameHistoryOutcome.NotCommitted);
  Assert.IsTrue(TAtlasBlameLinks.History(nil, mFile, mBuffer, 2, 4, 50).Outcome =
    TAtlasBlameHistoryOutcome.Failed);
end;

procedure TAtlasBlameLinksTests.BlameRevisionsAreDistinctAndCommitted;
var
  mLines: TArray<TAtlasVcsBlameLine>;
  mRevisions: TArray<string>;
begin
  SetLength(mLines, 4);
  mLines[0].Revision := '5';
  mLines[1].Revision := '';
  mLines[2].Revision := '3';
  mLines[3].Revision := '5';
  mRevisions := TAtlasBlameLinks.BlameRevisions(mLines);
  Assert.AreEqual(2, Integer(Length(mRevisions)));
  Assert.AreEqual('5', mRevisions[0]);
  Assert.AreEqual('3', mRevisions[1]);
end;

procedure TAtlasBlameLinksTests.ShortRevisionAndSubject;
begin
  Assert.AreEqual('2e17e3b', TAtlasBlameLinks.ShortRevision(TAtlasVcsKind.Git,
    '2e17e3b0f83577f8a4a215a8ed44a1fc66f22d59'));
  Assert.AreEqual('r42', TAtlasBlameLinks.ShortRevision(TAtlasVcsKind.Svn, '42'));
  Assert.AreEqual('ATL-1 Anfang', TAtlasBlameLinks.Subject(#10 + '  ATL-1 Anfang  ' + #10 + 'mehr'));
  Assert.AreEqual('', TAtlasBlameLinks.Subject(''));
end;

procedure TAtlasBlameLinksTests.SvnHistoryOf200RevisionsIsFast;
const
  cRevisions = 200;
  cSep = '------------------------------------------------------------------------';
var
  mXml, mDiff: TStringBuilder;
  mRunner: TBenchRunner;
  mRunnerRef: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mHistory: IAtlasVcsLineHistory;
  mCommits: TArray<TAtlasVcsLineCommit>;
  mList: TAtlasBlameIssueList;
  mRevision, mLine, mStart: Integer;
  mWatch: TStopwatch;
  mRoot: string;
begin
  // Jede Revision ändert eine Zeile; jede fünfte trifft die Methode in den Zeilen 1000–1040.
  mXml := TStringBuilder.Create;
  mDiff := TStringBuilder.Create;
  try
    mXml.Append('<?xml version="1.0" encoding="UTF-8"?>'#10'<log>'#10);
    for mRevision := 5000 downto 5000 - cRevisions + 1 do
    begin
      mXml.Append('<logentry revision="').Append(mRevision).Append('"><author>anna</author>')
        .Append('<date>2026-10-01T08:00:00.000000Z</date><msg>ATL-').Append(mRevision mod 7 + 1)
        .Append(' Änderung</msg></logentry>'#10);
      // Die übrigen ändern weiter oben (Zeilen 100–899).
      mStart := 100 + (mRevision * 37) mod 800;
      if mRevision mod 5 = 0 then
        mStart := 1010;
      mDiff.Append(cSep).Append(#10).Append('r').Append(mRevision)
        .Append(' | anna | 2026-10-01 10:00:00 +0200 (Mi, 01 Okt 2026) | 1 line'#10#10'ATL-1 x'#10#10)
        .Append('Index: Kunde.pas'#10'==================================================================='#10)
        .Append('--- Kunde.pas'#9'(revision 1)'#10'+++ Kunde.pas'#9'(revision 2)'#10)
        .Append('@@ -').Append(mStart - 3).Append(',7 +').Append(mStart - 3).Append(',7 @@'#10);
      for mLine := 1 to 3 do
        mDiff.Append(' gleich').Append(mLine).Append(#10);
      mDiff.Append('-alt'#10'+neu'#10);
      for mLine := 1 to 3 do
        mDiff.Append(' gleich').Append(mLine).Append(#10);
      mDiff.Append(#10);
    end;
    mXml.Append('</log>'#10);
    mDiff.Append(cSep).Append(#10);
    mRunner := TBenchRunner.Create;
    mRunnerRef := mRunner;
    mRunner.Xml := TEncoding.UTF8.GetBytes(mXml.ToString);
    mRunner.Diff := TEncoding.UTF8.GetBytes(mDiff.ToString);
  finally
    mXml.Free;
    mDiff.Free;
  end;
  if PathDelim = '\' then
    mRoot := 'C:\Projekte\Kunde'
  else
    mRoot := '/projekte/kunde';
  mVcs := TAtlasSvnVersionControl.Create(mRoot, mRunnerRef, 'svn.exe', 5000);
  Assert.IsTrue(Supports(mVcs, IAtlasVcsLineHistory, mHistory));
  mWatch := TStopwatch.StartNew;
  Assert.IsTrue(mHistory.LineHistory(mRoot + PathDelim + 'Kunde.pas', 1000, 1040, cRevisions, mCommits) =
    TAtlasVcsOutcome.Ok);
  mList := TAtlasBlameLinks.Group(YouTrack, mCommits);
  mWatch.Stop;
  Assert.AreEqual(cRevisions div 5, Integer(Length(mCommits)), 'jede fünfte Revision trifft die Methode');
  Assert.IsTrue(Length(mList.Issues) > 0);
  // Zwei Aufrufe beim Server bleiben vom Budget von 5 s; das Auswerten darf höchstens 1 s brauchen.
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 1000, Format('%d ms für %d Revisionen', [mWatch.ElapsedMilliseconds,
    cRevisions]));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBlameLinksTests);

end.
