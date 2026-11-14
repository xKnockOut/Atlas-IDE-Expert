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
// Argument (RegOpenKeyEx), nicht jeder Weg, Option pairs, stille Muster;
// noreturn-returns (#1132): Beispiel, Exit, Methoden, Ende über raise, Halt
// und andere noreturn-Routinen, unbekannte Aufrufe mit und ohne Index,
// Abschalten.

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
    /// <summary>Ein Aufruf einer noreturn-Routine beendet den Weg wie raise; ohne noreturn meldet die Regel.
    /// </summary>
    [Test]
    procedure NoReturnCallEndsPath;
    [Test]
    procedure FunctionNameAssignmentIsSilent;
    [Test]
    procedure ProcedureIsSilent;
    [Test]
    procedure UninitializedReadReports;
    [Test]
    procedure UninitializedFlagsNestedAndRecords;
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
    /// Kontrollflussgraphen.</summary>
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
    procedure DestructorNotNilSafeGuardsAndQuietClasses;
    [Test]
    procedure HandleLeakIssueExample;
    [Test]
    procedure HandleLeakVariants;
    [Test]
    procedure HandleLeakSilentCases;
    [Test]
    procedure HandleLeakPairsAndOff;
  end;

  [TestFixture]
  TNoreturnReturnsTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure ExitAndMethods;
    [Test]
    procedure EndingPathsAreSilent;
    [Test]
    procedure UnknownCallsUseIndex;
    [Test]
    procedure OffAndExclude;
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
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert;

function Routine(const ABody: string; const AHeader: string;
  const AVars: string): string; overload;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10 + AHeader + #10 + AVars + 'begin'#10 + ABody +
    #10'end;'#10'end.';
end;

function Routine(const ABody: string): string; overload;
begin
  Result := Routine(ABody, 'function F: Integer;', '');
end;

function Routine(const ABody: string; const AHeader: string): string; overload;
begin
  Result := Routine(ABody, AHeader, '');
end;

