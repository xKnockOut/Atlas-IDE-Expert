unit Atlas.Common.Metrics.Report.Tests;

// Tests des Metrikberichts (#66): Zusammenfassung, JSON, Markdown und Titel
// der Code Lens.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMetricsReportTests = class
  public
    [Test]
    procedure SummaryAveragesAndMaximum;
    [Test]
    procedure SummaryWithoutMethodsIsZero;
    [Test]
    procedure TenthsTextHasOneDecimal;
    [Test]
    procedure JsonStringEscapes;
    [Test]
    procedure RoutineJsonListsExceeded;
    [Test]
    procedure JsonHasFormatLimitsSummaryAndFiles;
    [Test]
    procedure MarkdownListsMethodsOverLimits;
    [Test]
    procedure MarkdownWithoutOverLimits;
    [Test]
    procedure LensTitleShowsLimitWhenExceeded;
    [Test]
    procedure LimitsDefaultsFromSpecification;
    [Test]
    procedure KindKeysRoundTrip;
    [Test]
    procedure StructureJsonAndLensPart;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Report;

function Routine(const AName: string; ALine, ALength, ADepth, ACyclomatic, ACognitive,
  AParameters: Integer): TRoutineMetrics;
begin
  Result.Name := AName;
  Result.NameRange := TTextRange.Create(ALine, 10, ALine, 10 + Length(AName));
  Result.Range := TTextRange.Create(ALine, 0, ALine + ALength + 1, 4);
  Result.Values[TMetricKind.MethodLength] := ALength;
  Result.Values[TMetricKind.NestingDepth] := ADepth;
  Result.Values[TMetricKind.Cyclomatic] := ACyclomatic;
  Result.Values[TMetricKind.Cognitive] := ACognitive;
  Result.Values[TMetricKind.ParameterCount] := AParameters;
end;

function SampleFiles: TArray<TFileMetrics>;
var
  First, Second: TArray<TRoutineMetrics>;
begin
  SetLength(First, 2);
  First[0] := Routine('TFoo.Small', 4, 10, 1, 2, 1, 0);
  First[1] := Routine('TFoo.Big', 20, 75, 5, 17, 20, 2);
  SetLength(Second, 1);
  Second[0] := Routine('Helper', 7, 6, 0, 1, 0, 7);
  SetLength(Result, 2);
  Result[0] := TFileMetrics.Create('Source/Foo.pas', First);
  Result[1] := TFileMetrics.Create('Source/Helper.pas', Second);
end;

{ TMetricsReportTests }

procedure TMetricsReportTests.SummaryAveragesAndMaximum;
var
  Summary: TMetricsSummary;
begin
  Summary := TMetricsReport.Summarize(SampleFiles, TMetricLimits.Default);
  Assert.AreEqual(2, Summary.Files);
  Assert.AreEqual(3, Summary.Methods);
  // (10 + 75 + 6) / 3 = 30,33 → 303 Zehntel
  Assert.AreEqual(303, Summary.AverageTenths(TMetricKind.MethodLength));
  // (2 + 17 + 1) / 3 = 6,67 → 67 Zehntel
  Assert.AreEqual(67, Summary.AverageTenths(TMetricKind.Cyclomatic));
  Assert.AreEqual(75, Summary.Maximum[TMetricKind.MethodLength]);
  Assert.AreEqual(1, Summary.Exceeded[TMetricKind.Cyclomatic]);
  Assert.AreEqual(1, Summary.Exceeded[TMetricKind.ParameterCount]);
  Assert.AreEqual(2, Summary.OverLimits, 'TFoo.Big und Helper');
end;

procedure TMetricsReportTests.SummaryWithoutMethodsIsZero;
var
  Summary: TMetricsSummary;
begin
  Summary := TMetricsReport.Summarize(nil, TMetricLimits.Default);
  Assert.AreEqual(0, Summary.Methods);
  Assert.AreEqual(0, Summary.AverageTenths(TMetricKind.Cognitive));
end;

