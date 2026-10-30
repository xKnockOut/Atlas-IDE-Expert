unit Atlas.Common.Rules.Builtin.TypeKinds.Tests;

// Tests der Regel type-kind-required (#1370): je Code die Form aus
// Tests/Compilermeldungen (Cm.<Code>.pas) und ein Gegenfall, den dcc ohne
// Meldung übersetzt: Index, ^, Punkt und with auf einfachen Werten (E2016,
// E2017, E2018), Korrektur "^ entfernen", Helfer und unbekannte Units,
// Vorfahren von object, Klasse und Helfer (E2019, E2021, E2022, E2474),
// New/Dispose mit Konstruktor und TypeOf (E2467, E2019), TBasis.Machen
// (E2076), Slice (E2193), array of const (E2150), Write/Read (E2054, E2055),
// Abschalten und Registrierung.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTypeKindRequiredTests = class
  public
    [Test]
    procedure IndexDereferenceMemberAndWith;
    [Test]
    procedure DereferenceFixForClassesAndRecords;
    [Test]
    procedure ValidAccessIsSilent;
    [Test]
    procedure HelpersAndUnknownUnitsAreSilent;
    [Test]
    procedure AncestorsOfObjectClassAndHelper;
    [Test]
    procedure ValidAncestorsAreSilent;
    [Test]
    procedure ConstructorFormsAndTypeOf;
    [Test]
    procedure ClassMethodForm;
    [Test]
    procedure ClassMethodFormInMethodsIsSilent;
    [Test]
    procedure SliceOutsideOpenArray;
    [Test]
    procedure RecordInArrayOfConst;
    [Test]
    procedure WriteAndReadWithStructuredTypes;
    [Test]
    procedure WriteAndReadSilentCases;
    [Test]
    procedure OffAndExclude;
    [Test]
    procedure RuleIsRegistered;
    /// <summary>X.TryGetValue&lt;Integer&gt;(…) ist kein Punkt auf dem Boolean-Ergebnis (Fehlalarm in
    /// Atlas.Common.Lsp.Positions).</summary>
    [Test]
    procedure GenericMethodCallIsNoDotOnResult;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.TypeKinds,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

function Lines(const ALines: array of string): string;
var
  mLine: string;
begin
  Result := '';
  for mLine in ALines do
    Result := Result + mLine + #10;
end;

/// <summary>Index mit System (TObject, TClass, PInteger, TextFile) und SysUtils mit TIntegerHelper.</summary>
function SystemIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(Lines(['unit System;', 'interface', 'type', '  TObject = class',
    '  public', '    function ToString: string; virtual;', '  end;', '  TClass = class of TObject;',
    '  PInteger = ^Integer;', '  TArray<T> = array of T;', 'implementation', 'end.']), 'C:\BDS\source\System.pas',
    nil));
  Result.AddUnit(TIndexExtractor.ExtractText(Lines(['unit SysUtils;', 'interface', 'type',
    '  TIntegerHelper = record helper for Integer', '  public', '    function ToString: string;', '  end;',
    'procedure Ausgeben(const AFormat: string; const AArgs: array of const);', 'implementation', 'end.']),
    'C:\BDS\source\SysUtils.pas', nil));
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TTypeKindRequiredRule.Create, ASource, SystemIndex, '', 'Typarten.pas');
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TTypeKindRequiredRule.Create, ASource, SystemIndex, AConfig, APath);
end;

function Apply(const AText: string; const AFix: TRuleFix): string;
begin
  Result := TChangeSignature.ApplyEdits(AText, AFix.Edits);
end;

