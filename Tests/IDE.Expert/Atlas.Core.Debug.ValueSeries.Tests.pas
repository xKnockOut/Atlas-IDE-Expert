unit Atlas.Core.Debug.ValueSeries.Tests;

// Werteverlauf aus Logpunkten (#2552) ohne IDE: Zahlen in deutscher und
// englischer Schreibweise, Text als Lücke, Wert aus der zusammengeführten
// Zeile, Reihe mit Grenze, Threads, Kennzahlen und CSV.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasValueSeriesTests = class
  public
    /// <summary>Abnahme: Gleitkommazahlen deutsch und englisch; Text ist keine Zahl.</summary>
    [Test]
    procedure NumbersGermanAndEnglish;
    [Test]
    procedure TextIsNoNumber;
    [Test]
    procedure SplitTakesPrefixAndPlace;
    [Test]
    procedure ExtractValueFromMessage;
    [Test]
    procedure ExtractNeedsSinglePlaceholder;
    [Test]
    procedure PointFromLineOrGap;
    /// <summary>Abnahme: Mehr Treffer als die Grenze, die ältesten fallen heraus.</summary>
    [Test]
    procedure LimitDropsOldest;
    [Test]
    procedure SmallerLimitKeepsNewest;
    /// <summary>Abnahme: Filter nach Thread; Text als Lücke, nicht als 0.</summary>
    [Test]
    procedure ThreadsStatsAndGaps;
    /// <summary>Abnahme: CSV mit Zeit, Thread und Wert je Treffer.</summary>
    [Test]
    procedure CsvHasTimeThreadValue;
    [Test]
    procedure SetFindsSeriesByPlace;
    [Test]
    procedure ValueText;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Logpoint,
  Atlas.Core.Debug.ValueSeries;

function Point(AAtMs: Int64; const AThread, AText: string): TAtlasValuePoint;
begin
  Result := Default(TAtlasValuePoint);
  Result.AtMs := AAtMs;
  Result.Thread := AThread;
  Result.Line := AText;
  Result.IsGap := not TAtlasLogpointNumber.TryParse(AText, Result.Value);
end;

procedure TAtlasValueSeriesTests.NumbersGermanAndEnglish;
var
  mValue: Double;
begin
  Assert.IsTrue(TAtlasLogpointNumber.TryParse('48', mValue));
  Assert.AreEqual(Double(48), mValue, 1E-9);
  Assert.IsTrue(TAtlasLogpointNumber.TryParse('-3,5', mValue));
  Assert.AreEqual(Double(-3.5), mValue, 1E-9);
  Assert.IsTrue(TAtlasLogpointNumber.TryParse('3.25', mValue));
  Assert.AreEqual(Double(3.25), mValue, 1E-9);
  Assert.IsTrue(TAtlasLogpointNumber.TryParse('1.234,5', mValue));
  Assert.AreEqual(Double(1234.5), mValue, 1E-9);
  Assert.IsTrue(TAtlasLogpointNumber.TryParse('1,234.5', mValue));
  Assert.AreEqual(Double(1234.5), mValue, 1E-9);
  Assert.IsTrue(TAtlasLogpointNumber.TryParse('1.234.567', mValue));
  Assert.AreEqual(Double(1234567), mValue, 1E-9);
  Assert.IsTrue(TAtlasLogpointNumber.TryParse('2.5E3', mValue));
  Assert.AreEqual(Double(2500), mValue, 1E-9);
  Assert.IsTrue(TAtlasLogpointNumber.TryParse(' 7 ', mValue));
  Assert.AreEqual(Double(7), mValue, 1E-9);
end;

procedure TAtlasValueSeriesTests.TextIsNoNumber;
var
  mValue: Double;
begin
  Assert.IsFalse(TAtlasLogpointNumber.TryParse('', mValue));
  Assert.IsFalse(TAtlasLogpointNumber.TryParse('True', mValue));
  Assert.IsFalse(TAtlasLogpointNumber.TryParse('''abc''', mValue));
  Assert.IsFalse(TAtlasLogpointNumber.TryParse('nil', mValue));
  Assert.IsFalse(TAtlasLogpointNumber.TryParse('12 ms', mValue));
  Assert.IsFalse(TAtlasLogpointNumber.TryParse('E5', mValue));
  Assert.IsFalse(TAtlasLogpointNumber.TryParse('-', mValue));
  Assert.AreEqual(Double(0), mValue, 1E-9);
end;

procedure TAtlasValueSeriesTests.SplitTakesPrefixAndPlace;
var
  mMessage, mPlace: string;
