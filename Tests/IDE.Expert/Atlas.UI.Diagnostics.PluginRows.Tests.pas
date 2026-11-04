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
  end;

implementation

uses
  System.SysUtils,
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
  mRows := TAtlasPluginGridRows.Requests(TArray<TAtlasRequestTiming>.Create(mRequest), 16);
  Assert.AreEqual('textDocument/hover', mRows[0].Cells[0]);
  Assert.AreEqual(Ord(TAtlasGridMark.Warn), Ord(mRows[0].Mark(5)), 'Zeitüberschreitung');
  Assert.AreEqual(Ord(TAtlasGridMark.Bad), Ord(mRows[0].Mark(7)), 'Fehler');
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginGridRowsTests);

end.
