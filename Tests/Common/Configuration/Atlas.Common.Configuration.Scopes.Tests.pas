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
  Assert.AreEqual<TConfigurationScope>(TConfigurationScope.Global, TConfigurationScopes.ScopeOf('index.projectGroup'));
  Assert.AreEqual<TConfigurationScope>(TConfigurationScope.Project, TConfigurationScopes.ScopeOf('index.exclude'));
  Assert.AreEqual<TConfigurationScope>(TConfigurationScope.Global, TConfigurationScopes.ScopeOf('memoryBudgetMb'));
  Assert.AreEqual<TConfigurationScope>(TConfigurationScope.Global,
    TConfigurationScopes.ScopeOf('hints.xmlDocFull'), 'erbt von hints');
  Assert.AreEqual<TConfigurationScope>(TConfigurationScope.Both,
    TConfigurationScopes.ScopeOf('rules'), 'global und Projekt');
  Assert.AreEqual<TConfigurationScope>(TConfigurationScope.Project, TConfigurationScopes.ScopeOf('format.indentSize'));
  Assert.AreEqual<TConfigurationScope>(TConfigurationScope.Global, TConfigurationScopes.ScopeOf('completion.matching'));
  Assert.AreEqual<TConfigurationScope>(TConfigurationScope.Project,
    TConfigurationScopes.ScopeOf('completion.senderCast'));
  Assert.AreEqual<TConfigurationScope>(TConfigurationScope.Unknown, TConfigurationScopes.ScopeOf('unbekannt'));
  Assert.IsTrue(TConfigurationScopes.IsMixed('index'));
  Assert.IsTrue(TConfigurationScopes.IsMixed('completion'));
  Assert.IsFalse(TConfigurationScopes.IsMixed('hints'));
  Assert.IsFalse(TConfigurationScopes.IsMixed('rules'));
end;

procedure TConfigurationScopesTests.ListsAreDisjoint;
var
  mGlobalPath, mProjectPath: string;
begin
  for mGlobalPath in cGlobalSettingPaths do
  begin
    for mProjectPath in cProjectSettingPaths do
    begin
      // rules, tasks (#900) und excludeTests (x-scope "both") stehen absichtlich in beiden Listen.
      if (mGlobalPath = mProjectPath) and ((mGlobalPath = 'rules') or (mGlobalPath = 'tasks') or
        (mGlobalPath = 'excludeTests')) then
      begin
        Continue;
      end;
      Assert.AreNotEqual(mGlobalPath, mProjectPath);
      // Ein ganzes Objekt an einem Ort und eines seiner Glieder am anderen wäre widersprüchlich.
      Assert.IsFalse(mGlobalPath.StartsWith(mProjectPath + '.'), mGlobalPath);
      Assert.IsFalse(mProjectPath.StartsWith(mGlobalPath + '.'), mProjectPath);
    end;
  end;
end;

procedure TConfigurationScopesTests.GlobalRulesProjectOverridesPerRule;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  // Global erlaubt, ohne Meldung.
  TConfigurationScopes.Filter('{"rules": {"no-with": "off"}}', TConfigurationScope.Global, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  TConfigurationScopes.Filter('{"rules": {"no-with": "off"}}', TConfigurationScope.Project, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.Parse(TConfigurationScopes.Effective(
    '{"rules": {"no-with": "off", "magic-number": "hint"}}', '', '{"rules": {"magic-number": "error"}}'), mIssues);
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(mSettings.RuleSeverity('no-with', TRuleSeverity.Warning)), 'global');
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mSettings.RuleSeverity('magic-number', TRuleSeverity.Warning)),
    'Projekt übersteuert');
end;

