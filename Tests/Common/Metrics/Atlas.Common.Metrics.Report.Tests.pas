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

/// <summary>Routine AName ab ALine; AValues sind Länge, Verschachtelung, zyklomatische und kognitive
/// Komplexität und Parameterzahl.</summary>
function Routine(const AName: string; ALine: Integer; const AValues: array of Integer): TRoutineMetrics;
begin
  Assert.AreEqual(5, Integer(Length(AValues)), 'Länge, Tiefe, zyklomatisch, kognitiv, Parameter');
  Result := Default(TRoutineMetrics);
  Result.Name := AName;
  Result.NameRange := TTextRange.Create(ALine, 10, ALine, 10 + Length(AName));
  Result.Range := TTextRange.Create(ALine, 0, ALine + AValues[0] + 1, 4);
  Result.Values[TMetricKind.MethodLength] := AValues[0];
  Result.Values[TMetricKind.NestingDepth] := AValues[1];
  Result.Values[TMetricKind.Cyclomatic] := AValues[2];
  Result.Values[TMetricKind.Cognitive] := AValues[3];
  Result.Values[TMetricKind.ParameterCount] := AValues[4];
end;

function SampleFiles: TArray<TFileMetrics>;
var
  mFirst, mSecond: TArray<TRoutineMetrics>;
begin
  SetLength(mFirst, 2);
  mFirst[0] := Routine('TFoo.Small', 4, [10, 1, 2, 1, 0]);
  mFirst[1] := Routine('TFoo.Big', 20, [75, 5, 17, 20, 2]);
  SetLength(mSecond, 1);
  mSecond[0] := Routine('Helper', 7, [6, 0, 1, 0, 7]);
  SetLength(Result, 2);
  Result[0] := TFileMetrics.Create('Source/Foo.pas', mFirst);
  Result[1] := TFileMetrics.Create('Source/Helper.pas', mSecond);
end;

{ TMetricsReportTests }

procedure TMetricsReportTests.SummaryAveragesAndMaximum;
var
  mSummary: TMetricsSummary;
begin
  mSummary := TMetricsReport.Summarize(SampleFiles, TMetricLimits.Default);
  Assert.AreEqual(2, mSummary.Files);
  Assert.AreEqual(3, mSummary.Methods);
  // (10 + 75 + 6) / 3 = 30,33 → 303 Zehntel
  Assert.AreEqual(303, mSummary.AverageTenths(TMetricKind.MethodLength));
  // (2 + 17 + 1) / 3 = 6,67 → 67 Zehntel
  Assert.AreEqual(67, mSummary.AverageTenths(TMetricKind.Cyclomatic));
  Assert.AreEqual(75, mSummary.Maximum[TMetricKind.MethodLength]);
  Assert.AreEqual(1, mSummary.Exceeded[TMetricKind.Cyclomatic]);
  Assert.AreEqual(1, mSummary.Exceeded[TMetricKind.ParameterCount]);
  Assert.AreEqual(2, mSummary.OverLimits, 'TFoo.Big und Helper');
end;

procedure TMetricsReportTests.SummaryWithoutMethodsIsZero;
var
  mSummary: TMetricsSummary;
begin
  mSummary := TMetricsReport.Summarize(nil, TMetricLimits.Default);
  Assert.AreEqual(0, mSummary.Methods);
  Assert.AreEqual(0, mSummary.AverageTenths(TMetricKind.Cognitive));
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
  mJson: string;
begin
  mJson := TMetricsReport.RoutineJson(Routine('TFoo.Big', 20, [75, 5, 17, 20, 2]), TMetricLimits.Default);
  Assert.Contains(mJson, '"name": "TFoo.Big"');
  Assert.Contains(mJson, '"line": 21');
  Assert.Contains(mJson, '"character": 11');
  Assert.Contains(mJson, '"values": {"length": 75, "nesting": 5, "cyclomatic": 17, "cognitive": 20, "parameters": 2, ' +
    '"operands": 0, "locals": 0, "exits": 0}');
  Assert.Contains(mJson, '"exceeded": ["length", "nesting", "cyclomatic", "cognitive"]');
