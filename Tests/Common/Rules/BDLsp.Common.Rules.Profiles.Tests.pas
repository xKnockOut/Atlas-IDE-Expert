unit BDLsp.Common.Rules.Profiles.Tests;

// Tests für Regelprofile, Pfadregeln und das Erkennen von Test-Units (#146).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleProfilesTests = class
  public
    [Test]
    procedure StandardKeepsDefault;
    [Test]
    procedure FastKeepsOnlyBugsAndVulnerabilities;
    [Test]
    procedure SecurityAndStyleFilterCategories;
    [Test]
    procedure StrictRaisesHintsAndEnablesExperimental;
    [Test]
    procedure OwnProfileExtendsBuiltin;
    [Test]
    procedure ConfigRulesWinOverProfile;
    [Test]
    procedure OverrideMatchesPathOnly;
    [Test]
    procedure OverrideWildcardHitsAllRules;
    [Test]
    procedure CyclicProfilesTerminate;
    [Test]
    procedure ParsesProfileForEditorAndCli;
    [Test]
    procedure ReportsUnknownProfile;
    [Test]
    procedure DetectsTestUnits;
    [Test]
    procedure CatalogKnowsCategories;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Configuration.Parser,
  BDLsp.Common.Pascal.Lexer,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Profiles;

function Settings(const AJson: string): TServerSettings;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Result := TConfigurationParser.Parse(AJson, Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'Konfiguration fehlerhaft');
end;

function SeverityOf(const ASettings: TServerSettings; const ACategory: string;
  ADefault: TRuleSeverity = TRuleSeverity.Warning; const APath: string = 'Source/Main.pas';
  AExperimental: Boolean = False): TRuleSeverity;
var
  Enabled: Boolean;
begin
  Result := TRuleProfiles.Severity(ASettings, ASettings.Profile,
    TRuleDescriptor.Create('probe', ADefault, 'Probe', AExperimental), ACategory, APath, Enabled);
end;

procedure TRuleProfilesTests.StandardKeepsDefault;
begin
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(SeverityOf(TServerSettings.Default, 'code-smell', TRuleSeverity.Hint)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(SeverityOf(Settings('{"profile":"standard"}'), 'code-smell', TRuleSeverity.Hint)));
end;

procedure TRuleProfilesTests.FastKeepsOnlyBugsAndVulnerabilities;
var
  Fast: TServerSettings;
begin
  Fast := Settings('{"profile":"fast"}');
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(SeverityOf(Fast, 'bug')));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(SeverityOf(Fast, 'vulnerability')));
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(SeverityOf(Fast, 'code-smell')));
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(SeverityOf(Fast, 'security-hotspot')));
  // Regeln ohne Katalogeintrag bleiben an.
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(SeverityOf(Fast, '')));
end;

procedure TRuleProfilesTests.SecurityAndStyleFilterCategories;
begin
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(SeverityOf(Settings('{"profile":"security"}'), 'security-hotspot')));
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(SeverityOf(Settings('{"profile":"security"}'), 'bug')));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(SeverityOf(Settings('{"profile":"style"}'), 'code-smell')));
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(SeverityOf(Settings('{"profile":"style"}'), 'vulnerability')));
end;

procedure TRuleProfilesTests.StrictRaisesHintsAndEnablesExperimental;
var
  Streng: TServerSettings;
  Enabled: Boolean;
begin
  Streng := Settings('{"profile":"strict"}');
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(SeverityOf(Streng, 'code-smell', TRuleSeverity.Hint)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(SeverityOf(Streng, 'bug', TRuleSeverity.Error)));
  TRuleProfiles.Severity(Streng, Streng.Profile, TRuleDescriptor.Create('probe', TRuleSeverity.Hint, 'Probe', True),
    'bug', '', Enabled);
  Assert.IsTrue(Enabled);
  TRuleProfiles.Severity(TServerSettings.Default, '', TRuleDescriptor.Create('probe', TRuleSeverity.Hint, 'Probe', True),
    'bug', '', Enabled);
  Assert.IsFalse(Enabled);
end;

