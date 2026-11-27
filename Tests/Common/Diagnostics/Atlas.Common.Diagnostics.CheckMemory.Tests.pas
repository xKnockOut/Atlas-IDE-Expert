unit Atlas.Common.Diagnostics.CheckMemory.Tests;

// Speicher eines Laufs von --check --timings (#1480): Werte zu festen
// Zeitpunkten mit vorgegebener Messung. Zwei Projekte, deren Index
// nacheinander fertig wird: bereit beim Zielprojekt, Gruppe und Ende erst
// nach dem zweiten, Gipfel auch aus dem Hintergrund.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCheckMemoryTests = class
  public
    [Test]
    procedure WithoutMeasuringAllMinusOne;
    [Test]
    procedure SecondProjectFinishesAfterTarget;
    [Test]
    procedure OtherProjectFinishesBeforeTarget;
    [Test]
    procedure BackgroundFindsPeak;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  Atlas.Common.Diagnostics.CheckMemory;

type
  /// <summary>Vorgegebener Heap; die Messung liest Bytes.</summary>
  TFakeHeap = class
  private
    FBytes: Int64;
  public
    property Bytes: Int64 read FBytes write FBytes;
  end;

/// <summary>Messung über AHeap; eigene Routine, damit die anonyme Methode nur AHeap einfängt.</summary>
function MeasureOf(AHeap: TFakeHeap): TCheckMemoryMeasure;
begin
  Result :=
    function: Int64
    begin
      Result := AHeap.Bytes;
    end;
end;

{ TCheckMemoryTests }

procedure TCheckMemoryTests.WithoutMeasuringAllMinusOne;
var
  mHeap: TFakeHeap;
  mTrack: TCheckMemoryTrack;
begin
  mTrack := nil;
  mHeap := TFakeHeap.Create;
  try
    mTrack := TCheckMemoryTrack.Create(MeasureOf(mHeap));
    Assert.AreEqual<Int64>(-1, mTrack.ReadyBytes);
    Assert.AreEqual<Int64>(-1, mTrack.GroupBytes);
    Assert.AreEqual<Int64>(-1, mTrack.PeakBytes);
    Assert.AreEqual<Int64>(-1, mTrack.EndBytes);
  finally
    mTrack.Free;
    mHeap.Free;
  end;
end;

procedure TCheckMemoryTests.SecondProjectFinishesAfterTarget;
var
  mHeap: TFakeHeap;
  mTrack: TCheckMemoryTrack;
begin
  mTrack := nil;
  mHeap := TFakeHeap.Create;
  try
    mTrack := TCheckMemoryTrack.Create(MeasureOf(mHeap));
    mHeap.Bytes := 100;
    mTrack.IndexFinished(True);
    mHeap.Bytes := 300;
    mTrack.IndexFinished(False);
    // Ein erneuter Aufbau des Zielprojekts ändert den Wert bei bereit nicht.
    mTrack.IndexFinished(True);
    mTrack.MarkGroup;
    mHeap.Bytes := 250;
    mTrack.Finish;
    mHeap.Bytes := 50;
    mTrack.Finish;
    Assert.AreEqual<Int64>(100, mTrack.ReadyBytes);
    Assert.AreEqual<Int64>(300, mTrack.GroupBytes);
    Assert.AreEqual<Int64>(300, mTrack.PeakBytes);
    Assert.AreEqual<Int64>(250, mTrack.EndBytes);
  finally
    mTrack.Free;
    mHeap.Free;
  end;
end;

procedure TCheckMemoryTests.OtherProjectFinishesBeforeTarget;
var
  mHeap: TFakeHeap;
  mTrack: TCheckMemoryTrack;
begin
  mTrack := nil;
  mHeap := TFakeHeap.Create;
  try
    mTrack := TCheckMemoryTrack.Create(MeasureOf(mHeap));
    mHeap.Bytes := 400;
    mTrack.IndexFinished(False);
    mHeap.Bytes := 200;
    mTrack.IndexFinished(True);
    mTrack.MarkGroup;
    Assert.AreEqual<Int64>(200, mTrack.ReadyBytes);
    Assert.AreEqual<Int64>(200, mTrack.GroupBytes);
    Assert.AreEqual<Int64>(400, mTrack.PeakBytes);
    Assert.AreEqual<Int64>(-1, mTrack.EndBytes);
  finally
    mTrack.Free;
    mHeap.Free;
  end;
end;

procedure TCheckMemoryTests.BackgroundFindsPeak;
const
  cWaitMs = 5000;
var
  mHeap: TFakeHeap;
  mTrack: TCheckMemoryTrack;
  mWatch: TStopwatch;
begin
  mTrack := nil;
  mHeap := TFakeHeap.Create;
  try
    mTrack := TCheckMemoryTrack.Create(MeasureOf(mHeap));
    mHeap.Bytes := 900;
    mTrack.StartSampling;
    mWatch := TStopwatch.StartNew;
    while (mTrack.PeakBytes < 900) and (mWatch.ElapsedMilliseconds < cWaitMs) do
    begin
      TThread.Sleep(TCheckMemoryTrack.cSampleMs);
    end;
    mHeap.Bytes := 10;
    mTrack.Finish;
    Assert.AreEqual<Int64>(900, mTrack.PeakBytes);
    Assert.AreEqual<Int64>(10, mTrack.EndBytes);
    Assert.AreEqual<Int64>(-1, mTrack.ReadyBytes);
  finally
    mTrack.Free;
    mHeap.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCheckMemoryTests);

end.
