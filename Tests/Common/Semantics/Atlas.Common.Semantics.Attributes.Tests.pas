unit Atlas.Common.Semantics.Attributes.Tests;

// Tests für Attribute in der Namensauflösung (#119).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  [TestFixture]
  TAttributesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ResolvedAt(const AMarker: string): TResolvedSymbol;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure UseAtPosition;
    [Test]
    procedure SuffixFirst;
    [Test]
    procedure PlainNameWithoutSuffixClass;
    [Test]
    procedure QualifiedName;
    [Test]
    procedure SuffixClassMustBeAttribute;
    [Test]
    procedure ClassNamesOrder;
    [Test]
    procedure NamesOfAttributeNode;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.Attributes;

const
  cUnitAttribute =
    'unit DUnitX.Attributes;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TCustomAttribute = class'#10 +
    '  end;'#10 +
    '  TestFixtureAttribute = class(TCustomAttribute)'#10 +
    '  public'#10 +
    '    constructor Create; overload;'#10 +
    '    constructor Create(const AName: string); overload;'#10 +
    '  end;'#10 +
    '  TestCaseAttribute = class(TCustomAttribute)'#10 +
    '  public'#10 +
    '    constructor Create(const AName, AValues: string);'#10 +
    '  end;'#10 +
    '  Foo = class(TCustomAttribute)'#10 +
    '  end;'#10 +
    '  BarAttribute = class(TObject)'#10 +
    '  end;'#10 +
    '  Bar = class(TCustomAttribute)'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  cUnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses DUnitX.Attributes;'#10 +
    'type'#10 +
    '  [TestFixture]'#10 +
    '  [DUnitX.Attributes.TestFixture(''Name'')]'#10 +
    '  [Foo, Bar]'#10 +
    '  TTest = class'#10 +
    '  public'#10 +
    '    [TestCase(''A'', ''1,2'')]'#10 +
    '    procedure P;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TTest.P;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  mIndex, mLine, mLineStart, mRun: Integer;
begin
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  mLine := 0;
  mLineStart := 1;
  for mRun := 1 to mIndex - 1 do
  begin
    if AText[mRun] = #10 then
    begin
      Inc(mLine);
      mLineStart := mRun + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

procedure TAttributesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitAttribute, 'C:\P\DUnitX.Attributes.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TAttributesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TAttributesTests.ResolvedAt(const AMarker: string): TResolvedSymbol;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    Result := FResolver.Resolve(mTree, 'C:\P\Haupt.pas', PositionOf(cUnitHaupt, AMarker));
  finally
    mTree.Free;
  end;
end;

procedure TAttributesTests.UseAtPosition;
var
  mTree: TSyntaxTree;
  mUse: TAttributeUse;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    Assert.IsTrue(TAttributes.At(mTree, PositionOf(cUnitHaupt, 'TestCase('), mUse));
    Assert.AreEqual('TestCase', mUse.Name);
    Assert.AreEqual(2, mUse.ArgCount);
    Assert.IsTrue(TAttributes.At(mTree, PositionOf(cUnitHaupt, 'Attributes.TestFixture('), mUse));
    Assert.AreEqual('DUnitX.Attributes.TestFixture', mUse.Name);
    Assert.AreEqual(1, mUse.ArgCount);
    Assert.IsTrue(TAttributes.At(mTree, PositionOf(cUnitHaupt, 'Bar]'), mUse));
    Assert.AreEqual('Bar', mUse.Name);
    Assert.AreEqual(0, mUse.ArgCount);
    // In den Argumenten und außerhalb der Klammern kein Attributname.
    Assert.IsFalse(TAttributes.At(mTree, PositionOf(cUnitHaupt, '''1,2'''), mUse));
    Assert.IsFalse(TAttributes.At(mTree, PositionOf(cUnitHaupt, 'TTest = '), mUse));
  finally
    mTree.Free;
  end;
end;

procedure TAttributesTests.SuffixFirst;
var
  mResolved: TResolvedSymbol;
begin
  mResolved := ResolvedAt('TestFixture]');
  Assert.AreEqual('TestFixtureAttribute', mResolved.Name);
  Assert.AreEqual(5, mResolved.SelectionRange.StartPos.Line);
  Assert.AreEqual('TestCaseAttribute', ResolvedAt('TestCase(').Name);
end;

procedure TAttributesTests.PlainNameWithoutSuffixClass;
begin
  Assert.AreEqual('Foo', ResolvedAt('Foo,').Name);
end;

procedure TAttributesTests.QualifiedName;
begin
  Assert.AreEqual('TestFixtureAttribute', ResolvedAt('TestFixture(''Name'')').Name);
end;

procedure TAttributesTests.SuffixClassMustBeAttribute;
begin
  // BarAttribute stammt nicht von TCustomAttribute ab.
  Assert.AreEqual('Bar', ResolvedAt('Bar]').Name);
end;

procedure TAttributesTests.ClassNamesOrder;
begin
  Assert.AreEqual(2, Integer(Length(TAttributes.ClassNames('TestFixture'))));
  Assert.AreEqual('TestFixtureAttribute', TAttributes.ClassNames('TestFixture')[0]);
  Assert.AreEqual(1, Integer(Length(TAttributes.ClassNames('TestFixtureAttribute'))));
end;

procedure TAttributesTests.NamesOfAttributeNode;
var
  mTree: TSyntaxTree;
  mFound: TArray<string>;
begin
  mTree := TPascalParser.Parse('unit U;'#10'interface'#10'type'#10'  TA = class'#10'  public'#10 +
    '    [Test, DUnitX.Attributes.TestCaseAttribute(''a'', ''1'')]'#10'    procedure P;'#10'  end;'#10 +
    'implementation'#10'end.');
  try
    mFound := nil;
    mTree.Root.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := True;
        if ANode.Kind = TSyntaxKind.Attribute then
        begin
          mFound := mFound + TAttributes.Names(ANode);
        end;
      end);
    Assert.AreEqual('Test,TestCase', string.Join(',', mFound));
    Assert.AreEqual(0, Integer(Length(TAttributes.Names(nil))));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAttributesTests);

end.
