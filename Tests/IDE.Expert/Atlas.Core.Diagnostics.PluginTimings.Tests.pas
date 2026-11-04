unit Atlas.Core.Diagnostics.PluginTimings.Tests;

// Rekorder der Plugin-Zeiten (Diagnose-Fenster, Reiter Hauptthread, Server,
// Hintergrund, Hänger): eigene Zeit ohne verschachtelte Aufrufe, Belegung je
// Sekunde nur über den äußersten Aufruf, Ring der langsamen Aufrufe, Anhalten
// und Zurücksetzen, Schwelle, Anfragen, Quellen, Hänger, der Messpunkt in
// TAtlasGuard.Run und das Abschalten einer Funktion bis zum Neustart. Die Uhr
// und „Hauptthread?“ sind im Test gesetzt.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Diagnostics.PluginTimings;

type
  [TestFixture]
  TAtlasPluginTimingsTests = class
  private
    FClockUs: Int64;
    FMain: Boolean;
    FRecorder: TAtlasPluginRecorder;
    FFolder: string;
    FOldFolder: string;
    procedure Call(AToken: Integer);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ein verschachtelter Aufruf zählt bei sich, nicht beim äußeren.</summary>
    [Test]
    procedure OwnTimeExcludesNestedCalls;
    /// <summary>Belegung nur über den äußersten Aufruf, nur abgeschlossene Sekunden.</summary>
    [Test]
    procedure BusyCountsOnlyOutermostCall;
    [Test]
    procedure BusySplitsAtSecondBoundary;
    [Test]
    procedure OtherThreadsAreNotMeasured;
    [Test]
    procedure PauseStopsCountingResetClears;
    [Test]
    procedure SlowRingKeepsNewest;
    [Test]
    procedure ThresholdIsClamped;
    /// <summary>Die längste Aktion im Aufruf steht in der Zeile des langsamen Aufrufs.</summary>
    [Test]
    procedure SlowCallNamesLongestActivity;
    [Test]
    procedure RequestsCountOutcomesAndWaiting;
    [Test]
    procedure SourcesCountTimeAndSlowSkips;
    [Test]
    procedure HangsKeepNewest;
    /// <summary>TAtlasGuard.Run misst über TAtlasGuard.Timing, auch wenn der Aufruf scheitert.</summary>
    [Test]
    procedure GuardRunReportsToTiming;
    [Test]
    procedure EnabledSwitchesGuardHook;
    /// <summary>„Bis zum Neustart ausschalten“ im Kontextmenü.</summary>
    [Test]
    procedure DisableTripsFeature;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard;

{ TAtlasPluginTimingsTests }

procedure TAtlasPluginTimingsTests.Setup;
var
  mSelf: TAtlasPluginTimingsTests;
begin
  mSelf := Self;
  FClockUs := 0;
  FMain := True;
  FRecorder := TAtlasPluginRecorder.Create(
    function: Int64
    begin
      Result := mSelf.FClockUs;
    end,
    function: TDateTime
    begin
      Result := EncodeDate(2026, 11, 4) + mSelf.FClockUs / (86400.0 * 1000000);
    end,
    function: Boolean
    begin
      Result := mSelf.FMain;
    end);
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasPluginTimingsTests' + TGUID.NewGuid.ToString);
  FOldFolder := TAtlasGuard.RotatingLog.Folder;
  TAtlasGuard.RotatingLog.Folder := FFolder;
  TAtlasGuard.Fuse.ResetAll;
end;

procedure TAtlasPluginTimingsTests.TearDown;
begin
  TAtlasGuard.Timing := nil;
  TAtlasPluginTimings.Enabled := False;
  TAtlasGuard.Fuse.ResetAll;
  TAtlasGuard.RotatingLog.Folder := FOldFolder;
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FreeAndNil(FRecorder);
  FFolder := '';
  FOldFolder := '';
end;

procedure TAtlasPluginTimingsTests.Call(AToken: Integer);
begin
  FRecorder.Leave(TAtlasFeature.Completion, AToken);
end;

