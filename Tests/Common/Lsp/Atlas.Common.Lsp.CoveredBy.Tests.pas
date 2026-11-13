unit Atlas.Common.Lsp.CoveredBy.Tests;

// Tests für „getestet von“ (#1778): Methoden einer Unit (öffentlich, privat, Destruktor, Routinen), Zeile der
// Marke, Tests je Methode nach Tiefe, Testunits, Verwendung durch eine Testunit und die Antwort als JSON;
// ungetestete Methoden des Projekts (#1783).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CoveredBy;

type
  [TestFixture]
  TCoveredByTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Determine(const AFileName, AText: string; ADepth: Integer; AIncludePrivate: Boolean): TCoveredResult;
    function RequestOf(ADepth: Integer; AIncludePrivate: Boolean): TCoveredRequest;
    function Project(ABudgetMs: Integer): TUntestedResult;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PublicMethodsAndInterfaceRoutines;
    [Test]
    procedure PrivateOnlyOnRequest;
    [Test]
    procedure MarkStandsAtNameInBody;
    [Test]
    procedure DirectCallersAreTests;
    [Test]
    procedure DeeperCallersNeedDepth;
    [Test]
    procedure MethodWithoutTestHasNone;
    [Test]
    procedure TestUnitHasNoMethods;
    [Test]
    procedure UsedByTestUnit;
    [Test]
    procedure JsonCarriesCountsAndTests;
    [Test]
    procedure ProjectListsUntestedPerUnit;
    [Test]
    procedure ProjectWithoutBudgetSkipsUnits;
    [Test]
    procedure UntestedOfKeepsOrder;
    [Test]
    procedure ProjectJsonCarriesUnitsAndMethods;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Impact;

const
  BasisFile = 'C:\P\Basis.pas';
  AndereFile = 'C:\P\Andere.pas';
  BasisTestFile = 'C:\P\Basis.Tests.pas';
  ProgramFile = 'C:\P\Tests.dpr';

  UnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TBaseline = class'#10 +
    '  private'#10 +
    '    function Normalize(const AText: string): string;'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    destructor Destroy; override;'#10 +
    '    function Match(const AText: string): Boolean;'#10 +
    '    function Count: Integer;'#10 +
    '  end;'#10 +
    'procedure Pruefe;'#10 +
    'implementation'#10 +
    #10 +
    'procedure Intern;'#10 +
    'begin'#10 +
    'end;'#10 +
    #10 +
    'constructor TBaseline.Create;'#10 +
    'begin'#10 +
    'end;'#10 +
    #10 +
    'destructor TBaseline.Destroy;'#10 +
    'begin'#10 +
    '  inherited;'#10 +
    'end;'#10 +
    #10 +
    'function TBaseline.Normalize(const AText: string): string;'#10 +
    '  procedure Lokal;'#10 +
    '  begin'#10 +
    '  end;'#10 +
    'begin'#10 +
    '  Result := AText;'#10 +
    'end;'#10 +
    #10 +
    'function TBaseline.Match(const AText: string): Boolean;'#10 +
    'begin'#10 +
    '  Result := Normalize(AText) <> '''';'#10 +
    'end;'#10 +
    #10 +
    'function TBaseline.Count: Integer;'#10 +
    'begin'#10 +
    '  Result := 0;'#10 +
    'end;'#10 +
    #10 +
    'procedure Pruefe;'#10 +
    'begin'#10 +
    '  Intern;'#10 +
    'end;'#10 +
    'end.';

  UnitAndere =
    'unit Andere;'#10 +
    'interface'#10 +
    'procedure Leer;'#10 +
    'implementation'#10 +
    'procedure Leer;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitBasisTests =
    'unit Basis.Tests;'#10 +
    'interface'#10 +
    'uses DUnitX.TestFramework, Basis;'#10 +
    'type'#10 +
    '  [TestFixture]'#10 +
    '  TBaselineTests = class'#10 +
    '  public'#10 +
    '    [Test]'#10 +
    '    procedure MatchFindet;'#10 +
    '    [Test]'#10 +
    '    procedure LeerFindetNicht;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TBaselineTests.MatchFindet;'#10 +
    'var'#10 +
    '  mBaseline: TBaseline;'#10 +
    'begin'#10 +
    '  mBaseline := TBaseline.Create;'#10 +
    '  Assert.IsTrue(mBaseline.Match(''a''));'#10 +
    'end;'#10 +
    'procedure TBaselineTests.LeerFindetNicht;'#10 +
    'var'#10 +
    '  mBaseline: TBaseline;'#10 +
    'begin'#10 +
    '  mBaseline := nil;'#10 +
    '  Assert.IsFalse(mBaseline.Match(''''));'#10 +
    'end;'#10 +
    'end.';

  ProgramTests =
    'program Tests;'#10 +
    'uses'#10 +
    '  DUnitX.TestFramework,'#10 +
    '  Basis.Tests in ''Basis.Tests.pas'';'#10 +
    'begin'#10 +
    'end.';

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, BasisFile) then
  begin
    Result := UnitBasis;
  end
  else if SameText(AFileName, AndereFile) then
  begin
    Result := UnitAndere;
  end
  else if SameText(AFileName, BasisTestFile) then
  begin
    Result := UnitBasisTests;
  end
  else if SameText(AFileName, ProgramFile) then
  begin
    Result := ProgramTests;
  end
  else
  begin
    Result := '';
  end;