/// <summary>Unit mit Record TPunkt, Klasse TKunde, Aufzählung TFarbe und Zeiger PZahl; AStatements im Rumpf von Fall
/// (ab Zeile 21, nullbasiert), AUses nach interface (z. B. 'uses SysUtils;').</summary>
function Typarten(const AUses, AStatements: string): string;
begin
  Result := Lines(['unit Typarten;', 'interface', AUses, 'type', '  TPunkt = record', '    X, Y: Integer;',
    '  end;', '  TKunde = class', '  public', '    Name: string;', '  end;', '  TFarbe = (Rot, Gruen);',
    '  PZahl = ^Integer;', 'implementation', 'procedure Fall(AKunde: TKunde; AFarbe: TFarbe; AZeiger: PZahl);',
    'var', '  mZahl: Integer;', '  mZeichen: Char;', '  mWert: Double;', '  mPunkt: TPunkt;', 'begin']) +
    AStatements + Lines(['end;', 'end.']);
end;

procedure TTypeKindRequiredTests.IndexDereferenceMemberAndWith;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Typarten('', Lines(['  mZahl[1] := 0;', '  mZahl^ := 0;', '  mZahl.Wert := 0;',
    '  with mZahl do', '    ;', '  mZeichen[1] := ''a'';', '  AFarbe^ := Rot;', '  mWert.X := 1;'])));
  Assert.AreEqual(7, Integer(Length(mFound)));
  Assert.AreEqual(TypeKindRequiredRuleId, mFound[0].RuleId);
  Assert.AreEqual('mZahl ist eine Ganzzahl (Integer), kein Array; ein Index ist hier nicht möglich (wie E2016).',
    mFound[0].Message);
  Assert.AreEqual(21, mFound[0].Range.StartPos.Line);
  Assert.AreEqual('mZahl ist eine Ganzzahl (Integer), kein Zeiger; ^ ist hier nicht möglich (wie E2017).',
    mFound[1].Message);
  Assert.AreEqual(0, Integer(Length(mFound[1].Fixes)));
  Assert.AreEqual('mZahl ist eine Ganzzahl (Integer), kein Record, keine Klasse und kein object-Typ; .Wert ist hier ' +
    'nicht möglich (wie E2018).', mFound[2].Message);
  Assert.AreEqual('with braucht einen Record, eine Klasse oder einen object-Typ; mZahl ist eine Ganzzahl (Integer) ' +
    '(wie E2018).', mFound[3].Message);
  Assert.AreEqual('mZeichen ist ein Zeichen (Char), kein Array; ein Index ist hier nicht möglich (wie E2016).',
    mFound[4].Message);
  Assert.AreEqual('AFarbe ist eine Aufzählung (TFarbe), kein Zeiger; ^ ist hier nicht möglich (wie E2017).',
    mFound[5].Message);
  Assert.AreEqual('mWert ist eine Gleitkommazahl (Double), kein Record, keine Klasse und kein object-Typ; .X ist ' +
    'hier nicht möglich (wie E2018).', mFound[6].Message);
end;

procedure TTypeKindRequiredTests.DereferenceFixForClassesAndRecords;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Typarten('', Lines(['  AKunde^.Name := ''A'';', '  mPunkt^.X := 1;', '  AKunde^ := nil;']));
  mFound := Findings(mSource);
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual('AKunde ist eine Klasse (TKunde), kein Zeiger; ^ ist hier nicht möglich (wie E2017).',
    mFound[0].Message);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('^ entfernen', mFound[0].Fixes[0].Title);
  Assert.IsTrue(mFound[0].Fixes[0].Safe);
  mFixed := Apply(mSource, mFound[0].Fixes[0]);
  Assert.AreEqual(Typarten('', Lines(['  AKunde.Name := ''A'';', '  mPunkt^.X := 1;', '  AKunde^ := nil;'])), mFixed);
  Assert.AreEqual('mPunkt ist ein Record (TPunkt), kein Zeiger; ^ ist hier nicht möglich (wie E2017).',
    mFound[1].Message);
  Assert.AreEqual(1, Integer(Length(mFound[1].Fixes)));
  // Ohne Punkt danach ändert das Entfernen die Bedeutung: keine Korrektur.
  Assert.AreEqual(0, Integer(Length(mFound[2].Fixes)));
end;

