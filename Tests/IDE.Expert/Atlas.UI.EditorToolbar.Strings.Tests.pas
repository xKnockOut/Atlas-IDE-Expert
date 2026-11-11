unit Atlas.UI.EditorToolbar.Strings.Tests;

// Texte des Features Editorleiste: jede Id in beiden Sprachen, gleiche Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasEditorToolbarStringsTests = class
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
  Atlas.UI.EditorToolbar.Strings;

procedure TAtlasEditorToolbarStringsTests.EveryTextExistsInBothLanguages;
var
  mId: TAtlasEditorToolbarTextId;
  mGerman: string;
  mCount: Integer;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  mCount := 0;
  try
    for mId := Low(TAtlasEditorToolbarTextId) to High(TAtlasEditorToolbarTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasEditorToolbarStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      AssertTextPair(mGerman, TAtlasEditorToolbarStrings.Text(mId), Ord(mId));
      Inc(mCount);
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
  Assert.AreEqual(Ord(High(TAtlasEditorToolbarTextId)) + 1, mCount, 'jede Id geprüft');
end;

procedure TAtlasEditorToolbarStringsTests.FollowsLanguageOfBase;
var
  mId: TAtlasEditorToolbarTextId;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TAtlasLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für die Texte des Features.
  mSaved := TAtlasStrings.Language;
  mDiffers := 0;
  try
    for mId := Low(TAtlasEditorToolbarTextId) to High(TAtlasEditorToolbarTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasEditorToolbarStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      if mGerman <> TAtlasEditorToolbarStrings.Text(mId) then
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
  TDUnitX.RegisterTestFixture(TAtlasEditorToolbarStringsTests);

end.