begin
  Assert.IsTrue(TAtlasLogpointValue.Split('[LOG] Offen: 48 · Auftrag.Lauf.pas:240', '[LOG]', mMessage, mPlace));
  Assert.AreEqual('Offen: 48', mMessage);
  Assert.AreEqual('Auftrag.Lauf.pas:240', mPlace);
  Assert.IsFalse(TAtlasLogpointValue.Split('Anderes 48', '[LOG]', mMessage, mPlace));
  Assert.IsTrue(TAtlasLogpointValue.Split('[log] ohne Ort', '[LOG]', mMessage, mPlace));
  Assert.AreEqual('ohne Ort', mMessage);
  Assert.AreEqual('', mPlace);
end;

procedure TAtlasValueSeriesTests.ExtractValueFromMessage;
var
  mValue: string;
begin
  Assert.IsTrue(TAtlasLogpointValue.Extract(TAtlasLogpointTemplate.Parse('Offen: {FOffen.Count}'), 'Offen: 48',
    mValue));
  Assert.AreEqual('48', mValue);
  Assert.IsTrue(TAtlasLogpointValue.Extract(TAtlasLogpointTemplate.Parse('Dauer {Ms:0.0} ms'), 'Dauer 12,5 ms',
    mValue));
  Assert.AreEqual('12,5', mValue);
  Assert.IsTrue(TAtlasLogpointValue.Extract(TAtlasLogpointTemplate.Parse('{X}'), '-3', mValue));
  Assert.AreEqual('-3', mValue);
  Assert.IsFalse(TAtlasLogpointValue.Extract(TAtlasLogpointTemplate.Parse('Offen: {X}'), 'Zu: 3', mValue));
end;

procedure TAtlasValueSeriesTests.ExtractNeedsSinglePlaceholder;
var
  mValue: string;
begin
  Assert.IsFalse(TAtlasLogpointValue.CanRecord(TAtlasLogpointTemplate.Parse('nur Text')));
  Assert.IsFalse(TAtlasLogpointValue.CanRecord(TAtlasLogpointTemplate.Parse('{A} und {B}')));
  Assert.IsFalse(TAtlasLogpointValue.CanRecord(TAtlasLogpointTemplate.Parse('kaputt {A')));
  Assert.IsTrue(TAtlasLogpointValue.CanRecord(TAtlasLogpointTemplate.Parse('Wert {A}')));
  Assert.IsFalse(TAtlasLogpointValue.Extract(TAtlasLogpointTemplate.Parse('{A} und {B}'), '1 und 2', mValue));
end;

procedure TAtlasValueSeriesTests.PointFromLineOrGap;
var
  mTemplate: TAtlasLogpointTemplate;
  mPoint: TAtlasValuePoint;
begin
  mTemplate := TAtlasLogpointTemplate.Parse('Offen: {FOffen.Count}');
  Assert.IsTrue(TAtlasValuePoint.TryOf(mTemplate, 'Offen: 1.234,5', 1500, '7', 'Zeile', mPoint));
  Assert.IsFalse(mPoint.IsGap);
  Assert.AreEqual(Double(1234.5), mPoint.Value, 1E-9);
  Assert.AreEqual(Int64(1500), mPoint.AtMs);
  Assert.AreEqual('7', mPoint.Thread);
  Assert.AreEqual('Zeile', mPoint.Line);
  // Ein Text-Wert ist ein Treffer, aber eine Lücke.
  Assert.IsTrue(TAtlasValuePoint.TryOf(mTemplate, 'Offen: nil', 1600, '7', 'Zeile', mPoint));
  Assert.IsTrue(mPoint.IsGap);
  Assert.IsFalse(TAtlasValuePoint.TryOf(mTemplate, 'Zu: 3', 1700, '7', 'Zeile', mPoint));
end;

procedure TAtlasValueSeriesTests.LimitDropsOldest;
var
  mSeries: TAtlasValueSeries;
  mIndex: Integer;
begin
  mSeries := TAtlasValueSeries.Create('Offen', 'A.pas:1', TAtlasValueSeries.cMinLimit);
  try
    for mIndex := 1 to 25 do
    begin
      mSeries.Add(Point(mIndex * 100, '1', IntToStr(mIndex)));
    end;
    Assert.AreEqual(TAtlasValueSeries.cMinLimit, mSeries.Count);
    Assert.AreEqual(Double(16), mSeries[0].Value, 1E-9);
    Assert.AreEqual(Double(25), mSeries[mSeries.Count - 1].Value, 1E-9);
    Assert.AreEqual(Int64(1600), mSeries[0].AtMs);
  finally
    mSeries.Free;
  end;
