unit Atlas.Common.Configuration.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConfigurationParserTests = class
  public
    [Test]
    procedure MergesLayersPerKey;
    [Test]
    procedure ReadsArchitectureSettings;
    [Test]
    procedure ReadsHotspotsSettings;
    [Test]
    procedure ReadsArchitectureComparisonSettings;
    /// <summary>architecture.grouping (#1366): Feinheit 0,2–5,0 und Regler im Fenster.</summary>
    [Test]
    procedure ReadsArchitectureGrouping;
    [Test]
    procedure ReadsQuerySettings;
    [Test]
    procedure ReadsRuleChecksSwitch;
    [Test]
    procedure ReadsNavigationSymbolPath;
    [Test]
    procedure ReadsAllSettings;
    [Test]
    procedure EmptyObjectGivesDefaults;
    /// <summary>language "" folgt dem Client (#1458).</summary>
    [Test]
    procedure EmptyLanguageFollowsClient;
    [Test]
    procedure AllowsCommentsAndTrailingCommas;
    [Test]
    procedure ReportsSyntaxErrorWithPosition;
    [Test]
    procedure ReportsWrongTypesAndKeepsValidSettings;
    [Test]
    procedure WarnsAboutUnknownKeys;
    [Test]
    procedure ReadsRuleObjectsWithOptions;
    [Test]
    procedure ReadsInlayHints;
    [Test]
    procedure ReadsCodeLens;
    [Test]
    procedure ReadsSmartIndent;
    [Test]
    procedure ReadsSuggestionPatterns;
    [Test]
    procedure ReadsClassCompletion;
    /// <summary>"references" (#1119): erschlossene Treffer an, Textfunde aus.</summary>
    [Test]
    procedure ReadsReferences;
    [Test]
    procedure ReadsNavigationImpact;
    [Test]
    procedure ReadsAffectedTests;
    [Test]
    procedure MetricsSwitchesOffMetricRules;
    [Test]
    procedure ChecksMetricLimitOption;
    [Test]
    procedure ChecksFactoriesOption;
    [Test]
    procedure ChecksTodoKeywordsOption;
    [Test]
    procedure ChecksForbiddenSymbolsOption;
  end;

  [TestFixture]
  TServerSettingsTests = class
  public
    [Test]
    procedure RuleSeverityFallsBackToDefault;
    [Test]
    procedure MatchesGlobPatterns;
    [Test]
    procedure ExcludesFolders;
    [Test]
    procedure RecognizesConfigurationFileNames;
    [Test]
    procedure PrefersNewFileOverLegacy;
    [Test]
    procedure ReadsDelphiProductNumbers;
    [Test]
    procedure ReadsMinDelphiVersion;
    [Test]
    procedure ReadsSortUses;
    /// <summary>#1352: Untergrenze der Sammelkorrektur.</summary>
    [Test]
    procedure ReadsFixMinConfidence;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.TestSupport;