procedure TTypeKindRequiredTests.ValidAccessIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(Findings(Typarten('', Lines(['  AZeiger^ := 1;', '  mPunkt.X := 1;',
    '  AKunde.Name := ''A'';', '  AFarbe := TFarbe.Rot;', '  with mPunkt do', '    X := 2;', '  with AKunde do',
    '    Name := ''B'';', '  mZahl := Length(AKunde.Name);', '  mZeichen := AKunde.Name[1];',
    '  Unbekannt[1] := 0;', '  Unbekannt^ := 0;', '  Unbekannt.X := 0;']))))));
end;

procedure TTypeKindRequiredTests.HelpersAndUnknownUnitsAreSilent;
begin
  // Mit Helfer meldet dcc bei unbekanntem Mitglied E2003, nicht E2018.
  Assert.AreEqual(0, Integer(Length(Findings(Typarten('uses SysUtils;', Lines(['  AKunde.Name := mZahl.ToString;',
    '  mZahl.Wert := 0;']))))));
  // Eine Unit außerhalb des Index könnte einen Helfer bringen.
  Assert.AreEqual(0, Integer(Length(Findings(Typarten('uses Fremd;', Lines(['  mZahl.Wert := 0;',
    '  mZahl[1] := 0;']))))));
  // Helfer für den Alias, mit dem der Wert deklariert ist.
  Assert.AreEqual(0, Integer(Length(Findings(Lines(['unit Alias;', 'interface', 'type', '  TZahl = Integer;',
    '  TZahlHelfer = record helper for TZahl', '    function Doppelt: Integer;', '  end;', 'implementation',
    'function TZahlHelfer.Doppelt: Integer;', 'begin', '  Result := 2 * Self;', 'end;', 'procedure Fall;', 'var',
    '  mWert: TZahl;', 'begin', '  mWert := mWert.Wert;', 'end;', 'end.'])))));
  // Ohne Helfer bleibt E2018.
  Assert.AreEqual(1, Integer(Length(Findings(Typarten('uses SysUtils;', Lines(['  mWert.X := 1;']))))));
end;

procedure TTypeKindRequiredTests.AncestorsOfObjectClassAndHelper;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Lines(['unit Vorfahren;', 'interface', 'type', '  TRec = record', '    Wert: Integer;', '  end;',
    '  TAltObjekt = object(TObject)', '  end;', '  TKlasse = class(TRec)', '  end;', '  TMeta = class(TClass)',
    '  end;', '  TZahlKlasse = class(Integer)', '  end;', '  THelfer = class helper(TObject) for TObject', '  end;',
    '  TRecHelfer = record helper for TObject', '  end;', 'implementation', 'end.']));
  Assert.AreEqual(6, Integer(Length(mFound)));
  Assert.AreEqual('Der Vorfahr eines object-Typs muss ein object-Typ sein; TObject ist eine Klasse (wie E2019).',
    mFound[0].Message);
  Assert.AreEqual(6, mFound[0].Range.StartPos.Line);
  Assert.AreEqual('Der Vorfahr einer Klasse muss eine Klasse sein; TRec ist ein Record (wie E2021).',
    mFound[1].Message);
  Assert.AreEqual('Der Vorfahr einer Klasse muss eine Klasse sein; TClass ist eine Klassenreferenz (wie E2021).',
    mFound[2].Message);
  Assert.AreEqual('Der Vorfahr einer Klasse muss eine Klasse sein; Integer ist eine Ganzzahl (wie E2021).',
    mFound[3].Message);
  Assert.AreEqual('Der Vorfahr eines Class-Helpers muss ein Class-Helper sein; TObject ist eine Klasse ' +
    '(wie E2022).', mFound[4].Message);
  Assert.AreEqual('Ein Record-Helper braucht einen Record oder einfachen Typ; TObject ist eine Klasse, dafür gibt ' +
    'es class helper (wie E2474).', mFound[5].Message);
end;

