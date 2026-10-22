unit Atlas.Core.Diagnostics.StackRing.Tests;

// Tests für den Ringpuffer der Ausnahme-Mitschnitte und die Beschreibung der Rahmen (Stacktraces der Sicherung).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStackRingTests = class
  public
    [Test]
    procedure FindsNewestEntryOfSameThread;
    [Test]
    procedure MatchesObjectOrFaultAddress;
    [Test]
    procedure IgnoresOtherThreadsAndZeroKeys;
    [Test]
    procedure OverwritesOldestEntries;
    [Test]
    procedure AddressesStartWithFaultAddress;
    [Test]
    procedure DescribeNamesModulesAndResolvesAtlasFrames;
    [Test]
    procedure SymbolizeAcceptsHangFrames;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.MapFile,
  Atlas.Core.Diagnostics.Hangs,
  Atlas.Core.Diagnostics.StackRing;

const
  // Ausschnitt einer detaillierten Map (DCC_MapFile=3): Codesegment ab Modulbasis + $1000.
  SampleMap =
    ' Start         Length     Name                   Class'#13#10 +
    ' 0001:00401000 0000A000H .text                   CODE'#13#10 +
    ''#13#10 +
    '  Address             Publics by Value'#13#10 +
    ''#13#10 +
    ' 0001:00000100       Atlas.IDE.Editor.Minimap.TAtlasMinimap.PaintLine'#13#10 +
    ' 0001:00000180       Atlas.IDE.Editor.Minimap.TAtlasMinimap.Paint'#13#10 +
    ''#13#10 +
    'Line numbers for Atlas.IDE.Editor.Minimap(Atlas.IDE.Editor.Minimap.pas) segment .text'#13#10 +
    ''#13#10 +
    '   600 0001:00000100   612 0001:00000120   640 0001:00000180'#13#10 +
    ''#13#10;

function Entry(AThread: Cardinal; AAddress: NativeUInt; const AParams: array of NativeUInt;
  const AFrames: array of NativeUInt): TAtlasStackRecord;
var
  Index: Integer;
begin
  Result := Default(TAtlasStackRecord);
  Result.ThreadId := AThread;
  Result.Address := AAddress;
  for Index := 0 to High(AParams) do
    Result.Params[Index] := AParams[Index];
  Result.ParamCount := Length(AParams);
  for Index := 0 to High(AFrames) do
    Result.Frames[Index] := AFrames[Index];
  Result.Count := Length(AFrames);
end;

procedure TAtlasStackRingTests.FindsNewestEntryOfSameThread;
var
  Ring: TAtlasStackRing;
  Found: TAtlasStackRecord;
begin
  Ring := TAtlasStackRing.Create;
  try
    // Erneutes raise derselben Ausnahme: der jüngere Mitschnitt gilt.
    Ring.Add(Entry(7, $100, [$500, $AAAA], [$1]));
    Ring.Add(Entry(7, $200, [$600, $AAAA], [$2]));
    Assert.IsTrue(Ring.Find(7, [$AAAA], Found));
    Assert.AreEqual<UInt64>($2, Found.Frames[0]);
  finally
    Ring.Free;
  end;
end;

procedure TAtlasStackRingTests.MatchesObjectOrFaultAddress;
var
  Ring: TAtlasStackRing;
  Found: TAtlasStackRecord;
begin
  Ring := TAtlasStackRing.Create;
  try
    // Delphi-Ausnahme: Objekt in den Parametern; Zugriffsverletzung: Fehleradresse im Record.
    Ring.Add(Entry(3, $7000, [$123, $BEEF], [$1]));
    Ring.Add(Entry(3, $9000, [0, $4321], [$2]));
    Assert.IsTrue(Ring.Find(3, [$BEEF, $1], Found));
    Assert.AreEqual<UInt64>($7000, Found.Address);
    Assert.IsTrue(Ring.Find(3, [$5, $9000], Found));
    Assert.AreEqual<UInt64>($2, Found.Frames[0]);
    Assert.IsFalse(Ring.Find(3, [$5, $6], Found));
  finally
    Ring.Free;
  end;
end;

procedure TAtlasStackRingTests.IgnoresOtherThreadsAndZeroKeys;
var
  Ring: TAtlasStackRing;
  Found: TAtlasStackRecord;
