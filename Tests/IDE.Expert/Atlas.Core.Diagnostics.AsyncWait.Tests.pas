unit Atlas.Core.Diagnostics.AsyncWait.Tests;

// Gemeinsames Warten auf asynchrone Anfragen (Code-Review D-105): fertig,
// Frist, Abbruch durch den Aufrufer, Abbruchsignal des Plugins; nach dem
// Abbrechen wartet es kurz auf das Ende der Anfrage.

interface

uses
  System.SysUtils,
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasAsyncWaitTests = class
  private
    FCompleted: Boolean;
    FCancels: Integer;
    FPolls: Integer;
    function IsCompleted: TFunc<Boolean>;
    function Cancel: TProc;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CompletedRequestIsDone;
    [Test]
    procedure CompletesWhileWaiting;
    /// <summary>Frist erreicht: abbrechen und auf das Ende warten.</summary>
    [Test]
    procedure DeadlineCancelsAndDrains;
    [Test]
    procedure CallerCancels;
    [Test]
    procedure ShutdownSignalStops;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Diagnostics.AsyncWait;

procedure TAtlasAsyncWaitTests.Setup;
begin
  FCompleted := False;
  FCancels := 0;
  FPolls := 0;
  TAtlasShutdown.Reset;
end;

procedure TAtlasAsyncWaitTests.TearDown;
begin
  TAtlasShutdown.Reset;
end;

function TAtlasAsyncWaitTests.IsCompleted: TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Inc(FPolls);
      Result := FCompleted;
    end;
end;

function TAtlasAsyncWaitTests.Cancel: TProc;
begin
  Result :=
    procedure
    begin
      Inc(FCancels);
      FCompleted := True;
    end;
end;

procedure TAtlasAsyncWaitTests.CompletedRequestIsDone;
begin
  FCompleted := True;
  Assert.AreEqual(Ord(TAtlasAsyncEnd.Done),
    Ord(TAtlasAsyncWait.Await(IsCompleted(), Cancel(), TAtlasDeadline.Passed, nil)));
  Assert.AreEqual(0, FCancels);
end;

procedure TAtlasAsyncWaitTests.CompletesWhileWaiting;
var
  mEnd: TAtlasAsyncEnd;
begin
  mEnd := TAtlasAsyncWait.Await(
    function: Boolean
    begin
      Inc(FPolls);
      Result := FPolls > 2;
    end, Cancel(), TAtlasDeadline.After(60000), nil);
  Assert.AreEqual(Ord(TAtlasAsyncEnd.Done), Ord(mEnd));
  Assert.AreEqual(0, FCancels);
end;

procedure TAtlasAsyncWaitTests.DeadlineCancelsAndDrains;
begin
  Assert.AreEqual(Ord(TAtlasAsyncEnd.Timeout),
    Ord(TAtlasAsyncWait.Await(IsCompleted(), Cancel(), TAtlasDeadline.Passed, nil)));
  Assert.AreEqual(1, FCancels);
  Assert.IsTrue(FCompleted);
end;

procedure TAtlasAsyncWaitTests.CallerCancels;
begin
  Assert.AreEqual(Ord(TAtlasAsyncEnd.Cancelled),
    Ord(TAtlasAsyncWait.Await(IsCompleted(), Cancel(), TAtlasDeadline.After(60000),
    function: Boolean
    begin
      Result := True;
    end)));
  Assert.AreEqual(1, FCancels);
end;

procedure TAtlasAsyncWaitTests.ShutdownSignalStops;
begin
  TAtlasShutdown.Signal;
  Assert.AreEqual(Ord(TAtlasAsyncEnd.Stopped),
    Ord(TAtlasAsyncWait.Await(IsCompleted(), Cancel(), TAtlasDeadline.After(60000), nil)));
  Assert.AreEqual(1, FCancels);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAsyncWaitTests);

end.
