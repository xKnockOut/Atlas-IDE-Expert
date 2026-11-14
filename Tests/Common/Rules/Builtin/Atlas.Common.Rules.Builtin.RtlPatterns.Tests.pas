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
    procedure SelfAssignmentThroughSetterSilent;
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
    [Test]
    procedure RandomizeInOtherProjectUnitIsSilent;
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
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Tests.RuleAssert;

function InRoutine(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

procedure TRtlPatternRulesTests.SelfAssignmentReportedWithFix;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TSelfAssignmentRule.Create, InRoutine('  Save;'#10'  Kunde.Name := Kunde.Name;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual('', mFindings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(27, mFindings[0].Fixes[0].Edits[0].Range.EndPos.Character);
  TRuleAssert.Reports(TSelfAssignmentRule.Create, InRoutine('  if A then X := x else Y := 1;'));
  TRuleAssert.Reports(TSelfAssignmentRule.Create, InRoutine('  begin Liste[I] := Liste[I] end;'));
end;

procedure TRtlPatternRulesTests.SelfAssignmentOffersSelfForHiddenField;
const
  cSource =
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
  mIndex: ISymbolIndex;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mFindings: TArray<TRuleFinding>;
begin
  mIndex := TSymbolIndex.Create;
  mTree := TPascalParser.Parse(cSource);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := 'Kunde.pas';
    mContext.UnitName := 'Kunde';
    mContext.Text := cSource;
    mContext.Tree := mTree;
    mContext.Index := mIndex;
    mFindings := TRuleEngine.Run([TSelfAssignmentRule.Create], TServerSettings.Default, mContext);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(2, Integer(Length(mFindings)));
  // Parameter verdeckt das Feld: zuerst "Self. ergänzen", dann "Anweisung entfernen".
  Assert.AreEqual(11, mFindings[0].Range.StartPos.Line);
  Assert.IsTrue(Pos('Parameter Name verdeckt Feld TKunde.Name', mFindings[0].Message) > 0, mFindings[0].Message);
  Assert.AreEqual(2, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Self.', mFindings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(2, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.AreEqual(2, mFindings[0].Fixes[0].Edits[0].Range.EndPos.Character);
  Assert.AreEqual('', mFindings[0].Fixes[1].Edits[0].NewText);
  // Ohne gleichnamiges Feld bleibt es beim Entfernen; der Name steht wie geschrieben in der Meldung.
  Assert.AreEqual(17, mFindings[1].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(mFindings[1].Fixes)));
  Assert.AreEqual(1, Pos('Zahl wird sich selbst zugewiesen', mFindings[1].Message), mFindings[1].Message);
end;

procedure TRtlPatternRulesTests.SelfAssignmentThroughSetterSilent;
const
  cSource =
    'unit Fenster;'#10 +                             // 0
    'interface'#10 +                                 // 1
    'type'#10 +                                      // 2
    '  TFenster = class'#10 +                        // 3
    '  private'#10 +                                 // 4
    '    FTop, FLeft: Integer;'#10 +                 // 5
    '    procedure SetTop(AValue: Integer);'#10 +    // 6
    '  public'#10 +                                  // 7
    '    procedure Auffrischen;'#10 +                // 8
    '    property Top: Integer read FTop write SetTop;'#10 + // 9
    '    property Left: Integer read FLeft write FLeft;'#10 + // 10
    '  end;'#10 +                                    // 11
    'implementation'#10 +                            // 12
    'procedure TFenster.SetTop(AValue: Integer);'#10 + // 13
    'begin'#10 +                                     // 14
    '  FTop := AValue;'#10 +                         // 15
    'end;'#10 +                                      // 16
    'procedure TFenster.Auffrischen;'#10 +           // 17
    'begin'#10 +                                     // 18
    '  Top := Top;'#10 +                             // 19
    '  Self.Top := Self.Top;'#10 +                   // 20
    '  Left := Left;'#10 +                           // 21
    'end;'#10 +                                      // 22
    'end.';
var
  mIndex: ISymbolIndex;
  mContext: TRuleContext;
  mTree: TSyntaxTree;
  mFindings: TArray<TRuleFinding>;
begin
  // FP-Prüfung 28.10.2026 (F08): "Top := Top" ruft den Setter auf und ist gewollt; nur Left schreibt ein Feld.
  mIndex := TSymbolIndex.Create;
  mTree := TPascalParser.Parse(cSource);
  try
    mContext := Default(TRuleContext);
    mContext.RelativePath := 'Fenster.pas';
    mContext.UnitName := 'Fenster';
    mContext.Text := cSource;
    mContext.Tree := mTree;
    mContext.Index := mIndex;
    mFindings := TRuleEngine.Run([TSelfAssignmentRule.Create], TServerSettings.Default, mContext);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(21, mFindings[0].Range.StartPos.Line);
  mFindings := nil;
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
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TForHighToLowRule.Create, InRoutine('  for I := High(A) to Low(A) do'#10 +
    '    Save(A[I]);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('downto', mFindings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(19, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  Assert.IsTrue(mFindings[0].Fixes[0].Safe);
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
  cBody = '  for I := 10 to 1 do'#10'    Countdown(I);';
var
  mFindings: TArray<TRuleFinding>;
begin
  // Beispiel aus #1023 mit Korrektur.
  mFindings := TRuleAssert.Findings(TForHighToLowRule.Create, InRoutine(cBody));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('for-high-to-low', mFindings[0].RuleId);
  Assert.AreEqual('Die Schleife läuft nie (10 to 1); gemeint war downto (wie H2135).', mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('to durch downto ersetzen', mFindings[0].Fixes[0].Title);
  Assert.AreEqual(InRoutine('  for I := 10 downto 1 do'#10'    Countdown(I);'),
    TChangeSignature.ApplyEdits(InRoutine(cBody), mFindings[0].Fixes[0].Edits));
  // Vorzeichen, Hex, Zeichen, Inline-Variable mit und ohne Typ (auch für High … to Low).
  mFindings := TRuleAssert.Findings(TForHighToLowRule.Create, InRoutine('  for I := -1 to -5 do;'#10 +
    '  for I := $10 to 3 do;'#10'  for C := ''z'' to ''a'' do;'#10'  for C := #13 to #10 do;'#10 +
    '  for var K := 3 to 2 do;'#10'  for var K: Integer := 3 to 2 do;'#10'  for var K := High(A) to Low(A) do;'));
  Assert.AreEqual(7, Integer(Length(mFindings)));
  Assert.AreEqual('Die Schleife läuft nie (3 to 2); gemeint war downto (wie H2135).', mFindings[5].Message);
  Assert.AreEqual('Die Schleife läuft nie (-1 to -5); gemeint war downto (wie H2135).', mFindings[0].Message);
  Assert.AreEqual('Die Schleife läuft nie ($10 to 3); gemeint war downto (wie H2135).', mFindings[1].Message);
  Assert.AreEqual('Die Schleife läuft nie (''z'' to ''a''); gemeint war downto (wie H2135).', mFindings[2].Message);
  Assert.AreEqual('Die Schleife läuft nie (#13 to #10); gemeint war downto (wie H2135).', mFindings[3].Message);
end;

procedure TRtlPatternRulesTests.ForConstantBoundsSilentAndOff;
const
  cBody = '  for I := 10 to 1 do;';
begin
  // Korrigierte Form, aufsteigend, gleiche Grenzen (läuft einmal), Ausdrücke und Namen, bedingte Übersetzung.
  TRuleAssert.Silent(TForHighToLowRule.Create, InRoutine('  for I := 10 downto 1 do;'#10 +
    '  for I := 1 to 10 do;'#10'  for I := 5 to 5 do;'#10'  for I := 10 - 9 to 1 do;'#10 +
    '  for I := Max to 1 do;'#10'  for I := 10 to N do;'#10'  for I := -5 to -1 do;'#10 +
    '  for I := {$IFDEF X}10{$ELSE}0{$ENDIF} to 1 do;'#10'  for C := ''a'' to ''z'' do;'));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForHighToLowRule.Create, InRoutine(cBody),
    '{"rules": {"for-high-to-low": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TForHighToLowRule.Create, InRoutine(cBody),
    '{"rules": {"group:compiler": "off"}}', 'U.pas'))));
end;

procedure TRtlPatternRulesTests.ExceptionNotRaisedReportedWithFix;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TExceptionNotRaisedRule.Create,
    InRoutine('  if X = nil then'#10'    EArgumentException.Create(''X fehlt'');'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('raise ', mFindings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(4, mFindings[0].Fixes[0].Edits[0].Range.StartPos.Character);
  TRuleAssert.Reports(TExceptionNotRaisedRule.Create, InRoutine('  Exception.CreateFmt(''%d'', [N])'));
end;

procedure TRtlPatternRulesTests.RaisedExceptionSilent;
begin
  TRuleAssert.Silent(TExceptionNotRaisedRule.Create, InRoutine('  raise EArgumentException.Create(''X'');'#10 +
    '  E := Exception.Create(''X'');'#10'  Exception.Create(''X'').Free;'#10'  Engine.Create;'));
end;

procedure TRtlPatternRulesTests.AssertSideEffectReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TAssertSideEffectRule.Create, InRoutine('  Assert(List.Remove(X) >= 0);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.IsTrue(Pos('Remove', mFindings[0].Message) > 0, mFindings[0].Message);
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
  cConfig = '{ "rules": { "assert-side-effect": { "severity": "warning", "mutatingMethods": ["Push"] } } }';
begin
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TAssertSideEffectRule.Create,
    InRoutine('  Assert(Stack.Push(X));'), cConfig))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TAssertSideEffectRule.Create,
    InRoutine('  Assert(List.Remove(X) >= 0);'), cConfig))));
  Assert.AreEqual(6, Integer(Length(TAssertSideEffectRule.MutatingMethods(''))));
end;

procedure TRtlPatternRulesTests.IfThenSideEffectReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TIfThenSideEffectRule.Create,
    InRoutine('  S := IfThen(Assigned(X), X.Name, '''');'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual('if Assigned(X) then S := X.Name else S := '''';', mFindings[0].Fixes[0].Edits[0].NewText);
  mFindings := TRuleAssert.Findings(TIfThenSideEffectRule.Create,
    InRoutine('  Caption := IfThen(Kunde <> nil, Kunde.Name, Format(''%d'', [N]));'));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  mFindings := TRuleAssert.Findings(TIfThenSideEffectRule.Create, InRoutine('  Log(IfThen(B, Load, ''-''));'));
  Assert.AreEqual(0, Integer(Length(mFindings)));
  mFindings := TRuleAssert.Findings(TIfThenSideEffectRule.Create, InRoutine('  Log(IfThen(B, Load(1), ''-''));'));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TRtlPatternRulesTests.IfThenWithoutSideEffectSilent;
begin
  TRuleAssert.Silent(TIfThenSideEffectRule.Create, InRoutine('  S := IfThen(A > B, ''x'', ''y'');'#10 +
    '  N := IfThen(Flag, 1, 2);'));
  // Standardroutinen ohne Seiteneffekte in den Zweigen (#1109).
  TRuleAssert.Silent(TIfThenSideEffectRule.Create, InRoutine(
    '  S := IfThen(C > 0, Copy(T, 1, C - 1), T);'#10 +
    '  S := IfThen(A = '''', ''-'', Format(''%s: %s'', [A, ExtractFileExt(F)]));'#10 +
    '  S := IfThen(Length(L) > 0, ''('' + string.Join('', '', L) + '')'', '''');'));
  // Methode eines Objekts bleibt ein möglicher Seiteneffekt.
  TRuleAssert.Reports(TIfThenSideEffectRule.Create, InRoutine('  S := IfThen(B, List.Join(''x''), '''');'));
end;

procedure TRtlPatternRulesTests.RandomWithoutRandomize;
const
  cConfig = '{ "minConfidence": "low", "rules": { "random-without-randomize": "hint" } }';
begin
  // Standard aus.
  TRuleAssert.Silent(TRandomWithoutRandomizeRule.Create, InRoutine('  N := Random(6);'));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TRandomWithoutRandomizeRule.Create,
    InRoutine('  N := Random(6);'#10'  M := Random(6);'), cConfig))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRandomWithoutRandomizeRule.Create,
    InRoutine('  Randomize;'#10'  N := Random(6);'), cConfig))));
  // Eigener Aufzählungswert Random (TTexts = (Title, Random)) ist kein Aufruf von System.Random.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRandomWithoutRandomizeRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TTexts = (Title, Random);'#10'implementation'#10'end.', cConfig))));
  // Auch unter SCOPEDENUMS, wo der Wert nur als TTexts.Random sichtbar ist (Gesamtlauf 07.11.).
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TRandomWithoutRandomizeRule.Create,
    'unit U;'#10'interface'#10'{$SCOPEDENUMS ON}'#10'type'#10'  TTexts = (Title, Random);'#10'implementation'#10 +
    'end.', cConfig))));
end;

procedure TRtlPatternRulesTests.RandomizeInOtherProjectUnitIsSilent;
const
  cConfig = '{ "minConfidence": "low", "rules": { "random-without-randomize": "hint" } }';
var
  mIndex: ISymbolIndex;
  mUnit: TUnitIndex;
begin
  // Randomize steht einmal am Programmstart (Testprogramm), Random in einer Testunit: kein Befund.
  mIndex := TSymbolIndex.Create;
  mUnit := TIndexExtractor.ExtractText(InRoutine('  Random(6);'), 'U.pas', nil, nil, True);
  mIndex.AddUnit(mUnit);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.IndexFindings(TRandomWithoutRandomizeRule.Create,
    InRoutine('  N := Random(6);'), mIndex, cConfig, 'U.pas'))), 'ohne Randomize im Projekt');
  mUnit := TIndexExtractor.ExtractText('unit Start;'#10'interface'#10'implementation'#10'initialization'#10 +
    '  Randomize;'#10'end.', 'Start.pas', nil, nil, True);
  mIndex.AddUnit(mUnit);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TRandomWithoutRandomizeRule.Create,
    InRoutine('  N := Random(6);'), mIndex, cConfig, 'U.pas'))), 'Randomize in einer anderen Unit');
end;

initialization
  TDUnitX.RegisterTestFixture(TRtlPatternRulesTests);

end.
