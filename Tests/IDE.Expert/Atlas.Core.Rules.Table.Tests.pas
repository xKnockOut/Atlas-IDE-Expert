unit Atlas.Core.Rules.Table.Tests;

// Tests für das Modell der Seite „Prüfregeln“ (#909): Katalogfelder,
// Optionen, Ausnahmen, Hauptschalter je Gruppe und Suche; Gegenregeln (#1025).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Rules')]
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
    procedure GroupOptionKeepsSwitchAndBack;
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
    [Test]
    procedure ObjectListTableRoundTrips;
    [Test]
    procedure RuleRowsFromCatalogAndFile;
    [Test]
    procedure RuleSeverityKeepsOptions;
    [Test]
    procedure SeverityChangeTouchesOnlyThatRule;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Rules.Table;

const
  cCatalogText =
    '{"rules": [' +
    '{"id": "magic-number", "name": "Magische Zahl", "category": "code-smell", "severity": "hint",' +
    ' "group": "style", "description": "Zahl ohne Namen", "bad": "X := 42;", "good": "X := Answer;",' +
    ' "options": [{"name": "ignore", "type": "string-list", "default": ["0", "1"], "description": "erlaubt"}],' +
    ' "experimental": true},' +
    '{"id": "empty-except", "name": "Leeres except", "category": "bug", "severity": "warning",' +
    ' "group": "exceptions", "description": "Fehler werden verschluckt", "options": []}]}';

function Catalog: TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(cCatalogText);
end;

procedure TAtlasRuleTableTests.RowsCarryCatalogFieldsAndOptionValues;
var
  mValue: TJSONValue;
  mRows: TArray<TAtlasRuleRow>;
begin
  mValue := Catalog;
  try
    mRows := TAtlasRuleTable.Rows(mValue,
      '{"magic-number": {"severity": "warning", "ignore": ["2"], "own": 5, "exclude": ["Legacy/**"]}}');
    Assert.AreEqual(2, Integer(Length(mRows)));
    Assert.AreEqual('style', mRows[0].Group);
    Assert.AreEqual('Zahl ohne Namen', mRows[0].Description);
    Assert.AreEqual('X := 42;', mRows[0].Bad);
    Assert.AreEqual('X := Answer;', mRows[0].Good);
    Assert.IsTrue(mRows[0].Experimental);
    Assert.AreEqual(2, Integer(Length(mRows[0].Options)));
    Assert.AreEqual('ignore', mRows[0].Options[0].Name);
    Assert.AreEqual('string-list', mRows[0].Options[0].Kind);
    Assert.AreEqual('["0","1"]', mRows[0].Options[0].DefaultJson);
    Assert.AreEqual('["2"]', mRows[0].Options[0].ValueJson);
    // Unbekannte Option aus der Datei bleibt sichtbar.
    Assert.AreEqual('own', mRows[0].Options[1].Name);
    Assert.AreEqual('json', mRows[0].Options[1].Kind);
    Assert.AreEqual('5', mRows[0].Options[1].ValueJson);
    Assert.AreEqual(1, Integer(Length(mRows[0].Exclude)));
    Assert.AreEqual('Legacy/**', mRows[0].Exclude[0]);
    Assert.IsFalse(mRows[1].Experimental);
    Assert.AreEqual(0, Integer(Length(mRows[1].Options)));
  finally
    mValue.Free;
  end;
end;

procedure TAtlasRuleTableTests.GroupKeysAreNoRuleRows;
var
  mRows: TArray<TAtlasRuleRow>;
begin
  mRows := TAtlasRuleTable.Rows(nil, '{"group:style": "off", "no-with": "error"}');
  Assert.AreEqual(1, Integer(Length(mRows)));
  Assert.AreEqual('no-with', mRows[0].Id);
end;

procedure TAtlasRuleTableTests.OptionTurnsTextIntoObjectAndBack;
var
  mRules: string;
