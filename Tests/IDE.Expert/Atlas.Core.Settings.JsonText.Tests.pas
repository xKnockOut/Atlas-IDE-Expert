unit Atlas.Core.Settings.JsonText.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>atlas.json gezielt ändern, Einstellungen aus dem Schema (#227).</summary>
  [TestFixture]
  TAtlasJsonTextTests = class
  public
    [Test]
    procedure ReplacesValueAndKeepsComments;
    [Test]
    procedure AddsMissingKeyWithSiblingIndent;
    [Test]
    procedure CreatesNestedObjects;
    [Test]
    procedure FillsEmptyAndMissingFile;
    [Test]
    procedure AddsAfterTrailingComma;
    [Test]
    procedure RemovesKeyWithItsComma;
    [Test]
    procedure RemovesFirstAndOnlyKey;
    [Test]
    procedure ReadsValuesThroughComments;
    [Test]
    procedure SchemaListsSimpleFieldsAndComplexOnes;
    [Test]
    procedure FieldAcceptsOnlyMatchingValues;
    /// <summary>Zeilenkommentar endet auch an einem alleinstehenden CR, wie beim Server.</summary>
    [Test]
    procedure LineCommentEndsAtCr;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.SchemaData;

const
  cLB = #13#10;
  cSample =
    '{' + cLB +
    '  "$schema": "./atlas.schema.json",' + cLB +
    '  // Sprache der Meldungen' + cLB +
    '  "language": "de",' + cLB +
    '  "compiler": { "onSave": true }, /* bleibt */' + cLB +
    '  "custom": 1' + cLB +
    '}' + cLB;

procedure TAtlasJsonTextTests.ReplacesValueAndKeepsComments;
begin
  Assert.AreEqual(cSample.Replace('"de"', '"en"'), TAtlasJsonText.SetValue(cSample, 'language', '"en"'));
  Assert.AreEqual(cSample.Replace('"onSave": true', '"onSave": false'),
    TAtlasJsonText.SetValue(cSample, 'compiler.onSave', 'false'));
end;

procedure TAtlasJsonTextTests.AddsMissingKeyWithSiblingIndent;
begin
  Assert.AreEqual(cSample.Replace('"custom": 1', '"custom": 1,' + cLB + '  "logLevel": "debug"'),
    TAtlasJsonText.SetValue(cSample, 'logLevel', '"debug"'));
end;

procedure TAtlasJsonTextTests.CreatesNestedObjects;
begin
  Assert.AreEqual(cSample.Replace('"custom": 1', '"custom": 1,' + cLB + '  "format": {' + cLB + '    "indentSize": 4' +
    cLB + '  }'), TAtlasJsonText.SetValue(cSample, 'format.indentSize', '4'));
  // Im vorhandenen Objekt auf einer Zeile: dahinter anhängen.
  Assert.Contains(TAtlasJsonText.SetValue(cSample, 'compiler.extra', '1'), '"onSave": true,');
end;

procedure TAtlasJsonTextTests.FillsEmptyAndMissingFile;
var
  mRoot: TJSONObject;
begin
  Assert.AreEqual('{' + cLB + '  "language": "en"' + cLB + '}' + cLB, TAtlasJsonText.SetValue('{' + cLB + '}' + cLB,
    'language', '"en"'));
  mRoot := TAtlasJsonText.Parse(TAtlasJsonText.SetValue('', 'format.useTabs', 'true'));
  try
    Assert.AreEqual('true', TAtlasJsonText.ValueAt(mRoot, 'format.useTabs'));
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasJsonTextTests.AddsAfterTrailingComma;
begin
  Assert.AreEqual('{' + cLB + '  "a": 1,' + cLB + '  "b": 2' + cLB + '}',
    TAtlasJsonText.SetValue('{' + cLB + '  "a": 1,' + cLB + '}', 'b', '2'));
end;

procedure TAtlasJsonTextTests.RemovesKeyWithItsComma;
begin
  Assert.AreEqual(cSample.Replace('}, /* bleibt */' + cLB + '  "custom": 1', '} /* bleibt */'),
    TAtlasJsonText.Remove(cSample, 'custom'));
  Assert.AreEqual(cSample.Replace('{ "onSave": true }', '{}'), TAtlasJsonText.Remove(cSample, 'compiler.onSave'));
  Assert.AreEqual(cSample, TAtlasJsonText.Remove(cSample, 'fehlt.ganz'));
end;

procedure TAtlasJsonTextTests.RemovesFirstAndOnlyKey;
begin
  Assert.AreEqual('{ "b": 2 }', TAtlasJsonText.Remove('{ "a": 1, "b": 2 }', 'a'));
  Assert.AreEqual('{}', TAtlasJsonText.Remove('{ "a": 1 }', 'a'));
end;

procedure TAtlasJsonTextTests.ReadsValuesThroughComments;
var
  mRoot: TJSONObject;
begin
  mRoot := TAtlasJsonText.Parse(cSample + '// Ende');
  try
    Assert.IsNotNull(mRoot);
    Assert.AreEqual('"de"', TAtlasJsonText.ValueAt(mRoot, 'language'));
    Assert.AreEqual('true', TAtlasJsonText.ValueAt(mRoot, 'compiler.onSave'));
    Assert.AreEqual('', TAtlasJsonText.ValueAt(mRoot, 'format.indentSize'));
  finally
    mRoot.Free;
  end;
  Assert.IsNull(TAtlasJsonText.Parse('{ "a": '));
  mRoot := TAtlasJsonText.Parse('{ "a": [1, 2,], }');
  try
    Assert.IsNotNull(mRoot, 'Schlusskommas wie in VS Code erlaubt');
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasJsonTextTests.SchemaListsSimpleFieldsAndComplexOnes;
var
  mFields: TArray<TAtlasSettingField>;
  mField: TAtlasSettingField;
  mFound: TDictionary<string, TAtlasSettingField>;
  mKey: string;
begin
  mFields := TAtlasSettingsSchema.Fields(AtlasSchemaJson);
  mFound := TDictionary<string, TAtlasSettingField>.Create;
  try
    for mField in mFields do
    begin
      mFound.AddOrSetValue(mField.Path, mField);
    end;
    for mKey in TArray<string>.Create('compiler.onSave', 'language', 'format.indentSize', 'exclude', 'rules', 'overrides',
      'sortUses', 'profile', 'mcp.globalSettings', 'mcp.disabledTools') do
    begin
      Assert.IsTrue(mFound.ContainsKey(mKey), Format('%s fehlt (%d Felder)', [mKey, Length(mFields)]));
    end;
    Assert.IsFalse(mFound.ContainsKey('$schema'));
    Assert.AreEqual<TAtlasSettingKind>(TAtlasSettingKind.Boolean_, mFound['compiler.onSave'].Kind);
    Assert.AreEqual('Compiler', mFound['compiler.onSave'].Page);
    Assert.AreEqual<TAtlasSettingKind>(TAtlasSettingKind.Choice, mFound['language'].Kind);
    // Vorgabe "" = wie der Client bzw. die IDE (#1458).
    Assert.AreEqual('""', mFound['language'].DefaultJson);
    Assert.AreEqual<TAtlasSettingKind>(TAtlasSettingKind.Integer_, mFound['format.indentSize'].Kind);
    Assert.AreEqual<TAtlasSettingKind>(TAtlasSettingKind.List, mFound['exclude'].Kind);
    Assert.AreEqual<TAtlasSettingKind>(TAtlasSettingKind.Complex, mFound['rules'].Kind);
    Assert.AreEqual<TAtlasSettingKind>(TAtlasSettingKind.Complex, mFound['overrides'].Kind);
    Assert.AreEqual<TAtlasSettingKind>(TAtlasSettingKind.Choice, mFound['sortUses'].Kind);
    Assert.AreEqual<TAtlasSettingKind>(TAtlasSettingKind.Text, mFound['profile'].Kind);
    Assert.AreEqual('Allgemein', TAtlasSettingsSchema.Pages(mFields)[0]);
    // Schalter für die globale Datei im MCP-Modus, als Kontrollkästchen der Projekt-Einstellungen.
    Assert.AreEqual<TAtlasSettingKind>(TAtlasSettingKind.Boolean_, mFound['mcp.globalSettings'].Kind);
    Assert.AreEqual('MCP', mFound['mcp.globalSettings'].Page);
    Assert.IsFalse(mFound['mcp.globalSettings'].Global, 'gehört nach atlas.json');
    Assert.AreEqual('true', mFound['mcp.globalSettings'].DefaultJson);
    Assert.IsTrue(mFound['mcp.disabledTools'].Global);
  finally
    mFound.Free;
  end;
end;

procedure TAtlasJsonTextTests.FieldAcceptsOnlyMatchingValues;
var
  mField: TAtlasSettingField;
begin
  mField := Default(TAtlasSettingField);
  mField.Kind := TAtlasSettingKind.Text;
  Assert.IsTrue(mField.Accepts('"standard"'));
  Assert.IsFalse(mField.Accepts('{"editor": "x"}'), 'Profil als Objekt bleibt unangetastet');
  Assert.IsTrue(mField.Accepts(''));
  mField.Kind := TAtlasSettingKind.List;
  Assert.IsTrue(mField.Accepts('["a","b"]'));
  Assert.IsFalse(mField.Accepts('[1]'));
  Assert.AreEqual('de', TAtlasSettingsSchema.Display('"de"'));
end;

procedure TAtlasJsonTextTests.LineCommentEndsAtCr;
var
  mRoot: TJSONObject;
begin
  mRoot := TAtlasJsonText.Parse('{ // Kommentar'#13'"a": 1 }');
  try
    Assert.IsNotNull(mRoot);
    Assert.AreEqual('1', TAtlasJsonText.ValueAt(mRoot, 'a'));
  finally
    mRoot.Free;
  end;
  Assert.AreEqual('{ "a": 2 }', TAtlasJsonText.SetValue('{ "a": 1 }', 'a', '2'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasJsonTextTests);

end.
