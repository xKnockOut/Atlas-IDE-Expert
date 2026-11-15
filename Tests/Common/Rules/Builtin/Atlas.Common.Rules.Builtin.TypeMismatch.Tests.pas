unit Atlas.Common.Rules.Builtin.TypeMismatch.Tests;

// Tests der Regel type-mismatch (#1369). Je Code die Form aus
// Tests/Compilermeldungen (Cm.<Code>.pas) und Gegenfälle, die dcc ohne Meldung
// übersetzt: Zuweisung und Standardwert (E2010), Prozedur als Wert (E2010),
// doppelte lokale Deklaration und Result aus dem interface-Teil (E2010),
// Argumente und Array-Property (E2010), var-Argument (E2033), Operatoren
// (E2015, E2010), Typumwandlungen (E2089), Inc und Ptr (E2008), prozedurale
// Typen (E2009, E2010), Methodenreferenzen mit anderer Parameterliste
// (#1897) und Funktionen ohne () (#1899), bedingte Deklarationen, with,
// Abschalten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeMismatchTests = class
  public
    [Test]
    procedure AssignmentsWithIncompatibleTypes;
    [Test]
    procedure CompatibleAssignmentsAreSilent;
    [Test]
    procedure ProcedureAsValue;
    [Test]
    procedure StaticArraysClassesAndDefaults;
    [Test]
    procedure DuplicateLocalAndInterfaceResult;
    [Test]
    procedure ValueAndVarArguments;
    [Test]
    procedure ArgumentsThatFitAreSilent;
    [Test]
    procedure ArrayPropertyIndex;
    [Test]
    procedure OperatorsNotApplicable;
    [Test]
    procedure OperatorsThatFitAreSilent;
    [Test]
    procedure InvalidTypecasts;
    [Test]
    procedure IncAndPtr;
    [Test]
    procedure ProceduralTypes;
    [Test]
    procedure ConditionalParameterModifierIsSilent;
    /// <summary>#1897: Routine an TFunc/TProc mit const-Parameter statt Wertparameter, als Zuweisung und
    /// Argument.</summary>
    [Test]
    procedure MethodReferenceParameters;
    /// <summary>#1899: parameterlose Funktion, die eine Methodenreferenz liefert, ohne () zugewiesen und
    /// übergeben; Korrektur ().</summary>
    [Test]
    procedure FunctionReturningReferenceWithoutParens;
    [Test]
    procedure MethodReferencesThatFitAreSilent;
    /// <summary>#2309: TProc und TFunc aus System.SysUtils ohne RTL im Index (Cloud, CI); still ohne
    /// System.SysUtils in uses und wenn eine fremde Unit dahinter den Typ verdecken kann.</summary>
    [Test]
    procedure RtlReferencesWithoutIndex;
    /// <summary>#2309: Argumente beim Aufruf einer Variablen, eines Felds bzw. einer Property von prozeduralem Typ
    /// (Hover: FOnDebugTree(…, DebugTreeRefresh)).</summary>
    [Test]
    procedure ProceduralCalleeArguments;
    [Test]
    procedure ConditionalDeclarationsAndWithAreSilent;
    [Test]
    procedure OffAndGroupSwitches;
    [Test]
    procedure RuleIsRegistered;
    /// <summary>IfThen aus System.Math (Integer) und System.StrUtils (string): dcc führt die Überladungen beider Units
    /// zusammen; der Ergebnistyp entscheidet sich an den Argumenten (Fehlalarm in
    /// Atlas.Common.Lsp.CompletionCollector).
    /// </summary>
    [Test]
    procedure OverloadsFromSeveralUnitsAreSilent;
    /// <summary>Ein im Typ des Felds (oder einem umgebenden Typ) verschachtelter Typ verdeckt einen gleichnamigen
    /// aus dem uses: TKarte.TBytes8 ist ein dynamisches Array, Typen.TBytes8 ein statisches (Fehlalarm in
    /// PasVulkan.Collections).</summary>
    [Test]
    procedure NestedTypeHidesUsedType;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.TypeMismatch,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Tests.RuleAssert;

/// <summary>Index mit System (TObject).</summary>
function SystemIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  end;'#10'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
end;

/// <summary>Index mit System und den Methodenreferenzen aus System.SysUtils.</summary>
function SysUtilsIndex: ISymbolIndex;
begin
  Result := SystemIndex;
  Result.AddUnit(TIndexExtractor.ExtractText('unit System.SysUtils;'#10'interface'#10'type'#10 +
    '  TProc = reference to procedure;'#10'  TProc<T> = reference to procedure (Arg1: T);'#10 +
    '  TFunc<TResult> = reference to function: TResult;'#10 +
    '  TFunc<T,TResult> = reference to function (Arg1: T): TResult;'#10'implementation'#10'end.',
    'C:\BDS\source\System.SysUtils.pas', nil));
end;

/// <summary>Befunde in einer Unit, die System.SysUtils einbindet und ADeclarations vor der Routine Fall mit den
/// Anweisungen AStatements deklariert.</summary>
function ReferenceFindings(const ADeclarations, AStatements: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.IndexFindings(TTypeMismatchRule.Create, 'unit Fall;'#10'interface'#10'uses'#10 +
    '  System.SysUtils;'#10'implementation'#10'var'#10'  GTest: TFunc<string, TArray<string>>;'#10 +
    '  GProc: TProc<string>;'#10 + ADeclarations + 'procedure Fall;'#10'begin'#10 + AStatements + 'end;'#10'end.',
    SysUtilsIndex, '', 'Fall.pas');
end;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    if Result <> '' then
    begin
      Result := Result + ' | ';
    end;
    Result := Result + IntToStr(mFinding.Range.StartPos.Line) + ': ' + mFinding.Message;
  end;
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TTypeMismatchRule.Create, ASource, SystemIndex, '', 'Fall.pas');
end;

