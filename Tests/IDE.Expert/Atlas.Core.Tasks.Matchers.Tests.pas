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
  TAtlasTaskMatchersTests = class
  public
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

procedure TAtlasTaskMatchersTests.PwshFindsLinesOfTheCheckScripts;
var
  Lines: TAtlasTaskLineMatcher;
  Finding: TAtlasTaskFinding;
begin
  Lines := Matcher(TAtlasTaskMatcherKind.Pwsh);
  try
    // Check-Delphi12.ps1 (Write-Host "  $_", Pfad relativ zum Repo).
    Assert.IsTrue(Lines.Match('  Packages\Atlas.Common\Source\Kunde.pas:88: "is not" gibt es erst ab Delphi 13; ' +
      '"not (X is T)" verwenden', Finding));
    Assert.AreEqual('Packages\Atlas.Common\Source\Kunde.pas', Finding.FileName);
    Assert.AreEqual(88, Finding.Line);
    Assert.AreEqual(0, Finding.Column);
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Error, 'ohne Wort: error');
    Assert.AreEqual('"is not" gibt es erst ab Delphi 13; "not (X is T)" verwenden', Finding.Message);
    // Check-MainThreadQueue.ps1, unter Linux mit /.
    Assert.IsTrue(Lines.Match('  Packages/Atlas.IDE.Expert/Source/IDE/Foo.pas:12: Einreihen ohne Besitzer überlebt ' +
      'das Entladen; TAtlasMainThread.Queue bzw. ForceQueue verwenden', Finding));
    Assert.AreEqual('Packages/Atlas.IDE.Expert/Source/IDE/Foo.pas', Finding.FileName);
    Assert.AreEqual(12, Finding.Line);
    // Check-PackageDependencies.ps1 mit Gedankenstrich im Text.
    Assert.IsTrue(Lines.Match('  Packages\Atlas.Common\Source\A.pas:5: uses Vcl.Forms – Atlas.Common muss frei ' +
      'von VCL sein', Finding));
    Assert.AreEqual(5, Finding.Line);
    // Check-Delphi12.ps1 an der .dproj ohne Zeile; Check-TestCoverage ohne Zeile.
    Assert.IsTrue(Lines.Match('  Tests\Atlas.Tests.dproj: ProjectVersion fehlt', Finding));
    Assert.AreEqual('Tests\Atlas.Tests.dproj', Finding.FileName);
    Assert.AreEqual(0, Finding.Line, 'Befund an der Datei');
    Assert.AreEqual('ProjectVersion fehlt', Finding.Message);
    Assert.IsTrue(Lines.Match('  Packages\Atlas.IDE.Expert\Source\Core\X.pas: keine Testunit nennt X', Finding));
    // Klammerform und Spalte.
    Assert.IsTrue(Lines.Match('C:\Repo\Unit1.pas(14,3): Text', Finding));
    Assert.AreEqual('C:\Repo\Unit1.pas', Finding.FileName);
    Assert.AreEqual(14, Finding.Line);
    Assert.AreEqual(3, Finding.Column);
    Assert.IsTrue(Lines.Match('Unit1.pas:7:9: Text', Finding));
    Assert.AreEqual(9, Finding.Column);
    // Kopf- und Schlusszeilen der Skripte sind keine Befunde.
    Assert.IsFalse(Lines.Match('Nicht mit Delphi 12 oder Win64 verträglich:', Finding));
    Assert.IsFalse(Lines.Match('Quelltext ist mit Delphi 12 und Win64 verträglich.', Finding));
    Assert.IsFalse(Lines.Match('Rollenmatrix: 12 Fälle wie erwartet.', Finding));
    Assert.IsFalse(Lines.Match('Geschrieben: docs/Konfiguration.md', Finding));
    Assert.IsFalse(Lines.Match('', Finding));
  finally
    Lines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.PwshSeverityWords;
var
  Lines: TAtlasTaskLineMatcher;
  Finding: TAtlasTaskFinding;
