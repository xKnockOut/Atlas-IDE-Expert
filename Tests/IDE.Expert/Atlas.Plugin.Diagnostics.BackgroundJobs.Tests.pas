unit Atlas.Plugin.Diagnostics.BackgroundJobs.Tests;

// Hintergrundaufträge der Versionsverwaltung: Das Ergebnis kommt im
// Hauptthread, beendete Threads werden freigegeben, und ein Thread, der nach
// Stop noch läuft, geht an TAtlasOverdueThreads, statt ohne Besitzer liegen
// zu bleiben. Eine Ausnahme im Ergebnis zählt für das Feature und erreicht
// den Hauptthread nicht.

interface

uses
  System.SyncObjs,
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBackgroundJobsTests = class
  private const
    /// <summary>Erfundenes Package: Der Test entlädt nichts und hält nichts im Speicher fest.</summary>
    cModule = $5A5B0000;
  private
    FRelease: TEvent;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Das Ergebnis kommt im Hauptthread; danach ist kein Auftrag mehr offen.</summary>
    [Test]
    procedure DoneArrivesAndThreadIsFreed;
    /// <summary>Ein Auftrag über der Zeitgrenze von Stop geht an TAtlasOverdueThreads und wird nach seinem Ende
    /// freigegeben; sein Ergebnis kommt nicht mehr.</summary>
    [Test]
    procedure OverdueWorkIsAdoptedAndItsResultDropped;
    /// <summary>Ein schon eingereihtes, aber noch nicht zugestelltes Ergebnis verwirft Stop.</summary>
    [Test]
    procedure StopDropsQueuedResult;
    /// <summary>Wirft das Ergebnis, fängt die Sicherung die Ausnahme und rechnet sie dem Feature an; der Thread
    /// wird trotzdem freigegeben.</summary>
    [Test]
    procedure ThrowingDoneIsGuarded;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Plugin.Diagnostics.Deadline,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Diagnostics.UnloadSafety,
  Atlas.Plugin.Diagnostics.WorkerSlot,
  Atlas.Plugin.Diagnostics.BackgroundJobs;

/// <summary>Zugestellte Ergebnisse abarbeiten, bis ADone gesetzt ist oder AMs vergangen sind.</summary>
procedure DeliverUntil(const ADone: TFunc<Boolean>; AMs: Cardinal);
var
  mDeadline: TAtlasDeadline;
begin
  mDeadline := TAtlasDeadline.After(AMs);
  while not ADone() and not mDeadline.Reached do
  begin
    CheckSynchronize(10);
  end;
end;

{ TAtlasBackgroundJobsTests }

procedure TAtlasBackgroundJobsTests.Setup;
begin
  FRelease := TEvent.Create(nil, True, False, '');
end;

procedure TAtlasBackgroundJobsTests.TearDown;
begin
  TAtlasGuard.OnFailure := nil;
  TAtlasGuard.Fuse.ResetAll;
  // Ein überfälliger Auftrag endet hier; ohne Freigabe hielte ihn erst der Abbau der Liste.
  FRelease.SetEvent;
  TAtlasOverdueThreads.Settle(cModule, 2000);
  FreeAndNil(FRelease);
end;

procedure TAtlasBackgroundJobsTests.DoneArrivesAndThreadIsFreed;
var
  mWorker: TAtlasBackgroundJobs;
  mDone: Boolean;
begin
  mDone := False;
  mWorker := TAtlasBackgroundJobs.Create(cModule, TAtlasFeature.Tracker);
  try
    Assert.IsTrue(mWorker.Run(
      procedure
      begin
      end,
      procedure
      begin
        mDone := True;
      end));
    DeliverUntil(
      function: Boolean
      begin
        Result := mDone;
      end, 5000);
    Assert.IsTrue(mDone);
    Assert.AreEqual(0, mWorker.Pending);
    Assert.IsTrue(mWorker.Stop(1000));
    Assert.AreEqual(0, TAtlasOverdueThreads.Pending(cModule));
  finally
    mWorker.Free;
  end;
end;

procedure TAtlasBackgroundJobsTests.OverdueWorkIsAdoptedAndItsResultDropped;
var
  mWorker: TAtlasBackgroundJobs;
  mRelease, mStarted: TEvent;
  mDone: Boolean;
