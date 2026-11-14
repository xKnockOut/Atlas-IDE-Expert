unit Atlas.Core.Tasks.Matchers.Tests;

// Tests für die Muster der Projektaufgaben (#900): eingebaute Muster mit
// Zeilen der echten Tools/Check-*.ps1, des Compilers und von MSBuild, eigenes
// Muster mit benannten Gruppen und severityMap, Pfade gegen Arbeitsordner,
// Projektdateien und Suchpfad.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasTaskMatchersTests = class
  public
    /// <summary>Einmal-Belegungen vorwegnehmen; sie gehören nicht in die Leckmessung.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure PwshFindsLinesOfTheCheckScripts;
    [Test]
    procedure PwshSeverityWords;
    [Test]
    procedure DccIdeAndCommandLine;
    [Test]
    procedure MsBuildLines;
    [Test]
    procedure GenericLines;
    [Test]
    procedure CustomMatcherWithSeverityMap;
    [Test]
    procedure CustomMatcherErrorsAndGroupNumbers;
    [Test]
    procedure NoMatcherFindsNothing;
    [Test]
    procedure PathsResolveAgainstCwdProjectAndSearchPath;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Matchers;

function Matcher(AKind: TAtlasTaskMatcherKind): TAtlasTaskLineMatcher;
begin
  Result := TAtlasTaskLineMatcher.Create(TAtlasTaskMatcher.Create(AKind));
end;

procedure TAtlasTaskMatchersTests.WarmUpFirstUse;
begin
  CustomMatcherErrorsAndGroupNumbers;
end;

procedure TAtlasTaskMatchersTests.PwshFindsLinesOfTheCheckScripts;
var
  mLines: TAtlasTaskLineMatcher;
  mFinding: TAtlasTaskFinding;
begin
  mLines := Matcher(TAtlasTaskMatcherKind.Pwsh);
  try
    // Check-Delphi12.ps1 (Write-Host "  $_", Pfad relativ zum Repo).
    Assert.IsTrue(mLines.Match('  Packages\Atlas.Common\Source\Kunde.pas:88: "is not" gibt es erst ab Delphi 13; ' +
      '"not (X is T)" verwenden', mFinding));
    Assert.AreEqual('Packages\Atlas.Common\Source\Kunde.pas', mFinding.FileName);
    Assert.AreEqual(88, mFinding.Line);
    Assert.AreEqual(0, mFinding.Column);
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Error, mFinding.Severity, 'ohne Wort: error');
    Assert.AreEqual('"is not" gibt es erst ab Delphi 13; "not (X is T)" verwenden', mFinding.Message);
    // Check-MainThreadQueue.ps1, unter Linux mit /.
    Assert.IsTrue(mLines.Match('  Packages/Atlas.IDE.Expert/Source/IDE/Foo.pas:12: Einreihen ohne Besitzer überlebt ' +
      'das Entladen; TAtlasMainThread.Queue bzw. ForceQueue verwenden', mFinding));
    Assert.AreEqual('Packages/Atlas.IDE.Expert/Source/IDE/Foo.pas', mFinding.FileName);
    Assert.AreEqual(12, mFinding.Line);
    // Check-PackageDependencies.ps1 mit Gedankenstrich im Text.
    Assert.IsTrue(mLines.Match('  Packages\Atlas.Common\Source\A.pas:5: uses Vcl.Forms – Atlas.Common muss frei ' +
      'von VCL sein', mFinding));
    Assert.AreEqual(5, mFinding.Line);
    // Check-Delphi12.ps1 an der .dproj ohne Zeile; Check-TestCoverage ohne Zeile.
    Assert.IsTrue(mLines.Match('  Tests\Atlas.Tests.dproj: ProjectVersion fehlt', mFinding));
    Assert.AreEqual('Tests\Atlas.Tests.dproj', mFinding.FileName);
    Assert.AreEqual(0, mFinding.Line, 'Befund an der Datei');
    Assert.AreEqual('ProjectVersion fehlt', mFinding.Message);
    Assert.IsTrue(mLines.Match('  Packages\Atlas.IDE.Expert\Source\Core\X.pas: keine Testunit nennt X', mFinding));
    // Klammerform und Spalte.
    Assert.IsTrue(mLines.Match('C:\Repo\Unit1.pas(14,3): Text', mFinding));
    Assert.AreEqual('C:\Repo\Unit1.pas', mFinding.FileName);
    Assert.AreEqual(14, mFinding.Line);
    Assert.AreEqual(3, mFinding.Column);
    Assert.IsTrue(mLines.Match('Unit1.pas:7:9: Text', mFinding));
    Assert.AreEqual(9, mFinding.Column);
    // Kopf- und Schlusszeilen der Skripte sind keine Befunde.
    Assert.IsFalse(mLines.Match('Nicht mit Delphi 12 oder Win64 verträglich:', mFinding));
    Assert.IsFalse(mLines.Match('Quelltext ist mit Delphi 12 und Win64 verträglich.', mFinding));
    Assert.IsFalse(mLines.Match('Rollenmatrix: 12 Fälle wie erwartet.', mFinding));
    Assert.IsFalse(mLines.Match('Geschrieben: docs/Konfiguration.md', mFinding));
    Assert.IsFalse(mLines.Match('', mFinding));
  finally
    mLines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.PwshSeverityWords;
