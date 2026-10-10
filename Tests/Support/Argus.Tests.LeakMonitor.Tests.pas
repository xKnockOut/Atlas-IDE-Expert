unit Argus.Tests.LeakMonitor.Tests;

// Prüft die Speicherleck-Überwachung selbst und spielt die
// Protokollaufzeichnungen im Dauerlauf ab.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLeakMonitorTests = class
  public
    [Test]
    procedure DetectsDeliberateLeak;
    [Test]
    procedure BalancedAllocationIsNoLeak;
    [Test]
    procedure NegativeBalanceIsNoLeak;
    [Test]
    procedure FreeOnOtherThreadIsNoLeak;
    [Test]
    procedure ReportNamesThreads;
    [Test]
    [IgnoreMemoryLeaks]
    procedure ReplayDoesNotGrowMemory;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  Argus.Common.Lsp.ProtocolReplay,
  Argus.Tests.LeakMonitor;

const
  // Anzahl der Durchläufe aller Aufzeichnungen im Dauerlauf.
  ReplayRounds = 500;
  // Toleranz für Schwankungen des Speichermanagers.
  AllowedGrowth = 64 * 1024;

procedure TLeakMonitorTests.DetectsDeliberateLeak;
var
  Monitor: IMemoryLeakMonitor;
  Leak: TObject;
begin
  Monitor := TLeakMonitor.Create;
  Monitor.PreTest;
  // Absichtliches Leck: wird erst nach der Messung freigegeben.
  Leak := TStringBuilder.Create(1024);
  Monitor.PostTest;
  Leak.Free;
  Assert.IsTrue(Monitor.TestMemoryAllocated > 0, 'Leck nicht erkannt');
end;

procedure TLeakMonitorTests.BalancedAllocationIsNoLeak;
var
  Monitor: IMemoryLeakMonitor;
  Temp: TObject;
begin
  Monitor := TLeakMonitor.Create;
  Monitor.PreTest;
  Temp := TStringBuilder.Create(1024);
  Temp.Free;
  Monitor.PostTest;
  Assert.AreEqual(Int64(0), Monitor.TestMemoryAllocated);
end;

procedure TLeakMonitorTests.NegativeBalanceIsNoLeak;
var
  Monitor: IMemoryLeakMonitor;
  Old: TObject;
begin
  // Freigaben älteren Speichers (z. B. durch Threads früherer Tests) sind kein Leck.
  Monitor := TLeakMonitor.Create;
  Old := TStringBuilder.Create(1024);
  Monitor.PreTest;
  Old.Free;
  Monitor.PostTest;
  Assert.AreEqual(Int64(0), Monitor.TestMemoryAllocated);
end;

procedure TLeakMonitorTests.FreeOnOtherThreadIsNoLeak;
var
  Monitor: IMemoryLeakMonitor;
  Shared: TObject;
  Worker: TThread;
begin
  // Ein Thread des Tests gibt Speicher frei, während der Test schon endet: Der
  // Monitor wartet die Freigabe ab, statt ein Leck zu melden.
  Monitor := TLeakMonitor.Create;
  Worker := TThread.CreateAnonymousThread(
    procedure
    begin
      FreeAndNil(Shared);
    end);
  Worker.FreeOnTerminate := False;
  try
    Monitor.PreTest;
    Shared := TStringBuilder.Create(1024);
    Worker.Start;
    Monitor.PostTest;
    Worker.WaitFor;
  finally
    Worker.Free;
  end;
  Assert.AreEqual(Int64(0), Monitor.TestMemoryAllocated);
end;

procedure TLeakMonitorTests.ReportNamesThreads;
var
  Monitor: IMemoryLeakMonitor;
  Report: IMemoryLeakMonitor2;
begin
  Monitor := TLeakMonitor.Create;
  Monitor.PreTest;
  Monitor.PostTest;
  Assert.IsTrue(Supports(Monitor, IMemoryLeakMonitor2, Report));
  Assert.Contains(Report.GetReport, 'Threads am Anfang');
  Assert.IsTrue(ProcessThreadCount > 0);
end;

procedure TLeakMonitorTests.ReplayDoesNotGrowMemory;
var
  Recordings: TObjectList<TJSONObject>;
  FileName: string;
  Value: TJSONValue;

  procedure ReplayAll;
  var
    Recording: TJSONObject;
    Replay: TProtocolReplay;
  begin
    for Recording in Recordings do
    begin
      Replay := TProtocolReplay.Create;
      try
        Replay.Run(Recording);
      finally
        Replay.Free;
      end;
    end;
  end;

var
  Before: Int64;
  Pass: Integer;
begin
  Recordings := TObjectList<TJSONObject>.Create(True);
  try
    for FileName in TDirectory.GetFiles(TProtocolReplay.DataDirectory, '*.json') do
    begin
      Value := TJSONObject.ParseJSONValue(TFile.ReadAllText(FileName, TEncoding.UTF8));
      if Value is TJSONObject then
        Recordings.Add(TJSONObject(Value))
      else
        Value.Free;
    end;
    Assert.IsTrue(Recordings.Count > 0, 'Keine Aufzeichnungen gefunden');

    // Aufwärmrunde füllt Caches, die bewusst bestehen bleiben.
    ReplayAll;
    Before := AllocatedBytes;
    for Pass := 1 to ReplayRounds do
      ReplayAll;
    Assert.IsTrue(AllocatedBytes - Before <= AllowedGrowth,
      Format('Speicher nach %d Durchläufen um %d Bytes gewachsen',
        [ReplayRounds, AllocatedBytes - Before]));
  finally
    Recordings.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLeakMonitorTests);

end.
