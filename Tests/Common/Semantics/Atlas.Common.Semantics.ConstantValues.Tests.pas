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
  mFound: TSyntaxNode;
begin
  mFound := nil;
  FTree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (ANode.Kind = TSyntaxKind.ConstDecl) and SameText(ANode.Name, AName) then
      begin
        mFound := ANode[ANode.ChildCount - 1];
      end;
      Result := True;
    end);
  Assert.IsNotNull(mFound, AName);
  Result := mFound;
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
  mFound: TSyntaxNode;
begin
  mFound := nil;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      if (mFound = nil) and (ANode.Kind = TSyntaxKind.ConstDecl) and SameText(ANode.Name, AName) then
      begin
        mFound := ANode[ANode.ChildCount - 1];
      end;
      Result := mFound = nil;
    end);
  Result := mFound;
end;

const
  cSource = 'unit Probe;'#10'interface'#10'uses'#10'  Farben;'#10'implementation'#10'const'#10 +
    '  Eigen = 3;'#10'  A = Grenze - Eigen;'#10'  B = Ord(fBlau) + 1;'#10'  C = Ord(cB);'#10'  D = Unbekannt + 1;'#10 +
    'end.';

{ TConstantValuesTests }

procedure TConstantValuesTests.ConstantsAndEnumsOfOwnUnit;
var
  mFixture: TFixture;
  mValue: Int64;
