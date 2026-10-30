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
  All = 'abstract-class-instantiated,abstract-declaration-invalid,anonymous-capture-invalid,anonymous-thread-not-started,argument-count-mismatch,asm-invalid,assert-side-effect,assign-to-property-member,attribute-usage-invalid,bidi-control,blocking-call-in-main-thread,bool-compare,boolean-assign-if,calling-convention-required,captured-loop-variable,case-insensitive-compare,case-missing-enum-value,case-selector-not-ordinal,char-to-pchar,' +
  All = 'abstract-class-instantiated,abstract-declaration-invalid,anonymous-capture-invalid,anonymous-thread-not-started,argument-count-mismatch,assert-side-effect,assign-to-property-member,attribute-usage-invalid,automation-invalid,bidi-control,blocking-call-in-main-thread,bool-compare,boolean-assign-if,calling-convention-required,captured-loop-variable,case-insensitive-compare,case-missing-enum-value,case-selector-not-ordinal,char-to-pchar,' +
    'class-reference-nonvirtual-constructor,collection-modified-in-loop,commented-out-code,comparison-always-constant,comparison-as-statement,' +
    'compiler-directive-invalid,compiler-hints,compiler-warnings-disabled,component-create-without-override,component-default-mismatch,component-fixed-pixels,' +
    'component-hardcoded-color,component-interface-dangling,component-missing-free-notification,component-missing-inherited,' +
    'component-palette-icon,component-setter-without-invalidate,condition-not-boolean,conditional-directive-unbalanced,conditional-expression-version,confusable-identifier,constant-condition,constant-expression-error,' +
    'constant-initializer-mismatch,constructor-on-instance,control-char,create-without-assignment,createprocess-readonly-commandline,dataset-edit-without-post,dataset-loop-without-next,debug-display-placeholder,declaration-invalid,declared-not-implemented,default-parameter-invalid,default-property-invalid,delimited-text-without-strict,deprecated-symbol,deref-before-nil-check,destroy-called-directly,destroy-without-override,destructor-not-nil-safe,' +
    'dfm-circular-datasource,dfm-control-field-type-mismatch,dfm-duplicate-binding,' +
    'dfm-master-without-fields,dfm-property,dfm-required-field-without-control,dictionary-get-without-check,directive-typo,dispinterface-invalid,dll-export-unsafe,dunitx-test-without-assert,duplicate-assignment,duplicate-case-label,duplicate-condition,duplicate-declaration,duplicate-interface-guid,dynamic-array-misuse,' +
    'empty-except,empty-finally,empty-routine,empty-statement,equals-without-gethashcode,event-call-without-assigned,except-handler-order,exception-freed,exception-in-destructor,exception-not-raised,exports-invalid,field-after-method,field-free-without-nil,field-not-freed,file-encoding-unsupported,filename-compare-case,first-char-address,float-equality,for-high-to-low,for-in-not-enumerable,for-variable-after-loop,for-variable-misuse,forbidden-uses,' +
    'foreign-form-control-access,form-access-before-create,form-autocreate-and-manual,form-field-type-mismatch,form-field-without-object,' +
    'form-object-without-field,form-resource-missing,format-args,format-without-settings,generic-constraint-violated,generic-declaration-invalid,generic-exception-raised,generic-inference-failed,getter-side-effect,global-formatsettings-modified,guid-syntax-invalid,handle-leak,hardcoded-path,hides-virtual,' +
    'hresult-integer-mix,ifthen-side-effect,implemented-not-declared,implements-clause-invalid,implicit-package-import,inaccessible-member,infinite-loop,inherited-abstract-call,inherited-constructor-after-try,inherited-form-handler-without-inherited,inherited-order,inherited-without-ancestor,inherited-wrong-method,initialization-not-finalized,inline-not-expanded,int32-mul-overflow,integer-division-to-float,interface-declaration-invalid,interface-guid,interface-not-implemented,' +
    'invalid-var-argument,invisible-char,jump-outside-allowed-scope,label-misuse,' +
    'load-without-encoding,local-routine-as-callback,lock-without-finally,loop-condition-unchanged,loop-off-by-one,loop-runs-at-most-once,managed-type-raw-memory,member-hides-ancestor,message-handler-without-inherited,message-method-invalid,metric-boolean-operands,metric-class-size,metric-cognitive-complexity,metric-cyclomatic-complexity,' +
    'metric-exit-points,metric-inheritance-depth,metric-local-count,metric-method-length,metric-nesting-depth,metric-parameter-count,metric-unit-length,metric-uses-count,missing-begin-end,missing-inherited,noreturn-returns,now-for-elapsed-time,null-compare,operator-declaration-invalid,operator-precedence,ota-notifier-not-removed,out-param-read,overload-directive-missing,override-only-inherited,override-target-missing,owned-field-free-unclear,owned-item-freed,pair-without-finally,parallel-for-shared-write,path-concat-without-delimiter,pchar-of-temporary,pos-arguments-swapped,' +
    'possibly-uninitialized,processmessages-in-loop,property-accessor-invalid,property-redeclaration-invalid,published-type-invalid,queue-nil-in-package,raise-in-finally,raw-memory-leak,readonly-property-assigned,redundant-assigned-free,redundant-cast,redundant-jump,registry-hklm-write,reraise-exception-object,reraise-outside-handler,' +
    'result-not-set,' +
    'security-command-injection,security-insecure-http,security-insecure-random,security-sql-injection,' +
    'security-tls-verification-disabled,security-weak-crypto,self-as-interface-in-constructor,self-assignment,self-free-in-event-handler,setlength-in-loop,setter-recursion,shadowed-name,signature-mismatch,signed-unsigned-mix,sizeof-pointer,' +
    'slash-command,sql-write-without-where,string-conversion,string-index-base,string-length-limit,stringlist-objects-leak,stringlist-unsorted,suspicious-string-pointer-cast,synchronize-in-destructor,task-exception-unobserved,text-after-final-end,thread-free-with-free-on-terminate,thread-loop-without-terminated,thread-resume-suspend,' +
    'thread-unsafe-increment,thread-use-after-free-on-terminate,thread-vcl-access,threadvar-managed,transaction-without-rollback,trivial-accessor,type-restriction-violated,type-too-large,type-used-before-declaration,typed-constant-modified,typeinfo-invalid,' +
    'ui-call-in-console-or-service,unchecked-conversion,unchecked-enum-cast,unconditional-recursion,unit-name-conflict,unit-name-mismatch,unneeded-forward-declaration,unreachable-code,unrelated-class-cast,unresolved-attribute,unresolved-identifier,unresolved-type,unsafe-code,unsatisfied-forward,' +
    'untyped-pointer-refcount,unused-assignment,unused-declaration,unused-local,unused-parameter,unused-private-member,unused-public-member,unused-unit,unused-uses,use-after-free,uses-cycle,uses-unit-not-found,variant-record-managed-field,virtual-instead-of-override,with-statement,' +
    'write-only-property,writeln-in-gui-app,xmldoc-mismatch';
