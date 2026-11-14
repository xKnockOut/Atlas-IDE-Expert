unit Atlas.Core.Debug.ObjectCount.Tests;

// Tests für den Kern der Objektzählung (#858) ohne IDE und ohne Windows: Ein nachgebauter Prozessspeicher mit
// einem Abbild (VMTs, Klassennamen) und einem Datenbereich (Objekte) prüft das Erkennen der VMTs über den
// Selbstzeiger für 32 und 64 Bit, das Zusammenfassen gleichnamiger Klassen und den Vergleich zweier Zählungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasObjectCountTests = class
  public
    [Test]
    procedure CountsObjectsOfBothWin64Layouts;
    [Test]
    procedure CountsObjectsWin32;
    [Test]
    procedure IgnoresPointersThatAreNoVmt;
    [Test]
    procedure MergesClassesOfTheSameName;
    [Test]
    procedure RecognizesClassNames;
    [Test]
    procedure CompareShowsGrowthFirst;
    [Test]
    procedure CompareFiltersByName;
    [Test]
    procedure CompareWithoutBaseSortsByCount;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Debug.ObjectCount;

const
  cImageBase = $400000;
  cDataBase = $10000000;
  cImageSize = 8192;
  cDataSize = 4096;

type
  /// <summary>Prozessspeicher aus zwei Bereichen: Abbild und Daten.</summary>
  TFakeMemory = class(TInterfacedObject, IAtlasProcessMemory)
  private
    FPointerSize: Integer;
    FImage: TBytes;
    FData: TBytes;
    function Slot(AAddress: UInt64; out ABytes: TBytes; out AOffset: Integer): Boolean;
  public
    constructor Create(APointerSize: Integer);
    procedure PutPointer(AAddress, AValue: UInt64);
    procedure PutInteger(AAddress: UInt64; AValue: Integer);
    procedure PutName(AAddress: UInt64; const AName: string);
    /// <summary>VMT bei AVmt mit Anordnung ALayout, Klassenname bei AName, Instanzgröße ASize.</summary>
    procedure PutVmt(AVmt: UInt64; const ALayout: TAtlasVmtLayout; ANameAt: UInt64; const AName: string;
      ASize: Integer);
    function PointerSize: Integer;
    function Regions: TArray<TAtlasMemoryRegion>;
    function Read(AAddress: UInt64; var ABuffer; ASize: Integer): Integer;
  end;

constructor TFakeMemory.Create(APointerSize: Integer);
begin
  inherited Create;
  FPointerSize := APointerSize;
  SetLength(FImage, cImageSize);
  SetLength(FData, cDataSize);
end;

function TFakeMemory.Slot(AAddress: UInt64; out ABytes: TBytes; out AOffset: Integer): Boolean;
begin
  Result := True;
  if (AAddress >= cImageBase) and (AAddress < cImageBase + cImageSize) then
  begin
    ABytes := FImage;
    AOffset := Integer(AAddress - cImageBase);
    Exit;
  end;
  if (AAddress >= cDataBase) and (AAddress < cDataBase + cDataSize) then
  begin
    ABytes := FData;
    AOffset := Integer(AAddress - cDataBase);
    Exit;
  end;
  ABytes := nil;
  AOffset := 0;
  Result := False;
end;

procedure TFakeMemory.PutPointer(AAddress, AValue: UInt64);
var
  mBytes: TBytes;
  mOffset: Integer;
begin
  Assert.IsTrue(Slot(AAddress, mBytes, mOffset), 'Adresse außerhalb');
  Move(AValue, mBytes[mOffset], FPointerSize);
end;

procedure TFakeMemory.PutInteger(AAddress: UInt64; AValue: Integer);
var
  mBytes: TBytes;
  mOffset: Integer;
begin
  Assert.IsTrue(Slot(AAddress, mBytes, mOffset), 'Adresse außerhalb');
  Move(AValue, mBytes[mOffset], SizeOf(AValue));
