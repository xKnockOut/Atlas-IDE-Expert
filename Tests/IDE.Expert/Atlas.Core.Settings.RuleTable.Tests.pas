unit Atlas.Core.Settings.RuleTable.Tests;

// Tests für das Modell der Seite „Prüfregeln“ (#909): Katalogfelder,
// Optionen, Ausnahmen, Hauptschalter je Gruppe und Suche; Gegenregeln (#1025).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasRuleTableTests = class
  public
    [Test]
    procedure RowsCarryCatalogFieldsAndOptionValues;
    [Test]
    procedure GroupKeysAreNoRuleRows;
    [Test]
    procedure OptionTurnsTextIntoObjectAndBack;
    [Test]
    procedure ExcludeIsWrittenAndRemoved;
    [Test]
    procedure GroupSwitchWritesAndRemovesKey;
    [Test]
    procedure FilterByGroupAndText;
    [Test]
    procedure EffectiveSeverityFallsBackToGlobalAndDefault;
    [Test]
    procedure OptionTextShowsValueOrDefault;
    [Test]
    procedure OptionJsonChecksKind;
    [Test]
    procedure ListTextRoundTrips;
    [Test]
    procedure SearchFindsCategory;
    [Test]
    procedure ChangesListOnlyChangedRules;
    [Test]
    procedure OverridingRuleOnlyWhenEnabled;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Settings.RuleTable;

const
  CatalogText =
    '{"rules": [' +
    '{"id": "magic-number", "name": "Magische Zahl", "category": "code-smell", "severity": "hint",' +
    ' "group": "style", "description": "Zahl ohne Namen", "bad": "X := 42;", "good": "X := Answer;",' +
    ' "options": [{"name": "ignore", "type": "string-list", "default": ["0", "1"], "description": "erlaubt"}],' +
    ' "experimental": true},' +
    '{"id": "empty-except", "name": "Leeres except", "category": "bug", "severity": "warning",' +
    ' "group": "exceptions", "description": "Fehler werden verschluckt", "options": []}]}';

function Catalog: TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(CatalogText);
end;

procedure TAtlasRuleTableTests.RowsCarryCatalogFieldsAndOptionValues;
var
  Value: TJSONValue;
  Rows: TArray<TAtlasRuleRow>;
begin
  Value := Catalog;
  try
    Rows := TAtlasRuleTable.Rows(Value,
      '{"magic-number": {"severity": "warning", "ignore": ["2"], "own": 5, "exclude": ["Legacy/**"]}}');
    Assert.AreEqual(2, Integer(Length(Rows)));
    Assert.AreEqual('style', Rows[0].Group);
    Assert.AreEqual('Zahl ohne Namen', Rows[0].Description);
    Assert.AreEqual('X := 42;', Rows[0].Bad);
    Assert.AreEqual('X := Answer;', Rows[0].Good);
    Assert.IsTrue(Rows[0].Experimental);
    Assert.AreEqual(2, Integer(Length(Rows[0].Options)));
    Assert.AreEqual('ignore', Rows[0].Options[0].Name);
    Assert.AreEqual('string-list', Rows[0].Options[0].Kind);
    Assert.AreEqual('["0","1"]', Rows[0].Options[0].DefaultJson);
    Assert.AreEqual('["2"]', Rows[0].Options[0].ValueJson);
    // Unbekannte Option aus der Datei bleibt sichtbar.
    Assert.AreEqual('own', Rows[0].Options[1].Name);
    Assert.AreEqual('json', Rows[0].Options[1].Kind);
    Assert.AreEqual('5', Rows[0].Options[1].ValueJson);
    Assert.AreEqual(1, Integer(Length(Rows[0].Exclude)));
    Assert.AreEqual('Legacy/**', Rows[0].Exclude[0]);
    Assert.IsFalse(Rows[1].Experimental);
    Assert.AreEqual(0, Integer(Length(Rows[1].Options)));
  finally
    Value.Free;
  end;
