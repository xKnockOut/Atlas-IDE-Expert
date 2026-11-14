unit Atlas.Common.Lsp.Attributes.Tests;

// Hover und Referenzsuche auf Attributen (#119).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver;

type
  [TestFixture]
  TLspAttributesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
  public
    /// <summary>Ein Hover vorab; einmalig angelegte Daten zählen sonst als Leck des ersten Tests.</summary>
    [SetupFixture]
    procedure WarmUp;
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
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Hover,
  Atlas.Common.Lsp.References;

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

const
  cAttributeFile = 'C:\P\DUnitX.Attributes.pas';
  cHauptFile = 'C:\P\Haupt.pas';

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(AFileName, cAttributeFile);
  AText := cUnitAttribute;
end;

procedure TLspAttributesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitAttribute, cAttributeFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspAttributesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function Hover(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AMarker: string): THoverInfo;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    Result := TLspHover.InfoAt(THoverSource.Create(AResolver, AIndex, ReadText), mTree, cUnitHaupt, cHauptFile,
      PositionOf(cUnitHaupt, AMarker));
  finally
    mTree.Free;
  end;
end;

procedure TLspAttributesTests.WarmUp;
begin
  Setup;
  try
    Hover(FResolver, FIndex, 'TestCase(');
    Hover(FResolver, FIndex, 'TestFixture]');
  finally
    TearDown;
  end;
end;

procedure TLspAttributesTests.HoverShowsMatchingConstructor;
var
  mInfo: THoverInfo;
begin
  mInfo := Hover(FResolver, FIndex, 'TestCase(');
  Assert.Contains(mInfo.Declaration, 'TestCaseAttribute = class(TCustomAttribute)');
  Assert.AreEqual('constructor Create(const AName, AValues: string);', mInfo.Constructors);
  mInfo := Hover(FResolver, FIndex, 'TestFixture(''Name'')');
  Assert.AreEqual('constructor Create(const AName: string); overload;', mInfo.Constructors);
  Assert.Contains(mInfo.ToMarkdown, 'constructor Create(const AName: string); overload;');
end;

procedure TLspAttributesTests.HoverWithoutArgumentsShowsParameterless;
begin
  // [TestFixture] ohne Argumente: nur der parameterlose Konstruktor.
  Assert.AreEqual('constructor Create; overload;', Hover(FResolver, FIndex, 'TestFixture]').Constructors);
  Assert.AreEqual('', Hover(FResolver, FIndex, 'TTest = ').Constructors);
end;

procedure TLspAttributesTests.ReferencesFindBothSpellings;
var
  mTree: TSyntaxTree;
  mFound: TArray<TReferenceLocation>;
  mLocation: TReferenceLocation;
  mText: string;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    mFound := TLspReferences.Find(FResolver, FIndex, mTree,
      TReferenceSearch.Create(cHauptFile, PositionOf(cUnitHaupt, 'TestFixture]'), True,
      [cAttributeFile, cHauptFile],
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := ReadText(AFileName, AText);
      end));
  finally
    mTree.Free;
  end;
  mText := '';
  for mLocation in mFound do
  begin
    mText := mText + Format('%s:%d ', [ExtractFileName(mLocation.FileName), mLocation.Range.StartPos.Line]);
  end;
  // Deklaration, [TestFixture], [DUnitX.Attributes.TestFixture(…)] und [TestFixtureAttribute].
  Assert.AreEqual('Haupt.pas:4 Haupt.pas:5 Haupt.pas:7 DUnitX.Attributes.pas:5', Trim(mText));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspAttributesTests);

end.
