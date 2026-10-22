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
  All = 'abstract-class-instantiated,anonymous-capture-invalid,anonymous-thread-not-started,assert-side-effect,assign-to-property-member,attribute-usage-invalid,bidi-control,blocking-call-in-main-thread,bool-compare,boolean-assign-if,captured-loop-variable,case-insensitive-compare,case-missing-enum-value,char-to-pchar,' +
    'collection-modified-in-loop,commented-out-code,comparison-as-statement,' +
    'component-create-without-override,component-default-mismatch,component-fixed-pixels,' +
    'component-hardcoded-color,component-missing-free-notification,component-missing-inherited,' +
    'component-palette-icon,component-setter-without-invalidate,conditional-directive-unbalanced,confusable-identifier,' +
    'constructor-on-instance,control-char,create-without-assignment,createprocess-readonly-commandline,dataset-edit-without-post,dataset-loop-without-next,declared-not-implemented,delimited-text-without-strict,deprecated-symbol,deref-before-nil-check,destroy-called-directly,destroy-without-override,' +
    'dfm-circular-datasource,dfm-control-field-type-mismatch,dfm-duplicate-binding,' +
    'dfm-master-without-fields,dfm-property,dfm-required-field-without-control,dictionary-get-without-check,dunitx-test-without-assert,duplicate-case-label,duplicate-condition,duplicate-declaration,duplicate-interface-guid,' +
    'empty-except,empty-statement,event-call-without-assigned,except-handler-order,exception-freed,exception-in-destructor,exception-not-raised,field-after-method,field-free-without-nil,field-not-freed,float-equality,for-high-to-low,forbidden-uses,' +
    'foreign-form-control-access,form-access-before-create,form-field-type-mismatch,form-field-without-object,' +
    'form-object-without-field,format-without-settings,generic-declaration-invalid,generic-exception-raised,hides-virtual,' +
    'ifthen-side-effect,implemented-not-declared,implicit-package-import,int32-mul-overflow,interface-guid,interface-not-implemented,' +
    'invisible-char,' +
    'lock-without-finally,loop-off-by-one,managed-type-raw-memory,message-handler-without-inherited,metric-class-size,metric-cognitive-complexity,metric-cyclomatic-complexity,' +
    'metric-method-length,metric-nesting-depth,metric-parameter-count,metric-unit-length,metric-uses-count,missing-inherited,null-compare,operator-declaration-invalid,operator-precedence,ota-notifier-not-removed,out-param-read,overload-directive-missing,override-target-missing,owned-field-free-unclear,owned-item-freed,pair-without-finally,pchar-of-temporary,' +
    'possibly-uninitialized,processmessages-in-loop,property-accessor-invalid,queue-nil-in-package,raise-in-finally,readonly-property-assigned,redundant-assigned-free,reraise-exception-object,' +
    'result-not-set,' +
    'security-command-injection,security-insecure-http,security-insecure-random,security-sql-injection,' +
    'security-tls-verification-disabled,security-weak-crypto,self-as-interface-in-constructor,self-assignment,setter-recursion,shadowed-name,signature-mismatch,sizeof-pointer,' +
    'slash-command,sql-write-without-where,string-index-base,stringlist-unsorted,synchronize-in-destructor,task-exception-unobserved,thread-free-with-free-on-terminate,thread-loop-without-terminated,thread-resume-suspend,' +
    'thread-use-after-free-on-terminate,thread-vcl-access,threadvar-managed,transaction-without-rollback,type-restriction-violated,type-used-before-declaration,' +
    'unchecked-conversion,unchecked-enum-cast,unneeded-forward-declaration,unreachable-code,unresolved-attribute,unresolved-identifier,' +
    'unused-assignment,unused-local,unused-parameter,use-after-free,uses-unit-not-found,virtual-instead-of-override,with-statement,' +
    'writeln-in-gui-app';