var
  mLines: TAtlasTaskLineMatcher;
  mFinding: TAtlasTaskFinding;
begin
  mLines := Matcher(TAtlasTaskMatcherKind.Pwsh);
  try
    Assert.IsTrue(mLines.Match('WARNUNG: Src\A.pas:3: lange Zeile', mFinding));
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Warning, mFinding.Severity);
    Assert.AreEqual('Src\A.pas', mFinding.FileName);
    Assert.IsTrue(mLines.Match('Src\A.pas:3: HINWEIS: Kommentar fehlt', mFinding));
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Info, mFinding.Severity);
    Assert.AreEqual('Kommentar fehlt', mFinding.Message);
    Assert.IsTrue(mLines.Match('Src\A.pas:3: FEHLER unbekannter Typ', mFinding));
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Error, mFinding.Severity);
    Assert.AreEqual('unbekannter Typ', mFinding.Message);
    // Kleingeschrieben ist es Text, keine Schwere.
    Assert.IsTrue(mLines.Match('Src\A.pas:3: warnung im Text', mFinding));
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Error, mFinding.Severity);
    Assert.AreEqual('warnung im Text', mFinding.Message);
    Assert.IsTrue(mLines.Match('Write-Error: Src\B.pas:4: Parser weicht ab', mFinding));
    Assert.AreEqual('Src\B.pas', mFinding.FileName);
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Error, mFinding.Severity);
  finally
    mLines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.DccIdeAndCommandLine;
var
  mLines: TAtlasTaskLineMatcher;
  mFinding: TAtlasTaskFinding;
