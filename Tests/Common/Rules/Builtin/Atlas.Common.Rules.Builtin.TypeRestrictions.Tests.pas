unit Atlas.Common.Rules.Builtin.TypeRestrictions.Tests;

// Tests der Sprachregeln für Typdeklarationen: operator-declaration-invalid
// (#1030) mit dem Beispiel samt Korrektur in Deklaration und Rumpf, allen
// Codes (E2393, E2517, E2518, E2519, E2521, E2617, E2037), stillen
// Fällen (richtige Operatoren, Aliase, unbekannte Typen, Klassen) und Abschalten;
// generic-declaration-invalid (#1029) mit dem Beispiel und je Gruppe von
// Codes ein gemeldeter und ein stiller Fall, still bei Methodenzuordnungen
// (#1325); type-restriction-violated (#994)
// mit dem Beispiel samt Korrektur, Records, lokalen Records, Helfern,
// Klassenkonstruktoren, inline, threadvar und der Option disabledChecks.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TOperatorDeclarationInvalidTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure UnknownOperatorName;
    [Test]
    procedure ParameterCount;
    [Test]
    procedure OwnTypeMissing;
    [Test]
    procedure IncResultAndAncestor;
    [Test]
    procedure AssignNeedsVar;
    [Test]
    procedure CorrectOperatorsAreSilent;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TGenericDeclarationInvalidTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure Constraints;
    [Test]
    procedure TypesWithoutParameters;
    [Test]
    procedure MethodsWithoutParameters;
    [Test]
    procedure ClassReferencesAndAttributes;
    [Test]
    procedure ShadowedTypeParameter;
    [Test]
    procedure MethodResolutionIsNoDeclaration;
    [Test]
    procedure TypeArgumentCount;
    [Test]
    procedure LocalSymbolsInGenericMethods;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TTypeRestrictionViolatedTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure RecordMembers;
    [Test]
    procedure LocalAndAnonymousRecords;
    [Test]
    procedure Helpers;
    [Test]
    procedure ClassConstructors;
    [Test]
    procedure InlineRoutines;
    [Test]
    procedure ThreadVars;
    [Test]
    procedure DisabledChecksOffAndExclude;
  end;

  [TestFixture]
  TAttributeUsageInvalidTests = class
  public
    [Test]
    procedure IssueExample;
    [Test]
    procedure WeakTargets;
    [Test]
    procedure Duplicates;
    [Test]
    procedure VolatileTargets;
    [Test]
    procedure ConstantArguments;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TTypeInfoInvalidTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure Variables;
    [Test]
    procedure TypesWithoutTypeInfo;
    [Test]
    procedure SilentCases;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.TypeRestrictions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function OperatorFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TOperatorDeclarationInvalidRule.Create, ASource);
end;

function OperatorFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TOperatorDeclarationInvalidRule.Create, ASource, AConfig, APath);
end;

/// <summary>Unit mit TGeld (Record), den Mitgliedern AMembers und den Rümpfen ABodies.</summary>
function Geld(const AMembers, ABodies: string): string; overload;
begin
  Result := 'unit Geld;'#10'interface'#10'type'#10'  TGeld = record'#10'    Betrag: Currency;'#10 + AMembers +
    '  end;'#10'implementation'#10 + ABodies + 'end.';
end;

/// <summary>Wie Geld(AMembers, ABodies) ohne Rümpfe.</summary>
function Geld(const AMembers: string): string; overload;
begin
  Result := Geld(AMembers, '');
end;

procedure TOperatorDeclarationInvalidTests.IssueExampleWithFix;
var
  Source: string;
