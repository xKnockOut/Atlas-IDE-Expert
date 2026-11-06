unit Atlas.Core.Diagnostics.MainThread.Tests;

// Einreihen in den Hauptthread über TAtlasMainThread (Code-Review A-02):
// Einträge überleben das Freigeben des einreihenden Arbeiters, nicht aber
// Stop (Entladen); Ausnahmen zählen für das angegebene Feature. Einträge eines
// abgemeldeten oder entladenen Moduls verfallen, die anderer Module nicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasMainThreadTests = class
  private
    FFolder: string;
    FOldFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure QueueRunsAtOnceInMainThread;
    [Test]
    procedure ForceQueueWaitsForCheckSynchronize;
    [Test]
    procedure EntryOfFreedWorkerStillRuns;
    [Test]
    // Ausnahme mit Grund (Bericht N2): Stop gibt den Besitzer-Thread frei, Start legt einen neuen an, der wie
    // im Plugin bis zum Entladen weiterläuft. Seine Startdaten (BeginThread) gibt erst der neue Thread frei,
    // sobald er läuft, unter Last nach der Messung. Darauf zu warten hieße, Start im Plugin aufzuhalten.
    [IgnoreMemoryLeaks]
    procedure StopDropsWaitingAndLaterEntries;
    [Test]
    procedure ExceptionCountsForFeature;
    [Test]
    procedure QueueFromWorkerRunsInMainThread;
    [Test]
    procedure ModuleOfIsModuleOfTheCode;
    [Test]
    procedure CloseModuleDropsWaitingAndLaterEntries;
    [Test]
    procedure CloseOtherModuleKeepsEntries;
    [Test]
    procedure ModuleUnloadedDropsButStaysOpen;
    [Test]
    procedure CloseModuleDropsEntriesOfWorker;
    [Test]
    // Wie StopDropsWaitingAndLaterEntries: Start legt einen neuen Besitzer-Thread an.
    [IgnoreMemoryLeaks]
    procedure StopEmptiesPendingList;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Diagnostics,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread;

/// <summary>Wartet ohne TThread.WaitFor (das arbeitet im Hauptthread die Warteschlange ab).</summary>
procedure WaitFinished(AThread: TThread);
var
  Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  while not AThread.Finished and (Watch.ElapsedMilliseconds < 5000) do
  begin
    Sleep(1);
  end;
end;

{ TAtlasMainThreadTests }

procedure TAtlasMainThreadTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasMainThreadTests' + TGUID.NewGuid.ToString);
  FOldFolder := TAtlasGuard.RotatingLog.Folder;
  TAtlasGuard.RotatingLog.Folder := FFolder;
  TAtlasGuard.Fuse.ResetAll;
  // Reste anderer Tests abarbeiten, damit sie hier nicht mitzählen.
  CheckSynchronize;
end;

procedure TAtlasMainThreadTests.TearDown;
begin
  // Ein Test, der Stop ohne Start verließe, ließe spätere Einträge verpuffen.
  TAtlasMainThread.Start;
  TAtlasGuard.OnFailure := nil;
  TAtlasGuard.Fuse.ResetAll;
  TAtlasGuard.RotatingLog.Folder := FOldFolder;
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
  FOldFolder := '';
end;

procedure TAtlasMainThreadTests.QueueRunsAtOnceInMainThread;
var
  Ran: Boolean;
begin
  Ran := False;
  TAtlasMainThread.Queue(TAtlasFeature.Completion,
    procedure
    begin
      Ran := True;
    end);
  Assert.IsTrue(Ran, 'Queue im Hauptthread läuft sofort');
end;

procedure TAtlasMainThreadTests.ForceQueueWaitsForCheckSynchronize;
var
  Count: Integer;
begin
  Count := 0;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Completion,
    procedure
    begin
      Inc(Count);
    end);
  Assert.AreEqual(0, Count, 'ForceQueue wartet auf CheckSynchronize');
  CheckSynchronize;
  Assert.AreEqual(1, Count);
  CheckSynchronize;
  Assert.AreEqual(1, Count, 'genau einmal');
end;

procedure TAtlasMainThreadTests.EntryOfFreedWorkerStillRuns;
var
  Worker: TThread;
  Ran: Boolean;
