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
    /// <summary>Bereiche der Korrektur über die Zeilentabelle des Ableitungscaches.</summary>
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
    /// <summary>Ohne Sichtbarkeitsangabe ist eine Methode in TDataModule, TForm, Nachfahren derselben Datei und
    /// unter {$M+} published: Der Designer legt Ereignis-Handler dort an.</summary>
    [Test]
    procedure ImplicitlyPublishedHandlerIsSilent;
    /// <summary>Ohne RTTI (TObject) oder hinter private bleibt die Methode ein Befund.</summary>
    [Test]
    procedure DefaultSectionWithoutTypeInfoReports;
    /// <summary>Die Formulardatei weist die Methode einem Ereignis zu.</summary>
    [Test]
    procedure FormEventHandlerIsSilent;
    [Test]
    procedure CallbackRoutineIsSilent;
    [Test]
    procedure MethodAssignedThroughObjectIsSilent;
    /// <summary>Routinen in einer Tabelle (typisierte Konstante, Array-Literal, Record-Konstante) haben die
    /// Signatur des Elementtyps (#1451).</summary>
    [Test]
    procedure RoutineInTableIsSilent;
    /// <summary>Eine Routine, die nur aus einer anonymen Methode aufgerufen wird, hat eine freie Signatur (#1451).
    /// </summary>
    [Test]
    procedure RoutineCalledFromCallbackReports;
    [Test]
    procedure PlainMethodReports;
    [Test]
    procedure InterfaceImplementationIsSilent;
    [Test]
    procedure OverwrittenAssignmentReports;
    [Test]
    procedure ResultPresetNeverRead;
    [Test]
    procedure ResultReadAtEndIsSilent;
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
  Atlas.Common.Rules.Builtin.Unused.Shared,
  Atlas.Common.Rules.Builtin.Unused.Duplicates,
  Atlas.Common.Rules.Builtin.Unused.EmptyRoutines,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert,
  Atlas.Common.Rules.Profiles;

function Routine(const ABody: string; const AHeader: string;
  const AVars: string): string; overload;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10 + AHeader + #10 + AVars + 'begin'#10 + ABody +
    #10'end;'#10'end.';
end;

function Routine(const ABody: string): string; overload;
begin
  Result := Routine(ABody, 'procedure P;', '');
end;

function Routine(const ABody: string; const AHeader: string): string; overload;
begin
  Result := Routine(ABody, AHeader, '');
end;

function ClassUnit(const AMembers, AImplementation: string; const AAncestors: string): string; overload;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TFoo = class(' + AAncestors + ')'#10 + AMembers +
    #10'  end;'#10'implementation'#10 + AImplementation + #10'end.';
end;

function ClassUnit(const AMembers, AImplementation: string): string; overload;
begin
  Result := ClassUnit(AMembers, AImplementation, 'TObject');
end;

