unit Atlas.UI.Documentation.Labels.Tests;

// Tests der Überschriften der XMLDoc-Abschnitte in der Sprache der Oberfläche.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDocLabelTextsTests = class
  public
    [Test]
    procedure German;
  end;

implementation

uses
  Atlas.Core.Documentation.Layout,
  Atlas.UI.Strings,
  Atlas.UI.Documentation.Labels;

procedure TAtlasDocLabelTextsTests.German;
var
  mSaved: TAtlasLanguage;
  mLabels, mExpected: TAtlasDocLabels;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mLabels := TAtlasDocLabelTexts.Current;
    mExpected := TAtlasDocLabels.German;
    Assert.AreEqual(mExpected.Params, mLabels.Params);
    Assert.AreEqual(mExpected.TypeParams, mLabels.TypeParams);
    Assert.AreEqual(mExpected.Returns, mLabels.Returns);
    Assert.AreEqual(mExpected.Value, mLabels.Value);
    Assert.AreEqual(mExpected.Exceptions, mLabels.Exceptions);
    Assert.AreEqual(mExpected.Remarks, mLabels.Remarks);
    Assert.AreEqual(mExpected.Example, mLabels.Example);
    Assert.AreEqual(mExpected.SeeAlso, mLabels.SeeAlso);
    Assert.AreEqual(mExpected.Undocumented, mLabels.Undocumented);
    Assert.AreEqual(mExpected.More, mLabels.More);
    Assert.AreEqual(mExpected.Less, mLabels.Less);
    Assert.AreEqual(mExpected.CountParam, mLabels.CountParam);
    Assert.AreEqual(mExpected.CountParams, mLabels.CountParams);
    Assert.AreEqual(mExpected.CountTypeParam, mLabels.CountTypeParam);
    Assert.AreEqual(mExpected.CountTypeParams, mLabels.CountTypeParams);
    Assert.AreEqual(mExpected.CountException, mLabels.CountException);
    Assert.AreEqual(mExpected.CountExceptions, mLabels.CountExceptions);
    Assert.AreEqual(mExpected.ItemReturns, mLabels.ItemReturns);
    Assert.AreEqual(mExpected.ItemValue, mLabels.ItemValue);
    Assert.AreEqual(mExpected.ItemRemarks, mLabels.ItemRemarks);
    Assert.AreEqual(mExpected.ItemExample, mLabels.ItemExample);
    Assert.AreEqual(mExpected.ItemSeeAlso, mLabels.ItemSeeAlso);
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDocLabelTextsTests);

end.