begin
  mRules := TAtlasRuleTable.WithOption('{"magic-number": "warning"}', 'magic-number', 'ignore', '["0"]');
  Assert.AreEqual('{"magic-number":{"severity":"warning","ignore":["0"]}}', mRules);
  mRules := TAtlasRuleTable.WithOption(mRules, 'magic-number', 'ignore', '');
  Assert.AreEqual('{"magic-number":"warning"}', mRules);
  mRules := TAtlasRuleTable.WithOption('', 'metric-method-length', 'max', '80');
  Assert.AreEqual('{"metric-method-length":{"max":80}}', mRules);
  mRules := TAtlasRuleTable.WithOption(mRules, 'metric-method-length', 'max', '');
  Assert.AreEqual('', mRules);
  // Kein gültiges JSON: nichts ändert sich.
  mRules := TAtlasRuleTable.WithOption('{"a": "off"}', 'a', 'max', '{kaputt');
  Assert.AreEqual('{"a":"off"}', mRules);
end;

procedure TAtlasRuleTableTests.ExcludeIsWrittenAndRemoved;
var
  mRules: string;
begin
  mRules := TAtlasRuleTable.WithExclude('{"no-with": "error"}', 'no-with', ['Legacy/**', ' ', 'Alt.Unit ']);
  Assert.AreEqual('{"no-with":{"severity":"error","exclude":["Legacy/**","Alt.Unit"]}}', mRules);
  mRules := TAtlasRuleTable.WithExclude(mRules, 'no-with', nil);
  Assert.AreEqual('{"no-with":"error"}', mRules);
end;

procedure TAtlasRuleTableTests.GroupSwitchWritesAndRemovesKey;
var
  mRules: string;
begin
  Assert.AreEqual('group:style', TAtlasRuleTable.GroupKey('style'));
  mRules := TAtlasRuleTable.WithGroup('{"no-with": "error"}', 'style', False);
  Assert.AreEqual('{"no-with":"error","group:style":"off"}', mRules);
  Assert.IsTrue(TAtlasRuleTable.GroupOff(mRules, 'style'));
  Assert.IsFalse(TAtlasRuleTable.GroupOff(mRules, 'exceptions'));
  mRules := TAtlasRuleTable.WithGroup(mRules, 'style', True);
  Assert.AreEqual('{"no-with":"error"}', mRules);
  Assert.IsFalse(TAtlasRuleTable.GroupOff('', 'style'));
end;

procedure TAtlasRuleTableTests.GroupOptionKeepsSwitchAndBack;
var
  mRules: string;
begin
  // #1024: "typeLevel" der Gruppe „Compiler vorab“ macht den Schlüssel zum Objekt; der Hauptschalter bleibt.
  mRules := TAtlasRuleTable.WithGroupOption('{"group:compiler": "off"}', 'compiler', 'typeLevel', 'off');
  Assert.AreEqual('{"group:compiler":{"severity":"off","typeLevel":"off"}}', mRules);
  Assert.IsTrue(TAtlasRuleTable.GroupOff(mRules, 'compiler'));
  Assert.AreEqual('off', TAtlasRuleTable.GroupOption(mRules, 'compiler', 'typeLevel'));
  mRules := TAtlasRuleTable.WithGroup(mRules, 'compiler', True);
  Assert.AreEqual('{"group:compiler":{"typeLevel":"off"}}', mRules);
  Assert.IsFalse(TAtlasRuleTable.GroupOff(mRules, 'compiler'));
  mRules := TAtlasRuleTable.WithGroup(mRules, 'compiler', False);
  mRules := TAtlasRuleTable.WithGroupOption(mRules, 'compiler', 'typeLevel', '');
  Assert.AreEqual('{"group:compiler":"off"}', mRules);
  Assert.AreEqual('', TAtlasRuleTable.GroupOption(mRules, 'compiler', 'typeLevel'));
  Assert.AreEqual('off', TAtlasRuleTable.GroupOption(mRules, 'compiler', 'severity'));
  mRules := TAtlasRuleTable.WithGroup(mRules, 'compiler', True);
  Assert.AreEqual('', mRules);
  Assert.AreEqual(1, Integer(Length(TAtlasRuleTable.Rows(nil,
    '{"group:compiler": {"typeLevel": "off"}, "no-with": "error"}'))));
end;

procedure TAtlasRuleTableTests.FilterByGroupAndText;
var
  mValue: TJSONValue;
  mRows: TArray<TAtlasRuleRow>;
  mHits: TArray<Integer>;
  mGroups: TArray<string>;
