unit Argus.Windows.Diagnostics.StackTrace.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStackTraceTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ExceptionsCarryStackTraceAfterInstall;
    [Test]
    procedure UninstallRestoresPreviousState;
    [Test]
    procedure DescribesAddressAsModuleAndOffset;
    [Test]
    procedure MapFileNamesUnitAndRoutine;
  end;

implementation

uses
  System.SysUtils,
  Argus.Windows.Diagnostics.StackTrace;

procedure RaiseSomething;
begin
  raise EAbort.Create('Test');
end;

{ TStackTraceTests }

procedure TStackTraceTests.TearDown;
begin
  TStackTrace.Uninstall;
end;

procedure TStackTraceTests.ExceptionsCarryStackTraceAfterInstall;
var
  Trace: string;
  ExeName: string;
begin
  TStackTrace.Install;
  Assert.IsTrue(TStackTrace.Installed);
  Trace := '';
  try
    RaiseSomething;
  except
    on E: EAbort do
      Trace := E.StackTrace;
  end;
  ExeName := ExtractFileName(ParamStr(0));
  Assert.IsTrue(Trace.Contains(ExeName + '+$'), Trace);
end;

procedure TStackTraceTests.UninstallRestoresPreviousState;
var
  Previous: Pointer;
begin
  Previous := @Exception.GetStackInfoStringProc;
  TStackTrace.Install;
  Assert.IsTrue(@Exception.GetStackInfoStringProc <> Previous);
  TStackTrace.Uninstall;
  Assert.IsFalse(TStackTrace.Installed);
  Assert.IsTrue(@Exception.GetStackInfoStringProc = Previous);
end;

procedure TStackTraceTests.DescribesAddressAsModuleAndOffset;
begin
  Assert.IsTrue(TStackTrace.DescribeAddress(@RaiseSomething).StartsWith(ExtractFileName(ParamStr(0)) + '+$'));
  Assert.IsTrue(TStackTrace.Current.Contains(ExtractFileName(ParamStr(0))));
end;

procedure TStackTraceTests.MapFileNamesUnitAndRoutine;
var
  Trace: string;
begin
  // Künstlicher Absturz (#282): Die .map neben der Test-EXE (DCC_MapFile=3) löst die Adressen auf.
  Assert.IsTrue(FileExists(ChangeFileExt(ParamStr(0), '.map')), 'Map-Datei fehlt neben der Test-EXE');
  TStackTrace.Install;
  Trace := '';
  try
    RaiseSomething;
  except
    on E: EAbort do
      Trace := E.StackTrace;
  end;
  Assert.IsTrue(Trace.Contains('Argus.Windows.Diagnostics.StackTrace.Tests.RaiseSomething'), Trace);
  Assert.IsTrue(Trace.Contains('Argus.Windows.Diagnostics.StackTrace.Tests.pas:'), Trace);
end;

initialization
  TDUnitX.RegisterTestFixture(TStackTraceTests);

end.