end;

procedure TFakeMemory.PutName(AAddress: UInt64; const AName: string);
var
  mBytes: TBytes;
  mOffset: Integer;
  mUtf8: TBytes;
begin
  Assert.IsTrue(Slot(AAddress, mBytes, mOffset), 'Adresse außerhalb');
  mUtf8 := TEncoding.UTF8.GetBytes(AName);
  mBytes[mOffset] := Byte(Length(mUtf8));
  Move(mUtf8[0], mBytes[mOffset + 1], Length(mUtf8));
end;

procedure TFakeMemory.PutVmt(AVmt: UInt64; const ALayout: TAtlasVmtLayout; ANameAt: UInt64; const AName: string;
  ASize: Integer);
begin
  PutPointer(AVmt - UInt64(ALayout.SelfBelow), AVmt);
  PutPointer(AVmt - UInt64(ALayout.NameBelow), ANameAt);
  PutInteger(AVmt - UInt64(ALayout.SizeBelow), ASize);
  PutName(ANameAt, AName);
end;

function TFakeMemory.PointerSize: Integer;
begin
  Result := FPointerSize;
end;

function TFakeMemory.Regions: TArray<TAtlasMemoryRegion>;
begin
  SetLength(Result, 2);
  Result[0] := TAtlasMemoryRegion.Make(cImageBase, cImageSize, TAtlasMemoryRegionKind.Image);
  Result[1] := TAtlasMemoryRegion.Make(cDataBase, cDataSize, TAtlasMemoryRegionKind.Data);
end;

function TFakeMemory.Read(AAddress: UInt64; var ABuffer; ASize: Integer): Integer;
var
  mBytes: TBytes;
  mOffset: Integer;
begin
  Result := 0;
  if not Slot(AAddress, mBytes, mOffset) then
  begin
    Exit;
  end;
  Result := ASize;
  if mOffset + Result > Length(mBytes) then
  begin
    Result := Length(mBytes) - mOffset;
  end;
  Move(mBytes[mOffset], ABuffer, Result);
end;

function CountOf(AMemory: TFakeMemory): TAtlasObjectCount;
var
  mMemory: IAtlasProcessMemory;
  mCounter: TAtlasObjectCounter;
begin
  mMemory := AMemory;
  mCounter := TAtlasObjectCounter.Create(mMemory);
  try
    Result := mCounter.Run;
  finally
    mCounter.Free;
  end;
end;

