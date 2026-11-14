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
    /// <summary>Der künstliche Hänger läuft unter seinem Namen und meldet sich danach ab.</summary>
    [Test]
    procedure HangTestRunsAsNamedActivity;
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
  mMonitor: TAtlasHangMonitor;
begin
  mMonitor := TAtlasHangMonitor.Create(500);
  try
    Assert.AreEqual('', mMonitor.Finish(MakeHang(499, '')));
    Assert.AreEqual(0, Integer(mMonitor.Count));
  finally
    mMonitor.Free;
  end;
end;

procedure TAtlasHangTests.ReportNamesAtlasActionAndCountsSession;
var
  mMonitor: TAtlasHangMonitor;
  mHang: TAtlasHang;
  mText: string;
begin
  mMonitor := TAtlasHangMonitor.Create(500);
  try
    mHang := MakeHang(730, 'Vervollständigung filtern');
    mHang.Window := 'Unit1.pas';
    mHang.Frames := ['Atlas.IDE.Expert.bpl+1A2B', 'coreide370.bpl+FF'];
    mText := mMonitor.Finish(mHang);
    Assert.Contains(mText, 'Hänger 730 ms um 10:15:00');
    Assert.Contains(mText, 'Atlas: Vervollständigung filtern, 730 ms');
    Assert.Contains(mText, 'Fenster: Unit1.pas');
    Assert.Contains(mText, 'Atlas.IDE.Expert.bpl+1A2B');
    // Ohne Aktion, aber Atlas im Stapel: zählt als beteiligt.
    mHang := MakeHang(1500, '');
    mHang.Frames := ['Atlas.IDE.Expert.bpl+10'];
    Assert.Contains(mMonitor.Finish(mHang), 'Atlas im Aufrufstapel');
    mMonitor.Finish(MakeHang(600, ''));
    Assert.AreEqual('Sitzung: 3 Hänger, längster 1500 ms, 2 mit Atlas', mMonitor.Summary);
  finally
    mMonitor.Free;
  end;
end;

procedure TAtlasHangTests.ActivityScopesNest;
var
  mOuter, mInner: IInterface;
begin
  Assert.AreEqual('', TAtlasActivity.Current);
  mOuter := TAtlasActivity.Scope('Vervollständigung');
  mInner := TAtlasActivity.Scope('Filtern');
  Assert.AreEqual('Filtern', TAtlasActivity.Current);
  mInner := nil;
  Assert.AreEqual('Vervollständigung', TAtlasActivity.Current);
  mOuter := nil;
  Assert.AreEqual('', TAtlasActivity.Current);
end;

procedure TAtlasHangTests.ActivityTimesOutermostDuringStart;
var
  mTimes: TAtlasStartTimes;
  mClock: TFunc<Int64>;
  mTick: Int64;
  mOuter, mInner: IInterface;
  mParts: TArray<TAtlasStartPart>;
begin
  // Bis zur freien Nachrichtenschleife zählt jede äußerste Atlas-Aktion zu den Startanteilen.
  mTick := 0;
  mClock :=
    function: Int64
    begin
      Inc(mTick, 40);
      Result := mTick;
    end;
  mTimes := TAtlasStartTimes.Create(mClock);
  try
    TAtlasActivity.TimeInto(mTimes);
    try
      mOuter := TAtlasActivity.Scope('Bauen beim Öffnen');
      mInner := TAtlasActivity.Scope('Compilerprüfung');
      mInner := nil;
      mOuter := nil;
    finally
      TAtlasActivity.TimeInto(nil);
    end;
    mParts := mTimes.Slowest(10);
    Assert.AreEqual(1, Integer(Length(mParts)), 'die innere Aktion steckt in der äußeren');
    Assert.AreEqual('Aktion Bauen beim Öffnen', mParts[0].Name);
    Assert.AreEqual(Int64(40), mParts[0].Ms);
    // Nach TimeInto(nil) zählt nichts mehr.
    mOuter := TAtlasActivity.Scope('Symbolhinweis');
    mOuter := nil;
    Assert.AreEqual(Int64(40), mTimes.Total);
    Assert.AreEqual('', TAtlasActivity.Current);
  finally
    mTimes.Free;
  end;
end;

procedure TAtlasHangTests.HangTestRunsAsNamedActivity;
var
  mTimes: TAtlasStartTimes;
  mTick: Int64;
  mParts: TArray<TAtlasStartPart>;
begin
  mTick := 0;
  mTimes := TAtlasStartTimes.Create(
    function: Int64
    begin
      Inc(mTick, 40);
      Result := mTick;
    end);
  try
    TAtlasActivity.TimeInto(mTimes);
    try
      TAtlasActivity.HangTest(1);
    finally
      TAtlasActivity.TimeInto(nil);
    end;
    mParts := mTimes.Slowest(10);
    Assert.AreEqual(1, Integer(Length(mParts)));
    Assert.AreEqual('Aktion ' + TAtlasActivity.cHangTestName, mParts[0].Name);
    Assert.AreEqual('', TAtlasActivity.Current);
  finally
    mTimes.Free;
  end;
end;

