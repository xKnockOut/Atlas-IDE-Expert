unit Atlas.Common.Rules.Builtin.Inlining.Tests;

// Tests der Regel inline-not-expanded (#1017): fehlende Unit (H2443) bei
// Aufruf, Property-Getter und for-in, die korrigierte Form und eine nicht
// eingebettete Routine schweigen; strict private (H2444), inline-Aufrufer mit
// Unit nur im implementation-uses (H2445), direkter und indirekter Zyklus
// (H2456, H2457); Schnellkorrektur; abschaltbar; die Verweise im Index;
// Laufzeit bei vielen Aufrufen und langer uses-Kette (#1220); H2445 auch
// bei inline-Routinen, deren Rumpf auf nichts außerhalb verweist (#1381).
// Fehlalarme aus der Prüfung von Atlas und der RTL: Alias einer Deklaration
// aus System (tkRecord in System.TypInfo, TList<T>.Add), strict private-
// Methoden (TMonitor.Enter), Zyklus bei Rümpfen nur mit eingebauten Typen
// und Intrinsics (THashFNV1a32.GetHashValue).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TInliningRulesTests = class
  public
    [Test]
    procedure MissingUnitIsReported;
    [Test]
    procedure CorrectedUsesAreSilent;
    [Test]
    procedure NotInlineIsSilent;
    [Test]
    procedure PropertyGetterAndForIn;
    [Test]
    procedure QuickFixAddsUnit;
    [Test]
    procedure StrictPrivateMember;
    [Test]
    procedure StrictPrivateInSameUnit;
    [Test]
    procedure InlineCallerWithImplementationUses;
    /// <summary>#1381: Halb verweist auf nichts außerhalb seiner Unit (Cm.H2445); auch dann meldet dcc H2445.
    /// Gegenfälle: nicht inline aufrufende Routine, Unit im interface-uses.</summary>
    [Test]
    procedure InlineCallerWithoutBodyReferences;
    /// <summary>#1381: Wie Cm.H2456 bleibt dcc 13 bei einem Zyklus still, wenn der Rumpf auf nichts außerhalb
    /// verweist (abhängig von der Reihenfolge der Übersetzung, #1383).</summary>
    [Test]
    procedure CycleWithoutBodyReferencesIsSilent;
    /// <summary>Wie System.TypInfo (tkRecord = System.TTypeKind.tkRecord): Ein Alias aus System braucht die
    /// Unit des Alias nicht; ein eigener Wert schon.</summary>
    [Test]
    procedure AliasOfSystemNeedsNoUnit;
    /// <summary>Wie TMonitor.Enter: Der Rumpf ruft eine strict private-Methode, dcc bettet trotzdem ein.
    /// </summary>
    [Test]
    procedure StrictPrivateMethodIsSilent;
    /// <summary>Wie THashFNV1a32.GetHashValue in System.Generics.Defaults: Der Rumpf benutzt nur eingebaute Typen
    /// und Intrinsics, der Zyklus bleibt stumm; ein Verweis auf eine andere Unit meldet ihn weiter.</summary>
    [Test]
    procedure CycleWithBuiltinsOnlyIsSilent;
    [Test]
    procedure CircularUnits;
    [Test]
    procedure SwitchableAndInlineOff;
    [Test]
    procedure IndexKeepsBodyReferences;
    [Test]
    procedure RuleIsRegistered;
    /// <summary>#1220: Tausende Aufrufe einer inline-Routine, deren Unit über eine lange uses-Kette läuft, bleiben
    /// deutlich unter einer Sekunde; die Zyklussuche läuft je Unit nur einmal.</summary>
    [Test]
    [Category('Benchmark')]
    procedure ManyCallsWithLongUsesChainStayFast;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Diagnostics,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Rules.Builtin.Inlining,
  Atlas.Tests.RuleAssert;

