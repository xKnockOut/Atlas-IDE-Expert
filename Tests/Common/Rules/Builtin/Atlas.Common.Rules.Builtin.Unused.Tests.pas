unit Atlas.Common.Rules.Builtin.Unused.Tests;

// Tests für unused-local, unused-parameter und unused-assignment (#91) sowie
// duplicate-assignment (#1051): Beispiel mit Sprung, Gegenstück im Hinweis, Ziele
// (Self., Felder, Zeiger), stille Fälle (Lesen, Aufruf, lokale Variablen,
// False/True, bedingte Zweige), Option allowProperties, Abschalten und exclude.
// empty-routine (#977): Beispiel des Issues, beide Korrekturen, Ausnahmen
// (Kommentar, virtual, message, Formular-Handler), Entfernen nur ohne Verweis.

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
    /// <summary>Bereiche der Korrektur über die Zeilentabelle des Ableitungscaches (Review D-04).</summary>
    [Test]
    procedure RemoveVariableFixInCrLfFile;
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
    procedure MethodAssignedThroughObjectIsSilent;
    [Test]
    procedure PlainMethodReports;
    [Test]
    procedure InterfaceImplementationIsSilent;
    [Test]
    procedure OverwrittenAssignmentReports;
    [Test]
    procedure InterfaceAssignmentIsSilent;
    [Test]
    procedure AssignmentBeforeFailingTryIsRead;
    /// <summary>H2077 nur bei bekanntem, nicht verwaltetem Typ (#1383, Cm.E2056).</summary>
    [Test]
    procedure AssignmentCodeOnlyForUnmanagedTypes;
    [Test]
    procedure AssignmentReadLaterIsSilent;
    [Test]
    procedure AssignmentReadInLoopIsSilent;
    /// <summary>Leeren eines gesetzten Werts ist Freigabe; Leeren ohne vorherigen Wert bleibt ein Befund.</summary>
    [Test]
    procedure ClearingAssignedValueIsSilent;
    [Test]
    procedure WildcardMatching;
    [Test]
    procedure EmptyRoutineReported;
    [Test]
    procedure EmptyRoutineCommentFix;
    [Test]
    procedure EmptyRoutineRemoveFix;
    [Test]
    procedure EmptyRoutineSilentCases;
    [Test]
    procedure EmptyRoutineSwitchedOff;
  end;

  [TestFixture]
  TDuplicateAssignmentTests = class
  public
    [Test]
    procedure IssueExampleWithJump;
    [Test]
    procedure CounterpartOnlyWhenMissing;
    [Test]
    procedure TargetsAndKeys;
    [Test]
    procedure ReadOrCallInBetweenIsSilent;
    [Test]
    procedure SilentCases;
    [Test]
    procedure ConditionalBranches;
    [Test]
    procedure AllowPropertiesOption;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Unused,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
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

