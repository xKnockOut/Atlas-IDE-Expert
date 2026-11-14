unit Atlas.Core.Diagnostics.FeatureTable.Tests;

// Startreihenfolge, Abbau und Stufen der Feature-Tabelle;
// Startanteile je Teil; Modul-Schalter (#1454).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFeatureTableTests = class
  public
    [Test]
    procedure StartsInOrder;
    [Test]
    procedure StopsInReverseOnlyActive;
    [Test]
    procedure SkipsBelowMinLevel;
    [Test]
    procedure StartWantedIsIdempotent;
    [Test]
    procedure LaterWantedStartsOnSecondCall;
    [Test]
    procedure WantedSeesLevel;
    [Test]
    procedure StopAllContinuesAfterFailure;
    [Test]
    procedure TimesEachStartedPart;
    [Test]
    procedure ModuleOffSkipsItsParts;
    [Test]
    procedure StopOffModulesStopsOnlyThoseInReverse;
    [Test]
    procedure JoinUnknownPartRaises;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Diagnostics.StartTimes,
  Atlas.Core.Diagnostics.FeatureTable;

type
  /// <summary>Protokolliert Start und Stop; je Teil ein Schalter „läuft“.</summary>
  TProbe = class
  public
    Log: string;
    Active: array[0..3] of Boolean;
    procedure AddTo(ATable: TAtlasFeatureTable; AIndex: Integer; AMinLevel: TAtlasSafeLevel);
    procedure AddWantedTo(ATable: TAtlasFeatureTable; AIndex: Integer; const AWanted: TAtlasFeatureWanted);
  end;

procedure TProbe.AddTo(ATable: TAtlasFeatureTable; AIndex: Integer; AMinLevel: TAtlasSafeLevel);
begin
  AddWantedTo(ATable, AIndex,
    function(ALevel: TAtlasSafeLevel): Boolean
    begin
      Result := Ord(ALevel) <= Ord(AMinLevel);
    end);
end;

procedure TProbe.AddWantedTo(ATable: TAtlasFeatureTable; AIndex: Integer; const AWanted: TAtlasFeatureWanted);
var
  mName: string;
begin
  mName := Chr(Ord('A') + AIndex);
  ATable.AddWanted(mName, AWanted,
    function: Boolean
    begin
      Result := Active[AIndex];
    end,
    procedure
    begin
      Active[AIndex] := True;
      Log := Log + '+' + mName;
    end,
    procedure
    begin
      Active[AIndex] := False;
      Log := Log + '-' + mName;
    end);
end;

procedure TFeatureTableTests.StartsInOrder;
var
  mTable: TAtlasFeatureTable;
  mProbe: TProbe;
begin
  mTable := TAtlasFeatureTable.Create;
  mProbe := TProbe.Create;
  try
    mProbe.AddTo(mTable, 0, TAtlasSafeLevel.Minimal);
    mProbe.AddTo(mTable, 1, TAtlasSafeLevel.Minimal);
    mProbe.AddTo(mTable, 2, TAtlasSafeLevel.Minimal);
    mTable.StartWanted(TAtlasSafeLevel.Normal);
    Assert.AreEqual('+A+B+C', mProbe.Log);
    Assert.AreEqual('A,B,C', string.Join(',', mTable.Names));
  finally
    mProbe.Free;
    mTable.Free;
  end;
end;

procedure TFeatureTableTests.StopsInReverseOnlyActive;
var
  mTable: TAtlasFeatureTable;
  mProbe: TProbe;
begin
  mTable := TAtlasFeatureTable.Create;
  mProbe := TProbe.Create;
  try
    mProbe.AddTo(mTable, 0, TAtlasSafeLevel.Minimal);
    mProbe.AddTo(mTable, 1, TAtlasSafeLevel.Normal);
    mProbe.AddTo(mTable, 2, TAtlasSafeLevel.Minimal);
    mTable.StartWanted(TAtlasSafeLevel.Safe);
    mProbe.Log := '';
    mTable.StopAll;
    Assert.AreEqual('-C-A', mProbe.Log);
    Assert.IsFalse(mProbe.Active[0]);
    Assert.IsFalse(mProbe.Active[2]);
  finally
    mProbe.Free;
    mTable.Free;
  end;
end;

procedure TFeatureTableTests.SkipsBelowMinLevel;
var
  mTable: TAtlasFeatureTable;
  mProbe: TProbe;
begin
  mTable := TAtlasFeatureTable.Create;
  mProbe := TProbe.Create;
  try
    mProbe.AddTo(mTable, 0, TAtlasSafeLevel.Normal);
    mProbe.AddTo(mTable, 1, TAtlasSafeLevel.Safe);
    mProbe.AddTo(mTable, 2, TAtlasSafeLevel.Minimal);
    mTable.StartWanted(TAtlasSafeLevel.Minimal);
    Assert.AreEqual('+C', mProbe.Log);
    mProbe.Log := '';
    mTable.StartWanted(TAtlasSafeLevel.Safe);
    Assert.AreEqual('+B', mProbe.Log);
    mProbe.Log := '';
    mTable.StartWanted(TAtlasSafeLevel.Normal);
    Assert.AreEqual('+A', mProbe.Log);
  finally
    mProbe.Free;
    mTable.Free;
  end;
