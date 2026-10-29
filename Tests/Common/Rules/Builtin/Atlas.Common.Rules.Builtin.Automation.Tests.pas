unit Atlas.Common.Rules.Builtin.Automation.Tests;

// Tests der Regel automation-invalid (#1373): Abschnitt automated mit Feldern
// (E2175), Konstruktoren (E2177), dynamic und message (E2178),
// Aufrufkonventionen (E2179), doppelten dispids (E2180), Properties (E2181,
// E2182, E2096), dispid an override und außerhalb von automated (E2185) und
// unzulässigen Typen (E2176); Aufrufe über Variant und OleVariant (E2160,
// E2281, E2166); die Fälle aus Tests/Compilermeldungen, stille Fälle und die
// Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAutomationInvalidTests = class
  public
    [Test]
    procedure MembersInAutomatedSection;
    [Test]
    procedure DispidDuplicatesAndOverride;
    [Test]
    procedure PropertyClausesAndAccessors;
    [Test]
    procedure IllegalTypes;
    [Test]
    procedure DispatchCalls;
    [Test]
    procedure CompilerMessageCases;
    [Test]
    procedure SilentCases;
    [Test]
    procedure OffAndExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Automation,
  Atlas.Tests.RuleAssert;

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TAutomationInvalidRule.Create, ASource, '', 'Auto.pas');
end;

function Findings(const ASource, AConfig, APath: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TAutomationInvalidRule.Create, ASource, AConfig, APath);
end;

