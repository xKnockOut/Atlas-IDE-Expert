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
  UnitAttribute =
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

  UnitHaupt =
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
  Index, Line, LineStart, Run: Integer;
begin
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Line := 0;
  LineStart := 1;
  for Run := 1 to Index - 1 do
    if AText[Run] = #10 then
    begin
      Inc(Line);
      LineStart := Run + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

procedure TAttributesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitAttribute, 'C:\P\DUnitX.Attributes.pas', nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TAttributesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TAttributesTests.ResolvedAt(const AMarker: string): TResolvedSymbol;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Result := FResolver.Resolve(Tree, 'C:\P\Haupt.pas', PositionOf(UnitHaupt, AMarker));
  finally
    Tree.Free;
  end;
end;

procedure TAttributesTests.UseAtPosition;
var
  Tree: TSyntaxTree;
  Use: TAttributeUse;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Assert.IsTrue(TAttributes.At(Tree, PositionOf(UnitHaupt, 'TestCase('), Use));
    Assert.AreEqual('TestCase', Use.Name);
    Assert.AreEqual(2, Use.ArgCount);
    Assert.IsTrue(TAttributes.At(Tree, PositionOf(UnitHaupt, 'Attributes.TestFixture('), Use));
    Assert.AreEqual('DUnitX.Attributes.TestFixture', Use.Name);
    Assert.AreEqual(1, Use.ArgCount);
    Assert.IsTrue(TAttributes.At(Tree, PositionOf(UnitHaupt, 'Bar]'), Use));
    Assert.AreEqual('Bar', Use.Name);
    Assert.AreEqual(0, Use.ArgCount);
    // In den Argumenten und außerhalb der Klammern kein Attributname.
    Assert.IsFalse(TAttributes.At(Tree, PositionOf(UnitHaupt, '''1,2'''), Use));
    Assert.IsFalse(TAttributes.At(Tree, PositionOf(UnitHaupt, 'TTest = '), Use));
  finally
    Tree.Free;
  end;
end;

procedure TAttributesTests.SuffixFirst;
var
  Resolved: TResolvedSymbol;
begin
  Resolved := ResolvedAt('TestFixture]');
  Assert.AreEqual('TestFixtureAttribute', Resolved.Name);
  Assert.AreEqual(5, Resolved.SelectionRange.StartPos.Line);
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

initialization
  TDUnitX.RegisterTestFixture(TAttributesTests);

end.