begin
  Ran := False;
  Worker := TThread.CreateAnonymousThread(
    procedure
    begin
      TAtlasMainThread.Queue(TAtlasFeature.Completion,
        procedure
        begin
          Ran := True;
        end);
    end);
  Worker.FreeOnTerminate := False;
  Worker.Start;
  WaitFinished(Worker);
  // Wie ReapWorkers: Der Arbeiter ist frei, bevor CheckSynchronize läuft.
  Worker.Free;
  Assert.IsFalse(Ran, 'noch nicht ausgeführt');
  CheckSynchronize;
  Assert.IsTrue(Ran, 'Eintrag überlebt das Freigeben des Arbeiters');
end;

procedure TAtlasMainThreadTests.StopDropsWaitingAndLaterEntries;
var
  Count: Integer;
  Increment: TThreadProcedure;
begin
  Count := 0;
  Increment :=
    procedure
    begin
      Inc(Count);
    end;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, Increment);
  TAtlasMainThread.Stop;
  try
    TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, Increment);
    CheckSynchronize;
    Assert.AreEqual(0, Count, 'wartende und spätere Einträge verworfen');
    TAtlasMainThread.Queue(TAtlasFeature.Completion, Increment);
    Assert.AreEqual(1, Count, 'Queue im Hauptthread läuft auch nach Stop sofort');
  finally
    TAtlasMainThread.Start;
  end;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, Increment);
  CheckSynchronize;
  Assert.AreEqual(2, Count, 'nach Start wieder angenommen');
end;

procedure TAtlasMainThreadTests.ExceptionCountsForFeature;
var
  Failures: Integer;
  Feature: TAtlasFeature;
begin
  Failures := 0;
  Feature := TAtlasFeature.Completion;
  TAtlasGuard.OnFailure :=
    procedure(AFeature: TAtlasFeature)
    begin
      Inc(Failures);
      Feature := AFeature;
    end;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Hover,
    procedure
    begin
      raise EInvalidOpException.Create('kaputt');
    end);
  Assert.WillNotRaise(
    procedure
    begin
      CheckSynchronize;
    end);
  Assert.AreEqual(1, Failures);
  Assert.IsTrue(Feature = TAtlasFeature.Hover, 'zählt für das angegebene Feature');
end;

procedure TAtlasMainThreadTests.QueueFromWorkerRunsInMainThread;
var
  Worker: TThread;
  RanIn: TThreadID;
begin
  RanIn := 0;
  Worker := TThread.CreateAnonymousThread(
    procedure
    begin
      TAtlasMainThread.Queue(TAtlasFeature.Signature,
        procedure
        begin
          RanIn := TThread.CurrentThread.ThreadID;
        end);
    end);
  Worker.FreeOnTerminate := False;
  Worker.Start;
  WaitFinished(Worker);
  Worker.Free;
  CheckSynchronize;
  Assert.IsTrue(RanIn = MainThreadID, 'Eintrag läuft im Hauptthread');
end;

/// <summary>Zählt jeden Aufruf in ACount; eigene Routine, damit keine andere anonyme Methode den Rahmen teilt.
/// </summary>
function Counter(var ACount: Integer): TThreadProcedure;
var
  mCount: PInteger;
begin
  mCount := @ACount;
  Result :=
    procedure
    begin
      Inc(mCount^);
    end;
end;

/// <summary>Arbeit eines Arbeiters, der AProc über Queue einreiht; eigene Routine, damit der Arbeiter den Wert
/// einfängt und nicht die Variable des Tests.</summary>
function Enqueuer(const AProc: TThreadProcedure): TProc;
var
  mProc: TThreadProcedure;
begin
  mProc := AProc;
  Result :=
    procedure
    begin
      TAtlasMainThread.Queue(TAtlasFeature.Hover, mProc);
    end;
end;

procedure TAtlasMainThreadTests.ModuleOfIsModuleOfTheCode;
var
  mCount: Integer;
begin
  mCount := 0;
  Assert.IsTrue(TAtlasMainThread.ModuleOf(Counter(mCount)) = NativeUInt(FindHInstance(@Counter)),
    'Modul der Routine, die die anonyme Methode übersetzt hat');
  Assert.IsTrue(TAtlasMainThread.ModuleOf(Counter(mCount)) <> 0);
  Assert.IsTrue(TAtlasMainThread.ModuleOf(nil) = 0, 'ohne Methode');