procedure TTypeKindRequiredTests.ValidAncestorsAreSilent;
begin
  Assert.AreEqual(0, Integer(Length(Findings(Lines(['unit Vorfahren;', 'interface', 'type', '  IFoo = interface',
    '  end;', '  TRec = record', '    Wert: Integer;', '  end;', '  TAltBasis = object', '  end;',
    '  TAltObjekt = object(TAltBasis)', '  end;', '  TBasis = class', '  end;', '  TKlasse = class(TBasis, IFoo)',
    '  end;', '  TNurInterface = class(IFoo)', '  end;', '  TUnbekannt = class(TFremd)', '  end;',
    '  TBasisHelfer = class helper for TObject', '  end;', '  THelfer = class helper(TBasisHelfer) for TBasis',
    '  end;', '  TZahlHelfer = record helper for Integer', '  end;', '  TRecHelfer = record helper for TRec',
    '  end;', 'implementation', 'end.'])))));
end;

procedure TTypeKindRequiredTests.ConstructorFormsAndTypeOf;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Typarten('', Lines(['  New(AZeiger, Init);', '  Dispose(AZeiger, Done);',
    '  AZeiger := TypeOf(mZahl);'])));
  Assert.AreEqual(3, Integer(Length(mFound)));
  Assert.AreEqual('New mit Konstruktor braucht einen Zeiger auf einen Record oder object-Typ; AZeiger zeigt auf ' +
    'Integer (wie E2467).', mFound[0].Message);
  Assert.AreEqual('Dispose mit Destruktor braucht einen Zeiger auf einen object-Typ; AZeiger zeigt auf Integer ' +
    '(wie E2019).', mFound[1].Message);
  Assert.AreEqual('TypeOf braucht einen object-Typ mit VMT; mZahl ist eine Ganzzahl (Integer) (wie E2019).',
    mFound[2].Message);
  // PInteger aus System und Zeiger ohne Alias.
  mFound := Findings(Lines(['unit Zeiger;', 'interface', 'implementation', 'procedure Fall;', 'var',
    '  mZeiger: PInteger;', '  mDirekt: ^Byte;', 'begin', '  New(mZeiger, Init);', '  Dispose(mDirekt, Done);', 'end;',
    'end.']));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Dispose mit Destruktor braucht einen Zeiger auf einen object-Typ; mDirekt zeigt auf Byte ' +
    '(wie E2019).', mFound[1].Message);
  // Gegenfälle: einfache Formen, object-Typen, eigene Routine New.
  Assert.AreEqual(0, Integer(Length(Findings(Typarten('', Lines(['  New(AZeiger);', '  Dispose(AZeiger);',
    '  AZeiger := TypeOf(AKunde);']))))));
  Assert.AreEqual(0, Integer(Length(Findings(Lines(['unit Alt;', 'interface', 'type', '  TAlt = object',
    '    constructor Init;', '    destructor Done;', '  end;', '  PAlt = ^TAlt;', 'implementation',
    'constructor TAlt.Init;', 'begin', 'end;', 'destructor TAlt.Done;', 'begin', 'end;',
    'procedure New(var P: PInteger; X: Integer);', 'begin', 'end;', 'procedure Fall;', 'var', '  mAlt: PAlt;',
    '  mZeiger: PInteger;', 'begin', '  System.New(mAlt, Init);', '  Dispose(mAlt, Done);', '  New(mZeiger, 1);',
    'end;', 'end.'])))));
end;

/// <summary>TBasis mit Machen, class procedure Klasse und Konstruktor; ARest nach der Klassendeklaration (ab Zeile 9, nullbasiert).
/// </summary>
function Basis(const ARest: string): string;
begin
  Result := Lines(['unit Basis;', 'interface', 'type', '  TBasis = class', '  public', '    procedure Machen;',
    '    class procedure Klasse;', '    constructor Create;', '  end;']) + ARest + Lines(['implementation',
    'procedure TBasis.Machen;', 'begin', 'end;', 'class procedure TBasis.Klasse;', 'begin', 'end;',
    'constructor TBasis.Create;', 'begin', 'end;']);
