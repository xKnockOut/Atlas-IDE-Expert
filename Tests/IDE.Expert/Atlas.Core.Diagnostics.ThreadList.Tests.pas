unit Atlas.Core.Diagnostics.ThreadList.Tests;

// Verfolgte Hintergrund-Threads (#886): Kein Thread gibt sich selbst frei,
// StopAll wartet auf alle, Start räumt beendete auf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TThreadListTests = class
  public
    [Test]
    procedure StartedThreadDoesNotFreeItself;
    [Test]
    procedure StopAllWaitsForRunningThread;
    [Test]
    procedure StartPrunesFinishedThreads;
    [Test]
    procedure StopAllReportsHangingThread;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Diagnostics.ThreadList;

type
  /// <summary>Setzt beim Freigeben AFreed: zeigt, wann ein Thread, der sich selbst freigibt, seine anonyme
  /// Methode losgelassen hat (Bericht N2: abwarten statt eine feste Zeit schlafen).</summary>
  TFreedSignal = class(TInterfacedObject)
  private
    FFreed: TEvent;
  public
    constructor Create(AFreed: TEvent);
    destructor Destroy; override;
  end;

constructor TFreedSignal.Create(AFreed: TEvent);
begin
  inherited Create;
  FFreed := AFreed;
end;

destructor TFreedSignal.Destroy;
begin
  FFreed.SetEvent;
  inherited;
end;

/// <summary>Wartet auf ARelease und hält ASignal, bis der Thread die Methode freigibt. ASignal wird als Wert
/// erfasst, nicht als Variable des Aufrufers.</summary>
function Hanging(ARelease: TEvent; const ASignal: IInterface): TProc;
var
  Signal: IInterface;
begin
  Signal := ASignal;
  Result :=
    procedure
    begin
      if Signal <> nil then
        ARelease.WaitFor(5000);
    end;
end;

/// <summary>Eigene Routine: Hilfswerte des Aufrufs (Methode, Signal) gibt sie beim Rücksprung frei, sonst hielte
/// der Test sie bis zu seinem Ende.</summary>
procedure StartHanging(AList: TAtlasThreadList; ARelease, AFreed: TEvent);
begin
  AList.Start(Hanging(ARelease, TFreedSignal.Create(AFreed)));
end;

procedure TThreadListTests.StartedThreadDoesNotFreeItself;
var
  List: TAtlasThreadList;
  Thread: TThread;
begin
  List := TAtlasThreadList.Create;
  try
    Thread := List.Start(
      procedure
      begin
      end);
    Assert.IsFalse(Thread.FreeOnTerminate);
    Assert.IsTrue(List.StopAll(5000));
    Assert.AreEqual(0, Integer(List.Count));
  finally
    List.Free;
  end;
end;

procedure TThreadListTests.StopAllWaitsForRunningThread;
var
  List: TAtlasThreadList;
  Release: TEvent;
  Done: Boolean;
begin
  Done := False;
  Release := TEvent.Create(nil, True, False, '');
  List := TAtlasThreadList.Create;
  try
    List.Start(
      procedure
      begin
        Release.WaitFor(5000);
        Sleep(50);
        Done := True;
      end);
    Release.SetEvent;
    Assert.IsTrue(List.StopAll(5000));
    // Erst nach dem Ende des Threads kehrt StopAll zurück.
    Assert.IsTrue(Done);
  finally
    List.Free;
    Release.Free;
  end;
end;

procedure TThreadListTests.StartPrunesFinishedThreads;
var
  List: TAtlasThreadList;
  First: TThread;
  Waited: Integer;
begin
  List := TAtlasThreadList.Create;
  try
    First := List.Start(
      procedure
      begin
      end);
    Waited := 0;
    while not First.Finished and (Waited < 5000) do
    begin
      Sleep(5);
      Inc(Waited, 5);
    end;
    Assert.IsTrue(First.Finished);
    List.Start(
      procedure
      begin
      end);
    // Der erste ist beendet und beim zweiten Start freigegeben worden.
    Assert.AreEqual(1, Integer(List.Count));
    Assert.IsTrue(List.StopAll(5000));
  finally
    List.Free;
  end;
end;

procedure TThreadListTests.StopAllReportsHangingThread;
var
  List: TAtlasThreadList;
  Release, Freed: TEvent;
  Signaled: Boolean;
begin
  Signaled := False;
  Release := TEvent.Create(nil, True, False, '');
  Freed := TEvent.Create(nil, True, False, '');
  List := TAtlasThreadList.Create;
  try
    StartHanging(List, Release, Freed);
    // Hängt der Thread, meldet StopAll das; er gibt sich nach seiner Rückkehr selbst frei.
    Assert.IsFalse(List.StopAll(50));
    Assert.AreEqual(0, Integer(List.Count));
    Release.SetEvent;
    // Mit sich selbst gibt er seine anonyme Methode frei und damit das Signal.
    Signaled := Freed.WaitFor(5000) = TWaitResult.wrSignaled;
    Assert.IsTrue(Signaled, 'Thread gab sich nicht selbst frei');
  finally
    List.Free;
    // Läuft der Thread noch, greift er später auf beide Ereignisse zu: dann lieber ein Leck im roten Test.
    if Signaled then
    begin
      Freed.Free;
      Release.Free;
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TThreadListTests);

end.