/// <summary>Treffer als "Zeile: Meldung" (Zeilen ab 1 wie im Editor), je Treffer eine Zeile.</summary>
function Lines(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
    Result := Result + Format('%d: %s', [mFinding.Range.StartPos.Line + 1, mFinding.Message]) + #10;
end;

/// <summary>Unit Auto mit ATypes im interface-Teil und ABodies im implementation-Teil.</summary>
function AutoUnit(const ATypes, ABodies: string): string;
begin
  Result := 'unit Auto;'#10'interface'#10'type'#10 + ATypes + 'implementation'#10 + ABodies + 'end.';
end;

{ TAutomationInvalidTests }

procedure TAutomationInvalidTests.MembersInAutomatedSection;
var
  mSource: string;
begin
  mSource := AutoUnit(
    '  TAuto = class'#10 +            // 4
    '  automated'#10 +                // 5
    '    FWert, FZweit: Integer;'#10 + // 6
    '    constructor Create;'#10 +    // 7
    '    destructor Destroy; override;'#10 + // 8
    '    procedure Neu; dynamic;'#10 + // 9
    '    procedure Nachricht(var AMsg); message 1;'#10 + // 10
    '    procedure Machen; stdcall;'#10 + // 11
    '    procedure Gut; register;'#10 + // 12
    '    function Rechnen: Integer; safecall;'#10 + // 13
    '  end;'#10, '');
  Assert.AreEqual(
    '6: Felder sind im Abschnitt automated nicht erlaubt (wie E2175).'#10 +
    '7: Konstruktoren und Destruktoren sind im Abschnitt automated nicht erlaubt (wie E2177).'#10 +
    '8: Konstruktoren und Destruktoren sind im Abschnitt automated nicht erlaubt (wie E2177).'#10 +
    '9: dynamic ist im Abschnitt automated nicht erlaubt (wie E2178).'#10 +
    '10: message ist im Abschnitt automated nicht erlaubt (wie E2178).'#10 +
    '11: Im Abschnitt automated ist nur register erlaubt, nicht stdcall (wie E2179).'#10 +
    '13: Im Abschnitt automated ist nur register erlaubt, nicht safecall (wie E2179).'#10,
    Lines(Findings(mSource)));
end;

procedure TAutomationInvalidTests.DispidDuplicatesAndOverride;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := AutoUnit(
    '  TBasis = class'#10 +                         // 4
    '  automated'#10 +                              // 5
    '    procedure Erste; dispid 1;'#10 +           // 6
    '    procedure Zweite; dispid 1;'#10 +          // 7
    '    procedure Dritte; dispid $10;'#10 +        // 8
    '    procedure Vierte; dispid 16;'#10 +         // 9
    '    procedure Virtuell; virtual; dispid 2;'#10 + // 10
    '    property Wert: Integer read GetWert dispid 1;'#10 + // 11
    '  private'#10 +                                // 12
    '    function GetWert: Integer;'#10 +           // 13
    '  end;'#10 +
    '  TKind = class(TBasis)'#10 +                  // 15
    '  automated'#10 +                              // 16
    '    procedure Virtuell; override; dispid 3;'#10 + // 17
    '    procedure Eigene; dispid 1;'#10 +          // 18
    '  public'#10 +                                 // 19
    '    procedure Oeffentlich; dispid 4;'#10 +     // 20
    '  end;'#10, '');
  mFound := Findings(mSource);
  Assert.AreEqual(
    '7: dispid 1 ist schon an Erste vergeben (wie E2180).'#10 +
    '9: dispid 16 ist schon an Dritte vergeben (wie E2180).'#10 +
    '11: dispid 1 ist schon an Erste vergeben (wie E2180).'#10 +
    '17: Die überschriebene Methode Virtuell übernimmt die dispid des Vorfahren und darf keine eigene angeben ' +
    '(wie E2185).'#10 +
    '20: dispid ist nur im Abschnitt automated erlaubt (wie E2185).'#10,
    Lines(mFound));
  // Die Meldung steht an der Direktive samt Wert.
  Assert.AreEqual(22, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(30, mFound[0].Range.EndPos.Character);
end;

procedure TAutomationInvalidTests.PropertyClausesAndAccessors;
var
  mSource: string;
begin
  mSource := AutoUnit(
    '  TBasis = class'#10 +                                      // 4
    '  private'#10 +                                             // 5
    '    FWert: Integer;'#10 +                                   // 6
    '    FPunkt: record X: Integer; end;'#10 +                   // 7
    '    function GetWert(AIndex: Integer): Integer;'#10 +       // 8
    '    procedure SetWert(AIndex, AWert: Integer);'#10 +        // 9
    '  automated'#10 +                                           // 10
    '    property Feld: Integer read FWert write FWert;'#10 +    // 11
    '    property Index: Integer index 1 read GetWert write SetWert;'#10 + // 12
    '    property Gespeichert: Integer read Gut stored False;'#10 + // 13
    '    property Vorgabe: Integer read Gut default 0;'#10 +     // 14
    '    property Ohne: Integer read Gut nodefault;'#10 +        // 15
    '    property X: Integer read FPunkt.X;'#10 +                // 16
    '    function Gut: Integer;'#10 +                            // 17
    '  end;'#10 +
    '  TKind = class(TBasis)'#10 +                               // 19
    '  automated'#10 +                                           // 20
    '    property Feld;'#10 +                                    // 21
    '  end;'#10, '');
  Assert.AreEqual(
    '11: Im Abschnitt automated muss read auf eine Methode zeigen; FWert ist ein Feld (wie E2096).'#10 +
    '11: Im Abschnitt automated muss write auf eine Methode zeigen; FWert ist ein Feld (wie E2096).'#10 +
    '12: index ist an Properties im Abschnitt automated nicht erlaubt (wie E2182).'#10 +
    '13: stored ist an Properties im Abschnitt automated nicht erlaubt (wie E2182).'#10 +
    '14: default ist an Properties im Abschnitt automated nicht erlaubt (wie E2182).'#10 +
    '15: nodefault ist an Properties im Abschnitt automated nicht erlaubt (wie E2182).'#10 +
    '21: Die Property Feld darf im Abschnitt automated nicht ohne Typ neu deklariert werden (wie E2181).'#10,
    Lines(Findings(mSource)));
end;

procedure TAutomationInvalidTests.IllegalTypes;
var
  mSource: string;
begin
  mSource := AutoUnit(
    '  TPunkt = record'#10 +                                       // 4
    '    X, Y: Integer;'#10 +                                      // 5
    '  end;'#10 +
    '  PPunkt = ^TPunkt;'#10 +                                     // 7
    '  TFarbe = (Rot, Gruen);'#10 +                                // 8
    '  TFarben = set of TFarbe;'#10 +                              // 9
    '  TAuto = class'#10 +                                         // 10
    '  private'#10 +                                               // 11
    '    function GetPunkt: TPunkt;'#10 +                          // 12
    '  automated'#10 +                                             // 13
    '    procedure Punkt(APunkt: TPunkt);'#10 +                    // 14
    '    procedure Zeiger(AZeiger: Pointer; ATyp: PPunkt);'#10 +   // 15
    '    function Farben: TFarben;'#10 +                           // 16
    '    property Wo: TPunkt read GetPunkt;'#10 +                  // 17
    '    procedure Erlaubt(AZahl: Integer; const AText: WideString; AWert: OleVariant; ' +
    'AFarbe: TFarbe; out AKomma: Double);'#10 +                    // 18
    '  end;'#10, '');
  Assert.AreEqual(
    '14: Der Typ TPunkt ist im Abschnitt automated nicht erlaubt (wie E2176).'#10 +
    '15: Der Typ Pointer ist im Abschnitt automated nicht erlaubt (wie E2176).'#10 +
    '15: Der Typ PPunkt ist im Abschnitt automated nicht erlaubt (wie E2176).'#10 +
    '16: Der Typ TFarben ist im Abschnitt automated nicht erlaubt (wie E2176).'#10 +
    '17: Der Typ TPunkt ist im Abschnitt automated nicht erlaubt (wie E2176).'#10,
    Lines(Findings(mSource)));
end;

procedure TAutomationInvalidTests.DispatchCalls;
var
  mSource: string;
begin
  mSource := AutoUnit(
    '  TPunkt = record'#10 +                              // 4
    '    X, Y: Integer;'#10 +                             // 5
    '  end;'#10,
    'procedure Fall;'#10 +                                // 8
    'var'#10 +                                            // 9
    '  mOle: OleVariant;'#10 +                            // 10
    '  mVar: Variant;'#10 +                               // 11
    '  mPunkt: TPunkt;'#10 +                              // 12
    '  mZeiger: Pointer;'#10 +                            // 13
    'begin'#10 +                                          // 14
    '  mOle.Machen(mPunkt);'#10 +                         // 15
    '  mVar.Machen(1, mZeiger);'#10 +                     // 16
    '  mOle.Dokument.Seiten[1].Oeffnen(mPunkt);'#10 +     // 17
    '  mVar.Machen(Wert := 1, 2);'#10 +                   // 18
    '  mVar.Machen(1, Wert := 2, Name := ''a'');'#10 +    // 19
    '  mVar := mOle.Rechnen(mZeiger);'#10 +               // 20
    'end;'#10);
  Assert.AreEqual(
    '15: Der Typ TPunkt ist in einem OLE-Automation-Aufruf nicht erlaubt (wie E2160).'#10 +
    '16: Der Typ Pointer ist in einem Variant-Dispatch-Aufruf nicht erlaubt (wie E2281).'#10 +
    '17: Der Typ TPunkt ist in einem OLE-Automation-Aufruf nicht erlaubt (wie E2160).'#10 +
    '18: Unbenannte Argumente müssen vor den benannten stehen (wie E2166).'#10 +
    '20: Der Typ Pointer ist in einem OLE-Automation-Aufruf nicht erlaubt (wie E2160).'#10,
    Lines(Findings(mSource)));
end;

procedure TAutomationInvalidTests.CompilerMessageCases;
const
  cDispatch = 'unit Cm;'#10'interface'#10'implementation'#10'uses'#10'  System.Variants;'#10;
begin
  // Inhalt wie Tests/Compilermeldungen/Faelle/Cm.E2160, Cm.E2166, Cm.E2281, Cm.E2183 und Cm.E2181 (ohne Kopf).
  Assert.AreEqual('21: Der Typ TPunkt ist in einem OLE-Automation-Aufruf nicht erlaubt (wie E2160).'#10,
    Lines(Findings(cDispatch + 'type'#10'  TPunkt = record'#10'    X, Y: Integer;'#10'  end;'#10#10 +
    'procedure Fall;'#10'var'#10'  mObjekt: OleVariant;'#10'  mPunkt: TPunkt;'#10'begin'#10 +
    '  mPunkt := Default(TPunkt);'#10'  mObjekt := Unassigned;'#10#10#10#10'  mObjekt.Machen(mPunkt);'#10 +
    'end;'#10#10'end.')));
  Assert.AreEqual('13: Unbenannte Argumente müssen vor den benannten stehen (wie E2166).'#10,
    Lines(Findings(cDispatch + #10'procedure Fall;'#10'var'#10'  mObjekt: OleVariant;'#10'begin'#10 +
    '  mObjekt := Unassigned;'#10#10'  mObjekt.Machen(Wert := 1, 2);'#10'end;'#10#10'end.')));
  Assert.AreEqual('15: Der Typ Pointer ist in einem Variant-Dispatch-Aufruf nicht erlaubt (wie E2281).'#10,
    Lines(Findings(cDispatch + #10'procedure Fall;'#10'var'#10'  mObjekt: Variant;'#10'  mZeiger: Pointer;'#10 +
    'begin'#10'  mObjekt := Unassigned;'#10'  mZeiger := nil;'#10#10'  mObjekt.Machen(mZeiger);'#10'end;'#10#10 +
    'end.')));
  Assert.AreEqual('11: dispid ist nur im Abschnitt automated erlaubt (wie E2185).'#10,
    Lines(Findings('unit Cm;'#10#10#10#10#10'interface'#10#10'type'#10'  TKlasse = class'#10'  public'#10 +
    '    procedure Machen; dispid 1;'#10'  end;'#10#10'implementation'#10#10'procedure TKlasse.Machen;'#10 +
    'begin'#10'end;'#10#10'end.')));
  Assert.AreEqual(
    '13: Im Abschnitt automated muss read auf eine Methode zeigen; FWert ist ein Feld (wie E2096).'#10 +
    '18: Die Property Wert darf im Abschnitt automated nicht ohne Typ neu deklariert werden (wie E2181).'#10,
    Lines(Findings('unit Cm;'#10#10#10#10#10'interface'#10#10'type'#10'  TBasis = class'#10'  private'#10 +
    '    FWert: Integer;'#10'  automated'#10'    property Wert: Integer read FWert;'#10'  end;'#10#10 +
    '  TKind = class(TBasis)'#10'  automated'#10'    property Wert;'#10'  end;'#10#10'implementation'#10#10'end.')));
end;

procedure TAutomationInvalidTests.SilentCases;
var
  mSource: string;
begin
  mSource := AutoUnit(
    '  TPunkt = record'#10 +
    '    X, Y: Integer;'#10 +
    '  end;'#10 +
    '  TWert = record'#10 +
    '    class operator Implicit(const AWert: TWert): Variant;'#10 +
    '  end;'#10 +
    '  PText = ^Char;'#10 +
    '  IAutoDisp = dispinterface'#10 +
    '    [''{00000000-0000-0000-0000-000000000001}'']'#10 +
    '    procedure Machen; dispid 1;'#10 +
    '    procedure Noch; dispid 3;'#10 +
    '    property Wert: Integer readonly dispid 2;'#10 +
    '  end;'#10 +
    '  TBasis = class'#10 +
    '  private'#10 +
    '    FWert: Integer;'#10 +
    '    function GetWert: Integer;'#10 +
    '    procedure SetWert(AWert: Integer);'#10 +
    '  public'#10 +
    '    constructor Create;'#10 +
    '    procedure Dyn; dynamic;'#10 +
    '    property Feld: Integer read FWert index 1;'#10 +
    '  automated'#10 +
    '    procedure Erste(AZahl: Integer; const AText: WideString); dispid 1;'#10 +
    '    procedure Zweite(var AWert: OleVariant); register; dispid 2;'#10 +
    '    procedure Virtuell; virtual; dispid 3;'#10 +
    '    function Text(AZeiger: PText): Integer;'#10 +
    '    property Wert: Integer read GetWert write SetWert dispid 4;'#10 +
    '{$IFDEF ALT}'#10 +
    '    procedure Alt; stdcall;'#10 +
    '{$ENDIF}'#10 +
    '  end;'#10 +
    '  TKind = class(TBasis)'#10 +
    '  automated'#10 +
    '    procedure Virtuell; override;'#10 +
    '    procedure Eigene; dispid 1;'#10 +
    '  end;'#10,
    'procedure Fall(const AObjekt: TBasis; AQuelle: IDispatch);'#10 +
    'var'#10 +
    '  mVar: Variant;'#10 +
    '  mPunkt: TPunkt;'#10 +
    '  mWert: TWert;'#10 +
    '  mZeiger: Pointer;'#10 +
    'begin'#10 +
    '  mVar.Machen(1, ''Text'', mVar, AQuelle, Wert := 2, Name := ''a'');'#10 +
    '  mVar.Machen(mWert);'#10 +
    '  AObjekt.Erste(mPunkt.X, '''');'#10 +
    '  Fall(AObjekt, AQuelle);'#10 +
    '  mVar.Machen(mPunkt.X, @mZeiger);'#10 +
    'end;'#10);
  Assert.AreEqual('', Lines(Findings(mSource)));
end;

procedure TAutomationInvalidTests.OffAndExclude;
var
  mSource: string;
begin
  mSource := AutoUnit('  TAuto = class'#10'  automated'#10'    procedure Machen; stdcall;'#10'  end;'#10, '');
  Assert.AreEqual(1, Integer(Length(Findings(mSource, '', 'Source/Auto.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"automation-invalid": "off"}}',
    'Source/Auto.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource, '{"rules": {"group:compiler": "off"}}', 'Source/Auto.pas'))));
  Assert.AreEqual(0, Integer(Length(Findings(mSource,
    '{"rules": {"automation-invalid": {"exclude": ["Source/*.pas"]}}}', 'Source/Auto.pas'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAutomationInvalidTests);

end.