begin
  mDone := False;
  mRelease := FRelease;
  mStarted := TEvent.Create(nil, True, False, '');
  mWorker := TAtlasBackgroundJobs.Create(cModule, TAtlasFeature.Tracker);
  try
    Assert.IsTrue(mWorker.Run(
      procedure
      begin
        mStarted.SetEvent;
        mRelease.WaitFor(5000);
      end,
      procedure
      begin
        mDone := True;
      end));
    // Erst stoppen, wenn die Arbeit läuft: Delphis ThreadProc überspringt Execute, wenn Terminate vor dem
    // Anlaufen des Threads kam; dann wäre der Thread sofort fertig und nichts überfällig (FPC startet trotzdem).
    Assert.AreEqual<TWaitResult>(wrSignaled, mStarted.WaitFor(5000), 'Arbeit läuft');
    Assert.IsFalse(mWorker.Stop(50));
    Assert.AreEqual(0, mWorker.Pending);
    Assert.AreEqual(1, TAtlasOverdueThreads.Pending(cModule));
  finally
    mWorker.Free;
  end;
  FRelease.SetEvent;
  Assert.IsTrue(TAtlasOverdueThreads.Settle(cModule, 2000));
  // Erst nach dem Ende des Threads freigeben, er hat das Ereignis gesetzt.
  mStarted.Free;
  Assert.AreEqual(0, TAtlasOverdueThreads.Pending(cModule));
  CheckSynchronize(50);
  Assert.IsFalse(mDone);
  Assert.IsTrue(TAtlasUnloadSafety.IsSafe(cModule));
end;

procedure TAtlasBackgroundJobsTests.StopDropsQueuedResult;
var
  mWorker: TAtlasBackgroundJobs;
  mFinished: TEvent;
  mDone: Boolean;
begin
  mDone := False;
  mFinished := TEvent.Create(nil, True, False, '');
  try
    mWorker := TAtlasBackgroundJobs.Create(cModule, TAtlasFeature.Tracker);
    try
      Assert.IsTrue(mWorker.Run(
        procedure
        begin
          mFinished.SetEvent;
        end,
        procedure
        begin
          mDone := True;
        end));
      Assert.AreEqual(TWaitResult.wrSignaled, mFinished.WaitFor(5000));
      Assert.IsTrue(mWorker.Stop(2000));
    finally
      mWorker.Free;
    end;
    CheckSynchronize(50);
    Assert.IsFalse(mDone);
  finally
    mFinished.Free;
  end;
end;

procedure TAtlasBackgroundJobsTests.ThrowingDoneIsGuarded;
var
  mWorker: TAtlasBackgroundJobs;
  mReached: Boolean;
  mFailures: Integer;
  mFeature: TAtlasFeature;
  mOldFolder, mFolder: string;
begin
  mReached := False;
  mFailures := 0;
  mFeature := TAtlasFeature.Completion;
  TAtlasGuard.Fuse.ResetAll;
  TAtlasGuard.OnFailure :=
    procedure(AFeature: TAtlasFeature)
    begin
      Inc(mFailures);
      mFeature := AFeature;
    end;
  // Die Fehlerzeile der Sicherung nicht ins Protokoll des Benutzers.
  mOldFolder := TAtlasGuard.RotatingLog.Folder;
  mFolder := TPath.Combine(TPath.GetTempPath, 'AtlasBackgroundJobsTests' + TGUID.NewGuid.ToString);
  TAtlasGuard.RotatingLog.Folder := mFolder;
  mWorker := TAtlasBackgroundJobs.Create(cModule, TAtlasFeature.Tracker);
  try
    Assert.IsTrue(mWorker.Run(
      procedure
      begin
      end,
      procedure
      begin
        mReached := True;
        raise EInvalidOpException.Create('Anzeige kaputt');
      end));
    Assert.WillNotRaise(
      procedure
      begin
        DeliverUntil(
          function: Boolean
          begin
            Result := mReached;
          end, 5000);
      end);
    Assert.IsTrue(mReached);
    Assert.AreEqual(1, mFailures);
    Assert.AreEqual<TAtlasFeature>(TAtlasFeature.Tracker, mFeature);
    Assert.AreEqual(0, mWorker.Pending, 'Thread trotzdem freigegeben');
  finally
    mWorker.Free;
    TAtlasGuard.RotatingLog.Folder := mOldFolder;
    if TDirectory.Exists(mFolder) then
    begin
      TDirectory.Delete(mFolder, True);
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBackgroundJobsTests);

end.
