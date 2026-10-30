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
    procedure AcceptsSingleAndTypographicDashes;
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
    /// <summary>#1356: --timings mit und ohne Datei, unabhängig vom Regelprofil --profile.</summary>
    [Test]
    procedure ReadsTimings;
    [Test]
    procedure WarnsAboutInvalidLinterValues;
    [Test]
    procedure ReadsChangedArguments;
    [Test]
    procedure ReadsAffectedTestsArguments;
    [Test]
    procedure ReadsFailOnAndSourceRoot;
    /// <summary>Alle Text- und Schalterparameter der Tabelle (S-02), auch mit Großbuchstaben.</summary>
    [Test]
    procedure ReadsTableOptions;
    /// <summary>#1355: --replay nennt anfrage.json eines Absturzfalls.</summary>
    [Test]
    procedure ReadsReplayFile;
    /// <summary>#1352: Sammelkorrektur.</summary>
    [Test]
    procedure ReadsFixArguments;
    /// <summary>#1358: --format-check, --format-write und --format diff.</summary>
    [Test]
    procedure ReadsFormatterArguments;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Output,
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
  Assert.IsFalse(Options.LogNames, 'anonym ist Vorgabe');
  Options := TCommandLineOptions.Parse(['--log-names']);
  Assert.IsTrue(Options.LogNames);
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

procedure TCommandLineOptionsTests.AcceptsSingleAndTypographicDashes;
var
  Options: TCommandLineOptions;