end;

procedure TTypeKindRequiredTests.ClassMethodForm;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Basis(Lines(['  TAndere = class', '  public', '    procedure Rufen;', '  end;'])) +
    Lines(['procedure TAndere.Rufen;', 'begin', '  TBasis.Machen;', 'end;', 'procedure Fall;', 'begin',
    '  TBasis.Machen();', 'end;', 'end.']));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Machen ist keine Klassenmethode; TBasis.Machen geht nur in Methoden von TBasis und seinen ' +
    'Nachfahren (wie E2076).', mFound[0].Message);
  Assert.AreEqual(25, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(29, mFound[1].Range.StartPos.Line);
end;

procedure TTypeKindRequiredTests.ClassMethodFormInMethodsIsSilent;
begin
  Assert.AreEqual(0, Integer(Length(Findings(Basis(Lines(['  TKind = class(TBasis)', '  public',
    '    procedure Rufen;', '  end;'])) + Lines(['procedure TKind.Rufen;', '  procedure Innen;', '  begin',
    '    TBasis.Machen;', '  end;', 'var', '  mZeiger: Pointer;', 'begin', '  TBasis.Machen;', '  Innen;', 'end;',
    'procedure Fall;', 'var', '  mBasis: TBasis;', '  mZeiger: Pointer;', 'begin', '  TBasis.Klasse;',
    '  mBasis := TBasis.Create;', '  mBasis.Machen;', '  mZeiger := @TBasis.Machen;', 'end;', 'end.'])))));
end;

/// <summary>Routinen mit offenem Array, Integer und array of const; AStatements im Rumpf von Fall (ab Zeile 35, nullbasiert).
/// </summary>
function Felder(const AUses, AStatements: string): string;
begin
  Result := Lines(['unit Felder;', 'interface', AUses, 'type', '  TPunkt = record', '    X, Y: Integer;', '  end;',
    '  TWert = record', '    class operator Implicit(const A: TWert): Integer;', '  end;', 'implementation',
    'class operator TWert.Implicit(const A: TWert): Integer;', 'begin', '  Result := 0;', 'end;',
    'procedure Offen(const A: array of Integer);', 'begin', 'end;', 'procedure Zahl(A: Integer);', 'begin', 'end;',
    'procedure Nimm(const A: array of const);', 'begin', 'end;', 'procedure Fall;', 'var',
    '  mQuelle: array[0..3] of Integer;', '  mZiel: array of Integer;', '  mPunkt: TPunkt;', '  mWert: TWert;',
    '  mObjekt: TObject;', '  mZahl: Integer;', '  mDatei: file of TPunkt;', '  mText: TextFile;', 'begin']) +
    AStatements + Lines(['end;', 'end.']);
end;

procedure TTypeKindRequiredTests.SliceOutsideOpenArray;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Felder('', Lines(['  mZiel := Slice(mQuelle, 2);', '  Zahl(Slice(mQuelle, 2));'])));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('Slice ist nur als Argument für einen offenen Array-Parameter möglich (wie E2193).',
    mFound[0].Message);
  Assert.AreEqual(36, mFound[1].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Findings(Felder('', Lines(['  Offen(Slice(mQuelle, 2));',
    '  Unbekannt(Slice(mQuelle, 2));']))))));
end;

procedure TTypeKindRequiredTests.RecordInArrayOfConst;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(Felder('uses SysUtils;', Lines(['  Nimm([mPunkt]);', '  Ausgeben(''%d'', [mZahl, mPunkt]);'])));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual('mPunkt ist ein Record (TPunkt); array of const nimmt keine Records (wie E2150).',
    mFound[0].Message);
  Assert.AreEqual(36, mFound[1].Range.StartPos.Line);
  Assert.AreEqual(0, Integer(Length(Findings(Felder('', Lines(['  Nimm([mZahl, ''Text'', mObjekt, nil]);',
    '  Nimm([mWert]);', '  Offen([mZahl, 1]);']))))));
end;