end;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  AText := TextOf(AFileName);
  Result := AText <> '';
end;

/// <summary>0-basierte Zeile, in der AMarker zuerst vorkommt.</summary>
function LineOf(const AText, AMarker: string): Integer;
var
  mIndex, mScan: Integer;
begin
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    Assert.Fail(Format('"%s" nicht gefunden', [AMarker]));
  end;
  Result := 0;
  for mScan := 1 to mIndex - 1 do
  begin
    if AText[mScan] = #10 then
    begin
      Inc(Result);
    end;
  end;
end;

function Names(const AMethods: TArray<TCoveredMethod>): string;
var
  mMethod: TCoveredMethod;
begin
  Result := '';
  for mMethod in AMethods do
  begin
    Result := Result + mMethod.Name + ' ';
  end;
  Result := Trim(Result);
end;

function MethodNamed(const AResult: TCoveredResult; const AName: string): TCoveredMethod;
var
  mMethod: TCoveredMethod;
begin
  Result := Default(TCoveredMethod);
  for mMethod in AResult.Methods do
  begin
    if mMethod.Name = AName then
    begin
      Exit(mMethod);
    end;
  end;
  Assert.Fail(Format('Methode %s fehlt', [AName]));
end;

{ TCoveredByTests }

procedure TCoveredByTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil, nil, True));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitAndere, AndereFile, nil, nil, True));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasisTests, BasisTestFile, nil, nil, True));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TCoveredByTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TCoveredByTests.RequestOf(ADepth: Integer; AIncludePrivate: Boolean): TCoveredRequest;
begin
  Result := Default(TCoveredRequest);
  Result.Files := TArray<string>.Create(BasisFile, AndereFile, BasisTestFile);
  Result.Options := TImpactOptions.Default;
  Result.Options.Depth := ADepth;
  Result.Options.Tests := TImpactTestScope.FromProgram('{unit}.Tests', ProgramTests);
  Result.IncludePrivate := AIncludePrivate;
end;

function TCoveredByTests.Determine(const AFileName, AText: string; ADepth: Integer;
  AIncludePrivate: Boolean): TCoveredResult;
begin
  Result := TCoveredBy.Determine(FResolver, FIndex, AFileName, AText, RequestOf(ADepth, AIncludePrivate),
    function(const AName: string; out AContent: string): Boolean
    begin
      Result := ReadFile(AName, AContent);
    end, nil);
end;

function TCoveredByTests.Project(ABudgetMs: Integer): TUntestedResult;
begin
  Result := TCoveredBy.Project(FResolver, FIndex, RequestOf(1, False),
    function(const AName: string; out AContent: string): Boolean
    begin
      Result := ReadFile(AName, AContent);
    end, nil, ABudgetMs);
end;

procedure TCoveredByTests.PublicMethodsAndInterfaceRoutines;
begin
  // Destruktor (ruft Free), private Methode, lokale Routine und Routine nur im implementation-Teil fehlen.
  Assert.AreEqual('TBaseline.Create TBaseline.Match TBaseline.Count Pruefe',
    Names(TCoveredBy.Methods(BasisFile, UnitBasis, False)));
end;

procedure TCoveredByTests.PrivateOnlyOnRequest;
var
  mMethods: TArray<TCoveredMethod>;
begin
  mMethods := TCoveredBy.Methods(BasisFile, UnitBasis, True);
  Assert.AreEqual('Intern TBaseline.Create TBaseline.Normalize TBaseline.Match TBaseline.Count Pruefe',
    Names(mMethods));
  Assert.IsFalse(mMethods[0].IsPublic, 'Intern steht nur im implementation-Teil');
  Assert.IsFalse(mMethods[2].IsPublic, 'Normalize ist private');
  Assert.AreEqual('private', TCoveredBy.VisibilityName(mMethods[2].Visibility));
  Assert.IsTrue(mMethods[3].IsPublic, 'Match ist public');