begin
  Lines := Matcher(TAtlasTaskMatcherKind.Pwsh);
  try
    Assert.IsTrue(Lines.Match('WARNUNG: Src\A.pas:3: lange Zeile', Finding));
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Warning);
    Assert.AreEqual('Src\A.pas', Finding.FileName);
    Assert.IsTrue(Lines.Match('Src\A.pas:3: HINWEIS: Kommentar fehlt', Finding));
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Info);
    Assert.AreEqual('Kommentar fehlt', Finding.Message);
    Assert.IsTrue(Lines.Match('Src\A.pas:3: FEHLER unbekannter Typ', Finding));
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Error);
    Assert.AreEqual('unbekannter Typ', Finding.Message);
    // Kleingeschrieben ist es Text, keine Schwere.
    Assert.IsTrue(Lines.Match('Src\A.pas:3: warnung im Text', Finding));
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Error);
    Assert.AreEqual('warnung im Text', Finding.Message);
    Assert.IsTrue(Lines.Match('Write-Error: Src\B.pas:4: Parser weicht ab', Finding));
    Assert.AreEqual('Src\B.pas', Finding.FileName);
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Error);
  finally
    Lines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.DccIdeAndCommandLine;
var
  Lines: TAtlasTaskLineMatcher;
  Finding: TAtlasTaskFinding;
begin
  Lines := Matcher(TAtlasTaskMatcherKind.Dcc);
  try
    Assert.IsTrue(Lines.Match('[dcc64 Error] Datei.pas(12): E2003 Undeclared identifier: ''Foo''', Finding));
    Assert.AreEqual('Datei.pas', Finding.FileName);
    Assert.AreEqual(12, Finding.Line);
    Assert.AreEqual('E2003', Finding.Code);
    Assert.AreEqual('Undeclared identifier: ''Foo''', Finding.Message);
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Error);
    Assert.IsTrue(Lines.Match('[dcc32 Warnung] Kunde.pas(40): W1036 Variable ''X'' ist möglicherweise nicht ' +
      'initialisiert worden', Finding));
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Warning);
    Assert.AreEqual('W1036', Finding.Code);
    Assert.IsTrue(Lines.Match('[dcc32 Hinweis] Kunde.pas(41): H2164 Variable ''Y'' wurde deklariert, aber in ' +
      '''Z'' nicht verwendet', Finding));
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Info);
    Assert.IsTrue(Lines.Match('[dcc32 Schwerer Fehler] Projekt.dpr(9): F2613 Unit ''Gibts'' nicht gefunden.',
      Finding));
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Error);
    Assert.AreEqual('F2613', Finding.Code);
    // Kommandozeilen-Compiler.
    Assert.IsTrue(Lines.Match('C:\P\Unit1.pas(28) Error: E2003 Undeclared identifier: ''x''', Finding));
    Assert.AreEqual('C:\P\Unit1.pas', Finding.FileName);
    Assert.AreEqual(28, Finding.Line);
    Assert.AreEqual('E2003', Finding.Code);
    Assert.IsTrue(Lines.Match('Unit1.pas(30) Hint: H2077 Value assigned to ''y'' never used', Finding));
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Info);
    Assert.IsFalse(Lines.Match('Embarcadero Delphi for Win64 compiler version 36.0', Finding));
    Assert.IsFalse(Lines.Match('Unit1.pas(30)', Finding));
  finally
    Lines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.MsBuildLines;
var
  Lines: TAtlasTaskLineMatcher;
  Finding: TAtlasTaskFinding;
begin
  Lines := Matcher(TAtlasTaskMatcherKind.MsBuild);
  try
    Assert.IsTrue(Lines.Match('  C:\P\Unit1.pas(12,5): error E2003: Undeclared identifier: ''x'' [C:\P\App.dproj]',
      Finding));
    Assert.AreEqual('C:\P\Unit1.pas', Finding.FileName);
    Assert.AreEqual(12, Finding.Line);
    Assert.AreEqual(5, Finding.Column);
    Assert.AreEqual('E2003', Finding.Code);
    Assert.AreEqual('Undeclared identifier: ''x''', Finding.Message, 'ohne Projekt in Klammern');
    Assert.IsTrue(Lines.Match('Unit2.pas(7): warning W1000: Symbol ''Old'' is deprecated', Finding));
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Warning);
    Assert.IsTrue(Lines.Match('Unit2.pas(7): dcc hint H2443: Inline function not expanded', Finding));
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Info);
    Assert.AreEqual('H2443', Finding.Code);
    Assert.IsTrue(Lines.Match('MSBUILD : error MSB1009: Project file does not exist.', Finding));
    Assert.AreEqual('', Finding.FileName, 'Werkzeugname ist keine Datei');
    Assert.AreEqual('MSB1009', Finding.Code);
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Error);
    Assert.IsTrue(Lines.Match('C:\P\App.dproj : warning MSB3277: Konflikte', Finding));
    Assert.AreEqual('C:\P\App.dproj', Finding.FileName);
    Assert.AreEqual(0, Finding.Line);
    Assert.IsFalse(Lines.Match('Build succeeded.', Finding));
    Assert.IsFalse(Lines.Match('    0 Error(s)', Finding));
  finally
    Lines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.GenericLines;
