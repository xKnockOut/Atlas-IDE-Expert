unit Atlas.Common.Rules.Builtin.Declarations.Duplicates.Tests;

// Tests der Teilunit duplicate-declaration: lokale Variable mit dem Namen eines Parameters.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationDuplicatesTests = class
  public
    [Test]
    procedure IsReported;
    [Test]
    procedure IsSilent;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Declarations.Duplicates,
  Atlas.Tests.RuleAssert;

procedure TDeclarationDuplicatesTests.IsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDuplicateDeclarationRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure Summieren(Betrag: Currency);'#10'var'#10'  Betrag: Currency;'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('duplicate-declaration', mFindings[0].RuleId);
end;

procedure TDeclarationDuplicatesTests.IsSilent;
begin
  TRuleAssert.Silent(TDuplicateDeclarationRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure Summieren(Betrag: Currency);'#10'var'#10'  Summe: Currency;'#10'begin'#10'end;'#10'end.');
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationDuplicatesTests);

end.
