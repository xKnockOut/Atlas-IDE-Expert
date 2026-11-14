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
  Atlas.Core.Diagnostics.ThreadList,
  Atlas.Core.Diagnostics.WorkerSlot;

type
  /// <summary>Setzt beim Freigeben AFreed: zeigt, wann ein Thread, der sich selbst freigibt, seine anonyme
  /// Methode losgelassen hat (abwarten statt eine feste Zeit schlafen).</summary>
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
  mSignal: IInterface;
begin
  mSignal := ASignal;
  Result :=
    procedure
    begin
      if mSignal <> nil then
      begin
        ARelease.WaitFor(5000);
      end;
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
  mList: TAtlasThreadList;
  mThread: TThread;
begin
  mList := TAtlasThreadList.Create;
  try
    mThread := mList.Start(
      procedure
      begin
      end);
    Assert.IsFalse(mThread.FreeOnTerminate);
    Assert.IsTrue(mList.StopAll(5000));
    Assert.AreEqual(0, Integer(mList.Count));
  finally
    mList.Free;
  end;
end;

procedure TThreadListTests.StopAllWaitsForRunningThread;
var
  mList: TAtlasThreadList;
  mRelease: TEvent;
  mDone: Boolean;
begin
  mDone := False;
  mRelease := TEvent.Create(nil, True, False, '');
  mList := TAtlasThreadList.Create;
  try
    mList.Start(
      procedure
      begin
        mRelease.WaitFor(5000);
        Sleep(50);
        mDone := True;
      end);
    mRelease.SetEvent;
    Assert.IsTrue(mList.StopAll(5000));
    // Erst nach dem Ende des Threads kehrt StopAll zurück.
    Assert.IsTrue(mDone);
  finally
    mList.Free;
    mRelease.Free;
  end;
end;

procedure TThreadListTests.StartPrunesFinishedThreads;
var
  mList: TAtlasThreadList;
  mFirst: TThread;
  mWaited: Integer;
begin
  mList := TAtlasThreadList.Create;
  try
    mFirst := mList.Start(
      procedure
      begin
      end);
    mWaited := 0;
    while not mFirst.Finished and (mWaited < 5000) do
    begin
      Sleep(5);
      Inc(mWaited, 5);
    end;
    Assert.IsTrue(mFirst.Finished);
    mList.Start(
      procedure
      begin
      end);
    // Der erste ist beendet und beim zweiten Start freigegeben worden.
    Assert.AreEqual(1, Integer(mList.Count));
    Assert.IsTrue(mList.StopAll(5000));
  finally
    mList.Free;
  end;
end;

procedure TThreadListTests.StopAllReportsHangingThread;
var
  mList: TAtlasThreadList;
  mRelease, mFreed: TEvent;
  mSignaled: Boolean;
begin
  mSignaled := False;
  mRelease := TEvent.Create(nil, True, False, '');
  mFreed := TEvent.Create(nil, True, False, '');
  mList := TAtlasThreadList.Create;
  try
    StartHanging(mList, mRelease, mFreed);
    // Hängt der Thread, meldet StopAll das; TAtlasOverdueThreads gibt ihn nach seiner Rückkehr frei.
    Assert.IsFalse(mList.StopAll(50));
    Assert.AreEqual(0, Integer(mList.Count));
    Assert.AreEqual(1, TAtlasOverdueThreads.Pending(HInstance));
    mRelease.SetEvent;
    Assert.IsTrue(TAtlasOverdueThreads.Settle(HInstance, 5000));
    // Mit dem Thread geht seine anonyme Methode und damit das Signal.
    mSignaled := mFreed.WaitFor(5000) = TWaitResult.wrSignaled;
    Assert.IsTrue(mSignaled, 'Überfälliger Thread wurde nicht freigegeben');
  finally
    mList.Free;
    // Läuft der Thread noch, greift er später auf beide Ereignisse zu: dann lieber ein Leck im roten Test.
    if mSignaled then
    begin
      mFreed.Free;
      mRelease.Free;
    end;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TThreadListTests);

end.
