unit Atlas.Text.Anonymize.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Regeln der Fehlerbericht-Anonymisierung, gemeinsam für Server und Plugin (D-02).</summary>
  [TestFixture]
  TTextAnonymizerTests = class
  public
    [Test]
    procedure ReplacesWorkspaceAndOtherPaths;
    [Test]
    procedure ReplacesFileUrisAndJsonEscapes;
    [Test]
    procedure LongestRootFirst;
    [Test]
    procedure KeepsTimesAndWebUrls;
    [Test]
    procedure ReplacesIdentity;
    [Test]
    procedure ReplacesQuotedValues;
    [Test]
    procedure UserNameBeforeUmlaut;
    [Test]
    procedure FenceSafe;
    [Test]
    procedure WorkspaceRootAloneStays;
    [Test]
    procedure RedactsMarkedValues;
    [Test]
    procedure MarkedPathUnderRootAndBareName;
    [Test]
    procedure JsonValuesKeepKeywordsOnly;
    [Test]
    procedure KeywordsAreLowerWordsAndPlatforms;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Anonymize,
  Atlas.Text.LogMarks;

const
  cRoot = 'C:\Projekte\Geheim';

procedure TTextAnonymizerTests.ReplacesWorkspaceAndOtherPaths;
begin
  Assert.AreEqual('Datei <pfad> und <pfad> fehlt',
    TTextAnonymizer.AnonymizePaths('Datei E:\Andere\a.pas und \\server\share\b.inc fehlt', [cRoot], []));
  Assert.AreEqual('<ws>/<datei>.pas', TTextAnonymizer.AnonymizePaths(cRoot + '\src\a.pas', [cRoot + '\'], []));
  Assert.AreEqual('<pfad> und <ws>/<datei>.pas',
    TTextAnonymizer.AnonymizePaths('D:\x\y.dpr und C:/Projekte/Geheim/a.pas', [cRoot], []));
end;

procedure TTextAnonymizerTests.ReplacesFileUrisAndJsonEscapes;
begin
  Assert.AreEqual('<ws>/<datei>.pas', TTextAnonymizer.AnonymizePaths('file:///C%3A/Projekte/Geheim/Main.pas', [cRoot],
    []));
  Assert.AreEqual('"<ws>/<datei>"', TTextAnonymizer.AnonymizePaths('"C:\\Projekte\\Geheim\\src"', [cRoot], []));
  Assert.AreEqual('<pfad>', TTextAnonymizer.AnonymizePaths('file:///d%3A/x/y.pas', [cRoot], []));
end;

procedure TTextAnonymizerTests.LongestRootFirst;
begin
  Assert.AreEqual('<ws>/<datei>.pas',
    TTextAnonymizer.AnonymizePaths(cRoot + '\Sub\a.pas', [cRoot, cRoot + '\Sub'], []));
end;

procedure TTextAnonymizerTests.KeepsTimesAndWebUrls;
begin
  Assert.AreEqual('Zeit 10:00:01, http://x.de', // lsp-ignore: security-insecure-http
    TTextAnonymizer.AnonymizePaths('Zeit 10:00:01, http://x.de', [cRoot], [])); // lsp-ignore: security-insecure-http
end;

procedure TTextAnonymizerTests.ReplacesIdentity;
begin
  Assert.AreEqual('Hallo <benutzer>', TTextAnonymizer.AnonymizePaths('Hallo Marco', [], ['marco', 'ab']));
  Assert.AreEqual('ab', TTextAnonymizer.AnonymizePaths('ab', [], ['ab']));
end;

procedure TTextAnonymizerTests.ReplacesQuotedValues;
begin
  Assert.AreEqual('Unit "<wert>" und „<wert>“, don''t',
    TTextAnonymizer.AnonymizeLogLine('Unit "Foo" und „Bar“, don''t', [], []));
  Assert.AreEqual('«<wert>» und ''<wert>''', TTextAnonymizer.ReplaceQuoted('«x» und ''y'''));
  Assert.AreEqual('"<ws>"', TTextAnonymizer.ReplaceQuoted('"<ws>"'));
end;

procedure TTextAnonymizerTests.UserNameBeforeUmlaut;
begin
  // Ein Umlaut gehört zum Wort: Kein Pfad beginnt mitten in "Ärger:\x".
  Assert.AreEqual(#$00C4'C:\x', TTextAnonymizer.AnonymizePaths(#$00C4'C:\x', [], []));
  // Apostroph nach Umlaut ist ein Apostroph im Wort, kein Anführungszeichen.
  Assert.AreEqual('Gr'#$00FC#$00DF'''e ''<wert>''', TTextAnonymizer.ReplaceQuoted('Gr'#$00FC#$00DF'''e ''x'''));
end;

procedure TTextAnonymizerTests.FenceSafe;
begin
  Assert.AreEqual('a ` ` ` b', TTextAnonymizer.FenceSafe('a ``` b'));
end;

procedure TTextAnonymizerTests.WorkspaceRootAloneStays;
begin
  Assert.AreEqual('Ordner <ws> geladen', TTextAnonymizer.AnonymizePaths('Ordner ' + cRoot + ' geladen', [cRoot], []));
  // Unterordner und Dateiname verraten das Projekt (#1478): nur die Endung bleibt.
  Assert.AreEqual('<ws>/<datei>.dproj, <ws>/<datei>', TTextAnonymizer.AnonymizePaths(cRoot +
    '\Kunden\Kunden.dproj, ' + cRoot + '\Kunden\Daten', [cRoot], []));
end;

procedure TTextAnonymizerTests.RedactsMarkedValues;
begin
  Assert.AreEqual('Typ <name> fehlt: <text>', TTextAnonymizer.AnonymizeLogLine('Typ ' + TLogMarks.Name('TKunde') +
    ' fehlt: ' + TLogMarks.Text('Kunde.Speichern ist nil'), [cRoot], []));
  Assert.AreEqual('Typ <name>', TTextAnonymizer.RedactMarks('Typ ' + TLogMarks.Name('TKunde'), []));
end;

procedure TTextAnonymizerTests.MarkedPathUnderRootAndBareName;
begin
  Assert.AreEqual('<ws>/<datei>.pas', TTextAnonymizer.RedactMarks(TLogMarks.Path(cRoot + '\Kunde.pas'), [cRoot]));
  Assert.AreEqual('<pfad>', TTextAnonymizer.RedactMarks(TLogMarks.Path('D:\Andere\Kunde.pas'), [cRoot]));
  Assert.AreEqual('<datei>.pas', TTextAnonymizer.RedactMarks(TLogMarks.Path('Kunde.pas'), [cRoot]));
  Assert.AreEqual('<datei>', TTextAnonymizer.RedactMarks(TLogMarks.Path('Kunden'), [cRoot]));
end;

procedure TTextAnonymizerTests.JsonValuesKeepKeywordsOnly;
var
  mText: string;
begin
  mText := TTextAnonymizer.AnonymizeJsonValues('{"logLevel": "warning", "rules": {"unused-unit": "off"}, ' +
    '"exclude": ["Kunden.Daten", "**/Generiert/*.pas"], "project": "Kunden.dproj", "count": 3, "on": true, ' +
    '"config": "Release"}');
  Assert.Contains(mText, '"warning"');
  Assert.Contains(mText, '"unused-unit"');
  Assert.Contains(mText, '"off"');
  Assert.Contains(mText, '"Release"');
  Assert.Contains(mText, '3');
  Assert.Contains(mText, 'true');
  Assert.IsFalse(mText.Contains('Kunden'), 'Unit- und Projektnamen');
  Assert.IsFalse(mText.Contains('Generiert'), 'Muster mit Ordnernamen');
  Assert.AreEqual('{}', TTextAnonymizer.AnonymizeJsonValues('kein JSON'));
end;

procedure TTextAnonymizerTests.KeywordsAreLowerWordsAndPlatforms;
begin
  Assert.IsTrue(TTextAnonymizer.IsKeyword('unused-unit'));
  Assert.IsTrue(TTextAnonymizer.IsKeyword('editor.font_size'));
  Assert.IsTrue(TTextAnonymizer.IsKeyword('1.2.0'));
  Assert.IsTrue(TTextAnonymizer.IsKeyword('Win64'));
  Assert.IsTrue(TTextAnonymizer.IsKeyword(''));
  // Schon ersetzt (SettingsWithoutPaths des Plugins) bleibt ersetzt.
  Assert.IsTrue(TTextAnonymizer.IsKeyword('<pfad>'));
  Assert.IsFalse(TTextAnonymizer.IsKeyword('<Kunden>'));
  Assert.IsFalse(TTextAnonymizer.IsKeyword('Kunden'));
  Assert.IsFalse(TTextAnonymizer.IsKeyword('kunden--daten'));
  Assert.IsFalse(TTextAnonymizer.IsKeyword('kunden-'));
  Assert.IsFalse(TTextAnonymizer.IsKeyword('src/kunden'));
  Assert.IsFalse(TTextAnonymizer.IsKeyword('https://firma.example'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextAnonymizerTests);

end.
