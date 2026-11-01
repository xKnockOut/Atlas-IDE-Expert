unit Atlas.Core.Hover.Declaration.Tests;

// Tests für den Typ aus der Hover-Deklaration (#835, #1455).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Hover.Declaration;

type
  [TestFixture]
  THoverDeclarationTests = class
  public
    [Test]
    procedure DeclaredTypeFromHover;
  end;

implementation

procedure THoverDeclarationTests.DeclaredTypeFromHover;
begin
  Assert.AreEqual('TObjectList<TKunde>', TAtlasHoverDeclaration.DeclaredType('var Kunden: TObjectList<TKunde>'));
  Assert.AreEqual('TList<Integer>', TAtlasHoverDeclaration.DeclaredType('property Items: TList<Integer> read FItems'));
  Assert.AreEqual('TPoint', TAtlasHoverDeclaration.DeclaredType('function Mitte(A, B: Integer): TPoint;'));
  Assert.AreEqual('TDictionary<string, TKunde>',
    TAtlasHoverDeclaration.DeclaredType('Index: TDictionary<string, TKunde> = nil'));
  Assert.AreEqual('System.SysUtils.TBytes', TAtlasHoverDeclaration.DeclaredType('Daten: System.SysUtils.TBytes;'));
  Assert.AreEqual('array of Byte', TAtlasHoverDeclaration.DeclaredType('Puffer: array of Byte'));
  Assert.AreEqual('TÜbersicht', TAtlasHoverDeclaration.DeclaredType('Ü: TÜbersicht'));
  Assert.AreEqual('', TAtlasHoverDeclaration.DeclaredType('procedure Speichern'));
end;

initialization
  TDUnitX.RegisterTestFixture(THoverDeclarationTests);

end.
