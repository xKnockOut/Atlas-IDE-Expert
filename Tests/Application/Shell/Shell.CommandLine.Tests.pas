unit Shell.CommandLine.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCommandLineOptionsTests = class
  public
    [Test]
    procedure DefaultsWithoutArguments;
    [Test]
    procedure ReadsValuesSeparatedBySpace;
    [Test]
    procedure ReadsValuesWithEqualsSign;
    [Test]
    procedure IgnoresEditorArgumentsSilently;
    [Test]
    procedure WarnsAboutUnknownArgument;
    [Test]
    procedure WarnsAboutInvalidLogLevel;
    [Test]
    procedure WarnsAboutMissingValue;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Logging.Contract,
  Shell.CommandLine;

{ TCommandLineOptionsTests }

procedure TCommandLineOptionsTests.DefaultsWithoutArguments;
var
  NoArguments: TArray<string>;
  Options: TCommandLineOptions;
begin
  NoArguments := nil;
  Options := TCommandLineOptions.Parse(NoArguments);
  Assert.AreEqual('', Options.LogFile);
  Assert.AreEqual('', Options.TraceFile);
  Assert.IsTrue(Options.LogLevel = TLogLevel.Info);
  Assert.AreEqual<NativeInt>(0, Length(Options.Warnings));
end;

procedure TCommandLineOptionsTests.ReadsValuesSeparatedBySpace;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--log', 'C:\Logs\server.log', '--log-level', 'debug',
    '--trace', 'C:\Logs\trace.txt']);
  Assert.AreEqual('C:\Logs\server.log', Options.LogFile);
  Assert.AreEqual('C:\Logs\trace.txt', Options.TraceFile);
  Assert.IsTrue(Options.LogLevel = TLogLevel.Debug);
  Assert.AreEqual<NativeInt>(0, Length(Options.Warnings));
end;

procedure TCommandLineOptionsTests.ReadsValuesWithEqualsSign;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--log=server.log', '--log-level=WARNING']);
  Assert.AreEqual('server.log', Options.LogFile);
  Assert.IsTrue(Options.LogLevel = TLogLevel.Warning);
end;

procedure TCommandLineOptionsTests.IgnoresEditorArgumentsSilently;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--stdio', '--clientProcessId=4711']);
  Assert.AreEqual<NativeInt>(0, Length(Options.Warnings));
end;

procedure TCommandLineOptionsTests.WarnsAboutUnknownArgument;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--gibtsnicht']);
  Assert.AreEqual<NativeInt>(1, Length(Options.Warnings));
  Assert.Contains(Options.Warnings[0], '--gibtsnicht');
end;

procedure TCommandLineOptionsTests.WarnsAboutInvalidLogLevel;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--log-level', 'laut']);
  Assert.IsTrue(Options.LogLevel = TLogLevel.Info);
  Assert.AreEqual<NativeInt>(1, Length(Options.Warnings));
end;

procedure TCommandLineOptionsTests.WarnsAboutMissingValue;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--log']);
  Assert.AreEqual('', Options.LogFile);
  Assert.AreEqual<NativeInt>(1, Length(Options.Warnings));
end;

initialization
  TDUnitX.RegisterTestFixture(TCommandLineOptionsTests);

end.
