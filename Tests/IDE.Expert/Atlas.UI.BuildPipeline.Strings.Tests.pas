unit Atlas.UI.BuildPipeline.Strings.Tests;

// Texte des Moduls Build-Pipeline (#1455): jede Id in beiden Sprachen, gleiche Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.BuildPipeline')]
  TAtlasBuildPipelineStringsTests = class
  public
    [Test]
    procedure EveryTextExistsInBothLanguages;
    [Test]
    procedure FollowsLanguageOfBase;
  end;

implementation

uses
  Atlas.UI.Strings,
  Atlas.UI.Strings.Tests,
  Atlas.UI.BuildPipeline.Strings;

procedure TAtlasBuildPipelineStringsTests.EveryTextExistsInBothLanguages;
var
  mId: TAtlasBuildPipelineTextId;
  mGerman: string;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    for mId := Low(TAtlasBuildPipelineTextId) to High(TAtlasBuildPipelineTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasBuildPipelineStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      AssertTextPair(mGerman, TAtlasBuildPipelineStrings.Text(mId), Ord(mId));
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasBuildPipelineStringsTests.FollowsLanguageOfBase;
var
  mId: TAtlasBuildPipelineTextId;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TAtlasLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für die Texte des Moduls.
  mSaved := TAtlasStrings.Language;
  mDiffers := 0;
  try
    for mId := Low(TAtlasBuildPipelineTextId) to High(TAtlasBuildPipelineTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasBuildPipelineStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      if mGerman <> TAtlasBuildPipelineStrings.Text(mId) then
      begin
        Inc(mDiffers);
      end;
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
  Assert.IsTrue(mDiffers > 0, 'kein Text folgt der Sprache von Base');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBuildPipelineStringsTests);

end.
