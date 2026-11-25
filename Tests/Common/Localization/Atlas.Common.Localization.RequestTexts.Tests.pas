unit Atlas.Common.Localization.RequestTexts.Tests;

// Gemeinsame Texte zu Anfragen (#1458): Aufzählungen mit „und“ bzw. „oder“, fehlende Argumente in Einzahl und
// Mehrzahl und erlaubte Werte, je in beiden Sprachen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Localization.Texts;

type
  [TestFixture]
  TRequestTextsTests = class
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
  Atlas.Common.Localization.RequestTexts;

{ TRequestTextsTests }

procedure TRequestTextsTests.Setup;
begin
  FSaved := TAtlasLocale.Language;
end;

procedure TRequestTextsTests.TearDown;
begin
  TAtlasLocale.Use(FSaved);
end;

procedure TRequestTextsTests.JoinedUsesCommasAndLastWord;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('', TRequestTexts.Joined([], False));
  Assert.AreEqual('a', TRequestTexts.Joined(['a'], False));
  Assert.AreEqual('a und b', TRequestTexts.Joined(['a', 'b'], False));
  Assert.AreEqual('a, b oder c', TRequestTexts.Joined(['a', 'b', 'c'], True));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('a, b and c', TRequestTexts.Joined(['a', 'b', 'c'], False));
  Assert.AreEqual('a or b', TRequestTexts.Joined(['a', 'b'], True));
end;

procedure TRequestTextsTests.MissingNamesOneOrMany;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('Argument "uri" fehlt', TRequestTexts.Missing(['uri']));
  Assert.AreEqual('Argumente "uri", "position" und "name" fehlen', TRequestTexts.Missing(['uri', 'position', 'name']));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('Argument "uri" is missing', TRequestTexts.Missing(['uri']));
  Assert.AreEqual('Arguments "line" and "column" are missing', TRequestTexts.Missing(['line', 'column']));
end;

procedure TRequestTextsTests.ChoiceListsAllowedValues;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('"format" ist markdown oder json', TRequestTexts.Choice('format', ['markdown', 'json']));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('"section" is hotspots or coupling', TRequestTexts.Choice('section', ['hotspots', 'coupling']));
end;

procedure TRequestTextsTests.NoProjectFollowsLanguage;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('Kein Projekt geladen', TRequestTexts.NoProject);
  Assert.AreEqual('Kein Projekt geladen; Datei angeben', TRequestTexts.NoProjectGiveFile);
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('No project loaded', TRequestTexts.NoProject);
  Assert.AreEqual('No project loaded; specify a file', TRequestTexts.NoProjectGiveFile);
end;

initialization
  TDUnitX.RegisterTestFixture(TRequestTextsTests);

end.
