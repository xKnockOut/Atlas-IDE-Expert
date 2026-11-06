unit Shell.Texts.Tests;

// Gemeinsame Texte der Shell (#1458): Aufzählungen mit „und“ bzw. „oder“, fehlende Argumente in Einzahl und
// Mehrzahl und erlaubte Werte, je in beiden Sprachen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Localization.Texts;

type
  [TestFixture]
  TShellTextsTests = class
  private
    FSaved: TTextLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure JoinedUsesCommasAndLastWord;
    [Test]
    procedure MissingNamesOneOrMany;
    [Test]
    procedure ChoiceListsAllowedValues;
    [Test]
    procedure NoProjectFollowsLanguage;
  end;

implementation

uses
  Shell.Texts;

procedure TShellTextsTests.Setup;
begin
  FSaved := TAtlasLocale.Language;
end;

procedure TShellTextsTests.TearDown;
begin
  TAtlasLocale.Use(FSaved);
end;

procedure TShellTextsTests.JoinedUsesCommasAndLastWord;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('', TShellTexts.Joined([], False));
  Assert.AreEqual('a', TShellTexts.Joined(['a'], False));
  Assert.AreEqual('a und b', TShellTexts.Joined(['a', 'b'], False));
  Assert.AreEqual('a, b oder c', TShellTexts.Joined(['a', 'b', 'c'], True));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('a, b and c', TShellTexts.Joined(['a', 'b', 'c'], False));
  Assert.AreEqual('a or b', TShellTexts.Joined(['a', 'b'], True));
end;

procedure TShellTextsTests.MissingNamesOneOrMany;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('Argument "uri" fehlt', TShellTexts.Missing(['uri']));
  Assert.AreEqual('Argumente "uri", "position" und "name" fehlen', TShellTexts.Missing(['uri', 'position', 'name']));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('Argument "uri" is missing', TShellTexts.Missing(['uri']));
  Assert.AreEqual('Arguments "line" and "column" are missing', TShellTexts.Missing(['line', 'column']));
end;

procedure TShellTextsTests.ChoiceListsAllowedValues;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('"format" ist markdown oder json', TShellTexts.Choice('format', ['markdown', 'json']));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('"section" is hotspots or coupling', TShellTexts.Choice('section', ['hotspots', 'coupling']));
end;

procedure TShellTextsTests.NoProjectFollowsLanguage;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('Kein Projekt geladen', TShellTexts.NoProject);
  Assert.AreEqual('Kein Projekt geladen; Datei angeben', TShellTexts.NoProjectGiveFile);
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('No project loaded', TShellTexts.NoProject);
  Assert.AreEqual('No project loaded; specify a file', TShellTexts.NoProjectGiveFile);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellTextsTests);

end.
