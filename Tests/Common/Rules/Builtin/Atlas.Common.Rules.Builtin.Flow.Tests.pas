unit Atlas.Common.Rules.Builtin.Flow.Tests;

// Tests für die Flussregeln result-not-set und possibly-uninitialized (#269).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFlowRulesTests = class
  public
    [Test]
    procedure ResultSetOnlyInBranchReports;
    [Test]
    procedure ResultSetOnAllPathsIsSilent;
    [Test]
    procedure ResultAsVarArgumentIsSilent;
    [Test]
    procedure RaiseAndExitWithValueAreSilent;
    [Test]
    procedure FunctionNameAssignmentIsSilent;
    [Test]
    procedure ProcedureIsSilent;
    [Test]
    procedure UninitializedReadReports;
    [Test]
    procedure AssignedBeforeReadIsSilent;
    [Test]
    procedure OutArgumentIsSilent;
    [Test]
    procedure ManagedTypeIsSilent;
    [Test]
    procedure OpaqueUseHelper;
    [Test]
    procedure UnreachableAfterExitReportsFirstStatement;
    [Test]
    procedure UnreachableInBranchAndTry;
    [Test]
    procedure ReachableCodeIsSilent;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow,
  Atlas.Tests.RuleAssert;

function Routine(const ABody: string; const AHeader: string = 'function F: Integer;';
  const AVars: string = ''): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10 + AHeader + #10 + AVars + 'begin'#10 + ABody +
    #10'end;'#10'end.';
end;

function FirstOfKind(ANode: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  Index: Integer;
begin
  if ANode.Kind = AKind then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := FirstOfKind(ANode[Index], AKind);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

procedure TFlowRulesTests.ResultSetOnlyInBranchReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TResultNotSetRule.Create, Routine('  if A then'#10'    Result := 1;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
end;

procedure TFlowRulesTests.ResultSetOnAllPathsIsSilent;
begin
  TRuleAssert.Silent(TResultNotSetRule.Create,
    Routine('  if A then'#10'    Result := 1'#10'  else'#10'    Result := 2;'));
end;

procedure TFlowRulesTests.ResultAsVarArgumentIsSilent;
begin
  TRuleAssert.Silent(TResultNotSetRule.Create, Routine('  FMap.TryGetValue(K, Result);'));
end;

procedure TFlowRulesTests.RaiseAndExitWithValueAreSilent;
begin
  TRuleAssert.Silent(TResultNotSetRule.Create,
    Routine('  if A then'#10'    Exit(1);'#10'  raise Exception.Create(''x'');'));
end;

procedure TFlowRulesTests.FunctionNameAssignmentIsSilent;
begin
  TRuleAssert.Silent(TResultNotSetRule.Create, Routine('  F := 1;'));
end;

procedure TFlowRulesTests.ProcedureIsSilent;
begin
  TRuleAssert.Silent(TResultNotSetRule.Create, Routine('  if A then'#10'    B;', 'procedure P;'));
end;

procedure TFlowRulesTests.UninitializedReadReports;
begin
  TRuleAssert.Reports(TPossiblyUninitializedRule.Create,
    Routine('  if A then'#10'    I := 1;'#10'  J := I;', 'procedure P;', 'var'#10'  I, J: Integer;'#10));
end;

procedure TFlowRulesTests.AssignedBeforeReadIsSilent;
begin
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create,
    Routine('  I := 0;'#10'  if A then'#10'    I := 1;'#10'  J := I;', 'procedure P;', 'var'#10'  I, J: Integer;'#10));
end;

procedure TFlowRulesTests.OutArgumentIsSilent;
begin
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create,
    Routine('  Lese(I);'#10'  J := I;', 'procedure P;', 'var'#10'  I, J: Integer;'#10));
end;

procedure TFlowRulesTests.ManagedTypeIsSilent;
begin
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create,
    Routine('  T := S;', 'procedure P;', 'var'#10'  S, T: string;'#10));
end;

procedure TFlowRulesTests.OpaqueUseHelper;
var
  Tree: TSyntaxTree;
  Block: TSyntaxNode;
begin
  Tree := TPascalParser.Parse(Routine('  P := @X;', 'procedure P;'));
  try
    // Lokale Routinen überspringt die Prüfung, daher der Rumpf selbst.
    Block := FirstOfKind(Tree.Root, TSyntaxKind.Block);
    Assert.IsTrue(HasOpaqueUse(Block, 'X'));
    Assert.IsFalse(HasOpaqueUse(Block, 'Y'));
  finally
    Tree.Free;
  end;
end;

procedure TFlowRulesTests.UnreachableAfterExitReportsFirstStatement;
var
  Findings: TArray<TRuleFinding>;
begin
  // Zeile 5 ist Exit; gemeldet wird nur A in Zeile 6, nicht auch B.
  Findings := TRuleAssert.Findings(TUnreachableCodeRule.Create,
    Routine('  Exit;'#10'  A;'#10'  if X then'#10'    B;', 'procedure P;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(6, Findings[0].Range.EndPos.Line, 'Nur die erste Zeile markieren');
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
end;

procedure TFlowRulesTests.UnreachableInBranchAndTry;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TUnreachableCodeRule.Create,
    Routine('  if X then'#10'  begin'#10'    raise E;'#10'    A;'#10'  end;'#10'  B;', 'procedure P;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
  // Ein ganzer try-Block hinter Exit zählt als ein Abschnitt.
  Findings := TRuleAssert.Findings(TUnreachableCodeRule.Create,
    Routine('  Exit;'#10'  try'#10'    A;'#10'  finally'#10'    B;'#10'  end;', 'procedure P;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
end;

procedure TFlowRulesTests.ReachableCodeIsSilent;
begin
  TRuleAssert.Silent(TUnreachableCodeRule.Create,
    Routine('  if X then'#10'    Exit;'#10'  A;'#10'  if Y then'#10'    goto L;'#10'  B;'#10'L:'#10'  C;', 'procedure P;',
    'label'#10'  L;'#10));
  TRuleAssert.Silent(TUnreachableCodeRule.Create,
    Routine('  while X do'#10'  begin'#10'    if Y then'#10'      Break;'#10'    Continue;'#10'  end;'#10'  A;',
    'procedure P;'));
  // asm macht den Graphen unvollständig: keine Aussage.
  TRuleAssert.Silent(TUnreachableCodeRule.Create,
    Routine('  Exit;'#10'  asm'#10'    nop'#10'  end;', 'procedure P;'));
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowRulesTests);

end.
