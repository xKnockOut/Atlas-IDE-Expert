unit Atlas.UI.Editor.RegionFolds.Tests;

// Tests für die Texte zu „Regionen beim Öffnen“ (#1814): Auswahl passend zu den Werten der Einstellung, beide
// Sprachen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasRegionFoldsTextsTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ChoicesMatchSettingValues;
    [Test]
    procedure EnglishTexts;
  end;

implementation

uses
  Atlas.Plugin.Localization.Language,
  Atlas.Core.Settings.Plugin.Store,
  Atlas.UI.Editor.RegionFolds;

{ TAtlasRegionFoldsTextsTests }

procedure TAtlasRegionFoldsTextsTests.TearDown;
begin
  TAtlasTextLanguage.Current := TAtlasLanguage.German;
end;

procedure TAtlasRegionFoldsTextsTests.ChoicesMatchSettingValues;
var
  mChoices: TArray<string>;
begin
  TAtlasTextLanguage.Current := TAtlasLanguage.German;
  mChoices := TAtlasRegionFoldsTexts.Choices;
  Assert.AreEqual(Integer(Length(cAtlasRegionFoldModes)), Integer(Length(mChoices)));
  Assert.AreEqual('unverändert lassen', mChoices[0], 'keep steht vorn');
  Assert.AreEqual('aus (auch keine Befehle)', mChoices[3], 'off steht hinten');
end;

procedure TAtlasRegionFoldsTextsTests.EnglishTexts;
begin
  TAtlasTextLanguage.Current := TAtlasLanguage.English;
  Assert.AreEqual('Collapse all regions', TAtlasRegionFoldsTexts.Text(TAtlasRegionFoldsText.CollapseCommand));
  Assert.AreEqual('Expand all regions', TAtlasRegionFoldsTexts.Text(TAtlasRegionFoldsText.ExpandCommand));
  Assert.AreEqual('collapse all', TAtlasRegionFoldsTexts.Choices[1]);
  Assert.AreEqual('Collapse block', TAtlasRegionFoldsTexts.Text(TAtlasRegionFoldsText.FoldBlockCommand));
  Assert.AreEqual('No collapsed blocks in this file.',
    TAtlasRegionFoldsTexts.Text(TAtlasRegionFoldsText.NoFoldedBlocks));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRegionFoldsTextsTests);

end.
