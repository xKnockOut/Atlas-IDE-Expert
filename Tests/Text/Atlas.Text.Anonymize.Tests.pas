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
  end;

implementation

uses
  Atlas.Text.Anonymize;

const
  Root = 'C:\Projekte\Geheim';

procedure TTextAnonymizerTests.ReplacesWorkspaceAndOtherPaths;
begin
  Assert.AreEqual('Datei <pfad> und <pfad> fehlt',
    TTextAnonymizer.AnonymizePaths('Datei E:\Andere\a.pas und \\server\share\b.inc fehlt', [Root], []));
  Assert.AreEqual('<ws>\src\a.pas', TTextAnonymizer.AnonymizePaths(Root + '\src\a.pas', [Root + '\'], []));
  Assert.AreEqual('<pfad> und <ws>/a.pas',
    TTextAnonymizer.AnonymizePaths('D:\x\y.dpr und C:/Projekte/Geheim/a.pas', [Root], []));
end;

procedure TTextAnonymizerTests.ReplacesFileUrisAndJsonEscapes;
begin
  Assert.AreEqual('<ws>/Main.pas', TTextAnonymizer.AnonymizePaths('file:///C%3A/Projekte/Geheim/Main.pas', [Root], []));
  Assert.AreEqual('"<ws>\\src"', TTextAnonymizer.AnonymizePaths('"C:\\Projekte\\Geheim\\src"', [Root], []));
  Assert.AreEqual('<pfad>', TTextAnonymizer.AnonymizePaths('file:///d%3A/x/y.pas', [Root], []));
end;

procedure TTextAnonymizerTests.LongestRootFirst;
begin
  Assert.AreEqual('<ws>\a.pas', TTextAnonymizer.AnonymizePaths(Root + '\Sub\a.pas', [Root, Root + '\Sub'], []));
end;

procedure TTextAnonymizerTests.KeepsTimesAndWebUrls;
begin
  Assert.AreEqual('Zeit 10:00:01, http://x.de',
    TTextAnonymizer.AnonymizePaths('Zeit 10:00:01, http://x.de', [Root], []));
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

initialization
  TDUnitX.RegisterTestFixture(TTextAnonymizerTests);

end.
