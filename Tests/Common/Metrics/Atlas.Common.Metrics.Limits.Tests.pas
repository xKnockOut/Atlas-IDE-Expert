unit Atlas.Common.Metrics.Limits.Tests;

// Tests der Grenzwerte der Code-Metriken aus den Einstellungen (#66): Option "max", Vorgaben bei fehlenden und
// ungültigen Werten, Regel-IDs je Kennzahl.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMetricSettingsTests = class
  public
    [Test]
    procedure LimitsFromSettings;
    [Test]
    procedure InvalidMaxKeepsDefault;
    [Test]
    procedure RuleIdsPerKind;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Limits;

{ TMetricSettingsTests }

procedure TMetricSettingsTests.LimitsFromSettings;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
  mLimits: TMetricLimits;
begin
  mSettings := TConfigurationParser.Parse('{"rules": {"metric-parameter-count": {"max": 4}, ' +
    '"metric-method-length": "off"}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  mLimits := TMetricSettings.Limits(mSettings);
  Assert.AreEqual(4, mLimits.Values[TMetricKind.ParameterCount]);
  Assert.AreEqual(60, mLimits.Values[TMetricKind.MethodLength]);
  Assert.AreEqual(15, mLimits.Values[TMetricKind.Cyclomatic]);
end;

procedure TMetricSettingsTests.InvalidMaxKeepsDefault;
begin
  Assert.AreEqual(15, TMetricSettings.LimitFromOptions('{"max": 0}', 15));
  Assert.AreEqual(15, TMetricSettings.LimitFromOptions('{"max": 2.5}', 15));
  Assert.AreEqual(15, TMetricSettings.LimitFromOptions('{"max": "10"}', 15));
  Assert.AreEqual(15, TMetricSettings.LimitFromOptions('', 15));
  Assert.AreEqual(10, TMetricSettings.LimitFromOptions('{"severity": "warning", "max": 10}', 15));
end;

procedure TMetricSettingsTests.RuleIdsPerKind;
begin
  Assert.AreEqual(cCyclomaticComplexityRuleId, TMetricSettings.RuleId(TMetricKind.Cyclomatic));
  Assert.AreEqual(cExitPointsRuleId, TMetricSettings.RuleId(TMetricKind.ExitPoints));
  Assert.AreEqual(cClassSizeRuleId, TMetricSettings.RuleId(TStructureKind.ClassSize));
  Assert.AreEqual(cInheritanceDepthRuleId, TMetricSettings.RuleId(TStructureKind.InheritanceDepth));
end;

end.
