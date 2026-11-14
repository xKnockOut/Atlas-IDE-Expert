unit Atlas.Common.Index.Memory.Tests;

// Tests für das Speicherbudget des Symbolindex (#185).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexMemoryTests = class
  public
    [Test]
    procedure PoolReturnsSameStringForEqualValues;
    [Test]
    procedure PoolDoesNotChangeCallerArrays;
    [Test]
    procedure CompactKeepsOnlyInterfaceSymbols;
    [Test]
    procedure UnitBytesGrowWithSymbols;
    [Test]
    procedure IndexTracksMemoryBytes;
    /// <summary>#1356: Speicher nach Projekt, Bibliothek und Verwendungen; die Teile ergeben MemoryBytes.</summary>
    [Test]
    procedure MemoryPartsSplitIndex;
    [Test]
    procedure WithoutBudgetNothingIsCompacted;
    [Test]
    procedure CompactsLibraryUnitsFirst;
    [Test]
    procedure CompactsProjectUnitsWhenLibrariesAreNotEnough;
    [Test]
    procedure KeepsProjectUsagesWhileLibrariesAreEnough;
    [Test]
    procedure MillionLinesStayBelowBudget;
    [Test]
    procedure CacheKeepsLibraryAndCompactFlags;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Memory,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Cache;

function MakeSymbol(const AName: string; AInInterface: Boolean): TIndexSymbol;
begin
  Result := Default(TIndexSymbol);
  Result.Name := AName;
  Result.Container := 'TContainer';
  Result.Kind := TIndexSymbolKind.Method;
  Result.Range := TTextRange.Create(TTextPosition.Create(1, 0), TTextPosition.Create(1, 10));
  Result.SelectionRange := Result.Range;
  Result.InInterface := AInInterface;
  Result.Ancestors := ['TObject'];
  Result.TypeName := 'Integer';
end;

function MakeUnit(const AName: string; ALibrary: Boolean; AInterfaceSymbols,
  AImplementationSymbols: Integer): TUnitIndex;
var
  mIndex: Integer;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AName;
  Result.FileName := 'C:\Quelle\' + AName + '.pas';
  Result.Library_ := ALibrary;
  Result.InterfaceUses := ['System.SysUtils'];
  Result.ImplementationUses := ['System.Classes'];
  SetLength(Result.Symbols, AInterfaceSymbols + AImplementationSymbols);
  for mIndex := 0 to High(Result.Symbols) do
  begin
    Result.Symbols[mIndex] := MakeSymbol(AName + 'Symbol' + IntToStr(mIndex), mIndex < AInterfaceSymbols);
  end;
end;

procedure TIndexMemoryTests.PoolReturnsSameStringForEqualValues;
var
  mPool: TStringPool;
  mFirst, mSecond: string;
begin
  mPool := TStringPool.Create;
  try
    mFirst := mPool.Intern(Copy('TObjekt', 1, MaxInt));
    mSecond := mPool.Intern(Copy('TObjekt', 1, MaxInt));
    Assert.AreEqual<Pointer>(Pointer(mSecond), Pointer(mFirst));
    Assert.AreEqual(1, Integer(mPool.Count));
    Assert.AreEqual('', mPool.Intern(''));
  finally
    mPool.Free;
  end;
end;

procedure TIndexMemoryTests.PoolDoesNotChangeCallerArrays;
var
  mPool: TStringPool;
  mOriginal, mPooled: TUnitIndex;
  mBefore: Pointer;
begin
  mPool := TStringPool.Create;
  try
    mPool.Intern(Copy('TObject', 1, MaxInt));
    mOriginal := MakeUnit('A', False, 1, 0);
    mBefore := Pointer(mOriginal.Symbols[0].Ancestors[0]);
    mPooled := mOriginal;
    mPooled.Symbols := Copy(mOriginal.Symbols);
    mPool.InternUnit(mPooled);
    Assert.AreEqual<Pointer>(Pointer(mOriginal.Symbols[0].Ancestors[0]), mBefore);
    Assert.AreEqual('TObject', mPooled.Symbols[0].Ancestors[0]);
  finally
    mPool.Free;
  end;
end;

procedure TIndexMemoryTests.CompactKeepsOnlyInterfaceSymbols;
var
  mCompact: TUnitIndex;
