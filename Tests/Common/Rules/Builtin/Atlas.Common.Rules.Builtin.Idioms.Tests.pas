unit Atlas.Common.Rules.Builtin.Idioms.Tests;

// Tests der Regeln aus Rules.Builtin.Idioms: je Regel das Beispiel aus dem
// Issue, Varianten, stille Fälle, Korrekturen und Einstellungen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIdiomRulesTests = class
  public
    [Test]
    procedure MoneyIssueExample;
    [Test]
    procedure MoneyNames;
    [Test]
    procedure MoneyVariants;
    [Test]
    procedure MoneyFixesAcrossDeclarations;
    [Test]
    procedure MoneyAmbiguousWords;
    [Test]
    procedure MoneySilentCases;
    [Test]
    procedure MoneyOptions;
    [Test]
    procedure ChainIssueExample;
    [Test]
    procedure ChainVariants;
    [Test]
    procedure ChainWithoutFix;
    [Test]
    procedure ChainSilentCases;
    [Test]
    procedure ChainOptions;
    [Test]
    procedure PreferCaseExampleWithFix;
    [Test]
    procedure PreferCaseSilentCases;
    [Test]
    procedure PreferCaseOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin.Idioms,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Tests.RuleAssert;

const
  // Niedrige Konfidenz und Standard aus: erst mit minConfidence low und eingeschalteter Regel sichtbar.
  cMoneyOn = '{"minConfidence": "low", "rules": {"money-as-float": "hint"}}';
  cChainOn = '{"rules": {"string-if-chain": "hint"}}';
  cPreferCaseOn = '{"rules": {"prefer-case": "hint"}}';

function TypeUnit(const ATypes: string): string;
begin
  Result := 'unit Kasse;'#10'interface'#10'type'#10 + ATypes + 'implementation'#10'end.';
end;

function RoutineUnit(const AVars, ABody: string): string;
begin
  Result := 'unit Kasse;'#10'interface'#10'implementation'#10'procedure Buchen;'#10 + AVars + 'begin'#10 + ABody +
    #10'end;'#10'end.';
end;

{ money-as-float }

