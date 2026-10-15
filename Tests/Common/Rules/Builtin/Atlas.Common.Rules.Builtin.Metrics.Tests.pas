unit Atlas.Common.Rules.Builtin.Metrics.Tests;

// Tests der Metrik-Regeln (#66): Treffer mit Regel-ID auf dem Methodennamen,
// Unterdrückung per Kommentar, Grenzwerte aus atlas.json ("max").

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMetricRulesTests = class
  public
    [Test]
    procedure ParameterCountReportsOnName;
    [Test]
    procedure ParameterCountAtLimitSilent;
    [Test]
    procedure CyclomaticUsesMaxFromConfiguration;
    [Test]
    procedure SuppressedByComment;
    [Test]
    procedure MethodLengthReports;
    [Test]
    procedure NestingDepthReports;
    [Test]
    procedure CognitiveReports;
    [Test]
    procedure LimitsFromSettings;
    [Test]
    procedure InvalidMaxKeepsDefault;
    [Test]
    procedure RulesAreRegistered;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Metrics,
  Atlas.Tests.RuleAssert;

function InUnit(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10 + ABody + #10'end.';
end;

const
  SevenParameters = 'procedure Book(A, B, C, D, E, F, G: Integer);'#10'begin'#10'end;';
  SixParameters = 'procedure Book(A, B, C, D, E, F: Integer);'#10'begin'#10'end;';
  /// <summary>Zyklomatisch 4: drei if.</summary>
  ThreeIfs = 'procedure Run;'#10'begin'#10'  if A then X;'#10'  if B then Y;'#10'  if C then Z;'#10'end;';

{ TMetricRulesTests }

procedure TMetricRulesTests.ParameterCountReportsOnName;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMetricRule.Create(TMetricKind.ParameterCount), InUnit(SevenParameters));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(ParameterCountRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(14, Findings[0].Range.EndPos.Character);
  Assert.AreEqual('Methode Book hat 7 Parameter (Grenzwert 6); zusammengehörige Werte bündeln', Findings[0].Message);
end;

procedure TMetricRulesTests.ParameterCountAtLimitSilent;
begin
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.ParameterCount), InUnit(SixParameters));
end;

procedure TMetricRulesTests.CyclomaticUsesMaxFromConfiguration;
var
  Findings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.Cyclomatic), InUnit(ThreeIfs));
  Findings := TRuleAssert.Findings(TMetricRule.Create(TMetricKind.Cyclomatic), InUnit(ThreeIfs),
    '{"rules": {"metric-cyclomatic-complexity": {"severity": "warning", "max": 3}}}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(CyclomaticComplexityRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual('Methode Run hat zyklomatische Komplexität 4 (Grenzwert 3)', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMetricRule.Create(TMetricKind.Cyclomatic), InUnit(ThreeIfs),
    '{"rules": {"metric-cyclomatic-complexity": {"max": 4}}}'))), 'der Grenzwert selbst ist erlaubt');
end;

procedure TMetricRulesTests.SuppressedByComment;
begin
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.ParameterCount),
    InUnit('// lsp-ignore: metric-parameter-count'#10 + SevenParameters));
  TRuleAssert.Reports(TMetricRule.Create(TMetricKind.ParameterCount),
    InUnit('// lsp-ignore: metric-method-length'#10 + SevenParameters));
end;

procedure TMetricRulesTests.MethodLengthReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMetricRule.Create(TMetricKind.MethodLength),
    InUnit('procedure Run;'#10'begin'#10'  // Kommentar'#10#10'  X;'#10'end;'),
    '{"rules": {"metric-method-length": {"max": 3}}}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Methode Run hat 4 Codezeilen (Grenzwert 3); in kleinere Methoden aufteilen', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMetricRule.Create(TMetricKind.MethodLength),
    InUnit('procedure Run;'#10'begin'#10'  // Kommentar'#10#10'  X;'#10'end;'),
    '{"rules": {"metric-method-length": {"max": 4}}}'))), 'Kommentar und Leerzeile zählen nicht');
end;

procedure TMetricRulesTests.NestingDepthReports;
const
  Deep = 'procedure Run;'#10'begin'#10'  if A then'#10'    while B do'#10'      try'#10'        X;'#10 +
    '      finally'#10'        Y;'#10'      end;'#10'end;';
begin
  TRuleAssert.Silent(TMetricRule.Create(TMetricKind.NestingDepth), InUnit(Deep));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMetricRule.Create(TMetricKind.NestingDepth), InUnit(Deep),
    '{"rules": {"metric-nesting-depth": {"max": 2}}}'))));
end;

procedure TMetricRulesTests.CognitiveReports;
const
  // if (1) + for (2, Ebene 1) + if (3, Ebene 2) = 6
  Nested = 'procedure Run;'#10'begin'#10'  if A then'#10'    for I := 0 to 9 do'#10'      if B then'#10 +
    '        X;'#10'end;';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMetricRule.Create(TMetricKind.Cognitive), InUnit(Nested),
    '{"rules": {"metric-cognitive-complexity": {"max": 5}}}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Methode Run hat kognitive Komplexität 6 (Grenzwert 5)', Findings[0].Message);
end;

procedure TMetricRulesTests.LimitsFromSettings;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
  Limits: TMetricLimits;
begin
  Settings := TConfigurationParser.Parse('{"rules": {"metric-parameter-count": {"max": 4}, ' +
    '"metric-method-length": "off"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Limits := TMetricRules.Limits(Settings);
  Assert.AreEqual(4, Limits.Values[TMetricKind.ParameterCount]);
  Assert.AreEqual(60, Limits.Values[TMetricKind.MethodLength]);
  Assert.AreEqual(15, Limits.Values[TMetricKind.Cyclomatic]);
end;

procedure TMetricRulesTests.InvalidMaxKeepsDefault;
begin
  Assert.AreEqual(15, TMetricRules.LimitFromOptions('{"max": 0}', 15));
  Assert.AreEqual(15, TMetricRules.LimitFromOptions('{"max": 2.5}', 15));
  Assert.AreEqual(15, TMetricRules.LimitFromOptions('{"max": "10"}', 15));
  Assert.AreEqual(15, TMetricRules.LimitFromOptions('', 15));
  Assert.AreEqual(10, TMetricRules.LimitFromOptions('{"severity": "warning", "max": 10}', 15));
end;

procedure TMetricRulesTests.RulesAreRegistered;
var
  Rule: IRule;
  Found: string;
begin
  Found := '';
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id.StartsWith('metric-') then
      Found := Found + Rule.Descriptor.Id + ' ';
  Assert.AreEqual('metric-method-length metric-nesting-depth metric-cyclomatic-complexity ' +
    'metric-cognitive-complexity metric-parameter-count ', Found);
end;

initialization
  TDUnitX.RegisterTestFixture(TMetricRulesTests);

end.