function CrLf(const AText: string): string;
begin
  Result := StringReplace(AText, #10, #13#10, [rfReplaceAll]);
end;

/// <summary>Wendet die erste Korrektur des ersten Treffers an (Zeilen mit #10 oder #13#10).</summary>
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

procedure TUnusedRulesTests.RemoveVariableFixInCrLfFile;
var
  Source: string;
begin
  Source := CrLf(Routine('  I := 1;'#10'  Foo(I);', 'procedure P;', 'var'#10'  I: Integer;'#10'  J: string;'#10));
  Assert.AreEqual(CrLf(Routine('  I := 1;'#10'  Foo(I);', 'procedure P;', 'var'#10'  I: Integer;'#10)),
    ApplyFirstFix(Source, TRuleAssert.Findings(TUnusedLocalRule.Create, Source)));
  Source := CrLf(Routine('  Foo;', 'procedure P;', 'var'#10'  J: string;'#10));
  Assert.AreEqual(CrLf(Routine('  Foo;')), ApplyFirstFix(Source, TRuleAssert.Findings(TUnusedLocalRule.Create, Source)));
  Source := CrLf(Routine('  J := 1;'#10'  Foo(J);', 'procedure P;', 'var'#10'  I, J: Integer;'#10));
  Assert.AreEqual(CrLf(Routine('  J := 1;'#10'  Foo(J);', 'procedure P;', 'var'#10'  J: Integer;'#10)),
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

// Writer.OnFindMethodName := Namer.FindMethodName: Die Methode erfüllt einen Ereignistyp (#1109).
procedure TUnusedRulesTests.MethodAssignedThroughObjectIsSilent;
begin
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    ClassUnit('  public'#10'    procedure Name(Writer: TObject; var AName: string);',
      'procedure TFoo.Name(Writer: TObject; var AName: string);'#10'begin'#10'  AName := '''';'#10'end;'#10 +
      'procedure P(Foo: TFoo; W: TWriter);'#10'begin'#10'  W.OnFindMethodName := Foo.Name;'#10'end;'));
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

// Bereichswächter und vorzeitige Freigabe wirken über den Referenzzähler (#1109).
procedure TUnusedRulesTests.InterfaceAssignmentIsSilent;
begin
  TRuleAssert.Silent(TUnusedAssignmentRule.Create,
    Routine('  Activity := Scope(''x'');'#10'  Writer := Buffer.CreateWriter;'#10'  Writer.Insert(''a'');'#10 +
      '  Writer := nil;'#10'  Work;', 'procedure P;', 'var'#10'  Activity: IInterface;'#10'  Writer: IOTAEditWriter;'#10));
  // Andere Typen weiterhin.
  TRuleAssert.Reports(TUnusedAssignmentRule.Create,
    Routine('  Item := Load;'#10'  Work;', 'procedure P;', 'var'#10'  Item: TItem;'#10));
end;

// Recent := nil vor try: Wirft RecentProjects, liest die Schleife den alten Wert (#1109).
procedure TUnusedRulesTests.AssignmentBeforeFailingTryIsRead;
begin
  TRuleAssert.Silent(TUnusedAssignmentRule.Create,
    Routine('  Recent := nil;'#10'  try'#10'    Recent := RecentProjects;'#10'  except'#10'    Report;'#10'  end;'#10 +
      '  for S in Recent do'#10'    Use(S);', 'procedure P;', 'var'#10'  Recent: TArray<string>;'#10'  S: string;'#10));
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

procedure TUnusedRulesTests.AssignmentCodeOnlyForUnmanagedTypes;
const
  // Verwaltete Typen: dcc meldet H2077 nicht.
  ManagedTypes: array[0..4] of string = ('string', 'TArray<Integer>', 'Variant', 'TBytes', 'TMitText');
var
  Findings: TArray<TRuleFinding>;
  TypeName: string;
begin
  Findings := TRuleAssert.Findings(TUnusedAssignmentRule.Create,
    Routine('  I := 1;', 'procedure P;', 'var'#10'  I: Integer;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Der an "I" zugewiesene Wert wird nie gelesen (wie H2077)', Findings[0].Message);
  for TypeName in ManagedTypes do
  begin
    Findings := TRuleAssert.Findings(TUnusedAssignmentRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
      'type'#10'  TMitText = record'#10'    Text: string;'#10'  end;'#10'procedure P;'#10'var'#10'  X: ' + TypeName +
      ';'#10'begin'#10'  X := Default(' + TypeName + ');'#10'end;'#10'end.');
    Assert.AreEqual(1, Integer(Length(Findings)), TypeName);
    Assert.AreEqual('Der an "X" zugewiesene Wert wird nie gelesen', Findings[0].Message, TypeName);
  end;
  // Inline-Variable ohne Typangabe: Typ unbekannt, also ohne Code.
  Findings := TRuleAssert.Findings(TUnusedAssignmentRule.Create, Routine('  var I := 1;'#10'  I := 2;'));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Der an "I" zugewiesene Wert wird nie gelesen', Findings[0].Message);
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

procedure TUnusedRulesTests.ClearingAssignedValueIsSilent;
const
  // Rechte Seiten, die das Ziel leeren.
  ClearValues: array[0..4] of string = ('nil', '''''', 'Default(TErgebnis)', 'TErgebnis.Empty', 'Default( TErgebnis )');
var
  Value: string;
  Findings: TArray<TRuleFinding>;
begin
  for Value in ClearValues do
  begin
    // Started := Default(…) am Testende, Lookup := nil vor Resolver.Free.
    TRuleAssert.Silent(TUnusedAssignmentRule.Create,
      Routine('  X := Load;'#10'  Result := X.Text;'#10'  X := ' + Value + ';'#10'  Work;', 'function F: string;',
        'var'#10'  X: TErgebnis;'#10));
    // Leeren im finally: Der Wert davor stammt aus dem try.
    TRuleAssert.Silent(TUnusedAssignmentRule.Create,
      Routine('  try'#10'    X := Load;'#10'    Result := X.Text;'#10'  finally'#10'    X := ' + Value + ';'#10'  end;',
        'function F: string;', 'var'#10'  X: TErgebnis;'#10));
    // Ohne vorherigen Wert ist das Leeren überflüssig.
    Findings := TRuleAssert.Findings(TUnusedAssignmentRule.Create,
      Routine('  X := ' + Value + ';'#10'  Work;', 'procedure P;', 'var'#10'  X: TErgebnis;'#10));
    Assert.AreEqual(1, Integer(Length(Findings)), Value);
  end;
  // Andere Werte am Ende bleiben Befunde.
  Findings := TRuleAssert.Findings(TUnusedAssignmentRule.Create,
    Routine('  X := Load;'#10'  Result := X.Text;'#10'  X := Load;', 'function F: string;', 'var'#10'  X: TErgebnis;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(9, Findings[0].Range.StartPos.Line);
end;

procedure TUnusedRulesTests.WildcardMatching;
begin
  Assert.IsTrue(MatchesWildcard('Dummy1', 'dummy*'));
  Assert.IsTrue(MatchesWildcard('_x', '_?'));
  Assert.IsFalse(MatchesWildcard('_xy', '_?'));
  Assert.IsTrue(MatchesWildcard('AUnused', '*Unused'));
  Assert.IsFalse(MatchesWildcard('Used', 'X*'));
end;

{ TDuplicateAssignmentTests }

/// <summary>Methode TForm1.Init mit ABody; AVars als var-Abschnitt.</summary>
function Formular(const ABody: string; const AVars: string = ''): string;
begin
  Result := Routine(ABody, 'procedure TForm1.Init;', AVars);
end;

function DuplicateCount(const ASource: string; const AConfig: string = ''): Integer;
begin
  Result := Length(TRuleAssert.Findings(TDuplicateAssignmentRule.Create, ASource, AConfig));
end;

procedure TDuplicateAssignmentTests.IssueExampleWithJump;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Left := 8;'#10'  Panel.Left := 40;'#10'  Panel.Width := 200;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('duplicate-assignment', Findings[0].RuleId);
  Assert.AreEqual('Panel.Left wird in Zeile 6 schon gesetzt; gemeint ist vermutlich Panel.Top.', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(12, Findings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.IsTrue(Findings[0].Fixes[0].HasJump);
  Assert.AreEqual(5, Findings[0].Fixes[0].JumpTo.Line);
  // Die korrigierte Form ist still.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Left := 8;'#10'  Panel.Top := 40;'#10'  Panel.Width := 200;'));
end;

procedure TDuplicateAssignmentTests.CounterpartOnlyWhenMissing;
var
  Findings: TArray<TRuleFinding>;
begin
  // Top wird schon gesetzt: keine Vermutung, nur der Verlust.
  Findings := TRuleAssert.Findings(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Top := 1;'#10'  Panel.Left := 8;'#10'  Panel.Left := 40;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Panel.Left wird in Zeile 7 schon gesetzt; der erste Wert geht ungelesen verloren.',
    Findings[0].Message);
  // Ohne Gegenstück in der Tabelle.
  Findings := TRuleAssert.Findings(TDuplicateAssignmentRule.Create,
    Formular('  Caption := ''A'';'#10'  Caption := ''B'';'));
  Assert.AreEqual('Caption wird in Zeile 6 schon gesetzt; der erste Wert geht ungelesen verloren.',
    Findings[0].Message);
  Findings := TRuleAssert.Findings(TDuplicateAssignmentRule.Create,
    Formular('  Bild.Height := 8;'#10'  Bild.height := 40;'));
  Assert.AreEqual('Bild.height wird in Zeile 6 schon gesetzt; gemeint ist vermutlich Bild.Width.',
    Findings[0].Message);
  Assert.AreEqual('Top', TDuplicateAssignmentRule.Counterpart('left'));
  Assert.AreEqual('Width', TDuplicateAssignmentRule.Counterpart('Height'));
  Assert.AreEqual('', TDuplicateAssignmentRule.Counterpart('Caption'));
end;

procedure TDuplicateAssignmentTests.TargetsAndKeys;
begin
  // Self.FWert und FWert sind dasselbe Ziel, ebenso Zeiger und verschachtelte Mitglieder.
  Assert.AreEqual(1, DuplicateCount(Formular('  Self.FWert := -1;'#10'  FWert := 2;')));
  Assert.AreEqual(1, DuplicateCount(Formular('  P^.X := nil;'#10'  P^.X := Q;')));
  Assert.AreEqual(1, DuplicateCount(Formular('  Panel.Font.Size := 8;'#10'  Panel.Font.Size := 10;')));
  Assert.AreEqual(1, DuplicateCount(Formular('  with Panel do'#10'  begin'#10'    Left := 1;'#10 +
    '    Left := 2;'#10'  end;')));
  // Mitglieder lokaler Records zählen, im initialization-Abschnitt ebenso.
  Assert.AreEqual(1, DuplicateCount(Formular('  R.Left := 1;'#10'  R.Left := 2;', 'var'#10'  R: TRect;'#10)));
  Assert.AreEqual(1, DuplicateCount('unit U;'#10'interface'#10'implementation'#10'initialization'#10 +
    '  Application.Title := ''A'';'#10'  Application.Title := ''B'';'#10'end.'));
  // Zuweisungen an andere Objekte mit festen Werten dazwischen.
  Assert.AreEqual(1, DuplicateCount(Formular('  Panel.Left := 8;'#10'  Knopf.Left := 3;'#10'  Panel.Left := 40;')));
end;

procedure TDuplicateAssignmentTests.ReadOrCallInBetweenIsSilent;
begin
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Left := 8;'#10'  X := Panel.Left;'#10'  Panel.Left := 40;'));
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Left := 8;'#10'  Ausrichten;'#10'  Panel.Left := 40;'));
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Left := 8;'#10'  Knopf.Left := Berechne(1);'#10'  Panel.Left := 40;'));
  // Der zweite Wert liest das Ziel oder ruft etwas auf.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Left := 8;'#10'  Panel.Left := Panel.Left + 4;'));
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  FWert := 8;'#10'  FWert := Doppelt(1);'));
  // Andere Property desselben Objekts dazwischen: ihr Setter kann den Wert lesen.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Left := 8;'#10'  Panel.Align := alNone;'#10'  Panel.Left := 40;'));
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  FWert := 8;'#10'  Anzahl := 1;'#10'  FWert := 40;'));
  // if, Schleifen und andere Anweisungen unterbrechen die Folge.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Left := 8;'#10'  if A then'#10'    B := 1;'#10'  Panel.Left := 40;'));
end;

procedure TDuplicateAssignmentTests.SilentCases;
begin
  // Lokale Variablen, Parameter und Result deckt unused-assignment ab.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  I := 1;'#10'  I := 2;', 'var'#10'  I: Integer;'#10));
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Routine('  Result := 1;'#10'  Result := 2;'#10'  AWert := 1;'#10'  AWert := 2;', 'function F(var AWert: Integer): Integer;'));
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Routine('  var I := 1;'#10'  I := 2;'#10'  I := 3;', 'procedure P;'));
  // Ziele mit Index oder Aufruf.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Liste[0] := 1;'#10'  Liste[0] := 2;'#10'  Gib.X := 1;'#10'  Gib().X := 2;'));
  // False/True im Wechsel stößt etwas an; derselbe Wert zweimal wird gemeldet.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Abfrage.Active := False;'#10'  Abfrage.Active := True;'));
  Assert.AreEqual(1, DuplicateCount(Formular('  Abfrage.Active := True;'#10'  Abfrage.Active := True;')));
  // then- und else-Zweig, verschiedene Anweisungsfolgen.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  if A then'#10'    Panel.Left := 8'#10'  else'#10'    Panel.Left := 40;'));
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Left := 8;'#10'  begin'#10'    Panel.Left := 40;'#10'  end;'));
end;

procedure TDuplicateAssignmentTests.ConditionalBranches;
begin
  // Zweige desselben {$IFDEF} schließen sich aus.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  {$IFDEF X}'#10'  Caption := ''a'';'#10'  {$ELSE}'#10'  Caption := ''b'';'#10'  {$ENDIF}'));
  // Überschreiben nur unter einer Bedingung ist gewollt.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Caption := ''Atlas'';'#10'  {$IFDEF DEBUG}'#10'  Caption := ''Atlas (Debug)'';'#10'  {$ENDIF}'));
  // Bedingte erste Zuweisung wird immer überschrieben.
  Assert.AreEqual(1, DuplicateCount(
    Formular('  {$IFDEF DEBUG}'#10'  Caption := ''Atlas (Debug)'';'#10'  {$ENDIF}'#10'  Caption := ''Atlas'';')));
end;

procedure TDuplicateAssignmentTests.AllowPropertiesOption;
var
  Issues: TArray<TConfigurationIssue>;
begin
  // Standard: Visible und Enabled dürfen doppelt gesetzt werden.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Visible := True;'#10'  Panel.Visible := True;'#10'  Enabled := True;'#10'  Enabled := True;'));
  Assert.AreEqual(1, DuplicateCount(Formular('  Panel.Visible := True;'#10'  Panel.Visible := True;'),
    '{"rules": {"duplicate-assignment": {"allowProperties": ["Cap*"]}}}'));
  Assert.AreEqual(0, DuplicateCount(Formular('  Panel.Caption := ''A'';'#10'  Panel.Caption := ''B'';'),
    '{"rules": {"duplicate-assignment": {"allowProperties": ["cap*"]}}}'));
  TConfigurationParser.Parse('{"rules": {"duplicate-assignment": {"allowProperties": [1]}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('"allowProperties" muss eine Liste von Texten sein', Issues[0].Message);
  TConfigurationParser.Parse('{"rules": {"duplicate-assignment": {"allowProperties": ["Visible"]}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

procedure TDuplicateAssignmentTests.OffAndExclude;
var
  Source: string;
begin
  Source := Formular('  Panel.Left := 8;'#10'  Panel.Left := 40;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateAssignmentRule.Create, Source,
    '{"rules": {"duplicate-assignment": "off"}}', 'Source/U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateAssignmentRule.Create, Source,
    '{"rules": {"duplicate-assignment": {"exclude": ["Source/*.pas"]}}}', 'Source/U.pas'))));
end;

/// <summary>Unit mit Klasse TImport: AMembers im Typ, ABodies im implementation-Teil.</summary>
function ImportUnit(const AMembers, ABodies: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TImport = class'#10 + AMembers + #10'  end;'#10'implementation'#10 +
    ABodies + #10'end.';
end;

/// <summary>Wendet die Korrektur mit dem Titel ATitle an; das Ergebnis muss fehlerfrei parsen.</summary>
function EmptyFixed(const ASource, ATitle: string): string;
var
  Findings: TArray<TRuleFinding>;
  Fix: TRuleFix;
  Tree: TSyntaxTree;
begin
  Findings := TRuleAssert.Findings(TEmptyRoutineRule.Create, ASource);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Result := '';
  for Fix in Findings[0].Fixes do
    if Fix.Title = ATitle then
      Result := TChangeSignature.ApplyEdits(ASource, Fix.Edits);
  Assert.AreNotEqual('', Result, ATitle);
  Tree := TPascalParser.Parse(Result);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), Result);
  finally
    Tree.Free;
  end;
end;

procedure TUnusedRulesTests.EmptyRoutineReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Assert.IsFalse((TEmptyRoutineRule.Create as IRule).Descriptor.Experimental, 'Standard an');
  Findings := TRuleAssert.Findings(TEmptyRoutineRule.Create, ImportUnit('  public'#10'    procedure Pruefen;',
    'procedure TImport.Pruefen;'#10'begin'#10'end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Pruefen ist leer; entweder fehlt der Inhalt oder die Methode kann weg.', Findings[0].Message);
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
  // Öffentlich: nur der Kommentar, nicht das Entfernen.
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  // Routinen, auch lokale und mit leerer Anweisung.
  Findings := TRuleAssert.Findings(TEmptyRoutineRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure Aussen;'#10'  procedure Innen;'#10'  begin'#10'  end;'#10'begin'#10'  Innen;'#10'end;'#10 +
    'procedure Leer;'#10'begin'#10'  ;'#10'end;'#10'end.');
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Innen ist leer; entweder fehlt der Inhalt oder die Routine kann weg.', Findings[0].Message);
end;

procedure TUnusedRulesTests.EmptyRoutineCommentFix;
var
  Source: string;
begin
  Source := ImportUnit('  public'#10'    procedure Pruefen;', 'procedure TImport.Pruefen;'#10'begin'#10'end;');
  Assert.AreEqual(ImportUnit('  public'#10'    procedure Pruefen;', 'procedure TImport.Pruefen;'#10'begin'#10 +
    '  // Absichtlich leer.'#10'end;'), EmptyFixed(Source, 'Kommentar einfügen'));
  // Die korrigierte Form wird nicht mehr gemeldet.
  TRuleAssert.Silent(TEmptyRoutineRule.Create, EmptyFixed(Source, 'Kommentar einfügen'));
end;

procedure TUnusedRulesTests.EmptyRoutineRemoveFix;
var
  Source: string;
begin
  // Private Methode ohne Verweis: Deklaration samt XML-Doku und Rumpf verschwinden.
  Source := ImportUnit('  private'#10'    /// <summary>Prüft.</summary>'#10'    procedure Pruefen;'#10 +
    '  public'#10'    procedure Laden;', 'procedure TImport.Laden;'#10'begin'#10'  Writeln;'#10'end;'#10#10 +
    'procedure TImport.Pruefen;'#10'begin'#10'end;');
  Assert.AreEqual(ImportUnit('  private'#10'  public'#10'    procedure Laden;', 'procedure TImport.Laden;'#10 +
    'begin'#10'  Writeln;'#10'end;'), EmptyFixed(Source, 'Methode entfernen'));
  // Routine nur im implementation-Teil, mit forward.
  Source := 'unit U;'#10'interface'#10'implementation'#10'procedure Leer; forward;'#10#10'procedure Leer;'#10 +
    'begin'#10'end;'#10'end.';
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'end.', EmptyFixed(Source, 'Routine entfernen'));
  // Mit Verweis oder im interface: nur der Kommentar.
  Source := ImportUnit('  private'#10'    procedure Pruefen;'#10'  public'#10'    procedure Laden;',
    'procedure TImport.Laden;'#10'begin'#10'  Pruefen;'#10'end;'#10'procedure TImport.Pruefen;'#10'begin'#10'end;');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TEmptyRoutineRule.Create, Source)[0].Fixes)));
  Source := 'unit U;'#10'interface'#10'procedure Leer;'#10'implementation'#10'procedure Leer;'#10'begin'#10'end;'#10 +
    'end.';
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TEmptyRoutineRule.Create, Source)[0].Fixes)));
end;

procedure TUnusedRulesTests.EmptyRoutineSilentCases;
const
  Cases: array[0..4] of string = (
    '  public'#10'    procedure Pruefen;|procedure TImport.Pruefen;'#10'begin'#10'  // Nichts zu tun.'#10'end;',
    '  public'#10'    procedure Pruefen;|procedure TImport.Pruefen;'#10'begin'#10'  Writeln;'#10'end;',
    '  protected'#10'    procedure Pruefen; virtual;|procedure TImport.Pruefen;'#10'begin'#10'end;',
    '  private'#10'    procedure WMSize(var Msg: TMessage); message WM_SIZE;|procedure TImport.WMSize(var Msg: TMessage);' +
      #10'begin'#10'end;',
    '  public'#10'    procedure Pruefen;|procedure TImport.Pruefen;'#10'asm'#10'end;');
var
  Item: string;
  Parts: TArray<string>;
begin
  for Item in Cases do
  begin
    Parts := Item.Split(['|']);
    Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyRoutineRule.Create, ImportUnit(Parts[0],
      Parts[1])))), Item);
  end;
  // Klasse mit Interface: der Compiler verlangt jede Methode des Interfaces.
  TRuleAssert.Silent(TEmptyRoutineRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TNotifier = class(TInterfacedObject, IOTANotifier)'#10'    procedure AfterSave;'#10'  end;'#10 +
    'implementation'#10'procedure TNotifier.AfterSave;'#10'begin'#10'end;'#10'end.');
  // Ereignis-Handler aus der Formulardatei.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(TEmptyRoutineRule.Create,
    ImportUnit('  published'#10'    procedure FormCreate(Sender: TObject);',
    'procedure TImport.FormCreate(Sender: TObject);'#10'begin'#10'end;'),
    'object Import: TImport'#10'  OnCreate = FormCreate'#10'end'))));
end;

procedure TUnusedRulesTests.EmptyRoutineSwitchedOff;
var
  Source: string;
begin
  Source := ImportUnit('  public'#10'    procedure Pruefen;', 'procedure TImport.Pruefen;'#10'begin'#10'end;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyRoutineRule.Create, Source,
    '{"rules": {"empty-routine": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyRoutineRule.Create, Source,
    '{"rules": {"empty-routine": {"exclude": ["Alt/**"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TEmptyRoutineRule.Create, Source,
    '{"rules": {"empty-routine": {"exclude": ["Alt/**"]}}}', 'Neu/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnusedRulesTests);
  TDUnitX.RegisterTestFixture(TDuplicateAssignmentTests);

end.
