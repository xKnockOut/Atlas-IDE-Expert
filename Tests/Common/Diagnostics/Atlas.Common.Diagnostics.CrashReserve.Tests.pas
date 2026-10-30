unit Atlas.Common.Diagnostics.CrashReserve.Tests;

// Tests für TCrashReserve (#1355): Arbeit im reservierten Thread, Fehler und
// Zeitlimit kommen beim Aufrufer an.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCrashReserveTests = class
  public
    [Test]
    procedure RunsWorkInOtherThread;
    [Test]
    procedure ReportsFailure;
    [Test]
    procedure RunsAgainAfterFailure;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Diagnostics.CrashReserve;

procedure TCrashReserveTests.RunsWorkInOtherThread;
var
  mReserve: TCrashReserve;
  mThread: TThreadID;
  mFailure: string;
begin
  mThread := 0;
  mReserve := TCrashReserve.Create;
  try
    Assert.IsTrue(mReserve.Run(
      procedure
      begin
        mThread := TThread.CurrentThread.ThreadID;
      end, mFailure), mFailure);
  finally
    mReserve.Free;
  end;
  Assert.IsTrue(TThread.CurrentThread.ThreadID <> mThread);
  Assert.AreEqual('', mFailure);
end;

procedure TCrashReserveTests.ReportsFailure;
var
  mReserve: TCrashReserve;
  mFailure: string;
begin
  mReserve := TCrashReserve.Create;
  try
    Assert.IsFalse(mReserve.Run(
      procedure
      begin
        raise EInOutError.Create('Platte voll');
      end, mFailure));
  finally
    mReserve.Free;
  end;
  Assert.AreEqual('EInOutError: Platte voll', mFailure);
end;

procedure TCrashReserveTests.RunsAgainAfterFailure;
var
  mReserve: TCrashReserve;
  mFailure: string;
  mCalls: Integer;
begin
  mCalls := 0;
  mReserve := TCrashReserve.Create;
  try
    mReserve.Run(
      procedure
      begin
        raise Exception.Create('erst');
      end, mFailure);
    Assert.IsTrue(mReserve.Run(
      procedure
      begin
        Inc(mCalls);
      end, mFailure), mFailure);
  finally
    mReserve.Free;
  end;
  Assert.AreEqual(1, mCalls);
end;

initialization
  TDUnitX.RegisterTestFixture(TCrashReserveTests);

end.
