unit Atlas.Common.Semantics.ConstantValues.Tests;

// Tests der Konstantenwerte einer Datei (#983, #1011): Zahlen, eigene und
// fremde Konstanten, Aufzählungswerte, Werte einer Aufzählung in Reihenfolge,
// Wertebereiche der eingebauten Ganzzahltypen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConstantValuesTests = class
  public
    [Test]
    procedure ConstantsAndEnumValues;
    [Test]
    procedure EnumMembersInOrder;
    [Test]
    procedure IntegerRanges;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.ConstantValues;

function FarbenIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit Farben;'#10'interface'#10'const'#10'  Basis = 10;'#10 +
    '  Grenze = Basis * 2 + 1;'#10'type'#10'  TFarbe = (fRot, fGruen, fBlau);'#10 +
    '  TCode = (cA = 1, cB = 5);'#10'implementation'#10'end.', 'C:\Projekt\Farben.pas', nil));
end;

/// <summary>Erster Knoten der Art AKind mit dem Namen AName (bei Konstanten der Wert dahinter).</summary>
function FindDecl(ANode: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.ConstDecl) and SameText(ANode.Name, AName) then
    Exit(ANode[ANode.ChildCount - 1]);
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindDecl(ANode[Index], AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

const
  Source = 'unit Probe;'#10'interface'#10'uses'#10'  Farben;'#10'implementation'#10'const'#10 +
    '  Eigen = 3;'#10'  A = Grenze - Eigen;'#10'  B = Ord(fBlau) + 1;'#10'  C = Ord(cB);'#10'  D = Unbekannt + 1;'#10 +
    'end.';

procedure TConstantValuesTests.ConstantsAndEnumValues;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Values: TConstantValues;
  Value: Int64;
begin
  Tree := TPascalParser.Parse(Source);
  Resolver := TNameResolver.Create(FarbenIndex);
  try
    Resolver.PinTree(Tree, 'Probe.pas');
    Values := TConstantValues.Create(Tree, 'Probe.pas', FarbenIndex, Resolver);
    try
      Assert.IsTrue(Values.EvaluateNode(FindDecl(Tree.Root, 'A'), Value));
      Assert.AreEqual(Int64(18), Value);
      Assert.IsTrue(Values.EvaluateNode(FindDecl(Tree.Root, 'B'), Value));
      Assert.AreEqual(Int64(3), Value);
      // Eigene Werte (cB = 5): Position nicht sicher.
      Assert.IsFalse(Values.EvaluateNode(FindDecl(Tree.Root, 'C'), Value));
      Assert.IsFalse(Values.EvaluateNode(FindDecl(Tree.Root, 'D'), Value));
      Assert.IsFalse(Values.EvaluateNode(nil, Value));
    finally
      Values.Free;
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TConstantValuesTests.EnumMembersInOrder;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Values: TConstantValues;
  Index: ISymbolIndex;
  Farbe, Code: TResolvedSymbol;
  Names: TArray<string>;
  Units: TUnitIndex;
begin
  Index := FarbenIndex;
  Tree := TPascalParser.Parse(Source);
  Resolver := TNameResolver.Create(Index);
  try
    Resolver.PinTree(Tree, 'Probe.pas');
    Values := TConstantValues.Create(Tree, 'Probe.pas', Index, Resolver);
    try
      Assert.IsTrue(Index.FindUnit('Farben', Units));
      Assert.IsTrue(Resolver.ResolveTypeFrom(Units, 'TFarbe', Farbe));
      Assert.IsTrue(Values.EnumMembers(Farbe, Names));
      Assert.AreEqual('fRot,fGruen,fBlau', string.Join(',', Names));
      Assert.IsTrue(Resolver.ResolveTypeFrom(Units, 'TCode', Code));
      Assert.IsFalse(Values.EnumMembers(Code, Names));
    finally
      Values.Free;
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TConstantValuesTests.IntegerRanges;
var
  LowValue, HighValue: Int64;
begin
  Assert.IsTrue(TConstantValues.IntegerRange('Byte', LowValue, HighValue));
  Assert.AreEqual(Int64(0), LowValue);
  Assert.AreEqual(Int64(255), HighValue);
  Assert.IsTrue(TConstantValues.IntegerRange('smallint', LowValue, HighValue));
  Assert.AreEqual(Int64(-32768), LowValue);
  Assert.IsTrue(TConstantValues.IntegerRange('Cardinal', LowValue, HighValue));
  Assert.AreEqual(Int64(4294967295), HighValue);
  Assert.IsTrue(TConstantValues.IntegerRange('Integer', LowValue, HighValue));
  Assert.AreEqual(Int64(-2147483648), LowValue);
  // Plattformabhängig: weitester Bereich.
  Assert.IsTrue(TConstantValues.IntegerRange('LongInt', LowValue, HighValue));
  Assert.AreEqual(Int64(High(Int64)), HighValue);
  Assert.IsTrue(TConstantValues.IntegerRange('NativeUInt', LowValue, HighValue));
  Assert.AreEqual(Int64(0), LowValue);
  Assert.IsFalse(TConstantValues.IntegerRange('Double', LowValue, HighValue));
  Assert.IsFalse(TConstantValues.IntegerRange('Char', LowValue, HighValue));
end;

initialization
  TDUnitX.RegisterTestFixture(TConstantValuesTests);

end.
