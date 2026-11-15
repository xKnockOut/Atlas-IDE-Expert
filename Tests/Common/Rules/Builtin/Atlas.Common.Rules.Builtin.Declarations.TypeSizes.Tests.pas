unit Atlas.Common.Rules.Builtin.Declarations.TypeSizes.Tests;

// Tests der Teilunit type-too-large: statisches Array ab 2 GB; Ketten verschachtelter Records ohne exponentielle
// Laufzeit.

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
    [Test]
    procedure NestedRecordChainIsReportedOnce;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Declarations.TypeSizes,
  Atlas.Tests.RuleAssert;

{ TDeclarationTypeSizesTests }

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

procedure TDeclarationTypeSizesTests.NestedRecordChainIsReportedOnce;
var
  mSource: string;
  mIndex: Integer;
  mFindings: TArray<TRuleFinding>;
begin
  // 40 Records mit je vier Feldern des vorigen: ohne Zwischenspeicher je Name 4^Tiefe Rechnungen (Hänger in
  // Header-Übersetzungen mit tief verschachtelten Strukturen). TR16 hat als erster 4 GB.
  // Der äußerste Record steht vorn, damit die Rechnung von oben beginnt.
  mSource := 'unit U;'#10'interface'#10'type'#10'  TOben = record A: TR40; B: TR40; end;'#10 +
    '  TR0 = record A: Byte; end;'#10;
  for mIndex := 1 to 40 do
  begin
    mSource := mSource + Format('  TR%0:d = record A: TR%1:d; B: TR%1:d; C: TR%1:d; D: TR%1:d; end;'#10,
      [mIndex, mIndex - 1]);
  end;
  mFindings := TRuleAssert.Findings(TTypeTooLargeRule.Create, mSource + 'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.IsTrue(Pos('TR16', mFindings[0].Message) > 0, mFindings[0].Message);
  mSource := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationTypeSizesTests);

end.