begin
  mCompact := TIndexMemory.Compacted(MakeUnit('A', True, 2, 3));
  Assert.IsTrue(mCompact.Compact);
  Assert.AreEqual(2, Integer(Length(mCompact.Symbols)));
  Assert.IsTrue(mCompact.Symbols[0].InInterface and mCompact.Symbols[1].InInterface);
  Assert.AreEqual(1, Integer(Length(mCompact.ImplementationUses)));
end;

procedure TIndexMemoryTests.UnitBytesGrowWithSymbols;
begin
  Assert.IsTrue(TIndexMemory.UnitBytes(MakeUnit('A', False, 10, 0)) > TIndexMemory.UnitBytes(MakeUnit('A', False, 1, 0)));
  Assert.IsTrue(TIndexMemory.UnitBytes(Default(TUnitIndex)) > 0);
end;

procedure TIndexMemoryTests.IndexTracksMemoryBytes;
var
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  Assert.AreEqual<Int64>(0, mIndex.MemoryBytes);
  mIndex.AddUnit(MakeUnit('A', False, 5, 5));
  Assert.AreEqual<Int64>(TIndexMemory.UnitBytes(MakeUnit('A', False, 5, 5)), mIndex.MemoryBytes);
  mIndex.AddUnit(MakeUnit('A', False, 5, 5));
  Assert.AreEqual<Int64>(TIndexMemory.UnitBytes(MakeUnit('A', False, 5, 5)), mIndex.MemoryBytes);
  mIndex.RemoveFile('C:\Quelle\A.pas');
  Assert.AreEqual<Int64>(0, mIndex.MemoryBytes);
end;

function WithUsages(const AUnit: TUnitIndex): TUnitIndex;
var
  mUsage: TIndexUsage;
begin
  Result := AUnit;
  mUsage := Default(TIndexUsage);
  mUsage.Name := 'TVerwendet';
  Result.Usages := [mUsage, mUsage];
end;

procedure TIndexMemoryTests.MemoryPartsSplitIndex;
var
  mIndex: ISymbolIndex;
  mProject, mLibrary: TUnitIndex;
  mParts: TIndexMemoryParts;
begin
  mProject := WithUsages(MakeUnit('A', False, 3, 2));
  mLibrary := WithUsages(MakeUnit('B', True, 4, 0));
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(mProject);
  mIndex.AddUnit(mLibrary);
  mParts := mIndex.MemoryParts;
  Assert.AreEqual<Int64>(TIndexMemory.UnitBytes(mProject) - TIndexMemory.UsageBytes(mProject), mParts.ProjectBytes);
  Assert.AreEqual<Int64>(TIndexMemory.UnitBytes(mLibrary) - TIndexMemory.UsageBytes(mLibrary), mParts.LibraryBytes);
  Assert.AreEqual<Int64>(TIndexMemory.UsageBytes(mProject) + TIndexMemory.UsageBytes(mLibrary), mParts.UsageBytes);
  Assert.IsTrue(mParts.UsageBytes > 0);
  Assert.AreEqual<Int64>(mIndex.MemoryBytes, mParts.ProjectBytes + mParts.LibraryBytes + mParts.UsageBytes);
  // Budget erzwingt das Auslagern: die Verwendungen verschwinden, die Summe stimmt weiter.
  mIndex.SetBudget(1);
  mIndex.AddUnit(MakeUnit('C', False, 1, 0));
  mParts := mIndex.MemoryParts;
  Assert.AreEqual<Int64>(0, mParts.UsageBytes);
  Assert.AreEqual<Int64>(mIndex.MemoryBytes, mParts.ProjectBytes + mParts.LibraryBytes + mParts.UsageBytes);
  mIndex.RemoveFile(mProject.FileName);
  mIndex.RemoveFile(mLibrary.FileName);
  mIndex.RemoveFile('C:\Quelle\C.pas');
  mParts := mIndex.MemoryParts;
  Assert.AreEqual<Int64>(0, mParts.ProjectBytes + mParts.LibraryBytes + mParts.UsageBytes);
end;

procedure TIndexMemoryTests.WithoutBudgetNothingIsCompacted;
var
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('A', True, 5, 50));
  Assert.AreEqual(0, mIndex.CompactCount);
  Assert.AreEqual(55, mIndex.SymbolCount);
end;

