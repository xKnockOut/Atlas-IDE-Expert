unit Atlas.Common.Lsp.PullDiagnostics.Cache.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Lsp.PullDiagnostics.Cache;

type
  [TestFixture]
  TPullReportCacheTests = class
  private
    FCache: TPullReportCache;
    FComputed: Integer;
    function Compute: TPullCompute;
    function CountOf(const AUri, AResultId: string): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WithoutResultIdAlwaysComputes;
    [Test]
    procedure SameStateComesFromStore;
    [Test]
    procedure NewStateComputesAgain;
    [Test]
    procedure FilesAreStoredSeparately;
    [Test]
    procedure WaiterTakesResultOfRunningComputation;
    [Test]
    procedure CancelledWaiterStops;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.Diagnostics,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract;

type
  /// <summary>Abbruchsignal einer abgebrochenen Anfrage.</summary>
  TCancelledToken = class(TInterfacedObject, IJsonRpcCancellationToken)
  public
    function IsCancellationRequested: Boolean;
    procedure ThrowIfCancellationRequested;
  end;

function TCancelledToken.IsCancellationRequested: Boolean;
begin
  Result := True;
end;

procedure TCancelledToken.ThrowIfCancellationRequested;
begin
  raise EJsonRpcRequestCancelled.Create;
end;

/// <summary>Berechnung in einem eigenen Thread, die AStarted setzt, auf AGo wartet und [42] liefert.</summary>
function ComputeInThread(ACache: TPullReportCache; AStarted, AGo: TEvent): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    begin
      ACache.Get('file:///a.pas', '1',
        function: TJSONArray
        begin
          AStarted.SetEvent;
          AGo.WaitFor(10000);
          Result := TJSONArray.Create;
          Result.Add(42);
        end, nil).Free;
    end);
  Result.FreeOnTerminate := False;
  Result.Start;
end;

procedure TPullReportCacheTests.Setup;
begin
  FComputed := 0;
  FCache := TPullReportCache.Create;
end;

procedure TPullReportCacheTests.TearDown;
begin
  FCache.Free;
  FCache := nil;
end;

function TPullReportCacheTests.Compute: TPullCompute;
var
  mTests: TPullReportCacheTests;
begin
  mTests := Self;
  Result :=
    function: TJSONArray
    begin
      Inc(mTests.FComputed);
      Result := TJSONArray.Create;
      Result.Add(mTests.FComputed);
    end;
end;

/// <summary>Zahl im ersten Eintrag der Befunde, also der Lauf, der sie berechnet hat.</summary>
function TPullReportCacheTests.CountOf(const AUri, AResultId: string): Integer;
var
  mItems: TJSONArray;
begin
  mItems := FCache.Get(AUri, AResultId, Compute(), nil);
  try
    Result := mItems.Items[0].GetValue<Integer>;
  finally
    mItems.Free;
  end;
end;

procedure TPullReportCacheTests.WithoutResultIdAlwaysComputes;
begin
  Assert.AreEqual(1, CountOf('file:///a.pas', ''));
  Assert.AreEqual(2, CountOf('file:///a.pas', ''));
  Assert.AreEqual(2, FComputed);
end;

procedure TPullReportCacheTests.SameStateComesFromStore;
begin
  Assert.AreEqual(1, CountOf('file:///a.pas', '1:v1'));
  Assert.AreEqual(1, CountOf('file:///a.pas', '1:v1'));
  Assert.AreEqual(1, FComputed);
end;

procedure TPullReportCacheTests.NewStateComputesAgain;
begin
  CountOf('file:///a.pas', '1:v1');
  Assert.AreEqual(2, CountOf('file:///a.pas', '1:v2'));
  Assert.AreEqual(2, FComputed);
end;

procedure TPullReportCacheTests.FilesAreStoredSeparately;
begin
  CountOf('file:///a.pas', '1:v1');
  Assert.AreEqual(2, CountOf('file:///b.pas', '1:v1'));
  Assert.AreEqual(1, CountOf('file:///a.pas', '1:v1'));
end;

procedure TPullReportCacheTests.WaiterTakesResultOfRunningComputation;
var
  mStarted, mGo: TEvent;
  mThread: TThread;
  mItems: TJSONArray;
  mClock: TStopwatch;
begin
  mStarted := TEvent.Create(nil, True, False, '');
  mGo := TEvent.Create(nil, True, False, '');
  try
    mThread := ComputeInThread(FCache, mStarted, mGo);
    try
      Assert.AreEqual(Ord(wrSignaled), Ord(mStarted.WaitFor(10000)));
      TThread.CreateAnonymousThread(
        procedure
        begin
          Sleep(50);
          mGo.SetEvent;
        end).Start;
      // Dieselbe Datei im selben Stand: kein eigener Lauf, das Ende der Berechnung weckt den Wartenden.
      mClock := TStopwatch.StartNew;
      mItems := FCache.Get('file:///a.pas', '1', Compute(), nil);
      try
        Assert.AreEqual(0, FComputed);
        Assert.AreEqual(42, mItems.Items[0].GetValue<Integer>);
      finally
        mItems.Free;
      end;
      Assert.IsTrue(mClock.ElapsedMilliseconds < 5000);
      mThread.WaitFor;
    finally
      mThread.Free;
    end;
  finally
    mGo.Free;
    mStarted.Free;
  end;
end;

procedure TPullReportCacheTests.CancelledWaiterStops;
var
  mStarted, mGo: TEvent;
  mThread: TThread;
  mCache: TPullReportCache;
begin
  mCache := FCache;
  mStarted := TEvent.Create(nil, True, False, '');
  mGo := TEvent.Create(nil, True, False, '');
  try
    mThread := ComputeInThread(FCache, mStarted, mGo);
    try
      Assert.AreEqual(Ord(wrSignaled), Ord(mStarted.WaitFor(10000)));
      Assert.WillRaise(
        procedure
        begin
          mCache.Get('file:///a.pas', '1', Compute(), TCancelledToken.Create).Free;
        end, EJsonRpcRequestCancelled);
      Assert.AreEqual(0, FComputed);
      mGo.SetEvent;
      mThread.WaitFor;
    finally
      mThread.Free;
    end;
  finally
    mGo.Free;
    mStarted.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPullReportCacheTests);

end.
