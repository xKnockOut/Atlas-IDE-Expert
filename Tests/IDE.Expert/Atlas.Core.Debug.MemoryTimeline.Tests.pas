unit Atlas.Core.Debug.MemoryTimeline.Tests;

// Tests für den Kern des Speicherverlaufs (#858) ohne IDE: Zuwachs im gewählten Bereich, Obergrenze der Messungen
// samt Marken, CSV, Zahlen mit Einheit und die Abbildung auf die Zeichenfläche.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasMemoryTimelineTests = class
  public
    [Test]
    procedure GrowthBetweenTwoPoints;
    [Test]
    procedure GrowthNeedsTwoSamples;
    [Test]
    procedure DropsOldestSamplesAndTheirMarks;
    [Test]
    procedure CsvWithMarks;
    [Test]
    procedure FormatsValues;
    [Test]
    procedure ScaleMapsBothWays;
    [Test]
    procedure NiceMaxRoundsUp;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.MemoryTimeline;

function Sample(AAtMs, APrivate, AHandles: Int64): TAtlasMemorySample;
begin
  Result := Default(TAtlasMemorySample);
  Result.AtMs := AAtMs;
  Result.Values[TAtlasMemorySeries.PrivateBytes] := APrivate;
  Result.Values[TAtlasMemorySeries.WorkingSet] := APrivate * 2;
  Result.Values[TAtlasMemorySeries.Handles] := AHandles;
  Result.Values[TAtlasMemorySeries.GdiObjects] := 10;
  Result.Values[TAtlasMemorySeries.UserObjects] := 5;
end;

/// <summary>Ein Programm, das je Sekunde 1 MB und 3 Handles mehr hält.</summary>
function Leaking(ASeconds: Integer): TAtlasMemoryTimeline;
var
  mSecond: Integer;
begin
  Result := TAtlasMemoryTimeline.Create;
  for mSecond := 0 to ASeconds do
  begin
    Result.AddSample(Sample(mSecond * 1000, Int64(mSecond) * 1024 * 1024, 100 + 3 * mSecond));
  end;
end;

procedure TAtlasMemoryTimelineTests.GrowthBetweenTwoPoints;
var
  mTimeline: TAtlasMemoryTimeline;
  mGrowth: TAtlasMemoryGrowth;
begin
  mTimeline := Leaking(60);
  try
    // Bereich rückwärts gezogen und zwischen den Messungen: gilt von 10 s bis 50 s.
    mGrowth := mTimeline.Growth(50500, 9500);
    Assert.IsTrue(mGrowth.Valid);
    Assert.AreEqual(Int64(10000), mGrowth.FromMs);
    Assert.AreEqual(Int64(40000), mGrowth.DurationMs);
    Assert.AreEqual(Int64(40) * 1024 * 1024, mGrowth.Deltas[TAtlasMemorySeries.PrivateBytes]);
    Assert.AreEqual(Int64(120), mGrowth.Deltas[TAtlasMemorySeries.Handles]);
    Assert.AreEqual(Int64(0), mGrowth.Deltas[TAtlasMemorySeries.GdiObjects]);
    Assert.AreEqual(Int64(60) * 1024 * 1024, mTimeline.MaxOf(TAtlasMemorySeries.PrivateBytes));
  finally
    mTimeline.Free;
  end;
end;

procedure TAtlasMemoryTimelineTests.GrowthNeedsTwoSamples;
var
  mTimeline: TAtlasMemoryTimeline;
begin
  mTimeline := Leaking(5);
  try
    Assert.IsFalse(mTimeline.Growth(1200, 1800).Valid, 'keine Messung im Bereich');
    Assert.IsFalse(mTimeline.Growth(2000, 2000).Valid, 'eine Messung');
    Assert.IsTrue(mTimeline.Growth(2000, 3000).Valid);
    mTimeline.Clear;
    Assert.IsFalse(mTimeline.Growth(0, 10000).Valid, 'leer');
    Assert.AreEqual(Int64(0), mTimeline.MaxOf(TAtlasMemorySeries.Handles));
  finally
    mTimeline.Free;
  end;
end;

procedure TAtlasMemoryTimelineTests.DropsOldestSamplesAndTheirMarks;
var
  mTimeline: TAtlasMemoryTimeline;
  mSecond: Integer;