procedure TIdiomRulesTests.MoneyIssueExample;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := TypeUnit('  TPosition = record'#10'    Menge: Integer;'#10'    Preis: Double;'#10'  end;'#10);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMoneyAsFloatRule.Create, mSource))), 'Standard aus');
  mFindings := TRuleAssert.Findings(TMoneyAsFloatRule.Create, mSource, cMoneyOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Preis ist Double; Currency rechnet Cent-Beträge exakt.', mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(mFindings[0].Confidence));
  Assert.AreEqual(5, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(4, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('Typ in Currency ändern', mFindings[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(TypeUnit('  TPosition = record'#10'    Menge: Integer;'#10'    Preis: Currency;'#10'  end;'#10), mFixed);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMoneyAsFloatRule.Create, mFixed, cMoneyOn))));
end;

procedure TIdiomRulesTests.MoneyNames;
var
  mPatterns, mNames: TArray<string>;
  mName: string;
begin
  Assert.AreEqual('Preis', TMoneyAsFloatRule.HeadOf('GesamtPreis'));
  Assert.AreEqual('Betrag', TMoneyAsFloatRule.HeadOf('ABetrag'));
  Assert.AreEqual('Netto', TMoneyAsFloatRule.HeadOf('FNetto'));
  Assert.AreEqual('AMOUNT', TMoneyAsFloatRule.HeadOf('TOTAL_AMOUNT'));
  Assert.AreEqual('Gewicht', TMoneyAsFloatRule.HeadOf('NettoGewicht'));
  Assert.AreEqual('Summe2', TMoneyAsFloatRule.HeadOf('Summe2'));
  mPatterns := ['Betrag', 'Preis', 'Summe', 'Netto', 'Brutto', 'Steuer', 'Amount', 'Price'];
  mNames := ['Preis', 'GesamtPreis', 'Nettobetrag', 'FNetto', 'Preise', 'Steuern', 'Summen', 'TOTAL_AMOUNT',
    'UnitPrice', 'Prices', 'LBrutto', 'Preis2'];
  for mName in mNames do
  begin
    Assert.IsTrue(TMoneyAsFloatRule.IsMoneyName(mName, mPatterns), mName);
  end;
  mNames := ['Menge', 'NettoGewicht', 'ASteuerSatz', 'Steuersatz', 'PriceFactor', 'Pruefsumme', 'Prüfsumme',
    'Rabattquote', 'BetragAnteil', 'ExchangeRate', 'Preisliste'];
  for mName in mNames do
  begin
    Assert.IsFalse(TMoneyAsFloatRule.IsMoneyName(mName, mPatterns), mName);
  end;
end;

procedure TIdiomRulesTests.MoneyVariants;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  // Lokale Variable, Inline-Variable, Real und Single.
  mSource := RoutineUnit('var'#10'  Summe: Real;'#10'  Anzahl: Integer;'#10,
    '  var Brutto: Single := 0;'#10'  Summe := Brutto;');
  mFindings := TRuleAssert.Findings(TMoneyAsFloatRule.Create, mSource, cMoneyOn);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('Summe ist Real; Currency rechnet Cent-Beträge exakt.', mFindings[0].Message);
  Assert.AreEqual('Brutto ist Single; Currency rechnet Cent-Beträge exakt.', mFindings[1].Message);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[1].Fixes[0].Edits);
  Assert.Contains(mFixed, '  var Brutto: Currency := 0;');
  // Mehrere Namen: jeder Geldname wird gemeldet, die Korrektur nur, wenn alle Geldbeträge sind.
  mFindings := TRuleAssert.Findings(TMoneyAsFloatRule.Create, TypeUnit('  TZeile = record'#10 +
    '    Netto, Brutto: Extended;'#10'    Preis, Gewicht: System.Double;'#10'  end;'#10), cMoneyOn);
  Assert.AreEqual(3, Integer(Length(mFindings)));
  Assert.AreEqual('Brutto ist Extended; Currency rechnet Cent-Beträge exakt.', mFindings[1].Message);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual(1, Integer(Length(mFindings[1].Fixes)));
  Assert.AreEqual(0, Integer(Length(mFindings[2].Fixes)));
  Assert.AreEqual('Preis ist System.Double; Currency rechnet Cent-Beträge exakt.', mFindings[2].Message);
  // Parameter einer Routine nur im implementation-Teil.
  mFindings := TRuleAssert.Findings(TMoneyAsFloatRule.Create, 'unit Kasse;'#10'interface'#10'implementation'#10 +
    'function Rabatt(const APreis: Double; ARabattSatz: Double): Double;'#10'begin'#10 +
    '  Result := APreis * ARabattSatz;'#10'end;'#10'end.', cMoneyOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('APreis ist Double; Currency rechnet Cent-Beträge exakt.', mFindings[0].Message);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes[0].Edits)));
end;

procedure TIdiomRulesTests.MoneyFixesAcrossDeclarations;
const
  cSource = 'unit Kasse;'#10'interface'#10'type'#10'  TKasse = class'#10'  private'#10'    FNetto: Double;'#10 +
    '    FBrutto: Double;'#10'    procedure SetBrutto(const AValue: Double);'#10'  public'#10 +
    '    procedure Buchen(const ABetrag: Double; AMenge: Integer);'#10 +
    '    property Netto: Double read FNetto write FNetto;'#10'    property Brutto: Double read FBrutto write SetBrutto;'#10 +
    '  end;'#10'procedure Ausgeben(ANetto: Double);'#10'implementation'#10 +
    'procedure TKasse.SetBrutto(const AValue: Double);'#10'begin'#10'end;'#10 +
    'procedure TKasse.Buchen(const ABetrag: Double; AMenge: Integer);'#10'begin'#10'end;'#10 +
    'procedure Ausgeben(ANetto: Double);'#10'begin'#10'end;'#10'end.';
var
  mFindings: TArray<TRuleFinding>;
  mFixed: string;
begin
  mFindings := TRuleAssert.Findings(TMoneyAsFloatRule.Create, cSource, cMoneyOn);
  // FNetto, FBrutto, ABetrag, Netto, Brutto, ANetto; die Parameter der Implementierung nicht noch einmal.
  Assert.AreEqual(6, Integer(Length(mFindings)));
  // Feld mit Property, die nur das Feld liest und schreibt: beide ändern.
  Assert.AreEqual('FNetto ist Double; Currency rechnet Cent-Beträge exakt.', mFindings[0].Message);
  mFixed := TChangeSignature.ApplyEdits(cSource, mFindings[0].Fixes[0].Edits);
  Assert.Contains(mFixed, '    FNetto: Currency;');
  Assert.Contains(mFixed, '    property Netto: Currency read FNetto write FNetto;');
  // Feld hinter einem Setter: Setter müsste mitwandern, keine Korrektur.
  Assert.AreEqual('FBrutto ist Double; Currency rechnet Cent-Beträge exakt.', mFindings[1].Message);
  Assert.AreEqual(0, Integer(Length(mFindings[1].Fixes)));
  // Parameter der Methode: Deklaration und Implementierung.
  Assert.AreEqual('ABetrag ist Double; Currency rechnet Cent-Beträge exakt.', mFindings[2].Message);
  mFixed := TChangeSignature.ApplyEdits(cSource, mFindings[2].Fixes[0].Edits);
  Assert.Contains(mFixed, '    procedure Buchen(const ABetrag: Currency; AMenge: Integer);');
  Assert.Contains(mFixed, 'procedure TKasse.Buchen(const ABetrag: Currency; AMenge: Integer);');
  // Property über das Feld.
  Assert.AreEqual('Netto ist Double; Currency rechnet Cent-Beträge exakt.', mFindings[3].Message);
  Assert.AreEqual(2, Integer(Length(mFindings[3].Fixes[0].Edits)));
  Assert.AreEqual(0, Integer(Length(mFindings[4].Fixes)));
  // Routine im interface-Teil: beide Köpfe.
  Assert.AreEqual('ANetto ist Double; Currency rechnet Cent-Beträge exakt.', mFindings[5].Message);
  mFixed := TChangeSignature.ApplyEdits(cSource, mFindings[5].Fixes[0].Edits);
  Assert.Contains(mFixed, 'procedure Ausgeben(ANetto: Currency);'#10'implementation');
  Assert.Contains(mFixed, 'procedure Ausgeben(ANetto: Currency);'#10'begin');
end;

procedure TIdiomRulesTests.MoneyAmbiguousWords;
const
  cColorUnit = 'unit Farben;'#10'interface'#10'type'#10'  TFarbe = record'#10 +
    '    class function Aufhellen(AFarbe: Cardinal; AAmount: Double): Cardinal; static;'#10'  end;'#10 +
    'implementation'#10'class function TFarbe.Aufhellen(AFarbe: Cardinal; AAmount: Double): Cardinal;'#10 +
    'var'#10'  Summe: Double;'#10'begin'#10'  Summe := AAmount * 255;'#10'  Result := AFarbe + Round(Summe);'#10'end;'#10 +
    'end.';
var
  mFindings: TArray<TRuleFinding>;
  mPatterns: TArray<string>;
begin
  mPatterns := ['Betrag', 'Preis', 'Summe', 'Netto', 'Brutto', 'Steuer', 'Amount', 'Price'];
  Assert.IsTrue(TMoneyAsFloatRule.IsAmbiguousName('AAmount', mPatterns));
  Assert.IsTrue(TMoneyAsFloatRule.IsAmbiguousName('Gesamtsumme', mPatterns));
  Assert.IsFalse(TMoneyAsFloatRule.IsAmbiguousName('Preis', mPatterns));
  // Farbanteil und Summe von Messwerten: ohne Geldbezug still, auch mit checkRound.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMoneyAsFloatRule.Create, cColorUnit,
    '{"minConfidence": "low", "rules": {"money-as-float": {"severity": "hint", "checkRound": true}}}'))));
  // Mit Geldbezug im Typ (Currency, Rabatt) bzw. in der Routine (Euro).
  mFindings := TRuleAssert.Findings(TMoneyAsFloatRule.Create, TypeUnit('  TZahlung = record'#10 +
    '    Amount: Double;'#10'    Rabatt: Integer;'#10'  end;'#10'  TRechnung = record'#10'    Summe: Double;'#10 +
    '    Porto: Currency;'#10'  end;'#10), cMoneyOn);
  Assert.AreEqual(2, Integer(Length(mFindings)));
  Assert.AreEqual('Amount ist Double; Currency rechnet Cent-Beträge exakt.', mFindings[0].Message);
  Assert.AreEqual('Summe ist Double; Currency rechnet Cent-Beträge exakt.', mFindings[1].Message);
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMoneyAsFloatRule.Create,
    RoutineUnit('var'#10'  Summe: Double;'#10, '  Summe := 0;'#10'  Anzeigen(Summe, InEuro);'),
    cMoneyOn))));
end;

procedure TIdiomRulesTests.MoneySilentCases;
begin
  // Currency, Integer, Nicht-Geldnamen, Sätze und Faktoren, Funktionsergebnis.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMoneyAsFloatRule.Create, TypeUnit('  TPosition = record'#10 +
    '    Preis: Currency;'#10'    Betrag: Int64;'#10'    Gewicht: Double;'#10'    SteuerSatz: Double;'#10 +
    '    PreisFaktor: Single;'#10'    NettoGewicht: Double;'#10'    function Brutto: Double;'#10'  end;'#10),
    cMoneyOn))));
  // Ohne checkRound bleibt Round still.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMoneyAsFloatRule.Create,
    RoutineUnit('var'#10'  Preis: Currency;'#10, '  Writeln(Round(Preis));'), cMoneyOn))));
end;

procedure TIdiomRulesTests.MoneyOptions;
var
  mSource: string;
  mFindings: TArray<TRuleFinding>;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSource := RoutineUnit('var'#10'  Preis: Double;'#10'  Kosten: Double;'#10, '  Preis := Kosten;');
  mFindings := TRuleAssert.Findings(TMoneyAsFloatRule.Create, mSource,
    '{"minConfidence": "low", "rules": {"money-as-float": {"severity": "hint", "namePatterns": ["Kosten"]}}}');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Kosten ist Double; Currency rechnet Cent-Beträge exakt.', mFindings[0].Message);
  // checkRound: Round mit einem Geldbetrag im Argument, auch Currency und in Ausdrücken.
  mFindings := TRuleAssert.Findings(TMoneyAsFloatRule.Create, RoutineUnit('var'#10'  Preis: Currency;'#10 +
    '  Anzahl: Integer;'#10, '  Anzahl := Round(Preis * 100);'#10'  Anzahl := Round(Anzahl / 2);'),
    '{"minConfidence": "low", "rules": {"money-as-float": {"severity": "hint", "checkRound": true}}}');
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Round rundet Preis auf die nächste gerade Zahl (2,5 wird 2); Geldbeträge kaufmännisch runden, ' +
    'z. B. mit SimpleRoundTo.', mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleConfidence.Low), Ord(mFindings[0].Confidence));
  // off und exclude.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMoneyAsFloatRule.Create, mSource,
    '{"minConfidence": "low", "rules": {"money-as-float": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TMoneyAsFloatRule.Create, mSource,
    '{"minConfidence": "low", "rules": {"money-as-float": {"severity": "hint", "exclude": ["Kasse/*"]}}}',
    'Kasse/Kasse.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TMoneyAsFloatRule.Create, mSource, cMoneyOn,
    'Kasse/Kasse.pas'))));
  // Der Parser prüft die Arten der Optionen.
  TConfigurationParser.Parse('{"rules": {"money-as-float": {"namePatterns": "Preis", "checkRound": "ja"}}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.AreEqual('"namePatterns" muss eine Liste von Texten sein', mIssues[0].Message);
  Assert.AreEqual('"checkRound" muss true oder false sein', mIssues[1].Message);
  mIssues := nil;
end;

{ string-if-chain }

function ChainUnit(const ABody: string): string;
begin
  Result := 'unit Werkzeug;'#10'interface'#10'implementation'#10'uses'#10'  System.SysUtils;'#10 +
    'procedure Ausfuehren(const Befehl: string);'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

const
  cIssueChain = '  if Befehl = ''neu'' then Neu'#10'  else if Befehl = ''oeffnen'' then Oeffnen'#10 +
    '  else if Befehl = ''speichern'' then Speichern'#10'  else if Befehl = ''beenden'' then Beenden;';

procedure TIdiomRulesTests.ChainIssueExample;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := ChainUnit(cIssueChain);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringIfChainRule.Create, mSource))), 'Standard aus');
  mFindings := TRuleAssert.Findings(TStringIfChainRule.Create, mSource, cChainOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Vier Vergleiche desselben Strings; case IndexStr(Befehl, [...]) ist kürzer.', mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(mFindings[0].Confidence));
  Assert.AreEqual(7, mFindings[0].Range.StartPos.Line);
  Assert.AreEqual(2, mFindings[0].Range.StartPos.Character);
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('In case IndexStr(…) umwandeln', mFindings[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(ChainUnit('  case IndexStr(Befehl, [''neu'', ''oeffnen'', ''speichern'', ''beenden'']) of'#10 +
    '    0: Neu;'#10'    1: Oeffnen;'#10'    2: Speichern;'#10'    3: Beenden;'#10'  end;').Replace(
    '  System.SysUtils;', '  System.SysUtils,'#10'  System.StrUtils;'), mFixed);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringIfChainRule.Create, mFixed, cChainOn))));
end;

procedure TIdiomRulesTests.ChainVariants;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  // SameText mit or, umgedrehter Vergleich, Block als Zweig und Rest als else.
  mSource := ChainUnit('  if SameText(Befehl, ''neu'') or SameText(Befehl, ''new'') then'#10'    Neu'#10 +
    '  else if SameText(''oeffnen'', Befehl) then'#10'  begin'#10'    Laden;'#10'    Zeigen;'#10'  end'#10 +
    '  else if (SameText(Befehl, ''ende'')) then'#10'    Beenden'#10'  else'#10'    Fehler(Befehl);');
  mFindings := TRuleAssert.Findings(TStringIfChainRule.Create, mSource, cChainOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Vier Vergleiche desselben Strings; case IndexText(Befehl, [...]) ist kürzer.', mFindings[0].Message);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(ChainUnit('  case IndexText(Befehl, [''neu'', ''new'', ''oeffnen'', ''ende'']) of'#10 +
    '    0, 1: Neu;'#10'    2:'#10'      begin'#10'        Laden;'#10'        Zeigen;'#10'      end;'#10 +
    '    3: Beenden;'#10 +
    '  else'#10'    Fehler(Befehl);'#10'  end;').Replace('  System.SysUtils;', '  System.SysUtils,'#10'  System.StrUtils;'),
    mFixed);
  // Feld eines Objekts als String; die Kette beginnt erst im else-Zweig.
  mSource := ChainUnit('  if Bereit then'#10'    Starten'#10'  else if Edit1.Text = ''a'' then A'#10 +
    '  else if Edit1.Text = ''b'' then B'#10'  else if Edit1.Text = ''c'' then C'#10 +
    '  else if Edit1.Text = ''d'' then D'#10'  else if Edit1.Text = ''e'' then E;');
  mFindings := TRuleAssert.Findings(TStringIfChainRule.Create, mSource, cChainOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Fünf Vergleiche desselben Strings; case IndexStr(Edit1.Text, [...]) ist kürzer.',
    mFindings[0].Message);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.Contains(mFixed, '  else case IndexStr(Edit1.Text, [''a'', ''b'', ''c'', ''d'', ''e'']) of'#10'    0: A;');
  Assert.AreEqual('Zwölf', TStringIfChainRule.CountWord(12));
  Assert.AreEqual('13', TStringIfChainRule.CountWord(13));
end;

procedure TIdiomRulesTests.ChainWithoutFix;
var
  mFindings: TArray<TRuleFinding>;
begin
  // Gemischte Groß-/Kleinschreibung, doppeltes Literal, Kommentar zwischen den Zweigen.
  mFindings := TRuleAssert.Findings(TStringIfChainRule.Create, ChainUnit('  if Befehl = ''a'' then A'#10 +
    '  else if SameText(Befehl, ''b'') then B'#10'  else if Befehl = ''c'' then C'#10 +
    '  else if Befehl = ''d'' then D;'), cChainOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  mFindings := TRuleAssert.Findings(TStringIfChainRule.Create, ChainUnit('  if Befehl = ''a'' then A'#10 +
    '  else if Befehl = ''b'' then B'#10'  else if Befehl = ''a'' then C'#10'  else if Befehl = ''d'' then D;'),
    cChainOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
  mFindings := TRuleAssert.Findings(TStringIfChainRule.Create, ChainUnit('  if Befehl = ''a'' then A'#10 +
    '  // b kommt bald weg'#10'  else if Befehl = ''b'' then B'#10'  else if Befehl = ''c'' then C'#10 +
    '  else if Befehl = ''d'' then D;'), cChainOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual(0, Integer(Length(mFindings[0].Fixes)));
end;

procedure TIdiomRulesTests.ChainSilentCases;
begin
  // Drei Vergleiche, verschiedene Strings, and, Aufruf statt Variable, Zahlen, ein einzelnes if mit or.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringIfChainRule.Create, ChainUnit(
    '  if Befehl = ''a'' then A'#10'  else if Befehl = ''b'' then B'#10'  else if Befehl = ''c'' then C;'#10 +
    '  if Befehl = ''a'' then A'#10'  else if Name = ''b'' then B'#10'  else if Befehl = ''c'' then C'#10 +
    '  else if Name = ''d'' then D;'#10 +
    '  if (Befehl = ''a'') and Bereit then A'#10'  else if Befehl = ''b'' then B'#10'  else if Befehl = ''c'' then C'#10 +
    '  else if Befehl = ''d'' then D;'#10 +
    '  if Lesen() = ''a'' then A'#10'  else if Lesen() = ''b'' then B'#10'  else if Lesen() = ''c'' then C'#10 +
    '  else if Lesen() = ''d'' then D;'#10 +
    '  if Zahl = 1 then A'#10'  else if Zahl = 2 then B'#10'  else if Zahl = 3 then C'#10'  else if Zahl = 4 then D;'#10 +
    '  if (Befehl = ''a'') or (Befehl = ''b'') or (Befehl = ''c'') or (Befehl = ''d'') then A'#10 +
    '  else if Bereit then B;'),
    cChainOn))));
  // Ein Zweig nur unter {$IFDEF}: zählt nicht mit, drei bleiben.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringIfChainRule.Create, ChainUnit(
    '  if Befehl = ''a'' then A'#10'{$IFDEF DEBUG}'#10'  else if Befehl = ''b'' then B'#10'{$ENDIF}'#10 +
    '  else if Befehl = ''c'' then C'#10'  else if Befehl = ''d'' then D;'), cChainOn))));
end;

procedure TIdiomRulesTests.ChainOptions;
var
  mSource: string;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSource := ChainUnit('  if Befehl = ''a'' then A'#10'  else if Befehl = ''b'' then B'#10'  else if Befehl = ''c'' then C;');
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringIfChainRule.Create, mSource, cChainOn))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TStringIfChainRule.Create, mSource,
    '{"rules": {"string-if-chain": {"severity": "hint", "min": 3}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringIfChainRule.Create, ChainUnit(cIssueChain),
    '{"rules": {"string-if-chain": {"severity": "hint", "min": 5}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringIfChainRule.Create, ChainUnit(cIssueChain),
    '{"rules": {"string-if-chain": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TStringIfChainRule.Create, ChainUnit(cIssueChain),
    '{"rules": {"string-if-chain": {"severity": "hint", "exclude": ["Werkzeug"]}}}', 'Quellen/Werkzeug.pas'))));
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TStringIfChainRule.Create, ChainUnit(cIssueChain), cChainOn,
    'Quellen/Werkzeug.pas'))));
  TConfigurationParser.Parse('{"rules": {"string-if-chain": {"min": 1}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('"min" muss eine ganze Zahl ab 2 sein', mIssues[0].Message);
  mIssues := nil;
end;

{ prefer-case }

function KindUnit(const ABody: string): string;
begin
  Result := 'unit Werkzeug;'#10'interface'#10'implementation'#10'procedure Neu;'#10'begin'#10'end;'#10 +
    'procedure Ausfuehren(Kind: Integer);'#10'var'#10'  S: string;'#10'begin'#10 + ABody + #10'end;'#10'end.';
end;

const
  cKindChain = '  if Kind = 1 then Neu'#10'  else if (Kind = 2) or (Kind = 3) then Neu'#10 +
    '  else if (Kind >= 4) and (Kind <= 6) then Neu'#10'  else Kind := 0;';

procedure TIdiomRulesTests.PreferCaseExampleWithFix;
var
  mSource, mFixed: string;
  mFindings: TArray<TRuleFinding>;
begin
  mSource := KindUnit(cKindChain);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPreferCaseRule.Create, mSource))), 'Standard aus');
  mFindings := TRuleAssert.Findings(TPreferCaseRule.Create, mSource, cPreferCaseOn);
  Assert.AreEqual(1, Integer(Length(mFindings)));
  Assert.AreEqual('Vier Zweige vergleichen denselben Ausdruck mit Konstanten; als case ist die Kette kürzer.',
    mFindings[0].Message);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(mFindings[0].Severity));
  Assert.AreEqual(1, Integer(Length(mFindings[0].Fixes)));
  Assert.AreEqual('In case umwandeln', mFindings[0].Fixes[0].Title);
  mFixed := TChangeSignature.ApplyEdits(mSource, mFindings[0].Fixes[0].Edits);
  Assert.AreEqual(KindUnit('  case Kind of'#10'    1: Neu;'#10'    2, 3: Neu;'#10'    4..6: Neu;'#10'  else'#10 +
    '    Kind := 0;'#10'  end;'), mFixed);
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPreferCaseRule.Create, mFixed, cPreferCaseOn))));
end;

