unit Atlas.Common.Index.Files.Tests;

// Tests für TIndexFiles.UnitOf (#500): eigene Datei, per $I eingebundene
// Datei, ohne Index.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexFilesTests = class
  public
    [Test]
    procedure UnitOfFindsOwnFile;
    [Test]
    procedure UnitOfFindsIncludingUnit;
    [Test]
    procedure UnitOfWithoutIndexIsFalse;
  end;

implementation

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Files;

function SampleIndex: ISymbolIndex;
var
  U: TUnitIndex;
begin
  U := Default(TUnitIndex);
  U.UnitName := 'Kunde';
  U.FileName := 'C:\x\Kunde.pas';
  U.Includes := ['C:\x\inc.inc'];
  Result := TSymbolIndex.Create;
  Result.AddUnit(U);
end;

procedure TIndexFilesTests.UnitOfFindsOwnFile;
var
  Found: TUnitIndex;
begin
  Assert.IsTrue(TIndexFiles.UnitOf(SampleIndex, 'C:\x\Kunde.pas', Found));
  Assert.AreEqual('Kunde', Found.UnitName);
end;

procedure TIndexFilesTests.UnitOfFindsIncludingUnit;
var
  Found: TUnitIndex;
begin
  Assert.IsTrue(TIndexFiles.UnitOf(SampleIndex, 'C:\X\INC.inc', Found));
  Assert.AreEqual('Kunde', Found.UnitName);
  Assert.IsFalse(TIndexFiles.UnitOf(SampleIndex, 'C:\x\andere.inc', Found));
end;

procedure TIndexFilesTests.UnitOfWithoutIndexIsFalse;
var
  Found: TUnitIndex;
begin
  Assert.IsFalse(TIndexFiles.UnitOf(nil, 'C:\x\Kunde.pas', Found));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexFilesTests);

end.
