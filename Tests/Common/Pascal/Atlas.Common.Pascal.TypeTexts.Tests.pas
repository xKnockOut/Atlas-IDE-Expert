unit Atlas.Common.Pascal.TypeTexts.Tests;

// Tests für Typtexte ohne Index: Elementtyp, Typfamilien, generische Bindungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalTypeTextsTests = class
  public
    [Test]
    procedure ElementTypes;
    [Test]
    procedure StringAndPointerTypes;
    [Test]
    procedure BooleanTypes;
    [Test]
    procedure SubstitutesBindings;
    [Test]
    procedure GenericNames;
    [Test]
    procedure NamesFromTypes;
  end;

implementation

uses
  Atlas.Common.Pascal.TypeTexts;

{ TPascalTypeTextsTests }

procedure TPascalTypeTextsTests.ElementTypes;
begin
  Assert.AreEqual('Integer', TPascalTypeTexts.ElementOf('TArray<Integer>'));
  Assert.AreEqual('TPair<string, Integer>', TPascalTypeTexts.ElementOf('TArray<TPair<string, Integer>>'));
  Assert.AreEqual('string', TPascalTypeTexts.ElementOf('array of string'));
  Assert.AreEqual('Byte', TPascalTypeTexts.ElementOf('array[0..9] of Byte'));
  Assert.AreEqual('TFarbe', TPascalTypeTexts.ElementOf('set of TFarbe'));
  Assert.AreEqual('', TPascalTypeTexts.ElementOf('array of const'));
  Assert.AreEqual('', TPascalTypeTexts.ElementOf('TStringList'));
end;

procedure TPascalTypeTextsTests.StringAndPointerTypes;
begin
  Assert.IsTrue(TPascalTypeTexts.IsStringType('string'));
  Assert.IsTrue(TPascalTypeTexts.IsStringType('AnsiString'));
  Assert.IsFalse(TPascalTypeTexts.IsStringType('Char'));
  Assert.IsTrue(TPascalTypeTexts.IsPointerType('Pointer'));
  Assert.IsTrue(TPascalTypeTexts.IsPointerType('^TKunde'));
  Assert.IsFalse(TPascalTypeTexts.IsPointerType('TKunde'));
end;

procedure TPascalTypeTextsTests.BooleanTypes;
begin
  Assert.IsTrue(TPascalTypeTexts.IsBooleanType('Boolean'));
  Assert.IsTrue(TPascalTypeTexts.IsBooleanType(' LongBool '));
  Assert.IsFalse(TPascalTypeTexts.IsBooleanType('Integer'));
end;

procedure TPascalTypeTextsTests.SubstitutesBindings;
begin
  Assert.AreEqual('function Compare(const A, B: TKunde): Integer;',
    TPascalTypeTexts.SubstituteWords('function Compare(const A, B: T): Integer;', TArray<string>.Create('T=TKunde')));
  Assert.AreEqual('TList<T>.Count', TPascalTypeTexts.SubstituteWords('TList<T>.Count', nil));
  Assert.AreEqual('System.T', TPascalTypeTexts.SubstituteWords('System.T', TArray<string>.Create('T=TKunde')));
end;

procedure TPascalTypeTextsTests.GenericNames;
begin
  Assert.AreEqual('IComparer<TKunde>', TPascalTypeTexts.GenericName('IComparer', TArray<string>.Create('T=TKunde')));
  Assert.AreEqual('TPair<string, Integer>', TPascalTypeTexts.GenericName('TPair',
    TArray<string>.Create('K=string', 'V=Integer')));
  Assert.AreEqual('IComparer', TPascalTypeTexts.GenericName('IComparer', nil));
end;

procedure TPascalTypeTextsTests.NamesFromTypes;
begin
  Assert.AreEqual('Customer', TPascalTypeTexts.NameFromType('TCustomer'));
  Assert.AreEqual('Exporter', TPascalTypeTexts.NameFromType('IExporter'));
  Assert.AreEqual('List', TPascalTypeTexts.NameFromType('System.Generics.Collections.TList<TKunde>'));
  Assert.AreEqual('Text', TPascalTypeTexts.NameFromType('string'));
  Assert.AreEqual('Value', TPascalTypeTexts.NameFromType('Integer'));
  Assert.AreEqual('Value', TPascalTypeTexts.NameFromType('{Typ}'));
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalTypeTextsTests);

end.
