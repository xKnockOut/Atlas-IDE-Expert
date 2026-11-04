unit Atlas.Common.Rules.Builtin.Declarations.Overloads.Tests;

// Tests der Teilunit overload-directive-missing: verschachtelte Routinen gleichen Namens ohne overload.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationOverloadsTests = class
  public
    [Test]
    procedure IsReported;
    [Test]
    procedure IsSilent;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Declarations.Overloads,
  Atlas.Tests.RuleAssert;

procedure TDeclarationOverloadsTests.IsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, 'unit U;'#10'interface'#10'implementation'#10'procedure Aussen;'#10'  procedure Innen; begin end;'#10 +
    '  procedure Innen(X: Integer); begin end;'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('overload-directive-missing', mFindings[0].RuleId);
end;

procedure TDeclarationOverloadsTests.IsSilent;
begin
  TRuleAssert.Silent(TOverloadDirectiveMissingRule.Create, 'unit U;'#10'interface'#10'implementation'#10'procedure Aussen;'#10 +
    '  procedure Innen; overload; begin end;'#10'  procedure Innen(X: Integer); overload; begin end;'#10'begin'#10 +
    'end;'#10'end.');
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationOverloadsTests);

end.