procedure TConfigurationScopesTests.KeepsTextWithoutMisplacedKeys;
const
  cProject = '// Kommentar'#10'{"rules": {"empty-except": "off"}, "unbekannt": 1, "$schema": "x"}';
  cGlobal = '{"index": {"usages": false}, "language": "en"}';
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(cProject, TConfigurationScopes.Filter(cProject, TConfigurationScope.Project, mIssues));
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(cGlobal, TConfigurationScopes.Filter(cGlobal, TConfigurationScope.Global, mIssues));
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('', TConfigurationScopes.Filter('', TConfigurationScope.Project, mIssues));
end;

procedure TConfigurationScopesTests.RemovesAndReportsMisplacedKeys;
var
  mIssues: TArray<TConfigurationIssue>;
  mText: string;
  mSettings: TServerSettings;
begin
  mText := TConfigurationScopes.Filter('{'#10'  "platform": "Win64",'#10'  "memoryBudgetMb": 512'#10'}',
    TConfigurationScope.Project, mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsFalse(mIssues[0].IsError);
  Assert.AreEqual(2, mIssues[0].Range.StartPos.Line);
  Assert.AreEqual(2, mIssues[0].Range.StartPos.Character);
  Assert.Contains(mIssues[0].Message, '"memoryBudgetMb"');
  Assert.Contains(mIssues[0].Message, 'settings.json');
  mSettings := TConfigurationParser.Parse(mText, mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('Win64', mSettings.Platform);
  Assert.AreEqual(TServerSettings.Default.MemoryBudgetMb, mSettings.MemoryBudgetMb);
  // Umgekehrt: Projekt-Schlüssel in der globalen Datei.
  mText := TConfigurationScopes.Filter('{"platform": "Win64", "logLevel": "debug"}',
    TConfigurationScope.Global, mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, 'atlas.json');
  mSettings := TConfigurationParser.Parse(mText, mIssues);
  Assert.AreEqual(TServerSettings.Default.Platform, mSettings.Platform);
  Assert.AreEqual('debug', mSettings.LogLevel);
end;

procedure TConfigurationScopesTests.FiltersMixedObjectsPerMember;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  mSettings := TConfigurationParser.Parse(TConfigurationScopes.Filter(
    '{"index": {"projectGroup": false, "exclude": ["**/Demos/**"]}}', TConfigurationScope.Project, mIssues),
    mIssues);
  Assert.IsTrue(mSettings.IndexProjectGroup, 'Vorgabe, weil im Projekt ignoriert');
  Assert.AreEqual(1, Integer(Length(mSettings.IndexExclude)));
  // Bleibt im Objekt nichts übrig, fällt es ganz weg.
  Assert.AreEqual('{}', TConfigurationScopes.Filter('{"index": {"usages": false}}', TConfigurationScope.Project,
    mIssues));
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual(0, mIssues[0].Range.StartPos.Line);
  Assert.AreEqual(11, mIssues[0].Range.StartPos.Character);
end;

procedure TConfigurationScopesTests.PassesInvalidTextThrough;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual('{"language": ', TConfigurationScopes.Filter('{"language": ', TConfigurationScope.Project, mIssues));
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('[1]', TConfigurationScopes.Filter('[1]', TConfigurationScope.Global, mIssues));
end;

procedure TConfigurationScopesTests.LayersGlobalEditorProject;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  mSettings := TConfigurationParser.Parse(TConfigurationScopes.Effective(
    '{"language": "en", "index": {"usages": false}, "delphiVersion": "23.0", "format": {"indentSize": 4}}',
    '{"delphiVersion": "37.0", "platform": "Linux64"}',
    '{"platform": "Win64", "index": {"exclude": ["a"]}, "language": "de", "format": {"useTabs": true}}'), mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('en', mSettings.Language, 'language nur global');
  Assert.AreEqual('37.0', mSettings.DelphiVersion, 'Editor über global');
  Assert.AreEqual('Win64', mSettings.Platform, 'platform nur im Projekt');
  Assert.IsFalse(mSettings.IndexUsages);
  Assert.AreEqual(1, Integer(Length(mSettings.IndexExclude)));
  Assert.IsTrue(mSettings.Formatting.UseTabs);
  Assert.AreEqual(TFormatStyle.Default.IndentSize, mSettings.Formatting.IndentSize, 'format nur im Projekt');
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
  mIssues: TArray<TConfigurationIssue>;
  mText: string;
  mSettings: TServerSettings;
begin
  mText := TConfigurationScopes.Filter('{"platform": "Win64",'#10' "token": "abc",'#10 +
    ' "rules": {"empty-except": "off", "x": {"password": "geheim", "max": 3}}}', TConfigurationScope.Project, mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.IsFalse(mIssues[0].IsError, 'Warnung, kein Fehler');
  Assert.AreEqual(1, mIssues[0].Range.StartPos.Line);
  Assert.AreEqual(1, mIssues[0].Range.StartPos.Character);
  Assert.Contains(mIssues[0].Message, '"token"');
  Assert.Contains(mIssues[0].Message, 'Zugangsdaten');
  Assert.Contains(mIssues[1].Message, '"rules.x.password"');
  Assert.DoesNotContain(mText, 'abc');
  Assert.DoesNotContain(mText, 'geheim');
  mSettings := TConfigurationParser.Parse(mText, mIssues);
  Assert.AreEqual('Win64', mSettings.Platform, 'der Rest gilt');
  // Adresse mit Benutzer und Passwort.
  TConfigurationScopes.Filter('{"exclude": ["https://u:p@host/x"]}', TConfigurationScope.Project, mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, 'Adresse');
  // Regel-IDs mit „password“ im Namen sind keine Zugangsdaten.
  Assert.AreEqual('{"rules": {"hardcoded-password": "error"}}', TConfigurationScopes.Filter(
    '{"rules": {"hardcoded-password": "error"}}', TConfigurationScope.Project, mIssues));
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;

procedure TConfigurationScopesTests.IgnoresAbsolutePathsInProjectFile;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  mSettings := TConfigurationParser.Parse(TConfigurationScopes.Filter(
    '{"project": "C:\\Users\\marco\\Kasse.dproj", "exclude": ["Generated/**", "D:\\Fremd\\**"], ' +
    '"testUnits": {"folder": "\\\\server\\tests", "project": "Tests\\Tests.dproj"}, ' +
    '"index": {"exclude": ["//server/x/**"]}, "overrides": [{"files": ["C:/a/*.pas", "Tests/**"], ' +
    '"rules": {"*": "off"}}]}', TConfigurationScope.Project, mIssues), mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'gefilterter Text ist gültig');
  Assert.AreEqual('', mSettings.Project);
  Assert.AreEqual(1, Integer(Length(mSettings.Exclude)));
  Assert.AreEqual('Generated/**', mSettings.Exclude[0]);
  Assert.AreEqual('', mSettings.TestUnits.Folder);
  Assert.AreEqual('Tests\Tests.dproj', mSettings.TestUnits.Project);
  Assert.AreEqual(0, Integer(Length(mSettings.IndexExclude)));
  Assert.AreEqual(1, Integer(Length(mSettings.Overrides)));
  Assert.AreEqual(1, Integer(Length(mSettings.Overrides[0].Files)));
  Assert.AreEqual('Tests/**', mSettings.Overrides[0].Files[0]);
  // Gemeldet: project, exclude, testUnits.folder, index.exclude, overrides.files.
  TConfigurationScopes.Filter('{"project": "C:\\Kasse.dproj", "exclude": ["D:\\x"], ' +
    '"testUnits": {"folder": "\\\\s\\t"}, "index": {"exclude": ["//s/x"]}, ' +
    '"overrides": [{"files": ["C:/a"]}]}', TConfigurationScope.Project, mIssues);
  Assert.AreEqual(5, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"project"');
  Assert.Contains(mIssues[0].Message, 'absolute Pfade');
  Assert.Contains(mIssues[4].Message, '"overrides.files"');
end;

procedure TConfigurationScopesTests.KeepsRelativePathsAndGlobs;
const
  cText = '{"project": "App\\Kasse.dproj", "exclude": ["/Generated/**", "..\\Gemeinsam\\**"], ' +
    '"testUnits": {"folder": "..\\Tests"}, "slashCommands": {"headerTemplate": "C:\\x"}}';
var
  mIssues: TArray<TConfigurationIssue>;
  mFiltered: string;
begin
  // slashCommands gehört nach settings.json und wird nur deshalb gemeldet; Pfade ab dem Projektordner und
  // relative Pfade bleiben.
  mFiltered := TConfigurationScopes.Filter(cText, TConfigurationScope.Project, mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"slashCommands"');
  Assert.Contains(mFiltered, '"/Generated/**"');
  Assert.Contains(mFiltered, '..\\Gemeinsam');
  Assert.Contains(mFiltered, '"App\\Kasse.dproj"');
end;

procedure TConfigurationScopesTests.GlobalFileKeepsPersonalPaths;
const
  cText = '{"logFile": "C:\\Users\\marco\\atlas.log", "traceFile": "D:\\trace.json"}';
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // settings.json ist persönlich: absolute Pfade bleiben, keine Meldung.
  Assert.AreEqual(cText, TConfigurationScopes.Filter(cText, TConfigurationScope.Global, mIssues));
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;

procedure TConfigurationScopesTests.ExperimentalKeysNeedMasterSwitch;
const
  cPaths: array[0..1] of string = ('refactoring.liveRename', 'smartPaste');
var
  mList: TArray<string>;
  mIssues: TArray<TConfigurationIssue>;
  mText: string;
begin
  mList := nil;
  for mText in cPaths do
  begin
    mList := mList + [mText];
  end;
  // Hauptschalter: global, Vorgabe aus, vom Parser gelesen.
  Assert.AreEqual<TConfigurationScope>(TConfigurationScope.Global,
    TConfigurationScopes.ScopeOf('experimental.enabled'));
  Assert.IsFalse(TServerSettings.Default.ExperimentalEnabled);
  Assert.IsTrue(TConfigurationParser.Parse('{"experimental": {"enabled": true}}', mIssues).ExperimentalEnabled);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  TConfigurationParser.Parse('{"experimental": {"enabled": true, "x": 1}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'unbekanntes Glied gemeldet');
  Assert.IsFalse(TConfigurationScopes.ExperimentalEnabled('{"experimental": {"enabled": false}}'));
  Assert.IsFalse(TConfigurationScopes.ExperimentalEnabled(''));
  // Ohne Hauptschalter: Glied und ganzer Schlüssel fallen weg, die übrigen bleiben.
  mText := TConfigurationScopes.WithoutExperimental(
    '{"refactoring": {"liveRename": true, "preview": false}, "smartPaste": true, "metrics": false}', mList);
  Assert.AreEqual('{"refactoring": {"preview": false}, "metrics": false}', mText);
  // Mit Hauptschalter bleibt der Text, wie er ist.
  mText := '{"experimental": {"enabled": true}, "smartPaste": true}';
  Assert.AreEqual(mText, TConfigurationScopes.WithoutExperimental(mText, mList));
  // Ohne experimentelle Schlüssel, ohne Liste, bei ungültigem Text: unverändert.
  Assert.AreEqual('{"metrics": false}', TConfigurationScopes.WithoutExperimental('{"metrics": false}', mList));
  Assert.AreEqual('{"smartPaste": true}', TConfigurationScopes.WithoutExperimental('{"smartPaste": true}', nil));
  Assert.AreEqual('{kaputt', TConfigurationScopes.WithoutExperimental('{kaputt', mList));
  // Die echte Liste aus dem Schema enthält nie den Hauptschalter.
  for mText in ExperimentalSettingPaths do
  begin
    Assert.AreNotEqual('experimental.enabled', mText);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TConfigurationScopesTests);

end.
