unit Atlas.Core.Diagnostics.MainThread.Tests;

// Einreihen in den Hauptthread über TAtlasMainThread (Code-Review A-02):
// Einträge überleben das Freigeben des einreihenden Arbeiters, nicht aber
// Stop (Entladen); Ausnahmen zählen für das angegebene Feature.

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
    Sleep(1);
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
    TDirectory.Delete(FFolder, True);
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasMainThreadTests);

end.
