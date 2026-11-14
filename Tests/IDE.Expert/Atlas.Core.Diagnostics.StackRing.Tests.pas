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
  cSampleMap =
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
  mIndex: Integer;
begin
  Result := Default(TAtlasStackRecord);
  Result.ThreadId := AThread;
  Result.Address := AAddress;
  for mIndex := 0 to High(AParams) do
  begin
    Result.Params[mIndex] := AParams[mIndex];
  end;
  Result.ParamCount := Length(AParams);
  for mIndex := 0 to High(AFrames) do
  begin
    Result.Frames[mIndex] := AFrames[mIndex];
  end;
  Result.Count := Length(AFrames);
end;

procedure TAtlasStackRingTests.FindsNewestEntryOfSameThread;
var
  mRing: TAtlasStackRing;
  mFound: TAtlasStackRecord;
begin
  mRing := TAtlasStackRing.Create;
  try
    // Erneutes raise derselben Ausnahme: der jüngere Mitschnitt gilt.
    mRing.Add(Entry(7, $100, [$500, $AAAA], [$1]));
    mRing.Add(Entry(7, $200, [$600, $AAAA], [$2]));
    Assert.IsTrue(mRing.Find(7, [$AAAA], mFound));
    Assert.AreEqual<UInt64>($2, mFound.Frames[0]);
  finally
    mRing.Free;
  end;
end;

procedure TAtlasStackRingTests.MatchesObjectOrFaultAddress;
var
  mRing: TAtlasStackRing;
  mFound: TAtlasStackRecord;
begin
  mRing := TAtlasStackRing.Create;
  try
    // Delphi-Ausnahme: Objekt in den Parametern; Zugriffsverletzung: Fehleradresse im Record.
    mRing.Add(Entry(3, $7000, [$123, $BEEF], [$1]));
    mRing.Add(Entry(3, $9000, [0, $4321], [$2]));
    Assert.IsTrue(mRing.Find(3, [$BEEF, $1], mFound));
    Assert.AreEqual<UInt64>($7000, mFound.Address);
    Assert.IsTrue(mRing.Find(3, [$5, $9000], mFound));
    Assert.AreEqual<UInt64>($2, mFound.Frames[0]);
    Assert.IsFalse(mRing.Find(3, [$5, $6], mFound));
  finally
    mRing.Free;
  end;
end;

procedure TAtlasStackRingTests.IgnoresOtherThreadsAndZeroKeys;
var
  mRing: TAtlasStackRing;
  mFound: TAtlasStackRecord;
begin
  mRing := TAtlasStackRing.Create;
  try
    mRing.Add(Entry(1, $100, [0, $AAAA], [$1]));
    Assert.IsFalse(mRing.Find(2, [$AAAA], mFound), 'anderer Thread');
    Assert.IsFalse(mRing.Find(1, [0], mFound), '0 passt nie, auch nicht zu leeren Parametern');
    mRing.Clear;
    Assert.IsFalse(mRing.Find(1, [$AAAA], mFound), 'nach Clear leer');
  finally
    mRing.Free;
  end;
end;

procedure TAtlasStackRingTests.OverwritesOldestEntries;
var
  mRing: TAtlasStackRing;
  mFound: TAtlasStackRecord;
  mIndex: Integer;
begin
  mRing := TAtlasStackRing.Create;
  try
    for mIndex := 1 to TAtlasStackRing.cSlotCount + 8 do
    begin
      mRing.Add(Entry(1, NativeUInt(mIndex), [], []));
    end;
    Assert.IsFalse(mRing.Find(1, [1], mFound), 'älteste überschrieben');
    Assert.IsFalse(mRing.Find(1, [8], mFound));
    Assert.IsTrue(mRing.Find(1, [9], mFound));
    Assert.IsTrue(mRing.Find(1, [NativeUInt(TAtlasStackRing.cSlotCount + 8)], mFound));
  finally
    mRing.Free;
  end;
end;

procedure TAtlasStackRingTests.AddressesStartWithFaultAddress;
var
  mAddresses: TArray<UInt64>;
begin
  mAddresses := Entry(1, $500, [], [$10, 0, $20]).Addresses;
  Assert.AreEqual(3, Integer(Length(mAddresses)), 'Fehleradresse vorn, leere Rahmen ausgelassen');
  Assert.AreEqual<UInt64>($500, mAddresses[0]);
  Assert.AreEqual<UInt64>($20, mAddresses[2]);
end;

procedure TAtlasStackRingTests.DescribeNamesModulesAndResolvesAtlasFrames;
var
  mMap: TMapFile;
  mModules: TArray<TAtlasModuleRange>;
  mAtlas, mRtl: TAtlasModuleRange;
  mText: string;
  mLines: TArray<string>;
begin
  mAtlas.Name := 'Atlas.IDE.Expert370.bpl';
  mAtlas.Base := $10000000;
  mAtlas.Size := $100000;
  mRtl.Name := 'rtl370.bpl';
  mRtl.Base := $20000000;
  mRtl.Size := $100000;
  mModules := [mAtlas, mRtl];
  mMap := TMapFile.Create(cSampleMap);
  try
    mText := TAtlasStackFrames.Describe([$10001124, $20000010, $30000000, $10001184], mModules, mMap,
      'Atlas.IDE.Expert370.bpl', 3);
    mLines := mText.Split([sLineBreak]);
    Assert.AreEqual(3, Integer(Length(mLines)), 'höchstens AMax Zeilen');
    Assert.AreEqual('Atlas.IDE.Expert370.bpl+$1124 Atlas.IDE.Editor.Minimap.TAtlasMinimap.PaintLine ' +
      '(Atlas.IDE.Editor.Minimap.pas:612)', mLines[0]);
    Assert.AreEqual('rtl370.bpl+$10', mLines[1]);
    Assert.AreEqual('$30000000', mLines[2], 'ohne Modul nur die Adresse');
  finally
    mMap.Free;
  end;
end;

procedure TAtlasStackRingTests.SymbolizeAcceptsHangFrames;
var
  mMap: TMapFile;
begin
  mMap := TMapFile.Create(cSampleMap);
  try
    // Der Einfrier-Wächter schreibt „Modul+Offset“ ohne $.
    Assert.AreEqual('Atlas.IDE.Expert370.bpl+1184 Atlas.IDE.Editor.Minimap.TAtlasMinimap.Paint ' +
      '(Atlas.IDE.Editor.Minimap.pas:640)', TAtlasStackFrames.Symbolize('Atlas.IDE.Expert370.bpl+1184', mMap,
      'Atlas.IDE.Expert370.bpl'));
    Assert.AreEqual('rtl370.bpl+1184', TAtlasStackFrames.Symbolize('rtl370.bpl+1184', mMap,
      'Atlas.IDE.Expert370.bpl'));
    Assert.AreEqual('Atlas.IDE.Expert370.bpl+zz', TAtlasStackFrames.Symbolize('Atlas.IDE.Expert370.bpl+zz', mMap,
      'Atlas.IDE.Expert370.bpl'));
    Assert.AreEqual('Atlas.IDE.Expert370.bpl+1184', TAtlasStackFrames.Symbolize('Atlas.IDE.Expert370.bpl+1184', nil,
      'Atlas.IDE.Expert370.bpl'));
  finally
    mMap.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStackRingTests);

end.
