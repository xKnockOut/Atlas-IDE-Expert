unit Atlas.Common.Rules.Builtin.Declarations.Tests;

// Tests für declared-not-implemented und implemented-not-declared (#124) sowie
// signature-mismatch (#996) mit dem Angleichen abweichender Köpfe (#100):
// Beispiel aus dem Issue, Anzahl, Ergebnistyp, Namen, Modifizierer,
// Aufrufkonvention, nächstliegende Überladung, Abschalten und Ausnahmen;
// interface-not-implemented (#1000): fehlende Interface-Methoden (E2291),
// abweichender Kopf (E2211), Zuordnung ohne Interface (E2265), geerbte
// Methoden, Zuordnungen, implements und unbekannte Vorfahren.
// field-after-method (#986): Beispiel mit beiden Korrekturen, Attribute und
// Kommentare wandern mit, Records mit var zuerst, Feld neben anderem auf der
// Zeile, neue Abschnitte und var, Zweige bedingter Übersetzung, Abschalten.
// overload-directive-missing (#987): Beispiel mit Korrektur, E2267, E2252,
// E2301, Routinen der Unit über interface und implementation, verschachtelte
// Routinen, stille Fälle (var, Generika, Operatoren, forward, {$IF}-Zweige).
// default-parameter (#976): Beispiel mit Überladungen in Deklaration und Rumpf,
// Methoden mit mehreren Standardwerten, Routinen nur im implementation-Teil,
// Meldung ohne Korrektur bei vorgegebener Signatur, Abschalten.
// duplicate-declaration (#988): Beispiel mit Korrekturen, Bereiche (Routine,
// Typ, Record mit variantem Teil, Unit), uses mit checkUses, stille Fälle und
// Optionen.
// Sonderformen der Deklaration (#1325): die Minimalfälle F02, F03, F06, F07,
// F13 und F18 der FP-Prüfung sowie asm- und external-Rümpfe, override und ein
// gleichnamiger generischer Typ neben dem nicht generischen sind still; echte Überladungen ohne overload und fehlende Rümpfe werden weiter
// gemeldet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDeclarationRulesTests = class
  public
    [Test]
    procedure MissingBodyReportsWithFix;
    [Test]
    procedure ImplementedMethodIsSilent;
    [Test]
    procedure MissingOverloadIsReported;
    [Test]
    procedure AbstractAndExternalAreSilent;
    [Test]
    procedure GenericTypeIsSilent;
    [Test]
    procedure ConditionalDeclarationIsSilent;
    [Test]
    procedure IncludeLowersConfidence;
    [Test]
    procedure BodyWithoutDeclarationReports;
    [Test]
    procedure FixAddsDeclarationToExistingPrivate;
    [Test]
    procedure FixCreatesPrivateSection;
    [Test]
    procedure GlobalRoutineIsSilent;
    [Test]
    procedure ModifierMismatchAlignsBothWays;
    [Test]
    procedure SyncActionCanBeSwitchedOff;
    [Test]
    procedure DefaultsStayInDeclaration;
    [Test]
    procedure AmbiguousOverloadOffersNoAlignment;
    [Test]
    procedure SignatureMismatchIssueExample;
    [Test]
    procedure SignatureMismatchVariants;
    [Test]
    procedure SignatureMismatchOffAndExclude;
    [Test]
    procedure InterfaceIssueExample;
    [Test]
    procedure InterfaceImplementationsThatCount;
    [Test]
    procedure InterfaceUnknownAncestorIsSilent;
    [Test]
    procedure InterfaceDifferentSignature;
    [Test]
    procedure InterfaceResolutionForUnlistedInterface;
    [Test]
    procedure InterfaceOffAndExclude;
    [Test]
    procedure FieldAfterMethodIssueExample;
    [Test]
    procedure FieldAfterMethodVariants;
    [Test]
    procedure FieldAfterMethodSilentCases;
    [Test]
    procedure FieldAfterMethodConditional;
    [Test]
    procedure FieldAfterMethodOffAndExclude;
    [Test]
    procedure OverloadIssueExample;
    [Test]
    procedure OverloadVariants;
    [Test]
    procedure OverloadSilentCases;
    [Test]
    procedure OverloadOffAndExclude;
    [Test]
    procedure SpecialFormClassConstructor;
    [Test]
    procedure SpecialFormMethodResolution;
    [Test]
    procedure SpecialFormGenericConstraints;
    [Test]
    procedure SpecialFormEmptyParentheses;
    [Test]
    procedure SpecialFormShortImplementation;
    [Test]
    procedure SpecialFormOpenArrayElementType;
    [Test]
    procedure SpecialFormAsmExternalAndOverride;
    [Test]
    procedure SpecialFormGenericNamesake;
    [Test]
    procedure SpecialFormCounterChecks;
    [Test]
    procedure DuplicateDeclarationIssueExample;
    [Test]
    procedure DuplicateDeclarationScopes;
    [Test]
    procedure DuplicateDeclarationUses;
    [Test]
    procedure DuplicateDeclarationSilentCases;
    [Test]
    procedure DuplicateDeclarationOptions;
    [Test]
    procedure VariantManagedIssueExample;
    [Test]
    procedure VariantManagedKinds;
    [Test]
    procedure VariantManagedMoveFixes;
    [Test]
    procedure VariantManagedGenericAndFile;
    [Test]
    procedure VariantManagedFromIndex;
    [Test]
    procedure VariantManagedSilentCases;
    [Test]
    procedure VariantManagedOffAndExclude;
    [Test]
    procedure TypeTooLargeIssueExample;
    [Test]
    procedure TypeTooLargeRecordsAndNames;
    [Test]
    procedure TypeTooLargeGenericInstance;
    [Test]
    procedure TypeTooLargeSilentCases;
    [Test]
    procedure TypeTooLargeOffAndExclude;
    [Test]
    procedure DefaultParameterReportedWithFix;
    [Test]
    procedure DefaultParameterMethodWithSeveral;
    [Test]
    procedure DefaultParameterImplementationOnly;
    [Test]
    procedure DefaultParameterWithoutFix;
    [Test]
    procedure DefaultParameterSwitchedOff;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rules.Builtin.Declarations,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert;

function ClassUnit(const AMembers, AImplementation: string; const AHead: string = 'TFoo = class'): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  ' + AHead + #10 + AMembers + #10'  end;'#10 +
    'implementation'#10 + AImplementation + #10'end.';
end;

