unit Atlas.Common.Diagnostics.StackGuard.Tests;

// Tests für TStackGuard (#1094): Nach einem abgefangenen Stapelüberlauf ruft
// AfterError die Wiederherstellung der Plattform, sonst nicht.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStackGuardTests = class
  public
    [TearDown]
    procedure RestoreNothing;
    [Test]
    procedure OverflowCallsRestore;
    [Test]
    procedure OtherErrorsLeaveGuardAlone;
    [Test]
    procedure WithoutRestoreNothingHappens;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Diagnostics.StackGuard;

type
  /// <summary>Gleichnamig zur veralteten RTL-Klasse (W1000): IsOverflow erkennt den Überlauf am Namen.</summary>
  EStackOverflow = class(Exception);

procedure TStackGuardTests.RestoreNothing;
begin
  TStackGuard.Restore := nil;
end;

procedure TStackGuardTests.OverflowCallsRestore;
var
  mCalls, mBefore: Integer;
  mError: Exception;
begin
  mCalls := 0;
  TStackGuard.Restore :=
    procedure
    begin
      Inc(mCalls);
    end;
  mBefore := TStackGuard.Restored;
  mError := EStackOverflow.Create('Stapel');
  try
    Assert.IsTrue(TStackGuard.IsOverflow(mError));
    TStackGuard.AfterError(mError);
  finally
    mError.Free;
  end;
  Assert.AreEqual(1, mCalls);
  Assert.AreEqual(mBefore + 1, TStackGuard.Restored);
end;

procedure TStackGuardTests.OtherErrorsLeaveGuardAlone;
var
  mCalls: Integer;
  mError: Exception;
begin
  mCalls := 0;
  TStackGuard.Restore :=
    procedure
    begin
      Inc(mCalls);
    end;
  mError := EArgumentException.Create('anders');
  try
    Assert.IsFalse(TStackGuard.IsOverflow(mError));
    TStackGuard.AfterError(mError);
  finally
    mError.Free;
  end;
  TStackGuard.AfterError(nil);
  Assert.AreEqual(0, mCalls);
end;

procedure TStackGuardTests.WithoutRestoreNothingHappens;
var
  mBefore: Integer;
  mError: Exception;
begin
  mBefore := TStackGuard.Restored;
  mError := EStackOverflow.Create('Stapel');
  try
    TStackGuard.AfterError(mError);
  finally
    mError.Free;
  end;
  Assert.AreEqual(mBefore, TStackGuard.Restored);
end;

initialization
  TDUnitX.RegisterTestFixture(TStackGuardTests);

end.
