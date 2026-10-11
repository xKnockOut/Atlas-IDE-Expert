unit Atlas.Common.Rules.Confidence.Tests;

// Tests für die Konfidenzpolitik der Regeltreffer (#144).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleConfidenceTests = class
  public
    [Test]
    procedure HighConfidenceKeepsError;
    [Test]
    procedure MediumConfidenceCapsErrorToWarning;
    [Test]
    procedure LowConfidenceHiddenByDefault;
    [Test]
    procedure LowConfidenceShownAsHintWhenThresholdLow;
    [Test]
    procedure HighThresholdHidesMedium;
    [Test]
    procedure CapNeverRaisesSeverity;
    [Test]
    procedure ExperimentalRuleNeedsExplicitConfiguration;
    [Test]
    procedure DisplayMessageShowsConfidence;
    [Test]
    procedure ParsesMinConfidence;
    [Test]
    procedure RejectsUnknownMinConfidence;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Tests.RuleAssert;

type
  /// <summary>Beispielregel: ein Treffer je Datei mit fester Konfidenz.</summary>
  TFixedRule = class(TInterfacedObject, IRule)
  private
    FConfidence: TRuleConfidence;
    FSeverity: TRuleSeverity;
    FExperimental: Boolean;
  public
    constructor Create(AConfidence: TRuleConfidence; ASeverity: TRuleSeverity = TRuleSeverity.Error;
      AExperimental: Boolean = False);
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

constructor TFixedRule.Create(AConfidence: TRuleConfidence; ASeverity: TRuleSeverity; AExperimental: Boolean);
begin
  inherited Create;
  FConfidence := AConfidence;
  FSeverity := ASeverity;
  FExperimental := AExperimental;
end;

function TFixedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('fixed', FSeverity, 'Ein Treffer je Datei', FExperimental);
end;

procedure TFixedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  AReport.Add(TTextRange.Create(0, 0, 0, 4), 'Treffer', FConfidence);
end;

const
  Source = 'unit U; interface implementation end.';

{ TRuleConfidenceTests }

procedure TRuleConfidenceTests.HighConfidenceKeepsError;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TFixedRule.Create(TRuleConfidence.High), Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
end;

procedure TRuleConfidenceTests.MediumConfidenceCapsErrorToWarning;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TFixedRule.Create(TRuleConfidence.Medium), Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
end;

procedure TRuleConfidenceTests.LowConfidenceHiddenByDefault;
begin
  TRuleAssert.Silent(TFixedRule.Create(TRuleConfidence.Low), Source);
end;

procedure TRuleConfidenceTests.LowConfidenceShownAsHintWhenThresholdLow;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TFixedRule.Create(TRuleConfidence.Low), Source, '{ "minConfidence": "low" }');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
end;

procedure TRuleConfidenceTests.HighThresholdHidesMedium;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFixedRule.Create(TRuleConfidence.Medium), Source,
    '{ "minConfidence": "high" }'))));
end;

procedure TRuleConfidenceTests.CapNeverRaisesSeverity;
begin
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(TRuleEngine.CapSeverity(TRuleSeverity.Hint, TRuleConfidence.Medium)));
  Assert.AreEqual(Ord(TRuleSeverity.Information),
    Ord(TRuleEngine.CapSeverity(TRuleSeverity.Information, TRuleConfidence.High)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(TRuleEngine.CapSeverity(TRuleSeverity.Warning, TRuleConfidence.Low)));
end;

procedure TRuleConfidenceTests.ExperimentalRuleNeedsExplicitConfiguration;
begin
  TRuleAssert.Silent(TFixedRule.Create(TRuleConfidence.High, TRuleSeverity.Warning, True), Source);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(
    TFixedRule.Create(TRuleConfidence.High, TRuleSeverity.Warning, True), Source,
    '{ "rules": { "fixed": "off" } }'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(
    TFixedRule.Create(TRuleConfidence.High, TRuleSeverity.Warning, True), Source,
    '{ "rules": { "fixed": "warning" } }'))));
end;

procedure TRuleConfidenceTests.DisplayMessageShowsConfidence;
var
  Finding: TRuleFinding;
begin
  Finding := Default(TRuleFinding);
  Finding.Message := 'Leerer except-Block';
  Finding.Confidence := TRuleConfidence.High;
  Assert.AreEqual('Leerer except-Block', Finding.DisplayMessage);
  Finding.Confidence := TRuleConfidence.Medium;
  Assert.AreEqual('Leerer except-Block (Konfidenz: mittel)', Finding.DisplayMessage);
end;

procedure TRuleConfidenceTests.ParsesMinConfidence;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(TServerSettings.Default.MinConfidence));
  Assert.AreEqual(Ord(TRuleConfidence.Low),
    Ord(TConfigurationParser.Parse('{ "minConfidence": "low" }', Issues).MinConfidence));
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

procedure TRuleConfidenceTests.RejectsUnknownMinConfidence;
var
  Issues: TArray<TConfigurationIssue>;
begin
  TConfigurationParser.Parse('{ "minConfidence": "sicher" }', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleConfidenceTests);

end.