function CountOfClass(const ACount: TAtlasObjectCount; const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := 0;
  mIndex := ACount.IndexOf(AName);
  if mIndex >= 0 then
  begin
    Result := ACount.Classes[mIndex].Count;
  end;
end;

/// <summary>Objekte von AVmt an den Stellen AOffsets des Datenbereichs.</summary>
procedure PutObjects(AMemory: TFakeMemory; AVmt: UInt64; const AOffsets: array of Integer);
var
  mOffset: Integer;
begin
  for mOffset in AOffsets do
  begin
    AMemory.PutPointer(cDataBase + UInt64(mOffset), AVmt);
  end;
end;

function Counted(const AItems: array of string; const ACounts: array of Integer): TAtlasObjectCount;
var
  mIndex: Integer;
begin
  // Wie TAtlasObjectCounter.Run: nach Namen sortiert.
  Result := Default(TAtlasObjectCount);
  SetLength(Result.Classes, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    Result.Classes[mIndex].Name := AItems[mIndex];
    Result.Classes[mIndex].Count := ACounts[mIndex];
    Result.Classes[mIndex].InstanceSize := 16;
  end;
end;

{ TAtlasObjectCountTests }

procedure TAtlasObjectCountTests.CountsObjectsOfBothWin64Layouts;
var
  mMemory: TFakeMemory;
  mLayouts: TArray<TAtlasVmtLayout>;
  mCount: TAtlasObjectCount;
begin
  mMemory := TFakeMemory.Create(8);
  mLayouts := TAtlasVmtLayout.ForPointerSize(8);
  Assert.AreEqual(2, Integer(Length(mLayouts)));
  mMemory.PutVmt(cImageBase + 1024, mLayouts[0], cImageBase + 4096, 'TLeak', 24);
  mMemory.PutVmt(cImageBase + 2048, mLayouts[1], cImageBase + 4200, 'TKeep', 40);
  PutObjects(mMemory, cImageBase + 1024, [0, 32, 64]);
  PutObjects(mMemory, cImageBase + 2048, [128, 256]);
  mCount := CountOf(mMemory);
  Assert.AreEqual(2, Integer(Length(mCount.Classes)));
  Assert.AreEqual(3, CountOfClass(mCount, 'TLeak'));
  Assert.AreEqual(2, CountOfClass(mCount, 'TKeep'));
  Assert.AreEqual(5, mCount.Total);
  Assert.AreEqual(24, mCount.Classes[mCount.IndexOf('TLeak')].InstanceSize);
  Assert.AreEqual<UInt64>(cDataSize, mCount.ScannedBytes, 'gelesene Bytes');
end;

procedure TAtlasObjectCountTests.CountsObjectsWin32;
var
  mMemory: TFakeMemory;
  mCount: TAtlasObjectCount;
begin
  mMemory := TFakeMemory.Create(4);
  mMemory.PutVmt(cImageBase + 1024, TAtlasVmtLayout.ForPointerSize(4)[0], cImageBase + 4096,
    'TList<System.Integer>', 20);
  PutObjects(mMemory, cImageBase + 1024, [8, 16, 24, 40]);
  // Nicht auf 8 ausgerichtet: kein Objektanfang.
  PutObjects(mMemory, cImageBase + 1024, [44]);
  mCount := CountOf(mMemory);
  Assert.AreEqual(4, CountOfClass(mCount, 'TList<System.Integer>'));
  Assert.AreEqual(4, mCount.Total);
end;

procedure TAtlasObjectCountTests.IgnoresPointersThatAreNoVmt;
var
  mMemory: TFakeMemory;
  mLayout: TAtlasVmtLayout;
  mCount: TAtlasObjectCount;
begin
  mMemory := TFakeMemory.Create(8);
  mLayout := TAtlasVmtLayout.ForPointerSize(8)[0];
  // Selbstzeiger falsch.
  mMemory.PutVmt(cImageBase + 1024, mLayout, cImageBase + 4096, 'TFalsch', 24);
  mMemory.PutPointer(cImageBase + 1024 - UInt64(mLayout.SelfBelow), cImageBase + 8);
  // Name kein Bezeichner.
  mMemory.PutVmt(cImageBase + 2048, mLayout, cImageBase + 4200, '1 kaputt', 24);
  // Instanzgröße unmöglich.
  mMemory.PutVmt(cImageBase + 3072, mLayout, cImageBase + 4300, 'TRiesig', -1);
  PutObjects(mMemory, cImageBase + 1024, [0]);
  PutObjects(mMemory, cImageBase + 2048, [8]);
  PutObjects(mMemory, cImageBase + 3072, [16]);
  // Zeiger in den Datenbereich und auf den Anfang des Abbilds.
  PutObjects(mMemory, cDataBase + 64, [24]);
  PutObjects(mMemory, cImageBase, [32]);
  mCount := CountOf(mMemory);
  Assert.AreEqual(0, mCount.Total);
  Assert.AreEqual(0, Integer(Length(mCount.Classes)));
end;

procedure TAtlasObjectCountTests.MergesClassesOfTheSameName;
var
  mMemory: TFakeMemory;
  mLayout: TAtlasVmtLayout;
  mCount: TAtlasObjectCount;
begin
  // Gleiche Klasse in EXE und BPL (zwei VMTs).
  mMemory := TFakeMemory.Create(8);
  mLayout := TAtlasVmtLayout.ForPointerSize(8)[0];
  mMemory.PutVmt(cImageBase + 1024, mLayout, cImageBase + 4096, 'TForm1', 900);
  mMemory.PutVmt(cImageBase + 2048, mLayout, cImageBase + 4200, 'TForm1', 900);
  PutObjects(mMemory, cImageBase + 1024, [0, 8]);
  PutObjects(mMemory, cImageBase + 2048, [16]);
  mCount := CountOf(mMemory);
  Assert.AreEqual(1, Integer(Length(mCount.Classes)));
  Assert.AreEqual(3, CountOfClass(mCount, 'TForm1'));
end;

procedure TAtlasObjectCountTests.RecognizesClassNames;
begin
  Assert.IsTrue(TAtlasObjectCounter.IsClassName('TForm1'));
  Assert.IsTrue(TAtlasObjectCounter.IsClassName('_TInner'));
  Assert.IsTrue(TAtlasObjectCounter.IsClassName('TDictionary<System.string,System.Integer>'));
  Assert.IsTrue(TAtlasObjectCounter.IsClassName('T'#$00C4'nderung'));
  Assert.IsFalse(TAtlasObjectCounter.IsClassName(''));
  Assert.IsFalse(TAtlasObjectCounter.IsClassName('1TForm'));
  Assert.IsFalse(TAtlasObjectCounter.IsClassName('.TForm'));
  Assert.IsFalse(TAtlasObjectCounter.IsClassName('T Form'));
  Assert.IsFalse(TAtlasObjectCounter.IsClassName('T'#0));
end;

procedure TAtlasObjectCountTests.CompareShowsGrowthFirst;
var
  mRows: TArray<TAtlasObjectCountRow>;
begin
  mRows := TAtlasObjectCountCompare.Rows(Counted(['TA', 'TB', 'TGone'], [5, 10, 2]),
    Counted(['TA', 'TB', 'TNew'], [15, 10, 1]), True, '');
  Assert.AreEqual(4, Integer(Length(mRows)));
  Assert.AreEqual('TA', mRows[0].Name);
  Assert.AreEqual(10, mRows[0].Delta);
  Assert.AreEqual(Int64(15 * 16), mRows[0].Bytes);
  Assert.AreEqual('TNew', mRows[1].Name);
  Assert.AreEqual(1, mRows[1].Delta);
  Assert.AreEqual('TB', mRows[2].Name);
  Assert.AreEqual(0, mRows[2].Delta);
  Assert.AreEqual('TGone', mRows[3].Name);
  Assert.AreEqual(-2, mRows[3].Delta);
  Assert.AreEqual(0, mRows[3].Count);
end;

procedure TAtlasObjectCountTests.CompareFiltersByName;
var
  mRows: TArray<TAtlasObjectCountRow>;
begin
  mRows := TAtlasObjectCountCompare.Rows(Counted(['TKunde', 'TRechnung'], [1, 1]),
    Counted(['TKunde', 'TKundenListe', 'TRechnung'], [3, 1, 1]), True, ' kunde ');
  Assert.AreEqual(2, Integer(Length(mRows)));
  Assert.AreEqual('TKunde', mRows[0].Name);
  Assert.AreEqual('TKundenListe', mRows[1].Name);
end;

procedure TAtlasObjectCountTests.CompareWithoutBaseSortsByCount;
var
  mRows: TArray<TAtlasObjectCountRow>;
begin
  mRows := TAtlasObjectCountCompare.Rows(Default(TAtlasObjectCount),
    Counted(['TA', 'TB', 'TC'], [2, 7, 2]), False, '');
  Assert.AreEqual(3, Integer(Length(mRows)));
  Assert.AreEqual('TB', mRows[0].Name);
  Assert.AreEqual('TA', mRows[1].Name);
  Assert.AreEqual('TC', mRows[2].Name);
  Assert.AreEqual(0, mRows[0].Delta);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasObjectCountTests);

end.