begin
  mValue := Catalog;
  try
    mRows := TAtlasRuleTable.Rows(mValue, '');
    mGroups := TAtlasRuleTable.Groups(mRows);
    Assert.AreEqual(2, Integer(Length(mGroups)));
    Assert.AreEqual('style', mGroups[0]);
    Assert.AreEqual('exceptions', mGroups[1]);
    Assert.AreEqual(2, Integer(Length(TAtlasRuleTable.Filter(mRows, '', ''))));
    mHits := TAtlasRuleTable.Filter(mRows, 'exceptions', '');
    Assert.AreEqual(1, Integer(Length(mHits)));
    Assert.AreEqual(1, mHits[0]);
    // Suche in Kennung, Name und Beschreibung.
    mHits := TAtlasRuleTable.Filter(mRows, '', 'VERSCHLUCKT');
    Assert.AreEqual(1, Integer(Length(mHits)));
    Assert.AreEqual(1, mHits[0]);
    mHits := TAtlasRuleTable.Filter(mRows, '', 'magic');
    Assert.AreEqual(1, Integer(Length(mHits)));
    Assert.AreEqual(0, mHits[0]);
    Assert.AreEqual(0, Integer(Length(TAtlasRuleTable.Filter(mRows, 'style', 'except'))));
  finally
    mValue.Free;
  end;
end;

procedure TAtlasRuleTableTests.EffectiveSeverityFallsBackToGlobalAndDefault;
var
  mRow: TAtlasRuleRow;
begin
  mRow := Default(TAtlasRuleRow);
  mRow.DefaultSeverity := 'warning';
  Assert.AreEqual('warning', mRow.Effective);
  mRow.GlobalSeverity := 'off';
  Assert.AreEqual('off', mRow.Effective);
  Assert.IsFalse(mRow.Enabled);
  mRow.Severity := 'error';
  Assert.AreEqual('error', mRow.Effective);
  Assert.IsTrue(mRow.Enabled);
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
  mJson: string;
begin
  Assert.IsTrue(TAtlasRuleTable.OptionJson('integer', ' 80 ', mJson));
  Assert.AreEqual('80', mJson);
  Assert.IsFalse(TAtlasRuleTable.OptionJson('integer', 'acht', mJson));
  Assert.IsTrue(TAtlasRuleTable.OptionJson('boolean', 'True', mJson));
  Assert.AreEqual('true', mJson);
  Assert.IsFalse(TAtlasRuleTable.OptionJson('boolean', 'ja', mJson));
  Assert.IsTrue(TAtlasRuleTable.OptionJson('string', 'a"b', mJson));
  Assert.AreEqual('"a\"b"', mJson);
  Assert.IsTrue(TAtlasRuleTable.OptionJson('string-list', '0; 1;; 2 ', mJson));
  Assert.AreEqual('["0","1","2"]', mJson);
  Assert.IsTrue(TAtlasRuleTable.OptionJson('number-list', '0; -1; 2.5', mJson));
  Assert.AreEqual('[0,-1,2.5]', mJson);
  Assert.IsFalse(TAtlasRuleTable.OptionJson('number-list', '1; zwei', mJson));
  Assert.IsTrue(TAtlasRuleTable.OptionJson('json', '{"a": 1}', mJson));
  Assert.AreEqual('{"a":1}', mJson);
  Assert.IsFalse(TAtlasRuleTable.OptionJson('json', '{a', mJson));
  // Leeres Feld: Vorgabe.
  Assert.IsTrue(TAtlasRuleTable.OptionJson('integer', '  ', mJson));
  Assert.AreEqual('', mJson);
end;

procedure TAtlasRuleTableTests.ListTextRoundTrips;
var
  mItems: TArray<string>;
begin
  mItems := TAtlasRuleTable.ParseList(' Tests\*.pas ;; Vendor.* ');
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('Tests\*.pas', mItems[0]);
  Assert.AreEqual('Vendor.*', mItems[1]);
  Assert.AreEqual('Tests\*.pas; Vendor.*', TAtlasRuleTable.ListText(mItems));
  Assert.AreEqual(0, Integer(Length(TAtlasRuleTable.ParseList(''))));
  mItems := nil;
end;

procedure TAtlasRuleTableTests.SearchFindsCategory;
var
  mValue: TJSONValue;
  mRows: TArray<TAtlasRuleRow>;
  mFound: TArray<Integer>;
