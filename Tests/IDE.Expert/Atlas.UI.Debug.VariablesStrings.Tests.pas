unit Atlas.UI.Debug.VariablesStrings.Tests;

// Texte des Fensters „Variablen“ (#853): jede Id in beiden Sprachen, gleiche Platzhalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasVariablesStringsTests = class
  public
    [Test]
    procedure EveryTextExistsInBothLanguages;
    [Test]
    procedure FmtFillsPlaceholders;
  end;

implementation

uses
  Atlas.UI.Strings,
  Atlas.UI.Strings.Tests,
  Atlas.UI.Debug.VariablesStrings;

procedure TAtlasVariablesStringsTests.EveryTextExistsInBothLanguages;
var
  mId: TAtlasVariablesTextId;
  mGerman: string;
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    for mId := Low(TAtlasVariablesTextId) to High(TAtlasVariablesTextId) do
    begin
      TAtlasStrings.Language := TAtlasLanguage.German;
      mGerman := TAtlasVariablesStrings.Text(mId);
      TAtlasStrings.Language := TAtlasLanguage.English;
      AssertTextPair(mGerman, TAtlasVariablesStrings.Text(mId), Ord(mId));
    end;
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasVariablesStringsTests.FmtFillsPlaceholders;
var
  mSaved: TAtlasLanguage;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('3 Treffer', TAtlasVariablesStrings.Fmt(TAtlasVariablesTextId.VariablesHits, [3]));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('3 matches', TAtlasVariablesStrings.Fmt(TAtlasVariablesTextId.VariablesHits, [3]));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVariablesStringsTests);

end.
