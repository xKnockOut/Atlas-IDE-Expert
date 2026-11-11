unit Atlas.UI.Diagnostics.PluginRows.Tests;

// Zellen der Tabellen im Diagnose-Fenster: Warnfarbe ab der Schwelle,
// Fehlerfarbe ab dem Zehnfachen, Anteil als Balken, Strich ohne Aktion,
// Zeitüberschreitungen und Fehler der Server-Anfragen markiert.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPluginGridRowsTests = class
  public
    [Test]
    procedure MarkByThreshold;
    [Test]
    procedure FeatureRowCellsAndBar;
    [Test]
    procedure SlowRowWithoutActivityShowsDash;
    [Test]
    procedure RequestRowMarksTimeoutsAndFailures;
    [Test]
    procedure ColumnsMatchCells;
    /// <summary>Breit genug: feste Breiten, die erste Spalte nimmt den Rest.</summary>
    [Test]
    procedure LayoutKeepsFixedWidthsWhenWide;
    /// <summary>Zu schmal (Startgröße, Reiter „Server“): Die erste Spalte behält ihr Minimum, die übrigen werden
    /// anteilig schmaler und enden am rechten Rand.</summary>
    [Test]
    procedure LayoutShrinksFixedColumnsWhenNarrow;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.PluginTimings,
  Atlas.Core.Diagnostics.PluginReport,
  Atlas.UI.Diagnostics.Grid,
  Atlas.UI.Diagnostics.PluginRows;

function FeatureRow: TAtlasFeatureRow;
begin
  Result := Default(TAtlasFeatureRow);
  Result.Feature := TAtlasFeature.Minimap;
  Result.Name := TAtlasGuard.FeatureName(TAtlasFeature.Minimap);
  Result.Stat.Calls := 4;
  Result.Stat.TotalMs := 80;
  Result.Stat.MaxMs := 200;
  Result.Stat.SlowCalls := 2;
  Result.Share := 0.25;
end;

{ TAtlasPluginGridRowsTests }

procedure TAtlasPluginGridRowsTests.MarkByThreshold;
begin
  Assert.AreEqual(Ord(TAtlasGridMark.None), Ord(TAtlasPluginGridRows.Mark(15.9, 16)));
  Assert.AreEqual(Ord(TAtlasGridMark.Warn), Ord(TAtlasPluginGridRows.Mark(16, 16)));
  Assert.AreEqual(Ord(TAtlasGridMark.Bad), Ord(TAtlasPluginGridRows.Mark(160, 16)));
  Assert.AreEqual(Ord(TAtlasGridMark.None), Ord(TAtlasPluginGridRows.Mark(500, 0)), 'ohne Schwelle');
end;

procedure TAtlasPluginGridRowsTests.FeatureRowCellsAndBar;
var
  mRows: TArray<TAtlasGridRow>;
begin
  mRows := TAtlasPluginGridRows.Features(TArray<TAtlasFeatureRow>.Create(FeatureRow), 16);
  Assert.AreEqual(1, Integer(Length(mRows)));
  Assert.AreEqual(TAtlasGuard.FeatureName(TAtlasFeature.Minimap), mRows[0].Cells[0]);
  Assert.AreEqual('4', mRows[0].Cells[1]);
  Assert.AreEqual('80.0', mRows[0].Cells[2]);
  Assert.AreEqual('20.0', mRows[0].Cells[3]);
  Assert.AreEqual('200', mRows[0].Cells[4]);
  Assert.AreEqual('25', mRows[0].Cells[6]);
  Assert.AreEqual(Ord(TAtlasGridMark.Warn), Ord(mRows[0].Mark(3)), 'Mittel über der Schwelle');
  Assert.AreEqual(Ord(TAtlasGridMark.Bad), Ord(mRows[0].Mark(4)), 'Maximum über dem Zehnfachen');
  Assert.AreEqual(Ord(TAtlasGridMark.Warn), Ord(mRows[0].Mark(5)));
  Assert.AreEqual(0.25, mRows[0].Bar, 0.0001);
end;

procedure TAtlasPluginGridRowsTests.SlowRowWithoutActivityShowsDash;
var
  mCall: TAtlasSlowCall;
  mRows: TArray<TAtlasGridRow>;
begin
  mCall := Default(TAtlasSlowCall);
  mCall.Feature := TAtlasFeature.Outline;
  mCall.Ms := 20;
  mRows := TAtlasPluginGridRows.Slow(TArray<TAtlasSlowCall>.Create(mCall), 16);
  Assert.AreEqual('–', mRows[0].Cells[2]);
  Assert.AreEqual('20.0', mRows[0].Cells[3]);
  Assert.IsTrue(mRows[0].Bar < 0, 'ohne Balken');
