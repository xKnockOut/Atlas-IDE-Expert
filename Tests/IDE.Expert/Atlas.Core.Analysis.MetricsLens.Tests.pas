unit Atlas.Core.Analysis.MetricsLens.Tests;

// Tests der Beschriftung der Code Lens mit Code-Metriken (#66) im Modul Analyse (#1756): Beschriftung mit
// Grenzwert, Kennzahlen des Aufbaus (#939) mit Vererbungstiefe neben den Membern (#980), Überschreitung und Zeile
// wiedererkennen. Die Antwort liest Base (Atlas.Core.Editor.Metrics).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Analysis')]
  TAtlasAnalysisMetricsLensTests = class
  public
    [Test]
    procedure CaptionMarksExceededValues;
    [Test]
    procedure StructureCaptions;
    [Test]
    procedure InheritanceDepthBesideMembers;
    [Test]
    procedure MissingLimitsNeverExceed;
    [Test]
    procedure LineMatchesMethodName;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Editor.Metrics,
  Atlas.Core.Analysis.MetricsLens;

const
  cAnswer = '{"limits": {"length": 60, "nesting": 4, "cyclomatic": 15, "cognitive": 15, "parameters": 6, ' +
    '"operands": 5, "locals": 12, "exits": 4}, "methods": [{"name": "TFoo.Run", "line": 12, "values": ' +
    '{"length": 7, "nesting": 1, "cyclomatic": 17, "cognitive": 3, "parameters": 2, "operands": 6, "locals": 3, ' +
    '"exits": 1}}, {"name": "Help", "line": 30, "values": {"length": 2}}]}';
  cLimitFormat = '%s (> %d)';

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

function GermanFormats: TAtlasMetricFormats;
begin
  Result[TAtlasMetric.MethodLength] := '%d Zeilen';
  Result[TAtlasMetric.Nesting] := 'Tiefe %d';
  Result[TAtlasMetric.Cyclomatic] := 'zyklomatisch %d';
  Result[TAtlasMetric.Cognitive] := 'kognitiv %d';
  Result[TAtlasMetric.Parameters] := '%d Parameter';
  Result[TAtlasMetric.Operands] := 'Operanden %d';
  Result[TAtlasMetric.Locals] := '%d lokale';
  Result[TAtlasMetric.Exits] := '%d Ausstiege';
end;

function GermanStructureFormats: TAtlasStructureFormats;
begin
  Result[TAtlasStructureMetric.ClassSize] := '%d Member';
  Result[TAtlasStructureMetric.UnitLength] := '%d Zeilen';
  Result[TAtlasStructureMetric.UsesCount] := '%d Units im uses';
  Result[TAtlasStructureMetric.InheritanceDepth] := 'Vererbungstiefe %d';
end;

{ TAtlasAnalysisMetricsLensTests }

procedure TAtlasAnalysisMetricsLensTests.CaptionMarksExceededValues;
var
  mMetrics: TAtlasFileMetrics;
begin
  mMetrics := Parse(cAnswer);
  Assert.AreEqual('7 Zeilen · Tiefe 1 · zyklomatisch 17 (> 15) · kognitiv 3 · 2 Parameter · Operanden 6 (> 5) · ' +
    '3 lokale · 1 Ausstiege', TAtlasMetricsLens.Caption(mMetrics.Methods[0], mMetrics.Limits, GermanFormats,
    cLimitFormat));
  Assert.AreEqual('2 Zeilen · Tiefe 0 · zyklomatisch 0 · kognitiv 0 · 0 Parameter · Operanden 0 · 0 lokale · ' +
    '0 Ausstiege', TAtlasMetricsLens.Caption(mMetrics.Methods[1], mMetrics.Limits, GermanFormats, cLimitFormat));
  Assert.IsTrue(TAtlasMetricsLens.Exceeds(mMetrics.Methods[0], mMetrics.Limits));
  Assert.IsFalse(TAtlasMetricsLens.Exceeds(mMetrics.Methods[1], mMetrics.Limits));
end;

procedure TAtlasAnalysisMetricsLensTests.StructureCaptions;
var
  mMetrics: TAtlasFileMetrics;
