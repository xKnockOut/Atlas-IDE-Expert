unit Atlas.Common.Rules.Builtin.Declarations.VariantRecords.Tests;

// Tests der Teilunit variant-record-managed-field: string im varianten Teil eines Records.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationVariantRecordsTests = class
  public
    [Test]
    procedure IsReported;
    [Test]
    procedure IsSilent;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Declarations.VariantRecords,
  Atlas.Tests.RuleAssert;

procedure TDeclarationVariantRecordsTests.IsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TVariantRecordManagedFieldRule.Create, 'unit U;'#10'interface'#10'type'#10'  TWert = record'#10'    case Art: Integer of'#10 +
    '      0: (Zahl: Double);'#10'      1: (Text: string);'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('variant-record-managed-field', mFindings[0].RuleId);
end;

procedure TDeclarationVariantRecordsTests.IsSilent;
begin
  TRuleAssert.Silent(TVariantRecordManagedFieldRule.Create, 'unit U;'#10'interface'#10'type'#10'  TWert = record'#10'    case Art: Integer of'#10 +
    '      0: (Zahl: Double);'#10'      1: (Text: ShortString);'#10'  end;'#10'implementation'#10'end.');
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationVariantRecordsTests);

end.
