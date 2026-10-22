unit Atlas.Common.Rules.Builtin.TypeChecks.Tests;

// Tests der Regeln aus Builtin.TypeChecks. dynamic-array-misuse (#1038):
// Beispiel Dispose mit Korrektur, New und SetLength auf Arrays, New(Typ) mit
// und ohne Länge, Alias über die Datei und TBytes ohne Index, stille Fälle
// (Zeiger, offene Array-Parameter, eigene Routine New), Abschalten.
// local-routine-as-callback (#1039): Beispiel mit Korrektur (Auslagern),
// Zuweisung, Prozedur und parameterlose Funktion, ohne Korrektur bei Zugriff
// auf äußere Namen, Adresse in typisierter Konstante, stille Fälle (Aufrufe,
// of object, reference to, Unit-Routinen, @Routine), Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TDynamicArrayMisuseTests = class
  public
    [Test]
    procedure IssueExampleDisposeWithFix;
    [Test]
    procedure NewAndSetLengthOnArrays;
    [Test]
    procedure NewWithTypeIdentifier;
    [Test]
    procedure AliasesAndRtlArrays;
    [Test]
    procedure PointersAndOpenArraysAreSilent;
    [Test]
    procedure OffAndExclude;
    [Test]
    procedure RuleIsRegistered;
  end;

  [TestFixture]
  TLocalRoutineAsCallbackTests = class
  public
    [Test]
    procedure IssueExampleWithMoveFix;
    [Test]
    procedure AssignmentAndParameterlessRoutines;
    [Test]
    procedure NoMoveWhenOuterNamesAreUsed;
    [Test]
    procedure AddressInTypedConstant;
    [Test]
    procedure CallsAndOtherTypesAreSilent;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.TypeChecks,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

/// <summary>Index mit System (TObject, TArray&lt;T&gt;).</summary>
function SystemIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  end;'#10'  TArray<T> = array of T;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
end;

function Apply(const AText: string; const AFix: TRuleFix): string;
begin
  Result := TChangeSignature.ApplyEdits(AText, AFix.Edits);
end;

{ TDynamicArrayMisuseTests }

function ArrayFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TDynamicArrayMisuseRule.Create, ASource, SystemIndex, '', 'Werte.pas');
end;

function ArrayFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TDynamicArrayMisuseRule.Create, ASource, SystemIndex, AConfig, APath);
end;

/// <summary>Unit mit TWerte = array of Double, TPunkt (Record) und PPunkt; AStatements im Rumpf von Rechnen.
/// </summary>
function Werte(const AStatements: string): string;
begin
  Result := 'unit Werte;'#10'interface'#10'type'#10'  TWerte = array of Double;'#10'  TReihe = TWerte;'#10 +
    '  TPunkt = record'#10'    X: Integer;'#10'  end;'#10'  PPunkt = ^TPunkt;'#10'implementation'#10 +
    'procedure Rechnen(Offen: array of Integer);'#10'var'#10'  Werte: TArray<Double>;'#10'  Reihe: TReihe;'#10 +
    '  Liste: array of Integer;'#10'  Punkt: PPunkt;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