begin
  mValue := Catalog;
  try
    mRows := TAtlasRuleTable.Rows(mValue, '');
    mFound := TAtlasRuleTable.Filter(mRows, '', 'CODE-SMELL');
    Assert.AreEqual(1, Integer(Length(mFound)));
    Assert.AreEqual('magic-number', mRows[mFound[0]].Id);
    Assert.AreEqual(14, Integer(Length(TAtlasRuleTable.cGroupIds)));
    Assert.AreEqual('find-bugs', TAtlasRuleTable.cGroupIds[0]);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasRuleTableTests.ChangesListOnlyChangedRules;
var
  mChanges: TArray<TPair<string, string>>;
begin
  mChanges := TAtlasRuleTable.Changes('{"a": "off", "b": {"severity": "error"}, "c": "hint"}',
    '{"a": "off", "b": {"severity": "warning"}, "group:style": "off"}');
  Assert.AreEqual(3, Integer(Length(mChanges)));
  Assert.AreEqual('rules.b', mChanges[0].Key);
  Assert.AreEqual('{"severity":"warning"}', mChanges[0].Value);
  Assert.AreEqual('rules.group:style', mChanges[1].Key);
  Assert.AreEqual('"off"', mChanges[1].Value);
  Assert.AreEqual('rules.c', mChanges[2].Key);
  Assert.AreEqual('', mChanges[2].Value);
  Assert.AreEqual(0, Integer(Length(TAtlasRuleTable.Changes('', ''))));
  mChanges := nil;
end;

procedure TAtlasRuleTableTests.OverridingRuleOnlyWhenEnabled;
const
  cText = '{"rules": [' +
    '{"id": "redundant-begin-end", "category": "code-smell", "severity": "hint", "group": "style",' +
    ' "overriddenBy": ["missing-begin-end"]},' +
    '{"id": "missing-begin-end", "category": "code-smell", "severity": "hint", "group": "style"}]}';
var
  mValue: TJSONValue;
  mRows: TArray<TAtlasRuleRow>;
begin
  mValue := TJSONObject.ParseJSONValue(cText);
  try
    mRows := TAtlasRuleTable.Rows(mValue, '');
    Assert.AreEqual('missing-begin-end', string.Join(',', mRows[0].OverriddenBy));
    Assert.AreEqual('missing-begin-end', TAtlasRuleTable.OverridingRule(mRows, mRows[0]));
    Assert.AreEqual('', TAtlasRuleTable.OverridingRule(mRows, mRows[1]));
    mRows := TAtlasRuleTable.Rows(mValue, '{"missing-begin-end": "off"}');
    Assert.AreEqual('', TAtlasRuleTable.OverridingRule(mRows, mRows[0]));
  finally
    mValue.Free;
  end;
end;

procedure TAtlasRuleTableTests.ObjectListTableRoundTrips;
var
  mValue: TJSONValue;
  mRows: TArray<TAtlasRuleRow>;
  mOption: TAtlasRuleOption;
  mCells: TArray<TArray<string>>;
begin
  // Tabelle der Symbole von forbidden-symbol (#1133).
  mValue := TJSONObject.ParseJSONValue('{"rules": [{"id": "forbidden-symbol", "name": "Verboten", ' +
    '"category": "code-smell", "severity": "warning", "group": "architecture", "options": [{"name": "symbols", ' +
    '"type": "object-list", "columns": [{"name": "name"}, {"name": "kind"}, {"name": "units", "list": true}], ' +
    '"default": [], "description": "Verbote"}]}]}');
  try
    mRows := TAtlasRuleTable.Rows(mValue, '{"forbidden-symbol": {"symbols": [{"name": "System.Write*", ' +
      '"units": ["App.*", "!App.Cli"], "severity": "error"}, {"name": "TThread.Queue", "kind": "routine"}]}}');
  finally
    mValue.Free;
  end;
  mOption := mRows[0].Options[0];
  Assert.AreEqual('object-list', mOption.Kind);
  Assert.AreEqual(3, Integer(Length(mOption.Columns)));
  Assert.IsTrue(mOption.Columns[2].List);
  Assert.IsFalse(mOption.Columns[0].List);
  mCells := TAtlasRuleTable.TableCells(mOption);
  Assert.AreEqual(2, Integer(Length(mCells)));
  Assert.AreEqual('System.Write*', mCells[0][0]);
  Assert.AreEqual('', mCells[0][1]);
  Assert.AreEqual('App.*; !App.Cli', mCells[0][2]);
  Assert.AreEqual('routine', mCells[1][1]);
  // Unbekannte Schlüssel (severity) stehen in keiner Spalte und fallen beim Zurückschreiben weg.
  Assert.AreEqual('[{"name":"System.Write*","units":["App.*","!App.Cli"]},{"name":"TThread.Queue","kind":"routine"}]',
    TAtlasRuleTable.TableJson(mOption, mCells));
  // Leere Zeilen entfallen.
  Assert.AreEqual('[{"kind":"type"}]', TAtlasRuleTable.TableJson(mOption,
    [TArray<string>.Create(' ', '', ''), TArray<string>.Create('', 'type')]));
  Assert.AreEqual('[]', TAtlasRuleTable.TableJson(mOption, nil));
  mOption.ValueJson := '';
  Assert.AreEqual(0, Integer(Length(TAtlasRuleTable.TableCells(mOption))));
  mCells := nil;
  mRows := nil;
