unit Atlas.Core.Diagnostics.WorkerSlot.Tests;

// Arbeiter-Threads über ihrer Zeitgrenze: Der Slot gibt
// beendete frei, übergibt überfällige an TAtlasOverdueThreads, und diese
// kennzeichnen ihr Package als unsicher, wenn es beim Abmelden seines Moduls
// noch Code von ihnen ausführt. Festgehalten wird vor FreeLibrary
// (SettleBeforeUnload), nie im Rückruf beim Entladen (Code-Review T-103).

interface

uses
  System.Classes,
  System.SyncObjs,
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWorkerSlotTests = class
  private const
    /// <summary>Erfundenes Package: Der Test entlädt nichts und hält nichts im Speicher fest.</summary>
    cModule = $5A5A0000;
  private
    FRelease: TEvent;
    FPinned: TArray<HMODULE>;
    function NewWorker: TThread;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FinishedWorkersAreFreed;
    [Test]
    procedure StopWaitsForQuickWorkers;
    /// <summary>Überschreitet ein Thread die Zeitgrenze, kehrt Stop zurück und der Thread wird nach seinem Ende
    /// freigegeben.</summary>
    [Test]
    procedure OverdueWorkerIsAdoptedAndFreedLater;
    [Test]
    procedure SettleMarksModuleUnsafeWhileWorkerRuns;
    [Test]
    procedure SettleKeepsModuleSafeWhenWorkerEnds;
    /// <summary>Abmelden mit laufendem überfälligem Thread: festhalten, bevor das Package entladen wird.</summary>
    [Test]
    procedure SettleBeforeUnloadPinsWhileWorkerRuns;
    [Test]
    procedure SettleBeforeUnloadWithoutOverdueWorkersPinsNothing;
    /// <summary>Der Rückruf beim Entladen läuft aus DLL_PROCESS_DETACH: Er darf weder warten noch festhalten.</summary>
    [Test]
    procedure UnloadNoticeNeitherWaitsNorPins;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Diagnostics.UnloadSafety,
  Atlas.Core.Diagnostics.WorkerSlot;

procedure TAtlasWorkerSlotTests.Setup;
begin
  FRelease := TEvent.Create(nil, True, False, '');
  FPinned := nil;
  TAtlasUnloadSafety.ResetForTests(
    procedure(AModule: HMODULE)
    begin
      FPinned := FPinned + [AModule];
    end);
end;

procedure TAtlasWorkerSlotTests.TearDown;
begin
  FRelease.SetEvent;
  TAtlasOverdueThreads.Settle(cModule, 2000);
  TAtlasUnloadSafety.ResetForTests(nil);
  FreeAndNil(FRelease);
  FPinned := nil;
end;

function TAtlasWorkerSlotTests.NewWorker: TThread;
var
  mRelease: TEvent;
begin
  mRelease := FRelease;
  Result := TThread.CreateAnonymousThread(
    procedure
    begin
      mRelease.WaitFor(5000);
    end);
end;

procedure TAtlasWorkerSlotTests.FinishedWorkersAreFreed;
var
  mSlot: TAtlasWorkerSlot;
begin
  mSlot := TAtlasWorkerSlot.Create(cModule);
  try
    FRelease.SetEvent;
    mSlot.Start(NewWorker);
    Assert.AreEqual(1, mSlot.Count);
    Assert.IsTrue(mSlot.Stop(2000));
    Assert.AreEqual(0, mSlot.Count);
    Assert.IsFalse(mSlot.Busy);
  finally
    mSlot.Free;
  end;
end;

procedure TAtlasWorkerSlotTests.StopWaitsForQuickWorkers;
var
  mSlot: TAtlasWorkerSlot;
begin
  mSlot := TAtlasWorkerSlot.Create(cModule);
  try
    mSlot.Start(NewWorker);
    Assert.IsTrue(mSlot.Busy);
    FRelease.SetEvent;
    Assert.IsTrue(mSlot.Stop(2000));
    Assert.AreEqual(0, TAtlasOverdueThreads.Pending(cModule));
  finally
    mSlot.Free;
  end;
end;

procedure TAtlasWorkerSlotTests.OverdueWorkerIsAdoptedAndFreedLater;
var
  mSlot: TAtlasWorkerSlot;