begin
  mTimeline := TAtlasMemoryTimeline.Create(3);
  try
    mTimeline.AddMark(500, TAtlasMemoryMarkKind.Stop, 'früh');
    mTimeline.AddMark(2500, TAtlasMemoryMarkKind.Custom, 'spät');
    for mSecond := 0 to 4 do
    begin
      mTimeline.AddSample(Sample(mSecond * 1000, mSecond, mSecond));
    end;
    Assert.AreEqual(3, mTimeline.Count);
    Assert.AreEqual(Int64(2000), mTimeline[0].AtMs);
    Assert.AreEqual(1, mTimeline.MarkCount);
    Assert.AreEqual('spät', mTimeline.Marks[0].Name);
  finally
    mTimeline.Free;
  end;
end;

procedure TAtlasMemoryTimelineTests.CsvWithMarks;
var
  mTimeline: TAtlasMemoryTimeline;
  mLines: TArray<string>;
begin
  mTimeline := Leaking(2);
  try
    mTimeline.AddMark(500, TAtlasMemoryMarkKind.Stop, 'Halt 1');
    mTimeline.AddMark(900, TAtlasMemoryMarkKind.Custom, 'Klick, zehnmal');
    mLines := mTimeline.ToCsv.Split([sLineBreak]);
    Assert.AreEqual('seconds,private_bytes,working_set,handles,gdi_objects,user_objects,marks', mLines[0]);
    Assert.AreEqual('0.000,0,0,100,10,5,', mLines[1]);
    Assert.AreEqual('1.000,1048576,2097152,103,10,5,"Halt 1 / Klick, zehnmal"', mLines[2]);
    Assert.AreEqual('2.000,2097152,4194304,106,10,5,', mLines[3]);
  finally
    mTimeline.Free;
  end;
end;

procedure TAtlasMemoryTimelineTests.FormatsValues;
var
  mFormat: TFormatSettings;
begin
  mFormat := TFormatSettings.Invariant;
  Assert.AreEqual('512 B', TAtlasMemoryFormat.Bytes(512, mFormat));
  Assert.AreEqual('1.5 KB', TAtlasMemoryFormat.Bytes(1536, mFormat));
  Assert.AreEqual('38.0 MB', TAtlasMemoryFormat.Bytes(Int64(38) * 1024 * 1024, mFormat));
  Assert.AreEqual('+38.0 MB', TAtlasMemoryFormat.Signed(TAtlasMemorySeries.PrivateBytes, Int64(38) * 1024 * 1024,
    mFormat));
  Assert.AreEqual('-2.0 GB', TAtlasMemoryFormat.Signed(TAtlasMemorySeries.WorkingSet, -Int64(2) * 1024 * 1024 * 1024,
    mFormat));
  Assert.AreEqual('+120', TAtlasMemoryFormat.Signed(TAtlasMemorySeries.Handles, 120, mFormat));
  Assert.AreEqual('-3', TAtlasMemoryFormat.Signed(TAtlasMemorySeries.GdiObjects, -3, mFormat));
  Assert.AreEqual('+0', TAtlasMemoryFormat.Signed(TAtlasMemorySeries.UserObjects, 0, mFormat));
end;

procedure TAtlasMemoryTimelineTests.ScaleMapsBothWays;
var
  mScale: TAtlasMemoryChartScale;
begin
  mScale := TAtlasMemoryChartScale.Make(10000, 20000, 200, 101, 51);
  Assert.AreEqual(0, mScale.XOf(10000));
  Assert.AreEqual(50, mScale.XOf(15000));
  Assert.AreEqual(100, mScale.XOf(20000));
  Assert.AreEqual(Int64(15000), mScale.AtOf(50));
  Assert.AreEqual(Int64(20000), mScale.AtOf(500), 'außerhalb begrenzt');
  Assert.AreEqual(50, mScale.YOf(0));
  Assert.AreEqual(25, mScale.YOf(100));
  Assert.AreEqual(0, mScale.YOf(300), 'über der Obergrenze oben');
  mScale := TAtlasMemoryChartScale.Make(0, 0, 0, 0, 0);
  Assert.AreEqual(0, mScale.XOf(0), 'leere Fläche ohne Division durch null');
end;

procedure TAtlasMemoryTimelineTests.NiceMaxRoundsUp;
begin
  Assert.AreEqual(Int64(1), TAtlasMemoryChartScale.NiceMax(0));
  Assert.AreEqual(Int64(5), TAtlasMemoryChartScale.NiceMax(3));
  Assert.AreEqual(Int64(200), TAtlasMemoryChartScale.NiceMax(120));
  Assert.AreEqual(Int64(500), TAtlasMemoryChartScale.NiceMax(500));
  Assert.AreEqual(Int64(100000000), TAtlasMemoryChartScale.NiceMax(63000000));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasMemoryTimelineTests);

end.
