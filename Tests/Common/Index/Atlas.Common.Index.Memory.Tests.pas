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

function MakeUnit(const AName: string; ALibrary: Boolean; AInterfaceSymbols, AImplementationSymbols: Integer): TUnitIndex;
var
  Index: Integer;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AName;
  Result.FileName := 'C:\Quelle\' + AName + '.pas';
  Result.Library_ := ALibrary;
  Result.InterfaceUses := ['System.SysUtils'];
  Result.ImplementationUses := ['System.Classes'];
  SetLength(Result.Symbols, AInterfaceSymbols + AImplementationSymbols);
  for Index := 0 to High(Result.Symbols) do
    Result.Symbols[Index] := MakeSymbol(AName + 'Symbol' + IntToStr(Index), Index < AInterfaceSymbols);
end;

procedure TIndexMemoryTests.PoolReturnsSameStringForEqualValues;
var
  Pool: TStringPool;
  First, Second: string;
begin
  Pool := TStringPool.Create;
  try
    First := Pool.Intern(Copy('TObjekt', 1, MaxInt));
    Second := Pool.Intern(Copy('TObjekt', 1, MaxInt));
    Assert.IsTrue(Pointer(First) = Pointer(Second));
    Assert.AreEqual(1, Integer(Pool.Count));
    Assert.AreEqual('', Pool.Intern(''));
  finally
    Pool.Free;
  end;
end;

procedure TIndexMemoryTests.PoolDoesNotChangeCallerArrays;
var
  Pool: TStringPool;
  Original, Pooled: TUnitIndex;
  Before: Pointer;
begin
  Pool := TStringPool.Create;
  try
    Pool.Intern(Copy('TObject', 1, MaxInt));
    Original := MakeUnit('A', False, 1, 0);
    Before := Pointer(Original.Symbols[0].Ancestors[0]);
    Pooled := Original;
    Pooled.Symbols := Copy(Original.Symbols);
    Pool.InternUnit(Pooled);
    Assert.IsTrue(Before = Pointer(Original.Symbols[0].Ancestors[0]));
    Assert.AreEqual('TObject', Pooled.Symbols[0].Ancestors[0]);
  finally
    Pool.Free;
  end;
end;

procedure TIndexMemoryTests.CompactKeepsOnlyInterfaceSymbols;
var
  Compact: TUnitIndex;
begin
  Compact := TIndexMemory.Compacted(MakeUnit('A', True, 2, 3));
  Assert.IsTrue(Compact.Compact);
  Assert.AreEqual(2, Integer(Length(Compact.Symbols)));
  Assert.IsTrue(Compact.Symbols[0].InInterface and Compact.Symbols[1].InInterface);
  Assert.AreEqual(1, Integer(Length(Compact.ImplementationUses)));
end;

procedure TIndexMemoryTests.UnitBytesGrowWithSymbols;
begin
  Assert.IsTrue(TIndexMemory.UnitBytes(MakeUnit('A', False, 10, 0)) > TIndexMemory.UnitBytes(MakeUnit('A', False, 1, 0)));
  Assert.IsTrue(TIndexMemory.UnitBytes(Default(TUnitIndex)) > 0);
end;

procedure TIndexMemoryTests.IndexTracksMemoryBytes;
var
  Index: ISymbolIndex;
begin
  Index := TSymbolIndex.Create;
  Assert.AreEqual<Int64>(0, Index.MemoryBytes);
  Index.AddUnit(MakeUnit('A', False, 5, 5));
  Assert.AreEqual<Int64>(TIndexMemory.UnitBytes(MakeUnit('A', False, 5, 5)), Index.MemoryBytes);
  Index.AddUnit(MakeUnit('A', False, 5, 5));
  Assert.AreEqual<Int64>(TIndexMemory.UnitBytes(MakeUnit('A', False, 5, 5)), Index.MemoryBytes);
  Index.RemoveFile('C:\Quelle\A.pas');
  Assert.AreEqual<Int64>(0, Index.MemoryBytes);
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
  Index: ISymbolIndex;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('A', True, 5, 50));
  Assert.AreEqual(0, Index.CompactCount);
  Assert.AreEqual(55, Index.SymbolCount);
end;

procedure TIndexMemoryTests.CompactsLibraryUnitsFirst;
var
  Index: ISymbolIndex;
  Found: TUnitIndex;
  Full: Int64;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('Projekt', False, 5, 50));
  Index.AddUnit(MakeUnit('Vcl', True, 5, 50));
  Full := Index.MemoryBytes;
  Index.SetBudget(Full - 1);
  Assert.IsTrue(Index.MemoryBytes <= Full - 1);
  Assert.IsTrue(Index.FindUnit('Vcl', Found) and Found.Compact);
  Assert.IsTrue(Index.FindUnit('Projekt', Found) and not Found.Compact);
  Assert.AreEqual(1, Index.CompactCount);
  Assert.AreEqual(60, Index.SymbolCount);
end;

procedure TIndexMemoryTests.CompactsProjectUnitsWhenLibrariesAreNotEnough;
var
  Index: ISymbolIndex;
  Found: TUnitIndex;
begin
  Index := TSymbolIndex.Create;
  Index.SetBudget(TIndexMemory.UnitBytes(MakeUnit('Projekt', False, 5, 50)));
  Index.AddUnit(MakeUnit('Projekt', False, 5, 50));
  Assert.AreEqual(0, Index.CompactCount);
  Index.AddUnit(MakeUnit('Vcl', True, 5, 50));
  Assert.IsTrue(Index.FindUnit('Projekt', Found) and Found.Compact);
  Assert.IsTrue(Index.FindUnit('Vcl', Found) and Found.Compact);
  Assert.IsTrue(Index.FindSymbols('VclSymbol0') <> nil);
  Assert.IsTrue(Index.FindSymbols('VclSymbol10') = nil);
end;

procedure TIndexMemoryTests.MillionLinesStayBelowBudget;
const
  // Grob 1 Mio. Zeilen: 2000 Units mit je 500 Zeilen und 60 Symbolen.
  UnitCount = 2000;
  Budget = 16 * 1024 * 1024;
var
  Index: ISymbolIndex;
  Number: Integer;
begin
  Index := TSymbolIndex.Create;
  Index.SetBudget(Budget);
  for Number := 1 to UnitCount do
    Index.AddUnit(MakeUnit('Unit' + IntToStr(Number), Number mod 2 = 0, 15, 45));
  Assert.AreEqual(UnitCount, Index.UnitCount);
  Assert.IsTrue(Index.MemoryBytes <= Budget, Format('%d > %d', [Index.MemoryBytes, Int64(Budget)]));
  Assert.IsTrue(Index.CompactCount > 0);
end;

procedure TIndexMemoryTests.CacheKeepsLibraryAndCompactFlags;
var
  Units: TArray<TUnitIndex>;
  LibraryUnit, CompactUnit: TUnitIndex;
begin
  // Erst in Variablen: Temporäre Records mit verwalteten Feldern im offenen
  // Array-Konstruktor gibt der Compiler nicht zuverlässig frei.
  LibraryUnit := MakeUnit('A', True, 1, 0);
  CompactUnit := TIndexMemory.Compacted(MakeUnit('B', False, 1, 1));
  Units := TIndexCache.Deserialize(TIndexCache.Serialize([LibraryUnit, CompactUnit]));
  Assert.AreEqual(2, Integer(Length(Units)));
  Assert.IsTrue(Units[0].Library_ and not Units[0].Compact);
  Assert.IsTrue(Units[1].Compact and not Units[1].Library_);
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexMemoryTests);

end.
