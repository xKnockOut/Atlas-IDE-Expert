unit Atlas.Core.Debug.TimeChart.Tests;

// Abbildung von Zeit und Wert auf die Zeichenfläche (TAtlasTimeChartScale),
// gemeinsam für Speicherverlauf (#858) und Logpunkt-Verlauf (#2552).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasTimeChartScaleTests = class
  public
    [Test]
    procedure ScaleMapsTimeAndValue;
    /// <summary>Speicherverlauf: Werte ab 0, außerhalb begrenzt, leere Fläche ohne Division durch null.</summary>
    [Test]
    procedure ScaleMapsBothWays;
    [Test]
    procedure NiceRangeWithNegativeAndSmallValues;
  end;

implementation

uses
  Atlas.Core.Debug.TimeChart;

procedure TAtlasTimeChartScaleTests.ScaleMapsTimeAndValue;
var
  mScale: TAtlasTimeChartScale;
begin
  mScale := TAtlasTimeChartScale.Make(1000, 2000, -10, 10, 101, 21);
  Assert.AreEqual(0, mScale.XOf(1000));
  Assert.AreEqual(100, mScale.XOf(2000));
  Assert.AreEqual(Int64(1500), mScale.AtOf(50));
  Assert.AreEqual(20, mScale.YOf(-10));
  Assert.AreEqual(10, mScale.YOf(0));
  Assert.AreEqual(0, mScale.YOf(10));
  Assert.AreEqual(0, mScale.YOf(99));
  Assert.AreEqual(Double(0), mScale.TickValue(2, 4), 1E-9);
  mScale := TAtlasTimeChartScale.Make(5, 5, 3, 3, 0, 0);
  Assert.AreEqual(Int64(6), mScale.ToMs);
  Assert.AreEqual(Double(4), mScale.MaxValue, 1E-9);
end;

procedure TAtlasTimeChartScaleTests.ScaleMapsBothWays;
var
  mScale: TAtlasTimeChartScale;
begin
  mScale := TAtlasTimeChartScale.Make(10000, 20000, 0, 200, 101, 51);
  Assert.AreEqual(0, mScale.XOf(10000));
  Assert.AreEqual(50, mScale.XOf(15000));
  Assert.AreEqual(100, mScale.XOf(20000));
  Assert.AreEqual(Int64(15000), mScale.AtOf(50));
  Assert.AreEqual(Int64(20000), mScale.AtOf(500), 'außerhalb begrenzt');
  Assert.AreEqual(50, mScale.YOf(0));
  Assert.AreEqual(25, mScale.YOf(100));
  Assert.AreEqual(0, mScale.YOf(300), 'über der Obergrenze oben');
  mScale := TAtlasTimeChartScale.Make(0, 0, 0, 0, 0, 0);
  Assert.AreEqual(0, mScale.XOf(0), 'leere Fläche ohne Division durch null');
end;

procedure TAtlasTimeChartScaleTests.NiceRangeWithNegativeAndSmallValues;
var
  mLow, mHigh: Double;
begin
  Assert.AreEqual(Double(1), TAtlasTimeChartScale.NiceMax(0), 1E-12);
  Assert.AreEqual(Double(5), TAtlasTimeChartScale.NiceMax(3), 1E-12);
  Assert.AreEqual(Double(200), TAtlasTimeChartScale.NiceMax(120), 1E-9);
  Assert.AreEqual(Double(1000), TAtlasTimeChartScale.NiceMax(1000), 1E-9);
  Assert.AreEqual(Double(0.5), TAtlasTimeChartScale.NiceMax(0.3), 1E-12);
  TAtlasTimeChartScale.NiceRange(-3, 48, mLow, mHigh);
  Assert.AreEqual(Double(-5), mLow, 1E-9);
  Assert.AreEqual(Double(50), mHigh, 1E-9);
  TAtlasTimeChartScale.NiceRange(-7, -2, mLow, mHigh);
  Assert.AreEqual(Double(-10), mLow, 1E-9);
  Assert.AreEqual(Double(0), mHigh, 1E-9);
  TAtlasTimeChartScale.NiceRange(0, 0, mLow, mHigh);
  Assert.AreEqual(Double(0), mLow, 1E-9);
  Assert.AreEqual(Double(1), mHigh, 1E-9);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTimeChartScaleTests);

end.
