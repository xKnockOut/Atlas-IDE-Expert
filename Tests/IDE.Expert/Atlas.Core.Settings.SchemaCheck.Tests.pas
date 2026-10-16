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
  Issues: TArray<string>;
begin
  Assert.IsTrue(TAtlasSchemaCheck.Validate('{' + sLineBreak +
    '  // Kommentare wie in atlas.json erlaubt' + sLineBreak +
    '  "$schema": "./atlas.schema.json",' + sLineBreak +
    '  "profile": {"editor": "standard", "cli": "strict"},' + sLineBreak +
    '  "rules": {"empty-except": "error", "metric-length": {"severity": "warning", "max": 80}},' + sLineBreak +
    '  "sortUses": true,' + sLineBreak +
    '  "exclude": ["ThirdParty/**"]' + sLineBreak +
    '}', AtlasSchemaJson, 'project', Issues), Joined(Issues));
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(TAtlasSchemaCheck.Validate('{}', AtlasSchemaJson, 'project', Issues));
end;

procedure TAtlasSchemaCheckTests.ReportsTypeAndEnum;
var
  Issues: TArray<string>;
begin
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"excludeTests": "ja", "minConfidence": "sehr"}', AtlasSchemaJson,
    'project', Issues));
  Assert.AreEqual(2, Integer(Length(Issues)), Joined(Issues));
  Assert.Contains(Issues[0], 'excludeTests: erwartet boolean');
  Assert.Contains(Issues[1], 'minConfidence: Wert "sehr" ist nicht erlaubt');
  // Eine Zahl ist kein Text, auch wenn System.JSON sie als TJSONString führt.
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"testProfile": 1}', AtlasSchemaJson, 'project', Issues));
  Assert.Contains(Joined(Issues), 'testProfile: erwartet string');
  // Typliste: boolean oder string.
  Assert.IsTrue(TAtlasSchemaCheck.Validate('{"sortUses": "namespace"}', AtlasSchemaJson, 'project', Issues),
    Joined(Issues));
end;

procedure TAtlasSchemaCheckTests.ChecksOneOf;
var
  Issues: TArray<string>;
begin
  Assert.IsTrue(TAtlasSchemaCheck.Validate('{"profile": "fast"}', AtlasSchemaJson, 'project', Issues));
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"profile": ["fast"]}', AtlasSchemaJson, 'project', Issues));
  Assert.Contains(Joined(Issues), 'profile: passt zu keiner erlaubten Form');
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"profile": {"editr": "fast"}}', AtlasSchemaJson, 'project', Issues));
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"rules": {"empty-except": "laut"}}', AtlasSchemaJson, 'project',
    Issues));
  Assert.Contains(Joined(Issues), 'rules.empty-except');
end;

procedure TAtlasSchemaCheckTests.ReportsUnknownKeysAndItems;
var
  Issues: TArray<string>;
begin
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"profil": "fast"}', AtlasSchemaJson, 'project', Issues));
  Assert.Contains(Joined(Issues), 'profil: unbekannter Schlüssel');
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"exclude": ["a", 2]}', AtlasSchemaJson, 'project', Issues));
  Assert.Contains(Joined(Issues), 'exclude[1]: erwartet string');
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"overrides": [{"files": ["x"], "rules": {"*": "aus"}}]}',
    AtlasSchemaJson, 'project', Issues));
  Assert.Contains(Joined(Issues), 'overrides[0].rules.*');
end;

procedure TAtlasSchemaCheckTests.ChecksScope;
var
  Issues: TArray<string>;
begin
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"logLevel": "info"}', AtlasSchemaJson, 'project', Issues));
  Assert.Contains(Joined(Issues), 'logLevel: gehört in die Einstellungen "global"');
  Assert.IsTrue(TAtlasSchemaCheck.Validate('{"logLevel": "info"}', AtlasSchemaJson, 'global', Issues));
  Assert.IsTrue(TAtlasSchemaCheck.Validate('{"logLevel": "info"}', AtlasSchemaJson, '', Issues));
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"exclude": []}', AtlasSchemaJson, 'global', Issues));
end;

procedure TAtlasSchemaCheckTests.ChecksLimitsAndRequired;
var
  Issues: TArray<string>;
begin
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"memoryBudgetMb": -5}', AtlasSchemaJson, 'global', Issues));
  Assert.Contains(Joined(Issues), 'memoryBudgetMb: kleiner als');
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"memoryBudgetMb": 1.5}', AtlasSchemaJson, 'global', Issues));
  Assert.Contains(Joined(Issues), 'memoryBudgetMb: erwartet integer');
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"overrides": [{"rules": {}}]}', AtlasSchemaJson, 'project', Issues));
  Assert.Contains(Joined(Issues), 'overrides[0].files: fehlt');
end;

procedure TAtlasSchemaCheckTests.RejectsInvalidJson;
var
  Issues: TArray<string>;
begin
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{"profile": ', AtlasSchemaJson, 'project', Issues));
  Assert.Contains(Joined(Issues), 'kein gültiges JSON-Objekt');
  Assert.IsFalse(TAtlasSchemaCheck.Validate('[1]', AtlasSchemaJson, 'project', Issues));
  Assert.IsFalse(TAtlasSchemaCheck.Validate('{}', 'kein Schema', 'project', Issues));
  Assert.Contains(Joined(Issues), 'Schema nicht lesbar');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSchemaCheckTests);

end.
