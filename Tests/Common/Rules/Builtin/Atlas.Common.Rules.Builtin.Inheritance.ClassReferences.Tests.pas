unit Atlas.Common.Rules.Builtin.Inheritance.ClassReferences.Tests;

// Tests der Teilunit class-reference-nonvirtual-constructor: Create über eine Klassenreferenz.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceClassReferencesTests = class
  public
    [Test]
    procedure ClassRefTargets;
    [Test]
    procedure NonvirtualConstructorIsReported;
    [Test]
    procedure VirtualConstructorIsSilent;
    [Test]
    procedure UnknownClassRefKeepsSuppression;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Inheritance.ClassReferences,
  Atlas.Tests.RuleAssert;

procedure TInheritanceClassReferencesTests.ClassRefTargets;
begin
  Assert.AreEqual('TPlugin',
    TClassReferenceNonvirtualConstructorRule.ClassRefTarget('TPluginKlasse = class of TPlugin'));
  Assert.AreEqual('', TClassReferenceNonvirtualConstructorRule.ClassRefTarget('TPlugin = class'));
end;

procedure TInheritanceClassReferencesTests.NonvirtualConstructorIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TClassReferenceNonvirtualConstructorRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TPlugin = class'#10'  public'#10'    constructor Create;'#10 +
    '  end;'#10'  TPluginKlasse = class of TPlugin;'#10'implementation'#10'constructor TPlugin.Create;'#10 +
    'begin'#10'end;'#10'function Neu(Klasse: TPluginKlasse): TPlugin;'#10'begin'#10 +
    '  Result := Klasse.Create;'#10'end;'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('class-reference-nonvirtual-constructor', mFindings[0].RuleId);
end;

procedure TInheritanceClassReferencesTests.VirtualConstructorIsSilent;
begin
  TRuleAssert.Silent(TClassReferenceNonvirtualConstructorRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TPlugin = class'#10'  public'#10 +
    '    constructor Create; virtual;'#10'  end;'#10'  TPluginKlasse = class of TPlugin;'#10 +
    'implementation'#10'constructor TPlugin.Create;'#10'begin'#10'end;'#10 +
    'function Neu(Klasse: TPluginKlasse): TPlugin;'#10'begin'#10'  Result := Klasse.Create;'#10'end;'#10 +
    'end.'#10);
end;

procedure TInheritanceClassReferencesTests.UnknownClassRefKeepsSuppression;
const
  cIgnore = ' // lsp-ignore: class-reference-nonvirtual-constructor';
var
  mFindings: TArray<TRuleFinding>;
begin
  // ExceptClass kennt der Index nicht (RTL fehlt): Die Regel kann die Zeile nicht entscheiden, ihr lsp-ignore ist
  // keine unused-suppression (PullDiagnostics, raise FErrorClass.Create).
  mFindings := TRuleAssert.Findings(TClassReferenceNonvirtualConstructorRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'procedure Wirf(AKlasse: ExceptClass);'#10'begin'#10 +
    '  raise AKlasse.Create(''x'');' + cIgnore + #10'end;'#10'end.'#10);
  Assert.AreEqual(0, Integer(Length(mFindings)));
  // Bekannte Klasse mit virtuellem Konstruktor: entschieden, das lsp-ignore wirkt nicht.
  mFindings := TRuleAssert.Findings(TClassReferenceNonvirtualConstructorRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TPlugin = class'#10'  public'#10 +
    '    constructor Create; virtual;'#10'  end;'#10'  TPluginKlasse = class of TPlugin;'#10 +
    'implementation'#10'constructor TPlugin.Create;'#10'begin'#10'end;'#10 +
    'function Neu(Klasse: TPluginKlasse): TPlugin;'#10'begin'#10'  Result := Klasse.Create;' + cIgnore + #10 +
    'end;'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('unused-suppression', mFindings[0].RuleId);
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceClassReferencesTests);

end.
