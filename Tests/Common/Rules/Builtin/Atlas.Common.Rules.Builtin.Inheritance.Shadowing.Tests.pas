unit Atlas.Common.Rules.Builtin.Inheritance.Shadowing.Tests;

// Tests der Teilunit shadowed-name: Parameter oder lokale Variable heißt wie ein Feld oder eine globale Variable.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInheritanceShadowingTests = class
  public
    [Test]
    procedure ParameterHidesField;
    [Test]
    procedure LocalHidesGlobal;
    [Test]
    procedure OtherNamesAreSilent;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Inheritance.Shadowing,
  Atlas.Tests.RuleAssert;

procedure TInheritanceShadowingTests.ParameterHidesField;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TShadowedNameRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TKunde = class'#10'  private'#10'    Anzahl: Integer;'#10 +
    '  public'#10'    procedure Setze(Anzahl: Integer);'#10'  end;'#10'implementation'#10 +
    'procedure TKunde.Setze(Anzahl: Integer);'#10'begin'#10'end;'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('shadowed-name', mFindings[0].RuleId);
end;

procedure TInheritanceShadowingTests.LocalHidesGlobal;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TShadowedNameRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'var'#10'  Zaehler: Integer;'#10'procedure Lauf;'#10'var'#10 +
    '  Zaehler: Integer;'#10'begin'#10'  Zaehler := 1;'#10'end;'#10'end.'#10);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('shadowed-name', mFindings[0].RuleId);
end;

procedure TInheritanceShadowingTests.OtherNamesAreSilent;
begin
  TRuleAssert.Silent(TShadowedNameRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TKunde = class'#10'  private'#10'    FAnzahl: Integer;'#10 +
    '  public'#10'    procedure Setze(AAnzahl: Integer);'#10'  end;'#10'implementation'#10 +
    'procedure TKunde.Setze(AAnzahl: Integer);'#10'begin'#10'  FAnzahl := AAnzahl;'#10'end;'#10'end.'#10);
end;

initialization
  TDUnitX.RegisterTestFixture(TInheritanceShadowingTests);

end.
