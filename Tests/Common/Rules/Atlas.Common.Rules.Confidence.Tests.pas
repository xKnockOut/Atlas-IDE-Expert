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
    procedure ConfidenceNamesForTextAndMachines;
    [Test]
    procedure UserSeverityErrorStillCappedByConfidence;
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
  /// <summary>Beispielregel: ein Treffer je Datei mit fester Konfidenz. AId wählt die Kennung; ob die Regel
  /// experimentell ist, sagt allein der Regelkatalog (#145), etwa für magic-number.</summary>
  TFixedRule = class(TInterfacedObject, IRule)
  private
    FConfidence: TRuleConfidence;
    FSeverity: TRuleSeverity;
    FId: string;
  public
    constructor Create(AConfidence: TRuleConfidence); overload;
    constructor Create(AConfidence: TRuleConfidence; ASeverity: TRuleSeverity); overload;
    constructor Create(AConfidence: TRuleConfidence; ASeverity: TRuleSeverity;
      const AId: string); overload;
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

constructor TFixedRule.Create(AConfidence: TRuleConfidence);
begin
  Create(AConfidence, TRuleSeverity.Error, 'fixed');
end;

constructor TFixedRule.Create(AConfidence: TRuleConfidence; ASeverity: TRuleSeverity);
begin
  Create(AConfidence, ASeverity, 'fixed');
end;

constructor TFixedRule.Create(AConfidence: TRuleConfidence; ASeverity: TRuleSeverity; const AId: string);
begin
  inherited Create;
  FConfidence := AConfidence;
  FSeverity := ASeverity;
  FId := AId;
end;

function TFixedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(FId, FSeverity, 'Ein Treffer je Datei');
end;

procedure TFixedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  AReport.Add(TTextRange.Create(0, 0, 0, 4), 'Treffer', FConfidence);
end;

const
  cSource = 'unit U; interface implementation end.';

{ TRuleConfidenceTests }

procedure TRuleConfidenceTests.HighConfidenceKeepsError;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TFixedRule.Create(TRuleConfidence.High), cSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
end;

procedure TRuleConfidenceTests.MediumConfidenceCapsErrorToWarning;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TFixedRule.Create(TRuleConfidence.Medium), cSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
end;

procedure TRuleConfidenceTests.LowConfidenceHiddenByDefault;
begin
  TRuleAssert.Silent(TFixedRule.Create(TRuleConfidence.Low), cSource);
end;

procedure TRuleConfidenceTests.LowConfidenceShownAsHintWhenThresholdLow;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TFixedRule.Create(TRuleConfidence.Low), cSource, '{ "minConfidence": "low" }');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
end;

procedure TRuleConfidenceTests.HighThresholdHidesMedium;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFixedRule.Create(TRuleConfidence.Medium), cSource,
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
  // magic-number ist laut Katalog nur im Profil strict aktiv ("profiles": ["strict"]).
  TRuleAssert.Silent(TFixedRule.Create(TRuleConfidence.High, TRuleSeverity.Warning, 'magic-number'), cSource);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(
    TFixedRule.Create(TRuleConfidence.High, TRuleSeverity.Warning, 'magic-number'), cSource,
    '{ "rules": { "magic-number": "off" } }'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(
    TFixedRule.Create(TRuleConfidence.High, TRuleSeverity.Warning, 'magic-number'), cSource,
    '{ "rules": { "magic-number": "warning" } }'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(
    TFixedRule.Create(TRuleConfidence.High, TRuleSeverity.Warning, 'magic-number'), cSource,
    '{ "profile": "strict" }'))));
end;

procedure TRuleConfidenceTests.ConfidenceNamesForTextAndMachines;
begin
  Assert.AreEqual('mittel', ConfidenceText(TRuleConfidence.Medium));
  Assert.AreEqual('niedrig', ConfidenceText(TRuleConfidence.Low));
  Assert.AreEqual('high', ConfidenceName(TRuleConfidence.High));
  Assert.AreEqual('medium', ConfidenceName(TRuleConfidence.Medium));
  Assert.AreEqual('low', ConfidenceName(TRuleConfidence.Low));
end;

procedure TRuleConfidenceTests.UserSeverityErrorStillCappedByConfidence;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Der Deckel gilt auch, wenn der Benutzer "error" einstellt.
  mFindings := TRuleAssert.Findings(TFixedRule.Create(TRuleConfidence.Medium, TRuleSeverity.Hint), cSource,
    '{ "rules": { "fixed": "error" } }');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  mFindings := TRuleAssert.Findings(TFixedRule.Create(TRuleConfidence.Low, TRuleSeverity.Hint), cSource,
    '{ "minConfidence": "low", "rules": { "fixed": { "severity": "error" } } }');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
end;

procedure TRuleConfidenceTests.ParsesMinConfidence;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(TServerSettings.Default.MinConfidence));
  Assert.AreEqual(Ord(TRuleConfidence.Low),
    Ord(TConfigurationParser.Parse('{ "minConfidence": "low" }', mIssues).MinConfidence));
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;

procedure TRuleConfidenceTests.RejectsUnknownMinConfidence;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  TConfigurationParser.Parse('{ "minConfidence": "sicher" }', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleConfidenceTests);

end.
