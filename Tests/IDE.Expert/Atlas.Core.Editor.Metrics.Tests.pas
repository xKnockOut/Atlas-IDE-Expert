unit Atlas.Core.Editor.Metrics.Tests;

// Tests der Code-Metriken im Plugin (#66): Antwort des Servers lesen und
// Kennungen; #980: Operanden, lokale Variablen, Ausstiege und Vererbungstiefe
// neben den Membern. Beschriftung und Zeile wiedererkennen prüft
// Atlas.Core.Analysis.MetricsLens.Tests (Modul Analyse, #1756).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasEditorMetricsTests = class
  public
    [Test]
    procedure ReadsServerAnswer;
    [Test]
    procedure ReadsStructure;
    [Test]
    procedure InheritanceDepthBesideMembers;
    [Test]
    procedure InvalidAnswerIsOffAndEmpty;
    [Test]
    procedure MissingLimitsNeverExceed;
    [Test]
    procedure KeysOfTheServer;
    [Test]
    procedure ReportFileNames;
    [Test]
    procedure ReportMarkdownFromAnswer;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Editor.Metrics;

const
  Answer = '{"enabled": false, "limits": {"length": 60, "nesting": 4, "cyclomatic": 15, "cognitive": 15, ' +
    '"parameters": 6, "operands": 5, "locals": 12, "exits": 4}, "file": "Main.pas", "methods": [' +
    '{"name": "TFoo.Run", "line": 12, "character": 15, "values": {"length": 7, "nesting": 1, "cyclomatic": 17, ' +
    '"cognitive": 3, "parameters": 2, "operands": 6, "locals": 3, "exits": 1}, "exceeded": ["cyclomatic"]}, ' +
    '{"name": "Ohne Zeile"}, 42, ' +
    '{"name": "Help", "line": 30, "values": {"length": 2}}]}';

function Parse(const AJson: string): TAtlasFileMetrics;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasFileMetrics.FromJson(Value);
  finally
    Value.Free;
  end;
end;

{ TAtlasEditorMetricsTests }

procedure TAtlasEditorMetricsTests.ReadsServerAnswer;
var
  Metrics: TAtlasFileMetrics;
begin
  Metrics := Parse(Answer);
  Assert.IsFalse(Metrics.Enabled);
  Assert.AreEqual(15, Metrics.Limits[TAtlasMetric.Cyclomatic]);
  Assert.AreEqual(6, Metrics.Limits[TAtlasMetric.Parameters]);
  Assert.AreEqual(2, Integer(Length(Metrics.Methods)), 'ohne Zeile und Nicht-Objekte übergangen');
  Assert.AreEqual('TFoo.Run', Metrics.Methods[0].Name);
  Assert.AreEqual(11, Metrics.Methods[0].Line, 'Server zählt ab 1, Editor ab 0');
  Assert.AreEqual(17, Metrics.Methods[0].Values[TAtlasMetric.Cyclomatic]);
  Assert.AreEqual(2, Metrics.Methods[1].Values[TAtlasMetric.MethodLength]);
  Assert.AreEqual(0, Metrics.Methods[1].Values[TAtlasMetric.Nesting], 'fehlende Werte sind 0');
  Assert.AreEqual(1, Metrics.IndexAt(29));
  Assert.AreEqual(0, Metrics.IndexAt(11));
  Assert.AreEqual(-1, Metrics.IndexAt(12));
end;

procedure TAtlasEditorMetricsTests.ReadsStructure;
var
  Metrics: TAtlasFileMetrics;
begin
  Metrics := Parse('{"structure": [{"kind": "unitLength", "name": "Main", "line": 1, "value": 2140, ' +
    '"limit": 2000}, {"kind": "usesCount", "name": "Main", "line": 3, "value": 12, "limit": 30}, ' +
    '{"kind": "classSize", "name": "TfrmHaupt", "line": 8, "value": 87}, {"kind": "anders", "line": 9, ' +
    '"value": 1}, {"kind": "classSize", "name": "Ohne Zeile", "value": 1}], "methods": []}');
  Assert.AreEqual(3, Integer(Length(Metrics.Structures)), 'unbekannte Art und fehlende Zeile übergangen');
  Assert.AreEqual(0, Metrics.StructureAt(0));
  Assert.AreEqual(1, Metrics.StructureAt(2));
  Assert.AreEqual(2, Metrics.StructureAt(7));
  Assert.AreEqual(-1, Metrics.StructureAt(8));
  Assert.AreEqual('TfrmHaupt', Metrics.Structures[2].Name);
  Assert.AreEqual(MaxInt, Metrics.Structures[2].Limit, 'ohne Grenzwert nie überschritten');
  Assert.AreEqual(2140, Metrics.Structures[0].Value);
  Assert.AreEqual(2000, Metrics.Structures[0].Limit);
  Assert.AreEqual(0, Integer(Length(Parse(Answer).Structures)), 'ältere Server ohne "structure"');
end;

