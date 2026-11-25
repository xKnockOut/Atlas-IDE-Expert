unit Atlas.UI.Debug.ObjectMarks.Strings.Tests;

// Texte für markierte Objekte (#839): jede Id in beiden Sprachen, gleiche Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasObjectMarksStringsTests = class
  public
    [Test]
    procedure EveryTextExistsInBothLanguages;
    [Test]
    procedure FollowsLanguageOfBase;
  end;

implementation

uses
  Atlas.Plugin.Localization.Strings,
  Atlas.Plugin.Localization.Strings.Tests,
  Atlas.UI.Debug.ObjectMarks.Strings;

{ TAtlasObjectMarksStringsTests }

procedure TAtlasObjectMarksStringsTests.EveryTextExistsInBothLanguages;
var
  mId: TAtlasObjectMarksTextId;
  mGerman: string;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    for mId := Low(TAtlasObjectMarksTextId) to High(TAtlasObjectMarksTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasObjectMarksStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      AssertTextPair(mGerman, TAtlasObjectMarksStrings.Text(mId), Ord(mId));
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasObjectMarksStringsTests.FollowsLanguageOfBase;
var
  mId: TAtlasObjectMarksTextId;
  mGerman: string;
  mDiffers: Integer;
  mSaved: TAtlasLanguage;
begin
  // Kein eigener Sprachschalter: Ein Wechsel in Base gilt sofort auch für die Texte des Moduls.
  mSaved := TAtlasStrings.Language;
  mDiffers := 0;
  try
    for mId := Low(TAtlasObjectMarksTextId) to High(TAtlasObjectMarksTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasObjectMarksStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      if mGerman <> TAtlasObjectMarksStrings.Text(mId) then
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
  TDUnitX.RegisterTestFixture(TAtlasObjectMarksStringsTests);

end.
