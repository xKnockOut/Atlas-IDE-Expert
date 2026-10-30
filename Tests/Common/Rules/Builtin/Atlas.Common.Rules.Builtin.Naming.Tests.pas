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
  Atlas.Tests.RuleAssert;

const
  Enabled = '{"rules": {"naming-prefix": "hint"}}';

function Findings(const ASource: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TNamingPrefixRule.Create, ASource, Enabled);
end;

function Findings(const ASource, AConfig: string): TArray<TRuleFinding>; overload;
begin
  Result := TRuleAssert.Findings(TNamingPrefixRule.Create, ASource, AConfig);
end;

function Messages(const AFound: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFound do
    Result := Result + Finding.Message + '|';
end;

/// <summary>Offset von APosition in AText mit Zeilen aus #10.</summary>
function OffsetOf(const AText: string; const APosition: TTextPosition): Integer;
var
  Line, Index: Integer;
begin
  Line := 0;
  Index := 1;
  while (Line < APosition.Line) and (Index <= Length(AText)) do
  begin
    if AText[Index] = #10 then
      Inc(Line);
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
  Assert.IsTrue((TNamingPrefixRule.Create as IRule).Descriptor.Experimental, 'nur eingeschaltet aktiv');
end;

procedure TNamingRulesTests.LocalReportedAndRenamed;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := UnitOf('', 'procedure P;'#10'var'#10'  Count, mOk: Integer;'#10'begin'#10'  Count := 1;'#10 +
    '  mOk := Count + Self.Count;'#10'end;'#10);
  Found := Findings(Source);
  Assert.AreEqual(1, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual('Lokale Variable Count ohne Präfix m (erwartet: mCount)', Found[0].Message);
  Assert.AreEqual(5, Found[0].Range.StartPos.Line);
  Assert.AreEqual(2, Found[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('In mCount umbenennen', Found[0].Fixes[0].Title);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  // Self.Count ist ein anderes Symbol und bleibt.
  Assert.AreEqual(StringReplace(StringReplace(Source, 'Count', 'mCount', [rfReplaceAll]), 'Self.mCount',
    'Self.Count', []), Fixed);
  TRuleAssert.Silent(TNamingPrefixRule.Create, Fixed);
  Assert.AreEqual(0, Integer(Length(Findings(Fixed))));
end;

procedure TNamingRulesTests.InlineVariablesAndConstants;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := UnitOf('', 'procedure P;'#10'begin'#10'  Total := 0;'#10'  var Total := 1;'#10'  const Limit = 3;'#10 +
    '  for var Item in [1, 2] do'#10'    Total := Total + Item + Limit;'#10'  for var I := 1 to 2 do'#10 +
    '    Total := I;'#10'end;'#10);
  Found := Findings(Source);
  Assert.AreEqual('Lokale Variable Total ohne Präfix m (erwartet: mTotal)|' +
    'Konstante Limit ohne Präfix c (erwartet: cLimit)|' +
    'Lokale Variable Item ohne Präfix m (erwartet: mItem)|', Messages(Found));
  // Inline: erst ab der Deklaration; das Total davor ist ein anderes Symbol.
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.Contains(Fixed, '  Total := 0;'#10'  var mTotal := 1;');
  Assert.Contains(Fixed, 'mTotal := mTotal + Item + Limit;');
  Assert.Contains(Fixed, 'mTotal := I;');
  Fixed := ApplyFix(Source, Found[2].Fixes[0]);
  Assert.Contains(Fixed, 'for var mItem in [1, 2] do'#10'    Total := Total + mItem + Limit;');
end;

procedure TNamingRulesTests.FieldRenamedInClassAndMethods;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := UnitOf('type'#10'  TKunde = class'#10'  private'#10'    Name: string;'#10'  protected'#10 +
    '    Alter: Integer;'#10'    property Titel: string read Name write Name;'#10'    procedure Setzen;'#10 +
    '  end;'#10, 'procedure TKunde.Setzen;'#10'begin'#10'  Name := ''x'';'#10'  Self.Name := Name;'#10'end;'#10);
  Found := Findings(Source);
  Assert.AreEqual('Feld Name ohne Präfix F (erwartet: FName)|Feld Alter ohne Präfix F (erwartet: FAlter)|',
    Messages(Found));
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.AreEqual(StringReplace(Source, 'Name', 'FName', [rfReplaceAll]), Fixed);
  // Geschützte Felder können Nachfahren in anderen Units verwenden: keine Korrektur.
  Assert.AreEqual(0, Integer(Length(Found[1].Fixes)));
end;

procedure TNamingRulesTests.PublicFieldsKeepNames;
var
  Found: TArray<TRuleFinding>;
begin
  // Wie TAtlasResultEntry: Felder eines Records ohne Abschnitt, public- und published-Felder.
  Found := Findings(UnitOf('type'#10'  TEintrag = record'#10'    FileName: string;'#10'    Line: Integer;'#10 +
    '    class function Create(ALine: Integer): TEintrag; static;'#10'  end;'#10 +
    '  TPunkt = record'#10'  public'#10'    X, Y: Integer;'#10'  end;'#10 +
    '  TKunde = class'#10'  public'#10'    Alter: Integer;'#10'    class var Anzahl: Integer;'#10 +
    '  published'#10'    Titel: string;'#10'  end;'#10, ''));
  Assert.AreEqual('', Messages(Found));
  // Private Felder eines Records und Felder einer Klasse ohne Abschnitt bleiben gemeldet.
  Found := Findings(UnitOf('type'#10'  TZaehler = record'#10'  private'#10'    Wert: Integer;'#10'  public'#10 +
    '    property Stand: Integer read Wert;'#10'  end;'#10'  TListe = class'#10'    Anzahl: Integer;'#10'  end;'#10,
    ''));
  Assert.AreEqual('Feld Wert ohne Präfix F (erwartet: FWert)|Feld Anzahl ohne Präfix F (erwartet: FAnzahl)|',
    Messages(Found));
end;

procedure TNamingRulesTests.ParameterRenamedInDeclarationAndImplementation;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := UnitOf('type'#10'  TKunde = class'#10'    procedure Setzen(const Wert: string; AAlt: Integer);'#10 +
    '  end;'#10, 'procedure TKunde.Setzen(const Wert: string; AAlt: Integer);'#10'begin'#10 +
    '  Writeln(Wert, AAlt);'#10'end;'#10);
  Found := Findings(Source);
  // Nur einmal an der Deklaration.
  Assert.AreEqual('Parameter Wert ohne Präfix A (erwartet: AWert)|', Messages(Found));
  Assert.AreEqual(4, Found[0].Range.StartPos.Line);
  Fixed := ApplyFix(Source, Found[0].Fixes[0]);
  Assert.AreEqual(StringReplace(Source, 'Wert', 'AWert', [rfReplaceAll]), Fixed);
  TRuleAssert.Silent(TNamingPrefixRule.Create, Fixed);
  Assert.AreEqual(0, Integer(Length(Findings(Fixed))));
end;

procedure TNamingRulesTests.ParametersOfStandaloneRoutines;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  // interface-Abschnitt: an der Deklaration; Routine nur in der implementation: dort. Anonyme Methoden und
  // Prozedurtypen auch.
  Source := UnitOf('type'#10'  TRechner = reference to function(Wert: Integer): Integer;'#10 +
    'function Doppelt(Wert: Integer): Integer;'#10, 'function Doppelt(Wert: Integer): Integer;'#10'begin'#10 +
    '  Result := Wert * 2;'#10'end;'#10'function Halb(Zahl: Integer): Integer;'#10'var'#10'  mF: TRechner;'#10 +
    'begin'#10'  mF := function(Teil: Integer): Integer'#10'    begin'#10'      Result := Teil;'#10'    end;'#10 +
    '  Result := Zahl div 2;'#10'end;'#10);
  Found := Findings(Source);
  Assert.AreEqual('Parameter Wert ohne Präfix A (erwartet: AWert)|Parameter Wert ohne Präfix A (erwartet: AWert)|' +
    'Parameter Zahl ohne Präfix A (erwartet: AZahl)|Parameter Teil ohne Präfix A (erwartet: ATeil)|',
    Messages(Found));
  // Doppelt: Deklaration und Implementierung zusammen.
  Fixed := ApplyFix(Source, Found[1].Fixes[0]);
  Assert.Contains(Fixed, 'function Doppelt(AWert: Integer): Integer;'#10'implementation');
  Assert.Contains(Fixed, 'Result := AWert * 2;');
  Assert.Contains(Fixed, 'reference to function(Wert: Integer)', 'der Prozedurtyp ist ein eigener Treffer');
  Fixed := ApplyFix(Source, Found[3].Fixes[0]);
  Assert.Contains(Fixed, 'function(ATeil: Integer): Integer'#10'    begin'#10'      Result := ATeil;');
end;

procedure TNamingRulesTests.ConstantsInRoutineClassAndUnit;
var
  Source, Fixed: string;
  Found: TArray<TRuleFinding>;
begin
  Source := UnitOf('const'#10'  Oeffentlich = 1;'#10'type'#10'  TKunde = class'#10'  private const'#10 +
    '    Grenze = 2;'#10'  private'#10'    FWert: Integer;'#10'  end;'#10'resourcestring'#10'  sTitel = ''T'';'#10,
    'const'#10'  Intern = 3;'#10'procedure P;'#10'const'#10'  Lokal = 4;'#10'begin'#10 +
    '  Writeln(Oeffentlich + Intern + Lokal + TKunde.Grenze);'#10'end;'#10);
  Found := Findings(Source);
  Assert.AreEqual('Konstante Oeffentlich ohne Präfix c (erwartet: cOeffentlich)|' +
    'Konstante Grenze ohne Präfix c (erwartet: cGrenze)|Konstante Intern ohne Präfix c (erwartet: cIntern)|' +
    'Konstante Lokal ohne Präfix c (erwartet: cLokal)|', Messages(Found));
  // interface: andere Units sehen sie.
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  Fixed := ApplyFix(Source, Found[2].Fixes[0]);
  Assert.Contains(Fixed, '  cIntern = 3;');
  Assert.Contains(Fixed, 'Oeffentlich + cIntern + Lokal');
  Fixed := ApplyFix(Source, Found[3].Fixes[0]);
  Assert.Contains(Fixed, '  cLokal = 4;');
  Assert.Contains(Fixed, 'Intern + cLokal + TKunde');
end;

procedure TNamingRulesTests.Exceptions;
var
  Source: string;
  Found: TArray<TRuleFinding>;
begin
  TRuleAssert.Silent(TNamingPrefixRule.Create, '');
  // Formular: Komponenten vor dem ersten Abschnitt, published-Felder; override, message, published-Methode und
  // Ereignis-Handler; Schleifenzähler, globale Variable.
  Source := UnitOf('type'#10'  TMain = class(TForm)'#10'    Button1: TButton;'#10 +
    '    procedure Button1Click(Sender: TObject; var Key: Word);'#10'  published'#10'    Label1: TLabel;'#10 +
    '  private'#10'    FOk: Boolean;'#10'  protected'#10'    procedure WndProc(var Message: TMessage); override;'#10 +
    '    procedure WMSize(var Msg: TWMSize); message WM_SIZE;'#10'  published'#10 +
    '    procedure Ereignis(Wert: Integer);'#10'  end;'#10'var'#10'  Global: Integer;'#10,
    'procedure P;'#10'var'#10'  I: Integer;'#10'begin'#10'  for I := 1 to 2 do ;'#10'  for var J := 1 to 2 do ;'#10 +
    'end;'#10'procedure TMain.Button1Click(Sender: TObject; var Key: Word);'#10'begin'#10'end;'#10 +
    'procedure TMain.WndProc(var Message: TMessage);'#10'begin'#10'end;'#10 +
    'procedure TMain.WMSize(var Msg: TWMSize);'#10'begin'#10'end;'#10 +
    'procedure TMain.Ereignis(Wert: Integer);'#10'begin'#10'end;'#10);
  Found := Findings(Source);
  Assert.AreEqual('', Messages(Found), 'Ausnahmen');
  // ignore: Muster.
  Source := UnitOf('type'#10'  TApi = record'#10'  private'#10'    cbSize: Cardinal;'#10'    dwFlags: Cardinal;'#10 +
    '  end;'#10, '');
  Found := Findings(Source, '{"rules": {"naming-prefix": {"severity": "hint", "ignore": ["cb*", "dw*"]}}}');
  Assert.AreEqual('', Messages(Found));
end;

procedure TNamingRulesTests.InterfaceImplementationsKeepNames;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(UnitOf('type'#10'  IBasis = interface'#10'    procedure Laden(Datei: string);'#10'  end;'#10 +
    '  IDienst = interface(IBasis)'#10'    procedure Melden(Text: string);'#10'  end;'#10 +
    '  TDienst = class(TInterfacedObject, IDienst)'#10'    procedure Laden(Datei: string);'#10 +
    '    procedure Melden(Text: string);'#10'    procedure Eigen(Wert: Integer);'#10'  end;'#10 +
    '  TFremd = class(TInterfacedObject, IUnbekannt)'#10'    procedure Tun(Wert: Integer);'#10'  end;'#10, ''));
  // Die Interfaces selbst und die eigene Methode; die Implementierungen behalten die Namen, und bei einem
  // unbekannten Interface schweigt die Regel.
  Assert.AreEqual('Parameter Datei ohne Präfix A (erwartet: ADatei)|Parameter Text ohne Präfix A (erwartet: AText)|' +
    'Parameter Wert ohne Präfix A (erwartet: AWert)|', Messages(Found));
  Assert.AreEqual(12, Found[2].Range.StartPos.Line);
end;

procedure TNamingRulesTests.NoFixWhenUnsafe;
var
  Found: TArray<TRuleFinding>;
begin
  // with im Rumpf.
  Found := Findings(UnitOf('', 'procedure P(R: TRect);'#10'var'#10'  Left: Integer;'#10'begin'#10 +
    '  with R do'#10'    Left := 1;'#10'end;'#10));
  Assert.AreEqual(2, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual(0, Integer(Length(Found[1].Fixes)));
  // Der neue Name gibt es schon.
  Found := Findings(UnitOf('', 'procedure P;'#10'var'#10'  Wert, mWert: Integer;'#10'begin'#10 +
    '  Wert := mWert;'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
  // Eine lokale Routine deklariert den Namen neu.
  Found := Findings(UnitOf('', 'procedure P;'#10'var'#10'  Wert: Integer;'#10'  procedure Q;'#10'  var'#10 +
    '    Wert: string;'#10'  begin'#10'  end;'#10'begin'#10'  Wert := 1;'#10'end;'#10));
  Assert.AreEqual(2, Integer(Length(Found)));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

procedure TNamingRulesTests.ConfigurationAndProjectFile;
var
  Source: string;
  Context: TRuleContext;
  Found: TArray<TRuleFinding>;
  Issues: TArray<TConfigurationIssue>;
begin
  // Der Parser prüft die Optionen.
  TConfigurationParser.Parse('{"rules": {"naming-prefix": {"local": 1, "field": "F"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.Contains(Issues[0].Message, '"local" muss ein Text sein');
  Source := UnitOf('', 'procedure P(Wert: Integer);'#10'const'#10'  Grenze = 1;'#10'var'#10'  LIndex: Integer;'#10 +
    'begin'#10'end;'#10);
  // Experimentell: ohne Eintrag in atlas.json still.
  Assert.AreEqual(0, Integer(Length(Findings(Source, ''))));
  Assert.AreEqual(3, Integer(Length(Findings(Source))));
  // Optionen: anderes Präfix, leer = Art aus.
  Found := Findings(Source,
    '{"rules": {"naming-prefix": {"severity": "hint", "local": "L", "constant": "", "parameter": "a_"}}}');
  Assert.AreEqual('Parameter Wert ohne Präfix a_ (erwartet: a_Wert)|', Messages(Found));
  // Projektdatei .atlas über den Projektkontext.
  Context := Default(TRuleContext);
  Context.Text := Source;
  Context.Naming.Known[TRuleNamingKind.Local] := True;
  Context.Naming.Prefixes[TRuleNamingKind.Local] := 'L';
  Context.Naming.Known[TRuleNamingKind.Constant] := True;
  Context.Naming.Prefixes[TRuleNamingKind.Constant] := '';
  Found := TRuleAssert.ContextFindings(TNamingPrefixRule.Create, Context, Enabled);
  Assert.AreEqual('Parameter Wert ohne Präfix A (erwartet: AWert)|', Messages(Found));
  // atlas.json hat Vorrang vor der Projektdatei.
  Found := TRuleAssert.ContextFindings(TNamingPrefixRule.Create, Context,
    '{"rules": {"naming-prefix": {"severity": "hint", "local": "m", "parameter": ""}}}');
  Assert.AreEqual('Lokale Variable LIndex ohne Präfix m (erwartet: mLIndex)|', Messages(Found));
end;

procedure TNamingRulesTests.ShadowedNameUsesProjectPrefixes;
var
  Context: TRuleContext;
  Found: TArray<TRuleFinding>;
begin
  Context := Default(TRuleContext);
  Assert.AreEqual('L', NamingPrefixFor(Context, TRuleNamingKind.Local, 'L'));
  Context.Naming.Known[TRuleNamingKind.Local] := True;
  Assert.AreEqual('L', NamingPrefixFor(Context, TRuleNamingKind.Local, 'L'), 'leer: Vorgabe der Regel');
  Context.Naming.Prefixes[TRuleNamingKind.Local] := 'm';
  Assert.AreEqual('m', NamingPrefixFor(Context, TRuleNamingKind.Local, 'L'));
  Context.Text := UnitOf('type'#10'  TKunde = class'#10'  private'#10'    FState: Integer;'#10'  public'#10 +
    '    property State: Integer read FState;'#10'    procedure Zeigen;'#10'  end;'#10,
    'procedure TKunde.Zeigen;'#10'var'#10'  State: Integer;'#10'begin'#10'  State := 1;'#10'end;'#10);
  Found := TRuleAssert.ContextFindings(TShadowedNameRule.Create, Context, '');
  Assert.AreEqual(1, Integer(Length(Found)));
  Assert.AreEqual('In mState umbenennen', Found[0].Fixes[0].Title);
end;


procedure TNamingRulesTests.NewNamesFollowActiveRule;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
  Context: TRuleContext;
  Names: TPascalNamePrefixes;
begin
  Context := Default(TRuleContext);
  // Experimentell und aus: keine Präfixe.
  Names := TRuleEngine.NewNames([TNamingPrefixRule.Create as IRule], TServerSettings.Default, Context);
  Assert.AreEqual('', Names.ConstantPrefix + Names.LocalPrefix + Names.FieldPrefix + Names.ParameterPrefix);
  Assert.AreEqual('NewConstant', Names.Constant('NewConstant'));
  Settings := TConfigurationParser.Parse(Enabled, Issues);
  Names := TRuleEngine.NewNames([TNamingPrefixRule.Create as IRule], Settings, Context);
  Assert.AreEqual('mValue', Names.Local('Value'));
  Assert.AreEqual('FCount', Names.Field('Count'));
  Assert.AreEqual('APreis', Names.Parameter('Preis'));
  Assert.AreEqual('cNewConstant', Names.Constant('NewConstant'));
  Assert.AreEqual('mValue', Names.Local('mValue'), 'trägt das Präfix schon');
  // Optionen der Regel gelten auch für neue Namen.
  Settings := TConfigurationParser.Parse('{"rules": {"naming-prefix": {"severity": "hint", "constant": "k"}}}',
    Issues);
  Names := TRuleEngine.NewNames([TNamingPrefixRule.Create as IRule], Settings, Context);
  Assert.AreEqual('kNewConstant', Names.Constant('NewConstant'));
  Context := Default(TRuleContext);
end;

procedure TNamingRulesTests.FixesFollowNamingRule;
const
  Source = 'unit U;'#10'interface'#10'implementation'#10'function Rabatt(APreis: Double): Double;'#10'begin'#10 +
    '  Result := APreis * 0.93;'#10'end;'#10'end.';

  function FixText(const AConfig: string): string;
  var
    Found: TArray<TRuleFinding>;
    Finding: TRuleFinding;
  begin
    Result := '';
    Found := TRuleAssert.FindingsOfAll([TMagicNumberRule.Create as IRule, TNamingPrefixRule.Create as IRule],
      Source, AConfig);
    for Finding in Found do
      if (Finding.RuleId = 'magic-number') and (Length(Finding.Fixes) > 0) then
        Result := ApplyFix(Source, Finding.Fixes[0]);
  end;

var
  Fixed: string;
begin
  // magic-number meldet mit niedriger Konfidenz.
  Fixed := FixText('{"minConfidence": "low", "rules": {"magic-number": "hint"}}');
  Assert.IsTrue(Pos('NewConstant = 0.93', Fixed) > 0, Fixed);
  Assert.IsFalse(Pos('cNewConstant', Fixed) > 0, 'ohne Namensregel unverändert');
  Fixed := FixText('{"minConfidence": "low", "rules": {"magic-number": "hint", "naming-prefix": "hint"}}');
  Assert.IsTrue(Pos('cNewConstant = 0.93', Fixed) > 0, Fixed);
  Assert.IsTrue(Pos('APreis * cNewConstant', Fixed) > 0, Fixed);
end;

procedure TNamingRulesTests.FixWhenNewNameOnlyElsewhere;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(UnitOf('', 'procedure Q(const ABuf; ACount: Integer);'#10'begin'#10'end;'#10 +
    'procedure P(const Buf; ACount: Integer);'#10'begin'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)), 'ABuf steht nur in Q');
  Assert.AreEqual('In ABuf umbenennen', Found[0].Fixes[0].Title);
  // Ein Nachbarparameter heißt schon so.
  Found := Findings(UnitOf('', 'procedure P(const Buf; ABuf: Integer);'#10'begin'#10'end;'#10));
  Assert.AreEqual(1, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual(0, Integer(Length(Found[0].Fixes)));
end;

initialization
  TDUnitX.RegisterTestFixture(TNamingRulesTests);

end.
