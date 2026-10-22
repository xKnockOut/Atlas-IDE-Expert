unit Atlas.Common.Rules.Builtin.RtlPatterns.Tests;

// Tests für die Regeln zu RTL-Mustern aus #153, Stufe 1: je Regel ein
// positiver und ein negativer Fall, dazu die Fälle aus der Abnahme; konstante
// Grenzen, die nie laufen, bei for-high-to-low (#1023, wie H2135).

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
    procedure SelfAssignmentOffersSelfForHiddenField;
    [Test]
    procedure ForHighToLowReportedWithFix;
    [Test]
    procedure ForLowToHighSilent;
    [Test]
    procedure ForConstantBoundsNeverRun;
    [Test]
    procedure ForConstantBoundsSilentAndOff;
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
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.RtlPatterns,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Tests.RuleAssert;

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

procedure TRtlPatternRulesTests.SelfAssignmentOffersSelfForHiddenField;
const
  Source =
    'unit Kunde;'#10 +                               // 0
    'interface'#10 +                                 // 1
    'type'#10 +                                      // 2
    '  TKunde = class'#10 +                          // 3
    '    Name: string;'#10 +                         // 4
    '    procedure SetzeName(const Name: string);'#10 + // 5
    '    procedure Lokal;'#10 +                      // 6
    '  end;'#10 +                                    // 7
    'implementation'#10 +                            // 8
    'procedure TKunde.SetzeName(const Name: string);'#10 + // 9
    'begin'#10 +                                     // 10
    '  Name := Name;'#10 +                           // 11
    'end;'#10 +                                      // 12
    'procedure TKunde.Lokal;'#10 +                   // 13
    'var'#10 +                                       // 14
    '  Zahl: Integer;'#10 +                          // 15
    'begin'#10 +                                     // 16
    '  Zahl := Zahl;'#10 +                           // 17
    'end;'#10 +                                      // 18
    'end.';
var
  Index: ISymbolIndex;
  Context: TRuleContext;
  Tree: TSyntaxTree;
  Findings: TArray<TRuleFinding>;
begin
  Index := TSymbolIndex.Create;
  Tree := TPascalParser.Parse(Source);
  try
    Context := Default(TRuleContext);
    Context.RelativePath := 'Kunde.pas';
    Context.UnitName := 'Kunde';
    Context.Text := Source;
    Context.Tree := Tree;
    Context.Index := Index;
    Findings := TRuleEngine.Run([TSelfAssignmentRule.Create], TServerSettings.Default, Context);
  finally
    Tree.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Findings)));
  // Parameter verdeckt das Feld: zuerst "Self. ergänzen", dann "Anweisung entfernen".
  Assert.AreEqual(11, Findings[0].Range.StartPos.Line);
  Assert.IsTrue(Pos('Parameter Name verdeckt Feld TKunde.Name', Findings[0].Message) > 0, Findings[0].Message);
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Self.', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(2, Findings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(2, Findings[0].Fixes[0].Edits[0].Range.EndPos.Character);
  Assert.AreEqual('', Findings[0].Fixes[1].Edits[0].NewText);
  // Ohne gleichnamiges Feld bleibt es beim Entfernen; der Name steht wie geschrieben in der Meldung.
  Assert.AreEqual(17, Findings[1].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Findings[1].Fixes)));
  Assert.IsTrue(Pos('Zahl wird sich selbst zugewiesen', Findings[1].Message) = 1, Findings[1].Message);
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

procedure TRtlPatternRulesTests.ForConstantBoundsNeverRun;
const
  Body = '  for I := 10 to 1 do'#10'    Countdown(I);';
var
  Findings: TArray<TRuleFinding>;
begin
  // Beispiel aus #1023 mit Korrektur.
  Findings := TRuleAssert.Findings(TForHighToLowRule.Create, InRoutine(Body));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('for-high-to-low', Findings[0].RuleId);
  Assert.AreEqual('Die Schleife läuft nie (10 to 1); gemeint war downto (wie H2135).', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('to durch downto ersetzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual(InRoutine('  for I := 10 downto 1 do'#10'    Countdown(I);'),
    TChangeSignature.ApplyEdits(InRoutine(Body), Findings[0].Fixes[0].Edits));
  // Vorzeichen, Hex, Zeichen, Inline-Variable mit und ohne Typ (auch für High … to Low).
  Findings := TRuleAssert.Findings(TForHighToLowRule.Create, InRoutine('  for I := -1 to -5 do;'#10 +
    '  for I := $10 to 3 do;'#10'  for C := ''z'' to ''a'' do;'#10'  for C := #13 to #10 do;'#10 +
    '  for var K := 3 to 2 do;'#10'  for var K: Integer := 3 to 2 do;'#10'  for var K := High(A) to Low(A) do;'));
  Assert.AreEqual(7, Integer(Length(Findings)));
  Assert.AreEqual('Die Schleife läuft nie (3 to 2); gemeint war downto (wie H2135).', Findings[5].Message);
  Assert.AreEqual('Die Schleife läuft nie (-1 to -5); gemeint war downto (wie H2135).', Findings[0].Message);
  Assert.AreEqual('Die Schleife läuft nie ($10 to 3); gemeint war downto (wie H2135).', Findings[1].Message);
  Assert.AreEqual('Die Schleife läuft nie (''z'' to ''a''); gemeint war downto (wie H2135).', Findings[2].Message);
  Assert.AreEqual('Die Schleife läuft nie (#13 to #10); gemeint war downto (wie H2135).', Findings[3].Message);
end;

procedure TRtlPatternRulesTests.ForConstantBoundsSilentAndOff;
const
  Body = '  for I := 10 to 1 do;';
begin
  // Korrigierte Form, aufsteigend, gleiche Grenzen (läuft einmal), Ausdrücke und Namen, bedingte Übersetzung.
  TRuleAssert.Silent(TForHighToLowRule.Create, InRoutine('  for I := 10 downto 1 do;'#10 +
    '  for I := 1 to 10 do;'#10'  for I := 5 to 5 do;'#10'  for I := 10 - 9 to 1 do;'#10 +
    '  for I := Max to 1 do;'#10'  for I := 10 to N do;'#10'  for I := -5 to -1 do;'#10 +
    '  for I := {$IFDEF X}10{$ELSE}0{$ENDIF} to 1 do;'#10'  for C := ''a'' to ''z'' do;'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForHighToLowRule.Create, InRoutine(Body),
    '{"rules": {"for-high-to-low": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForHighToLowRule.Create, InRoutine(Body),
    '{"rules": {"group:compiler": "off"}}', 'U.pas'))));
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
