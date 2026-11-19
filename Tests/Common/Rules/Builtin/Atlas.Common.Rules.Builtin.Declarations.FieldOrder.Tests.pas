unit Atlas.Common.Rules.Builtin.Declarations.FieldOrder.Tests;

// Tests der Teilunit field-after-method: Feld nach Methode gemeldet, Felder
// zuerst still. Die ausführlichen Fälle stehen in Declarations.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationFieldOrderTests = class
  public
    [Test]
    procedure IsReported;
    [Test]
    procedure IsSilent;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Declarations.FieldOrder,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit der Klasse TKunde und den Mitgliedern AMembers.</summary>
function Kunde(const AMembers: string): string;
begin
  Result := 'unit Kunden;'#10'interface'#10'type'#10'  TKunde = class'#10 + AMembers + '  end;'#10 +
    'implementation'#10'end.';
end;

{ TDeclarationFieldOrderTests }

procedure TDeclarationFieldOrderTests.IsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TFieldAfterMethodRule.Create, Kunde('    procedure A;'#10'    FX: Integer;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cFieldAfterMethodRuleId, mFindings[0].RuleId);
  Assert.AreEqual('Feld nach Methoden im selben Abschnitt (wie E2169).', mFindings[0].Message);
end;

procedure TDeclarationFieldOrderTests.IsSilent;
begin
  TRuleAssert.Silent(TFieldAfterMethodRule.Create, Kunde('    FX: Integer;'#10'    procedure A;'#10));
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationFieldOrderTests);

end.