procedure TAtlasPluginTimingsTests.OwnTimeExcludesNestedCalls;
var
  mOuter, mInner: Integer;
  mSnapshot: TAtlasPluginSnapshot;
  mTiming: TAtlasFeatureTiming;
begin
  mOuter := FRecorder.Enter;
  FClockUs := 1000;
  mInner := FRecorder.Enter;
  FClockUs := 21000;
  FRecorder.Leave(TAtlasFeature.Hover, mInner);
  FClockUs := 25000;
  Call(mOuter);
  mSnapshot := FRecorder.Snapshot;
  Assert.AreEqual(2, Integer(Length(mSnapshot.Features)));
  for mTiming in mSnapshot.Features do
  begin
    if mTiming.Feature = TAtlasFeature.Hover then
    begin
      Assert.AreEqual(20.0, mTiming.Stat.TotalMs, 0.001, 'Tooltip: eigene Zeit');
      Assert.AreEqual(1, mTiming.Stat.SlowCalls);
    end
    else
    begin
      Assert.AreEqual(Ord(TAtlasFeature.Completion), Ord(mTiming.Feature));
      Assert.AreEqual(5.0, mTiming.Stat.TotalMs, 0.001, 'Vervollständigung ohne den Tooltip');
      Assert.AreEqual(0, mTiming.Stat.SlowCalls);
    end;
  end;
  Assert.AreEqual(1, Integer(Length(mSnapshot.Slow)));
  Assert.AreEqual(Ord(TAtlasFeature.Hover), Ord(mSnapshot.Slow[0].Feature));
end;

procedure TAtlasPluginTimingsTests.BusyCountsOnlyOutermostCall;
var
  mOuter, mInner: Integer;
  mSnapshot: TAtlasPluginSnapshot;
begin
  mOuter := FRecorder.Enter;
  FClockUs := 100000;
  mInner := FRecorder.Enter;
  FClockUs := 200000;
  FRecorder.Leave(TAtlasFeature.Hover, mInner);
  FClockUs := 500000;
  Call(mOuter);
  FClockUs := 1000000;
  mSnapshot := FRecorder.Snapshot;
  Assert.AreEqual(1, Integer(Length(mSnapshot.Busy)), 'eine abgeschlossene Sekunde');
  Assert.AreEqual(50.0, mSnapshot.Busy[0], 0.001);
  Assert.AreEqual(50.0, mSnapshot.BusyPercent, 0.001);
end;

procedure TAtlasPluginTimingsTests.BusySplitsAtSecondBoundary;
var
  mToken: Integer;
  mSnapshot: TAtlasPluginSnapshot;
begin
  FClockUs := 900000;
  mToken := FRecorder.Enter;
  FClockUs := 1200000;
  Call(mToken);
  FClockUs := 2500000;
  mSnapshot := FRecorder.Snapshot;
  Assert.AreEqual(2, Integer(Length(mSnapshot.Busy)));
  Assert.AreEqual(10.0, mSnapshot.Busy[0], 0.001);
  Assert.AreEqual(20.0, mSnapshot.Busy[1], 0.001);
end;

procedure TAtlasPluginTimingsTests.OtherThreadsAreNotMeasured;
var
  mToken: Integer;
begin
  FMain := False;
  mToken := FRecorder.Enter;
  Assert.AreEqual(-1, mToken);
  FClockUs := 50000;
  Call(mToken);
  Assert.AreEqual(0, Integer(Length(FRecorder.Snapshot.Features)));
end;

procedure TAtlasPluginTimingsTests.PauseStopsCountingResetClears;
var
  mToken: Integer;
  mSince: TDateTime;
