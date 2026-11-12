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
    procedure ActivityTimesOutermostDuringStart;
    /// <summary>Ohne Aktion nennt der Wächter die innerste Funktion aus TAtlasGuard.Run; RunIde ist keine
    /// Funktion von Atlas; nach einer Exception ist der Stapel wieder leer.</summary>
    [Test]
    procedure RunningNamesGuardFeature;
    [Test]
    procedure StackScanMapsAddressesToModules;
    /// <summary>Ein Atlas-Rahmen unterhalb der 24 angezeigten zählt als beteiligt und steht im Bericht.</summary>
    [Test]
    procedure AtlasFrameBelowShownFramesCounts;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.StartTimes,
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

procedure TAtlasHangTests.ActivityTimesOutermostDuringStart;
var
  Times: TAtlasStartTimes;
  Clock: TFunc<Int64>;
  Tick: Int64;
  Outer, Inner: IInterface;
  Parts: TArray<TAtlasStartPart>;
begin
  // Bis zur freien Nachrichtenschleife zählt jede äußerste Atlas-Aktion zu den Startanteilen.
  Tick := 0;
  Clock :=
    function: Int64
    begin
      Inc(Tick, 40);
      Result := Tick;
    end;
  Times := TAtlasStartTimes.Create(Clock);
  try
    TAtlasActivity.TimeInto(Times);
    try
      Outer := TAtlasActivity.Scope('Bauen beim Öffnen');
      Inner := TAtlasActivity.Scope('Compilerprüfung');
      Inner := nil;
      Outer := nil;
    finally
      TAtlasActivity.TimeInto(nil);
    end;
    Parts := Times.Slowest(10);
    Assert.AreEqual(1, Integer(Length(Parts)), 'die innere Aktion steckt in der äußeren');
    Assert.AreEqual('Aktion Bauen beim Öffnen', Parts[0].Name);
    Assert.AreEqual(Int64(40), Parts[0].Ms);
    // Nach TimeInto(nil) zählt nichts mehr.
    Outer := TAtlasActivity.Scope('Symbolhinweis');
    Outer := nil;
    Assert.AreEqual(Int64(40), Times.Total);
    Assert.AreEqual('', TAtlasActivity.Current);
  finally
    Times.Free;
  end;
end;

procedure TAtlasHangTests.RunningNamesGuardFeature;
var
  Seen: TArray<string>;
  Other: TThread;
  OtherName: string;
begin
  Seen := nil;
  Assert.AreEqual('', TAtlasActivity.Running);
  TAtlasGuard.Run(TAtlasFeature.EditorToolbar,
    procedure
    var
      Scope: IInterface;
    begin
      Seen := Seen + [TAtlasActivity.Running];
      TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
        procedure
        begin
          Seen := Seen + [TAtlasActivity.Running];
        end);
      Seen := Seen + [TAtlasActivity.Running];
      TAtlasGuard.RunIde(
        procedure
        begin
          Seen := Seen + [TAtlasActivity.Running];
        end);
      Scope := TAtlasActivity.Scope('Tastenkarte');
      Seen := Seen + [TAtlasActivity.Running];
      Scope := nil;
      raise EAbort.Create('Test');
    end);
  Assert.AreEqual(TAtlasGuard.FeatureName(TAtlasFeature.EditorToolbar) + '|' +
    TAtlasGuard.FeatureName(TAtlasFeature.Breadcrumbs) + '|' + TAtlasGuard.FeatureName(TAtlasFeature.EditorToolbar) +
    '||Tastenkarte', string.Join('|', Seen));
  Assert.AreEqual('', TAtlasActivity.Running, 'nach der Exception leer');
  // Aufrufe aus anderen Threads legen nichts auf.
  OtherName := 'unberührt';
  Other := TThread.CreateAnonymousThread(
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Outline,
        procedure
        begin
          OtherName := TAtlasGuard.CurrentFeatureName;
        end);
    end);
  Other.FreeOnTerminate := False;
  try
    Other.Start;
    Other.WaitFor;
  finally
    Other.Free;
  end;
  Assert.AreEqual('', OtherName);
  Seen := nil;
  OtherName := '';
end;

procedure TAtlasHangTests.AtlasFrameBelowShownFramesCounts;
var
  Modules: TArray<TAtlasModuleRange>;
  Addresses: TArray<UInt64>;
  Index: Integer;
  Monitor: TAtlasHangMonitor;
  Hang: TAtlasHang;
  Text: string;
begin
  SetLength(Modules, 2);
  Modules[0].Name := 'coreide370.bpl';
  Modules[0].Base := $400000;
  Modules[0].Size := $100000;
  Modules[1].Name := 'Atlas.IDE.Welcome370.bpl';
  Modules[1].Base := $50000000;
  Modules[1].Size := $100000;
  // 60 Rahmen der IDE (Projekt laden), darunter der Klick der Willkommensseite.
  Addresses := nil;
  for Index := 1 to 60 do
  begin
    Addresses := Addresses + [UInt64($400000 + Index * 16)];
  end;
  Addresses := Addresses + [UInt64($50000200), UInt64($50000300)];
  Hang := MakeHang(13900, '');
  Hang.Frames := TAtlasStackScan.Frames(Addresses, Modules);
  Hang.AtlasFrame := TAtlasStackScan.FirstIn(Addresses, Modules, 'Atlas');
  Assert.AreEqual(24, Integer(Length(Hang.Frames)));
  Assert.AreEqual('Atlas.IDE.Welcome370.bpl+200', Hang.AtlasFrame);
  Assert.IsTrue(TAtlasHangMonitor.InvolvesAtlas(Hang));
  Monitor := TAtlasHangMonitor.Create(500);
  try
    Text := Monitor.Finish(Hang);
    Assert.Contains(Text, 'Atlas im Aufrufstapel');
    Assert.Contains(Text, '… Atlas.IDE.Welcome370.bpl+200');
  finally
    Monitor.Free;
  end;
  // Ohne Atlas-Modul im Abzug: leer.
  Assert.AreEqual('', TAtlasStackScan.FirstIn([UInt64($400010)], Modules, 'Atlas'));
  Assert.AreEqual('', TAtlasStackScan.FirstIn(Addresses, [Modules[0]], 'Atlas'));
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