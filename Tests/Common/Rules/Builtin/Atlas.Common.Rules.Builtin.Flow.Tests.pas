unit Atlas.Common.Rules.Builtin.Flow.Tests;

// Tests für die Flussregeln result-not-set und possibly-uninitialized (#269),
// unreachable-code (#94) und use-after-free (#915): Beispiel mit Sprung zur
// Freigabe, FreeAndNil, Konfidenz nach Block, doppelte Freigabe, Dispose,
// stille Muster (neue Zuweisung, Abfrage auf nil, Übergabe, try/finally,
// Schleife), Abschalten und Ausnahmen; deref-before-nil-check (#916):
// Beispiel mit Korrektur, Feld mit und ohne Aufruf dazwischen, stille Muster
// (Prüfung davor, neue Zuweisung, X := X.Next, Prüfung im selben Ausdruck,
// Schleife), Rumpf mit begin … end, else ohne Korrektur, Abschalten;
// field-free-without-nil (#917): Beispiel mit Korrektur FreeAndNil, Zweig,
// stille Muster (Destruktor, := nil, Methode setzt neu, lokale Variable),
// Option ignoreMethods, Abschalten und Ausnahmen; out-param-read (#924):
// Beispiel mit Korrektur in Deklaration und Implementierung, Integer,
// stille Muster, Abschalten; destructor-not-nil-safe (#1087): Beispiel mit
// Korrektur, bedingtes Anlegen, Hilfsmethode des Destruktors, Option
// onlyAfterRaisingCode, stille Muster, Abschalten und Ausnahmen; handle-leak
// (#1088): Beispiel mit Korrektur, Prüfung auf INVALID_HANDLE_VALUE, out-
// Argument (RegOpenKeyEx), nicht jeder Weg, Option pairs, stille Muster.

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
    /// <summary>Fluss-, Erfassungs- und Unbenutzt-Regeln in einem Lauf teilen Routinen und
    /// Kontrollflussgraphen (Review P-03).</summary>
    [Test]
    procedure FlowRulesFindSameWithSharedGraphs;
    [Test]
    procedure UseAfterFreeReportsWithJump;
    [Test]
    procedure UseAfterFreeAndNilAndConfidence;
    [Test]
    procedure DoubleFreeAndDispose;
    [Test]
    procedure SafeUsesAfterFreeAreSilent;
    [Test]
    procedure UseAfterFreeOffAndExclude;
    [Test]
    procedure DerefBeforeNilCheckReportsWithFix;
    [Test]
    procedure DerefBeforeNilCheckBlockAndElse;
    [Test]
    procedure DerefBeforeNilCheckSilentCases;
    [Test]
    procedure DerefBeforeNilCheckFieldsAndOff;
    [Test]
    procedure FieldFreeWithoutNilReportsWithFix;
    [Test]
    procedure FieldFreeWithoutNilSilentCases;
    [Test]
    procedure FieldFreeIgnoreMethodsAndOff;
    [Test]
    procedure OutParamReadIssueExample;
    [Test]
    procedure OutParamReadMethodAndInteger;
    [Test]
    procedure OutParamReadSilentAndOff;
    [Test]
    procedure DestructorNotNilSafeIssueExample;
    [Test]
    procedure DestructorNotNilSafeVariants;
    [Test]
    procedure DestructorNotNilSafeSilentCases;
    [Test]
    procedure HandleLeakIssueExample;
    [Test]
    procedure HandleLeakVariants;
    [Test]
    procedure HandleLeakSilentCases;
    [Test]
    procedure HandleLeakPairsAndOff;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Flow,
  Atlas.Common.Rules.Builtin.Capture,
  Atlas.Common.Rules.Builtin.Unused,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.CodeActions,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Configuration.Parser,
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

procedure TFlowRulesTests.FlowRulesFindSameWithSharedGraphs;
const
  Source =
    'unit U;'#10'interface'#10'implementation'#10 +
    'function F(A: Boolean; Unbenutzt: Integer): Integer;'#10 +
    'begin'#10'  if A then'#10'    Result := 1;'#10'end;'#10 +
    'procedure P;'#10'var'#10'  I, J: Integer;'#10'  K: Integer;'#10'  S: string;'#10 +
    '  procedure Inner;'#10'  var'#10'    X: Integer;'#10'  begin'#10'    Foo(X);'#10'  end;'#10 +
    'begin'#10'  Foo(I);'#10'  K := 1;'#10'  K := 2;'#10'  Foo(K);'#10 +
    '  for S in Liste do'#10'    TThread.Queue(nil, procedure begin Memo1.Lines.Add(S); end);'#10 +
    '  Exit;'#10'  Bar;'#10'end;'#10'end.';
var
  Count: Integer;
begin
  Count := TRuleAssert.SameAsSeparateRuns([TResultNotSetRule.Create, TPossiblyUninitializedRule.Create,
    TUnreachableCodeRule.Create, TCapturedLoopVariableRule.Create, TUnusedLocalRule.Create,
    TUnusedParameterRule.Create, TUnusedAssignmentRule.Create], Source, '{"minConfidence": "low"}');
  Assert.IsTrue(Count >= 5, 'Treffer mehrerer Regeln: ' + IntToStr(Count));
end;

const
  FreeHeader = 'procedure P(A: Boolean; Bericht: TBericht; Protokoll: TStrings; Zeiger: PDaten);';

procedure TFlowRulesTests.UseAfterFreeReportsWithJump;
var
  Findings: TArray<TRuleFinding>;
  Actions: TArray<TCodeAction>;
  Source: string;
  Rule: IRule;
  Found: Boolean;