end;

procedure TFeatureTableTests.StartWantedIsIdempotent;
var
  mTable: TAtlasFeatureTable;
  mProbe: TProbe;
begin
  mTable := TAtlasFeatureTable.Create;
  mProbe := TProbe.Create;
  try
    mProbe.AddTo(mTable, 0, TAtlasSafeLevel.Minimal);
    mProbe.AddTo(mTable, 1, TAtlasSafeLevel.Minimal);
    mTable.StartWanted(TAtlasSafeLevel.Normal);
    mTable.StartWanted(TAtlasSafeLevel.Normal);
    Assert.AreEqual('+A+B', mProbe.Log);
  finally
    mProbe.Free;
    mTable.Free;
  end;
end;

procedure TFeatureTableTests.LaterWantedStartsOnSecondCall;
var
  mTable: TAtlasFeatureTable;
  mProbe: TProbe;
  mSwitch: Boolean;
begin
  mTable := TAtlasFeatureTable.Create;
  mProbe := TProbe.Create;
  try
    // Schnellschalter: Das Teil ist erst nach dem Einschalten gewünscht.
    mSwitch := False;
    mProbe.AddTo(mTable, 0, TAtlasSafeLevel.Minimal);
    mProbe.AddWantedTo(mTable, 1,
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := mSwitch;
      end);
    mTable.StartWanted(TAtlasSafeLevel.Safe);
    Assert.AreEqual('+A', mProbe.Log);
    mSwitch := True;
    mTable.StartWanted(TAtlasSafeLevel.Safe);
    Assert.AreEqual('+A+B', mProbe.Log);
  finally
    mProbe.Free;
    mTable.Free;
  end;
end;

procedure TFeatureTableTests.WantedSeesLevel;
var
  mTable: TAtlasFeatureTable;
  mProbe: TProbe;
  mSeen: TAtlasSafeLevel;
begin
  mTable := TAtlasFeatureTable.Create;
  mProbe := TProbe.Create;
  try
    mSeen := TAtlasSafeLevel.Normal;
    mProbe.AddWantedTo(mTable, 0,
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        mSeen := ALevel;
        Result := False;
      end);
    mTable.StartWanted(TAtlasSafeLevel.Minimal);
    Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Minimal, mSeen);
    Assert.AreEqual('', mProbe.Log);
  finally
    mProbe.Free;
    mTable.Free;
  end;
end;

procedure TFeatureTableTests.StopAllContinuesAfterFailure;
var
  mTable: TAtlasFeatureTable;
  mProbe: TProbe;
  mFailures: TArray<string>;
begin
  // #886: Ein Stop mit Ausnahme (Entladen mitten im Gruppen-Build) darf die übrigen Teile nicht stehen lassen.
  mTable := TAtlasFeatureTable.Create;
  mProbe := TProbe.Create;
  try
    mProbe.AddTo(mTable, 0, TAtlasSafeLevel.Minimal);
    mTable.Add('Kaputt', TAtlasSafeLevel.Minimal,
      function: Boolean
      begin
        Result := True;
      end,
      procedure
      begin
      end,
      procedure
      begin
        raise EArgumentException.Create('Stop misslungen');
      end);
    mProbe.AddTo(mTable, 2, TAtlasSafeLevel.Minimal);
    mTable.StartWanted(TAtlasSafeLevel.Normal);
    mProbe.Log := '';
    mFailures := mTable.StopAll;
    Assert.AreEqual('-C-A', mProbe.Log);
    Assert.AreEqual(1, Integer(Length(mFailures)));
    Assert.AreEqual('Kaputt: EArgumentException', mFailures[0]);
  finally
    mProbe.Free;
    mTable.Free;
  end;
end;

procedure TFeatureTableTests.TimesEachStartedPart;
var
  mTable: TAtlasFeatureTable;
  mProbe: TProbe;
  mTimes: TAtlasStartTimes;
  mClock: TFunc<Int64>;
  mTick: Int64;
  mParts: TArray<TAtlasStartPart>;
