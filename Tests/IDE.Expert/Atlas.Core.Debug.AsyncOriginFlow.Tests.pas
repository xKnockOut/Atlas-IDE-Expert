unit Atlas.Core.Debug.AsyncOriginFlow.Tests;

// Tests für die Entscheidungen der Herkunft eingereihter Methoden außerhalb von Aufrufstellen und Ablage (#859,
// #1967): durchsuchte Dateien, Zuordnung, Meldung, Rahmen des Ergebnisfensters; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasAsyncOriginFlowTests = class
  public
    [Test]
    procedure SourcesArePasAndDpr;
    [Test]
    procedure SameThreadAndSiteKeepsAssignment;
    [Test]
    procedure ReportByWindow;
    [Test]
    procedure FrameOfItem;
  end;

implementation

uses
  Atlas.Core.Debug.AsyncOriginFlow;

{ TAtlasAsyncOriginFlowTests }

procedure TAtlasAsyncOriginFlowTests.SourcesArePasAndDpr;
begin
  Assert.IsTrue(TAtlasAsyncOriginFlow.IsSource('Kunden.PAS'));
  Assert.IsTrue(TAtlasAsyncOriginFlow.IsSource('Projekt.dpr'));
  Assert.IsFalse(TAtlasAsyncOriginFlow.IsSource('Main.dfm'));
  Assert.IsFalse(TAtlasAsyncOriginFlow.IsSource('Kunden.inc'));
end;

procedure TAtlasAsyncOriginFlowTests.SameThreadAndSiteKeepsAssignment;
begin
  Assert.IsFalse(TAtlasAsyncOriginFlow.Reassigns(True, 4120, 2, 4120, 2));
  Assert.IsTrue(TAtlasAsyncOriginFlow.Reassigns(True, 4120, 2, 4121, 2));
  Assert.IsTrue(TAtlasAsyncOriginFlow.Reassigns(True, 4120, 2, 4120, 3));
  Assert.IsTrue(TAtlasAsyncOriginFlow.Reassigns(False, 4120, 2, 4120, 2));
end;

procedure TAtlasAsyncOriginFlowTests.ReportByWindow;
begin
  Assert.AreEqual<TAtlasOriginReport>(TAtlasOriginReport.None, TAtlasAsyncOriginFlow.ReportOf(False, True));
  Assert.AreEqual<TAtlasOriginReport>(TAtlasOriginReport.Title, TAtlasAsyncOriginFlow.ReportOf(True, True));
  Assert.AreEqual<TAtlasOriginReport>(TAtlasOriginReport.Results, TAtlasAsyncOriginFlow.ReportOf(True, False));
end;

procedure TAtlasAsyncOriginFlowTests.FrameOfItem;
begin
  Assert.AreEqual(2, TAtlasAsyncOriginFlow.FrameOf(True, '2', 3));
  Assert.AreEqual(-1, TAtlasAsyncOriginFlow.FrameOf(True, '3', 3));
  Assert.AreEqual(-1, TAtlasAsyncOriginFlow.FrameOf(True, 'x', 3));
  Assert.AreEqual(-1, TAtlasAsyncOriginFlow.FrameOf(False, '0', 3));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAsyncOriginFlowTests);

end.
