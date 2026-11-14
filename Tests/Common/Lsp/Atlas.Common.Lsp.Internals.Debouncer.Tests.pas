unit Atlas.Common.Lsp.Internals.Debouncer.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDebouncerTests = class
  public
    [Test]
    procedure RunsImmediatelyWithoutDelay;
    [Test]
    procedure RunsOnlyLastActionPerKey;
    [Test]
    procedure KeepsKeysSeparate;
    [Test]
    procedure CancelDropsPendingAction;
    [Test]
    procedure ReportsErrorsAndKeepsRunning;
    [Test]
    procedure DestroyDropsPendingActions;
    [Test]
    procedure WaitIdleWaitsForPendingAndRunningActions;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Common.Lsp.Internals.Debouncer;

type
  /// <summary>Hält fest, welche Aktionen gelaufen sind, und meldet die erwartete Anzahl.</summary>
  TRecorder = class
  private
    FValues: TStringList;
    FDone: TCountdownEvent;
  public
    constructor Create(AExpected: Integer);
    destructor Destroy; override;
    function Action(const AValue: string): TProc;
    function WaitFor(ATimeoutMs: Cardinal): Boolean;
    /// <summary>Gelaufene Aktionen, sortiert und mit Komma getrennt.</summary>
    function Text: string;
  end;

{ TRecorder }

constructor TRecorder.Create(AExpected: Integer);
begin
  inherited Create;
  FValues := TStringList.Create;
  FDone := TCountdownEvent.Create(AExpected);
end;

destructor TRecorder.Destroy;
begin
  FDone.Free;
  FValues.Free;
  inherited;
end;

function TRecorder.Action(const AValue: string): TProc;
begin
  Result :=
    procedure
    begin
      TMonitor.Enter(FValues);
      try
        FValues.Add(AValue);
      finally
        TMonitor.Exit(FValues);
      end;
      if not FDone.IsSet then
      begin
        FDone.Signal;
      end;
    end;
end;

function TRecorder.WaitFor(ATimeoutMs: Cardinal): Boolean;
begin
  Result := FDone.WaitFor(ATimeoutMs) = TWaitResult.wrSignaled;
end;

function TRecorder.Text: string;
begin
  TMonitor.Enter(FValues);
  try
    FValues.Sort;
    Result := FValues.CommaText;
  finally
    TMonitor.Exit(FValues);
  end;
end;

{ TDebouncerTests }

procedure TDebouncerTests.RunsImmediatelyWithoutDelay;
var
  mDebouncer: TDebouncer;
  mCount: Integer;
begin
  mCount := 0;
  mDebouncer := TDebouncer.Create(0);
  try
    mDebouncer.Schedule('a',
      procedure
      begin
        Inc(mCount);
      end);
    Assert.AreEqual(1, mCount);
  finally
    mDebouncer.Free;
  end;
end;

procedure TDebouncerTests.RunsOnlyLastActionPerKey;
var
  mDebouncer: TDebouncer;
  mRecorder: TRecorder;
  mIndex: Integer;
begin
  mRecorder := TRecorder.Create(1);
  mDebouncer := TDebouncer.Create(50);
  try
    for mIndex := 1 to 5 do
    begin
      mDebouncer.Schedule('a', mRecorder.Action(IntToStr(mIndex)));
    end;
    Assert.IsTrue(mRecorder.WaitFor(2000));
    Sleep(150);
    Assert.AreEqual('5', mRecorder.Text);
  finally
    mDebouncer.Free;
    mRecorder.Free;
  end;
end;

procedure TDebouncerTests.KeepsKeysSeparate;
var
  mDebouncer: TDebouncer;
  mRecorder: TRecorder;
begin
  mRecorder := TRecorder.Create(2);
  mDebouncer := TDebouncer.Create(20);
  try
    mDebouncer.Schedule('a', mRecorder.Action('a'));
    mDebouncer.Schedule('b', mRecorder.Action('b'));
    Assert.IsTrue(mRecorder.WaitFor(2000));
    Assert.AreEqual('a,b', mRecorder.Text);
  finally
    mDebouncer.Free;
    mRecorder.Free;
  end;
end;

procedure TDebouncerTests.WaitIdleWaitsForPendingAndRunningActions;
var
  mDebouncer: TDebouncer;
  mFinished: Integer;
begin
  // #177: Messungen im Dauerlauf erst, wenn nichts mehr geplant ist und nichts läuft.
  mFinished := 0;
  mDebouncer := TDebouncer.Create(20);
  try
    Assert.IsTrue(mDebouncer.WaitIdle(0), 'leer ist sofort ruhig');
    mDebouncer.Schedule('a',
      procedure
      begin
        TThread.Sleep(50);
        TInterlocked.Increment(mFinished);
      end);
    Assert.IsFalse(mDebouncer.WaitIdle(5), 'geplant ist nicht ruhig');
    Assert.IsTrue(mDebouncer.WaitIdle(2000));
    Assert.AreEqual(1, TInterlocked.CompareExchange(mFinished, 0, 0), 'erst nach der laufenden Aktion ruhig');
  finally
    mDebouncer.Free;
  end;
end;

procedure TDebouncerTests.CancelDropsPendingAction;
var
  mDebouncer: TDebouncer;
  mDone: TEvent;
  mCancelled: Boolean;
begin
  mCancelled := False;
  mDone := TEvent.Create(nil, True, False, '');
  mDebouncer := TDebouncer.Create(50);
  try
    mDebouncer.Schedule('a',
      procedure
      begin
        mCancelled := True;
      end);
    mDebouncer.Cancel('a');
    mDebouncer.Schedule('b',
      procedure
      begin
        mDone.SetEvent;
      end);
    Assert.AreEqual<TWaitResult>(TWaitResult.wrSignaled, mDone.WaitFor(2000));
    Assert.IsFalse(mCancelled);
  finally
    mDebouncer.Free;
    mDone.Free;
  end;
end;

procedure TDebouncerTests.ReportsErrorsAndKeepsRunning;
var
  mDebouncer: TDebouncer;
  mDone: TEvent;
  mError: string;
begin
  mError := '';
  mDone := TEvent.Create(nil, True, False, '');
  mDebouncer := TDebouncer.Create(10);
  try
    mDebouncer.OnError :=
      procedure(AE: Exception)
      begin
        mError := AE.Message;
      end;
    mDebouncer.Schedule('a',
      procedure
      begin
        raise Exception.Create('kaputt');
      end);
    Sleep(100);
    mDebouncer.Schedule('a',
      procedure
      begin
        mDone.SetEvent;
      end);
    Assert.AreEqual<TWaitResult>(TWaitResult.wrSignaled, mDone.WaitFor(2000));
    Assert.AreEqual('kaputt', mError);
  finally
    mDebouncer.Free;
    mDone.Free;
  end;
end;

procedure TDebouncerTests.DestroyDropsPendingActions;
var
  mDebouncer: TDebouncer;
  mRan: Boolean;
begin
  mRan := False;
  mDebouncer := TDebouncer.Create(1000);
  mDebouncer.Schedule('a',
    procedure
    begin
      mRan := True;
    end);
  mDebouncer.Free;
  Assert.IsFalse(mRan);
end;

initialization
  TDUnitX.RegisterTestFixture(TDebouncerTests);

end.