var
  Lines: TAtlasTaskLineMatcher;
  Finding: TAtlasTaskFinding;
begin
  Lines := Matcher(TAtlasTaskMatcherKind.Generic);
  try
    Assert.IsTrue(Lines.Match('Datei.pas(12): Text', Finding));
    Assert.AreEqual('Datei.pas', Finding.FileName);
    Assert.AreEqual(12, Finding.Line);
    Assert.AreEqual('Text', Finding.Message);
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Error);
    Assert.IsTrue(Lines.Match('src\a.c(3,9): warning C4996: veraltet', Finding));
    Assert.AreEqual(9, Finding.Column);
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Warning);
    Assert.AreEqual('C4996', Finding.Code);
    Assert.AreEqual('veraltet', Finding.Message);
    Assert.IsTrue(Lines.Match('lib/x.py:10:4: Hinweis zu lang', Finding));
    Assert.AreEqual('lib/x.py', Finding.FileName);
    Assert.AreEqual(4, Finding.Column);
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Info);
    Assert.IsFalse(Lines.Match('fertig in 3 s', Finding));
  finally
    Lines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.CustomMatcherWithSeverityMap;
var
  Spec: TAtlasTaskMatcher;
  Lines: TAtlasTaskLineMatcher;
  Finding: TAtlasTaskFinding;
begin
  // Fremdes Werkzeug: „[BAD] Kunde.pas L12 C4 K101 Text“.
  Spec := TAtlasTaskMatcher.Create(TAtlasTaskMatcherKind.Custom);
  Spec.Regex := '^\[(?<severity>\w+)\] (?<file>\S+) L(?<line>\d+)(?: C(?<column>\d+))? (?<code>K\d+) ' +
    '(?<message>.*)$';
  Spec.SeverityWords := TArray<string>.Create('bad', 'meh');
  Spec.SeverityValues := [TAtlasTaskSeverity.Error, TAtlasTaskSeverity.Warning];
  Spec.DefaultSeverity := TAtlasTaskSeverity.Info;
  Lines := TAtlasTaskLineMatcher.Create(Spec);
  try
    Assert.AreEqual('', Lines.Error);
    Assert.IsTrue(Lines.Match('[BAD] Kunde.pas L12 C4 K101 Feld ungenutzt', Finding));
    Assert.AreEqual('Kunde.pas', Finding.FileName);
    Assert.AreEqual(12, Finding.Line);
    Assert.AreEqual(4, Finding.Column);
    Assert.AreEqual('K101', Finding.Code);
    Assert.AreEqual('Feld ungenutzt', Finding.Message);
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Error);
    Assert.IsTrue(Lines.Match('[Meh] Kunde.pas L13 K102 Name', Finding), 'Spalte fehlt');
    Assert.AreEqual(0, Finding.Column);
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Warning, 'Groß-/Kleinschreibung egal');
    Assert.IsTrue(Lines.Match('[warning] Kunde.pas L14 K103 x', Finding));
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Warning, 'Standardwort ohne Eintrag');
    Assert.IsTrue(Lines.Match('[NOTE] Kunde.pas L15 K104 y', Finding));
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Info, 'unbekannt: severity des Musters');
    Assert.IsFalse(Lines.Match('Zusammenfassung: 4 Meldungen', Finding));
  finally
    Lines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.CustomMatcherErrorsAndGroupNumbers;
var
  Spec: TAtlasTaskMatcher;
  Lines: TAtlasTaskLineMatcher;
  Finding: TAtlasTaskFinding;
