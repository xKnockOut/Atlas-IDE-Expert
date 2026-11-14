unit Atlas.UI.Debug.Profile.Strings.Tests;

// Texte des Profilers (#2057): jede Id in beiden Sprachen, gleiche Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasProfileStringsTests = class
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
  Atlas.UI.Debug.Profile.Strings;

procedure TAtlasProfileStringsTests.EveryTextExistsInBothLanguages;
var
  mId: TAtlasProfileTextId;
  mGerman: string;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    for mId := Low(TAtlasProfileTextId) to High(TAtlasProfileTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasProfileStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      AssertTextPair(mGerman, TAtlasProfileStrings.Text(mId), Ord(mId));
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasProfileStringsTests.FollowsLanguageOfBase;
var
  mId: TAtlasProfileTextId;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TAtlasLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für die Texte des Moduls.
  mSaved := TAtlasStrings.Language;
  mDiffers := 0;
  try
    for mId := Low(TAtlasProfileTextId) to High(TAtlasProfileTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasProfileStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      if mGerman <> TAtlasProfileStrings.Text(mId) then
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
  TDUnitX.RegisterTestFixture(TAtlasProfileStringsTests);

end.
