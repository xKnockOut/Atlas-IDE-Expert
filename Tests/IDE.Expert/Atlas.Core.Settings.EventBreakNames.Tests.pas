unit Atlas.Core.Settings.EventBreakNames.Tests;

// Tests für die Liste der häufigen Ereignisse (#856,
// debug.breakOnNextEvent.excluded): Vorgabe, Zerlegen, Normalisieren.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasEventBreakSettingsTests = class
  public
    [Test]
    procedure ExcludedListNormalized;
    [Test]
    procedure ExcludedListKeepsOrderWithoutDuplicates;
  end;

implementation

uses
  Atlas.Core.Settings.EventBreakNames;

{ TAtlasEventBreakSettingsTests }

procedure TAtlasEventBreakSettingsTests.ExcludedListNormalized;
begin
  Assert.AreEqual('OnPaint, OnMouseMove, OnUpdate',
    TAtlasEventBreakSettings.NormalizeExcluded(' OnPaint;OnMouseMove,,OnUpdate ,onpaint'));
  Assert.AreEqual('', TAtlasEventBreakSettings.NormalizeExcluded('  '));
  Assert.AreEqual(TAtlasEventBreakSettings.DefaultExcluded,
    TAtlasEventBreakSettings.NormalizeExcluded(TAtlasEventBreakSettings.DefaultExcluded));
end;

procedure TAtlasEventBreakSettingsTests.ExcludedListKeepsOrderWithoutDuplicates;
var
  mList: TArray<string>;
begin
  mList := TAtlasEventBreakSettings.ExcludedList('OnResize'#9'onresize'#13#10'OnPaint');
  Assert.AreEqual(2, Integer(Length(mList)));
  Assert.AreEqual('OnResize', mList[0]);
  Assert.AreEqual('OnPaint', mList[1]);
  Assert.AreEqual(3, Integer(Length(TAtlasEventBreakSettings.ExcludedList(TAtlasEventBreakSettings.DefaultExcluded))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEventBreakSettingsTests);

end.
