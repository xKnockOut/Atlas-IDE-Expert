unit Atlas.Core.Diagnostics.AsyncWait.Tests;

// Gemeinsames Warten auf asynchrone Anfragen (Code-Review D-105): fertig,
// Frist, Abbruch durch den Aufrufer, Abbruchsignal des Plugins. Nach dem
// Abbrechen meldet Await, ob die Anfrage beendet ist, und AwaitSettled kehrt
// erst nach ihrem Ende zurück (Code-Review W-103).

interface

uses
  System.SysUtils,
  DUnitX.TestFramework,
  Atlas.Core.Diagnostics.Deadline;

type
  [TestFixture]
  TAtlasAsyncWaitTests = class
  private
    FCompleted: Boolean;
    FCancels: Integer;
    FPolls: Integer;
    FLateEnd: TAtlasDeadline;
    function IsCompleted: TFunc<Boolean>;
    function Cancel: TProc;
    /// <summary>Anfrage, die erst AMs nach dem Abbruch endet.</summary>
    function LateIsCompleted: TFunc<Boolean>;
    function LateCancel(AMs: Cardinal): TProc;
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
    procedure DeadlineCancelsRequest;
    [Test]
    procedure CallerCancels;
    [Test]
    procedure ShutdownSignalStops;
    /// <summary>Endet die Anfrage nach dem Abbruch nicht sofort, meldet Await Completed = False.</summary>
    [Test]
    procedure RunningAfterCancelIsReported;
    /// <summary>AwaitSettled kehrt erst zurück, wenn die abgebrochene Anfrage beendet ist: Vorher dürfte der
    /// Aufrufer Client und Streams nicht freigeben.</summary>
    [Test]
    procedure SettledWaitsForLateEnd;
    [Test]
    procedure ConnectTimeoutIsCapped;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Diagnostics.AsyncWait;

const
  /// <summary>So spät endet die Anfrage in den Tests nach dem Abbruch.</summary>
  cLateEndMs = 300;

procedure TAtlasAsyncWaitTests.Setup;
begin
  FCompleted := False;
  FCancels := 0;
  FPolls := 0;
  FLateEnd := TAtlasDeadline.After(60000);
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

function TAtlasAsyncWaitTests.LateIsCompleted: TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Inc(FPolls);
      Result := (FCancels > 0) and FLateEnd.Reached;
    end;
end;

function TAtlasAsyncWaitTests.LateCancel(AMs: Cardinal): TProc;
begin
  Result :=
    procedure
    begin
      Inc(FCancels);
      FLateEnd := TAtlasDeadline.After(AMs);
    end;
end;

procedure TAtlasAsyncWaitTests.CompletedRequestIsDone;
var
  mResult: TAtlasAsyncResult;
begin
  FCompleted := True;
  mResult := TAtlasAsyncWait.Await(IsCompleted(), Cancel(), TAtlasDeadline.Passed, nil);
  Assert.AreEqual(Ord(TAtlasAsyncEnd.Done), Ord(mResult.Ended));
  Assert.IsTrue(mResult.Completed);
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
    end, Cancel(), TAtlasDeadline.After(60000), nil).Ended;
  Assert.AreEqual(Ord(TAtlasAsyncEnd.Done), Ord(mEnd));
  Assert.AreEqual(0, FCancels);
end;

procedure TAtlasAsyncWaitTests.DeadlineCancelsRequest;
var
  mResult: TAtlasAsyncResult;
begin
  mResult := TAtlasAsyncWait.Await(IsCompleted(), Cancel(), TAtlasDeadline.Passed, nil);
  Assert.AreEqual(Ord(TAtlasAsyncEnd.Timeout), Ord(mResult.Ended));
  Assert.AreEqual(1, FCancels);
  Assert.IsTrue(mResult.Completed);
end;

procedure TAtlasAsyncWaitTests.CallerCancels;
begin
  Assert.AreEqual(Ord(TAtlasAsyncEnd.Cancelled),
    Ord(TAtlasAsyncWait.Await(IsCompleted(), Cancel(), TAtlasDeadline.After(60000),
    function: Boolean
    begin
      Result := True;
    end).Ended));
  Assert.AreEqual(1, FCancels);
end;

procedure TAtlasAsyncWaitTests.ShutdownSignalStops;
begin
  TAtlasShutdown.Signal;
  Assert.AreEqual(Ord(TAtlasAsyncEnd.Stopped),
    Ord(TAtlasAsyncWait.Await(IsCompleted(), Cancel(), TAtlasDeadline.After(60000), nil).Ended));
  Assert.AreEqual(1, FCancels);
end;

procedure TAtlasAsyncWaitTests.RunningAfterCancelIsReported;
var
  mResult: TAtlasAsyncResult;
begin
  mResult := TAtlasAsyncWait.Await(LateIsCompleted(), LateCancel(cLateEndMs), TAtlasDeadline.Passed, nil);
  Assert.AreEqual(Ord(TAtlasAsyncEnd.Timeout), Ord(mResult.Ended));
  Assert.AreEqual(1, FCancels);
  Assert.IsFalse(mResult.Completed, 'Await meldet eine noch laufende Anfrage als beendet');
end;

procedure TAtlasAsyncWaitTests.SettledWaitsForLateEnd;
var
  mEnd: TAtlasAsyncEnd;
begin
  // Kein kurzes Nachwarten mehr: Endet die Anfrage erst nach dem früheren cDrainMs (500 ms), kehrt AwaitSettled
  // trotzdem erst nach ihrem Ende zurück.
  mEnd := TAtlasAsyncWait.AwaitSettled(LateIsCompleted(), LateCancel(cLateEndMs * 3), TAtlasDeadline.Passed, nil);
  Assert.AreEqual(Ord(TAtlasAsyncEnd.Timeout), Ord(mEnd));
  Assert.AreEqual(1, FCancels);
  Assert.IsTrue(FLateEnd.Reached, 'AwaitSettled kehrt vor dem Ende der Anfrage zurück');
end;

procedure TAtlasAsyncWaitTests.ConnectTimeoutIsCapped;
begin
  Assert.AreEqual(Integer(TAtlasAsyncWait.cConnectMs), TAtlasAsyncWait.ConnectTimeout(60000));
  Assert.AreEqual(1500, TAtlasAsyncWait.ConnectTimeout(1500));
  Assert.AreEqual(0, TAtlasAsyncWait.ConnectTimeout(-1));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAsyncWaitTests);

end.
