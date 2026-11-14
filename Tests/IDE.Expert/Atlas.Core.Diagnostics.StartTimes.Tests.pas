unit Atlas.Core.Diagnostics.StartTimes.Tests;

// Startanteile: Teile addieren, messen auch bei Ausnahmen, die
// längsten nennen, langsamen Start erkennen und die Protokollzeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStartTimesTests = class
  public
    [Test]
    procedure AddsUpPartsByName;
    [Test]
    procedure NegativeDurationCountsAsZero;
    [Test]
    procedure MeasuresEvenWhenPartRaises;
    [Test]
    procedure SlowestAreSortedAndCut;
    [Test]
    procedure SlowStartNeedsLimit;
    [Test]
    procedure LogLineNamesAtlasShare;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.StartTimes;

/// <summary>Uhr, die bei jedem Ablesen um AStepMs weiterläuft.</summary>
function SteppingClock(AStepMs: Int64): TFunc<Int64>;
var
  mTick: Int64;
begin
  mTick := 0;
  Result :=
    function: Int64
    begin
      Inc(mTick, AStepMs);
      Result := mTick;
    end;
end;

procedure TAtlasStartTimesTests.AddsUpPartsByName;
var
  mTimes: TAtlasStartTimes;
  mParts: TArray<TAtlasStartPart>;
begin
  mTimes := TAtlasStartTimes.Create;
  try
    mTimes.Add('Manager', 100);
    mTimes.Add('Forms', 40);
    mTimes.Add('manager', 50);
    Assert.AreEqual(Int64(190), mTimes.Total);
    mParts := mTimes.Slowest(10);
    Assert.AreEqual(2, Integer(Length(mParts)), 'gleicher Name ohne Rücksicht auf Groß- und Kleinschreibung');
    Assert.AreEqual('Manager', mParts[0].Name);
    Assert.AreEqual(Int64(150), mParts[0].Ms);
  finally
    mTimes.Free;
  end;
end;

procedure TAtlasStartTimesTests.NegativeDurationCountsAsZero;
var
  mTimes: TAtlasStartTimes;
begin
  mTimes := TAtlasStartTimes.Create;
  try
    // Die Uhr kann zwischen zwei Lesungen nicht rückwärts laufen; eine Differenz aus zwei Quellen schon.
    mTimes.Add('Anmeldung', -5);
    mTimes.Add('Manager', 30);
    Assert.AreEqual(Int64(30), mTimes.Total);
  finally
    mTimes.Free;
  end;
end;

procedure TAtlasStartTimesTests.MeasuresEvenWhenPartRaises;
var
  mTimes: TAtlasStartTimes;
  mRan: Boolean;
begin
  mTimes := TAtlasStartTimes.Create(SteppingClock(30));
  try
    mRan := False;
    mTimes.Measure('Compile',
      procedure
      begin
        mRan := True;
      end);
    Assert.IsTrue(mRan);
    Assert.AreEqual(Int64(30), mTimes.Total, 'eine Lesung vor, eine nach dem Teil');
    Assert.WillRaise(
      procedure
      begin
        mTimes.Measure('Forms',
          procedure
          begin
            raise EArgumentException.Create('Start fehlgeschlagen');
          end);
      end, EArgumentException);
    Assert.AreEqual(Int64(60), mTimes.Total, 'auch ein fehlgeschlagener Start hat Zeit gekostet');
  finally
    mTimes.Free;
  end;
end;

procedure TAtlasStartTimesTests.SlowestAreSortedAndCut;
var
  mTimes: TAtlasStartTimes;
  mParts: TArray<TAtlasStartPart>;
begin
  mTimes := TAtlasStartTimes.Create;
  try
    mTimes.Add('Klein', TAtlasStartTimes.cMinPartMs - 1);
    mTimes.Add('Forms', 200);
    mTimes.Add('Manager', 300);
    mTimes.Add('Palette', 200);
    mTimes.Add('Aktion Bauen beim Öffnen', 900);
    mParts := mTimes.Slowest(3);
    Assert.AreEqual(3, Integer(Length(mParts)));
    Assert.AreEqual('Aktion Bauen beim Öffnen', mParts[0].Name);
    Assert.AreEqual('Manager', mParts[1].Name);
    Assert.AreEqual('Forms', mParts[2].Name, 'gleich lang: in der Reihenfolge des ersten Eintrags');
    Assert.AreEqual('Aktion Bauen beim Öffnen 900 ms, Manager 300 ms, Forms 200 ms, Palette 200 ms',
      mTimes.SlowestText, 'ohne Teile unter MinPartMs');
    Assert.AreEqual(0, Integer(Length(mTimes.Slowest(0))));
  finally
    mTimes.Free;
  end;
end;

procedure TAtlasStartTimesTests.SlowStartNeedsLimit;
begin
  Assert.IsTrue(TAtlasStartTimes.IsSlow(30001, 30000));
  Assert.IsFalse(TAtlasStartTimes.IsSlow(30000, 30000), 'genau das Limit ist nicht zu langsam');
  Assert.IsFalse(TAtlasStartTimes.IsSlow(500000, 0), 'ohne Limit nie');
end;

procedure TAtlasStartTimesTests.LogLineNamesAtlasShare;
var
  mTimes: TAtlasStartTimes;
begin
  mTimes := TAtlasStartTimes.Create;
  try
    mTimes.Add('Manager', 300);
    mTimes.Add('Forms', 150);
    mTimes.Add('Klein', 3);
    Assert.AreEqual('Start: 45000 ms bis zur freien Nachrichtenschleife (länger als 30000 ms), davon Atlas 453 ms: ' +
      'Manager 300 ms, Forms 150 ms', mTimes.LogLine(45000, 30000));
    Assert.AreEqual('Start: 8000 ms bis zur freien Nachrichtenschleife, davon Atlas 453 ms: Manager 300 ms, ' +
      'Forms 150 ms', mTimes.LogLine(8000, 30000));
  finally
    mTimes.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStartTimesTests);

end.
