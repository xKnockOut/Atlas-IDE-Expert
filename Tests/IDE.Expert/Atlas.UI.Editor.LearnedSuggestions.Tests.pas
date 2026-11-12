unit Atlas.UI.Editor.LearnedSuggestions.Tests;

// Tests für die Texte der gelernten Vorschläge (#1890): Befehl, Optionsseite und Liste in beiden Sprachen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLearnedTextsTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure GermanTexts;
    [Test]
    procedure EnglishTexts;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Localization.Language,
  Atlas.UI.Editor.LearnedSuggestions;

{ TAtlasLearnedTextsTests }

procedure TAtlasLearnedTextsTests.TearDown;
begin
  TAtlasTextLanguage.Current := TAtlasLanguage.German;
end;

procedure TAtlasLearnedTextsTests.GermanTexts;
begin
  TAtlasTextLanguage.Current := TAtlasLanguage.German;
  Assert.AreEqual('Gelernte Vorschläge anzeigen …', TAtlasLearnedTexts.Text(TAtlasLearnedText.Command));
  Assert.AreEqual('3× übernommen, 1× verworfen', Format(TAtlasLearnedTexts.Text(TAtlasLearnedText.Used), [3, 1]));
end;

procedure TAtlasLearnedTextsTests.EnglishTexts;
begin
  TAtlasTextLanguage.Current := TAtlasLanguage.English;
  Assert.AreEqual('Show learned suggestions …', TAtlasLearnedTexts.Text(TAtlasLearnedText.Command));
  Assert.AreEqual('Forget', TAtlasLearnedTexts.Text(TAtlasLearnedText.Forget));
  Assert.AreEqual('atlas.json', TAtlasLearnedTexts.Text(TAtlasLearnedText.OriginTeam));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasLearnedTextsTests);

end.
