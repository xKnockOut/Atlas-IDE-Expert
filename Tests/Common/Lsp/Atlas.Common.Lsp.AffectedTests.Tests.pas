unit Atlas.Common.Lsp.AffectedTests.Tests;

// Tests für die betroffenen Tests einer Änderung (#1353): Zuordnung geänderter Zeilen (interface,
// implementation, initialization, Lücken, Kommentare), .dfm, .inc, Testprogramm, Verfolgung bis zum Test,
// Zusammenfassen zur Fixture, Sortierung, Formate und Zeitbedarf.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.ChangedFiles,
  Atlas.Common.Lsp.AffectedTests;

type
  [TestFixture]
  TAffectedTestsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Determine(const AInputs: TArray<TAffectedInput>): TAffectedResult; overload;
    function Determine(const AInputs: TArray<TAffectedInput>; const APrograms: TArray<string>): TAffectedResult;
      overload;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ImplementationLineMapsToRoutine;
    [Test]
    procedure InterfaceDeclarationMapsToMethod;
    [Test]
    procedure ConstantMapsToConstant;
    [Test]
    procedure InitializationIsWholeUnit;
    [Test]
    procedure UsesIsWholeUnit;
    [Test]
    procedure CommentAndBlankLinesIgnored;
    [Test]
    procedure GapInsideRoutineMapsToRoutine;
    [Test]
    procedure GapBetweenRoutinesIsWholeUnit;
    [Test]
    procedure FormClassFromFirstLine;
    [Test]
    procedure IncludeLinesFindDirective;
    [Test]
    procedure MatchChangeReachesItsTests;
    [Test]
    procedure PrivateImplementationChangeReachesTestsWithPath;
    [Test]
    procedure InitializationChangeRunsUsingFixtures;
    [Test]
    procedure FormChangeReachesFormTests;
    [Test]
    procedure IncludeChangeCountsForIncludingUnit;
    [Test]
    procedure CommentOnlyChangeIsSkipped;
    [Test]
    procedure TestProgramChangeNeedsAll;
    [Test]
    procedure OtherFilesAreSkipped;
    [Test]
    procedure CollapseAboveEightyPercent;
    [Test]
    procedure SortIsUniqueAndCaseInsensitive;
    [Test]
    procedure FormatsParse;
    [Test]
    procedure DUnitXArgumentJoinsRunNames;
    [Test]
    procedure JsonRoundTrip;
    [Test]
    procedure TextNamesTestsAndReasons;
    [Test]
    [Category('Benchmark')]
    procedure TwentyFilesInThousandUnitsStayFast;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Diagnostics,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Impact;

