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
    /// <summary>#1458: Der Hinweis entsteht erst bei der Ausgabe in der dann gültigen Sprache.</summary>
    [Test]
    procedure WarningTextFollowsLanguage;
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
    /// <summary>#1458: --locale de|en, sonst Warnung und keine Angabe.</summary>
    [Test]
    procedure ReadsLocale;
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
    /// <summary>Alle Text- und Schalterparameter der Tabelle, auch mit Großbuchstaben.</summary>
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
    /// <summary>#1901: Befehl des Laufs für die Statusdatei.</summary>
    [Test]
    procedure NamesRunCommand;
    /// <summary>#1900: AtlasMonitor bietet jeden Schalter an oder lässt ihn bewusst aus; keiner ist veraltet.
    /// </summary>
    [Test]
    procedure MonitorKnowsEverySwitch;
    /// <summary>#1900: Jeder Aufruf aus AtlasMonitor liest sich ohne Warnung und wählt den richtigen Befehl.</summary>
    [Test]
    procedure MonitorCallsParse;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Output,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Monitor.Commands,
  Shell.CommandLine;

{ TCommandLineOptionsTests }

procedure TCommandLineOptionsTests.DefaultsWithoutArguments;
var
  mNoArguments: TArray<string>;
  mOptions: TCommandLineOptions;
begin
  mNoArguments := nil;
  mOptions := TCommandLineOptions.Parse(mNoArguments);
  Assert.AreEqual('', mOptions.LogFile);
  Assert.AreEqual('', mOptions.TraceFile);
  Assert.AreEqual<TLogLevel>(TLogLevel.Info, mOptions.LogLevel);
  Assert.AreEqual<NativeInt>(0, Length(mOptions.Warnings));
end;

procedure TCommandLineOptionsTests.ReadsValuesSeparatedBySpace;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--log', 'C:\Logs\server.log', '--log-level', 'debug',
    '--trace', 'C:\Logs\trace.txt']);
  Assert.AreEqual('C:\Logs\server.log', mOptions.LogFile);
  Assert.AreEqual('C:\Logs\trace.txt', mOptions.TraceFile);
  Assert.AreEqual<TLogLevel>(TLogLevel.Debug, mOptions.LogLevel);
  Assert.IsFalse(mOptions.LogNames, 'anonym ist Vorgabe');
  mOptions := TCommandLineOptions.Parse(['--log-names']);
  Assert.IsTrue(mOptions.LogNames);
  Assert.AreEqual<NativeInt>(0, Length(mOptions.Warnings));
end;

procedure TCommandLineOptionsTests.ReadsValuesWithEqualsSign;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--log=server.log', '--log-level=WARNING']);
  Assert.AreEqual('server.log', mOptions.LogFile);
  Assert.AreEqual<TLogLevel>(TLogLevel.Warning, mOptions.LogLevel);
end;

procedure TCommandLineOptionsTests.IgnoresEditorArgumentsSilently;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--stdio', '--clientProcessId=4711']);
  Assert.AreEqual<NativeInt>(0, Length(mOptions.Warnings));
end;

procedure TCommandLineOptionsTests.ReadsClientProcessId;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--stdio', '--clientProcessId=1234']);
  Assert.AreEqual(Cardinal(1234), mOptions.ClientProcessId);
  mOptions := TCommandLineOptions.Parse(['--clientProcessId', '99']);
  Assert.AreEqual(Cardinal(99), mOptions.ClientProcessId);
end;

procedure TCommandLineOptionsTests.WarnsAboutInvalidClientProcessId;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--clientProcessId=abc']);
  Assert.AreEqual(Cardinal(0), mOptions.ClientProcessId);
  Assert.AreEqual<NativeInt>(1, Length(mOptions.Warnings));
  Assert.Contains(mOptions.Warnings[0].Text, 'abc');
end;

procedure TCommandLineOptionsTests.WarnsAboutUnknownArgument;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--gibtsnicht']);
  Assert.AreEqual<NativeInt>(1, Length(mOptions.Warnings));
  Assert.Contains(mOptions.Warnings[0].Text, '--gibtsnicht');
end;

procedure TCommandLineOptionsTests.WarningTextFollowsLanguage;
var
  mOptions: TCommandLineOptions;
  mSaved: TTextLanguage;
