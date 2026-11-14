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
  cAnswer = '{"enabled": false, "limits": {"length": 60, "nesting": 4, "cyclomatic": 15, "cognitive": 15, ' +
    '"parameters": 6, "operands": 5, "locals": 12, "exits": 4}, "file": "Main.pas", "methods": [' +
    '{"name": "TFoo.Run", "line": 12, "character": 15, "values": {"length": 7, "nesting": 1, "cyclomatic": 17, ' +
    '"cognitive": 3, "parameters": 2, "operands": 6, "locals": 3, "exits": 1}, "exceeded": ["cyclomatic"]}, ' +
    '{"name": "Ohne Zeile"}, 42, ' +
    '{"name": "Help", "line": 30, "values": {"length": 2}}]}';

function Parse(const AJson: string): TAtlasFileMetrics;
var
  mValue: TJSONValue;
begin
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasFileMetrics.FromJson(mValue);
  finally
    mValue.Free;
  end;
end;

{ TAtlasEditorMetricsTests }

procedure TAtlasEditorMetricsTests.ReadsServerAnswer;
var
  mMetrics: TAtlasFileMetrics;
begin
  mMetrics := Parse(cAnswer);
  Assert.IsFalse(mMetrics.Enabled);
  Assert.AreEqual(15, mMetrics.Limits[TAtlasMetric.Cyclomatic]);
  Assert.AreEqual(6, mMetrics.Limits[TAtlasMetric.Parameters]);
  Assert.AreEqual(2, Integer(Length(mMetrics.Methods)), 'ohne Zeile und Nicht-Objekte übergangen');
  Assert.AreEqual('TFoo.Run', mMetrics.Methods[0].Name);
  Assert.AreEqual(11, mMetrics.Methods[0].Line, 'Server zählt ab 1, Editor ab 0');
  Assert.AreEqual(17, mMetrics.Methods[0].Values[TAtlasMetric.Cyclomatic]);
  Assert.AreEqual(2, mMetrics.Methods[1].Values[TAtlasMetric.MethodLength]);
  Assert.AreEqual(0, mMetrics.Methods[1].Values[TAtlasMetric.Nesting], 'fehlende Werte sind 0');
  Assert.AreEqual(1, mMetrics.IndexAt(29));
  Assert.AreEqual(0, mMetrics.IndexAt(11));
  Assert.AreEqual(-1, mMetrics.IndexAt(12));
end;

procedure TAtlasEditorMetricsTests.ReadsStructure;
var
  mMetrics: TAtlasFileMetrics;
begin
  mMetrics := Parse('{"structure": [{"kind": "unitLength", "name": "Main", "line": 1, "value": 2140, ' +
    '"limit": 2000}, {"kind": "usesCount", "name": "Main", "line": 3, "value": 12, "limit": 30}, ' +
    '{"kind": "classSize", "name": "TfrmHaupt", "line": 8, "value": 87}, {"kind": "anders", "line": 9, ' +
    '"value": 1}, {"kind": "classSize", "name": "Ohne Zeile", "value": 1}], "methods": []}');
  Assert.AreEqual(3, Integer(Length(mMetrics.Structures)), 'unbekannte Art und fehlende Zeile übergangen');
  Assert.AreEqual(0, mMetrics.StructureAt(0));
  Assert.AreEqual(1, mMetrics.StructureAt(2));
  Assert.AreEqual(2, mMetrics.StructureAt(7));
  Assert.AreEqual(-1, mMetrics.StructureAt(8));
  Assert.AreEqual('TfrmHaupt', mMetrics.Structures[2].Name);
  Assert.AreEqual(MaxInt, mMetrics.Structures[2].Limit, 'ohne Grenzwert nie überschritten');
  Assert.AreEqual(2140, mMetrics.Structures[0].Value);
  Assert.AreEqual(2000, mMetrics.Structures[0].Limit);
  Assert.AreEqual(0, Integer(Length(Parse(cAnswer).Structures)), 'ältere Server ohne "structure"');
end;

procedure TAtlasEditorMetricsTests.InheritanceDepthBesideMembers;
var
  mMetrics: TAtlasFileMetrics;
begin
  mMetrics := Parse('{"structure": [{"kind": "classSize", "name": "TfrmHaupt", "line": 8, "value": 87, ' +
    '"limit": 40}, {"kind": "inheritanceDepth", "name": "TfrmHaupt", "line": 8, "value": 3, "limit": 5}, ' +
    '{"kind": "inheritanceDepth", "name": "TDialog", "line": 20, "value": 6, "limit": 5, "atLeast": true}], ' +
    '"methods": []}');
  Assert.AreEqual(3, Integer(Length(mMetrics.Structures)));
  Assert.AreEqual(2, Integer(Length(mMetrics.StructuresAt(7))), 'Member und Vererbungstiefe in einer Zeile');
  Assert.IsFalse(mMetrics.Structures[1].AtLeast);
  Assert.IsTrue(mMetrics.Structures[2].AtLeast);
  Assert.AreEqual<TAtlasStructureMetric>(TAtlasStructureMetric.InheritanceDepth, mMetrics.StructuresAt(7)[1].Kind);
  Assert.AreEqual(0, Integer(Length(mMetrics.StructuresAt(0))));
end;

procedure TAtlasEditorMetricsTests.InvalidAnswerIsOffAndEmpty;
var
  mMetrics: TAtlasFileMetrics;
begin
  mMetrics := TAtlasFileMetrics.FromJson(nil);
  Assert.IsFalse(mMetrics.Enabled);
  Assert.AreEqual(0, Integer(Length(mMetrics.Methods)));
  mMetrics := Parse('[1, 2]');
  Assert.IsFalse(mMetrics.Enabled);
  mMetrics := Parse('{"methods": "keine"}');
  Assert.IsTrue(mMetrics.Enabled, 'ohne "enabled" an');
  Assert.AreEqual(0, Integer(Length(mMetrics.Methods)));
end;

procedure TAtlasEditorMetricsTests.MissingLimitsNeverExceed;
var
  mMetrics: TAtlasFileMetrics;
begin
  mMetrics := Parse('{"limits": {"nesting": 1}, "methods": [{"name": "A", "line": 1, ' +
    '"values": {"length": 900, "nesting": 2}}]}');
  Assert.AreEqual(MaxInt, mMetrics.Limits[TAtlasMetric.MethodLength]);
  Assert.AreEqual(1, mMetrics.Limits[TAtlasMetric.Nesting]);
  mMetrics := Parse('{"methods": [{"name": "A", "line": 1, "values": {"length": 900}}]}');
  Assert.AreEqual(MaxInt, mMetrics.Limits[TAtlasMetric.Nesting], 'ohne "limits" unbegrenzt');
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
  mText: string;
begin
  Assert.IsTrue(TAtlasMetricsReportFile.MarkdownFrom('"# Code-Metriken: Kasse\r\n\r\n| a | b |"', mText));
  Assert.AreEqual('# Code-Metriken: Kasse'#13#10#13#10'| a | b |', mText);
  Assert.IsFalse(TAtlasMetricsReportFile.MarkdownFrom('{"summary": {}}', mText), 'kein Markdown');
  Assert.AreEqual('', mText);
  Assert.IsFalse(TAtlasMetricsReportFile.MarkdownFrom('""', mText), 'leer');
  Assert.IsFalse(TAtlasMetricsReportFile.MarkdownFrom('', mText), 'keine Antwort');
  Assert.IsFalse(TAtlasMetricsReportFile.MarkdownFrom('kein JSON', mText));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditorMetricsTests);

end.