begin
  mLines := Matcher(TAtlasTaskMatcherKind.Dcc);
  try
    Assert.IsTrue(mLines.Match('[dcc64 Error] Datei.pas(12): E2003 Undeclared identifier: ''Foo''', mFinding));
    Assert.AreEqual('Datei.pas', mFinding.FileName);
    Assert.AreEqual(12, mFinding.Line);
    Assert.AreEqual('E2003', mFinding.Code);
    Assert.AreEqual('Undeclared identifier: ''Foo''', mFinding.Message);
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Error, mFinding.Severity);
    Assert.IsTrue(mLines.Match('[dcc32 Warnung] Kunde.pas(40): W1036 Variable ''X'' ist möglicherweise nicht ' +
      'initialisiert worden', mFinding));
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Warning, mFinding.Severity);
    Assert.AreEqual('W1036', mFinding.Code);
    Assert.IsTrue(mLines.Match('[dcc32 Hinweis] Kunde.pas(41): H2164 Variable ''Y'' wurde deklariert, aber in ' +
      '''Z'' nicht verwendet', mFinding));
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Info, mFinding.Severity);
    Assert.IsTrue(mLines.Match('[dcc32 Schwerer Fehler] Projekt.dpr(9): F2613 Unit ''Gibts'' nicht gefunden.',
      mFinding));
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Error, mFinding.Severity);
    Assert.AreEqual('F2613', mFinding.Code);
    // Kommandozeilen-Compiler.
    Assert.IsTrue(mLines.Match('C:\P\Unit1.pas(28) Error: E2003 Undeclared identifier: ''x''', mFinding));
    Assert.AreEqual('C:\P\Unit1.pas', mFinding.FileName);
    Assert.AreEqual(28, mFinding.Line);
    Assert.AreEqual('E2003', mFinding.Code);
    Assert.IsTrue(mLines.Match('Unit1.pas(30) Hint: H2077 Value assigned to ''y'' never used', mFinding));
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Info, mFinding.Severity);
    Assert.IsFalse(mLines.Match('Embarcadero Delphi for Win64 compiler version 36.0', mFinding));
    Assert.IsFalse(mLines.Match('Unit1.pas(30)', mFinding));
  finally
    mLines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.MsBuildLines;
var
  mLines: TAtlasTaskLineMatcher;
  mFinding: TAtlasTaskFinding;
begin
  mLines := Matcher(TAtlasTaskMatcherKind.MsBuild);
  try
    Assert.IsTrue(mLines.Match('  C:\P\Unit1.pas(12,5): error E2003: Undeclared identifier: ''x'' [C:\P\App.dproj]',
      mFinding));
    Assert.AreEqual('C:\P\Unit1.pas', mFinding.FileName);
    Assert.AreEqual(12, mFinding.Line);
    Assert.AreEqual(5, mFinding.Column);
    Assert.AreEqual('E2003', mFinding.Code);
    Assert.AreEqual('Undeclared identifier: ''x''', mFinding.Message, 'ohne Projekt in Klammern');
    Assert.IsTrue(mLines.Match('Unit2.pas(7): warning W1000: Symbol ''Old'' is deprecated', mFinding));
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Warning, mFinding.Severity);
    Assert.IsTrue(mLines.Match('Unit2.pas(7): dcc hint H2443: Inline function not expanded', mFinding));
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Info, mFinding.Severity);
    Assert.AreEqual('H2443', mFinding.Code);
    Assert.IsTrue(mLines.Match('MSBUILD : error MSB1009: Project file does not exist.', mFinding));
    Assert.AreEqual('', mFinding.FileName, 'Werkzeugname ist keine Datei');
    Assert.AreEqual('MSB1009', mFinding.Code);
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Error, mFinding.Severity);
    Assert.IsTrue(mLines.Match('C:\P\App.dproj : warning MSB3277: Konflikte', mFinding));
    Assert.AreEqual('C:\P\App.dproj', mFinding.FileName);
    Assert.AreEqual(0, mFinding.Line);
    Assert.IsFalse(mLines.Match('Build succeeded.', mFinding));
    Assert.IsFalse(mLines.Match('    0 Error(s)', mFinding));
  finally
    mLines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.GenericLines;
var
  mLines: TAtlasTaskLineMatcher;
  mFinding: TAtlasTaskFinding;
begin
  mLines := Matcher(TAtlasTaskMatcherKind.Generic);
  try
    Assert.IsTrue(mLines.Match('Datei.pas(12): Text', mFinding));
    Assert.AreEqual('Datei.pas', mFinding.FileName);
    Assert.AreEqual(12, mFinding.Line);
    Assert.AreEqual('Text', mFinding.Message);
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Error, mFinding.Severity);
    Assert.IsTrue(mLines.Match('src\a.c(3,9): warning C4996: veraltet', mFinding));
    Assert.AreEqual(9, mFinding.Column);
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Warning, mFinding.Severity);
    Assert.AreEqual('C4996', mFinding.Code);
    Assert.AreEqual('veraltet', mFinding.Message);
    Assert.IsTrue(mLines.Match('lib/x.py:10:4: Hinweis zu lang', mFinding));
    Assert.AreEqual('lib/x.py', mFinding.FileName);
    Assert.AreEqual(4, mFinding.Column);
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Info, mFinding.Severity);
    Assert.IsFalse(mLines.Match('fertig in 3 s', mFinding));
  finally
    mLines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.CustomMatcherWithSeverityMap;