const
  UnitListen =
    'unit Werk.Listen;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TListe<T> = class'#10 +
    '  private'#10 +
    '    FAnzahl: Integer;'#10 +
    '  public'#10 +
    '    property Count: Integer read FAnzahl;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  UnitMathe =
    'unit Werk.Mathe;'#10 +
    'interface'#10 +
    'function Mal2(A: Integer): Integer;'#10 +
    'function Halb(A: Integer): Integer; inline;'#10 +
    'implementation'#10 +
    'function Mal2(A: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A * 2;'#10 +
    'end;'#10 +
    'function Halb(A: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := A div 2;'#10 +
    'end;'#10 +
    'end.';

  UnitJson =
    'unit Werk.Json;'#10 +
    'interface'#10 +
    'uses Werk.Listen;'#10 +
    'type'#10 +
    '  TJsonEnum = class'#10 +
    '  public'#10 +
    '    constructor Create(AAnzahl: Integer);'#10 +
    '    function MoveNext: Boolean;'#10 +
    '  end;'#10 +
    '  TJsonFeld = class'#10 +
    '  private'#10 +
    '    FWerte: TListe<Integer>;'#10 +
    '    function GetZahl: Integer; inline;'#10 +
    '  strict private'#10 +
    '    FGeheim: Integer;'#10 +
    '  public'#10 +
    '    function Anzahl: Integer; inline;'#10 +
    '    function Normal: Integer;'#10 +
    '    function Geheim: Integer; inline;'#10 +
    '    function Nochmal: Integer;'#10 +
    '    function GetEnumerator: TJsonEnum; inline;'#10 +
    '    property Zahl: Integer read GetZahl;'#10 +
    '  end;'#10 +
    'function Doppelt(A: Integer): Integer; inline;'#10 +
    'implementation'#10 +
    'uses Werk.Mathe;'#10 +
    'constructor TJsonEnum.Create(AAnzahl: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'function TJsonEnum.MoveNext: Boolean;'#10 +
    'begin'#10 +
    '  Result := False;'#10 +
    'end;'#10 +
    'function TJsonFeld.GetZahl: Integer;'#10 +
    'begin'#10 +
    '  Result := FWerte.Count;'#10 +
    'end;'#10 +
    'function TJsonFeld.Anzahl: Integer;'#10 +
    'var'#10 +
    '  Lokal: Integer;'#10 +
    'begin'#10 +
    '  Lokal := FWerte.Count;'#10 +
    '  Result := Lokal;'#10 +
    'end;'#10 +
    'function TJsonFeld.Normal: Integer;'#10 +
    'begin'#10 +
    '  Result := FWerte.Count;'#10 +
    'end;'#10 +
    'function TJsonFeld.Geheim: Integer;'#10 +
    'begin'#10 +
    '  Result := FGeheim;'#10 +
    'end;'#10 +
    'function TJsonFeld.Nochmal: Integer;'#10 +
    'begin'#10 +
    '  Result := Geheim;'#10 +
    'end;'#10 +
    'function TJsonFeld.GetEnumerator: TJsonEnum;'#10 +
    'begin'#10 +
    '  Result := TJsonEnum.Create(FWerte.Count);'#10 +
    'end;'#10 +
    'function Doppelt(A: Integer): Integer;'#10 +
    'begin'#10 +
    '  Result := Mal2(A);'#10 +
    'end;'#10 +
    'end.';

  // Zyklus: Werk.Kreis verwendet Haupt, Werk.Ring über Werk.Kreis ebenso.
  UnitKreis =
    'unit Werk.Kreis;'#10 +
    'interface'#10 +
    'function Eins: Integer; inline;'#10 +
    'implementation'#10 +
    'uses Haupt;'#10 +
    'function Eins: Integer;'#10 +
    'begin'#10 +
    '  Result := Mal2(1);'#10 +
    'end;'#10 +
    'end.';

  UnitRing =
    'unit Werk.Ring;'#10 +
    'interface'#10 +
    'function Zwei: Integer; inline;'#10 +
    'implementation'#10 +
    'uses Werk.Kreis, Werk.Mathe;'#10 +
    'function Zwei: Integer;'#10 +
    'begin'#10 +
    '  Result := Mal2(1);'#10 +
    'end;'#10 +
    'end.';

