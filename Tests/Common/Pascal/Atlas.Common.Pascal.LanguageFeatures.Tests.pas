unit Atlas.Common.Pascal.LanguageFeatures.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLanguageFeaturesTests = class
  public
    [Test]
    procedure ParsesVersions;
    [Test]
    procedure ReportsNothingWithoutVersion;
    [Test]
    procedure ReportsInlineVarBeforeRio;
    [Test]
    procedure AcceptsInlineVarFromRio;
    [Test]
    procedure ReportsIfExpressionBefore37;
    [Test]
    procedure ReportsManagedRecordBefore21;
    [Test]
    procedure ReportsMultilineStringBefore23;
    [Test]
    procedure ParsesIfExpression;
    [Test]
    procedure ReportsDigitSeparatorAndBinaryBefore11;
    [Test]
    procedure ReportsIsNotAndNotInBefore13;
    [Test]
    procedure ParsesIsNotAndNotIn;
    [Test]
    procedure InactiveBranchIsSilent;
    [Test]
    procedure MessageNamesProducts;
    [Test]
    procedure LanguageLevelIsTheOlderVersion;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Lsp.InactiveRegions,
  Atlas.Common.Pascal.LanguageFeatures;

function Findings(const ASource, AVersion: string): TArray<TLanguageFeatureFinding>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(ASource);
  try
    Result := TLanguageFeatures.Check(mTree, AVersion);
  finally
    mTree.Free;
  end;
end;

const
  cInlineVarSource =
    'unit A;'#13#10'interface'#13#10'implementation'#13#10 +
    'procedure P;'#13#10'begin'#13#10'  var X := 1;'#13#10'end;'#13#10'end.';
  cIfExprSource =
    'unit A;'#13#10'interface'#13#10'implementation'#13#10 +
    'procedure P;'#13#10'var X: Integer;'#13#10'begin'#13#10 +
    '  X := if X > 0 then 1 else 2;'#13#10'end;'#13#10'end.';

{ TLanguageFeaturesTests }

procedure TLanguageFeaturesTests.ParsesVersions;
begin
  Assert.AreEqual(37000, TLanguageFeatures.ParseVersion('37.0'));
  Assert.AreEqual(22000, TLanguageFeatures.ParseVersion('22'));
  Assert.AreEqual(-1, TLanguageFeatures.ParseVersion(''));
  Assert.AreEqual(-1, TLanguageFeatures.ParseVersion('abc'));
  Assert.IsTrue(TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, '20.0'));
  Assert.IsFalse(TLanguageFeatures.IsAvailable(TLanguageFeature.InlineVariable, '19.0'));
  // Codes der Compilermeldungen je Version (#1382): ohne gültige Version gilt die neueste.
  Assert.IsTrue(TLanguageFeatures.IsAtLeast('37.0', '37.0'));
  Assert.IsFalse(TLanguageFeatures.IsAtLeast('23.0', '37.0'));
  Assert.IsTrue(TLanguageFeatures.IsAtLeast('', '37.0'));
end;

procedure TLanguageFeaturesTests.ReportsNothingWithoutVersion;
begin
  Assert.AreEqual(0, Integer(Length(Findings(cInlineVarSource, ''))));
end;

procedure TLanguageFeaturesTests.ReportsInlineVarBeforeRio;
var
  mItems: TArray<TLanguageFeatureFinding>;
begin
  mItems := Findings(cInlineVarSource, '19.0');
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual<TLanguageFeature>(TLanguageFeature.InlineVariable, mItems[0].Feature);
  Assert.AreEqual(5, mItems[0].StartPos.Line);
  Assert.IsTrue(Pos('Delphi 10.3 Rio', mItems[0].Message) > 0);
end;

procedure TLanguageFeaturesTests.AcceptsInlineVarFromRio;
begin
  Assert.AreEqual(0, Integer(Length(Findings(cInlineVarSource, '20.0'))));
end;

procedure TLanguageFeaturesTests.ReportsIfExpressionBefore37;
var
  mItems: TArray<TLanguageFeatureFinding>;
begin
  mItems := Findings(cIfExprSource, '36.0');
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual<TLanguageFeature>(TLanguageFeature.IfExpression, mItems[0].Feature);
  Assert.AreEqual(0, Integer(Length(Findings(cIfExprSource, '37.0'))));
end;

procedure TLanguageFeaturesTests.ReportsManagedRecordBefore21;
const
  cSource =
    'unit A;'#13#10'interface'#13#10'type'#13#10'  TR = record'#13#10 +
    '    class operator Initialize(out Dest: TR);'#13#10'  end;'#13#10 +
    'implementation'#13#10'end.';
var
  mItems: TArray<TLanguageFeatureFinding>;
begin
  mItems := Findings(cSource, '20.0');
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual<TLanguageFeature>(TLanguageFeature.ManagedRecord, mItems[0].Feature);
  Assert.AreEqual(0, Integer(Length(Findings(cSource, '21.0'))));
end;

procedure TLanguageFeaturesTests.ReportsMultilineStringBefore23;
const
  cSource =
    'unit A;'#13#10'interface'#13#10'const'#13#10'  S = '''''''#13#10 +
    '    Text'#13#10'    '''''';'#13#10'implementation'#13#10'end.';
var
  mItems: TArray<TLanguageFeatureFinding>;
begin
  mItems := Findings(cSource, '22.0');
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual<TLanguageFeature>(TLanguageFeature.MultilineString, mItems[0].Feature);
  Assert.AreEqual(0, Integer(Length(Findings(cSource, '23.0'))));
