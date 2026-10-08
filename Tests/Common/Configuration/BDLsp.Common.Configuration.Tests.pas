unit BDLsp.Common.Configuration.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Configuration.Parser;

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
    '{"serverPath": "C:\\Bin\\BetterDelphiLSP.exe", "platform": "Win32", "config": "Release", "language": "en"}',
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
    '  "format": { "indent": 2 }'#13#10 +
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
  Assert.AreEqual('{ "indent": 2 }', Settings.Format);
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

initialization
  TDUnitX.RegisterTestFixture(TConfigurationParserTests);
  TDUnitX.RegisterTestFixture(TServerSettingsTests);

end.
