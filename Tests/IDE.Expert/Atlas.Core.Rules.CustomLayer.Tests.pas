unit Atlas.Core.Rules.CustomLayer.Tests;

// Tests des Assistenten „Eigene Prüfregel“ (#1821): Namensraum der Unit, neue
// Schicht hinter vorhandenen, Schweregrad als Text bleibt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Rules')]
  TAtlasCustomLayerTests = class
  public
    [Test]
    procedure LayerFromNamespace;
    [Test]
    procedure NewLayerWithoutRules;
    [Test]
    procedure NewLayerKeepsExisting;
    [Test]
    procedure SeverityTextBecomesObject;
  end;

implementation

uses
  Atlas.Core.Rules.CustomLayer;

procedure TAtlasCustomLayerTests.LayerFromNamespace;
begin
  Assert.AreEqual('Kunden.Logik.*', TAtlasCustomLayer.LayerFrom('Kunden.Logik.Engine'));
  Assert.AreEqual('Rechner', TAtlasCustomLayer.LayerFrom(' Rechner '));
  Assert.AreEqual('*', TAtlasCustomLayer.LayerFrom(''));
end;

procedure TAtlasCustomLayerTests.NewLayerWithoutRules;
var
  mPath, mJson: string;
begin
  Assert.AreEqual(0, TAtlasCustomLayer.NewLayer('', 'Kunden.*', mPath, mJson));
  Assert.AreEqual('rules.forbidden-uses', mPath);
  Assert.AreEqual('{"layers":[{"from":"Kunden.*","deny":[],"allow":[]}]}', mJson);
end;

procedure TAtlasCustomLayerTests.NewLayerKeepsExisting;
var
  mPath, mJson: string;
begin
  Assert.AreEqual(1, TAtlasCustomLayer.NewLayer('{"magic-number": "off", "forbidden-uses": {"severity": "warning", ' +
    '"layers": [{"from": "*.Core.*", "deny": ["Vcl.*"]}]}}', 'Kunden.*', mPath, mJson));
  Assert.AreEqual('{"severity":"warning","layers":[{"from":"*.Core.*","deny":["Vcl.*"]},' +
    '{"from":"Kunden.*","deny":[],"allow":[]}]}', mJson);
end;

procedure TAtlasCustomLayerTests.SeverityTextBecomesObject;
var
  mPath, mJson: string;
begin
  TAtlasCustomLayer.NewLayer('{"forbidden-uses": "error"}', 'A.*', mPath, mJson);
  Assert.AreEqual('{"severity":"error","layers":[{"from":"A.*","deny":[],"allow":[]}]}', mJson);
  TAtlasCustomLayer.NewLayer('{"forbidden-uses": {"layers": 3}}', 'A.*', mPath, mJson);
  Assert.AreEqual('{"layers":[{"from":"A.*","deny":[],"allow":[]}]}', mJson, 'ungültige Liste ersetzt');
  TAtlasCustomLayer.NewLayer('kaputt', 'A.*', mPath, mJson);
  Assert.AreEqual('{"layers":[{"from":"A.*","deny":[],"allow":[]}]}', mJson);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCustomLayerTests);

end.
