unit Atlas.Core.Settings.SchemaCheck.Tests;

// Tests für die Prüfung einer atlas.json gegen atlas.schema.json (#759):
// Typen, enum, oneOf, unbekannte Schlüssel, Listen, Grenzen und der Ort
// (x-scope) der Schlüssel.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSchemaCheckTests = class
  public
    [Test]
    procedure AcceptsValidProjectFile;
    [Test]
    procedure ReportsTypeAndEnum;
    [Test]
    procedure ChecksOneOf;
    [Test]
    procedure ReportsUnknownKeysAndItems;
    [Test]
    procedure ChecksScope;
    [Test]
    procedure ChecksLimitsAndRequired;
    [Test]
    procedure RejectsInvalidJson;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.SchemaCheck;

function Joined(const AIssues: TArray<string>): string;
begin
  Result := string.Join(' | ', AIssues);
end;

{ TAtlasSchemaCheckTests }

procedure TAtlasSchemaCheckTests.AcceptsValidProjectFile;
var
  mIssues: TArray<string>;
begin
  Assert.IsTrue(TAtlasSchemaCheck.Validate('{' + sLineBreak +
    '  // Kommentare wie in atlas.json erlaubt' + sLineBreak +
    '  "$schema": "./atlas.schema.json",' + sLineBreak +
    '  "profile": {"editor": "standard", "cli": "strict"},' + sLineBreak +
    '  "rules": {"empty-except": "error", "metric-length": {"severity": "warning", "max": 80}},' + sLineBreak +
    '  "sortUses": true,' + sLineBreak +
    '  "exclude": ["ThirdParty/**"]' + sLineBreak +
    '}', AtlasSchemaJson, 'project', mIssues), Joined(mIssues));
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsTrue(TAtlasSchemaCheck.Validate('{}', AtlasSchemaJson, 'project', mIssues));
end;

procedure TAtlasSchemaCheckTests.ReportsTypeAndEnum;
var
  mIssues: TArray<string>;
begin
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"excludeTests": "ja", "minConfidence": "sehr"}', AtlasSchemaJson,
    'project', mIssues));
  Assert.AreEqual(2, Integer(Length(mIssues)), Joined(mIssues));
  Assert.Contains(mIssues[0], 'excludeTests: erwartet boolean');
  Assert.Contains(mIssues[1], 'minConfidence: Wert "sehr" ist nicht erlaubt');
  // Eine Zahl ist kein Text, auch wenn System.JSON sie als TJSONString führt.
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"testProfile": 1}', AtlasSchemaJson, 'project', mIssues));
  Assert.Contains(Joined(mIssues), 'testProfile: erwartet string');
  // Typliste: boolean oder string.
  Assert.IsTrue(TAtlasSchemaCheck.Validate('{"sortUses": "namespace"}', AtlasSchemaJson, 'project', mIssues),
    Joined(mIssues));
end;

procedure TAtlasSchemaCheckTests.ChecksOneOf;
var
  mIssues: TArray<string>;
begin
  Assert.IsTrue(TAtlasSchemaCheck.Validate('{"profile": "fast"}', AtlasSchemaJson, 'project', mIssues));
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"profile": ["fast"]}', AtlasSchemaJson, 'project', mIssues));
  Assert.Contains(Joined(mIssues), 'profile: passt zu keiner erlaubten Form');
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"profile": {"editr": "fast"}}', AtlasSchemaJson, 'project', mIssues));
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"rules": {"empty-except": "laut"}}', AtlasSchemaJson, 'project',
    mIssues));
  Assert.Contains(Joined(mIssues), 'rules.empty-except');
end;

procedure TAtlasSchemaCheckTests.ReportsUnknownKeysAndItems;
var
  mIssues: TArray<string>;
begin
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"profil": "fast"}', AtlasSchemaJson, 'project', mIssues));
  Assert.Contains(Joined(mIssues), 'profil: unbekannter Schlüssel');
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"exclude": ["a", 2]}', AtlasSchemaJson, 'project', mIssues));
  Assert.Contains(Joined(mIssues), 'exclude[1]: erwartet string');
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"overrides": [{"files": ["x"], "rules": {"*": "aus"}}]}',
    AtlasSchemaJson, 'project', mIssues));
  Assert.Contains(Joined(mIssues), 'overrides[0].rules.*');
end;

procedure TAtlasSchemaCheckTests.ChecksScope;
var
  mIssues: TArray<string>;
begin
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"logLevel": "info"}', AtlasSchemaJson, 'project', mIssues));
  Assert.Contains(Joined(mIssues), 'logLevel: gehört in die Einstellungen "global"');
  Assert.IsTrue(TAtlasSchemaCheck.Validate('{"logLevel": "info"}', AtlasSchemaJson, 'global', mIssues));
  Assert.IsTrue(TAtlasSchemaCheck.Validate('{"logLevel": "info"}', AtlasSchemaJson, '', mIssues));
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"exclude": []}', AtlasSchemaJson, 'global', mIssues));
end;

procedure TAtlasSchemaCheckTests.ChecksLimitsAndRequired;
var
  mIssues: TArray<string>;
begin
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"memoryBudgetMb": -5}', AtlasSchemaJson, 'global', mIssues));
  Assert.Contains(Joined(mIssues), 'memoryBudgetMb: kleiner als');
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"memoryBudgetMb": 1.5}', AtlasSchemaJson, 'global', mIssues));
  Assert.Contains(Joined(mIssues), 'memoryBudgetMb: erwartet integer');
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"overrides": [{"rules": {}}]}', AtlasSchemaJson, 'project', mIssues));
  Assert.Contains(Joined(mIssues), 'overrides[0].files: fehlt');
end;

procedure TAtlasSchemaCheckTests.RejectsInvalidJson;
var
  mIssues: TArray<string>;
begin
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"profile": ', AtlasSchemaJson, 'project', mIssues));
  Assert.Contains(Joined(mIssues), 'kein gültiges JSON-Objekt');
  Assert.IsFalse(TAtlasSchemaCheck.Validate('[1]', AtlasSchemaJson, 'project', mIssues));
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{}', 'kein Schema', 'project', mIssues));
  Assert.Contains(Joined(mIssues), 'Schema nicht lesbar');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSchemaCheckTests);

end.
