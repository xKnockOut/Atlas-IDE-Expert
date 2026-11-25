unit Atlas.Plugin.Lsp.BackgroundRequest.Tests;

// Tests für Serveranfragen im Hintergrund (2.0-stable: Inlay-Hints, Glühbirne, Überschreibungen und Gliederung
// warteten im Hauptthread): Abschluss im Hauptthread, höchstens eine Anfrage, verworfener Abschluss nach Freigabe,
// keine Antwort des Servers als AOk = False mit Meldung. Die Schlange arbeitet Aufträge der Reihe nach ab; von
// AddLatest-Aufträgen zählt nur der jüngste.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBackgroundRequestTests = class
  public
    [Test]
    procedure DoneRunsInMainThreadAfterWork;
    [Test]
    procedure SecondStartIsRefusedWhileBusy;
    [Test]
    procedure DoneIsDroppedAfterFree;
    [Test]
    procedure NoAnswerGivesErrorText;
    [Test]
    procedure OtherExceptionStillFinishes;
    [Test]
    procedure ServerErrorIsReportedWithText;
    [Test]
    procedure QueueRunsJobsInOrder;
    [Test]
    procedure QueueKeepsOnlyLatestCommand;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Lsp.Client,
  Atlas.Plugin.Lsp.BackgroundRequest,
  Atlas.Tests.Wait;

/// <summary>Arbeit, die bis zum Signal wartet.</summary>
function Blocked(AGate: TEvent): TProc;
begin
  Result :=
    procedure
    begin
      AGate.WaitFor(5000);
    end;
end;

/// <summary>Arbeit, die AError wirft.</summary>
function Raising(AError: Exception): TProc;
begin
  Result :=
    procedure
    begin
      raise AError;
    end;
end;

type
  /// <summary>Abschluss, der Aufrufe zählt und das Ergebnis festhält.</summary>
  TDoneProbe = class
  public
    Count: Integer;
    Ok: Boolean;
    Error: string;
    function Done: TAtlasRequestDone;
  end;

{ TDoneProbe }

function TDoneProbe.Done: TAtlasRequestDone;
begin
  Result :=
    procedure(AOk: Boolean; const AError: string)
    begin
      Inc(Count);
      Ok := AOk;
      Error := AError;
    end;
end;

type
  /// <summary>Abschlüsse, die ihren Namen der Reihe nach anhängen.</summary>
  TOrderProbe = class
  public
    Count: Integer;
    Log: string;
    function Done(const AName: string): TAtlasRequestDone;
  end;

{ TOrderProbe }

function TOrderProbe.Done(const AName: string): TAtlasRequestDone;
begin
  Result :=
    procedure(AOk: Boolean; const AError: string)
    begin
      Inc(Count);
      Log := Log + AName;
    end;
end;

/// <summary>Bedingung: die Schlange ist leer und nichts läuft mehr.</summary>
function Drained(AQueue: TAtlasBackgroundQueue; AProbe: TOrderProbe; ACount: Integer): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := (AQueue.Waiting = 0) and (AProbe.Count >= ACount);
    end;
end;

/// <summary>Bedingung: der Abschluss lief mindestens ACount-mal.</summary>
function Reached(AProbe: TDoneProbe; ACount: Integer): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := AProbe.Count >= ACount;
    end;
end;

{ TAtlasBackgroundRequestTests }

procedure TAtlasBackgroundRequestTests.DoneRunsInMainThreadAfterWork;
var
  mRequest: TAtlasBackgroundRequest;
  mWorkThread: TThreadID;
  mDoneThread: TThreadID;
  mWork: TProc;
  mFinish: TAtlasRequestDone;
  mOk: Boolean;