var
  mSpec: TAtlasTaskMatcher;
  mLines: TAtlasTaskLineMatcher;
  mFinding: TAtlasTaskFinding;
begin
  // Fremdes Werkzeug: „[BAD] Kunde.pas L12 C4 K101 Text“.
  mSpec := TAtlasTaskMatcher.Create(TAtlasTaskMatcherKind.Custom);
  mSpec.Regex := '^\[(?<severity>\w+)\] (?<file>\S+) L(?<line>\d+)(?: C(?<column>\d+))? (?<code>K\d+) ' +
    '(?<message>.*)$';
  mSpec.SeverityWords := TArray<string>.Create('bad', 'meh');
  mSpec.SeverityValues := [TAtlasTaskSeverity.Error, TAtlasTaskSeverity.Warning];
  mSpec.DefaultSeverity := TAtlasTaskSeverity.Info;
  mLines := TAtlasTaskLineMatcher.Create(mSpec);
  try
    Assert.AreEqual('', mLines.Error);
    Assert.IsTrue(mLines.Match('[BAD] Kunde.pas L12 C4 K101 Feld ungenutzt', mFinding));
    Assert.AreEqual('Kunde.pas', mFinding.FileName);
    Assert.AreEqual(12, mFinding.Line);
    Assert.AreEqual(4, mFinding.Column);
    Assert.AreEqual('K101', mFinding.Code);
    Assert.AreEqual('Feld ungenutzt', mFinding.Message);
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Error, mFinding.Severity);
    Assert.IsTrue(mLines.Match('[Meh] Kunde.pas L13 K102 Name', mFinding), 'Spalte fehlt');
    Assert.AreEqual(0, mFinding.Column);
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Warning, mFinding.Severity, 'Groß-/Kleinschreibung egal');
    Assert.IsTrue(mLines.Match('[warning] Kunde.pas L14 K103 x', mFinding));
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Warning, mFinding.Severity, 'Standardwort ohne Eintrag');
    Assert.IsTrue(mLines.Match('[NOTE] Kunde.pas L15 K104 y', mFinding));
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Info, mFinding.Severity, 'unbekannt: severity des Musters');
    Assert.IsFalse(mLines.Match('Zusammenfassung: 4 Meldungen', mFinding));
  finally
    mLines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.CustomMatcherErrorsAndGroupNumbers;
var
  mSpec: TAtlasTaskMatcher;
  mLines: TAtlasTaskLineMatcher;
  mFinding: TAtlasTaskFinding;
