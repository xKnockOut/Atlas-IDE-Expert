unit Rules.Providers.RuleDocs.Tests;

// Tests für den Anbieter von IRuleDocs: Regeln des Katalogs als Werte in beiden Sprachen, wirksamer Schweregrad mit
// Herkunft (rules, Gruppe, Kennzahlen, Profil) und Optionen aus den Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleDocsProviderTests = class
  public
    [Test]
    procedure RulesCarryCatalogValues;
    [Test]
    procedure RulesFollowLanguage;
    [Test]
    procedure StateFromProfileByDefault;
    [Test]
    procedure StateFromRulesSetting;
    [Test]
    procedure StateFromGroupSwitch;
    [Test]
    procedure StateFromMetricsSwitch;
    [Test]
    procedure StateCarriesProjectOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Findings.Contract,
  Rules.Contract.Api,
  Rules.Catalog,
  Rules.Providers.RuleDocs;

function DocsOf: IRuleDocs;
begin
  Result := TRuleDocsProvider.Create;
end;

function Find(const ARules: TArray<TFindingRuleInfo>; const AId: string): TFindingRuleInfo;
var
  mRule: TFindingRuleInfo;
begin
  Result := Default(TFindingRuleInfo);
  for mRule in ARules do
  begin
    if mRule.Id = AId then
    begin
      Exit(mRule);
    end;
  end;
  Assert.Fail('Regel fehlt: ' + AId);
end;

function SettingsWith(const AJson: string): TServerSettings;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Result := TConfigurationParser.Parse(AJson, mIssues);
end;

{ TRuleDocsProviderTests }

procedure TRuleDocsProviderTests.RulesCarryCatalogValues;
var
  mRules: TArray<TFindingRuleInfo>;
  mRule: TFindingRuleInfo;
  mEntry: TRuleCatalogEntry;
begin
  mRules := DocsOf.Rules('en');
  Assert.AreEqual(Integer(Length(TRuleCatalog.Shared.Entries)), Integer(Length(mRules)));
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('empty-except', mEntry));
  mRule := Find(mRules, 'empty-except');
  Assert.AreEqual(mEntry.Name, mRule.Name);
  Assert.AreEqual(mEntry.Description, mRule.Description);
  Assert.AreEqual(TRuleCatalog.CategoryName(mEntry.Category), mRule.Category);
  Assert.AreEqual(TRuleCatalog.GroupName(mEntry.Group), mRule.Group);
  Assert.AreEqual(TRuleCatalog.GroupKey(mEntry.Group), mRule.GroupKey);
  Assert.AreEqual(Ord(mEntry.DefaultSeverity), Ord(mRule.DefaultSeverity));
  Assert.AreEqual(mEntry.Bad, mRule.Bad);
  Assert.AreEqual(mEntry.Good, mRule.Good);
  Assert.AreEqual(TRuleCatalog.HelpUri('empty-except'), mRule.HelpUri);
  Assert.IsTrue(Find(mRules, 'magic-number').Experimental);
  Assert.IsFalse(mRule.Experimental);
  Assert.AreEqual('F2069', string.Join(',', Find(mRules, 'line-length').CompilerCodes));
end;

procedure TRuleDocsProviderTests.RulesFollowLanguage;
var
  mEntry: TRuleCatalogEntry;
begin
  Assert.IsTrue(TRuleCatalog.InLanguage(TTextLanguage.German).TryFind('empty-except', mEntry));
  Assert.AreEqual(mEntry.Name, Find(DocsOf.Rules('de'), 'empty-except').Name);
  Assert.AreNotEqual(mEntry.Name, Find(DocsOf.Rules('en'), 'empty-except').Name);
  Assert.AreEqual(Find(DocsOf.Rules('en'), 'empty-except').Name, Find(DocsOf.Rules('xx'), 'empty-except').Name);
end;

procedure TRuleDocsProviderTests.StateFromProfileByDefault;
var
  mState: TFindingRuleState;
begin
  mState := DocsOf.State('empty-except', TServerSettings.Default);
  Assert.AreEqual(Ord(TFindingRuleOrigin.Profile), Ord(mState.Origin));
  Assert.AreEqual('standard', mState.Detail);
  Assert.AreNotEqual(Ord(TRuleSeverity.Off), Ord(mState.Severity));
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(DocsOf.State('magic-number', TServerSettings.Default).Severity));
end;

procedure TRuleDocsProviderTests.StateFromRulesSetting;
var
  mState: TFindingRuleState;
begin
  mState := DocsOf.State('empty-except', SettingsWith('{"rules":{"empty-except":"hint"}}'));
  Assert.AreEqual(Ord(TFindingRuleOrigin.Rules), Ord(mState.Origin));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mState.Severity));
  Assert.AreEqual('', mState.Detail);
end;

procedure TRuleDocsProviderTests.StateFromGroupSwitch;
var
  mEntry: TRuleCatalogEntry;
  mKey: string;
  mState: TFindingRuleState;
begin
  Assert.IsTrue(TRuleCatalog.Shared.TryFind('empty-except', mEntry));
  mKey := TRuleCatalog.GroupKey(mEntry.Group);
  mState := DocsOf.State('empty-except', SettingsWith('{"rules":{"' + mKey + '":"off"}}'));
  Assert.AreEqual(Ord(TFindingRuleOrigin.Group), Ord(mState.Origin));
  Assert.AreEqual(mKey, mState.Detail);
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(mState.Severity));
end;

procedure TRuleDocsProviderTests.StateFromMetricsSwitch;
begin
  Assert.AreEqual(Ord(TFindingRuleOrigin.Metrics),
    Ord(DocsOf.State('metric-cyclomatic-complexity', SettingsWith('{"metrics":false}')).Origin));
end;

procedure TRuleDocsProviderTests.StateCarriesProjectOptions;
var
  mState: TFindingRuleState;
begin
  mState := DocsOf.State('line-length', SettingsWith('{"rules":{"line-length":{"severity":"hint","max":100}}}'));
  Assert.IsTrue(mState.ProjectOptions.Contains('100'), mState.ProjectOptions);
  Assert.AreEqual('', DocsOf.State('line-length', TServerSettings.Default).ProjectOptions);
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleDocsProviderTests);

end.
