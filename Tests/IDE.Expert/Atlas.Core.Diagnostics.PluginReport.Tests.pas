unit Atlas.Core.Diagnostics.PluginReport.Tests;

// Zeilen und Bericht der Plugin-Zeiten: Reihenfolge mit eindeutigem
// Gleichstand, Anteil je Funktion, Filter „Nur X zeigen“, neueste zuerst,
// Zahlen mit Punkt und der Abschnitt „## Plugin-Zeiten“ für „Bericht kopieren“.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Diagnostics.PluginTimings;

type
  [TestFixture]
  TAtlasPluginReportTests = class
  private
    FSnapshot: TAtlasPluginSnapshot;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FeaturesSortedByTotalThenName;
    [Test]
    procedure SlowNewestFirstAndFiltered;
    [Test]
    procedure RequestsSortedByWaiting;
    [Test]
    procedure HangsNewestFirst;
    [Test]
    procedure NumbersUseDot;
    [Test]
    procedure ReportHasAllSections;
    [Test]
    procedure EmptyReportSaysSo;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.PluginReport;

function Feature(AFeature: TAtlasFeature; ATotalMs: Double): TAtlasFeatureTiming;
begin
  Result := Default(TAtlasFeatureTiming);
  Result.Feature := AFeature;
  Result.Stat.Calls := 2;
  Result.Stat.TotalMs := ATotalMs;
  Result.Stat.MaxMs := ATotalMs;
end;

function SlowCall(AFeature: TAtlasFeature; AMs: Double): TAtlasSlowCall;
begin
  Result := Default(TAtlasSlowCall);
  Result.Feature := AFeature;
  Result.Ms := AMs;
end;

function Request(const AMethod: string; AWaitedMs, ATotalMs: Double): TAtlasRequestTiming;
begin
  Result := Default(TAtlasRequestTiming);
  Result.Method := AMethod;
  Result.WaitedMs := AWaitedMs;
  if AWaitedMs > 0 then
  begin
    // Zwei Wartezeiten: Der Bericht zeigt das Mittel je wartender Anfrage, nicht die Summe.
    Result.WaitedCalls := 2;
  end;
  Result.Stat.Calls := 1;
  Result.Stat.TotalMs := ATotalMs;
end;

{ TAtlasPluginReportTests }

procedure TAtlasPluginReportTests.Setup;
var
  mHang, mLater: TAtlasHangEntry;
  mSource: TAtlasSourceTiming;
begin
  FSnapshot := Default(TAtlasPluginSnapshot);
  FSnapshot.ThresholdMs := 16;
  FSnapshot.Features := TArray<TAtlasFeatureTiming>.Create(Feature(TAtlasFeature.Outline, 10),
    Feature(TAtlasFeature.Minimap, 30), Feature(TAtlasFeature.Hover, 10));
  FSnapshot.Slow := TArray<TAtlasSlowCall>.Create(SlowCall(TAtlasFeature.Minimap, 20),
    SlowCall(TAtlasFeature.Outline, 17), SlowCall(TAtlasFeature.Minimap, 25));
  FSnapshot.Requests := TArray<TAtlasRequestTiming>.Create(Request('b', 0, 50), Request('a', 0, 50),
    Request('c', 5, 1));
  mSource := Default(TAtlasSourceTiming);
  mSource.Name := 'Server';
  mSource.Stat.Calls := 1;
  mSource.Stat.TotalMs := 3;
  FSnapshot.Sources := TArray<TAtlasSourceTiming>.Create(mSource);
  mHang := Default(TAtlasHangEntry);
  mHang.DurationMs := 700;
  mHang.Activity := 'Speichern';
  mLater := mHang;
  mLater.DurationMs := 1200;
  mLater.WithAtlas := True;
  FSnapshot.Hangs := TArray<TAtlasHangEntry>.Create(mHang, mLater);
  FSnapshot.Busy := TArray<Double>.Create(10, 30);
end;

procedure TAtlasPluginReportTests.TearDown;
begin
  FSnapshot := Default(TAtlasPluginSnapshot);
end;

procedure TAtlasPluginReportTests.FeaturesSortedByTotalThenName;
var
  mRows: TArray<TAtlasFeatureRow>;
