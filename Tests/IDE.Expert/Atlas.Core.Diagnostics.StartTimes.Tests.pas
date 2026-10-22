unit Atlas.Core.Diagnostics.StartTimes.Tests;

// Startanteile (Bericht N4): Teile addieren, messen auch bei Ausnahmen, die
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
  Tick: Int64;
begin
  Tick := 0;
  Result :=
    function: Int64
    begin
      Inc(Tick, AStepMs);
      Result := Tick;
    end;
end;

procedure TAtlasStartTimesTests.AddsUpPartsByName;
var
  Times: TAtlasStartTimes;
  Parts: TArray<TAtlasStartPart>;
begin
  Times := TAtlasStartTimes.Create;
  try
    Times.Add('Manager', 100);
    Times.Add('Forms', 40);
    Times.Add('manager', 50);
    Assert.AreEqual(Int64(190), Times.Total);
    Parts := Times.Slowest(10);
    Assert.AreEqual(2, Integer(Length(Parts)), 'gleicher Name ohne Rücksicht auf Groß- und Kleinschreibung');
    Assert.AreEqual('Manager', Parts[0].Name);
    Assert.AreEqual(Int64(150), Parts[0].Ms);
  finally
    Times.Free;
  end;
end;

procedure TAtlasStartTimesTests.NegativeDurationCountsAsZero;
var
  Times: TAtlasStartTimes;
begin
  Times := TAtlasStartTimes.Create;
  try
    // Die Uhr kann zwischen zwei Lesungen nicht rückwärts laufen; eine Differenz aus zwei Quellen schon.
    Times.Add('Anmeldung', -5);
    Times.Add('Manager', 30);
    Assert.AreEqual(Int64(30), Times.Total);
  finally
    Times.Free;
  end;
end;

procedure TAtlasStartTimesTests.MeasuresEvenWhenPartRaises;
var
  Times: TAtlasStartTimes;
  Ran: Boolean;
begin
  Times := TAtlasStartTimes.Create(SteppingClock(30));
  try
    Ran := False;
    Times.Measure('Compile',
      procedure
      begin
        Ran := True;
      end);
    Assert.IsTrue(Ran);
    Assert.AreEqual(Int64(30), Times.Total, 'eine Lesung vor, eine nach dem Teil');
    Assert.WillRaise(
      procedure
      begin
        Times.Measure('Forms',
          procedure
          begin
            raise EArgumentException.Create('Start fehlgeschlagen');
          end);
      end, EArgumentException);
    Assert.AreEqual(Int64(60), Times.Total, 'auch ein fehlgeschlagener Start hat Zeit gekostet');
  finally
    Times.Free;
  end;
end;

procedure TAtlasStartTimesTests.SlowestAreSortedAndCut;
var
  Times: TAtlasStartTimes;
  Parts: TArray<TAtlasStartPart>;
begin
  Times := TAtlasStartTimes.Create;
  try
    Times.Add('Klein', TAtlasStartTimes.MinPartMs - 1);
    Times.Add('Forms', 200);
    Times.Add('Manager', 300);
    Times.Add('Palette', 200);
    Times.Add('Aktion Bauen beim Öffnen', 900);
    Parts := Times.Slowest(3);
    Assert.AreEqual(3, Integer(Length(Parts)));
    Assert.AreEqual('Aktion Bauen beim Öffnen', Parts[0].Name);
    Assert.AreEqual('Manager', Parts[1].Name);
    Assert.AreEqual('Forms', Parts[2].Name, 'gleich lang: in der Reihenfolge des ersten Eintrags');
    Assert.AreEqual('Aktion Bauen beim Öffnen 900 ms, Manager 300 ms, Forms 200 ms, Palette 200 ms',
      Times.SlowestText, 'ohne Teile unter MinPartMs');
    Assert.AreEqual(0, Integer(Length(Times.Slowest(0))));
  finally
    Times.Free;
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
  Times: TAtlasStartTimes;
begin
  Times := TAtlasStartTimes.Create;
  try
    Times.Add('Manager', 300);
    Times.Add('Forms', 150);
    Times.Add('Klein', 3);
    Assert.AreEqual('Start: 45000 ms bis zur freien Nachrichtenschleife (länger als 30000 ms), davon Atlas 453 ms: ' +
      'Manager 300 ms, Forms 150 ms', Times.LogLine(45000, 30000));
    Assert.AreEqual('Start: 8000 ms bis zur freien Nachrichtenschleife, davon Atlas 453 ms: Manager 300 ms, ' +
      'Forms 150 ms', Times.LogLine(8000, 30000));
  finally
    Times.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStartTimesTests);

end.
