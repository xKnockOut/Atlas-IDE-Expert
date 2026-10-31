unit Atlas.Common.Configuration.Scopes.Tests;

// Tests für den Ort der Einstellungen: jeder Schlüssel in genau einer Datei.
// Dazu die Sperre für Zugangsdaten und absolute Pfade in atlas.json (#486).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConfigurationScopesTests = class
  public
    [Test]
    procedure KnowsPlaceOfEachKey;
    [Test]
    procedure ListsAreDisjoint;
    [Test]
    procedure GlobalRulesProjectOverridesPerRule;
    [Test]
    procedure KeepsTextWithoutMisplacedKeys;
    [Test]
    procedure RemovesAndReportsMisplacedKeys;
    [Test]
    procedure FiltersMixedObjectsPerMember;
    [Test]
    procedure PassesInvalidTextThrough;
    [Test]
    procedure LayersGlobalEditorProject;
    [Test]
    procedure BuildsGlobalFileName;
    [Test]
    procedure IgnoresCredentialsInProjectFile;
    [Test]
    procedure IgnoresAbsolutePathsInProjectFile;
    [Test]
    procedure KeepsRelativePathsAndGlobs;
    [Test]
    procedure GlobalFileKeepsPersonalPaths;
    /// <summary>#834: Hauptschalter experimental.enabled; ohne ihn fallen experimentelle Schlüssel weg.</summary>
    [Test]
    procedure ExperimentalKeysNeedMasterSwitch;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Scopes,
  Atlas.Common.Configuration.Internals.ScopeData;

procedure TConfigurationScopesTests.KnowsPlaceOfEachKey;
begin
  Assert.IsTrue(TConfigurationScopes.ScopeOf('index.projectGroup') = TConfigurationScope.Global);
  Assert.IsTrue(TConfigurationScopes.ScopeOf('index.exclude') = TConfigurationScope.Project);
  Assert.IsTrue(TConfigurationScopes.ScopeOf('memoryBudgetMb') = TConfigurationScope.Global);
  Assert.IsTrue(TConfigurationScopes.ScopeOf('hints.xmlDocFull') = TConfigurationScope.Global, 'erbt von hints');
  Assert.IsTrue(TConfigurationScopes.ScopeOf('rules') = TConfigurationScope.Both, 'global und Projekt');
  Assert.IsTrue(TConfigurationScopes.ScopeOf('format.indentSize') = TConfigurationScope.Project);
  Assert.IsTrue(TConfigurationScopes.ScopeOf('completion.matching') = TConfigurationScope.Global);
  Assert.IsTrue(TConfigurationScopes.ScopeOf('completion.senderCast') = TConfigurationScope.Project);
  Assert.IsTrue(TConfigurationScopes.ScopeOf('unbekannt') = TConfigurationScope.Unknown);
  Assert.IsTrue(TConfigurationScopes.IsMixed('index'));
  Assert.IsTrue(TConfigurationScopes.IsMixed('completion'));
  Assert.IsFalse(TConfigurationScopes.IsMixed('hints'));
  Assert.IsFalse(TConfigurationScopes.IsMixed('rules'));
end;

procedure TConfigurationScopesTests.ListsAreDisjoint;
var
  GlobalPath, ProjectPath: string;
begin
  for GlobalPath in GlobalSettingPaths do
    for ProjectPath in ProjectSettingPaths do
    begin
      // rules, tasks (#900) und excludeTests (x-scope "both") stehen absichtlich in beiden Listen.
      if (GlobalPath = ProjectPath) and ((GlobalPath = 'rules') or (GlobalPath = 'tasks') or
        (GlobalPath = 'excludeTests')) then
        Continue;
      Assert.AreNotEqual(GlobalPath, ProjectPath);
      // Ein ganzes Objekt an einem Ort und eines seiner Glieder am anderen wäre widersprüchlich.
      Assert.IsFalse(GlobalPath.StartsWith(ProjectPath + '.'), GlobalPath);
      Assert.IsFalse(ProjectPath.StartsWith(GlobalPath + '.'), ProjectPath);
    end;
end;