procedure TIndexMemoryTests.CompactsLibraryUnitsFirst;
var
  mIndex: ISymbolIndex;
  mFound: TUnitIndex;
  mFull: Int64;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('Projekt', False, 5, 50));
  mIndex.AddUnit(MakeUnit('Vcl', True, 5, 50));
  mFull := mIndex.MemoryBytes;
  mIndex.SetBudget(mFull - 1);
  Assert.IsTrue(mIndex.MemoryBytes <= mFull - 1);
  Assert.IsTrue(mIndex.FindUnit('Vcl', mFound) and mFound.Compact);
  Assert.IsTrue(mIndex.FindUnit('Projekt', mFound) and not mFound.Compact);
  Assert.AreEqual(1, mIndex.CompactCount);
  Assert.AreEqual(60, mIndex.SymbolCount);
end;

procedure TIndexMemoryTests.CompactsProjectUnitsWhenLibrariesAreNotEnough;
var
  mIndex: ISymbolIndex;
  mFound: TUnitIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.SetBudget(TIndexMemory.UnitBytes(MakeUnit('Projekt', False, 5, 50)));
  mIndex.AddUnit(MakeUnit('Projekt', False, 5, 50));
  Assert.AreEqual(0, mIndex.CompactCount);
  mIndex.AddUnit(MakeUnit('Vcl', True, 5, 50));
  Assert.IsTrue(mIndex.FindUnit('Projekt', mFound) and mFound.Compact);
  Assert.IsTrue(mIndex.FindUnit('Vcl', mFound) and mFound.Compact);
  Assert.AreNotEqual(0, Integer(Length(mIndex.FindSymbols('VclSymbol0'))));
  Assert.AreEqual(0, Integer(Length(mIndex.FindSymbols('VclSymbol10'))));
end;

procedure TIndexMemoryTests.KeepsProjectUsagesWhileLibrariesAreEnough;
var
  mIndex: ISymbolIndex;
  mFound: TUnitIndex;
  mFull: Int64;
begin
  // Ohne die Verwendungen der Projekt-Units liest unused-public-member jede Datei der Gruppe (Abbrüche in
  // 2.0-stable): Reicht das Kompakthalten der Bibliotheken, bleiben sie im Speicher.
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(WithUsages(MakeUnit('Projekt', False, 5, 5)));
  mIndex.AddUnit(MakeUnit('Vcl', True, 5, 50));
  mFull := mIndex.MemoryBytes;
  mIndex.SetBudget(mFull - 1);
  Assert.IsTrue(mIndex.MemoryBytes <= mFull - 1);
  Assert.IsTrue(mIndex.FindUnit('Vcl', mFound) and mFound.Compact);
  Assert.IsTrue(mIndex.FindUnit('Projekt', mFound) and not mFound.Compact);
  Assert.AreEqual(2, Integer(Length(mFound.Usages)));
  Assert.IsTrue(mIndex.MemoryParts.UsageBytes > 0);
end;

procedure TIndexMemoryTests.MillionLinesStayBelowBudget;
const
  // Grob 1 Mio. Zeilen: 2000 Units mit je 500 Zeilen und 60 Symbolen.
  cUnitCount = 2000;
  cBudget = 16 * 1024 * 1024;
var
  mIndex: ISymbolIndex;
  mNumber: Integer;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.SetBudget(cBudget);
  for mNumber := 1 to cUnitCount do
  begin
    mIndex.AddUnit(MakeUnit('Unit' + IntToStr(mNumber), mNumber mod 2 = 0, 15, 45));
  end;
  Assert.AreEqual(cUnitCount, mIndex.UnitCount);
  Assert.IsTrue(mIndex.MemoryBytes <= cBudget, Format('%d > %d', [mIndex.MemoryBytes, Int64(cBudget)]));
  Assert.IsTrue(mIndex.CompactCount > 0);
end;

procedure TIndexMemoryTests.CacheKeepsLibraryAndCompactFlags;
var
  mUnits: TArray<TUnitIndex>;
  mLibraryUnit, mCompactUnit: TUnitIndex;
begin
  // Erst in Variablen: Temporäre Records mit verwalteten Feldern im offenen
  // Array-Konstruktor gibt der Compiler nicht zuverlässig frei.
  mLibraryUnit := MakeUnit('A', True, 1, 0);
  mCompactUnit := TIndexMemory.Compacted(MakeUnit('B', False, 1, 1));
  mUnits := TIndexCache.Deserialize(TIndexCache.Serialize([mLibraryUnit, mCompactUnit]));
  Assert.AreEqual(2, Integer(Length(mUnits)));
  Assert.IsTrue(mUnits[0].Library_ and not mUnits[0].Compact);
  Assert.IsTrue(mUnits[1].Compact and not mUnits[1].Library_);
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexMemoryTests);

end.
