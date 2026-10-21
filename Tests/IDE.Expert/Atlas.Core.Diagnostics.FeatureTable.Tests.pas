unit Atlas.Core.Diagnostics.FeatureTable.Tests;

// Startreihenfolge, Abbau und Stufen der Feature-Tabelle (Code-Review S-03).

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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.SafeMode,
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
  Name: string;
begin
  Name := Chr(Ord('A') + AIndex);
  ATable.AddWanted(Name, AWanted,
    function: Boolean
    begin
      Result := Active[AIndex];
    end,
    procedure
    begin
      Active[AIndex] := True;
      Log := Log + '+' + Name;
    end,
    procedure
    begin
      Active[AIndex] := False;
      Log := Log + '-' + Name;
    end);
end;

procedure TFeatureTableTests.StartsInOrder;
var
  Table: TAtlasFeatureTable;
  Probe: TProbe;
begin
  Table := TAtlasFeatureTable.Create;
  Probe := TProbe.Create;
  try
    Probe.AddTo(Table, 0, TAtlasSafeLevel.Minimal);
    Probe.AddTo(Table, 1, TAtlasSafeLevel.Minimal);
    Probe.AddTo(Table, 2, TAtlasSafeLevel.Minimal);
    Table.StartWanted(TAtlasSafeLevel.Normal);
    Assert.AreEqual('+A+B+C', Probe.Log);
    Assert.AreEqual('A,B,C', string.Join(',', Table.Names));
  finally
    Probe.Free;
    Table.Free;
  end;
end;

procedure TFeatureTableTests.StopsInReverseOnlyActive;
var
  Table: TAtlasFeatureTable;
  Probe: TProbe;
begin
  Table := TAtlasFeatureTable.Create;
  Probe := TProbe.Create;
  try
    Probe.AddTo(Table, 0, TAtlasSafeLevel.Minimal);
    Probe.AddTo(Table, 1, TAtlasSafeLevel.Normal);
    Probe.AddTo(Table, 2, TAtlasSafeLevel.Minimal);
    Table.StartWanted(TAtlasSafeLevel.Safe);
    Probe.Log := '';
    Table.StopAll;
    Assert.AreEqual('-C-A', Probe.Log);
    Assert.IsFalse(Probe.Active[0]);
    Assert.IsFalse(Probe.Active[2]);
  finally
    Probe.Free;
    Table.Free;
  end;
end;

procedure TFeatureTableTests.SkipsBelowMinLevel;
var
  Table: TAtlasFeatureTable;
  Probe: TProbe;
begin
  Table := TAtlasFeatureTable.Create;
  Probe := TProbe.Create;
  try
    Probe.AddTo(Table, 0, TAtlasSafeLevel.Normal);
    Probe.AddTo(Table, 1, TAtlasSafeLevel.Safe);
    Probe.AddTo(Table, 2, TAtlasSafeLevel.Minimal);
    Table.StartWanted(TAtlasSafeLevel.Minimal);
    Assert.AreEqual('+C', Probe.Log);
    Probe.Log := '';
    Table.StartWanted(TAtlasSafeLevel.Safe);
    Assert.AreEqual('+B', Probe.Log);
    Probe.Log := '';
    Table.StartWanted(TAtlasSafeLevel.Normal);
    Assert.AreEqual('+A', Probe.Log);
  finally
    Probe.Free;
    Table.Free;
  end;
end;

procedure TFeatureTableTests.StartWantedIsIdempotent;
var
  Table: TAtlasFeatureTable;
  Probe: TProbe;
begin
  Table := TAtlasFeatureTable.Create;
  Probe := TProbe.Create;
  try
    Probe.AddTo(Table, 0, TAtlasSafeLevel.Minimal);
    Probe.AddTo(Table, 1, TAtlasSafeLevel.Minimal);
    Table.StartWanted(TAtlasSafeLevel.Normal);
    Table.StartWanted(TAtlasSafeLevel.Normal);
    Assert.AreEqual('+A+B', Probe.Log);
  finally
    Probe.Free;
    Table.Free;
  end;
end;

procedure TFeatureTableTests.LaterWantedStartsOnSecondCall;
var
  Table: TAtlasFeatureTable;
  Probe: TProbe;
  Switch: Boolean;
begin
  Table := TAtlasFeatureTable.Create;
  Probe := TProbe.Create;
  try
    // Schnellschalter: Das Teil ist erst nach dem Einschalten gewünscht.
    Switch := False;
    Probe.AddTo(Table, 0, TAtlasSafeLevel.Minimal);
    Probe.AddWantedTo(Table, 1,
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := Switch;
      end);
    Table.StartWanted(TAtlasSafeLevel.Safe);
    Assert.AreEqual('+A', Probe.Log);
    Switch := True;
    Table.StartWanted(TAtlasSafeLevel.Safe);
    Assert.AreEqual('+A+B', Probe.Log);
  finally
    Probe.Free;
    Table.Free;
  end;
end;

procedure TFeatureTableTests.WantedSeesLevel;
var
  Table: TAtlasFeatureTable;
  Probe: TProbe;
  Seen: TAtlasSafeLevel;
begin
  Table := TAtlasFeatureTable.Create;
  Probe := TProbe.Create;
  try
    Seen := TAtlasSafeLevel.Normal;
    Probe.AddWantedTo(Table, 0,
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Seen := ALevel;
        Result := False;
      end);
    Table.StartWanted(TAtlasSafeLevel.Minimal);
    Assert.IsTrue(Seen = TAtlasSafeLevel.Minimal);
    Assert.AreEqual('', Probe.Log);
  finally
    Probe.Free;
    Table.Free;
  end;
end;

procedure TFeatureTableTests.StopAllContinuesAfterFailure;
var
  Table: TAtlasFeatureTable;
  Probe: TProbe;
  Failures: TArray<string>;
begin
  // #886: Ein Stop mit Ausnahme (Entladen mitten im Gruppen-Build) darf die übrigen Teile nicht stehen lassen.
  Table := TAtlasFeatureTable.Create;
  Probe := TProbe.Create;
  try
    Probe.AddTo(Table, 0, TAtlasSafeLevel.Minimal);
    Table.Add('Kaputt', TAtlasSafeLevel.Minimal,
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
    Probe.AddTo(Table, 2, TAtlasSafeLevel.Minimal);
    Table.StartWanted(TAtlasSafeLevel.Normal);
    Probe.Log := '';
    Failures := Table.StopAll;
    Assert.AreEqual('-C-A', Probe.Log);
    Assert.AreEqual(1, Integer(Length(Failures)));
    Assert.AreEqual('Kaputt: EArgumentException', Failures[0]);
  finally
    Probe.Free;
    Table.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TFeatureTableTests);

end.