end;

procedure TMetricsReportTests.JsonHasFormatLimitsSummaryAndFiles;
var
  mJson: string;
begin
  mJson := TMetricsReport.Json(SampleFiles, TMetricLimits.Default);
  Assert.Contains(mJson, '{"format": 1, ');
  Assert.Contains(mJson, '"limits": {"length": 60, "nesting": 4, "cyclomatic": 15, "cognitive": 15, "parameters": 6, ' +
    '"operands": 5, "locals": 12, "exits": 4}');
  Assert.Contains(mJson, '"summary": {"files": 2, "methods": 3, "overLimits": 2, "average": {"length": 30.3');
  Assert.Contains(mJson, '{"file": "Source/Helper.pas", "methods": [{"name": "Helper"');
  Assert.Contains(mJson, '"exceeded": ["parameters"]');
end;

procedure TMetricsReportTests.MarkdownListsMethodsOverLimits;
var
  mText: string;
begin
  mText := TMetricsReport.Markdown(SampleFiles, TMetricLimits.Default, 'Demo');
  Assert.Contains(mText, '# Code-Metriken: Demo');
  Assert.Contains(mText, '2 Dateien, 3 Methoden, davon 2 über mindestens einem Grenzwert.');
  Assert.Contains(mText, '| zyklomatisch | 15 | 6,7 | 17 | 1 |');
  Assert.Contains(mText, '## Über einem Grenzwert');
  Assert.Contains(mText, '| TFoo.Big | Source/Foo.pas | 21 | **75** | **5** | **17** | **20** | 2 | 0 | 0 | 0 |');
  Assert.Contains(mText, '| Helper | Source/Helper.pas | 8 | 6 | 0 | 1 | 0 | **7** | 0 | 0 | 0 |');
  Assert.Contains(mText, '| lokale Variablen | 12 | 0,0 | 0 | 0 |');
  Assert.IsTrue(Pos('| TFoo.Big', mText) < Pos('| Helper', mText), 'meiste Überschreitungen zuerst');
  Assert.Contains(mText, '## Komplexeste Methoden');
  Assert.Contains(mText, '| Source/Foo.pas | 2 | 42,5 | 17 | 20 | 1 |');
end;

procedure TMetricsReportTests.MarkdownWithoutOverLimits;
var
  mFiles: TArray<TFileMetrics>;
  mRoutines: TArray<TRoutineMetrics>;
  mText: string;