end;

procedure TAtlasValueSeriesTests.SmallerLimitKeepsNewest;
var
  mSeries: TAtlasValueSeries;
  mIndex: Integer;
begin
  mSeries := TAtlasValueSeries.Create('Offen', 'A.pas:1', 20);
  try
    for mIndex := 1 to 15 do
    begin
      mSeries.Add(Point(mIndex, '1', IntToStr(mIndex)));
    end;
    mSeries.SetLimit(TAtlasValueSeries.cMinLimit);
    Assert.AreEqual(TAtlasValueSeries.cMinLimit, mSeries.Count);
    Assert.AreEqual(Double(6), mSeries[0].Value, 1E-9);
    mSeries.Add(Point(16, '1', '16'));
    Assert.AreEqual(Double(7), mSeries[0].Value, 1E-9);
    Assert.AreEqual(Double(16), mSeries[TAtlasValueSeries.cMinLimit - 1].Value, 1E-9);
  finally
    mSeries.Free;
  end;
end;

procedure TAtlasValueSeriesTests.ThreadsStatsAndGaps;
var
  mSeries: TAtlasValueSeries;
  mStats: TAtlasValueStats;
  mThreads: TArray<string>;
begin
  mSeries := TAtlasValueSeries.Create('Offen', 'A.pas:1', 100);
  try
    mSeries.Add(Point(100, '7', '3'));
    mSeries.Add(Point(200, '9', '10'));
    mSeries.Add(Point(300, '7', 'nil'));
    mSeries.Add(Point(400, '7', '-2'));
    mThreads := mSeries.Threads;
    Assert.AreEqual(2, Integer(Length(mThreads)));
    Assert.AreEqual('7', mThreads[0]);
    Assert.AreEqual('9', mThreads[1]);
    Assert.AreEqual(3, Integer(Length(mSeries.PointsOf('7'))));
    Assert.IsTrue(mSeries.PointsOf('7')[1].IsGap);
    mStats := mSeries.Stats('7');
    Assert.AreEqual(3, mStats.Count);
    Assert.AreEqual(2, mStats.Numbers);
    Assert.AreEqual(Double(-2), mStats.Min, 1E-9);
    Assert.AreEqual(Double(3), mStats.Max, 1E-9);
    Assert.AreEqual(Double(-2), mStats.Last, 1E-9);
    Assert.AreEqual(Double(10), mSeries.Stats('').Max, 1E-9);
  finally
    mSeries.Free;
  end;
end;

procedure TAtlasValueSeriesTests.CsvHasTimeThreadValue;
var
  mSeries: TAtlasValueSeries;
begin
  mSeries := TAtlasValueSeries.Create('Offen', 'A.pas:1', 100);
  try
    mSeries.Add(Point(1500, '7', '3,5'));
    mSeries.Add(Point(2000, 'Arbeiter, 2', 'nil'));
    Assert.AreEqual('time_s,thread,value' + sLineBreak + '1.500,7,3.5' + sLineBreak + '2.000,"Arbeiter, 2",' +
      sLineBreak, mSeries.ToCsv(''));
    Assert.AreEqual('time_s,thread,value' + sLineBreak + '1.500,7,3.5' + sLineBreak, mSeries.ToCsv('7'));
  finally
    mSeries.Free;
  end;
end;

procedure TAtlasValueSeriesTests.SetFindsSeriesByPlace;
var
  mSet: TAtlasValueSeriesSet;
  mSeries: TAtlasValueSeries;
begin
  mSet := TAtlasValueSeriesSet.Create;
  try
    mSeries := mSet.Ensure('A.pas:1', 'Offen', 100);
    Assert.AreSame(mSeries, mSet.Ensure('a.pas:1', 'Neu', 50));
    Assert.AreEqual('Neu', mSeries.Name);
    Assert.AreEqual(50, mSeries.Limit);
    Assert.IsNull(mSet.Find('B.pas:2'));
    Assert.AreEqual(1, mSet.Count);
    mSet.Clear;
    Assert.AreEqual(0, mSet.Count);
  finally
    mSet.Free;
  end;
end;

procedure TAtlasValueSeriesTests.ValueText;
var
  mFormat: TFormatSettings;
begin
  mFormat := TFormatSettings.Invariant;
  Assert.AreEqual('48', TAtlasValueText.Text(48, mFormat));
  Assert.AreEqual('-3.5', TAtlasValueText.Text(-3.5, mFormat));
  Assert.AreEqual('0.1235', TAtlasValueText.Text(0.12346, mFormat));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasValueSeriesTests);

end.