end;

procedure TAtlasMainThreadTests.CloseModuleDropsWaitingAndLaterEntries;
var
  mCount: Integer;
  mIncrement: TThreadProcedure;
  mModule: NativeUInt;
begin
  mCount := 0;
  mIncrement := Counter(mCount);
  mModule := TAtlasMainThread.ModuleOf(mIncrement);
  TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, mIncrement);
  Assert.AreEqual(1, TAtlasMainThread.PendingCount);
  TAtlasMainThread.CloseModule(mModule);
  try
    Assert.AreEqual(0, TAtlasMainThread.PendingCount, 'wartender Eintrag verworfen');
    TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, mIncrement);
    Assert.AreEqual(0, TAtlasMainThread.PendingCount, 'späterer Eintrag nicht angenommen');
    CheckSynchronize;
    Assert.AreEqual(0, mCount, 'nichts vom abgemeldeten Modul ausgeführt');
    TAtlasMainThread.Queue(TAtlasFeature.Completion, mIncrement);
    Assert.AreEqual(1, mCount, 'Queue im Hauptthread läuft weiter sofort');
  finally
    TAtlasMainThread.OpenModule(mModule);
  end;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, mIncrement);
  CheckSynchronize;
  Assert.AreEqual(2, mCount, 'nach dem Anmelden wieder angenommen');
  mIncrement := nil;
end;

procedure TAtlasMainThreadTests.CloseOtherModuleKeepsEntries;
var
  mCount: Integer;
  mIncrement: TThreadProcedure;
  mOther: NativeUInt;
begin
  mCount := 0;
  mIncrement := Counter(mCount);
  mOther := TAtlasMainThread.ModuleOf(mIncrement) + 1;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, mIncrement);
  TAtlasMainThread.CloseModule(mOther);
  try
    TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, mIncrement);
    CheckSynchronize;
    Assert.AreEqual(2, mCount, 'Einträge anderer Module laufen');
  finally
    TAtlasMainThread.OpenModule(mOther);
  end;
  mIncrement := nil;
end;

procedure TAtlasMainThreadTests.ModuleUnloadedDropsButStaysOpen;
var
  mCount: Integer;
  mIncrement: TThreadProcedure;
begin
  mCount := 0;
  mIncrement := Counter(mCount);
  TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, mIncrement);
  TAtlasMainThread.ModuleUnloaded(TAtlasMainThread.ModuleOf(mIncrement));
  CheckSynchronize;
  Assert.AreEqual(0, mCount, 'wartender Eintrag des entladenen Moduls verworfen');
  TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, mIncrement);
  CheckSynchronize;
  Assert.AreEqual(1, mCount, 'ein neu geladenes Package unter demselben Handle beginnt offen');
  mIncrement := nil;
end;

procedure TAtlasMainThreadTests.CloseModuleDropsEntriesOfWorker;
var
  mCount: Integer;
  mIncrement: TThreadProcedure;
  mModule: NativeUInt;
  mWorker: TThread;
begin
  mCount := 0;
  mIncrement := Counter(mCount);
  mModule := TAtlasMainThread.ModuleOf(mIncrement);
  mWorker := TThread.CreateAnonymousThread(Enqueuer(mIncrement));
  mWorker.FreeOnTerminate := False;
  mWorker.Start;
  WaitFinished(mWorker);
  mWorker.Free;
  // Wie beim Abmelden eines Moduls, dessen Arbeiter noch ein Ergebnis eingereiht hat.
  TAtlasMainThread.CloseModule(mModule);
  try
    CheckSynchronize;
    Assert.AreEqual(0, mCount, 'Eintrag des Arbeiters verworfen');
  finally
    TAtlasMainThread.OpenModule(mModule);
  end;
  mIncrement := nil;
end;

procedure TAtlasMainThreadTests.StopEmptiesPendingList;
var
  mCount: Integer;
begin
  mCount := 0;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, Counter(mCount));
  TAtlasMainThread.Stop;
  try
    Assert.AreEqual(0, TAtlasMainThread.PendingCount, 'Stop leert die Liste');
  finally
    TAtlasMainThread.Start;
  end;
  CheckSynchronize;
  Assert.AreEqual(0, mCount);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMainThreadTests);

end.
