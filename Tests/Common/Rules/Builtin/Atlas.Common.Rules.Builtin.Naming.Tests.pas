unit Atlas.Common.Rules.Builtin.Naming.Tests;

// Tests der Regel naming-prefix (#1111): jede Art mit Meldung und Korrektur,
// die Ausnahmen, Fälle ohne Korrektur und die Konfiguration (Optionen,
// Projektdatei .atlas, leer = aus); dazu die Präfixe der Projektdatei in der
// Korrektur von shadowed-name.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TNamingRulesTests = class
  public
    [Test]
    procedure FollowsAndExpected;
    [Test]
    procedure LocalReportedAndRenamed;
    [Test]
    procedure InlineVariablesAndConstants;
    [Test]
    procedure FieldRenamedInClassAndMethods;
    /// <summary>Öffentliche Felder (public, published, Record ohne Abschnitt) tragen kein F, z. B. TPoint.X.
    /// </summary>
    [Test]
    procedure PublicFieldsKeepNames;
    [Test]
    procedure ParameterRenamedInDeclarationAndImplementation;
    [Test]
    procedure ParametersOfStandaloneRoutines;
    [Test]
    procedure ConstantsInRoutineClassAndUnit;
    [Test]
    procedure Exceptions;
    [Test]
    procedure InterfaceImplementationsKeepNames;
    /// <summary>Im Code einem Ereignis zugewiesene Methoden (FEvents.OnEditorPaintLine := PaintLine) und Paare aus
    /// einem Buchstaben (function(const A, B: T)) behalten ihre Namen.</summary>
    [Test]
    procedure EventMethodsAndLetterPairsKeepNames;
    [Test]
    procedure NoFixWhenUnsafe;
    /// <summary>Der neue Name zählt nur dort, wo umbenannt wird: ABuf als Parameter einer anderen Routine sperrt
    /// die Korrektur nicht, ein Nachbarparameter ABuf schon.</summary>
    [Test]
    procedure FixWhenNewNameOnlyElsewhere;
    [Test]
    procedure ConfigurationAndProjectFile;
    [Test]
    procedure ShadowedNameUsesProjectPrefixes;
    /// <summary>Präfixe neuer Namen: die der Namensregel, wenn sie für die Datei läuft (auch aus ihren Optionen),
    /// sonst keine.</summary>
    [Test]
    procedure NewNamesFollowActiveRule;
    /// <summary>„Konstante einführen“ (magic-number) bildet cNewConstant, wenn naming-prefix läuft; sonst meldete
    /// die Namensregel die Korrektur gleich wieder.</summary>
    [Test]
    procedure FixesFollowNamingRule;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Builtin.Naming,
  Atlas.Common.Rules.Builtin.Inheritance,
  Atlas.Common.Rules.Builtin.Style,
  Atlas.Tests.RuleAssert,
  Atlas.Common.Rules.Profiles;

const
  cEnabled = '{"rules": {"naming-prefix": "hint"}}';

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TNamingPrefixRule.Create, ASource, cEnabled);
end;

function Findings(const ASource, AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TNamingPrefixRule.Create, ASource, AConfig);
end;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  mFinding: TRuleFinding;
begin
  Result := '';
  for mFinding in AFound do
  begin
    Result := Result + mFinding.Message + '|';
  end;
end;

/// <summary>Offset von APosition in AText mit Zeilen aus #10.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  mLine, mIndex: Integer;
begin
  mLine := 0;
  mIndex := 1;
  while (mLine < APosition.Line) and (mIndex <= Length(AText)) do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
    end;
    Inc(mIndex);
  end;
  Result := mIndex + APosition.Character;
end;

/// <summary>Wendet die Edits einer Korrektur von hinten nach vorn an.</summary>
function ApplyFix(const AText: string; const AFix: TRuleFix): string;
var
  mIndex, mStart, mStop: Integer;
begin
  Result := AText;
  for mIndex := High(AFix.Edits) downto 0 do
  begin
    mStart := OffsetOf(Result, AFix.Edits[mIndex].Range.StartPos);
    mStop := OffsetOf(Result, AFix.Edits[mIndex].Range.EndPos);
    Result := Copy(Result, 1, mStart - 1) + AFix.Edits[mIndex].NewText + Copy(Result, mStop, MaxInt);
  end;
