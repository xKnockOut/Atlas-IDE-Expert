unit Atlas.Common.Rules.Builtin.TypeDeclarations.Tests;

// Tests der Regeln zur Deklaration von Klassen- und Interface-Mitgliedern:
// message-method-invalid (#1070): Beispiel aus dem Issue (E2140), gleiche
// Nummern über Werte und Ausdrücke, sich ausschließende {$IF}-Zweige,
// Parameterlisten mit Korrektur (E2138), Nummern unter 1 (E2139) und die
// Einstellungen.
// interface-declaration-invalid (#1075): Beispiel aus dem Issue (E2209),
// Sichtbarkeit und Direktiven (E2210), Property-Klauseln (E2207), Properties
// und Neudeklarationen ohne Typ (E2206), Klassen und Records
// als Interfaces und doppelte Einträge (E2205, E2208), stille Fälle und die
// Einstellungen.
// implements-clause-invalid (#1076): Beispiel aus dem Issue (E2261), Typ,
// index und Getter (E2259, E2260, E2262, E2263), doppelte Interfaces und
// Methodenzuordnungen (E2257, E2264), implements außerhalb von Klassen
// (E2258), stille Fälle und die Einstellungen.
// calling-convention-required (#1078): Beispiel aus dem Issue mit Korrektur
// (E2277), varargs ohne external (E2591), Konstruktoren und Destruktoren
// (E2236) und Accessoren von published-Properties (E2270) mit Korrektur in
// Deklaration und Rumpf, stille Fälle und die Einstellungen.
// dispinterface-invalid (#1374): die Fälle aus Tests/Compilermeldungen (E2228
// bis E2231) mit Position, die Korrekturen, Vorfahr und fehlende GUID
// zusammen, stille Fälle (Gegenfall Cm.E2228b) und die Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMessageMethodInvalidTests = class
  public
    [Test]
    procedure IssueExampleDuplicateNumber;
    [Test]
    procedure DuplicatesByValueAndText;
    [Test]
    procedure ExclusiveBranchesAreSilent;
    [Test]
    procedure ParameterListWithFixes;
    [Test]
    procedure NumberBelowOne;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TInterfaceDeclarationInvalidTests = class
  public
    [Test]
    procedure IssueExampleField;
    [Test]
    procedure VisibilityAndDirectives;
    [Test]
    procedure PropertyClauses;
    [Test]
    procedure InheritedPropertiesAndAccessors;
    [Test]
    procedure ClassesAsInterfacesAndDuplicates;
    [Test]
    procedure SilentCases;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TImplementsClauseInvalidTests = class
  public
    [Test]
    procedure IssueExampleWithoutRead;
    [Test]
    procedure TypeIndexAndGetter;
    [Test]
    procedure DuplicatesAndMethodResolutions;
    [Test]
    procedure OutsideOfClasses;
    [Test]
    procedure SilentCases;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TCallingConventionRequiredTests = class
  public
    [Test]
    procedure IssueExampleVarargsWithFix;
    [Test]
    procedure ConstructorsAndDestructors;
    [Test]
    procedure PublishedAccessors;
    [Test]
    procedure OffAndExclude;
  end;

  [TestFixture]
  TDispinterfaceInvalidTests = class
  public
    [Test]
    procedure IssueCasesWithPositions;
    [Test]
    procedure FixesRemoveAndInsert;
    [Test]
    procedure AncestorWithoutGuid;
    [Test]
    procedure SilentCases;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.TypeDeclarations,
  Atlas.Tests.RuleAssert;

/// <summary>Unit Messages mit einigen Nachrichtennummern und TMessage.</summary>
function MessagesIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit Messages;'#10'interface'#10'const'#10'  WM_NULL = $0000;'#10 +
    '  WM_MOVE = $0003;'#10'  WM_SIZE = $0005;'#10'  WM_USER = $0400;'#10'type'#10'  TMessage = record'#10 +
    '    Msg: Cardinal;'#10'  end;'#10'  TWMSize = TMessage;'#10'implementation'#10'end.',
    'C:\BDS\source\Messages.pas', nil));
end;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TMessageMethodInvalidRule.Create, ASource, MessagesIndex, '', 'Fenster.pas');
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TMessageMethodInvalidRule.Create, ASource, MessagesIndex, AConfig, APath);
end;

/// <summary>Unit Fenster mit TFenster: AMembers im private-Abschnitt, ABodies im implementation-Teil.</summary>
function Fenster(const AMembers, ABodies: string): string;
begin
  Result := 'unit Fenster;'#10'interface'#10'uses'#10'  Messages;'#10'type'#10'  TFenster = class'#10'  private'#10 +
    AMembers + '  end;'#10'implementation'#10 + ABodies + 'end.';
end;

