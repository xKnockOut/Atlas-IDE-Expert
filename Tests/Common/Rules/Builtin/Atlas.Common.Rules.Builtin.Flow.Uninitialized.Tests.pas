unit Atlas.Common.Rules.Builtin.Flow.Uninitialized.Tests;

// Tests der Teilunit possibly-uninitialized: Lesen vor der ersten Zuweisung, Merker, verwaltete Typen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowUninitializedTests = class
  public
    [Test]
    procedure ReadBeforeAssignIsReported;
    [Test]
    procedure AssignedOnAllPathsIsSilent;
    [Test]
    procedure GuardedByFlagIsSilent;
    [Test]
    procedure ManagedTypeIsSilent;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow.Uninitialized,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit "procedure P(B: Boolean)", den Variablen AVars und dem Rumpf ABody.</summary>
function Routine(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Zeige(A: Integer);'#10'begin'#10'end;'#10 +
    'procedure P(B: Boolean);'#10'var'#10 + AVars + #10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TFlowUninitializedTests.ReadBeforeAssignIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TPossiblyUninitializedRule.Create, Routine('  N: Integer;',
    '  if B then'#10'    N := 1;'#10'  Zeige(N + 1);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('possibly-uninitialized', mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
end;

procedure TFlowUninitializedTests.AssignedOnAllPathsIsSilent;
begin
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, Routine('  N: Integer;',
    '  if B then'#10'    N := 1'#10'  else'#10'    N := 2;'#10'  Zeige(N + 1);'));
end;

procedure TFlowUninitializedTests.GuardedByFlagIsSilent;
begin
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, Routine('  N: Integer;'#10'  Gefunden: Boolean;',
    '  Gefunden := False;'#10'  if B then'#10'  begin'#10'    N := 1;'#10'    Gefunden := True;'#10'  end;'#10 +
    '  if Gefunden then'#10'    Zeige(N + 1);'));
end;

procedure TFlowUninitializedTests.ManagedTypeIsSilent;
begin
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, Routine('  S, T: string;', '  T := S;'));
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowUninitializedTests);

end.
