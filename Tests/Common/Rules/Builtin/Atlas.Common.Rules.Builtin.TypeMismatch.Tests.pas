unit Atlas.Common.Rules.Builtin.TypeMismatch.Tests;

// Tests der Regel type-mismatch (#1369). Je Code die Form aus
// Tests/Compilermeldungen (Cm.<Code>.pas) und Gegenfälle, die dcc ohne Meldung
// übersetzt: Zuweisung und Standardwert (E2010), Prozedur als Wert (E2010),
// doppelte lokale Deklaration und Result aus dem interface-Teil (E2010),
// Argumente und Array-Property (E2010), var-Argument (E2033), Operatoren
// (E2015, E2010), Typumwandlungen (E2089), Inc und Ptr (E2008), prozedurale
// Typen (E2009, E2010), bedingte Deklarationen, with, Abschalten.

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
    procedure ConditionalDeclarationsAndWithAreSilent;
    [Test]
    procedure OffAndGroupSwitches;
    [Test]
    procedure RuleIsRegistered;
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
      Result := Result + ' | ';
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
  Assert.AreEqual(TypeMismatchRuleId, mFound[0].RuleId);
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
    '  mReferenz: reference to procedure(AWert: Integer);'#10'  mZahl: Integer;'#10 +
    '  mFunktion: function: Integer;'#10'begin'#10'  mRueckruf := Frei;'#10'  mRueckruf := TKlasse.Statisch;'#10 +
    '  mEreignis := AKlasse.Machen;'#10'  mReferenz := Frei;'#10'  mZahl := Zahl;'#10'  mFunktion := Zahl;'#10 +
    'end;'#10));
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

procedure TTypeMismatchTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
    if mRule.Descriptor.Id = TypeMismatchRuleId then
      mFound := True;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeMismatchTests);

end.
