unit Atlas.Common.Rules.Builtin.Flow.HandleLeak.Tests;

// Tests der Teilunit handle-leak: Leck, Schließen, Weitergabe, Prüfung des Öffnens, Korrektur.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowHandleLeakTests = class
  public
    [Test]
    procedure NeverClosedIsReported;
    [Test]
    procedure ClosedIsSilent;
    [Test]
    procedure PassedOnIsSilent;
    [Test]
    procedure FailedOpenBranchIsSilent;
    [Test]
    procedure FixAppendsClose;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow.HandleLeak,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit "procedure P(const Name: string)", der Variablen H: THandle und dem Rumpf ABody.</summary>
function Routine(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Merke(A: THandle);'#10'begin'#10'end;'#10 +
    'procedure P(const Name: string);'#10'var'#10'  H: THandle;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TFlowHandleLeakTests.NeverClosedIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(THandleLeakRule.Create, Routine('  H := OpenProcess(0, False, 1);'#10 +
    '  WaitForSingleObject(H, 0);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(HandleLeakRuleId, mFindings[0].RuleId);
  Assert.AreEqual('H wird nie mit CloseHandle geschlossen (Handle-Leck).', mFindings[0].Message);
end;

procedure TFlowHandleLeakTests.ClosedIsSilent;
begin
  TRuleAssert.Silent(THandleLeakRule.Create, Routine('  H := OpenProcess(0, False, 1);'#10'  try'#10 +
    '    WaitForSingleObject(H, 0);'#10'  finally'#10'    CloseHandle(H);'#10'  end;'));
end;

procedure TFlowHandleLeakTests.PassedOnIsSilent;
begin
  TRuleAssert.Silent(THandleLeakRule.Create, Routine('  H := OpenProcess(0, False, 1);'#10'  Merke(H);'));
end;

procedure TFlowHandleLeakTests.FailedOpenBranchIsSilent;
begin
  TRuleAssert.Silent(THandleLeakRule.Create, Routine('  H := OpenProcess(0, False, 1);'#10 +
    '  if H = 0 then'#10'    Exit;'#10'  CloseHandle(H);'));
end;

procedure TFlowHandleLeakTests.FixAppendsClose;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(THandleLeakRule.Create, Routine('  H := OpenProcess(0, False, 1);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual(';'#10'  CloseHandle(H)', mFindings[0].Fixes[0].Edits[0].NewText);
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowHandleLeakTests);

end.
