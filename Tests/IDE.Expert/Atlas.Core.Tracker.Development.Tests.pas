unit Atlas.Core.Tracker.Development.Tests;

// Reiter „Entwicklung“ der Issue-Vorschau (#1269) ohne IDE: Kennung als
// eigenes Stück in der Nachricht, Branches (lokal und entfernt zusammen,
// Basis, YouTrack mit Projekt), Vereinigung der Dateien aller Commits nach
// Projekt, erste geänderte Zeile und Unit, Diff je Datei, Zwischenspeicher
// und der ganze Ablauf über eine Versionsverwaltung mit festen Antworten.
// Dazu der Benchmark: ein Git-Repository mit 10 000 Commits (git fast-import)
// liefert den Reiter in unter 2 s.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasIssueDevelopmentTests = class
  public
    [Test]
    procedure KeyCountsOnlyAsOwnToken;
    [Test]
    procedure BranchesJoinLocalAndRemote;
    [Test]
    procedure BranchesOfYouTrackNeedProject;
    /// <summary>Abnahme: Vereinigung der Dateien aller Commits, gruppiert nach Projekt.</summary>
    [Test]
    procedure UnitsGroupedByProject;
    [Test]
    procedure FirstChangedLineAndUnit;
    [Test]
    procedure DiffLinesPerFile;
    [Test]
    procedure CacheKeepsRecentEntries;
    [Test]
    procedure CollectAsksVersionControl;
    [Test]
    procedure CollectWithoutHistory;
    /// <summary>Abnahme: 10 000 Commits, Reiter in unter 2 s.</summary>
    [Test]
    [Category('Benchmark')]
    procedure TenThousandCommitsUnderTwoSeconds;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Development,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.Composition,
  Atlas.Core.Vcs.Adapters.ProcessRunner;

type
  /// <summary>Versionsverwaltung mit festen Antworten für IAtlasVcsHistory; zählt die Aufrufe.</summary>
  TFakeHistory = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsHistory)
  public
    Entries: TArray<TAtlasVcsLogEntry>;
    Refs: TArray<TAtlasVcsRef>;
    SearchOutcome: TAtlasVcsOutcome;
    BranchOutcome: TAtlasVcsOutcome;
    Calls: TArray<string>;
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
    function SearchLog(const AText: string; AMax: Integer; out AEntries: TArray<TAtlasVcsLogEntry>): TAtlasVcsOutcome;
    function AllBranches(out ABranches: TArray<TAtlasVcsRef>): TAtlasVcsOutcome;
    function Distance(const ABranch, ABase: string; out AAhead, ABehind: Integer): TAtlasVcsOutcome;
    function ContentOf(const ARevision: string; const AFile: TAtlasVcsLogFile; ABefore: Boolean;
      out AContent: TBytes): TAtlasVcsOutcome;
  end;

  /// <summary>Nur IAtlasVersionControl, ohne IAtlasVcsHistory.</summary>
  TPlainVcs = class(TInterfacedObject, IAtlasVersionControl)
  public
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
    Result := 'C:\Projekte\Kasse'
  else
    Result := '/projekte/kasse';
end;

function Under(const ARelative: string): string;
begin
  Result := Root + PathDelim + StringReplace(ARelative, '/', PathDelim, [rfReplaceAll]);
end;

function LogFile(const ARelative: string; AKind: TAtlasVcsChangeKind): TAtlasVcsLogFile;
begin
  Result := Default(TAtlasVcsLogFile);
  Result.RepositoryPath := ARelative;
  Result.Path := Under(ARelative);
  Result.Kind := AKind;
end;

function Entry(const ARevision, AMessage: string; const AFiles: TArray<TAtlasVcsLogFile>): TAtlasVcsLogEntry;
begin
  Result := Default(TAtlasVcsLogEntry);
  Result.Revision := ARevision;
  Result.Message := AMessage;
  Result.Summary := AMessage;
  Result.Author := 'Marco';
  Result.Files := AFiles;
end;

function Ref(const AName, ALocalName: string; ARemote, ACurrent: Boolean): TAtlasVcsRef;
begin
  Result := Default(TAtlasVcsRef);
  Result.Name := AName;
  Result.LocalName := ALocalName;
  Result.Remote := ARemote;
  Result.Current := ACurrent;
end;

