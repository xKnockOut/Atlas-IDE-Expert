unit Atlas.Common.Rules.Builtin.Flow.UseAfterFree.Tests;

// Tests der Teilunit use-after-free: Lesen nach Free, Neuzuweisung, Abfrage mit Assigned, Übergabe als Argument.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowUseAfterFreeTests = class
  public
    [Test]
    procedure ReadAfterFreeIsReported;
    [Test]
    procedure ReassignedIsSilent;
    [Test]
    procedure AssignedAfterFreeAndNilIsSilent;
    [Test]
    procedure PassedAsArgumentIsSilent;
    [Test]
    procedure AssignedAfterFreeIsReported;
  end;

implementation

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow.UseAfterFree,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit "procedure P(L: TStringList)" und dem Rumpf ABody.</summary>
function Routine(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Merke(A: TObject);'#10'begin'#10'end;'#10 +
    'procedure P(L: TStringList);'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TFlowUseAfterFreeTests.ReadAfterFreeIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create, Routine('  L.Free;'#10'  L.Clear;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(UseAfterFreeRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
end;

procedure TFlowUseAfterFreeTests.ReassignedIsSilent;
begin
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine('  L.Free;'#10'  L := TStringList.Create;'#10'  L.Clear;'));
end;

procedure TFlowUseAfterFreeTests.AssignedAfterFreeAndNilIsSilent;
begin
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine('  FreeAndNil(L);'#10'  if Assigned(L) then'#10 +
    '    L.Clear;'));
end;

procedure TFlowUseAfterFreeTests.PassedAsArgumentIsSilent;
begin
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine('  L.Free;'#10'  Merke(L);'#10'  L.Clear;'));
end;

procedure TFlowUseAfterFreeTests.AssignedAfterFreeIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create, Routine('  L.Free;'#10'  if Assigned(L) then'#10 +
    '    Merke(nil);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowUseAfterFreeTests);

end.