procedure TConfigurationScopesTests.GlobalRulesProjectOverridesPerRule;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  // Global erlaubt, ohne Meldung.
  TConfigurationScopes.Filter('{"rules": {"no-with": "off"}}', TConfigurationScope.Global, Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  TConfigurationScopes.Filter('{"rules": {"no-with": "off"}}', TConfigurationScope.Project, Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Settings := TConfigurationParser.Parse(TConfigurationScopes.Effective(
    '{"rules": {"no-with": "off", "magic-number": "hint"}}', '', '{"rules": {"magic-number": "error"}}'), Issues);
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(Settings.RuleSeverity('no-with', TRuleSeverity.Warning)), 'global');
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Settings.RuleSeverity('magic-number', TRuleSeverity.Warning)),
    'Projekt übersteuert');
end;

procedure TConfigurationScopesTests.KeepsTextWithoutMisplacedKeys;
const
  Project = '// Kommentar'#10'{"rules": {"empty-except": "off"}, "unbekannt": 1, "$schema": "x"}';
  Global = '{"index": {"usages": false}, "language": "en"}';
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(Project, TConfigurationScopes.Filter(Project, TConfigurationScope.Project, Issues));
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(Global, TConfigurationScopes.Filter(Global, TConfigurationScope.Global, Issues));
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('', TConfigurationScopes.Filter('', TConfigurationScope.Project, Issues));
end;

procedure TConfigurationScopesTests.RemovesAndReportsMisplacedKeys;
var
  Issues: TArray<TConfigurationIssue>;
  Text: string;
  Settings: TServerSettings;
