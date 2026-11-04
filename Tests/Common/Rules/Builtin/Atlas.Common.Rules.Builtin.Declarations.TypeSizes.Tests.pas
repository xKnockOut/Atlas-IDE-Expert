unit Atlas.Common.Rules.Builtin.Declarations.TypeSizes.Tests;

// Tests der Teilunit type-too-large: statisches Array ab 2 GB.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationTypeSizesTests = class
  public
    [Test]
    procedure IsReported;
    [Test]
    procedure IsSilent;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Declarations.TypeSizes,
  Atlas.Tests.RuleAssert;

procedure TDeclarationTypeSizesTests.IsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TTypeTooLargeRule.Create, 'unit U;'#10'interface'#10'type'#10'  TPuffer = array[0..High(Integer)] of Int64;'#10 +
    'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('type-too-large', mFindings[0].RuleId);
end;

procedure TDeclarationTypeSizesTests.IsSilent;
begin
  TRuleAssert.Silent(TTypeTooLargeRule.Create, 'unit U;'#10'interface'#10'type'#10'  TPuffer = array[0..9] of Int64;'#10'implementation'#10'end.');
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationTypeSizesTests);

end.
