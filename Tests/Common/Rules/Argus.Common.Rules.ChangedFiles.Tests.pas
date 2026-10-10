unit Argus.Common.Rules.ChangedFiles.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Rules.ChangedFiles;

function P(const APath: string): string;
begin
  Result := TChangedFiles.FullPath('C:\Repo', APath);
end;

procedure TChangedFilesTests.NameStatusRenamedAndDeleted;
var
  Paths: TArray<string>;
begin
  Paths := TChangedFiles.ParseNameStatus(['M'#9'Src/Kunden.pas', 'R087'#9'Src/Alt.pas'#9'Src/Neu.pas',
    'D'#9'Src/Weg.pas', 'A'#9'Src/Form1.dfm', 'warning: irgendwas']);
  Assert.AreEqual(3, Integer(Length(Paths)));
  Assert.AreEqual('Src/Kunden.pas', Paths[0]);
  Assert.AreEqual('Src/Neu.pas', Paths[1]);
  Assert.AreEqual('Src/Form1.dfm', Paths[2]);
end;

procedure TChangedFilesTests.HunksToLines;
var
  Changes: TArray<TChangedLines>;
begin
  Changes := TChangedFiles.ParseHunks(['diff --git a/A.pas b/A.pas', '--- a/A.pas', '+++ b/A.pas',
    '@@ -3,0 +4,2 @@ procedure X;', '+  Neu;', '+  Neu2;', '@@ -10 +12 @@', '-alt', '+neu', '@@ -20,3 +21,0 @@',
    'diff --git a/B.pas b/B.pas', '--- a/B.pas', '+++ /dev/null', '@@ -1,5 +0,0 @@']);
  Assert.AreEqual(1, Integer(Length(Changes)));
  Assert.AreEqual('A.pas', Changes[0].Path);
  Assert.AreEqual(2, Integer(Length(Changes[0].Spans)));
  // Zeilen 4-5 und 12 (1-basiert) sind 3, 4 und 11 (0-basiert).
  Assert.IsFalse(Changes[0].Contains(2));
  Assert.IsTrue(Changes[0].Contains(3));
  Assert.IsTrue(Changes[0].Contains(4));
  Assert.IsFalse(Changes[0].Contains(5));
  Assert.IsTrue(Changes[0].Contains(11));
  Assert.IsFalse(Changes[0].Contains(20));
end;

procedure TChangedFilesTests.IncludeNamesWithoutSwitches;
var
  Names: TArray<string>;
begin
  Names := TChangedFiles.IncludeNames('{$I Defines.inc}'#10'{$I+}'#10'{$IFDEF X}{$ENDIF}'#10 +
    '{$INCLUDE ''Pfad mit Leer\Opt.inc''}'#10'(*$I Alt*)'#10'{$I-}');
  Assert.AreEqual(3, Integer(Length(Names)));
  Assert.AreEqual('Defines.inc', Names[0]);
  Assert.AreEqual('Pfad mit Leer\Opt.inc', Names[1]);
  Assert.AreEqual('Alt', Names[2]);
end;

procedure TChangedFilesTests.SelectUnitsAndForms;
var
  Selected: TArray<string>;
begin
  Selected := TChangedFiles.Select([P('Src/Kunden.pas'), P('Src/Haupt.dfm'), P('README.md')],
    [P('Src/Kunden.pas'), P('Src/Haupt.pas'), P('Src/Rest.pas')], nil);
  Assert.AreEqual(2, Integer(Length(Selected)));
  Assert.AreEqual(P('Src/Kunden.pas'), Selected[0]);
  Assert.AreEqual(P('Src/Haupt.pas'), Selected[1]);
end;

procedure TChangedFilesTests.SelectByInclude;
var
  Selected: TArray<string>;
begin
  Selected := TChangedFiles.Select([P('Inc/Defines.inc')], [P('Src/A.pas'), P('Src/B.pas'), P('Src/C.pas')],
    function(const AFileName: string): TArray<string>
    begin
      if SameText(ExtractFileName(AFileName), 'A.pas') then
        Result := ['..\Inc\Defines.inc']
      else if SameText(ExtractFileName(AFileName), 'B.pas') then
        Result := ['Defines']
      else
        Result := ['Andere.inc'];
    end);
  Assert.AreEqual(2, Integer(Length(Selected)));
  Assert.AreEqual(P('Src/B.pas'), Selected[1]);
end;

procedure TChangedFilesTests.ProjectFileSelectsAll;
begin
  Assert.AreEqual(2, Integer(Length(TChangedFiles.Select([P('Projekt.dproj')], [P('A.pas'), P('B.pas')], nil))));
  Assert.AreEqual(2, Integer(Length(TChangedFiles.Select([P('argus.json')], [P('A.pas'), P('B.pas')], nil))));
  Assert.AreEqual(0, Integer(Length(TChangedFiles.Select([P('docs/X.md')], [P('A.pas'), P('B.pas')], nil))));
end;

procedure TChangedFilesTests.LinesOfFullPath;
var
  Lines: TChangedLines;
  Changes: TArray<TChangedLines>;
begin
  Changes := TChangedFiles.ParseHunks(['+++ b/Src/A.pas', '@@ -1 +1 @@']);
  Assert.IsTrue(TChangedFiles.LinesOf(Changes, 'C:\Repo', P('src/a.pas'), Lines));
  Assert.IsTrue(Lines.Contains(0));
  Assert.IsFalse(TChangedFiles.LinesOf(Changes, 'C:\Repo', P('Src/B.pas'), Lines));
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
  Paths: TArray<string>;
begin
  Paths := TChangedFiles.ParseSvnStatus(['M       Src\Kunde.pas', 'A  +    Src\Neu.pas', 'D       Src\Weg.pas',
    '?       Src\Entwurf.pas', ' M      Src', 'R       Src\Ersetzt.pas'], False);
  Assert.AreEqual(3, Integer(Length(Paths)));
  Assert.AreEqual('Src\Kunde.pas', Paths[0]);
  Assert.AreEqual('Src\Neu.pas', Paths[1]);
  Assert.AreEqual('Src\Ersetzt.pas', Paths[2]);
  Assert.AreEqual(4, Integer(Length(TChangedFiles.ParseSvnStatus(['M       A.pas', '?       B.pas',
    'A       C.dfm', 'D       D.pas', '?       E.pas'], True))));
  Paths := TChangedFiles.ParseSvnSummarize(['M       Src/Kunde.pas', 'D       Src/Weg.pas', ' M      Src/Prop.pas',
    'A       Src/Form1.dfm']);
  Assert.AreEqual(2, Integer(Length(Paths)));
  Assert.AreEqual('Src/Form1.dfm', Paths[1]);
end;

procedure TChangedFilesTests.SvnDiffCountsOnlyAddedLines;
var
  Changes: TArray<TChangedLines>;
begin
  Changes := TChangedFiles.ParseSvnDiff(['Index: Src/A.pas', StringOfChar('=', 67),
    '--- Src/A.pas'#9'(revision 12)', '+++ Src/A.pas'#9'(working copy)', '@@ -3,5 +3,6 @@', ' kontext',
    '-alt', '+neu', '+neu2', ' kontext', ' kontext', '@@ -20,2 +21,2 @@', ' kontext', '+neu3', '-alt',
    'Index: Src/B.pas']);
  Assert.AreEqual(1, Integer(Length(Changes)));
  Assert.AreEqual('Src/A.pas', Changes[0].Path);
  // Zeile 3 (1-basiert) ist Kontext, 4 und 5 neu, 22 neu.
  Assert.IsFalse(Changes[0].Contains(2));
  Assert.IsTrue(Changes[0].Contains(3));
  Assert.IsTrue(Changes[0].Contains(4));
  Assert.IsFalse(Changes[0].Contains(5));
  Assert.IsFalse(Changes[0].Contains(20));
  Assert.IsTrue(Changes[0].Contains(21));
  Assert.AreEqual(2, Integer(Length(Changes[0].Spans)));
end;

initialization
  TDUnitX.RegisterTestFixture(TChangedFilesTests);

end.
