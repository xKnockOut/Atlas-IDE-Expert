unit Atlas.Common.Rules.Builtin.Inheritance.OverrideTargets.Tests;

// Tests der Teilunit override-target-missing: override ohne virtuelle Methode im Vorfahren, sealed-Vorfahr.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceOverrideTargetsTests = class
  public
    [Test]
    procedure MissingTargetIsReported;
    [Test]
    procedure SealedAncestorIsReported;
    [Test]
    procedure MatchingOverrideIsSilent;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Inheritance.OverrideTargets,
  Atlas.Tests.RuleAssert;

procedure TInheritanceOverrideTargetsTests.MissingTargetIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    procedure Lauf; virtual;'#10 +
    '  end;'#10'  TAbleitung = class(TBasis)'#10'  public'#10'    procedure Laufen; override;'#10'  end;'#10 +
    'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'procedure TAbleitung.Laufen;'#10 +
    'begin'#10'end;'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('override-target-missing', mFindings[0].RuleId);
end;

procedure TInheritanceOverrideTargetsTests.SealedAncestorIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOverrideTargetMissingRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class sealed'#10'  end;'#10 +
    '  TAbleitung = class(TBasis)'#10'  end;'#10'implementation'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('override-target-missing', mFindings[0].RuleId);
end;

procedure TInheritanceOverrideTargetsTests.MatchingOverrideIsSilent;
begin
  TRuleAssert.Silent(TOverrideTargetMissingRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    procedure Lauf; virtual;'#10 +
    '  end;'#10'  TAbleitung = class(TBasis)'#10'  public'#10'    procedure Lauf; override;'#10'  end;'#10 +
    'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'procedure TAbleitung.Lauf;'#10 +
    'begin'#10'end;'#10'end.'#10);
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceOverrideTargetsTests);

end.
