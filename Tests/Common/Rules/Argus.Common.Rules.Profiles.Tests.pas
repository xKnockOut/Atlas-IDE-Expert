unit Argus.Common.Rules.Profiles.Tests;

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
    procedure StrictEnablesExperimentalAndLowConfidence;
    [Test]
    procedure ExplicitMinConfidenceWinsOverProfile;
    [Test]
    procedure BuiltinProfilesActivateExpectedRules;
    [Test]
    procedure TestProfileAppliesToTestUnits;
    [Test]
    procedure OwnProfileExtendsBuiltin;
    [Test]
    procedure ConfigRulesWinOverProfile;
    [Test]
    procedure OverrideMatchesPathOnly;
    [Test]
    procedure OverrideDowngradesWarningInTests;
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
    procedure DetectsTestProjects;
    [Test]
    procedure CatalogKnowsCategories;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Argus.Common.Configuration.Contract,
  Argus.Common.Configuration.Parser,
  Argus.Common.Pascal.Lexer,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Engine,
  Argus.Common.Rules.Builtin,
  Argus.Common.Rules.Profiles;

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

procedure TRuleProfilesTests.StrictEnablesExperimentalAndLowConfidence;
var
  Streng: TServerSettings;
  Enabled: Boolean;
begin
  Streng := Settings('{"profile":"strict"}');
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(SeverityOf(Streng, 'code-smell', TRuleSeverity.Hint)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(TRuleProfiles.MinConfidence(Streng, Streng.Profile)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(TRuleProfiles.MinConfidence(Streng, 'fast')));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(TRuleProfiles.MinConfidence(
    Settings('{"profile":"ci","profiles":{"ci":{"extends":"strict"}}}'), 'ci')));
  TRuleProfiles.Severity(Streng, Streng.Profile, TRuleDescriptor.Create('probe', TRuleSeverity.Hint, 'Probe', True),
    'bug', '', Enabled);
  Assert.IsTrue(Enabled);
  TRuleProfiles.Severity(TServerSettings.Default, '', TRuleDescriptor.Create('probe', TRuleSeverity.Hint, 'Probe', True),
    'bug', '', Enabled);
  Assert.IsFalse(Enabled);
end;

procedure TRuleProfilesTests.ExplicitMinConfidenceWinsOverProfile;
var
  Given: TServerSettings;
begin
  Given := Settings('{"profile":"strict","minConfidence":"high"}');
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(TRuleProfiles.MinConfidence(Given, Given.Profile)));
end;

/// <summary>Aktive eingebaute Regeln unter AProfile, sortiert und mit Komma getrennt.</summary>
function ActiveRules(const AProfile: string): string;
var
  Rule: IRule;
  Config: TServerSettings;
  Enabled: Boolean;
  Ids: TArray<string>;
begin
  Config := TServerSettings.Default;
  Config.Profile := AProfile;
  Ids := nil;
  for Rule in BuiltinRules do
    if (TRuleEngine.EffectiveSeverity(Rule.Descriptor, Config, '', Enabled) <> TRuleSeverity.Off) and
      (Enabled or not Rule.Descriptor.Experimental) then
      Ids := Ids + [Rule.Descriptor.Id];
  TArray.Sort<string>(Ids);
  Result := string.Join(',', Ids);
end;

procedure TRuleProfilesTests.BuiltinProfilesActivateExpectedRules;
const
  Threads = 'thread-free-with-free-on-terminate,thread-use-after-free-on-terminate,thread-vcl-access';
  All = 'bidi-control,component-create-without-override,confusable-identifier,control-char,' +
    'declared-not-implemented,destroy-without-override,forbidden-uses,hides-virtual,implemented-not-declared,' +
    'invisible-char,lock-without-finally,possibly-uninitialized,result-not-set,synchronize-in-destructor,' +
    'thread-free-with-free-on-terminate,thread-resume-suspend,thread-use-after-free-on-terminate,' +
    'thread-vcl-access,unused-assignment,unused-local,unused-parameter,' +
    'virtual-instead-of-override';
begin
  Assert.AreEqual(All, ActiveRules('standard'));
  Assert.AreEqual(All, ActiveRules('strict'));
  Assert.AreEqual('bidi-control,component-create-without-override,control-char,declared-not-implemented,' +
    'destroy-without-override,hides-virtual,implemented-not-declared,lock-without-finally,possibly-uninitialized,' +
    'result-not-set,synchronize-in-destructor,' + Threads + ',virtual-instead-of-override',
    ActiveRules('fast'));
  Assert.AreEqual('bidi-control,confusable-identifier,invisible-char', ActiveRules('security'));
  Assert.AreEqual('forbidden-uses,thread-resume-suspend,unused-assignment,unused-local,unused-parameter',
    ActiveRules('style'));
end;

procedure TRuleProfilesTests.TestProfileAppliesToTestUnits;
var
  Config: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Config := Settings('{"testProfile":"lasch","profiles":{"lasch":{"categories":["bug"]}}}');
  Assert.AreEqual('lasch', Config.TestProfile);
  TConfigurationParser.Parse('{"testProfile":"fehlt"}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
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

procedure TRuleProfilesTests.OverrideDowngradesWarningInTests;
var
  Paths: TServerSettings;
begin
  Paths := Settings('{"overrides":[{"files":["Tests/**"],"rules":{"*":"hint"}}]}');
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(SeverityOf(Paths, 'bug', TRuleSeverity.Warning, 'Tests/Sub/A.Tests.pas')));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(SeverityOf(Paths, 'bug', TRuleSeverity.Warning, 'Source/A.pas')));
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

procedure TRuleProfilesTests.DetectsTestProjects;
begin
  // DUnitX-Konsolenprojekt
  Assert.IsTrue(TRuleProfiles.IsTestUnit(TPascalLexer.Tokenize(
    'program AppTests;'#10'{$APPTYPE CONSOLE}'#10'uses'#10'  System.SysUtils,'#10'  DUnitX.Loggers.Console,'#10 +
    '  DUnitX.TestFramework,'#10'  App.Tests in ''App.Tests.pas'';'#10'begin'#10'end.')));
  // DUnit-GUI-Projekt
  Assert.IsTrue(TRuleProfiles.IsTestUnit(TPascalLexer.Tokenize(
    'program LegacyTests;'#10'uses'#10'  Forms,'#10'  TestFramework,'#10'  GUITestRunner;'#10'begin'#10 +
    '  GUITestRunner.RunRegisteredTests;'#10'end.')));
  // Normales Projekt
  Assert.IsFalse(TRuleProfiles.IsTestUnit(TPascalLexer.Tokenize(
    'program App;'#10'uses'#10'  Vcl.Forms,'#10'  Main in ''Main.pas'';'#10'begin'#10'end.')));
end;

procedure TRuleProfilesTests.CatalogKnowsCategories;
begin
  Assert.AreEqual('bug', TRuleProfiles.CategoryOf('syntax'));
  Assert.AreEqual('', TRuleProfiles.CategoryOf('gibt-es-nicht'));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleProfilesTests);

end.
