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
    [Test]
    procedure ContainerBeforeLastDot;
    [Test]
    procedure AmpersandOnlyInFront;
    [Test]
    procedure GenericsAndUnitPrefixDropped;
    [Test]
    procedure TypePrefixOnlyBeforeCapital;
    [Test]
    procedure CapitalizedFirstLetter;
    [Test]
    procedure InterfaceByCapitalAfterI;
    [Test]
    procedure CompareIgnoresCaseFirst;
    [Test]
    procedure ListSplitAndSearched;
    [Test]
    procedure SectionKeywords;
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

procedure TTextNamesTests.ContainerBeforeLastDot;
begin
  Assert.AreEqual('Unit1.TWorker', TTextNames.ContainerOf('Unit1.TWorker.Run'));
  Assert.AreEqual('', TTextNames.ContainerOf('Run'));
end;

procedure TTextNamesTests.AmpersandOnlyInFront;
begin
  Assert.AreEqual('Type', TTextNames.WithoutAmpersand('&Type'));
  Assert.AreEqual('A&B', TTextNames.WithoutAmpersand('A&B'));
end;

procedure TTextNamesTests.GenericsAndUnitPrefixDropped;
begin
  Assert.AreEqual('TObjectList', TTextNames.WithoutGenerics(' TObjectList<TOrder> '));
  Assert.AreEqual('System.TList', TTextNames.WithoutGenerics('System.TList<T>'));
  Assert.AreEqual('TList', TTextNames.BareTypeName('System.Generics.Collections.TList<Integer>'));
  Assert.AreEqual('TKunde', TTextNames.BareTypeName('TKunde'));
end;

procedure TTextNamesTests.TypePrefixOnlyBeforeCapital;
begin
  Assert.AreEqual('Kunde', TTextNames.WithoutTypePrefix('TKunde'));
  Assert.AreEqual('Tabelle', TTextNames.WithoutTypePrefix('Tabelle'));
  Assert.AreEqual('T', TTextNames.WithoutTypePrefix('T'));
end;

procedure TTextNamesTests.CapitalizedFirstLetter;
begin
  Assert.AreEqual('Wert', TTextNames.Capitalized('wert'));
  Assert.AreEqual('', TTextNames.Capitalized(''));
end;

procedure TTextNamesTests.InterfaceByCapitalAfterI;
begin
  Assert.IsTrue(TTextNames.LooksLikeInterface('Unit1.IKunde'));
  Assert.IsFalse(TTextNames.LooksLikeInterface('Index'));
  Assert.IsFalse(TTextNames.LooksLikeInterface('I'));
end;

procedure TTextNamesTests.CompareIgnoresCaseFirst;
begin
  Assert.IsTrue(TTextNames.Compare('alpha', 'Beta') < 0);
  Assert.IsTrue(TTextNames.Compare('Beta', 'alpha') > 0);
  Assert.IsTrue(TTextNames.Compare('Name', 'name') <> 0, 'Gleichstand wird nach Groß-/Kleinschreibung entschieden');
  Assert.AreEqual(0, TTextNames.Compare('Name', 'Name'));
end;

procedure TTextNamesTests.ListSplitAndSearched;
var
  mNames: TArray<string>;
begin
  mNames := TTextNames.SplitList(' A, ,B ,');
  Assert.AreEqual(2, Integer(Length(mNames)));
  Assert.AreEqual('A', mNames[0]);
  Assert.AreEqual('B', mNames[1]);
  Assert.IsTrue(TTextNames.InList('FA, FListe,FB', 'fliste'));
  Assert.IsFalse(TTextNames.InList('FA, FListe', 'Liste'));
  mNames := nil;
end;

procedure TTextNamesTests.SectionKeywords;
begin
  Assert.AreEqual('interface', TTextNames.SectionKeyword(True));
  Assert.AreEqual('implementation', TTextNames.SectionKeyword(False));
end;

initialization
  TDUnitX.RegisterTestFixture(TTextNamesTests);

end.