procedure TTypeKindRequiredTests.WriteAndReadWithStructuredTypes;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Felder('', Lines(['  Writeln(ErrOutput, mObjekt);', '  Readln(mObjekt);', '  Write(mText, mPunkt);',
    '  Writeln(mPunkt);']));
  mFound := Findings(mSource);
  Assert.AreEqual(4, Integer(Length(mFound)));
  Assert.AreEqual('Writeln kann mObjekt nicht ausgeben: TObject ist eine Klasse (wie E2054).', mFound[0].Message);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('mObjekt.ToString', mFound[0].Fixes[0].Title);
  mFixed := Apply(mSource, mFound[0].Fixes[0]);
  Assert.AreEqual(Felder('', Lines(['  Writeln(ErrOutput, mObjekt.ToString);', '  Readln(mObjekt);',
    '  Write(mText, mPunkt);', '  Writeln(mPunkt);'])), mFixed);
  Assert.AreEqual('Readln kann mObjekt nicht einlesen: TObject ist eine Klasse (wie E2055).', mFound[1].Message);
  Assert.AreEqual('Write kann mPunkt nicht ausgeben: TPunkt ist ein Record (wie E2054).', mFound[2].Message);
  Assert.AreEqual(0, Integer(Length(mFound[2].Fixes)));
  Assert.AreEqual(38, mFound[3].Range.StartPos.Line);
end;

procedure TTypeKindRequiredTests.WriteAndReadSilentCases;
begin
  Assert.AreEqual(0, Integer(Length(Findings(Felder('', Lines(['  Writeln(mZahl, '' '', mZahl:4);',
    '  Write(mDatei, mPunkt);', '  Read(mDatei, mPunkt);', '  Writeln(mText, mZahl);', '  Writeln(mWert);',
    '  Writeln;', '  Write(Unbekannt, mPunkt);']))))));
  // Eigene Routine Writeln verdeckt die eingebaute.
  Assert.AreEqual(0, Integer(Length(Findings(Lines(['unit Eigen;', 'interface', 'implementation',
    'procedure Writeln(A: TObject);', 'begin', 'end;', 'procedure Fall;', 'var', '  mObjekt: TObject;', 'begin',
    '  Writeln(mObjekt);', 'end;', 'end.'])))));
end;

procedure TTypeKindRequiredTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := Typarten('', Lines(['  mZahl[1] := 0;']));
  Assert.AreEqual(1, Integer(Length(Findings(mSource, '', 'Source/Typarten.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"type-kind-required": "off"}}',
    'Source/Typarten.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"group:compiler": "off"}}',
    'Source/Typarten.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"group:compiler": {"typeLevel": "off"}}}',
    'Source/Typarten.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource,
    '{"rules": {"type-kind-required": {"exclude": ["Source/*.pas"]}}}', 'Source/Typarten.pas'))));
end;

procedure TTypeKindRequiredTests.GenericMethodCallIsNoDotOnResult;
begin
  Assert.AreEqual(0, Integer(Length(Findings('unit Typarten;'#10'interface'#10'type'#10'  TJson = class'#10 +
    '    function TryGetValue<T>(const AName: string; out AValue: T): Boolean;'#10'  end;'#10'implementation'#10 +
    'function TJson.TryGetValue<T>(const AName: string; out AValue: T): Boolean;'#10'begin'#10 +
    '  Result := False;'#10'end;'#10'procedure Lies(AJson: TObject);'#10'var'#10'  mZahl: Integer;'#10 +
    'begin'#10'  if TJson(AJson).TryGetValue<Integer>(''n'', mZahl) then'#10'    Exit;'#10'end;'#10'end.'))));
end;

procedure TTypeKindRequiredTests.RuleIsRegistered;
var
  mRule: IRule;
  mFound: Boolean;
begin
  mFound := False;
  for mRule in BuiltinRules do
    if mRule.Descriptor.Id = TypeKindRequiredRuleId then
      mFound := True;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TTypeKindRequiredTests);

end.
