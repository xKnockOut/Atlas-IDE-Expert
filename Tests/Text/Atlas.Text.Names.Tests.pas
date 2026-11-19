unit Atlas.Text.Names.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTextNamesTests = class
  public
    [Test]
    procedure LastPartBehindLastDot;
    [Test]
    procedure QualifiedWithoutContainer;
    [Test]
    procedure UnitNameOnlyForPas;
    [Test]
    procedure PascalFileByExtension;
  end;

implementation

uses
  Atlas.Text.Names;

{ TTextNamesTests }

procedure TTextNamesTests.LastPartBehindLastDot;
begin
  Assert.AreEqual('Run', TTextNames.LastPart('Unit1.TWorker.Run'));
  Assert.AreEqual('Run', TTextNames.LastPart('Run'));
  Assert.AreEqual('', TTextNames.LastPart('TWorker.'));
end;

procedure TTextNamesTests.QualifiedWithoutContainer;
begin
  Assert.AreEqual('TFoo.Bar', TTextNames.Qualified('TFoo', 'Bar'));
  Assert.AreEqual('Bar', TTextNames.Qualified('', 'Bar'));
end;

procedure TTextNamesTests.UnitNameOnlyForPas;
begin
  Assert.AreEqual('Firma.Kunden', TTextNames.UnitNameOf('Src/Firma.Kunden.PAS'));
  Assert.AreEqual('', TTextNames.UnitNameOf('Projekt.dpr'));
end;

procedure TTextNamesTests.PascalFileByExtension;
begin
  Assert.IsTrue(TTextNames.IsPascalFile('A.PAS'));
  Assert.IsTrue(TTextNames.IsPascalFile('App.dpr'));
  Assert.IsTrue(TTextNames.IsPascalFile('Pkg.dpk'));
  Assert.IsFalse(TTextNames.IsPascalFile('Main.dfm'));
  Assert.IsFalse(TTextNames.IsPascalFile('Ohne'));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextNamesTests);

end.