begin
  // So stand es in der Registry: Gedankenstrich statt "--" (#647).
  Options := TCommandLineOptions.Parse([#$2013'log', 'C:\Temp\atlas-server.log', '-log-level', 'debug']);
  Assert.AreEqual<NativeInt>(0, Length(Options.Warnings));
  Assert.AreEqual('C:\Temp\atlas-server.log', Options.LogFile);
  Assert.IsTrue(Options.LogLevel = TLogLevel.Debug);
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
  Assert.IsFalse(Options.Metrics);
  Options := TCommandLineOptions.Parse(['--check', 'App.dproj', '--metrics', '--format', 'json']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.IsTrue(Options.Metrics, '--metrics (#66)');
  Assert.AreEqual(Ord(TFindingsFormat.Json), Ord(Options.CheckFormat));
  Assert.IsFalse(Options.Todos);
  Options := TCommandLineOptions.Parse(['--check', 'App.dproj', '--todos']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.IsTrue(Options.Todos, '--todos (#68)');
  // Symbolindex (#1112): Standard mit Index und dem Cache des Servers.
  Assert.IsFalse(Options.NoIndex);
  Assert.AreEqual('', Options.IndexCacheFolder);
  Options := TCommandLineOptions.Parse(['--check', 'App.dproj', '--no-index', '--index-cache', 'C:\Cache']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.IsTrue(Options.NoIndex, '--no-index (#1112)');
  Assert.AreEqual('C:\Cache', Options.IndexCacheFolder);
  Assert.AreEqual('', Options.ArchitectureFile);
  Options := TCommandLineOptions.Parse(['--architecture=Bericht.html']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.AreEqual('Bericht.html', Options.ArchitectureFile, '--architecture (#1118)');
  Assert.AreEqual('', Options.HotspotsFile);
  Options := TCommandLineOptions.Parse(['--check', 'App.dproj', '--hotspots', 'hotspots.html']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.AreEqual('hotspots.html', Options.HotspotsFile, '--hotspots (#1354)');
  Assert.AreEqual('App.dproj', Options.CheckTarget);
  Options := TCommandLineOptions.Parse(['--architecture=Bericht.html']);
  Assert.AreEqual('', Options.CheckTarget);
  // Vergleich (#1121): Abweichungsarten bei --fail-on ohne Warnung, der Wert bleibt für den Bericht.
  Options := TCommandLineOptions.Parse(['--architecture', 'neu.json', '--compare', 'alt.json', '--fail-on',
    'newCycle,centralGrowth']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.AreEqual('alt.json', Options.CompareFile);
  Assert.AreEqual('newCycle,centralGrowth', Options.FailOnText);
  Options := TCommandLineOptions.Parse(['--fail-on', 'irgendwas']);
  Assert.AreEqual(1, Integer(Length(Options.Warnings)));
end;

procedure TCommandLineOptionsTests.ReadsFailOnAndSourceRoot;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--check', 'App\App.dproj', '--fail-on', 'warning', '--source-root=C:\Repo']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.AreEqual(Ord(TFailOn.Warning), Ord(Options.FailOn));
  Assert.AreEqual('C:\Repo', Options.SourceRoot);
  Options := TCommandLineOptions.Parse(['--check', 'App.dproj']);
  Assert.AreEqual(Ord(TFailOn.Error), Ord(Options.FailOn), 'Standard: nur Fehler');
  Assert.AreEqual('', Options.SourceRoot);
  Options := TCommandLineOptions.Parse(['--fail-on=never']);
  Assert.AreEqual(Ord(TFailOn.Never), Ord(Options.FailOn));
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

procedure TCommandLineOptionsTests.ReadsChangedArguments;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--check', 'App.dproj', '--changed', '--changed-lines']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.AreEqual('main', Options.ChangedRef);
  Assert.IsTrue(Options.ChangedMergeBase);
  Assert.IsTrue(Options.ChangedLines);
  Assert.IsFalse(Options.IncludeUncommitted);
  Options := TCommandLineOptions.Parse(['--changed', 'develop', '--check', 'App.dproj']);
  Assert.AreEqual('develop', Options.ChangedRef);
  Assert.AreEqual('App.dproj', Options.CheckTarget);
  Options := TCommandLineOptions.Parse(['--diff=HEAD~3', '--include-uncommitted']);
  Assert.AreEqual('HEAD~3', Options.ChangedRef);
  Assert.IsFalse(Options.ChangedMergeBase);
  Assert.IsTrue(Options.IncludeUncommitted);
  Options := TCommandLineOptions.Parse(['--check', 'App.dproj']);
  Assert.AreEqual('', Options.ChangedRef);
end;

procedure TCommandLineOptionsTests.ReadsAffectedTestsArguments;
var
  mOptions: TCommandLineOptions;
begin
  // #1353: Basis optional wie bei --changed; dunitx ist nur hier ein Format, ohne Warnung.
  mOptions := TCommandLineOptions.Parse(['--check', 'Tests.dproj', '--affected-tests', '--format', 'dunitx']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.IsTrue(mOptions.AffectedTests);
  Assert.AreEqual('', mOptions.AffectedBase);
  Assert.AreEqual('dunitx', mOptions.FormatText);
  mOptions := TCommandLineOptions.Parse(['--affected-tests', 'develop', '--check', 'Tests.dproj']);
  Assert.AreEqual('develop', mOptions.AffectedBase);
  Assert.AreEqual('Tests.dproj', mOptions.CheckTarget);
  mOptions := TCommandLineOptions.Parse(['--affected-tests=HEAD', '--include-uncommitted', '--check', 'T.dproj']);
  Assert.AreEqual('HEAD', mOptions.AffectedBase);
  Assert.IsTrue(mOptions.IncludeUncommitted);
  // --include-uncommitted gehört hier zu --affected-tests, nicht zu --changed.
  Assert.AreEqual('', mOptions.ChangedRef);
end;

procedure TCommandLineOptionsTests.ReadsTimings;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--timings']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.IsTrue(mOptions.Timings);
  Assert.AreEqual('', mOptions.TimingsFile);
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--timings', 'profil.md', '--profile', 'strict']);
  Assert.AreEqual('profil.md', mOptions.TimingsFile);
  Assert.AreEqual('strict', mOptions.Profile);
  mOptions := TCommandLineOptions.Parse(['--timings=profil.json', '--check', 'App.dproj']);
  Assert.AreEqual('profil.json', mOptions.TimingsFile);
  Assert.AreEqual('App.dproj', mOptions.CheckTarget);
  mOptions := TCommandLineOptions.Parse(['--timings', '--check', 'App.dproj']);
  Assert.IsTrue(mOptions.Timings);
  Assert.AreEqual('', mOptions.TimingsFile);
  Assert.AreEqual('App.dproj', mOptions.CheckTarget);
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj']);
  Assert.IsFalse(mOptions.Timings);
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
  Options := TCommandLineOptions.Parse(['--format', 'xml', '--min-severity', 'off', '--fail-on', 'hint']);
  Assert.AreEqual(3, Integer(Length(Options.Warnings)));
  Assert.AreEqual(Ord(TFailOn.Error), Ord(Options.FailOn));
  Assert.AreEqual(Ord(TFindingsFormat.Text), Ord(Options.CheckFormat));
  Assert.AreEqual(Ord(TRuleSeverity.Default), Ord(Options.MinSeverity));
  Assert.AreEqual('', Options.CheckTarget);
end;

procedure TCommandLineOptionsTests.ReadsTableOptions;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--trace=t.json', '--OUTPUT', 'o.txt', '--baseline', 'b.json', '--root=R',
    '--log-names', '--clear-cache', '--include-uncommitted', '--changed-lines', '--update-baseline',
    '--suppression-stats', '--metrics', '--todos']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.AreEqual('t.json', Options.TraceFile);
  Assert.AreEqual('o.txt', Options.OutputFile);
  Assert.AreEqual('b.json', Options.BaselineFile);
  Assert.AreEqual('R', Options.McpRoot);
  Assert.IsTrue(Options.LogNames and Options.ClearCache and Options.IncludeUncommitted and Options.ChangedLines);
  Assert.IsTrue(Options.UpdateBaseline and Options.SuppressionStats and Options.Metrics and Options.Todos);
  Assert.IsFalse(Options.Mcp or Options.Restricted);
  // --include-uncommitted ohne Ref: Standardbasis.
  Assert.AreEqual(TCommandLineOptions.DefaultChangedBase, Options.ChangedRef);
end;

procedure TCommandLineOptionsTests.ReadsReplayFile;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--replay', 'C:\Fall\anfrage.json']);
  Assert.AreEqual('C:\Fall\anfrage.json', Options.ReplayFile);
  Assert.AreEqual<NativeInt>(0, Length(Options.Warnings));
  Options := TCommandLineOptions.Parse(['--stdio']);
  Assert.AreEqual('', Options.ReplayFile);
end;

procedure TCommandLineOptionsTests.ReadsFixArguments;
var
  Options: TCommandLineOptions;
begin
  Options := TCommandLineOptions.Parse(['--check', 'App.dproj', '--fix', 'redundant-cast, unused-uses',
    '--fix-dry-run']);
  Assert.AreEqual(0, Integer(Length(Options.Warnings)));
  Assert.AreEqual('redundant-cast|unused-uses', string.Join('|', Options.FixRules));
  Assert.IsTrue(Options.FixDryRun);
  Options := TCommandLineOptions.Parse(['--check', 'App.dproj', '--fix=all']);
  Assert.AreEqual('all', string.Join('|', Options.FixRules));
  Assert.IsFalse(Options.FixDryRun);
  Assert.AreEqual(0, Integer(Length(TCommandLineOptions.Parse(['--check', 'App.dproj']).FixRules)));
  Options := TCommandLineOptions.Parse(['--check', 'App.dproj', '--fix', ',']);
  Assert.AreEqual(1, Integer(Length(Options.Warnings)));
end;

procedure TCommandLineOptionsTests.ReadsFormatterArguments;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--check', 'Src', '--format-check', '--format', 'diff', '--changed-lines']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.IsTrue(mOptions.FormatCheck);
  Assert.IsFalse(mOptions.FormatWrite);
  Assert.IsTrue(mOptions.FormatDiff);
  Assert.IsTrue(mOptions.ChangedLines);
  mOptions := TCommandLineOptions.Parse(['--check', 'Src', '--format-write', '--format=DIFF', '--format', 'json']);
  Assert.IsTrue(mOptions.FormatWrite);
  Assert.IsFalse(mOptions.FormatDiff);
  Assert.IsTrue(mOptions.CheckFormat = TFindingsFormat.Json);
  Assert.IsFalse(TCommandLineOptions.Parse([]).FormatCheck);
end;

initialization
  TDUnitX.RegisterTestFixture(TCommandLineOptionsTests);

end.