procedure TRuleProfilesTests.OwnProfileExtendsBuiltin;
var
  Own: TServerSettings;
begin
  Own := Settings('{"profile":"team","profiles":{"team":{"extends":"fast","rules":{"probe":"error"}}}}');
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(SeverityOf(Own, 'bug')));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(SeverityOf(Own, 'code-smell')), 'Ausdrückliche Profilregel schlägt den Kategoriefilter');
  Own := Settings('{"profile":"nur-stil","profiles":{"nur-stil":{"categories":["code-smell"]}}}');
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(SeverityOf(Own, 'bug')));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(SeverityOf(Own, 'code-smell')));
end;

procedure TRuleProfilesTests.ConfigRulesWinOverProfile;
begin
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(SeverityOf(Settings('{"profile":"fast","rules":{"probe":"hint"}}'), 'code-smell')));
end;

procedure TRuleProfilesTests.OverrideMatchesPathOnly;
var
  Paths: TServerSettings;
begin
  Paths := Settings('{"overrides":[{"files":["Tests/**"],"rules":{"probe":"off"}}]}');
  Assert.AreEqual(Ord(TRuleSeverity.Off), Ord(SeverityOf(Paths, 'bug', TRuleSeverity.Warning, 'Tests/Unit1.Tests.pas')));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(SeverityOf(Paths, 'bug', TRuleSeverity.Warning, 'Source/Unit1.pas')));
end;

procedure TRuleProfilesTests.OverrideWildcardHitsAllRules;
var
  Paths: TServerSettings;
begin
  Paths := Settings('{"rules":{"probe":"error"},"overrides":[{"files":["Generated/*.pas"],"rules":{"*":"hint"}}]}');
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(SeverityOf(Paths, 'bug', TRuleSeverity.Warning, 'Generated/Api.pas')));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(SeverityOf(Paths, 'bug', TRuleSeverity.Warning, 'Source/Api.pas')));
end;

procedure TRuleProfilesTests.CyclicProfilesTerminate;
var
  Cycle: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Cycle := TConfigurationParser.Parse('{"profile":"a","profiles":{"a":{"extends":"b"},"b":{"extends":"a"}}}', Issues);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(SeverityOf(Cycle, 'bug')));
end;

procedure TRuleProfilesTests.ParsesProfileForEditorAndCli;
var
  Both: TServerSettings;
begin
  Both := Settings('{"profile":{"editor":"fast","cli":"strict"},"excludeTests":true}');
  Assert.AreEqual('fast', Both.Profile);
  Assert.AreEqual('strict', Both.CliProfile);
  Assert.IsTrue(Both.ExcludeTests);
end;

procedure TRuleProfilesTests.ReportsUnknownProfile;
var
  Issues: TArray<TConfigurationIssue>;
begin
  TConfigurationParser.Parse('{"profile":"gibtsnicht"}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, 'gibtsnicht');
  TConfigurationParser.Parse('{"profiles":{"x":{"extends":"fehlt"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  TConfigurationParser.Parse('{"overrides":[{"rules":{"a":"off"}}]}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'Pfadregel ohne files');
end;

procedure TRuleProfilesTests.DetectsTestUnits;
begin
  Assert.IsTrue(TRuleProfiles.IsTestUnit(TPascalLexer.Tokenize(
    'unit A.Tests;'#10'interface'#10'uses'#10'  DUnitX.TestFramework;'#10'implementation'#10'end.')));
  Assert.IsTrue(TRuleProfiles.IsTestUnit(TPascalLexer.Tokenize(
    'unit B;'#10'interface'#10'implementation'#10'uses TestFramework, SysUtils;'#10'end.')));
  Assert.IsFalse(TRuleProfiles.IsTestUnit(TPascalLexer.Tokenize(
    'unit C;'#10'interface'#10'uses System.SysUtils;'#10'implementation'#10'end.')));
end;

procedure TRuleProfilesTests.CatalogKnowsCategories;
begin
  Assert.AreEqual('bug', TRuleProfiles.CategoryOf('syntax'));
  Assert.AreEqual('', TRuleProfiles.CategoryOf('gibt-es-nicht'));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleProfilesTests);

end.