function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  Line, Index: Integer;
begin
  Index := 1;
  for Line := 1 to APosition.Line do
  begin
    while (Index <= Length(AText)) and (AText[Index] <> #10) do
      Inc(Index);
    Inc(Index);
  end;
  Result := Index + APosition.Character;
end;

/// <summary>Wendet die Edits einer Korrektur von hinten nach vorn an.</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  Index, Start, Stop: Integer;
begin
  Result := AText;
  for Index := High(AFix.Edits) downto 0 do
  begin
    Start := OffsetOf(Result, AFix.Edits[Index].Range.StartPos);
    Stop := OffsetOf(Result, AFix.Edits[Index].Range.EndPos);
    Result := Copy(Result, 1, Start - 1) + AFix.Edits[Index].NewText + Copy(Result, Stop, MaxInt);
  end;
end;

{ TMessageMethodInvalidTests }

procedure TMessageMethodInvalidTests.IssueExampleDuplicateNumber;
var
  Found: TArray<TRuleFinding>;
  Line: string;
begin
  Line := '    procedure WMGroesse(var Msg: TWMSize); message WM_SIZE;';
  Found := Findings(Fenster('    procedure WMSize(var Msg: TWMSize); message WM_SIZE;'#10 + Line + #10, ''));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('WM_SIZE wird schon von WMSize behandelt (wie E2140).', Found[0].Message);
  Assert.AreEqual(Integer(Ord(TRuleSeverity.Error)), Integer(Ord(Found[0].Severity)));
  Assert.AreEqual(8, Found[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('WM_SIZE', Line) - 1, Found[0].Range.StartPos.Character);
  Assert.AreEqual(Pos('WM_SIZE', Line) + 6, Found[0].Range.EndPos.Character);
  // Korrigierte Form: eigene Nummer.
  Assert.AreEqual(0, Integer(Length(Findings(Fenster('    procedure WMSize(var Msg: TWMSize); message WM_SIZE;'#10 +
    '    procedure WMMove(var Msg: TMessage); message WM_MOVE;'#10, '')))));
end;

procedure TMessageMethodInvalidTests.DuplicatesByValueAndText;
var
  Found: TArray<TRuleFinding>;
begin
  // Gleicher Wert über eine Zahl, gleicher Ausdruck mit unbekanntem Namen.
  Found := Findings(Fenster('    procedure A(var M: TMessage); message WM_SIZE;'#10 +
    '    procedure B(var M: TMessage); message $0005;'#10 +
    '    procedure C(var M: TMessage); message CM_BASE + 1;'#10 +
    '    procedure D(var M: TMessage); message CM_BASE+1;'#10 +
    '    procedure E(var M: TMessage); message WM_USER + 1;'#10 +
    '    procedure F(var M: TMessage); message CM_BASE + 2;'#10, ''));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('$0005 wird schon von A behandelt (wie E2140).', Found[0].Message);
  Assert.AreEqual('CM_BASE+1 wird schon von C behandelt (wie E2140).', Found[1].Message);
  // Dieselbe Nummer in zwei Klassen ist erlaubt; ebenso wie im Vorfahren (Überschreiben).
  Assert.AreEqual(0, Integer(Length(Findings(Fenster('    procedure A(var M: TMessage); message WM_SIZE;'#10 +
    '  end;'#10'  TKind = class(TFenster)'#10'    procedure A(var M: TMessage); message WM_SIZE;'#10, '')))));
  // Verschachtelte Klasse zählt für sich.
  Assert.AreEqual(0, Integer(Length(Findings(Fenster('    type'#10'      TInnen = class'#10 +
    '        procedure A(var M: TMessage); message WM_SIZE;'#10'      end;'#10'    private'#10 +
    '    procedure A(var M: TMessage); message WM_SIZE;'#10, '')))));
end;

procedure TMessageMethodInvalidTests.ExclusiveBranchesAreSilent;
var
  Members: string;
begin
  Members := '  {$IFDEF ALT}'#10'    procedure A(var M: TMessage); message WM_SIZE;'#10'  {$ELSE}'#10 +
    '    procedure B(var M: TMessage); message WM_SIZE;'#10'  {$ENDIF}'#10;
  Assert.AreEqual(0, Integer(Length(Findings(Fenster(Members, '')))));
  // Außerhalb der Bedingung wird die zweite immer mit übersetzt.
  Assert.AreEqual(1, Integer(Length(Findings(Fenster(Members +
    '    procedure C(var M: TMessage); message WM_SIZE;'#10, '')))));
end;

procedure TMessageMethodInvalidTests.ParameterListWithFixes;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Fenster('    procedure WMA(Msg: TMessage); message 10;'#10 +
    '    procedure WMB(var A, B: Integer); message 11;'#10'    procedure WMC; message 12;'#10 +
    '    procedure WMD(const Msg: TMessage); message 13;'#10'    procedure WME(var Msg); message 14;'#10 +
    '    function WMF(var Msg: TMessage): Integer; message 15;'#10'    procedure WMG(var Msg: TMessage); message 16;'#10,
    'procedure TFenster.WMA(Msg: TMessage);'#10'begin'#10'end;'#10#10 +
    'procedure TFenster.WMB(var A, B: Integer);'#10'begin'#10'end;'#10#10 +
    'procedure TFenster.WMC;'#10'begin'#10'end;'#10#10);
  Found := Findings(Source);
  Assert.AreEqual(4, Integer(Length(Found)));
  Assert.AreEqual('Die message-Methode WMA braucht genau einen var-Parameter (wie E2138).', Found[0].Message);
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual(14, Found[0].Range.StartPos.Character);
  Assert.AreEqual(17, Found[0].Range.EndPos.Character);
  Assert.AreEqual('Parameter Msg als var übergeben', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('procedure WMA(var Msg: TMessage); message 10;', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('procedure TFenster.WMA(var Msg: TMessage);', Fixed) > 0, Fixed);
  Assert.AreEqual('Die message-Methode WMB braucht genau einen var-Parameter (wie E2138).', Found[1].Message);
  Assert.AreEqual('Signatur (var Msg: TMessage) einsetzen', Found[1].Fixes[0].Title);
  Fixed := ApplyFix(Fixed, Findings(Fixed)[0].Fixes[0]);
  Assert.IsTrue(Pos('procedure WMB(var Msg: TMessage); message 11;', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('procedure TFenster.WMB(var Msg: TMessage);', Fixed) > 0, Fixed);
  Fixed := ApplyFix(Fixed, Findings(Fixed)[0].Fixes[0]);
  // Der Rumpf ohne Parameterliste bleibt.
  Assert.IsTrue(Pos('procedure WMC(var Msg: TMessage); message 12;', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('procedure TFenster.WMC;', Fixed) > 0, Fixed);
  Fixed := ApplyFix(Fixed, Findings(Fixed)[0].Fixes[0]);
  Assert.IsTrue(Pos('procedure WMD(var Msg: TMessage); message 13;', Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(Findings(Fixed))), Fixed);
end;

procedure TMessageMethodInvalidTests.NumberBelowOne;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Fenster('    procedure A(var M: TMessage); message 0;'#10 +
    '    procedure B(var M: TMessage); message -151;'#10'    procedure C(var M: TMessage); message WM_NULL;'#10 +
    '    procedure D(var M: TMessage); message 151;'#10'    procedure E(var M: TMessage); message WM_USER - 1;'#10,
    ''));
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('Die Nachrichtennummer 0 von A muss mindestens 1 sein (wie E2139).', Found[0].Message);
  Assert.AreEqual('Die Nachrichtennummer -151 von B muss mindestens 1 sein (wie E2139).', Found[1].Message);
  Assert.AreEqual('Die Nachrichtennummer WM_NULL von C muss mindestens 1 sein (wie E2139).', Found[2].Message);
end;

procedure TMessageMethodInvalidTests.OffAndExclude;
var
  Source: string;
begin
  Source := Fenster('    procedure A(var M: TMessage); message WM_SIZE;'#10 +
    '    procedure B(var M: TMessage); message WM_SIZE;'#10, '');
  Assert.AreEqual(1, Integer(Length(Findings(Source, '', 'Source/Fenster.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"message-method-invalid": "off"}}',
    'Source/Fenster.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:compiler": "off"}}', 'Source/Fenster.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"message-method-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Fenster.pas'))));
end;

{ TInterfaceDeclarationInvalidTests }

/// <summary>System mit TObject, IInterface und TInterfacedObject; Unit Basis mit IBasis (Property Name über
/// GetName), TKlasse, TPunkt (Record), TFarbe (Aufzählung) und dem Alias TAlias.</summary>
function BasisIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText('unit System;'#10'interface'#10'type'#10'  TObject = class'#10 +
    '  end;'#10'  IInterface = interface'#10'    function _AddRef: Integer; stdcall;'#10'  end;'#10 +
    '  TInterfacedObject = class(TObject, IInterface)'#10'    function _AddRef: Integer; stdcall;'#10'  end;'#10 +
    'implementation'#10'end.', 'C:\BDS\source\System.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText('unit Basis;'#10'interface'#10'type'#10'  IBasis = interface'#10 +
    '    function GetName: string;'#10'    property Name: string read GetName;'#10'  end;'#10 +
    '  TKlasse = class'#10'  end;'#10'  TPunkt = record'#10'    X: Integer;'#10'  end;'#10 +
    '  TFarbe = (fRot, fBlau);'#10'  TAlias = IBasis;'#10'implementation'#10'end.', 'C:\Projekt\Basis.pas', nil));
end;

function InterfaceFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TInterfaceDeclarationInvalidRule.Create, ASource, BasisIndex, '', 'Kunden.pas');
end;

function InterfaceFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TInterfaceDeclarationInvalidRule.Create, ASource, BasisIndex, AConfig, APath);
end;

/// <summary>Unit Kunden, die Basis einbindet, mit den Typen ATypes.</summary>
function Kunden(const ATypes: string): string;
begin
  Result := 'unit Kunden;'#10'interface'#10'uses'#10'  Basis;'#10'type'#10 + ATypes + 'implementation'#10'end.';
end;

procedure TInterfaceDeclarationInvalidTests.IssueExampleField;
var
  Found: TArray<TRuleFinding>;
begin
  Found := InterfaceFindings(Kunden('  IKunde = interface'#10'    FName: string;'#10'    function GetName: string;'#10 +
    '  end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Interfaces dürfen keine Felder haben (wie E2209).', Found[0].Message);
  Assert.AreEqual(Integer(Ord(TRuleSeverity.Error)), Integer(Ord(Found[0].Severity)));
  Assert.AreEqual(6, Found[0].Range.StartPos.Line);
  Assert.AreEqual(4, Found[0].Range.StartPos.Character);
  Assert.AreEqual(9, Found[0].Range.EndPos.Character);
  // Korrigierte Form und Felder einer Klasse.
  Assert.AreEqual(0, Integer(Length(InterfaceFindings(Kunden('  IKunde = interface'#10 +
    '    function GetName: string;'#10'  end;'#10'  TKunde = class'#10'    FName: string;'#10'  end;'#10)))));
  Found := InterfaceFindings(Kunden('  IKunde = interface'#10'    class var Zaehler: Integer;'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(6, Found[0].Range.StartPos.Line);
end;

procedure TInterfaceDeclarationInvalidTests.VisibilityAndDirectives;
var
  Found: TArray<TRuleFinding>;
begin
  Found := InterfaceFindings(Kunden('  IKunde = interface'#10'  private'#10'    procedure A; virtual;'#10 +
    '    procedure B; stdcall;'#10'    function C: Integer; safecall;'#10'    procedure D; overload;'#10 +
    '    procedure D(X: Integer); overload; abstract;'#10'  end;'#10));
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('Die Direktive private ist in Interfaces nicht erlaubt (wie E2210).', Found[0].Message);
  Assert.AreEqual(6, Found[0].Range.StartPos.Line);
  Assert.AreEqual('Die Direktive virtual ist in Interfaces nicht erlaubt (wie E2210).', Found[1].Message);
  Assert.AreEqual(7, Found[1].Range.StartPos.Line);
  Assert.AreEqual(17, Found[1].Range.StartPos.Character);
  Assert.AreEqual(24, Found[1].Range.EndPos.Character);
  Assert.AreEqual('Die Direktive abstract ist in Interfaces nicht erlaubt (wie E2210).', Found[2].Message);
end;

procedure TInterfaceDeclarationInvalidTests.PropertyClauses;
var
  Found: TArray<TRuleFinding>;
begin
  Found := InterfaceFindings(Kunden('  IKunde = interface'#10'    function GetX: Integer;'#10 +
    '    procedure SetX(V: Integer);'#10'    function GetItem(I: Integer): Integer;'#10 +
    '    property X: Integer read GetX write SetX stored False;'#10'    property Y: Integer read GetX default 0;'#10 +
    '    property Z: Integer read GetX nodefault;'#10 +
    '    property Items[I: Integer]: Integer read GetItem; default;'#10 +
    '    property Default: Integer read GetX;'#10'    property Stored: Integer read GetX;'#10'  end;'#10));
  Assert.AreEqual(3, Integer(Length(Found)));
  Assert.AreEqual('Die Klausel stored ist in Interfaces nicht erlaubt (wie E2207).', Found[0].Message);
  Assert.AreEqual(9, Found[0].Range.StartPos.Line);
  Assert.AreEqual(45, Found[0].Range.StartPos.Character);
  Assert.AreEqual('Die Klausel default ist in Interfaces nicht erlaubt (wie E2207).', Found[1].Message);
  Assert.AreEqual('Die Klausel nodefault ist in Interfaces nicht erlaubt (wie E2207).', Found[2].Message);
  // In einer Klasse sind die Klauseln erlaubt.
  Assert.AreEqual(0, Integer(Length(InterfaceFindings(Kunden('  TKunde = class'#10'    function GetX: Integer;'#10 +
    '  published'#10'    property X: Integer read GetX stored False default 0;'#10'  end;'#10)))));
end;

procedure TInterfaceDeclarationInvalidTests.InheritedPropertiesAndAccessors;
var
  Found: TArray<TRuleFinding>;
begin
  Found := InterfaceFindings(Kunden('  IKunde = interface(IBasis)'#10'    property Name;'#10 +
    '    property Titel: string read GetName;'#10'  end;'#10));
  // Titel mit dem geerbten Getter GetName übersetzt dcc (ID3, #1328).
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Die Property Name ist schon in IBasis deklariert; Interfaces dürfen Properties nicht ' +
    'ohne Typ neu aufführen (wie E2206).', Found[0].Message);
  Assert.AreEqual(6, Found[0].Range.StartPos.Line);
  Assert.AreEqual(13, Found[0].Range.StartPos.Character);
  // Eigener Accessor und neuer Name: still.
  Assert.AreEqual(0, Integer(Length(InterfaceFindings(Kunden('  IKunde = interface(IBasis)'#10 +
    '    function GetTitel: string;'#10'    property Titel: string read GetTitel;'#10'  end;'#10)))));
  // Neudeklaration mit Typ und eigenem Accessor übersetzt dcc (DUnitX, JCL, Spring4D; #1328).
  Assert.AreEqual(0, Integer(Length(InterfaceFindings(Kunden('  IKunde = interface(IBasis)'#10 +
    '    procedure SetName(const AName: string);'#10'    function GetName: string;'#10 +
    '    property Name: string read GetName write SetName;'#10'  end;'#10)))));
  // Geerbter Accessor übersetzt dcc, generisch (DUnitX IList<T>, ID2) wie nicht generisch (ID1; #1328).
  Assert.AreEqual(0, Integer(Length(InterfaceFindings(Kunden('  IKunde = interface(IBasis)'#10 +
    '    procedure SetName(const AName: string);'#10'    property Name: string read GetName write SetName;'#10 +
    '  end;'#10)))));
  Assert.AreEqual(0, Integer(Length(InterfaceFindings(Kunden('  IListe<T> = interface'#10 +
    '    function GetAnzahl: Integer;'#10'    property Anzahl: Integer read GetAnzahl;'#10'  end;'#10 +
    '  IVoll<T> = interface(IListe<T>)'#10'    procedure SetAnzahl(AWert: Integer);'#10 +
    '    property Anzahl: Integer read GetAnzahl write SetAnzahl;'#10'  end;'#10)))));
  // Ohne Typ über zwei Stufen in derselben Unit.
  Found := InterfaceFindings(Kunden('  IMitte = interface(IBasis)'#10'  end;'#10 +
    '  IKunde = interface(IMitte)'#10'    property Name;'#10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('Die Property Name ist schon in IBasis deklariert; Interfaces dürfen Properties nicht ' +
    'ohne Typ neu aufführen (wie E2206).', Found[0].Message);
end;

procedure TInterfaceDeclarationInvalidTests.ClassesAsInterfacesAndDuplicates;
var
  Found: TArray<TRuleFinding>;
begin
  Found := InterfaceFindings(Kunden('  IFalsch = interface(TKlasse)'#10'  end;'#10 +
    '  TDienst = class(TInterfacedObject, TPunkt, IBasis, TFarbe, Basis.IBasis)'#10'  end;'#10));
  Assert.AreEqual(4, Integer(Length(Found)));
  Assert.AreEqual('TKlasse ist eine Klasse und kein Interface (wie E2205).', Found[0].Message);
  Assert.AreEqual(5, Found[0].Range.StartPos.Line);
  Assert.AreEqual(22, Found[0].Range.StartPos.Character);
  Assert.AreEqual('TPunkt ist ein Record und kein Interface (wie E2205).', Found[1].Message);
  Assert.AreEqual('TFarbe ist eine Aufzählung und kein Interface (wie E2205).', Found[2].Message);
  Assert.AreEqual('Basis.IBasis steht schon in der Liste der Interfaces (wie E2208).', Found[3].Message);
  Assert.AreEqual(7, Found[3].Range.StartPos.Line);
end;

procedure TInterfaceDeclarationInvalidTests.SilentCases;
begin
  // Alias, unbekannter Typ, erster Eintrag einer Klasse, bedingte Zweige, dispinterface.
  Assert.AreEqual(0, Integer(Length(InterfaceFindings(Kunden('  IKunde = interface(TAlias)'#10'  end;'#10 +
    '  IAnders = interface(IUnbekannt)'#10'  end;'#10'  TDienst = class(TKlasse, TAlias, IUnbekannt)'#10'  end;'#10 +
    '  ISchalter = interface'#10'  {$IFDEF ALT}'#10'    FAlt: Integer;'#10'  {$ENDIF}'#10'  end;'#10 +
    '  IDisp = dispinterface'#10'    [''{00000000-0000-0000-0000-000000000001}'']'#10 +
    '    property Wert: Integer readonly dispid 1;'#10'  end;'#10)))));
end;

procedure TInterfaceDeclarationInvalidTests.OffAndExclude;
var
  Source: string;
begin
  Source := Kunden('  IKunde = interface'#10'    FName: string;'#10'  end;'#10);
  Assert.AreEqual(1, Integer(Length(InterfaceFindings(Source, '', 'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(InterfaceFindings(Source, '{"rules": {"interface-declaration-invalid": "off"}}',
    'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(InterfaceFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(InterfaceFindings(Source,
    '{"rules": {"interface-declaration-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Kunden.pas'))));
end;

{ TImplementsClauseInvalidTests }

/// <summary>Meldungen der Treffer, eine je Zeile (für Fehlermeldungen der Tests).</summary>
function Messages(const AFound: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFound do
    Result := Result + Finding.Message + #10;
end;

function ImplementsFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TImplementsClauseInvalidRule.Create, ASource, BasisIndex, '', 'Kunden.pas');
end;

function ImplementsFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.IndexFindings(TImplementsClauseInvalidRule.Create, ASource, BasisIndex, AConfig, APath);
end;

/// <summary>Unit Kunden mit den Interfaces IA bis ID und TDienst (TInterfacedObject, AList) mit AMembers.</summary>
function Dienst(const AList, AMembers: string): string;
begin
  Result := Kunden('  IA = interface'#10'  end;'#10'  IB = interface'#10'  end;'#10'  IC = interface'#10'  end;'#10 +
    '  ID = interface'#10'  end;'#10'  TDienst = class(TInterfacedObject, ' + AList + ')'#10 + AMembers + '  end;'#10);
end;

procedure TImplementsClauseInvalidTests.IssueExampleWithoutRead;
var
  Found: TArray<TRuleFinding>;
  Line: string;
begin
  Line := '    property Basis: IBasis write FBasis implements IBasis;';
  Found := ImplementsFindings(Kunden('  TDienst = class(TInterfacedObject, IBasis)'#10'    FBasis: IBasis;'#10 +
    Line + #10'  end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('implements braucht eine lesbare Property (wie E2261).', Found[0].Message);
  Assert.AreEqual(Integer(Ord(TRuleSeverity.Error)), Integer(Ord(Found[0].Severity)));
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('implements', Line) - 1, Found[0].Range.StartPos.Character);
  // Korrigierte Form.
  Assert.AreEqual(0, Integer(Length(ImplementsFindings(Kunden('  TDienst = class(TInterfacedObject, IBasis)'#10 +
    '    FBasis: IBasis;'#10'    property Basis: IBasis read FBasis write FBasis implements IBasis;'#10 +
    '  end;'#10)))));
end;

procedure TImplementsClauseInvalidTests.TypeIndexAndGetter;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ImplementsFindings(Dienst('IA, IB, IC, ID', '    FZahl: Integer;'#10'    FPunkt: TPunkt;'#10 +
    '    function GetB: IB; cdecl;'#10'    function GetC(I: Integer): IC;'#10'    function GetD: ID; dynamic;'#10 +
    '    property Zahl: Integer read FZahl implements IA;'#10'    property B: IB read GetB implements IB;'#10 +
    '    property C: IC index 1 read GetC implements IC;'#10'    property D: ID read GetD implements ID;'#10 +
    '    property Punkt: TPunkt read FPunkt implements IBasis;'#10));
  Assert.AreEqual(5, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual('implements ist nur an Properties mit Klassen- oder Interface-Typ erlaubt, Integer ist keiner ' +
    '(wie E2259).', Found[0].Message);
  Assert.AreEqual(19, Found[0].Range.StartPos.Line);
  Assert.AreEqual(19, Found[0].Range.StartPos.Character);
  Assert.AreEqual('Der Getter GetB einer implements-Property darf nicht cdecl sein, nur register (wie E2262).',
    Found[1].Message);
  Assert.AreEqual(20, Found[1].Range.StartPos.Line);
  Assert.AreEqual('implements ist nicht zusammen mit index erlaubt (wie E2260).', Found[2].Message);
  Assert.AreEqual('Der Getter GetD einer implements-Property darf nicht dynamic sein (wie E2263 und E2148).', Found[3].Message);
  // Record als Typ.
  Assert.AreEqual('implements ist nur an Properties mit Klassen- oder Interface-Typ erlaubt, TPunkt ist keiner ' +
    '(wie E2259).', Found[4].Message);
end;

procedure TImplementsClauseInvalidTests.DuplicatesAndMethodResolutions;
var
  Found: TArray<TRuleFinding>;
  Line: string;
begin
  Line := '    property A2: IA read FA implements IA, IB;';
  Found := ImplementsFindings(Dienst('IA, IB, IC', '    FA: IA;'#10'    procedure Tun;'#10 +
    '    property A1: IA read FA implements IA;'#10 + Line + #10'    procedure IB.Machen = Tun;'#10 +
    '    procedure IC.Machen = Tun;'#10));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('IA wird schon von A1 per implements umgesetzt (wie E2257).', Found[0].Message);
  Assert.AreEqual(17, Found[0].Range.StartPos.Line);
  Assert.AreEqual(Pos('IA, IB', Line) - 1, Found[0].Range.StartPos.Character);
  Assert.AreEqual('Für IB gibt es die implements-Property A2; Methodenzuordnungen sind dann nicht erlaubt ' +
    '(wie E2264).', Found[1].Message);
  Assert.AreEqual(18, Found[1].Range.StartPos.Line);
  Assert.AreEqual(14, Found[1].Range.StartPos.Character);
end;

procedure TImplementsClauseInvalidTests.OutsideOfClasses;
var
  Found: TArray<TRuleFinding>;
begin
  Found := ImplementsFindings(Kunden('  IA = interface'#10'    function GetA: IA;'#10 +
    '    property A: IA read GetA implements IA;'#10'  end;'#10'  TWert = record'#10'    FA: IA;'#10 +
    '    property A: IA read FA implements IA;'#10'  end;'#10));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual('implements ist nur in Klassen erlaubt (wie E2258).', Found[0].Message);
  Assert.AreEqual(7, Found[0].Range.StartPos.Line);
  Assert.AreEqual(11, Found[1].Range.StartPos.Line);
end;

procedure TImplementsClauseInvalidTests.SilentCases;
begin
  // Unbekannter Typ, Alias, Klasse, register, Feld als Getter, generisches Interface, bedingter Zweig.
  Assert.AreEqual(0, Integer(Length(ImplementsFindings(Dienst('IA, IB, IC, ID, IBasis', '    FX: TUnbekannt;'#10 +
    '    FAlias: TAlias;'#10'    FKlasse: TKlasse;'#10'    function GetD: ID; register;'#10 +
    '    property X: TUnbekannt read FX implements IA;'#10'    property Alias: TAlias read FAlias implements IBasis;'#10 +
    '    property Klasse: TKlasse read FKlasse implements IB;'#10'    property D: ID read GetD implements ID;'#10 +
    '  {$IFDEF ALT}'#10'    property C: IC read FX write FX index 2 implements IC;'#10'  {$ENDIF}'#10 +
    '    property Liste: IList<Integer> read FListe implements IList<Integer>;'#10)))));
end;

procedure TImplementsClauseInvalidTests.OffAndExclude;
var
  Source: string;
begin
  Source := Kunden('  TDienst = class(TInterfacedObject, IBasis)'#10'    FBasis: IBasis;'#10 +
    '    property Basis: IBasis write FBasis implements IBasis;'#10'  end;'#10);
  Assert.AreEqual(1, Integer(Length(ImplementsFindings(Source, '', 'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(ImplementsFindings(Source, '{"rules": {"implements-clause-invalid": "off"}}',
    'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(ImplementsFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Kunden.pas'))));
  Assert.AreEqual(0, Integer(Length(ImplementsFindings(Source,
    '{"rules": {"implements-clause-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Kunden.pas'))));
end;

{ TCallingConventionRequiredTests }

function ConventionFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TCallingConventionRequiredRule.Create, ASource);
end;

function ConventionFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TCallingConventionRequiredRule.Create, ASource, AConfig, APath);
end;

/// <summary>Unit Druck mit AInterface im interface- und AImplementation im implementation-Teil.</summary>
function Druck(const AInterface, AImplementation: string): string;
begin
  Result := 'unit Druck;'#10'interface'#10 + AInterface + 'implementation'#10 + AImplementation + 'end.';
end;

procedure TCallingConventionRequiredTests.IssueExampleVarargsWithFix;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Druck('function Formatieren(Muster: PAnsiChar): Integer; stdcall; varargs; external ''msvcrt.dll'';'#10 +
    'function Zwei(Muster: PAnsiChar): Integer; varargs; external ''msvcrt.dll'';'#10 +
    'function Drei(Muster: PAnsiChar): Integer; cdecl; varargs; external ''msvcrt.dll'';'#10 +
    'procedure Vier(Muster: PAnsiChar); stdcall; varargs;'#10, 'procedure Vier(Muster: PAnsiChar);'#10'begin'#10 +
    'end;'#10);
  Found := ConventionFindings(Source);
  Assert.AreEqual(3, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual('varargs ist nur mit cdecl erlaubt (wie E2277).', Found[0].Message);
  Assert.AreEqual(2, Found[0].Range.StartPos.Line);
  Assert.AreEqual(59, Found[0].Range.StartPos.Character);
  Assert.AreEqual('cdecl setzen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('function Formatieren(Muster: PAnsiChar): Integer; cdecl; varargs; external ''msvcrt.dll'';',
    Fixed) > 0, Fixed);
  Fixed := ApplyFix(Fixed, Found[1].Fixes[0]);
  Assert.IsTrue(Pos('function Zwei(Muster: PAnsiChar): Integer; cdecl; varargs; external ''msvcrt.dll'';', Fixed) > 0,
    Fixed);
  Assert.AreEqual('varargs ist nur mit cdecl erlaubt (wie E2591).', Found[2].Message);
  Assert.AreEqual(5, Found[2].Range.StartPos.Line);
  Fixed := ApplyFix(Fixed, Found[2].Fixes[0]);
  Assert.AreEqual(0, Integer(Length(ConventionFindings(Fixed))), Fixed);
end;

procedure TCallingConventionRequiredTests.ConstructorsAndDestructors;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Druck('type'#10'  TBasis = class'#10'    constructor Create; pascal;'#10 +
    '    destructor Destroy; override; stdcall;'#10'    constructor Neu; register;'#10 +
    '    class constructor Init;'#10'    procedure Machen; stdcall;'#10'  end;'#10,
    'constructor TBasis.Create; pascal;'#10'begin'#10'end;'#10#10'destructor TBasis.Destroy;'#10'begin'#10'end;'#10);
  Found := ConventionFindings(Source);
  Assert.AreEqual(2, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual('Konstruktoren und Destruktoren brauchen register, nicht pascal (wie E2236).', Found[0].Message);
  Assert.AreEqual(4, Found[0].Range.StartPos.Line);
  Assert.AreEqual(24, Found[0].Range.StartPos.Character);
  Assert.AreEqual('pascal entfernen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('    constructor Create;'#10, Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('constructor TBasis.Create;'#10, Fixed) > 0, Fixed);
  Assert.AreEqual('Konstruktoren und Destruktoren brauchen register, nicht stdcall (wie E2236).', Found[1].Message);
  Fixed := ApplyFix(Fixed, ConventionFindings(Fixed)[0].Fixes[0]);
  Assert.IsTrue(Pos('    destructor Destroy; override;'#10, Fixed) > 0, Fixed);
  Assert.AreEqual(0, Integer(Length(ConventionFindings(Fixed))), Fixed);
end;

procedure TCallingConventionRequiredTests.PublishedAccessors;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := Druck('type'#10'  TBasis = class'#10'  private'#10'    function GetWert: Integer; cdecl;'#10 +
    '    procedure SetWert(V: Integer); stdcall;'#10'    function GetAnders: Integer; cdecl;'#10'  public'#10 +
    '    property Anders: Integer read GetAnders;'#10'  published'#10 +
    '    property Wert: Integer read GetWert write SetWert;'#10'    property Feld: Integer read FFeld;'#10'  end;'#10,
    'function TBasis.GetWert: Integer; cdecl;'#10'begin'#10'  Result := 0;'#10'end;'#10);
  Found := ConventionFindings(Source);
  Assert.AreEqual(2, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual('Der Getter GetWert der published-Property Wert braucht register, nicht cdecl (wie E2270).',
    Found[0].Message);
  Assert.AreEqual(11, Found[0].Range.StartPos.Line);
  Assert.AreEqual(32, Found[0].Range.StartPos.Character);
  Assert.AreEqual('Der Setter SetWert der published-Property Wert braucht register, nicht stdcall (wie E2270).',
    Found[1].Message);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.IsTrue(Pos('    function GetWert: Integer;'#10, Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('function TBasis.GetWert: Integer;'#10, Fixed) > 0, Fixed);
  Assert.AreEqual(1, Integer(Length(ConventionFindings(Fixed))), Fixed);
end;

procedure TCallingConventionRequiredTests.OffAndExclude;
var
  Source: string;
begin
  Source := Druck('function Formatieren(Muster: PAnsiChar): Integer; stdcall; varargs; external ''msvcrt.dll'';'#10,
    '');
  Assert.AreEqual(1, Integer(Length(ConventionFindings(Source, '', 'Source/Druck.pas'))));
  Assert.AreEqual(0, Integer(Length(ConventionFindings(Source, '{"rules": {"calling-convention-required": "off"}}',
    'Source/Druck.pas'))));
  Assert.AreEqual(0, Integer(Length(ConventionFindings(Source, '{"rules": {"group:compiler": "off"}}',
    'Source/Druck.pas'))));
  Assert.AreEqual(0, Integer(Length(ConventionFindings(Source,
    '{"rules": {"calling-convention-required": {"exclude": ["Source/*.pas"]}}}', 'Source/Druck.pas'))));
end;

{ TDispinterfaceInvalidTests }

function DispFindings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TDispinterfaceInvalidRule.Create, ASource);
end;

function DispFindings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TDispinterfaceInvalidRule.Create, ASource, AConfig, APath);
end;

/// <summary>Unit Anzeige mit IBasis (Zeilen 3 und 4) und ATypes ab Zeile 5 im type-Abschnitt.</summary>
function Anzeige(const ATypes: string): string;
begin
  Result := 'unit Anzeige;'#10'interface'#10'type'#10'  IBasis = interface'#10'  end;'#10 + ATypes +
    'implementation'#10'end.';
end;

/// <summary>Die vier Fälle Cm.E2228 bis Cm.E2231 in einer Unit.</summary>
function DispCases: string;
begin
  Result := Anzeige('  DA = dispinterface(IBasis)'#10'    [''{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A0001}'']'#10'  end;'#10 +
    '  DB = dispinterface'#10'    procedure Machen; dispid 1;'#10'  end;'#10 +
    '  DC = dispinterface'#10'    [''{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A0003}'']'#10 +
    '    procedure Machen; stdcall; dispid 1;'#10'  end;'#10 +
    '  DD = dispinterface'#10'    [''{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A0004}'']'#10 +
    '    function GetWert: Integer; dispid 1;'#10'    procedure SetWert(AWert: Integer); dispid 2;'#10 +
    '    property Wert: Integer read GetWert write SetWert;'#10'  end;'#10);
end;

procedure TDispinterfaceInvalidTests.IssueCasesWithPositions;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := DispFindings(DispCases);
  Assert.AreEqual(5, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('Ein dispinterface kann keinen Vorfahren haben (wie E2228).', mFound[0].Message);
  Assert.AreEqual(5, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(20, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(28, mFound[0].Range.EndPos.Character);
  Assert.AreEqual('Das dispinterface DB braucht eine GUID (wie E2229).', mFound[1].Message);
  Assert.AreEqual(8, mFound[1].Range.StartPos.Line);
  Assert.AreEqual(2, mFound[1].Range.StartPos.Character);
  Assert.AreEqual('Methoden eines dispinterface dürfen keine Direktive stdcall haben (wie E2230).',
    mFound[2].Message);
  Assert.AreEqual(13, mFound[2].Range.StartPos.Line);
  Assert.AreEqual(22, mFound[2].Range.StartPos.Character);
  Assert.AreEqual('Die Direktive read ist in einem dispinterface nicht erlaubt (wie E2231).', mFound[3].Message);
  Assert.AreEqual(19, mFound[3].Range.StartPos.Line);
  Assert.AreEqual(27, mFound[3].Range.StartPos.Character);
  Assert.AreEqual('Die Direktive write ist in einem dispinterface nicht erlaubt (wie E2231).', mFound[4].Message);
  Assert.AreEqual(40, mFound[4].Range.StartPos.Character);
  Assert.AreEqual(Ord(TRuleSeverity.Error), Ord(mFound[0].Severity));
end;

procedure TDispinterfaceInvalidTests.FixesRemoveAndInsert;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := DispCases;
  mFound := DispFindings(mSource);
  Assert.AreEqual('Vorfahren entfernen', mFound[0].Fixes[0].Title);
  mFixed := ApplyFix(mSource, mFound[0].Fixes[0]);
  Assert.IsTrue(Pos('  DA = dispinterface'#10'    [''{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A0001}'']', mFixed) > 0, mFixed);
  Assert.AreEqual(4, Integer(Length(DispFindings(mFixed))), mFixed);
  Assert.AreEqual('GUID einfügen', mFound[1].Fixes[0].Title);
  mFixed := ApplyFix(mSource, mFound[1].Fixes[0]);
  Assert.IsTrue(Pos('  DB = dispinterface'#10'    [''{', mFixed) > 0, mFixed);
  Assert.AreEqual(4, Integer(Length(DispFindings(mFixed))), mFixed);
  Assert.AreEqual('stdcall entfernen', mFound[2].Fixes[0].Title);
  mFixed := ApplyFix(mSource, mFound[2].Fixes[0]);
  Assert.AreEqual(0, Pos('stdcall', mFixed), mFixed);
  Assert.IsTrue(Pos('2A0003}'']'#10'    procedure Machen; dispid 1;'#10, mFixed) > 0, mFixed);
  Assert.AreEqual(4, Integer(Length(DispFindings(mFixed))), mFixed);
  // Für read und write gibt es keine sichere Korrektur (readonly/writeonly hängen vom Getter ab).
  Assert.AreEqual(0, Integer(Length(mFound[3].Fixes)));
end;

procedure TDispinterfaceInvalidTests.AncestorWithoutGuid;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := Anzeige('  DE = dispinterface(IBasis)'#10'    procedure Machen; dispid 1;'#10'  end;'#10);
  mFound := DispFindings(mSource);
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  // Nach Position: zuerst der Name (E2229), dann die Klammer (E2228).
  Assert.AreEqual('Das dispinterface DE braucht eine GUID (wie E2229).', mFound[0].Message);
  // GUID hinter der Klammer der Vorfahren, danach lässt sich der Vorfahr entfernen.
  mFixed := ApplyFix(mSource, mFound[0].Fixes[0]);
  Assert.IsTrue(Pos('  DE = dispinterface(IBasis)'#10'    [''{', mFixed) > 0, mFixed);
  mFound := DispFindings(mFixed);
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  mFixed := ApplyFix(mFixed, mFound[0].Fixes[0]);
  Assert.IsTrue(Pos('  DE = dispinterface'#10'    [''{', mFixed) > 0, mFixed);
  Assert.AreEqual(0, Integer(Length(DispFindings(mFixed))), mFixed);
end;

procedure TDispinterfaceInvalidTests.SilentCases;
begin
  // Vorwärtsdeklaration, GUID über eine Konstante, dispid, readonly, writeonly, default an einer Array-Property,
  // Hinweise, overload (von dcc nicht belegt), bedingte Zweige und gewöhnliche Interfaces.
  Assert.AreEqual(0, Integer(Length(DispFindings(Anzeige('  DAnzeige = dispinterface;'#10 +
    '  DListe = dispinterface'#10'    [cListeGuid]'#10 +
    '    property Eintrag[AIndex: Integer]: DAnzeige readonly dispid 0; default;'#10'  end;'#10 +
    '  DAnzeige = dispinterface'#10'    [''{6A0F0D5E-1C11-4B8E-9A43-3F1D4C2A2280}'']'#10 +
    '    procedure Machen; dispid 1;'#10'    procedure Alt; dispid 2; deprecated;'#10 +
    '    procedure Laden(AWert: Integer); overload; dispid 3;'#10 +
    '    property Name: WideString readonly dispid 4;'#10'    property Ziel: WideString writeonly dispid 5;'#10 +
    '    property Breite: Integer dispid 6;'#10'  {$IFDEF ALT}'#10'    procedure Neu; stdcall;'#10 +
    '    property Wert: Integer read GetWert;'#10'  {$ENDIF}'#10'  end;'#10 +
    '  {$IFDEF ALT}'#10'  DOhne = dispinterface(IBasis)'#10'    procedure Machen; stdcall;'#10'  end;'#10 +
    '  {$ENDIF}'#10'  IKunde = interface'#10'    function GetWert: Integer; stdcall;'#10 +
    '    property Wert: Integer read GetWert;'#10'  end;'#10)))));
end;

procedure TDispinterfaceInvalidTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := Anzeige('  DB = dispinterface'#10'    procedure Machen; dispid 1;'#10'  end;'#10);
  Assert.AreEqual(1, Integer(Length(DispFindings(mSource, '', 'Source/Anzeige.pas'))));
  Assert.AreEqual(0, Integer(Length(DispFindings(mSource, '{"rules": {"dispinterface-invalid": "off"}}',
    'Source/Anzeige.pas'))));
  Assert.AreEqual(0, Integer(Length(DispFindings(mSource, '{"rules": {"group:compiler": "off"}}',
    'Source/Anzeige.pas'))));
  Assert.AreEqual(0, Integer(Length(DispFindings(mSource,
    '{"rules": {"dispinterface-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Anzeige.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TMessageMethodInvalidTests);
  TDUnitX.RegisterTestFixture(TInterfaceDeclarationInvalidTests);
  TDUnitX.RegisterTestFixture(TImplementsClauseInvalidTests);
  TDUnitX.RegisterTestFixture(TCallingConventionRequiredTests);
  TDUnitX.RegisterTestFixture(TDispinterfaceInvalidTests);

end.