end;

procedure TLanguageFeaturesTests.ParsesIfExpression;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cIfExprSource);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
  finally
    mTree.Free;
  end;
end;

const
  cOperatorSource =
    'unit A;'#13#10'interface'#13#10'implementation'#13#10 +
    'procedure P(O: TObject; C: Integer);'#13#10'begin'#13#10 +
    '  if O is not TObject then'#13#10'    Exit;'#13#10 +
    '  if C not in [1, 2] then'#13#10'    Exit;'#13#10'end;'#13#10'end.';

procedure TLanguageFeaturesTests.ReportsDigitSeparatorAndBinaryBefore11;
const
  cSource =
    'unit A;'#13#10'interface'#13#10'const'#13#10'  Million = 1_000_000;'#13#10 +
    '  Maske = %1010;'#13#10'  Hex = $FF;'#13#10'implementation'#13#10'end.';
var
  mItems: TArray<TLanguageFeatureFinding>;
begin
  mItems := Findings(cSource, '21.0');
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual<TLanguageFeature>(TLanguageFeature.DigitSeparator, mItems[0].Feature);
  Assert.AreEqual(3, mItems[0].StartPos.Line);
  Assert.AreEqual<TLanguageFeature>(TLanguageFeature.BinaryLiteral, mItems[1].Feature);
  Assert.AreEqual(4, mItems[1].StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Findings(cSource, '22.0'))));
end;

procedure TLanguageFeaturesTests.ReportsIsNotAndNotInBefore13;
var
  mItems: TArray<TLanguageFeatureFinding>;
begin
  mItems := Findings(cOperatorSource, '23.0');
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual<TLanguageFeature>(TLanguageFeature.IsNotOperator, mItems[0].Feature);
  Assert.AreEqual(5, mItems[0].StartPos.Line);
  Assert.AreEqual<TLanguageFeature>(TLanguageFeature.NotInOperator, mItems[1].Feature);
  Assert.AreEqual(7, mItems[1].StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Findings(cOperatorSource, '37.0'))));
  // "not (C in S)" und "not X" sind alte Schreibweisen.
  Assert.AreEqual(0, Integer(Length(Findings(StringReplace(StringReplace(cOperatorSource, 'is not TObject',
    'is TObject', []), 'C not in [1, 2]', 'not (C in [1, 2])', []), '23.0'))));
end;

procedure TLanguageFeaturesTests.ParsesIsNotAndNotIn;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cOperatorSource);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
  finally
    mTree.Free;
  end;
end;

procedure TLanguageFeaturesTests.InactiveBranchIsSilent;
const
  cSource =
    'unit A;'#13#10'interface'#13#10'implementation'#13#10 +
    'procedure P;'#13#10'begin'#13#10'{$IF CompilerVersion >= 33}'#13#10'  var X := 1;'#13#10 +
    '{$IFEND}'#13#10'end;'#13#10'end.';
var
  mTree: TSyntaxTree;
  mInactive: TArray<TTextRange>;
begin
  // Delphi 10.2 (BDS 19.0) hat CompilerVersion 32: der Zweig ist inaktiv.
  mInactive := TLspInactiveRegions.Ranges(cSource,
    TPascalPreprocessor.PredefinedSymbols('Win64', TPascalPreprocessor.CompilerVersionOfBds(19.0)));
  Assert.AreEqual(1, Integer(Length(mInactive)));
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.AreEqual(0, Integer(Length(TLanguageFeatures.Check(mTree, '19.0', mInactive))));
    Assert.AreEqual(1, Integer(Length(TLanguageFeatures.Check(mTree, '19.0'))));
  finally
    mTree.Free;
  end;
end;

procedure TLanguageFeaturesTests.MessageNamesProducts;
var
  mItems: TArray<TLanguageFeatureFinding>;
begin
  Assert.AreEqual('Delphi 13 Florence', TLanguageFeatures.ProductName('37.0'));
  Assert.AreEqual('Delphi 12 Athens', TLanguageFeatures.ProductName('23'));
  Assert.AreEqual('BDS 30.0', TLanguageFeatures.ProductName('30.0'));
  mItems := Findings(cIfExprSource, '23.0');
  Assert.AreEqual(1, Integer(Length(mItems)));
  Assert.AreEqual('If-Ausdruck erst ab Delphi 13 Florence verfügbar (eingestellt: Delphi 12 Athens)', mItems[0].Message);
end;

procedure TLanguageFeaturesTests.LanguageLevelIsTheOlderVersion;
begin
  // #1126: minDelphiVersion senkt den Sprachstand, hebt ihn aber nie.
  Assert.AreEqual('23.0', TLanguageFeatures.LanguageLevel('37.0', '23.0'));
  Assert.AreEqual('23.0', TLanguageFeatures.LanguageLevel('23.0', '37.0'));
  Assert.AreEqual('23.0', TLanguageFeatures.LanguageLevel('', '23.0'));
  Assert.AreEqual('37.0', TLanguageFeatures.LanguageLevel('37.0', ''));
  Assert.AreEqual('37.0', TLanguageFeatures.LanguageLevel('37.0', 'neu'));
  Assert.AreEqual('', TLanguageFeatures.LanguageLevel('', ''));
  Assert.IsFalse(TLanguageFeatures.IsAvailable(TLanguageFeature.IsNotOperator,
    TLanguageFeatures.LanguageLevel('37.0', '23.0')));
end;

initialization
  TDUnitX.RegisterTestFixture(TLanguageFeaturesTests);

end.