begin
  Text := TConfigurationScopes.Filter('{'#10'  "platform": "Win64",'#10'  "memoryBudgetMb": 512'#10'}',
    TConfigurationScope.Project, Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsFalse(Issues[0].IsError);
  Assert.AreEqual(2, Issues[0].Range.StartPos.Line);
  Assert.AreEqual(2, Issues[0].Range.StartPos.Character);
  Assert.Contains(Issues[0].Message, '"memoryBudgetMb"');
  Assert.Contains(Issues[0].Message, 'settings.json');
  Settings := TConfigurationParser.Parse(Text, Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('Win64', Settings.Platform);
  Assert.AreEqual(TServerSettings.Default.MemoryBudgetMb, Settings.MemoryBudgetMb);
  // Umgekehrt: Projekt-Schlüssel in der globalen Datei.
  Text := TConfigurationScopes.Filter('{"platform": "Win64", "logLevel": "debug"}',
    TConfigurationScope.Global, Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, 'atlas.json');
  Settings := TConfigurationParser.Parse(Text, Issues);
  Assert.AreEqual(TServerSettings.Default.Platform, Settings.Platform);
  Assert.AreEqual('debug', Settings.LogLevel);
end;

procedure TConfigurationScopesTests.FiltersMixedObjectsPerMember;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  Settings := TConfigurationParser.Parse(TConfigurationScopes.Filter(
    '{"index": {"projectGroup": false, "exclude": ["**/Demos/**"]}}', TConfigurationScope.Project, Issues),
    Issues);
  Assert.IsTrue(Settings.IndexProjectGroup, 'Vorgabe, weil im Projekt ignoriert');
  Assert.AreEqual(1, Integer(Length(Settings.IndexExclude)));
  // Bleibt im Objekt nichts übrig, fällt es ganz weg.
  Assert.AreEqual('{}', TConfigurationScopes.Filter('{"index": {"usages": false}}', TConfigurationScope.Project,
    Issues));
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual(0, Issues[0].Range.StartPos.Line);
  Assert.AreEqual(11, Issues[0].Range.StartPos.Character);
end;

procedure TConfigurationScopesTests.PassesInvalidTextThrough;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual('{"language": ', TConfigurationScopes.Filter('{"language": ', TConfigurationScope.Project, Issues));
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('[1]', TConfigurationScopes.Filter('[1]', TConfigurationScope.Global, Issues));
end;

procedure TConfigurationScopesTests.LayersGlobalEditorProject;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  Settings := TConfigurationParser.Parse(TConfigurationScopes.Effective(
    '{"language": "en", "index": {"usages": false}, "delphiVersion": "23.0", "format": {"indentSize": 4}}',
    '{"delphiVersion": "37.0", "platform": "Linux64"}',
    '{"platform": "Win64", "index": {"exclude": ["a"]}, "language": "de", "format": {"useTabs": true}}'), Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('en', Settings.Language, 'language nur global');
  Assert.AreEqual('37.0', Settings.DelphiVersion, 'Editor über global');
  Assert.AreEqual('Win64', Settings.Platform, 'platform nur im Projekt');
  Assert.IsFalse(Settings.IndexUsages);
  Assert.AreEqual(1, Integer(Length(Settings.IndexExclude)));
  Assert.IsTrue(Settings.Formatting.UseTabs);
  Assert.AreEqual(TFormatStyle.Default.IndentSize, Settings.Formatting.IndentSize, 'format nur im Projekt');
  Assert.AreEqual('', TConfigurationScopes.Effective('', '', ''));
end;

procedure TConfigurationScopesTests.BuildsGlobalFileName;
begin
  Assert.AreEqual('', TConfigurationScopes.GlobalFile(''));
  Assert.AreEqual(IncludeTrailingPathDelimiter('C:\Daten') + 'Atlas' + PathDelim + 'settings.json',
    TConfigurationScopes.GlobalFile('C:\Daten'));
end;

procedure TConfigurationScopesTests.IgnoresCredentialsInProjectFile;
var
  Issues: TArray<TConfigurationIssue>;
  Text: string;
  Settings: TServerSettings;
begin
  Text := TConfigurationScopes.Filter('{"platform": "Win64",'#10' "token": "abc",'#10 +
    ' "rules": {"empty-except": "off", "x": {"password": "geheim", "max": 3}}}', TConfigurationScope.Project, Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Assert.IsFalse(Issues[0].IsError, 'Warnung, kein Fehler');
  Assert.AreEqual(1, Issues[0].Range.StartPos.Line);
  Assert.AreEqual(1, Issues[0].Range.StartPos.Character);
  Assert.Contains(Issues[0].Message, '"token"');
  Assert.Contains(Issues[0].Message, 'Zugangsdaten');
  Assert.Contains(Issues[1].Message, '"rules.x.password"');
  Assert.DoesNotContain(Text, 'abc');
  Assert.DoesNotContain(Text, 'geheim');
  Settings := TConfigurationParser.Parse(Text, Issues);
  Assert.AreEqual('Win64', Settings.Platform, 'der Rest gilt');
  // Adresse mit Benutzer und Passwort.
  TConfigurationScopes.Filter('{"exclude": ["https://u:p@host/x"]}', TConfigurationScope.Project, Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, 'Adresse');
  // Regel-IDs mit „password“ im Namen sind keine Zugangsdaten.
  Assert.AreEqual('{"rules": {"hardcoded-password": "error"}}', TConfigurationScopes.Filter(
    '{"rules": {"hardcoded-password": "error"}}', TConfigurationScope.Project, Issues));
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

procedure TConfigurationScopesTests.IgnoresAbsolutePathsInProjectFile;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  Settings := TConfigurationParser.Parse(TConfigurationScopes.Filter(
    '{"project": "C:\\Users\\marco\\Kasse.dproj", "exclude": ["Generated/**", "D:\\Fremd\\**"], ' +
    '"testUnits": {"folder": "\\\\server\\tests", "project": "Tests\\Tests.dproj"}, ' +
    '"index": {"exclude": ["//server/x/**"]}, "overrides": [{"files": ["C:/a/*.pas", "Tests/**"], ' +
    '"rules": {"*": "off"}}]}', TConfigurationScope.Project, Issues), Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'gefilterter Text ist gültig');
  Assert.AreEqual('', Settings.Project);
  Assert.AreEqual(1, Integer(Length(Settings.Exclude)));
  Assert.AreEqual('Generated/**', Settings.Exclude[0]);
  Assert.AreEqual('', Settings.TestUnits.Folder);
  Assert.AreEqual('Tests\Tests.dproj', Settings.TestUnits.Project);
  Assert.AreEqual(0, Integer(Length(Settings.IndexExclude)));
  Assert.AreEqual(1, Integer(Length(Settings.Overrides)));
  Assert.AreEqual(1, Integer(Length(Settings.Overrides[0].Files)));
  Assert.AreEqual('Tests/**', Settings.Overrides[0].Files[0]);
  // Gemeldet: project, exclude, testUnits.folder, index.exclude, overrides.files.
  TConfigurationScopes.Filter('{"project": "C:\\Kasse.dproj", "exclude": ["D:\\x"], ' +
    '"testUnits": {"folder": "\\\\s\\t"}, "index": {"exclude": ["//s/x"]}, ' +
    '"overrides": [{"files": ["C:/a"]}]}', TConfigurationScope.Project, Issues);
  Assert.AreEqual(5, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"project"');
  Assert.Contains(Issues[0].Message, 'absolute Pfade');
  Assert.Contains(Issues[4].Message, '"overrides.files"');
end;

procedure TConfigurationScopesTests.KeepsRelativePathsAndGlobs;
const
  Text = '{"project": "App\\Kasse.dproj", "exclude": ["/Generated/**", "..\\Gemeinsam\\**"], ' +
    '"testUnits": {"folder": "..\\Tests"}, "slashCommands": {"headerTemplate": "C:\\x"}}';
var
  Issues: TArray<TConfigurationIssue>;
  Filtered: string;
begin
  // slashCommands gehört nach settings.json und wird nur deshalb gemeldet; Pfade ab dem Projektordner und
  // relative Pfade bleiben.
  Filtered := TConfigurationScopes.Filter(Text, TConfigurationScope.Project, Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"slashCommands"');
  Assert.Contains(Filtered, '"/Generated/**"');
  Assert.Contains(Filtered, '..\\Gemeinsam');
  Assert.Contains(Filtered, '"App\\Kasse.dproj"');
end;

procedure TConfigurationScopesTests.GlobalFileKeepsPersonalPaths;
const
  Text = '{"logFile": "C:\\Users\\marco\\atlas.log", "traceFile": "D:\\trace.json"}';
var
  Issues: TArray<TConfigurationIssue>;
begin
  // settings.json ist persönlich: absolute Pfade bleiben, keine Meldung.
  Assert.AreEqual(Text, TConfigurationScopes.Filter(Text, TConfigurationScope.Global, Issues));
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

procedure TConfigurationScopesTests.ExperimentalKeysNeedMasterSwitch;
const
  Paths: array[0..1] of string = ('refactoring.liveRename', 'smartPaste');
var
  List: TArray<string>;
  Issues: TArray<TConfigurationIssue>;
  Text: string;
begin
  List := nil;
  for Text in Paths do
    List := List + [Text];
  // Hauptschalter: global, Vorgabe aus, vom Parser gelesen.
  Assert.IsTrue(TConfigurationScopes.ScopeOf('experimental.enabled') = TConfigurationScope.Global);
  Assert.IsFalse(TServerSettings.Default.ExperimentalEnabled);
  Assert.IsTrue(TConfigurationParser.Parse('{"experimental": {"enabled": true}}', Issues).ExperimentalEnabled);
  Assert.AreEqual(0, Integer(Length(Issues)));
  TConfigurationParser.Parse('{"experimental": {"enabled": true, "x": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'unbekanntes Glied gemeldet');
  Assert.IsFalse(TConfigurationScopes.ExperimentalEnabled('{"experimental": {"enabled": false}}'));
  Assert.IsFalse(TConfigurationScopes.ExperimentalEnabled(''));
  // Ohne Hauptschalter: Glied und ganzer Schlüssel fallen weg, die übrigen bleiben.
  Text := TConfigurationScopes.WithoutExperimental(
    '{"refactoring": {"liveRename": true, "preview": false}, "smartPaste": true, "metrics": false}', List);
  Assert.AreEqual('{"refactoring": {"preview": false}, "metrics": false}', Text);
  // Mit Hauptschalter bleibt der Text, wie er ist.
  Text := '{"experimental": {"enabled": true}, "smartPaste": true}';
  Assert.AreEqual(Text, TConfigurationScopes.WithoutExperimental(Text, List));
  // Ohne experimentelle Schlüssel, ohne Liste, bei ungültigem Text: unverändert.
  Assert.AreEqual('{"metrics": false}', TConfigurationScopes.WithoutExperimental('{"metrics": false}', List));
  Assert.AreEqual('{"smartPaste": true}', TConfigurationScopes.WithoutExperimental('{"smartPaste": true}', nil));
  Assert.AreEqual('{kaputt', TConfigurationScopes.WithoutExperimental('{kaputt', List));
  // Die echte Liste aus dem Schema enthält nie den Hauptschalter.
  for Text in ExperimentalSettingPaths do
    Assert.AreNotEqual('experimental.enabled', Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TConfigurationScopesTests);

end.
