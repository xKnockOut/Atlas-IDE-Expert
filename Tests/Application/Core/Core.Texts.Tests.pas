unit Core.Texts.Tests;

// Gemeinsame Texte der Shell (#1458): Aufzählungen mit „und“ bzw. „oder“, fehlende Argumente in Einzahl und
// Mehrzahl und erlaubte Werte, je in beiden Sprachen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Localization.Texts;

type
  [TestFixture]
  TCoreTextsTests = class
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
  Core.Texts;

{ TCoreTextsTests }

procedure TCoreTextsTests.Setup;
begin
  FSaved := TAtlasLocale.Language;
end;

procedure TCoreTextsTests.TearDown;
begin
  TAtlasLocale.Use(FSaved);
end;

procedure TCoreTextsTests.JoinedUsesCommasAndLastWord;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('', TCoreTexts.Joined([], False));
  Assert.AreEqual('a', TCoreTexts.Joined(['a'], False));
  Assert.AreEqual('a und b', TCoreTexts.Joined(['a', 'b'], False));
  Assert.AreEqual('a, b oder c', TCoreTexts.Joined(['a', 'b', 'c'], True));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('a, b and c', TCoreTexts.Joined(['a', 'b', 'c'], False));
  Assert.AreEqual('a or b', TCoreTexts.Joined(['a', 'b'], True));
end;

procedure TCoreTextsTests.MissingNamesOneOrMany;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('Argument "uri" fehlt', TCoreTexts.Missing(['uri']));
  Assert.AreEqual('Argumente "uri", "position" und "name" fehlen', TCoreTexts.Missing(['uri', 'position', 'name']));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('Argument "uri" is missing', TCoreTexts.Missing(['uri']));
  Assert.AreEqual('Arguments "line" and "column" are missing', TCoreTexts.Missing(['line', 'column']));
end;

procedure TCoreTextsTests.ChoiceListsAllowedValues;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('"format" ist markdown oder json', TCoreTexts.Choice('format', ['markdown', 'json']));
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('"section" is hotspots or coupling', TCoreTexts.Choice('section', ['hotspots', 'coupling']));
end;

procedure TCoreTextsTests.NoProjectFollowsLanguage;
begin
  TAtlasLocale.Use(TTextLanguage.German);
  Assert.AreEqual('Kein Projekt geladen', TCoreTexts.NoProject);
  Assert.AreEqual('Kein Projekt geladen; Datei angeben', TCoreTexts.NoProjectGiveFile);
  TAtlasLocale.Use(TTextLanguage.English);
  Assert.AreEqual('No project loaded', TCoreTexts.NoProject);
  Assert.AreEqual('No project loaded; specify a file', TCoreTexts.NoProjectGiveFile);
end;

initialization
  TDUnitX.RegisterTestFixture(TCoreTextsTests);

end.