function Findings(const ASource, AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TTypeMismatchRule.Create, ASource, SystemIndex, AConfig, 'Source/Fall.pas');
end;

/// <summary>Unit Fall mit den Deklarationen AInterface im interface-Teil und AImplementation davor.</summary>
function UnitText(const AInterface, AImplementation: string): string;
begin
  Result := 'unit Fall;'#10'interface'#10 + AInterface + 'implementation'#10 + AImplementation + 'end.';
end;

/// <summary>Routine Fall mit den lokalen Variablen AVars und den Anweisungen AStatements.</summary>
function Body(const AVars, AStatements: string): string;
begin
  Result := UnitText('', 'procedure Fall;'#10'var'#10 + AVars + 'begin'#10 + AStatements + 'end;'#10);
end;

/// <summary>Die einzige Meldung zu ASource; '' ohne, alle Meldungen bei mehreren.</summary>
function OnlyMessage(const ASource: string): string;
var
  mFound: TArray<TRuleFinding>;
  mFinding: TRuleFinding;
begin
  mFound := Findings(ASource);
  Result := '';
  for mFinding in mFound do
  begin
    if Result <> '' then
    begin
      Result := Result + ' | ';
    end;
    Result := Result + mFinding.Message;
  end;
end;

procedure AssertSilent(const ASource: string);
begin
  Assert.AreEqual('', OnlyMessage(ASource), ASource);
end;

const
  cVars = '  mZahl: Integer;'#10'  mText: string;'#10'  mZeichen: Char;'#10'  mWert: Double;'#10 +
    '  mFlag: Boolean;'#10'  mKlein: Byte;'#10'  mPreis: Currency;'#10'  mZeiger: PChar;'#10'  mVariant: Variant;'#10 +
    '  mGross: Int64;'#10'  mObjekt: TObject;'#10;

{ TTypeMismatchTests }

procedure TTypeMismatchTests.AssignmentsWithIncompatibleTypes;
var
  mFound: TArray<TRuleFinding>;
begin
  // Cm.E2010.
  mFound := Findings(Body(cVars, '  mZahl := ''abc'';'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(cTypeMismatchRuleId, mFound[0].RuleId);
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''string'' (wie E2010).', mFound[0].Message);
  Assert.AreEqual(17, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(11, mFound[0].Range.StartPos.Character);
  Assert.AreEqual('Inkompatible Typen: ''string'' und ''Integer'' (wie E2010).',
    OnlyMessage(Body(cVars, '  mText := 1;'#10)));
  Assert.AreEqual('Inkompatible Typen: ''Boolean'' und ''Integer'' (wie E2010).',
    OnlyMessage(Body(cVars, '  mFlag := mZahl;'#10)));
  Assert.AreEqual('Inkompatible Typen: ''Char'' und ''string'' (wie E2010).',
    OnlyMessage(Body(cVars, '  mZeichen := ''ab'';'#10)));
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''Extended'' (wie E2010).',
    OnlyMessage(Body(cVars, '  mZahl := 1.5;'#10)));
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''Extended'' (wie E2010).',
    OnlyMessage(Body(cVars, '  mZahl := mZahl / 2;'#10)));
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''Pointer'' (wie E2010).',
    OnlyMessage(Body(cVars, '  mZahl := nil;'#10)));
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''Currency'' (wie E2010).',
    OnlyMessage(Body(cVars, '  mZahl := mPreis;'#10)));
  Assert.AreEqual('Inkompatible Typen: ''Double'' und ''string'' (wie E2010).',
    OnlyMessage(Body(cVars, '  mWert := mText;'#10)));
end;

procedure TTypeMismatchTests.CompatibleAssignmentsAreSilent;
begin
  AssertSilent(Body(cVars, '  mWert := mZahl;'#10'  mText := mZeichen;'#10'  mZeichen := ''a'';'#10 +
    '  mZeichen := mText[1];'#10'  mVariant := mText;'#10'  mZahl := mVariant;'#10'  mGross := mZahl;'#10 +
    '  mPreis := 1;'#10'  mWert := mPreis;'#10'  mZeiger := ''abc'';'#10'  mText := mZeiger;'#10 +
    '  mObjekt := nil;'#10'  mZahl := Ord(''a'');'#10'  mZahl := Length(mText);'#10'  mFlag := mZahl > 0;'#10 +
    '  mText := mText + ''x'';'#10'  mZahl := mZahl div 2;'#10'  mKlein := mZahl;'#10'  mZahl := Unbekannt;'#10 +
    '  mZahl := Round(mWert);'#10'  mZeichen := Chr(65);'#10));
  // Untypisierte Konstante mit einem Zeichen; Records können Implicit haben.
  AssertSilent(UnitText('type'#10'  TBetrag = record'#10'    Wert: Integer;'#10'  end;'#10,
    'const'#10'  cTrenner = '','';'#10'procedure Fall;'#10'var'#10'  mZeichen: Char;'#10'  mBetrag: TBetrag;'#10 +
    'begin'#10'  mZeichen := cTrenner;'#10'  mBetrag := 1;'#10'end;'#10));
end;

procedure TTypeMismatchTests.ProcedureAsValue;
begin
  // Cm.E2143.
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''procedure, untyped pointer or untyped parameter'' ' +
    '(wie E2010).', OnlyMessage(UnitText('', 'procedure Nichts;'#10'begin'#10'end;'#10'procedure Fall;'#10 +
    'var'#10'  mZahl: Integer;'#10'begin'#10'  mZahl := Nichts;'#10'end;'#10)));
  // Ein prozeduraler Typ nimmt die Prozedur, ein Zeiger ihre Adresse.
  AssertSilent(UnitText('', 'procedure Nichts;'#10'begin'#10'end;'#10'procedure Fall;'#10'var'#10 +
    '  mProzedur: procedure;'#10'  mZeiger: Pointer;'#10'begin'#10'  mProzedur := Nichts;'#10 +
    '  mZeiger := @Nichts;'#10'end;'#10));
end;

procedure TTypeMismatchTests.StaticArraysClassesAndDefaults;
begin
  // Cm.E2413.
  Assert.AreEqual('Inkompatible Typen: ''array[0..2] of Integer'' und ''Pointer'' (wie E2010).',
    OnlyMessage(Body('  mFeld: array[0..2] of Integer;'#10, '  mFeld := nil;'#10)));
  // array of Char nimmt einen String passender Länge, ein dynamisches Array nil.
  AssertSilent(Body('  mFeld: array[0..2] of Char;'#10'  mListe: array of Integer;'#10,
    '  mFeld := ''abc'';'#10'  mListe := nil;'#10));
  // Cm.W1013: Standardwert 0 für eine Klasse.
  Assert.AreEqual('Inkompatible Typen: ''TObject'' und ''Integer'' (wie E2010).',
    OnlyMessage(UnitText('', 'procedure Nehmen(AObjekt: TObject = 0);'#10'begin'#10'end;'#10)));
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''Char'' (wie E2010).',
    OnlyMessage(UnitText('', 'procedure Nehmen(AZahl: Integer = ''a'');'#10'begin'#10'end;'#10)));
  AssertSilent(UnitText('', 'procedure Nehmen(AObjekt: TObject = nil; AZahl: Integer = 0; ' +
    'AText: string = ''''; AWert: Double = 1);'#10'begin'#10'end;'#10));
  Assert.AreEqual('Inkompatible Typen: ''TObject'' und ''Integer'' (wie E2010).',
    OnlyMessage(Body(cVars, '  mObjekt := 0;'#10)));
end;

procedure TTypeMismatchTests.DuplicateLocalAndInterfaceResult;
begin
  // Cm.E2004: Wie bei dcc gilt die letzte Deklaration.
  Assert.AreEqual('Inkompatible Typen: ''string'' und ''Integer'' (wie E2010).',
    OnlyMessage(Body('  mZahl: Integer;'#10'  mZahl: string;'#10, '  mZahl := 1;'#10)));
  // Cm.E2037: Result hat den Typ aus dem interface-Teil.
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''string'' (wie E2010).',
    OnlyMessage(UnitText('function Liefere: Integer;'#10, 'function Liefere: string;'#10'begin'#10 +
    '  Result := '''';'#10'end;'#10)));
  AssertSilent(UnitText('function Liefere: string;'#10, 'function Liefere: string;'#10'begin'#10 +
    '  Result := '''';'#10'end;'#10));
end;

procedure TTypeMismatchTests.ValueAndVarArguments;
const
  cRoutines = 'procedure Erhoehen(var AWert: Integer);'#10'begin'#10'end;'#10 +
    'procedure Zeigen(const AText: string; AZahl: Integer);'#10'begin'#10'end;'#10;
var
  mFound: TArray<TRuleFinding>;
begin
  // Cm.E2033.
  mFound := Findings(UnitText('', cRoutines + 'procedure Fall;'#10'var'#10'  mKlein: Byte;'#10'begin'#10 +
    '  Erhoehen(mKlein);'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('Die Typen der tatsächlichen und formalen var-Parameter müssen übereinstimmen: Integer und Byte ' +
    '(wie E2033).', mFound[0].Message);
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''Char'' (wie E2010).',
    OnlyMessage(UnitText('', cRoutines + 'procedure Fall;'#10'begin'#10'  Zeigen(''a'', ''b'');'#10'end;'#10)));
  Assert.AreEqual('Inkompatible Typen: ''string'' und ''Integer'' (wie E2010).',
    OnlyMessage(UnitText('', cRoutines + 'procedure Fall;'#10'begin'#10'  Zeigen(1, 2);'#10'end;'#10)));
  // Methode eines Objekts.
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''Char'' (wie E2010).',
    OnlyMessage(UnitText('type'#10'  TListe = class'#10'    procedure Setzen(AZahl: Integer);'#10'  end;'#10,
    'procedure TListe.Setzen(AZahl: Integer);'#10'begin'#10'end;'#10'procedure Fall(AListe: TListe);'#10 +
    'begin'#10'  AListe.Setzen(''x'');'#10'end;'#10)));
  // string[N] an var ShortString: mit {$P+} sind das offene Strings (FP mORMot2 AppendShort(LF, line)).
  AssertSilent(UnitText('', 'procedure Anhaengen(const AQuelle: ShortString; var AZiel: ShortString);'#10 +
    'begin'#10'end;'#10'procedure Fall;'#10'var'#10'  mZeile: string[87];'#10'begin'#10 +
    '  Anhaengen(''x'', mZeile);'#10'end;'#10));
  // string[N] an var string bleibt ein Fehler.
  Assert.AreEqual(1, Integer(Length(Findings(UnitText('', 'procedure Fuellen(var AText: string);'#10 +
    'begin'#10'end;'#10'procedure Fall;'#10'var'#10'  mZeile: string[87];'#10'begin'#10 +
    '  Fuellen(mZeile);'#10'end;'#10)))));
end;

procedure TTypeMismatchTests.ArgumentsThatFitAreSilent;
begin
  AssertSilent(UnitText('', 'procedure Erhoehen(var AWert: Integer);'#10'begin'#10'end;'#10 +
    'procedure Lesen(var APuffer);'#10'begin'#10'end;'#10 +
    'procedure Zeigen(const AText: string; AWert: Double);'#10'begin'#10'end;'#10 +
    'procedure Nimm(AZahl: Integer); overload;'#10'begin'#10'end;'#10 +
    'procedure Nimm(const AText: string); overload;'#10'begin'#10'end;'#10 +
    'procedure Breit(var AWert: NativeInt);'#10'begin'#10'end;'#10 +
    'procedure Fall;'#10'var'#10'  mZahl: Integer;'#10'  mLang: LongInt;'#10'  mKlein: Byte;'#10 +
    '  mBreit: NativeInt;'#10'begin'#10'  Erhoehen(mZahl);'#10'  Erhoehen(mLang);'#10'  Lesen(mKlein);'#10 +
    '  Zeigen(''a'', 1);'#10'  Zeigen(''a'', mZahl);'#10'  Nimm(''a'');'#10'  Nimm(1);'#10 +
    '  Breit(mBreit);'#10'end;'#10));
end;

procedure TTypeMismatchTests.ArrayPropertyIndex;
const
  cListe = 'type'#10'  TListe = class'#10'  private'#10'    function GetEintrag(AIndex: Integer): string;'#10 +
    '  public'#10'    property Eintrag[AIndex: Integer]: string read GetEintrag; default;'#10'  end;'#10;
  cGetter = 'function TListe.GetEintrag(AIndex: Integer): string;'#10'begin'#10'  Result := '''';'#10'end;'#10;
begin
  // Cm.E2450.
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''Char'' (wie E2010).',
    OnlyMessage(UnitText(cListe, cGetter + 'function Fall(AListe: TListe): string;'#10'begin'#10 +
    '  Result := AListe[''a''];'#10'end;'#10)));
  AssertSilent(UnitText(cListe, cGetter + 'function Fall(AListe: TListe): string;'#10'begin'#10 +
    '  Result := AListe[1] + AListe.Eintrag[2];'#10'end;'#10));
end;

procedure TTypeMismatchTests.OperatorsNotApplicable;
begin
  // Cm.E2015, Cm.E2020, Cm.E2008.
  Assert.AreEqual('Der Operator - ist auf string und Char nicht anwendbar (wie E2015).',
    OnlyMessage(Body(cVars, '  mText := mText - ''a'';'#10)));
  Assert.AreEqual('Der Operator is braucht rechts eine Klasse; Integer ist keine (wie E2015).',
    OnlyMessage(Body(cVars, '  if mObjekt is Integer then'#10'    Exit;'#10)));
  Assert.AreEqual('Inkompatible Typen: ''Integer'' und ''AnsiChar'' (wie E2010).',
    OnlyMessage(Body('  mMenge: set of Byte;'#10, '  mMenge := [1] + [''a''];'#10)));
  Assert.AreEqual('Inkompatible Typen: ''string'' und ''Integer'' (wie E2010).',
    OnlyMessage(Body(cVars, '  mText := ''Anzahl: '' + mZahl;'#10)));
  Assert.AreEqual('Der Operator div ist auf Double und Integer nicht anwendbar (wie E2015).',
    OnlyMessage(Body(cVars, '  mWert := mWert div 2;'#10)));
  Assert.AreEqual('Der Operator not ist auf string nicht anwendbar (wie E2015).',
    OnlyMessage(Body(cVars, '  mFlag := not mText;'#10)));
  Assert.AreEqual('Der Operator - ist auf Boolean nicht anwendbar (wie E2015).',
    OnlyMessage(Body(cVars, '  mZahl := -mFlag;'#10)));
  Assert.AreEqual('Der Operator + ist auf Boolean und Integer nicht anwendbar (wie E2015).',
    OnlyMessage(Body(cVars, '  mZahl := mFlag + 1;'#10)));
end;

procedure TTypeMismatchTests.OperatorsThatFitAreSilent;
begin
  AssertSilent(Body(cVars + '  mMenge: set of Byte;'#10, '  mZahl := mZahl + 1;'#10'  mText := mText + mZeichen;'#10 +
    '  mFlag := mFlag and (mZahl > 0);'#10'  mZahl := mZahl and $FF;'#10'  mMenge := [1] + [2] - [3];'#10 +
    '  mVariant := mVariant + 1;'#10'  mWert := mWert * mZahl;'#10'  mPreis := mPreis * 2;'#10 +
    '  mZahl := mZahl shl 2;'#10'  mFlag := not mFlag;'#10'  mZahl := -mZahl;'#10 +
    '  mFlag := mZeichen in [''a''..''z''];'#10'  mZeiger := mZeiger + 1;'#10));
end;

procedure TTypeMismatchTests.InvalidTypecasts;
begin
  // Cm.E2089.
  Assert.AreEqual('Ungültige Typumwandlung: string nach Byte (wie E2089).',
    OnlyMessage(Body(cVars, '  mKlein := Byte(mText);'#10)));
  Assert.AreEqual('Ungültige Typumwandlung: Double nach Integer (wie E2089).',
    OnlyMessage(Body(cVars, '  mZahl := Integer(mWert);'#10)));
  // Integer(S) übersetzt Win32 (gleich groß wie ein Zeiger); Ordinaltypen untereinander gehen immer.
  AssertSilent(Body(cVars, '  mZahl := Integer(mText);'#10'  mKlein := Byte(mZahl);'#10 +
    '  mZahl := Word(mZeichen);'#10'  mZeichen := Char(65);'#10'  mZahl := Integer(mFlag);'#10));
end;

procedure TTypeMismatchTests.IncAndPtr;
begin
  // Cm.E2013, Cm.E2198.
  Assert.AreEqual('Inkompatible Typen: Inc erwartet als Schrittweite eine Ganzzahl, 1.5 ist Extended (wie E2008).',
    OnlyMessage(Body(cVars, '  Inc(mZahl, 1.5);'#10)));
  Assert.AreEqual('Inkompatible Typen: Ptr erwartet eine Adresse als Ganzzahl, mText ist string (wie E2008).',
    OnlyMessage(Body(cVars + '  mAdresse: Pointer;'#10, '  mAdresse := Ptr(mText);'#10)));
  AssertSilent(Body(cVars + '  mAdresse: Pointer;'#10, '  Inc(mZahl, 2);'#10'  Dec(mZahl);'#10 +
    '  mAdresse := Ptr(mZahl);'#10));
  // Dezimalzahlen über High(Int64) sind UInt64, keine Gleitkommazahlen (Alcinoe: FNV-Startwert, Dec um 10^19).
  AssertSilent(Body(cVars, '  mGross := Int64(14695981039346656037);'#10 +
    '  Dec(mGross, 10000000000000000000);'#10));
end;

procedure TTypeMismatchTests.ProceduralTypes;
const
  cKlasse = 'type'#10'  TRueckruf = procedure;'#10'  TEreignis = procedure of object;'#10 +
    '  TKlasse = class'#10'  public'#10'    procedure Machen;'#10'    class procedure Statisch; static;'#10 +
    '  end;'#10;
  cRuempfe = 'procedure TKlasse.Machen;'#10'begin'#10'end;'#10'class procedure TKlasse.Statisch;'#10'begin'#10 +
    'end;'#10'procedure Frei;'#10'begin'#10'end;'#10;
begin
  // Cm.E2009.
  Assert.AreEqual('Inkompatible Typen: ''Liste der Parameter ist unterschiedlich''; Fall passt nicht zum ' +
    'prozeduralen Typ (wie E2009).', OnlyMessage(UnitText('', 'procedure Fall;'#10'var'#10 +
    '  mProzedur: procedure(AWert: Integer);'#10'begin'#10'  mProzedur := Fall;'#10'end;'#10)));
  // Cm.E2366, Cm.E2380.
  Assert.AreEqual('Inkompatible Typen: ''Reguläre Prozedur und Methodenzeiger''; TKlasse.Machen ist eine Methode, ' +
    'der Typ hat kein of object (wie E2009).', OnlyMessage(UnitText(cKlasse, cRuempfe + 'procedure Fall;'#10 +
    'var'#10'  mRueckruf: TRueckruf;'#10'begin'#10'  mRueckruf := TKlasse.Machen;'#10'end;'#10)));
  Assert.AreEqual('Inkompatible Typen: ''Methodenzeiger und reguläre Prozedur''; TKlasse.Statisch ist keine ' +
    'Methode eines Objekts (wie E2009).', OnlyMessage(UnitText(cKlasse, cRuempfe + 'procedure Fall;'#10 +
    'var'#10'  mEreignis: TEreignis;'#10'begin'#10'  mEreignis := TKlasse.Statisch;'#10'end;'#10)));
  // Cm.E2273: von den Überladungen passt keine.
  Assert.AreEqual('Inkompatible Typen: ''Double'' und ''Integer'' (wie E2010).',
    OnlyMessage(UnitText('', 'procedure Nimm(AWert: Integer); overload;'#10'begin'#10'end;'#10 +
    'procedure Nimm(const AText: string); overload;'#10'begin'#10'end;'#10'procedure Fall;'#10'var'#10 +
    '  mRueckruf: procedure(AWert: Double);'#10'begin'#10'  mRueckruf := Nimm;'#10'end;'#10)));
  // Passende Zuweisungen, reference to und Funktionen ohne Parameter (Aufruf) bleiben still.
  AssertSilent(UnitText(cKlasse, cRuempfe + 'function Zahl: Integer;'#10'begin'#10'  Result := 1;'#10'end;'#10 +
    'procedure Fall(AKlasse: TKlasse);'#10'var'#10'  mRueckruf: TRueckruf;'#10'  mEreignis: TEreignis;'#10 +
    '  mReferenz: reference to procedure;'#10'  mZahl: Integer;'#10 +
    '  mFunktion: function: Integer;'#10'begin'#10'  mRueckruf := Frei;'#10'  mRueckruf := TKlasse.Statisch;'#10 +
    '  mEreignis := AKlasse.Machen;'#10'  mReferenz := Frei;'#10'  mReferenz := AKlasse.Machen;'#10 +
    '  mZahl := Zahl;'#10'  mFunktion := Zahl;'#10'end;'#10));
  // Methodenreferenz mit Parametern, Routine ohne (wie E2010, #1897).
  Assert.AreEqual('Inkompatible Typen: ''reference to procedure(AWert: Integer)'' und ''Procedure''; die ' +
    'Parameter von Frei passen nicht zur Methodenreferenz (Zahl, const/var/out oder Typ, wie E2010).',
    OnlyMessage(UnitText(cKlasse, cRuempfe + 'procedure Fall;'#10'var'#10 +
    '  mReferenz: reference to procedure(AWert: Integer);'#10'begin'#10'  mReferenz := Frei;'#10'end;'#10)));
end;

procedure TTypeMismatchTests.ConditionalParameterModifierIsSilent;
const
  cTypen = 'type'#10'  TAuswahl = record'#10'    A: Integer;'#10'  end;'#10 +
    '  TAuswahlEreignis = procedure(Sender: TObject; const AWahl: TAuswahl) of object;'#10 +
    '  TBeobachter = class'#10'  public'#10 +
    '    procedure Gewaehlt(Sender: TObject; {$IFDEF FPC}constref{$ELSE}const{$ENDIF} AWahl: TAuswahl);'#10 +
    '  end;'#10;
begin
  // Der Kopf der Methode hängt an einer bedingten Direktive; dcc sieht const (PascalCoin: OnSelection).
  AssertSilent(UnitText(cTypen, 'procedure TBeobachter.Gewaehlt(Sender: TObject; ' +
    '{$IFDEF FPC}constref{$ELSE}const{$ENDIF} AWahl: TAuswahl);'#10'begin'#10'end;'#10 +
    'procedure Fall(ABeobachter: TBeobachter);'#10'var'#10'  mEreignis: TAuswahlEreignis;'#10'begin'#10 +
    '  mEreignis := ABeobachter.Gewaehlt;'#10'end;'#10));
end;

procedure TTypeMismatchTests.MethodReferenceParameters;
const
  cRoutinen = 'function LastFailed(const AProject: string): TArray<string>;'#10'begin'#10'  Result := nil;'#10 +
    'end;'#10'procedure Say(const AText: string);'#10'begin'#10'end;'#10 +
    'procedure Merke(var AText: string);'#10'begin'#10'end;'#10 +
    'procedure Zaehle(AZahl: Integer);'#10'begin'#10'end;'#10 +
    'procedure Frage(const AText: string; AAntwort: TProc<string>);'#10'begin'#10'end;'#10;
  cWie = ' passen nicht zur Methodenreferenz (Zahl, const/var/out oder Typ, wie E2010).';
begin
  // Fall aus Atlas.IDE.Tests.Composition: TFunc<T, R> erwartet den Parameter ohne const.
  Assert.AreEqual('26: Inkompatible Typen: ''TFunc<string,TArray<string>>'' und ''Procedure''; die Parameter von ' +
    'LastFailed' + cWie, Messages(ReferenceFindings(cRoutinen, '  GTest := LastFailed;'#10)));
  // var statt Wertparameter, anderer Typ.
  Assert.AreEqual('26: Inkompatible Typen: ''TProc<string>'' und ''Procedure''; die Parameter von Merke' + cWie +
    ' | 27: Inkompatible Typen: ''TProc<string>'' und ''Procedure''; die Parameter von Zaehle' + cWie,
    Messages(ReferenceFindings(cRoutinen, '  GProc := Merke;'#10'  GProc := Zaehle;'#10)));
  // Als Argument (Debug.EventBreak: Report(const AText: string) an TProc<string>).
  Assert.AreEqual('26: Inkompatible Typen: ''TProc<string>'' und ''Procedure''; die Parameter von Say' + cWie,
    Messages(ReferenceFindings(cRoutinen, '  Frage(''Weiter?'', Say);'#10)));
  // Anonyme Methoden mit const bzw. ohne Parameter (#1345).
  Assert.AreEqual('26: Inkompatible Typen: ''TProc<string>'' und ''Procedure''; die Parameter von ' +
    'procedure(const AText: string)' + cWie + ' | 27: Inkompatible Typen: ''TProc<string>'' und ''Procedure''; ' +
    'die Parameter von procedure' + cWie, Messages(ReferenceFindings(cRoutinen,
    '  GProc := procedure(const AText: string) begin end;'#10'  Frage(''Weiter?'', procedure begin end);'#10)));
end;

procedure TTypeMismatchTests.FunctionReturningReferenceWithoutParens;
const
  cRoutinen = 'function Gib: TProc<string>;'#10'begin'#10'  Result := nil;'#10'end;'#10 +
    'procedure Frage(const AText: string; AAntwort: TProc<string>);'#10'begin'#10'end;'#10;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := ReferenceFindings(cRoutinen, '  GProc := Gib;'#10'  Frage(''Weiter?'', Gib);'#10);
  Assert.AreEqual('17: Inkompatible Typen: ''TProc<string>'' und ''Procedure''; Gib liefert TProc<string>, ohne () ' +
    'steht der Name aber für die Funktion selbst (wie E2010). | 18: Inkompatible Typen: ''TProc<string>'' und ' +
    '''Procedure''; Gib liefert TProc<string>, ohne () steht der Name aber für die Funktion selbst (wie E2010).',
    Messages(mFound));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('() ergänzen', mFound[0].Fixes[0].Title);
  Assert.AreEqual('()', mFound[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(17, mFound[0].Fixes[0].Edits[0].Range.StartPos.Line);
  Assert.AreEqual(14, mFound[0].Fixes[0].Edits[0].Range.StartPos.Character);
end;

procedure TTypeMismatchTests.MethodReferencesThatFitAreSilent;
const
  cRoutinen = 'type'#10'  TBox = class'#10'    procedure Nimm(AText: string);'#10'  end;'#10 +
    'procedure TBox.Nimm(AText: string);'#10'begin'#10'end;'#10 +
    'function Passt(AProject: string): TArray<string>;'#10'begin'#10'  Result := nil;'#10'end;'#10 +
    'procedure Hoere(AText: string);'#10'begin'#10'end;'#10 +
    'function Gib: TProc<string>;'#10'begin'#10'  Result := nil;'#10'end;'#10 +
    'function Zahl: Integer;'#10'begin'#10'  Result := 1;'#10'end;'#10 +
    'procedure Frage(const AText: string; AAntwort: TProc<string>);'#10'begin'#10'end;'#10;
begin
  Assert.AreEqual('', Messages(ReferenceFindings(cRoutinen + 'var'#10'  GBox: TBox;'#10'  GZahl: TFunc<Integer>;'#10,
    '  GTest := Passt;'#10'  GProc := Hoere;'#10'  GProc := GBox.Nimm;'#10'  GProc := Gib();'#10 +
    '  GZahl := Zahl;'#10'  Frage(''Weiter?'', Hoere);'#10'  Frage(''Weiter?'', Gib());'#10 +
    '  Frage(''Weiter?'', procedure(AText: string)'#10'    begin'#10'    end);'#10)));
end;

/// <summary>Befunde in einer Unit mit AUses, deren Index nur System kennt (ohne RTL-Quelltext).</summary>
function WithoutRtlFindings(const AUses, ADeclarations, AStatements: string): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.IndexFindings(TTypeMismatchRule.Create, 'unit Fall;'#10'interface'#10'uses'#10 + AUses +
    ';'#10'implementation'#10'var'#10'  GProc: TProc<string>;'#10'  GFunc: System.SysUtils.TFunc<Integer>;'#10 +
    ADeclarations + 'procedure Fall;'#10'begin'#10 + AStatements + 'end;'#10'end.', SystemIndex, '', 'Fall.pas');
end;

procedure TTypeMismatchTests.RtlReferencesWithoutIndex;
const
  cRoutinen = 'function Gib: TProc<string>;'#10'begin'#10'  Result := nil;'#10'end;'#10 +
    'function Zahl: TFunc<Integer>;'#10'begin'#10'  Result := nil;'#10'end;'#10 +
    'procedure Merke(var AText: string);'#10'begin'#10'end;'#10 +
    'procedure Frage(const AText: string; const AAntwort: TProc<string>);'#10'begin'#10'end;'#10;
  cAnweisungen = '  GProc := Gib;'#10'  Frage(''Weiter?'', Gib);'#10'  GFunc := Zahl;'#10'  GProc := Merke;'#10;
  cOhne = ', ohne () steht der Name aber für die Funktion selbst (wie E2010).';
begin
  // Fall aus Atlas.IDE.Debug.RuntimeReport: RunServerCommandAsync(…, ReportAnswer).
  Assert.AreEqual('25: Inkompatible Typen: ''TProc<string>'' und ''Procedure''; Gib liefert TProc<string>' + cOhne +
    ' | 26: Inkompatible Typen: ''TProc<string>'' und ''Procedure''; Gib liefert TProc<string>' + cOhne +
    ' | 27: Inkompatible Typen: ''TFunc<Integer>'' und ''Procedure''; Zahl liefert TFunc<Integer>' + cOhne +
    ' | 28: Inkompatible Typen: ''TProc<string>'' und ''Procedure''; die Parameter von Merke passen nicht zur ' +
    'Methodenreferenz (Zahl, const/var/out oder Typ, wie E2010).',
    Messages(WithoutRtlFindings('  System.SysUtils,'#10'  Vcl.Forms', cRoutinen, cAnweisungen)));
  Assert.AreEqual('', Messages(WithoutRtlFindings('  System.SysUtils', cRoutinen,
    '  GProc := Gib();'#10'  Frage(''Weiter?'', Gib());'#10'  GFunc := Zahl();'#10)));
  // Eine fremde Unit hinter System.SysUtils kann TProc verdecken; ohne System.SysUtils gibt es keinen.
  Assert.AreEqual('', Messages(WithoutRtlFindings('  System.SysUtils,'#10'  Fremd', cRoutinen, cAnweisungen)));
  Assert.AreEqual('', Messages(WithoutRtlFindings('  System.Classes', cRoutinen, cAnweisungen)));
end;

procedure TTypeMismatchTests.NestedTypeHidesUsedType;
const
  cKarte = 'unit Fall;'#10'interface'#10'uses'#10'  Typen;'#10'type'#10'  TKarte = class'#10'  public'#10 +
    '    type'#10'      TBytes8 = array of Byte;'#10'      TListe = TBytes8;'#10'      TInnen = class'#10 +
    '        FInnen: TBytes8;'#10'      end;'#10'  private'#10'    FDaten: TBytes8;'#10'    FListe: TListe;'#10 +
    '    FFremd: TAndere;'#10'  public'#10'    procedure Leeren;'#10'    procedure Setze(const A: TBytes8);'#10'  end;'#10 +
    '  TAndere = class'#10 +
    '    FDaten: TBytes8;'#10'  end;'#10'implementation'#10 +
    'procedure TKarte.Leeren;'#10'var'#10'  mInnen: TInnen;'#10'begin'#10'  FDaten := nil;'#10 +
    '  FListe := nil;'#10'  mInnen := nil;'#10'  mInnen.FInnen := nil;'#10'  FFremd.FDaten := nil;'#10'  Setze(FDaten);'#10'end;'#10 +
    'procedure TKarte.Setze(const A: TBytes8);'#10'begin'#10'end;'#10'end.';
var
  mIndex: ISymbolIndex;
begin
  mIndex := SystemIndex;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Typen;'#10'interface'#10'type'#10 +
    '  TBytes8 = array[0..65535] of Byte;'#10'implementation'#10'end.', 'Typen.pas', nil));
  // Nur das Feld von TAndere hat das statische Array aus Typen.
  Assert.AreEqual('33: Inkompatible Typen: ''TBytes8'' und ''Pointer'' (wie E2010).',
    Messages(TRuleAssert.IndexFindings(TTypeMismatchRule.Create, cKarte, mIndex, '', 'Fall.pas')));
end;

procedure TTypeMismatchTests.ProceduralCalleeArguments;
const
  cTypen = 'type'#10'  TBaum = reference to function(const AText: string; const ANeu: TProc): string;'#10 +
    '  TAnsicht = class'#10'    FBaum: TBaum;'#10'    FAuch: TFunc<string, TProc, string>;'#10 +
    '    FZahl: TProc<Integer>;'#10'    function Neu: TProc;'#10'    procedure Zeige;'#10'  end;'#10;
  cRuempfe = 'function TAnsicht.Neu: TProc;'#10'begin'#10'  Result := nil;'#10'end;'#10;
  cOhne = 'Inkompatible Typen: ''TProc'' und ''Procedure''; Neu liefert TProc, ohne () steht der Name aber für die ' +
    'Funktion selbst (wie E2010).';
begin
  Assert.AreEqual('22: ' + cOhne + ' | 23: ' + cOhne + ' | 24: Inkompatible Typen: ''Integer'' und ''Char'' ' +
    '(wie E2010).', Messages(TRuleAssert.IndexFindings(TTypeMismatchRule.Create, 'unit Fall;'#10'interface'#10'uses'#10 +
    '  System.SysUtils;'#10 + cTypen + 'implementation'#10 + cRuempfe + 'procedure TAnsicht.Zeige;'#10'var'#10 +
    '  mText: string;'#10'begin'#10'  mText := FBaum(''a'', Neu);'#10'  mText := FAuch(''a'', Neu);'#10 +
    '  FZahl(''a'');'#10'  mText := FBaum(''a'', Neu());'#10'  FZahl(1);'#10'end;'#10'end.', SysUtilsIndex, '',
    'Fall.pas')));
end;

procedure TTypeMismatchTests.ConditionalDeclarationsAndWithAreSilent;
begin
  // Aliase: über die Kette bis zum eingebauten Typ; ein Glied in einem bedingten Zweig macht den Typ offen
  // (Virtual-TreeView TDimension), var-Argumente mit Alias bleiben offen (Graphics32 TFloat = Single).
  Assert.AreEqual('Inkompatible Typen: ''TBreite'' und ''Char'' (wie E2010).',
    OnlyMessage(UnitText('type'#10'  TMass = Integer;'#10'  TBreite = TMass;'#10, 'procedure Fall;'#10'var'#10 +
    '  mBreite: TBreite;'#10'begin'#10'  mBreite := ''a'';'#10'end;'#10)));
  AssertSilent(UnitText('type'#10'{$IFDEF FMX}'#10'  TMass = Single;'#10'{$ELSE}'#10'  TMass = Integer;'#10 +
    '{$ENDIF}'#10'  TBreite = TMass;'#10, 'procedure Fall;'#10'var'#10'  mBreite: TBreite;'#10'begin'#10 +
    '  mBreite := 1.5;'#10'end;'#10));
  AssertSilent(UnitText('type'#10'  TFloat = Single;'#10, 'procedure Teilen(var AWert: Single);'#10'begin'#10 +
    'end;'#10'procedure Fall;'#10'var'#10'  mWert: TFloat;'#10'begin'#10'  Teilen(mWert);'#10'end;'#10));
  // Lines[i][j] ist ein Zeichen (SynEdit); Result einer überladenen Funktion hat den eigenen Typ (Clipper).
  AssertSilent(UnitText('type'#10'  TListe = class'#10'    function GetZeile(AIndex: Integer): string;'#10 +
    '    property Zeilen[AIndex: Integer]: string read GetZeile; default;'#10'  end;'#10 +
    'function Wahl(AFlag, AJa, ANein: Boolean): Boolean; overload;'#10 +
    'function Wahl(AFlag: Boolean; AJa, ANein: Integer): Integer; overload;'#10,
    'function TListe.GetZeile(AIndex: Integer): string;'#10'begin'#10'  Result := '''';'#10'end;'#10 +
    'function Wahl(AFlag, AJa, ANein: Boolean): Boolean;'#10'begin'#10'  Result := AJa;'#10'end;'#10 +
    'function Wahl(AFlag: Boolean; AJa, ANein: Integer): Integer;'#10'begin'#10'  Result := AJa;'#10'end;'#10 +
    'procedure Fall(AListe: TListe);'#10'var'#10'  mZeichen: Char;'#10'begin'#10 +
    '  mZeichen := AListe[0][1];'#10'end;'#10));
  AssertSilent(Body('{$IFDEF UNICODE}'#10'  mZahl: string;'#10'{$ELSE}'#10'  mZahl: Integer;'#10'{$ENDIF}'#10,
    '  mZahl := 1;'#10));
  AssertSilent(UnitText('type'#10'  TPunkt = record'#10'    X: string;'#10'  end;'#10,
    'procedure Fall(const APunkt: TPunkt);'#10'var'#10'  X: Integer;'#10'begin'#10'  with APunkt do'#10 +
    '    X := ''a'';'#10'end;'#10));
end;

procedure TTypeMismatchTests.OffAndGroupSwitches;
var
  mSource: string;
begin
  mSource := Body(cVars, '  mZahl := ''abc'';'#10);
  Assert.AreEqual(1, Integer(Length(Findings(mSource, ''))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"type-mismatch": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"group:compiler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"group:compiler": {"typeLevel": "off"}}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"type-mismatch": {"exclude": ["Source/*.pas"]}}}'))));
end;

procedure TTypeMismatchTests.RuleIsRegistered;var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
  begin
    if mRule.Descriptor.Id = cTypeMismatchRuleId then
    begin
      mFound := True;
    end;
  end;
  Assert.IsTrue(mFound);
end;

procedure TTypeMismatchTests.OverloadsFromSeveralUnitsAreSilent;
var
  mIndex: ISymbolIndex;
  mSource: string;
begin
  mIndex := SystemIndex;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Mathe;'#10'interface'#10 +
    'function IfThen(ACond: Boolean; ATrue, AFalse: Integer): Integer; overload;'#10'implementation'#10 +
    'function IfThen(ACond: Boolean; ATrue, AFalse: Integer): Integer;'#10'begin'#10'  Result := ATrue;'#10 +
    'end;'#10'end.', 'C:\P\Mathe.pas', nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Texte;'#10'interface'#10 +
    'function IfThen(ACond: Boolean; const ATrue, AFalse: string): string; overload;'#10'implementation'#10 +
    'function IfThen(ACond: Boolean; const ATrue, AFalse: string): string;'#10'begin'#10'  Result := ATrue;'#10 +
    'end;'#10'end.', 'C:\P\Texte.pas', nil));
  mSource := 'unit Fall;'#10'interface'#10'implementation'#10'uses'#10'  Mathe,'#10'  Texte;'#10 +
    'procedure Fall(AFlag: Boolean; AZahl: Integer);'#10'var'#10'  mOrder: Integer;'#10'begin'#10 +
    '  mOrder := AZahl + IfThen(AFlag, 0, AZahl);'#10'end;'#10'end.';
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TTypeMismatchRule.Create, mSource, mIndex, '',
    'Fall.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeMismatchTests);

end.