function GitHubRequest(const ABases: TArray<string>): TAtlasIssueDevelopmentRequest;
begin
  Result := TAtlasIssueDevelopmentRequest.Create('github', 'beispiel/kasse', '#753', ABases, nil);
end;

{ TFakeHistory }

function TFakeHistory.Kind: TAtlasVcsKind;
begin
  Result := TAtlasVcsKind.Git;
end;

function TFakeHistory.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result := TAtlasVcsWorkingCopy.Empty;
  Result.Kind := TAtlasVcsKind.Git;
  Result.Root := Root;
end;

function TFakeHistory.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  AHead := TAtlasVcsHead.Empty;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeHistory.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeHistory.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeHistory.Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeHistory.ChangeMarker: string;
begin
  Result := '';
end;

function TFakeHistory.SearchLog(const AText: string; AMax: Integer;
  out AEntries: TArray<TAtlasVcsLogEntry>): TAtlasVcsOutcome;
begin
  Calls := Calls + [Format('log %s %d', [AText, AMax])];
  AEntries := Entries;
  Result := SearchOutcome;
end;

function TFakeHistory.AllBranches(out ABranches: TArray<TAtlasVcsRef>): TAtlasVcsOutcome;
begin
  Calls := Calls + ['branches'];
  ABranches := Refs;
  Result := BranchOutcome;
end;

