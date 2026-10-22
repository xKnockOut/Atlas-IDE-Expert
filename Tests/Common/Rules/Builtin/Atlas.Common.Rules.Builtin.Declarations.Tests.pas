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
// duplicate-declaration (#988): Beispiel mit Korrekturen, Bereiche (Routine,
// Typ, Record mit variantem Teil, Unit), uses mit checkUses, stille Fälle und
// Optionen.

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
    procedure DuplicateDeclarationIssueExample;
    [Test]
    procedure DuplicateDeclarationScopes;
    [Test]
    procedure DuplicateDeclarationUses;
    [Test]
    procedure DuplicateDeclarationSilentCases;
    [Test]
    procedure DuplicateDeclarationOptions;
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

initialization
  TDUnitX.RegisterTestFixture(TDeclarationRulesTests);

end.