end;

procedure TCoveredByTests.MarkStandsAtNameInBody;
var
  mMethods: TArray<TCoveredMethod>;
begin
  mMethods := TCoveredBy.Methods(BasisFile, UnitBasis, False);
  Assert.AreEqual(LineOf(UnitBasis, 'function TBaseline.Match'), mMethods[1].Line);
  Assert.AreEqual(Integer(Length('function TBaseline.')), mMethods[1].Character);
  Assert.AreEqual('Basis', mMethods[1].Item.UnitName);
end;

procedure TCoveredByTests.DirectCallersAreTests;
var
  mFound: TCoveredResult;
  mMatch: TCoveredMethod;
begin
  mFound := Determine(BasisFile, UnitBasis, 1, False);
  Assert.IsFalse(mFound.IsTestUnit);
  Assert.AreEqual(1, mFound.Depth);
  mMatch := MethodNamed(mFound, 'TBaseline.Match');
  Assert.AreEqual(2, Integer(Length(mMatch.Tests)));
  // Nach Name sortiert.
  Assert.AreEqual('Basis.Tests.TBaselineTests.LeerFindetNicht', mMatch.Tests[0].Name);
  Assert.AreEqual('Basis.Tests.TBaselineTests.MatchFindet', mMatch.Tests[1].Name);
  Assert.AreEqual(1, mMatch.Tests[0].Level);
  Assert.AreEqual(BasisTestFile, mMatch.Tests[0].FileName);
  Assert.AreEqual(LineOf(UnitBasisTests, 'procedure TBaselineTests.LeerFindetNicht'), mMatch.Tests[0].Line);
  Assert.AreEqual('Basis.Tests.TBaselineTests.LeerFindetNicht', mMatch.Tests[0].RunNames[0]);
  Assert.AreEqual(1, Integer(Length(MethodNamed(mFound, 'TBaseline.Create').Tests)));
end;

procedure TCoveredByTests.DeeperCallersNeedDepth;
begin
  // Normalize ruft nur Match; die Tests erreichen sie erst über zwei Ebenen.
  Assert.AreEqual(0, Integer(Length(MethodNamed(Determine(BasisFile, UnitBasis, 1, True),
    'TBaseline.Normalize').Tests)));
  Assert.AreEqual(2, Integer(Length(MethodNamed(Determine(BasisFile, UnitBasis, 2, True),
    'TBaseline.Normalize').Tests)));
end;

procedure TCoveredByTests.MethodWithoutTestHasNone;
var
  mFound: TCoveredResult;
begin
  mFound := Determine(BasisFile, UnitBasis, 1, False);
  Assert.AreEqual(0, Integer(Length(MethodNamed(mFound, 'TBaseline.Count').Tests)));
  Assert.AreEqual(0, Integer(Length(MethodNamed(mFound, 'Pruefe').Tests)));
  Assert.AreEqual(2, mFound.Tested, 'Create und Match');
  Assert.AreEqual(4, Integer(Length(mFound.Methods)));
end;

procedure TCoveredByTests.TestUnitHasNoMethods;
var
  mFound: TCoveredResult;
begin
  mFound := Determine(BasisTestFile, UnitBasisTests, 1, True);
  Assert.IsTrue(mFound.IsTestUnit);
  Assert.AreEqual(0, Integer(Length(mFound.Methods)));
end;

procedure TCoveredByTests.UsedByTestUnit;
begin
  Assert.IsTrue(Determine(BasisFile, UnitBasis, 1, False).HasTestUnit, 'Basis.Tests verwendet Basis');
  Assert.IsFalse(Determine(AndereFile, UnitAndere, 1, False).HasTestUnit, 'keine Testunit verwendet Andere');
end;

procedure TCoveredByTests.JsonCarriesCountsAndTests;
var
  mJson: TJSONObject;
  mMethods, mTests: TJSONArray;
  mMethod: TJSONObject;