begin
  mRows := TAtlasPluginRows.Features(FSnapshot);
  Assert.AreEqual(3, Integer(Length(mRows)));
  Assert.AreEqual(Ord(TAtlasFeature.Minimap), Ord(mRows[0].Feature));
  Assert.AreEqual(0.6, mRows[0].Share, 0.0001);
  // Gleichstand 10 ms: nach Namen, „Gliederung“ vor „Tooltip“.
  Assert.AreEqual(TAtlasGuard.FeatureName(TAtlasFeature.Outline), mRows[1].Name);
  Assert.AreEqual(TAtlasGuard.FeatureName(TAtlasFeature.Hover), mRows[2].Name);
end;

procedure TAtlasPluginReportTests.SlowNewestFirstAndFiltered;
var
  mCalls: TArray<TAtlasSlowCall>;
begin
  mCalls := TAtlasPluginRows.Slow(FSnapshot, False, TAtlasFeature.Completion);
  Assert.AreEqual(3, Integer(Length(mCalls)));
  Assert.AreEqual(25.0, mCalls[0].Ms, 0.001, 'neueste zuerst');
  mCalls := TAtlasPluginRows.Slow(FSnapshot, True, TAtlasFeature.Minimap);
  Assert.AreEqual(2, Integer(Length(mCalls)));
  Assert.AreEqual(25.0, mCalls[0].Ms, 0.001);
  Assert.AreEqual(20.0, mCalls[1].Ms, 0.001);
end;

procedure TAtlasPluginReportTests.RequestsSortedByWaiting;
var
  mRequests: TArray<TAtlasRequestTiming>;
begin
  mRequests := TAtlasPluginRows.Requests(FSnapshot);
  Assert.AreEqual('c', mRequests[0].Method, 'der Hauptthread wartete');
  Assert.AreEqual('a', mRequests[1].Method, 'Gleichstand nach Namen');
  Assert.AreEqual('b', mRequests[2].Method);
end;

procedure TAtlasPluginReportTests.HangsNewestFirst;
var
  mHangs: TArray<TAtlasHangEntry>;
begin
  mHangs := TAtlasPluginRows.Hangs(FSnapshot);
  Assert.AreEqual(Int64(1200), mHangs[0].DurationMs);
  Assert.AreEqual(Int64(700), mHangs[1].DurationMs);
end;

procedure TAtlasPluginReportTests.NumbersUseDot;
begin
  Assert.AreEqual('3.2', TAtlasPluginRows.Ms(3.24));
  Assert.AreEqual('1,234', TAtlasPluginRows.Ms(1234.4));
  Assert.AreEqual('–', TAtlasPluginRows.Ms(-1));
  Assert.AreEqual('7.4', TAtlasPluginRows.Percent(7.44));
  Assert.AreEqual('38', TAtlasPluginRows.Percent(38.2));
end;

procedure TAtlasPluginReportTests.ReportHasAllSections;
var
  mText: string;
begin
  mText := TAtlasPluginReport.Build(FSnapshot);
  Assert.StartsWith('## Plugin-Zeiten', mText);
  Assert.Contains(mText, 'belegt: 20 %');
  Assert.Contains(mText, '### Hauptthread je Funktion');
  Assert.Contains(mText, TAtlasGuard.FeatureName(TAtlasFeature.Minimap) + ' | 2 | 30.0 | 15.0 | 30.0 | 0 | 60');
  Assert.Contains(mText, '### Langsame Aufrufe');
  Assert.Contains(mText, '### Server-Anfragen');
  Assert.Contains(mText, 'c | 1 | 1.0 | 0.0 | 2 | 2.5 | 0 | 0 | 0');
  Assert.Contains(mText, '### Quellen im Hintergrund');
  Assert.Contains(mText, 'Server | 1 | 3.0 | 0.0 | 0');
  Assert.Contains(mText, ': 1200 ms, Speichern, Atlas beteiligt: True');
end;

procedure TAtlasPluginReportTests.EmptyReportSaysSo;
var
  mText: string;
begin
  mText := TAtlasPluginReport.Build(Default(TAtlasPluginSnapshot));
  Assert.Contains(mText, 'Noch kein Aufruf gemessen.');
  Assert.Contains(mText, 'Keiner.');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginReportTests);

end.
