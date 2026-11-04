unit Atlas.Common.Rules.Builtin.Declarations.Defaults.Tests;

// Tests der Teilunit default-parameter: Vorgabewert nur bei eingeschalteter Regel gemeldet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationDefaultsTests = class
  public
    [Test]
    procedure IsReported;
    [Test]
    procedure IsSilent;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Declarations.Defaults,
  Atlas.Tests.RuleAssert;

const
  cConfig = '{"rules": {"default-parameter": "warning"}}';

procedure TDeclarationDefaultsTests.IsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDefaultParameterRule.Create, 'unit U;'#10'interface'#10'procedure Zeige(A: Integer = 1);'#10'implementation'#10 +
    'procedure Zeige(A: Integer);'#10'begin'#10'end;'#10'end.', cConfig);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('default-parameter', mFindings[0].RuleId);
end;

procedure TDeclarationDefaultsTests.IsSilent;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDefaultParameterRule.Create, 'unit U;'#10'interface'#10'procedure Zeige(A: Integer = 1);'#10'implementation'#10 +
    'procedure Zeige(A: Integer);'#10'begin'#10'end;'#10'end.'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationDefaultsTests);

end.