function FirstOfKind(ANode: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  mIndex: Integer;
begin
  if ANode.Kind = AKind then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := FirstOfKind(ANode[mIndex], AKind);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

procedure TFlowRulesTests.ResultSetOnlyInBranchReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TResultNotSetRule.Create, Routine('  if A then'#10'    Result := 1;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
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

procedure TFlowRulesTests.NoReturnCallEndsPath;
const
  cSource = 'unit U;'#10'interface'#10'procedure Fehler(const AText: string);%s'#10 +
    'function F(A: Integer): Integer;'#10'implementation'#10 +
    'procedure Fehler(const AText: string);'#10'begin'#10'  raise Exception.Create(AText);'#10'end;'#10 +
    'function F(A: Integer): Integer;'#10'begin'#10'  if A > 0 then'#10'    Exit(A);'#10'  Fehler(''x'');'#10 +
    'end;'#10'end.';
begin
  TRuleAssert.Silent(TResultNotSetRule.Create, Format(cSource, [' noreturn;']));
  TRuleAssert.Reports(TResultNotSetRule.Create, Format(cSource, ['']));
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
  // Ein Feld als var- oder out-Argument schreibt einen Teil des Records.
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create,
    Routine('  Lese(E.Wert);'#10'  J := E.Wert;', 'procedure P;', 'var'#10'  E: TEintrag;'#10'  J: Integer;'#10));
end;

procedure TFlowRulesTests.UninitializedFlagsNestedAndRecords;
const
  cVars = 'var'#10'  I, J: Integer;'#10'  Gefunden: Boolean;'#10;
begin
  // Merker (#1109): I bekommt seinen Wert zusammen mit Gefunden := True.
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, Routine('  Gefunden := False;'#10'  for K in L do'#10 +
    '    if K > 0 then'#10'    begin'#10'      I := K;'#10'      Gefunden := True;'#10'    end;'#10 +
    '  if not Gefunden then'#10'    Exit;'#10'  J := I;', 'procedure P;', cVars));
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, Routine('  Gefunden := False;'#10'  if A then'#10 +
    '  begin'#10'    I := 1;'#10'    Gefunden := True;'#10'  end;'#10'  if Gefunden and B then'#10'    J := I;',
    'procedure P;', cVars));
  // Prüfung des Merkers in try … finally.
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, Routine('  try'#10'    Gefunden := False;'#10 +
    '    for K in L do'#10'      if K > 0 then'#10'      begin'#10'        I := K;'#10'        Gefunden := True;'#10 +
    '      end;'#10'    if not Gefunden then'#10'      Exit;'#10'    J := I;'#10'  finally'#10'    Aufraeumen;'#10 +
    '  end;', 'procedure P;', cVars));
  // Merker aus einem Ausdruck, direkt danach "if Gefunden then begin I := …; Break; end".
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, Routine('  Gefunden := False;'#10'  for K in L do'#10 +
    '  begin'#10'    Gefunden := K > 0;'#10'    if Gefunden then'#10'    begin'#10'      I := K;'#10'      Break;'#10 +
    '    end;'#10'  end;'#10'  if Gefunden then'#10'    J := I;', 'procedure P;', cVars));
  TRuleAssert.Reports(TPossiblyUninitializedRule.Create, Routine('  Gefunden := False;'#10'  for K in L do'#10 +
    '  begin'#10'    Gefunden := K > 0;'#10'    if Gefunden and (K > 5) then'#10'    begin'#10'      I := K;'#10 +
    '      Break;'#10'    end;'#10'  end;'#10 +
    '  if Gefunden then'#10'    J := I;', 'procedure P;', cVars));
  // Gefunden wird auch ohne I gesetzt: kein Merker.
  TRuleAssert.Reports(TPossiblyUninitializedRule.Create, Routine('  Gefunden := C;'#10'  if A then'#10 +
    '  begin'#10'    I := 1;'#10'    Gefunden := True;'#10'  end;'#10'  if Gefunden then'#10'    J := I;',
    'procedure P;', cVars));
  // Ohne Prüfung des Merkers bleibt der Befund.
  TRuleAssert.Reports(TPossiblyUninitializedRule.Create, Routine('  Gefunden := False;'#10'  if A then'#10 +
    '  begin'#10'    I := 1;'#10'    Gefunden := True;'#10'  end;'#10'  J := I;', 'procedure P;', cVars));
  // Eine lokale Routine setzt I.
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, Routine('  Setzen;'#10'  J := I;', 'procedure P;',
    cVars + '  procedure Setzen;'#10'  begin'#10'    I := 1;'#10'  end;'#10));
  // Methode eines Records der Unit legt ihn an (Scanner.Init).
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create, 'unit U;'#10'interface'#10'implementation'#10'type'#10 +
    '  TLeser = record'#10'    Pos: Integer;'#10'    procedure Init;'#10'  end;'#10'procedure TLeser.Init;'#10 +
    'begin'#10'  Pos := 0;'#10'end;'#10'procedure P;'#10'var'#10'  L: TLeser;'#10'  J: Integer;'#10'begin'#10 +
    '  L.Init;'#10'  J := L.Pos;'#10'end;'#10'end.');
  TRuleAssert.Reports(TPossiblyUninitializedRule.Create, 'unit U;'#10'interface'#10'implementation'#10'type'#10 +
    '  TLeser = record'#10'    Pos: Integer;'#10'  end;'#10'procedure P;'#10'var'#10'  L: TLeser;'#10 +
    '  J: Integer;'#10'begin'#10'  J := L.Pos;'#10'end;'#10'end.');
end;

procedure TFlowRulesTests.ManagedTypeIsSilent;
begin
  TRuleAssert.Silent(TPossiblyUninitializedRule.Create,
    Routine('  T := S;', 'procedure P;', 'var'#10'  S, T: string;'#10));
end;

procedure TFlowRulesTests.OpaqueUseHelper;
var
  mTree: TSyntaxTree;
  mBlock: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(Routine('  P := @X;', 'procedure P;'));
  try
    // Lokale Routinen überspringt die Prüfung, daher der Rumpf selbst.
    mBlock := FirstOfKind(mTree.Root, TSyntaxKind.Block);
    Assert.IsTrue(HasOpaqueUse(mBlock, 'X'));
    Assert.IsFalse(HasOpaqueUse(mBlock, 'Y'));
  finally
    mTree.Free;
  end;
end;

procedure TFlowRulesTests.UnreachableAfterExitReportsFirstStatement;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Zeile 5 ist Exit; gemeldet wird nur A in Zeile 6, nicht auch B.
  mFindings := TRuleAssert.Findings(TUnreachableCodeRule.Create,
    Routine('  Exit;'#10'  A;'#10'  if X then'#10'    B;', 'procedure P;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(6, mFindings[0].Range.EndPos.Line, 'Nur die erste Zeile markieren');
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
end;

procedure TFlowRulesTests.UnreachableInBranchAndTry;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TUnreachableCodeRule.Create,
    Routine('  if X then'#10'  begin'#10'    raise E;'#10'    A;'#10'  end;'#10'  B;', 'procedure P;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(8, mFindings[0].Range.StartPos.Line);
  // Ein ganzer try-Block hinter Exit zählt als ein Abschnitt.
  mFindings := TRuleAssert.Findings(TUnreachableCodeRule.Create,
    Routine('  Exit;'#10'  try'#10'    A;'#10'  finally'#10'    B;'#10'  end;', 'procedure P;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
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
  cSource =
    'unit U;'#10'interface'#10'implementation'#10 +
    'function F(A: Boolean; Unbenutzt: Integer): Integer;'#10 +
    'begin'#10'  if A then'#10'    Result := 1;'#10'end;'#10 +
    'procedure P;'#10'var'#10'  I, J: Integer;'#10'  K: Integer;'#10'  S: string;'#10 +
    '  procedure Inner;'#10'  var'#10'    X: Integer;'#10'  begin'#10'    Foo(X);'#10'  end;'#10 +
    'begin'#10'  Foo(I);'#10'  K := 1;'#10'  K := 2;'#10'  Foo(K);'#10 +
    '  for S in Liste do'#10'    TThread.Queue(nil, procedure begin Memo1.Lines.Add(S); end);'#10 +
    '  Exit;'#10'  Bar;'#10'end;'#10'end.';
var
  mCount: Integer;
begin
  mCount := TRuleAssert.SameAsSeparateRuns([TResultNotSetRule.Create, TPossiblyUninitializedRule.Create,
    TUnreachableCodeRule.Create, TCapturedLoopVariableRule.Create, TUnusedLocalRule.Create,
    TUnusedParameterRule.Create, TUnusedAssignmentRule.Create], cSource, '{"minConfidence": "low"}');
  Assert.IsTrue(mCount >= 5, 'Treffer mehrerer Regeln: ' + IntToStr(mCount));
end;

const
  cFreeHeader = 'procedure P(A: Boolean; Bericht: TBericht; Protokoll: TStrings; Zeiger: PDaten);';

procedure TFlowRulesTests.UseAfterFreeReportsWithJump;
var
  mFindings: TArray<TRuleFinding>;
  mActions: TArray<TCodeAction>;
  mSource: string;
  mRule: IRule;
  mFound: Boolean;
begin
  mSource := Routine('  Bericht.Free;'#10'  Protokoll.Add(''Seiten: '' + IntToStr(Bericht.Seiten));', cFreeHeader);
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cUseAfterFreeRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Bericht wurde in Zeile 6 freigegeben und wird hier wieder gelesen.', mFindings[0].Message);
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(38, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(45, mFindings[0].Range.EndPos.Character);
  // Keine automatische Korrektur, nur der Sprung zur Freigabe.
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Zur Freigabe in Zeile 6 springen', mFindings[0].Fixes[0].Title);
  Assert.IsTrue(mFindings[0].Fixes[0].HasJump);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes[0].Edits)));
  Assert.AreEqual(5, mFindings[0].Fixes[0].JumpTo.Line);
  Assert.AreEqual(2, mFindings[0].Fixes[0].JumpTo.Character);
  mActions := TRuleCodeActions.ForFindings(mFindings, mSource, mFindings[0].Range);
  Assert.AreEqual('Zur Freigabe in Zeile 6 springen', mActions[0].Title);
  Assert.AreEqual(cGoToPositionCommand, mActions[0].Command);
  Assert.AreEqual(2, Integer(Length(mActions[0].CommandArguments)));
  Assert.AreEqual('5', mActions[0].CommandArguments[0]);
  Assert.AreEqual('2', mActions[0].CommandArguments[1]);
  Assert.AreEqual(cRuleFixTag, mActions[0].Tag);
  Assert.AreEqual(0, Integer(Length(mActions[0].Edits)));
  // Gewöhnliche Korrekturen behalten keinen Befehl.
  Assert.AreEqual('', mActions[1].Command);
  mFound := False;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cUseAfterFreeRuleId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound, cUseAfterFreeRuleId);
end;

procedure TFlowRulesTests.UseAfterFreeAndNilAndConfidence;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create,
    Routine('  FreeAndNil(Bericht);'#10'  Bericht.Drucken;'#10'  Bericht.Free;', cFreeHeader));
  Assert.AreEqual(1, Integer(Length(mFindings)), 'Free nach FreeAndNil ist harmlos');
  Assert.AreEqual('Bericht wurde in Zeile 6 mit FreeAndNil freigegeben und ist hier nil.', mFindings[0].Message);
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Line);
  // Freigabe nur in einem Zweig: mittlere Konfidenz.
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create,
    Routine('  if A then'#10'    Bericht.Free;'#10'  Bericht.Drucken;', cFreeHeader), '{"minConfidence": "low"}',
    'U.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
  // Self.FFeld zählt wie FFeld.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUseAfterFreeRule.Create,
    Routine('  Self.Bericht.Free;'#10'  Bericht.Drucken;', cFreeHeader)))));
end;

procedure TFlowRulesTests.DoubleFreeAndDispose;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create,
    Routine('  Bericht.Free;'#10'  if Assigned(Bericht) then'#10'    Bericht.Free;', cFreeHeader));
  Assert.AreEqual(2, Integer(Length(mFindings)), 'Assigned nach Free ist immer True, das zweite Free gibt doppelt frei');
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(7, mFindings[1].Range.StartPos.Line);
  mFindings := TRuleAssert.Findings(TUseAfterFreeRule.Create,
    Routine('  Dispose(Zeiger);'#10'  Zeiger^.Wert := 1;', cFreeHeader));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Zeiger wurde in Zeile 6 freigegeben und wird hier wieder gelesen.', mFindings[0].Message);
  // Freigabe in der Schleife ohne neue Zuweisung: der zweite Durchlauf gibt doppelt frei.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUseAfterFreeRule.Create,
    Routine('  while A do'#10'    Bericht.Free;', cFreeHeader), '{"minConfidence": "low"}', 'U.pas'))));
end;

procedure TFlowRulesTests.SafeUsesAfterFreeAreSilent;
begin
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine(
    // Neue Zuweisung.
    '  Bericht.Free;'#10'  Bericht := TBericht.Create;'#10'  Bericht.Drucken;'#10 +
    '  Bericht.Free;'#10'  Bericht := nil;'#10'  if Bericht = nil then'#10'    Exit;'#10, cFreeHeader));
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine(
    // Nach FreeAndNil abgefragt.
    '  FreeAndNil(Bericht);'#10'  if Assigned(Bericht) then'#10'    Bericht.Drucken;'#10 +
    '  if Bericht <> nil then'#10'    Bericht.Drucken;', cFreeHeader));
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine(
    // Übergabe: nur der Zeigerwert (Liste.Remove) oder neu gesetzt (var-Parameter).
    '  Bericht.Free;'#10'  Liste.Remove(Bericht);'#10'  Bericht.Drucken;', cFreeHeader));
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine(
    // try/finally und Schleife mit neuer Zuweisung je Durchlauf.
    '  while A do'#10'  begin'#10'    Bericht := TBericht.Create;'#10'    try'#10'      Bericht.Drucken;'#10 +
    '    finally'#10'      Bericht.Free;'#10'    end;'#10'  end;'#10 +
    '  Protokoll.Free;'#10'  Bericht := nil;'#10'  Protokoll := TStringList.Create;'#10'  Protokoll.Clear;',
    cFreeHeader));
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine(
    // Im try neu gesetzt; der Weg über eine Ausnahme dazwischen bleibt aus.
    '  Bericht := TBericht.Create;'#10'  try'#10'    Bericht.Free;'#10'    Bericht := TBericht.Create;'#10 +
    '    Bericht.Drucken;'#10'  finally'#10'    Bericht.Free;'#10'  end;', cFreeHeader));
  TRuleAssert.Silent(TUseAfterFreeRule.Create, Routine(
    // Freigabe nur auf einem Weg, der nicht zum Zugriff führt.
    '  if A then'#10'  begin'#10'    Bericht.Free;'#10'    Exit;'#10'  end;'#10'  Bericht.Drucken;', cFreeHeader));
end;

procedure TFlowRulesTests.UseAfterFreeOffAndExclude;
var
  mSource: string;
begin
  mSource := Routine('  Bericht.Free;'#10'  Bericht.Drucken;', cFreeHeader);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUseAfterFreeRule.Create, mSource,
    '{"rules": {"use-after-free": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TUseAfterFreeRule.Create, mSource,
    '{"rules": {"use-after-free": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TUseAfterFreeRule.Create, mSource,
    '{"rules": {"use-after-free": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

const
  cCheckHeader = 'procedure P(Kunde, Knoten: TKunde);';
  cCheckVars = 'var'#10'  Titel: string;'#10;

procedure TFlowRulesTests.DerefBeforeNilCheckReportsWithFix;
const
  cBody = '  Titel := Kunde.Name;'#10'  if Assigned(Kunde) then'#10'    Anzeigen(Kunde);';
  cFixed = '  if Assigned(Kunde) then'#10'  begin'#10'    Titel := Kunde.Name;'#10'    Anzeigen(Kunde);'#10'  end;';
var
  mFindings: TArray<TRuleFinding>;
  mText: string;
  mTree: TSyntaxTree;
  mRule: IRule;
  mFound: Boolean;
begin
  mFindings := TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Routine(cBody, cCheckHeader, cCheckVars));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cDerefBeforeNilCheckRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Kunde wird hier benutzt, aber erst in Zeile 9 auf nil geprüft.', mFindings[0].Message);
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(11, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Prüfung vor den Zugriff ziehen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  mText := TChangeSignature.ApplyEdits(Routine(cBody, cCheckHeader, cCheckVars), mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(Routine(cFixed, cCheckHeader, cCheckVars), mText);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), 'Ergebnis parst fehlerfrei');
  finally
    mTree.Free;
  end;
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, mText);
  mFound := False;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cDerefBeforeNilCheckRuleId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound, cDerefBeforeNilCheckRuleId);
end;

procedure TFlowRulesTests.DerefBeforeNilCheckBlockAndElse;
const
  cBody = '  Kunde.Laden;'#10'  if Kunde <> nil then'#10'  begin'#10'    Anzeigen(Kunde);'#10'    Titel := '''';'#10 +
    '  end;';
  cFixed = '  if Kunde <> nil then'#10'  begin'#10'    Kunde.Laden;'#10'    Anzeigen(Kunde);'#10'    Titel := '''';'#10 +
    '  end;';
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Routine(cBody, cCheckHeader, cCheckVars));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Routine(cFixed, cCheckHeader, cCheckVars),
    TChangeSignature.ApplyEdits(Routine(cBody, cCheckHeader, cCheckVars), mFindings[0].Fixes[0].Edits));
  // Mit else oder nicht direkt danach: Meldung ohne Korrektur.
  mFindings := TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Routine('  Titel := Kunde.Name;'#10 +
    '  if Kunde = nil then'#10'    Titel := '''''#10'  else'#10'    Anzeigen(Kunde);', cCheckHeader, cCheckVars));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  mFindings := TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Routine('  Titel := Kunde.Name;'#10 +
    '  Anzeigen(Titel);'#10'  if Assigned(Kunde) then'#10'    Anzeigen(Kunde);', cCheckHeader, cCheckVars));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Kunde wird hier benutzt, aber erst in Zeile 10 auf nil geprüft.', mFindings[0].Message);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TFlowRulesTests.DerefBeforeNilCheckSilentCases;
begin
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // Schon vorher geprüft.
    '  if Kunde = nil then'#10'    Exit;'#10'  Titel := Kunde.Name;'#10'  if Assigned(Kunde) then'#10 +
    '    Anzeigen(Kunde);', cCheckHeader, cCheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // Dazwischen neu gesetzt bzw. X := X.Next.
    '  Titel := Kunde.Name;'#10'  Kunde := Suchen(Titel);'#10'  if Assigned(Kunde) then'#10'    Anzeigen(Kunde);'#10 +
    '  Knoten := Knoten.Weiter;'#10'  if Knoten <> nil then'#10'    Anzeigen(Knoten);', cCheckHeader, cCheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // Prüfung im selben Ausdruck vor dem Zugriff, Schleife über eine Kette.
    '  if Assigned(Kunde) and Kunde.Aktiv then'#10'    Anzeigen(Kunde);'#10 +
    '  while Knoten <> nil do'#10'  begin'#10'    Knoten.Pruefen;'#10'    Knoten := Knoten.Weiter;'#10'  end;',
    cCheckHeader, cCheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // X is T im selben Ausdruck schützt wie Assigned; der else-Zweig prüft danach auf nil.
    '  if (Kunde is TKunde) and Kunde.Aktiv then'#10'    Anzeigen(Kunde)'#10'  else if Kunde <> nil then'#10 +
    '    Melden;', cCheckHeader, cCheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // Übergabe dazwischen: die Routine kann den Wert ändern.
    '  Titel := Kunde.Name;'#10'  Ersetzen(Kunde);'#10'  if Assigned(Kunde) then'#10'    Anzeigen(Kunde);',
    cCheckHeader, cCheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // Supports setzt Kunde im selben Ausdruck; Zugriff nur in einem Zweig, die Prüfung gilt dem anderen.
    '  if Supports(Quelle, IKunde, Kunde) and Kunde.Aktiv then'#10'    Titel := '''';'#10 +
    '  if A then'#10'  begin'#10'    Kunde := TKunde.Create;'#10'    Kunde.Laden;'#10'  end;'#10 +
    '  if Kunde <> nil then'#10'    Anzeigen(Kunde);', 'procedure P(A: Boolean; Kunde: TKunde);', cCheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // while als Prüfung späterer Durchläufe.
    '  Titel := Knoten.Name;'#10'  while Knoten <> nil do'#10'    Knoten := Knoten.Parent;', cCheckHeader, cCheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // Ein Zweig setzt Knoten neu (FindChild kann nil liefern); die Prüfung gilt diesem Wert (#1109).
    '  if Knoten.Kind = 1 then'#10'    Knoten := Knoten.FindChild(2);'#10'  if Knoten = nil then'#10'    Exit;',
    cCheckHeader, cCheckVars));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    // FreeAndNil im except-Zweig setzt Kunde auf nil; die Prüfung danach gilt diesem Weg (TWICImage laden).
    '  try'#10'    Kunde.Laden;'#10'  except'#10'    on Exception do'#10'      FreeAndNil(Kunde);'#10'  end;'#10 +
    '  if Kunde <> nil then'#10'    Anzeigen(Kunde);', cCheckHeader, cCheckVars));
end;

procedure TFlowRulesTests.DerefBeforeNilCheckFieldsAndOff;
var
  mSource: string;
begin
  // Feld ohne Aufruf dazwischen: gemeldet; mit Aufruf (kann das Feld ändern): still.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, Routine(
    '  Titel := FKunde.Name;'#10'  if Assigned(FKunde) then'#10'    Titel := '''';', cCheckHeader, cCheckVars)))));
  TRuleAssert.Silent(TDerefBeforeNilCheckRule.Create, Routine(
    '  Titel := FKunde.Name;'#10'  Laden;'#10'  if Assigned(FKunde) then'#10'    Titel := '''';', cCheckHeader,
    cCheckVars));
  mSource := Routine('  Titel := Kunde.Name;'#10'  if Assigned(Kunde) then'#10'    Anzeigen(Kunde);', cCheckHeader,
    cCheckVars);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, mSource,
    '{"rules": {"deref-before-nil-check": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, mSource,
    '{"rules": {"deref-before-nil-check": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TDerefBeforeNilCheckRule.Create, mSource,
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
  cBody = 'procedure TImport.Zuruecksetzen;'#10'begin'#10'  FCache.Free;'#10'end;'#10;
  cFixed = 'procedure TImport.Zuruecksetzen;'#10'begin'#10'  FreeAndNil(FCache);'#10'end;'#10;
var
  mFindings: TArray<TRuleFinding>;
  mText: string;
  mTree: TSyntaxTree;
  mRule: IRule;
  mFound: Boolean;
begin
  mFindings := TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(cBody));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cFieldFreeWithoutNilRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('FCache bleibt nach Free gesetzt; ein späterer Zugriff trifft freigegebenen Speicher.',
    mFindings[0].Message);
  Assert.AreEqual(15, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual('FreeAndNil(FCache)', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  mText := TChangeSignature.ApplyEdits(ClassUnit(cBody), mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(ClassUnit(cFixed), mText);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), 'Ergebnis parst fehlerfrei');
  finally
    mTree.Free;
  end;
  TRuleAssert.Silent(TFieldFreeWithoutNilRule.Create, mText);
  // Nur in einem Zweig, Self.FFeld und Free().
  Assert.AreEqual(2, Integer(Length(TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(
    'procedure TImport.Zuruecksetzen;'#10'begin'#10'  if FListe = nil then'#10'    Self.FCache.Free'#10 +
    '  else'#10'    FCache := nil;'#10'  FListe.Free();'#10'end;'#10)))));
  // Generische Klasse.
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TStapel<T> = class'#10'  private'#10'    FElemente: TList<T>;'#10 +
    '    procedure Leeren;'#10'  end;'#10'implementation'#10 +
    'procedure TStapel<T>.Leeren;'#10'begin'#10'  FElemente.Free;'#10'end;'#10'end.'))));
  mFound := False;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cFieldFreeWithoutNilRuleId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound, cFieldFreeWithoutNilRuleId);
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
  cBody = 'procedure TImport.BeforeDestruction;'#10'begin'#10'  FCache.Free;'#10'end;'#10 +
    'procedure TImport.Zuruecksetzen;'#10'begin'#10'  FListe.Free;'#10'end;'#10;
var
  mFindings: TArray<TRuleFinding>;
  mIssues: TArray<TConfigurationIssue>;
begin
  mFindings := TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(cBody));
  Assert.AreEqual(1, Integer(Length(mFindings)), 'Vorgabe: BeforeDestruction ausgenommen');
  Assert.AreEqual('FListe bleibt nach Free gesetzt; ein späterer Zugriff trifft freigegebenen Speicher.',
    mFindings[0].Message);
  mFindings := TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(cBody),
    '{"rules": {"field-free-without-nil": {"ignoreMethods": ["Zuruecksetzen"]}}}', 'U.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)), 'Option ersetzt die Vorgabe');
  Assert.AreEqual('FCache bleibt nach Free gesetzt; ein späterer Zugriff trifft freigegebenen Speicher.',
    mFindings[0].Message);
  Assert.AreEqual(2, Integer(Length(TFieldFreeWithoutNilRule.DefaultIgnoreMethods)));
  TConfigurationParser.Parse('{"rules": {"field-free-without-nil": {"ignoreMethods": "Destroy"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('"ignoreMethods" muss eine Liste von Texten sein', mIssues[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(cBody),
    '{"rules": {"field-free-without-nil": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(cBody),
    '{"rules": {"field-free-without-nil": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TFieldFreeWithoutNilRule.Create, ClassUnit(cBody),
    '{"rules": {"field-free-without-nil": {"exclude": ["Alt/*.pas"]}}}', 'Neu/U.pas'))));
end;

const
  cAnhaengen = 'unit U;'#10'interface'#10'procedure Anhaengen(out Text: string);'#10'implementation'#10 +
    'procedure Anhaengen(out Text: string);'#10'begin'#10'  Text := Text + sLineBreak + ''Ende'';'#10'end;'#10'end.';

procedure TFlowRulesTests.OutParamReadIssueExample;
var
  mFindings: TArray<TRuleFinding>;
  mFixed: string;
begin
  mFindings := TRuleAssert.Findings(TOutParamReadRule.Create, cAnhaengen);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('out-Parameter Text wird gelesen, bevor er gesetzt ist; bei string ist er hier immer leer.',
    mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(10, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual('out durch var ersetzen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(2, Integer(Length(mFindings[0].Fixes[0].Edits)), 'Deklaration und Implementierung');
  mFixed := TChangeSignature.ApplyEdits(cAnhaengen, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(StringReplace(cAnhaengen, '(out Text', '(var Text', [rfReplaceAll]), mFixed);
  TRuleAssert.Silent(TOutParamReadRule.Create, mFixed);
end;

procedure TFlowRulesTests.OutParamReadMethodAndInteger;
const
  cSource = 'unit U;'#10'interface'#10'type'#10'  TZaehler = class'#10'    procedure Weiter(out N: Integer);'#10 +
    '  end;'#10'  TAnderer = class'#10'    procedure Weiter(out N: Integer);'#10'  end;'#10'implementation'#10 +
    'procedure TZaehler.Weiter(out N: Integer);'#10'begin'#10'  if N > 0 then'#10'    N := 0;'#10'end;'#10 +
    'procedure TAnderer.Weiter(out N: Integer);'#10'begin'#10'  N := 1;'#10'end;'#10'end.';
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TOutParamReadRule.Create, cSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('out-Parameter N wird gelesen, bevor er gesetzt ist; sein Wert ist hier undefiniert.',
    mFindings[0].Message);
  // Nur die Deklaration in TZaehler, nicht die gleichnamige in TAnderer.
  Assert.AreEqual(2, Integer(Length(mFindings[0].Fixes[0].Edits)));
  Assert.AreEqual(4, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(10, mFindings[0].Fixes[0].Edits[1].Range.StartPos.Line);
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
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOutParamReadRule.Create, cAnhaengen,
    '{"rules": {"out-param-read": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOutParamReadRule.Create, cAnhaengen,
    '{"rules": {"out-param-read": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TOutParamReadRule.Create, cAnhaengen,
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
  cImportCreate = '  inherited Create;'#10'  FStrom := TFileStream.Create(Datei, fmOpenRead);'#10 +
    '  FZeilen := TStringList.Create;';

procedure TFlowRulesTests.DestructorNotNilSafeIssueExample;
const
  cDestroy = '  FZeilen.Clear;'#10'  FZeilen.Free;'#10'  FStrom.Free;'#10'  inherited;';
  cFixed = '  if Assigned(FZeilen) then'#10'    FZeilen.Clear;'#10'  FZeilen.Free;'#10'  FStrom.Free;'#10'  inherited;';
var
  mFindings: TArray<TRuleFinding>;
  mText: string;
  mTree: TSyntaxTree;
  mRule: IRule;
  mFound: Boolean;
begin
  mFindings := TRuleAssert.Findings(TDestructorNotNilSafeRule.Create, ImportUnit(cImportCreate, cDestroy));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cDestructorNotNilSafeRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('Wirft TFileStream.Create, ist FZeilen beim Destruktor noch nil; FZeilen.Clear stürzt ab und ' +
    'verdeckt die eigentliche Exception.', mFindings[0].Message);
  Assert.AreEqual(21, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('In if Assigned(FZeilen) then einschließen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  mText := TChangeSignature.ApplyEdits(ImportUnit(cImportCreate, cDestroy), mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(ImportUnit(cImportCreate, cFixed), mText);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), 'Ergebnis parst fehlerfrei');
  finally
    mTree.Free;
  end;
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, mText);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDestructorNotNilSafeRule.Create,
    ImportUnit(cImportCreate, cDestroy), '{"rules": {"destructor-not-nil-safe": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDestructorNotNilSafeRule.Create,
    ImportUnit(cImportCreate, cDestroy), '{"rules": {"destructor-not-nil-safe": {"exclude": ["Alt/*.pas"]}}}',
    'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TDestructorNotNilSafeRule.Create,
    ImportUnit(cImportCreate, cDestroy), '{"rules": {"destructor-not-nil-safe": {"exclude": ["Alt/*.pas"]}}}',
    'Neu/U.pas'))));
  mFound := False;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cDestructorNotNilSafeRuleId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound, cDestructorNotNilSafeRuleId);
end;

procedure TFlowRulesTests.DestructorNotNilSafeVariants;
var
  mFindings: TArray<TRuleFinding>;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Nur bedingt angelegt: auch ohne Aufruf davor; Zugriff über Self, Property und Index.
  mFindings := TRuleAssert.Findings(TDestructorNotNilSafeRule.Create, ImportUnit(
    '  inherited Create;'#10'  if Datei <> '''' then'#10'    FZeilen := TStringList.Create;',
    '  if Self.FZeilen.Count > 0 then'#10'    Speichern;'#10'  FZeilen.Free;'#10'  inherited;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('FZeilen wird im Konstruktor nur bedingt angelegt und kann beim Destruktor nil sein; ' +
    'Self.FZeilen.Count stürzt dann ab.', mFindings[0].Message);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)), 'if über mehrere Zeilen: keine Korrektur');
  // Ein Aufruf ohne Klammern vor dem Anlegen; Zugriff in einer Hilfsmethode, die nur der Destruktor aufruft.
  mFindings := TRuleAssert.Findings(TDestructorNotNilSafeRule.Create, ImportUnit(
    '  inherited Create;'#10'  Pruefen;'#10'  FZeilen := TStringList.Create;',
    '  Leeren;'#10'  FZeilen.Free;'#10'  inherited;',
    'procedure TImport.Leeren;'#10'begin'#10'  FZeilen[0] := '''';'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Wirft Pruefen, ist FZeilen beim Destruktor noch nil; FZeilen[0] stürzt ab und verdeckt die ' +
    'eigentliche Exception.', mFindings[0].Message);
  Assert.AreEqual(27, mFindings[0].Range.StartPos.Line);
  // onlyAfterRaisingCode aus: auch das erste angelegte Feld.
  mFindings := TRuleAssert.Findings(TDestructorNotNilSafeRule.Create, ImportUnit(cImportCreate,
    '  FStrom.Position := 0;'#10'  FStrom.Free;'#10'  inherited;'),
    '{"rules": {"destructor-not-nil-safe": {"onlyAfterRaisingCode": false}}}', 'U.pas');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Wirft TFileStream.Create, ist FStrom beim Destruktor noch nil; FStrom.Position stürzt ab und ' +
    'verdeckt die eigentliche Exception.', mFindings[0].Message);
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(cImportCreate,
    '  FStrom.Position := 0;'#10'  FStrom.Free;'#10'  inherited;'));
  // Der Parser prüft die Option als Wahrheitswert.
  TConfigurationParser.Parse('{"rules": {"destructor-not-nil-safe": {"onlyAfterRaisingCode": "ja"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  TConfigurationParser.Parse('{"rules": {"destructor-not-nil-safe": {"onlyAfterRaisingCode": false}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  // Je Anweisung ein Befund, damit jede Korrektur ihre Anweisung schützt.
  TRuleAssert.Reports(TDestructorNotNilSafeRule.Create, ImportUnit(cImportCreate,
    '  FZeilen.Clear;'#10'  FZeilen.Sorted := False;'#10'  FZeilen.Free;'#10'  inherited;'), 2);
  // TObjectList<T>.Create(True) wirft höchstens EOutOfMemory; ein Konstruktor mit Datei davor schon.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(
    '  FStrom := TObjectList<TObject>.Create(True);'#10'  FZeilen := TStringList.Create;',
    '  FZeilen.Clear;'#10'  inherited;'));
  // Destroy ist nicht nil-sicher; DisposeOf schon.
  TRuleAssert.Reports(TDestructorNotNilSafeRule.Create, ImportUnit(cImportCreate,
    '  FZeilen.Destroy;'#10'  FStrom.DisposeOf;'#10'  inherited;'));
end;

procedure TFlowRulesTests.DestructorNotNilSafeSilentCases;
begin
  // Free, FreeAndNil, Assigned, <> nil, = nil mit Exit.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(cImportCreate,
    '  FreeAndNil(FZeilen);'#10'  FStrom.Free;'#10'  inherited;'));
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(cImportCreate,
    '  if Assigned(FZeilen) and (FZeilen.Count > 0) then'#10'    FZeilen.Clear;'#10'  FZeilen.Free;'#10 +
    '  inherited;'));
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(cImportCreate,
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
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(cImportCreate,
    '  Leeren;'#10'  inherited;',
    'procedure TImport.BeforeDestruction;'#10'begin'#10'  FZeilen.SaveToFile(''x'');'#10'end;'#10 +
    'procedure TImport.Leeren;'#10'begin'#10'  FZeilen.Clear;'#10'end;'#10 +
    'procedure TImport.Neu;'#10'begin'#10'  Leeren;'#10'end;'#10));
  // Im Destruktor neu gesetzt; Feld nicht im Konstruktor angelegt; Klasse ohne Konstruktor.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit(cImportCreate,
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

function GuardUnit(const AFirst, ASecond, ADestructor: string): string;
begin
  Result := ImportUnit('  inherited Create;'#10'  Pruefen;'#10 + AFirst + #10 + ASecond, ADestructor);
end;

function LocalClassUnit(const AHelper, AConstructor: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10 + AHelper + '  TA = class'#10'    FH: THelfer;'#10 +
    '    FL: TObject;'#10'    constructor Create;'#10'    destructor Destroy; override;'#10'  end;'#10 +
    'implementation'#10 + AConstructor + 'constructor TA.Create;'#10'begin'#10'  FH := THelfer.Create;'#10 +
    '  FL := TFoo.Create;'#10'end;'#10'destructor TA.Destroy;'#10'begin'#10'  FL.Clear;'#10'end;'#10'end.';
end;

procedure TFlowRulesTests.DestructorNotNilSafeGuardsAndQuietClasses;
begin
  // Wächterfeld (#1109): FStrom wird erst nach FZeilen gesetzt; ist FStrom nicht nil, ist FZeilen es auch.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, GuardUnit('  FZeilen := TStringList.Create;',
    '  FStrom := TFileStream.Create(Datei, fmOpenRead);', '  if FStrom <> nil then'#10'    FZeilen.Clear;'#10 +
    '  inherited;'));
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, GuardUnit('  FZeilen := TStringList.Create;',
    '  FStrom := TFileStream.Create(Datei, fmOpenRead);', '  if Assigned(FStrom) then'#10'  begin'#10 +
    '    FZeilen.Clear;'#10'    FZeilen.Sorted := False;'#10'  end;'#10'  inherited;'));
  // Umgekehrte Reihenfolge: FStrom sagt nichts über FZeilen.
  TRuleAssert.Reports(TDestructorNotNilSafeRule.Create, GuardUnit('  FStrom := TFileStream.Create(Datei, fmOpenRead);',
    '  FZeilen := TStringList.Create;', '  if FStrom <> nil then'#10'    FZeilen.Clear;'#10'  inherited;'));
  // Nur bedingt vor dem Wächter angelegt: kein Schluss.
  TRuleAssert.Reports(TDestructorNotNilSafeRule.Create, GuardUnit('  if Datei <> '''' then'#10 +
    '    FZeilen := TStringList.Create;', '  FStrom := TFileStream.Create(Datei, fmOpenRead);',
    '  if FStrom <> nil then'#10'    FZeilen.Clear;'#10'  inherited;'));
  // Klasse der Unit ohne werfenden Konstruktor wirft höchstens EOutOfMemory, wie TStringList.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, LocalClassUnit('  THelfer = class'#10'  end;'#10, ''));
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, LocalClassUnit('  THelfer = class(TStringList)'#10 +
    '    constructor Create;'#10'  end;'#10, 'constructor THelfer.Create;'#10'begin'#10'  inherited Create;'#10 +
    '  Sorted := True;'#10'end;'#10));
  // Werfender Konstruktor oder unbekannter Vorfahr: zählt als werfend.
  TRuleAssert.Reports(TDestructorNotNilSafeRule.Create, LocalClassUnit('  THelfer = class'#10 +
    '    constructor Create;'#10'  end;'#10, 'constructor THelfer.Create;'#10'begin'#10 +
    '  LoadFromFile(''x'');'#10'end;'#10));
  TRuleAssert.Reports(TDestructorNotNilSafeRule.Create, LocalClassUnit('  THelfer = class(TFremd)'#10'  end;'#10,
    ''));
  // Kurzschluss: "(FZeilen <> nil) and FZeilen.Sorted" schützt den rechten Teil.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, GuardUnit('  FStrom := TFileStream.Create(Datei, fmOpenRead);',
    '  FZeilen := TStringList.Create;', '  FOk := (FZeilen <> nil) and FZeilen.Sorted;'#10'  inherited;'));
  TRuleAssert.Reports(TDestructorNotNilSafeRule.Create, GuardUnit('  FStrom := TFileStream.Create(Datei, fmOpenRead);',
    '  FZeilen := TStringList.Create;', '  FOk := (FZeilen = nil) and FZeilen.Sorted;'#10'  inherited;'));
  // Grafikobjekte der VCL legen ihr Handle erst bei Bedarf an.
  TRuleAssert.Silent(TDestructorNotNilSafeRule.Create, ImportUnit('  inherited Create;'#10 +
    '  FStrom := TFont.Create;'#10'  FZeilen := TStringList.Create;', '  FZeilen.Clear;'#10'  inherited;'));
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
  cBody = '  CreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI);'#10 +
    '  WaitForSingleObject(PI.hProcess, INFINITE);';
  cFixed = '  CreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI);'#10'  try'#10 +
    '    WaitForSingleObject(PI.hProcess, INFINITE);'#10'  finally'#10'    CloseHandle(PI.hThread);'#10 +
    '    CloseHandle(PI.hProcess);'#10'  end;';
var
  mFindings: TArray<TRuleFinding>;
  mText: string;
  mTree: TSyntaxTree;
  mRule: IRule;
  mFound: Boolean;
begin
  mFindings := TRuleAssert.Findings(THandleLeakRule.Create, Prozess(cBody));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(cHandleLeakRuleId, mFindings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual('PI.hProcess und PI.hThread werden nie mit CloseHandle geschlossen (Handle-Leck).',
    mFindings[0].Message);
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('In try … finally CloseHandle einschließen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes[0].Edits)), 'ein Undo-Schritt');
  mText := TChangeSignature.ApplyEdits(Prozess(cBody), mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(Prozess(cFixed), mText);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), 'Ergebnis parst fehlerfrei');
  finally
    mTree.Free;
  end;
  TRuleAssert.Silent(THandleLeakRule.Create, mText);
  mFound := False;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cHandleLeakRuleId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound, cHandleLeakRuleId);
end;

procedure TFlowRulesTests.HandleLeakVariants;
var
  mFindings: TArray<TRuleFinding>;
  mText: string;
begin
  // Nach der Prüfung auf INVALID_HANDLE_VALUE, auf einem Weg mit Exit nicht geschlossen.
  mFindings := TRuleAssert.Findings(THandleLeakRule.Create, Datei('  H: THandle;'#10,
    '  H := CreateFileW(''a.txt'', GENERIC_READ, 0, nil, OPEN_EXISTING, 0, 0);'#10 +
    '  if H = INVALID_HANDLE_VALUE then'#10'    RaiseLastOSError;'#10'  if Fehler then'#10'    Exit;'#10 +
    '  CloseHandle(H);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('H wird nicht auf jedem Weg mit CloseHandle geschlossen (Handle-Leck).', mFindings[0].Message);
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)), 'nur ohne jedes Schließen eine Korrektur');
  // out-Argument von RegOpenKeyEx im Zweig "gelungen".
  mFindings := TRuleAssert.Findings(THandleLeakRule.Create, Datei('  Key: HKEY;'#10,
    '  if RegOpenKeyEx(HKEY_CURRENT_USER, ''Software\Atlas'', 0, KEY_READ, Key) = ERROR_SUCCESS then'#10 +
    '    RegQueryValueEx(Key, ''Pfad'', nil, nil, nil, nil);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Key wird nie mit RegCloseKey geschlossen (Handle-Leck).', mFindings[0].Message);
  // GetDC: das Gegenstück bekommt das Fenster; letzte Anweisung im Block: nur anhängen.
  mFindings := TRuleAssert.Findings(THandleLeakRule.Create, Datei('  DC: HDC;'#10,
    '  DC := GetDC(Wnd);'#10'  TextOut(DC, 0, 0, ''x'', 1);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  mText := TChangeSignature.ApplyEdits(Datei('  DC: HDC;'#10, '  DC := GetDC(Wnd);'#10'  TextOut(DC, 0, 0, ''x'', 1);'),
    mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(Datei('  DC: HDC;'#10, '  DC := GetDC(Wnd);'#10'  try'#10'    TextOut(DC, 0, 0, ''x'', 1);'#10 +
    '  finally'#10'    ReleaseDC(Wnd, DC);'#10'  end;'), mText);
  mFindings := TRuleAssert.Findings(THandleLeakRule.Create, Datei('  Lib: HMODULE;'#10,
    '  Lib := LoadLibrary(''x.dll'');'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('FreeLibrary ergänzen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(Datei('  Lib: HMODULE;'#10, '  Lib := LoadLibrary(''x.dll'');'#10'  FreeLibrary(Lib);'),
    TChangeSignature.ApplyEdits(Datei('  Lib: HMODULE;'#10, '  Lib := LoadLibrary(''x.dll'');'),
    mFindings[0].Fixes[0].Edits));
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
  // Im Array gespeichert (Handles := Handles + [H]): Weitergabe.
  TRuleAssert.Silent(THandleLeakRule.Create, Datei('  H: THandle;'#10'  Handles: TArray<THandle>;'#10,
    '  H := FindFirstChangeNotification(''c:\'', False, 0);'#10'  Handles := Handles + [H];'));
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
  cBody = '  H := MeinOeffnen(1);'#10'  Benutzen;';
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create, Datei('  H: THandle;'#10, cBody),
    '{}', 'U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create, Datei('  H: THandle;'#10, cBody),
    '{"rules": {"handle-leak": {"pairs": ["MeinOeffnen>MeinSchliessen"]}}}', 'U.pas'))));
  Assert.AreEqual('H wird nie mit MeinSchliessen geschlossen (Handle-Leck).', TRuleAssert.Findings(
    THandleLeakRule.Create, Datei('  H: THandle;'#10, cBody),
    '{"rules": {"handle-leak": {"pairs": [{"open": "MeinOeffnen", "close": "MeinSchliessen"}]}}}',
    'U.pas')[0].Message);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create, Datei('  H: THandle;'#10,
    cBody + #10'  MeinSchliessen(H);'), '{"rules": {"handle-leak": {"pairs": ["MeinOeffnen>MeinSchliessen"]}}}',
    'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create, Prozess(
    '  CreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI);'), '{"rules": {"handle-leak": "off"}}',
    'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(THandleLeakRule.Create, Prozess(
    '  CreateProcess(nil, PChar(Befehl), nil, nil, False, 0, nil, nil, SI, PI);'),
    '{"rules": {"handle-leak": {"exclude": ["Alt/*.pas"]}}}', 'Alt/U.pas'))));
  // Der Parser nimmt Texte "Öffnen>Schließen" und Objekte an, aber keine Zahlen.
  TConfigurationParser.Parse('{"rules": {"handle-leak": {"pairs": ["A>B", {"open": "C", "close": "D"}]}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  TConfigurationParser.Parse('{"rules": {"handle-leak": {"pairs": [1]}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  TConfigurationParser.Parse('{"rules": {"handle-leak": {"pairs": ["OhnePfeil"]}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;

{ TNoreturnReturnsTests }

/// <summary>Unit mit der noreturn-Deklaration im interface und dem Rumpf ABody der Implementierung.</summary>
function Abbruch(const ABody: string): string;
begin
  Result := 'unit Import;'#10'interface'#10'procedure Fehler(const AText: string); noreturn;'#10 +
    'procedure Melden(const AText: string);'#10'implementation'#10 +
    'procedure Melden(const AText: string);'#10'begin'#10'end;'#10 +
    'procedure Fehler(const AText: string);'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

function NoreturnFindings(const ASource: string; const AConfig: string; const APath: string):
  TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TNoreturnReturnsRule.Create, ASource, AConfig, APath);
end;

function NoreturnFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := NoreturnFindings(ASource, '', '');
end;

function NoreturnFindings(const ASource: string; const AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := NoreturnFindings(ASource, AConfig, '');
end;

function IndexWith(const ASource: string): ISymbolIndex;
var
  mTree: TSyntaxTree;
begin
  Result := TSymbolIndex.Create;
  mTree := TPascalParser.Parse(ASource);
  try
    Result.AddUnit(TIndexExtractor.Extract(mTree, 'C:\Quellen\Werkzeug.pas'));
  finally
    mTree.Free;
  end;
end;

procedure TNoreturnReturnsTests.IssueExample;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := NoreturnFindings(Abbruch('  if AText <> '''' then'#10'    raise EImport.Create(AText);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Fehler kann am Ende normal zurückkehren, obwohl die Routine noreturn ist.', mFound[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFound[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFound[0].Confidence));
  // Am Namen der Implementierung (Zeile 8), nicht an der Deklaration.
  Assert.AreEqual(8, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(10, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  // Leerer Rumpf und Rumpf ohne raise.
  Assert.AreEqual(1, Integer(Length(NoreturnFindings(Abbruch('')))));
  Assert.AreEqual(1, Integer(Length(NoreturnFindings(Abbruch('  Melden(AText);'#10)))));
end;

procedure TNoreturnReturnsTests.ExitAndMethods;
const
  cKlasse = 'unit Import;'#10'interface'#10'type'#10'  TImport = class'#10 +
    '    procedure Abbrechen; noreturn;'#10'    procedure Beenden; noreturn;'#10'  end;'#10'implementation'#10 +
    'procedure TImport.Abbrechen;'#10'begin'#10'  %s'#10'end;'#10 +
    'procedure TImport.Beenden;'#10'begin'#10'  %s'#10'end;'#10'end.';
var
  mFound: TArray<TRuleFinding>;
begin
  // Exit an der Anweisung; der Weg danach endet mit raise.
  mFound := NoreturnFindings(Abbruch('  if AText = '''' then'#10'    Exit;'#10'  raise EImport.Create(AText);'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Exit verlässt Fehler normal, obwohl die Routine noreturn ist.', mFound[0].Message);
  Assert.AreEqual(11, mFound[0].Range.StartPos.Line);
  // Methoden: Direktive an der Klassendeklaration; Aufruf einer anderen noreturn-Methode beendet den Weg.
  mFound := NoreturnFindings(Format(cKlasse, ['raise EAbort.Create(''x'');', 'Abbrechen;']));
  Assert.AreEqual(0, Integer(Length(mFound)));
  mFound := NoreturnFindings(Format(cKlasse, ['Beenden;', 'Self.Abbrechen;']));
  Assert.AreEqual(0, Integer(Length(mFound)));
  mFound := NoreturnFindings(Format(cKlasse, ['Beenden;', '']));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Beenden kann am Ende normal zurückkehren, obwohl die Routine noreturn ist.', mFound[0].Message);
end;

procedure TNoreturnReturnsTests.EndingPathsAreSilent;
const
  cBodies: array[0..7] of string = (
    '  raise EImport.Create(AText);'#10,
    '  if AText = '''' then'#10'    raise EImport.Create(''leer'')'#10'  else'#10 +
      '    raise EImport.Create(AText);'#10,
    '  Melden(AText);'#10'  Halt(1);'#10,
    '  RunError(204);'#10,
    '  Abort;'#10,
    '  try'#10'    Melden(AText);'#10'  finally'#10'    Melden(''x'');'#10'  end;'#10'  raise EImport.Create(AText);'#10,
    // Ende über eine andere noreturn-Routine (hier die Routine selbst: Rekursion).
    '  Fehler(AText + ''!'');'#10,
    // Exit nach Halt ist nicht erreichbar.
    '  Halt(1);'#10'  Exit;'#10);
var
  mBody: string;
begin
  for mBody in cBodies do
  begin
    Assert.AreEqual(0, Integer(Length(NoreturnFindings(Abbruch(mBody)))), mBody);
  end;
  // Ohne noreturn meldet die Regel nichts.
  Assert.AreEqual(0, Integer(Length(NoreturnFindings(Abbruch('').Replace(' noreturn;', '')))));
  // asm: Der Graph ist unvollständig.
  Assert.AreEqual(0, Integer(Length(NoreturnFindings(Abbruch('  asm'#10'    nop'#10'  end;'#10)))));
end;

procedure TNoreturnReturnsTests.UnknownCallsUseIndex;
const
  cWerkzeug = 'unit Werkzeug;'#10'interface'#10'procedure Protokolliere(const AText: string);'#10 +
    'procedure Ausnahme(const AText: string); noreturn;'#10'implementation'#10 +
    'procedure Protokolliere(const AText: string);'#10'begin'#10'end;'#10 +
    'procedure Ausnahme(const AText: string);'#10'begin'#10'  raise EImport.Create(AText);'#10'end;'#10'end.';
var
  mIndex: ISymbolIndex;
  mSource: string;
begin
  // Ohne Index könnte Protokolliere selbst noreturn sein: still.
  mSource := Abbruch('  Protokolliere(AText);'#10);
  Assert.AreEqual(0, Integer(Length(NoreturnFindings(mSource))));
  Assert.AreEqual(0, Integer(Length(NoreturnFindings(Abbruch('  FLog.Add(AText);'#10)))));
  Assert.AreEqual(0, Integer(Length(NoreturnFindings(Abbruch('  inherited;'#10)))));
  // Mit Index: Protokolliere kehrt zurück, Ausnahme nicht.
  mIndex := IndexWith(cWerkzeug);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TNoreturnReturnsRule.Create, mSource, mIndex, '',
    'Import.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TNoreturnReturnsRule.Create,
    Abbruch('  Protokolliere(AText);'#10'  Ausnahme(AText);'#10), mIndex, '', 'Import.pas'))));
end;

procedure TNoreturnReturnsTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := Abbruch('');
  Assert.AreEqual(1, Integer(Length(NoreturnFindings(mSource, '', 'Source/Import.pas'))));
  Assert.AreEqual(0, Integer(Length(NoreturnFindings(mSource, '{"rules": {"noreturn-returns": "off"}}',
    'Source/Import.pas'))));
  Assert.AreEqual(0, Integer(Length(NoreturnFindings(mSource,
    '{"rules": {"noreturn-returns": {"exclude": ["Source/*.pas"]}}}', 'Source/Import.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TFlowRulesTests);
  TDUnitX.RegisterTestFixture(TNoreturnReturnsTests);

end.
