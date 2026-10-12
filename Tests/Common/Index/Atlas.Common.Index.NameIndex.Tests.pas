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
  Index: ISymbolIndex;
  Names: TImportNameIndex;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('Bib', True, [Symbol('TBib', '', True)]));
  Index.AddUnit(MakeUnit('Proj', False, [Symbol('TProj', '', True), Symbol('Feld', 'TProj', True),
    Symbol('Intern', '', False)]));
  Names := TImportNameIndex.Build(Index);
  Assert.AreEqual(2, Names.Count);
  Assert.AreEqual('TProj', Names.Units[Names.Entries[0].UnitPos].Symbols[Names.Entries[0].SymbolPos].Name);
  Assert.AreEqual('TBib', Names.Units[Names.Entries[1].UnitPos].Symbols[Names.Entries[1].SymbolPos].Name);
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
  Index: ISymbolIndex;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(MakeUnit('A', False, [Symbol('TA', '', True)]));
  Assert.AreEqual(1, TImportNames.Current(Index).Count);
  Index.AddUnit(MakeUnit('B', False, [Symbol('TB', '', True)]));
  Assert.AreEqual(2, TImportNames.Current(Index).Count);
  // Ein neuer Index an möglicherweise derselben Adresse wird nicht mit dem alten verwechselt.
  Index := TSymbolIndex.Create;
  Assert.AreEqual(0, TImportNames.Current(Index).Count);
end;

initialization
  TDUnitX.RegisterTestFixture(TImportNameIndexTests);

end.
