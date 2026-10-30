unit Atlas.Common.Hotspots.History.Tests;

// Tests der Verlaufsdaten der Hotspots (#1354): git log --numstat und
// svn log -v --xml als Fixtures, Umbenennungen in beiden Schreibweisen von
// git, Umbenennung als Kopie mit Löschen in SVN, Verfolgen auf den heutigen
// Namen, Zeitangaben und Zeilen eines Diffs.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  THotspotHistoryTests = class
  public
    [Test]
    procedure ParsesGitNumstat;
    [Test]
    procedure SplitsBothRenameForms;
    [Test]
    procedure ParsesSvnXmlWithRename;
    [Test]
    procedure SvnOnlyBelowPrefix;
    [Test]
    procedure FollowsRenamesToCurrentName;
    [Test]
    procedure AddedFileEndsOlderHistory;
    [Test]
    procedure IsoDatesRoundTrip;
    [Test]
    procedure CountsPatchLines;
    [Test]
    procedure BuildsArguments;
  end;

/// <summary>Ausgabe von git log mit THotspotHistory.GitLogArguments für einen Commit.</summary>
function GitRecord(const ARevision: string; ASeconds: Int64; const AAuthor, ASummary: string;
  const ANumstat: TArray<string>): string;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.Hotspots.History;

function GitRecord(const ARevision: string; ASeconds: Int64; const AAuthor, ASummary: string;
  const ANumstat: TArray<string>): string;
var
  mLine: string;
begin
  Result := THotspotHistory.GitRecord + ARevision + THotspotHistory.GitField + IntToStr(ASeconds) +
    THotspotHistory.GitField + AAuthor + THotspotHistory.GitField + ASummary + #10#10;
  for mLine in ANumstat do
    Result := Result + mLine + #10;
end;

function SvnFixture: string;
begin
  Result :=
    '<?xml version="1.0" encoding="UTF-8"?>'#10 +
    '<log>'#10 +
    '<logentry revision="12">'#10 +
    '<author>anna</author>'#10 +
    '<date>2026-10-20T08:30:00.123456Z</date>'#10 +
    '<paths>'#10 +
    '<path action="A" kind="file" copyfrom-path="/trunk/Src/Alt.pas" copyfrom-rev="11">/trunk/Src/Neu.pas</path>'#10 +
    '<path action="D" kind="file">/trunk/Src/Alt.pas</path>'#10 +
    '<path action="M" kind="file">/trunk/Src/Haupt.pas</path>'#10 +
    '</paths>'#10 +
    '<msg>Alt in Neu umbenannt &amp; Haupt angepasst'#10'Zweite Zeile</msg>'#10 +
    '</logentry>'#10 +
    '<logentry revision="9">'#10 +
    '<author>bernd</author>'#10 +
    '<date>2026-09-01T10:00:00.000000Z</date>'#10 +
    '<paths>'#10 +
    '<path action="A" kind="dir">/trunk/Src</path>'#10 +
    '<path action="A" kind="file">/trunk/Src/Alt.pas</path>'#10 +
    '<path action="M" kind="file">/branches/x/Src/Alt.pas</path>'#10 +
    '<path action="D" kind="file">/trunk/Src/Weg.pas</path>'#10 +
    '</paths>'#10 +
    '<msg>Start</msg>'#10 +
    '</logentry>'#10 +
    '<logentry revision="10">'#10 +
    '<author>anna</author>'#10 +
    '<date>2026-09-15T10:00:00.000000Z</date>'#10 +
    '<paths>'#10 +
    '<path action="M" kind="dir">/trunk</path>'#10 +
    '</paths>'#10 +
    '<msg>Nur Eigenschaften</msg>'#10 +
    '</logentry>'#10 +
    '</log>'#10;
end;

function Change(const APath, AOld: string; AKind: THotspotChangeKind): THotspotFileChange;
begin
  Result := THotspotFileChange.Make(APath, AOld, AKind, 1, 1);
end;

function Commit(const ARevision: string; const AFiles: TArray<THotspotFileChange>): THotspotCommit;
begin
  Result := Default(THotspotCommit);
  Result.Revision := ARevision;
  Result.Author := 'anna';
  Result.Files := AFiles;
end;

{ THotspotHistoryTests }

procedure THotspotHistoryTests.ParsesGitNumstat;
var
  mCommits: TArray<THotspotCommit>;
