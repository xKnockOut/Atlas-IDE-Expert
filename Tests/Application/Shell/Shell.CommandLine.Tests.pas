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
    procedure ReadsClientProcessId;
    [Test]
    procedure WarnsAboutInvalidClientProcessId;
    [Test]
    procedure WarnsAboutInvalidLogLevel;
    [Test]
    procedure WarnsAboutMissingValue;
    [Test]
    procedure ReadsLinterArguments;
    [Test]
    procedure ReadsMcpArguments;
    [Test]
    procedure ReadsRestricted;
    [Test]
    procedure ReadsProfile;
    [Test]
    procedure WarnsAboutInvalidLinterValues;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Logging.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Rules.Output,
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

procedure TCommandLineOptionsTests.ReadsClientProcessId;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--stdio', '--clientProcessId=1234']);
  Assert.AreEqual(Cardinal(1234), Options.ClientProcessId);
  Options := TCommandLineOptions.Parse(['--clientProcessId', '99']);
  Assert.AreEqual(Cardinal(99), Options.ClientProcessId);
end;

procedure TCommandLineOptionsTests.WarnsAboutInvalidClientProcessId;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--clientProcessId=abc']);
  Assert.AreEqual(Cardinal(0), Options.ClientProcessId);
  Assert.AreEqual<NativeInt>(1, Length(Options.Warnings));
  Assert.Contains(Options.Warnings[0], 'abc');
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

procedure TCommandLineOptionsTests.ReadsLinterArguments;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--check', 'App.dproj', '--format=sarif', '--output', 'out.sarif',
    '--rules', 'syntax, empty-except', '--units=Main,Legacy/**', '--min-severity', 'warning', '--suppression-stats',
    '--baseline', 'alt.json', '--update-baseline', '--clear-cache']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.AreEqual('App.dproj', Options.CheckTarget);
  Assert.AreEqual(Ord(TFindingsFormat.Sarif), Ord(Options.CheckFormat));
  Assert.AreEqual('out.sarif', Options.OutputFile);
  Assert.AreEqual(2, Integer(Length(Options.RuleFilter)));
  Assert.AreEqual('empty-except', Options.RuleFilter[1]);
  Assert.AreEqual('Legacy/**', Options.UnitFilter[1]);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Options.MinSeverity));
  Assert.IsTrue(Options.SuppressionStats);
  Assert.AreEqual('alt.json', Options.BaselineFile);
  Assert.IsTrue(Options.UpdateBaseline);
  Assert.IsTrue(Options.ClearCache);
end;

procedure TCommandLineOptionsTests.ReadsMcpArguments;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--mcp', '--root', 'C:\Projekte\App']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.IsTrue(Options.Mcp);
  Assert.AreEqual('C:\Projekte\App', Options.McpRoot);
  Assert.IsFalse(TCommandLineOptions.Parse([]).Mcp);
end;

procedure TCommandLineOptionsTests.ReadsProfile;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--check', 'App.dproj', '--profile', 'strict']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.AreEqual('strict', Options.Profile);
  Assert.AreEqual('', TCommandLineOptions.Parse([]).Profile);
end;

procedure TCommandLineOptionsTests.ReadsRestricted;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--stdio', '--restricted']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.IsTrue(Options.Restricted);
  Assert.IsFalse(TCommandLineOptions.Parse([]).Restricted);
end;

procedure TCommandLineOptionsTests.WarnsAboutInvalidLinterValues;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--format', 'xml', '--min-severity', 'off']);
  Assert.AreEqual(2, Integer(Length(Options.Warnings)));
  Assert.AreEqual(Ord(TFindingsFormat.Text), Ord(Options.CheckFormat));
  Assert.AreEqual(Ord(TRuleSeverity.Default), Ord(Options.MinSeverity));
  Assert.AreEqual('', Options.CheckTarget);
end;

initialization
  TDUnitX.RegisterTestFixture(TCommandLineOptionsTests);

end.
