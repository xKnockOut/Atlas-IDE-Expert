unit Atlas.Common.Index.NameIndex.Tests;

// Tests für den Namensindex der Import-Vorschläge (#617).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TImportNameIndexTests = class
  public
    [Test]
    procedure KeepsOnlyImportableSymbolsProjectFirst;
    [Test]
    procedure MaskRejectsNamesWithoutQueryCharacters;
    [Test]
    procedure CurrentRebuildsAfterIndexChange;
  end;

implementation

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.NameIndex;

function Symbol(const AName, AContainer: string; AInInterface: Boolean): TIndexSymbol;
begin
  Result := Default(TIndexSymbol);
  Result.Name := AName;
  Result.Container := AContainer;
  Result.InInterface := AInInterface;
end;

function MakeUnit(const AName: string; ALibrary: Boolean; const ASymbols: TArray<TIndexSymbol>): TUnitIndex;
begin
  Result := Default(TUnitIndex);
  Result.UnitName := AName;
  Result.FileName := 'C:\' + AName + '.pas';
  Result.Library_ := ALibrary;
  Result.Symbols := ASymbols;
end;

procedure TImportNameIndexTests.KeepsOnlyImportableSymbolsProjectFirst;
var
  mIndex: ISymbolIndex;
  mNames: TImportNameIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('Bib', True, [Symbol('TBib', '', True)]));
  mIndex.AddUnit(MakeUnit('Proj', False, [Symbol('TProj', '', True), Symbol('Feld', 'TProj', True),
    Symbol('Intern', '', False)]));
  mNames := TImportNameIndex.Build(mIndex);
  Assert.AreEqual(2, Integer(mNames.Count));
  Assert.AreEqual('TProj', mNames.Units[mNames.Entries[0].UnitPos].Symbols[mNames.Entries[0].SymbolPos].Name);
  Assert.AreEqual('TBib', mNames.Units[mNames.Entries[1].UnitPos].Symbols[mNames.Entries[1].SymbolPos].Name);
end;

procedure TImportNameIndexTests.MaskRejectsNamesWithoutQueryCharacters;
begin
  Assert.IsTrue(TImportNameIndex.MayMatch(TImportNameIndex.MaskOf('TBButton'), TImportNameIndex.MaskOf('tbb')));
  Assert.IsTrue(TImportNameIndex.MayMatch(TImportNameIndex.MaskOf('Get_Value2'), TImportNameIndex.MaskOf('V_2')));
  Assert.IsFalse(TImportNameIndex.MayMatch(TImportNameIndex.MaskOf('TButton'), TImportNameIndex.MaskOf('Bx')));
  Assert.IsTrue(TImportNameIndex.MayMatch(TImportNameIndex.MaskOf('Egal'), TImportNameIndex.MaskOf('')));
end;

procedure TImportNameIndexTests.CurrentRebuildsAfterIndexChange;
var
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(MakeUnit('A', False, [Symbol('TA', '', True)]));
  Assert.AreEqual(1, TImportNames.Current(mIndex).Count);
  mIndex.AddUnit(MakeUnit('B', False, [Symbol('TB', '', True)]));
  Assert.AreEqual(2, TImportNames.Current(mIndex).Count);
  // Ein neuer Index an möglicherweise derselben Adresse wird nicht mit dem alten verwechselt.
  mIndex := TSymbolIndex.Create;
  Assert.AreEqual(0, TImportNames.Current(mIndex).Count);
end;

initialization
  TDUnitX.RegisterTestFixture(TImportNameIndexTests);

end.