begin
  mJson := TCoveredBy.ToJson(Determine(BasisFile, UnitBasis, 1, False));
  try
    Assert.AreEqual('Basis', mJson.GetValue<string>('unit'));
    Assert.AreEqual(2, mJson.GetValue<Integer>('tested'));
    Assert.AreEqual(4, mJson.GetValue<Integer>('total'));
    Assert.IsTrue(mJson.GetValue<Boolean>('hasTestUnit'));
    Assert.IsFalse(mJson.GetValue<Boolean>('testUnit'));
    mMethods := mJson.GetValue<TJSONArray>('methods');
    mMethod := mMethods.Items[1] as TJSONObject;
    Assert.AreEqual('TBaseline.Match', mMethod.GetValue<string>('name'));
    Assert.AreEqual(LineOf(UnitBasis, 'function TBaseline.Match'), mMethod.GetValue<Integer>('line'));
    Assert.AreEqual('public', mMethod.GetValue<string>('visibility'));
    mTests := mMethod.GetValue<TJSONArray>('tests');
    Assert.AreEqual(2, mTests.Count);
    Assert.AreEqual('Basis.Tests.TBaselineTests.LeerFindetNicht',
      (mTests.Items[0] as TJSONObject).GetValue<string>('name'));
    Assert.AreEqual(1, (mTests.Items[0] as TJSONObject).GetValue<TJSONArray>('run').Count);
    Assert.AreEqual(0, mJson.GetValue<TJSONArray>('limits').Count);
  finally
    mJson.Free;
  end;
end;

procedure TCoveredByTests.ProjectListsUntestedPerUnit;
var
  mFound: TUntestedResult;
begin
  mFound := Project(TCoveredBy.cProjectTimeoutMs);
  // Basis.Tests ist Testunit und fehlt; Andere hat keine Testunit und wird nicht analysiert.
  Assert.AreEqual(2, Integer(Length(mFound.Units)));
  Assert.AreEqual('Basis', mFound.Units[0].UnitName);
  Assert.IsTrue(mFound.Units[0].HasTestUnit);
  Assert.AreEqual(2, mFound.Units[0].Tested);
  Assert.AreEqual(4, mFound.Units[0].Total);
  Assert.AreEqual('TBaseline.Count Pruefe', Names(mFound.Units[0].Untested));
  Assert.AreEqual('Andere', mFound.Units[1].UnitName);
  Assert.IsFalse(mFound.Units[1].HasTestUnit);
  Assert.AreEqual(0, mFound.Units[1].Tested);
  Assert.AreEqual('Leer', Names(mFound.Units[1].Untested));
  Assert.AreEqual(0, mFound.Skipped);
end;

procedure TCoveredByTests.ProjectWithoutBudgetSkipsUnits;
var
  mFound: TUntestedResult;
begin
  mFound := Project(0);
  Assert.AreEqual(0, Integer(Length(mFound.Units)));
  Assert.AreEqual(3, mFound.Skipped);
  Assert.IsTrue(TImpactLimit.Time in mFound.Limits);
end;

procedure TCoveredByTests.UntestedOfKeepsOrder;
var
  mUnit: TUntestedUnit;
begin
  mUnit := TCoveredBy.UntestedOf(Determine(BasisFile, UnitBasis, 2, True), BasisFile);
  Assert.AreEqual(BasisFile, mUnit.FileName);
  Assert.AreEqual(6, mUnit.Total);
  Assert.AreEqual('Intern TBaseline.Count Pruefe', Names(mUnit.Untested));
end;

procedure TCoveredByTests.ProjectJsonCarriesUnitsAndMethods;
var
  mJson: TJSONObject;
  mUnit, mMethod: TJSONObject;
begin
  mJson := TCoveredBy.ProjectToJson(Project(TCoveredBy.cProjectTimeoutMs));
  try
    Assert.AreEqual(2, mJson.GetValue<TJSONArray>('units').Count);
    mUnit := mJson.GetValue<TJSONArray>('units').Items[0] as TJSONObject;
    Assert.AreEqual('Basis', mUnit.GetValue<string>('unit'));
    Assert.IsTrue(mUnit.GetValue<string>('uri').StartsWith('file:'));
    Assert.IsTrue(mUnit.GetValue<Boolean>('hasTestUnit'));
    Assert.AreEqual(2, mUnit.GetValue<Integer>('tested'));
    Assert.AreEqual(4, mUnit.GetValue<Integer>('total'));
    mMethod := mUnit.GetValue<TJSONArray>('untested').Items[0] as TJSONObject;
    Assert.AreEqual('TBaseline.Count', mMethod.GetValue<string>('name'));
    Assert.AreEqual(LineOf(UnitBasis, 'function TBaseline.Count'), mMethod.GetValue<Integer>('line'));
    Assert.AreEqual(Integer(Length('function TBaseline.')), mMethod.GetValue<Integer>('character'));
    Assert.AreEqual(0, mJson.GetValue<Integer>('skipped'));
    Assert.AreEqual(0, mJson.GetValue<TJSONArray>('limits').Count);
  finally
    mJson.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCoveredByTests);

end.
