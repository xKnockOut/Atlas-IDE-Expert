unit Atlas.Core.Tracker.Internals.FormYaml.Tests;

// YAML-Leser der Issue-Formulare (#2137): Zuordnungen und Listen nach
// Einrückung, „- schlüssel: wert“, Listen auf der Einrückung ihres Schlüssels,
// Werte mit und ohne Anführungszeichen, Blöcke | und >, Folgen und
// Abbildungen in Klammern, Wahrheitswerte und null; nicht Unterstütztes
// (Anker, Verweise, Typen, mehrere Dokumente, Tabulatoren) gibt nil.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasFormYamlTests = class
  public
    [Test]
    procedure ReadsMapsAndLists;
    [Test]
    procedure ListAtIndentOfItsKey;
    [Test]
    procedure QuotedValuesAndComments;
    [Test]
    procedure LiteralAndFoldedBlocks;
    [Test]
    procedure FlowSequencesAndMaps;
    [Test]
    procedure BooleansAndNull;
    [Test]
    procedure RejectsUnsupportedConstructs;
    [Test]
    procedure ReadsFormOfAtlas;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Tracker.Internals.FormYaml;

function Lines(const ALines: array of string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    Result := Result + ALines[mIndex] + #10;
  end;
end;

function Obj(AValue: TJSONValue): TJSONObject;
begin
  Assert.IsTrue(AValue is TJSONObject, 'Abbildung erwartet');
  Result := TJSONObject(AValue);
end;

function Arr(AValue: TJSONValue): TJSONArray;
begin
  Assert.IsTrue(AValue is TJSONArray, 'Folge erwartet');
  Result := TJSONArray(AValue);
end;

/// <summary>Wahrheitswert AExpected (TJSONBool, nicht TJSONTrue/TJSONFalse).</summary>
function IsFlag(AValue: TJSONValue; AExpected: Boolean): Boolean;
begin
  Result := (AValue is TJSONBool) and (TJSONBool(AValue).AsBoolean = AExpected);
end;

function Str(AValue: TJSONValue): string;
begin
  Assert.IsTrue(AValue is TJSONString, 'Text erwartet');
  Result := TJSONString(AValue).Value;
end;

procedure TAtlasFormYamlTests.ReadsMapsAndLists;
var
  mRoot: TJSONValue;
  mBody: TJSONArray;
  mItem: TJSONObject;
begin
  mRoot := TAtlasFormYaml.ToJson(Lines(['name: Fehler', 'body:', '  - type: input', '    id: version',
    '    attributes:', '      label: Atlas-Version', '  - type: textarea', '    id: log']));
  try
    Assert.AreEqual('Fehler', Str(Obj(mRoot).Values['name']));
    mBody := Arr(Obj(mRoot).Values['body']);
    Assert.AreEqual(2, Integer(mBody.Count));
    mItem := Obj(mBody.Items[0]);
    Assert.AreEqual('input', Str(mItem.Values['type']));
    Assert.AreEqual('version', Str(mItem.Values['id']));
    Assert.AreEqual('Atlas-Version', Str(Obj(mItem.Values['attributes']).Values['label']));
    Assert.AreEqual('log', Str(Obj(mBody.Items[1]).Values['id']));
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasFormYamlTests.ListAtIndentOfItsKey;
var
  mRoot: TJSONValue;
  mOptions: TJSONArray;
begin
  mRoot := TAtlasFormYaml.ToJson(Lines(['options:', '- hoch', '- niedrig', 'multiple: true']));
  try
    mOptions := Arr(Obj(mRoot).Values['options']);
    Assert.AreEqual(2, Integer(mOptions.Count));
    Assert.AreEqual('niedrig', Str(mOptions.Items[1]));
    Assert.IsTrue(IsFlag(Obj(mRoot).Values['multiple'], True));
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasFormYamlTests.QuotedValuesAndComments;
var
  mRoot: TJSONValue;
begin
  mRoot := TAtlasFormYaml.ToJson(Lines(['title: "Fehler: "', 'single: ''it''''s''', 'plain: wert # Kommentar',
    'escaped: "a\nb \"c\""', 'hash: a#b']));
  try
    Assert.AreEqual('Fehler: ', Str(Obj(mRoot).Values['title']));
    Assert.AreEqual('it''s', Str(Obj(mRoot).Values['single']));
    Assert.AreEqual('wert', Str(Obj(mRoot).Values['plain']));
    Assert.AreEqual('a' + #10 + 'b "c"', Str(Obj(mRoot).Values['escaped']));
    Assert.AreEqual('a#b', Str(Obj(mRoot).Values['hash']));
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasFormYamlTests.LiteralAndFoldedBlocks;
var
  mRoot: TJSONValue;
begin
  mRoot := TAtlasFormYaml.ToJson(Lines(['literal: |', '  Zeile 1', '    eingerückt', '', '  Zeile 3',
    'folded: >', '  ein', '  Satz', 'strip: |-', '  ohne', 'next: x']));
  try
    Assert.AreEqual('Zeile 1' + #10 + '  eingerückt' + #10 + #10 + 'Zeile 3' + #10,
      Str(Obj(mRoot).Values['literal']));
    Assert.AreEqual('ein Satz' + #10, Str(Obj(mRoot).Values['folded']));
    Assert.AreEqual('ohne', Str(Obj(mRoot).Values['strip']));
    Assert.AreEqual('x', Str(Obj(mRoot).Values['next']));
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasFormYamlTests.FlowSequencesAndMaps;
var
  mRoot: TJSONValue;
  mLabels: TJSONArray;
  mMap: TJSONObject;
begin
  mRoot := TAtlasFormYaml.ToJson(Lines(['labels: ["bug", triage]', 'map: {a: 1, b: "zwei"}', 'multi: [eins,',
    '  zwei]', 'empty: []']));
  try
    mLabels := Arr(Obj(mRoot).Values['labels']);
    Assert.AreEqual(2, Integer(mLabels.Count));
    Assert.AreEqual('bug', Str(mLabels.Items[0]));
    Assert.AreEqual('triage', Str(mLabels.Items[1]));
    mMap := Obj(Obj(mRoot).Values['map']);
    Assert.AreEqual('1', Str(mMap.Values['a']), 'Zahlen bleiben Text');
    Assert.AreEqual('zwei', Str(mMap.Values['b']));
    Assert.AreEqual(2, Integer(Arr(Obj(mRoot).Values['multi']).Count));
    Assert.AreEqual(0, Integer(Arr(Obj(mRoot).Values['empty']).Count));
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasFormYamlTests.BooleansAndNull;
var
  mRoot: TJSONValue;
begin
  mRoot := TAtlasFormYaml.ToJson(Lines(['blank_issues_enabled: false', 'yes: true', 'none: null', 'tilde: ~',
    'empty:']));
  try
    Assert.IsTrue(IsFlag(Obj(mRoot).Values['blank_issues_enabled'], False));
    Assert.IsTrue(IsFlag(Obj(mRoot).Values['yes'], True));
    Assert.IsTrue(Obj(mRoot).Values['none'] is TJSONNull);
    Assert.IsTrue(Obj(mRoot).Values['tilde'] is TJSONNull);
    Assert.IsTrue(Obj(mRoot).Values['empty'] is TJSONNull);
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasFormYamlTests.RejectsUnsupportedConstructs;
begin
  Assert.IsNull(TAtlasFormYaml.ToJson(Lines(['a: &anker wert', 'b: *anker'])), 'Anker');
  Assert.IsNull(TAtlasFormYaml.ToJson(Lines(['a: !!str wert'])), 'Typ');
  Assert.IsNull(TAtlasFormYaml.ToJson(Lines(['a: 1', '---', 'b: 2'])), 'mehrere Dokumente');
  Assert.IsNull(TAtlasFormYaml.ToJson(Lines(['a:', #9 + 'b: 1'])), 'Tabulator');
  Assert.IsNull(TAtlasFormYaml.ToJson(Lines(['? a', ': b'])), 'Schlüssel mit ?');
  Assert.IsNull(TAtlasFormYaml.ToJson(Lines(['a: "offen'])), 'offenes Anführungszeichen');
end;

procedure TAtlasFormYamlTests.ReadsFormOfAtlas;
var
  mRoot: TJSONValue;
  mBody: TJSONArray;
  mAttributes: TJSONObject;
begin
  mRoot := TAtlasFormYaml.ToJson(Lines(['name: Fehler', 'title: "Fehler: "', 'labels: ["bug"]', 'body:',
    '  - type: markdown', '    attributes:', '      value: |', '        Hinweis', '        zweite Zeile',
    '  - type: dropdown', '    id: ide', '    attributes:', '      label: Delphi-Version und IDE', '      options:',
    '        - Delphi 13 (32-Bit-IDE)', '        - Delphi 13 (64-Bit-IDE)', '    validations:',
    '      required: true']));
  try
    mBody := Arr(Obj(mRoot).Values['body']);
    Assert.AreEqual('Hinweis' + #10 + 'zweite Zeile' + #10,
      Str(Obj(Obj(mBody.Items[0]).Values['attributes']).Values['value']));
    mAttributes := Obj(Obj(mBody.Items[1]).Values['attributes']);
    Assert.AreEqual('Delphi 13 (64-Bit-IDE)', Str(Arr(mAttributes.Values['options']).Items[1]));
    Assert.IsTrue(IsFlag(Obj(Obj(mBody.Items[1]).Values['validations']).Values['required'], True));
  finally
    mRoot.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasFormYamlTests);

end.
