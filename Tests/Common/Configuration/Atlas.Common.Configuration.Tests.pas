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
    procedure ReadsArchitectureComparisonSettings;
    [Test]
    procedure ReadsNavigationSymbolPath;
    [Test]
    procedure ReadsAllSettings;
    [Test]
    procedure EmptyObjectGivesDefaults;
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
    /// <summary>"references" (#1119): erschlossene Treffer an, Textfunde aus.</summary>
    [Test]
    procedure ReadsReferences;
    [Test]
    procedure ReadsNavigationImpact;
    [Test]
    procedure MetricsSwitchesOffMetricRules;
    [Test]
    procedure ChecksMetricLimitOption;
    [Test]
    procedure ChecksTodoKeywordsOption;
    [Test]
    procedure ChecksForbiddenSymbolsOption;
    [Test]
    procedure ReadsHints;
    [Test]
    procedure ReadsMcpDisabledTools;
    [Test]
    procedure ReadsMcpGlobalSettings;
    /// <summary>#900: Abschnitt "tasks" (Projektaufgaben des Plugins) wird geprüft, nicht gemeldet.</summary>
    [Test]
    procedure ChecksTasks;
    /// <summary>#1260: issues.connections (Tracker-Verbindungen des Plugins) wird geprüft: nur https, ohne
    /// Benutzer, eindeutige Namen.</summary>
    [Test]
    procedure ChecksIssueConnections;
    /// <summary>#1261: issues.projects (Zuordnung Delphi-Projekt → Tracker-Projekt) wird geprüft: match und
    /// connection nötig, ein Pfad nur einmal (ohne Groß-/Kleinschreibung, „/“ wie „\“).</summary>
    [Test]
    procedure ChecksIssueProjects;
    /// <summary>#1262: issues.queries mit Name und Abfrage, doppelte Namen und fehlende Angaben gemeldet.</summary>
    [Test]
    procedure ChecksIssueQueries;
    [Test]
    procedure ReadsStringLiteral;
    [Test]
    procedure ReadsDirectives;
    [Test]
    procedure ReadsMemberOrder;
    [Test]
    procedure ReadsTestUnits;
    [Test]
    procedure ReadsDfmPropertyRules;
    [Test]
    procedure ReadsCompilerSettings;
    [Test]
    procedure ReadsVcsProvider;
    [Test]
    procedure ReadsFormatSettings;
    [Test]
    procedure FileOverridesEditorPerKey;
    [Test]
    procedure MergesRulesPerId;
    [Test]
    procedure EditorOrFileAlone;
    [Test]
    procedure ReadsDefaultEncoding;
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
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser;

function Parse(const AText: string; out AIssues: TArray<TConfigurationIssue>): TServerSettings;
begin
  Result := TConfigurationParser.Parse(AText, AIssues);
end;

{ TConfigurationParserTests }