begin
  Ring := TAtlasStackRing.Create;
  try
    Ring.Add(Entry(1, $100, [0, $AAAA], [$1]));
    Assert.IsFalse(Ring.Find(2, [$AAAA], Found), 'anderer Thread');
    Assert.IsFalse(Ring.Find(1, [0], Found), '0 passt nie, auch nicht zu leeren Parametern');
    Ring.Clear;
    Assert.IsFalse(Ring.Find(1, [$AAAA], Found), 'nach Clear leer');
  finally
    Ring.Free;
  end;
end;

procedure TAtlasStackRingTests.OverwritesOldestEntries;
var
  Ring: TAtlasStackRing;
  Found: TAtlasStackRecord;
  Index: Integer;
begin
  Ring := TAtlasStackRing.Create;
  try
    for Index := 1 to TAtlasStackRing.SlotCount + 8 do
      Ring.Add(Entry(1, NativeUInt(Index), [], []));
    Assert.IsFalse(Ring.Find(1, [1], Found), 'älteste überschrieben');
    Assert.IsFalse(Ring.Find(1, [8], Found));
    Assert.IsTrue(Ring.Find(1, [9], Found));
    Assert.IsTrue(Ring.Find(1, [NativeUInt(TAtlasStackRing.SlotCount + 8)], Found));
  finally
    Ring.Free;
  end;
end;

procedure TAtlasStackRingTests.AddressesStartWithFaultAddress;
var
  Addresses: TArray<UInt64>;
begin
  Addresses := Entry(1, $500, [], [$10, 0, $20]).Addresses;
  Assert.AreEqual(3, Integer(Length(Addresses)), 'Fehleradresse vorn, leere Rahmen ausgelassen');
  Assert.AreEqual<UInt64>($500, Addresses[0]);
  Assert.AreEqual<UInt64>($20, Addresses[2]);
end;

procedure TAtlasStackRingTests.DescribeNamesModulesAndResolvesAtlasFrames;
var
  Map: TMapFile;
  Modules: TArray<TAtlasModuleRange>;
  Atlas, Rtl: TAtlasModuleRange;
  Text: string;
  Lines: TArray<string>;
begin
  Atlas.Name := 'Atlas.IDE.Expert370.bpl';
  Atlas.Base := $10000000;
  Atlas.Size := $100000;
  Rtl.Name := 'rtl370.bpl';
  Rtl.Base := $20000000;
  Rtl.Size := $100000;
  Modules := [Atlas, Rtl];
  Map := TMapFile.Create(SampleMap);
  try
    Text := TAtlasStackFrames.Describe([$10001124, $20000010, $30000000, $10001184], Modules, Map,
      'Atlas.IDE.Expert370.bpl', 3);
    Lines := Text.Split([sLineBreak]);
    Assert.AreEqual(3, Integer(Length(Lines)), 'höchstens AMax Zeilen');
    Assert.AreEqual('Atlas.IDE.Expert370.bpl+$1124 Atlas.IDE.Editor.Minimap.TAtlasMinimap.PaintLine ' +
      '(Atlas.IDE.Editor.Minimap.pas:612)', Lines[0]);
    Assert.AreEqual('rtl370.bpl+$10', Lines[1]);
    Assert.AreEqual('$30000000', Lines[2], 'ohne Modul nur die Adresse');
  finally
    Map.Free;
  end;
end;

procedure TAtlasStackRingTests.SymbolizeAcceptsHangFrames;
var
  Map: TMapFile;
begin
  Map := TMapFile.Create(SampleMap);
  try
    // Der Einfrier-Wächter schreibt „Modul+Offset“ ohne $.
    Assert.AreEqual('Atlas.IDE.Expert370.bpl+1184 Atlas.IDE.Editor.Minimap.TAtlasMinimap.Paint ' +
      '(Atlas.IDE.Editor.Minimap.pas:640)', TAtlasStackFrames.Symbolize('Atlas.IDE.Expert370.bpl+1184', Map,
      'Atlas.IDE.Expert370.bpl'));
    Assert.AreEqual('rtl370.bpl+1184', TAtlasStackFrames.Symbolize('rtl370.bpl+1184', Map,
      'Atlas.IDE.Expert370.bpl'));
    Assert.AreEqual('Atlas.IDE.Expert370.bpl+zz', TAtlasStackFrames.Symbolize('Atlas.IDE.Expert370.bpl+zz', Map,
      'Atlas.IDE.Expert370.bpl'));
    Assert.AreEqual('Atlas.IDE.Expert370.bpl+1184', TAtlasStackFrames.Symbolize('Atlas.IDE.Expert370.bpl+1184', nil,
      'Atlas.IDE.Expert370.bpl'));
  finally
    Map.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStackRingTests);

end.
