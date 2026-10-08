unit BDLsp.Common.Pascal.LanguageFeatures.Tests;

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
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Pascal.LanguageFeatures;

function Findings(const ASource, AVersion: string): TArray<TLanguageFeatureFinding>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(ASource);
  try
    Result := TLanguageFeatures.Check(Tree, AVersion);
  finally
    Tree.Free;
  end;
end;

const
  InlineVarSource =
    'unit A;'#13#10'interface'#13#10'implementation'#13#10 +
    'procedure P;'#13#10'begin'#13#10'  var X := 1;'#13#10'end;'#13#10'end.';
  IfExprSource =
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
end;

procedure TLanguageFeaturesTests.ReportsNothingWithoutVersion;
begin
  Assert.AreEqual(0, Integer(Length(Findings(InlineVarSource, ''))));
end;

procedure TLanguageFeaturesTests.ReportsInlineVarBeforeRio;
var
  Items: TArray<TLanguageFeatureFinding>;
begin
  Items := Findings(InlineVarSource, '19.0');
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.IsTrue(Items[0].Feature = TLanguageFeature.InlineVariable);
  Assert.AreEqual(5, Items[0].StartPos.Line);
  Assert.IsTrue(Pos('20.0', Items[0].Message) > 0);
end;

procedure TLanguageFeaturesTests.AcceptsInlineVarFromRio;
begin
  Assert.AreEqual(0, Integer(Length(Findings(InlineVarSource, '20.0'))));
end;

procedure TLanguageFeaturesTests.ReportsIfExpressionBefore37;
var
  Items: TArray<TLanguageFeatureFinding>;
begin
  Items := Findings(IfExprSource, '36.0');
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.IsTrue(Items[0].Feature = TLanguageFeature.IfExpression);
  Assert.AreEqual(0, Integer(Length(Findings(IfExprSource, '37.0'))));
end;

procedure TLanguageFeaturesTests.ReportsManagedRecordBefore21;
const
  Source =
    'unit A;'#13#10'interface'#13#10'type'#13#10'  TR = record'#13#10 +
    '    class operator Initialize(out Dest: TR);'#13#10'  end;'#13#10 +
    'implementation'#13#10'end.';
var
  Items: TArray<TLanguageFeatureFinding>;
begin
  Items := Findings(Source, '20.0');
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.IsTrue(Items[0].Feature = TLanguageFeature.ManagedRecord);
  Assert.AreEqual(0, Integer(Length(Findings(Source, '21.0'))));
end;

procedure TLanguageFeaturesTests.ReportsMultilineStringBefore23;
const
  Source =
    'unit A;'#13#10'interface'#13#10'const'#13#10'  S = '''''''#13#10 +
    '    Text'#13#10'    '''''';'#13#10'implementation'#13#10'end.';
var
  Items: TArray<TLanguageFeatureFinding>;
begin
  Items := Findings(Source, '22.0');
  Assert.AreEqual(1, Integer(Length(Items)));
  Assert.IsTrue(Items[0].Feature = TLanguageFeature.MultilineString);
  Assert.AreEqual(0, Integer(Length(Findings(Source, '23.0'))));
end;

procedure TLanguageFeaturesTests.ParsesIfExpression;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(IfExprSource);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLanguageFeaturesTests);

end.