function TFakeHistory.Distance(const ABranch, ABase: string; out AAhead, ABehind: Integer): TAtlasVcsOutcome;
begin
  Calls := Calls + ['distance ' + ABranch + ' ' + ABase];
  AAhead := 3;
  ABehind := 1;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeHistory.ContentOf(const ARevision: string; const AFile: TAtlasVcsLogFile; ABefore: Boolean;
  out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

{ TPlainVcs }

function TPlainVcs.Kind: TAtlasVcsKind;
begin
  Result := TAtlasVcsKind.Git;
end;

function TPlainVcs.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result := TAtlasVcsWorkingCopy.Empty;
end;

function TPlainVcs.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  AHead := TAtlasVcsHead.Empty;
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlainVcs.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlainVcs.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlainVcs.Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TPlainVcs.ChangeMarker: string;
begin
  Result := '';
end;

{ TAtlasIssueDevelopmentTests }

procedure TAtlasIssueDevelopmentTests.KeyCountsOnlyAsOwnToken;
begin
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.MentionsKey('#12', 'Fix #12'));
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.MentionsKey('#12', 'beispiel/kasse#12: Fix'), 'mit Repository davor');
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.MentionsKey('#12', '(#12)'));
  Assert.IsFalse(TAtlasIssueDevelopmentQuery.MentionsKey('#12', 'Fix #123'), 'längere Nummer');
  Assert.IsFalse(TAtlasIssueDevelopmentQuery.MentionsKey('#12', 'x#12'), 'Buchstabe davor');
  Assert.IsFalse(TAtlasIssueDevelopmentQuery.MentionsKey('#12', 'repo#12'), 'ohne owner/ kein Repository');
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.MentionsKey('ATL-1', 'atl-1 klein geschrieben'));
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.MentionsKey('ATL-1', 'Erst ATL-10, dann ATL-1.'), 'zweites Vorkommen');
  Assert.IsFalse(TAtlasIssueDevelopmentQuery.MentionsKey('ATL-1', 'ATL-10'));
  Assert.IsFalse(TAtlasIssueDevelopmentQuery.MentionsKey('ATL-1', 'XATL-1'));
  Assert.IsFalse(TAtlasIssueDevelopmentQuery.MentionsKey('', 'egal'));
  Assert.AreEqual(2, Integer(Length(TAtlasIssueDevelopmentQuery.Matching('#12', TArray<TAtlasVcsLogEntry>.Create(
    Entry('a', 'Fix #12', nil), Entry('b', 'Fix #123', nil), Entry('c', 'Teil 2'#10#10'Siehe #12', nil))))));
end;

procedure TAtlasIssueDevelopmentTests.BranchesJoinLocalAndRemote;
var
  mBranches: TArray<TAtlasIssueBranch>;
begin
  mBranches := TAtlasIssueDevelopmentQuery.BranchesOf(GitHubRequest(TArray<string>.Create('develop', 'main')),
    TArray<TAtlasVcsRef>.Create(
      Ref('main', 'main', False, False),
      Ref('feature/753-atlas-bereiche', 'feature/753-atlas-bereiche', False, True),
      Ref('origin/main', 'main', True, False),
      Ref('origin/feature/753-atlas-bereiche', 'feature/753-atlas-bereiche', True, False),
      Ref('origin/bugfix/753-nur-entfernt', 'bugfix/753-nur-entfernt', True, False),
      Ref('feature/7530-anderes', 'feature/7530-anderes', False, False)));
  Assert.AreEqual(2, Integer(Length(mBranches)), 'lokal und entfernt gleichen Namens sind eine Zeile');
  Assert.AreEqual('feature/753-atlas-bereiche', mBranches[0].Name);
  Assert.IsTrue(mBranches[0].Local);
  Assert.IsTrue(mBranches[0].Remote);
  Assert.IsTrue(mBranches[0].Current);
  Assert.AreEqual('origin/feature/753-atlas-bereiche', mBranches[0].RemoteName);
  Assert.AreEqual('main', mBranches[0].Base, 'develop gibt es nicht, main lokal');
  Assert.AreEqual(-1, mBranches[0].Ahead, 'noch nicht gezählt');
  Assert.AreEqual('bugfix/753-nur-entfernt', mBranches[1].Name);
  Assert.IsFalse(mBranches[1].Local);
  Assert.IsTrue(mBranches[1].Remote);
  // Basis nur entfernt: origin/<Name>.
  mBranches := TAtlasIssueDevelopmentQuery.BranchesOf(GitHubRequest(TArray<string>.Create('main')),
    TArray<TAtlasVcsRef>.Create(Ref('origin/main', 'main', True, False),
    Ref('feature/753-x', 'feature/753-x', False, False)));
  Assert.AreEqual('origin/main', mBranches[0].Base);
  // Ohne passende Basis kein Vergleich.
  mBranches := TAtlasIssueDevelopmentQuery.BranchesOf(GitHubRequest(nil),
    TArray<TAtlasVcsRef>.Create(Ref('feature/753-x', 'feature/753-x', False, False)));
  Assert.AreEqual('', mBranches[0].Base);
end;

procedure TAtlasIssueDevelopmentTests.BranchesOfYouTrackNeedProject;
var
  mRequest: TAtlasIssueDevelopmentRequest;
  mBranches: TArray<TAtlasIssueBranch>;
  mRefs: TArray<TAtlasVcsRef>;
  mIndex: Integer;
begin
  mRequest := TAtlasIssueDevelopmentRequest.Create('YouTrack', 'ATL', 'ATL-123', nil, nil);
  Assert.AreEqual('youtrack', mRequest.Provider);
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.BranchMatches(mRequest, 'feature/ATL-123-tracker'));
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.BranchMatches(mRequest, 'ATL-123'), 'SVN: Name unter ^/branches');
  Assert.IsFalse(TAtlasIssueDevelopmentQuery.BranchMatches(mRequest, 'feature/ATL-1234-x'));
  Assert.IsFalse(TAtlasIssueDevelopmentQuery.BranchMatches(mRequest, 'feature/KASSE-123'));
  // Höchstens MaxBranches.
  mRefs := nil;
  for mIndex := 1 to TAtlasIssueDevelopmentRequest.MaxBranches + 3 do
    mRefs := mRefs + [Ref('ATL-123-v' + IntToStr(mIndex), 'ATL-123-v' + IntToStr(mIndex), True, False)];
  mBranches := TAtlasIssueDevelopmentQuery.BranchesOf(mRequest, mRefs);
  Assert.AreEqual(TAtlasIssueDevelopmentRequest.MaxBranches, Integer(Length(mBranches)));
end;

procedure TAtlasIssueDevelopmentTests.UnitsGroupedByProject;
var
  mCommits: TArray<TAtlasVcsLogEntry>;
  mProjects: TArray<TAtlasIssueProject>;
  mGroups: TArray<TAtlasIssueUnitGroup>;
begin
  // Neueste zuerst: Main.pas zuletzt gelöscht, Tool.pas in zwei Commits.
  mCommits := TArray<TAtlasVcsLogEntry>.Create(
    Entry('c3', '#753 aufräumen', TArray<TAtlasVcsLogFile>.Create(
      LogFile('app/Main.pas', TAtlasVcsChangeKind.Deleted),
      LogFile('pakete/werkzeug/Tool.pas', TAtlasVcsChangeKind.Modified))),
    Entry('c2', '#753 Formular', TArray<TAtlasVcsLogFile>.Create(
      LogFile('app/Formular.dfm', TAtlasVcsChangeKind.Modified),
      LogFile('pakete/werkzeug/Tool.pas', TAtlasVcsChangeKind.Modified),
      LogFile('pakete/werkzeug/sub/Hilfe.pas', TAtlasVcsChangeKind.Added))),
    Entry('c1', '#753 Anfang', TArray<TAtlasVcsLogFile>.Create(
      LogFile('app/Main.pas', TAtlasVcsChangeKind.Added),
      LogFile('README.md', TAtlasVcsChangeKind.Modified))));
  // Der Name entscheidet bei gleichem Ordner; Formular.dfm über Formular.pas im Projekt „Kasse“.
  mProjects := TArray<TAtlasIssueProject>.Create(
    TAtlasIssueProject.Create(Under('pakete/werkzeug/Werkzeug.dproj'), nil),
    TAtlasIssueProject.Create(Under('Kasse.dproj'), TArray<string>.Create(Under('app/Formular.pas'),
      Under('app/Main.pas'))),
    TAtlasIssueProject.Create(Under('Alle.dproj'), nil));
  mGroups := TAtlasIssueDevelopmentQuery.GroupUnits(mCommits, mProjects);
  Assert.AreEqual(3, Integer(Length(mGroups)));
  Assert.AreEqual('Alle', mGroups[0].Project, 'Projekte nach Name');
  Assert.AreEqual(1, Integer(Length(mGroups[0].Units)), 'README.md liegt unter dem Ordner von Alle');
  Assert.AreEqual(Under('README.md'), mGroups[0].Units[0].Path);
  Assert.AreEqual('Kasse', mGroups[1].Project);
  Assert.AreEqual(Under('Kasse.dproj'), mGroups[1].ProjectFile);
  Assert.AreEqual(2, Integer(Length(mGroups[1].Units)), 'Mitglied vor Ordner');
  Assert.AreEqual(Under('app/Formular.dfm'), mGroups[1].Units[0].Path, 'nach Pfad sortiert');
  Assert.AreEqual(Under('app/Main.pas'), mGroups[1].Units[1].Path);
  Assert.IsTrue(mGroups[1].Units[1].Deleted, 'jüngster Stand zählt');
  Assert.AreEqual(2, mGroups[1].Units[1].Commits);
  Assert.AreEqual('Werkzeug', mGroups[2].Project, 'tiefster Ordner');
  Assert.AreEqual(2, Integer(Length(mGroups[2].Units)));
  Assert.AreEqual(Under('pakete/werkzeug/sub/Hilfe.pas'), mGroups[2].Units[0].Path);
  Assert.AreEqual(2, mGroups[2].Units[1].Commits);
  Assert.IsFalse(mGroups[2].Units[1].Deleted);
  // Ohne Projekte: alles in der Gruppe ohne Namen; Dateien außerhalb der Arbeitskopie (SVN) entfallen.
  mCommits := mCommits + [Entry('c0', '#753 anderes Projekt', TArray<TAtlasVcsLogFile>.Create(
    Default(TAtlasVcsLogFile)))];
  mGroups := TAtlasIssueDevelopmentQuery.GroupUnits(mCommits, nil);
  Assert.AreEqual(1, Integer(Length(mGroups)));
  Assert.AreEqual('', mGroups[0].Project);
  Assert.AreEqual(5, Integer(Length(mGroups[0].Units)));
  Assert.AreEqual(0, Integer(Length(TAtlasIssueDevelopmentQuery.GroupUnits(nil, mProjects))));
end;

procedure TAtlasIssueDevelopmentTests.FirstChangedLineAndUnit;
var
  mFile: TAtlasVcsLogFile;
begin
  Assert.AreEqual(2, TAtlasIssueDevelopmentQuery.FirstChangedLine('a'#10'b'#10'c', 'a'#10'x'#10'c'));
  Assert.AreEqual(3, TAtlasIssueDevelopmentQuery.FirstChangedLine('a'#10'b', 'a'#10'b'#10'neu'), 'angehängt');
  Assert.AreEqual(1, TAtlasIssueDevelopmentQuery.FirstChangedLine('', 'neu'), 'neue Datei');
  Assert.AreEqual(2, TAtlasIssueDevelopmentQuery.FirstChangedLine('a'#10'b'#10'c', 'a'#10'b'), 'hinten gekürzt');
  Assert.AreEqual(1, TAtlasIssueDevelopmentQuery.FirstChangedLine('a', ''));
  // Erst die Pascal-Datei, dann irgendeine, nie eine gelöschte.
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.OpenTarget(Entry('a', '', TArray<TAtlasVcsLogFile>.Create(
    LogFile('Readme.md', TAtlasVcsChangeKind.Modified), LogFile('Alt.pas', TAtlasVcsChangeKind.Deleted),
    LogFile('Neu.pas', TAtlasVcsChangeKind.Added))), mFile));
  Assert.AreEqual(Under('Neu.pas'), mFile.Path);
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.OpenTarget(Entry('a', '', TArray<TAtlasVcsLogFile>.Create(
    LogFile('Alt.pas', TAtlasVcsChangeKind.Deleted), LogFile('Readme.md', TAtlasVcsChangeKind.Modified))), mFile));
  Assert.AreEqual(Under('Readme.md'), mFile.Path);
  Assert.IsFalse(TAtlasIssueDevelopmentQuery.OpenTarget(Entry('a', '', TArray<TAtlasVcsLogFile>.Create(
    LogFile('Alt.pas', TAtlasVcsChangeKind.Deleted))), mFile));
end;

procedure TAtlasIssueDevelopmentTests.DiffLinesPerFile;
var
  mFiles: TArray<TAtlasIssueFileDiff>;
  mLines: TArray<string>;
  mFile: TAtlasIssueFileDiff;
begin
  mFile.Caption := 'A.pas';
  mFile.Before := 'unit A;'#10'end.';
  mFile.After := 'unit A;'#10'// neu'#10'end.';
  mFiles := [mFile];
  mFile.Caption := 'Gleich.pas';
  mFile.Before := 'x';
  mFile.After := 'x';
  mFiles := mFiles + [mFile];
  mFile.Caption := 'B.pas';
  mFile.Before := '';
  mFile.After := 'unit B;';
  mFiles := mFiles + [mFile];
  mLines := TAtlasIssueDevelopmentQuery.DiffLines(mFiles);
  Assert.AreEqual('=== A.pas ===', mLines[0]);
  Assert.IsTrue(string.Join(#10, mLines).Contains('+ // neu'), string.Join(#10, mLines));
  Assert.IsFalse(string.Join(#10, mLines).Contains('Gleich.pas'), 'ohne Änderung kein Abschnitt');
  Assert.IsTrue(string.Join(#10, mLines).Contains(#10#10'=== B.pas ==='), 'Leerzeile zwischen Dateien');
  Assert.AreEqual(0, Integer(Length(TAtlasIssueDevelopmentQuery.DiffLines(nil))));
end;

procedure TAtlasIssueDevelopmentTests.CacheKeepsRecentEntries;
var
  mCache: TAtlasIssueDevelopmentCache;
  mDevelopment: TAtlasIssueDevelopment;
  mTarget, mOther: TAtlasTrackerTarget;
  mIndex: Integer;
begin
  mTarget := TAtlasTrackerTarget.Create('youtrack', 'https://beispiel.youtrack.cloud/', 'ATL', '');
  mOther := TAtlasTrackerTarget.Create('github', '', 'beispiel/kasse', '');
  mCache := TAtlasIssueDevelopmentCache.Create;
  try
    mDevelopment := TAtlasIssueDevelopment.Empty;
    mDevelopment.Key := 'ATL-1';
    mDevelopment.Truncated := True;
    mCache.Put(mTarget, mDevelopment);
    Assert.IsTrue(mCache.Get(mTarget, 'atl-1', mDevelopment), 'Kennung ohne Groß-/Kleinschreibung');
    Assert.IsTrue(mDevelopment.Truncated);
    Assert.IsFalse(mCache.Get(mOther, 'ATL-1', mDevelopment), 'je Tracker');
    Assert.IsTrue(mDevelopment.VcsOutcome = TAtlasVcsOutcome.NoWorkingCopy, 'ohne Treffer leer');
    // ATL-1 bleibt, weil zuletzt gelesen; das älteste andere fällt heraus.
    for mIndex := 2 to TAtlasIssueDevelopmentCache.MaxEntries do
    begin
      mDevelopment := TAtlasIssueDevelopment.Empty;
      mDevelopment.Key := 'ATL-' + IntToStr(mIndex);
      mCache.Put(mTarget, mDevelopment);
    end;
    Assert.IsTrue(mCache.Get(mTarget, 'ATL-1', mDevelopment));
    mDevelopment := TAtlasIssueDevelopment.Empty;
    mDevelopment.Key := 'ATL-999';
    mCache.Put(mTarget, mDevelopment);
    Assert.AreEqual(TAtlasIssueDevelopmentCache.MaxEntries, mCache.Count);
    Assert.IsTrue(mCache.Get(mTarget, 'ATL-1', mDevelopment));
    Assert.IsFalse(mCache.Get(mTarget, 'ATL-2', mDevelopment));
    mCache.Clear;
    Assert.AreEqual(0, mCache.Count);
  finally
    mCache.Free;
  end;
end;

procedure TAtlasIssueDevelopmentTests.CollectAsksVersionControl;
var
  mFake: TFakeHistory;
  mVcs: IAtlasVersionControl;
  mDevelopment: TAtlasIssueDevelopment;
begin
  mFake := TFakeHistory.Create;
  mVcs := mFake;
  mFake.Entries := TArray<TAtlasVcsLogEntry>.Create(
    Entry('c2', '#753 Teil 2', TArray<TAtlasVcsLogFile>.Create(LogFile('A.pas', TAtlasVcsChangeKind.Modified))),
    Entry('c1', '#7530 grob gefunden', TArray<TAtlasVcsLogFile>.Create(LogFile('B.pas',
    TAtlasVcsChangeKind.Modified))));
  mFake.Refs := TArray<TAtlasVcsRef>.Create(Ref('main', 'main', False, False),
    Ref('origin/feature/753-x', 'feature/753-x', True, False));
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.Collect(mVcs, GitHubRequest(TArray<string>.Create('main')),
    mDevelopment) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual('log #753 200', mFake.Calls[0], 'grobe Suche mit der Kennung');
  Assert.AreEqual('branches', mFake.Calls[1]);
  Assert.AreEqual('distance origin/feature/753-x main', mFake.Calls[2], 'nur entfernt: über den Remote-Namen');
  Assert.AreEqual('#753', mDevelopment.Key);
  Assert.IsTrue(mDevelopment.VcsKind = TAtlasVcsKind.Git);
  Assert.AreEqual(1, Integer(Length(mDevelopment.Commits)), '#7530 fällt heraus');
  Assert.IsFalse(mDevelopment.Truncated);
  Assert.AreEqual(1, mDevelopment.UnitCount);
  Assert.AreEqual(1, Integer(Length(mDevelopment.Branches)));
  Assert.AreEqual(3, mDevelopment.Branches[0].Ahead);
  Assert.AreEqual(1, mDevelopment.Branches[0].Behind);
  // Branches scheitern: Commits bleiben.
  mFake.Calls := nil;
  mFake.BranchOutcome := TAtlasVcsOutcome.Failed;
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.Collect(mVcs, GitHubRequest(nil), mDevelopment) = TAtlasVcsOutcome.Ok);
  Assert.AreEqual(1, Integer(Length(mDevelopment.Commits)));
  Assert.AreEqual(0, Integer(Length(mDevelopment.Branches)));
  // Suche scheitert: das Ergebnis sagt es.
  mFake.SearchOutcome := TAtlasVcsOutcome.TimedOut;
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.Collect(mVcs, GitHubRequest(nil), mDevelopment) =
    TAtlasVcsOutcome.TimedOut);
  Assert.IsTrue(mDevelopment.VcsOutcome = TAtlasVcsOutcome.TimedOut);
  Assert.AreEqual(0, Integer(Length(mDevelopment.Commits)));
end;

procedure TAtlasIssueDevelopmentTests.CollectWithoutHistory;
var
  mDevelopment: TAtlasIssueDevelopment;
  mVcs: IAtlasVersionControl;
  mFake: TFakeHistory;
  mRequest: TAtlasIssueDevelopmentRequest;
  mIndex: Integer;
begin
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.Collect(nil, GitHubRequest(nil), mDevelopment) =
    TAtlasVcsOutcome.NoWorkingCopy);
  Assert.IsTrue(mDevelopment.VcsOutcome = TAtlasVcsOutcome.NoWorkingCopy);
  mVcs := TPlainVcs.Create;
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.Collect(mVcs, GitHubRequest(nil), mDevelopment) =
    TAtlasVcsOutcome.NoWorkingCopy, 'ohne IAtlasVcsHistory');
  // So viele Treffer wie erlaubt: ältere wurden nicht durchsucht.
  mFake := TFakeHistory.Create;
  mVcs := mFake;
  for mIndex := 1 to 5 do
    mFake.Entries := mFake.Entries + [Entry(IntToStr(mIndex), '#753', nil)];
  mRequest := GitHubRequest(nil);
  mRequest.MaxCommits := 5;
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.Collect(mVcs, mRequest, mDevelopment) = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(mDevelopment.Truncated);
  Assert.AreEqual('log #753 5', mFake.Calls[0]);
  mRequest.Key := '';
  Assert.IsTrue(TAtlasIssueDevelopmentQuery.Collect(mVcs, mRequest, mDevelopment) = TAtlasVcsOutcome.Failed,
    'ohne Kennung keine Suche');
  Assert.AreEqual(2, Integer(Length(mFake.Calls)), 'nur die eine Suche von vorhin und ihre Branches');
end;

/// <summary>Startet AExecutable mit AInput als Standardeingabe (git fast-import liest nur von dort); Ausgabe
/// verworfen. Exit-Code.</summary>
function RunWithInput(const AExecutable: string; const AArguments: TArray<string>;
  const AWorkingDir, AInput: string): Cardinal;
var
  mSecurity: TSecurityAttributes;
  mInput, mOutput: THandle;
  mStartup: TStartupInfo;
  mProcess: TProcessInformation;
  mLine, mArgument: string;
begin
  mSecurity.nLength := SizeOf(mSecurity);
  mSecurity.lpSecurityDescriptor := nil;
  mSecurity.bInheritHandle := True;
  mInput := CreateFile(PChar(AInput), GENERIC_READ, FILE_SHARE_READ, @mSecurity, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL, 0);
  if mInput = INVALID_HANDLE_VALUE then
    RaiseLastOSError;
  mOutput := CreateFile('NUL', GENERIC_WRITE, FILE_SHARE_READ or FILE_SHARE_WRITE, @mSecurity, OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL, 0);
  try
    FillChar(mStartup, SizeOf(mStartup), 0);
    mStartup.cb := SizeOf(mStartup);
    mStartup.dwFlags := STARTF_USESTDHANDLES;
    mStartup.hStdInput := mInput;
    mStartup.hStdOutput := mOutput;
    mStartup.hStdError := mOutput;
    mLine := TAtlasVcsProcessRunner.QuoteArgument(AExecutable);
    for mArgument in AArguments do
      mLine := mLine + ' ' + TAtlasVcsProcessRunner.QuoteArgument(mArgument);
    UniqueString(mLine);
    if not CreateProcess(PChar(AExecutable), PChar(mLine), nil, nil, True, CREATE_NO_WINDOW, nil,
      PChar(AWorkingDir), mStartup, mProcess) then
      RaiseLastOSError;
    try
      WaitForSingleObject(mProcess.hProcess, 120000);
      if not GetExitCodeProcess(mProcess.hProcess, Result) then
        Result := High(Cardinal);
    finally
      CloseHandle(mProcess.hThread);
      CloseHandle(mProcess.hProcess);
    end;
  finally
    CloseHandle(mInput);
    if mOutput <> INVALID_HANDLE_VALUE then
      CloseHandle(mOutput);
  end;
end;

/// <summary>Strom für git fast-import: ACount Commits auf main, jeder ändert eine von sieben Units; jeder 100.
/// nennt ATL-77, jeder 1000. ATL-770 (Treffer der groben Suche, die nicht zählen). Der Branch
/// feature/ATL-77-tracker steht zehn Commits vor dem Ende.</summary>
function FastImportStream(ACount: Integer): string;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
  mMessage, mContent: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 1 to ACount do
    begin
      if mIndex mod 100 = 0 then
        mMessage := Format('ATL-77 Schritt %d', [mIndex])
      else if mIndex mod 1000 = 550 then
        mMessage := Format('ATL-770 anderes Issue %d', [mIndex])
      else
        mMessage := Format('Commit %d', [mIndex]);
      mContent := Format('unit U%d;'#10'// Stand %d'#10'end.'#10, [mIndex mod 7, mIndex]);
      mBuilder.Append('commit refs/heads/main'#10);
      mBuilder.Append(Format('mark :%d'#10, [mIndex]));
      mBuilder.Append(Format('committer Atlas Test <test@example.org> %d +0000'#10, [1761000000 + mIndex * 60]));
      mBuilder.Append(Format('data %d'#10'%s'#10, [Length(mMessage), mMessage]));
      if mIndex > 1 then
        mBuilder.Append(Format('from :%d'#10, [mIndex - 1]));
      mBuilder.Append(Format('M 100644 inline src/U%d.pas'#10, [mIndex mod 7]));
      mBuilder.Append(Format('data %d'#10'%s'#10, [Length(mContent), mContent]));
    end;
    mBuilder.Append('reset refs/heads/feature/ATL-77-tracker'#10);
    mBuilder.Append(Format('from :%d'#10#10, [ACount - 10]));
    Result := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
end;

procedure TAtlasIssueDevelopmentTests.TenThousandCommitsUnderTwoSeconds;
const
  cCommits = 10000;
var
  mGit, mFolder, mStream: string;
  mRunner: IAtlasVcsRunner;
  mVcs: IAtlasVersionControl;
  mRequest: TAtlasIssueDevelopmentRequest;
  mDevelopment: TAtlasIssueDevelopment;
  mWatch: TStopwatch;
  mFile: string;
begin
  mGit := TAtlasVcsTools.Find(TAtlasVcsKind.Git);
  if mGit = '' then
    Assert.Pass('git nicht installiert; Prüfung übersprungen');
  // Im Test erlaubt: Der Hauptthread des Testprogramms ist keine IDE.
  mRunner := TAtlasVcsProcessRunner.Create(True, nil);
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasDev-' + TGUID.NewGuid.ToString.Substring(1, 8));
  TDirectory.CreateDirectory(mFolder);
  try
    Assert.AreEqual(0, mRunner.Run(mGit, ['init', '-q'], mFolder, 30000).ExitCode);
    mStream := TPath.Combine(mFolder, 'import.fi');
    TFile.WriteAllText(mStream, FastImportStream(cCommits), TEncoding.ASCII);
    Assert.AreEqual(Cardinal(0), RunWithInput(mGit, ['fast-import', '--quiet'], mFolder, mStream), 'fast-import');
    TFile.Delete(mStream);
    Assert.AreEqual(0, mRunner.Run(mGit, ['symbolic-ref', 'HEAD', 'refs/heads/main'], mFolder, 30000).ExitCode);
    Assert.AreEqual(0, mRunner.Run(mGit, ['checkout', '-q', '-f', 'main'], mFolder, 30000).ExitCode);

    mVcs := TAtlasVersionControl.Open(mFolder, TAtlasVcsProvider.Auto, mRunner);
    mRequest := TAtlasIssueDevelopmentRequest.Create('youtrack', 'ATL', 'ATL-77', TArray<string>.Create('main'),
      nil);
    mWatch := TStopwatch.StartNew;
    Assert.IsTrue(TAtlasIssueDevelopmentQuery.Collect(mVcs, mRequest, mDevelopment) = TAtlasVcsOutcome.Ok);
    mWatch.Stop;
    Assert.AreEqual(cCommits div 100, Integer(Length(mDevelopment.Commits)), 'ATL-770 zählt nicht');
    Assert.IsFalse(mDevelopment.Truncated);
    Assert.AreEqual(7, mDevelopment.UnitCount, 'Vereinigung der Dateien');
    Assert.AreEqual(1, Integer(Length(mDevelopment.Branches)));
    Assert.AreEqual('feature/ATL-77-tracker', mDevelopment.Branches[0].Name);
    Assert.AreEqual('main', mDevelopment.Branches[0].Base);
    Assert.AreEqual(0, mDevelopment.Branches[0].Ahead);
    Assert.AreEqual(10, mDevelopment.Branches[0].Behind);
    mFile := mDevelopment.Commits[0].Files[0].Path;
    Assert.IsTrue(TFile.Exists(mFile), mFile);
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 2000, Format('%d ms für %d Commits', [mWatch.ElapsedMilliseconds,
      cCommits]));
  finally
    mVcs := nil;
    for mFile in TDirectory.GetFiles(mFolder, '*', TSearchOption.soAllDirectories) do
    begin
      {$WARN SYMBOL_PLATFORM OFF}
      TFile.SetAttributes(mFile, [TFileAttribute.faNormal]);
      {$WARN SYMBOL_PLATFORM ON}
    end;
    try
      TDirectory.Delete(mFolder, True);
    except
      on EInOutError do
        ;
      on EOSError do
        ;
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssueDevelopmentTests);

end.
