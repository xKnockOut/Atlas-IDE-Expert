unit BDLsp.Common.Lsp.Internals.Debouncer.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  BDLsp.Common.Lsp.Internals.Debouncer;

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
        FDone.Signal;
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
  Debouncer: TDebouncer;
  Count: Integer;
begin
  Count := 0;
  Debouncer := TDebouncer.Create(0);
  try
    Debouncer.Schedule('a',
      procedure
      begin
        Inc(Count);
      end);
    Assert.AreEqual(1, Count);
  finally
    Debouncer.Free;
  end;
end;

procedure TDebouncerTests.RunsOnlyLastActionPerKey;
var
  Debouncer: TDebouncer;
  Recorder: TRecorder;
  Index: Integer;
begin
  Recorder := TRecorder.Create(1);
  Debouncer := TDebouncer.Create(50);
  try
    for Index := 1 to 5 do
      Debouncer.Schedule('a', Recorder.Action(IntToStr(Index)));
    Assert.IsTrue(Recorder.WaitFor(2000));
    Sleep(150);
    Assert.AreEqual('5', Recorder.Text);
  finally
    Debouncer.Free;
    Recorder.Free;
  end;
end;

procedure TDebouncerTests.KeepsKeysSeparate;
var
  Debouncer: TDebouncer;
  Recorder: TRecorder;
begin
  Recorder := TRecorder.Create(2);
  Debouncer := TDebouncer.Create(20);
  try
    Debouncer.Schedule('a', Recorder.Action('a'));
    Debouncer.Schedule('b', Recorder.Action('b'));
    Assert.IsTrue(Recorder.WaitFor(2000));
    Assert.AreEqual('a,b', Recorder.Text);
  finally
    Debouncer.Free;
    Recorder.Free;
  end;
end;

procedure TDebouncerTests.CancelDropsPendingAction;
var
  Debouncer: TDebouncer;
  Done: TEvent;
  Cancelled: Boolean;
begin
  Cancelled := False;
  Done := TEvent.Create(nil, True, False, '');
  Debouncer := TDebouncer.Create(50);
  try
    Debouncer.Schedule('a',
      procedure
      begin
        Cancelled := True;
      end);
    Debouncer.Cancel('a');
    Debouncer.Schedule('b',
      procedure
      begin
        Done.SetEvent;
      end);
    Assert.IsTrue(Done.WaitFor(2000) = TWaitResult.wrSignaled);
    Assert.IsFalse(Cancelled);
  finally
    Debouncer.Free;
    Done.Free;
  end;
end;

procedure TDebouncerTests.ReportsErrorsAndKeepsRunning;
var
  Debouncer: TDebouncer;
  Done: TEvent;
  Error: string;
begin
  Error := '';
  Done := TEvent.Create(nil, True, False, '');
  Debouncer := TDebouncer.Create(10);
  try
    Debouncer.OnError :=
      procedure(E: Exception)
      begin
        Error := E.Message;
      end;
    Debouncer.Schedule('a',
      procedure
      begin
        raise Exception.Create('kaputt');
      end);
    Sleep(100);
    Debouncer.Schedule('a',
      procedure
      begin
        Done.SetEvent;
      end);
    Assert.IsTrue(Done.WaitFor(2000) = TWaitResult.wrSignaled);
    Assert.AreEqual('kaputt', Error);
  finally
    Debouncer.Free;
    Done.Free;
  end;
end;

procedure TDebouncerTests.DestroyDropsPendingActions;
var
  Debouncer: TDebouncer;
  Ran: Boolean;
begin
  Ran := False;
  Debouncer := TDebouncer.Create(1000);
  Debouncer.Schedule('a',
    procedure
    begin
      Ran := True;
    end);
  Debouncer.Free;
  Assert.IsFalse(Ran);
end;

initialization
  TDUnitX.RegisterTestFixture(TDebouncerTests);

end.
