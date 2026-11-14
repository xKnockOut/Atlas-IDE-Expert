unit Atlas.Core.Lsp.BackgroundRequest.Tests;

// Tests für Serveranfragen im Hintergrund (2.0-stable: Inlay-Hints, Glühbirne, Überschreibungen und Gliederung
// warteten im Hauptthread): Abschluss im Hauptthread, höchstens eine Anfrage, verworfener Abschluss nach Freigabe,
// keine Antwort des Servers als AOk = False mit Meldung.

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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.BackgroundRequest;

/// <summary>Arbeitet eingereihte Aufrufe ab, bis ACondition gilt oder ATimeoutMs um sind.</summary>
function WaitWithin(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal): Boolean;
var
  mStart: UInt64;
begin
  mStart := TThread.GetTickCount64;
  repeat
    CheckSynchronize(5);
    if ACondition() then
    begin
      Exit(True);
    end;
  until TThread.GetTickCount64 - mStart > ATimeoutMs;
  Result := False;
end;

/// <summary>Wie WaitWithin mit der üblichen Wartezeit von drei Sekunden.</summary>
function WaitUntil(const ACondition: TFunc<Boolean>): Boolean;
const
  cTimeoutMs = 3000;
begin
  Result := WaitWithin(ACondition, cTimeoutMs);
end;

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
    Assert.IsTrue(WaitUntil(
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
  mProbe := TDoneProbe.Create;
  mGate := TEvent.Create(nil, True, False, '');
  mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
  try
    Assert.IsTrue(mRequest.Start(Blocked(mGate), mProbe.Done()));
    Assert.IsFalse(mRequest.Start(Blocked(mGate), mProbe.Done()), 'zweite Anfrage solange die erste läuft');
    mGate.SetEvent;
    Assert.IsTrue(WaitUntil(Reached(mProbe, 1)));
    Assert.IsTrue(mRequest.Start(Blocked(mGate), mProbe.Done()), 'nach dem Abschluss wieder frei');
    Assert.IsTrue(WaitUntil(Reached(mProbe, 2)));
    Assert.AreEqual(2, mProbe.Count);
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
    WaitWithin(Reached(mProbe, 1), 200);
    Assert.AreEqual(0, mProbe.Count);
  finally
    mProbe.Free;
  end;
end;

procedure TAtlasBackgroundRequestTests.NoAnswerGivesErrorText;
var
  mRequest: TAtlasBackgroundRequest;
  mProbe: TDoneProbe;
begin
  mProbe := TDoneProbe.Create;
  mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
  try
    mRequest.Start(Raising(ELspTimeoutError.Create('Zeitlimit')), mProbe.Done());
    Assert.IsTrue(WaitUntil(Reached(mProbe, 1)));
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
  mProbe := TDoneProbe.Create;
  mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
  try
    mRequest.Start(Raising(EAbort.Create('Abbruch')), mProbe.Done());
    Assert.IsTrue(WaitUntil(Reached(mProbe, 1)));
    Assert.IsFalse(mProbe.Ok);
    Assert.IsFalse(mRequest.Busy, 'nach einer Ausnahme wieder frei');
  finally
    mRequest.Free;
    mProbe.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBackgroundRequestTests);

end.
