unit Atlas.UI.Build.Strings.Tests;

// Texte des Moduls Build-Werkzeuge (#1455): jede Id in beiden Sprachen, gleiche Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasBuildStringsTests = class
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
  Atlas.UI.Build.Strings;

procedure TAtlasBuildStringsTests.EveryTextExistsInBothLanguages;
var
  mId: TAtlasBuildTextId;
  mGerman: string;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    for mId := Low(TAtlasBuildTextId) to High(TAtlasBuildTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasBuildStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      AssertTextPair(mGerman, TAtlasBuildStrings.Text(mId), Ord(mId));
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasBuildStringsTests.FollowsLanguageOfBase;
var
  mId: TAtlasBuildTextId;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TAtlasLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für die Texte des Moduls.
  mSaved := TAtlasStrings.Language;
  mDiffers := 0;
  try
    for mId := Low(TAtlasBuildTextId) to High(TAtlasBuildTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasBuildStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      if mGerman <> TAtlasBuildStrings.Text(mId) then
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
  TDUnitX.RegisterTestFixture(TAtlasBuildStringsTests);

end.
