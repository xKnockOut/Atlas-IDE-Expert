unit BDLsp.Common.Rules.Builtin.RtlPatterns.Tests;

// Tests für die Regeln zu RTL-Mustern aus #153, Stufe 1: je Regel ein
// positiver und ein negativer Fall, dazu die Fälle aus der Abnahme.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRtlPatternRulesTests = class
  public
    [Test]
    procedure SelfAssignmentReportedWithFix;
    [Test]
    procedure SelfAssignmentSilent;
    [Test]
    procedure ForHighToLowReportedWithFix;
    [Test]
    procedure ForLowToHighSilent;
    [Test]
    procedure ExceptionNotRaisedReportedWithFix;
    [Test]
    procedure RaisedExceptionSilent;
    [Test]
    procedure AssertSideEffectReported;
    [Test]
    procedure AssertWithoutSideEffectSilent;
    [Test]
    procedure AssertMutatingMethodsOption;
    [Test]
    procedure IfThenSideEffectReported;
    [Test]
    procedure IfThenWithoutSideEffectSilent;
    [Test]
    procedure RandomWithoutRandomize;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Rules.Contract,
  BDLsp.Common.Rules.Builtin.RtlPatterns,
  BDLsp.Tests.RuleAssert;

function InRoutine(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TRtlPatternRulesTests.SelfAssignmentReportedWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TSelfAssignmentRule.Create, InRoutine('  Save;'#10'  Kunde.Name := Kunde.Name;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(27, Findings[0].Fixes[0].Edits[0].Range.EndPos.Character);
  TRuleAssert.Reports(TSelfAssignmentRule.Create, InRoutine('  if A then X := x else Y := 1;'));
  TRuleAssert.Reports(TSelfAssignmentRule.Create, InRoutine('  begin Liste[I] := Liste[I] end;'));
end;

procedure TRtlPatternRulesTests.SelfAssignmentSilent;
begin
  TRuleAssert.Silent(TSelfAssignmentRule.Create, InRoutine('  X := Y;'#10'  Liste[I] := Liste[J];'#10 +
    '  X := X + 1;'#10'  for I := I to 10 do;'));
  TRuleAssert.Silent(TSelfAssignmentRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure P;'#10'var X: Integer;'#10'begin'#10'  X := F(X);'#10'end;'#10'end.');
end;

procedure TRtlPatternRulesTests.ForHighToLowReportedWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TForHighToLowRule.Create, InRoutine('  for I := High(A) to Low(A) do'#10 +
    '    Save(A[I]);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('downto', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(19, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.IsTrue(Findings[0].Fixes[0].Safe);
  TRuleAssert.Reports(TForHighToLowRule.Create, InRoutine('  for I := Liste.Count - 1 to 0 do Liste.Delete(I);'));
end;

procedure TRtlPatternRulesTests.ForLowToHighSilent;
begin
  TRuleAssert.Silent(TForHighToLowRule.Create, InRoutine('  for I := Low(A) to High(A) do Save(A[I]);'#10 +
    '  for I := High(A) downto Low(A) do Save(A[I]);'#10'  for I := 0 to Liste.Count - 1 do;'#10 +
    '  for I := High(A) - 1 to Low(A) + 5 do;'));
end;

procedure TRtlPatternRulesTests.ExceptionNotRaisedReportedWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TExceptionNotRaisedRule.Create,
    InRoutine('  if X = nil then'#10'    EArgumentException.Create(''X fehlt'');'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('raise ', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(4, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  TRuleAssert.Reports(TExceptionNotRaisedRule.Create, InRoutine('  Exception.CreateFmt(''%d'', [N])'));
end;

procedure TRtlPatternRulesTests.RaisedExceptionSilent;
begin
  TRuleAssert.Silent(TExceptionNotRaisedRule.Create, InRoutine('  raise EArgumentException.Create(''X'');'#10 +
    '  E := Exception.Create(''X'');'#10'  Exception.Create(''X'').Free;'#10'  Engine.Create;'));
end;

procedure TRtlPatternRulesTests.AssertSideEffectReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TAssertSideEffectRule.Create, InRoutine('  Assert(List.Remove(X) >= 0);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.IsTrue(Pos('Remove', Findings[0].Message) > 0, Findings[0].Message);
  TRuleAssert.Reports(TAssertSideEffectRule.Create, InRoutine('  Assert(Map.TryGetValue(K, V));'));
  TRuleAssert.Reports(TAssertSideEffectRule.Create, InRoutine('  Assert(TryStrToInt(S, N), ''Zahl'');'));
end;

procedure TRtlPatternRulesTests.AssertWithoutSideEffectSilent;
begin
  TRuleAssert.Silent(TAssertSideEffectRule.Create, InRoutine('  Assert(List.Count > 0);'#10 +
    '  Assert(Assigned(X), ''X fehlt'');'#10'  Assert(IsValid(Kunde));'#10'  Assert(Add > 0);'));
end;

procedure TRtlPatternRulesTests.AssertMutatingMethodsOption;
const
  Config = '{ "rules": { "assert-side-effect": { "severity": "warning", "mutatingMethods": ["Push"] } } }';
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TAssertSideEffectRule.Create,
    InRoutine('  Assert(Stack.Push(X));'), Config))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TAssertSideEffectRule.Create,
    InRoutine('  Assert(List.Remove(X) >= 0);'), Config))));
  Assert.AreEqual(6, Integer(Length(TAssertSideEffectRule.MutatingMethods(''))));
end;

procedure TRtlPatternRulesTests.IfThenSideEffectReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TIfThenSideEffectRule.Create,
    InRoutine('  S := IfThen(Assigned(X), X.Name, '''');'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('if Assigned(X) then S := X.Name else S := '''';', Findings[0].Fixes[0].Edits[0].NewText);
  Findings := TRuleAssert.Findings(TIfThenSideEffectRule.Create,
    InRoutine('  Caption := IfThen(Kunde <> nil, Kunde.Name, Format(''%d'', [N]));'));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Findings := TRuleAssert.Findings(TIfThenSideEffectRule.Create, InRoutine('  Log(IfThen(B, Load, ''-''));'));
  Assert.AreEqual(0, Integer(Length(Findings)));
  Findings := TRuleAssert.Findings(TIfThenSideEffectRule.Create, InRoutine('  Log(IfThen(B, Load(1), ''-''));'));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TRtlPatternRulesTests.IfThenWithoutSideEffectSilent;
begin
  TRuleAssert.Silent(TIfThenSideEffectRule.Create, InRoutine('  S := IfThen(A > B, ''x'', ''y'');'#10 +
    '  N := IfThen(Flag, 1, 2);'));
end;

procedure TRtlPatternRulesTests.RandomWithoutRandomize;
const
  Config = '{ "minConfidence": "low", "rules": { "random-without-randomize": "hint" } }';
begin
  // Standard aus.
  TRuleAssert.Silent(TRandomWithoutRandomizeRule.Create, InRoutine('  N := Random(6);'));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TRandomWithoutRandomizeRule.Create,
    InRoutine('  N := Random(6);'#10'  M := Random(6);'), Config))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRandomWithoutRandomizeRule.Create,
    InRoutine('  Randomize;'#10'  N := Random(6);'), Config))));
end;

initialization
  TDUnitX.RegisterTestFixture(TRtlPatternRulesTests);

end.
