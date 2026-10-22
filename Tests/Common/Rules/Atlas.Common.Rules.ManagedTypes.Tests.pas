unit Atlas.Common.Rules.ManagedTypes.Tests;

// Tests für die Auflösung verwalteter Typen der Prüfregeln (#921, #1071).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TManagedTypesTests = class
  public
    [Test]
    procedure PrimitiveAndArrayTypes;
    [Test]
    procedure RecordsAndAliasesInFile;
    [Test]
    procedure CustomManagedRecords;
    [Test]
    procedure TypesFromIndex;
    [Test]
    procedure UnknownTypesAreUnmanaged;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.ManagedTypes;

const
  Source = 'unit U;'#10'interface'#10'type'#10'  TName = record'#10'    S: string;'#10'  end;'#10 +
    '  TAlias = TName;'#10'  TLeer = record'#10'    N: Integer;'#10'  end;'#10'  TZaehler = record'#10 +
    '    class operator Initialize(out ADest: TZaehler);'#10'  end;'#10'  THuelle = record'#10 +
    '    Z: array[0..1] of TZaehler;'#10'  end;'#10'implementation'#10'end.';

procedure Check(const AIndex: ISymbolIndex; const AProc: TProc<TManagedTypes>);
var
  Tree: TSyntaxTree;
  Types: TManagedTypes;
begin
  Tree := TPascalParser.Parse(Source);
  Types := TManagedTypes.Create(Tree, Source, AIndex);
  try
    AProc(Types);
  finally
    Types.Free;
    Tree.Free;
  end;
end;

procedure TManagedTypesTests.PrimitiveAndArrayTypes;
begin
  Check(nil,
    procedure(ATypes: TManagedTypes)
    begin
      Assert.AreEqual('Strings', ATypes.Managed('UnicodeString', 0));
      Assert.AreEqual('Variants', ATypes.Managed('OleVariant', 0));
      Assert.AreEqual('Interfaces', ATypes.Managed('IInterface', 0));
      Assert.AreEqual('dynamische Arrays', ATypes.Managed('TArray<Integer>', 0));
      Assert.AreEqual('Strings', ATypes.Managed('array[0..3] of string', 0));
      Assert.AreEqual('', ATypes.Managed('array[0..3] of Byte', 0));
      Assert.IsTrue(ATypes.IsPrimitive('TBytes'));
      Assert.IsFalse(ATypes.IsPrimitive('TName'));
    end);
end;

procedure TManagedTypesTests.RecordsAndAliasesInFile;
begin
  Check(nil,
    procedure(ATypes: TManagedTypes)
    begin
      Assert.AreEqual('Strings', ATypes.Managed('TName', 0));
      Assert.AreEqual('Strings', ATypes.Managed('TAlias', 0));
      Assert.AreEqual('', ATypes.Managed('TLeer', 0));
      Assert.AreEqual('', ATypes.Managed('TZaehler', 0));
    end);
end;

procedure TManagedTypesTests.CustomManagedRecords;
begin
  Check(nil,
    procedure(ATypes: TManagedTypes)
    begin
      Assert.IsTrue(ATypes.CustomManaged('TZaehler', 0));
      Assert.IsTrue(ATypes.CustomManaged('THuelle', 0));
      Assert.IsTrue(ATypes.CustomManaged('array[1..2] of TZaehler', 0));
      Assert.IsFalse(ATypes.CustomManaged('TName', 0));
      Assert.IsFalse(ATypes.CustomManaged('array of TZaehler', 0));
    end);
end;

procedure TManagedTypesTests.TypesFromIndex;
var
  Index: ISymbolIndex;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Fremd;'#10'interface'#10'type'#10'  TFremd = record'#10 +
    '    Liste: TArray<Integer>;'#10'  end;'#10'  TFremdAlias = TFremd;'#10'  TFremdZaehler = record'#10 +
    '    class operator Finalize(var ADest: TFremdZaehler);'#10'  end;'#10'  IFremd = interface'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\P\Fremd.pas', nil));
  Check(Index,
    procedure(ATypes: TManagedTypes)
    begin
      Assert.AreEqual('dynamische Arrays', ATypes.Managed('TFremd', 0));
      Assert.AreEqual('dynamische Arrays', ATypes.Managed('TFremdAlias', 0));
      Assert.AreEqual('Interfaces', ATypes.Managed('IFremd', 0));
      Assert.IsTrue(ATypes.CustomManaged('TFremdZaehler', 0));
      Assert.IsFalse(ATypes.CustomManaged('TFremd', 0));
    end);
end;

procedure TManagedTypesTests.UnknownTypesAreUnmanaged;
begin
  Check(nil,
    procedure(ATypes: TManagedTypes)
    begin
      Assert.AreEqual('', ATypes.Managed('TUnbekannt', 0));
      Assert.IsFalse(ATypes.CustomManaged('TUnbekannt', 0));
      Assert.AreEqual('', ATypes.Managed('TList<string>', 0));
    end);
end;

initialization
  TDUnitX.RegisterTestFixture(TManagedTypesTests);

end.