begin
  mFixture := TFixture.Create(Werte('type'#10'  TFarbe = (Rot, Gruen, Blau);'#10'const'#10'  Basis = 10;'#10 +
    '  Doppelt = Basis * 2;'#10'  Letzte = Ord(Blau) + Doppelt;'#10'  Text = ''abc'';'#10), nil);
  try
    Assert.AreEqual(Ord(TOrdinalStatus.Value), Ord(mFixture.Status('Doppelt', mValue)));
    Assert.AreEqual(Int64(20), mValue);
    Assert.AreEqual(Ord(TOrdinalStatus.Value), Ord(mFixture.Status('Letzte', mValue)));
    Assert.AreEqual(Int64(22), mValue);
    Assert.AreEqual(Ord(TOrdinalStatus.Unknown), Ord(mFixture.Status('Text', mValue)));
  finally
    mFixture.Free;
  end;
end;

procedure TConstantValuesTests.ConstantsFromIndex;
var
  mIndex: ISymbolIndex;
  mFixture: TFixture;
  mValue: Int64;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Grenzen;'#10'interface'#10'const'#10'  Basis = 4;'#10 +
    '  Grenze = Basis * 25;'#10'implementation'#10'end.', 'C:\Projekt\Grenzen.pas', nil));
  mFixture := TFixture.Create('unit Werte;'#10'interface'#10'uses'#10'  Grenzen;'#10'const'#10 +
    '  Halb = Grenze div 2;'#10'implementation'#10'end.', mIndex);
  try
    Assert.AreEqual(Ord(TOrdinalStatus.Value), Ord(mFixture.Status('Halb', mValue)));
    Assert.AreEqual(Int64(50), mValue);
  finally
    mFixture.Free;
  end;
end;

procedure TConstantValuesTests.CheckGivesReason;
var
  mFixture: TFixture;
  mValue: Int64;
  mFirst, mLast: Integer;
begin
  mFixture := TFixture.Create(Werte('const'#10'  Null = 0;'#10'  Teilt = 5 div Null;'#10 +
    '  Riesig = 1000000 * 1000000 * 1000000 * 1000;'#10), nil);
  try
    Assert.AreEqual(Ord(TOrdinalStatus.DivisionByZero), Ord(mFixture.Status('Teilt', mValue)));
    Assert.AreEqual(Ord(TOrdinalStatus.Overflow), Ord(mFixture.Status('Riesig', mValue)));
    Assert.IsTrue(mFixture.FValues.TokenRange(mFixture.ValueNode('Teilt'), mFirst, mLast));
    Assert.AreEqual('5', mFixture.FTree.Tokens[mFirst].Text);
    Assert.AreEqual('Null', mFixture.FTree.Tokens[mLast].Text);
  finally
    mFixture.Free;
  end;
end;

procedure TConstantValuesTests.ConditionalConstantsNeedSameBranch;
var
  mFixture: TFixture;
  mValue: Int64;
begin
  mFixture := TFixture.Create(Werte('const'#10'{$IFDEF KLEIN}'#10'  Seiten = 0;'#10'  Innen = 10 div Seiten;'#10 +
    '{$ELSE}'#10'  Seiten = 5;'#10'{$ENDIF}'#10'  Aussen = 10 div Seiten;'#10), nil);
  try
    Assert.AreEqual(Ord(TOrdinalStatus.DivisionByZero), Ord(mFixture.Status('Innen', mValue)));
    Assert.AreEqual(Ord(TOrdinalStatus.Unknown), Ord(mFixture.Status('Aussen', mValue)));
  finally
    mFixture.Free;
  end;
end;

procedure TConstantValuesTests.ConstantsAndEnumValues;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mValues: TConstantValues;
  mValue: Int64;
begin
  mTree := TPascalParser.Parse(cSource);
  mResolver := TNameResolver.Create(FarbenIndex);
  try
    mResolver.PinTree(mTree, 'Probe.pas');
    mValues := TConstantValues.Create(mTree, 'Probe.pas', FarbenIndex, mResolver);
    try
      Assert.IsTrue(mValues.EvaluateNode(FindDecl(mTree.Root, 'A'), mValue));
      Assert.AreEqual(Int64(18), mValue);
      Assert.IsTrue(mValues.EvaluateNode(FindDecl(mTree.Root, 'B'), mValue));
      Assert.AreEqual(Int64(3), mValue);
      // Eigene Werte (cB = 5): Position nicht sicher.
      Assert.IsFalse(mValues.EvaluateNode(FindDecl(mTree.Root, 'C'), mValue));
      Assert.IsFalse(mValues.EvaluateNode(FindDecl(mTree.Root, 'D'), mValue));
      Assert.IsFalse(mValues.EvaluateNode(nil, mValue));
    finally
      mValues.Free;
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TConstantValuesTests.EnumMembersInOrder;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mValues: TConstantValues;
  mIndex: ISymbolIndex;
  mFarbe, mCode: TResolvedSymbol;
  mNames: TArray<string>;
  mUnits: TUnitIndex;
begin
  mIndex := FarbenIndex;
  mTree := TPascalParser.Parse(cSource);
  mResolver := TNameResolver.Create(mIndex);
  try
    mResolver.PinTree(mTree, 'Probe.pas');
    mValues := TConstantValues.Create(mTree, 'Probe.pas', mIndex, mResolver);
    try
      Assert.IsTrue(mIndex.FindUnit('Farben', mUnits));
      Assert.IsTrue(mResolver.ResolveTypeFrom(mUnits, 'TFarbe', mFarbe));
      Assert.IsTrue(mValues.EnumMembers(mFarbe, mNames));
      Assert.AreEqual('fRot,fGruen,fBlau', string.Join(',', mNames));
      Assert.IsTrue(mResolver.ResolveTypeFrom(mUnits, 'TCode', mCode));
      Assert.IsFalse(mValues.EnumMembers(mCode, mNames));
    finally
      mValues.Free;
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TConstantValuesTests.IntegerRanges;
var
  mLowValue, mHighValue: Int64;
begin
  Assert.IsTrue(TConstantValues.IntegerRange('Byte', mLowValue, mHighValue));
  Assert.AreEqual(Int64(0), mLowValue);
  Assert.AreEqual(Int64(255), mHighValue);
  Assert.IsTrue(TConstantValues.IntegerRange('smallint', mLowValue, mHighValue));
  Assert.AreEqual(Int64(-32768), mLowValue);
  Assert.IsTrue(TConstantValues.IntegerRange('Cardinal', mLowValue, mHighValue));
  Assert.AreEqual(Int64(4294967295), mHighValue);
  Assert.IsTrue(TConstantValues.IntegerRange('Integer', mLowValue, mHighValue));
  Assert.AreEqual(Int64(-2147483648), mLowValue);
  // Plattformabhängig: weitester Bereich.
  Assert.IsTrue(TConstantValues.IntegerRange('LongInt', mLowValue, mHighValue));
  Assert.AreEqual(Int64(High(Int64)), mHighValue);
  Assert.IsTrue(TConstantValues.IntegerRange('NativeUInt', mLowValue, mHighValue));
  Assert.AreEqual(Int64(0), mLowValue);
  Assert.IsFalse(TConstantValues.IntegerRange('Double', mLowValue, mHighValue));
  Assert.IsFalse(TConstantValues.IntegerRange('Char', mLowValue, mHighValue));
end;

initialization
  TDUnitX.RegisterTestFixture(TConstantValuesTests);

end.