begin
  Source := Routine('  Bericht.Free;'#10'  Protokoll.Add(''Seiten: '' + IntToStr(Bericht.Seiten));', FreeHeader);
  Findings := TRuleAssert.Findings(TUseAfterFreeRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(UseAfterFreeRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Bericht wurde in Zeile 6 freigegeben und wird hier wieder gelesen.', Findings[0].Message);
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(38, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(45, Findings[0].Range.EndPos.Character);
  // Keine automatische Korrektur, nur der Sprung zur Freigabe.
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Zur Freigabe in Zeile 6 springen', Findings[0].Fixes[0].Title);
  Assert.IsTrue(Findings[0].Fixes[0].HasJump);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes[0].Edits)));
  Assert.AreEqual(5, Findings[0].Fixes[0].JumpTo.Line);
  Assert.AreEqual(2, Findings[0].Fixes[0].JumpTo.Character);
  Actions := TRuleCodeActions.ForFindings(Findings, Source, Findings[0].Range);
  Assert.AreEqual('Zur Freigabe in Zeile 6 springen', Actions[0].Title);
  Assert.AreEqual(GoToPositionCommand, Actions[0].Command);
  Assert.AreEqual(2, Integer(Length(Actions[0].CommandArguments)));
  Assert.AreEqual('5', Actions[0].CommandArguments[0]);
  Assert.AreEqual('2', Actions[0].CommandArguments[1]);
  Assert.AreEqual(RuleFixTag, Actions[0].Tag);
  Assert.AreEqual(0, Integer(Length(Actions[0].Edits)));
  // Gewöhnliche Korrekturen behalten keinen Befehl.
  Assert.AreEqual('', Actions[1].Command);
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = UseAfterFreeRuleId then
      Found := True;
  Assert.IsTrue(Found, UseAfterFreeRuleId);
end;

procedure TFlowRulesTests.UseAfterFreeAndNilAndConfidence;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TUseAfterFreeRule.Create,
    Routine('  FreeAndNil(Bericht);'#10'  Bericht.Drucken;'#10'  Bericht.Free;', FreeHeader));
  Assert.AreEqual(1, Integer(Length(Findings)), 'Free nach FreeAndNil ist harmlos');
  Assert.AreEqual('Bericht wurde in Zeile 6 mit FreeAndNil freigegeben und ist hier nil.', Findings[0].Message);
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  // Freigabe nur in einem Zweig: mittlere Konfidenz.
  Findings := TRuleAssert.Findings(TUseAfterFreeRule.Create,
    Routine('  if A then'#10'    Bericht.Free;'#10'  Bericht.Drucken;', FreeHeader), '{"minConfidence": "low"}',
    'U.pas');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  // Self.FFeld zählt wie FFeld.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUseAfterFreeRule.Create,
    Routine('  Self.Bericht.Free;'#10'  Bericht.Drucken;', FreeHeader)))));
end;

procedure TFlowRulesTests.DoubleFreeAndDispose;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TUseAfterFreeRule.Create,
    Routine('  Bericht.Free;'#10'  if Assigned(Bericht) then'#10'    Bericht.Free;', FreeHeader));
  Assert.AreEqual(2, Integer(Length(Findings)), 'Assigned nach Free ist immer True, das zweite Free gibt doppelt frei');
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(7, Findings[1].Range.StartPos.Line);
  Findings := TRuleAssert.Findings(TUseAfterFreeRule.Create,
    Routine('  Dispose(Zeiger);'#10'  Zeiger^.Wert := 1;', FreeHeader));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Zeiger wurde in Zeile 6 freigegeben und wird hier wieder gelesen.', Findings[0].Message);
  // Freigabe in der Schleife ohne neue Zuweisung: der zweite Durchlauf gibt doppelt frei.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUseAfterFreeRule.Create,
    Routine('  while A do'#10'    Bericht.Free;', FreeHeader), '{"minConfidence": "low"}', 'U.pas'))));
end;

procedure TFlowRulesTests.SafeUsesAfterFreeAreSilent;
begin
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine(
    // Neue Zuweisung.
    '  Bericht.Free;'#10'  Bericht := TBericht.Create;'#10'  Bericht.Drucken;'#10 +
    '  Bericht.Free;'#10'  Bericht := nil;'#10'  if Bericht = nil then'#10'    Exit;'#10, FreeHeader));
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine(
    // Nach FreeAndNil abgefragt.
    '  FreeAndNil(Bericht);'#10'  if Assigned(Bericht) then'#10'    Bericht.Drucken;'#10 +
    '  if Bericht <> nil then'#10'    Bericht.Drucken;', FreeHeader));
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine(
    // Übergabe: nur der Zeigerwert (Liste.Remove) oder neu gesetzt (var-Parameter).
    '  Bericht.Free;'#10'  Liste.Remove(Bericht);'#10'  Bericht.Drucken;', FreeHeader));
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine(
    // try/finally und Schleife mit neuer Zuweisung je Durchlauf.
    '  while A do'#10'  begin'#10'    Bericht := TBericht.Create;'#10'    try'#10'      Bericht.Drucken;'#10 +
    '    finally'#10'      Bericht.Free;'#10'    end;'#10'  end;'#10 +
    '  Protokoll.Free;'#10'  Bericht := nil;'#10'  Protokoll := TStringList.Create;'#10'  Protokoll.Clear;',
    FreeHeader));
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine(
    // Im try neu gesetzt; der Weg über eine Ausnahme dazwischen bleibt aus.
    '  Bericht := TBericht.Create;'#10'  try'#10'    Bericht.Free;'#10'    Bericht := TBericht.Create;'#10 +
    '    Bericht.Drucken;'#10'  finally'#10'    Bericht.Free;'#10'  end;', FreeHeader));
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine(
    // Freigabe nur auf einem Weg, der nicht zum Zugriff führt.
    '  if A then'#10'  begin'#10'    Bericht.Free;'#10'    Exit;'#10'  end;'#10'  Bericht.Drucken;', FreeHeader));
end;

procedure TFlowRulesTests.UseAfterFreeOffAndExclude;
var
  Source: string;
begin
  Source := Routine('  Bericht.Free;'#10'  Bericht.Drucken;', FreeHeader);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUseAfterFreeRule.Create, Source,
    '{"rules": {"use-after-free": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUseAfterFreeRule.Create, Source,
    '{"rules": {"use-after-free": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUseAfterFreeRule.Create, Source,
    '{"rules": {"use-after-free": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

const
  CheckHeader = 'procedure P(Kunde, Knoten: TKunde);';
  CheckVars = 'var'#10'  Titel: string;'#10;

procedure TFlowRulesTests.DerefBeforeNilCheckReportsWithFix;
const
  Body = '  Titel := Kunde.Name;'#10'  if Assigned(Kunde) then'#10'    Anzeigen(Kunde);';
  Fixed = '  if Assigned(Kunde) then'#10'  begin'#10'    Titel := Kunde.Name;'#10'    Anzeigen(Kunde);'#10'  end;';
var
  Findings: TArray<TRuleFinding>;
  Text: string;
  Tree: TSyntaxTree;
  Rule: IRule;
  Found: Boolean;
begin
  Findings := TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Routine(Body, CheckHeader, CheckVars));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(DerefBeforeNilCheckRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('Kunde wird hier benutzt, aber erst in Zeile 9 auf nil geprüft.', Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(11, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Prüfung vor den Zugriff ziehen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Text := TChangeSignature.ApplyEdits(Routine(Body, CheckHeader, CheckVars), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Routine(Fixed, CheckHeader, CheckVars), Text);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'Ergebnis parst fehlerfrei');
  finally
    Tree.Free;
  end;
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Text);
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = DerefBeforeNilCheckRuleId then
      Found := True;
  Assert.IsTrue(Found, DerefBeforeNilCheckRuleId);
end;

procedure TFlowRulesTests.DerefBeforeNilCheckBlockAndElse;
const
  Body = '  Kunde.Laden;'#10'  if Kunde <> nil then'#10'  begin'#10'    Anzeigen(Kunde);'#10'    Titel := '''';'#10 +
    '  end;';
  Fixed = '  if Kunde <> nil then'#10'  begin'#10'    Kunde.Laden;'#10'    Anzeigen(Kunde);'#10'    Titel := '''';'#10 +
    '  end;';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Routine(Body, CheckHeader, CheckVars));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Routine(Fixed, CheckHeader, CheckVars),
    TChangeSignature.ApplyEdits(Routine(Body, CheckHeader, CheckVars), Findings[0].Fixes[0].Edits));
  // Mit else oder nicht direkt danach: Meldung ohne Korrektur.
  Findings := TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Routine('  Titel := Kunde.Name;'#10 +
    '  if Kunde = nil then'#10'    Titel := '''''#10'  else'#10'    Anzeigen(Kunde);', CheckHeader, CheckVars));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Findings := TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Routine('  Titel := Kunde.Name;'#10 +
    '  Anzeigen(Titel);'#10'  if Assigned(Kunde) then'#10'    Anzeigen(Kunde);', CheckHeader, CheckVars));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Kunde wird hier benutzt, aber erst in Zeile 10 auf nil geprüft.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TFlowRulesTests.DerefBeforeNilCheckSilentCases;
begin
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // Schon vorher geprüft.
    '  if Kunde = nil then'#10'    Exit;'#10'  Titel := Kunde.Name;'#10'  if Assigned(Kunde) then'#10 +
    '    Anzeigen(Kunde);', CheckHeader, CheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // Dazwischen neu gesetzt bzw. X := X.Next.
    '  Titel := Kunde.Name;'#10'  Kunde := Suchen(Titel);'#10'  if Assigned(Kunde) then'#10'    Anzeigen(Kunde);'#10 +
    '  Knoten := Knoten.Weiter;'#10'  if Knoten <> nil then'#10'    Anzeigen(Knoten);', CheckHeader, CheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // Prüfung im selben Ausdruck vor dem Zugriff, Schleife über eine Kette.
    '  if Assigned(Kunde) and Kunde.Aktiv then'#10'    Anzeigen(Kunde);'#10 +
    '  while Knoten <> nil do'#10'  begin'#10'    Knoten.Pruefen;'#10'    Knoten := Knoten.Weiter;'#10'  end;',
    CheckHeader, CheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // Übergabe dazwischen: die Routine kann den Wert ändern.
    '  Titel := Kunde.Name;'#10'  Ersetzen(Kunde);'#10'  if Assigned(Kunde) then'#10'    Anzeigen(Kunde);',
    CheckHeader, CheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // Supports setzt Kunde im selben Ausdruck; Zugriff nur in einem Zweig, die Prüfung gilt dem anderen.
    '  if Supports(Quelle, IKunde, Kunde) and Kunde.Aktiv then'#10'    Titel := '''';'#10 +
    '  if A then'#10'  begin'#10'    Kunde := TKunde.Create;'#10'    Kunde.Laden;'#10'  end;'#10 +
    '  if Kunde <> nil then'#10'    Anzeigen(Kunde);', 'procedure P(A: Boolean; Kunde: TKunde);', CheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // while als Prüfung späterer Durchläufe.
    '  Titel := Knoten.Name;'#10'  while Knoten <> nil do'#10'    Knoten := Knoten.Parent;', CheckHeader, CheckVars));
end;

procedure TFlowRulesTests.DerefBeforeNilCheckFieldsAndOff;
var
  Source: string;
begin
  // Feld ohne Aufruf dazwischen: gemeldet; mit Aufruf (kann das Feld ändern): still.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Routine(
    '  Titel := FKunde.Name;'#10'  if Assigned(FKunde) then'#10'    Titel := '''';', CheckHeader, CheckVars)))));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    '  Titel := FKunde.Name;'#10'  Laden;'#10'  if Assigned(FKunde) then'#10'    Titel := '''';', CheckHeader,
    CheckVars));
  Source := Routine('  Titel := Kunde.Name;'#10'  if Assigned(Kunde) then'#10'    Anzeigen(Kunde);', CheckHeader,
    CheckVars);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Source,
    '{"rules": {"deref-before-nil-check": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Source,
    '{"rules": {"deref-before-nil-check": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Source,
    '{"rules": {"deref-before-nil-check": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

function ClassUnit(const AImplementation: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TImport = class'#10'  private'#10'    FCache: TObject;'#10 +
    '    FListe: TList;'#10'    procedure Laden;'#10'    procedure Zuruecksetzen;'#10'  public'#10 +
    '    destructor Destroy; override;'#10'  end;'#10'implementation'#10 + AImplementation + 'end.';
end;

procedure TFlowRulesTests.FieldFreeWithoutNilReportsWithFix;
const
  Body = 'procedure TImport.Zuruecksetzen;'#10'begin'#10'  FCache.Free;'#10'end;'#10;
  Fixed = 'procedure TImport.Zuruecksetzen;'#10'begin'#10'  FreeAndNil(FCache);'#10'end;'#10;
var
  Findings: TArray<TRuleFinding>;
  Text: string;
  Tree: TSyntaxTree;
  Rule: IRule;
  Found: Boolean;
begin
  Findings := TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(Body));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(FieldFreeWithoutNilRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('FCache bleibt nach Free gesetzt; ein späterer Zugriff trifft freigegebenen Speicher.',
    Findings[0].Message);
  Assert.AreEqual(15, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('FreeAndNil(FCache)', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Text := TChangeSignature.ApplyEdits(ClassUnit(Body), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(ClassUnit(Fixed), Text);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'Ergebnis parst fehlerfrei');
  finally
    Tree.Free;
  end;
  TRuleAssert.Silent(TFieldFreeWithoutNilRule.Create, Text);
  // Nur in einem Zweig, Self.FFeld und Free().
  Assert.AreEqual(2, Integer(Length(TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(
    'procedure TImport.Zuruecksetzen;'#10'begin'#10'  if FListe = nil then'#10'    Self.FCache.Free'#10 +
    '  else'#10'    FCache := nil;'#10'  FListe.Free();'#10'end;'#10)))));
  // Generische Klasse.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TStapel<T> = class'#10'  private'#10'    FElemente: TList<T>;'#10 +
    '    procedure Leeren;'#10'  end;'#10'implementation'#10 +
    'procedure TStapel<T>.Leeren;'#10'begin'#10'  FElemente.Free;'#10'end;'#10'end.'))));
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = FieldFreeWithoutNilRuleId then
      Found := True;
  Assert.IsTrue(Found, FieldFreeWithoutNilRuleId);
end;

procedure TFlowRulesTests.FieldFreeWithoutNilSilentCases;
begin
  TRuleAssert.Silent(TFieldFreeWithoutNilRule.Create, ClassUnit(
    // Destruktor und ein neues Objekt bzw. nil danach.
    'destructor TImport.Destroy;'#10'begin'#10'  FCache.Free;'#10'  FListe.Free;'#10'  inherited;'#10'end;'#10 +
    'procedure TImport.Zuruecksetzen;'#10'begin'#10'  FCache.Free;'#10'  FCache := nil;'#10 +
    '  FListe.Free;'#10'  FListe := TList.Create;'#10'end;'#10));
  TRuleAssert.Silent(TFieldFreeWithoutNilRule.Create, ClassUnit(
    // Eine Methode derselben Klasse setzt das Feld neu.
    'procedure TImport.Laden;'#10'begin'#10'  FCache := TObject.Create;'#10'end;'#10 +
    'procedure TImport.Zuruecksetzen;'#10'begin'#10'  FCache.Free;'#10'  Laden;'#10'end;'#10));
  TRuleAssert.Silent(TFieldFreeWithoutNilRule.Create, ClassUnit(
    // Lokale Variable, FreeAndNil, Routine ohne Klasse.
    'procedure TImport.Zuruecksetzen;'#10'var'#10'  FCache: TObject;'#10'begin'#10'  FCache := nil;'#10 +
    '  FCache.Free;'#10'  FreeAndNil(FListe);'#10'end;'#10 +
    'procedure Aufraeumen(FCache: TObject);'#10'begin'#10'  FCache.Free;'#10'end;'#10));
  TRuleAssert.Silent(TFieldFreeWithoutNilRule.Create, ClassUnit(
    // Nur aus dem Destruktor aufgerufen.
    'procedure TImport.Zuruecksetzen;'#10'begin'#10'  FCache.Free;'#10'end;'#10 +
    'destructor TImport.Destroy;'#10'begin'#10'  Zuruecksetzen;'#10'  inherited;'#10'end;'#10));
  // Auch anderswo aufgerufen: gemeldet.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(
    'procedure TImport.Zuruecksetzen;'#10'begin'#10'  FCache.Free;'#10'end;'#10 +
    'procedure TImport.Laden;'#10'begin'#10'  Zuruecksetzen;'#10'end;'#10 +
    'destructor TImport.Destroy;'#10'begin'#10'  Zuruecksetzen;'#10'  inherited;'#10'end;'#10)))));
  // DUnitX: [TearDown] gibt frei, [Setup] legt neu an.
  TRuleAssert.Silent(TFieldFreeWithoutNilRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TTests = class'#10'  private'#10'    FListe: TList;'#10'  public'#10 +
    '    [TearDown]'#10'    procedure Aufraeumen;'#10'  end;'#10'implementation'#10 +
    'procedure TTests.Aufraeumen;'#10'begin'#10'  FListe.Free;'#10'end;'#10'end.');
end;

procedure TFlowRulesTests.FieldFreeIgnoreMethodsAndOff;
const
  Body = 'procedure TImport.BeforeDestruction;'#10'begin'#10'  FCache.Free;'#10'end;'#10 +
    'procedure TImport.Zuruecksetzen;'#10'begin'#10'  FListe.Free;'#10'end;'#10;
var
  Findings: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
begin
  Findings := TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(Body));
  Assert.AreEqual(1, Integer(Length(Findings)), 'Vorgabe: BeforeDestruction ausgenommen');
  Assert.AreEqual('FListe bleibt nach Free gesetzt; ein späterer Zugriff trifft freigegebenen Speicher.',
    Findings[0].Message);
  Findings := TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(Body),
    '{"rules": {"field-free-without-nil": {"ignoreMethods": ["Zuruecksetzen"]}}}', 'U.pas');
  Assert.AreEqual(1, Integer(Length(Findings)), 'Option ersetzt die Vorgabe');
  Assert.AreEqual('FCache bleibt nach Free gesetzt; ein späterer Zugriff trifft freigegebenen Speicher.',
    Findings[0].Message);
  Assert.AreEqual(2, Integer(Length(TFieldFreeWithoutNilRule.DefaultIgnoreMethods)));
  TConfigurationParser.Parse('{"rules": {"field-free-without-nil": {"ignoreMethods": "Destroy"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"ignoreMethods" muss eine Liste von Texten sein', Issues[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(Body),
    '{"rules": {"field-free-without-nil": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(Body),
    '{"rules": {"field-free-without-nil": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(Body),
    '{"rules": {"field-free-without-nil": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

const
  Anhaengen = 'unit U;'#10'interface'#10'procedure Anhaengen(out Text: string);'#10'implementation'#10 +
    'procedure Anhaengen(out Text: string);'#10'begin'#10'  Text := Text + sLineBreak + ''Ende'';'#10'end;'#10'end.';

procedure TFlowRulesTests.OutParamReadIssueExample;
var
  Findings: TArray<TRuleFinding>;
  Fixed: string;
begin
  Findings := TRuleAssert.Findings(TOutParamReadRule.Create, Anhaengen);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('out-Parameter Text wird gelesen, bevor er gesetzt ist; bei string ist er hier immer leer.',
    Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(10, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('out durch var ersetzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes[0].Edits)), 'Deklaration und Implementierung');
  Fixed := TChangeSignature.ApplyEdits(Anhaengen, Findings[0].Fixes[0].Edits);
  Assert.AreEqual(StringReplace(Anhaengen, '(out Text', '(var Text', [rfReplaceAll]), Fixed);
  TRuleAssert.Silent(TOutParamReadRule.Create, Fixed);
end;

procedure TFlowRulesTests.OutParamReadMethodAndInteger;
const
  Source = 'unit U;'#10'interface'#10'type'#10'  TZaehler = class'#10'    procedure Weiter(out N: Integer);'#10 +
    '  end;'#10'  TAnderer = class'#10'    procedure Weiter(out N: Integer);'#10'  end;'#10'implementation'#10 +
    'procedure TZaehler.Weiter(out N: Integer);'#10'begin'#10'  if N > 0 then'#10'    N := 0;'#10'end;'#10 +
    'procedure TAnderer.Weiter(out N: Integer);'#10'begin'#10'  N := 1;'#10'end;'#10'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TOutParamReadRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('out-Parameter N wird gelesen, bevor er gesetzt ist; sein Wert ist hier undefiniert.',
    Findings[0].Message);
  // Nur die Deklaration in TZaehler, nicht die gleichnamige in TAnderer.
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes[0].Edits)));
  Assert.AreEqual(4, Findings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(10, Findings[0].Fixes[0].Edits[1].Range.StartPos.Line);
end;

procedure TFlowRulesTests.OutParamReadSilentAndOff;
begin
  // Erst gesetzt, dann gelesen; an eine Routine übergeben; Feld eines Records gesetzt; var-Parameter.
  TRuleAssert.Silent(TOutParamReadRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure A(out S: string);'#10'begin'#10'  S := '''';'#10'  S := S + ''x'';'#10'end;'#10 +
    'procedure B(out S: string);'#10'begin'#10'  Fuellen(S);'#10'  S := S + ''x'';'#10'end;'#10 +
    'procedure C(out R: TPunkt);'#10'begin'#10'  R.X := 1;'#10'  R.Y := R.X;'#10'end;'#10 +
    'procedure D(var S: string);'#10'begin'#10'  S := S + ''x'';'#10'end;'#10 +
    'function E(out P: TPunkt): Boolean;'#10'begin'#10'  Result := Lesen(P.X) and (P.X > 0);'#10'end;'#10'end.');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOutParamReadRule.Create, Anhaengen,
    '{"rules": {"out-param-read": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOutParamReadRule.Create, Anhaengen,
    '{"rules": {"out-param-read": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TOutParamReadRule.Create, Anhaengen,
    '{"rules": {"out-param-read": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

function ImportUnit(const AConstructor, ADestructor, AExtra: string): string; overload;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TImport = class'#10'  private'#10'    FStrom: TFileStream;'#10 +
    '    FZeilen: TStringList;'#10'    procedure Leeren;'#10'  public'#10 +
    '    constructor Create(const Datei: string);'#10'    destructor Destroy; override;'#10'  end;'#10 +
    'implementation'#10'constructor TImport.Create(const Datei: string);'#10'begin'#10 + AConstructor + #10 +
    'end;'#10'destructor TImport.Destroy;'#10'begin'#10 + ADestructor + #10'end;'#10 + AExtra + 'end.';
end;

function ImportUnit(const AConstructor, ADestructor: string): string; overload;
begin
  Result := ImportUnit(AConstructor, ADestructor, '');
end;

const
  ImportCreate = '  inherited Create;'#10'  FStrom := TFileStream.Create(Datei, fmOpenRead);'#10 +
    '  FZeilen := TStringList.Create;';

procedure TFlowRulesTests.DestructorNotNilSafeIssueExample;
const
  Destroy = '  FZeilen.Clear;'#10'  FZeilen.Free;'#10'  FStrom.Free;'#10'  inherited;';
  Fixed = '  if Assigned(FZeilen) then'#10'    FZeilen.Clear;'#10'  FZeilen.Free;'#10'  FStrom.Free;'#10'  inherited;';
var
  Findings: TArray<TRuleFinding>;
  Text: string;
  Tree: TSyntaxTree;
  Rule: IRule;
  Found: Boolean;
begin
  Findings := TRuleAssert.Findings(TDestructorNotNilSafeRule.Create, ImportUnit(ImportCreate, Destroy));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(DestructorNotNilSafeRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Wirft TFileStream.Create, ist FZeilen beim Destruktor noch nil; FZeilen.Clear stürzt ab und ' +
    'verdeckt die eigentliche Exception.', Findings[0].Message);
  Assert.AreEqual(21, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('In if Assigned(FZeilen) then einschließen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Text := TChangeSignature.ApplyEdits(ImportUnit(ImportCreate, Destroy), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(ImportUnit(ImportCreate, Fixed), Text);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'Ergebnis parst fehlerfrei');
  finally
    Tree.Free;
  end;
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, Text);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDestructorNotNilSafeRule.Create,
    ImportUnit(ImportCreate, Destroy), '{"rules": {"destructor-not-nil-safe": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDestructorNotNilSafeRule.Create,
    ImportUnit(ImportCreate, Destroy), '{"rules": {"destructor-not-nil-safe": {"exclude": ["Alt/*.pas"]}}}',
    'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TDestructorNotNilSafeRule.Create,
    ImportUnit(ImportCreate, Destroy), '{"rules": {"destructor-not-nil-safe": {"exclude": ["Alt/*.pas"]}}}',
    'Neu/U.pas'))));
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = DestructorNotNilSafeRuleId then
      Found := True;
  Assert.IsTrue(Found, DestructorNotNilSafeRuleId);
end;

procedure TFlowRulesTests.DestructorNotNilSafeVariants;
var
  Findings: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
begin
  // Nur bedingt angelegt: auch ohne Aufruf davor; Zugriff über Self, Property und Index.
  Findings := TRuleAssert.Findings(TDestructorNotNilSafeRule.Create, ImportUnit(
    '  inherited Create;'#10'  if Datei <> '''' then'#10'    FZeilen := TStringList.Create;',
    '  if Self.FZeilen.Count > 0 then'#10'    Speichern;'#10'  FZeilen.Free;'#10'  inherited;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('FZeilen wird im Konstruktor nur bedingt angelegt und kann beim Destruktor nil sein; ' +
    'Self.FZeilen.Count stürzt dann ab.', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)), 'if über mehrere Zeilen: keine Korrektur');
  // Ein Aufruf ohne Klammern vor dem Anlegen; Zugriff in einer Hilfsmethode, die nur der Destruktor aufruft.
  Findings := TRuleAssert.Findings(TDestructorNotNilSafeRule.Create, ImportUnit(
    '  inherited Create;'#10'  Pruefen;'#10'  FZeilen := TStringList.Create;',
    '  Leeren;'#10'  FZeilen.Free;'#10'  inherited;',
    'procedure TImport.Leeren;'#10'begin'#10'  FZeilen[0] := '''';'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Wirft Pruefen, ist FZeilen beim Destruktor noch nil; FZeilen[0] stürzt ab und verdeckt die ' +
    'eigentliche Exception.', Findings[0].Message);
  Assert.AreEqual(27, Findings[0].Range.StartPos.Line);
  // onlyAfterRaisingCode aus: auch das erste angelegte Feld.
  Findings := TRuleAssert.Findings(TDestructorNotNilSafeRule.Create, ImportUnit(ImportCreate,
    '  FStrom.Position := 0;'#10'  FStrom.Free;'#10'  inherited;'),
    '{"rules": {"destructor-not-nil-safe": {"onlyAfterRaisingCode": false}}}', 'U.pas');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Wirft TFileStream.Create, ist FStrom beim Destruktor noch nil; FStrom.Position stürzt ab und ' +
    'verdeckt die eigentliche Exception.', Findings[0].Message);
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(ImportCreate,
    '  FStrom.Position := 0;'#10'  FStrom.Free;'#10'  inherited;'));
  // Der Parser prüft die Option als Wahrheitswert.
  TConfigurationParser.Parse('{"rules": {"destructor-not-nil-safe": {"onlyAfterRaisingCode": "ja"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  TConfigurationParser.Parse('{"rules": {"destructor-not-nil-safe": {"onlyAfterRaisingCode": false}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Je Anweisung ein Befund, damit jede Korrektur ihre Anweisung schützt.
  TRuleAssert.Reports(TDestructorNotNilSafeRule.Create, ImportUnit(ImportCreate,
    '  FZeilen.Clear;'#10'  FZeilen.Sorted := False;'#10'  FZeilen.Free;'#10'  inherited;'), 2);
  // TObjectList<T>.Create(True) wirft höchstens EOutOfMemory; ein Konstruktor mit Datei davor schon.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(
    '  FStrom := TObjectList<TObject>.Create(True);'#10'  FZeilen := TStringList.Create;',
    '  FZeilen.Clear;'#10'  inherited;'));
  // Destroy ist nicht nil-sicher; DisposeOf schon.
  TRuleAssert.Reports(TDestructorNotNilSafeRule.Create, ImportUnit(ImportCreate,
    '  FZeilen.Destroy;'#10'  FStrom.DisposeOf;'#10'  inherited;'));
end;

procedure TFlowRulesTests.DestructorNotNilSafeSilentCases;
begin
  // Free, FreeAndNil, Assigned, <> nil, = nil mit Exit.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(ImportCreate,
    '  FreeAndNil(FZeilen);'#10'  FStrom.Free;'#10'  inherited;'));
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(ImportCreate,
    '  if Assigned(FZeilen) and (FZeilen.Count > 0) then'#10'    FZeilen.Clear;'#10'  FZeilen.Free;'#10 +
    '  inherited;'));
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(ImportCreate,
    '  if FZeilen <> nil then'#10'    FZeilen.Clear;'#10'  inherited;'));
  // Kein werfender Aufruf vor dem Anlegen: inherited Create zählt nicht.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(
    '  inherited Create;'#10'  FZeilen := TStringList.Create;'#10'  FStrom := TFileStream.Create(Datei, fmOpenRead);',
    '  FZeilen.Clear;'#10'  FZeilen.Free;'#10'  FStrom.Free;'#10'  inherited;'));
  // Auf beiden Zweigen angelegt, ohne Aufruf davor.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(
    '  if Datei = '''' then'#10'    FZeilen := TStringList.Create'#10'  else'#10 +
    '    FZeilen := THashedStringList.Create;',
    '  FZeilen.Clear;'#10'  inherited;'));
  // BeforeDestruction läuft nach einer Exception im Konstruktor nicht; Leeren wird auch anderswo aufgerufen.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(ImportCreate,
    '  Leeren;'#10'  inherited;',
    'procedure TImport.BeforeDestruction;'#10'begin'#10'  FZeilen.SaveToFile(''x'');'#10'end;'#10 +
    'procedure TImport.Leeren;'#10'begin'#10'  FZeilen.Clear;'#10'end;'#10 +
    'procedure TImport.Neu;'#10'begin'#10'  Leeren;'#10'end;'#10));
  // Im Destruktor neu gesetzt; Feld nicht im Konstruktor angelegt; Klasse ohne Konstruktor.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(ImportCreate,
    '  FZeilen := nil;'#10'  FZeilen.Free;'#10'  inherited;'));
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit('  inherited Create;'#10'  Pruefen;',
    '  FZeilen.Clear;'#10'  inherited;'));
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, 'unit U;'#10'interface'#10'type'#10'  TA = class'#10 +
    '    FL: TList;'#10'    destructor Destroy; override;'#10'  end;'#10'implementation'#10 +
    'destructor TA.Destroy;'#10'begin'#10'  FL.Clear;'#10'end;'#10'end.');
  // Konstruktoren der RTL, die höchstens EOutOfMemory werfen, und Supports zählen nicht als werfend.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(
    '  FStrom := TMemoryStream.Create;'#10'  if Supports(Datei, IInterface) then'#10'    Exit;'#10 +
    '  FZeilen := TStringList.Create;', '  FZeilen.Clear;'#10'  inherited;'));
  // Öffentliche Methoden rufen auch andere Units auf; sie laufen nicht nur im Destruktor.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, 'unit U;'#10'interface'#10'type'#10'  TA = class'#10 +
    '    FS: TFileStream;'#10'    FL: TList;'#10'  public'#10'    constructor Create;'#10 +
    '    destructor Destroy; override;'#10'    procedure Schliessen;'#10'  end;'#10'implementation'#10 +
    'constructor TA.Create;'#10'begin'#10'  FS := TFileStream.Create(''x'', fmOpenRead);'#10 +
    '  FL := TList.Create;'#10'end;'#10'destructor TA.Destroy;'#10'begin'#10'  Schliessen;'#10'end;'#10 +
    'procedure TA.Schliessen;'#10'begin'#10'  FL.Clear;'#10'end;'#10'end.');
  // Record mit Create (TStopwatch).
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, 'unit U;'#10'interface'#10'type'#10'  TA = class'#10 +
    '    FL: TList;'#10'    FUhr: TStopwatch;'#10'    constructor Create;'#10'    destructor Destroy; override;'#10 +
    '  end;'#10'implementation'#10'constructor TA.Create;'#10'begin'#10'  FL := TList.Create;'#10 +
    '  FUhr := TStopwatch.StartNew;'#10'  FUhr := TStopwatch.Create;'#10'end;'#10'destructor TA.Destroy;'#10 +
    'begin'#10'  FUhr.Stop;'#10'  FL.Free;'#10'end;'#10'end.');
end;

function Prozess(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure ProzessStarten(const Befehl: string);'#10 +
    'var SI: TStartupInfo; PI: TProcessInformation;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

function Datei(const AVars, ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure Lesen(Wnd: HWND; Fehler: Boolean);'#10 +
    'var'#10 + AVars + 'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TFlowRulesTests.HandleLeakIssueExample;
const
  Body = '  CreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI);'#10 +
    '  WaitForSingleObject(PI.hProcess, INFINITE);';
  Fixed = '  CreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI);'#10'  try'#10 +
    '    WaitForSingleObject(PI.hProcess, INFINITE);'#10'  finally'#10'    CloseHandle(PI.hThread);'#10 +
    '    CloseHandle(PI.hProcess);'#10'  end;';
var
  Findings: TArray<TRuleFinding>;
  Text: string;
  Tree: TSyntaxTree;
  Rule: IRule;
  Found: Boolean;
begin
  Findings := TRuleAssert.Findings(THandleLeakRule.Create, Prozess(Body));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(HandleLeakRuleId, Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual('PI.hProcess und PI.hThread werden nie mit CloseHandle geschlossen (Handle-Leck).',
    Findings[0].Message);
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('In try … finally CloseHandle einschließen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  Text := TChangeSignature.ApplyEdits(Prozess(Body), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Prozess(Fixed), Text);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), 'Ergebnis parst fehlerfrei');
  finally
    Tree.Free;
  end;
  TRuleAssert.Silent(THandleLeakRule.Create, Text);
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = HandleLeakRuleId then
      Found := True;
  Assert.IsTrue(Found, HandleLeakRuleId);
end;

procedure TFlowRulesTests.HandleLeakVariants;
var
  Findings: TArray<TRuleFinding>;
  Text: string;
begin
  // Nach der Prüfung auf INVALID_HANDLE_VALUE, auf einem Weg mit Exit nicht geschlossen.
  Findings := TRuleAssert.Findings(THandleLeakRule.Create, Datei('  H: THandle;'#10,
    '  H := CreateFileW(''a.txt'', GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);'#10 +
    '  if H = INVALID_HANDLE_VALUE then'#10'    RaiseLastOSError;'#10'  if Fehler then'#10'    Exit;'#10 +
    '  CloseHandle(H);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('H wird nicht auf jedem Weg mit CloseHandle geschlossen (Handle-Leck).', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)), 'nur ohne jedes Schließen eine Korrektur');
  // out-Argument von RegOpenKeyEx im Zweig "gelungen".
  Findings := TRuleAssert.Findings(THandleLeakRule.Create, Datei('  Key: HKEY;'#10,
    '  if RegOpenKeyEx(HKEY_CURRENT_USER, ''Software\Atlas'', 0, KEY_READ, Key) = ERROR_SUCCESS then'#10 +
    '    RegQueryValueEx(Key, ''Pfad'', nil, nil, nil, nil);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Key wird nie mit RegCloseKey geschlossen (Handle-Leck).', Findings[0].Message);
  // GetDC: das Gegenstück bekommt das Fenster; letzte Anweisung im Block: nur anhängen.
  Findings := TRuleAssert.Findings(THandleLeakRule.Create, Datei('  DC: HDC;'#10,
    '  DC := GetDC(Wnd);'#10'  TextOut(DC, 0, 0, ''x'', 1);'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Text := TChangeSignature.ApplyEdits(Datei('  DC: HDC;'#10, '  DC := GetDC(Wnd);'#10'  TextOut(DC, 0, 0, ''x'', 1);'),
    Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Datei('  DC: HDC;'#10, '  DC := GetDC(Wnd);'#10'  try'#10'    TextOut(DC, 0, 0, ''x'', 1);'#10 +
    '  finally'#10'    ReleaseDC(Wnd, DC);'#10'  end;'), Text);
  Findings := TRuleAssert.Findings(THandleLeakRule.Create, Datei('  Lib: HMODULE;'#10,
    '  Lib := LoadLibrary(''x.dll'');'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('FreeLibrary ergänzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(Datei('  Lib: HMODULE;'#10, '  Lib := LoadLibrary(''x.dll'');'#10'  FreeLibrary(Lib);'),
    TChangeSignature.ApplyEdits(Datei('  Lib: HMODULE;'#10, '  Lib := LoadLibrary(''x.dll'');'),
    Findings[0].Fixes[0].Edits));
  // Inline-Variable und GDI-Objekt; if mit Fehlerwert 0 im else-Zweig.
  TRuleAssert.Reports(THandleLeakRule.Create, Datei('  X: Integer;'#10,
    '  var Stift := CreatePen(PS_SOLID, 1, 0);'#10'  SelectObject(0, Stift);'));
  TRuleAssert.Reports(THandleLeakRule.Create, Datei('  E: THandle;'#10,
    '  E := CreateEvent(nil, True, False, nil);'#10'  if E <> 0 then'#10'    SetEvent(E)'#10'  else'#10 +
    '    Exit;'));
end;

procedure TFlowRulesTests.HandleLeakSilentCases;
begin
  // Geschlossen, auch im finally; Fehlerzweig ohne Schließen.
  TRuleAssert.Silent(THandleLeakRule.Create, Prozess(
    '  if not CreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI) then'#10 +
    '    RaiseLastOSError;'#10'  try'#10'    WaitForSingleObject(PI.hProcess, INFINITE);'#10'  finally'#10 +
    '    CloseHandle(PI.hThread);'#10'    CloseHandle(PI.hProcess);'#10'  end;'));
  TRuleAssert.Silent(THandleLeakRule.Create, Datei('  H: THandle;'#10,
    '  H := CreateFile(''a.txt'', GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);'#10 +
    '  if H = INVALID_HANDLE_VALUE then'#10'    Exit;'#10'  ReadFile(H, X, 1, N, nil);'#10'  CloseHandle(H);'));
  // Weitergabe: Ergebnis, Feld, unbekannte Routine, Methode, anonyme Methode.
  TRuleAssert.Silent(THandleLeakRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'function Oeffnen: THandle;'#10'var'#10'  H: THandle;'#10'begin'#10 +
    '  H := CreateEvent(nil, True, False, nil);'#10'  Result := H;'#10'end;'#10'end.');
  TRuleAssert.Silent(THandleLeakRule.Create, Datei('  H: THandle;'#10,
    '  FEreignis := CreateEvent(nil, True, False, nil);'#10'  H := CreateEvent(nil, True, False, nil);'#10 +
    '  Merken(H);'));
  TRuleAssert.Silent(THandleLeakRule.Create, Datei('  H: THandle;'#10,
    '  H := CreateFile(''a.txt'', GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);'#10 +
    '  FStrom := THandleStream.Create(H);'));
  TRuleAssert.Silent(THandleLeakRule.Create, Datei('  H: THandle;'#10,
    '  H := CreateEvent(nil, True, False, nil);'#10'  Liste.Add(H);'));
  TRuleAssert.Silent(THandleLeakRule.Create, Datei('  H: THandle;'#10,
    '  H := CreateEvent(nil, True, False, nil);'#10'  TThread.CreateAnonymousThread(procedure'#10 +
    '    begin'#10'      CloseHandle(H);'#10'    end).Start;'));
  // Funktionszeiger aus GetProcAddress außerhalb der Routine gespeichert: Das Modul bleibt absichtlich geladen.
  TRuleAssert.Silent(THandleLeakRule.Create, Datei('  Lib: HMODULE;'#10,
    '  Lib := LoadLibrary(''x.dll'');'#10'  if Lib = 0 then'#10'    Exit;'#10 +
    '  @GlobalerZeiger := GetProcAddress(Lib, ''Funktion'');'));
  // Nur lokal benutzt: Leck.
  TRuleAssert.Reports(THandleLeakRule.Create, Datei('  Lib: HMODULE;'#10'  P: Pointer;'#10,
    '  Lib := LoadLibrary(''x.dll'');'#10'  P := GetProcAddress(Lib, ''Funktion'');'));
  // Parameter und Felder verfolgt die Regel nicht; Exit(H) gibt weiter.
  TRuleAssert.Silent(THandleLeakRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'function Oeffnen(var H: THandle): THandle;'#10'var'#10'  K: THandle;'#10'begin'#10 +
    '  H := CreateEvent(nil, True, False, nil);'#10'  K := OpenProcess(0, False, 1);'#10'  Exit(K);'#10 +
    'end;'#10'end.');
end;

procedure TFlowRulesTests.HandleLeakPairsAndOff;
const
  Body = '  H := MeinOeffnen(1);'#10'  Benutzen;';
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create, Datei('  H: THandle;'#10, Body),
    '{}', 'U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create, Datei('  H: THandle;'#10, Body),
    '{"rules": {"handle-leak": {"pairs": ["MeinOeffnen>MeinSchliessen"]}}}', 'U.pas'))));
  Assert.AreEqual('H wird nie mit MeinSchliessen geschlossen (Handle-Leck).', TRuleAssert.Findings(
    THandleLeakRule.Create, Datei('  H: THandle;'#10, Body),
    '{"rules": {"handle-leak": {"pairs": [{"open": "MeinOeffnen", "close": "MeinSchliessen"}]}}}',
    'U.pas')[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create, Datei('  H: THandle;'#10,
    Body + #10'  MeinSchliessen(H);'), '{"rules": {"handle-leak": {"pairs": ["MeinOeffnen>MeinSchliessen"]}}}',
    'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create, Prozess(
    '  CreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI);'), '{"rules": {"handle-leak": "off"}}',
    'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create, Prozess(
    '  CreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI);'),
    '{"rules": {"handle-leak": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  // Der Parser nimmt Texte "Öffnen>Schließen" und Objekte an, aber keine Zahlen.
  TConfigurationParser.Parse('{"rules": {"handle-leak": {"pairs": ["A>B", {"open": "C", "close": "D"}]}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  TConfigurationParser.Parse('{"rules": {"handle-leak": {"pairs": [1]}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  TConfigurationParser.Parse('{"rules": {"handle-leak": {"pairs": ["OhnePfeil"]}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowRulesTests);

end.
