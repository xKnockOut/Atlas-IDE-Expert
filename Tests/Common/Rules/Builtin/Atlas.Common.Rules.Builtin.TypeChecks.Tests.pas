unit Atlas.Common.Rules.Builtin.TypeChecks.Tests;

// Tests der Regeln aus Builtin.TypeChecks. dynamic-array-misuse (#1038):
// Beispiel Dispose mit Korrektur, New und SetLength auf Arrays, New(Typ) mit
// und ohne Länge, Alias über die Datei und TBytes ohne Index, stille Fälle
// (Zeiger, offene Array-Parameter, eigene Routine New), Abschalten.
// local-routine-as-callback (#1039): Beispiel mit Korrektur (Auslagern),
// Zuweisung, Prozedur und parameterlose Funktion, ohne Korrektur bei Zugriff
// auf äußere Namen, Adresse in typisierter Konstante, stille Fälle (Aufrufe,
// of object, reference to, Unit-Routinen, @Routine), Abschalten.
// hresult-integer-mix (#1040): Beispiel mit Korrektur in Deklaration und
// Rumpf, umgekehrt und über eine Zuordnung IFoo.Bar = Baz, Interface samt
// Vorfahr aus dem Index, stille Fälle (gleiche Typen, Cardinal, Varianten in
// bedingten Zweigen, andere Parameter), Abschalten.

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
  THresultIntegerMixTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure ReverseAndResolutionClause;
    [Test]
    procedure InterfaceFromIndex;
    [Test]
    procedure MatchingAndConditionalVariantsAreSilent;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TInvalidVarArgumentTests = class
  public
    [Test]
    procedure IssueExampleWithFix;
    [Test]
    procedure ConstantsPropertiesAndResults;
    [Test]
    procedure OpenArraysSliceAndExpressions;
    [Test]
    procedure PropertyFixWritesBack;
    [Test]
    procedure VariablesAndUntypedParametersAreSilent;
    [Test]
    procedure RoutinesFromIndex;
    [Test]
    procedure OffAndExclude;
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
  Atlas.Common.Configuration.Contract,
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
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = HresultIntegerMixRuleId then
      Found := True;
  Assert.IsTrue(Found);
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = InvalidVarArgumentRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

{ THresultIntegerMixTests }

function MixFindings(const ASource: string; const AIndex: ISymbolIndex = nil): TArray<TRuleFinding>; overload;
var
  Index: ISymbolIndex;
begin
  Index := AIndex;
  if Index = nil then
    Index := SystemIndex;
  Result := TRuleAssert.IndexFindings(THresultIntegerMixRule.Create, ASource, Index, '', 'Export.pas');
end;

function MixFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(THresultIntegerMixRule.Create, ASource, SystemIndex, AConfig, APath);
end;

/// <summary>IExport mit Schreiben: HRESULT; TExport implementiert es mit AResult.</summary>
function Export(const AResult: string): string;
begin
  Result := 'unit Export;'#10'interface'#10'type'#10'  IExport = interface'#10'    function Schreiben: HRESULT; stdcall;'#10 +
    '  end;'#10'  TExport = class(TInterfacedObject, IExport)'#10'    function Schreiben: ' + AResult + '; stdcall;'#10 +
    '  end;'#10'implementation'#10'function TExport.Schreiben: ' + AResult + ';'#10'begin'#10'  Result := 0;'#10 +
    'end;'#10'end.';
end;

procedure THresultIntegerMixTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Export('Integer');
  Found := MixFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(HresultIntegerMixRuleId, Found[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Warning), Ord(Found[0].Severity));
  Assert.AreEqual('IExport.Schreiben liefert HRESULT, die Implementierung Integer (wie X1008).', Found[0].Message);
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Ergebnistyp HRESULT wie im Interface', Found[0].Fixes[0].Title);
  Fixed := Apply(Source, Found[0].Fixes[0]);
  Assert.AreEqual(Export('HRESULT'), Fixed);
  Assert.AreEqual(0, Integer(Length(MixFindings(Fixed))), Fixed);
end;

procedure THresultIntegerMixTests.ReverseAndResolutionClause;
var
  Found: TArray<TRuleFinding>;