begin
  Assert.AreEqual(2, TAtlasTaskLineMatcher.GroupNumber('(a)(?<file>b)', 'file'));
  Assert.AreEqual(1, TAtlasTaskLineMatcher.GroupNumber('(?:x)\((?<line>\d+)', 'line'), '\( und (?: zählen nicht');
  Assert.AreEqual(2, TAtlasTaskLineMatcher.GroupNumber('[(](a)(?P<code>c)', 'code'), '( in [...] zählt nicht');
  Assert.AreEqual(2, TAtlasTaskLineMatcher.GroupNumber('(?<=x)(a)(?''message''m)', 'message'),
    'Rückschau zählt nicht');
  Assert.AreEqual(0, TAtlasTaskLineMatcher.GroupNumber('(a)', 'file'));
  // Ungültiger Ausdruck: Fehlertext, keine Befunde, keine Ausnahme.
  mSpec := TAtlasTaskMatcher.Create(TAtlasTaskMatcherKind.Custom);
  mSpec.Regex := '(?<file>[a-';
  mLines := TAtlasTaskLineMatcher.Create(mSpec);
  try
    Assert.AreNotEqual('', mLines.Error);
    Assert.IsFalse(mLines.Match('[a-', mFinding));
  finally
    mLines.Free;
  end;
  // Ohne Gruppe message: die ganze Zeile.
  mSpec.Regex := '^(?<file>\S+\.pas)!(?<line>\d+)';
  mLines := TAtlasTaskLineMatcher.Create(mSpec);
  try
    Assert.IsTrue(mLines.Match('A.pas!3 kaputt ', mFinding));
    Assert.AreEqual('A.pas!3 kaputt', mFinding.Message);
    Assert.AreEqual<TAtlasTaskSeverity>(TAtlasTaskSeverity.Error, mFinding.Severity);
  finally
    mLines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.NoMatcherFindsNothing;
var
  mLines: TAtlasTaskLineMatcher;
  mFinding: TAtlasTaskFinding;
begin
  mLines := Matcher(TAtlasTaskMatcherKind.None);
  try
    Assert.IsFalse(mLines.Match('Datei.pas(12): Text', mFinding));
  finally
    mLines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.PathsResolveAgainstCwdProjectAndSearchPath;
var
  mExists: TAtlasTaskFileExists;
  mProject, mSearch: TArray<string>;
begin
  mExists :=
    function(const AFileName: string): Boolean
    begin
      Result := SameText(AFileName, 'C:\Repo\Packages\A.pas') or SameText(AFileName, 'C:\Lib\Util.pas');
    end;
  mProject := TArray<string>.Create('C:\Repo\Source\Core\Kunde.pas', 'C:\Repo\Source\Form1.pas');
  mSearch := TArray<string>.Create('', 'C:\Lib\');
  Assert.AreEqual('C:\Repo\Packages\A.pas', TAtlasTaskPaths.Resolve('Packages/A.pas', 'C:\Repo', mProject, mSearch,
    mExists), 'gegen den Arbeitsordner');
  Assert.AreEqual('C:\Repo\Packages\A.pas', TAtlasTaskPaths.Resolve('.\Tools\..\Packages\A.pas', 'C:\Repo\', nil,
    nil, mExists));
  Assert.AreEqual('C:\Repo\Source\Core\Kunde.pas', TAtlasTaskPaths.Resolve('Core\Kunde.pas', 'C:\Anders', mProject,
    mSearch, mExists), 'Ende eines Pfads im Projekt');
  Assert.AreEqual('C:\Repo\Source\Form1.pas', TAtlasTaskPaths.Resolve('form1.pas', 'C:\Anders', mProject, mSearch,
    mExists));
  Assert.AreEqual('C:\Lib\Util.pas', TAtlasTaskPaths.Resolve('Util.pas', 'C:\Repo', mProject, mSearch, mExists),
    'Suchpfad');
  Assert.AreEqual('C:\Repo\Fehlt.pas', TAtlasTaskPaths.Resolve('Fehlt.pas', 'C:\Repo', mProject, mSearch, mExists),
    'nicht gefunden: gegen den Arbeitsordner');
  Assert.AreEqual('D:\x\y.pas', TAtlasTaskPaths.Resolve('D:/x/./y.pas', 'C:\Repo', mProject, mSearch, mExists),
    'absolut bleibt');
  Assert.AreEqual('\\server\share\a.pas', TAtlasTaskPaths.Normalize('\\server\share\b\..\a.pas'));
  Assert.AreEqual('C:\a.pas', TAtlasTaskPaths.Normalize('C:\..\a.pas'), 'nicht über das Laufwerk hinaus');
  Assert.AreEqual('', TAtlasTaskPaths.Resolve('', 'C:\Repo', mProject, mSearch, mExists));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTaskMatchersTests);

end.
