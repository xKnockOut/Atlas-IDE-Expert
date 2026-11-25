unit Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.Tests;

// Tests der Teilunit destructor-not-nil-safe: Zugriff nach werfendem Konstruktor, Abfrage, Kurzschluss, Korrektur.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowDestructorNotNilSafeTests = class
  public
    [Test]
    procedure AccessAfterRaisingCreateIsReported;
    [Test]
    procedure AssignedGuardIsSilent;
    [Test]
    procedure ShortCircuitIsSilent;
    [Test]
    procedure FreeIsSilent;
    [Test]
    procedure FixWrapsStatement;
  end;

implementation

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe,
  Atlas.Tests.RuleAssert,
  Atlas.Common.Rules.Builtin.Flow.DestructorNotNilSafe.TestSupport;

const
  cCreate = '  inherited Create;'#10'  FStrom := TFileStream.Create(Datei, fmOpenRead);'#10 +
    '  FZeilen := TStringList.Create;';

{ TFlowDestructorNotNilSafeTests }

procedure TFlowDestructorNotNilSafeTests.AccessAfterRaisingCreateIsReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDestructorNotNilSafeRule.Create, ImportUnit(cCreate, '  FZeilen.Clear;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cDestructorNotNilSafeRuleId, mFindings[0].RuleId);
end;

procedure TFlowDestructorNotNilSafeTests.AssignedGuardIsSilent;
begin
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(cCreate, '  if Assigned(FZeilen) then'#10 +
    '    FZeilen.Clear;'));
end;

procedure TFlowDestructorNotNilSafeTests.ShortCircuitIsSilent;
begin
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(cCreate, '  if (FZeilen <> nil) and ' +
    '(FZeilen.Count > 0) then'#10'    Exit;'));
end;

procedure TFlowDestructorNotNilSafeTests.FreeIsSilent;
begin
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(cCreate, '  FZeilen.Free;'#10'  FStrom.Free;'));
end;

procedure TFlowDestructorNotNilSafeTests.FixWrapsStatement;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDestructorNotNilSafeRule.Create, ImportUnit(cCreate, '  FZeilen.Clear;'));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('if Assigned(FZeilen) then'#10'    FZeilen.Clear', mFindings[0].Fixes[0].Edits[0].NewText);
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowDestructorNotNilSafeTests);

end.