end;

procedure TAtlasRuleTableTests.GroupKeysAreNoRuleRows;
var
  Rows: TArray<TAtlasRuleRow>;
begin
  Rows := TAtlasRuleTable.Rows(nil, '{"group:style": "off", "no-with": "error"}');
  Assert.AreEqual(1, Integer(Length(Rows)));
  Assert.AreEqual('no-with', Rows[0].Id);
end;

procedure TAtlasRuleTableTests.OptionTurnsTextIntoObjectAndBack;
var
  Rules: string;
begin
  Rules := TAtlasRuleTable.WithOption('{"magic-number": "warning"}', 'magic-number', 'ignore', '["0"]');
  Assert.AreEqual('{"magic-number":{"severity":"warning","ignore":["0"]}}', Rules);
  Rules := TAtlasRuleTable.WithOption(Rules, 'magic-number', 'ignore', '');
  Assert.AreEqual('{"magic-number":"warning"}', Rules);
  Rules := TAtlasRuleTable.WithOption('', 'metric-method-length', 'max', '80');
  Assert.AreEqual('{"metric-method-length":{"max":80}}', Rules);
  Rules := TAtlasRuleTable.WithOption(Rules, 'metric-method-length', 'max', '');
  Assert.AreEqual('', Rules);
  // Kein gültiges JSON: nichts ändert sich.
  Rules := TAtlasRuleTable.WithOption('{"a": "off"}', 'a', 'max', '{kaputt');
  Assert.AreEqual('{"a":"off"}', Rules);
end;

procedure TAtlasRuleTableTests.ExcludeIsWrittenAndRemoved;
var
  Rules: string;
begin
  Rules := TAtlasRuleTable.WithExclude('{"no-with": "error"}', 'no-with', ['Legacy/**', ' ', 'Alt.Unit ']);
  Assert.AreEqual('{"no-with":{"severity":"error","exclude":["Legacy/**","Alt.Unit"]}}', Rules);
  Rules := TAtlasRuleTable.WithExclude(Rules, 'no-with', nil);
  Assert.AreEqual('{"no-with":"error"}', Rules);
end;

procedure TAtlasRuleTableTests.GroupSwitchWritesAndRemovesKey;
var
  Rules: string;
begin
  Assert.AreEqual('group:style', TAtlasRuleTable.GroupKey('style'));
  Rules := TAtlasRuleTable.WithGroup('{"no-with": "error"}', 'style', False);
  Assert.AreEqual('{"no-with":"error","group:style":"off"}', Rules);
  Assert.IsTrue(TAtlasRuleTable.GroupOff(Rules, 'style'));
  Assert.IsFalse(TAtlasRuleTable.GroupOff(Rules, 'exceptions'));
  Rules := TAtlasRuleTable.WithGroup(Rules, 'style', True);
  Assert.AreEqual('{"no-with":"error"}', Rules);
  Assert.IsFalse(TAtlasRuleTable.GroupOff('', 'style'));
end;

procedure TAtlasRuleTableTests.FilterByGroupAndText;
var
  Value: TJSONValue;
  Rows: TArray<TAtlasRuleRow>;
  Hits: TArray<Integer>;
  Groups: TArray<string>;
begin
  Value := Catalog;
  try
    Rows := TAtlasRuleTable.Rows(Value, '');
    Groups := TAtlasRuleTable.Groups(Rows);
    Assert.AreEqual(2, Integer(Length(Groups)));
    Assert.AreEqual('style', Groups[0]);
    Assert.AreEqual('exceptions', Groups[1]);
    Assert.AreEqual(2, Integer(Length(TAtlasRuleTable.Filter(Rows, '', ''))));
    Hits := TAtlasRuleTable.Filter(Rows, 'exceptions', '');
    Assert.AreEqual(1, Integer(Length(Hits)));
    Assert.AreEqual(1, Hits[0]);
    // Suche in Kennung, Name und Beschreibung.
    Hits := TAtlasRuleTable.Filter(Rows, '', 'VERSCHLUCKT');
    Assert.AreEqual(1, Integer(Length(Hits)));
    Assert.AreEqual(1, Hits[0]);
    Hits := TAtlasRuleTable.Filter(Rows, '', 'magic');
    Assert.AreEqual(1, Integer(Length(Hits)));
    Assert.AreEqual(0, Hits[0]);
    Assert.AreEqual(0, Integer(Length(TAtlasRuleTable.Filter(Rows, 'style', 'except'))));
  finally
    Value.Free;
  end;
