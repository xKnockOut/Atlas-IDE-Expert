unit Argus.Common.Rules.Builtin.Performance.Tests;

// Tests für die Performance-Regeln (#278): je Regel ein positiver und ein negativer Fall.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPerformanceRulesTests = class
  public
    [Test]
    procedure RulesOffByDefault;
    [Test]
    procedure StringConcatInLoopReported;
    [Test]
    procedure StringConcatOutsideLoopOrNoStringSilent;
    [Test]
    procedure LoopInvariantCallReported;
    [Test]
    procedure ForBoundsAndCheapConditionSilent;
    [Test]
    procedure MissingBeginUpdateReported;
    [Test]
    procedure BeginUpdatePresentSilent;
  end;

implementation

uses
  System.SysUtils,
  Argus.Common.Configuration.Contract,
  Argus.Common.Rules.Contract,
  Argus.Common.Rules.Builtin.Performance,
  Argus.Tests.RuleAssert;

const
  // Niedrige Konfidenz wird erst ab minConfidence "low" gemeldet.
  AllOn = '{ "minConfidence": "low", "rules": { "string-concat-in-loop": "hint", "loop-invariant-call": "hint", ' +
    '"missing-begin-update": "hint" } }';

function InRoutine(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10 + AVars + #10'begin'#10 +
    ABody + #10'end;'#10'end.';
end;

function Count(const ARule: IRule; const ASource: string): Integer;
begin
  Result := Length(TRuleAssert.Findings(ARule, ASource, AllOn));
end;

procedure TPerformanceRulesTests.RulesOffByDefault;
var
  Rule: IRule;
begin
  for Rule in TArray<IRule>.Create(TStringConcatInLoopRule.Create, TLoopInvariantCallRule.Create,
    TMissingBeginUpdateRule.Create) do
    Assert.IsTrue(Rule.Descriptor.Experimental, Rule.Descriptor.Id);
end;

procedure TPerformanceRulesTests.StringConcatInLoopReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TStringConcatInLoopRule.Create, InRoutine('  S: string;'#10'  I: Integer;',
    '  for I := 1 to 10 do'#10'    S := S + IntToStr(I);'), AllOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(Findings[0].Confidence));
  Assert.AreEqual(1, Count(TStringConcatInLoopRule.Create, InRoutine('  S: string;',
    '  repeat'#10'    S := S + ''x'';'#10'  until Length(S) > 5;')));
end;

procedure TPerformanceRulesTests.StringConcatOutsideLoopOrNoStringSilent;
begin
  Assert.AreEqual(0, Count(TStringConcatInLoopRule.Create, InRoutine('  S: string;'#10'  N, I: Integer;',
    '  S := S + ''x'';'#10'  for I := 1 to 10 do'#10'    N := N + I;')));
end;

procedure TPerformanceRulesTests.LoopInvariantCallReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TLoopInvariantCallRule.Create, InRoutine('  I: Integer;',
    '  while I < Length(Trim(Memo.Lines.Text)) do'#10'    Inc(I);'), AllOn);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(1, Count(TLoopInvariantCallRule.Create, InRoutine('  I: Integer;',
    '  repeat'#10'    Inc(I);'#10'  until FileExists(Name);')));
end;

procedure TPerformanceRulesTests.ForBoundsAndCheapConditionSilent;
begin
  Assert.AreEqual(0, Count(TLoopInvariantCallRule.Create, InRoutine('  I: Integer;',
    '  for I := 1 to Length(Trim(S)) do'#10'    Inc(N);'#10'  while I < List.Count do'#10'    Inc(I);'#10 +
    '  while Reader.Trim do'#10'    Inc(I);')));
end;

procedure TPerformanceRulesTests.MissingBeginUpdateReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TMissingBeginUpdateRule.Create, InRoutine('  I: Integer;',
    '  for I := 1 to 100 do'#10'  begin'#10'    ListBox1.Items.Add(IntToStr(I));'#10 +
    '    ListBox1.Items.Add(''x'');'#10'  end;'), AllOn);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, 'ListBox1.Items.BeginUpdate');
end;

procedure TPerformanceRulesTests.BeginUpdatePresentSilent;
begin
  Assert.AreEqual(0, Count(TMissingBeginUpdateRule.Create, InRoutine('  I: Integer;',
    '  Memo1.Lines.BeginUpdate;'#10'  try'#10'    for I := 1 to 100 do'#10'      Memo1.Lines.Add(''x'');'#10 +
    '  finally'#10'    Memo1.Lines.EndUpdate;'#10'  end;'#10'  ListBox1.Items.Add(''y'');'#10 +
    '  for I := 1 to 3 do'#10'    List.Add(I);')));
end;

initialization
  TDUnitX.RegisterTestFixture(TPerformanceRulesTests);

end.
