unit Atlas.Windows.Diagnostics.StackTrace.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TStackTraceTests = class
  public
    /// <summary>Der erste Stapel-Abzug liest die Map-Datei einmal für die ganze Sitzung (#282).</summary>
    [SetupFixture]
    procedure WarmUp;
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
  Atlas.Windows.Diagnostics.StackTrace;

procedure RaiseSomething;
begin
  raise EAbort.Create('Test');
end;

{ TStackTraceTests }

procedure TStackTraceTests.WarmUp;
var
  mTrace: string;
begin
  mTrace := '';
  TStackTrace.Install;
  try
    try
      RaiseSomething;
    except
      on E: EAbort do
        mTrace := E.StackTrace;
    end;
  finally
    TStackTrace.Uninstall;
  end;
  if mTrace = '' then
  begin
    Exit;
  end;
end;

procedure TStackTraceTests.TearDown;
begin
  TStackTrace.Uninstall;
end;

procedure TStackTraceTests.ExceptionsCarryStackTraceAfterInstall;
var
  mTrace: string;
  mExeName: string;
begin
  TStackTrace.Install;
  Assert.IsTrue(TStackTrace.Installed);
  mTrace := '';
  try
    RaiseSomething;
  except
    on E: EAbort do
      mTrace := E.StackTrace;
  end;
  mExeName := ExtractFileName(ParamStr(0));
  Assert.IsTrue(mTrace.Contains(mExeName + '+$'), mTrace);
end;

procedure TStackTraceTests.UninstallRestoresPreviousState;
var
  mPrevious: Pointer;
begin
  mPrevious := @Exception.GetStackInfoStringProc;
  TStackTrace.Install;
  Assert.AreNotEqual<Pointer>(mPrevious, @Exception.GetStackInfoStringProc);
  TStackTrace.Uninstall;
  Assert.IsFalse(TStackTrace.Installed);
  Assert.AreEqual<Pointer>(mPrevious, @Exception.GetStackInfoStringProc);
end;

procedure TStackTraceTests.DescribesAddressAsModuleAndOffset;
begin
  Assert.IsTrue(TStackTrace.DescribeAddress(@RaiseSomething).StartsWith(ExtractFileName(ParamStr(0)) + '+$'));
  Assert.IsTrue(TStackTrace.Current.Contains(ExtractFileName(ParamStr(0))));
end;

procedure TStackTraceTests.MapFileNamesUnitAndRoutine;
var
  mTrace: string;
begin
  // Künstlicher Absturz (#282): Die .map neben der Test-EXE (DCC_MapFile=3) löst die Adressen auf.
  Assert.IsTrue(FileExists(ChangeFileExt(ParamStr(0), '.map')), 'Map-Datei fehlt neben der Test-EXE');
  TStackTrace.Install;
  mTrace := '';
  try
    RaiseSomething;
  except
    on E: EAbort do
      mTrace := E.StackTrace;
  end;
  Assert.IsTrue(mTrace.Contains('Atlas.Windows.Diagnostics.StackTrace.Tests.RaiseSomething'), mTrace);
  Assert.IsTrue(mTrace.Contains('Atlas.Windows.Diagnostics.StackTrace.Tests.pas:'), mTrace);
end;

initialization
  TDUnitX.RegisterTestFixture(TStackTraceTests);

end.
