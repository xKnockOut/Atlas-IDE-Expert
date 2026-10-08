unit BDLsp.Common.Rules.Builtin.UnitFiles.Tests;

// Tests für die Regel unit-name-mismatch (#181).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnitNameMismatchRuleTests = class
  public
    [Test]
    procedure ReportsMismatchWithFix;
    [Test]
    procedure AcceptsMatchingNameIgnoringCase;
    [Test]
    procedure IgnoresProgramsAndUnknownFiles;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Builtin.UnitFiles,
  BDLsp.Tests.RuleAssert;

const
  ToolsUnit = 'unit Tools;'#10'interface'#10'implementation'#10'end.';

procedure TUnitNameMismatchRuleTests.ReportsMismatchWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TUnitNameMismatchRule.Create, ToolsUnit, '', 'Source/Helpers.pas');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(10, Findings[0].Range.EndPos.Character);
  Assert.Contains(Findings[0].Message, 'Helpers.pas');
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Helpers', Findings[0].Fixes[0].Edits[0].NewText);
end;

procedure TUnitNameMismatchRuleTests.AcceptsMatchingNameIgnoringCase;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameMismatchRule.Create,
    'unit data.MODEL;'#10'interface'#10'implementation'#10'end.', '', 'Data.Model.pas'))));
end;

procedure TUnitNameMismatchRuleTests.IgnoresProgramsAndUnknownFiles;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUnitNameMismatchRule.Create,
    'program App;'#10'begin'#10'end.', '', 'Other.dpr'))));
  TRuleAssert.Silent(TUnitNameMismatchRule.Create, ToolsUnit);
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitNameMismatchRuleTests);

end.
