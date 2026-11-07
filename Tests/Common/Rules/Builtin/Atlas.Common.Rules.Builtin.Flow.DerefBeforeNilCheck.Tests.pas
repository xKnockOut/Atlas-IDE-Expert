unit Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck.Tests;

// Tests der Teilunit deref-before-nil-check: Zugriff vor der Abfrage, Korrektur, Abfrage davor, Neuzuweisung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowDerefBeforeNilCheckTests = class
  public
    [Test]
    procedure AccessBeforeCheckIsReported;
    [Test]
    procedure FixMovesCheckBeforeAccess;
    [Test]
    procedure CheckBeforeAccessIsSilent;
    [Test]
    procedure ReassignedBeforeCheckIsSilent;
    [Test]
    procedure IsCheckCountsAsNilCheck;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow.DerefBeforeNilCheck,
  Atlas.Tests.RuleAssert;

/// <summary>Unit mit "procedure P(L: TStringList)" und dem Rumpf ABody.</summary>
function Routine(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'function Neu: TStringList;'#10'begin'#10 +
    '  Result := nil;'#10'end;'#10'procedure P(L: TStringList);'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TFlowDerefBeforeNilCheckTests.AccessBeforeCheckIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Routine('  L.Clear;'#10 +
    '  if L <> nil then'#10'    L.Sort;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cDerefBeforeNilCheckRuleId, mFindings[0].RuleId);
end;

procedure TFlowDerefBeforeNilCheckTests.FixMovesCheckBeforeAccess;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Routine('  L.Clear;'#10 +
    '  if Assigned(L) then'#10'    L.Sort;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('if Assigned(L) then'#10'  begin'#10'    L.Clear;'#10'    L.Sort;'#10'  end',
    mFindings[0].Fixes[0].Edits[0].NewText);
end;

procedure TFlowDerefBeforeNilCheckTests.CheckBeforeAccessIsSilent;
begin
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine('  if L = nil then'#10'    Exit;'#10 +
    '  L.Clear;'#10'  if L <> nil then'#10'    L.Sort;'));
end;

procedure TFlowDerefBeforeNilCheckTests.ReassignedBeforeCheckIsSilent;
begin
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine('  L.Clear;'#10'  L := Neu;'#10 +
    '  if L <> nil then'#10'    L.Sort;'));
end;

procedure TFlowDerefBeforeNilCheckTests.IsCheckCountsAsNilCheck;
begin
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine('  if L is TStringList then'#10'    L.Clear;'#10 +
    '  if L <> nil then'#10'    L.Sort;'));
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowDerefBeforeNilCheckTests);

end.