begin
  mMetrics := Parse('{"structure": [{"kind": "unitLength", "name": "Main", "line": 1, "value": 2140, ' +
    '"limit": 2000}, {"kind": "usesCount", "name": "Main", "line": 3, "value": 12, "limit": 30}, ' +
    '{"kind": "classSize", "name": "TfrmHaupt", "line": 8, "value": 87}], "methods": []}');
  Assert.AreEqual('2140 Zeilen (> 2000)', TAtlasMetricsLens.StructureCaption(mMetrics.Structures[0],
    GermanStructureFormats, cLimitFormat));
  Assert.AreEqual('12 Units im uses', TAtlasMetricsLens.StructureCaption(mMetrics.Structures[1],
    GermanStructureFormats, cLimitFormat));
  Assert.AreEqual('87 Member', TAtlasMetricsLens.StructureCaption(mMetrics.Structures[2], GermanStructureFormats,
    cLimitFormat), 'ohne Grenzwert nie überschritten');
end;

procedure TAtlasAnalysisMetricsLensTests.InheritanceDepthBesideMembers;
var
  mMetrics: TAtlasFileMetrics;
begin
  mMetrics := Parse('{"structure": [{"kind": "classSize", "name": "TfrmHaupt", "line": 8, "value": 87, ' +
    '"limit": 40}, {"kind": "inheritanceDepth", "name": "TfrmHaupt", "line": 8, "value": 3, "limit": 5}, ' +
    '{"kind": "inheritanceDepth", "name": "TDialog", "line": 20, "value": 6, "limit": 5, "atLeast": true}], ' +
    '"methods": []}');
  Assert.AreEqual('87 Member (> 40) · Vererbungstiefe 3', TAtlasMetricsLens.StructureCaption(
    mMetrics.StructuresAt(7), GermanStructureFormats, 'Vererbungstiefe mindestens %d', cLimitFormat));
  Assert.AreEqual('Vererbungstiefe mindestens 6 (> 5)', TAtlasMetricsLens.StructureCaption(
    mMetrics.StructuresAt(19), GermanStructureFormats, 'Vererbungstiefe mindestens %d', cLimitFormat));
  Assert.AreEqual('', TAtlasMetricsLens.StructureCaption(mMetrics.StructuresAt(0), GermanStructureFormats,
    'Vererbungstiefe mindestens %d', cLimitFormat), 'leere Zeile');
end;

procedure TAtlasAnalysisMetricsLensTests.MissingLimitsNeverExceed;
var
  mMetrics: TAtlasFileMetrics;
begin
  mMetrics := Parse('{"limits": {"nesting": 1}, "methods": [{"name": "A", "line": 1, ' +
    '"values": {"length": 900, "nesting": 2}}]}');
  Assert.IsTrue(TAtlasMetricsLens.Exceeds(mMetrics.Methods[0], mMetrics.Limits));
  mMetrics := Parse('{"methods": [{"name": "A", "line": 1, "values": {"length": 900}}]}');
  Assert.IsFalse(TAtlasMetricsLens.Exceeds(mMetrics.Methods[0], mMetrics.Limits));
end;

procedure TAtlasAnalysisMetricsLensTests.LineMatchesMethodName;
begin
  Assert.IsTrue(TAtlasMetricsLens.LineMatches('procedure TFoo.Run(A: Integer);', 'TFoo.Run'));
  Assert.IsTrue(TAtlasMetricsLens.LineMatches('function run: Boolean;', 'TFoo.Run'), 'ohne Groß/klein');
  Assert.IsTrue(TAtlasMetricsLens.LineMatches('class procedure TFoo.TBar.Run;', 'TFoo.TBar.Run'));
  Assert.IsFalse(TAtlasMetricsLens.LineMatches('procedure TFoo.Running;', 'TFoo.Run'), 'nur ganze Bezeichner');
  Assert.IsFalse(TAtlasMetricsLens.LineMatches('procedure TFoo.ReRun;', 'TFoo.Run'));
  Assert.IsTrue(TAtlasMetricsLens.LineMatches('procedure TFoo.ReRun; procedure Run;', 'Run'), 'zweiter Treffer');
  Assert.IsTrue(TAtlasMetricsLens.LineMatches('Run', 'Run'), 'ganze Zeile');
  Assert.IsFalse(TAtlasMetricsLens.LineMatches('begin', 'Run'));
  Assert.IsFalse(TAtlasMetricsLens.LineMatches('procedure Run;', ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasAnalysisMetricsLensTests);

end.