end;

function UnitOf(const AInterface, AImplementation: string): string;
begin
  Result := 'unit U;'#10'interface'#10 + AInterface + 'implementation'#10 + AImplementation + 'end.';
end;

{ TNamingRulesTests }

procedure TNamingRulesTests.FollowsAndExpected;
begin
  Assert.IsTrue(TNamingConvention.Follows('mIndex', 'm'));
  Assert.IsTrue(TNamingConvention.Follows('m1', 'm'));
  Assert.IsFalse(TNamingConvention.Follows('menu', 'm'), 'Kleinbuchstabe nach dem Präfix');
  Assert.IsFalse(TNamingConvention.Follows('MIndex', 'm'), 'Groß-/Kleinschreibung des Präfixes zählt');
  Assert.IsFalse(TNamingConvention.Follows('m', 'm'), 'nur das Präfix');
  Assert.IsTrue(TNamingConvention.Follows('f_name', 'f_'), 'Präfix ohne Buchstaben am Ende');
  Assert.IsTrue(TNamingConvention.Follows('Name', ''), 'leeres Präfix');
  Assert.AreEqual('mIndex', TNamingConvention.Expected('Index', 'm'));
  Assert.AreEqual('mIndex', TNamingConvention.Expected('index', 'm'));
  Assert.AreEqual('f_name', TNamingConvention.Expected('name', 'f_'));
  Assert.IsTrue(TRuleProfiles.IsExperimental((TNamingPrefixRule.Create as IRule).Descriptor.Id), 'nur eingeschaltet aktiv');
end;

