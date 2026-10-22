unit Atlas.Common.Index.LibraryUnits.Tests;

// Tests für TLibraryUnits (#980): Namen von RTL, VCL und Bibliotheken,
// Markierung Library_ des Index, ohne Index.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLibraryUnitsTests = class
  public
    [Test]
    procedure RecognizesLibraryNames;
    [Test]
    procedure ProjectNamesAreNoLibrary;
    [Test]
    procedure IndexFlagMarksLibrary;
    [Test]
    procedure WithoutIndexOnlyNames;
  end;

implementation

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.LibraryUnits;

function SampleIndex: ISymbolIndex;
var
  U: TUnitIndex;
begin
  Result := TSymbolIndex.Create;
  U := Default(TUnitIndex);
  U.UnitName := 'cxGrid';
  U.FileName := 'C:\lib\cxGrid.pas';
  U.Library_ := True;
  Result.AddUnit(U);
  U := Default(TUnitIndex);
  U.UnitName := 'Kunde';
  U.FileName := 'C:\x\Kunde.pas';
  Result.AddUnit(U);
end;

procedure TLibraryUnitsTests.RecognizesLibraryNames;
begin
  Assert.IsTrue(TLibraryUnits.IsLibraryUnit('System.SysUtils'));
  Assert.IsTrue(TLibraryUnits.IsLibraryUnit('vcl.forms'));
  Assert.IsTrue(TLibraryUnits.IsLibraryUnit('System'));
  Assert.IsTrue(TLibraryUnits.IsLibraryUnit('Vcl'));
  Assert.IsTrue(TLibraryUnits.IsLibraryUnit('FireDAC.Comp.Client'));
  Assert.IsTrue(TLibraryUnits.IsLibraryUnit('Posix.Unistd'));
end;

procedure TLibraryUnitsTests.ProjectNamesAreNoLibrary;
begin
  Assert.IsFalse(TLibraryUnits.IsLibraryUnit('SystemTools'));
  Assert.IsFalse(TLibraryUnits.IsLibraryUnit('MyApp.Main'));
  Assert.IsFalse(TLibraryUnits.IsLibraryUnit(''));
end;

procedure TLibraryUnitsTests.IndexFlagMarksLibrary;
var
  Index: ISymbolIndex;
begin
  Index := SampleIndex;
  Assert.IsTrue(TLibraryUnits.IsLibrary(Index, 'cxGrid'));
  Assert.IsFalse(TLibraryUnits.IsLibrary(Index, 'Kunde'));
  Assert.IsTrue(TLibraryUnits.IsLibrary(Index, 'Vcl.Forms'));
  Assert.IsFalse(TLibraryUnits.IsLibrary(Index, 'Unbekannt'));
end;

procedure TLibraryUnitsTests.WithoutIndexOnlyNames;
begin
  Assert.IsFalse(TLibraryUnits.IsLibrary(nil, 'cxGrid'));
  Assert.IsTrue(TLibraryUnits.IsLibrary(nil, 'System.Classes'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLibraryUnitsTests);

end.
