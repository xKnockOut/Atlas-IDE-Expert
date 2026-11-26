unit Atlas.Common.JsonRpc.Providers.ServerActivityObserver.Tests;

// Tests für den Beobachter am Verteiler (#1901): meldet Anfragen an die Aktivität und reicht sie weiter.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Diagnostics.ServerActivity;

type
  [TestFixture]
  TServerActivityObserverTests = class
  private
    FActivity: TServerActivity;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ObserverForwardsToNext;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Providers.ServerActivityObserver;

type
  /// <summary>Zählt die Meldungen, die der Beobachter weiterreicht.</summary>
  TCountingObserver = class(TInterfacedObject, IJsonRpcRequestObserver)
  public
    StartedCount: Integer;
    FinishedCount: Integer;
    procedure Started(const AMethod: string);
    procedure Finished(const AMethod: string; const AParams, AResult: TJSONValue; const AError: Exception;
      AQueueMs, AElapsedMs: Int64);
  end;

{ TCountingObserver }

procedure TCountingObserver.Started(const AMethod: string);
begin
  Inc(StartedCount);
end;

procedure TCountingObserver.Finished(const AMethod: string; const AParams, AResult: TJSONValue;
  const AError: Exception; AQueueMs, AElapsedMs: Int64);
begin
  Inc(FinishedCount);
end;

{ TServerActivityObserverTests }

procedure TServerActivityObserverTests.Setup;
begin
  FActivity := TServerActivity.Create;
end;

procedure TServerActivityObserverTests.TearDown;
begin
  FreeAndNil(FActivity);
end;

procedure TServerActivityObserverTests.ObserverForwardsToNext;
var
  mCounter: TCountingObserver;
  mNext, mObserver: IJsonRpcRequestObserver;
  mError: Exception;
begin
  mCounter := TCountingObserver.Create;
  mNext := mCounter;
  mObserver := TServerActivityObserver.Create(FActivity, mNext);
  mObserver.Started('initialize');
  Assert.AreEqual(1, FActivity.Snapshot(TThread.GetTickCount64).Running);
  mError := Exception.Create('kaputt');
  try
    mObserver.Finished('initialize', nil, nil, mError, 0, 5);
  finally
    mError.Free;
  end;
  Assert.AreEqual(1, mCounter.StartedCount);
  Assert.AreEqual(1, mCounter.FinishedCount);
  Assert.AreEqual(0, FActivity.Snapshot(TThread.GetTickCount64).Running);
  Assert.AreEqual(1, FActivity.Snapshot(TThread.GetTickCount64).Errors);
  // Ohne Nachfolger nur die Aktivität.
  mObserver := TServerActivityObserver.Create(FActivity, nil);
  mObserver.Started('shutdown');
  mObserver.Finished('shutdown', nil, nil, nil, 0, 1);
  Assert.AreEqual(1, FActivity.Snapshot(TThread.GetTickCount64).Errors);
end;

initialization
  TDUnitX.RegisterTestFixture(TServerActivityObserverTests);

end.