procedure TConfigurationParserTests.FileOverridesEditorPerKey;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  Settings := TConfigurationParser.ParseLayered(
    '{"serverPath": "C:\\Bin\\AtlasServer.exe", "platform": "Win32", "config": "Release", "language": "en"}',
    '{ // Datei gewinnt'#10' "platform": "Win64", "language": "de" }', Issues);
  Assert.AreEqual('Win64', Settings.Platform);
  Assert.AreEqual('de', Settings.Language);
  Assert.AreEqual('Release', Settings.Config);
  // Unbekannte Editor-Schlüssel wie serverPath erzeugen keine Meldung.
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

procedure TConfigurationParserTests.MergesRulesPerId;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  Settings := TConfigurationParser.ParseLayered(
    '{"rules": {"with-statement": "error", "unused-variable": "hint"}}',
    '{"rules": {"with-statement": "off"}}', Issues);
  Assert.IsTrue(Settings.RuleSeverity('with-statement', TRuleSeverity.Warning) = TRuleSeverity.Off);
  Assert.IsTrue(Settings.RuleSeverity('unused-variable', TRuleSeverity.Warning) = TRuleSeverity.Hint);
end;

procedure TConfigurationParserTests.EditorOrFileAlone;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual('Win32', TConfigurationParser.ParseLayered('{"platform": "Win32"}', '', Issues).Platform);
  Assert.AreEqual('Win64', TConfigurationParser.ParseLayered('', '{"platform": "Win64"}', Issues).Platform);
  Assert.AreEqual('de', TConfigurationParser.ParseLayered('', '', Issues).Language);
  // Meldungen gelten nur der Datei.
  TConfigurationParser.ParseLayered('{"language": "fr"}', '{"language": "xx"}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

procedure TConfigurationParserTests.ReadsDefaultEncoding;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(65001, Parse('{}', Issues).DefaultEncoding);
  Assert.AreEqual(1250, Parse('{"encoding": "windows-1250"}', Issues).DefaultEncoding);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(65001, Parse('{"encoding": "utf-8"}', Issues).DefaultEncoding);
  // Unbekannte Kodierung: Meldung, es bleibt UTF-8.
  Assert.AreEqual(65001, Parse('{"encoding": "klingonisch"}', Issues).DefaultEncoding);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // atlas.json hat Vorrang vor dem Editor.
  Assert.AreEqual(1252, TConfigurationParser.ParseLayered('{"encoding": "1250"}', '{"encoding": "cp1252"}',
    Issues).DefaultEncoding);
  Assert.AreEqual(1250, TConfigurationParser.ParseLayered('{"encoding": "1250"}', '{}', Issues).DefaultEncoding);
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
  Settings := Parse('{"architecture": {"centralUnits": 101}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Parse('{"architecture": []}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"architecture": {"centralUnits": 30}}',
    '{"architecture": {"exclude": ["Demo/**"]}}', Issues);
  Assert.AreEqual(1, Integer(Length(Settings.ArchitectureExclude)));
end;

procedure TConfigurationParserTests.MergesLayersPerKey;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
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
  Settings := TConfigurationParser.Parse(TConfigurationParser.MergeText('{"format": {"indentSize": 4, ' +
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
  Assert.AreEqual('de', Settings.Language);
  Assert.AreEqual('', Settings.DelphiVersion);
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
  Assert.AreEqual('de', Settings.Language);
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

{ TServerSettingsTests }

procedure TConfigurationParserTests.ReadsFormatSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual(2, Settings.Formatting.IndentSize);
  Assert.IsTrue(Settings.Formatting.Given = []);
  Settings := Parse('{"format": {"useTabs": true, "keywordCase": "lower", "endOfLine": "crlf", ' +
    '"spaceAfterComma": false}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Settings.Formatting.UseTabs);
  Assert.IsTrue(Settings.Formatting.KeywordCase = TKeywordCase.Lower);
  Assert.AreEqual(#13#10, Settings.Formatting.EndOfLine);
  Assert.IsFalse(Settings.Formatting.SpaceAfterComma);
  Assert.IsTrue(Settings.Formatting.Given = [TFormatKey.UseTabs, TFormatKey.KeywordCase, TFormatKey.EndOfLine,
    TFormatKey.SpaceAfterComma]);
  Settings := Parse('{"format": {"indentSize": 0, "keywordCase": "camel", "x": 1}}', Issues);
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.IsTrue(Settings.Formatting.Given = []);
  // Blockstruktur, Stellung, Umbruch und Ausrichtung (#43).
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Formatting.Reindent);
  Assert.IsTrue(Settings.Formatting.BeginPlacement = TBlockPlacement.Preserve);
  Assert.AreEqual(0, Settings.Formatting.MaxLineLength);
  Settings := Parse('{"format": {"reindent": false, "beginPlacement": "newLine", "elsePlacement": "sameLine", ' +
    '"maxLineLength": 100, "alignAssignments": true, "alignDeclarations": true, "alignComments": true}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Formatting.Reindent);
  Assert.IsTrue(Settings.Formatting.BeginPlacement = TBlockPlacement.NewLine);
  Assert.IsTrue(Settings.Formatting.ElsePlacement = TBlockPlacement.SameLine);
  Assert.AreEqual(100, Settings.Formatting.MaxLineLength);
  Assert.IsTrue(Settings.Formatting.AlignAssignments);
  Assert.IsTrue(Settings.Formatting.AlignDeclarations);
  Assert.IsTrue(Settings.Formatting.AlignComments);
  Assert.IsTrue(Settings.Formatting.Given = [TFormatKey.MaxLineLength]);
  Settings := Parse('{"format": {"beginPlacement": "below", "maxLineLength": -1}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
end;

procedure TConfigurationParserTests.ReadsVcsProvider;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Versionsverwaltung (#571): Vorgabe auto.
  Settings := Parse('{}', Issues);
  Assert.AreEqual('auto', Settings.VcsProvider);
  Settings := Parse('{"vcs": {"provider": "svn"}}', Issues);
  Assert.AreEqual('svn', Settings.VcsProvider);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Settings := Parse('{"vcs": {"provider": "cvs", "x": 1}}', Issues);
  Assert.AreEqual('auto', Settings.VcsProvider, 'unbekannter Wert bleibt bei der Vorgabe');
  Assert.AreEqual(2, Integer(Length(Issues)));
  Parse('{"vcs": "git"}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'vcs muss ein Objekt sein');
  Settings := TConfigurationParser.ParseLayered('{"vcs": {"provider": "git"}}', '{"vcs": {"provider": "off"}}',
    Issues);
  Assert.AreEqual('off', Settings.VcsProvider, 'Datei vor Editor');
  Settings := TConfigurationParser.ParseLayered('', '{"vcs": {"provider": "git"}}', Issues);
  Assert.AreEqual('git', Settings.VcsProvider);
end;

procedure TConfigurationParserTests.ReadsCompilerSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Vorgabe aus: Das Plugin wählt „Nach dem Speichern“ selbst.
  Settings := Parse('{}', Issues);
  Assert.IsFalse(Settings.Compiler.OnSave);
  Settings := Parse('{"compiler": {"onSave": true}}', Issues);
  Assert.IsTrue(Settings.Compiler.OnSave);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Settings := Parse('{"compiler": {"onSave": "nein", "x": 1}}', Issues);
  Assert.IsFalse(Settings.Compiler.OnSave);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"compiler": {"onSave": true}}', '{}', Issues);
  Assert.IsTrue(Settings.Compiler.OnSave);
  // Weg zum Compiler (#261): Vorgabe auto ohne cc.ps1.
  Settings := Parse('{}', Issues);
  Assert.AreEqual(Ord(TCompilerBackendSetting.Auto), Ord(Settings.Compiler.Backend));
  Assert.AreEqual('', Settings.Compiler.IdeCommand);
  Settings := Parse('{"compiler": {"backend": "ide", "ideCommand": "C:\\Tools\\cc.ps1"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(Ord(TCompilerBackendSetting.Ide), Ord(Settings.Compiler.Backend));
  Assert.AreEqual('C:\Tools\cc.ps1', Settings.Compiler.IdeCommand);
  Settings := Parse('{"compiler": {"backend": "off"}}', Issues);
  Assert.AreEqual(Ord(TCompilerBackendSetting.Off), Ord(Settings.Compiler.Backend));
  Settings := Parse('{"compiler": {"backend": "dcc"}}', Issues);
  Assert.AreEqual(Ord(TCompilerBackendSetting.Dcc), Ord(Settings.Compiler.Backend));
  Settings := Parse('{"compiler": {"backend": "msbuild", "ideCommand": 3}}', Issues);
  Assert.AreEqual(Ord(TCompilerBackendSetting.Auto), Ord(Settings.Compiler.Backend), 'ungültig = Vorgabe');
  Assert.AreEqual(2, Integer(Length(Issues)));
  // Schnellbefehle (#293)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.SlashCommands);
  Assert.AreEqual(0, Integer(Length(Settings.SlashCommandsDisabled)));
  Settings := Parse('{"slashCommands": {"enabled": false, "disabled": ["uses", "var"]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.SlashCommands);
  Assert.AreEqual('var', Settings.SlashCommandsDisabled[1]);
  Parse('{"slashCommands": {"disabled": "uses", "x": 1}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"slashCommands": {"disabled": ["uses"]}}', '{}', Issues);
  Assert.AreEqual(1, Integer(Length(Settings.SlashCommandsDisabled)));
  // Alias usesCommand aus #254: Vorgabe an, false schaltet /uses ab, atlas.json überdeckt den Editor.
  Assert.IsTrue(Parse('{}', Issues).UsesCommand);
  Settings := Parse('{"usesCommand": false}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.UsesCommand);
  Parse('{"usesCommand": "nein"}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"usesCommand": true}', '{"usesCommand": false}', Issues);
  Assert.IsFalse(Settings.UsesCommand, 'atlas.json gilt vor den Editor-Einstellungen');
  // Gerüst des Dokumentationskommentars (#88)
  Assert.IsTrue(Parse('{}', Issues).CompleteBlocksDocComment);
  Settings := Parse('{"completeBlocks": {"docComment": false}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.CompleteBlocksDocComment);
  Parse('{"completeBlocks": {"docComment": 1, "x": true}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Parse('{"completeBlocks": true}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"completeBlocks": {"docComment": false}}', '{}', Issues);
  Assert.IsFalse(Settings.CompleteBlocksDocComment);
  // Protokollaufruf für /log und /except (#304)
  Assert.AreEqual('', Parse('{}', Issues).SlashLogCall);
  Settings := Parse('{"slashCommands": {"logCall": "Log.Debug"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('Log.Debug', Settings.SlashLogCall);
  Settings := Parse('{"slashCommands": {"logCall": 3}}', Issues);
  Assert.AreEqual('', Settings.SlashLogCall);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"slashCommands": {"logCall": "Log.Debug"}}', '{}', Issues);
  Assert.AreEqual('Log.Debug', Settings.SlashLogCall);
  // Palettenseite für /component (#299)
  Assert.AreEqual('Eigene', Parse('{}', Issues).SlashComponentPalette);
  Assert.AreEqual('Firma', Parse('{"slashCommands": {"componentPalette": "Firma"}}', Issues).SlashComponentPalette);
  // #297: Name und Kategorie für /todo, ungenutzte uses bei /sortuses.
  Settings := Parse('{"slashCommands": {"todoOwner": "Marco", "todoCategory": "Review", ' +
    '"sortUsesRemoveUnused": false}}', Issues);
  Assert.AreEqual('Marco', Settings.SlashTodoOwner);
  Assert.AreEqual('Review', Settings.SlashTodoCategory);
  Assert.IsFalse(Settings.SlashSortUsesRemoveUnused);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{}', Issues).SlashSortUsesRemoveUnused);
  Assert.AreEqual('', Parse('{}', Issues).SlashTodoOwner);
  // #875: /helper für Aufzählungen
  Assert.IsTrue(Parse('{}', Issues).SlashEnumHelper);
  Assert.IsFalse(Parse('{"slashCommands": {"enumHelper": false}}', Issues).SlashEnumHelper);
  Assert.IsFalse(TConfigurationParser.ParseLayered('{"slashCommands": {"enumHelper": false}}', '{}',
    Issues).SlashEnumHelper);
  Assert.IsTrue(Parse('{}', Issues).SlashSetHelper);
  Assert.IsFalse(Parse('{"slashCommands": {"setHelper": false}}', Issues).SlashSetHelper);
  Assert.IsFalse(TConfigurationParser.ParseLayered('{"slashCommands": {"setHelper": false}}', '{}',
    Issues).SlashSetHelper);
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Vervollständigung (#229)
  Assert.IsTrue(Parse('{}', Issues).Completion.Matching = TCompletionMatching.Fuzzy);
  Assert.IsTrue(Parse('{"completion": {"matching": "prefix"}}', Issues).Completion.Matching = TCompletionMatching.Prefix);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{"completion": {"matching": "egal", "x": 1}}', Issues).Completion.Matching = TCompletionMatching.Fuzzy);
  Assert.AreEqual(2, Integer(Length(Issues)));
  // Abschnitt für Interface-Methoden (#466)
  Assert.IsTrue(Parse('{}', Issues).Completion.InterfaceSection = TCompletionInterfaceSection.Public);
  Assert.IsTrue(Parse('{"completion": {"interfaceSection": "protected"}}', Issues).Completion.InterfaceSection =
    TCompletionInterfaceSection.Protected);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{"completion": {"interfaceSection": "strict"}}', Issues).Completion.InterfaceSection =
    TCompletionInterfaceSection.Public);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Typumwandlung von Sender (#480)
  Assert.IsTrue(Parse('{}', Issues).Completion.SenderCast = TCompletionSenderCast.AsOperator);
  Assert.IsTrue(Parse('{"completion": {"senderCast": "cast"}}', Issues).Completion.SenderCast =
    TCompletionSenderCast.HardCast);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{"completion": {"senderCast": "hart"}}', Issues).Completion.SenderCast =
    TCompletionSenderCast.AsOperator);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Typkonvertierung vorschlagen (#490, experimentell)
  Assert.IsTrue(Parse('{}', Issues).Completion.TypeConversion = TCompletionTypeConversion.Off);
  Assert.IsTrue(Parse('{"completion": {"typeConversion": "helper"}}', Issues).Completion.TypeConversion =
    TCompletionTypeConversion.Helper);
  Assert.IsTrue(Parse('{"completion": {"typeConversion": "function"}}', Issues).Completion.TypeConversion =
    TCompletionTypeConversion.Function_);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{"completion": {"typeConversion": "immer"}}', Issues).Completion.TypeConversion =
    TCompletionTypeConversion.Off);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Alle Felder zuweisen (#491, experimentell)
  Assert.IsFalse(Parse('{}', Issues).Completion.AssignAllFields);
  Assert.IsTrue(Parse('{"completion": {"assignAllFields": true}}', Issues).Completion.AssignAllFields);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"assignAllFields": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // uses-Vervollständigung mit Gruppen und Hinweisen (#469)
  Assert.IsTrue(Parse('{}', Issues).Completion.UsesDetails);
  Assert.IsFalse(Parse('{"completion": {"usesDetails": false}}', Issues).Completion.UsesDetails);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"usesDetails": "ja"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Vollständiger inherited-Aufruf (#482)
  Assert.IsTrue(Parse('{}', Issues).Completion.InheritedCall);
  Assert.IsFalse(Parse('{"completion": {"inheritedCall": false}}', Issues).Completion.InheritedCall);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"inheritedCall": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Attribute nach "[" (#465)
  Assert.IsTrue(Parse('{}', Issues).Completion.Attributes);
  Assert.IsFalse(Parse('{"completion": {"attributes": false}}', Issues).Completion.Attributes);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"attributes": "ja"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Anonyme Methoden (#468)
  Assert.IsTrue(Parse('{}', Issues).Completion.AnonymousMethods);
  Assert.IsFalse(Parse('{"completion": {"anonymousMethods": false}}', Issues).Completion.AnonymousMethods);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"anonymousMethods": 0}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Herkunft in with-Blöcken (#481)
  Assert.IsTrue(Parse('{}', Issues).Completion.WithOrigin);
  Assert.IsFalse(Parse('{"completion": {"withOrigin": false}}', Issues).Completion.WithOrigin);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"withOrigin": "nein"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Exception-Klassen (#483)
  Assert.IsTrue(Parse('{}', Issues).Completion.ExceptionClasses);
  Assert.IsFalse(Parse('{"completion": {"exceptionClasses": false}}', Issues).Completion.ExceptionClasses);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"exceptionClasses": []}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Hinweis bei unvollständigem Code (#457)
  Assert.IsTrue(Parse('{}', Issues).Completion.SyntaxNotice);
  Assert.IsFalse(Parse('{"completion": {"syntaxNotice": false}}', Issues).Completion.SyntaxNotice);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"syntaxNotice": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Gleiche Namen aus verschiedenen Units (#475)
  Assert.IsTrue(Parse('{}', Issues).Completion.SameNameVariants);
  Assert.IsTrue(Parse('{}', Issues).Completion.SameNameInsert = TCompletionSameNameInsert.Prefix);
  Assert.IsFalse(Parse('{}', Issues).Completion.ShowFmxUnits);
  Assert.IsFalse(Parse('{"completion": {"sameNameVariants": false}}', Issues).Completion.SameNameVariants);
  Assert.IsTrue(Parse('{"completion": {"sameNameInsert": "uses"}}', Issues).Completion.SameNameInsert =
    TCompletionSameNameInsert.Uses_);
  Assert.IsTrue(Parse('{"completion": {"showFmxUnits": true}}', Issues).Completion.ShowFmxUnits);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"sameNameInsert": "move"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Freigabe absichern (#489)
  Assert.IsTrue(Parse('{}', Issues).Completion.OfferTryFinally);
  Assert.IsTrue(Parse('{}', Issues).Completion.FreeStyle = TCompletionFreeStyle.Free);
  Assert.IsFalse(Parse('{"completion": {"offerTryFinally": false}}', Issues).Completion.OfferTryFinally);
  Assert.IsTrue(Parse('{"completion": {"freeStyle": "freeAndNil"}}', Issues).Completion.FreeStyle =
    TCompletionFreeStyle.FreeAndNil);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"freeStyle": "nil"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Schlüsselwörter (#31)
  Assert.IsTrue(Parse('{}', Issues).Completion.Keywords);
  Assert.IsFalse(Parse('{"completion": {"keywords": false}}', Issues).Completion.Keywords);
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Postfix-Vorlagen und Inline-Variablen (#188)
  Assert.IsTrue(Parse('{}', Issues).Completion.PostfixTemplates);
  Assert.IsFalse(Parse('{"completion": {"postfixTemplates": false}}', Issues).Completion.PostfixTemplates);
  // Typargumente nach den Constraints (#450)
  Assert.IsTrue(Parse('{}', Issues).Completion.GenericConstraints);
  Assert.IsFalse(Parse('{"completion": {"genericConstraints": false}}', Issues).Completion.GenericConstraints);
  // Namensvorschläge (#452)
  Assert.IsTrue(Parse('{}', Issues).Completion.NameSuggestions);
  Assert.IsFalse(Parse('{"completion": {"nameSuggestions": false}}', Issues).Completion.NameSuggestions);
  // Feld und Zugriffsmethoden nach read/write (#467)
  Assert.IsTrue(Parse('{}', Issues).Completion.CreateAccessors);
  Assert.IsFalse(Parse('{"completion": {"createAccessors": false}}', Issues).Completion.CreateAccessors);
  Assert.IsTrue(Parse('{}', Issues).Completion.AccessorSection = TCompletionAccessorSection.Private);
  Assert.IsTrue(Parse('{"completion": {"accessorSection": "protected"}}', Issues).Completion.AccessorSection =
    TCompletionAccessorSection.Protected);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{"completion": {"accessorSection": "public"}}', Issues).Completion.AccessorSection =
    TCompletionAccessorSection.Private);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // String als resourcestring auslagern (#473)
  Assert.IsTrue(Parse('{}', Issues).Completion.ResourceStrings);
  Assert.IsFalse(Parse('{"completion": {"resourceStrings": false}}', Issues).Completion.ResourceStrings);
  Assert.AreEqual('', Parse('{}', Issues).Completion.ResourceStringUnit);
  Assert.AreEqual('App.Texte', Parse('{"completion": {"resourceStringUnit": "App.Texte"}}',
    Issues).Completion.ResourceStringUnit);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('', Parse('{"completion": {"resourceStringUnit": "App Texte"}}',
    Issues).Completion.ResourceStringUnit);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{}', Issues).Refactoring.InlineVar);
  Assert.IsFalse(Parse('{"refactoring": {"inlineVar": false}}', Issues).Refactoring.InlineVar);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"refactoring": {"inlineVars": false}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Signatur ändern (#100)
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ChangeSignature);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.NewParameterOverload);
  Assert.IsFalse(Parse('{}', Issues).Refactoring.VirtualOverload);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.SyncSignatures);
  Assert.IsFalse(Parse('{"refactoring": {"changeSignature": false}}', Issues).Refactoring.ChangeSignature);
  Assert.IsFalse(Parse('{"refactoring": {"newParameter": "updateCallers"}}', Issues).Refactoring.NewParameterOverload);
  Assert.IsTrue(Parse('{"refactoring": {"virtualOverload": true}}', Issues).Refactoring.VirtualOverload);
  Assert.IsFalse(Parse('{"refactoring": {"syncSignatures": false}}', Issues).Refactoring.SyncSignatures);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ForwardDeclaration);
  Assert.IsFalse(Parse('{"refactoring": {"forwardDeclaration": false}}', Issues).Refactoring.ForwardDeclaration);
  // try/finally und Klassen-Aktionen (#42)
  Assert.IsTrue(Parse('{}', Issues).Refactoring.TryFinally);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ClassActions);
  Assert.IsFalse(Parse('{"refactoring": {"tryFinally": false}}', Issues).Refactoring.TryFinally);
  Assert.IsFalse(Parse('{"refactoring": {"classActions": false}}', Issues).Refactoring.ClassActions);
  // Typ ausschreiben (#453)
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ExplicitType);
  Assert.IsFalse(Parse('{"refactoring": {"explicitType": false}}', Issues).Refactoring.ExplicitType);
  // Schnellkorrekturen an Compilermeldungen (#549)
  Assert.IsTrue(Parse('{}', Issues).Refactoring.CompilerFixes);
  Assert.IsFalse(Parse('{"refactoring": {"compilerFixes": false}}', Issues).Refactoring.CompilerFixes);
  // Unit nicht gefunden: Suchpfad ergänzen (#550)
  Assert.IsTrue(Parse('{}', Issues).Refactoring.MissingUnit);
  Assert.IsFalse(Parse('{"refactoring": {"missingUnit": false}}', Issues).Refactoring.MissingUnit);
  // Warnung gezielt abschalten (#531)
  Assert.IsTrue(Parse('{}', Issues).Refactoring.DisableWarning);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.DisableWarningReason);
  Assert.IsFalse(Parse('{"refactoring": {"disableWarning": false}}', Issues).Refactoring.DisableWarning);
  Assert.IsFalse(Parse('{"refactoring": {"disableWarningReason": false}}', Issues).Refactoring.DisableWarningReason);
  // #50: Extrahieren, case vervollständigen und with auflösen.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.Extract);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.CompleteCase);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ResolveWith);
  Assert.IsFalse(Parse('{"refactoring": {"extract": false}}', Issues).Refactoring.Extract);
  Assert.IsFalse(Parse('{"refactoring": {"completeCase": false}}', Issues).Refactoring.CompleteCase);
  Assert.IsFalse(Parse('{"refactoring": {"resolveWith": false}}', Issues).Refactoring.ResolveWith);
  // #103: Einbetten, experimentell und daher aus.
  Assert.IsFalse(Parse('{}', Issues).Refactoring.InlineCode);
  Assert.IsTrue(Parse('{"refactoring": {"inline": true}}', Issues).Refactoring.InlineCode);
  Assert.IsFalse(Parse('{}', Issues).Refactoring.MoveClass);
  Assert.IsTrue(Parse('{"refactoring": {"moveClass": true}}', Issues).Refactoring.MoveClass);
  // #512: uses nachziehen, experimentell und daher "off".
  Assert.IsFalse(Parse('{}', Issues).Refactoring.UnitRenameFollowUp);
  Assert.IsTrue(Parse('{"refactoring": {"unitRenameFollowUp": "ask"}}', Issues).Refactoring.UnitRenameFollowUp);
  Assert.IsFalse(Parse('{"refactoring": {"unitRenameFollowUp": "off"}}', Issues).Refactoring.UnitRenameFollowUp);
  Parse('{"refactoring": {"unitRenameFollowUp": "yes"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #472: Methode aus Aufruf anlegen.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.CreateMethod);
  Assert.AreEqual('private', Parse('{}', Issues).Refactoring.CreateMethodSection);
  Assert.IsFalse(Parse('{}', Issues).Refactoring.CreateMethodCaretInBody);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ConstParameters);
  Assert.IsFalse(Parse('{"refactoring": {"createMethod": false}}', Issues).Refactoring.CreateMethod);
  Assert.AreEqual('protected', Parse('{"refactoring": {"createMethodSection": "Protected"}}',
    Issues).Refactoring.CreateMethodSection);
  Assert.IsTrue(Parse('{"refactoring": {"createMethodCaret": "body"}}', Issues).Refactoring.CreateMethodCaretInBody);
  Assert.IsFalse(Parse('{"refactoring": {"constParameters": false}}', Issues).Refactoring.ConstParameters);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"refactoring": {"newParameter": "default"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Parse('{"refactoring": {"createMethodSection": "published", "createMethodCaret": "ende"}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  // #682: Property aus Getter und Setter.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.PropertyFromAccessors);
  Assert.AreEqual('Get|Set|Is|Has', string.Join('|', Parse('{}', Issues).Refactoring.PropertyFromAccessorsPrefixes));
  Assert.AreEqual('ask', Parse('{}', Issues).Refactoring.PropertyFromAccessorsReplaceCalls);
  Assert.AreEqual('accessor', Parse('{}', Issues).Refactoring.PropertyFromAccessorsSection);
  Assert.AreEqual('off', Parse('{}', Issues).Refactoring.PropertyFromAccessorsHideAccessors);
  Assert.IsFalse(Parse('{"refactoring": {"propertyFromAccessors": false}}', Issues).Refactoring.PropertyFromAccessors);
  Assert.AreEqual('Read|Write', string.Join('|', Parse('{"refactoring": {"propertyFromAccessorsPrefixes": ' +
    '["Read", " Write ", ""]}}', Issues).Refactoring.PropertyFromAccessorsPrefixes));
  Assert.AreEqual('always', Parse('{"refactoring": {"propertyFromAccessorsReplaceCalls": "Always"}}',
    Issues).Refactoring.PropertyFromAccessorsReplaceCalls);
  Assert.AreEqual('published', Parse('{"refactoring": {"propertyFromAccessorsSection": "published"}}',
    Issues).Refactoring.PropertyFromAccessorsSection);
  Assert.AreEqual('protected', Parse('{"refactoring": {"propertyFromAccessorsHideAccessors": "protected"}}',
    Issues).Refactoring.PropertyFromAccessorsHideAccessors);
  // #666: Felder im Destruktor freigeben.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.FreeFields);
  Assert.AreEqual('free', Parse('{}', Issues).Refactoring.FreeFieldsStyle);
  Assert.IsFalse(Parse('{"refactoring": {"freeFields": false}}', Issues).Refactoring.FreeFields);
  Assert.AreEqual('freeAndNil', Parse('{"refactoring": {"freeFieldsStyle": "FreeAndNil"}}',
    Issues).Refactoring.FreeFieldsStyle);
  // #712: Als Konstante deklarieren.
  Assert.IsFalse(Parse('{}', Issues).Refactoring.SuggestConst);
  Assert.IsTrue(Parse('{"refactoring": {"suggestConst": true}}', Issues).Refactoring.SuggestConst);
  // #644: var-Block pflegen.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.VarBlock);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.VarBlockMerge);
  Assert.AreEqual('usage', Parse('{}', Issues).Refactoring.VarBlockSort);
  Assert.IsFalse(Parse('{"refactoring": {"varBlock": false}}', Issues).Refactoring.VarBlock);
  Assert.IsFalse(Parse('{"refactoring": {"varBlockMerge": false}}', Issues).Refactoring.VarBlockMerge);
  Assert.AreEqual('alpha', Parse('{"refactoring": {"varBlockSort": "Alpha"}}', Issues).Refactoring.VarBlockSort);
  Assert.AreEqual('usage', Parse('{"refactoring": {"varBlockSort": "quer"}}', Issues).Refactoring.VarBlockSort);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #715: Boolean umkehren.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.InvertBoolean);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.InvertBooleanIncludeDfm);
  Assert.AreEqual('Not', Parse('{}', Issues).Refactoring.InvertBooleanFallbackPrefix);
  Assert.AreEqual(0, Integer(Length(Parse('{}', Issues).Refactoring.InvertBooleanAntonyms)));
  Assert.IsFalse(Parse('{"refactoring": {"invertBoolean": false}}', Issues).Refactoring.InvertBoolean);
  Assert.IsFalse(Parse('{"refactoring": {"invertBooleanIncludeDfm": false}}',
    Issues).Refactoring.InvertBooleanIncludeDfm);
  Assert.AreEqual('No', Parse('{"refactoring": {"invertBooleanFallbackPrefix": "No"}}',
    Issues).Refactoring.InvertBooleanFallbackPrefix);
  Assert.AreEqual('Verbose=Silent', string.Join(',', Parse('{"refactoring": {"invertBooleanAntonyms": ' +
    '{"Verbose": "Silent"}}}', Issues).Refactoring.InvertBooleanAntonyms));
  // #646: if-Kette und case.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.IfCase);
  Assert.IsFalse(Parse('{"refactoring": {"ifCase": false}}', Issues).Refactoring.IfCase);
  // #656: Bedingungen umformen.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.Conditions);
  Assert.IsFalse(Parse('{"refactoring": {"conditions": false}}', Issues).Refactoring.Conditions);
  // #684: if-Anweisung und Bedingungsausdruck.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ConditionalExpression);
  Assert.IsFalse(Parse('{"refactoring": {"conditionalExpression": false}}', Issues).Refactoring.ConditionalExpression);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.NestedRoutine);
  Assert.IsFalse(Parse('{"refactoring": {"nestedRoutine": false}}', Issues).Refactoring.NestedRoutine);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.PromoteVariable);
  Assert.IsFalse(Parse('{"refactoring": {"promoteVariable": false}}', Issues).Refactoring.PromoteVariable);
  // #680: anonyme Methode und Methode.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.AnonymousMethod);
  Assert.IsFalse(Parse('{"refactoring": {"anonymousMethod": false}}', Issues).Refactoring.AnonymousMethod);
  Assert.AreEqual('forward', Parse('{}', Issues).Refactoring.AnonymousMethodDeferredCapture);
  Assert.AreEqual('fields', Parse('{"refactoring": {"anonymousMethodDeferredCapture": "Fields"}}',
    Issues).Refactoring.AnonymousMethodDeferredCapture);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('forward', Parse('{"refactoring": {"anonymousMethodDeferredCapture": "felder"}}',
    Issues).Refactoring.AnonymousMethodDeferredCapture);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #686: Methode ohne Self.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.MethodKind);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.MethodKindMarker);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.MethodKindStatic);
  Assert.IsFalse(Parse('{"refactoring": {"methodKind": false}}', Issues).Refactoring.MethodKind);
  Assert.IsFalse(Parse('{"refactoring": {"methodKindMarker": false}}', Issues).Refactoring.MethodKindMarker);
  Assert.IsFalse(Parse('{"refactoring": {"methodKindStatic": false}}', Issues).Refactoring.MethodKindStatic);
  // #681: Typ-Alias.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.TypeAlias);
  Assert.IsFalse(Parse('{"refactoring": {"typeAlias": false}}', Issues).Refactoring.TypeAlias);
  Assert.AreEqual('unit', Parse('{}', Issues).Refactoring.TypeAliasScope);
  Assert.AreEqual('project', Parse('{"refactoring": {"typeAliasScope": "Project"}}', Issues).Refactoring.TypeAliasScope);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('unit', Parse('{"refactoring": {"typeAliasScope": "datei"}}', Issues).Refactoring.TypeAliasScope);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #667: Aufzählung mit Namenstabelle.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.EnumTables);
  Assert.IsFalse(Parse('{}', Issues).Refactoring.EnumTablesResourceStrings);
  Assert.IsFalse(Parse('{"refactoring": {"enumTables": false}}', Issues).Refactoring.EnumTables);
  Assert.IsTrue(Parse('{"refactoring": {"enumTablesResourceStrings": true}}',
    Issues).Refactoring.EnumTablesResourceStrings);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"refactoring": {"propertyFromAccessorsPrefixes": "Get", "propertyFromAccessorsReplaceCalls": "ja", ' +
    '"propertyFromAccessorsSection": "private", "propertyFromAccessorsHideAccessors": "public"}}', Issues);
  Assert.AreEqual(4, Integer(Length(Issues)));
  Parse('{"refactoring": {"invertBooleanAntonyms": ["Hidden"], "invertBooleanFallbackPrefix": "nicht gut"}}',
    Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Parse('{"refactoring": {"invertBooleanAntonyms": {"Hidden": "1x"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #664: Interface aus Klasse herauslösen.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ExtractInterface);
  Assert.IsFalse(Parse('{"refactoring": {"extractInterface": false}}', Issues).Refactoring.ExtractInterface);
  Parse('{"refactoring": {"extractInterface": "ja"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #713: Basisklasse herauslösen.
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Refactoring.ExtractSuperclass);
  Assert.AreEqual('sameUnit', Settings.Refactoring.ExtractSuperclassTarget);
  Assert.AreEqual('Base', Settings.Refactoring.ExtractSuperclassNameSuffix);
  Assert.AreEqual('move', Settings.Refactoring.ExtractSuperclassMethodMode);
  Assert.AreEqual('protected', Settings.Refactoring.ExtractSuperclassRaiseVisibility);
  Settings := Parse('{"refactoring": {"extractSuperclass": false, "extractSuperclassTarget": "newunit", ' +
    '"extractSuperclassNameSuffix": "Custom", "extractSuperclassMethodMode": "Abstract", ' +
    '"extractSuperclassRaiseVisibility": "strictprotected"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Refactoring.ExtractSuperclass);
  Assert.AreEqual('newUnit', Settings.Refactoring.ExtractSuperclassTarget);
  Assert.AreEqual('Custom', Settings.Refactoring.ExtractSuperclassNameSuffix);
  Assert.AreEqual('abstract', Settings.Refactoring.ExtractSuperclassMethodMode);
  Assert.AreEqual('strictProtected', Settings.Refactoring.ExtractSuperclassRaiseVisibility);
  Parse('{"refactoring": {"extractSuperclassTarget": "otherUnit", "extractSuperclassNameSuffix": "1x", ' +
    '"extractSuperclassMethodMode": "copy", "extractSuperclassRaiseVisibility": "public"}}', Issues);
  Assert.AreEqual(4, Integer(Length(Issues)));
  // #675: Mitglied verschieben.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.MoveMember);
  Assert.IsFalse(Parse('{"refactoring": {"moveMember": false}}', Issues).Refactoring.MoveMember);
  Parse('{"refactoring": {"moveMember": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #717: Zugriffsmethode durch Feld ersetzen.
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Refactoring.InlineAccessor);
  Assert.IsTrue(Settings.Refactoring.InlineAccessorEqualityCheck);
  Assert.IsTrue(Settings.Refactoring.InlineAccessorBulk);
  Assert.IsFalse(Settings.Refactoring.InlineAccessorDiagnostic);
  Settings := Parse('{"refactoring": {"inlineAccessor": false, "inlineAccessorEqualityCheck": false, ' +
    '"inlineAccessorBulk": false, "inlineAccessorDiagnostic": true}}', Issues);
  Assert.IsFalse(Settings.Refactoring.InlineAccessor);
  Assert.IsFalse(Settings.Refactoring.InlineAccessorEqualityCheck);
  Assert.IsFalse(Settings.Refactoring.InlineAccessorBulk);
  Assert.IsTrue(Settings.Refactoring.InlineAccessorDiagnostic);
  Parse('{"refactoring": {"inlineAccessorBulk": "ja"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #716: Sicher löschen.
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Refactoring.SafeDelete);
  Assert.IsFalse(Settings.Refactoring.SafeDeletePreviewWhenUnused);
  Assert.AreEqual('ask', Settings.Refactoring.SafeDeleteCascade);
  Assert.AreEqual('ask', Settings.Refactoring.SafeDeleteIncludeOverrides);
  Settings := Parse('{"refactoring": {"safeDelete": false, "safeDeletePreviewWhenUnused": true, ' +
    '"safeDeleteCascade": "Always", "safeDeleteIncludeOverrides": "never"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Refactoring.SafeDelete);
  Assert.IsTrue(Settings.Refactoring.SafeDeletePreviewWhenUnused);
  Assert.AreEqual('always', Settings.Refactoring.SafeDeleteCascade);
  Assert.AreEqual('never', Settings.Refactoring.SafeDeleteIncludeOverrides);
  Settings := Parse('{"refactoring": {"safeDeleteCascade": "manchmal"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('ask', Settings.Refactoring.SafeDeleteCascade);
  // Speicherbudget (#185)
  Assert.AreEqual(768, Parse('{}', Issues).MemoryBudgetMb, 'Vorgabe 768 MB (Rückmeldung 15.10.2026)');
  Assert.AreEqual(0, Parse('{"memoryBudgetMb": 0}', Issues).MemoryBudgetMb, '0 = unbegrenzt');
  Assert.AreEqual(512, Parse('{"memoryBudgetMb": 512}', Issues).MemoryBudgetMb);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(768, Parse('{"memoryBudgetMb": -1}', Issues).MemoryBudgetMb);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"memoryBudgetMb": 100}', '{"memoryBudgetMb": 200}', Issues);
  Assert.AreEqual(200, Settings.MemoryBudgetMb);
  // Zeitlimit für Anfragen (#283)
  Assert.AreEqual(10000, Parse('{}', Issues).RequestTimeoutMs);
  Assert.AreEqual(30000, Parse('{"requestTimeoutMs": 30000}', Issues).RequestTimeoutMs);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(10000, Parse('{"requestTimeoutMs": 10}', Issues).RequestTimeoutMs);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Diagnoselog (#647)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.DiagnosticsLog);
  Assert.AreEqual(7, Settings.DiagnosticsLogDays);
  Assert.IsFalse(Settings.DiagnosticsLogMapFile);
  Settings := Parse('{"diagnostics": {"log": false, "logDays": 3, "logMapFile": true}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.DiagnosticsLog);
  Assert.AreEqual(3, Settings.DiagnosticsLogDays);
  Assert.IsTrue(Settings.DiagnosticsLogMapFile);
  Assert.AreEqual(7, Parse('{"diagnostics": {"logDays": 0, "x": 1}}', Issues).DiagnosticsLogDays);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"diagnostics": {"log": false}}', '{"diagnostics": {"logDays": 2}}', Issues);
  Assert.IsTrue(Settings.DiagnosticsLog, 'atlas.json ersetzt den ganzen Abschnitt');
  Assert.AreEqual(2, Settings.DiagnosticsLogDays);
  // Umfang des Index (#648)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.IndexProjectGroup and Settings.IndexSearchPaths);
  Assert.IsFalse(Settings.IndexLibraryPaths, 'Bibliothekspfade nur auf Wunsch (Dauer)');
  Assert.IsTrue(Settings.IndexUsages, 'Verwendungen standardmäßig an (#492)');
  Assert.AreEqual<NativeInt>(0, Length(Settings.IndexExclude));
  Settings := Parse('{"index": {"projectGroup": false, "searchPaths": false, "libraryPaths": false, ' +
    '"usages": false, "exclude": ["**/Demos/**"]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.IndexProjectGroup or Settings.IndexSearchPaths or Settings.IndexLibraryPaths);
  Assert.IsFalse(Settings.IndexUsages);
  Parse('{"index": {"usages": "ja"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsTrue(Settings.IsIndexExcluded('C:\Komponenten\Demos\Main.pas'));
  Assert.IsFalse(Settings.IsIndexExcluded('C:\Komponenten\Source\Main.pas'));
  Parse('{"index": {"exclude": "Demos", "x": true}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"index": {"searchPaths": false}}', '{"index": {"exclude": []}}', Issues);
  Assert.IsTrue(Settings.IndexSearchPaths, 'atlas.json ersetzt den ganzen Abschnitt');
  // Aufräumen des Cache-Ordners (#905)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.IndexRemoveOrphans, 'verwaiste Caches standardmäßig löschen');
  Assert.AreEqual(14, Settings.IndexCacheMaxAgeDays);
  Assert.AreEqual(256, Settings.IndexCacheMaxMb);
  Settings := Parse('{"index": {"removeOrphans": false, "cacheMaxAgeDays": 0, "cacheMaxMb": 1024}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.IndexRemoveOrphans);
  Assert.AreEqual(0, Settings.IndexCacheMaxAgeDays);
  Assert.AreEqual(1024, Settings.IndexCacheMaxMb);
  Settings := Parse('{"index": {"removeOrphans": 1, "cacheMaxAgeDays": -1, "cacheMaxMb": "viel"}}', Issues);
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.IsTrue(Settings.IndexRemoveOrphans);
  Assert.AreEqual(14, Settings.IndexCacheMaxAgeDays);
  Assert.AreEqual(256, Settings.IndexCacheMaxMb);
  Settings := TConfigurationParser.ParseLayered('{"index": {"cacheMaxAgeDays": 30}}', '{}', Issues);
  Assert.AreEqual(30, Settings.IndexCacheMaxAgeDays);
  // Schlüsselworthervorhebung (#307)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Highlight.BlockPairs and Settings.Highlight.Directives and Settings.Highlight.ExitPoints);
  Assert.AreEqual(4, Integer(Length(Settings.Highlight.ExitKeywords)));
  Settings := Parse('{"highlight": {"exitPoints": false, "exitKeywords": ["Exit", "Fail"]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Highlight.ExitPoints);
  Assert.IsTrue(Settings.Highlight.BlockPairs);
  Assert.AreEqual('Fail', Settings.Highlight.ExitKeywords[1]);
  Parse('{"highlight": {"blockPairs": 1, "foo": true}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  // Protokoll (#265)
  Assert.AreEqual('info', Parse('{}', Issues).LogLevel);
  Settings := Parse('{"logLevel": "debug", "logFile": "C:\\Log\\lsp.log", "traceFile": "t.json"}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('debug', Settings.LogLevel);
  Assert.AreEqual('C:\Log\lsp.log', Settings.LogFile);
  Assert.AreEqual('t.json', Settings.TraceFile);
  Assert.AreEqual('info', Parse('{"logLevel": "laut"}', Issues).LogLevel);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"logLevel": "error"}', '{"logLevel": "warning"}', Issues);
  Assert.AreEqual('warning', Settings.LogLevel);
end;

procedure TConfigurationParserTests.ReadsStringLiteral;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual(Ord(TStringLiteralStyle.Auto), Ord(Settings.StringLiteral.Style));
  Assert.AreEqual(Ord(TStringLiteralBreak.SLineBreak), Ord(Settings.StringLiteral.LineBreak));
  Assert.AreEqual(0, Settings.StringLiteral.MaxLineLength);
  Settings := Parse('{"stringLiteral": {"style": "concat", "lineBreak": "#13#10", "maxLineLength": 100}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(Ord(TStringLiteralStyle.Concat), Ord(Settings.StringLiteral.Style));
  Assert.AreEqual(Ord(TStringLiteralBreak.CrLf), Ord(Settings.StringLiteral.LineBreak));
  Assert.AreEqual(100, Settings.StringLiteral.MaxLineLength);
  Settings := Parse('{"stringLiteral": {"style": "kurz", "lineBreak": "space", "maxLineLength": -1, "x": 1}}', Issues);
  // Ungültiger Stil und negative Länge (Fehler), "x" unbekannt (Warnung).
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.AreEqual(Ord(TStringLiteralBreak.Space), Ord(Settings.StringLiteral.LineBreak));
  Assert.AreEqual(Ord(TStringLiteralStyle.Auto), Ord(Settings.StringLiteral.Style));
end;

procedure TConfigurationParserTests.ReadsDirectives;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Directives.Completion);
  Assert.IsTrue(Settings.Directives.Hover);
  Settings := Parse('{"directives": {"completion": false, "hover": false}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Directives.Completion);
  Assert.IsFalse(Settings.Directives.Hover);
  Settings := Parse('{"directives": {"x": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Parse('{"directives": 1}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

procedure TConfigurationParserTests.ReadsDfmPropertyRules;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  Assert.AreEqual(0, Integer(Length(Parse('{}', Issues).DfmPropertyRules)));
  Settings := Parse('{"dfmPropertyRules": [' +
    '{"class": "TLabel", "property": "Transparent", "condition": "=", "value": "True", "fix": "auto"},' +
    '{"class": "TForm", "property": "Position", "condition": "<>", "value": "poDesigned", "message": "Zentriert",' +
    ' "severity": "hint", "includeDescendants": false, "exclude": ["**/Alt/*.dfm"]},' +
    '{"class": "TEdit", "property": "Hint", "condition": "notEmpty", "fix": "none"}]}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(3, Integer(Length(Settings.DfmPropertyRules)));
  Assert.AreEqual('TLabel', Settings.DfmPropertyRules[0].ClassName);
  Assert.AreEqual('Transparent', Settings.DfmPropertyRules[0].PropertyPath);
  Assert.IsTrue(Settings.DfmPropertyRules[0].Condition = TDfmCondition.Equal);
  Assert.IsTrue(Settings.DfmPropertyRules[0].Fix = TDfmFixMode.Auto);
  Assert.IsTrue(Settings.DfmPropertyRules[0].Severity = TRuleSeverity.Warning);
  Assert.IsTrue(Settings.DfmPropertyRules[0].IncludeDescendants);
  Assert.IsTrue(Settings.DfmPropertyRules[1].Condition = TDfmCondition.NotEqual);
  Assert.IsTrue(Settings.DfmPropertyRules[1].Severity = TRuleSeverity.Hint);
  Assert.IsFalse(Settings.DfmPropertyRules[1].IncludeDescendants);
  Assert.AreEqual('Zentriert', Settings.DfmPropertyRules[1].Message);
  Assert.AreEqual('**/Alt/*.dfm', Settings.DfmPropertyRules[1].Exclude[0]);
  Assert.IsTrue(Settings.DfmPropertyRules[2].Condition = TDfmCondition.NotEmpty);
  Assert.IsTrue(Settings.DfmPropertyRules[2].Fix = TDfmFixMode.None);
  // Fehlerhafte Regeln: ohne property, = ohne value, unbekannte Bedingung, unbekannter Schlüssel.
  Settings := Parse('{"dfmPropertyRules": [{"class": "TLabel"}, {"class": "TA", "property": "B", "condition": "="},' +
    ' {"class": "TA", "property": "B", "condition": "gleich", "value": "1", "x": 1}, 5]}', Issues);
  Assert.AreEqual(5, Integer(Length(Issues)));
  Assert.AreEqual(1, Integer(Length(Settings.DfmPropertyRules)));
  Parse('{"dfmPropertyRules": {}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Editor zuerst, die Datei hat Vorrang.
  Settings := TConfigurationParser.ParseLayered('{"dfmPropertyRules": []}',
    '{"dfmPropertyRules": [{"class": "TA", "property": "B", "value": "1"}]}', Issues);
  Assert.AreEqual(1, Integer(Length(Settings.DfmPropertyRules)));
end;

procedure TConfigurationParserTests.ReadsMemberOrder;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual(6, Integer(Length(Settings.MemberOrder.Sections)));
  Assert.AreEqual('field', Settings.MemberOrder.Members[0]);
  Assert.IsFalse(Settings.MemberOrder.SortFields);
  Settings := Parse('{"memberOrder": {"sections": ["public", "private"], "members": ["method", "field"], ' +
    '"sortFields": true, "sortPublished": true}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('public', Settings.MemberOrder.Sections[0]);
  Assert.AreEqual('method', Settings.MemberOrder.Members[0]);
  Assert.IsTrue(Settings.MemberOrder.SortFields);
  Assert.IsTrue(Settings.MemberOrder.SortPublished);
  Settings := Parse('{"memberOrder": {"sections": ["intern"], "x": 1}}', Issues);
  // Unbekannte Sichtbarkeit (Fehler), "x" unbekannt (Warnung).
  Assert.AreEqual(2, Integer(Length(Issues)));
end;

procedure TConfigurationParserTests.ReadsTestUnits;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual('{unit}.Tests', Settings.TestUnits.Pattern);
  Assert.AreEqual('', Settings.TestUnits.Folder);
  Assert.AreEqual('', Settings.TestUnits.Project);
  Settings := Parse('{"testUnits": {"pattern": "Test.{unit}", "folder": "Tests/Unit", ' +
    '"project": "Tests/Tests.dproj"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('Test.{unit}', Settings.TestUnits.Pattern);
  Assert.AreEqual('Tests/Unit', Settings.TestUnits.Folder);
  Assert.AreEqual('Tests/Tests.dproj', Settings.TestUnits.Project);
  Settings := Parse('{"testUnits": {"pattern": "Tests", "project": "Tests.exe", "x": 1}}', Issues);
  // Muster ohne {unit} und Projekt ohne .dproj/.dpr (Fehler), "x" unbekannt (Warnung).
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.AreEqual('{unit}.Tests', Settings.TestUnits.Pattern, 'ungültiges Muster bleibt bei der Vorgabe');
end;

procedure TConfigurationParserTests.ReadsMcpGlobalSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.McpGlobalSettings, 'Vorgabe: globale Datei lesen');
  Settings := Parse('{"mcp": {"globalSettings": false}}', Issues);
  Assert.IsFalse(Settings.McpGlobalSettings);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Settings := Parse('{"mcp": {"globalSettings": "nein"}}', Issues);
  Assert.IsTrue(Settings.McpGlobalSettings, 'Ungültiger Wert lässt die Vorgabe');
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"mcp": {"globalSettings": true}}',
    '{"mcp": {"globalSettings": false}}', Issues);
  Assert.IsFalse(Settings.McpGlobalSettings, 'Datei vor Editor');
end;

procedure TConfigurationParserTests.ChecksTasks;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"tasks": [{"name": "Delphi-12-Prüfung", "command": "pwsh", "args": ["Tools/Check-Delphi12.ps1"],' +
    ' "cwd": "${projectDir}", "group": "check", "matcher": "pwsh", "key": "Ctrl+Alt+1", "timeoutSec": 300,' +
    ' "beforeBuild": "block", "env": {"NO_COLOR": "1"}},' +
    ' {"name": "Fremd", "command": "lint.exe", "matcher": {"regex": "^(?<file>[^:]+):(?<line>\\d+) (?<message>.*)$",' +
    ' "severity": "warning", "severityMap": {"SCHLIMM": "error"}}}]}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'Beispiel aus dem Issue ohne Meldung');
  Assert.IsTrue(Settings.Tasks.StartsWith('['), Settings.Tasks);
  Settings := Parse('{"tasks": [{"name": "A", "command": "x", "group": "lint", "matcher": "eslint", "timeoutSec": -1,' +
    ' "beforeBuild": "stop", "foo": 1}, {"name": "a", "command": ""}, {"command": "y"}, 3,' +
    ' {"name": "M", "command": "z", "matcher": {"severityMap": {"X": "fatal"}}}]}', Issues);
  // group, matcher, timeoutSec, beforeBuild, foo; Doppelname a und leerer command; ohne name; 3; Muster ohne regex
  // und severityMap-Wert.
  Assert.AreEqual(11, Integer(Length(Issues)));
  Parse('{"tasks": {"name": "A"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'keine Liste');
  Settings := TConfigurationParser.ParseLayered('{"tasks": []}', '{"tasks": [{"name": "B", "command": "b"}]}',
    Issues);
  Assert.IsTrue(Settings.Tasks.Contains('"B"'), 'Datei vor Editor');
end;

procedure TConfigurationParserTests.ChecksIssueConnections;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"issues": {"connections": [{"name": "Firma", "provider": "youtrack",' +
    ' "url": "https://youtrack.firma.local"}, {"name": "GitHub", "provider": "github", "url": "https://github.com"}]}}',
    Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'Beispiel aus dem Issue ohne Meldung');
  Assert.IsTrue(Settings.IssueConnections.StartsWith('['), Settings.IssueConnections);
  Assert.IsTrue(Settings.IssueConnections.Contains('"Firma"'), Settings.IssueConnections);
  Settings := Parse('{"issues": {"connections": [{"name": "A", "provider": "youtrack", "url": "http://yt.local"},' +
    ' {"name": "a", "provider": "github", "url": "https://user@github.com"}, {"provider": "", "url": 3, "token": "x"},' +
    ' 3], "queries": []}}', Issues);
  // http; Doppelname a und Benutzer in der Adresse; url kein String, token unbekannt, ohne name, ohne provider (leer)
  // und ohne url; 3. queries ist seit #1262 bekannt.
  Assert.AreEqual(9, Integer(Length(Issues)));
  Parse('{"issues": {"connections": {"name": "A"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'keine Liste');
  Parse('{"issues": []}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'kein Objekt');
  Settings := TConfigurationParser.ParseLayered('{}', '{"issues": {"connections": [{"name": "B", "provider": "github",' +
    ' "url": "https://github.com"}]}}', Issues);
  Assert.IsTrue(Settings.IssueConnections.Contains('"B"'), 'Datei vor Editor');
end;

procedure TConfigurationParserTests.ChecksIssueProjects;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"issues": {"projects": [{"match": "C:\\Projekte\\Kasse\\Kasse.groupproj", ' +
    '"connection": "Firma", "project": "KASSE"}, {"match": "C:\\Projekte\\Atlas", "connection": "GitHub"}]}}',
    Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'Beispiel aus dem Issue ohne Meldung; project darf fehlen');
  Assert.IsTrue(Settings.IssueProjects.StartsWith('['), Settings.IssueProjects);
  Assert.IsTrue(Settings.IssueProjects.Contains('"KASSE"'), Settings.IssueProjects);
  Settings := Parse('{"issues": {"projects": [{"match": "C:\\A", "connection": "Firma"}, ' +
    '{"match": "c:/a/", "connection": "GitHub"}, {"connection": 3, "project": 4, "x": 1}, 3]}}', Issues);
  // Pfad doppelt; connection kein String, project kein String, x unbekannt, ohne match, ohne connection; 3.
  Assert.AreEqual(7, Integer(Length(Issues)));
  Parse('{"issues": {"projects": {"match": "C:\\A"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'keine Liste');
  Settings := TConfigurationParser.ParseLayered('{}', '{"issues": {"projects": [{"match": "C:\\B", ' +
    '"connection": "Firma"}]}}', Issues);
  Assert.IsTrue(Settings.IssueProjects.Contains('Firma'), 'Datei vor Editor');
end;

procedure TConfigurationParserTests.ChecksIssueQueries;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"issues": {"queries": [{"name": "Mir zugewiesen", "query": "assignee: meine #Ungelöst"}, ' +
    '{"name": "Sprint", "query": "#{Aktueller Sprint}", "connection": "Firma", "project": "KASSE"}]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'connection und project dürfen fehlen');
  Assert.IsTrue(Settings.IssueQueries.StartsWith('['), Settings.IssueQueries);
  Assert.IsTrue(Settings.IssueQueries.Contains('"Sprint"'), Settings.IssueQueries);
  Settings := Parse('{"issues": {"queries": [{"name": "A", "query": "x"}, {"name": "a", "query": ""}, ' +
    '{"connection": 3, "x": 1}, 3]}}', Issues);
  // Name doppelt, query leer; connection kein String, x unbekannt, ohne name, ohne query; 3.
  Assert.AreEqual(7, Integer(Length(Issues)));
  Parse('{"issues": {"queries": {"name": "A"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'keine Liste');
  Settings := TConfigurationParser.ParseLayered('{}', '{"issues": {"queries": [{"name": "B", "query": "y"}]}}',
    Issues);
  Assert.IsTrue(Settings.IssueQueries.Contains('"B"'), 'Datei vor Editor');
end;

procedure TConfigurationParserTests.ReadsMcpDisabledTools;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual(0, Integer(Length(Settings.McpDisabledTools)));
  Settings := Parse('{"mcp": {"disabledTools": ["rename_symbol", 3], "x": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Settings.McpDisabledTools)));
  Assert.AreEqual('rename_symbol', Settings.McpDisabledTools[0]);
  Assert.AreEqual(2, Integer(Length(Issues)), 'Zahl in der Liste und unbekannter Schlüssel');
  Settings := TConfigurationParser.ParseLayered('{"mcp": {"disabledTools": ["a"]}}',
    '{"mcp": {"disabledTools": ["b"]}}', Issues);
  Assert.AreEqual('b', Settings.McpDisabledTools[0], 'Datei vor Editor');
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

procedure TConfigurationParserTests.ReadsHints;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual(THintSettings.ExpandLast, Settings.Hints.XmlDocExpand);
  Assert.AreEqual(0, Settings.Hints.XmlDocMaxLines);
  // published-Mitglieder im Hover (#110).
  Assert.IsTrue(Settings.Hints.PublishedMembers);
  Assert.IsFalse(Parse('{"hints": {"publishedMembers": false}}', Issues).Hints.PublishedMembers);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"hints": {"publishedMembers": 0}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := Parse('{"hints": {"xmlDocExpand": "collapsed", "xmlDocMaxLines": 10}}', Issues);
  Assert.AreEqual(THintSettings.ExpandCollapsed, Settings.Hints.XmlDocExpand);
  Assert.AreEqual(10, Settings.Hints.XmlDocMaxLines);
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Außerhalb 0–50 bzw. falsch getypt (Fehler), unbekannter Schlüssel (Warnung); Vorgaben bleiben.
  Settings := Parse('{"hints": {"xmlDocMaxLines": 51, "xmlDocExpand": "auf", "x": 1}}', Issues);
  Assert.AreEqual(0, Settings.Hints.XmlDocMaxLines);
  Assert.AreEqual(THintSettings.ExpandLast, Settings.Hints.XmlDocExpand);
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.IsTrue(Issues[0].IsError);
  Assert.IsTrue(Issues[1].IsError);
  Assert.IsFalse(Issues[2].IsError);
  Settings := Parse('{"hints": {"xmlDocMaxLines": -1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Veraltetes xmlDocFull (#770): true = expanded, false = collapsed, mit Warnung; xmlDocExpand gewinnt.
  Settings := Parse('{"hints": {"xmlDocFull": false}}', Issues);
  Assert.AreEqual(THintSettings.ExpandCollapsed, Settings.Hints.XmlDocExpand);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsFalse(Issues[0].IsError);
  Settings := Parse('{"hints": {"xmlDocFull": true}}', Issues);
  Assert.AreEqual(THintSettings.ExpandExpanded, Settings.Hints.XmlDocExpand);
  Settings := Parse('{"hints": {"xmlDocExpand": "last", "xmlDocFull": false}}', Issues);
  Assert.AreEqual(THintSettings.ExpandLast, Settings.Hints.XmlDocExpand);
  // Die Datei ersetzt den Block aus dem Editor (IDE-Plugin).
  Settings := TConfigurationParser.ParseLayered('{"hints": {"xmlDocExpand": "collapsed"}}',
    '{"hints": {"xmlDocMaxLines": 5}}', Issues);
  Assert.AreEqual(THintSettings.ExpandLast, Settings.Hints.XmlDocExpand);
  Assert.AreEqual(5, Settings.Hints.XmlDocMaxLines);
  // Begründungen (#1123): Schalter, Marken, ADR-Ordner.
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Hints.Rationale);
  Assert.AreEqual(0, Integer(Length(Settings.Hints.RationaleMarkers)));
  Assert.AreEqual('', Settings.Hints.AdrFolder);
  Settings := Parse('{"hints": {"rationale": false, "rationaleMarkers": ["WHY", " PERF "], ' +
    '"adrFolder": "doc/decisions"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Hints.Rationale);
  Assert.AreEqual('WHY PERF', string.Join(' ', Settings.Hints.RationaleMarkers));
  Assert.AreEqual('doc/decisions', Settings.Hints.AdrFolder);
  Settings := Parse('{"hints": {"rationale": "ja", "rationaleMarkers": ["WHY", ""], "adrFolder": 3}}', Issues);
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.IsTrue(Settings.Hints.Rationale);
  Settings := Parse('{"hints": {"rationaleMarkers": "WHY"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual(0, Integer(Length(Settings.Hints.RationaleMarkers)));
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

initialization
  TDUnitX.RegisterTestFixture(TConfigurationParserTests);
  TDUnitX.RegisterTestFixture(TServerSettingsTests);

end.
