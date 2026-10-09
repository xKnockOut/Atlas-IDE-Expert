unit Argus.Common.Configuration.Tests;

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
    procedure ReadsCompilerSettings;
    [Test]
    procedure ReadsFormatSettings;
    [Test]
    procedure FileOverridesEditorPerKey;
    [Test]
    procedure MergesRulesPerId;
    [Test]
    procedure EditorOrFileAlone;
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
  Argus.Common.Configuration.Contract,
  Argus.Common.Configuration.Parser;

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
    '{"serverPath": "C:\\Bin\\ArgusServer.exe", "platform": "Win32", "config": "Release", "language": "en"}',
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
  // Vervollständigung (#229)
  Assert.IsTrue(Parse('{}', Issues).Completion.Matching = TCompletionMatching.Fuzzy);
  Assert.IsTrue(Parse('{"completion": {"matching": "prefix"}}', Issues).Completion.Matching = TCompletionMatching.Prefix);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{"completion": {"matching": "egal", "x": 1}}', Issues).Completion.Matching = TCompletionMatching.Fuzzy);
  Assert.AreEqual(2, Integer(Length(Issues)));
  // Speicherbudget (#185)
  Assert.AreEqual(0, Parse('{}', Issues).MemoryBudgetMb);
  Assert.AreEqual(512, Parse('{"memoryBudgetMb": 512}', Issues).MemoryBudgetMb);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(0, Parse('{"memoryBudgetMb": -1}', Issues).MemoryBudgetMb);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"memoryBudgetMb": 100}', '{"memoryBudgetMb": 200}', Issues);
  Assert.AreEqual(200, Settings.MemoryBudgetMb);
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
  Assert.IsTrue(IsConfigurationFileName('argus.json'));
  Assert.IsTrue(IsConfigurationFileName('Argus.JSON'));
  Assert.IsTrue(IsConfigurationFileName('delphi-lsp.json'));
  Assert.IsFalse(IsConfigurationFileName('argus-baseline.json'));
end;

procedure TServerSettingsTests.PrefersNewFileOverLegacy;
var
  Dir: string;
begin
  Dir := TPath.Combine(TPath.GetTempPath, 'Argus.Tests.' + TGUID.NewGuid.ToString);
  TDirectory.CreateDirectory(Dir);
  try
    // Ohne Datei: der neue Name, damit dort angelegt wird.
    Assert.AreEqual(TPath.Combine(Dir, 'argus.json'), ExistingOrLegacyFile(Dir, 'argus.json', 'delphi-lsp.json'));
    TFile.WriteAllText(TPath.Combine(Dir, 'delphi-lsp.json'), '{}');
    Assert.AreEqual(TPath.Combine(Dir, 'delphi-lsp.json'), ExistingOrLegacyFile(Dir, 'argus.json', 'delphi-lsp.json'));
    TFile.WriteAllText(TPath.Combine(Dir, 'argus.json'), '{}');
    Assert.AreEqual(TPath.Combine(Dir, 'argus.json'), ExistingOrLegacyFile(Dir, 'argus.json', 'delphi-lsp.json'));
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
