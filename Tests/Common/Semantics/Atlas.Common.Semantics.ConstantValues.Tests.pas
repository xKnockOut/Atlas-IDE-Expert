unit Atlas.Common.Semantics.ConstantValues.Tests;

// Tests von TConstantValues (#983, #992): Konstanten und Aufzählungswerte der
// eigenen Unit und aus dem Index, Check mit Grund, Konstanten aus {$IF}-Zweigen
// und der Tokenbereich eines Knotens; Werte eines Knotens, einer Aufzählung in
// Reihenfolge und Wertebereiche der eingebauten Ganzzahltypen (#1011).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TConstantValuesTests = class
  public
    [Test]
    procedure ConstantsAndEnumsOfOwnUnit;
    [Test]
    procedure ConstantsFromIndex;
    [Test]
    procedure CheckGivesReason;
    [Test]
    procedure ConditionalConstantsNeedSameBranch;
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
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Semantics.ConstantValues;

type
  /// <summary>Ausdruck AName = … der letzten Konstanten im Baum (Wert der Deklaration).</summary>
  TFixture = class
  private
    FTree: TSyntaxTree;
    FResolver: TNameResolver;
    FValues: TConstantValues;
  public
    constructor Create(const ASource: string; const AIndex: ISymbolIndex);
    destructor Destroy; override;
    /// <summary>Wertknoten der Konstanten AName.</summary>
    function ValueNode(const AName: string): TSyntaxNode;
    function Status(const AName: string; out AValue: Int64): TOrdinalStatus;
  end;

constructor TFixture.Create(const ASource: string; const AIndex: ISymbolIndex);
begin
  inherited Create;
  FTree := TPascalParser.Parse(ASource);
  FResolver := TNameResolver.Create(AIndex, nil);
  FResolver.PinTree(FTree, 'Werte.pas');
  FValues := TConstantValues.Create(FTree, 'Werte.pas', AIndex, FResolver);
end;

destructor TFixture.Destroy;
begin
  FValues.Free;
  FResolver.UnpinTree;
  FResolver.Free;
  FTree.Free;
  inherited;
end;

function TFixture.ValueNode(const AName: string): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.ConstDecl) and SameText(ANode.Name, AName) then
        Found := ANode[ANode.ChildCount - 1];
      Result := True;
    end);
  Assert.IsNotNull(Found, AName);
  Result := Found;
end;

function TFixture.Status(const AName: string; out AValue: Int64): TOrdinalStatus;
begin
  Result := FValues.Check(ValueNode(AName), AValue);
end;

function Werte(const ADeclarations: string): string;
begin
  Result := 'unit Werte;'#10'interface'#10 + ADeclarations + 'implementation'#10'end.';
end;

function FarbenIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit Farben;'#10'interface'#10'const'#10'  Basis = 10;'#10 +
    '  Grenze = Basis * 2 + 1;'#10'type'#10'  TFarbe = (fRot, fGruen, fBlau);'#10 +
    '  TCode = (cA = 1, cB = 5);'#10'implementation'#10'end.', 'C:\Projekt\Farben.pas', nil));
end;

/// <summary>Wert der ersten Konstanten AName unter ARoot; nil ohne.</summary>
function FindDecl(ARoot: TSyntaxNode; const AName: string): TSyntaxNode;
var
  Found: TSyntaxNode;
begin
  Found := nil;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (Found = nil) and (ANode.Kind = TSyntaxKind.ConstDecl) and SameText(ANode.Name, AName) then
        Found := ANode[ANode.ChildCount - 1];
      Result := Found = nil;
    end);
  Result := Found;
end;

const
  Source = 'unit Probe;'#10'interface'#10'uses'#10'  Farben;'#10'implementation'#10'const'#10 +
    '  Eigen = 3;'#10'  A = Grenze - Eigen;'#10'  B = Ord(fBlau) + 1;'#10'  C = Ord(cB);'#10'  D = Unbekannt + 1;'#10 +
    'end.';

{ TConstantValuesTests }

procedure TConstantValuesTests.ConstantsAndEnumsOfOwnUnit;
var
  Fixture: TFixture;
  Value: Int64;
begin
  Fixture := TFixture.Create(Werte('type'#10'  TFarbe = (Rot, Gruen, Blau);'#10'const'#10'  Basis = 10;'#10 +
    '  Doppelt = Basis * 2;'#10'  Letzte = Ord(Blau) + Doppelt;'#10'  Text = ''abc'';'#10), nil);
  try
    Assert.AreEqual(Ord(TOrdinalStatus.Value), Ord(Fixture.Status('Doppelt', Value)));
    Assert.AreEqual(Int64(20), Value);
    Assert.AreEqual(Ord(TOrdinalStatus.Value), Ord(Fixture.Status('Letzte', Value)));
    Assert.AreEqual(Int64(22), Value);
    Assert.AreEqual(Ord(TOrdinalStatus.Unknown), Ord(Fixture.Status('Text', Value)));
  finally
    Fixture.Free;
  end;
end;

procedure TConstantValuesTests.ConstantsFromIndex;
var
  Index: ISymbolIndex;
  Fixture: TFixture;
  Value: Int64;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Grenzen;'#10'interface'#10'const'#10'  Basis = 4;'#10 +
    '  Grenze = Basis * 25;'#10'implementation'#10'end.', 'C:\Projekt\Grenzen.pas', nil));
  Fixture := TFixture.Create('unit Werte;'#10'interface'#10'uses'#10'  Grenzen;'#10'const'#10 +
    '  Halb = Grenze div 2;'#10'implementation'#10'end.', Index);
  try
    Assert.AreEqual(Ord(TOrdinalStatus.Value), Ord(Fixture.Status('Halb', Value)));
    Assert.AreEqual(Int64(50), Value);
  finally
    Fixture.Free;
  end;
end;

procedure TConstantValuesTests.CheckGivesReason;
var
  Fixture: TFixture;
  Value: Int64;
  First, Last: Integer;
begin
  Fixture := TFixture.Create(Werte('const'#10'  Null = 0;'#10'  Teilt = 5 div Null;'#10 +
    '  Riesig = 1000000 * 1000000 * 1000000 * 1000;'#10), nil);
  try
    Assert.AreEqual(Ord(TOrdinalStatus.DivisionByZero), Ord(Fixture.Status('Teilt', Value)));
    Assert.AreEqual(Ord(TOrdinalStatus.Overflow), Ord(Fixture.Status('Riesig', Value)));
    Assert.IsTrue(Fixture.FValues.TokenRange(Fixture.ValueNode('Teilt'), First, Last));
    Assert.AreEqual('5', Fixture.FTree.Tokens[First].Text);
    Assert.AreEqual('Null', Fixture.FTree.Tokens[Last].Text);
  finally
    Fixture.Free;
  end;
end;

procedure TConstantValuesTests.ConditionalConstantsNeedSameBranch;
var
  Fixture: TFixture;
  Value: Int64;
begin
  Fixture := TFixture.Create(Werte('const'#10'{$IFDEF KLEIN}'#10'  Seiten = 0;'#10'  Innen = 10 div Seiten;'#10 +
    '{$ELSE}'#10'  Seiten = 5;'#10'{$ENDIF}'#10'  Aussen = 10 div Seiten;'#10), nil);
  try
    Assert.AreEqual(Ord(TOrdinalStatus.DivisionByZero), Ord(Fixture.Status('Innen', Value)));
    Assert.AreEqual(Ord(TOrdinalStatus.Unknown), Ord(Fixture.Status('Aussen', Value)));
  finally
    Fixture.Free;
  end;
end;

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
