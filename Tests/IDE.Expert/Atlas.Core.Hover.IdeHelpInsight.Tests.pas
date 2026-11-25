unit Atlas.Core.Hover.IdeHelpInsight.Tests;

// Wann Atlas das Help-Insight-Fenster der IDE ausblendet, nach welcher Datei
// es entscheidet und wann es meldet, dass das Fenster nie erschien.

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
    [Test]
    procedure DecidesByFileUnderMouse;
    [Test]
    procedure ReportsUnseenOnlyAfterHovering;
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

procedure TAtlasIdeHelpInsightTests.DecidesByFileUnderMouse;
begin
  Assert.AreEqual('C:\p\B.pas', TAtlasIdeHelpInsight.FileToDecide('C:\p\B.pas', 'C:\p\A.pas'),
    'zwei Editorfenster: das unter der Maus');
  Assert.AreEqual('C:\p\A.pas', TAtlasIdeHelpInsight.FileToDecide('', 'C:\p\A.pas'), 'ohne Maus: oberster');
  Assert.AreEqual('', TAtlasIdeHelpInsight.FileToDecide('', ''));
end;

procedure TAtlasIdeHelpInsightTests.ReportsUnseenOnlyAfterHovering;
begin
  Assert.IsTrue(TAtlasIdeHelpInsight.ReportUnseen(True, True, False));
  Assert.IsFalse(TAtlasIdeHelpInsight.ReportUnseen(True, True, True), 'gesehen');
  Assert.IsFalse(TAtlasIdeHelpInsight.ReportUnseen(True, False, False), 'nie gezeigt: nichts zu sagen');
  Assert.IsFalse(TAtlasIdeHelpInsight.ReportUnseen(False, True, False), 'ohne Haken meldet schon das Anlegen');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIdeHelpInsightTests);

end.
