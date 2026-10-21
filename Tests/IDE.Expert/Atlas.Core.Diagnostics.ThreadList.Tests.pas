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
    [IgnoreMemoryLeaks]
    procedure StopAllReportsHangingThread;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Diagnostics.ThreadList;

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
  Release: TEvent;
begin
  Release := TEvent.Create(nil, True, False, '');
  List := TAtlasThreadList.Create;
  try
    List.Start(
      procedure
      begin
        Release.WaitFor(5000);
      end);
    // Hängt der Thread, meldet StopAll das; er gibt sich nach seiner Rückkehr selbst frei.
    Assert.IsFalse(List.StopAll(50));
    Assert.AreEqual(0, Integer(List.Count));
    Release.SetEvent;
    Sleep(200);
  finally
    List.Free;
    Release.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TThreadListTests);

end.
