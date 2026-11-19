unit Atlas.Common.History.Commits.Tests;

// Tests der Commit-Zerlegung der Symbolgeschichte (#2641): Kennungen in Nachrichten, erste Zeile, Datei und
// Einführung aus git log -L, geänderte Dateien aus git show --name-status.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSymbolCommitsTests = class
  public
    [Test]
    procedure FindsGitHubKeys;
    [Test]
    procedure SkipsEntitiesAndCharConstants;
    [Test]
    procedure FindsPrefixKeyOnlyAtStart;
    [Test]
    procedure SummaryIsFirstLine;
    [Test]
    procedure PatchPathAndIntroduction;
    [Test]
    procedure ParsesNameStatus;
    [Test]
    procedure ParsesLineLog;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.History.Contract,
  Atlas.Common.Hotspots.Contract,
  Atlas.Common.History.Commits;

function Keys(const AMessage: string): string;
begin
  Result := string.Join(',', TSymbolCommits.IssueKeys(AMessage));
end;

procedure TSymbolCommitsTests.FindsGitHubKeys;
begin
  Assert.AreEqual('#12,owner/repo#5', Keys('Fix (#12), siehe owner/repo#5 und #12'));
  Assert.AreEqual('#7', Keys('#7: Anfang'));
end;

procedure TSymbolCommitsTests.SkipsEntitiesAndCharConstants;
begin
  Assert.AreEqual('', Keys('Zeichen &#123; und #13#10 und x#4 und #5a'));
end;

procedure TSymbolCommitsTests.FindsPrefixKeyOnlyAtStart;
begin
  Assert.AreEqual('ATL-97', Keys('ATL-97 Speicher'));
  Assert.AreEqual('', Keys('Kodierung UTF-8 und ISO-9001'));
  Assert.AreEqual('', Keys('ATL-97a kein Kürzel'));
end;

procedure TSymbolCommitsTests.SummaryIsFirstLine;
begin
  Assert.AreEqual('Erste Zeile', TSymbolCommits.Summary(#10'  Erste Zeile  '#13#10#13#10'Rest'));
end;

procedure TSymbolCommitsTests.PatchPathAndIntroduction;
var
  mIntro, mChange: TArray<string>;
begin
  mIntro := TArray<string>.Create('diff --git a/Src/A.pas b/Src/A.pas', '--- /dev/null', '+++ b/Src/A.pas',
    '@@ -0,0 +4,2 @@', '+a', '+b');
  mChange := TArray<string>.Create('--- a/Alt.pas', '+++ b/Neu.pas', '@@ -4,2 +4,2 @@', '-a', '+b');
  Assert.AreEqual('Src/A.pas', TSymbolCommits.PatchPath(mIntro));
  Assert.AreEqual('Neu.pas', TSymbolCommits.PatchPath(mChange));
  Assert.IsTrue(TSymbolCommits.IsIntroduction(mIntro));
  Assert.IsFalse(TSymbolCommits.IsIntroduction(mChange));  Assert.IsTrue(TSymbolCommits.IsIntroduction(TArray<string>.Create('@@ -57,0 +58,2 @@', '+a', '+b')),
    'eingefügt in eine bestehende Datei');
  Assert.IsFalse(TSymbolCommits.IsIntroduction(TArray<string>.Create('@@ -57,10 +58,2 @@', '+a', '+b')));
  Assert.AreEqual('', TSymbolCommits.PatchPath(nil));
end;

procedure TSymbolCommitsTests.ParsesNameStatus;
var
  mFiles: TArray<THotspotFileChange>;
begin
  mFiles := TSymbolCommits.ParseNameStatus('M'#9'A.pas'#10'R087'#9'Alt/B.pas'#9'Neu/B.pas'#10'D'#9'C.pas'#10 +
    'A'#9'D.pas'#10#10);
  Assert.AreEqual(4, Integer(Length(mFiles)));
  Assert.AreEqual<THotspotChangeKind>(THotspotChangeKind.Modified, mFiles[0].Kind);
  Assert.AreEqual('Neu/B.pas', mFiles[1].Path);
  Assert.AreEqual('Alt/B.pas', mFiles[1].OldPath);
  Assert.AreEqual<THotspotChangeKind>(THotspotChangeKind.Renamed, mFiles[1].Kind);
  Assert.AreEqual<THotspotChangeKind>(THotspotChangeKind.Deleted, mFiles[2].Kind);
  Assert.AreEqual<THotspotChangeKind>(THotspotChangeKind.Added, mFiles[3].Kind);
end;

procedure TSymbolCommitsTests.ParsesLineLog;
var
  mCommits: TArray<TSymbolLineCommit>;
begin
  mCommits := TSymbolCommits.ParseLineLog(#$1E'abc123'#$1F'Anna'#$1F'86400'#$1F'#4 Erste'#10#10'Rest'#10#$1F +
    #10'diff --git a/A.pas b/A.pas'#10'@@ -1,0 +1,1 @@'#10'+x'#10 + #$1E'def'#$1F'Bert'#$1F'kaputt'#$1F'x'#$1F);
  Assert.AreEqual(1, Integer(Length(mCommits)), 'Satz mit ungültiger Zeit fällt weg');
  Assert.AreEqual('abc123', mCommits[0].Revision);
  Assert.AreEqual('Anna', mCommits[0].Author);
  Assert.AreEqual('1970-01-02', FormatDateTime('yyyy-mm-dd', mCommits[0].Date));
  Assert.AreEqual('#4 Erste'#10#10'Rest', mCommits[0].Message);
  Assert.AreEqual(3, Integer(Length(mCommits[0].Patch)));
  Assert.AreEqual('+x', mCommits[0].Patch[2]);
end;

initialization
  TDUnitX.RegisterTestFixture(TSymbolCommitsTests);

end.
