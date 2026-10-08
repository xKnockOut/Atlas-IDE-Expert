unit BDLsp.Common.Lsp.Attributes.Tests;

// Hover und Referenzsuche auf Attributen (#119).

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Semantics.NameResolver;

type
  [TestFixture]
  TLspAttributesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure HoverShowsMatchingConstructor;
    [Test]
    procedure HoverWithoutArgumentsShowsParameterless;
    [Test]
    procedure ReferencesFindBothSpellings;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Index.Extractor,
  BDLsp.Common.Lsp.Hover,
  BDLsp.Common.Lsp.References;

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
    '  [TestFixtureAttribute]'#10 +
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

const
  AttributeFile = 'C:\P\DUnitX.Attributes.pas';
  HauptFile = 'C:\P\Haupt.pas';

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(AFileName, AttributeFile);
  AText := UnitAttribute;
end;

procedure TLspAttributesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitAttribute, AttributeFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspAttributesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function Hover(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AMarker: string): THoverInfo;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Result := TLspHover.InfoAt(AResolver, AIndex, Tree, UnitHaupt, HauptFile, PositionOf(UnitHaupt, AMarker),
      ReadText);
  finally
    Tree.Free;
  end;
end;

procedure TLspAttributesTests.HoverShowsMatchingConstructor;
var
  Info: THoverInfo;
begin
  Info := Hover(FResolver, FIndex, 'TestCase(');
  Assert.Contains(Info.Declaration, 'TestCaseAttribute = class(TCustomAttribute)');
  Assert.AreEqual('constructor Create(const AName, AValues: string);', Info.Constructors);
  Info := Hover(FResolver, FIndex, 'TestFixture(''Name'')');
  Assert.AreEqual('constructor Create(const AName: string); overload;', Info.Constructors);
  Assert.Contains(Info.ToMarkdown, 'constructor Create(const AName: string); overload;');
end;

procedure TLspAttributesTests.HoverWithoutArgumentsShowsParameterless;
begin
  // [TestFixture] ohne Argumente: nur der parameterlose Konstruktor.
  Assert.AreEqual('constructor Create; overload;', Hover(FResolver, FIndex, 'TestFixture]').Constructors);
  Assert.AreEqual('', Hover(FResolver, FIndex, 'TTest = ').Constructors);
end;

procedure TLspAttributesTests.ReferencesFindBothSpellings;
var
  Tree: TSyntaxTree;
  Found: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
  Text: string;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Found := TLspReferences.Find(FResolver, FIndex, Tree, HauptFile, PositionOf(UnitHaupt, 'TestFixture]'), True,
      [AttributeFile, HauptFile],
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := ReadText(AFileName, AText);
      end);
  finally
    Tree.Free;
  end;
  Text := '';
  for Location in Found do
    Text := Text + Format('%s:%d ', [ExtractFileName(Location.FileName), Location.Range.StartPos.Line]);
  // Deklaration, [TestFixture], [DUnitX.Attributes.TestFixture(…)] und [TestFixtureAttribute].
  Assert.AreEqual('Haupt.pas:4 Haupt.pas:5 Haupt.pas:7 DUnitX.Attributes.pas:5', Trim(Text));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspAttributesTests);

end.
