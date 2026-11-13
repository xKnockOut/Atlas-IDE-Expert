unit Atlas.Common.JsonRpc.WorkerPool.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TJsonRpcWorkerPoolTests = class
  public
    /// <summary>Wartende Aufträge belegen Threads; ein kurzer Auftrag startet trotzdem sofort in einem neuen.</summary>
    [Test]
    procedure ShortWorkDoesNotWaitBehindBlockedWork;
    /// <summary>Über MaxThreads wartet ein Auftrag, bis ein Thread frei wird.</summary>
    [Test]
    procedure WorkAboveMaxThreadsWaitsForFreeThread;
    /// <summary>Ein freier Thread übernimmt den nächsten Auftrag, statt einen weiteren anzulegen.</summary>
    [Test]
    procedure IdleThreadIsReused;
    /// <summary>Ohne Arbeit endet ein Thread nach IdleMs.</summary>
    [Test]
    procedure IdleThreadEndsAfterIdleTime;
    /// <summary>Close lässt angenommene Aufträge zu Ende laufen und lehnt neue ab.</summary>
    [Test]
    procedure CloseFinishesAcceptedWorkAndRefusesNew;
    /// <summary>Läuft ein Auftrag länger als das Warten in Close, meldet Close False; der Thread endet später.</summary>
    [Test]
    procedure CloseReportsWorkStillRunning;
    /// <summary>Nach einem Close mit False zählt ThreadCount den laufenden Thread, ein zweites Close wartet
    /// auf ihn.</summary>
    [Test]
    procedure SecondCloseAfterTimeoutWaitsForRunningThread;
    /// <summary>Eine Ausnahme im Auftrag beendet den Thread nicht.</summary>
    [Test]
    procedure ExceptionDoesNotStopWorker;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Common.JsonRpc.WorkerPool;

type
  /// <summary>Sperre für wartende Aufträge und Zähler der fertigen.</summary>
  ITestGate = interface
    ['{5C0B2F7E-91A4-4D63-B8E2-3A7F6D1C9E40}']
    procedure Open;
    procedure Pass;
    function Started: Integer;
    function Done: Integer;
  end;

  TTestGate = class(TInterfacedObject, ITestGate)
  private
    FEvent: TEvent;
    FStarted: Integer;
    FDone: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Open;
    procedure Pass;
    function Started: Integer;
    function Done: Integer;
  end;

constructor TTestGate.Create;
begin
  inherited Create;
  FEvent := TEvent.Create(nil, True, False, '');
end;

destructor TTestGate.Destroy;
begin
  FEvent.Free;
  inherited Destroy;
end;

procedure TTestGate.Open;
begin
  FEvent.SetEvent;
end;

procedure TTestGate.Pass;
begin
  TInterlocked.Increment(FStarted);
  FEvent.WaitFor(10000);
  TInterlocked.Increment(FDone);
end;

function TTestGate.Started: Integer;
begin
  Result := TInterlocked.CompareExchange(FStarted, 0, 0);
end;

function TTestGate.Done: Integer;
begin
  Result := TInterlocked.CompareExchange(FDone, 0, 0);
end;

/// <summary>Auftrag, der bis zum Öffnen von AGate wartet.</summary>
function GateWork(const AGate: ITestGate): TProc;
var
  mGate: ITestGate;
begin
  mGate := AGate;
  Result :=
    procedure
    begin
      mGate.Pass;
    end;
end;

/// <summary>Auftrag, der sofort durchläuft.</summary>
function QuickWork(const AGate: ITestGate): TProc;
var
  mGate: ITestGate;
begin
  mGate := AGate;
  mGate.Open;
  Result :=
    procedure
    begin
      mGate.Pass;
    end;
end;

function FailingWork: TProc;
begin
  Result :=
    procedure
    begin
      raise EInvalidOpException.Create('Testfehler');
    end;
end;

function DoneReached(const AGate: ITestGate; ACount: Integer): TFunc<Boolean>;
var
  mGate: ITestGate;