begin
  Found := MixFindings(Export('Integer').Replace('function Schreiben: HRESULT;', 'function Schreiben: Integer;')
    .Replace(': Integer; stdcall;'#10'  end;'#10'implementation', ': HResult; stdcall;'#10'  end;'#10'implementation'));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('IExport.Schreiben liefert Integer, die Implementierung HResult (wie X1008).', Found[0].Message);
  // Zuordnung: Schreiben implementiert SchreibenIntern.
  Found := MixFindings('unit Export;'#10'interface'#10'type'#10'  IExport = interface'#10 +
    '    function Schreiben: HRESULT; stdcall;'#10'  end;'#10'  TExport = class(TInterfacedObject, IExport)'#10 +
    '    function IExport.Schreiben = SchreibenIntern;'#10'    function Schreiben: HRESULT; stdcall;'#10 +
    '    function SchreibenIntern: LongInt; stdcall;'#10'  end;'#10'implementation'#10'end.');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('IExport.Schreiben liefert HRESULT, die Implementierung LongInt (wie X1008).', Found[0].Message);
  Assert.AreEqual(9, Found[0].Range.StartPos.Line);
end;

procedure THresultIntegerMixTests.InterfaceFromIndex;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
begin
  Index := SystemIndex;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Schnittstellen;'#10'interface'#10'type'#10 +
    '  IBasis = interface'#10'    function Pruefen(const A: string): HRESULT; stdcall;'#10'  end;'#10 +
    '  IExport = interface(IBasis)'#10'    procedure Leeren;'#10'  end;'#10'implementation'#10'end.',
    'C:\Projekt\Schnittstellen.pas', nil));
  Found := MixFindings('unit Export;'#10'interface'#10'uses'#10'  Schnittstellen;'#10'type'#10 +
    '  TExport = class(TInterfacedObject, IExport)'#10'    function Pruefen(const A: string): Integer; stdcall;'#10 +
    '    procedure Leeren;'#10'  end;'#10'implementation'#10'end.', Index);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('IBasis.Pruefen liefert HRESULT, die Implementierung Integer (wie X1008).', Found[0].Message);
end;

procedure THresultIntegerMixTests.MatchingAndConditionalVariantsAreSilent;
begin
  Assert.AreEqual(0, Integer(Length(MixFindings(Export('HRESULT')))));
  Assert.AreEqual(0, Integer(Length(MixFindings(Export('HResult')))));
  Assert.AreEqual(0, Integer(Length(MixFindings(Export('Cardinal')))));
  // Andere Parameter: implementiert etwas anderes.
  Assert.AreEqual(0, Integer(Length(MixFindings(Export('Integer').Replace('    function Schreiben: Integer; stdcall;',
    '    function Schreiben(A: Integer): Integer; stdcall;'#10'    function Schreiben: HRESULT; stdcall;')
    .Replace('function TExport.Schreiben: Integer;', 'function TExport.Schreiben(A: Integer): Integer;')))));
  // Varianten in bedingten Zweigen: eine passt.
  Assert.AreEqual(0, Integer(Length(MixFindings(Export('Integer').Replace('    function Schreiben: Integer; stdcall;',
    '{$IFDEF ALT}'#10'    function Schreiben: Integer; stdcall;'#10'{$ELSE}'#10'    function Schreiben: HRESULT; stdcall;' +
    #10'{$ENDIF}')))));
end;

procedure THresultIntegerMixTests.OffAndExclude;
var
  Source: string;
begin
  Source := Export('Integer');
  Assert.AreEqual(1, Integer(Length(MixFindings(Source, '', 'Source/Export.pas'))));
  Assert.AreEqual(0, Integer(Length(MixFindings(Source, '{"rules": {"hresult-integer-mix": "off"}}',
    'Source/Export.pas'))));
  Assert.AreEqual(0, Integer(Length(MixFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Export.pas'))));
  Assert.AreEqual(0, Integer(Length(MixFindings(Source,
    '{"rules": {"hresult-integer-mix": {"exclude": ["Source/*.pas"]}}}', 'Source/Export.pas'))));
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

{ TInvalidVarArgumentTests }

function VarFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TInvalidVarArgumentRule.Create, ASource, SystemIndex, '', 'Zeilen.pas');
end;

function VarFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TInvalidVarArgumentRule.Create, ASource, SystemIndex, AConfig, APath);
end;

/// <summary>Routinen mit var-, out- und untypisierten Parametern; AStatements stehen in Bearbeiten.</summary>
function Zeilen(const AStatements: string): string;
begin
  Result := 'unit Zeilen;'#10'interface'#10'type'#10'  TZeile = class'#10'  private'#10'    FText: string;'#10 +
    '    FAnzahl: Integer;'#10'  public'#10'    property Text: string read FText write FText;'#10 +
    '    property Anzahl: Integer read FAnzahl;'#10'  end;'#10'const'#10'  Grenze = 10;'#10 +
    '  Start: Integer = 1;'#10'implementation'#10'procedure Erhoehen(var Zeichen: Char);'#10'begin'#10'end;'#10 +
    'procedure Zaehlen(var Ziel: Integer);'#10'begin'#10'end;'#10'procedure Lesen(out Ziel: Integer);'#10 +
    'begin'#10'end;'#10'procedure Fuellen(var Werte: array of Integer);'#10'begin'#10'end;'#10 +
    'procedure Puffer(var Daten);'#10'begin'#10'end;'#10'procedure Anhaengen(var Text: string);'#10'begin'#10 +
    'end;'#10'function Doppelt(Zahl: Integer): Integer;'#10'begin'#10'  Result := Zahl * 2;'#10'end;'#10 +
    'procedure Bearbeiten(const Fest: Integer; Zeile: TZeile);'#10'var'#10'  S: string;'#10'  Zahl: Integer;'#10 +
    '  Feld: array[0..3] of Integer;'#10'begin'#10 + AStatements + 'end;'#10'end.';
end;

procedure TInvalidVarArgumentTests.IssueExampleWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Zeilen('  Erhoehen(S[1]);'#10);
  Found := VarFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(InvalidVarArgumentRuleId, Found[0].RuleId);
  Assert.AreEqual('Ein String-Element kann nicht an einen var-Parameter übergeben werden (wie E2354).',
    Found[0].Message);
  Assert.AreEqual(43, Found[0].Range.StartPos.Line);
  Assert.AreEqual(11, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('Über eine lokale Variable Wert übergeben', Found[0].Fixes[0].Title);
  Fixed := Apply(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('  Feld: array[0..3] of Integer;'#10'  Wert: Char;'#10'begin'#10'  Wert := S[1];'#10 +
    '  Erhoehen(Wert);'#10'  S[1] := Wert;'#10'end;', Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(VarFindings(Fixed))), Fixed);
end;

procedure TInvalidVarArgumentTests.ConstantsPropertiesAndResults;
var
  Found: TArray<TRuleFinding>;
begin
  Found := VarFindings(Zeilen('  Zaehlen(Grenze);'#10'  Zaehlen(Start);'#10'  Zaehlen(Fest);'#10 +
    '  Zaehlen(Zeile.Anzahl);'#10'  Zaehlen(Doppelt(2));'#10'  Zaehlen(5);'#10));
  Assert.AreEqual(6, Integer(Length(Found)));
  Assert.AreEqual('Die Konstante Grenze ist keine Variable und kann nicht an einen var-Parameter übergeben ' +
    'werden (wie E2197).', Found[0].Message);
  Assert.AreEqual('Die typisierte Konstante Start ist keine Variable und kann nicht an einen var-Parameter ' +
    'übergeben werden (wie E2197).', Found[1].Message);
  Assert.AreEqual('Der const-Parameter Fest ist keine Variable und kann nicht an einen var-Parameter übergeben ' +
    'werden (wie E2197).', Found[2].Message);
  Assert.AreEqual('Die Eigenschaft Zeile.Anzahl ist keine Variable und kann nicht an einen var-Parameter ' +
    'übergeben werden (wie E2197).', Found[3].Message);
  Assert.AreEqual('Das Ergebnis von Doppelt ist keine Variable und kann nicht an einen var-Parameter übergeben ' +
    'werden (wie E2197).', Found[4].Message);
  Assert.AreEqual('Der Wert 5 ist keine Variable und kann nicht an einen var-Parameter übergeben werden ' +
    '(wie E2197).', Found[5].Message);
  // Ohne Rückschreiben: Die Korrektur übergibt eine Kopie.
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  // Mit {$J+} sind typisierte Konstanten beschreibbar.
  Assert.AreEqual(0, Integer(Length(VarFindings('{$J+}'#10 + Zeilen('  Zaehlen(Start);'#10)))));
end;

procedure TInvalidVarArgumentTests.OpenArraysSliceAndExpressions;
var
  Found: TArray<TRuleFinding>;
begin
  Found := VarFindings(Zeilen('  Fuellen(Grenze);'#10'  Fuellen([1, 2]);'#10'  Fuellen(Slice(Feld, 2));'#10 +
    '  Zaehlen(Zahl + 1);'#10'  Lesen(-Zahl);'#10));
  Assert.AreEqual(5, Integer(Length(Found)));
  Assert.AreEqual('Eine Konstante kann nicht als offenes Array an einen var-Parameter übergeben werden (wie E2192).',
    Found[0].Message);
  Assert.AreEqual(Found[0].Message, Found[1].Message);
  Assert.AreEqual('Slice ist für einen var-Parameter nicht erlaubt; Änderungen kämen nicht im Array an (wie E2454).',
    Found[2].Message);
  Assert.AreEqual('An einen var-Parameter muss eine Variable übergeben werden, kein Ausdruck (wie E2036).',
    Found[3].Message);
  Assert.AreEqual('An einen out-Parameter muss eine Variable übergeben werden, kein Ausdruck (wie E2036).',
    Found[4].Message);
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(Found[2].Fixes)));
  Assert.AreEqual(1, Integer(Length(Found[3].Fixes)));
end;

procedure TInvalidVarArgumentTests.PropertyFixWritesBack;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Zeilen('  Anhaengen(Zeile.Text);'#10);
  Found := VarFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Fixed := Apply(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('  Wert: string;'#10'begin'#10'  Wert := Zeile.Text;'#10'  Anhaengen(Wert);'#10 +
    '  Zeile.Text := Wert;'#10, Fixed) > 0, Fixed);
  // out: ohne Zuweisung vorab; Anzahl hat kein write, also kein Rückschreiben.
  Source := Zeilen('  Lesen(Zeile.Anzahl);'#10);
  Found := VarFindings(Source);
  Assert.AreEqual(1, Integer(Length(Found)));
  Fixed := Apply(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('  Wert: Integer;'#10'begin'#10'  Lesen(Wert);'#10'end;', Fixed) > 0, Fixed);
end;

procedure TInvalidVarArgumentTests.VariablesAndUntypedParametersAreSilent;
begin
  Assert.AreEqual(0, Integer(Length(VarFindings(Zeilen('  Zaehlen(Zahl);'#10'  Lesen(Feld[0]);'#10 +
    '  Puffer(S[1]);'#10'  Inc(Zahl);'#10'  Zaehlen(Integer(Zahl));'#10'  Fuellen(Feld);'#10 +
    '  Zahl := Doppelt(Grenze);'#10'  Zaehlen(Zeile.FAnzahl);'#10'  Anhaengen(S);'#10)))));
end;

procedure TInvalidVarArgumentTests.RoutinesFromIndex;
var
  Index: ISymbolIndex;
  Found: TArray<TRuleFinding>;
begin
  Index := SystemIndex;
  Index.AddUnit(TIndexExtractor.ExtractText('unit Fremd;'#10'interface'#10'type'#10'  TLeser = class'#10 +
    '    class procedure Holen(out A: Integer); overload;'#10 +
    '    class procedure Holen(A: Integer; out B: Integer); overload;'#10'  end;'#10 +
    'procedure Setzen(var A: Integer; B: Integer = 0);'#10'implementation'#10'end.', 'C:\Projekt\Fremd.pas', nil));
  // Überladungen aus einer anderen Unit: Die Auswahl kennt Atlas nicht sicher, also still.
  Found := TRuleAssert.IndexFindings(TInvalidVarArgumentRule.Create, 'unit Nutzer;'#10'interface'#10 +
    'implementation'#10'uses'#10'  Fremd;'#10'procedure Tun;'#10'var'#10'  Zahl: Integer;'#10'begin'#10 +
    '  TLeser.Holen(5, Zahl);'#10'  Setzen(Zahl, 2);'#10'  Setzen(3);'#10'end;'#10'end.', Index, '', 'Nutzer.pas');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(11, Found[0].Range.StartPos.Line);
end;

procedure TInvalidVarArgumentTests.OffAndExclude;
var
  Source: string;
begin
  Source := Zeilen('  Erhoehen(S[1]);'#10);
  Assert.AreEqual(1, Integer(Length(VarFindings(Source, '', 'Source/Zeilen.pas'))));
  Assert.AreEqual(0, Integer(Length(VarFindings(Source, '{"rules": {"invalid-var-argument": "off"}}',
    'Source/Zeilen.pas'))));
  Assert.AreEqual(0, Integer(Length(VarFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Zeilen.pas'))));
  Assert.AreEqual(0, Integer(Length(VarFindings(Source,
    '{"rules": {"invalid-var-argument": {"exclude": ["Source/*.pas"]}}}', 'Source/Zeilen.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TDynamicArrayMisuseTests);
  TDUnitX.RegisterTestFixture(TLocalRoutineAsCallbackTests);
  TDUnitX.RegisterTestFixture(THresultIntegerMixTests);
  TDUnitX.RegisterTestFixture(TInvalidVarArgumentTests);

end.