/// <summary>Wendet die erste Korrektur des ersten Treffers an (Zeilen mit #10, Einfügung in einer Zeile).</summary>
function ApplyFirstFix(const AText: string; const AFindings: TArray<TRuleFinding>): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Line: string;
begin
  Edit := AFindings[0].Fixes[0].Edits[0];
  Lines := AText.Split([#10]);
  Line := Lines[Edit.Range.StartPos.Line];
  Lines[Edit.Range.StartPos.Line] := Copy(Line, 1, Edit.Range.StartPos.Character) + Edit.NewText +
    Copy(Line, Edit.Range.EndPos.Character + 1, MaxInt);
  Result := string.Join(#10, Lines);
end;

function ParsesCleanly(const AText: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

procedure TDeclarationRulesTests.MissingBodyReportsWithFix;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDeclaredNotImplementedRule.Create,
    ClassUnit('    procedure Lauf(A: Integer);', ''));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.Contains(Findings[0].Message, 'TFoo.Lauf');
  Assert.AreEqual(4, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.Contains(Findings[0].Fixes[0].Edits[0].NewText, 'procedure TFoo.Lauf(A: Integer);');
end;

procedure TDeclarationRulesTests.ImplementedMethodIsSilent;
begin
  TRuleAssert.Silent(TDeclaredNotImplementedRule.Create,
    ClassUnit('    procedure Lauf(A: Integer);', 'procedure TFoo.Lauf(A: Integer);'#10'begin'#10'end;'));
  TRuleAssert.Silent(TImplementedNotDeclaredRule.Create,
    ClassUnit('    procedure Lauf(A: Integer);', 'procedure TFoo.Lauf(A: Integer);'#10'begin'#10'end;'));
end;

procedure TDeclarationRulesTests.MissingOverloadIsReported;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDeclaredNotImplementedRule.Create,
    ClassUnit('    procedure Lauf(A: Integer); overload;'#10'    procedure Lauf(const S: string); overload;',
      'procedure TFoo.Lauf(A: Integer);'#10'begin'#10'end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
end;

procedure TDeclarationRulesTests.AbstractAndExternalAreSilent;
begin
  TRuleAssert.Silent(TDeclaredNotImplementedRule.Create,
    ClassUnit('    procedure Lauf; virtual; abstract;'#10'    procedure Fremd; external ''x.dll'';', ''));
end;

procedure TDeclarationRulesTests.GenericTypeIsSilent;
begin
  TRuleAssert.Silent(TDeclaredNotImplementedRule.Create,
    ClassUnit('    procedure Lauf(A: T);', '', 'TFoo<T> = class'));
end;

procedure TDeclarationRulesTests.ConditionalDeclarationIsSilent;
begin
  TRuleAssert.Silent(TDeclaredNotImplementedRule.Create,
    ClassUnit('{$IFDEF DEBUG}'#10'    procedure Lauf;'#10'{$ENDIF}', ''));
end;

procedure TDeclarationRulesTests.IncludeLowersConfidence;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDeclaredNotImplementedRule.Create,
    ClassUnit('    procedure Lauf;', '{$I Teile.inc}'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(Ord(TRuleConfidence.Medium), Ord(Findings[0].Confidence));
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Findings[0].Severity));
end;

procedure TDeclarationRulesTests.BodyWithoutDeclarationReports;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TImplementedNotDeclaredRule.Create,
    ClassUnit('    procedure Lauf;', 'procedure TFoo.Lauf;'#10'begin'#10'end;'#10 +
      'procedure TFoo.Extra(A: Integer);'#10'begin'#10'end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.Contains(Findings[0].Message, 'TFoo.Extra');
end;

procedure TDeclarationRulesTests.FixAddsDeclarationToExistingPrivate;
var
  Source, Fixed: string;
begin
  Source := ClassUnit('  private'#10'    FWert: Integer;', 'function TFoo.Extra(A: Integer): string;'#10'begin'#10'end;');
  Fixed := ApplyFirstFix(Source, TRuleAssert.Findings(TImplementedNotDeclaredRule.Create, Source));
  Assert.AreEqual(ClassUnit('  private'#10'    function Extra(A: Integer): string;'#10'    FWert: Integer;',
    'function TFoo.Extra(A: Integer): string;'#10'begin'#10'end;'), Fixed);
  Assert.IsTrue(ParsesCleanly(Fixed));
end;

procedure TDeclarationRulesTests.FixCreatesPrivateSection;
var
  Source, Fixed: string;
begin
  Source := ClassUnit('  public'#10'    procedure Lauf;', 'procedure TFoo.Lauf;'#10'begin'#10'end;'#10 +
    'procedure TFoo.Extra;'#10'begin'#10'end;');
  Fixed := ApplyFirstFix(Source, TRuleAssert.Findings(TImplementedNotDeclaredRule.Create, Source));
  Assert.AreEqual(ClassUnit('  public'#10'    procedure Lauf;'#10'  private'#10'    procedure Extra;',
    'procedure TFoo.Lauf;'#10'begin'#10'end;'#10'procedure TFoo.Extra;'#10'begin'#10'end;'), Fixed);
  Assert.IsTrue(ParsesCleanly(Fixed));
  TRuleAssert.Silent(TImplementedNotDeclaredRule.Create, Fixed);
end;

procedure TDeclarationRulesTests.GlobalRoutineIsSilent;
begin
  TRuleAssert.Silent(TImplementedNotDeclaredRule.Create,
    'unit U;'#10'interface'#10'implementation'#10'procedure Hilfe;'#10'begin'#10'end;'#10'end.');
end;

/// <summary>Wendet alle Edits einer Korrektur an (jedes Edit in einer Zeile, von hinten nach vorn).</summary>
function ApplyAll(const AText: string; const AFix: TRuleFix): string;
var
  Lines: TArray<string>;
  Edit: TRuleEdit;
  Line: string;
  Index: Integer;
begin
  Lines := AText.Split([#10]);
  for Index := High(AFix.Edits) downto 0 do
  begin
    Edit := AFix.Edits[Index];
    Line := Lines[Edit.Range.StartPos.Line];
    Lines[Edit.Range.StartPos.Line] := Copy(Line, 1, Edit.Range.StartPos.Character) + Edit.NewText +
      Copy(Line, Edit.Range.EndPos.Character + 1, MaxInt);
  end;
  Result := string.Join(#10, Lines);
end;

procedure TDeclarationRulesTests.SyncActionCanBeSwitchedOff;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // refactoring.syncSignatures aus (#100): Meldung bleibt, ohne Angleich-Aktionen.
  Source := ClassUnit('    procedure Foo(A: Integer);', 'procedure TFoo.Foo(const A: Integer);'#10'begin'#10'end;');
  Findings := TRuleAssert.Findings(TSignatureMismatchRule.Create, Source,
    '{"refactoring": {"syncSignatures": false}}');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TDeclarationRulesTests.ModifierMismatchAlignsBothWays;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := ClassUnit('    procedure Foo(A: Integer);', 'procedure TFoo.Foo(const A: Integer);'#10'begin'#10'end;');
  Findings := TRuleAssert.Findings(TSignatureMismatchRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Foo weicht von der Deklaration ab: A mit const (wie E2037).', Findings[0].Message);
  // Rumpf angleichen zuerst, die Deklaration als zweite Aktion.
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes)));
  Assert.IsFalse(Findings[0].Fixes[0].Alternative);
  Assert.IsTrue(Findings[0].Fixes[1].Alternative);
  Assert.AreEqual(ClassUnit('    procedure Foo(A: Integer);', 'procedure TFoo.Foo(A: Integer);'#10'begin'#10'end;'),
    ApplyAll(Source, Findings[0].Fixes[0]));
  Assert.AreEqual(ClassUnit('    procedure Foo(const A: Integer);',
    'procedure TFoo.Foo(const A: Integer);'#10'begin'#10'end;'), ApplyAll(Source, Findings[0].Fixes[1]));
  TRuleAssert.Silent(TSignatureMismatchRule.Create, ApplyAll(Source, Findings[0].Fixes[0]));
  TRuleAssert.Silent(TSignatureMismatchRule.Create, ApplyAll(Source, Findings[0].Fixes[1]));
  Assert.IsTrue(ParsesCleanly(ApplyAll(Source, Findings[0].Fixes[1])));
  // Die beiden anderen Regeln schweigen: es fehlt kein Name.
  TRuleAssert.Silent(TDeclaredNotImplementedRule.Create, Source);
  TRuleAssert.Silent(TImplementedNotDeclaredRule.Create, Source);
end;

procedure TDeclarationRulesTests.DefaultsStayInDeclaration;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := ClassUnit('    function Bar(A: Integer = 5; B: string = ''x;y''): Boolean;',
    'function TFoo.Bar(const A: Integer; B: string): Boolean;'#10'begin'#10'end;');
  Findings := TRuleAssert.Findings(TSignatureMismatchRule.Create, Source);
  Assert.AreEqual('(A: Integer; B: string): Boolean', Findings[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual('(const A: Integer = 5; B: string = ''x;y''): Boolean', Findings[0].Fixes[1].Edits[0].NewText);
end;

procedure TDeclarationRulesTests.SignatureMismatchIssueExample;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := ClassUnit('    procedure Buchen(const Betrag: Currency; Datum: TDate);',
    'procedure TKonto.Buchen(Betrag: Currency; Datum: TDateTime);'#10'begin'#10'end;', 'TKonto = class');
  Findings := TRuleAssert.Findings(TSignatureMismatchRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('signature-mismatch', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('Buchen weicht von der Deklaration ab: Betrag ohne const, Datum TDateTime statt TDate (wie E2037).',
    Findings[0].Message);
  // Gemeldet am Namen im Kopf der Implementierung.
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(17, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(ClassUnit('    procedure Buchen(const Betrag: Currency; Datum: TDate);',
    'procedure TKonto.Buchen(const Betrag: Currency; Datum: TDate);'#10'begin'#10'end;', 'TKonto = class'),
    ApplyAll(Source, Findings[0].Fixes[0]));
  // Korrigierte Form und naheliegender Negativfall: anders gruppiert, ohne Parameterliste im Rumpf.
  TRuleAssert.Silent(TSignatureMismatchRule.Create, ApplyAll(Source, Findings[0].Fixes[0]));
  TRuleAssert.Silent(TSignatureMismatchRule.Create, ClassUnit('    procedure Buchen(const A, B: Currency);',
    'procedure TKonto.Buchen(const A: Currency; const B: Currency);'#10'begin'#10'end;', 'TKonto = class'));
  TRuleAssert.Silent(TSignatureMismatchRule.Create, ClassUnit('    procedure Buchen(const A: Currency);',
    'procedure TKonto.Buchen;'#10'begin'#10'end;', 'TKonto = class'));
end;

procedure TDeclarationRulesTests.SignatureMismatchVariants;
var
  Findings: TArray<TRuleFinding>;
  Source: string;
begin
  Assert.AreEqual('Foo weicht von der Deklaration ab: 2 statt 1 Parameter (wie E2037).',
    TRuleAssert.Findings(TSignatureMismatchRule.Create, ClassUnit('    procedure Foo(A: Integer);',
    'procedure TFoo.Foo(A: Integer; B: Integer);'#10'begin'#10'end;'))[0].Message);
  Assert.AreEqual('Foo weicht von der Deklaration ab: Ergebnis Int64 statt Integer (wie E2037).',
    TRuleAssert.Findings(TSignatureMismatchRule.Create, ClassUnit('    function Foo: Integer;',
    'function TFoo.Foo: Int64;'#10'begin'#10'end;'))[0].Message);
  Assert.AreEqual('Foo weicht von der Deklaration ab: Wert statt A, Wert var statt out (wie E2037).',
    TRuleAssert.Findings(TSignatureMismatchRule.Create, ClassUnit('    procedure Foo(out A: Integer);',
    'procedure TFoo.Foo(var Wert: Integer);'#10'begin'#10'end;'))[0].Message);
  // Aufrufkonvention: weglassen ist erlaubt, eine andere Angabe nicht.
  TRuleAssert.Silent(TSignatureMismatchRule.Create, ClassUnit('    procedure Foo(A: Integer); stdcall;',
    'procedure TFoo.Foo(A: Integer);'#10'begin'#10'end;'));
  Source := ClassUnit('    procedure Foo(A: Integer); stdcall;', 'procedure TFoo.Foo(A: Integer); cdecl;'#10'begin'#10'end;');
  Findings := TRuleAssert.Findings(TSignatureMismatchRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Foo weicht von der Deklaration ab: cdecl statt stdcall (wie E2037).', Findings[0].Message);
  Assert.AreEqual(ClassUnit('    procedure Foo(A: Integer); stdcall;',
    'procedure TFoo.Foo(A: Integer); stdcall;'#10'begin'#10'end;'), ApplyAll(Source, Findings[0].Fixes[0]));
  Assert.AreEqual(ClassUnit('    procedure Foo(A: Integer); cdecl;',
    'procedure TFoo.Foo(A: Integer); cdecl;'#10'begin'#10'end;'), ApplyAll(Source, Findings[0].Fixes[1]));
  Source := ClassUnit('    procedure Foo(A: Integer);', 'procedure TFoo.Foo(A: Integer); stdcall;'#10'begin'#10'end;');
  Findings := TRuleAssert.Findings(TSignatureMismatchRule.Create, Source);
  Assert.AreEqual('Foo weicht von der Deklaration ab: stdcall statt register (wie E2037).', Findings[0].Message);
  Assert.AreEqual(ClassUnit('    procedure Foo(A: Integer); stdcall;',
    'procedure TFoo.Foo(A: Integer); stdcall;'#10'begin'#10'end;'), ApplyAll(Source, Findings[0].Fixes[1]));
  // Überladung: verglichen wird mit der nächstliegenden Deklaration.
  Findings := TRuleAssert.Findings(TSignatureMismatchRule.Create, ClassUnit(
    '    procedure Foo(A: Integer); overload;'#10'    procedure Foo(A, B: string); overload;',
    'procedure TFoo.Foo(A: Integer);'#10'begin'#10'end;'#10'procedure TFoo.Foo(A: string; B: Integer);'#10 +
    'begin'#10'end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Foo weicht von der Deklaration ab: B Integer statt string (wie E2037).', Findings[0].Message);
end;

procedure TDeclarationRulesTests.SignatureMismatchOffAndExclude;
var
  Source: string;
begin
  Source := ClassUnit('    procedure Foo(A: Integer);', 'procedure TFoo.Foo(const A: Integer);'#10'begin'#10'end;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSignatureMismatchRule.Create, Source,
    '{"rules": {"signature-mismatch": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSignatureMismatchRule.Create, Source,
    '{"rules": {"group:compiler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TSignatureMismatchRule.Create, Source,
    '{"rules": {"signature-mismatch": {"exclude": ["Source/*.pas"]}}}', 'Source/U.pas'))));
  // Ein fehlender Name bleibt bei den anderen Regeln.
  Source := ClassUnit('    procedure Foo(A: Integer);', 'procedure TFoo.Bar(A: Integer);'#10'begin'#10'end;');
  TRuleAssert.Silent(TSignatureMismatchRule.Create, Source);
  TRuleAssert.Reports(TDeclaredNotImplementedRule.Create, Source);
  TRuleAssert.Reports(TImplementedNotDeclaredRule.Create, Source);
end;

procedure TDeclarationRulesTests.AmbiguousOverloadOffersNoAlignment;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TImplementedNotDeclaredRule.Create, ClassUnit(
    '    procedure Foo(A: Integer); overload;'#10'    procedure Foo(A: string); overload;',
    'procedure TFoo.Foo(A: Double);'#10'begin'#10'end;'));
  Assert.AreEqual(1, Integer(Length(Findings)));
  // Nur "Deklaration ergänzen".
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
end;

/// <summary>Unit mit ILogger (Info, Warnung, Fehler) und der Klasse AClass samt AImplementation.</summary>
function LoggerUnit(const AClass, AImplementation: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10 +
    '  ILogger = interface'#10 +
    '    procedure Info(const Text: string);'#10 +
    '    procedure Warnung(const Text: string);'#10 +
    '    procedure Fehler(const Text: string);'#10 +
    '  end;'#10 + AClass + #10'implementation'#10 + AImplementation + #10'end.';
end;

const
  DateiLog = '  TDateiLog = class(TInterfacedObject, ILogger)'#10'  public'#10 +
    '    procedure Info(const Text: string);'#10'  end;';
  DateiLogBody = 'procedure TDateiLog.Info(const Text: string);'#10'begin'#10'end;';

procedure TDeclarationRulesTests.InterfaceIssueExample;
var
  Source, Fixed: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := LoggerUnit(DateiLog, DateiLogBody);
  Findings := TRuleAssert.Findings(TInterfaceNotImplementedRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('ILogger.Fehler und ILogger.Warnung fehlen in TDateiLog (wie E2291).', Findings[0].Message);
  Assert.AreEqual(8, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  // Die Korrektur deklariert die fehlenden Methoden und legt leere Rümpfe an.
  Fixed := ApplyAll(Source, Findings[0].Fixes[0]);
  Assert.IsTrue(Fixed.Contains('    procedure Info(const Text: string);'#10 +
    '    procedure Warnung(const Text: string);'#10'    procedure Fehler(const Text: string);'#10'  end;'), Fixed);
  Assert.IsTrue(Fixed.Contains('procedure TDateiLog.Fehler(const Text: string);'), Fixed);
  Assert.IsTrue(ParsesCleanly(Fixed), Fixed);
  TRuleAssert.Silent(TInterfaceNotImplementedRule.Create, Fixed);
end;

procedure TDeclarationRulesTests.InterfaceImplementationsThatCount;
begin
  // Vollständig.
  TRuleAssert.Silent(TInterfaceNotImplementedRule.Create, LoggerUnit(
    '  TLog = class(TInterfacedObject, ILogger)'#10'    procedure Info(const Text: string);'#10 +
    '    procedure Warnung(const Text: string);'#10'    procedure Fehler(const Text: string);'#10'  end;', ''));
  // Geerbt aus einer Vorfahrklasse.
  TRuleAssert.Silent(TInterfaceNotImplementedRule.Create, LoggerUnit(
    '  TBasis = class(TInterfacedObject)'#10'    procedure Warnung(const Text: string);'#10 +
    '    procedure Fehler(const Text: string);'#10'  end;'#10 +
    '  TLog = class(TBasis, ILogger)'#10'    procedure Info(const Text: string);'#10'  end;', ''));
  // Methodenzuordnungen.
  TRuleAssert.Silent(TInterfaceNotImplementedRule.Create, LoggerUnit(
    '  TLog = class(TInterfacedObject, ILogger)'#10'    procedure ILogger.Warnung = Melde;'#10 +
    '    procedure ILogger.Fehler = Melde;'#10'    procedure Info(const Text: string);'#10 +
    '    procedure Melde(const Text: string);'#10'  end;', ''));
  // implements-Delegation.
  TRuleAssert.Silent(TInterfaceNotImplementedRule.Create, LoggerUnit(
    '  TLog = class(TInterfacedObject, ILogger)'#10'    FLog: ILogger;'#10 +
    '    property Log: ILogger read FLog implements ILogger;'#10'  end;', ''));
  // TObject-Methoden zählen (ToString), Methoden von IInterface bringt TInterfacedObject mit.
  TRuleAssert.Silent(TInterfaceNotImplementedRule.Create,
    'unit U;'#10'interface'#10'type'#10'  IText = interface(IInterface)'#10'    function ToString: string;'#10 +
    '    function _AddRef: Integer; stdcall;'#10'  end;'#10'  TText = class(TInterfacedObject, IText)'#10'  end;'#10 +
    'implementation'#10'end.');
end;

procedure TDeclarationRulesTests.InterfaceUnknownAncestorIsSilent;
begin
  // Ein unbekannter Vorfahr kann die Methoden liefern; ein unbekanntes Interface ist nicht prüfbar.
  TRuleAssert.Silent(TInterfaceNotImplementedRule.Create, LoggerUnit(
    '  TLog = class(TFremdeBasis, ILogger)'#10'    procedure Info(const Text: string);'#10'  end;', ''));
  TRuleAssert.Silent(TInterfaceNotImplementedRule.Create, LoggerUnit(
    '  TLog = class(TInterfacedObject, IFremd)'#10'    procedure Info(const Text: string);'#10'  end;', ''));
  // Bedingte Klasse.
  TRuleAssert.Silent(TInterfaceNotImplementedRule.Create, LoggerUnit('{$IFDEF DEBUG}'#10 + DateiLog + #10'{$ENDIF}', ''));
end;

procedure TDeclarationRulesTests.InterfaceDifferentSignature;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TInterfaceNotImplementedRule.Create, LoggerUnit(
    '  TLog = class(TInterfacedObject, ILogger)'#10'    procedure Info(const Text: Integer);'#10 +
    '    procedure Warnung(const Text: string);'#10'    procedure Fehler(const Text: string);'#10'  end;', ''));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Info weicht von der Deklaration in ILogger ab (wie E2211).', Findings[0].Message);
  Assert.AreEqual(9, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
end;

procedure TDeclarationRulesTests.InterfaceResolutionForUnlistedInterface;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TInterfaceNotImplementedRule.Create, LoggerUnit(
    '  TLog = class(TInterfacedObject, ILogger)'#10'    procedure IAnders.Info = Melde;'#10 +
    '    procedure Info(const Text: string);'#10'    procedure Warnung(const Text: string);'#10 +
    '    procedure Fehler(const Text: string);'#10'    procedure Melde(const Text: string);'#10'  end;', ''));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('IAnders steht nicht in der Interface-Liste von TLog (wie E2265).', Findings[0].Message);
end;

procedure TDeclarationRulesTests.InterfaceOffAndExclude;
var
  Source: string;
begin
  Source := LoggerUnit(DateiLog, DateiLogBody);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceNotImplementedRule.Create, Source,
    '{"rules": {"interface-not-implemented": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceNotImplementedRule.Create, Source,
    '{"rules": {"group:compiler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TInterfaceNotImplementedRule.Create, Source,
    '{"rules": {"interface-not-implemented": {"exclude": ["Source/*.pas"]}}}', 'Source/U.pas'))));
end;

function Kunde(const AMembers: string): string;
begin
  Result := 'unit Kunden;'#10'interface'#10'type'#10'  TKunde = class'#10 + AMembers + '  end;'#10 +
    'implementation'#10'end.';
end;

procedure TDeclarationRulesTests.FieldAfterMethodIssueExample;
const
  Members = '  private'#10'    function GetName: string;'#10'    FName: string;'#10;
var
  Findings: TArray<TRuleFinding>;
  Text: string;
begin
  Findings := TRuleAssert.Findings(TFieldAfterMethodRule.Create, Kunde(Members));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(FieldAfterMethodRuleId, Findings[0].RuleId);
  Assert.AreEqual('Feld nach Methoden im selben Abschnitt (wie E2169).', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual(6, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Feld an den Anfang des Abschnitts verschieben', Findings[0].Fixes[0].Title);
  Text := TChangeSignature.ApplyEdits(Kunde(Members), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Kunde('  private'#10'    FName: string;'#10'    function GetName: string;'#10), Text);
  TRuleAssert.Silent(TFieldAfterMethodRule.Create, Text);
  Assert.AreEqual('var davor setzen', Findings[0].Fixes[1].Title);
  Text := TChangeSignature.ApplyEdits(Kunde(Members), Findings[0].Fixes[1].Edits);
  Assert.AreEqual(Kunde('  private'#10'    function GetName: string;'#10'    var FName: string;'#10), Text);
  TRuleAssert.Silent(TFieldAfterMethodRule.Create, Text);
end;

procedure TDeclarationRulesTests.FieldAfterMethodVariants;
const
  Members = '  private'#10'    /// <summary>Name</summary>'#10'    [Stored]'#10'    property Name: string read FName;'#10 +
    '    procedure Setzen;'#10'    // Puffer'#10'    [Weak] FPuffer: TObject;'#10'    FA, FB: Integer;'#10;
  Rec = 'unit R;'#10'interface'#10'type'#10'  TPunkt = record'#10'    procedure Setzen;'#10'    X: Integer;'#10 +
    '  end;'#10'implementation'#10'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  // Nach einer Property, mit Attribut und Kommentar; zwei Felder je eine Meldung.
  Findings := TRuleAssert.Findings(TFieldAfterMethodRule.Create, Kunde(Members));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual(Kunde('  private'#10'    // Puffer'#10'    [Weak] FPuffer: TObject;'#10 +
    '    /// <summary>Name</summary>'#10'    [Stored]'#10'    property Name: string read FName;'#10 +
    '    procedure Setzen;'#10'    FA, FB: Integer;'#10),
    TChangeSignature.ApplyEdits(Kunde(Members), Findings[0].Fixes[0].Edits));
  Assert.AreEqual(Kunde('  private'#10'    /// <summary>Name</summary>'#10'    [Stored]'#10 +
    '    property Name: string read FName;'#10'    procedure Setzen;'#10'    // Puffer'#10 +
    '    var [Weak] FPuffer: TObject;'#10'    FA, FB: Integer;'#10),
    TChangeSignature.ApplyEdits(Kunde(Members), Findings[0].Fixes[1].Edits));
  // Record: var zuerst, weil Verschieben das Speicherlayout ändert.
  Findings := TRuleAssert.Findings(TFieldAfterMethodRule.Create, Rec);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('var davor setzen', Findings[0].Fixes[0].Title);
  Assert.AreEqual('Feld an den Anfang des Abschnitts verschieben', Findings[0].Fixes[1].Title);
  // Feld auf derselben Zeile wie anderes: nur var.
  Findings := TRuleAssert.Findings(TFieldAfterMethodRule.Create, Kunde('    procedure A; FX: Integer;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('var davor setzen', Findings[0].Fixes[0].Title);
end;

procedure TDeclarationRulesTests.FieldAfterMethodSilentCases;
begin
  // Felder zuerst, neuer Abschnitt, var und class var, verschiedene {$IF}-Zweige.
  TRuleAssert.Silent(TFieldAfterMethodRule.Create, Kunde('    FErst: Integer;'#10'    procedure A;'#10 +
    '  private'#10'    FZweit: Integer;'#10'    procedure B;'#10'    var'#10'      FDritt: Integer;'#10 +
    '    class var FKlasse: Integer;'#10'  public'#10'    procedure C;'#10'  type'#10'    TArt = Integer;'#10 +
    '  var'#10'    FViert: TArt;'#10));
  TRuleAssert.Silent(TFieldAfterMethodRule.Create, Kunde('{$IFDEF DEBUG}'#10'    procedure A;'#10'{$ENDIF}'#10 +
    '    FX: Integer;'#10));
  TRuleAssert.Silent(TFieldAfterMethodRule.Create, Kunde('{$IFDEF DEBUG}'#10'    procedure A;'#10'{$ELSE}'#10 +
    '    FX: Integer;'#10'{$ENDIF}'#10));
end;

procedure TDeclarationRulesTests.FieldAfterMethodConditional;
var
  Findings: TArray<TRuleFinding>;
begin
  // Methode ohne Bedingung, Feld unter DEBUG: dort immer ein Fehler, verschoben wird nicht.
  Findings := TRuleAssert.Findings(TFieldAfterMethodRule.Create, Kunde('    procedure A;'#10'{$IFDEF DEBUG}'#10 +
    '    FX: Integer;'#10'{$ENDIF}'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('var davor setzen', Findings[0].Fixes[0].Title);
end;

procedure TDeclarationRulesTests.FieldAfterMethodOffAndExclude;
const
  Members = '    procedure A;'#10'    FX: Integer;'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFieldAfterMethodRule.Create, Kunde(Members),
    '{"rules": {"field-after-method": "off"}}', 'Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFieldAfterMethodRule.Create, Kunde(Members),
    '{"rules": {"group:compiler": "off"}}', 'Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TFieldAfterMethodRule.Create, Kunde(Members),
    '{"rules": {"field-after-method": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Kunden.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TFieldAfterMethodRule.Create, Kunde(Members),
    '{"rules": {"field-after-method": {"exclude": ["Alt/*.pas"]}}}', 'Neu/Kunden.pas'))));
end;

procedure TDeclarationRulesTests.OverloadIssueExample;
const
  Members = '    procedure Laden(const Datei: string);'#10'    procedure Laden(Strom: TStream);'#10;
var
  Findings: TArray<TRuleFinding>;
  Text: string;
begin
  Findings := TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, Kunde(Members));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(OverloadDirectiveMissingRuleId, Findings[0].RuleId);
  Assert.AreEqual('Laden ist überladen, aber nicht mit overload markiert (wie E2254).', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(14, Findings[0].Range.StartPos.Character);
  Assert.AreEqual('overload; an alle Deklarationen anhängen', Findings[0].Fixes[0].Title);
  Text := TChangeSignature.ApplyEdits(Kunde(Members), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Kunde('    procedure Laden(const Datei: string); overload;'#10 +
    '    procedure Laden(Strom: TStream); overload;'#10), Text);
  TRuleAssert.Silent(TOverloadDirectiveMissingRule.Create, Text);
end;

procedure TDeclarationRulesTests.OverloadVariants;
var
  Findings: TArray<TRuleFinding>;
begin
  // Frühere ohne overload (E2267); overload vor den übrigen Direktiven.
  Findings := TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, Kunde(
    '    procedure Laden(const Datei: string); virtual;'#10'    procedure Laden(Strom: TStream); overload;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Laden ist überladen, die frühere Deklaration in Zeile 5 trägt kein overload (wie E2267).',
    Findings[0].Message);
  Assert.AreEqual(Kunde('    procedure Laden(const Datei: string); overload; virtual;'#10 +
    '    procedure Laden(Strom: TStream); overload;'#10), TChangeSignature.ApplyEdits(Kunde(
    '    procedure Laden(const Datei: string); virtual;'#10'    procedure Laden(Strom: TStream); overload;'#10),
    Findings[0].Fixes[0].Edits));
  // Gleiche Parameter (E2252) und gleiches Ergebnis (E2301), auch mit anderen Namen.
  Findings := TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, Kunde(
    '    procedure Laden(A, B: Integer); overload;'#10'    procedure Laden(X: Integer; Y: integer); overload;'#10 +
    '    function Wert(const S: string): Integer; overload;'#10'    function Wert(const T: string): Integer; overload;'#10));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Laden mit denselben Parametern gibt es schon in Zeile 5 (wie E2252).', Findings[0].Message);
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('Wert mit denselben Parametern und demselben Ergebnistyp gibt es schon in Zeile 7 (wie E2301).',
    Findings[1].Message);
  // Routinen der Unit: interface und implementation zusammen, Rumpf zur Deklaration zählt nicht.
  Findings := TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, 'unit U;'#10'interface'#10 +
    'procedure Global(A: Integer);'#10'implementation'#10'procedure Global(A: Integer);'#10'begin'#10'end;'#10 +
    'procedure Global(const S: string);'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('unit U;'#10'interface'#10'procedure Global(A: Integer); overload;'#10'implementation'#10 +
    'procedure Global(A: Integer);'#10'begin'#10'end;'#10'procedure Global(const S: string); overload;'#10'begin'#10 +
    'end;'#10'end.', TChangeSignature.ApplyEdits('unit U;'#10'interface'#10'procedure Global(A: Integer);'#10 +
    'implementation'#10'procedure Global(A: Integer);'#10'begin'#10'end;'#10'procedure Global(const S: string);'#10 +
    'begin'#10'end;'#10'end.', Findings[0].Fixes[0].Edits));
  // Verschachtelte Routinen bilden einen eigenen Bereich.
  Findings := TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure Aussen;'#10'  procedure Innen; begin end;'#10'  procedure Innen(X: Integer); begin end;'#10'begin'#10 +
    'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
end;

procedure TDeclarationRulesTests.OverloadSilentCases;
begin
  // overload überall, var gegen Wert, Generika, Operatoren, Rumpf zu forward, Methodenrümpfe,
  // gleichnamige Methoden verschiedener Klassen und Zweige von {$IFDEF}/{$ELSE}.
  TRuleAssert.Silent(TOverloadDirectiveMissingRule.Create, 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10 +
    '    procedure Laden(A: Integer); overload;'#10'    procedure Laden(var A: Integer); overload;'#10 +
    '    procedure Laden<T>(A: Integer); overload;'#10'  end;'#10'  TBar = class'#10'    procedure Laden;'#10'  end;'#10 +
    '  TWert = record'#10'    class operator Implicit(A: Integer): TWert;'#10 +
    '    class operator Implicit(A: TWert): Integer;'#10'  end;'#10'implementation'#10 +
    'procedure Vorab(A: Integer); forward;'#10'procedure Vorab(A: Integer);'#10'begin'#10'end;'#10 +
    'procedure TFoo.Laden(A: Integer);'#10'begin'#10'end;'#10'procedure TBar.Laden;'#10'begin'#10'end;'#10 +
    '{$IFDEF DEBUG}'#10'procedure Schreiben(A: Integer);'#10'begin'#10'end;'#10'{$ELSE}'#10 +
    'procedure Schreiben(A: Integer);'#10'begin'#10'end;'#10'{$ENDIF}'#10'end.');
end;

procedure TDeclarationRulesTests.OverloadOffAndExclude;
const
  Members = '    procedure Laden(const Datei: string);'#10'    procedure Laden(Strom: TStream);'#10;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, Kunde(Members),
    '{"rules": {"overload-directive-missing": "off"}}', 'Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, Kunde(Members),
    '{"rules": {"group:compiler": "off"}}', 'Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, Kunde(Members),
    '{"rules": {"overload-directive-missing": {"exclude": ["Alt/*.pas"]}}}', 'Alt/Kunden.pas'))));
end;

/// <summary>Meldet keine der Regeln, die Deklaration und Rumpf zuordnen, etwas zu ASource?</summary>
procedure AssertMatchingSilent(const ASource: string);
begin
  TRuleAssert.Silent(TDeclaredNotImplementedRule.Create, ASource);
  TRuleAssert.Silent(TImplementedNotDeclaredRule.Create, ASource);
  TRuleAssert.Silent(TSignatureMismatchRule.Create, ASource);
  TRuleAssert.Silent(TOverloadDirectiveMissingRule.Create, ASource);
end;

procedure TDeclarationRulesTests.SpecialFormClassConstructor;
begin
  // F02: class constructor ist keine Überladung des Instanz-Konstruktors.
  AssertMatchingSilent('unit F02_ClassCtorOverload;'#10'interface'#10'type'#10'  TA = class'#10'  public'#10 +
    '    class constructor Create;'#10'    class destructor Destroy;'#10'    constructor Create; overload;'#10 +
    '    constructor Create(X: Integer); overload;'#10'    destructor Destroy; override;'#10'  end;'#10 +
    'implementation'#10'class constructor TA.Create; begin end;'#10'class destructor TA.Destroy; begin end;'#10 +
    'constructor TA.Create; begin end;'#10'constructor TA.Create(X: Integer); begin end;'#10 +
    'destructor TA.Destroy; begin end;'#10'end.');
end;

procedure TDeclarationRulesTests.SpecialFormMethodResolution;
begin
  // F03: Methodenzuordnung braucht keinen Rumpf und ist keine Überladung.
  AssertMatchingSilent('unit F03_MethodResolution;'#10'interface'#10'type'#10'  IFoo = interface'#10 +
    '    function GetX: Integer;'#10'  end;'#10'  TA = class(TInterfacedObject, IFoo)'#10 +
    '    function IFoo.GetX = MyGetX;'#10'    function MyGetX: Integer;'#10'  end;'#10'implementation'#10 +
    'function TA.MyGetX: Integer; begin Result := 1; end;'#10'end.');
end;

procedure TDeclarationRulesTests.SpecialFormGenericConstraints;
begin
  // F06: Constraints stehen nur in der Deklaration; das ";" darin beendet den Kopf nicht.
  AssertMatchingSilent('unit F06_GenericConstraints;'#10'interface'#10'type'#10'  TA = class'#10 +
    '    procedure Reg<TI: IInterface; TC: class>(const N: string); overload;'#10 +
    '    procedure Reg<TI: IInterface; TC: class>(const S: Boolean; const N: string); overload;'#10'  end;'#10 +
    'implementation'#10'procedure TA.Reg<TI, TC>(const N: string); begin end;'#10 +
    'procedure TA.Reg<TI, TC>(const S: Boolean; const N: string); begin end;'#10'end.');
end;

procedure TDeclarationRulesTests.SpecialFormEmptyParentheses;
begin
  // F07: "()" in der Implementierung heißt keine Parameter.
  AssertMatchingSilent('unit F07_EmptyParens;'#10'interface'#10'uses Classes;'#10'type'#10'  TW = class(TThread)'#10 +
    '  protected'#10'    procedure Execute; override;'#10'    function Wert(): Integer;'#10'  end;'#10 +
    'implementation'#10'procedure TW.Execute(); begin end;'#10'function TW.Wert: Integer; begin Result := 0; end;'#10 +
    'end.');
end;

procedure TDeclarationRulesTests.SpecialFormShortImplementation;
begin
  // F13: Die Kurzform der Implementierung gehört zur einzigen Deklaration gleichen Namens, auch mit Kommentaren
  // im mehrzeiligen Kopf; ebenso bei Methoden.
  AssertMatchingSilent('unit F13_ShortFormImpl;'#10'interface'#10'function Foo('#10'    A: Integer;   // erster'#10 +
    '    B: Integer    // zweiter'#10' ): Integer; stdcall;'#10'type'#10'  TA = class'#10 +
    '    function Bar(A: Integer): Integer;'#10'  end;'#10'implementation'#10'function Foo;'#10'begin'#10 +
    '  Result := A + B;'#10'end;'#10'function TA.Bar;'#10'begin'#10'  Result := A;'#10'end;'#10'end.');
end;

procedure TDeclarationRulesTests.SpecialFormOpenArrayElementType;
begin
  // F18: Bei offenen Arrays zählt der Elementtyp.
  AssertMatchingSilent('unit F18_OpenArrayOverload;'#10'interface'#10'uses System.Rtti, System.TypInfo;'#10'type'#10 +
    '  TA = class'#10'    function Inject(const T: array of PTypeInfo): Integer; overload;'#10 +
    '    function Inject(const V: array of TValue): Integer; overload;'#10'  end;'#10 +
    'procedure Fill(const A: array of Integer); overload;'#10'procedure Fill(const A: array of string); overload;'#10 +
    'implementation'#10'function TA.Inject(const T: array of PTypeInfo): Integer; begin Result := 0; end;'#10 +
    'function TA.Inject(const V: array of TValue): Integer; begin Result := 1; end;'#10 +
    'procedure Fill(const A: array of Integer); begin end;'#10'procedure Fill(const A: array of string); begin end;'#10 +
    'end.');
end;

procedure TDeclarationRulesTests.SpecialFormAsmExternalAndOverride;
begin
  // Rumpf aus asm, external im implementation-Teil (auch in Kurzform), forward mit asm-Rumpf; override ohne
  // overload übernimmt es von der überschriebenen Methode.
  AssertMatchingSilent('unit U;'#10'interface'#10'function BitsHighest(X: Cardinal): Integer;'#10 +
    'function Lese(P: Pointer): Integer; stdcall;'#10'function Schreibe(P: Pointer): Integer; stdcall;'#10'type'#10 +
    '  TB = class(TBasis)'#10'    procedure Add(P: PChar); override;'#10 +
    '    procedure Add(P: PChar; Len: Integer); override;'#10'  end;'#10'implementation'#10 +
    'procedure Move4(const ASource; var ADest); forward;'#10'function BitsHighest(X: Cardinal): Integer;'#10'asm'#10 +
    '  MOV EAX, -1'#10'end;'#10'function Lese(P: Pointer): Integer; stdcall; external ''a.dll'';'#10 +
    'function Schreibe; external ''a.dll'';'#10'procedure Move4(const ASource; var ADest);'#10'asm'#10'end;'#10 +
    'procedure TB.Add(P: PChar); begin end;'#10'procedure TB.Add(P: PChar; Len: Integer); begin end;'#10'end.');
end;

procedure TDeclarationRulesTests.SpecialFormGenericNamesake;
begin
  // Neben TProperty steht ein generischer TProperty<T> gleichen Namens (Spring4D): Dessen Deklarationen und Rümpfe
  // gehören nicht zum nicht generischen Typ.
  AssertMatchingSilent('unit U;'#10'interface'#10'type'#10'  TProperty = class'#10 +
    '    constructor Create(const AName: string);'#10'  end;'#10'  TProperty<T: class> = class(TProperty)'#10 +
    '    constructor Create(const AName, APath: string);'#10'    function Wert: T;'#10'  end;'#10'implementation'#10 +
    'constructor TProperty.Create(const AName: string); begin end;'#10 +
    'constructor TProperty<T>.Create(const AName, APath: string); begin end;'#10 +
    'function TProperty<T>.Wert: T; begin Result := nil; end;'#10'end.');
end;

procedure TDeclarationRulesTests.SpecialFormCounterChecks;
var
  Findings: TArray<TRuleFinding>;
begin
  // Zwei echte Überladungen ohne overload, auch neben einem class constructor.
  Findings := TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, Kunde('    class constructor Create;'#10 +
    '    constructor Create;'#10'    constructor Create(X: Integer);'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Create ist überladen, aber nicht mit overload markiert (wie E2254).', Findings[0].Message);
  // Offene Arrays mit gleichem Elementtyp sind gleiche Parameter (E2252).
  Findings := TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, Kunde(
    '    procedure Fill(const A: array of Integer); overload;'#10 +
    '    procedure Fill(const B: array of Integer); overload;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Fill mit denselben Parametern gibt es schon in Zeile 5 (wie E2252).', Findings[0].Message);
  // Die Kurzform passt nicht, wenn es zwei Deklarationen gleichen Namens gibt.
  Findings := TRuleAssert.Findings(TOverloadDirectiveMissingRule.Create, 'unit U;'#10'interface'#10 +
    'procedure P(A: Integer); overload;'#10'procedure P(S: string); overload;'#10'implementation'#10 +
    'procedure P;'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  // Ein wirklich fehlender Rumpf, auch neben "()" und Kurzform.
  Findings := TRuleAssert.Findings(TDeclaredNotImplementedRule.Create, Kunde('    procedure Lauf;'#10 +
    '    procedure Halt(A: Integer);'#10'    procedure Fehlt;'#10).Replace('implementation'#10,
    'implementation'#10'procedure TKunde.Lauf(); begin end;'#10'procedure TKunde.Halt; begin end;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('"TKunde.Fehlt" ist deklariert, aber nicht implementiert', Findings[0].Message);
end;

function Rechnung(const ADeclarations: string): string;
begin
  Result := 'unit Rechnungen;'#10'interface'#10'implementation'#10 +
    'procedure TRechnung.Summieren(Betrag: Currency);'#10 + ADeclarations + 'begin'#10'end;'#10'end.';
end;

procedure TDeclarationRulesTests.DuplicateDeclarationIssueExample;
var
  Findings: TArray<TRuleFinding>;
  Text: string;
begin
  Findings := TRuleAssert.Findings(TDuplicateDeclarationRule.Create, Rechnung('var'#10'  Betrag: Currency;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(DuplicateDeclarationRuleId, Findings[0].RuleId);
  Assert.AreEqual('Betrag ist schon als Parameter deklariert (wie E2004).', Findings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  // Einzige Variable: der var-Abschnitt geht mit.
  Assert.AreEqual('Zweite Deklaration entfernen', Findings[0].Fixes[0].Title);
  Text := TChangeSignature.ApplyEdits(Rechnung('var'#10'  Betrag: Currency;'#10), Findings[0].Fixes[0].Edits);
  Assert.AreEqual(Rechnung(''), Text);
  TRuleAssert.Silent(TDuplicateDeclarationRule.Create, Text);
  // Unter mehreren: nur die Zeile bzw. der Name.
  Findings := TRuleAssert.Findings(TDuplicateDeclarationRule.Create, Rechnung('var'#10'  Summe: Currency;'#10 +
    '  Betrag: Currency;'#10));
  Assert.AreEqual(Rechnung('var'#10'  Summe: Currency;'#10), TChangeSignature.ApplyEdits(Rechnung('var'#10 +
    '  Summe: Currency;'#10'  Betrag: Currency;'#10), Findings[0].Fixes[0].Edits));
  Findings := TRuleAssert.Findings(TDuplicateDeclarationRule.Create, Rechnung('var'#10'  Betrag, Summe: Currency;'#10));
  Assert.AreEqual(Rechnung('var'#10'  Summe: Currency;'#10), TChangeSignature.ApplyEdits(Rechnung('var'#10 +
    '  Betrag, Summe: Currency;'#10), Findings[0].Fixes[0].Edits));
  Findings := TRuleAssert.Findings(TDuplicateDeclarationRule.Create, Rechnung('var'#10'  Summe, Betrag: Currency;'#10));
  Assert.AreEqual(Rechnung('var'#10'  Summe: Currency;'#10), TChangeSignature.ApplyEdits(Rechnung('var'#10 +
    '  Summe, Betrag: Currency;'#10), Findings[0].Fixes[0].Edits));
end;

procedure TDeclarationRulesTests.DuplicateDeclarationScopes;
var
  Findings: TArray<TRuleFinding>;
begin
  // Konstante und Variable, Typ und Label in einer Routine; zwei Parameter.
  Findings := TRuleAssert.Findings(TDuplicateDeclarationRule.Create, Rechnung('label'#10'  Weiter, Weiter;'#10 +
    'const'#10'  Satz = 19;'#10'type'#10'  TSatz = Integer;'#10'var'#10'  Satz: Integer;'#10'  TSatz: Integer;'#10));
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('Weiter ist schon als Label deklariert (wie E2004).', Findings[0].Message);
  Assert.AreEqual('Satz ist schon als Konstante deklariert (wie E2004).', Findings[1].Message);
  Assert.AreEqual('TSatz ist schon als Typ deklariert (wie E2004).', Findings[2].Message);
  Findings := TRuleAssert.Findings(TDuplicateDeclarationRule.Create, 'unit U;'#10'interface'#10'implementation'#10 +
    'procedure P(A: Integer; var A: string);'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)));
  // Felder, Methode und Property eines Typs; varianter Teil eines Records.
  Findings := TRuleAssert.Findings(TDuplicateDeclarationRule.Create, 'unit U;'#10'interface'#10'type'#10 +
    '  TKunde = class'#10'    FName, FOrt: string;'#10'  private'#10'    FName: string;'#10'    function Ort: string;'#10 +
    '    property Ort: string read FOrt;'#10'  end;'#10'  TForm = record'#10'    Art: Integer;'#10 +
    '    case Integer of'#10'      0: (Art: Byte);'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('FName ist schon als Feld deklariert (wie E2004).', Findings[0].Message);
  Assert.AreEqual('Ort ist schon als Methode deklariert (wie E2004).', Findings[1].Message);
  Assert.AreEqual(0, Integer(Length(Findings[1].Fixes)));
  Assert.AreEqual('Art ist schon als Feld deklariert (wie E2004).', Findings[2].Message);
  // Unit: interface und implementation sind ein Bereich.
  Findings := TRuleAssert.Findings(TDuplicateDeclarationRule.Create, 'unit U;'#10'interface'#10'var'#10 +
    '  Zaehler: Integer;'#10'implementation'#10'type'#10'  Zaehler = Integer;'#10'procedure Zaehler;'#10'begin'#10 +
    'end;'#10'end.');
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Zaehler ist schon als Variable deklariert (wie E2004).', Findings[0].Message);
  Assert.AreEqual('Zaehler ist schon als Variable deklariert (wie E2004).', Findings[1].Message);
end;

procedure TDeclarationRulesTests.DuplicateDeclarationUses;
const
  Source = 'unit U;'#10'interface'#10'uses'#10'  System.SysUtils, System.Classes, System.SysUtils;'#10 +
    'implementation'#10'uses'#10'  System.Classes;'#10'end.';
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TDuplicateDeclarationRule.Create, Source);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Unit System.SysUtils steht schon in uses (wie E2004).', Findings[0].Message);
  Assert.AreEqual('Unit System.Classes steht schon im uses des interface (wie E2004).', Findings[1].Message);
  Assert.AreEqual('Doppelten Eintrag entfernen', Findings[0].Fixes[0].Title);
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  System.SysUtils, System.Classes;'#10 +
    'implementation'#10'uses'#10'  System.Classes;'#10'end.', TChangeSignature.ApplyEdits(Source,
    Findings[0].Fixes[0].Edits));
  Assert.AreEqual('unit U;'#10'interface'#10'uses'#10'  System.SysUtils, System.Classes, System.SysUtils;'#10 +
    'implementation'#10'end.', TChangeSignature.ApplyEdits(Source, Findings[1].Fixes[0].Edits));
  // checkUses = false schaltet nur diesen Teil ab.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateDeclarationRule.Create, Source,
    '{"rules": {"duplicate-declaration": {"checkUses": false}}}', 'U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TDuplicateDeclarationRule.Create,
    Rechnung('var'#10'  Betrag: Currency;'#10), '{"rules": {"duplicate-declaration": {"checkUses": false}}}',
    'U.pas'))));
end;

procedure TDeclarationRulesTests.DuplicateDeclarationSilentCases;
begin
  // Überladungen und Rümpfe, Vorwärtsdeklaration, TList neben TList<T>, Feld und gleichnamiger
  // Parameter einer Methode, lokale Variable wie ein Feld, {$IFDEF}/{$ELSE}.
  TRuleAssert.Silent(TDuplicateDeclarationRule.Create, 'unit U;'#10'interface'#10'uses'#10'  System.SysUtils;'#10 +
    'type'#10'  TKunde = class;'#10'  TListe<T> = class'#10'  end;'#10'  TListe = class'#10'  end;'#10 +
    '  TKunde = class'#10'    FName: string;'#10'    procedure Setzen(FName: string); overload;'#10 +
    '    procedure Setzen(A: Integer); overload;'#10'  end;'#10'procedure Global;'#10'implementation'#10 +
    'procedure Global;'#10'begin'#10'end;'#10'procedure TKunde.Setzen(FName: string);'#10'var'#10'  A: Integer;'#10 +
    'begin'#10'end;'#10'procedure TKunde.Setzen(A: Integer);'#10'begin'#10'end;'#10'{$IFDEF DEBUG}'#10'var'#10 +
    '  Stufe: Integer;'#10'{$ELSE}'#10'const'#10'  Stufe = 0;'#10'{$ENDIF}'#10'end.');
end;

procedure TDeclarationRulesTests.DuplicateDeclarationOptions;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateDeclarationRule.Create,
    Rechnung('var'#10'  Betrag: Currency;'#10), '{"rules": {"duplicate-declaration": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateDeclarationRule.Create,
    Rechnung('var'#10'  Betrag: Currency;'#10), '{"rules": {"group:compiler": "off"}}', 'U.pas'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDuplicateDeclarationRule.Create,
    Rechnung('var'#10'  Betrag: Currency;'#10), '{"rules": {"duplicate-declaration": {"exclude": ["Alt/*.pas"]}}}',
    'Alt/U.pas'))));
  TConfigurationParser.Parse('{"rules": {"duplicate-declaration": {"checkUses": "ja"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

function Wert(const ABranches: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TArt = (waZahl, waText);'#10'  TWert = record'#10 +
    '    case Art: TArt of'#10 + ABranches + '  end;'#10'implementation'#10'end.';
end;

function Typen(const ATypes: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10'  TName = record'#10'    S: string;'#10'  end;'#10 +
    '  TZaehler = record'#10'    N: Integer;'#10'    class operator Initialize(out ADest: TZaehler);'#10'  end;'#10 +
    ATypes + 'implementation'#10'end.';
end;

procedure TDeclarationRulesTests.VariantManagedIssueExample;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
  Tree: TSyntaxTree;
begin
  Source := Wert('      waZahl: (Zahl: Double);'#10'      waText: (Text: string);'#10);
  Findings := TRuleAssert.Findings(TVariantRecordManagedFieldRule.Create, Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('variant-record-managed-field', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('string braucht Finalisierung und ist im varianten Teil nicht erlaubt (wie E2154).',
    Findings[0].Message);
  Assert.AreEqual(7, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(21, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(27, Findings[0].Range.EndPos.Character);
  Assert.AreEqual(2, Integer(Length(Findings[0].Fixes)));
  Assert.AreEqual('ShortString verwenden (höchstens 255 Zeichen)', Findings[0].Fixes[0].Title);
  Assert.AreEqual('Text in den festen Teil verschieben', Findings[0].Fixes[1].Title);
  Assert.AreEqual(Wert('      waZahl: (Zahl: Double);'#10'      waText: (Text: ShortString);'#10),
    TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[0].Edits));
  Source := TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[1].Edits);
  Assert.AreEqual('unit U;'#10'interface'#10'type'#10'  TArt = (waZahl, waText);'#10'  TWert = record'#10 +
    '    Text: string;'#10'    case Art: TArt of'#10'      waZahl: (Zahl: Double);'#10'      waText: ();'#10 +
    '  end;'#10'implementation'#10'end.', Source);
  Tree := TPascalParser.Parse(Source);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
  finally
    Tree.Free;
  end;
  TRuleAssert.Silent(TVariantRecordManagedFieldRule.Create, Source);
end;

procedure TDeclarationRulesTests.VariantManagedKinds;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TVariantRecordManagedFieldRule.Create, Typen('  TWert = record'#10 +
    '    case Integer of'#10'      0: (A: array of Integer);'#10'      1: (B: TBytes);'#10'      2: (C: IInterface);'#10 +
    '      3: (D: Variant);'#10'      4: (E: TName);'#10'      5: (F: array[0..1] of WideString);'#10 +
    '      6: (G: TZaehler);'#10'  end;'#10));
  Assert.AreEqual(7, Integer(Length(Findings)));
  Assert.AreEqual('array of Integer braucht Finalisierung und ist im varianten Teil nicht erlaubt (wie E2154).',
    Findings[0].Message);
  Assert.AreEqual('TName braucht Finalisierung und ist im varianten Teil nicht erlaubt (wie E2154).',
    Findings[4].Message);
  Assert.AreEqual(1, Integer(Length(Findings[4].Fixes)));
  Assert.AreEqual('TZaehler braucht Initialisierung und ist im varianten Teil nicht erlaubt (wie E2418).',
    Findings[6].Message);
end;

procedure TDeclarationRulesTests.VariantManagedMoveFixes;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // Letztes Feld eines Zweigs mit Vorgänger, Feld in der Mitte.
  Source := Wert('      waZahl: (Zahl: Double; Name, Text: string);'#10'      waText: (Wert: string; N: Integer);'#10);
  Findings := TRuleAssert.Findings(TVariantRecordManagedFieldRule.Create, Source);
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('Name,Text in den festen Teil verschieben', Findings[0].Fixes[1].Title);
  Assert.AreEqual(Wert('      waZahl: (Zahl: Double);'#10'      waText: (Wert: string; N: Integer);'#10).Replace(
    '    case', '    Name, Text: string;'#10'    case'), TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[1].Edits));
  Assert.AreEqual(Wert('      waZahl: (Zahl: Double; Name, Text: string);'#10'      waText: (N: Integer);'#10).Replace(
    '    case', '    Wert: string;'#10'    case'), TChangeSignature.ApplyEdits(Source, Findings[1].Fixes[1].Edits));
  // Verschachtelter varianter Teil: nur ShortString.
  Findings := TRuleAssert.Findings(TVariantRecordManagedFieldRule.Create, Wert('      waZahl: (Zahl: Double);'#10 +
    '      waText: (case Boolean of'#10'        True: (Text: string));'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
end;

procedure TDeclarationRulesTests.VariantManagedGenericAndFile;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Source := Typen('  TBox<T> = record'#10'    case Integer of'#10'      0: (Wert: T);'#10'      1: (Zahl: Integer);'#10 +
    '  end;'#10'  TDatei = file of string;'#10'  TZaehlerDatei = file of TZaehler;'#10);
  Findings := TRuleAssert.Findings(TVariantRecordManagedFieldRule.Create, Source);
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('Typparameter T kann Finalisierung brauchen und ist im varianten Teil nicht erlaubt; ' +
    'record-Einschränkung verwenden (wie E2569).', Findings[0].Message);
  Assert.AreEqual('T: record einschränken', Findings[0].Fixes[1].Title);
  TRuleAssert.Silent(TVariantRecordManagedFieldRule.Create, Typen('  TBox<T: record> = record'#10 +
    '    case Integer of'#10'      0: (Wert: T);'#10'  end;'#10));
  Assert.IsTrue(TChangeSignature.ApplyEdits(Source, Findings[0].Fixes[1].Edits).Contains('TBox<T: record> = record'));
  Assert.AreEqual('string braucht Finalisierung und ist in einem Dateityp nicht erlaubt (wie E2155).',
    Findings[1].Message);
  Assert.IsTrue(TChangeSignature.ApplyEdits(Source, Findings[1].Fixes[0].Edits).Contains('file of ShortString;'));
  Assert.AreEqual('TZaehler braucht Initialisierung und ist in einem Dateityp nicht erlaubt (wie E2417).',
    Findings[2].Message);
  // <K, V> ohne Einschränkung: Meldung ohne Korrektur zum Einschränken.
  Findings := TRuleAssert.Findings(TVariantRecordManagedFieldRule.Create, Typen('  TPaar<K, V> = record'#10 +
    '    case Integer of'#10'      0: (Schluessel: K);'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
end;

procedure TDeclarationRulesTests.VariantManagedFromIndex;
var
  Index: ISymbolIndex;
  Findings: TArray<TRuleFinding>;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Fremd;'#10'interface'#10'type'#10'  TFremd = record'#10 +
    '    Name: string;'#10'  end;'#10'  TFremdZaehler = record'#10'    class operator Finalize(var ADest: TFremdZaehler);'#10 +
    '  end;'#10'  TFremdZahl = record'#10'    N: Integer;'#10'  end;'#10'implementation'#10'end.', 'C:\P\Fremd.pas', nil));
  Findings := TRuleAssert.IndexFindings(TVariantRecordManagedFieldRule.Create, 'unit U;'#10'interface'#10'uses'#10 +
    '  Fremd;'#10'type'#10'  TWert = record'#10'    case Integer of'#10'      0: (A: TFremd);'#10 +
    '      1: (B: TFremdZaehler);'#10'      2: (C: TFremdZahl);'#10'  end;'#10'implementation'#10'end.', Index, '', '');
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.IsTrue(Findings[0].Message.StartsWith('TFremd braucht Finalisierung'));
  Assert.IsTrue(Findings[1].Message.StartsWith('TFremdZaehler braucht Initialisierung'));
end;

procedure TDeclarationRulesTests.VariantManagedSilentCases;
begin
  // Kurze Strings, einfache Typen, Klassen, Zeiger, unbekannte Typen, fester Teil, eingeschränkte Parameter.
  TRuleAssert.Silent(TVariantRecordManagedFieldRule.Create, Typen('  TWert = record'#10'    Name: string;'#10 +
    '    case Integer of'#10'      0: (A: ShortString);'#10'      1: (B: string[20]);'#10'      2: (C: Integer);'#10 +
    '      3: (D: TObject);'#10'      4: (E: PChar);'#10'      5: (F: TUnbekannt);'#10'      6: (G: array[0..3] of Byte);'#10 +
    '      7: (H: ^string);'#10'  end;'#10'  TBox<T: class; U: record> = record'#10'    W: T;'#10 +
    '    case Integer of'#10'      0: (A: T);'#10'      1: (B: U);'#10'  end;'#10'  TDatei = file of Integer;'#10 +
    '  TRoh = file;'#10'  TKurz = file of ShortString;'#10));
end;

procedure TDeclarationRulesTests.VariantManagedOffAndExclude;
var
  Source: string;
begin
  Source := Wert('      waText: (Text: string);'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TVariantRecordManagedFieldRule.Create, Source,
    '{"rules": {"variant-record-managed-field": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TVariantRecordManagedFieldRule.Create, Source,
    '{"rules": {"variant-record-managed-field": {"exclude": ["Source/*.pas"]}}}', 'Source/U.pas'))));
end;

function Groesse(const ATypes: string): string;
begin
  Result := 'unit U;'#10'interface'#10'type'#10 + ATypes + 'implementation'#10'end.';
end;

procedure TDeclarationRulesTests.TypeTooLargeIssueExample;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TTypeTooLargeRule.Create, Groesse('  TPuffer = array[0..High(Integer)] of Int64;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('type-too-large', Findings[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(Findings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Findings[0].Confidence));
  Assert.AreEqual('TPuffer ist 16 GB groß; erlaubt sind 2 GB (wie E2100).', Findings[0].Message);
  Assert.AreEqual(3, Findings[0].Range.StartPos.Line);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Character);
  Assert.AreEqual(9, Findings[0].Range.EndPos.Character);
  // Korrigierte Form: halber Indexbereich bzw. dynamisches Array.
  TRuleAssert.Silent(TTypeTooLargeRule.Create, Groesse('  TPuffer = array[0..High(Integer) div 16] of Int64;'#10 +
    '  TListe = array of Int64;'#10));
end;

procedure TDeclarationRulesTests.TypeTooLargeRecordsAndNames;
var
  Findings: TArray<TRuleFinding>;
begin
  // Konstanten, Aufzählung als Index, mehrdimensional, Record aus zwei großen Feldern, Variable, Folgefehler.
  Findings := TRuleAssert.Findings(TTypeTooLargeRule.Create, 'unit U;'#10'interface'#10'const'#10 +
    '  Anzahl = 1 shl 20;'#10'type'#10'  TFarbe = (Rot, Gruen, Blau);'#10 +
    '  TBlock = array[0..Anzahl - 1] of Byte;'#10'  TFlaeche = array[TFarbe, 0..Anzahl - 1, Word] of Byte;'#10 +
    '  TPaar = record'#10'    A, B: array[1..1024] of TBlock;'#10'  end;'#10'  TGross = record'#10 +
    '    Paar: TPaar;'#10'  end;'#10'var'#10'  Feld: array[Integer] of Byte;'#10'implementation'#10'end.');
  Assert.AreEqual(3, Integer(Length(Findings)));
  Assert.AreEqual('TFlaeche ist 192 GB groß; erlaubt sind 2 GB (wie E2100).', Findings[0].Message);
  Assert.AreEqual('TPaar ist mindestens 2 GB groß; erlaubt sind 2 GB (wie E2100).', Findings[1].Message);
  Assert.AreEqual('Feld ist 4 GB groß; erlaubt sind 2 GB (wie E2100).', Findings[2].Message);
  // Unbekannte Teile zählen 0, Zeiger mindestens 4 Byte.
  Findings := TRuleAssert.Findings(TTypeTooLargeRule.Create, Groesse('  TListe = array[0..$3FFFFFFF] of record'#10 +
    '    Text: string;'#10'    Fremd: TUnbekannt;'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('TListe ist mindestens 4 GB groß; erlaubt sind 2 GB (wie E2100).', Findings[0].Message);
  // Inneres Feld über der Grenze: dort gemeldet, der Record nicht noch einmal.
  Findings := TRuleAssert.Findings(TTypeTooLargeRule.Create, Groesse('  TDaten = record'#10 +
    '    A, B: array[0..MaxInt] of Int64;'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('A, B ist 16 GB groß; erlaubt sind 2 GB (wie E2100).', Findings[0].Message);
end;

procedure TDeclarationRulesTests.TypeTooLargeGenericInstance;
var
  Findings: TArray<TRuleFinding>;
begin
  Findings := TRuleAssert.Findings(TTypeTooLargeRule.Create, Groesse('  TFeld<T> = array[0..$FFFFFFF] of T;'#10 +
    '  TKlein = TFeld<Byte>;'#10'  TGross = TFeld<Int64>;'#10'  THuelle = record'#10'    Werte: TFeld<Double>;'#10 +
    '  end;'#10));
  Assert.AreEqual(2, Integer(Length(Findings)));
  Assert.AreEqual('TFeld<Int64> ist 2 GB groß; erlaubt sind 2 GB (wie E2543).', Findings[0].Message);
  Assert.AreEqual(5, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('TFeld<Double> ist 2 GB groß; erlaubt sind 2 GB (wie E2543).', Findings[1].Message);
end;

procedure TDeclarationRulesTests.TypeTooLargeSilentCases;
begin
  // Knapp unter 2 GB, dynamische Arrays, Klassen, unbekannte Grenzen, Index aus fremder Unit, typisierte Konstante.
  TRuleAssert.Silent(TTypeTooLargeRule.Create, 'unit U;'#10'interface'#10'const'#10'  Grenze: Integer = MaxInt;'#10 +
    'type'#10'  TFast = array[0..MaxInt - 1] of Byte;'#10'  TDyn = array of array of Int64;'#10 +
    '  TKlasse = class'#10'    Werte: array[0..1000] of Int64;'#10'  end;'#10 +
    '  TFremd = array[0..Fremd.Maximum] of Int64;'#10'  TTypisiert = array[0..Grenze] of Int64;'#10 +
    '  TOffen<T> = array[0..MaxInt] of T;'#10'  TKurz = array[0..$FFFF] of string[200];'#10'implementation'#10'end.');
end;

procedure TDeclarationRulesTests.TypeTooLargeOffAndExclude;
var
  Source: string;
begin
  Source := Groesse('  TPuffer = array[0..High(Integer)] of Int64;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTypeTooLargeRule.Create, Source,
    '{"rules": {"type-too-large": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TTypeTooLargeRule.Create, Source,
    '{"rules": {"type-too-large": {"exclude": ["Source/*.pas"]}}}', 'Source/U.pas'))));
end;

const
  DefaultOn = '{"rules": {"default-parameter": "warning"}}';

function DefaultFindings(const ASource: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.Findings(TDefaultParameterRule.Create, ASource, DefaultOn);
end;

/// <summary>Wendet die einzige Korrektur an; das Ergebnis muss fehlerfrei parsen.</summary>
function DefaultFixed(const ASource: string): string;
var
  Findings: TArray<TRuleFinding>;
  Tree: TSyntaxTree;
begin
  Findings := DefaultFindings(ASource);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual(1, Integer(Length(Findings[0].Fixes)));
  Result := TChangeSignature.ApplyEdits(ASource, Findings[0].Fixes[0].Edits);
  Tree := TPascalParser.Parse(Result);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), Result);
  finally
    Tree.Free;
  end;
end;

procedure TDeclarationRulesTests.DefaultParameterReportedWithFix;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  Assert.IsTrue((TDefaultParameterRule.Create as IRule).Descriptor.Experimental, 'Standard aus');
  Source := 'unit U;'#10'interface'#10'procedure Exportieren(const Datei: string; MitKopf: Boolean = True);'#10 +
    'implementation'#10'procedure Exportieren(const Datei: string; MitKopf: Boolean);'#10'begin'#10'end;'#10'end.';
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDefaultParameterRule.Create, Source))));
  Findings := DefaultFindings(Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Standardparameter; eine Überladung ohne MitKopf hält den Vorgabewert in der Bibliothek.',
    Findings[0].Message);
  Assert.AreEqual(2, Findings[0].Range.StartPos.Line);
  Assert.AreEqual('unit U;'#10'interface'#10'procedure Exportieren(const Datei: string); overload;'#10 +
    'procedure Exportieren(const Datei: string; MitKopf: Boolean); overload;'#10'implementation'#10 +
    'procedure Exportieren(const Datei: string);'#10'begin'#10'  Exportieren(Datei, True);'#10'end;'#10#10 +
    'procedure Exportieren(const Datei: string; MitKopf: Boolean);'#10'begin'#10'end;'#10'end.',
    DefaultFixed(Source));
  // Die korrigierte Form meldet nichts mehr.
  Assert.AreEqual(0, Integer(Length(DefaultFindings(DefaultFixed(Source)))));
end;

procedure TDeclarationRulesTests.DefaultParameterMethodWithSeveral;
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  // Der Rumpf wiederholt einen Standardwert; er fällt weg.
  Source := ClassUnit('  public'#10'    function Summe(A: Integer; B: Integer = 1; C: Integer = 2): Integer;',
    'function TRechner.Summe(A: Integer; B: Integer = 1; C: Integer = 2): Integer;'#10'begin'#10 +
    '  Result := A + B + C;'#10'end;', 'TRechner = class');
  Findings := DefaultFindings(Source);
  Assert.AreEqual(1, Integer(Length(Findings)));
  Assert.AreEqual('Standardparameter; Überladungen ohne B und C halten die Vorgabewerte in der Bibliothek.',
    Findings[0].Message);
  Assert.AreEqual(ClassUnit('  public'#10'    function Summe(A: Integer): Integer; overload;'#10 +
    '    function Summe(A: Integer; B: Integer): Integer; overload;'#10 +
    '    function Summe(A: Integer; B: Integer; C: Integer): Integer; overload;',
    'function TRechner.Summe(A: Integer): Integer;'#10'begin'#10'  Result := Summe(A, 1, 2);'#10'end;'#10#10 +
    'function TRechner.Summe(A: Integer; B: Integer): Integer;'#10'begin'#10'  Result := Summe(A, B, 2);'#10 +
    'end;'#10#10'function TRechner.Summe(A: Integer; B: Integer; C: Integer): Integer;'#10'begin'#10 +
    '  Result := A + B + C;'#10'end;', 'TRechner = class'), DefaultFixed(Source));
end;

procedure TDeclarationRulesTests.DefaultParameterImplementationOnly;
var
  Source: string;
begin
  Source := 'unit U;'#10'interface'#10'implementation'#10'function Teil(const S: string; N: Integer = 3): string;'#10 +
    'begin'#10'  Result := Copy(S, 1, N);'#10'end;'#10'end.';
  Assert.AreEqual('unit U;'#10'interface'#10'implementation'#10'function Teil(const S: string): string; overload;'#10 +
    'begin'#10'  Result := Teil(S, 3);'#10'end;'#10#10'function Teil(const S: string; N: Integer): string; overload;'#10 +
    'begin'#10'  Result := Copy(S, 1, N);'#10'end;'#10'end.', DefaultFixed(Source));
end;

procedure TDeclarationRulesTests.DefaultParameterWithoutFix;
const
  Cases: array[0..4] of string = (
    // virtual: Nachfahren überschreiben genau diese Signatur.
    'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'    procedure P(A: Integer = 0); virtual;'#10'  end;'#10 +
    'implementation'#10'procedure TFoo.P(A: Integer);'#10'begin'#10'end;'#10'end.',
    // Interface: jede Klasse müsste beide Überladungen umsetzen.
    'unit U;'#10'interface'#10'type'#10'  IFoo = interface'#10'    procedure P(A: Integer = 0);'#10'  end;'#10 +
    'implementation'#10'end.',
    // Als Wert benutzt: @P wäre mehrdeutig.
    'unit U;'#10'interface'#10'implementation'#10'procedure P(A: Integer = 0);'#10'begin'#10'end;'#10 +
    'procedure Q;'#10'begin'#10'  Zeiger := @P;'#10'end;'#10'end.',
    // Es gibt schon eine Überladung.
    'unit U;'#10'interface'#10'procedure P(A: Integer = 0); overload;'#10'procedure P(const S: string); overload;'#10 +
    'implementation'#10'procedure P(A: Integer);'#10'begin'#10'end;'#10'procedure P(const S: string);'#10'begin'#10 +
    'end;'#10'end.',
    // Bedingte Übersetzung.
    'unit U;'#10'interface'#10'{$IFDEF DEBUG}'#10'procedure P(A: Integer = 0);'#10'{$ENDIF}'#10'implementation'#10 +
    '{$IFDEF DEBUG}'#10'procedure P(A: Integer);'#10'begin'#10'end;'#10'{$ENDIF}'#10'end.');
var
  Source: string;
  Findings: TArray<TRuleFinding>;
begin
  for Source in Cases do
  begin
    Findings := DefaultFindings(Source);
    Assert.AreEqual(1, Integer(Length(Findings)), Source);
    Assert.AreEqual(0, Integer(Length(Findings[0].Fixes)), Source);
  end;
  // Ohne Standardwert keine Meldung; der Rumpf zur Deklaration zählt nicht doppelt.
  Assert.AreEqual(0, Integer(Length(DefaultFindings('unit U;'#10'interface'#10'procedure P(A: Integer);'#10 +
    'implementation'#10'procedure P(A: Integer);'#10'begin'#10'end;'#10'end.'))));
end;

procedure TDeclarationRulesTests.DefaultParameterSwitchedOff;
var
  Source: string;
begin
  Source := 'unit U;'#10'interface'#10'implementation'#10'procedure P(A: Integer = 0);'#10'begin'#10'end;'#10'end.';
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDefaultParameterRule.Create, Source,
    '{"rules": {"default-parameter": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TDefaultParameterRule.Create, Source,
    '{"rules": {"default-parameter": {"severity": "warning", "exclude": ["Alt/**"]}}}', 'Alt/U.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TDefaultParameterRule.Create, Source,
    '{"rules": {"default-parameter": {"severity": "warning", "exclude": ["Alt/**"]}}}', 'Neu/U.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TDeclarationRulesTests);

end.
