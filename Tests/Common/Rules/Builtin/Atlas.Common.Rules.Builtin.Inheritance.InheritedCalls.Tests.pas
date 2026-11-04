unit Atlas.Common.Rules.Builtin.Inheritance.InheritedCalls.Tests;

// Tests der Teilunit override-only-inherited und inherited-without-ancestor.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceInheritedCallsTests = class
  public
    [Test]
    procedure OnlyInheritedIsReported;
    [Test]
    procedure OwnCodeIsSilent;
    [Test]
    procedure InheritedWithoutAncestorIsReported;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Inheritance.InheritedCalls,
  Atlas.Tests.RuleAssert;

procedure TInheritanceInheritedCallsTests.OnlyInheritedIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOverrideOnlyInheritedRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    procedure Lauf; virtual;'#10 +
    '  end;'#10'  TAbleitung = class(TBasis)'#10'  public'#10'    procedure Lauf; override;'#10'  end;'#10 +
    'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'procedure TAbleitung.Lauf;'#10 +
    'begin'#10'  inherited;'#10'end;'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('override-only-inherited', mFindings[0].RuleId);
end;

procedure TInheritanceInheritedCallsTests.OwnCodeIsSilent;
begin
  TRuleAssert.Silent(TOverrideOnlyInheritedRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    procedure Lauf; virtual;'#10 +
    '  end;'#10'  TAbleitung = class(TBasis)'#10'  public'#10'    procedure Lauf; override;'#10'  end;'#10 +
    'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'procedure TAbleitung.Lauf;'#10 +
    'begin'#10'  inherited;'#10'  Writeln;'#10'end;'#10'end.'#10);
end;

procedure TInheritanceInheritedCallsTests.InheritedWithoutAncestorIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TInheritedWithoutAncestorRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    procedure Lauf; virtual;'#10 +
    '  end;'#10'  TAbleitung = class(TBasis)'#10'  public'#10'    procedure Neu;'#10'  end;'#10 +
    'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'procedure TAbleitung.Neu;'#10'begin'#10 +
    '  inherited;'#10'end;'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('inherited-without-ancestor', mFindings[0].RuleId);
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceInheritedCallsTests);

end.