begin
  mToken := FRecorder.Enter;
  FClockUs := 30000;
  Call(mToken);
  FRecorder.Paused := True;
  Assert.AreEqual(-1, FRecorder.Enter, 'angehalten');
  FRecorder.SourceDone('Server', 5);
  FRecorder.RequestDone('textDocument/completion', 5, TAtlasRequestOutcome.Done, True);
  Assert.AreEqual(0, Integer(Length(FRecorder.Snapshot.Sources)));
  Assert.AreEqual(0, Integer(Length(FRecorder.Snapshot.Requests)));
  Assert.AreEqual(1, Integer(Length(FRecorder.Snapshot.Features)), 'Werte bleiben stehen');
  Assert.IsTrue(FRecorder.Snapshot.Paused);
  FRecorder.Paused := False;
  mSince := FRecorder.Snapshot.Since;
  FClockUs := 60000000;
  FRecorder.Reset;
  Assert.AreEqual(0, Integer(Length(FRecorder.Snapshot.Features)));
  Assert.AreEqual(0, Integer(Length(FRecorder.Snapshot.Slow)));
  Assert.IsTrue(FRecorder.Snapshot.Since > mSince, 'Messung seit beginnt neu');
end;

procedure TAtlasPluginTimingsTests.SlowRingKeepsNewest;
var
  mIndex, mToken: Integer;
  mSlow: TArray<TAtlasSlowCall>;
begin
  for mIndex := 1 to TAtlasPluginRecorder.cSlowCapacity + 5 do
  begin
    mToken := FRecorder.Enter;
    FClockUs := FClockUs + 16000 + mIndex;
    Call(mToken);
  end;
  mSlow := FRecorder.Snapshot.Slow;
  Assert.AreEqual(TAtlasPluginRecorder.cSlowCapacity, Integer(Length(mSlow)));
  Assert.AreEqual(16.006, mSlow[0].Ms, 0.0001, 'die ältesten fünf sind fort');
  Assert.AreEqual(16.205, mSlow[High(mSlow)].Ms, 0.0001);
end;

procedure TAtlasPluginTimingsTests.ThresholdIsClamped;
var
  mToken: Integer;
begin
  FRecorder.ThresholdMs := 0;
  Assert.AreEqual(TAtlasPluginRecorder.cMinThresholdMs, FRecorder.ThresholdMs);
  FRecorder.ThresholdMs := 5000;
  Assert.AreEqual(TAtlasPluginRecorder.cMaxThresholdMs, FRecorder.ThresholdMs);
  FRecorder.ThresholdMs := 50;
  mToken := FRecorder.Enter;
  FClockUs := 40000;
  Call(mToken);
  Assert.AreEqual(0, Integer(Length(FRecorder.Snapshot.Slow)), '40 ms unter 50 ms');
  Assert.AreEqual(50, FRecorder.Snapshot.ThresholdMs);
end;

procedure TAtlasPluginTimingsTests.SlowCallNamesLongestActivity;
var
  mToken: Integer;
  mSlow: TArray<TAtlasSlowCall>;
begin
  mToken := FRecorder.Enter;
  FClockUs := 2000;
  FRecorder.ActivityDone('Kurz', 1000);
  FClockUs := 32000;
  FRecorder.ActivityDone('Speichern prüfen', 2000);
  FClockUs := 40000;
  Call(mToken);
  mSlow := FRecorder.Snapshot.Slow;
  Assert.AreEqual(1, Integer(Length(mSlow)));
  Assert.AreEqual('Speichern prüfen', mSlow[0].Activity);
  Assert.AreEqual(40.0, mSlow[0].Ms, 0.001);
end;

procedure TAtlasPluginTimingsTests.RequestsCountOutcomesAndWaiting;
var
  mRequests: TArray<TAtlasRequestTiming>;
begin
  FRecorder.RequestDone('textDocument/hover', 30, TAtlasRequestOutcome.Done, True);
  FRecorder.RequestDone('textDocument/hover', 10, TAtlasRequestOutcome.TimedOut, False);
  FRecorder.RequestDone('textDocument/hover', 2, TAtlasRequestOutcome.Cancelled, True);
  FRecorder.RequestDone('textDocument/hover', 1, TAtlasRequestOutcome.Failed, False);
  mRequests := FRecorder.Snapshot.Requests;
  Assert.AreEqual(1, Integer(Length(mRequests)));
  Assert.AreEqual(4, mRequests[0].Stat.Calls);
  Assert.AreEqual(32.0, mRequests[0].WaitedMs, 0.001, 'nur die Anfragen aus dem Hauptthread');
  Assert.AreEqual(30.0, mRequests[0].Stat.MaxMs, 0.001);
  Assert.AreEqual(1, mRequests[0].TimedOut);
  Assert.AreEqual(1, mRequests[0].Cancelled);
  Assert.AreEqual(1, mRequests[0].Failed);