function NewIndex: ISymbolIndex;
begin
  Result := TSymbolIndex.Create;
  Result.AddUnit(TIndexExtractor.ExtractText(UnitListen, 'C:\P\Werk.Listen.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitMathe, 'C:\P\Werk.Mathe.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitJson, 'C:\P\Werk.Json.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitKreis, 'C:\P\Werk.Kreis.pas', nil));
  Result.AddUnit(TIndexExtractor.ExtractText(UnitRing, 'C:\P\Werk.Ring.pas', nil));
end;

function Haupt(const AUses, ABody: string): string;
begin
  Result := 'unit Haupt;'#10'interface'#10'uses ' + AUses + ';'#10'implementation'#10 +
    'procedure Lauf(F: TJsonFeld);'#10'var'#10'  X: Integer;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

function Findings(const ASource: string; const AConfig: string = ''): TArray<TRuleFinding>;
begin
  Result := TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, ASource, NewIndex, AConfig, 'Haupt.pas');
end;

function Messages(const AFindings: TArray<TRuleFinding>): string;
var
  Finding: TRuleFinding;
begin
  Result := '';
  for Finding in AFindings do
    Result := Result + Format('%d:%d %s|', [Finding.Range.StartPos.Line, Finding.Range.StartPos.Character,
      Finding.Message]);
end;

{ TInliningRulesTests }

procedure TInliningRulesTests.MissingUnitIsReported;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Haupt('Werk.Json', '  X := F.Anzahl;'#10'  X := Doppelt(X);'#10));
  Assert.AreEqual('8:9 Inline-Funktion TJsonFeld.Anzahl wird nicht eingebettet: Werk.Listen fehlt in uses ' +
    '(wie H2443).|9:7 Inline-Funktion Doppelt wird nicht eingebettet: Werk.Mathe fehlt in uses (wie H2443).|',
    Messages(Found));
  Assert.AreEqual(InlineNotExpandedRuleId, Found[0].RuleId);
  Assert.AreEqual(Ord(TRuleSeverity.Hint), Ord(Found[0].Severity));
  Assert.AreEqual(Ord(TRuleConfidence.High), Ord(Found[0].Confidence));
end;

procedure TInliningRulesTests.CorrectedUsesAreSilent;
begin
  Assert.AreEqual('', Messages(Findings(Haupt('Werk.Json, Werk.Listen, Werk.Mathe',
    '  X := F.Anzahl;'#10'  X := Doppelt(X) + F.Zahl;'#10'  for X in F do;'#10))));
end;

procedure TInliningRulesTests.NotInlineIsSilent;
begin
  // Normal hat denselben Rumpf, ist aber nicht inline; Nochmal ruft Geheim in der eigenen Unit.
  Assert.AreEqual('', Messages(Findings(Haupt('Werk.Json', '  X := F.Normal + F.Nochmal;'#10))));
end;

procedure TInliningRulesTests.PropertyGetterAndForIn;
begin
  Assert.AreEqual('8:9 Inline-Funktion TJsonFeld.GetZahl wird nicht eingebettet: Werk.Listen fehlt in uses ' +
    '(wie H2443).|9:11 Inline-Funktion TJsonFeld.GetEnumerator wird nicht eingebettet: Werk.Listen fehlt in uses ' +
    '(wie H2443).|', Messages(Findings(Haupt('Werk.Json', '  X := F.Zahl;'#10'  for X in F do;'#10))));
end;

procedure TInliningRulesTests.QuickFixAddsUnit;
var
  Found: TArray<TRuleFinding>;
begin
  Found := Findings(Haupt('Werk.Json', '  X := F.Anzahl;'#10));
  Assert.AreEqual(1, Integer(Length(Found)), Messages(Found));
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes)));
  Assert.AreEqual('uses Werk.Listen ergänzen', Found[0].Fixes[0].Title);
  Assert.AreEqual(1, Integer(Length(Found[0].Fixes[0].Edits)));
  Assert.AreEqual(#10#10'uses'#10'  Werk.Listen;', Found[0].Fixes[0].Edits[0].NewText);
  Assert.AreEqual(3, Found[0].Fixes[0].Edits[0].Range.StartPos.Line);
end;

procedure TInliningRulesTests.StrictPrivateMember;
begin
  Assert.AreEqual('8:9 Inline-Funktion TJsonFeld.Geheim wird nicht eingebettet: Zugriff auf TJsonFeld.FGeheim ' +
    '(strict private) ist hier nicht möglich (wie H2444).|',
    Messages(Findings(Haupt('Werk.Json', '  X := F.Geheim;'#10))));
end;

procedure TInliningRulesTests.StrictPrivateInSameUnit;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TZaehler = class'#10 +
    '  strict private'#10 +
    '    FStand: Integer;'#10 +
    '  public'#10 +
    '    function Stand: Integer; inline;'#10 +
    '    function Doppelt: Integer;'#10 +
    '  end;'#10 +
    'function Abfrage(Z: TZaehler): Integer;'#10 +
    'implementation'#10 +
    'function TZaehler.Stand: Integer;'#10 +
    'begin'#10 +
    '  Result := FStand;'#10 +
    'end;'#10 +
    'function TZaehler.Doppelt: Integer;'#10 +
    'begin'#10 +
    '  Result := Stand * 2;'#10 +
    'end;'#10 +
    'function Abfrage(Z: TZaehler): Integer;'#10 +
    'begin'#10 +
    '  Result := Z.Stand;'#10 +
    'end;'#10 +
    'end.';
  Expected = '22:14 Inline-Funktion TZaehler.Stand wird nicht eingebettet: Zugriff auf TZaehler.FStand ' +
    '(strict private) ist hier nicht möglich (wie H2444).|';
begin
  // Auch in derselben Unit ist strict private außerhalb der Klasse unsichtbar; die Methode der Klasse
  // selbst (Doppelt) bettet ein. Das gilt mit und ohne Projektindex.
  Assert.AreEqual(Expected, Messages(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, Source, nil, '',
    'Haupt.pas')));
  Assert.AreEqual(Expected, Messages(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, Source,
    TSymbolIndex.Create, '', 'Haupt.pas')));
  // Ohne strict ist das Feld in der Unit sichtbar.
  Assert.AreEqual('', Messages(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create,
    ReplaceStr(Source, 'strict private', 'private'), nil, '', 'Haupt.pas')));
end;

procedure TInliningRulesTests.InlineCallerWithImplementationUses;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'function Vier: Integer; inline;'#10 +
    'implementation'#10 +
    'uses Werk.Json, Werk.Mathe;'#10 +
    'function Vier: Integer;'#10 +
    'begin'#10 +
    '  Result := Doppelt(2);'#10 +
    'end;'#10 +
    'function Acht: Integer;'#10 +
    'begin'#10 +
    '  Result := Doppelt(4);'#10 +
    'end;'#10 +
    'end.';
begin
  Assert.AreEqual('7:12 Inline-Funktion Doppelt wird nicht eingebettet: Werk.Json steht nur im uses des ' +
    'implementation-Teils, und die aufrufende Routine ist selbst inline (wie H2445).|',
    Messages(Findings(Source)));
end;

procedure TInliningRulesTests.InlineCallerWithoutBodyReferences;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'function Vier: Integer; inline;'#10 +
    'implementation'#10 +
    'uses Werk.Mathe;'#10 +
    'function Vier: Integer;'#10 +
    'begin'#10 +
    '  Result := Halb(8);'#10 +
    'end;'#10 +
    'function Acht: Integer;'#10 +
    'begin'#10 +
    '  Result := Halb(16);'#10 +
    'end;'#10 +
    'end.';
begin
  Assert.AreEqual('7:12 Inline-Funktion Halb wird nicht eingebettet: Werk.Mathe steht nur im uses des ' +
    'implementation-Teils, und die aufrufende Routine ist selbst inline (wie H2445).|',
    Messages(Findings(Source)));
  Assert.AreEqual('', Messages(Findings(ReplaceStr(ReplaceStr(Source, 'uses Werk.Mathe;'#10, ''),
    'interface'#10, 'interface'#10'uses Werk.Mathe;'#10))));
end;

procedure TInliningRulesTests.CycleWithoutBodyReferencesIsSilent;
const
  cZirkel =
    'unit Werk.Zirkel;'#10 +
    'interface'#10 +
    'function Drei: Integer; inline;'#10 +
    'implementation'#10 +
    'uses Haupt;'#10 +
    'function Drei: Integer;'#10 +
    'begin'#10 +
    '  Result := 3;'#10 +
    'end;'#10 +
    'end.';
  cSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Werk.Zirkel;'#10 +
    'function Rechne: Integer;'#10 +
    'begin'#10 +
    '  Result := Drei;'#10 +
    'end;'#10 +
    'end.';
var
  mIndex: ISymbolIndex;
begin
  mIndex := NewIndex;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cZirkel, 'C:\P\Werk.Zirkel.pas', nil));
  Assert.AreEqual('', Messages(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, cSource, mIndex, '',
    'Haupt.pas')));
end;

procedure TInliningRulesTests.AliasOfSystemNeedsNoUnit;
const
  cArten =
    'unit Werk.Arten;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TArt = System.TTypeKind;'#10 +
    'const'#10 +
    '  akRecord = System.TTypeKind.tkRecord;'#10 +
    '  akEigen = 7;'#10 +
    'implementation'#10 +
    'end.';
  cStapel =
    'unit Werk.Stapel;'#10 +
    'interface'#10 +
    'uses Werk.Arten;'#10 +
    'type'#10 +
    '  TStapel<T> = class'#10 +
    '  public'#10 +
    '    function Art: Boolean; inline;'#10 +
    '    function Eigen: Integer; inline;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'function TStapel<T>.Art: Boolean;'#10 +
    'var'#10 +
    '  A: TArt;'#10 +
    'begin'#10 +
    '  A := GetTypeKind(T);'#10 +
    '  Result := A in [akRecord];'#10 +
    'end;'#10 +
    'function TStapel<T>.Eigen: Integer;'#10 +
    'begin'#10 +
    '  Result := akEigen;'#10 +
    'end;'#10 +
    'end.';
  cSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Werk.Stapel;'#10 +
    'procedure Lauf(S: TStapel<Integer>);'#10 +
    'var'#10 +
    '  X: Integer;'#10 +
    'begin'#10 +
    '  if S.Art then'#10 +
    '    X := S.Eigen;'#10 +
    'end;'#10 +
    'end.';
var
  mIndex: ISymbolIndex;
begin
  mIndex := NewIndex;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cArten, 'C:\P\Werk.Arten.pas', nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText(cStapel, 'C:\P\Werk.Stapel.pas', nil));
  Assert.AreEqual('9:11 Inline-Funktion TStapel.Eigen wird nicht eingebettet: Werk.Arten fehlt in uses ' +
    '(wie H2443).|', Messages(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, cSource, mIndex, '',
    'Haupt.pas')));
end;

procedure TInliningRulesTests.StrictPrivateMethodIsSilent;
const
  cWaechter =
    'unit Werk.Waechter;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TWaechter = record'#10 +
    '  strict private'#10 +
    '    FStand: Integer;'#10 +
    '    class procedure Pruefe; static; inline;'#10 +
    '  public'#10 +
    '    class procedure Betrete; static; inline;'#10 +
    '    function Stand: Integer; inline;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'class procedure TWaechter.Pruefe;'#10 +
    'begin'#10 +
    'end;'#10 +
    'class procedure TWaechter.Betrete;'#10 +
    'begin'#10 +
    '  Pruefe;'#10 +
    'end;'#10 +
    'function TWaechter.Stand: Integer;'#10 +
    'begin'#10 +
    '  Result := FStand;'#10 +
    'end;'#10 +
    'end.';
  cSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Werk.Waechter;'#10 +
    'function Lauf(W: TWaechter): Integer;'#10 +
    'begin'#10 +
    '  TWaechter.Betrete;'#10 +
    '  Result := W.Stand;'#10 +
    'end;'#10 +
    'end.';
var
  mIndex: ISymbolIndex;
begin
  mIndex := NewIndex;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cWaechter, 'C:\P\Werk.Waechter.pas', nil));
  Assert.AreEqual('7:14 Inline-Funktion TWaechter.Stand wird nicht eingebettet: Zugriff auf TWaechter.FStand ' +
    '(strict private) ist hier nicht möglich (wie H2444).|',
    Messages(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, cSource, mIndex, '', 'Haupt.pas')));
end;

procedure TInliningRulesTests.CycleWithBuiltinsOnlyIsSilent;
const
  cZirkel =
    'unit Werk.Zirkel;'#10 +
    'interface'#10 +
    'function Drei: Integer; inline;'#10 +
    'function Vier: Integer; inline;'#10 +
    'implementation'#10 +
    'uses Haupt, Werk.Mathe;'#10 +
    'function Drei: Integer;'#10 +
    'begin'#10 +
    '  Result := Integer(SizeOf(Cardinal)) + Length(''abc'');'#10 +
    'end;'#10 +
    'function Vier: Integer;'#10 +
    'begin'#10 +
    '  Result := Mal2(2);'#10 +
    'end;'#10 +
    'end.';
  cSource =
    'unit Haupt;'#10 +
    'interface'#10 +
    'implementation'#10 +
    'uses Werk.Zirkel;'#10 +
    'function Rechne: Integer;'#10 +
    'begin'#10 +
    '  Result := Drei + Vier;'#10 +
    'end;'#10 +
    'end.';
var
  mIndex: ISymbolIndex;
begin
  mIndex := NewIndex;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cZirkel, 'C:\P\Werk.Zirkel.pas', nil));
  Assert.AreEqual('6:19 Inline-Funktion Vier wird nicht eingebettet: Werk.Zirkel verwendet die übersetzte Unit ' +
    'Haupt (wie H2456).|', Messages(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, cSource, mIndex, '',
    'Haupt.pas')));
end;

procedure TInliningRulesTests.CircularUnits;
const
  Source =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Werk.Kreis, Werk.Ring, Werk.Mathe;'#10 +
    'implementation'#10 +
    'procedure Lauf;'#10 +
    'var'#10 +
    '  X: Integer;'#10 +
    'begin'#10 +
    '  X := Eins + Zwei;'#10 +
    'end;'#10 +
    'end.';
begin
  Assert.AreEqual('8:7 Inline-Funktion Eins wird nicht eingebettet: Werk.Kreis verwendet die übersetzte Unit ' +
    'Haupt (wie H2456).|8:14 Inline-Funktion Zwei wird nicht eingebettet: Werk.Ring verwendet die übersetzte ' +
    'Unit Haupt indirekt über Werk.Kreis (wie H2457).|', Messages(Findings(Source)));
end;

procedure TInliningRulesTests.SwitchableAndInlineOff;
var
  Source: string;
begin
  Source := Haupt('Werk.Json', '  X := F.Anzahl;'#10);
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"inline-not-expanded": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source, '{"rules": {"group:compiler": "off"}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(Source,
    '{"rules": {"inline-not-expanded": {"severity": "hint", "exclude": ["Haupt.pas"]}}}'))));
  Assert.AreEqual(0, Integer(Length(Findings(ReplaceStr(Source, 'implementation'#10,
    'implementation'#10'{$INLINE OFF}'#10)))));
  // Ohne Index kennt die Regel Werk.Json nicht und schweigt.
  Assert.AreEqual(0, Integer(Length(TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create, Source, nil, '',
    'Haupt.pas'))));
end;

procedure TInliningRulesTests.IndexKeepsBodyReferences;
var
  UnitIndex: TUnitIndex;
  Symbol: TIndexSymbol;
  Refs: string;
begin
  UnitIndex := TIndexExtractor.ExtractText(UnitJson, 'C:\P\Werk.Json.pas', nil);
  Refs := '';
  for Symbol in UnitIndex.Symbols do
    if Symbol.InInterface and (Symbol.InlineRefs <> nil) then
      Refs := Refs + Symbol.QualifiedName + '=' + String.Join(',', Symbol.InlineRefs) + '|';
  // Lokale Namen, Result, eigene Typen und Mitglieder ohne weiteren Zugriff fehlen; Normal und Nochmal sind
  // nicht inline. Eingebaute Typen (Integer) löst erst die Regel auf.
  Assert.AreEqual('TJsonFeld.GetZahl=:TListe<Integer>|TJsonFeld.Anzahl=:Integer,:TListe<Integer>|' +
    'TJsonFeld.Geheim=!FGeheim|TJsonFeld.GetEnumerator=:TListe<Integer>|Doppelt=Mal2|', Refs);
  // Ohne Verweise bleibt die inline-Routine erkennbar (#1381); Mal2 ist nicht inline.
  UnitIndex := TIndexExtractor.ExtractText(UnitMathe, 'C:\P\Werk.Mathe.pas', nil);
  Refs := '';
  for Symbol in UnitIndex.Symbols do
    if Symbol.InInterface and (Symbol.InlineRefs <> nil) then
      Refs := Refs + Symbol.QualifiedName + '=' + IntToStr(Length(Symbol.InlineRefs)) + ':' +
        String.Join(',', Symbol.InlineRefs) + '|';
  Assert.AreEqual('Halb=1:|', Refs);
end;

procedure TInliningRulesTests.RuleIsRegistered;
var
  Rule: IRule;
  Found: Boolean;
begin
  Found := False;
  for Rule in BuiltinRules do
    if Rule.Descriptor.Id = InlineNotExpandedRuleId then
      Found := True;
  Assert.IsTrue(Found);
end;

procedure TInliningRulesTests.ManyCallsWithLongUsesChainStayFast;
const
  cChainLength = 350;
  cRoutines = 300;
  cCallsPerRoutine = 10;
var
  mIndex: ISymbolIndex;
  mStep, mCall: Integer;
  mNext, mBody: string;
  mBuilder: TStringBuilder;
  mWatch: TStopwatch;
  mFound: TArray<TRuleFinding>;
begin
  // cRoutines Routinen mit je cCallsPerRoutine Aufrufen. Werk.Basis.Wert ist inline und braucht Werk.Typen; Werk.Basis verwendet Kette1, die Kette läuft über
  // cChainLength Units und kommt nie bei Haupt an. Haupt hat alles in uses: Jeder Aufruf durchläuft also alle
  // Prüfungen ohne Meldung, früher jedes Mal mit der vollen Breitensuche über die Kette.
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Werk.Typen;'#10'interface'#10'type'#10 +
    '  TZahl = Integer;'#10'implementation'#10'end.', 'C:\P\Werk.Typen.pas', nil));
  mIndex.AddUnit(TIndexExtractor.ExtractText('unit Werk.Basis;'#10'interface'#10'uses Werk.Typen;'#10 +
    'function Wert(A: Integer): Integer; inline;'#10'implementation'#10'uses Kette1;'#10 +
    'function Wert(A: Integer): Integer;'#10'var'#10'  Z: TZahl;'#10'begin'#10'  Z := A;'#10'  Result := Z;'#10 +
    'end;'#10'end.', 'C:\P\Werk.Basis.pas', nil));
  for mStep := 1 to cChainLength do
  begin
    if mStep < cChainLength then
      mNext := Format('uses Kette%d, Werk.Typen;'#10, [mStep + 1])
    else
      mNext := 'uses Werk.Typen;'#10;
    mIndex.AddUnit(TIndexExtractor.ExtractText(Format('unit Kette%d;'#10'interface'#10'%s' +
      'implementation'#10'end.', [mStep, mNext]), Format('C:\P\Kette%d.pas', [mStep]), nil));
  end;
  mBuilder := TStringBuilder.Create;
  try
    for mStep := 1 to cRoutines do
    begin
      mBuilder.Append(Format('procedure Lauf%d;'#10'var'#10'  X: Integer;'#10'begin'#10'  X := 0;'#10, [mStep]));
      for mCall := 1 to cCallsPerRoutine do
        mBuilder.Append('  X := Wert(X);'#10);
      mBuilder.Append('end;'#10);
    end;
    mBody := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  mWatch := TStopwatch.StartNew;
  mFound := TRuleAssert.IndexFindings(TInlineNotExpandedRule.Create,
    'unit Haupt;'#10'interface'#10'uses Werk.Basis, Werk.Typen;'#10'implementation'#10 + mBody + 'end.',
    mIndex, '', 'Haupt.pas');
  mWatch.Stop;
  System.Writeln(Format('inline-not-expanded: %d Aufrufe, uses-Kette %d Units: %d ms',
    [cRoutines * cCallsPerRoutine, cChainLength, mWatch.ElapsedMilliseconds]));
  Assert.AreEqual('', Messages(mFound));
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 1000, Format('zu langsam: %d ms', [mWatch.ElapsedMilliseconds]));
end;

initialization
  TDUnitX.RegisterTestFixture(TInliningRulesTests);

end.
