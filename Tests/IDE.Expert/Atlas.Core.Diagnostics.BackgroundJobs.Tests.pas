unit Atlas.Core.Diagnostics.BackgroundJobs.Tests;

// Hintergrundaufträge der Versionsverwaltung: Das Ergebnis kommt im
// Hauptthread, beendete Threads werden freigegeben, und ein Thread, der nach
// Stop noch läuft, geht an TAtlasOverdueThreads, statt ohne Besitzer liegen
// zu bleiben.

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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Diagnostics.UnloadSafety,
  Atlas.Core.Diagnostics.WorkerSlot,
  Atlas.Core.Diagnostics.BackgroundJobs;

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
  mWorker := TAtlasBackgroundJobs.Create(cModule);
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
  mRelease: TEvent;
  mDone: Boolean;
begin
  mDone := False;
  mRelease := FRelease;
  mWorker := TAtlasBackgroundJobs.Create(cModule);
  try
    Assert.IsTrue(mWorker.Run(
      procedure
      begin
        mRelease.WaitFor(5000);
      end,
      procedure
      begin
        mDone := True;
      end));
    Assert.IsFalse(mWorker.Stop(50));
    Assert.AreEqual(0, mWorker.Pending);
    Assert.AreEqual(1, TAtlasOverdueThreads.Pending(cModule));
  finally
    mWorker.Free;
  end;
  FRelease.SetEvent;
  Assert.IsTrue(TAtlasOverdueThreads.Settle(cModule, 2000));
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
    mWorker := TAtlasBackgroundJobs.Create(cModule);
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasBackgroundJobsTests);

end.
