unit Atlas.Common.Rules.Builtin.TypeRestrictions.Tests;

// Tests der Sprachregeln für Typdeklarationen: operator-declaration-invalid
// (#1030) mit dem Beispiel samt Korrektur in Deklaration und Rumpf, allen
// Codes (E2393, E2517, E2518, E2519, E2520, E2521, E2522, E2464), stillen
// Fällen (richtige Operatoren, Aliase, unbekannte Typen) und Abschalten;
// generic-declaration-invalid (#1029) mit dem Beispiel und je Gruppe von
// Codes ein gemeldeter und ein stiller Fall.

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
    procedure TypeArgumentCount;
    [Test]
    procedure LocalSymbolsInGenericMethods;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
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
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Geld('    class operator Equal(const A, B: TGeld): Integer;'#10,
    'class operator TGeld.Equal(const A, B: TGeld): Integer;'#10'begin'#10'  Result := 0;'#10'end;'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Equal muss Boolean liefern (wie E2520).', Found[0].Message);
  Assert.AreEqual(5, Found[0].Range.StartPos.Line);
  Assert.AreEqual(19, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Boolean als Ergebnis', Found[0].Fixes[0].Title);
  Fixed := TChangeSignature.ApplyEdits(Source, Found[0].Fixes[0].Edits);
  Assert.AreEqual(Geld('    class operator Equal(const A, B: TGeld): Boolean;'#10,
    'class operator TGeld.Equal(const A, B: TGeld): Boolean;'#10'begin'#10'  Result := 0;'#10'end;'#10), Fixed);
  Assert.AreEqual(0, Integer(Length(OperatorFindings(Fixed))), Fixed);
end;

procedure TOperatorDeclarationInvalidTests.UnknownOperatorName;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Geld('    class operator Addition(const A, B: TGeld): TGeld;'#10,
    'class operator TGeld.Addition(const A, B: TGeld): TGeld;'#10'begin'#10'end;'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Unbekannter Operator Addition (wie E2393).', Found[0].Message);
  Source := Geld('    class operator Substract(const A, B: TGeld): TGeld;'#10,
    'class operator TGeld.Substract(const A, B: TGeld): TGeld;'#10'begin'#10'end;'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
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
  // Klasse mit Umwandlung in den Vorfahren.
  Found := OperatorFindings('unit Tiere;'#10'interface'#10'type'#10'  TTier = class'#10'  end;'#10 +
    '  THund = class(TTier)'#10'    class operator Implicit(A: THund): TTier;'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Implicit darf nicht in den Vorfahren TTier oder aus ihm umwandeln (wie E2522).', Found[0].Message);
end;

procedure TOperatorDeclarationInvalidTests.AssignNeedsVar;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Geld('    class operator Assign(const Dest: TGeld; const [ref] Src: TGeld);'#10);
  Found := OperatorFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Der erste Parameter von Assign muss ein var-Parameter sein (wie E2464).', Found[0].Message);
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
  Source := Geld('    class operator Equal(const A, B: TGeld): Integer;'#10);
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

initialization
  TDUnitX.RegisterTestFixture(TOperatorDeclarationInvalidTests);
  TDUnitX.RegisterTestFixture(TGenericDeclarationInvalidTests);

end.