function CrLf(const AText: string): string;
begin
  Result := StringReplace(AText, #10, #13#10, [rfReplaceAll]);
end;

/// <summary>Wendet die erste Korrektur des ersten Treffers an (Zeilen mit #10 oder #13#10).</summary>
function ApplyFirstFix(const ASource: string; const AFindings: TArray<TRuleFinding>): string;
var
  mLines: TArray<string>;
  mEdit: TRuleEdit;

  function OffsetOf(ALine, ACharacter: Integer): Integer;
  var
    mIndex: Integer;
  begin
    Result := 0;
    for mIndex := 0 to ALine - 1 do
    begin
      Inc(Result, Length(mLines[mIndex]) + 1);
    end;
    Inc(Result, ACharacter);
  end;

begin
  mLines := ASource.Split([#10]);
  mEdit := AFindings[0].Fixes[0].Edits[0];
  Result := Copy(ASource, 1, OffsetOf(mEdit.Range.StartPos.Line, mEdit.Range.StartPos.Character)) + mEdit.NewText +
    Copy(ASource, OffsetOf(mEdit.Range.EndPos.Line, mEdit.Range.EndPos.Character) + 1, MaxInt);
end;

procedure TUnusedRulesTests.UnusedLocalReportsWithFix;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := Routine('  I := 1;'#10'  Foo(I);', 'procedure P;', 'var'#10'  I: Integer;'#10'  J: string;'#10);
  mFindings := TRuleAssert.Findings(TUnusedLocalRule.Create, mSource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.Contains(mFindings[0].Message, '"J"');
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual(Routine('  I := 1;'#10'  Foo(I);', 'procedure P;', 'var'#10'  I: Integer;'#10),
    ApplyFirstFix(mSource, mFindings));
end;

procedure TUnusedRulesTests.FixRemovesEmptyVarSection;
var
  mSource: string;
begin
  mSource := Routine('  Foo;', 'procedure P;', 'var'#10'  J: string;'#10);
  Assert.AreEqual(Routine('  Foo;'), ApplyFirstFix(mSource, TRuleAssert.Findings(TUnusedLocalRule.Create, mSource)));
end;

procedure TUnusedRulesTests.FixRemovesNameFromList;
var
  mSource: string;
begin
  mSource := Routine('  J := 1;'#10'  Foo(J);', 'procedure P;', 'var'#10'  I, J: Integer;'#10);
  Assert.AreEqual(Routine('  J := 1;'#10'  Foo(J);', 'procedure P;', 'var'#10'  J: Integer;'#10),
    ApplyFirstFix(mSource, TRuleAssert.Findings(TUnusedLocalRule.Create, mSource)));
  mSource := Routine('  I := 1;'#10'  Foo(I);', 'procedure P;', 'var'#10'  I, J: Integer;'#10);
  Assert.AreEqual(Routine('  I := 1;'#10'  Foo(I);', 'procedure P;', 'var'#10'  I: Integer;'#10),
    ApplyFirstFix(mSource, TRuleAssert.Findings(TUnusedLocalRule.Create, mSource)));
end;

procedure TUnusedRulesTests.RemoveVariableFixInCrLfFile;
var
  mSource: string;
begin
  mSource := CrLf(Routine('  I := 1;'#10'  Foo(I);', 'procedure P;', 'var'#10'  I: Integer;'#10'  J: string;'#10));
  Assert.AreEqual(CrLf(Routine('  I := 1;'#10'  Foo(I);', 'procedure P;', 'var'#10'  I: Integer;'#10)),
    ApplyFirstFix(mSource, TRuleAssert.Findings(TUnusedLocalRule.Create, mSource)));
  mSource := CrLf(Routine('  Foo;', 'procedure P;', 'var'#10'  J: string;'#10));
  Assert.AreEqual(CrLf(Routine('  Foo;')), ApplyFirstFix(mSource, TRuleAssert.Findings(TUnusedLocalRule.Create, mSource)));
  mSource := CrLf(Routine('  J := 1;'#10'  Foo(J);', 'procedure P;', 'var'#10'  I, J: Integer;'#10));
  Assert.AreEqual(CrLf(Routine('  J := 1;'#10'  Foo(J);', 'procedure P;', 'var'#10'  J: Integer;'#10)),
    ApplyFirstFix(mSource, TRuleAssert.Findings(TUnusedLocalRule.Create, mSource)));
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
  mFindings: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TUnusedLocalRule.Create,
    Routine('  {$IFDEF DEBUG}'#10'  Log(I);'#10'  {$ENDIF}', 'procedure P;', 'var'#10'  I: Integer;'#10));
  // Mit Direktiven, aber nirgends erwähnt: Treffer mit niedriger Konfidenz.
  mFindings := TRuleAssert.Findings(TUnusedLocalRule.Create,
    Routine('  {$IFDEF DEBUG}'#10'  Log;'#10'  {$ENDIF}', 'procedure P;', 'var'#10'  I: Integer;'#10),
    '{"minConfidence": "low"}');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(mFindings[0].Confidence));
end;

procedure TUnusedRulesTests.UnusedInlineVarReports;
var
  mSource: string;
begin
  mSource := Routine('  var X := 1;'#10'  Foo;');
  Assert.AreEqual(Routine('  Foo;'), ApplyFirstFix(mSource, TRuleAssert.Findings(TUnusedLocalRule.Create, mSource)));
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
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TUnusedLocalRule.Create,
    Routine('  Foo;', 'procedure P;', 'var'#10'  Dummy1: Integer;'#10),
    '{"rules": {"unused-local": {"ignore": ["dummy*"]}}}');
  Assert.AreEqual(0, Integer(Length(mFindings)));
end;

procedure TUnusedRulesTests.UnusedParameterReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TUnusedParameterRule.Create, Routine('  Foo(A);', 'procedure P(A, B: Integer);'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, '"B"');
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(mFindings[0].Confidence));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
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

procedure TUnusedRulesTests.ImplicitlyPublishedHandlerIsSilent;
const
  cImpl = 'procedure TFoo.DataSet1BeforePost(DataSet: TDataSet);'#10'begin'#10'end;';
begin
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    ClassUnit('    procedure DataSet1BeforePost(DataSet: TDataSet);', cImpl, 'TDataModule'));
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    ClassUnit('    procedure DataSet1BeforePost(DataSet: TDataSet);'#10'  private'#10'    FWert: Integer;', cImpl,
      'Vcl.Forms.TForm'));
  // Vorfahr in derselben Datei.
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class(TForm)'#10'  end;'#10 +
    '  TFoo = class(TBasis)'#10'    procedure DataSet1BeforePost(DataSet: TDataSet);'#10'  end;'#10 +
    'implementation'#10 + cImpl + #10'end.');
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    'unit U;'#10'interface'#10'type'#10'  {$M+}'#10'  TFoo = class'#10 +
    '    procedure DataSet1BeforePost(DataSet: TDataSet);'#10'  end;'#10'  {$M-}'#10 +
    'implementation'#10 + cImpl + #10'end.');
end;

procedure TUnusedRulesTests.DefaultSectionWithoutTypeInfoReports;
const
  cImpl = 'procedure TFoo.Run(A: Integer);'#10'begin'#10'end;';
begin
  TRuleAssert.Reports(TUnusedParameterRule.Create, ClassUnit('    procedure Run(A: Integer);', cImpl));
  TRuleAssert.Reports(TUnusedParameterRule.Create,
    ClassUnit('  private'#10'    procedure Run(A: Integer);', cImpl, 'TDataModule'));
  // Lokaler Vorfahr ohne RTTI.
  TRuleAssert.Reports(TUnusedParameterRule.Create,
    'unit U;'#10'interface'#10'type'#10'  TBasis = class'#10'  end;'#10 +
    '  TFoo = class(TBasis)'#10'    procedure Run(A: Integer);'#10'  end;'#10 +
    'implementation'#10 + cImpl + #10'end.');
end;

procedure TUnusedRulesTests.FormEventHandlerIsSilent;
var
  mSource: string;
  mRule: IRule;
begin
  // Erst in eine Interface-Variable: an den const-Parameter direkt übergeben würde die Regel nie frei.
  mRule := TUnusedParameterRule.Create;
  mSource := ClassUnit('  public'#10'    procedure DataSet1BeforePost(DataSet: TDataSet);',
    'procedure TFoo.DataSet1BeforePost(DataSet: TDataSet);'#10'begin'#10'end;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.FormFindings(mRule, mSource,
    'object Foo: TFoo'#10'  object DataSet1: TClientDataSet'#10'    BeforePost = DataSet1BeforePost'#10 +
    '  end'#10'end'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.FormFindings(mRule, mSource,
    'object Foo: TFoo'#10'  Caption = ''DataSet1BeforePostX'''#10'end'))));
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

procedure TUnusedRulesTests.RoutineInTableIsSilent;
begin
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'type'#10'  TFix = function(A, B: Integer): Integer;'#10 +
    'function Erste(A, B: Integer): Integer;'#10'begin'#10'  Result := A;'#10'end;'#10 +
    'function Zweite(A, B: Integer): Integer;'#10'begin'#10'  Result := B;'#10'end;'#10 +
    'const'#10'  cFixes: array[0..1] of TFix = (Erste, Zweite);'#10'end.');
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'function Erste(A, B: Integer): Integer;'#10'begin'#10 +
    '  Result := A;'#10'end;'#10'procedure P;'#10'var'#10'  mFixes: TArray<TFix>;'#10'begin'#10 +
    '  mFixes := [Erste];'#10'end;'#10'end.');
  TRuleAssert.Silent(TUnusedParameterRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'function Erste(A, B: Integer): Integer;'#10'begin'#10 +
    '  Result := A;'#10'end;'#10'const'#10'  cEintrag: TEintrag = (Name: ''x''; Lauf: Erste);'#10'end.');
end;

procedure TUnusedRulesTests.RoutineCalledFromCallbackReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TUnusedParameterRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'function Bau(AParent: TObject): TObject;'#10'begin'#10 +
    '  Result := nil;'#10'end;'#10'procedure P;'#10'begin'#10'  Register(function(AParent: TObject): TObject'#10 +
    '    begin'#10'      Result := Bau(AParent);'#10'    end);'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.Contains(mFindings[0].Message, '"AParent"');
  Assert.AreEqual(3, mFindings[0].Range.StartPos.Line);
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

function FindingLines(const AFindings: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFindings do
  begin
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ':' + mFinding.Message + '|';
  end;
end;

// Vorbelegung von Result, die jeder Weg überschreibt (#1345, wie H2077): vor try … except, vor einer Schleife
// mit Exit(Wert) und eigener Zuweisung danach; dazu eine lokale Variable vor case.
procedure TUnusedRulesTests.ResultPresetNeverRead;
begin
  Assert.AreEqual('5:Der an "Result" zugewiesene Wert wird nie gelesen (wie H2077)|',
    FindingLines(TRuleAssert.Findings(TUnusedAssignmentRule.Create, Routine('  Result := False;'#10'  try'#10 +
    '    Result := Load;'#10'  except'#10'    Result := False;'#10'  end;', 'function P: Boolean;'))));
  Assert.AreEqual('7:Der an "Result" zugewiesene Wert wird nie gelesen (wie H2077)|',
    FindingLines(TRuleAssert.Findings(TUnusedAssignmentRule.Create, Routine('  Result := -1;'#10 +
    '  for I := 0 to N do'#10'    if I > 3 then'#10'      Exit(I);'#10'  Result := -2;',
    'function P(N: Integer): Integer;', 'var'#10'  I: Integer;'#10))));
  Assert.AreEqual('7:Der an "K" zugewiesene Wert wird nie gelesen (wie H2077)|',
    FindingLines(TRuleAssert.Findings(TUnusedAssignmentRule.Create, Routine('  K := 0;'#10 +
    '  case N of'#10'    1: K := 2;'#10'    2: K := 3;'#10'  else'#10'    Exit;'#10'  end;'#10'  Result := K;',
    'function P(N: Integer): Integer;', 'var'#10'  K: Integer;'#10))));
end;

procedure TUnusedRulesTests.ResultReadAtEndIsSilent;
begin
  // Normales Ende, Lesen nach einer Ausnahme im except-Teil, Ergebnis ohne Typangabe, verwaltete Typen, Inc.
  TRuleAssert.Silent(TUnusedAssignmentRule.Create, Routine('  Result := False;'#10'  if N > 0 then'#10 +
    '    Result := True;', 'function P(N: Integer): Boolean;'));
  TRuleAssert.Silent(TUnusedAssignmentRule.Create, Routine('  Result := nil;'#10'  try'#10 +
    '    Result := Load;'#10'  except'#10'    Result.Free;'#10'    raise;'#10'  end;', 'function P: TObject;'));
  TRuleAssert.Silent(TUnusedAssignmentRule.Create, Routine('  Result := 1;'#10'  Result := 2;', 'function TA.P;'));
  TRuleAssert.Silent(TUnusedAssignmentRule.Create, Routine('  Result := '''';'#10'  Result := ''a'';',
    'function P: string;'));
  TRuleAssert.Silent(TUnusedAssignmentRule.Create, Routine('  Result := 0;'#10'  for I := 1 to N do'#10 +
    '    Inc(Result, I);', 'function P(N: Integer): Integer;', 'var'#10'  I: Integer;'#10));
end;

procedure TUnusedRulesTests.OverwrittenAssignmentReports;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TUnusedAssignmentRule.Create,
    Routine('  I := 1;'#10'  I := 2;'#10'  J := I;', 'procedure P;', 'var'#10'  I, J: Integer;'#10));
  // I := 1 wird überschrieben; der an J zugewiesene Wert wird nie gelesen.
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(9, mFindings[1].Range.StartPos.Line);
end;

procedure TUnusedRulesTests.AssignmentCodeOnlyForUnmanagedTypes;
const
  // Verwaltete Typen: dcc meldet H2077 nicht.
  cManagedTypes: array[0..4] of string = ('string', 'TArray<Integer>', 'Variant', 'TBytes', 'TMitText');
var
  mFindings: TArray<TRuleFinding>;
  mTypeName: string;
begin
  mFindings := TRuleAssert.Findings(TUnusedAssignmentRule.Create,
    Routine('  I := 1;', 'procedure P;', 'var'#10'  I: Integer;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Der an "I" zugewiesene Wert wird nie gelesen (wie H2077)', mFindings[0].Message);
  for mTypeName in cManagedTypes do
  begin
    mFindings := TRuleAssert.Findings(TUnusedAssignmentRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
      'type'#10'  TMitText = record'#10'    Text: string;'#10'  end;'#10'procedure P;'#10'var'#10'  X: ' + mTypeName +
      ';'#10'begin'#10'  X := Default(' + mTypeName + ');'#10'end;'#10'end.');
    Assert.AreEqual(1, Integer(Length(mFindings)), mTypeName);
    Assert.AreEqual('Der an "X" zugewiesene Wert wird nie gelesen', mFindings[0].Message, mTypeName);
  end;
  // Inline-Variable ohne Typangabe: Typ unbekannt, also ohne Code.
  mFindings := TRuleAssert.Findings(TUnusedAssignmentRule.Create, Routine('  var I := 1;'#10'  I := 2;'));
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('Der an "I" zugewiesene Wert wird nie gelesen', mFindings[0].Message);
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
  cClearValues: array[0..4] of string = ('nil', '''''', 'Default(TErgebnis)', 'TErgebnis.Empty', 'Default( TErgebnis )');
var
  mValue: string;
  mFindings: TArray<TRuleFinding>;
begin
  for mValue in cClearValues do
  begin
    // Started := Default(…) am Testende, Lookup := nil vor Resolver.Free.
    TRuleAssert.Silent(TUnusedAssignmentRule.Create,
      Routine('  X := Load;'#10'  Result := X.Text;'#10'  X := ' + mValue + ';'#10'  Work;', 'function F: string;',
        'var'#10'  X: TErgebnis;'#10));
    // Leeren im finally: Der Wert davor stammt aus dem try.
    TRuleAssert.Silent(TUnusedAssignmentRule.Create,
      Routine('  try'#10'    X := Load;'#10'    Result := X.Text;'#10'  finally'#10'    X := ' + mValue + ';'#10'  end;',
        'function F: string;', 'var'#10'  X: TErgebnis;'#10));
    // Ohne vorherigen Wert ist das Leeren überflüssig.
    mFindings := TRuleAssert.Findings(TUnusedAssignmentRule.Create,
      Routine('  X := ' + mValue + ';'#10'  Work;', 'procedure P;', 'var'#10'  X: TErgebnis;'#10));
    Assert.AreEqual(1, Integer(Length(mFindings)), mValue);
  end;
  // Andere Werte am Ende bleiben Befunde.
  mFindings := TRuleAssert.Findings(TUnusedAssignmentRule.Create,
    Routine('  X := Load;'#10'  Result := X.Text;'#10'  X := Load;', 'function F: string;', 'var'#10'  X: TErgebnis;'#10));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(9, mFindings[0].Range.StartPos.Line);
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
function Formular(const ABody: string; const AVars: string): string; overload;
begin
  Result := Routine(ABody, 'procedure TForm1.Init;', AVars);
end;

function Formular(const ABody: string): string; overload;
begin
  Result := Formular(ABody, '');
end;

function DuplicateCount(const ASource: string; const AConfig: string): Integer; overload;
begin
  Result := Length(TRuleAssert.Findings(TDuplicateAssignmentRule.Create, ASource, AConfig));
end;

function DuplicateCount(const ASource: string): Integer; overload;
begin
  Result := DuplicateCount(ASource, '');
end;

procedure TDuplicateAssignmentTests.IssueExampleWithJump;
var
  mFindings: TArray<TRuleFinding>;
begin
  mFindings := TRuleAssert.Findings(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Left := 8;'#10'  Panel.Left := 40;'#10'  Panel.Width := 200;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('duplicate-assignment', mFindings[0].RuleId);
  Assert.AreEqual('Panel.Left wird in Zeile 6 schon gesetzt; gemeint ist vermutlich Panel.Top.', mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual(6, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(12, mFindings[0].Range.EndPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.IsTrue(mFindings[0].Fixes[0].HasJump);
  Assert.AreEqual(5, mFindings[0].Fixes[0].JumpTo.Line);
  // Die korrigierte Form ist still.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Left := 8;'#10'  Panel.Top := 40;'#10'  Panel.Width := 200;'));
end;

procedure TDuplicateAssignmentTests.CounterpartOnlyWhenMissing;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Top wird schon gesetzt: keine Vermutung, nur der Verlust.
  mFindings := TRuleAssert.Findings(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Top := 1;'#10'  Panel.Left := 8;'#10'  Panel.Left := 40;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Panel.Left wird in Zeile 7 schon gesetzt; der erste Wert geht ungelesen verloren.',
    mFindings[0].Message);
  // Ohne Gegenstück in der Tabelle.
  mFindings := TRuleAssert.Findings(TDuplicateAssignmentRule.Create,
    Formular('  Caption := ''A'';'#10'  Caption := ''B'';'));
  Assert.AreEqual('Caption wird in Zeile 6 schon gesetzt; der erste Wert geht ungelesen verloren.',
    mFindings[0].Message);
  mFindings := TRuleAssert.Findings(TDuplicateAssignmentRule.Create,
    Formular('  Bild.Height := 8;'#10'  Bild.height := 40;'));
  Assert.AreEqual('Bild.height wird in Zeile 6 schon gesetzt; gemeint ist vermutlich Bild.Width.',
    mFindings[0].Message);
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
  mIssues: TArray<TConfigurationIssue>;
begin
  // Standard: Visible und Enabled dürfen doppelt gesetzt werden.
  TRuleAssert.Silent(TDuplicateAssignmentRule.Create,
    Formular('  Panel.Visible := True;'#10'  Panel.Visible := True;'#10'  Enabled := True;'#10'  Enabled := True;'));
  Assert.AreEqual(1, DuplicateCount(Formular('  Panel.Visible := True;'#10'  Panel.Visible := True;'),
    '{"rules": {"duplicate-assignment": {"allowProperties": ["Cap*"]}}}'));
  Assert.AreEqual(0, DuplicateCount(Formular('  Panel.Caption := ''A'';'#10'  Panel.Caption := ''B'';'),
    '{"rules": {"duplicate-assignment": {"allowProperties": ["cap*"]}}}'));
  TConfigurationParser.Parse('{"rules": {"duplicate-assignment": {"allowProperties": [1]}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('"allowProperties" muss eine Liste von Texten sein', mIssues[0].Message);
  TConfigurationParser.Parse('{"rules": {"duplicate-assignment": {"allowProperties": ["Visible"]}}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;

procedure TDuplicateAssignmentTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := Formular('  Panel.Left := 8;'#10'  Panel.Left := 40;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateAssignmentRule.Create, mSource,
    '{"rules": {"duplicate-assignment": "off"}}', 'Source/U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateAssignmentRule.Create, mSource,
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
  mFindings: TArray<TRuleFinding>;
  mFix: TRuleFix;
  mTree: TSyntaxTree;
begin
  mFindings := TRuleAssert.Findings(TEmptyRoutineRule.Create, ASource);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Result := '';
  for mFix in mFindings[0].Fixes do
  begin
    if mFix.Title = ATitle then
    begin
      Result := TChangeSignature.ApplyEdits(ASource, mFix.Edits);
    end;
  end;
  Assert.AreNotEqual('', Result, ATitle);
  mTree := TPascalParser.Parse(Result);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), Result);
  finally
    mTree.Free;
  end;
end;

procedure TUnusedRulesTests.EmptyRoutineReported;
var
  mFindings: TArray<TRuleFinding>;
begin
  Assert.IsFalse(TRuleProfiles.IsExperimental((TEmptyRoutineRule.Create as IRule).Descriptor.Id), 'Standard an');
  mFindings := TRuleAssert.Findings(TEmptyRoutineRule.Create, ImportUnit('  public'#10'    procedure Pruefen;',
    'procedure TImport.Pruefen;'#10'begin'#10'end;'));
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Pruefen ist leer; entweder fehlt der Inhalt oder die Methode kann weg.', mFindings[0].Message);
  Assert.AreEqual(8, mFindings[0].Range.StartPos.Line);
  // Öffentlich: nur der Kommentar, nicht das Entfernen.
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  // Routinen, auch lokale und mit leerer Anweisung.
  mFindings := TRuleAssert.Findings(TEmptyRoutineRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure Aussen;'#10'  procedure Innen;'#10'  begin'#10'  end;'#10'begin'#10'  Innen;'#10'end;'#10 +
    'procedure Leer;'#10'begin'#10'  ;'#10'end;'#10'end.');
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('Innen ist leer; entweder fehlt der Inhalt oder die Routine kann weg.', mFindings[0].Message);
end;

procedure TUnusedRulesTests.EmptyRoutineCommentFix;
var
  mSource: string;
begin
  mSource := ImportUnit('  public'#10'    procedure Pruefen;', 'procedure TImport.Pruefen;'#10'begin'#10'end;');
  Assert.AreEqual(ImportUnit('  public'#10'    procedure Pruefen;', 'procedure TImport.Pruefen;'#10'begin'#10 +
    '  // Absichtlich leer.'#10'end;'), EmptyFixed(mSource, 'Kommentar einfügen'));
  // Die korrigierte Form wird nicht mehr gemeldet.
  TRuleAssert.Silent(TEmptyRoutineRule.Create, EmptyFixed(mSource, 'Kommentar einfügen'));
end;

procedure TUnusedRulesTests.EmptyRoutineRemoveFix;
var
  mSource: string;
begin
  // Private Methode ohne Verweis: Deklaration samt XML-Doku und Rumpf verschwinden.
  mSource := ImportUnit('  private'#10'    /// <summary>Prüft.</summary>'#10'    procedure Pruefen;'#10 +
    '  public'#10'    procedure Laden;', 'procedure TImport.Laden;'#10'begin'#10'  Writeln;'#10'end;'#10#10 +
    'procedure TImport.Pruefen;'#10'begin'#10'end;');
  Assert.AreEqual(ImportUnit('  private'#10'  public'#10'    procedure Laden;', 'procedure TImport.Laden;'#10 +
    'begin'#10'  Writeln;'#10'end;'), EmptyFixed(mSource, 'Methode entfernen'));
  // Routine nur im implementation-Teil, mit forward.
  mSource := 'unit U;'#10'interface'#10'implementation'#10'procedure Leer; forward;'#10#10'procedure Leer;'#10 +
    'begin'#10'end;'#10'end.';
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'end.', EmptyFixed(mSource, 'Routine entfernen'));
  // Mit Verweis oder im interface: nur der Kommentar.
  mSource := ImportUnit('  private'#10'    procedure Pruefen;'#10'  public'#10'    procedure Laden;',
    'procedure TImport.Laden;'#10'begin'#10'  Pruefen;'#10'end;'#10'procedure TImport.Pruefen;'#10'begin'#10'end;');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TEmptyRoutineRule.Create, mSource)[0].Fixes)));
  mSource := 'unit U;'#10'interface'#10'procedure Leer;'#10'implementation'#10'procedure Leer;'#10'begin'#10'end;'#10 +
    'end.';
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TEmptyRoutineRule.Create, mSource)[0].Fixes)));
end;

procedure TUnusedRulesTests.EmptyRoutineSilentCases;
const
  cCases: array[0..4] of string = (
    '  public'#10'    procedure Pruefen;|procedure TImport.Pruefen;'#10'begin'#10'  // Nichts zu tun.'#10'end;',
    '  public'#10'    procedure Pruefen;|procedure TImport.Pruefen;'#10'begin'#10'  Writeln;'#10'end;',
    '  protected'#10'    procedure Pruefen; virtual;|procedure TImport.Pruefen;'#10'begin'#10'end;',
    '  private'#10'    procedure WMSize(var Msg: TMessage); message WM_SIZE;|procedure TImport.WMSize(var Msg: TMessage);' +
      #10'begin'#10'end;',
    '  public'#10'    procedure Pruefen;|procedure TImport.Pruefen;'#10'asm'#10'end;');
var
  mItem: string;
  mParts: TArray<string>;
begin
  for mItem in cCases do
  begin
    mParts := mItem.Split(['|']);
    Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyRoutineRule.Create, ImportUnit(mParts[0],
      mParts[1])))), mItem);
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
  mSource: string;
begin
  mSource := ImportUnit('  public'#10'    procedure Pruefen;', 'procedure TImport.Pruefen;'#10'begin'#10'end;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyRoutineRule.Create, mSource,
    '{"rules": {"empty-routine": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TEmptyRoutineRule.Create, mSource,
    '{"rules": {"empty-routine": {"exclude": ["Alt/**"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TEmptyRoutineRule.Create, mSource,
    '{"rules": {"empty-routine": {"exclude": ["Alt/**"]}}}', 'Neu/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TUnusedRulesTests);
  TDUnitX.RegisterTestFixture(TDuplicateAssignmentTests);

end.