begin
  Assert.AreEqual(2, TAtlasTaskLineMatcher.GroupNumber('(a)(?<file>b)', 'file'));
  Assert.AreEqual(1, TAtlasTaskLineMatcher.GroupNumber('(?:x)\((?<line>\d+)', 'line'), '\( und (?: zählen nicht');
  Assert.AreEqual(2, TAtlasTaskLineMatcher.GroupNumber('[(](a)(?P<code>c)', 'code'), '( in [...] zählt nicht');
  Assert.AreEqual(2, TAtlasTaskLineMatcher.GroupNumber('(?<=x)(a)(?''message''m)', 'message'),
    'Rückschau zählt nicht');
  Assert.AreEqual(0, TAtlasTaskLineMatcher.GroupNumber('(a)', 'file'));
  // Ungültiger Ausdruck: Fehlertext, keine Befunde, keine Ausnahme.
  Spec := TAtlasTaskMatcher.Create(TAtlasTaskMatcherKind.Custom);
  Spec.Regex := '(?<file>[a-';
  Lines := TAtlasTaskLineMatcher.Create(Spec);
  try
    Assert.AreNotEqual('', Lines.Error);
    Assert.IsFalse(Lines.Match('[a-', Finding));
  finally
    Lines.Free;
  end;
  // Ohne Gruppe message: die ganze Zeile.
  Spec.Regex := '^(?<file>\S+\.pas)!(?<line>\d+)';
  Lines := TAtlasTaskLineMatcher.Create(Spec);
  try
    Assert.IsTrue(Lines.Match('A.pas!3 kaputt ', Finding));
    Assert.AreEqual('A.pas!3 kaputt', Finding.Message);
    Assert.IsTrue(Finding.Severity = TAtlasTaskSeverity.Error);
  finally
    Lines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.NoMatcherFindsNothing;
var
  Lines: TAtlasTaskLineMatcher;
  Finding: TAtlasTaskFinding;
begin
  Lines := Matcher(TAtlasTaskMatcherKind.None);
  try
    Assert.IsFalse(Lines.Match('Datei.pas(12): Text', Finding));
  finally
    Lines.Free;
  end;
end;

procedure TAtlasTaskMatchersTests.PathsResolveAgainstCwdProjectAndSearchPath;
var
  Exists: TAtlasTaskFileExists;
  Project, Search: TArray<string>;
begin
  Exists :=
    function(const AFileName: string): Boolean
    begin
      Result := SameText(AFileName, 'C:\Repo\Packages\A.pas') or SameText(AFileName, 'C:\Lib\Util.pas');
    end;
  Project := TArray<string>.Create('C:\Repo\Source\Core\Kunde.pas', 'C:\Repo\Source\Form1.pas');
  Search := TArray<string>.Create('', 'C:\Lib\');
  Assert.AreEqual('C:\Repo\Packages\A.pas', TAtlasTaskPaths.Resolve('Packages/A.pas', 'C:\Repo', Project, Search,
    Exists), 'gegen den Arbeitsordner');
  Assert.AreEqual('C:\Repo\Packages\A.pas', TAtlasTaskPaths.Resolve('.\Tools\..\Packages\A.pas', 'C:\Repo\', nil,
    nil, Exists));
  Assert.AreEqual('C:\Repo\Source\Core\Kunde.pas', TAtlasTaskPaths.Resolve('Core\Kunde.pas', 'C:\Anders', Project,
    Search, Exists), 'Ende eines Pfads im Projekt');
  Assert.AreEqual('C:\Repo\Source\Form1.pas', TAtlasTaskPaths.Resolve('form1.pas', 'C:\Anders', Project, Search,
    Exists));
  Assert.AreEqual('C:\Lib\Util.pas', TAtlasTaskPaths.Resolve('Util.pas', 'C:\Repo', Project, Search, Exists),
    'Suchpfad');
  Assert.AreEqual('C:\Repo\Fehlt.pas', TAtlasTaskPaths.Resolve('Fehlt.pas', 'C:\Repo', Project, Search, Exists),
    'nicht gefunden: gegen den Arbeitsordner');
  Assert.AreEqual('D:\x\y.pas', TAtlasTaskPaths.Resolve('D:/x/./y.pas', 'C:\Repo', Project, Search, Exists),
    'absolut bleibt');
  Assert.AreEqual('\\server\share\a.pas', TAtlasTaskPaths.Normalize('\\server\share\b\..\a.pas'));
  Assert.AreEqual('C:\a.pas', TAtlasTaskPaths.Normalize('C:\..\a.pas'), 'nicht über das Laufwerk hinaus');
  Assert.AreEqual('', TAtlasTaskPaths.Resolve('', 'C:\Repo', Project, Search, Exists));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTaskMatchersTests);

end.
