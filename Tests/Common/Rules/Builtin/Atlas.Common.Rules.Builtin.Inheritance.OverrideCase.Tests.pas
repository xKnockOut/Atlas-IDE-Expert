unit Atlas.Common.Rules.Builtin.Inheritance.OverrideCase.Tests;

// Tests der Teilunit override-case-mismatch: override anders geschrieben oder weniger sichtbar als der Vorfahr.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceOverrideCaseTests = class
  public
    [Test]
    procedure CaseMismatchIsReported;
    [Test]
    procedure LowerVisibilityIsReported;
    [Test]
    procedure SameSpellingIsSilent;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Inheritance.OverrideCase,
  Atlas.Tests.RuleAssert;

procedure TInheritanceOverrideCaseTests.CaseMismatchIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOverrideCaseMismatchRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    procedure Lauf; virtual;'#10 +
    '  end;'#10'  TAbleitung = class(TBasis)'#10'  public'#10'    procedure lauf; override;'#10'  end;'#10 +
    'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'procedure TAbleitung.lauf;'#10 +
    'begin'#10'end;'#10'end.'#10, '{"rules": {"override-case-mismatch": "hint"}}', '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('override-case-mismatch', mFindings[0].RuleId);
end;

procedure TInheritanceOverrideCaseTests.LowerVisibilityIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOverrideCaseMismatchRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    procedure Lauf; virtual;'#10 +
    '  end;'#10'  TAbleitung = class(TBasis)'#10'  protected'#10'    procedure Lauf; override;'#10'  end;'#10 +
    'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'procedure TAbleitung.Lauf;'#10 +
    'begin'#10'end;'#10'end.'#10, '{"rules": {"override-case-mismatch": "hint"}}', '');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('override-case-mismatch', mFindings[0].RuleId);
end;

procedure TInheritanceOverrideCaseTests.SameSpellingIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOverrideCaseMismatchRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  public'#10'    procedure Lauf; virtual;'#10 +
    '  end;'#10'  TAbleitung = class(TBasis)'#10'  public'#10'    procedure Lauf; override;'#10'  end;'#10 +
    'implementation'#10'procedure TBasis.Lauf;'#10'begin'#10'end;'#10'procedure TAbleitung.Lauf;'#10 +
    'begin'#10'end;'#10'end.'#10, '{"rules": {"override-case-mismatch": "hint"}}', ''))));
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceOverrideCaseTests);

end.