procedure TAtlasHangTests.RunningNamesGuardFeature;
var
  mSeen: TArray<string>;
  mOther: TThread;
  mOtherName: string;
begin
  mSeen := nil;
  Assert.AreEqual('', TAtlasActivity.Running);
  TAtlasGuard.Run(TAtlasFeature.EditorToolbar,
    procedure
    var
      Scope: IInterface;
    begin
      mSeen := mSeen + [TAtlasActivity.Running];
      TAtlasGuard.Run(TAtlasFeature.Breadcrumbs,
        procedure
        begin
          mSeen := mSeen + [TAtlasActivity.Running];
        end);
      mSeen := mSeen + [TAtlasActivity.Running];
      TAtlasGuard.RunIde(
        procedure
        begin
          mSeen := mSeen + [TAtlasActivity.Running];
        end);
      Scope := TAtlasActivity.Scope('Tastenkarte');
      mSeen := mSeen + [TAtlasActivity.Running];
      Scope := nil;
      raise EAbort.Create('Test');
    end);
  Assert.AreEqual(TAtlasGuard.FeatureName(TAtlasFeature.EditorToolbar) + '|' +
    TAtlasGuard.FeatureName(TAtlasFeature.Breadcrumbs) + '|' + TAtlasGuard.FeatureName(TAtlasFeature.EditorToolbar) +
    '||Tastenkarte', string.Join('|', mSeen));
  Assert.AreEqual('', TAtlasActivity.Running, 'nach der Exception leer');
  // Aufrufe aus anderen Threads legen nichts auf.
  mOtherName := 'unberührt';
  mOther := TThread.CreateAnonymousThread(
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Outline,
        procedure
        begin
          mOtherName := TAtlasGuard.CurrentFeatureName;
        end);
    end);
  mOther.FreeOnTerminate := False;
  try
    mOther.Start;
    mOther.WaitFor;
  finally
    mOther.Free;
  end;
  Assert.AreEqual('', mOtherName);
  mSeen := nil;
  mOtherName := '';
end;

procedure TAtlasHangTests.AtlasFrameBelowShownFramesCounts;
var
  mModules: TArray<TAtlasModuleRange>;
  mAddresses: TArray<UInt64>;
  mIndex: Integer;
  mMonitor: TAtlasHangMonitor;
  mHang: TAtlasHang;
  mText: string;
begin
  SetLength(mModules, 2);
  mModules[0].Name := 'coreide370.bpl';
  mModules[0].Base := $400000;
  mModules[0].Size := $100000;
  mModules[1].Name := 'Atlas.IDE.Welcome370.bpl';
  mModules[1].Base := $50000000;
  mModules[1].Size := $100000;
  // 60 Rahmen der IDE (Projekt laden), darunter der Klick der Willkommensseite.
  mAddresses := nil;
  for mIndex := 1 to 60 do
  begin
    mAddresses := mAddresses + [UInt64($400000 + mIndex * 16)];
  end;
  mAddresses := mAddresses + [UInt64($50000200), UInt64($50000300)];
  mHang := MakeHang(13900, '');
  mHang.Frames := TAtlasStackScan.Frames(mAddresses, mModules);
  mHang.AtlasFrame := TAtlasStackScan.FirstIn(mAddresses, mModules, 'Atlas');
  Assert.AreEqual(24, Integer(Length(mHang.Frames)));
  Assert.AreEqual('Atlas.IDE.Welcome370.bpl+200', mHang.AtlasFrame);
  Assert.IsTrue(TAtlasHangMonitor.InvolvesAtlas(mHang));
  mMonitor := TAtlasHangMonitor.Create(500);
  try
    mText := mMonitor.Finish(mHang);
    Assert.Contains(mText, 'Atlas im Aufrufstapel');
    Assert.Contains(mText, '… Atlas.IDE.Welcome370.bpl+200');
  finally
    mMonitor.Free;
  end;
  // Ohne Atlas-Modul im Abzug: leer.
  Assert.AreEqual('', TAtlasStackScan.FirstIn([UInt64($400010)], mModules, 'Atlas'));
  Assert.AreEqual('', TAtlasStackScan.FirstIn(mAddresses, [mModules[0]], 'Atlas'));
end;

procedure TAtlasHangTests.StackScanMapsAddressesToModules;
var
  mModules: TArray<TAtlasModuleRange>;
  mFrames: TArray<string>;
begin
  SetLength(mModules, 2);
  mModules[0].Name := 'bds.exe';
  mModules[0].Base := $400000;
  mModules[0].Size := $10000;
  mModules[1].Name := 'Atlas.IDE.Expert.bpl';
  mModules[1].Base := $50000000;
  mModules[1].Size := $100000;
  // Daten ohne Modul fallen weg, gleiche Rahmen direkt hintereinander nur einmal.
  mFrames := TAtlasStackScan.Frames([$401234, $12, $50000100, $50000100, $400010], mModules);
  Assert.AreEqual('bds.exe+1234|Atlas.IDE.Expert.bpl+100|bds.exe+10', string.Join('|', mFrames));
  Assert.AreEqual(1, Integer(Length(TAtlasStackScan.Frames([$401234, $401235, $401236], mModules, 1))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasHangTests);

end.