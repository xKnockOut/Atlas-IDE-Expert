unit Atlas.UI.SymbolPath.Strings.Tests;

// Texte des Features Symbolpfad: jede Id in beiden Sprachen, gleiche Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSymbolPathStringsTests = class
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
  Atlas.UI.SymbolPath.Strings;

procedure TAtlasSymbolPathStringsTests.EveryTextExistsInBothLanguages;
var
  mId: TAtlasSymbolPathTextId;
  mGerman: string;
  mCount: Integer;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  mCount := 0;
  try
    for mId := Low(TAtlasSymbolPathTextId) to High(TAtlasSymbolPathTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasSymbolPathStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      AssertTextPair(mGerman, TAtlasSymbolPathStrings.Text(mId), Ord(mId));
      Inc(mCount);
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
  Assert.AreEqual(Ord(High(TAtlasSymbolPathTextId)) + 1, mCount, 'jede Id geprüft');
end;

procedure TAtlasSymbolPathStringsTests.FollowsLanguageOfBase;
var
  mId: TAtlasSymbolPathTextId;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TAtlasLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für die Texte des Features.
  mSaved := TAtlasStrings.Language;
  mDiffers := 0;
  try
    for mId := Low(TAtlasSymbolPathTextId) to High(TAtlasSymbolPathTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasSymbolPathStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      if mGerman <> TAtlasSymbolPathStrings.Text(mId) then
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
  TDUnitX.RegisterTestFixture(TAtlasSymbolPathStringsTests);

end.
