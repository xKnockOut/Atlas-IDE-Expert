unit Atlas.Core.Editor.Metrics.Tests;

// Tests der Code Lens mit Code-Metriken im Plugin (#66): Antwort des Servers
// lesen, Beschriftung mit Grenzwert, Zeile wiedererkennen.

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
    procedure InvalidAnswerIsOffAndEmpty;
    [Test]
    procedure MissingLimitsNeverExceed;
    [Test]
    procedure CaptionMarksExceededValues;
    [Test]
    procedure LineMatchesMethodName;
    [Test]
    procedure ReportFileNames;
    [Test]
    procedure ReportMarkdownFromAnswer;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Editor.Metrics;

const
  Answer = '{"enabled": false, "limits": {"length": 60, "nesting": 4, "cyclomatic": 15, "cognitive": 15, ' +
    '"parameters": 6}, "file": "Main.pas", "methods": [' +
    '{"name": "TFoo.Run", "line": 12, "character": 15, "values": {"length": 7, "nesting": 1, "cyclomatic": 17, ' +
    '"cognitive": 3, "parameters": 2}, "exceeded": ["cyclomatic"]}, ' +
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

function GermanFormats: TAtlasMetricFormats;
begin
  Result[TAtlasMetric.MethodLength] := '%d Zeilen';
  Result[TAtlasMetric.Nesting] := 'Tiefe %d';
  Result[TAtlasMetric.Cyclomatic] := 'zyklomatisch %d';
  Result[TAtlasMetric.Cognitive] := 'kognitiv %d';
  Result[TAtlasMetric.Parameters] := '%d Parameter';
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
  Assert.IsTrue(TAtlasMetricsLens.Exceeds(Metrics.Methods[0], Metrics.Limits));
  Metrics := Parse('{"methods": [{"name": "A", "line": 1, "values": {"length": 900}}]}');
  Assert.IsFalse(TAtlasMetricsLens.Exceeds(Metrics.Methods[0], Metrics.Limits));
end;

procedure TAtlasEditorMetricsTests.CaptionMarksExceededValues;
var
  Metrics: TAtlasFileMetrics;
begin
  Metrics := Parse(Answer);
  Assert.AreEqual('7 Zeilen · Tiefe 1 · zyklomatisch 17 (> 15) · kognitiv 3 · 2 Parameter',
    TAtlasMetricsLens.Caption(Metrics.Methods[0], Metrics.Limits, GermanFormats, '%s (> %d)'));
  Assert.AreEqual('2 Zeilen · Tiefe 0 · zyklomatisch 0 · kognitiv 0 · 0 Parameter',
    TAtlasMetricsLens.Caption(Metrics.Methods[1], Metrics.Limits, GermanFormats, '%s (> %d)'));
  Assert.IsTrue(TAtlasMetricsLens.Exceeds(Metrics.Methods[0], Metrics.Limits));
  Assert.IsFalse(TAtlasMetricsLens.Exceeds(Metrics.Methods[1], Metrics.Limits));
  Assert.AreEqual('cognitive', TAtlasMetricsLens.Key(TAtlasMetric.Cognitive));
  Assert.AreEqual('parameters', TAtlasMetricsLens.Key(TAtlasMetric.Parameters));
end;

procedure TAtlasEditorMetricsTests.LineMatchesMethodName;
begin
  Assert.IsTrue(TAtlasMetricsLens.LineMatches('procedure TFoo.Run(A: Integer);', 'TFoo.Run'));
  Assert.IsTrue(TAtlasMetricsLens.LineMatches('function run: Boolean;', 'TFoo.Run'), 'ohne Groß/klein');
  Assert.IsTrue(TAtlasMetricsLens.LineMatches('class procedure TFoo.TBar.Run;', 'TFoo.TBar.Run'));
  Assert.IsFalse(TAtlasMetricsLens.LineMatches('procedure TFoo.Running;', 'TFoo.Run'), 'nur ganze Bezeichner');
  Assert.IsFalse(TAtlasMetricsLens.LineMatches('procedure TFoo.ReRun;', 'TFoo.Run'));
  Assert.IsTrue(TAtlasMetricsLens.LineMatches('procedure TFoo.ReRun; procedure Run;', 'Run'), 'zweiter Treffer');
  Assert.IsFalse(TAtlasMetricsLens.LineMatches('begin', 'Run'));
  Assert.IsFalse(TAtlasMetricsLens.LineMatches('procedure Run;', ''));
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