procedure TNamingRulesTests.LocalReportedAndRenamed;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := UnitOf('', 'procedure P;'#10'var'#10'  Count, mOk: Integer;'#10'begin'#10'  Count := 1;'#10 +
    '  mOk := Count + Self.Count;'#10'end;'#10);
  mFound := Findings(mSource);
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual('Lokale Variable Count ohne Präfix m (erwartet: mCount)', mFound[0].Message);
  Assert.AreEqual(5, mFound[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFound[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual('In mCount umbenennen', mFound[0].Fixes[0].Title);
  mFixed := ApplyFix(mSource, mFound[0].Fixes[0]);
  // Self.Count ist ein anderes Symbol und bleibt.
  Assert.AreEqual(StringReplace(StringReplace(mSource, 'Count', 'mCount', [rfReplaceAll]), 'Self.mCount',
    'Self.Count', []), mFixed);
  TRuleAssert.Silent(TNamingPrefixRule.Create, mFixed);
  Assert.AreEqual(0, Integer(Length(Findings(mFixed))));
end;

procedure TNamingRulesTests.InlineVariablesAndConstants;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := UnitOf('', 'procedure P;'#10'begin'#10'  Total := 0;'#10'  var Total := 1;'#10'  const Limit = 3;'#10 +
    '  for var Item in [1, 2] do'#10'    Total := Total + Item + Limit;'#10'  for var I := 1 to 2 do'#10 +
    '    Total := I;'#10'end;'#10);
  mFound := Findings(mSource);
  Assert.AreEqual('Lokale Variable Total ohne Präfix m (erwartet: mTotal)|' +
    'Konstante Limit ohne Präfix c (erwartet: cLimit)|' +
    'Lokale Variable Item ohne Präfix m (erwartet: mItem)|', Messages(mFound));
  // Inline: erst ab der Deklaration; das Total davor ist ein anderes Symbol.
  mFixed := ApplyFix(mSource, mFound[0].Fixes[0]);
  Assert.Contains(mFixed, '  Total := 0;'#10'  var mTotal := 1;');
  Assert.Contains(mFixed, 'mTotal := mTotal + Item + Limit;');
  Assert.Contains(mFixed, 'mTotal := I;');
  mFixed := ApplyFix(mSource, mFound[2].Fixes[0]);
  Assert.Contains(mFixed, 'for var mItem in [1, 2] do'#10'    Total := Total + mItem + Limit;');
end;

procedure TNamingRulesTests.FieldRenamedInClassAndMethods;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := UnitOf('type'#10'  TKunde = class'#10'  private'#10'    Name: string;'#10'  protected'#10 +
    '    Alter: Integer;'#10'    property Titel: string read Name write Name;'#10'    procedure Setzen;'#10 +
    '  end;'#10, 'procedure TKunde.Setzen;'#10'begin'#10'  Name := ''x'';'#10'  Self.Name := Name;'#10'end;'#10);
  mFound := Findings(mSource);
  Assert.AreEqual('Feld Name ohne Präfix F (erwartet: FName)|Feld Alter ohne Präfix F (erwartet: FAlter)|',
    Messages(mFound));
  mFixed := ApplyFix(mSource, mFound[0].Fixes[0]);
  Assert.AreEqual(StringReplace(mSource, 'Name', 'FName', [rfReplaceAll]), mFixed);
  // Geschützte Felder können Nachfahren in anderen Units verwenden: keine Korrektur.
  Assert.AreEqual(0, Integer(Length(mFound[1].Fixes)));
end;

procedure TNamingRulesTests.PublicFieldsKeepNames;
var
  mFound: TArray<TRuleFinding>;
begin
  // Wie TAtlasResultEntry: Felder eines Records ohne Abschnitt, public- und published-Felder.
  mFound := Findings(UnitOf('type'#10'  TEintrag = record'#10'    FileName: string;'#10'    Line: Integer;'#10 +
    '    class function Create(ALine: Integer): TEintrag; static;'#10'  end;'#10 +
    '  TPunkt = record'#10'  public'#10'    X, Y: Integer;'#10'  end;'#10 +
    '  TKunde = class'#10'  public'#10'    Alter: Integer;'#10'    class var Anzahl: Integer;'#10 +
    '  published'#10'    Titel: string;'#10'  end;'#10, ''));
  Assert.AreEqual('', Messages(mFound));
  // Private Felder eines Records und Felder einer Klasse ohne Abschnitt bleiben gemeldet.
  mFound := Findings(UnitOf('type'#10'  TZaehler = record'#10'  private'#10'    Wert: Integer;'#10'  public'#10 +
    '    property Stand: Integer read Wert;'#10'  end;'#10'  TListe = class'#10'    Anzahl: Integer;'#10'  end;'#10,
    ''));
  Assert.AreEqual('Feld Wert ohne Präfix F (erwartet: FWert)|Feld Anzahl ohne Präfix F (erwartet: FAnzahl)|',
    Messages(mFound));
end;

procedure TNamingRulesTests.ParameterRenamedInDeclarationAndImplementation;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := UnitOf('type'#10'  TKunde = class'#10'    procedure Setzen(const Wert: string; AAlt: Integer);'#10 +
    '  end;'#10, 'procedure TKunde.Setzen(const Wert: string; AAlt: Integer);'#10'begin'#10 +
    '  Writeln(Wert, AAlt);'#10'end;'#10);
  mFound := Findings(mSource);
  // Nur einmal an der Deklaration.
  Assert.AreEqual('Parameter Wert ohne Präfix A (erwartet: AWert)|', Messages(mFound));
  Assert.AreEqual(4, mFound[0].Range.StartPos.Line);
  mFixed := ApplyFix(mSource, mFound[0].Fixes[0]);
  Assert.AreEqual(StringReplace(mSource, 'Wert', 'AWert', [rfReplaceAll]), mFixed);
  TRuleAssert.Silent(TNamingPrefixRule.Create, mFixed);
  Assert.AreEqual(0, Integer(Length(Findings(mFixed))));
end;

procedure TNamingRulesTests.ParametersOfStandaloneRoutines;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  // interface-Abschnitt: an der Deklaration; Routine nur in der implementation: dort. Anonyme Methoden und
  // Prozedurtypen auch.
  mSource := UnitOf('type'#10'  TRechner = reference to function(Wert: Integer): Integer;'#10 +
    'function Doppelt(Wert: Integer): Integer;'#10, 'function Doppelt(Wert: Integer): Integer;'#10'begin'#10 +
    '  Result := Wert * 2;'#10'end;'#10'function Halb(Zahl: Integer): Integer;'#10'var'#10'  mF: TRechner;'#10 +
    'begin'#10'  mF := function(Teil: Integer): Integer'#10'    begin'#10'      Result := Teil;'#10'    end;'#10 +
    '  Result := Zahl div 2;'#10'end;'#10);
  mFound := Findings(mSource);
  Assert.AreEqual('Parameter Wert ohne Präfix A (erwartet: AWert)|Parameter Wert ohne Präfix A (erwartet: AWert)|' +
    'Parameter Zahl ohne Präfix A (erwartet: AZahl)|Parameter Teil ohne Präfix A (erwartet: ATeil)|',
    Messages(mFound));
  // Doppelt: Deklaration und Implementierung zusammen.
  mFixed := ApplyFix(mSource, mFound[1].Fixes[0]);
  Assert.Contains(mFixed, 'function Doppelt(AWert: Integer): Integer;'#10'implementation');
  Assert.Contains(mFixed, 'Result := AWert * 2;');
  Assert.Contains(mFixed, 'reference to function(Wert: Integer)', 'der Prozedurtyp ist ein eigener Treffer');
  mFixed := ApplyFix(mSource, mFound[3].Fixes[0]);
  Assert.Contains(mFixed, 'function(ATeil: Integer): Integer'#10'    begin'#10'      Result := ATeil;');
end;

procedure TNamingRulesTests.ConstantsInRoutineClassAndUnit;
var
  mSource, mFixed: string;
  mFound: TArray<TRuleFinding>;
begin
  mSource := UnitOf('const'#10'  Oeffentlich = 1;'#10'type'#10'  TKunde = class'#10'  private const'#10 +
    '    Grenze = 2;'#10'  private'#10'    FWert: Integer;'#10'  end;'#10'resourcestring'#10'  sTitel = ''T'';'#10,
    'const'#10'  Intern = 3;'#10'procedure P;'#10'const'#10'  Lokal = 4;'#10'begin'#10 +
    '  Writeln(Oeffentlich + Intern + Lokal + TKunde.Grenze);'#10'end;'#10);
  mFound := Findings(mSource);
  Assert.AreEqual('Konstante Oeffentlich ohne Präfix c (erwartet: cOeffentlich)|' +
    'Konstante Grenze ohne Präfix c (erwartet: cGrenze)|Konstante Intern ohne Präfix c (erwartet: cIntern)|' +
    'Konstante Lokal ohne Präfix c (erwartet: cLokal)|', Messages(mFound));
  // interface: andere Units sehen sie.
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  mFixed := ApplyFix(mSource, mFound[2].Fixes[0]);
  Assert.Contains(mFixed, '  cIntern = 3;');
  Assert.Contains(mFixed, 'Oeffentlich + cIntern + Lokal');
  mFixed := ApplyFix(mSource, mFound[3].Fixes[0]);
  Assert.Contains(mFixed, '  cLokal = 4;');
  Assert.Contains(mFixed, 'Intern + cLokal + TKunde');
end;

procedure TNamingRulesTests.Exceptions;
var
  mSource: string;
  mFound: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TNamingPrefixRule.Create, '');
  // Formular: Komponenten vor dem ersten Abschnitt, published-Felder; override, message, published-Methode und
  // Ereignis-Handler; Schleifenzähler, globale Variable.
  mSource := UnitOf('type'#10'  TMain = class(TForm)'#10'    Button1: TButton;'#10 +
    '    procedure Button1Click(Sender: TObject; var Key: Word);'#10'  published'#10'    Label1: TLabel;'#10 +
    '  private'#10'    FOk: Boolean;'#10'  protected'#10'    procedure WndProc(var Message: TMessage); override;'#10 +
    '    procedure WMSize(var Msg: TWMSize); message WM_SIZE;'#10'  published'#10 +
    '    procedure Ereignis(Wert: Integer);'#10'  end;'#10'var'#10'  Global: Integer;'#10,
    'procedure P;'#10'var'#10'  I: Integer;'#10'begin'#10'  for I := 1 to 2 do ;'#10'  for var J := 1 to 2 do ;'#10 +
    'end;'#10'procedure TMain.Button1Click(Sender: TObject; var Key: Word);'#10'begin'#10'end;'#10 +
    'procedure TMain.WndProc(var Message: TMessage);'#10'begin'#10'end;'#10 +
    'procedure TMain.WMSize(var Msg: TWMSize);'#10'begin'#10'end;'#10 +
    'procedure TMain.Ereignis(Wert: Integer);'#10'begin'#10'end;'#10);
  mFound := Findings(mSource);
  Assert.AreEqual('', Messages(mFound), 'Ausnahmen');
  // ignore: Muster.
  mSource := UnitOf('type'#10'  TApi = record'#10'  private'#10'    cbSize: Cardinal;'#10'    dwFlags: Cardinal;'#10 +
    '  end;'#10, '');
  mFound := Findings(mSource, '{"rules": {"naming-prefix": {"severity": "hint", "ignore": ["cb*", "dw*"]}}}');
  Assert.AreEqual('', Messages(mFound));
end;

procedure TNamingRulesTests.InterfaceImplementationsKeepNames;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(UnitOf('type'#10'  IBasis = interface'#10'    procedure Laden(Datei: string);'#10'  end;'#10 +
    '  IDienst = interface(IBasis)'#10'    procedure Melden(Text: string);'#10'  end;'#10 +
    '  TDienst = class(TInterfacedObject, IDienst)'#10'    procedure Laden(Datei: string);'#10 +
    '    procedure Melden(Text: string);'#10'    procedure Eigen(Wert: Integer);'#10'  end;'#10 +
    '  TFremd = class(TInterfacedObject, IUnbekannt)'#10'    procedure Tun(Wert: Integer);'#10'  end;'#10, ''));
  // Die Interfaces selbst und die eigene Methode; die Implementierungen behalten die Namen, und bei einem
  // unbekannten Interface schweigt die Regel.
  Assert.AreEqual('Parameter Datei ohne Präfix A (erwartet: ADatei)|Parameter Text ohne Präfix A (erwartet: AText)|' +
    'Parameter Wert ohne Präfix A (erwartet: AWert)|', Messages(mFound));
  Assert.AreEqual(12, mFound[2].Range.StartPos.Line);
end;

procedure TNamingRulesTests.EventMethodsAndLetterPairsKeepNames;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(UnitOf('type'#10'  TMarken = class'#10'  private'#10'    FEvents: TEvents;'#10 +
    '    procedure PaintLine(const Rect: TRect; var AllowDefaultPainting: Boolean);'#10 +
    '    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);'#10 +
    '    procedure Eigen(Wert: Integer);'#10'    procedure Start;'#10'  end;'#10,
    'procedure TMarken.PaintLine(const Rect: TRect; var AllowDefaultPainting: Boolean);'#10'begin'#10'end;'#10 +
    'procedure TMarken.AppMessage(var Msg: TMsg; var Handled: Boolean);'#10'begin'#10'end;'#10 +
    'procedure TMarken.Eigen(Wert: Integer);'#10'begin'#10'end;'#10 +
    'procedure TMarken.Start;'#10'begin'#10'  FEvents.OnEditorPaintLine := PaintLine;'#10 +
    '  Application.OnMessage := Self.AppMessage;'#10'end;'#10 +
    'function Abstand(const A, B: Integer): Integer;'#10'begin'#10'  Result := B - A;'#10'end;'#10 +
    'function Mitte(X, Y: Integer): Integer;'#10'begin'#10'  Result := (X + Y) div 2;'#10'end;'#10));
  Assert.AreEqual('Parameter Wert ohne Präfix A (erwartet: AWert)|Parameter X ohne Präfix A (erwartet: AX)|' +
    'Parameter Y ohne Präfix A (erwartet: AY)|', Messages(mFound));
end;

procedure TNamingRulesTests.NoFixWhenUnsafe;
var
  mFound: TArray<TRuleFinding>;
begin
  // with im Rumpf.
  mFound := Findings(UnitOf('', 'procedure P(R: TRect);'#10'var'#10'  Left: Integer;'#10'begin'#10 +
    '  with R do'#10'    Left := 1;'#10'end;'#10));
  Assert.AreEqual(2, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(mFound[1].Fixes)));
  // Der neue Name gibt es schon.
  mFound := Findings(UnitOf('', 'procedure P;'#10'var'#10'  Wert, mWert: Integer;'#10'begin'#10 +
    '  Wert := mWert;'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  // Eine lokale Routine deklariert den Namen neu.
  mFound := Findings(UnitOf('', 'procedure P;'#10'var'#10'  Wert: Integer;'#10'  procedure Q;'#10'  var'#10 +
    '    Wert: string;'#10'  begin'#10'  end;'#10'begin'#10'  Wert := 1;'#10'end;'#10));
  Assert.AreEqual(2, Integer(Length(mFound)));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
  // Der neue Name wäre ein reserviertes Wort (S → AS, Atlas.Common.Semantics.ControlFlow).
  mFound := Findings(UnitOf('', 'procedure P(S: Integer);'#10'begin'#10'  S := 1;'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
end;

procedure TNamingRulesTests.ConfigurationAndProjectFile;
var
  mSource: string;
  mContext: TRuleContext;
  mFound: TArray<TRuleFinding>;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Der Parser prüft die Optionen.
  TConfigurationParser.Parse('{"rules": {"naming-prefix": {"local": 1, "field": "F"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.Contains(mIssues[0].Message, '"local" muss ein Text sein');
  mSource := UnitOf('', 'procedure P(Wert: Integer);'#10'const'#10'  Grenze = 1;'#10'var'#10'  LIndex: Integer;'#10 +
    'begin'#10'end;'#10);
  // Experimentell: ohne Eintrag in atlas.json still.
  Assert.AreEqual(0, Integer(Length(Findings(mSource, ''))));
  Assert.AreEqual(3, Integer(Length(Findings(mSource))));
  // Optionen: anderes Präfix, leer = Art aus.
  mFound := Findings(mSource,
    '{"rules": {"naming-prefix": {"severity": "hint", "local": "L", "constant": "", "parameter": "a_"}}}');
  Assert.AreEqual('Parameter Wert ohne Präfix a_ (erwartet: a_Wert)|', Messages(mFound));
  // Projektdatei .atlas über den Projektkontext.
  mContext := Default(TRuleContext);
  mContext.Text := mSource;
  mContext.Naming.Known[TRuleNamingKind.Local] := True;
  mContext.Naming.Prefixes[TRuleNamingKind.Local] := 'L';
  mContext.Naming.Known[TRuleNamingKind.Constant] := True;
  mContext.Naming.Prefixes[TRuleNamingKind.Constant] := '';
  mFound := TRuleAssert.ContextFindings(TNamingPrefixRule.Create, mContext, cEnabled);
  Assert.AreEqual('Parameter Wert ohne Präfix A (erwartet: AWert)|', Messages(mFound));
  // atlas.json hat Vorrang vor der Projektdatei.
  mFound := TRuleAssert.ContextFindings(TNamingPrefixRule.Create, mContext,
    '{"rules": {"naming-prefix": {"severity": "hint", "local": "m", "parameter": ""}}}');
  Assert.AreEqual('Lokale Variable LIndex ohne Präfix m (erwartet: mLIndex)|', Messages(mFound));
end;

procedure TNamingRulesTests.ShadowedNameUsesProjectPrefixes;
var
  mContext: TRuleContext;
  mFound: TArray<TRuleFinding>;
begin
  mContext := Default(TRuleContext);
  Assert.AreEqual('L', NamingPrefixFor(mContext, TRuleNamingKind.Local, 'L'));
  mContext.Naming.Known[TRuleNamingKind.Local] := True;
  Assert.AreEqual('L', NamingPrefixFor(mContext, TRuleNamingKind.Local, 'L'), 'leer: Vorgabe der Regel');
  mContext.Naming.Prefixes[TRuleNamingKind.Local] := 'm';
  Assert.AreEqual('m', NamingPrefixFor(mContext, TRuleNamingKind.Local, 'L'));
  mContext.Text := UnitOf('type'#10'  TKunde = class'#10'  private'#10'    FState: Integer;'#10'  public'#10 +
    '    property State: Integer read FState;'#10'    procedure Zeigen;'#10'  end;'#10,
    'procedure TKunde.Zeigen;'#10'var'#10'  State: Integer;'#10'begin'#10'  State := 1;'#10'end;'#10);
  mFound := TRuleAssert.ContextFindings(TShadowedNameRule.Create, mContext, '');
  Assert.AreEqual(1, Integer(Length(mFound)));
  Assert.AreEqual('In mState umbenennen', mFound[0].Fixes[0].Title);
end;


procedure TNamingRulesTests.NewNamesFollowActiveRule;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
  mContext: TRuleContext;
  mNames: TPascalNamePrefixes;
begin
  mContext := Default(TRuleContext);
  // Experimentell und aus: keine Präfixe.
  mNames := TRuleEngine.NewNames([TNamingPrefixRule.Create as IRule], TServerSettings.Default, mContext);
  Assert.AreEqual('', mNames.ConstantPrefix + mNames.LocalPrefix + mNames.FieldPrefix + mNames.ParameterPrefix);
  Assert.AreEqual('NewConstant', mNames.Constant('NewConstant'));
  mSettings := TConfigurationParser.Parse(cEnabled, mIssues);
  mNames := TRuleEngine.NewNames([TNamingPrefixRule.Create as IRule], mSettings, mContext);
  Assert.AreEqual('mValue', mNames.Local('Value'));
  Assert.AreEqual('FCount', mNames.Field('Count'));
  Assert.AreEqual('APreis', mNames.Parameter('Preis'));
  Assert.AreEqual('cNewConstant', mNames.Constant('NewConstant'));
  Assert.AreEqual('mValue', mNames.Local('mValue'), 'trägt das Präfix schon');
  // Optionen der Regel gelten auch für neue Namen.
  mSettings := TConfigurationParser.Parse('{"rules": {"naming-prefix": {"severity": "hint", "constant": "k"}}}',
    mIssues);
  mNames := TRuleEngine.NewNames([TNamingPrefixRule.Create as IRule], mSettings, mContext);
  Assert.AreEqual('kNewConstant', mNames.Constant('NewConstant'));
  mContext := Default(TRuleContext);
end;

procedure TNamingRulesTests.FixesFollowNamingRule;
const
  cSource = 'unit U;'#10'interface'#10'implementation'#10'function Rabatt(APreis: Double): Double;'#10'begin'#10 +
    '  Result := APreis * 0.93;'#10'end;'#10'end.';

  function FixText(const AConfig: string): string;
  var
    mFound: TArray<TRuleFinding>;
    mFinding: TRuleFinding;
  begin
    Result := '';
    mFound := TRuleAssert.FindingsOfAll([TMagicNumberRule.Create as IRule, TNamingPrefixRule.Create as IRule],
      cSource, AConfig);
    for mFinding in mFound do
    begin
      if (mFinding.RuleId = 'magic-number') and (Length(mFinding.Fixes) > 0) then
      begin
        Result := ApplyFix(cSource, mFinding.Fixes[0]);
      end;
    end;
  end;

var
  mFixed: string;
begin
  // magic-number meldet mit niedriger Konfidenz.
  mFixed := FixText('{"minConfidence": "low", "rules": {"magic-number": "hint"}}');
  Assert.IsTrue(Pos('NewConstant = 0.93', mFixed) > 0, mFixed);
  Assert.IsFalse(Pos('cNewConstant', mFixed) > 0, 'ohne Namensregel unverändert');
  mFixed := FixText('{"minConfidence": "low", "rules": {"magic-number": "hint", "naming-prefix": "hint"}}');
  Assert.IsTrue(Pos('cNewConstant = 0.93', mFixed) > 0, mFixed);
  Assert.IsTrue(Pos('APreis * cNewConstant', mFixed) > 0, mFixed);
end;

procedure TNamingRulesTests.FixWhenNewNameOnlyElsewhere;
var
  mFound: TArray<TRuleFinding>;
begin
  mFound := Findings(UnitOf('', 'procedure Q(const ABuf; ACount: Integer);'#10'begin'#10'end;'#10 +
    'procedure P(const Buf; ACount: Integer);'#10'begin'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(1, Integer(Length(mFound[0].Fixes)), 'ABuf steht nur in Q');
  Assert.AreEqual('In ABuf umbenennen', mFound[0].Fixes[0].Title);
  // Ein Nachbarparameter heißt schon so.
  mFound := Findings(UnitOf('', 'procedure P(const Buf; ABuf: Integer);'#10'begin'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(mFound)), Messages(mFound));
  Assert.AreEqual(0, Integer(Length(mFound[0].Fixes)));
end;

initialization
  TDUnitX.RegisterTestFixture(TNamingRulesTests);

end.