begin
  Assert.AreEqual(All, ActiveRules('standard'));
  // strict schaltet experimentelle Regeln ein (#146): security-path-traversal (#149), file-header und
  // hardcoded-string (#56), random-without-randomize (#153), die freiwillige Regel todo-comment (#68),
  // die Architekturregeln des Rollenkonzepts (ohne "prefixes" stumm, Code-Review A-12), prefer-case (#646),
  // method-without-self (#686).
  Assert.AreEqual(Merged(All, ['architecture-contract-content', 'architecture-role-import',
    'catch-all-without-raise', 'default-parameter', 'file-header', 'forbidden-symbol', 'global-variable',
    'hardcoded-string',
    'implicit-variants-unit', 'legacy-stack-queue', 'legacy-tlist', 'line-length', 'loop-invariant-call', 'magic-number',
    'managed-param-without-const', 'method-without-self', 'missing-begin-update', 'money-as-float', 'naming-prefix',
    'narrowing-assignment',
    'override-case-mismatch', 'prefer-case', 'public-field', 'random-without-randomize', 'redundant-begin-end',
    'redundant-parens', 'security-path-traversal', 'sql-select-star', 'string-concat-in-loop', 'string-if-chain',
    'todo-comment']), ActiveRules('strict'));
  Assert.AreEqual('abstract-class-instantiated,abstract-declaration-invalid,anonymous-capture-invalid,anonymous-thread-not-started,argument-count-mismatch,asm-invalid,assert-side-effect,assign-to-property-member,attribute-usage-invalid,bidi-control,calling-convention-required,captured-loop-variable,case-missing-enum-value,case-selector-not-ordinal,char-to-pchar,' +
  Assert.AreEqual('abstract-class-instantiated,abstract-declaration-invalid,anonymous-capture-invalid,anonymous-thread-not-started,argument-count-mismatch,assert-side-effect,assign-to-property-member,attribute-usage-invalid,automation-invalid,bidi-control,calling-convention-required,captured-loop-variable,case-missing-enum-value,case-selector-not-ordinal,char-to-pchar,' +
    'class-reference-nonvirtual-constructor,collection-modified-in-loop,comparison-always-constant,comparison-as-statement,' +
    'compiler-directive-invalid,component-create-without-override,component-default-mismatch,component-interface-dangling,component-missing-free-notification,' +
    'component-missing-inherited,condition-not-boolean,conditional-directive-unbalanced,conditional-expression-version,constant-condition,constant-expression-error,constant-initializer-mismatch,constructor-on-instance,control-char,create-without-assignment,createprocess-readonly-commandline,dataset-edit-without-post,dataset-loop-without-next,debug-display-placeholder,declaration-invalid,declared-not-implemented,default-parameter-invalid,default-property-invalid,delimited-text-without-strict,' +
    'deref-before-nil-check,destroy-called-directly,destroy-without-override,destructor-not-nil-safe,dfm-circular-datasource,dfm-control-field-type-mismatch,' +
    'dfm-duplicate-binding,dfm-master-without-fields,dfm-required-field-without-control,dictionary-get-without-check,directive-typo,dispinterface-invalid,' +
    'dll-export-unsafe,duplicate-assignment,duplicate-case-label,duplicate-condition,duplicate-declaration,duplicate-interface-guid,dynamic-array-misuse,empty-statement,equals-without-gethashcode,event-call-without-assigned,except-handler-order,exception-freed,exception-in-destructor,exception-not-raised,exports-invalid,field-after-method,field-free-without-nil,field-not-freed,file-encoding-unsupported,filename-compare-case,first-char-address,float-equality,for-high-to-low,for-in-not-enumerable,for-variable-after-loop,for-variable-misuse,' +
    'form-access-before-create,form-autocreate-and-manual,form-field-type-mismatch,form-field-without-object,form-object-without-field,form-resource-missing,format-args,generic-constraint-violated,generic-declaration-invalid,generic-inference-failed,global-formatsettings-modified,guid-syntax-invalid,handle-leak,hides-virtual,' +
    'hresult-integer-mix,ifthen-side-effect,implemented-not-declared,implements-clause-invalid,inaccessible-member,infinite-loop,inherited-abstract-call,inherited-constructor-after-try,inherited-form-handler-without-inherited,inherited-order,inherited-wrong-method,initialization-not-finalized,int32-mul-overflow,integer-division-to-float,interface-declaration-invalid,interface-guid,interface-not-implemented,invalid-var-argument,jump-outside-allowed-scope,label-misuse,load-without-encoding,local-routine-as-callback,lock-without-finally,loop-condition-unchanged,loop-off-by-one,loop-runs-at-most-once,managed-type-raw-memory,member-hides-ancestor,message-handler-without-inherited,message-method-invalid,' +
    'missing-inherited,noreturn-returns,operator-declaration-invalid,operator-precedence,ota-notifier-not-removed,out-param-read,overload-directive-missing,override-target-missing,owned-field-free-unclear,owned-item-freed,pair-without-finally,parallel-for-shared-write,path-concat-without-delimiter,pchar-of-temporary,pos-arguments-swapped,' +
    'possibly-uninitialized,property-accessor-invalid,property-redeclaration-invalid,published-type-invalid,queue-nil-in-package,raise-in-finally,raw-memory-leak,readonly-property-assigned,registry-hklm-write,reraise-outside-handler,result-not-set,security-command-injection,' +
    'security-sql-injection,security-tls-verification-disabled,self-as-interface-in-constructor,self-assignment,self-free-in-event-handler,setter-recursion,signature-mismatch,signed-unsigned-mix,sizeof-pointer,' +
    'sql-write-without-where,string-conversion,string-index-base,string-length-limit,stringlist-objects-leak,stringlist-unsorted,suspicious-string-pointer-cast,synchronize-in-destructor,thread-free-with-free-on-terminate,thread-loop-without-terminated,' +
    'thread-unsafe-increment,thread-use-after-free-on-terminate,' +
    'thread-vcl-access,threadvar-managed,transaction-without-rollback,type-restriction-violated,type-too-large,type-used-before-declaration,typed-constant-modified,typeinfo-invalid,ui-call-in-console-or-service,unchecked-conversion,unchecked-enum-cast,unconditional-recursion,unit-name-conflict,unit-name-mismatch,unreachable-code,unrelated-class-cast,unresolved-attribute,unresolved-identifier,unresolved-type,unsatisfied-forward,untyped-pointer-refcount,use-after-free,uses-unit-not-found,' +
    'variant-record-managed-field,virtual-instead-of-override,writeln-in-gui-app',
    ActiveRules('fast'));
  Assert.AreEqual('bidi-control,confusable-identifier,invisible-char,security-command-injection,security-insecure-http,' +
    'security-insecure-random,security-sql-injection,security-tls-verification-disabled,' +
    'security-weak-crypto',
    ActiveRules('security'));
  Assert.AreEqual('blocking-call-in-main-thread,bool-compare,boolean-assign-if,case-insensitive-compare,commented-out-code,compiler-hints,compiler-warnings-disabled,component-fixed-pixels,' +
    'component-hardcoded-color,component-palette-icon,component-setter-without-invalidate,deprecated-symbol,dfm-property,dunitx-test-without-assert,empty-except,empty-finally,empty-routine,' +
    'forbidden-uses,foreign-form-control-access,format-without-settings,generic-exception-raised,getter-side-effect,hardcoded-path,implicit-package-import,inherited-without-ancestor,inline-not-expanded,' +
    'metric-boolean-operands,metric-class-size,metric-cognitive-complexity,metric-cyclomatic-complexity,metric-exit-points,metric-inheritance-depth,metric-local-count,metric-method-length,' +
    'metric-nesting-depth,metric-parameter-count,metric-unit-length,metric-uses-count,missing-begin-end,now-for-elapsed-time,null-compare,override-only-inherited,processmessages-in-loop,redundant-assigned-free,redundant-cast,redundant-jump,' +
    'reraise-exception-object,setlength-in-loop,shadowed-name,slash-command,task-exception-unobserved,text-after-final-end,thread-resume-suspend,trivial-accessor,unneeded-forward-declaration,unsafe-code,' +
    'unused-assignment,unused-declaration,unused-local,' +
    'unused-parameter,unused-private-member,unused-public-member,unused-unit,unused-uses,uses-cycle,with-statement,write-only-property,xmldoc-mismatch',
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
