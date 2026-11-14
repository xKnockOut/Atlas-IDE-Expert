unit Atlas.Common.Rules.ChangedFiles.Tests;

// Tests für die Auswahl geänderter Dateien (#157).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TChangedFilesTests = class
  public
    [Test]
    procedure NameStatusRenamedAndDeleted;
    [Test]
    procedure HunksToLines;
    [Test]
    procedure IncludeNamesWithoutSwitches;
    [Test]
    procedure SelectUnitsAndForms;
    [Test]
    procedure SelectByInclude;
    [Test]
    procedure ProjectFileSelectsAll;
    [Test]
    procedure LinesOfFullPath;
    [Test]
    procedure QuotedPaths;
    [Test]
    procedure SvnStatusAndSummarize;
    [Test]
    procedure SvnDiffCountsOnlyAddedLines;
    [Test]
    procedure GitAndSvnAgreeOnGaps;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.ChangedFiles;

function P(const APath: string): string;
begin
  Result := TChangedFiles.FullPath('C:\Repo', APath);
end;

procedure TChangedFilesTests.NameStatusRenamedAndDeleted;
var
  mPaths: TArray<string>;
begin
  mPaths := TChangedFiles.ParseNameStatus(['M'#9'Src/Kunden.pas', 'R087'#9'Src/Alt.pas'#9'Src/Neu.pas',
    'D'#9'Src/Weg.pas', 'A'#9'Src/Form1.dfm', 'warning: irgendwas']);
  Assert.AreEqual(3, Integer(Length(mPaths)));
  Assert.AreEqual('Src/Kunden.pas', mPaths[0]);
  Assert.AreEqual('Src/Neu.pas', mPaths[1]);
  Assert.AreEqual('Src/Form1.dfm', mPaths[2]);
end;

procedure TChangedFilesTests.HunksToLines;
var
  mChanges: TArray<TChangedLines>;
begin
  mChanges := TChangedFiles.ParseHunks(['diff --git a/A.pas b/A.pas', '--- a/A.pas', '+++ b/A.pas',
    '@@ -3,0 +4,2 @@ procedure X;', '+  Neu;', '+  Neu2;', '@@ -10 +12 @@', '-alt', '+neu', '@@ -20,3 +21,0 @@',
    'diff --git a/B.pas b/B.pas', '--- a/B.pas', '+++ /dev/null', '@@ -1,5 +0,0 @@']);
  Assert.AreEqual(1, Integer(Length(mChanges)));
  Assert.AreEqual('A.pas', mChanges[0].Path);
  Assert.AreEqual(2, Integer(Length(mChanges[0].Spans)));
  // Zeilen 4-5 und 12 (1-basiert) sind 3, 4 und 11 (0-basiert).
  Assert.IsFalse(mChanges[0].Contains(2));
  Assert.IsTrue(mChanges[0].Contains(3));
  Assert.IsTrue(mChanges[0].Contains(4));
  Assert.IsFalse(mChanges[0].Contains(5));
  Assert.IsTrue(mChanges[0].Contains(11));
  Assert.IsFalse(mChanges[0].Contains(20));
end;

procedure TChangedFilesTests.IncludeNamesWithoutSwitches;
var
  mNames: TArray<string>;
begin
  mNames := TChangedFiles.IncludeNames('{$I Defines.inc}'#10'{$I+}'#10'{$IFDEF X}{$ENDIF}'#10 +
    '{$INCLUDE ''Pfad mit Leer\Opt.inc''}'#10'(*$I Alt*)'#10'{$I-}');
  Assert.AreEqual(3, Integer(Length(mNames)));
  Assert.AreEqual('Defines.inc', mNames[0]);
  Assert.AreEqual('Pfad mit Leer\Opt.inc', mNames[1]);
  Assert.AreEqual('Alt', mNames[2]);
end;

procedure TChangedFilesTests.SelectUnitsAndForms;
var
  mSelected: TArray<string>;
begin
  mSelected := TChangedFiles.Select([P('Src/Kunden.pas'), P('Src/Haupt.dfm'), P('README.md')],
    [P('Src/Kunden.pas'), P('Src/Haupt.pas'), P('Src/Rest.pas')], nil);
  Assert.AreEqual(2, Integer(Length(mSelected)));
  Assert.AreEqual(P('Src/Kunden.pas'), mSelected[0]);
  Assert.AreEqual(P('Src/Haupt.pas'), mSelected[1]);
end;

procedure TChangedFilesTests.SelectByInclude;
var
  mSelected: TArray<string>;
begin
  mSelected := TChangedFiles.Select([P('Inc/Defines.inc')], [P('Src/A.pas'), P('Src/B.pas'), P('Src/C.pas')],
    function(const AFileName: string): TArray<string>
    begin
      if SameText(ExtractFileName(AFileName), 'A.pas') then
      begin
        Result := ['..\Inc\Defines.inc'];
      end
      else if SameText(ExtractFileName(AFileName), 'B.pas') then
      begin
        Result := ['Defines'];
      end
      else
      begin
        Result := ['Andere.inc'];
      end;
    end);
  Assert.AreEqual(2, Integer(Length(mSelected)));
  Assert.AreEqual(P('Src/B.pas'), mSelected[1]);
end;

procedure TChangedFilesTests.ProjectFileSelectsAll;
begin
  Assert.AreEqual(2, Integer(Length(TChangedFiles.Select([P('Projekt.dproj')], [P('A.pas'), P('B.pas')], nil))));
  Assert.AreEqual(2, Integer(Length(TChangedFiles.Select([P('atlas.json')], [P('A.pas'), P('B.pas')], nil))));
  Assert.AreEqual(0, Integer(Length(TChangedFiles.Select([P('docs/X.md')], [P('A.pas'), P('B.pas')], nil))));
end;

procedure TChangedFilesTests.LinesOfFullPath;
var
  mLines: TChangedLines;
  mChanges: TArray<TChangedLines>;
begin
  mChanges := TChangedFiles.ParseHunks(['+++ b/Src/A.pas', '@@ -1 +1 @@']);
  Assert.IsTrue(TChangedFiles.LinesOf(mChanges, 'C:\Repo', P('src/a.pas'), mLines));
  Assert.IsTrue(mLines.Contains(0));
  Assert.IsFalse(TChangedFiles.LinesOf(mChanges, 'C:\Repo', P('Src/B.pas'), mLines));
end;

procedure TChangedFilesTests.QuotedPaths;
begin
  Assert.AreEqual('Src/Kunde.pas', TChangedFiles.UnquotePath('Src/Kunde.pas'));
  Assert.AreEqual('Src/'#$00E4'nderung mit Leer.pas',
    TChangedFiles.UnquotePath('"Src/\303\244nderung mit Leer.pas"'));
  Assert.AreEqual('A"B.pas', TChangedFiles.UnquotePath('"A\"B.pas"'));
  Assert.AreEqual('Src/'#$00FC'.pas', TChangedFiles.ParseNameStatus(['M'#9'"Src/\303\274.pas"'])[0]);
  Assert.AreEqual('Src/'#$00FC'.pas', TChangedFiles.ParseHunks(['+++ "b/Src/\303\274.pas"'])[0].Path);
end;

procedure TChangedFilesTests.SvnStatusAndSummarize;
var
  mPaths: TArray<string>;
begin
  mPaths := TChangedFiles.ParseSvnStatus(['M       Src\Kunde.pas', 'A  +    Src\Neu.pas', 'D       Src\Weg.pas',
    '?       Src\Entwurf.pas', ' M      Src', 'R       Src\Ersetzt.pas'], False);
  Assert.AreEqual(3, Integer(Length(mPaths)));
  Assert.AreEqual('Src\Kunde.pas', mPaths[0]);
  Assert.AreEqual('Src\Neu.pas', mPaths[1]);
  Assert.AreEqual('Src\Ersetzt.pas', mPaths[2]);
  Assert.AreEqual(4, Integer(Length(TChangedFiles.ParseSvnStatus(['M       A.pas', '?       B.pas',
    'A       C.dfm', 'D       D.pas', '?       E.pas'], True))));
  mPaths := TChangedFiles.ParseSvnSummarize(['M       Src/Kunde.pas', 'D       Src/Weg.pas', ' M      Src/Prop.pas',
    'A       Src/Form1.dfm']);
  Assert.AreEqual(2, Integer(Length(mPaths)));
  Assert.AreEqual('Src/Form1.dfm', mPaths[1]);
end;

procedure TChangedFilesTests.SvnDiffCountsOnlyAddedLines;
var
  mChanges: TArray<TChangedLines>;
begin
  mChanges := TChangedFiles.ParseSvnDiff(['Index: Src/A.pas', StringOfChar('=', 67),
    '--- Src/A.pas'#9'(revision 12)', '+++ Src/A.pas'#9'(working copy)', '@@ -3,5 +3,6 @@', ' kontext',
    '-alt', '+neu', '+neu2', ' kontext', ' kontext', '@@ -20,2 +21,2 @@', ' kontext', '+neu3', '-alt',
    'Index: Src/B.pas']);
  Assert.AreEqual(1, Integer(Length(mChanges)));
  Assert.AreEqual('Src/A.pas', mChanges[0].Path);
  // Zeile 3 (1-basiert) ist Kontext, 4 und 5 neu, 22 neu.
  Assert.IsFalse(mChanges[0].Contains(2));
  Assert.IsTrue(mChanges[0].Contains(3));
  Assert.IsTrue(mChanges[0].Contains(4));
  Assert.IsFalse(mChanges[0].Contains(5));
  Assert.IsFalse(mChanges[0].Contains(20));
  Assert.IsTrue(mChanges[0].Contains(21));
  Assert.AreEqual(2, Integer(Length(mChanges[0].Spans)));
end;

procedure TChangedFilesTests.GitAndSvnAgreeOnGaps;
var
  mGit, mSvn: TArray<TChangedLines>;
begin
  // Dieselbe Änderung (#1353): alte Zeilen 5 und 6 entfernt, alte Zeile 9 ersetzt; Git mit -U0, SVN mit Kontext.
  mGit := TChangedFiles.ParseHunks(['+++ b/Src/A.pas', '@@ -5,2 +4,0 @@', '@@ -9 +7 @@']);
  mSvn := TChangedFiles.ParseSvnDiff(['Index: Src/A.pas', '--- Src/A.pas'#9'(revision 12)',
    '+++ Src/A.pas'#9'(working copy)', '@@ -3,8 +3,6 @@', ' z3', ' z4', '-z5', '-z6', ' z7', ' z8', '-z9', '+neu9',
    ' z10']);
  Assert.AreEqual(1, Integer(Length(mGit)));
  Assert.AreEqual(1, Integer(Length(mSvn)));
  Assert.AreEqual(1, Integer(Length(mGit[0].Gaps)));
  Assert.AreEqual(1, Integer(Length(mSvn[0].Gaps)));
  // Vor der 0-basierten Zeile 4 der neuen Fassung (z7) fehlen sie.
  Assert.AreEqual(4, mGit[0].Gaps[0]);
  Assert.AreEqual(mGit[0].Gaps[0], mSvn[0].Gaps[0]);
  Assert.AreEqual(1, Integer(Length(mGit[0].Spans)));
  Assert.AreEqual(1, Integer(Length(mSvn[0].Spans)));
  Assert.AreEqual(6, mGit[0].Spans[0].First);
  Assert.AreEqual(mGit[0].Spans[0].First, mSvn[0].Spans[0].First);
  Assert.AreEqual(mGit[0].Spans[0].Last, mSvn[0].Spans[0].Last);
  // Am Dateiende entfernt (SVN: kein "+" mehr danach).
  mSvn := TChangedFiles.ParseSvnDiff(['+++ Src/A.pas', '@@ -1,3 +1,1 @@', ' z1', '-z2', '-z3']);
  Assert.AreEqual(1, Integer(Length(mSvn[0].Gaps)));
  Assert.AreEqual(1, mSvn[0].Gaps[0]);
  Assert.AreEqual(1, TChangedFiles.ParseHunks(['+++ b/Src/A.pas', '@@ -2,2 +1,0 @@'])[0].Gaps[0]);
end;

initialization
  TDUnitX.RegisterTestFixture(TChangedFilesTests);

end.