begin
  mGate := AGate;
  Result :=
    function: Boolean
    begin
      Result := mGate.Done >= ACount;
    end;
end;

function StartedReached(const AGate: ITestGate; ACount: Integer): TFunc<Boolean>;
var
  mGate: ITestGate;
begin
  mGate := AGate;
  Result :=
    function: Boolean
    begin
      Result := mGate.Started >= ACount;
    end;
end;

function NoThreads(const APool: IJsonRpcWorkerPool): TFunc<Boolean>;
var
  mPool: IJsonRpcWorkerPool;
begin
  mPool := APool;
  Result :=
    function: Boolean
    begin
      Result := mPool.ThreadCount = 0;
    end;
end;

function WaitUntil(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal): Boolean;
var
  mDue: UInt64;
begin
  mDue := TThread.GetTickCount64 + ATimeoutMs;
  while not ACondition() do
  begin
    if TThread.GetTickCount64 > mDue then
    begin
      Exit(False);
    end;
    TThread.Sleep(5);
  end;
  Result := True;
end;

{ TJsonRpcWorkerPoolTests }

procedure TJsonRpcWorkerPoolTests.ShortWorkDoesNotWaitBehindBlockedWork;
var
  mPool: IJsonRpcWorkerPool;
  mBlocked, mQuick: ITestGate;
  mIndex: Integer;
begin
  mPool := TJsonRpcWorkerPool.Create(64, 30000);
  mBlocked := TTestGate.Create;
  mQuick := TTestGate.Create;
  // Mehr wartende Aufträge, als ein Rechner Kerne hat.
  for mIndex := 1 to 24 do
  begin
    Assert.IsTrue(mPool.Run(GateWork(mBlocked)));
  end;
  Assert.IsTrue(mPool.Run(QuickWork(mQuick)));
  Assert.IsTrue(WaitUntil(DoneReached(mQuick, 1), 2000), 'Kurzer Auftrag wartete hinter den blockierten');
  Assert.AreEqual(0, mBlocked.Done);
  mBlocked.Open;
  Assert.IsTrue(mPool.Close(5000));
  Assert.AreEqual(24, mBlocked.Done);
end;

procedure TJsonRpcWorkerPoolTests.WorkAboveMaxThreadsWaitsForFreeThread;
var
  mPool: IJsonRpcWorkerPool;
  mFirst, mSecond: ITestGate;
begin
  mPool := TJsonRpcWorkerPool.Create(2, 30000);
  mFirst := TTestGate.Create;
  mSecond := TTestGate.Create;
  mPool.Run(GateWork(mFirst));
  mPool.Run(GateWork(mFirst));
  mPool.Run(GateWork(mSecond));
  Assert.IsTrue(WaitUntil(StartedReached(mFirst, 2), 2000));
  TThread.Sleep(50);
  Assert.AreEqual(0, mSecond.Started, 'Dritter Auftrag lief trotz voller Threads');
  Assert.AreEqual(2, mPool.ThreadCount);
  mSecond.Open;
  mFirst.Open;
  Assert.IsTrue(WaitUntil(DoneReached(mSecond, 1), 2000));
  Assert.IsTrue(mPool.Close(5000));
end;

procedure TJsonRpcWorkerPoolTests.IdleThreadIsReused;
var
  mPool: IJsonRpcWorkerPool;
  mGate: ITestGate;
  mIndex: Integer;
begin
  mPool := TJsonRpcWorkerPool.Create(64, 30000);
  mGate := TTestGate.Create;
  for mIndex := 1 to 5 do
  begin
    mPool.Run(QuickWork(mGate));
    Assert.IsTrue(WaitUntil(DoneReached(mGate, mIndex), 2000));
    // Erst wartet der Thread wieder, dann kommt der nächste Auftrag.
    TThread.Sleep(20);
  end;
  Assert.AreEqual(1, mPool.ThreadCount);
  Assert.IsTrue(mPool.Close(5000));
end;

procedure TJsonRpcWorkerPoolTests.IdleThreadEndsAfterIdleTime;
var
  mPool: IJsonRpcWorkerPool;
  mGate: ITestGate;