end;

procedure TAtlasPluginTimingsTests.SourcesCountTimeAndSlowSkips;
var
  mSources: TArray<TAtlasSourceTiming>;
begin
  FRecorder.SourceDone('Server', 20);
  FRecorder.SourceDone('Server', 4);
  FRecorder.ProviderSlow('Server');
  mSources := FRecorder.Snapshot.Sources;
  Assert.AreEqual(1, Integer(Length(mSources)));
  Assert.AreEqual(2, mSources[0].Stat.Calls);
  Assert.AreEqual(12.0, mSources[0].Stat.MeanMs, 0.001);
  Assert.AreEqual(1, mSources[0].Stat.SlowCalls, 'ab 16 ms');
  Assert.AreEqual(1, mSources[0].Slow, 'über dem Zeitlimit');
end;

procedure TAtlasPluginTimingsTests.HangsKeepNewest;
var
  mIndex: Integer;
  mHang: TAtlasHangEntry;
  mHangs: TArray<TAtlasHangEntry>;
begin
  for mIndex := 1 to TAtlasPluginRecorder.cHangCapacity + 1 do
  begin
    mHang := Default(TAtlasHangEntry);
    mHang.DurationMs := mIndex;
    mHang.Activity := 'Aktion';
    FRecorder.HangDone(mHang);
  end;
  mHangs := FRecorder.Snapshot.Hangs;
  Assert.AreEqual(TAtlasPluginRecorder.cHangCapacity, Integer(Length(mHangs)));
  Assert.AreEqual(Int64(2), mHangs[0].DurationMs);
end;

procedure TAtlasPluginTimingsTests.GuardRunReportsToTiming;
var
  mSelf: TAtlasPluginTimingsTests;
  mFeatures: TArray<TAtlasFeatureTiming>;
begin
  mSelf := Self;
  TAtlasGuard.Timing := FRecorder;
  TAtlasGuard.Run(TAtlasFeature.Outline,
    procedure
    begin
      mSelf.FClockUs := mSelf.FClockUs + 20000;
    end);
  TAtlasGuard.Run(TAtlasFeature.Outline,
    procedure
    begin
      mSelf.FClockUs := mSelf.FClockUs + 1000;
      raise EAbort.Create('Test');
    end);
  TAtlasGuard.Timing := nil;
  mFeatures := FRecorder.Snapshot.Features;
  Assert.AreEqual(1, Integer(Length(mFeatures)));
  Assert.AreEqual(Ord(TAtlasFeature.Outline), Ord(mFeatures[0].Feature));
  Assert.AreEqual(2, mFeatures[0].Stat.Calls, 'auch der gescheiterte Aufruf');
  Assert.AreEqual(21.0, mFeatures[0].Stat.TotalMs, 0.001);
end;

procedure TAtlasPluginTimingsTests.EnabledSwitchesGuardHook;
begin
  TAtlasPluginTimings.Enabled := False;
  Assert.IsNull(TAtlasGuard.Timing);
  Assert.AreEqual(Int64(0), TAtlasPluginTimings.StampIfEnabled, 'aus: kein Zeitstempel');
  TAtlasPluginTimings.Enabled := True;
  Assert.AreSame(TAtlasPluginTimings.Shared, TAtlasGuard.Timing);
  TAtlasPluginTimings.Enabled := False;
  Assert.IsNull(TAtlasGuard.Timing);
end;

procedure TAtlasPluginTimingsTests.DisableTripsFeature;
begin
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Minimap));
  TAtlasGuard.Disable(TAtlasFeature.Minimap);
  Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.Minimap));
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Outline), 'nur diese Funktion');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginTimingsTests);

end.