begin
  mWorkThread := 0;
  mDoneThread := 0;
  mOk := False;
  mWork :=
    procedure
    begin
      mWorkThread := TThread.CurrentThread.ThreadID;
    end;
  mFinish :=
    procedure(AOk: Boolean; const AError: string)
    begin
      mDoneThread := TThread.CurrentThread.ThreadID;
      mOk := AOk;
    end;
  mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
  try
    Assert.IsTrue(mRequest.Start(mWork, mFinish));
    Assert.IsTrue(mRequest.Busy);
    Assert.IsTrue(TTestWait.Synchronized(
      function: Boolean
      begin
        Result := mDoneThread <> 0;
      end));
    Assert.AreNotEqual<TThreadID>(MainThreadID, mWorkThread, 'Arbeit im Hintergrund');
    Assert.AreEqual<TThreadID>(MainThreadID, mDoneThread, 'Abschluss im Hauptthread');
    Assert.IsTrue(mOk);
    Assert.IsFalse(mRequest.Busy);
  finally
    mRequest.Free;
  end;
end;

procedure TAtlasBackgroundRequestTests.SecondStartIsRefusedWhileBusy;
var
  mRequest: TAtlasBackgroundRequest;
  mGate: TEvent;
  mProbe: TDoneProbe;
begin
  mProbe := nil;
  mGate := nil;
  mRequest := nil;
  try
    mProbe := TDoneProbe.Create;
    mGate := TEvent.Create(nil, True, False, '');
    mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
    Assert.IsTrue(mRequest.Start(Blocked(mGate), mProbe.Done()));
    Assert.IsFalse(mRequest.Start(Blocked(mGate), mProbe.Done()), 'zweite Anfrage solange die erste läuft');
    mGate.SetEvent;
    Assert.IsTrue(TTestWait.Synchronized(Reached(mProbe, 1)));
    Assert.IsTrue(mRequest.Start(Blocked(mGate), mProbe.Done()), 'nach dem Abschluss wieder frei');
    Assert.IsTrue(TTestWait.Synchronized(Reached(mProbe, 2)));
    Assert.AreEqual(2, Integer(mProbe.Count));
  finally
    mRequest.Free;
    mGate.Free;
    mProbe.Free;
  end;
end;

procedure TAtlasBackgroundRequestTests.DoneIsDroppedAfterFree;
var
  mRequest: TAtlasBackgroundRequest;
  mProbe: TDoneProbe;
  mWork: TProc;
begin
  mWork :=
    procedure
    begin
    end;
  mProbe := TDoneProbe.Create;
  try
    mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
    mRequest.Start(mWork, mProbe.Done());
    // Freigabe wartet die Arbeit ab; der eingereihte Abschluss darf danach nichts mehr tun.
    mRequest.Free;
    TTestWait.Synchronized(Reached(mProbe, 1), 200);
    Assert.AreEqual(0, Integer(mProbe.Count));
  finally
    mProbe.Free;
  end;
end;

procedure TAtlasBackgroundRequestTests.NoAnswerGivesErrorText;
var
  mRequest: TAtlasBackgroundRequest;
  mProbe: TDoneProbe;
begin
  mProbe := nil;
  mRequest := nil;
  try
    mProbe := TDoneProbe.Create;
    mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
    mRequest.Start(Raising(ELspTimeoutError.Create('Zeitlimit')), mProbe.Done());
    Assert.IsTrue(TTestWait.Synchronized(Reached(mProbe, 1)));
    Assert.IsFalse(mProbe.Ok);
    Assert.AreEqual('Zeitlimit', mProbe.Error);
    Assert.IsFalse(mRequest.Busy, 'nach fehlender Antwort wieder frei');
  finally
    mRequest.Free;
    mProbe.Free;
  end;
end;

procedure TAtlasBackgroundRequestTests.OtherExceptionStillFinishes;
var
  mRequest: TAtlasBackgroundRequest;
  mProbe: TDoneProbe;
begin
  mProbe := nil;
  mRequest := nil;
  try
    mProbe := TDoneProbe.Create;
    mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
    mRequest.Start(Raising(EAbort.Create('Abbruch')), mProbe.Done());
    Assert.IsTrue(TTestWait.Synchronized(Reached(mProbe, 1)));
    Assert.IsFalse(mProbe.Ok);
    Assert.IsFalse(mRequest.Busy, 'nach einer Ausnahme wieder frei');
  finally
    mRequest.Free;
    mProbe.Free;
  end;
end;

procedure TAtlasBackgroundRequestTests.ServerErrorIsReportedWithText;
var
  mRequest: TAtlasBackgroundRequest;
  mProbe: TDoneProbe;
  mReported: string;
  mOld: TProc<TAtlasFeature>;