procedure TAtlasEditorMetricsTests.InheritanceDepthBesideMembers;
var
  Metrics: TAtlasFileMetrics;
begin
  Metrics := Parse('{"structure": [{"kind": "classSize", "name": "TfrmHaupt", "line": 8, "value": 87, ' +
    '"limit": 40}, {"kind": "inheritanceDepth", "name": "TfrmHaupt", "line": 8, "value": 3, "limit": 5}, ' +
    '{"kind": "inheritanceDepth", "name": "TDialog", "line": 20, "value": 6, "limit": 5, "atLeast": true}], ' +
    '"methods": []}');
  Assert.AreEqual(3, Integer(Length(Metrics.Structures)));
  Assert.AreEqual(2, Integer(Length(Metrics.StructuresAt(7))), 'Member und Vererbungstiefe in einer Zeile');
  Assert.IsFalse(Metrics.Structures[1].AtLeast);
  Assert.IsTrue(Metrics.Structures[2].AtLeast);
  Assert.IsTrue(Metrics.StructuresAt(7)[1].Kind = TAtlasStructureMetric.InheritanceDepth);
  Assert.AreEqual(0, Integer(Length(Metrics.StructuresAt(0))));
end;

procedure TAtlasEditorMetricsTests.InvalidAnswerIsOffAndEmpty;
var
  Metrics: TAtlasFileMetrics;
begin
  Metrics := TAtlasFileMetrics.FromJson(nil);
  Assert.IsFalse(Metrics.Enabled);
  Assert.AreEqual(0, Integer(Length(Metrics.Methods)));
  Metrics := Parse('[1, 2]');
  Assert.IsFalse(Metrics.Enabled);
  Metrics := Parse('{"methods": "keine"}');
  Assert.IsTrue(Metrics.Enabled, 'ohne "enabled" an');
  Assert.AreEqual(0, Integer(Length(Metrics.Methods)));
end;

procedure TAtlasEditorMetricsTests.MissingLimitsNeverExceed;
var
  Metrics: TAtlasFileMetrics;
begin
  Metrics := Parse('{"limits": {"nesting": 1}, "methods": [{"name": "A", "line": 1, ' +
    '"values": {"length": 900, "nesting": 2}}]}');
  Assert.AreEqual(MaxInt, Metrics.Limits[TAtlasMetric.MethodLength]);
  Assert.AreEqual(1, Metrics.Limits[TAtlasMetric.Nesting]);
  Metrics := Parse('{"methods": [{"name": "A", "line": 1, "values": {"length": 900}}]}');
  Assert.AreEqual(MaxInt, Metrics.Limits[TAtlasMetric.Nesting], 'ohne "limits" unbegrenzt');
end;

procedure TAtlasEditorMetricsTests.KeysOfTheServer;
begin
  Assert.AreEqual('exits', TAtlasMetricKeys.Key(TAtlasMetric.Exits));
  Assert.AreEqual('cognitive', TAtlasMetricKeys.Key(TAtlasMetric.Cognitive));
  Assert.AreEqual('parameters', TAtlasMetricKeys.Key(TAtlasMetric.Parameters));
  Assert.AreEqual('usesCount', TAtlasMetricKeys.StructureKey(TAtlasStructureMetric.UsesCount));
  Assert.AreEqual('inheritanceDepth', TAtlasMetricKeys.StructureKey(TAtlasStructureMetric.InheritanceDepth));
end;

procedure TAtlasEditorMetricsTests.ReportFileNames;
begin
  Assert.AreEqual('C:\Daten\Atlas\Berichte', TAtlasMetricsReportFile.Folder('C:\Daten\Atlas'));
  Assert.AreEqual('C:\Daten\Atlas\Berichte', TAtlasMetricsReportFile.Folder('C:\Daten\Atlas\'));
  Assert.AreEqual('C:\B\Metriken-Kasse.md', TAtlasMetricsReportFile.FileName('C:\B', 'D:\Src\Kasse.dproj'));
  Assert.AreEqual('C:\B\Metriken.md', TAtlasMetricsReportFile.FileName('C:\B\', ''));
end;

procedure TAtlasEditorMetricsTests.ReportMarkdownFromAnswer;
var
  Text: string;
begin
  Assert.IsTrue(TAtlasMetricsReportFile.MarkdownFrom('"# Code-Metriken: Kasse\r\n\r\n| a | b |"', Text));
  Assert.AreEqual('# Code-Metriken: Kasse'#13#10#13#10'| a | b |', Text);
  Assert.IsFalse(TAtlasMetricsReportFile.MarkdownFrom('{"summary": {}}', Text), 'kein Markdown');
  Assert.AreEqual('', Text);
  Assert.IsFalse(TAtlasMetricsReportFile.MarkdownFrom('""', Text), 'leer');
  Assert.IsFalse(TAtlasMetricsReportFile.MarkdownFrom('', Text), 'keine Antwort');
  Assert.IsFalse(TAtlasMetricsReportFile.MarkdownFrom('kein JSON', Text));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditorMetricsTests);

end.
