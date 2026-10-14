unit Atlas.Common.Configuration.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConfigurationParserTests = class
  public
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
    procedure ReadsHints;
    [Test]
    procedure ReadsMcpDisabledTools;
    [Test]
    procedure ReadsStringLiteral;
    [Test]
    procedure ReadsMemberOrder;
    [Test]
    procedure ReadsDfmPropertyRules;
    [Test]
    procedure ReadsCompilerSettings;
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
    procedure ReadsSortUses;
  end;

implementation

uses
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
end;

procedure TConfigurationParserTests.ReadsCompilerSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Compiler.OnSave);
  Settings := Parse('{"compiler": {"onSave": false}}', Issues);
  Assert.IsFalse(Settings.Compiler.OnSave);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Settings := Parse('{"compiler": {"onSave": "nein", "x": 1}}', Issues);
  Assert.IsTrue(Settings.Compiler.OnSave);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"compiler": {"onSave": false}}', '{}', Issues);
  Assert.IsFalse(Settings.Compiler.OnSave);
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
  // Freigabe absichern (#489)
  Assert.IsTrue(Parse('{}', Issues).Completion.OfferTryFinally);
  Assert.IsTrue(Parse('{}', Issues).Completion.FreeStyle = TCompletionFreeStyle.Free);
  Assert.IsFalse(Parse('{"completion": {"offerTryFinally": false}}', Issues).Completion.OfferTryFinally);
  Assert.IsTrue(Parse('{"completion": {"freeStyle": "freeAndNil"}}', Issues).Completion.FreeStyle =
    TCompletionFreeStyle.FreeAndNil);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"freeStyle": "nil"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Speicherbudget (#185)
  Assert.AreEqual(256, Parse('{}', Issues).MemoryBudgetMb, 'Vorgabe 256 MB (#492)');
  Assert.AreEqual(0, Parse('{"memoryBudgetMb": 0}', Issues).MemoryBudgetMb, '0 = unbegrenzt');
  Assert.AreEqual(512, Parse('{"memoryBudgetMb": 512}', Issues).MemoryBudgetMb);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(256, Parse('{"memoryBudgetMb": -1}', Issues).MemoryBudgetMb);
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

procedure TConfigurationParserTests.ReadsHints;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Hints.XmlDocFull);
  Assert.AreEqual(0, Settings.Hints.XmlDocMaxLines);
  Settings := Parse('{"hints": {"xmlDocFull": false, "xmlDocMaxLines": 10}}', Issues);
  Assert.IsFalse(Settings.Hints.XmlDocFull);
  Assert.AreEqual(10, Settings.Hints.XmlDocMaxLines);
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Außerhalb 0–50 bzw. falsch getypt (Fehler), unbekannter Schlüssel (Warnung); Vorgaben bleiben.
  Settings := Parse('{"hints": {"xmlDocMaxLines": 51, "xmlDocFull": "nein", "x": 1}}', Issues);
  Assert.AreEqual(0, Settings.Hints.XmlDocMaxLines);
  Assert.IsTrue(Settings.Hints.XmlDocFull);
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.IsTrue(Issues[0].IsError);
  Assert.IsTrue(Issues[1].IsError);
  Assert.IsFalse(Issues[2].IsError);
  Settings := Parse('{"hints": {"xmlDocMaxLines": -1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Die Datei ersetzt den Block aus dem Editor (IDE-Plugin).
  Settings := TConfigurationParser.ParseLayered('{"hints": {"xmlDocFull": false}}',
    '{"hints": {"xmlDocMaxLines": 5}}', Issues);
  Assert.IsTrue(Settings.Hints.XmlDocFull);
  Assert.AreEqual(5, Settings.Hints.XmlDocMaxLines);
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
