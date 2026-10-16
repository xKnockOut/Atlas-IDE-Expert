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
    /// <summary>Zeilenkommentar endet auch an einem alleinstehenden CR, wie beim Server (ADR 0012).</summary>
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
  LB = #13#10;
  Sample =
    '{' + LB +
    '  "$schema": "./atlas.schema.json",' + LB +
    '  // Sprache der Meldungen' + LB +
    '  "language": "de",' + LB +
    '  "compiler": { "onSave": true }, /* bleibt */' + LB +
    '  "custom": 1' + LB +
    '}' + LB;

procedure TAtlasJsonTextTests.ReplacesValueAndKeepsComments;
begin
  Assert.AreEqual(Sample.Replace('"de"', '"en"'), TAtlasJsonText.SetValue(Sample, 'language', '"en"'));
  Assert.AreEqual(Sample.Replace('"onSave": true', '"onSave": false'),
    TAtlasJsonText.SetValue(Sample, 'compiler.onSave', 'false'));
end;

procedure TAtlasJsonTextTests.AddsMissingKeyWithSiblingIndent;
begin
  Assert.AreEqual(Sample.Replace('"custom": 1', '"custom": 1,' + LB + '  "logLevel": "debug"'),
    TAtlasJsonText.SetValue(Sample, 'logLevel', '"debug"'));
end;

procedure TAtlasJsonTextTests.CreatesNestedObjects;
begin
  Assert.AreEqual(Sample.Replace('"custom": 1', '"custom": 1,' + LB + '  "format": {' + LB + '    "indentSize": 4' +
    LB + '  }'), TAtlasJsonText.SetValue(Sample, 'format.indentSize', '4'));
  // Im vorhandenen Objekt auf einer Zeile: dahinter anhängen.
  Assert.Contains(TAtlasJsonText.SetValue(Sample, 'compiler.extra', '1'), '"onSave": true,');
end;

procedure TAtlasJsonTextTests.FillsEmptyAndMissingFile;
var
  Root: TJSONObject;
begin
  Assert.AreEqual('{' + LB + '  "language": "en"' + LB + '}' + LB, TAtlasJsonText.SetValue('{' + LB + '}' + LB,
    'language', '"en"'));
  Root := TAtlasJsonText.Parse(TAtlasJsonText.SetValue('', 'format.useTabs', 'true'));
  try
    Assert.AreEqual('true', TAtlasJsonText.ValueAt(Root, 'format.useTabs'));
  finally
    Root.Free;
  end;
end;

procedure TAtlasJsonTextTests.AddsAfterTrailingComma;
begin
  Assert.AreEqual('{' + LB + '  "a": 1,' + LB + '  "b": 2' + LB + '}',
    TAtlasJsonText.SetValue('{' + LB + '  "a": 1,' + LB + '}', 'b', '2'));
end;

procedure TAtlasJsonTextTests.RemovesKeyWithItsComma;
begin
  Assert.AreEqual(Sample.Replace('}, /* bleibt */' + LB + '  "custom": 1', '} /* bleibt */'),
    TAtlasJsonText.Remove(Sample, 'custom'));
  Assert.AreEqual(Sample.Replace('{ "onSave": true }', '{}'), TAtlasJsonText.Remove(Sample, 'compiler.onSave'));
  Assert.AreEqual(Sample, TAtlasJsonText.Remove(Sample, 'fehlt.ganz'));
end;

procedure TAtlasJsonTextTests.RemovesFirstAndOnlyKey;
begin
  Assert.AreEqual('{ "b": 2 }', TAtlasJsonText.Remove('{ "a": 1, "b": 2 }', 'a'));
  Assert.AreEqual('{}', TAtlasJsonText.Remove('{ "a": 1 }', 'a'));
end;

procedure TAtlasJsonTextTests.ReadsValuesThroughComments;
var
  Root: TJSONObject;
