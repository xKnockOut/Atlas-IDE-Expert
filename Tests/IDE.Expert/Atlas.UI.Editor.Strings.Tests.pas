unit Atlas.UI.Editor.Strings.Tests;

// Texte des Features Editor: jede Id in beiden Sprachen, gleiche Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasEditorStringsTests = class
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
  Atlas.UI.Editor.Strings;

procedure TAtlasEditorStringsTests.EveryTextExistsInBothLanguages;
var
  mId: TAtlasEditorTextId;
  mGerman: string;
  mCount: Integer;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  mCount := 0;
  try
    for mId := Low(TAtlasEditorTextId) to High(TAtlasEditorTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasEditorStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      AssertTextPair(mGerman, TAtlasEditorStrings.Text(mId), Ord(mId));
      Inc(mCount);
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
  Assert.AreEqual(Ord(High(TAtlasEditorTextId)) + 1, mCount, 'jede Id geprüft');
end;

procedure TAtlasEditorStringsTests.FollowsLanguageOfBase;
var
  mId: TAtlasEditorTextId;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TAtlasLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für die Texte des Features.
  mSaved := TAtlasStrings.Language;
  mDiffers := 0;
  try
    for mId := Low(TAtlasEditorTextId) to High(TAtlasEditorTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasEditorStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      if mGerman <> TAtlasEditorStrings.Text(mId) then
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
  TDUnitX.RegisterTestFixture(TAtlasEditorStringsTests);

end.
