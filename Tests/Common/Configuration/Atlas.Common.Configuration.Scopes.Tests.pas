unit Atlas.Common.Configuration.Scopes.Tests;

// Tests für den Ort der Einstellungen: jeder Schlüssel in genau einer Datei.

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
  Assert.IsTrue(TConfigurationScopes.ScopeOf('rules') = TConfigurationScope.Project);
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
      Assert.AreNotEqual(GlobalPath, ProjectPath);
      // Ein ganzes Objekt an einem Ort und eines seiner Glieder am anderen wäre widersprüchlich.
      Assert.IsFalse(GlobalPath.StartsWith(ProjectPath + '.'), GlobalPath);
      Assert.IsFalse(ProjectPath.StartsWith(GlobalPath + '.'), ProjectPath);
    end;
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
  Text := TConfigurationScopes.Filter('{"rules": {"empty-except": "off"}, "logLevel": "debug"}',
    TConfigurationScope.Global, Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, 'atlas.json');
  Settings := TConfigurationParser.Parse(Text, Issues);
  Assert.AreEqual(0, Integer(Length(Settings.Rules)));
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

initialization
  TDUnitX.RegisterTestFixture(TConfigurationScopesTests);

end.