begin
  mSaved := TAtlasLocale.Language;
  try
    mOptions := TCommandLineOptions.Parse(['--gibtsnicht', '--log-level', 'laut']);
    Assert.AreEqual<NativeInt>(2, Length(mOptions.Warnings));
    Assert.AreEqual<TCommandLineWarningKind>(TCommandLineWarningKind.UnknownParameter, mOptions.Warnings[0].Kind);
    TAtlasLocale.Use(TTextLanguage.English);
    Assert.AreEqual('Unknown parameter "--gibtsnicht" is ignored', mOptions.Warnings[0].Text);
    Assert.AreEqual('Unknown log level "laut", using info', mOptions.Warnings[1].Text);
    TAtlasLocale.Use(TTextLanguage.German);
    Assert.AreEqual('Unbekannter Parameter "--gibtsnicht" wird ignoriert', mOptions.Warnings[0].Text);
  finally
    TAtlasLocale.Use(mSaved);
  end;
end;

procedure TCommandLineOptionsTests.AcceptsSingleAndTypographicDashes;
var
  mOptions: TCommandLineOptions;
begin
  // So stand es in der Registry: Gedankenstrich statt "--" (#647).
  mOptions := TCommandLineOptions.Parse([#$2013'log', 'C:\Temp\atlas-server.log', '-log-level', 'debug']);
  Assert.AreEqual<NativeInt>(0, Length(mOptions.Warnings));
  Assert.AreEqual('C:\Temp\atlas-server.log', mOptions.LogFile);
  Assert.AreEqual<TLogLevel>(TLogLevel.Debug, mOptions.LogLevel);
end;

procedure TCommandLineOptionsTests.WarnsAboutInvalidLogLevel;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--log-level', 'laut']);
  Assert.AreEqual<TLogLevel>(TLogLevel.Info, mOptions.LogLevel);
  Assert.AreEqual<NativeInt>(1, Length(mOptions.Warnings));
end;

procedure TCommandLineOptionsTests.WarnsAboutMissingValue;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--log']);
  Assert.AreEqual('', mOptions.LogFile);
  Assert.AreEqual<NativeInt>(1, Length(mOptions.Warnings));
end;

procedure TCommandLineOptionsTests.ReadsLinterArguments;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--format=sarif', '--output', 'out.sarif',
    '--rules', 'syntax, empty-except', '--units=Main,Legacy/**', '--min-severity', 'warning', '--suppression-stats',
    '--baseline', 'alt.json', '--update-baseline', '--clear-cache']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.AreEqual('App.dproj', mOptions.CheckTarget);
  Assert.AreEqual(Ord(TFindingsFormat.Sarif), Ord(mOptions.CheckFormat));
  Assert.AreEqual('out.sarif', mOptions.OutputFile);
  Assert.AreEqual(2, Integer(Length(mOptions.RuleFilter)));
  Assert.AreEqual('empty-except', mOptions.RuleFilter[1]);
  Assert.AreEqual('Legacy/**', mOptions.UnitFilter[1]);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mOptions.MinSeverity));
  Assert.IsTrue(mOptions.SuppressionStats);
  Assert.AreEqual('alt.json', mOptions.BaselineFile);
  Assert.IsTrue(mOptions.UpdateBaseline);
  Assert.IsTrue(mOptions.ClearCache);
  Assert.IsFalse(mOptions.Metrics);
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--metrics', '--format', 'json']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.IsTrue(mOptions.Metrics, '--metrics (#66)');
  Assert.AreEqual(Ord(TFindingsFormat.Json), Ord(mOptions.CheckFormat));
  Assert.IsFalse(mOptions.Todos);
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--todos']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.IsTrue(mOptions.Todos, '--todos (#68)');
  // Symbolindex (#1112): Standard mit Index und dem Cache des Servers.
  Assert.IsFalse(mOptions.NoIndex);
  Assert.AreEqual('', mOptions.IndexCacheFolder);
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--no-index', '--index-cache', 'C:\Cache']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.IsTrue(mOptions.NoIndex, '--no-index (#1112)');
  Assert.AreEqual('C:\Cache', mOptions.IndexCacheFolder);
  Assert.AreEqual('', mOptions.ArchitectureFile);
  mOptions := TCommandLineOptions.Parse(['--architecture=Bericht.html']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.AreEqual('Bericht.html', mOptions.ArchitectureFile, '--architecture (#1118)');
  Assert.AreEqual('', mOptions.HotspotsFile);
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--hotspots', 'hotspots.html']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.AreEqual('hotspots.html', mOptions.HotspotsFile, '--hotspots (#1354)');
  Assert.AreEqual('App.dproj', mOptions.CheckTarget);
  // Mutanten (#1460): Datei, Routine und Operatoren ohne Warnung.
  mOptions := TCommandLineOptions.Parse(['--mutate', 'Preise.pas', '--routine', 'TPreise.Satz', '--operators',
    'boundary,not', '--format', 'json']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.AreEqual('Preise.pas', mOptions.MutateFile, '--mutate (#1460)');
  Assert.AreEqual('TPreise.Satz', mOptions.MutateRoutine);
  Assert.AreEqual('boundary,not', mOptions.MutateOperators);
  mOptions := TCommandLineOptions.Parse(['--architecture=Bericht.html']);
  Assert.AreEqual('', mOptions.CheckTarget);
  // Vergleich (#1121): Abweichungsarten bei --fail-on ohne Warnung, der Wert bleibt für den Bericht.
  mOptions := TCommandLineOptions.Parse(['--architecture', 'neu.json', '--compare', 'alt.json', '--fail-on',
    'newCycle,centralGrowth']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.AreEqual('alt.json', mOptions.CompareFile);
  Assert.AreEqual('newCycle,centralGrowth', mOptions.FailOnText);
  mOptions := TCommandLineOptions.Parse(['--fail-on', 'irgendwas']);
  Assert.AreEqual(1, Integer(Length(mOptions.Warnings)));
end;

procedure TCommandLineOptionsTests.ReadsFailOnAndSourceRoot;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--check', 'App\App.dproj', '--fail-on', 'warning', '--source-root=C:\Repo']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.AreEqual(Ord(TFailOn.Warning), Ord(mOptions.FailOn));
  Assert.AreEqual('C:\Repo', mOptions.SourceRoot);
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj']);
  Assert.AreEqual(Ord(TFailOn.Error), Ord(mOptions.FailOn), 'Standard: nur Fehler');
  Assert.AreEqual('', mOptions.SourceRoot);
  mOptions := TCommandLineOptions.Parse(['--fail-on=never']);
  Assert.AreEqual(Ord(TFailOn.Never), Ord(mOptions.FailOn));
end;

procedure TCommandLineOptionsTests.ReadsMcpArguments;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--mcp', '--root', 'C:\Projekte\App']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.IsTrue(mOptions.Mcp);
  Assert.AreEqual('C:\Projekte\App', mOptions.McpRoot);
  Assert.IsFalse(TCommandLineOptions.Parse([]).Mcp);
end;

procedure TCommandLineOptionsTests.ReadsChangedArguments;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--changed', '--changed-lines']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.AreEqual('main', mOptions.ChangedRef);
  Assert.IsTrue(mOptions.ChangedMergeBase);
  Assert.IsTrue(mOptions.ChangedLines);
  Assert.IsFalse(mOptions.IncludeUncommitted);
  mOptions := TCommandLineOptions.Parse(['--changed', 'develop', '--check', 'App.dproj']);
  Assert.AreEqual('develop', mOptions.ChangedRef);
  Assert.AreEqual('App.dproj', mOptions.CheckTarget);
  mOptions := TCommandLineOptions.Parse(['--diff=HEAD~3', '--include-uncommitted']);
  Assert.AreEqual('HEAD~3', mOptions.ChangedRef);
  Assert.IsFalse(mOptions.ChangedMergeBase);
  Assert.IsTrue(mOptions.IncludeUncommitted);
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj']);
  Assert.AreEqual('', mOptions.ChangedRef);
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

procedure TCommandLineOptionsTests.ReadsLocale;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--locale', 'en']);
  Assert.AreEqual('en', mOptions.Locale);
  Assert.AreEqual<NativeInt>(0, Length(mOptions.Warnings));
  mOptions := TCommandLineOptions.Parse(['--locale=de-DE']);
  Assert.AreEqual('de-DE', mOptions.Locale);
  mOptions := TCommandLineOptions.Parse(['--locale', 'fr']);
  Assert.AreEqual('', mOptions.Locale);
  Assert.AreEqual<NativeInt>(1, Length(mOptions.Warnings));
  mOptions := TCommandLineOptions.Parse([]);
  Assert.AreEqual('', mOptions.Locale);
end;

procedure TCommandLineOptionsTests.ReadsProfile;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--profile', 'strict']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.AreEqual('strict', mOptions.Profile);
  Assert.AreEqual('', TCommandLineOptions.Parse([]).Profile);
end;

procedure TCommandLineOptionsTests.ReadsRestricted;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--stdio', '--restricted']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.IsTrue(mOptions.Restricted);
  Assert.IsFalse(TCommandLineOptions.Parse([]).Restricted);
end;

procedure TCommandLineOptionsTests.WarnsAboutInvalidLinterValues;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--format', 'xml', '--min-severity', 'off', '--fail-on', 'hint']);
  Assert.AreEqual(3, Integer(Length(mOptions.Warnings)));
  Assert.AreEqual(Ord(TFailOn.Error), Ord(mOptions.FailOn));
  Assert.AreEqual(Ord(TFindingsFormat.Text), Ord(mOptions.CheckFormat));
  Assert.AreEqual(Ord(TRuleSeverity.Default), Ord(mOptions.MinSeverity));
  Assert.AreEqual('', mOptions.CheckTarget);
end;

procedure TCommandLineOptionsTests.ReadsTableOptions;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--trace=t.json', '--OUTPUT', 'o.txt', '--baseline', 'b.json', '--root=R',
    '--log-names', '--clear-cache', '--include-uncommitted', '--changed-lines', '--update-baseline',
    '--suppression-stats', '--metrics', '--todos']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.AreEqual('t.json', mOptions.TraceFile);
  Assert.AreEqual('o.txt', mOptions.OutputFile);
  Assert.AreEqual('b.json', mOptions.BaselineFile);
  Assert.AreEqual('R', mOptions.McpRoot);
  Assert.IsTrue(mOptions.LogNames and mOptions.ClearCache and mOptions.IncludeUncommitted and mOptions.ChangedLines);
  Assert.IsTrue(mOptions.UpdateBaseline and mOptions.SuppressionStats and mOptions.Metrics and mOptions.Todos);
  Assert.IsFalse(mOptions.Mcp or mOptions.Restricted);
  // --include-uncommitted ohne Ref: Standardbasis.
  Assert.AreEqual(TCommandLineOptions.cDefaultChangedBase, mOptions.ChangedRef);
end;

procedure TCommandLineOptionsTests.ReadsReplayFile;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--replay', 'C:\Fall\anfrage.json']);
  Assert.AreEqual('C:\Fall\anfrage.json', mOptions.ReplayFile);
  Assert.AreEqual<NativeInt>(0, Length(mOptions.Warnings));
  mOptions := TCommandLineOptions.Parse(['--stdio']);
  Assert.AreEqual('', mOptions.ReplayFile);
end;

procedure TCommandLineOptionsTests.ReadsFixArguments;
var
  mOptions: TCommandLineOptions;
begin
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--fix', 'redundant-cast, unused-uses',
    '--fix-dry-run']);
  Assert.AreEqual(0, Integer(Length(mOptions.Warnings)));
  Assert.AreEqual('redundant-cast|unused-uses', string.Join('|', mOptions.FixRules));
  Assert.IsTrue(mOptions.FixDryRun);
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--fix=all']);
  Assert.AreEqual('all', string.Join('|', mOptions.FixRules));
  Assert.IsFalse(mOptions.FixDryRun);
  Assert.AreEqual(0, Integer(Length(TCommandLineOptions.Parse(['--check', 'App.dproj']).FixRules)));
  mOptions := TCommandLineOptions.Parse(['--check', 'App.dproj', '--fix', ',']);
  Assert.AreEqual(1, Integer(Length(mOptions.Warnings)));
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
  Assert.AreEqual<TFindingsFormat>(TFindingsFormat.Json, mOptions.CheckFormat);
  Assert.IsFalse(TCommandLineOptions.Parse([]).FormatCheck);
end;

procedure TCommandLineOptionsTests.NamesRunCommand;
begin
  Assert.AreEqual('', TCommandLineOptions.Parse([]).RunCommand);
  Assert.AreEqual('', TCommandLineOptions.Parse(['--mcp', '--root', 'Src']).RunCommand);
  Assert.AreEqual('check', TCommandLineOptions.Parse(['--check', 'Src']).RunCommand);
  Assert.AreEqual('fix', TCommandLineOptions.Parse(['--check', 'Src', '--fix', 'all']).RunCommand);
  Assert.AreEqual('format-check', TCommandLineOptions.Parse(['--check', 'Src', '--format-check']).RunCommand);
  Assert.AreEqual('format-write', TCommandLineOptions.Parse(['--check', 'Src', '--format-write']).RunCommand);
  Assert.AreEqual('metrics', TCommandLineOptions.Parse(['--check', 'Src', '--metrics']).RunCommand);
  Assert.AreEqual('todos', TCommandLineOptions.Parse(['--check', 'Src', '--todos']).RunCommand);
  Assert.AreEqual('architecture', TCommandLineOptions.Parse(['--check', 'Src', '--architecture', 'a.md']).RunCommand);
  Assert.AreEqual('affected-tests', TCommandLineOptions.Parse(['--check', 'T.dproj', '--affected-tests']).RunCommand);
  Assert.AreEqual('query', TCommandLineOptions.Parse(['--query', 'classes']).RunCommand);
  Assert.AreEqual('hotspots', TCommandLineOptions.Parse(['--hotspots', 'h.html']).RunCommand);
  Assert.AreEqual('mutate', TCommandLineOptions.Parse(['--mutate', 'Preise.pas', '--routine', 'Satz']).RunCommand);
end;

function Contains(const AList: TArray<string>; const AValue: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if mItem = AValue then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TCommandLineOptionsTests.MonitorKnowsEverySwitch;
var
  mSwitch: string;
  mKnown, mMonitor: TArray<string>;
begin
  mKnown := TCommandLineOptions.Switches;
  mMonitor := TMonitorCommands.CoveredSwitches + TMonitorCommands.SkippedSwitches;
  for mSwitch in mKnown do
  begin
    Assert.IsTrue(Contains(mMonitor, mSwitch), mSwitch + ' fehlt in TMonitorCommands (CoveredSwitches oder ' +
      'SkippedSwitches)');
  end;
  for mSwitch in mMonitor do
  begin
    Assert.IsTrue(Contains(mKnown, mSwitch), mSwitch + ' kennt der Server nicht');
  end;
  mKnown := nil;
  mMonitor := nil;
end;

procedure TCommandLineOptionsTests.MonitorCallsParse;
const
  cNames: array[TMonitorCommand] of string = ('check', 'metrics', 'todos', 'format-check', 'format-write', 'fix',
    'fix', 'affected-tests', 'architecture', 'architecture', 'architecture', 'hotspots', 'query', '');
var
  mCommand: TMonitorCommand;
  mOptions: TMonitorOptions;
  mParsed: TCommandLineOptions;
begin
  mOptions := Default(TMonitorOptions);
  mOptions.MinSeverity := 'warning';
  mOptions.Rules := 'a,b';
  mOptions.Changed := True;
  mOptions.ChangedBase := 'dev';
  mOptions.ChangedLines := True;
  mOptions.Timings := True;
  mOptions.Query := 'classes';
  mOptions.ArchitectureFile := 'alt.json';
  mOptions.ReplayFile := 'anfrage.json';
  mOptions.AffectedBase := 'main';
  for mCommand := Low(TMonitorCommand) to High(TMonitorCommand) do
  begin
    mParsed := TCommandLineOptions.Parse(TMonitorCommands.Arguments(mCommand, 'C:\Src', mOptions,
      'C:\Temp\out' + TMonitorCommands.OutputExtension(mCommand), 'de'));
    Assert.AreEqual(0, Integer(Length(mParsed.Warnings)), TMonitorCommands.Text(mCommand));
    Assert.AreEqual(cNames[mCommand], mParsed.RunCommand, TMonitorCommands.Text(mCommand));
  end;
  mParsed := TCommandLineOptions.Parse(TMonitorCommands.Arguments(TMonitorCommand.Check, 'C:\Src', mOptions,
    'C:\Temp\out.sarif', 'de'));
  Assert.AreEqual('dev', mParsed.ChangedRef);
  Assert.AreEqual<TFindingsFormat>(TFindingsFormat.Sarif, mParsed.CheckFormat);
  Assert.AreEqual<TFailOn>(TFailOn.Never, mParsed.FailOn);
  Assert.AreEqual('C:\Temp\out.timings.md', mParsed.TimingsFile);
  Assert.AreEqual('anfrage.json', TCommandLineOptions.Parse(TMonitorCommands.Arguments(TMonitorCommand.Replay, '',
    mOptions, '', '')).ReplayFile);
  mOptions := Default(TMonitorOptions);
  mParsed := Default(TCommandLineOptions);
end;

initialization
  TDUnitX.RegisterTestFixture(TCommandLineOptionsTests);

end.