procedure TConfigurationParserTests.ReadsQuerySettings;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Code-Abfragen (#1351)
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.QueryEnabled);
  Assert.AreEqual(0, Integer(Length(mSettings.Queries)));
  mSettings := Parse('{"query": {"enabled": false}, "queries": [{"name": "grosse-klassen", ' +
    '"query": " classes where methods > 40 ", "description": "Zu groß", "failIfAny": true, "severity": "error", ' +
    '"message": "{name} hat {methods} Methoden"}, {"name": "b", "query": "units where usedBy = 0"}]}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.QueryEnabled);
  Assert.AreEqual(2, Integer(Length(mSettings.Queries)));
  Assert.AreEqual('grosse-klassen', mSettings.Queries[0].Name);
  Assert.AreEqual('classes where methods > 40', mSettings.Queries[0].Query);
  Assert.AreEqual('Zu groß', mSettings.Queries[0].Description);
  Assert.IsTrue(mSettings.Queries[0].FailIfAny);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Error, mSettings.Queries[0].Severity);
  Assert.AreEqual('{name} hat {methods} Methoden', mSettings.Queries[0].Message);
  Assert.IsFalse(mSettings.Queries[1].FailIfAny);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Warning, mSettings.Queries[1].Severity);
  // Fehlender Name oder Abfrage, ungültiger Name, doppelter Name, falscher Schweregrad, unbekannte Angabe.
  mSettings := Parse('{"queries": [{"query": "units where name = A"}, {"name": "x"}, {"name": "a b", "query": "q"}, ' +
    '{"name": "d", "query": "q1"}, {"name": "D", "query": "q2"}, {"name": "s", "query": "q", "severity": "laut"}, ' +
    '{"name": "u", "query": "q", "farbe": 1}]}', mIssues);
  Assert.AreEqual('d,s,u', mSettings.Queries[0].Name + ',' + mSettings.Queries[1].Name + ',' + mSettings.Queries[2].Name);
  Assert.AreEqual('q1', mSettings.Queries[0].Query);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Warning, mSettings.Queries[1].Severity);
  Assert.IsTrue(Length(mIssues) >= 6);
  Parse('{"queries": {}, "query": {"enabled": 1, "x": 2}}', mIssues);
  Assert.AreEqual(3, Integer(Length(mIssues)));
  // Projektdatei vor Editor: queries gilt als Ganzes.
  mSettings := TConfigurationParser.ParseLayered('{"queries": [{"name": "a", "query": "q"}]}',
    '{"queries": [{"name": "b", "query": "r"}], "query": {"enabled": false}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mSettings.Queries)));
  Assert.AreEqual('b', mSettings.Queries[0].Name);
  Assert.IsFalse(mSettings.QueryEnabled);
end;
procedure TConfigurationParserTests.ReadsRuleChecksSwitch;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Modul-Schalter Prüfregeln (#1454): Vorgabe an, aus über settings.json bzw. jede Ebene.
  Assert.IsTrue(Parse('{}', mIssues).RuleChecksEnabled);
  mSettings := Parse('{"ruleChecks": {"enabled": false}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.RuleChecksEnabled);
  Parse('{"ruleChecks": {"enabled": 1, "x": 2}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)), 'kein Wahrheitswert, unbekannte Angabe');
  Parse('{"ruleChecks": true}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'kein Objekt');
  mSettings := TConfigurationParser.ParseLayered('{}', '{"ruleChecks": {"enabled": false}}', mIssues);
  Assert.IsFalse(mSettings.RuleChecksEnabled);
end;
procedure TConfigurationParserTests.ReadsArchitectureComparisonSettings;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Architekturvergleich (#1121)
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual('', mSettings.ArchitectureBaseline);
  Assert.AreEqual('newCycle', string.Join(',', mSettings.ArchitectureFailOn));
  mSettings := Parse('{"architecture": {"baseline": " Stand/main.json ", "failOn": ["newCycle", "centralGrowth"]}}',
    mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('Stand/main.json', mSettings.ArchitectureBaseline);
  Assert.AreEqual('newCycle,centralGrowth', string.Join(',', mSettings.ArchitectureFailOn));
  mSettings := Parse('{"architecture": {"failOn": []}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(0, Integer(Length(mSettings.ArchitectureFailOn)));
  mSettings := Parse('{"architecture": {"baseline": 3, "failOn": ["newCycle", "error"]}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.AreEqual('newCycle', string.Join(',', mSettings.ArchitectureFailOn));
  Parse('{"architecture": {"failOn": "newCycle"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{}', '{"architecture": {"baseline": "a.json", ' +
    '"failOn": ["subsystemChange"]}}', mIssues);
  Assert.AreEqual('a.json', mSettings.ArchitectureBaseline);
  Assert.AreEqual('subsystemChange', string.Join(',', mSettings.ArchitectureFailOn));
end;
/// <summary>Vorgaben, Nachteilung (#1364), Fundamente (#1365) und Zuordnung erklären (#1368).</summary>
procedure ReadsGroupingSplitAndFoundations;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual(Double(1), mSettings.ArchitectureGroupingResolution, 1E-9);
  Assert.IsTrue(mSettings.ArchitectureGroupingShowResolutionSlider);
  Assert.AreEqual(Double(0.25), mSettings.ArchitectureGroupingMaxShare, 1E-9);
  Assert.AreEqual(Double(0.3), mSettings.ArchitectureGroupingMinCohesion, 1E-9);
  // Nachteilung (#1364): 0 schaltet ab, Grenzen 0,9 bzw. 1.
  mSettings := Parse('{"architecture": {"grouping": {"maxShare": 0, "minCohesion": 1}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(Double(0), mSettings.ArchitectureGroupingMaxShare, 1E-9);
  Assert.AreEqual(Double(1), mSettings.ArchitectureGroupingMinCohesion, 1E-9);
  mSettings := Parse('{"architecture": {"grouping": {"maxShare": 0.9, "minCohesion": 0.05}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(Double(0.9), mSettings.ArchitectureGroupingMaxShare, 1E-9);
  Assert.AreEqual(Double(0.05), mSettings.ArchitectureGroupingMinCohesion, 1E-9);
  mSettings := Parse('{"architecture": {"grouping": {"maxShare": 0.95, "minCohesion": -0.1}}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.AreEqual(Double(0.25), mSettings.ArchitectureGroupingMaxShare, 1E-9);
  Assert.AreEqual(Double(0.3), mSettings.ArchitectureGroupingMinCohesion, 1E-9);
  Parse('{"architecture": {"grouping": {"maxShare": "viel"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Fundamente (#1365).
  Assert.AreEqual('separate', TServerSettings.Default.ArchitectureGroupingFoundations);
  mSettings := Parse('{"architecture": {"grouping": {"foundations": "attach"}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('attach', mSettings.ArchitectureGroupingFoundations);
  mSettings := Parse('{"architecture": {"grouping": {"foundations": "Group"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('separate', mSettings.ArchitectureGroupingFoundations);
  // Zuordnung erklären (#1368).
  Assert.IsTrue(TServerSettings.Default.ArchitectureExplainAssignment);
  mSettings := Parse('{"architecture": {"explainAssignment": false}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.ArchitectureExplainAssignment);
  mSettings := Parse('{"architecture": {"explainAssignment": "nein"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsTrue(mSettings.ArchitectureExplainAssignment);
end;
/// <summary>Farben und Namen halten (#1367), Auflösung mit Grenzen und globale Ebene.</summary>
procedure ReadsGroupingResolution;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Farben und Namen halten (#1367).
  Assert.IsTrue(TServerSettings.Default.ArchitectureGroupingKeepPrevious);
  mSettings := Parse('{"architecture": {"grouping": {"keepPrevious": false}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.ArchitectureGroupingKeepPrevious);
  mSettings := Parse('{"architecture": {"grouping": {"keepPrevious": "aus"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsTrue(mSettings.ArchitectureGroupingKeepPrevious);
  mSettings := Parse('{"architecture": {"grouping": {"resolution": 2.5, "showResolutionSlider": false}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(Double(2.5), mSettings.ArchitectureGroupingResolution, 1E-9);
  Assert.IsFalse(mSettings.ArchitectureGroupingShowResolutionSlider);
  // Grenzen 0,2 und 5,0 gelten noch.
  mSettings := Parse('{"architecture": {"grouping": {"resolution": 0.2}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(Double(0.2), mSettings.ArchitectureGroupingResolution, 1E-9);
  mSettings := Parse('{"architecture": {"grouping": {"resolution": 5}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(Double(5), mSettings.ArchitectureGroupingResolution, 1E-9);
  // Außerhalb, falscher Typ und unbekannte Schlüssel: Meldung, Vorgabe bleibt.
  mSettings := Parse('{"architecture": {"grouping": {"resolution": 0.1, "showResolutionSlider": 1, "x": 1}}}',
    mIssues);
  Assert.AreEqual(3, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.IsFalse(mIssues[2].IsError);
  Assert.AreEqual(Double(1), mSettings.ArchitectureGroupingResolution, 1E-9);
  Assert.IsTrue(mSettings.ArchitectureGroupingShowResolutionSlider);
  Parse('{"architecture": {"grouping": {"resolution": 5.5}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Parse('{"architecture": {"grouping": {"resolution": "fein"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Parse('{"architecture": {"grouping": true}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Globale Ebene wie die übrigen architecture-Schlüssel.
  mSettings := TConfigurationParser.ParseLayered('{"architecture": {"grouping": {"resolution": 0.5}}}', '{}',
    mIssues);
  Assert.AreEqual(Double(0.5), mSettings.ArchitectureGroupingResolution, 1E-9);
end;
procedure TConfigurationParserTests.ReadsArchitectureGrouping;
begin
  ReadsGroupingSplitAndFoundations;
  ReadsGroupingResolution;
end;
procedure TConfigurationParserTests.ReadsNavigationSymbolPath;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.Navigation.SymbolPath);
  mSettings := Parse('{"navigation": {"symbolPath": false}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.Navigation.SymbolPath);
  // Unbekannte Schlüssel sind Warnungen, falscher Typ ein Fehler.
  mSettings := Parse('{"navigation": {"symbolPath": 1, "x": 1}}', mIssues);
  Assert.IsTrue(mSettings.Navigation.SymbolPath);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.IsFalse(mIssues[1].IsError);
  Parse('{"navigation": true}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Steht navigation in der Datei, gilt ihr Objekt ganz, auch mit den Vorgaben.
  mSettings := TConfigurationParser.ParseLayered('{"navigation": {"symbolPath": false}}', '{"navigation": {}}', mIssues);
  Assert.IsTrue(mSettings.Navigation.SymbolPath);
end;
procedure TConfigurationParserTests.ReadsArchitectureSettings;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Architekturübersicht (#1118)
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.ArchitectureEnabled);
  Assert.AreEqual('projectGroup', mSettings.ArchitectureScope);
  Assert.IsFalse(mSettings.ArchitectureIncludeLibraryUnits);
  Assert.AreEqual(15, mSettings.ArchitectureCentralUnits);
  Assert.AreEqual(0, Integer(Length(mSettings.ArchitectureExclude)));
  mSettings := Parse('{"architecture": {"enabled": false, "scope": "project", "includeLibraryUnits": true, ' +
    '"centralUnits": 40, "exclude": ["Tests/**", "*.Tests"]}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.ArchitectureEnabled);
  Assert.AreEqual('project', mSettings.ArchitectureScope);
  Assert.IsTrue(mSettings.ArchitectureIncludeLibraryUnits);
  Assert.AreEqual(40, mSettings.ArchitectureCentralUnits);
  Assert.AreEqual('Tests/**|*.Tests', string.Join('|', mSettings.ArchitectureExclude));
  mSettings := Parse('{"architecture": {"enabled": 1, "scope": "alles", "centralUnits": 4, "exclude": "Tests", ' +
    '"x": true}}', mIssues);
  Assert.AreEqual(5, Integer(Length(mIssues)));
  Assert.IsTrue(mSettings.ArchitectureEnabled);
  Assert.AreEqual('projectGroup', mSettings.ArchitectureScope);
  Assert.AreEqual(15, mSettings.ArchitectureCentralUnits);
  Parse('{"architecture": {"centralUnits": 101}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Parse('{"architecture": []}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"architecture": {"centralUnits": 30}}',
    '{"architecture": {"exclude": ["Demo/**"]}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mSettings.ArchitectureExclude)));
end;
procedure TConfigurationParserTests.ReadsHotspotsSettings;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Hotspots (#1354)
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.HotspotsEnabled);
  Assert.AreEqual(12, mSettings.HotspotsMonths);
  Assert.AreEqual(5, mSettings.HotspotsCouplingMinCommits);
  mSettings := Parse('{"hotspots": {"enabled": false, "months": 24, "coupling": {"minCommits": 8}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.HotspotsEnabled);
  Assert.AreEqual(24, mSettings.HotspotsMonths);
  Assert.AreEqual(8, mSettings.HotspotsCouplingMinCommits);
  mSettings := Parse('{"hotspots": {"enabled": 1, "months": 61, "coupling": {"minCommits": 1, "y": 2}, "x": true}}',
    mIssues);
  Assert.AreEqual(5, Integer(Length(mIssues)));
  Assert.IsTrue(mSettings.HotspotsEnabled);
  Assert.AreEqual(12, mSettings.HotspotsMonths);
  Assert.AreEqual(5, mSettings.HotspotsCouplingMinCommits);
  Parse('{"hotspots": {"months": 0, "coupling": {"minCommits": 1001}}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Parse('{"hotspots": {"months": 2.5, "coupling": []}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Parse('{"hotspots": []}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"hotspots": {"months": 6}}',
    '{"hotspots": {"coupling": {"minCommits": 3}}}', mIssues);
  // Die Datei setzt "hotspots" und hat damit für den ganzen Schlüssel Vorrang.
  Assert.AreEqual(12, mSettings.HotspotsMonths);
  Assert.AreEqual(3, mSettings.HotspotsCouplingMinCommits);
end;
procedure TConfigurationParserTests.MergesLayersPerKey;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // #227: globale Datei unter den Editor-Einstellungen; Objekte je Schlüssel, Listen ersetzt.
  Assert.AreEqual('', TConfigurationParser.MergeText('', ''));
  Assert.AreEqual('{"a": 1}', TConfigurationParser.MergeText('', '{"a": 1}'));
  Assert.AreEqual('{"a": 1}', TConfigurationParser.MergeText('{"a": 1}', '  '));
  Assert.AreEqual('{"a": 1}', TConfigurationParser.MergeText('{"a": 1', '{"a": 1}'));
  Assert.AreEqual('{"b": 2, "a": 3}', TConfigurationParser.MergeText('{"a": 1, "b": 2}', '{"a": 3}'));
  Assert.AreEqual('{"x": ["c"], "r": {"q": "error", "p": "off"}}', TConfigurationParser.MergeText(
    '// global'#10'{"x": ["a", "b"], "r": {"p": "warning", "q": "error"}}', '{"x": ["c"], "r": {"p": "off"}}'));
  Assert.AreEqual('{"k\"y": 1}', TConfigurationParser.MergeText('{"k\"y": 1}', '{}'));
  TConfigurationParser.Parse(TConfigurationParser.MergeText('{"format": {"indentSize": 4, ' +
    '"useTabs": true}}', '{"format": {"indentSize": 3}}'), mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;
procedure TConfigurationParserTests.ReadsAllSettings;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse(
    '{'#13#10 +
    '  "$schema": "./schema.json",'#13#10 +
    '  "delphiVersion": "37.0",'#13#10 +
    '  "language": "en",'#13#10 +
    '  "project": "App.dproj", "config": "Release", "platform": "Win64",'#13#10 +
    '  "rules": { "unused-variable": "warning", "with-statement": "off" },'#13#10 +
    '  "exclude": ["ThirdParty/**"],'#13#10 +
    '  "format": { "indentSize": 4 }'#13#10 +
    '}', mIssues);
  Assert.AreEqual<NativeInt>(0, Length(mIssues));
  Assert.AreEqual('37.0', mSettings.DelphiVersion);
  Assert.AreEqual('en', mSettings.Language);
  Assert.AreEqual('App.dproj', mSettings.Project);
  Assert.AreEqual('Release', mSettings.Config);
  Assert.AreEqual('Win64', mSettings.Platform);
  Assert.AreEqual<NativeInt>(2, Length(mSettings.Rules));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Warning, mSettings.RuleSeverity('UNUSED-VARIABLE', TRuleSeverity.Hint));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Off, mSettings.RuleSeverity('with-statement', TRuleSeverity.Hint));
  Assert.AreEqual('ThirdParty/**', mSettings.Exclude[0]);
  Assert.AreEqual('{ "indentSize": 4 }', mSettings.Format);
  Assert.AreEqual(4, mSettings.Formatting.IndentSize);
end;
procedure TConfigurationParserTests.EmptyObjectGivesDefaults;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual<NativeInt>(0, Length(mIssues));
  Assert.AreEqual('', mSettings.Language);
  Assert.AreEqual('', mSettings.DelphiVersion);
end;
procedure TConfigurationParserTests.EmptyLanguageFollowsClient;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{"language": ""}', mIssues);
  Assert.AreEqual<NativeInt>(0, Length(mIssues));
  Assert.AreEqual('', mSettings.Language);
  mSettings := Parse('{"language": "en"}', mIssues);
  Assert.AreEqual('en', mSettings.Language);
end;
procedure TConfigurationParserTests.AllowsCommentsAndTrailingCommas;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{ // Zeilenkommentar'#10'  /* Block */ "platform": "Win32", }', mIssues);
  Assert.AreEqual<NativeInt>(0, Length(mIssues));
  Assert.AreEqual('Win32', mSettings.Platform);
end;
procedure TConfigurationParserTests.ReportsSyntaxErrorWithPosition;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Zeile 1: Komma fehlt vor "language".
  mSettings := Parse('{'#13#10'  "platform": "Win64"'#13#10'  "language": "en"'#13#10'}', mIssues);
  Assert.AreEqual<NativeInt>(1, Length(mIssues));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.AreEqual(2, mIssues[0].Range.StartPos.Line);
  Assert.AreEqual(2, mIssues[0].Range.StartPos.Character);
  // Bei Syntaxfehlern gelten die Vorgaben.
  Assert.AreEqual('', mSettings.Platform);
end;
procedure TConfigurationParserTests.ReportsWrongTypesAndKeepsValidSettings;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{"language": "fr", "platform": 64, "config": "Debug", "rules": {"a": "laut"}}', mIssues);
  Assert.AreEqual<NativeInt>(3, Length(mIssues));
  Assert.AreEqual('', mSettings.Language);
  Assert.AreEqual('', mSettings.Platform);
  Assert.AreEqual('Debug', mSettings.Config);
  Assert.AreEqual<NativeInt>(0, Length(mSettings.Rules));
  // "fr" steht in Spalte 13 bis 17.
  Assert.AreEqual(13, mIssues[0].Range.StartPos.Character);
  Assert.AreEqual(17, mIssues[0].Range.EndPos.Character);
end;
procedure TConfigurationParserTests.WarnsAboutUnknownKeys;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Parse('{'#10'  "plattform": "Win64"'#10'}', mIssues);
  Assert.AreEqual<NativeInt>(1, Length(mIssues));
  Assert.IsFalse(mIssues[0].IsError);
  Assert.AreEqual(1, mIssues[0].Range.StartPos.Line);
  Assert.AreEqual(2, mIssues[0].Range.StartPos.Character);
  Assert.AreEqual(13, mIssues[0].Range.EndPos.Character);
end;
procedure TConfigurationParserTests.ReadsRuleObjectsWithOptions;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{"rules": {"max-length": {"severity": "info", "limit": 120}}}', mIssues);
  Assert.AreEqual<NativeInt>(0, Length(mIssues));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Information, mSettings.Rules[0].Severity);
  Assert.AreEqual('{"severity": "info", "limit": 120}', mSettings.Rules[0].Options);
end;
procedure TConfigurationParserTests.ReadsInlayHints;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.InlayHints.ParameterNames);
  Assert.AreEqual(20, mSettings.InlayHints.EndMarkerMinLines);
  Assert.IsTrue(mSettings.InlayHints.IncludeDefines);
  mSettings := Parse('{"inlayHints": {"includeDefines": false}}', mIssues);
  Assert.IsFalse(mSettings.InlayHints.IncludeDefines, '#860');
  Assert.IsTrue(mSettings.InlayHints.ControlChars, '#862 Vorgabe');
  mSettings := Parse('{"inlayHints": {"controlChars": false}}', mIssues);
  Assert.IsFalse(mSettings.InlayHints.ControlChars, '#862');
  Assert.AreEqual(0, Integer(Length(mIssues)));
  mSettings := Parse('{"inlayHints": {"parameterNames": false, "endMarkerMinLines": 8, "inferredTypes": 1, "x": true}}',
    mIssues);
  Assert.IsFalse(mSettings.InlayHints.ParameterNames);
  Assert.IsTrue(mSettings.InlayHints.InferredTypes);
  Assert.IsTrue(mSettings.InlayHints.EndMarkers);
  Assert.AreEqual(8, mSettings.InlayHints.EndMarkerMinLines);
  // inferredTypes falsch getypt (Fehler), "x" unbekannt (Warnung).
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.IsFalse(mIssues[1].IsError);
  // Die Datei ersetzt den ganzen Block aus dem Editor.
  mSettings := TConfigurationParser.ParseLayered('{"inlayHints": {"endMarkers": false}}',
    '{"inlayHints": {"endMarkerMinLines": 5}}', mIssues);
  Assert.IsTrue(mSettings.InlayHints.EndMarkers);
  Assert.AreEqual(5, mSettings.InlayHints.EndMarkerMinLines);
end;
procedure TConfigurationParserTests.ReadsCodeLens;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.CodeLens.Metrics, 'Kennzahlen standardmäßig an (#66)');
  mSettings := Parse('{"codeLens": {"metrics": false}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.CodeLens.Metrics);
  mSettings := Parse('{"codeLens": {"metrics": 1, "x": true}}', mIssues);
  Assert.IsTrue(mSettings.CodeLens.Metrics);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.IsFalse(mIssues[1].IsError);
  Parse('{"codeLens": true}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Die Datei ersetzt den Block aus dem Editor.
  mSettings := TConfigurationParser.ParseLayered('{"codeLens": {"metrics": false}}', '{"codeLens": {}}', mIssues);
  Assert.IsTrue(mSettings.CodeLens.Metrics);
end;
procedure TConfigurationParserTests.ReadsSmartIndent;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.SmartIndent.Enabled, 'Einrückung beim Tippen standardmäßig an (#1827)');
  Assert.IsTrue(mSettings.SmartIndent.AfterEnter);
  Assert.IsTrue(mSettings.SmartIndent.OutdentClosers);
  Assert.IsTrue(mSettings.SmartIndent.SplitStrings);
  Assert.AreEqual('indent', mSettings.SmartIndent.SplitStringsIndent);
  mSettings := Parse('{"smartIndent": {"enabled": false, "afterEnter": false, "outdentClosers": false, ' +
    '"splitStrings": false, "splitStringsIndent": "align"}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.SmartIndent.Enabled);
  Assert.IsFalse(mSettings.SmartIndent.AfterEnter);
  Assert.IsFalse(mSettings.SmartIndent.OutdentClosers);
  Assert.IsFalse(mSettings.SmartIndent.SplitStrings);
  Assert.AreEqual('align', mSettings.SmartIndent.SplitStringsIndent);
  mSettings := Parse('{"smartIndent": {"splitStringsIndent": "rechts", "x": true}}', mIssues);
  Assert.AreEqual('indent', mSettings.SmartIndent.SplitStringsIndent);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.IsFalse(mIssues[1].IsError);
end;
procedure TConfigurationParserTests.ReadsSuggestionPatterns;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual(0, Integer(Length(mSettings.Suggestions.Patterns)), 'Ohne atlas.json keine eigenen Muster (#1890)');
  mSettings := Parse('{"suggestions": {"patterns": [{"after": " Log.Enter ", "insert": ["try", "  $|", "finally", ' +
    '"  Log.Leave;", "end;"]}]}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(1, Integer(Length(mSettings.Suggestions.Patterns)));
  Assert.AreEqual('Log.Enter', mSettings.Suggestions.Patterns[0].After);
  Assert.AreEqual(5, Integer(Length(mSettings.Suggestions.Patterns[0].Insert)));
  Assert.AreEqual('  Log.Leave;', mSettings.Suggestions.Patterns[0].Insert[3]);
  // Ohne Zeilen, ohne Auslöser und kein Objekt: alle fallen mit Fehler weg, das gültige bleibt.
  mSettings := Parse('{"suggestions": {"patterns": [{"after": "A"}, {"insert": ["x"]}, 3, ' +
    '{"after": "B", "insert": ["y"]}]}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mSettings.Suggestions.Patterns)));
  Assert.AreEqual('B', mSettings.Suggestions.Patterns[0].After);
  Assert.AreEqual(3, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  mSettings := Parse('{"suggestions": {"patterns": {}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;

procedure TConfigurationParserTests.ReadsClassCompletion;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual('brace', mSettings.ClassCompletion.TypeComment, '{ TFoo } wie die IDE (#1835)');
  Assert.IsTrue(mSettings.ClassCompletion.LifecycleFirst, '#1836');
  Assert.IsTrue(mSettings.ClassCompletion.BodyStubs, '#1837');
  mSettings := Parse('{"classCompletion": {"typeComment": "region", "lifecycleFirst": false, "bodyStubs": false}}',
    mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('region', mSettings.ClassCompletion.TypeComment);
  Assert.IsFalse(mSettings.ClassCompletion.LifecycleFirst);
  Assert.IsFalse(mSettings.ClassCompletion.BodyStubs);
  mSettings := Parse('{"classCompletion": {"typeComment": "kasten"}}', mIssues);
  Assert.AreEqual('brace', mSettings.ClassCompletion.TypeComment, 'Unbekanntes bleibt bei der Vorgabe');
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
end;
procedure TConfigurationParserTests.ReadsReferences;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.References.Inferred);
  Assert.IsFalse(mSettings.References.TextMatches);
  mSettings := Parse('{"references": {"inferred": false, "textMatches": true}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.References.Inferred);
  Assert.IsTrue(mSettings.References.TextMatches);
  mSettings := Parse('{"references": {"inferred": 1, "x": true}}', mIssues);
  Assert.IsTrue(mSettings.References.Inferred);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.IsFalse(mIssues[1].IsError);
  Parse('{"references": true}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Die Datei ersetzt den Block aus dem Editor.
  mSettings := TConfigurationParser.ParseLayered('{"references": {"inferred": false}}', '{"references": {}}', mIssues);
  Assert.IsTrue(mSettings.References.Inferred);
end;
procedure TConfigurationParserTests.ReadsNavigationImpact;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.Navigation.Impact);
  Assert.AreEqual(2, mSettings.Navigation.ImpactDepth);
  mSettings := Parse('{"navigation": {"impact": false, "impactDepth": 4}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.Navigation.Impact);
  Assert.AreEqual(4, mSettings.Navigation.ImpactDepth);
  // Außerhalb von 1 bis 5 bleibt die Vorgabe; unbekannte Schlüssel sind Warnungen.
  mSettings := Parse('{"navigation": {"impactDepth": 9, "x": 1}}', mIssues);
  Assert.AreEqual(2, mSettings.Navigation.ImpactDepth);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.IsFalse(mIssues[1].IsError);
  Parse('{"navigation": true}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"navigation": {"impactDepth": 5}}', '{"navigation": {}}', mIssues);
  Assert.AreEqual(2, mSettings.Navigation.ImpactDepth);
end;
procedure TConfigurationParserTests.ReadsAffectedTests;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Betroffene Tests (#1353): Vorgabe an, Tiefe 3.
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.Tests.Affected);
  Assert.AreEqual(3, mSettings.Tests.AffectedDepth);
  mSettings := Parse('{"tests": {"affected": false, "affectedDepth": 5}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.Tests.Affected);
  Assert.AreEqual(5, mSettings.Tests.AffectedDepth);
  // Außerhalb von 1 bis 5 bleibt die Vorgabe; unbekannte Schlüssel sind Warnungen.
  mSettings := Parse('{"tests": {"affectedDepth": 0, "x": 1}}', mIssues);
  Assert.AreEqual(3, mSettings.Tests.AffectedDepth);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.IsFalse(mIssues[1].IsError);
  Parse('{"tests": []}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"tests": {"affected": false}}', '{}', mIssues);
  Assert.IsFalse(mSettings.Tests.Affected);
  // Ordner der Vergleichsdateien (#1881): Vorgabe Tests\Erwartet, leer ist ein Fehler und lässt die Vorgabe.
  Assert.AreEqual(TTestsSettings.cDefaultApprovalFolder, mSettings.Tests.ApprovalFolder);
  mSettings := Parse('{"tests": {"approvalFolder": "Golden"}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('Golden', mSettings.Tests.ApprovalFolder);
  mSettings := Parse('{"tests": {"approvalFolder": " "}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.AreEqual(TTestsSettings.cDefaultApprovalFolder, mSettings.Tests.ApprovalFolder);
end;
procedure TConfigurationParserTests.MetricsSwitchesOffMetricRules;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mLength_, mOther: TRuleDescriptor;
begin
  mLength_ := TRuleDescriptor.Create('metric-method-length', TRuleSeverity.Warning, 'Länge');
  mOther := TRuleDescriptor.Create('empty-except', TRuleSeverity.Warning, 'Leer');
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.Metrics, 'Kennzahlen standardmäßig an');
  Assert.AreNotEqual(Ord(TRuleSeverity.Off), Ord(TRuleEngine.EffectiveSeverity(mLength_, mSettings, '')));
  mSettings := Parse('{"metrics": false}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.Metrics);
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(TRuleEngine.EffectiveSeverity(mLength_, mSettings, '')));
  Assert.AreNotEqual(Ord(TRuleSeverity.Off), Ord(TRuleEngine.EffectiveSeverity(mOther, mSettings, '')),
    'andere Regeln bleiben');
  // Das Projekt setzt die Regel ausdrücklich: sie gilt trotz des globalen Schalters.
  mSettings := Parse('{"metrics": false, "rules": {"metric-method-length": "error"}}', mIssues);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(TRuleEngine.EffectiveSeverity(mLength_, mSettings, '')));
  Parse('{"metrics": 1}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;
procedure TConfigurationParserTests.ChecksMetricLimitOption;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{"rules": {"metric-cyclomatic-complexity": {"severity": "warning", "max": 10}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('{"severity": "warning", "max": 10}', mSettings.Rules[0].Options);
  Parse('{"rules": {"metric-method-length": {"max": 0}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"max"');
  Parse('{"rules": {"metric-method-length": {"max": "80"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Parse('{"rules": {"metric-method-length": {"max": 2.5}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // minLines von commented-out-code (#942).
  Parse('{"rules": {"commented-out-code": {"minLines": 5}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"rules": {"commented-out-code": {"minLines": 0}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"minLines"');
  // minRecordSize und ignoreOverrides von managed-param-without-const (#975).
  Parse('{"rules": {"managed-param-without-const": {"minRecordSize": 32, "ignoreOverrides": false}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"rules": {"managed-param-without-const": {"minRecordSize": 0}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"minRecordSize"');
  Parse('{"rules": {"managed-param-without-const": {"ignoreOverrides": "nein"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"ignoreOverrides"');
  // requirePublic und checkReturns von xmldoc-mismatch (#979).
  Parse('{"rules": {"xmldoc-mismatch": {"requirePublic": true, "checkReturns": false}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"rules": {"xmldoc-mismatch": {"checkReturns": "nein"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"checkReturns"');
  // allowTypes von unrelated-class-cast (#1129).
  Parse('{"rules": {"unrelated-class-cast": {"allowTypes": ["TEdit=TButton", "THackControl"]}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"rules": {"unrelated-class-cast": {"allowTypes": "TEdit"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"allowTypes"');
  // registrationCalls von dunitx-fixture-not-registered (#1882).
  Parse('{"rules": {"dunitx-fixture-not-registered": {"registrationCalls": ["RegistriereAlle"]}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"rules": {"dunitx-fixture-not-registered": {"registrationCalls": "RegistriereAlle"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"registrationCalls"');
  // managedFields von dunitx-setup-not-torn-down (#1781).
  Parse('{"rules": {"dunitx-setup-not-torn-down": {"managedFields": false}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"rules": {"dunitx-setup-not-torn-down": {"managedFields": "nein"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"managedFields"');
  // pureFunctions von ignored-result (#624).
  Parse('{"rules": {"ignored-result": {"pureFunctions": ["Bereinigt", "TText.Clean"]}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"rules": {"ignored-result": {"pureFunctions": "Bereinigt"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"pureFunctions"');
  // formatMethods von format-args (#56).
  Parse('{"rules": {"format-args": {"formatMethods": ["TLogger.LogFmt", "Protokoll"]}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"rules": {"format-args": {"formatMethods": "Protokoll"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"formatMethods"');
  // checkFree von redundant-cast (#1139).
  Parse('{"rules": {"redundant-cast": {"checkFree": false}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"rules": {"redundant-cast": {"checkFree": "nein"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"checkFree"');
  // allowFirstElement von loop-runs-at-most-once (#1131).
  Parse('{"rules": {"loop-runs-at-most-once": {"allowFirstElement": true}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"rules": {"loop-runs-at-most-once": {"allowFirstElement": "ja"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"allowFirstElement"');
end;
procedure TConfigurationParserTests.ChecksFactoriesOption;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // factories von created-result-not-freed (#1876).
  Parse('{"rules": {"created-result-not-freed": {"factories": ["NeueListe", "TBau.Neu"]}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"rules": {"created-result-not-freed": {"factories": "NeueListe"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"factories"');
end;

procedure TConfigurationParserTests.ChecksForbiddenSymbolsOption;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // symbols von forbidden-symbol (#1133).
  Parse('{"rules": {"forbidden-symbol": {"symbols": [{"name": "System.Write*", "kind": "routine", ' +
    '"message": "Nur über ILogger", "replacement": "Log", "severity": "error", "units": ["App.*", "!App.Cli"], ' +
    '"firstArgument": ["nil"], "allowFirstArgument": ["ErrOutput"]}, {"name": "Vcl.Forms.TApplication.' +
    'ProcessMessages"}]}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"rules": {"forbidden-symbol": {"symbols": {"name": "X"}}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"symbols"');
  Parse('{"rules": {"forbidden-symbol": {"symbols": [{"kind": "type"}, "X", {"name": ""}]}}}', mIssues);
  Assert.AreEqual(3, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, 'ohne "name"');
  Assert.Contains(mIssues[1].Message, 'ein Objekt');
  Assert.Contains(mIssues[2].Message, '"name"');
  Parse('{"rules": {"forbidden-symbol": {"symbols": [{"name": "X", "kind": "methode", "severity": "laut", ' +
    '"units": "App", "message": 1, "farbe": "rot"}]}}}', mIssues);
  Assert.AreEqual(5, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"kind"');
  Assert.Contains(mIssues[1].Message, 'Schweregrad');
  Assert.Contains(mIssues[2].Message, '"units"');
  Assert.Contains(mIssues[3].Message, '"message"');
  Assert.Contains(mIssues[4].Message, '"farbe"');
end;
procedure TConfigurationParserTests.ChecksTodoKeywordsOption;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{"rules": {"todo-comment": {"severity": "hint", "keywords": ["TODO", "hack"]}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('{"severity": "hint", "keywords": ["TODO", "hack"]}', mSettings.Rules[0].Options);
  Parse('{"rules": {"todo-comment": {"keywords": "TODO"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"keywords"');
  // DONE ist die Marke der erledigten Einträge; Zeichen außer Buchstaben passen nicht zum ersten Wort.
  Parse('{"rules": {"todo-comment": {"keywords": ["DONE", "TO-DO", "", 1, "XXX"]}}}', mIssues);
  Assert.AreEqual(4, Integer(Length(mIssues)));
end;
procedure TServerSettingsTests.RuleSeverityFallsBackToDefault;
var
  mSettings: TServerSettings;
begin
  mSettings := TServerSettings.Default;
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Error, mSettings.RuleSeverity('x', TRuleSeverity.Error));
end;
procedure TServerSettingsTests.MatchesGlobPatterns;
begin
  Assert.IsTrue(MatchesGlob('ThirdParty/**', 'ThirdParty\Lib\A.pas'));
  Assert.IsTrue(MatchesGlob('**/*.inc', 'Source\Deep\X.INC'));
  Assert.IsTrue(MatchesGlob('**/*.inc', 'X.inc'));
  Assert.IsTrue(MatchesGlob('Gen/*.pas', 'Gen/A.pas'));
  Assert.IsFalse(MatchesGlob('Gen/*.pas', 'Gen/Sub/A.pas'));
  Assert.IsTrue(MatchesGlob('Unit?.pas', 'Unit1.pas'));
  Assert.IsFalse(MatchesGlob('Unit?.pas', 'Unit12.pas'));
end;
procedure TServerSettingsTests.ExcludesFolders;
var
  mSettings: TServerSettings;
begin
  mSettings := TServerSettings.Default;
  mSettings.Exclude := ['Vendor', 'Tools/'];
  Assert.IsTrue(mSettings.IsExcluded('Vendor\A.pas'));
  Assert.IsTrue(mSettings.IsExcluded('./Tools/B.pas'));
  Assert.IsFalse(mSettings.IsExcluded('Source\Vendor.pas'));
end;
procedure TServerSettingsTests.RecognizesConfigurationFileNames;
begin
  Assert.IsTrue(IsConfigurationFileName('atlas.json'));
  Assert.IsTrue(IsConfigurationFileName('Atlas.JSON'));
  Assert.IsTrue(IsConfigurationFileName('delphi-lsp.json'));
  Assert.IsFalse(IsConfigurationFileName('atlas-baseline.json'));
end;
procedure TServerSettingsTests.PrefersNewFileOverLegacy;
var
  mDir: string;
begin
  mDir := TPath.Combine(TPath.GetTempPath, 'Atlas.Tests.' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(mDir);
  try
    // Ohne Datei: der neue Name, damit dort angelegt wird.
    Assert.AreEqual(TPath.Combine(mDir, 'atlas.json'), ExistingOrLegacyFile(mDir, 'atlas.json', 'delphi-lsp.json'));
    TFile.WriteAllText(TPath.Combine(mDir, 'delphi-lsp.json'), '{}');
    Assert.AreEqual(TPath.Combine(mDir, 'delphi-lsp.json'), ExistingOrLegacyFile(mDir, 'atlas.json', 'delphi-lsp.json'));
    TFile.WriteAllText(TPath.Combine(mDir, 'atlas.json'), '{}');
    Assert.AreEqual(TPath.Combine(mDir, 'atlas.json'), ExistingOrLegacyFile(mDir, 'atlas.json', 'delphi-lsp.json'));
  finally
    TDirectory.Delete(mDir, True);
  end;
end;
procedure TServerSettingsTests.ReadsDelphiProductNumbers;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // "12" ist Delphi 12 (BDS 23.0), nicht BDS 12.0 (Delphi 2009).
  Assert.AreEqual('23.0', BdsVersionOf('12'));
  Assert.AreEqual('37.0', BdsVersionOf('13'));
  Assert.AreEqual('20.0', BdsVersionOf('10.3'));
  Assert.AreEqual('17.0', BdsVersionOf('10'));
  Assert.AreEqual('23.0', BdsVersionOf('23.0'));
  Assert.AreEqual('', BdsVersionOf('9'));
  Assert.AreEqual('', BdsVersionOf('neu'));
  Assert.AreEqual('23.0', Parse('{"delphiVersion": "12"}', mIssues).DelphiVersion);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('', Parse('{"delphiVersion": "7"}', mIssues).DelphiVersion);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Unbekannte BDS-Nummer (#109).
  Assert.AreEqual('', BdsVersionOf('99'));
  Assert.AreEqual('', BdsVersionOf('30.0'));
  Assert.AreEqual('', Parse('{"delphiVersion": "99"}', mIssues).DelphiVersion);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('19.0', Parse('{"delphiVersion": "10.2"}', mIssues).DelphiVersion);
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;
procedure TServerSettingsTests.ReadsMinDelphiVersion;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // #1126: älteste Version, mit der das Projekt übersetzen muss; Produktnummern wie bei delphiVersion.
  Assert.AreEqual('', Parse('{}', mIssues).MinDelphiVersion);
  Assert.AreEqual('23.0', Parse('{"minDelphiVersion": "12"}', mIssues).MinDelphiVersion);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('22.0', Parse('{"minDelphiVersion": "22.0"}', mIssues).MinDelphiVersion);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('', Parse('{"minDelphiVersion": "7"}', mIssues).MinDelphiVersion);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Die globale delphiVersion bleibt davon unberührt.
  Assert.AreEqual('', Parse('{"minDelphiVersion": "12"}', mIssues).DelphiVersion);
end;
procedure TServerSettingsTests.ReadsSortUses;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Assert.IsFalse(Parse('{}', mIssues).SortUses);
  Assert.IsTrue(Parse('{"sortUses": true}', mIssues).SortUses);
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;
procedure TServerSettingsTests.ReadsFixMinConfidence;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Parse('{}', mIssues).FixMinConfidence));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Parse('{"fix": {"minConfidence": "medium"}}',
    mIssues).FixMinConfidence));
  Assert.AreEqual(0, Integer(Length(mIssues)));
  // Niedrige Konfidenz ist für Sammelkorrekturen nie erlaubt; die Vorgabe bleibt.
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Parse('{"fix": {"minConfidence": "low"}}',
    mIssues).FixMinConfidence));
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Parse('{"fix": {"bulk": true}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Parse('{"fix": "high"}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;
initialization
  TDUnitX.RegisterTestFixture(TConfigurationParserTests);
  TDUnitX.RegisterTestFixture(TServerSettingsTests);

end.
