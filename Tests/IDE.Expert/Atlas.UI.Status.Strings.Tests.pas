unit Atlas.UI.Status.Strings.Tests;

// Texte des Features Statusfenster: jede Id in beiden Sprachen, gleiche Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStatusStringsTests = class
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
  Atlas.UI.Status.Strings;

procedure TAtlasStatusStringsTests.EveryTextExistsInBothLanguages;
var
  mId: TAtlasStatusTextId;
  mGerman: string;
  mCount: Integer;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  mCount := 0;
  try
    for mId := Low(TAtlasStatusTextId) to High(TAtlasStatusTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasStatusStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      AssertTextPair(mGerman, TAtlasStatusStrings.Text(mId), Ord(mId));
      Inc(mCount);
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
  Assert.AreEqual(Ord(High(TAtlasStatusTextId)) + 1, mCount, 'jede Id geprüft');
end;

procedure TAtlasStatusStringsTests.FollowsLanguageOfBase;
var
  mId: TAtlasStatusTextId;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TAtlasLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für die Texte des Features.
  mSaved := TAtlasStrings.Language;
  mDiffers := 0;
  try
    for mId := Low(TAtlasStatusTextId) to High(TAtlasStatusTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasStatusStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      if mGerman <> TAtlasStatusStrings.Text(mId) then
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
  TDUnitX.RegisterTestFixture(TAtlasStatusStringsTests);

end.