begin
  // Beispiel aus #1030: Equal mit Integer-Ergebnis. dcc übersetzt Vergleiche mit anderem Ergebnis als Boolean
  // (Spring4D Persistence.Criteria, OP1-OP5, #1328); E2520 meldet die Regel daher nicht mehr.
  Source := Geld('    class operator Equal(const A, B: TGeld): Integer;'#10,
    'class operator TGeld.Equal(const A, B: TGeld): Integer;'#10'begin'#10'  Result := 0;'#10'end;'#10);
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Source))));
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Geld('    class operator LessThan(const A, B: TGeld): TGeld;'#10)))));
end;

procedure TOperatorDeclarationInvalidTests.UnknownOperatorName;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Geld('    class operator Addition(const A, B: TGeld): TGeld;'#10,
    'class operator TGeld.Addition(const A, B: TGeld): TGeld;'#10'begin'#10'end;'#10);
  Found := OperatorFindings(Source);
  // Zum Rumpf meldet dcc E2037 (Cm.E2393, #1380).
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Unbekannter Operator Addition (wie E2393).', Found[0].Message);
  Assert.AreEqual('Zu TGeld.Addition gibt es keine gültige Deklaration; der Rumpf passt zu nichts (wie E2037).',
    Found[1].Message);
  Assert.AreEqual(8, Found[1].Range.StartPos.Line);
  Assert.AreEqual(21, Found[1].Range.StartPos.Character);
  Source := Geld('    class operator Substract(const A, B: TGeld): TGeld;'#10,
    'class operator TGeld.Substract(const A, B: TGeld): TGeld;'#10'begin'#10'end;'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('Unbekannter Operator Substract; gemeint ist wohl Subtract (wie E2393).', Found[0].Message);
  Assert.AreEqual('In Subtract umbenennen', Found[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Geld('    class operator Subtract(const A, B: TGeld): TGeld;'#10,
    'class operator TGeld.Subtract(const A, B: TGeld): TGeld;'#10'begin'#10'end;'#10), Fixed);
end;

procedure TOperatorDeclarationInvalidTests.ParameterCount;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Geld('    class operator Negative(const A, B: TGeld): TGeld;'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der Operator Negative muss 1 Parameter haben (wie E2517).', Found[0].Message);
  Assert.AreEqual('Parameter nach Vorlage: (const A: TGeld)', Found[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Geld('    class operator Negative(const A: TGeld): TGeld;'#10), Fixed);
  Found := OperatorFindings(Geld('    class operator Add(const A: TGeld): TGeld;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der Operator Add muss 2 Parameter haben (wie E2517).', Found[0].Message);
  // Umwandlungen ohne Vorlage.
  Found := OperatorFindings(Geld('    class operator Implicit(A: Integer; B: TGeld): TGeld;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TOperatorDeclarationInvalidTests.OwnTypeMissing;
var
  Found: TArray<TRuleFinding>;
begin
  Found := OperatorFindings(Geld('    class operator Add(A, B: Integer): TGeld;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der Operator Add muss TGeld in mindestens einem Parameter haben (wie E2518).', Found[0].Message);
  Found := OperatorFindings(Geld('    class operator Implicit(A: Integer): string;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Implicit muss TGeld als Parameter oder Ergebnis haben (wie E2521).', Found[0].Message);
  // Unbekannter Typ aus einer anderen Unit: keine Aussage.
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Geld('    class operator Add(A, B: TFremd): TGeld;'#10)))));
  // Alias des eigenen Typs.
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Geld('    class operator Add(A, B: TMoney): TGeld;'#10).Replace(
    'implementation', 'type'#10'  TMoney = TGeld;'#10'implementation')))));
end;

procedure TOperatorDeclarationInvalidTests.IncResultAndAncestor;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Geld('    class operator Inc(const A: TGeld): Integer;'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Inc muss denselben Typ liefern wie den ersten Parameter, hier TGeld (wie E2519).',
    Found[0].Message);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Geld('    class operator Inc(const A: TGeld): TGeld;'#10), Fixed);
  // Klasse mit Umwandlung in den Vorfahren: Delphi 13 lehnt den Operator in einer Klasse schon als E2123 ab
  // (Regel syntax), E2522 gibt es nicht mehr (#1382).
  Found := OperatorFindings('unit Tiere;'#10'interface'#10'type'#10'  TTier = class'#10'  end;'#10 +
    '  THund = class(TTier)'#10'    class operator Implicit(A: THund): TTier;'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(0, Integer(Length(Found)));
  // Klassenoperatoren gibt es nur in Records: Der Rumpf passt zu nichts (Cm.E2522, #1380).
  Found := OperatorFindings('unit Tiere;'#10'interface'#10'type'#10'  TTier = class'#10'  end;'#10 +
    '  THund = class(TTier)'#10'    class operator Implicit(A: THund): TTier;'#10'  end;'#10'implementation'#10#10 +
    'class operator THund.Implicit(A: THund): TTier;'#10'begin'#10'  Result := A;'#10'end;'#10#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Zu THund.Implicit gibt es keine gültige Deklaration; der Rumpf passt zu nichts (wie E2037).',
    Found[0].Message);
end;

procedure TOperatorDeclarationInvalidTests.AssignNeedsVar;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Geld('    class operator Assign(const Dest: TGeld; const [ref] Src: TGeld);'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der erste Parameter von Assign muss ein var-Parameter des eigenen Typs sein (wie E2617).', Found[0].Message);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Geld('    class operator Assign(var Dest: TGeld; const [ref] Src: TGeld);'#10), Fixed);
  Source := Geld('    class operator Assign(Dest: TGeld; const [ref] Src: TGeld);'#10);
  Fixed := TChangeSignature.ApplyEdits(Source, OperatorFindings(Source)[0].Fixes[0].Edits);
  Assert.AreEqual(Geld('    class operator Assign(var Dest: TGeld; const [ref] Src: TGeld);'#10), Fixed);
end;

procedure TOperatorDeclarationInvalidTests.CorrectOperatorsAreSilent;
begin
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Geld(
    '    class operator Equal(const A, B: TGeld): Boolean;'#10 +
    '    class operator NotEqual(const A, B: TGeld): Boolean; inline;'#10 +
    '    class operator Add(const A: TGeld; B: Currency): TGeld;'#10 +
    '    class operator In(A: Integer; const B: TGeld): Boolean;'#10 +
    '    class operator Implicit(A: Currency): TGeld;'#10 +
    '    class operator Explicit(const A: TGeld): Currency;'#10 +
    '    class operator Negative(const A: TGeld): TGeld;'#10 +
    '    class operator Inc(const A: TGeld): TGeld;'#10 +
    '    class operator Initialize(out Dest: TGeld);'#10 +
    '    class operator Finalize(var Dest: TGeld);'#10 +
    '    class operator Assign(var Dest: TGeld; const [ref] Src: TGeld);'#10 +
    '    class operator True(const A: TGeld): Boolean;'#10 +
    '    class operator GreaterThan(const A, B: TGeld): TBoolAlias;'#10 +
    '    class function Add(A, B: Integer): Integer; static;'#10)))));
  // Generischer Record.
  Assert.AreEqual(0, Integer(Length(OperatorFindings('unit G;'#10'interface'#10'type'#10'  TBox<T> = record'#10 +
    '    class operator Implicit(const A: T): TBox<T>;'#10'    class operator Equal(const A, B: TBox<T>): Boolean;'#10 +
    '  end;'#10'implementation'#10'end.'))));
end;

procedure TOperatorDeclarationInvalidTests.OffAndExclude;
var
  Source: string;
begin
  Source := Geld('    class operator Inc(const A: TGeld): Integer;'#10);
  Assert.AreEqual(1, Integer(Length(OperatorFindings(Source, '', 'Source/Geld.pas'))));
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Source, '{"rules": {"operator-declaration-invalid": "off"}}',
    'Source/Geld.pas'))));
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Geld.pas'))));
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Source,
    '{"rules": {"operator-declaration-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Geld.pas'))));
end;

function GenericFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TGenericDeclarationInvalidRule.Create, ASource);
end;

function GenericFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TGenericDeclarationInvalidRule.Create, ASource, AConfig, APath);
end;

/// <summary>Meldungen von AFound mit Zeile (ab 1), getrennt durch |.</summary>
function Messages(const AFound: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFound do
  begin
    if Result <> '' then
      Result := Result + '|';
    Result := Result + IntToStr(Finding.Range.StartPos.Line + 1) + ': ' + Finding.Message;
  end;
end;

/// <summary>Unit G mit den Typen ATypes im interface-Teil und AImplementation dahinter.</summary>
function GenericUnit(const ATypes, AImplementation: string): string;
begin
  Result := 'unit G;'#10'interface'#10'type'#10 + ATypes + 'implementation'#10 + AImplementation + 'end.';
end;

procedure TGenericDeclarationInvalidTests.IssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := GenericFindings('unit G;'#10'interface'#10'procedure Tauschen<T>(var A, B: T);'#10'implementation'#10 +
    'procedure Tauschen<T>(var A, B: T);'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Globale Routinen dürfen keine Typparameter haben; als class-Methode eines Records deklarieren ' +
    '(wie E2530).', Found[0].Message);
  Assert.AreEqual(2, Found[0].Range.StartPos.Line);
  Assert.AreEqual(10, Found[0].Range.StartPos.Character);
  Assert.AreEqual(21, Found[0].Range.EndPos.Character);
  // Nur im implementation-Teil: dort gemeldet.
  Assert.AreEqual('4: Globale Routinen dürfen keine Typparameter haben; als class-Methode eines Records ' +
    'deklarieren (wie E2530).', Messages(GenericFindings('unit G;'#10'interface'#10'implementation'#10 +
    'procedure Tauschen<T>(var A, B: T);'#10'begin'#10'end;'#10'end.')));
  // Richtig: class-Methode eines Records.
  Assert.AreEqual('', Messages(GenericFindings(GenericUnit(
    '  TTausch = record'#10'    class procedure Tauschen<T>(var A, B: T); static;'#10'  end;'#10,
    'class procedure TTausch.Tauschen<T>(var A, B: T);'#10'var'#10'  C: T;'#10'begin'#10'  C := A;'#10 +
    '  A := B;'#10'  B := C;'#10'end;'#10))));
end;

procedure TGenericDeclarationInvalidTests.Constraints;
begin
  Assert.AreEqual('4: class und record lassen sich nicht zusammen fordern (wie E2507).',
    Messages(GenericFindings(GenericUnit('  TA<T: class, record> = class'#10'  end;'#10, ''))));
  Assert.AreEqual('4: Die Einschränkung constructor steht doppelt (wie E2603).',
    Messages(GenericFindings(GenericUnit('  TA<T: class, constructor, constructor> = class'#10'  end;'#10, ''))));
  Assert.AreEqual('4: constructor widerspricht der Einschränkung record (wie E2516).',
    Messages(GenericFindings(GenericUnit('  TA<T: record, constructor> = class'#10'  end;'#10, ''))));
  Assert.AreEqual('6: Die Klasse TBasis lässt sich nicht zusammen mit class bzw. record fordern (wie E2552).',
    Messages(GenericFindings(GenericUnit('  TBasis = class'#10'  end;'#10'  TA<T: class, TBasis> = class'#10 +
    '  end;'#10, ''))));
  Assert.AreEqual('8: Nur eine Klasse ist als Einschränkung erlaubt; TZwei ist die zweite (wie E2553).',
    Messages(GenericFindings(GenericUnit('  TEins = class'#10'  end;'#10'  TZwei = class'#10'  end;'#10 +
    '  TA<T: TEins, TZwei> = class'#10'  end;'#10, ''))));
  Assert.AreEqual('4: Integer ist keine gültige Einschränkung; erlaubt sind Klassen, Interfaces, class, record ' +
    'und constructor (wie E2510).|9: TPunkt ist keine gültige Einschränkung; erlaubt sind Klassen, Interfaces, ' +
    'class, record und constructor (wie E2510).', Messages(GenericFindings(GenericUnit(
    '  TA<T: Integer> = class'#10'  end;'#10'  TPunkt = record'#10'  end;'#10'  TB = class'#10 +
    '    procedure M<T: TPunkt>;'#10'  end;'#10, ''))));
  // Zweite Gruppe nach Semikolon, verschachtelte Typargumente.
  Assert.AreEqual('4: class und record lassen sich nicht zusammen fordern (wie E2507).',
    Messages(GenericFindings(GenericUnit('  TA<K: IComparable<K>; V: record, class> = class'#10'  end;'#10, ''))));
  // Zulässige und nicht sicher bekannte Einschränkungen.
  Assert.AreEqual('', Messages(GenericFindings(GenericUnit(
    '  IFoo = interface'#10'  end;'#10'  TPunkt = record'#10'  end;'#10'  TZahl = Integer;'#10 +
    '  TA<T: class, constructor; U: record; V: TComponent, IFoo, constructor> = class'#10'  end;'#10 +
    '  TB<T: TZahl; U: IComparer<T>; W: TFremd; X: Unit2.TPunkt> = class'#10'  end;'#10 +
    '  TC<T: IFoo, IInterface> = class'#10'    procedure M<U: T>;'#10'  end;'#10, ''))));
end;

procedure TGenericDeclarationInvalidTests.TypesWithoutParameters;
const
  Hint = ' darf keine Typparameter haben; erlaubt sind sie an Klassen, Records, Interfaces, Arrays und ' +
    'Prozedurtypen (wie E2508).';
begin
  Assert.AreEqual('4: Der Typ TE' + Hint + '|5: Der Typ TL' + Hint + '|6: Der Typ TZ' + Hint + '|7: Der Typ TM' +
    Hint + '|8: Der Typ TH' + Hint, Messages(GenericFindings(GenericUnit(
    '  TE<T> = (eA, eB);'#10'  TL<T> = TList<T>;'#10'  TZ<T> = ^Integer;'#10'  TM<T> = set of Byte;'#10 +
    '  TH<T> = class helper for TObject'#10'  end;'#10, ''))));
  Assert.AreEqual('', Messages(GenericFindings(GenericUnit(
    '  TK<T> = class;'#10'  TK<T> = class'#10'  end;'#10'  TR<T> = record'#10'  end;'#10 +
    '  II<T> = interface'#10'  end;'#10'  TArr<T> = array of T;'#10'  TP<T> = reference to procedure(A: T);'#10 +
    '  TF<T> = function: T;'#10'  TE = (eA, eB);'#10'  TL = TList<Integer>;'#10, ''))));
end;

procedure TGenericDeclarationInvalidTests.MethodsWithoutParameters;
begin
  Assert.AreEqual('6: Operatoren dürfen keine Typparameter haben (wie E2529).|' +
    '7: Destruktoren dürfen keine Typparameter haben (wie E2528).|' +
    '8: Klassenkonstruktoren dürfen keine Typparameter haben (wie E2528).|' +
    '9: Virtuelle, dynamische und message-Methoden dürfen keine Typparameter haben (wie E2533).|' +
    '10: Virtuelle, dynamische und message-Methoden dürfen keine Typparameter haben (wie E2533).|' +
    '13: Interface-Methoden dürfen keine Typparameter haben (wie E2535).',
    Messages(GenericFindings(GenericUnit(
    '  TA = class'#10'  public'#10 +
    '    class operator Add<T>(const A, B: TA): TA;'#10 +
    '    destructor Destroy<T>;'#10 +
    '    class constructor Create<T>;'#10 +
    '    procedure Laden<T>; virtual;'#10 +
    '    procedure Lesen<T>(A: T); override;'#10 +
    '  end;'#10 +
    '  IA = interface'#10 +
    '    procedure Schreiben<T>(A: T);'#10 +
    '  end;'#10, ''))));
  Assert.AreEqual('', Messages(GenericFindings(GenericUnit(
    '  TA = class'#10'  public'#10'    class function Neu<T>: T; static;'#10'    constructor Create<T>(A: T);'#10 +
    '    procedure Laden<T>(A: T);'#10'    procedure Lesen; virtual;'#10'    destructor Destroy; override;'#10 +
    '  end;'#10,
    'procedure TA.Laden<T>(A: T);'#10'begin'#10'end;'#10))));
end;

procedure TGenericDeclarationInvalidTests.ClassReferencesAndAttributes;
begin
  Assert.AreEqual('6: class of ist für parametrisierte Typen nicht erlaubt (wie E2548).',
    Messages(GenericFindings(GenericUnit('  TListe<T> = class'#10'  end;'#10 +
    '  TListeKlasse = class of TListe<Integer>;'#10, ''))));
  Assert.AreEqual('4: Die Attributklasse TNamen darf keine Typparameter haben (wie E2549).|' +
    '8: Die Attributklasse TMehr darf keine Typparameter haben (wie E2549).',
    Messages(GenericFindings(GenericUnit('  TNamen<T> = class(TCustomAttribute)'#10'  end;'#10 +
    '  TEigenes = class(TCustomAttribute)'#10'  end;'#10'  TMehr<T> = class(TEigenes)'#10'  end;'#10, ''))));
  Assert.AreEqual('6: Parametrisierte Typen können nicht als Attribut stehen (wie E2565).|' +
    '8: Parametrisierte Typen können nicht als Attribut stehen (wie E2565).',
    Messages(GenericFindings(GenericUnit('  TMarke = class(TCustomAttribute)'#10'  end;'#10 +
    '  [TMarke<Integer>]'#10'  TA = class'#10'    [TMarke<string>(''x'')]'#10'    procedure M;'#10'  end;'#10, ''))));
  Assert.AreEqual('', Messages(GenericFindings(GenericUnit('  TMarke = class(TCustomAttribute)'#10'  end;'#10 +
    '  TListe<T> = class'#10'  end;'#10'  TKlasse = class of TMarke;'#10'  [TMarke]'#10'  TA<T> = class'#10 +
    '  end;'#10, ''))));
end;

procedure TGenericDeclarationInvalidTests.ShadowedTypeParameter;
begin
  Assert.AreEqual('5: Der Typparameter T verdeckt den gleichnamigen Typparameter von TListe (wie H2509).',
    Messages(GenericFindings(GenericUnit('  TListe<T> = class'#10'    procedure Hinzu<T>(A: T);'#10'  end;'#10,
    'procedure TListe<T>.Hinzu<T>(A: T);'#10'begin'#10'end;'#10))));
  Assert.AreEqual('', Messages(GenericFindings(GenericUnit('  TListe<T> = class'#10'    procedure Hinzu<U>(A: U);'#10 +
    '  end;'#10'  TAndere<U> = class'#10'  end;'#10, ''))));
end;

procedure TGenericDeclarationInvalidTests.MethodResolutionIsNoDeclaration;
begin
  // F03 mit generischem Interface: IEnumerator<T>.GetCurrent = GetCurrentGen nennt das T des Interfaces und
  // deklariert keinen eigenen Typparameter (#1325).
  Assert.AreEqual('', Messages(GenericFindings(GenericUnit('  TE<T> = class(TInterfacedObject, IEnumerator<T>)'#10 +
    '    function GetCurrentGen: T;'#10'    function IEnumerator<T>.GetCurrent = GetCurrentGen;'#10'  end;'#10,
    'function TE<T>.GetCurrentGen: T;'#10'begin'#10'  Result := Default(T);'#10'end;'#10))));
  // Gegenprobe: eine eigene Methode mit verdeckendem Typparameter wird weiter gemeldet.
  Assert.AreEqual('6: Der Typparameter T verdeckt den gleichnamigen Typparameter von TE (wie H2509).',
    Messages(GenericFindings(GenericUnit('  TE<T> = class(TInterfacedObject, IEnumerator<T>)'#10 +
    '    function IEnumerator<T>.GetCurrent = GetCurrentGen;'#10'    procedure Hinzu<T>(A: T);'#10'  end;'#10,
    'procedure TE<T>.Hinzu<T>(A: T);'#10'begin'#10'end;'#10))));
end;

procedure TGenericDeclarationInvalidTests.TypeArgumentCount;
var
  Source: string;
begin
  Source := GenericUnit('  TA = class'#10'    class function F<T>(X: T): T; static;'#10 +
    '    class function F<T, U>(X: T; Y: U): T; overload; static;'#10'    procedure M;'#10'  end;'#10,
    'procedure TA.M;'#10'begin'#10'  F<Integer>(1);'#10'  TA.F<Integer, string>(1, ''a'');'#10 +
    '  Self.F<Integer, string, Byte>(2);'#10'  X := TA.F<Integer, Byte, Word>(1) + 1;'#10'end;'#10);
  Assert.AreEqual('14: F hat keine Variante mit 3 Typparametern; deklariert: F<T>, F<T, U> (wie E2551).|' +
    '15: F hat keine Variante mit 3 Typparametern; deklariert: F<T>, F<T, U> (wie E2551).',
    Messages(GenericFindings(Source)));
  // Vorfahr außerhalb der Datei, with und nicht generische Variante: still.
  Assert.AreEqual('', Messages(GenericFindings(GenericUnit(
    '  TA = class(TFremd)'#10'    class function F<T>: T; static;'#10'    procedure M;'#10'  end;'#10 +
    '  TB = class'#10'    class function F<T>: T; overload; static;'#10'    class function F: Integer; overload;' +
    ' static;'#10'    procedure M;'#10'  end;'#10,
    'procedure TA.M;'#10'begin'#10'  F<Integer, string>;'#10'end;'#10'procedure TB.M;'#10'begin'#10 +
    '  F<Integer, string>;'#10'  with Liste do'#10'    F<Integer, string>;'#10'end;'#10))));
end;

procedure TGenericDeclarationInvalidTests.LocalSymbolsInGenericMethods;
var
  Source: string;
begin
  Source := GenericUnit('  TListe<T> = class'#10'    procedure Pruefen;'#10'  end;'#10 +
    '  TWerkzeug = class'#10'    class function Neu<T>: T; static;'#10'  end;'#10,
    'const'#10'  Grenze = 10;'#10'type'#10'  THilfe = class'#10'  end;'#10 +
    'function Hilf: Integer;'#10'begin'#10'  Result := 1;'#10'end;'#10 +
    'procedure TListe<T>.Pruefen;'#10'var'#10'  H: THilfe;'#10'begin'#10'  if Hilf > Grenze then'#10 +
    '    Exit;'#10'  if Grenze = 0 then'#10'    Exit;'#10'end;'#10 +
    'class function TWerkzeug.Neu<T>: T;'#10'begin'#10'  Result := Default(T);'#10'  Hilf;'#10'end;'#10);
  Assert.AreEqual('22: TListe.Pruefen gehört zu einem generischen Typ bzw. ist generisch, steht im interface-Teil ' +
    'und darf THilfe aus dem implementation-Teil nicht verwenden (wie E2506).|' +
    '24: TListe.Pruefen gehört zu einem generischen Typ bzw. ist generisch, steht im interface-Teil und darf Hilf ' +
    'aus dem implementation-Teil nicht verwenden (wie E2506).|' +
    '24: TListe.Pruefen gehört zu einem generischen Typ bzw. ist generisch, steht im interface-Teil und darf ' +
    'Grenze aus dem implementation-Teil nicht verwenden (wie E2506).|' +
    '32: TWerkzeug.Neu gehört zu einem generischen Typ bzw. ist generisch, steht im interface-Teil und darf Hilf ' +
    'aus dem implementation-Teil nicht verwenden (wie E2506).', Messages(GenericFindings(Source)));
  // Gleichnamige Mitglieder, lokale Namen, Deklarationen im interface-Teil, with und nicht generische Typen.
  Source := GenericUnit('  TListe<T> = class'#10'  private'#10'    Grenze: Integer;'#10'    procedure Pruefen;'#10 +
    '  end;'#10'  TFest = class'#10'    procedure Pruefen;'#10'  end;'#10'const'#10'  Oben = 1;'#10,
    'const'#10'  Grenze = 10;'#10'  Hilf = 2;'#10'  Oben = 3;'#10 +
    'procedure TListe<T>.Pruefen;'#10'var'#10'  Hilf: Integer;'#10'begin'#10'  Hilf := Grenze + Oben;'#10 +
    '  with Self do'#10'    Hilf := Grenze;'#10'end;'#10 +
    'procedure TFest.Pruefen;'#10'begin'#10'  if Hilf > Grenze then'#10'    Exit;'#10'end;'#10);
  Assert.AreEqual('', Messages(GenericFindings(Source)));
end;

procedure TGenericDeclarationInvalidTests.OffAndExclude;
var
  Source: string;
begin
  Source := GenericUnit('  TA<T: class, record> = class'#10'  end;'#10, '');
  Assert.AreEqual(1, Integer(Length(GenericFindings(Source, '', 'Source/G.pas'))));
  Assert.AreEqual(0, Integer(Length(GenericFindings(Source, '{"rules": {"generic-declaration-invalid": "off"}}',
    'Source/G.pas'))));
  Assert.AreEqual(0, Integer(Length(GenericFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/G.pas'))));
  Assert.AreEqual(0, Integer(Length(GenericFindings(Source,
    '{"rules": {"generic-declaration-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/G.pas'))));
end;

function RestrictionFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TTypeRestrictionViolatedRule.Create, ASource);
end;

function RestrictionFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TTypeRestrictionViolatedRule.Create, ASource, AConfig, APath);
end;

procedure TTypeRestrictionViolatedTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := GenericUnit('  TPunkt = record'#10'    X, Y: Integer;'#10'    function Laenge: Double; virtual;'#10 +
    '  end;'#10, '');
  Found := RestrictionFindings(Source);
  Assert.AreEqual('6: Records erlauben keine virtuellen Methoden (wie E2379).', Messages(Found));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('virtual entfernen', Found[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(GenericUnit('  TPunkt = record'#10'    X, Y: Integer;'#10'    function Laenge: Double;'#10 +
    '  end;'#10, ''), Fixed);
  Assert.AreEqual('', Messages(RestrictionFindings(Fixed)));
end;

procedure TTypeRestrictionViolatedTests.RecordMembers;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := GenericUnit('  TR = record'#10 +
    '    procedure A; override;'#10 +
    '    function B: Integer; virtual; abstract;'#10 +
    '    constructor Create;'#10 +
    '    constructor Neu(X: Integer = 0; Y: Integer = 1);'#10 +
    '    destructor Destroy;'#10 +
    '    class procedure C;'#10 +
    '  end;'#10, '');
  Found := RestrictionFindings(Source);
  Assert.AreEqual('5: Die Direktive override ist in Records nicht erlaubt (wie E2463).|' +
    '6: Records erlauben keine virtuellen Methoden (wie E2379).|' +
    '7: Records erlauben keine parameterlosen Konstruktoren (wie E2394).|' +
    '8: Records erlauben keine Konstruktoren, die ohne Argumente aufrufbar sind; alle Parameter haben ' +
    'Vorgabewerte (wie E2471).|' +
    '9: Records dürfen keinen Destruktor einführen (wie E2465).|' +
    '10: Klassenmethoden in Records müssen static sein (wie E2398).', Messages(Found));
  // virtual und abstract gehen zusammen weg.
  Fixed := TChangeSignature.ApplyEdits(Source, Found[1].Fixes[0].Edits);
  Assert.IsTrue(Pos('    function B: Integer;'#10, Fixed) > 0, Fixed);
  Assert.AreEqual('static ergänzen', Found[5].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[5].Fixes[0].Edits);
  Assert.IsTrue(Pos('    class procedure C; static;'#10, Fixed) > 0, Fixed);
  // Erlaubtes.
  Assert.AreEqual('', Messages(RestrictionFindings(GenericUnit('  TR = record'#10 +
    '    constructor Create(X: Integer; Y: Integer = 1);'#10'    class function Neu: TR; static;'#10 +
    '    class constructor Init;'#10'    class destructor Fertig;'#10 +
    '    class operator Add(const A, B: TR): TR;'#10'    procedure M; inline;'#10'  end;'#10 +
    '  TO = object'#10'    procedure V; virtual;'#10'  end;'#10, ''))));
end;

procedure TTypeRestrictionViolatedTests.LocalAndAnonymousRecords;
begin
  Assert.AreEqual('7: Lokale und anonyme Records dürfen keine Methoden deklarieren (wie E2433).|' +
    '8: Lokale und anonyme Records dürfen keine Properties deklarieren (wie E2434).|' +
    '9: Lokale und anonyme Records dürfen keine Klassenmitglieder deklarieren (wie E2435).|' +
    '10: Lokale und anonyme Records dürfen keine Typen deklarieren (wie E2436).|' +
    '12: Lokale und anonyme Records dürfen keine Konstanten deklarieren (wie E2437).|' +
    '17: Lokale und anonyme Records dürfen keine Methoden deklarieren (wie E2433).',
    Messages(RestrictionFindings('unit G;'#10'interface'#10'implementation'#10'procedure Lokal;'#10 +
    'type'#10'  TL = record'#10'    procedure M;'#10'    property P: Integer read A;'#10 +
    '    class var Z: Integer;'#10'    type'#10'      TI = Integer;'#10'    const'#10'      K = 1;'#10 +
    '  end;'#10'var'#10'  A: Integer;'#10'  R: record X: Integer; procedure N; end;'#10'begin'#10'end;'#10 +
    'end.')));
  Assert.AreEqual('', Messages(RestrictionFindings('unit G;'#10'interface'#10'implementation'#10 +
    'procedure Lokal;'#10'type'#10'  TL = record'#10'    A, B: Integer;'#10'  end;'#10'var'#10 +
    '  R: record X: Integer; end;'#10'begin'#10'end;'#10'end.')));
end;

procedure TTypeRestrictionViolatedTests.Helpers;
begin
  Assert.AreEqual('5: Helfer dürfen keine Felder deklarieren (wie E2599).|' +
    '7: Helfer dürfen keine Felder deklarieren (wie E2599).|' +
    '9: Class-Helfer dürfen keinen Destruktor einführen (wie E2295).|' +
    '15: Record-Helfer erlauben keine virtuellen Methoden (wie E2598).|' +
    '16: Die Direktive message ist in Record-Helfern nicht erlaubt (wie E2475).|' +
    '21: Der Helfer TLH kann nicht als Typ in Deklarationen stehen (wie E2527).',
    // Klassenkonstruktor (Zeile 10) und Konstruktor ohne Aufruf (Zeile 27) übersetzt dcc (Skia4Delphi, #1328).
    Messages(RestrictionFindings(GenericUnit(
    '  TLH = class helper for TList'#10 +
    '    FAnzahl: Integer;'#10 +
    '    class var FZaehler: Integer;'#10 +
    '    var FMehr: Integer;'#10 +
    '  public'#10 +
    '    destructor Destroy; override;'#10 +
    '    class constructor Init;'#10 +
    '    constructor Neu(A: Integer);'#10 +
    '    constructor Leer;'#10 +
    '  end;'#10 +
    '  TIH = record helper for Integer'#10 +
    '    function F: Integer; virtual;'#10 +
    '    procedure G(var M); message 1;'#10 +
    '    function H: Integer; inline;'#10 +
    '  end;'#10 +
    'var'#10 +
    '  Helfer: TObject;'#10 +
    '  Falsch: TLH;'#10,
    'constructor TLH.Neu(A: Integer);'#10'begin'#10'  Create;'#10'end;'#10 +
    'constructor TLH.Leer;'#10'begin'#10'  FZaehler := 1;'#10'end;'#10))));
  // Vorfahr-Helfer und generischer Kontext.
  Assert.AreEqual('14: Ein Class-Helfer, der von TBH abstammt, kann nur Nachfahren von TListe helfen (wie E2294).|' +
    '16: Ein Class-Helfer, der von TBH abstammt, kann nur Nachfahren von TListe helfen (wie E2294).|' +
    '19: Helfer dürfen nicht im Kontext eines parametrisierten Typs deklariert werden (wie E2589).',
    Messages(RestrictionFindings(GenericUnit(
    '  TAnders = class'#10'  end;'#10'  TListe = class'#10'  end;'#10'  TKind = class(TListe)'#10'  end;'#10 +
    '  TBH = class helper for TListe'#10'  end;'#10'  TGut = class helper (TBH) for TKind'#10'  end;'#10 +
    '  TFalsch = class helper (TBH) for TAnders'#10'  end;'#10'  TWurzel = class helper (TBH) for TObject end;'#10'  TG<T> = class'#10'  type'#10'    TInnen = class helper for TObject'#10'    end;'#10'  end;'#10,
    ''))));
end;

procedure TTypeRestrictionViolatedTests.ClassConstructors;
begin
  Assert.AreEqual('6: Klassenkonstruktoren dürfen keine Parameter haben (wie E2360).|' +
    '7: Mehrere Klassenkonstruktoren in TA: Init und Zwei (wie E2359).|' +
    '7: Klassenkonstruktoren dürfen nicht virtual, dynamic oder message sein (wie E2534).',
    Messages(RestrictionFindings(GenericUnit('  TA = class'#10'  public'#10 +
    '    class constructor Init(A: Integer);'#10'    class constructor Zwei; virtual;'#10'  end;'#10, ''))));
  Assert.AreEqual('', Messages(RestrictionFindings(GenericUnit('  TA = class'#10'  public'#10'  {$IFDEF X}'#10 +
    '    class constructor Init;'#10'  {$ELSE}'#10'    class constructor Init2;'#10'  {$ENDIF}'#10 +
    '    class destructor Fertig;'#10'  end;'#10, ''))));
end;

procedure TTypeRestrictionViolatedTests.InlineRoutines;
begin
  Assert.AreEqual('6: Inline-Methoden dürfen nicht virtual oder dynamic sein (wie E2425).|' +
    '7: inline ist an Konstruktoren und Destruktoren nicht erlaubt (wie E2442).|' +
    '8: Inline-Routinen dürfen keine offenen Array-Parameter haben (wie E2439).|' +
    '9: Inline-Routinen dürfen keinen asm-Block haben (wie E2426).|' +
    '21: Die Inline-Routine TA.Rechnen aus dem interface-Teil darf Grenze aus dem implementation-Teil nicht ' +
    'verwenden (wie E2441).',
    Messages(RestrictionFindings(GenericUnit('  TA = class'#10'  public'#10 +
    '    procedure V; virtual; inline;'#10'    constructor Create; inline;'#10 +
    '    function Summe(const A: array of Integer): Integer; inline;'#10'    function Roh: Integer; inline;'#10 +
    '    function Rechnen: Integer; inline;'#10'  end;'#10,
    'const'#10'  Grenze: Integer = 3;'#10'function TA.Roh: Integer;'#10'asm'#10'  mov eax, 1'#10'end;'#10 +
    'function TA.Rechnen: Integer;'#10'begin'#10'  Result := Grenze;'#10'end;'#10))));
  Assert.AreEqual('7: Die Inline-Routine Aussen darf die lokale Routine Hilfe nicht aufrufen (wie E2501).|' +
    '14: Die eingebettete lokale Routine Mitte darf nicht auf Wert der umgebenden Routine zugreifen (wie E2449).',
    Messages(RestrictionFindings('unit G;'#10'interface'#10'implementation'#10 +
    'function Aussen: Integer; inline;'#10'  function Hilfe: Integer; begin Result := 1; end;'#10'begin'#10 +
    '  Result := Hilfe;'#10'end;'#10 +
    'procedure Rahmen(Wert: Integer);'#10'var'#10'  Lokal: Integer;'#10 +
    '  function Mitte: Integer; inline;'#10'  begin'#10'    Result := Wert;'#10'  end;'#10 +
    '  function Eigen(Wert: Integer): Integer; inline;'#10'  begin'#10'    Result := Wert;'#10'  end;'#10 +
    'begin'#10'  Lokal := Mitte + Eigen(1);'#10'end;'#10'end.')));
  // Erlaubtes: inline ohne Hürde, Symbole des implementation-Teils in Routinen ohne inline oder nur im
  // implementation-Teil.
  Assert.AreEqual('', Messages(RestrictionFindings(GenericUnit('  TA = class'#10'  public'#10 +
    '    function Doppelt(A: Integer): Integer; inline;'#10'    function Weit: Integer;'#10 +
    '    function Lang(const A: TArray<Integer>): Integer; inline;'#10'  end;'#10,
    'const'#10'  Grenze = 3;'#10'function Intern: Integer; inline;'#10'begin'#10'  Result := Grenze;'#10 +
    'end;'#10'function TA.Doppelt(A: Integer): Integer;'#10'begin'#10'  Result := A * 2;'#10'end;'#10 +
    'function TA.Weit: Integer;'#10'begin'#10'  Result := Grenze;'#10'end;'#10))));
  // Echte Konstanten, Aufzählungswerte und Routinen des implementation-Teils sowie inline nur am Rumpf
  // übersetzt dcc (mORMot2, Clipper2, HtmlViewer; TR1-TR5, #1328).
  Assert.AreEqual('', Messages(RestrictionFindings(GenericUnit('  TA = class'#10'  public'#10 +
    '    function Rechnen: Integer; inline;'#10'    function Hinten: Integer;'#10'  end;'#10 +
    'function Frei: Integer; inline;'#10,
    'type'#10'  TFarbe = (fRot, fBlau);'#10'const'#10'  Grenze = 3;'#10 +
    'function Quadrat(A: Integer): Integer;'#10'begin'#10'  Result := A * A;'#10'end;'#10 +
    'function TA.Rechnen: Integer;'#10'begin'#10'  Result := Quadrat(Grenze) + Ord(fBlau);'#10'end;'#10 +
    'function TA.Hinten: Integer;'#10'  inline;'#10'var'#10'  mFarbe: TFarbe;'#10'begin'#10 +
    '  mFarbe := fRot;'#10'  Result := Ord(mFarbe);'#10'end;'#10 +
    'function Frei: Integer;'#10'var'#10'  mFarbe: TFarbe;'#10'begin'#10'  mFarbe := fBlau;'#10 +
    '  Result := Quadrat(Grenze) + Ord(mFarbe);'#10'end;'#10))));
  // Gegentest: eine Variable des implementation-Teils bleibt E2441 (TG1); Typen übersetzt dcc (TR8).
  Assert.AreEqual('12: Die Inline-Routine Frei aus dem interface-Teil darf Zaehler aus dem implementation-Teil ' +
    'nicht verwenden (wie E2441).',
    Messages(RestrictionFindings(GenericUnit('  TLeer = class'#10'  end;'#10'function Frei: Integer; inline;'#10,
    'var'#10'  Zaehler: Integer;'#10'function Frei: Integer;'#10'begin'#10'  Result := Zaehler;'#10'end;'#10))));
  // Gegentest: eine typisierte Konstante des implementation-Teils meldet dcc ebenfalls (TG4).
  Assert.AreEqual('12: Die Inline-Routine Frei aus dem interface-Teil darf Start aus dem implementation-Teil ' +
    'nicht verwenden (wie E2441).',
    Messages(RestrictionFindings(GenericUnit('  TLeer = class'#10'  end;'#10'function Frei: Integer; inline;'#10,
    'const'#10'  Start: Integer = 2;'#10'function Frei: Integer;'#10'begin'#10'  Result := Start;'#10'end;'#10))));
end;

procedure TTypeRestrictionViolatedTests.ThreadVars;
begin
  Assert.AreEqual('4: threadvar-Variablen lassen sich nicht initialisieren (wie E2194).|' +
    '5: threadvar-Variablen dürfen nicht absolute sein (wie E2190).|' +
    '9: threadvar ist nur auf Unit-Ebene erlaubt, nicht lokal in einer Routine (wie E2189).',
    Messages(RestrictionFindings('unit G;'#10'interface'#10'threadvar'#10'  Zaehler: Integer = 3;'#10 +
    '  Alias: Integer absolute Zaehler;'#10'  Gut: Integer;'#10'implementation'#10'procedure Lokal;'#10 +
    'threadvar'#10'  T: Integer;'#10'begin'#10'end;'#10'end.')));
  Assert.AreEqual('', Messages(RestrictionFindings('unit G;'#10'interface'#10'threadvar'#10'  T: Integer;'#10 +
    'var'#10'  V: Integer = 3;'#10'implementation'#10'end.')));
end;

procedure TTypeRestrictionViolatedTests.DisabledChecksOffAndExclude;
var
  Source: string;
  Issues: TArray<TConfigurationIssue>;
begin
  Source := GenericUnit('  TPunkt = record'#10'    function Laenge: Double; virtual;'#10'    class procedure C;'#10 +
    '  end;'#10, '');
  Assert.AreEqual(2, Integer(Length(RestrictionFindings(Source, '', 'Source/G.pas'))));
  Assert.AreEqual('6: Klassenmethoden in Records müssen static sein (wie E2398).', Messages(RestrictionFindings(Source,
    '{"rules": {"type-restriction-violated": {"disabledChecks": ["E2379"]}}}', 'Source/G.pas')));
  Assert.AreEqual(0, Integer(Length(RestrictionFindings(Source, '{"rules": {"type-restriction-violated": "off"}}',
    'Source/G.pas'))));
  Assert.AreEqual(0, Integer(Length(RestrictionFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/G.pas'))));
  Assert.AreEqual(0, Integer(Length(RestrictionFindings(Source,
    '{"rules": {"type-restriction-violated": {"exclude": ["Source/*.pas"]}}}', 'Source/G.pas'))));
  // Parser: disabledChecks muss eine Liste von Texten sein.
  TConfigurationParser.Parse('{"rules": {"type-restriction-violated": {"disabledChecks": "E2379"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  TConfigurationParser.Parse('{"rules": {"type-restriction-violated": {"disabledChecks": ["E2379"]}}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
end;

function AttributeFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TAttributeUsageInvalidRule.Create, ASource);
end;

function AttributeFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TAttributeUsageInvalidRule.Create, ASource, AConfig, APath);
end;

procedure TAttributeUsageInvalidTests.IssueExample;
var
  Found: TArray<TRuleFinding>;
begin
  Found := AttributeFindings(GenericUnit('  TZaehler = class'#10'  private'#10'    [Weak] FZaehler: Integer;'#10 +
    '  end;'#10, ''));
  Assert.AreEqual('6: [Weak] ist nur an Klassen- und Interface-Referenzen erlaubt; FZaehler hat den Typ Integer ' +
    '(wie E2584).', Messages(Found));
  Assert.AreEqual(5, Found[0].Range.StartPos.Character);
  Assert.AreEqual(9, Found[0].Range.EndPos.Character);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  // Korrigiert: [Weak] an einer Interface-Referenz.
  Assert.AreEqual('', Messages(AttributeFindings(GenericUnit('  TZaehler = class'#10'  private'#10 +
    '    [Weak] FBesitzer: IInterface;'#10'    FZaehler: Integer;'#10'  end;'#10, ''))));
end;

procedure TAttributeUsageInvalidTests.WeakTargets;
begin
  Assert.AreEqual('9: [Weak] ist nur an Klassen- und Interface-Referenzen erlaubt; FPunkt hat den Typ TPunkt ' +
    '(wie E2584).|' +
    '10: [Weak] ist nur an Klassen- und Interface-Referenzen erlaubt; FListe hat den Typ array of TObject ' +
    '(wie E2584).|' +
    '11: [Weak] ist nur an Klassen- und Interface-Referenzen erlaubt; FZahl hat den Typ TZahl (wie E2584).|' +
    '12: [Weak] ist nur an Klassen- und Interface-Referenzen erlaubt; FName hat den Typ string (wie E2584).|' +
    '17: [Weak] ist nur an Klassen- und Interface-Referenzen erlaubt; Global hat den Typ Boolean (wie E2584).|' +
    '21: [Weak] ist nur an Klassen- und Interface-Referenzen erlaubt; Lokal hat den Typ TFarbe (wie E2584).',
    Messages(AttributeFindings('unit G;'#10'interface'#10'type'#10'  TPunkt = record X: Integer; end;'#10 +
    '  TZahl = Integer;'#10'  TFarbe = (Rot, Gruen);'#10'  TKnoten = class'#10'  private'#10 +
    '    [Weak] FPunkt: TPunkt;'#10'    [Weak] FListe: array of TObject;'#10'    [Weak] FZahl: TZahl;'#10 +
    '    [System.WeakAttribute] FName: string;'#10'    [Weak] FEltern: TKnoten;'#10'    [Weak] FBasis: TObject;'#10 +
    '  end;'#10'var'#10'  [Weak] Global: Boolean;'#10'implementation'#10'procedure P;'#10'var'#10 +
    '  [Weak] Lokal: TFarbe;'#10'begin'#10'end;'#10'end.')));
  // Unbekannte Typen, Generics, Zeiger, Methodenzeiger und reference to bleiben still, ebenso ein eigenes Weak.
  Assert.AreEqual('', Messages(AttributeFindings(GenericUnit('  TProc = reference to procedure;'#10 +
    '  TKnoten = class'#10'  private'#10'    [Weak] FFremd: TFremd;'#10'    [Weak] FListe: TList<Integer>;'#10 +
    '    [Weak] FZeiger: Pointer;'#10'    [Weak] FAufruf: TProc;'#10'    [Weak] FEreignis: TNotifyEvent;'#10 +
    '    [Unsafe] FWert: Integer;'#10'    [Weak] procedure Tu([Weak] var A: IInterface);'#10'  end;'#10, ''))));
  Assert.AreEqual('', Messages(AttributeFindings(GenericUnit('  WeakAttribute = class(TCustomAttribute);'#10 +
    '  TKnoten = class'#10'    [Weak] FZahl: Integer;'#10'  end;'#10, ''))));
end;

procedure TAttributeUsageInvalidTests.Duplicates;
begin
  Assert.AreEqual('5: [Weak] steht mehrfach an derselben Deklaration; ein Attribut des Compilers darf je Ziel nur ' +
    'einmal stehen (wie E2326).|' +
    '6: [Unsafe] steht mehrfach an derselben Deklaration; ein Attribut des Compilers darf je Ziel nur einmal ' +
    'stehen (wie E2326).|' +
    '9: [Volatile] steht mehrfach an derselben Deklaration; ein Attribut des Compilers darf je Ziel nur einmal ' +
    'stehen (wie E2326).',
    Messages(AttributeFindings('unit G;'#10'interface'#10'type'#10'  TKnoten = class'#10 +
    '    [Weak, Weak] FA: TObject;'#10'    [Unsafe] [Unsafe] FB: IInterface;'#10'  end;'#10'var'#10 +
    '  [Volatile, Volatile] Zaehler: Integer;'#10'implementation'#10'end.')));
  // Eigene Attribute dürfen mehrfach stehen (DUnitX TestCase); sich ausschließende Zweige zählen nicht doppelt.
  Assert.AreEqual('', Messages(AttributeFindings(GenericUnit('  TTests = class'#10 +
    '    [TestCase(''A'', ''1'')]'#10'    [TestCase(''B'', ''2'')]'#10'    procedure Pruefe(A: Integer);'#10 +
    '    {$IFDEF X}[Weak]{$ELSE}[Weak]{$ENDIF} FA: TObject;'#10'    [Weak] FB: TObject;'#10 +
    '    [Unsafe] FC: TObject;'#10'  end;'#10, ''))));
end;

procedure TAttributeUsageInvalidTests.VolatileTargets;
begin
  Assert.AreEqual('4: [Volatile] gilt nur für Variablen, Parameter und Felder, nicht für Typen, Routinen, Methoden ' +
    'oder Properties (wie E2325).|' +
    '6: [Volatile] gilt nur für Variablen, Parameter und Felder, nicht für Typen, Routinen, Methoden oder ' +
    'Properties (wie E2325).|' +
    '7: [Volatile] gilt nur für Variablen, Parameter und Felder, nicht für Typen, Routinen, Methoden oder ' +
    'Properties (wie E2325).',
    Messages(AttributeFindings(GenericUnit('  [Volatile] TZaehler = class'#10'    FWert: Integer;'#10 +
    '    [Volatile] procedure Erhoehe;'#10'    [Volatile] property Wert: Integer read FWert;'#10'  end;'#10, ''))));
  Assert.AreEqual('', Messages(AttributeFindings('unit G;'#10'interface'#10'type'#10'  TZaehler = class'#10 +
    '    [Volatile] FWert: Integer;'#10'    procedure Erhoehe([Volatile] var A: Integer);'#10'  end;'#10 +
    'var'#10'  [Volatile] Global: Integer;'#10'implementation'#10'procedure TZaehler.Erhoehe(var A: Integer);'#10 +
    'begin'#10'end;'#10'end.')));
end;

procedure TAttributeUsageInvalidTests.ConstantArguments;
begin
  Assert.AreEqual('11: Das Argument Grenze von [Bereich] ist kein konstanter Ausdruck; Attributargumente müssen ' +
    'Konstanten, TypeInfo-Ausdrücke oder Array-Konstruktoren sein (wie E2448).|' +
    '12: Der Aufruf Standard in [Bereich] ist kein konstanter Ausdruck; Attributargumente müssen Konstanten, ' +
    'TypeInfo-Ausdrücke oder Array-Konstruktoren sein (wie E2448).|' +
    '13: Das Argument Standard von [Name] ist kein konstanter Ausdruck; Attributargumente müssen Konstanten, ' +
    'TypeInfo-Ausdrücke oder Array-Konstruktoren sein (wie E2448).',
    Messages(AttributeFindings('unit G;'#10'interface'#10'const'#10'  Oben = 10;'#10'var'#10'  Grenze: Integer;'#10 +
    'function Standard: string;'#10'type'#10'  TKonfig = class'#10'  public'#10 +
    '    [Bereich(1, Grenze + 1)] FA: Integer;'#10'    [Bereich(Standard(), 2)] FB: Integer;'#10 +
    '    [Name(Standard)] FC: string;'#10 +
    '    [Bereich(Oben, SizeOf(Grenze))] [Typ(TypeInfo(TKonfig))] FD: Integer;'#10'  end;'#10 +
    'implementation'#10'function Standard: string;'#10'begin'#10'  Result := '''';'#10'end;'#10'end.')));
  // Konstanten, gleichnamige Konstanten in Klassen, später deklarierte Variablen, Felder und Variablen in einem
  // anderen Zweig bleiben still.
  Assert.AreEqual('', Messages(AttributeFindings('unit G;'#10'interface'#10'var'#10'  Wert: Integer;'#10 +
    '{$IFDEF X}'#10'  Bedingt: Integer;'#10'{$ENDIF}'#10'type'#10'  TKonfig = class'#10 +
    '  public const'#10'    Wert = 3;'#10'  public'#10'    [Bereich(Wert)] FA: Integer;'#10 +
    '    [Bereich(Spaeter)] FB: Integer;'#10'    [Bereich(FA)] FC: Integer;'#10'    [Bereich(Bedingt)] FD: Integer;'#10 +
    '  end;'#10'var'#10'  Spaeter: Integer;'#10'implementation'#10'end.')));
end;

procedure TAttributeUsageInvalidTests.OffAndExclude;
var
  Source: string;
begin
  Source := GenericUnit('  TZaehler = class'#10'    [Weak] FZaehler: Integer;'#10'  end;'#10, '');
  Assert.AreEqual(1, Integer(Length(AttributeFindings(Source, '', 'Source/G.pas'))));
  Assert.AreEqual(0, Integer(Length(AttributeFindings(Source, '{"rules": {"attribute-usage-invalid": "off"}}',
    'Source/G.pas'))));
  Assert.AreEqual(0, Integer(Length(AttributeFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/G.pas'))));
  Assert.AreEqual(0, Integer(Length(AttributeFindings(Source,
    '{"rules": {"attribute-usage-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/G.pas'))));
end;

function TypeInfoFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TTypeInfoInvalidRule.Create, ASource);
end;

function TypeInfoFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TTypeInfoInvalidRule.Create, ASource, AConfig, APath);
end;

/// <summary>Unit G mit TStatus und der Funktion StatusName, deren Rumpf AExpression liefert.</summary>
function StatusUnit(const AExpression: string): string;
begin
  Result := 'unit G;'#10'interface'#10'type'#10'  TStatus = (Aus, An);'#10'implementation'#10 +
    'uses System.TypInfo;'#10'function StatusName(Status: TStatus): string;'#10'begin'#10'  Result := ' +
    AExpression + ';'#10'end;'#10'end.';
end;

procedure TTypeInfoInvalidTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := StatusUnit('GetEnumName(TypeInfo(Status), Ord(Status))');
  Found := TypeInfoFindings(Source);
  Assert.AreEqual('9: TypeInfo erwartet einen Typ, Status ist eine Variable; gemeint ist TypeInfo(TStatus) ' +
    '(wie E2133).', Messages(Found));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('TypeInfo(TStatus) einsetzen', Found[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(StatusUnit('GetEnumName(TypeInfo(TStatus), Ord(Status))'), Fixed);
  Assert.AreEqual(0, Integer(Length(TypeInfoFindings(Fixed))), Fixed);
end;

procedure TTypeInfoInvalidTests.Variables;
begin
  Assert.AreEqual('14: Default erwartet einen Typ, Wert ist eine Variable; gemeint ist Default(Integer) (wie E2537).|' +
    '15: TypeInfo erwartet einen Typ, FListe ist eine Variable; gemeint ist TypeInfo(TList<Integer>) (wie E2133).|' +
    '17: TypeInfo erwartet einen Typ, Anzahl ist eine Variable; gemeint ist TypeInfo(Integer) (wie E2133).|' +
    '17: Default erwartet einen Typ, Result ist eine Variable; gemeint ist Default(string) (wie E2537).|' +
    '18: TypeInfo erwartet einen Typ, Zaehler ist eine Variable; gemeint ist TypeInfo(Cardinal) (wie E2133).|' +
    '19: TypeInfo erwartet einen Typ, Lokal ist eine Variable; gemeint ist TypeInfo(Double) (wie E2133).|' +
    '20: TypeInfo erwartet einen Typ, I ist eine Variable; gemeint ist TypeInfo(Integer) (wie E2133).|' +
    '21: TypeInfo erwartet einen Typ, E ist eine Variable; gemeint ist TypeInfo(Exception) (wie E2133).|' +
    '22: Default erwartet einen Typ, A ist eine Variable; gemeint ist Default(Byte) (wie E2537).|' +
    '23: TypeInfo erwartet einen Typ, Q ist eine Variable (wie E2133).',
    Messages(TypeInfoFindings('unit G;'#10'interface'#10'type'#10'  TKonto = class'#10'  private'#10 +
    '    FListe: TList<Integer>;'#10'    function Lies(Wert: Integer; var Q): string;'#10'  end;'#10 +
    'var'#10'  Zaehler: Cardinal;'#10'implementation'#10'function TKonto.Lies(Wert: Integer; var Q): string;'#10 +
    'begin'#10'  X := Default(Wert);'#10'  X := TypeInfo(FListe);'#10'  var Anzahl: Integer := 0;'#10 +
    '  X := TypeInfo(Anzahl); X := Default(Result);'#10'  X := TypeInfo(Zaehler);'#10 +
    '  var Lokal: Double := 0; X := TypeInfo(Lokal);'#10'  for var I: Integer := 0 to 1 do X := TypeInfo(I);'#10 +
    '  try except on E: Exception do X := TypeInfo(E); end;'#10 +
    '  F(procedure(A: Byte) begin X := Default(A); end);'#10'  X := TypeInfo(Q);'#10'end;'#10'end.')));
end;

procedure TTypeInfoInvalidTests.TypesWithoutTypeInfo;
begin
  Assert.AreEqual('11: TStatus hat keine Typinformation: Aufzählungen mit festen Werten erzeugen keine RTTI ' +
    '(wie E2134).|' +
    '12: TAlias hat keine Typinformation: Aufzählungen mit festen Werten erzeugen keine RTTI (wie E2134).|' +
    '13: TextFile hat keine Typinformation: Dateitypen erzeugen keine RTTI (wie E2134).|' +
    '14: TDatei hat keine Typinformation: Dateitypen erzeugen keine RTTI (wie E2134).|' +
    '15: Default ist für den Dateityp Text nicht erlaubt (wie E2538).|' +
    '16: Default ist für den Dateityp File nicht erlaubt (wie E2538).|' +
    '17: Default ist für den Dateityp TDatei nicht erlaubt, und Dateivariablen lassen sich nicht zuweisen ' +
    '(wie E2538 und E2015).',
    Messages(TypeInfoFindings('unit G;'#10'interface'#10'type'#10'  TStatus = (Aus = 1, An = 5);'#10 +
    '  TAlias = TStatus;'#10'  TDatei = file of Integer;'#10'  TFarbe = (Rot, Gruen);'#10'implementation'#10 +
    'procedure P;'#10'begin'#10'  X := TypeInfo(TStatus);'#10'  X := TypeInfo(TAlias);'#10 +
    '  X := TypeInfo(TextFile);'#10'  X := TypeInfo(TDatei);'#10'  Default(Text);'#10'  Default(File);'#10 +
    '  D := Default(TDatei);'#10'  X := TypeInfo(TFarbe); Y := Default(TFarbe); Z := TypeInfo(TList<Integer>);'#10 +
    'end;'#10'end.')));
end;

procedure TTypeInfoInvalidTests.SilentCases;
begin
  // with, Methoden fremder Typen, lokale Typen, Typparameter, Konstanten, Variablen in anderem Zweig und
  // unbekannte Namen bleiben still.
  Assert.AreEqual('', Messages(TypeInfoFindings('unit G;'#10'interface'#10'type'#10 +
    '  TBox<T> = class'#10'    procedure Zeige;'#10'  end;'#10'implementation'#10'{$IFDEF X}'#10'var'#10 +
    '  Bedingt: Integer;'#10'{$ENDIF}'#10'procedure TBox<T>.Zeige;'#10'begin'#10'  X := TypeInfo(T);'#10 +
    'end;'#10'procedure TFremd.Zeige;'#10'begin'#10'  X := TypeInfo(FWert);'#10'end;'#10 +
    'procedure P(Wert: Integer);'#10'type'#10'  TLokal = Integer;'#10'const'#10'  K = 1;'#10'begin'#10 +
    '  with Q do X := TypeInfo(Wert);'#10'  X := TypeInfo(TLokal); X := Default(K);'#10 +
    '  X := TypeInfo(Bedingt); X := TypeInfo(TUnbekannt);'#10'end;'#10'end.')));
  // Eigene Routine Default bzw. eigener Typ Text verdecken die des Compilers.
  Assert.AreEqual('', Messages(TypeInfoFindings('unit G;'#10'interface'#10'type'#10'  Text = Integer;'#10 +
    'function Default(A: Integer): Integer;'#10'implementation'#10'function Default(A: Integer): Integer;'#10 +
    'begin'#10'  Result := A;'#10'end;'#10'procedure P(Wert: Integer);'#10'begin'#10 +
    '  X := Default(Wert); Y := TypeInfo(Text);'#10'end;'#10'end.')));
end;

procedure TTypeInfoInvalidTests.OffAndExclude;
var
  Source: string;
begin
  Source := StatusUnit('GetEnumName(TypeInfo(Status), Ord(Status))');
  Assert.AreEqual(1, Integer(Length(TypeInfoFindings(Source, '', 'Source/G.pas'))));
  Assert.AreEqual(0, Integer(Length(TypeInfoFindings(Source, '{"rules": {"typeinfo-invalid": "off"}}',
    'Source/G.pas'))));
  Assert.AreEqual(0, Integer(Length(TypeInfoFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/G.pas'))));
  Assert.AreEqual(0, Integer(Length(TypeInfoFindings(Source,
    '{"rules": {"typeinfo-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/G.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TOperatorDeclarationInvalidTests);
  TDUnitX.RegisterTestFixture(TGenericDeclarationInvalidTests);
  TDUnitX.RegisterTestFixture(TTypeRestrictionViolatedTests);
  TDUnitX.RegisterTestFixture(TAttributeUsageInvalidTests);
  TDUnitX.RegisterTestFixture(TTypeInfoInvalidTests);

end.
