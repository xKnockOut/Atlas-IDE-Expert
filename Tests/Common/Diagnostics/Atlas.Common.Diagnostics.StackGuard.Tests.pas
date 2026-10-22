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
  Calls, Before: Integer;
  Error: Exception;
begin
  Calls := 0;
  TStackGuard.Restore :=
    procedure
    begin
      Inc(Calls);
    end;
  Before := TStackGuard.Restored;
  Error := EStackOverflow.Create('Stapel');
  try
    Assert.IsTrue(TStackGuard.IsOverflow(Error));
    TStackGuard.AfterError(Error);
  finally
    Error.Free;
  end;
  Assert.AreEqual(1, Calls);
  Assert.AreEqual(Before + 1, TStackGuard.Restored);
end;

procedure TStackGuardTests.OtherErrorsLeaveGuardAlone;
var
  Calls: Integer;
  Error: Exception;
begin
  Calls := 0;
  TStackGuard.Restore :=
    procedure
    begin
      Inc(Calls);
    end;
  Error := EArgumentException.Create('anders');
  try
    Assert.IsFalse(TStackGuard.IsOverflow(Error));
    TStackGuard.AfterError(Error);
  finally
    Error.Free;
  end;
  TStackGuard.AfterError(nil);
  Assert.AreEqual(0, Calls);
end;

procedure TStackGuardTests.WithoutRestoreNothingHappens;
var
  Before: Integer;
  Error: Exception;
begin
  Before := TStackGuard.Restored;
  Error := EStackOverflow.Create('Stapel');
  try
    TStackGuard.AfterError(Error);
  finally
    Error.Free;
  end;
  Assert.AreEqual(Before, TStackGuard.Restored);
end;

initialization
  TDUnitX.RegisterTestFixture(TStackGuardTests);

end.