begin
  SetLength(mRoutines, 1);
  mRoutines[0] := Routine('Run', 1, [3, 0, 1, 0, 0]);
  SetLength(mFiles, 1);
  mFiles[0] := TFileMetrics.Create('Run.pas', mRoutines);
  mText := TMetricsReport.Markdown(mFiles, TMetricLimits.Default, '');
  Assert.Contains(mText, '# Code-Metriken' + #13#10);
  Assert.Contains(mText, 'Keine Methode überschreitet einen Grenzwert.');
end;

procedure TMetricsReportTests.LensTitleShowsLimitWhenExceeded;
var
  mValues: TMetricValues;
begin
  mValues := Routine('A', 0, [12, 2, 4, 3, 2]).Values;
  Assert.AreEqual('12 Zeilen · Tiefe 2 · zyklomatisch 4 · kognitiv 3 · 2 Parameter · Operanden 0 · 0 lokale · ' +
    '0 Ausstiege', TMetricsReport.LensTitle(mValues, TMetricLimits.Default));
  mValues[TMetricKind.Cyclomatic] := 17;
  mValues[TMetricKind.BooleanOperands] := 6;
  mValues[TMetricKind.LocalCount] := 3;
  mValues[TMetricKind.ExitPoints] := 5;
  Assert.AreEqual('12 Zeilen · Tiefe 2 · zyklomatisch 17 (> 15) · kognitiv 3 · 2 Parameter · Operanden 6 (> 5) · ' +
    '3 lokale · 5 Ausstiege (> 4)', TMetricsReport.LensTitle(mValues, TMetricLimits.Default));
end;

procedure TMetricsReportTests.LimitsDefaultsFromSpecification;
var
  mLimits: TMetricLimits;
  mValues: TMetricValues;
begin
  mLimits := TMetricLimits.Default;
  Assert.AreEqual(60, mLimits.Values[TMetricKind.MethodLength]);
  Assert.AreEqual(4, mLimits.Values[TMetricKind.NestingDepth]);
  Assert.AreEqual(15, mLimits.Values[TMetricKind.Cyclomatic]);
  Assert.AreEqual(15, mLimits.Values[TMetricKind.Cognitive]);
  Assert.AreEqual(6, mLimits.Values[TMetricKind.ParameterCount]);
  Assert.AreEqual(5, mLimits.Values[TMetricKind.BooleanOperands]);
  Assert.AreEqual(12, mLimits.Values[TMetricKind.LocalCount]);
  Assert.AreEqual(4, mLimits.Values[TMetricKind.ExitPoints]);
  Assert.AreEqual(5, mLimits.Structure[TStructureKind.InheritanceDepth]);
  Assert.IsFalse(mLimits.Exceeds(TMetricKind.Cyclomatic, 15), 'der Grenzwert selbst ist erlaubt');
  Assert.IsTrue(mLimits.Exceeds(TMetricKind.Cyclomatic, 16));
  mValues := Routine('A', 0, [61, 0, 1, 0, 0]).Values;
  Assert.AreEqual(1, Integer(Length(mLimits.Exceeded(mValues))));
end;

procedure TMetricsReportTests.StructureJsonAndLensPart;
var
  mItem: TStructureMetrics;
  mLimits: TMetricLimits;
begin
  mLimits := TMetricLimits.Default;
  Assert.AreEqual(40, mLimits.Structure[TStructureKind.ClassSize]);
  Assert.AreEqual(2000, mLimits.Structure[TStructureKind.UnitLength]);
  Assert.AreEqual(30, mLimits.Structure[TStructureKind.UsesCount]);
  Assert.IsFalse(mLimits.ExceedsStructure(TStructureKind.ClassSize, 40));
  Assert.IsTrue(mLimits.ExceedsStructure(TStructureKind.ClassSize, 41));
  mItem := Default(TStructureMetrics);
  mItem.Kind := TStructureKind.ClassSize;
  mItem.Name := 'TfrmHaupt';
  mItem.NameRange := TTextRange.Create(4, 2, 4, 11);
  mItem.Value := 87;
  Assert.AreEqual('[{"kind": "classSize", "name": "TfrmHaupt", "line": 5, "character": 3, "value": 87, ' +
    '"limit": 40}]', TMetricsReport.StructureJson([mItem], mLimits));
  Assert.AreEqual('[]', TMetricsReport.StructureJson(nil, mLimits));
  Assert.AreEqual('87 Member (> 40)', TMetricsReport.StructureLensPart(TStructureKind.ClassSize, 87, mLimits));
  Assert.AreEqual('12 Units im uses', TMetricsReport.StructureLensPart(TStructureKind.UsesCount, 12, mLimits));
  Assert.AreEqual('unitLength', TMetricsReport.StructureKey(TStructureKind.UnitLength));
end;

procedure TMetricsReportTests.KindKeysRoundTrip;
var
  mKind, mFound: TMetricKind;
begin
  for mKind := Low(TMetricKind) to High(TMetricKind) do
  begin
    Assert.IsTrue(TMetrics.TryKindOf(TMetrics.Key(mKind), mFound), TMetrics.Key(mKind));
    Assert.AreEqual<TMetricKind>(mFound, mKind, TMetrics.Key(mKind));
  end;
  Assert.IsFalse(TMetrics.TryKindOf('lines', mFound));
end;

initialization
  TDUnitX.RegisterTestFixture(TMetricsReportTests);

end.