begin
  mProbe := nil;
  mRequest := nil;
  mReported := '';
  mOld := TAtlasGuard.OnFailure;
  try
    TAtlasGuard.OnFailure :=
      procedure(AFeature: TAtlasFeature)
      begin
        mReported := 'gemeldet';
      end;
    mProbe := TDoneProbe.Create;
    mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
    mRequest.Start(Raising(ELspResponseError.CreateCode('kaputt', -32603)), mProbe.Done());
    Assert.IsTrue(TTestWait.Synchronized(Reached(mProbe, 1)));
    Assert.IsFalse(mProbe.Ok);
    Assert.AreEqual('kaputt', mProbe.Error, 'der Aufrufer bekommt die Meldung');
    Assert.AreEqual('gemeldet', mReported, 'ein Fehler im Server geht ins Fehlerprotokoll');
    Assert.IsFalse(mRequest.Busy);
  finally
    TAtlasGuard.OnFailure := mOld;
    // Der gemeldete Fehler bleibt sonst als Zeitpunkt in der Sicherung von Outline stehen (Leckmonitor).
    TAtlasGuard.Enable(TAtlasFeature.Outline);
    mRequest.Free;
    mProbe.Free;
  end;
end;

procedure TAtlasBackgroundRequestTests.QueueRunsJobsInOrder;
var
  mQueue: TAtlasBackgroundQueue;
  mGate: TEvent;
  mProbe: TOrderProbe;
begin
  mProbe := nil;
  mGate := nil;
  mQueue := nil;
  try
    mProbe := TOrderProbe.Create;
    mGate := TEvent.Create(nil, True, False, '');
    mQueue := TAtlasBackgroundQueue.Create(TAtlasFeature.Results);
    mQueue.Add(Blocked(mGate), mProbe.Done('A'));
    mQueue.Add(Blocked(mGate), mProbe.Done('B'));
    mQueue.Add(Blocked(mGate), mProbe.Done('C'));
    Assert.AreEqual(2, mQueue.Waiting, 'einer läuft, zwei warten');
    mGate.SetEvent;
    Assert.IsTrue(TTestWait.Synchronized(Drained(mQueue, mProbe, 3)));
    Assert.AreEqual('ABC', mProbe.Log);
  finally
    mQueue.Free;
    mGate.Free;
    if mProbe <> nil then
    begin
      mProbe.Log := '';
    end;
    mProbe.Free;
  end;
end;

procedure TAtlasBackgroundRequestTests.QueueKeepsOnlyLatestCommand;
var
  mQueue: TAtlasBackgroundQueue;
  mGate: TEvent;
  mProbe: TOrderProbe;
begin
  mProbe := nil;
  mGate := nil;
  mQueue := nil;
  try
    mProbe := TOrderProbe.Create;
    mGate := TEvent.Create(nil, True, False, '');
    mQueue := TAtlasBackgroundQueue.Create(TAtlasFeature.Results);
    // A läuft, B wartet; C ersetzt B, und das Ergebnis von A verfällt. Ein Aufklappen (Add) bleibt erhalten.
    mQueue.AddLatest(Blocked(mGate), mProbe.Done('A'));
    mQueue.AddLatest(Blocked(mGate), mProbe.Done('B'));
    mQueue.Add(Blocked(mGate), mProbe.Done('x'));
    mQueue.AddLatest(Blocked(mGate), mProbe.Done('C'));
    Assert.AreEqual(2, mQueue.Waiting, 'B ersetzt');
    mGate.SetEvent;
    Assert.IsTrue(TTestWait.Synchronized(Drained(mQueue, mProbe, 2)));
    // Nach C läuft nichts mehr; ein später Abschluss von A käme hier zu spät.
    TTestWait.Synchronized(Drained(mQueue, mProbe, 3), 200);
    Assert.AreEqual('xC', mProbe.Log);
  finally
    mQueue.Free;
    mGate.Free;
    if mProbe <> nil then
    begin
      mProbe.Log := '';
    end;
    mProbe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBackgroundRequestTests);

end.
