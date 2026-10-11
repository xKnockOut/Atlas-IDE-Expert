unit Atlas.Common.Rules.Builtin.Unused.Tests;

// Tests für unused-local, unused-parameter und unused-assignment (#91).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnusedRulesTests = class
  public
    [Test]
    procedure UnusedLocalReportsWithFix;
    [Test]
    procedure FixRemovesEmptyVarSection;
    [Test]
    procedure FixRemovesNameFromList;
    [Test]
    procedure UsedLocalIsSilent;
    [Test]
    procedure LocalUsedInNestedRoutineIsSilent;
    [Test]
    procedure LocalUsedOnlyInInactiveBranchIsSilent;
    [Test]
    procedure UnusedInlineVarReports;
    [Test]
    procedure LoopVariableCountsAsUse;
    [Test]
    procedure AbsoluteCountsAsUse;
    [Test]
    procedure IgnorePatternSilencesLocal;
    [Test]
    procedure UnusedParameterReports;
    [Test]
    procedure OutParameterWrittenIsSilent;
    [Test]
    procedure OverrideMethodIsSilent;
    [Test]
    procedure EventHandlerIsSilent;
    [Test]
    procedure PublishedMethodIsSilent;
    [Test]
    procedure CallbackRoutineIsSilent;
    [Test]
    procedure PlainMethodReports;
    [Test]
    procedure InterfaceImplementationIsSilent;
    [Test]
    procedure OverwrittenAssignmentReports;
    [Test]
    procedure AssignmentReadLaterIsSilent;
    [Test]
    procedure AssignmentReadInLoopIsSilent;
    [Test]
    procedure WildcardMatching;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Unused,
  Atlas.Tests.RuleAssert;

function Routine(const ABody: string; const AHeader: string = 'procedure P;';
  const AVars: string = ''): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10 + AHeader + #10 + AVars + 'begin'#10 + ABody +
    #10'end;'#10'end.';
end;

function ClassUnit(const AMembers, AImplementation: string; const AAncestors: string = 'TObject'): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TFoo = class(' + AAncestors + ')'#10 + AMembers +
    #10'  end;'#10'implementation'#10 + AImplementation + #10'end.';
end;

/// <summary>Wendet die erste Korrektur des ersten Treffers an (Zeilen mit #10).</summary>
function ApplyFirstFix(const ASource: string; const AFindings: TArray<TRuleFinding>): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;

  function OffsetOf(ALine, ACharacter: Integer): Integer;
  var
    Index: Integer;
  begin
    Result := 0;
    for Index := 0 to ALine - 1 do
      Inc(Result, Length(Lines[Index]) + 1);
    Inc(Result, ACharacter);
  end;

