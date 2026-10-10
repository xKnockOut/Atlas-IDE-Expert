unit Argus.Core.Diagnostics.Hangs.Tests;

// Tests für den Einfrier-Wächter (#501), Teil ohne Windows.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusHangTests = class
  public
    [Test]
    procedure BelowThresholdWritesNothing;
    [Test]
    procedure ReportNamesArgusActionAndCountsSession;
    [Test]
    procedure ActivityScopesNest;
    [Test]
    procedure StackScanMapsAddressesToModules;
  end;

implementation

uses
  System.SysUtils,
  Argus.Core.Diagnostics.Hangs;

function MakeHang(ADurationMs: Int64; const AActivity: string): TArgusHang;
begin
  Result := Default(TArgusHang);
  Result.DurationMs := ADurationMs;
  Result.At := EncodeTime(10, 15, 0, 0);
  Result.Activity := AActivity;
end;

procedure TArgusHangTests.BelowThresholdWritesNothing;
var
  Monitor: TArgusHangMonitor;
begin
  Monitor := TArgusHangMonitor.Create(500);
  try
    Assert.AreEqual('', Monitor.Finish(MakeHang(499, '')));
    Assert.AreEqual(0, Monitor.Count);
  finally
    Monitor.Free;
  end;
end;

procedure TArgusHangTests.ReportNamesArgusActionAndCountsSession;
var
  Monitor: TArgusHangMonitor;
  Hang: TArgusHang;
  Text: string;
begin
  Monitor := TArgusHangMonitor.Create(500);
  try
    Hang := MakeHang(730, 'Vervollständigung filtern');
    Hang.Window := 'Unit1.pas';
    Hang.Frames := ['Argus.IDE.Expert.bpl+1A2B', 'coreide370.bpl+FF'];
    Text := Monitor.Finish(Hang);
    Assert.Contains(Text, 'Hänger 730 ms um 10:15:00');
    Assert.Contains(Text, 'Argus: Vervollständigung filtern, 730 ms');
    Assert.Contains(Text, 'Fenster: Unit1.pas');
    Assert.Contains(Text, 'Argus.IDE.Expert.bpl+1A2B');
    // Ohne Aktion, aber Argus im Stapel: zählt als beteiligt.
    Hang := MakeHang(1500, '');
    Hang.Frames := ['Argus.IDE.Expert.bpl+10'];
    Assert.Contains(Monitor.Finish(Hang), 'Argus im Aufrufstapel');
    Monitor.Finish(MakeHang(600, ''));
    Assert.AreEqual('Sitzung: 3 Hänger, längster 1500 ms, 2 mit Argus', Monitor.Summary);
  finally
    Monitor.Free;
  end;
end;

procedure TArgusHangTests.ActivityScopesNest;
var
  Outer, Inner: IInterface;
begin
  Assert.AreEqual('', TArgusActivity.Current);
  Outer := TArgusActivity.Scope('Vervollständigung');
  Inner := TArgusActivity.Scope('Filtern');
  Assert.AreEqual('Filtern', TArgusActivity.Current);
  Inner := nil;
  Assert.AreEqual('Vervollständigung', TArgusActivity.Current);
  Outer := nil;
  Assert.AreEqual('', TArgusActivity.Current);
end;

procedure TArgusHangTests.StackScanMapsAddressesToModules;
var
  Modules: TArray<TArgusModuleRange>;
  Frames: TArray<string>;
begin
  SetLength(Modules, 2);
  Modules[0].Name := 'bds.exe';
  Modules[0].Base := $400000;
  Modules[0].Size := $10000;
  Modules[1].Name := 'Argus.IDE.Expert.bpl';
  Modules[1].Base := $50000000;
  Modules[1].Size := $100000;
  // Daten ohne Modul fallen weg, gleiche Rahmen direkt hintereinander nur einmal.
  Frames := TArgusStackScan.Frames([$401234, $12, $50000100, $50000100, $400010], Modules);
  Assert.AreEqual('bds.exe+1234|Argus.IDE.Expert.bpl+100|bds.exe+10', string.Join('|', Frames));
  Assert.AreEqual(1, Integer(Length(TArgusStackScan.Frames([$401234, $401235, $401236], Modules, 1))));
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusHangTests);

end.