end;

procedure TAtlasRuleTableTests.EffectiveSeverityFallsBackToGlobalAndDefault;
var
  Row: TAtlasRuleRow;
begin
  Row := Default(TAtlasRuleRow);
  Row.DefaultSeverity := 'warning';
  Assert.AreEqual('warning', Row.Effective);
  Row.GlobalSeverity := 'off';
  Assert.AreEqual('off', Row.Effective);
  Assert.IsFalse(Row.Enabled);
  Row.Severity := 'error';
  Assert.AreEqual('error', Row.Effective);
  Assert.IsTrue(Row.Enabled);
end;

function Option(const AKind, ADefault, AValue: string): TAtlasRuleOption;
begin
  Result := Default(TAtlasRuleOption);
  Result.Name := 'x';
  Result.Kind := AKind;
  Result.DefaultJson := ADefault;
  Result.ValueJson := AValue;
end;

procedure TAtlasRuleTableTests.OptionTextShowsValueOrDefault;
begin
  Assert.AreEqual('0; 1', TAtlasRuleTable.OptionText(Option('string-list', '["0","1"]', '')));
  Assert.AreEqual('7', TAtlasRuleTable.OptionText(Option('string-list', '["0"]', '["7"]')));
  Assert.AreEqual('120', TAtlasRuleTable.OptionText(Option('integer', '120', '')));
  Assert.AreEqual('Prefix', TAtlasRuleTable.OptionText(Option('string', '"Prefix"', '')));
  Assert.AreEqual('true', TAtlasRuleTable.OptionText(Option('boolean', 'false', 'true')));
  Assert.AreEqual('{"a":1}', TAtlasRuleTable.OptionText(Option('json', '', '{"a":1}')));
  Assert.AreEqual('0; 1; -1', TAtlasRuleTable.OptionText(Option('number-list', '[0,1,-1]', '')));
  Assert.AreEqual('', TAtlasRuleTable.OptionText(Option('json', '', '')));
end;

procedure TAtlasRuleTableTests.OptionJsonChecksKind;
var
  Json: string;
begin
  Assert.IsTrue(TAtlasRuleTable.OptionJson('integer', ' 80 ', Json));
  Assert.AreEqual('80', Json);
  Assert.IsFalse(TAtlasRuleTable.OptionJson('integer', 'acht', Json));
  Assert.IsTrue(TAtlasRuleTable.OptionJson('boolean', 'True', Json));
  Assert.AreEqual('true', Json);
  Assert.IsFalse(TAtlasRuleTable.OptionJson('boolean', 'ja', Json));
  Assert.IsTrue(TAtlasRuleTable.OptionJson('string', 'a"b', Json));
  Assert.AreEqual('"a\"b"', Json);
  Assert.IsTrue(TAtlasRuleTable.OptionJson('string-list', '0; 1;; 2 ', Json));
  Assert.AreEqual('["0","1","2"]', Json);
  Assert.IsTrue(TAtlasRuleTable.OptionJson('number-list', '0; -1; 2.5', Json));
  Assert.AreEqual('[0,-1,2.5]', Json);
  Assert.IsFalse(TAtlasRuleTable.OptionJson('number-list', '1; zwei', Json));
  Assert.IsTrue(TAtlasRuleTable.OptionJson('json', '{"a": 1}', Json));
  Assert.AreEqual('{"a":1}', Json);
  Assert.IsFalse(TAtlasRuleTable.OptionJson('json', '{a', Json));
  // Leeres Feld: Vorgabe.
  Assert.IsTrue(TAtlasRuleTable.OptionJson('integer', '  ', Json));
  Assert.AreEqual('', Json);