begin
  Root := TAtlasJsonText.Parse(Sample + '// Ende');
  try
    Assert.IsNotNull(Root);
    Assert.AreEqual('"de"', TAtlasJsonText.ValueAt(Root, 'language'));
    Assert.AreEqual('true', TAtlasJsonText.ValueAt(Root, 'compiler.onSave'));
    Assert.AreEqual('', TAtlasJsonText.ValueAt(Root, 'format.indentSize'));
  finally
    Root.Free;
  end;
  Assert.IsNull(TAtlasJsonText.Parse('{ "a": '));
  Root := TAtlasJsonText.Parse('{ "a": [1, 2,], }');
  try
    Assert.IsNotNull(Root, 'Schlusskommas wie in VS Code erlaubt');
  finally
    Root.Free;
  end;
end;

procedure TAtlasJsonTextTests.SchemaListsSimpleFieldsAndComplexOnes;
var
  Fields: TArray<TAtlasSettingField>;
  Field: TAtlasSettingField;
  Found: TDictionary<string, TAtlasSettingField>;
begin
  Fields := TAtlasSettingsSchema.Fields(AtlasSchemaJson);
  Found := TDictionary<string, TAtlasSettingField>.Create;
  try
    for Field in Fields do
      Found.AddOrSetValue(Field.Path, Field);
    Assert.IsFalse(Found.ContainsKey('$schema'));
    Assert.IsTrue(Found['compiler.onSave'].Kind = TAtlasSettingKind.Boolean_);
    Assert.AreEqual('Compiler', Found['compiler.onSave'].Page);
    Assert.IsTrue(Found['language'].Kind = TAtlasSettingKind.Choice);
    Assert.AreEqual('"de"', Found['language'].DefaultJson);
    Assert.IsTrue(Found['format.indentSize'].Kind = TAtlasSettingKind.Integer_);
    Assert.IsTrue(Found['exclude'].Kind = TAtlasSettingKind.List);
    Assert.IsTrue(Found['rules'].Kind = TAtlasSettingKind.Complex);
    Assert.IsTrue(Found['overrides'].Kind = TAtlasSettingKind.Complex);
    Assert.IsTrue(Found['sortUses'].Kind = TAtlasSettingKind.Choice);
    Assert.IsTrue(Found['profile'].Kind = TAtlasSettingKind.Text);
    Assert.AreEqual('Allgemein', TAtlasSettingsSchema.Pages(Fields)[0]);
    // D-08: Schalter für die globale Datei im MCP-Modus, als Kontrollkästchen der Projekt-Einstellungen.
    Assert.IsTrue(Found['mcp.globalSettings'].Kind = TAtlasSettingKind.Boolean_);
    Assert.AreEqual('MCP', Found['mcp.globalSettings'].Page);
    Assert.IsFalse(Found['mcp.globalSettings'].Global, 'gehört nach atlas.json');
    Assert.AreEqual('true', Found['mcp.globalSettings'].DefaultJson);
    Assert.IsTrue(Found['mcp.disabledTools'].Global);
  finally
    Found.Free;
  end;
end;

procedure TAtlasJsonTextTests.FieldAcceptsOnlyMatchingValues;
var
  Field: TAtlasSettingField;
begin
  Field := Default(TAtlasSettingField);
  Field.Kind := TAtlasSettingKind.Text;
  Assert.IsTrue(Field.Accepts('"standard"'));
  Assert.IsFalse(Field.Accepts('{"editor": "x"}'), 'Profil als Objekt bleibt unangetastet');
  Assert.IsTrue(Field.Accepts(''));
  Field.Kind := TAtlasSettingKind.List;
  Assert.IsTrue(Field.Accepts('["a","b"]'));
  Assert.IsFalse(Field.Accepts('[1]'));
  Assert.AreEqual('de', TAtlasSettingsSchema.Display('"de"'));
end;

procedure TAtlasJsonTextTests.LineCommentEndsAtCr;
var
  Root: TJSONObject;
begin
  Root := TAtlasJsonText.Parse('{ // Kommentar'#13'"a": 1 }');
  try
    Assert.IsNotNull(Root);
    Assert.AreEqual('1', TAtlasJsonText.ValueAt(Root, 'a'));
  finally
    Root.Free;
  end;
  Assert.AreEqual('{ "a": 2 }', TAtlasJsonText.SetValue('{ "a": 1 }', 'a', '2'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasJsonTextTests);

end.