begin
  mSlot := TAtlasWorkerSlot.Create(cModule);
  try
    mSlot.Start(NewWorker);
    Assert.IsFalse(mSlot.Stop(50));
    Assert.AreEqual(0, mSlot.Count);
    Assert.AreEqual(1, TAtlasOverdueThreads.Pending(cModule));
    FRelease.SetEvent;
    Assert.IsTrue(TAtlasOverdueThreads.Settle(cModule, 2000));
    Assert.AreEqual(0, TAtlasOverdueThreads.Pending(cModule));
    Assert.IsTrue(TAtlasUnloadSafety.IsSafe(cModule));
  finally
    mSlot.Free;
  end;
end;

procedure TAtlasWorkerSlotTests.SettleMarksModuleUnsafeWhileWorkerRuns;
var
  mSlot: TAtlasWorkerSlot;
begin
  mSlot := TAtlasWorkerSlot.Create(cModule);
  try
    mSlot.Start(NewWorker);
    mSlot.Stop(20);
    Assert.IsFalse(TAtlasOverdueThreads.Settle(cModule, 20));
    Assert.IsFalse(TAtlasUnloadSafety.IsSafe(cModule));
    Assert.AreEqual(1, Integer(Length(FPinned)));
    Assert.AreEqual(HMODULE(cModule), FPinned[0]);
  finally
    mSlot.Free;
  end;
end;

procedure TAtlasWorkerSlotTests.SettleKeepsModuleSafeWhenWorkerEnds;
var
  mSlot: TAtlasWorkerSlot;
begin
  mSlot := TAtlasWorkerSlot.Create(cModule);
  try
    mSlot.Start(NewWorker);
    mSlot.Stop(20);
    FRelease.SetEvent;
    Assert.IsTrue(TAtlasOverdueThreads.Settle(cModule, 2000));
    Assert.IsTrue(TAtlasUnloadSafety.IsSafe(cModule));
    Assert.AreEqual(0, Integer(Length(FPinned)));
  finally
    mSlot.Free;
  end;
end;

procedure TAtlasWorkerSlotTests.SettleBeforeUnloadPinsWhileWorkerRuns;
var
  mSlot: TAtlasWorkerSlot;
begin
  mSlot := TAtlasWorkerSlot.Create(cModule);
  try
    mSlot.Start(NewWorker);
    mSlot.Stop(20);
    Assert.IsFalse(TAtlasOverdueThreads.SettleBeforeUnload(cModule, 20));
    Assert.IsFalse(TAtlasUnloadSafety.IsSafe(cModule));
    Assert.AreEqual(1, Integer(Length(FPinned)));
    Assert.AreEqual(HMODULE(cModule), FPinned[0]);
  finally
    mSlot.Free;
  end;
end;

procedure TAtlasWorkerSlotTests.SettleBeforeUnloadWithoutOverdueWorkersPinsNothing;
var
  mSlot: TAtlasWorkerSlot;
begin
  mSlot := TAtlasWorkerSlot.Create(cModule);
  try
    FRelease.SetEvent;
    mSlot.Start(NewWorker);
    Assert.IsTrue(mSlot.Stop(2000));
    Assert.IsTrue(TAtlasOverdueThreads.SettleBeforeUnload(cModule, 20));
    Assert.IsTrue(TAtlasUnloadSafety.IsSafe(cModule));
    Assert.AreEqual(0, Integer(Length(FPinned)));
  finally
    mSlot.Free;
  end;
end;

procedure TAtlasWorkerSlotTests.UnloadNoticeNeitherWaitsNorPins;
var
  mSlot: TAtlasWorkerSlot;
  mWatch: TStopwatch;
begin
  mSlot := TAtlasWorkerSlot.Create(cModule);
  try
    mSlot.Start(NewWorker);
    mSlot.Stop(20);
    mWatch := TStopwatch.StartNew;
    TAtlasOverdueThreads.NoteModuleUnload(cModule);
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 1000, 'Der Rückruf wartet');
    Assert.IsTrue(TAtlasUnloadSafety.IsSafe(cModule));
    Assert.AreEqual(0, Integer(Length(FPinned)));
    Assert.AreEqual(1, TAtlasOverdueThreads.Pending(cModule));
  finally
    mSlot.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWorkerSlotTests);

end.
