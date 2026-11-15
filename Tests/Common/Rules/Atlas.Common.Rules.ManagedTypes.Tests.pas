unit Atlas.Common.Rules.ManagedTypes.Tests;

// Tests für die Auflösung verwalteter Typen der Prüfregeln (#921, #1071); tief verschachtelte Records ohne
// exponentielle Laufzeit.

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
    [Test]
    procedure NestedRecordChains;
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
  cSource = 'unit U;'#10'interface'#10'type'#10'  TName = record'#10'    S: string;'#10'  end;'#10 +
    '  TAlias = TName;'#10'  TLeer = record'#10'    N: Integer;'#10'  end;'#10'  TZaehler = record'#10 +
    '    class operator Initialize(out ADest: TZaehler);'#10'  end;'#10'  THuelle = record'#10 +
    '    Z: array[0..1] of TZaehler;'#10'  end;'#10'  TLeser = reference to function(const A: string): Boolean;'#10 +
    '  TEreignis = procedure of object;'#10'implementation'#10'end.';

procedure Check(const AIndex: ISymbolIndex; const AProc: TProc<TManagedTypes>);
var
  mTree: TSyntaxTree;
  mTypes: TManagedTypes;
begin
  mTree := TPascalParser.Parse(cSource);
  mTypes := TManagedTypes.Create(mTree, cSource, AIndex);
  try
    AProc(mTypes);
  finally
    mTypes.Free;
    mTree.Free;
  end;
end;

{ TManagedTypesTests }

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
      // Methodenreferenzen sind Interfaces, Methodenzeiger nicht.
      Assert.AreEqual('Methodenreferenzen', ATypes.Managed('TLeser', 0));
      Assert.AreEqual('Methodenreferenzen', ATypes.Managed('reference to procedure', 0));
      Assert.AreEqual('', ATypes.Managed('TEreignis', 0));
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
  mIndex: ISymbolIndex;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Fremd;'#10'interface'#10'type'#10'  TFremd = record'#10 +
    '    Liste: TArray<Integer>;'#10'  end;'#10'  TFremdAlias = TFremd;'#10'  TFremdZaehler = record'#10 +
    '    class operator Finalize(var ADest: TFremdZaehler);'#10'  end;'#10'  IFremd = interface'#10'  end;'#10 +
    '  TFremdRueckruf = reference to procedure(A: Integer);'#10'  TFremdZeiger = procedure(A: Integer);'#10 +
    'implementation'#10'end.', 'C:\P\Fremd.pas', nil));
  Check(mIndex,
    procedure(ATypes: TManagedTypes)
    begin
      Assert.AreEqual('dynamische Arrays', ATypes.Managed('TFremd', 0));
      Assert.AreEqual('dynamische Arrays', ATypes.Managed('TFremdAlias', 0));
      Assert.AreEqual('Interfaces', ATypes.Managed('IFremd', 0));
      Assert.AreEqual('Methodenreferenzen', ATypes.Managed('TFremdRueckruf', 0));
      Assert.AreEqual('', ATypes.Managed('TFremdZeiger', 0));
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

procedure TManagedTypesTests.NestedRecordChains;
var
  mSource: string;
  mIndex: Integer;
  mTree: TSyntaxTree;
  mTypes: TManagedTypes;
begin
  // Je vier Felder des vorigen Records: ohne gemerkte Antworten 4^16 Durchläufe bis zur Tiefengrenze (Hänger in
  // Header-Übersetzungen). TS hat einen String ganz unten, TP nur Zahlen.
  mSource := 'unit U;'#10'interface'#10'type'#10'  TS0 = record S: string; end;'#10'  TP0 = record N: Integer; end;'#10;
  for mIndex := 1 to 30 do
  begin
    mSource := mSource + Format('  TS%0:d = record A, B, C: Integer; D: TS%1:d; end;'#10, [mIndex, mIndex - 1]) +
      Format('  TP%0:d = record A: TP%1:d; B: TP%1:d; C: TP%1:d; D: TP%1:d; end;'#10, [mIndex, mIndex - 1]);
  end;
  mSource := mSource + 'implementation'#10'end.';
  mTree := TPascalParser.Parse(mSource);
  mTypes := TManagedTypes.Create(mTree, mSource, nil);
  try
    Assert.AreEqual('Strings', mTypes.Managed('TS10', 0));
    Assert.AreEqual('', mTypes.Managed('TP30', 0));
    Assert.IsFalse(mTypes.CustomManaged('TP30', 0));
  finally
    mTypes.Free;
    mTree.Free;
  end;
  mSource := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TManagedTypesTests);

end.