end;

procedure TAtlasPluginGridRowsTests.RequestRowMarksTimeoutsAndFailures;
var
  mRequest: TAtlasRequestTiming;
  mRows: TArray<TAtlasGridRow>;
begin
  mRequest := Default(TAtlasRequestTiming);
  mRequest.Method := 'textDocument/hover';
  mRequest.Stat.Calls := 3;
  mRequest.TimedOut := 1;
  mRequest.Failed := 1;
  // Drei Wartezeiten des Hauptthreads, zusammen 30 ms: Mittel 10 ms liegt unter der Schwelle.
  mRequest.WaitedMs := 30;
  mRequest.WaitedCalls := 3;
  mRows := TAtlasPluginGridRows.Requests(TArray<TAtlasRequestTiming>.Create(mRequest), 16);
  Assert.AreEqual('textDocument/hover', mRows[0].Cells[0]);
  Assert.AreEqual('3', mRows[0].Cells[4]);
  Assert.AreEqual(TAtlasPluginRows.Ms(10), mRows[0].Cells[5]);
  Assert.AreEqual(Ord(TAtlasGridMark.None), Ord(mRows[0].Mark(5)), 'Mittel unter der Schwelle');
  Assert.AreEqual(Ord(TAtlasGridMark.Warn), Ord(mRows[0].Mark(6)), 'Zeitüberschreitung');
  Assert.AreEqual(Ord(TAtlasGridMark.Bad), Ord(mRows[0].Mark(8)), 'Fehler');
  Assert.AreEqual(Integer(Length(TAtlasPluginGridRows.RequestColumns)), Integer(Length(mRows[0].Cells)));
end;

procedure TAtlasPluginGridRowsTests.ColumnsMatchCells;
var
  mHang: TAtlasHangEntry;
  mSource: TAtlasSourceTiming;
begin
  Assert.AreEqual(Integer(Length(TAtlasPluginGridRows.FeatureColumns)),
    Integer(Length(TAtlasPluginGridRows.Features(TArray<TAtlasFeatureRow>.Create(FeatureRow), 16)[0].Cells)));
  mSource := Default(TAtlasSourceTiming);
  mSource.Name := 'Server';
  Assert.AreEqual(Integer(Length(TAtlasPluginGridRows.SourceColumns)),
    Integer(Length(TAtlasPluginGridRows.Sources(TArray<TAtlasSourceTiming>.Create(mSource))[0].Cells)));
  mHang := Default(TAtlasHangEntry);
  Assert.AreEqual(Integer(Length(TAtlasPluginGridRows.HangColumns)),
    Integer(Length(TAtlasPluginGridRows.Hangs(TArray<TAtlasHangEntry>.Create(mHang))[0].Cells)));
end;

procedure TAtlasPluginGridRowsTests.LayoutKeepsFixedWidthsWhenWide;
var
  mSpans: TArray<TPoint>;
begin
  mSpans := TAtlasGridLayout.Spans(TArray<Integer>.Create(0, 100, 50), 500, 160, 40);
  Assert.AreEqual(0, mSpans[0].X);
  Assert.AreEqual(350, mSpans[0].Y);
  Assert.AreEqual(350, mSpans[1].X);
  Assert.AreEqual(450, mSpans[1].Y);
  Assert.AreEqual(500, mSpans[2].Y);
end;

procedure TAtlasPluginGridRowsTests.LayoutShrinksFixedColumnsWhenNarrow;
var
  mWidths: TArray<Integer>;
  mSpans: TArray<TPoint>;
  mIndex: Integer;
begin
  // Spalten des Reiters „Server“: 64 + 72 + 72 + 150 + 120 + 90 + 60 = 628 feste Pixel.
  mWidths := TArray<Integer>.Create(0, 64, 72, 72, 150, 120, 90, 60);
  mSpans := TAtlasGridLayout.Spans(mWidths, 600, 160, 40);
  Assert.AreEqual(160, mSpans[0].Y, 'Anfrage behält ihr Minimum');
  for mIndex := 1 to High(mSpans) do
  begin
    Assert.AreEqual(mSpans[mIndex - 1].Y, mSpans[mIndex].X, 'lückenlos');
    Assert.IsTrue(mSpans[mIndex].Y - mSpans[mIndex].X >= 40, 'Mindestbreite');
    Assert.IsTrue(mSpans[mIndex].Y - mSpans[mIndex].X <= mWidths[mIndex], 'höchstens die feste Breite');
  end;
  Assert.IsTrue(mSpans[High(mSpans)].Y <= 600, 'endet am Rand: ' + IntToStr(mSpans[High(mSpans)].Y));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginGridRowsTests);

end.