procedure TDynamicArrayMisuseTests.IssueExampleDisposeWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Werte('  Dispose(Werte);'#10);
  Found := ArrayFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(DynamicArrayMisuseRuleId, Found[0].RuleId);
  Assert.AreEqual('Dispose ist für dynamische Arrays nicht erlaubt und nicht nötig (wie E2256).', Found[0].Message);
  Assert.AreEqual(17, Found[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Werte := nil', Found[0].Fixes[0].Title);
  Fixed := Apply(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('  Werte := nil;'#10, Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(ArrayFindings(Fixed))), Fixed);
end;

procedure TDynamicArrayMisuseTests.NewAndSetLengthOnArrays;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Werte('  New(Liste);'#10);
  Found := ArrayFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('New ist für dynamische Arrays nicht erlaubt; die Länge setzt SetLength (wie E2255).',
    Found[0].Message);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Fixed := Apply(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('  SetLength(Liste, 1);'#10, Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(ArrayFindings(Fixed))), Fixed);
  Found := ArrayFindings(Werte('  SetLength(Werte);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('SetLength braucht für das dynamische Array Werte mindestens eine Länge (wie E2246).',
    Found[0].Message);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  // Richtige Formen.
  Assert.AreEqual(0, Integer(Length(ArrayFindings(Werte('  SetLength(Werte, 3);'#10'  Werte := nil;'#10 +
    '  SetLength(Liste, 2, 3);'#10)))));
end;

procedure TDynamicArrayMisuseTests.NewWithTypeIdentifier;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ArrayFindings(Werte('  Reihe := New(TWerte);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('New für das dynamische Array TWerte braucht mindestens eine Länge (wie E2308).', Found[0].Message);
  Found := ArrayFindings(Werte('  Reihe := New(TPunkt, 3);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('New mit Länge erwartet den Typ eines dynamischen Arrays; TPunkt ist keiner (wie E2307).',
    Found[0].Message);
  Assert.AreEqual(0, Integer(Length(ArrayFindings(Werte('  Reihe := New(TWerte, 3);'#10)))));
end;

procedure TDynamicArrayMisuseTests.AliasesAndRtlArrays;
var
  Found: TArray<TRuleFinding>;
begin
  // TReihe = TWerte = array of Double.
  Found := ArrayFindings(Werte('  Dispose(Reihe);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  // TBytes ohne System.SysUtils im Index.
  Found := ArrayFindings('unit Puffer;'#10'interface'#10'uses'#10'  System.SysUtils;'#10'implementation'#10 +
    'procedure Lesen;'#10'var'#10'  Daten: TBytes;'#10'begin'#10'  Dispose(Daten);'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
end;

procedure TDynamicArrayMisuseTests.PointersAndOpenArraysAreSilent;
begin
  Assert.AreEqual(0, Integer(Length(ArrayFindings(Werte('  New(Punkt);'#10'  Dispose(Punkt);'#10 +
    '  Punkt := New(PPunkt);'#10)))));
  // Offener Array-Parameter: kein dynamisches Array (eigener Fehler des Compilers).
  Assert.AreEqual(0, Integer(Length(ArrayFindings(Werte('  Dispose(Offen);'#10)))));
  // Unbekannte Namen und eine eigene Routine New.
  Assert.AreEqual(0, Integer(Length(ArrayFindings(Werte('  Dispose(Unbekannt);'#10)))));
  Assert.AreEqual(0, Integer(Length(ArrayFindings(Werte('  New(Liste);'#10).Replace('procedure Rechnen',
    'procedure New(var A: array of Integer);'#10'begin'#10'end;'#10'procedure Rechnen')))));
end;

procedure TDynamicArrayMisuseTests.OffAndExclude;
var
  Source: string;
begin
  Source := Werte('  Dispose(Werte);'#10);
  Assert.AreEqual(1, Integer(Length(ArrayFindings(Source, '', 'Source/Werte.pas'))));
  Assert.AreEqual(0, Integer(Length(ArrayFindings(Source, '{"rules": {"dynamic-array-misuse": "off"}}',
    'Source/Werte.pas'))));
  Assert.AreEqual(0, Integer(Length(ArrayFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Werte.pas'))));
  Assert.AreEqual(0, Integer(Length(ArrayFindings(Source,
    '{"rules": {"dynamic-array-misuse": {"exclude": ["Source/*.pas"]}}}', 'Source/Werte.pas'))));
end;

procedure TDynamicArrayMisuseTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = DynamicArrayMisuseRuleId then
      Found := True;
  Assert.IsTrue(Found);
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = LocalRoutineAsCallbackRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

{ TLocalRoutineAsCallbackTests }

function CallbackFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TLocalRoutineAsCallbackRule.Create, ASource, SystemIndex, '', 'Listen.pas');
end;

function CallbackFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TLocalRoutineAsCallbackRule.Create, ASource, SystemIndex, AConfig, APath);
end;

/// <summary>Unit mit TListe.Sort(Compare: TVergleich), Ereignis und Methodenreferenz; ANested sind die
/// verschachtelten Routinen von TListe.Sortieren, AStatements ihr Rumpf.</summary>
function Liste(const ANested, AStatements: string): string;
begin
  Result := 'unit Listen;'#10'interface'#10'type'#10'  TVergleich = function(A, B: Pointer): Integer;'#10 +
    '  TAktion = procedure;'#10'  TEreignis = procedure of object;'#10'  TAufgabe = reference to procedure;'#10 +
    '  TListe = class'#10'  private'#10'    FAnzahl: Integer;'#10'  public'#10 +
    '    procedure Sort(Compare: TVergleich);'#10'    procedure Ausfuehren(Aufgabe: TAufgabe; Ereignis: TEreignis);'#10 +
    '    procedure Sortieren;'#10'  end;'#10'implementation'#10'procedure TListe.Sort(Compare: TVergleich);'#10 +
    'begin'#10'end;'#10'procedure TListe.Ausfuehren(Aufgabe: TAufgabe; Ereignis: TEreignis);'#10'begin'#10'end;'#10 +
    'procedure TListe.Sortieren;'#10'var'#10'  Aktion: TAktion;'#10 + ANested + 'begin'#10 + AStatements + 'end;'#10 +
    'end.';
end;

const
  Vergleich = '  function Vergleich(A, B: Pointer): Integer;'#10'  begin'#10'    Result := 0;'#10'  end;'#10;

procedure TLocalRoutineAsCallbackTests.IssueExampleWithMoveFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Liste(Vergleich, '  Sort(Vergleich);'#10);
  Found := CallbackFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(LocalRoutineAsCallbackRuleId, Found[0].RuleId);
  Assert.AreEqual('Die lokale Funktion Vergleich kann nicht als Prozedurvariable übergeben werden (wie E2094).',
    Found[0].Message);
  Assert.AreEqual(30, Found[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Vergleich als Routine der Unit auslagern', Found[0].Fixes[0].Title);
  Fixed := Apply(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('end;'#10'function Vergleich(A, B: Pointer): Integer;'#10'begin'#10'  Result := 0;'#10'end;'#10#10 +
    'procedure TListe.Sortieren;'#10'var'#10'  Aktion: TAktion;'#10'begin'#10'  Sort(Vergleich);', Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(CallbackFindings(Fixed))), Fixed);
end;

procedure TLocalRoutineAsCallbackTests.AssignmentAndParameterlessRoutines;
var
  Found: TArray<TRuleFinding>;
begin
  Found := CallbackFindings(Liste('  procedure Melden;'#10'  begin'#10'  end;'#10, '  Aktion := Melden;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Die lokale Prozedur Melden kann keiner Prozedurvariablen zugewiesen werden (wie E2094).',
    Found[0].Message);
  // Parameterlose Funktion an einen Integer: ein Aufruf.
  Assert.AreEqual(0, Integer(Length(CallbackFindings(Liste('  function Null: Integer;'#10'  begin'#10 +
    '    Result := 0;'#10'  end;'#10, '  FAnzahl := Null;'#10)))));
end;

procedure TLocalRoutineAsCallbackTests.NoMoveWhenOuterNamesAreUsed;
var
  Found: TArray<TRuleFinding>;
begin
  // FAnzahl gehört zur Klasse: Auf Unit-Ebene wäre es unbekannt.
  Found := CallbackFindings(Liste('  function Vergleich(A, B: Pointer): Integer;'#10'  begin'#10 +
    '    Result := FAnzahl;'#10'  end;'#10, '  Sort(Vergleich);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  // Lokale Variable der äußeren Routine.
  Found := CallbackFindings(Liste('  function Vergleich(A, B: Pointer): Integer;'#10'  begin'#10 +
    '    Aktion := nil;'#10'    Result := 0;'#10'  end;'#10, '  Sort(Vergleich);'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TLocalRoutineAsCallbackTests.AddressInTypedConstant;
var
  Found: TArray<TRuleFinding>;
begin
  Found := CallbackFindings('unit Zeiger;'#10'interface'#10'implementation'#10'procedure Lesen;'#10'var'#10 +
    '  Wert: Integer;'#10'const'#10'  Adresse: Pointer = @Wert;'#10'begin'#10'end;'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Die Adresse des lokalen Symbols Wert ist keine Konstante (wie E2278).', Found[0].Message);
  // Globale Variable: erlaubt.
  Assert.AreEqual(0, Integer(Length(CallbackFindings('unit Zeiger;'#10'interface'#10'implementation'#10'var'#10 +
    '  Wert: Integer;'#10'procedure Lesen;'#10'const'#10'  Adresse: Pointer = @Wert;'#10'begin'#10'end;'#10 +
    'end.'))));
end;

procedure TLocalRoutineAsCallbackTests.CallsAndOtherTypesAreSilent;
begin
  // Aufrufe, Adresse mit @ (untypisierter Zeiger), anonyme Methode.
  Assert.AreEqual(0, Integer(Length(CallbackFindings(Liste(Vergleich, '  Vergleich(nil, nil);'#10 +
    '  FAnzahl := Vergleich(nil, nil);'#10'  Sort(function(A, B: Pointer): Integer begin Result := 0; end);'#10)))));
  // Methodenzeiger und Methodenreferenz meldet der Compiler mit anderen Codes.
  Assert.AreEqual(0, Integer(Length(CallbackFindings(Liste('  procedure Melden;'#10'  begin'#10'  end;'#10,
    '  Ausfuehren(Melden, Melden);'#10)))));
  // Routine der Unit statt lokaler Routine.
  Assert.AreEqual(0, Integer(Length(CallbackFindings(Liste('', '  Sort(Vergleich);'#10).Replace(
    'procedure TListe.Sortieren;'#10, Vergleich.Replace('  ', '') + 'procedure TListe.Sortieren;'#10)))));
end;

procedure TLocalRoutineAsCallbackTests.OffAndExclude;
var
  Source: string;
begin
  Source := Liste(Vergleich, '  Sort(Vergleich);'#10);
  Assert.AreEqual(1, Integer(Length(CallbackFindings(Source, '', 'Source/Listen.pas'))));
  Assert.AreEqual(0, Integer(Length(CallbackFindings(Source, '{"rules": {"local-routine-as-callback": "off"}}',
    'Source/Listen.pas'))));
  Assert.AreEqual(0, Integer(Length(CallbackFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Listen.pas'))));
  Assert.AreEqual(0, Integer(Length(CallbackFindings(Source,
    '{"rules": {"local-routine-as-callback": {"exclude": ["Source/*.pas"]}}}', 'Source/Listen.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TDynamicArrayMisuseTests);
  TDUnitX.RegisterTestFixture(TLocalRoutineAsCallbackTests);

end.