procedure TMetricsReportTests.TenthsTextHasOneDecimal;
begin
  Assert.AreEqual('12.5', TMetricsReport.TenthsText(125));
  Assert.AreEqual('3.0', TMetricsReport.TenthsText(30));
  Assert.AreEqual('0.4', TMetricsReport.TenthsText(4));
  Assert.AreEqual('-1.5', TMetricsReport.TenthsText(-15));
end;

procedure TMetricsReportTests.JsonStringEscapes;
begin
  Assert.AreEqual('"a\"b\\c\nd"', TMetricsReport.JsonString('a"b\c' + #10 + 'd'));
  Assert.AreEqual('"\u0001"', TMetricsReport.JsonString(#1));
end;

procedure TMetricsReportTests.RoutineJsonListsExceeded;
var
  Json: string;
begin
  Json := TMetricsReport.RoutineJson(Routine('TFoo.Big', 20, 75, 5, 17, 20, 2), TMetricLimits.Default);
  Assert.Contains(Json, '"name": "TFoo.Big"');
  Assert.Contains(Json, '"line": 21');
  Assert.Contains(Json, '"character": 11');
  Assert.Contains(Json, '"values": {"length": 75, "nesting": 5, "cyclomatic": 17, "cognitive": 20, "parameters": 2}');
  Assert.Contains(Json, '"exceeded": ["length", "nesting", "cyclomatic", "cognitive"]');
end;

procedure TMetricsReportTests.JsonHasFormatLimitsSummaryAndFiles;
var
  Json: string;
begin
  Json := TMetricsReport.Json(SampleFiles, TMetricLimits.Default);
  Assert.Contains(Json, '{"format": 1, ');
  Assert.Contains(Json, '"limits": {"length": 60, "nesting": 4, "cyclomatic": 15, "cognitive": 15, "parameters": 6}');
  Assert.Contains(Json, '"summary": {"files": 2, "methods": 3, "overLimits": 2, "average": {"length": 30.3');
  Assert.Contains(Json, '{"file": "Source/Helper.pas", "methods": [{"name": "Helper"');
  Assert.Contains(Json, '"exceeded": ["parameters"]');
end;

procedure TMetricsReportTests.MarkdownListsMethodsOverLimits;
var
  Text: string;
begin
  Text := TMetricsReport.Markdown(SampleFiles, TMetricLimits.Default, 'Demo');
  Assert.Contains(Text, '# Code-Metriken: Demo');
  Assert.Contains(Text, '2 Dateien, 3 Methoden, davon 2 über mindestens einem Grenzwert.');
  Assert.Contains(Text, '| zyklomatisch | 15 | 6,7 | 17 | 1 |');
  Assert.Contains(Text, '## Über einem Grenzwert');
  Assert.Contains(Text, '| TFoo.Big | Source/Foo.pas | 21 | **75** | **5** | **17** | **20** | 2 |');
  Assert.Contains(Text, '| Helper | Source/Helper.pas | 8 | 6 | 0 | 1 | 0 | **7** |');
  Assert.IsTrue(Pos('| TFoo.Big', Text) < Pos('| Helper', Text), 'meiste Überschreitungen zuerst');
  Assert.Contains(Text, '## Komplexeste Methoden');
  Assert.Contains(Text, '| Source/Foo.pas | 2 | 42,5 | 17 | 20 | 1 |');
end;

procedure TMetricsReportTests.MarkdownWithoutOverLimits;
var
  Files: TArray<TFileMetrics>;
  Routines: TArray<TRoutineMetrics>;
  Text: string;
begin
  SetLength(Routines, 1);
  Routines[0] := Routine('Run', 1, 3, 0, 1, 0, 0);
  SetLength(Files, 1);
  Files[0] := TFileMetrics.Create('Run.pas', Routines);
  Text := TMetricsReport.Markdown(Files, TMetricLimits.Default, '');
  Assert.Contains(Text, '# Code-Metriken' + #13#10);
  Assert.Contains(Text, 'Keine Methode überschreitet einen Grenzwert.');
end;

procedure TMetricsReportTests.LensTitleShowsLimitWhenExceeded;
var
  Values: TMetricValues;
begin
  Values := Routine('A', 0, 12, 2, 4, 3, 2).Values;
  Assert.AreEqual('12 Zeilen · Tiefe 2 · zyklomatisch 4 · kognitiv 3 · 2 Parameter',
    TMetricsReport.LensTitle(Values, TMetricLimits.Default));
  Values[TMetricKind.Cyclomatic] := 17;
  Assert.AreEqual('12 Zeilen · Tiefe 2 · zyklomatisch 17 (> 15) · kognitiv 3 · 2 Parameter',
    TMetricsReport.LensTitle(Values, TMetricLimits.Default));
end;

procedure TMetricsReportTests.LimitsDefaultsFromSpecification;
var
  Limits: TMetricLimits;
  Values: TMetricValues;
begin
  Limits := TMetricLimits.Default;
  Assert.AreEqual(60, Limits.Values[TMetricKind.MethodLength]);
  Assert.AreEqual(4, Limits.Values[TMetricKind.NestingDepth]);
  Assert.AreEqual(15, Limits.Values[TMetricKind.Cyclomatic]);
  Assert.AreEqual(15, Limits.Values[TMetricKind.Cognitive]);
  Assert.AreEqual(6, Limits.Values[TMetricKind.ParameterCount]);
  Assert.IsFalse(Limits.Exceeds(TMetricKind.Cyclomatic, 15), 'der Grenzwert selbst ist erlaubt');
  Assert.IsTrue(Limits.Exceeds(TMetricKind.Cyclomatic, 16));
  Values := Routine('A', 0, 61, 0, 1, 0, 0).Values;
  Assert.AreEqual(1, Integer(Length(Limits.Exceeded(Values))));
end;

procedure TMetricsReportTests.StructureJsonAndLensPart;
var
  Item: TStructureMetrics;
  Limits: TMetricLimits;
begin
  Limits := TMetricLimits.Default;
  Assert.AreEqual(40, Limits.Structure[TStructureKind.ClassSize]);
  Assert.AreEqual(2000, Limits.Structure[TStructureKind.UnitLength]);
  Assert.AreEqual(30, Limits.Structure[TStructureKind.UsesCount]);
  Assert.IsFalse(Limits.ExceedsStructure(TStructureKind.ClassSize, 40));
  Assert.IsTrue(Limits.ExceedsStructure(TStructureKind.ClassSize, 41));
  Item := Default(TStructureMetrics);
  Item.Kind := TStructureKind.ClassSize;
  Item.Name := 'TfrmHaupt';
  Item.NameRange := TTextRange.Create(4, 2, 4, 11);
  Item.Value := 87;
  Assert.AreEqual('[{"kind": "classSize", "name": "TfrmHaupt", "line": 5, "character": 3, "value": 87, ' +
    '"limit": 40}]', TMetricsReport.StructureJson([Item], Limits));
  Assert.AreEqual('[]', TMetricsReport.StructureJson(nil, Limits));
  Assert.AreEqual('87 Member (> 40)', TMetricsReport.StructureLensPart(TStructureKind.ClassSize, 87, Limits));
  Assert.AreEqual('12 Units im uses', TMetricsReport.StructureLensPart(TStructureKind.UsesCount, 12, Limits));
  Assert.AreEqual('unitLength', TMetricsReport.StructureKey(TStructureKind.UnitLength));
end;

procedure TMetricsReportTests.KindKeysRoundTrip;
var
  Kind, Found: TMetricKind;
begin
  for Kind := Low(TMetricKind) to High(TMetricKind) do
  begin
    Assert.IsTrue(TMetrics.TryKindOf(TMetrics.Key(Kind), Found), TMetrics.Key(Kind));
    Assert.IsTrue(Kind = Found, TMetrics.Key(Kind));
  end;
  Assert.IsFalse(TMetrics.TryKindOf('lines', Found));
end;

initialization
  TDUnitX.RegisterTestFixture(TMetricsReportTests);

end.