begin
  // Beim Start misst die Tabelle jedes gestartete Teil, damit ein langsamer Start seine Ursache nennt.
  mTick := 0;
  mClock :=
    function: Int64
    begin
      Inc(mTick, 25);
      Result := mTick;
    end;
  mTable := TAtlasFeatureTable.Create;
  mProbe := TProbe.Create;
  mTimes := TAtlasStartTimes.Create(mClock);
  try
    mProbe.AddTo(mTable, 0, TAtlasSafeLevel.Minimal);
    mProbe.AddTo(mTable, 1, TAtlasSafeLevel.Normal);
    mProbe.AddTo(mTable, 2, TAtlasSafeLevel.Minimal);
    mTable.Times := mTimes;
    mTable.StartWanted(TAtlasSafeLevel.Safe);
    Assert.AreEqual('+A+C', mProbe.Log);
    mParts := mTimes.Slowest(10);
    Assert.AreEqual(2, Integer(Length(mParts)), 'nur gestartete Teile');
    Assert.AreEqual('A', mParts[0].Name);
    Assert.AreEqual(Int64(25), mParts[0].Ms);
    Assert.AreEqual('C', mParts[1].Name);
    // Nach dem Start (Times nil) zählt ein Schnellschalter nicht mehr mit.
    mTable.Times := nil;
    mTable.StartWanted(TAtlasSafeLevel.Normal);
    Assert.AreEqual('+A+C+B', mProbe.Log);
    Assert.AreEqual(Int64(50), mTimes.Total);
  finally
    mTimes.Free;
    mProbe.Free;
    mTable.Free;
  end;
end;

procedure TFeatureTableTests.ModuleOffSkipsItsParts;
var
  mTable: TAtlasFeatureTable;
  mProbe: TProbe;
  mDebugOn: Boolean;
begin
  mTable := TAtlasFeatureTable.Create;
  mProbe := TProbe.Create;
  try
    mProbe.AddTo(mTable, 0, TAtlasSafeLevel.Minimal);
    mProbe.AddTo(mTable, 1, TAtlasSafeLevel.Minimal);
    mProbe.AddTo(mTable, 2, TAtlasSafeLevel.Minimal);
    mTable.Join('debug', ['B', 'C']);
    mDebugOn := False;
    mTable.ModuleOn :=
      function(const AModule: string): Boolean
      begin
        Result := (AModule <> 'debug') or mDebugOn;
      end;
    mTable.StartWanted(TAtlasSafeLevel.Normal);
    Assert.AreEqual('+A', mProbe.Log);
    Assert.AreEqual('debug', mTable.ModuleOf('C'));
    Assert.AreEqual('', mTable.ModuleOf('A'), 'Kern');
    // Wieder an: Die Teile starten beim nächsten Aufruf, ohne Neustart.
    mDebugOn := True;
    mTable.StartWanted(TAtlasSafeLevel.Normal);
    Assert.AreEqual('+A+B+C', mProbe.Log);
    mTable.ModuleOn := nil;
  finally
    mProbe.Free;
    mTable.Free;
  end;
end;

procedure TFeatureTableTests.StopOffModulesStopsOnlyThoseInReverse;
var
  mTable: TAtlasFeatureTable;
  mProbe: TProbe;
  mDebugOn: Boolean;
  mFailures: TArray<string>;
begin
  mTable := TAtlasFeatureTable.Create;
  mProbe := TProbe.Create;
  try
    mProbe.AddTo(mTable, 0, TAtlasSafeLevel.Minimal);
    mProbe.AddTo(mTable, 1, TAtlasSafeLevel.Minimal);
    mProbe.AddTo(mTable, 2, TAtlasSafeLevel.Minimal);
    mProbe.AddTo(mTable, 3, TAtlasSafeLevel.Minimal);
    mTable.Join('debug', ['B', 'D']);
    mTable.Join('tests', ['C']);
    mDebugOn := True;
    mTable.ModuleOn :=
      function(const AModule: string): Boolean
      begin
        Result := (AModule <> 'debug') or mDebugOn;
      end;
    mTable.StartWanted(TAtlasSafeLevel.Normal);
    mProbe.Log := '';
    mFailures := mTable.StopOffModules;
    Assert.AreEqual('', mProbe.Log, 'alle Module an: nichts gestoppt');
    mDebugOn := False;
    mFailures := mTable.StopOffModules;
    Assert.AreEqual('-D-B', mProbe.Log);
    Assert.AreEqual(0, Integer(Length(mFailures)));
    Assert.IsTrue(mProbe.Active[0]);
    Assert.IsTrue(mProbe.Active[2], 'anderes Modul läuft weiter');
    mProbe.Log := '';
    mTable.StopOffModules;
    Assert.AreEqual('', mProbe.Log, 'nur aktive Teile');
    mTable.ModuleOn := nil;
  finally
    mProbe.Free;
    mTable.Free;
  end;
end;

procedure TFeatureTableTests.JoinUnknownPartRaises;
var
  mTable: TAtlasFeatureTable;
  mProbe: TProbe;
begin
  mTable := TAtlasFeatureTable.Create;
  mProbe := TProbe.Create;
  try
    mProbe.AddTo(mTable, 0, TAtlasSafeLevel.Minimal);
    Assert.WillRaise(
      procedure
      begin
        mTable.Join('debug', ['A', 'Z']);
      end, EArgumentException);
  finally
    mProbe.Free;
    mTable.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFeatureTableTests);

end.
