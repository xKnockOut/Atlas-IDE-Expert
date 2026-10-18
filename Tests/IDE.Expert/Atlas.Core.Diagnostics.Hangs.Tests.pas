unit Atlas.Core.Diagnostics.Hangs.Tests;

// Tests für den Einfrier-Wächter (#501), Teil ohne Windows.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasHangTests = class
  public
    [Test]
    procedure BelowThresholdWritesNothing;
    [Test]
    procedure ReportNamesAtlasActionAndCountsSession;
    [Test]
    procedure ActivityScopesNest;
    [Test]
    procedure StackScanMapsAddressesToModules;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Hangs;

function MakeHang(ADurationMs: Int64; const AActivity: string): TAtlasHang;
begin
  Result := Default(TAtlasHang);
  Result.DurationMs := ADurationMs;
  Result.At := EncodeTime(10, 15, 0, 0);
  Result.Activity := AActivity;
end;

procedure TAtlasHangTests.BelowThresholdWritesNothing;
var
  Monitor: TAtlasHangMonitor;
begin
  Monitor := TAtlasHangMonitor.Create(500);
  try
    Assert.AreEqual('', Monitor.Finish(MakeHang(499, '')));
    Assert.AreEqual(0, Integer(Monitor.Count));
  finally
    Monitor.Free;
  end;
end;

procedure TAtlasHangTests.ReportNamesAtlasActionAndCountsSession;
var
  Monitor: TAtlasHangMonitor;
  Hang: TAtlasHang;
  Text: string;
begin
  Monitor := TAtlasHangMonitor.Create(500);
  try
    Hang := MakeHang(730, 'Vervollständigung filtern');
    Hang.Window := 'Unit1.pas';
    Hang.Frames := ['Atlas.IDE.Expert.bpl+1A2B', 'coreide370.bpl+FF'];
    Text := Monitor.Finish(Hang);
    Assert.Contains(Text, 'Hänger 730 ms um 10:15:00');
    Assert.Contains(Text, 'Atlas: Vervollständigung filtern, 730 ms');
    Assert.Contains(Text, 'Fenster: Unit1.pas');
    Assert.Contains(Text, 'Atlas.IDE.Expert.bpl+1A2B');
    // Ohne Aktion, aber Atlas im Stapel: zählt als beteiligt.
    Hang := MakeHang(1500, '');
    Hang.Frames := ['Atlas.IDE.Expert.bpl+10'];
    Assert.Contains(Monitor.Finish(Hang), 'Atlas im Aufrufstapel');
    Monitor.Finish(MakeHang(600, ''));
    Assert.AreEqual('Sitzung: 3 Hänger, längster 1500 ms, 2 mit Atlas', Monitor.Summary);
  finally
    Monitor.Free;
  end;
end;

procedure TAtlasHangTests.ActivityScopesNest;
var
  Outer, Inner: IInterface;
begin
  Assert.AreEqual('', TAtlasActivity.Current);
  Outer := TAtlasActivity.Scope('Vervollständigung');
  Inner := TAtlasActivity.Scope('Filtern');
  Assert.AreEqual('Filtern', TAtlasActivity.Current);
  Inner := nil;
  Assert.AreEqual('Vervollständigung', TAtlasActivity.Current);
  Outer := nil;
  Assert.AreEqual('', TAtlasActivity.Current);
end;

procedure TAtlasHangTests.StackScanMapsAddressesToModules;
var
  Modules: TArray<TAtlasModuleRange>;
  Frames: TArray<string>;
begin
  SetLength(Modules, 2);
  Modules[0].Name := 'bds.exe';
  Modules[0].Base := $400000;
  Modules[0].Size := $10000;
  Modules[1].Name := 'Atlas.IDE.Expert.bpl';
  Modules[1].Base := $50000000;
  Modules[1].Size := $100000;
  // Daten ohne Modul fallen weg, gleiche Rahmen direkt hintereinander nur einmal.
  Frames := TAtlasStackScan.Frames([$401234, $12, $50000100, $50000100, $400010], Modules);
  Assert.AreEqual('bds.exe+1234|Atlas.IDE.Expert.bpl+100|bds.exe+10', string.Join('|', Frames));
  Assert.AreEqual(1, Integer(Length(TAtlasStackScan.Frames([$401234, $401235, $401236], Modules, 1))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHangTests);

end.