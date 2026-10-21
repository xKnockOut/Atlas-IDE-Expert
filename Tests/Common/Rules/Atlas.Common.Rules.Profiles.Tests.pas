unit Atlas.Common.Rules.Profiles.Tests;

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
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Profiles;

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

/// <summary>AList um AExtra ergänzt und sortiert wie ActiveRules.</summary>
function Merged(const AList: string; const AExtra: array of string): string;
var
  Ids: TArray<string>;
  Id: string;
begin
  Ids := AList.Split([',']);
  for Id in AExtra do
    Ids := Ids + [Id];
  TArray.Sort<string>(Ids);
  Result := string.Join(',', Ids);
end;

procedure TRuleProfilesTests.BuiltinProfilesActivateExpectedRules;
const
  Threads = 'thread-free-with-free-on-terminate,thread-use-after-free-on-terminate,thread-vcl-access';
  All = 'assert-side-effect,bidi-control,bool-compare,captured-loop-variable,char-to-pchar,' +
    'collection-modified-in-loop,' +
    'component-create-without-override,component-default-mismatch,component-fixed-pixels,' +
    'component-hardcoded-color,component-missing-free-notification,component-missing-inherited,' +
    'component-palette-icon,component-setter-without-invalidate,confusable-identifier,' +
    'constructor-on-instance,control-char,declared-not-implemented,deprecated-symbol,destroy-without-override,' +
    'dfm-circular-datasource,dfm-control-field-type-mismatch,dfm-duplicate-binding,' +
    'dfm-master-without-fields,dfm-property,dfm-required-field-without-control,duplicate-interface-guid,' +
    'empty-except,empty-statement,exception-freed,exception-not-raised,float-equality,for-high-to-low,forbidden-uses,' +
    'foreign-form-control-access,form-field-type-mismatch,form-field-without-object,' +
    'form-object-without-field,format-without-settings,generic-exception-raised,hides-virtual,' +
    'ifthen-side-effect,implemented-not-declared,implicit-package-import,int32-mul-overflow,interface-guid,' +
    'invisible-char,' +
    'lock-without-finally,loop-off-by-one,metric-cognitive-complexity,metric-cyclomatic-complexity,metric-method-length,' +
    'metric-nesting-depth,metric-parameter-count,operator-precedence,owned-field-free-unclear,owned-field-not-freed,' +
    'possibly-uninitialized,raise-in-finally,redundant-assigned-free,' +
    'result-not-set,' +
    'security-command-injection,security-insecure-http,security-insecure-random,security-sql-injection,' +
    'security-tls-verification-disabled,security-weak-crypto,self-assignment,setter-recursion,sizeof-pointer,' +
    'slash-command,synchronize-in-destructor,thread-free-with-free-on-terminate,thread-resume-suspend,' +
    'thread-use-after-free-on-terminate,thread-vcl-access,type-used-before-declaration,' +
    'unneeded-forward-declaration,unreachable-code,unresolved-identifier,' +
    'unused-assignment,unused-local,unused-parameter,virtual-instead-of-override,with-statement';
begin
  Assert.AreEqual(All, ActiveRules('standard'));
  // strict schaltet experimentelle Regeln ein (#146): security-path-traversal (#149), file-header und
  // hardcoded-string (#56), random-without-randomize (#153), die freiwillige Regel todo-comment (#68),
  // die Architekturregeln des Rollenkonzepts (ohne "prefixes" stumm, Code-Review A-12).
  Assert.AreEqual(Merged(All, ['architecture-contract-content', 'architecture-role-import',
    'catch-all-without-raise', 'file-header', 'hardcoded-string',
    'loop-invariant-call', 'missing-begin-update', 'random-without-randomize', 'redundant-begin-end',
    'redundant-parens', 'security-path-traversal', 'string-concat-in-loop', 'todo-comment']), ActiveRules('strict'));
  Assert.AreEqual('assert-side-effect,bidi-control,captured-loop-variable,char-to-pchar,' +
    'collection-modified-in-loop,' +
    'component-create-without-override,component-default-mismatch,component-missing-free-notification,' +
    'component-missing-inherited,constructor-on-instance,control-char,declared-not-implemented,' +
    'destroy-without-override,dfm-circular-datasource,dfm-control-field-type-mismatch,' +
    'dfm-duplicate-binding,dfm-master-without-fields,dfm-required-field-without-control,' +
    'duplicate-interface-guid,empty-statement,exception-freed,exception-not-raised,float-equality,for-high-to-low,' +
    'form-field-type-mismatch,form-field-without-object,form-object-without-field,hides-virtual,' +
    'ifthen-side-effect,implemented-not-declared,int32-mul-overflow,interface-guid,lock-without-finally,loop-off-by-one,' +
    'operator-precedence,owned-field-free-unclear,owned-field-not-freed,' +
    'possibly-uninitialized,raise-in-finally,result-not-set,security-command-injection,' +
    'security-sql-injection,security-tls-verification-disabled,self-assignment,setter-recursion,sizeof-pointer,' +
    'synchronize-in-destructor,thread-free-with-free-on-terminate,thread-use-after-free-on-terminate,' +
    'thread-vcl-access,type-used-before-declaration,unreachable-code,unresolved-identifier,' +
    'virtual-instead-of-override',
    ActiveRules('fast'));
  Assert.AreEqual('bidi-control,confusable-identifier,invisible-char,security-command-injection,security-insecure-http,' +
    'security-insecure-random,security-sql-injection,security-tls-verification-disabled,' +
    'security-weak-crypto',
    ActiveRules('security'));
  Assert.AreEqual('bool-compare,component-fixed-pixels,component-hardcoded-color,component-palette-icon,' +
    'component-setter-without-invalidate,deprecated-symbol,dfm-property,empty-except,forbidden-uses,' +
    'foreign-form-control-access,format-without-settings,generic-exception-raised,implicit-package-import,' +
    'metric-cognitive-complexity,metric-cyclomatic-complexity,metric-method-length,metric-nesting-depth,' +
    'metric-parameter-count,' +
    'redundant-assigned-free,slash-command,thread-resume-suspend,unneeded-forward-declaration,' +
    'unused-assignment,unused-local,' +
    'unused-parameter,with-statement',
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
