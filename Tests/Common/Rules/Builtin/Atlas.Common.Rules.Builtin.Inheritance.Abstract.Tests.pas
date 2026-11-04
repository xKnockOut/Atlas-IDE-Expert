unit Atlas.Common.Rules.Builtin.Inheritance.Abstract.Tests;

// Tests der Teilunit abstract-class-instantiated und inherited-abstract-call.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceAbstractTests = class
  public
    [Test]
    procedure AbstractSignatures;
    [Test]
    procedure InstanceIsReported;
    [Test]
    procedure ConcreteClassIsSilent;
    [Test]
    procedure InheritedAbstractCallIsReported;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Inheritance.Abstract,
  Atlas.Tests.RuleAssert;

procedure TInheritanceAbstractTests.AbstractSignatures;
begin
  Assert.IsTrue(TInheritedAbstractCallRule.IsAbstractSignature('procedure A; virtual; abstract;'));
  Assert.IsFalse(TInheritedAbstractCallRule.IsAbstractSignature('procedure A(abstract: Boolean); virtual;'));
  Assert.IsFalse(TInheritedAbstractCallRule.IsAbstractSignature('procedure A; virtual;'));
end;

procedure TInheritanceAbstractTests.InstanceIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TAbstractClassInstantiatedRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10 +
    '    procedure Lauf; virtual; abstract;'#10'  end;'#10'implementation'#10'procedure Neu;'#10'begin'#10 +
    '  TBasis.Create.Free;'#10'end;'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('abstract-class-instantiated', mFindings[0].RuleId);
end;

procedure TInheritanceAbstractTests.ConcreteClassIsSilent;
begin
  TRuleAssert.Silent(TAbstractClassInstantiatedRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    procedure Lauf; virtual;'#10 +
    '  end;'#10'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'procedure Neu;'#10'begin'#10 +
    '  TBasis.Create.Free;'#10'end;'#10'end.'#10);
end;

procedure TInheritanceAbstractTests.InheritedAbstractCallIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TInheritedAbstractCallRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10 +
    '    procedure Lauf; virtual; abstract;'#10'  end;'#10'  TAbleitung = class(TBasis)'#10'  public'#10 +
    '    procedure Lauf; override;'#10'  end;'#10'implementation'#10'procedure TAbleitung.Lauf;'#10'begin'#10 +
    '  inherited Lauf;'#10'end;'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('inherited-abstract-call', mFindings[0].RuleId);
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceAbstractTests);

end.
