unit Atlas.UI.Settings.Strings.Tests;

// Texte des Features Einstellungen: jede Id in beiden Sprachen, gleiche Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsStringsTests = class
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
  Atlas.UI.Settings.Strings;

procedure TAtlasSettingsStringsTests.EveryTextExistsInBothLanguages;
var
  mId: TAtlasSettingsTextId;
  mGerman: string;
  mCount: Integer;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  mCount := 0;
  try
    for mId := Low(TAtlasSettingsTextId) to High(TAtlasSettingsTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasSettingsStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      AssertTextPair(mGerman, TAtlasSettingsStrings.Text(mId), Ord(mId));
      Inc(mCount);
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
  Assert.AreEqual(Ord(High(TAtlasSettingsTextId)) + 1, mCount, 'jede Id geprüft');
end;

procedure TAtlasSettingsStringsTests.FollowsLanguageOfBase;
var
  mId: TAtlasSettingsTextId;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TAtlasLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für die Texte des Features.
  mSaved := TAtlasStrings.Language;
  mDiffers := 0;
  try
    for mId := Low(TAtlasSettingsTextId) to High(TAtlasSettingsTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasSettingsStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      if mGerman <> TAtlasSettingsStrings.Text(mId) then
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
  TDUnitX.RegisterTestFixture(TAtlasSettingsStringsTests);

end.
