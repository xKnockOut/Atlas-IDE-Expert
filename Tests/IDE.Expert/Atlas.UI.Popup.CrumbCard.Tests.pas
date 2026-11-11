unit Atlas.UI.Popup.CrumbCard.Tests;

// Kennzahlen-Karte der Brotkrumen (#1787): Beschriftung und Wert je Zeile,
// über der Grenze mit der Grenze.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCrumbCardTipTests = class
  public
    [Test]
    procedure ValueShowsLimitWhenOver;
    [Test]
    procedure CaptionsInBothLanguages;
  end;

implementation

uses
  Atlas.Core.Editor.CrumbCard,
  Atlas.UI.Strings,
  Atlas.UI.Popup.CrumbCard;

function Row(AValue, ALimit: Integer): TAtlasCardRow;
begin
  Result := Default(TAtlasCardRow);
  Result.Metric := TAtlasCardMetric.Lines;
  Result.Value := AValue;
  Result.Limit := ALimit;
end;

procedure TAtlasCrumbCardTipTests.ValueShowsLimitWhenOver;
var
  mOld: TAtlasLanguage;
begin
  mOld := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('86 (Grenze 60)', TAtlasCrumbCardTip.RowValue(Row(86, 60)));
    Assert.AreEqual('12', TAtlasCrumbCardTip.RowValue(Row(12, 60)));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('86 (limit 60)', TAtlasCrumbCardTip.RowValue(Row(86, 60)));
  finally
    TAtlasStrings.Language := mOld;
  end;
end;

procedure TAtlasCrumbCardTipTests.CaptionsInBothLanguages;
var
  mOld: TAtlasLanguage;
begin
  mOld := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Assert.AreEqual('Zeilen', TAtlasCrumbCardTip.RowCaption(Row(1, 1)));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('Lines', TAtlasCrumbCardTip.RowCaption(Row(1, 1)));
  finally
    TAtlasStrings.Language := mOld;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCrumbCardTipTests);

end.
