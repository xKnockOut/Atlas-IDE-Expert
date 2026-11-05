unit Atlas.Core.Lsp.BackgroundRequest.Tests;

// Tests für Serveranfragen im Hintergrund (2.0-stable: Inlay-Hints, Glühbirne, Überschreibungen und Gliederung
// warteten im Hauptthread): Abschluss im Hauptthread, höchstens eine Anfrage, verworfener Abschluss nach Freigabe.

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
    procedure DoneRunsEvenIfWorkRaises;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Lsp.BackgroundRequest;

/// <summary>Arbeitet eingereihte Aufrufe ab, bis ACondition gilt oder die Zeit um ist.</summary>
function WaitUntil(const ACondition: TFunc<Boolean>; ATimeoutMs: Cardinal = 3000): Boolean;
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

/// <summary>Arbeit, die bis zum Signal wartet.</summary>
function Blocked(AGate: TEvent): TProc;
begin
  Result :=
    procedure
    begin
      AGate.WaitFor(5000);
    end;
end;

{ TAtlasBackgroundRequestTests }

procedure TAtlasBackgroundRequestTests.DoneRunsInMainThreadAfterWork;
var
  mRequest: TAtlasBackgroundRequest;
  mWorkThread: TThreadID;
  mDoneThread: TThreadID;
  mDone: Boolean;
  mWork: TProc;
  mFinish: TProc;
begin
  mWorkThread := 0;
  mDoneThread := 0;
  mDone := False;
  mWork :=
    procedure
    begin
      mWorkThread := TThread.CurrentThread.ThreadID;
    end;
  mFinish :=
    procedure
    begin
      mDoneThread := TThread.CurrentThread.ThreadID;
      mDone := True;
    end;
  mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
  try
    Assert.IsTrue(mRequest.Start(mWork, mFinish));
    Assert.IsTrue(mRequest.Busy);
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := mDone;
      end));
    Assert.IsTrue(mWorkThread <> MainThreadID, 'Arbeit im Hintergrund');
    Assert.IsTrue(mDoneThread = MainThreadID, 'Abschluss im Hauptthread');
    Assert.IsFalse(mRequest.Busy);
  finally
    mRequest.Free;
  end;
end;

procedure TAtlasBackgroundRequestTests.SecondStartIsRefusedWhileBusy;
var
  mRequest: TAtlasBackgroundRequest;
  mGate: TEvent;
  mDone: Integer;
  mFinish: TProc;
begin
  mDone := 0;
  mFinish :=
    procedure
    begin
      Inc(mDone);
    end;
  mGate := TEvent.Create(nil, True, False, '');
  mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
  try
    Assert.IsTrue(mRequest.Start(Blocked(mGate), mFinish));
    Assert.IsFalse(mRequest.Start(Blocked(mGate), mFinish), 'zweite Anfrage solange die erste läuft');
    mGate.SetEvent;
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := mDone = 1;
      end));
    Assert.IsTrue(mRequest.Start(Blocked(mGate), mFinish), 'nach dem Abschluss wieder frei');
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := mDone = 2;
      end));
  finally
    mRequest.Free;
    mGate.Free;
  end;
end;

procedure TAtlasBackgroundRequestTests.DoneIsDroppedAfterFree;
var
  mRequest: TAtlasBackgroundRequest;
  mDone: Boolean;
  mWork: TProc;
  mFinish: TProc;
begin
  mDone := False;
  mWork :=
    procedure
    begin
    end;
  mFinish :=
    procedure
    begin
      mDone := True;
    end;
  mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
  mRequest.Start(mWork, mFinish);
  // Freigabe wartet die Arbeit ab; der eingereihte Abschluss darf danach nichts mehr tun.
  mRequest.Free;
  WaitUntil(
    function: Boolean
    begin
      Result := mDone;
    end, 200);
  Assert.IsFalse(mDone);
end;

procedure TAtlasBackgroundRequestTests.DoneRunsEvenIfWorkRaises;
var
  mRequest: TAtlasBackgroundRequest;
  mDone: Boolean;
  mWork: TProc;
  mFinish: TProc;
begin
  mDone := False;
  mWork :=
    procedure
    begin
      raise EAbort.Create('Abbruch');
    end;
  mFinish :=
    procedure
    begin
      mDone := True;
    end;
  mRequest := TAtlasBackgroundRequest.Create(TAtlasFeature.Outline);
  try
    mRequest.Start(mWork, mFinish);
    Assert.IsTrue(WaitUntil(
      function: Boolean
      begin
        Result := mDone;
      end));
    Assert.IsFalse(mRequest.Busy, 'nach einer Ausnahme wieder frei');
  finally
    mRequest.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBackgroundRequestTests);

end.
