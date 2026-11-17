unit Atlas.Core.Hover.IdeHelpInsight.Tests;

// Wann Atlas das Help-Insight-Fenster der IDE ausblendet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasIdeHelpInsightTests = class
  public
    [Test]
    procedure RecognisesHelpInsightWindowOnly;
    [Test]
    procedure HidesOnlyWithOwnTooltipInHandledFile;
  end;

implementation

uses
  Atlas.Core.Hover.IdeHelpInsight;

{ TAtlasIdeHelpInsightTests }

procedure TAtlasIdeHelpInsightTests.RecognisesHelpInsightWindowOnly;
begin
  Assert.IsTrue(TAtlasIdeHelpInsight.IsHelpInsightWindow('THelpInsightWindowImpl'));
  Assert.IsTrue(TAtlasIdeHelpInsight.IsHelpInsightWindow('thelpinsightwindowimpl'));
  Assert.IsFalse(TAtlasIdeHelpInsight.IsHelpInsightWindow('TAtlasHoverTip'));
  Assert.IsFalse(TAtlasIdeHelpInsight.IsHelpInsightWindow('TNoFocusWebBrowser'));
  Assert.IsFalse(TAtlasIdeHelpInsight.IsHelpInsightWindow(''));
end;

procedure TAtlasIdeHelpInsightTests.HidesOnlyWithOwnTooltipInHandledFile;
begin
  Assert.IsTrue(TAtlasIdeHelpInsight.ShouldHide(TAtlasIdeHelpInsight.cWindowClass, True, True));
  Assert.IsFalse(TAtlasIdeHelpInsight.ShouldHide(TAtlasIdeHelpInsight.cWindowClass, False, True),
    'Ohne eigenen Tooltip gehört der Hinweis der IDE');
  Assert.IsFalse(TAtlasIdeHelpInsight.ShouldHide(TAtlasIdeHelpInsight.cWindowClass, True, False),
    'Datei, die Atlas nicht bedient');
  Assert.IsFalse(TAtlasIdeHelpInsight.ShouldHide('TAtlasHoverTip', True, True));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIdeHelpInsightTests);

end.