begin
  mPool := TJsonRpcWorkerPool.Create(64, 30);
  mGate := TTestGate.Create;
  mPool.Run(QuickWork(mGate));
  Assert.IsTrue(WaitUntil(DoneReached(mGate, 1), 2000));
  Assert.IsTrue(WaitUntil(NoThreads(mPool), 2000), 'Thread endete nicht nach IdleMs');
  Assert.IsTrue(mPool.Close(5000));
  // Der beendete Thread gibt sich selbst frei.
  TThread.Sleep(50);
end;

procedure TJsonRpcWorkerPoolTests.CloseFinishesAcceptedWorkAndRefusesNew;
var
  mPool: IJsonRpcWorkerPool;
  mGate, mLate: ITestGate;
begin
  mPool := TJsonRpcWorkerPool.Create(1, 30000);
  mGate := TTestGate.Create;
  mLate := TTestGate.Create;
  mPool.Run(GateWork(mGate));
  mPool.Run(GateWork(mGate));
  Assert.IsTrue(WaitUntil(StartedReached(mGate, 1), 2000));
  mGate.Open;
  Assert.IsTrue(mPool.Close(5000));
  Assert.AreEqual(2, mGate.Done);
  Assert.IsFalse(mPool.Run(QuickWork(mLate)));
  Assert.AreEqual(0, mLate.Done);
  Assert.AreEqual(0, mPool.ThreadCount);
end;

procedure TJsonRpcWorkerPoolTests.CloseReportsWorkStillRunning;
var
  mPool: IJsonRpcWorkerPool;
  mGate: ITestGate;
begin
  mPool := TJsonRpcWorkerPool.Create(4, 30000);
  mGate := TTestGate.Create;
  mPool.Run(GateWork(mGate));
  Assert.IsTrue(WaitUntil(StartedReached(mGate, 1), 2000));
  Assert.IsFalse(mPool.Close(30));
  mGate.Open;
  Assert.IsTrue(WaitUntil(DoneReached(mGate, 1), 2000));
  mPool := nil;
  // Der Thread hält den Pool bis zu seinem Ende und gibt sich dann selbst frei.
  TThread.Sleep(100);
end;

procedure TJsonRpcWorkerPoolTests.SecondCloseAfterTimeoutWaitsForRunningThread;
var
  mPool: IJsonRpcWorkerPool;
  mGate, mQuick: ITestGate;
begin
  mPool := TJsonRpcWorkerPool.Create(4, 30000);
  mGate := TTestGate.Create;
  mQuick := TTestGate.Create;
  // Ein Thread ist schon fertig, wenn Close aufgibt; den gibt Close frei, den anderen nicht.
  mPool.Run(GateWork(mGate));
  mPool.Run(QuickWork(mQuick));
  Assert.IsTrue(WaitUntil(StartedReached(mGate, 1), 2000));
  Assert.IsTrue(WaitUntil(DoneReached(mQuick, 1), 2000));
  Assert.IsFalse(mPool.Close(30));
  Assert.AreEqual(1, mPool.ThreadCount);
  mGate.Open;
  Assert.IsTrue(mPool.Close(5000));
  Assert.AreEqual(0, mPool.ThreadCount);
  Assert.AreEqual(1, mGate.Done);
  mPool := nil;
  // Der aufgegebene Thread gibt sich nach Execute selbst frei.
  TThread.Sleep(100);
end;

procedure TJsonRpcWorkerPoolTests.ExceptionDoesNotStopWorker;
var
  mPool: IJsonRpcWorkerPool;
  mGate: ITestGate;
begin
  mPool := TJsonRpcWorkerPool.Create(1, 30000);
  mGate := TTestGate.Create;
  mPool.Run(FailingWork());
  mPool.Run(QuickWork(mGate));
  Assert.IsTrue(WaitUntil(DoneReached(mGate, 1), 2000));
  Assert.AreEqual(1, mPool.ThreadCount);
  Assert.IsTrue(mPool.Close(5000));
end;

end.