procedure TIdiomRulesTests.PreferCaseSilentCases;
begin
  // Drei Zweige, Strings, verschiedene Ausdrücke, Direktive in der Kette.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPreferCaseRule.Create, KindUnit(
    '  if Kind = 1 then Neu'#10'  else if Kind = 2 then Neu'#10'  else Neu;'#10 +
    '  if S = ''a'' then Neu'#10'  else if S = ''b'' then Neu'#10'  else if S = ''c'' then Neu'#10'  else Neu;'#10 +
    '  if Kind = 1 then Neu'#10'  else if Length(S) = 2 then Neu'#10'  else if Kind = 3 then Neu'#10'  else Neu;'#10 +
    '  if Kind = 1 then Neu'#10'{$IFDEF DEBUG}'#10'  else if Kind = 2 then Neu'#10'{$ENDIF}'#10 +
    '  else if Kind = 3 then Neu'#10'  else Neu;'), cPreferCaseOn))));
end;

procedure TIdiomRulesTests.PreferCaseOptions;
var
  mSource: string;
begin
  mSource := KindUnit('  if Kind = 1 then Neu'#10'  else if Kind = 2 then Neu'#10'  else Neu;');
  Assert.AreEqual(1, Integer(Length(TRuleAssert.Findings(TPreferCaseRule.Create, mSource,
    '{"rules": {"prefer-case": {"severity": "hint", "min": 3}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPreferCaseRule.Create, KindUnit(cKindChain),
    '{"rules": {"prefer-case": {"severity": "hint", "min": 5}}}'))));
  Assert.AreEqual(0, Integer(Length(TRuleAssert.Findings(TPreferCaseRule.Create, KindUnit(cKindChain),
    '{"rules": {"prefer-case": "off"}}'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TIdiomRulesTests);

end.