end;

procedure TAtlasRuleTableTests.ListTextRoundTrips;
var
  Items: TArray<string>;
begin
  Items := TAtlasRuleTable.ParseList(' Tests\*.pas ;; Vendor.* ');
  Assert.AreEqual(2, Integer(Length(Items)));
  Assert.AreEqual('Tests\*.pas', Items[0]);
  Assert.AreEqual('Vendor.*', Items[1]);
  Assert.AreEqual('Tests\*.pas; Vendor.*', TAtlasRuleTable.ListText(Items));
  Assert.AreEqual(0, Integer(Length(TAtlasRuleTable.ParseList(''))));
  Items := nil;
end;

procedure TAtlasRuleTableTests.SearchFindsCategory;
var
  Value: TJSONValue;
  Rows: TArray<TAtlasRuleRow>;
  Found: TArray<Integer>;
begin
  Value := Catalog;
  try
    Rows := TAtlasRuleTable.Rows(Value, '');
    Found := TAtlasRuleTable.Filter(Rows, '', 'CODE-SMELL');
    Assert.AreEqual(1, Integer(Length(Found)));
    Assert.AreEqual('magic-number', Rows[Found[0]].Id);
    Assert.AreEqual(14, Integer(Length(TAtlasRuleTable.GroupIds)));
    Assert.AreEqual('find-bugs', TAtlasRuleTable.GroupIds[0]);
  finally
    Value.Free;
  end;
end;

procedure TAtlasRuleTableTests.ChangesListOnlyChangedRules;
var
  Changes: TArray<TPair<string, string>>;
begin
  Changes := TAtlasRuleTable.Changes('{"a": "off", "b": {"severity": "error"}, "c": "hint"}',
    '{"a": "off", "b": {"severity": "warning"}, "group:style": "off"}');
  Assert.AreEqual(3, Integer(Length(Changes)));
  Assert.AreEqual('rules.b', Changes[0].Key);
  Assert.AreEqual('{"severity":"warning"}', Changes[0].Value);
  Assert.AreEqual('rules.group:style', Changes[1].Key);
  Assert.AreEqual('"off"', Changes[1].Value);
  Assert.AreEqual('rules.c', Changes[2].Key);
  Assert.AreEqual('', Changes[2].Value);
  Assert.AreEqual(0, Integer(Length(TAtlasRuleTable.Changes('', ''))));
  Changes := nil;
end;

procedure TAtlasRuleTableTests.OverridingRuleOnlyWhenEnabled;
const
  Text = '{"rules": [' +
    '{"id": "redundant-begin-end", "category": "code-smell", "severity": "hint", "group": "style",' +
    ' "overriddenBy": ["missing-begin-end"]},' +
    '{"id": "missing-begin-end", "category": "code-smell", "severity": "hint", "group": "style"}]}';
var
  Value: TJSONValue;
  Rows: TArray<TAtlasRuleRow>;
begin
  Value := TJSONObject.ParseJSONValue(Text);
  try
    Rows := TAtlasRuleTable.Rows(Value, '');
    Assert.AreEqual('missing-begin-end', string.Join(',', Rows[0].OverriddenBy));
    Assert.AreEqual('missing-begin-end', TAtlasRuleTable.OverridingRule(Rows, Rows[0]));
    Assert.AreEqual('', TAtlasRuleTable.OverridingRule(Rows, Rows[1]));
    Rows := TAtlasRuleTable.Rows(Value, '{"missing-begin-end": "off"}');
    Assert.AreEqual('', TAtlasRuleTable.OverridingRule(Rows, Rows[0]));
  finally
    Value.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRuleTableTests);

end.