begin
  Lines := ASource.Split([#10]);
  Edit := AFindings[0].Fixes[0].Edits[0];
  Result := Copy(ASource, 1, OffsetOf(Edit.Range.StartPos.Line, Edit.Range.StartPos.Character)) + Edit.NewText +
    Copy(ASource, OffsetOf(Edit.Range.EndPos.Line, Edit.Range.EndPos.Character) + 1, MaxInt);
end;

procedure TUnusedRulesTests.UnusedLocalReportsWithFix;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Routine('  I := 1;'#10'  Foo(I);', 'procedure P;', 'var'#10'  I: Integer;'#10'  J: string;'#10);
  Findings := TRuleAssert.Findings(TUnusedLocalRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Findings[0].Severity));
  Assert.Contains(Findings[0].Message, '"J"');
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(Routine('  I := 1;'#10'  Foo(I);', 'procedure P;', 'var'#10'  I: Integer;'#10),
    ApplyFirstFix(Source, Findings));
end;

procedure TUnusedRulesTests.FixRemovesEmptyVarSection;
var
  Source: string;
begin
  Source := Routine('  Foo;', 'procedure P;', 'var'#10'  J: string;'#10);
  Assert.AreEqual(Routine('  Foo;'), ApplyFirstFix(Source, TRuleAssert.Findings(TUnusedLocalRule.Create, Source)));
end;

procedure TUnusedRulesTests.FixRemovesNameFromList;
var
  Source: string;
begin
  Source := Routine('  J := 1;'#10'  Foo(J);', 'procedure P;', 'var'#10'  I, J: Integer;'#10);
  Assert.AreEqual(Routine('  J := 1;'#10'  Foo(J);', 'procedure P;', 'var'#10'  J: Integer;'#10),
    ApplyFirstFix(Source, TRuleAssert.Findings(TUnusedLocalRule.Create, Source)));
  Source := Routine('  I := 1;'#10'  Foo(I);', 'procedure P;', 'var'#10'  I, J: Integer;'#10);
  Assert.AreEqual(Routine('  I := 1;'#10'  Foo(I);', 'procedure P;', 'var'#10'  I: Integer;'#10),
    ApplyFirstFix(Source, TRuleAssert.Findings(TUnusedLocalRule.Create, Source)));
end;

procedure TUnusedRulesTests.UsedLocalIsSilent;
begin
  TRuleAssert.Silent(TUnusedLocalRule.Create,
    Routine('  I := 1;'#10'  if I > 0 then'#10'    Foo;', 'procedure P;', 'var'#10'  I: Integer;'#10));
end;

procedure TUnusedRulesTests.LocalUsedInNestedRoutineIsSilent;
begin
  TRuleAssert.Silent(TUnusedLocalRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'var'#10'  I: Integer;'#10 +
    '  procedure Q;'#10'  begin'#10'    I := 2;'#10'  end;'#10'begin'#10'  Q;'#10'end;'#10'end.');
end;

procedure TUnusedRulesTests.LocalUsedOnlyInInactiveBranchIsSilent;
var
  Findings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TUnusedLocalRule.Create,
    Routine('  {$IFDEF DEBUG}'#10'  Log(I);'#10'  {$ENDIF}', 'procedure P;', 'var'#10'  I: Integer;'#10));
  // Mit Direktiven, aber nirgends erwähnt: Treffer mit niedriger Konfidenz.
  Findings := TRuleAssert.Findings(TUnusedLocalRule.Create,
    Routine('  {$IFDEF DEBUG}'#10'  Log;'#10'  {$ENDIF}', 'procedure P;', 'var'#10'  I: Integer;'#10),
    '{"minConfidence": "low"}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(Findings[0].Confidence));
end;

procedure TUnusedRulesTests.UnusedInlineVarReports;
var
  Source: string;
begin
  Source := Routine('  var X := 1;'#10'  Foo;');
  Assert.AreEqual(Routine('  Foo;'), ApplyFirstFix(Source, TRuleAssert.Findings(TUnusedLocalRule.Create, Source)));
end;

procedure TUnusedRulesTests.LoopVariableCountsAsUse;
begin
  TRuleAssert.Silent(TUnusedLocalRule.Create,
    Routine('  for I := 1 to 3 do'#10'    Foo;', 'procedure P;', 'var'#10'  I: Integer;'#10));
end;

procedure TUnusedRulesTests.AbsoluteCountsAsUse;
begin
  TRuleAssert.Reports(TUnusedLocalRule.Create,
    Routine('  Foo(B);', 'procedure P;', 'var'#10'  A: Integer;'#10'  B: Cardinal absolute A;'#10), 0);
end;

procedure TUnusedRulesTests.IgnorePatternSilencesLocal;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TUnusedLocalRule.Create,
    Routine('  Foo;', 'procedure P;', 'var'#10'  Dummy1: Integer;'#10),
    '{"rules": {"unused-local": {"ignore": ["dummy*"]}}}');
  Assert.AreEqual(0, Integer(Length(Findings)));
end;

procedure TUnusedRulesTests.UnusedParameterReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TUnusedParameterRule.Create, Routine('  Foo(A);', 'procedure P(A, B: Integer);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, '"B"');
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TUnusedRulesTests.OutParameterWrittenIsSilent;
begin
  TRuleAssert.Silent(TUnusedParameterRule.Create, Routine('  A := 1;', 'procedure P(out A: Integer);'));
end;

procedure TUnusedRulesTests.OverrideMethodIsSilent;
begin
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    ClassUnit('    procedure Run(A: Integer); override;', 'procedure TFoo.Run(A: Integer);'#10'begin'#10'end;'));
end;

procedure TUnusedRulesTests.EventHandlerIsSilent;
begin
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    ClassUnit('  public'#10'    procedure Button1Click(Sender: TObject);',
      'procedure TFoo.Button1Click(Sender: TObject);'#10'begin'#10'end;'));
end;

procedure TUnusedRulesTests.PublishedMethodIsSilent;
begin
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    ClassUnit('  published'#10'    procedure Changed(AValue: Integer);',
      'procedure TFoo.Changed(AValue: Integer);'#10'begin'#10'end;'));
end;

procedure TUnusedRulesTests.CallbackRoutineIsSilent;
begin
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'procedure Cb(A: Integer);'#10'begin'#10'end;'#10 +
    'procedure P;'#10'begin'#10'  Register(@Cb);'#10'end;'#10'end.');
end;

procedure TUnusedRulesTests.PlainMethodReports;
begin
  TRuleAssert.Reports(TUnusedParameterRule.Create,
    ClassUnit('  public'#10'    procedure Run(A: Integer);', 'procedure TFoo.Run(A: Integer);'#10'begin'#10'end;'));
end;

procedure TUnusedRulesTests.InterfaceImplementationIsSilent;
begin
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    ClassUnit('  public'#10'    procedure Run(A: Integer);', 'procedure TFoo.Run(A: Integer);'#10'begin'#10'end;',
      'TInterfacedObject, IRunner'));
end;

procedure TUnusedRulesTests.OverwrittenAssignmentReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TUnusedAssignmentRule.Create,
    Routine('  I := 1;'#10'  I := 2;'#10'  J := I;', 'procedure P;', 'var'#10'  I, J: Integer;'#10));
  // I := 1 wird überschrieben; der an J zugewiesene Wert wird nie gelesen.
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(9, Findings[1].Range.StartPos.Line);
end;

procedure TUnusedRulesTests.AssignmentReadLaterIsSilent;
begin
  TRuleAssert.Silent(TUnusedAssignmentRule.Create,
    Routine('  I := 1;'#10'  if A then'#10'    I := 2;'#10'  Result := I;', 'function F: Integer;',
      'var'#10'  I: Integer;'#10));
end;

procedure TUnusedRulesTests.AssignmentReadInLoopIsSilent;
begin
  TRuleAssert.Silent(TUnusedAssignmentRule.Create,
    Routine('  I := 0;'#10'  while I < 10 do'#10'    I := I + 1;', 'procedure P;', 'var'#10'  I: Integer;'#10));
end;

procedure TUnusedRulesTests.WildcardMatching;
begin
  Assert.IsTrue(MatchesWildcard('Dummy1', 'dummy*'));
  Assert.IsTrue(MatchesWildcard('_x', '_?'));
  Assert.IsFalse(MatchesWildcard('_xy', '_?'));
  Assert.IsTrue(MatchesWildcard('AUnused', '*Unused'));
  Assert.IsFalse(MatchesWildcard('Used', 'X*'));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnusedRulesTests);

end.