end;

procedure TAtlasRuleTableTests.RuleRowsFromCatalogAndFile;
var
  mCatalog: TJSONValue;
  mRows: TArray<TAtlasRuleRow>;
begin
  mCatalog := TJSONObject.ParseJSONValue('{"rules": [' +
    '{"id": "no-with", "name": "Kein with", "category": "code-smell", "severity": "warning"},' +
    '{"id": "empty-except", "name": "Leeres except", "category": "bug", "severity": "error"}]}');
  try
    mRows := TAtlasRuleTable.Rows(mCatalog, '{"no-with": "off", "own-rule": {"severity": "hint", "x": 1}}');
    Assert.AreEqual(3, Integer(Length(mRows)));
    Assert.AreEqual('no-with', mRows[0].Id);
    Assert.AreEqual('off', mRows[0].Severity);
    Assert.AreEqual('warning', mRows[0].DefaultSeverity);
    Assert.IsTrue(mRows[0].Known);
    Assert.AreEqual('', mRows[1].Severity);
    Assert.AreEqual('own-rule', mRows[2].Id);
    Assert.IsFalse(mRows[2].Known);
    Assert.IsTrue(mRows[2].HasOptions);
    Assert.AreEqual('hint', mRows[2].Severity);
    // Ohne Server: nur die Regeln aus der Datei.
    Assert.AreEqual(2, Integer(Length(TAtlasRuleTable.Rows(nil, '{"a": "off", "b": "error"}'))));
    // Im Projekt: globaler Wert je Regel, das Projekt übersteuert ihn.
    mRows := TAtlasRuleTable.Rows(nil, '{"a": "off"}', '{"a": "hint", "b": "error"}');
    Assert.AreEqual('off', mRows[0].Severity);
    Assert.AreEqual('hint', mRows[0].GlobalSeverity);
  finally
    mCatalog.Free;
  end;
end;

procedure TAtlasRuleTableTests.RuleSeverityKeepsOptions;
var
  mRules: string;
begin
  mRules := TAtlasRuleTable.WithSeverity('{"magic-number": {"severity": "hint", "ignore": [0]}}', 'magic-number',
    'error');
  Assert.IsTrue(Pos('"ignore":[0]', mRules) > 0);
  Assert.IsTrue(Pos('"severity":"error"', mRules) > 0);
  mRules := TAtlasRuleTable.WithSeverity('{"no-with": "error"}', 'no-with', '');
  Assert.AreEqual('', mRules);
  mRules := TAtlasRuleTable.WithSeverity('', 'no-with', 'off');
  Assert.AreEqual('{"no-with":"off"}', mRules);
end;

procedure TAtlasRuleTableTests.SeverityChangeTouchesOnlyThatRule;
var
  mPath, mJson: string;
begin
  // Hat die Regel Optionen, ändert sich nur "severity".
  TAtlasRuleTable.SeverityChange('{"magic-number": {"severity": "hint"}}', 'magic-number', 'off', mPath, mJson);
  Assert.AreEqual('rules.magic-number.severity', mPath);
  Assert.AreEqual('"off"', mJson);
  TAtlasRuleTable.SeverityChange('{"no-with": "error"}', 'no-with', '', mPath, mJson);
  Assert.AreEqual('rules.no-with', mPath);
  Assert.AreEqual('', mJson);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasRuleTableTests);

end.