begin
  Assert.AreEqual(All, ActiveRules('standard'));
  // strict schaltet experimentelle Regeln ein (#146): security-path-traversal (#149), file-header und
  // hardcoded-string (#56), random-without-randomize (#153), die freiwillige Regel todo-comment (#68),
  // die Architekturregeln des Rollenkonzepts (ohne "prefixes" stumm, Code-Review A-12).
  Assert.AreEqual(Merged(All, ['architecture-contract-content', 'architecture-role-import',
    'catch-all-without-raise', 'file-header', 'global-variable', 'hardcoded-string',
    'line-length', 'loop-invariant-call', 'magic-number', 'missing-begin-update', 'public-field', 'random-without-randomize', 'redundant-begin-end',
    'redundant-parens', 'security-path-traversal', 'string-concat-in-loop', 'todo-comment']), ActiveRules('strict'));
  Assert.AreEqual('abstract-class-instantiated,anonymous-capture-invalid,anonymous-thread-not-started,assert-side-effect,assign-to-property-member,attribute-usage-invalid,bidi-control,captured-loop-variable,case-missing-enum-value,char-to-pchar,' +
    'collection-modified-in-loop,comparison-as-statement,' +
    'component-create-without-override,component-default-mismatch,component-missing-free-notification,' +
    'component-missing-inherited,conditional-directive-unbalanced,constructor-on-instance,control-char,create-without-assignment,createprocess-readonly-commandline,dataset-edit-without-post,dataset-loop-without-next,declared-not-implemented,delimited-text-without-strict,' +
    'deref-before-nil-check,destroy-called-directly,destroy-without-override,dfm-circular-datasource,dfm-control-field-type-mismatch,' +
    'dfm-duplicate-binding,dfm-master-without-fields,dfm-required-field-without-control,dictionary-get-without-check,' +
    'duplicate-case-label,duplicate-condition,duplicate-declaration,duplicate-interface-guid,empty-statement,event-call-without-assigned,except-handler-order,exception-freed,exception-in-destructor,exception-not-raised,field-after-method,field-free-without-nil,field-not-freed,float-equality,for-high-to-low,' +
    'form-access-before-create,form-field-type-mismatch,form-field-without-object,form-object-without-field,generic-declaration-invalid,hides-virtual,' +
    'ifthen-side-effect,implemented-not-declared,int32-mul-overflow,interface-guid,interface-not-implemented,lock-without-finally,loop-off-by-one,managed-type-raw-memory,message-handler-without-inherited,' +
    'missing-inherited,operator-declaration-invalid,operator-precedence,ota-notifier-not-removed,out-param-read,overload-directive-missing,override-target-missing,owned-field-free-unclear,owned-item-freed,pair-without-finally,pchar-of-temporary,' +
    'possibly-uninitialized,property-accessor-invalid,queue-nil-in-package,raise-in-finally,readonly-property-assigned,result-not-set,security-command-injection,' +
    'security-sql-injection,security-tls-verification-disabled,self-as-interface-in-constructor,self-assignment,setter-recursion,signature-mismatch,sizeof-pointer,' +
    'sql-write-without-where,string-index-base,stringlist-unsorted,synchronize-in-destructor,thread-free-with-free-on-terminate,thread-loop-without-terminated,' +
    'thread-use-after-free-on-terminate,' +
    'thread-vcl-access,threadvar-managed,transaction-without-rollback,type-restriction-violated,type-used-before-declaration,unchecked-conversion,unchecked-enum-cast,unreachable-code,unresolved-attribute,unresolved-identifier,use-after-free,uses-unit-not-found,' +
    'virtual-instead-of-override,writeln-in-gui-app',
    ActiveRules('fast'));
  Assert.AreEqual('bidi-control,confusable-identifier,invisible-char,security-command-injection,security-insecure-http,' +
    'security-insecure-random,security-sql-injection,security-tls-verification-disabled,' +
    'security-weak-crypto',
    ActiveRules('security'));
  Assert.AreEqual('blocking-call-in-main-thread,bool-compare,boolean-assign-if,case-insensitive-compare,commented-out-code,component-fixed-pixels,component-hardcoded-color,component-palette-icon,' +
    'component-setter-without-invalidate,deprecated-symbol,dfm-property,dunitx-test-without-assert,empty-except,forbidden-uses,' +
    'foreign-form-control-access,format-without-settings,generic-exception-raised,implicit-package-import,' +
    'metric-class-size,metric-cognitive-complexity,metric-cyclomatic-complexity,metric-method-length,' +
    'metric-nesting-depth,metric-parameter-count,metric-unit-length,metric-uses-count,' +
    'null-compare,processmessages-in-loop,redundant-assigned-free,reraise-exception-object,shadowed-name,slash-command,task-exception-unobserved,thread-resume-suspend,unneeded-forward-declaration,' +
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