const
  BasisFile = 'C:\P\Basis.pas';
  AndereFile = 'C:\P\Andere.pas';
  FormularFile = 'C:\P\Formular.pas';
  FormularForm = 'C:\P\Formular.dfm';
  FormularInclude = 'C:\P\Formular.inc';
  BasisTestFile = 'C:\P\Basis.Tests.pas';
  FormularTestFile = 'C:\P\Formular.Tests.pas';
  ProgramFile = 'C:\P\Tests.dpr';

  UnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'uses System.SysUtils;'#10 +
    'type'#10 +
    '  TBaseline = class'#10 +
    '  private'#10 +
    '    function Normalize(const AText: string): string;'#10 +
    '  public'#10 +
    '    function Match(const AText: string): Boolean;'#10 +
    '  end;'#10 +
    'const'#10 +
    '  cLimit = 3;'#10 +
    'implementation'#10 +
    #10 +
    'function TBaseline.Normalize(const AText: string): string;'#10 +
    'begin'#10 +
    '  // nur ein Kommentar'#10 +
    '  Result := AText;'#10 +
    'end;'#10 +
    #10 +
    'function TBaseline.Match(const AText: string): Boolean;'#10 +
    'begin'#10 +
    '  Result := Normalize(AText) <> '''';'#10 +
    'end;'#10 +
    #10 +
    'initialization'#10 +
    '  TBaseline.ClassName;'#10 +
    'end.';

  UnitAndere =
    'unit Andere;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'procedure Pruefe;'#10 +
    'implementation'#10 +
    'procedure Pruefe;'#10 +
    'var'#10 +
    '  mBaseline: TBaseline;'#10 +
    'begin'#10 +
    '  mBaseline := nil;'#10 +
    '  mBaseline.Match(''a'');'#10 +
    'end;'#10 +
    'end.';

  UnitFormular =
    'unit Formular;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TForm1 = class'#10 +
    '    procedure Button1Click(Sender: TObject);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    '{$I Formular.inc}'#10 +
    '{$R *.dfm}'#10 +
    'procedure TForm1.Button1Click(Sender: TObject);'#10 +
    'var'#10 +
    '  mBaseline: TBaseline;'#10 +
    'begin'#10 +
    '  mBaseline := nil;'#10 +
    '  mBaseline.Match(''x'');'#10 +
    'end;'#10 +
    'end.';

  FormFormular =
    'object Form1: TForm1'#10 +
    '  Caption = ''Formular'''#10 +
    'end';

  IncludeFormular =
    'const'#10 +
    '  cIncluded = 1;';

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
    '    [Test]'#10 +
    '    procedure UnabhaengigEins;'#10 +
    '    [Test]'#10 +
    '    procedure UnabhaengigZwei;'#10 +
    '    [Test]'#10 +
    '    procedure UnabhaengigDrei;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TBaselineTests.MatchFindet;'#10 +
    'var'#10 +
    '  mBaseline: TBaseline;'#10 +
    'begin'#10 +
    '  mBaseline := nil;'#10 +
    '  Assert.IsTrue(mBaseline.Match(''a''));'#10 +
    'end;'#10 +
    'procedure TBaselineTests.LeerFindetNicht;'#10 +
    'var'#10 +
    '  mBaseline: TBaseline;'#10 +
    'begin'#10 +
    '  mBaseline := nil;'#10 +
    '  Assert.IsFalse(mBaseline.Match(''''));'#10 +
    'end;'#10 +
    'procedure TBaselineTests.UnabhaengigEins;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TBaselineTests.UnabhaengigZwei;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TBaselineTests.UnabhaengigDrei;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitFormularTests =
    'unit Formular.Tests;'#10 +
    'interface'#10 +
    'uses DUnitX.TestFramework, Formular;'#10 +
    'type'#10 +
    '  [TestFixture]'#10 +
    '  TFormularTests = class'#10 +
    '  public'#10 +
    '    [Test]'#10 +
    '    procedure Klick;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFormularTests.Klick;'#10 +
    'var'#10 +
    '  mForm: TForm1;'#10 +
    'begin'#10 +
    '  mForm := nil;'#10 +
    '  mForm.Button1Click(nil);'#10 +
    'end;'#10 +
    'end.';

  ProgramTests =
    'program Tests;'#10 +
    'uses'#10 +
    '  DUnitX.TestFramework,'#10 +
    '  Basis.Tests in ''Basis.Tests.pas'','#10 +
    '  Formular.Tests in ''Formular.Tests.pas'';'#10 +
    'begin'#10 +
    'end.';

function TextOf(const AFileName: string): string;
begin
  if SameText(AFileName, BasisFile) then
    Result := UnitBasis
  else if SameText(AFileName, AndereFile) then
    Result := UnitAndere
  else if SameText(AFileName, FormularFile) then
    Result := UnitFormular
  else if SameText(AFileName, FormularForm) then
    Result := FormFormular
  else if SameText(AFileName, FormularInclude) then
    Result := IncludeFormular
  else if SameText(AFileName, BasisTestFile) then
    Result := UnitBasisTests
  else if SameText(AFileName, FormularTestFile) then
    Result := UnitFormularTests
  else if SameText(AFileName, ProgramFile) then
    Result := ProgramTests
  else
    Result := '';
end;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  AText := TextOf(AFileName);
  Result := AText <> '';
end;

function ProjectFiles: TArray<string>;
begin
  Result := TArray<string>.Create(BasisFile, AndereFile, FormularFile, BasisTestFile, FormularTestFile);
end;

/// <summary>0-basierte Zeile, in der AMarker zuerst vorkommt.</summary>
function LineOf(const AText, AMarker: string): Integer;
var
  mIndex, mScan: Integer;
begin
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Result := 0;
  for mScan := 1 to mIndex - 1 do
    if AText[mScan] = #10 then
      Inc(Result);
end;

function Span(AFirst, ALast: Integer): TChangedLines;
var
  mSpan: TLineSpan;
begin
  Result := Default(TChangedLines);
  mSpan.First := AFirst;
  mSpan.Last := ALast;
  Result.Spans := [mSpan];
end;

function Gap(AAt: Integer): TChangedLines;
begin
  Result := Default(TChangedLines);
  Result.Gaps := [AAt];
end;

function LinesAt(const AText, AMarker: string): TChangedLines;
begin
  Result := Span(LineOf(AText, AMarker), LineOf(AText, AMarker));
end;

function Input(const AFileName: string; const ALines: TChangedLines): TAffectedInput;
begin
  Result := Default(TAffectedInput);
  Result.FileName := AFileName;
  Result.Lines := ALines;
  Result.HasLines := True;
end;

function WholeFile(const AFileName: string): TAffectedInput;
begin
  Result := Default(TAffectedInput);
  Result.FileName := AFileName;
  Result.HasLines := False;
end;

function TestNamed(const AResult: TAffectedResult; const AName: string; out ATest: TAffectedTest): Boolean;
var
  mTest: TAffectedTest;
begin
  for mTest in AResult.Tests do
    if mTest.Name = AName then
    begin
      ATest := mTest;
      Exit(True);
    end;
  ATest := Default(TAffectedTest);
  Result := False;
end;

function Names(const AResult: TAffectedResult): string;
var
  mTest: TAffectedTest;
begin
  Result := '';
  for mTest in AResult.Tests do
    Result := Result + mTest.Name + ' ';
end;

function Fake(const AName, AFixture, AMethod: string): TAffectedTest;
begin
  Result := Default(TAffectedTest);
  Result.UnitName := 'U';
  Result.Fixture := AFixture;
  Result.Method := AMethod;
  Result.Name := AName;
  Result.RunNames := TArray<string>.Create(AName);
  Result.FileName := 'C:\P\U.pas';
end;

{ TAffectedTestsTests }

procedure TAffectedTestsTests.Setup;
var
  mFormular: TUnitIndex;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil, nil, True));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitAndere, AndereFile, nil, nil, True));
  mFormular := TIndexExtractor.ExtractText(UnitFormular, FormularFile, nil, nil, True);
  // Ohne Include-Auflösung im Test: Die eingebundene Datei wie der Index sie nennt.
  mFormular.Includes := TArray<string>.Create(FormularInclude);
  FIndex.AddUnit(mFormular);
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasisTests, BasisTestFile, nil, nil, True));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitFormularTests, FormularTestFile, nil, nil, True));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TAffectedTestsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TAffectedTestsTests.Determine(const AInputs: TArray<TAffectedInput>): TAffectedResult;
begin
  Result := Determine(AInputs, TArray<string>.Create(ProgramFile));
end;

function TAffectedTestsTests.Determine(const AInputs: TArray<TAffectedInput>;
  const APrograms: TArray<string>): TAffectedResult;
var
  mRequest: TAffectedRequest;
begin
  mRequest := Default(TAffectedRequest);
  mRequest.Files := ProjectFiles;
  mRequest.TestPrograms := APrograms;
  mRequest.Options := TImpactOptions.Default;
  mRequest.Options.Depth := TAffectedTests.DefaultDepth;
  mRequest.Options.Tests := TImpactTestScope.FromProgram('{unit}.Tests', ProgramTests);
  mRequest.Base := 'main';
  Result := TAffectedTests.Determine(FResolver, FIndex, AInputs, mRequest,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadFile(AFileName, AText);
    end, nil);
end;

procedure TAffectedTestsTests.ImplementationLineMapsToRoutine;
var
  mChanges: TArray<TAffectedChange>;
begin
  mChanges := TAffectedTests.MapPascal(BasisFile, UnitBasis, LinesAt(UnitBasis, 'Result := Normalize'));
  Assert.AreEqual(1, Integer(Length(mChanges)));
  Assert.IsTrue(mChanges[0].Kind = TAffectedChangeKind.Symbol);
  Assert.AreEqual('TBaseline.Match', mChanges[0].Text);
  Assert.AreEqual('implementation', mChanges[0].Place);
  Assert.AreEqual(BasisFile, mChanges[0].Source);
end;

procedure TAffectedTestsTests.InterfaceDeclarationMapsToMethod;
var
  mChanges: TArray<TAffectedChange>;
begin
  // Eine geänderte Signatur im interface zählt für die Methode, nicht für die ganze Klasse.
  mChanges := TAffectedTests.MapPascal(BasisFile, UnitBasis, LinesAt(UnitBasis, '    function Match('));
  Assert.AreEqual(1, Integer(Length(mChanges)));
  Assert.IsTrue(mChanges[0].Kind = TAffectedChangeKind.Symbol);
  Assert.AreEqual('TBaseline.Match', mChanges[0].Text);
  Assert.AreEqual('interface', mChanges[0].Place);
end;

procedure TAffectedTestsTests.ConstantMapsToConstant;
var
  mChanges: TArray<TAffectedChange>;
begin
  mChanges := TAffectedTests.MapPascal(BasisFile, UnitBasis, LinesAt(UnitBasis, 'cLimit = 3'));
  Assert.AreEqual(1, Integer(Length(mChanges)));
  Assert.IsTrue(mChanges[0].Kind = TAffectedChangeKind.Symbol);
  Assert.AreEqual('cLimit', mChanges[0].Item.Name);
end;

procedure TAffectedTestsTests.InitializationIsWholeUnit;
var
  mChanges: TArray<TAffectedChange>;
begin
  mChanges := TAffectedTests.MapPascal(BasisFile, UnitBasis, LinesAt(UnitBasis, 'TBaseline.ClassName'));
  Assert.AreEqual(1, Integer(Length(mChanges)));
  Assert.IsTrue(mChanges[0].Kind = TAffectedChangeKind.WholeUnit);
  Assert.AreEqual('Unit Basis', mChanges[0].Text);
  Assert.AreEqual('initialization', mChanges[0].Place);
end;

procedure TAffectedTestsTests.UsesIsWholeUnit;
var
  mChanges: TArray<TAffectedChange>;
begin
  mChanges := TAffectedTests.MapPascal(BasisFile, UnitBasis, LinesAt(UnitBasis, 'uses System.SysUtils'));
  Assert.AreEqual(1, Integer(Length(mChanges)));
  Assert.IsTrue(mChanges[0].Kind = TAffectedChangeKind.WholeUnit);
  Assert.AreEqual('interface', mChanges[0].Place);
end;

procedure TAffectedTestsTests.CommentAndBlankLinesIgnored;
var
  mLines: TChangedLines;
begin
  // Leerzeile vor der Routine und der Kommentar in ihrem Rumpf.
  mLines := Span(LineOf(UnitBasis, 'function TBaseline.Normalize') - 1, LineOf(UnitBasis, 'function TBaseline.Normalize')
    - 1);
  mLines.Spans := mLines.Spans + LinesAt(UnitBasis, '// nur ein Kommentar').Spans;
  Assert.AreEqual(0, Integer(Length(TAffectedTests.MapPascal(BasisFile, UnitBasis, mLines))));
end;

procedure TAffectedTestsTests.GapInsideRoutineMapsToRoutine;
var
  mChanges: TArray<TAffectedChange>;
begin
  // Zeilen vor "Result := AText" entfernt: davor und danach steht Normalize.
  mChanges := TAffectedTests.MapPascal(BasisFile, UnitBasis, Gap(LineOf(UnitBasis, 'Result := AText')));
  Assert.AreEqual(1, Integer(Length(mChanges)));
  Assert.AreEqual('TBaseline.Normalize', mChanges[0].Text);
end;

procedure TAffectedTestsTests.GapBetweenRoutinesIsWholeUnit;
var
  mChanges: TArray<TAffectedChange>;
begin
  // Vor "function TBaseline.Match" entfernt (etwa eine ganze Routine): davor Normalize, danach Match.
  mChanges := TAffectedTests.MapPascal(BasisFile, UnitBasis, Gap(LineOf(UnitBasis, 'function TBaseline.Match')));
  Assert.AreEqual(1, Integer(Length(mChanges)));
  Assert.IsTrue(mChanges[0].Kind = TAffectedChangeKind.WholeUnit);
  Assert.AreEqual('implementation', mChanges[0].Place);
end;

procedure TAffectedTestsTests.FormClassFromFirstLine;
begin
  Assert.AreEqual('TForm1', TAffectedTests.FormClass(FormFormular));
  Assert.AreEqual('TForm2', TAffectedTests.FormClass(#10'inherited Form2: TForm2'#10'end'));
  Assert.AreEqual('TFrame1', TAffectedTests.FormClass('inline Frame1: TFrame1 [0]'#10'end'));
  Assert.AreEqual('', TAffectedTests.FormClass('kein Formular'));
end;

procedure TAffectedTestsTests.IncludeLinesFindDirective;
var
  mLines: TArray<Integer>;
begin
  mLines := TAffectedTests.IncludeLines(UnitFormular, FormularInclude);
  Assert.AreEqual(1, Integer(Length(mLines)));
  Assert.AreEqual(LineOf(UnitFormular, '{$I Formular.inc}'), mLines[0]);
  // Ohne Endung gilt .inc.
  Assert.AreEqual(1, Integer(Length(TAffectedTests.IncludeLines('{$INCLUDE Formular}', FormularInclude))));
  Assert.AreEqual(0, Integer(Length(TAffectedTests.IncludeLines(UnitFormular, 'C:\P\Andere.inc'))));
end;

procedure TAffectedTestsTests.MatchChangeReachesItsTests;
var
  mFound: TAffectedResult;
  mTest: TAffectedTest;
begin
  mFound := Determine([Input(BasisFile, LinesAt(UnitBasis, 'Result := Normalize'))]);
  Assert.IsFalse(mFound.All, mFound.AllReason);
  Assert.IsTrue(TestNamed(mFound, 'Basis.Tests.TBaselineTests.MatchFindet', mTest), Names(mFound));
  Assert.AreEqual('TBaselineTests', mTest.Fixture);
  Assert.AreEqual('MatchFindet', mTest.Method);
  Assert.AreEqual(BasisTestFile, mTest.FileName);
  Assert.AreEqual('TBaseline.Match → TBaselineTests.MatchFindet', mTest.Reasons[0].Text);
  Assert.IsTrue(TestNamed(mFound, 'Basis.Tests.TBaselineTests.LeerFindetNicht', mTest), Names(mFound));
  // Über den Klick-Handler eine Ebene weiter.
  Assert.IsTrue(TestNamed(mFound, 'Formular.Tests.TFormularTests.Klick', mTest), Names(mFound));
  // Tests, die Match nicht erreichen, fehlen; 2 von 5 sind keine ganze Fixture.
  Assert.IsFalse(TestNamed(mFound, 'Basis.Tests.TBaselineTests.UnabhaengigEins', mTest), Names(mFound));
  Assert.IsFalse(TestNamed(mFound, 'Basis.Tests.TBaselineTests', mTest), Names(mFound));
  Assert.AreEqual('main', mFound.Base);
end;

procedure TAffectedTestsTests.PrivateImplementationChangeReachesTestsWithPath;
var
  mFound: TAffectedResult;
  mTest: TAffectedTest;
begin
  // Normalize ist privat und steht nur im implementation-Teil geändert; Tests rufen es nie direkt.
  mFound := Determine([Input(BasisFile, LinesAt(UnitBasis, 'Result := AText'))]);
  Assert.IsFalse(mFound.All, mFound.AllReason);
  Assert.AreEqual(1, Integer(Length(mFound.Changes)));
  Assert.AreEqual('TBaseline.Normalize', mFound.Changes[0].Text);
  Assert.IsTrue(TestNamed(mFound, 'Basis.Tests.TBaselineTests.MatchFindet', mTest), Names(mFound));
  Assert.AreEqual('TBaseline.Normalize → TBaseline.Match → TBaselineTests.MatchFindet', mTest.Reasons[0].Text);
  Assert.IsFalse(mTest.Reasons[0].Inferred);
end;

procedure TAffectedTestsTests.InitializationChangeRunsUsingFixtures;
var
  mFound: TAffectedResult;
  mTest: TAffectedTest;
begin
  mFound := Determine([Input(BasisFile, LinesAt(UnitBasis, 'TBaseline.ClassName'))]);
  Assert.IsFalse(mFound.All, mFound.AllReason);
  // Alle Tests der Units, die Basis verwenden, als ganze Fixtures.
  Assert.IsTrue(TestNamed(mFound, 'Basis.Tests.TBaselineTests', mTest), Names(mFound));
  Assert.AreEqual('', mTest.Method);
  Assert.AreEqual('Unit Basis → Unit Basis.Tests', mTest.Reasons[0].Text);
  Assert.IsTrue(TestNamed(mFound, 'Formular.Tests.TFormularTests', mTest), Names(mFound));
  Assert.AreEqual(2, Integer(Length(mFound.Tests)), Names(mFound));
end;

procedure TAffectedTestsTests.FormChangeReachesFormTests;
var
  mFound: TAffectedResult;
  mTest: TAffectedTest;
begin
  mFound := Determine([WholeFile(FormularForm)]);
  Assert.IsFalse(mFound.All, mFound.AllReason);
  Assert.AreEqual(1, Integer(Length(mFound.Changes)));
  Assert.AreEqual('TForm1', mFound.Changes[0].Text);
  Assert.AreEqual('Formular', mFound.Changes[0].Place);
  Assert.AreEqual(FormularForm, mFound.Changes[0].Source);
  Assert.IsTrue(TestNamed(mFound, 'Formular.Tests.TFormularTests.Klick', mTest), Names(mFound));
  Assert.IsFalse(TestNamed(mFound, 'Basis.Tests.TBaselineTests.MatchFindet', mTest), Names(mFound));
end;

procedure TAffectedTestsTests.IncludeChangeCountsForIncludingUnit;
var
  mFound: TAffectedResult;
  mTest: TAffectedTest;
begin
  mFound := Determine([WholeFile(FormularInclude)]);
  Assert.IsFalse(mFound.All, mFound.AllReason);
  Assert.AreEqual(1, Integer(Length(mFound.Changes)));
  Assert.AreEqual('Include', mFound.Changes[0].Place);
  Assert.AreEqual(FormularInclude, mFound.Changes[0].Source);
  // Das {$I} steht außerhalb jeder Routine: die ganze Unit Formular.
  Assert.IsTrue(mFound.Changes[0].Kind = TAffectedChangeKind.WholeUnit);
  Assert.IsTrue(TestNamed(mFound, 'Formular.Tests.TFormularTests', mTest), Names(mFound));
  Assert.IsFalse(TestNamed(mFound, 'Basis.Tests.TBaselineTests', mTest), Names(mFound));
end;

procedure TAffectedTestsTests.CommentOnlyChangeIsSkipped;
var
  mFound: TAffectedResult;
begin
  mFound := Determine([Input(BasisFile, LinesAt(UnitBasis, '// nur ein Kommentar'))]);
  Assert.IsFalse(mFound.All);
  Assert.AreEqual(0, Integer(Length(mFound.Tests)));
  Assert.AreEqual(1, Integer(Length(mFound.Skipped)));
  Assert.AreEqual('nur Leerzeilen oder Kommentare', mFound.Skipped[0].Reason);
end;

procedure TAffectedTestsTests.TestProgramChangeNeedsAll;
var
  mFound: TAffectedResult;
begin
  mFound := Determine([WholeFile('C:\P\Tests.dproj')]);
  Assert.IsTrue(mFound.All);
  Assert.AreEqual('Testprogramm Tests.dproj geändert', mFound.AllReason);
  Assert.AreEqual(0, Integer(Length(mFound.Tests)));
end;

procedure TAffectedTestsTests.OtherFilesAreSkipped;
var
  mFound: TAffectedResult;
begin
  mFound := Determine([WholeFile('C:\P\README.md'), WholeFile('C:\Fremd\Fremd.pas'), WholeFile('C:\P\App.dproj')]);
  Assert.IsFalse(mFound.All);
  Assert.AreEqual(3, Integer(Length(mFound.Skipped)));
  Assert.AreEqual(0, Integer(Length(mFound.Tests)));
end;

procedure TAffectedTestsTests.CollapseAboveEightyPercent;
var
  mTests, mCollapsed: TArray<TAffectedTest>;
  mTotal: TFunc<TAffectedTest, Integer>;
  mRun: TFunc<TAffectedTest, TArray<string>>;
  mIndex: Integer;
begin
  mTotal :=
    function(ATest: TAffectedTest): Integer
    begin
      Result := 5;
    end;
  mRun :=
    function(ATest: TAffectedTest): TArray<string>
    begin
      Result := TArray<string>.Create('U.' + ATest.Fixture);
    end;
  mTests := nil;
  for mIndex := 1 to 4 do
    mTests := mTests + [Fake(Format('U.TFix.T%d', [mIndex]), 'TFix', Format('T%d', [mIndex]))];
  // 4 von 5 = 80 %: nicht mehr als 80 %, die Methoden bleiben.
  mCollapsed := TAffectedTests.Collapse(mTests, mTotal, mRun);
  Assert.AreEqual(4, Integer(Length(mCollapsed)));
  mTests := mTests + [Fake('U.TFix.T5', 'TFix', 'T5')];
  mCollapsed := TAffectedTests.Collapse(mTests, mTotal, mRun);
  Assert.AreEqual(1, Integer(Length(mCollapsed)));
  Assert.AreEqual('U.TFix', mCollapsed[0].Name);
  Assert.AreEqual('', mCollapsed[0].Method);
  Assert.AreEqual('U.TFix', mCollapsed[0].RunNames[0]);
end;

procedure TAffectedTestsTests.SortIsUniqueAndCaseInsensitive;
var
  mTests: TArray<TAffectedTest>;
begin
  mTests := TArray<TAffectedTest>.Create(Fake('b.X', 'b', 'X'), Fake('a.Y', 'a', 'Y'), Fake('A.y', 'A', 'y'),
    Fake('a.x', 'a', 'x'));
  TAffectedTests.Sort(mTests);
  // Ohne Groß-/Kleinschreibung a.x < a.y < b.x; Gleichstand (A.y, a.Y) ordinal.
  Assert.AreEqual('a.x', mTests[0].Name);
  Assert.AreEqual('A.y', mTests[1].Name);
  Assert.AreEqual('a.Y', mTests[2].Name);
  Assert.AreEqual('b.X', mTests[3].Name);
end;

procedure TAffectedTestsTests.FormatsParse;
var
  mFormat: TAffectedFormat;
begin
  Assert.IsTrue(TAffectedTests.TryParseFormat('', mFormat));
  Assert.IsTrue(mFormat = TAffectedFormat.Text);
  Assert.IsTrue(TAffectedTests.TryParseFormat('JSON', mFormat));
  Assert.IsTrue(mFormat = TAffectedFormat.Json);
  Assert.IsTrue(TAffectedTests.TryParseFormat('dunitx', mFormat));
  Assert.IsTrue(mFormat = TAffectedFormat.DUnitX);
  Assert.IsFalse(TAffectedTests.TryParseFormat('xml', mFormat));
end;

procedure TAffectedTestsTests.DUnitXArgumentJoinsRunNames;
var
  mFound: TAffectedResult;
  mArgument: string;
begin
  mFound := Default(TAffectedResult);
  mFound.Tests := TArray<TAffectedTest>.Create(Fake('U.TFix.A', 'TFix', 'A'), Fake('U.TFix.B', 'TFix', 'B'));
  Assert.IsTrue(TAffectedTests.DUnitXArgument(mFound, mArgument));
  Assert.AreEqual('--run:U.TFix.A,U.TFix.B', mArgument);
  Assert.AreEqual(mArgument, TAffectedTests.Render(mFound, TAffectedFormat.DUnitX));
  mFound.All := True;
  Assert.IsTrue(TAffectedTests.DUnitXArgument(mFound, mArgument));
  Assert.AreEqual('', mArgument);
  mFound.All := False;
  mFound.Tests[0].RunNames := TArray<string>.Create(StringOfChar('x', 30000));
  Assert.IsFalse(TAffectedTests.DUnitXArgument(mFound, mArgument));
end;

procedure TAffectedTestsTests.JsonRoundTrip;
var
  mFound, mBack: TAffectedResult;
  mJson: TJSONObject;
  mTest: TAffectedTest;
  mBase: string;
  mDepth, mRunCount: Integer;
  mAll: Boolean;
begin
  mFound := Determine([Input(BasisFile, LinesAt(UnitBasis, 'Result := AText'))]);
  mJson := TAffectedTests.ToJson(mFound);
  try
    // GetValue<T> erst in Variablen, nicht direkt als Argument von Assert.
    mBase := mJson.GetValue<string>('base');
    mDepth := mJson.GetValue<Integer>('depth');
    mAll := mJson.GetValue<Boolean>('all');
    mRunCount := mJson.GetValue<TJSONArray>('run').Count;
    Assert.AreEqual('main', mBase);
    Assert.AreEqual(3, mDepth);
    Assert.IsFalse(mAll);
    Assert.AreEqual(Integer(Length(mFound.RunNames)), mRunCount);
    mBack := TAffectedTests.FromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.AreEqual(Integer(Length(mFound.Tests)), Integer(Length(mBack.Tests)));
  Assert.IsTrue(TestNamed(mBack, 'Basis.Tests.TBaselineTests.MatchFindet', mTest), Names(mBack));
  Assert.AreEqual('TBaseline.Normalize → TBaseline.Match → TBaselineTests.MatchFindet', mTest.Reasons[0].Text);
end;

procedure TAffectedTestsTests.TextNamesTestsAndReasons;
var
  mText: string;
begin
  mText := TAffectedTests.Render(Determine([Input(BasisFile, LinesAt(UnitBasis, 'Result := Normalize'))]),
    TAffectedFormat.Text);
  Assert.IsTrue(Pos('Basis.Tests.TBaselineTests.MatchFindet', mText) > 0, mText);
  Assert.IsTrue(Pos('← TBaseline.Match → TBaselineTests.MatchFindet', mText) > 0, mText);
  Assert.IsTrue(Pos('run_tests tests: ', mText) > 0, mText);
end;

procedure TAffectedTestsTests.TwentyFilesInThousandUnitsStayFast;
const
  cUnits = 1000;
  cChanged = 20;
var
  mTexts, mFiles: TArray<string>;
  mIndex: Integer;
  mBig: ISymbolIndex;
  mResolver: TNameResolver;
  mRequest: TAffectedRequest;
  mInputs: TArray<TAffectedInput>;
  mWatch: TStopwatch;
  mFound: TAffectedResult;
begin
  // Kette Stufe0 ← Stufe1 ← …; jede zehnte Unit hat eine Testunit, die ihre Routine aufruft.
  SetLength(mTexts, cUnits + cUnits div 10);
  SetLength(mFiles, Length(mTexts));
  mBig := TSymbolIndex.Create;
  for mIndex := 0 to cUnits - 1 do
  begin
    mFiles[mIndex] := Format('C:\B\Stufe%d.pas', [mIndex]);
    if mIndex = 0 then
      mTexts[mIndex] := 'unit Stufe0;'#10'interface'#10'procedure Lauf0;'#10'implementation'#10 +
        'procedure Lauf0;'#10'begin'#10'end;'#10'end.'
    else
      mTexts[mIndex] := Format('unit Stufe%d;'#10'interface'#10'uses Stufe%d;'#10'procedure Lauf%d;'#10 +
        'implementation'#10'procedure Lauf%d;'#10'begin'#10'  Lauf%d;'#10'end;'#10'end.',
        [mIndex, mIndex - 1, mIndex, mIndex, mIndex - 1]);
  end;
  for mIndex := 0 to cUnits div 10 - 1 do
  begin
    mFiles[cUnits + mIndex] := Format('C:\B\Stufe%d.Tests.pas', [mIndex * 10]);
    mTexts[cUnits + mIndex] := Format('unit Stufe%d.Tests;'#10'interface'#10'uses DUnitX.TestFramework, Stufe%d;'#10 +
      'type'#10'  [TestFixture]'#10'  TStufe%dTests = class'#10'  public'#10'    [Test]'#10'    procedure Laeuft;'#10 +
      '  end;'#10'implementation'#10'procedure TStufe%dTests.Laeuft;'#10'begin'#10'  Lauf%d;'#10'end;'#10'end.',
      [mIndex * 10, mIndex * 10, mIndex * 10, mIndex * 10, mIndex * 10]);
  end;
  for mIndex := 0 to High(mTexts) do
    mBig.AddUnit(TIndexExtractor.ExtractText(mTexts[mIndex], mFiles[mIndex], nil, nil, True));
  mInputs := nil;
  for mIndex := 0 to cChanged - 1 do
    mInputs := mInputs + [Input(mFiles[mIndex * 37], LinesAt(mTexts[mIndex * 37], 'begin'))];
  mRequest := Default(TAffectedRequest);
  mRequest.Files := mFiles;
  mRequest.Options := TImpactOptions.Default;
  mRequest.Options.Depth := TAffectedTests.DefaultDepth;
  mRequest.Options.Tests := TImpactTestScope.FromProgram('{unit}.Tests', '');
  mResolver := TNameResolver.Create(mBig);
  try
    mWatch := TStopwatch.StartNew;
    mFound := TAffectedTests.Determine(mResolver, mBig, mInputs, mRequest,
      function(const AFileName: string; out AText: string): Boolean
      var
        mSlot: Integer;
      begin
        for mSlot := 0 to High(mFiles) do
          if SameText(mFiles[mSlot], AFileName) then
          begin
            AText := mTexts[mSlot];
            Exit(True);
          end;
        Result := False;
      end, nil);
    mWatch.Stop;
  finally
    mResolver.Free;
  end;
  Assert.IsFalse(mFound.All, mFound.AllReason);
  Assert.AreEqual(cChanged, Integer(Length(mFound.Changes)));
  Assert.IsTrue(Length(mFound.Tests) > 0, 'Tests der Stufen in Reichweite');
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 5000, Format('%d ms', [mWatch.ElapsedMilliseconds]));
end;

initialization
  TDUnitX.RegisterTestFixture(TAffectedTestsTests);

end.