begin
  mCommits := THotspotHistory.ParseGitLog(
    GitRecord('c2', 1761700000, 'Anna Admin', 'Zweiter Stand', TArray<string>.Create('3'#9'1'#9'Src/A.pas',
    '-'#9'-'#9'Bild.png', '0'#9'2'#9'Src/{Alt => Neu}/B.pas')) +
    GitRecord('c1', 1761600000, 'Bernd', 'Erster', TArray<string>.Create('10'#9'0'#9'Src/A.pas')) +
    // Ohne Dateien (leerer Commit) fällt weg.
    GitRecord('c0', 1761500000, 'Bernd', 'Leer', nil));
  Assert.AreEqual(2, Integer(Length(mCommits)));
  Assert.AreEqual('c2', mCommits[0].Revision);
  Assert.AreEqual('Anna Admin', mCommits[0].Author);
  Assert.AreEqual('Zweiter Stand', mCommits[0].Summary);
  Assert.AreEqual(Int64(1761700000), DateTimeToUnix(mCommits[0].Date, True));
  Assert.AreEqual(3, Integer(Length(mCommits[0].Files)));
  Assert.AreEqual('Src/A.pas', mCommits[0].Files[0].Path);
  Assert.AreEqual(3, mCommits[0].Files[0].Added);
  Assert.AreEqual(1, mCommits[0].Files[0].Deleted);
  Assert.AreEqual(-1, mCommits[0].Files[1].Added, 'Binärdatei: unbekannt');
  Assert.IsTrue(mCommits[0].Files[2].Kind = THotspotChangeKind.Renamed);
  Assert.AreEqual('Src/Neu/B.pas', mCommits[0].Files[2].Path);
  Assert.AreEqual('Src/Alt/B.pas', mCommits[0].Files[2].OldPath);
  Assert.AreEqual(10, mCommits[1].Files[0].Added);
end;

procedure THotspotHistoryTests.SplitsBothRenameForms;
var
  mOld, mNew: string;
begin
  Assert.IsTrue(THotspotHistory.SplitRename('Alt.pas => Neu.pas', mOld, mNew));
  Assert.AreEqual('Alt.pas', mOld);
  Assert.AreEqual('Neu.pas', mNew);
  Assert.IsTrue(THotspotHistory.SplitRename('Src/{ => Core}/A.pas', mOld, mNew));
  Assert.AreEqual('Src/A.pas', mOld);
  Assert.AreEqual('Src/Core/A.pas', mNew);
  Assert.IsTrue(THotspotHistory.SplitRename('{Alt => Neu}/A.pas', mOld, mNew));
  Assert.AreEqual('Alt/A.pas', mOld);
  Assert.AreEqual('Neu/A.pas', mNew);
  Assert.IsFalse(THotspotHistory.SplitRename('Src/A.pas', mOld, mNew));
  Assert.AreEqual('Src/A.pas', mNew);
  Assert.AreEqual('', mOld);
end;

procedure THotspotHistoryTests.ParsesSvnXmlWithRename;
var
  mCommits: TArray<THotspotCommit>;
begin
  mCommits := THotspotHistory.ParseSvnLog(SvnFixture, '/trunk');
  Assert.AreEqual(2, Integer(Length(mCommits)), 'nur Eigenschaften eines Ordners: kein Commit');
  Assert.AreEqual('12', mCommits[0].Revision, 'neueste zuerst');
  Assert.AreEqual('9', mCommits[1].Revision);
  Assert.AreEqual('anna', mCommits[0].Author);
  Assert.AreEqual('Alt in Neu umbenannt & Haupt angepasst', mCommits[0].Summary, 'erste Zeile, Entitäten');
  Assert.AreEqual('2026-10-20T08:30:00Z', THotspotHistory.IsoDate(mCommits[0].Date));
  Assert.AreEqual(2, Integer(Length(mCommits[0].Files)), 'die gelöschte Quelle steht beim neuen Pfad');
  Assert.AreEqual('Src/Neu.pas', mCommits[0].Files[0].Path);
  Assert.IsTrue(mCommits[0].Files[0].Kind = THotspotChangeKind.Renamed);
  Assert.AreEqual('Src/Alt.pas', mCommits[0].Files[0].OldPath);
  Assert.AreEqual(-1, mCommits[0].Files[0].Added, 'svn log kennt keine Zeilen');
  Assert.IsTrue(mCommits[0].Files[1].Kind = THotspotChangeKind.Modified);
  Assert.AreEqual(2, Integer(Length(mCommits[1].Files)), 'Ordner und anderer Branch fallen weg');
  Assert.IsTrue(mCommits[1].Files[0].Kind = THotspotChangeKind.Added);
  Assert.IsTrue(mCommits[1].Files[1].Kind = THotspotChangeKind.Deleted);
end;

procedure THotspotHistoryTests.SvnOnlyBelowPrefix;
var
  mCommits: TArray<THotspotCommit>;
begin
  mCommits := THotspotHistory.ParseSvnLog(SvnFixture, '/branches/x');
  Assert.AreEqual(1, Integer(Length(mCommits)));
  Assert.AreEqual('Src/Alt.pas', mCommits[0].Files[0].Path);
  mCommits := THotspotHistory.ParseSvnLog(SvnFixture, '/');
  Assert.AreEqual('trunk/Src/Neu.pas', mCommits[0].Files[0].Path, 'Wurzel des Repositorys');
end;

procedure THotspotHistoryTests.FollowsRenamesToCurrentName;
var
  mCommits: TArray<THotspotCommit>;
begin
  // Neueste zuerst: c3 ändert B, c2 benennt A in B um, c1 ändert A.
  mCommits := THotspotHistory.FollowRenames(TArray<THotspotCommit>.Create(
    Commit('c3', [Change('Src/B.pas', '', THotspotChangeKind.Modified)]),
    Commit('c2', [Change('Src/B.pas', 'Src/A.pas', THotspotChangeKind.Renamed)]),
    Commit('c1', [Change('Src/A.pas', '', THotspotChangeKind.Modified), Change('Src/C.pas', '',
    THotspotChangeKind.Modified)])));
  Assert.AreEqual(3, Integer(Length(mCommits)));
  Assert.AreEqual('Src/B.pas', mCommits[1].Files[0].Path);
  Assert.AreEqual('Src/A.pas', mCommits[1].Files[0].OldPath, 'Name vor dem Commit bleibt');
  Assert.AreEqual('Src/B.pas', mCommits[2].Files[0].Path, 'alte Änderung unter dem heutigen Namen');
  Assert.AreEqual('Src/C.pas', mCommits[2].Files[1].Path);
end;

procedure THotspotHistoryTests.AddedFileEndsOlderHistory;
var
  mCommits: TArray<THotspotCommit>;
begin
  // A wurde gelöscht und in c2 neu angelegt: c1 gehört zur früheren Datei.
  mCommits := THotspotHistory.FollowRenames(TArray<THotspotCommit>.Create(
    Commit('c3', [Change('A.pas', '', THotspotChangeKind.Modified)]),
    Commit('c2', [Change('A.pas', '', THotspotChangeKind.Added)]),
    Commit('c1', [Change('A.pas', '', THotspotChangeKind.Modified)])));
  Assert.AreEqual(2, Integer(Length(mCommits)), 'c1 ohne Dateien fällt weg');
  Assert.AreEqual('c2', mCommits[1].Revision);
end;

procedure THotspotHistoryTests.IsoDatesRoundTrip;
var
  mDate: TDateTime;
begin
  Assert.IsTrue(THotspotHistory.TryParseIsoDate('2026-10-29T21:24:52.123456Z', mDate));
  Assert.AreEqual('2026-10-29T21:24:52Z', THotspotHistory.IsoDate(mDate));
  Assert.IsTrue(THotspotHistory.TryParseIsoDate('2026-01-02T03:04:05Z', mDate));
  Assert.AreEqual('2026-01-02T03:04:05Z', THotspotHistory.IsoDate(mDate));
  Assert.IsFalse(THotspotHistory.TryParseIsoDate('29.10.2026', mDate));
  Assert.AreEqual('2025-10-29T00:00:00Z', THotspotHistory.IsoDate(THotspotHistory.Since(EncodeDate(2026, 10, 29),
    12)));
end;

procedure THotspotHistoryTests.CountsPatchLines;
var
  mAdded, mDeleted: Integer;
begin
  THotspotHistory.CountPatch(TArray<string>.Create('diff --git a/A.pas b/A.pas', '--- a/A.pas', '+++ b/A.pas',
    '@@ -1,2 +1,3 @@', ' unit A;', '-  X := 1;', '+  X := 2;', '+  Y := 3;'), mAdded, mDeleted);
  Assert.AreEqual(2, mAdded);
  Assert.AreEqual(1, mDeleted);
end;

procedure THotspotHistoryTests.BuildsArguments;
var
  mArguments: TArray<string>;
begin
  mArguments := THotspotHistory.GitLogArguments(EncodeDate(2025, 10, 29));
  Assert.AreEqual('log', mArguments[0]);
  Assert.AreEqual('--since=2025-10-29T00:00:00Z', mArguments[High(mArguments)]);
  Assert.IsTrue(string.Join(' ', mArguments).Contains('--numstat'));
  Assert.IsTrue(string.Join(' ', mArguments).Contains('-M'), 'Umbenennungen erkennen');
  mArguments := THotspotHistory.SvnLogArguments(EncodeDate(2025, 10, 29), 'C:\Arbeit');
  Assert.AreEqual('HEAD:{2025-10-29T00:00:00Z}', mArguments[High(mArguments) - 1]);
  Assert.AreEqual('C:\Arbeit', mArguments[High(mArguments)]);
end;

initialization
  TDUnitX.RegisterTestFixture(THotspotHistoryTests);

end.
