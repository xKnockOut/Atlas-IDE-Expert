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
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Code-Abfragen (#1351)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.QueryEnabled);
  Assert.AreEqual(0, Integer(Length(Settings.Queries)));
  Settings := Parse('{"query": {"enabled": false}, "queries": [{"name": "grosse-klassen", ' +
    '"query": " classes where methods > 40 ", "description": "Zu groß", "failIfAny": true, "severity": "error", ' +
    '"message": "{name} hat {methods} Methoden"}, {"name": "b", "query": "units where usedBy = 0"}]}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.QueryEnabled);
  Assert.AreEqual(2, Integer(Length(Settings.Queries)));
  Assert.AreEqual('grosse-klassen', Settings.Queries[0].Name);
  Assert.AreEqual('classes where methods > 40', Settings.Queries[0].Query);
  Assert.AreEqual('Zu groß', Settings.Queries[0].Description);
  Assert.IsTrue(Settings.Queries[0].FailIfAny);
  Assert.IsTrue(Settings.Queries[0].Severity = TRuleSeverity.Error);
  Assert.AreEqual('{name} hat {methods} Methoden', Settings.Queries[0].Message);
  Assert.IsFalse(Settings.Queries[1].FailIfAny);
  Assert.IsTrue(Settings.Queries[1].Severity = TRuleSeverity.Warning);
  // Fehlender Name oder Abfrage, ungültiger Name, doppelter Name, falscher Schweregrad, unbekannte Angabe.
  Settings := Parse('{"queries": [{"query": "units where name = A"}, {"name": "x"}, {"name": "a b", "query": "q"}, ' +
    '{"name": "d", "query": "q1"}, {"name": "D", "query": "q2"}, {"name": "s", "query": "q", "severity": "laut"}, ' +
    '{"name": "u", "query": "q", "farbe": 1}]}', Issues);
  Assert.AreEqual('d,s,u', Settings.Queries[0].Name + ',' + Settings.Queries[1].Name + ',' + Settings.Queries[2].Name);
  Assert.AreEqual('q1', Settings.Queries[0].Query);
  Assert.IsTrue(Settings.Queries[1].Severity = TRuleSeverity.Warning);
  Assert.IsTrue(Length(Issues) >= 6);
  Parse('{"queries": {}, "query": {"enabled": 1, "x": 2}}', Issues);
  Assert.AreEqual(3, Integer(Length(Issues)));
  // Projektdatei vor Editor: queries gilt als Ganzes.
  Settings := TConfigurationParser.ParseLayered('{"queries": [{"name": "a", "query": "q"}]}',
    '{"queries": [{"name": "b", "query": "r"}], "query": {"enabled": false}}', Issues);
  Assert.AreEqual(1, Integer(Length(Settings.Queries)));
  Assert.AreEqual('b', Settings.Queries[0].Name);
  Assert.IsFalse(Settings.QueryEnabled);
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
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Architekturvergleich (#1121)
  Settings := Parse('{}', Issues);
  Assert.AreEqual('', Settings.ArchitectureBaseline);
  Assert.AreEqual('newCycle', string.Join(',', Settings.ArchitectureFailOn));
  Settings := Parse('{"architecture": {"baseline": " Stand/main.json ", "failOn": ["newCycle", "centralGrowth"]}}',
    Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('Stand/main.json', Settings.ArchitectureBaseline);
  Assert.AreEqual('newCycle,centralGrowth', string.Join(',', Settings.ArchitectureFailOn));
  Settings := Parse('{"architecture": {"failOn": []}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(0, Integer(Length(Settings.ArchitectureFailOn)));
  Settings := Parse('{"architecture": {"baseline": 3, "failOn": ["newCycle", "error"]}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Assert.AreEqual('newCycle', string.Join(',', Settings.ArchitectureFailOn));
  Parse('{"architecture": {"failOn": "newCycle"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{}', '{"architecture": {"baseline": "a.json", ' +
    '"failOn": ["subsystemChange"]}}', Issues);
  Assert.AreEqual('a.json', Settings.ArchitectureBaseline);
  Assert.AreEqual('subsystemChange', string.Join(',', Settings.ArchitectureFailOn));
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
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Navigation.SymbolPath);
  Settings := Parse('{"navigation": {"symbolPath": false}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Navigation.SymbolPath);
  // Unbekannte Schlüssel sind Warnungen, falscher Typ ein Fehler.
  Settings := Parse('{"navigation": {"symbolPath": 1, "x": 1}}', Issues);
  Assert.IsTrue(Settings.Navigation.SymbolPath);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Assert.IsTrue(Issues[0].IsError);
  Assert.IsFalse(Issues[1].IsError);
  Parse('{"navigation": true}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Steht navigation in der Datei, gilt ihr Objekt ganz, auch mit den Vorgaben.
  Settings := TConfigurationParser.ParseLayered('{"navigation": {"symbolPath": false}}', '{"navigation": {}}', Issues);
  Assert.IsTrue(Settings.Navigation.SymbolPath);
end;
procedure TConfigurationParserTests.ReadsArchitectureSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Architekturübersicht (#1118)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.ArchitectureEnabled);
  Assert.AreEqual('projectGroup', Settings.ArchitectureScope);
  Assert.IsFalse(Settings.ArchitectureIncludeLibraryUnits);
  Assert.AreEqual(15, Settings.ArchitectureCentralUnits);
  Assert.AreEqual(0, Integer(Length(Settings.ArchitectureExclude)));
  Settings := Parse('{"architecture": {"enabled": false, "scope": "project", "includeLibraryUnits": true, ' +
    '"centralUnits": 40, "exclude": ["Tests/**", "*.Tests"]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.ArchitectureEnabled);
  Assert.AreEqual('project', Settings.ArchitectureScope);
  Assert.IsTrue(Settings.ArchitectureIncludeLibraryUnits);
  Assert.AreEqual(40, Settings.ArchitectureCentralUnits);
  Assert.AreEqual('Tests/**|*.Tests', string.Join('|', Settings.ArchitectureExclude));
  Settings := Parse('{"architecture": {"enabled": 1, "scope": "alles", "centralUnits": 4, "exclude": "Tests", ' +
    '"x": true}}', Issues);
  Assert.AreEqual(5, Integer(Length(Issues)));
  Assert.IsTrue(Settings.ArchitectureEnabled);
  Assert.AreEqual('projectGroup', Settings.ArchitectureScope);
  Assert.AreEqual(15, Settings.ArchitectureCentralUnits);
  Parse('{"architecture": {"centralUnits": 101}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Parse('{"architecture": []}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"architecture": {"centralUnits": 30}}',
    '{"architecture": {"exclude": ["Demo/**"]}}', Issues);
  Assert.AreEqual(1, Integer(Length(Settings.ArchitectureExclude)));
end;
procedure TConfigurationParserTests.ReadsHotspotsSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Hotspots (#1354)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.HotspotsEnabled);
  Assert.AreEqual(12, Settings.HotspotsMonths);
  Assert.AreEqual(5, Settings.HotspotsCouplingMinCommits);
  Settings := Parse('{"hotspots": {"enabled": false, "months": 24, "coupling": {"minCommits": 8}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.HotspotsEnabled);
  Assert.AreEqual(24, Settings.HotspotsMonths);
  Assert.AreEqual(8, Settings.HotspotsCouplingMinCommits);
  Settings := Parse('{"hotspots": {"enabled": 1, "months": 61, "coupling": {"minCommits": 1, "y": 2}, "x": true}}',
    Issues);
  Assert.AreEqual(5, Integer(Length(Issues)));
  Assert.IsTrue(Settings.HotspotsEnabled);
  Assert.AreEqual(12, Settings.HotspotsMonths);
  Assert.AreEqual(5, Settings.HotspotsCouplingMinCommits);
  Parse('{"hotspots": {"months": 0, "coupling": {"minCommits": 1001}}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Parse('{"hotspots": {"months": 2.5, "coupling": []}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Parse('{"hotspots": []}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"hotspots": {"months": 6}}',
    '{"hotspots": {"coupling": {"minCommits": 3}}}', Issues);
  // Die Datei setzt "hotspots" und hat damit für den ganzen Schlüssel Vorrang.
  Assert.AreEqual(12, Settings.HotspotsMonths);
  Assert.AreEqual(3, Settings.HotspotsCouplingMinCommits);
end;
procedure TConfigurationParserTests.MergesLayersPerKey;
var
  Issues: TArray<TConfigurationIssue>;
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
    '"useTabs": true}}', '{"format": {"indentSize": 3}}'), Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;
procedure TConfigurationParserTests.ReadsAllSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse(
    '{'#13#10 +
    '  "$schema": "./schema.json",'#13#10 +
    '  "delphiVersion": "37.0",'#13#10 +
    '  "language": "en",'#13#10 +
    '  "project": "App.dproj", "config": "Release", "platform": "Win64",'#13#10 +
    '  "rules": { "unused-variable": "warning", "with-statement": "off" },'#13#10 +
    '  "exclude": ["ThirdParty/**"],'#13#10 +
    '  "format": { "indentSize": 4 }'#13#10 +
    '}', Issues);
  Assert.AreEqual<NativeInt>(0, Length(Issues));
  Assert.AreEqual('37.0', Settings.DelphiVersion);
  Assert.AreEqual('en', Settings.Language);
  Assert.AreEqual('App.dproj', Settings.Project);
  Assert.AreEqual('Release', Settings.Config);
  Assert.AreEqual('Win64', Settings.Platform);
  Assert.AreEqual<NativeInt>(2, Length(Settings.Rules));
  Assert.IsTrue(Settings.RuleSeverity('UNUSED-VARIABLE', TRuleSeverity.Hint) = TRuleSeverity.Warning);
  Assert.IsTrue(Settings.RuleSeverity('with-statement', TRuleSeverity.Hint) = TRuleSeverity.Off);
  Assert.AreEqual('ThirdParty/**', Settings.Exclude[0]);
  Assert.AreEqual('{ "indentSize": 4 }', Settings.Format);
  Assert.AreEqual(4, Settings.Formatting.IndentSize);
end;
procedure TConfigurationParserTests.EmptyObjectGivesDefaults;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual<NativeInt>(0, Length(Issues));
  Assert.AreEqual('', Settings.Language);
  Assert.AreEqual('', Settings.DelphiVersion);
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
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{ // Zeilenkommentar'#10'  /* Block */ "platform": "Win32", }', Issues);
  Assert.AreEqual<NativeInt>(0, Length(Issues));
  Assert.AreEqual('Win32', Settings.Platform);
end;
procedure TConfigurationParserTests.ReportsSyntaxErrorWithPosition;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Zeile 1: Komma fehlt vor "language".
  Settings := Parse('{'#13#10'  "platform": "Win64"'#13#10'  "language": "en"'#13#10'}', Issues);
  Assert.AreEqual<NativeInt>(1, Length(Issues));
  Assert.IsTrue(Issues[0].IsError);
  Assert.AreEqual(2, Issues[0].Range.StartPos.Line);
  Assert.AreEqual(2, Issues[0].Range.StartPos.Character);
  // Bei Syntaxfehlern gelten die Vorgaben.
  Assert.AreEqual('', Settings.Platform);
end;
procedure TConfigurationParserTests.ReportsWrongTypesAndKeepsValidSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"language": "fr", "platform": 64, "config": "Debug", "rules": {"a": "laut"}}', Issues);
  Assert.AreEqual<NativeInt>(3, Length(Issues));
  Assert.AreEqual('', Settings.Language);
  Assert.AreEqual('', Settings.Platform);
  Assert.AreEqual('Debug', Settings.Config);
  Assert.AreEqual<NativeInt>(0, Length(Settings.Rules));
  // "fr" steht in Spalte 13 bis 17.
  Assert.AreEqual(13, Issues[0].Range.StartPos.Character);
  Assert.AreEqual(17, Issues[0].Range.EndPos.Character);
end;
procedure TConfigurationParserTests.WarnsAboutUnknownKeys;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Parse('{'#10'  "plattform": "Win64"'#10'}', Issues);
  Assert.AreEqual<NativeInt>(1, Length(Issues));
  Assert.IsFalse(Issues[0].IsError);
  Assert.AreEqual(1, Issues[0].Range.StartPos.Line);
  Assert.AreEqual(2, Issues[0].Range.StartPos.Character);
  Assert.AreEqual(13, Issues[0].Range.EndPos.Character);
end;
procedure TConfigurationParserTests.ReadsRuleObjectsWithOptions;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"rules": {"max-length": {"severity": "info", "limit": 120}}}', Issues);
  Assert.AreEqual<NativeInt>(0, Length(Issues));
  Assert.IsTrue(Settings.Rules[0].Severity = TRuleSeverity.Information);
  Assert.AreEqual('{"severity": "info", "limit": 120}', Settings.Rules[0].Options);
end;
procedure TConfigurationParserTests.ReadsInlayHints;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.InlayHints.ParameterNames);
  Assert.AreEqual(20, Settings.InlayHints.EndMarkerMinLines);
  Assert.IsTrue(Settings.InlayHints.IncludeDefines);
  Settings := Parse('{"inlayHints": {"includeDefines": false}}', Issues);
  Assert.IsFalse(Settings.InlayHints.IncludeDefines, '#860');
  Assert.IsTrue(Settings.InlayHints.ControlChars, '#862 Vorgabe');
  Settings := Parse('{"inlayHints": {"controlChars": false}}', Issues);
  Assert.IsFalse(Settings.InlayHints.ControlChars, '#862');
  Assert.AreEqual(0, Integer(Length(Issues)));
  Settings := Parse('{"inlayHints": {"parameterNames": false, "endMarkerMinLines": 8, "inferredTypes": 1, "x": true}}',
    Issues);
  Assert.IsFalse(Settings.InlayHints.ParameterNames);
  Assert.IsTrue(Settings.InlayHints.InferredTypes);
  Assert.IsTrue(Settings.InlayHints.EndMarkers);
  Assert.AreEqual(8, Settings.InlayHints.EndMarkerMinLines);
  // inferredTypes falsch getypt (Fehler), "x" unbekannt (Warnung).
  Assert.AreEqual(2, Integer(Length(Issues)));
  Assert.IsTrue(Issues[0].IsError);
  Assert.IsFalse(Issues[1].IsError);
  // Die Datei ersetzt den ganzen Block aus dem Editor.
  Settings := TConfigurationParser.ParseLayered('{"inlayHints": {"endMarkers": false}}',
    '{"inlayHints": {"endMarkerMinLines": 5}}', Issues);
  Assert.IsTrue(Settings.InlayHints.EndMarkers);
  Assert.AreEqual(5, Settings.InlayHints.EndMarkerMinLines);
end;
procedure TConfigurationParserTests.ReadsCodeLens;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.CodeLens.Metrics, 'Kennzahlen standardmäßig an (#66)');
  Settings := Parse('{"codeLens": {"metrics": false}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.CodeLens.Metrics);
  Settings := Parse('{"codeLens": {"metrics": 1, "x": true}}', Issues);
  Assert.IsTrue(Settings.CodeLens.Metrics);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Assert.IsTrue(Issues[0].IsError);
  Assert.IsFalse(Issues[1].IsError);
  Parse('{"codeLens": true}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Die Datei ersetzt den Block aus dem Editor.
  Settings := TConfigurationParser.ParseLayered('{"codeLens": {"metrics": false}}', '{"codeLens": {}}', Issues);
  Assert.IsTrue(Settings.CodeLens.Metrics);
end;
procedure TConfigurationParserTests.ReadsSmartIndent;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.SmartIndent.Enabled, 'Einrückung beim Tippen standardmäßig an (#1827)');
  Assert.IsTrue(Settings.SmartIndent.AfterEnter);
  Assert.IsTrue(Settings.SmartIndent.OutdentClosers);
  Assert.IsTrue(Settings.SmartIndent.SplitStrings);
  Assert.AreEqual('indent', Settings.SmartIndent.SplitStringsIndent);
  Settings := Parse('{"smartIndent": {"enabled": false, "afterEnter": false, "outdentClosers": false, ' +
    '"splitStrings": false, "splitStringsIndent": "align"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.SmartIndent.Enabled);
  Assert.IsFalse(Settings.SmartIndent.AfterEnter);
  Assert.IsFalse(Settings.SmartIndent.OutdentClosers);
  Assert.IsFalse(Settings.SmartIndent.SplitStrings);
  Assert.AreEqual('align', Settings.SmartIndent.SplitStringsIndent);
  Settings := Parse('{"smartIndent": {"splitStringsIndent": "rechts", "x": true}}', Issues);
  Assert.AreEqual('indent', Settings.SmartIndent.SplitStringsIndent);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Assert.IsTrue(Issues[0].IsError);
  Assert.IsFalse(Issues[1].IsError);
end;
procedure TConfigurationParserTests.ReadsSuggestionPatterns;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual(0, Integer(Length(Settings.Suggestions.Patterns)), 'Ohne atlas.json keine eigenen Muster (#1890)');
  Settings := Parse('{"suggestions": {"patterns": [{"after": " Log.Enter ", "insert": ["try", "  $|", "finally", ' +
    '"  Log.Leave;", "end;"]}]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(1, Integer(Length(Settings.Suggestions.Patterns)));
  Assert.AreEqual('Log.Enter', Settings.Suggestions.Patterns[0].After);
  Assert.AreEqual(5, Integer(Length(Settings.Suggestions.Patterns[0].Insert)));
  Assert.AreEqual('  Log.Leave;', Settings.Suggestions.Patterns[0].Insert[3]);
  // Ohne Zeilen, ohne Auslöser und kein Objekt: alle fallen mit Fehler weg, das gültige bleibt.
  Settings := Parse('{"suggestions": {"patterns": [{"after": "A"}, {"insert": ["x"]}, 3, ' +
    '{"after": "B", "insert": ["y"]}]}}', Issues);
  Assert.AreEqual(1, Integer(Length(Settings.Suggestions.Patterns)));
  Assert.AreEqual('B', Settings.Suggestions.Patterns[0].After);
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.IsTrue(Issues[0].IsError);
  Settings := Parse('{"suggestions": {"patterns": {}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

procedure TConfigurationParserTests.ReadsClassCompletion;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual('brace', Settings.ClassCompletion.TypeComment, '{ TFoo } wie die IDE (#1835)');
  Assert.IsTrue(Settings.ClassCompletion.LifecycleFirst, '#1836');
  Assert.IsTrue(Settings.ClassCompletion.BodyStubs, '#1837');
  Settings := Parse('{"classCompletion": {"typeComment": "region", "lifecycleFirst": false, "bodyStubs": false}}',
    Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('region', Settings.ClassCompletion.TypeComment);
  Assert.IsFalse(Settings.ClassCompletion.LifecycleFirst);
  Assert.IsFalse(Settings.ClassCompletion.BodyStubs);
  Settings := Parse('{"classCompletion": {"typeComment": "kasten"}}', Issues);
  Assert.AreEqual('brace', Settings.ClassCompletion.TypeComment, 'Unbekanntes bleibt bei der Vorgabe');
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsTrue(Issues[0].IsError);
end;
procedure TConfigurationParserTests.ReadsReferences;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.References.Inferred);
  Assert.IsFalse(Settings.References.TextMatches);
  Settings := Parse('{"references": {"inferred": false, "textMatches": true}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.References.Inferred);
  Assert.IsTrue(Settings.References.TextMatches);
  Settings := Parse('{"references": {"inferred": 1, "x": true}}', Issues);
  Assert.IsTrue(Settings.References.Inferred);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Assert.IsTrue(Issues[0].IsError);
  Assert.IsFalse(Issues[1].IsError);
  Parse('{"references": true}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Die Datei ersetzt den Block aus dem Editor.
  Settings := TConfigurationParser.ParseLayered('{"references": {"inferred": false}}', '{"references": {}}', Issues);
  Assert.IsTrue(Settings.References.Inferred);
end;
procedure TConfigurationParserTests.ReadsNavigationImpact;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Navigation.Impact);
  Assert.AreEqual(2, Settings.Navigation.ImpactDepth);
  Settings := Parse('{"navigation": {"impact": false, "impactDepth": 4}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Navigation.Impact);
  Assert.AreEqual(4, Settings.Navigation.ImpactDepth);
  // Außerhalb von 1 bis 5 bleibt die Vorgabe; unbekannte Schlüssel sind Warnungen.
  Settings := Parse('{"navigation": {"impactDepth": 9, "x": 1}}', Issues);
  Assert.AreEqual(2, Settings.Navigation.ImpactDepth);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Assert.IsTrue(Issues[0].IsError);
  Assert.IsFalse(Issues[1].IsError);
  Parse('{"navigation": true}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"navigation": {"impactDepth": 5}}', '{"navigation": {}}', Issues);
  Assert.AreEqual(2, Settings.Navigation.ImpactDepth);
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
end;
procedure TConfigurationParserTests.MetricsSwitchesOffMetricRules;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
  Length_, Other: TRuleDescriptor;
begin
  Length_ := TRuleDescriptor.Create('metric-method-length', TRuleSeverity.Warning, 'Länge');
  Other := TRuleDescriptor.Create('empty-except', TRuleSeverity.Warning, 'Leer');
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Metrics, 'Kennzahlen standardmäßig an');
  Assert.AreNotEqual(Ord(TRuleSeverity.Off), Ord(TRuleEngine.EffectiveSeverity(Length_, Settings, '')));
  Settings := Parse('{"metrics": false}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Metrics);
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(TRuleEngine.EffectiveSeverity(Length_, Settings, '')));
  Assert.AreNotEqual(Ord(TRuleSeverity.Off), Ord(TRuleEngine.EffectiveSeverity(Other, Settings, '')),
    'andere Regeln bleiben');
  // Das Projekt setzt die Regel ausdrücklich: sie gilt trotz des globalen Schalters.
  Settings := Parse('{"metrics": false, "rules": {"metric-method-length": "error"}}', Issues);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(TRuleEngine.EffectiveSeverity(Length_, Settings, '')));
  Parse('{"metrics": 1}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;
procedure TConfigurationParserTests.ChecksMetricLimitOption;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"rules": {"metric-cyclomatic-complexity": {"severity": "warning", "max": 10}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('{"severity": "warning", "max": 10}', Settings.Rules[0].Options);
  Parse('{"rules": {"metric-method-length": {"max": 0}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"max"');
  Parse('{"rules": {"metric-method-length": {"max": "80"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Parse('{"rules": {"metric-method-length": {"max": 2.5}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // minLines von commented-out-code (#942).
  Parse('{"rules": {"commented-out-code": {"minLines": 5}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"rules": {"commented-out-code": {"minLines": 0}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"minLines"');
  // minRecordSize und ignoreOverrides von managed-param-without-const (#975).
  Parse('{"rules": {"managed-param-without-const": {"minRecordSize": 32, "ignoreOverrides": false}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"rules": {"managed-param-without-const": {"minRecordSize": 0}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"minRecordSize"');
  Parse('{"rules": {"managed-param-without-const": {"ignoreOverrides": "nein"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"ignoreOverrides"');
  // requirePublic und checkReturns von xmldoc-mismatch (#979).
  Parse('{"rules": {"xmldoc-mismatch": {"requirePublic": true, "checkReturns": false}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"rules": {"xmldoc-mismatch": {"checkReturns": "nein"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"checkReturns"');
  // allowTypes von unrelated-class-cast (#1129).
  Parse('{"rules": {"unrelated-class-cast": {"allowTypes": ["TEdit=TButton", "THackControl"]}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"rules": {"unrelated-class-cast": {"allowTypes": "TEdit"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"allowTypes"');
  // formatMethods von format-args (#56).
  Parse('{"rules": {"format-args": {"formatMethods": ["TLogger.LogFmt", "Protokoll"]}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"rules": {"format-args": {"formatMethods": "Protokoll"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"formatMethods"');
  // checkFree von redundant-cast (#1139).
  Parse('{"rules": {"redundant-cast": {"checkFree": false}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"rules": {"redundant-cast": {"checkFree": "nein"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"checkFree"');
  // allowFirstElement von loop-runs-at-most-once (#1131).
  Parse('{"rules": {"loop-runs-at-most-once": {"allowFirstElement": true}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"rules": {"loop-runs-at-most-once": {"allowFirstElement": "ja"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"allowFirstElement"');
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
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"rules": {"todo-comment": {"severity": "hint", "keywords": ["TODO", "hack"]}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('{"severity": "hint", "keywords": ["TODO", "hack"]}', Settings.Rules[0].Options);
  Parse('{"rules": {"todo-comment": {"keywords": "TODO"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"keywords"');
  // DONE ist die Marke der erledigten Einträge; Zeichen außer Buchstaben passen nicht zum ersten Wort.
  Parse('{"rules": {"todo-comment": {"keywords": ["DONE", "TO-DO", "", 1, "XXX"]}}}', Issues);
  Assert.AreEqual(4, Integer(Length(Issues)));
end;
procedure TServerSettingsTests.RuleSeverityFallsBackToDefault;
var
  Settings: TServerSettings;
begin
  Settings := TServerSettings.Default;
  Assert.IsTrue(Settings.RuleSeverity('x', TRuleSeverity.Error) = TRuleSeverity.Error);
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
  Settings: TServerSettings;
begin
  Settings := TServerSettings.Default;
  Settings.Exclude := ['Vendor', 'Tools/'];
  Assert.IsTrue(Settings.IsExcluded('Vendor\A.pas'));
  Assert.IsTrue(Settings.IsExcluded('./Tools/B.pas'));
  Assert.IsFalse(Settings.IsExcluded('Source\Vendor.pas'));
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
  Dir: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'Atlas.Tests.' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  try
    // Ohne Datei: der neue Name, damit dort angelegt wird.
    Assert.AreEqual(TPath.Combine(Dir, 'atlas.json'), ExistingOrLegacyFile(Dir, 'atlas.json', 'delphi-lsp.json'));
    TFile.WriteAllText(TPath.Combine(Dir, 'delphi-lsp.json'), '{}');
    Assert.AreEqual(TPath.Combine(Dir, 'delphi-lsp.json'), ExistingOrLegacyFile(Dir, 'atlas.json', 'delphi-lsp.json'));
    TFile.WriteAllText(TPath.Combine(Dir, 'atlas.json'), '{}');
    Assert.AreEqual(TPath.Combine(Dir, 'atlas.json'), ExistingOrLegacyFile(Dir, 'atlas.json', 'delphi-lsp.json'));
  finally
    TDirectory.Delete(Dir, True);
  end;
end;
procedure TServerSettingsTests.ReadsDelphiProductNumbers;
var
  Issues: TArray<TConfigurationIssue>;
begin
  // "12" ist Delphi 12 (BDS 23.0), nicht BDS 12.0 (Delphi 2009).
  Assert.AreEqual('23.0', BdsVersionOf('12'));
  Assert.AreEqual('37.0', BdsVersionOf('13'));
  Assert.AreEqual('20.0', BdsVersionOf('10.3'));
  Assert.AreEqual('17.0', BdsVersionOf('10'));
  Assert.AreEqual('23.0', BdsVersionOf('23.0'));
  Assert.AreEqual('', BdsVersionOf('9'));
  Assert.AreEqual('', BdsVersionOf('neu'));
  Assert.AreEqual('23.0', Parse('{"delphiVersion": "12"}', Issues).DelphiVersion);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('', Parse('{"delphiVersion": "7"}', Issues).DelphiVersion);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Unbekannte BDS-Nummer (#109).
  Assert.AreEqual('', BdsVersionOf('99'));
  Assert.AreEqual('', BdsVersionOf('30.0'));
  Assert.AreEqual('', Parse('{"delphiVersion": "99"}', Issues).DelphiVersion);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('19.0', Parse('{"delphiVersion": "10.2"}', Issues).DelphiVersion);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;
procedure TServerSettingsTests.ReadsMinDelphiVersion;
var
  Issues: TArray<TConfigurationIssue>;
begin
  // #1126: älteste Version, mit der das Projekt übersetzen muss; Produktnummern wie bei delphiVersion.
  Assert.AreEqual('', Parse('{}', Issues).MinDelphiVersion);
  Assert.AreEqual('23.0', Parse('{"minDelphiVersion": "12"}', Issues).MinDelphiVersion);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('22.0', Parse('{"minDelphiVersion": "22.0"}', Issues).MinDelphiVersion);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('', Parse('{"minDelphiVersion": "7"}', Issues).MinDelphiVersion);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Die globale delphiVersion bleibt davon unberührt.
  Assert.AreEqual('', Parse('{"minDelphiVersion": "12"}', Issues).DelphiVersion);
end;
procedure TServerSettingsTests.ReadsSortUses;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.IsFalse(Parse('{}', Issues).SortUses);
  Assert.IsTrue(Parse('{"sortUses": true}', Issues).SortUses);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;
procedure TServerSettingsTests.ReadsFixMinConfidence;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Parse('{}', Issues).FixMinConfidence));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Parse('{"fix": {"minConfidence": "medium"}}',
    Issues).FixMinConfidence));
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Niedrige Konfidenz ist für Sammelkorrekturen nie erlaubt; die Vorgabe bleibt.
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Parse('{"fix": {"minConfidence": "low"}}',
    Issues).FixMinConfidence));
  Assert.AreEqual(1, Integer(Length(Issues)));
  Parse('{"fix": {"bulk": true}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Parse('{"fix": "high"}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;
initialization
  TDUnitX.RegisterTestFixture(TConfigurationParserTests);
  TDUnitX.RegisterTestFixture(TServerSettingsTests);

end.
